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
  pauseWhileAttacking = true
}

if config.curePoison == nil and config.curePosion ~= nil then
  config.curePoison = config.curePosion == true
end

-- Preserve the old attack checkbox choice when loading an unmigrated profile.
if config.pauseWhileAttacking == nil and config.stopHaste ~= nil then
  config.pauseWhileAttacking = config.stopHaste == true
end

for key, value in pairs(defaults) do
  if config[key] == nil then config[key] = value end
end

local numericKeys = {
  "poisonCost", "curseCost", "bleedCost", "burnCost", "electrifyCost",
  "paralyseCost", "hasteCost",
  "utamoCost", "utanaCost", "uturaCost"
}
for _, key in ipairs(numericKeys) do
  config[key] = tonumber(config[key]) or defaults[key]
end

config.paralyseSpell = tostring(config.paralyseSpell or defaults.paralyseSpell)
config.hasteSpell = tostring(config.hasteSpell or defaults.hasteSpell)
config.uturaType = tostring(config.uturaType or defaults.uturaType)

-- Remove only the obsolete thresholds and the renamed attack option.
local removedOldOptions = config.significantDamage ~= nil or config.cureMinHp ~= nil or
  config.stopHaste ~= nil
config.significantDamage = nil
config.cureMinHp = nil
config.stopHaste = nil

local FAST_INTERVAL = 20

local function saveConfig()
  if type(vBotConfigSave) == "function" then vBotConfigSave("heal") end
end

if removedOldOptions then saveConfig() end

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
  bindCheck(conditionsWindow.Hold.PauseWhileAttacking, "pauseWhileAttacking")

  conditionsWindow.closeButton.onClick = function()
    conditionsWindow:hide()
  end
end

local lastCastAt = 0
local lastParalyseAttempt = nil
local nextParalyseCandidate = 1
local utanaCast = nil
local nextCureCheck = 0
local nextLongCheck = 0
local controllerRunning = false
local hasteStatus = "Esperando comprobacion"
local RECOVERY_DURATION = 60000 -- MythicOT effect duration, not its cooldown
local recoveryEffectUntil = nil
local recoveryPendingUntil = 0
local lastRecoveryConfirmedAt = nil
local observedSpellCooldowns = {}
local observedGroupCooldowns = {}
local unobservedCooldownSince = {}
local latestPlayerStates = nil
local antiStatus = "Esperando comprobacion"
local antiDetail = antiStatus
storage = storage or {}
if type(storage.conditionsAntiParalyze) ~= "table" then storage.conditionsAntiParalyze = {} end
local antiDiagnostic = storage.conditionsAntiParalyze
antiDiagnostic.version = "20261001-2"
antiDiagnostic.attempts = {}

local function setAntiStatus(status, detail)
  detail = detail or status
  if status == antiStatus and detail == antiDetail then return end
  antiStatus, antiDetail = status, detail
  antiDiagnostic.status, antiDiagnostic.detail = status, detail
  antiDiagnostic.at = now
  if conditionsWindow and conditionsWindow.Anti.AntiStatus then
    conditionsWindow.Anti.AntiStatus:setText(status)
    conditionsWindow.Anti.AntiStatus:setTooltip(detail)
  end
end

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

local function normalizedSpell(spell)
  return tostring(spell or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
end

-- Cooldown widgets can retain an active flag. Actual protocol durations are
-- authoritative for Anti-Paralyze; an old flag alone cannot block it forever.
if type(onSpellCooldown) == "function" then
  onSpellCooldown(function(iconId, duration)
    iconId, duration = tonumber(iconId), tonumber(duration)
    if iconId and duration then observedSpellCooldowns[iconId] = now + math.max(0, duration) end
  end)
end
if type(onGroupSpellCooldown) == "function" then
  onGroupSpellCooldown(function(groupId, duration)
    groupId, duration = tonumber(groupId), tonumber(duration)
    if groupId and duration then observedGroupCooldowns[groupId] = now + math.max(0, duration) end
  end)
end

local function antiSpellOnCooldown(spell)
  local data
  if type(getSpellData) == "function" then
    local ok, value = pcall(getSpellData, spell)
    if ok and type(value) == "table" then data = value end
  end
  local function gate(key, nativeActive, expiresAt, expectedDuration)
    if expiresAt and now < expiresAt then return true end
    if nativeActive ~= true then unobservedCooldownSince[key] = nil; return false end
    if expiresAt then return false end -- expired server cooldown; stale icon
    unobservedCooldownSince[key] = unobservedCooldownSince[key] or now
    return now - unobservedCooldownSince[key] < math.max(300, tonumber(expectedDuration) or 1000)
  end
  local cd = modules and modules.game_cooldown
  if data and tonumber(data.id) and cd and type(cd.isCooldownIconActive) == "function" then
    local id = tonumber(data.id)
    local ok, active = pcall(cd.isCooldownIconActive, id)
    if ok then
      local blocked = gate("icon:" .. id, active, observedSpellCooldowns[id], data.exhaustion)
      if type(data.group) == "table" then
        for groupId, duration in pairs(data.group) do
          groupId = tonumber(groupId)
          if groupId then
            local groupOk, groupActive = false, nil
            if type(cd.isGroupCooldownIconActive) == "function" then
              groupOk, groupActive = pcall(cd.isGroupCooldownIconActive, groupId)
            end
            local groupBlocked = gate("group:" .. groupId, groupActive,
              observedGroupCooldowns[groupId], duration)
            blocked = groupBlocked or blocked
            if not groupOk and not observedGroupCooldowns[groupId] and spellOnCooldown(spell) then
              blocked = gate("spell:" .. spell, true, nil, data.exhaustion) or blocked
            end
          end
        end
      end
      return blocked
    end
  end
  -- Keep received cooldown deadlines effective on clients without the
  -- individual icon/group accessors as well.
  if data then
    local expiresAt = observedSpellCooldowns[tonumber(data.id)]
    if expiresAt and now < expiresAt then return true end
    if type(data.group) == "table" then
      for groupId in pairs(data.group) do
        expiresAt = observedGroupCooldowns[tonumber(groupId)]
        if expiresAt and now < expiresAt then return true end
      end
    end
  end
  return gate("spell:" .. spell, spellOnCooldown(spell), nil, data and data.exhaustion)
end

local function isRecoverySpell(spell)
  spell = normalizedSpell(spell)
  return spell == "utura" or spell == "utura gran"
end

local function recoveryWallTime()
  if not os or type(os.time) ~= "function" then return nil end
  local ok, value = pcall(os.time)
  return ok and tonumber(value) or nil
end

local function confirmRecoveryEffect()
  recoveryEffectUntil = now + RECOVERY_DURATION
  recoveryPendingUntil = 0
  lastRecoveryConfirmedAt = now
  local wallTime = recoveryWallTime()
  if wallTime then
    -- Wall time survives reloading the bot and restarting the client. Allow
    -- one extra second for its lower precision; live timing uses milliseconds.
    config.recoveryEffectExpiresAt = wallTime + RECOVERY_DURATION / 1000 + 1
    saveConfig()
  end
end

local function recoveryEffectActive()
  if recoveryEffectUntil == nil then
    local wallTime = recoveryWallTime()
    local remaining = wallTime and (tonumber(config.recoveryEffectExpiresAt) or 0) - wallTime or 0
    if remaining > 0 and remaining <= RECOVERY_DURATION / 1000 + 1 then
      recoveryEffectUntil = now + remaining * 1000
    else
      recoveryEffectUntil = 0
    end
  end
  return now < recoveryEffectUntil or now < recoveryPendingUntil
end

-- Confirm actual casts, including manual casts and casts while Conditions is
-- off. Sending a phrase alone must not lock Recovery for a full minute if the
-- server rejects it. Both Recovery variants share the same effect timer.
if type(onTalk) == "function" then
  onTalk(function(name, level, mode, text)
    if not isRecoverySpell(text) then return end
    local ok, ownName = pcall(function()
      local localPlayer = player
      if not localPlayer and g_game and g_game.getLocalPlayer then
        localPlayer = g_game.getLocalPlayer()
      end
      return localPlayer and localPlayer:getName()
    end)
    if ok and ownName and name == ownName then confirmRecoveryEffect() end
  end)
end

if type(onSpellCooldown) == "function" then
  onSpellCooldown(function(iconId, duration)
    if type(getSpellData) ~= "function" then return end
    for _, spell in ipairs({"utura", "utura gran"}) do
      local ok, data = pcall(getSpellData, spell)
      if ok and type(data) == "table" and tonumber(data.id) == tonumber(iconId) then
        -- The phrase and cooldown can confirm the same cast almost together.
        if not lastRecoveryConfirmedAt or now - lastRecoveryConfirmedAt > 1500 then
          confirmRecoveryEffect()
        end
        return
      end
    end
  end)
end

local function playerWalkingNow()
  local ok, walking = pcall(function()
    local localPlayer = g_game and g_game.getLocalPlayer and g_game.getLocalPlayer() or player
    return localPlayer and localPlayer:isWalking()
  end)
  return ok and walking == true
end

local function isHasteSpell(spell)
  return spell:match("^utani%s") ~= nil or
    spell == normalizedSpell(config.hasteSpell)
end

local combatActive

local function castManaged(spell, minimumDelay, urgent)
  spell = normalizedSpell(spell)
  if spell == "" then return false end
  -- Recovery is always blocked in PZ, regardless of the general pause option.
  if isRecoverySpell(spell) and isInPz() then return false end
  -- These spells must wait for PvE/PvP combat to finish on every cast path,
  -- including custom Anti-Paralyze spells and a disabled general pause option.
  if (spell == "exana pox" or isRecoverySpell(spell)) and combatActive() then return false end
  -- Gate both maintained Haste and Anti-Paralyse Haste at the point of casting.
  if isHasteSpell(spell) and not playerWalkingNow() then return false end
  if urgent then
    if antiSpellOnCooldown(spell) or type(say) ~= "function" then return false end
    -- No shared spell queue can acknowledge an urgent cast without sending it.
    local ok, sent = pcall(say, spell)
    if ok and sent ~= false then lastCastAt = now; return true end
    return false
  end
  if spellOnCooldown(spell) then return false end

  local delay = castDelay(minimumDelay)
  if not urgent and now - lastCastAt < delay then return false end

  if TargetBot and type(TargetBot.saySpell) == "function" then
    local ok, sent = pcall(TargetBot.saySpell, spell, delay)
    if ok and sent == true then
      lastCastAt = now
      return true
    end
    return false
  end

  if type(say) == "function" then
    local ok, sent = pcall(say, spell)
    if ok and sent ~= false then
      lastCastAt = now
      return true
    end
  end
  return false
end

local function conditionActive(check)
  if type(check) ~= "function" then return false end
  local ok, active = pcall(check)
  return ok and active == true
end

local function readPlayerStates()
  local ok, states = pcall(function()
    local localPlayer = g_game and g_game.getLocalPlayer and g_game.getLocalPlayer() or player
    return localPlayer and localPlayer:getStates()
  end)
  if ok and tonumber(states) then return tonumber(states) end
  return latestPlayerStates
end

local function statesHaveParalysis(states)
  local constants = PlayerStates or (modules and modules.gamelib and modules.gamelib.PlayerStates)
  local mask = type(constants) == "table" and tonumber(constants.Paralyze) or 32
  mask = mask and mask > 0 and mask or 32
  return math.floor(states / mask) % 2 == 1
end

local function paralyzedNow()
  local states = readPlayerStates()
  if type(states) == "number" then return statesHaveParalysis(states) end
  return conditionActive(isParalyzed)
end

combatActive = function()
  -- The swords state also covers receiving attacks without a selected target.
  if conditionActive(isInFight) or conditionActive(hasSwords) then return true end
  local states = readPlayerStates()
  if type(states) == "number" then
    local constants = PlayerStates or (modules and modules.gamelib and modules.gamelib.PlayerStates)
    local mask = type(constants) == "table" and tonumber(constants.Swords) or 128
    mask = mask and mask > 0 and mask or 128
    if math.floor(states / mask) % 2 == 1 then return true end
  end

  local creature
  if g_game and type(g_game.getAttackingCreature) == "function" then
    local ok, value = pcall(g_game.getAttackingCreature)
    if ok then creature = value end
  end
  if not creature and type(target) == "function" then
    local ok, value = pcall(target)
    if ok then creature = value end
  end
  if creature then
    -- PvP and PvE targets count alike. Ignore a dead target left during looting.
    local hpOk, health = pcall(function() return creature:getHealthPercent() end)
    if not hpOk or not tonumber(health) or tonumber(health) > 0 then return true end
  elseif g_game and conditionActive(g_game.isAttacking) then
    return true
  end

  -- Cover target switches and being surrounded before the swords state arrives.
  -- The vBot helper uses the current floor and excludes player summons.
  if type(getMonsters) == "function" then
    local ok, amount = pcall(getMonsters, 7, false)
    if ok and (tonumber(amount) or 0) > 0 then return true end
  end
  return false
end

local function normalConditionsBlocked()
  if config.ignoreInPz and isInPz() then return "Pausado en PZ" end
  if config.pauseWhileAttacking and combatActive() then return "Pausado en combate (PvE/PvP)" end
  return false
end

local function tryAntiParalyse()
  if not config.cureParalyse then
    lastParalyseAttempt = nil
    nextParalyseCandidate = 1
    setAntiStatus("Anti desactivado")
    return false
  end
  if not paralyzedNow() then
    lastParalyseAttempt = nil
    nextParalyseCandidate = 1
    setAntiStatus("Sin paralisis")
    return false
  end

  local retryDelay = castDelay(150)
  if lastParalyseAttempt and now - lastParalyseAttempt < retryDelay then return true end

  local candidates = {
    {spell = normalizedSpell(config.paralyseSpell), cost = tonumber(config.paralyseCost) or 0}
  }

  if config.paralyseUseHasteFallback and normalizedSpell(config.hasteSpell) ~= candidates[1].spell then
    table.insert(candidates, {
      spell = normalizedSpell(config.hasteSpell),
      cost = tonumber(config.hasteCost) or 0
    })
  end

  -- If the condition remains after a sent spell, try the other candidate on
  -- the next retry instead of assuming that sending the primary cured it.
  local blocked = {}
  for offset = 0, #candidates - 1 do
    local index = ((nextParalyseCandidate - 1 + offset) % #candidates) + 1
    local candidate = candidates[index]
    if candidate.spell == "" then
      table.insert(blocked, "Hechizo principal vacio")
    elseif mana() < candidate.cost then
      table.insert(blocked, candidate.spell .. ": mana " .. mana() .. "/" .. candidate.cost)
    elseif antiSpellOnCooldown(candidate.spell) then
      table.insert(blocked, candidate.spell .. ": cooldown activo")
    else
      lastParalyseAttempt = now
      local sent = castManaged(candidate.spell, retryDelay, true)
      table.insert(antiDiagnostic.attempts, {at = now, spell = candidate.spell, sent = sent,
        mana = mana(), states = readPlayerStates()})
      while #antiDiagnostic.attempts > 8 do table.remove(antiDiagnostic.attempts, 1) end
      if sent then
        nextParalyseCandidate = (index % #candidates) + 1
        setAntiStatus("Enviado: " .. candidate.spell,
          "Paralisis activa. Enviado " .. candidate.spell .. "; esperando que desaparezca el estado.")
        return true
      end
      table.insert(blocked, candidate.spell .. ": envio rechazado")
    end
  end
  setAntiStatus("Esperando mana/cooldown", table.concat(blocked, " | "))
  return true
end

local function tryHoldUtamo()
  if not config.holdUtamo then return false end
  if hasManaShield() or mana() < (tonumber(config.utamoCost) or 0) then return false end
  return castManaged("utamo vita", 300)
end

local function tryHoldHaste()
  if not config.holdHaste then hasteStatus = "Mantener Haste desactivado"; return false end
  if not playerWalkingNow() then hasteStatus = "Quieto; esperando movimiento"; return false end
  if hasHaste() then hasteStatus = "Efecto de velocidad activo"; return false end
  if mana() < (tonumber(config.hasteCost) or 0) then hasteStatus = "Mana insuficiente"; return false end
  local sent = castManaged(config.hasteSpell, 300)
  hasteStatus = sent and "Hechizo enviado; esperando efecto" or "Esperando cooldown o turno para lanzar"
  return sent
end

local function tryCureConditions()
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
  if config.holdUtura and not recoveryEffectActive() and mana() >= (tonumber(config.uturaCost) or 0) then
    local canUse = true
    if type(canCast) == "function" then
      local ok, result = pcall(canCast, config.uturaType)
      canUse = ok and result == true
    end
    if canUse and castManaged(config.uturaType, 700) then
      if not lastRecoveryConfirmedAt or lastRecoveryConfirmedAt < now then
        recoveryPendingUntil = now + math.max(1500, math.min(3000, currentPing() * 2 + 300))
      end
      if type(onTalk) ~= "function" and type(onSpellCooldown) ~= "function" then
        confirmRecoveryEffect()
      end
      return true
    end
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
    if not config.enabled then
      hasteStatus = "Conditions desactivado"
      setAntiStatus("Conditions desactivado")
      return
    end

    if tryAntiParalyse() then return end
    local blocked = normalConditionsBlocked()
    if blocked then hasteStatus = blocked; return end
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
  getHasteStatus = function()
    if not config.enabled then return "Conditions desactivado" end
    if not config.holdHaste then return "Mantener Haste desactivado" end
    return hasteStatus
  end,
  getAntiParalyseStatus = function() return antiDetail end,
  isOn = function() return config.enabled == true end,
  setOn = function() setEnabled(true) end,
  setOff = function() setEnabled(false) end
}

macro(FAST_INTERVAL, function()
  runController()
end)

onPlayerHealthChange(function()
  if config.enabled then runController() end
end)

onManaChange(function()
  if config.enabled then runController() end
end)

if type(onStatesChange) == "function" then
  onStatesChange(function(localPlayer, states, oldStates)
    latestPlayerStates = tonumber(states)
    if latestPlayerStates and not statesHaveParalysis(latestPlayerStates) then
      lastParalyseAttempt = nil
      nextParalyseCandidate = 1
    end
    if config.enabled then runController() end
  end)
end
