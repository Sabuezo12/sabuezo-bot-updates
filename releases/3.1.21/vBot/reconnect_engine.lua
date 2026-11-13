-- Reconect: decisions only. It drives nothing by itself: reconnect.lua tells it what happened (game started,
-- game ended, connection error, login error, the user asked to log out) and calls tick() from the client timer, and it
-- asks reconnect.lua to try the login. Everything it needs comes in through `deps`, so it can be tested alone.
--
-- Rules:
--   * Off by default. When on, a game end that nobody asked for (lost connection, server closed it, kick that
--     is not a ban) is followed by login attempts with the same character.
--   * A logout asked by the user or by the bot (safeLogout, forceLogout, logout) is never undone.
--   * A ban, suspension, wrong password or deleted character stops it.
--   * The client timer schedules the first attempt. Retries run every four seconds, MAX_ATTEMPTS at most.
--
-- This code keeps running on client timers after the bot's context has stopped, and that environment may no
-- longer resolve globals, so everything it uses is captured here as locals when the file loads.
local pcall, type, pairs, ipairs, tostring, tonumber = pcall, type, pairs, ipairs, tostring, tonumber
local table, string, math = table, string, math

HelperReconnectEngine = HelperReconnectEngine or {}
local E = HelperReconnectEngine

E.FIRST_DELAY_MS = 250
local RETRY_DELAY = 4
E.MAX_ATTEMPTS = 40
E.INTENTIONAL_WINDOW = 30 -- seconds in which a logout request explains the next game end
E.ERROR_WINDOW = 10       -- seconds in which an error message explains the next game end
E.STALE = 1800            -- a pending reconnection older than this is forgotten

-- Messages that mean "do not insist" (Lua patterns, lower case).
local FATAL = {'%f[%a]ban%f[%A]', '%f[%a]banned%f[%A]', 'banish', 'suspend', 'delet', 'password', 'account name',
  'blocked', 'locked', 'forbidden', 'not allowed', 'wrong'}

function E.isFatal(message)
  local text = tostring(message or ''):lower()
  for _, pattern in ipairs(FATAL) do
    if text:find(pattern) then return true end
  end
  return false
end

local function number(value, default)
  value = tonumber(value)
  if value == nil or value ~= value then return default end
  return value
end

-- Fixes whatever is in storage so the rest of the code can trust it.
function E.normalize(config)
  if type(config.enabled) ~= 'boolean' then config.enabled = false end
  if type(config.stats) ~= 'table' then config.stats = {} end
  local stats = config.stats
  for _, key in ipairs({'drops', 'reconnects', 'attempts'}) do stats[key] = math.max(0, math.floor(number(stats[key], 0))) end
  if stats.lastDropAt ~= nil then stats.lastDropAt = number(stats.lastDropAt, nil) end
  if stats.lastOkAt ~= nil then stats.lastOkAt = number(stats.lastOkAt, nil) end
  config.drops = nil -- discard the old rolling window; stats.drops is still used for reporting
  if config.pending ~= nil then
    if type(config.pending) ~= 'table' or not tonumber(config.pending.at) then config.pending = nil
    else config.pending = {at = tonumber(config.pending.at), attempts = math.max(0, math.floor(number(config.pending.attempts, 0)))} end
  end
  return config
end

function E.new(deps)
  local config = E.normalize(deps.config)
  local engine = {config = config, mode = 'idle', trace = {}, attempts = 0, nextAt = 0}
  local intentionalUntil, lastError, lastErrorAt = 0, nil, 0
  local stopReason

  local function now() return number(deps.clock and deps.clock(), 0) end
  local function online() return deps.isOnline and deps.isOnline() == true end
  local function log(message)
    local entry = {at = now(), text = message}
    engine.trace[#engine.trace + 1] = entry
    while #engine.trace > 40 do table.remove(engine.trace, 1) end
    if deps.log then pcall(deps.log, message, entry) end
  end
  engine.log = log

  local function stop(reason)
    engine.mode = 'stopped'
    stopReason = reason
    config.pending = nil
    log('Reconect se detiene: ' .. reason)
  end

  -- The game is up: a pending reconnection was a success.
  function engine.onGameStart()
    local pending = config.pending
    if pending then
      config.stats.reconnects = config.stats.reconnects + 1
      config.stats.lastOkAt = now()
      config.pending = nil
      log(string.format('Reconectado tras %d intento(s), %d s despues de la caida', pending.attempts, math.max(0, now() - pending.at)))
    end
    engine.mode, engine.attempts, stopReason = 'idle', 0, nil
    intentionalUntil, lastError = 0, nil
  end

  -- The user (or the bot) asked to log out: the game end that follows is wanted.
  function engine.onIntentionalLogout()
    intentionalUntil = now() + E.INTENTIONAL_WINDOW
  end

  function engine.onConnectionError(message, code)
    lastError, lastErrorAt = 'conexion perdida: ' .. tostring(message or code or '?'), now()
  end

  function engine.onLoginError(message)
    lastError, lastErrorAt = tostring(message or '?'), now()
    -- While trying, a refused login that is final ends the attempts; a transient one (world full...) does not.
    if engine.mode == 'waiting' and E.isFatal(message) then stop('el servidor rechazo la entrada: ' .. tostring(message):sub(1, 120)) end
  end

  function engine.onGameEnd()
    if not config.enabled then engine.mode = 'idle'; return end
    if engine.mode == 'waiting' or engine.mode == 'stopped' then return end
    local time = now()
    if time <= intentionalUntil then
      engine.mode = 'manual'
      log('Salida voluntaria: no se reconecta')
      return
    end
    local explained = lastError and time - lastErrorAt <= E.ERROR_WINDOW
    if explained and E.isFatal(lastError) then
      engine.mode = 'stopped'
      stopReason = 'el servidor dijo: ' .. lastError:sub(1, 120)
      log('Reconect no insiste: ' .. stopReason)
      return
    end
    config.stats.drops = config.stats.drops + 1
    config.stats.lastDropAt = time
    config.pending = {at = time, attempts = 0}
    engine.mode, engine.attempts, engine.nextAt = 'waiting', 0, time
    log(string.format('Conexion perdida%s: primer intento programado', explained and (' (' .. lastError:sub(1, 80) .. ')') or ''))
  end

  function engine.setEnabled(value)
    value = value == true
    if config.enabled == value then return end
    config.enabled = value
    if not value then
      engine.mode, config.pending, stopReason = 'idle', nil, nil
    elseif engine.mode == 'stopped' or engine.mode == 'manual' then
      engine.mode, stopReason = 'idle', nil
    end
    log(value and 'Reconect activado' or 'Reconect desactivado')
  end

  -- Called when the module loads (a reload, or a new bot context after a login).
  function engine.onLoad()
    local pending = config.pending
    if not pending then return end
    if now() - pending.at > E.STALE then config.pending = nil; return end
    if online() then engine.onGameStart() return end
    -- A new bot context that finds the game offline keeps trying where the old one left off.
    if config.enabled then
      local retryDelay = pending.attempts > 0 and RETRY_DELAY or 0
      engine.mode, engine.attempts, engine.nextAt = 'waiting', pending.attempts, now() + retryDelay
    else
      config.pending = nil
    end
  end

  -- Returns true when it tried to log in.
  function engine.tick()
    if not config.enabled or engine.mode ~= 'waiting' then return false end
    if online() then engine.onGameStart() return false end
    local time = now()
    if time < engine.nextAt then return false end
    if deps.isLogging and deps.isLogging() then
      engine.nextAt = time + RETRY_DELAY
      return false
    end
    if engine.attempts >= E.MAX_ATTEMPTS then
      stop(string.format('%d intentos sin entrar', E.MAX_ATTEMPTS))
      return false
    end
    local attemptNumber = engine.attempts + 1
    engine.attempts = attemptNumber
    if config.pending then config.pending.attempts = attemptNumber end
    config.stats.attempts = config.stats.attempts + 1
    engine.nextAt = time + RETRY_DELAY
    local ok, done, detail = pcall(deps.attempt, attemptNumber)
    if not ok then done, detail = false, 'error: ' .. tostring(done) end
    log(string.format('Intento %d/%d: %s%s', attemptNumber, E.MAX_ATTEMPTS, done and 'pedido al cliente' or 'no se pudo',
      detail and (' (' .. tostring(detail) .. ')') or ''))
    return true
  end

  -- {kind, message, remaining} for the panel.
  function engine.status()
    if not config.enabled then return {kind = 'off', message = 'Desactivado'} end
    if engine.mode == 'waiting' then
      return {kind = 'counting', message = string.format('Reconectando: intento %d/%d', engine.attempts + 1, E.MAX_ATTEMPTS),
        remaining = math.max(0, engine.nextAt - now())}
    end
    if engine.mode == 'stopped' then return {kind = 'stopped', message = 'Detenido: ' .. tostring(stopReason or '?')} end
    if engine.mode == 'manual' then return {kind = 'idle', message = 'Saliste tu: no se reconecta'} end
    local stats = config.stats
    return {kind = 'idle', message = string.format('Vigilando | caidas %d, reconexiones %d', stats.drops, stats.reconnects)}
  end

  return engine
end

return E
