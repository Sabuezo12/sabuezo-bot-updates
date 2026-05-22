setDefaultTab("Main")
local regex = [["(.*?)"]]
local panelName = "BOTserver"
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
  broadcasts = true
}
end

local config = storage[panelName]
config.enabled = config.enabled == true
if config.manaInfo == nil then config.manaInfo = true end
if config.mwallInfo == nil then config.mwallInfo = true end
if config.vocation == nil then config.vocation = true end
if config.outfit == nil then config.outfit = false end
if config.broadcasts == nil then config.broadcasts = true end
config.mwalls = {}

BotServer._rodMasterMainGeneration = (BotServer._rodMasterMainGeneration or 0) + 1
local botServerListenGeneration = BotServer._rodMasterMainGeneration
local botServerListenSocket = nil
local lastVocationSync = 0
local serverCount = {}
local ServerMembers = nil
local members = {}
local lastPresenceSync = 0
local MEMBER_TIMEOUT = 30000

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

local function touchMember(memberName)
  if type(memberName) ~= "string" or memberName == "" then return end
  members[memberName] = now or 0
end

local function pruneMembers()
  local currentTime = now or 0
  for memberName, lastSeen in pairs(members) do
    if currentTime - lastSeen > MEMBER_TIMEOUT then
      members[memberName] = nil
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
    table.insert(names, memberName)
  end
  table.sort(names)
  return table.concat(names, "\n")
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
  return ok
end

local function publishPresence(force)
  if not config.enabled or not BotServer._websocket then return end
  if not force and now and now - lastPresenceSync < 5000 then return end

  local selfName = getSelfName()
  lastPresenceSync = now or 0
  touchMember(selfName)
  sendBotServer("presence", {name = selfName, voc = player:getVocation()})
end

local function syncVocation(force)
  if not config.vocation or not BotServer._websocket then return end
  if not force and now and now - lastVocationSync < 10000 then return end

  lastVocationSync = now or 0
  sendBotServer("voc", player:getVocation())
  sendBotServer("voc", "yes")
end

if not storage.BotServerChannel then
  math.randomseed(os.time())
  storage.BotServerChannel = tostring(math.random(1000000000000,9999999999999))
end

local channel = tostring(storage.BotServerChannel)
if config.enabled then
  BotServer.init(name(), channel)
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
      botServerWindow.Data.ServerStatus:setText("CONNECTING...")
      ui.botServer:setColor('#FFF380')
      botServerWindow.Data.ServerStatus:setColor('#FFF380')
    else
      if BotServer._websocket then
        BotServer.terminate()
      end
	  BotServer.resetReconnect()
      botServerWindow.Data.ServerStatus:setText("DISCONNECTED")
      ui.botServer:setColor('#E3242B')
      botServerWindow.Data.ServerStatus:setColor('#E3242B')
      botServerWindow.Data.Participants:setText("-")
      botServerWindow.Data.Members:setTooltip('')
      ServerMembers = {}
      serverCount = {}
      members = {}
      lastPresenceSync = 0
    end
    initBotServerListenFunctions()
    publishPresence(true)
    schedule(2000, updateStatusText)
  end

  botServerWindow.Data.Channel:setText(storage.BotServerChannel)
  botServerWindow.Data.Channel.onTextChange = function(widget, text)
    storage.BotServerChannel = text
  end
  botServerWindow.Data.Random.onClick = function(widget)
    storage.BotServerChannel = tostring(math.random(1000000000000,9999999999999))
    botServerWindow.Data.Channel:setText(storage.BotServerChannel)
  end
  botServerWindow.Features.Feature1:setOn(config.manaInfo)
  botServerWindow.Features.Feature1.onClick = function(widget)
    config.manaInfo = not config.manaInfo
    widget:setOn(config.manaInfo)
  end
  botServerWindow.Features.Feature2:setOn(config.mwallInfo)
  botServerWindow.Features.Feature2.onClick = function(widget)
    config.mwallInfo = not config.mwallInfo
    widget:setOn(config.mwallInfo)
  end
  botServerWindow.Features.Feature3:setOn(config.vocation)
  botServerWindow.Features.Feature3.onClick = function(widget)
    config.vocation = not config.vocation
    if config.vocation then
      syncVocation(true)
    end
    widget:setOn(config.vocation)
  end
  botServerWindow.Features.Feature4:setOn(config.outfit)
  botServerWindow.Features.Feature4.onClick = function(widget)
    config.outfit = not config.outfit
    widget:setOn(config.outfit)
  end
  botServerWindow.Features.Feature5:setOn(config.broadcasts)
  botServerWindow.Features.Feature5.onClick = function(widget)
    config.broadcasts = not config.broadcasts
    widget:setOn(config.broadcasts)
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

    touchMember(memberName)
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
    botServerWindow.Data.ServerStatus:setText("CONNECTED")
    botServerWindow.Data.ServerStatus:setColor('#03AC13')
    ui.botServer:setColor('#03AC13')
    botServerWindow.Data.Participants:setText(getMemberCount())
    botServerWindow.Data.Members:setTooltip(getMembersTooltip())
  else
    if config.enabled then
      botServerWindow.Data.ServerStatus:setText("CONNECTING...")
      ui.botServer:setColor('#FFF380')
      botServerWindow.Data.ServerStatus:setColor('#FFF380')
    else
      botServerWindow.Data.ServerStatus:setText("DISCONNECTED")
      ui.botServer:setColor('#E3242B')
      botServerWindow.Data.ServerStatus:setColor('#E3242B')
    end
    botServerWindow.Data.Participants:setText("-")
  end
end

macro(500, function()
  if config.enabled and BotServer._websocket then
    initBotServerListenFunctions()
    publishPresence()
    syncVocation()
  end
end)

macro(1000, function()
  pruneMwalls()
  pruneMembers()
  if config.enabled and BotServer._websocket then
    initBotServerListenFunctions()
    publishPresence(true)
    sendBotServer("list")
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
  if config.mwallInfo and BotServer._websocket then
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
  if config.manaInfo and BotServer._websocket then
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
