CaveBot.Extensions.BuySupplies = {}

-- Native v15 purchase support is opt-in; legacy purchases stay capped at 100.
local CLIENT_MAX_TRADE_QUANTITY = 65535
local MODAL_CONFIRM_TIMEOUT = 20
local PARTIAL_SETTLE_SECONDS = 3
local RECOVERED_INVENTORY_GRACE_SECONDS = 6
local MAX_PARTIAL_BATCHES = 6
local CATEGORY_SHOP_TIMEOUT = 8

local tradeRequest = { key = nil, lastRetry = nil, attempts = 0 }

local function resetTradeRequest(key, retries)
  if retries == 0 or tradeRequest.key ~= key then
    tradeRequest.key = key
    tradeRequest.lastRetry = nil
    tradeRequest.attempts = 0
    tradeRequest.activeFilter = nil
    tradeRequest.filtersTried = {}
    tradeRequest.categoryWaiting = false
    tradeRequest.categoryRequestedAt = nil
    tradeRequest.categoryBaseline = nil
    tradeRequest.partialBatches = {}
  end
end

-- MythicOTC can display its NPC shop without exposing the OTCv8 npcWindow
-- used by NPC.isTrading(). Track the protocol event that opens the shop.
local npcTrade = { open = false, items = {} }
local tradeWatcherConnected = false
local tradeWatcherError = nil
local tradeBridge = nil

local function clearNpcTrade()
  npcTrade.open = false
  npcTrade.items = {}
end

local function readBuyItem(entry)
  if type(entry) ~= "table" then return nil end
  local item = entry.ptr or entry.item or entry[1]
  local id = tonumber(entry.id or entry.itemId)
  if not id and item then
    local ok, result = pcall(function() return item:getId() end)
    if ok then id = tonumber(result) end
  end
  if not id and type(item) == "number" then id = item end
  if id and type(item) == "number" and Item and Item.create then
    item = Item.create(id)
  end
  local price = tonumber(entry.buyPrice or entry.price or entry[4])
  if not id or not item or not price or price <= 0 then return nil end
  return { id = id, item = item }
end

local function onOpenNpcTrade(items)
  clearNpcTrade()
  npcTrade.open = true
  if type(items) ~= "table" then return end
  for _, entry in pairs(items) do
    local item = readBuyItem(entry)
    if item then npcTrade.items[#npcTrade.items + 1] = item end
  end
end

local function getOpenBuyItems()
  if npcTrade.open then
    if #npcTrade.items > 0 then return npcTrade.items end
    local trade = modules.game_npctrade
    local list = trade and trade.tradeItems and trade.tradeItems[trade.BUY]
    local items = {}
    if type(list) == "table" then
      for _, entry in pairs(list) do
        local item = readBuyItem(entry)
        if item then items[#items + 1] = item end
      end
    end
    return items
  end
  if NPC.isTrading() then return NPC.getBuyItems() end
  return nil
end

local function safeWidgetValue(widget, method)
  local ok, value = pcall(function() return widget[method](widget) end)
  if ok then return value end
  return nil
end

local function safeWidgetProperty(widget, name)
  local ok, value = pcall(function() return widget[name] end)
  if ok then return value end
  return nil
end

local function childById(parent, id)
  if not parent then return nil end
  local ok, child = pcall(function() return parent:recursiveGetChildById(id) end)
  if ok then return child end
  return nil
end

-- Opening/closing or paging backpacks can change visible counts without a
-- purchase. Only reconcile a partial batch against the same inventory view.
local function inventoryViewSignature()
  if not g_game or type(g_game.getContainers) ~= "function" then return nil end
  local ok, containers = pcall(g_game.getContainers)
  if not ok or type(containers) ~= "table" then return nil end
  local parts = {}
  for id, container in pairs(containers) do
    local item = safeWidgetValue(container, "getContainerItem")
    parts[#parts + 1] = tostring(id) .. ":" ..
      tostring(item and safeWidgetValue(item, "getId")) .. ":" ..
      tostring(safeWidgetValue(container, "getFirstIndex"))
  end
  table.sort(parts)
  return table.concat(parts, ",")
end

-- MythicOTC 15 can keep an old NPC name while replacing the shop contents.
local function getModalBuyItems(expectedNpc)
  local root = g_ui and g_ui.getRootWidget and g_ui.getRootWidget()
  local modal = childById(root, "npcModalWindow")
  if not modal or safeWidgetValue(modal, "isVisible") ~= true then return nil, "closed" end

  local nameLabel = childById(modal, "npcName")
  local shownName = tostring(safeWidgetValue(nameLabel, "getText") or "")

  local panel = childById(modal, "npcTradeItemsPanel")
  if not panel or safeWidgetValue(panel, "isVisible") ~= true then
    return nil, "items_hidden", shownName
  end

  local items = {}
  local rows = safeWidgetValue(panel, "getChildren")
  if type(rows) == "table" then
    for _, row in ipairs(rows) do
      local icon = childById(row, "itemIcon")
      local item = icon and safeWidgetValue(icon, "getItem")
      local id = item and tonumber(safeWidgetValue(item, "getId"))
      if id and id > 0 then
        items[#items + 1] = { id = id, item = item, row = row, icon = icon }
      end
    end
  end
  local status = shownName:lower() == tostring(expectedNpc):lower() and
    "modal" or "label_mismatch"
  return items, status, shownName, modal
end

local function supplyShopCategory(id)
  local name = nil
  if vBot and vBot.ItemCounter and vBot.ItemCounter.getName then
    name = vBot.ItemCounter.getName(id)
  end
  if (not name or name == tostring(id)) and Item and Item.create then
    local ok, item = pcall(Item.create, id)
    if ok and item then
      local data = safeWidgetValue(item, "getMarketData")
      name = data and data.name or name
    end
  end
  name = tostring(name or ""):lower()
  if name:find("potion", 1, true) then return "potions" end
  if name:find("rune", 1, true) then return "runes" end
  return nil
end

local function shopSignature(items)
  local ids, seen = {}, {}
  for _, entry in ipairs(items or {}) do
    local id = tonumber(entry.id)
    if id and not seen[id] then
      seen[id] = true
      ids[#ids + 1] = id
    end
  end
  table.sort(ids)
  for i, id in ipairs(ids) do ids[i] = tostring(id) end
  return table.concat(ids, ",")
end

-- Xodet exposes smaller catalogs through NPC dialogue. Close the old modal
-- before asking for another category so an old list cannot be bought as new.
local function requestCategoryShop(modal, items, category)
  local ok, err = pcall(function()
    if type(CaveBot.Conversation) ~= "function" then
      error("NPC conversation is unavailable")
    end
    if NPC and type(NPC.closeTrade) == "function" then NPC.closeTrade() end
    modal:hide()
    CaveBot.Conversation("bye", "hi", category)
  end)
  if not ok then return false, tostring(err) end
  tradeRequest.activeFilter = category
  tradeRequest.categoryBaseline = shopSignature(items)
  tradeRequest.categoryRequestedAt = os.time()
  tradeRequest.categoryWaiting = true
  return true
end

local function matchesModalIdentity(items, status, shownName, identity)
  -- The title is informational. Keep the fresh shop's catalog stable while
  -- selecting Buy, the item and the quantity, including when the title changes.
  return items and identity and
    (status == "modal" or status == "label_mismatch") and
    shopSignature(items) == identity.signature
end

-- Ask the v15 shop for the full shortfall, then verify the resulting count.
local function requestModalPurchase(entry, modal, npcName, current, wanted, identity, diagnostic)
  local npcModule = modules and modules.game_npcmodal
  local selectBuyMode = npcModule and npcModule.onNpcTradeBuyClick
  if type(selectBuyMode) ~= "function" then
    diagnostic.stage = "modal_buy_mode_unavailable"
    warn("CaveBot[BuySupplies]: client Buy mode is unavailable")
    CaveBot.setOff()
    return false
  end

  -- This refreshes the item rows, so the entry found before it must be discarded.
  local modeOk, modeError = pcall(selectBuyMode)
  if not modeOk then
    diagnostic.stage = "modal_buy_mode_failed"
    diagnostic.error = tostring(modeError)
    CaveBot.setOff()
    return false
  end
  local refreshedItems, status, shownNpc, refreshedModal = getModalBuyItems(npcName)
  if refreshedModal ~= modal or
      not matchesModalIdentity(refreshedItems, status, shownNpc, identity) then
    diagnostic.stage = "modal_changed_after_buy_mode"
    diagnostic.shownNpc = shownNpc
    CaveBot.setOff()
    return false
  end
  local refreshedEntry
  for _, candidate in ipairs(refreshedItems) do
    if candidate.id == entry.id then refreshedEntry = candidate break end
  end
  local preview = childById(modal, "item2")
  local quantity = childById(modal, "userInput")
  local countSlider = childById(modal, "countScrollBar")
  local buyButton = childById(modal, "BuySellButton")
  local modeButton = childById(modal, "buyButton")
  local sellModeButton = childById(modal, "sellButton")
  if not refreshedEntry or not preview or not quantity or not countSlider or
      not buyButton or not modeButton or not sellModeButton then
    diagnostic.stage = "modal_controls_missing"
    warn("CaveBot[BuySupplies]: NPC shop controls are incomplete")
    CaveBot.setOff()
    return false
  end

  diagnostic.selectionAttempts = {}
  local callback = safeWidgetProperty(refreshedEntry.row, "onMousePress")
  local selected = false
  if type(callback) == "function" then
    local ok, callbackError = pcall(function()
      callback(refreshedEntry.row,
        safeWidgetValue(refreshedEntry.row, "getPosition"), MouseLeftButton or 1)
    end)
    local previewId = tonumber(safeWidgetValue(preview, "getItemId")) or 0
    diagnostic.selectionAttempts[1] = {
      action = "rowLeftPress", ok = ok,
      error = not ok and tostring(callbackError) or nil, previewId = previewId
    }
    selected = ok and previewId == entry.id
  end
  if not selected then
    diagnostic.itemId = entry.id
    diagnostic.previewId = safeWidgetValue(preview, "getItemId")
    diagnostic.stage = "modal_selection_failed"
    warn("CaveBot[BuySupplies]: shop item was not selected; no purchase sent")
    CaveBot.setOff()
    return false
  end

  local requested = math.min(CLIENT_MAX_TRADE_QUANTITY, math.floor(wanted))
  local sliderMaximum = tonumber(safeWidgetValue(countSlider, "getMaximum"))
  diagnostic.sliderMaximum = sliderMaximum
  diagnostic.requestedAmount = requested
  -- The native maximum can reflect capacity, money and the per-trade limit.
  -- Do not overwrite that limit by putting the full shortfall in userInput.
  if sliderMaximum then requested = math.min(requested, math.floor(sliderMaximum)) end
  if requested < 1 then
    diagnostic.stage = "modal_quantity_unavailable"
    diagnostic.itemId = entry.id
    warn("CaveBot[BuySupplies]: la tienda no permite comprar mas; revisa cap, oro y espacio en BP")
    CaveBot.setOff()
    return false
  end
  local amountSet = pcall(function()
    countSlider:setValue(requested)
    quantity:setText(tostring(requested))
    local onTextChange = safeWidgetProperty(quantity, "onTextChange")
    if type(onTextChange) == "function" then onTextChange(quantity) end
  end)
  local amount = tonumber(safeWidgetValue(quantity, "getText"))
  diagnostic.acceptedAmount = amount
  local latestItems, latestStatus, latestName, latestModal = getModalBuyItems(npcName)
  if not amountSet or not amount or amount < 1 or amount > requested or
      amount ~= math.floor(amount) or
      latestModal ~= modal or
      not matchesModalIdentity(latestItems, latestStatus, latestName, identity) or
      tonumber(safeWidgetValue(preview, "getItemId")) ~= entry.id or
      safeWidgetValue(modeButton, "isOn") ~= true or
      safeWidgetValue(sellModeButton, "isOn") ~= false or
      safeWidgetValue(buyButton, "isEnabled") ~= true or
      tostring(safeWidgetValue(buyButton, "getText") or ""):lower() ~= "buy" then
    diagnostic.stage = "modal_purchase_guard_failed"
    diagnostic.itemId = entry.id
    diagnostic.confirmText = safeWidgetValue(buyButton, "getText")
    diagnostic.buyModeOn = safeWidgetValue(modeButton, "isOn")
    diagnostic.sellModeOn = safeWidgetValue(sellModeButton, "isOn")
    diagnostic.quantityText = safeWidgetValue(quantity, "getText")
    warn("CaveBot[BuySupplies]: shop selection/quantity changed; no purchase sent")
    CaveBot.setOff()
    return false
  end

  local visibleBefore = player and player:getItemsCount(entry.id) or 0
  storage.sabuezoBuySuppliesPending = {
    npc = npcName, itemId = entry.id, amount = amount,
    before = current, visibleBefore = visibleBefore, requestedAt = os.time(),
    observedCurrent = current, observedVisible = visibleBefore,
    lastInventoryChangeAt = os.time(), inventoryView = inventoryViewSignature()
  }
  diagnostic.stage = "modal_batch_requested"
  diagnostic.itemId = entry.id
  diagnostic.amount = amount
  diagnostic.visibleBefore = visibleBefore
  local ok, buyError = pcall(function()
    -- onConfirmTrade can return silently when its private selected-entry or
    -- quantity state is stale, even though the modal preview looks correct.
    -- The selected row provides the same Item passed to g_game.buyItem by the
    -- client's Buy button. Keep the UI/identity guards above before sending.
    g_game.buyItem(refreshedEntry.item, amount, false, false)
  end)
  if not ok then
    storage.sabuezoBuySuppliesPending = nil
    diagnostic.stage = "modal_batch_failed"
    diagnostic.error = tostring(buyError)
    warn("CaveBot[BuySupplies]: shop request failed: " .. tostring(buyError))
    CaveBot.setOff()
  else
    print("CaveBot[BuySupplies]: requested " .. amount .. "x " .. entry.id ..
      "; waiting for inventory confirmation")
    CaveBot.delay(500)
    return "retry"
  end
  return false
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
  -- Hide any boat/previous shop before requesting a fresh list from the NPC
  -- reached by this waypoint. Reopening, rather than the title, proves freshness.
  if type(CaveBot.CloseNpcWindows) == "function" then
    CaveBot.CloseNpcWindows()
  else
    if NPC and type(NPC.closeTrade) == "function" then pcall(NPC.closeTrade) end
    local root = g_ui and g_ui.getRootWidget and g_ui.getRootWidget()
    local modal = childById(root, "npcModalWindow")
    if modal then pcall(function() modal:hide() end) end
  end
  clearNpcTrade()
  tradeWord = trimText(tradeWord)
  if tradeWord ~= "" then
    CaveBot.Conversation("hi", tradeWord)
  else
    CaveBot.OpenNpcTrade()
  end
end

CaveBot.Extensions.BuySupplies.setup = function()
  if type(connect) == "function" and g_game then
    -- Native connections may outlive a bot reload. Reuse one dispatcher and
    -- replace its handlers instead of retaining another old bot context.
    local host = modules and modules.game_bot
    tradeBridge = (host and host._sabuezoBuySuppliesTradeBridge) or tradeBridge or {}
    if host then host._sabuezoBuySuppliesTradeBridge = tradeBridge end
    tradeBridge.onOpen = onOpenNpcTrade
    tradeBridge.onClose = clearNpcTrade
    local bridge = tradeBridge
    local connected, connectError = pcall(function()
      if bridge.connected then return end
      connect(g_game, {
        onOpenNpcTrade = function(items) bridge.onOpen(items) end,
        onCloseNpcTrade = function() bridge.onClose() end,
        onGameEnd = function() bridge.onClose() end
      })
      bridge.connected = true
    end)
    if not connected then
      tradeWatcherConnected = false
      tradeWatcherError = tostring(connectError)
    else
      tradeWatcherConnected = true
      tradeWatcherError = nil
    end
  else
    tradeWatcherConnected = false
    tradeWatcherError = "connect=" .. type(connect) .. ", g_game=" .. type(g_game)
  end

  CaveBot.registerAction("BuySupplies", "#C300FF", function(value, retries)
    local possibleItems = {}
    resetTradeRequest(value, retries)

    local npcName, tradeWord, waitVal, parseError = parseBuySuppliesValue(value)
    if parseError then
      warn("CaveBot[BuySupplies]: " .. parseError)
      return false 
    end

    local previousDiagnostic = storage.sabuezoBuySuppliesDiagnostic
    local diagnostic = {
      npc = npcName, retries = retries, time = os.time(),
      mode = storage.extras and storage.extras.buySuppliesV15 == true and "v15" or "legacy",
      stage = "starting", shopIds = {}, supplies = {},
      watcherConnected = tradeWatcherConnected,
      watcherError = tradeWatcherError
    }
    storage.sabuezoBuySuppliesDiagnostic = diagnostic

    local pending = storage.sabuezoBuySuppliesPending
    if type(pending) == "table" then
      -- Inventory confirmation belongs to the item/request, not the NPC at
      -- the current waypoint. Reconcile it before blocking another shop.
      local differentShop = tostring(pending.npc):lower() ~= npcName:lower()
      if differentShop and pending.observedCurrent == nil and pending.observedVisible == nil then
        -- Older saved requests have no observation state. Give the backpack
        -- manager time to reopen supplies after login before declaring failure.
        pending.inventoryRecoveryUntil = os.time() + RECOVERED_INVENTORY_GRACE_SECONDS
      end
      local current, source, visible = getCounterInfo(pending.itemId)
      local visibleBefore = tonumber(pending.visibleBefore)
      if not visibleBefore and type(previousDiagnostic) == "table" and
          previousDiagnostic.stage == "modal_batch_unconfirmed" and
          type(previousDiagnostic.pending) == "table" and
          tonumber(previousDiagnostic.pending.itemId) == tonumber(pending.itemId) and
          tonumber(previousDiagnostic.pending.before) == tonumber(pending.before) and
          tonumber(previousDiagnostic.pending.amount) == tonumber(pending.amount) then
        visibleBefore = tonumber(previousDiagnostic.pending.visible)
      end
      diagnostic.pending = {
        npc = pending.npc, differentShop = differentShop,
        itemId = pending.itemId, before = pending.before,
        amount = pending.amount, current = current,
        source = source, visible = visible, visibleBefore = visibleBefore
      }
      local before = tonumber(pending.before) or 0
      local amount = tonumber(pending.amount) or 0
      local expected = before + amount
      local visibleConfirmed = visibleBefore and visibleBefore >= 0 and
        visible >= visibleBefore + (tonumber(pending.amount) or 0)
      if current >= expected or visibleConfirmed then
        if visibleConfirmed and current < expected and
            vBot.ItemCounter and vBot.ItemCounter.set then
          vBot.ItemCounter.set(pending.itemId, expected, "buy")
        end
        storage.sabuezoBuySuppliesPending = nil
        diagnostic.stage = "modal_batch_confirmed"
        print("CaveBot[BuySupplies]: confirmed " .. pending.amount .. "x " .. pending.itemId)
        CaveBot.delay(350)
        return "retry"
      end
      local timestamp = os.time()
      pending.firstObservedAt = tonumber(pending.firstObservedAt) or timestamp
      if pending.observedCurrent ~= current or pending.observedVisible ~= visible then
        pending.observedCurrent, pending.observedVisible = current, visible
        pending.lastInventoryChangeAt = timestamp
      end
      local elapsed = timestamp - (tonumber(pending.requestedAt) or timestamp)
      local settledFor = timestamp - (tonumber(pending.lastInventoryChangeAt) or timestamp)
      local received = math.max(0, current - before)
      diagnostic.pending.received = received
      diagnostic.pending.settledFor = settledFor
      diagnostic.pending.inventoryViewChanged = pending.inventoryView ~= nil and
        pending.inventoryView ~= inventoryViewSignature()
      -- Wait the entire confirmation interval before accepting a smaller
      -- batch: ordinary streamed container updates must not trigger a second
      -- purchase. Require matching real counts, a stable view and a quiet tail.
      local partialConfirmed = received > 0 and received < amount and
        visibleBefore == before and current == visible and
        not diagnostic.pending.inventoryViewChanged
      if elapsed >= MODAL_CONFIRM_TIMEOUT and partialConfirmed and
          settledFor >= PARTIAL_SETTLE_SECONDS then
        storage.sabuezoBuySuppliesPending = nil
        diagnostic.stage = "modal_batch_partially_confirmed"
        diagnostic.receivedAmount = received
        tradeRequest.partialBatches = tradeRequest.partialBatches or {}
        local key = tostring(pending.itemId)
        tradeRequest.partialBatches[key] = (tradeRequest.partialBatches[key] or 0) + 1
        print("CaveBot[BuySupplies]: received " .. received .. " of " .. amount ..
          "x " .. pending.itemId .. "; recounting the remaining supplies")
        if tradeRequest.partialBatches[key] >= MAX_PARTIAL_BATCHES then
          diagnostic.stage = "repeated_partial_batches"
          warn("CaveBot[BuySupplies]: varias compras parciales; revisa cap, oro y espacio en BP")
          CaveBot.setOff()
          return false
        end
        CaveBot.delay(350)
        return "retry"
      end
      if elapsed >= MODAL_CONFIRM_TIMEOUT and
          timestamp >= (tonumber(pending.inventoryRecoveryUntil) or 0) and
          (not partialConfirmed or settledFor >= PARTIAL_SETTLE_SECONDS or
            timestamp - pending.firstObservedAt >=
              MODAL_CONFIRM_TIMEOUT + PARTIAL_SETTLE_SECONDS * 2) then
        if differentShop then
          diagnostic.stage = "different_shop_purchase_pending"
          warn("CaveBot[BuySupplies]: compra de " .. tostring(pending.npc) ..
            " sin confirmar; abre la BP de ese supply")
        else
          diagnostic.stage = "modal_batch_unconfirmed"
          warn("CaveBot[BuySupplies]: inventory did not confirm the shop purchase; stopping to avoid duplicates")
        end
        CaveBot.setOff()
        return false
      end
      diagnostic.stage = "waiting_for_batch_confirmation"
      CaveBot.delay(500)
      return "retry"
    end

    local npc = getCreatureByName(npcName)
    if not npc then 
      diagnostic.stage = "npc_missing"
      print("CaveBot[BuySupplies]: NPC not found")
      return false 
    end
    
    if waitVal then
      delay(waitVal)
    end

    if retries > 200 then
      diagnostic.stage = "too_many_retries"
      print("CaveBot[BuySupplies]: Too many tries, can't buy")
      if next(tradeRequest.partialBatches or {}) then
        warn("CaveBot[BuySupplies]: compra incompleta; revisa cap, oro y espacio en BP")
        CaveBot.setOff()
      end
      return false
    end

    if not CaveBot.ReachNPC(npcName) then
      diagnostic.stage = "approaching_npc"
      return "retry"
    end

    local npcItems, modal, modalName, modalIdentity, tradeSource
    if diagnostic.mode == "v15" then
      if not (modules and modules.game_npcmodal) then
        diagnostic.stage = "v15_shop_unavailable"
        warn("CaveBot[BuySupplies]: Buy Supplies v15 is enabled, but this client has no v15 shop")
        CaveBot.setOff()
        return false
      end
      local modalStatus
      npcItems, modalStatus, modalName, modal = getModalBuyItems(npcName)
      if tradeRequest.attempts == 0 then
        -- Even a matching title can belong to a previous visit. Always request
        -- the target's shop once; retries and pending purchases reuse that list.
        npcItems = nil
        diagnostic.stage = "waiting_for_target_shop"
      elseif npcItems then
        local buyClick = modules.game_npcmodal.onNpcTradeBuyClick
        local ok, refreshError = pcall(function()
          if type(buyClick) ~= "function" then error("Buy mode unavailable") end
          buyClick()
        end)
        if not ok then
          diagnostic.stage = "shop_refresh_failed"
          diagnostic.error = tostring(refreshError)
          CaveBot.setOff()
          return false
        end
        npcItems, modalStatus, modalName, modal = getModalBuyItems(npcName)
        if npcItems then
          modalIdentity = { signature = shopSignature(npcItems) }
          diagnostic.shownNpc = modalName
          diagnostic.requestedTargetTrade = true
          diagnostic.labelMismatchAccepted = modalStatus == "label_mismatch"
          diagnostic.configuredMatches = 0
          local configured = Supplies.getItemsData()
          for _, entry in ipairs(npcItems) do
            if configured[entry.id] or configured[tostring(entry.id)] then
              diagnostic.configuredMatches = diagnostic.configuredMatches + 1
            end
          end
        end
      end
      tradeSource = "modal"
    else
      npcItems = getOpenBuyItems()
      tradeSource = "legacy"
    end
    if tradeSource == "modal" and tradeRequest.categoryWaiting then
      local changed = npcItems and #npcItems > 0 and
        shopSignature(npcItems) ~= tradeRequest.categoryBaseline
      if changed then
        tradeRequest.categoryWaiting = false
        diagnostic.categoryOpened = tradeRequest.activeFilter
      else
        diagnostic.category = tradeRequest.activeFilter
        if os.time() - (tradeRequest.categoryRequestedAt or 0) >= CATEGORY_SHOP_TIMEOUT then
          diagnostic.stage = "category_shop_not_detected"
          warn("CaveBot[BuySupplies]: Xodet did not open the requested " ..
            tostring(tradeRequest.activeFilter) .. " shop")
          CaveBot.setOff()
          return false
        end
        diagnostic.stage = "waiting_for_category_shop"
        CaveBot.delay(500)
        return "retry"
      end
    end
    if not npcItems then
      if diagnostic.stage ~= "waiting_for_target_shop" then
        diagnostic.stage = "waiting_for_trade"
      end
      diagnostic.tradeAttempts = tradeRequest.attempts
      if tradeRequest.attempts >= 2 and retries - tradeRequest.lastRetry >= 5 then
        diagnostic.stage = "trade_not_detected"
        warn("CaveBot[BuySupplies]: a fresh NPC shop was not detected; stopping repeated trade messages")
        CaveBot.setOff()
        return false
      end
      if tradeRequest.attempts == 0 or retries - tradeRequest.lastRetry >= 5 then
        openNpcTrade(tradeWord)
        tradeRequest.lastRetry = retries
        tradeRequest.attempts = tradeRequest.attempts + 1
      end
      CaveBot.delay(math.max(500, (tonumber(storage.extras.talkDelay) or 1000) * 2))
      return "retry"
    end

    if #npcItems == 0 then
      diagnostic.stage = "shop_items_unreadable"
      warn("CaveBot[BuySupplies]: trade opened, but no buy items were readable")
      return false
    end

    diagnostic.stage = "checking_shop"
    diagnostic.tradeSource = tradeSource
    diagnostic.shopTotal = #npcItems
    for i,v in pairs(npcItems) do
      table.insert(possibleItems, v.id)
      if #diagnostic.shopIds < 80 then
        diagnostic.shopIds[#diagnostic.shopIds + 1] = v.id
      end
    end

    local matches = 0
    for id, values in pairs(Supplies.getItemsData()) do
      id = tonumber(id)
      if id then
        local available = not not table.find(possibleItems, id)
        local max = tonumber(values.max) or 0
        local current, source, visible = getCounterInfo(id)
        -- Use the counter result and retain its source for diagnostics.
        current = tonumber(current) or 0
        diagnostic.supplies[tostring(id)] = {
          max = max, current = current, source = source,
          visible = visible, available = available
        }
        if available then
          matches = matches + 1
          if vBot.ItemCounter and vBot.ItemCounter.registerItemId then
            if vBot.ItemCounter.registerSupplyItem then
              vBot.ItemCounter.registerSupplyItem(id, values)
            else
              vBot.ItemCounter.registerItemId(id)
            end
          end

          local toBuy = max - current

          if toBuy > 0 then
            if tradeSource == "modal" then
              local matchedEntry
              for _, entry in ipairs(npcItems) do
                if entry.id == id then matchedEntry = entry break end
              end
              return requestModalPurchase(matchedEntry, modal, npcName, current,
                toBuy, modalIdentity, diagnostic)
            end
            toBuy = math.min(100, toBuy)

            local matchedItem = nil
            for _, entry in pairs(npcItems) do
              if entry.id == id then matchedItem = entry.item break end
            end
            local ok, buyError = pcall(function()
              if matchedItem then
                g_game.buyItem(matchedItem, toBuy, false, false)
              else
                NPC.buy(id, toBuy)
              end
            end)
            if not ok then
              diagnostic.stage = "buy_request_failed"
              diagnostic.itemId = id
              warn("CaveBot[BuySupplies]: buy request failed for " .. id .. ": " .. tostring(buyError))
              return false
            end
            diagnostic.stage = "buy_requested"
            diagnostic.itemId = id
            diagnostic.amount = toBuy
            if vBot.ItemCounter and vBot.ItemCounter.set then
              vBot.ItemCounter.set(id, current + toBuy, "buy")
            end
            print("CaveBot[BuySupplies]: requested " .. toBuy .. "x " .. id)
            CaveBot.delay(math.max(500, tonumber(storage.extras.talkDelay) or 1000))
            return "retry"
          end
        end
      end
    end

    diagnostic.matches = matches
    if tradeSource == "modal" and modal and npcName:lower() == "xodet" then
      -- First evaluate a category after its rows have refreshed on a retry.
      if tradeRequest.activeFilter then
        tradeRequest.filtersTried[tradeRequest.activeFilter] = true
      end
      local neededCategories = {}
      for key, info in pairs(diagnostic.supplies) do
        if info.current < info.max and not info.available then
          local category = supplyShopCategory(tonumber(key))
          if category and not tradeRequest.filtersTried[category] then
            neededCategories[category] = true
          end
        end
      end
      local nextFilter = neededCategories.potions and "potions" or
        (neededCategories.runes and "runes" or nil)
      if nextFilter then
        local applied, filterError = requestCategoryShop(modal, npcItems, nextFilter)
        diagnostic.filter = nextFilter
        diagnostic.filterError = filterError
        if applied then
          diagnostic.stage = "requesting_shop_category"
          CaveBot.delay(math.max(1000, (tonumber(storage.extras.talkDelay) or 1000) * 3))
          return "retry"
        end
        diagnostic.stage = "shop_category_request_failed"
        warn("CaveBot[BuySupplies]: could not request Xodet's " ..
          nextFilter .. " shop: " .. tostring(filterError))
        CaveBot.setOff()
        return false
      end
    end
    if tradeSource == "modal" then
      storage.sabuezoBuySuppliesLastShop = {
        npc = npcName, shownName = modalName,
        signature = shopSignature(npcItems), time = os.time()
      }
    end
    local missing = 0
    for _, info in pairs(diagnostic.supplies) do
      if info.current < info.max and not info.available then
        missing = missing + 1
      end
    end
    if tradeSource == "modal" and missing > 0 then
      diagnostic.stage = "configured_items_unavailable_here"
      diagnostic.unavailableCount = missing
      print("CaveBot[BuySupplies]: " .. missing .. " configured supply items were not found in " .. npcName .. "'s shop")
    elseif matches == 0 then
      diagnostic.stage = "no_matching_ids"
      warn("CaveBot[BuySupplies]: none of the configured supply IDs are sold by " .. npcName)
    else
      diagnostic.stage = "configured_items_at_max"
      print("CaveBot[BuySupplies]: configured shop items are already at max")
    end
    if type(CaveBot.FinishNpcConversation) == "function" then
      local result = CaveBot.FinishNpcConversation(0)
      for key, resultValue in pairs(result or {}) do diagnostic[key] = resultValue end
      clearNpcTrade()
      CaveBot.delay(math.max(500, (tonumber(storage.extras.talkDelay) or 100) * 2))
      return true
    end
    local goodbyeOk, goodbyeError = pcall(function() NPC.say("bye") end)
    diagnostic.goodbyeSent = goodbyeOk
    if not goodbyeOk then
      diagnostic.goodbyeError = tostring(goodbyeError)
      warn("CaveBot[BuySupplies]: could not say bye to " .. npcName .. ": " .. tostring(goodbyeError))
    end
    if NPC and type(NPC.closeTrade) == "function" then
      local closeOk, closeError = pcall(NPC.closeTrade)
      diagnostic.tradeClosed = closeOk
      if not closeOk then diagnostic.tradeCloseError = tostring(closeError) end
    end
    -- NPC.closeTrade targets the classic shop. MythicOTC v15 keeps its
    -- conversation and Buy list in a separate modal, so hide that window too.
    if tradeSource == "modal" and modal and
        safeWidgetValue(modal, "isVisible") == true then
      local closeOk, closeError = pcall(function() modal:hide() end)
      diagnostic.modalClosed = closeOk and
        safeWidgetValue(modal, "isVisible") ~= true
      if not closeOk then diagnostic.modalCloseError = tostring(closeError) end
      if not diagnostic.modalClosed then
        warn("CaveBot[BuySupplies]: could not close the v15 shop window")
      end
    end
    clearNpcTrade()
    CaveBot.delay(math.max(500, (tonumber(storage.extras.talkDelay) or 100) * 2))
    return true
 end)

 CaveBot.Editor.registerAction("buysupplies", "buy supplies", {
  value="NPC name",
  title="Buy Supplies",
  description="NPC name, word(optional), delay(in ms, optional)",
 })
end
