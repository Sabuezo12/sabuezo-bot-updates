storage.itemCounter = storage.itemCounter or {}
if type(storage.itemCounter.items) ~= "table" then storage.itemCounter.items = {} end
if type(storage.itemCounter.watch) ~= "table" then storage.itemCounter.watch = {} end
storage.itemCounter.enabled = true

local settings = storage.itemCounter
local watchItems = settings.watch
local rowWidgets = {}
local registeredEntrySignatures = {}
local DEFAULT_WATCH_VERSION = 1
local DEFAULT_WATCH_ITEMS = {
  { id = 12081, alias = "Full Health Potion" },
  { id = 11767, alias = "Health Recovery Potion" },
  { id = 11846, alias = "Adrenaline 500ml" },
  { id = 11766, alias = "Mana Recovery Potion" },
  { id = 12066, alias = "Swiftness Potion" },
  { id = 12123, alias = "Nitro Potions" },
  { id = 11845, alias = "Rewind Potion" }
}

local trim = function(text)
  return tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local normalizeWatchList = function()
  if type(settings.watch) ~= "table" then
    settings.watch = {}
  end

  watchItems = settings.watch
  for index, entry in ipairs(watchItems) do
    if type(entry) ~= "table" then
      watchItems[index] = { id = tonumber(entry) or 0, alias = "" }
    else
      entry.id = tonumber(entry.id) or 0
      entry.alias = tostring(entry.alias or "")
    end
  end

  if #watchItems == 0 then
    table.insert(watchItems, { id = 0, alias = "" })
  end
end

local hasWatchItem = function(itemId)
  itemId = tonumber(itemId)
  if not itemId then return false end

  for _, entry in ipairs(watchItems) do
    if tonumber(entry and entry.id) == itemId then
      return true
    end
  end

  return false
end

local applyDefaultWatchItems = function()
  normalizeWatchList()

  if tonumber(settings.defaultWatchVersion) and tonumber(settings.defaultWatchVersion) >= DEFAULT_WATCH_VERSION then
    return
  end

  if #watchItems == 1 and tonumber(watchItems[1].id) == 0 and tostring(watchItems[1].alias or "") == "" then
    table.remove(watchItems, 1)
  end

  for _, item in ipairs(DEFAULT_WATCH_ITEMS) do
    if not hasWatchItem(item.id) then
      table.insert(watchItems, { id = item.id, alias = item.alias })
    end
  end

  settings.defaultWatchVersion = DEFAULT_WATCH_VERSION
end

local getAliasList = function(aliasText)
  local aliases = {}
  aliasText = trim(aliasText)
  if aliasText == "" then return aliases end

  for rawAlias in aliasText:gmatch("[^,;]+") do
    local alias = trim(rawAlias)
    if alias ~= "" then
      table.insert(aliases, alias)
    end
  end

  return aliases
end

local registerCounterEntry = function(entry)
  local id = tonumber(entry and entry.id)
  if not id or id <= 100 or not vBot.ItemCounter then return end

  local signature = tostring(id) .. "|" .. tostring(entry.alias or "")
  if registeredEntrySignatures[id] == signature then return end

  if vBot.ItemCounter.registerWatchItem then
    vBot.ItemCounter.registerWatchItem(id, entry)
  else
    local aliases = getAliasList(entry.alias)
    if #aliases > 0 and vBot.ItemCounter.register then
      vBot.ItemCounter.register(id, aliases[1], aliases)
    elseif vBot.ItemCounter.registerItemId then
      vBot.ItemCounter.registerItemId(id)
    end
  end

  registeredEntrySignatures[id] = signature
end

local getCounterAmount = function(entry)
  local id = tonumber(entry and entry.id)
  if not id or id <= 100 then return nil end

  registerCounterEntry(entry)
  if itemAmount then
    return tonumber(itemAmount(id)) or 0
  end
  if vBot.ItemCounter and vBot.ItemCounter.get then
    return tonumber(vBot.ItemCounter.get(id)) or 0
  end
  return 0
end

local updateRowCount = function(row)
  local amount = getCounterAmount(row.entry)
  if amount == nil then
    row.widget.count:setText("Actual: -")
    row.widget.count:setColor("#aaaaaa")
    return
  end

  row.widget.count:setText("Actual: " .. amount)
  row.widget.count:setColor(amount > 0 and "#9dff9d" or "#ff8888")
end

local rootWidget = g_ui.getRootWidget()
local counterWindow = UI.createWindow("ItemCounterWindow", rootWidget)
counterWindow:hide()
counterWindow.closeButton.onClick = function()
  counterWindow:hide()
end

local refreshRows
refreshRows = function()
  normalizeWatchList()
  registeredEntrySignatures = {}
  if vBot.ItemCounter and vBot.ItemCounter.clearWatchItems then
    vBot.ItemCounter.clearWatchItems()
  end

  counterWindow.list:destroyChildren()
  rowWidgets = {}

  for index, entry in ipairs(watchItems) do
    local row = UI.createWidget("ItemCounterRow", counterWindow.list)
    local rowState = {
      widget = row,
      entry = entry
    }
    rowWidgets[index] = rowState

    row.item:setShowCount(false)

    row.item.onItemChange = function(widget)
      entry.id = widget:getItemId()
      registerCounterEntry(entry)
      updateRowCount(rowState)
    end

    row.alias.onTextChange = function(widget, text)
      entry.alias = text
      registerCounterEntry(entry)
    end

    row.remove.onClick = function()
      table.remove(watchItems, index)
      refreshRows()
    end

    row.item:setItemId(entry.id)
    row.alias:setText(entry.alias or "")
    updateRowCount(rowState)
  end
end

vBot.ItemCounter.getWatchItems = function()
  normalizeWatchList()
  return watchItems
end

vBot.ItemCounter.openSetup = function()
  refreshRows()
  counterWindow:show()
  counterWindow:raise()
  counterWindow:focus()
end

counterWindow.add.onClick = function()
  table.insert(watchItems, { id = 0, alias = "" })
  refreshRows()
end

applyDefaultWatchItems()
refreshRows()

macro(250, function()
  if not settings.enabled then return end
  if vBot.ItemCounter and vBot.ItemCounter.updateAmmo then
    vBot.ItemCounter.updateAmmo()
  end

  for _, row in ipairs(rowWidgets) do
    updateRowCount(row)
  end
end)
