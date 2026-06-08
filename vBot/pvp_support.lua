setDefaultTab("Tools")

local panelName = "pvpSupport"
if not storage[panelName] then
  storage[panelName] = {
    holdTarget = false,
    holdTargetName = "",
    lastPlayer = "",
    lastExivaName = "",
    exivaTarget = false,
    exivaLast = false,
    exivaSpell = "exiva"
  }
end

local config = storage[panelName]
local holdTargetId = nil
local lastAutoExiva = 0

local function getTime()
  if now then return now end
  if g_clock and g_clock.millis then return g_clock.millis() end
  return 0
end

local function cleanName(name)
  if not name then return "" end
  return tostring(name):gsub("^%s*(.-)%s*$", "%1")
end

config.holdTarget = config.holdTarget == true
config.exivaTarget = config.exivaTarget == true
config.exivaLast = config.exivaLast == true
config.holdTargetName = ""
config.lastPlayer = cleanName(config.lastPlayer)
config.lastExivaName = cleanName(config.lastExivaName)
config.exivaSpell = config.exivaSpell or "exiva"

local function isEscapeKey(keys)
  return keys == "Escape" or keys == "Esc"
end

local function getAttackTarget()
  if type(target) == "function" then
    local ok, creature = pcall(target)
    if ok and creature then return creature end
  end

  if g_game and g_game.getAttackingCreature then
    return g_game.getAttackingCreature()
  end
end

local function attackCreature(creature)
  if not creature then return end

  if type(attack) == "function" then
    local ok = pcall(function()
      attack(creature)
    end)
    if ok then return true end
  end

  if g_game and g_game.attack then
    return g_game.attack(creature)
  end
end

local function isPlayer(creature)
  if not creature then return false end
  local ok, result = pcall(function() return creature:isPlayer() end)
  return ok and result == true
end

local function isNpc(creature)
  if not creature then return false end
  local ok, result = pcall(function() return creature:isNpc() end)
  return ok and result == true
end

local function sameFloor(creature)
  return creature and creature:getPosition() and creature:getPosition().z == posz()
end

local function rememberPlayer(creature)
  if not creature or not isPlayer(creature) then return end
  local name = cleanName(creature:getName())
  if name ~= "" then
    config.lastPlayer = name
  end
end

local function rememberHoldTarget(creature)
  if not creature or not sameFloor(creature) or isNpc(creature) then return end

  holdTargetId = creature:getId()
  config.holdTargetName = cleanName(creature:getName())
  rememberPlayer(creature)
end

local function clearHoldTarget()
  holdTargetId = nil
  config.holdTargetName = ""
end

local function sayExiva(name)
  name = cleanName(name)
  if name == "" then return false end

  local message = (config.exivaSpell or "exiva") .. ' "' .. name .. '"'
  config.lastExivaName = name

  if type(say) == "function" then
    local ok = pcall(function()
      say(message)
    end)
    if ok then return true end
  end

  if g_game and g_game.talk then
    return g_game.talk(message)
  end

  return true
end

local function runAutoExiva()
  if config.exivaTarget and config.lastPlayer ~= "" then
    return sayExiva(config.lastPlayer)
  end

  if config.exivaLast and config.lastExivaName ~= "" then
    return sayExiva(config.lastExivaName)
  end

  return false
end

onAttackingCreatureChange(function(newCreature, oldCreature)
  if newCreature then
    rememberPlayer(newCreature)
  elseif oldCreature then
    rememberPlayer(oldCreature)
  end
end)

onTalk(function(name, level, mode, text, channelId, pos)
  if name ~= player:getName() then return end

  local exivaName = text:match('[Ee][Xx][Ii][Vv][Aa]%s+"([^"]+)"') or text:match('[Ee][Xx][Ii][Vv][Aa]%s+(.+)')
  if exivaName then
    config.lastExivaName = cleanName(exivaName:gsub('"', ""))
  end
end)

onKeyDown(function(keys)
  if isEscapeKey(keys) then
    clearHoldTarget()
  end
end)

onKeyPress(function(keys)
  if isEscapeKey(keys) then
    clearHoldTarget()
  end
end)

macro(100, function()
  if not config.holdTarget then return end

  local currentTarget = getAttackTarget()
  if currentTarget and sameFloor(currentTarget) and not isNpc(currentTarget) then
    rememberHoldTarget(currentTarget)
    return
  end

  if not holdTargetId then return end

  for _, spec in ipairs(getSpectators()) do
    if spec and sameFloor(spec) and spec:getId() == holdTargetId then
      return attackCreature(spec)
    end
  end
end)

macro(100, function()
  if not config.exivaTarget then return end

  local currentTarget = getAttackTarget()
  if currentTarget then
    rememberPlayer(currentTarget)
  end
end)

macro(200, function()
  if not config.exivaTarget and not config.exivaLast then return end
  if getTime() - lastAutoExiva < 4000 then return end

  if runAutoExiva() then
    lastAutoExiva = getTime()
  end
end)

HoldTarget = {
  isOn = function()
    return config.holdTarget
  end,
  setOn = function()
    config.holdTarget = true
    local currentTarget = getAttackTarget()
    if currentTarget then
      rememberHoldTarget(currentTarget)
    end
  end,
  setOff = function()
    config.holdTarget = false
    clearHoldTarget()
  end
}

ExivaTarget = {
  isOn = function()
    return config.exivaTarget
  end,
  setOn = function()
    config.exivaTarget = true
    local currentTarget = getAttackTarget()
    if currentTarget then
      rememberPlayer(currentTarget)
    end
    if runAutoExiva() then
      lastAutoExiva = getTime()
    end
  end,
  setOff = function()
    config.exivaTarget = false
  end
}

ExivaLast = {
  isOn = function()
    return config.exivaLast
  end,
  setOn = function()
    config.exivaLast = true
    if runAutoExiva() then
      lastAutoExiva = getTime()
    end
  end,
  setOff = function()
    config.exivaLast = false
  end
}
