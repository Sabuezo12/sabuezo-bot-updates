local function safeGetSlot(slot)
  if HelperAPI and type(HelperAPI.getSlotItem) == 'function' then
    local ok, item = pcall(HelperAPI.getSlotItem, slot)
    if ok and item then return item end
  end
  if type(getSlot) == 'function' then
    local ok, item = pcall(getSlot, slot)
    if ok and item then return item end
  end
  -- Fallback: search inventory
  if player and type(player.getItem) == 'function' then
    local ok, item = pcall(function() return player:getItem(slot) end)
    if ok and item then return item end
  end
  if g_game and type(g_game.getLocalPlayer) == 'function' then
    local lp = g_game.getLocalPlayer()
    if lp and type(lp.getItem) == 'function' then
      local ok, item = pcall(function() return lp:getItem(slot) end)
      if ok and item then return item end
    end
  end
  return nil
end

-- config
setDefaultTab("HP")
-- UI.Separator()
local scripts = 2 -- if you want more auto equip panels you can change 2 to higher value

-- script by kondrah, don't edit below unless you know what you are doing
local label = UI.Label("Simple Equipper")

if type(storage.autoEquip) ~= "table" then
  storage.autoEquip = {}
end
for i=1,scripts do
  if not storage.autoEquip[i] then
    storage.autoEquip[i] = {on=false, title="Auto Equip", item1=i == 1 and 3052 or 0, item2=i == 1 and 3089 or 0, slot=i == 1 and 9 or 0}
  end
  UI.TwoItemsAndSlotPanel(storage.autoEquip[i], function(widget, newParams)
    storage.autoEquip[i] = newParams
  end)
end
macro(250, function()
  local containers = (HelperAPI and HelperAPI.getContainers and HelperAPI.getContainers())
    or (g_game and type(g_game.getContainers) == 'function' and g_game.getContainers())
    or {}
  for index, autoEquip in ipairs(storage.autoEquip) do
    if autoEquip.on then
      local slotItem = safeGetSlot(autoEquip.slot)
      if not slotItem or (slotItem:getId() ~= autoEquip.item1 and slotItem:getId() ~= autoEquip.item2) then
        for _, container in pairs(containers) do
          for __, item in ipairs(container:getItems()) do
            if item:getId() == autoEquip.item1 or item:getId() == autoEquip.item2 then
              g_game.move(item, {x=65535, y=autoEquip.slot, z=0}, item:getCount())
              delay(1000) -- don't call it too often      
              return
            end
          end
        end
      end
    end
  end
end)

UI.Separator()
