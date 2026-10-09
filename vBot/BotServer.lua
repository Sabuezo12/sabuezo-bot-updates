setDefaultTab("Main")
local regex = [["(.*?)"]]
local panelName = "BOTserver"
local DEFAULT_BOTSERVER_CHANNEL = "Slegna1324"
local DEFAULT_WEBSOCKET_URL = "wss://sabuezo-botserver-render.onrender.com/"
local DEFAULT_WEBSOCKET_TOKEN = "Slegna"
local BOTSERVER_DEFAULTS_VERSION = 6
local ui = setupUI([[
Panel
  height: 24

  BotServerSkinOpener
    id: botServer
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    height: 24
    !text: tr('BotServer')

    UIWidget
      id: connectionDot
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      margin-left: 8
      size: 14 14
      phantom: true

    BotServerIcon
      id: membersIcon
      anchors.left: connectionDot.right
      anchors.verticalCenter: parent.verticalCenter
      margin-left: 5
      size: 18 18

    Label
      id: memberBadge
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      margin-right: 6
      size: 24 20
      font: verdana-11px-antialised
      text-align: center
      text: 0
      phantom: true
      image-border: 4
]])
ui:setId(panelName)
vBot.BotServerOpener = ui.botServer
local openerAssetRoot = (configDir or '/bot/pruebas') .. '/vBot/botserver_assets/'
ui.botServer.connectionDot:setImageSource(openerAssetRoot .. 'status-red.png')
ui.botServer.membersIcon:setImageSource(openerAssetRoot .. 'members.png')
ui.botServer.memberBadge:setImageSource(openerAssetRoot .. 'input.png')

if not storage[panelName] then
  storage[panelName] = {
  manaInfo = true,
  broadcasts = true,
  minimapMembers = true,
  exivaTracker = true
}
end

local config = storage[panelName]
if storage.BotServerDefaultsVersion ~= BOTSERVER_DEFAULTS_VERSION then
  storage.BotServerChannel = DEFAULT_BOTSERVER_CHANNEL
  config.enabled = true
  config.transportMode = "websocket"
  config.guildChannelId = 0
  config.webSocketUrl = DEFAULT_WEBSOCKET_URL
  config.webSocketToken = DEFAULT_WEBSOCKET_TOKEN
  storage.BotServerDefaultsVersion = BOTSERVER_DEFAULTS_VERSION
elseif config.enabled == nil then
  config.enabled = true
else
  config.enabled = config.enabled == true
end
if config.manaInfo == nil then config.manaInfo = true end
if config.broadcasts == nil then config.broadcasts = true end
if config.minimapMembers == nil then config.minimapMembers = true end
if config.exivaTracker == nil then config.exivaTracker = true end
if config.transportMode ~= "guild" and config.transportMode ~= "party" and
   config.transportMode ~= "opcode" and
   config.transportMode ~= "websocket" then
  config.transportMode = "websocket"
end
config.guildChannelId = math.max(0, math.min(65535, tonumber(config.guildChannelId) or 0))
config.gameChannelId = math.max(0, math.min(65535, tonumber(config.gameChannelId) or 1))
config.extendedOpcode = math.max(0, math.min(255, tonumber(config.extendedOpcode) or 201))
config.webSocketUrl = DEFAULT_WEBSOCKET_URL
config.webSocketToken = DEFAULT_WEBSOCKET_TOKEN
-- Retired BotServer features; vocation outfits now belong to Player List.
config.mwallInfo = nil
config.mwalls = nil
config.vocation = nil
config.outfit = nil

BotServer._rodMasterMainGeneration = (BotServer._rodMasterMainGeneration or 0) + 1
local botServerListenGeneration = BotServer._rodMasterMainGeneration
local botServerListenSocket = nil
local serverCount = {}
local ServerMembers = nil
local members = {}
vBot.BotServerMembers = {}
local memberInfo = {}
local lastPresenceSync = 0
local lastPresencePositionKey = nil
local lastPresenceMana = nil
local lastPresenceHp = nil
local visibleMemberHp = {}
local nextVisibleHpScanAt = 0
local lastPositionPresenceSync = 0
local GAME_STATUS_UPDATE_INTERVAL = 3000
local WEBSOCKET_MIN_STATUS_INTERVAL = 100
local MEMBER_TIMEOUT = 30000
local MEMBER_POSITION_TIMEOUT = 15000
local MEMBER_STATS_TIMEOUT = 15000
local MAX_MINIMAP_MARKERS = 16
local MINIMAP_MARKER_COLOR = "#ffffffff"
local MINIMAP_MARKER_SIZE = 13
local MINIMAP_MARKER_IMAGE = (type(configDir) == "string" and configDir or "/bot/pruebas") ..
  "/vBot/map_markers/member-diamond.png"
local MINIMAP_OVERLAY_UPDATE = 300
local clientId = nil
local minimapOverlay = {
  widget = nil,
  parent = nil,
  markers = {},
  nextUpdateAt = 0
}
local cyclopediaMinimapNextUpdateAt = 0

local function statusUpdateInterval()
  if config.transportMode == "websocket" then
    local connectionPing = tonumber(BotServer and BotServer.ping) or 0
    if connectionPing <= 0 then return WEBSOCKET_MIN_STATUS_INTERVAL end
    return math.max(WEBSOCKET_MIN_STATUS_INTERVAL, math.ceil(connectionPing))
  end
  return GAME_STATUS_UPDATE_INTERVAL
end

local function currentBotServerListeners(listenerSocket)
  return config.enabled and BotServer._websocket and
    BotServer._rodMasterMainGeneration == botServerListenGeneration and
    BotServer._websocket == listenerSocket
end

local function getSelfName()
  local ok, value = pcall(function() return name() end)
  if ok and value and value ~= "" then return value end

  ok, value = pcall(function() return player:getName() end)
  if ok and value and value ~= "" then return value end

  return "Unknown"
end

local function hasPosition(pos)
  return type(pos) == "table" and tonumber(pos.x) and tonumber(pos.y) and tonumber(pos.z)
end

local function copyPosition(pos)
  if not hasPosition(pos) then return nil end
  return {
    x = tonumber(pos.x),
    y = tonumber(pos.y),
    z = tonumber(pos.z)
  }
end

local function positionKey(pos)
  if not hasPosition(pos) then return nil end
  return tostring(pos.x) .. "," .. tostring(pos.y) .. "," .. tostring(pos.z)
end

local function getSelfPosition()
  if not player or not player.getPosition then return nil end

  local ok, pos = pcall(function() return player:getPosition() end)
  if ok then return copyPosition(pos) end
  return nil
end

local function normalizeManaPercent(value)
  value = tonumber(value)
  if not value or value ~= value or value == math.huge or value == -math.huge then return nil end
  return math.max(0, math.min(100, math.floor(value + 0.5)))
end

local function getSelfManaPercent()
  if type(manapercent) ~= "function" then return nil end
  local ok, value = pcall(manapercent)
  if not ok then return nil end
  return normalizeManaPercent(value)
end

local function getSelfHpPercent()
  if type(hppercent) ~= "function" then return nil end
  local ok, value = pcall(hppercent)
  if not ok then return nil end
  return normalizeManaPercent(value)
end

local function touchMember(memberName, info)
  if type(memberName) ~= "string" or memberName == "" then return end
  members[memberName] = now or 0
  if not vBot.BotServerMembers[memberName] then
    vBot.BotServerMembers[memberName] = true
    CachedFriends = {}
    CachedEnemies = {}
  end

  if type(info) == "table" then
    local current = memberInfo[memberName] or {}
    current.name = memberName
    current.clientId = info.clientId or current.clientId
    local mana, hp, pos = normalizeManaPercent(info.mana), normalizeManaPercent(info.hp), copyPosition(info.pos)
    if mana ~= nil then current.mana, current.manaSeenAt = mana, now or 0 end
    if hp ~= nil then current.hp, current.hpSeenAt = hp, now or 0 end
    if pos then current.pos, current.positionSeenAt = pos, now or 0 end
    current.lastSeen = now or 0
    current.wallTime = tonumber(info.time) or os.time()
    memberInfo[memberName] = current
  elseif not memberInfo[memberName] then
    memberInfo[memberName] = {
      name = memberName,
      lastSeen = now or 0,
      wallTime = os.time()
    }
  end
end

local function applyVisibleMemberMana(memberName, mana)
  if not config.enabled or not config.manaInfo then return false end
  mana = normalizeManaPercent(mana)
  if mana == nil then return false end

  local okCreature, creature = pcall(function() return getPlayerByName(memberName) end)
  if not okCreature or not creature then return false end

  local ok = pcall(function() creature:setManaPercent(mana) end)
  return ok
end

local function refreshVisibleMemberMana()
  local currentTime = now or 0
  for memberName, info in pairs(memberInfo) do
    if info and info.mana ~= nil and currentTime - (info.lastSeen or 0) <= MEMBER_TIMEOUT then
      applyVisibleMemberMana(memberName, info.mana)
    end
  end
end

local function pruneMembers()
  local currentTime = now or 0
  for memberName, lastSeen in pairs(members) do
    if currentTime - lastSeen > MEMBER_TIMEOUT then
      members[memberName] = nil
      memberInfo[memberName] = nil
      vBot.BotServerMembers[memberName] = nil
      CachedFriends = {}
      CachedEnemies = {}
    end
  end

  if config.enabled and BotServer._websocket then
    touchMember(getSelfName())
  end
end

local function getMemberCount()
  local count = 0
  for _ in pairs(members) do
    count = count + 1
  end
  return count
end

local function getMembersTooltip()
  local names = {}
  for memberName in pairs(members) do
    local info = memberInfo[memberName]
    local text = memberName
    if info and hasPosition(info.pos) then
      text = text .. " - " .. positionKey(info.pos)
    end
    if info and info.mana ~= nil then
      text = text .. " - Mana " .. tostring(info.mana) .. "%"
    end
    table.insert(names, text)
  end
  table.sort(names)
  return table.concat(names, "\n")
end

local function readVisibleMemberHp()
  local currentTime = now or 0
  if not config.enabled or not BotServer._websocket then
    visibleMemberHp, nextVisibleHpScanAt = {}, 0
    return visibleMemberHp
  end
  -- Store only names, percentages and times. Never keep native creature userdata.
  if currentTime < nextVisibleHpScanAt and nextVisibleHpScanAt - currentTime <= 500 then
    return visibleMemberHp
  end
  nextVisibleHpScanAt = currentTime + 500
  visibleMemberHp = {}
  local wanted, hasWanted = {}, false
  local ownName = getSelfName():lower()
  for memberName, info in pairs(memberInfo) do
    if memberName:lower() ~= ownName and (info.hp == nil or not info.hpSeenAt or
      currentTime - info.hpSeenAt > MEMBER_STATS_TIMEOUT) then
      wanted[memberName:lower()] = memberName
      hasWanted = true
    end
  end
  if not hasWanted then return visibleMemberHp end
  local ok, spectators = pcall(function()
    if type(getSpectators) == 'function' then return getSpectators() end
  end)
  if not ok or type(spectators) ~= 'table' then return visibleMemberHp end
  for _, creature in ipairs(spectators) do
    local readOk, memberName, health = pcall(function()
      if not creature:isPlayer() then return end
      local who = wanted[tostring(creature:getName()):lower()]
      if not who then return end
      return who, normalizeManaPercent(creature:getHealthPercent())
    end)
    if readOk and memberName and health ~= nil then
      visibleMemberHp[memberName] = {hp = health, seenAt = currentTime}
    end
  end
  return visibleMemberHp
end

BotServer.getMemberSnapshot = function(includeVisibleHealth)
  pruneMembers()
  local visibleHealth = includeVisibleHealth and readVisibleMemberHp() or {}
  local snapshot = {}
  for memberName, info in pairs(memberInfo) do
    snapshot[memberName] = {
      name = memberName,
      clientId = info and info.clientId or nil,
      mana = info and info.mana or nil,
      hp = info and info.hp or nil,
      manaSeenAt = info and info.manaSeenAt or nil,
      hpSeenAt = info and info.hpSeenAt or nil,
      positionSeenAt = info and info.positionSeenAt or nil,
      pos = info and copyPosition(info.pos) or nil,
      lastSeen = info and info.lastSeen or nil,
      wallTime = info and info.wallTime or nil
    }
    local observation = visibleHealth[memberName]
    local remoteHpFresh = info and info.hp ~= nil and info.hpSeenAt and
      (now or 0) - info.hpSeenAt <= MEMBER_STATS_TIMEOUT
    if observation and not remoteHpFresh then
      snapshot[memberName].hp, snapshot[memberName].hpSeenAt = observation.hp, observation.seenAt
      snapshot[memberName].hpSource = 'visible'
    elseif info and info.hp ~= nil then snapshot[memberName].hpSource = 'shared' end
  end

  local selfName = getSelfName()
  snapshot[selfName] = snapshot[selfName] or {name = selfName}
  snapshot[selfName].pos = getSelfPosition() or snapshot[selfName].pos
  if config.enabled and BotServer._websocket then
    snapshot[selfName].lastSeen = now or snapshot[selfName].lastSeen
    snapshot[selfName].positionSeenAt = now or 0
    snapshot[selfName].hp, snapshot[selfName].hpSeenAt = getSelfHpPercent(), now or 0
    snapshot[selfName].hpSource = 'shared'
    snapshot[selfName].mana, snapshot[selfName].manaSeenAt = getSelfManaPercent(), now or 0
  end
  return snapshot
end

BotServer.isExivaTrackerEnabled = function()
  return config.enabled and config.exivaTracker == true
end

local function safeFileName(value)
  value = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
  value = value:gsub("[^%w%-_]", "_")
  if value == "" then value = "default" end
  return value
end

local function sendBotServer(topic, message)
  if not BotServer._websocket then return false end

  local ok = pcall(function()
    if message == nil then
      BotServer.send(topic)
    else
      BotServer.send(topic, message)
    end
  end)
  return ok == true
end

local function publishPresence(force)
  if not config.enabled then return end
  local selfPos = getSelfPosition()
  local selfPosKey = positionKey(selfPos)
  local selfMana = getSelfManaPercent()
  local selfHp = getSelfHpPercent()
  local moved = selfPosKey and selfPosKey ~= lastPresencePositionKey
  local manaChanged = selfMana ~= lastPresenceMana
  local hpChanged = selfHp ~= lastPresenceHp
  local canSendStatus = (moved or manaChanged or hpChanged) and now and
    now - lastPositionPresenceSync >= statusUpdateInterval()
  if not force and not canSendStatus and now and now - lastPresenceSync < 5000 then return end

  local selfName = getSelfName()
  lastPresenceSync = now or 0
  if force or canSendStatus then
    lastPresencePositionKey = selfPosKey
    lastPresenceMana = selfMana
    lastPresenceHp = selfHp
    lastPositionPresenceSync = now or 0
  end
  touchMember(selfName, {clientId = clientId, mana = selfMana, hp = selfHp, pos = selfPos})
  sendBotServer("presence", {
    clientId = clientId,
    name = selfName,
    mana = selfMana,
    hp = selfHp,
    pos = selfPos
  })
end

local function getMinimapWidget()
  if not modules or not modules.game_minimap then return nil end

  if modules.game_minimap.getMiniMapUi then
    local ok, minimap = pcall(modules.game_minimap.getMiniMapUi)
    if ok and minimap then return minimap end
  end

  return modules.game_minimap.minimapWidget
end

local function destroyMemberMinimapOverlayWidgets(minimap, keepWidget)
  if not minimap then return end

  if minimap.getChildren then
    local okChildren, children = pcall(function() return minimap:getChildren() end)
    if okChildren and type(children) == "table" then
      for _, child in pairs(children) do
        local okId, id = pcall(function()
          return child.getId and child:getId() or nil
        end)
        if child ~= keepWidget and okId and id == "botServerMembersMinimapOverlay" then
          pcall(function() child:destroy() end)
        end
      end
    end
  end

  if keepWidget or not minimap.getChildById then return end
  for _ = 1, 5 do
    local ok, child = pcall(function() return minimap:getChildById("botServerMembersMinimapOverlay") end)
    if not ok or not child then break end
    pcall(function() child:destroy() end)
  end
end

local function hideMemberMinimapOverlay()
  local minimap = minimapOverlay.parent or getMinimapWidget()
  local markers = minimapOverlay.markers
  if minimap and type(minimap._sabuezoBotServerMarkers) == "table" then
    markers = minimap._sabuezoBotServerMarkers
  end
  for _, marker in pairs(markers or {}) do
    if marker.widget then
      pcall(function() marker.widget:destroy() end)
    elseif minimap and marker.id ~= nil and
           type(minimap.removeWidget) == "function" then
      pcall(function() minimap:removeWidget(marker.id) end)
    end
  end
  minimapOverlay.markers = {}
  if minimap then minimap._sabuezoBotServerMarkers = {} end

  destroyMemberMinimapOverlayWidgets(minimap)

  if minimapOverlay.widget then
    pcall(function() minimapOverlay.widget:destroy() end)
  end
  minimapOverlay.widget = nil
  minimapOverlay.parent = nil
end

local function createMemberMinimapOverlay()
  local minimap = getMinimapWidget()
  if not minimap then return nil end

  if minimapOverlay.widget and minimapOverlay.parent == minimap then
    destroyMemberMinimapOverlayWidgets(minimap, minimapOverlay.widget)
    return minimapOverlay.widget
  end

  hideMemberMinimapOverlay()

  minimapOverlay.parent = minimap
  minimapOverlay.widget = setupUI([[
Panel
  id: botServerMembersMinimapOverlay
  anchors.fill: parent
  phantom: true
  focusable: false
  visible: false
  background-color: alpha

  UIWidget
    id: marker1
    anchors.left: parent.left
    anchors.top: parent.top
    size: 5 5
    phantom: true
    focusable: false
    background-color: #00ffd0dd

  UIWidget
    id: marker2
    anchors.left: parent.left
    anchors.top: parent.top
    size: 5 5
    phantom: true
    focusable: false
    background-color: #00ffd0dd

  UIWidget
    id: marker3
    anchors.left: parent.left
    anchors.top: parent.top
    size: 5 5
    phantom: true
    focusable: false
    background-color: #00ffd0dd

  UIWidget
    id: marker4
    anchors.left: parent.left
    anchors.top: parent.top
    size: 5 5
    phantom: true
    focusable: false
    background-color: #00ffd0dd

  UIWidget
    id: marker5
    anchors.left: parent.left
    anchors.top: parent.top
    size: 5 5
    phantom: true
    focusable: false
    background-color: #00ffd0dd

  UIWidget
    id: marker6
    anchors.left: parent.left
    anchors.top: parent.top
    size: 5 5
    phantom: true
    focusable: false
    background-color: #00ffd0dd

  UIWidget
    id: marker7
    anchors.left: parent.left
    anchors.top: parent.top
    size: 5 5
    phantom: true
    focusable: false
    background-color: #00ffd0dd

  UIWidget
    id: marker8
    anchors.left: parent.left
    anchors.top: parent.top
    size: 5 5
    phantom: true
    focusable: false
    background-color: #00ffd0dd

  UIWidget
    id: marker9
    anchors.left: parent.left
    anchors.top: parent.top
    size: 5 5
    phantom: true
    focusable: false
    background-color: #00ffd0dd

  UIWidget
    id: marker10
    anchors.left: parent.left
    anchors.top: parent.top
    size: 5 5
    phantom: true
    focusable: false
    background-color: #00ffd0dd

  UIWidget
    id: marker11
    anchors.left: parent.left
    anchors.top: parent.top
    size: 5 5
    phantom: true
    focusable: false
    background-color: #00ffd0dd

  UIWidget
    id: marker12
    anchors.left: parent.left
    anchors.top: parent.top
    size: 5 5
    phantom: true
    focusable: false
    background-color: #00ffd0dd

  UIWidget
    id: marker13
    anchors.left: parent.left
    anchors.top: parent.top
    size: 5 5
    phantom: true
    focusable: false
    background-color: #00ffd0dd

  UIWidget
    id: marker14
    anchors.left: parent.left
    anchors.top: parent.top
    size: 5 5
    phantom: true
    focusable: false
    background-color: #00ffd0dd

  UIWidget
    id: marker15
    anchors.left: parent.left
    anchors.top: parent.top
    size: 5 5
    phantom: true
    focusable: false
    background-color: #00ffd0dd

  UIWidget
    id: marker16
    anchors.left: parent.left
    anchors.top: parent.top
    size: 5 5
    phantom: true
    focusable: false
    background-color: #00ffd0dd
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

local function hideAllMinimapMarkers(overlay)
  if not overlay then return end
  for i = 1, MAX_MINIMAP_MARKERS do
    local marker = overlay["marker" .. i]
    if marker then
      pcall(function() marker:setVisible(false) end)
    end
  end
end

local function setMinimapMarker(marker, x, y, tooltip)
  if not marker then return end
  pcall(function() marker:setBackgroundColor("alpha") end)
  pcall(function() marker:setImageSource(MINIMAP_MARKER_IMAGE) end)
  pcall(function() marker:setVisible(true) end)
  pcall(function() marker:setTooltip(tooltip or "") end)
  pcall(function() marker:setPhantom(false) end)
  pcall(function() marker:setMarginLeft(math.floor(x)) end)
  pcall(function() marker:setMarginTop(math.floor(y)) end)
  pcall(function() marker:setSize({width = MINIMAP_MARKER_SIZE, height = MINIMAP_MARKER_SIZE}) end)
end

local function nativeMinimapSupported(minimap)
  return minimap and g_ui and type(g_ui.createWidget) == "function" and
    type(minimap.centerInPosition) == "function"
end

local function nativeMarkerTooltip(memberName, info)
  return tostring(memberName)
end

local function updateNativeMemberMinimap(minimap, markerStorageKey, trackPrimary)
  markerStorageKey = markerStorageKey or "_sabuezoBotServerMarkers"
  if trackPrimary and minimapOverlay.parent ~= minimap then
    hideMemberMinimapOverlay()
    minimapOverlay.parent = minimap
  end

  destroyMemberMinimapOverlayWidgets(minimap)

  if type(minimap[markerStorageKey]) ~= "table" then
    minimap[markerStorageKey] = {}
  end
  local markers = minimap[markerStorageKey]
  if trackPrimary then minimapOverlay.markers = markers end

  local desired = {}
  local markerCount = 0
  local currentTime = now or 0
  local selfName = getSelfName()
  local nativeFailed = false
  local cameraPosition = nil
  if minimap.getCameraPosition then
    local ok, position = pcall(function() return minimap:getCameraPosition() end)
    if ok then cameraPosition = position end
  end

  for memberName, info in pairs(memberInfo) do
    if markerCount >= MAX_MINIMAP_MARKERS then break end
    if memberName ~= selfName and info and info.clientId ~= clientId and
       hasPosition(info.pos) and
       currentTime - (info.lastSeen or 0) <= MEMBER_POSITION_TIMEOUT then
      markerCount = markerCount + 1
      desired[memberName] = true

      local position = {
        x = tonumber(info.pos.x),
        y = tonumber(info.pos.y),
        z = tonumber(info.pos.z)
      }
      local posKey = positionKey(position)
      local marker = markers[memberName]

      if marker and not marker.widget then
        if marker.id ~= nil and type(minimap.removeWidget) == "function" then
          pcall(function() minimap:removeWidget(marker.id) end)
        end
        markers[memberName] = nil
        marker = nil
      end

      if not marker then
        local ok, widget = pcall(function()
          local cross = g_ui.createWidget("UIWidget", minimap)
          if not cross then return nil end
          cross:setId("botServerMember_" .. safeFileName(memberName))
          cross:setSize({width = MINIMAP_MARKER_SIZE, height = MINIMAP_MARKER_SIZE})
          cross:setImageSource(MINIMAP_MARKER_IMAGE)
          if cross.setImageColor then cross:setImageColor(MINIMAP_MARKER_COLOR) end
          if cross.setTooltip then cross:setTooltip(nativeMarkerTooltip(memberName, info)) end
          if cross.setPhantom then cross:setPhantom(false) end
          if cross.setFocusable then cross:setFocusable(false) end
          minimap:centerInPosition(cross, position)
          return cross
        end)
        if ok and widget then
          marker = {widget = widget, posKey = posKey}
          markers[memberName] = marker
        else
          nativeFailed = true
        end
      elseif marker.posKey ~= posKey then
        local ok = pcall(function()
          minimap:centerInPosition(marker.widget, position)
        end)
        if ok then marker.posKey = posKey else nativeFailed = true end
      end

      if marker and marker.widget then
        pcall(function()
          marker.widget:setVisible(not cameraPosition or
            tonumber(cameraPosition.z) == tonumber(position.z))
          marker.widget:setTooltip(nativeMarkerTooltip(memberName, info))
          if marker.widget.setPhantom then marker.widget:setPhantom(false) end
        end)
      end
    end
  end

  for memberName, marker in pairs(markers) do
    if not desired[memberName] then
      if marker.widget then
        pcall(function() marker.widget:destroy() end)
      elseif marker.id ~= nil and type(minimap.removeWidget) == "function" then
        pcall(function() minimap:removeWidget(marker.id) end)
      end
      markers[memberName] = nil
    end
  end
  return not nativeFailed
end

local CYCLOPEDIA_MARKER_KEY = "_sabuezoBotServerCyclopediaMarkers"

local function getCyclopediaMinimapWidget()
  local mapCyclopedia = modules and modules.game_cyclopedia and
    modules.game_cyclopedia.MapCyclopedia
  if mapCyclopedia and type(mapCyclopedia.getMinimapWidget) == "function" then
    local ok, minimap = pcall(function() return mapCyclopedia.getMinimapWidget() end)
    if ok and minimap then return minimap end
  end

  local root = g_ui and g_ui.getRootWidget and g_ui.getRootWidget()
  if not root or not root.recursiveGetChildById then return nil end
  local ok, minimap = pcall(function()
    local panel = root:recursiveGetChildById("MapDataPanel")
    return panel and panel:recursiveGetChildById("minimap") or nil
  end)
  return ok and minimap or nil
end

local function destroyNativeMemberMarkers(minimap, markerStorageKey)
  if not minimap or type(minimap[markerStorageKey]) ~= "table" then return end
  for _, marker in pairs(minimap[markerStorageKey]) do
    if marker.widget then
      pcall(function() marker.widget:destroy() end)
    elseif marker.id ~= nil and type(minimap.removeWidget) == "function" then
      pcall(function() minimap:removeWidget(marker.id) end)
    end
  end
  minimap[markerStorageKey] = {}
end

local function hideCyclopediaMemberMarkers()
  local minimap = getCyclopediaMinimapWidget()
  if minimap then destroyNativeMemberMarkers(minimap, CYCLOPEDIA_MARKER_KEY) end
end

local function updateCyclopediaMemberMinimap(force)
  if not config.enabled or not config.minimapMembers then
    hideCyclopediaMemberMarkers()
    return
  end
  if not force and now and now < cyclopediaMinimapNextUpdateAt then return end
  cyclopediaMinimapNextUpdateAt = (now or 0) + MINIMAP_OVERLAY_UPDATE

  local minimap = getCyclopediaMinimapWidget()
  if not nativeMinimapSupported(minimap) then return end
  updateNativeMemberMinimap(minimap, CYCLOPEDIA_MARKER_KEY, false)
end

local function updateMemberMinimapOverlay(force)
  if not config.enabled or not config.minimapMembers then
    hideMemberMinimapOverlay()
    return
  end

  if not force and now and now < minimapOverlay.nextUpdateAt then return end
  minimapOverlay.nextUpdateAt = (now or 0) + MINIMAP_OVERLAY_UPDATE

  local minimap = getMinimapWidget()
  if nativeMinimapSupported(minimap) then
    if updateNativeMemberMinimap(minimap, "_sabuezoBotServerMarkers", true) then return end
  end

  local overlay = createMemberMinimapOverlay()
  if not minimap or not overlay then return end

  local width, height = getWidgetSize(minimap)
  if not width or not height or width < 20 or height < 20 then
    hideMemberMinimapOverlay()
    return
  end

  local scale, centerMapPos = estimateMinimapScale(minimap, width, height)
  if not scale or not centerMapPos then
    hideMemberMinimapOverlay()
    return
  end

  hideAllMinimapMarkers(overlay)

  local markerIndex = 0
  local currentTime = now or 0
  local selfName = getSelfName()
  local centerX = width / 2
  local centerY = height / 2

  for memberName, info in pairs(memberInfo) do
    if markerIndex >= MAX_MINIMAP_MARKERS then break end
    if memberName ~= selfName and info and info.clientId ~= clientId and hasPosition(info.pos) and
      currentTime - (info.lastSeen or 0) <= MEMBER_POSITION_TIMEOUT and info.pos.z == centerMapPos.z then
      local x = centerX + (info.pos.x - centerMapPos.x) * scale
      local y = centerY + (info.pos.y - centerMapPos.y) * scale
      if x >= 0 and x <= width - MINIMAP_MARKER_SIZE and y >= 0 and y <= height - MINIMAP_MARKER_SIZE then
        markerIndex = markerIndex + 1
        local tooltip = tostring(memberName)
        setMinimapMarker(overlay["marker" .. markerIndex], clamp(x - 6, 0, width - MINIMAP_MARKER_SIZE), clamp(y - 6, 0, height - MINIMAP_MARKER_SIZE), tooltip)
      end
    end
  end

  if markerIndex == 0 then
    pcall(function() overlay:setVisible(false) end)
    return
  end

  pcall(function() overlay:setVisible(true) end)
  pcall(function() overlay:raise() end)
end

if not storage.BotServerChannel or storage.BotServerChannel == "" then
  storage.BotServerChannel = DEFAULT_BOTSERVER_CHANNEL
end

if not storage.BotServerClientId then
  math.randomseed(os.time())
  storage.BotServerClientId = tostring(math.random(1000000000000,9999999999999))
end
clientId = safeFileName(getSelfName()) .. "_" .. safeFileName(storage.BotServerClientId)

local channel = tostring(storage.BotServerChannel)
if config.enabled then
  BotServer.init(name(), channel)
end

local function restartGameTransport()
  if not config.enabled or not GameBotServerTransport or not GameBotServerTransport.restart then return end
  GameBotServerTransport.restart()
  schedule(100, function()
    if not config.enabled then return end
    initBotServerListenFunctions()
    publishPresence(true)
    updateStatusText()
  end)
end


rootWidget = g_ui.getRootWidget()
if rootWidget then
  botServerWindow = UI.createWindow('BotServerWindow')
  botServerWindow:hide()

  botServerWindow.enabled:setOn(config.enabled)
  botServerWindow.enabled.onClick = function()
    config.enabled = not config.enabled
    botServerWindow.enabled:setOn(config.enabled)
    if config.enabled then
      channel = tostring(storage.BotServerChannel)
      BotServer.init(name(), channel)
      botServerWindow.Data.ServerStatus:setText("GAME: STARTING")
      ui.botServer:setColor('#FFF380')
      botServerWindow.Data.ServerStatus:setColor('#FFF380')
    else
      if BotServer._websocket then
        BotServer.terminate()
      end
      if BotServer.resetReconnect then
        BotServer.resetReconnect()
      end
      botServerWindow.Data.ServerStatus:setText("DISCONNECTED")
      ui.botServer:setColor('#E3242B')
      botServerWindow.Data.ServerStatus:setColor('#E3242B')
      botServerWindow.Data.Participants:setText("-")
      botServerWindow.Data.Members:setTooltip('')
      ServerMembers = {}
      serverCount = {}
      members = {}
      memberInfo = {}
      vBot.BotServerMembers = {}
      CachedFriends = {}
      CachedEnemies = {}
      lastPresenceSync = 0
      hideMemberMinimapOverlay()
      hideCyclopediaMemberMarkers()
    end
    initBotServerListenFunctions()
    publishPresence(true)
    schedule(2000, updateStatusText)
  end

  botServerWindow.Data.Channel:setText(storage.BotServerChannel)
  pcall(function()
    botServerWindow.Data.Channel:setTooltip("Clave logica del grupo. Todos tus amigos deben usar exactamente la misma.")
    botServerWindow.Data.Random:setTooltip("Genera una clave de grupo nueva.")
  end)
  botServerWindow.Data.Channel.onTextChange = function(widget, text)
    storage.BotServerChannel = text
    channel = tostring(text)
    if GameBotServerTransport and GameBotServerTransport.setRoom then
      GameBotServerTransport.setRoom(channel)
    end
    members = {}
    memberInfo = {}
    vBot.BotServerMembers = {}
    CachedFriends = {}
    CachedEnemies = {}
    lastPresenceSync = 0
    hideMemberMinimapOverlay()
    hideCyclopediaMemberMarkers()
  end
  local transportLabels = {
    guild = "Guild",
    party = "Party",
    opcode = "Extended Opcode",
    websocket = "WebSocket"
  }
  local transportValues = {
    ["Guild"] = "guild",
    ["Party"] = "party",
    ["Extended Opcode"] = "opcode",
    ["WebSocket"] = "websocket"
  }
  botServerWindow.Transport.TransportMode:setOption(transportLabels[config.transportMode] or "Guild")
  botServerWindow.Transport.TransportMode.onOptionChange = function(widget)
    local option = widget:getCurrentOption()
    config.transportMode = transportValues[option and option.text or "Guild"] or "guild"
    restartGameTransport()
  end
  botServerWindow.Transport.GuildChannelId:setValue(config.guildChannelId)
  botServerWindow.Transport.GuildChannelId.onValueChange = function(widget, value)
    config.guildChannelId = math.max(0, math.min(65535, tonumber(value) or 0))
    restartGameTransport()
  end
  botServerWindow.Transport.GameChannelId:setValue(config.gameChannelId)
  botServerWindow.Transport.GameChannelId.onValueChange = function(widget, value)
    config.gameChannelId = math.max(0, math.min(65535, tonumber(value) or 1))
    restartGameTransport()
  end
  botServerWindow.Transport.ExtendedOpcode:setValue(config.extendedOpcode)
  botServerWindow.Transport.ExtendedOpcode.onValueChange = function(widget, value)
    config.extendedOpcode = math.max(0, math.min(255, tonumber(value) or 201))
    restartGameTransport()
  end
  pcall(function()
    botServerWindow.Transport.TransportMode:setTooltip(
      "WebSocket usa Render y es el modo mas rapido. Guild/Party usan el chat del juego.")
    botServerWindow.Transport.GuildChannelId:setTooltip(
      "ID del canal Guild. En protocolo 8.6 normalmente es 0.")
    botServerWindow.Transport.GameChannelId:setTooltip(
      "ID del canal Party. En protocolo 8.6 normalmente es 1.")
    botServerWindow.Transport.ExtendedOpcode:setTooltip(
      "Opcode del relay instalado en el servidor. Debe coincidir en todos los clientes.")
  end)
  botServerWindow.Data.Random.onClick = function(widget)
    storage.BotServerChannel = tostring(math.random(1000000000000,9999999999999))
    botServerWindow.Data.Channel:setText(storage.BotServerChannel)
    members = {}
    memberInfo = {}
    vBot.BotServerMembers = {}
    CachedFriends = {}
    CachedEnemies = {}
    lastPresenceSync = 0
    hideMemberMinimapOverlay()
    hideCyclopediaMemberMarkers()
  end
  botServerWindow.Features.Feature1:setOn(config.manaInfo)
  pcall(function() botServerWindow.Features.Feature1:setTooltip("Muestra mana de miembros conectados cuando esten visibles.") end)
  botServerWindow.Features.Feature1.onClick = function(widget)
    config.manaInfo = not config.manaInfo
    widget:setOn(config.manaInfo)
  end
  botServerWindow.Features.Feature5:setOn(config.broadcasts)
  pcall(function() botServerWindow.Features.Feature5:setTooltip("Permite recibir mensajes broadcast del canal.") end)
  botServerWindow.Features.Feature5.onClick = function(widget)
    config.broadcasts = not config.broadcasts
    widget:setOn(config.broadcasts)
  end
  botServerWindow.Features.Feature6:setOn(config.minimapMembers)
  pcall(function() botServerWindow.Features.Feature6:setTooltip("Muestra miembros conectados en el minimapa y Cyclopedia Map.") end)
  botServerWindow.Features.Feature6.onClick = function(widget)
    config.minimapMembers = not config.minimapMembers
    widget:setOn(config.minimapMembers)
    if config.minimapMembers then
      updateMemberMinimapOverlay(true)
      updateCyclopediaMemberMinimap(true)
    else
      hideMemberMinimapOverlay()
      hideCyclopediaMemberMarkers()
    end
  end
  if botServerWindow.Features.Feature7 then
    botServerWindow.Features.Feature7:setOn(config.exivaTracker)
    pcall(function()
      botServerWindow.Features.Feature7:setTooltip(
        "Coordina exivas con miembros conectados y marca la zona estimada en los mapas.")
    end)
    botServerWindow.Features.Feature7.onClick = function(widget)
      config.exivaTracker = not config.exivaTracker
      widget:setOn(config.exivaTracker)
    end
  end
  botServerWindow.Features.Broadcast.onClick = function(widget)
    sendBotServer("broadcast", botServerWindow.Features.broadcastText:getText())
    botServerWindow.Features.broadcastText:setText('')
  end
end

function initBotServerListenFunctions()
  if not BotServer._websocket then return end
  if not config.enabled then return end
  if BotServer._rodMasterMainListenersGeneration == botServerListenGeneration and
    BotServer._rodMasterMainListenersSocket == BotServer._websocket then return end

  botServerListenSocket = BotServer._websocket
  local listenerSocket = botServerListenSocket
  BotServer._rodMasterMainListenersGeneration = botServerListenGeneration
  BotServer._rodMasterMainListenersSocket = botServerListenSocket

  -- list
  BotServer.listen("list", function(name, data)
    if not currentBotServerListeners(listenerSocket) then return end
    serverCount = regexMatch(json.encode(data), regex)
    ServerMembers = json.encode(data)
    if type(data) == "table" then
      for memberName, value in pairs(data) do
        if type(memberName) == "string" and memberName ~= "" and type(value) ~= "table" then
          touchMember(memberName)
        elseif type(value) == "string" then
          touchMember(value)
        elseif type(value) == "table" then
          touchMember(value.name or value.player or value[1])
        end
      end
    elseif type(data) == "string" then
      touchMember(data)
    end
  end)

  -- presence
  BotServer.listen("presence", function(name, message)
    if not currentBotServerListeners(listenerSocket) then return end

    local memberName = name
    if type(message) == "table" and type(message.name) == "string" and message.name ~= "" then
      memberName = message.name
    end

    touchMember(memberName, {
      clientId = type(message) == "table" and message.clientId or nil,
      mana = type(message) == "table" and message.mana or nil,
      hp = type(message) == "table" and message.hp or nil,
      pos = type(message) == "table" and message.pos or nil
    })
    if type(message) == "table" then
      applyVisibleMemberMana(memberName, message.mana)
    end
  end)

  -- mana
  BotServer.listen("mana", function(name, message)
    if not currentBotServerListeners(listenerSocket) then return end
    if config.manaInfo and type(message) == "table" then
      local memberName = type(message.name) == "string" and message.name ~= "" and message.name or name
      local mana = normalizeManaPercent(message.mana)
      touchMember(memberName, {mana = mana})
      applyVisibleMemberMana(memberName, mana)
    end
  end)

  -- broadcast
  BotServer.listen("broadcast", function(name, message)
    if not currentBotServerListeners(listenerSocket) then return end
    if config.broadcasts then
      broadcastMessage(name..": "..message)
    end
  end)
  publishPresence(true)
end
initBotServerListenFunctions()

function updateStatusText()
  pruneMembers()
  local statusText = "DISCONNECTED"
  local statusLevel = "error"
  if config.enabled and GameBotServerTransport and GameBotServerTransport.getStatus then
    statusText, statusLevel = GameBotServerTransport.getStatus()
  elseif BotServer._websocket then
    statusText = "GAME: CONNECTED"
    statusLevel = "connected"
  end
  local statusColor = statusLevel == "connected" and '#03AC13' or
    (statusLevel == "waiting" and '#FFF380' or '#E3242B')
  botServerWindow.Data.ServerStatus:setText(statusText)
  botServerWindow.Data.ServerStatus:setColor(statusColor)
  ui.botServer:setColor('#e4edf3')
  if BotServer._websocket then
    botServerWindow.Data.Participants:setText(getMemberCount())
    botServerWindow.Data.Members:setTooltip(getMembersTooltip())
  else
    botServerWindow.Data.Participants:setText("-")
    botServerWindow.Data.Members:setTooltip('')
  end
end

local exivaActivityUiCache={}
local function setExivaActivityLabel(key,widget,text,tooltip,color)
  if not widget then return end
  local cached=exivaActivityUiCache[key] or {}
  exivaActivityUiCache[key]=cached
  if cached.text~=text then widget:setText(text);cached.text=text end
  if tooltip and cached.tooltip~=tooltip then widget:setTooltip(tooltip);cached.tooltip=tooltip end
  if color and cached.color~=color then widget:setColor(color);cached.color=color end
end

local function shortExivaName(text)
  text=tostring(text or '')
  return #text>38 and text:sub(1,35)..'...' or text
end

local function updateExivaActivityPanel()
  local window=botServerWindow
  if not window or (type(window.isVisible)=='function' and not window:isVisible()) then return end
  local panel=window.ExivaActivity
  if not panel then return end
  setExivaActivityLabel('headerTime',panel.Headings.Time,'Hora')
  setExivaActivityLabel('headerInitiator',panel.Headings.Initiator,'Iniciador')
  setExivaActivityLabel('headerTarget',panel.Headings.Target,'Objetivo')
  local tracker=vBot and vBot.ExivaTracker
  local status=tracker and type(tracker.getControlStatus)=='function' and tracker.getControlStatus() or {}
  local history=tracker and type(tracker.getActivity)=='function' and tracker.getActivity() or {}
  local canStop=status.canStop==true
  panel.Stop:setVisible(canStop)
  panel.Stop:setEnabled(canStop and status.connected==true and (status.remaining or 0)==0)
  if not exivaActivityUiCache.stopBound then panel.Stop.onClick=function()
    local active=vBot and vBot.ExivaTracker
    if active and type(active.stopGroupExivas)=='function' then
      local ok=active.stopGroupExivas()
      if not ok and type(warn)=='function' then warn('No se pudo enviar la pausa de exiva al grupo.') end
      updateExivaActivityPanel()
    end
  end;exivaActivityUiCache.stopBound=true end
  local statusText,color
  if (status.remaining or 0)>0 then
    statusText='Pausa: '..status.remaining..' s | '..tostring(status.stoppedBy or '')
    color='#ffd166'
  elseif history[1] then
    local recent=history[1]
    statusText='Ultimo hace '..recent.ageSeconds..' s | '..recent.count..' inicio(s)'
    if recent.count>1 and recent.interval then statusText=statusText..' | intervalo '..recent.interval..' s' end
    color='#cfd3d7'
  else
    statusText='Sin exivas registrados';color='#a0a0a0'
  end
  setExivaActivityLabel('status',panel.Status,statusText,
    'Muestra quien inicia la busqueda, sin contar las respuestas automaticas de sus companeros. '..
    'La pausa apaga Exiva Target/Last durante 60 s; despues hace falta iniciar una busqueda nueva.',color)
  for index=1,4 do
    local row=panel['Row'..index]
    local entry=history[index]
    local tooltip=entry and (entry.initiator..' -> '..entry.target..'\nHora: '..entry.time..
      ' | hace '..entry.ageSeconds..' s\nInicios consecutivos: '..entry.count..
      (entry.interval and (' | ultimo intervalo: '..entry.interval..' s') or '')) or 'Sin registros'
    setExivaActivityLabel(index..'time',row.Time,entry and entry.time or '-',tooltip)
    setExivaActivityLabel(index..'initiator',row.Initiator,entry and shortExivaName(entry.initiator) or '-',tooltip)
    setExivaActivityLabel(index..'target',row.Target,entry and shortExivaName(entry.target) or '-',tooltip)
  end
end

macro(1000, updateExivaActivityPanel)

macro(100, function()
  if config.enabled then
    initBotServerListenFunctions()
    publishPresence()
    refreshVisibleMemberMana()
    updateMemberMinimapOverlay()
    updateCyclopediaMemberMinimap()
  else
    hideMemberMinimapOverlay()
    hideCyclopediaMemberMarkers()
  end
end)

macro(1000, function()
  pruneMembers()
  if config.enabled then
    initBotServerListenFunctions()
    publishPresence(true)
    if BotServer._websocket then
      sendBotServer("list")
    end
  end
  updateStatusText()
  delay(4000)
end)

ui.botServer.onClick = function(widget)
    botServerWindow:show()
    if vBot.BotServerDashboard then vBot.BotServerDashboard.refresh(true) end
    updateExivaActivityPanel()
    botServerWindow:raise()
    botServerWindow:focus()
end

botServerWindow.closeButton.onClick = function(widget)
    botServerWindow:hide()
end

publishPresence(true)
