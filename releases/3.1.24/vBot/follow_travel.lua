-- Match a recent Navi jump to a Travel waypoint in this character's CaveBot routes.
ComboFollowTravel={}
local Travel=ComboFollowTravel
local directory='cavebot_configs'
Travel.maxAge=120000

function Travel.near(a,b,radius)
  return a and b and a.z==b.z and math.max(math.abs(a.x-b.x),math.abs(a.y-b.y))<=radius
end

function Travel.sameJump(a,b)
  return a and b and a.sequence and a.sequence==b.sequence and math.abs(a.at-b.at)<=5000 and
    Travel.near(a.from,b.from,0) and Travel.near(a.to,b.to,0)
end

local function waypoint(entry)
  if type(entry)=='table' and type(entry[1])=='string' and type(entry[2])=='string' then
    return entry[1]:lower(),entry[2]
  end
end

local function position(value)
  local x,y,z=value:match('^%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)')
  if x then return {x=tonumber(x),y=tonumber(y),z=tonumber(z)} end
end

local function port(entries,index,step,departure)
  for i=index+step,index+step*8,step do
    local action,value=waypoint(entries[i])
    if not action or action=='travel' then return nil end
    if action=='goto' then
      local tile=position(value)
      -- Some routes repeat a departure waypoint before the first arrival waypoint.
      if tile and not Travel.near(tile,departure,8) then return tile end
    end
  end
end

local function text(value)
  value=value and value:match('^%s*(.-)%s*$')
  if value and #value>0 and #value<=64 and not value:find('%c') then return value end
end

function Travel.begin(jump,config)
  local ok,names=pcall(function() return config.list(directory) end)
  return {jump=jump,names=ok and type(names)=='table' and names or {},index=1}
end

function Travel.advance(search,config)
  local name=search.names[search.index]
  if not name then return search.trip,search.trip and 'ready' or 'missing' end
  search.index=search.index+1
  local ok,entries=pcall(config.load,directory,name)
  if ok and type(entries)=='table' then
    for index,entry in ipairs(entries) do
      local action,value=waypoint(entry)
      if action=='travel' and Travel.near(port(entries,index,-1),search.jump.from,8) and
          Travel.near(port(entries,index,1,search.jump.from),search.jump.to,16) then
        local npc,destination=value:match('^([^,]+),([^,]+)')
        npc,destination=text(npc),text(destination)
        if npc and destination then
          local key=npc:lower()..'\0'..destination:lower()
          if search.trip and search.trip.key~=key then return nil,'ambiguous' end
          if not search.trip then search.trip={npc=npc,destination=destination,key=key} end
        end
      end
    end
  end
  return nil,'scanning'
end

function Travel.findNpc(name,origin,spectators)
  local wanted=name:lower()
  for _,npc in pairs(spectators or {}) do
    if npc:isNpc() and npc:getName():lower()==wanted and Travel.near(npc:getPosition(),origin,3) then return npc end
  end
end

function Travel.cancel(trip,cavebot)
  if not trip or not trip.revision then return end
  if cavebot.IsNpcConversationCurrent(trip.revision) then cavebot.CancelNpcConversation() end
  trip.revision=nil
end

-- Change 113: travel without a CaveBot Travel waypoint. The leader writes down
-- the city of its last NPC trip (CaveBot.Travel, or the captain's question when
-- it talks by hand) and Navi sends it with the jump; the follower then talks to
-- that NPC, or the nearest one, for the same city.
Travel.intentMaxAge=45000

-- A city name: 1-32 chars, letters, spaces, apostrophe or hyphen.
function Travel.cleanDestination(value)
  if type(value)~='string' then return nil end
  value=value:match('^%s*(.-)%s*$')
  if #value<2 or #value>32 or not value:match("^%a[%a' %-]*$") then return nil end
  return value
end

function Travel.cleanNpc(value)
  if type(value)~='string' then return nil end
  value=value:match('^%s*(.-)%s*$')
  if #value<1 or #value>64 or not value:match("^[%w %.'%-]+$") or not value:find('%a') then return nil end
  return value
end

-- City offered in an NPC question ("Do you seek a passage to Venore for 170
-- gold?", "...viajar a Venore por...", "...para Venore por...").
local offers={
  "[Tt]o (%u[%a' %-]-) for ",
  "[Tt]o (%u[%a' %-]-)%?",
  " a (%u[%a' %-]-) por ",
  " a (%u[%a' %-]-)%?",
  "[Pp]ara (%u[%a' %-]-) por ",
}
function Travel.parseDestination(text)
  if type(text)~='string' or #text>240 then return nil end
  for _,pattern in ipairs(offers)do
    local city=Travel.cleanDestination(text:match(pattern))
    if city then
      local words=0
      for _ in city:gmatch('%S+')do words=words+1 end
      if words<=3 then return city end
    end
  end
  return nil
end

function Travel.nearestNpc(origin,spectators,radius)
  local best,bestDistance
  for _,npc in pairs(spectators or {})do
    local okNpc,isNpc=pcall(function() return npc:isNpc() end)
    local okPos,pos=pcall(function() return npc:getPosition() end)
    if okNpc and isNpc and okPos and pos and Travel.near(pos,origin,radius) then
      local d=math.max(math.abs(pos.x-origin.x),math.abs(pos.y-origin.y))
      if not best or d<bestDistance then best,bestDistance=npc,d end
    end
  end
  return best
end

local function clock()
  if now then return now end
  if g_clock and g_clock.millis then return g_clock.millis() end
  return 0
end
local function selfPosition()
  local ok,pos=pcall(function() return player:getPosition() end)
  if ok and type(pos)=='table' then return {x=pos.x,y=pos.y,z=pos.z} end
end
local function spectators()
  if type(getSpectators)~='function' then return {} end
  local ok,list=pcall(getSpectators,false)
  return ok and type(list)=='table' and list or {}
end

-- source: 'cavebot' (exact value), 'npc' (parsed question), 'own' (own words).
function Travel.noteIntent(destination,npcName,source)
  local city=Travel.cleanDestination(destination)
  local pos=selfPosition()
  if not city or not pos then return false end
  local time=clock()
  local prior=Travel.intent
  -- A parsed NPC question never overrides an exact CaveBot value of the same talk.
  if prior and prior.source=='cavebot' and source~='cavebot' and time-prior.at<=10000 then return false end
  if not Travel.cleanNpc(npcName) then
    local npc=Travel.nearestNpc(pos,spectators(),4)
    local ok,name=pcall(function() return npc and npc:getName() end)
    npcName=ok and name or nil
  end
  Travel.intent={destination=city,npc=Travel.cleanNpc(npcName),pos=pos,at=time,source=source or 'cavebot'}
  return true
end

-- The intent belongs to a jump that starts next to where it was written down.
function Travel.intentFor(from,time)
  local intent=Travel.intent
  if not intent or type(from)~='table' or type(time)~='number' then return nil end
  if time<intent.at or time-intent.at>Travel.intentMaxAge or not Travel.near(intent.pos,from,6) then return nil end
  Travel.intent=nil
  return intent
end

-- Manual talk: the captain's question names the city; some servers also echo
-- our own words ("venore", then "yes").
if type(onTalk)=='function' then
  local ignored={hi=true,hello=true,yes=true,no=true,bye=true,farewell=true,trade=true,
    passage=true,travel=true,sail=true,si=true,ola=true,hola=true}
  local lastWord
  onTalk(function(name,level,mode,text)
    if type(name)~='string' or type(text)~='string' or #text>240 then return end
    local okSelf,selfName=pcall(function() return player:getName() end)
    if okSelf and type(selfName)=='string' and name:lower()==selfName:lower() then
      local word=text:lower():match('^%s*(.-)%s*$')
      if word=='yes' or word=='si' or word=='sim' then
        if lastWord and clock()-lastWord.at<=20000 and
            not (Travel.intent and clock()-Travel.intent.at<=20000) then
          Travel.noteIntent(lastWord.text,nil,'own')
        end
      elseif not ignored[word] and Travel.cleanDestination(text) then
        lastWord={text=text:match('^%s*(.-)%s*$'),at=clock()}
      end
      return
    end
    local city=Travel.parseDestination(text)
    if not city then return end
    local pos=selfPosition()
    local creature=type(getCreatureByName)=='function' and getCreatureByName(name)
    local okNpc,isNpc=pcall(function() return creature and creature:isNpc() end)
    local okPos,npcPos=pcall(function() return creature and creature:getPosition() end)
    if not pos or not okNpc or not isNpc or not okPos or not Travel.near(npcPos,pos,4) then return end
    Travel.noteIntent(city,name,'npc')
  end)
end

return Travel
