--[[
  HelperAPI - Unified Cross-Client API Layer
  Abstracts differences between OTC, Valkaris, Aurera, and generic OTC forks.
  All calls use pcall defensively and return nil or false gracefully.
]]

HelperAPI = HelperAPI or {}

-- Re-export ClientDetector capabilities dynamically
HelperAPI.caps = setmetatable({}, {
  __index = function(t, k)
    if ClientDetector and ClientDetector.caps then
      return ClientDetector.caps[k]
    end
    return nil
  end
})

local function safeCall(fn, ...)
  if type(fn) ~= 'function' then return false, nil end
  local ok, res = pcall(fn, ...)
  if ok then return true, res end
  return false, nil
end

local function getLocalPlayer()
  if player then return player end
  if g_game and type(g_game.getLocalPlayer) == 'function' then
    local ok, lp = pcall(g_game.getLocalPlayer)
    if ok and lp then return lp end
  end
  return nil
end

-- ============================================================================
-- Player Stats
-- ============================================================================

function HelperAPI.hp()
  local lp = getLocalPlayer()
  if lp and type(lp.getHealth) == 'function' then
    local ok, val = pcall(function() return lp:getHealth() end)
    if ok and type(val) == 'number' then return val end
  end
  if type(hp) == 'function' and hp ~= HelperAPI.hp then
    local ok, val = pcall(hp)
    if ok and type(val) == 'number' then return val end
  end
  return nil
end

function HelperAPI.maxHp()
  local lp = getLocalPlayer()
  if lp and type(lp.getMaxHealth) == 'function' then
    local ok, val = pcall(function() return lp:getMaxHealth() end)
    if ok and type(val) == 'number' then return val end
  end
  if type(maxhp) == 'function' and maxhp ~= HelperAPI.maxHp then
    local ok, val = pcall(maxhp)
    if ok and type(val) == 'number' then return val end
  end
  return nil
end

function HelperAPI.hpPercent()
  local lp = getLocalPlayer()
  if lp and type(lp.getHealthPercent) == 'function' then
    local ok, val = pcall(function() return lp:getHealthPercent() end)
    if ok and type(val) == 'number' then return val end
  end
  if type(hppercent) == 'function' and hppercent ~= HelperAPI.hpPercent then
    local ok, val = pcall(hppercent)
    if ok and type(val) == 'number' then return val end
  end
  local cur = HelperAPI.hp()
  local max = HelperAPI.maxHp()
  if cur and max and max > 0 then
    return math.floor((cur / max) * 100)
  end
  return 100
end

function HelperAPI.mp()
  local lp = getLocalPlayer()
  if lp and type(lp.getMana) == 'function' then
    local ok, val = pcall(function() return lp:getMana() end)
    if ok and type(val) == 'number' then return val end
  end
  if type(mana) == 'function' and mana ~= HelperAPI.mp then
    local ok, val = pcall(mana)
    if ok and type(val) == 'number' then return val end
  end
  return nil
end

function HelperAPI.maxMp()
  local lp = getLocalPlayer()
  if lp and type(lp.getMaxMana) == 'function' then
    local ok, val = pcall(function() return lp:getMaxMana() end)
    if ok and type(val) == 'number' then return val end
  end
  if type(maxmana) == 'function' and maxmana ~= HelperAPI.maxMp then
    local ok, val = pcall(maxmana)
    if ok and type(val) == 'number' then return val end
  end
  return nil
end

function HelperAPI.mpPercent()
  local lp = getLocalPlayer()
  if lp and type(lp.getManaPercent) == 'function' then
    local ok, val = pcall(function() return lp:getManaPercent() end)
    if ok and type(val) == 'number' then return val end
  end
  if type(manapercent) == 'function' and manapercent ~= HelperAPI.mpPercent then
    local ok, val = pcall(manapercent)
    if ok and type(val) == 'number' then return val end
  end
  if type(mppercent) == 'function' and mppercent ~= HelperAPI.mpPercent then
    local ok, val = pcall(mppercent)
    if ok and type(val) == 'number' then return val end
  end
  local cur = HelperAPI.mp()
  local max = HelperAPI.maxMp()
  if cur and max and max > 0 then
    return math.floor((cur / max) * 100)
  end
  return 100
end

function HelperAPI.playerPos()
  local lp = getLocalPlayer()
  if lp and type(lp.getPosition) == 'function' then
    local ok, pos = pcall(function() return lp:getPosition() end)
    if ok and pos and pos.x then
      return {x = pos.x, y = pos.y, z = pos.z}
    end
  end
  if type(pos) == 'function' and pos ~= HelperAPI.playerPos then
    local ok, p = pcall(pos)
    if ok and p and p.x then
      return {x = p.x, y = p.y, z = p.z}
    end
  end
  return nil
end

-- ============================================================================
-- Equipment
-- ============================================================================

function HelperAPI.getSlotItem(slot)
  if slot == nil then return nil end

  if type(getSlot) == 'function' and getSlot ~= HelperAPI.getSlotItem then
    local ok, item = pcall(getSlot, slot)
    if ok and item then return item end
  end

  local lp = getLocalPlayer()
  if lp then
    if type(lp.getItem) == 'function' then
      local ok, item = pcall(function() return lp:getItem(slot) end)
      if ok and item then return item end
    end
    if type(lp.getInventoryItem) == 'function' then
      local ok, item = pcall(function() return lp:getInventoryItem(slot) end)
      if ok and item then return item end
    end
  end

  if g_game and type(g_game.getInventoryItem) == 'function' then
    local ok, item = pcall(g_game.getInventoryItem, slot)
    if ok and item then return item end
  end

  return nil
end

HelperAPI._cachedEquipMethod = nil

-- Rings and amulets are equipped by "using" them in many clients, and Inmortal
-- relies on that when equipItemId/equipItem are missing, so the use-based
-- fallbacks stay on by default. Set to false to restrict equipItemById to
-- real equip calls (it will then never consume a usable item by mistake).
if HelperAPI.allowUseFallback == nil then HelperAPI.allowUseFallback = true end

-- ---------------------------------------------------------------------------
-- Equip tracing (read-only): the last attempts, what each native method
-- returned, and what the finger/neck slots held before and 700 ms after.
-- A native call returning without error does not prove the server equipped
-- the item, so the slot snapshot is the real evidence. Shown by the
-- diagnostics panel and written to _diagnostics/client-report.json.
-- ---------------------------------------------------------------------------
HelperAPI.trace = HelperAPI.trace or {}

-- Events go to the bot's existing console (RinoConsole), under "Acciones".
function HelperAPI.consoleLog(message, detail)
  if RinoConsole and type(RinoConsole.log) == 'function' then
    pcall(RinoConsole.log, 'action', 'Inmortal', message, detail)
  end
end

function HelperAPI.traceAdd(entry)
  entry.at = type(now) == 'number' and now or 0
  table.insert(HelperAPI.trace, entry)
  while #HelperAPI.trace > 24 do table.remove(HelperAPI.trace, 1) end
  return entry
end

local function slotItemId(slot)
  local item = HelperAPI.getSlotItem(slot)
  if not item then return 0 end
  local ok, id = pcall(function() return item:getId() end)
  return ok and tonumber(id) or -1
end

function HelperAPI.slotIds()
  local caps = ClientDetector and ClientDetector.caps or {}
  return {finger = slotItemId(caps.fingerSlot or 9), neck = slotItemId(caps.neckSlot or 2)}
end

function HelperAPI.equipItemById(itemId, preferObject)
  itemId = tonumber(itemId)
  if not itemId or itemId <= 0 then return false end

  local lp = getLocalPlayer()
  local slotsBefore = HelperAPI.slotIds()
  local entry = HelperAPI.traceAdd({kind = 'equip', itemId = itemId, tried = {}, before = slotsBefore})
  local function verifyLater(method)
    entry.method = method
    if type(schedule) == 'function' then
      schedule(700, function()
        entry.after = HelperAPI.slotIds()
        local b, a = entry.before or {}, entry.after
        HelperAPI.consoleLog('equipar ' .. tostring(itemId) .. ' via ' .. tostring(method) ..
          (entry.cached and ' (metodo en cache)' or ''),
          'dedo ' .. tostring(b.finger) .. '->' .. tostring(a.finger) ..
          ' | cuello ' .. tostring(b.neck) .. '->' .. tostring(a.neck) ..
          ' | probados: ' .. table.concat(entry.tried or {}, ','))
      end)
    end
  end

  local function tryMethod(method)
    if method == "equipItemId" then
      if g_game and type(g_game.equipItemId) == 'function' then
        local ok, res = pcall(g_game.equipItemId, itemId, 0)
        if ok and res ~= false then return true end
        local ok2, res2 = pcall(g_game.equipItemId, itemId)
        if ok2 and res2 ~= false then return true end
      end
    elseif method == "equipItemObject" then
      if g_game and type(g_game.equipItem) == 'function' and Item and type(Item.create) == 'function' then
        local ok, itm = pcall(Item.create, itemId)
        if ok and itm then
          local eOk, res = pcall(g_game.equipItem, itm)
          if eOk and res ~= false then return true end
        end
      end
    elseif method == "actionbar" then
      local ab = (modules and (modules.game_actionbar or modules.game_actionbars)) or nil
      if ab and type(ab.onExecuteAction) == 'function' and g_ui and type(g_ui.getRootWidget) == 'function' then
        local root = g_ui.getRootWidget()
        local button = root and root:recursiveGetChildById("actionButton" .. tostring(itemId))
        if button then
          local ok, res = pcall(ab.onExecuteAction, button)
          if ok and res ~= false then return true end
        end
      end
    elseif method == "hotkeys" then
      if modules and modules.game_hotkeys then
        if type(modules.game_hotkeys.useHotkeyItem) == 'function' then
          local ok, res = pcall(modules.game_hotkeys.useHotkeyItem, itemId)
          if ok and res ~= false then return true end
        end
        if lp and type(modules.game_hotkeys.useHotkeyItemWith) == 'function' then
          local ok, res = pcall(modules.game_hotkeys.useHotkeyItemWith, itemId, lp)
          if ok and res ~= false then return true end
        end
      end
    elseif method == "useInventoryItem" then
      if g_game and type(g_game.useInventoryItem) == 'function' then
        local ok, res = pcall(g_game.useInventoryItem, itemId, 0)
        if ok and res ~= false then return true end
        local ok2, res2 = pcall(g_game.useInventoryItem, itemId)
        if ok2 and res2 ~= false then return true end
      end
    elseif method == "useInventoryItemWith" then
      if g_game and type(g_game.useInventoryItemWith) == 'function' and lp then
        local ok, res = pcall(g_game.useInventoryItemWith, itemId, lp, 0)
        if ok and res ~= false then return true end
      end
    end
    return false
  end

  -- Record what each method returned, not only the one that "worked".
  local rawTry = tryMethod
  tryMethod = function(method)
    local returned = rawTry(method)
    entry.tried[#entry.tried + 1] = method .. '=' .. tostring(returned)
    return returned
  end

  -- Try cached method first if available
  if HelperAPI._cachedEquipMethod then
    if tryMethod(HelperAPI._cachedEquipMethod) then
      entry.cached = true
      verifyLater(HelperAPI._cachedEquipMethod)
      return true, HelperAPI._cachedEquipMethod
    end
  end

  -- Determine evaluation order
  local methods = {}
  if preferObject then
    table.insert(methods, "equipItemObject")
    table.insert(methods, "equipItemId")
  else
    table.insert(methods, "equipItemId")
    table.insert(methods, "equipItemObject")
  end
  table.insert(methods, "actionbar")
  table.insert(methods, "hotkeys")
  if HelperAPI.allowUseFallback then
    table.insert(methods, "useInventoryItem")
    table.insert(methods, "useInventoryItemWith")
  end

  for _, m in ipairs(methods) do
    if m ~= HelperAPI._cachedEquipMethod then
      if tryMethod(m) then
        HelperAPI._cachedEquipMethod = m
        verifyLater(m)
        return true, m
      end
    end
  end

  HelperAPI.consoleLog('equipar ' .. tostring(itemId) .. ': ningun metodo respondio',
    'probados: ' .. table.concat(entry.tried or {}, ','))
  return false
end

function HelperAPI.unequipSlot(slot, destContainer)
  if slot == nil then return false end

  if g_game and type(g_game.unequipItem) == 'function' then
    local ok, res = pcall(g_game.unequipItem, slot)
    if ok and res ~= false then return true end
  end

  local item = HelperAPI.getSlotItem(slot)
  if not item then return false end

  if destContainer and type(destContainer.getSlotPosition) == 'function' and type(destContainer.getItemsCount) == 'function' then
    local ok, pos = pcall(function() return destContainer:getSlotPosition(destContainer:getItemsCount()) end)
    if ok and pos and g_game and type(g_game.move) == 'function' then
      local mOk, res = pcall(g_game.move, item, pos, item:getCount() or 1)
      if mOk and res ~= false then return true end
    end
  end

  local backSlot = (ClientDetector and ClientDetector.caps and ClientDetector.caps.backSlot)
    or SlotBack or InventorySlotBack or 3

  if g_game and type(g_game.move) == 'function' then
    local count = 1
    if type(item.getCount) == 'function' then
      local cOk, c = pcall(function() return item:getCount() end)
      if cOk and c then count = c end
    end
    local ok, res = pcall(g_game.move, item, {x = 65535, y = backSlot, z = 0}, count)
    if ok and res ~= false then return true end
  end

  return false
end

-- ============================================================================
-- Combat
-- ============================================================================

function HelperAPI.attackCreature(creature)
  if not creature then return false end

  if g_game and type(g_game.attack) == 'function' then
    local ok, res = pcall(g_game.attack, creature)
    if ok and res ~= false then return true end
  end

  if type(attack) == 'function' and attack ~= HelperAPI.attackCreature then
    local ok, res = pcall(attack, creature)
    if ok and res ~= false then return true end
  end

  return false
end

function HelperAPI.cancelAttack()
  local done = false

  if g_game and type(g_game.cancelAttack) == 'function' then
    local ok = pcall(g_game.cancelAttack)
    if ok then done = true end
  end

  if g_game and type(g_game.cancelAttackAndFollow) == 'function' then
    local ok = pcall(g_game.cancelAttackAndFollow)
    if ok then done = true end
  end

  if type(cancelAttack) == 'function' and cancelAttack ~= HelperAPI.cancelAttack then
    local ok = pcall(cancelAttack)
    if ok then done = true end
  end

  return done
end

function HelperAPI.getTarget()
  if g_game and type(g_game.getAttackingCreature) == 'function' then
    local ok, c = pcall(g_game.getAttackingCreature)
    if ok and c then return c end
  end

  if type(target) == 'function' and target ~= HelperAPI.getTarget then
    local ok, c = pcall(target)
    if ok and c then return c end
  end

  if type(getTarget) == 'function' and getTarget ~= HelperAPI.getTarget then
    local ok, c = pcall(getTarget)
    if ok and c then return c end
  end

  return nil
end

-- ============================================================================
-- Items & Containers
-- ============================================================================

function HelperAPI.getContainers()
  if ApiCompat and ApiCompat.has('getContainers') then
    return ApiCompat.getContainers()
  end

  if g_game and type(g_game.getContainers) == 'function' then
    local ok, list = pcall(g_game.getContainers)
    if ok and type(list) == 'table' then return list end
  end

  if type(getContainers) == 'function' and getContainers ~= HelperAPI.getContainers then
    local ok, list = pcall(getContainers)
    if ok and type(list) == 'table' then return list end
  end

  return {}
end

function HelperAPI.findItem(itemId)
  itemId = tonumber(itemId)
  if not itemId or itemId <= 0 then return nil end

  if type(findItem) == 'function' and findItem ~= HelperAPI.findItem then
    local ok, item = pcall(findItem, itemId)
    if ok and item then return item end
  end

  local containers = HelperAPI.getContainers()
  for _, container in pairs(containers) do
    if container and type(container.getItems) == 'function' then
      local ok, items = pcall(function() return container:getItems() end)
      if ok and type(items) == 'table' then
        for _, itm in ipairs(items) do
          if itm and type(itm.getId) == 'function' and itm:getId() == itemId then
            return itm
          end
        end
      end
    end
  end

  return nil
end

function HelperAPI.useItemOnSelf(itemId)
  itemId = tonumber(itemId)
  if not itemId or itemId <= 0 then return false end

  local lp = getLocalPlayer()

  if PushMax and type(PushMax.performItem) == 'function' then
    local ok, res = pcall(PushMax.performItem, 'HelperAPI', itemId, true, nil, itemId)
    if ok and res then return true end
  end

  if g_game and type(g_game.useInventoryItemWith) == 'function' and lp then
    local ok, res = pcall(g_game.useInventoryItemWith, itemId, lp, 0)
    if ok and res ~= false then return true end
  end

  if type(useWith) == 'function' and lp then
    local ok, res = pcall(useWith, itemId, lp, 0)
    if ok and res ~= false then return true end
  end

  if g_game and type(g_game.useInventoryItem) == 'function' then
    local ok, res = pcall(g_game.useInventoryItem, itemId, 0)
    if ok and res ~= false then return true end
  end

  local item = HelperAPI.findItem(itemId)
  if item and lp and g_game and type(g_game.useWith) == 'function' then
    local ok, res = pcall(g_game.useWith, item, lp)
    if ok and res ~= false then return true end
  end

  return false
end

function HelperAPI.moveItem(item, dest, count)
  if not item or not dest then return false end

  if g_game and type(g_game.move) == 'function' then
    local c = count
    if not c and type(item.getCount) == 'function' then
      local ok, cnt = pcall(function() return item:getCount() end)
      c = ok and cnt or 1
    end
    c = c or 1

    local ok, res = pcall(g_game.move, item, dest, c)
    return ok and res ~= false
  end

  return false
end

-- ============================================================================
-- Walking
-- ============================================================================

function HelperAPI.walk(dir)
  if dir == nil then return false end

  if type(safeBotWalk) == 'function' then
    local ok, res = pcall(safeBotWalk, dir)
    if ok and res ~= false then return true end
  end

  if type(walk) == 'function' and walk ~= HelperAPI.walk and walk ~= safeBotWalk then
    local ok, res = pcall(walk, dir)
    if ok and res ~= false then return true end
  end

  if g_game and type(g_game.walk) == 'function' then
    local ok, res = pcall(g_game.walk, dir, false)
    if ok and res ~= false then return true end
  end

  return false
end

-- ============================================================================
-- Spells & Chat
-- ============================================================================

function HelperAPI.say(text, sayType)
  if not text or text == '' then return false end

  if type(say) == 'function' and say ~= HelperAPI.say then
    local ok, res = pcall(say, text)
    if ok and res ~= false then return true end
  end

  if g_game and type(g_game.talk) == 'function' then
    local ok, res = pcall(g_game.talk, text)
    if ok and res ~= false then return true end
  end

  if g_game and type(g_game.talkChannel) == 'function' then
    local ok, res = pcall(g_game.talkChannel, sayType or 1, 0, text)
    if ok and res ~= false then return true end
  end

  return false
end

-- ============================================================================
-- Global Fallback Bridges (Non-breaking for legacy modules)
-- ============================================================================

if type(getSlot) ~= 'function' then
  getSlot = function(slot) return HelperAPI.getSlotItem(slot) end
end

if type(hppercent) ~= 'function' then
  hppercent = function() return HelperAPI.hpPercent() end
end

if type(manapercent) ~= 'function' and type(mppercent) ~= 'function' then
  manapercent = function() return HelperAPI.mpPercent() end
  mppercent = manapercent
elseif type(manapercent) ~= 'function' and type(mppercent) == 'function' then
  manapercent = mppercent
elseif type(mppercent) ~= 'function' and type(manapercent) == 'function' then
  mppercent = manapercent
end

if type(findItem) ~= 'function' then
  findItem = function(id) return HelperAPI.findItem(id) end
end

if type(attack) ~= 'function' then
  attack = function(c) return HelperAPI.attackCreature(c) end
end

if type(cancelAttack) ~= 'function' then
  cancelAttack = function() return HelperAPI.cancelAttack() end
end

if type(target) ~= 'function' then
  target = function() return HelperAPI.getTarget() end
end

if type(getTarget) ~= 'function' then
  getTarget = function() return HelperAPI.getTarget() end
end

return HelperAPI
