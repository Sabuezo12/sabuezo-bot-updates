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
  {'HelperThemeLabel','conditionTitle'},{'HelperThemeCombo','condition'},
  {'HelperThemeLabel','itemTitle'},{'HelperThemeInput','itemId'},
  {'HelperThemeLabel','thresholdTitle'},{'HelperThemeInput','threshold'},
  {'HelperThemeLabel','teamTitle'},{'HelperThemeInput','names'},{'HelperThemeInput','range'},
  {'HelperThemeLabel','joinTitle'},{'HelperThemeCombo','join'},{'HelperThemeCombo','condition2'},
  {'HelperThemeInput','threshold2'},{'HelperThemeInput','param2'},
  {'HelperThemeLabel','intervalTitle'},{'HelperThemeInput','interval'},
  {'HelperThemeLabel','yesTitle'},{'HelperThemeCombo','yesMode'},{'HelperThemeCombo','yesLabel'},{'HelperThemeInput','yesText'},
  {'HelperThemeLabel','noTitle'},{'HelperThemeCombo','noMode'},{'HelperThemeCombo','noLabel'},{'HelperThemeInput','noText'},
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
  for _,entry in ipairs(F.CONDITIONS)do
    editor.condition:addOption(entry.text,entry.id)
    if not entry.team then editor.condition2:addOption(entry.text,entry.id)end
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
  local names,known=labels()
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
  local function draft()
    local c={version=1,condition=selected(editor.condition),itemId=tonumber(editor.itemId:getText()),
      threshold=tonumber(editor.threshold:getText()),names=editor.names:getText(),range=tonumber(editor.range:getText()),
      intervalMs=(tonumber(editor.interval:getText())or 0)*1000,
      yes={mode=selected(editor.yesMode),label=selected(editor.yesLabel),text=editor.yesText:getText()},
      no={mode=selected(editor.noMode),label=selected(editor.noLabel),text=editor.noText:getText()}}
    local join=selected(editor.join)
    if join=='and' or join=='or' then
      local id=selected(editor.condition2);local meta=F.byId[id] or {}
      local extra=tonumber(editor.param2:getText())
      c.join=join
      c.second={condition=id,threshold=tonumber(editor.threshold2:getText()),names='',
        itemId=meta.item and extra or nil,range=meta.range and extra or nil}
    end
    return c
  end
  local function update()
    local c=draft();local meta=F.byId[c.condition] or {}
    editor.itemId:setEnabled(meta.item==true);editor.threshold:setEnabled(meta.threshold~=nil)
    editor.thresholdTitle:setText(meta.threshold or 'Umbral')
    editor.names:setEnabled(meta.team==true or meta.names==true);editor.range:setEnabled(meta.range==true)
    editor.teamTitle:setText(meta.names and 'Nombres' or 'Equipo')
    local join=selected(editor.join);local on=join=='and' or join=='or'
    local meta2=F.byId[selected(editor.condition2)] or {}
    editor.condition2:setEnabled(on);editor.threshold2:setEnabled(on and meta2.threshold~=nil)
    editor.param2:setEnabled(on and (meta2.item or meta2.range)==true)
    editor.threshold2:setTooltip(meta2.threshold or 'Esta condicion no usa valor.')
    editor.param2:setTooltip(meta2.item and 'ID del objeto.' or meta2.range and 'Rango en SQM, de 1 a 10.' or 'No se usa.')
    for _,branch in ipairs({'yes','no'})do
      local mode=c[branch].mode
      local text=mode=='say' or mode=='alarm'
      editor[branch..'Label']:setVisible(not text);editor[branch..'Label']:setEnabled(mode=='label')
      editor[branch..'Text']:setVisible(text)
    end
    local valid,message=F.validate((function()c.version=F.version(c);return c end)())
    editor.preview:setText(F.describe(c));editor.feedback:setText(valid and '' or message)
  end
  for _,id in ipairs({'condition','yesMode','noMode','yesLabel','noLabel','join','condition2'})do editor[id].onOptionChange=update end
  for _,id in ipairs({'itemId','threshold','names','range','interval','threshold2','param2','yesText','noText'})do
    editor[id].onTextChange=update
  end
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
