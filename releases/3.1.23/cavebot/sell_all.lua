CaveBot.Extensions.SellAll = {}

local sellAllCap = 0
local nativeSale
local SELL_CONFIRM_TIMEOUT = 2500
local SELL_PARTIAL_SETTLE_MS = 500
local SELL_MODE_TIMEOUT = 4500
local SELL_LIST_SETTLE_MS = 250
local SELL_ROW_TIMEOUT = 2000
-- The server refuses a trade request that arrives too soon after the previous
-- one, so requests go one at a time with a pause that grows after a refusal.
local SELL_REQUEST_GAP_MS = 600
local SELL_DELAYED_GAP_MS = 1100
local SELL_MAX_GAP_MS = 2000
local STALLED_RETRY_MS = 10000
local STOCK_REFRESH_TIMEOUT = 1800
local NPC_REPLY, NPC_START_REPLY = 10, 51

-- The value of the action is "NPC, yes, id, id": the NPC's name, "yes" to sell with a delay, then the IDs of
-- the items that must NOT be sold (exceptions). The editor panel reads and writes it through these two.
local function trim(text)
  return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Returns {npc, delayed, ids, extra}. `extra` keeps any other word, so nothing typed by hand is lost.
CaveBot.Extensions.SellAll.decode = function(value)
  local result = {npc = "", delayed = false, ids = {}, extra = {}}
  local seen, first = {}, true
  for part in (tostring(value or "") .. ","):gmatch("([^,]*),") do
    part = trim(part)
    if part ~= "" then
      if first then
        first = false
        -- "NPC" is only the placeholder of a new action, not a name.
        result.npc = part == "NPC" and "" or part
      elseif part:lower() == "yes" then
        result.delayed = true
      else
        local id = tonumber(part)
        if id and id > 100 and id == math.floor(id) then
          if not seen[id] then seen[id] = true; result.ids[#result.ids + 1] = id end
        else
          result.extra[#result.extra + 1] = part
        end
      end
    end
  end
  return result
end

CaveBot.Extensions.SellAll.encode = function(config)
  local parts = {trim(config.npc)}
  if config.delayed then parts[#parts + 1] = "yes" end
  for _, id in ipairs(config.ids or {}) do parts[#parts + 1] = tostring(id) end
  for _, word in ipairs(config.extra or {}) do parts[#parts + 1] = tostring(word) end
  return table.concat(parts, ", ")
end

local function nativeTradeModal()
  local root = g_ui and g_ui.getRootWidget and g_ui.getRootWidget()
  return root and root.recursiveGetChildById and root:recursiveGetChildById("npcModalWindow")
end

local function finishNativeSale(message, success)
  local revision = nativeSale and nativeSale.conversation
  nativeSale = nil
  if revision and CaveBot.IsNpcConversationCurrent(revision) then CaveBot.FinishNpcConversation(0, revision) end
  print("CaveBot[SellAll]: " .. message)
  return success
end

local function waitAtSeller(state, time, message, wait)
  if not state.nextNoticeAt or time >= state.nextNoticeAt then
    state.nextNoticeAt = time + 5000
    print("CaveBot[SellAll]: " .. message .. ". Espero en el waypoint de venta.")
  end
  delay(wait)
  return "retry"
end

-- Every sale request (bag or item) waits for the pause since the previous one.
local function noteRequest(state, time)
  state.nextSaleAt = time + (state.delayed and math.max(SELL_DELAYED_GAP_MS, state.gap) or state.gap)
end

local function slowDown(state)
  state.gap = math.min(SELL_MAX_GAP_MS, state.gap * 2)
end

-- Last server text received after a request, for the console line of a refused sale.
local function replySince(state, since)
  if since and state.lastReplyAt and state.lastReplyAt >= since then return state.lastReply end
end

local function reopenNativeShop(state, time, reason)
  if state.conversation and CaveBot.IsNpcConversationCurrent(state.conversation) then
    CaveBot.CancelNpcConversation()
    CaveBot.CloseNpcWindows()
  end
  for id, pending in pairs(state.pending) do state.uncertain[id] = pending end
  state.pouchUncertain = state.pouchPending or state.pouchUncertain
  state.shop, state.conversation, state.baseline, state.openDeadline = nil, nil, nil, nil
  state.tradeAfter, state.shopSpeaker, state.refresh = nil, nil, nil
  state.modeDeadline, state.modeRetryAt, state.sellReadyAt, state.rowsDeadline = nil, nil, nil, nil
  state.pouchPending, state.emptySince = nil, nil
  state.pending, state.opens, state.nextSaleAt = {}, 0, nil
  -- Recount in a fresh shop before repeating an unconfirmed request.
  state.retryAt = time + 1000
  return waitAtSeller(state, time, reason .. "; vuelvo a consultar al vendedor", 1000)
end

local function inventoryCount(id)
  if not player or type(player.getInventoryCount) ~= "function" then return nil end
  local ok, count = pcall(player.getInventoryCount, player, id, 0)
  if ok and type(count) == "number" and count >= 0 and count < math.huge then return math.floor(count) end
end

local function equippedCounts()
  local counts = {}
  if player and player.getInventoryItem then
    for slot = 1, LAST_INVENTORY or 10 do
      local item = player:getInventoryItem(slot)
      if item then
        local id = item:getId()
        counts[id] = (counts[id] or 0) + math.max(1, tonumber(item:getCount()) or 1)
      end
    end
  end
  return counts
end

local function saleSettled(pending, sold, time)
  if sold == pending.quantity then return true end
  -- Some requests produce several inventory updates. Let them settle before
  -- sending another request for the same item.
  if sold ~= pending.confirmed then
    pending.confirmed = sold
    pending.settleAt = time + SELL_PARTIAL_SETTLE_MS
  end
  return time >= (sold > 0 and pending.settleAt or pending.deadline)
end

local function pouchProgress(pending, goods)
  local sold, remaining = 0, 0
  for id, before in pairs(pending.items) do
    local left = math.min(before, tonumber(goods[id]) or 0)
    sold = sold + before - left
    remaining = remaining + left
  end
  return sold, remaining
end

local function sellLootPouch(state, modalModule, time)
  if state.pouchUncertain or state.pouchStalled then return false end
  local goods = modalModule and modalModule.lootPouchItems
  local ignored = modalModule and modalModule.sellAllIgnoredItems
  if type(goods) ~= "table" or type(ignored) ~= "table" or type(modalModule.sendSellAll) ~= "function" then
    return false
  end
  local pending = state.pouchPending
  if pending then
    local sold, remaining = pouchProgress(pending, goods)
    if not saleSettled(pending, sold, time) then return true end
    state.sold = state.sold + sold
    state.pouchPending = nil
    if remaining > 0 then
      if sold > 0 then return true end
      state.pouchUncertain = pending
      slowDown(state)
    else
      print("CaveBot[SellAll]: venta confirmada de la bolsa de loot (" .. sold .. " unidades)")
    end
    return false
  end

  local items, total = {}, 0
  for id, count in pairs(goods) do
    local amount = tonumber(count)
    if amount and amount > 0 and not ignored[id] and not state.keep[id] then
      items[id] = amount
      total = total + amount
    end
  end
  if total == 0 then return false end
  if state.nextSaleAt and time < state.nextSaleAt then return true end

  -- The native bulk action reads its exclusion table synchronously. Restore
  -- the user's own entries before any delayed window cleanup runs.
  local added = {}
  for id in pairs(state.keep) do
    if not ignored[id] then
      added[#added + 1] = {id = id, previous = ignored[id]}
      ignored[id] = true
    end
  end
  local ok, result = pcall(modalModule.sendSellAll)
  for _, entry in ipairs(added) do ignored[entry.id] = entry.previous end
  local request = {items = items, quantity = total, confirmed = 0, deadline = time + SELL_CONFIRM_TIMEOUT}
  noteRequest(state, time)
  if not ok or result == false then
    state.pouchUncertain = request
    return false
  end
  state.pouchPending = request
  print("CaveBot[SellAll]: solicitada venta de la bolsa de loot")
  return true
end

local function recordSale(state, id, pending, sold)
  state.sold = state.sold + sold
  state.remaining[id] = pending.before - sold
  state.refusals[id] = nil
  if sold < pending.quantity then state.batchSize[id] = sold end
end

local function reconcileStock(state, trade, modalModule)
  state.remaining = {}
  for id, pending in pairs(state.uncertain) do
    local count = trade.goods[id] or 0
    local sold = math.min(pending.quantity, math.max(0, pending.before - count))
    if sold > 0 then
      recordSale(state, id, pending, sold)
    elseif count > 0 then
      local failures = (state.refusals[id] or 0) + 1
      state.refusals[id] = failures
      local reply = pending.reply and (". Servidor: " .. pending.reply) or ""
      if pending.quantity <= 1 and failures >= 3 then
        state.stalled[id] = count
      elseif pending.quantity > 1 and failures >= 2 then
        -- Smaller batches only after a refusal that a longer pause did not fix.
        state.batchSize[id] = failures == 2 and math.max(1, math.min(100, math.floor(pending.quantity / 2))) or 1
        print("CaveBot[SellAll]: item " .. id .. " sigue sin venderse; reintento de " ..
          state.batchSize[id] .. " unidades" .. reply)
      else
        print("CaveBot[SellAll]: item " .. id .. " no se vendio; reintento con pausa de " ..
          state.gap .. " ms" .. reply)
      end
    end
  end
  state.uncertain = {}
  if state.pouchUncertain and modalModule and type(modalModule.lootPouchItems) == "table" then
    local sold, remaining = pouchProgress(state.pouchUncertain, modalModule.lootPouchItems)
    state.sold = state.sold + sold
    state.pouchRefusals = sold > 0 and 0 or (state.pouchRefusals or 0) + 1
    if remaining > 0 and state.pouchRefusals >= 2 then state.pouchStalled = state.pouchUncertain end
    state.pouchUncertain = nil
  end
end

local function identifySeller(state)
  local modal = nativeTradeModal()
  local nameLabel = modal and modal:isVisible() and modal:recursiveGetChildById("npcName")
  local shownName = nameLabel and trim(nameLabel:getText()) or ""
  local expected = state.npc:lower()
  local titleMatches = shownName == "" or shownName:lower() == expected
  return titleMatches or state.shopSpeaker == expected, shownName, titleMatches
end

local function refreshStock(state, trade, time)
  state.refresh = {goods = trade.goods, deadline = time + STOCK_REFRESH_TIMEOUT}
  state.shopSpeaker, state.tradeAfter = nil, time
  if not NPC or type(NPC.say) ~= "function" then return reopenNativeShop(state, time, "actualizo el inventario") end
  local ok, sent = pcall(NPC.say, "trade")
  if not ok or sent == false then return reopenNativeShop(state, time, "actualizo el inventario") end
  delay(100)
  return "retry"
end

local function waitForSellMode(state, modalModule, time)
  local modal = nativeTradeModal()
  if not modal or not modal:isVisible() then return nil, "tienda oculta" end
  local sellMode = modal:recursiveGetChildById("sellButton")
  local buyMode = modal:recursiveGetChildById("buyButton")
  if not sellMode or not buyMode then return nil, "faltan las pestanas Buy y Sell" end
  if not sellMode:isOn() or buyMode:isOn() then
    if not modalModule or type(modalModule.onNpcTradeSellClick) ~= "function" then return nil, "pestana Sell no disponible" end
    if not state.modeRetryAt or time >= state.modeRetryAt then
      state.modeRetryAt = time + 400
      local ok, err = pcall(modalModule.onNpcTradeSellClick)
      if not ok then return nil, tostring(err) end
      state.sellReadyAt = time + SELL_LIST_SETTLE_MS
    end
    return nil, "esperando que se active Sell"
  end
  if not state.sellReadyAt then state.sellReadyAt = time + SELL_LIST_SETTLE_MS end
  if time < state.sellReadyAt then return nil, "cargando la lista Sell" end
  return modal
end

local function selectSellRow(modal, id, wanted)
  local function child(name) return modal:recursiveGetChildById(name) end
  local preview, slider, confirm = child("item2"), child("countScrollBar"), child("BuySellButton")
  if not preview or not slider or not confirm then return nil, "controles de venta incompletos", true end
  local panel = child("npcTradeItemsPanel")
  if not panel or not panel:isVisible() then return nil, "lista de venta oculta", true end
  for _, row in ipairs(panel:getChildren() or {}) do
    local icon = row:recursiveGetChildById("itemIcon")
    local entry = row.entry
    local item = entry and entry.item or icon and icon:getItem()
    if item and item:getId() == id and type(row.onMousePress) == "function" then
      row.onMousePress(row, row:getPosition(), MouseLeftButton or 1)
      if tonumber(preview:getItemId()) ~= id or not confirm:isEnabled() then return nil, "el item no se puede vender" end
      local amount = math.min(wanted, math.floor(tonumber(slider:getMaximum()) or 0))
      if amount > 0 then return item, amount end
      return nil, "cantidad no vendible"
    end
  end
  return nil, "no aparece en la lista Sell", true
end

local function sellNative(value, retries)
  local trade, listening
  if CaveBot.getNpcTrade then trade, listening = CaveBot.getNpcTrade() end
  if not listening or not g_game or type(g_game.sellItem) ~= "function" then
    return finishNativeSale("no estan disponibles los eventos de venta de Valkaris", false)
  end
  if retries == 0 or not nativeSale or nativeSale.value ~= value then
    local config = CaveBot.Extensions.SellAll.decode(value)
    local keep = {}
    for _, id in ipairs(config.ids) do keep[id] = true end
    for _, item in ipairs(storage.cavebotSell or {}) do
      local id = tonumber(type(item) == "table" and item.id or item)
      if id then keep[id] = true end
    end
    nativeSale = {value = value, npc = config.npc, keep = keep, delayed = config.delayed,
      opens = 0, sold = 0, pending = {}, uncertain = {}, remaining = {}, stalled = {}, refusals = {}, batchSize = {},
      gap = SELL_REQUEST_GAP_MS}
  end
  local state = nativeSale
  local time = now or g_clock.millis()
  if state.npc == "" then return finishNativeSale("falta el nombre del vendedor", false) end
  if state.retryAt and time < state.retryAt then delay(100); return "retry" end
  local npc = getCreatureByName(state.npc)
  if not npc or not npc:isNpc() then
    if state.conversation then return reopenNativeShop(state, time, "se perdio al vendedor") end
    return waitAtSeller(state, time, "no veo a " .. state.npc, 500)
  end
  local origin, position = player:getPosition(), npc:getPosition()
  if not origin or not position or position.z ~= origin.z then
    if state.conversation then return reopenNativeShop(state, time, "se perdio el alcance del vendedor") end
    return waitAtSeller(state, time, "el vendedor esta fuera de alcance", 500)
  end
  if math.max(math.abs(position.x-origin.x), math.abs(position.y-origin.y)) > 3 then
    if state.conversation then return reopenNativeShop(state, time, "se perdio el alcance del vendedor") end
    CaveBot.GoTo(position)
    delay(200)
    return "retry"
  end

  if state.conversation and not CaveBot.IsNpcConversationCurrent(state.conversation) then
    return reopenNativeShop(state, time, "la conversacion de venta cambio")
  end
  local modalModule = modules and modules.game_npcmodal
  if state.refresh then
    local fresh = trade.open and trade.goodsReceived and trade.goods ~= state.refresh.goods
    if fresh and (trade.revision == state.shop or identifySeller(state)) then
      state.shop, state.refresh, state.emptySince = trade.revision, nil, nil
      reconcileStock(state, trade, modalModule)
    elseif time >= state.refresh.deadline then
      return reopenNativeShop(state, time, "la tienda no actualizo el inventario")
    else
      delay(100)
      return "retry"
    end
  end
  if state.shop and (not trade.open or trade.revision ~= state.shop) then
    return reopenNativeShop(state, time, "la tienda se cerro o cambio durante la venta")
  end
  if not state.shop then
    local sellerMatches, shownName, titleMatches = identifySeller(state)
    local freshList = trade.open and state.baseline and (trade.revision or 0) > state.baseline
    -- Next Gen can keep the previous NPC's title across a new trade. A
    -- private reply from this seller and new shop data identify the visit.
    if freshList and trade.goodsReceived and sellerMatches then
      state.shop = trade.revision
      reconcileStock(state, trade, modalModule)
      if not titleMatches then
        print("CaveBot[SellAll]: tienda confirmada por " .. state.npc .. " (el cliente conserva el titulo " .. shownName .. ")")
      end
    elseif not state.openDeadline or time >= state.openDeadline then
      if state.opens >= 2 then
        local reason = not freshList and "falta una lista nueva de la tienda" or
          not trade.goodsReceived and "falta el inventario de la tienda" or
          "la ventana muestra " .. shownName .. " y falta la respuesta de " .. state.npc
        return reopenNativeShop(state, time, reason)
      end
      CaveBot.CloseNpcWindows()
      state.baseline = trade.revision or 0
      state.shopSpeaker = nil
      local duration, revision = CaveBot.OpenNpcTrade()
      state.conversation = revision
      state.opens = state.opens + 1
      duration = tonumber(duration) or 2000
      state.tradeAfter = time + duration / 2 -- OpenNpcTrade schedules "hi" and then "trade".
      state.openDeadline = time + duration + 4500
    end
    if not state.shop then delay(100); return "retry" end
  end

  local modal, modeError = waitForSellMode(state, modalModule, time)
  if not modal then
    state.modeDeadline = state.modeDeadline or time + SELL_MODE_TIMEOUT
    if time >= state.modeDeadline then return reopenNativeShop(state, time, "no se pudo preparar Sell (" .. modeError .. ")") end
    delay(100)
    return "retry"
  end
  state.modeDeadline = nil
  if state.pouchStalled and modalModule and type(modalModule.lootPouchItems) == "table" and
    pouchProgress(state.pouchStalled, modalModule.lootPouchItems) > 0 then
    state.pouchStalled, state.pouchRefusals = nil, nil
  end
  if sellLootPouch(state, modalModule, time) then state.emptySince = nil; delay(100); return "retry" end

  local view = CaveBot.getNpcInventoryViewSignature and CaveBot.getNpcInventoryViewSignature()
  local pendingCount = 0
  for id, pending in pairs(state.pending) do
    local current = pending.nativeBefore and view == pending.view and inventoryCount(id)
    local nativeDelta = current and pending.nativeBefore - current or 0
    local sold = math.min(pending.quantity, math.max(0, pending.before - (trade.goods[id] or 0), nativeDelta))
    if saleSettled(pending, sold, time) then
      state.pending[id] = nil
      if sold > 0 then recordSale(state, id, pending, sold)
      else
        pending.reply = replySince(state, pending.sentAt)
        state.uncertain[id] = pending
        slowDown(state)
      end
    else
      pendingCount = pendingCount + 1
    end
  end
  if pendingCount > 0 or state.nextSaleAt and time < state.nextSaleAt then delay(100); return "retry" end

  local equipped = equippedCounts()
  local waitingForRows, unsold = false, {}
  for id in pairs(trade.sellItems or {}) do
    local shopCount = trade.goods[id] or 0
    local count = math.min(shopCount, state.remaining[id] or shopCount)
    local equippedCount = equipped[id] or 0
    if state.stalled[id] and state.stalled[id] ~= count then
      state.stalled[id], state.refusals[id], state.batchSize[id] = nil, nil, nil
    end
    local amount = math.min(state.batchSize[id] or 65535, math.floor(count - equippedCount))
    if amount > 0 and not state.keep[id] and not state.pending[id] and not state.uncertain[id] then
      if state.stalled[id] then
        unsold[#unsold + 1] = id .. " x" .. (count - equippedCount)
      else
        local ok, item, quantity, loading = pcall(selectSellRow, modal, id, amount)
        if ok and item then
          local nativeBefore = view and inventoryCount(id)
          if nativeBefore ~= count and nativeBefore ~= count + equippedCount then nativeBefore = nil end
          local sent, result = pcall(g_game.sellItem, item, quantity, true)
          if sent and result ~= false then
            state.pending[id] = {before = count, quantity = quantity, confirmed = 0, sentAt = time,
              nativeBefore = nativeBefore, view = view, deadline = time + SELL_CONFIRM_TIMEOUT}
            state.rowsDeadline = nil
            state.emptySince = nil
            noteRequest(state, time)
            delay(100)
            return "retry"
          end
        end
        if loading then state.rowsDeadline = state.rowsDeadline or time + SELL_ROW_TIMEOUT end
        if loading and time < state.rowsDeadline then
          waitingForRows = true
        else
          state.uncertain[id] = {before = count, quantity = 0}
        end
      end
    end
  end
  if waitingForRows or pendingCount > 0 then state.emptySince = nil; delay(100); return "retry" end
  for _ in pairs(state.uncertain) do return refreshStock(state, trade, time) end
  if state.pouchUncertain then return refreshStock(state, trade, time) end
  if state.pouchStalled then unsold[#unsold + 1] = "bolsa de loot" end
  if #unsold > 0 then
    table.sort(unsold)
    -- Keep the waypoint, but offer the refused items again with the longest pause.
    state.stalledSince = state.stalledSince or time
    local wait = STALLED_RETRY_MS - (time - state.stalledSince)
    if wait <= 0 then
      state.stalledSince, state.pouchStalled, state.pouchRefusals = nil, nil, nil
      state.stalled, state.refusals, state.batchSize = {}, {}, {}
      state.gap = SELL_MAX_GAP_MS
      print("CaveBot[SellAll]: vuelvo a ofrecer " .. table.concat(unsold, ", "))
      delay(100)
      return "retry"
    end
    return waitAtSeller(state, time, "vendidas " .. state.sold ..
      " unidades. El vendedor deja pendientes " .. table.concat(unsold, ", ") ..
      "; reintento en " .. math.ceil(wait / 1000) .. " s", 500)
  end
  state.emptySince = state.emptySince or time
  if time - state.emptySince < 100 then delay(100); return "retry" end
  return finishNativeSale(state.sold > 0 and ("venta confirmada de " .. state.sold .. " unidades") or
    "no hay objetos vendibles fuera de las excepciones y el equipo", true)
end

CaveBot.Extensions.SellAll.setup = function()
  if type(onTalk) == "function" then
    onTalk(function(name, _, mode)
      local state = nativeSale
      if (mode ~= NPC_REPLY and mode ~= NPC_START_REPLY) or type(name) ~= "string" or
          not state or state.shop and not state.refresh or not state.tradeAfter or not state.conversation or
          not CaveBot.IsNpcConversationCurrent(state.conversation) then return end
      -- The executor updates now on its tick, so a fast reply can see the previous tick.
      if (now or g_clock.millis()) + 100 >= state.tradeAfter then state.shopSpeaker = trim(name):lower() end
    end)
  end
  if type(onTextMessage) == "function" then
    -- Keeps what the server answers during the visit (e.g. a refused or too fast request).
    onTextMessage(function(_, text)
      local state = nativeSale
      if not state or not state.shop or type(text) ~= "string" then return end
      text = trim(text):gsub("%s+", " ")
      if text ~= "" then state.lastReply, state.lastReplyAt = text:sub(1, 120), now or g_clock.millis() end
    end)
  end
  CaveBot.registerAction("SellAll", "#C300FF", function(value, retries)
    if (modules and modules.game_npcmodal) or nativeTradeModal() then return sellNative(value, retries) end
    local val = string.split(value, ",")
    local wait

    -- table formatting
    for i, v in ipairs(val) do
      v = v:trim()
      v = tonumber(v) or v
      val[i] = v
    end

    if table.find(val, "yes", true) then
      wait = true
    end

    local npcName = val[1]
    local npc = getCreatureByName(npcName)
    if not npc then 
      print("CaveBot[SellAll]: NPC not found! skipping")
      return false 
    end

    if retries > 10 then
      print("CaveBot[SellAll]: can't sell, skipping")
      return false
    end

    if freecap() == sellAllCap then
      sellAllCap = 0 
      CaveBot.FinishNpcConversation(0)
      print("CaveBot[SellAll]: Sold everything, proceeding")
      return true
    end

    delay(800)
    if not CaveBot.ReachNPC(npcName) then
      return "retry"
    end

    if not NPC.isTrading() then
      CaveBot.OpenNpcTrade()
      delay(storage.extras.talkDelay*2)
      return "retry"
    else
      sellAllCap = freecap()
    end

    storage.cavebotSell = storage.cavebotSell or {}
    for i, item in ipairs(storage.cavebotSell) do
      local data = type(item) == 'number' and item or item.id
      if not table.find(val, data) then
        table.insert(val, data)
      end
    end

    table.dump(val)
    local kept = 0
    for _, entry in ipairs(val) do if type(entry) == "number" then kept = kept + 1 end end
    print("CaveBot[SellAll]: se conservan " .. kept .. " objetos (excepciones)")

    modules.game_npctrade.sellAll(wait, val)
    if wait then
      print("CaveBot[SellAll]: Sold All with delay")
    else
      print("CaveBot[SellAll]: Sold All without delay")
    end

    return "retry"
  end)

 CaveBot.Editor.registerAction("sellall", "sell all", {
  value="NPC",
  title="Sell All",
  description="NPC Name, 'yes' if sell with delay, exceptions: id separated by comma (the panel edits them)",
 })
end
