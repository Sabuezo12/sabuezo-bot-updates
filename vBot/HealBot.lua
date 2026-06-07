local standBySpells = false
local standByItems = false

local red = "#ff0800" -- "#ff0800" / #ea3c53 best
local blue = "#7ef9ff"

setDefaultTab("HP")
local healPanelName = "healbot"
local ui = setupUI([[
Panel
  height: 38

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('HealBot')

  Button
    id: settings
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 17
    text: Setup

  Button
    id: 1
    anchors.top: prev.bottom
    anchors.left: parent.left
    text: 1
    margin-right: 2
    margin-top: 4
    size: 17 17

  Button
    id: 2
    anchors.verticalCenter: prev.verticalCenter
    anchors.left: prev.right
    text: 2
    margin-left: 4
    size: 17 17
    
  Button
    id: 3
    anchors.verticalCenter: prev.verticalCenter
    anchors.left: prev.right
    text: 3
    margin-left: 4
    size: 17 17

  Button
    id: 4
    anchors.verticalCenter: prev.verticalCenter
    anchors.left: prev.right
    text: 4
    margin-left: 4
    size: 17 17 
    
  Button
    id: 5
    anchors.verticalCenter: prev.verticalCenter
    anchors.left: prev.right
    text: 5
    margin-left: 4
    size: 17 17
    
  Label
    id: name
    anchors.verticalCenter: prev.verticalCenter
    anchors.left: prev.right
    anchors.right: parent.right
    text-align: center
    margin-left: 4
    height: 17
    text: Profile #1
    background: #292A2A
]])
ui:setId(healPanelName)

if not HealBotConfig[healPanelName] or not HealBotConfig[healPanelName][1] or #HealBotConfig[healPanelName] ~= 5 then
  HealBotConfig[healPanelName] = {
    [1] = {
      enabled = false,
      spellTable = {},
      itemTable = {},
      name = "Profile #1",
      Visible = true,
      OldSchool = false,
      Cooldown = true,
      Interval = true,
      Conditions = true,
      Delay = true,
      MessageDelay = false
    },
    [2] = {
      enabled = false,
      spellTable = {},
      itemTable = {},
      name = "Profile #2",
      Visible = true,
      OldSchool = false,
      Cooldown = true,
      Interval = true,
      Conditions = true,
      Delay = true,
      MessageDelay = false
    },
    [3] = {
      enabled = false,
      spellTable = {},
      itemTable = {},
      name = "Profile #3",
      Visible = true,
      OldSchool = false,
      Cooldown = true,
      Interval = true,
      Conditions = true,
      Delay = true,
      MessageDelay = false
    },
    [4] = {
      enabled = false,
      spellTable = {},
      itemTable = {},
      name = "Profile #4",
      Visible = true,
      OldSchool = false,
      Cooldown = true,
      Interval = true,
      Conditions = true,
      Delay = true,
      MessageDelay = false
    },
    [5] = {
      enabled = false,
      spellTable = {},
      itemTable = {},
      name = "Profile #5",
      Visible = true,
      OldSchool = false,
      Cooldown = true,
      Interval = true,
      Conditions = true,
      Delay = true,
      MessageDelay = false
    },
  }
end

if not HealBotConfig.currentHealBotProfile or HealBotConfig.currentHealBotProfile == 0 or HealBotConfig.currentHealBotProfile > 5 then 
  HealBotConfig.currentHealBotProfile = 1
end

-- finding correct table, manual unfortunately
local currentSettings
local setActiveProfile = function()
  local n = HealBotConfig.currentHealBotProfile
  currentSettings = HealBotConfig[healPanelName][n]
end
setActiveProfile()

if type(storage.healbotManualCooldowns) ~= "table" then storage.healbotManualCooldowns = {} end
if type(storage.healbotManualCooldowns.spell) ~= "table" then storage.healbotManualCooldowns.spell = {} end
if type(storage.healbotManualCooldowns.item) ~= "table" then storage.healbotManualCooldowns.item = {} end

local manualCooldownStore = storage.healbotManualCooldowns

local activeProfileColor = function()
  for i=1,5 do
    if i == HealBotConfig.currentHealBotProfile then
      ui[i]:setColor("green")
    else
      ui[i]:setColor("white")
    end
  end
end
activeProfileColor()

local sourceFromOption = function(text)
  if text == "Mana Percent" then
    return "MP%"
  elseif text == "Health Percent" then
    return "HP%"
  end
  return "burst"
end

local optionFromSource = function(source)
  if source == "MP" then
    return "Mana Percent"
  elseif source == "HP" then
    return "Health Percent"
  elseif source == "MP%" then
    return "Mana Percent"
  elseif source == "HP%" then
    return "Health Percent"
  end
  return "Burst Damage"
end

local signFromOption = function(text)
  if text == "Above" then
    return ">"
  elseif text == "Below" then
    return "<"
  end
  return "="
end

local optionFromSign = function(sign)
  if sign == ">" then
    return "Above"
  elseif sign == "<" then
    return "Below"
  end
  return "Equal To"
end

local normalizeRelation = function(relation)
  return relation == "or" and "or" or "and"
end

local relationFromWidget = function(widget)
  if not widget then return "and" end
  if widget.getText then
    return normalizeRelation(widget:getText())
  end
  if widget.getCurrentOption then
    local option = widget:getCurrentOption()
    if option and option.text then
      return normalizeRelation(option.text)
    end
  end
  return "and"
end

local currentValueFor = function(origin)
  if origin == "HP%" then
    return hppercent()
  elseif origin == "HP" then
    return hp()
  elseif origin == "MP%" then
    return manapercent()
  elseif origin == "MP" then
    return mana()
  elseif origin == "burst" then
    return burstDamageValue()
  end
  return nil
end

local conditionMatches = function(origin, sign, value)
  local currentValue = currentValueFor(origin)
  local conditionValue = tonumber(value)
  if not currentValue or not conditionValue then return false end

  if sign == "=" then
    return currentValue == conditionValue
  elseif sign == ">" then
    return currentValue >= conditionValue
  elseif sign == "<" then
    return currentValue <= conditionValue
  end

  return false
end

local normalizeManaCost = function(value)
  return math.max(0, tonumber(value) or 0)
end

local currentManaAmount = function()
  if player and player.getMana then
    local ok, value = pcall(function() return player:getMana() end)
    if ok and tonumber(value) then
      return tonumber(value)
    end
  end

  return tonumber(mana()) or 0
end

local extraSummary = function(entry)
  local text = ""
  if entry.extraEnabled then
    text = text .. " " .. normalizeRelation(entry.extraRelation) .. " " .. tostring(entry.extraOrigin) .. tostring(entry.extraSign) .. tostring(entry.extraValue)
  end
  return text
end

local entryConditionsPass = function(entry)
  local mainPass = conditionMatches(entry.origin, entry.sign, entry.value)
  if not entry.extraEnabled then
    return mainPass
  end

  local extraPass = conditionMatches(entry.extraOrigin, entry.extraSign, entry.extraValue)
  if normalizeRelation(entry.extraRelation) == "or" then
    return mainPass or extraPass
  end

  return mainPass and extraPass
end

local parseManualCooldown = function(value)
  if type(value) == "number" then
    return math.max(0, math.floor(value))
  end

  local text = tostring(value or ""):lower():trim()
  if text == "" then return 0 end
  text = text:gsub(",", ".")

  local amount, unit = text:match("^(%d+%.?%d*)%s*([a-z]*)")
  amount = tonumber(amount)
  if not amount then return nil end

  if unit == "" or unit == "ms" or unit == "msec" or unit == "millisecond" or unit == "milliseconds" then
    return math.max(0, math.floor(amount))
  elseif unit == "s" or unit == "sec" or unit == "secs" or unit == "second" or unit == "seconds" or unit == "seg" or unit == "segundo" or unit == "segundos" then
    return math.max(0, math.floor(amount * 1000))
  elseif unit == "m" or unit == "min" or unit == "mins" or unit == "minute" or unit == "minutes" or unit == "minuto" or unit == "minutos" then
    return math.max(0, math.floor(amount * 60000))
  elseif unit == "h" or unit == "hr" or unit == "hrs" or unit == "hour" or unit == "hours" or unit == "hora" or unit == "horas" then
    return math.max(0, math.floor(amount * 3600000))
  end

  return nil
end

local formatManualCooldown = function(value)
  local cooldown = tonumber(value) or 0
  if cooldown <= 0 then return "" end
  if cooldown % 3600000 == 0 then
    return tostring(cooldown / 3600000) .. "h"
  elseif cooldown % 60000 == 0 then
    return tostring(cooldown / 60000) .. "m"
  elseif cooldown % 1000 == 0 then
    return tostring(cooldown / 1000) .. "s"
  end
  return tostring(cooldown) .. "ms"
end

local cooldownSummary = function(entry)
  local text = formatManualCooldown(entry.cooldown)
  return text ~= "" and " cd:" .. text or ""
end

local manualCooldownKey = function(kind, entry)
  if kind == "spell" then
    return tostring(entry.spell or ""):lower()
  elseif kind == "item" then
    return tostring(entry.item or 0) .. ":" .. tostring(entry.subType or 0)
  end
  return ""
end

local isManualCooldownReady = function(kind, entry)
  local cooldown = tonumber(entry.cooldown) or 0
  if cooldown <= 0 then return true end

  if type(manualCooldownStore[kind]) ~= "table" then manualCooldownStore[kind] = {} end
  local key = manualCooldownKey(kind, entry)
  if key == "" then return true end

  local readyAt = tonumber(manualCooldownStore[kind][key])
  if not readyAt or os.time() >= readyAt then
    manualCooldownStore[kind][key] = nil
    return true
  end

  return false
end

local startManualCooldown = function(kind, entry)
  local cooldown = tonumber(entry.cooldown) or 0
  if cooldown <= 0 then return end

  if type(manualCooldownStore[kind]) ~= "table" then manualCooldownStore[kind] = {} end
  local key = manualCooldownKey(kind, entry)
  if key == "" then return end

  manualCooldownStore[kind][key] = os.time() + math.max(1, math.ceil(cooldown / 1000))
end

local pendingItemCooldownChecks = {}
local ITEM_COOLDOWN_CONFIRM_TIMEOUT = 1200
local ITEM_COOLDOWN_CONFIRM_INTERVAL = 100

local registerHealItemCounter = function(itemId)
  itemId = tonumber(itemId)
  if not itemId or itemId <= 100 then return end

  if vBot.ItemCounter and vBot.ItemCounter.registerItemId then
    vBot.ItemCounter.registerItemId(itemId)
  end
end

local getHealItemCounterSnapshot = function(itemId)
  itemId = tonumber(itemId)
  local visible = 0
  local known = nil
  local amount = 0

  if itemId and itemId > 100 then
    if visibleItemAmount then
      visible = tonumber(visibleItemAmount(itemId)) or 0
    end
    if vBot.ItemCounter and vBot.ItemCounter.get then
      known = tonumber(vBot.ItemCounter.get(itemId))
    end
    if itemAmount then
      amount = tonumber(itemAmount(itemId)) or 0
    else
      amount = math.max(visible, known or 0)
    end
  end

  return {
    visible = visible,
    known = known,
    amount = amount
  }
end

local didHealItemCounterDecrease = function(before, after)
  if before.known and after.known and after.known < before.known then return true end
  if before.visible > 0 and after.visible < before.visible then return true end
  if before.amount > 0 and after.amount < before.amount then return true end
  if before.amount <= 0 and after.known and after.known > 0 then return true end
  return false
end

local isItemCooldownConfirmationPending = function(entry)
  local key = manualCooldownKey("item", entry)
  if key == "" then return false end

  local deadline = pendingItemCooldownChecks[key]
  if not deadline then return false end
  if now <= deadline then return true end

  pendingItemCooldownChecks[key] = nil
  return false
end

local confirmManualItemCooldown = function(entry, beforeSnapshot)
  local cooldown = tonumber(entry.cooldown) or 0
  if cooldown <= 0 then return end

  local key = manualCooldownKey("item", entry)
  local itemId = tonumber(entry.item)
  if key == "" or not itemId or itemId <= 100 then return end

  local deadline = now + ITEM_COOLDOWN_CONFIRM_TIMEOUT
  pendingItemCooldownChecks[key] = deadline

  local function checkCounter()
    if pendingItemCooldownChecks[key] ~= deadline then return end

    local afterSnapshot = getHealItemCounterSnapshot(itemId)
    if didHealItemCounterDecrease(beforeSnapshot, afterSnapshot) then
      pendingItemCooldownChecks[key] = nil
      startManualCooldown("item", entry)
      standByItems = false
      return
    end

    if now < deadline then
      schedule(ITEM_COOLDOWN_CONFIRM_INTERVAL, checkCounter)
      return
    end

    pendingItemCooldownChecks[key] = nil
    standByItems = false
  end

  schedule(ITEM_COOLDOWN_CONFIRM_INTERVAL, checkCounter)
end

local readAdvancedConditions = function(panel, prefix)
  local advanced = panel[prefix .. "Advanced"] and panel[prefix .. "Advanced"]:isChecked()
  local extraText = panel[prefix .. "ExtraValue"] and panel[prefix .. "ExtraValue"]:getText():trim() or ""
  local extraEnabled = advanced and extraText:len() > 0
  local extraValue = nil

  if extraEnabled then
    extraValue = tonumber(extraText)
    if not extraValue then
      warn("HealBot: incorrect extra condition value!")
      return nil
    end
  end

  if advanced and not extraEnabled then
    warn("HealBot: set an extra condition or turn Advanced off.")
    return nil
  end

  return {
    extraEnabled = extraEnabled or false,
    extraOrigin = extraEnabled and sourceFromOption(panel[prefix .. "ExtraSource"]:getCurrentOption().text) or nil,
    extraSign = extraEnabled and signFromOption(panel[prefix .. "ExtraCondition"]:getCurrentOption().text) or nil,
    extraRelation = extraEnabled and relationFromWidget(panel[prefix .. "ExtraRelation"]) or "and",
    extraValue = extraValue
  }
end

local castHealSpell = function(words)
  say(words)
  standBySpells = false
  standByItems = false
end

local safeUseCall = function(fn, ...)
  if type(fn) ~= "function" then return false end
  local ok, result = pcall(fn, ...)
  return ok and result ~= false
end

local useHealItem = function(item, subType)
  local used = false

  if type(item) == "number" then
    if g_game.useInventoryItemWith and safeUseCall(g_game.useInventoryItemWith, item, player, subType or 0) then
      used = true
    elseif modules and modules.game_hotkeys and modules.game_hotkeys.useHotkeyItemWith and safeUseCall(modules.game_hotkeys.useHotkeyItemWith, item, player, subType or 0) then
      used = true
    elseif useWith and safeUseCall(useWith, item, player, subType or 0) then
      used = true
    elseif g_game.useInventoryItem and safeUseCall(g_game.useInventoryItem, item) then
      used = true
    end
  elseif item and useWith and safeUseCall(useWith, item, player, subType) then
    used = true
  end

  standByItems = false
  standBySpells = false
  return used
end

ui.title:setOn(currentSettings.enabled)
ui.title.onClick = function(widget)
  currentSettings.enabled = not currentSettings.enabled
  widget:setOn(currentSettings.enabled)
  vBotConfigSave("heal")
end

ui.settings.onClick = function(widget)
  healWindow:show()
  healWindow:raise()
  healWindow:focus()
end

local importHealBotStyle = function()
  local ok = pcall(function()
    local configName = modules.game_bot.contentsPanel.config:getCurrentOption().text
    local stylePath = "/bot/" .. configName .. "/vBot/HealBot.otui"
    g_ui.importStyle(stylePath)
    if g_resources and g_resources.readFileContents and g_ui.loadUIFromString then
      local styleContents = g_resources.readFileContents(stylePath)
      if styleContents and styleContents:len() > 0 then
        pcall(function() g_ui.loadUIFromString(styleContents) end)
      end
    end
  end)
  if not ok then
    warn("HealBot: could not import HealBot.otui")
  end
end

rootWidget = g_ui.getRootWidget()
if rootWidget then
  importHealBotStyle()
  healWindow = UI.createWindow('HealWindowV3', rootWidget)
  healWindow:hide()
  
  -- Modificación de Título Principal
  healWindow:setText('Advanced HealBot Config - By:Sabuezo')
  
  -- Inyección de tooltips mejorada
  healWindow.healer.spells.spellFormula:setTooltip('Spell Words (Ej: exura med ico)')
  healWindow.healer.spells.manaCost:setTooltip('Mana minimo requerido. 0 desactiva este filtro.')
  healWindow.healer.spells.spellValue:setTooltip('Poner valor de disparo (Ej: 80)')
  healWindow.healer.spells.spellExtraValue:setTooltip('Valor de disparo extra')
  healWindow.healer.spells.spellCooldown:setTooltip('Cooldown manual opcional: 3m, 30s, 180000ms')

  healWindow.healer.items.itemValue:setTooltip('Poner valor de disparo (Ej: 80)')
  healWindow.healer.items.itemId:setTooltip('Arrastra y suelta el item aquí (Ej: Poción)')
  healWindow.healer.items.itemExtraValue:setTooltip('Valor de disparo extra')
  healWindow.healer.items.itemCooldown:setTooltip('Cooldown manual opcional: 3m, 30s, 180000ms')

  local setTip = function(widget, text)
    if widget and widget.setTooltip then widget:setTooltip(text) end
  end
  setTip(healWindow.healer.spells.spellSource, 'Stat to check (e.g. Health Percent)')
  setTip(healWindow.healer.spells.spellCondition, 'Condition (e.g. Below)')
  setTip(healWindow.healer.spells.spellValue, 'Trigger value (e.g. 80)')
  setTip(healWindow.healer.spells.spellFormula, 'Spell words (e.g. exura med ico)')
  setTip(healWindow.healer.spells.manaCost, 'Mana minimo requerido para lanzar. Usa 0 para desactivar este filtro.')
  setTip(healWindow.healer.spells.spellCooldown, 'Manual cooldown. Empty or 0 disables it. Use 3m, 30s, 1h, or 180000ms.')
  setTip(healWindow.healer.spells.spellAdvanced, 'Enable a second condition')
  setTip(healWindow.healer.spells.spellExtraRelation, 'How to combine both conditions: and / or')
  setTip(healWindow.healer.spells.spellExtraSource, 'Second stat to check')
  setTip(healWindow.healer.spells.spellExtraCondition, 'Second condition')
  setTip(healWindow.healer.spells.spellExtraValue, 'Second trigger value (e.g. 40)')

  setTip(healWindow.healer.items.itemSource, 'Stat to check before using the item')
  setTip(healWindow.healer.items.itemCondition, 'Condition (e.g. Below)')
  setTip(healWindow.healer.items.itemValue, 'Trigger value (e.g. 80)')
  setTip(healWindow.healer.items.itemId, 'Drag the item here (e.g. health potion)')
  setTip(healWindow.healer.items.itemCooldown, 'Manual cooldown. Empty or 0 disables it. Use 3m, 30s, 1h, or 180000ms.')
  setTip(healWindow.healer.items.itemAdvanced, 'Enable a second condition')
  setTip(healWindow.healer.items.itemExtraRelation, 'How to combine both conditions: and / or')
  setTip(healWindow.healer.items.itemExtraSource, 'Second stat to check')
  setTip(healWindow.healer.items.itemExtraCondition, 'Second condition')
  setTip(healWindow.healer.items.itemExtraValue, 'Second trigger value (e.g. 40)')

  healWindow.onVisibilityChange = function(widget, visible)
    if not visible then
      vBotConfigSave("heal")
      healWindow.healer:show()
      healWindow.settings:hide()
      healWindow.settingsButton:setText("Settings")
    end
  end

  healWindow.settingsButton.onClick = function(widget)
    if healWindow.healer:isVisible() then
      healWindow.healer:hide()
      healWindow.settings:show()
      widget:setText("Back")
    else
      healWindow.healer:show()
      healWindow.settings:hide()
      widget:setText("Settings")
    end
  end

  local setProfileName = function()
    ui.name:setText(currentSettings.name)
  end
  healWindow.settings.profiles.Name.onTextChange = function(widget, text)
    currentSettings.name = text
    setProfileName()
  end
  healWindow.settings.list.Visible.onClick = function(widget)
    currentSettings.Visible = not currentSettings.Visible
    healWindow.settings.list.Visible:setChecked(currentSettings.Visible)
  end
  healWindow.settings.list.OldSchool.onClick = function(widget)
    currentSettings.OldSchool = not currentSettings.OldSchool
    healWindow.settings.list.OldSchool:setChecked(currentSettings.OldSchool)
  end
  healWindow.settings.list.Cooldown.onClick = function(widget)
    currentSettings.Cooldown = not currentSettings.Cooldown
    healWindow.settings.list.Cooldown:setChecked(currentSettings.Cooldown)
  end
  healWindow.settings.list.Interval.onClick = function(widget)
    currentSettings.Interval = not currentSettings.Interval
    healWindow.settings.list.Interval:setChecked(currentSettings.Interval)
  end
  healWindow.settings.list.Conditions.onClick = function(widget)
    currentSettings.Conditions = not currentSettings.Conditions
    healWindow.settings.list.Conditions:setChecked(currentSettings.Conditions)
  end
  healWindow.settings.list.Delay.onClick = function(widget)
    currentSettings.Delay = not currentSettings.Delay
    healWindow.settings.list.Delay:setChecked(currentSettings.Delay)
  end
  healWindow.settings.list.MessageDelay.onClick = function(widget)
    currentSettings.MessageDelay = not currentSettings.MessageDelay
    healWindow.settings.list.MessageDelay:setChecked(currentSettings.MessageDelay)
  end

  local editingSpellEntry = nil
  local editingItemEntry = nil

  local setComboOption = function(widget, option)
    if widget and widget.setOption then
      widget:setOption(option)
    end
  end

  local resetSpellEditor = function(clear)
    editingSpellEntry = nil
    healWindow.healer.spells.addSpell:setText("Add")
    if clear then
      healWindow.healer.spells.spellFormula:setText('')
      healWindow.healer.spells.spellValue:setText('')
      healWindow.healer.spells.manaCost:setText('0')
      healWindow.healer.spells.spellCooldown:setText('')
      healWindow.healer.spells.spellAdvanced:setChecked(false)
      setComboOption(healWindow.healer.spells.spellExtraRelation, "and")
      healWindow.healer.spells.spellExtraValue:setText('')
    end
  end

  local resetItemEditor = function(clear)
    editingItemEntry = nil
    healWindow.healer.items.addItem:setText("Add")
    if clear then
      healWindow.healer.items.itemId:setItemId(0)
      healWindow.healer.items.itemValue:setText('')
      healWindow.healer.items.itemCooldown:setText('')
      healWindow.healer.items.itemAdvanced:setChecked(false)
      setComboOption(healWindow.healer.items.itemExtraRelation, "and")
      healWindow.healer.items.itemExtraValue:setText('')
    end
  end

  local loadAdvancedEditor = function(panel, prefix, entry)
    local hasExtra = entry.extraEnabled and true or false
    panel[prefix .. "Advanced"]:setChecked(hasExtra)
    setComboOption(panel[prefix .. "ExtraRelation"], normalizeRelation(entry.extraRelation))
    setComboOption(panel[prefix .. "ExtraSource"], optionFromSource(entry.extraOrigin or "MP%"))
    setComboOption(panel[prefix .. "ExtraCondition"], optionFromSign(entry.extraSign or "<"))
    panel[prefix .. "ExtraValue"]:setText(hasExtra and tostring(entry.extraValue or "") or "")
  end

  local applyEntryData = function(entry, data)
    for key in pairs(entry) do
      entry[key] = nil
    end
    for key, value in pairs(data) do
      entry[key] = value
    end
  end

  local editSpellEntry = function(entry)
    editingSpellEntry = entry
    resetItemEditor(false)
    healWindow.healer.spells.addSpell:setText("Save")
    setComboOption(healWindow.healer.spells.spellSource, optionFromSource(entry.origin))
    setComboOption(healWindow.healer.spells.spellCondition, optionFromSign(entry.sign))
    healWindow.healer.spells.spellValue:setText(tostring(entry.value or ""))
    healWindow.healer.spells.spellFormula:setText(entry.spell or "")
    healWindow.healer.spells.manaCost:setText(tostring(normalizeManaCost(entry.cost)))
    healWindow.healer.spells.spellCooldown:setText(formatManualCooldown(entry.cooldown))
    loadAdvancedEditor(healWindow.healer.spells, "spell", entry)
  end

  local editItemEntry = function(entry)
    editingItemEntry = entry
    resetSpellEditor(false)
    healWindow.healer.items.addItem:setText("Save")
    setComboOption(healWindow.healer.items.itemSource, optionFromSource(entry.origin))
    setComboOption(healWindow.healer.items.itemCondition, optionFromSign(entry.sign))
    healWindow.healer.items.itemValue:setText(tostring(entry.value or ""))
    healWindow.healer.items.itemId:setItemId(entry.item or 0)
    healWindow.healer.items.itemCooldown:setText(formatManualCooldown(entry.cooldown))
    loadAdvancedEditor(healWindow.healer.items, "item", entry)
  end

  local refreshSpells = function()
    if currentSettings.spellTable then
      healWindow.healer.spells.spellList:destroyChildren()
      for _, entry in pairs(currentSettings.spellTable) do
        local label = UI.createWidget("SpellEntry", healWindow.healer.spells.spellList)
        label.enabled:setChecked(entry.enabled)
        label.enabled.onClick = function(widget)
          standBySpells = false
          standByItems = false
          entry.enabled = not entry.enabled
          label.enabled:setChecked(entry.enabled)
        end
        label.remove.onClick = function(widget)
          standBySpells = false
          standByItems = false
          if editingSpellEntry == entry then
            resetSpellEditor(true)
          end
          table.removevalue(currentSettings.spellTable, entry)
          reindexTable(currentSettings.spellTable)
          label:destroy()
        end
        label.onDoubleClick = function(widget)
          standBySpells = false
          standByItems = false
          editSpellEntry(entry)
        end
        label:setText("(MP>=" .. normalizeManaCost(entry.cost) .. ") " .. entry.origin .. entry.sign .. entry.value .. extraSummary(entry) .. cooldownSummary(entry) .. ": " .. entry.spell)
      end
    end
  end
  refreshSpells()

  local refreshItems = function()
    if currentSettings.itemTable then
      healWindow.healer.items.itemList:destroyChildren()
      for _, entry in pairs(currentSettings.itemTable) do
        local label = UI.createWidget("ItemEntry", healWindow.healer.items.itemList)
        label.enabled:setChecked(entry.enabled)
        label.enabled.onClick = function(widget)
          standBySpells = false
          standByItems = false
          entry.enabled = not entry.enabled
          label.enabled:setChecked(entry.enabled)
        end
        label.remove.onClick = function(widget)
          standBySpells = false
          standByItems = false
          if editingItemEntry == entry then
            resetItemEditor(true)
          end
          table.removevalue(currentSettings.itemTable, entry)
          reindexTable(currentSettings.itemTable)
          label:destroy()
        end
        label.onDoubleClick = function(widget)
          standBySpells = false
          standByItems = false
          editItemEntry(entry)
        end
        label.id:setItemId(entry.item)
        label.id:setItemSubType(entry.subType)
        label:setText(entry.origin .. entry.sign .. entry.value .. extraSummary(entry) .. cooldownSummary(entry) .. ": " .. entry.item)
      end
    end
  end
  refreshItems()

  healWindow.healer.spells.MoveUp.onClick = function(widget)
    local input = healWindow.healer.spells.spellList:getFocusedChild()
    if not input then return end
    local index = healWindow.healer.spells.spellList:getChildIndex(input)
    if index < 2 then return end

    local t = currentSettings.spellTable

    t[index],t[index-1] = t[index-1], t[index]
    healWindow.healer.spells.spellList:moveChildToIndex(input, index - 1)
    healWindow.healer.spells.spellList:ensureChildVisible(input)
  end

  healWindow.healer.spells.MoveDown.onClick = function(widget)
    local input = healWindow.healer.spells.spellList:getFocusedChild()
    if not input then return end
    local index = healWindow.healer.spells.spellList:getChildIndex(input)
    if index >= healWindow.healer.spells.spellList:getChildCount() then return end

    local t = currentSettings.spellTable

    t[index],t[index+1] = t[index+1],t[index]
    healWindow.healer.spells.spellList:moveChildToIndex(input, index + 1)
    healWindow.healer.spells.spellList:ensureChildVisible(input)
  end

  healWindow.healer.items.MoveUp.onClick = function(widget)
    local input = healWindow.healer.items.itemList:getFocusedChild()
    if not input then return end
    local index = healWindow.healer.items.itemList:getChildIndex(input)
    if index < 2 then return end

    local t = currentSettings.itemTable

    t[index],t[index-1] = t[index-1], t[index]
    healWindow.healer.items.itemList:moveChildToIndex(input, index - 1)
    healWindow.healer.items.itemList:ensureChildVisible(input)
  end

  healWindow.healer.items.MoveDown.onClick = function(widget)
    local input = healWindow.healer.items.itemList:getFocusedChild()
    if not input then return end
    local index = healWindow.healer.items.itemList:getChildIndex(input)
    if index >= healWindow.healer.items.itemList:getChildCount() then return end

    local t = currentSettings.itemTable

    t[index],t[index+1] = t[index+1],t[index]
    healWindow.healer.items.itemList:moveChildToIndex(input, index + 1)
    healWindow.healer.items.itemList:ensureChildVisible(input)
  end

  healWindow.healer.spells.addSpell.onClick = function(widget)
  
    local spellFormula = healWindow.healer.spells.spellFormula:getText():trim()
    local manaCost = normalizeManaCost(healWindow.healer.spells.manaCost:getText())
    local spellTrigger = tonumber(healWindow.healer.spells.spellValue:getText())
    local spellCooldown = parseManualCooldown(healWindow.healer.spells.spellCooldown:getText())
    local spellSource = healWindow.healer.spells.spellSource:getCurrentOption().text
    local spellEquasion = healWindow.healer.spells.spellCondition:getCurrentOption().text
    local source
    local equasion

    if not spellTrigger then  
      warn("HealBot: incorrect condition value!") 
      healWindow.healer.spells.spellFormula:setText('')
      healWindow.healer.spells.spellValue:setText('')
      healWindow.healer.spells.manaCost:setText('0')
      return 
    end
    if not spellCooldown then
      warn("HealBot: incorrect spell cooldown value!")
      healWindow.healer.spells.spellCooldown:setText('')
      return
    end

    source = sourceFromOption(spellSource)
    equasion = signFromOption(spellEquasion)

    local advanced = readAdvancedConditions(healWindow.healer.spells, "spell")
    if not advanced then return end

    if spellFormula:len() > 0 then
      local entryEnabled = true
      if editingSpellEntry and editingSpellEntry.enabled ~= nil then
        entryEnabled = editingSpellEntry.enabled
      end
      local data = {index = editingSpellEntry and editingSpellEntry.index or #currentSettings.spellTable+1, spell = spellFormula, sign = equasion, origin = source, cost = manaCost, value = spellTrigger, enabled = entryEnabled, cooldown = spellCooldown, extraEnabled = advanced.extraEnabled, extraOrigin = advanced.extraOrigin, extraSign = advanced.extraSign, extraRelation = advanced.extraRelation, extraValue = advanced.extraValue}
      if editingSpellEntry then
        applyEntryData(editingSpellEntry, data)
      else
        table.insert(currentSettings.spellTable, data)
      end
      resetSpellEditor(true)
    end
    standBySpells = false
    standByItems = false
    refreshSpells()
  end

  healWindow.healer.items.addItem.onClick = function(widget)
  
    local id = healWindow.healer.items.itemId:getItemId()
    local thing = g_things.getThingType(id)
    local subType = g_game.getClientVersion() >= 860 and 0 or 1
    if thing and thing:isFluidContainer() then
      subType = healWindow.healer.items.itemId:getItem():getSubType()
    end
    local trigger = tonumber(healWindow.healer.items.itemValue:getText())
    local itemCooldown = parseManualCooldown(healWindow.healer.items.itemCooldown:getText())
    local src = healWindow.healer.items.itemSource:getCurrentOption().text
    local eq = healWindow.healer.items.itemCondition:getCurrentOption().text
    local source
    local equasion

    if not trigger then
      warn("HealBot: incorrect trigger value!")
      healWindow.healer.items.itemId:setItemId(0)
      healWindow.healer.items.itemValue:setText('')
      return
    end
    if not itemCooldown then
      warn("HealBot: incorrect item cooldown value!")
      healWindow.healer.items.itemCooldown:setText('')
      return
    end

    source = sourceFromOption(src)
    equasion = signFromOption(eq)

    local advanced = readAdvancedConditions(healWindow.healer.items, "item")
    if not advanced then return end

    if id > 100 then
      local entryEnabled = true
      if editingItemEntry and editingItemEntry.enabled ~= nil then
        entryEnabled = editingItemEntry.enabled
      end
      local data = {index = editingItemEntry and editingItemEntry.index or #currentSettings.itemTable+1,item = id, sign = equasion, origin = source, value = trigger, enabled = entryEnabled, subType = subType, cooldown = itemCooldown, extraEnabled = advanced.extraEnabled, extraOrigin = advanced.extraOrigin, extraSign = advanced.extraSign, extraRelation = advanced.extraRelation, extraValue = advanced.extraValue}
      if editingItemEntry then
        applyEntryData(editingItemEntry, data)
      else
        table.insert(currentSettings.itemTable, data)
      end
      standBySpells = false
      standByItems = false
      refreshItems()
      resetItemEditor(true)
    end
  end

  healWindow.closeButton.onClick = function(widget)
    healWindow:hide()
  end

  local loadSettings = function()
    ui.title:setOn(currentSettings.enabled)
    setProfileName()
    resetSpellEditor(true)
    resetItemEditor(true)
    healWindow.settings.profiles.Name:setText(currentSettings.name)
    refreshSpells()
    refreshItems()
    healWindow.settings.list.Visible:setChecked(currentSettings.Visible)
    healWindow.settings.list.OldSchool:setChecked(currentSettings.OldSchool)
    healWindow.settings.list.Cooldown:setChecked(currentSettings.Cooldown)
    healWindow.settings.list.Delay:setChecked(currentSettings.Delay)
    healWindow.settings.list.MessageDelay:setChecked(currentSettings.MessageDelay)
    healWindow.settings.list.Interval:setChecked(currentSettings.Interval)
    healWindow.settings.list.Conditions:setChecked(currentSettings.Conditions)
  end
  loadSettings()

  local profileChange = function()
    setActiveProfile()
    activeProfileColor()
    loadSettings()
    vBotConfigSave("heal")
  end

  local resetSettings = function()
    currentSettings.enabled = false
    currentSettings.spellTable = {}
    currentSettings.itemTable = {}
    currentSettings.Visible = true
    currentSettings.OldSchool = false
    currentSettings.Cooldown = true
    currentSettings.Delay = true
    currentSettings.MessageDelay = false
    currentSettings.Interval = true
    currentSettings.Conditions = true
    currentSettings.name = "Profile #" .. HealBotConfig.currentHealBotProfile
  end

  -- profile buttons
  for i=1,5 do
    local button = ui[i]
      button.onClick = function()
      HealBotConfig.currentHealBotProfile = i
      profileChange()
    end
  end

  healWindow.settings.profiles.ResetSettings.onClick = function()
    resetSettings()
    loadSettings()
  end


  -- public functions
  HealBot = {} -- global table

  HealBot.isOn = function()
    return currentSettings.enabled
  end

  HealBot.isOff = function()
    return not currentSettings.enabled
  end

  HealBot.setOff = function()
    currentSettings.enabled = false
    ui.title:setOn(currentSettings.enabled)
    vBotConfigSave("heal")
  end

  HealBot.setOn = function()
    currentSettings.enabled = true
    ui.title:setOn(currentSettings.enabled)
    vBotConfigSave("heal")
  end

  HealBot.setOffSilent = function()
    currentSettings.enabled = false
    ui.title:setOn(currentSettings.enabled)
  end

  HealBot.setOnSilent = function()
    currentSettings.enabled = true
    ui.title:setOn(currentSettings.enabled)
  end

  HealBot.getActiveProfile = function()
    return HealBotConfig.currentHealBotProfile -- returns number 1-5
  end

  HealBot.setActiveProfile = function(n)
    if not n or not tonumber(n) or n < 1 or n > 5 then
      return error("[HealBot] wrong profile parameter! should be 1 to 5 is " .. n)
    else
      HealBotConfig.currentHealBotProfile = n
      profileChange()
    end
  end

  HealBot.show = function()
    healWindow:show()
    healWindow:raise()
    healWindow:focus()
  end
end

-- spells
macro(100, function()
  if standBySpells then return end
  if not currentSettings.enabled then return end
  local somethingIsOnCooldown = false

  for _, entry in pairs(currentSettings.spellTable) do
    if entry.enabled and currentManaAmount() >= normalizeManaCost(entry.cost) and entryConditionsPass(entry) then
      if not isManualCooldownReady("spell", entry) then
        somethingIsOnCooldown = true
      elseif canCast(entry.spell, not currentSettings.Conditions, not currentSettings.Cooldown) then
        castHealSpell(entry.spell)
        startManualCooldown("spell", entry)
        return
      else
        somethingIsOnCooldown = true
      end
    end
  end
  if not somethingIsOnCooldown then
    standBySpells = true 
  end
end)

-- items
macro(100, function()
  if standByItems then return end
  if not currentSettings.enabled or #currentSettings.itemTable == 0 then return end
  if vBot.pauseHealItemsUntil and now < vBot.pauseHealItemsUntil then return end
  if currentSettings.Delay and vBot.isUsing then return end
  if currentSettings.MessageDelay and vBot.isUsingPotion then return end
  local somethingIsOnCooldown = false

  if not currentSettings.MessageDelay then
    delay(400)
  end

  if TargetBot.isOn() and TargetBot.Looting.getStatus():len() > 0 and currentSettings.Interval then
    if not currentSettings.MessageDelay then
      delay(700)
    else
      delay(200)
    end
  end

  for _, entry in pairs(currentSettings.itemTable) do
    local item = findItem(entry.item)
    local visibleRequired = currentSettings.Visible or currentSettings.OldSchool
    if (not visibleRequired or item) and entry.enabled then
      local useItem = visibleRequired and item or entry.item
      if entryConditionsPass(entry) then
        registerHealItemCounter(entry.item)
        if not isManualCooldownReady("item", entry) then
          somethingIsOnCooldown = true
        elseif isItemCooldownConfirmationPending(entry) then
          somethingIsOnCooldown = true
        else
          local beforeSnapshot = getHealItemCounterSnapshot(entry.item)
          if useHealItem(useItem, entry.subType) then
            confirmManualItemCooldown(entry, beforeSnapshot)
            return
          end
        end
      end
    end
  end
  if not somethingIsOnCooldown then
    standByItems = true
  end
end)
UI.Separator()

onPlayerHealthChange(function(healthPercent)
  standByItems = false
  standBySpells = false
end)

onManaChange(function(player, mana, maxMana, oldMana, oldMaxMana)
  standByItems = false
  standBySpells = false
end)
