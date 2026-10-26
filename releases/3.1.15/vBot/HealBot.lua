local standBySpells = false
local standByItems = false
local requestHealSpellWake
local requestHealItemWake

local red = "#ff0800" -- "#ff0800" / #ea3c53 best
local blue = "#7ef9ff"

setDefaultTab("HP")
local healPanelName = "healbot"
local ui = setupUI([[
Panel
  height: 38

  HelperThemePower
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('HealBot')

  HelperThemeButton
    id: settings
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 17
    text: Setup

  HelperThemeButton
    id: 1
    anchors.top: prev.bottom
    anchors.left: parent.left
    text: 1
    margin-right: 2
    margin-top: 4
    size: 17 17

  HelperThemeButton
    id: 2
    anchors.verticalCenter: prev.verticalCenter
    anchors.left: prev.right
    text: 2
    margin-left: 4
    size: 17 17
    
  HelperThemeButton
    id: 3
    anchors.verticalCenter: prev.verticalCenter
    anchors.left: prev.right
    text: 3
    margin-left: 4
    size: 17 17

  HelperThemeButton
    id: 4
    anchors.verticalCenter: prev.verticalCenter
    anchors.left: prev.right
    text: 4
    margin-left: 4
    size: 17 17 
    
  HelperThemeButton
    id: 5
    anchors.verticalCenter: prev.verticalCenter
    anchors.left: prev.right
    text: 5
    margin-left: 4
    size: 17 17
    
  HelperThemeLabel
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
      ClientCooldowns = true,
      clientCooldownDefaultsVersion = 1,
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
      ClientCooldowns = true,
      clientCooldownDefaultsVersion = 1,
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
      ClientCooldowns = true,
      clientCooldownDefaultsVersion = 1,
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
      ClientCooldowns = true,
      clientCooldownDefaultsVersion = 1,
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
      ClientCooldowns = true,
      clientCooldownDefaultsVersion = 1,
      Interval = true,
      Conditions = true,
      Delay = true,
      MessageDelay = false
    },
  }
end

-- Adopt the requested ON default once, including profiles from R165. Later
-- explicit OFF choices survive reloads; no healing rules or power state change.
local updatedClientDefaults = false
for _, profile in ipairs(HealBotConfig[healPanelName]) do
  if profile.clientCooldownDefaultsVersion ~= 1 then
    profile.ClientCooldowns = true
    profile.Cooldown = true
    profile.clientCooldownDefaultsVersion = 1
    updatedClientDefaults = true
  end
end
if updatedClientDefaults then vBotConfigSave("heal") end

if not HealBotConfig.currentHealBotProfile or HealBotConfig.currentHealBotProfile == 0 or HealBotConfig.currentHealBotProfile > 5 then 
  HealBotConfig.currentHealBotProfile = 1
end

-- finding correct table, manual unfortunately
local currentSettings
local setActiveProfile = function()
  local n = HealBotConfig.currentHealBotProfile
  currentSettings = HealBotConfig[healPanelName][n]
  standBySpells = false
  if requestHealSpellWake then requestHealSpellWake() end
  if requestHealItemWake then requestHealItemWake() end
end
setActiveProfile()

if type(storage.healbotManualCooldowns) ~= "table" then storage.healbotManualCooldowns = {} end
if type(storage.healbotManualCooldowns.spell) ~= "table" then storage.healbotManualCooldowns.spell = {} end
if type(storage.healbotManualCooldowns.item) ~= "table" then storage.healbotManualCooldowns.item = {} end

local manualCooldownStore = storage.healbotManualCooldowns

local activeProfileColor = function()
  for i=1,5 do
    if i == HealBotConfig.currentHealBotProfile then
      ui[i]:setOn(true)
    else
      ui[i]:setOn(false)
    end
  end
end
activeProfileColor()

local sourceFromOption = function(text)
  if text == "Mana (%)" or text == "Mana Percent" then
    return "MP%"
  elseif text == "Vida (%)" or text == "Health Percent" then
    return "HP%"
  end
  return "burst"
end

local optionFromSource = function(source)
  if source == "MP" then
    return "Mana (%)"
  elseif source == "HP" then
    return "Vida (%)"
  elseif source == "MP%" then
    return "Mana (%)"
  elseif source == "HP%" then
    return "Vida (%)"
  end
  return "Dano reciente"
end

local signFromOption = function(text)
  if text == "Mayor que" or text == "Above" then
    return ">"
  elseif text == "Menor que" or text == "Below" then
    return "<"
  end
  return "="
end

local optionFromSign = function(sign)
  if sign == ">" then
    return "Mayor que"
  elseif sign == "<" then
    return "Menor que"
  end
  return "Igual a"
end

local normalizeRelation = function(relation)
  return (relation == "or" or relation == "o") and "or" or "and"
end

local optionFromRelation = function(relation)
  return normalizeRelation(relation) == "or" and "o" or "y"
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
    text = text .. " " .. optionFromRelation(entry.extraRelation) .. " " .. tostring(entry.extraOrigin) .. tostring(entry.extraSign) .. tostring(entry.extraValue)
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
  local used = nil

  if itemId and itemId > 100 then
    if visibleItemAmount then
      visible = tonumber(visibleItemAmount(itemId)) or 0
    end
    if vBot.ItemCounter and vBot.ItemCounter.get then
      known = tonumber(vBot.ItemCounter.get(itemId))
    end
    if vBot.ItemCounter and type(vBot.ItemCounter.getUsed)=='function'then
      local ok,value=pcall(vBot.ItemCounter.getUsed,itemId)
      if ok then used=tonumber(value)end
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
    amount = amount,
    used = used
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
      if requestHealItemWake then requestHealItemWake() end
      return
    end

    if now < deadline then
      schedule(ITEM_COOLDOWN_CONFIRM_INTERVAL, checkCounter)
      return
    end

    pendingItemCooldownChecks[key] = nil
    standByItems = false
    if requestHealItemWake then requestHealItemWake() end
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

-- Optional client timers take precedence over SpellCastTable's fixed waits.
-- Keep this local to HealBot: AttackBot, items and shared vlib stay independent.
local healClientSpellTimers, healClientGroupTimers, healClientPending = {}, {}, {}
local healClientSendReadyAt = 0
local healClientPacketSerial, healClientInFlight = 0, nil
local healClientDataCache, healClientCacheSize = {}, 0
local healClientCooldownRelevant

local function wakeForHealCooldown(timers, id)
  if requestHealSpellWake and healClientCooldownRelevant and
      healClientCooldownRelevant(timers == healClientGroupTimers, id) then
    standBySpells = false
    requestHealSpellWake()
  end
end

local function observeHealClientCooldown(timers, id, duration)
  id, duration = tonumber(id), tonumber(duration)
  if not id or id <= 0 or id % 1 ~= 0 or not duration or duration ~= duration or
      duration < 0 or duration == math.huge then return end
  healClientPacketSerial = healClientPacketSerial + 1
  local timer = {at = now + duration, expired = duration == 0, serial = healClientPacketSerial}
  timers[id] = timer
  if duration > 0 then
    local function finish()
      if timers[id] ~= timer then return end
      timer.expired = true
      wakeForHealCooldown(timers, id)
    end
    -- Like AttackBot, measure from receipt rather than the HUD's coarse
    -- progress animation or the executor's possibly one-turn-old now value.
    if type(schedule) ~= 'function' or not pcall(schedule, duration, finish) then
      timer.noScheduler = true
    end
  end
  wakeForHealCooldown(timers, id)
  return true
end

local function confirmHealClientRequest()
  local pending = healClientInFlight
  if not pending then return end
  local spellTimer = healClientSpellTimers[pending.id]
  if not spellTimer or spellTimer.serial <= pending.serial then return end
  for groupId in pairs(pending.group) do
    local groupTimer = healClientGroupTimers[groupId]
    if not groupTimer or groupTimer.serial <= pending.serial then return end
  end
  -- A complete native reply replaces the temporary send guard. Do not hold
  -- a ready spell for 200/500ms after the client supplied its actual waits.
  if healClientPending[pending.words] == pending then healClientPending[pending.words] = nil end
  healClientInFlight = nil
  healClientSendReadyAt = 0
  if requestHealSpellWake then requestHealSpellWake() end
end

if type(onSpellCooldown) == 'function' then
  onSpellCooldown(function(id, duration)
    if not observeHealClientCooldown(healClientSpellTimers, id, duration) then return end
    id = tonumber(id)
    for words, pending in pairs(healClientPending) do
      if pending.id == id then healClientPending[words] = nil end
    end
    confirmHealClientRequest()
  end)
end
if type(onGroupSpellCooldown) == 'function' then
  onGroupSpellCooldown(function(id, duration)
    if not observeHealClientCooldown(healClientGroupTimers, id, duration) then return end
    confirmHealClientRequest()
  end)
end

local function healClientSpellInfo(words)
  if not currentSettings.ClientCooldowns or not currentSettings.Cooldown then return nil end
  local cooldowns = modules and modules.game_cooldown
  if not cooldowns or type(cooldowns.isCooldownIconActive) ~= 'function' or
      type(cooldowns.isGroupCooldownIconActive) ~= 'function' or
      not g_game or type(g_game.getClientVersion) ~= 'function' or
      type(getSpellData) ~= 'function' then return nil end
  local ok, version = pcall(g_game.getClientVersion)
  if not ok or not tonumber(version) or tonumber(version) < 960 then return nil end
  words = tostring(words):lower():trim()
  local learned = vBot and vBot.customCooldowns and vBot.customCooldowns[words]
  if type(learned) ~= 'table' then learned = nil end
  local cached = healClientDataCache[words]
  if not cached or cached.lookup ~= getSpellData or now >= cached.untilAt or
      cached.learned ~= learned or cached.learnedId ~= (learned and learned.id) or
      cached.learnedGroup ~= (learned and learned.group) then
    local found, data = pcall(getSpellData, words)
    if healClientCacheSize >= 128 then healClientDataCache = {}; healClientCacheSize = 0 end
    if not healClientDataCache[words] then healClientCacheSize = healClientCacheSize + 1 end
    cached = {lookup = getSpellData, untilAt = now + 1000,
      learned = learned, learnedId = learned and learned.id, learnedGroup = learned and learned.group,
      data = found and type(data) == 'table' and data or nil}
    healClientDataCache[words] = cached
  end
  local data = cached.data
  local id = data and tonumber(data.id)
  -- getSpellData includes server-specific IDs/groups learned by vlib.
  -- Unknown/incomplete metadata must keep the existing fallback behavior.
  if not id or id <= 0 or id % 1 ~= 0 or type(data.group) ~= 'table' then return nil end
  local groups = {}
  for groupId in pairs(data.group) do
    groupId = tonumber(groupId)
    if not groupId or groupId <= 0 or groupId % 1 ~= 0 then return nil end
    groups[groupId] = true
  end
  return {words = words, id = id, group = groups, cooldowns = cooldowns,
    mana = tonumber(data.mana) or 0, level = tonumber(data.level) or 0}
end

healClientCooldownRelevant = function(isGroup, id)
  if not currentSettings.enabled or not currentSettings.ClientCooldowns or not currentSettings.Cooldown then return false end
  for _, entry in pairs(currentSettings.spellTable) do
    if entry.enabled then
      local info = healClientSpellInfo(entry.spell)
      if info and (isGroup and info.group[id] or not isGroup and info.id == id) then return true end
    end
  end
  return false
end

local function healClientCooldownActive(timers, id, readIcon)
  local timer = timers[id]
  if timer then
    if timer.noScheduler then return now < timer.at end
    return not timer.expired
  end
  -- Covers cooldowns already active when the bot was reloaded.
  local ok, active = pcall(readIcon, id)
  if not ok then return nil end
  return active and true or false
end

local function healSpellReady(words)
  local info = healClientSpellInfo(words)
  if info then
    local cooling = healClientCooldownActive(healClientSpellTimers, info.id, info.cooldowns.isCooldownIconActive)
    if cooling == true then return false, info end
    local compatible = cooling ~= nil
    for groupId in pairs(info.group) do
      local groupCooling = healClientCooldownActive(healClientGroupTimers, groupId, info.cooldowns.isGroupCooldownIconActive)
      if groupCooling == true then return false, info end
      if groupCooling == nil then compatible = false end
    end
    if compatible then
      local pending = healClientPending[info.words]
      local waiting = now < healClientSendReadyAt or pending and now < pending.at
      local requirements = not currentSettings.Conditions or
        level() >= info.level and currentManaAmount() >= info.mana
      -- Only skip the legacy cooldown check. Keep RL requirements and all
      -- configured healing conditions, priority and manual rule waits.
      return not waiting and requirements, info
    end
  end
  return canCast(words, not currentSettings.Conditions, not currentSettings.Cooldown), nil
end

local castHealSpell = function(words, nativeInfo)
  if nativeInfo then
    -- Bound retries while awaiting a server reply; never invent a full spell
    -- cooldown for an unconfirmed/failed request.
    local pending = {words = nativeInfo.words, id = nativeInfo.id, at = now + 500,
      serial = healClientPacketSerial, group = nativeInfo.group}
    healClientPending[nativeInfo.words] = pending
    healClientInFlight = pending
    healClientSendReadyAt = now + 200
  end
  say(words)
  standBySpells = false
  standByItems = false
end

local safeUseCall = function(fn, ...)
  if type(fn) ~= "function" then return false end
  local ok, result = pcall(fn, ...)
  return ok and result ~= false
end

-- findItem may skip loot containers. Include visible Purse/Loot Pouch
-- supplies, and allow the native item-ID hotkey path when the purse is closed.
local healItemSource = function(entry)
  local item = findItem(entry.item)
  if not item and g_game.getContainers then
    for _, container in pairs(g_game.getContainers()) do
      for _, candidate in ipairs(container:getItems()) do
        if candidate:getId()==entry.item then item=candidate;break end
      end
      if item then break end
    end
  end
  if item then return item end
  if currentSettings.OldSchool then return nil end
  if not currentSettings.Visible then return entry.item end
  local ok, purse = pcall(function()
    if type(getPurse)=="function" then
      local item=getPurse()
      if item then return item end
    end
    return player and player:getInventoryItem(InventorySlotPurse or SlotPurse or 11)
  end)
  if ok and purse then return entry.item end
end

local useHealItem = function(item, subType)
  local used = false
  local id = type(item)=="number" and item or item and item:getId()
  local direct = id==35563
  if not direct and g_things and type(g_things.getThingType)=="function" then
    local ok, multiUse = pcall(function()
      local thing=g_things.getThingType(id)
      if thing and type(thing.isMultiUse)=="function" then return thing:isMultiUse() end
    end)
    if ok and multiUse==false then direct=true end
  end

  if direct then
    used = (type(item)~="number" and safeUseCall(g_game.use,item)) or
      safeUseCall(g_game.useInventoryItem,id,subType or 0)
  elseif type(item) == "number" then
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

-- The native multi-use packet carries one shared item-use delay, without an
-- item ID. It is not a healing-spell group or proof of item consumption.
local healItemOwner = {active = true, packets = 0, nativeAttempts = 0, fallbackAttempts = 0}
local healMultiUseTimer, healNativeItemPending
local healLegacyItemReadyAt, healLootItemReadyAt = 0, 0
local healItemShared = modules and modules.game_bot
local cleanupHealItemCooldown

local function healItemIsMultiUse(entry)
  if tonumber(entry.item) == 35563 then return false end
  if not g_things or type(g_things.getThingType) ~= 'function' then return nil end
  local ok, value = pcall(function()
    local thing = g_things.getThingType(entry.item)
    if thing and type(thing.isMultiUse) == 'function' then return thing:isMultiUse() end
  end)
  if ok and type(value) == 'boolean' then return value end
  return nil
end

local function healNativeItemsEnabled()
  return healItemOwner.active and currentSettings.ClientCooldowns and healMultiUseTimer ~= nil
end

local function armHealItemWake(readyAt)
  if not healNativeItemsEnabled() or type(schedule) ~= 'function' then return end
  if healItemOwner.wakeAt and healItemOwner.wakeAt <= readyAt then return end
  healItemOwner.wakeAt = readyAt
  local ok = pcall(schedule, math.max(1, readyAt - now), function()
    if not healItemOwner.active or healItemOwner.wakeAt ~= readyAt then return end
    healItemOwner.wakeAt = nil
    if requestHealItemWake then requestHealItemWake() end
  end)
  if not ok then healItemOwner.wakeAt = nil end
end

local function observeHealMultiUseCooldown(duration)
  if not healItemOwner.active then return end
  duration = tonumber(duration)
  if not duration or duration ~= duration or duration < 0 or duration == math.huge or duration % 1 ~= 0 then return end
  healItemOwner.packets = healItemOwner.packets + 1
  local timer = {at = now + duration, duration = duration, expired = duration == 0}
  healMultiUseTimer = timer
  healNativeItemPending = nil
  if duration > 0 then
    local function finish()
      if not healItemOwner.active or healMultiUseTimer ~= timer then return end
      timer.expired = true
      standByItems = false
      if requestHealItemWake then requestHealItemWake() end
    end
    if type(schedule) ~= 'function' or not pcall(schedule, duration, finish) then timer.noScheduler = true end
  end
  standByItems = false
  if requestHealItemWake then requestHealItemWake() end
end

local function addHealItemListener(name, callback)
  local listeners = g_game[name]
  if listeners == nil then g_game[name] = callback
  elseif type(listeners) == 'function' then g_game[name] = {listeners, callback}
  elseif type(listeners) == 'table' then table.insert(listeners, callback)
  else return false end
  return true
end

local function removeHealItemListener(name, callback)
  local listeners = g_game[name]
  if listeners == callback then g_game[name] = nil
  elseif type(listeners) == 'table' then
    for i = #listeners, 1, -1 do if listeners[i] == callback then table.remove(listeners, i) end end
    if #listeners == 1 then g_game[name] = listeners[1] end
  end
end

local function resetHealItemSession()
  healMultiUseTimer, healNativeItemPending = nil, nil
  healLegacyItemReadyAt, healLootItemReadyAt = 0, 0
  healItemOwner.wakeAt = nil
  standByItems = false
end

cleanupHealItemCooldown = function()
  if not healItemOwner.active then return end
  healItemOwner.active = false
  removeHealItemListener('onMultiUseCooldown', observeHealMultiUseCooldown)
  removeHealItemListener('onGameEnd', resetHealItemSession)
  if healItemShared and healItemShared.sabuezoHealItemCooldownCleanup == cleanupHealItemCooldown then
    healItemShared.sabuezoHealItemCooldownCleanup = nil
  end
end
if healItemShared and type(healItemShared.sabuezoHealItemCooldownCleanup) == 'function' then
  healItemShared.sabuezoHealItemCooldownCleanup()
end
-- Use the same listener-list convention as OTC's connect()/signalcall().
-- The bot executor does not forward this native event in older clients.
if type(onMultiUseCooldown) == 'function' then
  onMultiUseCooldown(observeHealMultiUseCooldown)
else
  pcall(addHealItemListener, 'onMultiUseCooldown', observeHealMultiUseCooldown)
end
pcall(addHealItemListener, 'onGameEnd', resetHealItemSession)
if healItemShared then healItemShared.sabuezoHealItemCooldownCleanup = cleanupHealItemCooldown end
local oldHealPanelDestroy = ui.onDestroy
ui.onDestroy = function(widget)
  cleanupHealItemCooldown()
  if type(oldHealPanelDestroy) == 'function' then return oldHealPanelDestroy(widget) end
  if type(oldHealPanelDestroy) == 'table' then
    for _, callback in pairs(oldHealPanelDestroy) do
      if type(callback) == 'function' and callback(widget) then return true end
    end
  end
end

local function healNativeItemReady(entry)
  if not healNativeItemsEnabled() or healItemIsMultiUse(entry) ~= true then return nil end
  local timer = healMultiUseTimer
  if timer.noScheduler and now < timer.at or not timer.noScheduler and not timer.expired then return false end
  if healNativeItemPending and now < healNativeItemPending.at then
    armHealItemWake(healNativeItemPending.at)
    return false
  end
  return true
end

local function noteHealNativeItemRequest(entry)
  if not currentSettings.ClientCooldowns or healItemIsMultiUse(entry) ~= true then return end
  -- Until a fresh server packet arrives, retain the previous 400ms fallback.
  -- A successful local API call alone never means the server is ready again.
  healNativeItemPending = {id = entry.item, at = now + 400}
  armHealItemWake(healNativeItemPending.at)
  return healNativeItemPending
end

ui.title:setOn(currentSettings.enabled)
ui.title.onClick = function(widget)
  currentSettings.enabled = not currentSettings.enabled
  widget:setOn(currentSettings.enabled)
  vBotConfigSave("heal")
  standBySpells = false
  if requestHealSpellWake then requestHealSpellWake() end
  if requestHealItemWake then requestHealItemWake() end
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
  
  -- Modificacion de Titulo Principal
  healWindow:setText('HealBot')
  
  -- Inyeccion de tooltips mejorada
  healWindow.healer.spells.spellFormula:setTooltip('Palabras del hechizo (ejemplo: exura med ico)')
  healWindow.healer.spells.manaCost:setTooltip('Mana minimo requerido. 0 desactiva este filtro.')
  healWindow.healer.spells.spellValue:setTooltip('Poner valor de disparo (Ej: 80)')
  healWindow.healer.spells.spellExtraValue:setTooltip('Valor de disparo extra')
  healWindow.healer.spells.spellCooldown:setTooltip('Espera manual opcional: 3m, 30s, 180000ms')

  healWindow.healer.items.itemValue:setTooltip('Poner valor de disparo (Ej: 80)')
  healWindow.healer.items.itemId:setTooltip('Arrastra y suelta el item aqui (Ej: Pocion)')
  healWindow.healer.items.itemExtraValue:setTooltip('Valor de disparo extra')
  healWindow.healer.items.itemCooldown:setTooltip('Espera manual opcional: 3m, 30s, 180000ms')

  local setTip = function(widget, text)
    if widget and widget.setTooltip then widget:setTooltip(text) end
  end
  setTip(healWindow.healer.spells.spellSource, 'Dato que activa la regla: mana, vida o dano reciente.')
  setTip(healWindow.healer.spells.spellCondition, 'Comparacion con el valor indicado: menor, mayor o igual.')
  setTip(healWindow.healer.spells.spellValue, 'Valor que activa la regla (ejemplo: 80).')
  setTip(healWindow.healer.spells.spellFormula, 'Palabras del hechizo (ejemplo: exura med ico).')
  setTip(healWindow.healer.spells.manaCost, 'Mana minimo requerido para lanzar. Usa 0 para desactivar este filtro.')
  setTip(healWindow.healer.spells.spellCooldown, 'Espera manual opcional: 3m, 30s, 1h o 180000ms. Vacio o 0 la desactiva.')
  setTip(healWindow.healer.spells.spellAdvanced, 'Activar una segunda condicion.')
  setTip(healWindow.healer.spells.spellExtraRelation, 'Combinar las condiciones con y (ambas) u o (cualquiera).')
  setTip(healWindow.healer.spells.spellExtraSource, 'Segundo dato que se comprobara.')
  setTip(healWindow.healer.spells.spellExtraCondition, 'Comparacion de la segunda condicion.')
  setTip(healWindow.healer.spells.spellExtraValue, 'Valor de la segunda condicion (ejemplo: 40).')

  setTip(healWindow.healer.items.itemSource, 'Dato que se comprobara antes de usar el objeto.')
  setTip(healWindow.healer.items.itemCondition, 'Comparacion con el valor indicado: menor, mayor o igual.')
  setTip(healWindow.healer.items.itemValue, 'Valor que activa la regla (ejemplo: 80).')
  setTip(healWindow.healer.items.itemId, 'Arrastra aqui el objeto que quieras usar (ejemplo: una pocion).')
  setTip(healWindow.healer.items.itemCooldown, 'Espera manual opcional: 3m, 30s, 1h o 180000ms. Vacio o 0 la desactiva.')
  setTip(healWindow.healer.items.itemAdvanced, 'Activar una segunda condicion.')
  setTip(healWindow.healer.items.itemExtraRelation, 'Combinar las condiciones con y (ambas) u o (cualquiera).')
  setTip(healWindow.healer.items.itemExtraSource, 'Segundo dato que se comprobara.')
  setTip(healWindow.healer.items.itemExtraCondition, 'Comparacion de la segunda condicion.')
  setTip(healWindow.healer.items.itemExtraValue, 'Valor de la segunda condicion (ejemplo: 40).')
  setTip(healWindow.settings.list.ClientCooldowns, 'Prioriza cooldowns de hechizos y el uso compartido de objetos multiuso/pociones cuando el servidor envia su senal. Sin datos usa el respaldo habitual. Respeta condiciones y esperas manuales.')

  -- UI tabs share the original healer/settings objects and original rule handlers.
  local selectedHealTab="spells"
  local selectingProfile=false
  local function selectHealTab(name)
    selectedHealTab=name
    healWindow.healer:setVisible(name~="conditions")
    healWindow.settings:setVisible(name=="conditions")
    healWindow.healer.spells:setVisible(name=="spells")
    healWindow.healer.items:setVisible(name=="items")
    for _,key in ipairs({"spells","items","conditions"}) do healWindow.tabs[key]:setOn(key==name) end
  end
  for _,name in ipairs({"spells","items","conditions"}) do
    local tab=name
    healWindow.tabs[tab].onClick=function() selectHealTab(tab) end
  end
  for i=1,5 do healWindow.profileSelect:addOption("Perfil "..i,i) end
  healWindow.profileSelect.onOptionChange=function()
    if selectingProfile then return end
    local option=healWindow.profileSelect:getCurrentOption()
    if option and HealBot and HealBot.setActiveProfile then HealBot.setActiveProfile(option.data) end
  end
  healWindow.power.onClick=function()
    if HealBot.isOn() then HealBot.setOff() else HealBot.setOn() end
  end
  local titleSetOn=ui.title.setOn
  ui.title.setOn=function(widget,value)
    local result=titleSetOn(widget,value)
    healWindow.power:setOn(value)
    healWindow.power:setText(value and "ON" or "OFF")
    return result
  end
  healWindow.onVisibilityChange=function(widget,visible)
    if not visible then vBotConfigSave("heal") end
  end
  healWindow.settingsButton.onClick=function() selectHealTab("conditions") end
  selectHealTab(selectedHealTab)

  local setProfileName = function()
    ui.name:setText(currentSettings.name)
    healWindow.profileName:setText(currentSettings.name)
    selectingProfile=true
    healWindow.profileSelect:setOption("Perfil "..HealBotConfig.currentHealBotProfile)
    selectingProfile=false
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
    if not currentSettings.Cooldown then
      currentSettings.ClientCooldowns = false
      healWindow.settings.list.ClientCooldowns:setChecked(false)
    end
    standBySpells = false
    vBotConfigSave("heal")
  end
  healWindow.settings.list.ClientCooldowns.onClick = function(widget)
    currentSettings.ClientCooldowns = not currentSettings.ClientCooldowns
    healWindow.settings.list.ClientCooldowns:setChecked(currentSettings.ClientCooldowns)
    if currentSettings.ClientCooldowns then
      currentSettings.Cooldown = true
      healWindow.settings.list.Cooldown:setChecked(true)
    end
    standBySpells = false
    vBotConfigSave("heal")
    if requestHealSpellWake then requestHealSpellWake() end
    if requestHealItemWake then requestHealItemWake() end
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
    healWindow.healer.spells.addSpell:setText("Agregar")
    if clear then
      healWindow.healer.spells.spellFormula:setText('')
      healWindow.healer.spells.spellValue:setText('')
      healWindow.healer.spells.manaCost:setText('0')
      healWindow.healer.spells.spellCooldown:setText('')
      healWindow.healer.spells.spellAdvanced:setChecked(false)
      setComboOption(healWindow.healer.spells.spellExtraRelation, "y")
      healWindow.healer.spells.spellExtraValue:setText('')
    end
  end

  local resetItemEditor = function(clear)
    editingItemEntry = nil
    healWindow.healer.items.addItem:setText("Agregar")
    if clear then
      healWindow.healer.items.itemId:setItemId(0)
      healWindow.healer.items.itemValue:setText('')
      healWindow.healer.items.itemCooldown:setText('')
      healWindow.healer.items.itemAdvanced:setChecked(false)
      setComboOption(healWindow.healer.items.itemExtraRelation, "y")
      healWindow.healer.items.itemExtraValue:setText('')
    end
  end

  local loadAdvancedEditor = function(panel, prefix, entry)
    local hasExtra = entry.extraEnabled and true or false
    panel[prefix .. "Advanced"]:setChecked(hasExtra)
    setComboOption(panel[prefix .. "ExtraRelation"], optionFromRelation(entry.extraRelation))
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
    healWindow.healer.spells.addSpell:setText("Guardar")
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
    healWindow.healer.items.addItem:setText("Guardar")
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
        label:setText(entry.spell)
        label:setTooltip("(MP>=" .. normalizeManaCost(entry.cost) .. ") " .. entry.origin .. entry.sign .. entry.value .. extraSummary(entry) .. cooldownSummary(entry) .. ": " .. entry.spell)
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
        label:setText("Item " .. entry.item)
        label:setTooltip(entry.origin .. entry.sign .. entry.value .. extraSummary(entry) .. cooldownSummary(entry) .. ": " .. entry.item)
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
    healWindow.settings.list.ClientCooldowns:setChecked(currentSettings.ClientCooldowns == true)
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
    currentSettings.ClientCooldowns = true
    currentSettings.clientCooldownDefaultsVersion = 1
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
    standBySpells = false
    if requestHealSpellWake then requestHealSpellWake() end
    if requestHealItemWake then requestHealItemWake() end
  end

  HealBot.setOffSilent = function()
    currentSettings.enabled = false
    ui.title:setOn(currentSettings.enabled)
  end

  HealBot.setOnSilent = function()
    currentSettings.enabled = true
    ui.title:setOn(currentSettings.enabled)
    standBySpells = false
    if requestHealSpellWake then requestHealSpellWake() end
    if requestHealItemWake then requestHealItemWake() end
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
  HealBot.getItemCooldownState = function()
    local timer = healMultiUseTimer
    local remaining = timer and (timer.noScheduler and math.max(0, timer.at-now) or not timer.expired and math.max(1,timer.at-now) or 0) or nil
    return {active = healItemOwner.active, enabled = currentSettings.ClientCooldowns == true, observed = timer ~= nil,
      packets = healItemOwner.packets, remainingMs = remaining, lastDurationMs = timer and timer.duration,
      nativeAttempts = healItemOwner.nativeAttempts, fallbackAttempts = healItemOwner.fallbackAttempts,
      pendingRemainingMs = healNativeItemPending and math.max(0, healNativeItemPending.at-now) or 0,
      source = timer and currentSettings.ClientCooldowns and 'client_multiuse' or 'fallback'}
  end
end

-- spells
local function runHealSpells()
  if standBySpells then return end
  if not currentSettings.enabled then return end
  local somethingIsOnCooldown = false

  for _, entry in pairs(currentSettings.spellTable) do
    if entry.enabled and (not entry.minLevel or type(level)=="function" and level()>=entry.minLevel) and
      currentManaAmount() >= normalizeManaCost(entry.cost) and entryConditionsPass(entry) then
      if not isManualCooldownReady("spell", entry) then
        somethingIsOnCooldown = true
      else
        local ready, nativeInfo = healSpellReady(entry.spell)
        if ready then
          castHealSpell(entry.spell, nativeInfo)
          startManualCooldown("spell", entry)
          return
        end
        somethingIsOnCooldown = true
      end
    end
  end
  if not somethingIsOnCooldown then
    standBySpells = true 
  end
end

local healSpellCycleBusy, healSpellWakePending = false, false
local function dispatchHealSpells()
  if healSpellCycleBusy then return end
  healSpellCycleBusy = true
  local ok, err = pcall(runHealSpells)
  healSpellCycleBusy = false
  if not ok then error(err) end
end
-- Keep the existing light polling fallback. Native events wake the same
-- guarded decision immediately on the next executor turn, without that wait.
macro(100, dispatchHealSpells)
requestHealSpellWake = function()
  if healSpellWakePending or not currentSettings.enabled or not currentSettings.ClientCooldowns or
      not currentSettings.Cooldown or type(schedule) ~= 'function' then return end
  healSpellWakePending = true
  local ok = pcall(schedule, 0, function()
    healSpellWakePending = false
    if not currentSettings.enabled or not currentSettings.ClientCooldowns or not currentSettings.Cooldown then return end
    if g_game and type(g_game.isOnline) == 'function' and not g_game.isOnline() then return end
    dispatchHealSpells()
  end)
  if not ok then healSpellWakePending = false end
end

-- items
local function runHealItems()
  if standByItems then return end
  if not currentSettings.enabled or #currentSettings.itemTable == 0 then return end
  if vBot.pauseHealItemsUntil and now < vBot.pauseHealItemsUntil then return end
  if currentSettings.Delay and vBot.isUsing then return end
  local coordinatingItems=PushMax and type(PushMax.isCoordinatingItems)=='function'and PushMax.isCoordinatingItems()
  local somethingIsOnCooldown = false
  local legacyAttempted = false
  local lootingItems = TargetBot and type(TargetBot.isOn) == "function" and
      TargetBot.Looting and type(TargetBot.Looting.getStatus) == "function" and
      TargetBot.isOn() and TargetBot.Looting.getStatus():len() > 0 and currentSettings.Interval and not coordinatingItems
  local legacyGap = currentSettings.MessageDelay and 100 or 400
  local lootGap = currentSettings.MessageDelay and 200 or 700

  for _, entry in pairs(currentSettings.itemTable) do
    if entry.enabled and entryConditionsPass(entry) then
      local useItem = healItemSource(entry)
      if useItem then
        registerHealItemCounter(entry.item)
        local nativeReady = healNativeItemReady(entry)
        if not isManualCooldownReady("item", entry) then
          somethingIsOnCooldown = true
        elseif isItemCooldownConfirmationPending(entry) then
          somethingIsOnCooldown = true
        elseif nativeReady == false then
          somethingIsOnCooldown = true
        elseif nativeReady == nil and (now < healLegacyItemReadyAt or currentSettings.MessageDelay and vBot.isUsingPotion) then
          somethingIsOnCooldown = true
          if now < healLegacyItemReadyAt then armHealItemWake(healLegacyItemReadyAt) end
        elseif lootingItems and now < healLootItemReadyAt then
          somethingIsOnCooldown = true
          armHealItemWake(healLootItemReadyAt)
        elseif PushMax and type(PushMax.allowHealItem)=='function'and not PushMax.allowHealItem(entry.item)then
          -- Keep the item loop armed. The spell macro and configured healing
          -- conditions/cooldowns remain independent of this short turn.
          somethingIsOnCooldown = true
        else
          local beforeSnapshot = getHealItemCounterSnapshot(entry.item)
          local previousPending = healNativeItemPending
          local request = noteHealNativeItemRequest(entry)
          if useHealItem(useItem, entry.subType) then
            if nativeReady == nil then
              healLegacyItemReadyAt = now + legacyGap
              healItemOwner.fallbackAttempts = healItemOwner.fallbackAttempts + 1
            else
              healItemOwner.nativeAttempts = healItemOwner.nativeAttempts + 1
            end
            if lootingItems then healLootItemReadyAt = now + lootGap end
            if PushMax and type(PushMax.noteHealItem)=='function'then PushMax.noteHealItem(entry.item,beforeSnapshot)
            elseif PushMax and type(PushMax.noteHealing)=='function'and player:getHealthPercent()<=40 then PushMax.noteHealing()end
            confirmManualItemCooldown(entry, beforeSnapshot)
            return
          end
          if request and healNativeItemPending == request then healNativeItemPending = previousPending end
          if nativeReady == nil then legacyAttempted = true end
          somethingIsOnCooldown = true
        end
      end
    end
  end
  if legacyAttempted then healLegacyItemReadyAt = now + legacyGap end
  if not somethingIsOnCooldown then
    standByItems = true
  end
end

local healItemCycleBusy, healItemWakePending = false, false
local function dispatchHealItems()
  if not healItemOwner.active or healItemCycleBusy then return end
  healItemCycleBusy = true
  local ok, err = pcall(runHealItems)
  healItemCycleBusy = false
  if not ok then error(err) end
end
macro(100, dispatchHealItems)
requestHealItemWake = function()
  if not healNativeItemsEnabled() or healItemWakePending or not currentSettings.enabled or
      #currentSettings.itemTable == 0 or type(schedule) ~= 'function' then return end
  healItemWakePending = true
  local ok = pcall(schedule, 0, function()
    healItemWakePending = false
    if not healNativeItemsEnabled() or not currentSettings.enabled then return end
    if g_game and type(g_game.isOnline) == 'function' and not g_game.isOnline() then return end
    standByItems = false
    dispatchHealItems()
  end)
  if not ok then healItemWakePending = false end
end
UI.Separator()

onPlayerHealthChange(function(healthPercent)
  standByItems = false
  standBySpells = false
  requestHealSpellWake()
  requestHealItemWake()
end)

onManaChange(function(player, mana, maxMana, oldMana, oldMaxMana)
  standByItems = false
  standBySpells = false
  requestHealSpellWake()
  requestHealItemWake()
end)
