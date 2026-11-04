-- Cache only within one target evaluation cycle. Both arrow counts must use
-- the complete pattern, including players outside the target selection range.
local arrowPatternOffsets = {}
local function arrowOffsets(pattern)
  local cached = arrowPatternOffsets[pattern]
  if cached ~= nil then return cached or nil end
  local cells,width,height,lineLength = {},0,0,0
  -- Match the native parser, including whitespace and direction-only cells.
  for index = 1, #pattern do
    local cell = pattern:sub(index,index)
    lineLength = lineLength+1
    if cell:match("[01%+%-NnEeWwSs]") then
      cells[#cells+1] = cell == "1" or cell == "+"
    else
      lineLength = lineLength-1
      if lineLength > 1 then
        if width == 0 then width = lineLength end
        if width ~= lineLength then arrowPatternOffsets[pattern]=false;return nil end
        height,lineLength = height+1,0
      end
    end
  end
  if lineLength > 0 then
    if width == 0 then width = lineLength end
    if width ~= lineLength then arrowPatternOffsets[pattern]=false;return nil end
    height = height+1
  end
  if width == 0 or width > 5 or height > 5 or width%2 ~= 1 or height%2 ~= 1 then
    arrowPatternOffsets[pattern] = false
    return nil
  end
  local offsets = {}
  for y = 1, height do
    for x = 1, width do
      -- Position-based native patterns use direction 8, so N/E/S/W are off.
      if cells[(y-1)*width+x] then
        offsets[#offsets+1] = {x-1-math.floor(width/2), y-1-math.floor(height/2)}
      end
    end
  end
  arrowPatternOffsets[pattern] = offsets
  return offsets
end

local function arrowGrid(cycle)
  if cycle.arrowGrid ~= nil then return cycle.arrowGrid or nil end
  cycle.arrowGrid = false
  if not cycle.origin or not cycle.creatures or #cycle.creatures < 3 or not cycle.positions or
      not g_map or type(g_map.getSpectatorsInRange) ~= "function" then return nil end
  local minX,maxX,minY,maxY,count=nil,nil,nil,nil,0
  for _, actor in ipairs(cycle.creatures) do
    if actor:isMonster() then
      local position = cycle.positions[actor] or actor:getPosition()
      cycle.positions[actor] = position
      if position and position.z == cycle.origin.z then
        count = count+1
        minX = minX and math.min(minX,position.x) or position.x
        maxX = maxX and math.max(maxX,position.x) or position.x
        minY = minY and math.min(minY,position.y) or position.y
        maxY = maxY and math.max(maxY,position.y) or position.y
      end
    end
  end
  -- Small groups keep the cheaper individual query. At map edges, retain the
  -- native pattern's coordinate handling instead of guessing wrap behavior.
  if count < 3 or minX < 3 or minY < 3 or maxX > 65532 or maxY > 65532 then return nil end
  local center = {x=math.floor((minX+maxX)/2),y=math.floor((minY+maxY)/2),z=cycle.origin.z}
  local xRange = math.max(center.x-minX,maxX-center.x)+2
  local yRange = math.max(center.y-minY,maxY-center.y)+2
  local grid = {cells={},minX=minX,maxX=maxX,minY=minY,maxY=maxY,z=center.z}
  local oldTibia = g_game.getClientVersion() < 960
  for _, actor in ipairs(g_map.getSpectatorsInRange(center,false,xRange,yRange)) do
    local position = actor:getPosition()
    if actor ~= player and position and position.z == center.z then
      local key = position.x..","..position.y
      local cell = grid.cells[key]
      if not cell then cell={monsters=0,players={}};grid.cells[key]=cell end
      if actor:isMonster() and (oldTibia or actor:getType() < 3) then
        cell.monsters = cell.monsters+1
      elseif actor:isPlayer() then
        cell.players[#cell.players+1] = actor:getName()
      end
    end
  end
  cycle.arrowGrid = grid
  return grid
end

local function gridArrowCounts(position,pattern,cycle)
  local offsets = arrowOffsets(pattern)
  if not offsets then return nil end
  local grid = arrowGrid(cycle)
  if not grid or position.z ~= grid.z or position.x < grid.minX or position.x > grid.maxX or
      position.y < grid.minY or position.y > grid.maxY then return nil end
  local counts = {monsters=0,players={}}
  for _, offset in ipairs(offsets) do
    local cell = grid.cells[(position.x+offset[1])..","..(position.y+offset[2])]
    if cell then
      counts.monsters = counts.monsters+cell.monsters
      for _, name in ipairs(cell.players) do counts.players[#counts.players+1] = name end
    end
  end
  return counts
end

local function arrowCounts(position, pattern, cycle, safe)
  if not cycle or type(getSpectators) ~= "function" then
    return getCreaturesInArea(position, pattern, 2), safe and getCreaturesInArea(position, pattern, 3) or 0
  end
  cycle.areas, cycle.friends = cycle.areas or {}, cycle.friends or {}
  local areas = cycle.areas[pattern]
  if not areas then areas = {}; cycle.areas[pattern] = areas end
  local key = position.x..","..position.y..","..position.z
  local counts = areas[key]
  if not counts then
    counts = gridArrowCounts(position,pattern,cycle)
    if not counts then
      counts = {monsters=0, players={}}
      local oldTibia = g_game.getClientVersion() < 960
      for _, actor in pairs(getSpectators(position, pattern)) do
        if actor ~= player then
          if actor:isMonster() and (oldTibia or actor:getType() < 3) then
            counts.monsters = counts.monsters+1
          elseif actor:isPlayer() then
            counts.players[#counts.players+1] = actor:getName()
          end
        end
      end
    end
    areas[key] = counts
  end
  if safe and counts.unsafe == nil then
    counts.unsafe = 0
    for _, name in ipairs(counts.players) do
      if cycle.friends[name] == nil then cycle.friends[name] = isFriend(name) and true or false end
      if not cycle.friends[name] then counts.unsafe = counts.unsafe+1 end
    end
  end
  return counts.monsters, counts.unsafe or 0
end

TargetBot.Creature.calculatePriority = function(creature, config, path, cycle)
  -- config is based on creature_editor
  local priority = 0
  local currentTarget = g_game.getAttackingCreature()

  local function addArrowAreaPriority(pattern)
    local position = creature:getPosition()
    local mobCount, unsafePlayers = arrowCounts(position, pattern, cycle, config.rpSafe)

    if config.rpSafe and unsafePlayers > 0 then
      if currentTarget == creature then
        g_game.cancelAttackAndFollow()
      end
      return nil
    end

    -- Area arrows should prefer the tile that hits more monsters.
    -- One extra monster must outweigh distance and low-health bonuses.
    return mobCount * 14
  end

  -- extra priority if it's current target
  if currentTarget == creature then
    priority = priority + 1
  end

  -- check if distance is ok
  if #path > config.maxDistance then
    if config.rpSafe then
      if currentTarget == creature then
        g_game.cancelAttackAndFollow()  -- if not, stop attack (pvp safe)
      end
    end
    return priority
  end

  -- add config priority
  priority = priority + config.priority
  
  -- extra priority for close distance
  local path_length = #path
  local max_increase_by_distance = 10
  local max_distance = 5
  local trapped
  if cycle then
    if cycle.trapped == nil then cycle.trapped = isTrapped() end
    trapped = cycle.trapped
  else trapped = isTrapped() end
  if trapped and path_length == 1 then
    priority = priority + (2 * max_increase_by_distance) -- double extra priority if trapped
  elseif path_length <= max_distance then
    local calc = (max_distance - path_length + 1) / max_distance * max_increase_by_distance
    priority = priority + calc
  end

  -- extra priority for paladin area arrows
  if config.diamondArrows or config.burstArrows then
    local bestArrowPriority = nil

    if config.diamondArrows then
      bestArrowPriority = addArrowAreaPriority(diamondArrowArea)
    end
    if config.burstArrows then
      local burstPriority = addArrowAreaPriority(burstArrowArea)
      if burstPriority and (not bestArrowPriority or burstPriority > bestArrowPriority) then
        bestArrowPriority = burstPriority
      end
    end

    if not bestArrowPriority then return 0 end
    priority = priority + bestArrowPriority
  end

  -- extra priority for low health
  local max_increase_by_health = 10
  local hp = creature:getHealthPercent()
  if config.chase and hp < 30 then
    priority = priority + max_increase_by_health
  else
    local calc = (100 - hp) / 100 * max_increase_by_health
    priority = priority + calc
  end

  return priority
end
