setDefaultTab("Tools")

local STORAGE_KEY = "exivaCalibrator"
local REQUEST_TOPIC_PREFIX = "xcq_"
local POSITION_TOPIC_PREFIX = "xcp_"
local MAX_SAMPLES = 200
local RESPONSE_TIMEOUT = 15000
local REQUIRED_STABLE_TIME = 1000

storage[STORAGE_KEY] = type(storage[STORAGE_KEY]) == "table" and storage[STORAGE_KEY] or {}
local config = storage[STORAGE_KEY]
if config.enabled == nil then config.enabled = true end
config.enabled = config.enabled == true
config.samples = type(config.samples) == "table" and config.samples or {}
config.target = tostring(config.target or "Rod Master")
while #config.samples > MAX_SAMPLES do table.remove(config.samples, 1) end

local pending = nil

local ui = setupUI([[
Panel
  height: 95

  BotSwitch
    id: enabled
    anchors.top: parent.top
    anchors.left: parent.left
    width: 108
    height: 17
    text-align: center
    text: Exiva Calibrador

  Button
    id: measure
    anchors.top: parent.top
    anchors.left: enabled.right
    margin-left: 3
    width: 65
    height: 17
    text: Medir

  TextEdit
    id: target
    anchors.top: enabled.bottom
    anchors.left: parent.left
    margin-top: 2
    width: 176
    height: 17

  Button
    id: next
    anchors.top: target.bottom
    anchors.left: parent.left
    margin-top: 2
    width: 87
    height: 17
    text: Junto

  Button
    id: near
    anchors.top: next.top
    anchors.left: next.right
    margin-left: 2
    width: 87
    height: 17
    text: Cerca

  Button
    id: far
    anchors.top: next.bottom
    anchors.left: parent.left
    margin-top: 2
    width: 87
    height: 17
    text: Lejos

  Button
    id: veryFar
    anchors.top: far.top
    anchors.left: far.right
    margin-left: 2
    width: 87
    height: 17
    text: Muy lejos

  Button
    id: copy
    anchors.top: far.bottom
    anchors.left: parent.left
    margin-top: 2
    width: 87
    height: 17
    text: Copiar 0

  Button
    id: clear
    anchors.top: copy.top
    anchors.left: copy.right
    margin-left: 2
    width: 87
    height: 17
    text: Limpiar
]])

local function getTime()
  if g_clock and g_clock.millis then return g_clock.millis() end
  return now or 0
end

local function cleanName(value)
  return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function normalizeName(value)
  return cleanName(value):lower()
end

local function topicKey(value)
  local compact = normalizeName(value):gsub("[^%w]", "")
  if compact == "" then compact = "unknown" end
  local hash = 0
  for index = 1, #compact do
    hash = (hash * 33 + compact:byte(index)) % 65536
  end
  return compact:sub(1, 18) .. "_" .. string.format("%04x", hash)
end

local function selfName()
  if player and player.getName then
    local ok, value = pcall(function() return player:getName() end)
    if ok and value and value ~= "" then return value end
  end
  return "Unknown"
end

local function copyPosition(value)
  if type(value) ~= "table" then return nil end
  local x, y, z = tonumber(value.x), tonumber(value.y), tonumber(value.z)
  if not x or not y or not z then return nil end
  return {x = x, y = y, z = z}
end

local function currentPosition()
  if not player or not player.getPosition then return nil end
  local ok, value = pcall(function() return player:getPosition() end)
  return ok and copyPosition(value) or nil
end

local function positionText(value)
  if not value then return "?, ?, ?" end
  return string.format("%d, %d, %d", value.x, value.y, value.z)
end

local function samePosition(left, right)
  return left and right and left.x == right.x and left.y == right.y and left.z == right.z
end

local lastSelfPosition = nil
local lastSelfMovementAt = getTime()

local function selfStableFor()
  local current = currentPosition()
  if not samePosition(current, lastSelfPosition) then
    lastSelfPosition = current
    lastSelfMovementAt = getTime()
  end
  return math.max(0, getTime() - lastSelfMovementAt), current
end

local function websocketReady()
  return BotServer and BotServer._websocket and GameBotServerTransport and
    GameBotServerTransport.state and
    GameBotServerTransport.state.activeMode == "websocket"
end

local function sendBotServer(topic, message)
  if not websocketReady() or type(BotServer.send) ~= "function" then return false end
  local ok, result = pcall(BotServer.send, topic, message)
  return ok and result ~= false
end

local function updateUi(lastText)
  if not ui then return end
  ui.enabled:setOn(config.enabled)
  ui.measure:setText(pending and "Pendiente" or "Medir")
  ui.copy:setText("Copiar " .. tostring(#config.samples))
  if lastText and lastText ~= "" then ui.copy:setTooltip(lastText) end
end

local function sanitizeCell(value)
  local sanitized = tostring(value or ""):gsub("[\r\n\t]", " ")
  return sanitized
end

local function exportSamples()
  local rows = {
    "fecha\tobservador\tobjetivo\tobservador_x\tobservador_y\tobservador_z\tobjetivo_x\tobjetivo_y\tobjetivo_z\tdx\tdy\tdz\tdistancia_sqm\tdistancia_manhattan\tdistancia_euclidiana\tretraso_pos_ms\tobservador_estable_ms\tobjetivo_estable_ms\tverificacion_ms\tcategoria\tmodo\trespuesta"
  }
  for _, sample in ipairs(config.samples) do
    local observer = sample.observerPos or {}
    local target = sample.targetPos or {}
    table.insert(rows, table.concat({
      sanitizeCell(sample.date),
      sanitizeCell(sample.observer),
      sanitizeCell(sample.target),
      sanitizeCell(observer.x), sanitizeCell(observer.y), sanitizeCell(observer.z),
      sanitizeCell(target.x), sanitizeCell(target.y), sanitizeCell(target.z),
      sanitizeCell(sample.dx), sanitizeCell(sample.dy), sanitizeCell(sample.dz),
      sanitizeCell(sample.squareDistance), sanitizeCell(sample.manhattanDistance),
      sanitizeCell(sample.euclideanDistance), sanitizeCell(sample.positionDelay),
      sanitizeCell(sample.observerStableFor), sanitizeCell(sample.targetStableFor),
      sanitizeCell(sample.verificationDelay),
      sanitizeCell(sample.classification),
      sanitizeCell(sample.mode), sanitizeCell(sample.response)
    }, "\t"))
  end
  return table.concat(rows, "\n")
end

ui.enabled:setOn(config.enabled)
ui.enabled:setTooltip(
  "Activa el calibrador manual asistido de exiva.")
ui.enabled.onClick = function(widget)
  config.enabled = not config.enabled
  widget:setOn(config.enabled)
end

ui.target:setText(config.target)
ui.target:setTooltip("Nombre exacto del objetivo conectado al BotServer.")
ui.target.onTextChange = function(widget, text)
  config.target = cleanName(text)
end
ui.measure:setTooltip("Lanza exiva al objetivo y prepara una muestra.")
ui.next:setTooltip("Guardar la respuesta: standing next to you.")
ui.near:setTooltip("Guardar una respuesta sin far ni very far.")
ui.far:setTooltip("Guardar una respuesta far.")
ui.veryFar:setTooltip("Guardar una respuesta very far.")

ui.copy:setTooltip("Copia todas las muestras en formato tabulado.")
ui.copy.onClick = function()
  if #config.samples == 0 then
    warn("[Exiva Cal] Todavia no hay muestras.")
    return
  end
  g_window.setClipboardText(exportSamples())
  warn("[Exiva Cal] " .. tostring(#config.samples) .. " muestras copiadas al portapapeles.")
end
ui.clear:setTooltip("Elimina todas las muestras guardadas.")
ui.clear.onClick = function()
  config.samples = {}
  updateUi("Muestras eliminadas")
  warn("[Exiva Cal] Muestras eliminadas.")
end
updateUi()

BotServer._exivaCalibratorGeneration = (BotServer._exivaCalibratorGeneration or 0) + 1
local generation = BotServer._exivaCalibratorGeneration
local registeredSocket = nil

local function activeGeneration()
  return BotServer and BotServer._exivaCalibratorGeneration == generation
end

local function makeRequestId()
  return table.concat({
    normalizeName(selfName()):gsub("[^%w]", ""),
    tostring(os.time()),
    tostring(getTime()),
    tostring(math.random(1000, 9999))
  }, ":")
end

local function sendPendingPositionRequest(phase)
  if not pending or not phase then return false end
  local current = getTime()
  local retryKey = phase .. "NextAttemptAt"
  if current < (pending[retryKey] or 0) then return false end
  pending[retryKey] = current + 500
  local sent = sendBotServer(REQUEST_TOPIC_PREFIX .. topicKey(pending.target), {
    id = pending.id,
    phase = phase,
    requester = pending.observer,
    target = pending.target,
    observerPos = pending.observerPos,
    castAt = pending.castAt
  })
  if sent then pending[phase .. "RequestedAt"] = current end
  return sent
end

local function calculateSample(entry)
  local observerPos = entry.observerPos
  local targetPos = entry.targetPos
  local dx, dy, dz, squareDistance, manhattanDistance, euclideanDistance
  if observerPos and targetPos then
    dx = targetPos.x - observerPos.x
    dy = targetPos.y - observerPos.y
    dz = targetPos.z - observerPos.z
    squareDistance = math.max(math.abs(dx), math.abs(dy))
    manhattanDistance = math.abs(dx) + math.abs(dy)
    euclideanDistance = math.floor((math.sqrt(dx * dx + dy * dy) * 10) + 0.5) / 10
  end

  return {
    date = os.date("%Y-%m-%d %H:%M:%S"),
    observer = entry.observer,
    target = entry.target,
    observerPos = observerPos,
    targetPos = targetPos,
    dx = dx,
    dy = dy,
    dz = dz,
    squareDistance = squareDistance,
    manhattanDistance = manhattanDistance,
    euclideanDistance = euclideanDistance,
    positionDelay = entry.positionAt and entry.castAt and
      math.max(0, entry.positionAt - entry.castAt) or nil,
    observerStableFor = entry.observerStableFor,
    targetStableFor = entry.targetStableFor,
    verificationDelay = entry.verifyAt and entry.responseAt and
      math.max(0, entry.verifyAt - entry.responseAt) or nil,
    classification = entry.classification,
    mode = entry.responseMode,
    response = entry.responseText
  }
end

local function savePendingSample()
  if not pending or not pending.responseText or not pending.verified then return false end
  local sample = calculateSample(pending)
  table.insert(config.samples, sample)
  while #config.samples > MAX_SAMPLES do table.remove(config.samples, 1) end

  local metrics
  if sample.targetPos then
    metrics = string.format(
      "dx=%d dy=%d dz=%d | sqm=%d eu=%.1f",
      sample.dx, sample.dy, sample.dz, sample.squareDistance, sample.euclideanDistance)
  else
    metrics = "sin posicion exacta del objetivo"
  end
  local summary = string.format(
    "[Exiva Cal] #%d %s -> %s | %s | %s",
    #config.samples, positionText(sample.observerPos), positionText(sample.targetPos),
    metrics, sample.classification or sample.response)
  warn(summary)
  pending = nil
  updateUi(summary)
  return true
end

local RESPONSE_HINTS = {
  "standing next", "is to the", "far to the", "very far", "north", "south",
  "east", "west", "higher level", "lower level"
}

local function likelyExivaResponse(text, targetName)
  local lower = normalizeName(text)
  if not lower:find(normalizeName(targetName), 1, true) then return false end
  for _, hint in ipairs(RESPONSE_HINTS) do
    if lower:find(hint, 1, true) then return true end
  end
  return false
end

local function addCandidate(source, mode, text)
  if not pending then return end
  text = cleanName(text)
  if text == "" then return end
  pending.candidates = pending.candidates or {}

  for _, candidate in ipairs(pending.candidates) do
    if candidate.text == text then return end
  end
  if #pending.candidates < 12 then
    table.insert(pending.candidates, {
      source = tostring(source or "unknown"),
      mode = mode,
      text = text
    })
  end

  if not pending.manual and not pending.responseText and
     likelyExivaResponse(text, pending.target) then
    local observerStableFor, observerPosition = selfStableFor()
    if not samePosition(observerPosition, pending.observerPos) then
      warn("[Exiva Cal] Muestra descartada: " .. selfName() ..
        " se movio durante el exiva.")
      pending = nil
      return
    end
    pending.responseText = text
    pending.responseMode = mode
    pending.responseSource = source
    pending.responseAt = getTime()
    pending.observerStableFor = observerStableFor
    if pending.targetPos and not pending.verifyRequestedAt then
      sendPendingPositionRequest("verify")
    end
  end
end

local function diagnosticCandidates(entry)
  local result = {}
  for index, candidate in ipairs(entry.candidates or {}) do
    if index > 5 then break end
    local text = candidate.text
    if #text > 90 then text = text:sub(1, 87) .. "..." end
    table.insert(result, tostring(candidate.source) .. ": " .. text)
  end
  return table.concat(result, " | ")
end

vBot.ExivaCalibrationCaptureConsoleText = function(text, speaktype, tabName)
  if not activeGeneration() or not config.enabled or not pending then return end
  local source = "console:" .. tostring(tabName or "?")
  addCandidate(source, speaktype, text)
end

local function registerListeners()
  if not activeGeneration() or not websocketReady() then return false end
  local socket = BotServer._websocket
  if registeredSocket == socket then return true end
  registeredSocket = socket
  local listenerSocket = socket

  local requestTopic = REQUEST_TOPIC_PREFIX .. topicKey(selfName())
  local positionTopic = POSITION_TOPIC_PREFIX .. topicKey(selfName())

  local requestOk = BotServer.listen(requestTopic, function(sender, message)
    if not activeGeneration() or BotServer._websocket ~= listenerSocket or
       not config.enabled or type(message) ~= "table" then return end
    if normalizeName(message.target) ~= normalizeName(selfName()) then return end
    if type(message.id) ~= "string" or message.id == "" then return end

    local stableFor, targetPosition = selfStableFor()
    sendBotServer(POSITION_TOPIC_PREFIX .. topicKey(message.requester), {
      id = message.id,
      phase = message.phase or "cast",
      requester = message.requester,
      target = selfName(),
      pos = targetPosition,
      stable = stableFor >= REQUIRED_STABLE_TIME,
      stableFor = stableFor,
      capturedAt = getTime()
    })
  end)

  local positionOk = BotServer.listen(positionTopic, function(sender, message)
    if not activeGeneration() or BotServer._websocket ~= listenerSocket or
       not config.enabled or not pending or type(message) ~= "table" then return end
    if message.id ~= pending.id then return end
    if normalizeName(message.requester) ~= normalizeName(selfName()) then return end
    if normalizeName(message.target) ~= normalizeName(pending.target) then return end
    if normalizeName(sender) ~= normalizeName(pending.target) then return end

    local phase = tostring(message.phase or "cast")
    local targetPosition = copyPosition(message.pos)
    if phase == "verify" then
      if not samePosition(targetPosition, pending.targetPos) then
        warn("[Exiva Cal] Muestra descartada: " .. pending.target ..
          " cambio de posicion durante el exiva.")
        pending = nil
        updateUi("Objetivo movido; muestra descartada")
        return
      end
      pending.verified = true
      pending.verifyAt = getTime()
      pending.targetStableFor = math.min(
        tonumber(pending.targetStableFor) or math.huge,
        tonumber(message.stableFor) or math.huge)
      if pending.targetStableFor == math.huge then pending.targetStableFor = nil end
      if pending.responseText then savePendingSample() end
      return
    end

    if not targetPosition then
      warn("[Exiva Cal] " .. pending.target .. " no envio una posicion valida.")
      pending = nil
      updateUi("Posicion del objetivo no disponible")
      return
    end
    pending.targetPos = targetPosition
    pending.positionAt = getTime()
    pending.targetStableFor = tonumber(message.stableFor)
    if pending.responseText and not pending.verifyRequestedAt then
      sendPendingPositionRequest("verify")
    end
  end)

  if requestOk == false or positionOk == false then
    registeredSocket = nil
    return false
  end
  return true
end

local CATEGORIES = {
  next = {label = "Junto", response = "standing next to you"},
  near = {label = "Cerca", response = "near"},
  far = {label = "Lejos", response = "far"},
  very_far = {label = "Muy lejos", response = "very far"}
}

local function beginManualMeasurement(targetName)
  if not config.enabled then
    warn("[Exiva Cal] Activa el calibrador antes de medir.")
    return false
  end
  if pending then
    warn("[Exiva Cal] Ya hay una medicion pendiente.")
    return false
  end

  targetName = cleanName(targetName):gsub('"', '')
  if targetName == "" then
    warn("[Exiva Cal] Escribe el nombre del objetivo.")
    return false
  end

  local observerStableFor, observerPosition = selfStableFor()
  if not observerPosition then
    warn("[Exiva Cal] No se pudo leer tu posicion.")
    return false
  end
  if observerStableFor < REQUIRED_STABLE_TIME then
    warn("[Exiva Cal] Espera 1 segundo sin moverte antes de medir.")
    return false
  end

  pending = {
    id = makeRequestId(),
    observer = selfName(),
    target = targetName,
    observerPos = observerPosition,
    observerStableFor = observerStableFor,
    castAt = getTime(),
    candidates = {},
    manual = true
  }

  if not registerListeners() or not sendPendingPositionRequest("cast") then
    warn("[Exiva Cal] BotServer WebSocket no esta listo.")
    pending = nil
    updateUi("BotServer no disponible")
    return false
  end

  config.target = targetName
  ui.target:setText(targetName)
  updateUi("Esperando categoria manual")
  return true
end

local function sayExiva(targetName)
  local command = 'exiva "' .. targetName .. '"'
  local ok = pcall(function()
    if type(say) == "function" then
      say(command)
    elseif g_game and type(g_game.talk) == "function" then
      g_game.talk(command)
    else
      error("talk unavailable")
    end
  end)
  if not ok then
    warn("[Exiva Cal] No se pudo lanzar " .. command .. ".")
    pending = nil
    updateUi("No se pudo lanzar exiva")
    return false
  end
  warn("[Exiva Cal] Exiva enviado. Marca Junto, Cerca, Lejos o Muy lejos.")
  return true
end

local function classifyPending(categoryId)
  local category = CATEGORIES[categoryId]
  if not category then return false end
  if not pending then
    warn("[Exiva Cal] Pulsa Medir antes de marcar el resultado.")
    return false
  end
  if pending.responseText then
    warn("[Exiva Cal] La categoria ya fue marcada; esperando verificacion.")
    return false
  end

  local observerStableFor, observerPosition = selfStableFor()
  if not samePosition(observerPosition, pending.observerPos) then
    warn("[Exiva Cal] Muestra descartada: " .. selfName() .. " se movio.")
    pending = nil
    updateUi("Observador movido; muestra descartada")
    return false
  end

  pending.classification = category.label
  pending.responseText = category.response
  pending.responseMode = "manual"
  pending.responseSource = "manual"
  pending.responseAt = getTime()
  pending.observerStableFor = observerStableFor
  updateUi("Categoria: " .. category.label)

  if pending.targetPos then
    sendPendingPositionRequest("verify")
  else
    warn("[Exiva Cal] Categoria marcada; esperando posicion de " .. pending.target .. ".")
  end
  return true
end

ui.measure.onClick = function()
  local targetName = cleanName(ui.target:getText())
  if beginManualMeasurement(targetName) then sayExiva(targetName) end
end
ui.next.onClick = function() classifyPending("next") end
ui.near.onClick = function() classifyPending("near") end
ui.far.onClick = function() classifyPending("far") end
ui.veryFar.onClick = function() classifyPending("very_far") end

onTalk(function(speaker, level, mode, text)
  if not activeGeneration() or not config.enabled then return end
  text = tostring(text or "")
  if normalizeName(speaker) == normalizeName(selfName()) then
    local targetName = text:match('^%s*[Ee][Xx][Ii][Vv][Aa]%s+"([^"]+)"') or
      text:match("^%s*[Ee][Xx][Ii][Vv][Aa]%s+(.+)$")
    targetName = cleanName(targetName):gsub('^"', ''):gsub('"$', '')
    if targetName ~= "" then
      if pending and pending.manual and
         normalizeName(pending.target) == normalizeName(targetName) and
         getTime() - pending.castAt < 2000 then
        return
      end
      local observerStableFor, observerPosition = selfStableFor()
      if observerStableFor < REQUIRED_STABLE_TIME then
        warn("[Exiva Cal] Espera 1 segundo sin moverte antes de repetir el exiva.")
        return
      end
      pending = {
        id = makeRequestId(),
        observer = selfName(),
        target = targetName,
        observerPos = observerPosition,
        observerStableFor = observerStableFor,
        castAt = getTime(),
        candidates = {},
        manual = true
      }

      if not registerListeners() or not sendPendingPositionRequest("cast") then
        warn("[Exiva Cal] BotServer WebSocket no esta listo; esta muestra no se guardara.")
        pending = nil
      else
        updateUi("Marca la categoria visible")
      end
      return
    end
  end

  addCandidate("talk:" .. tostring(speaker or "?"), mode, text)
end)

onTextMessage(function(mode, text)
  if not activeGeneration() or not config.enabled or not pending then return end
  addCandidate("text:" .. tostring(mode), mode, text)
end)

macro(100, function()
  if not activeGeneration() then return end
  selfStableFor()
  registerListeners()
  if not pending then return end

  local age = getTime() - pending.castAt
  if pending.responseText and pending.targetPos and not pending.verifyRequestedAt then
    sendPendingPositionRequest("verify")
  end
  if pending and pending.responseText and pending.verified then
    savePendingSample()
  elseif pending and age >= RESPONSE_TIMEOUT then
    if pending.responseText then
      warn("[Exiva Cal] Respuesta recibida, pero no se pudo verificar la posicion de " ..
        pending.target .. ".")
      pending = nil
      updateUi("No se pudo verificar la posicion")
      return
    end
    if pending.manual then
      warn("[Exiva Cal] Medicion vencida: no se marco una categoria a tiempo.")
      pending = nil
      updateUi("Medicion vencida")
      return
    end
    local candidates = diagnosticCandidates(pending)
    if candidates ~= "" then
      warn("[Exiva Cal] No se identifico la respuesta. Candidatos: " .. candidates)
    else
      warn("[Exiva Cal] No llego ningun mensaje despues de exiva " .. pending.target .. ".")
    end
    pending = nil
    updateUi("Respuesta no identificada")
  end
end)
