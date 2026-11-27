-- Astra stores native sidebars under the temporary creature id assigned at
-- login. Keep a stable per-profile copy as well as the Bot/top-bar placement.

vBot = vBot or {}
vBot.LayoutPersistenceGeneration = (vBot.LayoutPersistenceGeneration or 0) + 1
local generation = vBot.LayoutPersistenceGeneration

storage.astraLayout = storage.astraLayout or {}
local layout = storage.astraLayout
local startedAt = (g_clock and g_clock.millis and g_clock.millis()) or 0
local captureAfter = startedAt + 6000

local function clockMillis()
  if type(now) == "number" then return now end
  if g_clock and g_clock.millis then
    local ok, value = pcall(function() return g_clock.millis() end)
    if ok and type(value) == "number" then return value end
  end
  return os.time() * 1000
end

local function validWidget(widget)
  if not widget then return false end
  if not widget.isDestroyed then return true end
  local ok, destroyed = pcall(function() return widget:isDestroyed() end)
  return ok and not destroyed
end

local function widgetId(widget)
  if not validWidget(widget) or not widget.getId then return "" end
  local ok, id = pcall(function() return widget:getId() end)
  return ok and tostring(id or "") or ""
end

local function childIndex(parent, child)
  if not validWidget(parent) or not parent.getChildren then return nil end
  local ok, children = pcall(function() return parent:getChildren() end)
  if not ok or type(children) ~= "table" then return nil end
  for index, candidate in ipairs(children) do
    if candidate == child then return index end
  end
  return nil
end

local function getBotWindow()
  local gameBot = modules and modules.game_bot
  local window = gameBot and gameBot.botWindow or nil
  if validWidget(window) then return window end

  local root = g_ui and g_ui.getRootWidget and g_ui.getRootWidget() or nil
  if root and root.recursiveGetChildById then
    local ok, result = pcall(function() return root:recursiveGetChildById("botWindow") end)
    if ok and validWidget(result) then return result end
  end
  return nil
end

local function captureBotLayout()
  local window = getBotWindow()
  if not window or not window.getParent then return false end

  local okParent, parent = pcall(function() return window:getParent() end)
  if not okParent or not validWidget(parent) then return false end
  local container = parent.getParent and parent:getParent() or nil

  local saved = layout.bot or {}
  saved.parentId = widgetId(parent)
  saved.containerId = widgetId(container)
  saved.panelIndex = childIndex(container, parent)
  saved.windowIndex = childIndex(parent, window)
  if window.getHeight then
    local ok, height = pcall(function() return window:getHeight() end)
    if ok and tonumber(height) then saved.height = tonumber(height) end
  end
  if window.isMinimized then
    local ok, minimized = pcall(function() return window:isMinimized() end)
    if ok then saved.minimized = minimized == true end
  end
  layout.bot = saved
  return true
end

local function findSavedPanel()
  local saved = layout.bot
  if type(saved) ~= "table" then return nil end
  local root = g_ui and g_ui.getRootWidget and g_ui.getRootWidget() or nil
  if not root then return nil end

  if saved.containerId and saved.containerId ~= "" and saved.panelIndex and
     root.recursiveGetChildById then
    local ok, container = pcall(function()
      return root:recursiveGetChildById(saved.containerId)
    end)
    if ok and validWidget(container) and container.getChildByIndex then
      local okPanel, panel = pcall(function()
        return container:getChildByIndex(tonumber(saved.panelIndex))
      end)
      if okPanel and validWidget(panel) and
         (saved.parentId == "" or widgetId(panel) == saved.parentId) then
        return panel
      end
    end
  end

  if saved.parentId and saved.parentId ~= "" and root.recursiveGetChildById then
    local ok, panel = pcall(function()
      return root:recursiveGetChildById(saved.parentId)
    end)
    if ok and validWidget(panel) then return panel end
  end
  return nil
end

local function restoreBotLayout(window)
  window = window or getBotWindow()
  local saved = layout.bot
  local panel = findSavedPanel()
  if not window or not panel or type(saved) ~= "table" then return false end

  local ok = pcall(function()
    if window:getParent() ~= panel then window:setParent(panel, true) end
    if saved.windowIndex and panel.moveChildToIndex then
      panel:moveChildToIndex(window, math.max(1, tonumber(saved.windowIndex) or 1))
    end
    if saved.height and window.setHeight then window:setHeight(saved.height) end
    if saved.minimized == true and window.minimize then
      window:minimize()
    elseif saved.minimized == false and window.maximize then
      window:maximize()
    end
    window:show()
  end)
  return ok
end

local nativeLayout = {
  currentPath = nil,
  stablePath = nil,
  restoring = false,
}

local function currentConfigName()
  local gameBot = modules and modules.game_bot
  local contents = gameBot and gameBot.contentsPanel or nil
  local config = contents and contents.config or nil
  if config and config.getCurrentOption then
    local ok, option = pcall(function() return config:getCurrentOption() end)
    if ok and option and option.text and tostring(option.text) ~= "" then
      return tostring(option.text)
    end
  end

  local player = g_game and g_game.getLocalPlayer and g_game.getLocalPlayer() or nil
  return player and player.getName and tostring(player:getName()) or nil
end

local function ensureDirectory(path)
  if not g_resources or not g_resources.directoryExists or
     not g_resources.makeDir then return false end
  local ok, exists = pcall(function() return g_resources.directoryExists(path) end)
  if ok and exists then return true end
  return pcall(function() g_resources.makeDir(path) end)
end

local function readResource(path)
  if not path or not g_resources or not g_resources.fileExists or
     not g_resources.readFileContents then return nil end
  local existsOk, exists = pcall(function() return g_resources.fileExists(path) end)
  if not existsOk or not exists then return nil end
  local readOk, contents = pcall(function() return g_resources.readFileContents(path) end)
  if not readOk or type(contents) ~= "string" or contents == "" then return nil end
  return contents
end

local function decodeSidebarConfig(contents)
  if type(contents) ~= "string" or not json or type(json.decode) ~= "function" then
    return nil
  end
  local ok, decoded = pcall(function() return json.decode(contents) end)
  if not ok or type(decoded) ~= "table" then return nil end
  local manager = decoded.sidebarWidgetsMangerOptions
  if type(manager) ~= "table" or type(manager.openWidgetsOrderPerSidebar) ~= "table" then
    return nil
  end
  return decoded
end

local function prepareNativeLayoutPaths()
  if nativeLayout.currentPath and nativeLayout.stablePath then return true end
  local player = g_game and g_game.getLocalPlayer and g_game.getLocalPlayer() or nil
  local playerId = player and player.getId and tonumber(player:getId()) or nil
  local configName = currentConfigName()
  if not playerId or not configName or configName == "" then return false end

  local currentDir = "/characterdata/" .. tostring(playerId)
  local stableDir = "/bot/" .. configName .. "/layout"
  if not ensureDirectory(currentDir) or not ensureDirectory(stableDir) then return false end

  nativeLayout.currentPath = currentDir .. "/sidebars.json"
  nativeLayout.stablePath = stableDir .. "/sidebars.json"
  return true
end

local function saveNativeLayoutSnapshot()
  if nativeLayout.restoring or not prepareNativeLayoutPaths() then return false end
  local contents = readResource(nativeLayout.currentPath)
  if not decodeSidebarConfig(contents) then return false end
  if readResource(nativeLayout.stablePath) == contents then return true end
  local ok = pcall(function()
    g_resources.writeFileContents(nativeLayout.stablePath, contents)
  end)
  return ok
end

local function moveBotOutOfSidebars()
  local window = getBotWindow()
  local root = g_ui and g_ui.getRootWidget and g_ui.getRootWidget() or nil
  if not window or not root or not window.setParent then return end
  if type(layout.bot) ~= "table" or not layout.bot.parentId then
    captureBotLayout()
  end
  pcall(function()
    if window:getParent() ~= root then window:setParent(root, true) end
  end)
end

local function restoreNativeLayoutSnapshot()
  if nativeLayout.restoring or not prepareNativeLayoutPaths() then return false end
  local contents = readResource(nativeLayout.stablePath)
  local config = decodeSidebarConfig(contents)
  if not config then
    saveNativeLayoutSnapshot()
    return false
  end

  -- If Astra already loaded this exact file, avoid rebuilding live panels.
  if readResource(nativeLayout.currentPath) == contents then return true end

  nativeLayout.restoring = true
  local writeOk = pcall(function()
    g_resources.writeFileContents(nativeLayout.currentPath, contents)
  end)
  if not writeOk then
    nativeLayout.restoring = false
    return false
  end

  -- game_interface closes non-native widgets while rebuilding sidebars.
  moveBotOutOfSidebars()
  local sidebars = modules and modules.game_sidebars
  local interface = modules and modules.game_interface
  local loaded = sidebars and type(sidebars.loadConfigJson) == "function" and
    pcall(sidebars.loadConfigJson)
  local applied = interface and type(interface.onPlayerLoad) == "function" and
    pcall(interface.onPlayerLoad, config.sidebarWidgetsMangerOptions)
  nativeLayout.restoring = false

  if loaded and applied then
    for _, delay in ipairs({100, 350, 900, 1800}) do
      schedule(delay, function()
        if generation == vBot.LayoutPersistenceGeneration then restoreBotLayout() end
      end)
    end
    return true
  end
  return false
end

local function installNativeLayoutSaveHook()
  local sidebars = modules and modules.game_sidebars
  if not sidebars or type(sidebars.saveConfigJson) ~= "function" then return end

  local oldHook = sidebars._sabuezoStableLayoutHook
  if type(oldHook) == "table" and sidebars.saveConfigJson == oldHook.wrapper and
     type(oldHook.original) == "function" then
    sidebars.saveConfigJson = oldHook.original
  end

  local original = sidebars.saveConfigJson
  local wrapper = function(...)
    local result = original(...)
    if generation == vBot.LayoutPersistenceGeneration then
      saveNativeLayoutSnapshot()
    end
    return result
  end
  sidebars._sabuezoStableLayoutHook = {original = original, wrapper = wrapper}
  sidebars.saveConfigJson = wrapper
end

local function installBotPlacementHook()
  local interface = modules and modules.game_interface
  if not interface or type(interface.addToPanelsWithPriority) ~= "function" then
    return
  end

  local oldHook = interface._sabuezoLayoutHook
  if type(oldHook) == "table" and
     interface.addToPanelsWithPriority == oldHook.wrapper and
     type(oldHook.original) == "function" then
    interface.addToPanelsWithPriority = oldHook.original
  end

  local original = interface.addToPanelsWithPriority
  local wrapper = function(widget, forcePriority)
    if generation == vBot.LayoutPersistenceGeneration and
       widgetId(widget) == "botWindow" and restoreBotLayout(widget) then
      return true
    end
    return original(widget, forcePriority)
  end
  interface._sabuezoLayoutHook = {original = original, wrapper = wrapper}
  interface.addToPanelsWithPriority = wrapper
end

local topBarSaveEvent = nil
local function flushTopBarLayout()
  topBarSaveEvent = nil
  if generation ~= vBot.LayoutPersistenceGeneration then return end
  local topBar = modules and modules.game_topbar
  if not topBar or type(topBar.offline) ~= "function" then return end
  if g_game and g_game.isOnline and not g_game.isOnline() then return end
  pcall(topBar.offline)
end

local function saveTopBarSoon()
  if topBarSaveEvent and removeEvent then pcall(removeEvent, topBarSaveEvent) end
  local delay = math.max(350, captureAfter - clockMillis())
  topBarSaveEvent = schedule(delay, flushTopBarLayout)
end

local function installTopBarHooks()
  local topBar = modules and modules.game_topbar
  if not topBar then return end

  local previous = topBar._sabuezoLayoutHooks
  if type(previous) == "table" then
    for name, hook in pairs(previous) do
      if type(hook) == "table" and topBar[name] == hook.wrapper then
        topBar[name] = hook.original
      end
    end
  end

  local hooks = {}
  for _, name in ipairs({"setupTopBar", "toggleSkillPanel"}) do
    local original = topBar[name]
    if type(original) == "function" then
      local wrapper = function(...)
        local result = original(...)
        saveTopBarSoon()
        return result
      end
      hooks[name] = {original = original, wrapper = wrapper}
      topBar[name] = wrapper
    end
  end
  topBar._sabuezoLayoutHooks = hooks
end

installBotPlacementHook()
installTopBarHooks()
installNativeLayoutSaveHook()
restoreNativeLayoutSnapshot()

for _, delay in ipairs({50, 250, 750, 1500, 3000, 5000}) do
  schedule(delay, function()
    if generation == vBot.LayoutPersistenceGeneration then restoreBotLayout() end
  end)
end

schedule(6500, saveTopBarSoon)

macro(1000, function()
  if generation ~= vBot.LayoutPersistenceGeneration then return end
  if clockMillis() >= captureAfter then captureBotLayout() end
end)
