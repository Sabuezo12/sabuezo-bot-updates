local panelName = "Dash"
local DASH_DELAY = 25
local KEY_HOLD_MS = 140

if not storage[panelName] then
  storage[panelName] = {
    enabled = false
  }
end

local config = storage[panelName]
config.enabled = config.enabled == true

local lastWalkAt = 0
local keyUntil = {
  w = 0,
  a = 0,
  s = 0,
  d = 0
}

local keyAliases = {
  w = {"W", "w", "KeyW"},
  a = {"A", "a", "KeyA"},
  s = {"S", "s", "KeyS"},
  d = {"D", "d", "KeyD"}
}

local function getTime()
  if now then return now end
  if g_clock and g_clock.millis then return g_clock.millis() end
  return 0
end

local function normalizeKey(key)
  key = tostring(key or ""):lower()
  if key == "keyw" then return "w" end
  if key == "keya" then return "a" end
  if key == "keys" then return "s" end
  if key == "keyd" then return "d" end
  return key
end

local function setEnabled(enabled)
  config.enabled = enabled == true
  if not config.enabled then
    keyUntil.w = 0
    keyUntil.a = 0
    keyUntil.s = 0
    keyUntil.d = 0
  end
end

local function isKeyPressed(key)
  if g_keyboard and g_keyboard.isKeyPressed then
    for _, alias in ipairs(keyAliases[key] or {}) do
      local ok, pressed = pcall(function()
        return g_keyboard.isKeyPressed(alias)
      end)
      if ok and pressed then return true end
    end
  end

  return getTime() <= (keyUntil[key] or 0)
end

local function directionFromKeys()
  local dx = 0
  local dy = 0

  if isKeyPressed("w") then dy = dy - 1 end
  if isKeyPressed("s") then dy = dy + 1 end
  if isKeyPressed("a") then dx = dx - 1 end
  if isKeyPressed("d") then dx = dx + 1 end

  if dx == 0 and dy == -1 then return 0 end
  if dx == 1 and dy == 0 then return 1 end
  if dx == 0 and dy == 1 then return 2 end
  if dx == -1 and dy == 0 then return 3 end
  if dx == 1 and dy == -1 then return 4 end
  if dx == 1 and dy == 1 then return 5 end
  if dx == -1 and dy == 1 then return 6 end
  if dx == -1 and dy == -1 then return 7 end
  return nil
end

local function walkDirection(dir)
  if dir == nil then return false end

  if g_game and g_game.walk then
    local ok = pcall(function()
      g_game.walk(dir, false)
    end)
    if ok then return true end
  end

  if type(walk) == "function" then
    local ok = pcall(function()
      walk(dir)
    end)
    if ok then return true end
  end

  return false
end

local function dashStep()
  if not config.enabled then return false end

  local time = getTime()
  if time - lastWalkAt < DASH_DELAY then return false end

  local dir = directionFromKeys()
  if dir == nil then return false end

  if walkDirection(dir) then
    lastWalkAt = time
    return true
  end

  return false
end

onKeyDown(function(keys)
  if not config.enabled then return end

  local key = normalizeKey(keys)
  if keyUntil[key] == nil then return end

  keyUntil[key] = getTime() + KEY_HOLD_MS
  dashStep()
end)

macro(20, function()
  dashStep()
end)

Dash = {
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
