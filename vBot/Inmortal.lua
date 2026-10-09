-- Inmortal: Energy Ring/Might Ring/Amulet Protector
-- Energy Ring + Might Ring + Amulet editable
-- Corregido para OTC/vBot v15:
-- 1) El Energy Ring se quita inmediatamente al llegar al HP de OFF.
-- 2) MR/SSA se conservan hasta consumirse; el normal espera recuperacion.
-- 3) El Might Ring NO pelea contra el Energy Ring mientras el Energy Ring está puesto.
-- 4) Después de quitarse el Energy Ring, el Might Ring ya puede funcionar inmediatamente.
-- 5) La recuperacion exige HP/MP al menos 10 puntos sobre sus limites.

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
    height: 17
    font: verdana-11px-rounded
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
config.hudEnabled = config.hudEnabled ~= false

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
local safeDelay = 500
local safeMargin = 10
local safeSince = {}
local moveDelayMin = 35
local moveDelayMax = 110
local globalMoveGap = 25

local dangerActionButtons = {
  ering = "8.3",
  ring = "7.2",
  amulet = "8.2"
}

local function registerCounterItem(id, name, aliases, keepOnUse)
  id = tonumber(id)
  if not id or id <= 0 or not vBot.ItemCounter then return end

  if vBot.ItemCounter.registerItemId then
    vBot.ItemCounter.registerItemId(id)
  end

  if vBot.ItemCounter.register then
    vBot.ItemCounter.register(id, name, aliases, keepOnUse ~= false)
  end

  if vBot.ItemCounter.registerWatchItem then
    vBot.ItemCounter.registerWatchItem(id)
  end
end

local function registerCounterItems()
  registerCounterItem(config.amulet.dangerItem, "stone skin amulet", {"stone skin amulets", "ssa"})
  registerCounterItem(config.ring.dangerItem, "might ring", {"might rings", "mr"})
  registerCounterItem(config.ering.dangerItem, "energy ring", {"energy rings", "ering", "e-ring"})
  registerCounterItem(3081, "stone skin amulet", {"stone skin amulets", "ssa"})
  registerCounterItem(3048, "might ring", {"might rings", "mr"})
  -- Let the client supply the potion's actual name for Server Log matching.
  registerCounterItem(35563, nil, nil, false)
end

local nativeCounterTotals = {}
local counterSnapshots = {}
local function counterValue(id)
  id = tonumber(id)
  if not id or id <= 0 then return "?" end
  if not vBot.ItemCounter or not vBot.ItemCounter.format then return "?" end

  local counter = vBot.ItemCounter
  -- Item Counter can rebuild its watch list when its editor opens.
  local watched = storage.itemCounter and storage.itemCounter.watchItems
  if counter.registerWatchItem and not (watched and watched[tostring(id)]) then
    counter.registerWatchItem(id)
  end
  local snapshot = counterSnapshots[id]
  local interval = nativeCounterTotals[id] and 250 or 1000
  if not snapshot or now - snapshot.at >= interval then
    local total
    if type(player.getInventoryCount) == "function" then
      local ok, value = pcall(player.getInventoryCount, player, id, 0)
      total = ok and tonumber(value) or nil
    end
    local visible = snapshot and snapshot.visible or 0
    if not nativeCounterTotals[id] or not total or total < 0 then
      visible = player:getItemsCount(id) or 0
    end
    if total and total >= 0 and total > visible then nativeCounterTotals[id] = true end
    snapshot = {at=now, total=total, visible=visible}
    counterSnapshots[id] = snapshot
  end
  local total, visible = snapshot.total, snapshot.visible
  if total and total >= 0 and nativeCounterTotals[id] then
    if counter.set and (not counter.get or counter.get(id) ~= total) then
      counter.set(id, total, "confirmed", 0)
    end
    return tostring(total)
  end
  if counter.getAmount then counter.getAmount(id, visible) end
  -- Closing a BP must not turn its last known stock into zero.
  if visible > 0 and counter.set and counter.getSource and counter.getSource(id) == "visible" then
    counter.set(id, counter.get and counter.get(id) or visible, "confirmed", 0)
  end

  local text = counter.format(id)
  local known = tonumber(text)
  return known and known > visible and "~" .. text or text
end

local protectWindow = nil
-- Use the same map parent/style as CaveBot HUD, anchored to the opposite corner.
-- setupUI registers this widget for the bot's normal reload cleanup.
local hudPanel = setupUI([[
InmortalHudLabel < Label
  height: 12
  text-auto-resize: true
  font: verdana-11px-rounded
  text-align: left
  color: #ffffff
  phantom: true
  focusable: false

InmortalHudRow < Panel
  height: 12
  background-color: #00000055
  opacity: 0.92
  phantom: true
  focusable: false
  anchors.left: parent.left
  anchors.right: parent.right

  InmortalHudLabel
    id: caption
    anchors.top: parent.top
    anchors.left: parent.left

  InmortalHudLabel
    id: amount
    anchors.top: parent.top
    anchors.right: parent.right
    text-align: right
    color: #ffd166

Panel
  id: inmortalHudPanel
  width: 1
  height: 36
  anchors.right: parent.right
  anchors.bottom: parent.bottom
  margin-right: 5
  margin-bottom: 5
  phantom: true
  focusable: false

  InmortalHudRow
    id: ssa
    anchors.top: parent.top

  InmortalHudRow
    id: rings
    anchors.top: prev.bottom

  InmortalHudRow
    id: potion
    anchors.top: prev.bottom
]], modules.game_interface.getMapPanel())
hudPanel.ssa.caption:setText("~ SSA:")
hudPanel.rings.caption:setText("~ Might Rings:")
hudPanel.potion.caption:setText("~ MSP:")
local hudCaptionWidth = math.max(hudPanel.ssa.caption:getWidth(), hudPanel.rings.caption:getWidth(), hudPanel.potion.caption:getWidth())
hudPanel:setVisible(config.hudEnabled)

local lastCounterText
local function updateCounterLabel()
  local ssa, rings, potion = counterValue(3081), counterValue(3048), counterValue(35563)
  local text = "SSA: " .. ssa .. "  MR: " .. rings .. "  MSP: " .. potion
  if text == lastCounterText then return end
  hudPanel.ssa.amount:setText(ssa)
  hudPanel.rings.amount:setText(rings)
  hudPanel.potion.amount:setText(potion)
  local amountWidth = math.max(hudPanel.ssa.amount:getWidth(), hudPanel.rings.amount:getWidth(), hudPanel.potion.amount:getWidth())
  hudPanel:setWidth(hudCaptionWidth + 6 + amountWidth)
  if protectWindow and protectWindow.counts then
    protectWindow.counts:setColoredText({
      "SSA: ", "#ffffff", ssa, "#ffff00",
      "  MR: ", "#ffffff", rings, "#ffff00",
      "  MSP: ", "#ffffff", potion, "#ffff00"
    })
  end
  lastCounterText = text
end

registerCounterItems()

local fingerSlot = SlotFinger or InventorySlotFinger or 9
local neckSlot = SlotNeck or InventorySlotNecklace or InventorySlotNeck or 2
local backSlot = SlotBack or InventorySlotBack or 3

local lastMove = {
  finger = 0,
  neck = 0,
  manaItem = 0
}
local lastGlobalMove = 0
local itemSearchAfter = {}
local visibleEquipIds = {}
local actionButtonCache = {}
local pendingEquip = {}
local nativeFallback = {}
local counterNeedsSync = false

local shieldItemDelay = 1000

-- Pendiente de poner ring normal después de quitar Energy Ring.
-- OJO: Esto NO bloquea Might Ring.
local eringPendingNormal = false
local resumeMightAfterEring = false

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
  protectWindow:setText("Inmortal by Sabuezo")
  protectWindow:hide()

  protectWindow.closeButton.onClick = function()
    protectWindow:hide()
  end

  protectWindow.showHud:setOn(config.hudEnabled)
  protectWindow.showHud.onClick = function(widget)
    config.hudEnabled = not config.hudEnabled
    widget:setOn(config.hudEnabled)
    hudPanel:setVisible(config.hudEnabled)
    updateCounterLabel()
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
updateCounterLabel()

-- =========================
-- CONTROL DE ENCENDIDO
-- =========================
local function setProtectEnabled(enabled)
  if enabled and ERing and ERing.isOn and ERing.isOn() and ERing.setOff then
    pcall(ERing.setOff)
  end

  config.enabled = enabled == true
  safeSince.finger, safeSince.neck = nil, nil
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
local counterExpectedId = {}

local lastCounterSlotId = {
  finger = false,
  neck = false
}

local lastCounterLabelAt = 0

local function matchCounterId(slotId, inactiveSlotId, itemId)
  itemId = tonumber(itemId)
  if itemId and itemId > 0 and
      (slotId == itemId or slotId == activeId(itemId) or inactiveSlotId == itemId) then
    return itemId
  end
  return nil
end

local function trackedCounterId(slotItem)
  if not slotItem then return nil end

  local slotId = slotItem:getId()
  local inactiveSlotId = inactiveId(slotId)
  return matchCounterId(slotId, inactiveSlotId, config.ering.dangerItem) or
    matchCounterId(slotId, inactiveSlotId, config.ring.dangerItem) or
    matchCounterId(slotId, inactiveSlotId, config.amulet.dangerItem)
end

local function suppressCounterSlot(slotKey, itemId)
  counterSuppressUntil[slotKey] = now + 1500
  itemId = tonumber(itemId) or 0
  counterExpectedId[slotKey] = itemId > 0 and (
    matchCounterId(itemId, inactiveId(itemId), config.ering.dangerItem) or
    matchCounterId(itemId, inactiveId(itemId), config.ring.dangerItem) or
    matchCounterId(itemId, inactiveId(itemId), config.amulet.dangerItem)) or false
end

local function updateCounterSlot(slotKey, slotItem)
  local currentId = trackedCounterId(slotItem)
  local previousId = lastCounterSlotId[slotKey]

  if previousId == false then
    lastCounterSlotId[slotKey] = currentId
    return
  end

  local ownMove = now <= (counterSuppressUntil[slotKey] or 0) and
    counterExpectedId[slotKey] ~= nil and (currentId or false) == counterExpectedId[slotKey]
  if ownMove then
    -- Suppress just the acknowledged swap, never later consumption during
    -- the same 1.5-second window (a low-charge SSA may expire immediately).
    counterSuppressUntil[slotKey], counterExpectedId[slotKey] = 0, nil
  end
  if previousId and previousId ~= currentId and not ownMove then
    if vBot.ItemCounter and vBot.ItemCounter.adjust then
      vBot.ItemCounter.adjust(previousId, -1, "slot")
    end
  end

  lastCounterSlotId[slotKey] = currentId
end

local function updateCounterSlots()
  updateCounterSlot("finger", getFinger())
  updateCounterSlot("neck", getNeck())
end

local function canMove(slotKey)
  local pending = pendingEquip[slotKey]
  if pending and now < pending.untilAt then return false end
  if pending then
    nativeFallback[slotKey] = {id=pending.id, removing=pending.removing, untilAt=now+1000}
  end
  pendingEquip[slotKey] = nil
  local ping = g_game.getPing and tonumber(g_game.getPing()) or 0
  local delayMs = math.max(moveDelayMin, math.min(moveDelayMax, math.floor((ping * 0.65) + 20)))

  if now - (lastMove[slotKey] or 0) < delayMs then
    return false
  end

  if now - lastGlobalMove < globalMoveGap then return false end

  return true
end

local function markMove(slotKey)
  lastMove[slotKey] = now
  lastGlobalMove = now
end

local function markNativeMove(slotKey, itemId, removing)
  suppressCounterSlot(slotKey, not removing and itemId or 0)
  markMove(slotKey)
  nativeFallback[slotKey] = nil
  local ping = g_game.getPing and tonumber(g_game.getPing()) or 0
  pendingEquip[slotKey] = {
    id=itemId, removing=removing,
    untilAt=now + math.max(200, math.min(1000, ping*2+100))
  }
end

local function observeEquipment(slotKey, item)
  local pending = pendingEquip[slotKey]
  if not pending then return end
  local equipped = isEquipped(item, pending.id)
  if pending.removing and not equipped or not pending.removing and equipped then
    pendingEquip[slotKey] = nil
  end
end

local function safeCall(fn, ...)
  if type(fn) ~= "function" then return false end
  local ok, result = pcall(fn, ...)
  return ok and result ~= false
end

local function executeActionButton(actionButtonId)
  if not actionButtonId or actionButtonId == "" then return false end

  if not (modules and modules.game_actionbar and modules.game_actionbar.onExecuteAction and g_ui) then
    return false
  end

  local button = actionButtonCache[actionButtonId]
  if not button then
    local root = g_ui.getRootWidget()
    button = root and root:recursiveGetChildById(actionButtonId)
    if button then actionButtonCache[actionButtonId] = button end
  end

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
  if now < (itemSearchAfter[itemId] or 0) then return nil end

  local ids = {
    itemId,
    inactiveId(itemId),
    activeId(itemId)
  }

  for _, id in ipairs(ids) do
    if id and id > 0 then
      local item = findItem(id)

      -- Some clients omit loot containers from findItem. The Loot Pouch in
      -- the purse is also a valid supply source, regardless of that flag.
      if not item then
        for _, container in pairs(g_game.getContainers()) do
          for _, candidate in ipairs(container:getItems()) do
            if candidate:getId() == id then item = candidate; break end
          end
          if item then break end
        end
      end

      if item then
        itemSearchAfter[itemId] = 0
        return item
      end
    end
  end

  itemSearchAfter[itemId] = now + 60
  return nil
end

local supplyContainerHints = {}

local function findSupplyContainerId(itemId)
  local validIds = {[itemId] = true}
  local inactiveItemId = inactiveId(itemId)
  local activeItemId = activeId(itemId)
  if inactiveItemId then validIds[inactiveItemId] = true end
  if activeItemId then validIds[activeItemId] = true end

  for _, container in pairs(g_game.getContainers()) do
    for _, item in ipairs(container:getItems()) do
      if validIds[item:getId()] then
        local containerItem = container:getContainerItem()
        return containerItem and containerItem:getId() or nil
      end
    end
  end

  return nil
end

local function maintainSupplyContainer(section, supplyKey)
  if not section.enabled then return end

  local itemId = tonumber(section.dangerItem)
  if not itemId or itemId <= 0 then return end

  local containerId = findSupplyContainerId(itemId)
  if containerId then
    supplyContainerHints[itemId] = containerId
    return
  end

  if ContainerManager and ContainerManager.requestItemContainer then
    pcall(ContainerManager.requestItemContainer, itemId, supplyContainerHints[itemId], {
      config.ering.dangerItem,
      config.ring.dangerItem,
      config.amulet.dangerItem
    }, supplyKey)
  end
end

local purseOpenAfter = 0
local purseChildren = {}
local function requestPurseSupply()
  if now < purseOpenAfter then return end
  local purse
  if type(getPurse) == "function" then
    local ok, value = pcall(getPurse)
    if ok then purse = value end
  end
  if not purse and player and type(player.getInventoryItem) == "function" then
    local ok, value = pcall(player.getInventoryItem, player, SlotPurse or InventorySlotPurse or 11)
    if ok then purse = value end
  end
  if not purse then return end

  local containers, opened = g_game.getContainers(), {}
  local root
  for _, container in pairs(containers) do
    local containerItem = container:getContainerItem()
    if containerItem then
      local id = containerItem:getId()
      opened[id] = true
      if id == purse:getId() then root = container end
    end
  end
  -- Only open branches discovered inside the equipped purse, never arbitrary
  -- ground containers. This also handles a server-specific Loot Pouch ID.
  if not root then
    if safeCall(g_game.open, purse) then purseOpenAfter = now + 1000 end
    return
  end
  for _, container in pairs(containers) do
    local containerItem = container:getContainerItem()
    if container == root or containerItem and purseChildren[containerItem:getId()] then
      for _, item in ipairs(container:getItems()) do
        if item.isContainer and item:isContainer() then
          local id = item:getId()
          purseChildren[id] = true
          if not opened[id] and safeCall(g_game.open, item) then
            purseOpenAfter = now + 1000
            return
          end
        end
      end
    end
  end
  purseOpenAfter = now + 1000
end

local urgentSupplyAfter = {}
local function requestDangerSupply(itemId)
  itemId = tonumber(itemId)
  if not itemId or now < (urgentSupplyAfter[itemId] or 0) then return end
  urgentSupplyAfter[itemId] = now + 250
  requestPurseSupply()

  if itemId == tonumber(config.amulet.dangerItem) then
    maintainSupplyContainer(config.amulet, "ssa")
  elseif itemId == tonumber(config.ring.dangerItem) then
    maintainSupplyContainer(config.ring, "might")
  elseif itemId == tonumber(config.ering.dangerItem) then
    maintainSupplyContainer(config.ering, "ering")
  end
end

local function unequipToBack(slotItem, slotKey)
  if not slotItem or not canMove(slotKey) then return false end
  -- Address the equipped main BP directly, even when its window is closed.
  -- Do not toggle equip-by-ID: that lets the server choose the source BP.
  local back = type(getBack) == "function" and getBack() or nil
  if not back then return false end
  local outgoingId = slotItem:getId()
  if safeCall(g_game.move, slotItem, {x = 65535, y = backSlot, z = 0}, 1) then
    markNativeMove(slotKey, outgoingId, true)
    return true
  end
  return false
end

local function equipmentFor(slotKey)
  if slotKey == "finger" then return getFinger() end
  return getNeck()
end

local function moveItemToSlot(itemId, slot, slotKey)
  if not itemId or itemId <= 0 then return false end
  if not canMove(slotKey) then return false end

  local equipped = equipmentFor(slotKey)
  if isEquipped(equipped, itemId) then return true end
  -- First store the outgoing equipment in main BP. Wait for its inventory
  -- acknowledgement before equipping anything from a possibly full BP.
  if equipped then return unequipToBack(equipped, slotKey) end

  -- The server resolves the item by ID, including closed or hidden BPs.
  -- Prefer this for both danger and normal equipment.
  -- Once a visible source (including purse Loot Pouch) has worked, use it
  -- immediately for replacements instead of retrying a rejected native path.
  local item = visibleEquipIds[itemId] and findItemSmart(itemId) or nil
  local fallback = nativeFallback[slotKey]
  local tryVisible = fallback and now < fallback.untilAt and not fallback.removing and
    inactiveId(fallback.id) == inactiveId(itemId)
  if not item and not tryVisible and equipItemById(inactiveId(itemId)) then
    markNativeMove(slotKey, itemId, false)
    return true
  end

  item = item or findItemSmart(itemId)

  if item then
    if safeCall(g_game.move, item, {x = 65535, y = slot, z = 0}, 1) then
      visibleEquipIds[itemId] = true
      markNativeMove(slotKey, itemId, false)
      return true
    end
  end

  return false
end

local function equipDangerItem(itemId, slot, slotKey, actionButtonId)
  if not itemId or itemId <= 0 then return false end
  if not canMove(slotKey) then return false end
  if moveItemToSlot(itemId, slot, slotKey) then return true end

  requestDangerSupply(itemId)
  if not canMove(slotKey) then return false end
  -- A failed main-BP move must never fall through to an atomic swap.
  if equipmentFor(slotKey) then return false end

  if executeActionButton(actionButtonId) then
    markNativeMove(slotKey, itemId, false)
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
  safeSince[slotKey] = nil
end

local function slotSafe(slotKey)
  return safeSince[slotKey] ~= nil and now - safeSince[slotKey] >= safeDelay
end

local function sectionRecovered(section, hp, mp)
  if not section.enabled or not section.dangerItem or section.dangerItem <= 0 then return true end
  return hp >= math.min(100, (section.hpAt or 75) + safeMargin) and
    mp >= math.min(100, (section.mpAt or 75) + safeMargin)
end

local function updateSlotRecovery(slotKey, ready)
  if not ready then safeSince[slotKey] = nil
  elseif safeSince[slotKey] == nil then safeSince[slotKey] = now end
end

local function updateRecoveryTimers()
  local hp, mp = hppercent() or 100, manapercent() or 100
  local fingerRecovered = sectionRecovered(config.ring, hp, mp)
  if config.ering.enabled and config.ering.mode == "ring" and config.ering.dangerItem > 0 then
    fingerRecovered = fingerRecovered and hp >= math.min(100, config.ering.hpAt + safeMargin)
  end
  updateSlotRecovery("finger", fingerRecovered)
  updateSlotRecovery("neck", sectionRecovered(config.amulet, hp, mp))
end

local function normalGearBlocked()
  if sectionDanger(config.ring) or sectionDanger(config.amulet) then return true end
  if not config.ering.enabled then return false end
  local hp = hppercent() or 100
  if hp <= config.ering.hpAt then return true end
  local shield = config.ering.mode == "spell" and hasManaShield() or
    config.ering.mode == "ring" and isEquipped(getFinger(), config.ering.dangerItem)
  return shield and hp < config.ering.removeAt
end

-- =========================
-- MODO SPELL / UTAMO
-- =========================
local shieldSpellCooldowns, shieldGroupCooldowns = {}, {}
local shieldFallbackCooldowns, shieldFallbackGroups = {}, {}
local shieldSpellCache, shieldAttemptAt = {}, {}
local shieldUnobservedSince = {}
local shieldPending = nil
local shieldRejected = {}
local shieldPotionPendingUntil = 0
local lastShield = hasManaShield()

local function shieldPhrase(words)
  return tostring(words or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
end

local function shieldSpellData(words)
  local cached = shieldSpellCache[words]
  if cached and now < cached.untilAt then return cached.data end
  local data
  if type(getSpellData) == "function" then
    local ok, value = pcall(getSpellData, words)
    if ok and type(value) == "table" then data = value end
  end
  shieldSpellCache[words] = {data=data, untilAt=now+(data and 1000 or 100)}
  return data
end

local function confirmShieldSpell(words, castAt)
  words = shieldPhrase(words)
  local spellOn, spellOff = shieldPhrase(config.ering.spellOn), shieldPhrase(config.ering.spellOff)
  if words ~= spellOn and words ~= spellOff then return end
  local data = shieldSpellData(words)
  castAt = castAt or now
  -- These are compatibility fallbacks only. A sent/failed phrase never starts
  -- the full timer, and Utamo's individual cooldown never blocks Exana.
  shieldFallbackCooldowns[words] = castAt + (data and tonumber(data.exhaustion) or
    (words == spellOn and 14000 or 2000))
  local groups = data and data.group or {[3]=2000}
  if type(groups) == "table" then
    for group, duration in pairs(groups) do
      group, duration = tonumber(group), tonumber(duration)
      if group and duration then shieldFallbackGroups[group] = castAt + duration end
    end
  end
  if shieldPending and shieldPending.words == words then shieldPending = nil end
  shieldRejected[words] = nil
end

if type(onSpellCooldown) == "function" then
  onSpellCooldown(function(id, duration)
    id, duration = tonumber(id), tonumber(duration)
    if not id or not duration then return end
    shieldSpellCooldowns[id] = now + math.max(0, duration)
    if shieldPending then
      local data = shieldSpellData(shieldPending.words)
      if data and tonumber(data.id) == id then
        confirmShieldSpell(shieldPending.words, shieldPending.at)
      end
    end
  end)
end
if type(onGroupSpellCooldown) == "function" then
  onGroupSpellCooldown(function(id, duration)
    id, duration = tonumber(id), tonumber(duration)
    if id and duration then shieldGroupCooldowns[id] = now + math.max(0, duration) end
  end)
end
if type(onTalk) == "function" then
  onTalk(function(name, _, _, words)
    words = shieldPhrase(words)
    if words ~= shieldPhrase(config.ering.spellOn) and words ~= shieldPhrase(config.ering.spellOff) then return end
    local ok, ownName = pcall(function() return player:getName() end)
    if ok and ownName and name == ownName then
      confirmShieldSpell(words, shieldPending and shieldPending.words == words and shieldPending.at or now)
    end
  end)
end

local function shieldSpellBlocked(words)
  local data = shieldSpellData(words)
  local cooldown = modules and modules.game_cooldown
  local function blocked(expiresAt, api, id, fallbackAt, key, duration)
    if expiresAt then return now < expiresAt end -- server deadline also clears stale widgets
    if type(api) == "function" and id then
      local ok, active = pcall(api, id)
      if ok then
        if active ~= true then shieldUnobservedSince[key] = nil; return false end
        shieldUnobservedSince[key] = shieldUnobservedSince[key] or now
        return now - shieldUnobservedSince[key] < math.max(300, tonumber(duration) or 2000)
      end
    end
    return fallbackAt and now < fallbackAt or false
  end
  local id = data and tonumber(data.id)
  local onCooldown = blocked(id and shieldSpellCooldowns[id], cooldown and cooldown.isCooldownIconActive,
    id, shieldFallbackCooldowns[words], "spell:" .. words, data and data.exhaustion)
  local groups = data and data.group or {[3]=2000}
  if type(groups) == "table" then
    for group, duration in pairs(groups) do
      group = tonumber(group)
      if group then
        local groupBlocked = blocked(shieldGroupCooldowns[group], cooldown and cooldown.isGroupCooldownIconActive,
          group, shieldFallbackGroups[group], "group:" .. group, duration)
        onCooldown = groupBlocked or onCooldown
      end
    end
  end
  return onCooldown
end

local function tryShieldSpell(words)
  words = shieldPhrase(words)
  if words == "" or shieldSpellBlocked(words) then return false end
  local ping = g_game.getPing and tonumber(g_game.getPing()) or 0
  local retryDelay = math.max(250, math.min(600, ping * 2 + 80))
  if now - (shieldAttemptAt[words] or 0) < retryDelay then return false end
  shieldAttemptAt[words] = now
  -- Register before say: some clients synchronously report talk/cooldowns.
  shieldPending = {words=words, at=now}
  if safeCall(say, words) then shieldRejected[words] = nil; return true end
  shieldPending = nil
  shieldRejected[words] = true
  return false
end

local function handleSpellShield()
  if not config.ering.enabled or config.ering.mode ~= "spell" then return end

  local hp = hppercent() or 100
  local hasShield = hasManaShield()
  if hasShield ~= lastShield and shieldPending then
    local expected = hasShield and shieldPhrase(config.ering.spellOn) or shieldPhrase(config.ering.spellOff)
    if shieldPending.words == expected and now - shieldPending.at <= 1500 then
      confirmShieldSpell(expected, shieldPending.at)
    end
  end
  lastShield = hasShield
  if hasShield then shieldPotionPendingUntil = 0 end
  local spellOn = shieldPhrase(config.ering.spellOn)
  local attemptedAt = shieldAttemptAt[spellOn]
  local waitAfterSpell = not attemptedAt or now - attemptedAt >= 250
  local utamoUnavailable = shieldSpellBlocked(spellOn) or shieldRejected[spellOn] or
    shieldPending and shieldPending.words == spellOn and now - shieldPending.at >= 250

  if config.ering.manaItemId and config.ering.manaItemId > 0 then
    local itemHp = config.ering.shieldItemHp or config.ering.manaItemMp or 50
    if hp <= itemHp and not hasShield and utamoUnavailable and waitAfterSpell then
      if now - (lastMove["manaItem"] or 0) > shieldItemDelay and useItemOnSelf(config.ering.manaItemId) then
        lastMove["manaItem"] = now
        shieldPending = nil -- the potion's shield must not confirm a rejected Utamo
        local ping = g_game.getPing and tonumber(g_game.getPing()) or 0
        shieldPotionPendingUntil = now + math.max(250, math.min(600, ping * 2 + 80))
        return
      end
    end
  end

  if hp <= config.ering.hpAt then
    if not hasShield and now >= shieldPotionPendingUntil then tryShieldSpell(config.ering.spellOn) end
  end

  if hp >= config.ering.removeAt then
    if hasShield then tryShieldSpell(config.ering.spellOff) end
  end

end

-- =========================
-- FINGER / ENERGY RING + MIGHT RING
-- =========================
local function handleFinger()
  local finger = getFinger()
  observeEquipment("finger", finger)
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
        -- Preserve a charged MR interrupted by ERing: resume protection when
        -- the shield ring is removed, rather than returning normal too early.
        if isEquipped(finger, 3048) then resumeMightAfterEring = true end
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
    -- se quita inmediatamente, conservando el OFF configurado.
    if eringEquipped and hp >= eringRemoveAt then
      if unequipToBack(finger, "finger") then
        -- El equipo normal espera la recuperacion de 500 ms.
        -- Esto NO bloquea al Might Ring.
        eringPendingNormal = true
        markSlotDanger("finger")
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

  if resumeMightAfterEring then
    if isEquipped(finger, 3048) then resumeMightAfterEring = false
    else equipDangerItem(3048, fingerSlot, "finger", dangerActionButtons.ring) end
    return
  end

  -- A Might Ring already in use is retained until the server consumes it.
  -- Energy Ring still has priority above and keeps its configured ON/OFF.
  if isEquipped(finger, 3048) or normalGearBlocked() then return end

  -- =====================================================
  -- RING NORMAL DESPUÉS DEL ENERGY RING
  -- Esperar 500 ms por encima del margen de recuperacion.
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
        return -- keep pending until the equipment change is observed
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
  observeEquipment("neck", neck)
  local amuletEquipped = isEquipped(neck, config.amulet.dangerItem)

  -- SSA / Amulet de peligro
  if sectionDanger(config.amulet) then
    markSlotDanger("neck")

    if not amuletEquipped then
      equipDangerItem(config.amulet.dangerItem, neckSlot, "neck", dangerActionButtons.amulet)
    end

    return
  end

  -- Do not discard the remaining charges to restore the normal amulet.
  if isEquipped(neck, 3081) or normalGearBlocked() then return end

  -- Esperar 500 ms con HP y mana al menos 10 puntos sobre sus limites.
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
-- CICLO PRINCIPAL: eventos para respuesta inmediata y macro para reintentos.
-- =========================
local cycleRunning = false
local function runProtectionCycle()
  if not config.enabled then return end
  if cycleRunning then return end

  cycleRunning = true
  local ok, err = pcall(function()
    updateRecoveryTimers()
    handleSpellShield()
    handleFinger()
    handleNeck()
  end)
  cycleRunning = false
  if counterNeedsSync then
    updateCounterSlots()
    counterNeedsSync = false
  end
  if not ok then error(err) end
end

macro(10, function()
  runProtectionCycle()
end)

-- El contador sigue los cambios de inventario, incluso con Inmortal apagado.
-- La proteccion conserva sus eventos de HP/mana y sus reintentos de 10 ms.
local counterScanInterval = 1000
local function counterInventoryChange(slot, item)
  local slotKey
  if slot == fingerSlot then
    slotKey = "finger"
  elseif slot == neckSlot then
    slotKey = "neck"
  else
    return
  end
  observeEquipment(slotKey, item)

  -- Algunos clientes notifican dentro de move/equip. Esperar a que termine
  -- el ciclo permite aplicar la supresion de movimientos propios primero.
  if cycleRunning then
    counterNeedsSync = true
    return
  end

  updateCounterSlot(slotKey, item)
end

if type(onPlayerInventoryChange) == "function" then
  onPlayerInventoryChange(counterInventoryChange)
elseif type(onInventoryChange) == "function" then
  onInventoryChange(function(creature, slot, item)
    if creature == player then counterInventoryChange(slot, item) end
  end)
else
  counterScanInterval = 250
end

updateCounterSlots()
local lastCounterScanAt = now
macro(250, function()
  if counterNeedsSync or now - lastCounterScanAt >= counterScanInterval then
    updateCounterSlots()
    lastCounterScanAt = now
    counterNeedsSync = false
  end

  if now - lastCounterLabelAt >= 250 then
    updateCounterLabel()
    lastCounterLabelAt = now
  end
end)

onPlayerHealthChange(function()
  if not config.enabled then return end

  runProtectionCycle()
end)

onManaChange(function()
  if config.enabled then runProtectionCycle() end
end)

macro(500, function()
  if not config.enabled then return end
  -- Native equip-by-ID does not need to open supply backpacks first.
  if type(g_game.equipItemId) == "function" then return end
  maintainSupplyContainer(config.ring, "might")
  maintainSupplyContainer(config.amulet, "ssa")
end)
