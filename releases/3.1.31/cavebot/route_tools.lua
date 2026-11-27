importStyle('/cavebot/route_tools.otui')
local F=CaveBot.FunctionRules
local function skin(name,children)
  local styles=HelperAppearance and HelperAppearance.metadata and HelperAppearance.metadata.styles
  if type(styles)~='table' or styles[name] or not styles.CaveBotZonePZWindow then return end
  local function copy(value)
    if type(value)~='table'then return value end
    local result={};for k,v in pairs(value)do result[k]=copy(v)end;return result
  end
  local window=copy(styles.CaveBotZonePZWindow)
  window.style,window.children=name,{}
  local function nodeFor(child)
    local kind,id=child[1],child[2]
    local node=copy(styles[kind] or {props={},states={}})
    node.style,node.type,node.id,node.children=kind,kind,id,{}
    for _,nested in ipairs(child[3] or {})do node.children[#node.children+1]=nodeFor(nested)end
    return node
  end
  for _,child in ipairs(children)do window.children[#window.children+1]=nodeFor(child)end
  styles[name]=window
end
CaveBot.Editor.skinWindow=skin -- also used by cavebot/function_editor.lua
skin('CaveBotRuleWindow',{
  {'HelperThemeLabel','presetTitle'},{'HelperThemeCombo','preset'},
  {'HelperThemeLabel','sec1'},{'HelperThemeLabel','conditionTitle'},{'HelperThemeCombo','condition'},
  {'HelperThemeLabel','condHelp'},
  {'HelperThemeLabel','itemTitle'},{'HelperThemeInput','itemId'},
  {'HelperThemeLabel','thresholdTitle'},{'HelperThemeInput','threshold'},
  {'HelperThemeLabel','teamTitle'},{'HelperThemeInput','names'},
  {'HelperThemeLabel','rangeTitle'},{'HelperThemeInput','range'},
  {'HelperThemeButton','moreToggle'},
  {'HelperThemeLabel','joinTitle'},{'HelperThemeCombo','join'},{'HelperThemeCombo','condition2'},
  {'HelperThemeLabel','threshold2Title'},{'HelperThemeInput','threshold2'},
  {'HelperThemeLabel','param2Title'},{'HelperThemeInput','param2'},
  {'HelperThemeLabel','names2Title'},{'HelperThemeInput','names2'},
  {'HelperThemeLabel','intervalTitle'},{'HelperThemeInput','interval'},
  {'HelperThemeLabel','sec2'},
  {'HelperThemeLabel','yesTitle'},{'HelperThemeCombo','yesMode'},{'HelperThemeCombo','yesLabel'},{'HelperThemeInput','yesText'},
  {'HelperThemeCombo','yesBp'},
  {'HelperThemeLabel','noTitle'},{'HelperThemeCombo','noMode'},{'HelperThemeCombo','noLabel'},{'HelperThemeInput','noText'},
  {'HelperThemeCombo','noBp'},
  {'HelperThemeLabel','preview'},{'HelperThemeLabel','feedback'},
  {'HelperThemeButton','advanced'},{'HelperThemeButton','cancel'},{'HelperThemeButton','ok'}})
skin('CaveBotValidationWindow',{{'HelperThemeScroll','reportPanel',{{'HelperThemeLabel','report'}}},
  {'VerticalScrollBar','reportScroll'},{'HelperThemeButton','closeReport'}})
local function selected(combo)
  local option=combo:getCurrentOption();return option and option.data
end
local function labels()
  local names,seen={},{}
  for _,row in ipairs(CaveBot.actionList:getChildren())do
    if row.action=='label'then
      local name=tostring(row.value):match('^%s*(.-)%s*$')
      if name~='' and not seen[name:lower()]then names[#names+1]=name;seen[name:lower()]=true end
    end
  end
  return names,seen
end
local HELP={
  always='Hace la accion de abajo cada vez que la ruta pasa por este waypoint.',
  supplies='Se cumple cuando te faltan objetos de la lista de supplies del Helper.',
  pz='Se cumple cuando tu personaje tiene el PZ bloqueado.',
  skull='Se cumple cuando tienes skull (blanca, roja, negra o naranja).',
  item='Se cumple cuando te quedan menos unidades del objeto que el valor indicado.',
  capacity='Se cumple cuando tu capacidad es menor que el valor indicado.',
  health='Se cumple cuando tu vida (%) baja del valor indicado.',
  mana='Se cumple cuando tu mana (%) baja del valor indicado.',
  team='Se cumple cuando todo el equipo esta en tu piso y dentro del rango.',
  stamina='Se cumple cuando tu stamina baja de las horas indicadas.',
  hunt='Se cumple cuando llevas al menos esos minutos cazando.',
  laps='Se cumple una vez cada N vueltas completas de la ruta.',
  monsters='Se cumple cuando hay al menos esa cantidad de monstruos cerca.',
  players='Se cumple cuando hay jugadores desconocidos cerca (no party, amigos ni guild).',
  level='Se cumple cuando tu nivel es igual o mayor al indicado.',
  gold='Se cumple cuando llevas al menos ese oro en la mochila.',
}
function CaveBot.Editor.editRule(value,callback)
  local config=F.decode(value) or F.defaults()
  local editor=UI.createWindow('CaveBotRuleWindow')
  editor:setText('CaveBot | Funcion sin programar')
  local W=580
  for _,entry in ipairs(F.CONDITIONS)do
    editor.condition:addOption(entry.text,entry.id)
    if not entry.team and not entry.always then editor.condition2:addOption(entry.text,entry.id)end
  end
  editor.condition:setCurrentOptionByData(config.condition)
  editor.itemId:setText(tostring(config.itemId or 268));editor.threshold:setText(tostring(config.threshold or 100))
  editor.names:setText(config.names or '');editor.range:setText(tostring(config.range or 7))
  editor.interval:setText(tostring((config.intervalMs or 300)/1000))
  editor.join:addOption('Sin segunda','none');editor.join:addOption('Y (las dos)','and');editor.join:addOption('O (una basta)','or')
  local second=config.second
  editor.join:setCurrentOptionByData(second and config.join or 'none')
  editor.condition2:setCurrentOptionByData(second and second.condition or 'capacity')
  editor.threshold2:setText(tostring(second and second.threshold or 100))
  editor.param2:setText(tostring(second and (second.itemId or second.range) or 7))
  editor.names2:setText(second and second.names or '')
  local names,known=labels()
  -- BPs for "Cerrar y reabrir BPs" (233): every window, or one entry of the Container Manager.
  local bpEntries={}
  if type(ContainerManager)=='table' and type(ContainerManager.getEntries)=='function' then
    local ok,list=pcall(ContainerManager.getEntries)
    if ok and type(list)=='table' then bpEntries=list end
  end
  for _,branch in ipairs({'yes','no'})do
    local bp=editor[branch..'Bp']
    local saved=config[branch] and tonumber(config[branch].bp) or 0
    local listed=saved==0
    bp:addOption('Todas las BPs',0)
    for _,entry in ipairs(bpEntries)do
      local id=tonumber(entry.id)
      if id and id>0 then
        bp:addOption(tostring(entry.name or 'BP')..' ('..id..')'..(entry.enabled and '' or ' - apagada'),id)
        if id==saved then listed=true end
      end
    end
    if not listed then bp:addOption('BP '..saved..' (no esta en el Container Manager)',saved)end
    bp:setCurrentOptionByData(saved)
  end
  for _,branch in ipairs({'yes','no'})do
    local mode,combo=editor[branch..'Mode'],editor[branch..'Label']
    for _,option in ipairs(F.MODES)do mode:addOption(option.text,option.id)end
    combo:addOption('Selecciona un label','')
    for _,name in ipairs(names)do combo:addOption(name,name)end
    local entry=config[branch]or {mode='next',label=''}
    entry.label=entry.label or ''
    if entry.label~='' and not known[tostring(entry.label):lower()]then combo:addOption(entry.label..' (no existe)',entry.label)end
    mode:setCurrentOptionByData(entry.mode);combo:setCurrentOptionByData(entry.label or '')
    editor[branch..'Text']:setText(entry.text or '')
  end
  -- Preset selector: never applied on open, only when the user picks one.
  editor.preset:addOption('Empezar con un ejemplo...','')
  editor.preset:addOption('Supplies bajos: ir a refill','refill')
  editor.preset:addOption('Esperar al equipo','team')
  editor.preset:addOption('Esperar stamina','stamina')
  editor.preset:addOption('Alerta si hay jugadores','players')
  editor.preset:addOption('Cerrar y reabrir BPs (despues de comprar)','bps')
  editor.preset:setCurrentOptionByData('')
  local open=second~=nil
  local note=''
  local function draft()
    local c={version=1,condition=selected(editor.condition),itemId=tonumber(editor.itemId:getText()),
      threshold=tonumber(editor.threshold:getText()),names=editor.names:getText(),range=tonumber(editor.range:getText()),
      intervalMs=(tonumber(editor.interval:getText())or 0)*1000,
      yes={mode=selected(editor.yesMode),label=selected(editor.yesLabel),text=editor.yesText:getText()},
      no={mode=selected(editor.noMode),label=selected(editor.noLabel),text=editor.noText:getText()}}
    for _,branch in ipairs({'yes','no'})do
      if c[branch].mode=='reopen_bps'then c[branch].bp=tonumber(selected(editor[branch..'Bp']))or 0 end
    end
    local join=selected(editor.join)
    if join=='and' or join=='or' then
      local id=selected(editor.condition2);local meta=F.byId[id] or {}
      local extra=tonumber(editor.param2:getText())
      c.join=join
      c.second={condition=id,threshold=tonumber(editor.threshold2:getText()),
        names=meta.names and editor.names2:getText() or '',
        itemId=meta.item and extra or nil,range=meta.range and extra or nil}
    end
    -- "Siempre" alone has no "si no se cumple": that branch stays the plain next waypoint.
    if c.condition=='always' and not c.second then c.no={mode='next',label='',text=''}end
    return c
  end
  -- Every widget stays a direct child (editor.<id> API); the form is re-flowed
  -- by margins from the parent corner, so there are no anchor chains/cycles.
  local function put(widget,x,y,width,show)
    widget:setVisible(show)
    if show then
      widget:setMarginTop(y);widget:setMarginLeft(x)
      if width then widget:setWidth(width)end
    end
  end
  local function update()
    local c=draft();local meta=F.byId[c.condition] or {}
    local join=selected(editor.join);local on=join=='and' or join=='or'
    local meta2=F.byId[selected(editor.condition2)] or {}
    local y=0
    put(editor.presetTitle,0,y,100,true);put(editor.preset,106,y,W-106,true);y=y+32
    put(editor.sec1,0,y,W,true);y=y+24
    put(editor.conditionTitle,0,y,100,true);put(editor.condition,106,y,W-106,true);y=y+28
    editor.condHelp:setText(HELP[c.condition] or '');editor.condHelp:setHeight(30)
    put(editor.condHelp,0,y,W,true);y=y+34
    local x=0
    put(editor.itemTitle,x,y,100,meta.item==true);put(editor.itemId,x+106,y,90,meta.item==true)
    if meta.item then x=x+220 end
    editor.thresholdTitle:setText(meta.threshold or 'Valor')
    put(editor.thresholdTitle,x,y,110,meta.threshold~=nil);put(editor.threshold,x+116,y,90,meta.threshold~=nil)
    if meta.item or meta.threshold then y=y+28 end
    local text=meta.names and 'Solo estos (opcional)' or 'Nombres (con comas)'
    editor.teamTitle:setText(text)
    local showNames=meta.team==true or meta.names==true
    put(editor.teamTitle,0,y,150,showNames);put(editor.names,156,y,W-156,showNames)
    if showNames then y=y+28 end
    put(editor.rangeTitle,0,y,150,meta.range==true);put(editor.range,156,y,70,meta.range==true)
    if meta.range then y=y+28 end
    editor.moreToggle:setText((open and '[-] ' or '[+] ')..'Mas opciones'..(on and ' (segunda condicion activa)' or ''))
    put(editor.moreToggle,0,y,320,true);y=y+32
    local showSecond=open and on
    put(editor.joinTitle,0,y,100,open);put(editor.join,106,y,150,open)
    put(editor.condition2,262,y,W-262,showSecond)
    if open then y=y+28 end
    local t2=showSecond and meta2.threshold~=nil
    editor.threshold2Title:setText(meta2.threshold or 'Valor')
    put(editor.threshold2Title,0,y,150,t2);put(editor.threshold2,156,y,90,t2)
    if t2 then y=y+28 end
    local p2=showSecond and (meta2.item or meta2.range)==true
    editor.param2Title:setText(meta2.item and 'Objeto (ID)' or 'Rango (SQM)')
    put(editor.param2Title,0,y,150,p2);put(editor.param2,156,y,90,p2)
    if p2 then y=y+28 end
    local n2=showSecond and meta2.names==true
    put(editor.names2Title,0,y,150,n2);put(editor.names2,156,y,W-156,n2)
    if n2 then y=y+28 end
    put(editor.intervalTitle,0,y,150,open);put(editor.interval,156,y,90,open)
    if open then y=y+28 end
    y=y+6
    put(editor.sec2,0,y,W,true);y=y+24
    local always=c.condition=='always' and not c.second
    editor.yesTitle:setText(always and 'Hacer' or 'Si se cumple')
    for _,branch in ipairs({'yes','no'})do
      -- The "no" branch is read from its own combo: "Siempre" replaced it in the draft.
      local mode=branch=='no' and selected(editor.noMode) or c[branch].mode
      local row=not(always and branch=='no')
      local isText=mode=='say' or mode=='alarm'
      put(editor[branch..'Title'],0,y,100,row);put(editor[branch..'Mode'],106,y,200,row)
      put(editor[branch..'Label'],312,y,W-312,row and not isText and mode=='label')
      put(editor[branch..'Text'],312,y,W-312,row and isText)
      put(editor[branch..'Bp'],312,y,W-312,row and mode=='reopen_bps')
      editor[branch..'Text']:setTooltip(mode=='alarm' and 'Aviso que mostrara la alarma.' or 'Texto que se dice en el juego.')
      if row then y=y+28 end
    end
    local valid,message=F.validate((function()c.version=F.version(c);return c end)())
    if valid then
      local _,currentLabels=labels()
      for _,branch in ipairs({'yes','no'})do
        if c[branch].mode=='label' and not currentLabels[tostring(c[branch].label):lower()]then
          valid,message=false,'El label de destino no existe en esta ruta.'
        end
      end
    end
    local summary='Resumen: '..F.describe(c)
    local lines=0
    for line in(summary..'\n'):gmatch('(.-)\n')do lines=lines+math.max(1,math.ceil(#line/80))end
    local previewHeight=math.max(52,math.min(100,lines*14+8))
    editor.preview:setText(summary);editor.preview:setTooltip(summary)
    editor.preview:setHeight(previewHeight)
    put(editor.preview,0,y+4,W,true);y=y+previewHeight+8
    editor.feedback:setText(valid and note or message)
    editor:setHeight(math.min(700,y+102))
  end
  local loading=false
  local function setBranch(branch,mode,label,text,bp)
    editor[branch..'Mode']:setCurrentOptionByData(mode)
    editor[branch..'Label']:setCurrentOptionByData(label or '')
    editor[branch..'Text']:setText(text or '')
    if bp~=nil then editor[branch..'Bp']:setCurrentOptionByData(bp)end
  end
  local function applyPreset(id)
    note=''
    if id=='' then return end
    local c=draft()
    local function cond(name,threshold,range)
      editor.condition:setCurrentOptionByData(name)
      if threshold then editor.threshold:setText(tostring(threshold))end
      if range then editor.range:setText(tostring(range))end
      editor.join:setCurrentOptionByData('none')
    end
    if id=='refill' then
      local target
      for _,name in ipairs(names)do if name:lower():find('refill',1,true)then target=name;break end end
      target=target or names[1]
      cond('supplies')
      if target then setBranch('yes','label',target);setBranch('no','next')
      else
        setBranch('yes','label','');setBranch('no','next')
        note='Crea antes un label en la ruta (por ejemplo "refill") para elegirlo como destino.'
      end
    elseif id=='team' then
      cond('team',nil,7);setBranch('yes','next');setBranch('no','wait')
      note='Escribe los nombres del equipo separados por comas.'
    elseif id=='stamina' then
      cond('stamina',12);setBranch('yes','wait');setBranch('no','next')
    elseif id=='players' then
      cond('players',1,7);setBranch('yes','alarm',nil,'Jugador cerca');setBranch('no','next')
    elseif id=='bps' then
      -- The BP with V (open the next one when empty) is the one that goes down and hides new ammo.
      local target=0
      for _,entry in ipairs(bpEntries)do
        if entry.enabled and entry.openNextEmpty and tonumber(entry.id) then target=tonumber(entry.id);break end
      end
      cond('always');setBranch('yes','reopen_bps',nil,nil,target);setBranch('no','next')
      note='Ponlo justo despues de buy supplies.'..(target>0 and ' Elegida tu BP con V; puedes cambiarla.' or '')
    end
    local _=c
  end
  for _,id in ipairs({'condition','yesMode','noMode','yesLabel','noLabel','yesBp','noBp','join','condition2'})do
    editor[id].onOptionChange=function()if not loading then update()end end
  end
  for _,id in ipairs({'itemId','threshold','names','range','interval','threshold2','param2','names2','yesText','noText'})do
    editor[id].onTextChange=function()if not loading then update()end end
  end
  editor.preset.onOptionChange=function()
    if loading then return end
    local id=selected(editor.preset)
    if id=='' then return end
    loading=true
    applyPreset(id)
    editor.preset:setCurrentOptionByData('')
    loading=false
    update()
  end
  editor.moreToggle.onClick=function()open=not open;update()end
  editor.cancel.onClick=function()editor:destroy()end
  editor.onEscape=editor.cancel.onClick
  if editor.closeButton then editor.closeButton.onClick=editor.cancel.onClick end
  editor.ok.onClick=function()
    local c=draft();local encoded,message=F.encode(c)
    if not encoded then editor.feedback:setText(message);return end
    local _,currentLabels=labels()
    for _,branch in ipairs({'yes','no'})do
      if c[branch].mode=='label'and not currentLabels[tostring(c[branch].label):lower()]then
        editor.feedback:setText('El label de destino no existe en esta ruta.');return
      end
    end
    callback(encoded);editor:destroy()
  end
  editor.advanced.onClick=function()
    local encoded=F.encode(draft())or value or 'return true'
    editor:destroy()
    if CaveBot.Editor.editFunction then
      local ok,window=pcall(CaveBot.Editor.editFunction,encoded,callback)
      if ok and window then return end
    end
    UI.EditorWindow(encoded,CaveBot.Editor.Actions['function'],callback)
  end
  editor:setWidth(600)
  update()
  return editor
end
function CaveBot.Editor.reviewRoute()
  local report=CaveBot.RouteValidation.refresh()
  local window=UI.createWindow('CaveBotValidationWindow')
  window.report=window.reportPanel.report
  local text=CaveBot.RouteValidation.text(report)
  window.report:setText(text)
  local lines=0
  for line in (text..'\n'):gmatch('(.-)\n')do lines=lines+math.max(1,math.ceil(#line/65))end
  window.report:setHeight(math.max(240,lines*16+8))
  window.closeReport.onClick=function()window:destroy()end
  window.onEscape=window.closeReport.onClick
  if window.closeButton then window.closeButton.onClick=window.closeReport.onClick end
  return window
end
