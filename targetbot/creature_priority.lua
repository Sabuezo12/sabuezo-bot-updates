TargetBot.Creature.calculatePriority = function(creature, config, path)
  -- config is based on creature_editor
  local priority = 0
  local currentTarget = g_game.getAttackingCreature()

  local function addArrowAreaPriority(pattern)
    local position = creature:getPosition()
    local mobCount = getCreaturesInArea(position, pattern, 2)

    if config.rpSafe and getCreaturesInArea(position, pattern, 3) > 0 then
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
  if isTrapped() and path_length == 1 then
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
