-- Guard this bot's imported IDs against Aurera's loaded DAT. Never rewrite profiles.
local nativeThings, nativeGame, nativeItem = g_things, g_game, Item
local C = {version=1, warningLimit=6, skipped=0, warnings=0}
HelperClientCompat = C

local function isAureraDirectory()
  if not g_resources or type(g_resources.getWriteDir)~="function" then return false end
  local ok,path=pcall(g_resources.getWriteDir)
  if not ok or type(path)~="string" then return false end
  path=path:lower():gsub("\\","/"):gsub("/+","/")
  return (path.."/"):find("/otclientv8/aurera/",1,true)~=nil
end
C.isAurera=HelperClient and HelperClient.id=='aurera'
if not HelperClient then C.isAurera=isAureraDirectory() end
C.active=true
C.clientName=HelperClient and HelperClient.name or 'Cliente'

local seen={}
local function notice(key,message)
  C.skipped=C.skipped+1
  if seen[key] then return end
  seen[key]=true
  C.warnings=C.warnings+1
  if type(warn)~="function" then return end
  if C.warnings<=C.warningLimit then
    warn(C.clientName..": "..message..". Se conserva en tus ajustes.")
  elseif C.warnings==C.warningLimit+1 then
    warn(C.clientName..": se omitieron mas valores incompatibles; tus ajustes originales se conservan.")
  end
end

local function integer(value)
  local n=tonumber(value)
  if not n or n~=n or n==math.huge or n==-math.huge or n%1~=0 then return nil end
  return n
end

local catalogs,signature={},nil
local function datState()
  if not nativeThings or type(nativeThings.isDatLoaded)~="function" then return false end
  local ok,loaded=pcall(nativeThings.isDatLoaded)
  if not ok or not loaded then catalogs={};signature=nil;return false end
  if type(nativeThings.getDatSignature)=="function" then
    local read,current=pcall(nativeThings.getDatSignature)
    if read and current~=signature then catalogs={};signature=current end
  end
  return true
end

local function catalog(category)
  if not datState() then return nil end
  if catalogs[category] then return catalogs[category] end
  if type(nativeThings.getThingTypes)~="function" then return nil end
  local ok,types=pcall(nativeThings.getThingTypes,category)
  if not ok or type(types)~="table" then return nil end
  local result={ids={},count=0,maxId=0}
  for _,thing in pairs(types) do
    local read,id=pcall(function() return thing:getId() end)
    id=read and integer(id) or nil
    if id and id>0 and (category~=0 or id>=100) and not result.ids[id] then
      result.ids[id]=true
      result.count=result.count+1
      if id>result.maxId then result.maxId=id end
    end
  end
  if result.count==0 then return nil end
  catalogs[category]=result
  return result
end

local function valid(value,category)
  local id=integer(value)
  if not id or id<=0 or (category==0 and id<100) then return false end
  local known=catalog(category)
  return known~=nil and known.ids[id]==true
end

local function invalid(value,category)
  local known=catalog(category)
  if not known then
    notice("dat-unavailable","el catalogo DAT no esta disponible; se omite la accion")
  else
    notice(tostring(category)..":"..tostring(value),"el ID "..tostring(value).." no existe en el catalogo "..tostring(category))
  end
end

function C.refresh()
  catalogs={};signature=nil
  if not C.active then return true end
  return catalog(0)~=nil
end

function C.isValidItemId(value)
  if not C.active then return true end
  return valid(value,0)
end

-- Aurera's shipped spell catalog uses 6..10 for promotions. Imported Helper
-- profiles also use 11..15; both spellings resolve to the same base vocation.
function C.baseVocation(value)
  local id=tonumber(value)
  if not C.active or not id then return id end
  if id>=6 and id<=10 and id%1==0 then return id-5 end
  if id>=11 and id<=15 and id%1==0 then return id-10 end
  return id
end

function C.itemIdForDisplay(value)
  if not C.active then return value end
  local id=integer(value)
  if id==0 or value==nil then return 0 end
  if valid(value,0) then return id end
  invalid(value,0)
  return 0
end

function C.itemIdFromWidget(widget)
  local actual=widget:getItemId()
  local state=widget._aureraItemDisplay
  if state and actual~=0 then state.missing=nil end
  return state and state.missing or actual
end

-- A foreign item is visually empty, but remains the logical value of this
-- control until the user edits it. Initial painting must not fire handlers
-- which delete a supply/rule when they see an empty item.
function C.setItemIdForDisplay(widget,value)
  if not C.active then return widget:setItemId(value) end
  local displayed=C.itemIdForDisplay(value)
  local missing=value~=nil and tonumber(value)~=0 and displayed==0
  local state=widget._aureraItemDisplay
  if not missing and not state then return widget:setItemId(displayed) end
  if not state then
    state={getter=widget.getItemId,setter=widget.setItemId,epoch=0}
    widget._aureraItemDisplay=state
  end
  local previousMissing=state.missing
  if widget.onItemChange~=state.wrapper then state.callback=widget.onItemChange end
  state.wrapper=function(...)
    state.epoch=state.epoch+1
    state.missing=nil
    if type(state.callback)=='function' then return state.callback(...) end
  end
  state.missing=missing and tonumber(value) or nil
  if missing then
    widget.onItemChange=nil
    local ok,result=pcall(state.setter,widget,displayed)
    widget.onItemChange=state.wrapper
    assert(ok,result)
    return result
  end
  widget.onItemChange=state.wrapper
  local epoch=state.epoch
  local result=state.setter(widget,displayed)
  -- Clearing an empty-looking placeholder is still an intentional logical edit.
  if previousMissing and displayed==0 and epoch==state.epoch then state.wrapper(widget) end
  return result
end

function C.createItem(value,...)
  if not nativeItem or type(nativeItem.create)~="function" then return nil end
  if not C.active then return nativeItem.create(value,...) end
  if not valid(value,0) then invalid(value,0);return nil end
  return nativeItem.create(integer(value),...)
end

function C.getThingType(value,category,...)
  if not nativeThings or type(nativeThings.getThingType)~="function" then return nil end
  if not C.active then return nativeThings.getThingType(value,category,...) end
  category=category==nil and 0 or integer(category)
  if category==nil or category<0 or category>3 then
    notice("category:"..tostring(category),"se omite una categoria de objetos desconocida")
    return nil
  end
  if not valid(value,category) then invalid(value,category);return nil end
  return nativeThings.getThingType(integer(value),category,...)
end

-- Validate before a context helper can construct a native item or send its ID.
-- Exported for helpers whose closure still points to the client's original APIs.
function C.allowItemAction(value)
  if not C.active then return true end
  if valid(value,0) then return true end
  invalid(value,0)
  return false
end

function C.status()
  local known=C.active and catalog(0) or nil
  return {active=C.active,ready=known~=nil,items=known and known.count or 0,
    maxItemId=known and known.maxId or 0,skipped=C.skipped,warnings=C.warnings}
end

if C.active then
  -- Replace only references in this game_bot environment. Native tables/classes
  -- and other bot contexts keep their original function identities.
  local function proxyFor(original,overrides)
    if type(original)=="table" then
      for key,value in pairs(original) do
        -- Native signals must remain on the real game table, including
        -- signals installed after this sandbox was created.
        if overrides[key]==nil and not (type(key)=='string' and key:sub(1,2)=='on') then overrides[key]=value end
      end
    end
    local meta
    meta={__index=original,__newindex=function(self,key,value)
      if type(key)=='string' and key:sub(1,2)=='on' then original[key]=value
      else
        -- rawset is not exported by game_bot; temporarily detach our own
        -- metatable to store sandbox-only fields without changing the client.
        setmetatable(self,nil);self[key]=value;setmetatable(self,meta)
      end
    end}
    return setmetatable(overrides,meta)
  end
  if nativeThings then
    g_things=proxyFor(nativeThings,{getThingType=C.getThingType})
  end
  if nativeItem and type(nativeItem.create)=="function" then
    Item=proxyFor(nativeItem,{create=C.createItem})
  end
  if nativeGame then
    local proxy={}
    local function guard(name,empty)
      local original=nativeGame[name]
      if type(original)~="function" then return end
      proxy[name]=function(value,...)
        if not C.allowItemAction(value) then return empty end
        return original(integer(value),...)
      end
    end
    guard("useInventoryItem",false)
    guard("useInventoryItemWith",false)
    guard("equipItemId",false)
    guard("findPlayerItem",nil)
    guard("requestStashRetrieveItem",false)
    guard("stashWithdraw",false)
    g_game=proxyFor(nativeGame,proxy)
  end
end
