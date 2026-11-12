-- Keep a ranged target until its next autoattack actually leaves the player.
-- Spell/rune missiles must not release this hold. Time only releases it when the client
-- gives no missile events at all (HOLD_NO_EVENTS_MS) or as a failsafe (HOLD_FAILSAFE_MS).
TargetBot.ShotLock = {}
local S = TargetBot.ShotLock
local targetId, fired, lastPosition, previousPosition, observedAt, previousAt, primedAt
-- Failsafe: if no projectile is ever observed leaving the player (a client whose distance
-- effect ids are not in the list below, or without onMissle events), the lock would hold
-- the first target forever. After this long without a shot the hold is released.
local HOLD_FAILSAFE_MS = 4000
-- A client that never delivers onMissle events (Valkaris: 0 projectiles seen in minutes of
-- shooting) cannot confirm a shot. The autoattack leaves every 2 s, so the hold is released
-- after one attack interval instead of waiting for the 4 s failsafe on every target.
local HOLD_NO_EVENTS_MS = 2100
S.unknownLogged = {}
local projectiles = {
  [1]=true, [2]=true, [3]=true, [6]=true, [7]=true, [8]=true, [9]=true,
  [10]=true, [12]=true, [13]=true, [14]=true, [16]=true, [17]=true,
  [18]=true, [19]=true, [20]=true, [21]=true, [22]=true, [23]=true,
  [24]=true, [33]=true, [34]=true, [35]=true, [40]=true, [44]=true,
  [45]=true, [48]=true, [49]=true, [50]=true, [51]=true, [53]=true,
  [54]=true, [56]=true, [57]=true, [58]=true, [59]=true
}

local function samePosition(a,b)
  return a and b and a.x==b.x and a.y==b.y and a.z==b.z
end

local function observe(position)
  if not samePosition(position,lastPosition) then
    previousPosition=lastPosition
    previousAt=observedAt
    lastPosition=position and {x=position.x,y=position.y,z=position.z} or nil
  end
  observedAt=now
end

function S.reset()
  targetId,fired,lastPosition,previousPosition,observedAt,previousAt,primedAt=nil,false,nil,nil,nil,nil,nil
end

-- Console trace ("Acciones", origen TargetBot), only when the state changes.
local lastLogKey, lastLogAt = nil, 0
local function shotLog(message, detail)
  if not (RinoConsole and RinoConsole.valid and RinoConsole.valid()) then return end
  local key = message .. (detail or '')
  if key == lastLogKey and now - lastLogAt < 3000 then return end
  if now - lastLogAt < 400 then return end
  lastLogKey, lastLogAt = key, now
  pcall(RinoConsole.log, 'action', 'TargetBot', message, detail)
end

local function describe(params)
  if not params or not params.creature then return '?' end
  local stats = TargetBot.ArrowStats and TargetBot.ArrowStats.counts[params.creature:getId()]
  local ok, name = pcall(function() return params.creature:getName() end)
  return tostring(ok and name or '?') .. ' (' .. (stats and tostring(stats.count) or '?') .. ' en el area)'
end

function S.applies(config)
  if type(onMissle)~='function' or not config then return false end
  if config.diamondArrows or config.burstArrows then return true end
  -- MythicOT's client vocation IDs, also used by vBot/extras.lua.
  local id=type(voc)=='function' and voc() or nil
  return id==2 or id==12
end

local function prime(params)
  S.reset()
  if params and S.applies(params.config) then
    targetId=params.creature:getId()
    primedAt=now
    observe(params.creature:getPosition())
  end
  return params
end

function S.choose(best,currentParams)
  local current=g_game.getAttackingCreature()
  local config=currentParams and currentParams.config
  local position=current and current:getPosition()
  local origin=player and player:getPosition()
  local hp=current and current:getHealthPercent()
  -- Safety, range and disappearance can always release a target. Never hold
  -- one that cannot be shot just to wait for a projectile that cannot arrive.
  if not current or not currentParams or currentParams.creature~=current or
      not S.applies(config) or currentParams.priority<=0 or not current:isMonster() or
      not hp or hp<=0 or not position or not origin or position.z~=origin.z or
      (currentParams.pathLength or 0)>(tonumber(config.maxDistance) or 10) or
      not current:canShoot() then
    return prime(best)
  end
  if targetId~=current:getId() then prime(currentParams) end
  observe(position)
  if not fired then
    local noEvents = (S.seen or 0) == 0
    local limit = noEvents and HOLD_NO_EVENTS_MS or HOLD_FAILSAFE_MS
    if primedAt and now - primedAt > limit then
      S.failsafe = (S.failsafe or 0) + 1
      if noEvents then
        -- Expected on this client: say it once, not on every release.
        if not S.noEventsLogged then
          S.noEventsLogged = true
          shotLog('Flechas: este cliente no envia eventos de proyectil; el bloqueo de disparo dura ' .. (HOLD_NO_EVENTS_MS / 1000) ..
            ' s (un autoataque)', 'proyectiles vistos: 0 | con eventos, el bloqueo espera a la flecha real')
        end
      else
        shotLog('Flechas: ningun proyectil observado en ' .. (HOLD_FAILSAFE_MS / 1000) .. ' s; se libera el bloqueo de disparo',
          'veces: ' .. S.failsafe .. ' | proyectiles vistos: ' .. (S.seen or 0) .. ', propios: ' .. (S.seenOwn or 0) ..
          ', ultimo id propio: ' .. tostring(S.lastOwnId))
      end
      return prime(best or currentParams)
    end
    -- The hold is the normal state while shooting; one line every few seconds is enough
    -- (the console keeps only the last 300 events).
    if best and best.creature ~= current and now - (S.holdLogAt or 0) >= 4000 then
      S.holdLogAt = now
      shotLog('Flechas: mantiene ' .. describe(currentParams) .. ' hasta que salga su flecha; mejor: ' .. describe(best))
    end
    return currentParams
  end
  -- Spend this shot even when the best target stays the same. It cannot be
  -- reused for repeated switches between two subsequent autoattacks.
  local chosen = best or currentParams
  if chosen and chosen.creature ~= current then
    shotLog('Flechas: apunta a ' .. describe(chosen) .. '; el anterior era ' .. describe(currentParams))
  end
  return prime(chosen)
end

if type(onMissle)=='function' then
  onMissle(function(missile)
    if not player then return end
    local missileId = missile:getId()
    -- Trace only: does this client deliver missile events at all, and which ids leave the player?
    S.seen = (S.seen or 0) + 1
    if samePosition(missile:getSource(), player:getPosition()) then
      S.seenOwn = (S.seenOwn or 0) + 1
      S.lastOwnId = missileId
      if S.seenOwn <= 6 and RinoConsole and RinoConsole.valid and RinoConsole.valid() then
        local destination = missile:getDestination()
        local current = g_game.getAttackingCreature()
        local target = current and current:getPosition()
        pcall(RinoConsole.log, 'action', 'TargetBot', 'Flechas: proyectil propio id ' .. tostring(missileId) ..
          (projectiles[missileId] and ' (conocido)' or ' (DESCONOCIDO)'),
          'destino ' .. (destination and (destination.x .. ',' .. destination.y) or '?') ..
          ' | objetivo ' .. (target and (target.x .. ',' .. target.y) or '?') ..
          ' | coincide: ' .. tostring(samePosition(destination, target)))
      end
    end
    if not targetId or not TargetBot.isOn or not TargetBot.isOn() then return end
    if not projectiles[missileId] then
      -- A projectile leaving the player with an id this list does not know: on a client with
      -- other distance-effect ids the lock would wait for a shot it can never recognise.
      if not S.unknownLogged[missileId] and samePosition(missile:getSource(), player:getPosition()) then
        S.unknownLogged[missileId] = true
        shotLog('Flechas: sale un proyectil con id ' .. tostring(missileId) .. ' que el bloqueo de disparo no conoce',
          'si es la flecha, hay que anadir ese id a la lista de shot_lock.lua')
      end
      return
    end
    local current=g_game.getAttackingCreature()
    if not current or current:getId()~=targetId then return end
    local source,destination=missile:getSource(),missile:getDestination()
    if not samePosition(source,player:getPosition()) then return end
    local recent=observedAt and now and now-observedAt<=300
    local previousRecent=previousAt and now and now-previousAt<=300
    if samePosition(destination,current:getPosition()) or
        (recent and samePosition(destination,lastPosition)) or
        (previousRecent and samePosition(destination,previousPosition)) then
      fired=true
    end
  end)
end
