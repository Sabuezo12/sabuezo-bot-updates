local targetBotLure = false
local lureRule,lureHolding=nil,false
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
local FACE_HOLD_DELAY = 250
local faceConfirmKey = nil
local faceConfirmAt = 0

local function manualMovement()
  return TargetBot.Movement and TargetBot.Movement.isManual and TargetBot.Movement.isManual()
end
local function walkableTile(tile)
  if TargetBot.Movement and TargetBot.Movement.walkableTile then return TargetBot.Movement.walkableTile(tile,false) end
  return tile and tile:isWalkable(false)==true or false
end

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

local function getFacePath(fromPos, toPos, maxPath, options)
  if fromPos.x == toPos.x and fromPos.y == toPos.y then return {} end
  local params={
    ignoreCreatures = false,
    ignoreNonPathable = true,
    ignoreStairs = false,
    ignoreCost = false,
    allowOnlyVisibleTiles = true,
    precision = 0,
    maxDistanceFrom = options.maxDistanceFrom
  }
  local path
  if options.strictRange and TargetBot.Movement then
    path=TargetBot.Movement.findPath(fromPos,toPos,maxPath,params)
  else path=findPath(fromPos,toPos,maxPath,params) end
  if TargetBot.Movement and not TargetBot.Movement.pathSafe(fromPos,path,options.maxDistanceFrom) then return nil end
  return path
end

local function getBestFacePosition(creaturePos, playerPos, desiredRange, maxRange, maxPath, options)
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
      if range >= 1 and range <= maxRange and not checkedRanges[range]
        and (not options.strictRange or range == desiredRange) then
        checkedRanges[range] = true
        local bestPath

        for _, offset in ipairs(offsets) do
          local candidate = {
            x = creaturePos.x + offset.x * range,
            y = creaturePos.y + offset.y * range,
            z = creaturePos.z
          }
          local tile = g_map.getTile(candidate)
          local boundary = options.maxDistanceFrom
          local inside = not boundary or getDistanceBetween(candidate, boundary[1]) <= boundary[2]
          if inside and walkableTile(tile) and not tileHasCreature(tile)
            and (not TargetBot.Movement or TargetBot.Movement.floorSafe(candidate,tile)) then
            local path = getFacePath(playerPos, candidate, maxPath, options)
            local preferred=path and (not bestPath or
              options.strictRange and TargetBot.Movement and TargetBot.Movement.preferPath(path,bestPath) or
              not options.strictRange and #path<#bestPath)
            if preferred then
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
  local explorer=CaveBot and CaveBot.AutoExplorer
  if explorer and explorer.isOn and explorer.isOn() and explorer.holdMovement then
    explorer.holdMovement(FACE_HOLD_DELAY)
  end

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
  if manualMovement() then return player:getDirection()==direction, 'manual' end
  if TargetBot.Antitrap and TargetBot.Antitrap.ownsMovement() then
    return player:getDirection() == direction, "antitrap"
  end
  local combat=ComboFollowCombat and ComboFollowCombat.getState and ComboFollowCombat.getState()
  if combat and combat.active then
    if not combat.ready then return player:getDirection()==direction, 'followingLeader' end
    if not ComboFollowCombat.acquire() then return false, 'followingLeader' end
  end
  if holdDirectionalMovement() then
    resetFaceConfirmation()
    return false, "stopping"
  end

  if player:getDirection() ~= direction then
    resetFaceConfirmation()
    if now - lastFaceTurn >= FACE_TURN_DELAY then
      if AttackAlignment and AttackAlignment.face then AttackAlignment.face(direction)
      else turn(direction) end
      lastFaceTurn = now
    end
    if player:getDirection() == direction then return true, "ready" end
    return false, "turning"
  end

  local playerPos = player:getPosition()
  local creaturePos = creature:getPosition()
  local key = creature:getId() .. "|" .. playerPos.x .. "," .. playerPos.y .. "|" ..
    creaturePos.x .. "," .. creaturePos.y .. "|" .. direction
  if faceConfirmKey ~= key then
    faceConfirmKey = key
    faceConfirmAt = now
  end
  -- Native position/direction are sufficient; do not add a 150ms confirmation wait.

  return true, "ready"
end

local function caveAllowsAlignment()
  local explorer=CaveBot and CaveBot.AutoExplorer
  return explorer and explorer.isOn and explorer.isOn() or
    CaveBot and type(CaveBot.isOn)=='function' and CaveBot.isOn()==true
end
TargetBot.Creature.faceWithoutMoving = function(creature)
  if not creature then return false, 'invalid' end
  local from,to=player:getPosition(),creature:getPosition()
  if not from or not to or from.z~=to.z then return false, 'floor' end
  local dx,dy=to.x-from.x,to.y-from.y
  if dx==0 and dy==0 then return true,'ready' end
  local direction=math.abs(dx)>=math.abs(dy) and (dx>0 and 1 or 3) or (dy>0 and 2 or 0)
  if manualMovement() then return player:getDirection()==direction, 'manual' end
  local combat=ComboFollowCombat and ComboFollowCombat.getState and ComboFollowCombat.getState()
  if combat and combat.active and not combat.ready then return player:getDirection()==direction, 'followingLeader' end
  if player:getDirection()~=direction then
    if AttackAlignment and AttackAlignment.face then AttackAlignment.face(direction)
    elseif now-lastFaceTurn>=FACE_TURN_DELAY then turn(direction);lastFaceTurn=now end
  end
  return player:getDirection()==direction, 'facing'
end

-- Positions the player on the same row/column as the creature and faces it.
-- Returns true only when a directional spell can be fired at the target.
TargetBot.Creature.alignAndFace = function(creature, options)
  options = options or {}
  if manualMovement() then resetFaceConfirmation();return false, 'manual' end
  if not creature or not creature:getPosition() then return false, "invalid" end

  local creaturePos = creature:getPosition()
  local playerPos = player:getPosition()
  if not playerPos or creaturePos.z ~= playerPos.z then return false, "floor" end

  local combat=ComboFollowCombat and ComboFollowCombat.getState and ComboFollowCombat.getState()
  if combat and combat.active then return TargetBot.Creature.faceWithoutMoving(creature) end
  if not caveAllowsAlignment() then return TargetBot.Creature.faceWithoutMoving(creature) end

  local maxRange = math.max(1, tonumber(options.maxRange) or 7)
  local maxPath = math.max(1, tonumber(options.maxPath) or 10)
  local currentRange = getDistanceBetween(playerPos, creaturePos)
  local desiredRange = tonumber(options.desiredRange) or currentRange
  desiredRange = math.max(1, math.min(maxRange, desiredRange))

  local direction = getCardinalDirection(playerPos, creaturePos)
  if TargetBot.Antitrap and TargetBot.Antitrap.ownsMovement() and not direction then return false, "antitrap" end
  if direction and currentRange <= maxRange and (not options.strictRange or currentRange == desiredRange) then
    return confirmFaceDirection(creature, direction)
  end

  resetFaceConfirmation()
  holdDirectionalMovement()
  local path = getBestFacePosition(creaturePos, playerPos, desiredRange, maxRange, maxPath, options)
  if path and #path > 0 then
    if not player:isWalking() and now - lastFaceMove >= FACE_MOVE_DELAY then
      local direction=path[1]
      if TargetBot.Antitrap then direction=TargetBot.Antitrap.guardStep(playerPos,direction) end
      if direction~=nil and TargetBot.Movement and not TargetBot.Movement.canStep(playerPos,direction) then direction=nil end
      if direction~=nil then
        if TargetBot.Antitrap and TargetBot.Antitrap.ownsMovement() then
          TargetBot.Antitrap.send({step=direction},now)
        else
          safeBotWalk(direction)
        end
      end
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
      if walkableTile(tile) or tileHasCreature(tile) then
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
      tilesTable[tile] = not tileHasCreature(tile) and walkableTile(tile) and getWalkableTilesCount(tile:getPosition()) or nil
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

TargetBot.Creature.attack = function(params, targets, isLooting, movementControlled) -- params {config, creature, danger, priority}
  -- A delayed TargetBot cycle must never issue a new attack after the bot was disabled.
  if not TargetBot.isOn or not TargetBot.isOn() then return end

  if player:isWalking() then
    lastWalk = now
  end

  local config = params.config
  local creature = params.creature
  if (isLooting or movementControlled) and AttackBot and AttackBot.clearSpellMovement then AttackBot.clearSpellMovement() end
  
  if g_game.getAttackingCreature() ~= creature then
    -- Native attack() stops LocalPlayer's mouse destination. Keep existing
    -- autoattacks, but defer a new attack command while a pointer move owns it.
    if TargetBot.Movement and TargetBot.Movement.isPointerManual and TargetBot.Movement.isPointerManual() then return end
    g_game.attack(creature)
  end

  if not isLooting and not movementControlled then -- walk only when not looting
    local walkState = TargetBot.Creature.walk(creature, config, params.lureTargets or targets)
    if walkState == "facePending" then return end
  end

  -- AttackBot owns spells and runes while enabled, including temporary pauses.
  -- Target selection, normal attacks and movement above remain active.
  if AttackBot and type(AttackBot.isOn) == 'function' and AttackBot.isOn() then return end

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

local function isTrappedAt(pos)
  local isTrapped = true
  local dirs = {{-1,1}, {0,1}, {1,1}, {-1, 0}, {1, 0}, {-1, -1}, {0, -1}, {1, -1}}
  for i=1,#dirs do
    local tile = g_map.getTile({x=pos.x-dirs[i][1],y=pos.y-dirs[i][2],z=pos.z})
    if walkableTile(tile) then
      isTrapped = false
    end
  end
  return isTrapped
end

TargetBot.Creature.resetAnchor = function() anchorPosition = nil end

-- Capture the combat centre before an emergency can move the character.
-- Leaving its radius never replaces it; gathering the next pull releases it.
TargetBot.Creature.prepareMovement = function(creature, config, targets)
  local pos = player and player:getPosition()
  if manualMovement() or not creature or not config or not pos then
    TargetBot.Creature.resetAnchor()
    lureRule=nil;lureHolding=false;targetBotLure=false
    return
  end
  -- A temporarily unshootable scene is not proof that the pull has ended.
  targets = targets or targetCount
  -- Hysteresis belongs to this rule. The upper bound wins even for old
  -- imported min==max settings, and a previous rule cannot leak gather mode.
  if config.dynamicLure then
    local maximum=math.max(1,tonumber(config.lureMax)or 3)
    local minimum=math.max(0,math.min(maximum-1,tonumber(config.lureMin)or 1))
    if lureRule~=config then targetBotLure=targets<maximum end
    if targets>=maximum then targetBotLure=false
    elseif targets<=minimum then targetBotLure=true end
  else targetBotLure=false end
  lureRule=config
  local holding=config.dynamicLure==true and not targetBotLure and TargetBot.canLure()
  if holding and not lureHolding and TargetBot.holdCaveBot then TargetBot.holdCaveBot(true)end
  lureHolding=holding
  targetCount = targets
  delayValue = config.lureDelay

  if config.lureMax then
    lureMax = config.lureMax
  end

  dynamicLureDelay = config.dynamicLureDelay
  delayFrom = config.delayFrom

  if not config.keepDistance or not config.anchor then
    TargetBot.Creature.resetAnchor()
    return
  end
  local gathering = not lureHolding and config.closeLure and config.closeLureAmount <= getMonsters(1)
  if not gathering and not lureHolding and TargetBot.canLure() and (config.lure or config.lureCavebot or config.dynamicLure)
    and creature:getHealthPercent() >= (storage.extras.killUnder or 30) and not isTrappedAt(pos) then
    gathering = targetBotLure or (targets < config.lureCount and config.lureCavebot)
  end
  if gathering then
    TargetBot.Creature.resetAnchor()
  elseif not anchorPosition or anchorPosition.z ~= pos.z then
    anchorPosition = {x=pos.x, y=pos.y, z=pos.z}
  end
end

TargetBot.Creature.walk = function(creature, config, targets)
  if manualMovement() then
    TargetBot.walkTo(nil)
    if AttackBot and AttackBot.clearSpellMovement then AttackBot.clearSpellMovement() end
    TargetBot.Creature.resetAnchor()
    return 'manual' -- normal attacks/spells may continue; movement belongs to the keyboard.
  end
  if CaveBot and CaveBot.WaitStamina and CaveBot.WaitStamina.isBlocking()then
    TargetBot.walkTo(nil)
    if AttackBot and AttackBot.clearSpellMovement then AttackBot.clearSpellMovement()end
    return 'waitingStamina'
  end
  local combat=ComboFollowCombat and ComboFollowCombat.getState and ComboFollowCombat.getState()
  if combat and combat.active then
    TargetBot.walkTo(nil)
    TargetBot.Creature.resetAnchor()
    if TargetBot.holdCaveBot then TargetBot.holdCaveBot(false) end
    if combat.ready and AttackBot and AttackBot.isOn and AttackBot.isOn() then
      if AttackBot.setSpellMovementContext then AttackBot.setSpellMovementContext(creature,config,true) end
      if AttackBot.prepareSpellMovement then AttackBot.prepareSpellMovement(creature,config) end
    elseif AttackBot and AttackBot.clearSpellMovement then AttackBot.clearSpellMovement() end
    return 'followingLeader'
  end
  local cpos = creature:getPosition()
  local pos = player:getPosition()
  if not caveAllowsAlignment() and AttackBot and AttackBot.isOn and AttackBot.isOn() then
    if AttackBot.clearSpellMovement then AttackBot.clearSpellMovement() end
    TargetBot.Creature.resetAnchor()
    return 'facePending'
  end
  TargetBot.Creature.prepareMovement(creature, config, targets)
  local isTrapped = isTrappedAt(pos)

  -- AttackBot may borrow a gathering route for a ready directional spell.
  -- Its planner keeps the current pull distance and releases the route after
  -- the cast. Ordinary Keep Distance correction retains its existing priority.
  local gathering=not lureHolding and (
    config.closeLure and config.closeLureAmount<=getMonsters(1) or
    TargetBot.canLure() and (config.lure or config.lureCavebot or config.dynamicLure) and
      creature:getHealthPercent()>=(storage.extras.killUnder or 30) and not isTrapped and
      (targetBotLure or targets<(tonumber(config.lureCount) or 1)))
  if AttackBot and AttackBot.setSpellMovementContext then AttackBot.setSpellMovementContext(creature,config,gathering) end
  if AttackBot and (gathering or AttackBot.isSpellMovementCommitted and AttackBot.isSpellMovementCommitted()) and
    AttackBot.prepareSpellMovement and AttackBot.prepareSpellMovement(creature,config) then
    return 'facePending'
  end

  -- luring
  if not lureHolding and config.closeLure and config.closeLureAmount <= getMonsters(1) then
    return TargetBot.allowCaveBot(150)
  end
  if not lureHolding and TargetBot.canLure() and (config.lure or config.lureCavebot or config.dynamicLure) and not (creature:getHealthPercent() < (storage.extras.killUnder or 30)) and not isTrapped then
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

  -- Keep Distance is both retreat and pursuit. Measure actual SQM, not the
  -- number of steps in a path around obstacles, and do not accept range + 1.
  -- Correct the range before directional alignment can pause movement.
  if config.keepDistance then
    if config.anchor and anchorPosition and getDistanceBetween(pos, anchorPosition) > config.anchorRange then
      return TargetBot.walkTo(anchorPosition, 10, {ignoreNonPathable=true, ignoreCreatures=false,
        ignoreStairs=false, ignoreCost=false, allowOnlyVisibleTiles=true, avoidFloorChange=true,
        marginMin=0, marginMax=config.anchorRange, preferCardinal=true,
        maxDistanceFrom={anchorPosition,config.anchorRange}})
    end
    local range = math.max(1, tonumber(config.keepDistanceRange) or 1)
    if getDistanceBetween(pos, cpos) ~= range then
      local options = {ignoreNonPathable=true, ignoreCreatures=false, ignoreStairs=false,
        ignoreCost=false, allowOnlyVisibleTiles=true, avoidFloorChange=true,
        marginMin=range, marginMax=range, preferCardinal=true}
      if config.anchor and anchorPosition then
        options.maxDistanceFrom = {anchorPosition, config.anchorRange}
      end
      -- The destination is the reachable ring, not the monster's occupied tile.
      TargetBot.walkTo(cpos, 10, options)
      return
    end
  end

  if AttackBot and AttackBot.prepareSpellMovement and AttackBot.prepareSpellMovement(creature,config) then
    return "facePending"
  end

  if not config.keepDistance then
    local currentDistance = findPath(pos, cpos, 10, {ignoreCreatures=true, ignoreNonPathable=true, ignoreCost=true})
    if not currentDistance and TargetBot.Movement and TargetBot.Movement.fieldPath then
      currentDistance=TargetBot.Movement.fieldPath(pos,cpos,10,{ignoreCreatures=true})
    end
    if not currentDistance then return end
    if (not config.chase or #currentDistance == 1) and not config.avoidAttacks and config.rePosition and (creature:getHealthPercent() >= storage.extras.killUnder) then
      return rePosition(config.rePositionAmount or 6)
    end
    if (storage.extras.killUnder > 1 and creature:getHealthPercent() < storage.extras.killUnder) or config.chase then
      if #currentDistance > 1 then
        return TargetBot.walkTo(cpos, 10, {ignoreNonPathable=true, precision=1, avoidFloorChange=true,
          followFast=true,followCreature=creature})
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
      if walkableTile(tile) then
        return TargetBot.walkTo(candidate, 2, {ignoreNonPathable=true})
      end
    end
  end
end

TargetBot.Creature.getAnchorPosition = function() return anchorPosition end
TargetBot.Creature.isLureHolding=function()return lureHolding end
TargetBot.Creature.getLureCount=function()return targetCount end

onPlayerPositionChange(function(newPos, oldPos)
  if manualMovement() then return end
  if TargetBot.Antitrap and TargetBot.Antitrap.ownsMovement() then return end
  local explorer=CaveBot and CaveBot.AutoExplorer
  local automaticHunt=explorer and explorer.isOn and explorer.isOn()
  if CaveBot.isOff() and not automaticHunt then return end
  if TargetBot.isOff() then return end
  if not lureMax then return end
  if storage.TargetBotDelayWhenPlayer then return end
  if not dynamicLureDelay then return end

  if targetCount < (delayFrom or lureMax/2) or not target() then return end
  if automaticHunt and explorer.holdMovement then explorer.holdMovement(delayValue or 0) end
  CaveBot.delay(delayValue or 0)
end)
