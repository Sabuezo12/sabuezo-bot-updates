setDefaultTab("Main")

local panelName = "timerExecutor"

if type(storage[panelName]) ~= "table" then
  storage[panelName] = {
    enabled = false,
    actions = {}
  }
end

local config = storage[panelName]
if type(config.actions) ~= "table" then config.actions = {} end

local ui = setupUI([[
Panel
  height: 20

  BotSwitch
    id: enabled
    anchors.left: parent.left
    anchors.top: parent.top
    width: 130
    height: 18
    text-align: center
    text: Timer Executor

  Button
    id: setup
    anchors.left: prev.right
    anchors.right: parent.right
    anchors.top: prev.top
    margin-left: 3
    height: 18
    text: Setup
]], parent)

local runtime = {}
local rowStates = {}
local window

local actionTypes = {
  ["Say"] = true,
  ["Cast"] = true,
  ["Use Item"] = true,
  ["Use Self"] = true,
  ["Use Target"] = true,
  ["Use Tile"] = true,
  ["Lua"] = true
}

local function trim(text)
  return tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function safeCall(fn, ...)
  if type(fn) ~= "function" then return false end
  local ok, result = pcall(fn, ...)
  return ok and result ~= false
end

local function safeSay(text)
  text = trim(text)
  if text == "" then return false, "Empty text" end
  if safeCall(say, text) then return true end
  if g_game and g_game.talk and safeCall(function(words) g_game.talk(words) end, text) then return true end
  return false, "Cannot talk"
end

local function safeCast(text, interval)
  text = trim(text)
  if text == "" then return false, "Empty spell" end
  if type(canCast) == "function" and not canCast(text) then return false, "Cooldown" end
  if type(cast) == "function" and safeCall(cast, text, interval) then return true end
  return safeSay(text)
end

local function getVisibleItem(itemId)
  itemId = tonumber(itemId)
  if not itemId or itemId <= 100 then return nil end
  if type(findItem) == "function" then
    local ok, item = pcall(findItem, itemId)
    if ok and item then return item end
  end
  return nil
end

local function useThing(thing)
  if not thing then return false end
  if safeCall(use, thing) then return true end
  if g_game and g_game.use and safeCall(function(target) g_game.use(target) end, thing) then return true end
  return false
end

local function useItemId(itemId)
  itemId = tonumber(itemId)
  if not itemId or itemId <= 100 then return false, "No item" end

  local item = getVisibleItem(itemId)
  if item and useThing(item) then return true end
  if g_game and g_game.useInventoryItem and safeCall(g_game.useInventoryItem, itemId) then return true end
  return false, "Item not found"
end

local function useItemWithTarget(itemId, targetThing)
  itemId = tonumber(itemId)
  if not itemId or itemId <= 100 then return false, "No item" end
  if not targetThing then return false, "No target" end

  if g_game and g_game.useInventoryItemWith and safeCall(g_game.useInventoryItemWith, itemId, targetThing, 0) then return true end
  if modules and modules.game_hotkeys and modules.game_hotkeys.useHotkeyItemWith and
    safeCall(modules.game_hotkeys.useHotkeyItemWith, itemId, targetThing, 0) then return true end
  if safeCall(useWith, itemId, targetThing, 0) then return true end

  local item = getVisibleItem(itemId)
  if item and g_game and g_game.useWith and safeCall(function(source, target) g_game.useWith(source, target, 0) end, item, targetThing) then
    return true
  end

  return false, "Use failed"
end

local function currentTarget()
  if type(target) == "function" then
    local ok, creature = pcall(target)
    if ok and creature then return creature end
  end
  if g_game and g_game.getAttackingCreature then
    local ok, creature = pcall(function() return g_game.getAttackingCreature() end)
    if ok and creature then return creature end
  end
  return nil
end

local function parseOffset(text)
  text = trim(text)
  if text == "" then return 0, 0 end

  local x, y = text:match("^%s*(-?%d+)%s*[,; ]%s*(-?%d+)%s*$")
  return tonumber(x) or 0, tonumber(y) or 0
end

local function getOffsetTile(text)
  if not player or not player.getPosition then return nil end
  local p = player:getPosition()
  if not p then return nil end

  local offsetX, offsetY = parseOffset(text)
  local pos = {x = p.x + offsetX, y = p.y + offsetY, z = p.z}
  return g_map and g_map.getTile and g_map.getTile(pos) or nil
end

local function executeLua(code)
  code = trim(code)
  if code == "" then return false, "Empty code" end
  if type(loadstring) ~= "function" then return false, "No loadstring" end

  local chunk, err = loadstring(code)
  if not chunk then return false, tostring(err or "Lua error") end

  local ok, result = pcall(chunk)
  if not ok then return false, tostring(result or "Lua error") end
  if result == false then return false, "Returned false" end
  return true
end

local function ensureAction(action)
  if type(action) ~= "table" then action = {} end
  if not action.id then
    action.id = tostring(os.time()) .. "-" .. tostring(math.random(100000, 999999))
  end
  action.enabled = action.enabled == true
  if not actionTypes[action.actionType] then action.actionType = "Say" end
  action.name = trim(action.name)
  if action.name == "" then action.name = action.actionType end
  action.interval = tonumber(action.interval) or 60
  if action.interval < 1 then action.interval = 1 end
  if action.interval > 86400 then action.interval = 86400 end
  action.value = tostring(action.value or "")
  action.item = tonumber(action.item) or 0
  action.skipPz = action.skipPz == true
  action.skipAttack = action.skipAttack == true
  action.runOnStart = action.runOnStart == true
  action.once = action.once == true
  return action
end

local function intervalMs(action)
  return math.max(1, tonumber(action.interval) or 1) * 1000
end

local function getRuntime(action)
  action = ensureAction(action)
  runtime[action.id] = runtime[action.id] or {}
  local data = runtime[action.id]
  if not data.nextAt then
    data.nextAt = now + (action.runOnStart and 0 or intervalMs(action))
  end
  return data
end

local function setStatus(action, text, color)
  local state = rowStates[action.id]
  if state and state.status then
    state.status:setText(text or "-")
    state.status:setColor(color or "#aaaaaa")
  end
end

local function formatRemaining(seconds)
  seconds = math.max(0, math.floor(tonumber(seconds) or 0))
  if seconds < 60 then return tostring(seconds) .. "s" end
  if seconds < 3600 then
    return string.format("%dm %02ds", math.floor(seconds / 60), seconds % 60)
  end
  return string.format("%dh %02dm", math.floor(seconds / 3600), math.floor((seconds % 3600) / 60))
end

local function shouldSkip(action)
  if action.skipPz and type(isInPz) == "function" and isInPz() then
    return true, "PZ"
  end
  if action.skipAttack and g_game and g_game.isAttacking and g_game.isAttacking() then
    return true, "ATK"
  end
  return false
end

local function executeAction(action)
  action = ensureAction(action)
  local kind = action.actionType
  local itemId = tonumber(action.item) or 0
  local value = tostring(action.value or "")

  if kind == "Say" then
    return safeSay(value)
  elseif kind == "Cast" then
    return safeCast(value, intervalMs(action))
  elseif kind == "Use Item" then
    return useItemId(itemId)
  elseif kind == "Use Self" then
    return useItemWithTarget(itemId, player)
  elseif kind == "Use Target" then
    return useItemWithTarget(itemId, currentTarget())
  elseif kind == "Use Tile" then
    local tile = getOffsetTile(value)
    local thing = tile and tile:getTopUseThing()
    return useItemWithTarget(itemId, thing)
  elseif kind == "Lua" then
    return executeLua(value)
  end

  return false, "Bad type"
end

local function retryDelayMs(action)
  return math.min(5000, math.max(1000, math.floor(intervalMs(action) / 10)))
end

local function runAndSchedule(action)
  local data = getRuntime(action)
  if data.running then return false, "Busy" end

  data.running = true
  local ok, result, detail = pcall(executeAction, action)
  data.running = false

  local success = ok and result == true
  local err = ok and detail or result
  if success then
    data.nextAt = now + intervalMs(action)
    data.lastAt = now
    data.lastError = nil
    setStatus(action, "Hecho", "#8cff9a")
    if action.once then
      action.enabled = false
      local state = rowStates[action.id]
      if state and state.widget and state.widget.enabled then
        state.widget.enabled:setChecked(false)
      end
    end
  else
    data.nextAt = now + retryDelayMs(action)
    data.lastError = tostring(err or "Failed")
    setStatus(action, data.lastError:sub(1, 14), "#ff8888")
  end

  return success, err
end

local function updateStatus(action)
  action = ensureAction(action)
  if not config.enabled then
    setStatus(action, "Paused", "#aaaaaa")
    return
  end
  if not action.enabled then
    setStatus(action, "Off", "#aaaaaa")
    return
  end

  local skipped, reason = shouldSkip(action)
  if skipped then
    setStatus(action, reason, "#ffd166")
    return
  end

  local data = getRuntime(action)
  local remain = math.max(0, math.ceil(((data.nextAt or now) - now) / 1000))
  setStatus(action, remain <= 0 and "Listo" or formatRemaining(remain), remain <= 0 and "#8cff9a" or "#9dd1ce")
end

local function resetTimers()
  runtime = {}
  for _, action in ipairs(config.actions) do
    action = ensureAction(action)
    local data = getRuntime(action)
    data.nextAt = now + (action.runOnStart and 0 or intervalMs(action))
    updateStatus(action)
  end
end

local refreshRows

local function updateActionInputs(row, action)
  local kind = action.actionType
  local needsItem = kind == "Use Item" or kind == "Use Self" or kind == "Use Target" or kind == "Use Tile"
  local needsValue = kind == "Say" or kind == "Cast" or kind == "Use Tile" or kind == "Lua"

  row.item:setVisible(needsItem)
  row.value:setVisible(needsValue)

  if needsValue then
    pcall(function()
      row.value:breakAnchors()
      row.value:addAnchor(AnchorLeft, needsItem and "item" or "secondsLabel", AnchorRight)
      row.value:addAnchor(AnchorRight, "parent", AnchorRight)
      row.value:addAnchor(AnchorTop, "actionType", AnchorTop)
      row.value:setMarginLeft(7)
      row.value:setMarginRight(8)
    end)
  end

  if kind == "Use Tile" then
    row.value:setTooltip("Offset de la casilla: x,y")
  elseif kind == "Lua" then
    row.value:setTooltip("Codigo Lua a ejecutar")
  elseif kind == "Say" or kind == "Cast" then
    row.value:setTooltip("Texto o palabras del hechizo")
  else
    row.value:setTooltip("Esta accion no necesita texto")
  end
end

local function updateWindowSummary()
  if not window then return end

  local active = 0
  local nextRemain = nil
  for _, action in ipairs(config.actions) do
    action = ensureAction(action)
    if action.enabled then
      active = active + 1
      local data = getRuntime(action)
      local remain = math.max(0, math.ceil(((data.nextAt or now) - now) / 1000))
      if nextRemain == nil or remain < nextRemain then nextRemain = remain end
    end
  end

  if window.master then window.master:setOn(config.enabled == true) end
  if window.empty then window.empty:setVisible(#config.actions == 0) end
  if not window.summary then return end

  if not config.enabled then
    window.summary:setText("Pausado | " .. (active == 1 and "1 activa" or (active .. " activas")))
    window.summary:setColor("#ffd166")
  elseif active == 0 then
    window.summary:setText("Sin acciones activas")
    window.summary:setColor("#aaaaaa")
  else
    local activeText = active == 1 and "1 activa" or (active .. " activas")
    window.summary:setText(activeText .. " | proxima " .. formatRemaining(nextRemain or 0))
    window.summary:setColor("#9dd1ce")
  end
end

local function resizeWindow()
  if not window or not window.setHeight then return end
  local desired = math.min(420, math.max(220, 129 + (#config.actions * 95)))
  pcall(function() window:setHeight(desired) end)
end

local function bindActionRow(row, action, index)
  action = ensureAction(action)
  config.actions[index] = action
  rowStates[action.id] = {widget = row, status = row.status}

  row.name:setText(action.name)
  row.name.onTextChange = function(widget, text)
    action.name = trim(text)
  end

  row.enabled:setChecked(action.enabled)
  row.enabled.onClick = function(widget)
    action.enabled = not action.enabled
    widget:setChecked(action.enabled)
    local data = getRuntime(action)
    data.nextAt = now + (action.runOnStart and 0 or intervalMs(action))
    updateStatus(action)
  end

  if row.actionType.setOption then row.actionType:setOption(action.actionType) end
  row.actionType.onOptionChange = function(widget)
    local option = widget:getCurrentOption()
    local previousType = action.actionType
    action.actionType = option and option.text or "Say"
    if action.name == "" or action.name == previousType then
      action.name = action.actionType
      row.name:setText(action.name)
    end
    updateActionInputs(row, action)
    updateStatus(action)
  end

  row.interval:setValue(action.interval)
  row.interval.onValueChange = function(widget, value)
    action.interval = tonumber(value) or 1
    local data = getRuntime(action)
    data.nextAt = now + intervalMs(action)
    updateStatus(action)
  end

  row.item:setItemId(action.item)
  if row.item.setShowCount then row.item:setShowCount(false) end
  row.item.onItemChange = function(widget)
    action.item = widget:getItemId()
  end

  row.value:setText(action.value)
  row.value.onTextChange = function(widget, text)
    action.value = text
  end

  row.skipPz:setChecked(action.skipPz)
  row.skipPz.onClick = function(widget)
    action.skipPz = not action.skipPz
    widget:setChecked(action.skipPz)
    updateStatus(action)
  end

  row.skipAttack:setChecked(action.skipAttack)
  row.skipAttack.onClick = function(widget)
    action.skipAttack = not action.skipAttack
    widget:setChecked(action.skipAttack)
    updateStatus(action)
  end

  row.runOnStart:setChecked(action.runOnStart)
  row.runOnStart.onClick = function(widget)
    action.runOnStart = not action.runOnStart
    widget:setChecked(action.runOnStart)
    local data = getRuntime(action)
    data.nextAt = now + (action.runOnStart and 0 or intervalMs(action))
    updateStatus(action)
  end

  row.once:setChecked(action.once)
  row.once.onClick = function(widget)
    action.once = not action.once
    widget:setChecked(action.once)
  end

  row.duplicate.onClick = function()
    table.insert(config.actions, index + 1, ensureAction({
      enabled = action.enabled,
      name = action.name .. " copia",
      actionType = action.actionType,
      interval = action.interval,
      value = action.value,
      item = action.item,
      skipPz = action.skipPz,
      skipAttack = action.skipAttack,
      runOnStart = false,
      once = action.once
    }))
    refreshRows()
  end

  row.run.onClick = function()
    local skipped, reason = shouldSkip(action)
    if skipped then
      setStatus(action, reason, "#ffd166")
      return
    end

    runAndSchedule(action)
    updateWindowSummary()
  end

  row.remove.onClick = function()
    runtime[action.id] = nil
    table.remove(config.actions, index)
    refreshRows()
  end

  updateActionInputs(row, action)
  updateStatus(action)
end

refreshRows = function()
  if not window then return end
  window.list:destroyChildren()
  rowStates = {}

  for index, action in ipairs(config.actions) do
    local row = UI.createWidget("TimerExecutorActionRow", window.list)
    bindActionRow(row, action, index)
  end

  resizeWindow()
  updateWindowSummary()
end

local rootWidget = g_ui.getRootWidget()
if rootWidget then
  local previousWindow = rootWidget:recursiveGetChildById("TimerExecutorWindow")
  if previousWindow then previousWindow:destroy() end
  window = UI.createWindow("TimerExecutorWindow", rootWidget)
  window:hide()

  window.add.onClick = function()
    table.insert(config.actions, ensureAction({
      enabled = true,
      name = "Nueva accion",
      actionType = "Say",
      interval = 60,
      value = "",
      item = 0,
      skipPz = false,
      skipAttack = false,
      runOnStart = false,
      once = false
    }))
    refreshRows()
  end

  window.reset.onClick = function()
    resetTimers()
    updateWindowSummary()
  end


  window.master:setOn(config.enabled)
  window.master.onClick = function(widget)
    config.enabled = not config.enabled
    widget:setOn(config.enabled)
    ui.enabled:setOn(config.enabled)
    resetTimers()
    updateWindowSummary()
  end

  refreshRows()
end

ui.enabled:setOn(config.enabled)
ui.enabled.onClick = function(widget)
  config.enabled = not config.enabled
  widget:setOn(config.enabled)
  resetTimers()
  updateWindowSummary()
end

ui.setup.onClick = function()
  if not window then return end
  refreshRows()
  window:show()
  window:raise()
  window:focus()
end

TimerExecutor = {
  isOn = function()
    return config.enabled == true
  end,
  setOn = function()
    config.enabled = true
    ui.enabled:setOn(true)
    resetTimers()
    updateWindowSummary()
  end,
  setOff = function()
    config.enabled = false
    ui.enabled:setOn(false)
    resetTimers()
    updateWindowSummary()
  end,
  show = function()
    if ui.setup and ui.setup.onClick then ui.setup.onClick() end
  end
}

macro(250, function()
  ui.enabled:setOn(config.enabled)

  for _, action in ipairs(config.actions) do
    action = ensureAction(action)
    if config.enabled and action.enabled then
      local skipped, reason = shouldSkip(action)
      if skipped then
        setStatus(action, reason, "#ffd166")
      else
        local data = getRuntime(action)
        if now >= data.nextAt then
          runAndSchedule(action)
        else
          updateStatus(action)
        end
      end
    else
      updateStatus(action)
    end
  end

  updateWindowSummary()
end)
