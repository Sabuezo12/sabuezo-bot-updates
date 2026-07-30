-- BotServer transport over the current game connection.
-- Guild/Party channels work without server changes. Extended Opcode requires
-- a compatible relay on the game server.

GameBotServerTransport = GameBotServerTransport or {}
local transport = GameBotServerTransport

transport.generation = (transport.generation or 0) + 1
local generation = transport.generation

local PACKET_PREFIX = "#SB2#"
local PACKET_VERSION = 2
local RAW_PARTY_OPCODE = 43
local RAW_PARTY_RECORD_SIZE = 37
local RAW_PARTY_MAX_MEMBERS = 32
local MAX_CHAT_PACKET = 240
local CHAT_SEND_INTERVAL = 3000
local MEMBER_TIMEOUT = 35000
local SEEN_TIMEOUT = 60000
local TOPIC_INTERVALS = {
  presence = 3000,
  mana = 3000,
  voc = 10000
}
local COALESCED_TOPICS = {
  presence = true,
  mana = true,
  voc = true
}

local state = {
  active = false,
  socket = nil,
  clientName = "",
  room = "",
  requestedMode = "guild",
  activeMode = "guild",
  opcodeConfirmed = false,
  opcodeAvailable = false,
  listeners = {},
  members = {},
  pending = {},
  seen = {},
  lastTopicSent = {},
  lastChatSent = 0,
  sequence = 0
}
transport.state = state

BotServer = BotServer or {}
if not BotServer._gameTransportOriginal then
  BotServer._gameTransportOriginal = {
    init = BotServer.init,
    send = BotServer.send,
    listen = BotServer.listen,
    terminate = BotServer.terminate,
    resetReconnect = BotServer.resetReconnect,
    url = BotServer.url
  }
end

local function clockMillis()
  if type(now) == "number" then return now end
  if g_clock and g_clock.millis then
    local ok, value = pcall(function() return g_clock.millis() end)
    if ok and type(value) == "number" then return value end
  end
  return os.time() * 1000
end

local function gameOnline()
  if not g_game or not g_game.isOnline then return false end
  local ok, value = pcall(function() return g_game.isOnline() end)
  return ok and value == true
end

local function currentCharacterName()
  local ok, value = pcall(function() return name() end)
  if ok and type(value) == "string" and value ~= "" then return value end

  ok, value = pcall(function() return player:getName() end)
  if ok and type(value) == "string" and value ~= "" then return value end
  return "Unknown"
end

local function normalizedMode(value)
  value = tostring(value or "guild"):lower()
  if value == "extended opcode" or value == "extended" then value = "opcode" end
  if value ~= "guild" and value ~= "party" and value ~= "auto" and value ~= "opcode" then
    value = "guild"
  end
  return value
end

local function getConfig()
  storage.BOTserver = storage.BOTserver or {}
  local config = storage.BOTserver
  config.transportMode = normalizedMode(config.transportMode)
  config.guildChannelId = math.max(0, math.min(65535, tonumber(config.guildChannelId) or 0))
  config.gameChannelId = math.max(0, math.min(65535, tonumber(config.gameChannelId) or 1))
  config.extendedOpcode = math.max(0, math.min(255, tonumber(config.extendedOpcode) or 201))
  return config
end

local function validGeneration()
  return transport.generation == generation
end

local function touchMember(memberName)
  if type(memberName) ~= "string" or memberName == "" then return end
  state.members[memberName] = clockMillis()
end

local function pruneRuntime()
  local current = clockMillis()
  for memberName, seenAt in pairs(state.members) do
    if memberName ~= state.clientName and current - seenAt > MEMBER_TIMEOUT then
      state.members[memberName] = nil
    end
  end
  for packetId, seenAt in pairs(state.seen) do
    if current - seenAt > SEEN_TIMEOUT then
      state.seen[packetId] = nil
    end
  end
end

local function dispatch(topic, sender, message)
  local callbacks = state.listeners[topic]
  if type(callbacks) ~= "table" then return end

  for _, callback in ipairs(callbacks) do
    pcall(callback, sender, message)
  end
end

local function memberList()
  pruneRuntime()
  touchMember(state.clientName)

  local result = {}
  for memberName in pairs(state.members) do
    table.insert(result, memberName)
  end
  table.sort(result)
  return result
end

local function nextPacketId()
  state.sequence = state.sequence + 1
  local safeName = tostring(state.clientName):gsub("[^%w%-_]", "_")
  return safeName .. ":" .. tostring(clockMillis()) .. ":" .. tostring(state.sequence)
end

local function encodePacket(topic, message)
  local envelope = {
    v = PACKET_VERSION,
    r = state.room,
    t = topic,
    d = message,
    n = state.clientName,
    i = nextPacketId()
  }

  local ok, encoded = pcall(function() return json.encode(envelope) end)
  if not ok or type(encoded) ~= "string" then return nil end
  return PACKET_PREFIX .. encoded
end

local function encodeChatPacket(topic, message)
  local packet = encodePacket(topic, message)
  if not packet then return nil end
  if #packet <= MAX_CHAT_PACKET then return packet end
  if topic ~= "broadcast" or type(message) ~= "string" then return nil end

  local shortened = message
  while #shortened > 0 do
    shortened = shortened:sub(1, math.max(0, #shortened - 12))
    packet = encodePacket(topic, shortened)
    if packet and #packet <= MAX_CHAT_PACKET then return packet end
  end
  return nil
end

local function decodePacket(packet)
  if type(packet) ~= "string" or packet:sub(1, #PACKET_PREFIX) ~= PACKET_PREFIX then
    return nil
  end

  local ok, envelope = pcall(function()
    return json.decode(packet:sub(#PACKET_PREFIX + 1))
  end)
  if not ok or type(envelope) ~= "table" then return nil end
  if tonumber(envelope.v) ~= PACKET_VERSION then return nil end
  if tostring(envelope.r or "") ~= state.room then return nil end
  if type(envelope.t) ~= "string" or envelope.t == "" then return nil end
  return envelope
end

local function acceptPacket(packet, authoritativeSender)
  local envelope = decodePacket(packet)
  if not envelope then return nil end

  local packetId = tostring(envelope.i or "")
  if packetId ~= "" and state.seen[packetId] then return envelope end
  if packetId ~= "" then state.seen[packetId] = clockMillis() end

  local sender = authoritativeSender
  if type(sender) ~= "string" or sender == "" then
    sender = tostring(envelope.n or "Unknown")
  end
  touchMember(sender)

  if envelope.t:sub(1, 2) ~= "__" then
    dispatch(envelope.t, sender, envelope.d)
  end
  return envelope
end

local function protocolGame()
  if not g_game or not g_game.getProtocolGame then return nil end
  local ok, protocol = pcall(function() return g_game.getProtocolGame() end)
  if ok then return protocol end
  return nil
end

local function protocolGameClass()
  local protocolClass = ProtocolGame
  if not protocolClass and modules and modules.gamelib then
    protocolClass = modules.gamelib.ProtocolGame
  end
  if not protocolClass then
    local protocol = protocolGame()
    if protocol and
       (type(protocol.registerOpcode) == "function" or
        type(protocol.registerExtendedOpcode) == "function") then
      protocolClass = protocol
    end
  end
  return protocolClass
end

local function chatChannelId(mode)
  local config = getConfig()
  if mode == "party" then return config.gameChannelId end
  return config.guildChannelId
end

local function sendOpcodePacket(packet)
  if not gameOnline() or type(packet) ~= "string" then return false end
  local protocol = protocolGame()
  if not protocol or not protocol.sendExtendedOpcode then return false end

  local opcode = getConfig().extendedOpcode
  local ok = pcall(function()
    protocol:sendExtendedOpcode(opcode, packet)
  end)
  return ok == true
end

local function sendChatPacket(packet)
  if not gameOnline() or type(packet) ~= "string" then return false end
  local channelId = chatChannelId(state.activeMode)

  local ok = false
  if type(sayChannel) == "function" then
    ok = pcall(function() sayChannel(channelId, packet) end)
  elseif g_game and g_game.talkChannel then
    -- Anvard binds talkChannel as (speakType, channelId, message).
    ok = pcall(function() g_game.talkChannel(7, channelId, packet) end)
  end
  if ok then acceptPacket(packet, state.clientName) end
  return ok == true
end

local function flushPendingToOpcode()
  for key, entry in pairs(state.pending) do
    sendOpcodePacket(entry.packet)
    state.pending[key] = nil
  end
end

local function confirmOpcode()
  if state.opcodeConfirmed then return end
  state.opcodeConfirmed = true
  if state.requestedMode == "auto" then
    state.activeMode = "opcode"
    flushPendingToOpcode()
  end
end

local function sendProbeAck()
  local packet = encodePacket("__probe_ack", {ok = true})
  if packet then sendOpcodePacket(packet) end
end

local function handleOpcodePacket(packet)
  local envelope = acceptPacket(packet, nil)
  if not envelope then return end

  confirmOpcode()
  if envelope.t == "__probe" then
    sendProbeAck()
  end
end

local function unregisterOwnedOpcode()
  if not transport.registeredOpcode or not transport.ownsOpcodeRegistration then return end
  local protocolClass = protocolGameClass()
  if protocolClass and type(protocolClass.unregisterExtendedOpcode) == "function" then
    pcall(function()
      protocolClass.unregisterExtendedOpcode(transport.registeredOpcode)
    end)
  end
  transport.registeredOpcode = nil
  transport.ownsOpcodeRegistration = false
end

local function registerOpcode()
  local opcode = getConfig().extendedOpcode
  unregisterOwnedOpcode()
  local protocolClass = protocolGameClass()
  if not protocolClass or type(protocolClass.registerExtendedOpcode) ~= "function" then
    return false
  end

  local ok = pcall(function()
    protocolClass.registerExtendedOpcode(opcode, function(protocol, receivedOpcode, buffer)
      if not validGeneration() or not state.active then return end
      if tonumber(receivedOpcode) ~= opcode then return end
      handleOpcodePacket(tostring(buffer or ""))
    end)
  end)
  if ok then
    transport.registeredOpcode = opcode
    transport.ownsOpcodeRegistration = true
  end
  return ok == true
end

local function consumeRawPartyPacket(protocol, msg)
  -- Anvard's game server sends opcode 43 with party status records followed
  -- by a compact position/name list. The stock protocol 860 parser does not
  -- know this custom packet, so it must be consumed here to keep the stream
  -- aligned.
  if not msg or msg:getUnreadSize() < 10 then return end

  msg:getU32()
  msg:getU32()
  msg:getU8()

  local statusCount = msg:getU8()
  if statusCount > RAW_PARTY_MAX_MEMBERS or
     msg:getUnreadSize() < statusCount * RAW_PARTY_RECORD_SIZE + 2 then
    return
  end
  msg:skipBytes(statusCount * RAW_PARTY_RECORD_SIZE)

  msg:getU8()
  local nameCount = msg:getU8()
  if nameCount > RAW_PARTY_MAX_MEMBERS then return end

  for _ = 1, nameCount do
    if msg:getUnreadSize() < 6 then return end
    msg:getU32()

    local nameLength = msg:peekU16()
    if nameLength > 64 or msg:getUnreadSize() < nameLength + 2 then return end
    local memberName = msg:getString()
    if state.active and state.activeMode == "party" then touchMember(memberName) end
  end
end

local function registerRawPartyOpcode()
  local protocolClass = protocolGameClass()
  if not protocolClass or type(protocolClass.registerOpcode) ~= "function" then
    return false
  end

  if transport.registeredRawPartyOpcode and transport.ownsRawPartyOpcode and
     type(protocolClass.unregisterOpcode) == "function" then
    pcall(function()
      protocolClass.unregisterOpcode(transport.registeredRawPartyOpcode)
    end)
    transport.registeredRawPartyOpcode = nil
    transport.ownsRawPartyOpcode = false
  end

  local ok = pcall(function()
    protocolClass.registerOpcode(RAW_PARTY_OPCODE, consumeRawPartyPacket)
  end)
  if ok then
    transport.registeredRawPartyOpcode = RAW_PARTY_OPCODE
    transport.ownsRawPartyOpcode = true
  end
  return ok == true
end

local function installConsolePacketFilter()
  local gameConsole = modules and modules.game_console
  if not gameConsole or type(gameConsole.addTabText) ~= "function" then
    return false
  end

  local previousWrapper = transport.consoleTalkFilter
  local previousOriginal = transport.consoleOriginalOnTalk
  if type(previousWrapper) == "function" then
    if gameConsole.addTabText == previousWrapper and type(previousOriginal) == "function" then
      gameConsole.addTabText = previousOriginal
    end
  end

  local originalAddTabText = gameConsole.addTabText
  local filteredAddTabText = function(text, speaktype, tab, creatureName)
    if type(text) == "string" and
       text:find(PACKET_PREFIX, 1, true) then
      return
    end
    return originalAddTabText(text, speaktype, tab, creatureName)
  end

  gameConsole.addTabText = filteredAddTabText
  transport.consoleOriginalOnTalk = originalAddTabText
  transport.consoleTalkFilter = filteredAddTabText
  return true
end

local function prepareChatChannel(mode)
  if not gameOnline() then return end
  local channelId = chatChannelId(mode)

  local function closePartyChannel()
    if mode ~= "guild" or not g_game.leaveChannel then return end
    local partyChannelId = chatChannelId("party")
    if partyChannelId ~= channelId then
      pcall(function() g_game.leaveChannel(partyChannelId) end)
    end
  end

  closePartyChannel()
  if g_game.joinChannel then
    pcall(function() g_game.joinChannel(channelId) end)
  end
  if mode == "guild" and type(schedule) == "function" then
    schedule(1000, function()
      if validGeneration() and state.active and state.activeMode == "guild" then
        closePartyChannel()
      end
    end)
  end
end

local function sendProbe()
  if not state.active or not state.opcodeAvailable then return false end
  local packet = encodePacket("__probe", {name = state.clientName})
  if not packet then return false end
  return sendOpcodePacket(packet)
end

local function pendingKey(topic, packet)
  if COALESCED_TOPICS[topic] then return topic end
  local packetId = tostring(packet):match([["i":"([^"]+)"]])
  if packetId then return topic .. ":" .. packetId end
  return topic .. ":" .. nextPacketId()
end

local function queueChatPacket(topic, packet)
  local current = clockMillis()
  local interval = TOPIC_INTERVALS[topic] or 0
  local lastSent = state.lastTopicSent[topic]
  local dueAt = lastSent and math.max(current, lastSent + interval) or current
  local priority = (topic == "broadcast" or topic == "mwall") and 0 or 1

  state.pending[pendingKey(topic, packet)] = {
    topic = topic,
    packet = packet,
    dueAt = dueAt,
    priority = priority
  }
end

local function flushChatQueue()
  if not state.active or
     (state.activeMode ~= "guild" and state.activeMode ~= "party") then
    return
  end
  local current = clockMillis()
  if current - state.lastChatSent < CHAT_SEND_INTERVAL then return end

  local selectedKey = nil
  local selected = nil
  for key, entry in pairs(state.pending) do
    if entry.dueAt <= current and
       (not selected or entry.priority < selected.priority or
        (entry.priority == selected.priority and entry.dueAt < selected.dueAt)) then
      selectedKey = key
      selected = entry
    end
  end
  if not selected then return end

  if sendChatPacket(selected.packet) then
    state.lastChatSent = current
    state.lastTopicSent[selected.topic] = current
  end
  state.pending[selectedKey] = nil
end

function transport.init(clientName, room)
  unregisterOwnedOpcode()

  state.active = true
  state.clientName = tostring(clientName or currentCharacterName())
  state.room = tostring(room or "")
  state.requestedMode = getConfig().transportMode
  if state.requestedMode == "opcode" then
    state.activeMode = "opcode"
  elseif state.requestedMode == "party" then
    state.activeMode = "party"
  else
    state.activeMode = "guild"
  end
  state.opcodeConfirmed = false
  state.opcodeAvailable = false
  state.listeners = {}
  state.members = {}
  state.pending = {}
  state.seen = {}
  state.lastTopicSent = {}
  state.lastChatSent = 0
  state.socket = {gameTransport = true, generation = generation}
  BotServer._websocket = state.socket
  touchMember(state.clientName)

  if state.requestedMode == "guild" or state.requestedMode == "auto" then
    prepareChatChannel("guild")
  elseif state.requestedMode == "party" then
    prepareChatChannel("party")
  end
  if state.requestedMode == "opcode" or state.requestedMode == "auto" then
    state.opcodeAvailable = registerOpcode()
    if state.opcodeAvailable then
      schedule(500, function()
        if validGeneration() and state.active then sendProbe() end
      end)
    elseif state.requestedMode == "opcode" then
      state.activeMode = "opcode"
    end
  end
  return true
end

function transport.terminate()
  state.active = false
  state.pending = {}
  state.listeners = {}
  state.socket = nil
  BotServer._websocket = nil
  unregisterOwnedOpcode()
end

function transport.listen(topic, callback)
  if type(topic) ~= "string" or type(callback) ~= "function" then return false end
  state.listeners[topic] = state.listeners[topic] or {}
  table.insert(state.listeners[topic], callback)
  return true
end

function transport.send(topic, message)
  if not state.active or type(topic) ~= "string" then return false end
  if topic == "list" then
    dispatch("list", state.clientName, memberList())
    return true
  end

  -- Presence already carries vocation, so chat transports do not need
  -- separate vocation packets.
  if topic == "voc" and state.activeMode ~= "opcode" then
    return true
  end

  if state.activeMode == "opcode" then
    local packet = encodePacket(topic, message)
    return packet and sendOpcodePacket(packet) or false
  end

  local packet = encodeChatPacket(topic, message)
  if not packet then return false end
  queueChatPacket(topic, packet)
  return true
end

function transport.setRoom(room)
  state.room = tostring(room or "")
  state.members = {}
  state.pending = {}
  state.seen = {}
  touchMember(state.clientName)
  if state.opcodeAvailable then sendProbe() end
end

function transport.getStatus()
  if not state.active then return "DISCONNECTED", "error" end
  if not gameOnline() then return "GAME: OFFLINE", "waiting" end

  if state.requestedMode == "opcode" then
    if not state.opcodeAvailable then return "OPCODE: UNAVAILABLE", "error" end
    if not state.opcodeConfirmed then return "OPCODE: WAITING", "waiting" end
    return "GAME: OPCODE", "connected"
  end
  if state.requestedMode == "auto" and state.activeMode == "opcode" then
    return "GAME: OPCODE", "connected"
  end
  if state.requestedMode == "auto" and not state.opcodeAvailable then
    return "GAME: GUILD", "connected"
  end
  if state.requestedMode == "auto" then
    return "GAME: GUILD/AUTO", "connected"
  end
  if state.requestedMode == "guild" then return "GAME: GUILD", "connected" end
  return "GAME: PARTY", "connected"
end

function transport.restart()
  local wasActive = state.active
  local clientName = state.clientName ~= "" and state.clientName or currentCharacterName()
  local room = state.room
  transport.terminate()
  if wasActive then transport.init(clientName, room) end
end

BotServer.init = transport.init
BotServer.terminate = transport.terminate
BotServer.listen = transport.listen
BotServer.send = transport.send
BotServer.resetReconnect = function() end
BotServer.url = nil

getConfig().rawPartyOpcodeInstalled = registerRawPartyOpcode()
getConfig().consoleFilterInstalled = installConsolePacketFilter()

if type(onTalk) == "function" then
  onTalk(function(sender, level, mode, text, channelId)
    if not validGeneration() or not state.active then return end
    if state.activeMode ~= "guild" and state.activeMode ~= "party" then return end
    if tonumber(channelId) ~= chatChannelId(state.activeMode) then return end
    acceptPacket(text, sender)
  end)
end

macro(50, function()
  if not validGeneration() then return end
  pruneRuntime()
  flushChatQueue()
end)
