-- One TargetBot view. Only the old engine's apply/save bridge changes active
-- rules; searching, selecting and editing operate exclusively on profile drafts.
TargetBot.Unified = {}
local U=TargetBot.Unified
if HelperAppearance and HelperAppearance.metadata then
  -- game_bot's dofile has no return value. The companion publishes on U.
  -- Cosmetic metadata must never prevent the targeting engine from loading.
  local ok=pcall(dofile,'/targetbot/unified_theme.lua')
  local styles=U.themeStyles
  U.themeStyles=nil
  if ok and type(styles)=='table' then
    for name,descriptor in pairs(styles) do HelperAppearance.metadata.styles[name]=descriptor end
  elseif type(warn)=='function' then
    warn('TargetBot: no se pudo cargar la apariencia del panel. Recarga el bot para reintentar.')
  end
end
function U.copy(value)
  if type(value)~='table' then return value end
  local result={};for k,v in pairs(value) do result[k]=U.copy(v) end;return result
end
local function equal(a,b)
  if type(a)~=type(b) then return false end
  if type(a)~='table' then return a==b end
  for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
  for k in pairs(b) do if a[k]==nil then return false end end
  return true
end
local function trim(value) return tostring(value or ''):gsub('^%s+',''):gsub('%s+$','') end
local function ruleTitle(rule)
  local name=trim(rule and rule.name)
  if name=='*' then return 'Todos los monstruos' end
  return name~='' and name or 'Nuevo monstruo'
end
local function compile(name)
  local result={}
  for part in name:gmatch('[^,]+') do result[#result+1]='^'..trim(part):lower():gsub('%*','.*'):gsub('%?','.?')..'$' end
  return table.concat(result,'|')
end
U.compile=compile
function U.parseIgnored(text)
  local names,seen={},{}
  for part in tostring(text or ''):gsub('[\r\n]+',','):gmatch('[^,]+') do
    local name=trim(part):gsub('%s+',' ');local key=name:lower()
    if name~='' and not seen[key] then seen[key]=true;names[#names+1]=name end
  end
  return names
end
function U.selectDefaultProfile()
  storage._configs=storage._configs or {}
  storage._configs.targetbot_configs=storage._configs.targetbot_configs or {enabled=false}
  local settings=storage._configs.targetbot_configs
  local profiles=Config.list('targetbot_configs')
  for _,name in ipairs(profiles) do
    if trim(name):lower()=='todo' then settings.selected=name;return name end
  end
  -- Preserve all existing profiles. If Todo is missing, seed it from the
  -- selected configuration; a completely empty catalog starts disabled.
  local source
  for _,name in ipairs(profiles) do if name==settings.selected then source=name end end
  source=source or profiles[1]
  local ok,data=true,{targeting={},looting={}}
  if source then ok,data=pcall(Config.load,'targetbot_configs',source) end
  if not ok or type(data)~='table' then return nil end
  local saved,result=pcall(Config.save,'targetbot_configs','Todo',U.copy(data),'json')
  if not saved or result==false or not Config.fileExists('targetbot_configs','Todo') then return nil end
  settings.selected='Todo'
  if not source then settings.enabled=false end
  return 'Todo'
end
-- Same native keys, ranges and defaults as Creature.edit. No new combat mode.
U.specs={
 {'priority','Prioridad','priority',0,20,1},
 {'danger','Peligro','priority',0,10,1},
 {'maxDistance','Alcance (SQM)','priority',1,10,10},
 {'keepDistance','Mantener distancia','movement',false},
 {'keepDistanceRange','Distancia (SQM)','movement',1,5,1,'keepDistance'},
 {'chase','Perseguir objetivo','movement',true},
 {'dynamicLure','Lure dinamico','pull',false},
 {'lureMin','Minimo','pull',0,29,1,'dynamicLure'},
 {'lureMax','Maximo','pull',1,30,3,'dynamicLure'},
 {'dynamicLureDelay','Pausa dinamica','pull',false},
 {'lureSpread','Distancia (SQM)','pull',2,8,4,'dynamicLureDelay'},
 {'delayFrom','Desde (monstruos)','pull',1,29,2,'dynamicLureDelay'},
 {'dontLoot','Recoger loot de esta criatura','combat',false,'inverse'},
 {'rpSafe','Seguridad PvP de flechas','combat',false},
 {'anchor','Anclaje','advancedMovement',false},
 {'anchorRange','Radio (SQM)','advancedMovement',1,10,3,'anchor'},
 {'rePosition','Reposicionar clasico','advancedMovement',false},
 {'rePositionAmount','Casillas minimas','advancedMovement',0,7,5,'rePosition'},
 {'avoidAttacks','Evitar waves enemigas','advancedMovement',false},
 {'lure','Lure clasico','advancedPull',false},
 {'lureCount','Cantidad','advancedPull',0,5,1,'lure'},
 {'lureCavebot','Lure con CaveBot','advancedPull',false},
 {'closeLure','Agrupar cercanos','advancedPull',false},
 {'closeLureAmount','Hasta (a 1 SQM)','advancedPull',0,8,3,'closeLure'},
 {'antitrapBugMap','BugMap sin salida','advancedCombat',false},
 {'antitrapBugMapDelay','Espera (ms)','advancedCombat',300,3000,600,'antitrapBugMap'},
}
local tips={
 priority='Prioridad frente a otros monstruos. 0 permite excluirlo de los objetivos de combate.',
 danger='Peligro asignado a esta criatura; se usa tambien para decidir si recoger loot.',
 maxDistance='Distancia maxima para considerar este objetivo.',
 keepDistance='Mantener la distancia indicada y buscar una salida antes de quedar rodeado.',
 keepDistanceRange='Distancia deseada respecto al objetivo.',
 chase='Acercarse al objetivo en el movimiento clasico. Keep Distance controla su propia distancia.',
 dynamicLure='Reunir monstruos entre los limites minimo y maximo.',
 lureMin='Cantidad minima para retomar el recorrido. Debe ser menor que el maximo.',
 lureMax='Cantidad maxima antes de detener el lure dinamico.',
 dynamicLureDelay='Esperar a los monstruos del lure cuando se quedan atras, sin frenar en cada paso.',
 lureSpread='Si el monstruo mas atrasado se aleja mas que esto, el personaje se detiene hasta que se acerque.',
 delayFrom='Numero de monstruos a partir del cual se espera a la manada.',
 dontLoot='Permitir o excluir el loot de esta criatura. Objetos y mochilas se editan en Loot general.',
 rpSafe='Conservar la seguridad PvP de Diamond/Burst Arrows.',
 anchor='Conservar el centro del combate, incluido el limite del antitrap.',
 anchorRange='Radio de combate y del anclaje.',
 rePosition='Reposicionamiento clasico para buscar mas espacio; no se combina con Keep Distance.',
 rePositionAmount='Umbral de casillas libres alrededor para reposicionar.',
 avoidAttacks='Buscar posiciones laterales para evitar ataques enemigos en linea.',
 lure='Reunir monstruos con el lure clasico.',lureCount='Cantidad del lure clasico.',
 lureCavebot='Permitir que CaveBot reuna los monstruos.',
 closeLure='Proteccion anti-rodeo: si hay mas monstruos pegados que el limite, da pasos para que no te rodeen mas.',
 closeLureAmount='Maximo de monstruos pegados a 1 SQM (diagonales incluidas); si hay mas, te reacomodas.',
 antitrapBugMap='Con Keep Distance, intentar BugMap solo cuando no queda una salida caminando.',
 antitrapBugMapDelay='Espera sin salida antes de BugMap. Los intentos conservan el limite del motor.',
}
local ammoChoices={
 {text='Sin prioridad',diamond=false,burst=false},
 {text='Diamond Arrows',diamond=true,burst=false},
 {text='Burst Arrows',diamond=false,burst=true},
 {text='Diamond + Burst',diamond=true,burst=true},
}
function U.create(ui,ctx)
  local self={states={},controls={}}
  local emptyProfile={}
  local state,profile,loading,rows=nil,nil,false,{}
  local renderList,renderIgnored,loadForm,refresh,updateFold
  local lootOpen,advancedOpen,creating=false,false,false
  local page='objectives'
  local creaturePage='monsters'
  local studio=TargetBot.Looting.studio
  local portraits=TargetBot.Portraits
  local portraitRevision=portraits and portraits.revision or 0
  local cards={movement=ui.details.movement,pull=ui.details.pull,combat=ui.details.combat}
  local ignored={names={},saved={},source=nil,dirty=false,selected=nil}
  local function ignoreSource() return tostring(storage.extras and storage.extras.ignoreCreatures or '') end
  local function syncIgnored(force)
    local source=ignoreSource()
    if force or not ignored.dirty and ignored.source~=source then
      ignored.names=U.parseIgnored(source);ignored.saved=U.copy(ignored.names)
      ignored.source=source;ignored.dirty=false;ignored.selected=nil
      return true
    end
    return false
  end
  syncIgnored(true)
  local groups={priority=ui.details.priority.fields,movement=cards.movement.fields,
    pull=cards.pull.fields,combat=cards.combat.fields,
    advancedMovement=ui.advancedHost.movement.fields,advancedPull=ui.advancedHost.pull.fields,
    advancedCombat=ui.advancedHost.combat.fields}
  groups.advancedMovement=groups.movement
  groups.advancedPull=groups.pull
  groups.advancedCombat=groups.combat
  local function message(text,bad)
    ui.footer.message:setText(text)
    ui.footer.message:setColor(bad and '#f39b8f' or (state and state.dirty or ignored.dirty) and '#ffd05d' or '#c0cdd6')
  end
  local function selectedRule() return state and state.selected and state.rules[state.selected] end
  local function rememberNames()
    state.originalNames={}
    for _,rule in ipairs(state.rules) do state.originalNames[rule]=rule.name end
  end
  local function changed(key,value,invalid)
    if loading or not selectedRule() then return end
    if not invalid then selectedRule()[key]=value end
    state.raw[state.selected]=state.raw[state.selected] or {}
    state.raw[state.selected][key]=invalid
    refresh();renderList()
  end
  for _,spec in ipairs(U.specs) do
    local id,title,group=spec[1],spec[2],spec[3]
    local number=type(spec[4])=='number'
    local row=UI.createWidget(number and 'TargetStudioAmount' or 'TargetStudioOption',groups[group])
    row:setWidth(group=='priority'and 192 or 186)
    row:setId(id);row.caption:setText(title);row:setTooltip(tips[id])
    local control={row=row,spec=spec,number=number}
    self.controls[id]=control
    if number then
      row.controls.input:setTooltip(tips[id]..' '..spec[4]..' a '..spec[5]..'. Escribe el valor o usa - / +.')
      row.controls.input.onTextChange=function(_,raw)
        if loading then return end
        local value=tonumber(raw)
        local valid=value and value==value and value==math.floor(value) and value>=spec[4] and value<=spec[5]
        row.controls.input:setColor(valid and '#edf3f5' or '#f39b8f')
        changed(id,value,not valid and tostring(raw) or nil)
      end
      local function shift(delta)
        local value=tonumber(row.controls.input:getText()) or spec[6]
        local step=spec[5]-spec[4]>100 and 10 or 1
        row.controls.input:setText(tostring(math.max(spec[4],math.min(spec[5],value+delta*step))))
      end
      row.controls.minus.onClick=function()shift(-1)end
      row.controls.plus.onClick=function()shift(1)end
    else
      row.onClick=function()
        if loading or not selectedRule() then return end
        row:setOn(not row:isOn())
        row.track:setText(row:isOn() and 'ON' or 'OFF')
        row.track:setOn(row:isOn())
        changed(id,spec[5]=='inverse' and not row:isOn() or spec[5]~='inverse' and row:isOn())
      end
    end
  end
  local ammo=UI.createWidget('TargetStudioAmmo',groups.combat)
  ammo:setHeight(44);ammo:setWidth(186);ammo.caption:setWidth(180)
  ammo.list:setMarginLeft(0);ammo.list:setMarginTop(20)
  ammo.caption:setText('Municion preferida')
  for _,choice in ipairs(ammoChoices) do ammo.list:addOption(choice.text) end
  ammo.list.onOptionChange=function()
    if loading or not selectedRule() then return end
    for _,choice in ipairs(ammoChoices) do if choice.text==ammo.list:getCurrentOption().text then
      selectedRule().diamondArrows=choice.diamond;selectedRule().burstArrows=choice.burst
    end end
    refresh()
  end
  self.ammo=ammo
  self.controls.dontLoot.row.caption:setText('Loot de criatura')
  self.controls.rpSafe.row.caption:setText('Seguridad de flechas')
  self.controls.keepDistance.row.caption:setText('Distancia + antitrap')
  self.controls.avoidAttacks.row.caption:setText('Evitar waves')
  self.controls.delayFrom.row.caption:setText('Desde (monst.)')
  -- Share one row for the two lure limits instead of growing the window.
  local pair=setupUI([[
Panel
  width: 186
  height: 24
  layout:
    type: horizontalBox
    spacing: 6
]],groups.pull)
  for _,entry in ipairs({{'lureMin','Min.'},{'lureMax','Max.'}})do
    local row=self.controls[entry[1]].row
    row:setParent(pair);row:setWidth(90);row:setMarginTop(0);row.caption:setText(entry[2])
    row.controls:setWidth(58)
    row.controls.minus:setWidth(16);row.controls.plus:setWidth(16);row.controls.plus:setMarginLeft(42)
    row.controls.input:setMarginLeft(17);row.controls.input:setWidth(24)
  end
  groups.pull:moveChildToIndex(pair,2)
  ui.details.name.onTextChange=function(_,text) changed('name',text) end
  local function validate(index)
    local rule=state.rules[index]
    if trim(rule.name)=='' then return 'Escribe el nombre del monstruo.', 'name' end
    for key,raw in pairs(state.raw[index] or {}) do
      if raw~=nil then return 'Corrige el numero marcado en rojo: '..(self.controls[key] and self.controls[key].spec[2] or key)..'.',key end
    end
    if rule.dynamicLure and (tonumber(rule.lureMin) or 1)>=(tonumber(rule.lureMax) or 3) then
      return 'Lure dinamico: el minimo debe ser menor que el maximo.','lureMin'
    end
  end
  local function isDirty()
    if not state then return false end
    if not equal(state.rules,state.saved) then return true end
    for _,invalid in pairs(state.raw) do for _,raw in pairs(invalid) do if raw~=nil then return true end end end
    return false
  end
  refresh=function()
    if not state then return end
    state.dirty=isDirty()
    local rule=selectedRule()
    ui.details:setEnabled(rule~=nil)
    for _,card in pairs(cards) do card:setEnabled(rule~=nil) end
    ui.advancedHost:setEnabled(rule~=nil)
    ui.monsters.remove:setEnabled(rule~=nil)
    ui.monsters.add:setEnabled(ctx.canSave())
    local dirty=page=='looting'and studio and studio.dirty or page~='looting'and (state.dirty or ignored.dirty)
    ui.footer.save:setEnabled(page=='looting'and dirty or page~='looting'and (ignored.dirty or ctx.canSave()and state.dirty))
    ui.footer.discard:setEnabled(dirty==true)
    for _,control in pairs(self.controls) do
      local owner=control.number and control.spec[7]
      local invalid=state.selected and state.raw[state.selected] and state.raw[state.selected][control.spec[1]]~=nil
      local enabled=not owner or rule and rule[owner]==true or invalid
      control.row:setEnabled(rule~=nil and enabled)
      control.row:setOpacity(enabled and 1 or 0.8)
      control.row:show()
    end
    pair:show()
    if page=='looting'then
      message(dirty and'Loot: cambios sin guardar'or(studio and studio.message=='Loot global guardado.'and studio.message or'Sin cambios de loot pendientes'))
      if dirty then ui.footer.message:setColor('#ffd05d')end
    elseif not rule then
      message(ignored.dirty and 'Ignoradas: cambios sin guardar' or ctx.canSave() and 'Agrega un monstruo para configurar sus ajustes.' or 'Crea o selecciona un perfil de TargetBot.')
    else
      local errorText=validate(state.selected)
      message(errorText or ((state.dirty or ignored.dirty) and 'Cambios sin guardar' or 'Sin cambios pendientes'),errorText~=nil)
    end
    ui.details.title:setText(rule and ruleTitle(rule) or 'Selecciona un monstruo')
    if updateFold then updateFold() end
  end
  loadForm=function(index)
    state.selected=index;loading=true
    local rule=selectedRule() or {}
    ui.details.name:setText(rule.name or '')
    for id,control in pairs(self.controls) do
      local spec=control.spec
      if control.number then
        local value=rule[id];if value==nil then value=spec[6] end
        local raw=state.raw[index] and state.raw[index][id]
        control.row.controls.input:setText(raw or tostring(value))
        control.row.controls.input:setColor(raw and '#f39b8f' or '#edf3f5')
      else
        local value=rule[id];if value==nil then value=spec[4] end
        local on=spec[5]=='inverse' and not value or spec[5]~='inverse' and value==true
        control.row:setOn(on);control.row.track:setText(on and 'ON' or 'OFF')
        control.row.track:setOn(on)
      end
    end
    for _,choice in ipairs(ammoChoices) do
      if choice.diamond==(rule.diamondArrows==true) and choice.burst==(rule.burstArrows==true) then ammo.list:setCurrentOption(choice.text) end
    end
    loading=false;refresh();renderList()
  end
  local function paintPortrait(widget,fallback,rule)
    local outfit=rule and portraits and portraits.resolve(rule.name)
    widget:setVisible(outfit~=nil);fallback:setVisible(rule~=nil and outfit==nil)
    local wildcard=rule and trim(rule.name)=='*'
    -- A battle-list texture is not a creature sprite. Unknown names use an
    -- initial until their real appearance is observed, never a fake looktype.
    fallback:setImageSource('')
    fallback:setText(wildcard and '*' or trim(rule and rule.name):sub(1,1):upper())
    if outfit then widget:setOutfit(outfit) end
  end
  renderList=function()
    if not state then return end
    ui.monsters.list:destroyChildren();rows={}
    local search=trim(ui.monsters.search:getText()):lower()
    for index,rule in ipairs(state.rules) do
      if search=='' or tostring(rule.name or ''):lower():find(search,1,true) or ruleTitle(rule):lower():find(search,1,true) then
        local row=UI.createWidget('TargetStudioEntry',ui.monsters.list)
        row.title:setText(ruleTitle(rule))
        row.priority:setText('Prioridad: '..tostring(rule.priority or 1))
        row:setOn(index==state.selected)
        row:setTooltip(ruleTitle(rule)..'\nNombre: '..(rule.name or '')..'\nPrioridad: '..tostring(rule.priority or 1)..' | Peligro: '..tostring(rule.danger or 1))
        row.onClick=function()loadForm(index)end
        row.onDoubleClick=row.onClick
        paintPortrait(row.portrait,row.fallback,rule)
        rows[#rows+1]={widget=row,index=index}
      end
    end
    ui.monsters.heading:setText('Monstruos ('..#rows..(#rows~=#state.rules and '/'..#state.rules or '')..')')
    ui.body.creatureTabs.monsters:setText('Monstruos ('..#state.rules..')')
    ui.monsters.empty:setVisible(#rows==0)
    ui.monsters.empty:setText(#state.rules>0 and 'Sin coincidencias.\nPrueba otro nombre.' or 'No hay monstruos.\nUsa Agregar para crear una regla.')
    paintPortrait(ui.details.portrait,ui.details.fallback,selectedRule())
  end
  renderIgnored=function()
    ui.ignored.list:destroyChildren()
    local search=trim(ui.ignored.search:getText()):lower()
    local count=0
    for index,name in ipairs(ignored.names) do
      if search=='' or name:lower():find(search,1,true) then
        local row=UI.createWidget('TargetStudioEntry',ui.ignored.list)
        row.title:setText(name);row.priority:setText('Excluida de TargetBot')
        row:setOn(index==ignored.selected)
        row:setTooltip(name..'\nExcluida de TargetBot y del looting en todos los perfiles de este personaje.')
        row.onClick=function()ignored.selected=index;renderIgnored()end
        paintPortrait(row.portrait,row.fallback,{name=name})
        count=count+1
      end
    end
    ui.ignored.heading:setText('Criaturas ignoradas ('..#ignored.names..')')
    ui.body.creatureTabs.ignored:setText('Ignoradas ('..#ignored.names..')')
    ui.ignored.empty:setVisible(count==0)
    ui.ignored.empty:setText(#ignored.names>0 and 'Sin coincidencias.' or 'Ninguna criatura ignorada.\nUsa Ignorar para agregar nombres.')
    ui.ignored.remove:setEnabled(ignored.selected~=nil)
  end
  function self.addIgnoredNames(text)
    local seen={};for _,name in ipairs(ignored.names) do seen[name:lower()]=true end
    local added=0
    for _,name in ipairs(U.parseIgnored(text)) do
      if not seen[name:lower()] then
        ignored.names[#ignored.names+1]=name;seen[name:lower()]=true;added=added+1
      end
    end
    ignored.dirty=not equal(ignored.names,ignored.saved)
    if added>0 then ignored.selected=#ignored.names;ui.ignored.search:setText('') end
    renderIgnored();refresh()
    if added==0 then message('El nombre esta vacio o ya esta en Ignoradas.') end
    return added
  end
  function self.getIgnoredDraft() return ignored end
  ui.ignored.search.onTextChange=function()renderIgnored()end
  ui.ignored.add.onClick=function()
    local rule=selectedRule();local name=rule and trim(rule.name) or ''
    if name:find('[*?]') then name='' end
    UI.EditorWindow(name,{title='Ignorar criaturas',
      description='Nombres exactos, separados por comas. Se excluyen de TargetBot en todos los perfiles. Aplica con Guardar cambios.',
      multiline=true},function(text)self.addIgnoredNames(text)end)
  end
  ui.ignored.remove.onClick=function()
    if not ignored.selected then return end
    table.remove(ignored.names,ignored.selected)
    ignored.selected=nil;ignored.dirty=not equal(ignored.names,ignored.saved)
    renderIgnored();refresh()
  end
  ui.monsters.search.onTextChange=function()renderList()end
  ui.monsters.add.onClick=function()
    if not ctx.canSave() then return end
    local rule={name='',regex=''}
    for _,spec in ipairs(U.specs) do rule[spec[1]]=type(spec[4])=='number' and spec[6] or spec[4] end
    state.rules[#state.rules+1]=rule
    loading=true;ui.monsters.search:setText('');loading=false
    loadForm(#state.rules);ui.details.name:focus()
  end
  ui.monsters.remove.onClick=function()
    if not selectedRule() then return end
    local at=state.selected
    for index=at,#state.rules-1 do state.raw[index]=state.raw[index+1] end
    state.raw[#state.rules]=nil
    table.remove(state.rules,at)
    loadForm(#state.rules>0 and math.min(at,#state.rules) or nil)
  end
  ui.footer.discard.onClick=function()
    if page=='looting'and studio then studio.discard();refresh();return end
    syncIgnored(true);renderIgnored()
    if not state then return end
    state.rules=U.copy(state.saved);state.raw={};state.dirty=false
    rememberNames()
    loadForm(#state.rules>0 and 1 or nil)
  end
  function self.save()
    if page=='looting'and studio then local ok=studio.save();refresh();return ok end
    if ignored.dirty and not equal(U.parseIgnored(ignoreSource()),ignored.saved) then
      message('Ignoradas cambio fuera de este panel. Descarta para cargar la lista actual.',true);return false
    end
    if state and state.dirty and (not ctx.canSave() or ctx.getProfile()~=profile) then message('El perfil activo cambio; selecciona de nuevo el perfil.',true);return false end
    for index in ipairs(state and state.dirty and state.rules or {}) do
      local text,key=validate(index)
      if text then
        loading=true;ui.monsters.search:setText('');loading=false
        loadForm(index);message(text,true)
        if key=='name' then ui.details.name:focus()
        elseif self.controls[key] then self.controls[key].row.controls.input:focus() end
        return false
      end
    end
    local rules=U.copy(state and state.rules or {})
    for index,rule in ipairs(rules) do
      if state.originalNames[state.rules[index]]~=rule.name or not rule.regex then rule.regex=compile(rule.name) end
    end
    if state and state.dirty then
      local ok,text=ctx.apply(rules)
      if not ok then message(text or 'No se pudieron guardar los cambios.',true);return false end
      state.rules=U.copy(rules);state.saved=U.copy(rules);state.raw={};state.dirty=false
      rememberNames()
    end
    if ignored.dirty then TargetBot.Looting.setIgnoredCreatures(ignored.names);syncIgnored(true);renderIgnored() end
    if state then loadForm(#rules>0 and (state.selected and math.min(state.selected,#rules) or 1) or nil) else refresh() end
    message('Cambios guardados.')
    return true
  end
  ui.footer.save.onClick=self.save
  ui.footer.close.onClick=ctx.close
  function self.load(name,data)
    profile=name
    syncIgnored();renderIgnored()
    if ctx.getProfiles then
      local exists={};for _,value in ipairs(ctx.getProfiles()) do exists[value]=true end
      for value in pairs(self.states) do if value~=emptyProfile and not exists[value] then self.states[value]=nil end end
    end
    local key=name or emptyProfile
    local previous=self.states[key]
    -- OFF/ON reloads native configuration too: retain only unsaved UI drafts.
    if not previous or not previous.dirty then
      local rules=data and ctx.getRules() or {}
      previous={rules=U.copy(rules),saved=U.copy(rules),raw={},selected=#rules>0 and 1 or nil,dirty=false}
      self.states[key]=previous
    end
    state=previous
    if not state.originalNames then rememberNames() end
    loadForm(#state.rules>0 and (state.selected and math.min(state.selected,#state.rules) or 1) or nil)
  end
  function self.getDraft() return state end
  updateFold=function()
    local extra=creating and 30 or 0
    ui.newProfile:setVisible(creating)
    ui.live:setMarginTop(34+extra);ui.tabs:setMarginTop(56+extra)
    ui.body:setMarginTop(84+extra);ui.body:setHeight(410);ui.body:setVisible(page=='objectives')
    for _,panel in ipairs({ui.monsters,ui.ignored}) do
      panel:setHeight(410);panel.list:setHeight(286);panel.scroll:setHeight(286)
      panel.add:setMarginTop(346);panel.remove:setMarginTop(346)
      panel.heading:hide();panel.help:hide()
    end
    ui.monsters:setVisible(creaturePage=='monsters')
    ui.ignored:setVisible(creaturePage=='ignored')
    ui.body.creatureTabs.monsters:setOn(creaturePage=='monsters')
    ui.body.creatureTabs.ignored:setOn(creaturePage=='ignored')
    ui.details:setHeight(410)
    for i,name in ipairs({'movement','pull','combat'})do
      local card=cards[name];card:setMarginLeft((i-1)*204);card:setMarginTop(112)
      card:setWidth(200);card:setHeight(276)
    end
    ui.details.movementNote:hide();ui.details.hint:setMarginTop(392)
    ui.lootHost:setMarginTop(84+extra);ui.lootHost:setHeight(398);ui.lootHost:setVisible(page=='looting')
    ui.lootToggle:hide();ui.advancedToggle:hide();ui.advancedHost:hide()
    ui.tabs.objectives:setOn(page=='objectives');ui.tabs.looting:setOn(page=='looting')
    ui.tabs.scope:setText(page=='looting'and'Loot global compartido entre perfiles'or'Monstruos del perfil | Ignoradas globales')
    ui.footer.save:setTooltip(page=='looting'and'Guardar el filtro y los destinos globales de loot.'or'Guardar las reglas del perfil y las criaturas ignoradas globales.')
    ui.footer.discard:setTooltip(page=='looting'and'Descartar el borrador de loot.'or'Descartar el borrador de objetivos.')
    ui.footer:setMarginTop(502+extra);ui:setHeight(538+extra)
    if Helper and Helper.fitFloatingPanels then Helper.fitFloatingPanels() end
  end
  function self.setPage(value)
    page=value=='looting'and'looting'or'objectives'
    if page=='looting'and studio then studio.show()end
    if page=='objectives' then syncIgnored();renderIgnored() end
    updateFold();refresh()
  end
  function self.getPage()return page end
  function self.showLooting()
    if Helper and Helper.openCaveTargetConfig then Helper.openCaveTargetConfig('targetbot') end
    if Helper and Helper.openModule then Helper.openModule('targetbot') end
    self.setPage('looting')
  end
  function self.setCreaturePage(value)
    creaturePage=value=='ignored'and'ignored'or'monsters'
    if creaturePage=='ignored' then syncIgnored();renderIgnored() end
    updateFold()
  end
  function self.getCreaturePage()return creaturePage end
  function self.showIgnored()
    self.setPage('objectives');self.setCreaturePage('ignored');ui.ignored.search:focus()
  end
  ui.body.creatureTabs.monsters.onClick=function()self.setCreaturePage('monsters')end
  ui.body.creatureTabs.ignored.onClick=function()self.setCreaturePage('ignored')end
  ui.tabs.objectives.onClick=function()self.setPage('objectives')end
  ui.tabs.looting.onClick=function()self.setPage('looting')end
  ui.lootToggle.onClick=ui.tabs.looting.onClick
  ui.advancedToggle.onClick=ui.tabs.objectives.onClick
  if studio then studio.onChange=function()if refresh then refresh()end end end
  ui.profile.add.onClick=function()creating=not creating;updateFold();if creating then ui.newProfile.name:focus()end end
  ui.newProfile.cancel.onClick=function()creating=false;updateFold()end
  ui.newProfile.create.onClick=function()
    local name=trim(ui.newProfile.name:getText()):gsub('%s+','_')
    local stem=name:match('^([^%.]+)') or name
    if name=='' or #name>=30 or name:find('[/\\:*?"<>|%c]') or name:sub(-1)=='.' or stem:upper():match('^CON$') or stem:upper():match('^PRN$') or stem:upper():match('^AUX$') or stem:upper():match('^NUL$') or stem:upper():match('^COM%d$') or stem:upper():match('^LPT%d$') then message('Nombre de perfil no valido.',true);return end
    local callOk,ok,text=pcall(ctx.createProfile,name)
    if not callOk or not ok then message(callOk and (text or 'No se pudo crear el perfil.') or 'No se pudo crear el perfil: '..tostring(ok),true);return end
    creating=false;updateFold()
  end
  macro(500,function()
    if not ui:isVisible() then return end
    local active=AttackBot and AttackBot.isOn and AttackBot.isOn()
    local cave=CaveBot and CaveBot.isOn and CaveBot.isOn()
    local explorer=CaveBot and CaveBot.AutoExplorer
    local hunting=explorer and explorer.isOn and explorer.isOn()
    ui.details.movementNote:setText(active and (hunting and 'Auto Explorer: alineacion dentro del radio de caza.' or cave and 'CaveBot ON: permite alineacion ofensiva.' or 'CaveBot OFF: solo girar hacia el objetivo.') or 'Movimiento segun estos ajustes de TargetBot.')
    local ignoredChanged=syncIgnored()
    local changedOutfits=portraits and portraitRevision~=portraits.revision
    if changedOutfits then portraitRevision=portraits.revision;renderList() end
    if ignoredChanged or changedOutfits then renderIgnored();refresh() end
  end)
  updateFold()
  return self
end
