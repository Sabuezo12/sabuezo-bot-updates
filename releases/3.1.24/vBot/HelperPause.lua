-- Pause for the whole bot. CaveBot and TargetBot are held by a non-destructive gate (their
-- ON/OFF keeps the intended state, including hotkey changes while paused). Every other function
-- that acts (attack, healing, protection, buffs, tools...) is switched OFF and remembered, and
-- switched back ON on resume. Navi, the alarms and the item counter keep running.
HelperPause = {}
local P, H = HelperPause, Helper
storage.helperUI = type(storage.helperUI) == "table" and storage.helperUI or {}
local state = storage.helperUI
local paused = state.paused == true
local engines = {}
-- Handled by the gate above, or not actions: left alone by the pause.
local KEEP_RUNNING = {cavebot = true, targetbot = true, botserver = true, alarms = true, itemcounter = true,
  custom_hotkeys = true} -- las hotkeys son manuales: tienen que seguir vivas para poder reanudar el bot
-- A pause that is still on after this long (a reload or a new login much later) is lifted at
-- load, so a forgotten pause cannot leave the character without healing.
local STALE_SECONDS = 600
function P.isPaused() return paused end
function P.desired(id)
  local e = engines[id]
  if not e then return nil end
  local ok, enabled = pcall(e.isOn)
  if ok then return enabled == true end
end
-- True while the module is switched off by the pause and will come back on resume.
function P.willResume(id)
  if not paused or type(state.pausedModules) ~= "table" then return false end
  for _, saved in ipairs(state.pausedModules) do if saved == id then return true end end
  return false
end
function P.attach(id, engine)
  if not engine or type(engine.isOn) ~= "function" then return end
  local e = {isOn = engine.isOn, setOn = engine.setOn, setOff = engine.setOff}
  engines[id] = e
  engine.isOn = function() return not paused and e.isOn() end
  engine.isOff = function() return not engine.isOn() end
  engine.setOn = function(value)
    if paused and storage.cManager then storage.cManager.pausedCave = false end
    return e.setOn(value)
  end
  engine.setOff = function(value)
    if paused and storage.cManager then storage.cManager.pausedCave = false end
    return e.setOff(value)
  end
end

-- The module list and its real ON/OFF switch exist only when the Helper layer is loaded.
local function moduleApi()
  if not H or type(H.getState) ~= "function" or type(H.setEnabled) ~= "function" or type(H.order) ~= "table" then return nil end
  if type(H.valid) == "function" and not H.valid() then return nil end
  return H
end
local function pauseModules()
  local api = moduleApi()
  if not api then return end
  local saved = {}
  for _, m in ipairs(api.order) do
    if not KEEP_RUNNING[m.id] then
      local ok, on = pcall(api.getState, m)
      if ok and on == true then
        saved[#saved + 1] = m.id
        pcall(api.setEnabled, m, false)
      end
    end
  end
  state.pausedModules = saved
end
-- Only what the pause switched off comes back, and only if it is still off: a function the
-- user switched on by hand during the pause is not touched.
local function resumeModules()
  local saved = state.pausedModules
  state.pausedModules = nil
  local api = moduleApi()
  if type(saved) ~= "table" or not api then return end
  for _, id in ipairs(saved) do
    local m = api.modules and api.modules[id]
    if m then
      local ok, on = pcall(api.getState, m)
      if ok and on ~= true then pcall(api.setEnabled, m, true) end
    end
  end
end

function P.setPaused(value)
  value = value == true
  if paused == value then return end
  paused, state.paused = value, value
  if value then
    state.pausedAt = type(os) == "table" and type(os.time) == "function" and os.time() or nil
    -- Stop a native map-click path already submitted by an enabled engine.
    -- g_game.stop is the installed client's walking stop; do not cancel attack.
    local explorer=CaveBot and CaveBot.AutoExplorer
    local exploring=explorer and explorer.isOn and explorer.isOn()
    if (P.desired("cavebot") or P.desired("targetbot") or exploring) and player and g_game and g_game.stop then
      local ok, walking=pcall(function() return player:isWalking() end)
      if ok and walking then pcall(g_game.stop) end
    end
    -- Retire ContainerManager's old automatic resume claim. It cannot resume
    -- a route after a later user decision during this independent pause.
    if storage.cManager then storage.cManager.pausedCave = false end
    if CaveBot and CaveBot.resetWalking then pcall(CaveBot.resetWalking) end
    if TargetBot and TargetBot.walkTo then pcall(TargetBot.walkTo, nil) end
    if TargetBot and TargetBot.Antitrap then pcall(TargetBot.Antitrap.reset) end
    if TargetBot and TargetBot.Creature then pcall(TargetBot.Creature.resetAnchor) end
    pauseModules()
  else
    state.pausedAt = nil
    resumeModules()
  end
  if H and H.refresh then H.refresh() end
end
P.attach("cavebot", CaveBot)
P.attach("targetbot", TargetBot)

-- Lift a stale pause once everything is loaded.
if paused and type(os) == "table" and type(os.time) == "function" and type(schedule) == "function" then
  local at = tonumber(state.pausedAt)
  if at and os.time() - at > STALE_SECONDS then
    local minutes = math.floor((os.time() - at) / 60)
    pcall(schedule, 2500, function()
      if not P.isPaused() then return end
      P.setPaused(false)
      if type(RinoConsole) == "table" and type(RinoConsole.valid) == "function" and RinoConsole.valid() then
        RinoConsole.log("warn", "Pausa", "Bot reanudado: la pausa llevaba " .. minutes .. " min al cargar",
          "Una pausa de mas de " .. math.floor(STALE_SECONDS / 60) .. " min se levanta al cargar para no dejar al personaje sin curacion.")
      end
    end)
  end
end
