local targetBotLure = false
local targetCount = 0 
local delayValue = 0
local lureMax = 0
local anchorPosition = nil
local lastCall = now
local delayFrom = nil
local dynamicLureDelay = false
local lastFaceMove = 0
local lastFaceTurn = 0
local FACE_MOVE_DELAY = 100
local FACE_TURN_DELAY = 100
local FACE_CONFIRM_DELAY = 150
local FACE_HOLD_DELAY = 250
local faceConfirmKey = nil
local faceConfirmAt = 0

local function getCardinalDirection(fromPos, toPos)
  if not fromPos or not toPos or fromPos.z ~= toPos.z then return nil end
  if fromPos.x == toPos.x then
    if toPos.y < fromPos.y then return 0 end
    if toPos.y > fromPos.y then return 2 end
  elseif fromPos.y == toPos.y then
    if toPos.x > fromPos.x then return 1 end
    if toPos.x < fromPos.x then return 3 end
  end
  return nil
end

local function getFacePath(fromPos, toPos, maxPath)
  if fromPos.x == toPos.x and fromPos.y == toPos.y then return {} end
  return findPath(fromPos, toPos, maxPath, {
    ignoreCreatures = false,
    ignoreNonPathable = true,
    precision = 0
  })
end

local function getBestFacePosition(creaturePos, playerPos, desiredRange, maxRange, maxPath)
  local offsets = {
    {x = 0, y = -1},
    {x = 1, y = 0},
    {x = 0, y = 1},
    {x = -1, y = 0}
  }
  local checkedRanges = {}

  for delta = 0, maxRange - 1 do
    local ranges = {desiredRange - delta, desiredRange + delta}
    for _, range in ipairs(ranges) do
      if range >= 1 and range <= maxRange and not checkedRanges[range] then
        checkedRanges[range] = true
        local bestPath

        for _, offset in ipairs(offsets) do
          local candidate = {
            x = creaturePos.x + offset.x * range,
            y = creaturePos.y + offset.y * range,
            z = creaturePos.z
          }
          local tile = g_map.getTile(candidate)
          if tile and tile:isWalkable() and not tileHasCreature(tile) then
            local path = getFacePath(playerPos, candidate, maxPath)
            if path and (not bestPath or #path < #bestPath) then
              bestPath = path
            end
          end
        end

        if bestPath then return bestPath end
      end
    end
  end

  return nil
end

local function resetFaceConfirmation()
  faceConfirmKey = nil
  faceConfirmAt = 0
end

local function holdDirectionalMovement()
  local wasWalking = player:isWalking()

  if CaveBot and CaveBot.isOn and CaveBot.isOn() then
    if CaveBot.resetWalking then CaveBot.resetWalking() end
    if CaveBot.delay then CaveBot.delay(FACE_HOLD_DELAY) end
  end
  if TargetBot and TargetBot.isOn and TargetBot.isOn() and TargetBot.delay then
    TargetBot.delay(FACE_HOLD_DELAY)
  end
  if wasWalking and g_game and g_game.stop then
    pcall(function() g_game.stop() end)
  end

  return wasWalking
end

local function confirmFaceDirection(creature, direction)
  if direction == nil then return false, "direction" end
  if holdDirectionalMovement() then
    resetFaceConfirmation()
    return false, "stopping"
  end

  if player:getDirection() ~= direction then
    resetFaceConfirmation()
    if now - lastFaceTurn >= FACE_TURN_DELAY then
      turn(direction)
      lastFaceTurn = now
    end
    return false, "turning"
  end

  local playerPos = player:getPosition()
  local creaturePos = creature:getPosition()
  local key = creature:getId() .. "|" .. playerPos.x .. "," .. playerPos.y .. "|" ..
    creaturePos.x .. "," .. creaturePos.y .. "|" .. direction
  if faceConfirmKey ~= key then
    faceConfirmKey = key
    faceConfirmAt = now
    return false, "confirming"
  end
  if now - faceConfirmAt < FACE_CONFIRM_DELAY then return false, "confirming" end

  return true, "ready"
end

-- Positions the player on the same row/column as the creature and faces it.
-- Returns true only when a directional spell can be fired at the target.
TargetBot.Creature.alignAndFace = function(creature, options)
  options = options or {}
  if not creature or not creature:getPosition() then return false, "invalid" end

  local creaturePos = creature:getPosition()
  local playerPos = player:getPosition()
  if not playerPos or creaturePos.z ~= playerPos.z then return false, "floor" end

  local maxRange = math.max(1, tonumber(options.maxRange) or 7)
  local maxPath = math.max(1, tonumber(options.maxPath) or 10)
  local currentRange = getDistanceBetween(playerPos, creaturePos)
  local desiredRange = tonumber(options.desiredRange) or currentRange
  desiredRange = math.max(1, math.min(maxRange, desiredRange))

  local direction = getCardinalDirection(playerPos, creaturePos)
  if direction and currentRange <= maxRange then
    return confirmFaceDirection(creature, direction)
  end

  resetFaceConfirmation()
  holdDirectionalMovement()
  local path = getBestFacePosition(creaturePos, playerPos, desiredRange, maxRange, maxPath)
  if path and #path > 0 then
    if not player:isWalking() and now - lastFaceMove >= FACE_MOVE_DELAY then
      safeBotWalk(path[1])
      lastFaceMove = now
    end
    return false, "moving"
  end

  return false, "blocked"
end

TargetBot.Creature.faceDirection = function(creature, direction)
  if not creature or not creature:getPosition() then return false, "invalid" end
  local creaturePos = creature:getPosition()
  local playerPos = player:getPosition()
  if not playerPos or creaturePos.z ~= playerPos.z then return false, "floor" end
  return confirmFaceDirection(creature, direction)
end

TargetBot.Creature.faceCreature = function(creature)
  if not creature or not creature:getPosition() then return false, "invalid" end
  local creaturePos = creature:getPosition()
  local playerPos = player:getPosition()
  if not playerPos or creaturePos.z ~= playerPos.z then return false, "floor" end

  local diffX = creaturePos.x - playerPos.x
  local diffY = creaturePos.y - playerPos.y
  local direction
  if math.abs(diffX) >= math.abs(diffY) and diffX ~= 0 then
    direction = diffX > 0 and 1 or 3
  elseif diffY ~= 0 then
    direction = diffY > 0 and 2 or 0
  end
  return confirmFaceDirection(creature, direction)
end

function getWalkableTilesCount(position)
  local count = 0

  for i, tile in pairs(getNearTiles(position)) do
      if tile:isWalkable() or tileHasCreature(tile) then
          count = count + 1
      end
  end

  return count
end

function rePosition(minTiles)
  minTiles = minTiles or 8
  if now - lastCall < 500 then return end
  local pPos = player:getPosition()
  local tiles = getNearTiles(pPos)
  local playerTilesCount = getWalkableTilesCount(pPos)
  local tilesTable = {}

  if playerTilesCount > minTiles then return end
  for i, tile in ipairs(tiles) do
      tilesTable[tile] = not tileHasCreature(tile) and tile:isWalkable() and getWalkableTilesCount(tile:getPosition()) or nil
  end

  local best = 0
  local target = nil
  for k,v in pairs(tilesTable) do
      if v > best and v > playerTilesCount then
          best = v
          target = k:getPosition()
      end
  end

  if target then
      lastCall = now
      return CaveBot.GoTo(target, 0)
  end
end

TargetBot.Creature.attack = function(params, targets, isLooting) -- params {config, creature, danger, priority}
  if player:isWalking() then
    lastWalk = now
  end

  local config = params.config
  local creature = params.creature
  
  if g_game.getAttackingCreature() ~= creature then
    g_game.attack(creature)
  end

  if not isLooting then -- walk only when not looting
    local walkState = TargetBot.Creature.walk(creature, config, targets)
    if walkState == "facePending" then return end
  end

  -- attacks
  local mana = player:getMana()
  if config.useGroupAttack and config.groupAttackSpell:len() > 1 and mana > config.minManaGroup then
    local creatures = g_map.getSpectatorsInRange(player:getPosition(), false, config.groupAttackRadius, config.groupAttackRadius)
    local playersAround = false
    local monsters = 0
    for _, creature in ipairs(creatures) do
      if not creature:isLocalPlayer() and creature:isPlayer() and (not config.groupAttackIgnoreParty or creature:getShield() <= 2) then
        playersAround = true
      elseif creature:isMonster() then
        monsters = monsters + 1
      end
    end
    if monsters >= config.groupAttackTargets and (not playersAround or config.groupAttackIgnorePlayers) then
      if TargetBot.sayAttackSpell(config.groupAttackSpell, config.groupAttackDelay) then
        return
      end
    end
  end

  if config.useGroupAttackRune and config.groupAttackRune > 100 then
    local creatures = g_map.getSpectatorsInRange(creature:getPosition(), false, config.groupRuneAttackRadius, config.groupRuneAttackRadius)
    local playersAround = false
    local monsters = 0
    for _, creature in ipairs(creatures) do
      if not creature:isLocalPlayer() and creature:isPlayer() and (not config.groupAttackIgnoreParty or creature:getShield() <= 2) then
        playersAround = true
      elseif creature:isMonster() then
        monsters = monsters + 1
      end
    end
    if monsters >= config.groupRuneAttackTargets and (not playersAround or config.groupAttackIgnorePlayers) then
      if TargetBot.useAttackItem(config.groupAttackRune, 0, creature, config.groupRuneAttackDelay) then
        return
      end
    end
  end
  if config.useSpellAttack and config.attackSpell:len() > 1 and mana > config.minMana then
    if TargetBot.sayAttackSpell(config.attackSpell, config.attackSpellDelay) then
      return
    end
  end
  if config.useRuneAttack and config.attackRune > 100 then
    if TargetBot.useAttackItem(config.attackRune, 0, creature, config.attackRuneDelay) then
      return
    end
  end
end

TargetBot.Creature.walk = function(creature, config, targets)
  local cpos = creature:getPosition()
  local pos = player:getPosition()
  
  local isTrapped = true
  local pos = player:getPosition()
  local dirs = {{-1,1}, {0,1}, {1,1}, {-1, 0}, {1, 0}, {-1, -1}, {0, -1}, {1, -1}}
  for i=1,#dirs do
    local tile = g_map.getTile({x=pos.x-dirs[i][1],y=pos.y-dirs[i][2],z=pos.z})
    if tile and tile:isWalkable(false) then
      isTrapped = false
    end
  end

  -- data for external dynamic lure
  if config.lureMin and config.lureMax and config.dynamicLure then
    if config.lureMin >= targets then
      targetBotLure = true
    elseif targets >= config.lureMax then
      targetBotLure = false
    end
  end
  targetCount = targets
  delayValue = config.lureDelay

  if config.lureMax then
    lureMax = config.lureMax
  end

  dynamicLureDelay = config.dynamicLureDelay
  delayFrom = config.delayFrom

  -- luring
  if config.closeLure and config.closeLureAmount <= getMonsters(1) then
    return TargetBot.allowCaveBot(150)
  end
  if TargetBot.canLure() and (config.lure or config.lureCavebot or config.dynamicLure) and not (creature:getHealthPercent() < (storage.extras.killUnder or 30)) and not isTrapped then
    if targetBotLure then
      anchorPosition = nil
      return TargetBot.allowCaveBot(150)
    else
      if targets < config.lureCount then
        if config.lureCavebot then
          anchorPosition = nil
          return TargetBot.allowCaveBot(150)
        else
          local path = findPath(pos, cpos, 5, {ignoreNonPathable=true, precision=2})
          if path then
            return TargetBot.walkTo(cpos, 10, {marginMin=5, marginMax=6, ignoreNonPathable=true})
          end
        end
      end
    end
  end

  if config.faceMonster and not config.avoidAttacks then
    local desiredRange = config.keepDistance and config.keepDistanceRange or getDistanceBetween(pos, cpos)
    local ready = TargetBot.Creature.alignAndFace(creature, {
      desiredRange = desiredRange,
      maxRange = config.maxDistance or 10,
      maxPath = 10
    })
    if not ready then return "facePending" end
  end

  local currentDistance = findPath(pos, cpos, 10, {ignoreCreatures=true, ignoreNonPathable=true, ignoreCost=true})
  if (not config.chase or #currentDistance == 1) and not config.avoidAttacks and not config.keepDistance and config.rePosition and (creature:getHealthPercent() >= storage.extras.killUnder) then
    return rePosition(config.rePositionAmount or 6)
  end
  if ((storage.extras.killUnder > 1 and (creature:getHealthPercent() < storage.extras.killUnder)) or config.chase) and not config.keepDistance then
    if #currentDistance > 1 then
      return TargetBot.walkTo(cpos, 10, {ignoreNonPathable=true, precision=1})
    end
  elseif config.keepDistance then
    if not anchorPosition or distanceFromPlayer(anchorPosition) > config.anchorRange then
      anchorPosition = pos
    end
    if #currentDistance ~= config.keepDistanceRange and #currentDistance ~= config.keepDistanceRange + 1 then
      if config.anchor and anchorPosition and getDistanceBetween(pos, anchorPosition) <= config.anchorRange*2 then
        return TargetBot.walkTo(cpos, 10, {ignoreNonPathable=true, marginMin=config.keepDistanceRange, marginMax=config.keepDistanceRange + 1, maxDistanceFrom={anchorPosition, config.anchorRange}})
      else
        return TargetBot.walkTo(cpos, 10, {ignoreNonPathable=true, marginMin=config.keepDistanceRange, marginMax=config.keepDistanceRange + 1})
      end
    end
  end

  --target only movement
  if config.avoidAttacks then
    local diffx = cpos.x - pos.x
    local diffy = cpos.y - pos.y
    local candidates = {}
    if math.abs(diffx) == 1 and diffy == 0 then
      candidates = {{x=pos.x, y=pos.y-1, z=pos.z}, {x=pos.x, y=pos.y+1, z=pos.z}}
    elseif diffx == 0 and math.abs(diffy) == 1 then
      candidates = {{x=pos.x-1, y=pos.y, z=pos.z}, {x=pos.x+1, y=pos.y, z=pos.z}}
    end
    for _, candidate in ipairs(candidates) do
      local tile = g_map.getTile(candidate)
      if tile and tile:isWalkable() then
        return TargetBot.walkTo(candidate, 2, {ignoreNonPathable=true})
      end
    end
  end
end

onPlayerPositionChange(function(newPos, oldPos)
  if CaveBot.isOff() then return end
  if TargetBot.isOff() then return end
  if not lureMax then return end
  if storage.TargetBotDelayWhenPlayer then return end
  if not dynamicLureDelay then return end

  if targetCount < (delayFrom or lureMax/2) or not target() then return end
  CaveBot.delay(delayValue or 0)
end)
