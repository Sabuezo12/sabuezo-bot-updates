setDefaultTab("tools")
UI.Separator()

local panelName = "antipushCoins"
local GOLD_COIN_ID = 3031
local PLATINUM_COIN_ID = 3035
local CRYSTAL_COIN_ID = 3043
local DEFAULT_WITHDRAW_TEXT = "!bank withdraw 20000"
local MIN_PLATINUM = 30
local MIN_GOLD = 20
local PLATINUM_DELAY = 80
local CRYSTAL_DELAY = 80
local WITHDRAW_DELAY = 5000
local STACK_LAYER_COUNT = 6
local DROP_AMOUNT = 2

if not storage[panelName] then
  storage[panelName] = {
    enabled = false,
    hotkey = "Numpad0",
    withdrawText = DEFAULT_WITHDRAW_TEXT,
    dropItems = { GOLD_COIN_ID }
  }
end

local config = storage[panelName]
config.hotkey = config.hotkey or "Numpad0"
config.withdrawText = config.withdrawText or DEFAULT_WITHDRAW_TEXT
config.dropItems = config.dropItems or { GOLD_COIN_ID }
if type(config.dropItems) ~= "table" then
  config.dropItems = { GOLD_COIN_ID }
end

local ui = setupUI([[
Panel
  height: 20

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('AntiPush Coins')

  Button
    id: edit
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 18
    text: Edit
]])

local edit = setupUI([[
Panel
  height: 128
  margin-top: 2

  Label
    id: itemsLabel
    anchors.top: parent.top
    anchors.left: parent.left
    text: Items to Drop:
    height: 18

  BotContainer
    id: DropItems
    anchors.top: itemsLabel.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    height: 56
    margin-top: 2

  Label
    id: hotkeyLabel
    anchors.top: DropItems.bottom
    anchors.left: parent.left
    text: Hotkey:
    height: 18
    margin-top: 6

  Button
    id: HotkeyButton
    anchors.top: prev.top
    anchors.left: parent.horizontalCenter
    anchors.right: parent.right
    height: 18
    text-align: center
    text: Set

  Label
    id: withdrawLabel
    anchors.top: hotkeyLabel.bottom
    anchors.left: parent.left
    text: Bank Text:
    height: 18
    margin-top: 6

  Button
    id: WithdrawButton
    anchors.top: prev.top
    anchors.left: parent.horizontalCenter
    anchors.right: parent.right
    height: 18
    text-align: center
    text: Edit
]])
edit:hide()

local showEdit = false
local waitingHotkey = false
local lastPlatinumAt = 0
local lastCrystalAt = 0
local lastWithdrawAt = 0
local dropIds = {}
local dropSequence = {}
local nextDropIndex = 1
local lastPosKey = ""
local lastItemLayerCount = 0
local buildMoves = 0

local function getTime()
  if now then return now end
  if g_clock and g_clock.millis then return g_clock.millis() end
  return 0
end

local function trim(text)
  return tostring(text or ""):gsub("^%s*(.-)%s*$", "%1")
end

local function firstLine(text)
  text = tostring(text or ""):gsub("\r\n", "\n")
  return trim(text:match("([^\n]*)") or text)
end

local function sameKey(a, b)
  return trim(a):lower() == trim(b):lower()
end

local function addUnique(list, itemId)
  for _, id in ipairs(list) do
    if id == itemId then return end
  end
  table.insert(list, itemId)
end

local function refreshDropSequence()
  dropSequence = {}
  if #dropIds == 0 then return end

  local index = 1
  while #dropSequence < STACK_LAYER_COUNT do
    table.insert(dropSequence, dropIds[index])
    index = index + 1
    if index > #dropIds then
      index = 1
    end
  end

  if nextDropIndex > #dropSequence then
    nextDropIndex = 1
  end
end

local function refreshDropIds()
  dropIds = { GOLD_COIN_ID, PLATINUM_COIN_ID }
  local items = config.dropItems or {}

  for _, item in pairs(items) do
    local itemId = item
    if type(item) == "table" then
      itemId = item.id
    end
    itemId = tonumber(itemId)
    if itemId and itemId > 0 then
      addUnique(dropIds, itemId)
    end
  end

  refreshDropSequence()
end

local function dropIdsContain(itemId)
  for _, dropId in ipairs(dropIds) do
    if dropId == itemId then return true end
  end
  return false
end

local function sayText(text)
  if not text or text == "" then return false end
  if type(say) == "function" then
    local ok = pcall(function() say(text) end)
    if ok then return true end
  end
  if g_game and g_game.talk then
    g_game.talk(text)
    return true
  end
  return false
end

local function getItemCount(itemId)
  local total = 0
  if not getContainers then return total end

  for _, container in pairs(getContainers()) do
    for _, item in ipairs(container:getItems()) do
      if item:getId() == itemId then
        total = total + item:getCount()
      end
    end
  end
  return total
end

local function getPosKey(p)
  if not p then return "" end
  return p.x .. "," .. p.y .. "," .. p.z
end

local function getItemLayerCount(tile)
  local items = tile and tile:getItems()
  if not items then return 0 end
  return #items
end

local function useItem(item)
  if not item then return false end
  if type(use) == "function" then
    local ok = pcall(function() use(item) end)
    if ok then return true end
  end
  if g_game and g_game.use then
    g_game.use(item)
    return true
  end
  return false
end

local function ensureGold()
  local time = getTime()
  local goldCount = getItemCount(GOLD_COIN_ID)
  local platinumCount = getItemCount(PLATINUM_COIN_ID)
  local needsGold = dropIdsContain(GOLD_COIN_ID)
  local needsPlatinum = needsGold or dropIdsContain(PLATINUM_COIN_ID)

  if not needsGold and not needsPlatinum then return true end

  if needsPlatinum and platinumCount < MIN_PLATINUM and time - lastCrystalAt >= CRYSTAL_DELAY then
    local crystal = findItem(CRYSTAL_COIN_ID)
    if crystal and useItem(crystal) then
      lastCrystalAt = time
      return false
    end
  end

  if needsPlatinum and platinumCount < MIN_PLATINUM and time - lastWithdrawAt >= WITHDRAW_DELAY then
    if sayText(config.withdrawText) then
      lastWithdrawAt = time
    end
  end

  if needsGold and goldCount < MIN_GOLD and time - lastPlatinumAt >= PLATINUM_DELAY then
    local platinum = findItem(PLATINUM_COIN_ID)
    if platinum and useItem(platinum) then
      lastPlatinumAt = time
      return false
    end
  end

  return true
end

local function updateSettingButtons()
  edit.HotkeyButton:setText(config.hotkey or "")
  edit.WithdrawButton:setText("Bank Text")
  if edit.HotkeyButton.setTooltip then
    edit.HotkeyButton:setTooltip("Hotkey: " .. (config.hotkey or ""))
  end
  if edit.WithdrawButton.setTooltip then
    edit.WithdrawButton:setTooltip(config.withdrawText or "")
  end
end

local function setEnabled(enabled)
  config.enabled = enabled == true
  ui.title:setOn(config.enabled)
  lastPosKey = ""
  lastItemLayerCount = 0
  buildMoves = 0
  nextDropIndex = 1
end

AntiPush = {
  isOn = function()
    return config.enabled == true
  end,
  setOn = function()
    return setEnabled(true)
  end,
  setOff = function()
    return setEnabled(false)
  end
}

ui.title:setOn(config.enabled)
ui.title.onClick = function()
  setEnabled(not config.enabled)
end

ui.edit.onClick = function()
  showEdit = not showEdit
  edit:setVisible(showEdit)
end

UI.Container(function()
  local currentItems = edit.DropItems:getItems()
  if currentItems then
    config.dropItems = currentItems
    refreshDropIds()
  end
end, true, nil, edit.DropItems)

schedule(100, function()
  if edit.DropItems and config.dropItems then
    edit.DropItems:setItems(config.dropItems)
    refreshDropIds()
  end
end)

refreshDropIds()
updateSettingButtons()

edit.HotkeyButton.onClick = function()
  waitingHotkey = true
  edit.HotkeyButton:setText("Press key...")
end

edit.WithdrawButton.onClick = function()
  UI.MultilineEditorWindow(config.withdrawText or "", {
    title = "AntiPush Bank Text",
    description = "Text to say when platinum coins are low."
  }, function(text)
    config.withdrawText = firstLine(text)
    updateSettingButtons()
  end)
end

macro(20, function()
  if not config.enabled then return end
  if #dropSequence == 0 then return end

  local playerPos = pos()
  local currentPosKey = getPosKey(playerPos)
  if currentPosKey ~= lastPosKey then
    lastPosKey = currentPosKey
    lastItemLayerCount = 0
    buildMoves = 0
    nextDropIndex = 1
  end

  local tile = g_map.getTile(playerPos)
  if not tile then return end

  ensureGold()

  local itemLayerCount = getItemLayerCount(tile)
  if itemLayerCount ~= lastItemLayerCount then
    buildMoves = 0
  end
  lastItemLayerCount = itemLayerCount

  if itemLayerCount >= STACK_LAYER_COUNT then return end
  if tile:getThingCount() >= 10 then return end
  local missingLayers = STACK_LAYER_COUNT - itemLayerCount
  if buildMoves >= missingLayers then return end

  for _ = 1, #dropSequence do
    local itemId = dropSequence[nextDropIndex]
    nextDropIndex = nextDropIndex + 1
    if nextDropIndex > #dropSequence then
      nextDropIndex = 1
    end
    local item = findItem(itemId)
    if item then
      g_game.move(item, playerPos, DROP_AMOUNT)
      buildMoves = buildMoves + 1
      return
    end
  end
end)

onKeyDown(function(key)
  if waitingHotkey then
    config.hotkey = key
    waitingHotkey = false
    updateSettingButtons()
    return
  end

  if sameKey(key, config.hotkey) then
    setEnabled(not config.enabled)
  end
end)

UI.Separator()
