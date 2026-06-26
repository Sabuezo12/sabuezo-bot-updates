CaveBot.Extensions.BuySupplies = {}

local buySupplyCalibration = {
  key = nil,
  tried = {}
}

local function resetBuySupplyCalibration(key, retries)
  if retries == 0 or buySupplyCalibration.key ~= key then
    buySupplyCalibration.key = key
    buySupplyCalibration.tried = {}
  end
end

local function getCounterInfo(id)
  local visible = player and player:getItemsCount(id) or 0
  local current = tonumber(itemAmount(id)) or 0
  local source = "unknown"

  if vBot.ItemCounter and vBot.ItemCounter.getAmountInfo then
    current, source = vBot.ItemCounter.getAmountInfo(id, visible)
    current = tonumber(current) or 0
  end

  return current, source, visible
end

local function useSupplyItemForLog(id)
  if not player then return false end

  if g_game and g_game.useInventoryItemWith then
    local ok = pcall(function()
      g_game.useInventoryItemWith(id, player, 0)
    end)
    if ok then return true end
  end

  local item = findItem and findItem(id) or nil
  if item and g_game and g_game.useWith then
    local ok = pcall(function()
      g_game.useWith(item, player, 0)
    end)
    if ok then return true end
  end

  if item and useWith then
    local ok = pcall(function()
      useWith(item, player)
    end)
    if ok then return true end
  end

  if item and g_game and g_game.use then
    local ok = pcall(function()
      g_game.use(item)
    end)
    if ok then return true end
  end

  return false
end

local function calibrateSupplyCountersBeforeBuying()
  if not Supplies or not Supplies.getItemsData then return false end

  for id, values in pairs(Supplies.getItemsData()) do
    id = tonumber(id)
    if id and id > 100 then
      if vBot.ItemCounter and vBot.ItemCounter.registerSupplyItem then
        vBot.ItemCounter.registerSupplyItem(id, values)
      elseif vBot.ItemCounter and vBot.ItemCounter.registerItemId then
        vBot.ItemCounter.registerItemId(id)
      end

      local current, source, visible = getCounterInfo(id)
      if source ~= "log" and not buySupplyCalibration.tried[id] and (visible > 0 or current > 0) then
        buySupplyCalibration.tried[id] = true
        if useSupplyItemForLog(id) then
          print("CaveBot[BuySupplies]: calibrating " .. id .. " with Server Log")
          CaveBot.delay(700)
          return true
        end
      end
    end
  end

  return false
end

local function trimText(text)
  return tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function parseBuySuppliesValue(value)
  local data = string.split(value or "", ",")
  if #data == 0 or #data > 3 then
    return nil, nil, nil, "incorrect BuySupplies value"
  end

  local npcName = trimText(data[1])
  if npcName == "" then
    return nil, nil, nil, "missing NPC name"
  end

  local tradeWord = nil
  local waitVal = nil

  if #data >= 2 then
    local second = trimText(data[2])
    if second ~= "" then
      local secondNumber = tonumber(second)
      if secondNumber then
        waitVal = secondNumber
      else
        tradeWord = second
      end
    end
  end

  if #data == 3 then
    local third = trimText(data[3])
    if third ~= "" then
      local thirdNumber = tonumber(third)
      if not thirdNumber then
        return nil, nil, nil, "incorrect delay value"
      end
      if waitVal then
        return nil, nil, nil, "use NPC, word, delay or NPC, delay"
      end
      waitVal = thirdNumber
    end
  end

  return npcName, tradeWord, waitVal
end

local function openNpcTrade(tradeWord)
  tradeWord = trimText(tradeWord)
  if tradeWord ~= "" then
    CaveBot.Conversation("hi", tradeWord)
  else
    CaveBot.OpenNpcTrade()
  end
end

CaveBot.Extensions.BuySupplies.setup = function()
  CaveBot.registerAction("BuySupplies", "#C300FF", function(value, retries)
    local possibleItems = {}
    resetBuySupplyCalibration(value, retries)

    local npcName, tradeWord, waitVal, parseError = parseBuySuppliesValue(value)
    if parseError then
      warn("CaveBot[BuySupplies]: " .. parseError)
      return false 
    end

    local npc = getCreatureByName(npcName)
    if not npc then 
      print("CaveBot[BuySupplies]: NPC not found")
      return false 
    end
    
    if waitVal then
      delay(waitVal)
    end

    if retries > 50 then
      print("CaveBot[BuySupplies]: Too many tries, can't buy")
      return false
    end

    if not CaveBot.ReachNPC(npcName) then
      return "retry"
    end

    if calibrateSupplyCountersBeforeBuying() then
      return "retry"
    end

    if not NPC.isTrading() then
      openNpcTrade(tradeWord)
      CaveBot.delay(storage.extras.talkDelay*2)
      return "retry"
    end

    -- get items from npc
    local npcItems = NPC.getBuyItems()
    for i,v in pairs(npcItems) do
      table.insert(possibleItems, v.id)
    end

    for id, values in pairs(Supplies.getItemsData()) do
      id = tonumber(id)
      if table.find(possibleItems, id) then
        local max = tonumber(values.max) or 0
        if vBot.ItemCounter and vBot.ItemCounter.registerItemId then
          if vBot.ItemCounter.registerSupplyItem then
            vBot.ItemCounter.registerSupplyItem(id, values)
          else
            vBot.ItemCounter.registerItemId(id)
          end
        end

        local current = getCounterInfo(id)
        current = tonumber(itemAmount(id)) or current or 0
        local toBuy = max - current

        if toBuy > 0 then
          toBuy = math.min(100, toBuy)

          NPC.buy(id, math.min(100, toBuy))
          if vBot.ItemCounter and vBot.ItemCounter.set then
            vBot.ItemCounter.set(id, current + toBuy, "buy")
          end
          print("CaveBot[BuySupplies]: bought " .. toBuy .. "x " .. id)
          return "retry"
        end
      end
    end

    print("CaveBot[BuySupplies]: bought everything, proceeding")
    return true
 end)

 CaveBot.Editor.registerAction("buysupplies", "buy supplies", {
  value="NPC name",
  title="Buy Supplies",
  description="NPC name, word(optional), delay(in ms, optional)",
 })
end
