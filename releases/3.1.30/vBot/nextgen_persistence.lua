-- Fix the native Next Gen settings paths from the Helper executor.
local bot = modules.game_bot
local path = '/bot/' .. bot.contentsPanel.config:getCurrentOption().text .. '/vBot/'
local core = modules.corelib or bot
local game = bot.g_game or g_game
local resources = bot.g_resources or g_resources
local codec = bot.json or json
local nativeIO, nativeOS = core.io or io, core.os or os
local nativeSchedule = bot.scheduleEvent or core.scheduleEvent
local nativeConnect = bot.connect or core.connect
local nativeGetEnv = bot.getfenv or core.getfenv
local compile = loadstring or load
local hotkeys = assert(compile(resources.readFileContents(path .. 'nextgen_hotkeys.lua')))()
local installLoot = assert(compile(resources.readFileContents(path .. 'nextgen_quickloot.lua')))()
local host = bot._helperNextGenPersistence or {}
bot._helperNextGenPersistence = host

local function playerState()
  local gamelib = modules.gamelib or bot
  return gamelib.LoadedPlayer or bot.LoadedPlayer or core.LoadedPlayer
end

local function installHotkeys(loaded)
  local settings = modules.client_settings
  local options = core.Options or bot.Options or (settings and settings.Options)
  local keyBinds = core.KeyBinds or bot.KeyBinds
  if not options or type(options.saveData) ~= 'function' or
      type(options.getAutoSwtichPreset) ~= 'function' or not settings or not keyBinds or
      type(settings.autoSwitchHotkey) ~= 'function' or
      type(settings.configureGeneralHotkeys) ~= 'function' or
      not settings.CustomHotkeys or not settings.ActionHotkey then return end
  local lockFile
  if nativeIO and type(nativeIO.open) == 'function' and nativeOS and
      type(nativeOS.time) == 'function' and type(nativeSchedule) == 'function' then
    lockFile = resources.getWriteDir():gsub('[/\\]+$', '') .. '/settings/.helper-hotkey-save.lock'
  end
  return hotkeys.install(host, {
    options = options,
    settings = settings,
    keyBinds = keyBinds,
    loadedPlayer = loaded,
    resources = resources,
    json = codec,
    io = nativeIO,
    time = nativeOS and nativeOS.time,
    lockFile = lockFile,
    schedule = nativeSchedule
  })
end

local function installQuickLoot(loaded)
  local quickloot = modules.game_quickloot
  if not quickloot or type(quickloot.start) ~= 'function' then return end
  -- This build's Quick Loot module is unsandboxed. Its callbacks resolve the
  -- functions in their own environment, inherited by the module table.
  local nativeLoot = nativeGetEnv and nativeGetEnv(quickloot.start) or quickloot
  return installLoot(host, {
    quickloot = nativeLoot,
    loadedPlayer = loaded,
    game = game,
    resources = resources,
    json = codec
  })
end

if not host.endHook and type(nativeConnect) == 'function' then
  local function resetSelection()
    if host.hotkeys then
      host.hotkeys.appliedTo = nil
      host.hotkeys.refreshProfile = nil
    end
  end
  nativeConnect(game, {onGameEnd = resetSelection})
  host.endHook = resetSelection
end

local hotkeyBridge, lootBridge
local function tick()
  local player = game.isOnline() and game.getLocalPlayer()
  if not player then return end
  if not hotkeyBridge or not lootBridge then
    local loaded = playerState()
    if not loaded then return end
    hotkeyBridge = hotkeyBridge or installHotkeys(loaded)
    lootBridge = lootBridge or installQuickLoot(loaded)
  end
  if hotkeyBridge then hotkeyBridge.apply(player) end
  if lootBridge then lootBridge.tick() end
end

local lastError
local function guardedTick()
  local ok, message = pcall(tick)
  if not ok and message ~= lastError then
    lastError = message
    warn('Next Gen: error al guardar perfiles o Quick Loot: ' .. tostring(message))
  end
end
guardedTick()
macro(250, guardedTick)
