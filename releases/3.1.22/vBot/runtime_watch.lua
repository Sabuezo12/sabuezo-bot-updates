--[[
  runtime_watch - makes two kinds of silent problems visible, without touching
  the modules that cause them.

  1) HelperErrors: Helper uses pcall() in ~2000 places, and an error caught by
     pcall leaves no trace. This wraps pcall (in the bot environment only) so each
     DISTINCT caught error is recorded once in the console ("Errores ocultos"),
     with a counter. Behaviour is unchanged: pcall still returns exactly what it
     returned. Many caught errors are intentional probes (a method that may not
     exist), so the diagnostics panel shows counts, not alarms.

  2) HelperPerf: wraps macro() so each macro callback is timed. A callback that
     takes 80 ms or more is recorded under the macro's name and source file
     ("Rendimiento"), at most once per 10 s per macro.

  Both can be switched off: HelperErrors.enabled = false / HelperPerf.enabled = false.
]]

local function consoleLog(level, source, message, detail)
  local rawPcall = HelperErrors and HelperErrors.originalPcall or pcall
  if RinoConsole and type(RinoConsole.log) == 'function' and type(RinoConsole.valid) == 'function' then
    rawPcall(function()
      if RinoConsole.valid() then RinoConsole.log(level, source, message, detail) end
    end)
  end
end

local function clip(value, limit)
  local text = tostring(value):gsub('[\r\n]+', ' ')
  limit = limit or 180
  if #text > limit then text = text:sub(1, limit - 3) .. '...' end
  return text
end

-- ---------------------------------------------------------------------------
-- 1) Hidden errors
-- ---------------------------------------------------------------------------
HelperErrors = HelperErrors or {total = 0, distinct = 0, counts = {}}
local E = HelperErrors
if E.enabled == nil then E.enabled = true end
-- Always wrap the ORIGINAL pcall, never a previous wrapper, so reloads do not stack.
E.originalPcall = E.originalPcall or pcall
local rawPcall = E.originalPcall
local MAX_DISTINCT = 300
local reporting = false

local function report(err)
  if reporting then return end
  reporting = true
  local message = clip(err)
  E.total = E.total + 1
  local entry = E.counts[message]
  if not entry then
    if E.distinct >= MAX_DISTINCT then
      E.overflow = (E.overflow or 0) + 1
    else
      entry = {count = 0}
      E.counts[message] = entry
      E.distinct = E.distinct + 1
      consoleLog('hidden', 'Error ocultado', message, 'primera vez; se cuenta, no se repite cada vez')
    end
  end
  if entry then
    entry.count = entry.count + 1
    local c = entry.count
    if c == 10 or c == 100 or c == 1000 or c == 10000 then
      consoleLog('hidden', 'Error ocultado', message, 'ya van ' .. c .. ' veces')
    end
  end
  reporting = false
end

local function check(ok, ...)
  if not ok and E.enabled then report((...)) end
  return ok, ...
end

pcall = function(fn, ...) return check(rawPcall(fn, ...)) end

function E.summary(limit)
  local list = {}
  for message, entry in pairs(E.counts) do list[#list + 1] = {message = message, count = entry.count} end
  table.sort(list, function(a, b) if a.count ~= b.count then return a.count > b.count end return a.message < b.message end)
  while #list > (limit or 8) do table.remove(list) end
  return {total = E.total, distinct = E.distinct, overflow = E.overflow or 0, top = list}
end

-- ---------------------------------------------------------------------------
-- 2) Slow macros
-- ---------------------------------------------------------------------------
HelperPerf = HelperPerf or {slow = {}, totalSlow = 0}
local P = HelperPerf
if P.enabled == nil then P.enabled = true end
P.threshold = P.threshold or 80   -- ms
P.timed = P.timed or setmetatable({}, {__mode = 'k'})

local clock = os and os.clock
local unpackFn = unpack or (table and table.unpack)

local function record(label, took)
  local entry = P.slow[label]
  if not entry then
    entry = {count = 0, total = 0, max = 0}
    P.slow[label] = entry
  end
  entry.count = entry.count + 1
  entry.total = entry.total + took
  if took > entry.max then entry.max = took end
  P.totalSlow = P.totalSlow + 1
  local at = type(now) == 'number' and now or 0
  if not entry.loggedAt or at - entry.loggedAt >= 10000 then
    entry.loggedAt = at
    consoleLog('perf', 'Macro lento', clip(label, 100) .. ': ' .. math.floor(took) .. ' ms',
      'veces: ' .. entry.count .. ' | maximo ' .. math.floor(entry.max) .. ' ms')
  end
end

-- ---------------------------------------------------------------------------
-- 3) Macro firewall: a macro that fails every single time it runs
--
--    NOTHING IS EVER STOPPED. A macro is never switched off, its on/off state is never
--    touched and it keeps being called at its own interval; a protection macro such as
--    HealBot can therefore never be lost to this. What it does:
--      * after F.alertAfter failures in a row: ONE clear console entry naming the macro;
--      * macros that are not essential: after F.calmAfter failures in a row the repeated
--        error line is no longer re-raised (the client logged it ~80 times a second:
--        272,000 lines in an hour from a single bug). The macro stays on, and the first
--        success puts everything back to normal;
--      * essential macros (healing, protection, combat, CaveBot/TargetBot...): alert only.
--        Their behaviour is identical to before, not even the retry rhythm changes.
-- ---------------------------------------------------------------------------
HelperFirewall = HelperFirewall or {incidents = {}, zombies = {}, total = 0}
local F = HelperFirewall
if F.enabled == nil then F.enabled = true end
F.alertAfter = F.alertAfter or 20
F.calmAfter = F.calmAfter or 200
F.summaryEvery = F.summaryEvery or 60000 -- ms between "still failing" lines
local ESSENTIAL = {'healbot', 'inmortal', 'condition', 'friend_healer', 'equip', 'attackbot', 'target', 'cavebot',
  'pushmax', 'combo', 'autobuff', 'antipush', 'keepwall', 'firebomb', 'holdtarget', 'exeta'}
local function isEssential(source)
  source = tostring(source or ''):lower()
  for _, key in ipairs(ESSENTIAL) do
    if source:find(key, 1, true) then return true end
  end
  return false
end
F.isEssential = isEssential

-- Which bot instance this is. Each (re)load takes the next number; a macro that still runs
-- after a newer instance started belongs to an old one: it is reported, never stopped
-- (stopping it could leave nothing running if the newer load failed half way).
local rootWidget = g_ui and g_ui.getRootWidget and g_ui.getRootWidget() or nil
local generation = 0
if rootWidget then
  generation = (rootWidget._rinoGeneration or 0) + 1
  rootWidget._rinoGeneration = generation
end
F.generation = generation

local function timing(label, started)
  if P.enabled then
    local took = (clock() - started) * 1000
    if took >= P.threshold then record(label, took) end
  end
end

local function guardedCallback(label, source, fn)
  if type(fn) ~= 'function' or P.timed[fn] then return fn end
  local state = {fails = 0}
  local protected = isEssential(source)
  local function settle(started, ok, ...)
    timing(label, started)
    if ok then
      if state.fails > 0 then
        local incident = F.incidents[label]
        if incident then incident.recovered = true end
        if state.alerted then
          consoleLog('info', 'Cortafuegos', label .. ' volvio a funcionar', 'tras ' .. state.fails .. ' fallos seguidos')
        end
        state.fails, state.alerted, state.calm = 0, false, false
      end
      return ...
    end
    local err = ...
    if not F.enabled then error(err, 0) end
    local message = clip(err)
    state.fails = state.fails + 1
    F.total = F.total + 1
    local incident = F.incidents[label]
    if incident then incident.count, incident.message = state.fails, message end
    if state.fails == F.alertAfter then
      state.alerted = true
      F.incidents[label] = {label = label, message = message, count = state.fails, essential = protected}
      consoleLog('error', 'Cortafuegos', label .. ' falla sin parar (' .. state.fails .. ' veces seguidas): ' .. message,
        protected and 'Macro esencial: no se detiene ni se calma, solo se avisa.'
          or ('No se detiene ni se desactiva. Si sigue, tras ' .. F.calmAfter .. ' fallos deja de repetirse la linea de error.'))
    end
    if not protected and state.fails >= F.calmAfter then
      -- The macro stays on and runs again at its own interval; only the repeated error
      -- line is not re-raised to the client any more.
      local at = type(now) == 'number' and now or 0
      if not state.calm then
        state.calm = true
        state.summaryAt = at -- the first "still failing" line comes a minute from now
        consoleLog('error', 'Cortafuegos', label .. ': se deja de repetir el error en el registro del cliente',
          'El macro sigue activo; al primer exito todo vuelve a la normalidad.')
      end
      if at - (state.summaryAt or -F.summaryEvery) >= F.summaryEvery then
        state.summaryAt = at
        consoleLog('error', 'Cortafuegos', label .. ' sigue fallando: ' .. state.fails .. ' veces', message)
      end
      return
    end
    error(err, 0) -- as before: the client logs it and retries on its own
  end
  local wrapped = function(...)
    if rootWidget and generation > 0 then
      local current = rootWidget._rinoGeneration
      if current and current ~= generation and not F.zombies[label] then
        F.zombies[label] = true
        -- warn() reaches the client log even when this old instance's console is gone.
        warn('INSTANCIA ANTERIOR: el macro "' .. label .. '" sigue ejecutandose pero el bot ya se recargo (instancia ' ..
          generation .. ', actual ' .. tostring(current) .. '). No se detiene.')
      end
    end
    local started = clock()
    return settle(started, rawPcall(fn, ...))
  end
  P.timed[wrapped] = true
  return wrapped
end

local function macroSource()
  return RinoScriptControls and RinoScriptControls.source or Helper and Helper.source or '?'
end

local function macroLabel(interval, name)
  local source = macroSource()
  if type(name) == 'string' and name ~= '' then return name .. ' [' .. tostring(source) .. ']' end
  return tostring(source) .. ' (' .. tostring(interval) .. ' ms)'
end

if clock and unpackFn and type(macro) == 'function' then
  local inner = macro
  -- After a reload macro may already be our wrapper: wrap what is underneath it.
  if P.macroWrapper and inner == P.macroWrapper and P.macroInner then inner = P.macroInner end
  P.macroInner = inner
  P.macroWrapper = function(interval, ...)
    local count = select('#', ...)
    local args = {...}
    local name
    for i = 1, count do
      local value = args[i]
      if type(value) == 'string' and not name then name = value end
      if type(value) == 'function' then
        args[i] = guardedCallback(macroLabel(interval, name), macroSource(), value)
        break
      end
    end
    return inner(interval, unpackFn(args, 1, count))
  end
  macro = P.macroWrapper
end

function P.summary(limit)
  local list = {}
  for label, entry in pairs(P.slow) do
    list[#list + 1] = {label = label, count = entry.count, max = math.floor(entry.max), total = math.floor(entry.total)}
  end
  table.sort(list, function(a, b) if a.total ~= b.total then return a.total > b.total end return a.label < b.label end)
  while #list > (limit or 8) do table.remove(list) end
  return {totalSlow = P.totalSlow, threshold = P.threshold, top = list}
end

-- ---------------------------------------------------------------------------
-- 4) Stalls: any gap in the bot's own clock, whatever causes it
--
--    The client reports "Slow macro" without saying which one (every macro is created
--    through the same wrapper), and the timing above sees only the macro callbacks, so
--    a stall caused by the memory collector or by the client itself was invisible.
--    A tiny macro runs on every tick and measures the time between ticks. A gap of
--    STALL_MS or more is a stall; if the Lua heap also shrank by a megabyte or more
--    meanwhile, the collector is the probable cause. Read-only: nothing is changed.
-- ---------------------------------------------------------------------------
P.stalls = P.stalls or {count = 0, worst = 0, collector = 0, recent = {}}
local S = P.stalls
local STALL_MS = P.stallMs or 80
local STALL_IGNORE_MS = 60000 -- longer gaps are a pause, a reconnect or a suspended client
local COLLECTOR_DROP_KB = 1024

local function heapKB()
  if type(collectgarbage) ~= 'function' then return nil end
  local ok, value = rawPcall(collectgarbage, 'count')
  if ok and type(value) == 'number' then return value end
end

local lastTick, lastHeap
local function sampleTick()
  local t = type(now) == 'number' and now or nil
  if not t then return end
  local heap = heapKB()
  if heap then
    S.heapMB = heap / 1024
    if not S.peakMB or S.heapMB > S.peakMB then S.peakMB = S.heapMB end
  end
  if lastTick then
    local gap = t - lastTick
    if gap >= STALL_MS and gap < STALL_IGNORE_MS then
      local dropKB = (lastHeap and heap) and (lastHeap - heap) or 0
      local collector = dropKB >= COLLECTOR_DROP_KB
      S.count = S.count + 1
      if collector then S.collector = S.collector + 1 end
      if gap > S.worst then S.worst = gap end
      S.recent[#S.recent + 1] = {at = os.date and os.date('%H:%M:%S') or '?', ms = math.floor(gap),
        heapMB = heap and math.floor(heap / 1024 * 10) / 10 or nil, dropMB = math.floor(dropKB / 1024 * 10) / 10,
        cause = collector and 'recolector de memoria' or 'sin causa visible'}
      while #S.recent > 20 do table.remove(S.recent, 1) end
      if t - (S.loggedAt or -10000) >= 5000 then
        S.loggedAt = t
        consoleLog('perf', 'Tiron', math.floor(gap) .. ' ms',
          (heap and string.format('memoria de Lua %.0f MB, %+.1f MB desde la muestra anterior | ', heap / 1024, -dropKB / 1024) or '') ..
          'causa probable: ' .. (collector and 'recolector de memoria' or 'ninguna visible (cliente, dibujo o disco)') ..
          ' | tirones: ' .. S.count .. ' (peor ' .. math.floor(S.worst) .. ' ms)')
      end
    end
  end
  lastTick, lastHeap = t, heap
end

function P.stallSummary()
  local recent = {}
  for i, entry in ipairs(S.recent) do recent[i] = entry end
  return {count = S.count, worst = math.floor(S.worst), collector = S.collector, heapMB = S.heapMB and math.floor(S.heapMB),
    peakMB = S.peakMB and math.floor(S.peakMB), thresholdMs = STALL_MS, recent = recent}
end

function F.summary()
  local list = {}
  for _, incident in pairs(F.incidents) do list[#list + 1] = incident end
  table.sort(list, function(a, b) return (a.count or 0) > (b.count or 0) end)
  local zombies = {}
  for label in pairs(F.zombies) do zombies[#zombies + 1] = label end
  table.sort(zombies)
  return {total = F.total, generation = F.generation, incidents = list, previousInstances = zombies,
    alertAfter = F.alertAfter, calmAfter = F.calmAfter}
end

if clock and P.macroInner and not P.stallMacro then
  P.stallMacro = P.macroInner(10, sampleTick)
end

-- ---------------------------------------------------------------------------
-- 4b) Memory: the Lua heap against the whole process
--
--    collectgarbage("count") is the heap of the client's single Lua state: client scripts, the
--    bot and any older bot instance that is still alive. The process figure (when the client
--    offers g_platform.getMemoryUsage) also counts textures, sprites and the map, which Lua
--    cannot see. If the process grows to gigabytes while the Lua heap stays flat, the growth
--    belongs to the client itself. The memory each load starts with is kept across reloads,
--    so a leak per reload shows as a staircase. Read-only.
-- ---------------------------------------------------------------------------
P.memory = P.memory or {samples = {}, alerts = {}, count = 0, reached = {}}
local M = P.memory
local PROCESS_STEPS_MB = {1500, 2500, 3500}
local LUA_ALERT_MB = 500

-- The unit is not documented: accept a number of bytes, kilobytes or megabytes, or text like "812 MB".
local function megabytes(value)
  if type(value) == 'string' then
    local number = tonumber(value:match('[%d%.]+'))
    if not number then return nil end
    local unit = value:upper()
    if unit:find('GB', 1, true) then return number * 1024 end
    if unit:find('KB', 1, true) then return number / 1024 end
    return number
  end
  if type(value) ~= 'number' or value ~= value or value <= 0 then return nil end
  if value >= 5e7 then return value / 1048576 end -- bytes
  if value >= 1e5 then return value / 1024 end    -- kilobytes
  return value                                      -- megabytes
end

local function processMB()
  if type(g_platform) ~= 'table' or type(g_platform.getMemoryUsage) ~= 'function' then return nil end
  local ok, value = rawPcall(g_platform.getMemoryUsage)
  if ok then return megabytes(value), value end
end
M.processAvailable = type(g_platform) == 'table' and type(g_platform.getMemoryUsage) == 'function' or false

local function countOf(list)
  if type(list) ~= 'table' then return nil end
  local n = 0
  for _ in pairs(list) do n = n + 1 end
  return n
end

local function context()
  local info = {}
  if type(getSpectators) == 'function' then
    local ok, list = rawPcall(getSpectators)
    if ok then info.creatures = countOf(list) end
  end
  if type(g_game) == 'table' and type(g_game.getContainers) == 'function' then
    local ok, list = rawPcall(g_game.getContainers)
    if ok then info.containers = countOf(list) end
  end
  return info
end

local function clockText() return os.date and os.date('%H:%M:%S') or '?' end

-- What this load starts with, kept on the root widget so it survives the reload.
do
  local boots = rootWidget and rootWidget._rinoBoots
  if rootWidget and type(boots) ~= 'table' then boots = {}; rootWidget._rinoBoots = boots end
  local heap = heapKB()
  local proc = processMB()
  local record = {instance = generation, at = clockText(), luaMB = heap and math.floor(heap / 1024) or nil,
    processMB = proc and math.floor(proc) or nil}
  if boots then
    boots[#boots + 1] = record
    while #boots > 40 do table.remove(boots, 1) end
  end
  M.boots = boots or {record}
end

local function sampleMemory()
  local heap = heapKB()
  local proc = processMB()
  local lua = heap and heap / 1024 or nil
  M.count = M.count + 1
  M.luaMB, M.processMB = lua, proc
  if lua and (not M.peakLuaMB or lua > M.peakLuaMB) then M.peakLuaMB = lua end
  if proc and (not M.peakProcessMB or proc > M.peakProcessMB) then M.peakProcessMB = proc end
  M.samples[#M.samples + 1] = {at = clockText(), lua = lua and math.floor(lua) or nil, proc = proc and math.floor(proc) or nil}
  while #M.samples > 360 do table.remove(M.samples, 1) end

  local function alert(step, text, detail)
    local info = context()
    M.alerts[#M.alerts + 1] = {at = clockText(), step = step, instance = generation, processMB = proc and math.floor(proc) or nil,
      luaMB = lua and math.floor(lua) or nil, creatures = info.creatures, containers = info.containers}
    while #M.alerts > 20 do table.remove(M.alerts, 1) end
    consoleLog('perf', 'Memoria', text, detail .. ' | criaturas a la vista: ' .. tostring(info.creatures or '?') ..
      ' | contenedores abiertos: ' .. tostring(info.containers or '?') .. ' | instancia del bot: ' .. generation)
  end

  if proc then
    for _, step in ipairs(PROCESS_STEPS_MB) do
      if proc >= step then
        if not M.reached[step] then
          M.reached[step] = true
          local outside = lua and (proc - lua) >= 0.7 * proc
          alert(step, string.format('el proceso llego a %.0f MB (Lua %s MB)', proc, lua and string.format('%.0f', lua) or '?'),
            outside and 'La mayor parte esta FUERA de Lua: texturas, sprites o mapa del cliente, no el bot.'
              or 'Una parte importante es memoria de Lua (bot, scripts o instancias anteriores).')
        end
      elseif proc < step * 0.8 then
        M.reached[step] = nil
      end
    end
  end
  if lua then
    if lua >= LUA_ALERT_MB then
      if not M.luaReached then
        M.luaReached = true
        alert('lua', string.format('la memoria de Lua pasa de %d MB (%.0f MB)', LUA_ALERT_MB, lua),
          'Acumulacion en scripts, o instancias anteriores del bot aun vivas.')
      end
    elseif lua < LUA_ALERT_MB * 0.8 then
      M.luaReached = nil
    end
  end
end

function P.memorySummary()
  local recent, n = {}, #M.samples
  for i = math.max(1, n - 59), n do recent[#recent + 1] = M.samples[i] end
  local function round(v) return v and math.floor(v) or nil end
  local alerts = {}
  for i, entry in ipairs(M.alerts) do alerts[i] = entry end
  return {luaMB = round(M.luaMB), peakLuaMB = round(M.peakLuaMB), processMB = round(M.processMB), peakProcessMB = round(M.peakProcessMB),
    processAvailable = M.processAvailable, instance = generation, loadsThisSession = #(M.boots or {}), boots = M.boots,
    alerts = alerts, recent = recent, samples = M.count}
end

if clock and P.macroInner and not P.memoryMacro then
  P.memoryMacro = P.macroInner(10000, sampleMemory)
end

-- ---------------------------------------------------------------------------
-- 5) Keep the numbers: _diagnostics/perf.json, every minute while something new happened.
--    (client-report.json is rewritten at every load, so its counters always start at zero.)
-- ---------------------------------------------------------------------------
local lastPersisted = 0 -- nothing to say until something happens
local function persist()
  if type(json) ~= 'table' or type(json.encode) ~= 'function' or type(g_resources) ~= 'table' or
      type(g_resources.writeFileContents) ~= 'function' then return end
  -- Memory alerts count as news, and every 5 minutes the memory history is refreshed anyway.
  local activity = P.totalSlow + S.count + F.total + E.total + #M.alerts + math.floor(M.count / 30)
  if activity == lastPersisted then return end
  -- Same folder rule as client-report.json; the old panel lookup fails on Next Gen.
  local folder
  local base = type(configDir) == 'string' and configDir:gsub('\\', '/'):gsub('/+$', '') or nil
  if base and base:match('^/bot/[^/]+$') and not base:find('..', 1, true) then
    folder = base
  else
    local ok, config = rawPcall(function() return modules.game_bot.contentsPanel.config:getCurrentOption().text end)
    if not ok or type(config) ~= 'string' or config:find('[/\\%c]') then return end
    folder = '/bot/' .. config
  end
  -- Several clients share the bot folder: one file per character.
  local who = ''
  rawPcall(function() who = tostring(player:getName()):gsub('[^%w]', '_') end)
  local file = who ~= '' and ('perf-' .. who .. '.json') or 'perf.json'
  rawPcall(function()
    if type(g_resources.makeDir) == 'function' then g_resources.makeDir(folder .. '/_diagnostics') end
    g_resources.writeFileContents(folder .. '/_diagnostics/' .. file, json.encode({
      at = os.date and os.date('%Y-%m-%d %H:%M:%S') or '?', instance = generation,
      slowMacros = P.summary(10), stalls = P.stallSummary(), firewall = F.summary(), memory = P.memorySummary(),
      hiddenErrors = E.summary(8)}, 2))
    lastPersisted = activity
  end)
end
function P.persist() return persist() end
if clock and P.macroInner and not P.persistMacro then
  P.persistMacro = P.macroInner(60000, persist)
end
