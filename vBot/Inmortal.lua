-- Inmortal: Energy Ring/Might Ring/Amulet Protector
-- Energy Ring + Might Ring + Amulet editable
-- Corregido para OTC/vBot v15:
-- 1) El Energy Ring se quita inmediatamente al llegar al HP de OFF.
-- 2) La bajada de mana NO cuenta como daño para el timer.
-- 3) El Might Ring NO pelea contra el Energy Ring mientras el Energy Ring está puesto.
-- 4) Después de quitarse el Energy Ring, el Might Ring ya puede funcionar inmediatamente.
-- 5) El ring normal después del Energy Ring espera 2s sin recibir daño.

setDefaultTab("Hp")

local panelName = "autoProtect_Ultra"

-- Interfaz minimalista en el panel
local ui = setupUI([[
Panel
  height: 19

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('Inmortal')
    color: #ffffff

  Button
    id: setup
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 17
    text: Setup
]])
ui:setId(panelName)

-- =========================
-- STORAGE
-- =========================
local function defaultSection(enabled, hpAt, mpAt, dangerItem, normalItem)
  return {
    enabled = enabled,
    hpAt = hpAt or 75,
    mpAt = mpAt or 75,
    dangerItem = dangerItem or 0,
    normalItem = normalItem or 0
  }
end

local function normalizeSection(section, fallback)
  if type(section) ~= "table" then section = {} end
  if section.enabled == nil then section.enabled = fallback.enabled end

  local oldThreshold = tonumber(section.threshold)

  section.hpAt = tonumber(section.hpAt) or oldThreshold or fallback.hpAt
  section.mpAt = tonumber(section.mpAt) or oldThreshold or fallback.mpAt
  section.dangerItem = tonumber(section.dangerItem) or fallback.dangerItem
  section.normalItem = tonumber(section.normalItem) or fallback.normalItem

  return section
end

local function normalizeEringSection(section, fallback)
  if type(section) ~= "table" then section = {} end
  if section.enabled == nil then section.enabled = fallback.enabled end

  local oldThreshold = tonumber(section.threshold)

  section.mode = section.mode or fallback.mode
  section.hpAt = tonumber(section.hpAt) or oldThreshold or fallback.hpAt
  section.removeAt = tonumber(section.removeAt) or tonumber(section.mpAt) or fallback.removeAt
  section.dangerItem = tonumber(section.dangerItem) or fallback.dangerItem
  section.normalItem = tonumber(section.normalItem) or fallback.normalItem

  -- Variables modo Spell
  section.spellOn = section.spellOn or fallback.spellOn
  section.spellOff = section.spellOff or fallback.spellOff

  local spellItemId = tonumber(section.manaItemId)
  if spellItemId == 268 then spellItemId = nil end

  section.manaItemId = spellItemId or fallback.manaItemId
  section.manaItemMp = tonumber(section.shieldItemHp) or tonumber(section.manaItemHp) or tonumber(section.manaItemMp) or fallback.manaItemMp
  section.shieldItemHp = section.manaItemMp

  if section.removeAt <= section.hpAt then
    section.removeAt = math.min(100, section.hpAt + 2)
  end

  return section
end

if type(storage[panelName]) ~= "table" then
  storage[panelName] = {}
end

local config = storage[panelName]

if config.enabled == nil then config.enabled = false end

config.ering = normalizeEringSection(config.ering, {
  enabled = true,
  mode = "ring",
  hpAt = config.equipAt or 75,
  removeAt = config.removeAt or config.manaAt or 90,
  dangerItem = 3051,
  normalItem = config.normalRing or 3004,
  spellOn = "utamo vita",
  spellOff = "exana vita",
  manaItemId = 35563,
  manaItemMp = 50
})

config.ring = normalizeSection(config.ring, defaultSection(false, 70, 70, 3048, config.normalRing or 3004))
config.amulet = normalizeSection(config.amulet, defaultSection(false, 80, 80, 3081, 0))

-- =========================
-- CONFIG INTERNA
-- =========================
local safeDelay = 2000
local damageSampleMs = 100
local moveDelayMin = 50

local dangerActionButtons = {
  ering = "8.3",
  ring = "7.2",
  amulet = "8.2"
}

local function registerCounterItem(id, name, aliases)
  id = tonumber(id)
  if not id or id <= 0 or not vBot.ItemCounter then return end

  if vBot.ItemCounter.registerItemId then
    vBot.ItemCounter.registerItemId(id)
  end

  if vBot.ItemCounter.register then
    vBot.ItemCounter.register(id, name, aliases, true)
  end
end

local function registerCounterItems()
  registerCounterItem(config.amulet.dangerItem, "stone skin amulet", {"stone skin amulets", "ssa"})
  registerCounterItem(config.ring.dangerItem, "might ring", {"might rings", "mr"})
  registerCounterItem(config.ering.dangerItem, "energy ring", {"energy rings", "ering", "e-ring"})
end

local function counterValue(id)
  id = tonumber(id)
  if not id or id <= 0 then return "?" end
  if not vBot.ItemCounter or not vBot.ItemCounter.format then return "?" end

  if vBot.ItemCounter.getAmount then
    vBot.ItemCounter.getAmount(id, player:getItemsCount(id) or 0)
  end

  return vBot.ItemCounter.format(id)
end

local function updateCounterLabel()
  if not ui.counts then return end

  ui.counts:setText(
    "SSA: " .. counterValue(config.amulet.dangerItem) ..
    "  MR: " .. counterValue(config.ring.dangerItem) ..
    "  ER: " .. counterValue(config.ering.dangerItem)
  )
end

registerCounterItems()

local protectWindow = nil

local fingerSlot = SlotFinger or InventorySlotFinger or 9
local neckSlot = SlotNeck or InventorySlotNecklace or InventorySlotNeck or 2
local backSlot = SlotBack or InventorySlotBack or 3

local lastDangerAt = now or 0

local lastSlotDangerAt = {
  finger = now or 0,
  neck = now or 0
}

local lastSampleAt = now or 0
local lastHp = hppercent() or 100
local lastMana = manapercent() or 100

local lastMove = {
  finger = 0,
  neck = 0,
  manaItem = 0
}

local lastSpellCast = 0
local lastUtamoCast = 0
local spellDelay = 1000
local utamoCooldown = 14000
local shieldItemDelay = 1000

-- Pendiente de poner ring normal después de quitar Energy Ring.
-- OJO: Esto NO bloquea Might Ring.
local eringPendingNormal = false

-- =========================
-- FUNCIONES UI
-- =========================
local function setSwitch(widget, value)
  widget:setOn(value)
end

local function updateEringLabel(panel, section)
  local prefix = section.mode == "ring" and "ERing" or "Utamo"
  panel.label:setText(prefix .. " ON <= " .. section.hpAt .. "%  OFF >= " .. section.removeAt .. "%")
end

local function syncEringRemove(section, panel)
  if section.removeAt <= section.hpAt then
    section.removeAt = math.min(100, section.hpAt + 2)
    panel.mpThreshold:setValue(section.removeAt)
  end
end

local function bindEringSection(panel, section)
  setSwitch(panel.enabled, section.enabled)

  panel.enabled.onClick = function(widget)
    section.enabled = not section.enabled
    setSwitch(widget, section.enabled)
  end

  local function updateView()
    if section.mode == "ring" then
      panel.modeBtn:setText("Mode: Ring")
      panel.ringMode:setVisible(true)
      panel.spellMode:setVisible(false)
    else
      panel.modeBtn:setText("Mode: Spell")
      panel.ringMode:setVisible(false)
      panel.spellMode:setVisible(true)
    end

    updateEringLabel(panel, section)
  end

  panel.modeBtn.onClick = function()
    section.mode = section.mode == "ring" and "spell" or "ring"
    updateView()
  end

  panel.hpThreshold:setValue(section.hpAt)
  panel.hpThreshold.onValueChange = function(scroll, value)
    section.hpAt = value
    syncEringRemove(section, panel)
    updateEringLabel(panel, section)
  end

  panel.mpThreshold:setValue(section.removeAt)
  panel.mpThreshold.onValueChange = function(scroll, value)
    section.removeAt = value
    syncEringRemove(section, panel)
    updateEringLabel(panel, section)
  end

  local rm = panel.ringMode

  rm.dangerItem:setItemId(section.dangerItem)
  rm.dangerItem.onItemChange = function(widget)
    section.dangerItem = widget:getItemId()
    registerCounterItems()
    updateCounterLabel()
  end

  rm.normalItem:setItemId(section.normalItem)
  rm.normalItem.onItemChange = function(widget)
    section.normalItem = widget:getItemId()
  end

  local sm = panel.spellMode

  sm.spellOn:setText(section.spellOn)
  sm.spellOn.onTextChange = function(widget, text)
    section.spellOn = text
  end

  sm.spellOff:setText(section.spellOff)
  sm.spellOff.onTextChange = function(widget, text)
    section.spellOff = text
  end

  sm.manaItem:setItemId(section.manaItemId)
  sm.manaItem.onItemChange = function(widget)
    section.manaItemId = widget:getItemId()
  end

  sm.manaPctLabel:setText((section.manaItemMp or 50) .. "%")
  sm.manaItemThreshold:setValue(section.manaItemMp or 50)
  sm.manaItemThreshold.onValueChange = function(scroll, value)
    section.manaItemMp = value
    section.shieldItemHp = value
    sm.manaPctLabel:setText(value .. "%")
  end

  updateView()
end

local function updateSectionLabel(panel, section, title)
  panel.label:setText(title .. " HP <= " .. section.hpAt .. "% / MP <= " .. section.mpAt .. "%")
end

local function bindSection(panel, section, title)
  setSwitch(panel.enabled, section.enabled)

  panel.enabled.onClick = function(widget)
    section.enabled = not section.enabled
    setSwitch(widget, section.enabled)
  end

  panel.hpThreshold:setValue(section.hpAt)
  panel.hpThreshold.onValueChange = function(scroll, value)
    section.hpAt = value
    updateSectionLabel(panel, section, title)
  end

  panel.mpThreshold:setValue(section.mpAt)
  panel.mpThreshold.onValueChange = function(scroll, value)
    section.mpAt = value
    updateSectionLabel(panel, section, title)
  end

  panel.dangerItem:setItemId(section.dangerItem)
  panel.dangerItem.onItemChange = function(widget)
    section.dangerItem = widget:getItemId()
    registerCounterItems()
    updateCounterLabel()
  end

  panel.normalItem:setItemId(section.normalItem)
  panel.normalItem.onItemChange = function(widget)
    section.normalItem = widget:getItemId()
  end

  updateSectionLabel(panel, section, title)
end

-- =========================
-- CREACIÓN DE VENTANA SETUP
-- =========================
local rootWidget = g_ui.getRootWidget()

if rootWidget then
  protectWindow = UI.createWindow('AutoProtectWindow', rootWidget)
  protectWindow:hide()

  protectWindow.closeButton.onClick = function()
    protectWindow:hide()
  end

  ui.setup.onClick = function()
    protectWindow:show()
    protectWindow:raise()
    protectWindow:focus()
  end

  bindEringSection(protectWindow.ering, config.ering)
  bindSection(protectWindow.ring, config.ring, "Ring")
  bindSection(protectWindow.amulet, config.amulet, "Amulet")
end

-- =========================
-- CONTROL DE ENCENDIDO
-- =========================
local function setProtectEnabled(enabled)
  if enabled and ERing and ERing.isOn and ERing.isOn() and ERing.setOff then
    pcall(ERing.setOff)
  end

  config.enabled = enabled == true
  ui.title:setOn(config.enabled)
end

Inmortal = Inmortal or {}

function Inmortal.setOn()
  setProtectEnabled(true)
end

function Inmortal.setOff()
  setProtectEnabled(false)
end

function Inmortal.isOn()
  return config.enabled == true
end

setProtectEnabled(config.enabled)

ui.title.onClick = function()
  setProtectEnabled(not config.enabled)
end

-- =========================
-- FUNCIONES DE ITEMS
-- =========================
local function activeId(itemId)
  if getActiveItemId then return getActiveItemId(itemId) end
  if itemId == 3051 then return 3088 end
  return itemId
end

local function inactiveId(itemId)
  if getInactiveItemId then return getInactiveItemId(itemId) end
  if itemId == 3088 then return 3051 end
  return itemId
end

local function isEquipped(slotItem, itemId)
  if not slotItem or not itemId or itemId <= 0 then return false end

  local slotId = slotItem:getId()

  return slotId == itemId or slotId == activeId(itemId) or inactiveId(slotId) == itemId
end

local counterSuppressUntil = {
  finger = 0,
  neck = 0
}

local lastCounterSlotId = {
  finger = false,
  neck = false
}

local lastCounterLabelAt = 0

local function trackedCounterId(slotItem)
  if not slotItem then return nil end

  local tracked = {
    config.ering.dangerItem,
    config.ring.dangerItem,
    config.amulet.dangerItem
  }

  for _, itemId in ipairs(tracked) do
    itemId = tonumber(itemId)

    if itemId and itemId > 0 and isEquipped(slotItem, itemId) then
      return itemId
    end
  end

  return nil
end

local function suppressCounterSlot(slotKey)
  counterSuppressUntil[slotKey] = now + 1500
end

local function updateCounterSlot(slotKey, slotItem)
  local currentId = trackedCounterId(slotItem)
  local previousId = lastCounterSlotId[slotKey]

  if previousId == false then
    lastCounterSlotId[slotKey] = currentId
    return
  end

  if previousId and previousId ~= currentId and now > (counterSuppressUntil[slotKey] or 0) then
    if vBot.ItemCounter and vBot.ItemCounter.adjust then
      vBot.ItemCounter.adjust(previousId, -1, "slot")
    end
  end

  lastCounterSlotId[slotKey] = currentId
end

local function updateCounterSlots()
  updateCounterSlot("finger", getFinger())
  updateCounterSlot("neck", getNeck())

  if now - lastCounterLabelAt > 250 then
    updateCounterLabel()
    lastCounterLabelAt = now
  end
end

local function canMove(slotKey)
  local pingDelay = g_game.getPing and g_game.getPing() * 2 or 0
  local delayMs = math.max(pingDelay, moveDelayMin)

  if now - (lastMove[slotKey] or 0) < delayMs then
    return false
  end

  lastMove[slotKey] = now
  return true
end

local function safeCall(fn, ...)
  if type(fn) ~= "function" then return false end
  local ok = pcall(fn, ...)
  return ok
end

local function executeActionButton(actionButtonId)
  if not actionButtonId or actionButtonId == "" then return false end

  if not (modules and modules.game_actionbar and modules.game_actionbar.onExecuteAction and g_ui) then
    return false
  end

  local root = g_ui.getRootWidget()
  local button = root and root:recursiveGetChildById(actionButtonId)

  if not button then return false end

  return safeCall(modules.game_actionbar.onExecuteAction, button)
end

local function equipItemById(itemId)
  if not itemId or itemId <= 0 then return false end

  if g_game.equipItemId and safeCall(g_game.equipItemId, itemId) then
    return true
  end

  if modules and modules.game_hotkeys then
    if modules.game_hotkeys.useHotkeyItem and safeCall(modules.game_hotkeys.useHotkeyItem, itemId) then
      return true
    end

    if modules.game_hotkeys.useHotkeyItemWith and safeCall(modules.game_hotkeys.useHotkeyItemWith, itemId, player) then
      return true
    end
  end

  if g_game.useInventoryItem and safeCall(g_game.useInventoryItem, itemId) then
    return true
  end

  if g_game.useInventoryItemWith and safeCall(g_game.useInventoryItemWith, itemId, player) then
    return true
  end

  return false
end

local function useItemOnSelf(itemId)
  if not itemId or itemId <= 0 then return false end

  if g_game.useInventoryItemWith and safeCall(g_game.useInventoryItemWith, itemId, player) then
    return true
  end

  if useWith and safeCall(useWith, itemId, player) then
    return true
  end

  if g_game.useInventoryItem and safeCall(g_game.useInventoryItem, itemId) then
    return true
  end

  return false
end

local function findItemSmart(itemId)
  if not itemId or itemId <= 0 then return nil end

  local ids = {
    itemId,
    inactiveId(itemId),
    activeId(itemId)
  }

  for _, id in ipairs(ids) do
    if id and id > 0 then
      local item = findItem(id)

      if item then
        return item
      end
    end
  end

  return nil
end

local function moveItemToSlot(itemId, slot, slotKey)
  if not itemId or itemId <= 0 then return false end

  local item = findItemSmart(itemId)

  if item and canMove(slotKey) then
    suppressCounterSlot(slotKey)
    g_game.move(item, {x = 65535, y = slot, z = 0}, 1)
    return true
  end

  return false
end

local function equipDangerItem(itemId, slot, slotKey, actionButtonId)
  if not itemId or itemId <= 0 then return false end
  if not canMove(slotKey) then return false end

  suppressCounterSlot(slotKey)

  local item = findItemSmart(itemId)

  if item then
    g_game.move(item, {x = 65535, y = slot, z = 0}, 1)
    return true
  end

  if equipItemById(itemId) then return true end
  if executeActionButton(actionButtonId) then return true end

  return false
end

local function unequipToBack(slotItem, slotKey)
  if not slotItem then return false end

  if canMove(slotKey) then
    suppressCounterSlot(slotKey)
    g_game.move(slotItem, {x = 65535, y = backSlot, z = 0}, 1)
    return true
  end

  return false
end

-- =========================
-- CONDICIONES
-- =========================
local function sectionDanger(section)
  if not section.enabled then return false end
  if not section.dangerItem or section.dangerItem <= 0 then return false end

  local hp = hppercent() or 100
  local mp = manapercent() or 100

  return hp <= (section.hpAt or 75) or mp <= (section.mpAt or 75)
end

local function markSlotDanger(slotKey)
  lastDangerAt = now
  lastSlotDangerAt[slotKey] = now
end

local function slotSafe(slotKey)
  return now - (lastSlotDangerAt[slotKey] or 0) >= safeDelay
end

-- =========================
-- TIMER DE DAÑO CORREGIDO
-- =========================
local function updateDangerTimer()
  if now - lastSampleAt < damageSampleMs then return end

  local hp = hppercent() or 100
  local mana = manapercent() or 100

  -- Solo la bajada de HP cuenta como daño real.
  -- NO uses bajada de mana aquí, porque el Energy Ring puede bajar mana
  -- y eso impedía que se quitara.
  if hp < lastHp then
    lastDangerAt = now
    lastSlotDangerAt.finger = now
    lastSlotDangerAt.neck = now
  end

  lastHp = hp
  lastMana = mana
  lastSampleAt = now
end

-- =========================
-- MODO SPELL / UTAMO
-- =========================
local function handleSpellShield()
  if not config.ering.enabled or config.ering.mode ~= "spell" then return end

  local hp = hppercent() or 100
  local hasShield = hasManaShield()

  if hp <= config.ering.hpAt then
    lastDangerAt = now

    if not hasShield and now - lastUtamoCast > utamoCooldown then
      say(config.ering.spellOn)
      lastUtamoCast = now
    end
  end

  if hp >= config.ering.removeAt then
    if hasShield and now - lastSpellCast > spellDelay then
      say(config.ering.spellOff)
      lastSpellCast = now
    end
  end

  if config.ering.manaItemId and config.ering.manaItemId > 0 then
    local itemHp = config.ering.shieldItemHp or config.ering.manaItemMp or 50
    local utamoWasTried = lastUtamoCast > 0
    local utamoOnCooldown = utamoWasTried and now - lastUtamoCast < utamoCooldown
    local waitAfterSpell = now - lastUtamoCast > 250

    if hp <= itemHp and not hasShield and utamoOnCooldown and waitAfterSpell then
      if now - (lastMove["manaItem"] or 0) > shieldItemDelay then
        useItemOnSelf(config.ering.manaItemId)
        lastMove["manaItem"] = now
      end
    end
  end
end

-- =========================
-- FINGER / ENERGY RING + MIGHT RING
-- =========================
local function handleFinger()
  local finger = getFinger()
  local hp = hppercent() or 100

  -- =====================================================
  -- ENERGY RING TIENE CONTROL TOTAL SOLO MIENTRAS ESTÁ PUESTO
  -- =====================================================
  if config.ering.enabled and config.ering.mode == "ring" and config.ering.dangerItem and config.ering.dangerItem > 0 then
    local eringEquipped = isEquipped(finger, config.ering.dangerItem)
    local eringHpAt = config.ering.hpAt or 75
    local eringRemoveAt = config.ering.removeAt or math.min(100, eringHpAt + 2)

    -- Si baja al HP de Energy Ring, se pone y cancela espera de ring normal.
    if hp <= eringHpAt then
      eringPendingNormal = false
      markSlotDanger("finger")

      if not eringEquipped then
        equipDangerItem(config.ering.dangerItem, fingerSlot, "finger", dangerActionButtons.ering)
      end

      return
    end

    -- Si el Energy Ring está puesto y aún no llega al HP de quitarse,
    -- Might Ring NO debe pelear.
    if eringEquipped and hp < eringRemoveAt then
      markSlotDanger("finger")
      return
    end

    -- Si el Energy Ring está puesto y ya llegó al HP de OFF,
    -- se quita inmediatamente. NO espera los 2 segundos.
    if eringEquipped and hp >= eringRemoveAt then
      if unequipToBack(finger, "finger") then
        -- Solo queda pendiente poner ring normal después de 2s.
        -- Esto NO bloquea al Might Ring.
        eringPendingNormal = true
        lastSlotDangerAt.finger = now
      end

      return
    end
  else
    eringPendingNormal = false
  end

  -- =====================================================
  -- MIGHT RING / RING DE PELIGRO
  -- Ya puede funcionar si Energy Ring NO está equipado.
  -- Si entra Might Ring, cancelamos el pendiente de ring normal.
  -- =====================================================
  finger = getFinger()

  local ringEquipped = isEquipped(finger, config.ring.dangerItem)

  if sectionDanger(config.ring) then
    eringPendingNormal = false
    markSlotDanger("finger")

    if not ringEquipped then
      equipDangerItem(config.ring.dangerItem, fingerSlot, "finger", dangerActionButtons.ring)
    end

    return
  end

  -- =====================================================
  -- RING NORMAL DESPUÉS DEL ENERGY RING
  -- Este sí debe esperar 2 segundos sin recibir daño.
  -- =====================================================
  if eringPendingNormal then
    if not slotSafe("finger") then
      return
    end

    local normalAfterEring = config.ering.normalItem or 0

    if normalAfterEring and normalAfterEring > 0 then
      finger = getFinger()

      if not isEquipped(finger, normalAfterEring) then
        moveItemToSlot(normalAfterEring, fingerSlot, "finger")
      end
    end

    eringPendingNormal = false
    return
  end

  -- =====================================================
  -- NORMAL RING DEL SISTEMA DE MIGHT RING
  -- =====================================================
  if not slotSafe("finger") then return end

  local normalRing = 0

  if config.ring.enabled and config.ring.normalItem and config.ring.normalItem > 0 then
    normalRing = config.ring.normalItem
  end

  if normalRing and normalRing > 0 then
    if not isEquipped(finger, normalRing) then
      if not moveItemToSlot(normalRing, fingerSlot, "finger") and ringEquipped then
        unequipToBack(finger, "finger")
      end
    end

    return
  end

  -- Si NO hay normal ring configurado, quitar solo el ring de peligro.
  if finger and ringEquipped then
    unequipToBack(finger, "finger")
  end
end

-- =========================
-- NECK / SSA
-- =========================
local function handleNeck()
  local neck = getNeck()
  local amuletEquipped = isEquipped(neck, config.amulet.dangerItem)

  -- SSA / Amulet de peligro
  if sectionDanger(config.amulet) then
    markSlotDanger("neck")

    if not amuletEquipped then
      equipDangerItem(config.amulet.dangerItem, neckSlot, "neck", dangerActionButtons.amulet)
    end

    return
  end

  -- Esperar 2 segundos sin perder HP.
  if not slotSafe("neck") then return end

  local normalAmulet = 0

  if config.amulet.enabled and config.amulet.normalItem and config.amulet.normalItem > 0 then
    normalAmulet = config.amulet.normalItem
  end

  if normalAmulet and normalAmulet > 0 then
    if not isEquipped(neck, normalAmulet) then
      if not moveItemToSlot(normalAmulet, neckSlot, "neck") and amuletEquipped then
        unequipToBack(neck, "neck")
      end
    end

    return
  end

  -- Si NO hay normal amulet configurado, quitar solo el amulet de peligro.
  if neck and amuletEquipped then
    unequipToBack(neck, "neck")
  end
end

-- =========================
-- MACRO PRINCIPAL
-- =========================
macro(20, function()
  updateCounterSlots()

  if not config.enabled then return end

  updateDangerTimer()
  handleSpellShield()
  handleFinger()
  handleNeck()
end)
