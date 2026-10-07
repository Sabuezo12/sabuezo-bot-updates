setDefaultTab("Main")

local MAGIC_BAG_ID = 12548
local STORAGE_KEY = "magicBagSellerItems"

if type(storage[STORAGE_KEY]) ~= "table" then
  storage[STORAGE_KEY] = {}
end

if #storage[STORAGE_KEY] == 0 and type(storage.equipmentItems) == "table" then
  storage[STORAGE_KEY] = storage.equipmentItems
end

UI.Separator()
UI.Label("Venda com Loot Magic Bag:")

local equipmentContainer = UI.Container(function(widget, items)
  storage[STORAGE_KEY] = items
end, true)

equipmentContainer:setHeight(75)
equipmentContainer:setItems(storage[STORAGE_KEY])

local function isSelectedItem(itemId)
  for _, selectedItem in ipairs(storage[STORAGE_KEY]) do
    if selectedItem.id == itemId then
      return true
    end
  end

  return false
end

macro(2500, "Automatic Magic Bag Selling", function()
  if #storage[STORAGE_KEY] == 0 then
    return
  end

  for _, container in pairs(g_game.getContainers()) do
    for _, item in ipairs(container:getItems()) do
      if isSelectedItem(item:getId()) then
        useWith(MAGIC_BAG_ID, item)
      end
    end
  end
end)
