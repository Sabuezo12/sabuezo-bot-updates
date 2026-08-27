setDefaultTab("HP")

local panelName = "ConditionPanel"
local ui = setupUI([[
Panel
  height: 19

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('Conditions')

  Button
    id: conditionList
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 17
    text: Setup
]])
ui:setId(panelName)

if type(HealBotConfig[panelName]) ~= "table" then HealBotConfig[panelName] = {} end
local config = HealBotConfig[panelName]

local defaults = {
  enabled = false,
  curePoison = false,
  poisonCost = 20,
  cureCurse = false,
  curseCost = 80,
  cureBleed = false,
  bleedCost = 45,
  cureBurn = false,
  burnCost = 30,
  cureElectrify = false,
  electrifyCost = 22,
  cureParalyse = false,
  paralyseCost = 40,
  paralyseSpell = "utani hur",
  paralyseUseHasteFallback = true,
  significantDamage = 500,
  cureMinHp = 95,
  holdHaste = false,
  hasteCost = 40,
  hasteSpell = "utani hur",
  holdUtamo = false,
  utamoCost = 40,
  holdUtana = false,
  utanaCost = 440,
  holdUtura = false,
  uturaType = "Utura",
  uturaCost = 100,
  ignoreInPz = true,
  stopHaste = false
}

if config.curePoison == nil and config.curePosion ~= nil then
  config.curePoison = config.curePosion == true
end

for key, value in pairs(defaults) do
  if config[key] == nil then config[key] = value end
end

local numericKeys = {
  "poisonCost", "curseCost", "bleedCost", "burnCost", "electrifyCost",
  "paralyseCost", "significantDamage", "cureMinHp", "hasteCost",
  "utamoCost", "utanaCost", "uturaCost"
}
for _, key in ipairs(numericKeys) do
  config[key] = tonumber(config[key]) or defaults[key]
end

config.paralyseSpell = tostring(config.paralyseSpell or defaults.paralyseSpell)
config.hasteSpell = tostring(config.hasteSpell or defaults.hasteSpell)
config.uturaType = tostring(config.uturaType or defaults.uturaType)

local CURE_SAFE_DELAY = 2000
local DAMAGE_WINDOW = 350
local FAST_INTERVAL = 20

local function saveConfig()
  if type(vBotConfigSave) == "function" then vBotConfigSave("heal") end
end

local conditionsWindow
local rootWidget = g_ui.getRootWidget()
if rootWidget then
  local previousWindow = rootWidget:recursiveGetChildById("ConditionsWindow")
  if previousWindow then previousWindow:destroy() end

  conditionsWindow = UI.createWindow("ConditionsWindow", rootWidget)
  conditionsWindow:hide()

  conditionsWindow.onVisibilityChange = function(widget, visible)
    if not visible then saveConfig() end
  end

  local function bindSpin(widget, key)
    widget:setValue(tonumber(config[key]) or defaults[key] or 0)
    widget.onValueChange = function(changedWidget, value)
      config[key] = tonumber(value) or defaults[key] or 0
    end
  end

  local function bindCheck(widget, key)
    widget:setChecked(config[key] == true)
    widget.onClick = function(changedWidget)
      config[key] = not config[key]
      changedWidget:setChecked(config[key])
    end
  end

  local function bindText(widget, key)
    widget:setText(tostring(config[key] or ""))
    widget.onTextChange = function(changedWidget, text)
      config[key] = tostring(text or "")
    end
  end

  bindCheck(conditionsWindow.Anti.CureParalyse, "cureParalyse")
  bindSpin(conditionsWindow.Anti.ParalyseCost, "paralyseCost")
  bindText(conditionsWindow.Anti.ParalyseSpell, "paralyseSpell")
  bindCheck(conditionsWindow.Anti.UseHasteFallback, "paralyseUseHasteFallback")

  bindCheck(conditionsWindow.Cure.CurePoison, "curePoison")
  bindSpin(conditionsWindow.Cure.PoisonCost, "poisonCost")
  bindCheck(conditionsWindow.Cure.CureCurse, "cureCurse")
  bindSpin(conditionsWindow.Cure.CurseCost, "curseCost")
  bindCheck(conditionsWindow.Cure.CureBleed, "cureBleed")
  bindSpin(conditionsWindow.Cure.BleedCost, "bleedCost")
  bindCheck(conditionsWindow.Cure.CureBurn, "cureBurn")
  bindSpin(conditionsWindow.Cure.BurnCost, "burnCost")
  bindCheck(conditionsWindow.Cure.CureElectrify, "cureElectrify")
  bindSpin(conditionsWindow.Cure.ElectrifyCost, "electrifyCost")
  bindSpin(conditionsWindow.Cure.SignificantDamage, "significantDamage")
  bindSpin(conditionsWindow.Cure.CureMinHp, "cureMinHp")

  bindCheck(conditionsWindow.Hold.HoldHaste, "holdHaste")
  bindSpin(conditionsWindow.Hold.HasteCost, "hasteCost")
  bindText(conditionsWindow.Hold.HasteSpell, "hasteSpell")
  bindCheck(conditionsWindow.Hold.HoldUtamo, "holdUtamo")
  bindSpin(conditionsWindow.Hold.UtamoCost, "utamoCost")
  bindCheck(conditionsWindow.Hold.HoldUtana, "holdUtana")
  bindSpin(conditionsWindow.Hold.UtanaCost, "utanaCost")
  bindCheck(conditionsWindow.Hold.HoldUtura, "holdUtura")
  bindSpin(conditionsWindow.Hold.UturaCost, "uturaCost")
  conditionsWindow.Hold.UturaType:setOption(config.uturaType)
  conditionsWindow.Hold.UturaType.onOptionChange = function(widget)
    local option = widget:getCurrentOption()
    config.uturaType = option and option.text or "Utura"
  end
  bindCheck(conditionsWindow.Hold.IgnoreInPz, "ignoreInPz")
  bindCheck(conditionsWindow.Hold.StopHaste, "stopHaste")

  conditionsWindow.closeButton.onClick = function()
    conditionsWindow:hide()
  end
end

local lastHealth = hp and tonumber(hp()) or nil
local damageWindowStartedAt = now or 0
local damageWindowAmount = 0
local lastSignificantDamageAt = now or 0
local lastCastAt = 0
local lastParalyseAttempt = 0
local utanaCast = nil
local nextCureCheck = 0
local nextLongCheck = 0
local controllerRunning = false

local function currentPing()
  if not g_game or not g_game.getPing then return 0 end
  local ok, value = pcall(function() return g_game.getPing() end)
  return ok and math.max(0, tonumber(value) or 0) or 0
end

local function castDelay(minimum)
  return math.max(tonumber(minimum) or 150, math.min(450, currentPing() + 80))
end

local function spellOnCooldown(spell)
  if type(getSpellCoolDown) ~= "function" then return false end
  local ok, active = pcall(getSpellCoolDown, spell)
  return ok and active == true
end

local function groupCooldownActive(groupId)
  local cooldown = modules and modules.game_cooldown
  if not cooldown or type(cooldown.isGroupCooldownIconActive) ~= "function" then return false end
  local ok, active = pcall(function()
    return cooldown.isGroupCooldownIconActive(groupId)
  end)
  return ok and active == true
end

local function castManaged(spell, minimumDelay)
  spell = tostring(spell or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if spell == "" or spellOnCooldown(spell) then return false end

  local delay = castDelay(minimumDelay)
  if now - lastCastAt < delay then return false end

  if TargetBot and type(TargetBot.saySpell) == "function" then
    local ok, sent = pcall(TargetBot.saySpell, spell, delay)
    if ok and sent == true then
      lastCastAt = now
      return true
    end
    return false
  end

  if type(say) == "function" then
    local ok = pcall(say, spell)
    if ok then
      lastCastAt = now
      return true
    end
  end
  return false
end

local function trackDamage()
  if type(hp) ~= "function" then return end
  local current = tonumber(hp())
  if not current then return end

  if lastHealth == nil then
    lastHealth = current
    return
  end

  local loss = lastHealth - current
  if loss > 0 then
    if now - damageWindowStartedAt > DAMAGE_WINDOW then
      damageWindowStartedAt = now
      damageWindowAmount = 0
    end

    damageWindowAmount = damageWindowAmount + loss
    local threshold = math.max(1, tonumber(config.significantDamage) or defaults.significantDamage)
    if loss >= threshold or damageWindowAmount >= threshold then
      lastSignificantDamageAt = now
      damageWindowStartedAt = now
      damageWindowAmount = 0
    end
  elseif now - damageWindowStartedAt > DAMAGE_WINDOW then
    damageWindowStartedAt = now
    damageWindowAmount = 0
  end

  lastHealth = current
end

local function isOutsideRestrictedPz()
  return not config.ignoreInPz or not isInPz()
end

local function tryAntiParalyse()
  if not config.cureParalyse or not isParalyzed() then return false end

  local retryDelay = castDelay(150)
  if now - lastParalyseAttempt < retryDelay then return true end

  local candidates = {
    {spell = config.paralyseSpell, cost = tonumber(config.paralyseCost) or 0}
  }

  if config.paralyseUseHasteFallback and tostring(config.hasteSpell or "") ~= tostring(config.paralyseSpell or "") then
    table.insert(candidates, {
      spell = config.hasteSpell,
      cost = tonumber(config.hasteCost) or 0
    })
  end

  for _, candidate in ipairs(candidates) do
    if mana() >= candidate.cost and not spellOnCooldown(candidate.spell) then
      if castManaged(candidate.spell, retryDelay) then
        lastParalyseAttempt = now
        return true
      end
    end
  end

  return true
end

local function tryHoldUtamo()
  if not config.holdUtamo or not isOutsideRestrictedPz() then return false end
  if hasManaShield() or mana() < (tonumber(config.utamoCost) or 0) then return false end
  return castManaged("utamo vita", 300)
end

local function hasteAllowedWhileTargeting()
  if not config.stopHaste or not target() then return true end
  if not TargetBot or type(TargetBot.isCaveBotActionAllowed) ~= "function" then return false end
  local ok, allowed = pcall(TargetBot.isCaveBotActionAllowed)
  return ok and allowed == true
end

local function tryHoldHaste()
  if not config.holdHaste or not isOutsideRestrictedPz() then return false end
  if hasHaste() or mana() < (tonumber(config.hasteCost) or 0) then return false end
  if standTime() >= 3000 or not hasteAllowedWhileTargeting() then return false end
  return castManaged(config.hasteSpell, 300)
end

local function conditionActive(check)
  if type(check) ~= "function" then return false end
  local ok, active = pcall(check)
  return ok and active == true
end

local function tryCureConditions()
  if now - lastSignificantDamageAt < CURE_SAFE_DELAY then return false end
  if hppercent() < (tonumber(config.cureMinHp) or defaults.cureMinHp) then return false end
  if groupCooldownActive(2) then return false end

  local cures = {
    {enabled = config.curePoison, check = isPoisioned, cost = config.poisonCost, spell = "exana pox"},
    {enabled = config.cureCurse, check = isCursed, cost = config.curseCost, spell = "exana mort"},
    {enabled = config.cureBleed, check = isBleeding, cost = config.bleedCost, spell = "exana kor"},
    {enabled = config.cureBurn, check = isBurning, cost = config.burnCost, spell = "exana flam"},
    {enabled = config.cureElectrify, check = isEnergized, cost = config.electrifyCost, spell = "exana vis"}
  }

  for _, cure in ipairs(cures) do
    local cost = tonumber(cure.cost) or 0
    if cure.enabled and mana() >= cost and conditionActive(cure.check) then
      return castManaged(cure.spell, 450)
    end
  end
  return false
end

local function tryLongConditions()
  if not isOutsideRestrictedPz() then return false end

  if config.holdUtura and mana() >= (tonumber(config.uturaCost) or 0) and hppercent() < 90 then
    local canUse = true
    if type(canCast) == "function" then
      local ok, result = pcall(canCast, config.uturaType)
      canUse = ok and result == true
    end
    if canUse and castManaged(config.uturaType, 700) then return true end
  end

  if config.holdUtana and mana() >= (tonumber(config.utanaCost) or 0) and
      (not utanaCast or now - utanaCast > 120000) then
    if castManaged("utana vid", 700) then
      utanaCast = now
      return true
    end
  end

  return false
end

local function runController()
  if controllerRunning then return end
  controllerRunning = true

  local ok, err = pcall(function()
    trackDamage()
    if not config.enabled then return end

    if tryAntiParalyse() then return end
    if tryHoldUtamo() then return end
    if tryHoldHaste() then return end

    if now >= nextCureCheck then
      nextCureCheck = now + 100
      if tryCureConditions() then return end
    end

    if now >= nextLongCheck then
      nextLongCheck = now + 250
      tryLongConditions()
    end
  end)

  controllerRunning = false
  if not ok then error(err) end
end

local function setEnabled(enabled)
  config.enabled = enabled == true
  ui.title:setOn(config.enabled)
  if config.enabled then
    lastHealth = type(hp) == "function" and tonumber(hp()) or lastHealth
    lastSignificantDamageAt = now
    nextCureCheck = now + 100
  end
  saveConfig()
end

ui.title:setOn(config.enabled)
ui.title.onClick = function()
  setEnabled(not config.enabled)
end

ui.conditionList.onClick = function()
  if not conditionsWindow then return end
  conditionsWindow:show()
  conditionsWindow:raise()
  conditionsWindow:focus()
end

Conditions = {
  show = function()
    if ui.conditionList and ui.conditionList.onClick then ui.conditionList.onClick() end
  end,
  isOn = function() return config.enabled == true end,
  setOn = function() setEnabled(true) end,
  setOff = function() setEnabled(false) end
}

macro(FAST_INTERVAL, function()
  runController()
end)

onPlayerHealthChange(function()
  trackDamage()
  if config.enabled then runController() end
end)

onManaChange(function()
  if config.enabled then runController() end
end)
