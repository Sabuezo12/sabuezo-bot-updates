-- Helpers for CaveBot "function" waypoints, the prefix that exposes them to the Lua of a
-- waypoint, a syntax check, a dry run that performs none of the bot's usual actions, and
-- the catalog of functions and templates shown by the function editor
-- (cavebot/function_editor.lua). Existing functions keep working unchanged: the prefix
-- still defines retries, prev, delay, gotoLabel, waitStamina, setHealBot and stepDirection.
CaveBot.FunctionHelpers = CaveBot.FunctionHelpers or {}
CaveBot.FunctionRuntime = CaveBot.FunctionRuntime or {}
local H = CaveBot.FunctionHelpers
local R = CaveBot.FunctionRuntime

local CHUNK = "cavebot_function"

local function clock() return tonumber(now) or 0 end
local function trim(value) return tostring(value or ""):match("^%s*(.-)%s*$") end
local function say_warn(message) if type(warn) == "function" then pcall(warn, message) end end

-- Route bookkeeping: cavebot/cavebot.lua reports when the route starts and each lap ------
local route = {startedAt = nil, laps = 0}
function R.routeStarted()
  route.startedAt, route.laps = clock(), 0
end
function R.lapCompleted()
  route.laps = route.laps + 1
end

-- Minutes since the CaveBot route was switched on.
function H.huntMinutes()
  if not route.startedAt then return 0 end
  return math.floor(math.max(0, clock() - route.startedAt) / 60000)
end

-- Laps of the route completed since it was switched on.
function H.laps()
  return route.laps
end

-- Amount of an item, closed backpacks included when the client can count them.
function H.itemCount(id)
  id = tonumber(id)
  if not id then return 0 end
  local open = 0
  if type(itemAmount) == "function" then
    local ok, value = pcall(itemAmount, id)
    open = ok and tonumber(value) or 0
  end
  if player and type(player.getInventoryCount) == "function" then
    local ok, value = pcall(player.getInventoryCount, player, id, 0)
    if ok and tonumber(value) then return math.max(tonumber(value), open) end
  end
  return open
end

-- Gold coins, platinum and crystal counted as gold.
function H.goldCount()
  return H.itemCount(3031) + H.itemCount(3035) * 100 + H.itemCount(3043) * 10000
end

local function nameSet(names)
  if type(names) ~= "string" or trim(names) == "" then return nil end
  local set = {}
  for name in names:gmatch("[^,]+") do
    name = trim(name):lower()
    if name ~= "" then set[name] = true end
  end
  return set
end

local function around(range, pick)
  local origin = player and player:getPosition()
  if not origin or type(getSpectators) ~= "function" then return 0 end
  range = tonumber(range) or 7
  local count = 0
  for _, creature in ipairs(getSpectators() or {}) do
    if creature ~= player then
      local ok, counted = pcall(function()
        local p = creature:getPosition()
        if not p or p.z ~= origin.z then return false end
        if math.max(math.abs(p.x - origin.x), math.abs(p.y - origin.y)) > range then return false end
        return pick(creature)
      end)
      if ok and counted then count = count + 1 end
    end
  end
  return count
end

-- Living monsters within range (same floor); names: optional "Dragon, Dragon Lord".
function H.monstersAround(range, names)
  local wanted = nameSet(names)
  return around(range, function(creature)
    if not creature:isMonster() then return false end
    local health = creature:getHealthPercent()
    if health and health <= 0 then return false end
    return not wanted or wanted[tostring(creature:getName()):lower()] == true
  end)
end

local function friendly(creature)
  local okParty, party = pcall(function() return creature:isPartyMember() end)
  if okParty and party then return true end
  local name = creature:getName()
  if PlayerList then
    for _, check in ipairs({"isFriend", "isGuildMember"}) do
      if type(PlayerList[check]) == "function" then
        local ok, result = pcall(PlayerList[check], name)
        if ok and result then return true end
      end
    end
  end
  return false
end

-- Other players within range (same floor). Party, friends and guild are left out unless
-- includeFriends is true.
function H.playersAround(range, includeFriends)
  return around(range, function(creature)
    if not creature:isPlayer() then return false end
    local okLocal, isLocal = pcall(function() return creature:isLocalPlayer() end)
    if okLocal and isLocal then return false end
    return includeFriends == true or not friendly(creature)
  end)
end

local function switchMode(value)
  value = trim(value):lower()
  if value == "on" or value == "true" or value == "1" or value == "encender" or value == "activar" then return "on" end
  if value == "off" or value == "false" or value == "0" or value == "apagar" or value == "desactivar" then return "off" end
  if value == "toggle" or value == "cambiar" then return "toggle" end
end

local BOTS = {target = "TargetBot", targetbot = "TargetBot", attack = "AttackBot", attackbot = "AttackBot",
  heal = "HealBot", healbot = "HealBot", cave = "CaveBot", cavebot = "CaveBot"}

-- setBot("target" | "attack" | "heal" | "cave", "on" | "off" | "toggle")
function H.setBot(name, mode)
  local which, wanted = BOTS[trim(name):lower()], switchMode(mode)
  if not which or not wanted then
    say_warn('CaveBot[setBot]: usa setBot("target"|"attack"|"heal"|"cave", "on"|"off"|"toggle")')
    return false
  end
  if which == "HealBot" then return H.setHealBot(wanted) end
  local api = which == "TargetBot" and TargetBot or which == "AttackBot" and AttackBot or CaveBot
  if type(api) ~= "table" or type(api.setOn) ~= "function" or type(api.setOff) ~= "function" then
    say_warn("CaveBot[setBot]: " .. which .. " no esta disponible")
    return false
  end
  if wanted == "toggle" then
    local ok, on = pcall(function() return api.isOn and api.isOn() end)
    wanted = ok and on and "off" or "on"
  end
  if wanted == "on" then api.setOn() else api.setOff() end
  return true
end

local alarmAt = nil
-- Sound (at most every 3 s), window flash and a console warning.
function H.alarm(text)
  text = tostring(text or "Alarma del CaveBot")
  local t = clock()
  if not alarmAt or t - alarmAt >= 3000 or t < alarmAt then
    alarmAt = t
    if type(playSound) == "function" then pcall(playSound, "/sounds/alarm.ogg") end
    if type(g_window) == "table" and type(g_window.flash) == "function" then pcall(g_window.flash) end
  end
  say_warn("[CaveBot] " .. text)
  return true
end

-- The route continues at waypoint n (the action must return what this returns).
function H.gotoWaypoint(n)
  local list = CaveBot.actionList
  n = tonumber(n)
  if not list or not n then return false end
  local count = list:getChildCount()
  if n < 1 or n > count or n % 1 ~= 0 then
    say_warn("CaveBot[gotoWaypoint]: la ruta tiene " .. count .. " waypoints")
    return false
  end
  local previous = n - 1
  if previous < 1 then previous = count end
  list:focusChild(list:getChildByIndex(previous))
  return true
end

-- Protection zone blocked (after attacking players): vBot's isPzLocked when the client has
-- it, otherwise the player's PzBlock state (8192).
function H.pzLocked()
  if type(isPzLocked) == "function" then
    local ok, value = pcall(isPzLocked)
    if ok and type(value) == "boolean" then return value end
  end
  local ok, states = pcall(function() return player:getStates() end)
  states = ok and tonumber(states) or 0
  return math.floor(states / 8192) % 2 == 1
end

-- White, red, black or orange skull (yellow and the party's green do not count).
function H.hasSkull()
  local ok, skull = pcall(function() return player:getSkull() end)
  skull = ok and tonumber(skull) or 0
  return skull >= 3 and skull <= 6
end

-- A line in the RinoBot console (Acciones).
function H.log(text)
  if RinoConsole and type(RinoConsole.log) == "function" then
    pcall(RinoConsole.log, "action", "CaveBot funcion", tostring(text))
  end
  return true
end

local waiting = {row = nil, at = 0}
-- Waits on this waypoint until check() is true (returns true) or timeoutMs passes (false).
function H.waitUntil(check, retries, timeoutMs, everyMs)
  local t = clock()
  local row = CaveBot.actionList and CaveBot.actionList:getFocusedChild()
  if retries == 0 or waiting.row ~= row then waiting.row, waiting.at = row, t end
  if type(check) ~= "function" then
    say_warn("CaveBot[waitUntil]: el primer valor debe ser una funcion")
    return false
  end
  local ok, done = pcall(check)
  if not ok then
    if retries == 0 then say_warn("CaveBot[waitUntil]: " .. tostring(done)) end
    return false
  end
  if done then return true end
  if t - waiting.at >= (tonumber(timeoutMs) or 60000) then return false end
  CaveBot.delay(math.max(100, tonumber(everyMs) or 500))
  return "retry"
end

-- Prefix of every function waypoint ------------------------------------------------
R.exported = {"itemCount", "goldCount", "monstersAround", "playersAround", "huntMinutes", "laps",
  "setBot", "alarm", "gotoWaypoint", "log", "pzLocked", "hasSkull"}

function R.prefix(retries, prev)
  local lines = {
    "local retries = " .. tostring(tonumber(retries) or 0),
    "local prev = " .. tostring(prev),
    "local delay = CaveBot.delay",
    "local gotoLabel = CaveBot.gotoLabel",
    "local waitStamina = CaveBot.FunctionHelpers.waitStamina",
    "local setHealBot = CaveBot.FunctionHelpers.setHealBot",
    "local stepDirection = function(direction, maxRetries, waitMs) return CaveBot.FunctionHelpers.stepDirection(direction, retries, maxRetries, waitMs) end",
    "local waitUntil = function(check, timeoutMs, everyMs) return CaveBot.FunctionHelpers.waitUntil(check, retries, timeoutMs, everyMs) end",
    "local macro = function() warn('Macros inside cavebot functions are not allowed') end",
  }
  for _, name in ipairs(R.exported) do
    lines[#lines + 1] = "local " .. name .. " = CaveBot.FunctionHelpers." .. name
  end
  for extension in pairs(CaveBot.Extensions or {}) do
    lines[#lines + 1] = "local " .. extension .. " = CaveBot.Extensions." .. extension
  end
  return table.concat(lines, "\n") .. "\n", #lines
end

-- Error positions as the user's own line numbers.
function R.fixLines(message, offset)
  message = tostring(message)
  offset = tonumber(offset) or 0
  message = message:gsub('(' .. CHUNK .. '"%]:)(%d+)', function(head, n)
    return head .. math.max(1, tonumber(n) - offset)
  end)
  message = message:gsub("(at line )(%d+)", function(head, n)
    return head .. math.max(1, tonumber(n) - offset)
  end)
  return message
end

function R.labelExists(name)
  name = trim(name):lower()
  for _, row in ipairs(CaveBot.actionList and CaveBot.actionList:getChildren() or {}) do
    if row.action == "label" and trim(row.value):lower() == name then return true end
  end
  return false
end

local TRANSLATIONS = {
  {"'end' expected", "falta 'end'"}, {"'then' expected", "falta 'then'"}, {"'do' expected", "falta 'do'"},
  {"'=' expected", "falta '='"}, {"'%)' expected", "falta ')'"}, {"'%(' expected", "falta '('"},
  {"unfinished string", "texto sin cerrar (falta una comilla)"}, {"unexpected symbol", "simbolo inesperado"},
  {"to close 'if' at line", "para cerrar el 'if' de la linea"},
  {"to close 'function' at line", "para cerrar la 'function' de la linea"},
  {"to close 'for' at line", "para cerrar el 'for' de la linea"},
  {"to close 'while' at line", "para cerrar el 'while' de la linea"},
  {"to close '%(' at line", "para cerrar el '(' de la linea"}, {" near ", " cerca de "},
  {"attempt to call global", "se llamo a la funcion inexistente"},
  {"attempt to call a nil value", "se llamo a una funcion que no existe"},
  {"attempt to index", "se intento leer dentro de"}, {"a nil value", "un valor vacio (nil)"},
  {"attempt to compare", "no se pueden comparar"}, {"attempt to perform arithmetic on", "no se puede hacer cuentas con"},
}
function R.spanish(message)
  message = tostring(message)
  for _, pair in ipairs(TRANSLATIONS) do message = message:gsub(pair[1], pair[2]) end
  return message
end

-- Syntax and label check of a function's code, without running it.
function R.check(code)
  code = tostring(code or "")
  local compile = loadstring or load
  local result = {missingLabels = {}}
  local chunk, err = compile(code, CHUNK)
  if not chunk then
    local text = tostring(err)
    result.line = tonumber(text:match('"%]:(%d+):'))
    result.error = R.spanish(text:gsub('^%[string "' .. CHUNK .. '"%]:(%d+):%s*', "Linea %1: "))
  end
  local seen = {}
  for name in code:gmatch("gotoLabel%s*%(%s*[\"']([^\"']+)[\"']") do
    if not seen[name:lower()] and not R.labelExists(name) then
      seen[name:lower()] = true
      result.missingLabels[#result.missingLabels + 1] = name
    end
  end
  result.noReturn = not code:find("return", 1, true)
  return result
end

-- Dry run ----------------------------------------------------------------------------
-- The code runs once with the usual actions replaced by notes: it does not walk, talk,
-- jump to labels, switch bots or log out. Reads (positions, counts, isOn...) are real.
function R.record(text)
  if R.dryLog then R.dryLog[#R.dryLog + 1] = tostring(text) end
end

local READS = {"^is", "^get", "^has", "^can", "^last"}
function R.proxy(real, name, seen)
  local kind = type(real)
  if kind ~= "table" and kind ~= "userdata" then return real end
  seen = seen or {}
  if seen[real] then return seen[real] end
  local proxy = {}
  seen[real] = proxy
  return setmetatable(proxy, {__index = function(_, key)
    local value = real[key]
    if type(value) == "table" or type(value) == "userdata" then
      return R.proxy(value, name .. "." .. tostring(key), seen)
    end
    if type(value) ~= "function" then return value end
    local text = tostring(key)
    for _, pattern in ipairs(READS) do
      if text:match(pattern) then
        return function(self, ...)
          if self == proxy then return value(real, ...) end
          return value(self, ...)
        end
      end
    end
    return function() R.record(name .. "." .. text .. "(...)"); return true end
  end})
end

-- A preview uses its own copy, including nested settings; testing user Lua must
-- not persist assignments in the active character's storage.
function R.copyStorage(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local out = {}
  seen[value] = out
  for key, child in pairs(value) do out[key] = R.copyStorage(child, seen) end
  return out
end

-- Generated visual rules have a readable preview too. Calling their real run()
-- would invoke the bot module's globals, bypassing the Lua preview's local stubs.
local function previewRule(config)
  local ok, matched = pcall(CaveBot.FunctionRules.evaluate, config)
  if not ok then return {ok = false, error = R.spanish(matched), actions = {}} end
  if matched == nil then return {ok = true, result = "retry", actions = {"esperaria datos de la condicion"}} end
  local branch = matched and config.yes or config.no
  local mode, actions, result = branch.mode, {}, true
  if mode == "label" then
    actions[1] = "iria al label " .. tostring(branch.label)
    if not R.labelExists(branch.label) then result = "retry" end
  elseif mode == "wait" then actions[1], result = "esperaria " .. config.intervalMs .. " ms", "retry"
  elseif mode == "say" then actions[1] = "diria: " .. tostring(branch.text)
  elseif mode == "alarm" then actions[1] = "sonaria la alarma: " .. tostring(branch.text or "Regla del CaveBot")
  elseif mode == "stop" then actions[1] = "apagaria CaveBot"
  elseif mode == "logout" then actions[1], result = "haria logout", "retry"
  elseif mode ~= "next" then actions[1] = "pondria " .. tostring(mode):gsub("_", " en ") end
  return {ok = true, result = result, actions = actions}
end

local DRY_LINES = {
  "local __R = CaveBot.FunctionRuntime",
  "local storage = __R.copyStorage(storage)",
  'local delay = function(ms) __R.record("esperaria " .. tostring(ms) .. " ms") end',
  'local gotoLabel = function(name) __R.record("iria al label " .. tostring(name)); return __R.labelExists(name) end',
  'local gotoWaypoint = function(n) __R.record("iria al waypoint " .. tostring(n)); return true end',
  'local say = function(text) __R.record("diria: " .. tostring(text)) end',
  'local setBot = function(bot, mode) __R.record("pondria " .. tostring(bot) .. " en " .. tostring(mode)); return true end',
  'local setHealBot = function(mode) __R.record("pondria HealBot en " .. tostring(mode)); return true end',
  'local alarm = function(text) __R.record("sonaria la alarma: " .. tostring(text)); return true end',
  'local log = function(text) __R.record("consola: " .. tostring(text)); return true end',
  'local stepDirection = function(direction) __R.record("daria un paso hacia " .. tostring(direction)); return true end',
  'local waitStamina = function(minutes) __R.record("esperaria stamina de " .. tostring(minutes) .. " min"); return true end',
  'local waitUntil = function(check) local ok, done = pcall(check); __R.record("esperaria hasta que se cumpla (ahora: " .. ((ok and done) and "si" or "no") .. ")"); return (ok and done) and true or "retry" end',
  'local autoWalk = function() __R.record("caminaria (autoWalk)") end',
  'local walk = function() __R.record("caminaria") end',
  "local safeBotWalk = walk",
  'local use = function() __R.record("usaria un objeto") end',
  'local useWith = function() __R.record("usaria un objeto sobre otro") end',
  "local usewith = useWith",
  'local schedule = function() __R.record("programaria una accion") end',
  'local NPC = __R.proxy(NPC, "NPC")',
  'local TargetBot = __R.proxy(TargetBot, "TargetBot")',
  'local AttackBot = __R.proxy(AttackBot, "AttackBot")',
  'local HealBot = __R.proxy(HealBot, "HealBot")',
  'local g_game = __R.proxy(g_game, "g_game")',
}

function R.dryRun(code)
  code = tostring(code or "")
  local rules = CaveBot.FunctionRules
  local encoded = code:match("^%-%- RinoRule v1: ([^\n]+)\n")
  local config = rules and rules.decode(code)
  if config and encoded and code == "-- RinoRule v1: " .. encoded ..
      "\nreturn CaveBot.FunctionRules.run(" .. string.format("%q", encoded) .. ", retries)" then
    return previewRule(config)
  end
  local prefix, prefixLines = R.prefix(0, true)
  local lines = {}
  for _, line in ipairs(DRY_LINES) do lines[#lines + 1] = line end
  for extension in pairs(CaveBot.Extensions or {}) do
    lines[#lines + 1] = "local " .. extension .. ' = __R.proxy(CaveBot.Extensions.' .. extension .. ', "' .. extension .. '")'
  end
  lines[#lines + 1] = 'local CaveBot = __R.proxy(CaveBot, "CaveBot")' -- last: the lines above still use the real one
  local offset = prefixLines + #lines
  local compile = load or loadstring
  local chunk, err = compile(prefix .. table.concat(lines, "\n") .. "\n" .. tostring(code or ""), CHUNK)
  if not chunk then return {ok = false, error = R.spanish(R.fixLines(err, offset)), actions = {}} end
  R.dryLog = {}
  local ok, result = pcall(chunk)
  local actions = R.dryLog
  R.dryLog = nil
  if not ok then return {ok = false, error = R.spanish(R.fixLines(result, offset)), actions = actions} end
  return {ok = true, result = result, actions = actions}
end

function R.describeResult(result)
  if result == true then return "true: sigue con el siguiente waypoint" end
  if result == false then return "false: sigue con el siguiente waypoint (prev = false)" end
  if result == "retry" then return '"retry": repite esta funcion (esperando)' end
  return tostring(result) .. ": valor no valido; debe ser true, false o \"retry\""
end
