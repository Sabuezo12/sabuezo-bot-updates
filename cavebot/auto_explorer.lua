-- Auto Explorer for CaveBot.
-- It walks reachable unvisited tiles inside a configured radius and can follow floor changes.
CaveBot.AutoExplorer = CaveBot.AutoExplorer or {}

local AutoExplorer = CaveBot.AutoExplorer
local THINK_INTERVAL = 50
local FAST_STEP_DELAY = 60
local SCAN_INTERVAL = 180
local EMPTY_SCAN_INTERVAL = 650
local MAX_PATH_CHECKS = 18
local BLOCK_TIME = 8000
local STUCK_TIME = 2200
local NO_PROGRESS_TIME = 3500
local COVERAGE_RADIUS = 2
local FRONTIER_RADIUS = 4
local RECENT_TARGET_TIME = 12000
local TARGETBOT_PAUSE_DELAY = 250
local PATROL_RECENT_TIME = 45000
local DEATH_START_GRACE = 2500
local DEATH_HP_CONFIRM_TIME = 1800
local DEATH_OFFLINE_CONFIRM_TIME = 4000
local DEATH_SAFE_HP = 5
local MINIMAP_OVERLAY_UPDATE = 250
local MINIMAP_OVERLAY_THICKNESS = 2
local FLOOR_USE_COOLDOWN = 700

local FLOOR_CHANGE_USE_IDS = {
  [386] = true, [421] = true, [432] = true, [433] = true, [435] = true,
  [1947] = true, [1948] = true, [1968] = true, [1969] = true,
  [1386] = true, [1387] = true, [1388] = true, [1390] = true, [1391] = true, [1392] = true, [1394] = true,
  [5007] = true, [4911] = true, [5107] = true, [5108] = true, [5116] = true, [5117] = true,
  [5120] = true, [5122] = true, [5125] = true, [5126] = true, [5542] = true, [5733] = true,
  [5734] = true, [5736] = true, [5737] = true, [6250] = true, [6252] = true, [6253] = true,
  [6256] = true, [6257] = true, [6264] = true, [7131] = true, [7132] = true, [7727] = true,
  [8255] = true, [8256] = true, [8257] = true, [8258] = true
}

local state = {
  enabled = false,
  origin = nil,
  anchors = {},
  visited = {},
  walkedAt = {},
  walkCount = {},
  blocked = {},
  recentTargets = {},
  target = nil,
  targetWalkPos = nil,
  targetKey = nil,
  targetMode = "explore",
  targetStartedAt = 0,
  targetBestDistance = nil,
  targetNoProgressAt = 0,
  lastPosKey = nil,
  lastMoveAt = 0,
  startedAt = 0,
  nextThinkAt = 0,
  nextScanAt = 0,
  nextWalkAt = 0,
  nextOverlayUpdateAt = 0,
  lastFloorUseAt = 0,
  deathLowHpSince = 0,
  deathOfflineSince = 0,
  deathHadSafeHp = false,
  status = "Off",
  statusColor = "#c8c8c8"
}

local minimapOverlay = {
  widget = nil,
  parent = nil
}

local function currentTime()
  if type(now) == "number" then return now end
  if g_clock and g_clock.millis then
    local ok, value = pcall(function() return g_clock.millis() end)
    if ok and type(value) == "number" then return value end
  end
  return os and os.clock and math.floor(os.clock() * 1000) or 0
end

local function hasPosition(pos)
  return pos and pos.x and pos.y and pos.z
end

local function copyPosition(pos)
  if not hasPosition(pos) then return nil end
  return {x = pos.x, y = pos.y, z = pos.z}
end

local function positionKey(pos)
  if not hasPosition(pos) then return nil end
  return tostring(pos.x) .. "," .. tostring(pos.y) .. "," .. tostring(pos.z)
end

local function samePosition(a, b)
  return hasPosition(a) and hasPosition(b) and a.x == b.x and a.y == b.y and a.z == b.z
end

local function distance2d(a, b)
  if not hasPosition(a) or not hasPosition(b) then return 9999 end
  return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

local function clampRadius(value)
  value = tonumber(value) or 30
  if value < 5 then return 5 end
  if value > 120 then return 120 end
  return math.floor(value)
end

local function getRadius()
  local values = CaveBot.Config and CaveBot.Config.values or {}
  return clampRadius(values.autoExplorerRadius)
end

local function allowFloorChanges()
  local values = CaveBot.Config and CaveBot.Config.values or {}
  return values.autoExplorerFloors ~= false
end

local function getAnchor(pos)
  if hasPosition(state.origin) then return state.origin end

  if not hasPosition(pos) and player and player.getPosition then
    pos = player:getPosition()
  end
  if not hasPosition(pos) then return nil end

  state.origin = copyPosition(pos)
  return state.origin
end

local function inCurrentRadius(pos)
  if not hasPosition(pos) then return false end
  local anchor = getAnchor()
  return anchor and distance2d(pos, anchor) <= getRadius()
end

local function isFloorChangeByMinimap(pos)
  if not hasPosition(pos) or not g_map or not g_map.getMinimapColor then return false end
  local color = g_map.getMinimapColor(pos)
  return color and color >= 210 and color <= 213
end

local function tileHasCreature(tile)
  if not tile then return false end
  local ok, result = pcall(function()
    if tile.hasCreature then return tile:hasCreature() end
    local creatures = tile:getCreatures()
    return creatures and #creatures > 0
  end)
  return ok and result == true
end

local function isWalkableTile(tile)
  if not tile then return false end
  local ok, result = pcall(function() return tile:isWalkable() end)
  return ok and result == true
end

local function getTilePosition(tile)
  if not tile then return nil end
  local ok, pos = pcall(function() return tile:getPosition() end)
  return ok and pos or nil
end

local function listHasId(list, id)
  id = tonumber(id)
  if not id or type(list) ~= "table" then return false end
  if table.find then return table.find(list, id) ~= nil end
  for _, value in pairs(list) do
    if tonumber(value) == id then return true end
  end
  return false
end

local function safeUse(func, ...)
  if not func then return false end
  local ok, result = pcall(func, ...)
  return ok and result ~= false
end

local function tryUseThing(thing)
  if not thing then return false end
  if safeUse(use, thing) then return true end
  if g_game and g_game.use and safeUse(function(target) g_game.use(target) end, thing) then return true end
  return false
end

local function tryUseTool(toolId, thing)
  toolId = tonumber(toolId)
  if not toolId or toolId <= 0 or not thing then return false end
  if safeUse(useWith, toolId, thing) then return true end
  if g_game and g_game.useInventoryItemWith then
    return safeUse(function(id, target) g_game.useInventoryItemWith(id, target, 0) end, toolId, thing)
  end
  return false
end

local function getFloorChangeAction(tile, thing)
  if not tile or not thing or not thing.getId then return nil end
  local id = tonumber(thing:getId())
  if not id then return nil end

  local global = Global or {}
  if FLOOR_CHANGE_USE_IDS[id] then return "use" end
  if listHasId(global.ropeIds, id) then return "rope" end
  if listHasId(global.shovelIds, id) then return "shovel" end
  return nil
end

local function getFloorChangeThing(tile)
  if not tile then return nil, nil end

  local things = {}
  if tile.getTopUseThing then table.insert(things, tile:getTopUseThing()) end
  if tile.getTopThing then table.insert(things, tile:getTopThing()) end
  if tile.getGround then table.insert(things, tile:getGround()) end

  local items = tile.getItems and tile:getItems() or {}
  for _, item in ipairs(items) do
    table.insert(things, item)
  end

  for _, thing in ipairs(things) do
    local action = getFloorChangeAction(tile, thing)
    if action then return thing, action end
  end

  return nil, nil
end

local function isFloorChangeTile(tileOrPos, pos)
  local tile = nil
  if tileOrPos and tileOrPos.getPosition then
    tile = tileOrPos
    pos = pos or getTilePosition(tile)
  else
    pos = tileOrPos
  end

  if isFloorChangeByMinimap(pos) then return true end
  if tile and getFloorChangeThing(tile) then return true end
  return false
end

local function canCoverTile(tile)
  if not isWalkableTile(tile) then return false end
  if tile.canShoot then
    local ok, result = pcall(function() return tile:canShoot() end)
    if ok then return result == true end
  end
  return true
end

local function isBlocked(key)
  if not key then return false end
  local untilTime = state.blocked[key]
  if not untilTime then return false end
  if untilTime <= currentTime() then
    state.blocked[key] = nil
    return false
  end
  return true
end

local function markBlocked(pos)
  local key = positionKey(pos)
  if key then state.blocked[key] = currentTime() + BLOCK_TIME end
end

local function isRecentTarget(key)
  if not key then return false end
  local untilTime = state.recentTargets[key]
  if not untilTime then return false end
  if untilTime <= currentTime() then
    state.recentTargets[key] = nil
    return false
  end
  return true
end

local function markRecentTarget(key)
  if key then state.recentTargets[key] = currentTime() + RECENT_TARGET_TIME end
end

local function markVisited(pos)
  local key = positionKey(pos)
  if key then state.visited[key] = true end
end

local function markWalked(pos)
  local key = positionKey(pos)
  if not key then return end
  state.walkedAt[key] = currentTime()
  state.walkCount[key] = (tonumber(state.walkCount[key]) or 0) + 1
  markVisited(pos)
end

local function markAreaCovered(centerPos)
  if not hasPosition(centerPos) or not g_map or not g_map.getTiles then return end

  local okTiles, tiles = pcall(function() return g_map.getTiles(centerPos.z) end)
  if not okTiles or type(tiles) ~= "table" then return end

  for _, tile in pairs(tiles) do
    local tilePos = getTilePosition(tile)
    if tilePos and tilePos.z == centerPos.z and distance2d(centerPos, tilePos) <= COVERAGE_RADIUS then
      if not isFloorChangeTile(tile, tilePos) and inCurrentRadius(tilePos) and canCoverTile(tile) then
        markVisited(tilePos)
      end
    end
  end

  markVisited(centerPos)
end

local function countVisited()
  local total = 0
  for _ in pairs(state.visited) do
    total = total + 1
  end
  return total
end

local function compactStatus(text)
  text = tostring(text or "")
  local count = text:match("(%d+)%s+cubiertos")
  if text:find("Pausa: TargetBot", 1, true) then return "Pausa TB" end
  if text:find("Sin tiles nuevos", 1, true) then return count and ("Sin nuevos " .. count) or "Sin nuevos" end
  if text:find("Sin ruta disponible", 1, true) then return count and ("Sin ruta " .. count) or "Sin ruta" end
  if text:find("Recalculando", 1, true) then return "Recalculando" end
  if text:find("Ruta bloqueada", 1, true) then return "Bloqueado" end
  if text:find("^Piso") then return text:gsub(" | .*", "") end
  if text:find("^Patrulla") then return count and ("Patrulla " .. count) or "Patrulla" end
  if text:find("^On") then return count and ("On " .. count) or "On" end
  if text:find("^Off") then return count and ("Off " .. count) or "Off" end
  return text
end

local function setStatus(text, color)
  state.status = tostring(text or "")
  state.statusColor = color or "#ffffff"
  if AutoExplorer.panel and AutoExplorer.panel.statusRow and AutoExplorer.panel.statusRow.statusLabel then
    AutoExplorer.panel.statusRow.statusLabel:setText(compactStatus(state.status))
    AutoExplorer.panel.statusRow.statusLabel:setColor(state.statusColor)
    AutoExplorer.panel.statusRow.statusLabel:setTooltip(state.status)
  end
end

local function shouldPauseForTargetBot()
  if not TargetBot or not TargetBot.isActive then return false end

  local okActive, active = pcall(function() return TargetBot.isActive() end)
  if not okActive or active ~= true then return false end

  local allowed = false
  if TargetBot.isCaveBotActionAllowed then
    local okAllowed, value = pcall(function() return TargetBot.isCaveBotActionAllowed() end)
    allowed = okAllowed and value == true
  end

  return not allowed
end

local function looksLikeDeathText(text)
  if type(text) ~= "string" then return false end
  text = text:lower()
  return text:find("you are dead", 1, true) or
    text:find("you died", 1, true) or
    text:find("you were killed", 1, true)
end

local function resetDeathState()
  state.deathLowHpSince = 0
  state.deathOfflineSince = 0
  state.deathHadSafeHp = false
end

local function shouldDisableForDeath()
  if not state.enabled then return false end

  local time = currentTime()
  if state.startedAt and state.startedAt > 0 and time - state.startedAt < DEATH_START_GRACE then
    return false
  end

  if g_game and g_game.isOnline then
    local okOnline, online = pcall(function() return g_game.isOnline() end)
    if okOnline and online == false then
      if state.deathOfflineSince == 0 then state.deathOfflineSince = time end
      if time - state.deathOfflineSince >= DEATH_OFFLINE_CONFIRM_TIME then return true end
    else
      state.deathOfflineSince = 0
    end
  end

  if type(hppercent) == "function" then
    local okHp, hp = pcall(hppercent)
    hp = okHp and tonumber(hp) or nil
    if hp then
      if hp > DEATH_SAFE_HP then
        state.deathHadSafeHp = true
        state.deathLowHpSince = 0
      elseif hp <= 0 and state.deathHadSafeHp then
        if state.deathLowHpSince == 0 then state.deathLowHpSince = time end
        if time - state.deathLowHpSince >= DEATH_HP_CONFIRM_TIME then return true end
      else
        state.deathLowHpSince = 0
      end
    end
  end

  return false
end

local function getMinimapWidget()
  if not modules or not modules.game_minimap then return nil end
  return modules.game_minimap.minimapWidget
end

local function hideMinimapOverlay()
  if minimapOverlay.widget then
    pcall(function() minimapOverlay.widget:setVisible(false) end)
  end
end

local function createMinimapOverlay()
  local minimap = getMinimapWidget()
  if not minimap then return nil end

  if minimapOverlay.widget and minimapOverlay.parent == minimap then
    return minimapOverlay.widget
  end

  if minimapOverlay.widget then
    pcall(function() minimapOverlay.widget:destroy() end)
  end

  minimapOverlay.parent = minimap
  minimapOverlay.widget = setupUI([[
Panel
  id: autoExplorerMinimapOverlay
  anchors.fill: parent
  phantom: true
  focusable: false
  visible: false
  background-color: alpha

  UIWidget
    id: top
    anchors.left: parent.left
    anchors.top: parent.top
    width: 2
    height: 2
    phantom: true
    focusable: false
    background-color: #00ffd088

  UIWidget
    id: bottom
    anchors.left: parent.left
    anchors.top: parent.top
    width: 2
    height: 2
    phantom: true
    focusable: false
    background-color: #00ffd088

  UIWidget
    id: left
    anchors.left: parent.left
    anchors.top: parent.top
    width: 2
    height: 2
    phantom: true
    focusable: false
    background-color: #00ffd088

  UIWidget
    id: right
    anchors.left: parent.left
    anchors.top: parent.top
    width: 2
    height: 2
    phantom: true
    focusable: false
    background-color: #00ffd088

  UIWidget
    id: center
    anchors.left: parent.left
    anchors.top: parent.top
    width: 4
    height: 4
    phantom: true
    focusable: false
    background-color: #ffffffcc
]], minimap)

  pcall(function() minimapOverlay.widget:raise() end)
  return minimapOverlay.widget
end

local function getWidgetSize(widget)
  if not widget then return nil, nil end

  if widget.getSize then
    local ok, size = pcall(function() return widget:getSize() end)
    if ok and size then
      local width = tonumber(size.width or size.x)
      local height = tonumber(size.height or size.y)
      if width and height then return width, height end
    end
  end

  local width, height
  if widget.getWidth then
    local ok, value = pcall(function() return widget:getWidth() end)
    if ok then width = tonumber(value) end
  end
  if widget.getHeight then
    local ok, value = pcall(function() return widget:getHeight() end)
    if ok then height = tonumber(value) end
  end

  return width, height
end

local function getWidgetPosition(widget)
  if not widget or not widget.getPosition then return nil end
  local ok, pos = pcall(function() return widget:getPosition() end)
  if ok and pos and pos.x and pos.y then return pos end
  return nil
end

local function getMinimapTileAt(minimap, localX, localY)
  local origin = getWidgetPosition(minimap)
  if not origin or not minimap or not minimap.getTilePosition then return nil end

  local screenPos = {
    x = math.floor(origin.x + localX),
    y = math.floor(origin.y + localY)
  }
  local ok, mapPos = pcall(function() return minimap:getTilePosition(screenPos) end)
  if ok and hasPosition(mapPos) then return mapPos end
  return nil
end

local function estimateMinimapScale(minimap, width, height)
  local centerX = math.floor(width / 2)
  local centerY = math.floor(height / 2)
  local centerPos = getMinimapTileAt(minimap, centerX, centerY)
  if not centerPos then return nil, nil end

  local sample = math.max(10, math.floor(math.min(width, height) / 3))
  local leftX = math.max(1, centerX - sample)
  local rightX = math.min(width - 2, centerX + sample)
  local topY = math.max(1, centerY - sample)
  local bottomY = math.min(height - 2, centerY + sample)

  local leftPos = getMinimapTileAt(minimap, leftX, centerY)
  local rightPos = getMinimapTileAt(minimap, rightX, centerY)
  if leftPos and rightPos and leftPos.z == centerPos.z and rightPos.z == centerPos.z then
    local tiles = math.abs(rightPos.x - leftPos.x)
    if tiles > 0 then
      return math.max(0.2, math.min(12, math.abs(rightX - leftX) / tiles)), centerPos
    end
  end

  local topPos = getMinimapTileAt(minimap, centerX, topY)
  local bottomPos = getMinimapTileAt(minimap, centerX, bottomY)
  if topPos and bottomPos and topPos.z == centerPos.z and bottomPos.z == centerPos.z then
    local tiles = math.abs(bottomPos.y - topPos.y)
    if tiles > 0 then
      return math.max(0.2, math.min(12, math.abs(bottomY - topY) / tiles)), centerPos
    end
  end

  return nil, centerPos
end

local function clamp(value, minValue, maxValue)
  if value < minValue then return minValue end
  if value > maxValue then return maxValue end
  return value
end

local function setOverlayLine(widget, x, y, width, height)
  if not widget then return end
  pcall(function() widget:setVisible(true) end)
  pcall(function() widget:setMarginLeft(math.floor(x)) end)
  pcall(function() widget:setMarginTop(math.floor(y)) end)
  pcall(function() widget:setSize({width = math.max(1, math.floor(width)), height = math.max(1, math.floor(height))}) end)
  pcall(function() widget:setWidth(math.max(1, math.floor(width))) end)
  pcall(function() widget:setHeight(math.max(1, math.floor(height))) end)
end

local function updateMinimapOverlay(playerPos, force)
  if not state.enabled then
    hideMinimapOverlay()
    return
  end

  local time = currentTime()
  if not force and time < (state.nextOverlayUpdateAt or 0) then return end
  state.nextOverlayUpdateAt = time + MINIMAP_OVERLAY_UPDATE

  if not hasPosition(playerPos) then
    hideMinimapOverlay()
    return
  end

  local minimap = getMinimapWidget()
  local overlay = createMinimapOverlay()
  if not minimap or not overlay then return end

  local width, height = getWidgetSize(minimap)
  if not width or not height or width < 20 or height < 20 then
    hideMinimapOverlay()
    return
  end

  local scale, centerMapPos = estimateMinimapScale(minimap, width, height)
  if not scale or not centerMapPos or centerMapPos.z ~= playerPos.z then
    hideMinimapOverlay()
    return
  end

  local centerX = width / 2
  local centerY = height / 2
  local anchor = getAnchor(playerPos)
  if not anchor then
    hideMinimapOverlay()
    return
  end

  local anchorX = centerX + (anchor.x - centerMapPos.x) * scale
  local anchorY = centerY + (anchor.y - centerMapPos.y) * scale
  if anchorX < -width or anchorX > width * 2 or anchorY < -height or anchorY > height * 2 then
    hideMinimapOverlay()
    return
  end

  local halfSize = getRadius() * scale
  local left = math.floor(anchorX - halfSize)
  local right = math.floor(anchorX + halfSize)
  local top = math.floor(anchorY - halfSize)
  local bottom = math.floor(anchorY + halfSize)

  if right < 0 or bottom < 0 or left > width or top > height then
    hideMinimapOverlay()
    return
  end

  left = clamp(left, 0, width - 1)
  right = clamp(right, 0, width - 1)
  top = clamp(top, 0, height - 1)
  bottom = clamp(bottom, 0, height - 1)

  local boxWidth = right - left
  local boxHeight = bottom - top
  if boxWidth < 3 or boxHeight < 3 then
    hideMinimapOverlay()
    return
  end

  local thickness = MINIMAP_OVERLAY_THICKNESS
  setOverlayLine(overlay.top, left, top, boxWidth, thickness)
  setOverlayLine(overlay.bottom, left, bottom, boxWidth, thickness)
  setOverlayLine(overlay.left, left, top, thickness, boxHeight)
  setOverlayLine(overlay.right, right, top, thickness, boxHeight + thickness)
  setOverlayLine(overlay.center, clamp(anchorX - 2, 0, width - 4), clamp(anchorY - 2, 0, height - 4), 4, 4)

  pcall(function() overlay:setVisible(true) end)
  pcall(function() overlay:raise() end)
end

local function updateButtons()
  if not AutoExplorer.panel then return end
  local button = AutoExplorer.panel.enabled
  button:setOn(state.enabled == true)
  pcall(function()
    button:setImageColor(state.enabled and "#663333" or "#225533")
  end)
end

local function resetRuntime(keepEnabled)
  state.origin = nil
  state.anchors = {}
  state.visited = {}
  state.walkedAt = {}
  state.walkCount = {}
  state.blocked = {}
  state.recentTargets = {}
  state.target = nil
  state.targetWalkPos = nil
  state.targetKey = nil
  state.targetMode = "explore"
  state.targetStartedAt = 0
  state.targetBestDistance = nil
  state.targetNoProgressAt = 0
  state.lastPosKey = nil
  state.lastMoveAt = currentTime()
  state.startedAt = currentTime()
  state.nextThinkAt = 0
  state.nextScanAt = 0
  state.nextWalkAt = 0
  state.nextOverlayUpdateAt = 0
  state.lastFloorUseAt = 0
  resetDeathState()

  if player and player.getPosition then
    local pos = player:getPosition()
    if hasPosition(pos) then
      state.origin = copyPosition(pos)
      state.anchors[pos.z] = copyPosition(pos)
      markAreaCovered(pos)
      markWalked(pos)
      state.lastPosKey = positionKey(pos)
    end
  end

  if keepEnabled then
    setStatus("On | " .. countVisited() .. " cubiertos", "#8cff9a")
  else
    setStatus("Off", "#c8c8c8")
  end
end

local function getPathParams()
  local ignoreFields = false
  if CaveBot.Config and CaveBot.Config.get then
    local ok, value = pcall(function() return CaveBot.Config.get("ignoreFields") end)
    ignoreFields = ok and value == true
  end

  return {
    ignoreNonPathable = true,
    ignoreCreatures = false,
    ignoreFields = ignoreFields,
    precision = 0,
    ignoreStairs = not allowFloorChanges(),
    allowUnseen = false,
    allowOnlyVisibleTiles = true
  }
end

local function getPathTo(pos, maxDistance)
  if not getPath or not player or not player.getPosition then return nil end
  local ok, path = pcall(function()
    return getPath(player:getPosition(), pos, maxDistance, getPathParams())
  end)
  if ok and path and path[1] then return path end
  return nil
end

local function getFloorStandPosition(pos, maxDistance)
  if not hasPosition(pos) or not player or not player.getPosition then return nil, nil end

  local playerPos = player:getPosition()
  if not hasPosition(playerPos) or playerPos.z ~= pos.z then return nil, nil end
  if distance2d(playerPos, pos) <= 1 then return copyPosition(playerPos), {} end

  local offsets = {
    {x = 0, y = -1}, {x = 1, y = 0}, {x = 0, y = 1}, {x = -1, y = 0},
    {x = 1, y = -1}, {x = 1, y = 1}, {x = -1, y = 1}, {x = -1, y = -1}
  }
  local bestPos = nil
  local bestPath = nil
  local bestLength = nil

  for _, offset in ipairs(offsets) do
    local standPos = {x = pos.x + offset.x, y = pos.y + offset.y, z = pos.z}
    if inCurrentRadius(standPos) then
      local tile = g_map and g_map.getTile and g_map.getTile(standPos) or nil
      if tile and isWalkableTile(tile) and not tileHasCreature(tile) and not isBlocked(positionKey(standPos)) then
        local path = getPathTo(standPos, maxDistance)
        if path then
          local length = #path
          if not bestLength or length < bestLength then
            bestLength = length
            bestPos = copyPosition(standPos)
            bestPath = path
          end
        end
      end
    end
  end

  return bestPos, bestPath
end

local function canUseTile(tile)
  local pos = getTilePosition(tile)
  if not inCurrentRadius(pos) then return false end
  if tileHasCreature(tile) then return false end
  if isBlocked(positionKey(pos)) then return false end

  local floorTile = isFloorChangeTile(tile, pos)
  if floorTile and not allowFloorChanges() then return false end
  if not isWalkableTile(tile) then
    local floorThing = getFloorChangeThing(tile)
    if not (floorTile and floorThing and allowFloorChanges()) then return false end
  end

  return true
end

local function candidateScore(candidate, mode)
  local score = 0
  mode = mode or "explore"

  if mode == "patrol" then
    local age = candidate.lastWalkedAt > 0 and math.min(90000, currentTime() - candidate.lastWalkedAt) or 90000
    score = score + math.floor(age / 1000) * 5
    score = score - candidate.walkCount * 35
    score = score + math.min(candidate.distance, 10) * 8
    score = score + candidate.anchorDistance * 2
  else
    score = score + candidate.frontier * 30
    score = score + candidate.anchorDistance * 6
    score = score - candidate.distance * 3
  end

  if candidate.floorTile and allowFloorChanges() then
    score = score + 10
  end
  if isRecentTarget(candidate.key) then
    score = score - (mode == "patrol" and 220 or 120)
  end
  if candidate.lastWalkedAt > 0 and currentTime() - candidate.lastWalkedAt < PATROL_RECENT_TIME then
    score = score - (mode == "patrol" and 180 or 30)
  end

  return score
end

local function buildCandidates(mode)
  mode = mode or "explore"
  local playerPos = player and player.getPosition and player:getPosition() or nil
  if not hasPosition(playerPos) then return {} end
  getAnchor(playerPos)

  local candidates = {}
  local okTiles, tiles = pcall(function() return g_map.getTiles(posz()) end)
  if not okTiles or type(tiles) ~= "table" then return candidates end

  for _, tile in pairs(tiles) do
    if canUseTile(tile) then
      local tilePos = getTilePosition(tile)
      if tilePos and not samePosition(tilePos, playerPos) then
        local key = positionKey(tilePos)
        if key and (mode == "patrol" or not state.visited[key]) then
          local floorThing = getFloorChangeThing(tile)
          local candidate = {
            pos = copyPosition(tilePos),
            key = key,
            distance = distance2d(playerPos, tilePos),
            anchorDistance = distance2d(getAnchor(playerPos), tilePos),
            floorTile = isFloorChangeTile(tile, tilePos),
            floorUse = floorThing ~= nil,
            lastWalkedAt = tonumber(state.walkedAt[key]) or 0,
            walkCount = tonumber(state.walkCount[key]) or 0,
            frontier = 0,
            score = 0
          }
          table.insert(candidates, candidate)
        end
      end
    end
  end

  for _, candidate in ipairs(candidates) do
    local frontier = 0
    for _, other in ipairs(candidates) do
      if distance2d(candidate.pos, other.pos) <= FRONTIER_RADIUS then
        frontier = frontier + 1
      end
    end
    candidate.frontier = frontier
    candidate.score = candidateScore(candidate, mode)
  end

  table.sort(candidates, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    if a.frontier ~= b.frontier then return a.frontier > b.frontier end
    if a.anchorDistance ~= b.anchorDistance then return a.anchorDistance > b.anchorDistance end
    return a.distance < b.distance
  end)

  return candidates
end

local function chooseTargetFromCandidates(candidates, mode)
  local radius = getRadius()
  local maxDistance = math.max(8, radius * 2 + 10)
  local checked = 0
  local best = nil

  for _, candidate in ipairs(candidates) do
    if checked >= MAX_PATH_CHECKS then break end
    checked = checked + 1

    local path = getPathTo(candidate.pos, maxDistance)
    local walkPos = candidate.pos
    if not path and candidate.floorUse and allowFloorChanges() then
      walkPos, path = getFloorStandPosition(candidate.pos, maxDistance)
    end
    if path then
      local pathScore = candidate.score - (#path * 2)
      if not best or pathScore > best.score then
        best = {pos = candidate.pos, key = candidate.key, path = path, walkPos = walkPos, score = pathScore}
      end
    else
      markBlocked(candidate.pos)
    end
  end

  if best then
    return best.pos, best.key, best.path, mode, best.walkPos
  end

  return nil, nil, nil, mode, nil
end

local function chooseTarget()
  local target, key, path, mode, walkPos = chooseTargetFromCandidates(buildCandidates("explore"), "explore")
  if target then return target, key, path, mode, walkPos end

  target, key, path, mode, walkPos = chooseTargetFromCandidates(buildCandidates("patrol"), "patrol")
  if target then return target, key, path, mode, walkPos end

  return nil, nil, nil, "idle", nil
end

local function setTarget(pos, key, mode, walkPos)
  state.target = pos
  state.targetWalkPos = walkPos and copyPosition(walkPos) or nil
  state.targetKey = key
  state.targetMode = mode or "explore"
  state.targetStartedAt = currentTime()
  state.targetBestDistance = player and player.getPosition and distance2d(player:getPosition(), pos) or nil
  state.targetNoProgressAt = currentTime()
end

local function clearTarget(remember)
  if remember then
    markRecentTarget(state.targetKey)
  end
  state.target = nil
  state.targetWalkPos = nil
  state.targetKey = nil
  state.targetMode = "explore"
  state.targetStartedAt = 0
  state.targetBestDistance = nil
  state.targetNoProgressAt = 0
end

local function tryUseFloorChangeTarget(target)
  if not allowFloorChanges() or not hasPosition(target) or not player or not player.getPosition then return false end

  local playerPos = player:getPosition()
  if not hasPosition(playerPos) or playerPos.z ~= target.z then return false end
  if distance2d(playerPos, target) > 1 then return false end

  local tile = g_map and g_map.getTile and g_map.getTile(target) or nil
  if not tile then return false end
  if isWalkableTile(tile) and not samePosition(playerPos, target) then return false end

  local thing, action = getFloorChangeThing(tile)
  if not thing or not action then return false end

  local time = currentTime()
  if time - (state.lastFloorUseAt or 0) < FLOOR_USE_COOLDOWN then return true end

  local used = false
  local extras = storage and storage.extras or {}
  if action == "rope" then
    used = tryUseTool(extras.rope or 3003, thing)
  elseif action == "shovel" then
    used = tryUseTool(extras.shovel or 3457, thing)
  else
    used = tryUseThing(thing)
  end

  if used then
    state.lastFloorUseAt = time
    state.nextWalkAt = time + FLOOR_USE_COOLDOWN
    state.nextScanAt = time + FLOOR_USE_COOLDOWN
    if CaveBot.resetWalking then pcall(CaveBot.resetWalking) end
    setStatus("Usando cambio de piso", "#8fd3ff")
    return true
  end

  return false
end

local function walkToTarget(target)
  if not CaveBot.walkTo then return false end
  if tryUseFloorChangeTarget(target) then return true end

  local radius = getRadius()
  local walkTarget = state.targetWalkPos or target
  if hasPosition(walkTarget) and samePosition(walkTarget, player:getPosition()) and tryUseFloorChangeTarget(target) then
    return true
  end

  local ok, result = pcall(function()
    return CaveBot.walkTo(walkTarget, math.max(8, radius * 2 + 10), getPathParams())
  end)
  return ok and result == true
end

local function processStuck(playerPos)
  if state.target then
    local distance = distance2d(playerPos, state.target)
    if not state.targetBestDistance or distance < state.targetBestDistance then
      state.targetBestDistance = distance
      state.targetNoProgressAt = currentTime()
    elseif currentTime() - (state.targetNoProgressAt or 0) > NO_PROGRESS_TIME then
      markBlocked(state.target)
      clearTarget(true)
      state.lastMoveAt = currentTime()
      setStatus("Recalculando sin progreso", "#ffd166")
      return true
    end
  end

  local key = positionKey(playerPos)
  if key ~= state.lastPosKey then
    state.lastPosKey = key
    state.lastMoveAt = currentTime()
    return false
  end

  if state.target and currentTime() - (state.lastMoveAt or 0) > STUCK_TIME then
    markBlocked(state.target)
    clearTarget(true)
    state.lastMoveAt = currentTime()
    setStatus("Recalculando ruta", "#ffd166")
    return true
  end

  return false
end

local function keepInsideRadius(playerPos)
  if inCurrentRadius(playerPos) then return false end

  clearTarget(false)
  if CaveBot.resetWalking then pcall(CaveBot.resetWalking) end

  local anchor = getAnchor(playerPos)
  if anchor and playerPos.z == anchor.z and CaveBot.walkTo then
    local maxDistance = math.max(8, distance2d(playerPos, anchor) + 8)
    local ok, walking = pcall(function()
      return CaveBot.walkTo(anchor, maxDistance, getPathParams())
    end)
    if ok and walking then
      state.nextWalkAt = currentTime() + FAST_STEP_DELAY
      setStatus("Volviendo al radio", "#ffd166")
      return true
    end
  end

  AutoExplorer.disable()
  setStatus("Off | fuera del radio", "#ff7777")
  return true
end

local function explorerTick()
  if not state.enabled then return end
  if currentTime() < (state.nextThinkAt or 0) then return end
  state.nextThinkAt = currentTime() + THINK_INTERVAL

  if shouldDisableForDeath() then
    AutoExplorer.disable()
    setStatus("Off | muerte detectada", "#ff7777")
    return
  end

  if not player or not player.getPosition or not g_map then return end
  local playerPos = player:getPosition()
  if not hasPosition(playerPos) then return end
  updateMinimapOverlay(playerPos)

  getAnchor(playerPos)
  if keepInsideRadius(playerPos) then return end

  markAreaCovered(playerPos)
  markWalked(playerPos)

  if state.target and state.targetKey and state.visited[state.targetKey] and distance2d(playerPos, state.target) <= COVERAGE_RADIUS then
    clearTarget(true)
    if CaveBot.resetWalking then pcall(CaveBot.resetWalking) end
  end

  if shouldPauseForTargetBot() then
    if CaveBot.resetWalking then pcall(CaveBot.resetWalking) end
    state.nextWalkAt = currentTime() + TARGETBOT_PAUSE_DELAY
    state.nextScanAt = currentTime() + TARGETBOT_PAUSE_DELAY
    setStatus("Pausa: TargetBot | " .. countVisited() .. " cubiertos", "#ffd166")
    return
  end

  if currentTime() >= (state.nextWalkAt or 0) and CaveBot.doWalking and CaveBot.doWalking() then
    state.nextWalkAt = currentTime() + FAST_STEP_DELAY
    local label = state.targetMode == "patrol" and "Patrulla" or "On"
    setStatus(label .. " | " .. countVisited() .. " cubiertos", state.targetMode == "patrol" and "#8fd3ff" or "#8cff9a")
    return
  end

  if currentTime() < (state.nextWalkAt or 0) then
    return
  end

  if processStuck(playerPos) then return end

  if state.target and samePosition(playerPos, state.target) then
    markAreaCovered(state.target)
    clearTarget(true)
  end

  if state.target and isBlocked(state.targetKey) then
    clearTarget(false)
  end

  if not state.target then
    if currentTime() < (state.nextScanAt or 0) then return end
    state.nextScanAt = currentTime() + SCAN_INTERVAL
    local target, key, _, mode, walkPos = chooseTarget()
    if target then
      setTarget(target, key, mode, walkPos)
    end
  end

  if not state.target then
    state.nextScanAt = currentTime() + EMPTY_SCAN_INTERVAL
    setStatus("Sin ruta disponible | " .. countVisited() .. " cubiertos", "#ffaa00")
    return
  end

  if not walkToTarget(state.target) then
    markBlocked(state.target)
    clearTarget(true)
    state.nextScanAt = currentTime() + SCAN_INTERVAL
    setStatus("Ruta bloqueada", "#ffd166")
    return
  end

  state.nextWalkAt = currentTime() + FAST_STEP_DELAY
  local label = state.targetMode == "patrol" and "Patrulla" or "On"
  setStatus(label .. " | " .. countVisited() .. " cubiertos", state.targetMode == "patrol" and "#8fd3ff" or "#8cff9a")
end

AutoExplorer.isOn = function()
  return state.enabled == true
end

AutoExplorer.enable = function()
  if state.enabled then return end
  if CaveBot.Recorder and CaveBot.Recorder.isOn and CaveBot.Recorder.isOn() then
    CaveBot.Recorder.disable()
  end
  if CaveBot.setOff then pcall(CaveBot.setOff) end
  if CaveBot.resetWalking then pcall(CaveBot.resetWalking) end

  state.enabled = true
  resetRuntime(true)
  updateButtons()
  if player and player.getPosition then
    updateMinimapOverlay(player:getPosition(), true)
  end
  warn("Auto Explorer activado. Radio: " .. getRadius() .. " sqm.")
end

AutoExplorer.disable = function()
  if not state.enabled then return end
  state.enabled = false
  if CaveBot.resetWalking then pcall(CaveBot.resetWalking) end
  clearTarget(false)
  hideMinimapOverlay()
  setStatus("Off | " .. countVisited() .. " cubiertos", "#c8c8c8")
  updateButtons()
  warn("Auto Explorer detenido.")
end

AutoExplorer.reset = function()
  resetRuntime(state.enabled)
  if state.enabled and player and player.getPosition then
    updateMinimapOverlay(player:getPosition(), true)
  end
  if state.enabled then
    warn("Auto Explorer reiniciado desde la posicion actual.")
  end
  updateButtons()
end

local function registerExplorerNumber(id, defaultValue, widget, onSet)
  if CaveBot.Config.default_values[id] ~= nil then return end

  CaveBot.Config.value_setters[id] = function(value)
    value = clampRadius(value)
    CaveBot.Config.values[id] = value
    widget:setText(value, true)
    if onSet then onSet(value) end
  end

  CaveBot.Config.values[id] = defaultValue
  CaveBot.Config.default_values[id] = defaultValue
  CaveBot.Config.value_setters[id](defaultValue)

  widget.onTextChange = function(_, newValue)
    local value = tonumber(newValue)
    if not value then return end
    CaveBot.Config.values[id] = clampRadius(value)
    if onSet then onSet(CaveBot.Config.values[id]) end
    CaveBot.save()
  end
end

local function registerExplorerSwitch(id, defaultValue, widget, onSet)
  if CaveBot.Config.default_values[id] ~= nil then return end

  CaveBot.Config.value_setters[id] = function(value)
    value = value == true
    CaveBot.Config.values[id] = value
    widget:setOn(value, true)
    if onSet then onSet(value) end
  end

  CaveBot.Config.values[id] = defaultValue
  CaveBot.Config.default_values[id] = defaultValue
  CaveBot.Config.value_setters[id](defaultValue)

  widget.onClick = function(widget)
    widget:setOn(not widget:isOn())
    CaveBot.Config.values[id] = widget:isOn()
    if onSet then onSet(CaveBot.Config.values[id]) end
    CaveBot.save()
  end
end

AutoExplorer.setupMainPanel = function(panel)
  if not panel then return end
  AutoExplorer.panel = panel

  registerExplorerNumber("autoExplorerRadius", 30, panel.statusRow.radiusEdit, function()
    if state.enabled then AutoExplorer.reset() end
  end)
  registerExplorerSwitch("autoExplorerFloors", true, panel.optionsRow.floorSwitch, function()
    if state.enabled then clearTarget(false) end
  end)

  panel.enabled.onClick = function(widget)
    if state.enabled then
      AutoExplorer.disable()
    else
      AutoExplorer.enable()
    end
  end

  panel.optionsRow.resetButton.onClick = function()
    AutoExplorer.reset()
  end

  panel.enabled:setTooltip("Activa el explorador automatico. Apaga el CaveBot normal para evitar conflictos.")
  panel.optionsRow.resetButton:setTooltip("Limpia la memoria de tiles cubiertos y usa tu posicion actual como centro.")
  panel.statusRow.radiusEdit:setTooltip("Radio maximo desde la posicion donde activas o reseteas el Auto Explorer. Minimo 5, maximo 120 sqm.")
  panel.optionsRow.floorSwitch:setTooltip("Permite subir o bajar escaleras, rampas, agujeros y alcantarillas dentro del radio.")

  updateButtons()
  setStatus(state.status, state.statusColor)
end

onPlayerPositionChange(function(newPos, oldPos)
  if not state.enabled then return end
  if hasPosition(oldPos) then markAreaCovered(oldPos) end
  if not hasPosition(newPos) then return end
  updateMinimapOverlay(newPos, true)

  if hasPosition(oldPos) and newPos.z ~= oldPos.z then
    clearTarget(false)
    if CaveBot.resetWalking then pcall(CaveBot.resetWalking) end
    if not allowFloorChanges() then
      AutoExplorer.disable()
      setStatus("Off | cambio de piso bloqueado", "#ff7777")
      return
    end
    setStatus("Piso " .. tostring(newPos.z) .. " | " .. countVisited() .. " cubiertos", "#8cff9a")
  end

  markAreaCovered(newPos)
  markWalked(newPos)
end)

onTextMessage(function(mode, text)
  if not state.enabled then return end
  if not looksLikeDeathText(text) then return end
  AutoExplorer.disable()
  setStatus("Off | muerte detectada", "#ff7777")
end)

macro(THINK_INTERVAL, explorerTick)
