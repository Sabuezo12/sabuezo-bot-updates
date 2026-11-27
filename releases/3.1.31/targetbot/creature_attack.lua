local targetBotLure = false
local lureRule,lureHolding=nil,false
local pauseRule
local targetCount = 0 
local anchorPosition = nil
local anchorRadius = 3
local anchorRoutePull = false
local lastAnchorTrace = nil
local lastCall = now
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
-- On a floor the CaveBot route does not use (fell, or stairs taken while luring): the
-- TargetBot stops moving so the floor return (cavebot/floor_return.lua) can act at once.
local function strayedFloor(pos)
  local floorReturn = CaveBot and CaveBot.FloorReturn
  if not pos or not floorReturn or type(floorReturn.strayed) ~= 'function' then return false end
  local ok, strayed = pcall(floorReturn.strayed, pos)
  return ok and strayed == true
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
    maxDistanceFrom = options.maxDistanceFrom or options.anchorBounds
  }
  local path
  if options.strictRange and TargetBot.Movement then
    path=TargetBot.Movement.findPath(fromPos,toPos,maxPath,params)
  else path=findPath(fromPos,toPos,maxPath,params) end
  if TargetBot.Movement and not TargetBot.Movement.pathSafe(fromPos,path,options.maxDistanceFrom) then return nil end
  -- Anclaje: the whole alignment route stays inside the combat radius.
  if options.anchorBounds and TargetBot.Movement and not TargetBot.Movement.pathSafe(fromPos,path,options.anchorBounds) then return nil end
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
          local anchor = options.anchorBounds
          local inside = (not boundary or getDistanceBetween(candidate, boundary[1]) <= boundary[2])
            and (not anchor or getDistanceBetween(candidate, anchor[1]) <= anchor[2])
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
  -- Anclaje: a spell position outside the combat radius is not a candidate.
  local anchorBounds = TargetBot.Creature.getAnchorBounds and TargetBot.Creature.getAnchorBounds()
  if anchorBounds then
    local bounded = {}
    for name, value in pairs(options) do bounded[name] = value end
    bounded.anchorBounds = anchorBounds
    options = bounded
  end

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

-- bounds (optional) = {centre, radius} of the Anclaje; tiles outside it are skipped.
function rePosition(minTiles, bounds)
  minTiles = minTiles or 8
  if now - lastCall < 500 then return end
  local pPos = player:getPosition()
  local tiles = getNearTiles(pPos)
  local playerTilesCount = getWalkableTilesCount(pPos)
  local tilesTable = {}

  if playerTilesCount > minTiles then return end
  for i, tile in ipairs(tiles) do
      local inside = not bounds or getDistanceBetween(tile:getPosition(), bounds[1]) <= bounds[2]
      tilesTable[tile] = inside and not tileHasCreature(tile) and walkableTile(tile) and getWalkableTilesCount(tile:getPosition()) or nil
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

-- Read-only trace to the bot console ("Acciones"): when the Anclaje is fixed or released.
local function anchorTrace(message, detail)
  local traceKey = message .. (detail or '')
  if traceKey == lastAnchorTrace then return end
  lastAnchorTrace = traceKey
  if RinoConsole and RinoConsole.valid and RinoConsole.valid() then
    pcall(RinoConsole.log, 'action', 'TargetBot', message, detail)
  end
end

-- reason (optional) is only for the console trace.
TargetBot.Creature.resetAnchor = function(reason)
  if anchorPosition and reason then anchorTrace('Anclaje liberado: ' .. reason) end
  -- "Tirar hacia la ruta": the route resumes from the waypoint the fight reached.
  if anchorPosition and anchorRoutePull and reason and reason ~= 'movimiento manual' and reason ~= 'Combo Follow mueve al personaje' then
    local movement = TargetBot.Movement
    local pos = player and player:getPosition()
    if movement and movement.catchUpRoute and movement.catchUpRoute(pos) then
      anchorTrace('Tirar hacia la ruta: CaveBot sigue desde el waypoint mas cercano')
    end
  end
  anchorPosition = nil
  TargetBot.Creature.leaderAnchor = nil
end
-- "Tirar hacia la ruta" without Anclaje (change 224): when the lure goes back to gathering
-- or the fight ends, the route resumes from the waypoint the fight reached, not behind it.
local function routeCatchUp(rule)
  if type(rule) ~= 'table' or rule.routePull ~= true or rule.anchor == true then return end
  local movement = TargetBot.Movement
  local pos = player and player:getPosition()
  if movement and movement.catchUpRoute and movement.catchUpRoute(pos) then
    anchorTrace('Tirar hacia la ruta: CaveBot sigue desde el waypoint mas cercano')
  end
end

-- Anclaje on the Combo Follow leader: with the leader standing and the rule anchored,
-- the centre is the leader and TargetBot moves inside the rule's radius around him (chase,
-- grouping, antitrap, spell spots). No lure and no pull towards the route: CaveBot is
-- not walking. The leader's first step ends it (vBot/combo_plus.lua releases it).
local function anchorOnLeader(centre, radius)
  local same = anchorPosition and anchorPosition.x == centre.x and anchorPosition.y == centre.y and
    anchorPosition.z == centre.z and anchorRadius == radius
  if not same then
    anchorTrace('Anclaje en el leader', centre.x .. ',' .. centre.y .. ',' .. centre.z .. ' | radio ' .. radius .. ' SQM')
  end
  anchorPosition = {x=centre.x, y=centre.y, z=centre.z}
  anchorRadius, anchorRoutePull = radius, false
  lureRule, lureHolding, targetBotLure = nil, false, false
  TargetBot.Creature.leaderAnchor = anchorPosition
end
local function leaderAnchorHolds()
  return TargetBot.Creature.leaderAnchor ~= nil and anchorPosition == TargetBot.Creature.leaderAnchor and
    ComboFollowCombat and ComboFollowCombat.leaderRadius ~= nil
end

-- Anclaje: the combat centre and its radius, {centre, radius}, or nil when no
-- anchor applies. Every TargetBot movement (Keep Distance, chase, close
-- grouping/antitrap, reposition, avoid waves, classic lure, spell alignment and
-- looting during combat) stays inside it. It does not exist while Dynamic Lure
-- gathers with CaveBot: that walk is the route, not combat movement.
TargetBot.Creature.getAnchorBounds = function()
  local pos = player and player:getPosition()
  if not anchorPosition or not pos or pos.z ~= anchorPosition.z then return nil end
  return {anchorPosition, anchorRadius}
end

-- Capture the combat centre before an emergency can move the character.
-- Leaving its radius never replaces it; gathering the next pull releases it.
-- Anclaje is independent of Keep Distance (it used to need it, so with Keep
-- Distance OFF the option did nothing).
TargetBot.Creature.prepareMovement = function(creature, config, targets, noTarget)
  local pos = player and player:getPosition()
  if manualMovement() or not creature or not config or not pos then
    if lureRule and pos and not manualMovement() then routeCatchUp(lureRule) end
    TargetBot.Creature.resetAnchor(manualMovement() and 'movimiento manual' or not creature and 'fin del combate' or nil)
    lureRule=nil;lureHolding=false;targetBotLure=false
    return
  end
  -- Off the route's floor: no anchor there and no lure holding the CaveBot back.
  if strayedFloor(pos) then
    TargetBot.Creature.resetAnchor('cambio de piso fuera de la ruta')
    lureRule=nil;lureHolding=false;targetBotLure=false
    return
  end
  -- The Anclaje on the Follow leader stays while he stands (walk() keeps it on him).
  if leaderAnchorHolds() then
    lureRule=nil;lureHolding=false;targetBotLure=false
    return
  end
  TargetBot.Creature.leaderAnchor = nil
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
  pauseRule=config
  local holding=config.dynamicLure==true and not targetBotLure and TargetBot.canLure()
  if holding and not lureHolding and TargetBot.holdCaveBot then TargetBot.holdCaveBot(true)end
  if lureHolding and not holding then routeCatchUp(config) end
  lureHolding=holding
  targetCount = targets

  if not config.anchor then
    TargetBot.Creature.resetAnchor()
    return
  end
  -- Without an attackable target TargetBot stops holding CaveBot, so an anchor
  -- kept here would drag the character back after the route moved on. Keep
  -- Distance keeps its previous behaviour (its antitrap holds the area).
  if noTarget and not config.keepDistance then
    TargetBot.Creature.resetAnchor('sin objetivo atacable')
    return
  end
  anchorRadius = math.max(1, tonumber(config.anchorRange) or 3)
  anchorRoutePull = config.routePull == true
  local gathering = false
  if not gathering and not lureHolding and TargetBot.canLure() and (config.lure or config.lureCavebot or config.dynamicLure)
    and creature:getHealthPercent() >= (storage.extras.killUnder or 30) and not isTrappedAt(pos) then
    gathering = targetBotLure or (targets < (tonumber(config.lureCount) or 1) and config.lureCavebot)
  end
  if gathering then
    TargetBot.Creature.resetAnchor('el lure reune monstruos con CaveBot')
  elseif not anchorPosition or anchorPosition.z ~= pos.z then
    anchorPosition = {x=pos.x, y=pos.y, z=pos.z}
    anchorTrace('Anclaje fijado', pos.x .. ',' .. pos.y .. ',' .. pos.z .. ' | radio ' .. anchorRadius .. ' SQM')
  end
end

-- Read-only trace to the bot console ("Acciones"): state of the Dynamic Lure.
local lastLureTraceKey, lastLureTraceAt = nil, 0
local function lureTrace(config, targets)
  if not config.dynamicLure then return end
  if not (RinoConsole and RinoConsole.valid and RinoConsole.valid()) then return end
  if now - lastLureTraceAt < 1000 then return end
  local key = table.concat({tostring(targets), tostring(lureHolding), tostring(targetBotLure)}, '|')
  if key == lastLureTraceKey then return end
  lastLureTraceKey, lastLureTraceAt = key, now
  pcall(RinoConsole.log, 'action', 'TargetBot', 'monstruos ' .. tostring(targets) .. ' | lure dinamico',
    'retiene CaveBot: ' .. (lureHolding and 'si' or 'no') .. ' | modo reunir: ' .. (targetBotLure and 'si' or 'no'))
end

-- "Tirar hacia la ruta": fighting anchored and calm, lean to the side of the
-- radius that faces the next CaveBot waypoint, one safe step at a time, so the
-- pack is dragged along the route. The centre does not move; a step never puts
-- the character next to more monsters than now (nor above "Agrupar cercanos").
local function leanToRoute(pos, bounds, config)
  local movement = TargetBot.Movement
  local ahead = movement and movement.routeAhead and movement.routeAhead(pos)
  if not ahead then return end
  local centre, radius = bounds[1], bounds[2]
  local dx, dy = ahead.x - centre.x, ahead.y - centre.y
  local span = math.max(math.abs(dx), math.abs(dy))
  if span == 0 then return end
  local reach = math.min(span, radius) -- the edge; it stops one tile short of it
  local spot = {x = centre.x + math.floor(dx * reach / span + 0.5), y = centre.y + math.floor(dy * reach / span + 0.5), z = centre.z}
  local here = getDistanceBetween(pos, spot)
  if here <= 1 then return end
  local monsters = {}
  for _, actor in ipairs(g_map.getSpectatorsInRange(pos, false, 3, 3) or {}) do
    local p = actor:isMonster() and actor:getPosition()
    local hp = actor:getHealthPercent()
    if p and p.z == pos.z and (not hp or hp > 0) then monsters[#monsters + 1] = p end
  end
  local function adjacent(p)
    local count = 0
    for _, m in ipairs(monsters) do if getDistanceBetween(p, m) <= 1 then count = count + 1 end end
    return count
  end
  local limit = config.closeLure == true and math.max(1, tonumber(config.closeLureAmount) or 3) or math.huge
  local current = adjacent(pos)
  -- Not into the Agrupar cercanos distance nor a pocket the pack can close (antitrap).
  local antitrap = TargetBot.Antitrap
  local calm = antitrap and antitrap.calmSpot
  local best, bestScore
  for direction = 0, 7 do
    local to = movement.destination(pos, direction)
    if to and getDistanceBetween(to, centre) <= radius and getDistanceBetween(to, spot) < here and movement.canStep(pos, direction)
      and (not calm or calm(pos, to)) then
      local near = adjacent(to)
      if near <= current and near <= limit then
        local score = -getDistanceBetween(to, spot) * 10 - near - (direction >= 4 and 0.5 or 0)
        if not bestScore or score > bestScore then best, bestScore = to, score end
      end
    end
  end
  if best then
    return TargetBot.walkTo(best, 2, {ignoreNonPathable=true, ignoreCreatures=false, precision=0,
      avoidFloorChange=true, preferCardinal=true, maxDistanceFrom=bounds})
  end
end

TargetBot.Creature.walk = function(creature, config, targets)
  if manualMovement() then
    TargetBot.walkTo(nil)
    if AttackBot and AttackBot.clearSpellMovement then AttackBot.clearSpellMovement() end
    TargetBot.Creature.resetAnchor('movimiento manual')
    return 'manual' -- normal attacks/spells may continue; movement belongs to the keyboard.
  end
  if CaveBot and CaveBot.WaitStamina and CaveBot.WaitStamina.isBlocking()then
    TargetBot.walkTo(nil)
    if AttackBot and AttackBot.clearSpellMovement then AttackBot.clearSpellMovement()end
    return 'waitingStamina'
  end
  local combat=ComboFollowCombat and ComboFollowCombat.getState and ComboFollowCombat.getState()
  local onLeader=false
  if combat and combat.active and combat.ready and config and config.anchor and ComboFollowCombat.anchorOnLeader then
    local centre,radius=ComboFollowCombat.anchorOnLeader(config.anchorRange)
    if centre then
      anchorOnLeader(centre,radius)
      if TargetBot.holdCaveBot then TargetBot.holdCaveBot(false) end
      onLeader=true
    end
  end
  if combat and combat.active and not onLeader then
    TargetBot.walkTo(nil)
    TargetBot.Creature.resetAnchor('Combo Follow mueve al personaje')
    if TargetBot.holdCaveBot then TargetBot.holdCaveBot(false) end
    if combat.ready and AttackBot and AttackBot.isOn and AttackBot.isOn() then
      if AttackBot.setSpellMovementContext then AttackBot.setSpellMovementContext(creature,config,true) end
      if AttackBot.prepareSpellMovement then AttackBot.prepareSpellMovement(creature,config) end
    elseif AttackBot and AttackBot.clearSpellMovement then AttackBot.clearSpellMovement() end
    return 'followingLeader'
  end
  local cpos = creature:getPosition()
  local pos = player:getPosition()
  -- Off the route's floor: keep attacking, but let the CaveBot walk the way back now.
  if strayedFloor(pos) then
    TargetBot.walkTo(nil)
    if AttackBot and AttackBot.clearSpellMovement then AttackBot.clearSpellMovement() end
    anchorTrace('Regreso de piso: el TargetBot deja caminar al CaveBot')
    TargetBot.allowCaveBot(150)
    return 'floorReturn'
  end
  -- On the leader the route is paused on purpose: alignment moves inside his radius.
  if not onLeader and not caveAllowsAlignment() and AttackBot and AttackBot.isOn and AttackBot.isOn() then
    if AttackBot.clearSpellMovement then AttackBot.clearSpellMovement() end
    -- Keep the Anclaje: antitrap/close grouping still move the character here.
    -- Resetting it made target.lua fix it again on the next tick, at the new tile.
    return 'facePending'
  end
  if not onLeader then
    TargetBot.Creature.prepareMovement(creature, config, targets)
    lureTrace(config, targets)
  end
  local isTrapped = isTrappedAt(pos)

  -- AttackBot may borrow a gathering route for a ready directional spell.
  -- Its planner keeps the current pull distance and releases the route after
  -- the cast. Ordinary Keep Distance correction retains its existing priority.
  local gathering=not onLeader and not lureHolding and (
    TargetBot.canLure() and (config.lure or config.lureCavebot or config.dynamicLure) and
      creature:getHealthPercent()>=(storage.extras.killUnder or 30) and not isTrapped and
      (targetBotLure or targets<(tonumber(config.lureCount) or 1)))
  if AttackBot and AttackBot.setSpellMovementContext then AttackBot.setSpellMovementContext(creature,config,gathering) end
  if AttackBot and (gathering or AttackBot.isSpellMovementCommitted and AttackBot.isSpellMovementCommitted()) and
    AttackBot.prepareSpellMovement and AttackBot.prepareSpellMovement(creature,config) then
    return 'facePending'
  end

  -- Anclaje: outside the radius (a push, an emergency step, a manual click that
  -- ended) the way back comes before any other TargetBot movement. Antitrap /
  -- close grouping has its own safe return and owns movement while it runs.
  local anchorBounds = TargetBot.Creature.getAnchorBounds()
  if anchorBounds and getDistanceBetween(pos, anchorBounds[1]) > anchorBounds[2] then
    return TargetBot.walkTo(anchorBounds[1], 10, {ignoreNonPathable=true, ignoreCreatures=false,
      ignoreStairs=false, ignoreCost=false, allowOnlyVisibleTiles=true, avoidFloorChange=true,
      marginMin=0, marginMax=anchorBounds[2], preferCardinal=true, maxDistanceFrom=anchorBounds})
  end

  -- luring
  if not onLeader and not lureHolding and TargetBot.canLure() and (config.lure or config.lureCavebot or config.dynamicLure) and not (creature:getHealthPercent() < (storage.extras.killUnder or 30)) and not isTrapped then
    if targetBotLure then
      TargetBot.Creature.resetAnchor('el lure reune monstruos con CaveBot')
      return TargetBot.allowCaveBot(150)
    else
      if targets < config.lureCount then
        if config.lureCavebot then
          TargetBot.Creature.resetAnchor('el lure reune monstruos con CaveBot')
          return TargetBot.allowCaveBot(150)
        else
          local path = findPath(pos, cpos, 5, {ignoreNonPathable=true, precision=2})
          if path then
            -- Classic lure: TargetBot.walk keeps it inside the Anclaje radius.
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
    local range = math.max(1, tonumber(config.keepDistanceRange) or 1)
    if getDistanceBetween(pos, cpos) ~= range then
      local options = {ignoreNonPathable=true, ignoreCreatures=false, ignoreStairs=false,
        ignoreCost=false, allowOnlyVisibleTiles=true, avoidFloorChange=true,
        marginMin=range, marginMax=range, preferCardinal=true}
      if anchorBounds then
        options.maxDistanceFrom = anchorBounds
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
      return rePosition(config.rePositionAmount or 6, anchorBounds)
    end
    -- Quieto (change 222) does not walk to finish a low-health target either.
    local mode = TargetBot.Creature.fightMode(config)
    if mode ~= 'still' and (storage.extras.killUnder > 1 and creature:getHealthPercent() < storage.extras.killUnder) or config.chase then
      if #currentDistance > 1 then
        -- With Anclaje the chase stops at the edge of the radius (walking.lua).
        return TargetBot.walkTo(cpos, 10, {ignoreNonPathable=true, precision=1, avoidFloorChange=true,
          followFast=true,followCreature=creature})
      end
    elseif mode == 'dynamic' then
      -- Dinamico: close in on the pack so the AttackBot's 2-step spell positioning can reach
      -- it. Knight and Monk fight next to it; the others stop where their shortest area spell
      -- still reaches it (change 227: 2-4 SQM; 3 without area spells).
      local vocation = AttackBot and AttackBot.vocation and AttackBot.vocation()
      local reach = 1
      if vocation == 'Paladin' or vocation == 'Sorcerer' or vocation == 'Druid' then
        local ok, value = pcall(function() return AttackBot.dynamicReach and AttackBot.dynamicReach() end)
        reach = ok and tonumber(value) or 3
      end
      if #currentDistance > reach then
        -- Never into a tile Agrupar cercanos / BugMap sin salida would flee from at once; one
        -- checked step per tick (no fast multi-step packet past that limit).
        local antitrap = TargetBot.Antitrap
        local movement = TargetBot.Movement
        local first = movement and movement.destination(pos, currentDistance[1])
        if first and antitrap and antitrap.spellSpot and not antitrap.spellSpot(pos, first) then return end
        -- Tirar hacia la ruta (224, 225): at most 2 SQM back from the best progress to the next waypoint.
        local ahead, limit
        if config.routePull == true and movement and movement.routeLimit then ahead, limit = movement.routeLimit(pos) end
        if ahead and first and getDistanceBetween(first, ahead) > math.max(limit or 0, getDistanceBetween(pos, ahead)) then return end
        return TargetBot.walkTo(cpos, 10, {ignoreNonPathable=true, precision=reach, avoidFloorChange=true, spellSpot=true,
          routeAhead=ahead, routeLimit=limit})
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
      local inside = not anchorBounds or getDistanceBetween(candidate, anchorBounds[1]) <= anchorBounds[2]
      if inside and walkableTile(tile) then
        return TargetBot.walkTo(candidate, 2, {ignoreNonPathable=true})
      end
    end
  end

  -- Nothing else moved: lean towards the route (Keep Distance and chase keep
  -- their own positioning; rePosition returned above when enabled).
  if not onLeader and config.routePull == true and anchorBounds and not config.keepDistance and not config.chase then
    return leanToRoute(pos, anchorBounds, config)
  end
end

TargetBot.Creature.getAnchorPosition = function() return anchorPosition end
-- Modo de pelea (change 222): 'still' Quieto, 'chase' Perseguir, 'anchor' Anclado, 'dynamic'
-- Dinamico. chase/anchor keep deciding (the old editor and older code read them); only the
-- two without either need fightMode. Rules saved before 222 have none and are Dinamico.
TargetBot.Creature.fightMode = function(config)
  if type(config) ~= 'table' then return 'still' end
  if config.anchor == true then return 'anchor' end
  if config.chase == true then return 'chase' end
  if config.fightMode == 'still' then return 'still' end
  return 'dynamic'
end
TargetBot.Creature.isLureHolding=function()return lureHolding end
TargetBot.Creature.getLureCount=function()return targetCount end

-- Read-only trace: says why Dynamic Pause ("Pausa dinamica") was skipped or applied.
-- Silent while the option is OFF, repeats only when the reason changes.
local lastPauseKey, lastPauseAt = nil, 0
local function pauseTrace(message, detail)
  if not pauseRule or not pauseRule.dynamicLureDelay then return end
  local key = message .. (detail or '')
  if key == lastPauseKey or now - lastPauseAt < 1000 then return end
  lastPauseKey, lastPauseAt = key, now
  if RinoConsole and RinoConsole.valid and RinoConsole.valid() then
    pcall(RinoConsole.log, 'action', 'TargetBot', message, detail)
  end
end

-- Dynamic Pause ("Pausa dinamica"): wait for the pulled monsters instead of pausing every step.
-- CaveBot walks freely (mapClick included) while the last monster of the pull stays within
-- lureSpread SQM. When it falls further behind, the character stops until it comes back to
-- lureSpread-2 SQM (at least 2), or the pull stops getting closer (a queue in a corridor,
-- ranged monsters that keep their distance), then walks on.
local HERD_LEAVE = 9         -- beyond this it is no longer part of the pull
local HERD_STALL_MS = 1200   -- no approach for this long: stop waiting for that monster
local HERD_SETTLED_MS = 500  -- nobody got closer for this long: the pull is as tight as it gets
local HERD_MAX_WAIT_MS = 4000
local herd = {members = {}, waiting = false, since = 0, progressAt = 0, waits = 0, waitedMs = 0, longest = 0, summaryAt = 0}

-- Track the monsters that came within spread SQM. Each one has a limit (spread, or more for one
-- that keeps its own distance, like a ranged monster or the back of a queue) and a goal: the
-- distance it should come back to while the character waits.
local function herdScan(pos, spread, resume)
  local seen = {}
  local count, worstExcess, farthest, pending = 0, -math.huge, -1, false
  local specs = g_map.getSpectatorsInRange and g_map.getSpectatorsInRange(pos, false, HERD_LEAVE, HERD_LEAVE)
  for _, creature in pairs(specs or getSpectators()) do
    if creature ~= player and creature:isMonster() and (tonumber(creature:getType()) or 0) < 3 then
      local p, hp = creature:getPosition(), creature:getHealthPercent()
      if p and p.z == pos.z and hp and hp > 0 then
        local id = creature:getId()
        local dist = math.max(math.abs(p.x - pos.x), math.abs(p.y - pos.y))
        local member = herd.members[id]
        if not member and lureRule and dist <= spread then
          local rules = TargetBot.Creature.getConfigs(creature)
          if rules and #rules > 0 then member = {}; herd.members[id] = member end
        end
        if member and dist <= HERD_LEAVE then
          seen[id] = true
          member.dist = dist
          if dist <= resume then member.ignored, member.keeps = nil, nil end
          local limit = math.max(spread, member.keeps and member.keeps + 2 or 0)
          local goal = member.keeps or resume
          if herd.waiting and not member.ignored then
            if not member.best or dist < member.best then
              if member.best then herd.progressAt = now end
              member.best, member.progressAt = dist, now
            elseif dist > limit and now - member.progressAt >= HERD_STALL_MS then member.ignored = true end
          end
          if not member.ignored then
            count = count + 1
            farthest = math.max(farthest, dist)
            worstExcess = math.max(worstExcess, dist - limit)
            if dist > goal then pending = true end
          end
        end
      end
    end
  end
  for id in pairs(herd.members) do if not seen[id] then herd.members[id] = nil end end
  return count, worstExcess, farthest, pending
end

local function herdHold()
  local explorer = CaveBot and CaveBot.AutoExplorer
  if explorer and explorer.isOn and explorer.isOn() and explorer.holdMovement then explorer.holdMovement(200) end
  CaveBot.delay(200)
  if CaveBot.stopPathWalk and
    not (AttackBot and AttackBot.isSpellMovementCommitted and AttackBot.isSpellMovementCommitted()) then
    CaveBot.stopPathWalk()
  end
end

local function herdStop(reason, dist)
  if not herd.waiting then return end
  herd.waiting = false
  local waited = now - herd.since
  herd.waits, herd.waitedMs = herd.waits + 1, herd.waitedMs + waited
  herd.longest = math.max(herd.longest, waited)
  pauseTrace('Pausa dinamica: sigo el recorrido (' .. reason .. ')',
    'espere ' .. waited .. ' ms' .. (dist and dist >= 0 and (' | ultimo a ' .. dist .. ' SQM') or ''))
  if now - herd.summaryAt >= 30000 and herd.waits >= 3 and RinoConsole and RinoConsole.valid and RinoConsole.valid() then
    pcall(RinoConsole.log, 'action', 'TargetBot', 'Pausa dinamica: resumen de esperas',
      herd.waits .. ' esperas, promedio ' .. math.floor(herd.waitedMs / herd.waits) .. ' ms, la mas larga ' .. herd.longest .. ' ms')
    herd.summaryAt, herd.waits, herd.waitedMs, herd.longest = now, 0, 0, 0
  end
end

local function resetHerd(reason)
  herdStop(reason)
  herd.members, herd.floor = {}, nil
end

TargetBot.Creature.resetDynamicPause = function()
  pauseRule = nil
  resetHerd('regla de TargetBot recargada')
end

-- A monster still short of its goal must have stood HERD_STALL_MS without approaching before its
-- distance is learned: a slow melee monster between two of its steps is not one that keeps away.
local function herdSettled(resume)
  for _, member in pairs(herd.members) do
    if not member.ignored and member.dist and member.dist > resume and
      (not member.progressAt or now - member.progressAt < HERD_STALL_MS) then return false end
  end
  return true
end

-- Hard conditions: the pause does not apply at all (pull state is forgotten).
local function herdOff()
  if not pauseRule or not pauseRule.dynamicLureDelay then return true end
  if manualMovement() then return 'Pausa dinamica omitida: movimiento manual' end
  if isInPz() or HelperPause and HelperPause.isPaused() then return true end
  if CaveBot.Flee and CaveBot.Flee.blocksCombat() then return true end
  if strayedFloor(player and player:getPosition()) then return 'Pausa dinamica omitida: regreso de piso' end
  if TargetBot.Antitrap and TargetBot.Antitrap.ownsMovement() then return 'Pausa dinamica omitida: antitrap mueve al personaje' end
  -- Combo Follow walks with autoWalk too; stopping it would cut the follower's path.
  if ComboFollowCombat and ComboFollowCombat.isFollowing and ComboFollowCombat.isFollowing() then return 'Pausa dinamica omitida: Combo Follow mueve al personaje' end
  local explorer = CaveBot and CaveBot.AutoExplorer
  local automaticHunt = explorer and explorer.isOn and explorer.isOn()
  if CaveBot.isOff() and not automaticHunt then return 'Pausa dinamica omitida: CaveBot apagado' end
  if TargetBot.isOff() then return 'Pausa dinamica omitida: TargetBot apagado' end
  if storage.TargetBotDelayWhenPlayer then return 'Pausa dinamica omitida: hay un jugador cerca (TargetBotDelayWhenPlayer)' end
end

-- Soft conditions: keep following the pull, but do not wait for it now.
local function herdIdle(count)
  if lureHolding then return 'Pausa dinamica omitida: lure detenido en el maximo' end
  local from = math.max(1, tonumber(pauseRule.delayFrom) or math.ceil((tonumber(pauseRule.lureMax) or 4) / 2))
  if not herd.waiting and count < from then return 'Pausa dinamica omitida: monstruos ' .. count .. ' < desde ' .. from end
end

macro(100, function()
  local off = herdOff()
  if off then
    resetHerd('pausa desactivada')
    if off ~= true then pauseTrace(off) end
    return
  end
  local pos = player and player:getPosition()
  if not pos then return end
  if herd.floor ~= pos.z then
    resetHerd('cambio de piso')
    herd.floor = pos.z
  end
  local spread = math.max(2, math.min(8, math.floor(tonumber(pauseRule.lureSpread) or 4)))
  local resume = math.max(2, spread - 2) -- at 2 SQM a monster is right behind the front of the pull
  -- The attack shortlist can drop a lagging monster or lose its target entirely.
  -- Keep applying "Desde" to the monsters already gathered for this pull.
  local count, excess, farthest, pending = herdScan(pos, spread, resume)
  local idle = herdIdle(count)
  if idle then herdStop('sin lure activo', farthest);pauseTrace(idle);return end
  if herd.waiting then
    if not pending then herdStop(count > 0 and 'la manada llego' or 'ninguno se acerca', farthest)
    elseif excess <= 0 and now - herd.progressAt >= HERD_SETTLED_MS and herdSettled(resume) then
      -- Monsters that stay back on their own keep that distance as their goal from now on.
      for _, member in pairs(herd.members) do
        if not member.ignored and member.dist and member.dist > resume then member.keeps = member.dist end
      end
      herdStop('la manada ya no se acerca mas', farthest)
    elseif now - herd.since >= HERD_MAX_WAIT_MS then
      -- Those still beyond their limit are not waited for again until they come back.
      for _, member in pairs(herd.members) do
        if not member.ignored and member.dist and member.dist > math.max(spread, member.keeps and member.keeps + 2 or 0) then
          member.ignored = true
        end
      end
      herdStop('espera maxima', farthest)
    else herdHold() end
  elseif excess > 0 then
    herd.waiting, herd.since, herd.progressAt = true, now, now
    for _, member in pairs(herd.members) do member.best, member.progressAt = nil, nil end
    pauseTrace('Pausa dinamica: espero a la manada', 'ultimo a ' .. farthest .. ' SQM (limite ' .. spread .. ') | monstruos ' .. count)
    herdHold()
  end
end)

TargetBot.Creature.isHerdWaiting = function() return herd.waiting end

-- Existing scripts can use this to check whether a herd wait is active.
TargetBot.Creature.pauseWantsSteps = function()
  return herd.waiting
end
