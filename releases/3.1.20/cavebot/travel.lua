CaveBot.Extensions.Travel = {}

-- A trip is finished only when the character really is somewhere else.
-- Until then this waypoint is held and the conversation is repeated, so the
-- route can never continue in the wrong city. The action never returns false.
local FAST_ATTEMPTS = 3      -- conversations before slowing down
local SLOW_RETRY_MS = 15000  -- pause between conversations after that
local NPC_REACH = 3          -- SQM within which the NPC hears the greeting
local MISSING_RESYNC_MS = 10000 -- NPC out of sight this long: look for the route's real position
local state = nil

local function log(message, detail)
  if RinoConsole and type(RinoConsole.log) == "function" then
    pcall(RinoConsole.log, "action", "CaveBot", "Travel: " .. message, detail)
  end
end

-- true only the first time a key is seen during this visit to the waypoint
local function first(key)
  state.seen = state.seen or {}
  if state.seen[key] then return false end
  state.seen[key] = true
  return true
end

local function distance(a, b)
  return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

-- Creature with that name (case-insensitive, NPCs preferred) and the NPC names in view.
local function findNpc(name)
  local wanted, found, foundIsNpc, visible = name:lower(), nil, false, {}
  for _, spec in pairs(getSpectators()) do
    local okName, specName = pcall(function() return spec:getName() end)
    local okNpc, isNpc = pcall(function() return spec:isNpc() end)
    isNpc = okNpc and isNpc == true
    if okName and type(specName) == "string" then
      if isNpc then visible[#visible + 1] = specName end
      if specName:lower() == wanted and (not found or (isNpc and not foundIsNpc)) then
        found, foundIsNpc = spec, isNpc
      end
    end
  end
  return found, visible
end

-- Another floor, far away, or a few SQM away with the NPC out of sight.
local function traveled(origin, pos, npcVisible)
  if not origin or not pos then return false end
  if origin.z ~= pos.z then return true end
  local moved = distance(origin, pos)
  return moved >= 15 or (moved >= 5 and not npcVisible)
end

CaveBot.Extensions.Travel.setup = function()
  -- Remember what the NPC answered, to explain a failed trip.
  if type(onTalk) == "function" then
    onTalk(function(name, level, mode, text)
      if state and state.sentAt and type(name) == "string" and type(text) == "string" and
          name:lower() == state.npc then
        state.lastReply = text
      end
    end)
  end

  CaveBot.registerAction("Travel", "#db5a5a", function(value, retries)
    local data = string.split(value, ",")
    local npcName = data[1] and data[1]:trim() or ""
    local dest = data[2] and data[2]:trim() or ""
    local pos = player:getPosition()

    local fresh = retries == 0 or not state or state.value ~= value
    if fresh then state = {value = value, attempts = 0, npc = npcName:lower()} end

    if #data < 2 or npcName == "" or dest == "" then
      if first("value") then
        warn("CaveBot[Travel]: valor incorrecto, usa 'NPC, ciudad'. Se mantiene este waypoint.")
      end
      CaveBot.delay(5000)
      return "retry"
    end

    local npc, visible = findNpc(npcName)

    -- The trip may have completed while this action's state was lost
    -- (bot reloaded or route woken up between the conversation and the check).
    if fresh then
      local pending = storage._cavebotTravelPending
      if type(pending) == "table" and pending.value == value and type(pending.at) == "number" and
          os.time() - pending.at <= 20 and traveled(pending, pos, npc ~= nil) then
        storage._cavebotTravelPending = nil
        state = nil
        log("viaje a " .. dest .. " confirmado al reanudar")
        return true
      end
    end

    -- 1) A conversation was sent: has the character moved?
    if state.sentAt then
      if traveled(state.origin, pos, npc ~= nil) then
        log("viaje a " .. dest .. " confirmado" .. (state.attempts > 1 and (" al intento " .. state.attempts) or ""))
        storage._cavebotTravelPending = nil
        state = nil
        CaveBot.delay(500) -- let the new area load before the next waypoint
        return true
      end
      if now - state.sentAt < state.confirmMs then
        CaveBot.delay(250)
        return "retry"
      end
      -- Still in the same place: this attempt failed.
      state.sentAt = nil
      storage._cavebotTravelPending = nil
      local reply = state.lastReply and ("respuesta del NPC: " .. tostring(state.lastReply):sub(1, 120)) or
        "el NPC no respondio"
      log("no se viajo a " .. dest .. " (intento " .. state.attempts .. ")", reply)
      if state.attempts >= FAST_ATTEMPTS then
        state.nextAttemptAt = now + SLOW_RETRY_MS
        if first("failed") then
          warn("CaveBot[Travel]: no se pudo viajar a " .. dest .. " con " .. npcName .. " tras " ..
            state.attempts .. " intentos (" .. reply .. "). Se mantiene este waypoint y se reintenta cada " ..
            (SLOW_RETRY_MS / 1000) .. " s.")
        end
      end
    end

    -- 2) The NPC has to be in sight. Never continue the route without it.
    if not npc then
      state.missingSince = state.missingSince or now
      if now - state.missingSince >= 3000 and first("npc") then
        warn("CaveBot[Travel]: no veo al NPC '" .. npcName .. "'" ..
          (#visible > 0 and (" (NPC a la vista: " .. table.concat(visible, ", ") .. ")") or " (ningun NPC a la vista)") ..
          ". Se mantiene este waypoint; no se continua sin viajar.")
      end
      -- Maybe the character is already past this trip (bot reloaded at the destination):
      -- if it stands next to a waypoint that comes after this one, the route continues
      -- from there. Anywhere else this waypoint is held, as before.
      if now - state.missingSince >= MISSING_RESYNC_MS and CaveBot.resyncRoute and
          (not state.nextResyncAt or now >= state.nextResyncAt) then
        state.nextResyncAt = now + MISSING_RESYNC_MS
        local ok = CaveBot.resyncRoute("Travel: no veo a " .. npcName, {forwardOnly = true})
        if ok then
          storage._cavebotTravelPending = nil
          state = nil
          return true -- the engine continues from the waypoint the route was moved to
        end
      end
      CaveBot.delay(1000)
      return "retry"
    end
    state.missingSince = nil

    -- 3) After repeated failures, space the conversations out.
    if state.nextAttemptAt and now < state.nextAttemptAt then
      CaveBot.delay(500)
      return "retry"
    end

    -- 4) Stand next to the NPC, and stand still, before greeting.
    local npcPos = npc:getPosition()
    if not npcPos then
      CaveBot.delay(250)
      return "retry"
    end
    if npcPos.z ~= pos.z or distance(pos, npcPos) > NPC_REACH then
      state.reachSince = state.reachSince or now
      if now - state.reachSince >= 20000 and first("reach") then
        warn("CaveBot[Travel]: no consigo llegar junto a " .. npcName .. "; se sigue intentando sin avanzar la ruta.")
      end
      CaveBot.GoTo(npcPos)
      CaveBot.delay(250)
      return "retry"
    end
    state.reachSince = nil
    if player:isWalking() then
      CaveBot.delay(150)
      return "retry"
    end

    -- 5) Talk; the next calls verify the result.
    state.attempts = state.attempts + 1
    state.origin = {x = pos.x, y = pos.y, z = pos.z}
    state.sentAt = now
    state.lastReply = nil
    local duration = CaveBot.Travel(dest)
    state.confirmMs = (tonumber(duration) or (tonumber(storage.extras.talkDelay) or 1000) * 3) + 2000
    storage._cavebotTravelPending = {value = value, x = pos.x, y = pos.y, z = pos.z, at = os.time()}
    log("hablando con " .. npcName .. " para ir a " .. dest .. " (intento " .. state.attempts .. ")")
    CaveBot.delay(250)
    return "retry"
  end)

 CaveBot.Editor.registerAction("travel", "travel", {
  value="NPC name, city",
  title="Travel",
  description="NPC, ciudad. Confirma que el viaje ocurrio; si no, reintenta sin avanzar la ruta.",
 })
end
