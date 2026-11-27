-- Read-only party membership and positions. Navi and Auto Party share this view;
-- native minimap markers are never changed here.
HelperPartyContext = {}
local P = HelperPartyContext
local leaderShields = {[4]=true,[6]=true,[8]=true,[10]=true}
local memberShields = {[3]=true,[4]=true,[5]=true,[6]=true,[7]=true,[8]=true,[9]=true,[10]=true}
local sharedShields = {[5]=true,[6]=true,[7]=true,[8]=true,[9]=true,[10]=true}
local noShareShields = {[7]=true,[8]=true,[9]=true,[10]=true}
local cached, cachedAt, cachedOwner
local nativePositions={}
function P.normalize(name)
  return tostring(name or ''):match('^%s*(.-)%s*$'):lower()
end
local function method(object, name)
  if not object then return nil end
  local ok, result = pcall(function() return object[name](object) end)
  if ok then return result end
end
local function field(object, name)
  local ok, result = pcall(function() return object[name] end)
  if ok then return result end
end
local function localPlayer()
  if g_game and type(g_game.getLocalPlayer)=='function' then
    local ok, value=pcall(g_game.getLocalPlayer)
    if ok and value then return value end
  end
  return player
end
local function position(value)
  if type(value)~='table' then return nil end
  local x,y,z=tonumber(value.x),tonumber(value.y),tonumber(value.z)
  if not x or not y or not z or x%1~=0 or y%1~=0 or z%1~=0 or x<0 or y<0 or x>65535 or y>65535 or z<0 or z>15 then return nil end
  return {x=x,y=y,z=z}
end
function P.isInParty()
  return memberShields[tonumber(method(localPlayer(),'getShield'))]==true
end
function P.isLeader()
  return leaderShields[tonumber(method(localPlayer(),'getShield'))]==true
end
function P.invalidate() cached,cachedAt,cachedOwner=nil,nil,nil end
local function minimap()
  local module=modules and modules.game_minimap
  if not module then return nil end
  if type(module.getMiniMapUi)=='function' then
    local ok,value=pcall(module.getMiniMapUi)
    if ok and value then return value end
  end
  return module.minimapWidget
end
function P.snapshot()
  local me=localPlayer()
  local shield=tonumber(method(me,'getShield')) or 0
  local ownName=tostring(method(me,'getName') or '')
  local owner=ownName..':'..shield
  local time=tonumber(now)
  if time and cached and cachedOwner==owner and cachedAt and time>=cachedAt and time-cachedAt<200 then return cached end
  local result={inParty=memberShields[shield]==true,leader=leaderShields[shield]==true,
    sharing=sharedShields[shield]==true,eligible=sharedShields[shield]==true and not noShareShields[shield],
    ownName=ownName,shield=shield,members={},byName={}}
  cached,cachedAt,cachedOwner=result,time,owner
  if not result.inParty then nativePositions={};return result end
  local function add(name,info)
    if type(name)~='string' or name=='' or #name>80 or name:find('%c') then return end
    local key=P.normalize(name)
    local entry=result.byName[key]
    if not entry then
      entry={name=name,visible=false,confirmed=true}
      result.byName[key]=entry;result.members[#result.members+1]=entry
    end
    entry.name=name
    for field,value in pairs(info or {}) do if value~=nil then entry[field]=value end end
  end
  -- This native table is populated by the server's party tracking, including
  -- members outside the viewport. It is ignored immediately after leaving party.
  local map=minimap()
  local native=map and map.partyMembers
  local nativeSeen={}
  local function observe(name, pos, object, info)
    if type(name)~='string' or name=='' or #name>80 or name:find('%c') then return end
    local normalized=P.normalize(name)
    if nativeSeen[normalized] or #result.members>=100 then return end
    nativeSeen[normalized]=true
    local stamp=nativePositions[normalized]
    local posKey=pos and (pos.x..','..pos.y..','..pos.z)
    if not stamp or stamp.key~=posKey or stamp.object~=object then
      stamp={key=posKey,object=object,at=time};nativePositions[normalized]=stamp
    end
    info=info or {}
    info.pos,info.positionSeenAt,info.native=pos,stamp.at,true
    add(name,info)
  end
  if type(native)=='table' then
    for key,entry in pairs(native) do
      if type(entry)=='table' then
        local name=type(key)=='string' and key or entry.name
        local pos=position(entry.pos or entry.position)
        observe(name,pos,entry)
      end
    end
  end
  -- Current Thornia keeps partyDots/remotePartyState private. Its native map
  -- children carry creatureId, pos and either a creature or remote party name.
  -- Read that metadata even on hidden floors; never change native widgets.
  local children=method(map,'getChildren')
  for _,dot in pairs(type(children)=='table' and children or {}) do
    if method(dot,'isDestroyed')~=true and field(dot,'isLocalPlayer')~=true then
      local id=tonumber(field(dot,'creatureId'))
      local pos=position(field(dot,'pos'))
      if id and id>0 and id%1==0 and pos then
        local creature=field(dot,'creature')
        local s=tonumber(method(creature,'getShield'))
        if method(creature,'isPlayer')==true and memberShields[s] then
          observe(method(creature,'getName'),pos,dot,{id=id,shield=s,visible=true,creature=creature,
            leader=leaderShields[s]==true,sharing=sharedShields[s]==true,
            eligible=sharedShields[s]==true and not noShareShields[s]})
        elseif field(dot,'isRemote')==true then
          local name=field(dot,'partyDisplayName')
          if name~='Player '..id then observe(name,pos,dot,{id=id}) end
        end
      end
    end
  end
  for name in pairs(nativePositions)do if not nativeSeen[name]then nativePositions[name]=nil end end
  if type(getSpectators)=='function' then
    local ok,list=pcall(getSpectators)
    if ok then
      for _,creature in pairs(type(list)=='table' and list or {}) do
        local s=tonumber(method(creature,'getShield'))
        if method(creature,'isPlayer')==true and memberShields[s] then
          add(method(creature,'getName'),{id=method(creature,'getId'),shield=s,
            pos=position(method(creature,'getPosition')),positionSeenAt=time,visible=true,creature=creature,
            leader=leaderShields[s]==true,sharing=sharedShields[s]==true,
            eligible=sharedShields[s]==true and not noShareShields[s]})
        end
      end
    end
  end
  add(ownName,{id=method(me,'getId'),shield=shield,pos=position(method(me,'getPosition')),
    positionSeenAt=time,visible=true,creature=me,leader=result.leader,sharing=result.sharing,eligible=result.eligible,self=true})
  table.sort(result.members,function(a,b)
    if a.self~=b.self then return a.self==true end
    return P.normalize(a.name)<P.normalize(b.name)
  end)
  return result
end
function P.member(name) return P.snapshot().byName[P.normalize(name)] end
function P.isMember(name) return P.member(name)~=nil end
function P.getPosition(name)
  local entry=P.member(name)
  return entry and position(entry.pos) or nil, entry and entry.positionSeenAt or nil
end
return P
