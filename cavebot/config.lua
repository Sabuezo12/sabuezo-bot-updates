-- config for bot
CaveBot.Config = {}
CaveBot.Config.values = {}
CaveBot.Config.default_values = {}
CaveBot.Config.value_setters = {}

storage.caveBotSafety = storage.caveBotSafety or {}
CaveBot.Config.safety = storage.caveBotSafety
if CaveBot.Config.safety.deathCounter == nil then
  CaveBot.Config.safety.deathCounter = (storage.extras and tonumber(storage.extras.deathCounter)) or 0
end
if CaveBot.Config.safety.wasDead == nil then
  CaveBot.Config.safety.wasDead = false
end
if CaveBot.Config.safety.antiRedFrags == nil then
  CaveBot.Config.safety.antiRedFrags = 0
end
if CaveBot.Config.safety.antiRedUnequipped == nil then
  CaveBot.Config.safety.antiRedUnequipped = false
end
CaveBot.Config.safety.deathPolicyActive = false
CaveBot.Config.safety.deathWaitUntil = 0
CaveBot.Config.safety.deathWaitCaveBotWasOn = false
CaveBot.Config.safety.deathWaitTargetBotWasOn = false
CaveBot.Config.antiRedExitScheduled = false

CaveBot.Config.updateDeathLabel = function()
  local label = CaveBot.Config.deathStatusLabel
  if not label then return end

  local deaths = tonumber(CaveBot.Config.safety.deathCounter) or 0
  local limit = tonumber(CaveBot.Config.values.deathLimit) or 0
  local text = tostring(deaths)
  if limit > 0 then
    text = text .. "/" .. limit
  end
  text = text .. " muertes"
  local waitUntil = tonumber(CaveBot.Config.safety.deathWaitUntil) or 0

  if waitUntil > 0 and now and waitUntil > now then
    local minutesLeft = math.ceil((waitUntil - now) / 60000)
    text = text .. " | " .. minutesLeft .. "m"
  end

  label:setText(text)

  if limit > 0 and deaths >= limit then
    label:setColor("#ff0000")
  else
    label:setColor("#ffaa00")
  end
end

local function trimText(value)
  return tostring(value or ""):gsub("^%s*(.-)%s*$", "%1")
end

CaveBot.Config.clearDeathPolicy = function()
  CaveBot.Config.safety.deathPolicyActive = false
  CaveBot.Config.safety.deathWaitUntil = 0
  CaveBot.Config.safety.deathWaitCaveBotWasOn = false
  CaveBot.Config.safety.deathWaitTargetBotWasOn = false
end

CaveBot.Config.resetDeathCounter = function(silent)
  CaveBot.Config.safety.deathCounter = 0
  CaveBot.Config.safety.wasDead = false
  CaveBot.Config.clearDeathPolicy()
  CaveBot.Config.updateDeathLabel()
  if not silent then
    warn("El contador de muertes ha sido reiniciado a 0.")
  end
end

CaveBot.Config.resetAntiRedState = function()
  CaveBot.Config.safety.antiRedFrags = 0
  CaveBot.Config.safety.antiRedUnequipped = false
  CaveBot.Config.antiRedExitScheduled = false
end

local function getDefaultDeathLimit()
  if storage.extras and tonumber(storage.extras.deathLimit) then
    return tonumber(storage.extras.deathLimit)
  end

  return 2
end

local function caveBotSafetyExit()
  if CaveBot and CaveBot.setOff then pcall(CaveBot.setOff) end
  if TargetBot and TargetBot.setOff then pcall(TargetBot.setOff) end

  if g_game and g_game.cancelAttackAndFollow then
    pcall(g_game.cancelAttackAndFollow)
    pcall(g_game.cancelAttackAndFollow)
    pcall(g_game.cancelAttackAndFollow)
  end

  if modules and modules.game_interface and modules.game_interface.forceExit then
    pcall(modules.game_interface.forceExit)
  end
end

local function antiRedShouldExit()
  local killsLeft = 0
  if type(killsToRs) == "function" then
    local ok, result = pcall(killsToRs)
    if ok and tonumber(result) then
      killsLeft = tonumber(result)
    end
  end

  return killsLeft < 6 or (tonumber(CaveBot.Config.safety.antiRedFrags) or 0) > 1
end

local function antiRedUnequipLeft()
  if CaveBot.Config.safety.antiRedUnequipped then return end
  if type(getLeft) ~= "function" or not g_game or not g_game.equipItemId then return end

  local ok, leftItem = pcall(getLeft)
  if not ok or not leftItem then return end

  local okId, id = pcall(function() return leftItem:getId() end)
  if okId and id then
    CaveBot.Config.safety.antiRedUnequipped = true
    pcall(function() g_game.equipItemId(id) end)
  end
end

local function stopCaveTargetAfterDeath()
  if CaveBot and CaveBot.setOff then CaveBot.setOff() end
  if TargetBot and TargetBot.setOff then TargetBot.setOff() end
  warn("Limite de muertes alcanzado. CaveBot y TargetBot detenidos por seguridad.")
end

local function processDeathWait()
  local waitUntil = tonumber(CaveBot.Config.safety.deathWaitUntil) or 0
  if waitUntil <= 0 then return false end

  if now and now < waitUntil then
    CaveBot.Config.updateDeathLabel()
    return true
  end

  local caveBotWasOn = CaveBot.Config.safety.deathWaitCaveBotWasOn
  local targetBotWasOn = CaveBot.Config.safety.deathWaitTargetBotWasOn
  CaveBot.Config.resetDeathCounter(true)

  if caveBotWasOn and CaveBot and CaveBot.setOn then CaveBot.setOn() end
  if targetBotWasOn and TargetBot and TargetBot.setOn then TargetBot.setOn() end

  warn("Espera por muertes finalizada. Contador reseteado y hunt reanudada.")
  return false
end

local function startDeathWait()
  local minutes = tonumber(CaveBot.Config.values.deathWaitMinutes) or 60
  if minutes <= 0 then minutes = 60 end

  CaveBot.Config.safety.deathWaitCaveBotWasOn = CaveBot and CaveBot.isOn and CaveBot.isOn() or false
  CaveBot.Config.safety.deathWaitTargetBotWasOn = TargetBot and TargetBot.isOn and TargetBot.isOn() or false
  CaveBot.Config.safety.deathWaitUntil = now + math.floor(minutes * 60000)

  if CaveBot and CaveBot.setOff then CaveBot.setOff() end
  if TargetBot and TargetBot.setOff then TargetBot.setOff() end

  CaveBot.Config.updateDeathLabel()
  warn("Limite de muertes alcanzado. Esperando " .. minutes .. " minutos antes de volver a la hunt.")
end

local function runDeathLimitPolicy()
  if CaveBot.Config.safety.deathPolicyActive then return end
  CaveBot.Config.safety.deathPolicyActive = true

  local action = tostring(CaveBot.Config.values.deathAction or "stop"):lower()

  if action == "label" then
    local label = trimText(CaveBot.Config.values.deathLabel)
    if label ~= "" and CaveBot and CaveBot.gotoLabel and CaveBot.gotoLabel(label) then
      CaveBot.Config.resetDeathCounter(true)
      warn("Limite de muertes alcanzado. Enviando CaveBot al label: " .. label)
      return
    end

    warn("No se encontro el label de muertes: " .. label)
    stopCaveTargetAfterDeath()
    return
  end

  if action == "wait" then
    startDeathWait()
    return
  end

  stopCaveTargetAfterDeath()
end

local function setButtonState(button, active)
  if not button then return end
  button:setColor(active and "#ffffff" or "#c8c8c8")
  pcall(function()
    button:setImageColor(active and "#225577" or "#3b3b3b")
  end)
end

CaveBot.Config.updateDeathSafetyUi = function()
  local panel = CaveBot.Config.deathSafetyPanel
  if not panel then return end

  local action = tostring(CaveBot.Config.values.deathAction or "stop"):lower()
  setButtonState(panel.actionRow.stopButton, action == "stop")
  setButtonState(panel.actionRow.labelButton, action == "label")
  setButtonState(panel.actionRow.waitButton, action == "wait")

  if action == "label" then
    panel.labelRow:show()
  else
    panel.labelRow:hide()
  end

  if action == "wait" then
    panel.waitRow:show()
  else
    panel.waitRow:hide()
  end

  CaveBot.Config.updateDeathLabel()
end

local function registerCustomConfigValue(id, defaultValue, setter)
  if CaveBot.Config.default_values[id] ~= nil then
    return warn("Duplicated config key: " .. id)
  end

  CaveBot.Config.value_setters[id] = function(value)
    CaveBot.Config.values[id] = value
    setter(value)
  end
  CaveBot.Config.values[id] = defaultValue
  CaveBot.Config.default_values[id] = defaultValue
  CaveBot.Config.value_setters[id](defaultValue)
end

local function registerDeathNumber(id, defaultValue, widget, onSet)
  registerCustomConfigValue(id, defaultValue, function(value)
    value = tonumber(value) or defaultValue
    CaveBot.Config.values[id] = value
    widget:setText(value, true)
    if onSet then onSet(value) end
  end)

  widget.onTextChange = function(widget, newValue)
    local value = tonumber(newValue)
    if not value then return end
    CaveBot.Config.values[id] = value
    if onSet then onSet(value) end
    CaveBot.save()
  end
end

local function registerDeathText(id, defaultValue, widget, onSet)
  registerCustomConfigValue(id, defaultValue, function(value)
    value = tostring(value or "")
    CaveBot.Config.values[id] = value
    widget:setText(value, true)
    if onSet then onSet(value) end
  end)

  widget.onTextChange = function(widget, newValue)
    CaveBot.Config.values[id] = tostring(newValue or "")
    if onSet then onSet(CaveBot.Config.values[id]) end
    CaveBot.save()
  end
end

local function registerDeathSwitch(id, defaultValue, widget, onSet)
  registerCustomConfigValue(id, defaultValue, function(value)
    value = value == true
    CaveBot.Config.values[id] = value
    widget:setOn(value, true)
    if onSet then onSet(value) end
  end)

  widget.onClick = function(widget)
    widget:setOn(not widget:isOn())
    CaveBot.Config.values[id] = widget:isOn()
    if onSet then onSet(CaveBot.Config.values[id]) end
    CaveBot.save()
  end
end

local function registerDeathAction(panel)
  local choices = {stop = true, label = true, wait = true}
  registerCustomConfigValue("deathAction", "stop", function(value)
    value = tostring(value or "stop"):lower()
    if not choices[value] then value = "stop" end
    CaveBot.Config.values.deathAction = value
    CaveBot.Config.updateDeathSafetyUi()
  end)

  local function choose(value)
    CaveBot.Config.value_setters.deathAction(value)
    CaveBot.save()
  end

  panel.actionRow.stopButton.onClick = function() choose("stop") end
  panel.actionRow.labelButton.onClick = function() choose("label") end
  panel.actionRow.waitButton.onClick = function() choose("wait") end
end

CaveBot.Config.setupDeathSafetyPanel = function(parent)
  local panel = UI.createWidget("CaveBotDeathSafetyPanel", parent)
  CaveBot.Config.deathSafetyPanel = panel
  CaveBot.Config.deathStatusLabel = panel.statusRow.deathCounterLabel

  registerDeathNumber("deathLimit", getDefaultDeathLimit(), panel.limitRow.limitEdit, function()
    CaveBot.Config.updateDeathLabel()
  end)
  registerDeathAction(panel)
  registerDeathText("deathLabel", "", panel.labelRow.labelEdit)
  registerDeathNumber("deathWaitMinutes", 60, panel.waitRow.waitEdit)
  registerDeathSwitch("antiRed", false, panel.antiRedRow.antiRedSwitch, function()
    CaveBot.Config.resetAntiRedState()
  end)

  panel.limitRow.limitEdit:setTooltip("Cantidad de muertes permitidas antes de ejecutar la accion.")
  panel.actionRow.stopButton:setTooltip("Al llegar al limite, apaga CaveBot y TargetBot.")
  panel.actionRow.labelButton:setTooltip("Al llegar al limite, salta al label indicado y resetea el contador.")
  panel.actionRow.waitButton:setTooltip("Al llegar al limite, espera los minutos indicados y vuelve a la hunt.")
  panel.labelRow.labelEdit:setTooltip("Label al que ira el CaveBot si la accion seleccionada es Label.")
  panel.waitRow.waitEdit:setTooltip("Minutos que esperara si la accion seleccionada es Esperar.")
  panel.antiRedRow.antiRedSwitch:setTooltip("Al detectar warning de frag, detiene bots, cancela ataque e intenta salir.")

  panel.statusRow.resetButton.onClick = function()
    CaveBot.Config.resetDeathCounter()
  end
  panel.statusRow.resetButton:setTooltip("Reinicia el contador de muertes.")
  panel.statusRow.resetButton:setColor("#ffffff")
  pcall(function() panel.statusRow.resetButton:setImageColor("#663333") end)

  CaveBot.Config.updateDeathSafetyUi()
end

CaveBot.Config.setup = function()
  CaveBot.Config.ui = UI.createWidget("CaveBotConfigPanel")
  local ui = CaveBot.Config.ui
  local add = CaveBot.Config.add
  
  add("ping", "Server ping", 100)
  add("walkDelay", "Walk delay", 10)
  add("mapClick", "Use map click", false)
  add("mapClickDelay", "Map click delay", 100)
  add("ignoreFields", "Ignore fields", false)  
  add("skipBlocked", "Skip blocked path", false)  
  add("useDelay", "Delay after use", 400)
  CaveBot.Config.setupDeathSafetyPanel(ui)
end

CaveBot.Config.show = function()
  CaveBot.Config.ui:show()
end

CaveBot.Config.hide = function()
  CaveBot.Config.ui:hide()
end

CaveBot.Config.onConfigChange = function(configName, isEnabled, configData)
  for k, v in pairs(CaveBot.Config.default_values) do
    CaveBot.Config.value_setters[k](v)
  end
  if not configData then
    CaveBot.Config.updateDeathLabel()
    return
  end
  for k, v in pairs(configData) do
    if CaveBot.Config.value_setters[k] then
      CaveBot.Config.value_setters[k](v)
    end
  end
  CaveBot.Config.updateDeathLabel()
end

CaveBot.Config.save = function()
  return CaveBot.Config.values
end

CaveBot.Config.add = function(id, title, defaultValue)
  if CaveBot.Config.default_values[id] ~= nil then
    return warn("Duplicated config key: " .. id)
  end
    
  local panel
  local setter -- sets value
  if type(defaultValue) == "number" then
    panel = UI.createWidget("CaveBotConfigNumberValuePanel", CaveBot.Config.ui)
    panel:setId(id)
    setter = function(value)
      CaveBot.Config.values[id] = value
      panel.value:setText(value, true)
      if id == "deathLimit" then CaveBot.Config.updateDeathLabel() end
    end
    setter(defaultValue)
    panel.value.onTextChange = function(widget, newValue)
      newValue = tonumber(newValue)
      if newValue then
        CaveBot.Config.values[id] = newValue
        if id == "deathLimit" then CaveBot.Config.updateDeathLabel() end
        CaveBot.save()
      end
    end
  elseif type(defaultValue) == "boolean" then
    panel = UI.createWidget("CaveBotConfigBooleanValuePanel", CaveBot.Config.ui)
    panel:setId(id)
    setter = function(value)
      CaveBot.Config.values[id] = value
      panel.value:setOn(value, true)
      if id == "antiRed" then CaveBot.Config.resetAntiRedState() end
    end
    setter(defaultValue)
    panel.value.onClick = function(widget)
      widget:setOn(not widget:isOn())
      CaveBot.Config.values[id] = widget:isOn()
      if id == "antiRed" then CaveBot.Config.resetAntiRedState() end
      CaveBot.save()
    end
  elseif type(defaultValue) == "string" then
    panel = UI.createWidget("CaveBotConfigTextValuePanel", CaveBot.Config.ui)
    panel:setId(id)
    setter = function(value)
      value = tostring(value or "")
      CaveBot.Config.values[id] = value
      panel.value:setText(value, true)
    end
    setter(defaultValue)
    panel.value.onTextChange = function(widget, newValue)
      CaveBot.Config.values[id] = tostring(newValue or "")
      CaveBot.save()
    end
  else
    return warn("Invalid default value of config for key " .. id .. ", should be number, string or boolean")
  end
  
  panel.title:setText(tr(title) .. ":")
  
  CaveBot.Config.value_setters[id] = setter
  CaveBot.Config.values[id] = defaultValue
  CaveBot.Config.default_values[id] = defaultValue
end

CaveBot.Config.addChoice = function(id, title, choices, defaultValue)
  if CaveBot.Config.default_values[id] ~= nil then
    return warn("Duplicated config key: " .. id)
  end
  if type(choices) ~= "table" or #choices == 0 then
    return warn("Invalid choice list for config key: " .. id)
  end

  local panel = UI.createWidget("CaveBotConfigChoiceValuePanel", CaveBot.Config.ui)
  local choiceIndex = {}
  panel:setId(id)

  for index, choice in ipairs(choices) do
    choiceIndex[choice.value] = index
  end

  local function normalizeChoice(value)
    value = tostring(value or defaultValue):lower()
    if not choiceIndex[value] then
      value = defaultValue
    end
    return value
  end

  local setter = function(value)
    value = normalizeChoice(value)
    CaveBot.Config.values[id] = value
    panel.value:setText(choices[choiceIndex[value]].text)
  end

  setter(defaultValue)
  panel.value.onClick = function(widget)
    local index = choiceIndex[CaveBot.Config.values[id]] or 1
    index = index + 1
    if index > #choices then index = 1 end
    setter(choices[index].value)
    CaveBot.save()
  end

  panel.title:setText(tr(title) .. ":")

  CaveBot.Config.value_setters[id] = setter
  CaveBot.Config.values[id] = defaultValue
  CaveBot.Config.default_values[id] = defaultValue
end

CaveBot.Config.get = function(id)
  if CaveBot.Config.values[id] == nil then
    return warn("Invalid CaveBot.Config.get, id: " .. id)
  end
  return CaveBot.Config.values[id]
end

CaveBot.Config.set = function(id, value)
  if CaveBot.Config.get(id) == nil then return end
  CaveBot.Config.value_setters[id](value)
  CaveBot.save()
end

macro(500, function()
  if processDeathWait() then return end

  local limit = tonumber(CaveBot.Config.values.deathLimit) or 0
  if limit <= 0 then return end
  if type(hppercent) ~= "function" then return end

  local hp = hppercent()
  if not hp then return end

  if hp <= 1 and not CaveBot.Config.safety.wasDead then
    CaveBot.Config.safety.wasDead = true
    return
  end

  if hp > 50 and CaveBot.Config.safety.wasDead then
    CaveBot.Config.safety.wasDead = false
    CaveBot.Config.safety.deathCounter = (tonumber(CaveBot.Config.safety.deathCounter) or 0) + 1
    CaveBot.Config.updateDeathLabel()
    warn("Muerte detectada. Llevas: " .. CaveBot.Config.safety.deathCounter)

    if CaveBot.Config.safety.deathCounter >= limit then
      runDeathLimitPolicy()
    end
  end
end)

onTextMessage(function(mode, text)
  if not CaveBot.Config.values.antiRed then return end
  if type(text) ~= "string" or not text:find("Warning! The murder of", 1, true) then return end

  CaveBot.Config.safety.antiRedFrags = (tonumber(CaveBot.Config.safety.antiRedFrags) or 0) + 1
  if not antiRedShouldExit() or CaveBot.Config.antiRedExitScheduled then return end

  CaveBot.Config.antiRedExitScheduled = true
  if EquipManager and EquipManager.setOff then pcall(EquipManager.setOff) end

  schedule(100, function()
    antiRedUnequipLeft()
    caveBotSafetyExit()
  end)
end)
