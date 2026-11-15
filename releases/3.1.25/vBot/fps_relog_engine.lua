-- FPS Relog engine: says "!fps" every N minutes, at a moment when the character is safe,
-- and measures how long the relog takes. Pure logic (clock, snapshot, say and log are
-- injected) so it can be tested without the game.
--
-- The bot cannot act while the character is offline (it is unloaded with the game and
-- loaded again at login), so what can be controlled is WHEN the command is sent and how
-- soon after the player is back everything is running again. Both are measured.
HelperFpsRelogEngine = {}
local E = HelperFpsRelogEngine

local RELOAD_WINDOW = 300   -- s: a bot load this soon after the command is the relog coming back
local NO_RELOAD_AFTER = 20  -- s: if the bot is still the same one after this, the relog did not reload it
local RETRY_SAY = 5         -- s between attempts when the client refuses to send the command

local function integer(value, low, high, default)
  value = tonumber(value)
  if not value or value ~= value then return default end
  value = math.floor(value)
  if value < low then return low end
  if value > high then return high end
  return value
end

local function normalize(config)
  config.enabled = config.enabled == true
  config.command = type(config.command) == "string" and config.command:match("^%s*(.-)%s*$") or ""
  if config.command == "" then config.command = "!fps" end
  config.intervalMin = integer(config.intervalMin, 1, 720, 30)
  config.safeMonsters = config.safeMonsters ~= false
  config.monsterRadius = integer(config.monsterRadius, 1, 15, 7)
  config.minHp = integer(config.minHp, 0, 99, 70)
  config.playerRadius = integer(config.playerRadius, 0, 15, 0)
  config.waitSec = integer(config.waitSec, 0, 600, 120)
  config.forceAfterWait = config.forceAfterWait == true
  config.lastSentAt = tonumber(config.lastSentAt) or 0
  config.sentAt = tonumber(config.sentAt)
  if type(config.stats) ~= "table" then config.stats = {} end
  local stats = config.stats
  stats.count = integer(stats.count, 0, 1e9, 0)
  stats.returns = integer(stats.returns, 0, 1e9, 0)
  stats.total = integer(stats.total, 0, 1e9, 0)
  stats.noReload = integer(stats.noReload, 0, 1e9, 0)
  stats.last = tonumber(stats.last)
  stats.best = tonumber(stats.best)
  stats.worst = tonumber(stats.worst)
  return config
end
E.normalize = normalize

function E.new(options)
  local C = {config = normalize(assert(options.config)), state = {kind = "off", message = "Desactivado"}, trace = {}}
  local config = C.config
  local clock = options.clock
  C.manualDue, C.nextTryAt = false, 0

  local function note(text)
    C.trace[#C.trace + 1] = {at = clock(), text = text}
    while #C.trace > 30 do table.remove(C.trace, 1) end
    if options.log then pcall(options.log, text) end
  end
  local function state(kind, message, remaining)
    C.state.kind, C.state.message, C.state.remaining = kind, message, remaining
    return C.state
  end

  -- Safe moment: nothing that could kill the character while it is away/loading.
  -- In a protection zone nothing can attack, so no other check applies there.
  function C.isSafe(snap)
    if snap.inPz then return true end
    if config.safeMonsters and (snap.monsters or 0) > 0 then
      return false, string.format("monstruos a %d casillas (%d)", config.monsterRadius, snap.monsters)
    end
    if config.minHp > 0 and snap.hp and snap.hp < config.minHp then
      return false, string.format("HP %d%% (minimo %d%%)", snap.hp, config.minHp)
    end
    if config.playerRadius > 0 and (snap.players or 0) > 0 then
      return false, string.format("jugadores a %d casillas (%d)", config.playerRadius, snap.players)
    end
    return true
  end

  function C.setEnabled(enabled)
    enabled = enabled == true
    if enabled and not config.enabled then
      config.lastSentAt = clock() -- the countdown starts when it is switched on
      C.manualDue, C.waitingSince, C.waitReason = false, nil, nil
      note(string.format("Activado: %s cada %d min", config.command, config.intervalMin))
    elseif not enabled and config.enabled then
      C.manualDue, C.waitingSince, C.waitReason = false, nil, nil
      note("Desactivado")
    end
    config.enabled = enabled
    if not enabled then state("off", "Desactivado") end
  end

  -- "Send now": due at once, whether or not the automatic mode is on (it is how the
  -- command is tried). The safe-moment check still applies.
  function C.sendNow()
    C.manualDue = true
    C.waitingSince = C.waitingSince or clock()
    note("Envio manual pedido: " .. config.command)
    return true
  end

  -- Called once when the bot loads. A load soon after the command was sent is the
  -- relog coming back: record how long it took from the command to a running bot.
  function C.onLoad()
    local sent = config.sentAt
    if not sent then return nil end
    config.sentAt = nil
    local gap = clock() - sent
    if gap < 0 or gap > RELOAD_WINDOW then return nil end
    local stats = config.stats
    stats.last, stats.returns, stats.total = gap, stats.returns + 1, stats.total + gap
    stats.best = stats.best and math.min(stats.best, gap) or gap
    stats.worst = stats.worst and math.max(stats.worst, gap) or gap
    note(string.format("De vuelta %d s despues de %s (bot cargado; mejor %d s, peor %d s, media %.1f s)",
      gap, config.command, stats.best, stats.worst, stats.total / stats.returns))
    return gap
  end

  function C.tick()
    local now = clock()
    normalize(config)
    -- The command went out but this same bot is still running: the relog did not
    -- reload it (server-side relog, or the command did nothing).
    if config.sentAt and now - config.sentAt >= NO_RELOAD_AFTER then
      config.stats.noReload = config.stats.noReload + 1
      note(string.format("%s enviado hace %d s y el bot no se recargo: el servidor no desconecto al cliente o el comando no hizo nada",
        config.command, now - config.sentAt))
      config.sentAt = nil
    end
    if not config.enabled and not C.manualDue then return state("off", "Desactivado") end
    if config.lastSentAt > now then config.lastSentAt = now end -- clock went backwards

    local due = C.manualDue or now >= config.lastSentAt + config.intervalMin * 60
    if not due then
      C.waitingSince, C.waitReason = nil, nil
      return state("counting", "Proximo " .. config.command, config.lastSentAt + config.intervalMin * 60 - now)
    end
    local okSnap, snap, missing = pcall(options.snapshot, config)
    if not okSnap or type(snap) ~= "table" then
      -- Say which reading is missing, once, instead of waiting silently.
      local why = okSnap and tostring(missing or "sin conexion") or tostring(snap)
      if C.noDataReason ~= why then
        C.noDataReason = why
        note("Toca " .. config.command .. " pero no puedo leer: " .. why)
      end
      return state("waiting", "Sin datos del personaje (" .. why .. ")")
    end
    C.noDataReason = nil
    C.waitingSince = C.waitingSince or now
    if now < C.nextTryAt then return state("waiting", "Reintentando el envio...") end

    local safe, reason = C.isSafe(snap)
    local waited = now - C.waitingSince
    local forced = not safe and config.forceAfterWait and config.waitSec > 0 and waited >= config.waitSec
    if not safe and not forced then
      if C.waitReason ~= reason:gsub("%d+", "#") then
        C.waitReason = reason:gsub("%d+", "#")
        note("Toca " .. config.command .. " pero espero un momento seguro: " .. reason)
      end
      return state("waiting", string.format("Esperando momento seguro: %s (%d s)", reason, waited))
    end

    local ok, err = pcall(options.say, config.command)
    if not ok or err == false then
      C.nextTryAt = now + RETRY_SAY
      note("No se pudo enviar " .. config.command .. ": " .. tostring(ok and "el cliente no lo envio" or err))
      return state("waiting", "No se pudo enviar; reintento en " .. RETRY_SAY .. " s")
    end
    config.lastSentAt, config.sentAt = now, now
    config.stats.count = config.stats.count + 1
    C.manualDue, C.waitingSince, C.waitReason = false, nil, nil
    note(string.format("Enviado %s: HP %s%%, monstruos %d, jugadores %d%s (espero %d s)", config.command,
      tostring(snap.hp or "?"), snap.monsters or 0, snap.players or 0,
      forced and " - FORZADO tras la espera" or snap.inPz and " - en zona protegida" or "", waited))
    return state("sent", "Enviado; esperando el relog...")
  end

  return C
end

return E
