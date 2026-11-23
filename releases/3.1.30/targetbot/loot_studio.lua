TargetBot.LootStudio={}
local S,P=TargetBot.LootStudio,TargetBot.LootPolicy
local M=TargetBot.LootMode
local methods={auto="Automatico",native="Quick Loot",manual="Tradicional"}
local function same(a,b)
 if type(a)~=type(b)then return false end;if type(a)~='table'then return a==b end
 for k,v in pairs(a)do if not same(v,b[k])then return false end end
 for k in pairs(b)do if a[k]==nil then return false end end;return true
end
function S.create(parent,ctx)
 local ui=UI.createWidget('LootStudioRoot',parent)
 local self,draft,saved,loading,filterRows,destinationRows={widget=ui}
 local reload,renderFilters,renderDestinations,renderOverrides,refresh
 local capabilityStamp
 local function stamp()
  local engine,reason=M.resolve(draft.engine)
  local cap=M.capabilities()
  return engine..':'..tostring(cap.available)..':'..tostring(reason)
 end
 local function changed()
  if loading then return end
  self.dirty=not same(draft,saved)
  if self.onChange then self.onChange()end
 end
 local function note(text,bad)
  self.message=text;ui.note:setText(text);ui.note:setColor(bad and'#f39b8f'or'#c0cdd6')
  if self.onChange then self.onChange()end
 end
 local function list()return draft.filter=='skip'and draft.ignored or draft.accepted end
 local function combo(widget,ref,allowEmpty,callback)
  loading=true;widget:clearOptions()
  local options=P.options()
  if allowEmpty then table.insert(options,1,{text='Sin asignar',ref=nil})end
  local selected
  for i,option in ipairs(options)do widget:addOption(option.text);if P.refEqual(option.ref,ref)then selected=option.text end end
  if not selected and ref and ref.kind~='none'then
   selected='No disponible: '..P.refLabel(ref);options[#options+1]={text=selected,ref=P.copy(ref)};widget:addOption(selected)
  end
  widget:setCurrentOption(selected or options[1].text)
  widget:setTooltip(P.refLabel(ref)..'\nLos destinos (sesion) se vuelven a elegir si cierras la mochila o recargas.')
  widget.onOptionChange=function()
   if loading then return end
   local value=widget:getCurrentOption().text
   for _,option in ipairs(options)do if value==option.text then callback(P.copy(option.ref));changed();return end end
  end
  loading=false
 end
 local function paint(widget,id)
  if HelperClientCompat then HelperClientCompat.setItemIdForDisplay(widget,id or 0)
  elseif not id or id==0 or P.validId(id)then widget:setItemId(id or 0)end
 end
 local function addIds(text,override)
  local pending,seen={},{}
  for part in tostring(text or''):gmatch('[^,%s;]+')do
   local id=tonumber(part)
   if not id or not P.validId(id)then note('ID no disponible en este cliente: '..part,true);return end
   if not seen[id]then seen[id]=true;pending[#pending+1]=id end
  end
  for _,id in ipairs(pending)do
   if override then
    if not draft.overrides[tostring(id)]then draft.overrides[tostring(id)]={kind='none'}end
   else
    local found=false;for _,entry in ipairs(list())do if entry.id==id then found=true;break end end
    if not found then list()[#list()+1]={id=id,count=1}end
   end
  end
  changed();renderFilters();renderOverrides()
 end
 self.addIds=addIds
 local function ask(override)
  UI.EditorWindow('',{title=override and'Destino por objeto'or'Agregar objetos',
   description='Escribe uno o varios IDs separados por coma. Tambien puedes arrastrar un objeto al cuadro +.',multiline=false},function(text)addIds(text,override)end)
 end
 renderFilters=function()
  ui.filters.items:destroyChildren();filterRows={}
  ui.filters.listTitle:setText((draft.filter=='skip'and'Ignorados'or'Aceptados')..' ('..#list()..')')
  local search=tostring(ui.filters.search:getText()or''):lower()
  for index,entry in ipairs(list())do
   local id=entry.id;local name=P.name(id)
   if search==''or name:lower():find(search,1,true)or tostring(id):find(search,1,true)then
    local row=UI.createWidget('LootStudioItemRow',ui.filters.items)
    paint(row.item,id);row.name:setText(name);row.number:setText(tostring(id))
    row.name:setTooltip(name..' | ID '..id)
    row.remove.onClick=function()table.remove(list(),index);changed();renderFilters()end
    filterRows[#filterRows+1]=row
   end
  end
 end
 renderDestinations=function()
  ui.categories.rows:destroyChildren();destinationRows={}
  for _,entry in ipairs(P.categories)do
   local id,title=entry[1],entry[2]
   local row=UI.createWidget('LootStudioCategoryRow',ui.categories.rows)
   row.name:setText(title);row.name:setTooltip(title)
   local ref=draft.categories[id]
   paint(row.item,ref and ref.id)
   row.free:setText(ref and P.space(ref,draft)or'--')
   combo(row.destination,ref,true,function(value)
    draft.categories[id]=value;paint(row.item,value and value.id);row.free:setText(value and P.space(value,draft)or'--')
   end)
   row.remove.onClick=function()draft.categories[id]=nil;changed();renderDestinations()end
   destinationRows[#destinationRows+1]={row=row,key=id}
  end
 end
 renderOverrides=function()
  ui.overrides.items:destroyChildren()
  local ids={};for id in pairs(draft.overrides)do ids[#ids+1]=tonumber(id)end;table.sort(ids)
  for _,id in ipairs(ids)do
   local row=UI.createWidget('LootStudioOverrideRow',ui.overrides.items)
   paint(row.item,id);row.name:setText(P.name(id));row.name:setTooltip(P.name(id)..' | ID '..id)
   combo(row.destination,draft.overrides[tostring(id)],true,function(value)draft.overrides[tostring(id)]=value or{kind='none'}end)
   row.remove.onClick=function()draft.overrides[tostring(id)]=nil;changed();renderOverrides()end
  end
 end
 refresh=function()
  loading=true
  ui.skip:setChecked(draft.filter=='skip');ui.accept:setChecked(draft.filter=='accept')
  ui.fallback:setChecked(draft.fallback==true)
  ui.method:setCurrentOption(methods[draft.engine])
  loading=false
  combo(ui.main,draft.main,false,function(value)draft.main=value end)
  -- Automatico keeps the traditional fallback editable even while the
  -- current client can use native Quick Loot.
  local manual=draft.engine~='native'
  ui.categories:setEnabled(manual);ui.filters:setEnabled(manual);ui.overrides:setEnabled(manual)
  ui.skip:setEnabled(manual);ui.accept:setEnabled(manual);ui.fallback:setEnabled(manual);ui.main:setEnabled(manual)
  local engine,reason=M.resolve(draft.engine)
  local cap=M.capabilities()
  ui.native:setVisible(draft.engine~='manual');ui.native:setEnabled(cap.available)
  if draft.engine=='auto' then
   note(engine=='native' and 'Automatico: Quick Loot. Configura el loot nativo; las listas de abajo son el respaldo Tradicional.' or
    'Automatico: Tradicional. '..(reason or '')..' Configura aqui los objetos y mochilas.')
  elseif draft.engine=='manual' then
   note('Tradicional: abre cadaveres y mueve objetos. Abre tus mochilas y pulsa Actualizar.')
  else
   note(engine=='native' and 'Quick Loot: usa los filtros y mochilas del cliente. Pulsa Configurar nativo.' or
    (reason or 'Quick Loot no disponible.')..' Elige Automatico o Tradicional.',engine~='native')
  end
  renderDestinations();renderFilters();renderOverrides()
  capabilityStamp=stamp()
  changed()
 end
 for _,key in ipairs({'auto','native','manual'}) do ui.method:addOption(methods[key]) end
 ui.method.onOptionChange=function()
  if loading then return end
  for key,title in pairs(methods) do if ui.method:getCurrentOption().text==title then draft.engine=key end end
  changed();refresh()
 end
 ui.skip.onClick=function()draft.filter='skip';changed();refresh()end
 ui.accept.onClick=function()draft.filter='accept';changed();refresh()end
 ui.fallback.onClick=function()draft.fallback=not draft.fallback;changed();refresh()end
 ui.filters.search.onTextChange=function()if draft then renderFilters()end end
 ui.filters.add.onClick=function()ask(false)end
 ui.filters.clear.onClick=function()
  UI.ConfirmationWindow('Vaciar lista','Quitar todos los objetos de esta lista?',function()
   if draft.filter=='skip'then draft.ignored={}else draft.accepted={}end;changed();renderFilters()
  end)
 end
 ui.filters.drop.onItemChange=function(widget)
  local id=HelperClientCompat and HelperClientCompat.itemIdFromWidget(widget)or widget:getItemId()
  if id>0 then addIds(tostring(id),false);local cb=widget.onItemChange;widget.onItemChange=nil;paint(widget,0);widget.onItemChange=cb end
 end
 ui.overrides.add.onClick=function()ask(true)end
 ui.categories.refresh.onClick=function()refresh()end
 ui.native.onClick=function()
  local q=modules and modules.game_quickloot
  if q and q.QuickLoot and type(q.QuickLoot.toggle)=='function'then q.QuickLoot.toggle()
  elseif q and q.quicklootWindow then q.quicklootWindow:show();q.quicklootWindow:raise();q.quicklootWindow:focus()
  else note('Este cliente no expone el gestor de Quick Loot.',true)end
 end
 ui.settings.onClick=function()
  UI.EditorWindow(tostring(draft.minCapacity)..','..tostring(draft.maxDanger),{
   title='Limites del looting',description='Capacidad minima y peligro maximo, separados por coma. Ejemplo: 100,10',multiline=false},function(text)
   local a,b=tostring(text):match('^%s*(%d+)%s*,%s*(%d+)%s*$')
   if not a then note('Escribe dos enteros: capacidad,peligro.',true);return end
   local copy=P.copy(draft);copy.minCapacity=tonumber(a);copy.maxDanger=tonumber(b)
   local ok,err=P.validate(copy);if not ok then note(err,true);return end
   draft=copy;changed();note('Limites editados; pulsa Guardar cambios.')
  end)
 end
 function self.load()
  if self.dirty then return end
  saved=P.read(ctx.snapshot());draft=P.copy(saved);refresh()
 end
 function self.discard()self.dirty=false;self.load()end
 function self.getDraft()return draft end
 function self.save()
  local ok,err=ctx.apply(P.copy(draft));if not ok then note(err or'No se pudieron guardar los ajustes.',true);return false end
  saved=P.copy(draft);self.dirty=false;note('Loot global guardado.');changed();return true
 end
 function self.show()self.load();refresh()end
 macro(1000,function()
  if not ui:isVisible()or not draft then return end
  if stamp()~=capabilityStamp then refresh()end
  M.sync()
  local label,reason=M.label()
  ui.status:setText('Activo: '..label..(P.active()and P.message~=''and' | '..P.message or' | '..(reason or '')))
  for _,entry in ipairs(destinationRows or{})do local ref=draft.categories[entry.key];entry.row.free:setText(ref and P.space(ref,draft)or'--')end
 end)
 self.load();return self
end
