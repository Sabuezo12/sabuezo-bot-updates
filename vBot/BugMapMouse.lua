local panelName = "BugMapMouse"
local DEFAULT_HOLD_HOTKEY = "MouseMiddle"
local USE_DELAY = 60

if not storage[panelName] then
  storage[panelName] = {
    enabled = false,
    holdHotkey = DEFAULT_HOLD_HOTKEY
  }
end

local config = storage[panelName]
config.enabled = config.enabled == true
config.holdHotkey = config.holdHotkey or DEFAULT_HOLD_HOTKEY

local lastUse = 0
local holdingMouse = false
local holdingKeyboard = false
local keyboardHoldUntil = 0
local bugMapPanel = nil
local bugMapWindow = nil

local function getTime()
  if now then return now end
  if g_clock and g_clock.millis then return g_clock.millis() end
  return 0
end

local function normalizeHotkey(value)
  return tostring(value or ""):lower():gsub("%s+", ""):gsub("_", ""):gsub("-", "")
end

local function buttonCandidates(kind)
  local buttons = {}

  if kind == "middle" then
    if MouseMiddleButton then table.insert(buttons, MouseMiddleButton) end
    table.insert(buttons, 3)
    table.insert(buttons, 4)
  elseif kind == "left" then
    if MouseLeftButton then table.insert(buttons, MouseLeftButton) end
    table.insert(buttons, 1)
  elseif kind == "right" then
    if MouseRightButton then table.insert(buttons, MouseRightButton) end
    table.insert(buttons, 2)
  end

  return buttons
end

local function containsButton(buttons, mouseButton)
  for _, button in ipairs(buttons) do
    if button == mouseButton then return true end
  end
  return false
end

local function matchesMouseHotkey(mouseButton)
  local hotkey = normalizeHotkey(config.holdHotkey)
  if hotkey == "" then return false end

  if hotkey == "mousemiddle" or hotkey == "middlemouse" or hotkey == "middle" or
    hotkey == "wheel" or hotkey == "mousewheel" or hotkey == "mmb" then
    return containsButton(buttonCandidates("middle"), mouseButton)
  end

  if hotkey == "mouseleft" or hotkey == "leftmouse" or hotkey == "left" or hotkey == "lmb" then
    return containsButton(buttonCandidates("left"), mouseButton)
  end

  if hotkey == "mouseright" or hotkey == "rightmouse" or hotkey == "right" or hotkey == "rmb" then
    return containsButton(buttonCandidates("right"), mouseButton)
  end

  local numericButton = hotkey:match("^mousebutton(%d+)$") or hotkey:match("^mouse(%d+)$") or hotkey:match("^(%d+)$")
  return numericButton and tonumber(numericButton) == mouseButton
end

local function matchesKeyboardHotkey(keys)
  local hotkey = normalizeHotkey(config.holdHotkey)
  if hotkey == "" or hotkey:find("mouse") or hotkey == "middle" or hotkey == "wheel" or
    hotkey == "mmb" or hotkey == "lmb" or hotkey == "rmb" then
    return false
  end
  return normalizeHotkey(keys) == hotkey
end

local function isKeyboardHotkeyPressed()
  if not holdingKeyboard then return false end

  if g_keyboard and g_keyboard.isKeyPressed then
    local ok, pressed = pcall(function()
      return g_keyboard.isKeyPressed(config.holdHotkey)
    end)
    if ok and pressed then return true end
  end

  return getTime() <= keyboardHoldUntil
end

local function setEnabled(enabled)
  config.enabled = enabled == true
  if not config.enabled then
    holdingMouse = false
    holdingKeyboard = false
    keyboardHoldUntil = 0
  end
  if bugMapPanel and bugMapPanel.title then
    bugMapPanel.title:setOn(config.enabled)
  end
end

local function useTile(tile)
  if not tile then return false end

  local playerPos = player and player:getPosition()
  local tilePos = tile:getPosition()
  if not playerPos or not tilePos or playerPos.z ~= tilePos.z then return false end
  if math.max(math.abs(tilePos.x - playerPos.x), math.abs(tilePos.y - playerPos.y)) > 7 then return false end

  local thing = tile:getTopUseThing() or tile:getTopThing() or tile:getGround()
  if not thing then return false end

  local ok = pcall(function()
    if type(use) == "function" then
      use(thing)
    elseif g_game and g_game.use then
      g_game.use(thing)
    end
  end)

  if ok then
    lastUse = getTime()
    return true
  end
  return false
end

local function useMouseTile()
  if not config.enabled then return false end

  local time = getTime()
  if time - lastUse < USE_DELAY then return true end

  local tile = getTileUnderCursor and getTileUnderCursor()
  return useTile(tile)
end

local gameRoot = modules.game_interface and modules.game_interface.gameRootPanel
if gameRoot then
  vBotBugMapMouseOriginalHandlers = vBotBugMapMouseOriginalHandlers or {
    onMousePress = gameRoot.onMousePress,
    onMouseRelease = gameRoot.onMouseRelease
  }
  local previousMousePress = vBotBugMapMouseOriginalHandlers.onMousePress
  local previousMouseRelease = vBotBugMapMouseOriginalHandlers.onMouseRelease

  gameRoot.onMousePress = function(widget, mousePos, mouseButton)
    if config.enabled and matchesMouseHotkey(mouseButton) then
      holdingMouse = true
      useMouseTile()
      return true
    end

    if previousMousePress then
      return previousMousePress(widget, mousePos, mouseButton)
    end
    return false
  end

  gameRoot.onMouseRelease = function(widget, mousePos, mouseButton)
    if matchesMouseHotkey(mouseButton) then
      holdingMouse = false
      return config.enabled == true
    end

    if previousMouseRelease then
      return previousMouseRelease(widget, mousePos, mouseButton)
    end
    return false
  end
end

onKeyDown(function(keys)
  if not config.enabled then return end
  if not matchesKeyboardHotkey(keys) then return end

  holdingKeyboard = true
  keyboardHoldUntil = getTime() + 160
  useMouseTile()
end)

BugMapMouse = {
  isOn = function()
    return config.enabled == true
  end,
  setOn = function()
    setEnabled(true)
  end,
  setOff = function()
    setEnabled(false)
  end,
  toggle = function()
    setEnabled(not config.enabled)
  end
}

setDefaultTab("Main")

bugMapPanel = setupUI([[
Panel
  height: 19

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('BugMap')

  Button
    id: setup
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 17
    text: Setup
]])
bugMapPanel:setId(panelName)
bugMapPanel.title:setOn(config.enabled)
bugMapPanel.title.onClick = function(widget)
  setEnabled(not config.enabled)
end

local rootWidget = g_ui.getRootWidget()
if rootWidget then
  bugMapWindow = UI.createWindow('BugMapMouseWindow', rootWidget)
  bugMapWindow:hide()

  bugMapPanel.setup.onClick = function(widget)
    bugMapWindow:show()
    bugMapWindow:raise()
    bugMapWindow:focus()
  end

  bugMapWindow.closeButton.onClick = function(widget)
    bugMapWindow:hide()
  end

  bugMapWindow.hotkey.onTextChange = function(widget, text)
    config.holdHotkey = text
    holdingMouse = false
    holdingKeyboard = false
    keyboardHoldUntil = 0
  end
  bugMapWindow.hotkey:setText(config.holdHotkey)
end

macro(20, function()
  if not config.enabled then return end

  holdingKeyboard = isKeyboardHotkeyPressed()

  if holdingMouse or holdingKeyboard then
    useMouseTile()
  end
end)
