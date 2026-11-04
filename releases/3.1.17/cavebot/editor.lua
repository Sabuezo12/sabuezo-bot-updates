CaveBot.Editor = {}
CaveBot.Editor.Actions = {}

-- also works as registerAction(action, params), then text == action
-- params are options for text editor or function to be executed when clicked
-- you have many examples how to use it bellow
CaveBot.Editor.registerAction = function(action, text, params)
  if type(text) ~= 'string' then
    params = text
    text = action
  end

  local color = nil
  if type(params) ~= 'function' then
    local raction = CaveBot.Actions[action]
    if not raction then
      return warn("CaveBot editor warn: action " .. action .. " doesn't exist")
    end
    CaveBot.Editor.Actions[action] = params
    color = raction.color
  end
  
  local button = UI.createWidget('CaveBotEditorButton', CaveBot.Editor.ui.buttons)
  button:setText(text)
  if color then
    button:setColor(color)
  end
  button:setFont('verdana-11px-rounded')
  button.onClick = function()    
    if type(params) == 'function' then
      params()
      return
    end
    CaveBot.Editor.edit(action, nil, function(action, value)
      local focusedAction = CaveBot.actionList:getFocusedChild()
      local index = CaveBot.actionList:getChildCount()
      if focusedAction then
        index = CaveBot.actionList:getChildIndex(focusedAction)
      end
      local widget = CaveBot.addAction(action, value)
      CaveBot.actionList:moveChildToIndex(widget, index + 1)
      CaveBot.actionList:focusChild(widget)
      CaveBot.save()
    end)
  end
  return button
end

CaveBot.Editor.getCaveBotProfiles = function()
  local profiles = Config.list("cavebot_configs")

  table.sort(profiles)
  return profiles
end

CaveBot.Editor.parseSetProfileValue = function(value)
  value = tostring(value or ""):trim()
  if value == "" or value == "profileName" then
    return {}
  end

  if value:sub(1, 7):lower() == "random:" then
    value = value:sub(8)
  end

  local selected = {}
  for profile in value:gmatch("[^,]+") do
    profile = profile:trim()
    if profile ~= "" then
      table.insert(selected, profile)
    end
  end

  return selected
end

CaveBot.Editor.formatSetProfileValue = function(profiles)
  if #profiles == 1 then
    return profiles[1]
  end

  return "random:" .. table.concat(profiles, ",")
end

CaveBot.Editor.editSetProfile = function(value, callback)
  local editor = UI.createWindow("CaveBotSetProfileEditorWindow")
  local profiles = CaveBot.Editor.getCaveBotProfiles()
  local selected = CaveBot.Editor.parseSetProfileValue(value)
  local selectedByName = {}
  local profileWidgets = {}

  for _, profile in ipairs(selected) do
    selectedByName[profile] = true
  end

  local function getSelectedProfiles()
    local result = {}
    for _, entry in ipairs(profileWidgets) do
      if entry.widget:isOn() then
        table.insert(result, entry.name)
      end
    end
    return result
  end

  local function updatePreview()
    local selectedProfiles = getSelectedProfiles()
    if #selectedProfiles == 0 then
      editor.preview:setText("Select at least one route.")
    elseif #selectedProfiles == 1 then
      editor.preview:setText("Next route: " .. selectedProfiles[1])
    else
      editor.preview:setText("Random route: " .. #selectedProfiles .. " selected")
    end
  end

  if #profiles == 0 then
    UI.Label("No cavebot configs found.", editor.profiles)
  else
    for _, profile in ipairs(profiles) do
      local widget = UI.createWidget("CaveBotSetProfileCheckBox", editor.profiles)
      widget:setText(profile)
      widget:setOn(selectedByName[profile] == true)
      widget.onClick = function()
        widget:setOn(not widget:isOn())
        updatePreview()
      end
      table.insert(profileWidgets, {name = profile, widget = widget})
    end
  end

  editor.cancel.onClick = function()
    editor:destroy()
  end
  editor.onEscape = editor.cancel.onClick

  editor.ok.onClick = function()
    local selectedProfiles = getSelectedProfiles()
    if #selectedProfiles == 0 then
      return
    end

    editor:destroy()
    callback(CaveBot.Editor.formatSetProfileValue(selectedProfiles))
  end

  updatePreview()
end

CaveBot.Editor.editZonePZ = function(value,callback)
  local zone=CaveBot.FleeTools.zoneConfig(value)
  local editor=UI.createWindow('CaveBotZonePZWindow')
  local p=zone and zone.pos or {x=posx(),y=posy(),z=posz()}
  editor.coordinates:setText(p.x..','..p.y..','..p.z)
  editor.minutes:setText(tostring(zone and zone.minutes or 0))
  editor.feedback:setText(zone and ''or 'Revisa el punto y los minutos antes de guardar.')
  editor.cancel.onClick=function()editor:destroy()end
  editor.onEscape=editor.cancel.onClick
  if editor.closeButton then editor.closeButton.onClick=editor.cancel.onClick end
  editor.ok.onClick=function()
    local position=CaveBot.FleeTools.zonePosition(editor.coordinates:getText())
    local text=editor.minutes:getText()
    if not position or not tostring(editor.coordinates:getText()):match('^%s*%d+%s*,%s*%d+%s*,%s*%d+%s*$')then
      editor.feedback:setText('Punto invalido: usa x,y,z de una casilla PZ.');return
    end
    if not tostring(text):match('^%s*%d+%s*$')then editor.feedback:setText('Espera: minutos enteros de 0 a 10080.');return end
    local encoded=CaveBot.FleeTools.zoneValue(position,tonumber(text))
    if not encoded then editor.feedback:setText('Espera: minutos enteros de 0 a 10080.');return end
    callback(encoded);editor:destroy()
  end
  editor.coordinates.onEnter=editor.ok.onClick;editor.minutes.onEnter=editor.ok.onClick
  return editor
end

CaveBot.Editor.editWaitStamina = function(value, callback)
  local config, message = CaveBot.WaitStamina.decode(value)
  config = config or CaveBot.WaitStamina.defaults()
  config.maximum=config.maximum or 2520
  local editor = UI.createWindow("CaveBotWaitStaminaWindow")
  editor.minimum:setText(CaveBot.WaitStamina.formatHours(config.minimum))
  editor.maximum:setText(CaveBot.WaitStamina.formatHours(config.maximum))
  editor.interval:setText(tostring(config.checkMs / 1000))
  editor.belowMode:addOption("Quedarse y esperar", "wait")
  editor.belowMode:addOption("Ir a un label", "label")
  editor.readyMode:addOption("Siguiente waypoint", "next")
  editor.readyMode:addOption("Ir a un label", "label")
  local function routeLabels()
    local names, seen = {}, {}
    for _, widget in ipairs(CaveBot.actionList:getChildren()) do
      if widget.action == "label" and type(widget.value) == "string" then
        local name = widget.value:trim()
        if name ~= "" and not seen[name:lower()] then names[#names+1]=name; seen[name:lower()]=name end
      end
    end
    return names, seen
  end
  local names, seen = routeLabels()
  local function populate(combo, selected)
    combo:addOption("Selecciona un label", "")
    for _, name in ipairs(names) do combo:addOption(name, name) end
    if selected ~= "" then
      local actual = seen[selected:lower()]
      if not actual then combo:addOption(selected .. " (no existe)", selected) end
      combo:setCurrentOptionByData(actual or selected)
    end
  end
  populate(editor.belowLabel, config.belowLabel)
  populate(editor.readyLabel, config.readyLabel)
  editor.belowMode:setCurrentOptionByData(config.below)
  editor.readyMode:setCurrentOptionByData(config.ready)
  local function selection(combo)
    local option = combo:getCurrentOption()
    return option and option.data or ""
  end
  local function updateModes()
    editor.belowLabel:setEnabled(selection(editor.belowMode) == "label")
    editor.readyLabel:setEnabled(selection(editor.readyMode) == "label")
    editor.feedback:setText("")
  end
  editor.belowMode.onOptionChange=updateModes
  editor.readyMode.onOptionChange=updateModes
  editor.belowLabel.onOptionChange=function() editor.feedback:setText("") end
  editor.readyLabel.onOptionChange=editor.belowLabel.onOptionChange
  updateModes()
  if message then editor.feedback:setText(message) end
  editor.cancel.onClick=function() editor:destroy() end
  editor.onEscape=editor.cancel.onClick
  if editor.closeButton then editor.closeButton.onClick=editor.cancel.onClick end
  editor.ok.onClick=function()
    local minimum = CaveBot.WaitStamina.parseHours(editor.minimum:getText())
    local maximum = CaveBot.WaitStamina.parseHours(editor.maximum:getText())
    local seconds = tonumber(editor.interval:getText())
    if not minimum then editor.feedback:setText("Stamina invalida. Usa HH:MM entre 00:00 y 42:00."); return end
    if not maximum or maximum < minimum then
      editor.feedback:setText("Maxima invalida: debe ser >= minima y <= 42:00."); return
    end
    if not seconds or seconds ~= seconds or seconds < 0.1 or seconds > 3600 then
      editor.feedback:setText("Intervalo invalido: de 0.1 a 3600 segundos."); return
    end
    local draft = {minimum=minimum, maximum=maximum, checkMs=math.floor(seconds * 1000 + 0.5),
      below=selection(editor.belowMode), belowLabel=selection(editor.belowLabel),
      ready=selection(editor.readyMode), readyLabel=selection(editor.readyLabel)}
    local _, currentLabels = routeLabels()
    for _, branch in ipairs({"below", "ready"}) do
      if draft[branch] == "label" and not currentLabels[draft[branch .. "Label"]:lower()] then
        editor.feedback:setText("Selecciona un label que exista en esta ruta."); return
      end
    end
    local encoded, errorText = CaveBot.WaitStamina.encode(draft)
    if not encoded then editor.feedback:setText(errorText); return end
    callback(encoded)
    editor:destroy()
  end
  editor.minimum.onEnter=editor.ok.onClick
  editor.maximum.onEnter=editor.ok.onClick
  editor.interval.onEnter=editor.ok.onClick
  return editor
end


CaveBot.Editor.setup = function()
  CaveBot.Editor.ui = UI.createWidget(Helper and "HelperCaveEditorPanel" or "CaveBotEditorPanel")
  local ui = CaveBot.Editor.ui
  local registerAction = CaveBot.Editor.registerAction

  registerAction("move up", function()
    local action = CaveBot.actionList:getFocusedChild()
    if not action then return end
    local index = CaveBot.actionList:getChildIndex(action)
    if index < 2 then return end
    CaveBot.actionList:moveChildToIndex(action, index - 1)
    CaveBot.actionList:ensureChildVisible(action)
    CaveBot.save()
  end)
  registerAction("edit", function()
    local action = CaveBot.actionList:getFocusedChild()
    if not action or not action.onDoubleClick then return end
    action.onDoubleClick(action)
  end)
  registerAction("move down", function()
    local action = CaveBot.actionList:getFocusedChild()
    if not action then return end
    local index = CaveBot.actionList:getChildIndex(action)
    if index >= CaveBot.actionList:getChildCount() then return end
    CaveBot.actionList:moveChildToIndex(action, index + 1)
    CaveBot.actionList:ensureChildVisible(action)
    CaveBot.save()
  end)
  registerAction("remove", function()
    local action = CaveBot.actionList:getFocusedChild()
    if not action then return end
    action:destroy()
    CaveBot.save()
  end)
    
  registerAction("label", {
    value="labelName",
    title="Label",
    description="Add label",
    multiline=false   
  })
  registerAction("delay", {
    value="500",
    title="Delay",
    description="Delay next action (in milliseconds),randomness (in percent-optional)",
    multiline=false,
    validation="^[0-9]{1,10}$|^[0-9]{1,10},[0-9]{1,4}$"
  })
  registerAction("waitstamina", "wait stamina", {
    value=function() return CaveBot.WaitStamina.encode(CaveBot.WaitStamina.defaults()) end,
    title="Wait stamina",
    description="Minima activa la espera; maxima permite continuar. Horas:minutos y destinos.",
    multiline=false
  })
  registerAction("zonapz", "ZonaPZ", {
    value=function() return posx() .. "," .. posy() .. "," .. posz() end,
    title="ZonaPZ",
    description="Punto PZ y espera solo tras una huida PvP. En ruta normal no espera. 0: sin espera.",
    multiline=false,
    validation="^\\s*[0-9]{1,5}\\s*,\\s*[0-9]{1,5}\\s*,\\s*[0-9]{1,2}\\s*(,\\s*[0-9]{1,5}\\s*)?$"
  })
  registerAction("stepdirection", "step direction", {
    value="sur,30,200",
    title="Step direction",
    description="Direction,max retries,delay in milliseconds",
    multiline=false,
    validation="^\\s*(n|north|norte|e|east|este|derecha|s|south|sur|w|west|oeste|izquierda|ne|northeast|north-east|noreste|nordeste|se|southeast|south-east|sureste|nw|northwest|north-west|noroeste|sw|southwest|south-west|suroeste)\\s*(,\\s*[0-9]+\\s*)?(,\\s*[0-9]+\\s*)?$"
  })
  registerAction("setprofile", "set profile", {
    value="profileName",
    title="Set CaveBot profile",
    description="Change CaveBot route config by profile name without .cfg",
    multiline=false,
    validation="^\\s*(random:)?[^,]+(\\s*,\\s*[^,]+)*\\s*$"
  })
  registerAction("gotolabel", "go to label", {
    value="labelName",
    title="Go to label",
    description="Go to label",
    multiline=false   
  })
  registerAction("goto", "go to", {
    value=function() return posx() .. "," .. posy() .. "," .. posz() end,
    title="Go to position",
    description="Go to position (x,y,z)",
    multiline=false,
    validation="^\\s*([0-9]+)\\s*,\\s*([0-9]+)\\s*,\\s*([0-9]+),?\\s*([0-9]?)$"
  })
  registerAction("use", {
    value=function() return posx() .. "," .. posy() .. "," .. posz() end,
    title="Use",
    description="Use item from position (x,y,z) or from inventory (itemId)",
    multiline=false   
  }) 
  -- Recorded entries can be edited by double-click without adding another
  -- button or changing the classic editor's layout/order.
  CaveBot.Editor.Actions.floorchange = {
    title="Paso de escalera grabado",
    description="Antes: x,y,z; entrada: x,y; llegada: x,y,z (8 numeros)",
    multiline=false,
    width=550,
    validation="^\\s*[0-9]+(\\s*,\\s*[0-9]+){7}\\s*$"
  }
  registerAction("usewith", "use with", {
    value=function() return "itemId," .. posx() .. "," .. posy() .. "," .. posz() end,
    title="Use with",
    description="Use item at position (itemid,x,y,z)",
    multiline=false,
    validation="^\\s*([0-9]+)\\s*,\\s*([0-9]+)\\s*,\\s*([0-9]+)\\s*,\\s*([0-9]+)$"
  })
  registerAction("say", {
    value="text",
    title="Say",
    description="Enter text to say",
    multiline=false   
  }) 
  registerAction("follow", {
    value="NPC name",
    title="Follow Creature",
    description="insert creature name to follow",
    multiline=false   
  })
  registerAction("npcsay", {
    value="text",
    title="NPC Say",
    description="Enter text to NPC say",
    multiline=false   
  }) 
  registerAction("function", {
    title="Edit bot function",
    multiline=true,
    value=CaveBot.Editor.ExampleFunctions[1][2],
    examples=CaveBot.Editor.ExampleFunctions,
    width=650
  })
  
  -- ui.autoRecording.onClick = function()
  --   if ui.autoRecording:isOn() then
  --     CaveBot.Recorder.disable()
  --   else
  --     CaveBot.Recorder.enable()
  --   end
  -- end
  
  -- callbacks
  onPlayerPositionChange(function(pos)
    ui.pos:setText("Position: " .. pos.x .. ", " .. pos.y .. ", " .. pos.z) 
  end)
  ui.pos:setText("Position: " .. posx() .. ", " .. posy() .. ", " .. posz()) 
end

CaveBot.Editor.show = function()
  CaveBot.Editor.ui:show()
end


CaveBot.Editor.hide = function()
  CaveBot.Editor.ui:hide()
end

CaveBot.Editor.edit = function(action, value, callback) -- callback = function(action, value)
  local params = CaveBot.Editor.Actions[action]
  if not params then return end
  if not value then
    if type(params.value) == 'function' then
      value = params.value()
    elseif type(params.value) == 'string' then
      value = params.value
    end
  end

  if action == "waitstamina" then
    return CaveBot.Editor.editWaitStamina(value, function(newText)
      callback(action, newText)
    end)
  end

  if action=='zonapz'then
    return CaveBot.Editor.editZonePZ(value,function(newText)callback(action,newText)end)
  end

  if action == "setprofile" then
    return CaveBot.Editor.editSetProfile(value, function(newText)
      callback(action, newText)
    end)
  end

  UI.EditorWindow(value, params, function(newText)
    callback(action, newText)
  end)   
end
