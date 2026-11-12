--[[
  ClientDetector - Feature and capability sniffing for Open Tibia Client forks
  Detects client capabilities at runtime without relying solely on filesystem paths.
]]

ClientDetector = ClientDetector or {}

local function detectCapabilities()
  local caps = {}

  -- Core APIs
  caps.hasNativeSpellAim   = g_game and type(g_game.setNextTalkAim) == 'function' or false
  caps.hasThingCatalog     = g_things and type(g_things.getThingTypes) == 'function' or false
  caps.hasQuickLoot        = (g_game and (type(g_game.sendQuickLoot) == 'function' or type(g_game.quickLoot) == 'function'))
    or (HelperClient and HelperClient.nativeFeatures and HelperClient.nativeFeatures.GameThingQuickLoot ~= nil) or false

  -- Raw local filesystem I/O
  local rawIO = false
  if type(io) == 'table' and type(io.open) == 'function' then
    rawIO = true
  elseif modules and modules.corelib and type(modules.corelib.io) == 'table' and type(modules.corelib.io.open) == 'function' then
    rawIO = true
  elseif type(helperIO) == 'table' and type(helperIO.open) == 'function' then
    rawIO = true
  end
  caps.hasRawIO            = rawIO

  -- Game action & inventory functions
  caps.hasEquipItemId      = g_game and type(g_game.equipItemId) == 'function' or false
  caps.hasEquipItem        = g_game and type(g_game.equipItem) == 'function' or false
  caps.hasUseInventoryItem = g_game and type(g_game.useInventoryItem) == 'function' or false
  caps.hasInventoryCount   = (player and type(player.getInventoryCount) == 'function')
    or (g_game and type(g_game.getLocalPlayer) == 'function' and g_game.getLocalPlayer() and type(g_game.getLocalPlayer().getInventoryCount) == 'function') or false
  caps.hasActionBar        = (modules and (modules.game_actionbar ~= nil or modules.game_actionbars ~= nil)) or false
  caps.hasGetContainers    = g_game and type(g_game.getContainers) == 'function' or false
  caps.hasStyleFromString  = g_ui and type(g_ui.importStyleFromString) == 'function' or false

  -- Dat signature
  if g_things and type(g_things.getDatSignature) == 'function' then
    local ok, sig = pcall(g_things.getDatSignature)
    caps.datSignature = ok and sig or nil
  else
    caps.datSignature = nil
  end

  -- Slot constants with robust fallbacks
  caps.fingerSlot = SlotFinger or InventorySlotFinger or 9
  caps.neckSlot   = SlotNeck or InventorySlotNecklace or InventorySlotNeck or 2
  caps.backSlot   = SlotBack or InventorySlotBack or 3
  caps.headSlot   = SlotHead or InventorySlotHead or 1
  caps.bodySlot   = SlotBody or InventorySlotArmor or 4
  caps.legSlot    = SlotLegs or InventorySlotLegs or 7
  caps.feetSlot   = SlotFeet or InventorySlotFeet or 8
  -- Fallbacks follow upstream OTClient (Right=5, Left=6); only used when the
  -- client exposes neither the Slot* nor the InventorySlot* constants.
  caps.leftSlot   = SlotLeft or InventorySlotLeft or 6
  caps.rightSlot  = SlotRight or InventorySlotRight or 5
  caps.ammoSlot   = SlotAmmo or InventorySlotAmmo or 10
  caps.purseSlot  = SlotPurse or InventorySlotPurse or 11

  return caps
end

local function getCurrentPath()
  if HelperClient and HelperClient.writeRoot and type(HelperClient.writeRoot) == 'string' then
    return HelperClient.writeRoot:lower():gsub('\\', '/') .. '/'
  end
  if g_resources and type(g_resources.getWriteDir) == 'function' then
    local ok, wd = pcall(g_resources.getWriteDir)
    if ok and type(wd) == 'string' then
      return wd:lower():gsub('\\', '/') .. '/'
    end
  end
  return ''
end

-- Known profiles for scoring
local knownProfiles = {
  {
    id = 'valkaris',
    name = 'Valkaris',
    path = '/valkaris/',
    caps = {
      hasRawIO = true,
      hasEquipItemId = true,
      hasQuickLoot = true,
      hasNativeSpellAim = true,
    },
    hints = function()
      return ValkarisHelperCompatibility ~= nil or type(ValkarisTrace) == 'function'
    end
  },
  {
    id = 'valkaris-ng',
    name = 'Valkaris Next Gen',
    path = '/valkaris client/',
    caps = {
      hasRawIO = true,
      hasEquipItemId = true,
      hasQuickLoot = true,
      hasNativeSpellAim = true,
    },
    hints = function() return false end
  },
  {
    id = 'aurera',
    name = 'Aurera',
    path = '/otclientv8/aurera/',
    caps = {
      hasNativeSpellAim = false,
      hasRawIO = false,
    },
    hints = function()
      return HelperClientCompat and HelperClientCompat.isAurera == true
    end
  },
  {
    id = 'generic',
    name = 'Cliente generico',
    caps = {},
    hints = function() return false end
  }
}

function ClientDetector.detect()
  local caps = detectCapabilities()
  ClientDetector.caps = caps

  -- Score known profiles
  local currentPath = getCurrentPath()
  local registry = HelperClientRegistry or knownProfiles

  local bestProfile = nil
  local bestScore = -100

  for _, profile in ipairs(registry) do
    local score = 0
    if profile.caps and type(profile.caps) == 'table' then
      for capName, expectedVal in pairs(profile.caps) do
        if caps[capName] == expectedVal then
          score = score + 10
        else
          score = score - 5
        end
      end
    end

    -- Path hint as tie-breaker
    if profile.path and currentPath ~= '' and currentPath:find(profile.path:lower(), 1, true) then
      score = score + 5
    end

    -- Hint function check (if present in known profile)
    for _, kp in ipairs(knownProfiles) do
      if kp.id == profile.id and kp.hints and kp.hints() then
        score = score + 15
      end
    end

    -- Retain consistency with earlier HelperClient bootstrap if available
    if HelperClient and HelperClient.id == profile.id then
      score = score + 2
    end

    if score > bestScore then
      bestScore = score
      bestProfile = profile
    end
  end

  if not bestProfile or bestScore <= 0 then
    -- Fallback to generic or existing HelperClient
    if HelperClient and HelperClient.id then
      ClientDetector.id = HelperClient.id
      ClientDetector.name = HelperClient.name or 'Cliente'
    else
      ClientDetector.id = 'generic'
      ClientDetector.name = 'Cliente generico'
    end
  else
    ClientDetector.id = bestProfile.id
    ClientDetector.name = bestProfile.name
  end

  return ClientDetector
end

-- Both Valkaris clients (the original one and Next Gen).
function ClientDetector.isValkaris()
  return ClientDetector.id == 'valkaris' or ClientDetector.id == 'valkaris-ng'
end

function ClientDetector.isAurera()
  return ClientDetector.id == 'aurera'
end

-- Run immediate detection on load
ClientDetector.detect()

return ClientDetector
