-- walking
local expectedDirs = {}
local isWalking = {}
local walkPath = {}
local walkPathIter = 0

-- Mixed walking (per profile "Caminata mixta", only with mapClick off): a clear
-- stretch of the planned path (4-8 tiles with no creature on or next to it, no
-- stairs, holes, fields or remembered traps, and no monster within 8 SQM) is sent
-- as one native autoWalk. Every tick the next tiles are watched; as soon as
-- something appears, or the walk stalls, the leg is stopped and the goto goes on
-- step by step. Anything that resets the CaveBot's walking also stops the leg.
local MIXED_MIN, MIXED_MAX, MIXED_AHEAD, MIXED_MONSTER = 4, 8, 2, 8
local MIXED_OFFSETS = {[0]={0,-1},{1,0},{0,1},{-1,0},{1,-1},{1,1},{-1,1},{-1,-1}}
local MIXED_REPORT = 600000
local mixedLeg = nil
local mixedStats = {legs=0, steps=0, cut=0, reportAt=nil}
CaveBot.MixedWalk = {}
CaveBot.MixedWalk.enabled = function()
  return type(storage)=='table' and type(storage.extras)=='table' and storage.extras.walkMixed==true and
    not CaveBot.Config.get("mapClick")
end
CaveBot.MixedWalk.stats = function()
  return {legs=mixedStats.legs, steps=mixedStats.steps, cut=mixedStats.cut, active=mixedLeg~=nil}
end

CaveBot.resetWalking = function()
  if mixedLeg then
    mixedLeg = nil
    if #expectedDirs > 0 and g_game and type(g_game.stop)=='function' then pcall(g_game.stop) end
  end
  expectedDirs = {}
  walkPath = {}
  isWalking = false
end

local function mixedFlag(object, name)
  if not object or type(object[name])~='function' then return false end
  local ok, value = pcall(object[name], object)
  return ok and value==true
end
-- Positions of the other creatures on screen; nil when a living monster is near.
local function mixedCrowd(origin)
  if type(getSpectators)~='function' then return nil end
  local okList, list = pcall(getSpectators, false)
  if not okList or type(list)~='table' then return nil end
  local crowd = {}
  local okId, selfId = pcall(function() return player:getId() end)
  -- Players never block inside a protection zone.
  local pz = CaveBot.PlayerBlocker and CaveBot.PlayerBlocker.inPz and CaveBot.PlayerBlocker.inPz()
  for _, creature in pairs(list) do
    local ok, pos, monster, health, own = pcall(function()
      local mine = creature == player or (okId and creature:getId() == selfId) or (pz and creature:isPlayer())
      return creature:getPosition(), creature:isMonster(), creature:getHealthPercent(), mine
    end)
    if ok and not own and type(pos)=='table' and not (pos.x==origin.x and pos.y==origin.y and pos.z==origin.z) then
      if monster and (tonumber(health) or 100) > 0 and pos.z==origin.z and
          math.max(math.abs(pos.x-origin.x), math.abs(pos.y-origin.y)) <= MIXED_MONSTER then
        return nil
      end
      crowd[#crowd+1] = pos
    end
  end
  return crowd
end
-- A tile the server may cross on its own: seen, walkable, no floor change, field
-- or remembered trap, and no creature within `radius` of it.
local function mixedClear(p, crowd, radius)
  local ok, clear = pcall(function()
    -- Creatures are checked through `crowd`, so our own (pre-walking) creature never blocks.
    local tile = g_map.getTile(p)
    if not tile or not tile:isWalkable(true) then return false end
    local color = tonumber(g_map.getMinimapColor(p)) or 0
    if color >= 210 and color <= 213 then return false end
    if mixedFlag(tile, 'isFloorChange') or mixedFlag(tile:getGround(), 'isFloorChange') then return false end
    local movement = TargetBot and TargetBot.Movement
    if movement and movement.floorSafe and not movement.floorSafe(p, tile) then return false end
    for _, item in ipairs(tile:getItems() or {}) do
      if mixedFlag(item, 'isFloorChange') or (movement and movement.isDamageField and movement.isDamageField(item)) then
        return false
      end
    end
    local trap = CaveBot.FloorReturn and CaveBot.FloorReturn.isTrap
    if trap and trap(p) then return false end
    for _, c in ipairs(crowd) do
      if c.z==p.z and math.max(math.abs(c.x-p.x), math.abs(c.y-p.y)) <= radius then return false end
    end
    return true
  end)
  return ok and clear==true
end
-- The clear first stretch of `path`, or nil when it is too short to be worth a click.
local function mixedLegFor(origin, path)
  if not CaveBot.MixedWalk.enabled() or #path < MIXED_MIN then return nil end
  if type(autoWalk)~='function' or not g_game or type(g_game.stop)~='function' then return nil end
  if CaveBot.PlayerBlocker and CaveBot.PlayerBlocker.isActive() then return nil end
  local crowd = mixedCrowd(origin)
  if not crowd then return nil end
  local p, count = origin, 0
  for i = 1, math.min(#path, MIXED_MAX) do
    local o = MIXED_OFFSETS[path[i]]
    if not o then break end
    p = {x=p.x+o[1], y=p.y+o[2], z=p.z}
    if not mixedClear(p, crowd, 1) then break end
    count = i
  end
  if count < MIXED_MIN then return nil end
  local leg = {}
  for i = 1, count do leg[i] = path[i] end
  return leg
end
local function mixedReport()
  if not mixedStats.reportAt then mixedStats.reportAt = now + MIXED_REPORT; return end
  if now < mixedStats.reportAt or mixedStats.legs == 0 then return end
  mixedStats.reportAt = now + MIXED_REPORT
  if RinoConsole and type(RinoConsole.log)=='function' then
    pcall(RinoConsole.log, 'action', 'CaveBot', 'Caminata mixta: ' .. mixedStats.legs .. ' tramos con clic (' ..
      mixedStats.steps .. ' pasos), ' .. mixedStats.cut .. ' cortados por seguridad')
  end
end
-- Inside a protection zone players can be walked through: the straight path that
-- only crosses players (never an NPC or a monster) is used instead of a detour.
-- Crossing a player takes the server a few refused steps, so a free path at most
-- PlayerBlocker.PZ_FREE_EXTRA steps longer is still preferred, and a player the server
-- already refused to let us through (PlayerBlocker.crossRefused) is not crossed again.
local function pzThrough(dest, maxDist, params, free)
  local blocker = CaveBot.PlayerBlocker
  if params.ignoreCreatures or not (blocker and blocker.inPz and blocker.inPz()) then
    return nil
  end
  local PZ_FREE_EXTRA = tonumber(blocker.PZ_FREE_EXTRA) or 4
  local through = {}
  for key, value in pairs(params) do through[key] = value end
  through.ignoreCreatures = true
  local origin = player:getPosition()
  local path = getPath(origin, dest, maxDist, through)
  if not path or not path[1] then return nil end
  -- The client may count players here as passable, so the "free" path can cross them too.
  local crosses = blocker.crossesPlayer
  if free and free[1] and #free <= #path + PZ_FREE_EXTRA and not (crosses and crosses(origin, free)) then return nil end
  local ok, onlyPlayers = pcall(function()
    local p = origin
    for _, dir in ipairs(path) do
      local o = MIXED_OFFSETS[dir]
      if not o then return false end
      p = {x=p.x+o[1], y=p.y+o[2], z=p.z}
      if blocker.crossRefused and blocker.crossRefused(p) then return false end
      local tile = g_map.getTile(p)
      for _, creature in ipairs(tile and tile:getCreatures() or {}) do
        if creature ~= player and not mixedFlag(creature, 'isLocalPlayer') and not mixedFlag(creature, 'isPlayer') then return false end
      end
    end
    return true
  end)
  if ok and onlyPlayers then return path end
  return nil
end
-- While a leg runs: count its steps, stop it when it stalls or the next tiles stop being clear.
local function mixedTick()
  local leg = mixedLeg
  if #expectedDirs == 0 then
    mixedLeg = nil
    CaveBot.pathWalkUntil = nil
    return false
  end
  if #expectedDirs < leg.left then
    mixedStats.steps = mixedStats.steps + leg.left - #expectedDirs
    leg.left, leg.progressAt = #expectedDirs, now
  end
  local step = tonumber(player:getStepDuration(false, expectedDirs[1])) or 200
  local ping = tonumber(CaveBot.Config.get("ping")) or 100
  local origin = player:getPosition()
  local crowd = now - leg.progressAt <= step * 2 + ping + 400 and mixedCrowd(origin)
  local clear = crowd ~= nil and crowd ~= false
  local p = origin
  for i = 1, math.min(MIXED_AHEAD, #expectedDirs) do
    if not clear then break end
    local o = MIXED_OFFSETS[expectedDirs[i]]
    if not o then clear = false; break end
    p = {x=p.x+o[1], y=p.y+o[2], z=p.z}
    clear = mixedClear(p, crowd, 0)
  end
  if not clear then
    mixedStats.cut = mixedStats.cut + 1
    CaveBot.resetWalking()
    return false
  end
  return true
end

-- Preserve Dynamic Pause's ability to stop only CaveBot's own map-click leg.
CaveBot.stopPathWalk=function()
  local untilAt=CaveBot.pathWalkUntil
  CaveBot.pathWalkUntil=nil
  if untilAt and #expectedDirs>0 and now<untilAt and g_game.stop then
    pcall(g_game.stop)
    CaveBot.resetWalking()
  end
end

-- Protect route steps before sending them, including a map-click path's first step.
CaveBot.protectStep = function(direction)
  if CaveBot.Flee and CaveBot.Flee.isEscaping() then return true end
  local antitrap=TargetBot and TargetBot.Antitrap
  if not antitrap then return true end
  local escape=antitrap.refresh(player:getPosition(),now)
  if (escape or antitrap.protecting()) and CaveBot.Config.get('mapClick') then
    CaveBot._safetySteppedGoto=true -- This waypoint now advances through individual checked steps.
  end
  if escape then
    antitrap.send(escape,now)
    CaveBot.delay(100)
    return false
  end
  if not antitrap.protecting() then return true end
  if antitrap.ownsMovement() or player:isWalking() then CaveBot.delay(100);return false end
  local allowed=antitrap.guardStep(player:getPosition(),direction)
  if allowed==direction then return true end
  CaveBot.resetWalking()
  if allowed~=nil then antitrap.send({step=allowed},now) end
  CaveBot.delay(100)
  return false
end

CaveBot.doWalking = function()
  if CaveBot.Config.get("mapClick") then
    return false
  end
  if mixedLeg then return mixedTick() end
  if #expectedDirs == 0 then
    return false
  end
  if #expectedDirs >= 3 then
    CaveBot.resetWalking()
  end
  local dir = walkPath[walkPathIter]
  if dir then
    if CaveBot.PlayerBlocker then
      local handled, closed = CaveBot.PlayerBlocker.beforeStep(dir,walkPath,walkPathIter)
      if handled then return true end
      if closed then CaveBot.resetWalking(); return false end -- the goto decides what next
    end
    if not CaveBot.protectStep(dir) then return true end -- Wait; do not advance the route.
    if safeBotWalk(dir)==false then CaveBot.delay(100);return true end
    table.insert(expectedDirs, dir)
    walkPathIter = walkPathIter + 1
    CaveBot.delay(CaveBot.Config.get("walkDelay") + player:getStepDuration(false, dir))
    return true
  end
  return false  
end

-- called when player position has been changed (step has been confirmed by server)
onPlayerPositionChange(function(newPos, oldPos)
  if not oldPos or not newPos then return end
  if CaveBot.Flee and CaveBot.Flee.isEscaping() then
    CaveBot.wakeRoute(false);return
  end
  
  local dirs = {{NorthWest, North, NorthEast}, {West, 8, East}, {SouthWest, South, SouthEast}}
  local dir = dirs[newPos.y - oldPos.y + 2]
  if dir then
    dir = dir[newPos.x - oldPos.x + 2]
  end
  if not dir then
    dir = 8 -- 8 is invalid dir, it's fine
  end
  if CaveBot.pathWalkUntil and (oldPos.z~=newPos.z or expectedDirs[1]~=dir)then
    CaveBot.pathWalkUntil=nil
  end
  -- Our own step through a player in a protection zone: go on at walking pace.
  if CaveBot.PlayerBlocker and CaveBot.PlayerBlocker.crossed and CaveBot.PlayerBlocker.crossed(newPos, oldPos) then
    walkPath = {}
    CaveBot.delay(CaveBot.Config.get("walkDelay") + player:getStepDuration(false, dir))
    return
  end

  if not isWalking or not expectedDirs[1] then
    -- some other walk action is taking place (for example use on ladder), wait
    walkPath = {}
    CaveBot.delay(CaveBot.Config.get("ping") + player:getStepDuration(false, dir) + 150)
    return
  end
  
  if expectedDirs[1] ~= dir then
    if CaveBot.Config.get("mapClick") then
      CaveBot.delay(CaveBot.Config.get("walkDelay") + player:getStepDuration(false, dir))
    else
      CaveBot.delay(CaveBot.Config.get("mapClickDelay") + player:getStepDuration(false, dir))
    end
    return
  end
  
  table.remove(expectedDirs, 1)  
  if #expectedDirs==0 then CaveBot.pathWalkUntil=nil end
  if CaveBot.Config.get("mapClick") and #expectedDirs > 0 then
    CaveBot.delay(CaveBot.Config.get("mapClickDelay") + player:getStepDuration(false, dir))
  end
end)

CaveBot.walkTo = function(dest, maxDist, params)
  local options = {}
  for key,value in pairs(params or {}) do options[key] = value end
  options.ignoreFields,options.ignoreNonPathable = true,true
  params = options
  if CaveBot.Flee and CaveBot.Flee.isEscaping() then return CaveBot.Flee.walkTo(dest,maxDist,params) end
  local path = getPath(player:getPosition(), dest, maxDist, params)
  path = pzThrough(dest, maxDist, params, path) or path
  -- Remembered traps (cavebot/floor_return.lua): walk around them, or stop before one.
  if path and path[1] and CaveBot.FloorReturn and CaveBot.FloorReturn.avoidTraps then
    path = CaveBot.FloorReturn.avoidTraps(player:getPosition(), path)
  end
  if not path or not path[1] then
    return false
  end
  local dir = path[1]
  if CaveBot.PlayerBlocker then
    local handled, closed = CaveBot.PlayerBlocker.beforeStep(dir,path,1)
    if handled then return true end
    if closed then return false end
  end
  if not CaveBot.protectStep(dir) then return true end -- Safety is handling this step; retry the same waypoint.
  local protected=TargetBot and TargetBot.Antitrap and TargetBot.Antitrap.protecting()
  -- The TargetBot's Dynamic Pause now waits for the pull by stopping the autoWalk itself
  -- (targetbot/creature_attack.lua), so mapClick paths stay fluid.
  local paced=false

  if CaveBot.Config.get("mapClick") and not protected and not paced then
    local ok, ret = pcall(function()
      return autoWalk(path)
    end)
    if ok and ret~=false then
      isWalking = true
      expectedDirs = path
      -- The Dynamic Pause stops only this CaveBot leg (not Follow, manual or spell steps).
      CaveBot.pathWalkUntil = now + #path * math.max(100, player:getStepDuration(false, dir)) + 500
      CaveBot.delay(CaveBot.Config.get("mapClickDelay") + math.max(CaveBot.Config.get("ping") + player:getStepDuration(false, dir), player:getStepDuration(false, dir) * 2))
      return true
    end
  end

  if not protected then
    local leg = mixedLegFor(player:getPosition(), path)
    local ok, ret = false, false
    if leg then ok, ret = pcall(autoWalk, leg) end
    if ok and ret ~= false then
      isWalking = true
      expectedDirs = {}
      for i, step in ipairs(leg) do expectedDirs[i] = step end
      walkPath = {}
      mixedLeg = {left = #leg, progressAt = now}
      mixedStats.legs = mixedStats.legs + 1
      mixedReport()
      -- The Dynamic Pause can stop this leg like a map-click one.
      CaveBot.pathWalkUntil = now + #leg * math.max(100, player:getStepDuration(false, dir)) + 500
      CaveBot.delay(100)
      return true
    end
  end

  if safeBotWalk(dir)==false then CaveBot.delay(100);return true end
  isWalking = true
  walkPath = path
  walkPathIter = 2
  expectedDirs = { dir }
  CaveBot.delay(CaveBot.Config.get("walkDelay") + player:getStepDuration(false, dir))
  return true
end
