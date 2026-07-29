setDefaultTab("Main")
local regex = [["(.*?)"]]
local panelName = "BOTserver"
local DEFAULT_BOTSERVER_CHANNEL = "Slegna1324"
local BOTSERVER_DEFAULTS_VERSION = 4
local ui = setupUI([[
Panel
  height: 18

  Button
    id: botServer
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    height: 18
    !text: tr('BotServer')
]])
ui:setId(panelName)

if not storage[panelName] then
  storage[panelName] = {
  manaInfo = true,
  mwallInfo = true,
  vocation = true,
  outfit = false,
  broadcasts = true,
  minimapMembers = true
}
end

local config = storage[panelName]
if storage.BotServerDefaultsVersion ~= BOTSERVER_DEFAULTS_VERSION then
  storage.BotServerChannel = DEFAULT_BOTSERVER_CHANNEL
  config.enabled = true
  config.transportMode = "guild"
  config.guildChannelId = 0
  storage.BotServerDefaultsVersion = BOTSERVER_DEFAULTS_VERSION
elseif config.enabled == nil then
  config.enabled = true
else
  config.enabled = config.enabled == true
end
if config.manaInfo == nil then config.manaInfo = true end
if config.mwallInfo == nil then config.mwallInfo = true end
if config.vocation == nil then config.vocation = true end
if config.outfit == nil then config.outfit = false end
if config.broadcasts == nil then config.broadcasts = true end
if config.minimapMembers == nil then config.minimapMembers = true end
if config.transportMode ~= "guild" and config.transportMode ~= "party" and
   config.transportMode ~= "auto" and config.transportMode ~= "opcode" then
  config.transportMode = "guild"
end
config.guildChannelId = math.max(0, math.min(65535, tonumber(config.guildChannelId) or 0))
config.gameChannelId = math.max(0, math.min(65535, tonumber(config.gameChannelId) or 1))
config.extendedOpcode = math.max(0, math.min(255, tonumber(config.extendedOpcode) or 201))
config.mwalls = {}

BotServer._rodMasterMainGeneration = (BotServer._rodMasterMainGeneration or 0) + 1
local botServerListenGeneration = BotServer._rodMasterMainGeneration
local botServerListenSocket = nil
local lastVocationSync = 0
local serverCount = {}
local ServerMembers = nil
local members = {}
local memberInfo = {}
local lastPresenceSync = 0
local lastPresencePositionKey = nil
local lastPositionPresenceSync = 0
local MEMBER_TIMEOUT = 30000
local MEMBER_POSITION_TIMEOUT = 15000
local MAX_MINIMAP_MARKERS = 16
local MINIMAP_OVERLAY_UPDATE = 300
local clientId = nil
local minimapOverlay = {
  widget = nil,
  parent = nil,
  nextUpdateAt = 0
}

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

local function touchMember(memberName, info)
  if type(memberName) ~= "string" or memberName == "" then return end
  members[memberName] = now or 0

  if type(info) == "table" then
    local current = memberInfo[memberName] or {}
    current.name = memberName
    current.clientId = info.clientId or current.clientId
    current.voc = info.voc or current.voc
    current.mana = info.mana or current.mana
    current.pos = copyPosition(info.pos) or current.pos
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

local function pruneMembers()
  local currentTime = now or 0
  for memberName, lastSeen in pairs(members) do
    if currentTime - lastSeen > MEMBER_TIMEOUT then
      members[memberName] = nil
      memberInfo[memberName] = nil
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
    table.insert(names, text)
  end
  table.sort(names)
  return table.concat(names, "\n")
end

local function safeFileName(value)
  value = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
  value = value:gsub("[^%w%-_]", "_")
  if value == "" then value = "default" end
  return value
end

local function pruneMwalls()
  for pos, expires in pairs(config.mwalls) do
    if not expires or expires < now then
      config.mwalls[pos] = nil
    end
  end
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
  local moved = selfPosKey and selfPosKey ~= lastPresencePositionKey
  local canSendMove = moved and now and now - lastPositionPresenceSync >= 1000
  if not force and not canSendMove and now and now - lastPresenceSync < 5000 then return end

  local selfName = getSelfName()
  lastPresenceSync = now or 0
  if force or canSendMove then
    lastPresencePositionKey = selfPosKey
    lastPositionPresenceSync = now or 0
  end
  touchMember(selfName, {clientId = clientId, voc = player:getVocation(), pos = selfPos})
  sendBotServer("presence", {clientId = clientId, name = selfName, voc = player:getVocation(), pos = selfPos})
end

local function syncVocation(force)
  if not config.enabled or not config.vocation then return end
  if not force and now and now - lastVocationSync < 10000 then return end

  lastVocationSync = now or 0
  sendBotServer("voc", player:getVocation())
  sendBotServer("voc", "yes")
end

local function getMinimapWidget()
  if not modules or not modules.game_minimap then return nil end
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
  local minimap = getMinimapWidget()
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
  pcall(function() marker:setVisible(true) end)
  pcall(function() marker:setTooltip(tooltip or "") end)
  pcall(function() marker:setMarginLeft(math.floor(x)) end)
  pcall(function() marker:setMarginTop(math.floor(y)) end)
  pcall(function() marker:setSize({width = 5, height = 5}) end)
  pcall(function() marker:setWidth(5) end)
  pcall(function() marker:setHeight(5) end)
end

local function updateMemberMinimapOverlay(force)
  if not config.enabled or not config.minimapMembers then
    hideMemberMinimapOverlay()
    return
  end

  if not force and now and now < minimapOverlay.nextUpdateAt then return end
  minimapOverlay.nextUpdateAt = (now or 0) + MINIMAP_OVERLAY_UPDATE

  local minimap = getMinimapWidget()
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
      if x >= 0 and x <= width - 5 and y >= 0 and y <= height - 5 then
        markerIndex = markerIndex + 1
        local tooltip = memberName .. "\nPos: " .. positionKey(info.pos)
        if info.voc then tooltip = tooltip .. "\nVoc: " .. tostring(info.voc) end
        setMinimapMarker(overlay["marker" .. markerIndex], clamp(x - 2, 0, width - 5), clamp(y - 2, 0, height - 5), tooltip)
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
    syncVocation(true)
    publishPresence(true)
    updateStatusText()
  end)
end

vBot.BotServerMembers = {}

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
      lastPresenceSync = 0
      hideMemberMinimapOverlay()
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
    lastPresenceSync = 0
    hideMemberMinimapOverlay()
  end
  local transportLabels = {
    guild = "Guild",
    party = "Party",
    auto = "Auto",
    opcode = "Extended Opcode"
  }
  local transportValues = {
    ["Guild"] = "guild",
    ["Party"] = "party",
    ["Auto"] = "auto",
    ["Extended Opcode"] = "opcode"
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
      "Guild es el modo principal. Party es alternativo. Auto prueba Opcode y conserva Guild como respaldo.")
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
    lastPresenceSync = 0
    hideMemberMinimapOverlay()
  end
  botServerWindow.Features.Feature1:setOn(config.manaInfo)
  pcall(function() botServerWindow.Features.Feature1:setTooltip("Muestra mana de miembros conectados cuando esten visibles.") end)
  botServerWindow.Features.Feature1.onClick = function(widget)
    config.manaInfo = not config.manaInfo
    widget:setOn(config.manaInfo)
  end
  botServerWindow.Features.Feature2:setOn(config.mwallInfo)
  pcall(function() botServerWindow.Features.Feature2:setTooltip("Comparte Magic Walls detectadas con el canal.") end)
  botServerWindow.Features.Feature2.onClick = function(widget)
    config.mwallInfo = not config.mwallInfo
    widget:setOn(config.mwallInfo)
  end
  botServerWindow.Features.Feature3:setOn(config.vocation)
  pcall(function() botServerWindow.Features.Feature3:setTooltip("Comparte vocacion para Player List y marcas del bot.") end)
  botServerWindow.Features.Feature3.onClick = function(widget)
    config.vocation = not config.vocation
    if config.vocation then
      syncVocation(true)
    end
    widget:setOn(config.vocation)
  end
  botServerWindow.Features.Feature4:setOn(config.outfit)
  pcall(function() botServerWindow.Features.Feature4:setTooltip("Opcion heredada para vocacion por outfit.") end)
  botServerWindow.Features.Feature4.onClick = function(widget)
    config.outfit = not config.outfit
    widget:setOn(config.outfit)
  end
  botServerWindow.Features.Feature5:setOn(config.broadcasts)
  pcall(function() botServerWindow.Features.Feature5:setTooltip("Permite recibir mensajes broadcast del canal.") end)
  botServerWindow.Features.Feature5.onClick = function(widget)
    config.broadcasts = not config.broadcasts
    widget:setOn(config.broadcasts)
  end
  botServerWindow.Features.Feature6:setOn(config.minimapMembers)
  pcall(function() botServerWindow.Features.Feature6:setTooltip("Muestra miembros conectados como puntos temporales en el minimapa.") end)
  botServerWindow.Features.Feature6.onClick = function(widget)
    config.minimapMembers = not config.minimapMembers
    widget:setOn(config.minimapMembers)
    if config.minimapMembers then
      updateMemberMinimapOverlay(true)
    else
      hideMemberMinimapOverlay()
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
      voc = type(message) == "table" and message.voc or nil,
      pos = type(message) == "table" and message.pos or nil
    })
    if type(message) == "table" and message.voc then
      vBot.BotServerMembers[memberName] = message.voc
    end
  end)

  -- mwalls
  BotServer.listen("mwall", function(name, message)
    if not currentBotServerListeners(listenerSocket) then return end
    if config.mwallInfo and type(message) == "table" then
      local pos = message["pos"]
      local duration = tonumber(message["duration"]) or 0
      if pos and duration > 0 then
        pruneMwalls()
        if not config.mwalls[pos] or config.mwalls[pos] < now then
          config.mwalls[pos] = now + duration - 150 -- 150 is latency correction
        end
      end
    end
  end)

  -- mana
  BotServer.listen("mana", function(name, message)
    if not currentBotServerListeners(listenerSocket) then return end
    if config.manaInfo and type(message) == "table" then
      touchMember(name, {mana = message["mana"]})
      local creature = getPlayerByName(name)
      if creature then
        creature:setManaPercent(message["mana"])
      end
    end
  end)

  -- vocation
  BotServer.listen("voc", function(name, message)
    if not currentBotServerListeners(listenerSocket) then return end
    if message == "yes" and config.vocation then
      sendBotServer("voc", player:getVocation())
    else
      touchMember(name, {voc = message})
      vBot.BotServerMembers[name] = message
    end
  end)

  -- broadcast
  BotServer.listen("broadcast", function(name, message)
    if not currentBotServerListeners(listenerSocket) then return end
    if config.broadcasts then
      broadcastMessage(name..": "..message)
    end
  end)

  syncVocation(true)
  publishPresence(true)
end
initBotServerListenFunctions()

function updateStatusText()
  pruneMembers()
  if BotServer._websocket then
    local statusText = "GAME: CONNECTED"
    local statusLevel = "connected"
    if GameBotServerTransport and GameBotServerTransport.getStatus then
      statusText, statusLevel = GameBotServerTransport.getStatus()
    end
    local statusColor = statusLevel == "connected" and '#03AC13' or
      (statusLevel == "waiting" and '#FFF380' or '#E3242B')
    botServerWindow.Data.ServerStatus:setText(statusText)
    botServerWindow.Data.ServerStatus:setColor(statusColor)
    ui.botServer:setColor(statusColor)
    botServerWindow.Data.Participants:setText(getMemberCount())
    botServerWindow.Data.Members:setTooltip(getMembersTooltip())
  else
    botServerWindow.Data.ServerStatus:setText("DISCONNECTED")
    ui.botServer:setColor('#E3242B')
    botServerWindow.Data.ServerStatus:setColor('#E3242B')
    botServerWindow.Data.Participants:setText("-")
  end
end

macro(500, function()
  if config.enabled then
    initBotServerListenFunctions()
    publishPresence()
    syncVocation()
    updateMemberMinimapOverlay()
  else
    hideMemberMinimapOverlay()
  end
end)

macro(1000, function()
  pruneMwalls()
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
    botServerWindow:raise()
    botServerWindow:focus()
end

botServerWindow.closeButton.onClick = function(widget)
    botServerWindow:hide()
end

onAddThing(function(tile, thing)
  if config.enabled and config.mwallInfo then
    if thing:isItem() and thing:getId() == 2129 then
      pruneMwalls()
      local pos = tile:getPosition().x .. "," .. tile:getPosition().y .. "," .. tile:getPosition().z
      if not config.mwalls[pos] or config.mwalls[pos] < now then
        config.mwalls[pos] = now + 20000
        sendBotServer("mwall", {pos=pos, duration=20000})
      end
    end
  end
end)

-- mana
local lastMana = 0
macro(500, function()
  if config.enabled and config.manaInfo then
    if manapercent() ~= lastMana then
      lastMana = manapercent()
      sendBotServer("mana", {mana=lastMana})
    end
  end
end)

-- vocation
syncVocation(true)
publishPresence(true)

addSeparator()
