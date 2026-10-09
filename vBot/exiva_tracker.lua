-- Coordinated exiva tracker for BotServer members.
-- It reads new Server Log entries without replacing client console callbacks.

if not BotServer then
  return
end

local REQUEST_TOPIC = "exiva_req"
local RESULT_TOPIC = "exiva_res"
local CAPABILITY_TOPIC = "exiva_cap"
local CAPABILITY_VERSION = 1
local CAPABILITY_INTERVAL = 5000
local CAPABILITY_TIMEOUT = 30000
local MAX_OBSERVERS = 6
local MEMBER_POSITION_MAX_AGE = 30000
local DAMAGE_LIMIT = 500
local DAMAGE_SAFE_TIME = 2000
local CAST_TIMEOUT = 9000
local CAST_RETRY_INTERVAL = 1400
local AUTOMATIC_TALK_LIFETIME = 30000
local AUTOMATIC_ECHO_DUPLICATE_TIME = 100
local CLOSED_REQUEST_LIFETIME = 60000
local MAX_CAST_ATTEMPTS = 3
local CAPABILITY_DISCOVERY_DELAY = 450
local SESSION_TIMEOUT = 14000
local SESSION_PURGE_TIME = 30000
local ESTIMATE_LIFETIME = 15000
local RECALCULATE_DELAY = 450
local MARKER_UPDATE_INTERVAL = 300
local MAX_GEOMETRY_TESTS = 50000
local UNBOUNDED_SEARCH_RADIUS = 4096
local TAN_22_5 = math.sqrt(2) - 1
local MAIN_MARKER_KEY = "_sabuezoExivaTrackerMarkers"
local CYCLOPEDIA_MARKER_KEY = "_sabuezoExivaTrackerCyclopediaMarkers"
local TARGET_MARKER_IMAGE = (type(configDir) == "string" and configDir or "/bot/pruebas") ..
  "/vBot/map_markers/exiva-target.png"
local GUIDE_DOT_IMAGE = (type(configDir) == "string" and configDir or "/bot/pruebas") ..
  "/vBot/map_markers/exiva-guide-dot.png"
local GUIDE_ARROW_IMAGE = (type(configDir) == "string" and configDir or "/bot/pruebas") ..
  "/vBot/map_markers/exiva-guide-arrows.png"
local GUIDE_ARROW_SIZE = 17
local GUIDE_ARROW_DIRECTIONS = 16
local GUIDE_EDGE_MARGIN = 12
local GUIDE_MAX_DOTS = 40
local GUIDE_MAX_ARROWS = 6
local LARGE_MAP_MIN_WIDTH = 560
local LARGE_MAP_MIN_HEIGHT = 360
local LARGE_MAP_SETTLE_TIME = 180

BotServer._exivaTrackerGeneration = (BotServer._exivaTrackerGeneration or 0) + 1
local generation = BotServer._exivaTrackerGeneration
local registeredSocket = nil
local sessions = {}
local latestSessions = {}
local queuedCasts = {}
local pendingCasts = {}
local estimates = {}
local trackerMembers = {}
local processedMessages = setmetatable({}, {__mode = "k"})
local consoleInitialized = false
local lastServerLogTab = nil
local lastLargeDamageAt = 0
local previousTracker = vBot and vBot.ExivaTracker
BotServer._exivaAutomaticTalks = BotServer._exivaAutomaticTalks or {}
BotServer._exivaAutomaticEchoes = BotServer._exivaAutomaticEchoes or {}
BotServer._exivaClosedRequests = BotServer._exivaClosedRequests or {}
local automaticTalks = BotServer._exivaAutomaticTalks
local automaticEchoes = BotServer._exivaAutomaticEchoes
local closedRequests = BotServer._exivaClosedRequests
local nextMarkerUpdateAt = 0
local lastCapabilitySentAt = 0

local function clockMillis()
  if g_clock and g_clock.millis then return g_clock.millis() end
  return now or 0
end

local function activeGeneration()
  return BotServer and BotServer._exivaTrackerGeneration == generation
end

local function trim(value)
  return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function normalizedName(value)
  return trim(value):lower()
end

local function safeId(value)
  local result = normalizedName(value):gsub("[^%w%-_]", "_")
  return result ~= "" and result or "unknown"
end

local function selfName()
  local ok, value = pcall(function()
    if player and player.getName then return player:getName() end
    if type(name) == "function" then return name() end
  end)
  return ok and value and value ~= "" and value or "Unknown"
end

local function copyPosition(value)
  if type(value) ~= "table" then return nil end
  local x, y, z = tonumber(value.x), tonumber(value.y), tonumber(value.z)
  if not x or not y or not z then return nil end
  return {x = math.floor(x), y = math.floor(y), z = math.floor(z)}
end

local function currentPosition()
  local ok, value = pcall(function()
    return player and player.getPosition and player:getPosition() or nil
  end)
  return ok and copyPosition(value) or nil
end

local function positionKey(value)
  return value and table.concat({value.x, value.y, value.z}, ",") or ""
end

-- Correlate every automatic spell with its own speech acknowledgement.
-- These tickets survive bot reloads so an in-flight echo cannot start a search.
local function pruneAutomaticTalks(current)
  for target, tickets in pairs(automaticTalks) do
    for index = #tickets, 1, -1 do
      if current > tickets[index].expiresAt then table.remove(tickets, index) end
    end
    if #tickets == 0 then automaticTalks[target] = nil end
  end
  for target, echo in pairs(automaticEchoes) do
    if current - echo.receivedAt > AUTOMATIC_ECHO_DUPLICATE_TIME then automaticEchoes[target] = nil end
  end
  for id, expiresAt in pairs(closedRequests) do
    if current > expiresAt then closedRequests[id] = nil end
  end
end

local function rememberAutomaticTalk(sessionId, target)
  local key = normalizedName(target)
  local ticket = {sessionId = sessionId, expiresAt = clockMillis() + AUTOMATIC_TALK_LIFETIME}
  automaticTalks[key] = automaticTalks[key] or {}
  table.insert(automaticTalks[key], ticket)
  return ticket
end

local function forgetAutomaticTalk(target, ticket)
  local key = normalizedName(target)
  local tickets = automaticTalks[key] or {}
  for index = #tickets, 1, -1 do
    if tickets[index] == ticket then table.remove(tickets, index) end
  end
  if #tickets == 0 then automaticTalks[key] = nil end
end

local function consumeAutomaticTalk(target, signature)
  local current = clockMillis()
  pruneAutomaticTalks(current)
  local key = normalizedName(target)
  local tickets = automaticTalks[key]
  if tickets and #tickets > 0 then
    local ticket = table.remove(tickets, 1)
    if #tickets == 0 then automaticTalks[key] = nil end
    automaticEchoes[key] = {receivedAt = current, signature = signature}
    return true, ticket.sessionId
  end
  local echo = automaticEchoes[key]
  -- Some clients deliver the same speech callback twice in the same frame.
  -- Only deduplicate an acknowledged automatic command, for a short interval.
  return echo and echo.signature == signature and
    current - echo.receivedAt <= AUTOMATIC_ECHO_DUPLICATE_TIME or false
end

local function completeRemoteCast(sessionId)
  local session = sessions[sessionId]
  if session then session.remoteCastDone = true end
  queuedCasts[sessionId] = nil
  closedRequests[sessionId] = clockMillis() + CLOSED_REQUEST_LIFETIME
end

local function cancelSessionCasts(remoteOnly)
  for id, session in pairs(sessions) do
    if not session.castCancelled and
      (not remoteOnly or normalizedName(session.coordinator) ~= normalizedName(selfName())) then
      session.castCancelled = true
      completeRemoteCast(id)
      pendingCasts[id] = nil
    end
  end
end

-- Old remote sessions were interrupted by this reload, never resume their casts.
if previousTracker and type(previousTracker.getSessions) == "function" then
  local ok, previousSessions = pcall(previousTracker.getSessions)
  if ok and type(previousSessions) == "table" then
    for id, session in pairs(previousSessions) do
      if normalizedName(session.coordinator) ~= normalizedName(selfName()) then
        closedRequests[id] = clockMillis() + CLOSED_REQUEST_LIFETIME
      end
    end
  end
end

local function trackerEnabled()
  if type(BotServer.isExivaTrackerEnabled) == "function" then
    local ok, enabled = pcall(BotServer.isExivaTrackerEnabled)
    return ok and enabled == true
  end
  local config = storage and storage.BOTserver
  return type(config) == "table" and config.enabled == true and
    config.exivaTracker == true
end

local function botServerReady()
  return trackerEnabled() and BotServer._websocket and
    type(BotServer.send) == "function" and type(BotServer.listen) == "function"
end

local function sendBotServer(topic, message)
  if not botServerReady() then return false end
  local ok, result = pcall(function() return BotServer.send(topic, message) end)
  return ok and result ~= false
end

local function sendCapability(force, requestReply)
  if not botServerReady() then return false end
  local current = clockMillis()
  if not force and current - lastCapabilitySentAt < CAPABILITY_INTERVAL then
    return false
  end
  lastCapabilitySentAt = current
  trackerMembers[normalizedName(selfName())] = current
  return sendBotServer(CAPABILITY_TOPIC, {
    name = selfName(),
    version = CAPABILITY_VERSION,
    requestReply = requestReply == true
  })
end

local function parseExivaCommand(text)
  text = trim(text)
  if not text:lower():match("^exiva%s+") then return nil end
  local target = trim(text:sub((text:lower():find("exiva", 1, true) or 0) + 6))
  target = target:gsub('^"', ""):gsub('"$', "")
  return target ~= "" and target or nil
end

local DIRECTIONS = {
  "north-east", "south-east", "south-west", "north-west",
  "north", "south", "east", "west"
}

local function directionFromText(text)
  for _, direction in ipairs(DIRECTIONS) do
    if text:find(direction, 1, true) then return direction end
  end
  return nil
end

local function parseExivaResponse(text, target)
  local cleaned = trim(text):gsub("%s+", " ")
  local lower = cleaned:lower()
  local prefix = normalizedName(target) .. " is "
  if lower:sub(1, #prefix) ~= prefix then return nil end

  local body = lower:sub(#prefix + 1):gsub("[%s%.!]+$", "")
  local result = {text = cleaned, floor = "unknown"}

  if body:find("standing next to you", 1, true) then
    result.minDistance, result.maxDistance, result.floor = 0, 4, "same"
    return result
  end
  if body:find("above you", 1, true) then
    result.minDistance, result.maxDistance, result.floor = 0, 4, "higher"
    return result
  end
  if body:find("below you", 1, true) then
    result.minDistance, result.maxDistance, result.floor = 0, 4, "lower"
    return result
  end

  result.direction = directionFromText(body)
  if not result.direction then return nil end

  if body:find("very far", 1, true) then
    result.minDistance, result.maxDistance = 251, nil
    return result
  end
  if body:find("far to the", 1, true) then
    result.minDistance, result.maxDistance = 101, 250
    return result
  end
  if body:find("higher level", 1, true) then
    result.minDistance, result.maxDistance, result.floor = 5, 100, "higher"
    return result
  end
  if body:find("lower level", 1, true) then
    result.minDistance, result.maxDistance, result.floor = 5, 100, "lower"
    return result
  end
  if body:find("to the", 1, true) then
    result.minDistance, result.maxDistance, result.floor = 5, 100, "same"
    return result
  end
  return nil
end

local function directionForDelta(dx, dy)
  local ax, ay = math.abs(dx), math.abs(dy)
  if ax == 0 and ay == 0 then return nil end
  if ay <= ax * TAN_22_5 then return dx > 0 and "east" or "west" end
  if ax <= ay * TAN_22_5 then return dy > 0 and "south" or "north" end
  if dx > 0 then return dy > 0 and "south-east" or "north-east" end
  return dy > 0 and "south-west" or "north-west"
end

local function floorMatches(targetZ, observation)
  local observerZ = observation.observerPos.z
  if observation.floor == "same" then return targetZ == observerZ end
  if observation.floor == "higher" then return targetZ < observerZ end
  if observation.floor == "lower" then return targetZ > observerZ end
  return true
end

local function observationMatches(x, y, z, observation)
  if not floorMatches(z, observation) then return false end
  local dx = x - observation.observerPos.x
  local dy = y - observation.observerPos.y
  local distance = math.max(math.abs(dx), math.abs(dy))
  if distance < observation.minDistance then return false end
  if observation.maxDistance and distance > observation.maxDistance then return false end
  if observation.direction and directionForDelta(dx, dy) ~= observation.direction then
    return false
  end
  return true
end

local function allObservationsMatch(x, y, z, observations)
  for _, observation in ipairs(observations) do
    if not observationMatches(x, y, z, observation) then return false end
  end
  return true
end

local function hasEntries(value)
  for _ in pairs(value or {}) do return true end
  return false
end

local function observationsFromSession(session)
  local observations = {}
  for _, observation in pairs(session.observations or {}) do
    if observation.observerPos and observation.minDistance then
      table.insert(observations, observation)
    end
  end
  table.sort(observations, function(left, right)
    return normalizedName(left.observer) < normalizedName(right.observer)
  end)
  return observations
end

local function solveObservations(observations)
  if type(observations) ~= "table" or #observations == 0 then return nil end

  local minX, maxX, minY, maxY
  local unbounded = true
  local observerMinX, observerMaxX, observerMinY, observerMaxY
  for _, observation in ipairs(observations) do
    local pos = observation.observerPos
    observerMinX = not observerMinX and pos.x or math.min(observerMinX, pos.x)
    observerMaxX = not observerMaxX and pos.x or math.max(observerMaxX, pos.x)
    observerMinY = not observerMinY and pos.y or math.min(observerMinY, pos.y)
    observerMaxY = not observerMaxY and pos.y or math.max(observerMaxY, pos.y)
    if observation.maxDistance then
      unbounded = false
      local radius = observation.maxDistance
      minX = not minX and pos.x - radius or math.max(minX, pos.x - radius)
      maxX = not maxX and pos.x + radius or math.min(maxX, pos.x + radius)
      minY = not minY and pos.y - radius or math.max(minY, pos.y - radius)
      maxY = not maxY and pos.y + radius or math.min(maxY, pos.y + radius)
    end
  end

  if unbounded then
    minX, maxX = observerMinX - UNBOUNDED_SEARCH_RADIUS,
      observerMaxX + UNBOUNDED_SEARCH_RADIUS
    minY, maxY = observerMinY - UNBOUNDED_SEARCH_RADIUS,
      observerMaxY + UNBOUNDED_SEARCH_RADIUS
  end
  minX, maxX = math.max(0, minX), math.min(65535, maxX)
  minY, maxY = math.max(0, minY), math.min(65535, maxY)
  if minX > maxX or minY > maxY then return nil end

  local floors = {}
  for z = 0, 15 do
    local allowed = true
    for _, observation in ipairs(observations) do
      if not floorMatches(z, observation) then allowed = false break end
    end
    if allowed then table.insert(floors, z) end
  end
  if #floors == 0 then return nil end

  local width = maxX - minX + 1
  local height = maxY - minY + 1
  local tests = width * height * #floors
  local step = math.max(1, math.ceil(math.sqrt(tests / MAX_GEOMETRY_TESTS)))
  local statsByFloor = {}

  -- Todos los pisos admitidos ya cumplen las restricciones verticales.
  -- Sus candidatos X/Y son identicos: recorrer la cuadricula una sola vez.
  local scanZ = floors[1]
  local sharedStats = {count = 0, sumX = 0, sumY = 0}
  for x = minX, maxX, step do
    for y = minY, maxY, step do
      if allObservationsMatch(x, y, scanZ, observations) then
        sharedStats.count = sharedStats.count + 1
        sharedStats.sumX = sharedStats.sumX + x
        sharedStats.sumY = sharedStats.sumY + y
        sharedStats.minX = not sharedStats.minX and x or math.min(sharedStats.minX, x)
        sharedStats.maxX = not sharedStats.maxX and x or math.max(sharedStats.maxX, x)
        sharedStats.minY = not sharedStats.minY and y or math.min(sharedStats.minY, y)
        sharedStats.maxY = not sharedStats.maxY and y or math.max(sharedStats.maxY, y)
      end
    end
  end

  if sharedStats.count == 0 and step > 1 and
    tests <= MAX_GEOMETRY_TESTS * 4 then
    step = 1
    for x = minX, maxX do
      for y = minY, maxY do
        if allObservationsMatch(x, y, scanZ, observations) then
          sharedStats.count = sharedStats.count + 1
          sharedStats.sumX = sharedStats.sumX + x
          sharedStats.sumY = sharedStats.sumY + y
          sharedStats.minX = not sharedStats.minX and x or math.min(sharedStats.minX, x)
          sharedStats.maxX = not sharedStats.maxX and x or math.max(sharedStats.maxX, x)
          sharedStats.minY = not sharedStats.minY and y or math.min(sharedStats.minY, y)
          sharedStats.maxY = not sharedStats.maxY and y or math.max(sharedStats.maxY, y)
        end
      end
    end
  end
  if sharedStats.count == 0 then return nil end
  for _, z in ipairs(floors) do statsByFloor[z] = sharedStats end

  local selfPos = currentPosition()
  local selectedZ = selfPos and statsByFloor[selfPos.z] and selfPos.z or nil
  if not selectedZ then
    local bestCount = -1
    for z, stats in pairs(statsByFloor) do
      if stats.count > bestCount then selectedZ, bestCount = z, stats.count end
    end
  end
  local stats = statsByFloor[selectedZ]
  local averageX = stats.sumX / stats.count
  local averageY = stats.sumY / stats.count
  local centerX = math.floor(averageX + 0.5)
  local centerY = math.floor(averageY + 0.5)

  if not allObservationsMatch(centerX, centerY, selectedZ, observations) then
    local bestDistance = math.huge
    for x = minX, maxX, step do
      for y = minY, maxY, step do
        if allObservationsMatch(x, y, selectedZ, observations) then
          local distance = (x - averageX) * (x - averageX) +
            (y - averageY) * (y - averageY)
          if distance < bestDistance then
            bestDistance, centerX, centerY = distance, x, y
          end
        end
      end
    end
  end

  local validFloors = {}
  for z in pairs(statsByFloor) do table.insert(validFloors, z) end
  table.sort(validFloors)
  local rangeWidth = stats.maxX - stats.minX
  local rangeHeight = stats.maxY - stats.minY
  return {
    position = {x = centerX, y = centerY, z = selectedZ},
    minX = math.max(minX, stats.minX - step + 1),
    maxX = math.min(maxX, stats.maxX + step - 1),
    minY = math.max(minY, stats.minY - step + 1),
    maxY = math.min(maxY, stats.maxY + step - 1),
    floors = validFloors,
    responseCount = #observations,
    precision = math.ceil(math.max(rangeWidth, rangeHeight) / 2) + step - 1,
    sampleStep = step,
    unbounded = unbounded
  }
end

local function makeSessionId()
  return table.concat({
    safeId(selfName()), tostring(os.time()), tostring(clockMillis()),
    tostring(math.random(1000, 9999))
  }, ":")
end

local function selectedContains(selected, wantedName)
  local wanted = normalizedName(wantedName)
  if type(selected) ~= "table" then return false end
  for key, value in pairs(selected) do
    local candidate = type(value) == "string" and value or
      (type(key) == "string" and key or nil)
    if candidate and normalizedName(candidate) == wanted then return true end
  end
  return false
end

local function chebyshev(left, right)
  return math.max(math.abs(left.x - right.x), math.abs(left.y - right.y))
end

local function selectObservers()
  local selfPos = currentPosition()
  if not selfPos then return {}, nil end
  local ownName = selfName()
  local capabilityTime = clockMillis()
  trackerMembers[normalizedName(ownName)] = capabilityTime
  local candidates = {{name = ownName, pos = selfPos}}
  local known = {[normalizedName(ownName)] = true}
  local snapshot = {}
  if type(BotServer.getMemberSnapshot) == "function" then
    local ok, result = pcall(BotServer.getMemberSnapshot)
    if ok and type(result) == "table" then snapshot = result end
  end

  local current = now or clockMillis()
  for memberName, info in pairs(snapshot) do
    local key = normalizedName(memberName)
    local pos = info and copyPosition(info.pos)
    local age = info and info.lastSeen and current - info.lastSeen or 0
    local trackerAge = trackerMembers[key] and
      capabilityTime - trackerMembers[key] or math.huge
    if not known[key] and pos and age <= MEMBER_POSITION_MAX_AGE and
      trackerAge <= CAPABILITY_TIMEOUT then
      known[key] = true
      table.insert(candidates, {name = memberName, pos = pos})
    end
  end
  table.sort(candidates, function(left, right)
    if normalizedName(left.name) == normalizedName(ownName) then return true end
    if normalizedName(right.name) == normalizedName(ownName) then return false end
    return normalizedName(left.name) < normalizedName(right.name)
  end)

  local selected = {candidates[1]}
  local used = {[normalizedName(candidates[1].name)] = true}
  while #selected < math.min(MAX_OBSERVERS, #candidates) do
    local best, bestDistance
    for _, candidate in ipairs(candidates) do
      if not used[normalizedName(candidate.name)] then
        local minimum = math.huge
        for _, chosen in ipairs(selected) do
          minimum = math.min(minimum, chebyshev(candidate.pos, chosen.pos))
        end
        if not best or minimum > bestDistance then
          best, bestDistance = candidate, minimum
        end
      end
    end
    if not best then break end
    used[normalizedName(best.name)] = true
    table.insert(selected, best)
  end

  local names = {}
  for _, candidate in ipairs(selected) do table.insert(names, candidate.name) end
  return names, selfPos
end

local function newSession(message)
  local current = clockMillis()
  local session = {
    id = tostring(message.id),
    target = trim(message.target),
    coordinator = trim(message.coordinator),
    selected = message.selected or {},
    createdAt = current,
    expiresAt = current + SESSION_TIMEOUT,
    purgeAt = current + SESSION_PURGE_TIME,
    observations = {},
    recalculateAt = nil
  }
  sessions[session.id] = session
  latestSessions[normalizedName(session.target)] = session.id
  return session
end

local function addObservation(session, observer, message)
  if not session or session.castCancelled or clockMillis() > session.expiresAt or
    latestSessions[normalizedName(session.target)] ~= session.id or
    type(message) ~= "table" then return false end
  local observerPos = copyPosition(message.observerPos)
  local minDistance = tonumber(message.minDistance)
  if not observerPos or not minDistance then return false end
  local observation = {
    observer = trim(observer),
    observerPos = observerPos,
    minDistance = minDistance,
    maxDistance = tonumber(message.maxDistance),
    direction = message.direction,
    floor = message.floor or "unknown",
    text = trim(message.text),
    receivedAt = clockMillis()
  }
  local previous = session.observations[normalizedName(observer)]
  if previous and positionKey(previous.observerPos) == positionKey(observation.observerPos) and
    previous.minDistance == observation.minDistance and previous.maxDistance == observation.maxDistance and
    previous.direction == observation.direction and previous.floor == observation.floor and
    previous.text == observation.text then return false end
  session.observations[normalizedName(observer)] = observation
  session.recalculateAt = clockMillis() + RECALCULATE_DELAY
  return true
end

local function publishObservation(session, parsed, observerPos)
  if not session or not parsed or not observerPos then return end
  local message = {
    id = session.id,
    target = session.target,
    coordinator = session.coordinator,
    observer = selfName(),
    observerPos = observerPos,
    minDistance = parsed.minDistance,
    maxDistance = parsed.maxDistance,
    direction = parsed.direction,
    floor = parsed.floor,
    text = parsed.text,
    responseTime = os.time()
  }
  addObservation(session, selfName(), message)
  sendBotServer(RESULT_TOPIC, message)
end

local function beginManualSession(target)
  if not trackerEnabled() then return end
  sendCapability(true, true)
  local selected, observerPos = selectObservers()
  if not observerPos then return end

  local message = {
    id = makeSessionId(),
    target = target,
    coordinator = selfName(),
    selected = selected,
    requestTime = os.time()
  }
  local session = newSession(message)
  session.requestSocket = BotServer._websocket
  pendingCasts[session.id] = {
    target = target,
    observerPos = observerPos,
    castAt = clockMillis(),
    expiresAt = clockMillis() + CAST_TIMEOUT
  }

  sendBotServer(REQUEST_TOPIC, message)
  schedule(CAPABILITY_DISCOVERY_DELAY, function()
    if not activeGeneration() or not trackerEnabled() then return end
    local currentSession = sessions[session.id]
    if not currentSession or currentSession.castCancelled or
      clockMillis() > currentSession.expiresAt or
      currentSession.requestSocket ~= BotServer._websocket then return end

    local refreshed = selectObservers()
    currentSession.selected = refreshed
    sendBotServer(REQUEST_TOPIC, {
      id = currentSession.id,
      target = currentSession.target,
      coordinator = currentSession.coordinator,
      selected = refreshed,
      requestTime = os.time()
    })
  end)
end

local function queueRemoteCast(session)
  if not session or session.remoteCastDone or session.castCancelled or
    closedRequests[session.id] or clockMillis() > session.expiresAt or
    session.observations[normalizedName(selfName())] or
    pendingCasts[session.id] or queuedCasts[session.id] then return end
  queuedCasts[session.id] = {
    sessionId = session.id,
    target = session.target,
    expiresAt = session.expiresAt,
    requestSocket = BotServer._websocket,
    attempts = 0,
    nextAttemptAt = 0
  }
end

local function castQueuedExiva(entry)
  local session = sessions[entry.sessionId]
  local observerPos = currentPosition()
  if not session or not observerPos or session.castCancelled or session.remoteCastDone or
    not botServerReady() or entry.requestSocket ~= BotServer._websocket or
    clockMillis() > session.expiresAt then return false end

  local current = clockMillis()
  entry.attempts = (tonumber(entry.attempts) or 0) + 1
  entry.lastAttemptAt = current
  entry.nextAttemptAt = current + CAST_RETRY_INTERVAL
  pendingCasts[entry.sessionId] = {
    automatic = true,
    target = entry.target,
    observerPos = observerPos,
    castAt = current,
    expiresAt = current + CAST_TIMEOUT
  }
  local ticket = rememberAutomaticTalk(entry.sessionId, entry.target)

  local command = 'exiva "' .. entry.target:gsub('"', "") .. '"'
  local ok, result = pcall(function()
    if type(say) == "function" then
      return say(command)
    elseif g_game and type(g_game.talk) == "function" then
      return g_game.talk(command)
    else
      error("talk unavailable")
    end
  end)
  if not ok or result == false then
    forgetAutomaticTalk(entry.target, ticket)
    pendingCasts[entry.sessionId] = nil
    entry.nextAttemptAt = current + 500
    return false
  end
  return true
end

local function flattenConsoleText(value)
  if type(value) == "string" then return value end
  if type(value) ~= "table" then return tostring(value or "") end
  local parts = {}
  for _, part in ipairs(value) do
    if type(part) == "string" and not part:match("^#%x%x%x%x%x%x%x?%x?$") then
      table.insert(parts, part)
    end
  end
  return table.concat(parts)
end

local function processDamageText(text)
  local lower = text:lower()
  local amount = lower:match("you lose ([%d,]+) hitpoints") or
    lower:match("you lost ([%d,]+) hitpoints") or
    lower:match("you were hit for ([%d,]+) hitpoints")
  if amount then
    amount = amount:gsub(",", "")
    amount = tonumber(amount)
  end
  if amount and amount > DAMAGE_LIMIT then lastLargeDamageAt = clockMillis() end
end

local function processResponseText(text)
  local bestId, bestCastAt, bestParsed
  for sessionId, pending in pairs(pendingCasts) do
    if clockMillis() <= pending.expiresAt then
      local parsed = parseExivaResponse(text, pending.target)
      if parsed and (not bestCastAt or pending.castAt > bestCastAt) then
        bestId, bestCastAt, bestParsed = sessionId, pending.castAt, parsed
      end
    end
  end
  if not bestId then return end
  local pending = pendingCasts[bestId]
  pendingCasts[bestId] = nil
  if pending.automatic then completeRemoteCast(bestId) else queuedCasts[bestId] = nil end
  publishObservation(sessions[bestId], bestParsed, pending.observerPos)
end

local function processConsoleText(text)
  text = trim(text)
  if text == "" then return end
  processDamageText(text)
  processResponseText(text)
end

local function unchangedConsoleMessage(message, cached)
  if not cached or cached.timestamp ~= message.timestamp or
      cached.mode ~= message.mode or cached.name ~= message.name or
      cached.text ~= message.text then return false end
  if type(message.text) == "table" then
    if #message.text ~= #cached.parts then return false end
    for index, part in ipairs(message.text) do
      if cached.parts[index] ~= part then return false end
    end
  end
  return true
end

local function cacheConsoleMessage(message, signature)
  local cached = {
    timestamp = message.timestamp, mode = message.mode,
    name = message.name, text = message.text, signature = signature
  }
  if type(message.text) == "table" then
    cached.parts = {}
    for index, part in ipairs(message.text) do cached.parts[index] = part end
  end
  processedMessages[message] = cached
end

local function pollServerLog()
  local gameConsole = modules and modules.game_console
  local chat = gameConsole and gameConsole.g_chat or g_chat
  if not chat or type(chat.getTabByName) ~= "function" then return end
  local ok, tab = pcall(function() return chat:getTabByName("Server Log") end)
  if not ok or not tab or type(tab.messages) ~= "table" then return end
  if lastServerLogTab ~= tab then
    lastServerLogTab = tab
    processedMessages = setmetatable({}, {__mode = "k"})
    consoleInitialized = false
  end

  local first = math.max(1, #tab.messages - 39)
  for index = first, #tab.messages do
    local message = tab.messages[index]
    local cached = type(message) == "table" and processedMessages[message] or nil
    if type(message) == "table" and tonumber(message.timestamp or 0) > 0 and
        not unchangedConsoleMessage(message, cached) then
      local text = flattenConsoleText(message.text)
      local signature = table.concat({
        tostring(message.timestamp or 0), tostring(message.mode or 0),
        tostring(message.name or ""), text
      }, "|")
      cacheConsoleMessage(message, signature)
      if not cached or cached.signature ~= signature then
        if consoleInitialized then processConsoleText(text) end
      end
    end
  end
  consoleInitialized = true
end

local function registerBotServerListeners()
  if not botServerReady() then return false end
  local socket = BotServer._websocket
  if registeredSocket == socket then return true end
  if registeredSocket then cancelSessionCasts(true) end
  registeredSocket = socket
  local listenerSocket = socket
  trackerMembers = {[normalizedName(selfName())] = clockMillis()}
  lastCapabilitySentAt = 0

  local capabilityOk = BotServer.listen(CAPABILITY_TOPIC, function(sender, message)
    if not activeGeneration() or BotServer._websocket ~= listenerSocket or
      not trackerEnabled() or type(message) ~= "table" then return end
    local memberName = trim(message.name) ~= "" and message.name or sender
    if trim(sender) ~= "" and normalizedName(memberName) ~=
      normalizedName(sender) then return end
    if tonumber(message.version) ~= CAPABILITY_VERSION then return end
    trackerMembers[normalizedName(memberName)] = clockMillis()
    if message.requestReply == true then sendCapability(true, false) end
  end)

  local requestOk = BotServer.listen(REQUEST_TOPIC, function(sender, message)
    if not activeGeneration() or BotServer._websocket ~= listenerSocket or
      not trackerEnabled() or type(message) ~= "table" then return end
    if type(message.id) ~= "string" or type(message.target) ~= "string" or
      trim(message.target) == "" or type(message.coordinator) ~= "string" or
      trim(message.coordinator) == "" or normalizedName(sender) ~=
      normalizedName(message.coordinator) or closedRequests[message.id] then return end
    if normalizedName(message.coordinator) == normalizedName(selfName()) then return end

    local session = sessions[message.id] or newSession(message)
    if session.castCancelled or session.remoteCastDone or clockMillis() > session.expiresAt or
      normalizedName(session.target) ~= normalizedName(message.target) or
      normalizedName(session.coordinator) ~= normalizedName(message.coordinator) then return end
    session.selected = message.selected or {}
    if selectedContains(session.selected, selfName()) then
      queueRemoteCast(session)
    else
      queuedCasts[session.id] = nil
    end
  end)

  local resultOk = BotServer.listen(RESULT_TOPIC, function(sender, message)
    if not activeGeneration() or BotServer._websocket ~= listenerSocket or
      not trackerEnabled() or type(message) ~= "table" then return end
    if type(message.id) ~= "string" or trim(message.target) == "" then return end
    local observer = trim(sender) ~= "" and sender or message.observer
    if trim(message.observer) ~= "" and
      normalizedName(observer) ~= normalizedName(message.observer) then return end
    local session = sessions[message.id]
    if not session or session.castCancelled or clockMillis() > session.expiresAt or
      normalizedName(session.target) ~= normalizedName(message.target) or
      normalizedName(session.coordinator) ~= normalizedName(message.coordinator) then return end
    addObservation(session, observer, message)
  end)

  if capabilityOk == false or requestOk == false or resultOk == false then
    registeredSocket = nil
    return false
  end
  sendCapability(true, true)
  return true
end

local function floorsText(floors)
  local values = {}
  for _, floor in ipairs(floors or {}) do table.insert(values, tostring(floor)) end
  return table.concat(values, ",")
end

local function estimateInitiator(estimate)
  local coordinator = trim(estimate.coordinator)
  return coordinator ~= "" and "Inicio: " .. coordinator or nil
end

local function estimateTooltip(target, estimate)
  local suffix = estimate.unbounded and " (busqueda limitada)" or ""
  return table.concat({
    target,
    estimateInitiator(estimate) or "Inicio: sin datos",
    "Referencia aproximada: " .. positionKey(estimate.position),
    "Recuadro amarillo: limites aproximados de busqueda",
    "Guia punteada: rumbo directo hacia la estimacion",
    "Lectura hace " .. math.max(0, math.floor((clockMillis() - estimate.updatedAt) / 1000)) .. " s",
    "Zona X: " .. estimate.minX .. " - " .. estimate.maxX,
    "Zona Y: " .. estimate.minY .. " - " .. estimate.maxY,
    "Pisos: " .. floorsText(estimate.floors),
    "Respuestas: " .. estimate.responseCount,
    "Precision: +/- " .. estimate.precision .. " sqm" .. suffix
  }, "\n")
end

local function recalculateSession(session)
  session.recalculateAt = nil
  local targetKey = normalizedName(session.target)
  -- An older round must never overwrite or remove a newer round's estimate.
  if latestSessions[targetKey] ~= session.id or session.castCancelled or
    clockMillis() > session.expiresAt then return end
  local observations = observationsFromSession(session)
  if #observations == 0 then return end
  local estimate = solveObservations(observations)
  if not estimate then
    estimates[normalizedName(session.target)] = nil
    return
  end

  -- A point remains a useful reference while fresh readings still allow it.
  -- Recompute the uncertainty area normally; move the point when it is excluded.
  local previous = estimates[targetKey]
  local reference = previous and previous.position
  if reference and previous.expiresAt > clockMillis() and
    reference.x >= estimate.minX and reference.x <= estimate.maxX and
    reference.y >= estimate.minY and reference.y <= estimate.maxY and
    allObservationsMatch(reference.x, reference.y, reference.z, observations) then
    estimate.position = copyPosition(reference)
  end
  estimate.target = session.target
  estimate.coordinator = session.coordinator
  estimate.sessionId = session.id
  local newestReading = 0
  for _, observation in ipairs(observations) do
    newestReading = math.max(newestReading, observation.receivedAt or session.createdAt)
  end
  estimate.updatedAt = newestReading
  estimate.expiresAt = estimate.updatedAt + ESTIMATE_LIFETIME
  estimates[normalizedName(session.target)] = estimate
end

local function connectedMemberNames()
  local names = {}
  if type(BotServer.getMemberSnapshot) ~= "function" then return names end
  local ok, snapshot = pcall(BotServer.getMemberSnapshot)
  if not ok or type(snapshot) ~= "table" then return names end
  local current = now or clockMillis()
  for memberName, info in pairs(snapshot) do
    local age = info and info.lastSeen and current - info.lastSeen or 0
    if age <= 30000 then names[normalizedName(memberName)] = true end
  end
  return names
end

-- A destroyed OTC userdata may crash even when looking up isDestroyed.
-- Record destruction while onDestroy is still valid; later use only Lua keys.
local lifeOwner = (modules and modules.game_minimap) or BotServer
-- OTC can return distinct Lua userdata for the same native widget.
-- Table keys use raw userdata identity, so match native equality explicitly.
local mapLife = lifeOwner._pruebasMapLife
if not mapLife or mapLife.version ~= 2 then
  local dead = mapLife and mapLife.dead or setmetatable({}, {__mode = "k"})
  mapLife = {version = 2, dead = dead, watched = {}, retiredMaps = {}}
  lifeOwner._pruebasMapLife = mapLife

  function mapLife.isDead(widget)
    if not widget then return true end
    for known in pairs(mapLife.dead) do if known == widget then return true end end
    for _, known in ipairs(mapLife.retiredMaps) do if known == widget then return true end end
    return false
  end

  local function callDestroy(callback, ...)
    if type(callback) == "function" then return callback(...) end
    if type(callback) == "table" then
      for _, handler in pairs(callback) do
        if type(handler) == "function" then
          local result = handler(...)
          if result then return result end
        end
      end
    end
  end

  function mapLife.watch(widget, owner, callback)
    if mapLife.isDead(widget) then return false end
    local entry
    for known, watched in pairs(mapLife.watched) do
      if known == widget then entry = watched; break end
    end
    if not entry then
      entry = {widget = widget, callbacks = {}, original = widget.onDestroy}
      mapLife.watched[widget] = entry
      widget.onDestroy = function(self, ...)
        local known = entry.widget
        mapLife.dead[known], mapLife.dead[self] = true, true
        mapLife.watched[known] = nil
        if entry.callbacks.drag or entry.callbacks.exiva or entry.callbacks.dragProfile then
          table.insert(mapLife.retiredMaps, known)
          if #mapLife.retiredMaps > 32 then table.remove(mapLife.retiredMaps, 1) end
        end
        -- Dispose the canonical Lua record, even if self is a fresh userdata.
        for _, dispose in pairs(entry.callbacks) do dispose(known) end
        return callDestroy(entry.original, self, ...)
      end
    end
    if owner and callback then entry.callbacks[owner] = callback end
    return true
  end
end


-- Keep overlay ownership in Lua; obsolete map userdata must never be indexed.
local previousVisualState = BotServer._exivaVisualState
local visualState = previousVisualState
if not visualState or visualState.version ~= 4 then
  visualState = {version = 4, maps = {}, roots = {}, serial = 0}
  BotServer._exivaVisualState = visualState
end

local function uiRoot()
  if not g_ui or type(g_ui.getRootWidget) ~= "function" then return nil end
  return g_ui.getRootWidget()
end

-- Retire pre-v3 overlays using the current UI tree, never their saved handles.
if not previousVisualState or previousVisualState.version ~= 4 then
  local root = uiRoot()
  if root then
    local function retireLegacy(parent)
      for _, child in ipairs(parent:getChildren()) do
        local id = child:getId() or ""
        if id:match("^exivaSearchArea_") or id:match("^exivaGuide_") or
           id:match("^exivaTracker_") then
          child:destroy()
        else
          retireLegacy(child)
        end
      end
    end
    retireLegacy(root)
  end
end

local function canonicalMap(minimap)
  for known in pairs(visualState.maps) do
    if known == minimap then return known end
  end
  return minimap
end

local function mapData(minimap, storageKey)
  minimap = canonicalMap(minimap)
  local owned = visualState.maps[minimap]
  if not owned then owned = {}; visualState.maps[minimap] = owned end
  local data = owned[storageKey]
  if not data then data = {}; owned[storageKey] = data end
  return data
end

local function liveMap(minimap)
  return minimap and not mapLife.isDead(minimap) and minimap or nil
end

local function trackMap(minimap, storageKey)
  if not liveMap(minimap) then return false end
  mapData(minimap, storageKey)
  minimap = canonicalMap(minimap)
  mapLife.watch(minimap, "exiva", function() visualState.maps[minimap] = nil end)
  return true
end

local function watchVisual(widget, prefix)
  if not widget then return nil end
  visualState.serial = visualState.serial + 1
  local id = prefix .. "_" .. tostring(generation) .. "_" .. tostring(visualState.serial)
  widget:setId(id)
  visualState.roots[widget] = {id = id}
  mapLife.watch(widget, "exivaVisual", function() visualState.roots[widget] = nil end)
  return widget
end

local function visualPresent(minimap, widget)
  local record = widget and visualState.roots[widget]
  if not record or mapLife.dead[widget] then return false end
  -- Only the current map is queried; a removed overlay is never inspected.
  return minimap:getChildById(record.id) == widget
end

local function destroyVisual(widget)
  local record = widget and visualState.roots[widget]
  if not record then return end
  local root = uiRoot()
  local current = root and root:recursiveGetChildById(record.id)
  if current then current:destroy() end
  visualState.roots[widget] = nil
  mapLife.dead[widget] = true
end


local function getMainMinimap()
  local minimapModule = modules and modules.game_minimap
  if not minimapModule then return nil end
  if type(minimapModule.getMiniMapUi) == "function" then
    local ok, minimap = pcall(minimapModule.getMiniMapUi)
    if ok and liveMap(minimap) then return minimap end
  end
  return liveMap(minimapModule.minimapWidget)
end

local cachedCyclopediaMinimap = nil
local nextCyclopediaLookupAt = 0
local function getCyclopediaMinimap()
  local mapCyclopedia = modules and modules.game_cyclopedia and
    modules.game_cyclopedia.MapCyclopedia
  if mapCyclopedia and type(mapCyclopedia.getMinimapWidget) == "function" then
    local ok, minimap = pcall(function() return mapCyclopedia.getMinimapWidget() end)
    if ok and minimap then return liveMap(minimap) end
  end

  local current = clockMillis()
  if current < nextCyclopediaLookupAt then
    return liveMap(cachedCyclopediaMinimap)
  end
  nextCyclopediaLookupAt = current + 1000
  cachedCyclopediaMinimap = nil
  local root = g_ui and g_ui.getRootWidget and g_ui.getRootWidget()
  if not root or not root.recursiveGetChildById then return nil end
  local ok, minimap = pcall(function()
    local panel = root:recursiveGetChildById("MapDataPanel")
    return panel and panel:recursiveGetChildById("minimap") or nil
  end)
  cachedCyclopediaMinimap = ok and minimap or nil
  return cachedCyclopediaMinimap
end

local function destroyMapMarkers(minimap, storageKey)
  minimap = minimap and canonicalMap(minimap)
  local owned = minimap and visualState.maps[minimap]
  local data = owned and owned[storageKey]
  if not data then return end
  for _, marker in pairs(data[storageKey] or {}) do
    if marker.widget then pcall(destroyVisual, marker.widget) end
  end
  data[storageKey] = {}
  local areaKey = storageKey .. "_areas"
  for _, area in pairs(data[areaKey] or {}) do
    pcall(destroyVisual, area)
  end
  data[areaKey] = {}
  local guideKey = storageKey .. "_guide"
  local guide = data[guideKey]
  if guide and guide.widget then pcall(destroyVisual, guide.widget) end
  data[guideKey] = nil
  data[storageKey .. "_activity"] = nil
  if owned then
    owned[storageKey] = nil
    if not hasEntries(owned) then visualState.maps[minimap] = nil end
  end
end

-- The rectangle encloses the candidates; it is not an exact target position.
local function minimapProjection(minimap)
  if type(minimap.getTilePosition) ~= "function" or
     type(minimap.getPosition) ~= "function" or
     type(minimap.getSize) ~= "function" then return nil end
  local ok, projection = pcall(function()
    local size, origin = minimap:getSize(), minimap:getPosition()
    local width, height = tonumber(size.width), tonumber(size.height)
    if not width or not height or width < 20 or height < 20 then return nil end
    local cx, cy = math.floor(width / 2), math.floor(height / 2)
    local sx = math.max(8, math.min(32, math.floor(width / 3)))
    local sy = math.max(8, math.min(32, math.floor(height / 3)))
    local function tile(x, y)
      return copyPosition(minimap:getTilePosition({x = origin.x + x, y = origin.y + y}))
    end
    local center = tile(cx, cy)
    local left, right = tile(cx - sx, cy), tile(cx + sx, cy)
    local top, bottom = tile(cx, cy - sy), tile(cx, cy + sy)
    if not center or not left or not right or not top or not bottom then return nil end
    local dx, dy = right.x - left.x, bottom.y - top.y
    if dx <= 0 or dy <= 0 then return nil end
    return {width = width, height = height, cx = cx, cy = cy, center = center,
      originX = origin.x, originY = origin.y,
      scaleX = 2 * sx / dx, scaleY = 2 * sy / dy}
  end)
  return ok and projection or nil
end

-- Keep overlay sprites out of anchor-layout and mouse-event work during panning.
local function setVisualVisible(widget, visible)
  if not widget or mapLife.dead[widget] then return end
  if widget._exivaVisualVisible ~= visible then
    widget:setVisible(visible)
    widget._exivaVisualVisible = visible
  end
end

local function setVisualRect(widget, x, y, width, height)
  if not widget or mapLife.dead[widget] then return end
  x, y, width, height = math.floor(x), math.floor(y), math.floor(width), math.floor(height)
  local old = widget._exivaVisualRect
  if old and old.x == x and old.y == y and old.width == width and old.height == height then return end
  widget:setRect({x = x, y = y, width = width, height = height})
  widget._exivaVisualRect = {x = x, y = y, width = width, height = height}
end

local function estimateOnFloor(estimate, floor)
  for _, z in ipairs(estimate.floors or {estimate.position.z}) do
    if tonumber(z) == tonumber(floor) then return true end
  end
  return false
end

local function createSearchArea(minimap, targetKey)
  local overlay = setupUI([[
Panel
  anchors.fill: parent
  enabled: false
  phantom: true
  focusable: false
  background-color: alpha

  UIWidget
    id: shade
    phantom: true
    focusable: false
    background-color: #ffd34d18

  UIWidget
    id: topEdge
    phantom: true
    focusable: false
    background-color: #ffd34de6

  UIWidget
    id: bottomEdge
    phantom: true
    focusable: false
    background-color: #ffd34de6

  UIWidget
    id: leftEdge
    phantom: true
    focusable: false
    background-color: #ffd34de6

  UIWidget
    id: rightEdge
    phantom: true
    focusable: false
    background-color: #ffd34de6
]], minimap)
  watchVisual(overlay, "exivaSearchArea_" .. safeId(targetKey))
  return overlay
end

local function setSearchAreaPart(widget, x, y, width, height, viewWidth, viewHeight, originX, originY)
  -- Clip each edge separately: do not invent a border at the viewport edge.
  local left, top = math.max(0, x), math.max(0, y)
  local right, bottom = math.min(viewWidth, x + width), math.min(viewHeight, y + height)
  if right <= left or bottom <= top then setVisualVisible(widget, false) return end
  setVisualRect(widget, originX + math.floor(left), originY + math.floor(top),
    math.max(1, math.ceil(right - left)), math.max(1, math.ceil(bottom - top)))
  setVisualVisible(widget, true)
end

local function updateSearchAreas(minimap, storageKey, connectedMembers, projection)
  local areaKey = storageKey .. "_areas"
  mapData(minimap, storageKey)[areaKey] = mapData(minimap, storageKey)[areaKey] or {}
  local areas, desired = mapData(minimap, storageKey)[areaKey], {}
  if projection then
    for targetKey, estimate in pairs(estimates) do
      if estimate.expiresAt > clockMillis() and not connectedMembers[targetKey] and
         estimateOnFloor(estimate, projection.center.z) then
        desired[targetKey] = true
        local area = areas[targetKey]
        if not visualPresent(minimap, area) then
          if area then destroyVisual(area) end
          area = nil
          local ok, value = pcall(createSearchArea, minimap, targetKey)
          if ok then area = value; areas[targetKey] = area end
        end
        if area then
          setVisualVisible(area, true)
          local left = projection.cx + (estimate.minX - projection.center.x - 0.5) * projection.scaleX
          local right = projection.cx + (estimate.maxX - projection.center.x + 0.5) * projection.scaleX
          local top = projection.cy + (estimate.minY - projection.center.y - 0.5) * projection.scaleY
          local bottom = projection.cy + (estimate.maxY - projection.center.y + 0.5) * projection.scaleY
          pcall(function()
            local function part(widget, x, y, width, height)
              setSearchAreaPart(widget, x, y, width, height, projection.width, projection.height,
                projection.originX, projection.originY)
            end
            part(area.shade, left, top, right - left, bottom - top)
            part(area.topEdge, left, top, right - left, 2)
            part(area.bottomEdge, left, bottom - 2, right - left, 2)
            part(area.leftEdge, left, top, 2, bottom - top)
            part(area.rightEdge, right - 2, top, 2, bottom - top)
          end)
        end
      end
    end
  end
  for targetKey, area in pairs(areas) do
    if not desired[targetKey] then
      pcall(destroyVisual, area)
      areas[targetKey] = nil
    end
  end
end


-- Visual direction guide: the destination is an estimate, not a walking route.
local function destroyExivaGuide(minimap, storageKey)
  local key = storageKey .. "_guide"
  local guide = mapData(minimap, storageKey)[key]
  if guide and guide.widget then pcall(destroyVisual, guide.widget) end
  mapData(minimap, storageKey)[key] = nil
end

local function createExivaGuide(minimap, storageKey)
  local overlay = setupUI([[
Panel
  anchors.fill: parent
  enabled: false
  phantom: true
  focusable: false
  background-color: alpha

  Label
    id: caption
    size: 160 32
    text-align: left
    font: verdana-11px-rounded
    color: #ffe38a
    background-color: #141414cc
    phantom: true
    focusable: false
    visible: false
]], minimap)
  watchVisual(overlay, "exivaGuide_" .. safeId(storageKey))
  return {widget = overlay, items = {}, dots = {}, arrows = {}, used = 0,
    dotUsed = 0, arrowUsed = 0, needsRaise = true}
end

local function hideExivaGuide(minimap, storageKey)
  local guide = mapData(minimap, storageKey)[storageKey .. "_guide"]
  if guide and not visualPresent(minimap, guide.widget) then
    destroyExivaGuide(minimap, storageKey)
    return
  end
  if guide then
    setVisualVisible(guide.widget, false)
    guide.renderKey = nil
  end
end

local function guideItem(guide, x, y, direction)
  local pool, index
  if direction == nil then
    guide.dotUsed = guide.dotUsed + 1
    pool, index = guide.dots, guide.dotUsed
  else
    guide.arrowUsed = guide.arrowUsed + 1
    pool, index = guide.arrows, guide.arrowUsed
  end
  local widget = pool[index]
  if not widget then
    widget = g_ui.createWidget("UIWidget", guide.widget)
    widget:setPhantom(true)
    widget:setFocusable(false)
    pool[index] = widget
    guide.needsRaise = true
  end
  guide.used = guide.used + 1
  guide.items[guide.used] = widget
  local size = direction and GUIDE_ARROW_SIZE or 5
  local image = direction and GUIDE_ARROW_IMAGE or GUIDE_DOT_IMAGE
  local imageKey = image .. ":" .. tostring(direction or "dot")
  if widget._exivaGuideImage ~= imageKey then
    if widget._exivaGuideSource ~= image then
      widget:setImageSource(image)
      widget._exivaGuideSource = image
    end
    widget:setImageClip({x = direction and direction * GUIDE_ARROW_SIZE or 0,
      y = 0, width = size, height = size})
    widget._exivaGuideImage = imageKey
  end
  setVisualRect(widget, guide.originX + math.floor(x - size / 2 + 0.5),
    guide.originY + math.floor(y - size / 2 + 0.5), size, size)
  setVisualVisible(widget, true)
  return widget
end

local function finishExivaGuide(guide)
  for i = guide.dotUsed + 1, #guide.dots do setVisualVisible(guide.dots[i], false) end
  for i = guide.arrowUsed + 1, #guide.arrows do setVisualVisible(guide.arrows[i], false) end
  for i = guide.used + 1, #guide.items do guide.items[i] = nil end
  setVisualVisible(guide.widget, true)
  if guide.needsRaise then
    guide.widget:raise()
    for i = 1, guide.arrowUsed do guide.arrows[i]:raise() end
    guide.widget.caption:raise()
    guide.layerVersion = (guide.layerVersion or 0) + 1
    guide.needsRaise = false
  end
end

-- Clip a segment to the viewport. Both ends may be outside after panning.
local function clipGuideSegment(x, y, dx, dy, width, height)
  local first, last = 0, 1
  local function axis(origin, delta, low, high)
    if math.abs(delta) < 0.00001 then return origin >= low and origin <= high end
    local a, b = (low - origin) / delta, (high - origin) / delta
    if a > b then a, b = b, a end
    first, last = math.max(first, a), math.min(last, b)
    return first <= last
  end
  if not axis(x, dx, GUIDE_EDGE_MARGIN, width - GUIDE_EDGE_MARGIN) or
     not axis(y, dy, GUIDE_EDGE_MARGIN, height - GUIDE_EDGE_MARGIN) then return nil end
  return first, last
end

local function guideDirection(dx, dy)
  local selected, best = 0, -math.huge
  for direction = 0, GUIDE_ARROW_DIRECTIONS - 1 do
    local angle = direction * 2 * math.pi / GUIDE_ARROW_DIRECTIONS
    local score = dx * math.cos(angle) + dy * math.sin(angle)
    if score > best then selected, best = direction, score end
  end
  return selected
end

local function guideFloorHint(estimate, ownFloor)
  local floors = estimate.floors or {estimate.position.z}
  if #floors == 1 and tonumber(floors[1]) == ownFloor then return "" end
  local above, below = #floors > 0, #floors > 0
  for _, z in ipairs(floors) do
    z = tonumber(z)
    if not z or z >= ownFloor then above = false end
    if not z or z <= ownFloor then below = false end
  end
  if above then return "Arriba" end
  if below then return "Abajo" end
  return "Piso sin confirmar"
end

local function guideCaption(guide, text, x, y, width, height, startX, startY)
  local longest, lineCount = 0, 0
  for line in text:gmatch("[^\n]+") do
    longest = math.max(longest, #line); lineCount = lineCount + 1
  end
  local captionWidth = math.min(200, width - 4, longest * 7 + 6)
  local captionHeight = math.min(height - 4, lineCount * 14 + 4)
  local caption = guide.widget.caption
  if guide.captionText ~= text then caption:setText(text); guide.captionText = text end
  local maxLeft, maxTop = width - captionWidth - 2, height - captionHeight - 2
  local candidates = {{x + 12, y + 12}, {x - captionWidth - 12, y + 12},
    {x + 12, y - captionHeight - 12}, {x - captionWidth - 12, y - captionHeight - 12},
    {2, 2}, {maxLeft, 2}, {2, maxTop}, {maxLeft, maxTop}}
  local left, top, bestScore
  for _, candidate in ipairs(candidates) do
    local cx = math.max(2, math.min(maxLeft, candidate[1]))
    local cy = math.max(2, math.min(maxTop, candidate[2]))
    local function covers(px, py)
      return px >= cx - 10 and px <= cx + captionWidth + 10 and
        py >= cy - 10 and py <= cy + captionHeight + 10
    end
    local score = ((cx + captionWidth / 2 - x)^2 + (cy + captionHeight / 2 - y)^2) / 100
    -- Prefer an empty corner rather than covering the self pin or the dotted line.
    if covers(startX, startY) then score = score + 100000 end
    if covers(x, y) then score = score + 50000 end
    for i = 1, 15 do
      if covers(startX + (x - startX) * i / 16, startY + (y - startY) * i / 16) then
        score = score + 1000
      end
    end
    if not bestScore or score < bestScore then left, top, bestScore = cx, cy, score end
  end
  setVisualRect(caption, guide.originX + math.floor(left), guide.originY + math.floor(top), captionWidth, captionHeight)
  setVisualVisible(caption, true)
end

local function updateExivaGuide(minimap, storageKey, connectedMembers, projection, own)
  local key = storageKey .. "_guide"
  local targetKey, estimate
  local current = clockMillis()
  -- Follow the newest valid estimate; keep the other search areas unchanged.
  for candidateKey, candidate in pairs(estimates) do
    if candidate.expiresAt > current and not connectedMembers[candidateKey] and
       (not estimate or candidate.updatedAt > estimate.updatedAt or
        (candidate.updatedAt == estimate.updatedAt and candidateKey < targetKey)) then
      targetKey, estimate = candidateKey, candidate
    end
  end
  if not estimate then destroyExivaGuide(minimap, storageKey); return end
  if not projection or not own or projection.center.z ~= own.z or
     projection.width <= 2 * GUIDE_EDGE_MARGIN or projection.height <= 2 * GUIDE_EDGE_MARGIN then
    hideExivaGuide(minimap, storageKey)
    return
  end
  local function screen(pos)
    return projection.cx + (pos.x - projection.center.x) * projection.scaleX,
      projection.cy + (pos.y - projection.center.y) * projection.scaleY
  end
  local x, y = screen(own)
  local targetX, targetY = screen(estimate.position)
  local dx, dy = targetX - x, targetY - y
  local length = math.sqrt(dx * dx + dy * dy)
  local floorHint = guideFloorHint(estimate, own.z)
  local inside = targetX >= GUIDE_EDGE_MARGIN and targetX <= projection.width - GUIDE_EDGE_MARGIN and
    targetY >= GUIDE_EDGE_MARGIN and targetY <= projection.height - GUIDE_EDGE_MARGIN
  local first, last = clipGuideSegment(x, y, dx, dy, projection.width, projection.height)
  if not first or (length < 28 and floorHint == "") then
    hideExivaGuide(minimap, storageKey)
    return
  end
  local guide = mapData(minimap, storageKey)[key]
  if not guide or not visualPresent(minimap, guide.widget) then
    if guide then destroyVisual(guide.widget) end
    guide = createExivaGuide(minimap, storageKey); mapData(minimap, storageKey)[key] = guide
  end
  local renderKey = table.concat({targetKey, estimate.target, estimate.coordinator or "", floorHint,
    projection.originX, projection.originY, projection.width, projection.height,
    x, y, targetX, targetY}, "|")
  if guide.renderKey == renderKey then return end
  guide.renderKey = renderKey
  if guide.target ~= targetKey then guide.needsRaise = true end
  guide.target = targetKey
  guide.originX, guide.originY = projection.originX, projection.originY
  guide.used, guide.dotUsed, guide.arrowUsed = 0, 0, 0
  local endX, endY = x + last * dx, y + last * dy
  if length >= 28 then
    local ux, uy = dx / length, dy / length
    -- Leave room for the self pin and the target reticle.
    local startDistance = math.max(first * length, 14)
    local endDistance = math.min(last * length, length - (inside and 20 or 0))
    local span = endDistance - startDistance
    if span >= 0 then
      local spacing = math.max(9, span / (GUIDE_MAX_DOTS - 1))
      local direction = guideDirection(dx, dy)
      for distance = startDistance, endDistance, spacing do
        guideItem(guide, x + ux * distance, y + uy * distance)
      end
      -- Periodic chevrons plus a final arrow (at the edge for an offscreen target).
      local arrowSpacing = math.max(70, span / (GUIDE_MAX_ARROWS - 1))
      for distance = startDistance + 28, endDistance - 28, arrowSpacing do
        guideItem(guide, x + ux * distance, y + uy * distance, direction)
      end
      if span >= 12 or not inside then
        endX, endY = x + ux * endDistance, y + uy * endDistance
        guideItem(guide, endX, endY, direction)
      end
    end
  end
  if not inside or floorHint ~= "" then
    local label = estimate.target .. " ~"
    label = label .. "\n" .. (floorHint ~= "" and floorHint or "Rumbo aproximado")
    local initiator = estimateInitiator(estimate)
    if initiator then label = label .. "\n" .. initiator end
    guideCaption(guide, label, endX, endY, projection.width, projection.height, x, y)
  else
    setVisualVisible(guide.widget.caption, false)
  end
  finishExivaGuide(guide)
end


local function pauseMapVisuals(minimap, storageKey)
  hideExivaGuide(minimap, storageKey)
  for targetKey, area in pairs(mapData(minimap, storageKey)[storageKey .. "_areas"] or {}) do
    if visualPresent(minimap, area) then setVisualVisible(area, false)
    else
      destroyVisual(area)
      mapData(minimap, storageKey)[storageKey .. "_areas"][targetKey] = nil
    end
  end
  for markerKey, marker in pairs(mapData(minimap, storageKey)[storageKey] or {}) do
    if not visualPresent(minimap, marker.widget) then
      destroyVisual(marker.widget)
      mapData(minimap, storageKey)[storageKey][markerKey] = nil
    elseif marker.visible ~= false then
      marker.widget:setVisible(false)
      marker.visible = false
    end
  end
end

-- The expanded map is expensive to repaint during a drag. Resume after settling.
-- Read gesture state only; preserve the client's mouse and drag callbacks.
local function updateMapActivity(minimap, storageKey, own, current)
  if not trackMap(minimap, storageKey) or type(minimap.getSize) ~= "function" then return false end
  if type(minimap.isVisible) == "function" and not minimap:isVisible() then return false end
  local activityKey = storageKey .. "_activity"
  local previous = mapData(minimap, storageKey)[activityKey]
  local ok, size = pcall(function() return minimap:getSize() end)
  if not ok or not size then return false end
  local width, height = tonumber(size.width), tonumber(size.height)
  if not width or not height then return false end
  if width < LARGE_MAP_MIN_WIDTH and height < LARGE_MAP_MIN_HEIGHT then
    if previous and previous.paused then nextMarkerUpdateAt = 0 end
    mapData(minimap, storageKey)[activityKey] = nil
    return false
  end
  local activity = previous or {}
  mapData(minimap, storageKey)[activityKey] = activity
  if activity.checkedAt == current then return activity.paused end
  activity.checkedAt = current

  local function flag(method)
    if type(minimap[method]) ~= "function" then return false end
    local success, value = pcall(function() return minimap[method](minimap) end)
    return success and value == true
  end
  local camera, zoom
  if type(minimap.getCameraPosition) == "function" then
    local success, value = pcall(function() return minimap:getCameraPosition() end)
    if success then camera = copyPosition(value) end
  end
  if type(minimap.getZoom) == "function" then
    local success, value = pcall(function() return minimap:getZoom() end)
    if success then zoom = value end
  end

  local moved = camera and activity.camera and positionKey(camera) ~= positionKey(activity.camera)
  local following = false
  if moved and own then
    following = positionKey(camera) == positionKey(own) or
      (activity.own and camera.x - activity.camera.x == own.x - activity.own.x and
       camera.y - activity.camera.y == own.y - activity.own.y and
       camera.z - activity.camera.z == own.z - activity.own.z)
  end
  local resized = activity.width and (activity.width ~= width or activity.height ~= height)
  local zoomed = activity.zoom ~= nil and zoom ~= nil and activity.zoom ~= zoom
  -- Camera motion is a fallback for client variants without native drag state.
  local interacting = flag("isDragging") or flag("isPressed") or
    (moved and not following) or resized or zoomed
  if interacting then activity.resumeAt = current + LARGE_MAP_SETTLE_TIME end
  local paused = interacting or (activity.resumeAt ~= nil and current < activity.resumeAt)
  local wasPaused = activity.paused
  activity.paused = paused == true
  activity.camera, activity.own = camera, copyPosition(own)
  activity.width, activity.height, activity.zoom = width, height, zoom
  if activity.paused then
    pauseMapVisuals(minimap, storageKey)
  elseif wasPaused then
    activity.resumeAt = nil
    nextMarkerUpdateAt = 0
  end
  return activity.paused
end


local function markerPoints(estimate, visibleFloor)
  local points = {}
  local floors = estimate.floors
  if type(floors) ~= "table" or #floors == 0 then
    floors = {estimate.position.z}
  end

  for _, floor in ipairs(floors) do
    local z = tonumber(floor)
    if z and z == (tonumber(visibleFloor) or estimate.position.z) then
      table.insert(points, {
        id = "floor" .. tostring(z),
        pos = {x = estimate.position.x, y = estimate.position.y, z = z},
        image = TARGET_MARKER_IMAGE
      })
    end
  end

  return points
end

local function updateMapMarkers(minimap, storageKey, connectedMembers)
  if not trackMap(minimap, storageKey) or type(minimap.centerInPosition) ~= "function" or
    not g_ui or type(g_ui.createWidget) ~= "function" then return end
  if type(minimap.isVisible) == "function" and not minimap:isVisible() then return end
  local own = currentPosition()
  if updateMapActivity(minimap, storageKey, own, clockMillis()) then return end
  mapData(minimap, storageKey)[storageKey] = type(mapData(minimap, storageKey)[storageKey]) == "table" and
    mapData(minimap, storageKey)[storageKey] or {}
  local projection = minimapProjection(minimap)
  updateSearchAreas(minimap, storageKey, connectedMembers, projection)
  updateExivaGuide(minimap, storageKey, connectedMembers, projection, own)
  local guide = mapData(minimap, storageKey)[storageKey .. "_guide"]
  local guideLayer = guide and guide.layerVersion or 0
  local markers = mapData(minimap, storageKey)[storageKey]
  local desired = {}
  local cameraPosition
  if type(minimap.getCameraPosition) == "function" then
    local ok, value = pcall(function() return minimap:getCameraPosition() end)
    if ok then cameraPosition = value end
  end

  for targetKey, estimate in pairs(estimates) do
    if estimate.expiresAt > clockMillis() and
      not connectedMembers[targetKey] then
      local tooltip = estimateTooltip(estimate.target, estimate)
      for _, point in ipairs(markerPoints(estimate, cameraPosition and cameraPosition.z)) do
        local markerKey = targetKey .. ":" .. point.id
        desired[markerKey] = true
        local marker = markers[markerKey]
        if marker and not visualPresent(minimap, marker.widget) then
          destroyVisual(marker.widget)
          marker = nil
        end
        if not marker or not marker.widget then
          local ok, widget = pcall(function()
            local cross = setupUI([[
UIWidget
  size: 19 19
  focusable: false

  Label
    id: caption
    anchors.left: parent.right
    anchors.top: parent.top
    margin-left: 3
    margin-top: 1
    text-auto-resize: true
    font: verdana-11px-rounded
    color: #ffe38a
    background-color: #141414bb
    phantom: true
    focusable: false
]], minimap)
            if not cross then return nil end
            watchVisual(cross, "exivaTracker_" .. safeId(markerKey))
            if cross.setPhantom then cross:setPhantom(false) end
            if cross.setFocusable then cross:setFocusable(false) end
            return cross
          end)
          if ok and widget then
            marker = {widget = widget}
            markers[markerKey] = marker
          end
        end
        if marker and marker.widget then
          pcall(function()
            if marker.image ~= point.image then
              marker.widget:setImageSource(point.image)
              marker.image = point.image
            end
            local caption = estimate.target .. " ~ +/- " .. tostring(estimate.precision) .. " sqm"
            local initiator = estimateInitiator(estimate)
            if initiator then caption = caption .. "\n" .. initiator end
            if marker.caption ~= caption then
              marker.widget.caption:setText(caption)
              marker.caption = caption
            end
            if marker.guideLayer ~= guideLayer then
              marker.widget:raise()
              marker.guideLayer = guideLayer
            end
            if marker.tooltip ~= tooltip then
              marker.widget:setTooltip(tooltip)
              marker.tooltip = tooltip
            end
            local visible = not cameraPosition or
              tonumber(cameraPosition.z) == tonumber(point.pos.z)
            if marker.visible ~= visible then
              marker.widget:setVisible(visible)
              marker.visible = visible
            end
            local posKey = positionKey(point.pos)
            if marker.posKey ~= posKey then
              minimap:centerInPosition(marker.widget, point.pos)
              marker.posKey = posKey
            end
          end)
        end
      end
    end
  end

  for markerKey, marker in pairs(markers) do
    if not desired[markerKey] then
      if marker.widget then pcall(destroyVisual, marker.widget) end
      markers[markerKey] = nil
    end
  end
end

local function clearUnusedMaps(main, secondary)
  for minimap, owned in pairs(visualState.maps) do
    if minimap ~= main and minimap ~= secondary then
      for storageKey in pairs(owned) do destroyMapMarkers(minimap, storageKey) end
    end
  end
end

local function clearAllMarkers()
  clearUnusedMaps(nil, nil)
end

clearAllMarkers()
local markersActive = false

onTalk(function(speaker, level, mode, text, channelId)
  if not activeGeneration() or
    normalizedName(speaker) ~= normalizedName(selfName()) then return end
  local target = parseExivaCommand(text)
  if not target then return end
  local signature = table.concat({tostring(mode or 0), tostring(channelId or 0), trim(text)}, "|")
  local automatic, sessionId = consumeAutomaticTalk(target, signature)
  if automatic then
    if sessionId then completeRemoteCast(sessionId) end
    return
  end
  if trackerEnabled() then beginManualSession(target) end
end)

macro(100, function()
  if not activeGeneration() then return end
  local current = clockMillis()
  if not trackerEnabled() then cancelSessionCasts(false)
  elseif not botServerReady() then cancelSessionCasts(true) end
  pruneAutomaticTalks(current)
  pollServerLog()
  if registerBotServerListeners() then sendCapability(false, false) end

  for sessionId, entry in pairs(queuedCasts) do
    local session = sessions[sessionId]
    if current > entry.expiresAt or not session or session.castCancelled or session.remoteCastDone or
      entry.requestSocket ~= BotServer._websocket then
      completeRemoteCast(sessionId)
    elseif botServerReady() and current - lastLargeDamageAt >= DAMAGE_SAFE_TIME and
        current >= (tonumber(entry.nextAttemptAt) or 0) then
      castQueuedExiva(entry)
      if entry.attempts >= MAX_CAST_ATTEMPTS then completeRemoteCast(sessionId) end
    end
  end
  for sessionId, pending in pairs(pendingCasts) do
    if current > pending.expiresAt then
      pendingCasts[sessionId] = nil
      if pending.automatic then completeRemoteCast(sessionId) end
    end
  end
  for sessionId, session in pairs(sessions) do
    if session.recalculateAt and current >= session.recalculateAt then
      recalculateSession(session)
    end
    if current > session.purgeAt then
      completeRemoteCast(sessionId)
      sessions[sessionId] = nil
      local targetKey = normalizedName(session.target)
      if latestSessions[targetKey] == sessionId then latestSessions[targetKey] = nil end
    end
  end
  for targetKey, estimate in pairs(estimates) do
    if current > estimate.expiresAt then estimates[targetKey] = nil end
  end

  local visualsEnabled = trackerEnabled() and hasEntries(estimates)
  local mainMinimap, secondaryMinimap
  if visualsEnabled then
    mainMinimap, secondaryMinimap = getMainMinimap(), getCyclopediaMinimap()
    local own = currentPosition()
    -- Hide busy expanded-map overlays on the 100 ms tick, before the render tick.
    updateMapActivity(mainMinimap, MAIN_MARKER_KEY, own, current)
    if secondaryMinimap and secondaryMinimap ~= mainMinimap then
      updateMapActivity(secondaryMinimap, CYCLOPEDIA_MARKER_KEY, own, current)
    end
  end

  if current >= nextMarkerUpdateAt then
    nextMarkerUpdateAt = current + MARKER_UPDATE_INTERVAL
    if visualsEnabled then
      clearUnusedMaps(mainMinimap, secondaryMinimap)
      local connectedMembers = connectedMemberNames()
      updateMapMarkers(mainMinimap, MAIN_MARKER_KEY, connectedMembers)
      if secondaryMinimap and secondaryMinimap ~= mainMinimap then
        updateMapMarkers(secondaryMinimap, CYCLOPEDIA_MARKER_KEY, connectedMembers)
      elseif secondaryMinimap then
        -- Some expanded-map getters refer to the same widget: draw it only once.
        destroyMapMarkers(secondaryMinimap, CYCLOPEDIA_MARKER_KEY)
      end
      markersActive = true
    elseif markersActive or hasEntries(visualState.maps) then
      clearAllMarkers()
      markersActive = false
    end
  end
end)

vBot.ExivaTracker = {
  parseResponse = parseExivaResponse,
  solveObservations = solveObservations,
  getSessions = function() return sessions end,
  getEstimates = function() return estimates end,
  getTrackerMembers = function() return trackerMembers end
}
