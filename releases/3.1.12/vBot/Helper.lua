-- One shell hosts the complete original controls, callbacks and save actions.
local H = Helper
if not H or not H.valid() then return end
storage.helperUI = type(storage.helperUI) == "table" and storage.helperUI or {}
local settings = storage.helperUI
-- Restore the compact preset once for this correction. Later size choices
-- remain available; this never changes engine/profile data or icon positions.
if settings.directIconControlsVersion ~= 1 then
  if settings.sizePreset == "Grande" then settings.sizePreset = "Normal" end
  settings.directIconControlsVersion = 1
end
settings.favorites = type(settings.favorites) == "table" and settings.favorites or {}
-- Seed the shared home shortcuts once when this update first loads.
-- Later removals remain user choices across reloads and named profiles.
if (tonumber(settings.defaultFavoritesVersion) or 0) < 1 then
  for _, id in ipairs({"combo_plus", "friend_healer", "playerlist", "timerexecutor", "alarms", "dummy"}) do
    settings.favorites[id] = true
  end
  settings.defaultFavoritesVersion = 1
end
local section, selected, expanded = "Inicio", nil, false
local rows, activeView, stack = {}, nil, {}
local navigating, rendering, changing = false, false, false
local reloading, resizing = false, false
local createNative = H.originals.createWidget or UI.createWidget
local appearance=H.appearanceManager
local function create(style,parent)
  local w=createNative(style,parent)
  if HelperTheme then HelperTheme.decorate(w,style) end
  return w
end
local root = H.root
local window = H.originals.createWindow("HelperWindow", root)
if HelperTheme then HelperTheme.decorate(window,"HelperWindow") end
local icon = create("HelperLauncher", root)
window.botWidget, icon.botWidget = true, true
H.window, H.icon = window, icon
if RinoSkin and RinoSkin.prefix then
  RinoSkin.icon(window.brand,'brand');RinoSkin.icon(icon.emblem,'brand')
  RinoSkin.chrome(window.fold,'close','Recoger RinoBot')
  RinoSkin.chrome(window.minimize,'minimize','Recoger RinoBot')
  RinoSkin.chrome(window.expand,'expand','Cambiar tamano del panel')
  RinoSkin.chromeGlyph(window.reloadBot.glyph,'reload')
  RinoSkin.chromeGlyph(window.search.glyph,'search')
  RinoSkin.chromeGlyph(window.footer.pause.glyph,'pause')
  RinoSkin.chromeGlyph(window.footer.classicMode.glyph,'desktop')
  RinoSkin.icon(window.footer.updater.glyph,'settings')
end
dofile("/vBot/helper_home.lua")
window:hide()
local function safe(fn)
  local ok, value = pcall(fn)
  if ok then return value end
end
local function text(w, value)
  value = tostring(value or "")
  if H.live(w) and w:getText() ~= value then w:setText(value) end
end
local function header(name,direct,home,cave)
  window.back:setVisible(not home)
  window.selector:setVisible(not direct and not home and not cave)
  window.cavePower:setVisible(cave==true)
  window.sectionTitle:setVisible(direct)
  window.vertical:mergeStyle({['anchors.top']=home and 'search.bottom' or 'selector.bottom'})
  if direct then text(window.sectionTitle,name) end
end
local function place(w, p)
  local b, s = root:getRect(), w:getSize()
  p = p or w:getPosition()
  w:breakAnchors()
  w:setPosition({x=math.max(b.x, math.min(tonumber(p.x) or b.x, b.x+math.max(0,b.width-s.width))),
    y=math.max(b.y, math.min(tonumber(p.y) or b.y, b.y+math.max(0,b.height-s.height)))})
end
local function save()
  if not H.valid() then return end
  local p = icon:getPosition(); settings.icon = {x=p.x,y=p.y}
  p = window:getPosition(); settings.window = {x=p.x,y=p.y}
end
local function resize()
  if resizing then return end
  resizing=true
  local b = root:getSize()
  local width,height=460,500
  if expanded then
    width,height=740,620
    if activeView and H.live(activeView.widget) then
      local scripts=activeView.style=="InGameScriptManagerWindow"
      -- Scripts fixes its own workspace size, including its expanded layout.
      local form=activeView.widget:getSize()
      width=math.max(460,form.width+156)
      height=math.max(scripts and 470 or 500,form.height+(scripts and 208 or 148))
    end
  end
  local preset=settings.sizePreset or "Normal"
  if preset=="Grande" then width,height=width+80,height+60 end
  if preset=="Pequeno" and not expanded then width,height=440,470 end
  window:setSize({width=math.min(width,math.max(280,b.width-16)),
    height=math.min(height,math.max(300,b.height-16))})
  text(window.expand,expanded and "[-]" or "[+]")
  place(window); place(icon)
  if H.reflow then H.reflow() end
  resizing=false
end
H.fold = function()
  save()
  if H.closeFloatingPanels then H.closeFloatingPanels() end
  window:hide()
end
H.show = function()
  if not H.valid() then return end
  resize(); window:show(); window:raise()
  if H.refresh then H.refresh() end
end
function H.setLauncherVisible(shown)
  if not H.valid() then return false end
  settings.launcherVisible=shown==true
  icon:setVisible(settings.launcherVisible)
  if H.syncNativeButton then H.syncNativeButton() end
  if type(saveConfig)=="function" then saveConfig() end
  return true
end
function H.toggleLauncher() return H.setLauncherVisible(settings.launcherVisible==false) end
icon:setVisible(settings.launcherVisible~=false)
if H.syncNativeButton then H.syncNativeButton() end
window.fold.onClick, window.minimize.onClick = H.fold, H.fold
window.onEscape = function() H.fold(); return true end
window.onClose = function() H.fold(); return true end
window.expand.onClick = function() expanded=not expanded; resize() end
window.onGeometryChange = function() if not navigating then save() end end
window.onDestroy = function(w)
  if H.Home then H.Home.cleanup() end
  H.dispose(w)
end
icon.onDestroy = function(w) H.dispose(w) end
local drag, suppress = nil, false
icon.onDragEnter = function(w, mouse)
  local p=w:getPosition()
  drag={dx=mouse.x-p.x,dy=mouse.y-p.y,x=mouse.x,y=mouse.y}
  suppress=false; w:breakAnchors(); return true
end
icon.onDragMove = function(w, mouse)
  if not drag then return false end
  if math.abs(mouse.x-drag.x)+math.abs(mouse.y-drag.y)>=5 then suppress=true end
  place(w,{x=mouse.x-drag.dx,y=mouse.y-drag.dy}); return true
end
icon.onDragLeave = function() drag=nil; save(); return true end
icon.onMousePress = function() if not drag then suppress=false end; return false end
icon.onClick = function()
  if suppress then suppress=false; return end
  if window:isVisible() then H.fold() else H.show() end
end
-- Restore after geometry handlers are ready, without overwriting saved values.
local savedIcon, savedWindow = settings.icon, settings.window
navigating=true
place(icon,savedIcon or {x=350,y=160})
place(window,savedWindow or {x=410,y=120})
resize(); navigating=false; save()

local globals = {
  AttackBot=function() return AttackBot end, TargetBot=function() return TargetBot end,
  CaveBot=function() return CaveBot end, HealBot=function() return HealBot end,
  Inmortal=function() return Inmortal end, FriendHealer=function() return FriendHealer end,
  AutoBuff=function() return AutoBuff end, KeepWall=function() return KeepWall end,
  AntiPush=function() return AntiPush end, PullItems=function() return PullItems end,
  RecogeTodo=function() return RecogeTodo end, FireBomb=function() return FireBomb end,
  TimerExecutor=function() return TimerExecutor end, DummySmart=function() return DummySmart end, BugMapMouse=function() return BugMapMouse end,
  ImbuementScrolls=function() return ImbuementScrolls end, Dash=function() return Dash end
}
globals.HoldTarget=function() return HoldTarget end
globals.ExivaTarget=function() return ExivaTarget end
globals.ExivaLast=function() return ExivaLast end
local moduleAPIs={
  containermanager=function() return ContainerManager end,
  conditions=function() return Conditions end,
  alarms=function()
    if not Alarms then return end
    -- The native API returns nil before the first saved choice: that is OFF.
    return {isOn=function() return Alarms.isOn()==true end,
      setOn=Alarms.setOn,setOff=Alarms.setOff}
  end,
  itemcounter=function() return vBot and vBot.ItemCounter end,
  tools=function() return GoldConverter end,
  spy_level=function() return SpyLevelBridge end
}
local nativeMasters={combo_plus="title",equipper="switch",equip="title",
  manatrainer="title",pushmax="title",["z_auto-party"]="status",dummy="title",imbuementscrolls="title",
  conditions="title",alarms="title"}
local macroModules={containermanager=true,exeta=true,tools=true,eat_food=true}
local macroLabels={
  containermanager={["Container Manager"]=true},
  exeta={["Exeta when low HP"]=true,["Exeta If Player"]=true},
  tools={["Change Gold"]=true,["Send message on trade"]=true},
  eat_food={["Eat Food"]=true,["Conjure Food"]=true}
}
local function apiPower(e,key)
  if not e or type(e.isOn)~="function" or type(e.setOn)~="function" or type(e.setOff)~="function" then return end
  return {key=key,read=function() return safe(e.isOn) end,
    set=function(value) if safe(e.isOn)~=value then (value and e.setOn or e.setOff)() end end}
end
local function powers(m)
  if m.id=="eat_food" and HelperFoodBridge and type(HelperFoodBridge.getPowers)=="function" then
    local direct=HelperFoodBridge.getPowers()
    if #direct>0 then return direct end
  end
  local result={}
  -- CombatePvP opens a workspace; each engine keeps its own power control.
  if m.id=="pvp_support" then return result end
  local get=moduleAPIs[m.id] or globals[m.globalName]
  local power=apiPower(get and get(),m.id)
  if power then return {power} end
  local field=nativeMasters[m.id]
  if not field and not macroModules[m.id] then return result end
  local seen={}
  for index,item in ipairs(m.panels) do
    local w=item.widget
    if H.live(w) then
      local b=field and w:recursiveGetChildById(field) or w
      local id=safe(function() return b:getId() end) or ""
      local label=safe(function() return b:getText() end) or ""
      if field or tostring(id):match("^macro_") or macroLabels[m.id][label] then
        if H.live(b) and not seen[b] and type(b.onClick)=="function" and type(b.isOn)=="function" then
          seen[b]=true
          local button=b
          result[#result+1]={key=tostring(index)..":"..tostring(id),
            read=function() return safe(function() return button:isOn() end) end,
            set=function(value)
              if H.live(button) and button:isOn()~=value then button.onClick(button) end
            end}
        end
      end
    end
  end
  return result
end
function H.getState(m)
  if m.id=="botserver" then return storage.BOTserver and storage.BOTserver.enabled==true end
  if HelperPause and (m.id=="cavebot" or m.id=="targetbot") then return HelperPause.desired(m.id) end
  local known=false
  for _,power in ipairs(powers(m)) do
    local value=power.read()
    if value==true then return true end
    if value==false then known=true end
  end
  if known then return false end
end
function H.setEnabled(m,value)
  if not H.valid() then return end
  value=value==true
  if m.id=="botserver" then
    if H.getState(m)~=value and H.live(botServerWindow) and botServerWindow.enabled.onClick then
      botServerWindow.enabled.onClick(botServerWindow.enabled)
    end
    return
  end
  local controls=powers(m)
  if #controls==1 then controls[1].set(value); return end
  if #controls==0 then return end
  settings.powerGroups=type(settings.powerGroups)=="table" and settings.powerGroups or {}
  if not value then
    local saved,any={},false
    for _,power in ipairs(controls) do
      saved[power.key]=power.read()==true
      any=any or saved[power.key]
    end
    if any then settings.powerGroups[m.id]=saved end
    for _,power in ipairs(controls) do power.set(false) end
  else
    local saved=settings.powerGroups[m.id] or {}
    local restore=false
    for _,power in ipairs(controls) do restore=restore or saved[power.key]==true end
    -- Group OFF preserves the enabled selection; first ON enables its native controls.
    for _,power in ipairs(controls) do power.set(not restore or saved[power.key]==true) end
  end
end
local function visible(item,value)
  if H.live(item.widget) then item.widget:setVisible(value) end
end
local function hideForms()
  navigating=true
  for _,m in ipairs(H.order) do
    for _,item in ipairs(m.panels) do if item.mounted and not item.floatingPanel then visible(item,false) end end
    for _,item in ipairs(m.views) do if item.mounted and not item.floatingPanel then visible(item,false) end end
  end
  navigating=false
end
local function hostWidth(width)
  width=math.max(width or 0,window.viewport:getWidth()-2)
  for _,w in ipairs({window.viewport.host,window.viewport.host.menu,window.viewport.host.controls,window.viewport.host.forms}) do w:setWidth(width) end
end
H.reflow=function()
  local width=activeView and H.live(activeView.widget) and activeView.widget:getWidth()
  -- Menus use the visible width. Native forms keep their original dimensions.
  if not width and selected then
    width=310
    for _,item in ipairs(selected.panels) do
      if item.mounted and H.live(item.widget) then width=math.max(width,item.widget:getWidth()) end
    end
  end
  if not width then width=math.max(180,window.viewport:getWidth()-2) end
  hostWidth(width)
end
local function display(m,view)
  hideForms(); activeView=view
  header(m.name,m.id=="botserver" or m.id=="ingame_editor",false,m.id=="cavebot" and view==nil)
  window.viewport.host.menu:hide()
  window.viewport.host.controls:setVisible(view==nil)
  window.viewport.host.forms:setVisible(view~=nil)
  navigating=true
  local width=310
  if view then visible(view,true); width=math.max(width,view.widget:getWidth())
  else
    for _,item in ipairs(m.panels) do
      if item.mounted and not item.floatingPanel then
        visible(item,true); width=math.max(width,item.widget:getWidth())
      end
    end
  end
  hostWidth(width); navigating=false
  window.vertical:setValue(0); window.horizontal:setValue(0)
  text(window.footer.status,m.id=="ingame_editor" and "Scripts | Activa, edita o crea tus scripts" or m.name.." | Guarda desde el formulario")
end
local function addLabel(value,heading)
  local w=create(heading and "HelperHeading" or "HelperLabel",window.viewport.host.menu); w:setText(value)
end
local function bindToggleOnly(row,m)
  if m.id~="holdtarget" then return end
  row.name.onClick=row.power.onClick
  row.name:setTooltip(m.description.."\nActivar o desactivar Hold Target")
  row.setup.onClick=nil; row.setup:hide()
  if row.favorite then row.favorite:hide(); row.favorite:setWidth(0) end
end
local function addRow(m,compact,parent)
  local row=create(compact and "HelperQuickRow" or "HelperRow",parent or window.viewport.host.menu)
  row.name:setText(m.name); row.name:setTooltip(m.description.."\nAbrir configuracion completa")
  if RinoSkin and row.glyph then RinoSkin.icon(row.glyph,RinoSkin.iconName(m.id,m.section)) end
  row.name.onClick=function() H.openModule(m.id) end
  row.setup.onClick=row.name.onClick
  row.setup:setTooltip("Abrir configuracion completa")
  row.power.onClick=function()
    local enabled=H.getState(m)
    if enabled~=nil then H.setEnabled(m,not enabled); H.refresh() end
  end
  row.favorite:setOn(settings.favorites[m.id]==true)
  row.favorite:setText(settings.favorites[m.id] and "*" or "+")
  row.favorite:setTooltip("Agregar o quitar favorito")
  row.favorite.onClick=function()
    settings.favorites[m.id]=not settings.favorites[m.id]
    row.favorite:setOn(settings.favorites[m.id]); row.favorite:setText(settings.favorites[m.id] and "*" or "+")
  end
  bindToggleOnly(row,m)
  if row.glyph then
    row.glyph.rinoInteractive=true
    row.glyph:mergeStyle({phantom=false});row.glyph.onClick=row.name.onClick
    row.glyph:setTooltip(m.name.."\n"..m.description)
  end
  rows[#rows+1]={widget=row,module=m}
  local editor=vBot and vBot.IconEditor
  if m.id=="iconos" and not compact and editor and editor.setHoldToMove and editor.isHoldToMove then
    local drag=create("HelperRow",parent or window.viewport.host.menu)
    H.iconDragRow=drag
    if RinoSkin then RinoSkin.icon(drag.glyph,'tools') end
    drag.name:setText("Mover iconos")
    local tip="ON: arrastra el icono para moverlo sin espera. La posicion se guarda al soltar.\nOFF: arrastre bloqueado fuera del editor. Clic derecho abre su configuracion."
    drag.name:setTooltip(tip);drag.power:setTooltip(tip)
    drag.favorite:hide();drag.favorite:setWidth(0);drag.setup:hide()
    drag.name:setMarginRight(54)
    drag.power.onClick=function()
      editor.setHoldToMove(not editor.isHoldToMove());H.refresh()
    end
    drag.name.onClick=drag.power.onClick
  end
end
local function addFavorites()
  local grid=create("HelperFavoriteGrid",window.viewport.host.menu)
  local function fitGrid(w)
    local width=w:getWidth()
    if w.rinoWidth==width then return end
    local columns=width>=254 and 2 or 1
    local layout=w:getLayout()
    if layout then layout:setCellSize({width=math.max(1,math.floor((width-(columns-1)*6)/columns)),height=50});w.rinoWidth=width end
  end
  grid.onGeometryChange=fitGrid;fitGrid(grid)
  local count=0
  local short={pvp_support="CombatePvP",exivatarget="Exiva Target",exivalast="Exiva Last"}
  for _,m in ipairs(H.order) do
    if settings.favorites[m.id] and m.available and not m.hidden then
      count=count+1
      local row=create("HelperFavorite",grid)
      row.name:setText(short[m.id] or m.name)
      if RinoSkin then RinoSkin.icon(row.glyph,RinoSkin.iconName(m.id,m.section)) end
      row.name:setTooltip(m.name.."\n"..m.description)
      row.name.onClick=function() H.openModule(m.id) end
      row.setup.onClick=row.name.onClick
      row.setup:setTooltip("Abrir configuracion completa")
      row.power.onClick=function()
        local enabled=H.getState(m)
        if enabled~=nil then H.setEnabled(m,not enabled); H.refresh() end
      end
      bindToggleOnly(row,m)
      row.glyph.rinoInteractive=true
      row.glyph:mergeStyle({phantom=false});row.glyph.onClick=row.name.onClick
      row.glyph:setTooltip(m.name.."\n"..m.description)
      rows[#rows+1]={widget=row,module=m}
    end
  end
  if count==0 then
    grid:destroy()
    addLabel("Agrega favoritos con + en cada apartado.")
  end
end
local function matches(m,q,includeGrouped)
  if m.hidden or m.groupId and not includeGrouped then return false end
  if q=="" or (m.name.." "..m.description.." "..m.section):lower():find(q,1,true) then return true end
  if m.id=="pvp_support" then
    for _,id in ipairs(H.pvpModuleIds) do if matches(H.modules[id],q,true) then return true end end
  end
  local function scan(w)
    if not H.live(w) then return false end
    local t=safe(function() return w:getText() end)
    if t and tostring(t):lower():find(q,1,true) then return true end
    for _,child in ipairs(w:getChildren()) do if scan(child) then return true end end
    return false
  end
  for _,item in ipairs(m.panels) do if scan(item.widget) then return true end end
  for _,item in ipairs(m.views) do if scan(item.widget) then return true end end
  return false
end
function H.navigate(name)
  if rendering or not H.valid() then return end
  local q=window.search:getText():lower():gsub("^%s+",""):gsub("%s+$","")
  if name=="Navi" and q=="" then return H.openModule("botserver") end
  if name=="Scripts" and q=="" then return H.openModule("ingame_editor") end
  header(name,false,name=="Inicio" and q=="")
  rendering=true; section,selected,activeView,stack,expanded=name,nil,nil,{},false
  hideForms(); rows={}; window.viewport.host.menu:destroyChildren()
  window.viewport.host.menu:show(); window.viewport.host.controls:hide(); window.viewport.host.forms:hide()
  hostWidth(math.max(180,window.viewport:getWidth()-2)); changing=true
  window.selector:clearOptions(); window.selector:addOption(name..": funciones")
  local count=0
  if name=="Inicio" and q=="" then
    expanded=false
    H.Home.render(window.viewport.host.menu,create)
    addLabel("Favoritos",true)
    addFavorites()
  else
    for _,m in ipairs(H.order) do
      if m.available and (q~="" or m.section==name) and matches(m,q) then
        count=count+1; addRow(m)
        if m.id~="holdtarget" then window.selector:addOption(m.name,m.id) end
      end
    end
    if appearance and (name=="Ajustes" and q=="" or q~="" and ("apariencia colores paletas tema oscuro claro opacidad transparencia"):find(q,1,true)) then
      local row=create("HelperButton",window.viewport.host.menu)
      row:setText("Apariencia: colores y opacidad")
      row:setHeight(34);row:setTooltip("Paletas guardadas, colores del bot y transparencia de sus ventanas")
      row.onClick=function() appearance.open(H) end;count=count+1
    end
    if count==0 then addLabel("No hay funciones que coincidan.") end
  end
  changing=false
  for id,b in pairs(H.navButtons or {}) do b:setOn(id==name) end
  window.vertical:setValue(0); window.horizontal:setValue(0)
  text(window.footer.status,q~="" and "Pulsa el nombre para configurar" or "X recoge la ventana; las funciones siguen activas.")
  rendering=false; resize(); H.refresh()
end
local openerIds={
  attackbot={"settings"},healbot={"settings"},inmortal={"setup"},friend_healer={"edit"},
  conditions={"conditionList"},equipper={"setup"},botserver={"botServer"},
  containermanager={"mainSetup"},timerexecutor={"setup"},dummy={"setup"},alarms={"alerts"},
  combo_plus={"setup"},imbuementscrolls={"settings"},keepwall={"setup"},bugmapmouse={"setup"},
  pushmax={"push"},manatrainer={"settings"},zautobuff={"editSpellList"},
  ["z_auto-party"]={"editPlayerList"}
}
-- Independent OTUI shells own the same native forms, never another executor.
settings.panels=type(settings.panels)=="table" and settings.panels or {}
H.floatingPanels={}
local floatingModules={}
for _,m in ipairs(H.order) do
  -- The route workspace and full Navi dashboard stay directly in Helper.
  if m.id~="cavebot" and m.id~="botserver" then floatingModules[m.id]=true end
end
local function rememberPanel(panel)
  if not H.valid() or not H.live(panel.widget) then return end
  local p=panel.widget:getPosition()
  settings.panels[panel.key]={x=p.x,y=p.y}
end
function H.floatingOwner(w)
  for _,panel in ipairs(H.floatingPanels) do
    for _,item in ipairs(panel.items) do
      if item.floatingPanel==panel and H.live(item.widget) and H.inside(w,item.widget) then return panel.supplyDepot and item.module or panel.owner end
    end
  end
end
function H.isFloating(w) return H.floatingOwner(w)~=nil end
function H.closeFloatingPanel(panel,nativeClosed,collect)
  if panel.closing or not H.live(panel.widget) then return end
  panel.closing=true; rememberPanel(panel)
  for _,item in ipairs(panel.items) do
    if H.live(item.widget) then
      item.wantShow=false
      local native=item.widget
      local cancel=native.cancel or (native.footer and native.footer.cancel)
      local close=native.closeButton
      local requested=false
      if not nativeClosed then
        if H.live(cancel) and type(cancel.onClick)=="function" then cancel.onClick(cancel); requested=true
        elseif not collect and H.live(close) and type(close.onClick)=="function" then close.onClick(close); requested=true
        elseif not collect and item.window and type(native.onEscape)=="function" then native.onEscape(native); requested=true end
      end
      -- Editors such as Attack Studio can ask to apply/discard before closing.
      if requested and item.window and H.live(native) and native:isVisible() then
        item.wantShow=true; panel.closing=false; return
      end
      if H.live(item.widget) then
        if item.nativeHide then item.nativeHide(item.widget) else item.widget:hide() end
      end
    end
  end
  if H.live(panel.widget) then panel.widget:hide() end
  panel.closing=false
end
function H.closeFloatingPanels()
  if appearance then appearance.cancel() end
  local panels={}
  for _,panel in ipairs(H.floatingPanels) do panels[#panels+1]=panel end
  for _,panel in ipairs(panels) do H.closeFloatingPanel(panel,false,true) end
end
local function makeFloatingPanel(key,title)
  local w=H.originals.createWindow("HelperFloatingPanel",root)
  if HelperTheme then HelperTheme.decorate(w,"HelperFloatingPanel") end
  w.botWidget=true; w:hide()
  local panel={widget=w,key=key,items={}}
  H.floatingPanels[#H.floatingPanels+1]=panel
  w.heading:setText(title)
  if RinoSkin and w.glyph then RinoSkin.icon(w.glyph,'brand') end
  if RinoSkin and RinoSkin.prefix then RinoSkin.chrome(w.closeButton,'close','Cerrar panel') end
  w.closeButton.onClick=function() H.closeFloatingPanel(panel) end
  w.onClose=function() H.closeFloatingPanel(panel); return true end
  w.onEscape=w.onClose
  w.onGeometryChange=function() if panel.placed and not panel.positioning and not navigating then rememberPanel(panel) end end
  return panel
end
local function showFloatingPanel(panel,title)
  local w=panel.widget
  panel.positioning=true
  local width,height=0,0
  for _,item in ipairs(panel.items) do
    if H.live(item.widget) and (not panel.activeItem or item==panel.activeItem or item==panel.tabsItem) then
      width=math.max(width,item.size and item.size.width and item.size.width>0 and item.size.width or item.widget:getWidth())
      height=height+item.widget:getHeight()+5
    end
  end
  local bounds=root:getSize()
  w:setSize({width=math.min(math.max(340,width+32),math.max(280,bounds.width-16)),
    height=math.min(math.max(180,height+64),math.max(160,bounds.height-16))})
  w.viewport.host:setWidth(width)
  text(w.heading,title)
  local p=settings.panels[panel.key]
  if not panel.placed then
    local origin=window:getPosition()
    place(w,p or {x=origin.x+34,y=origin.y+50}); panel.placed=true
  else place(w) end
  w:show()
  for _,item in ipairs(panel.items) do
    if H.live(item.widget) and (not panel.activeItem or item==panel.activeItem or item==panel.tabsItem) then
      item.wantShow=true
      if item.nativeShow then item.nativeShow(item.widget) else item.widget:show() end
    end
  end
  if appearance then appearance.refreshOpacity() end
  w:raise(); panel.positioning=false; rememberPanel(panel)
end
function H.fitFloatingPanels()
  for _,panel in ipairs(H.floatingPanels) do
    if H.live(panel.widget) and panel.widget:isVisible() then
      showFloatingPanel(panel,panel.widget.heading:getText())
    end
  end
end
local function putInPanel(item,panel)
  item.floatingPanel=panel
  local w=item.widget
  w:setParent(panel.widget.viewport.host,true)
  w:breakAnchors()
  w:setMarginLeft(0); w:setMarginRight(0); w:setMarginTop(0); w:setMarginBottom(0)
end
local function embedView(item)
  local panel=item.floatingPanel
  if not panel then return end
  rememberPanel(panel); panel.widget:hide(); panel.items={}
  item.floatingPanel=nil
  item.widget:setParent(window.viewport.host.forms,true)
  item.widget:breakAnchors()
  if appearance then appearance.refreshOpacity(item.widget) end
end
function H.floatView(item,owner)
  if not H.valid() or not H.live(item.widget) then return end
  if item.floatingPanel and item.floatingPanel.supplyDepot and H.selectSupplyDepotPage then
    return H.selectSupplyDepotPage(item)
  end
  local panel=item.floatingPanel or item.popupPanel
  if not panel or not H.live(panel.widget) then
    panel=makeFloatingPanel(owner.id..":"..item.style,owner.name)
    item.popupPanel=panel
  end
  panel.owner=owner; panel.items={}
  if RinoSkin and panel.widget.glyph then RinoSkin.icon(panel.widget.glyph,RinoSkin.iconName(owner.id,owner.section)) end
  if owner.id=="iconos" and item.style=="IconEditorWindow" and not item.widget.simpleIcons and H.helperKeyControls then
    local controls=H.helperKeyControls
    if H.live(item.widget.helperHost) then
      controls.widget:setParent(item.widget.helperHost,true)
      controls.widget:setWidth(math.max(280,item.widget.helperHost:getWidth()))
      controls.floatingPanel=panel;controls.nested=true;controls.widget:show()
      item.widget.helperAvailable=true
      item.widget.helperTab:setEnabled(true)
      item.widget.helperNotice:hide()
    else panel.items[#panel.items+1]=controls end
  elseif owner.id=="equipper" and item.style=="EquipWindow" then
    -- These native master switches live outside their settings window.
    for _,controls in ipairs(owner.panels) do
      local w=controls.widget
      if controls.mounted and H.live(w) and (w.title or w.switch) then
        panel.items[#panel.items+1]=controls
        if H.live(w.setup) then w.setup:hide() end
      end
    end
  end
  panel.items[#panel.items+1]=item
  if owner.id=="conditions" and item.style=="ConditionsWindow" and H.foodSection then
    panel.items[#panel.items+1]=H.foodSection
    for _,controls in ipairs(H.modules.eat_food.panels) do
      if controls.foodIntegrated and H.live(controls.widget) then
        controls.floatingPanel=panel;controls.widget:show()
      end
    end
  end
  for _,entry in ipairs(panel.items) do putInPanel(entry,panel) end
  -- A native close action still runs its own save/cancel callback.
  local close=item.widget.closeButton
  if H.live(close) and close:getText()=="Volver" then close:setText("Cerrar") end
  showFloatingPanel(panel,item.dialogTitle or (owner.id=="cavebot" and
    (item.style=="CaveBotConfigWindow" and "CaveBot | Configuracion" or "CaveBot | Editor de accion") or owner.name))
end
local function floatControls(m)
  local panel=m.popupPanel
  if not panel or not H.live(panel.widget) then
    panel=makeFloatingPanel(m.id..":controls",m.name); m.popupPanel=panel
  end
  panel.owner=m; panel.items={}
  for _,item in ipairs(m.panels) do
    if item.mounted and H.live(item.widget) then
      panel.items[#panel.items+1]=item; putInPanel(item,panel)
    end
  end
  showFloatingPanel(panel,m.name)
end
local function moduleOptions(m)
  changing=true
  window.selector:clearOptions(); window.selector:addOption(m.name,m.id)
  for _,other in ipairs(H.order) do
    if other~=m and other.section==m.section and other.available and not other.hidden and not other.groupId then window.selector:addOption(other.name,other.id) end
  end
  changing=false
end
local function opener(m)
  if m.id=="supplies" and Supplies and Supplies.show then Supplies.show();return true end
  if m.id=="attackbot" and H.openAttackEditor then H.openAttackEditor();return true end
  if m.id=="ingame_editor" and vBot and vBot.InGameScriptManager and type(vBot.InGameScriptManager.open)=="function" then vBot.InGameScriptManager.open(); return true end
  if m.id=="itemcounter" and vBot.ItemCounter then vBot.ItemCounter.openSetup(); return true end
  if m.id=="updater" and SabuezoUpdaterBridge then SabuezoUpdaterBridge.open(); return true end
  if m.id=="iconos" and vBot.IconEditor then vBot.IconEditor.open(); return true end
  if m.id=="botsettings" and BotSettings then BotSettings.open("basic"); return true end
  if m.id=="cave_target_settings" and BotSettings then BotSettings.open("cave"); return true end
  for _,item in ipairs(m.panels) do
    if H.live(item.widget) then
      for _,id in ipairs(openerIds[m.id] or {}) do
        local b=item.widget:recursiveGetChildById(id)
        if b and type(b.onClick)=="function" then b.onClick(b); return true end
      end
    end
  end
  for _,item in ipairs(m.panels) do
    local w=item.widget
    if H.live(w) and type(w.onClick)=="function" and #m.views>0 then
      local t=tostring(safe(function() return w:getText() end) or ""):lower()
      if t:find("setting",1,true) or t:find("suppl",1,true) or t:find("editor",1,true) or t:find("list",1,true) then w.onClick(w); return true end
    end
  end
  return false
end
function H.openFloatingModule(m,fromIcon)
  if fromIcon and m.id=="cavebot" then return H.openModule("cavebot") end
  if not fromIcon and m.section=="CaveBot" and selected~=H.modules.cavebot then H.openModule("cavebot") end
  local previous=H.requestedFloating
  H.requestedFloating=m
  local opened=opener(m)
  if not opened then
    local view
    if m.id~="targetbot" then
      for _,item in ipairs(m.views) do
        if item.style~="HelperTextDialog" and item.mounted and H.live(item.widget) then view=item; break end
      end
    end
    if view then H.floatView(view,m) else floatControls(m) end
  end
  H.requestedFloating=previous
  if selected then moduleOptions(selected)
  else
    -- Keep the current menu and scroll position, including search results.
    changing=true
    window.selector:clearOptions(); window.selector:addOption(section..": funciones")
    if section~="Inicio" or window.search:getText():match("%S") then
      for _,row in ipairs(rows) do
        if row.module.id~="holdtarget" then window.selector:addOption(row.module.name,row.module.id) end
      end
    end
    changing=false
  end
end
-- Icon settings open independently; CaveBot opens its main route workspace.
function H.openIconConfiguration(id)
  if not H.valid() then return false end
  local m=H.modules[id]
  if not m then return false end
  if H.openCombatePvP and (id=="pvp_support" or m.groupId=="pvp_support") then
    H.openCombatePvP(id)
  else H.openFloatingModule(m,true) end
  return true
end
function H.openAttackFromTargetIcon()
  if not H.valid() then return false end
  local target=H.modules.targetbot
  for _,panel in ipairs(H.floatingPanels) do
    if panel.owner==target and H.live(panel.widget) then
      H.closeFloatingPanel(panel,true)
    end
  end
  return H.openIconConfiguration('attackbot')
end
function H.openModule(id)
  local grouped=H.modules[id]
  if H.openCombatePvP and (id=="pvp_support" or grouped and grouped.groupId=="pvp_support") then
    return H.openCombatePvP(id)
  end
  if id=="dash" then return end
  if id=="eat_food" then return H.openModule("conditions") end
  if id=="cavebot_control_panel" and H.routeActions and #H.routeActions==4 then return H.openModule("cavebot") end
  if id=="cave_target_settings" and H.openCaveTargetConfig then return H.openCaveTargetConfig() end
  if id=="holdtarget" then
    if H.valid() then H.navigate("Combate"); H.show() end
    return
  end
  if id=="exivatarget" or id=="exivalast" then return H.openModule("pvp_support") end
  local m=H.modules[id]
  if not m or not H.valid() then return end
  if floatingModules[id] and id~="ingame_editor" then return H.openFloatingModule(m) end
  selected,section,stack,activeView=m,m.section,{},nil
  expanded=true; resize(); moduleOptions(m); display(m,nil)
  for name,b in pairs(H.navButtons) do b:setOn(name==section) end
  H.requestedModule=m
  local opened=opener(m)
  H.requestedModule=nil
  if not opened and (#m.panels==0 or id=="botserver") and #m.views>0 then H.openView(m.views[1]) end
  H.show()
end
function H.openView(item)
  if navigating or not H.valid() or not item.mounted then return end
  if H.openCombatePvP and item.module.groupId=="pvp_support" and
      item.style~="HelperTextDialog" and item.style~="HelperSinglelineDialog" then
    return H.openCombatePvP(item.module.id)
  end
  local m=H.requestedFloating or H.requestedModule or item.module
  if H.requestedFloating or (floatingModules[m.id] and item.style~="InGameScriptManagerWindow") or (m.section=="CaveBot" and item.window) or
      (item.floatingPanel and not H.requestedModule) then
    return H.floatView(item,H.requestedFloating or (item.floatingPanel and item.floatingPanel.owner) or m)
  end
  embedView(item)
  if selected~=m then selected,section,stack=m,m.section,{} end
  if activeView and activeView~=item then stack[#stack+1]=activeView end
  expanded=true; resize(); display(m,item)
  if item.style=="InGameScriptManagerWindow" then
    for name,b in pairs(H.navButtons or {}) do b:setOn(name=="Scripts") end
  end
  H.show()
end
function H.mount(item)
  local w=item.widget
  if item.mounted or not H.live(w) then return end
  for other in pairs(H.widgets) do
    if other~=w and H.inside(w,other) then item.nested=true; return end
  end
  item.mounted=true; navigating=true
  w:setParent(item.window and window.viewport.host.forms or window.viewport.host.controls,true)
  w:breakAnchors()
  w:setMarginLeft(0); w:setMarginRight(0); w:setMarginTop(0); w:setMarginBottom(0)
  w:setWidth(item.size and item.size.width and item.size.width>0 and item.size.width or 300)
  if item.window then
    w.helperEmbedded=true
    pcall(function() w:setDraggable(false) end)
    w:setText(""); pcall(function() w:setImageSource("") end)
    local show,hide=w.show,w.hide
    item.nativeShow,item.nativeHide=show,hide
    w.show=function(widget)
      if not H.valid() or not H.live(widget) then return end
      item.wantShow=true
      if item.style=="AttackBotWindow" and H.openAttackEditor then H.openAttackEditor();return end
      show(widget); if not navigating then H.openView(item) end
    end
    w.hide=function(widget)
      if not H.valid() or not H.live(widget) then return end
      -- Direct workspaces have no intermediate controls page: Close collects Helper.
      if (item.style=="BotServerWindow" or item.style=="InGameScriptManagerWindow") and activeView==item and not navigating then H.fold(); return end
      item.wantShow=false
      hide(widget)
      if item.floatingPanel then H.closeFloatingPanel(item.floatingPanel,true); return end
      if not navigating and activeView==item then
        local prior=table.remove(stack)
        local owner=selected or item.module
        if prior and H.live(prior.widget) then display(owner,prior) else display(owner,nil) end
      end
    end
    local originalGeometry=w.onGeometryChange
    w.onGeometryChange=function(widget,old,new)
      if type(originalGeometry)=="function" then originalGeometry(widget,old,new) end
      if not H.valid() or navigating or resizing or not old or not new or
          (old.height==new.height and (item.style~="InGameScriptManagerWindow" or old.width==new.width)) then return end
      -- Navi grows when opening its map/alerts; keep its outer shell in sync.
      if activeView==item then resize()
      elseif item.floatingPanel and not item.floatingPanel.positioning
        and not item.floatingPanel.closing and not item.floatingPanel.disposing
        and H.live(item.floatingPanel.widget) and item.floatingPanel.widget:isVisible() then
        -- A layout/height update resizes an open shell; it never opens a closed one.
        showFloatingPanel(item.floatingPanel,item.floatingPanel.widget.heading:getText())
      end
    end
    local originalDestroy=w.onDestroy
    w.onDestroy=function(widget)
      if type(originalDestroy)=="function" then originalDestroy(widget) end
      item.wantShow=false
      local panel=item.floatingPanel
      if panel and H.valid() and not panel.disposing then
        panel.disposing=true; item.floatingPanel=nil; panel.items={}
        if H.live(panel.widget) then panel.widget:destroy() end
        for i,p in ipairs(H.floatingPanels) do if p==panel then table.remove(H.floatingPanels,i); break end end
      end
      if H.valid() and not navigating and activeView==item then
        local prior=table.remove(stack)
        local owner=selected or item.module
        if prior and H.live(prior.widget) then display(owner,prior) else display(owner,nil) end
      end
    end
  end
  if appearance then appearance.refreshOpacity(w) end
  w:setVisible(false); navigating=false
end
local function navigateSection(name)
  if rendering or not H.valid() then return end
  -- Leaving search is explicit navigation; clearing text must not render the old section.
  rendering=true
  text(window.search,"")
  rendering=false
  if name=="Navi" then H.openModule("botserver")
  elseif name=="CaveBot" and H.live(H.cavePanel) then H.openModule("cavebot")
  elseif name=="Scripts" then H.openModule("ingame_editor")
  else H.navigate(name); H.show() end
end
H.navButtons={}
for _,name in ipairs(H.sections) do
  local tab=name; local b=create("HelperNavButton",window.nav)
  b:setText(H.sectionLabels[name] or name)
  if RinoSkin then RinoSkin.icon(b.glyph,RinoSkin.sections[name]) end
  b.onClick=function() navigateSection(tab) end
  H.navButtons[name]=b
end
window.back.onClick=function() navigateSection("Inicio") end
window.selector.onOptionChange=function()
  if changing then return end
  local option=window.selector:getCurrentOption()
  if option and H.modules[option.data] then H.openModule(option.data) end
end
window.search.onTextChange=function() if not rendering then H.navigate(section) end end
window.footer.pause.onClick=function() HelperPause.setPaused(not HelperPause.isPaused()) end
window.footer.pause:setTooltip("Solo CaveBot y TargetBot. ON/OFF conserva el estado deseado. AttackBot, curacion, proteccion y Navi siguen funcionando.")
window.footer.updater.onClick=function() H.openModule("updater") end
window.cavePower.onClick=function()
  if not H.valid() then return end
  local m=H.modules.cavebot
  local enabled=H.getState(m)
  if enabled~=nil then
    (enabled and CaveBot.setOff or CaveBot.setOn)()
    H.refresh()
  end
end
function H.refresh()
  if not H.valid() or not H.live(window) or not H.live(icon) then return end
  if H.Home then H.Home.tick() end
  local active,known=0,0
  for _,id in ipairs({"attackbot","targetbot","healbot","inmortal","cavebot","botserver"}) do
    local value=H.getState(H.modules[id])
    if value~=nil then known=known+1; if value then active=active+1 end end
  end
  local paused=HelperPause and HelperPause.isPaused()
  icon:setTooltip("RBot | RinoBot | "..active.."/"..known.." funciones activadas\nArrastrar mueve; clic abre/recoge")
  if not window:isVisible() then return end
  local caveState=H.getState(H.modules.cavebot)
  window.cavePower:setOn(caveState==true);window.cavePower:setEnabled(caveState~=nil)
  window.cavePower:setTooltip(paused and "En pausa. ON/OFF indica el estado al reanudar." or
    "Activa o detiene CaveBot. Al activar, apaga Grabar ruta.")
  for _,row in ipairs(rows) do
    local m,b=row.module,row.widget.power
    local enabled=H.getState(m)
    b:setVisible(enabled~=nil)
    row.widget.setup:hide()
    if row.widget:getParent()==window.viewport.host.menu then row.widget.name:setMarginRight(enabled==nil and 3 or 54) end
    b:setEnabled(enabled~=nil); b:setOn(enabled==true)
    text(b.caption,enabled==nil and "--" or enabled and "ON" or "OFF")
    if not RinoSkin then b.caption:setMarginLeft(0) end
    local grouped=#powers(m)>1
    b:setTooltip(paused and (m.id=="cavebot" or m.id=="targetbot") and "En pausa. ON/OFF es el estado al reanudar." or
      grouped and "ON: alguna funcion activa. OFF apaga el grupo; ON restaura la seleccion anterior o activa todas en el primer uso." or "Cambiar estado real")
  end
  if H.live(H.iconDragRow) and vBot and vBot.IconEditor and vBot.IconEditor.isHoldToMove then
    local enabled=vBot.IconEditor.isHoldToMove()
    H.iconDragRow.power:setOn(enabled)
    text(H.iconDragRow.power.caption,enabled and "ON" or "OFF")
  end
  local character=safe(function() return player and player:getName() end) or "Sin personaje"
  local profile=safe(function() return g_settings.getNumber("profile") end) or "?"
  text(window.character,HelperProfiles and HelperProfiles.valid() and character or character.." | Helper / "..tostring(profile))
  window.character:setTooltip(character)
  if H.refreshProfiles then H.refreshProfiles() end
  text(window.footer.pause,paused and "Reanudar Cave + Target" or "Pausar Cave + Target")
  if RinoSkin and RinoSkin.prefix then RinoSkin.chromeGlyph(window.footer.pause.glyph,paused and 'play' or 'pause')end
  window.footer.pause:setOn(paused==true)
  text(window.footer.updater,"Updater "..(SabuezoUpdaterBridge and SabuezoUpdaterBridge.getVersion() or "?"))
end
-- Use the bot's own single event listener, cleaned up by game_bot on reload.
-- Other gameplay hotkeys keep their listeners; no keyboard binding is removed.
local helperKey=""
local function keyToggle()
  if not H.valid() then return end
  if window:isVisible() then H.fold() else H.show() end
end
H.unbind=function() helperKey="" end
local function bindKey(key)
  key=tostring(key or ""):gsub("^%s+",""):gsub("%s+$","")
  helperKey=key
end
onKeyDown(function(keys)
  if H.valid() and helperKey~="" and tostring(keys):lower()==helperKey:lower() then keyToggle() end
end)
local keyPanel=create("HelperGroup",window.viewport.host.controls); keyPanel:setWidth(310)
local label=create("HelperLabel",keyPanel); label:setText("Tecla para abrir Helper (vacio = ninguna)")
local input=create("HelperInput",keyPanel); input:setText(settings.hotkey or "")
local keySave=create("HelperButton",keyPanel); keySave:setText("Guardar tecla del Helper")
keySave.onClick=function() settings.hotkey=input:getText(); bindKey(settings.hotkey) end
local sizeLabel=create("HelperLabel",keyPanel); sizeLabel:setText("Tamano de la ventana")
local sizePreset=create("HelperSelector",keyPanel); sizePreset:setHeight(26)
for _,name in ipairs({"Normal","Pequeno","Grande"}) do sizePreset:addOption(name) end
if sizePreset.setCurrentOption then sizePreset:setCurrentOption(settings.sizePreset or "Normal") end
sizePreset.onOptionChange=function()
  local option=sizePreset:getCurrentOption()
  if option then settings.sizePreset=option.text; resize() end
end
-- Use the client's own reload: it saves storage and clears the old executor.
function H.reloadBot()
  if not H.valid() or reloading then return false end
  if type(reload) ~= "function" then
    warn("La recarga del bot no esta disponible en este cliente.")
    return false
  end
  save()
  if Supplies and type(Supplies.save)=="function" and H.live(SuppliesWindow) and SuppliesWindow:isVisible() then Supplies.save() end
  settings.legacy = false
  reloading = true
  H.keepNativeHiddenOnDispose = true
  window.reloadBot:setEnabled(false)
  local ok = pcall(reload)
  if not ok then
    reloading = false
    H.keepNativeHiddenOnDispose = false
    if H.valid() and H.live(window.reloadBot) then window.reloadBot:setEnabled(true) end
    warn("No se pudo recargar el bot. Vuelve a intentarlo o revisa la consola del cliente.")
  end
  return ok
end
window.reloadBot.onClick = H.reloadBot
window.reloadBot:setTooltip("Recargar el bot en modo Helper. Conserva los ajustes guardados y la posicion del icono.")
function H.useClassicMode()
  if not H.valid() or reloading then return end
  save(); H.closeFloatingPanels()
  settings.legacy=true
  if type(reload)=="function" then reload() end
end
window.footer.classicMode.onClick=H.useClassicMode
window.footer.classicMode:setTooltip("Usar las pestanas y ventanas del modo clasico. Recarga el bot y conserva tus configuraciones.")
H.helperKeyControls={widget=keyPanel,module=H.modules.iconos,style="HelperControls",mounted=true,size={width=310}}
H.modules.iconos.panels[#H.modules.iconos.panels+1]=H.helperKeyControls
H.helperKeyControls.dialogTitle="Ajustes del Helper"
function H.openHelperSettings()
  if not H.valid() then return false end
  H.floatView(H.helperKeyControls,H.modules.iconos);return true
end
keyPanel:hide(); bindKey(settings.hotkey)

-- Text editors are child forms too, including aliases bound to native labels.
-- Reuse one dialog per module; validation callbacks can refuse a save.
local textDialogs={}
function H.editText(value,options,callback)
  options=options or {}
  local m=H.textOwner or H.requestedFloating or selected or H.modules.ingame_editor
  local targetWidget=(type(value)=="table" or type(value)=="userdata") and value or nil
  if targetWidget then m=H.floatingOwner(targetWidget) or m end
  local contents=targetWidget and targetWidget:getText() or tostring(value or "")
  local singleline=options.multiline==false
  local routeName=singleline and m.id=="cavebot" and options.title=="Enter config name"
  local key=m.id..(singleline and ":singleline" or "")
  local style=singleline and "HelperSinglelineDialog" or "HelperTextDialog"
  local item=textDialogs[key]
  if not item then
    local w=H.originals.createWindow(style,root)
    H.record(w,style,true,m.id)
    item=H.widgets[w]; H.mount(item); textDialogs[key]=item
  end
  local w=item.widget
  item.dialogTitle=routeName and "CaveBot | Nueva ruta" or (singleline and (options.title or "Editar") or nil)
  w.description:setText(routeName and "Nombre de la nueva ruta" or
    ((options.title or "Editar")..(options.description and "\n"..options.description or "")))
  w.editor:setText(routeName and "" or contents)
  if w.feedback then w.feedback:setText("") end
  w.accept:setText(routeName and "Crear ruta" or "Guardar")
  local function refuse(message)
    if w.feedback then w.feedback:setText(message) else warn(message) end
    w.editor:focus()
    return false
  end
  w.cancel.onClick=function() w:hide() end
  if H.live(w.closeButton) then w.closeButton.onClick=w.cancel.onClick end
  w.onEscape=function() w:hide(); return true end
  w.accept.onClick=function()
    local draft=w.editor:getText()
    if routeName then
      draft=draft:gsub("^%s+",""):gsub("%s+$",""):gsub("%s+","_")
      if draft=="" then return refuse("Escribe un nombre para la ruta.") end
      if #draft>=30 then return refuse("Usa un nombre de menos de 30 caracteres.") end
      if draft:find('[%c/\\:*?"<>|]') or draft=="." or draft==".." then
        return refuse("Evita / \\ : * ? y otros caracteres de archivo.")
      end
      if Config and type(Config.list)=="function" then
        for _,name in ipairs(Config.list("cavebot_configs")) do
          if name:lower()==draft:lower() then return refuse("Ya existe una ruta con ese nombre.") end
        end
      end
    end
    if w.feedback then w.feedback:setText("") end
    local result
    if callback then
      local ok,value=pcall(callback,draft)
      if not ok then return refuse("No se pudo guardar. Revisa el valor e intenta de nuevo.") end
      result=value
    elseif targetWidget and H.live(targetWidget) then targetWidget:setText(draft) end
    if not H.live(w) then return end
    if result==false then
      if w.feedback then return refuse(w.feedback:getText()~="" and w.feedback:getText() or "Revisa el valor antes de guardar.") end
      return false
    end
    if routeName and Config and type(Config.list)=="function" then
      local created=false
      for _,name in ipairs(Config.list("cavebot_configs")) do if name==draft then created=true;break end end
      if not created then return refuse("No se pudo crear la ruta. Intenta con otro nombre.") end
    end
    w:hide()
  end
  w.editor.onEnter=singleline and function() w.accept.onClick();return true end or nil
  if m.section=="CaveBot" then
    local previous=H.requestedFloating; H.requestedFloating=m
    w:show(); H.requestedFloating=previous
  else w:show() end
  w.editor:focus()
  return w
end
-- A named profile uses the same native reload as the header button.
local fillingProfiles, profileRevision = false, nil
function H.refreshProfiles()
  local P=HelperProfiles
  local available=P and P.valid()
  window.profileList:setVisible(available==true)
  window.newProfile:setVisible(available==true)
  window.autoProfile:setVisible(available==true)
  if not available then return end
  if profileRevision==P.revision then return end
  fillingProfiles=true
  window.profileList:clearOptions()
  for _,entry in ipairs(P.list()) do window.profileList:addOption(entry.name,entry.id) end
  window.profileList:setCurrentOption(P.name())
  fillingProfiles=false; profileRevision=P.revision
  window.profileList:setTooltip("Perfil activo: "..P.name()..". Cambiar guarda los ajustes y recarga el bot. La eleccion se recuerda para este personaje.")
  window.autoProfile:setTooltip("Volver al perfil de "..P.character..". Cada personaje recibe uno automaticamente.")
end
local function prepareProfileChange()
  if not H.valid() or reloading then return false end
  if type(reload)~="function" then warn("La recarga del bot no esta disponible.");return false end
  H.closeFloatingPanels()
  for _,panel in ipairs(H.floatingPanels) do
    if H.live(panel.widget) and panel.widget:isVisible() then
      warn("Guarda o descarta los cambios del editor abierto antes de cambiar de perfil.")
      return false
    end
  end
  return true
end
function H.switchProfile(id)
  local P=HelperProfiles
  if not P or not P.valid() or id==P.activeId then return false end
  if not prepareProfileChange() then profileRevision=nil;H.refreshProfiles();return false end
  save()
  local ok,message=P.select(id)
  if not ok then warn(message);profileRevision=nil;H.refreshProfiles();return false end
  if not H.reloadBot() then
    local restored,detail=P.cancelSelection()
    if not restored then warn(detail) end
    profileRevision=nil;H.refreshProfiles();return false
  end
  return true
end
window.profileList.onOptionChange=function()
  if fillingProfiles or reloading then return end
  local option=window.profileList:getCurrentOption()
  if option then H.switchProfile(option.data) end
end
window.autoProfile.onClick=function()
  if HelperProfiles then H.switchProfile(HelperProfiles.automaticId) end
end
window.newProfile:setTooltip("Crear un perfil con nombre personalizado y ajustes predeterminados.")
window.newProfile.onClick=function()
  local P=HelperProfiles
  if not P or not P.valid() or not prepareProfileChange() then return end
  local previous=H.textOwner
  H.textOwner=H.modules.iconos
  local dialog
  dialog=H.editText("",{title="Nuevo perfil",description="Ajustes predeterminados",multiline=false},function(name)
    local ok,id=P.create(name)
    if not ok then
      if H.live(dialog) and dialog.feedback then dialog.feedback:setText(id) end
      return false
    end
    if H.live(dialog) then dialog:hide() end
    return H.switchProfile(id)
  end)
  H.textOwner=previous
  dialog.description:setText("Nombre del perfil (ajustes predeterminados)")
  dialog.accept:setText("Crear perfil")
end
H.refreshProfiles()

H.originals.EditorWindow=UI.EditorWindow
H.originals.MultilineEditorWindow=UI.MultilineEditorWindow
UI.EditorWindow=H.editText
UI.MultilineEditorWindow=H.editText

local function customPanel(id,style)
  local m=H.modules[id]
  local w=create(style or "HelperGroup",window.viewport.host.controls); w:setWidth(310)
  m.panels[#m.panels+1]={widget=w,mounted=true,size={width=310}}
  m.available=true; w:hide()
  return w
end
local auxiliaryRows={}
local function enginePanel(id,description)
  local w=customPanel(id)
  local row=create("HelperRow",w)
  w.helperPowerRow=row
  row.name:setText(H.modules[id].name); row.favorite:hide()
  row.name.onClick=function() end
  row.power.onClick=function()
    local state=H.getState(H.modules[id])
    if state~=nil then H.setEnabled(H.modules[id],not state); H.refresh() end
  end
  auxiliaryRows[#auxiliaryRows+1]={widget=row,module=H.modules[id]}
  local help=create("HelperLabel",w); help:setHeight(44);help:setText(description)
  -- Only this longer description wraps; standard headings stay on one line.
  if help.setTextWrap then help:setTextWrap(true) end
  return w
end
enginePanel("pullitems","Recoge objetos de las ocho casillas cercanas. Usa el ejecutor actual.")
enginePanel("dash","Movimiento con WASD. Activar conserva las teclas y el ejecutor actuales.")
local fire=enginePanel("firebomb","Activar puede usar una runa inmediatamente. Conserva la deteccion de fuego actual.")
local fireLabel=create("HelperLabel",fire); fireLabel:setText("Runa Fire Bomb")
local fireItem=create("BotItem",fire); fireItem:setSize({width=36,height=36})
if storage.fireBomb then fireItem:setItemId(storage.fireBomb.fireBombRuneId or 3192) end
local fireSave=create("HelperButton",fire); fireSave:setText("Guardar runa")
fireSave.onClick=function()
  local id=tonumber(fireItem:getItemId())
  if storage.fireBomb and id and id>0 then storage.fireBomb.fireBombRuneId=id end
end
local pvp=customPanel("pvp_support","HelperPvPDashboard")
pvp:setSize({width=696,height=524})
local pvpHeaders={pushmax=pvp.push.header,keepwall=pvp.keep.header,firebomb=pvp.fire.header,
  holdtarget=pvp.hold.header,pullitems=pvp.pull.header,exivatarget=pvp.exiva.target,exivalast=pvp.exiva.last,antipush1=pvp.anti.header}
local pvpRows={}
for _,id in ipairs(H.pvpModuleIds) do
  local m,header=H.modules[id],pvpHeaders[id]
  m.available=true
  header.name:setText(m.name);header.name:setTooltip(m.description)
  header.power:setTooltip("Activar o desactivar "..m.name)
  if RinoSkin then RinoSkin.icon(header.glyph,RinoSkin.iconName(id,m.section)) end
  header.power.onClick=function()
    if not H.valid() then return end
    local state=H.getState(m)
    if state~=nil then H.setEnabled(m,not state);H.refresh() end
  end
  pvpRows[#pvpRows+1]={widget=header,module=m}
end
pvpHeaders.firebomb.power:setTooltip("Activar puede usar una runa inmediatamente.")
pvp.exiva.spell:setText(storage.pvpSupport and storage.pvpSupport.exivaSpell or "exiva")
pvp.exiva.save.onClick=function()
  if not H.valid() then return end
  local value=pvp.exiva.spell:getText():gsub("^%s+",""):gsub("%s+$","")
  if value~="" and storage.pvpSupport then storage.pvpSupport.exivaSpell=value end
end
H.pvpControls={widget=pvp,headers=pvpHeaders,spell=pvp.exiva.spell,spellSave=pvp.exiva.save,
  fireItem=fireItem,fireSave=fireSave,cards={pushmax=pvp.push,keepwall=pvp.keep,firebomb=pvp.fire,
    holdtarget=pvp.hold,pullitems=pvp.pull,exivatarget=pvp.exiva,exivalast=pvp.exiva,antipush1=pvp.anti},nativeViews={}}
local spy=customPanel("spy_level")
local spyLabel=create("HelperLabel",spy); spyLabel:setText("Teclas para subir y bajar el piso visible")
local up=create("HelperInput",spy)
local down=create("HelperInput",spy)
local spyConfig=SpyLevelBridge and SpyLevelBridge.getConfig() or {}
up:setText(spyConfig.up or ""); down:setText(spyConfig.down or "")
local spySave=create("HelperButton",spy); spySave:setText("Guardar teclas de Spy Level")
spySave.onClick=function() if SpyLevelBridge then SpyLevelBridge.applyConfig(up:getText(),down:getText()) end end
H.modules.cave_target_settings.available=BotSettings~=nil

-- Keep auxiliary toggle rows synchronized without another executor.
local refresh=H.refresh
H.refresh=function()
  refresh()
  if not H.valid() then return end
  local extraRows={}
  for _,row in ipairs(pvpRows) do extraRows[#extraRows+1]=row end
  for _,row in ipairs(auxiliaryRows) do extraRows[#extraRows+1]=row end
  for _,row in ipairs(extraRows) do
    if H.live(row.widget) and row.widget:isVisible() then
      local state=H.getState(row.module)
      local on=state==true
      row.widget.power:setVisible(state~=nil);row.widget.power:setEnabled(state~=nil)
      row.widget.power:setOn(on); row.widget.power.caption:setText(on and "ON" or "OFF")
      if not RinoSkin then row.widget.power.caption:setMarginLeft(0) end
    end
  end
  if not window:isVisible() then return end
  local opener=vBot and vBot.BotServerOpener
  if H.live(opener) then
    local tooltip=safe(function() return opener:getTooltip() end)
    if tooltip and tooltip~="" then
      for _,row in ipairs(rows) do if row.module.id=="botserver" then row.widget.name:setTooltip(tooltip) end end
    end
  end
end
for _,m in ipairs(H.order) do
  for _,item in ipairs(m.panels) do if not item.mounted then H.mount(item) end end
  for _,item in ipairs(m.views) do H.mount(item) end
end
-- All PvP functions share a compact dashboard. Keep native fields
-- inside their original windows: their callbacks still resolve those IDs.
do
  local owner=H.modules.pvp_support
  local panel,controls
  for _,item in ipairs(owner.panels) do if item.widget==pvp then controls=item;break end end
  controls.size={width=696,height=524}
  local function placeField(w,x,y,width,height)
    if not H.live(w) then return end
    w:breakAnchors()
    w:applyStyle({["anchors.left"]="parent.left",["anchors.top"]="parent.top",
      ["margin-left"]=x,["margin-top"]=y,["margin-right"]=0,["margin-bottom"]=0,
      width=width,height=height,["text-align"]="left"})
    w:setSize({width=width,height=height})
  end
  local positions={
    pushmax={delayText={0,0,328,16},delay={0,18,328,14},label3={0,38,64,16},
      label2={66,38,64,16},label4={132,38,64,16},runeId={16,56,32,32},
      mwallId={82,56,32,32},finalMwallRuneId={148,56,32,32},
      destroyRuneLabel={198,38,64,16},destroyRuneId={214,56,32,32},
      disintegrateLabel={264,38,64,16},disintegrateRuneId={280,56,32,32},label5={0,94,328,16},
      destroyFieldIds={0,112,328,22},label1={0,144,328,16},hotkey={0,162,328,22}},
    keepwall={runeLabel={0,0,80,16},runeId={24,22,32,32},delayText={94,0,234,16},
      delay={94,22,234,14},hotkeyLabel={94,46,234,16},hotkeyButton={94,64,234,22}},
    antipush1={itemsLabel={0,0,332,16},DropItems={0,18,332,64},hotkeyLabel={350,0,100,22},
      HotkeyButton={450,0,234,22},withdrawLabel={350,32,100,22},WithdrawButton={450,32,234,22},
      movementLabel={350,60,214,22},MovementGuard={570,60,114,22}}
  }
  H.pvpControls.nativeLayout=positions
  local function borrow(id,style,body,height)
    for _,item in ipairs(H.modules[id].views) do
      if item.style==style and item.mounted and H.live(item.widget) then
        local w=item.widget
        w:setParent(body,true);placeField(w,0,0,328,height)
        w:mergeStyle({padding=0,["padding-top"]=0,["padding-bottom"]=0,["padding-left"]=0,["padding-right"]=0})
        for field,rect in pairs(positions[id]) do placeField(w[field],rect[1],rect[2],rect[3],rect[4]) end
        if id=="pushmax" then
          w.label3:setText(PushMax and PushMax.experimentalDistanceFire and "Fire Field"or PushMax and PushMax.experimentalNoFire and "Sin fuego"or "AntiPush");w.label2:setText("MW obj.");w.label4:setText("MW final")
          w.label5:setText("IDs de Destroy Field");w.label1:setText("Hotkey de Push Max")
        else w.runeLabel:setText("Runa MW");w.hotkeyLabel:setText("Hotkey de Keep Wall") end
        if H.live(w.closeButton) then w.closeButton:hide() end
        if H.live(w.separator) then w.separator:hide() end
        item.floatingPanel=panel;panel.items[#panel.items+1]=item
        H.pvpControls.nativeViews[id]=w
        return
      end
    end
    local missing=create("HelperLabel",body);missing:setText("Configuracion no disponible.")
  end
  local function borrowAntiPush()
    for _,item in ipairs(H.modules.antipush1.panels) do
      local w=item.widget
      if item.mounted and H.live(w) and H.live(w:recursiveGetChildById("HotkeyButton")) and
          H.live(w:recursiveGetChildById("DropItems")) then
        w:setParent(pvp.anti.body,true);placeField(w,0,0,684,84)
        for field,rect in pairs(positions.antipush1) do placeField(w[field],rect[1],rect[2],rect[3],rect[4]) end
        w.itemsLabel:setText("Objetos para tirar");w.withdrawLabel:setText("Retiro automatico")
        item.floatingPanel=panel;panel.items[#panel.items+1]=item
        H.pvpControls.nativeViews.antipush1=w
        return
      end
    end
    local missing=create("HelperLabel",pvp.anti.body);missing:setText("Configuracion no disponible.")
  end
  local hint=create("HelperLabel",pvp.hold.body);hint:setText("Conserva el objetivo actual.")
  placeField(hint,0,0,336,18)
  hint=create("HelperLabel",pvp.pull.body);hint:setText("Recoge objetos de alrededor.")
  placeField(hint,0,0,336,18)
  fireItem:setParent(pvp.fire.body,true);placeField(fireItem,0,4,32,32)
  local runeLabel=create("HelperLabel",pvp.fire.body);runeLabel:setText("Runa")
  placeField(runeLabel,40,10,68,18)
  fireSave:setParent(pvp.fire.body,true);placeField(fireSave,116,8,220,24)
  function H.openCombatePvP(id)
    if not H.valid() then return end
    if not panel or not H.live(panel.widget) then
      panel=makeFloatingPanel("pvp_support:controls",owner.name)
      panel.owner=owner;owner.popupPanel=panel;H.pvpPanel=panel
      panel.items={controls};panel.activeItem=controls
      putInPanel(controls,panel)
      borrow("pushmax","PushMaxWindow",pvp.push.body,192)
      borrow("keepwall","KeepWallWindow",pvp.keep.body,100)
      borrowAntiPush()
      if RinoSkin then RinoSkin.icon(panel.widget.glyph,"combat") end
    end
    if not panel.widget:isVisible() then
      pvp.exiva.spell:setText(storage.pvpSupport and storage.pvpSupport.exivaSpell or "exiva")
      if storage.fireBomb then fireItem:setItemId(storage.fireBomb.fireBombRuneId or 3192) end
    end
    panel.currentId=id
    panel.widget.vertical:setValue(0);panel.widget.horizontal:setValue(0)
    showFloatingPanel(panel,owner.name)
    for _,item in ipairs(panel.items) do
      if item~=controls and H.live(item.widget) then
        item.wantShow=true
        if item.nativeShow then item.nativeShow(item.widget) else item.widget:show() end
      end
    end
    H.refresh()
  end
end
-- Comida is part of the Conditions popup. Reparent the original macro switches
-- and food selector without copying engines, state, callbacks or item settings.
do
  local food=H.modules.eat_food
  if food and #food.panels>0 then
    local group=create("HelperFoodSection",window.viewport.host.controls)
    group:setWidth(500)
    group.heading=group.header.heading
    group.power=group.header.power
    group.power.onClick=function()
      if not H.valid() then return end
      local state=H.getState(food)
      if state~=nil then H.setEnabled(food,not state);H.refresh() end
    end
    group.header.conjure.onClick=function()
      if not H.valid() or not HelperFoodBridge or type(HelperFoodBridge.setConjureSelected)~="function" then return end
      HelperFoodBridge.setConjureSelected(not HelperFoodBridge.isConjureSelected())
      H.refresh()
    end
    local refreshFood=H.refresh
    H.refresh=function()
      refreshFood()
      if not H.valid() or not H.live(group) then return end
      local state=H.getState(food)
      group.power:setEnabled(state~=nil)
      group.power:setOn(state==true)
      group.power.caption:setText(state==nil and "--" or state and "ON" or "OFF")
      local canChoose=HelperFoodBridge and type(HelperFoodBridge.isConjureSelected)=="function"
      group.header.conjure:setEnabled(canChoose==true)
      group.header.conjure:setChecked(canChoose and HelperFoodBridge.isConjureSelected()==true or false)
    end
    local height=32
    for _,item in ipairs(food.panels) do
      if item.mounted and H.live(item.widget) then
        local w=item.widget
        local label=safe(function() return w:getText() end)
        local id=safe(function() return w:getId() end) or ""
        local nativeMacro=label=="Eat Food" or label=="Conjure Food" or tostring(id):match("^macro_")
        if nativeMacro then
          -- The header replaces hidden/duplicate native macro switches in Helper.
          w:hide();item.foodIntegrated=false;item.foodHidden=true
        else
          w:setParent(group,true);w:breakAnchors()
          w:setWidth(490);w:show()
          height=height+w:getHeight()+3
          item.nested=true;item.foodIntegrated=true
        end
      end
    end
    group:setHeight(height);group:hide()
    H.foodSection={widget=group,module=H.modules.conditions,style="HelperFoodSection",
      mounted=true,size={width=500,height=height}}
  end
end
-- Anti Push opens a scalar text editor; retain its owner across the native callback.
for _,item in ipairs(H.modules.antipush1.panels) do
  local button=H.live(item.widget) and item.widget:recursiveGetChildById("WithdrawButton")
  if button and type(button.onClick)=="function" then
    local click=button.onClick
    button.onClick=function(...)
      local previous=H.textOwner; H.textOwner=H.modules.antipush1
      local ok,result=pcall(click,...)
      H.textOwner=previous
      if not ok then error(result) end
      return result
    end
  end
end
-- Reuse the native CaveBot config, action list and editor callbacks.
for _,item in ipairs(H.modules.cavebot.panels) do
  if item.style=="HelperCaveBotPanel" then H.cavePanel=item.widget end
end
if H.live(H.cavePanel) then
  local m=H.modules.cavebot
  local links=create("HelperCaveLinks",window.viewport.host.controls)
  HelperTheme.decorate(links)
  H.caveLinks=links
  table.insert(m.panels,2,{widget=links,module=m,style="HelperCaveLinks",mounted=true,size={width=580,height=26}})
  for name,id in pairs({supplies="supplies",deposits="depositer_config",routeControls="cavebot_control_panel",settings="cave_target_settings"}) do
    local moduleId=id
    links[name].onClick=function() H.openModule(moduleId) end
  end
  -- Keep the native compatibility field; there is no collapse control in Helper.
  H.cavePanel.showEditor:setOn(true)
  H.cavePanel.showEditor:hide()
  H.cavePanel.showEditor.onClick=nil
end
-- Shared settings access; original route action widgets and callbacks stay untouched.
;(function()
  local entries={}
  for _,definition in ipairs({{"supplies","SuppliesWindow"},{"depositer_config","DepositerPanel"}}) do
    for _,item in ipairs(H.modules[definition[1]].views) do
      if item.style==definition[2] and item.mounted and H.live(item.widget) then
        entries[definition[1]]=item;break
      end
    end
  end
  if entries.supplies and entries.depositer_config then
    local panel=makeFloatingPanel("cavebot:suppliesDepot","Supplies y Depot")
    panel.supplyDepot=true;panel.owner=H.modules.supplies
    panel.items={entries.supplies,entries.depositer_config}
    for _,item in ipairs(panel.items) do
      putInPanel(item,panel)
      local entry=item
      local nativeRaise=entry.widget.raise
      -- Native openers raise their window. Inside a vertical layout that would
      -- move Supplies below Depot, so bring only the shared outer shell forward.
      entry.widget.raise=function(widget)
        if H.valid() and entry.floatingPanel==panel and H.live(panel.widget) then
          return panel.widget:raise()
        end
        return nativeRaise(widget)
      end
    end
    H.supplyDepotPanel=panel
    H.selectSupplyDepotPage=function(item)
      if not H.valid() or not H.live(panel.widget) then return end
      panel.positioning=true
      -- These are presentation heights; Depot's saved classic height is preserved.
      entries.supplies.widget:setHeight(282)
      entries.supplies.widget.conditionsFrame:setHeight(128)
      for _,id in ipairs({"SoftBoots","capValue","capSwitch","staminaValue","staminaSwitch","imbues"}) do
        entries.supplies.widget[id]:setHeight(18)
      end
      entries.depositer_config.widget:setHeight(226)
      showFloatingPanel(panel,"Supplies y Depot")
    end
    H.openSupplyDepotConfig=function(id)
      if H.valid() then return H.openFloatingModule(H.modules[id or "supplies"]) end
    end
    entries.supplies.nativeHide(entries.supplies.widget)
    entries.depositer_config.nativeHide(entries.depositer_config.widget)
  end
  H.routeActions={}
  local commands={
    {"Force Refill","Forzar refill",96,"Salir de la hunt en el siguiente supply check"},
    {"Back & Stop","Volver y parar",110,"Volver a ciudad y parar CaveBot al depositar"},
    {"To Trainers","Entrenadores",90,"Volver y seguir la label toTrainers al depositar"},
    {"Offline","Offline",68,"Volver y seguir la label toOfflineTraining al depositar"}
  }
  if H.caveLinks then
    H.caveLinks.supplies:show()
    H.caveLinks.supplies.onClick=function() H.openSupplyDepotConfig() end
    H.caveLinks.supplies:setTooltip("Supplies arriba y Depot debajo en una sola ventana")
    for _,id in ipairs({"deposits","settings","routeControls"}) do H.caveLinks[id]:hide() end
    local buttons={}
    for _,item in ipairs(H.modules.cavebot_control_panel.panels) do
      if H.live(item.widget) and H.live(item.widget.buttons) then
        for _,button in ipairs(item.widget.buttons:getChildren()) do buttons[button:getText()]=button end
      end
    end
    for _,command in ipairs(commands) do
      local button=buttons[command[1]]
      if H.live(button) then
        button:setParent(H.caveLinks,true);button:breakAnchors()
        button:setMarginLeft(0);button:setMarginRight(0);button:setMarginTop(0);button:setMarginBottom(0)
        button:setWidth(command[3]);button:setHeight(22);button:setText(command[2]);button:setTooltip(command[4])
        button:show();H.routeActions[#H.routeActions+1]=button
      end
    end
  end
  local cfg=CaveBot and CaveBot.Config and CaveBot.Config.window
  if not H.live(cfg) then
    for _,item in ipairs(H.modules.cavebot.views) do if item.style=="CaveBotConfigWindow" then cfg=item.widget;break end end
  end
  if not H.live(cfg) or not cfg.caveTargetTab then return end
  local shared=BotSettings and BotSettings.sections and BotSettings.sections.cave
  local originalParent=H.live(shared) and shared:getParent()
  local borrowed=false
  local function routePage()
    cfg.movement:show(); cfg.security:show(); cfg.caveTargetHost:hide()
    cfg.routeTab:setOn(true); cfg.caveTargetTab:setOn(false)
    text(cfg.description,"Movimiento y seguridad de la ruta seleccionada.")
    text(cfg.savedHint,"Los cambios se guardan automaticamente en la ruta seleccionada.")
  end
  local function restore()
    if borrowed and H.live(shared) and H.live(originalParent) then
      borrowed=false
      shared:setParent(originalParent,true); shared:breakAnchors()
      shared:applyStyle({["anchors.left"]="parent.left",["anchors.right"]="parent.right",
        ["anchors.top"]="sectionTabs.bottom",["anchors.bottom"]="separator.top",
        ["margin-left"]=0,["margin-right"]=0,["margin-top"]=10,["margin-bottom"]=8})
      shared:setVisible(originalParent.sectionTabs.cave:isOn())
    end
    if H.live(cfg) then routePage() end
  end
  H.caveConfig={window=cfg,section=shared,restore=restore}
  H.selectCaveConfigPage=function(page)
    if not H.valid() or not H.live(cfg) then return end
    if page~="target" or not H.live(shared) then restore(); return end
    borrowed=true
    shared:setParent(cfg.caveTargetHost,true); shared:breakAnchors()
    shared:applyStyle({["anchors.left"]="parent.left",["anchors.right"]="parent.right",
      ["anchors.top"]="parent.top",["anchors.bottom"]="parent.bottom",
      ["margin-left"]=0,["margin-right"]=0,["margin-top"]=0,["margin-bottom"]=0})
    cfg.movement:hide(); cfg.security:hide(); cfg.caveTargetHost:show(); shared:show()
    cfg.routeTab:setOn(false); cfg.caveTargetTab:setOn(true)
    text(cfg.description,"Opciones generales de CaveBot y TargetBot.")
    text(cfg.savedHint,"Los controles conservan sus valores y guardado habituales.")
  end
  cfg.routeTab.onClick=function() H.selectCaveConfigPage("route") end
  cfg.caveTargetTab.onClick=function() H.selectCaveConfigPage("target") end
  cfg.routeTab:setTooltip("Movimiento, esperas y seguridad de la ruta seleccionada")
  cfg.caveTargetTab:setTooltip("Panel original Cave y Target, con los mismos controles y valores")
  cfg.caveTargetTab:setEnabled(H.live(shared))
  local visibility=cfg.onVisibilityChange
  cfg.onVisibilityChange=function(widget,shown)
    if type(visibility)=="function" then visibility(widget,shown) end
    if not shown then restore() end
  end
  if H.live(shared) then
    local originalOpen,originalShow=BotSettings.open,BotSettings.showSection
    local caveTab=originalParent.sectionTabs.cave
    -- Cave and Target has its dedicated access in the CaveBot configuration.
    caveTab:hide()
    originalShow("basic")
    local open=function(...) restore(); return originalOpen(...) end
    local show=function(...) restore(); return originalShow(...) end
    BotSettings.open=open; BotSettings.showSection=show
    H.openCaveTargetConfig=function()
      if not H.valid() then return end
      if CaveBot.Config and CaveBot.Config.show then CaveBot.Config.show() end
      H.selectCaveConfigPage("target")
    end
    local unbind=H.unbind
    H.unbind=function()
      restore()
      if H.live(caveTab) then caveTab:show() end
      if BotSettings.open==open then BotSettings.open=originalOpen end
      if BotSettings.showSection==show then BotSettings.showSection=originalShow end
      if unbind then unbind() end
    end
  end
  routePage()
end)()

H.building=false; H.navigate("Inicio")
-- Inspectable runtime coverage: no personal configuration or credentials.
function H.audit()
  local result={schema=1,bot="Helper",version=SabuezoUpdaterBridge and SabuezoUpdaterBridge.getVersion() or "?",
    sections=H.sections,modules={},missing={},panels=0,forms=0}
  for _,m in ipairs(H.order) do
    local entry={id=m.id,name=m.name,section=m.section,available=m.available,panels={},forms={}}
    if m.hidden then entry.hidden=true end
    if m.aliasOf then entry.aliasOf=m.aliasOf end
    if m.groupId then entry.groupedInto=m.groupId end
    if m.id=="cave_target_settings" then entry.aliasOf="botsettings" end
    if m.id=="holdtarget" then entry.toggleOnly=true end
    if m.id=="exivatarget" or m.id=="exivalast" then entry.aliasOf="pvp_support" end
    for _,item in ipairs(m.panels) do
      if item.mounted and H.live(item.widget) then
        entry.panels[#entry.panels+1]=item.style or "HelperControls"
        result.panels=result.panels+1
      end
    end
    for _,item in ipairs(m.views) do
      if item.mounted and H.live(item.widget) then
        entry.forms[#entry.forms+1]=item.style
        result.forms=result.forms+1
      end
    end
    if not m.available then result.missing[#result.missing+1]=m.id end
    result.modules[#result.modules+1]=entry
  end
  if g_resources and json then pcall(function()
    local botName=modules.game_bot.contentsPanel.config:getCurrentOption().text
    g_resources.writeFileContents("/bot/"..botName.."/_helper_dev/runtime-inventory.json",json.encode(result,2))
  end) end
  return result
end
H.audit()
local function poll()
  if not H.valid() or not H.live(window) or not H.live(icon) then return end
  if H.hideNativePanel then H.hideNativePanel() end
  local size=root:getSize()
  if size.width~=H.lastWidth or size.height~=H.lastHeight then
    H.lastWidth,H.lastHeight=size.width,size.height; resize(); H.fitFloatingPanels()
    hostWidth(activeView and activeView.widget:getWidth() or 310)
  end
  H.refresh(); schedule(window:isVisible() and 250 or 1000,poll)
end
poll()
