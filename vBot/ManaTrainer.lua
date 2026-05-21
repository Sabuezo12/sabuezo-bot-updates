setDefaultTab("hp")

local panelName = "manaTrainer"
storage[panelName] = storage[panelName] or {}
local config = storage[panelName]

if config.enabled == nil then config.enabled = false end
if type(config.creatures) ~= "string" or config.creatures:len() == 0 then config.creatures = "Treiner" end
config.castDelay = tonumber(config.castDelay) or 1500
if config.pauseAttackBot == nil then config.pauseAttackBot = true end

local ui = setupUI([[
Panel
  height: 38

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('Mana Trainer')

  Button
    id: settings
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 17
    text: Setup

  Label
    id: status
    anchors.top: title.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 4
    height: 17
    text-align: center
    font: verdana-11px-rounded
    background: #292A2A
]])
ui:setId(panelName)

local creatureList = {}
local spellRules = {}
local rowStates = {}
local nextSpellIndex = 1
local lastCast = 0

storage._manaTrainerAttackBotPause = storage._manaTrainerAttackBotPause or {}
local attackBotPause = storage._manaTrainerAttackBotPause

local function trim(text)
  text = tostring(text or "")
  return text:match("^%s*(.-)%s*$") or ""
end

local function clamp(value, minValue, maxValue, defaultValue)
  value = tonumber(value) or defaultValue
  if value < minValue then return minValue end
  if value > maxValue then return maxValue end
  return value
end

local function makeRule(spell, mana, enabled)
  return {
    enabled = enabled ~= false,
    spell = trim(spell),
    mana = clamp(mana, 1, 100, 90)
  }
end

local function parseLegacyRules(text)
  local rules = {}
  for line in tostring(text or ""):gmatch("[^\n]+") do
    line = trim(line:gsub("%-%-.*$", ""))
    if line:len() > 0 then
      local spell, mana = line:match("^(.-)%s*[%|,;:]%s*(%d+)%s*%%?$")
      if not spell then
        spell = line
        mana = 90
      end
      spell = trim(spell)
      if spell:len() > 0 then
        table.insert(rules, makeRule(spell, mana, true))
      end
    end
  end
  return rules
end

local function normalizeRules()
  if type(config.rules) ~= "table" then
    config.rules = {}
  end

  if #config.rules == 0 and type(config.spells) == "string" and config.spells:len() > 0 then
    config.rules = parseLegacyRules(config.spells)
  end

  if #config.rules == 0 then
    table.insert(config.rules, makeRule("exura", 90, true))
  end

  for index, rule in ipairs(config.rules) do
    if type(rule) ~= "table" then
      config.rules[index] = makeRule(tostring(rule), 90, true)
    else
      rule.enabled = rule.enabled ~= false
      rule.spell = trim(rule.spell or rule.words or "")
      rule.mana = clamp(rule.mana or rule.percent, 1, 100, 90)
    end
  end
end

local function parseCreatures()
  creatureList = {}
  for entry in tostring(config.creatures or ""):gmatch("[^,;\n]+") do
    entry = trim(entry):lower()
    if entry:len() > 0 then
      table.insert(creatureList, entry)
    end
  end
end

local function refreshParsed()
  config.castDelay = clamp(config.castDelay, 250, 60000, 1500)
  config.pauseAttackBot = config.pauseAttackBot == true
  normalizeRules()
  parseCreatures()

  spellRules = {}
  for _, rule in ipairs(config.rules) do
    if rule.enabled and rule.spell and rule.spell:len() > 0 then
      table.insert(spellRules, rule)
    end
  end

  if nextSpellIndex > math.max(#spellRules, 1) then
    nextSpellIndex = 1
  end
end

local function nameMatches(wanted, creatureName)
  if wanted == "*" then return true end

  if wanted:sub(1, 1) == "*" and wanted:sub(-1) == "*" then
    local needle = wanted:sub(2, -2)
    return needle:len() > 0 and creatureName:find(needle, 1, true) ~= nil
  elseif wanted:sub(1, 1) == "*" then
    local needle = wanted:sub(2)
    return needle:len() > 0 and creatureName:sub(-needle:len()) == needle
  elseif wanted:sub(-1) == "*" then
    local needle = wanted:sub(1, -2)
    return needle:len() > 0 and creatureName:sub(1, needle:len()) == needle
  end

  return creatureName == wanted
end

local function getCurrentTarget()
  if g_game and g_game.getAttackingCreature then
    local ok, creature = pcall(function() return g_game.getAttackingCreature() end)
    if ok and creature then return creature end
  end

  if type(target) == "function" then
    local ok, creature = pcall(target)
    if ok and creature then return creature end
  end
end

local function getManaPercent()
  if type(manapercent) == "function" then
    return manapercent()
  end

  local maxMana = player and player:getMaxMana() or 0
  if maxMana <= 0 then return 0 end
  return math.floor((player:getMana() * 100) / maxMana)
end

local function targetMatches(creature)
  if not creature then return false end
  if creature == player then return false end

  local name = creature:getName()
  if type(name) ~= "string" then return false end
  name = name:lower()

  for _, wanted in ipairs(creatureList) do
    if nameMatches(wanted, name) then
      return true
    end
  end

  return false
end

local function setAttackBotPaused(paused)
  paused = paused == true and config.pauseAttackBot == true

  if not AttackBot then
    attackBotPause.active = false
    attackBotPause.wasOn = nil
    return
  end

  if paused then
    if not attackBotPause.active then
      attackBotPause.wasOn = AttackBot.isOn and AttackBot.isOn() or false
    end

    attackBotPause.active = true
    if AttackBot.setPause then
      AttackBot.setPause("manaTrainer", true)
    elseif AttackBot.setOff then
      AttackBot.setOff()
    end
    return
  end

  if attackBotPause.active then
    if AttackBot.setPause then
      AttackBot.setPause("manaTrainer", false)
    elseif attackBotPause.wasOn and AttackBot.setOn then
      AttackBot.setOn()
    end

    attackBotPause.active = false
    attackBotPause.wasOn = nil
  end
end

setAttackBotPaused(false)

local function updateStatus(text, color)
  refreshParsed()

  if not text then
    if #creatureList == 0 then
      text = "No creatures"
      color = "#ff8a8a"
    elseif config.enabled then
      text = #creatureList .. " target(s), " .. #spellRules .. " active spell(s)"
      color = "#8cff9a"
    else
      text = #creatureList .. " target(s), " .. #spellRules .. " active spell(s)"
      color = "#cfd3d7"
    end
  end

  ui.status:setText(text)
  ui.status:setColor(color or "#cfd3d7")
end

local rootWidget = g_ui.getRootWidget()
local window = UI.createWindow("ManaTrainerWindow", rootWidget)
window:hide()

local refreshRows

local function updateSummary()
  refreshParsed()
  window.summary:setText(#spellRules .. "/" .. #config.rules .. " active")
end

local function bindRow(row, rule, index)
  rowStates[index] = row

  row.enabled:setChecked(rule.enabled)
  row.enabled.onClick = function(widget)
    rule.enabled = not rule.enabled
    widget:setChecked(rule.enabled)
    refreshParsed()
    updateSummary()
    updateStatus()
  end

  row.spell:setText(rule.spell)
  row.spell.onTextChange = function(widget, text)
    rule.spell = text
    refreshParsed()
    updateSummary()
    updateStatus()
  end

  row.mana:setValue(rule.mana)
  row.mana.onValueChange = function(widget, value)
    rule.mana = clamp(value, 1, 100, 90)
    refreshParsed()
    updateSummary()
    updateStatus()
  end

  row.remove.onClick = function()
    table.remove(config.rules, index)
    refreshRows()
    updateStatus()
  end
end

refreshRows = function()
  normalizeRules()
  window.spellList:destroyChildren()
  rowStates = {}

  for index, rule in ipairs(config.rules) do
    local row = UI.createWidget("ManaTrainerSpellRow", window.spellList)
    bindRow(row, rule, index)
  end

  updateSummary()
end

local function updateWindow()
  refreshParsed()
  window.creatures:setText(config.creatures)
  window.castDelay:setValue(config.castDelay)
  window.pauseAttackBot:setChecked(config.pauseAttackBot)
  refreshRows()
end

ui.title:setOn(config.enabled)
ui.title.onClick = function(widget)
  config.enabled = not config.enabled
  widget:setOn(config.enabled)
  if not config.enabled then
    setAttackBotPaused(false)
  else
    lastCast = 0
  end
  updateStatus()
end

ui.settings.onClick = function()
  updateWindow()
  window:show()
  window:raise()
  window:focus()
end

window.creatures.onTextChange = function(widget, text)
  config.creatures = text
  updateStatus()
end

window.castDelay.onValueChange = function(widget, value)
  config.castDelay = clamp(value, 250, 60000, 1500)
  updateStatus()
end

window.pauseAttackBot.onClick = function(widget)
  config.pauseAttackBot = not config.pauseAttackBot
  widget:setChecked(config.pauseAttackBot)
  if not config.pauseAttackBot then
    setAttackBotPaused(false)
  end
end

window.addSpell.onClick = function()
  normalizeRules()
  table.insert(config.rules, makeRule("", 90, true))
  refreshRows()
end

window.resetTimers.onClick = function()
  lastCast = 0
  nextSpellIndex = 1
  updateStatus("Timer reset", "#9dd1ce")
end

refreshParsed()
updateStatus()

macro(250, function()
  if not config.enabled then
    setAttackBotPaused(false)
    return
  end

  refreshParsed()
  if #creatureList == 0 then
    setAttackBotPaused(false)
    updateStatus("No creatures", "#ff8a8a")
    return
  end

  local creature = getCurrentTarget()
  if not targetMatches(creature) then
    setAttackBotPaused(false)
    updateStatus("Waiting target", "#ffd166")
    return
  end

  setAttackBotPaused(true)

  if #spellRules == 0 then
    updateStatus("No active spells", "#ff8a8a")
    return
  end

  local mana = getManaPercent()
  if now - lastCast < config.castDelay then
    updateStatus("Training: " .. mana .. "%", "#cfd3d7")
    return
  end

  for i = 1, #spellRules do
    local index = ((nextSpellIndex + i - 2) % #spellRules) + 1
    local rule = spellRules[index]

    if mana >= rule.mana then
      say(rule.spell)
      lastCast = now
      nextSpellIndex = (index % #spellRules) + 1
      updateStatus("Casting: " .. rule.spell, "#8cff9a")
      return
    end
  end

  updateStatus("Mana " .. mana .. "%", "#cfd3d7")
end)

UI.Separator()
