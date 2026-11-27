-- Loot rules belong to the character, independently of TargetBot hunt profiles.
TargetBot.LootPolicy={}
local P=TargetBot.LootPolicy
local key='targetBotLootManager'
P.categories={{'unassigned','Sin clasificar'},{'gold','Oro'},{'products','Productos de criaturas'},
 {'weapons','Armas'},{'armor','Armaduras'},{'amulets','Amuletos'},{'boots','Botas'},
 {'helmets','Cascos'},{'legs','Piernas'},{'shields','Escudos'},{'rings','Anillos'},
 {'valuables','Objetos valiosos'},{'potions','Pociones'},{'runes','Runas'},
 {'ammo','Municion'},{'food','Comida'},{'tools','Herramientas'},
 {'containers','Contenedores'},{'decoration','Decoracion'},{'others','Otros'}}
local categoryMap={Armors='armor',Amulets='amulets',Boots='boots',Containers='containers',
 Decoration='decoration',Food='food',HelmetsHats='helmets',Legs='legs',Others='others',
 Potions='potions',Rings='rings',Runes='runes',Shields='shields',Tools='tools',Valuables='valuables',
 Ammunition='ammo',Axes='weapons',Clubs='weapons',DistanceWeapons='weapons',Swords='weapons',
 WandsRods='weapons',Fist='weapons',CreatureProducs='products',CreatureProducts='products',Gold='gold'}
local standard={ [1]='armor',[2]='amulets',[3]='boots',[4]='containers',[5]='decoration',
 [6]='food',[7]='helmets',[8]='legs',[9]='others',[10]='potions',[11]='rings',[12]='runes',
 [13]='shields',[14]='tools',[15]='valuables',[16]='ammo',[17]='weapons',[18]='weapons',
 [19]='weapons',[20]='weapons',[21]='weapons',[24]='products',[25]='containers',[27]='weapons'}
local categoryCache,names,validIds={},{},nil
local pending,failures=nil,{}
local managedFrame
local links,openReceipts={},{}
local session=tostring({})
local windowBindings,windowSerial={},0
P.message=''
function P.copy(v)
 if type(v)~='table'then return v end
 local out={};for k,x in pairs(v)do out[k]=P.copy(x)end;return out
end
local function call(o,m,...)
 if not o or type(o[m])~='function'then return end
 local ok,v=pcall(o[m],o,...);if ok then return v end
end
P.call=call
local function time()return tonumber(now)or 0 end
local function same(a,b)return a and b and a.x==b.x and a.y==b.y and a.z==b.z end
local function types(id)
 if type(id)~='number'or id~=id or id~=math.floor(id)or id<100 or id>65535 then return end
 if HelperClientCompat and not HelperClientCompat.isValidItemId(id)then return end
 if not(HelperClientCompat and HelperClientCompat.active)then
  if not validIds then
   if type(g_things.isDatLoaded)=='function'and not g_things.isDatLoaded()then return end
   if type(g_things.getThingTypes)~='function'then return end
   local ok,all=pcall(g_things.getThingTypes,0);if not ok or type(all)~='table'then return end
   validIds={};for _,thing in pairs(all)do local n=call(thing,'getId');if n then validIds[n]=true end end
  end
  if not validIds[id]then return end
 end
 local ok,v=pcall(g_things.getThingType,id,0);if ok then return v end
end
function P.validId(id)
 return type(id)=='number'and id==math.floor(id)and id>=100 and types(id)~=nil
end
function P.name(id)
 if names[id]then return names[id]end
 local thing=types(id);local data=call(thing,'getMarketData')
 local name=type(data)=='table'and data.name or nil
 if not name or name==''then name=call(thing,'getName')end
 if type(name)~='string'or name==''then name='ID '..tostring(id)end
 names[id]=name;return name
end
function P.category(id)
 if categoryCache[id]then return categoryCache[id]end
 local category='unassigned'
 -- These three currency IDs were verified against Aurera's loaded item data.
 local nativeName=P.name(id):lower()
 if nativeName=='gold coin'or nativeName=='platinum coin'or nativeName=='crystal coin'
   or HelperClientCompat and HelperClientCompat.isAurera and(id==3031 or id==3035 or id==3043)then category='gold'
 else
  local data=call(types(id),'getMarketData');local number=type(data)=='table'and tonumber(data.category)
  if number then
   local market=MarketCategory or HelperClient and HelperClient.marketCategories
   if type(market)=='table'then
    for name,value in pairs(market)do if value==number and categoryMap[name]then category=categoryMap[name];break end end
   end
   if category=='unassigned'then category=standard[number]or'unassigned'end
  end
 end
 categoryCache[id]=category;return category
end
local function entries(list)
 local out,seen={},{}
 for _,v in ipairs(type(list)=='table'and list or{})do
  local id=tonumber(type(v)=='table'and v.id or v)
  if id and id>0 and not seen[id]then seen[id]=true;out[#out+1]={id=id,count=1}end
 end
 return out
end
P.entries=entries
function P.read(seed)
 local saved=storage.extras and storage.extras[key]
 if type(saved)=='table'and(saved.version==2 or saved.version==3)then
  local value=P.copy(saved);value.version=3;value.engine=TargetBot.LootMode.requested(saved);return value
 end
 seed=seed or{}
 return{version=3,engine=TargetBot.LootMode.requested(),
  filter=seed.everyItem and'skip'or'accept',accepted=entries(seed.items),ignored={},categories={},overrides={},
  fallback=true,main={kind='legacy'},legacy=entries(seed.containers),
  minCapacity=tonumber(seed.minCapacity)or 100,maxDanger=tonumber(seed.maxDanger)or 10}
end
function P.current()return storage.extras and storage.extras[key]end
function P.active()
 local cfg=P.current()
 return type(cfg)=='table'and(cfg.version==2 or cfg.version==3)and TargetBot.LootMode.resolve()~='native'
end
function P.validate(cfg)
 local supported,reason=TargetBot.LootMode.canSelect(cfg.engine)
 if not supported then return false,reason end
 if cfg.filter~='accept'and cfg.filter~='skip'then return false,'Selecciona un filtro de objetos.'end
 for _,field in ipairs({'minCapacity','maxDanger'})do
  local n=tonumber(cfg[field]);if not n or n~=n or n<0 or n>1000000 or n~=math.floor(n)then return false,'Valor no valido: '..field end
 end
 return true
end
function P.commit(cfg)
 local ok,message=P.validate(cfg);if not ok then return false,message end
 storage.extras=storage.extras or{}
 local value=P.copy(cfg);value.version=3;value.accepted=entries(value.accepted);value.ignored=entries(value.ignored)
 storage.extras[key]=value;TargetBot.LootMode.reset()
 pending,failures=nil,{};P.message=''
 return true
end
function P.accepts(id,cfg)
 cfg=cfg or P.current();if not cfg then return false end
 local list=cfg.filter=='skip'and cfg.ignored or cfg.accepted
 local found=false;for _,v in ipairs(list or{})do if tonumber(v.id)==id then found=true;break end end
 return cfg.filter=='skip'and not found or cfg.filter=='accept'and found
end
local function allContainers()return g_game.getContainers()or{}end
local function containerById(open,id)
 for _,c in pairs(open)do if call(c,'getId')==id then return c end end
end
local function inventorySlot(slot)
 local character=g_game.getLocalPlayer and g_game.getLocalPlayer()or player
 return call(character,'getInventoryItem',slot)
end
local function owner(c)
 local link=links[call(c,'getId')]
 if link and link.container==c and inventorySlot(link.path.root)==link.root then return link.item end
 if ContainerManager and type(ContainerManager.getContainerSource)=='function'then
  local item=ContainerManager.getContainerSource(c);if item then return item end
 end
 return call(c,'getContainerItem')
end
-- A carried inventory path distinguishes equal-looking backpacks. Container
-- window IDs alone are not persisted because they can change after reconnect.
local function pathFor(item,open,seen,depth)
 if not item or depth>12 or seen[item]then return end;seen[item]=true
 local p=call(item,'getPosition');local id=call(item,'getId')
 if not p or p.x~=65535 or not id then return end
 if p.y>0 and p.y<64 then
  local root=inventorySlot(p.y)
  if root and call(root,'getId')==id and same(call(root,'getPosition'),p)then return{root=p.y,ids={id},slots={}}end
  return
 end
 local parent=containerById(open,p.y-64);if not parent or parent.lootContainer then return end
 local path=pathFor(owner(parent),open,seen,depth+1)
 if not path then return end
 path.slots[#path.slots+1]=p.z;path.ids[#path.ids+1]=id;return path
end
local function pathKey(path)
 if not path then return end
 local out={tostring(path.root)};for i,slot in ipairs(path.slots or{})do out[#out+1]=tostring(slot)..'@'..tostring(path.ids[i+1])end
 return table.concat(out,'/')..':'..tostring(path.ids[1])
end
P.pathKey=pathKey
function P.refKey(ref)
 if not ref then return end
 if ref.kind=='path'then return pathKey(ref.path)end
 if ref.kind=='window'then return tostring(ref.session)..':'..tostring(ref.token)end
 return ref.kind
end
local function samePath(a,b)return pathKey(a)~=nil and pathKey(a)==pathKey(b)end
local function containerPath(c,open)
 local path=pathFor(owner(c),open,{},0)
 if path then return path end
 local link=links[call(c,'getId')]
 if link and link.container==c and inventorySlot(link.path.root)==link.root then return P.copy(link.path)end
end
-- Open packets can contain a detached header item. Bind the window only after
-- observing the actual carried item before use and its unambiguous Open reply.
function P.observeUse(position,id)
 for key,receipt in pairs(openReceipts)do if time()>receipt.expires then openReceipts[key]=nil end end
 if not position or position.x~=65535 then return end
 local open=allContainers();local item
 if position.y>0 and position.y<64 then item=inventorySlot(position.y)
 elseif position.y>=64 then
  local parent=containerById(open,position.y-64)
  if parent and containerPath(parent,open)then
   for _,candidate in ipairs(call(parent,'getItems')or{})do
    if call(candidate,'getId')==id and same(call(candidate,'getPosition'),position)then item=candidate;break end
   end
  end
 end
 if not item or call(item,'getId')~=id or call(item,'isContainer')~=true then return end
 local path=pathFor(item,open,{},0);if not path then return end
 local prior=openReceipts[id]
 if prior and(prior.ambiguous or prior.item~=item)then
  openReceipts[id]={ambiguous=true,expires=time()+2500};return
 end
 local before={};for _,c in pairs(open)do before[call(c,'getId')]=c end
 openReceipts[id]={item=item,path=path,root=inventorySlot(path.root),before=before,expires=time()+2500}
end
function P.observeOpen(c,previous)
 if not c or c.lootContainer then return end
 local id=call(call(c,'getContainerItem'),'getId');local receipt=openReceipts[id]
 if receipt and not receipt.ambiguous and time()<=receipt.expires and receipt.before[call(c,'getId')]~=c and inventorySlot(receipt.path.root)==receipt.root then
  links[call(c,'getId')]={container=c,item=receipt.item,path=receipt.path,root=receipt.root}
  openReceipts[id]=nil;managedFrame=nil
 end
end
if type(onUse)=='function'then onUse(P.observeUse)end
if type(onContainerOpen)=='function'then onContainerOpen(P.observeOpen)end
if type(onContainerClose)=='function'then onContainerClose(function(c)
 local id=call(c,'getId');local link=links[id]
 if link and link.container==c then links[id]=nil;managedFrame=nil end
 local binding=windowBindings[id]
 if binding and binding.container==c then windowBindings[id]=nil;managedFrame=nil end
end)end
function P.options()
 local out={{text='Destinos anteriores',ref={kind='legacy'}},{text='Mochila principal',ref={kind='main'}}}
 local open=allContainers();local rows={}
 for _,c in pairs(open)do
  if not c.lootContainer then
   local item=owner(c);local path=containerPath(c,open)
   if path then rows[#rows+1]={container=c,path=path,item=item}
   else
    local position=call(item,'getPosition');local id=call(c,'getId');local itemId=call(item,'getId')
    -- An Open packet may omit the header's inventory position. Let the user
    -- explicitly select that live window, without rebinding it by ID later.
    if position and position.x==65535 and itemId and call(types(itemId),'isContainer')==true then
     local binding=windowBindings[id]
     if not binding or binding.container~=c then
      windowSerial=windowSerial+1;binding={container=c,token=windowSerial};windowBindings[id]=binding
     end
     local label=P.name(itemId)..' # '..id..' (sesion)'
     out[#out+1]={text=label,ref={kind='window',window=id,id=itemId,session=session,token=binding.token,label=label},container=c}
    end
   end
  end
 end
 table.sort(rows,function(a,b)return pathKey(a.path)<pathKey(b.path)end)
 for _,row in ipairs(rows)do
  local label=P.name(call(row.item,'getId'))..' ['..pathKey(row.path)..']'
  out[#out+1]={text=label,ref={kind='path',path=row.path,id=call(row.item,'getId'),label=label},container=row.container}
 end
 return out
end
function P.refEqual(a,b)
 if not a or not b then return a==b end
 if a.kind~=b.kind then return false end
 return P.refKey(a)==P.refKey(b)
end
function P.refLabel(ref)
 if not ref or ref.kind=='none'then return 'Sin asignar'end
 if ref.kind=='legacy'then return 'Destinos anteriores'end
 if ref.kind=='main'then return 'Mochila principal'end
 return ref.label or('ID '..tostring(ref.id))
end
local function resolve(ref,open,cfg)
 local out={};if not ref then return out end
 for _,c in pairs(open)do
  if not c.lootContainer then
   local item=owner(c);local matched=false
   if ref.kind=='path'then matched=samePath(containerPath(c,open),ref.path)
   elseif ref.kind=='window'then
    local binding=windowBindings[ref.window]
    matched=ref.session==session and binding and binding.token==ref.token and binding.container==c and call(c,'getId')==ref.window
   elseif ref.kind=='main'then
    local main=inventorySlot(SlotBack or InventorySlotBack or 3)
    matched=item==main or(main and same(call(item,'getPosition'),call(main,'getPosition'))and call(item,'getId')==call(main,'getId'))
   elseif ref.kind=='legacy'then
    local p=call(item,'getPosition')
    if containerPath(c,open)or p and p.x==65535 then
     for _,entry in ipairs(cfg.legacy or{})do if call(item,'getId')==entry.id then matched=true;break end end
    end
   end
   if matched then out[#out+1]=c end
  end
 end
 table.sort(out,function(a,b)return(call(a,'getId')or 0)<(call(b,'getId')or 0)end)
 return out
end
P.resolve=resolve
function P.destinationRefs(id,cfg)
 local refs,used={},{}
 local function add(ref)
  if not ref then return end
  local k=P.refKey(ref)
  if not used[k]then used[k]=true;refs[#refs+1]=ref end
 end
 add((cfg.overrides or{})[tostring(id)])
 add((cfg.categories or{})[P.category(id)])
 add((cfg.categories or{}).unassigned)
 if cfg.fallback then add(cfg.main)end
 return refs
end
function P.space(ref,cfg)
 local total,found=0,false
 for _,c in ipairs(resolve(ref,allContainers(),cfg))do
  found=true;total=total+math.max(0,(call(c,'getCapacity')or 0)-(call(c,'getItemsCount')or 0))
 end
 return found and tostring(total)or'--'
end
function P.destination(item,cfg)
 local id=call(item,'getId');local open=allContainers()
 for _,ref in ipairs(P.destinationRefs(id,cfg))do
  for _,c in ipairs(resolve(ref,open,cfg))do
   if call(item,'isStackable')then
    for slot,other in ipairs(call(c,'getItems')or{})do
     if call(other,'getId')==id and(call(other,'getCount')or 0)<100 then
      return c,call(c,'getSlotPosition',slot-1),math.min(call(item,'getCount')or 1,100-(call(other,'getCount')or 0))
     end
    end
   end
   if(call(c,'getItemsCount')or 0)<(call(c,'getCapacity')or 0)then
    return c,call(c,'getSlotPosition',call(c,'getItemsCount')or 0),math.max(1,call(item,'getCount')or 1)
   end
  end
 end
 return nil
end
local function unchanged(job)
 local source=containerById(allContainers(),job.source)
 if not source or source~=job.sourceObject then return nil end
 for _,item in ipairs(call(source,'getItems')or{})do
  if call(item,'getId')==job.id and same(call(item,'getPosition'),job.pos)and(call(item,'getCount')or 1)>=job.count then return true end
 end
 return false
end
local function destinationCount(container,id)
 local amount=0
 for _,item in ipairs(call(container,'getItems')or{})do if call(item,'getId')==id then amount=amount+(call(item,'getCount')or 1)end end
 return amount
end
function P.waiting()
 if not pending then return false end
 local state=unchanged(pending)
 if state~=true then
  local destination=containerById(allContainers(),pending.destination)
  local confirmed=state==false and destination==pending.destObject and destinationCount(destination,pending.id)>=pending.destCount+pending.amount
  P.message=confirmed and'Movimiento confirmado'or'El origen cambio; destino sin confirmar'
  pending=nil;return false
 end
 if time()<pending.untilAt then return true end
 P.message='Movimiento sin confirmar; reintento limitado';pending=nil;return false
end
function P.move(item,source)
 if P.waiting()then return true end
 local id=call(item,'getId');if not id or not P.validId(id)then return false end
 local origin=call(item,'getPosition');local sourceId=call(source,'getId')
 if not origin or origin.x~=65535 or sourceId==nil then return false end
 local bucket=failures[sourceId]
 if not bucket or bucket.container~=source then bucket={container=source,items={}};failures[sourceId]=bucket end
 local k=id..':'..origin.z..':'..tostring(call(item,'getCount')or 1)
 local tried=bucket.items[k]or 0;if tried>=3 then P.message='No se pudo recoger '..P.name(id);return false end
 local cfg=P.current();local dest,position,count=P.destination(item,cfg)
 if not dest or not position then P.message='Sin espacio o destino abierto: '..P.name(id);return false end
 local snapshot={source=sourceId,sourceObject=source,id=id,pos={x=origin.x,y=origin.y,z=origin.z},count=call(item,'getCount')or 1,untilAt=time()+1200,
  destination=call(dest,'getId'),destObject=dest,destCount=destinationCount(dest,id),amount=count}
 bucket.items[k]=tried+1
 local ok,result=pcall(g_game.move,item,position,count)
 if not ok or result==false then P.message='El cliente rechazo el movimiento';return false end
 pending=snapshot;P.message='Recogiendo '..P.name(id);return true
end
function P.reset()pending,failures=nil,{};managedFrame=nil;P.message=''end
function P.isManagedItem(item,source)
 if not P.active()or not P.accepts(call(item,'getId'))then return false end
 local cfg=P.current()
 if not managedFrame or managedFrame.time~=time()or managedFrame.cfg~=cfg then
  managedFrame={time=time(),cfg=cfg,refs={}}
  local open=allContainers()
  local function remember(ref)
   if not ref then return end
   local key=P.refKey(ref)
   if not managedFrame.refs[key]then
    local found={};for _,c in ipairs(resolve(ref,open,cfg))do found[call(c,'getId')]=c end
    managedFrame.refs[key]=found
   end
  end
  for _,ref in pairs(cfg.categories or{})do remember(ref)end
  for _,ref in pairs(cfg.overrides or{})do remember(ref)end
  if cfg.fallback then remember(cfg.main)end
 end
 for _,ref in ipairs(P.destinationRefs(call(item,'getId'),cfg))do
  local key=P.refKey(ref)
  if managedFrame.refs[key]and managedFrame.refs[key][call(source,'getId')]==source then return true end
 end
 return false
end
