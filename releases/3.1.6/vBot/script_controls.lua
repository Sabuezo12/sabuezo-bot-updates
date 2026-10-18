-- Inventory of existing macro handles. No engine, extra macro or UI traversal.
local root=g_ui.getRootWidget()
local previous=root._rinoScriptControls
if previous and previous.dispose then previous.dispose() end
local C={entries={},handles={},revision=0,source=nil,disposed=false}
RinoScriptControls=C
root._rinoScriptControls=C
local baseMacro=macro
function C.valid() return not C.disposed and root._rinoScriptControls==C end
local function invoke(handle,key,...)
  local fn=handle and handle[key]
  if type(fn)~='function' then return false end
  local ok,result=pcall(fn,...)
  if not ok then ok,result=pcall(fn,handle,...) end
  return ok,result
end
function C.isOn(entry)
  if not C.valid() or entry.retired then return false end
  local ok,value=invoke(entry.handle,'isOn')
  return ok and value==true
end
function C.available(entry)
  return C.valid() and not entry.retired and (not entry.owner or entry.owner.active and not entry.owner.failed)
end
function C.record(handle,name,source)
  if not C.valid() or type(handle)~='table' or type(handle.setOn)~='function' or type(handle.setOff)~='function' or type(handle.isOn)~='function' then return end
  local entry=C.handles[handle]
  if not entry then
    if type(name)~='string' or name=='' then return end
    entry={handle=handle,name=name,source=source or 'Macro cargado'}
    C.entries[#C.entries+1]=entry;C.handles[handle]=entry;C.revision=C.revision+1
  end
  return entry
end
function C.claim(handle,owner,name,index,onChange)
  local entry=C.record(handle,name,owner.name)
  if not entry then return end
  entry.owner,entry.name,entry.source,entry.index,entry.onChange=owner,name,owner.name,index,onChange
  C.revision=C.revision+1
end
function C.retire(owner)
  for _,entry in ipairs(C.entries)do
    if entry.owner==owner then entry.retired=true;C.handles[entry.handle]=nil end
  end
  C.revision=C.revision+1
end
function C.list()
  local result={}
  for _,entry in ipairs(C.entries)do
    if entry.owner then entry.source=entry.owner.name end
    if not entry.retired then result[#result+1]=entry end
  end
  return result
end
function C.setEnabled(entry,on)
  if not C.available(entry) then return false end
  local ok=invoke(entry.handle,on and 'setOn' or 'setOff')
  if ok and entry.onChange then entry.onChange(on==true) end
  return ok
end
-- Some client executors expose handles created before _Loader.lua ran.
-- Read only named handles; hidden engine loops do not become user switches.
if type(_macros)=='table' then
  for _,handle in ipairs(_macros)do C.record(handle,handle.name,'Macro cargado') end
end
local wrapped
wrapped=function(...)
  local handle=baseMacro(...)
  local _,name=...
  C.record(handle,name,C.source or Helper and Helper.source)
  return handle
end
macro=wrapped
function C.dispose()
  if C.disposed then return end
  C.disposed=true
  if macro==wrapped then macro=baseMacro end
  C.entries={};C.handles={}
  if root._rinoScriptControls==C then root._rinoScriptControls=nil end
end
