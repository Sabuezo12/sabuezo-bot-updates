setDefaultTab("HP")
---UI.Separator()
if type(storage.foodItems) ~= "table" then
  storage.foodItems = {3607, 3592, 3600, 3601, 3725, 3582, 3577, 3578, 3583, 3723, 3731, 3732, 3595, 3593}
end

local eatFoodMacro = macro(5000, "Eat Food", function()
  if player:getRegenerationTime() > 400 or not storage.foodItems[1] then return end
  -- search for food in containers
  for _, container in pairs(g_game.getContainers()) do
    for __, item in ipairs(container:getItems()) do
      for i, foodItem in ipairs(storage.foodItems) do
        if item:getId() == foodItem.id then
          return g_game.use(item)
        end
      end
    end
  end
end)

local foodContainer = UI.Container(function(widget, items)
  storage.foodItems = items
end, true)
foodContainer:setHeight(56)
foodContainer:setItems(storage.foodItems)

local helperFood = Helper and Helper.valid() and not (storage.helperUI and storage.helperUI.legacy == true)
if helperFood then storage.helperUI=type(storage.helperUI)=="table" and storage.helperUI or {} end
local conjureFoodMacro = macro(5000, "Conjure Food", function()
  -- In Helper, conjuring requires the user's explicit choice and food master ON.
  if helperFood and (storage.helperUI.foodConjureChoice~=true or not eatFoodMacro.isOn()) then return end
  if player:getRegenerationTime() <= 400 then
      cast("exevo pan", 5000)
  end
end)

UI.Separator()
-- Separate the master (eating) from the explicit conjure preference.
-- Ignore the old combined ON choice; it did not mean the user chose a spell.
if helperFood and (storage.helperUI.foodConjureChoice~=true or not eatFoodMacro.isOn()) then conjureFoodMacro.setOff() end
local function setFoodMacro(handle,value)
  if handle.isOn()~=value then
    if value then handle.setOn() else handle.setOff() end
  end
end
HelperFoodBridge = {}
function HelperFoodBridge.getPowers()
  return {{key="eat",read=function() return eatFoodMacro.isOn()==true end,
    set=function(value)
      setFoodMacro(eatFoodMacro,value)
      if helperFood then
        setFoodMacro(conjureFoodMacro,value and storage.helperUI.foodConjureChoice==true)
      end
    end}}
end
function HelperFoodBridge.isConjureSelected()
  if helperFood then return storage.helperUI.foodConjureChoice==true end
  return conjureFoodMacro.isOn()==true
end
function HelperFoodBridge.setConjureSelected(value)
  value=value==true
  if helperFood then
    storage.helperUI.foodConjureChoice=value
    setFoodMacro(conjureFoodMacro,value and eatFoodMacro.isOn())
  else setFoodMacro(conjureFoodMacro,value) end
end
