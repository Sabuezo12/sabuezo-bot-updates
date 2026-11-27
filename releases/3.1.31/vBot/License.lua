-- RinoBot license: the player's key, this PC's identity and a session token from
-- the Navi server (wss, message {type="auth"}). It activates, renews every hour
-- and hands the token to Navi.
-- Gate (change 239): decided once, at load. Without a license confirmed on this
-- PC in the last 3 days, every macro created after this file stays idle until a
-- key is accepted; then they start at once. A license that fails while playing
-- never stops anything: it only takes effect at the next load.
RinoLicense = RinoLicense or {}
local L = RinoLicense
if type(L.dispose) == "function" then pcall(L.dispose) end
L.generation = (L.generation or 0) + 1
local generation = L.generation

-- Same server and public token as Navi's default (GameBotServerTransport).
local SERVER_URL = "wss://sabuezo-botserver-render.onrender.com/?token=Slegna"
-- Render's free plan can take ~50 s to wake up.
local SOCKET_TIMEOUT_S = 60
local REPLY_TIMEOUT_MS = 60000
local OFFLINE_GRACE_S = 3 * 86400
-- Answers that make the next load stay idle (unreachable server never does).
local DEFINITIVE = {invalid_key = true, suspended = true, revoked = true, expired = true,
  device_limit = true, device_not_bound = true}
local GATE_TEXT = {
  no_key = "RinoBot necesita una licencia. Pega la clave que te dio Sabuezo.",
  new_key = "Esta clave aun no se comprobo en este PC.",
  grace = "No se pudo comprobar la licencia en 3 dias.",
  invalid_key = "Esa clave no existe. Revisa que este bien escrita.",
  suspended = "Tu clave esta suspendida.",
  revoked = "Esta clave fue anulada.",
  expired = "Tu clave vencio.",
  device_limit = "Esta clave ya esta activada en otro PC.",
  device_not_bound = "Este PC no esta activado con esa clave. Vuelve a escribirla.",
}
local SEND_FALLBACK_MS = 3000
local PROBE_TIMEOUT_MS = 20000
local RETRY_MS = {60000, 120000, 300000, 600000}
local DENIED_RETRY_MS = 30 * 60000
local KEY_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

local core = modules.corelib or modules.game_bot or {}
local nativeIO, nativeOS = core.io or io, core.os or os
local platform = core.g_platform or g_platform
local resources = core.g_resources or g_resources

local previous = type(L.state) == "table" and L.state or nil
local S = {
  status = "starting", -- starting | no_key | checking | active | offline | denied
  code = nil,
  message = "Comprobando la licencia...",
  key = nil,
  confirmed = false,   -- this PC was activated with this key at least once
  device = nil,
  token = nil,
  expiresAt = 0,       -- server time, seconds
  offset = 0,          -- server time minus local time, seconds
  config = {},
  attempts = 0,
  requestId = previous and previous.requestId or 0,
}
-- A reload keeps a valid token, so Navi does not lose it while we re-check.
if previous and type(previous.token) == "string" then
  S.token, S.expiresAt, S.offset, S.config = previous.token, previous.expiresAt or 0, previous.offset or 0, previous.config or {}
end
L.state = S
-- One table for the whole session: the macro wrapper reads it on every tick.
L.gate = L.gate or {blocked = false, reason = ""}
local sockets = {}

local function alive() return L.generation == generation end
local function nowSeconds() return os.time() + (S.offset or 0) end

local function later(ms, fn)
  if type(schedule) ~= "function" then return end
  schedule(ms, function() if alive() then fn() end end)
end

local function log(level, message, detail)
  pcall(function()
    if RinoConsole and RinoConsole.valid() then RinoConsole.log(level, "Licencia", message, detail) end
  end)
end

-- ------------------------------------------------------------------ files
local function read(path)
  if not path or not nativeIO or type(nativeIO.open) ~= "function" then return nil end
  local ok, value = pcall(function()
    local f = nativeIO.open(path, "rb")
    if not f then return nil end
    local s = f:read(4096)
    f:close()
    return s
  end)
  return ok and value or nil
end

local function write(path, text)
  if not path or not nativeIO or type(nativeIO.open) ~= "function" then return false end
  local ok, result = pcall(function()
    local f = nativeIO.open(path, "wb")
    if not f then return false end
    local done = f:write(text)
    f:close()
    return done ~= nil
  end)
  return ok and result == true
end

local function lines(text)
  local out = {}
  for line in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do out[#out + 1] = (line:gsub("\r$", "")) end
  return out
end

local function trim(text) return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- Bot folder (per client) and %LOCALAPPDATA%\RinoBot\License (shared by every client on this PC).
local function privateDir()
  local ok, path = pcall(function()
    local configName = modules.game_bot.contentsPanel.config:getCurrentOption().text
    local rel = "/bot/" .. configName .. "/_helper_license"
    pcall(resources.makeDir, rel)
    return (resources.getWriteDir():gsub("[/\\]+$", "")) .. rel
  end)
  return ok and path or nil
end

local function sharedDir()
  if not nativeOS or type(nativeOS.getenv) ~= "function" then return nil end
  local ok, base = pcall(nativeOS.getenv, "LOCALAPPDATA")
  if not ok or type(base) ~= "string" or base == "" then return nil end
  return base:gsub("\\", "/") .. "/RinoBot/License"
end

local function keyFiles()
  local out = {}
  local shared, private = sharedDir(), privateDir()
  if shared then out[#out + 1] = shared .. "/clave.txt" end
  if private then out[#out + 1] = private .. "/clave.txt" end
  return out
end

-- RINO-XXXXX-XXXXX-XXXXX-XXXXX, typed with or without dashes or prefix.
function L.normalizeKey(text)
  local body = tostring(text or ""):upper():gsub("[^0-9A-Z]", "")
  if #body == 24 and body:sub(1, 4) == "RINO" then body = body:sub(5) end
  body = body:gsub("O", "0"):gsub("[IL]", "1")
  if #body ~= 20 then return nil end
  for i = 1, #body do
    if not KEY_ALPHABET:find(body:sub(i, i), 1, true) then return nil end
  end
  return "RINO-" .. body:sub(1, 5) .. "-" .. body:sub(6, 10) .. "-" .. body:sub(11, 15) .. "-" .. body:sub(16, 20)
end

local function loadKey()
  for _, path in ipairs(keyFiles()) do
    local content = lines(read(path))
    local key = L.normalizeKey(content[1])
    if key then return key, content[2] == "ok" end
  end
  return nil, false
end

local function saveKey(key, confirmed)
  local text = key .. "\n" .. (confirmed and "ok" or "") .. "\n"
  local saved = false
  for _, path in ipairs(keyFiles()) do saved = write(path, text) or saved end
  return saved
end

-- Last server answer for a key: "ok" with its time, or a refusal code.
local function sessionFiles()
  local out = {}
  for _, path in ipairs(keyFiles()) do out[#out + 1] = (path:gsub("clave%.txt$", "sesion.txt")) end
  return out
end

local function loadSession(key)
  local best
  for _, path in ipairs(sessionFiles()) do
    local content = lines(read(path))
    local at = tonumber(content[3])
    if content[1] == key and content[2] and content[2] ~= "" and at and (not best or at > best.at) then
      best = {state = content[2], at = at}
    end
  end
  return best
end

local function saveSession(key, state)
  if not key then return end
  local text = key .. "\n" .. state .. "\n" .. tostring(os.time()) .. "\n"
  for _, path in ipairs(sessionFiles()) do write(path, text) end
end

-- ---------------------------------------------------------------- this PC
-- A small VBScript (the AFK companion starts its own the same way) reads
-- MachineGuid (64-bit registry view) and the system volume serial.
local function vbsString(value) return '"' .. tostring(value):gsub('"', '""') .. '"' end

local function probeScript(nonce, out, shared)
  return table.concat({
    'On Error Resume Next',
    'Set fs=CreateObject("Scripting.FileSystemObject")',
    'Set sh=CreateObject("WScript.Shell")',
    'Sub MakeDir(p)',
    ' If Not fs.FolderExists(p) Then MakeDir fs.GetParentFolderName(p): fs.CreateFolder p',
    'End Sub',
    'nonce=' .. vbsString(nonce),
    'out=Replace(' .. vbsString(out) .. ',"/","\\")',
    'guid=""',
    'guid=sh.RegRead("HKLM\\SOFTWARE\\Microsoft\\Cryptography\\MachineGuid")',
    'If Err.Number<>0 Or guid="" Then',
    ' Err.Clear',
    ' guid=""',
    ' Set ctx=CreateObject("WbemScripting.SWbemNamedValueSet")',
    ' ctx.Add "__ProviderArchitecture",64',
    ' Set svc=CreateObject("WbemScripting.SWbemLocator").ConnectServer(".","root\\default","","",,,,ctx)',
    ' Set reg=svc.Get("StdRegProv")',
    ' Set inp=reg.Methods_("GetStringValue").InParameters.SpawnInstance_()',
    ' inp.hDefKey=&H80000002',
    ' inp.sSubKeyName="SOFTWARE\\Microsoft\\Cryptography"',
    ' inp.sValueName="MachineGuid"',
    ' Set res=reg.ExecMethod_("GetStringValue",inp,,ctx)',
    ' guid=res.sValue',
    'End If',
    'Err.Clear',
    'serial=""',
    'serial=Hex(fs.GetDrive(fs.GetDriveName(sh.ExpandEnvironmentStrings("%SystemDrive%")&"\\")).SerialNumber)',
    -- The folder Lua reads the key from; Lua cannot create folders itself.
    shared and ('MakeDir Replace(' .. vbsString(shared) .. ',"/","\\")') or "' sin carpeta compartida",
    'Err.Clear',
    'Set f=fs.CreateTextFile(out&".tmp",True)',
    'f.WriteLine nonce',
    'f.WriteLine guid',
    'f.WriteLine serial',
    'f.Close',
    'If fs.FileExists(out) Then fs.DeleteFile out,True',
    'fs.MoveFile out&".tmp",out',
  }, "\r\n") .. "\r\n"
end

-- Plain environment values, only when the script cannot run at all.
local function fallbackDevice()
  if not nativeOS or type(nativeOS.getenv) ~= "function" then return nil end
  local parts = {}
  for _, name in ipairs({"COMPUTERNAME", "USERNAME", "PROCESSOR_IDENTIFIER", "NUMBER_OF_PROCESSORS"}) do
    local ok, value = pcall(nativeOS.getenv, name)
    parts[#parts + 1] = ok and tostring(value or "") or ""
  end
  local text = table.concat(parts, "|")
  if #text < 12 then return nil end
  return "e1|" .. text:lower()
end

local function probeDevice(done)
  local dir = privateDir()
  local saved = dir and lines(read(dir .. "/pc-ultimo.txt"))[1]
  local function finish(device, source)
    if device then
      if dir and device:sub(1, 3) == "w1|" then write(dir .. "/pc-ultimo.txt", device .. "\n") end
      return done(device, source)
    end
    if saved and saved ~= "" then return done(saved, "guardado") end
    return done(fallbackDevice(), "entorno")
  end
  if not dir or not platform or type(platform.openUrl) ~= "function" then return finish(nil) end
  local nonce = tostring(os.time()) .. "-" .. tostring({}):gsub("[^%w]", "")
  local out = dir .. "/pc.txt"
  local script = dir .. "/pc.vbs"
  if not write(script, probeScript(nonce, out, sharedDir())) then return finish(nil) end
  if not pcall(platform.openUrl, script) then return finish(nil) end
  local started = os.time()
  local function poll()
    local content = lines(read(out))
    if content[1] == nonce then
      local guid = trim(content[2]):lower()
      if #guid >= 8 then return finish("w1|" .. guid .. "|" .. trim(content[3]):upper(), "windows") end
      return finish(nil)
    end
    if (os.time() - started) * 1000 >= PROBE_TIMEOUT_MS then return finish(nil) end
    later(500, poll)
  end
  later(500, poll)
end

-- ------------------------------------------------------------------ server
local function version()
  local value = HelperClient and HelperClient.coreVersion
  return tostring(value or "?"):sub(1, 32)
end

local function request(action, done)
  local http = HTTP
  if type(http) ~= "table" or type(http.WebSocketJSON) ~= "function" then return done(nil, "sin WebSocket") end
  S.requestId = S.requestId + 1
  local id = S.requestId
  local message = {type = "auth", id = id, action = action, key = S.key, device = S.device, version = version()}
  local socket, finished, sent = nil, false, false
  local function finish(reply, reason)
    if finished then return end
    finished = true
    if socket then
      sockets[socket] = nil
      pcall(function() socket.close() end)
    end
    if alive() then done(reply, reason) end
  end
  local function send()
    if sent or finished or not socket then return end
    sent = true
    if not pcall(function() socket.send(message) end) then finish(nil, "no se pudo enviar") end
  end
  local ok, result = pcall(http.WebSocketJSON, SERVER_URL, {
    onOpen = function() send() end,
    onMessage = function(msg)
      if type(msg) == "string" and json and json.decode then
        local decoded, value = pcall(json.decode, msg)
        msg = decoded and value or nil
      end
      if type(msg) == "table" and msg.type == "auth" and tonumber(msg.id) == id then finish(msg) end
    end,
    onClose = function() finish(nil, "conexion cerrada") end,
    onError = function() finish(nil, "error de conexion") end,
  }, SOCKET_TIMEOUT_S)
  if not ok or type(result) ~= "table" then return finish(nil, "no se pudo conectar") end
  socket = result
  sockets[socket] = true
  -- Some clients never call onOpen; send anyway after a short wait.
  later(SEND_FALLBACK_MS, send)
  later(REPLY_TIMEOUT_MS, function() finish(nil, "sin respuesta") end)
end

local function describe(config)
  local parts = {}
  if config.user then parts[#parts + 1] = tostring(config.user) end
  if config.keyHint then parts[#parts + 1] = "clave ..." .. tostring(config.keyHint) end
  if tonumber(config.keyExpiresAt) then
    local ok, date = pcall(os.date, "%d/%m/%Y", tonumber(config.keyExpiresAt) - (S.offset or 0))
    parts[#parts + 1] = ok and type(date) == "string" and ("vence " .. date) or "con vencimiento"
  end
  return table.concat(parts, ", ")
end

local check
local function schedulePending(ms)
  S.retryAt = os.time() + math.floor(ms / 1000)
  later(ms, function()
    if S.retryAt and os.time() >= S.retryAt - 1 then check() end
  end)
end

local function unblock()
  if not L.gate.blocked then return end
  L.gate.blocked, L.gate.reason = false, ""
  log("info", "Licencia activa: el bot ya funciona.")
end

local function apply(action, reply, reason)
  if reply and reply.ok == true and type(reply.token) == "string" then
    saveSession(S.key, "ok")
    unblock()
    local wasActive = S.status == "active"
    S.token = reply.token
    S.expiresAt = tonumber(reply.expiresAt) or 0
    S.offset = (tonumber(reply.serverTime) or os.time()) - os.time()
    S.config = type(reply.config) == "table" and reply.config or {}
    S.status, S.code, S.attempts = "active", "ok", 0
    S.message = "Activa: " .. describe(S.config)
    if not S.confirmed then
      S.confirmed = true
      saveKey(S.key, true)
    end
    if not wasActive or action == "activate" then log("info", S.message) end
    if type(S.config.notice) == "string" and S.config.notice ~= "" then log("info", S.config.notice) end
    local renew = tonumber(S.config.renewSeconds) or 3600
    schedulePending(math.max(300, renew) * 1000)
    return
  end
  if reply and reply.code ~= "unavailable" and reply.code ~= "rate_limited" then
    -- The server said no: the token is dropped, macros keep running until the next load.
    S.token, S.expiresAt = nil, 0
    S.status, S.code = "denied", tostring(reply.code or "error")
    S.message = tostring(reply.message or "La licencia no es valida.")
    if DEFINITIVE[S.code] then
      saveSession(S.key, S.code)
      if not L.gate.blocked then
        log("warn", S.message, "El bot sigue funcionando hasta la proxima vez que se cargue.")
      else
        log("warn", S.message)
      end
    else
      log("warn", S.message)
    end
    if S.code == "suspended" or S.code == "expired" then schedulePending(DENIED_RETRY_MS) end
    return
  end
  -- No answer, or the server cannot check now: keep the last token while it lasts.
  S.attempts = S.attempts + 1
  local valid = S.token and S.expiresAt > nowSeconds()
  S.status = valid and "active" or "offline"
  S.code = reply and reply.code or "offline"
  S.message = valid and ("Activa sin conexion: " .. describe(S.config))
    or ("No se pudo comprobar la licencia (" .. tostring(reply and reply.message or reason or "sin respuesta") .. ").")
  if S.attempts == 1 then log(valid and "info" or "warn", S.message) end
  schedulePending(RETRY_MS[math.min(S.attempts, #RETRY_MS)])
end

check = function()
  S.retryAt = nil
  if not S.key then
    S.status, S.message = "no_key", "Sin clave. Abre Ajustes > Licencia y pega tu clave."
    return
  end
  if not S.device then
    S.status, S.message = "offline", "No se pudo identificar este PC."
    log("warn", S.message)
    return
  end
  if S.status ~= "active" then S.status, S.message = "checking", "Comprobando la licencia..." end
  local action = S.confirmed and "verify" or "activate"
  request(action, function(reply, reason) apply(action, reply, reason) end)
end

-- ------------------------------------------------------------------ public
function L.token()
  if S.token and S.expiresAt > nowSeconds() + 30 then return S.token end
  return nil
end

function L.status()
  return {status = S.status, code = S.code, message = S.message, config = S.config,
    hasKey = S.key ~= nil, expiresAt = S.expiresAt, blocked = L.gate.blocked, reason = L.gate.reason}
end

function L.activate(text)
  local key = L.normalizeKey(text)
  if not key then
    log("warn", "Esa clave no tiene el formato RINO-XXXXX-XXXXX-XXXXX-XXXXX.")
    return false
  end
  if key ~= S.key then S.token, S.expiresAt = nil, 0 end
  -- Typing the key is the only way to bind this PC ("activate"); the automatic
  -- checks only "verify" a PC that is already bound.
  S.key, S.confirmed = key, false
  saveKey(key, false)
  S.status, S.message, S.attempts = "checking", "Activando la clave...", 0
  log("info", "Activando la clave ..." .. key:sub(-4))
  if S.device then check() end
  return true
end

function L.open()
  local status = L.status()
  -- Blocked and nothing tried yet: say why the bot is idle.
  local text = (status.blocked and status.code == nil and status.status ~= "checking") and status.reason or status.message
  local options = {
    title = "Licencia de RinoBot",
    description = tostring(text),
    multiline = false,
  }
  local ok = pcall(UI.EditorWindow, S.key or "", options, function(text)
    if trim(text) ~= "" then L.activate(text) end
  end)
  if not ok then log("warn", "No se pudo abrir la ventana de la licencia.") end
  return ok
end

function L.dispose()
  for socket in pairs(sockets) do pcall(function() socket.close() end) end
  sockets = {}
end

-- ------------------------------------------------------------------- start
if Helper and type(Helper.modules) == "table" and Helper.modules.licencia then
  Helper.modules.licencia.available = true
end

S.key, S.confirmed = loadKey()
if not S.key then
  S.status, S.message = "no_key", "Sin clave. Abre Ajustes > Licencia y pega tu clave."
end

-- The gate is decided here, once. Only an accepted key lifts it during the session.
local function gateReason()
  if not S.key then return "no_key" end
  local session = loadSession(S.key)
  if not session then return "new_key" end
  if session.state ~= "ok" then return DEFINITIVE[session.state] and session.state or "new_key" end
  if os.time() - session.at > OFFLINE_GRACE_S then return "grace" end
  return nil
end
local reason = gateReason()
L.gate.blocked = reason ~= nil
L.gate.reason = reason and GATE_TEXT[reason] or ""

-- Every macro created after this file waits for the license (the Updater and the
-- modules before it keep working). Tail call: the client keeps naming the module
-- that created each macro in its "Slow macro" warning.
-- The bot sandbox has no select() or unpack(): arguments go by position. The
-- client's macro(timeout, name, hotkey, callback, parent) reads them by position,
-- so trailing nils are the same as missing arguments.
if not L.macroWrapped and type(macro) == "function" then
  L.macroWrapped = true
  local innerMacro = macro
  macro = function(a1, a2, a3, a4, a5, a6, a7, a8)
    local args = {a1, a2, a3, a4, a5, a6, a7, a8}
    for i = 1, 8 do
      local callback = args[i]
      if type(callback) == "function" then
        args[i] = function(...)
          if L.gate.blocked then return end
          return callback(...)
        end
        break
      end
    end
    return innerMacro(args[1], args[2], args[3], args[4], args[5], args[6], args[7], args[8])
  end
end

if L.gate.blocked then
  log("warn", "Bot detenido: " .. L.gate.reason, "Abre Ajustes > Licencia y pega tu clave.")
  -- Open the key window once the Helper is up (it loads last).
  later(2500, function()
    if not L.gate.blocked then return end
    local helper = Helper
    if helper and type(helper.openModule) == "function" and helper.modules and helper.modules.licencia then
      if pcall(helper.openModule, "licencia") then return end
    end
    L.open()
  end)
  local function remind()
    if not L.gate.blocked then return end
    log("warn", "Bot detenido: " .. L.gate.reason, "Abre Ajustes > Licencia y pega tu clave.")
    later(10 * 60000, remind)
  end
  later(10 * 60000, remind)
end

probeDevice(function(device, source)
  S.device, S.deviceSource = device, source
  if S.key then check() end
end)
