-- walking
local expectedDirs = {}
local isWalking = {}
local walkPath = {}
local walkPathIter = 0

CaveBot.resetWalking = function()
  expectedDirs = {}
  walkPath = {}
  isWalking = false
end

-- Protect route steps before sending them, including a map-click path's first step.
CaveBot.protectStep = function(direction)
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
  if #expectedDirs == 0 then
    return false
  end
  if #expectedDirs >= 3 then
    CaveBot.resetWalking()
  end
  local dir = walkPath[walkPathIter]
  if dir then
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
  
  local dirs = {{NorthWest, North, NorthEast}, {West, 8, East}, {SouthWest, South, SouthEast}}
  local dir = dirs[newPos.y - oldPos.y + 2]
  if dir then
    dir = dir[newPos.x - oldPos.x + 2]
  end
  if not dir then
    dir = 8 -- 8 is invalid dir, it's fine
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
  if CaveBot.Config.get("mapClick") and #expectedDirs > 0 then
    CaveBot.delay(CaveBot.Config.get("mapClickDelay") + player:getStepDuration(false, dir))
  end
end)

CaveBot.walkTo = function(dest, maxDist, params)
  local path = getPath(player:getPosition(), dest, maxDist, params)
  if not path or not path[1] then
    return false
  end
  local dir = path[1]
  if not CaveBot.protectStep(dir) then return true end -- Safety is handling this step; retry the same waypoint.
  local protected=TargetBot and TargetBot.Antitrap and TargetBot.Antitrap.protecting()
  
  if CaveBot.Config.get("mapClick") and not protected then
    local ok, ret = pcall(function()
      return autoWalk(path)
    end)
    if not ok or ret == nil or ret == false then
      ret = safeBotWalk(dir)
    end
    if ret then
      isWalking = true
      expectedDirs = path
      CaveBot.delay(CaveBot.Config.get("mapClickDelay") + math.max(CaveBot.Config.get("ping") + player:getStepDuration(false, dir), player:getStepDuration(false, dir) * 2))
    end
    return ret
  end
  
  if safeBotWalk(dir)==false then CaveBot.delay(100);return true end
  isWalking = true    
  walkPath = path
  walkPathIter = 2
  expectedDirs = { dir }
  CaveBot.delay(CaveBot.Config.get("walkDelay") + player:getStepDuration(false, dir))
  return true
end
