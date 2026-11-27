-- Three-column editor. Basic native widgets and event-driven drafts only:
-- no SpinBox, timers, movement changes or config writes before Save.
TargetBot.Creature.edit = function(config, callback)
  config = config or {}
  local editor = UI.createWindow('TargetBotCreatureEditorWindow')
  local fields, values, numbers = {}, {}, {}
  local loading, initial = true, {}
  local movement, pull, combat = editor.content.movement.fields, editor.content.pull.fields, editor.content.combat.fields
  local updatePreview, summary
  local assetRoot = (type(configDir)=='string' and configDir or '/bot/Sabuezo2')..'/targetbot/editor_assets/'
  local assets = {}
  local function image(widget, name)
    local source=assetRoot..name..'.png'
    if assets[source]==nil then
      local ok,exists=true,true
      if g_resources and type(g_resources.fileExists)=='function' then ok,exists=pcall(g_resources.fileExists,source) end
      assets[source]=ok and exists==true
    end
    widget:setImageSource(assets[source] and source or '')
    return assets[source]
  end
  for _, spec in ipairs({{'movement','Movimiento'},{'pull','Pull / Lure'},{'combat','Combate y loot'}}) do
    local card=editor.content[spec[1]]
    card.title:setText(spec[2]);image(card.icon,spec[1]=='pull' and 'lure' or spec[1])
  end
  editor.name:setText(config.name or '')
  local function gap(parent) return UI.createWidget('TargetBotCreatureEditorGap',parent) end
  local function label(parent, style, text, id)
    local widget=UI.createWidget(style,parent)
    if id then widget:setId(id) end
    widget:setText(text);return widget
  end
  local function addNumber(parent, id, title, minimum, maximum, defaultValue, tooltip, unit, owner)
    local row=UI.createWidget('TargetBotCreatureEditorAmount',parent)
    row:setId(id);row:setTooltip(tooltip)
    row.caption:setText(title..(unit and (' ('..unit..')') or ''))
    if owner then row:setMarginLeft(10);row:setMarginTop(2) end
    local state={row=row,valid=true,writing=false,owner=owner,min=minimum,max=maximum,
      step=maximum-minimum>100 and 10 or 1}
    function state:set(value)
      self.value=math.max(minimum,math.min(maximum,math.floor(tonumber(value) or defaultValue)))
      self.valid,self.writing=true,true
      row.controls.input:setText(tostring(self.value))
      row.controls.input:setColor('#edf3f5')
      self.writing=false
    end
    state:set(config[id]==nil and defaultValue or config[id])
    row.controls.input:setTooltip(tooltip..' Rango: '..minimum..' a '..maximum..'. Puedes escribir el numero.')
    row.controls.input.onTextChange=function(_,raw)
      if state.writing then return end
      local number=tonumber(raw)
      state.valid=number~=nil and number==number and number==math.floor(number) and number>=minimum and number<=maximum
      if state.valid then state.value=number end
      row.controls.input:setColor(state.valid and '#edf3f5' or '#f39b8f')
      updatePreview()
    end
    local function shift(direction) state:set(state.value+direction*state.step);updatePreview() end
    row.controls.minus.onClick=function() shift(-1) end
    row.controls.plus.onClick=function() shift(1) end
    fields[id],numbers[id]=row,state
    values[#values+1]={id,function() return state.value end}
    return row
  end
  local function addOption(parent, id, title, defaultValue, tooltip, inverse, margin)
    local row=UI.createWidget('TargetBotCreatureEditorOption',parent)
    row:setId(id);row:setTooltip(tooltip);row.caption:setText(title)
    if margin then row:setMarginTop(margin) end
    local active=config[id]==nil and defaultValue or config[id]==true
    row:setOn(inverse and not active or not inverse and active)
    local function refresh()
      if image(row.track,row:isOn() and 'switch-on' or 'switch-off') then row.track:setText('')
      else row.track:setText(row:isOn() and 'ON' or 'OFF') end
      row.caption:setColor(row:isOn() and '#edf3f5' or '#c1cbd1')
    end
    refresh()
    row.onClick=function() row:setOn(not row:isOn());refresh();updatePreview() end
    fields[id]=row
    values[#values+1]={id,function() if inverse then return not row:isOn() end;return row:isOn() end}
    return row
  end
  addNumber(movement,'priority','Prioridad',0,20,1,'Prioridad de este objetivo frente a los demas.')
  addNumber(movement,'danger','Peligro',0,10,1,'Valor de peligro asignado a esta criatura.')
  addNumber(movement,'maxDistance','Maxima',1,10,10,'Distancia maxima para considerar este objetivo.','SQM')
  gap(movement)
  addOption(movement,'chase','Perseguir objetivo',true,'Acercarse al objetivo cuando se usa el movimiento clasico.')
  -- Keep Distance + antitrap and Reposicionar are retired (Agrupar cercanos with SQM replaces
  -- them). Saved values are kept: this editor copies every key it does not show.
  addOption(movement,'anchor','Anclaje',false,'Fija el centro donde empieza el combate. El TargetBot se mueve dentro del radio; solo Agrupar cercanos/antitrap salen hasta 2 SQM para no quedar rodeado (4 si queda encerrado) y vuelven enseguida. El centro no se mueve hasta terminar el combate o que el lure vuelva a reunir con CaveBot.',false,8)
  addNumber(movement,'anchorRange','Radio',1,10,3,'Radio alrededor del centro fijado: perseguir, agrupar, antitrap, BugMap, esquivar waves, alinear hechizos y loot en combate. A los monstruos de fuera se les sigue atacando, pero no se los persigue.','SQM','anchor')
  addOption(movement,'avoidAttacks','Evitar waves enemigas',false,'Buscar posiciones laterales para evitar ataques en linea.',false,8)
  addOption(pull,'dynamicLure','Lure dinamico',false,'Usar los limites minimo y maximo para reunir monstruos y retomar CaveBot.')
  addNumber(pull,'lureMin','Minimo',0,29,1,'Cantidad de monstruos para retomar el recorrido.',nil,'dynamicLure')
  addNumber(pull,'lureMax','Maximo',1,30,3,'Cantidad de monstruos para detener el lure dinamico (y fijar el Anclaje).',nil,'dynamicLure')
  gap(pull)
  addOption(pull,'dynamicLureDelay','Pausa dinamica',false,'Esperar a los monstruos del lure cuando se quedan atras, sin frenar en cada paso.')
  addNumber(pull,'lureSpread','Distancia',2,8,4,'Si el monstruo mas atrasado se aleja mas que esto, el personaje se detiene hasta que se acerque.','SQM','dynamicLureDelay')
  addNumber(pull,'delayFrom','Desde',1,29,2,'Cantidad de monstruos a partir de la cual se espera a la manada.','monst.','dynamicLureDelay')
  gap(pull)
  -- Lure clasico and Lure con CaveBot are retired (Lure dinamico replaces them); saved values are kept.
  addOption(pull,'closeLure','Agrupar monstruos cercanos',false,'Busca una salida cuando los monstruos superan el limite o estan por cerrar el paso.',false,12)
  addNumber(pull,'closeLureAmount','Hasta',0,8,3,'Limite de monstruos a la distancia elegida en el panel de TargetBot (1 SQM = pegados, incluidas las diagonales). La proteccion puede actuar antes si quedan pocas salidas.',nil,'closeLure')
  addOption(combat,'dontLoot','Recoger loot',false,'Recoger el loot de esta criatura. Apagarlo activa la exclusion de loot.',true)
  gap(combat)
  local ammoTitle=label(combat,'TargetBotCreatureEditorText','Prioridad de municion:','ammoTitle')
  ammoTitle:setHeight(18);ammoTitle:setMarginTop(4)
  local ammo=UI.createWidget('TargetBotCreatureEditorAmmo',combat)
  ammo:setId('ammo');ammo:setTooltip('Conserva la prioridad de Diamond Arrows, Burst Arrows, ambas o ninguna.')
  local ammoChoices={
    {text='Sin prioridad',diamond=false,burst=false},
    {text='Diamond Arrows',diamond=true,burst=false},
    {text='Burst Arrows',diamond=false,burst=true},
    {text='Diamond + Burst',diamond=true,burst=true},
  }
  for _,choice in ipairs(ammoChoices) do
    ammo:addOption(choice.text)
    if choice.diamond==(config.diamondArrows==true) and choice.burst==(config.burstArrows==true) then ammo:setCurrentOption(choice.text) end
  end
  local function ammoChoice()
    for _,choice in ipairs(ammoChoices) do if choice.text==ammo:getCurrentOption().text then return choice end end
    return ammoChoices[1]
  end
  values[#values+1]={'diamondArrows',function() return ammoChoice().diamond end}
  values[#values+1]={'burstArrows',function() return ammoChoice().burst end}
  ammo.onOptionChange=function() updatePreview() end
  addOption(combat,'rpSafe','RP PvP Safe - Arrows',false,'Conservar la seguridad PvP de las flechas.',false,10)
  gap(combat)
  label(combat,'TargetBotCreatureEditorSection','Sin salida','emergencyTitle')
  addOption(combat,'antitrapBugMap','BugMap si no hay salida',false,'Nunca dejarse encerrar: sale caminando antes de que tapen la ultima salida (con o sin Agrupar cercanos) y, si aun asi queda encerrado, usa BugMap tras la Espera.')
  addNumber(combat,'antitrapBugMapDelay','Espera',60,3000,80,'Tiempo encerrado del todo antes de usar BugMap: minimo 60 ms. Si un BugMap no lo saca, reintenta cada 400 ms.','ms','antitrapBugMap')
  label(combat,'TargetBotCreatureEditorNote','Antes de quedar encerrado busca salida; BugMap solo si ya no queda ninguna.','emergencyHelp')
  summary=UI.createWidget('TargetBotCreatureEditorSummary',combat)
  summary:setId('summary');image(summary.icon,'summary')
  local function number(id) return numbers[id].value end
  local function validation()
    if not editor.name:getText():find('%S') then return 'Escribe el nombre de un objetivo.' end
    for _,value in ipairs(values) do
      if numbers[value[1]] and not numbers[value[1]].valid then return 'Corrige la cantidad marcada en rojo.' end
    end
    if fields.dynamicLure:isOn() and number('lureMin')>=number('lureMax') then
      return 'Lure dinamico: el minimo debe ser menor que el maximo.'
    end
  end
  updatePreview=function()
    if loading then return end
    local changed=editor.name:getText()~=initial.name
    for _,value in ipairs(values) do if value[2]()~=initial[value[1]] then changed=true end end
    for _,state in pairs(numbers) do
      if not state.valid then changed=true end
      local enabled=not state.owner or fields[state.owner]:isOn()
      state.row:setEnabled(enabled);state.row:setOpacity(enabled and 1 or 0.6)
    end
    summary.line1:setText(fields.dynamicLure:isOn() and ('Lure dinamico: '..number('lureMin')..' - '..number('lureMax')) or 'Lure dinamico: apagado')
    summary.line2:setText('Distancia maxima: '..number('maxDistance')..' SQM')
    summary.line3:setText(fields.closeLure:isOn() and ('Agrupar cercanos: max. '..number('closeLureAmount')) or 'Agrupar cercanos: apagado')
    local errorText=validation()
    editor.footer.ok:setEnabled(errorText==nil)
    editor.message:setColor(errorText and '#f3a092' or changed and '#ffd05d' or '#b9c8cf')
    editor.message:setText(errorText or (changed and 'Cambios sin guardar\nGuardar aplica los ajustes.' or 'Sin cambios pendientes\nAjustes de este objetivo.'))
  end
  editor.name.onTextChange=function() updatePreview() end
  editor.footer.cancel.onClick=function() editor:destroy() end
  editor.onEscape=editor.footer.cancel.onClick
  editor.footer.ok.onClick=function()
    local errorText=validation()
    if errorText then editor.message:setColor('#f3a092');editor.message:setText(errorText);return end
    -- Preserve attack spells and other server settings absent from this editor.
    local newConfig={}
    for key,value in pairs(config) do newConfig[key]=value end
    newConfig.name=editor.name:getText()
    for _,value in ipairs(values) do newConfig[value[1]]=value[2]() end
    newConfig.regex=''
    for part in string.gmatch(newConfig.name,'[^,]+') do
      if newConfig.regex:len()>0 then newConfig.regex=newConfig.regex..'|' end
      newConfig.regex=newConfig.regex..'^'..part:trim():lower():gsub('%*','.*'):gsub('%?','.?')..'$'
    end
    editor:destroy();callback(newConfig)
  end
  editor.onEnter=editor.footer.ok.onClick
  initial.name=editor.name:getText()
  for _,value in ipairs(values) do initial[value[1]]=value[2]() end
  loading=false;updatePreview()
end
