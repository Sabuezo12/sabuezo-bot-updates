-- A sent use packet is not proof of a route transition. Keep the known use
-- waypoint until its landing is observed; ordinary uses retain their contract.
CaveBot.Use={}
local U=CaveBot.Use
CaveBot.Extensions.Use=U
local function copy(p)return p and{x=p.x,y=p.y,z=p.z}end
local function distance(a,b)return math.max(math.abs(a.x-b.x),math.abs(a.y-b.y))end
function U.decode(value)
 if type(value)~='string'then return end
 value=value:match('^%s*%((.-)%)%s*$')or value
 local x,y,z=value:match('^%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*$')
 if x then
  x,y,z=tonumber(x),tonumber(y),tonumber(z)
  if x<65535 and y<65535 and z<=15 then return{position={x=x,y=y,z=z}}end
  return
 end
 local id=value:match('^%s*(%d+)%s*$');id=tonumber(id)
 if id and id>0 then return{id=id}end
end
local function gotoPosition(row)
 if not row or row.action~='goto'then return end
 local x,y,z=tostring(row.value):match('^%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*,?%s*%d*%s*$')
 if x then
  x,y,z=tonumber(x),tonumber(y),tonumber(z)
  if x<65535 and y<65535 and z<=15 then return{x=x,y=y,z=z}end
 end
end
function U.plan(rows,index,target)
 local bridge
 for i=index+1,math.min(#rows,index+6)do
  local row=rows[i]
  if row.action~='label'then
   local p=gotoPosition(row);if not p then return end
   if p.z~=target.z then
    -- A nearby walk followed by nearby stairs is an ordinary door use.
    -- A remote landing after one local bridge is a portal (the mirror route).
    if not bridge or distance(p,target)>8 then return{arrival=p,bridge=bridge}end
    return
   end
   if bridge or distance(p,target)>2 then return end
   bridge=row
  end
 end
end
function U.new(host)
 local C={};local job
 local function clear()job=nil;C.job=nil end
 C.reset=clear
 local function report(text)
  if C.status~=text then C.status=text;if host.report then host.report(text)end end
 end
 local function routePlan(row,target)
  local rows=host.rows()
  for i,entry in ipairs(rows)do if entry==row then return U.plan(rows,i,target)end end
 end
 local function current()
  return job and job.row==host.context()and job.owner==host.owner()and host.active()
 end
 function C.text(text)
  if not current()or not job.sentAt or host.time()<job.sentAt or host.time()>job.responseUntil or type(text)~='string'then return end
  local s=text:lower():match('^%s*(.-)%s*$'):gsub('[.!]$','')
  if s=='you are too far away'or s:find('cannot use',1,true)or s:find('can not use',1,true)or
   s:find('object cannot be used',1,true)or s:find('already using an item',1,true)or s:find('already using items',1,true)or
   s:find('first go upstairs',1,true)or s:find('first go downstairs',1,true)then job.rejected=text end
 end
 local function wait(ms)host.delay(ms or 250);return'retry'end
 local function complete(text)report(text);clear();return true end
 function C.canRunWhileTargeting(row)
  if not row or row.action~='use'then return false end
  local cfg=U.decode(row.value);local p=host.position()
  return cfg and cfg.position and p and cfg.position.z==p.z and distance(p,cfg.position)<=1 and
   routePlan(row,cfg.position)~=nil or false
 end
 function C.recover(row)
  local goal=gotoPosition(row);local p=host.position()
  if not goal or not p then return end
  if goal.z==p.z and distance(goal,p)>4 then return end
  local rows=host.rows();local index
  for i,entry in ipairs(rows)do if entry==row then index=i;break end end
  if not index then return end
  for i=index-1,math.max(1,index-16),-1 do
   local entry=rows[i]
   if entry.action=='use'then
    local cfg=U.decode(entry.value);local target=cfg and cfg.position
    if not target or target.z~=p.z or distance(p,target)>2 then return end
    local plan=U.plan(rows,i,target)
    if not plan then return end
    if(goal.z~=p.z and goal.z==plan.arrival.z)or(row==plan.bridge and goal.z==p.z)then
     report('Reintentando el uso anterior; aun no se completo el cruce al piso '..plan.arrival.z..'.')
     return entry
    end
    return
   elseif entry.action~='goto'and entry.action~='label'then return end
  end
 end
 function C.run(value,retries)
  local cfg=U.decode(value)
  if not cfg then report('Valor de use invalido: '..tostring(value));clear();return false end
  if not host.active()then clear();return wait(500)end
  local row,owner=host.context(),host.owner();local t=host.time()
  if not job or job.row~=row or job.owner~=owner or job.value~=value or retries==0 then
   job={row=row,owner=owner,value=value,target=cfg.position,id=cfg.id,attempts=0,nextAt=0};C.job=job
   if cfg.position then job.plan=routePlan(row,cfg.position)end
  end
  local p=host.position();if not p then return wait(500)end
  local plan,target=job.plan,job.target
  if plan and p.z==plan.arrival.z and distance(p,plan.arrival)<=host.maxDistance()then
   return complete('Cruce de use confirmado en el piso '..p.z..'.')
  end
  if target and p.z~=target.z then
   if job.sentAt and not plan then return complete('Cambio de piso tras usar el objeto confirmado.')end
   if not plan then clear();return false end
   report('El cruce de use sigue pendiente; el personaje esta en otro piso.');return wait(1000)
  end
  if job.sentAt and t>=job.nextAt and not plan and not job.rejected then
   return complete('Uso enviado sin rechazo del servidor.')
  end
  if t<job.nextAt then return wait(math.min(250,job.nextAt-t))end
  local thing=job.id
  if target then
   if distance(p,target)>1 then
    local ok=false
    if distance(p,target)<=host.maxDistance()then ok=host.walk(target)end
    report(ok and'Acercandome al objeto antes de usarlo.'or'Esperando acceso al objeto; conservo el waypoint use.')
    return wait(ok and 100 or 750)
   end
   thing=host.thing(target)
   if not thing then report('Esperando que el objeto este disponible; conservo el waypoint use.');return wait(500)end
  end
  job.origin=copy(p);job.sentAt=t;job.rejected=nil;job.attempts=job.attempts+1
  job.responseUntil=t+math.min(1000,math.max(250,host.ping()*3+150))
  local interval=math.max(750,host.useDelay()+host.ping()*2+200)
  if job.attempts>3 then interval=math.max(1500,interval)end
  job.nextAt=t+interval
  local ok,result=pcall(host.use,thing)
  if not ok or result==false then job.rejected='El cliente rechazo el uso.'end
  if job.attempts==1 or job.attempts%5==0 then
   report((plan and'Esperando el cruce tras usar el objeto' or'Uso del objeto enviado')..' (intento '..job.attempts..').')
  end
  return wait(math.min(250,interval))
 end
 return C
end
local function context()return CaveBot.actionList and(CaveBot.actionList:getFocusedChild()or CaveBot.actionList:getFirstChild())end
local runtime=U.new({time=function()return tonumber(now)or 0 end,context=context,
 owner=function()return player and player:getId()end,
 position=function()return player and player:getPosition()end,
 active=function()return player and CaveBot.isOn and CaveBot.isOn()and not(HelperPause and HelperPause.isPaused())end,
 rows=function()return CaveBot.actionList and CaveBot.actionList:getChildren()or{}end,
 maxDistance=function()return tonumber(storage.extras and storage.extras.gotoMaxDistance)or 24 end,
 walk=function(p)return CaveBot.walkTo(p,tonumber(storage.extras and storage.extras.gotoMaxDistance)or 24,
  {precision=1,ignoreFields=true,ignoreNonPathable=true,allowUnseen=true,allowOnlyVisibleTiles=false})end,
 thing=function(p)local tile=g_map.getTile(p);return tile and tile:getTopUseThing()end,
 use=function(thing)return use(thing)end,delay=function(ms)CaveBot.delay(ms)end,
 useDelay=function()return math.max(0,tonumber(CaveBot.Config.get('useDelay'))or 400)end,
 ping=function()return math.max(0,tonumber(CaveBot.Config.get('ping'))or 0)end,
 report=function(text)U.status=text;if RinoConsole and RinoConsole.log then pcall(RinoConsole.log,'action','CaveBot use',text)end end})
U.run=runtime.run;U.recover=runtime.recover;U.canRunWhileTargeting=runtime.canRunWhileTargeting
U.onConfigChange=runtime.reset
if type(onTextMessage)=='function'then onTextMessage(function(_,text)runtime.text(text)end)end
