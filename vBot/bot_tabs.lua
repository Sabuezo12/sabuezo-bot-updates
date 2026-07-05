local tabWidths = {
  Main = 30,
  Tools = 34,
  Cave = 32,
  Target = 44,
  Targ = 44,
  Tgt = 28,
  HP = 22
}

local function safeCall(fn)
  local ok, result = pcall(fn)
  if ok then
    return result
  end
end

local function getChildren(widget)
  return safeCall(function()
    return widget:getChildren()
  end) or {}
end

local function getText(widget)
  return safeCall(function()
    return widget:getText()
  end)
end

local function compactWidget(widget, width)
  safeCall(function() widget:setWidth(width) end)
  safeCall(function() widget:setHeight(18) end)
  safeCall(function() widget:setSize({ width = width, height = 18 }) end)
  safeCall(function() widget:setTextAlign(AlignCenter) end)
  safeCall(function() widget:setFont("verdana-11px-rounded") end)
end

local function collectTabRows(widget, rows)
  local children = getChildren(widget)
  if #children > 0 then
    local row = {}
    for _, child in ipairs(children) do
      local text = getText(child)
      if tabWidths[text] then
        table.insert(row, child)
      end
    end
    if #row >= 3 then
      table.insert(rows, row)
    end
  end

  for _, child in ipairs(children) do
    collectTabRows(child, rows)
  end
end

local function getBotWindow()
  local widget = modules and modules.game_bot and modules.game_bot.contentsPanel
  for _ = 1, 12 do
    if not widget then
      return nil
    end

    if getText(widget) == "Bot" then
      return widget
    end

    local parent = safeCall(function()
      return widget:getParent()
    end)
    if not parent or parent == rootWidget then
      return widget
    end
    widget = parent
  end
  return widget
end

local function compactBotTabs()
  local botWindow = getBotWindow()
  if not botWindow then
    return false
  end

  local rows = {}
  collectTabRows(botWindow, rows)
  if #rows == 0 then
    return false
  end

  for _, row in ipairs(rows) do
    for _, tab in ipairs(row) do
      local text = getText(tab)
      local width = tabWidths[text]
      if width then
        compactWidget(tab, width)
      end
    end
    safeCall(function() row[1]:getParent():updateLayout() end)
  end

  return true
end

local attempts = 0
local function retryCompactTabs()
  attempts = attempts + 1
  if compactBotTabs() or attempts >= 20 then
    return
  end

  if schedule then
    schedule(300, retryCompactTabs)
  elseif scheduleEvent then
    scheduleEvent(retryCompactTabs, 300)
  end
end

retryCompactTabs()
