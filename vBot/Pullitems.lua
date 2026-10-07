local panelName = "pullItemsTurbo"

if not storage[panelName] then
  storage[panelName] = { enabled = false }
end

local config = storage[panelName]
local PULL_DELAY = 80

local function setEnabled(enabled)
  config.enabled = enabled == true
end

local function itemCount(item)
  local ok, count = pcall(function()
    return item:getCount()
  end)
  if ok and count and count > 0 then
    return count
  end
  return 1
end

local function canMoveItem(item)
  if not item then return false end

  if item.isGround then
    local ok, isGround = pcall(function()
      return item:isGround()
    end)
    if ok and isGround then return false end
  end

  if item.isNotMoveable then
    local ok, notMoveable = pcall(function()
      return item:isNotMoveable()
    end)
    if ok and notMoveable then return false end
  end

  return true
end

local function pullFromTile(tile, playerPos)
  local items = tile and tile:getItems()
  if not items then return false end

  local moved = false
  for i = #items, 1, -1 do
    local item = items[i]
    if canMoveItem(item) then
      local ok = pcall(function()
        g_game.move(item, playerPos, itemCount(item))
      end)
      moved = moved or ok
    end
  end

  return moved
end

PullItems = {
  isOn = function()
    return config.enabled == true
  end,
  setOn = function()
    return setEnabled(true)
  end,
  setOff = function()
    return setEnabled(false)
  end
}

macro(PULL_DELAY, function()
  if not config.enabled then return end

  local playerPos = pos()
  local tiles = {
    {x = playerPos.x, y = playerPos.y - 1, z = playerPos.z},
    {x = playerPos.x + 1, y = playerPos.y, z = playerPos.z},
    {x = playerPos.x, y = playerPos.y + 1, z = playerPos.z},
    {x = playerPos.x - 1, y = playerPos.y, z = playerPos.z},
    {x = playerPos.x + 1, y = playerPos.y - 1, z = playerPos.z},
    {x = playerPos.x + 1, y = playerPos.y + 1, z = playerPos.z},
    {x = playerPos.x - 1, y = playerPos.y + 1, z = playerPos.z},
    {x = playerPos.x - 1, y = playerPos.y - 1, z = playerPos.z},
  }

  for _, checkPos in ipairs(tiles) do
    pullFromTile(g_map.getTile(checkPos), playerPos)
  end
end)
