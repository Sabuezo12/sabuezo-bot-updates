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
local CAPABILITY_TIMEOUT = 15000
local MAX_OBSERVERS = 4
local MEMBER_POSITION_MAX_AGE = 15000
local DAMAGE_LIMIT = 500
local DAMAGE_SAFE_TIME = 2000
local CAST_TIMEOUT = 9000
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
local CENTER_MARKER_IMAGE = "/images/game/minimap/flag4"
local CORNER_MARKER_IMAGE = "/images/game/minimap/waypoint"

BotServer._exivaTrackerGeneration = (BotServer._exivaTrackerGeneration or 0) + 1
local generation = BotServer._exivaTrackerGeneration
local registeredSocket = nil
local sessions = {}
local queuedCasts = {}
local pendingCasts = {}
local estimates = {}
local trackerMembers = {}
local processedMessages = setmetatable({}, {__mode = "k"})
local consoleInitialized = false
local lastServerLogTab = nil
local lastLargeDamageAt = 0
local suppressTarget = nil
local suppressUntil = 0
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

  for _, z in ipairs(floors) do
    local stats = {count = 0, sumX = 0, sumY = 0}
    for x = minX, maxX, step do
      for y = minY, maxY, step do
        if allObservationsMatch(x, y, z, observations) then
          stats.count = stats.count + 1
          stats.sumX = stats.sumX + x
          stats.sumY = stats.sumY + y
          stats.minX = not stats.minX and x or math.min(stats.minX, x)
          stats.maxX = not stats.maxX and x or math.max(stats.maxX, x)
          stats.minY = not stats.minY and y or math.min(stats.minY, y)
          stats.maxY = not stats.maxY and y or math.max(stats.maxY, y)
        end
      end
    end
    if stats.count > 0 then statsByFloor[z] = stats end
  end

  if not hasEntries(statsByFloor) and step > 1 and
    tests <= MAX_GEOMETRY_TESTS * 4 then
    step = 1
    for _, z in ipairs(floors) do
      local stats = {count = 0, sumX = 0, sumY = 0}
      for x = minX, maxX do
        for y = minY, maxY do
          if allObservationsMatch(x, y, z, observations) then
            stats.count = stats.count + 1
            stats.sumX = stats.sumX + x
            stats.sumY = stats.sumY + y
            stats.minX = not stats.minX and x or math.min(stats.minX, x)
            stats.maxX = not stats.maxX and x or math.max(stats.maxX, x)
            stats.minY = not stats.minY and y or math.min(stats.minY, y)
            stats.maxY = not stats.maxY and y or math.max(stats.maxY, y)
          end
        end
      end
      if stats.count > 0 then statsByFloor[z] = stats end
    end
  end
  if not hasEntries(statsByFloor) then return nil end

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
  local targetKey = normalizedName(message.target)
  if estimates[targetKey] then
    estimates[targetKey].expiresAt = current + ESTIMATE_LIFETIME
  end
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
  return session
end

local function addObservation(session, observer, message)
  if not session or type(message) ~= "table" then return false end
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
  pendingCasts[session.id] = {
    target = target,
    observerPos = observerPos,
    castAt = clockMillis(),
    expiresAt = clockMillis() + CAST_TIMEOUT
  }

  sendBotServer(REQUEST_TOPIC, message)
end

local function queueRemoteCast(session)
  if not session or pendingCasts[session.id] or queuedCasts[session.id] then return end
  queuedCasts[session.id] = {
    sessionId = session.id,
    target = session.target,
    expiresAt = clockMillis() + SESSION_TIMEOUT
  }
end

local function castQueuedExiva(entry)
  local session = sessions[entry.sessionId]
  local observerPos = currentPosition()
  if not session or not observerPos then return false end

  pendingCasts[entry.sessionId] = {
    target = entry.target,
    observerPos = observerPos,
    castAt = clockMillis(),
    expiresAt = clockMillis() + CAST_TIMEOUT
  }
  suppressTarget = normalizedName(entry.target)
  suppressUntil = clockMillis() + 2500

  local command = 'exiva "' .. entry.target:gsub('"', "") .. '"'
  local ok = pcall(function()
    if type(say) == "function" then
      say(command)
    elseif g_game and type(g_game.talk) == "function" then
      g_game.talk(command)
    else
      error("talk unavailable")
    end
  end)
  if not ok then pendingCasts[entry.sessionId] = nil end
  return ok
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
  publishObservation(sessions[bestId], bestParsed, pending.observerPos)
end

local function processConsoleText(text)
  text = trim(text)
  if text == "" then return end
  processDamageText(text)
  processResponseText(text)
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
    if type(message) == "table" and tonumber(message.timestamp or 0) > 0 then
      local text = flattenConsoleText(message.text)
      local signature = table.concat({
        tostring(message.timestamp or 0), tostring(message.mode or 0),
        tostring(message.name or ""), text
      }, "|")
      if processedMessages[message] ~= signature then
        processedMessages[message] = signature
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
    if type(message.id) ~= "string" or trim(message.target) == "" then return end
    if trim(message.coordinator) ~= "" and normalizedName(sender) ~=
      normalizedName(message.coordinator) then return end

    local session = sessions[message.id] or newSession(message)
    if selectedContains(message.selected, selfName()) and
      normalizedName(selfName()) ~= normalizedName(message.coordinator) then
      queueRemoteCast(session)
    end
  end)

  local resultOk = BotServer.listen(RESULT_TOPIC, function(sender, message)
    if not activeGeneration() or BotServer._websocket ~= listenerSocket or
      not trackerEnabled() or type(message) ~= "table" then return end
    if type(message.id) ~= "string" or trim(message.target) == "" then return end
    local observer = trim(sender) ~= "" and sender or message.observer
    if trim(message.observer) ~= "" and
      normalizedName(observer) ~= normalizedName(message.observer) then return end
    local session = sessions[message.id] or newSession(message)
    if normalizedName(session.target) ~= normalizedName(message.target) then return end
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

local function estimateTooltip(target, estimate)
  local suffix = estimate.unbounded and " (busqueda limitada)" or ""
  return table.concat({
    target,
    "Estimado: " .. positionKey(estimate.position),
    "Zona X: " .. estimate.minX .. " - " .. estimate.maxX,
    "Zona Y: " .. estimate.minY .. " - " .. estimate.maxY,
    "Pisos: " .. floorsText(estimate.floors),
    "Respuestas: " .. estimate.responseCount,
    "Precision: +/- " .. estimate.precision .. " sqm" .. suffix
  }, "\n")
end

local function recalculateSession(session)
  local observations = observationsFromSession(session)
  if #observations == 0 then return end
  local estimate = solveObservations(observations)
  session.recalculateAt = nil
  if not estimate then return end

  estimate.target = session.target
  estimate.updatedAt = clockMillis()
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

local function getMainMinimap()
  local minimapModule = modules and modules.game_minimap
  if not minimapModule then return nil end
  if type(minimapModule.getMiniMapUi) == "function" then
    local ok, minimap = pcall(minimapModule.getMiniMapUi)
    if ok and minimap then return minimap end
  end
  return minimapModule.minimapWidget
end

local function getCyclopediaMinimap()
  local mapCyclopedia = modules and modules.game_cyclopedia and
    modules.game_cyclopedia.MapCyclopedia
  if mapCyclopedia and type(mapCyclopedia.getMinimapWidget) == "function" then
    local ok, minimap = pcall(function() return mapCyclopedia.getMinimapWidget() end)
    if ok and minimap then return minimap end
  end
  local root = g_ui and g_ui.getRootWidget and g_ui.getRootWidget()
  if not root or not root.recursiveGetChildById then return nil end
  local ok, minimap = pcall(function()
    local panel = root:recursiveGetChildById("MapDataPanel")
    return panel and panel:recursiveGetChildById("minimap") or nil
  end)
  return ok and minimap or nil
end

local function destroyMapMarkers(minimap, storageKey)
  if not minimap or type(minimap[storageKey]) ~= "table" then return end
  for _, marker in pairs(minimap[storageKey]) do
    if marker.widget then pcall(function() marker.widget:destroy() end) end
  end
  minimap[storageKey] = {}
end

local function markerPoints(estimate)
  local points = {{
    id = "center",
    pos = estimate.position,
    image = CENTER_MARKER_IMAGE
  }}
  if estimate.maxX - estimate.minX <= 600 and estimate.maxY - estimate.minY <= 600 then
    local corners = {
      {estimate.minX, estimate.minY}, {estimate.maxX, estimate.minY},
      {estimate.minX, estimate.maxY}, {estimate.maxX, estimate.maxY}
    }
    local known = {[positionKey(estimate.position)] = true}
    for index, corner in ipairs(corners) do
      local pos = {x = corner[1], y = corner[2], z = estimate.position.z}
      local key = positionKey(pos)
      if not known[key] then
        known[key] = true
        table.insert(points, {
          id = "corner" .. index,
          pos = pos,
          image = CORNER_MARKER_IMAGE
        })
      end
    end
  end
  return points
end

local function updateMapMarkers(minimap, storageKey, connectedMembers)
  if not minimap or type(minimap.centerInPosition) ~= "function" or
    not g_ui or type(g_ui.createWidget) ~= "function" then return end
  minimap[storageKey] = type(minimap[storageKey]) == "table" and
    minimap[storageKey] or {}
  local markers = minimap[storageKey]
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
      for _, point in ipairs(markerPoints(estimate)) do
        local markerKey = targetKey .. ":" .. point.id
        desired[markerKey] = true
        local marker = markers[markerKey]
        if not marker or not marker.widget then
          local ok, widget = pcall(function()
            local cross = g_ui.createWidget("MinimapCross", minimap)
            if not cross then return nil end
            cross:setId("exivaTracker_" .. safeId(markerKey))
            if cross.setIcon then cross:setIcon(point.image) end
            if cross.setPhantom then cross:setPhantom(false) end
            if cross.setFocusable then cross:setFocusable(false) end
            minimap:centerInPosition(cross, point.pos)
            return cross
          end)
          if ok and widget then
            marker = {widget = widget}
            markers[markerKey] = marker
          end
        end
        if marker and marker.widget then
          pcall(function()
            if marker.widget.setIcon then marker.widget:setIcon(point.image) end
            marker.widget:setTooltip(tooltip)
            marker.widget:setVisible(not cameraPosition or
              tonumber(cameraPosition.z) == tonumber(point.pos.z))
            minimap:centerInPosition(marker.widget, point.pos)
          end)
        end
      end
    end
  end

  for markerKey, marker in pairs(markers) do
    if not desired[markerKey] then
      if marker.widget then pcall(function() marker.widget:destroy() end) end
      markers[markerKey] = nil
    end
  end
end

local function clearAllMarkers()
  destroyMapMarkers(getMainMinimap(), MAIN_MARKER_KEY)
  destroyMapMarkers(getCyclopediaMinimap(), CYCLOPEDIA_MARKER_KEY)
end

clearAllMarkers()

onTalk(function(speaker, level, mode, text)
  if not activeGeneration() or not trackerEnabled() or
    normalizedName(speaker) ~= normalizedName(selfName()) then return end
  local target = parseExivaCommand(text)
  if not target then return end
  if suppressTarget == normalizedName(target) and clockMillis() <= suppressUntil then
    suppressTarget = nil
    return
  end
  beginManualSession(target)
end)

macro(100, function()
  if not activeGeneration() then return end
  pollServerLog()
  if registerBotServerListeners() then sendCapability(false, false) end
  local current = clockMillis()

  for sessionId, entry in pairs(queuedCasts) do
    if current > entry.expiresAt then
      queuedCasts[sessionId] = nil
    elseif trackerEnabled() and current - lastLargeDamageAt >= DAMAGE_SAFE_TIME then
      castQueuedExiva(entry)
      queuedCasts[sessionId] = nil
    end
  end
  for sessionId, pending in pairs(pendingCasts) do
    if current > pending.expiresAt then pendingCasts[sessionId] = nil end
  end
  for sessionId, session in pairs(sessions) do
    if session.recalculateAt and current >= session.recalculateAt then
      recalculateSession(session)
    end
    if current > session.purgeAt then sessions[sessionId] = nil end
  end
  for targetKey, estimate in pairs(estimates) do
    if current > estimate.expiresAt then estimates[targetKey] = nil end
  end

  if current >= nextMarkerUpdateAt then
    nextMarkerUpdateAt = current + MARKER_UPDATE_INTERVAL
    if trackerEnabled() then
      local connectedMembers = connectedMemberNames()
      updateMapMarkers(getMainMinimap(), MAIN_MARKER_KEY, connectedMembers)
      updateMapMarkers(
        getCyclopediaMinimap(), CYCLOPEDIA_MARKER_KEY, connectedMembers)
    else
      clearAllMarkers()
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
