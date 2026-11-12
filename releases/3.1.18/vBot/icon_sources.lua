-- Read existing bot/script controls; creating an icon never loads an engine.
vBot=vBot or {}
local S={targets={},ordered={}}
vBot.IconSources=S
function S.call(fn,...)
  if type(fn)~='function' then return false end
  local ok,value=pcall(fn,...)
  if not ok then return false end
  return true,value
end
function S.id(kind,key)
  return 'RinoIcon_'..kind..'_'..tostring(key):gsub('.',function(c)return string.format('%02x',c:byte())end)
end
function S.notify(message)
  if S.onStatus then S.onStatus(message) end
end
function S.state(id)
  local t=S.targets[id]
  if not t or not t.available() then return nil end
  local ok,state=S.call(t.state)
  if ok then return state end
  return nil
end
function S.set(id,value)
  local t=S.targets[id]
  if not t or not t.available() or not t.set then S.notify('La funcion no esta disponible.');return false end
  local ok,result=S.call(t.set,value==true)
  if not ok or result==false then S.notify('No se pudo cambiar la funcion. Revisa su configuracion.');return false end
  return true
end
function S.open(id)
  local t=S.targets[id]
  if not t or not t.available() then S.notify('Origen no disponible; se conserva el icono guardado.');return false end
  local ok,result=S.call(t.open)
  return ok and result~=false
end
function S.collect(legacy,modules,bindings)
  local targets,ordered,legacyByModule={},{},{}
  local function add(t)
    if targets[t.id] then return end
    targets[t.id]=t;ordered[#ordered+1]=t
  end
  for _,data in ipairs(legacy) do
    if data.botScript then
      local engine=data.botScript;local module=modules[data.id] or(data.id=='HoldTargetIcon'and'holdtarget')
      if module then legacyByModule[module]=data.id end
      add({id=data.id,key=module or data.id,kind='bot',name=data.text:gsub('\n',' '),source='Bot',legacy=data,
        available=function()return true end,state=function()
          local H=Helper
          if H and H.valid() and H.getState and module and H.modules[module] then return H.getState(H.modules[module]) end
          if data.action then return nil end
          local ok,on=S.call(engine.isOn);if ok then return on==true end
        end,
        set=function(on)
          local H=Helper
          if H and H.valid() and H.setEnabled and module and H.modules[module] then H.setEnabled(H.modules[module],on);return true end
          local ok,result=S.call(on and engine.setOn or engine.setOff);return ok and result~=false
        end,
        open=function()
          local H=Helper
          if module=='holdtarget'then return false end
          if H and H.valid() and module then
            if H.openIconConfiguration then return H.openIconConfiguration(module) end
            if H.openModule then H.openModule(module);return true end
          end
          return false
        end})
    end
  end
  local H=Helper
  if H and H.valid() then
    for _,m in ipairs(H.order or {}) do
      if m.available and not m.hidden and not legacyByModule[m.id] then
        local id=S.id('bot',m.id)
        add({id=id,key=m.id,kind='bot',name=m.name,source=m.section or 'Bot',
          available=function()return H.valid() and m.available end,
          state=function()if H.getState then return H.getState(m)end end,
          set=function(on)if H.setEnabled then H.setEnabled(m,on);return true end;return false end,
          open=function()if H.openIconConfiguration then return H.openIconConfiguration(m.id)end;if H.openModule then H.openModule(m.id);return true end;return false end})
      end
    end
  end
  local manager=vBot.InGameScriptManager
  if manager and manager.listIconTargets then
    for _,script in ipairs(manager.listIconTargets()) do
      local key=tostring(script.id)
      add({id=S.id('script',key),key=key,kind='script',name=script.name,source='Mis scripts',
        available=function()return vBot.InGameScriptManager==manager end,
        state=function()return manager.getIconState(key)end,
        set=function(on)return manager.setIconState(key,on)end,
        open=function()return manager.openIconSource(key)end})
    end
  end
  local C=RinoScriptControls
  if C and C.valid() then
    local controls=C.list();local counts={}
    local function controlKey(e)
      if e.owner then return 'script:'..tostring(e.owner.scriptId)..':'..tostring(e.owner.handleKeys and e.owner.handleKeys[e.index] or tostring(e.index or 0)..':'..e.name) end
      return tostring(e.source):gsub('^/',''):gsub('%.lua$','')..':'..e.name
    end
    for _,e in ipairs(controls) do local key=controlKey(e);counts[key]=(counts[key]or 0)+1 end
    for _,e in ipairs(controls) do
      local key=controlKey(e);local unique=counts[key]==1
      add({id=S.id('macro',key),key=key,kind='macro',name=e.name,source=e.source,
        note=not unique and 'Nombre repetido: registra un ID propio.' or e.owner and not C.available(e) and'Activa el script para usar esta macro.' or nil,
        available=function()return unique and C.available(e)end,
        state=function()return C.isOn(e)end,
        set=function(on)return C.setEnabled(e,on)end,
        open=function()
          if e.owner and manager and manager.openIconSource then return manager.openIconSource(tostring(e.owner.scriptId))end
          local module=tostring(e.source):gsub('^/',''):match('([^/]+)$')or'';module=module:gsub('%.lua$',''):lower()
          if H and H.valid() and H.modules[module] and H.openModule then H.openModule(module);return true end
          return false
        end})
    end
    for key,registered in pairs(C.registeredIcons or {}) do
      if not registered.retired then
        local api=registered.api
        local toggle=type(api.isOn)=='function'and type(api.setOn)=='function'and type(api.setOff)=='function'
        add({id=S.id('custom',key),key=key,kind='macro',name=registered.name,source=registered.source,
          available=function()return C.available(registered)end,
          state=function()if toggle then local ok,on=S.call(api.isOn);if ok then return on==true end end end,
          set=toggle and function(on)local ok,result=S.call(on and api.setOn or api.setOff);return ok and result~=false end or nil,
          open=function()
            if api.open then local ok,result=S.call(api.open);return ok and result~=false end
            if registered.owner and manager and manager.openIconSource then return manager.openIconSource(tostring(registered.owner.scriptId))end
            return false
          end,
          run=not toggle and function()local ok,result=S.call(api.run or api.open);return ok and result~=false end or nil})
      end
    end
  end
  for id,saved in pairs(bindings) do
    if not targets[id] then
      add({id=id,key=saved.key,kind=saved.kind,name=saved.name or 'Icono guardado',source='Origen ausente',
        note='Su script no esta cargado. Los ajustes del icono se conservan.',
        available=function()return false end,state=function()return nil end,open=function()S.notify('Carga el script para usar este icono.');return false end})
    end
  end
  S.targets,S.ordered=targets,ordered
  local signature={}
  for _,t in ipairs(ordered) do signature[#signature+1]=t.id..':'..t.name..':'..t.source..':'..tostring(t.available())end
  return table.concat(signature,'|')
end
function S.proxy(id)
  return {isOn=function()return S.state(id)==true end,setOn=function()return S.set(id,true)end,setOff=function()return S.set(id,false)end}
end
