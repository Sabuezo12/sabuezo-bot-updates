-- Local, non-destructive gate: only CaveBot and TargetBot. Underlying profile
-- switches keep their intended state, including hotkey changes while paused.
HelperPause = {}
local P, H = HelperPause, Helper
storage.helperUI = type(storage.helperUI) == "table" and storage.helperUI or {}
local state = storage.helperUI
local paused = state.paused == true
local engines = {}
function P.isPaused() return paused end
function P.desired(id)
  local e = engines[id]
  if not e then return nil end
  local ok, enabled = pcall(e.isOn)
  if ok then return enabled == true end
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
function P.setPaused(value)
  value = value == true
  if paused == value then return end
  paused, state.paused = value, value
  if value then
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
  end
  if H and H.refresh then H.refresh() end
end
P.attach("cavebot", CaveBot)
P.attach("targetbot", TargetBot)
