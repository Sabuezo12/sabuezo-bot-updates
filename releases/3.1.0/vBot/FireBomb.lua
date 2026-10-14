local panelName = "fireBomb"
local DEFAULT_FIRE_BOMB_RUNE_ID = 3192
local DEFAULT_FIRE_FIELD_IDS = "2118,118,105,2121,2122,2123,2124,2125,2126,2131,2132,2133,2134,2135"
local SURROUNDING_FIELD_COUNT = 8
local FIRE_BOMB_DELAY = 1500
local FIRE_OBSERVE_DELAY = 900
local FIRE_RESCAN_INTERVAL = 250

if not storage[panelName] then
  storage[panelName] = {
    enabled = false,
    fireBombRuneId = DEFAULT_FIRE_BOMB_RUNE_ID
  }
end

local config = storage[panelName]
config.fireBombRuneId = config.fireBombRuneId or DEFAULT_FIRE_BOMB_RUNE_ID
config.fireFieldIds = DEFAULT_FIRE_FIELD_IDS

local needsFireBomb = false
local pendingFireScanAt = 0
local observedFireTiles = {}
local lastPlayerPosKey = ""
local lastFireBombAt = 0
local lastFireScanAt = 0
local cachedFireIdsText = nil
local cachedFireIds = {}

local function getTime()
  if now then return now end
  if g_clock and g_clock.millis then return g_clock.millis() end
  return 0
end

local function parseIds(text)
  local ids = {}
  for id in tostring(text or ""):gmatch("%d+") do
    table.insert(ids, tonumber(id))
  end
  return ids
end

local function getFireIds()
  local text = DEFAULT_FIRE_FIELD_IDS
  if text ~= cachedFireIdsText then
    cachedFireIdsText = text
    cachedFireIds = parseIds(text)
  end
  return cachedFireIds
end

local function tableSize(t)
  local count = 0
  for _ in pairs(t or {}) do
    count = count + 1
  end
  return count
end

local function keyFromPos(p)
  if not p then return "" end
  return p.x .. "," .. p.y .. "," .. p.z
end

local function getPlayerPosKey()
  return keyFromPos(pos())
end

local function tileHasFire(tile)
  if not tile then return false end
  local fireIds = getFireIds()
  if #fireIds == 0 then return false end

  local ground = tile:getGround()
  if ground and table.find(fireIds, ground:getId()) then return true end

  for _, item in ipairs(tile:getItems()) do
    if table.find(fireIds, item:getId()) then return true end
  end

  local top = tile:getTopThing()
  return top and top:isItem() and table.find(fireIds, top:getId())
end

local function scanSurroundingFireTiles()
  local found = {}
  local center = pos()
  if not center then return found end

  for x = -1, 1 do
    for y = -1, 1 do
      if x ~= 0 or y ~= 0 then
        local p = {x = center.x + x, y = center.y + y, z = center.z}
        if tileHasFire(g_map.getTile(p)) then
          found[keyFromPos(p)] = true
        end
      end
    end
  end

  return found
end

local function hasObservedFireGone()
  local currentFireTiles = scanSurroundingFireTiles()
  observedFireTiles = currentFireTiles
  return tableSize(currentFireTiles) < SURROUNDING_FIELD_COUNT
end

local function getUseSubtype(itemId)
  local thing = g_things and g_things.getThingType and g_things.getThingType(itemId)
  if not thing or not thing:isFluidContainer() then
    return g_game.getClientVersion() >= 860 and 0 or 1
  end
  return 0
end

local function useItemWithId(itemId, target)
  if not itemId or not target then return false end

  local subType = getUseSubtype(itemId)
  local visibleItem = findItem(itemId)
  if visibleItem and g_game and g_game.useWith then
    local ok = pcall(function()
      g_game.useWith(visibleItem, target, subType)
    end)
    if ok then return true end
  end

  if g_game and g_game.getClientVersion and g_game.getClientVersion() < 780 then
    local tmpItem = g_game.findPlayerItem(itemId, subType)
    if tmpItem and g_game.useWith then
      g_game.useWith(tmpItem, target, subType)
      return true
    end
  elseif g_game and g_game.useInventoryItemWith then
    local ok = pcall(function()
      g_game.useInventoryItemWith(itemId, target, subType)
    end)
    if ok then return true end
  end

  if type(useWith) == "function" then
    local ok = pcall(function()
      useWith(itemId, target, subType)
    end)
    if ok then return true end
  end

  return false
end

local function useFireBomb(tile, force)
  if not force and getTime() - lastFireBombAt < FIRE_BOMB_DELAY then return false end
  if not tile then return false end

  local fireTiles = scanSurroundingFireTiles()
  if tableSize(fireTiles) >= SURROUNDING_FIELD_COUNT then
    observedFireTiles = fireTiles
    pendingFireScanAt = 0
    lastFireScanAt = getTime()
    return false
  end

  local thing = tile:getTopUseThing() or tile:getTopThing()
  if not thing then return false end
  if not useItemWithId(config.fireBombRuneId, thing) then return false end

  lastFireBombAt = getTime()
  pendingFireScanAt = lastFireBombAt + FIRE_OBSERVE_DELAY
  return true
end

local function requestFireBomb()
  needsFireBomb = true
  observedFireTiles = {}
  pendingFireScanAt = 0
  lastFireScanAt = 0
end

local function updateFireBomb(tile)
  local currentPosKey = getPlayerPosKey()
  if currentPosKey ~= lastPlayerPosKey then
    lastPlayerPosKey = currentPosKey
    requestFireBomb()
  end

  local time = getTime()

  if pendingFireScanAt > 0 and time >= pendingFireScanAt then
    local fireTiles = scanSurroundingFireTiles()
    observedFireTiles = fireTiles
    if tableSize(fireTiles) >= SURROUNDING_FIELD_COUNT then
      observedFireTiles = fireTiles
      pendingFireScanAt = 0
      lastFireScanAt = time
    elseif time - lastFireBombAt < FIRE_BOMB_DELAY then
      pendingFireScanAt = time + FIRE_RESCAN_INTERVAL
    else
      pendingFireScanAt = 0
      lastFireScanAt = time
    end
  end

  if needsFireBomb then
    local fireTiles = scanSurroundingFireTiles()
    if tableSize(fireTiles) >= SURROUNDING_FIELD_COUNT then
      observedFireTiles = fireTiles
      pendingFireScanAt = 0
      lastFireScanAt = time
      needsFireBomb = false
      return
    end

    if useFireBomb(tile, true) then
      needsFireBomb = false
    end
    return
  end

  if pendingFireScanAt == 0 and time - lastFireScanAt >= FIRE_RESCAN_INTERVAL then
    lastFireScanAt = time
    if hasObservedFireGone() then
      useFireBomb(tile)
    end
  end
end

local function setEnabled(enabled)
  config.enabled = enabled == true
  if config.enabled then
    lastPlayerPosKey = getPlayerPosKey()
    requestFireBomb()
    local tile = g_map.getTile(pos())
    if tile then
      useFireBomb(tile, true)
    end
  else
    needsFireBomb = false
    pendingFireScanAt = 0
    observedFireTiles = {}
  end
end

FireBomb = {
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

macro(20, function()
  if not config.enabled then return end
  local tile = g_map.getTile(pos())
  if tile then
    updateFireBomb(tile)
  end
end)
