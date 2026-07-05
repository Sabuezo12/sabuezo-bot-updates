setDefaultTab("Main")
local regex = [["(.*?)"]]
local panelName = "BOTserver"
local DEFAULT_BOTSERVER_CHANNEL = "Slegna1324"
local BOTSERVER_DEFAULTS_VERSION = 2
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
if storage.BotServerDefaultsVersion ~= BOTSERVER_DEFAULTS_VERSION then
  storage.BotServerChannel = DEFAULT_BOTSERVER_CHANNEL
  config.enabled = true
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
local MEMBER_TIMEOUT_SECONDS = 30
local LOCAL_MESSAGE_TTL_SECONDS = 45
local LOCAL_BUS_ROOT = "/bot/_sabuezo_botserver"
local clientId = nil
local localMessageSeq = 0
local seenLocalBroadcasts = {}
local seenLocalMwalls = {}

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

local function wallTime()
  return os.time()
end

local function safeFileName(value)
  value = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
  value = value:gsub("[^%w%-_]", "_")
  if value == "" then value = "default" end
  return value
end

local function ensureDir(path)
  local ok, exists = pcall(function() return g_resources.directoryExists(path) end)
  if ok and exists then return true end
  return pcall(function() g_resources.makeDir(path) end)
end

local function getLocalBusBase()
  local channelName = safeFileName(storage.BotServerChannel or "default")
  ensureDir(LOCAL_BUS_ROOT)
  local channelPath = LOCAL_BUS_ROOT .. "/" .. channelName
  ensureDir(channelPath)
  ensureDir(channelPath .. "/members")
  ensureDir(channelPath .. "/broadcasts")
  ensureDir(channelPath .. "/mwalls")
  return channelPath
end

local function readLocalJson(path)
  local ok, exists = pcall(function() return g_resources.fileExists(path) end)
  if not ok or not exists then return nil end

  local readOk, contents = pcall(function() return g_resources.readFileContents(path) end)
  if not readOk or not contents or contents == "" then return nil end

  local decodeOk, data = pcall(function() return json.decode(contents) end)
  if decodeOk and type(data) == "table" then return data end
  return nil
end

local function writeLocalJson(path, data)
  local encodeOk, contents = pcall(function() return json.encode(data) end)
  if not encodeOk or not contents then return false end

  local writeOk = pcall(function() g_resources.writeFileContents(path, contents) end)
  return writeOk == true
end

local function deleteLocalFile(path)
  pcall(function()
    if g_resources.deleteFile then
      g_resources.deleteFile(path)
    end
  end)
end

local function localMessageId(topic)
  localMessageSeq = localMessageSeq + 1
  return safeFileName((clientId or getSelfName()) .. "_" .. topic .. "_" .. tostring(wallTime()) .. "_" .. tostring(now or 0) .. "_" .. tostring(localMessageSeq))
end

local function writeLocalPresence()
  if not config.enabled then return false end

  local base = getLocalBusBase()
  local memberPath = base .. "/members/" .. safeFileName(clientId or getSelfName()) .. ".json"
  local mana = 0
  local ok, result = pcall(function() return manapercent() end)
  if ok and result then mana = result end

  return writeLocalJson(memberPath, {
    clientId = clientId,
    name = getSelfName(),
    voc = player:getVocation(),
    mana = mana,
    time = wallTime()
  })
end

local function readLocalMembers()
  if not config.enabled then return end

  local base = getLocalBusBase()
  local ok, files = pcall(function()
    return g_resources.listDirectoryFiles(base .. "/members", false, false)
  end)
  if not ok or type(files) ~= "table" then return end

  local currentTime = wallTime()
  for _, file in ipairs(files) do
    local path = base .. "/members/" .. file
    local data = readLocalJson(path)
    local messageTime = type(data) == "table" and tonumber(data.time) or nil
    if type(data) == "table" and messageTime and currentTime - messageTime <= MEMBER_TIMEOUT_SECONDS then
      local memberName = data.name
      if type(memberName) == "string" and memberName ~= "" then
        touchMember(memberName)
        if data.voc then
          vBot.BotServerMembers[memberName] = data.voc
        end
        if config.manaInfo and data.mana then
          local creature = getPlayerByName(memberName)
          if creature then
            pcall(function() creature:setManaPercent(data.mana) end)
          end
        end
      end
    elseif messageTime and currentTime - messageTime > MEMBER_TIMEOUT_SECONDS * 3 then
      deleteLocalFile(path)
    end
  end
end

local function writeLocalBroadcast(message)
  if not config.enabled then return false end

  local base = getLocalBusBase()
  local id = localMessageId("broadcast")
  return writeLocalJson(base .. "/broadcasts/" .. id .. ".json", {
    id = id,
    clientId = clientId,
    name = getSelfName(),
    message = tostring(message or ""),
    time = wallTime()
  })
end

local function processLocalBroadcasts()
  if not config.enabled then return end

  local base = getLocalBusBase()
  local ok, files = pcall(function()
    return g_resources.listDirectoryFiles(base .. "/broadcasts", false, false)
  end)
  if not ok or type(files) ~= "table" then return end

  local currentTime = wallTime()
  for _, file in ipairs(files) do
    local path = base .. "/broadcasts/" .. file
    local data = readLocalJson(path)
    local id = data and data.id or file
    local messageTime = type(data) == "table" and tonumber(data.time) or nil
    if type(data) == "table" and messageTime and currentTime - messageTime <= LOCAL_MESSAGE_TTL_SECONDS then
      if data.clientId ~= clientId and not seenLocalBroadcasts[id] then
        seenLocalBroadcasts[id] = true
        if config.broadcasts and data.message and data.message ~= "" then
          broadcastMessage(tostring(data.name or "BotServer") .. ": " .. tostring(data.message))
        end
      end
    elseif messageTime and currentTime - messageTime > LOCAL_MESSAGE_TTL_SECONDS then
      deleteLocalFile(path)
    end
  end
end

local function writeLocalMwall(message)
  if not config.enabled or type(message) ~= "table" or not message.pos then return false end

  local base = getLocalBusBase()
  local id = localMessageId("mwall")
  return writeLocalJson(base .. "/mwalls/" .. id .. ".json", {
    id = id,
    clientId = clientId,
    name = getSelfName(),
    pos = message.pos,
    duration = tonumber(message.duration) or 0,
    time = wallTime()
  })
end

local function processLocalMwalls()
  if not config.enabled or not config.mwallInfo then return end

  local base = getLocalBusBase()
  local ok, files = pcall(function()
    return g_resources.listDirectoryFiles(base .. "/mwalls", false, false)
  end)
  if not ok or type(files) ~= "table" then return end

  local currentTime = wallTime()
  for _, file in ipairs(files) do
    local path = base .. "/mwalls/" .. file
    local data = readLocalJson(path)
    local id = data and data.id or file
    local messageTime = type(data) == "table" and tonumber(data.time) or nil
    if type(data) == "table" and messageTime and currentTime - messageTime <= LOCAL_MESSAGE_TTL_SECONDS then
      if data.clientId ~= clientId and not seenLocalMwalls[id] and data.pos and data.duration then
        seenLocalMwalls[id] = true
        local duration = tonumber(data.duration) or 0
        if duration > 0 and (not config.mwalls[data.pos] or config.mwalls[data.pos] < now) then
          config.mwalls[data.pos] = now + duration - 150
        end
      end
    elseif messageTime and currentTime - messageTime > LOCAL_MESSAGE_TTL_SECONDS then
      deleteLocalFile(path)
    end
  end
end

local function processLocalBus()
  if not config.enabled then return end
  readLocalMembers()
  processLocalBroadcasts()
  processLocalMwalls()
end

local function pruneMwalls()
  for pos, expires in pairs(config.mwalls) do
    if not expires or expires < now then
      config.mwalls[pos] = nil
    end
  end
end

local function sendBotServer(topic, message)
  local localOk = false
  if topic == "presence" or topic == "voc" or topic == "mana" then
    localOk = writeLocalPresence()
  elseif topic == "broadcast" then
    localOk = writeLocalBroadcast(message)
  elseif topic == "mwall" then
    localOk = writeLocalMwall(message)
  end

  if not BotServer._websocket then return localOk end

  local ok = pcall(function()
    if message == nil then
      BotServer.send(topic)
    else
      BotServer.send(topic, message)
    end
  end)
  return ok or localOk
end

local function publishPresence(force)
  if not config.enabled then return end
  if not force and now and now - lastPresenceSync < 5000 then return end

  local selfName = getSelfName()
  lastPresenceSync = now or 0
  touchMember(selfName)
  sendBotServer("presence", {name = selfName, voc = player:getVocation()})
end

local function syncVocation(force)
  if not config.enabled or not config.vocation then return end
  if not force and now and now - lastVocationSync < 10000 then return end

  lastVocationSync = now or 0
  sendBotServer("voc", player:getVocation())
  sendBotServer("voc", "yes")
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
    members = {}
    seenLocalBroadcasts = {}
    seenLocalMwalls = {}
    lastPresenceSync = 0
  end
  botServerWindow.Data.Random.onClick = function(widget)
    storage.BotServerChannel = tostring(math.random(1000000000000,9999999999999))
    botServerWindow.Data.Channel:setText(storage.BotServerChannel)
    members = {}
    seenLocalBroadcasts = {}
    seenLocalMwalls = {}
    lastPresenceSync = 0
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
      botServerWindow.Data.ServerStatus:setText("LOCAL BUS")
      ui.botServer:setColor('#FFF380')
      botServerWindow.Data.ServerStatus:setColor('#FFF380')
      botServerWindow.Data.Participants:setText(getMemberCount())
      botServerWindow.Data.Members:setTooltip(getMembersTooltip())
    else
      botServerWindow.Data.ServerStatus:setText("DISCONNECTED")
      ui.botServer:setColor('#E3242B')
      botServerWindow.Data.ServerStatus:setColor('#E3242B')
      botServerWindow.Data.Participants:setText("-")
    end
  end
end

macro(500, function()
  if config.enabled then
    initBotServerListenFunctions()
    publishPresence()
    syncVocation()
    processLocalBus()
  end
end)

macro(1000, function()
  pruneMwalls()
  pruneMembers()
  if config.enabled then
    initBotServerListenFunctions()
    publishPresence(true)
    processLocalBus()
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
