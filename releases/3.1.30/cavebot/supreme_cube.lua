-- Supreme Cube uses ordinary server modal choices. IDs are read from each
-- response, never guessed from the destination's order in the client catalog.
CaveBot.Extensions.SupremeCube={}
local S=CaveBot.Extensions.SupremeCube
CaveBot.SupremeCube=S
S.ITEM_ID=31633
S.sections={{id='Cities',text='Ciudades'},{id='Bosses',text='Jefes / bosses'},
 {id='Trainer',text='Entrenamiento'},{id='House',text='Casa / guild hall'}}
local function trim(s)return tostring(s or''):match('^%s*(.-)%s*$')end
local function key(s)return trim(s):lower()end
local function point(p)return p and{x=p.x,y=p.y,z=p.z}end
local function distance(a,b)return a and b and a.z==b.z and math.max(math.abs(a.x-b.x),math.abs(a.y-b.y))or math.huge end
function S.decode(value)
 if type(value)~='string'or #value>180 or value:find('%c')then return nil,'Destino del cubo invalido.'end
 local category,dest=value:match('^%s*([^,]+),%s*([^,]+)%s*$')
 if not category then return nil,'Elige una categoria y un destino para el Supreme Cube.'end
 local section
 for _,entry in ipairs(S.sections)do if key(category)==key(entry.id)then section=entry.id end end
 dest=trim(dest)
 if not section or dest==''or #dest>100 then return nil,'Categoria o destino del cubo invalido.'end
 if section=='Trainer'then
  if key(dest)~='trainer'then return nil,'En Entrenamiento el destino es Trainer.'end;dest='Trainer'
 elseif section=='House'then
  if key(dest)=='house'then dest='House'
  elseif key(dest)=='guild hall'then dest='Guild Hall'
  else return nil,'En Casa elige House o Guild Hall.'end
 end
 return{category=section,destination=dest}
end
function S.encode(c)
 local value=tostring(c and c.category or'')..', '..trim(c and c.destination)
 local config,message=S.decode(value)
 return config and(config.category..', '..config.destination)or nil,message
end
local function entries(rows)
 if type(rows)~='table'or #rows>255 then return end
 local result,seen={},{ }
 for _,row in ipairs(rows)do
  local id,text=type(row)=='table'and tonumber(row[1]or row.id),type(row)=='table'and(row[2]or row.text)
  if not id or id<0 or id>255 or id%1~=0 or seen[id]or type(text)~='string'or #text>240 then return end
  seen[id]=true;result[#result+1]={id=id,text=text}
 end
 return result
end
local function find(rows,name)
 local found
 for _,row in ipairs(rows)do
  if key(row.text)==key(name)then if found~=nil then return nil,'ambiguous'end;found=row.id end
 end
 return found
end
-- Isolated state machine; the host owns inventory/network/UI access.
function S.new(host)
 local C={cooldownUntil=0,arrivals={}}
 local job,lastTime
 local function status(text)
  if C.status~=text then C.status=text;if host.status then host.status(text)end end
 end
 local function current(j)return j and host.context()==j.context and host.owner()==j.owner and host.active()end
 local function reset()job=nil;C.job=nil end
 function C.reset()reset()end
 function C.ownDialog(dialog)
  if current(job)and job.modal and dialog then job.ownedDialog=dialog end
 end
 function C.teleport(actor,pos,oldPos)
  local t=host.time()
  if not current(job)or job.stage~='confirm'or t<job.sentAt or t>job.deadline or not pos or not oldPos then return false end
  local ok,id=pcall(function()return actor:getId()end)
  if not ok or id~=job.owner or distance(oldPos,job.origin)>1 then return false end
  job.teleported=point(pos);return true
 end
 function C.isTraveling()
  return current(job)and job.stage=='confirm'and host.time()<=job.deadline or false
 end
 function C.receive(id,title,message,buttons,enter,escape,choices)
  local t=host.time()
  if not current(job)or not job.sentAt or t<job.sentAt then return false end
  local waiting=job.stage=='root'or job.stage=='destinations'
  local delayed=waiting and t>job.deadline and t<=job.sentAt+30000
  local late=job.stage=='use'and job.lateStage and t<=job.lateUntil
  local stage=late and job.lateStage or job.stage
  if(stage~='root'and stage~='destinations')or(not late and not delayed and t>job.deadline)then return false end
  if type(id)~='number'or id<0 or id%1~=0 then return false end
  local b,c=entries(buttons),entries(choices)
  if not b or not c then return false end
  local root=title=='Supreme Cube'and message=='Locations'and find(c,'Cities')~=nil and find(c,'Bosses')~=nil and
   find(c,'Trainer')~=nil and find(c,'House')~=nil
  local locations=title=='Locations'and message=='Select a Location'
  if not(root or locations)or find(b,'Select')==nil then return false end
  if root and stage~='root'then return false end
  if locations and stage~='destinations'then return false end
  if locations and job.config.category~='Cities'and job.config.category~='Bosses'then return false end
  if late or delayed then job.stage=stage;job.sentAt=t;job.deadline=t+8000;job.lateStage=nil end
  job.modal={id=id,title=title,buttons=b,choices=c,root=root,at=t}
  if host.dialog then C.ownDialog(host.dialog())end
  return true
 end
 function C.text(message)
  if current(job)and type(message)=='string'and #message<500 then
   local text=message:lower()
   if text:find('supreme',1,true)or text:find('cooldown',1,true)or text:find('exhaust',1,true)or
      text:find('teleport',1,true)then job.reply=message end
  end
 end
 local function retry(text,t,wait,lateStage)
  if host.close then pcall(host.close,job.ownedDialog)end
  job.ownedDialog=nil
  job.lateStage=lateStage;job.lateUntil=job.sentAt and job.sentAt+30000 or t
  job.stage='use';job.modal=nil;job.nextAttempt=t+(wait or 15000)
  status(text);host.delay(500);return'retry'
 end
 function C.run(value,retries)
  local t=host.time()
  if lastTime and t<lastTime then reset();C.cooldownUntil=0 end
  lastTime=t
  local cfg,message=S.decode(value)
  if not cfg then status(message);host.delay(5000);return'retry'end
  local token,owner=host.context(),host.owner()
  if not job or job.value~=value or job.context~=token or job.owner~=owner or retries==0 then
   job={value=value,config=cfg,context=token,owner=owner,stage='use',nextAttempt=t};C.job=job
  end
  if not current(job)then reset();host.delay(500);return'retry'end
  local pos=host.position()
  if not pos then host.delay(500);return'retry'end
  local destination=tostring(owner)..':'..cfg.category..':'..key(cfg.destination)
  if job.stage=='confirm'then
   if job.teleported or distance(pos,job.origin)>=15 then
    C.arrivals[destination]=point(job.teleported or pos);C.cooldownUntil=t+60000
    if host.close then pcall(host.close,job.ownedDialog)end
    status('Llegada confirmada: '..cfg.destination..'.');reset()
    if host.arrived then host.arrived()end
    host.delay(500);return true
   end
   if t<=job.deadline then host.delay(200);return'retry'end
   return retry('No se confirmo el viaje a '..cfg.destination..'. '..(job.reply or'Comprueba cooldown y acceso; reintento en 60 s.'),t,60000)
  end
  if job.stage~='use'and host.foreignModal and host.foreignModal(job)then
   if t>job.deadline then return retry('Otro menu interrumpio el viaje; se reintentara al cerrarlo.',t)end
   host.delay(500);return'retry'
  end
  -- The custom client can open its catalog without forwarding a server modal
  -- to the bot. Select the exact native row and activate its Teleport callback;
  -- the client then owns its category/destination protocol handshake.
  if job.stage=='root'and host.prepareNative then
   local ok,native=pcall(host.prepareNative,cfg)
   if not ok then return retry('No pude preparar el destino en el menu del cubo.',t)end
   if native then
    job.ownedDialog=native.dialog;job.modal=nil
    if native.button then
     job.stage='confirm';job.origin=point(pos);job.sentAt=t;job.deadline=t+15000
     local sent,result=pcall(host.activateNative,native.button)
     if not sent or result==false then return retry('No pude activar Teleport en el Supreme Cube.',t)end
     status('Teleport activado para '..cfg.destination..'; esperando llegada.')
     host.delay(200);return'retry'
    end
    if t>job.deadline then return retry(native.error or'El destino no aparece en el menu del cubo.',t)end
    status('Seleccionando '..cfg.destination..' en el Supreme Cube.');host.delay(200);return'retry'
   end
  end
  if job.stage=='use'then
   -- A just-confirmed arrival can resume after a repeated waypoint without
   -- wasting another use. No city position is inferred from its name.
   if C.arrivals[destination]and distance(pos,C.arrivals[destination])<=1 then
    status('Ya estas en la llegada confirmada: '..cfg.destination..'.');reset();return true
   end
   if t<job.nextAttempt then host.delay(500);return'retry'end
   if t<C.cooldownUntil then status('Esperando cooldown del Supreme Cube.');host.delay(500);return'retry'end
   local blocked=host.blocked and host.blocked()
   if blocked then status(blocked);host.delay(500);return'retry'end
   job.stage='root';job.origin=point(pos);job.sentAt=t;job.deadline=t+8000;job.reply=nil;job.lateStage=nil
   local ok,value=pcall(host.use,S.ITEM_ID)
   if not ok or value==false then return retry('No pude usar el Supreme Cube (31633). Comprueba que lo llevas contigo.',t)end
   status('Abriendo Supreme Cube para '..cfg.destination..'.');host.delay(200);return'retry'
  end
  local modal=job.modal
  if modal then
   job.modal=nil
   job.ownedDialog=(host.dialog and host.dialog())or job.ownedDialog
   local wanted=modal.root and((cfg.category=='Cities'or cfg.category=='Bosses')and cfg.category or cfg.destination)or cfg.destination
   local choice,reason=find(modal.choices,wanted)
   local button=find(modal.buttons,'Select')
   if choice==nil or button==nil then
    return retry(reason=='ambiguous'and('El servidor ofrece varios destinos llamados '..wanted..'; revisa el menu manualmente.')or
     ('El servidor no ofrece '..wanted..' en este menu. Comprueba el destino y los requisitos.'),t,30000)
   end
   local final=not modal.root or(cfg.category~='Cities'and cfg.category~='Bosses')
   local ownedDialog=job.ownedDialog
   job.stage=final and'confirm'or'destinations';job.sentAt=t;job.deadline=t+(final and 10000 or 8000)
   if final then job.origin=point(pos)end
   local ok,value=pcall(host.answer,modal.id,button,choice)
   if not ok or value==false then return retry('No pude confirmar el menu del Supreme Cube.',t)end
   if not final and host.closeCategory then pcall(host.closeCategory,ownedDialog)end
   if final and host.close then pcall(host.close,ownedDialog)end
   status(final and('Esperando llegada a '..cfg.destination..'.')or('Buscando '..cfg.destination..' en el cubo.'))
   host.delay(200);return'retry'
  end
  if t>job.deadline then return retry('El Supreme Cube no respondio. '..(job.reply or'Comprueba el objeto y las restricciones de la zona.'),t,nil,job.stage)end
  host.delay(200);return'retry'
 end
 return C
end

local function modalModule()return modules and modules.game_modaldialog end
local function owner()
 local me=g_game.getLocalPlayer and g_game.getLocalPlayer()or player
 return me and me:getId()
end
local function context()return CaveBot.actionList and CaveBot.actionList:getFocusedChild()end
local function active()
 return(not Helper or Helper.valid())and CaveBot.isOn and CaveBot.isOn()and
  not(HelperPause and HelperPause.isPaused())and not(CaveBot.Flee and CaveBot.Flee.isEscaping())
end
function S.prepareNative(cfg)
 local m=modalModule();local d=m and m.supremeCubeDialog
 if not d or d:isDestroyed()or not d:isVisible()then return end
 local title=d:recursiveGetChildById('cubeTitle')
 if not title or key(title:getText())~='supreme cube'then return end
 local search=d:recursiveGetChildById('destinationSearch')
 local navigation=d:recursiveGetChildById('navigationList')
 local list=d:recursiveGetChildById('supremeChoiceList')
 local button=d:recursiveGetChildById('teleportButton')
 local result={dialog=d,error='El menu del Supreme Cube no esta listo para seleccionar el destino.'}
 if not search or not navigation or not list or not button then return result end
 if search:getText()~=''then search:setText('');return result end
 local category
 for _,entry in ipairs(navigation:getChildren())do if key(entry.category)==key(cfg.category)then category=entry;break end end
 if not category or type(category.onClick)~='function'then return result end
 if not category:isOn()then category.onClick(category);return result end
 local selected
 for _,row in ipairs(list:getChildren())do
  local dest=row.destination
  if type(dest)=='table'and not dest.category and key(dest.name)==key(cfg.destination)and key(dest.section)==key(cfg.category)then
   if selected then result.error='El cubo ofrece mas de un destino con ese nombre.';return result end
   selected=row
  end
 end
 if not selected or type(selected.onClick)~='function'then return result end
 local label=d:recursiveGetChildById('detailName')
 if list:getFocusedChild()~=selected or not label or key(label:getText())~=key(cfg.destination)then selected.onClick(selected)end
 if list:getFocusedChild()~=selected or not label or key(label:getText())~=key(cfg.destination)then return result end
 if not button:isEnabled()or not button:isVisible()or type(button.onClick)~='function'then return result end
 result.button=button;return result
end
local engine=S.new({time=function()return tonumber(now)or 0 end,owner=owner,context=context,active=active,
 position=function()local p=g_game.getLocalPlayer and g_game.getLocalPlayer()or player;return p and point(p:getPosition())end,
 delay=function(ms)CaveBot.delay(ms)end,use=function(id)return use(id)end,
 answer=function(...)return g_game.answerModalDialog(...)end,
 prepareNative=S.prepareNative,
 activateNative=function(button)return button.onClick(button)end,
 blocked=function()
  local m=modalModule()
  if m and(m.modalDialog or m.supremeCubeDialog)then return'Cierra el menu abierto antes de iniciar el viaje con el cubo.'end
  if type(isInFight)=='function'and isInFight()then return'Esperando a salir de combate para usar el Supreme Cube.'end
 end,
 dialog=function()
  local m=modalModule()
  if m and m.supremeCubeDialog then return m.supremeCubeDialog end
  local d=m and m.modalDialog
  if d and(d:getText()=='Supreme Cube'or d:getText()=='Locations')then return d end
 end,
 foreignModal=function(job)
  local m=modalModule();local d=m and m.modalDialog
  if not d or d==job.ownedDialog then return false end
  return not(job.modal and d:getText()==job.modal.title)
 end,
 closeCategory=function(dialog)
  local m=modalModule()
  if dialog and m and m.modalDialog==dialog and type(m.destroyDialog)=='function'then m.destroyDialog()end
 end,
 close=function(dialog)
  local m=modalModule()
  if dialog and m and m.supremeCubeDialog==dialog and type(m.destroySupremeCubeDialog)=='function'then m.destroySupremeCubeDialog(true)
  elseif dialog and m and m.modalDialog==dialog and type(m.destroyDialog)=='function'then m.destroyDialog()end
 end,
 arrived=function()if CaveBot.FloorReturn and CaveBot.FloorReturn.reset then CaveBot.FloorReturn.reset()end end,
 status=function(text)
  S.status=text
  if RinoConsole and RinoConsole.log then pcall(RinoConsole.log,'action','Supreme Cube',text)end
 end})
local function trace(kind,...)if S._trace then pcall(S._trace,kind,engine.job,...)end end
S.run=function(...)
 pcall(S.installTeleportObserver)
 trace('run',S.status)
 return engine.run(...)
end
S.reset=engine.reset;S.isTraveling=engine.isTraveling
if type(onModalDialog)=='function'then onModalDialog(function(...)trace('bot-modal',...);engine.receive(...)end)end
if type(onTextMessage)=='function'then onTextMessage(function(_,text)engine.text(text)end)end
S.onConfigChange=function()engine.reset()end
-- The native walking module confirms short teleports too. Observe its signal;
-- never replace walking, position callbacks, or the native teleport handler.
local observer
function S.installTeleportObserver()
 if observer and not observer.disposed then return true end
 local m=modules and modules.game_walking
 local game=m and m.g_game
 local on,off=m and m.connect,m and m.disconnect
 if not game or type(on)~='function'or type(off)~='function'or not g_ui then return false end
 local root=g_ui.getRootWidget()
 local previous=root._rinoCubeTeleportObserver
 if previous and previous.dispose then previous.dispose()end
 local o={}
 o.callback=function(...)if not o.disposed then engine.teleport(...)end end
 o.dispose=function()
  if o.disposed then return end;o.disposed=true
  pcall(off,game,{onTeleport=o.callback})
  if root._rinoCubeTeleportObserver==o then root._rinoCubeTeleportObserver=nil end
  if o.owner and o.owner.unbind==o.unbind then o.owner.unbind=o.previousUnbind end
 end
 local ok=pcall(on,game,{onTeleport=o.callback});if not ok then return false end
 observer=o;root._rinoCubeTeleportObserver=o
 if Helper then
  local owner,prior=Helper,Helper.unbind;o.owner,o.previousUnbind=owner,prior
  o.unbind=function(...)o.dispose();if prior then return prior(...)end end
  owner.unbind=o.unbind
 end
 return true
end
S.setup=function()
 pcall(S.installTeleportObserver)
 local previous=g_ui and g_ui.getRootWidget()._rinoCubeModalObserver
 if previous and previous.dispose then previous.dispose()end
 pcall(function()
  if type(configDir)=='string'and g_resources.fileExists(configDir..'/_helper_dev/development.lock')and
   g_resources.fileExists(configDir..'/_helper_dev/cube_trace.lua')then dofile('/_helper_dev/cube_trace.lua')end
 end)
 CaveBot.registerAction('supremecube','#e2be70',S.run)
 CaveBot.Editor.registerAction('supremecube','Supreme Cube',{value='Cities, Thais',title='Supreme Cube',
  description='Elige un destino fijo. Espera cooldown y confirma la llegada antes de seguir.',multiline=false})
end

-- The picker is loaded separately so the travel engine stays independently testable.
dofile('/cavebot/supreme_cube_editor.lua')
