Analyzer = Analyzer or {}

local XP_HISTORY_LIMIT = 15 * 60
local SKILL_HISTORY_LIMIT = 30 * 60
local CAVEBOT_DATA_LIMIT = 200

vBot.CaveBotData = vBot.CaveBotData or {
  refills = 0,
  rounds = 0,
  time = {},
  lastRefill = os.time(),
  refillTime = {}
}

vBot.CaveBotData.time = vBot.CaveBotData.time or {}
vBot.CaveBotData.refillTime = vBot.CaveBotData.refillTime or {}
vBot.CaveBotData.lastRefill = vBot.CaveBotData.lastRefill or os.time()
vBot.CaveBotData.refills = vBot.CaveBotData.refills or 0
vBot.CaveBotData.rounds = vBot.CaveBotData.rounds or 0

local launchTime = now
local startExp = 0
local expHistory = {}
local skillHistory = {}
local magicHistory = {}
local startSkillName = ""
local startSkillProgress = 0
local startMagicProgress = 0
local analyzerButton

storage.skillAnalyzer = storage.skillAnalyzer or {
  skillName = "Distance"
}
local skillConfig = storage.skillAnalyzer
skillConfig.skillName = skillConfig.skillName or "Distance"
if skillConfig.skillName == "Magic Level" then
  skillConfig.skillName = "Distance"
end

storage.analyzerLayout = storage.analyzerLayout or {}
local layoutConfig = storage.analyzerLayout
layoutConfig.windows = layoutConfig.windows or {}
local restoringLayout = false
local useNativeMiniWindowLayout = true

local analyzerPanels = {
  right = "getRightPanel",
  mainRight = "getMainRightPanel",
  rightExtra = "getRightExtraPanel",
  left = "getLeftPanel",
  leftExtra = "getLeftExtraPanel"
}

local analyzerPanelIds = {
  gameRightPanel = "right",
  gameMainRightPanel = "mainRight",
  gameRightExtraPanel = "rightExtra",
  gameLeftPanel = "left",
  gameLeftExtraPanel = "leftExtra"
}

local function getAnalyzerPanel(panelKey)
  local getter = analyzerPanels[panelKey]
  if not getter or not modules.game_interface or not modules.game_interface[getter] then return nil end

  local ok, panel = pcall(function()
    return modules.game_interface[getter]()
  end)

  if ok then return panel end
  return nil
end

local function getAnalyzerPanelKey(parent)
  if not parent then return nil end

  for panelKey in pairs(analyzerPanels) do
    if getAnalyzerPanel(panelKey) == parent then
      return panelKey
    end
  end

  local ok, parentId = pcall(function()
    return parent:getId()
  end)

  if ok and parentId then
    return analyzerPanelIds[parentId]
  end

  return nil
end

local function getAnalyzerPanelIndex(window)
  if not window then return nil end

  local okParent, parent = pcall(function()
    return window:getParent()
  end)
  if not okParent or not parent then return nil end

  local okIndex, index = pcall(function()
    return parent:getChildIndex(window)
  end)

  if okIndex then return tonumber(index) end
  return nil
end

local function saveAnalyzerWindowLayout(key, window)
  if useNativeMiniWindowLayout then return end
  if restoringLayout or not key or not window then return end

  local data = layoutConfig.windows[key] or {}
  local okParent, parent = pcall(function()
    return window:getParent()
  end)

  if okParent and parent then
    local panelKey = getAnalyzerPanelKey(parent)
    if panelKey then data.panel = panelKey end

    local okParentId, parentId = pcall(function()
      return parent:getId()
    end)
    if okParentId and parentId then data.parentId = parentId end

    local index = getAnalyzerPanelIndex(window)
    if index then data.index = index end
  end

  local okPos, posData = pcall(function()
    return window:getPosition()
  end)
  if okPos and posData and posData.x and posData.y then
    data.x = math.floor(posData.x)
    data.y = math.floor(posData.y)
  end

  local okVisible, visible = pcall(function()
    return window:isVisible()
  end)
  if okVisible then
    data.visible = visible == true
  end

  layoutConfig.windows[key] = data
end

local function applyAnalyzerWindowDock(key, window)
  local data = layoutConfig.windows[key]
  if type(data) ~= "table" or not window then return end

  local targetPanel = getAnalyzerPanel(data.panel)
  if not targetPanel and data.parentId and g_ui and g_ui.getRootWidget then
    local rootWidget = g_ui.getRootWidget()
    targetPanel = rootWidget and rootWidget:recursiveGetChildById(data.parentId) or nil
  end
  if not targetPanel then return end

  local targetIndex = tonumber(data.index)
  local okParent, currentParent = pcall(function()
    return window:getParent()
  end)
  if not okParent then currentParent = nil end

  if targetIndex then
    local okCount, childCount = pcall(function()
      return targetPanel:getChildCount()
    end)
    if okCount and childCount then
      local maxIndex = childCount
      if currentParent ~= targetPanel then maxIndex = maxIndex + 1 end
      if targetIndex < 1 then targetIndex = 1 end
      if targetIndex > maxIndex then targetIndex = maxIndex end
    end
  end

  if currentParent ~= targetPanel then
    local moved = false
    if targetPanel.insertChild and targetIndex then
      moved = pcall(function()
        if currentParent and currentParent.removeChild then
          currentParent:removeChild(window)
        end
        targetPanel:insertChild(targetIndex, window)
      end)
    end
    if not moved and window.setParent then
      pcall(function()
        window:setParent(targetPanel)
      end)
    end
  elseif targetIndex then
    local moved = false
    if targetPanel.moveChildToIndex then
      moved = pcall(function()
        targetPanel:moveChildToIndex(window, targetIndex)
      end)
    end
    if not moved and targetPanel.removeChild and targetPanel.insertChild then
      pcall(function()
        targetPanel:removeChild(window)
        targetPanel:insertChild(targetIndex, window)
      end)
    end
  end

  if targetPanel.fitAll then
    pcall(function()
      targetPanel:fitAll(window)
    end)
  end
end

local function restoreAnalyzerWindowLayout(key, window, restoreVisibility)
  if useNativeMiniWindowLayout then return end
  local data = layoutConfig.windows[key]
  if type(data) ~= "table" or not window then return end

  restoringLayout = true
  applyAnalyzerWindowDock(key, window)

  local okCurrentParent, currentParent = pcall(function()
    return window:getParent()
  end)
  local dockedInPanel = data.panel or analyzerPanelIds[tostring(data.parentId or "")]
  if okCurrentParent and getAnalyzerPanelKey(currentParent) then
    dockedInPanel = true
  end

  if not dockedInPanel and data.x and data.y then
    if window.move then
      pcall(function() window:move(data.x, data.y) end)
    elseif window.setPosition then
      pcall(function() window:setPosition({x = data.x, y = data.y}) end)
    end
  end

  if restoreVisibility == false then
    restoringLayout = false
    return
  end

  if data.visible == true then
    pcall(function()
      if key == "main" and window.open then
        window:open()
      else
        window:show()
      end
    end)
  else
    pcall(function()
      if key == "main" and window.close then
        window:close()
      else
        window:hide()
      end
    end)
  end
  restoringLayout = false
end

local function trackAnalyzerWindow(key, window)
  if not window then return end

  local previousGeometryChange = window.onGeometryChange
  window.onGeometryChange = function(widget, old, new)
    if previousGeometryChange then previousGeometryChange(widget, old, new) end
    if old and old.width == 0 and old.height == 0 then return end
    saveAnalyzerWindowLayout(key, widget)
  end

  local previousVisibilityChange = window.onVisibilityChange
  window.onVisibilityChange = function(widget, visible)
    if previousVisibilityChange then previousVisibilityChange(widget, visible) end
    saveAnalyzerWindowLayout(key, widget)
  end

  local previousDragLeave = window.onDragLeave
  window.onDragLeave = function(widget, droppedWidget, mousePos)
    local result = true
    if previousDragLeave then
      result = previousDragLeave(widget, droppedWidget, mousePos)
    end

    schedule(50, function()
      saveAnalyzerWindowLayout(key, widget)
    end)

    return result
  end
end

local function restoreAnalyzerWindowLayouts(windows, restoreVisibility)
  local orderedWindows = {}

  for _, tracked in ipairs(windows) do
    local data = layoutConfig.windows[tracked.key]
    table.insert(orderedWindows, {
      key = tracked.key,
      window = tracked.window,
      panel = type(data) == "table" and tostring(data.panel or data.parentId or "") or "",
      index = type(data) == "table" and (tonumber(data.index) or 999999) or 999999
    })
  end

  table.sort(orderedWindows, function(a, b)
    if a.panel == b.panel then return a.index < b.index end
    return a.panel < b.panel
  end)

  for _, tracked in ipairs(orderedWindows) do
    restoreAnalyzerWindowLayout(tracked.key, tracked.window, restoreVisibility)
  end
end

local oldWindows = {
  "MainAnalyzerWindow",
  "HuntingAnalyzerWindow",
  "LootAnalyzerWindow",
  "SupplyAnalyzerWindow",
  "ImpactAnalyzerWindow",
  "XPAnalyzerWindow",
  "SkillAnalyzerWindow",
  "PartyAnalyzerWindow",
  "ItemCounterAnalyzerWindow",
  "DropTracker",
  "CaveBotStats",
  "BossTracker",
  "FeaturesWindow"
}

for _, windowId in ipairs(oldWindows) do
  local element = g_ui.getRootWidget():recursiveGetChildById(windowId)
  if element then
    element:destroy()
  end
end

local mainWindow = UI.createMiniWindow("MainAnalyzerWindow")
mainWindow:hide()
mainWindow:setContentMaximumHeight(130)

local xpWindow = UI.createMiniWindow("XPAnalyzer")
xpWindow:hide()
xpWindow:setContentMaximumHeight(230)

local skillWindow = UI.createMiniWindow("SkillAnalyzer")
skillWindow:hide()
skillWindow:setContentMaximumHeight(240)

local statsWindow = UI.createMiniWindow("CaveBotStats")
statsWindow:hide()
statsWindow:setContentMaximumHeight(105)

local itemCounterWindow = UI.createMiniWindow("ItemCounterAnalyzer")
itemCounterWindow:hide()
itemCounterWindow:setContentMaximumHeight(320)

local function setupAnalyzerWindowOnStart(window)
  if window and window.setupOnStart then
    pcall(function()
      window:setupOnStart()
    end)
  end
end

setupAnalyzerWindowOnStart(mainWindow)
setupAnalyzerWindowOnStart(xpWindow)
setupAnalyzerWindowOnStart(skillWindow)
setupAnalyzerWindowOnStart(statsWindow)
setupAnalyzerWindowOnStart(itemCounterWindow)

trackAnalyzerWindow("main", mainWindow)
trackAnalyzerWindow("xp", xpWindow)
trackAnalyzerWindow("skill", skillWindow)
trackAnalyzerWindow("stats", statsWindow)
trackAnalyzerWindow("itemCounter", itemCounterWindow)

local trackedAnalyzerWindows = {
  {key = "main", window = mainWindow},
  {key = "xp", window = xpWindow},
  {key = "skill", window = skillWindow},
  {key = "stats", window = statsWindow},
  {key = "itemCounter", window = itemCounterWindow}
}

local keepButtons = {
  XPAnalyzer = true,
  SkillAnalyzer = true,
  Stats = true,
  ItemCounter = true,
  ResetSession = true
}

local children = mainWindow.contentsPanel:getChildren()
for _, child in ipairs(children) do
  if not keepButtons[child:getId()] then
    child:destroy()
  end
end

if mainWindow.contentsPanel.XPAnalyzer then
  mainWindow.contentsPanel.XPAnalyzer:setText("XP Analyzer")
end
if mainWindow.contentsPanel.SkillAnalyzer then
  mainWindow.contentsPanel.SkillAnalyzer:setText("Skill Analyzer")
end
if mainWindow.contentsPanel.Stats then
  mainWindow.contentsPanel.Stats:setText("CaveBot Stats")
end
if mainWindow.contentsPanel.ItemCounter then
  mainWindow.contentsPanel.ItemCounter:setText("Item Counter")
end
if mainWindow.contentsPanel.ResetSession then
  mainWindow.contentsPanel.ResetSession:setText("Reset Session")
end

local function toggleWindow(window)
  if window:isVisible() then
    if window.close then
      window:close()
    else
      window:hide()
    end
  else
    if window.open then
      window:open()
    else
      window:show()
    end
  end
  if window == xpWindow then saveAnalyzerWindowLayout("xp", window) end
  if window == skillWindow then saveAnalyzerWindowLayout("skill", window) end
  if window == statsWindow then saveAnalyzerWindowLayout("stats", window) end
  if window == itemCounterWindow then saveAnalyzerWindowLayout("itemCounter", window) end
end

local function toggleMainWindow()
  if mainWindow:isVisible() then
    if analyzerButton then analyzerButton:setOn(false) end
    mainWindow:close()
  else
    if analyzerButton then analyzerButton:setOn(true) end
    mainWindow:open()
  end
  saveAnalyzerWindowLayout("main", mainWindow)
end

local okButton, existingButton = pcall(function()
  local panel = modules.game_buttons.buttonsWindow.contentsPanel
  return panel and panel.buttons and panel.buttons.botAnalyzersButton
end)

analyzerButton = okButton and existingButton or nil
analyzerButton = analyzerButton or modules.client_topmenu.getButton("botAnalyzersButton")
if analyzerButton then
  analyzerButton:destroy()
end

analyzerButton = modules.client_topmenu.addRightGameToggleButton("botAnalyzersButton", "vBot Analyzers", "/images/topbuttons/analyzers", toggleMainWindow, false, 999999)
analyzerButton:setOn(false)

mainWindow.onClose = function()
  if analyzerButton then analyzerButton:setOn(false) end
  saveAnalyzerWindowLayout("main", mainWindow)
end

if mainWindow.contentsPanel.XPAnalyzer then
  mainWindow.contentsPanel.XPAnalyzer.onClick = function()
    toggleWindow(xpWindow)
  end
end

if mainWindow.contentsPanel.SkillAnalyzer then
  mainWindow.contentsPanel.SkillAnalyzer.onClick = function()
    toggleWindow(skillWindow)
  end
end

if mainWindow.contentsPanel.Stats then
  mainWindow.contentsPanel.Stats.onClick = function()
    toggleWindow(statsWindow)
  end
end

if mainWindow.contentsPanel.ItemCounter then
  mainWindow.contentsPanel.ItemCounter.onClick = function()
    toggleWindow(itemCounterWindow)
  end
end

restoreAnalyzerWindowLayouts(trackedAnalyzerWindows, true)
if analyzerButton then analyzerButton:setOn(mainWindow:isVisible()) end

for _, delayMs in ipairs({150, 500, 1000}) do
  schedule(delayMs, function()
    restoreAnalyzerWindowLayouts(trackedAnalyzerWindows, false)
    if analyzerButton then analyzerButton:setOn(mainWindow:isVisible()) end
  end)
end

macro(1000, function()
  if restoringLayout then return end
  for _, tracked in ipairs(trackedAnalyzerWindows) do
    saveAnalyzerWindowLayout(tracked.key, tracked.window)
  end
end)

local function clamp(value, minValue, maxValue)
  value = tonumber(value) or minValue
  if value < minValue then return minValue end
  if value > maxValue then return maxValue end
  return value
end

local function parseNumber(text)
  local value = tostring(text or ""):gsub("[^%d%-]", "")
  return tonumber(value)
end

local function formatNumber(value)
  value = math.floor(tonumber(value) or 0)
  local sign = value < 0 and "-" or ""
  local str = tostring(math.abs(value))
  local left, num, right = string.match(str, "^([^%d]*%d)(%d*)(.-)$")
  if not left then return sign .. str end
  return sign .. left .. (num:reverse():gsub("(%d%d%d)", "%1,"):reverse()) .. right
end

local function formatDuration(seconds)
  seconds = math.max(0, math.floor(tonumber(seconds) or 0))
  local days = math.floor(seconds / 86400)
  local hours = math.floor(seconds / 3600)
  local minutes = math.floor((seconds % 3600) / 60)
  local secs = seconds % 60

  if days > 0 then
    return string.format("%dd %02dh", days, hours % 24)
  end
  if hours > 0 then
    return string.format("%02dh %02dm", hours, minutes)
  end
  return string.format("%02dm %02ds", minutes, secs)
end

local function avg(values)
  local total = 0
  local count = 0
  for _, value in ipairs(values or {}) do
    total = total + (tonumber(value) or 0)
    count = count + 1
  end
  if count == 0 then return 0 end
  return total / count
end

local function trimData(values, limit)
  limit = limit or CAVEBOT_DATA_LIMIT
  while values and #values > limit do
    table.remove(values, 1)
  end
end

local function level()
  if type(lvl) == "function" then
    return tonumber(lvl()) or 1
  end
  return 1
end

local function expForLevel(levelValue)
  levelValue = math.max(1, tonumber(levelValue) or 1)
  return math.floor((50 * levelValue * levelValue * levelValue) / 3 - 100 * levelValue * levelValue + (850 * levelValue) / 3 - 200)
end

local function levelPercent()
  local readers = {
    function() return player:getLevelPercent() end,
    function() return g_game.getLocalPlayer():getLevelPercent() end,
    function() return modules.game_skills.skillsWindow.contentsPanel.level.percent:getPercent() end,
    function() return parseNumber(modules.game_skills.skillsWindow.contentsPanel.level.percent:getText()) end
  }

  for _, reader in ipairs(readers) do
    local ok, result = pcall(reader)
    if ok and tonumber(result) then
      return clamp(result, 0, 100)
    end
  end

  return 0
end

local function experienceFromSkillWindow()
  local paths = {
    function() return modules.game_skills.skillsWindow.contentsPanel.experience.value:getText() end,
    function() return modules.game_skills.skillsWindow.contentsPanel.exp.value:getText() end,
    function() return modules.game_skills.skillsWindow.contentsPanel.Experience.value:getText() end,
    function() return modules.game_skills.skillsWindow.contentsPanel.experience:getText() end
  }

  for _, reader in ipairs(paths) do
    local ok, text = pcall(reader)
    local value = ok and parseNumber(text)
    if value and value > 0 then
      return value
    end
  end
end

local function rawExperience()
  local readers = {
    function() return exp() end,
    function() return player:getExperience() end,
    function() return g_game.getLocalPlayer():getExperience() end,
    experienceFromSkillWindow
  }

  for _, reader in ipairs(readers) do
    local ok, value = pcall(reader)
    value = ok and tonumber(value)
    if value and value > 0 then
      return value
    end
  end
  return 0
end

local function estimatedExperience()
  local currentLevel = level()
  local baseExp = expForLevel(currentLevel)
  local nextExp = expForLevel(currentLevel + 1)
  local percent = levelPercent()
  return math.floor(baseExp + ((nextExp - baseExp) * percent / 100))
end

local function currentExperience()
  local currentLevel = level()
  local baseExp = expForLevel(currentLevel)
  local nextExp = expForLevel(currentLevel + 1)
  local raw = rawExperience()

  if raw >= baseExp and raw <= nextExp then
    return raw
  end

  return estimatedExperience()
end

local function expGained()
  return math.max(0, currentExperience() - startExp)
end

local function pushExpSample()
  table.insert(expHistory, {time = now, exp = currentExperience()})
  trimData(expHistory, XP_HISTORY_LIMIT)
end

local function expPerHour(raw)
  if #expHistory < 2 then
    return raw and 0 or "-"
  end

  local first = expHistory[1]
  local last = expHistory[#expHistory]
  local elapsed = math.max(1000, (last.time or now) - (first.time or now))
  local gained = math.max(0, (last.exp or 0) - (first.exp or 0))
  local value = math.floor(gained * 3600000 / elapsed)

  if raw then return value end
  return formatNumber(value)
end

local function expLeft()
  return math.max(0, expForLevel(level() + 1) - currentExperience())
end

local function timeToLevel()
  local perHour = expPerHour(true)
  if not perHour or perHour <= 0 then
    return "-"
  end
  return formatDuration(math.ceil(expLeft() / perHour * 3600))
end

local function drawGraph(graph, value)
  if graph and graph.addValue then
    graph:addValue(tonumber(value) or 0)
  end
end

local skillOptions = {
  {name = "Fist", id = 0},
  {name = "Club", id = 1},
  {name = "Sword", id = 2},
  {name = "Axe", id = 3},
  {name = "Distance", id = 4},
  {name = "Shielding", id = 5},
  {name = "Fishing", id = 6}
}

local function getSkillOption(name)
  for _, option in ipairs(skillOptions) do
    if option.name == name then return option end
  end
  return skillOptions[5]
end

local function readFirstNumber(readers, fallback)
  for _, reader in ipairs(readers) do
    local ok, value = pcall(reader)
    value = ok and tonumber(value)
    if value then return value end
  end
  return fallback or 0
end

local function currentSkillSnapshot()
  local option = getSkillOption(skillConfig.skillName)
  local level = 0
  local percent = 0

  level = readFirstNumber({
    function() return player:getSkillLevel(option.id) end,
    function() return g_game.getLocalPlayer():getSkillLevel(option.id) end
  }, 0)
  percent = readFirstNumber({
    function() return player:getSkillLevelPercent(option.id) end,
    function() return g_game.getLocalPlayer():getSkillLevelPercent(option.id) end
  }, 0)

  percent = clamp(percent, 0, 100)
  return {
    name = option.name,
    level = level,
    percent = percent,
    progress = (level * 100) + percent
  }
end

local function currentMagicSnapshot()
  local level = readFirstNumber({
    function() return player:getMagicLevel() end,
    function() return g_game.getLocalPlayer():getMagicLevel() end
  }, 0)
  local percent = readFirstNumber({
    function() return player:getMagicLevelPercent() end,
    function() return g_game.getLocalPlayer():getMagicLevelPercent() end
  }, 0)

  percent = clamp(percent, 0, 100)
  return {
    name = "Magic Level",
    level = level,
    percent = percent,
    progress = (level * 100) + percent
  }
end

local function resetSkillAnalyzerSession()
  local snapshot = currentSkillSnapshot()
  skillHistory = {}
  startSkillName = snapshot.name
  startSkillProgress = snapshot.progress
  table.insert(skillHistory, {time = now, progress = snapshot.progress})
end

local function resetMagicAnalyzerSession()
  local snapshot = currentMagicSnapshot()
  magicHistory = {}
  startMagicProgress = snapshot.progress
  table.insert(magicHistory, {time = now, progress = snapshot.progress})
end

local function pushSkillSample()
  local snapshot = currentSkillSnapshot()
  if snapshot.name ~= startSkillName then
    resetSkillAnalyzerSession()
    return
  end

  table.insert(skillHistory, {time = now, progress = snapshot.progress})
  trimData(skillHistory, SKILL_HISTORY_LIMIT)
end

local function pushMagicSample()
  local snapshot = currentMagicSnapshot()
  table.insert(magicHistory, {time = now, progress = snapshot.progress})
  trimData(magicHistory, SKILL_HISTORY_LIMIT)
end

local function skillPercentPerHour(raw)
  if #skillHistory < 2 then
    return raw and 0 or "-"
  end

  local first = skillHistory[1]
  local last = skillHistory[#skillHistory]
  local elapsed = math.max(1000, (last.time or now) - (first.time or now))
  local gained = math.max(0, (last.progress or 0) - (first.progress or 0))
  local value = gained * 3600000 / elapsed

  if raw then return value end
  return string.format("%.2f%%/h", value)
end

local function magicPercentPerHour()
  if #magicHistory < 2 then
    return 0
  end

  local first = magicHistory[1]
  local last = magicHistory[#magicHistory]
  local elapsed = math.max(1000, (last.time or now) - (first.time or now))
  local gained = math.max(0, (last.progress or 0) - (first.progress or 0))
  return gained * 3600000 / elapsed
end

local function skillTimeToNext()
  local snapshot = currentSkillSnapshot()
  local perHour = skillPercentPerHour(true)
  if not perHour or perHour <= 0 then
    return "-"
  end

  local left = math.max(0, 100 - snapshot.percent)
  return formatDuration(math.ceil(left / perHour * 3600))
end

local function magicTimeToNext()
  local snapshot = currentMagicSnapshot()
  local perHour = magicPercentPerHour()
  if not perHour or perHour <= 0 then
    return "-"
  end

  local left = math.max(0, 100 - snapshot.percent)
  return formatDuration(math.ceil(left / perHour * 3600))
end

local function skillSampleTime()
  if #skillHistory < 2 then return "00m 00s" end
  return formatDuration(((skillHistory[#skillHistory].time or now) - (skillHistory[1].time or now)) / 1000)
end

local xpGainLabel = UI.DualLabel("XP Gain:", "0", {}, xpWindow.contentsPanel).right
local xpHourLabel = UI.DualLabel("XP/h:", "0", {}, xpWindow.contentsPanel).right
local nextLevelLabel = UI.DualLabel("Next Level:", "-", {}, xpWindow.contentsPanel).right
local progressBar = UI.createWidget("AnalyzerProgressBar", xpWindow.contentsPanel)
progressBar:setPercent(levelPercent())
UI.Separator(xpWindow.contentsPanel)
local xpGraph = UI.createWidget("AnalyzerGraph", xpWindow.contentsPanel)
xpGraph:setTitle("XP/h")
drawGraph(xpGraph, 0)

local totalRoundsLabel = UI.DualLabel("Rounds:", "0", {}, statsWindow.contentsPanel).right
local avgRoundLabel = UI.DualLabel("Avg Round:", "00m 00s", {}, statsWindow.contentsPanel).right
local totalRefillsLabel = UI.DualLabel("Refills:", "0", {}, statsWindow.contentsPanel).right
local avgRefillLabel = UI.DualLabel("Avg Refill:", "00m 00s", {}, statsWindow.contentsPanel).right
local lastRefillLabel = UI.DualLabel("Last Refill:", "00m 00s", {}, statsWindow.contentsPanel).right

UI.Separator(statsWindow.contentsPanel)
local supplyStatsTitle = UI.Label("Supplies:", statsWindow.contentsPanel)
supplyStatsTitle:setFont("verdana-11px-rounded")
supplyStatsTitle:setColor("#9dd1ce")
local supplyStatsHeader = UI.createWidget("AnalyzerSupplyHeader", statsWindow.contentsPanel)
local supplyStatsEmpty = UI.Label("No supplies configured", statsWindow.contentsPanel)
supplyStatsEmpty:setFont("verdana-11px-rounded")
supplyStatsEmpty:setColor("#cfd3d7")
local supplyStatRows = {}
local registeredSupplyStatItems = {}

local function getSupplyStatsItems()
  local items = {}
  if not Supplies or not Supplies.getItemsData then
    return items
  end

  local ok, data = pcall(Supplies.getItemsData)
  if not ok or type(data) ~= "table" then
    return items
  end

  for id, values in pairs(data) do
    local numericId = tonumber(id)
    if numericId and numericId > 100 and type(values) == "table" then
      if vBot.ItemCounter and not registeredSupplyStatItems[numericId] then
        if vBot.ItemCounter.registerSupplyItem then
          vBot.ItemCounter.registerSupplyItem(numericId, values)
        elseif vBot.ItemCounter.registerItemId then
          vBot.ItemCounter.registerItemId(numericId)
        end
        registeredSupplyStatItems[numericId] = true
      end

      local name = tostring(numericId)
      local used = 0
      if vBot.ItemCounter then
        if vBot.ItemCounter.getName then
          name = vBot.ItemCounter.getName(numericId)
        end
        if vBot.ItemCounter.getUsed then
          used = vBot.ItemCounter.getUsed(numericId)
        end
      end

      table.insert(items, {
        id = numericId,
        name = name,
        current = tonumber(itemAmount(numericId)) or 0,
        used = used
      })
    end
  end

  table.sort(items, function(a, b)
    return tostring(a.name):lower() < tostring(b.name):lower()
  end)
  return items
end

local function resetSupplyUsageStats()
  if not vBot.ItemCounter or not vBot.ItemCounter.resetUsed then return end

  for _, item in ipairs(getSupplyStatsItems()) do
    vBot.ItemCounter.resetUsed(item.id)
  end
end

local function updateSupplyStatsRows()
  local items = getSupplyStatsItems()
  local visibleRows = {}

  supplyStatsEmpty:setVisible(#items == 0)

  for _, item in ipairs(items) do
    local key = tostring(item.id)
    visibleRows[key] = true

    if not supplyStatRows[key] then
      if vBot.ItemCounter and vBot.ItemCounter.resetUsed then
        vBot.ItemCounter.resetUsed(item.id)
        item.used = 0
      end
      local row = UI.createWidget("AnalyzerSupplyRow", statsWindow.contentsPanel)
      row.item:setItemId(item.id)
      if row.item.setShowCount then
        row.item:setShowCount(false)
      end
      supplyStatRows[key] = row
    end

    local row = supplyStatRows[key]
    row.item:setItemId(item.id)
    row.item:setTooltip(item.name)
    row.current:setText(formatNumber(item.current))
    row.used:setText(formatNumber(item.used))
  end

  for key, row in pairs(supplyStatRows) do
    if not visibleRows[key] then
      row:destroy()
      supplyStatRows[key] = nil
    end
  end

  supplyStatsHeader:setVisible(#items > 0)
end

local itemCounterRows = {}
local itemCounterSignature = ""

local function firstItemCounterAlias(text)
  text = tostring(text or "")
  local alias = text:match("([^,;]+)") or ""
  alias = alias:gsub("^%s+", ""):gsub("%s+$", "")
  return alias
end

local function getItemCounterName(entry)
  local alias = firstItemCounterAlias(entry.alias)
  if alias ~= "" then return alias end

  local id = tonumber(entry.id)
  local saved = storage.itemCounter and storage.itemCounter.items and storage.itemCounter.items[tostring(id)]
  if saved and saved.name and saved.name ~= "" then
    return saved.name
  end
  return tostring(id or "-")
end

local function getItemCounterAmount(entry)
  local id = tonumber(entry.id)
  if not id or id <= 100 then return 0 end
  if itemAmount then return tonumber(itemAmount(id)) or 0 end
  if vBot.ItemCounter and vBot.ItemCounter.get then
    return tonumber(vBot.ItemCounter.get(id)) or 0
  end
  return 0
end

local function getItemCounterEntries()
  local source = {}
  if vBot.ItemCounter and vBot.ItemCounter.getWatchItems then
    source = vBot.ItemCounter.getWatchItems()
  elseif storage.itemCounter and type(storage.itemCounter.watch) == "table" then
    source = storage.itemCounter.watch
  end

  local entries = {}
  for _, entry in ipairs(source) do
    if type(entry) == "table" and tonumber(entry.id) and tonumber(entry.id) > 100 then
      table.insert(entries, entry)
    end
  end
  return entries
end

local function refreshItemCounterRows(force)
  local entries = getItemCounterEntries()
  local signatureParts = {}
  for _, entry in ipairs(entries) do
    table.insert(signatureParts, tostring(entry.id) .. "|" .. tostring(entry.alias or ""))
  end
  local signature = table.concat(signatureParts, ";")
  if not force and signature == itemCounterSignature then return end

  itemCounterSignature = signature
  itemCounterWindow.contentsPanel:destroyChildren()
  itemCounterRows = {}

  local setupButton = UI.createWidget("AnalyzerButton", itemCounterWindow.contentsPanel)
  setupButton:setText("Setup Items")
  setupButton:setColor("#9dd1ce")
  setupButton.onClick = function()
    if vBot.ItemCounter and vBot.ItemCounter.openSetup then
      vBot.ItemCounter.openSetup()
    end
  end

  if #entries == 0 then
    UI.Label("No items configured.", itemCounterWindow.contentsPanel)
    return
  end

  UI.Separator(itemCounterWindow.contentsPanel)
  for _, entry in ipairs(entries) do
    local row = UI.createWidget("AnalyzerItemCounterRow", itemCounterWindow.contentsPanel)
    row.item:setShowCount(false)
    row.item:setItemId(tonumber(entry.id) or 0)
    row.name:setText(getItemCounterName(entry))
    table.insert(itemCounterRows, {widget = row, entry = entry})
  end
end

local function updateItemCounterRows()
  refreshItemCounterRows(false)
  for _, row in ipairs(itemCounterRows) do
    local amount = getItemCounterAmount(row.entry)
    row.widget.count:setText(formatNumber(amount))
    row.widget.count:setColor(amount > 0 and "#9dff9d" or "#ff8888")
  end
end

refreshItemCounterRows(true)

local magicCurrentLabel = UI.DualLabel("Magic:", "-", {}, skillWindow.contentsPanel).right
local magicProgressLabel = UI.DualLabel("ML Progress:", "-", {}, skillWindow.contentsPanel).right
local magicNextLabel = UI.DualLabel("ML Next:", "-", {}, skillWindow.contentsPanel).right
UI.Separator(skillWindow.contentsPanel)
local skillCurrentLabel = UI.DualLabel("Current:", "-", {}, skillWindow.contentsPanel).right
local skillProgressLabel = UI.DualLabel("Progress:", "-", {}, skillWindow.contentsPanel).right
local skillNextLabel = UI.DualLabel("Next Skill:", "-", {}, skillWindow.contentsPanel).right
local skillSampleLabel = UI.DualLabel("Sample:", "00m 00s", {}, skillWindow.contentsPanel).right
local skillProgressBar = UI.createWidget("AnalyzerProgressBar", skillWindow.contentsPanel)
skillProgressBar:setPercent(0)

if skillWindow.contentsPanel.skillBox then
  skillWindow.contentsPanel.skillBox:setOption(skillConfig.skillName)
  skillWindow.contentsPanel.skillBox.onOptionChange = function(widget)
    skillConfig.skillName = widget:getCurrentOption().text
    resetSkillAnalyzerSession()
  end
end

if skillWindow.contentsPanel.ResetSkillSession then
  skillWindow.contentsPanel.ResetSkillSession.onClick = function()
    resetSkillAnalyzerSession()
    resetMagicAnalyzerSession()
  end
end

resetAnalyzerSessionData = function()
  launchTime = now
  startExp = currentExperience()
  expHistory = {}
  pushExpSample()

  vBot.CaveBotData.refills = 0
  vBot.CaveBotData.rounds = 0
  vBot.CaveBotData.time = {}
  vBot.CaveBotData.refillTime = {}
  vBot.CaveBotData.lastRefill = os.time()
  resetSupplyUsageStats()

  if xpGraph and xpGraph.clear then
    xpGraph:clear()
    drawGraph(xpGraph, 0)
  end
end

if mainWindow.contentsPanel.ResetSession then
  mainWindow.contentsPanel.ResetSession.onClick = function()
    resetAnalyzerSessionData()
  end
end

startExp = currentExperience()
pushExpSample()
resetSkillAnalyzerSession()
resetMagicAnalyzerSession()

macro(1000, function()
  pushExpSample()
  pushSkillSample()
  pushMagicSample()
  trimData(vBot.CaveBotData.time, CAVEBOT_DATA_LIMIT)
  trimData(vBot.CaveBotData.refillTime, CAVEBOT_DATA_LIMIT)

  xpGainLabel:setText(formatNumber(expGained()))
  xpHourLabel:setText(expPerHour())
  nextLevelLabel:setText(timeToLevel())
  progressBar:setPercent(levelPercent())

  totalRoundsLabel:setText(formatNumber(vBot.CaveBotData.rounds or 0))
  avgRoundLabel:setText(formatDuration(avg(vBot.CaveBotData.time)))
  totalRefillsLabel:setText(formatNumber(vBot.CaveBotData.refills or 0))
  avgRefillLabel:setText(formatDuration(avg(vBot.CaveBotData.refillTime)))
  lastRefillLabel:setText(formatDuration(os.time() - (vBot.CaveBotData.lastRefill or os.time())))
  updateSupplyStatsRows()
  updateItemCounterRows()

  local magicSnapshot = currentMagicSnapshot()
  magicCurrentLabel:setText(tostring(magicSnapshot.level))
  magicProgressLabel:setText(string.format("%.2f%%", magicSnapshot.percent))
  magicNextLabel:setText(magicTimeToNext())

  local skillSnapshot = currentSkillSnapshot()
  skillCurrentLabel:setText(tostring(skillSnapshot.level))
  skillProgressLabel:setText(string.format("%.2f%%", skillSnapshot.percent))
  skillNextLabel:setText(skillTimeToNext())
  skillSampleLabel:setText(skillSampleTime())
  skillProgressBar:setPercent(math.floor(skillSnapshot.percent))
end)

macro(60 * 1000, function()
  drawGraph(xpGraph, expPerHour(true) or 0)
end)

Analyzer.getXpGained = function()
  return expGained()
end

Analyzer.getXpHour = function()
  return expPerHour()
end

Analyzer.getTimeToNextLevel = function()
  return timeToLevel()
end

Analyzer.getCaveBotStats = function()
  return {
    rounds = vBot.CaveBotData.rounds or 0,
    avgRound = avg(vBot.CaveBotData.time),
    refills = vBot.CaveBotData.refills or 0,
    avgRefill = avg(vBot.CaveBotData.refillTime),
    lastRefill = os.time() - (vBot.CaveBotData.lastRefill or os.time()),
    supplies = getSupplyStatsItems()
  }
end

Analyzer.getSkillStats = function()
  local snapshot = currentSkillSnapshot()
  local magicSnapshot = currentMagicSnapshot()
  return {
    name = snapshot.name,
    level = snapshot.level,
    percent = snapshot.percent,
    timeToNext = skillTimeToNext(),
    magic = {
      level = magicSnapshot.level,
      percent = magicSnapshot.percent,
      timeToNext = magicTimeToNext()
    }
  }
end
