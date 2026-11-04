-- Bounded local bot history. No chat hooks, packets or background file writes.
local root=g_ui.getRootWidget()
local previous=root._rinoConsole
local history,baseAt,sequence={},tonumber(now) or 0,0
if type(previous)=='table' then
  for _,entry in ipairs(previous.entries or {})do history[#history+1]=entry end
  baseAt=previous.baseAt or baseAt;sequence=previous.sequence or 0
  if type(previous.dispose)=='function' then pcall(previous.dispose) end
  previous.active=false
end
local C={active=true,entries=history,baseAt=baseAt,sequence=sequence,revision=0,limit=300,views={},originals={},wrappers={}}
RinoConsole=C;root._rinoConsole=C
function C.valid()return C.active and root._rinoConsole==C end
local function time()return tonumber(now) or 0 end
local function clean(value,limit)
  local text=tostring(value or ''):gsub('[\r\n\t]',' ')
  text=text:gsub('sk%-[%w%-_]+','[clave oculta]'):gsub('([?&][Tt][Oo][Kk][Ee][Nn]=)[^ &]+','%1[oculto]')
  limit=limit or 180
  if #text>limit and limit>=100 then return text:sub(1,limit-63)..'... '..text:sub(-59)end
  return text:sub(1,limit)
end
function C.log(level,source,message,detail)
  if not C.valid()then return end
  local n=time()
  level=clean(level or 'info',12);source=clean(source or 'Bot',48)
  message,detail=clean(message),clean(detail)
  local last=C.entries[#C.entries]
  if last and last.level==level and last.source==source and last.message==message and last.detail==detail and n>=last.at and n-last.at<1000 then
    last.count=(last.count or 1)+1;last.at=n
  else
    C.sequence=C.sequence+1
    C.entries[#C.entries+1]={n=C.sequence,at=n,level=level,source=source,message=message,detail=detail,count=1}
    if #C.entries>C.limit then table.remove(C.entries,1)end
  end
  C.revision=C.revision+1
end
function C.clear()
  if not C.valid()then return end
  C.entries={};C.revision=C.revision+1
end
local function stamp(n)
  local elapsed=math.floor(math.max(0,n-C.baseAt)/1000)
  return string.format('%02d:%02d:%02d',math.floor(elapsed/3600),math.floor(elapsed/60)%60,elapsed%60)
end
function C.lines(filter,search)
  local out={};filter=filter or 'Todos';search=tostring(search or ''):lower()
  for _,entry in ipairs(C.entries)do
    local match=filter=='Todos' or filter=='Avisos y errores' and (entry.level=='error' or entry.level=='warn')
      or filter=='Acciones' and entry.level=='action' or filter=='Push Max' and entry.source:find('Push Max',1,true)
    local text=entry.source..' '..entry.message..' '..entry.detail
    if match and (search=='' or text:lower():find(search,1,true))then
      out[#out+1]='['..stamp(entry.at)..'] '..entry.level:upper()..' | '..entry.source..' | '..entry.message
        ..(entry.detail~='' and ' | '..entry.detail or '')..((entry.count or 1)>1 and ' (x'..entry.count..')' or '')
    end
  end
  return out
end
function C.text(filter,search)return table.concat(C.lines(filter,search),'\n')end
function C.save()
  if not C.valid()then return false,'Consola retirada' end
  local base=type(configDir)=='string' and configDir:gsub('\\','/'):gsub('/+$','')
  if not base or not base:match('^/bot/[^/]+$') or base:find('..',1,true)then return false,'Ruta del bot no disponible' end
  local destination=base..'/_diagnostics'
  local ok,err=pcall(function()
    if not g_resources.directoryExists(destination)then g_resources.makeDir(destination)end
    assert(g_resources.writeFileContents(destination..'/rinobot-console.log','RinoBot | tiempo desde inicio de consola\n'..C.text())~=false)
  end)
  return ok,ok and '_diagnostics/rinobot-console.log' or tostring(err)
end
function C.status()
  C.log('info','Consola','Estado solicitado')
  if ContainerManager and type(ContainerManager.getStatus)=='function'then
    local ok,s=pcall(ContainerManager.getStatus)
    if ok and type(s)=='table'then
      C.log('info','Container Manager',s.revision or 'Estado','Gestor='..tostring(s.enabled)..' Sort Items='..tostring(s.sortItems)..' C='..#(s.entries or{}))
      for _,entry in ipairs(s.entries or{})do
        C.log('info','Container Manager','C: '..tostring(entry.name or entry.id)..' ['..tostring(entry.id)..']',entry.message)
      end
    end
  end
  if PushMax and type(PushMax.getStatus)=='function'then
    local ok,s=pcall(PushMax.getStatus)
    if ok and type(s)=='table'then
      C.log('info','Push Max',s.status or 'Sin estado','Activo='..tostring(s.active)..' ON='..tostring(PushMax.isOn and PushMax.isOn()))
      local stats=s.stats or {}
      C.log('info','Push Max','Contadores','Tareas='..tostring(stats.jobs or 0)..' pasos='..tostring(stats.walkSent or 0)..' pushes='..tostring(stats.pushSent or 0)..' observados='..tostring(stats.pushObserved or 0))
      if s.input then C.log('info','Push Max','Ultima tecla '..tostring(s.input.key),tostring(s.input.outcome)..' / '..tostring(s.input.reason or s.input.source or ''))end
    end
  end
  if Helper and type(Helper.getState)=='function' and type(Helper.modules)=='table' then
    local ids={};for id in pairs(Helper.modules)do ids[#ids+1]=id end;table.sort(ids)
    for _,id in ipairs(ids)do
      local module=Helper.modules[id]
      local ok,value=pcall(Helper.getState,module)
      if ok and type(value)=='boolean'then C.log('state',module.name or id,value and 'ON' or 'OFF')end
    end
  else
    for name,api in pairs({CaveBot=CaveBot,TargetBot=TargetBot,AttackBot=AttackBot})do
      if type(api)=='table'and type(api.isOn)=='function'then
        local ok,value=pcall(api.isOn)
        if ok then C.log('state',name,value and 'ON' or 'OFF')end
      end
    end
  end
end
local function source()
  return RinoScriptControls and RinoScriptControls.source or Helper and Helper.source or 'Bot'
end
function C.dispose()
  if not C.active then return end
  C.active=false
  for _,dispose in ipairs(C.views)do pcall(dispose)end
  if info==C.wrappers.info then info=C.originals.info end
  if warn==C.wrappers.warn then warn=C.originals.warn end
  if error==C.wrappers.error then error=C.originals.error end
  if print==C.wrappers.print then print=C.originals.print end
  if root._rinoConsole==C then root._rinoConsole=nil end
end
-- Preserve native return values and error behavior; log only messages already produced by the bot.
local originalInfo,originalWarn,originalError,originalPrint=info,warn,error,print
local function wrap(fn,level)
  return function(message,...)
    if C.valid()then pcall(C.log,level,source(),message)end
    return fn(message,...)
  end
end
if type(originalInfo)=='function'then C.originals.info=originalInfo;C.wrappers.info=wrap(originalInfo,'info');info=C.wrappers.info end
if type(originalWarn)=='function'then C.originals.warn=originalWarn;C.wrappers.warn=wrap(originalWarn,'warn');warn=C.wrappers.warn end
if type(originalError)=='function'then C.originals.error=originalError;C.wrappers.error=wrap(originalError,'error');error=C.wrappers.error end
if type(originalPrint)=='function'then C.originals.print=originalPrint;C.wrappers.print=wrap(originalPrint,'info');print=C.wrappers.print end
C.log('info','RinoBot',previous and 'Consola conservada tras recarga' or 'Consola iniciada','Historial local de hasta 300 eventos')
