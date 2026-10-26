-- Automatic hunting inside a fixed radius, without a waypoint route.
-- Planning is bounded; movement follows confirmed steps at the native cadence.
CaveBot.AutoExplorer = CaveBot.AutoExplorer or {}

local AutoExplorer = CaveBot.AutoExplorer
local AREA_MIN = 20
local AREA_MAX = 120
local AREA_DEFAULT = 30
local THINK_INTERVAL = 20
local FAST_STEP_DELAY = 20
local STATUS_INTERVAL = 250
local SECTOR_SIZE = 6
local WALK_CHUNK_SIZE = 12
local SCAN_INTERVAL = 1800
local EMPTY_SCAN_INTERVAL = 2500
local MAX_PATH_CHECKS = 3
local BLOCK_TIME = 8000
local STUCK_TIME = 2200
local NO_PROGRESS_TIME = 3500
local COVERAGE_RADIUS = 2
local FRONTIER_RADIUS = 4
local RECENT_TARGET_TIME = 25000
local TARGETBOT_PAUSE_DELAY = 250
local PATROL_RECENT_TIME = 60000
local PATROL_MIN_DISTANCE = 6
local PATROL_PREFERRED_DISTANCE = 18
local PATROL_PATH_CHECKS = 4
local EDGE_SCAN_DISTANCE = 3
local RETURN_INSIDE_MARGIN = 4
local RETURN_PATH_CHECKS = 4
local CORRIDOR_OPEN_MAX = 2
local CORRIDOR_DIRECTION_BONUS = 85
local CORRIDOR_BASE_BONUS = 90
local DEATH_START_GRACE = 2500
local DEATH_HP_CONFIRM_TIME = 1800
local DEATH_OFFLINE_CONFIRM_TIME = 4000
local DEATH_SAFE_HP = 5
local MINIMAP_OVERLAY_UPDATE = 250
local MINIMAP_OVERLAY_THICKNESS = 2
local FLOOR_USE_COOLDOWN = 700
local FLOOR_RETURN_SCAN_INTERVAL = 900
local FLOOR_RETURN_PATH_CHECKS = 4
local MAX_SCAN_RADIUS = 18
local MAX_RETURN_SCAN_RADIUS = 22

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
  visitedCount = 0,
  sectors = {},
  lastWalkedKey = nil,
  lastSector = nil,
  nextEncounterAt = 0,
  holdUntil = 0,
  nextStatusAt = 0,
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
  lastStepDx = 0,
  lastStepDy = 0,
  startedAt = 0,
  nextThinkAt = 0,
  nextScanAt = 0,
  nextWalkAt = 0,
  nextOverlayUpdateAt = 0,
  lastFloorUseAt = 0,
  floorReturnTarget = nil,
  floorReturnStartedAt = 0,
  floorLinks = {},
  floorAvoid = {},
  lastFloorAction = nil,
  returnJob = nil,
  nextPlan = nil,
  huntRoute = nil,
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

local clearPatrolWalk, patrolWalkTo
local patrolWalk = {path=nil,index=1,from=nil,dest=nil,pending=nil,nextAt=0,nativeRetryAt=0,lastMode="steps",chain=nil}

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

local function sign(value)
  value = tonumber(value) or 0
  if value > 0 then return 1 end
  if value < 0 then return -1 end
  return 0
end

local function clampRadius(value)
  value = tonumber(value) or AREA_DEFAULT
  if value < AREA_MIN then return AREA_MIN end
  if value > AREA_MAX then return AREA_MAX end
  return math.floor(value)
end

local function getRadius()
  local values = CaveBot.Config and CaveBot.Config.values or {}
  return clampRadius(values.autoExplorerRadius)
end

local function sameFloorEnabled()
  local values = CaveBot.Config and CaveBot.Config.values or {}
  -- The legacy field was wired directly to the displayed "Mismo piso" switch.
  -- Preserve its displayed choice, rather than its inverted old implementation.
  return values.autoExplorerFloors ~= false
end

local function allowFloorChanges()
  return not sameFloorEnabled()
end

local function isPreviewEnabled()
  local values = CaveBot.Config and CaveBot.Config.values or {}
  return values.autoExplorerPreview == true
end

local function shouldShowOverlay()
  return isPreviewEnabled()
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

local function getOverlayAnchor(pos)
  if state.enabled then
    return getAnchor(pos)
  end
  if hasPosition(pos) then
    return pos
  end
  return nil
end

local function inCurrentRadius(pos)
  if not hasPosition(pos) then return false end
  local anchor = getAnchor()
  return anchor and distance2d(pos, anchor) <= getRadius()
end

local function distanceFromAnchor(pos)
  local anchor = getAnchor()
  if not anchor then return 9999 end
  return distance2d(pos, anchor)
end

local function inStableReturnArea(pos)
  if not hasPosition(pos) then return false end
  return distanceFromAnchor(pos) <= math.max(1, getRadius() - RETURN_INSIDE_MARGIN)
end

local function isFloorChangeByMinimap(pos)
  if not hasPosition(pos) or not g_map or not g_map.getMinimapColor then return false end
  local color = g_map.getMinimapColor(pos)
  return color and color >= 210 and color <= 213
end

local function tileHasCreature(tile)
  if not tile then return false end
  local ok, result = pcall(function()
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
    pos = pos or tileOrPos
  end

  if state.floorAvoid[positionKey(pos)] then return true end
  if isFloorChangeByMinimap(pos) then return true end
  if tile then
    for _,name in ipairs({"isFloorChange","isFloorChangeUp","isFloorChangeDown"}) do
      local ok, result = pcall(function() return type(tile[name]) == "function" and tile[name](tile) end)
      if ok and result == true then return true end
    end
    local ok, color = pcall(function() return tile:getMinimapColorByte() end)
    color = ok and tonumber(color) or 0
    if color >= 210 and color <= 213 then return true end
    local elevated, high = pcall(function() return tile:hasElevation(3) end)
    if elevated and high == true then return true end
    local items = tile.getItems and tile:getItems() or {}
    local things = {}
    local ground = tile.getGround and tile:getGround()
    if ground then things[1] = ground end
    for _,item in ipairs(items) do things[#things+1] = item end
    for _,thing in ipairs(things) do
      local flagged, value = pcall(function() return type(thing.isFloorChange) == "function" and thing:isFloorChange() end)
      if flagged and value == true then return true end
    end
  end
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

local function countOpenCardinalTiles(pos)
  if not hasPosition(pos) or not g_map or not g_map.getTile then return 4 end

  local count = 0
  local offsets = {
    {x = 0, y = -1}, {x = 1, y = 0}, {x = 0, y = 1}, {x = -1, y = 0}
  }

  for _, offset in ipairs(offsets) do
    local tile = g_map.getTile({x = pos.x + offset.x, y = pos.y + offset.y, z = pos.z})
    if tile and isWalkableTile(tile) then
      count = count + 1
    end
  end

  return count
end

local function isCorridorArea(pos)
  return countOpenCardinalTiles(pos) <= CORRIDOR_OPEN_MAX
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
  if key and state.huntRoute then state.huntRoute.covered[key] = state.huntRoute.cycle end
  if key and not state.visited[key] then
    state.visited[key] = true
    state.visitedCount = state.visitedCount + 1
  end
end

local function sectorKey(pos)
  return pos.z .. ":" .. math.floor(pos.x / SECTOR_SIZE) .. ":" .. math.floor(pos.y / SECTOR_SIZE)
end

local function markWalked(pos)
  local key = positionKey(pos)
  if not key or key == state.lastWalkedKey then return end
  local route=state.huntRoute
  if route and state.origin and pos.z==state.origin.z and inCurrentRadius(pos) and not isFloorChangeTile(g_map.getTile(pos),pos) then
    if not route.nodes[key] then route.nodes[key]=copyPosition(pos);route.nodeCount=route.nodeCount+1 end
    local previous=route.nodes[state.lastWalkedKey]
    if previous and previous.z==pos.z and distance2d(previous,pos)==1 then
      route.edges[state.lastWalkedKey]=route.edges[state.lastWalkedKey] or {};route.edges[state.lastWalkedKey][key]=true
      route.edges[key]=route.edges[key] or {};route.edges[key][state.lastWalkedKey]=true
    end
  end
  state.lastWalkedKey = key
  state.walkedAt[key] = currentTime()
  state.walkCount[key] = (tonumber(state.walkCount[key]) or 0) + 1
  markVisited(pos)
  local sector = sectorKey(pos)
  local memory = state.sectors[sector] or {visits=0}
  memory.lastVisit = currentTime()
  if state.lastSector ~= sector then memory.visits = memory.visits + 1 end
  state.sectors[sector] = memory
  state.lastSector = sector
end

local function observeHunt()
  local time = currentTime()
  if time < state.nextEncounterAt then return end
  state.nextEncounterAt = time + 1000
  local creature = type(target) == "function" and target() or nil
  if not creature or not creature.isMonster or not creature:isMonster() then return end
  local pos = creature:getPosition()
  if not hasPosition(pos) or not inCurrentRadius(pos) then return end
  local key = sectorKey(pos)
  local memory = state.sectors[key] or {visits=0}
  memory.lastHunt = time
  state.sectors[key] = memory
end

local function markAreaCovered(centerPos)
  if not hasPosition(centerPos) or not g_map or not g_map.getTile then return end
  local coverageRadius = isCorridorArea(centerPos) and 0 or COVERAGE_RADIUS
  -- Coverage cannot pass through a wall into a parallel, unvisited passage.
  local queue,head,seen = {copyPosition(centerPos)},1,{[positionKey(centerPos)]=0}
  local offsets = {{0,-1},{1,0},{0,1},{-1,0}}
  while queue[head] do
    local pos=queue[head];head=head+1
    markVisited(pos)
    for _,offset in ipairs(offsets) do
      local nextPos={x=pos.x+offset[1],y=pos.y+offset[2],z=pos.z}
      local key=positionKey(nextPos)
      if seen[key]==nil and seen[positionKey(pos)]<coverageRadius then
        seen[key]=seen[positionKey(pos)]+1
        local tile=g_map.getTile(nextPos)
        if tile and inCurrentRadius(nextPos) and not isFloorChangeTile(tile,nextPos) and canCoverTile(tile) then
          queue[#queue+1]=nextPos
        end
      end
    end
  end
end

local function countVisited()
  return state.visitedCount
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
  if text:find("^Cazando") then return "Cazando" end
  if text:find("^On") then return count and ("On " .. count) or "On" end
  if text:find("^Off") then return "Off" end
  return text
end

local function setStatus(text, color)
  text, color = tostring(text or ""), color or "#ffffff"
  if state.status == text and state.statusColor == color and currentTime() < state.nextStatusAt then return end
  state.status, state.statusColor = text, color
  state.nextStatusAt = currentTime() + STATUS_INTERVAL
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
  local module = modules.game_minimap
  local widget
  if type(module.getMiniMapUi) == "function" then
    local ok, value = pcall(module.getMiniMapUi)
    if ok then widget = value end
  end
  widget = widget or module.minimapWidget
  local life = module._pruebasMapLife
  if widget and life and life.isDead and life.isDead(widget) then return nil end
  return widget
end

local function destroyMinimapOverlayWidgets(minimap, keepWidget)
  if not minimap then return end

  if minimap.getChildren then
    local okChildren, children = pcall(function() return minimap:getChildren() end)
    if okChildren and type(children) == "table" then
      for _, child in pairs(children) do
        local okId, id = pcall(function()
          return child.getId and child:getId() or nil
        end)
        if child ~= keepWidget and okId and id == "autoExplorerMinimapOverlay" then
          pcall(function() child:destroy() end)
        end
      end
    end
  end

  if keepWidget or not minimap.getChildById then return end
  for _ = 1, 5 do
    local ok, child = pcall(function() return minimap:getChildById("autoExplorerMinimapOverlay") end)
    if not ok or not child then break end
    pcall(function() child:destroy() end)
  end
end

local function destroyMinimapOverlay()
  local minimap = getMinimapWidget()
  destroyMinimapOverlayWidgets(minimap)
  local previous = minimapOverlay.parent
  local life = modules and modules.game_minimap and modules.game_minimap._pruebasMapLife
  if previous and previous ~= minimap and life and life.isDead and not life.isDead(previous) then
    destroyMinimapOverlayWidgets(previous)
  end
  minimapOverlay.widget = nil
  minimapOverlay.parent = nil
  minimapOverlay.visible = false
end

local function hideMinimapOverlay()
  if not minimapOverlay.widget and not minimapOverlay.parent then return end
  destroyMinimapOverlay()
end

local function createMinimapOverlay()
  local minimap = getMinimapWidget()
  if not minimap then return nil end

  if minimapOverlay.widget and minimapOverlay.parent == minimap then
    destroyMinimapOverlayWidgets(minimap, minimapOverlay.widget)
    return minimapOverlay.widget
  end

  destroyMinimapOverlay()

  minimapOverlay.parent = minimap
  local life = modules.game_minimap._pruebasMapLife
  if life and life.watch then
    life.watch(minimap,"autoExplorer",function()
      if minimapOverlay.parent == minimap then
        minimapOverlay.widget,minimapOverlay.parent,minimapOverlay.visible = nil,nil,false
      end
    end)
  end
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
  if not shouldShowOverlay() then
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
  local anchor = getOverlayAnchor(playerPos)
  if not anchor or anchor.z ~= centerMapPos.z then
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
  minimapOverlay.visible = true
end

local function refreshOverlayNow(force)
  if player and player.getPosition then
    local ok, pos = pcall(function() return player:getPosition() end)
    if ok and hasPosition(pos) then
      updateMinimapOverlay(pos, force == true)
      return
    end
  end
  if not state.enabled and not isPreviewEnabled() then
    hideMinimapOverlay()
  end
end

local function updateButtons()
  if not AutoExplorer.panel then return end
  local button = AutoExplorer.panel.enabled
  button:setOn(state.enabled == true)
  pcall(function()
    button:setImageColor(state.enabled and "#663333" or "#225533")
  end)
  if AutoExplorer.panel.optionsRow and AutoExplorer.panel.optionsRow.previewSwitch then
    AutoExplorer.panel.optionsRow.previewSwitch:setOn(isPreviewEnabled(), true)
  end
  if AutoExplorer.panel.optionsRow and AutoExplorer.panel.optionsRow.floorSwitch then
    AutoExplorer.panel.optionsRow.floorSwitch:setOn(sameFloorEnabled(),true)
  end
end

local function resetRuntime(keepEnabled, keepOrigin)
  local previousOrigin = keepOrigin and copyPosition(state.origin) or nil
  state.origin = nil
  state.anchors = {}
  state.visited = {}
  state.visitedCount = 0
  state.sectors = {}
  state.lastWalkedKey = nil
  state.lastSector = nil
  state.nextEncounterAt = 0
  state.holdUntil = 0
  state.nextStatusAt = 0
  clearPatrolWalk(false)
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
  state.lastStepDx = 0
  state.lastStepDy = 0
  state.startedAt = currentTime()
  state.nextThinkAt = 0
  state.nextScanAt = 0
  state.nextWalkAt = 0
  state.nextOverlayUpdateAt = 0
  state.lastFloorUseAt = 0
  state.floorReturnTarget = nil
  state.floorReturnStartedAt = 0
  state.floorLinks,state.floorAvoid = {},{}
  state.lastFloorAction,state.returnJob,state.nextPlan = nil,nil,nil
  state.huntRoute = {nodes={},edges={},covered={},cycle=1,nodeCount=0,nextScanAt=0,nextProbeAt=0,scanIndex=0,scanPasses=0,selections=0}
  resetDeathState()

  if player and player.getPosition then
    local pos = player:getPosition()
    if hasPosition(pos) then
      if hasPosition(previousOrigin) then
        state.origin = previousOrigin
        state.anchors[previousOrigin.z] = copyPosition(previousOrigin)
      else
        state.origin = copyPosition(pos)
        state.anchors[pos.z] = copyPosition(pos)
      end
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
  return {
    ignoreNonPathable = true,
    ignoreCreatures = false,
    ignoreFields = true,
    precision = 0,
    ignoreStairs = false, -- Native false avoids stairs; live checks are independent.
    allowFloorChange = allowFloorChanges(),
    allowUnseen = true,
    allowOnlyVisibleTiles = false
  }
end

local function getFloorReturnPathParams()
  local params = getPathParams()
  params.ignoreStairs = false
  params.allowFloorChange = false
  params.returning = true
  params.allowUnseen = true
  params.allowOnlyVisibleTiles = false
  return params
end

local function getPathTo(pos, maxDistance, params, from)
  if not getPath or not player or not player.getPosition then return nil end
  params = params or getPathParams()
  local native = {}
  for name,value in pairs(params) do
    if name ~= "allowFloorChange" and name ~= "allowedFloor" and name ~= "returning" then native[name] = value end
  end
  from = from or player:getPosition()
  local ok, path = pcall(function()
    return getPath(from, pos, maxDistance, native)
  end)
  if ok and path and path[1] then
    local current = copyPosition(from)
    local offsets = {{0,-1},{1,0},{0,1},{-1,0},{1,-1},{1,1},{-1,1},{-1,-1}}
    for _,direction in ipairs(path) do
      local offset = offsets[direction+1]
      if not offset then return nil end
      current = {x=current.x+offset[1],y=current.y+offset[2],z=current.z}
      local tile = g_map.getTile(current)
      if not params.returning and state.floorAvoid[positionKey(current)] then return nil end
      if not params.allowFloorChange and isFloorChangeTile(tile,current) and not samePosition(current,params.allowedFloor) then return nil end
    end
    return path
  end
  return nil
end

local function directionOffset(dir)
  if dir == North or dir == 0 then return 0, -1 end
  if dir == East or dir == 1 then return 1, 0 end
  if dir == South or dir == 2 then return 0, 1 end
  if dir == West or dir == 3 then return -1, 0 end
  if dir == NorthEast or dir == 4 then return 1, -1 end
  if dir == SouthEast or dir == 5 then return 1, 1 end
  if dir == SouthWest or dir == 6 then return -1, 1 end
  if dir == NorthWest or dir == 7 then return -1, -1 end
  return 0, 0
end

local function pathLeavesPerimeter(path, startPos, allowOutsideStart)
  if not path or not startPos then return false end

  local pos = copyPosition(startPos)
  local hasBeenInside = inCurrentRadius(pos)
  for _, dir in ipairs(path) do
    local dx, dy = directionOffset(dir)
    pos = {x = pos.x + dx, y = pos.y + dy, z = pos.z}

    if inCurrentRadius(pos) then
      hasBeenInside = true
    elseif hasBeenInside or not allowOutsideStart then
      return true
    end
  end

  return false
end

local function manualPointerWalking()
  if player and type(player.isAutoWalking) == "function" then
    local ok, active = pcall(player.isAutoWalking, player)
    if ok and active == true then return true end
  end
  if BugMapMouse and type(BugMapMouse.isManualMovement) == "function" then
    local ok, active = pcall(BugMapMouse.isManualMovement)
    if ok and active == true then return true end
  end
  return false
end

-- Cancel only an outstanding native chunk owned by this engine. A new manual
-- click-to-walk supersedes it and must never be stopped by a stale bot token.
clearPatrolWalk = function(keepPace,keepChain)
  local pending = patrolWalk.pending
  local chain = keepChain and patrolWalk.chain or nil
  patrolWalk.path, patrolWalk.from, patrolWalk.dest, patrolWalk.pending = nil, nil, nil, nil
  patrolWalk.index = 1
  state.nextPlan = nil
  patrolWalk.chain = not pending and chain or nil
  if pending and pending.native and pending.active and not manualPointerWalking() and
      g_game and type(g_game.stop) == "function" then pcall(g_game.stop) end
  if pending then patrolWalk.chain=nil end
  if not keepPace then patrolWalk.nextAt=0;patrolWalk.nativeRetryAt=0;patrolWalk.lastMode="steps";patrolWalk.chain=nil end
end

local function observePatrolPosition(pos)
  local pending = patrolWalk.pending
  if not pending then return end
  if pending.native then
    for index = pending.confirmed + 1, #pending.positions do
      if samePosition(pos, pending.positions[index]) then
        pending.confirmed = index
        patrolWalk.from = copyPosition(pos)
        patrolWalk.index = pending.startIndex + index
        state.targetNoProgressAt = currentTime()
        if index == #pending.positions then
          patrolWalk.pending = nil
          patrolWalk.nextAt = currentTime()
          patrolWalk.chain = {position=copyPosition(pos),untilAt=currentTime()+500}
        end
        return
      end
    end
    if not samePosition(pos, patrolWalk.from) then clearPatrolWalk(true) end
    return
  end
  if samePosition(pos, pending.to) then
    patrolWalk.from = copyPosition(pos)
    patrolWalk.index = patrolWalk.index + 1
    patrolWalk.pending = nil
    state.targetNoProgressAt = currentTime()
  elseif not samePosition(pos, pending.from) then
    clearPatrolWalk(true) -- A push, manual move or another movement owner changed the path.
  end
end

AutoExplorer.canMoveTo = function(to, from)
  if not state.enabled then return true end
  if not hasPosition(to) or not hasPosition(state.origin) then return false end
  if to.z ~= state.origin.z then return false end
  if sameFloorEnabled() and isFloorChangeTile(g_map.getTile(to),to) then return false end
  local after = distance2d(to, state.origin)
  if after <= getRadius() then return true end
  return hasPosition(from) and distance2d(from, state.origin) > getRadius() and after < distance2d(from, state.origin)
end

AutoExplorer.holdMovement = function(milliseconds)
  if not state.enabled then return end
  state.holdUntil = math.max(state.holdUntil, currentTime() + math.max(0, tonumber(milliseconds) or 0))
  clearPatrolWalk(true)
  if state.huntRoute then state.huntRoute.job,state.huntRoute.ready=nil,nil end
end

AutoExplorer.yieldNativeMovement = function(milliseconds)
  if not patrolWalk.pending or not patrolWalk.pending.native then return false end
  AutoExplorer.holdMovement(milliseconds)
  return true
end

local function stepDuration(direction)
  local duration = 150
  if player and type(player.getStepDuration) == "function" then
    local ok, value = pcall(player.getStepDuration, player, false, direction)
    if ok and tonumber(value) and value > 0 then duration = value end
  end
  local extra = CaveBot.Config and CaveBot.Config.get and tonumber(CaveBot.Config.get("walkDelay")) or 0
  return math.max(THINK_INTERVAL, duration + math.max(0, extra or 0))
end

local function nativeWalker()
  return type(autoWalk) == "function" and autoWalk or g_game and type(g_game.autoWalk) == "function" and g_game.autoWalk
end

local function checkedStep(origin, direction, params, allowOutside, nativeCheck)
  local dx, dy = directionOffset(direction)
  if dx == 0 and dy == 0 or pathLeavesPerimeter({direction}, origin, allowOutside) then return nil end
  local to = {x=origin.x+dx,y=origin.y+dy,z=origin.z}
  local tile = g_map.getTile(to)
  if not tile or not isWalkableTile(tile) or tileHasCreature(tile) or
      (not params.allowFloorChange and isFloorChangeTile(tile,to) and not samePosition(to,params.allowedFloor)) or
      (not params.returning and state.floorAvoid[positionKey(to)]) then return nil end
  if dx ~= 0 and dy ~= 0 then
    for _,side in ipairs({{x=to.x,y=origin.y,z=origin.z},{x=origin.x,y=to.y,z=origin.z}}) do
      local sideTile = g_map.getTile(side)
      if not sideTile or not isWalkableTile(sideTile) or tileHasCreature(sideTile) then return nil end
    end
  end
  local safety = TargetBot and TargetBot.Antitrap
  if nativeCheck and not params.returning and safety and safety.canRouteStep and not safety.canRouteStep(origin,direction) then return nil end
  return to, isFloorChangeTile(tile, to)
end

patrolWalkTo = function(dest, maxDistance, params, allowOutside)
  local time, origin = currentTime(), player:getPosition()
  observePatrolPosition(origin)
  if patrolWalk.pending then
    local pending = patrolWalk.pending
    if pending.native then
      local safety = TargetBot and TargetBot.Antitrap
      if not params.returning and safety and safety.canRouteStep and safety.refresh then safety.refresh(origin,time) end
      if not params.returning and safety and (safety.ownsMovement and safety.ownsMovement() or
          not safety.canRouteStep and safety.protecting and safety.protecting()) then clearPatrolWalk(true);return true end
      local from = origin
      for index = pending.confirmed + 1, #pending.positions do
        local to = checkedStep(from, pending.directions[index], params, allowOutside, true)
        if not to or not samePosition(to, pending.positions[index]) then clearPatrolWalk(true);return false end
        from = to
      end
    end
    if time < patrolWalk.pending.deadline then return true end
    local nativeBackoff = pending.native and (pending.confirmed == 0 and 5000 or 1000) or nil
    clearPatrolWalk(true)
    if nativeBackoff then patrolWalk.nativeRetryAt = time + nativeBackoff end
    patrolWalk.nextAt = time + 100
    return true
  end
  if time < patrolWalk.nextAt then return true end
  if samePosition(origin, dest) then return true end
  local chaining = patrolWalk.chain and time <= patrolWalk.chain.untilAt and
    samePosition(origin,patrolWalk.chain.position) and nativeWalker() and g_game and type(g_game.stop) == "function"
  if not chaining and type(player.isWalking) == "function" and player:isWalking() then return true end
  if not samePosition(patrolWalk.dest, dest) or not samePosition(patrolWalk.from, origin) or
      not patrolWalk.path or not patrolWalk.path[patrolWalk.index] then
    clearPatrolWalk(true)
    local path = getPathTo(dest, maxDistance, params)
    if not path or pathLeavesPerimeter(path, origin, allowOutside) then return false end
    patrolWalk.path, patrolWalk.from, patrolWalk.dest = path, copyPosition(origin), copyPosition(dest)
  end
  local direction = patrolWalk.path[patrolWalk.index]
  local to = checkedStep(origin, direction, params, allowOutside)
  if not to then clearPatrolWalk(true);return false end
  if type(player.canWalk) == "function" then
    local ok, ready = pcall(player.canWalk, player, direction)
    if ok and ready == false and not chaining then return true end
  end
  if not params.returning and CaveBot.protectStep and not CaveBot.protectStep(direction) then clearPatrolWalk(true);return true end
  local safety = TargetBot and TargetBot.Antitrap
  local protected = safety and safety.protecting and safety.protecting()
  local nativeWalk = nativeWalker()
  if nativeWalk and g_game and type(g_game.stop) == "function" and
      (not protected or safety.canRouteStep) and time >= patrolWalk.nativeRetryAt then
    local directions, positions, from, duration = {}, {}, origin, 0
    for index = patrolWalk.index, math.min(#patrolWalk.path,patrolWalk.index+WALK_CHUNK_SIZE-1) do
      local step, floorChange = checkedStep(from, patrolWalk.path[index], params, allowOutside, true)
      if not step then break end
      directions[#directions+1], positions[#positions+1] = patrolWalk.path[index], step
      duration = duration + stepDuration(patrolWalk.path[index])
      from = step
      if floorChange then break end -- Never queue steps beyond a floor transition.
    end
    if #directions > 0 then
      local ping = CaveBot.Config and CaveBot.Config.get and tonumber(CaveBot.Config.get("ping")) or 0
      local pending = {native=true,active=false,confirmed=0,directions=directions,positions=positions,
        startIndex=patrolWalk.index,deadline=time+math.max(1000,duration*2+(ping or 0)*3)}
      patrolWalk.pending = pending
      local ok, sent = pcall(nativeWalk, directions)
      if ok and sent ~= false or pending.confirmed > 0 then
        pending.active = true
        patrolWalk.lastMode = "native"
        patrolWalk.chain = nil
        return true
      end
      patrolWalk.pending = nil
      if chaining and player:isWalking() then
        patrolWalk.nativeRetryAt = time + THINK_INTERVAL
        return true
      end
      patrolWalk.nativeRetryAt = time + 1000
    end
  end
  if type(player.isWalking) == "function" and player:isWalking() then return true end
  patrolWalk.lastMode = "steps"
  local duration = stepDuration(direction)
  local ping = CaveBot.Config and CaveBot.Config.get and tonumber(CaveBot.Config.get("ping")) or 0
  patrolWalk.pending = {from=copyPosition(origin),to=to,deadline=time+math.max(800,duration*4+(ping or 0)*3)}
  patrolWalk.nextAt = time + duration
  local ok, sent = pcall(safeBotWalk, direction)
  if not ok or sent == false then clearPatrolWalk(true);patrolWalk.nextAt=time+100;return false end
  return true
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
  if floorTile then return false end -- Hunting never selects a floor change as its destination.
  if not isWalkableTile(tile) then
    local floorThing = getFloorChangeThing(tile)
    if not (floorTile and floorThing and allowFloorChanges()) then return false end
  end

  return true
end

local function getVisibleBounds(tiles, z)
  local bounds = nil
  for _, tile in pairs(tiles or {}) do
    local pos = getTilePosition(tile)
    if pos and pos.z == z then
      if not bounds then
        bounds = {minX = pos.x, maxX = pos.x, minY = pos.y, maxY = pos.y}
      else
        if pos.x < bounds.minX then bounds.minX = pos.x end
        if pos.x > bounds.maxX then bounds.maxX = pos.x end
        if pos.y < bounds.minY then bounds.minY = pos.y end
        if pos.y > bounds.maxY then bounds.maxY = pos.y end
      end
    end
  end
  return bounds
end

local function getEdgeDistance(pos, bounds)
  if not hasPosition(pos) or not bounds then return 99 end
  return math.min(
    math.abs(pos.x - bounds.minX),
    math.abs(bounds.maxX - pos.x),
    math.abs(pos.y - bounds.minY),
    math.abs(bounds.maxY - pos.y)
  )
end

local function edgeScore(edgeDistance, distance)
  edgeDistance = tonumber(edgeDistance) or 99
  distance = tonumber(distance) or 0
  local score = math.max(0, EDGE_SCAN_DISTANCE + 1 - edgeDistance) * 35
  if distance >= 5 then score = score + math.min(distance, 12) * 4 end
  return score
end

local function getNearbyBounds(centerPos, radius)
  if not hasPosition(centerPos) then return nil end
  radius = tonumber(radius) or MAX_SCAN_RADIUS
  return {
    minX = centerPos.x - radius,
    maxX = centerPos.x + radius,
    minY = centerPos.y - radius,
    maxY = centerPos.y + radius
  }
end

local function forEachNearbyTile(centerPos, radius, callback)
  if not hasPosition(centerPos) or not g_map or not g_map.getTile then return end
  radius = math.max(1, tonumber(radius) or MAX_SCAN_RADIUS)

  for x = centerPos.x - radius, centerPos.x + radius do
    for y = centerPos.y - radius, centerPos.y + radius do
      local tile = g_map.getTile({x = x, y = y, z = centerPos.z})
      if tile then
        callback(tile)
      end
    end
  end
end

local function bucketKey(x, y)
  return tostring(math.floor(x / FRONTIER_RADIUS)) .. ":" .. tostring(math.floor(y / FRONTIER_RADIUS))
end

local function buildCandidateBuckets(candidates)
  local buckets = {}
  for _, candidate in ipairs(candidates) do
    local pos = candidate.pos
    if hasPosition(pos) then
      local key = bucketKey(pos.x, pos.y)
      buckets[key] = (buckets[key] or 0) + 1
    end
  end
  return buckets
end

local function countNearbyCandidates(candidate, buckets)
  local pos = candidate and candidate.pos
  if not hasPosition(pos) or type(buckets) ~= "table" then return 0 end

  local bucketX = math.floor(pos.x / FRONTIER_RADIUS)
  local bucketY = math.floor(pos.y / FRONTIER_RADIUS)
  local count = 0
  for x = bucketX - 1, bucketX + 1 do
    for y = bucketY - 1, bucketY + 1 do
      count = count + (buckets[tostring(x) .. ":" .. tostring(y)] or 0)
    end
  end
  return count
end

local function patrolDistanceScore(distance)
  distance = tonumber(distance) or 0
  if distance < PATROL_MIN_DISTANCE then
    return -130 * (PATROL_MIN_DISTANCE - distance)
  end
  if distance <= PATROL_PREFERRED_DISTANCE then
    return distance * 18
  end
  return PATROL_PREFERRED_DISTANCE * 18 - ((distance - PATROL_PREFERRED_DISTANCE) * 6)
end

local function patrolCenterScore(anchorDistance)
  local radius = getRadius()
  local preferred = math.max(6, math.floor(radius * 0.72))
  return -math.abs((tonumber(anchorDistance) or 0) - preferred) * 5
end

local function corridorScore(candidate, mode)
  if not candidate or not candidate.corridor then return 0 end

  local score = CORRIDOR_BASE_BONUS + math.min(12, tonumber(candidate.distance) or 0) * 8
  if (candidate.directionScore or 0) > 0 then
    score = score + CORRIDOR_DIRECTION_BONUS
  elseif (candidate.directionScore or 0) < 0 then
    score = score - math.floor(CORRIDOR_DIRECTION_BONUS / 2)
  end

  if candidate.openCardinals <= 1 then
    score = score - 55
  end

  if mode == "patrol" then
    score = score + 70
  end

  return score
end

local function candidateScore(candidate, mode)
  local score = 0
  mode = mode or "explore"

  if mode == "patrol" then
    local age = candidate.lastWalkedAt > 0 and math.min(90000, currentTime() - candidate.lastWalkedAt) or 90000
    local memory = state.sectors[sectorKey(candidate.pos)]
    local sectorAge = memory and memory.lastVisit and math.min(90000, currentTime() - memory.lastVisit) or 90000
    score = score + math.floor(age / 1000) * 3 + math.floor(sectorAge / 1000) * 9
    score = score - math.min(candidate.walkCount, 6) * math.max(0, 60 - age / 1000)
    if memory and memory.lastHunt and currentTime() - memory.lastHunt > 30000 and sectorAge > 15000 then
      score = score + 140 -- Observed hunting history, not an assumed server respawn timer.
    end
    score = score + corridorScore(candidate, mode)
    score = score + patrolDistanceScore(candidate.distance)
    score = score + (candidate.directionScore or 0) * 45
  else
    score = score + candidate.frontier * 18
    score = score + (candidate.edgeScore or 0)
    score = score + corridorScore(candidate, mode)
    score = score + math.min(candidate.distance, 14) * 5
    score = score + candidate.anchorDistance * 4
    score = score - candidate.walkCount * 25
  end

  if candidate.floorTile and allowFloorChanges() then
    score = score + 10
  end
  if isRecentTarget(candidate.key) then
    score = score - (mode == "patrol" and 450 or 120)
  end
  if candidate.lastWalkedAt > 0 and currentTime() - candidate.lastWalkedAt < PATROL_RECENT_TIME then
    score = score - (mode == "patrol" and 360 or 30)
  end

  return score
end

local function rememberHuntTile(tile,pos)
  local route=state.huntRoute
  if not route or not hasPosition(pos) or not state.origin or pos.z~=state.origin.z or not inCurrentRadius(pos) then return end
  local key=positionKey(pos)
  if tile and isWalkableTile(tile) and not isFloorChangeTile(tile,pos) then
    if not route.nodes[key] then route.nodes[key]=copyPosition(pos);route.nodeCount=route.nodeCount+1 end
  elseif tile and not tileHasCreature(tile) and route.nodes[key] then
    route.nodes[key]=nil;route.nodeCount=route.nodeCount-1
  end
end

local function buildCandidates(mode, from)
  mode = mode or "explore"
  local playerPos = from or player and player.getPosition and player:getPosition() or nil
  if not hasPosition(playerPos) then return {} end
  local anchor = getAnchor(playerPos)

  local candidates = {}
  local scanRadius = math.min(getRadius(), MAX_SCAN_RADIUS)
  local bounds = getNearbyBounds(anchor or playerPos, scanRadius)

  forEachNearbyTile(playerPos, scanRadius, function(tile)
    rememberHuntTile(tile,getTilePosition(tile))
    if canUseTile(tile) then
      local tilePos = getTilePosition(tile)
      if tilePos and not samePosition(tilePos, playerPos) then
        local key = positionKey(tilePos)
        if key and (mode == "patrol" or not state.visited[key]) then
          local floorThing = getFloorChangeThing(tile)
          local distance = distance2d(playerPos, tilePos)
          local edgeDistanceValue = getEdgeDistance(tilePos, bounds)
          local openCardinals = countOpenCardinalTiles(tilePos)
          local candidate = {
            pos = copyPosition(tilePos),
            key = key,
            distance = distance,
            anchorDistance = distance2d(getAnchor(playerPos), tilePos),
            edgeDistance = edgeDistanceValue,
            edgeScore = edgeScore(edgeDistanceValue, distance),
            openCardinals = openCardinals,
            corridor = openCardinals <= CORRIDOR_OPEN_MAX,
            floorTile = isFloorChangeTile(tile, tilePos),
            floorUse = floorThing ~= nil,
            lastWalkedAt = tonumber(state.walkedAt[key]) or 0,
            walkCount = tonumber(state.walkCount[key]) or 0,
            directionScore = (sign(tilePos.x - playerPos.x) * (state.lastStepDx or 0)) +
              (sign(tilePos.y - playerPos.y) * (state.lastStepDy or 0)),
            frontier = 0,
            score = 0
          }
          table.insert(candidates, candidate)
        end
      end
    end
  end)

  local buckets = buildCandidateBuckets(candidates)
  for _, candidate in ipairs(candidates) do
    candidate.frontier = countNearbyCandidates(candidate, buckets)
    candidate.score = candidateScore(candidate, mode)
  end

  table.sort(candidates, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    if a.edgeScore ~= b.edgeScore then return a.edgeScore > b.edgeScore end
    if a.frontier ~= b.frontier then return a.frontier > b.frontier end
    if mode == "patrol" and a.distance ~= b.distance then
      return math.abs(a.distance - PATROL_PREFERRED_DISTANCE) < math.abs(b.distance - PATROL_PREFERRED_DISTANCE)
    end
    if a.anchorDistance ~= b.anchorDistance then
      if mode == "patrol" then return a.anchorDistance > b.anchorDistance end
      return a.anchorDistance > b.anchorDistance
    end
    return a.distance < b.distance
  end)

  return candidates
end

local function chooseTargetFromCandidates(candidates, mode, from)
  local radius = getRadius()
  local maxDistance = math.max(8, radius * 2 + 10)
  local checked = 0
  local best = nil
  local playerPos = from or player and player.getPosition and player:getPosition() or nil

  local ordered = candidates
  if mode=="patrol" and #candidates>PATROL_PATH_CHECKS then
    ordered={}
    for index=1,PATROL_PATH_CHECKS-1 do ordered[#ordered+1]=candidates[index] end
    local nearest
    for index=PATROL_PATH_CHECKS,#candidates do
      if not nearest or candidates[index].distance<nearest.distance then nearest=candidates[index] end
    end
    ordered[#ordered+1]=nearest
  end
  for _, candidate in ipairs(ordered) do
    if checked >= (mode == "patrol" and PATROL_PATH_CHECKS or MAX_PATH_CHECKS) then break end
    checked = checked + 1

    local path = getPathTo(candidate.pos, maxDistance, nil, playerPos)
    local walkPos = candidate.pos
    if not path and candidate.floorUse and allowFloorChanges() then
      walkPos, path = getFloorStandPosition(candidate.pos, maxDistance)
    end
    if path then
      if playerPos and pathLeavesPerimeter(path, playerPos, false) then
        markBlocked(candidate.pos)
      else
        local pathScore = candidate.score - (#path * 2)
        if not best or pathScore > best.score then
          best = {pos = candidate.pos, key = candidate.key, path = path, walkPos = walkPos, score = pathScore}
        end
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

-- A coverage round does not expire with time. Known pending passages win over
-- revisits; shortest graph paths can still cross a covered junction to reach one.
local huntOffsets={{0,-1},{1,0},{0,1},{-1,0},{1,-1},{1,1},{-1,1},{-1,-1}}
local function routeContext()
  local route=state.huntRoute
  if not route or not state.origin then return nil end
  local context=positionKey(state.origin)..":"..getRadius()..":"..tostring(sameFloorEnabled())
  if route.context~=context then
    route.context=context;route.job=nil;route.ready=nil;route.probes=nil;route.probeIndex=1;route.scanIndex=0;route.scanPasses=0
    route.nextScanAt=0;route.nextProbeAt=0
    for key,pos in pairs(route.nodes) do
      if not inCurrentRadius(pos) or pos.z~=state.origin.z then route.nodes[key]=nil;route.nodeCount=route.nodeCount-1 end
    end
  end
  return route
end

local function startRouteSearch(route,from)
  local key=positionKey(from)
  if not route.nodes[key] then return end
  route.job={from=copyPosition(from),queue={{key=key,pos=copyPosition(from),distance=0,fresh=0}},head=1,
    seen={[key]=true},cycle=route.cycle,context=route.context,best=nil,projected={}}
  local pending=patrolWalk.pending
  if pending and pending.native and samePosition(from,pending.positions[#pending.positions]) then
    -- Planning from the end of our own packet must not send us back along the
    -- steps that will have been covered before we reach that point.
    for index=pending.confirmed+1,#pending.positions do
      local pos=pending.positions[index];local radius=isCorridorArea(pos) and 0 or COVERAGE_RADIUS
      local queue,head,seen={pos},1,{[positionKey(pos)]=0}
      while queue[head] do
        local here=queue[head];head=head+1;local hereKey=positionKey(here)
        route.job.projected[hereKey]=true
        if seen[hereKey]<radius then
          for direction=1,4 do
            local offset=huntOffsets[direction];local nextPos={x=here.x+offset[1],y=here.y+offset[2],z=here.z}
            local nextKey=positionKey(nextPos)
            if seen[nextKey]==nil and route.nodes[nextKey] then
              seen[nextKey]=seen[hereKey]+1;queue[#queue+1]=nextPos
            end
          end
        end
      end
    end
  end
  route.ready=nil
end

local function advanceRouteSearch(route,budget)
  local job=route.job
  if not job then return end
  for _=1,budget do
    local node=job.queue[job.head]
    if not node or job.firstPending and node.distance>job.firstPending+PATROL_PREFERRED_DISTANCE then
      route.ready={from=job.from,target=job.best and job.best.pos,context=job.context,cycle=job.cycle,
        exhausted=not node,at=currentTime()};route.job=nil;return
    end
    job.head=job.head+1
    if route.nodes[node.key] and not state.floorAvoid[node.key] then
      local pending=route.covered[node.key]~=job.cycle and not job.projected[node.key]
      if pending and node.distance>0 and not isBlocked(node.key) then
        job.firstPending=job.firstPending or node.distance
        local score=node.fresh*40-(node.distance-node.fresh)*14+math.min(node.distance,PATROL_PREFERRED_DISTANCE)*3-
          math.max(0,node.distance-PATROL_PREFERRED_DISTANCE)*12
        if not job.best or score>job.best.score then job.best={pos=node.pos,score=score} end
      end
      for direction,offset in ipairs(huntOffsets) do
        local pos={x=node.pos.x+offset[1],y=node.pos.y+offset[2],z=node.pos.z}
        local key=positionKey(pos)
        local diagonal=direction>4
        local connected=not diagonal or route.nodes[positionKey({x=pos.x,y=node.pos.y,z=pos.z})] and
          route.nodes[positionKey({x=node.pos.x,y=pos.y,z=pos.z})] or route.edges[node.key] and route.edges[node.key][key]
        if connected and not job.seen[key] and route.nodes[key] and not state.floorAvoid[key] then
          job.seen[key]=true
          job.queue[#job.queue+1]={key=key,pos=route.nodes[key],distance=node.distance+1,
            fresh=node.fresh+(route.covered[key]~=job.cycle and not job.projected[key] and 1 or 0)}
        end
      end
    end
  end
end

local function probeHuntMap(route,from)
  if not route.probes then
    route.probes={}
    local radius=getRadius();local span=math.floor(radius/SECTOR_SIZE)
    for x=-span,span do for y=-span,span do
      local pos={x=state.origin.x+x*SECTOR_SIZE,y=state.origin.y+y*SECTOR_SIZE,z=state.origin.z}
      route.probes[#route.probes+1]={pos=pos,attempt=0,distance=distance2d(pos,state.origin)}
    end end
    table.sort(route.probes,function(a,b)
      if a.distance~=b.distance then return a.distance>b.distance end
      if a.pos.x~=b.pos.x then return a.pos.x<b.pos.x end
      return a.pos.y<b.pos.y
    end)
  end
  local offsets={{0,0},{-2,0},{2,0},{0,-2},{0,2},{-2,-2},{2,2},{-2,2},{2,-2}}
  -- Only one native path query per probe, at most twice a second. A minimap
  -- color alone never establishes walkability; only a confirmed path adds nodes.
  for _=1,12 do
    local seed=route.probes[route.probeIndex]
    if not seed then return end
    local target
    while seed.attempt<#offsets and not target do
      seed.attempt=seed.attempt+1
      local offset=offsets[seed.attempt]
      local pos={x=seed.pos.x+offset[1],y=seed.pos.y+offset[2],z=seed.pos.z}
      local color=g_map.getMinimapColor and tonumber(g_map.getMinimapColor(pos)) or 0
      if inCurrentRadius(pos) and not route.nodes[positionKey(pos)] and color and color~=0 and not isFloorChangeTile(nil,pos) then target=pos end
    end
    if target then
      local params=getPathParams();params.allowFloorChange=false;params.allowUnseen=false
      local path=getPathTo(target,math.max(64,getRadius()*4+10),params,from)
      if path and not pathLeavesPerimeter(path,from,false) then
        local pos=copyPosition(from)
        for _,direction in ipairs(path) do
          local previousKey=positionKey(pos)
          local dx,dy=directionOffset(direction);pos={x=pos.x+dx,y=pos.y+dy,z=pos.z}
          local key=positionKey(pos)
          if not route.nodes[key] then route.nodes[key]=copyPosition(pos);route.nodeCount=route.nodeCount+1 end
          route.edges[previousKey]=route.edges[previousKey] or {};route.edges[previousKey][key]=true
          route.edges[key]=route.edges[key] or {};route.edges[key][previousKey]=true
        end
        route.probeIndex=route.probeIndex+1
      end
      if not path and seed.attempt>=#offsets then route.probeIndex=route.probeIndex+1 end
      return
    end
    route.probeIndex=route.probeIndex+1
  end
end

local function updateHuntRoute(playerPos)
  local route=routeContext()
  if not route or playerPos.z~=state.origin.z then return end
  if currentTime()>=route.nextScanAt then
    route.nextScanAt=currentTime()+100
    local radius=getRadius();local side=radius*2+1;local total=side*side
    for _=1,96 do
      local index=route.scanIndex
      local pos={x=state.origin.x-radius+math.floor(index/side),y=state.origin.y-radius+index%side,z=state.origin.z}
      rememberHuntTile(g_map.getTile(pos),pos)
      route.scanIndex=(index+1)%total
      if route.scanIndex==0 then route.scanPasses=route.scanPasses+1 end
    end
  end
  if currentTime()>=route.nextProbeAt then
    route.nextProbeAt=currentTime()+500;probeHuntMap(route,playerPos)
  end
  advanceRouteSearch(route,192)
end

local function chooseRouteTarget(from)
  local route=routeContext()
  if not route then return nil end
  local ready=route.ready
  if ready and (not samePosition(ready.from,from) or ready.context~=route.context or ready.cycle~=route.cycle) then
    route.ready=nil;ready=nil
  end
  if not ready then
    if not route.job or not samePosition(route.job.from,from) then startRouteSearch(route,from) end
    advanceRouteSearch(route,768);ready=route.ready
  end
  if not ready then return nil end
  if ready.target and route.covered[positionKey(ready.target)]~=route.cycle then
    local path=getPathTo(ready.target,math.max(64,getRadius()*4+10),nil,from)
    route.ready=nil
    if path and not pathLeavesPerimeter(path,from,false) then
      route.selections=route.selections+1
      return copyPosition(ready.target),positionKey(ready.target),path,"route",copyPosition(ready.target)
    end
    markBlocked(ready.target)
  elseif ready.exhausted and not ready.target and route.scanPasses>0 and samePosition(from,player:getPosition()) then
    route.cycle=route.cycle+1;route.ready=nil
    -- Start a new hunting round only after the reachable graph has no debt.
    markAreaCovered(player:getPosition())
    startRouteSearch(route,from);advanceRouteSearch(route,768)
  else route.ready=nil end
  return nil
end

local function chooseTarget(from)
  from=from or player:getPosition()
  local route=routeContext()
  local candidates
  if route and route.nodeCount<2 then candidates=buildCandidates("patrol",from) end
  local target,key,path,mode,walkPos=chooseRouteTarget(from)
  if target then return target,key,path,mode,walkPos end
  target,key,path,mode,walkPos = chooseTargetFromCandidates(candidates or buildCandidates("patrol",from), "patrol",from)
  if target then return target, key, path, mode, walkPos end

  return nil, nil, nil, "idle", nil
end

local function setTarget(pos, key, mode, walkPos, path)
  clearPatrolWalk(true,true)
  state.target = pos
  state.targetWalkPos = walkPos and copyPosition(walkPos) or nil
  state.targetKey = key
  state.targetMode = mode or "explore"
  state.targetStartedAt = currentTime()
  state.targetBestDistance = player and player.getPosition and distance2d(player:getPosition(), pos) or nil
  state.targetNoProgressAt = currentTime()
  if path and path[1] then
    patrolWalk.path = path
    patrolWalk.from = copyPosition(player:getPosition())
    patrolWalk.dest = copyPosition(walkPos or pos)
  end
end

local function clearTarget(remember)
  clearPatrolWalk(true,remember==true)
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
  if remember then state.nextScanAt = currentTime() end
end

local function shouldReturnToOriginFloor(playerPos)
  return hasPosition(playerPos) and hasPosition(state.origin) and playerPos.z ~= state.origin.z
end

local function prepareNextLeg()
  local pending = patrolWalk.pending
  if not pending or not pending.native or not state.target or
      pending.startIndex+#pending.positions <= #patrolWalk.path or #pending.positions-pending.confirmed > 6 then return end
  local route=state.huntRoute
  local completedSearch=route and route.ready and route.ready.target and
    samePosition(route.ready.from,pending.positions[#pending.positions])
  if pending.prefetchTried and not completedSearch then return end
  pending.prefetchTried = true
  local endpoint = pending.positions[#pending.positions]
  if endpoint.z ~= state.origin.z or isFloorChangeTile(g_map.getTile(endpoint),endpoint) then return end
  local target,key,path,mode,walkPos
  if completedSearch then target,key,path,mode,walkPos=chooseRouteTarget(endpoint)
  else target,key,path,mode,walkPos=chooseTarget(endpoint) end
  if target then state.nextPlan = {from=copyPosition(endpoint),target=target,key=key,path=path,mode=mode,walkPos=walkPos,
    at=currentTime(),radius=getRadius(),sameFloor=sameFloorEnabled()} end
end

local function recordFloorChange(newPos,oldPos)
  local links = state.floorLinks
  local link = links[#links]
  if link and newPos.z == link.source.z then
    if state.returnJob then state.floorAvoid[positionKey(state.returnJob.target)] = true end
    table.remove(links)
  elseif newPos.z ~= state.origin.z then
    local pending = patrolWalk.pending
    local entry = pending and (pending.native and pending.positions[pending.confirmed+1] or pending.to)
    local action = state.lastFloorAction
    if action and action.target.z == oldPos.z and currentTime()-action.at < 1800 then entry = action.target end
    if not hasPosition(entry) and patrolWalk.chain and samePosition(patrolWalk.chain.position,oldPos) then entry=oldPos end
    local knownEntry = hasPosition(entry) and entry.z==oldPos.z
    if not knownEntry then
      local best
      for x=oldPos.x-1,oldPos.x+1 do for y=oldPos.y-1,oldPos.y+1 do
        local pos={x=x,y=y,z=oldPos.z}
        if isFloorChangeTile(g_map.getTile(pos),pos) and (not best or distance2d(pos,newPos)<distance2d(best,newPos)) then best=pos end
      end end
      entry=best or oldPos;knownEntry=best~=nil
    end
    if state.returnJob then state.returnJob.link.failed[positionKey(state.returnJob.target)]=currentTime()+30000 end
    links[#links+1] = {source=copyPosition(oldPos),entry=copyPosition(entry),landing=copyPosition(newPos),failed={}}
    if #links>16 then table.remove(links,1) end
    if knownEntry then state.floorAvoid[positionKey(entry)] = true end
  end
  if newPos.z == state.origin.z then state.floorLinks = {} end
  state.lastFloorAction,state.returnJob = nil,nil
end

local function tryUseFloorChangeTarget(target, force)
  if not force and not allowFloorChanges() then return false end
  if not hasPosition(target) or not player or not player.getPosition then return false end

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
  state.lastFloorAction = {target=copyPosition(target),at=time}
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
    setStatus(force and "Regresando de piso" or "Usando cambio de piso", force and "#ffd166" or "#8fd3ff")
    return true
  end

  return false
end

local function returnParams(floorTarget)
  local params = getFloorReturnPathParams()
  params.allowedFloor = floorTarget
  params.ignoreStairs = floorTarget ~= nil
  return params
end

local function returnCandidates(link,playerPos)
  local candidates = {}
  local projected = {x=link.entry.x,y=link.entry.y,z=playerPos.z}
  for x=link.landing.x-3,link.landing.x+3 do
    for y=link.landing.y-3,link.landing.y+3 do
      local pos = {x=x,y=y,z=playerPos.z}
      local tile = g_map.getTile(pos)
      if tile and (isFloorChangeTile(tile,pos) or getFloorChangeThing(tile)) and
          not (link.failed[positionKey(pos)] and link.failed[positionKey(pos)]>currentTime()) then
        local thing,action = getFloorChangeThing(tile)
        local score = distance2d(pos,projected)*5 + distance2d(pos,link.landing)*2
        if action == "rope" and link.source.z < playerPos.z then score = score-10 end
        candidates[#candidates+1] = {pos=pos,action=action,score=score,walkable=isWalkableTile(tile)}
      end
    end
  end
  table.sort(candidates,function(a,b)return a.score<b.score end)
  return candidates
end

local function returnStand(target,playerPos)
  if distance2d(playerPos,target)<=1 then return copyPosition(playerPos) end
  local best,length
  for direction=0,7 do
    local dx,dy = directionOffset(direction)
    local pos = {x=target.x+dx,y=target.y+dy,z=target.z}
    local tile = g_map.getTile(pos)
    if tile and isWalkableTile(tile) and not tileHasCreature(tile) and not isFloorChangeTile(tile,pos) then
      local path = getPathTo(pos,math.max(20,getRadius()*2+10),returnParams())
      if path and not pathLeavesPerimeter(path,playerPos,true) and (not length or #path<length) then best,length=pos,#path end
    end
  end
  return best
end

local function failReturn(job)
  job.link.failed[positionKey(job.target)] = currentTime()+10000
  state.returnJob = nil
  clearPatrolWalk(true)
  state.nextWalkAt = currentTime()+TARGETBOT_PAUSE_DELAY
end

local function processFloorReturn(playerPos)
  if not shouldReturnToOriginFloor(playerPos) then state.returnJob=nil;return false end
  if state.target then clearTarget(false) end
  if currentTime() < state.nextWalkAt then return true end
  local link = state.floorLinks[#state.floorLinks]
  if not link or link.landing.z ~= playerPos.z then
    setStatus("Regreso pendiente: no se registro el acceso","#ffaa00")
    state.nextWalkAt = currentTime()+FLOOR_RETURN_SCAN_INTERVAL
    return true
  end
  setStatus("Regresando al piso "..tostring(state.origin.z).." por el mismo acceso","#ffd166")
  local job = state.returnJob
  if not job then
    local candidates = returnCandidates(link,playerPos)
    for index=1,math.min(#candidates,FLOOR_RETURN_PATH_CHECKS) do
      local candidate = candidates[index]
      local stand = candidate.action and returnStand(candidate.pos,playerPos) or candidate.pos
      local params = returnParams(not candidate.action and candidate.pos or nil)
      local path = stand and (samePosition(stand,playerPos) and {} or getPathTo(stand,math.max(20,getRadius()*2+10),params))
      if path and not pathLeavesPerimeter(path,playerPos,true) then
        job = {link=link,target=candidate.pos,action=candidate.action,stand=stand,walkable=candidate.walkable,phase="approach"}
        state.returnJob = job
        break
      end
    end
    if not job then
      setStatus("Regreso pendiente: acceso cercano bloqueado o no visible","#ffaa00")
      state.nextWalkAt = currentTime()+FLOOR_RETURN_SCAN_INTERVAL
      return true
    end
  end
  if job.phase == "waiting" then
    if currentTime()<job.untilAt then return true end
    if job.action and not job.triedWalk and job.walkable then
      job.triedWalk=true;job.action=nil;job.phase="approach";job.stand=job.target
    else failReturn(job);return true end
  end
  if job.phase == "away" then
    if samePosition(playerPos,job.away) then job.phase="enter" end
    if job.phase=="away" then
      if not patrolWalkTo(job.away,20,returnParams(),true) then failReturn(job) end
      return true
    end
  end
  if job.action then
    if distance2d(playerPos,job.target)>1 then
      if not patrolWalkTo(job.stand,math.max(20,getRadius()*2+10),returnParams(),true) then failReturn(job) end
      return true
    end
    clearPatrolWalk(true)
    local thing = getFloorChangeThing(g_map.getTile(job.target))
    local extras = storage and storage.extras or {}
    state.lastFloorAction = {target=copyPosition(job.target),at=currentTime()}
    local used = job.action=="rope" and tryUseTool(extras.rope or 3003,thing) or
      job.action=="shovel" and tryUseTool(extras.shovel or 3457,thing) or
      job.action=="use" and tryUseThing(thing)
    if used then job.phase="waiting";job.untilAt=currentTime()+FLOOR_USE_COOLDOWN else failReturn(job) end
    return true
  end
  if samePosition(playerPos,job.target) and job.phase~="enter" then
    for direction=0,7 do
      local dx,dy = directionOffset(direction)
      local pos={x=playerPos.x+dx,y=playerPos.y+dy,z=playerPos.z}
      local tile=g_map.getTile(pos)
      if tile and isWalkableTile(tile) and not tileHasCreature(tile) and not isFloorChangeTile(tile,pos) and
          not pathLeavesPerimeter({direction},playerPos,true) then job.away=pos;job.phase="away";return true end
    end
    failReturn(job);return true
  end
  if samePosition(playerPos,job.target) then job.phase="waiting";job.untilAt=currentTime()+FLOOR_USE_COOLDOWN;return true end
  job.phase="enter"
  if not patrolWalkTo(job.target,math.max(20,getRadius()*2+10),returnParams(job.target),true) then failReturn(job) end
  return true
end

local function walkToTarget(target)
  if tryUseFloorChangeTarget(target) then return true end

  local radius = getRadius()
  local walkTarget = state.targetWalkPos or target
  local playerPos = player and player.getPosition and player:getPosition() or nil
  if hasPosition(walkTarget) and samePosition(walkTarget, player:getPosition()) and tryUseFloorChangeTarget(target) then
    return true
  end

  local ok, result = pcall(function()
    return patrolWalkTo(walkTarget, math.max(8, radius * 2 + 10), getPathParams(), false)
  end)
  return ok and result == true
end

local function processStuck(playerPos)
  if patrolWalk.pending and patrolWalk.pending.native then return false end -- Its own bounded deadline handles missing progress.
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

local function getReturnInsideRadiusTarget(playerPos)
  if not hasPosition(playerPos) or not g_map or not g_map.getTile then return nil end

  local candidates = {}
  forEachNearbyTile(playerPos, MAX_RETURN_SCAN_RADIUS, function(tile)
    local tilePos = getTilePosition(tile)
    if tilePos and tilePos.z == playerPos.z and inStableReturnArea(tilePos) and canUseTile(tile) then
      table.insert(candidates, {
        pos = copyPosition(tilePos),
        distance = distance2d(playerPos, tilePos),
        anchorDistance = distance2d(getAnchor(), tilePos)
      })
    end
  end)

  if #candidates == 0 then
    forEachNearbyTile(playerPos, MAX_RETURN_SCAN_RADIUS, function(tile)
      local tilePos = getTilePosition(tile)
      if tilePos and tilePos.z == playerPos.z and inCurrentRadius(tilePos) and canUseTile(tile) then
        table.insert(candidates, {
          pos = copyPosition(tilePos),
          distance = distance2d(playerPos, tilePos),
          anchorDistance = distance2d(getAnchor(), tilePos)
        })
      end
    end)
  end

  table.sort(candidates, function(a, b)
    if a.distance ~= b.distance then return a.distance < b.distance end
    return a.anchorDistance < b.anchorDistance
  end)

  local maxDistance = math.max(8, getRadius() * 2 + 10)
  local checked = 0
  for _, candidate in ipairs(candidates) do
    if checked >= RETURN_PATH_CHECKS then break end
    checked = checked + 1

    local path = getPathTo(candidate.pos, maxDistance)
    if path and not pathLeavesPerimeter(path, playerPos, true) then
      return candidate.pos
    end
  end

  return nil
end

local function keepInsideRadius(playerPos)
  if inCurrentRadius(playerPos) then return false end

  if patrolWalk.dest and inStableReturnArea(patrolWalk.dest) and
      patrolWalkTo(patrolWalk.dest, math.max(20,getRadius()*2+10), getPathParams(), true) then
    setStatus("Volviendo al perimetro", "#ffd166")
    return true
  end

  clearTarget(false)
  if CaveBot.resetWalking then pcall(CaveBot.resetWalking) end

  local returnTarget = getReturnInsideRadiusTarget(playerPos)
  if returnTarget then
    local maxDistance = math.max(8, distance2d(playerPos, returnTarget) + 8)
    local ok, walking = pcall(function()
      return patrolWalkTo(returnTarget, maxDistance, getPathParams(), true)
    end)
    if ok and walking then
      state.nextWalkAt = currentTime() + FAST_STEP_DELAY
      setStatus("Volviendo al perimetro", "#ffd166")
      return true
    end
  end

  state.nextWalkAt = currentTime() + EMPTY_SCAN_INTERVAL
  state.nextScanAt = currentTime() + EMPTY_SCAN_INTERVAL
  setStatus("Fuera del perimetro | buscando regreso", "#ffd166")
  return true
end

local function pausePatrol(reason)
  clearPatrolWalk(true)
  if state.huntRoute then state.huntRoute.job,state.huntRoute.ready=nil,nil end
  state.targetNoProgressAt, state.lastMoveAt = currentTime(), currentTime()
  state.nextWalkAt = currentTime() + FAST_STEP_DELAY
  setStatus(reason, "#ffd166")
end

local function explorerTick()
  if not state.enabled then return end
  if currentTime() < (state.nextThinkAt or 0) then return end
  state.nextThinkAt = currentTime() + THINK_INTERVAL
  if CaveBot.Flee and CaveBot.Flee.blocksCombat() then pausePatrol("Pausa: huida");return end
  if HelperPause and HelperPause.isPaused() then pausePatrol("Pausa: usuario");return end
  if PushMax and PushMax.ownsMovement and PushMax.ownsMovement() then pausePatrol("Pausa: Push Max");return end
  local movement = TargetBot and TargetBot.Movement
  if movement and movement.isManual and movement.isManual() then pausePatrol("Pausa: movimiento manual");return end
  local safety = TargetBot and TargetBot.Antitrap
  if safety and safety.ownsMovement and safety.ownsMovement() then pausePatrol("Pausa: antitrap");return end

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
  observeHunt()
  if processFloorReturn(playerPos) then return end

  local plan = AttackAlignment and AttackAlignment.getPlan and AttackAlignment.getPlan()
  if currentTime() < state.holdUntil or (plan and plan.committed) or shouldPauseForTargetBot() then
    pausePatrol("Pausa: TargetBot | " .. countVisited() .. " cubiertos");return
  end

  if keepInsideRadius(playerPos) then return end
  updateHuntRoute(playerPos)

  if state.lastWalkedKey ~= positionKey(playerPos) then markAreaCovered(playerPos);markWalked(playerPos) end

  prepareNextLeg()
  local nextLeg = state.nextPlan
  if nextLeg and samePosition(playerPos,nextLeg.from) and currentTime()-nextLeg.at<8000 and
      nextLeg.radius==getRadius() and nextLeg.sameFloor==sameFloorEnabled() and not patrolWalk.pending and
      (nextLeg.mode~="route" or state.huntRoute.covered[nextLeg.key]~=state.huntRoute.cycle) then
    markRecentTarget(state.targetKey)
    setTarget(nextLeg.target,nextLeg.key,nextLeg.mode,nextLeg.walkPos,nextLeg.path)
  end

  if state.target and state.targetKey and state.visited[state.targetKey] and distance2d(playerPos, state.target) <= 1 and
      not (patrolWalk.pending and patrolWalk.pending.native) then
    clearTarget(true)
    if CaveBot.resetWalking then pcall(CaveBot.resetWalking) end
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
    local target, key, path, mode, walkPos = chooseTarget()
    if target then
      setTarget(target, key, mode, walkPos, path)
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
    state.nextScanAt = currentTime() + TARGETBOT_PAUSE_DELAY
    setStatus("Ruta bloqueada", "#ffd166")
    return
  end

  state.nextWalkAt = currentTime() + FAST_STEP_DELAY
  setStatus("Cazando | vuelta " .. (state.huntRoute and state.huntRoute.cycle or 1) .. " | " .. countVisited() .. " cubiertos", "#8fd3ff")
end

AutoExplorer.isOn = function()
  return state.enabled == true
end

AutoExplorer.getStatus = function()
  local sectors = 0
  for _ in pairs(state.sectors) do sectors = sectors + 1 end
  local route=state.huntRoute
  local covered=0
  if route then for key in pairs(route.nodes) do if route.covered[key]==route.cycle then covered=covered+1 end end end
  return {enabled=state.enabled,mode="hunt",status=state.status,radius=getRadius(),
    center=copyPosition(state.origin),target=copyPosition(state.target),visited=state.visitedCount,
    sectors=sectors,pending=patrolWalk.pending~=nil,walkMode=patrolWalk.lastMode,chunkSize=WALK_CHUNK_SIZE,
    prefetched=state.nextPlan~=nil,sameFloor=sameFloorEnabled(),floorLinks=#state.floorLinks,
    routeNodes=state.huntRoute and state.huntRoute.nodeCount or 0,routeCycle=state.huntRoute and state.huntRoute.cycle or 0,
    routeCovered=covered,routePending=route and route.nodeCount-covered or 0,routeSelections=route and route.selections or 0,
    planning=state.huntRoute and state.huntRoute.job~=nil or false,
    returnAccess=state.returnJob and copyPosition(state.returnJob.target) or nil,
    preview=isPreviewEnabled(),overlayVisible=minimapOverlay.visible==true}
end

AutoExplorer.enable = function()
  if CaveBot.Flee and CaveBot.Flee.blocksCombat() then
    warn('Huida PvP retenida: rearma antes de explorar.');return
  end
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
  warn("Auto Explorer: caza automatica activada. Radio: " .. getRadius() .. " sqm.")
end

AutoExplorer.disable = function()
  if not state.enabled then return end
  state.enabled = false
  if CaveBot.resetWalking then pcall(CaveBot.resetWalking) end
  clearTarget(false)
  state.floorReturnTarget = nil
  state.floorReturnStartedAt = 0
  refreshOverlayNow(true)
  setStatus("Off | " .. countVisited() .. " cubiertos", "#c8c8c8")
  updateButtons()
  warn("Auto Explorer detenido.")
end

local function forceAutoExplorerOff(reason)
  if not state.enabled then
    refreshOverlayNow(true)
    return
  end

  state.enabled = false
  if CaveBot.resetWalking then pcall(CaveBot.resetWalking) end
  clearTarget(false)
  state.floorReturnTarget = nil
  state.floorReturnStartedAt = 0
  refreshOverlayNow(true)
  setStatus(reason or ("Off | " .. countVisited() .. " cubiertos"), "#c8c8c8")
  updateButtons()
end

AutoExplorer.reset = function()
  local keepCenter = state.enabled and hasPosition(state.origin)
  resetRuntime(state.enabled, keepCenter)
  if state.enabled and player and player.getPosition then
    updateMinimapOverlay(player:getPosition(), true)
  else
    refreshOverlayNow(true)
  end
  if state.enabled then
    warn("Auto Explorer reiniciado sin mover el centro.")
  end
  updateButtons()
end

AutoExplorer.hideOverlay = destroyMinimapOverlay

if CaveBot.setOn and not CaveBot._autoExplorerSetOnHooked then
  CaveBot._autoExplorerSetOnHooked = true
  CaveBot._autoExplorerOriginalSetOn = CaveBot.setOn
  CaveBot.setOn = function(val)
    if val ~= false then
      forceAutoExplorerOff("Off | CaveBot activado")
    end
    return CaveBot._autoExplorerOriginalSetOn(val)
  end
end

if CaveBot.setOff and not CaveBot._autoExplorerSetOffHooked then
  CaveBot._autoExplorerSetOffHooked = true
  CaveBot._autoExplorerOriginalSetOff = CaveBot.setOff
  CaveBot.setOff = function(val)
    if val ~= false then
      forceAutoExplorerOff("Off | CaveBot pausado")
    end
    return CaveBot._autoExplorerOriginalSetOff(val)
  end
end

local function registerExplorerNumber(id, defaultValue, widget, onSet, slider)
  local syncing = false
  local currentValue = CaveBot.Config.values[id]
  if currentValue == nil then currentValue = defaultValue end

  CaveBot.Config.value_setters[id] = function(value)
    value = clampRadius(value)
    CaveBot.Config.values[id] = value
    syncing = true
    if widget then widget:setText(value, true) end
    if slider and slider.setValue then slider:setValue(value) end
    syncing = false
    if onSet then onSet(value) end
  end

  CaveBot.Config.default_values[id] = CaveBot.Config.default_values[id] or defaultValue
  if slider and slider.setRange then slider:setRange(AREA_MIN, AREA_MAX) end
  if slider and slider.setStep then slider:setStep(1) end
  CaveBot.Config.value_setters[id](currentValue)

  if widget then widget.onTextChange = function(_, newValue)
    if syncing then return end
    local value = tonumber(newValue)
    if not value then return end
    CaveBot.Config.value_setters[id](value)
    CaveBot.save()
  end end

  if slider then slider.onValueChange = function(_, value)
    if syncing then return end
    CaveBot.Config.value_setters[id](value)
    CaveBot.save()
  end end
end

local function registerExplorerSwitch(id, defaultValue, widget, onSet)
  if not widget then return end
  local currentValue = CaveBot.Config.values[id]
  if currentValue == nil then currentValue = defaultValue end

  CaveBot.Config.value_setters[id] = function(value)
    value = value == true
    CaveBot.Config.values[id] = value
    widget:setOn(value, true)
    if onSet then onSet(value) end
  end

  CaveBot.Config.default_values[id] = CaveBot.Config.default_values[id] or defaultValue
  CaveBot.Config.value_setters[id](currentValue)

  widget.onClick = function(widget)
    widget:setOn(not widget:isOn())
    CaveBot.Config.value_setters[id](widget:isOn())
    CaveBot.save()
  end
end

AutoExplorer.setupMainPanel = function(panel)
  if not panel then return end
  AutoExplorer.panel = panel

  registerExplorerNumber("autoExplorerRadius", AREA_DEFAULT, panel.statusRow.radiusEdit, function()
    clearTarget(false)
    refreshOverlayNow(true)
  end, panel.perimeterRow and panel.perimeterRow.perimeterSlider)
  registerExplorerSwitch("autoExplorerFloors", true, panel.optionsRow.floorSwitch, function()
    if state.enabled then clearTarget(false) end
  end)
  registerExplorerSwitch("autoExplorerPreview", false, panel.optionsRow.previewSwitch, function(value)
    if value then
      refreshOverlayNow(true)
    else
      hideMinimapOverlay()
    end
    updateButtons()
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

  panel.enabled:setTooltip("Planea vueltas de caza dentro del radio: prioriza pasillos pendientes del mapa conocido y recuerda lo recorrido. Cede al combate y apaga la ruta del CaveBot.")
  panel.optionsRow.resetButton:setTooltip("Limpia memoria y ruta. El centro activo solo cambia al apagar y encender Auto Explorer.")
  panel.statusRow.radiusEdit:setTooltip("Radio de caza en SQM. El centro queda fijo donde activas Auto Explorer.")
  if panel.perimeterRow and panel.perimeterRow.perimeterSlider then
    panel.perimeterRow.perimeterSlider:setTooltip("Mueve la barra para ajustar el perimetro entre 20 y 120.")
  end
  panel.optionsRow.previewSwitch:setTooltip("Ver el radio de caza en el minimapa, incluso con Auto Explorer apagado.")
  panel.optionsRow.floorSwitch:setTooltip("ON: evita escaleras, huecos y cambios de piso. Si cambia de piso, incluso en OFF, regresa al inicial por el acceso registrado.")

  updateButtons()
  setStatus(state.status, state.statusColor)
end

onPlayerPositionChange(function(newPos, oldPos)
  if not hasPosition(newPos) then return end
  if state.enabled and hasPosition(oldPos) and newPos.z~=oldPos.z then recordFloorChange(newPos,oldPos) end
  observePatrolPosition(newPos)

  if not state.enabled then
    if isPreviewEnabled() then updateMinimapOverlay(newPos, true) end
    return
  end

  if hasPosition(oldPos) then markAreaCovered(oldPos) end
  updateMinimapOverlay(newPos, hasPosition(oldPos) and newPos.z ~= oldPos.z)

  if hasPosition(oldPos) and newPos.z ~= oldPos.z then
    state.lastStepDx = 0
    state.lastStepDy = 0
    clearTarget(false)
    if CaveBot.resetWalking then pcall(CaveBot.resetWalking) end

    if shouldReturnToOriginFloor(newPos) then
      state.floorReturnTarget = nil
      state.floorReturnStartedAt = currentTime()
      state.nextWalkAt = 0
      state.nextScanAt = 0
      setStatus("Regresando al piso " .. tostring(state.origin.z), "#ffd166")
      return
    end

    setStatus("Piso " .. tostring(newPos.z) .. " | " .. countVisited() .. " cubiertos", "#8cff9a")
  elseif hasPosition(oldPos) then
    state.lastStepDx = sign(newPos.x - oldPos.x)
    state.lastStepDy = sign(newPos.y - oldPos.y)
  end

  if shouldReturnToOriginFloor(newPos) then
    setStatus("Regresando al piso " .. tostring(state.origin.z), "#ffd166")
    return
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

macro(THINK_INTERVAL, function()
  if isPreviewEnabled() then
    refreshOverlayNow(false)
  end
  explorerTick()
end)

destroyMinimapOverlay() -- Retire a previous bot generation's drawing once, through the live map accessor.
