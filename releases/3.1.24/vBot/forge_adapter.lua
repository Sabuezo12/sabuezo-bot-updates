--[[
  forge_adapter - gives Auto Forge the conversion API it needs on clients whose
  game_forge module does not ship the "safe adapter" (e.g. Valkaris).

  It reads balances and rates from the client's Forge implementation and sends
  the same request as the Forge window. Next Gen uses ForgeSystem, player
  resource balances and g_game.sendForgeConverter.

  Safety: Auto Forge's engine (auto_forge_engine.lua) persists every request
  before it is sent and confirms it only when the balances change; it blocks
  itself on any doubt. This adapter adds: it refuses when the client says a
  request is pending, when the balances do not cover the conversion, when the
  rates are not the expected ones, and never repeats a request on its own. The
  client's own "disable conversion" flags are only reported, not obeyed: they
  can be stale or off by one.
]]

HelperForgeAdapter = HelperForgeAdapter or {}
local A = HelperForgeAdapter

A.safeAdapterVersion = 20261111   -- Auto Forge asks for >= 20261104
local DUST2SLIVER, SLIVER2CORE = 2, 3

local sessionKey = nil
local tokenCounter = 0
local inFlightUntil = 0

local function controller()
  local forge = modules and modules.game_forge
  local c = forge and forge.ForgeController
  if type(c) ~= 'table' or type(c.conversion) ~= 'table' then return nil end
  local types = c.conversion.types
  if type(types) ~= 'table' or types.DUST2SLIVER ~= DUST2SLIVER or types.SLIVER2CORE ~= SLIVER2CORE then return nil end
  if not g_game or type(g_game.forgeRequest) ~= 'function' then return nil end
  return c
end

local function nextGenForge()
  local forge = modules and modules.game_forge
  if forge and type(forge.ForgeSystem) == 'table' and g_game and type(g_game.sendForgeConverter) == 'function' then
    return forge
  end
end

local function number(value)
  value = tonumber(value)
  if value and value == value and value >= 0 and value == math.floor(value) then return value end
end

-- Rates come from the client's own conversion table, never assumed here.
local function rates(conversion)
  local coreGain = number(tostring(conversion.sliverToCoreLabel or ''):match('(%d+)'))
  return {
    dustCost = number(conversion.necessaryDustToSliver),
    sliverGain = number(conversion.dustToSliver),
    sliverCost = number(conversion.sliverToCore),
    coreGain = coreGain,
  }
end

-- True when the balances alone cover the conversion (see safeAutoConvert).
local function canConvert(c, kind)
  local conversion = c.conversion
  if kind == DUST2SLIVER then
    local dust, cost = number(c.currentDust), number(conversion.necessaryDustToSliver)
    return dust ~= nil and cost ~= nil and cost > 0 and dust >= cost
  end
  local slivers, cost = number(c.currentSlivers), number(conversion.sliverToCore)
  return slivers ~= nil and cost ~= nil and cost > 0 and slivers >= cost
end

function A.available()
  return controller() ~= nil or nextGenForge() ~= nil
end

local function sessionId()
  if not sessionKey then
    local name = 'player'
    if g_game and type(g_game.getLocalPlayer) == 'function' then
      local ok, lp = pcall(g_game.getLocalPlayer)
      if ok and lp then
        local okName, value = pcall(function() return lp:getName() end)
        if okName and value then name = tostring(value) end
      end
    end
    -- A new bot load (login) is a new session: a pending request never survives it.
    sessionKey = name .. ':' .. tostring(os.time())
  end
  return sessionKey
end

-- Resource IDs from Next Gen's gamelib/const.lua. Prefer the constants of the running client.
local function resourceBalance(player, forge, name, fallback)
  local gamelib = modules and modules.gamelib
  local id = number(forge[name]) or (gamelib and number(gamelib[name])) or fallback
  local ok, value = pcall(function() return player:getResourceValue(id) end)
  if ok then return number(value) end
end

local function nextGenSnapshot(forge)
  if type(g_game.isOnline) == 'function' and not g_game.isOnline() then return nil, 'offline' end
  local system = forge.ForgeSystem
  local sliverGain = number(system.slivers)
  local dustPerSliver = number(system.baseMultipier)
  local sliverCost = number(system.totalSlivers)
  if not sliverGain or sliverGain == 0 or not dustPerSliver or dustPerSliver == 0 or not sliverCost or sliverCost == 0 then
    return nil, 'rates_not_ready'
  end

  local ok, player = pcall(g_game.getLocalPlayer)
  if not ok or not player then return nil, 'balances_unavailable' end
  local dust = resourceBalance(player, forge, 'ResourceForgeDust', 70)
  local slivers = resourceBalance(player, forge, 'ResourceForgeSlivers', 71)
  local cores = resourceBalance(player, forge, 'ResourceForgeExaltedCore', 72)
  local bank = resourceBalance(player, forge, 'ResourceBank', 0)
  local inventory = resourceBalance(player, forge, 'ResourceInventary', 1)
  if not (dust and slivers and cores and bank and inventory) then return nil, 'balances_unavailable' end

  return {
    sessionId = sessionId(),
    pending = system.inForgeFusion == true or (tonumber(now) or 0) < inFlightUntil,
    dust = dust, slivers = slivers, cores = cores, gold = bank + inventory,
    dustCost = sliverGain * dustPerSliver, sliverGain = sliverGain, sliverCost = sliverCost, coreGain = 1,
  }
end

-- Returns a snapshot table, or nil plus a reason understood by auto_forge.lua.
function A.autoSnapshot()
  local c = controller()
  if not c then
    local forge = nextGenForge()
    if not forge then return nil, 'unsupported' end
    return nextGenSnapshot(forge)
  end
  local dust, slivers, cores, gold = number(c.currentDust), number(c.currentSlivers),
    number(c.currentExaltedCores), number(c.rawCurrentGold)
  if not (dust and slivers and cores and gold) then return nil, 'balances_unavailable' end
  local r = rates(c.conversion)
  -- Missing costs mean the Forge data has not been published yet (not that they are wrong).
  if not (r.dustCost and r.sliverGain and r.sliverCost and r.coreGain) then return nil, 'rates_not_ready' end
  local clock = type(now) == 'number' and now or 0
  return {
    sessionId = sessionId(),
    pending = c.waitingForResult == true or clock < inFlightUntil,
    dust = dust, slivers = slivers, cores = cores, gold = gold,
    dustCost = r.dustCost, sliverGain = r.sliverGain, sliverCost = r.sliverCost, coreGain = r.coreGain,
  }
end

local function trackRequest(clock)
  tokenCounter = tokenCounter + 1
  inFlightUntil = clock + 1500
  return tokenCounter
end

local function sendNextGen(forge, kind, clock)
  local current, reason = nextGenSnapshot(forge)
  if not current then return false, reason end
  if current.pending then return false, 'busy' end
  if current.dustCost ~= 60 or current.sliverGain ~= 3 or current.sliverCost ~= 50 then return false, 'invalid_rates' end
  if kind == DUST2SLIVER and current.dust < current.dustCost then return false, 'insufficient_dust' end
  if kind == SLIVER2CORE and current.slivers < current.sliverCost then return false, 'insufficient_slivers' end
  if type(g_game.getProtocolGame) ~= 'function' or not g_game.getProtocolGame() then return false, 'offline' end
  -- An exception during this call has an unknown outcome. Let the engine keep the
  -- pending record and stop instead of issuing another request.
  if g_game.sendForgeConverter(kind) == false then return false, 'request_failed' end
  return true, nil, trackRequest(clock)
end

-- Returns sent (boolean), reason, token. A true result only means "sent": the
-- engine waits for the balances to change before it counts the conversion.
function A.safeAutoConvert(kind)
  if kind ~= DUST2SLIVER and kind ~= SLIVER2CORE then return false, 'unsupported' end
  local c = controller()
  local clock = type(now) == 'number' and now or 0
  if clock < inFlightUntil then return false, 'request_in_flight' end
  if not c then
    local forge = nextGenForge()
    if not forge then return false, 'unsupported' end
    return sendNextGen(forge, kind, clock)
  end
  if c.waitingForResult == true then return false, 'busy' end
  -- The decision uses the balances and costs themselves. The client's own
  -- disableDustConversion / disableSliverConversion flags are computed by its Forge
  -- window: they can lag behind the balances (window closed) or be off by one (false
  -- at exactly 60 dust), which used to stop Auto Forge after a single conversion. The
  -- server validates every request anyway, and the engine only counts a conversion
  -- when the balances really change.
  if not canConvert(c, kind) then
    return false, kind == DUST2SLIVER and 'insufficient_dust' or 'insufficient_slivers'
  end
  local flagged = (kind == DUST2SLIVER and c.conversion.disableDustConversion == true) or
    (kind == SLIVER2CORE and c.conversion.disableSliverConversion == true)
  -- Same action the Forge window sends. If the binding wants every argument, the
  -- first call fails before sending anything and the full form is tried once.
  local ok = pcall(g_game.forgeRequest, kind)
  if not ok then ok = pcall(g_game.forgeRequest, kind, 0, 0, 0, false, false) end
  if not ok then return false, 'request_failed' end
  return true, nil, trackRequest(clock),
    flagged and 'el cliente marcaba esta conversion como desactivada; se envia porque hay saldo' or nil
end

function A.resetAutoPending()
  inFlightUntil = 0
  return true
end

return A
