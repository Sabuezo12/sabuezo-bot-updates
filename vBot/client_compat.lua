modules = modules or {}

if not modules.game_walking then
  modules.game_walking = {}
end

modules.game_walking.wsadWalking = modules.game_walking.wsadWalking or false

if not modules.game_walking.bindTurnKeys then
  modules.game_walking.bindTurnKeys = function() end
end

if not modules.game_walking.unbindTurnKeys then
  modules.game_walking.unbindTurnKeys = function() end
end

local originalWalk = sabuezoOriginalWalk or walk
sabuezoOriginalWalk = originalWalk
local safeBotWalking = false

local function offsetByDir(fromPos, dir)
  if not fromPos or dir == nil then return nil end
  local offsets = {
    [0] = {x = 0, y = -1},
    [1] = {x = 1, y = 0},
    [2] = {x = 0, y = 1},
    [3] = {x = -1, y = 0},
    [4] = {x = 1, y = -1},
    [5] = {x = 1, y = 1},
    [6] = {x = -1, y = 1},
    [7] = {x = -1, y = -1}
  }
  local offset = offsets[dir]
  if not offset then return nil end
  return {x = fromPos.x + offset.x, y = fromPos.y + offset.y, z = fromPos.z}
end

function safeBotWalk(dir)
  if dir == nil then return false end
  if safeBotWalking then return false end

  safeBotWalking = true

  if g_game and type(g_game.walk) == "function" and g_game.walk ~= safeBotWalk then
    local ok, result = pcall(function()
      return g_game.walk(dir, false)
    end)
    if ok then
      safeBotWalking = false
      return result ~= false
    end
  end

  if originalWalk and originalWalk ~= safeBotWalk and originalWalk ~= walk then
    local ok, result = pcall(function()
      return originalWalk(dir)
    end)
    if ok then
      safeBotWalking = false
      return result ~= false
    end
  end

  if player and player.getPosition and player.autoWalk then
    local targetPos = offsetByDir(player:getPosition(), dir)
    if targetPos then
      local ok, result = pcall(function()
        return player:autoWalk(targetPos)
      end)
      if ok then
        safeBotWalking = false
        return result ~= false
      end
    end
  end

  safeBotWalking = false
  return false
end

walk = safeBotWalk
modules.game_walking.walk = safeBotWalk
modules.game_walking.smartWalk = safeBotWalk

if not modules.game_walking.stopSmartWalk then
  modules.game_walking.stopSmartWalk = function() end
end

function tileHasCreature(tile)
  if not tile then
    return false
  end

  if tile.getCreatures then
    local ok, creatures = pcall(function()
      return tile:getCreatures()
    end)
    return ok and creatures and #creatures > 0
  end

  if tile.getTopCreature then
    local ok, creature = pcall(function()
      return tile:getTopCreature()
    end)
    return ok and creature ~= nil
  end

  if tile.getTopThing then
    local ok, thing = pcall(function()
      return tile:getTopThing()
    end)
    if ok and thing and thing.isCreature then
      local creatureOk, isCreature = pcall(function()
        return thing:isCreature()
      end)
      return creatureOk and isCreature == true
    end
  end

  return false
end
