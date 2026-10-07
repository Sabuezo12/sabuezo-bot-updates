local panelName = "keepWall"

local MAGIC_WALL_RUNE_ID = 3180
local MAGIC_WALL_OBJECT_IDS = {2128, 2129, 2130}
local WALL_DISTANCE = 2
local DEFAULT_KEEP_WALL_DELAY = 1000
local DEFAULT_KEEP_WALL_HOTKEY = ""
local TARGET_MOVE_PREDICT_MS = 350
local KEEP_WALL_EXTRA_LEAD_DISTANCE = 1
local KEEP_WALL_TICK_MS = 10
local ESCAPE_ROUTE_MAX_CANDIDATES = 3
local ESCAPE_ROUTE_HIGH_SCORE = 7

if not storage[panelName] then
  storage[panelName] = {
    enabled = false,
    runeId = MAGIC_WALL_RUNE_ID,
    wallDelay = DEFAULT_KEEP_WALL_DELAY,
    hotkey = DEFAULT_KEEP_WALL_HOTKEY
  }
end

local config = storage[panelName]
config.runeId = config.runeId or MAGIC_WALL_RUNE_ID
config.wallDelay = config.wallDelay or DEFAULT_KEEP_WALL_DELAY
config.hotkey = config.hotkey or DEFAULT_KEEP_WALL_HOTKEY
config.enabled = config.enabled == true

local lastCastAt = 0
local lastCastPosKey = ""
local keepWallPanel = nil
local keepWallWindow = nil
local waitingHotkey = false
local targetSnapshots = {}

local directionOffsets = {
  [0] = {x = 0, y = -1},
  [1] = {x = 1, y = 0},
  [2] = {x = 0, y = 1},
  [3] = {x = -1, y = 0},
  [4] = {x = 1, y = -1},
  [5] = {x = 1, y = 1},
  [6] = {x = -1, y = 1},
  [7] = {x = -1, y = -1}
}

if North ~= nil then directionOffsets[North] = {x = 0, y = -1} end
if East ~= nil then directionOffsets[East] = {x = 1, y = 0} end
if South ~= nil then directionOffsets[South] = {x = 0, y = 1} end
if West ~= nil then directionOffsets[West] = {x = -1, y = 0} end
if NorthEast ~= nil then directionOffsets[NorthEast] = {x = 1, y = -1} end
if SouthEast ~= nil then directionOffsets[SouthEast] = {x = 1, y = 1} end
if SouthWest ~= nil then directionOffsets[SouthWest] = {x = -1, y = 1} end
if NorthWest ~= nil then directionOffsets[NorthWest] = {x = -1, y = -1} end

local escapeRouteOffsets = {
  {x = 0, y = -1},
  {x = 1, y = 0},
  {x = 0, y = 1},
  {x = -1, y = 0},
  {x = 1, y = -1},
  {x = 1, y = 1},
  {x = -1, y = 1},
  {x = -1, y = -1}
}

local function getTime()
  if now then return now end
  if g_clock and g_clock.millis then return g_clock.millis() end
  return 0
end

local function trim(text)
  return tostring(text or ""):gsub("^%s*(.-)%s*$", "%1")
end

local function sameKey(a, b)
  return trim(a):lower() == trim(b):lower()
end

local function hasHotkey()
  return trim(config.hotkey) ~= ""
end

local function hasPosition(pos)
  return pos and pos.x and pos.y and pos.z
end

local function copyPosition(pos)
  if not hasPosition(pos) then return nil end
  return {x = pos.x, y = pos.y, z = pos.z}
end

local function samePosition(posA, posB)
  return hasPosition(posA) and hasPosition(posB) and posA.x == posB.x and posA.y == posB.y and posA.z == posB.z
end

local function positionKey(pos)
  if not hasPosition(pos) then return "" end
  return pos.x .. "," .. pos.y .. "," .. pos.z
end

local function getWallDelay()
  local wallDelay = tonumber(config.wallDelay) or DEFAULT_KEEP_WALL_DELAY
  if wallDelay < 1000 then wallDelay = 1000 end
  if wallDelay > 2000 then wallDelay = 2000 end
  return wallDelay
end

local function sameFloor(posA, posB)
  return hasPosition(posA) and hasPosition(posB) and posA.z == posB.z
end

local function getAttackTarget()
  if type(target) == "function" then
    local ok, creature = pcall(target)
    if ok and creature then return creature end
  end

  if type(getTarget) == "function" then
    local ok, creature = pcall(getTarget)
    if ok and creature then return creature end
  end

  if g_game and g_game.getAttackingCreature then
    local ok, creature = pcall(function() return g_game.getAttackingCreature() end)
    if ok and creature then return creature end
  end
end

local function getCreatureDirection(creature)
  if not creature or not creature.getDirection then return nil end

  local ok, direction = pcall(function()
    return creature:getDirection()
  end)
  if not ok then return nil end
  return direction
end

local function getCreatureName(creature)
  if not creature or not creature.getName then return nil end
  local ok, name = pcall(function() return creature:getName() end)
  return ok and name or nil
end

local function isCreatureWalking(creature)
  if not creature or not creature.isWalking then return false end
  local ok, walking = pcall(function() return creature:isWalking() end)
  return ok and walking == true
end

local function normalizeMoveOffset(dx, dy)
  if dx == 0 and dy == 0 then return nil end
  if math.abs(dx) > 1 or math.abs(dy) > 1 then return nil end
  return {x = dx, y = dy}
end

local function updateTargetSnapshot(creature, targetPos, direction, time)
  local key = getCreatureName(creature) or tostring(creature)
  local snapshot = targetSnapshots[key] or {}

  if snapshot.pos and sameFloor(snapshot.pos, targetPos) and not samePosition(snapshot.pos, targetPos) then
    local moveOffset = normalizeMoveOffset(targetPos.x - snapshot.pos.x, targetPos.y - snapshot.pos.y)
    if moveOffset then
      snapshot.moveOffset = moveOffset
      snapshot.movedAt = time
    end
  end

  if not samePosition(snapshot.pos, targetPos) or snapshot.direction ~= direction then
    snapshot.changedAt = time
  end

  snapshot.pos = copyPosition(targetPos)
  snapshot.direction = direction
  snapshot.updatedAt = time
  targetSnapshots[key] = snapshot
  return snapshot
end

local function addPositionCandidate(candidates, pos)
  if not hasPosition(pos) then return end
  local key = positionKey(pos)
  for _, candidate in ipairs(candidates) do
    if positionKey(candidate) == key then
      return
    end
  end
  table.insert(candidates, pos)
end

local function addWallCandidate(candidates, targetPos, offset, distance)
  if not offset then return end

  addPositionCandidate(candidates, {
    x = targetPos.x + (offset.x * distance),
    y = targetPos.y + (offset.y * distance),
    z = targetPos.z
  })
end

local function getKeepWallCandidates(creature, time)
  if not creature then return nil end

  time = time or getTime()
  local targetPos = copyPosition(creature:getPosition())
  if not sameFloor(targetPos, player:getPosition()) then return nil end

  local direction = getCreatureDirection(creature)
  local snapshot = updateTargetSnapshot(creature, targetPos, direction, time)
  local directionOffset = directionOffsets[direction]
  local movedRecently = snapshot and snapshot.moveOffset and snapshot.movedAt and time - snapshot.movedAt <= TARGET_MOVE_PREDICT_MS
  local candidates = {}

  if movedRecently then
    addWallCandidate(candidates, targetPos, snapshot.moveOffset, WALL_DISTANCE)
    addWallCandidate(candidates, targetPos, snapshot.moveOffset, WALL_DISTANCE + KEEP_WALL_EXTRA_LEAD_DISTANCE)
  end

  addWallCandidate(candidates, targetPos, directionOffset, WALL_DISTANCE)
  addWallCandidate(candidates, targetPos, directionOffset, WALL_DISTANCE + KEEP_WALL_EXTRA_LEAD_DISTANCE)

  if movedRecently and isCreatureWalking(creature) then
    addWallCandidate(candidates, targetPos, snapshot.moveOffset, WALL_DISTANCE + KEEP_WALL_EXTRA_LEAD_DISTANCE + 1)
  end

  return candidates
end

local function getKeepWallPosition(creature, time)
  local candidates = getKeepWallCandidates(creature, time)
  return candidates and candidates[1] or nil
end

local function tileHasMagicWall(tile)
  if not tile then return false end

  for _, item in ipairs(tile:getItems()) do
    if table.find(MAGIC_WALL_OBJECT_IDS, item:getId()) then
      return true
    end
  end

  local topThing = tile:getTopThing()
  return topThing and topThing:isItem() and table.find(MAGIC_WALL_OBJECT_IDS, topThing:getId())
end

local function listHasId(list, itemId)
  if not list or not itemId then return false end
  if table.find then
    return table.find(list, itemId) ~= nil
  end
  for _, id in ipairs(list) do
    if id == itemId then return true end
  end
  return false
end

local function getThingId(thing)
  if not thing or not thing.getId then return nil end
  local ok, itemId = pcall(function() return thing:getId() end)
  return ok and itemId or nil
end

local function isSpecialWallThing(thing)
  local itemId = getThingId(thing)
  if not itemId then return false end

  local global = Global or {}
  return listHasId(global.doorIds, itemId) or
    listHasId(global.useIds, itemId) or
    listHasId(global.ropeIds, itemId) or
    listHasId(global.shovelIds, itemId)
end

local function tileLooksLikeFloorChange(tile)
  if not tile or not tile.getPosition or not g_map or not g_map.getMinimapColor then return false end
  local minimapColor = g_map.getMinimapColor(tile:getPosition())
  return minimapColor and minimapColor >= 210 and minimapColor <= 213
end

local function isSpecialWallTile(tile)
  if not tile then return false end
  if tileLooksLikeFloorChange(tile) then return true end
  if isSpecialWallThing(tile:getTopUseThing()) then return true end
  if isSpecialWallThing(tile:getTopThing()) then return true end
  if tile.getGround and isSpecialWallThing(tile:getGround()) then return true end

  for _, item in ipairs(tile:getItems()) do
    if isSpecialWallThing(item) then return true end
  end

  return false
end

local function canUseMwallOn(tile)
  if not tile then return false end
  if tileHasMagicWall(tile) then return false end
  if tileHasCreature and tileHasCreature(tile) then return false end
  if tile.canShoot and not tile:canShoot() and not isSpecialWallTile(tile) then return false end
  return true
end

local function getMwallTargetThing(tile)
  if not tile then return nil end
  return tile:getTopUseThing() or tile:getTopThing() or (tile.getGround and tile:getGround())
end

local function offsetPosition(pos, offset, distance)
  if not hasPosition(pos) or not offset then return nil end
  return {
    x = pos.x + (offset.x * distance),
    y = pos.y + (offset.y * distance),
    z = pos.z
  }
end

local function sameOffset(offsetA, offsetB)
  return offsetA and offsetB and offsetA.x == offsetB.x and offsetA.y == offsetB.y
end

local function offsetDot(offsetA, offsetB)
  if not offsetA or not offsetB then return 0 end
  return (offsetA.x * offsetB.x) + (offsetA.y * offsetB.y)
end

local function sign(value)
  if value > 0 then return 1 end
  if value < 0 then return -1 end
  return 0
end

local function isEscapeStepOpen(tile)
  if not tile then return false end
  if tileHasMagicWall(tile) then return false end
  if tileHasCreature and tileHasCreature(tile) then return false end
  if isSpecialWallTile(tile) then return true end
  if tile.isWalkable and tile:isWalkable() then return true end
  return false
end

local function countOpenEscapeSides(pos, offset)
  if not hasPosition(pos) or not offset then return 0 end

  local sideOffsets = {}
  if offset.x == 0 then
    sideOffsets = {{x = 1, y = 0}, {x = -1, y = 0}}
  elseif offset.y == 0 then
    sideOffsets = {{x = 0, y = 1}, {x = 0, y = -1}}
  else
    sideOffsets = {{x = offset.x, y = 0}, {x = 0, y = offset.y}}
  end

  local openSides = 0
  for _, sideOffset in ipairs(sideOffsets) do
    local sideTile = g_map.getTile(offsetPosition(pos, sideOffset, 1))
    if isEscapeStepOpen(sideTile) then
      openSides = openSides + 1
    end
  end
  return openSides
end

local function scoreEscapeRoute(targetPos, playerPos, offset, snapshot, directionOffset, stepTile, wallTile, leadTile)
  local score = 0
  local awayOffset = normalizeMoveOffset(sign(targetPos.x - playerPos.x), sign(targetPos.y - playerPos.y))
  local awayScore = offsetDot(offset, awayOffset)

  if awayScore > 0 then
    score = score + (awayScore * 2)
  elseif awayScore < 0 then
    score = score - 2
  end

  if snapshot and snapshot.moveOffset then
    if sameOffset(offset, snapshot.moveOffset) then
      score = score + 5
    elseif offsetDot(offset, snapshot.moveOffset) > 0 then
      score = score + 2
    end
  end

  if directionOffset then
    if sameOffset(offset, directionOffset) then
      score = score + 4
    elseif offsetDot(offset, directionOffset) > 0 then
      score = score + 1
    end
  end

  if isSpecialWallTile(stepTile) or isSpecialWallTile(wallTile) or isSpecialWallTile(leadTile) then
    score = score + 8
  end

  local openSides = countOpenEscapeSides(offsetPosition(targetPos, offset, 1), offset)
  if openSides == 0 then
    score = score + 2
  elseif openSides == 1 then
    score = score + 1
  end

  return score
end

local function getEscapeWallCandidates(creature, time)
  if not creature then return nil end

  time = time or getTime()
  local targetPos = copyPosition(creature:getPosition())
  local playerPos = copyPosition(player:getPosition())
  if not sameFloor(targetPos, playerPos) then return nil end

  local direction = getCreatureDirection(creature)
  local directionOffset = directionOffsets[direction]
  local snapshot = updateTargetSnapshot(creature, targetPos, direction, time)
  local scored = {}

  for _, offset in ipairs(escapeRouteOffsets) do
    local stepPos = offsetPosition(targetPos, offset, 1)
    local wallPos = offsetPosition(targetPos, offset, WALL_DISTANCE)
    local leadPos = offsetPosition(targetPos, offset, WALL_DISTANCE + KEEP_WALL_EXTRA_LEAD_DISTANCE)
    local stepTile = g_map.getTile(stepPos)
    local wallTile = g_map.getTile(wallPos)
    local leadTile = g_map.getTile(leadPos)
    local stepIsSpecial = isSpecialWallTile(stepTile)
    local canWallStep = stepIsSpecial and canUseMwallOn(stepTile)
    local canWallRoute = canUseMwallOn(wallTile)

    if isEscapeStepOpen(stepTile) and (canWallRoute or canWallStep) then
      local score = scoreEscapeRoute(targetPos, playerPos, offset, snapshot, directionOffset, stepTile, wallTile, leadTile)
      table.insert(scored, {
        pos = canWallStep and stepPos or wallPos,
        leadPos = canWallStep and canWallRoute and wallPos or (canUseMwallOn(leadTile) and leadPos or nil),
        high = score >= ESCAPE_ROUTE_HIGH_SCORE or stepIsSpecial or isSpecialWallTile(wallTile),
        score = score
      })
    end
  end

  table.sort(scored, function(a, b)
    return a.score > b.score
  end)

  local high = {}
  local normal = {}
  for _, route in ipairs(scored) do
    local bucket = route.high and high or normal
    addPositionCandidate(bucket, route.pos)
    if route.leadPos then
      addPositionCandidate(bucket, route.leadPos)
    end
    if #high + #normal >= ESCAPE_ROUTE_MAX_CANDIDATES then
      break
    end
  end

  return {
    high = high,
    normal = normal
  }
end

local function getUseSubtype(itemId)
  local thing = g_things and g_things.getThingType and g_things.getThingType(itemId)
  if not thing or not thing:isFluidContainer() then
    return g_game.getClientVersion() >= 860 and 0 or 1
  end
  return 0
end

local function useItemWithId(itemId, targetThing)
  if not itemId or not targetThing then return false end

  local subType = getUseSubtype(itemId)
  local visibleItem = findItem(itemId)
  if visibleItem and g_game and g_game.useWith then
    local ok = pcall(function()
      g_game.useWith(visibleItem, targetThing, subType)
    end)
    if ok then return true end
  end

  if g_game and g_game.useInventoryItemWith then
    local ok = pcall(function()
      g_game.useInventoryItemWith(itemId, targetThing, subType)
    end)
    if ok then return true end
  end

  if type(useWith) == "function" then
    local ok = pcall(function()
      useWith(itemId, targetThing, subType)
    end)
    if ok then return true end
  end

  return false
end

local function castKeepWall(targetCreature)
  local time = getTime()
  if time - lastCastAt < getWallDelay() then return false end

  targetCreature = targetCreature or getAttackTarget()
  if not targetCreature then return false end

  local primaryCandidates = getKeepWallCandidates(targetCreature, time) or {}
  local escapeCandidates = getEscapeWallCandidates(targetCreature, time)
  local candidates = {}

  if escapeCandidates then
    for _, wallPos in ipairs(escapeCandidates.high) do
      addPositionCandidate(candidates, wallPos)
    end
  end

  for _, wallPos in ipairs(primaryCandidates) do
    addPositionCandidate(candidates, wallPos)
  end

  if escapeCandidates then
    for _, wallPos in ipairs(escapeCandidates.normal) do
      addPositionCandidate(candidates, wallPos)
    end
  end

  if #candidates == 0 then return false end

  for _, wallPos in ipairs(candidates) do
    local tile = g_map.getTile(wallPos)
    if canUseMwallOn(tile) then
      local thing = getMwallTargetThing(tile)
      if thing and useItemWithId(config.runeId, thing) then
        lastCastAt = time
        lastCastPosKey = positionKey(wallPos)
        return true
      end
    end
  end

  return false
end

local function setEnabled(enabled)
  config.enabled = enabled == true
  if keepWallPanel and keepWallPanel.title then
    keepWallPanel.title:setOn(config.enabled)
  end
  if not config.enabled then
    lastCastPosKey = ""
  end
end

KeepWall = {
  isOn = function()
    return config.enabled == true
  end,
  setOn = function()
    setEnabled(true)
  end,
  setOff = function()
    setEnabled(false)
  end,
  toggle = function()
    setEnabled(not config.enabled)
  end,
  getRuneId = function()
    return tonumber(config.runeId) or MAGIC_WALL_RUNE_ID
  end,
  getWallDelay = function()
    return getWallDelay()
  end
}

setDefaultTab("Main")

keepWallPanel = setupUI([[
Panel
  height: 19

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('KeepWall')

  Button
    id: setup
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 17
    text: Setup
]])
keepWallPanel:setId(panelName)
keepWallPanel.title:setOn(config.enabled)
keepWallPanel.title.onClick = function(widget)
  setEnabled(not config.enabled)
end

local rootWidget = g_ui.getRootWidget()
if rootWidget then
  keepWallWindow = UI.createWindow('KeepWallWindow', rootWidget)
  keepWallWindow:hide()

  keepWallPanel.setup.onClick = function(widget)
    keepWallWindow:show()
    keepWallWindow:raise()
    keepWallWindow:focus()
  end

  keepWallWindow.closeButton.onClick = function(widget)
    keepWallWindow:hide()
  end

  keepWallWindow.runeId.onItemChange = function(widget)
    config.runeId = widget:getItemId()
  end
  keepWallWindow.runeId:setItemId(config.runeId)

  if keepWallWindow.delay.setRange then
    keepWallWindow.delay:setRange(1000, 2000)
  end
  if keepWallWindow.delay.setStep then
    keepWallWindow.delay:setStep(100)
  end

  local updateDelayText = function()
    keepWallWindow.delayText:setText("Mwall Exhaust: " .. getWallDelay() .. "ms")
  end

  updateDelayText()
  keepWallWindow.delay.onValueChange = function(scroll, value)
    config.wallDelay = value
    updateDelayText()
  end
  keepWallWindow.delay:setValue(getWallDelay())

  local updateHotkeyText = function()
    local hotkey = trim(config.hotkey)
    if keepWallWindow.hotkeyButton then
      keepWallWindow.hotkeyButton:setText(waitingHotkey and "Press key..." or (hotkey ~= "" and hotkey or "None"))
      if keepWallWindow.hotkeyButton.setTooltip then
        keepWallWindow.hotkeyButton:setTooltip(hotkey ~= "" and ("Toggle hotkey: " .. hotkey) or "Click to set toggle hotkey.")
      end
    end
  end

  updateHotkeyText()
  if keepWallWindow.hotkeyButton then
    keepWallWindow.hotkeyButton.onClick = function(widget)
      waitingHotkey = true
      updateHotkeyText()
    end
  end
end

onKeyDown(function(key)
  if waitingHotkey then
    config.hotkey = sameKey(key, "Escape") and "" or key
    waitingHotkey = false
    if keepWallWindow and keepWallWindow.hotkeyButton then
      local hotkey = trim(config.hotkey)
      keepWallWindow.hotkeyButton:setText(hotkey ~= "" and hotkey or "None")
    end
    return
  end

  if hasHotkey() and sameKey(key, config.hotkey) then
    setEnabled(not config.enabled)
  end
end)

macro(KEEP_WALL_TICK_MS, function()
  if not config.enabled then return end
  local targetCreature = getAttackTarget()
  if targetCreature then
    getKeepWallPosition(targetCreature, getTime())
  end
  castKeepWall(targetCreature)
end)
