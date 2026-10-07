setDefaultTab("Tools")
UI.Separator()

local panelName = "RecogeTodo"

-- 1. Inicializar almacenamiento seguro
if not storage[panelName] then
  storage[panelName] = {
    enabled = false,
    lootItems = {}
  }
end

local config = storage[panelName]
if not config.lootItems then config.lootItems = {} end

-- 2. Panel de control (Interruptor y Botón Edit)
local ui = setupUI([[
Panel
  height: 20

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('Recoge Todo')

  Button
    id: edit
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 18
    text: Edit
]])

-- 3. Panel de Edición
local edit = setupUI([[
Panel
  height: 80
  margin-top: 2

  Label
    id: itemsLabel
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: Items to Loot:
    height: 15

  BotContainer
    id: LootItems
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 5
    height: 56
    horizontal-scrollbar: false
    vertical-scrollbar: false
]])
edit:hide()

-- 4. Lógica de la interfaz
local showEdit = false
ui.edit.onClick = function(widget)
  showEdit = not showEdit
  edit:setVisible(showEdit)
end

local function setEnabled(enabled)
  config.enabled = enabled == true
  ui.title:setOn(config.enabled)
end

ui.title:setOn(config.enabled)
ui.title.onClick = function(widget)
  setEnabled(not config.enabled)
end

RecogeTodo = {
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

-- 5. Sincronización de Items
UI.Container(function()
  local currentItems = edit.LootItems:getItems()
  if currentItems then
    config.lootItems = currentItems
  end
end, true, nil, edit.LootItems)

schedule(100, function()
  if edit.LootItems and config.lootItems then
    edit.LootItems:setItems(config.lootItems)
  end
end)

-- 6. Función auxiliar para verificar si un ID está en la lista
local function isLootItem(id)
  for _, item in pairs(config.lootItems) do
    local itemId = type(item) == "table" and item.id or item
    if itemId == id then return true end
  end
  return false
end

-- 7. Macro de Auto Loot (área 3x3)
macro(150, function()
  if not config.enabled then return end

  local playerPos = pos()
  for x = -1, 1 do
    for y = -1, 1 do
      local tile = g_map.getTile({x = playerPos.x + x, y = playerPos.y + y, z = playerPos.z})
      if tile then
        local items = tile:getItems()
        for _, item in ipairs(items) do
          if item:isPickupable() and isLootItem(item:getId()) then
            g_game.move(item, {x = 65535, y = 3, z = 0}, item:getCount())
            delay(25)
            return
          end
        end
      end
    end
  end
end)
