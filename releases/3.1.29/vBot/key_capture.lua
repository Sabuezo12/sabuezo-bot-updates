-- KeyCapture: pick a hotkey by PRESSING it instead of typing its name.
--
-- Bind it to a text field the module already has: the field stops being typeable; a click starts the
-- capture ("Pulsa una tecla...") and the next key press becomes the field's text. The stored text is exactly
-- what the client reports in onKeyDown(keys) ("PageUp", "Numpad0", "Ctrl+F9", ...), which is what every module
-- already compares against, so the modules keep their own onTextChange logic untouched.
--
--   KeyCapture.bind(widget, {allowMouse = true, allowClear = true, set = function(text) end})
--   KeyCapture.unbind(widget)   -- the field becomes a normal text field again
--   KeyCapture.active()         -- true while a capture runs (and for a moment after): modules with their
--                               -- own onKeyDown must ignore keys then, or the key being chosen would act
--
-- Escape cancels. A modifier alone (Ctrl, Shift, Alt) is not a key: it waits for the real one.
KeyCapture = KeyCapture or {}
local K = KeyCapture

local CAPTURE_TIMEOUT_MS = 10000
local GRACE_MS = 250
local current = nil -- {widget, startedAt, previous, color}
local lastEndedAt = -math.huge

local function clock()
  return tonumber(now) or os.time() * 1000
end

local MODIFIERS = {ctrl = true, control = true, shift = true, alt = true, meta = true, cmd = true, win = true}
-- "Ctrl", "Ctrl+Shift"... A trailing "+" is the plus key itself ("Ctrl++").
function K.isModifierOnly(keys)
  keys = tostring(keys or "")
  if keys == "" then return true end
  if keys:sub(-1) == "+" then return false end
  for part in keys:gmatch("[^%+]+") do
    if not MODIFIERS[part:lower()] then return false end
  end
  return true
end

-- Name stored for a mouse button (BugMapMouse understands these).
function K.mouseName(button)
  button = tonumber(button) or 0
  if button == (tonumber(MouseMiddleButton) or 3) then return "MouseMiddle" end
  return "MouseButton" .. button
end

local function call(widget, method, ...)
  if not widget or type(widget[method]) ~= "function" then return nil end
  local ok, value = pcall(widget[method], widget, ...)
  if ok then return value end
  return nil
end

-- Change the text without waking the module's onTextChange (the placeholder is not a value).
local function setSilently(widget, text)
  local handler = widget.onTextChange
  widget.onTextChange = nil
  pcall(widget.setText, widget, text)
  widget.onTextChange = handler
end

local function alive(widget)
  if not widget then return false end
  local ok, visible = pcall(function() return widget:isVisible() end)
  return ok and visible ~= false
end

local function placeholder(widget)
  local width = tonumber(call(widget, "getWidth")) or 200
  return width < 110 and "Pulsa..." or "Pulsa una tecla..."
end

local function restoreLook(state)
  call(state.widget, "setColor", state.color or "#e4edf3")
end

local function cancel()
  local state = current
  if not state then return end
  current = nil
  lastEndedAt = clock()
  if state.widget then
    setSilently(state.widget, state.previous)
    restoreLook(state)
  end
end

local function finish(widget, text)
  local state = current
  current = nil
  lastEndedAt = clock()
  if state then restoreLook(state) end
  local spec = widget._keyCapture or {}
  -- A normal setText: the module's onTextChange stores the new key.
  pcall(widget.setText, widget, text)
  if type(spec.set) == "function" then pcall(spec.set, text) end
end

local function start(widget)
  if current then
    local again = current.widget == widget
    cancel()
    if again then return end
  end
  local color = call(widget, "getColor")
  current = {widget = widget, startedAt = clock(), previous = tostring(call(widget, "getText") or ""), color = color}
  setSilently(widget, placeholder(widget))
  call(widget, "setColor", "#f0b55b")
  local started = current.startedAt
  if type(schedule) == "function" then
    schedule(CAPTURE_TIMEOUT_MS + 50, function()
      if current and current.startedAt == started then cancel() end
    end)
  end
end

function K.active()
  if current then return true end
  return clock() - lastEndedAt < GRACE_MS
end

-- Abort a running capture and put the previous text back (used before reading the field's text).
function K.cancel()
  cancel()
end

function K.isCapturing(widget)
  return current ~= nil and current.widget == widget
end

function K.bind(widget, spec)
  if not widget then return nil end
  spec = type(spec) == "table" and spec or {}
  if widget._keyCapture then K.unbind(widget) end
  widget._keyCapture = spec
  spec.previousMousePress = widget.onMousePress
  call(widget, "setEditable", false)
  widget.onMousePress = function(w, _, button)
    local left = tonumber(MouseLeftButton) or 1
    local right = tonumber(MouseRightButton) or 2
    if current and current.widget == w then
      if spec.allowMouse and type(button) == "number" and button ~= left and button ~= right then
        finish(w, K.mouseName(button))
      elseif button == right and spec.allowClear then
        finish(w, "")
      elseif button == left then
        cancel()
      end
      return true
    end
    if button == left then start(w) return true end
    if button == right and spec.allowClear then
      pcall(w.setText, w, "")
      if type(spec.set) == "function" then pcall(spec.set, "") end
      return true
    end
    return false
  end
  return widget
end

function K.unbind(widget)
  local spec = widget and widget._keyCapture
  if not spec then return end
  if current and current.widget == widget then cancel() end
  widget.onMousePress = spec.previousMousePress
  widget._keyCapture = nil
  call(widget, "setEditable", true)
end

onKeyDown(function(keys)
  if not current then return end
  if not alive(current.widget) or clock() - current.startedAt > CAPTURE_TIMEOUT_MS then
    cancel()
    return
  end
  keys = tostring(keys or "")
  if keys == "Escape" or keys == "Esc" then cancel() return end
  if K.isModifierOnly(keys) then return end
  finish(current.widget, keys)
end)

return K
