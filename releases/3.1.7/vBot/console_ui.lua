setDefaultTab('Main')
local console=RinoConsole
if not console or not console.valid()then return end
local window=UI.createWindow('RinoConsoleWindow',g_ui.getRootWidget())
window:hide()
local active,paused,revision,cycle=true,false,-1,0
local function valid()return active and console.valid()and not window:isDestroyed()end
local function filter()
  local option=window.filter:getCurrentOption()
  return option and option.text or 'Todos'
end
local function refresh(force)
  if not valid()or paused or not force and revision==console.revision then return end
  revision=console.revision
  local lines=console.lines(filter(),window.search:getText())
  window.log:setText(#lines>0 and table.concat(lines,'\n') or 'Sin eventos para este filtro.')
  if window.scroll.getMaximum then window.scroll:setValue(window.scroll:getMaximum())end
  window.status:setText(#lines..' eventos visibles / '..#console.entries..' guardados. Vista en directo.')
end
local function observe(token)
  if not valid()or token~=cycle or not window:isVisible()then return end
  refresh(false)
  schedule(250,function()observe(token)end)
end
for _,name in ipairs({'Todos','Avisos y errores','Acciones','Push Max'})do window.filter:addOption(name)end
window.filter.onOptionChange=function()refresh(true)end
window.search.onTextChange=function()refresh(true)end
window.pause:setTooltip('Pausa solo la vista de la consola.\nEl bot y el registro siguen activos.')
window.save:setTooltip('Guarda el historial completo en\n_diagnostics/rinobot-console.log.')
window.inspect:setTooltip('Muestra el estado actual de los modulos\nsin cambiar sus interruptores.')
window.pause.onClick=function()
  paused=not paused
  window.pause:setText(paused and 'Reanudar vista' or 'Pausar vista')
  if paused then window.status:setText('Vista en pausa. El bot y el registro continuan.')else refresh(true)end
end
window.clear.onClick=function()console.clear();if paused then window.log:setText('Historial limpiado.')else refresh(true)end end
window.copy.onClick=function()
  if g_window and type(g_window.setClipboardText)=='function'then
    local ok=pcall(g_window.setClipboardText,window.log:getText())
    if ok then window.status:setText('Texto visible copiado.');return end
  end
  if type(window.log.selectAll)=='function'then window.log:selectAll();window.log:focus()end
  window.status:setText('Selecciona el texto y usa Ctrl+C.')
end
window.save.onClick=function()
  local ok,path=console.save()
  window.status:setText(ok and 'Guardado en '..path or 'No se pudo guardar: '..tostring(path))
end
window.inspect.onClick=function()console.status();refresh(true)end
window.closeButton.onClick=function()window:hide()end
window.onVisibilityChange=function(_,visible)
  cycle=cycle+1
  if visible then
    refresh(true)
    local token=cycle;schedule(250,function()observe(token)end)
  end
end
console.views[#console.views+1]=function()
  active=false;cycle=cycle+1
  pcall(function()if not window:isDestroyed()then window:destroy()end end)
end
if not Helper or not Helper.valid()then
  UI.Button('Consola de RinoBot',function()
    if valid()then window:show();window:raise();window:focus()end
  end)
end
refresh(true)
