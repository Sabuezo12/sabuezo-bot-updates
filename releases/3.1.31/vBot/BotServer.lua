setDefaultTab("Main")
if not HelperPartyContext then dofile("/vBot/party_context.lua") end
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

    HelperThemeLabel
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
  manaInfo = false,
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
-- Network economy: HP/mana remain local to each character.
config.manaInfo = false
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
local lastPresenceSync = nil
local lastPresenceVocation, lastPresenceLevel = nil, nil
local presenceReplies = {}
local helloListSocket = nil
local presenceSocket = nil
local lastMemberListSync = nil
-- Change 234: presence carries vocation and level. It goes out when the bot connects (asking
-- the others for theirs), when the level or vocation changes (at most every 30 s) and every
-- 10 min; never because the character moved. Exiva and Follow ask for positions when they
-- need them and the party shows its own members.
local PRESENCE_HEARTBEAT = 600000
local PRESENCE_MIN_GAP = 30000
local PRESENCE_REPLY_GAP = 10000
-- The member list: every 30 s, or every 5 min when the server announces joins and leaves.
local MEMBER_LIST_INTERVAL = 30000
local MEMBER_LIST_INTERVAL_EVENTS = 300000
-- Allow two missed list refreshes before a silent member is dropped.
local MEMBER_TIMEOUT = 90000
local MEMBER_TIMEOUT_EVENTS = 900000
local MEMBER_POSITION_TIMEOUT = 90000
BotServer.networkSettings = {presenceHeartbeat = PRESENCE_HEARTBEAT, memberTimeout = MEMBER_TIMEOUT,
  positionTimeout = MEMBER_POSITION_TIMEOUT, shareStats = false, nativePartyPositions = true}
-- True when the server announces joins and leaves (it answered the _cfg request).
local function memberEvents()
  local transport = GameBotServerTransport
  if not transport or type(transport.serverFeatures) ~= "function" then return false end
  local ok, features = pcall(transport.serverFeatures)
  return ok and type(features) == "table" and features.members == true
end
local MAX_MINIMAP_MARKERS = 16
local MINIMAP_MARKER_COLOR = "#ffffffff"
local MINIMAP_MARKER_SIZE = 13
local MINIMAP_MARKER_IMAGE = (type(configDir) == "string" and configDir or "/bot/pruebas") ..
  "/vBot/map_markers/member-diamond.png"
local nativeMemberPin = "/game_cyclopedia/images/icon-map-other_player.png"
if g_resources.fileExists(nativeMemberPin) then
  MINIMAP_MARKER_IMAGE = nativeMemberPin
  MINIMAP_MARKER_SIZE = 16
end
function BotServer.getMemberMapIcon()
  return MINIMAP_MARKER_IMAGE, MINIMAP_MARKER_SIZE
end
local MINIMAP_OVERLAY_UPDATE = 300
local clientId = nil
local minimapOverlay = {
  widget = nil,
  parent = nil,
  markers = {},
  nextUpdateAt = 0
}
local cyclopediaMinimapNextUpdateAt = 0

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
  local x, y, z = tonumber(pos.x), tonumber(pos.y), tonumber(pos.z)
  if x ~= x or y ~= y or z ~= z or x % 1 ~= 0 or y % 1 ~= 0 or z % 1 ~= 0 or
      x < 0 or x > 65535 or y < 0 or y > 65535 or z < 0 or z > 15 then return nil end
  return {x = x, y = y, z = z}
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
  if not vBot.BotServerMembers[memberName] then
    vBot.BotServerMembers[memberName] = true
    CachedFriends = {}
    CachedEnemies = {}
  end

  if type(info) == "table" then
    local current = memberInfo[memberName] or {}
    current.name = memberName
    current.clientId = info.clientId or current.clientId
    local pos = copyPosition(info.pos)
    if pos then current.pos, current.positionSeenAt = pos, now or 0 end
    if type(info.voc) == "string" and info.voc ~= "" and #info.voc <= 24 then current.vocation = info.voc end
    local lvl = tonumber(info.lvl)
    if lvl and lvl >= 1 and lvl <= 100000 and lvl % 1 == 0 then current.level = lvl end
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

-- Used by exiva discovery: a fresh reply carries the observer's current position.
BotServer.observeMemberPosition = function(memberName, pos)
  if not config.enabled or not BotServer._websocket then return false end
  pos = copyPosition(pos)
  if not pos then return false end
  touchMember(memberName, {pos = pos})
  return true
end

local function pruneMembers()
  local currentTime = now or 0
  local timeout = memberEvents() and MEMBER_TIMEOUT_EVENTS or MEMBER_TIMEOUT
  for memberName, lastSeen in pairs(members) do
    if currentTime - lastSeen > timeout then
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
    if info and info.vocation then
      text = text .. " (" .. info.vocation .. (info.level and (" " .. info.level) or "") .. ")"
    elseif info and info.level then
      text = text .. " (nivel " .. info.level .. ")"
    end
    if info and hasPosition(info.pos) then
      text = text .. " - " .. positionKey(info.pos)
    end
    table.insert(names, text)
  end
  table.sort(names)
  return table.concat(names, "\n")
end

BotServer.isNativePartyMember = function(name)
  return HelperPartyContext and HelperPartyContext.isMember(name) == true
end

BotServer.getMemberSnapshot = function()
  pruneMembers()
  local snapshot = {}
  local events = memberEvents()
  for memberName, info in pairs(memberInfo) do
    -- Reuse the server's native party tracking for connected Navi members.
    -- Exiva/Follow still receive a position while ordinary movement broadcasts rest.
    local nativePos, nativeAt
    if HelperPartyContext then nativePos, nativeAt = HelperPartyContext.getPosition(memberName) end
    local useNative = nativePos and nativeAt and nativeAt >= (info.positionSeenAt or -1)
    snapshot[memberName] = {
      name = memberName, clientId = info.clientId,
      positionSeenAt = useNative and nativeAt or info.positionSeenAt,
      pos = useNative and nativePos or copyPosition(info.pos), positionSource = useNative and "party" or "navi",
      -- Still in the room: with the server's notices that is "now"; otherwise the last
      -- message or member list that named him.
      lastSeen = events and members[memberName] and (now or 0) or
        math.max(tonumber(info.lastSeen) or 0, tonumber(members[memberName]) or 0),
      wallTime = info.wallTime, vocation = info.vocation, level = info.level
    }
  end
  local selfName = getSelfName()
  snapshot[selfName] = snapshot[selfName] or {name = selfName}
  snapshot[selfName].pos = getSelfPosition() or snapshot[selfName].pos
  if config.enabled and BotServer._websocket then
    snapshot[selfName].lastSeen = now or 0
    snapshot[selfName].positionSeenAt = now or 0
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
  if BotServer._rodMasterMainGeneration ~= botServerListenGeneration or not BotServer._websocket then return false end

  local ok, result = pcall(function() return BotServer.send(topic, message) end)
  return ok and result ~= false
end

-- Exeta Res in a party: an ally tells the knight which monster is hitting it (party_threat.lua).
BotServer.announceThreat=function(message)
  if not currentBotServerListeners(BotServer._websocket) then return false end
  return sendBotServer('helperPartyThreat',message)
end

BotServer.announceFollowSupplies=function(visit,npc,position,shop)
  if not currentBotServerListeners(BotServer._websocket) then return false end
  return sendBotServer('helperFollowSupplies',{v=1,id=visit,npc=npc,pos=copyPosition(position),shop=shop})
end

-- Change 113: the leader used an object (Ctrl+Shift+right click); followers use it too.
BotServer.announceFollowUse=function(id,position,item)
  if not config.enabled or not currentBotServerListeners(BotServer._websocket) then return false end
  return sendBotServer('helperFollowUse',{v=1,id=id,pos=copyPosition(position),item=item})
end

-- FOLLOW ROUTE SERVICE: on-demand only; ordinary presence traffic stays small.
local followRoute={points={},links={},serial=0,nextRequest=0,replies={},socket=nil}
local FOLLOW_JUMP_TTL=120000
-- While searching, a follower asks every 600 ms and the leader answers each
-- follower at most every 450 ms (it was 2 s and 1.5 s: stale positions).
local FOLLOW_REQUEST_INTERVAL,FOLLOW_REPLY_INTERVAL,FOLLOW_REPLY_SERIALS=600,450,8
BotServer.FollowRoute=followRoute
-- Leader state for followers (vBot/follow_state.lua): pz, refill trip, route waypoint.
if not HelperFollowState then pcall(dofile,'/vBot/follow_state.lua') end
function followRoute.collectState()
  if not HelperFollowState then return nil end
  local ok,state=pcall(HelperFollowState.collect);if ok then return state end
end
function followRoute.storeState(sender,value)
  if not HelperFollowState or not memberInfo[sender] then return end
  local ok,state=pcall(HelperFollowState.read,value)
  if ok and state then memberInfo[sender].followState=state;memberInfo[sender].followStateAt=now or 0 end
end
function followRoute.record(pos)
  pos=copyPosition(pos);if not pos then return end
  local points=followRoute.points;local b=points[#points];local a=points[#points-1]
  if b and positionKey(b)==positionKey(pos) then return end
  if b then
    local span=math.max(math.abs(b.x-pos.x),math.abs(b.y-pos.y))
    if b.z~=pos.z and span<=8 then
      followRoute.links[#followRoute.links+1]={from=copyPosition(b),to=copyPosition(pos)}
      if #followRoute.links>32 then table.remove(followRoute.links,1) end
    elseif span>8 then
      followRoute.jumpSequence=(followRoute.jumpSequence or 0)+1
      followRoute.jump={from=copyPosition(b),to=copyPosition(pos),at=now or 0,sequence=followRoute.jumpSequence}
      -- Change 113: the city of the NPC trip that caused this jump, if any.
      local intent=ComboFollowTravel and type(ComboFollowTravel.intentFor)=='function' and
        ComboFollowTravel.intentFor(b,now or 0)
      if type(intent)=='table' then followRoute.jump.dest=intent.destination;followRoute.jump.npc=intent.npc end
    end
  end
  local function direction(from,to)
    local dx,dy=to.x-from.x,to.y-from.y
    return dx==0 and 0 or dx>0 and 1 or -1,dy==0 and 0 or dy>0 and 1 or -1
  end
  if a and a.z==b.z and b.z==pos.z then
    local ax,ay=direction(a,b);local bx,by=direction(b,pos)
    local contiguous=math.max(math.abs(b.x-pos.x),math.abs(b.y-pos.y))==1
    local short=math.max(math.abs(a.x-pos.x),math.abs(a.y-pos.y))<=6
    if contiguous and short and ax==bx and ay==by then points[#points]=pos;return end
  end
  points[#points+1]=pos
  if #points>48 then table.remove(points,1) end
end
function followRoute.current(socket)
  return socket==followRoute.socket and currentBotServerListeners(socket)
end
-- Change 234: a short key of the floor links; the follower sends back the one it holds.
function followRoute.linksKey()
  local links=followRoute.links;local last=links[#links]
  if not last then return '0' end
  return #links..':'..(positionKey(last.from) or '')..'>'..(positionKey(last.to) or '')
end
BotServer.getFollowStatus=function(memberName)
  local connected=currentBotServerListeners(BotServer._websocket) and true or false
  return {enabled=config.enabled==true,connected=connected,
    selfTarget=type(memberName)=='string' and memberName:lower()==getSelfName():lower()}
end
function followRoute.attach(socket)
  if not currentBotServerListeners(socket) then return false end
  if followRoute.socket~=socket then
    followRoute.socket=socket;followRoute.points={};followRoute.links={};followRoute.jump=nil;followRoute.replies={}
    followRoute.pending=nil;followRoute.nextRequest=0;followRoute.nextAttach=0
    followRoute.requestBound=false;followRoute.replyBound=false
    followRoute.record(getSelfPosition())
  end
  if followRoute.requestBound and followRoute.replyBound then return true end
  if (now or 0)<(followRoute.nextAttach or 0) then return false end
  followRoute.nextAttach=(now or 0)+2000
  if not followRoute.requestBound then
  local ok,result=pcall(BotServer.listen,'helperFollowRequest',function(sender,message)
    if not followRoute.current(socket) or type(sender)~='string' or #sender>64 or sender=='' or
      type(message)~='table' or message.v~=1 or type(message.target)~='string' or
      message.target:lower()~=getSelfName():lower() or sender:lower()==getSelfName():lower() or
      type(message.request)~='number' or message.request%1~=0 or message.request<1 then return end
    local time=now or 0
    local key=sender:lower();local prior=followRoute.replies[key]
    if prior and time>=prior and time-prior<FOLLOW_REPLY_INTERVAL then return end
    local count=0
    for who,at in pairs(followRoute.replies)do
      if time<at or time-at>90000 then followRoute.replies[who]=nil else count=count+1 end
    end
    if not prior and count>=32 then return end
    followRoute.replies[key]=time
    local pos=getSelfPosition();if not pos then return end
    followRoute.record(pos)
    -- Change 234: the follower names a point of our trail it already holds (have): send only
    -- the points after it. Links only when they changed (lk). Directed to him (_to).
    local points=followRoute.points
    local base
    if type(message.have)=='string' and #message.have<=40 then
      for i=#points,1,-1 do if positionKey(points[i])==message.have then base=i;break end end
    end
    local trail={}
    for i=(base or 0)+1,#points do trail[#trail+1]=copyPosition(points[i]) end
    local linksKey=followRoute.linksKey()
    local links
    if message.lk~=linksKey then
      links={}
      for i,edge in ipairs(followRoute.links)do links[i]={from=copyPosition(edge.from),to=copyPosition(edge.to)}end
    end
    local jump=followRoute.jump
    local age=jump and time-jump.at
    sendBotServer('helperFollowRoute',{v=1,to=sender,_to=sender,request=message.request,pos=pos,trail=trail,
      base=base and message.have or nil,links=links,lk=linksKey,jump=age and age>=0 and age<=FOLLOW_JUMP_TTL and
        {from=jump.from,to=jump.to,ageMs=math.floor(age),sequence=jump.sequence,dest=jump.dest,npc=jump.npc} or nil,
      state=followRoute.collectState()})
  end)
  followRoute.requestBound=ok and result~=false
  end
  if not followRoute.replyBound then
  local ok,result=pcall(BotServer.listen,'helperFollowRoute',function(sender,message)
    local pending=followRoute.pending
    if not followRoute.current(socket) or not pending or type(sender)~='string' or
      sender:lower()~=pending.name or type(message)~='table' or message.v~=1 or
      type(message.to)~='string' or message.to:lower()~=getSelfName():lower() or
      type(message.request)~='number' or message.request>pending.serial or
      message.request<=pending.serial-FOLLOW_REPLY_SERIALS or (now or 0)-pending.time>5000 then return end
    local pos=copyPosition(message.pos)
    if not pos or type(message.trail)~='table' or #message.trail>48 then return end
    local held=memberInfo[sender]
    local trail={}
    if message.base~=nil then
      -- Only the points after base came: keep ours up to it.
      if type(message.base)~='string' or not held or type(held.followTrail)~='table' then return end
      local cut
      for i=#held.followTrail,1,-1 do if positionKey(held.followTrail[i])==message.base then cut=i;break end end
      if not cut then return end
      for i=1,cut do trail[i]=copyPosition(held.followTrail[i]) end
    elseif #message.trail<1 then return end
    for i=1,#message.trail do
      local p=copyPosition(message.trail[i]);if not p then return end
      trail[#trail+1]=p
    end
    while #trail>48 do table.remove(trail,1) end
    if #trail<1 or positionKey(trail[#trail])~=positionKey(pos) then return end
    local links={}
    local linksKey=type(message.lk)=='string' and #message.lk<=80 and message.lk or nil
    if message.links~=nil then
      if type(message.links)~='table' or #message.links>32 then return end
      for _,edge in ipairs(message.links)do
        if type(edge)~='table' then return end
        local a,b=copyPosition(edge.from),copyPosition(edge.to)
        if not a or not b or a.z==b.z or math.max(math.abs(a.x-b.x),math.abs(a.y-b.y))>8 then return end
        links[#links+1]={from=a,to=b}
      end
    elseif linksKey and held and held.followLinksKey==linksKey then
      links=held.followLinks or {}
    else
      linksKey=nil -- the leader thought we had them: ask again with the next request
    end
    local jump
    if type(message.jump)=='table' then
      local a,b=copyPosition(message.jump.from),copyPosition(message.jump.to)
      if a and b and math.max(math.abs(a.x-b.x),math.abs(a.y-b.y))>8 then
        jump={from=a,to=b}
        local age,sequence=message.jump.ageMs,message.jump.sequence
        if type(age)=='number' and age>=0 and age<=FOLLOW_JUMP_TTL and age%1==0 and
            type(sequence)=='number' and sequence>=1 and sequence<=9007199254740991 and sequence%1==0 then
          jump.at=(now or 0)-age;jump.sequence=sequence
        end
        local travel=ComboFollowTravel
        if travel and type(travel.cleanDestination)=='function' then
          jump.dest=travel.cleanDestination(message.jump.dest)
          jump.npc=jump.dest and travel.cleanNpc(message.jump.npc) or nil
        end
      end
    end
    touchMember(sender,{pos=pos})
    memberInfo[sender].followTrail=trail;memberInfo[sender].followTrailAt=now or 0
    memberInfo[sender].followLinks=links;memberInfo[sender].followLinksKey=linksKey;memberInfo[sender].followJump=jump
    if message.state~=nil then followRoute.storeState(sender,message.state) end
    if ComboFollowCombat and type(ComboFollowCombat.onNaviRoute)=='function' then
      pcall(ComboFollowCombat.onNaviRoute,sender)
    end
  end)
  followRoute.replyBound=ok and result~=false
  end
  return followRoute.requestBound and followRoute.replyBound
end
BotServer.requestFollowRoute=function(memberName)
  if type(memberName)~='string' or memberName=='' or #memberName>64 or
    not config.enabled or not currentBotServerListeners(BotServer._websocket) then return false end
  if not followRoute.attach(BotServer._websocket) then return false end
  local time=now or 0;local key=memberName:lower()
  if followRoute.pending and followRoute.pending.name==key and time<followRoute.nextRequest then return false end
  followRoute.serial=followRoute.serial+1;followRoute.nextRequest=time+FOLLOW_REQUEST_INTERVAL
  followRoute.pending={name=key,serial=followRoute.serial,time=time}
  -- Change 234: tell the leader what we hold. The second-to-last point: the last one moves
  -- while he walks straight (followRoute.record extends it), the one before it stays.
  local have,lk
  for who,info in pairs(memberInfo)do
    if who:lower()==key then
      local trail=info.followTrail
      if type(trail)=='table' and #trail>0 then have=positionKey(trail[math.max(1,#trail-1)]) end
      lk=info.followLinksKey
      break
    end
  end
  return sendBotServer('helperFollowRequest',{v=1,target=memberName,_to=memberName,request=followRoute.serial,
    have=have,lk=lk})
end
BotServer.getMemberFollowRoute=function(memberName)
  if type(memberName)~='string' or not config.enabled or not currentBotServerListeners(BotServer._websocket) then return nil end
  local key=memberName:lower();local time=now or 0
  for who,info in pairs(memberInfo)do
    if who:lower()==key then
      local age=info.positionSeenAt and time-info.positionSeenAt
      local pos=copyPosition(info.pos)
      if not pos or not age or age<0 or age>MEMBER_POSITION_TIMEOUT or not members[who] then return nil end
      local trail={}
      if info.followTrailAt and time-info.followTrailAt>=0 and time-info.followTrailAt<=15000 then
        for i,p in ipairs(info.followTrail or {})do trail[i]=copyPosition(p)end
      end
      local jump=info.followJump
      if jump and jump.at and (time<jump.at or time-jump.at>FOLLOW_JUMP_TTL) then jump=nil end
      return {pos=pos,trail=trail,links=info.followLinks or {},jump=jump,positionSeenAt=info.positionSeenAt}
    end
  end
end
-- A member's leader state: seenAt (last message of any kind from him), and while fresh
-- pz (15 s), trip (25 s, renewed every 10 s while away) and cave (60 s).
BotServer.getMemberFollowState=function(memberName)
  if type(memberName)~='string' or memberName=='' or not config.enabled or
    not currentBotServerListeners(BotServer._websocket) then return nil end
  local key=memberName:lower();local time=now or 0
  for who,info in pairs(memberInfo)do
    if who:lower()==key then
      local state=members[who] and info.followState
      local age=state and info.followStateAt and time-info.followStateAt
      if not age or age<0 then state=nil end
      return {seenAt=members[who] and info.lastSeen or nil,
        pz=state and age<=15000 and state.pz or nil,trip=state and age<=25000 and state.trip or nil,
        cave=state and age<=60000 and state.cave or nil,caveAt=state and info.followStateAt or nil}
    end
  end
end
-- Followers learn at once when the leader starts or ends a refill trip, even in sight.
macro(500,function()
  if not followRoute.current(BotServer._websocket) then return end
  local state=followRoute.collectState();if not state then return end
  local time=now or 0
  local key=state.trip and 'trip' or 'hunt'
  if key==followRoute.stateKey and not(state.trip and time-(followRoute.stateAt or 0)>=10000) then return end
  if sendBotServer('helperFollowState',{v=1,state=state}) then followRoute.stateKey,followRoute.stateAt=key,time end
end)
if type(onPlayerPositionChange)=='function' then
  onPlayerPositionChange(function(newPos,oldPos)
    if not followRoute.current(BotServer._websocket) then return end
    followRoute.record(oldPos);followRoute.record(newPos)
  end)
end
-- END FOLLOW ROUTE SERVICE

-- Change 235: promoted vocations as their usual code (RP 782); without promotion the name.
-- Promoted ids are 11-15 in the Tibia protocol and 6-10 in Aurera's catalog.
local VOCATION_NAMES = {[1] = "Knight", [2] = "Paladin", [3] = "Sorcerer", [4] = "Druid", [5] = "Monk"}
local VOCATION_CODES = {[1] = "EK", [2] = "RP", [3] = "MS", [4] = "ED", [5] = "EM"}
local function selfVocation()
  local ok, id = pcall(function() return player:getVocation() end)
  id = ok and tonumber(id) or nil
  if not id or id % 1 ~= 0 then return nil end
  if id >= 11 and id <= 15 then return VOCATION_CODES[id - 10] end
  if id >= 6 and id <= 10 then return VOCATION_CODES[id - 5] end
  return VOCATION_NAMES[id]
end
local function selfLevel()
  local ok, value = pcall(level)
  value = ok and tonumber(value) or nil
  return value and value >= 1 and math.floor(value) or nil
end

-- to: answer one member who just connected (directed, no greeting of our own).
-- hello: greet again (ask the others for theirs) on a socket that already greeted.
local function publishPresence(force, to, hello)
  if not config.enabled or not BotServer._websocket then return false end
  local current = tonumber(now) or 0
  local vocation, playerLevel = selfVocation(), selfLevel()
  local fresh = presenceSocket ~= BotServer._websocket
  if not force and not to and not fresh then
    local elapsed = lastPresenceSync and current - lastPresenceSync or nil
    local changed = vocation ~= lastPresenceVocation or playerLevel ~= lastPresenceLevel
    if elapsed and elapsed >= 0 and elapsed < PRESENCE_HEARTBEAT and
        not (changed and elapsed >= PRESENCE_MIN_GAP) then
      return false
    end
  end
  local selfPos = getSelfPosition()
  -- The transport already provides the sender's identity. hi asks the others for theirs.
  local message = {pos = selfPos, voc = vocation, lvl = playerLevel}
  if to then message._to = to elseif fresh or hello then message.hi = true end
  if not sendBotServer("presence", message) then return false end
  if not to then
    lastPresenceSync, lastPresenceVocation, lastPresenceLevel = current, vocation, playerLevel
    presenceSocket = BotServer._websocket
  end
  touchMember(getSelfName(), {clientId = clientId, pos = selfPos, voc = vocation, lvl = playerLevel})
  return true
end

local function requestMemberList(force)
  local current = tonumber(now) or 0
  local interval = memberEvents() and MEMBER_LIST_INTERVAL_EVENTS or MEMBER_LIST_INTERVAL
  if not force and lastMemberListSync and current >= lastMemberListSync and
      current - lastMemberListSync < interval then return end
  if sendBotServer("list") then lastMemberListSync = current end
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

local function hasVisiblePartyMarker(minimap, name, position)
  if HelperPartyContext and not HelperPartyContext.isInParty() then return false end
  local party = minimap.partyMembers
  local member = type(party) == "table" and party[name]
  if type(member) ~= "table" or not member.widget or not hasPosition(member.pos) or
     tonumber(member.pos.z) ~= tonumber(position.z) then
    return false
  end
  local ok, visible = pcall(function() return member.widget:isVisible() end)
  return ok and visible == true
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
  if HelperTheme then HelperTheme.bindTooltip(marker) end
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
       not BotServer.isNativePartyMember(memberName) and
       not hasVisiblePartyMarker(minimap, memberName, info.pos) and
       currentTime - (info.positionSeenAt or 0) <= MEMBER_POSITION_TIMEOUT then
      markerCount = markerCount + 1
      desired[memberName] = true

      local position = {
        x = tonumber(info.pos.x),
        y = tonumber(info.pos.y),
        z = tonumber(info.pos.z)
      }
      local posKey = positionKey(position)
      local marker = markers[memberName]
      -- Some minimaps (Thornia) destroy their child widgets themselves.
      if marker and marker.widget and marker.widget.isDestroyed and marker.widget:isDestroyed() then
        markers[memberName] = nil
        marker = nil
      end

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
          if HelperTheme then HelperTheme.bindTooltip(cross) end
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
        pcall(function()
          if not (marker.widget.isDestroyed and marker.widget:isDestroyed()) then marker.widget:destroy() end
        end)
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
  local halfMarker = MINIMAP_MARKER_SIZE / 2

  for memberName, info in pairs(memberInfo) do
    if markerIndex >= MAX_MINIMAP_MARKERS then break end
    if memberName ~= selfName and info and info.clientId ~= clientId and hasPosition(info.pos) and
      currentTime - (info.positionSeenAt or 0) <= MEMBER_POSITION_TIMEOUT and info.pos.z == centerMapPos.z and
      not BotServer.isNativePartyMember(memberName) and
       not hasVisiblePartyMarker(minimap, memberName, info.pos) then
      local x = centerX + (info.pos.x - centerMapPos.x) * scale
      local y = centerY + (info.pos.y - centerMapPos.y) * scale
      if x >= halfMarker and x <= width - halfMarker and y >= halfMarker and y <= height - halfMarker then
        markerIndex = markerIndex + 1
        local tooltip = tostring(memberName)
        setMinimapMarker(overlay["marker" .. markerIndex], x - halfMarker, y - halfMarker, tooltip)
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

-- Navi diagnostics (read only): console lines "Acciones / Navi" when the connection changes and a
-- summary every minute, to see why the connected list can stay empty. Changes no behavior.
local naviDiag = {key = nil, changedAt = 0, summaryAt = 0}
local function naviLog(message, detail)
  if RinoConsole and type(RinoConsole.valid) == "function" and RinoConsole.valid() then
    pcall(RinoConsole.log, "action", "Navi", message, detail)
  end
end
local function naviCapabilities()
  local original = BotServer._gameTransportOriginal or {}
  local parts = {
    "init=" .. type(original.init), "send=" .. type(original.send), "listen=" .. type(original.listen),
    "terminate=" .. type(original.terminate), "HTTP=" .. type(HTTP),
    "HTTP.WebSocketJSON=" .. type(HTTP and HTTP.WebSocketJSON), "HTTP.WebSocket=" .. type(HTTP and HTTP.WebSocket),
  }
  local found = {}
  for _, key in ipairs({"openWebSocket", "openWebSocketJSON", "webSocket", "websocket"}) do
    local ok, value = pcall(function() return g_http and g_http[key] end)
    if ok and value ~= nil then found[#found + 1] = key end
  end
  parts[#parts + 1] = "g_http sockets=[" .. table.concat(found, ",") .. "]"
  return table.concat(parts, " | ")
end
local function naviTick()
  local clock = now or 0
  local status = "?"
  if GameBotServerTransport and GameBotServerTransport.getStatus then
    local ok, text = pcall(GameBotServerTransport.getStatus)
    if ok then status = tostring(text) end
  end
  local names = {}
  for memberName in pairs(members) do names[#names + 1] = memberName end
  table.sort(names)
  local key = status .. "|" .. tostring(BotServer._websocket ~= nil) .. "|" .. #names
  if key ~= naviDiag.key and clock - naviDiag.changedAt >= 3000 then
    naviDiag.key, naviDiag.changedAt = key, clock
    naviLog("estado: " .. status .. " | conectados " .. #names, table.concat(names, ", "))
  end
  if clock - naviDiag.summaryAt >= 60000 then
    naviDiag.summaryAt = clock
    local stats = {}
    if GameBotServerTransport and GameBotServerTransport.getTrafficStats then
      local ok, value = pcall(GameBotServerTransport.getTrafficStats)
      if ok and type(value) == "table" then stats = value end
    end
    local topics = {}
    for _, entry in ipairs(stats.topics or {}) do topics[#topics + 1] = entry.topic .. ":" .. entry.receivedMessages end
    local last = tonumber(stats.lastReceivedAt)
    naviLog("resumen: " .. status .. " | conectados " .. #names .. " | recibidos " .. tostring(stats.receivedMessages or "?") ..
      " | enviados " .. tostring(stats.sentMessages or "?") .. " | ultimo paquete recibido " ..
      (last and (math.floor((clock - last) / 1000) .. " s") or "nunca"),
      "sala=" .. tostring(storage.BotServerChannel) .. " | modo=" .. tostring(config.transportMode) ..
      " | temas recibidos=[" .. table.concat(topics, " ") .. "] | " .. naviCapabilities())
  end
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
  local started = BotServer.init(name(), channel)
  naviLog("arranque: BotServer.init devolvio " .. tostring(started) .. " | websocket=" ..
    tostring(BotServer._websocket ~= nil), naviCapabilities())
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
      lastPresenceSync = nil
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
    lastPresenceSync = nil
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
    lastPresenceSync = nil
    hideMemberMinimapOverlay()
    hideCyclopediaMemberMarkers()
  end
  botServerWindow.Features.Feature5:setOn(config.broadcasts)
  pcall(function() botServerWindow.Features.Feature5:setTooltip("Permite recibir mensajes broadcast del canal.") end)
  botServerWindow.Features.Feature5.onClick = function(widget)
    config.broadcasts = not config.broadcasts
    widget:setOn(config.broadcasts)
  end
  botServerWindow.Features.Feature6:setOn(config.minimapMembers)
  pcall(function() botServerWindow.Features.Feature6:setTooltip("Ubicaciones de Navi fuera de tu party. Los miembros de tu party usan los marcadores nativos; Exiva y Follow siguen disponibles.") end)
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
    local text = botServerWindow.Features.broadcastText:getText()
    if sendBotServer("broadcast", text) and config.broadcasts then
      local transport = GameBotServerTransport
      local features = transport and type(transport.serverFeatures) == "function" and transport.serverFeatures()
      if type(features) == "table" and features.echo == false then broadcastMessage(getSelfName() .. ": " .. text) end
    end
    botServerWindow.Features.broadcastText:setText('')
  end
end

function initBotServerListenFunctions()
  if not BotServer._websocket then return end
  if not config.enabled then return end
  if BotServer._rodMasterMainListenersGeneration == botServerListenGeneration and
    BotServer._rodMasterMainListenersSocket == BotServer._websocket then return end

  -- A reconnect must not retain members or coordinates from the previous channel/socket.
  if botServerListenSocket ~= BotServer._websocket then
    members, memberInfo = {}, {}
    vBot.BotServerMembers, CachedFriends, CachedEnemies = {}, {}, {}
    lastPresenceSync, lastMemberListSync = nil, nil
  end
  botServerListenSocket = BotServer._websocket
  local listenerSocket = botServerListenSocket
  BotServer._rodMasterMainListenersGeneration = botServerListenGeneration
  BotServer._rodMasterMainListenersSocket = botServerListenSocket

  -- list
  local okList = BotServer.listen("list", function(name, data)
    if not currentBotServerListeners(listenerSocket) then return end
    serverCount = regexMatch(json.encode(data), regex)
    ServerMembers = json.encode(data)
    if type(data) == "table" then
      local listed = {[getSelfName():lower()] = true}
      local function add(who)
        if type(who) ~= "string" or who == "" then return end
        listed[who:lower()] = true
        touchMember(who)
      end
      for memberName, value in pairs(data) do
        if type(memberName) == "string" and memberName ~= "" and type(value) ~= "table" then
          add(memberName)
        elseif type(value) == "string" then add(value)
        elseif type(value) == "table" then add(value.name or value.player or value[1]) end
      end
      for who in pairs(members) do
        if not listed[who:lower()] then
          members[who], memberInfo[who], vBot.BotServerMembers[who] = nil, nil, nil
          CachedFriends, CachedEnemies = {}, {}
        end
      end
    elseif type(data) == "string" then touchMember(data) end
    -- The first list on a socket proves it works: greet once more, in case the greeting sent
    -- while it was opening was lost (presence now goes out only on events).
    if helloListSocket ~= listenerSocket then
      helloListSocket = listenerSocket
      publishPresence(true, nil, true)
    end
  end)

  -- presence
  local okPresence = BotServer.listen("presence", function(name, message)
    if not currentBotServerListeners(listenerSocket) then return end

    -- Prefer the identity supplied by the relay, including with older clients.
    if type(name) ~= "string" or name == "" then return end
    local data = type(message) == "table" and message or {}
    touchMember(name, {clientId = data.clientId, pos = data.pos, voc = data.voc, lvl = data.lvl})
    -- A member who just connected asks for ours: answer him only, at most every 10 s.
    if data.hi == true and name:lower() ~= getSelfName():lower() then
      local key, time = name:lower(), now or 0
      local last = presenceReplies[key]
      if not last or time < last or time - last >= PRESENCE_REPLY_GAP then
        presenceReplies[key] = time
        publishPresence(true, name)
      end
    end
  end)

  -- Change 234: the server announces who joins and leaves the room (when it supports it).
  BotServer.listen("_join", function(name)
    if not currentBotServerListeners(listenerSocket) or type(name) ~= "string" or name == "" then return end
    touchMember(name)
  end)
  BotServer.listen("_leave", function(name)
    if not currentBotServerListeners(listenerSocket) or type(name) ~= "string" or name == "" then return end
    local key = name:lower()
    if key == getSelfName():lower() then return end
    for who in pairs(members) do
      if who:lower() == key then
        members[who], memberInfo[who], vBot.BotServerMembers[who] = nil, nil, nil
        CachedFriends, CachedEnemies = {}, {}
      end
    end
  end)

  -- broadcast
  local okBroadcast = BotServer.listen("broadcast", function(name, message)
    if not currentBotServerListeners(listenerSocket) then return end
    if config.broadcasts then
      broadcastMessage(name..": "..message)
    end
  end)
  naviLog("oyentes: list=" .. tostring(okList) .. " presence=" .. tostring(okPresence) ..
    " broadcast=" .. tostring(okBroadcast), "websocket=" .. tostring(BotServer._websocket ~= nil))
  -- Optional route listeners must never prevent normal presence registration.
  pcall(followRoute.attach,listenerSocket)
  pcall(BotServer.listen,'helperPartyThreat',function(sender,message)
    if not currentBotServerListeners(listenerSocket) then return end
    if PartyThreat and PartyThreat.onNavi then PartyThreat.onNavi(sender,message) end
  end)
  pcall(BotServer.listen,'helperFollowSupplies',function(sender,message)
    if not currentBotServerListeners(listenerSocket) then return end
    if ComboFollowCombat and ComboFollowCombat.onSupplyVisit then
      ComboFollowCombat.onSupplyVisit(sender,message)
    end
  end)
  pcall(BotServer.listen,'helperFollowUse',function(sender,message)
    if not currentBotServerListeners(listenerSocket) then return end
    if ComboFollowUse and ComboFollowUse.onNavi then pcall(ComboFollowUse.onNavi,sender,message) end
  end)
  pcall(BotServer.listen,'helperFollowState',function(sender,message)
    if not currentBotServerListeners(listenerSocket) then return end
    if type(sender)~='string' or sender=='' or #sender>64 or sender:lower()==getSelfName():lower() or
      type(message)~='table' or message.v~=1 then return end
    touchMember(sender,{})
    followRoute.storeState(sender,message.state)
  end)
  publishPresence(true)
  requestMemberList(true)
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
  if BotServer._rodMasterMainGeneration ~= botServerListenGeneration then return end
  if config.enabled then
    initBotServerListenFunctions()
    publishPresence()
    updateMemberMinimapOverlay()
    updateCyclopediaMemberMinimap()
  else
    hideMemberMinimapOverlay()
    hideCyclopediaMemberMarkers()
  end
end)

macro(1000, function()
  if BotServer._rodMasterMainGeneration ~= botServerListenGeneration then return end
  pruneMembers()
  if config.enabled then
    initBotServerListenFunctions()
    publishPresence()
    requestMemberList()
  end
  updateStatusText()
  pcall(naviTick)
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

publishPresence()
