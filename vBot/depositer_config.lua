setDefaultTab("Cave")

local panelName = "specialDeposit"
local depositerPanel
local rowStates = {}
local registeredEntrySignatures = {}

DepotManager = DepotManager or {}

if type(storage[panelName]) ~= "table" then
  storage[panelName] = {}
end
if type(storage[panelName].items) ~= "table" then
  storage[panelName].items = {}
end
if not tonumber(storage[panelName].height) or tonumber(storage[panelName].height) < 260 then
  storage[panelName].height = 430
end

local config = storage[panelName]

local function trim(text)
  return tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function lower(text)
  return trim(text):lower()
end

local function numericText(text, defaultValue)
  local value = tonumber(trim(text))
  if not value then return defaultValue or 0 end
  return value
end

local function getPanelHeight()
  local height = tonumber(config.height)
  if not height or height < 260 then
    height = 430
    config.height = height
  end
  return height
end

local function getItemName(id)
  id = tonumber(id) or 0
  if id <= 100 then return "Select item" end

  local ok, item = pcall(function() return Item.create(id) end)
  if ok and item then
    local okName, data = pcall(function() return item:getMarketData() end)
    if okName and data and data.name and data.name ~= "" then
      return data.name
    end
  end

  if vBot and vBot.ItemCounter and vBot.ItemCounter.getName then
    local name = vBot.ItemCounter.getName(id)
    if name and name ~= "" and name ~= tostring(id) then return name end
  end

  return tostring(id)
end

local function normalizeEntry(entry)
  if type(entry) ~= "table" then entry = { id = tonumber(entry) or 0 } end

  entry.id = tonumber(entry.id) or 0
  entry.mode = lower(entry.mode or entry.action or "deposit")
  if entry.mode ~= "withdraw" then entry.mode = "deposit" end

  entry.amount = tonumber(entry.amount or entry.keep or 0) or 0
  if entry.amount < 0 then entry.amount = 0 end

  entry.box = tonumber(entry.box or entry.index or 3) or 3
  if entry.box < 1 then entry.box = 3 end
  if entry.box > 17 then entry.box = 17 end

  entry.source = lower(entry.source or "box")
  if entry.source ~= "inbox" then entry.source = "box" end

  entry.alias = trim(entry.alias or entry.name or entry.logName or "")
  entry.enabled = entry.enabled ~= false
  return entry
end

local function normalizeSettings()
  local normalized = {}

  for _, entry in pairs(config.items) do
    if type(entry) == "table" then
      table.insert(normalized, normalizeEntry(entry))
    end
  end

  config.items = normalized
end

normalizeSettings()

local function splitAliases(text)
  local aliases = {}
  text = trim(text)
  if text == "" then return aliases end

  for raw in text:gmatch("[^,;]+") do
    local alias = trim(raw)
    if alias ~= "" then table.insert(aliases, alias) end
  end

  return aliases
end

local function registerDepotCounter(entry)
  local id = tonumber(entry and entry.id)
  if not id or id <= 100 or not vBot or not vBot.ItemCounter then return end

  local signature = tostring(id) .. "|" .. tostring(entry.alias or "")
  if registeredEntrySignatures[id] == signature then return end

  if vBot.ItemCounter.registerWatchItem then
    vBot.ItemCounter.registerWatchItem(id, entry)
  elseif vBot.ItemCounter.register then
    local aliases = splitAliases(entry.alias)
    if #aliases > 0 then
      vBot.ItemCounter.register(id, aliases[1], aliases)
    elseif vBot.ItemCounter.registerItemId then
      vBot.ItemCounter.registerItemId(id)
    end
  elseif vBot.ItemCounter.registerItemId then
    vBot.ItemCounter.registerItemId(id)
  end

  registeredEntrySignatures[id] = signature
end

local function visibleAmount(id)
  id = tonumber(id)
  if not id or id <= 100 or not player or not player.getItemsCount then return 0 end
  return tonumber(player:getItemsCount(id)) or 0
end

function DepotManager.countItem(entry)
  local id = tonumber(entry and entry.id)
  if not id or id <= 100 then return 0, "none" end

  registerDepotCounter(entry)

  local visible = visibleAmount(id)
  if vBot and vBot.ItemCounter and vBot.ItemCounter.getAmountInfo then
    return vBot.ItemCounter.getAmountInfo(id, visible)
  end
  if itemAmount then
    return tonumber(itemAmount(id)) or visible, "visible"
  end
  return visible, "visible"
end

function DepotManager.getEntries(mode)
  normalizeSettings()
  local result = {}
  mode = mode and lower(mode) or nil

  for _, entry in ipairs(config.items) do
    normalizeEntry(entry)
    if entry.enabled and entry.id > 100 and (not mode or entry.mode == mode) then
      registerDepotCounter(entry)
      table.insert(result, entry)
    end
  end

  return result
end

function getStashingIndex(id)
  id = tonumber(id)
  if not id then return nil end

  for _, entry in ipairs(config.items) do
    normalizeEntry(entry)
    if entry.mode == "deposit" and tonumber(entry.id) == id then
      return math.max(0, (tonumber(entry.box) or 1) - 1)
    end
  end

  return nil
end

local function updateAliasButton(button, alias)
  alias = trim(alias)
  if alias == "" then
    button:setText("Log")
    button:setColor("#d8d8d8")
  else
    button:setText("Set")
    button:setColor("#89d9ff")
  end
end

local function updateMode(row, entry)
  local isWithdraw = entry.mode == "withdraw"
  row.mode:setText(isWithdraw and "Withdraw" or "Deposit")
  row.mode:setColor(isWithdraw and "#75ff9b" or "#7ebdff")

  if row.source.setEnabled then
    row.source:setEnabled(isWithdraw)
  end
  row.source:setText(entry.source == "inbox" and "Inbox" or "Box")
  row.source:setColor(isWithdraw and "#d8d8d8" or "#777777")

  row.amount:setTooltip(isWithdraw and
    "Cantidad que quieres tener en el char; retirara del DP hasta llegar a este numero." or
    "Cantidad que quieres conservar en el char; depositara el exceso.")

  row.box:setTooltip(isWithdraw and
    "Depot Box de origen cuando Source esta en Box." or
    "Depot Box destino para depositar este item.")
end

local function updateActiveButton(row, entry)
  row.active:setText(entry.enabled and "On" or "Off")
  row.active:setColor(entry.enabled and "#75ff75" or "#ff7575")
end

local function updateCount(row, entry)
  if not row or not entry then return end
  local amount, source = DepotManager.countItem(entry)
  row.count:setText("Actual: " .. tostring(amount or 0) .. " | " .. tostring(source or "visible"))
  row.count:setColor((amount or 0) > 0 and "#a6ff9d" or "#c8c8c8")
end

local function removeEntry(target)
  for i, entry in ipairs(config.items) do
    if entry == target then
      table.remove(config.items, i)
      return true
    end
  end
  return false
end

local refreshEntries

local function createRow(entry)
  entry = normalizeEntry(entry)

  local row = g_ui.createWidget("DepotItemRow", depositerPanel.DepositerList)
  table.insert(rowStates, { row = row, entry = entry })

  row.item:setShowCount(false)
  row.item:setItemId(entry.id)
  row.name:setText(getItemName(entry.id))
  row.amount:setText(entry.amount)
  row.box:setText(entry.box)
  row.aliasValue:setText(entry.alias or "")

  row.item:setTooltip("Selecciona el item que quieres depositar o retirar.")
  row.mode:setTooltip("Cambia entre depositar y retirar.")
  row.amount:setTooltip("Cantidad configurada para esta regla.")
  row.box:setTooltip("Depot Box usado por esta regla.")
  row.source:setTooltip("Origen al retirar: Depot Box o Inbox.")
  row.alias:setTooltip("Nombre del item como aparece en Server Log. Puedes poner varios separados por coma.")
  row.active:setTooltip("Activa o desactiva esta regla sin borrarla.")
  row.remove:setTooltip("Elimina esta regla.")

  row.item.onItemChange = function(widget)
    local id = widget:getItemId()
    entry.id = id
    row.name:setText(getItemName(id))
    registerDepotCounter(entry)
    updateCount(row, entry)
  end

  row.mode.onClick = function()
    entry.mode = entry.mode == "deposit" and "withdraw" or "deposit"
    updateMode(row, entry)
  end

  row.active.onClick = function()
    entry.enabled = not entry.enabled
    updateActiveButton(row, entry)
  end

  row.amount.onTextChange = function(widget, text)
    entry.amount = math.max(0, numericText(text, 0))
  end

  row.box.onTextChange = function(widget, text)
    local value = numericText(text, entry.box)
    if value < 1 then value = 1 end
    if value > 17 then value = 17 end
    entry.box = value
  end

  row.source.onClick = function()
    if entry.mode ~= "withdraw" then return end
    entry.source = entry.source == "inbox" and "box" or "inbox"
    updateMode(row, entry)
  end

  row.aliasValue.onTextChange = function(widget, text)
    entry.alias = trim(text)
    updateAliasButton(row.alias, entry.alias)
    registerDepotCounter(entry)
    updateCount(row, entry)
  end

  row.alias.onClick = function()
    if entry.id <= 100 then return end
    local window = modules.client_textedit.show(row.aliasValue, {
      title = "Nombre en Server Log",
      description = "Escribe como aparece este item en Server Log. Puedes poner varios separados por coma."
    })
    schedule(50, function()
      if window then
        window:raise()
        window:focus()
      end
    end)
  end

  row.remove.onClick = function()
    removeEntry(entry)
    refreshEntries()
  end

  updateMode(row, entry)
  updateActiveButton(row, entry)
  updateAliasButton(row.alias, entry.alias)
  updateCount(row, entry)
end

refreshEntries = function()
  normalizeSettings()
  rowStates = {}
  registeredEntrySignatures = {}
  depositerPanel.DepositerList:destroyChildren()

  for _, entry in ipairs(config.items) do
    createRow(entry)
  end
end

depositerPanel = UI.createWindow("DepositerPanel", rootWidget)
depositerPanel:hide()
depositerPanel.CloseButton.onClick = function()
  depositerPanel:hide()
end

depositerPanel:setHeight(getPanelHeight())
depositerPanel.onGeometryChange = function(widget, old, new)
  if old.height == 0 then return end
  if new.height and new.height >= 260 then
    config.height = new.height
  end
end

depositerPanel.addDeposit:setTooltip("Agrega una regla para depositar el exceso de un item.")
depositerPanel.addWithdraw:setTooltip("Agrega una regla para retirar un item desde DP o Inbox.")
depositerPanel.resetCounters:setTooltip("Reinicia el contador de gastados de los items configurados.")

depositerPanel.addDeposit.onClick = function()
  table.insert(config.items, normalizeEntry({ mode = "deposit", id = 0, amount = 0, box = 3 }))
  refreshEntries()
end

depositerPanel.addWithdraw.onClick = function()
  table.insert(config.items, normalizeEntry({ mode = "withdraw", id = 0, amount = 0, box = 3, source = "box" }))
  refreshEntries()
end

depositerPanel.resetCounters.onClick = function()
  if not vBot or not vBot.ItemCounter or not vBot.ItemCounter.resetUsed then return end
  for _, entry in ipairs(config.items) do
    if tonumber(entry.id) and entry.id > 100 then
      vBot.ItemCounter.resetUsed(entry.id)
    end
  end
end

UI.Button("Depot Settings", function()
  local ok, err = pcall(function()
    depositerPanel:setHeight(getPanelHeight())
    refreshEntries()
    depositerPanel:show()
    depositerPanel:raise()
    depositerPanel:focus()
  end)
  if not ok then
    warn("Depot Settings error: " .. tostring(err))
  end
end)

refreshEntries()

macro(1000, function()
  if not depositerPanel or not depositerPanel:isVisible() then return end
  for _, state in ipairs(rowStates) do
    updateCount(state.row, state.entry)
  end
end)

UI.Separator()
UI.Label("Sell Exeptions")

if type(storage.cavebotSell) ~= "table" then
  storage.cavebotSell = { 23544, 3081 }
end

local sellContainer = UI.Container(function(widget, items)
  storage.cavebotSell = items
end, true)
sellContainer:setHeight(35)
sellContainer:setItems(storage.cavebotSell)
