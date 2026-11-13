setDefaultTab('Tools')
-- Reconect: if the connection drops, it tries to log in again with the same character, through the client's own
-- login (client_entergame) and the account the client remembers. The bot never reads, asks for or stores the
-- password. The decisions live in reconnect_engine.lua; this file is the game access and the panel.
--
-- What the clients this runs on taught it:
--   * The bot's context stops when the game ends, so a bot macro does not tick while offline. The retries run on
--     the client's own scheduleEvent, started when the connection drops. The bot environment does not export
--     scheduleEvent, but the tables of the client's modules fall back to the client's global environment, so it
--     is reached through them. Everything the offline path uses is captured below as locals, because the
--     environment of a stopped context may no longer resolve globals.
--   * The character list the client shows after a drop may have nothing selected; CharacterList.doLogin needs a
--     selected row, so the bot selects the character that was playing before asking for the login.
--   * The bot's storage is per profile and is not always saved when the game ends, so the ON/OFF switch lives in
--     the client's own settings (g_settings): one switch for every character, kept across logins.
--   * Every event goes to a timeline file that survives reloads (the next load reads it and keeps its tail), so
--     a test can be read afterwards however many times the bot was reloaded.
local pcall, type, pairs, ipairs, tostring, tonumber = pcall, type, pairs, ipairs, tostring, tonumber
local os, table, string, math = os, table, string, math
local g_game, g_ui, g_settings, g_resources, modules, configDir = g_game, g_ui, g_settings, g_resources, modules, configDir
local RinoConsole, HelperReconnectEngine, reload = RinoConsole, HelperReconnectEngine, reload

local SETTING = 'helperReconnectEnabled' -- NOT rinoAutoReconnectEnabled: the loader resets that retired key
local HISTORY_LINES = 80
local FIRST_LIST_POLL_MS = 125
local FIRST_LIST_POLLS = 12
local RELOG_FINISH_DELAY_MS = 200

storage.helperReconnect = type(storage.helperReconnect) == 'table' and storage.helperReconnect or {}
local config = storage.helperReconnect
local shared = modules and modules.game_bot

local previous = shared and shared.rinoReconnectService
if type(previous) == 'table' and type(previous.shutdown) == 'function' then pcall(previous.shutdown) end
local service = {generation = (type(previous) == 'table' and tonumber(previous.generation) or 0) + 1, dead = false, hooks = {}, wrapped = {}}
service.relogPending = type(previous) == 'table' and previous.relogPending == true
if shared then shared.rinoReconnectService = service end

local function call(fn, ...)
  if type(fn) ~= 'function' then return nil end
  local ok, value = pcall(fn, ...)
  if ok then return value end
end

local function entergame() return modules and modules.client_entergame end

-- The ON/OFF switch, kept in the client's settings. The bot's storage value is only the first-run fallback.
local function savedEnabled()
  if type(g_settings) ~= 'table' or type(g_settings.getBoolean) ~= 'function' then return nil end
  if type(g_settings.exists) == 'function' then
    local ok, present = pcall(g_settings.exists, SETTING)
    if ok and present ~= true then return nil end
  end
  local ok, value = pcall(g_settings.getBoolean, SETTING, false)
  if ok and type(value) == 'boolean' then return value end
end
local function saveEnabled(value)
  if type(g_settings) ~= 'table' then return end
  if type(g_settings.set) == 'function' then pcall(g_settings.set, SETTING, value == true) end
  if type(g_settings.save) == 'function' then pcall(g_settings.save) end
end
do
  local stored = savedEnabled()
  if stored ~= nil then config.enabled = stored
  elseif config.enabled == true then saveEnabled(true) end -- first run with the old per-profile value
end

-- A client function the bot environment may not export (scheduleEvent, removeEvent): the bot's own global when
-- there is one, else the same name read from a client module table. Returns the function and where it came from.
local function clientFunction(name, own)
  if type(own) == 'function' then return own, 'bot' end
  if type(modules) ~= 'table' then return nil, 'ninguno' end
  for _, key in ipairs({'client_entergame', 'game_bot', 'game_interface', 'client_topmenu'}) do
    local ok, fn = pcall(function() local module = modules[key]; return module and module[name] end)
    if ok and type(fn) == 'function' then return fn, 'modulo ' .. key end
  end
  return nil, 'ninguno'
end
local schedule, scheduleSource = clientFunction('scheduleEvent', scheduleEvent)
local unschedule = clientFunction('removeEvent', removeEvent)

-- Names of the functions a table offers (so the report says what this client has).
local function functionNames(tableValue)
  local names = {}
  if type(tableValue) ~= 'table' then return names end
  for name, value in pairs(tableValue) do
    if type(name) == 'string' and type(value) == 'function' then names[#names + 1] = name end
  end
  table.sort(names)
  return names
end

local function yes(value) return value and 'si' or 'no' end

-- The character that was playing: it is what gets selected in the client's list before logging in.
local function rememberCharacter()
  local name = g_game and call(g_game.getCharacterName)
  if type(name) ~= 'string' or name == '' then
    local character = g_game and call(g_game.getLocalPlayer)
    name = character and call(function() return character:getName() end)
  end
  if type(name) == 'string' and name ~= '' then config.lastCharacter = name end
  return config.lastCharacter
end

-- The client can retain the selected row even while the list window is hidden.
local function findCharacterRow()
  local wanted = tostring(config.lastCharacter or ''):lower()
  if wanted == '' then return nil end
  local okRoot, root = pcall(function() return g_ui and g_ui.getRootWidget() end)
  if not okRoot or root == nil then return nil end
  local queue, head, visited = {root}, 1, 0
  while head <= #queue and visited < 3000 do
    local widget = queue[head]
    head = head + 1
    visited = visited + 1
    local okName, name = pcall(function() return widget.characterName end)
    if okName and type(name) == 'string' and name:lower() == wanted then return widget end
    local okKids, kids = pcall(function() return widget:getChildren() end)
    if okKids and type(kids) == 'table' then
      for _, kid in ipairs(kids) do queue[#queue + 1] = kid end
    end
  end
end

-- The report file and its history. Written with the locals captured above, so it also works on a timer after
-- the bot's context has stopped.
local function reportPaths()
  local base = type(configDir) == 'string' and configDir:gsub('\\', '/'):gsub('/+$', '')
  if not base or not base:match('^/bot/[^/]+$') or base:find('..', 1, true) then return nil end
  return base .. '/_diagnostics/reconnect.txt', base .. '/_diagnostics'
end
local function writeFile(text)
  local path, dir = reportPaths()
  if not path or type(g_resources) ~= 'table' or type(g_resources.writeFileContents) ~= 'function' then return false end
  if type(g_resources.makeDir) == 'function' then pcall(g_resources.makeDir, dir) end
  return pcall(g_resources.writeFileContents, path, text)
end
-- The lines under "Eventos:" of the file the previous load left (capped): the history the new report keeps.
local function readHistory()
  local path = reportPaths()
  if not path or type(g_resources) ~= 'table' or type(g_resources.fileExists) ~= 'function' or type(g_resources.readFileContents) ~= 'function' then return {} end
  local okExists, exists = pcall(g_resources.fileExists, path)
  if not okExists or exists ~= true then return {} end
  local ok, text = pcall(g_resources.readFileContents, path)
  if not ok or type(text) ~= 'string' or #text > 65536 then return {} end
  text = text:gsub('\r', '')
  local from = text:find('\nEventos:\n', 1, true)
  if not from then return {} end
  local lines = {}
  for line in (text:sub(from + #'\nEventos:\n') .. '\n'):gmatch('([^\n]*)\n') do
    if line ~= '' and #lines < HISTORY_LINES then lines[#lines + 1] = line end
  end
  return lines
end
service.history = readHistory()

local engine
local function writeReport()
  local eg = entergame()
  local lines = {'RECONECT (generacion ' .. service.generation .. ')'}
  lines[#lines + 1] = 'Temporizadores: scheduleEvent ' .. scheduleSource .. ', removeEvent ' .. yes(type(unschedule) == 'function') ..
    ', macro ' .. yes(type(macro) == 'function') .. ' | al caerse: ' .. (type(schedule) == 'function' and 'cadena propia de scheduleEvent'
    or 'SOLO macro (si el bot se detiene desconectado no habra quien reintente)')
  lines[#lines + 1] = 'Interruptor guardado en los ajustes del cliente (' .. SETTING .. '): ' .. (savedEnabled() == nil and 'sin dato' or yes(savedEnabled()))
  lines[#lines + 1] = 'g_game: isOnline ' .. yes(g_game and type(g_game.isOnline) == 'function') .. ', safeLogout ' .. yes(g_game and type(g_game.safeLogout) == 'function') ..
    ', forceLogout ' .. yes(g_game and type(g_game.forceLogout) == 'function') .. ', logout ' .. yes(g_game and type(g_game.logout) == 'function') ..
    ', getCharacterName ' .. yes(g_game and type(g_game.getCharacterName) == 'function')
  lines[#lines + 1] = 'client_entergame: ' .. yes(type(eg) == 'table')
  if type(eg) == 'table' then
    lines[#lines + 1] = 'EnterGame: ' .. (type(eg.EnterGame) == 'table' and table.concat(functionNames(eg.EnterGame), ', ') or 'no existe')
    lines[#lines + 1] = 'CharacterList: ' .. (type(eg.CharacterList) == 'table' and table.concat(functionNames(eg.CharacterList), ', ') or 'no existe')
  end
  lines[#lines + 1] = 'Personaje que jugaba: ' .. tostring(config.lastCharacter or '(sin datos)')
  local hooks, wrapped = {}, {}
  for event in pairs(service.hooks) do hooks[#hooks + 1] = event end
  table.sort(hooks)
  for _, item in ipairs(service.wrapped) do wrapped[#wrapped + 1] = item.name end
  lines[#lines + 1] = 'Eventos escuchados: ' .. (#hooks > 0 and table.concat(hooks, ', ') or 'ninguno') .. ' | salida voluntaria vigilada en: ' .. (#wrapped > 0 and table.concat(wrapped, ', ') or 'ninguna')
  lines[#lines + 1] = 'Estado: ' .. (engine and engine.status().message or '?') .. ' | activado ' .. yes(config.enabled == true)
  lines[#lines + 1] = ''
  lines[#lines + 1] = 'Eventos:'
  local count = 0
  -- newest first: this load's events, then what earlier loads left
  for index = #(engine and engine.trace or {}), 1, -1 do
    local entry = engine.trace[index]
    lines[#lines + 1] = os.date('%H:%M:%S', entry.at) .. '  [g' .. service.generation .. '] ' .. entry.text
    count = count + 1
  end
  for _, line in ipairs(service.history) do
    if count >= HISTORY_LINES then break end
    lines[#lines + 1] = line
    count = count + 1
  end
  writeFile(table.concat(lines, '\n'))
end

local function log(message)
  if RinoConsole and type(RinoConsole.log) == 'function' then pcall(RinoConsole.log, 'action', 'Reconect', message) end
  writeReport()
end

-- Logging in again. Both ways ask the client to use what it already has; neither passes a password.
--   CharacterList.doLogin: logs in the character selected in the client's list (the bot selects the last one).
--   EnterGame.doLogin:     runs the client's own login from the start with the remembered account.
local function characterLogin()
  local eg = entergame()
  local list = type(eg) == 'table' and eg.CharacterList
  if type(list) ~= 'table' or type(list.doLogin) ~= 'function' then return nil, 'CharacterList.doLogin no existe' end
  local row = findCharacterRow()
  if not row then return nil, 'el personaje aun no esta en la lista' end
  return list.doLogin, row
end
local function viaCharacterList()
  local login, row = characterLogin()
  if not login then return false, row end
  local name = tostring(config.lastCharacter)
  local focused, result = pcall(function() return row:focus() end)
  if not focused or result == false then return false, 'no se pudo seleccionar ' .. name end
  local ok, err = pcall(login)
  if not ok then return false, 'CharacterList.doLogin fallo: ' .. tostring(err):sub(1, 100) end
  if err == false then return false, 'CharacterList.doLogin no inicio la entrada' end
  return true, 'CharacterList.doLogin, seleccionado ' .. name
end
local function viaEnterGame()
  local eg = entergame()
  local enter = type(eg) == 'table' and eg.EnterGame
  if type(enter) ~= 'table' or type(enter.doLogin) ~= 'function' then return false, 'EnterGame.doLogin no existe' end
  local ok, err = pcall(enter.doLogin)
  if not ok then return false, 'EnterGame.doLogin fallo: ' .. tostring(err):sub(1, 100) end
  if err == false then return false, 'EnterGame.doLogin no inicio la entrada' end
  return true, 'EnterGame.doLogin'
end
local function attempt(n)
  local ok, detail = viaCharacterList()
  if ok or engine.mode ~= 'waiting' or (n == 1 and type(schedule) == 'function') then return ok, detail end
  local accountOk, accountDetail = viaEnterGame()
  if accountOk then return true, accountDetail end
  return false, detail .. '; ' .. accountDetail
end

local function isOnline()
  return call(g_game and g_game.isOnline) == true
end

local nativeConfigName = type(configDir) == 'string' and configDir:gsub('\\', '/'):match('([^/]+)/?$')

local function finishRelog()
  local eg = entergame()
  local list = type(eg) == 'table' and eg.CharacterList
  if type(list) == 'table' then
    call(list.destroyLoadBox)
    if call(list.isVisible) == true then call(list.hide, true) end
  end

  -- Native refresh reads the existing settings. Only ask for it when the selected bot is still ON
  -- but its executor has not created any tabs after the normal login callbacks had time to run.
  if not nativeConfigName or not shared or type(reload) ~= 'function' then return end
  local shouldRefresh = call(function()
    local panel = shared.contentsPanel
    local option = panel.config:getCurrentOption()
    if not option or option.text ~= nativeConfigName or not panel.enableButton:isOn() then return false end
    local botTabs = panel.botTabs:getTabs()
    return type(botTabs) == 'table' and #botTabs == 0
  end)
  if shouldRefresh then
    engine.log('Relog: panel On sin pestanas, solicitando recarga nativa de ' .. nativeConfigName)
    local ok, err = pcall(reload)
    if not ok and not service.dead then engine.log('Relog: fallo de recarga nativa: ' .. tostring(err):sub(1, 140)) end
  end
end

local function scheduleRelogFinish()
  if not service.relogPending or service.relogEvent or type(schedule) ~= 'function' then return end
  local ok, event = pcall(schedule, function()
    service.relogEvent = nil
    if service.dead or not service.relogPending or not isOnline() then return end
    service.relogPending = false
    finishRelog()
  end, RELOG_FINISH_DELAY_MS)
  if ok then service.relogEvent = event end
end

engine = HelperReconnectEngine.new({
  config = config,
  clock = function() return os.time() end,
  isOnline = isOnline,
  isLogging = function() return call(g_game and g_game.isLogging) == true end,
  attempt = attempt,
  log = log,
})
-- The timer can observe a successful relog even when the client's onGameStart callback was missed.
local onGameStartInEngine = engine.onGameStart
function engine.onGameStart()
  onGameStartInEngine()
  scheduleRelogFinish()
end
-- Whatever flips the switch also saves it in the client's settings.
local setEnabledInEngine = engine.setEnabled
function engine.setEnabled(value)
  setEnabledInEngine(value)
  saveEnabled(config.enabled)
  writeReport() -- so the report shows what was just saved
end

-- Panel (a Tools module: power switch and a status line).
local panel = UI.createWidget('ReconnectPanel')
Reconect = {controller = engine, panel = panel}
function Reconect.isOn() return config.enabled == true end
function Reconect.setOn() engine.setEnabled(true) end
function Reconect.setOff() engine.setEnabled(false) end

local function refresh()
  local on = config.enabled == true
  if panel:isDestroyed() then return end
  panel.title:setOn(on)
  local status = engine.status()
  local message = status.message
  if status.kind == 'counting' and status.remaining > 0 then message = string.format('%s en %d s', message, status.remaining) end
  if panel.status:getText() ~= message then panel.status:setText(message) end
end
panel.title.onClick = function()
  engine.setEnabled(not config.enabled)
  refresh()
end

local function tick(waitForList)
  if service.dead then return end
  if waitForList and engine.mode == 'waiting' and engine.attempts == 0 and not isOnline() and not characterLogin() then
    return true
  end
  engine.tick()
  pcall(refresh)
  return false
end

-- While offline the bot's macros do not run: a chain of client timers does the retries, from the moment the
-- connection drops until the game is back (or the engine gives up).
local chain
local function startChain()
  if service.dead or service.chain or type(schedule) ~= 'function' then return false end
  service.chain = true
  service.firstListPolls = FIRST_LIST_POLLS
  local delay = engine.attempts == 0 and HelperReconnectEngine.FIRST_DELAY_MS or 1000
  engine.log('Temporizador del cliente: arranca la cadena de reintentos en ' .. delay .. ' ms')
  local ok, event = pcall(schedule, chain, delay)
  if ok then service.event = event else service.chain = false; engine.log('No se pudo programar el temporizador: ' .. tostring(event):sub(1, 100)) end
  return ok
end
chain = function()
  if service.dead then service.chain = false; return end
  local ok, waitingForList = pcall(tick, service.firstListPolls > 0)
  if not ok then engine.log('Error en el temporizador: ' .. tostring(waitingForList):sub(1, 140)) end
  if engine.mode == 'waiting' and not service.dead then
    local delay = 1000
    if ok and waitingForList then
      if service.firstListPolls == FIRST_LIST_POLLS then engine.log('Esperando al personaje en la lista del cliente') end
      service.firstListPolls = service.firstListPolls - 1
      delay = FIRST_LIST_POLL_MS
    end
    local scheduled, event = pcall(schedule, chain, delay)
    if scheduled then service.event = event
    else service.chain = false; engine.log('No se pudo reprogramar el temporizador: ' .. tostring(event):sub(1, 100)) end
  else
    service.chain = false
    engine.log('Temporizador del cliente: la cadena termina (' .. tostring(engine.mode) .. ')')
  end
end

-- g_game events: the same listener pattern the rest of the bot uses, undone on shutdown.
local function listen(event, callback)
  if not g_game then return end
  local listeners = g_game[event]
  if listeners == nil then g_game[event] = callback
  elseif type(listeners) == 'function' then g_game[event] = {listeners, callback}
  elseif type(listeners) == 'table' then
    local list = {}
    for _, fn in ipairs(listeners) do list[#list + 1] = fn end
    list[#list + 1] = callback
    g_game[event] = list
  else return end
  service.hooks[event] = callback
end
listen('onGameStart', function()
  if service.dead then return end
  local name = rememberCharacter()
  engine.log('Entrada en el juego' .. (name and (': ' .. name) or '') .. (config.enabled and '' or ' (Reconect APAGADO)'))
  engine.onGameStart()
end)
listen('onGameEnd', function()
  if service.dead then return end
  service.relogPending = true
  engine.onGameEnd()
  if not config.enabled then engine.log('Fin de partida con Reconect APAGADO: no se reconecta')
  elseif engine.mode == 'waiting' then startChain() end
end)
listen('onConnectionError', function(message, code)
  if service.dead then return end
  engine.log('Error de conexion: ' .. tostring(message or code or '?'):sub(1, 100))
  engine.onConnectionError(message, code)
end)
listen('onLoginError', function(message)
  if service.dead then return end
  engine.log('Error de entrada: ' .. tostring(message or '?'):sub(1, 120))
  engine.onLoginError(message)
end)

-- A logout asked for from the client's menu, a hotkey or the bot itself goes through these: it is wanted, not a drop.
for _, name in ipairs({'safeLogout', 'forceLogout', 'logout'}) do
  local original = g_game and g_game[name]
  if type(original) == 'function' then
    local function wrapper(...)
      if not service.dead then
        pcall(engine.onIntentionalLogout)
        pcall(engine.log, 'Cierre de sesion pedido (' .. name .. '): no se reconectara')
      end
      return original(...)
    end
    g_game[name] = wrapper
    service.wrapped[#service.wrapped + 1] = {name = name, original = original, wrapper = wrapper}
  end
end

function service.shutdown()
  service.dead = true
  if g_game then
    for event, callback in pairs(service.hooks) do
      local listeners = g_game[event]
      if listeners == callback then g_game[event] = nil
      elseif type(listeners) == 'table' then
        local remaining = {}
        for _, fn in ipairs(listeners) do if fn ~= callback then remaining[#remaining + 1] = fn end end
        if #remaining == 0 then g_game[event] = nil
        elseif #remaining == 1 then g_game[event] = remaining[1]
        else g_game[event] = remaining end
      end
    end
    for _, item in ipairs(service.wrapped) do
      if g_game[item.name] == item.wrapper then g_game[item.name] = item.original end
    end
  end
  service.hooks, service.wrapped = {}, {}
  if type(unschedule) == 'function' and service.event then pcall(unschedule, service.event) end
  if type(unschedule) == 'function' and service.relogEvent then pcall(unschedule, service.relogEvent) end
  service.chain = false
end

-- The native timer owns retry timing while it is active.
macro(1000, function()
  if not service.chain then tick() end
end)

local online = isOnline()
if online then rememberCharacter() end
engine.log(string.format('Modulo cargado (generacion %d): %s, Reconect %s, personaje %s', service.generation,
  online and 'en linea' or 'sin conexion', config.enabled and 'ENCENDIDO' or 'apagado', tostring(config.lastCharacter or '?')))
engine.onLoad()
if online then scheduleRelogFinish() end
if engine.mode == 'waiting' then startChain() end
refresh()
