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
-- Same native keys, ranges and defaults as Creature.edit. No new combat mode.
U.specs={
 {'priority','Prioridad','priority',0,20,1},
 {'danger','Peligro','priority',0,10,1},
 {'maxDistance','Alcance (SQM)','priority',1,10,10},
 {'keepDistance','Mantener distancia','movement',false},
 {'keepDistanceRange','Distancia (SQM)','movement',1,5,1,'keepDistance'},
 {'chase','Perseguir objetivo','movement',true},
 {'faceMonster','Mirar hacia el objetivo','movement',false},
 {'dynamicLure','Lure dinamico','pull',false},
 {'lureMin','Minimo','pull',0,29,1,'dynamicLure'},
 {'lureMax','Maximo','pull',1,30,3,'dynamicLure'},
 {'dynamicLureDelay','Pausa dinamica','pull',false},
 {'lureDelay','Pausa (ms)','pull',100,1000,250,'dynamicLureDelay'},
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
 faceMonster='Orientarse hacia el enemigo. La alineacion ofensiva requiere CaveBot ON.',
 dynamicLure='Reunir monstruos entre los limites minimo y maximo.',
 lureMin='Cantidad minima para retomar el recorrido. Debe ser menor que el maximo.',
 lureMax='Cantidad maxima antes de detener el lure dinamico.',
 dynamicLureDelay='Aplicar una pausa al movimiento del lure dinamico.',
 lureDelay='Pausa entre pasos del lure dinamico, en milisegundos.',
 delayFrom='Numero de monstruos a partir del cual se aplica la pausa.',
 dontLoot='Permitir o excluir el loot de esta criatura. Objetos y mochilas se editan en Loot general.',
 rpSafe='Conservar la seguridad PvP de Diamond/Burst Arrows.',
 anchor='Conservar el centro del combate, incluido el limite del antitrap.',
 anchorRange='Radio de combate y del anclaje.',
 rePosition='Reposicionamiento clasico para buscar mas espacio; no se combina con Keep Distance.',
 rePositionAmount='Umbral de casillas libres alrededor para reposicionar.',
 avoidAttacks='Buscar posiciones laterales para evitar ataques enemigos en linea.',
 lure='Reunir monstruos con el lure clasico.',lureCount='Cantidad del lure clasico.',
 lureCavebot='Permitir que CaveBot reuna los monstruos.',
 closeLure='Dar paso a CaveBot al alcanzar el limite de monstruos cercanos.',
 closeLureAmount='Limite de monstruos a 1 SQM para continuar CaveBot.',
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
  local self={states={},controls={},outfits={}}
  local emptyProfile={}
  local state,profile,loading,rows=nil,nil,false,{}
  local renderList,loadForm,refresh,updateFold
  local lootOpen,advancedOpen,creating=false,false,false
  local groups={priority=ui.details.priority.fields,movement=ui.details.movement.fields,
    pull=ui.details.pull.fields,combat=ui.details.combat.fields,
    advancedMovement=ui.advancedHost.movement.fields,advancedPull=ui.advancedHost.pull.fields,
    advancedCombat=ui.advancedHost.combat.fields}
  local function message(text,bad)
    ui.footer.message:setText(text)
    ui.footer.message:setColor(bad and '#f39b8f' or state and state.dirty and '#ffd05d' or '#c0cdd6')
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
    ui.advancedHost:setEnabled(rule~=nil)
    ui.monsters.remove:setEnabled(rule~=nil)
    ui.monsters.add:setEnabled(ctx.canSave())
    ui.footer.save:setEnabled(ctx.canSave() and state.dirty)
    ui.footer.discard:setEnabled(state.dirty)
    for _,control in pairs(self.controls) do
      local owner=control.number and control.spec[7]
      local enabled=not owner or rule and rule[owner]==true
      control.row:setEnabled(rule~=nil and enabled)
      control.row:setOpacity(enabled and 1 or 0.8)
    end
    if not rule then
      message(ctx.canSave() and 'Agrega un monstruo para configurar sus ajustes.' or 'Crea o selecciona un perfil de TargetBot.')
    else
      local errorText=validate(state.selected)
      message(errorText or (state.dirty and 'Cambios sin guardar' or 'Sin cambios pendientes'),errorText~=nil)
    end
    ui.details.title:setText(rule and ruleTitle(rule) or 'Selecciona un monstruo')
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
    local outfit=rule and self.outfits[trim(rule.name):lower()]
    widget:setVisible(outfit~=nil);fallback:setVisible(rule~=nil and outfit==nil)
    fallback:setText(rule and trim(rule.name)=='*' and '*' or '?')
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
    ui.monsters.empty:setVisible(#rows==0)
    ui.monsters.empty:setText(#state.rules>0 and 'Sin coincidencias.\nPrueba otro nombre.' or 'No hay monstruos.\nUsa Agregar para crear una regla.')
    paintPortrait(ui.details.portrait,ui.details.fallback,selectedRule())
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
    if not state then return end
    state.rules=U.copy(state.saved);state.raw={};state.dirty=false
    rememberNames()
    loadForm(#state.rules>0 and 1 or nil)
  end
  function self.save()
    if not state or not ctx.canSave() or ctx.getProfile()~=profile then message('El perfil activo cambio; selecciona de nuevo el perfil.',true);return false end
    for index in ipairs(state.rules) do
      local text,key=validate(index)
      if text then
        loading=true;ui.monsters.search:setText('');loading=false
        loadForm(index);message(text,true)
        if key=='name' then ui.details.name:focus()
        elseif self.controls[key] then self.controls[key].row.controls.input:focus() end
        return false
      end
    end
    local rules=U.copy(state.rules)
    for index,rule in ipairs(rules) do
      if state.originalNames[state.rules[index]]~=rule.name or not rule.regex then rule.regex=compile(rule.name) end
    end
    local ok,text=ctx.apply(rules)
    if not ok then message(text or 'No se pudieron guardar los cambios.',true);return false end
    state.rules=U.copy(rules);state.saved=U.copy(rules);state.raw={};state.dirty=false
    rememberNames()
    loadForm(#rules>0 and (state.selected and math.min(state.selected,#rules) or 1) or nil)
    message('Cambios guardados en '..tostring(profile)..'.')
    return true
  end
  ui.footer.save.onClick=self.save
  ui.footer.close.onClick=ctx.close
  function self.load(name,data)
    profile=name
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
    ui.live:setMarginTop(34+extra);ui.body:setMarginTop(60+extra)
    ui.lootToggle:setMarginTop(498+extra);ui.lootHost:setMarginTop(524+extra)
    local loot=lootOpen and 312 or 0
    ui.lootHost:setVisible(lootOpen)
    ui.advancedToggle:setMarginTop(524+extra+loot)
    ui.advancedHost:setMarginTop(550+extra+loot);ui.advancedHost:setVisible(advancedOpen)
    ui.footer:setMarginTop(556+extra+loot+(advancedOpen and 196 or 0))
    ui:setHeight(592+extra+loot+(advancedOpen and 196 or 0))
    ui.lootToggle:setText((lootOpen and '- ' or '+ ')..'Loot general: objetos, mochilas e ignorados')
    ui.advancedToggle:setText((advancedOpen and '- ' or '+ ')..'Opciones avanzadas de esta criatura: anclaje, waves y BugMap')
    if Helper and Helper.fitFloatingPanels then Helper.fitFloatingPanels() end
  end
  ui.lootToggle.onClick=function()lootOpen=not lootOpen;updateFold()end
  ui.advancedToggle.onClick=function()advancedOpen=not advancedOpen;updateFold()end
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
    ui.details.movementNote:setText(active and (cave and 'CaveBot ON: permite alineacion ofensiva.' or 'CaveBot OFF: solo girar hacia el objetivo.') or 'Movimiento segun estos ajustes de TargetBot.')
    local changedOutfits=false
    if type(getSpectators)=='function' then
      for _,actor in ipairs(getSpectators()) do
        if actor:isMonster() then
          local key=actor:getName():lower();local outfit=actor:getOutfit()
          if outfit and not equal(self.outfits[key],outfit) then self.outfits[key]=U.copy(outfit);changedOutfits=true end
        end
      end
    end
    if changedOutfits then renderList() end
  end)
  updateFold()
  return self
end
