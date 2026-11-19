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
skin('CaveBotRuleWindow',{
  {'HelperThemeLabel','conditionTitle'},{'HelperThemeCombo','condition'},
  {'HelperThemeLabel','itemTitle'},{'HelperThemeInput','itemId'},
  {'HelperThemeLabel','thresholdTitle'},{'HelperThemeInput','threshold'},
  {'HelperThemeLabel','teamTitle'},{'HelperThemeInput','names'},{'HelperThemeInput','range'},
  {'HelperThemeLabel','intervalTitle'},{'HelperThemeInput','interval'},
  {'HelperThemeLabel','yesTitle'},{'HelperThemeCombo','yesMode'},{'HelperThemeCombo','yesLabel'},
  {'HelperThemeLabel','noTitle'},{'HelperThemeCombo','noMode'},{'HelperThemeCombo','noLabel'},
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
function CaveBot.Editor.editRule(value,callback)
  local config=F.decode(value) or F.defaults()
  local editor=UI.createWindow('CaveBotRuleWindow')
  for _,entry in ipairs({{'Faltan supplies configurados','supplies'},{'Cantidad de un objeto por debajo del umbral','item'},
    {'Capacidad por debajo del umbral','capacity'},{'Vida por debajo del umbral (%)','health'},
    {'Mana por debajo del umbral (%)','mana'},{'Equipo reunido en el mismo piso','team'}})do
    editor.condition:addOption(entry[1],entry[2])
  end
  editor.condition:setCurrentOptionByData(config.condition)
  editor.itemId:setText(tostring(config.itemId or 268));editor.threshold:setText(tostring(config.threshold or 100))
  editor.names:setText(config.names or '');editor.range:setText(tostring(config.range or 7))
  editor.interval:setText(tostring((config.intervalMs or 300)/1000))
  local names,known=labels()
  for _,branch in ipairs({'yes','no'})do
    local mode,combo=editor[branch..'Mode'],editor[branch..'Label']
    mode:addOption('Siguiente waypoint','next');mode:addOption('Ir a un label','label');mode:addOption('Esperar y comprobar','wait')
    combo:addOption('Selecciona un label','')
    for _,name in ipairs(names)do combo:addOption(name,name)end
    local entry=config[branch]or {mode='next',label=''}
    if entry.label~='' and not known[tostring(entry.label):lower()]then combo:addOption(entry.label..' (no existe)',entry.label)end
    mode:setCurrentOptionByData(entry.mode);combo:setCurrentOptionByData(entry.label or '')
  end
  local function draft()
    return {version=1,condition=selected(editor.condition),itemId=tonumber(editor.itemId:getText()),
      threshold=tonumber(editor.threshold:getText()),names=editor.names:getText(),range=tonumber(editor.range:getText()),
      intervalMs=(tonumber(editor.interval:getText())or 0)*1000,
      yes={mode=selected(editor.yesMode),label=selected(editor.yesLabel)},
      no={mode=selected(editor.noMode),label=selected(editor.noLabel)}}
  end
  local function update()
    local c=draft();local numeric=c.condition=='item'or c.condition=='capacity'or c.condition=='health'or c.condition=='mana'
    editor.itemId:setEnabled(c.condition=='item');editor.threshold:setEnabled(numeric)
    editor.names:setEnabled(c.condition=='team');editor.range:setEnabled(c.condition=='team')
    editor.yesLabel:setEnabled(c.yes.mode=='label');editor.noLabel:setEnabled(c.no.mode=='label')
    editor.preview:setText(F.describe(c));editor.feedback:setText('')
  end
  for _,id in ipairs({'condition','yesMode','noMode','yesLabel','noLabel'})do editor[id].onOptionChange=update end
  for _,id in ipairs({'itemId','threshold','names','range','interval'})do editor[id].onTextChange=update end
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
    UI.EditorWindow(encoded,CaveBot.Editor.Actions['function'],callback)
  end
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
