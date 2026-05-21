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
  local configName = modules.game_bot.contentsPanel.config:getCurrentOption().text
  local path = "/bot/" .. configName .. "/cavebot_configs"
  local profiles = {}

  if not g_resources.directoryExists(path) then
    return profiles
  end

  local files = g_resources.listDirectoryFiles(path, false, false)
  for _, file in ipairs(files) do
    local ext = file:split(".")
    if ext[#ext]:lower() == "cfg" then
      local profileName = file:gsub("%.[Cc][Ff][Gg]$", "")
      table.insert(profiles, profileName)
    end
  end

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

CaveBot.Editor.setup = function()
  CaveBot.Editor.ui = UI.createWidget("CaveBotEditorPanel")
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
    value="2520,60000",
    title="Wait stamina",
    description="Minimum stamina in minutes (max 2520 = 42h),check delay in milliseconds",
    multiline=false,
    validation="^\\s*([0-9]|[1-9][0-9]{1,2}|1[0-9]{3}|2[0-4][0-9]{2}|25[0-1][0-9]|2520)\\s*(,\\s*[0-9]+\\s*)?$"
  })
  registerAction("sethealbot", "set healbot", {
    value="on",
    title="Set HealBot",
    description="on,off or toggle",
    multiline=false,
    validation="^\\s*(on|off|toggle|switch|true|false|yes|no|1|0|enable|disable|enabled|disabled|activar|desactivar|prender|encender|apagar|cambiar)\\s*$"
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

  if action == "setprofile" then
    return CaveBot.Editor.editSetProfile(value, function(newText)
      callback(action, newText)
    end)
  end

  UI.EditorWindow(value, params, function(newText)
    callback(action, newText)
  end)   
end
