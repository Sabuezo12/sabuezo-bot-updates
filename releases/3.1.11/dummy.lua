addSeparator()
setDefaultTab('Main')
local key='Dummy Train Smart'
if type(storage[key])~='table'then storage[key]={id=28557,id2=28559,enabled=false}end
local config=storage[key]
local function normalizeList(name,legacy)
  if type(config[name])~='table'then config[name]={{id=tonumber(config[legacy])or 0,enabled=true}}end
  for i,value in ipairs(config[name])do
    if type(value)~='table'then value={id=tonumber(value)or 0,enabled=true};config[name][i]=value end
    value.id=tonumber(value.id)or 0;if value.enabled==nil then value.enabled=true end
  end
end
normalizeList('items','id');normalizeList('dummies','id2')
config.range=math.max(1,math.min(7,tonumber(config.range)or 7))
config.waitSeconds=math.max(30,math.min(120,tonumber(config.waitSeconds)or 30))
config.retrySeconds=math.max(3,math.min(15,tonumber(config.retrySeconds)or 3))
if config.onlyPz==nil then config.onlyPz=false end
config.enabled=config.enabled==true
local ui=setupUI([[
Panel
  height: 46
  HelperThemePower
    id: title
    anchors.left: parent.left
    anchors.top: parent.top
    width: 130
    height: 20
    text: Dummy Smart
  HelperThemeButton
    id: setup
    anchors.left: title.right
    anchors.right: parent.right
    anchors.top: title.top
    height: 20
    margin-left: 4
    text: Configurar
  HelperThemeLabel
    id: status
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: title.bottom
    height: 24
    text-wrap: true
    color: #aaaaaa
    text: Apagado
]],parent)
ui:setId(key)
if Helper and Helper.valid()then Helper.record(ui,'DummySmartPanel',false,'dummy')end
local state={phase='idle',stationaryUntil=0,nextAt=0,player=player,pos=nil,online=false}
local pairFailures,itemFailures,dummyFailures={},{},{}
local window,refreshLists
local cachedDummies,scanAt={},0
local function clock()return tonumber(now)or 0 end
local function call(object,method,...)
  if not object or type(object[method])~='function'then return nil end
  local ok,v=pcall(object[method],object,...);if ok then return v end
end
local function position(p)return p and{x=p.x,y=p.y,z=p.z}end
local function same(a,b)return a and b and a.x==b.x and a.y==b.y and a.z==b.z end
local function online()
  if g_game and type(g_game.isOnline)=='function'then local ok,v=pcall(g_game.isOnline);return ok and v==true end
  return player~=nil
end
local function status(text,color)
  color=color or'#aaaaaa'
  if state.message~=text or state.color~=color then
    state.message,state.color=text,color;ui.status:setText(text);ui.status:setColor(color);ui.status:setTooltip(text)
    if window then window.status:setText(text);window.status:setColor(color)end
  end
end
local function resetWait(reason)
  state.phase='idle';state.current=nil;state.deadline=nil;state.startedAt=nil
  state.pos=position(call(player,'getPosition'));state.player=player;state.online=online()
  state.stationaryUntil=clock()+config.waitSeconds*1000;state.nextAt=state.stationaryUntil
  cachedDummies={};scanAt=0
  status(reason..': '..config.waitSeconds..'s','#ffd166')
end
local function legacyIds()
  config.id=config.items[1]and config.items[1].id or 0
  config.id2=config.dummies[1]and config.dummies[1].id or 0
end
local function listChanged()
  legacyIds();cachedDummies={};scanAt=0;pairFailures={};itemFailures={};dummyFailures={}
  -- Editing priorities affects the next attempt, never an active session.
  if state.phase=='idle'then state.nextAt=math.max(clock(),state.stationaryUntil)end
end
local function itemKey(item)
  local p=call(item,'getPosition');local id=call(item,'getId')
  if not id or not p or p.x~=65535 or p.y<=0 then return nil end
  return id..':'..p.x..':'..p.y..':'..p.z
end
local function availableItems()
  local byId,seen,purseKeys,purseItems={},{},{},{}
  local purse
  if type(getPurse)=='function'then local ok,value=pcall(getPurse);if ok then purse=value end end
  purse=purse or call(player,'getInventoryItem',SlotPurse or InventorySlotPurse or 11)
  local purseId=tonumber(call(purse,'getId'))
  if not purseId or purseId<=100 then purse=nil end
  local containers={}
  if g_game and type(g_game.getContainers)=='function'then
    local ok,value=pcall(g_game.getContainers);if ok and type(value)=='table'then containers=value end
  end
  local visited,walked={},0
  local function ordered(items)
    local keys={};for index in pairs(items)do keys[#keys+1]=index end
    table.sort(keys,function(a,b)
      if type(a)=='number'and type(b)=='number'then return a<b end
      return tostring(a)<tostring(b)
    end)
    return keys
  end
  local function add(item,owned,path)
    local id=tonumber(call(item,'getId'));local physical=itemKey(item)
    if not id or id<=100 then return end
    if owned then
      purseItems[item]=true;if physical then purseKeys[physical]=true end
    end
    -- Only items actually observed inside the carried purse may use the
    -- hotkey/ID path. Arbitrary ground or findItem results stay rejected.
    local k=physical or(owned and('purse:'..path..':'..id))
    if not k then return end
    for _,source in ipairs(byId[id]or{})do
      if source.item==item or source.key==k then
        source.purse=source.purse or owned==true
        if physical and source.byId then
          seen[source.key]=nil;source.item,source.key,source.byId=item,physical,false;seen[physical]=true
        end
        return
      end
    end
    if seen[k]then return end
    seen[k]=true;byId[id]=byId[id]or{}
    byId[id][#byId[id]+1]={item=item,key=k,id=id,purse=owned==true,byId=not physical}
  end
  local function visit(item,path,depth)
    if not item or visited[item]or walked>=512 or depth>4 then return end
    visited[item]=true;walked=walked+1
    add(item,true,path)
    -- Mythic's Item binding exposes embedded purse contents here. These
    -- objects need not belong to a normal g_game container or position.
    local contents=call(item,'getContainerItems')
    if type(contents)=='table'then
      for _,index in ipairs(ordered(contents))do visit(contents[index],path..'/'..tostring(index),depth+1)end
    end
  end
  if purse then visit(purse,'slot',0)end
  local scanned={}
  for pass=1,4 do
    local changed=false
    for containerId,container in pairs(containers)do
      if not scanned[container]then
        local owner=call(container,'getContainerItem');local ownerKey=itemKey(owner)
        local root=purse and owner and(owner==purse or call(owner,'getId')==purseId)
        local owned=owner and(purseItems[owner]or ownerKey and purseKeys[ownerKey])
        if not owned and owner then
          for item in pairs(purseItems)do if item==owner then owned=true;break end end
        end
        if root or owned then
          scanned[container]=true;changed=true
          local items=call(container,'getItems')
          if type(items)=='table'then
            for _,index in ipairs(ordered(items))do visit(items[index],'container'..tostring(containerId)..'/'..tostring(index),1)end
          end
        end
      end
    end
    if not changed then break end
  end
  for _,container in pairs(containers)do
    local items=call(container,'getItems')
    if type(items)=='table'then for _,item in pairs(items)do add(item,false)end end
  end
  if player and type(player.getInventoryItem)=='function'then for slot=1,11 do add(call(player,'getInventoryItem',slot),false)end end
  local out,ids={},{}
  for _,entry in ipairs(config.items)do
    if entry.enabled and entry.id>100 and not ids[entry.id]then
      ids[entry.id]=true
      if not byId[entry.id]and type(findItem)=='function'then local ok,item=pcall(findItem,entry.id);if ok then add(item,false)end end
      local items=byId[entry.id]or{}
      table.sort(items,function(a,b)return a.key<b.key end)
      for _,item in ipairs(items)do
        local blocked=itemFailures[item.key]
        if not blocked or blocked.item~=item.item or clock()>=blocked.untilAt then out[#out+1]=item end
      end
    end
  end
  return out
end

local function targets(p)
  if clock()<scanAt then return cachedDummies end
  scanAt=clock()+2000;cachedDummies={}
  local order={}
  for i,entry in ipairs(config.dummies)do if entry.enabled and entry.id>100 and not order[entry.id]then order[entry.id]=i end end
  local radius=config.range
  for dx=-radius,radius do for dy=-radius,radius do
    local tile=g_map and g_map.getTile and g_map.getTile({x=p.x+dx,y=p.y+dy,z=p.z})
    if tile then for _,item in ipairs(tile:getItems())do
      local id=call(item,'getId');local rank=id and order[id]
      local at=call(item,'getPosition')
      if rank and at and at.x==p.x+dx and at.y==p.y+dy and at.z==p.z then
        cachedDummies[#cachedDummies+1]={item=item,id=id,pos=position(at),rank=rank,distance=math.max(math.abs(dx),math.abs(dy)),key=id..':'..at.x..':'..at.y..':'..at.z}
      end
    end end
  end end
  table.sort(cachedDummies,function(a,b)
    if a.rank~=b.rank then return a.rank<b.rank end
    if a.distance~=b.distance then return a.distance<b.distance end
    return a.key<b.key
  end)
  while #cachedDummies>32 do table.remove(cachedDummies)end
  return cachedDummies
end
local function liveTarget(candidate,p)
  local at=candidate.pos
  if at.z~=p.z or math.max(math.abs(at.x-p.x),math.abs(at.y-p.y))>config.range then return nil end
  local tile=g_map and g_map.getTile and g_map.getTile(at)
  if tile then for _,item in ipairs(tile:getItems())do if call(item,'getId')==candidate.id then return item end end end
end
local function retry(reason,kind,duration)
  local current=state.current;duration=duration or 30000
  if current then
    if kind=='item'then itemFailures[current.exercise.key]={item=current.exercise.item,untilAt=clock()+duration}
    elseif kind=='dummy'then dummyFailures[current.dummy.key]=clock()+duration
    else pairFailures[current.key]=clock()+duration end
  end
  state.phase='idle';state.current=nil;state.deadline=nil
  state.nextAt=math.max(clock()+config.retrySeconds*1000,state.stationaryUntil)
  status(reason..'; probando alternativa','#ffd166')
end
local function contains(text,list)
  for _,value in ipairs(list)do if text:find(value,1,true)then return true end end
  return false
end
onTextMessage(function(_,text)
  if not config.enabled or type(text)~='string'then return end
  local lower=text:lower()
  if contains(lower,{'you started training','you have started training','you are already training','you are now training','comenzaste a entrenar','has comenzado a entrenar','começou a treinar','comecou a treinar'})then
    if state.phase~='training'then state.startedAt=clock()end
    state.phase='training';state.deadline=nil;status('Entrenamiento confirmado','#8cff9a');return
  end
  if state.phase~='waiting'and state.phase~='training'then return end
  if contains(lower,{'ran out of charges','no charges left','exercise weapon has disappeared','exercise weapon broke','exercise weapon is no longer usable','training weapon has disappeared','training weapon broke'})then
    retry('Item agotado','item',60000);return
  end
  if contains(lower,{'dummy is being used','dummy is already being used','dummy is already in use','someone else is using','dummy can only be used after','too many players are using'})then
    retry('Dummy ocupado o en espera','dummy',30000);return
  end
  if contains(lower,{'cannot use this object','can not use this object','not possible','not enough room','too far away','you cannot use this item'})and state.phase=='waiting'then
    retry('Uso rechazado','pair');return
  end
  if contains(lower,{'training has ended','training ended','training finished','finished training','treino terminou','entrenamiento termino','entrenamiento terminó','entrenamiento finalizo','entrenamiento finalizó'})then
    state.phase='idle';state.current=nil;state.startedAt=nil;state.nextAt=clock()+config.retrySeconds*1000
    cachedDummies={};scanAt=0;status('Entrenamiento finalizado; buscando item','#ffd166');return
  end
  if contains(lower,{'training has stopped','you stopped training','you have stopped training','you stop training','you are no longer training','training interrupted','training has been interrupted','training canceled','training cancelled','you canceled training','you cancelled training','you must wait 30 seconds','wait 30 seconds','30 seconds cooldown','treino cancelado','treino interrompido','parou de treinar','deixou de treinar','dejaste de entrenar','entrenamiento cancelado','entrenamiento interrumpido'})then
    resetWait('Entrenamiento interrumpido')
  end
end)
local function poll()
  if not config.enabled then status('Apagado');return end
  local connected=online()
  if not connected then
    if state.online then resetWait('Desconexion')end
    state.online=false;status('Desconectado');return
  end
  local p=call(player,'getPosition')
  if not p then status('Sin personaje');return end
  if not state.online or player~=state.player then resetWait('Conexion')end
  if state.pos and not same(state.pos,p)then resetWait('Movimiento')end
  state.pos=position(p);state.player=player;state.online=true
  if call(player,'getHealthPercent')==0 then resetWait('Personaje muerto');return end
  if state.phase=='training'then
    local seconds=math.floor((clock()-(state.startedAt or clock()))/1000)
    status(string.format('Entrenando %02d:%02d:%02d',math.floor(seconds/3600),math.floor(seconds/60)%60,seconds%60),'#8cff9a');return
  end
  if state.phase=='waiting'then
    if clock()<(state.deadline or 0)then status('Confirmando inicio: '..math.ceil((state.deadline-clock())/1000)..'s','#ffd166')
    else retry('Sin confirmacion','pair')end
    return
  end
  if clock()<state.nextAt then status('Espera: '..math.ceil((state.nextAt-clock())/1000)..'s','#ffd166');return end
  for key,untilAt in pairs(pairFailures)do if clock()>=untilAt then pairFailures[key]=nil end end
  for key,untilAt in pairs(dummyFailures)do if clock()>=untilAt then dummyFailures[key]=nil end end
  for key,failure in pairs(itemFailures)do if clock()>=failure.untilAt then itemFailures[key]=nil end end
  if config.onlyPz and(type(isInPz)~='function'or not isInPz())then status('Esperando estar en PZ','#ffd166');return end
  if g_game and type(g_game.isAttacking)=='function'and g_game.isAttacking()then status('Esperando terminar el ataque','#ffd166');return end
  if PushMax and type(PushMax.isCoordinatingItems)=='function'and PushMax.isCoordinatingItems()then status('Esperando terminar Push Max','#ffd166');return end
  local exercises=availableItems()
  if #exercises==0 then status('Sin item de entrenamiento en BP/purse','#ff8888');state.nextAt=clock()+3000;return end
  local candidates=targets(p)
  if #candidates==0 then status('Sin dummy configurado en alcance','#ff8888');state.nextAt=clock()+3000;return end
  for _,exercise in ipairs(exercises)do for _,dummy in ipairs(candidates)do
    local pairKey=exercise.key..'|'..dummy.key
    if clock()>=(pairFailures[pairKey]or 0)and clock()>=(dummyFailures[dummy.key]or 0)then
      local target=liveTarget(dummy,p)
      if target then
        state.current={exercise=exercise,dummy=dummy,key=pairKey};state.phase='waiting';state.deadline=clock()+5000
        local subtype=0;if g_game.getClientVersion and g_game.getClientVersion()<860 then subtype=1 end
        local ok,result
        if exercise.byId and type(g_game.useInventoryItemWith)=='function'then ok,result=pcall(g_game.useInventoryItemWith,exercise.id,target,subtype)
        elseif type(g_game.useWith)=='function'then ok,result=pcall(g_game.useWith,exercise.item,target,subtype)
        elseif type(g_game.useInventoryItemWith)=='function'then ok,result=pcall(g_game.useInventoryItemWith,exercise.id,target,subtype)
        elseif type(useWith)=='function'then ok,result=pcall(useWith,exercise.id,target,subtype)end
        if not ok or result==false then retry('No se pudo usar el item','pair')
        elseif state.phase=='waiting'then status('Confirmando: item '..exercise.id..(exercise.purse and' (purse)'or'')..' / dummy '..dummy.id,'#ffd166')end
        return
      end
    end
  end end
  state.nextAt=clock()+3000;status('Opciones en espera; reintentando por prioridad','#ffd166')
end
local function setEnabled(value)
  local changed=config.enabled~=(value==true)
  config.enabled=value==true;ui.title:setOn(config.enabled)
  if window then window.master:setOn(config.enabled)end
  if not changed then return end
  if config.enabled then resetWait('Activado')else state.phase='idle';state.current=nil;status('Apagado')end
end
setDummySmartOn=function()setEnabled(true)end
setDummySmartOff=function()setEnabled(false)end
local function bindList(name,panel)
  panel.list:destroyChildren()
  for index,entry in ipairs(config[name])do
    local row=UI.createWidget('DummySmartEntry',panel.list)
    row.rank:setText(index);row.item:setItemId(entry.id);row.enabled:setChecked(entry.enabled)
    row.description:setText(entry.id>100 and tostring(entry.id)or'Arrastra item')
    row.item.onItemChange=function(widget)entry.id=widget:getItemId();row.description:setText(tostring(entry.id));listChanged()end
    row.enabled.onClick=function(widget)entry.enabled=not entry.enabled;widget:setChecked(entry.enabled);listChanged()end
    row.up:setEnabled(index>1);row.down:setEnabled(index<#config[name])
    row.up.onClick=function()if index>1 then config[name][index],config[name][index-1]=config[name][index-1],entry;listChanged();refreshLists()end end
    row.down.onClick=function()if index<#config[name]then config[name][index],config[name][index+1]=config[name][index+1],entry;listChanged();refreshLists()end end
    row.remove.onClick=function()table.remove(config[name],index);listChanged();refreshLists()end
  end
  panel.add:setEnabled(#config[name]<32)
  panel.add.onClick=function()if #config[name]<32 then table.insert(config[name],{id=0,enabled=true});listChanged();refreshLists()end end
end
refreshLists=function()
  if window then
    bindList('items',window.items);bindList('dummies',window.dummies)
    window:setHeight(140+32*math.max(1,math.min(4,math.max(#config.items,#config.dummies))))
  end
end
-- Fixed world objects need not be draggable. Inspect the cursor tile only;
-- this tool never changes dummy priorities or sends an item/game action.
local identifyUnderCursor
local readingId=false
local function currentInspector()
  return DummySmart and DummySmart.identifyUnderCursor==identifyUnderCursor and window and call(window,'isDestroyed')~=true
end
local function identificationResult(label,message)
  if not currentInspector()then return end
  window.inspectId:setText(label);window.inspectId:setTooltip(message)
  if RinoConsole and type(RinoConsole.log)=='function'then
    RinoConsole.log('info','Dummy Smart',message)
  else print('[Dummy Smart] '..message)end
  -- A local readout lets support inspect the exact client IDs afterwards.
  -- Report failure never prevents the on-screen/console result.
  if type(configDir)=='string'and g_resources and type(g_resources.writeFileContents)=='function'then
    pcall(function()
      local directory=configDir..'/_diagnostics'
      if not g_resources.directoryExists(directory)then g_resources.makeDir(directory)end
      g_resources.writeFileContents(directory..'/dummy-identification.txt',message..'\n')
    end)
  end
end
identifyUnderCursor=function()
  if not currentInspector()then return false end
  if not online()then identificationResult('Sin conexion','Conectate y vuelve a pulsar Leer ID.');return false end
  if type(getTileUnderCursor)~='function'then
    identificationResult('No disponible','Este cliente no expone la lectura de la casilla bajo el cursor.');return false
  end
  local ok,tile=pcall(getTileUnderCursor)
  if not ok or not tile then
    identificationResult('Apunta al mapa','No se pudo leer la casilla. Pulsa Leer ID y apunta a la base de la estatua.');return false
  end
  local ground=call(tile,'getGround');local groundId=call(ground,'getId')
  local ids,seen={},{}
  for _,item in ipairs(call(tile,'getItems')or{})do
    local id=tonumber(call(item,'getId'))
    if id and id>100 and id~=groundId and call(item,'isGround')~=true and not seen[id]then
      seen[id]=true;ids[#ids+1]=id
    end
  end
  if #ids==0 then
    identificationResult('Sin objeto','La casilla no contiene un objeto identificable. Apunta a la base de la estatua, no a su parte alta.');return false
  end
  local p=call(tile,'getPosition')
  local where=p and(' | casilla '..p.x..','..p.y..','..p.z)or''
  local label=#ids==1 and('ID '..ids[1])or(#ids..' IDs; ver ayuda')
  local message='Objetos bajo el cursor: '..table.concat(ids,', ')..where
  if #ids>1 then message=message..' | Hay varios objetos; estos IDs no identifican por si solos cual es la estatua.'end
  identificationResult(label,message)
  return ids
end

local root=g_ui.getRootWidget()
if root then
  local old=root:recursiveGetChildById('DummySmartWindow');if old then old:destroy()end
  window=UI.createWindow('DummySmartWindow',root);window:hide();refreshLists()
  for _,entry in ipairs({{'range',1,7},{'waitSeconds',30,120},{'retrySeconds',3,15}})do
    local name=entry[1];local widget=window.options[name];widget:setValue(config[name])
    widget.onValueChange=function(_,value)
      config[name]=math.max(entry[2],math.min(entry[3],tonumber(value)or entry[2]));cachedDummies={};scanAt=0
    end
  end
  window.options.onlyPz:setChecked(config.onlyPz)
  window.options.onlyPz.onClick=function(widget)config.onlyPz=not config.onlyPz;widget:setChecked(config.onlyPz)end
  window.master:setOn(config.enabled);window.master.onClick=function()setEnabled(not config.enabled)end
  window.retry.onClick=function()
    if state.phase=='training'or state.phase=='waiting'then return end
    pairFailures={};itemFailures={};dummyFailures={};scanAt=0;state.nextAt=math.max(clock(),state.stationaryUntil)
  end
  window.inspectId.onClick=function()
    if readingId or not currentInspector()then return false end
    readingId=true;window.inspectId:setEnabled(false);window.inspectId:setText('Apunta (3s)')
    window.inspectId:setTooltip('Coloca el cursor sobre la base de la estatua; la lectura se hara en 3 segundos.')
    schedule(3000,function()
      if not currentInspector()then return end
      readingId=false;window.inspectId:setEnabled(true);identifyUnderCursor()
    end)
    return true
  end
  window.closeButton.onClick=function()window:hide()end
end
ui.title:setOn(config.enabled);ui.title.onClick=function()setEnabled(not config.enabled)end
ui.setup.onClick=function()if window then refreshLists();window:show();window:raise();window:focus()end end
onPlayerPositionChange(function(p,old)
  if config.enabled and not same(p,old)then resetWait('Movimiento')end
  state.pos=position(p)
end)
DummySmart={identifyUnderCursor=identifyUnderCursor,isOn=function()return config.enabled end,setOn=setDummySmartOn,setOff=setDummySmartOff,show=function()ui.setup.onClick()end,
  getStatus=function()return{enabled=config.enabled,phase=state.phase,message=state.message,items=#config.items,dummies=#config.dummies}end}
dummySmart=macro(1000,poll)
state.online=online();state.player=player;state.pos=position(call(player,'getPosition'))
if config.enabled then resetWait('Recarga')else status('Apagado')end
