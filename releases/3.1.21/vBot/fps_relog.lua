setDefaultTab('Tools')
-- FPS Relog: says "!fps" every N minutes at a safe moment and measures the relog.
-- The decisions live in fps_relog_engine.lua; this file is the panel and the game access.
storage.helperFpsRelog = type(storage.helperFpsRelog) == 'table' and storage.helperFpsRelog or {}
local config = storage.helperFpsRelog

local function call(fn, ...)
  if type(fn) ~= 'function' then return nil end
  local ok, value = pcall(fn, ...)
  if ok then return value end
end

-- nil plus the name of what could not be read: the engine then waits and says so,
-- instead of guessing (an unknown HP must never count as "full HP").
local function snapshot(cfg)
  if not (g_game and type(g_game.isOnline) == 'function' and g_game.isOnline()) then return nil, 'sin conexion' end
  local hp = tonumber(call(hppercent))
  if not hp then
    local localPlayer = call(g_game.getLocalPlayer)
    hp = localPlayer and tonumber(call(function() return localPlayer:getHealthPercent() end))
  end
  if not hp then return nil, 'HP' end
  local monsters = tonumber(call(getMonsters, cfg.monsterRadius))
  if not monsters then return nil, 'monstruos' end
  local players = 0
  if cfg.playerRadius > 0 then
    players = tonumber(call(getPlayers, cfg.playerRadius))
    if not players then return nil, 'jugadores' end
  end
  return {hp = hp, monsters = monsters, players = players, inPz = call(isInPz) == true}
end

local function sendCommand(text)
  -- Same chat path the Timer Executor uses for its "Say" action.
  if type(HelperAPI) == 'table' and type(HelperAPI.say) == 'function' then return HelperAPI.say(text) == true end
  if type(say) == 'function' and pcall(say, text) then return true end
  if g_game and type(g_game.talk) == 'function' and pcall(g_game.talk, text) then return true end
  return false
end

-- Every decision goes to the console under "Acciones" (origin FPS Relog).
local function log(message)
  if RinoConsole and type(RinoConsole.log) == 'function' then pcall(RinoConsole.log, 'action', 'FPS Relog', message) end
end

local engine = HelperFpsRelogEngine.new({config = config, clock = function() return os.time() end,
  snapshot = snapshot, say = sendCommand, log = log})
engine.onLoad()

-- What the server answers in the seconds after the command (shows whether it was understood).
local seenSent, reported = nil, 0
onTextMessage(function(mode, message)
  local sent = config.sentAt
  if not sent or os.time() - sent > 15 then return end
  if sent ~= seenSent then seenSent, reported = sent, 0 end
  if reported >= 6 then return end
  reported = reported + 1
  log('Respuesta del servidor tras el comando: ' .. tostring(message):sub(1, 160))
end)

local panel = UI.createWidget('FpsRelogPanel')
local window = UI.createWindow('FpsRelogWindow')
window:hide()
FpsRelog = {controller = engine, panel = panel, window = window}
function FpsRelog.isOn() return engine.config.enabled == true end
function FpsRelog.setOn() engine.setEnabled(true) end
function FpsRelog.setOff() engine.setEnabled(false) end

local function text(widget, value)
  if widget:getText() ~= value then widget:setText(value) end
end

local function seconds(value)
  value = math.max(0, math.floor(tonumber(value) or 0))
  return string.format('%d:%02d', math.floor(value / 60), value % 60)
end

local function refresh()
  local status = engine.state
  local on = config.enabled == true
  panel.title:setOn(on)
  window.enabled:setOn(on)
  local message = status.kind == 'counting' and
    string.format('%s en %s', status.message, seconds(status.remaining)) or status.message
  text(panel.status, message)
  text(window.status, message)
  local stats = config.stats
  local function secs(value) return value and (tostring(value) .. ' s') or '-' end
  text(window.stats, string.format('Enviados: %d | Vueltas medidas: %d | Ultima: %s | Mejor: %s | Peor: %s | Sin recarga: %d',
    stats.count, stats.returns, secs(stats.last), secs(stats.best), secs(stats.worst), stats.noReload))
  local entry = engine.trace[#engine.trace]
  text(window.lastEvent, entry and (os.date('%H:%M:%S', entry.at) .. '  ' .. entry.text) or 'Sin eventos todavia')
end

-- Settings window: values first, handlers after, so loading them never writes back.
window.interval:setValue(config.intervalMin)
window.command:setText(config.command)
window.safeMonsters:setChecked(config.safeMonsters)
window.monsterRadius:setValue(config.monsterRadius)
window.minHp:setValue(config.minHp)
window.playerRadius:setValue(config.playerRadius)
window.waitSec:setValue(config.waitSec)
window.force:setChecked(config.forceAfterWait)
window.interval.onValueChange = function(_, value) config.intervalMin = value end
window.command.onTextChange = function(_, value) config.command = value end
window.safeMonsters.onCheckChange = function(_, checked) config.safeMonsters = checked == true end
window.monsterRadius.onValueChange = function(_, value) config.monsterRadius = value end
window.minHp.onValueChange = function(_, value) config.minHp = value end
window.playerRadius.onValueChange = function(_, value) config.playerRadius = value end
window.waitSec.onValueChange = function(_, value) config.waitSec = value end
window.force.onCheckChange = function(_, checked) config.forceAfterWait = checked == true end

local function toggle()
  engine.setEnabled(not config.enabled)
  engine.tick()
  refresh()
end
panel.title.onClick = toggle
window.enabled.onClick = toggle
panel.settings.onClick = function() refresh(); window:show(); window:raise(); window:focus() end
window.closeButton.onClick = function()
  -- A command typed and closed is normalised (empty falls back to !fps).
  HelperFpsRelogEngine.normalize(config)
  window.command:setText(config.command)
  window:hide()
end
window.onEscape = window.closeButton.onClick
-- Works with the automatic mode off too: it is how the command is tried.
window.sendNow.onClick = function()
  engine.sendNow()
  engine.tick()
  refresh()
end
FpsRelog.open = panel.settings.onClick

macro(1000, function() engine.tick(); refresh() end)
engine.tick()
refresh()
