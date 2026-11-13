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

return Travel
