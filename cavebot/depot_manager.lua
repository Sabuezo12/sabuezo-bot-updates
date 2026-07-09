CaveBot.Extensions.DepotManager = {}

local depositState = {
  value = nil
}

local withdrawState = {
  sourceKey = nil,
  openedSourceKey = nil,
  stashRequestKey = nil,
  stashRequestAt = 0
}

local function trim(text)
  return tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function lower(text)
  return trim(text):lower()
end

local function splitCsv(text)
  local values = {}
  text = tostring(text or "")
  for raw in text:gmatch("([^,]+)") do
    table.insert(values, trim(raw))
  end
  return values
end

local function toSet(list)
  local set = {}
  for _, value in pairs(list or {}) do
    local id = tonumber(value)
    if id then set[id] = true end
  end
  return set
end

local function listHasId(list, id)
  id = tonumber(id)
  if not id then return false end
  for _, value in pairs(list or {}) do
    if tonumber(value) == id then return true end
  end
  return false
end

local DEPOT_LOCKER_IDS = {
  [2589] = true, [2590] = true, [2591] = true, [2592] = true,
  [3497] = true, [3498] = true, [3499] = true, [3500] = true
}

local DEPOT_CHEST_IDS = {
  [2594] = true,
  [3502] = true
}

local INBOX_IDS = {
  [12902] = true
}

-- Add known custom stash ids here if a server does not expose the locker item name.
local STASH_IDS = {
  [28750] = true
}

local DEPOT_BOX_INDEX_IDS = {
  [1] = 22797, [2] = 22798, [3] = 22799, [4] = 22800, [5] = 22801,
  [6] = 22802, [7] = 22803, [8] = 22804, [9] = 22805, [10] = 22806,
  [11] = 22807, [12] = 22808, [13] = 22809, [14] = 22810, [15] = 22811,
  [16] = 22812, [17] = 22813, [18] = 31915, [19] = 39723, [20] = 39724
}

local DEPOT_BOX_IDS = {}
for _, id in pairs(DEPOT_BOX_INDEX_IDS) do
  DEPOT_BOX_IDS[id] = true
end

local DEPOT_CONTAINER_EXCLUDES = {
  "inbox", "mail", "market", "stash", "store"
}

local depotReachTarget = nil
local depotReachRetries = 0

local function parseBoxToken(token)
  token = lower(token)
  local box = token:match("^box%s*:?%s*(%d+)$") or
              token:match("^dp%s*:?%s*(%d+)$") or
              token:match("^depot%s*:?%s*(%d+)$")
  box = tonumber(box)
  if box and box > 0 then return box end
  return nil
end

local function getContainerName(container)
  if not container then return "" end
  local ok, name = pcall(function() return container:getName() end)
  if not ok then return "" end
  return lower(name)
end

local function nameHasPattern(name, patterns)
  for _, pattern in ipairs(patterns or {}) do
    if name:find(pattern) then return true end
  end
  return false
end

local function containerNameMatches(container, includePatterns, excludePatterns)
  local name = getContainerName(container)
  if name == "" then return false end
  if nameHasPattern(name, excludePatterns) then return false end
  return nameHasPattern(name, includePatterns)
end

local function findContainerByPatterns(includePatterns, excludePatterns)
  for _, container in pairs(getContainers()) do
    if containerNameMatches(container, includePatterns, excludePatterns) then
      return container
    end
  end
  return nil
end

local function safeCall(fn)
  if type(fn) ~= "function" then return nil end
  local ok, result = pcall(fn)
  if ok then return result end
  return nil
end

local function getDepotDestinationContainer()
  local exact = safeCall(function() return getContainerByName("Depot chest") end)
  if exact then return exact end

  return findContainerByPatterns({"depot chest", "depot"}, DEPOT_CONTAINER_EXCLUDES)
end

local function getDepotRootContainer()
  local exact = safeCall(function() return getContainerByName("Locker") end)
  if exact then return exact end

  return findContainerByPatterns({"locker", "depot"}, DEPOT_CONTAINER_EXCLUDES)
end

local function getInboxContainer()
  local exact = safeCall(function() return getContainerByName("Your inbox") end)
  if exact then return exact end

  return findContainerByPatterns({"your inbox", "inbox", "mail"}, {"market", "stash"})
end

local function getStashContainer()
  local exact = safeCall(function() return getContainerByName("Supply Stash") end)
  if exact then return exact end

  exact = safeCall(function() return getContainerByName("Stash") end)
  if exact then return exact end

  return findContainerByPatterns({"supply stash", "stash"}, {"inbox", "mail", "market"})
end

DepotManagerStashState = DepotManagerStashState or {
  connected = false,
  amounts = {},
  updatedAt = 0
}

local function currentTimeMs()
  return tonumber(now) or safeCall(function() return g_clock.millis() end) or 0
end

local function clearMap(map)
  for key in pairs(map or {}) do
    map[key] = nil
  end
end

local function getRootWidgetCompat()
  if rootWidget then return rootWidget end

  local root = safeCall(function() return g_ui.getRootWidget() end)
  if root then return root end

  return safeCall(function() return modules.game_interface.getRootPanel() end)
end

local function getSupplyStashWindow()
  local root = getRootWidgetCompat()
  if not root then return nil end

  return safeCall(function()
    return root:recursiveGetChildById("stashWindow")
  end)
end

local function isSupplyStashWindowOpen()
  local window = getSupplyStashWindow()
  if not window then return false end

  local hidden = safeCall(function() return window:isHidden() end)
  return hidden ~= true
end

local function closeSupplyStashWindow()
  if not getSupplyStashWindow() then return end

  if type(onSupplyStashClose) == "function" then
    safeCall(onSupplyStashClose)
    return
  end

  local window = getSupplyStashWindow()
  safeCall(function() window:destroy() end)
end

local function onDepotSupplyStashEnter(payload)
  local state = DepotManagerStashState
  clearMap(state.amounts)
  state.updatedAt = currentTimeMs()

  if type(payload) ~= "table" then return end
  for i = 1, #payload do
    local row = payload[i]
    local itemId = tonumber(row and row[1])
    local amount = tonumber(row and row[2])
    if itemId and amount then
      state.amounts[itemId] = amount
    end
  end
end

local function ensureSupplyStashWatcher()
  local state = DepotManagerStashState
  if state.connected then return true end
  if type(connect) ~= "function" or not g_game then return false end

  local ok = pcall(function()
    connect(g_game, { onSupplyStashEnter = onDepotSupplyStashEnter })
  end)

  state.connected = ok == true
  return state.connected
end

local function getKnownStashAmount(itemId)
  itemId = tonumber(itemId)
  if not itemId then return nil end

  local state = DepotManagerStashState
  return state.amounts[itemId], state.updatedAt
end

local function isDepotLikeContainer(container)
  if not container then return true end
  local name = getContainerName(container)
  return name:find("depot") or name:find("locker") or name:find("inbox") or
    name:find("mail") or name:find("market") or name:find("stash") or
    name:find("store")
end

local function closeDepotContainers()
  for _, container in ipairs(getContainers()) do
    if isDepotLikeContainer(container) then
      g_game.close(container)
    end
  end
  closeSupplyStashWindow()
  withdrawState.sourceKey = nil
  withdrawState.openedSourceKey = nil
  withdrawState.stashRequestKey = nil
  withdrawState.stashRequestAt = 0
end

local function closeDepotBoxContainers()
  for _, container in ipairs(getContainers()) do
    if getContainerName(container):find("depot box") then
      g_game.close(container)
    end
  end
  withdrawState.openedSourceKey = nil
end

local function itemIdIn(set, item)
  return item and set[tonumber(item:getId())] == true
end

local function copyPosition(position)
  if not position then return nil end
  return {x = position.x, y = position.y, z = position.z}
end

local function canStandOn(position)
  local tile = position and g_map.getTile(position)
  if not tile then return false end

  if tileHasCreature and tileHasCreature(tile) then return false end

  local ok, walkable = pcall(function() return tile:isWalkable() end)
  return ok and walkable == true
end

local function canReachPosition(position)
  if not position then return false end
  if type(findPath) ~= "function" then return true end

  local ok, path = pcall(function()
    return findPath(pos(), position, 30, {
      ignoreNonPathable = false,
      precision = 0,
      ignoreCreatures = true
    })
  end)

  return ok and path ~= nil
end

local function getDepotAccessPositions(lockerPosition)
  if not lockerPosition then return {} end

  return {
    {x = lockerPosition.x + 1, y = lockerPosition.y, z = lockerPosition.z},
    {x = lockerPosition.x - 1, y = lockerPosition.y, z = lockerPosition.z},
    {x = lockerPosition.x, y = lockerPosition.y + 1, z = lockerPosition.z},
    {x = lockerPosition.x, y = lockerPosition.y - 1, z = lockerPosition.z}
  }
end

local function findNearbyDepotTile()
  for _, tile in pairs(getNearTiles(player:getPosition())) do
    for _, item in pairs(tile:getItems()) do
      if itemIdIn(DEPOT_LOCKER_IDS, item) then
        return tile
      end
    end
  end
  return nil
end

local function findClosestDepotAccessPosition()
  local playerPosition = player:getPosition()
  local bestPosition = nil
  local bestDistance = nil

  for _, tile in pairs(g_map.getTiles(posz())) do
    for _, item in pairs(tile:getItems()) do
      if itemIdIn(DEPOT_LOCKER_IDS, item) then
        local lockerPosition = copyPosition(tile:getPosition())
        local accessPositions = getDepotAccessPositions(lockerPosition)

        for _, accessPosition in ipairs(accessPositions) do
          if canStandOn(accessPosition) and canReachPosition(accessPosition) then
            local distance = getDistanceBetween(playerPosition, accessPosition)
            if not bestDistance or distance < bestDistance then
              bestDistance = distance
              bestPosition = accessPosition
            end
          end
        end

        if not bestPosition then
          local distance = getDistanceBetween(playerPosition, lockerPosition)
          if not bestDistance or distance < bestDistance then
            bestDistance = distance
            bestPosition = lockerPosition
          end
        end
      end
    end
  end

  return bestPosition
end

local function openItem(item, parent)
  if not item then return false end

  if parent then
    g_game.open(item, parent)
  else
    g_game.open(item)
  end

  delay(300)
  return true
end

local function safeMoveTopThing(tile)
  if not tile then return false end

  local topThing = tile:getTopUseThing()
  if not topThing or itemIdIn(DEPOT_LOCKER_IDS, topThing) then return false end

  local ok, notMoveable = pcall(function() return topThing:isNotMoveable() end)
  if ok and not notMoveable then
    g_game.move(topThing, player:getPosition(), topThing:getCount())
    delay(300)
    return true
  end

  return false
end

local function openNearbyDepotLocker()
  local tile = findNearbyDepotTile()
  if not tile then return false end

  for _, item in pairs(tile:getItems()) do
    if itemIdIn(DEPOT_LOCKER_IDS, item) then
      if safeMoveTopThing(tile) then return true end
      return openItem(item)
    end
  end

  return false
end

local function reachDepotCompat()
  if getDepotDestinationContainer() or getDepotRootContainer() or getInboxContainer() or
    getStashContainer() or isSupplyStashWindowOpen() then
    return true
  end

  if findNearbyDepotTile() then
    depotReachTarget = nil
    depotReachRetries = 0
    return true
  end

  local nativeReached = safeCall(function() return CaveBot.ReachDepot() end)
  if nativeReached == true then
    depotReachTarget = nil
    depotReachRetries = 0
    return true
  end

  if depotReachRetries > 30 or
    (depotReachTarget and getDistanceBetween(depotReachTarget, player:getPosition()) > 20) then
    depotReachTarget = nil
    depotReachRetries = 0
  end

  depotReachTarget = depotReachTarget or findClosestDepotAccessPosition()
  if not depotReachTarget then return false end

  if getDistanceBetween(player:getPosition(), depotReachTarget) <= 0 then
    depotReachTarget = nil
    depotReachRetries = 0
    return true
  end

  depotReachRetries = depotReachRetries + 1
  CaveBot.GoTo(depotReachTarget, 0)
  return false
end

local function openItemFromContainer(container, idSet)
  if not container then return false end

  for _, item in pairs(container:getItems()) do
    if itemIdIn(idSet, item) then
      return openItem(item, container)
    end
  end

  return false
end

local function sortedContainerItems(container)
  local result = {}
  if not container then return result end

  for slot, item in pairs(container:getItems()) do
    table.insert(result, { slot = tonumber(slot) or 0, item = item })
  end

  table.sort(result, function(a, b) return a.slot < b.slot end)
  return result
end

local function normalizeContainerSlot(container, slot)
  slot = tonumber(slot) or 0
  if not container then return slot end

  for rawSlot in pairs(container:getItems()) do
    if tonumber(rawSlot) == 0 then
      return slot
    end
  end

  return math.max(0, slot - 1)
end

local function getItemText(item)
  if not item then return "" end

  local parts = {}
  local okName, name = pcall(function() return item:getName() end)
  if okName and name then table.insert(parts, tostring(name)) end

  local okMarket, data = pcall(function() return item:getMarketData() end)
  if okMarket and data and data.name then table.insert(parts, tostring(data.name)) end

  local okTooltip, tooltip = pcall(function() return item:getTooltip() end)
  if okTooltip and tooltip then table.insert(parts, tostring(tooltip)) end

  return lower(table.concat(parts, " "))
end

local function openItemByTextFromContainer(container, includePatterns, excludePatterns)
  if not container then return false end

  for _, wrapped in ipairs(sortedContainerItems(container)) do
    local item = wrapped.item
    local text = getItemText(item)
    if text ~= "" and nameHasPattern(text, includePatterns) and not nameHasPattern(text, excludePatterns) then
      return openItem(item, container)
    end
  end

  return false
end

local function findStashLockerTarget(locker)
  if not locker then return nil, nil end

  for _, wrapped in ipairs(sortedContainerItems(locker)) do
    local item = wrapped.item
    local text = getItemText(item)
    if itemIdIn(STASH_IDS, item) or
      (text ~= "" and nameHasPattern(text, {"supply stash", "stash"}) and not nameHasPattern(text, {"inbox", "mail", "market"})) then
      return item, normalizeContainerSlot(locker, wrapped.slot)
    end
  end

  -- En clientes nuevos el Stash suele ser el segundo icono del Locker: Depot, Stash, Mail.
  local lockerItems = sortedContainerItems(locker)
  local likelyStash = lockerItems[2] and lockerItems[2].item
  if likelyStash and not itemIdIn(DEPOT_CHEST_IDS, likelyStash) and not itemIdIn(INBOX_IDS, likelyStash) then
    return likelyStash, normalizeContainerSlot(locker, lockerItems[2].slot)
  end

  return nil, nil
end

local function getDepotBoxContainer()
  return findContainerByPatterns({"depot box"}, nil)
end

local function getCurrentDepotBoxSourceKey()
  return withdrawState.openedSourceKey
end

local function depotContainerHasBoxes(container)
  if not container then return false end

  for _, item in pairs(container:getItems()) do
    if DEPOT_BOX_IDS[tonumber(item:getId())] then
      return true
    end
  end

  return false
end

local function openDepotChestCompat()
  if getDepotDestinationContainer() then return true end

  local nativeOpened = safeCall(function() return CaveBot.OpenDepotChest() end)
  if nativeOpened == true or getDepotDestinationContainer() then return true end

  local locker = getDepotRootContainer()
  if not locker then
    openNearbyDepotLocker()
    return false
  end

  if openItemFromContainer(locker, DEPOT_CHEST_IDS) then return false end

  if containerNameMatches(locker, {"depot"}, DEPOT_CONTAINER_EXCLUDES) then
    return true
  end

  return false
end

local function reachAndOpenDepotCompat()
  if getDepotDestinationContainer() then return true end
  if not reachDepotCompat() then return false end
  return openDepotChestCompat()
end

local function openDepotBoxCompat(index)
  local boxIndex = tonumber(index) or 1
  local sourceKey = "depot:" .. tostring(boxIndex)
  local openedBox = getDepotBoxContainer()
  if openedBox then
    if getCurrentDepotBoxSourceKey() == sourceKey then
      return true
    end

    closeDepotBoxContainers()
    return false
  end

  if not reachAndOpenDepotCompat() then return false end

  local depot = getDepotDestinationContainer()
  if not depot then return false end

  local boxId = DEPOT_BOX_INDEX_IDS[boxIndex]
  local hasDepotBoxes = false
  local depotBoxItems = {}

  for slot, item in pairs(depot:getItems()) do
    local id = tonumber(item:getId())
    if DEPOT_BOX_IDS[id] then
      hasDepotBoxes = true
      table.insert(depotBoxItems, { slot = tonumber(slot) or 0, item = item })
    end

    if boxId and id == boxId then
      withdrawState.openedSourceKey = sourceKey
      statusMessage("[DepotSettings] abriendo Depot Box " .. boxIndex)
      return openItem(item, depot)
    end
  end

  table.sort(depotBoxItems, function(a, b) return a.slot < b.slot end)

  local fallback = depotBoxItems[boxIndex]
  if fallback and fallback.item then
    withdrawState.openedSourceKey = sourceKey
    statusMessage("[DepotSettings] abriendo Depot Box " .. boxIndex)
    return openItem(fallback.item, depot)
  end

  if not hasDepotBoxes then
    withdrawState.openedSourceKey = sourceKey
  end

  return not hasDepotBoxes
end

local function findDepotSourceContainer(source)
  local sourceKey = "depot:" .. tostring(source.box or 1)
  local depotBox = getDepotBoxContainer()
  if depotBox then
    if getCurrentDepotBoxSourceKey() == sourceKey then
      return depotBox
    end

    return nil
  end

  local depot = getDepotDestinationContainer()
  if depot and not depotContainerHasBoxes(depot) then
    return depot
  end

  return nil
end

local reachAndOpenInboxCompat
local reachAndOpenStashCompat

local function ensureDepotSourceOpen(source)
  if source.type == "inbox" then
    return reachAndOpenInboxCompat()
  end

  if source.type == "stash" then
    return reachAndOpenStashCompat()
  end

  if source.type == "depot" then
    return openDepotBoxCompat(source.box)
  end

  return false
end

local function clearMismatchedDepotBox(source)
  if source.type ~= "depot" then return false end

  local depotBox = getDepotBoxContainer()
  if not depotBox then return false end

  local sourceKey = "depot:" .. tostring(source.box or 1)
  if getCurrentDepotBoxSourceKey() == sourceKey then return false end

  closeDepotBoxContainers()
  return true
end

reachAndOpenInboxCompat = function()
  if getInboxContainer() then return true end
  if not reachDepotCompat() then return false end

  local nativeOpened = safeCall(function() return CaveBot.OpenInbox() end)
  if nativeOpened == true or getInboxContainer() then return true end

  local locker = getDepotRootContainer()
  if not locker then
    openNearbyDepotLocker()
    return false
  end

  return openItemFromContainer(locker, INBOX_IDS)
end

local lastStashWarnAt = 0

local function warnStashNotFound(locker)
  if now and now - lastStashWarnAt < 5000 then return end
  lastStashWarnAt = now or 0

  local ids = {}
  for _, wrapped in ipairs(sortedContainerItems(locker)) do
    local item = wrapped.item
    if item and item.getId then
      table.insert(ids, tostring(item:getId()))
    end
  end

  warn("CaveBot[DepotSettings]: no encontre Stash en Locker. IDs: " .. table.concat(ids, ","))
end

reachAndOpenStashCompat = function()
  ensureSupplyStashWatcher()

  if getStashContainer() or isSupplyStashWindowOpen() then return true end
  if not reachDepotCompat() then return false end

  local locker = getDepotRootContainer()
  if not locker then
    openNearbyDepotLocker()
    return false
  end

  if openItemFromContainer(locker, STASH_IDS) then return false end
  if openItemByTextFromContainer(locker, {"supply stash", "stash"}, {"inbox", "mail", "market"}) then return false end

  local likelyStash = findStashLockerTarget(locker)
  if likelyStash then
    statusMessage("[DepotSettings] abriendo Stash")
    openItem(likelyStash, locker)
    return false
  end

  warnStashNotFound(locker)
  return false
end

local function resetLegacyDepotFlags()
  if not storage.caveBot then return end

  if storage.caveBot.backStop then
    storage.caveBot.backStop = false
    CaveBot.setOff()
  elseif storage.caveBot.backTrainers then
    storage.caveBot.backTrainers = false
    CaveBot.gotoLabel("toTrainers")
  elseif storage.caveBot.backOffline then
    storage.caveBot.backOffline = false
    CaveBot.gotoLabel("toOfflineTraining")
  end
end

local function finishDepotAction()
  closeDepotContainers()
  resetLegacyDepotFlags()
end

local function isStackable(item)
  if not item or not item.isStackable then return false end
  local ok, result = pcall(function() return item:isStackable() end)
  return ok and result
end

local function isContainerItem(item)
  if not item or not item.isContainer then return false end
  local ok, result = pcall(function() return item:isContainer() end)
  return ok and result
end

local function getSupplyIdSet()
  local ids = {}
  if Supplies and Supplies.getItemsData then
    local ok, data = pcall(Supplies.getItemsData)
    if ok and type(data) == "table" then
      for id in pairs(data) do
        id = tonumber(id)
        if id then ids[id] = true end
      end
    end
  end
  return ids
end

local function visibleInventoryAmount(id)
  local total = 0
  id = tonumber(id)
  if not id then return 0 end

  if player and player.getItemsCount then
    local ok, amount = pcall(function() return player:getItemsCount(id) end)
    if ok and tonumber(amount) then
      total = tonumber(amount)
    end
  end

  if total > 0 then return total end

  for _, container in pairs(getContainers()) do
    if not isDepotLikeContainer(container) then
      for _, item in pairs(container:getItems()) do
        if item:getId() == id then
          total = total + item:getCount()
        end
      end
    end
  end

  return total
end

local function adjustCounter(id, amount)
  if not vBot or not vBot.ItemCounter or not vBot.ItemCounter.adjust then return end
  vBot.ItemCounter.adjust(id, amount, "move")
end

local function getEntryCurrentAmount(entry)
  local id = tonumber(entry and entry.id)
  if not id then return 0, "unknown" end

  if DepotManager and DepotManager.countItem then
    local amount, source = DepotManager.countItem(entry)
    return tonumber(amount) or 0, source or "unknown"
  end

  local visible = visibleInventoryAmount(id)
  if vBot and vBot.ItemCounter and vBot.ItemCounter.getAmountInfo then
    local amount, source = vBot.ItemCounter.getAmountInfo(id, visible)
    return tonumber(amount) or 0, source or "unknown"
  end

  if itemAmount then
    return tonumber(itemAmount(id)) or visible, "visible"
  end

  return visible, "visible"
end

local function parseDepositValue(value)
  local parts = splitCsv(value)
  local mode = lower(parts[1])
  if mode == "" then mode = "loot" end

  local plan = {
    mode = mode,
    ids = {},
    except = {},
    reopen = false,
    box = nil,
    supplyIds = getSupplyIdSet()
  }

  if mode ~= "loot" and mode ~= "items" and mode ~= "ids" and mode ~= "all" then
    local firstId = tonumber(parts[1])
    if firstId then
      plan.mode = "items"
      plan.ids[firstId] = true
    else
      return nil, "modo invalido. Usa: loot | items | all"
    end
  end

  if plan.mode == "ids" then plan.mode = "items" end

  local readingExceptions = false
  for i = 2, #parts do
    local raw = parts[i]
    local token = lower(raw)
    local box = parseBoxToken(token)
    local id = tonumber(token)

    if token == "yes" or token == "reopen" or token == "abrir" then
      plan.reopen = true
    elseif token == "no" then
      plan.reopen = false
    elseif token == "except" or token == "exception" or token == "excepto" then
      readingExceptions = true
    elseif box then
      plan.box = box
    elseif id then
      if plan.mode == "all" or readingExceptions then
        plan.except[id] = true
      else
        plan.ids[id] = true
      end
    end
  end

  if plan.mode == "loot" then
    plan.ids = toSet(CaveBot.GetLootItems())
    if not next(plan.ids) then
      return nil, "no hay items configurados en TargetBot loot"
    end
  elseif plan.mode == "items" and not next(plan.ids) then
    return nil, "no hay ids para depositar"
  end

  return plan
end

local function shouldDepositItem(item, plan)
  if not item or not plan then return false end
  local id = item:getId()
  if not id or id <= 0 then return false end

  if plan.mode == "all" then
    if plan.except[id] or plan.supplyIds[id] then return false end
    return not isContainerItem(item)
  end

  return plan.ids[id] == true
end

local function findDepositCandidate(plan)
  for _, container in pairs(getContainers()) do
    if not isDepotLikeContainer(container) then
      for _, item in pairs(container:getItems()) do
        if shouldDepositItem(item, plan) then
          return item, container
        end
      end
    end
  end
  return nil, nil
end

local function findInventoryItemById(id)
  id = tonumber(id)
  if not id then return nil end

  for _, container in pairs(getContainers()) do
    if not isDepotLikeContainer(container) then
      for _, item in pairs(container:getItems()) do
        if item:getId() == id then
          return item, container
        end
      end
    end
  end

  return nil, nil
end

local function openNestedLootContainer()
  local lootContainers = CaveBot.GetLootContainers()
  if type(lootContainers) ~= "table" or #lootContainers == 0 then return false end

  for _, container in pairs(getContainers()) do
    if not isDepotLikeContainer(container) then
      for _, item in pairs(container:getItems()) do
        if listHasId(lootContainers, item:getId()) then
          g_game.open(item, container)
          delay(300)
          return true
        end
      end
    end
  end

  return false
end

local function getDepositIndex(item, plan)
  if plan.box then
    return math.max(0, plan.box - 1)
  end

  if type(getStashingIndex) == "function" then
    local configured = getStashingIndex(item:getId())
    if configured then return configured end
  end

  return isStackable(item) and 1 or 0
end

local function parseWithdrawSource(raw)
  local token = lower(raw)
  if token == "inbox" or token == "mail" or token == "correo" then
    return { type = "inbox" }
  end

  if token == "stash" or token == "supply stash" then
    return { type = "stash" }
  end

  local box = parseBoxToken(token) or tonumber(token)
  if box and box > 0 then
    return { type = "depot", box = box }
  end

  return nil
end

local function parseWithdrawValue(value)
  local parts = splitCsv(value)
  if #parts < 3 then
    return nil, "formato invalido. Usa: inbox,itemId,cantidad[,contenedor], stash,itemId,cantidad[,contenedor] o box:3,itemId,cantidad[,contenedor]"
  end

  local source = parseWithdrawSource(parts[1])
  local id = tonumber(parts[2])
  local amount = tonumber(parts[3])
  local destination = trim(parts[4] or "")

  if not source then return nil, "origen invalido. Usa inbox, stash o box:N" end
  if not id or not amount or amount <= 0 then return nil, "itemId/cantidad invalida" end

  return {
    source = source,
    id = id,
    amount = amount,
    destination = destination
  }
end

local function findSourceContainer(source)
  if source.type == "inbox" then
    return getInboxContainer()
  end

  if source.type == "stash" then
    return getStashContainer()
  end

  if source.type == "depot" then
    return findDepotSourceContainer(source)
  end

  return nil
end

local function findDestinationContainer(destinationName)
  if destinationName and destinationName ~= "" then
    return getContainerByName(destinationName, true)
  end

  for _, container in pairs(getContainers()) do
    local name = getContainerName(container)
    if container:getCapacity() > #container:getItems() and not isDepotLikeContainer(container) and
      not name:find("quiver") and not name:find("loot") then
      return container
    end
  end

  return nil
end

local function openNextContainer(container)
  if not container or not containerIsFull(container) then return false end
  local containerItem = container:getContainerItem()
  if not containerItem then return false end
  local containerId = containerItem:getId()

  for _, item in pairs(container:getItems()) do
    if item:getId() == containerId then
      g_game.open(item, container)
      delay(300)
      return true
    end
  end

  return false
end

local function ensureWithdrawDestination(destinationName)
  local destination = findDestinationContainer(destinationName)
  if not destination then
    return false, "no hay contenedor destino abierto"
  end

  if containerIsFull(destination) then
    if openNextContainer(destination) then return "retry" end
    return false, "contenedor destino lleno"
  end

  return true
end

local function requestStashWithdraw(itemId, amount)
  itemId = tonumber(itemId)
  amount = tonumber(amount) or 0
  if not itemId or amount <= 0 then return true end

  ensureSupplyStashWatcher()

  if not g_game or type(g_game.stashWithdraw) ~= "function" then
    return false, "este cliente no expone g_game.stashWithdraw"
  end

  if not isSupplyStashWindowOpen() then
    reachAndOpenStashCompat()
    return "retry"
  end

  local knownAmount = getKnownStashAmount(itemId)
  if knownAmount ~= nil and knownAmount <= 0 then
    return true, "no hay unidades de " .. itemId .. " en el stash"
  end

  local toWithdraw = math.max(1, math.min(amount, knownAmount or amount))
  local requestKey = tostring(itemId) .. ":" .. tostring(toWithdraw)
  local timeNow = currentTimeMs()

  if withdrawState.stashRequestKey == requestKey and
    timeNow - (withdrawState.stashRequestAt or 0) < 1200 then
    return "retry"
  end

  local ok, err = pcall(function()
    g_game.stashWithdraw(itemId, toWithdraw, 1)
  end)

  if not ok then
    return false, tostring(err)
  end

  withdrawState.stashRequestKey = requestKey
  withdrawState.stashRequestAt = timeNow

  if knownAmount ~= nil then
    DepotManagerStashState.amounts[itemId] = math.max(0, knownAmount - toWithdraw)
  end

  statusMessage("[DepotSettings] retirando del Stash " .. itemId .. " x" .. toWithdraw)
  adjustCounter(itemId, toWithdraw)
  delay(350)
  return "retry"
end

local function runDepositPlanAction(value, retries)
  local plan, err = parseDepositValue(value)
  if not plan then
    warn("CaveBot[DepositItems]: " .. err)
    finishDepotAction()
    return false
  end

  if depositState.value ~= value or retries == 0 then
    depositState.value = value
  end

  if retries > 450 then
    warn("CaveBot[DepositItems]: limite de intentos alcanzado, avanzando")
    finishDepotAction()
    return true
  end

  if not reachAndOpenDepotCompat() then
    return "retry"
  end

  CaveBot.PingDelay(2)

  local destination = getDepotDestinationContainer()
  if not destination then return "retry" end

  local item = findDepositCandidate(plan)
  if not item then
    if plan.reopen and openNestedLootContainer() then
      return "retry"
    end

    print("CaveBot[DepositItems]: deposito terminado")
    finishDepotAction()
    return true
  end

  local index = getDepositIndex(item, plan)
  statusMessage("[DepositItems] depositando item: " .. item:getId() .. " box " .. (index + 1))
  g_game.move(item, destination:getSlotPosition(index), item:getCount())
  adjustCounter(item:getId(), -item:getCount())
  delay(150)
  return "retry"
end

local function runWithdrawPlanAction(value, retries)
  local plan, err = parseWithdrawValue(value)
  if not plan then
    warn("CaveBot[WithdrawItems]: " .. err)
    finishDepotAction()
    return false
  end

  if retries > 250 then
    warn("CaveBot[WithdrawItems]: limite de intentos alcanzado, avanzando")
    finishDepotAction()
    return true
  end

  local currentAmount = visibleInventoryAmount(plan.id)
  if currentAmount >= plan.amount then
    print("CaveBot[WithdrawItems]: cantidad suficiente, avanzando")
    finishDepotAction()
    return true
  end

  if plan.source.type == "stash" then
    local destinationReady, destinationErr = ensureWithdrawDestination(plan.destination)
    if destinationReady == "retry" then return "retry" end
    if not destinationReady then
      warn("CaveBot[WithdrawItems]: " .. destinationErr)
      finishDepotAction()
      return false
    end

    local result, err = requestStashWithdraw(plan.id, plan.amount - currentAmount)
    if result == "retry" then return "retry" end
    if result == true then
      if err then warn("CaveBot[WithdrawItems]: " .. err) end
      finishDepotAction()
      return true
    end

    warn("CaveBot[WithdrawItems]: no pude retirar del Stash: " .. tostring(err))
    finishDepotAction()
    return false
  end

  local sourceContainer = findSourceContainer(plan.source)
  if not sourceContainer then
    if clearMismatchedDepotBox(plan.source) then return "retry" end
    if not ensureDepotSourceOpen(plan.source) then return "retry" end
    return "retry"
  end

  local destination = findDestinationContainer(plan.destination)
  if not destination then
    warn("CaveBot[WithdrawItems]: no hay contenedor destino abierto")
    finishDepotAction()
    return false
  end

  if containerIsFull(destination) then
    if openNextContainer(destination) then return "retry" end
    warn("CaveBot[WithdrawItems]: contenedor destino lleno")
    finishDepotAction()
    return false
  end

  CaveBot.PingDelay(2)

  local current = visibleInventoryAmount(plan.id)
  for _, item in pairs(sourceContainer:getItems()) do
    if item:getId() == plan.id then
      local toMove = math.max(1, math.min(item:getCount(), plan.amount - current))
      if not isStackable(item) then toMove = 1 end
      statusMessage("[WithdrawItems] retirando item: " .. plan.id .. " x" .. toMove)
      g_game.move(item, destination:getSlotPosition(destination:getItemsCount()), toMove)
      adjustCounter(plan.id, toMove)
      delay(150)
      return "retry"
    end
  end

  warn("CaveBot[WithdrawItems]: no encontre el item " .. plan.id .. " en el origen")
  finishDepotAction()
  return true
end

local function getConfiguredEntries(mode)
  if DepotManager and DepotManager.getEntries then
    return DepotManager.getEntries(mode)
  end
  return {}
end

local function hasConfiguredWork(mode)
  local entries = getConfiguredEntries(mode)
  for _, entry in ipairs(entries) do
    local current = getEntryCurrentAmount(entry)
    local amount = tonumber(entry.amount) or 0
    if mode == "deposit" and current > amount then
      return true
    elseif mode == "withdraw" and current < amount then
      return true
    end
  end
  return false
end

local function getEntryStorageType(entry)
  local source = lower(entry and entry.source or "box")
  if source == "stash" then return "stash" end
  return "box"
end

local function getEntryWithdrawSource(entry)
  local source = lower(entry and entry.source or "box")
  if source == "inbox" then return { type = "inbox" } end
  if source == "stash" then return { type = "stash" } end
  return { type = "depot", box = tonumber(entry and entry.box) or 1 }
end

local function getSourceKey(source)
  if not source then return "unknown" end
  if source.type == "depot" then return "depot:" .. tostring(source.box or 1) end
  return source.type or "unknown"
end

local function getDepositDestinationForEntry(entry)
  if getEntryStorageType(entry) == "stash" then
    if not reachDepotCompat() then return nil, nil, "stash" end

    local locker = getDepotRootContainer()
    if not locker then
      openNearbyDepotLocker()
      return nil, nil, "stash"
    end

    local stashItem, stashSlot = findStashLockerTarget(locker)
    if not stashItem or stashSlot == nil then
      warnStashNotFound(locker)
      return nil, nil, "stash"
    end

    return locker, stashSlot, "stash"
  end

  if not reachAndOpenDepotCompat() then return nil, nil, "box" end

  local destination = getDepotDestinationContainer()
  local index = math.max(0, (tonumber(entry and entry.box) or 1) - 1)
  return destination, index, "box"
end

local function processConfiguredDeposit(retries)
  local entries = getConfiguredEntries("deposit")
  if #entries == 0 then
    warn("CaveBot[DepotSettings]: no hay reglas Deposit activas en Depot Settings")
    finishDepotAction()
    return true
  end

  if not hasConfiguredWork("deposit") then
    warn("CaveBot[DepotSettings]: no hay items pendientes para depositar")
    finishDepotAction()
    return true
  end

  if retries > 450 then
    warn("CaveBot[DepotSettings]: limite depositando, avanzando")
    finishDepotAction()
    return true
  end

  if not reachDepotCompat() then
    return "retry"
  end

  CaveBot.PingDelay(2)

  for _, entry in ipairs(entries) do
    local current, source = getEntryCurrentAmount(entry)
    local keep = tonumber(entry.amount) or 0
    local excess = current - keep

    if excess > 0 then
      local item = findInventoryItemById(entry.id)
      if item then
        local toMove = math.max(1, math.min(item:getCount(), excess))
        if not isStackable(item) then toMove = 1 end
        local destination, index, storageType = getDepositDestinationForEntry(entry)
        if not destination then return "retry" end

        local targetLabel = storageType == "stash" and "stash" or ("box " .. (index + 1))
        statusMessage("[DepotSettings] depositando " .. entry.id .. " x" .. toMove .. " " .. targetLabel)
        g_game.move(item, destination:getSlotPosition(index), toMove)
        adjustCounter(entry.id, -toMove)
        delay(150)
        return "retry"
      else
        warn("CaveBot[DepotSettings]: " .. entry.id .. " cuenta " .. current .. " por " .. tostring(source) .. ", pero no esta visible para moverlo")
      end
    end
  end

  finishDepotAction()
  return true
end

local function processConfiguredWithdraw(retries)
  local entries = getConfiguredEntries("withdraw")
  if #entries == 0 then
    warn("CaveBot[DepotSettings]: no hay reglas Withdraw activas en Depot Settings")
    finishDepotAction()
    return true
  end

  if not hasConfiguredWork("withdraw") then
    warn("CaveBot[DepotSettings]: no hay items pendientes para retirar")
    finishDepotAction()
    return true
  end

  if retries > 350 then
    warn("CaveBot[DepotSettings]: limite retirando, avanzando")
    finishDepotAction()
    return true
  end

  for _, entry in ipairs(entries) do
    local current = getEntryCurrentAmount(entry)
    local target = tonumber(entry.amount) or 0

    if current < target then
      local source = getEntryWithdrawSource(entry)
      local sourceKey = getSourceKey(source)

      if source.type == "stash" then
        local destinationReady, destinationErr = ensureWithdrawDestination(entry.destination)
        if destinationReady == "retry" then return "retry" end
        if not destinationReady then
          warn("CaveBot[DepotSettings]: " .. destinationErr .. " para retirar " .. entry.id)
          finishDepotAction()
          return false
        end

        local result, err = requestStashWithdraw(entry.id, target - current)
        if result == "retry" then return "retry" end
        if result == true then
          if err then warn("CaveBot[DepotSettings]: " .. err) end
          finishDepotAction()
          return true
        end

        warn("CaveBot[DepotSettings]: no pude retirar del Stash: " .. tostring(err))
        finishDepotAction()
        return false
      end

      if withdrawState.sourceKey and withdrawState.sourceKey ~= sourceKey then
        closeDepotBoxContainers()
        withdrawState.sourceKey = nil
        return "retry"
      end
      withdrawState.sourceKey = sourceKey

      local sourceContainer = findSourceContainer(source)
      if not sourceContainer then
        if clearMismatchedDepotBox(source) then return "retry" end
        if not ensureDepotSourceOpen(source) then return "retry" end
        return "retry"
      end

      local destination = findDestinationContainer(entry.destination)
      if not destination then
        warn("CaveBot[DepotSettings]: no hay contenedor destino abierto para retirar " .. entry.id)
        finishDepotAction()
        return false
      end

      if containerIsFull(destination) then
        if openNextContainer(destination) then return "retry" end
        warn("CaveBot[DepotSettings]: contenedor destino lleno")
        finishDepotAction()
        return false
      end

      CaveBot.PingDelay(2)

      for _, item in ipairs(sourceContainer:getItems()) do
        if item:getId() == entry.id then
          local toMove = math.max(1, math.min(item:getCount(), target - current))
          if not isStackable(item) then toMove = 1 end

          statusMessage("[DepotSettings] retirando " .. entry.id .. " x" .. toMove)
          g_game.move(item, destination:getSlotPosition(destination:getItemsCount()), toMove)
          adjustCounter(entry.id, toMove)
          delay(150)
          return "retry"
        end
      end

      warn("CaveBot[DepotSettings]: no encontre " .. entry.id .. " en el origen configurado")
    end
  end

  finishDepotAction()
  return true
end

local function processConfiguredAction(value, retries)
  local mode = lower(value)
  if mode == "" then mode = "all" end

  if mode == "deposit" or mode == "deposits" or mode == "depositar" then
    return processConfiguredDeposit(retries)
  end

  if mode == "withdraw" or mode == "withdraws" or mode == "retirar" then
    return processConfiguredWithdraw(retries)
  end

  if mode ~= "all" and mode ~= "todo" then
    warn("CaveBot[DepotSettings]: modo invalido. Usa deposit, withdraw o all")
    return false
  end

  local deposited = processConfiguredDeposit(retries)
  if deposited ~= true then return deposited end

  return processConfiguredWithdraw(retries)
end

local function addDepotSettingsAction(actionName)
  local focusedAction = CaveBot.actionList:getFocusedChild()
  local index = CaveBot.actionList:getChildCount()
  if focusedAction then
    index = CaveBot.actionList:getChildIndex(focusedAction)
  end

  local widget = CaveBot.addAction(actionName, "settings")
  CaveBot.actionList:moveChildToIndex(widget, index + 1)
  CaveBot.actionList:focusChild(widget)
  CaveBot.save()
end

local function addDepotAction(mode)
  local focusedAction = CaveBot.actionList:getFocusedChild()
  local index = CaveBot.actionList:getChildCount()
  if focusedAction then
    index = CaveBot.actionList:getChildIndex(focusedAction)
  end

  local widget = CaveBot.addAction("depot", mode or "all")
  CaveBot.actionList:moveChildToIndex(widget, index + 1)
  CaveBot.actionList:focusChild(widget)
  CaveBot.save()
end

local function normalizeDepotMode(value)
  local mode = lower(value)
  if mode == "depositar" or mode == "deposits" then return "deposit" end
  if mode == "retirar" or mode == "withdraws" then return "withdraw" end
  if mode == "todo" or mode == "" then return "all" end
  if mode == "deposit" or mode == "withdraw" or mode == "all" then return mode end
  return "all"
end

local function showDepotActionSelector(value, callback)
  local editor = UI.createWindow("CaveBotDepotActionWindow")
  local selectedMode = normalizeDepotMode(value)
  local buttons = {
    deposit = editor.deposit,
    withdraw = editor.withdraw,
    all = editor.all
  }
  local labels = {
    deposit = "Deposita usando las reglas Deposit de Depot Settings.",
    withdraw = "Retira usando las reglas Withdraw de Depot Settings.",
    all = "Primero deposita y despues retira lo que falte."
  }

  local function selectMode(mode)
    selectedMode = mode
    for key, button in pairs(buttons) do
      button:setOn(key == selectedMode)
    end
    editor.preview:setText(labels[selectedMode] or "")
  end

  for mode, button in pairs(buttons) do
    button.onClick = function()
      selectMode(mode)
    end
  end

  editor.cancel.onClick = function()
    editor:destroy()
  end
  editor.onEscape = editor.cancel.onClick

  editor.ok.onClick = function()
    editor:destroy()
    callback("depot", selectedMode)
  end

  selectMode(selectedMode)
end

CaveBot.Extensions.DepotManager.setup = function()
  ensureSupplyStashWatcher()

  CaveBot.registerAction("depot", "#55D8FF", function(value, retries)
    return processConfiguredAction(value, retries)
  end)

  CaveBot.Editor.editDepotAction = showDepotActionSelector

  local depotButton = CaveBot.Editor.registerAction("depot", "Depot", function()
    showDepotActionSelector("all", function(action, value)
      addDepotAction(value)
    end)
  end)
  if depotButton then depotButton:setColor("#55D8FF") end

  CaveBot.registerAction("deposit", "#37A2FF", function(value, retries)
    return processConfiguredDeposit(retries)
  end)

  CaveBot.registerAction("withdraw", "#00C878", function(value, retries)
    return processConfiguredWithdraw(retries)
  end)
end
