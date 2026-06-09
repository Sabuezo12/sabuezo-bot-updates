---@diagnostic disable: undefined-global
setDefaultTab("Main")

local panelName = "pushmax"
local OLD_DESTROY_FIELD_IDS = "2118,105,2122"
local PREVIOUS_DESTROY_FIELD_IDS = "2118,118,105,2122,2123,2124,2125"
local DEFAULT_DESTROY_FIELD_IDS = "2118,118,105,2121,2122,2123,2124,2125,2126,2131,2132,2133,2134,2135"
local ui = setupUI([[
Panel
  height: 19

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('PUSHMAX')

  Button
    id: push
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 17
    text: Setup

]])
ui:setId(panelName)
if ui.title.setTooltip then
  ui.title:setTooltip("Activa o desactiva PUSHMAX.")
end
if ui.push.setTooltip then
  ui.push:setTooltip("Abre la configuracion visual de PUSHMAX.")
end

if not storage[panelName] then
  storage[panelName] = {
    enabled = true,
    pushDelay = 10,
    pushMaxRuneId = 3188,
    finalMwallRuneId = 3180,
    mwallBlockId = 2128,
    destroyFieldIds = DEFAULT_DESTROY_FIELD_IDS,
    pushMaxKey = "PageUp"
  }
end

local config = storage[panelName]
if not config.finalMwallRuneId then config.finalMwallRuneId = 3180 end
if not config.mwallBlockId then config.mwallBlockId = 2128 end
if not config.destroyFieldIds then config.destroyFieldIds = DEFAULT_DESTROY_FIELD_IDS end
if config.destroyFieldIds == OLD_DESTROY_FIELD_IDS or config.destroyFieldIds == PREVIOUS_DESTROY_FIELD_IDS then
  config.destroyFieldIds = DEFAULT_DESTROY_FIELD_IDS
end
if config.fastPushVersion ~= 8 then
  config.pushDelay = 10
  config.fastPushVersion = 8
  config.fastPush80 = true
end

ui.title:setOn(config.enabled)
ui.title.onClick = function(widget)
config.enabled = not config.enabled
widget:setOn(config.enabled)
end

ui.push.onClick = function(widget)
  pushWindow:show()
  pushWindow:raise()
  pushWindow:focus()
end

rootWidget = g_ui.getRootWidget()
if rootWidget then
  pushWindow = UI.createWindow('PushMaxWindow', rootWidget)
  pushWindow:hide()

  local setTooltip = function(widget, text)
    if widget and widget.setTooltip then
      widget:setTooltip(text)
    end
  end

  setTooltip(pushWindow.delayText, "Delay general para push largo y magic walls. No controla el cooldown real de push 1 sqm.")
  setTooltip(pushWindow.delay, "Delay general del push normal. El push 1 sqm y los delays despues de runa se ajustan en este lua.")
  setTooltip(pushWindow.label3, "Runa usada contra anti-push/trash debajo del target. Normalmente fire field.")
  setTooltip(pushWindow.runeId, "ID de la runa que se tira sobre el target si tiene trash debajo.")
  setTooltip(pushWindow.label2, "ID del objeto de magic wall ya puesto en el piso.")
  setTooltip(pushWindow.mwallId, "Objeto de magic wall que bloquea el tile. Sirve para esperar a que expire.")
  setTooltip(pushWindow.label4, "Runa para cerrar con magic wall cuando el target llega al destino final.")
  setTooltip(pushWindow.finalMwallRuneId, "ID de la runa de magic wall final.")
  setTooltip(pushWindow.label5, "IDs de fields que Destroy Field debe limpiar antes de empujar.")
  setTooltip(pushWindow.destroyFieldIds, "Lista separada por comas. Si un server usa fields custom, agrega sus IDs aqui.")
  setTooltip(pushWindow.label1, "Hotkey para marcar target/destino. Mantener presionada mucho tiempo marca CLEAR.")
  setTooltip(pushWindow.hotkey, "Nombre de la tecla usada para PUSHMAX, por ejemplo PageUp.")

  pushWindow.closeButton.onClick = function(widget)
    pushWindow:hide()
  end

  if pushWindow.delay.setRange then
    pushWindow.delay:setRange(10, 2000)
  end
  if pushWindow.delay.setStep then
    pushWindow.delay:setStep(10)
  end

  local updateDelayText = function()
    pushWindow.delayText:setText("Push Delay: ".. config.pushDelay)
  end
  updateDelayText()
  pushWindow.delay.onValueChange = function(scroll, value)
    config.pushDelay = value
    updateDelayText()
  end
  pushWindow.delay:setValue(config.pushDelay)

  pushWindow.runeId.onItemChange = function(widget)
    config.pushMaxRuneId = widget:getItemId()
  end
  pushWindow.runeId:setItemId(config.pushMaxRuneId)
  pushWindow.mwallId.onItemChange = function(widget)
    config.mwallBlockId = widget:getItemId()
  end
  pushWindow.mwallId:setItemId(config.mwallBlockId)
  pushWindow.finalMwallRuneId.onItemChange = function(widget)
    config.finalMwallRuneId = widget:getItemId()
  end
  pushWindow.finalMwallRuneId:setItemId(config.finalMwallRuneId)
  pushWindow.destroyFieldIds.onTextChange = function(widget, text)
    config.destroyFieldIds = text
  end
  pushWindow.destroyFieldIds:setText(config.destroyFieldIds)

  pushWindow.hotkey.onTextChange = function(widget, text)
    config.pushMaxKey = text
  end
  pushWindow.hotkey:setText(config.pushMaxKey)
end

-- variables for config
-- Guia rapida:
-- - ONE_SQM_PUSH_COOLDOWN controla el tiempo real entre pushes cuando estas pegado al target
--   y el destino marcado esta exactamente a 1 sqm. En este server ahora debe ser 1000 ms.
-- - Si el server cambia otra vez el delay de push, cambia primero ONE_SQM_PUSH_COOLDOWN.
-- - ONE_SQM_AFTER_RUNE_PUSH_DELAY controla cuanto esperar despues de usar runa cuando estas
--   pegado al target. En este server la medicion real es 3000 ms.
-- - DISTANCE_AFTER_RUNE_PUSH_DELAY controla cuanto esperar despues de usar runa cuando el push
--   viene desde distancia/ruta larga. En este server la medicion real es 2000 ms.
-- - ONE_SQM_HEAL_ITEMS_PAUSE_MS debe ser un poco mayor que ONE_SQM_PUSH_COOLDOWN para push normal.
--   Cuando se usa runa, el script manda una pausa mas larga solo para ese caso.
-- - STUCK_FIRST_PUSH_DELAY acompana al delay de push pegado cuando el modo no es 1 sqm directo.
local DESTROY_FIELD_RUNE_ID = 3148
local FAST_PUSH_DELAY = 20
local PLAYER_PUSH_COOLDOWN = 20
local ONE_SQM_PUSH_COOLDOWN = 1000 -- tiempo minimo entre pushes pegado + destino 1 sqm. Cambiar aqui si el server cambia el delay.
local ONE_SQM_AFTER_RUNE_PUSH_DELAY = 3000 -- despues de usar runa pegado al target, espera real antes de poder mover.
local DISTANCE_AFTER_RUNE_PUSH_DELAY = 2000 -- despues de usar runa desde distancia/ruta larga, espera real antes de poder mover.
local ONE_SQM_POST_PUSH_DELAY = 20 -- delay despues de mandar el push directo de 1 sqm
local ONE_SQM_CLEAR_FIELD_PUSH_DELAY = 10 -- despues de destroy field, intenta empujar casi inmediato
local ONE_SQM_CLEAR_FIELD_RETRY_MS = 600 -- ventana maxima para esperar que desaparezca el field
local ONE_SQM_ANTIPUSH_RUNE_DELAY = 20 -- delay minimo despues de tirar fire field/antipush rune
local ONE_SQM_ANTIPUSH_PUSH_DELAY = 100 -- espera para empujar despues de tirar fire field contra antipush
local ONE_SQM_QUEUE_RETRY_STEP = 10 -- cada cuantos ms revisa si ya puede empujar despues de limpiar field
local ONE_SQM_HEAL_ITEMS_PAUSE_MS = 1200 -- pausa items del HealBot durante push 1 sqm normal.
local ONE_SQM_RUNE_HEAL_ITEMS_PAUSE_MS = ONE_SQM_AFTER_RUNE_PUSH_DELAY + 200 -- pausa HealBot solo cuando el push 1 sqm uso runa.
local ONE_SQM_QUEUE_HOLD_MS = math.max(ONE_SQM_PUSH_COOLDOWN, ONE_SQM_AFTER_RUNE_PUSH_DELAY) + 250 -- evita repetir rune/destroy mientras ya hay un push 1 sqm pendiente.
local AUTO_ROUTE_TARGET_LOST_MS = 400 -- cancela una ruta si el target deja de estar visible brevemente
local STEP_PUSH_DELAY = 20
local POST_PUSH_DELAY = 20
local TURBO_PREDICTED_ROUTE = true
local PREDICTED_POST_PUSH_DELAY = 20
local PREDICTED_ROUTE_IMMEDIATE_PUSH = true
local PREDICTED_ROUTE_SKIP_TEXT_UPDATE = false
local STUCK_RETREAT_DELAY = 250
local RETREAT_COOLDOWN = 80
local RUNUP_PUSH_WINDOW = 10
local MAGIC_WALL_RUNE_ID = 3180
local AUTO_ROUTE_LIMIT = 40
local STUCK_FIRST_PUSH_DELAY = 1000 -- espera base anti-stuck; conviene igualarlo al cooldown real de push 1 sqm.
local cleanTile = nil

-- scripts

local targetTile
local pushTarget
local sourceTile
local destinationTile
local routeTiles = {}
local routeTargetId = nil
local autoRouteDestination = nil
local routeTextSignature = ""
local currentAttackTargetId = nil
local currentAttackTargetName = nil
local lastPushTargetPositionKey = nil
local lastPushTargetMoveAt = 0
local lastRetreatAt = 0
local lastPlayerPushAttemptAt = 0
local lastPushAttemptTargetKey = nil
local lastRunupAt = 0
local lastRunupTargetId = nil
local pendingRunupTargetId = nil
local lastPushCommandDistance = 0
local lastPushFromPos = nil
local lastPushToPos = nil
local stuckFirstPushTargetKey = nil
local stuckFirstPushStartedAt = 0
local oneSqmPushMode = false -- true solo cuando el comando original es empujar 1 sqm
local oneSqmQueuedPushKey = nil
local oneSqmQueuedPushBaseKey = nil
local oneSqmQueuedPushAt = 0
local lastPushRuneAt = 0
local lastPushRuneDelay = 0
local getCurrentTargetPlayer
local autoRouteLastSeenAt = 0

local resetData = function()
  for i, tile in pairs(g_map.getTiles(posz())) do
    local text = tile:getText()
    if text == "TARGET" or text == "DEST" or text == "CLEAR" or
      text == "PUSH X" or text == "PUSH Y" or (text and text:find("^PUSH %d+$")) then
      tile:setText('')
    end
  end
  pushTarget = nil
  targetTile = nil
  sourceTile = nil
  destinationTile = nil
  routeTiles = {}
  routeTargetId = nil
  autoRouteDestination = nil
  routeTextSignature = ""
  cleanTile = nil
  lastPushTargetPositionKey = nil
  lastPushTargetMoveAt = 0
  lastRetreatAt = 0
  lastPlayerPushAttemptAt = 0
  lastPushAttemptTargetKey = nil
  lastRunupAt = 0
  lastRunupTargetId = nil
  pendingRunupTargetId = nil
  lastPushCommandDistance = 0
  lastPushFromPos = nil
  lastPushToPos = nil
  stuckFirstPushTargetKey = nil
  stuckFirstPushStartedAt = 0
  oneSqmPushMode = false
  oneSqmQueuedPushKey = nil
  oneSqmQueuedPushBaseKey = nil
  oneSqmQueuedPushAt = 0
  lastPushRuneAt = 0
  lastPushRuneDelay = 0
  autoRouteLastSeenAt = 0
end

local getCreatureById = function(id)
  for i, spec in ipairs(getSpectators()) do
    if spec:getId() == id then
      return spec
    end
  end
  return false
end

local getCreatureByName = function(name)
  if not name then return nil end
  name = name:lower()
  for i, spec in ipairs(getSpectators()) do
    if spec:getName() and spec:getName():lower() == name then
      return spec
    end
  end
  return nil
end

local isNotOk = function(t,tile)
  local tileItems = {}

  for i, item in pairs(tile:getItems()) do
    table.insert(tileItems, item:getId())
  end
  for i, field in ipairs(t) do
    if table.find(tileItems, field) then
      return true
    end
  end
  return false
end

local cachedDestroyFieldIdsText = nil
local cachedDestroyFieldIds = nil

local getDestroyFieldIds = function()
  local text = tostring(config.destroyFieldIds or DEFAULT_DESTROY_FIELD_IDS)
  if cachedDestroyFieldIdsText == text and cachedDestroyFieldIds then
    return cachedDestroyFieldIds
  end

  local ids = {}

  for rawId in text:gmatch("%d+") do
    local id = tonumber(rawId)
    if id and not table.find(ids, id) then
      table.insert(ids, id)
    end
  end

  if #ids == 0 then
    for rawId in DEFAULT_DESTROY_FIELD_IDS:gmatch("%d+") do
      table.insert(ids, tonumber(rawId))
    end
  end

  cachedDestroyFieldIdsText = text
  cachedDestroyFieldIds = ids
  return ids
end

local getFieldThing = function(tile)
  if not tile then return nil end

  for i, item in pairs(tile:getItems()) do
    if table.find(getDestroyFieldIds(), item:getId()) then
      return item
    end
  end

  return nil
end

local canClearField = function(tile)
  return tile and tile:canShoot() and getFieldThing(tile)
end

local markPushRuneUsed = function(delayMs)
  lastPushRuneAt = now
  lastPushRuneDelay = tonumber(delayMs) or 0
end

local getRunePushCooldownRemaining = function()
  if lastPushRuneDelay <= 0 then return 0 end
  return math.max(0, lastPushRuneDelay - (now - lastPushRuneAt))
end

local clearField = function(tile, customDelay, runePushDelay)
  local fieldThing = canClearField(tile)
  if not fieldThing then return false end

  useWith(DESTROY_FIELD_RUNE_ID, fieldThing)
  if runePushDelay then
    markPushRuneUsed(runePushDelay)
  end
  delay(customDelay or POST_PUSH_DELAY)
  return true
end

local isCreatureThing = function(thing)
  if not thing then return false end
  local ok, result = pcall(function() return thing:isCreature() end)
  return ok and result
end

local tileHasCreature = function(tile)
  if not tile then return false end

  local ok, result = pcall(function()
    if tile.hasCreature then
      return tile:hasCreature()
    end

    local creatures = tile:getCreatures()
    return creatures and #creatures > 0
  end)

  return ok and result
end

local hasPosition = function(pos)
  return pos and pos.x and pos.y and pos.z
end

local safeDistance = function(a, b)
  if not hasPosition(a) or not hasPosition(b) then return nil end
  return getDistanceBetween(a, b)
end

local isOk = function(a,b)
  return safeDistance(a,b) == 1
end

local samePosition = function(a, b)
  return hasPosition(a) and hasPosition(b) and a.x == b.x and a.y == b.y and a.z == b.z
end

local sign = function(value)
  if value > 0 then return 1 end
  if value < 0 then return -1 end
  return 0
end

local isCardinalDirection = function(dir)
  return dir == 0 or dir == 1 or dir == 2 or dir == 3
end

local canUseStepDirection = function(dir)
  if dir == nil then return false end
  return isCardinalDirection(dir)
end

local directionTo = function(fromPos, toPos)
  if not hasPosition(fromPos) or not hasPosition(toPos) then return nil end

  local dx = sign(toPos.x - fromPos.x)
  local dy = sign(toPos.y - fromPos.y)
  if dx == 0 and dy == -1 then return 0 end
  if dx == 1 and dy == 0 then return 1 end
  if dx == 0 and dy == 1 then return 2 end
  if dx == -1 and dy == 0 then return 3 end
  if dx == 1 and dy == -1 then return 4 end
  if dx == 1 and dy == 1 then return 5 end
  if dx == -1 and dy == 1 then return 6 end
  if dx == -1 and dy == -1 then return 7 end
  return nil
end

local stepDirection = function(dir)
  if dir == nil then return false end

  if g_game.walk then
    local ok = pcall(function() g_game.walk(dir) end)
    if ok then return true end
  end
  if walk then
    local ok = pcall(function() walk(dir) end)
    if ok then return true end
  end
  return false
end

local getStepCandidatesToward = function(fromPos, toPos)
  if not hasPosition(fromPos) or not hasPosition(toPos) then return {} end

  local dx = sign(toPos.x - fromPos.x)
  local dy = sign(toPos.y - fromPos.y)
  local candidates = {}

  if math.abs(toPos.x - fromPos.x) >= math.abs(toPos.y - fromPos.y) then
    if dx ~= 0 then table.insert(candidates, {x = fromPos.x + dx, y = fromPos.y, z = fromPos.z}) end
    if dy ~= 0 then table.insert(candidates, {x = fromPos.x, y = fromPos.y + dy, z = fromPos.z}) end
  else
    if dy ~= 0 then table.insert(candidates, {x = fromPos.x, y = fromPos.y + dy, z = fromPos.z}) end
    if dx ~= 0 then table.insert(candidates, {x = fromPos.x + dx, y = fromPos.y, z = fromPos.z}) end
  end

  return candidates
end

local getPlayerRouteOffsets = function()
  local offsets = {
    {x = 1, y = 0}, {x = -1, y = 0}, {x = 0, y = 1}, {x = 0, y = -1}
  }

  return offsets
end

local canStandOn = function(pos)
  local tile = g_map.getTile(pos)
  if not tile then return false end
  if tileHasCreature(tile) or not tile:isWalkable() or isNotOk(getDestroyFieldIds(), tile) then return false end

  local minimapColor = g_map.getMinimapColor(pos)
  if minimapColor >= 210 and minimapColor <= 213 then return false end
  return true
end

local getPushStandPosition = function(creature, destination)
  local playerPos = player:getPosition()
  local targetPos = creature:getPosition()
  local destinationPos = destination:getPosition()
  if not hasPosition(playerPos) or not hasPosition(targetPos) or not hasPosition(destinationPos) then return nil end

  local dx = sign(destinationPos.x - targetPos.x)
  local dy = sign(destinationPos.y - targetPos.y)
  if dx ~= 0 or dy ~= 0 then
    local behind = {x = targetPos.x - dx, y = targetPos.y - dy, z = targetPos.z}
    if samePosition(playerPos, behind) or canStandOn(behind) then
      return behind
    end
  end

  local candidates = {
    {x = targetPos.x, y = targetPos.y - 1, z = targetPos.z},
    {x = targetPos.x + 1, y = targetPos.y, z = targetPos.z},
    {x = targetPos.x, y = targetPos.y + 1, z = targetPos.z},
    {x = targetPos.x - 1, y = targetPos.y, z = targetPos.z}
  }
  local bestPos
  local bestDistance
  for i, pos in ipairs(candidates) do
    if samePosition(playerPos, pos) then return pos end
    if canStandOn(pos) then
      local distance = getDistanceBetween(playerPos, pos)
      if not bestDistance or distance < bestDistance then
        bestDistance = distance
        bestPos = pos
      end
    end
  end
  return bestPos
end

local tryCrossApproach = function(creature, destination)
  if not creature or not destination then return false end
  local playerPos = player:getPosition()
  local targetPos = creature:getPosition()
  local distance = safeDistance(playerPos, targetPos)
  if not distance or distance <= 1 then return false end

  local standPos = getPushStandPosition(creature, destination)
  if not standPos then return false end

  local nextPos
  for i, candidate in ipairs(getStepCandidatesToward(playerPos, standPos)) do
    if canStandOn(candidate) then
      nextPos = candidate
      break
    end
  end

  if not nextPos or not canStandOn(nextPos) then return false end
  if not stepDirection(directionTo(playerPos, nextPos)) then return false end

  lastRunupAt = now
  lastRunupTargetId = creature:getId()
  delay(STEP_PUSH_DELAY)
  return true
end

local tryStepPush = function(creature, destination)
  if not creature or not destination then return false end

  local playerPos = player:getPosition()
  local targetPos = creature:getPosition()
  local destinationPos = destination:getPosition()
  if safeDistance(playerPos, targetPos) ~= 1 then return false end
  if safeDistance(targetPos, destinationPos) ~= 1 then return false end

  local playerToTarget = directionTo(playerPos, targetPos)
  local targetToDestination = directionTo(targetPos, destinationPos)
  if not canUseStepDirection(playerToTarget) then return false end
  if not canUseStepDirection(targetToDestination) then return false end
  if playerToTarget ~= targetToDestination then return false end
  if not stepDirection(playerToTarget) then return false end

  delay(STEP_PUSH_DELAY)
  return true
end

local routeIndex = function(pos)
  for i, routePos in ipairs(routeTiles) do
    if samePosition(routePos, pos) then
      return i
    end
  end
  return nil
end

local positionKey = function(pos)
  if not hasPosition(pos) then return nil end

  return pos.x .. "," .. pos.y .. "," .. pos.z
end

local copyPosition = function(pos)
  if not hasPosition(pos) then return nil end

  return {x = pos.x, y = pos.y, z = pos.z}
end

local pauseHealItemsForOneSqmPush = function(customMs)
  if not vBot then return end

  local pauseUntil = now + (tonumber(customMs) or ONE_SQM_HEAL_ITEMS_PAUSE_MS)
  if not vBot.pauseHealItemsUntil or vBot.pauseHealItemsUntil < pauseUntil then
    vBot.pauseHealItemsUntil = pauseUntil
  end
end

local getOneSqmPushCooldownRemaining = function()
  return math.max(0, ONE_SQM_PUSH_COOLDOWN - (now - lastPlayerPushAttemptAt), getRunePushCooldownRemaining())
end

local sendOneSqmMove = function(creature, destPos, fromPos, distance)
  pauseHealItemsForOneSqmPush()
  g_game.move(creature, destPos)
  lastPlayerPushAttemptAt = now
  lastPushAttemptTargetKey = positionKey(fromPos)
  pendingRunupTargetId = nil
  lastPushCommandDistance = distance or safeDistance(player:getPosition(), fromPos) or 0
  lastPushFromPos = copyPosition(fromPos)
  lastPushToPos = copyPosition(destPos)
end

local buildPlayerRoute = function(startPos, endPos, limit)
  if not startPos or not endPos or startPos.z ~= endPos.z then return nil end

  local startKey = positionKey(startPos)
  local endKey = positionKey(endPos)
  local queue = {copyPosition(startPos)}
  local head = 1
  local cameFrom = {}
  local distance = {[startKey] = 0}
  local positions = {[startKey] = copyPosition(startPos)}
  local offsets = getPlayerRouteOffsets()

  if samePosition(startPos, endPos) then
    return {copyPosition(startPos)}
  end

  while queue[head] do
    local current = queue[head]
    head = head + 1
    local currentKey = positionKey(current)
    if distance[currentKey] < limit then
      for i, offset in ipairs(offsets) do
        local nextPos = {x = current.x + offset.x, y = current.y + offset.y, z = current.z}
        local nextKey = positionKey(nextPos)

        if not distance[nextKey] and canStandOn(nextPos) then
          cameFrom[nextKey] = currentKey
          distance[nextKey] = distance[currentKey] + 1
          positions[nextKey] = nextPos

          if nextKey == endKey then
            local route = {}
            local key = endKey
            while key do
              table.insert(route, 1, positions[key])
              key = cameFrom[key]
            end
            return route
          end

          table.insert(queue, nextPos)
        end
      end
    end
  end

  return nil
end

local tryMoveToPushStandPosition = function(creature, destination)
  if not creature or not destination then return false end

  local standPos = getPushStandPosition(creature, destination)
  if not standPos then return false end

  local playerPos = player:getPosition()
  if not hasPosition(playerPos) then return false end
  if samePosition(playerPos, standPos) then return false end

  local route = buildPlayerRoute(playerPos, standPos, 6)
  if route and #route >= 2 then
    local dir = directionTo(route[1], route[2])
    if canUseStepDirection(dir) and stepDirection(dir) then
      lastRunupAt = now
      lastRunupTargetId = creature:getId()
      delay(STEP_PUSH_DELAY)
      return true
    end
  end

  return false
end

local isAtPushStandPosition = function(creature, destination)
  if not creature or not destination then return false end

  local standPos = getPushStandPosition(creature, destination)
  return standPos and samePosition(player:getPosition(), standPos)
end

local tryRetreatFromTarget = function(creature, destination)
  if not creature then return false end

  local playerPos = player:getPosition()
  local targetPos = creature:getPosition()
  local currentDistance = safeDistance(playerPos, targetPos)
  if not currentDistance then return false end
  local standPos = getPushStandPosition(creature, destination)
  local desiredPos

  if standPos then
    local dx = sign(standPos.x - targetPos.x)
    local dy = sign(standPos.y - targetPos.y)
    desiredPos = {x = standPos.x + dx, y = standPos.y + dy, z = standPos.z}
  end

  local cardinalCandidates = {
    {x = playerPos.x + 1, y = playerPos.y, z = playerPos.z},
    {x = playerPos.x - 1, y = playerPos.y, z = playerPos.z},
    {x = playerPos.x, y = playerPos.y + 1, z = playerPos.z},
    {x = playerPos.x, y = playerPos.y - 1, z = playerPos.z}
  }

  local getBestRetreat = function(candidates)
    local bestPos
    local bestScore
    for i, pos in ipairs(candidates) do
      local distanceFromTarget = getDistanceBetween(pos, targetPos)
      if distanceFromTarget > currentDistance and canStandOn(pos) then
        local score = distanceFromTarget * 10
        if desiredPos then
          score = score - getDistanceBetween(pos, desiredPos)
        end
        if not bestScore or score > bestScore then
          bestScore = score
          bestPos = pos
        end
      end
    end
    return bestPos
  end

  local bestPos = getBestRetreat(cardinalCandidates)
  if not bestPos then return false end
  if not stepDirection(directionTo(playerPos, bestPos)) then return false end

  lastRetreatAt = now
  pendingRunupTargetId = creature:getId()
  lastRunupAt = 0
  lastRunupTargetId = nil
  delay(STEP_PUSH_DELAY)
  return true
end

local routeSignature = function(route)
  local parts = {}
  for i, pos in ipairs(route) do
    parts[i] = positionKey(pos)
  end
  return table.concat(parts, "|")
end

local clearRouteTexts = function()
  for i, tile in pairs(g_map.getTiles(posz())) do
    local text = tile:getText()
    if text == "TARGET" or text == "DEST" or text == "PUSH X" or text == "PUSH Y" or
      (text and text:find("^PUSH %d+$")) then
      tile:setText("")
    end
  end
end

local showRoute = function(route)
  local signature = routeSignature(route)
  if signature == routeTextSignature then return end

  clearRouteTexts()
  routeTiles = route or {}
  routeTextSignature = signature

  local finalPos = routeTiles[#routeTiles]
  local finalTile = finalPos and g_map.getTile(finalPos) or nil
  if finalTile then
    finalTile:setText("DEST")
  end

  sourceTile = routeTiles[1] and g_map.getTile(routeTiles[1]) or nil
  destinationTile = routeTiles[2] and g_map.getTile(routeTiles[2]) or nil
end

local addRouteTile = function(tile)
  if not tile then return false end

  local pos = tile:getPosition()
  if #routeTiles > 0 and not isOk(routeTiles[#routeTiles], pos) then
    resetData()
    return false
  end

  if routeIndex(pos) then
    resetData()
    return false
  end

  table.insert(routeTiles, pos)
  routeTargetId = nil
  autoRouteDestination = nil
  showRoute(routeTiles)
  oneSqmPushMode = (#routeTiles == 2)

  return true
end

local isRouteTileWalkable = function(pos, startPos, endPos)
  if not pos or pos.z ~= startPos.z then return false end

  local tile = g_map.getTile(pos)
  if not tile then return false end
  if samePosition(pos, startPos) then return true end
  if tileHasCreature(tile) then return false end
  if samePosition(pos, endPos) then return true end

  local minimapColor = g_map.getMinimapColor(pos)
  if minimapColor >= 210 and minimapColor <= 213 then return false end

  if getFieldThing(tile) then
    return tile:canShoot()
  end

  return tile:isWalkable()
end

local buildPushRoute = function(startPos, endPos)
  if not startPos or not endPos or startPos.z ~= endPos.z then return nil end

  local startKey = positionKey(startPos)
  local endKey = positionKey(endPos)
  local queue = {copyPosition(startPos)}
  local head = 1
  local cameFrom = {}
  local distance = {[startKey] = 0}
  local positions = {[startKey] = copyPosition(startPos)}
  local offsets = {
    {x = 1, y = 0}, {x = -1, y = 0}, {x = 0, y = 1}, {x = 0, y = -1},
    {x = 1, y = 1}, {x = 1, y = -1}, {x = -1, y = 1}, {x = -1, y = -1}
  }

  if samePosition(startPos, endPos) then
    return {copyPosition(startPos)}
  end

  while queue[head] do
    local current = queue[head]
    head = head + 1
    local currentKey = positionKey(current)
    if distance[currentKey] < AUTO_ROUTE_LIMIT then
      for i, offset in ipairs(offsets) do
        local nextPos = {x = current.x + offset.x, y = current.y + offset.y, z = current.z}
        local nextKey = positionKey(nextPos)

        if not distance[nextKey] and isRouteTileWalkable(nextPos, startPos, endPos) then
          cameFrom[nextKey] = currentKey
          distance[nextKey] = distance[currentKey] + 1
          positions[nextKey] = nextPos

          if nextKey == endKey then
            local route = {}
            local key = endKey
            while key do
              table.insert(route, 1, positions[key])
              key = cameFrom[key]
            end
            return route
          end

          table.insert(queue, nextPos)
        end
      end
    end
  end

  return nil
end

local getPredictedPushRoute = function(creature, finalPos)
  if not TURBO_PREDICTED_ROUTE or not creature or not finalPos or #routeTiles < 2 then return nil end

  local targetPos = creature:getPosition()
  if not hasPosition(targetPos) or not hasPosition(finalPos) or targetPos.z ~= finalPos.z then return nil end
  if not samePosition(routeTiles[#routeTiles], finalPos) then return nil end

  local targetRouteIndex = routeIndex(targetPos)
  if not targetRouteIndex or targetRouteIndex >= #routeTiles then return nil end

  local route = {}
  for i = targetRouteIndex, #routeTiles do
    table.insert(route, copyPosition(routeTiles[i]))
  end
  return route
end

local isPredictedRouteAdvance = function(newPos, oldPos)
  if not TURBO_PREDICTED_ROUTE or not autoRouteDestination or not newPos then return false end
  if #routeTiles < 2 or not samePosition(routeTiles[#routeTiles], autoRouteDestination) then return false end

  local newRouteIndex = routeIndex(newPos)
  if not newRouteIndex or newRouteIndex >= #routeTiles then return false end

  if not oldPos then return newRouteIndex <= 2 end
  local oldRouteIndex = routeIndex(oldPos)
  return oldRouteIndex and newRouteIndex == oldRouteIndex + 1
end

local getDirectPushTile = function(creature, finalPos)
  if not creature or not finalPos then return nil end

  local targetPos = creature:getPosition()
  if not hasPosition(targetPos) or not hasPosition(finalPos) then return nil end

  local currentDistance = safeDistance(targetPos, finalPos)
  if not currentDistance then return nil end
  local offsets = {
    {x = 1, y = 0}, {x = -1, y = 0}, {x = 0, y = 1}, {x = 0, y = -1},
    {x = 1, y = 1}, {x = 1, y = -1}, {x = -1, y = 1}, {x = -1, y = -1}
  }
  local bestTile
  local bestDistance = currentDistance

  for i, offset in ipairs(offsets) do
    local pos = {x = targetPos.x + offset.x, y = targetPos.y + offset.y, z = targetPos.z}
    local distance = safeDistance(pos, finalPos)
    if distance and distance < bestDistance and isRouteTileWalkable(pos, targetPos, finalPos) then
      bestDistance = distance
      bestTile = g_map.getTile(pos)
    end
  end

  return bestTile
end

getCurrentTargetPlayer = function()
  local currentTarget

  if g_game and g_game.getAttackingCreature then
    local ok, creature = pcall(function() return g_game.getAttackingCreature() end)
    if ok and creature then currentTarget = creature end
  end
  if not currentTarget and type(target) == "function" then
    local ok, creature = pcall(target)
    if ok and creature then currentTarget = creature end
  end
  if not currentTarget and type(getTarget) == "function" then
    local ok, creature = pcall(getTarget)
    if ok and creature then currentTarget = creature end
  end

  local okPlayer, isPlayerTarget = false, false
  if currentTarget then
    okPlayer, isPlayerTarget = pcall(function() return currentTarget:isPlayer() end)
  end
  local currentTargetPos = currentTarget and currentTarget:getPosition() or nil
  if currentTarget and currentTarget ~= player and okPlayer and isPlayerTarget and hasPosition(currentTargetPos) and currentTargetPos.z == posz() then
    currentAttackTargetId = currentTarget:getId()
    currentAttackTargetName = currentTarget:getName()
    return currentTarget
  end
  if currentAttackTargetId then
    local remembered = getCreatureById(currentAttackTargetId)
    local rememberedPos = remembered and remembered:getPosition() or nil
    if remembered and remembered ~= player and hasPosition(rememberedPos) and rememberedPos.z == posz() then
      return remembered
    end
  end
  if currentAttackTargetName then
    local remembered = getCreatureByName(currentAttackTargetName)
    local rememberedPos = remembered and remembered:getPosition() or nil
    if remembered and remembered ~= player and hasPosition(rememberedPos) and rememberedPos.z == posz() then
      currentAttackTargetId = remembered:getId()
      return remembered
    end
  end
  return nil
end

local setAutoRouteTarget = function(creature, tile)
  if not creature or not tile then return false end
  if creature == player or not creature:isPlayer() then return false end

  local destination = tile:getPosition()
  local targetPos = creature:getPosition()
  if not hasPosition(targetPos) or not hasPosition(destination) or targetPos.z ~= destination.z then return false end
  local targetToDestinationDistance = safeDistance(targetPos, destination)
  local route = buildPushRoute(targetPos, destination)

  clearRouteTexts()
  routeTiles = {}
  routeTextSignature = ""
  pushTarget = creature
  targetTile = nil
  sourceTile = nil
  destinationTile = nil
  cleanTile = nil
  routeTargetId = creature:getId()
  currentAttackTargetId = creature:getId()
  currentAttackTargetName = creature:getName()
  autoRouteDestination = copyPosition(destination)
  autoRouteLastSeenAt = now
  oneSqmPushMode = (targetToDestinationDistance == 1) or (route and #route == 2)
  if route and #route >= 2 then
    showRoute(route)
  else
    tile:setText("DEST")
  end
  creature:setMarked("#00FF00")
  return true
end

local getPushablePlayer = function(tile)
  if not tile then return nil end
  for i, creature in ipairs(tile:getCreatures()) do
    if creature ~= player and creature:isPlayer() then
      return creature
    end
  end
  return nil
end

local getRouteTargetOnTile = function(tile)
  if not tile then return nil end
  if not routeTargetId then return getPushablePlayer(tile) end
  for i, creature in ipairs(tile:getCreatures()) do
    if creature:getId() == routeTargetId then
      return creature
    end
  end
  return nil
end

local canUseFinalMwallOn = function(tile, mwallObjectId)
  if not tile then return false end
  if tileHasCreature(tile) then return false end
  if not tile:isWalkable() or not tile:canShoot() then return false end

  local topThing = tile:getTopUseThing()
  if not topThing then return false end
  if mwallObjectId and topThing:getId() == mwallObjectId then return false end

  return true
end

local addUniquePosition = function(list, seen, pos)
  if not pos then return end

  local key = positionKey(pos)
  if seen[key] then return end

  seen[key] = true
  table.insert(list, pos)
end

local getFinalMwallTile = function(finalPos, fromPos, mwallObjectId)
  if not finalPos then return nil end

  local seen = {}
  local sideCandidates = {}
  local fallbackCandidates = {}
  if fromPos and fromPos.z == finalPos.z then
    local dx = sign(finalPos.x - fromPos.x)
    local dy = sign(finalPos.y - fromPos.y)
    if dx ~= 0 or dy ~= 0 then
      addUniquePosition(sideCandidates, seen, {x = finalPos.x - dy, y = finalPos.y + dx, z = finalPos.z})
      addUniquePosition(sideCandidates, seen, {x = finalPos.x + dy, y = finalPos.y - dx, z = finalPos.z})
      addUniquePosition(fallbackCandidates, seen, {x = finalPos.x - dx, y = finalPos.y - dy, z = finalPos.z})
      addUniquePosition(fallbackCandidates, seen, {x = finalPos.x + dx, y = finalPos.y + dy, z = finalPos.z})
    end
  end

  addUniquePosition(fallbackCandidates, seen, {x = finalPos.x + 1, y = finalPos.y, z = finalPos.z})
  addUniquePosition(fallbackCandidates, seen, {x = finalPos.x - 1, y = finalPos.y, z = finalPos.z})
  addUniquePosition(fallbackCandidates, seen, {x = finalPos.x, y = finalPos.y + 1, z = finalPos.z})
  addUniquePosition(fallbackCandidates, seen, {x = finalPos.x, y = finalPos.y - 1, z = finalPos.z})

  local playerPos = player:getPosition()
  local getBestTile = function(candidates)
    local bestTile
    local bestDistance
    for i, pos in ipairs(candidates) do
      local tile = g_map.getTile(pos)
      if canUseFinalMwallOn(tile, mwallObjectId) then
        local distance = getDistanceBetween(playerPos, pos)
        if not bestDistance or distance < bestDistance then
          bestDistance = distance
          bestTile = tile
        end
      end
    end
    return bestTile
  end

  return getBestTile(sideCandidates) or getBestTile(fallbackCandidates)
end

local castFinalMwall = function(finalPos, fromPos, mwallRuneId, mwallObjectId)
  local tile = getFinalMwallTile(finalPos, fromPos, mwallObjectId)
  if not tile then return false end

  local topThing = tile:getTopUseThing()
  if not topThing then return false end

  useWith(tonumber(mwallRuneId) or MAGIC_WALL_RUNE_ID, topThing)
  delay(POST_PUSH_DELAY)
  return true
end

local getOneSqmQueueKeys = function(creature, tilePos, reason)
  if not creature or not tilePos then return nil, nil end

  local creatureId = creature:getId()
  local targetKey = positionKey(creature:getPosition())
  local destKey = positionKey(tilePos)
  if not targetKey or not destKey then return nil, nil end

  local baseKey = tostring(creatureId) .. "|" .. targetKey .. ">" .. destKey
  return baseKey .. "|" .. tostring(reason or "push"), baseKey
end

local hasQueuedOneSqmPush = function(creature, tilePos, windowMs)
  local _, baseKey = getOneSqmQueueKeys(creature, tilePos, "any")
  if not baseKey then return false end
  local window = tonumber(windowMs) or 800

  return oneSqmQueuedPushBaseKey == baseKey and now - oneSqmQueuedPushAt < window
end

local queueOneSqmDirectPush = function(creature, tilePos, waitMs, reason, requireClearDestination, maxWaitMs)
  if not creature or not tilePos then return false end

  local queueKey, baseKey = getOneSqmQueueKeys(creature, tilePos, reason)
  if not queueKey or not baseKey then return false end

  local wait = tonumber(waitMs) or 0
  local maxWait = tonumber(maxWaitMs) or wait
  local duplicateWindow = math.max(wait + maxWait + 100, ONE_SQM_QUEUE_HOLD_MS)
  if oneSqmQueuedPushKey == queueKey and now - oneSqmQueuedPushAt < duplicateWindow then
    return true
  end

  local creatureId = creature:getId()
  local startTargetPos = copyPosition(creature:getPosition())
  local destPos = copyPosition(tilePos)
  local startedAt = now

  oneSqmQueuedPushKey = queueKey
  oneSqmQueuedPushBaseKey = baseKey
  oneSqmQueuedPushAt = now

  local function tryQueuedPush()
    if oneSqmQueuedPushKey ~= queueKey then return end

    local liveCreature = getCreatureById(creatureId)
    if not liveCreature then
      oneSqmQueuedPushKey = nil
      oneSqmQueuedPushBaseKey = nil
      return
    end

    local livePos = copyPosition(liveCreature:getPosition())
    if not samePosition(livePos, startTargetPos) or safeDistance(livePos, destPos) ~= 1 then
      oneSqmQueuedPushKey = nil
      oneSqmQueuedPushBaseKey = nil
      return
    end

    local liveDestination = g_map.getTile(destPos)
    if not liveDestination then
      oneSqmQueuedPushKey = nil
      oneSqmQueuedPushBaseKey = nil
      return
    end

    if requireClearDestination and isNotOk(getDestroyFieldIds(), liveDestination) then
      if now - startedAt < maxWait then
        schedule(ONE_SQM_QUEUE_RETRY_STEP, tryQueuedPush)
      else
        oneSqmQueuedPushKey = nil
        oneSqmQueuedPushBaseKey = nil
      end
      return
    end

    local cooldownRemaining = getOneSqmPushCooldownRemaining()
    if cooldownRemaining > 0 then
      schedule(math.max(ONE_SQM_QUEUE_RETRY_STEP, cooldownRemaining), tryQueuedPush)
      return
    end

    sendOneSqmMove(liveCreature, destPos, livePos, safeDistance(player:getPosition(), livePos) or 1)
    oneSqmQueuedPushKey = nil
    oneSqmQueuedPushBaseKey = nil
    -- IMPORTANTE:
    -- No usar delay() dentro de este callback de schedule().
    -- En OTC/vBot puede lanzar: "Invalid usage of delay function".
    -- El cooldown real ya queda protegido por lastPlayerPushAttemptAt,
    -- ONE_SQM_PUSH_COOLDOWN y el delay post-runa, asi que aqui no hace falta delay().
  end

  schedule(wait, tryQueuedPush)
  return true
end

local pushCreatureToTile = function(creature, destination, pushDelay, rune, customMwall, postPushDelay, directOneSqmPush)
  if not creature or not destination then return false end

  local tilePos = destination:getPosition()
  local targetPos = creature:getPosition()
  if not hasPosition(tilePos) or not hasPosition(targetPos) or not isOk(tilePos, targetPos) then return false end

  local tileOfTarget = g_map.getTile(targetPos)
  if not tileOfTarget then return false end

  directOneSqmPush = directOneSqmPush == true

  if directOneSqmPush and hasQueuedOneSqmPush(creature, tilePos, ONE_SQM_QUEUE_HOLD_MS) then
    return true
  end

  -- En 1 sqm directo, si el destino tiene field, primero lo quita y deja un push programado
  -- para dispararse apenas el tile quede libre. Esto evita esperar otro ciclo completo del macro.
  if directOneSqmPush and isNotOk(getDestroyFieldIds(), destination) then
    local fieldThing = canClearField(destination)
    if not fieldThing then return false end

    pauseHealItemsForOneSqmPush(ONE_SQM_RUNE_HEAL_ITEMS_PAUSE_MS)
    useWith(DESTROY_FIELD_RUNE_ID, fieldThing)
    markPushRuneUsed(ONE_SQM_AFTER_RUNE_PUSH_DELAY)
    queueOneSqmDirectPush(creature, tilePos, ONE_SQM_CLEAR_FIELD_PUSH_DELAY, "clearfield", true,
      math.max(ONE_SQM_CLEAR_FIELD_RETRY_MS, ONE_SQM_AFTER_RUNE_PUSH_DELAY))
    delay(ONE_SQM_CLEAR_FIELD_PUSH_DELAY)
    return true
  end

  if not destination:isWalkable() then
    local topThing = destination:getTopUseThing()
    if not topThing then return false end

    local topThingId = topThing:getId()
    if topThingId == 2129 or topThingId == 2130 or topThingId == customMwall then
      if destination:getTimer() < pushDelay + 500 then
        vBot.isUsing = true
        schedule(pushDelay + 700, function()
          vBot.isUsing = false
        end)
      end
      if destination:getTimer() > pushDelay then
        return true
      end
    else
      return false
    end
  end

  local playerDistance = safeDistance(player:getPosition(), creature:getPosition())
  if not playerDistance then return false end

  if directOneSqmPush and playerDistance == 0 then
    local cooldownRemaining = getOneSqmPushCooldownRemaining()
    if cooldownRemaining > 0 then return true end

    sendOneSqmMove(creature, tilePos, targetPos, 0)
    delay(ONE_SQM_POST_PUSH_DELAY)
    return true
  end

  local targetThing = tileOfTarget:getTopUseThing()
  if targetThing and not isCreatureThing(targetThing) and not targetThing:isNotMoveable() and
    destination:getTimer() < pushDelay + 500 then
    local runeCooldownRemaining = getRunePushCooldownRemaining()
    if runeCooldownRemaining > 0 then return true end

    if directOneSqmPush then
      -- Antipush pegado: en el modo nuevo tambien debe tirar fire field/runa,
      -- pero sin meter la espera vieja de stuck. Programa el push para el timing real del server.
      pauseHealItemsForOneSqmPush(ONE_SQM_RUNE_HEAL_ITEMS_PAUSE_MS)
      useWith(rune, creature)
      markPushRuneUsed(ONE_SQM_AFTER_RUNE_PUSH_DELAY)
      queueOneSqmDirectPush(creature, tilePos, ONE_SQM_ANTIPUSH_PUSH_DELAY, "antipush", false, ONE_SQM_ANTIPUSH_PUSH_DELAY)
      delay(ONE_SQM_ANTIPUSH_RUNE_DELAY)
      return true
    end

    useWith(rune, creature)
    markPushRuneUsed(DISTANCE_AFTER_RUNE_PUSH_DELAY)
    return true
  end

  if isNotOk(getDestroyFieldIds(), destination) then
    return clearField(destination, nil, DISTANCE_AFTER_RUNE_PUSH_DELAY)
  end

  local targetPositionKey = positionKey(targetPos)
  if lastPushTargetPositionKey ~= targetPositionKey then
    lastPushTargetPositionKey = targetPositionKey
    lastPushTargetMoveAt = now
    lastPushAttemptTargetKey = nil
    lastRetreatAt = 0
    pendingRunupTargetId = nil
    stuckFirstPushTargetKey = nil
    stuckFirstPushStartedAt = 0
  end

  local playerPushCooldown = directOneSqmPush and ONE_SQM_PUSH_COOLDOWN or math.max(pushDelay, PLAYER_PUSH_COOLDOWN)
  local waitingForRunup = pendingRunupTargetId == creature:getId()
  local useStuckFirstPushDelay = false
  if playerDistance > 2 then
    local approached = tryCrossApproach(creature, destination)
    if approached then return true end
    if not approached then
      local positioned = tryMoveToPushStandPosition(creature, destination)
      if positioned then return true end
    end
  elseif playerDistance == 1 then
    if directOneSqmPush then
      -- Push de 1 sqm: no retrocede ni espera el anti-stuck inicial.
      -- Esto evita que se quede congelado cuando estás pegado al target y no hay sqm atrás.
      pendingRunupTargetId = nil
      stuckFirstPushTargetKey = nil
      stuckFirstPushStartedAt = 0
    else
      if waitingForRunup and now - lastRetreatAt < RETREAT_COOLDOWN then return true end
      if lastPushAttemptTargetKey == targetPositionKey and lastPushCommandDistance > 1 and
        now - lastPlayerPushAttemptAt < STUCK_RETREAT_DELAY then
        return true
      end
      if now - lastRetreatAt < RETREAT_COOLDOWN then return true end

      local retreated = tryRetreatFromTarget(creature, destination)
      if retreated then
        stuckFirstPushTargetKey = nil
        stuckFirstPushStartedAt = 0
        return true
      end

      if stuckFirstPushTargetKey ~= targetPositionKey then
        stuckFirstPushTargetKey = targetPositionKey
        stuckFirstPushStartedAt = now
        return true
      end

      if now - stuckFirstPushStartedAt < STUCK_FIRST_PUSH_DELAY then return true end
      useStuckFirstPushDelay = true
    end
  end

  local runeCooldownRemaining = getRunePushCooldownRemaining()
  if runeCooldownRemaining > 0 then return true end

  if now - lastPlayerPushAttemptAt < playerPushCooldown then return true end

  if directOneSqmPush then
    sendOneSqmMove(creature, tilePos, targetPos, playerDistance)
  else
    g_game.move(creature, tilePos)
    lastPlayerPushAttemptAt = now
    lastPushAttemptTargetKey = targetPositionKey
    pendingRunupTargetId = nil
    lastPushCommandDistance = playerDistance
    lastPushFromPos = copyPosition(targetPos)
    lastPushToPos = copyPosition(tilePos)
  end
  local finalDelay = postPushDelay or POST_PUSH_DELAY
  if directOneSqmPush then
    finalDelay = ONE_SQM_POST_PUSH_DELAY
  end
  delay(useStuckFirstPushDelay and STUCK_FIRST_PUSH_DELAY or finalDelay)
  return true
end

local getPushRuntimeConfig = function()
  local pushDelay = tonumber(config.pushDelay) or FAST_PUSH_DELAY
  if pushDelay < FAST_PUSH_DELAY then pushDelay = FAST_PUSH_DELAY end

  return pushDelay,
    tonumber(config.pushMaxRuneId) or 3188,
    tonumber(config.finalMwallRuneId) or MAGIC_WALL_RUNE_ID,
    tonumber(config.mwallBlockId) or config.mwallBlockId
end

local tryPredictedRoutePush = function(routeTarget, pushDelay, rune, customMwall, directOneSqmPush)
  if not TURBO_PREDICTED_ROUTE or not autoRouteDestination then return false end

  local predictedRoute = getPredictedPushRoute(routeTarget, autoRouteDestination)
  if not predictedRoute or #predictedRoute < 2 then return false end

  local nextTile = g_map.getTile(predictedRoute[2])
  if not nextTile then return false end

  return pushCreatureToTile(routeTarget, nextTile, pushDelay, rune, customMwall, PREDICTED_POST_PUSH_DELAY, directOneSqmPush == true)
end

-- to mark
local hold = 0
onKeyDown(function(keys)
  if keys == "Escape" or keys == "Esc" then
    resetData()
    return
  end
  if not config.enabled then return end
  if keys ~= config.pushMaxKey then return end
  hold = now
  local tile = getTileUnderCursor()
  if not tile then return end
  local currentTarget = getCurrentTargetPlayer()
  if not currentTarget and routeTargetId then
    currentTarget = getCreatureById(routeTargetId)
  end
  if not currentTarget and currentAttackTargetName then
    currentTarget = getCreatureByName(currentAttackTargetName)
  end
  if currentTarget then
    setAutoRouteTarget(currentTarget, tile)
    return
  end

  if autoRouteDestination then return end
  local creature = tile:getCreatures()[1]
  if #routeTiles > 0 then
    addRouteTile(tile)
  elseif not pushTarget then
    addRouteTile(tile)
  end
end)

-- mark tile to throw anything from it
onKeyPress(function(keys)
  if not config.enabled then return end
  if keys ~= config.pushMaxKey then return end
  local tile = getTileUnderCursor()
  if not tile then return end

  if (hold - now) < -2500 then
    if #routeTiles > 0 or autoRouteDestination then
      resetData()
      return
    end
    if cleanTile and tile ~= cleanTile then
      resetData()
    elseif not cleanTile then
      cleanTile = tile
      tile:setText("CLEAR")
    end
  end
  hold = 0
end)

onCreaturePositionChange(function(creature, newPos, oldPos)
  if not config.enabled then return end
  if creature == player then
    if cleanTile or targetTile or (pushTarget and not autoRouteDestination) then
      resetData()
    elseif autoRouteDestination and newPos and autoRouteDestination.z ~= newPos.z then
      resetData()
      return
    elseif not autoRouteDestination and routeTiles[1] and newPos and routeTiles[1].z ~= newPos.z then
      resetData()
    end
  end

  if autoRouteDestination and routeTargetId and newPos and hasPosition(newPos) then
    local okId, creatureId = pcall(function() return creature:getId() end)
    if okId and creatureId == routeTargetId and autoRouteDestination.z ~= newPos.z then
      resetData()
      return
    end
  end

  if PREDICTED_ROUTE_IMMEDIATE_PUSH and newPos and routeTargetId and autoRouteDestination and
    creature:getId() == routeTargetId and isPredictedRouteAdvance(newPos, oldPos) then
    local pushDelay, rune, finalMwallRune, customMwall = getPushRuntimeConfig()
    if tryPredictedRoutePush(creature, pushDelay, rune, customMwall, oneSqmPushMode) then return end
  end
  if not pushTarget or not targetTile then return end
  if creature == pushTarget and samePosition(newPos, targetTile:getPosition()) then
    resetData()
  end
end)

onAttackingCreatureChange(function(newCreature, oldCreature)
  if not config.enabled then return end
  if newCreature and newCreature ~= player then
    local ok, isPlayerTarget = pcall(function() return newCreature:isPlayer() end)
    if ok and isPlayerTarget then
      local newTargetId = newCreature:getId()
      if autoRouteDestination and routeTargetId and newTargetId ~= routeTargetId then
        resetData()
      end
      currentAttackTargetId = newTargetId
      currentAttackTargetName = newCreature:getName()
    end
  end
end)

macro(20, function()
  if not config.enabled then return end

  local pushDelay, rune, finalMwallRune, customMwall = getPushRuntimeConfig()

  if cleanTile then
    local tilePos = cleanTile:getPosition()
    local pPos = player:getPosition()
    if not isOk(tilePos, pPos) then
      resetData()
      return
    end

    if not tileHasCreature(cleanTile) then return end
    local tiles = getNearTiles(tilePos)
    local destTile
    local forbidden = {}
    -- unfortunately double loop
    for i, tile in pairs(tiles) do
      local minimapColor = g_map.getMinimapColor(tile:getPosition())
      local stairs = (minimapColor >= 210 and minimapColor <= 213)
      if stairs then
        table.insert(forbidden, tile:getPosition())
      end
    end
    for i, tile in pairs(tiles) do
      local minimapColor = g_map.getMinimapColor(tile:getPosition())
      local stairs = (minimapColor >= 210 and minimapColor <= 213)
      if tile:isWalkable() and not isNotOk(getDestroyFieldIds(), tile) and not tileHasCreature(tile) and not stairs then
        local tooClose = false
        if #forbidden ~= 0 then
          for i=1,#forbidden do
            local pos = forbidden[i]
            if isOk(pos, tile:getPosition()) then
              tooClose = true
              break
            end
          end
        end
        if not tooClose then
          destTile = tile
          break
        end
      end
    end

    if not destTile then return end
    local parcel = cleanTile:getCreatures()[1]
    if parcel then
      g_game.move(parcel,destTile:getPosition())
      delay(2000)
    end
  elseif autoRouteDestination and routeTargetId then
    local routeTarget = getCreatureById(routeTargetId)
    if not routeTarget then
      if autoRouteLastSeenAt == 0 then autoRouteLastSeenAt = now end
      if now - autoRouteLastSeenAt >= AUTO_ROUTE_TARGET_LOST_MS then resetData() end
      return
    end
    pushTarget = routeTarget
    local routeTargetPos = routeTarget:getPosition()
    if not hasPosition(routeTargetPos) then return end
    if autoRouteDestination.z ~= routeTargetPos.z then
      resetData()
      return
    end
    autoRouteLastSeenAt = now

    local playerPos = player:getPosition()
    if not hasPosition(playerPos) or playerPos.z ~= routeTargetPos.z then
      resetData()
      return
    end

    local activeOneSqmPushMode = oneSqmPushMode and safeDistance(routeTargetPos, autoRouteDestination) == 1
    if samePosition(routeTargetPos, autoRouteDestination) then
      castFinalMwall(routeTargetPos, lastPushFromPos, finalMwallRune, customMwall)
      resetData()
      return
    end

    local predictedPushed = tryPredictedRoutePush(routeTarget, pushDelay, rune, customMwall, activeOneSqmPushMode)
    if predictedPushed then return end

    local predictedRoute = getPredictedPushRoute(routeTarget, autoRouteDestination)
    local route = predictedRoute or buildPushRoute(routeTargetPos, autoRouteDestination)
    if not route or #route < 2 then
      local directTile = getDirectPushTile(routeTarget, autoRouteDestination)
      if directTile then
        pushCreatureToTile(routeTarget, directTile, pushDelay, rune, customMwall, nil, activeOneSqmPushMode)
      end
      return
    end

    if not predictedRoute or not PREDICTED_ROUTE_SKIP_TEXT_UPDATE then
      showRoute(route)
    end
    local nextTile = g_map.getTile(route[2])
    if nextTile then
      local pushed = pushCreatureToTile(routeTarget, nextTile, pushDelay, rune, customMwall,
        predictedRoute and PREDICTED_POST_PUSH_DELAY or nil, activeOneSqmPushMode)
      if not pushed and predictedRoute then
        routeTargetPos = routeTarget:getPosition()
        if not hasPosition(routeTargetPos) then return end
        route = buildPushRoute(routeTargetPos, autoRouteDestination)
        if route and #route >= 2 then
          showRoute(route)
          nextTile = g_map.getTile(route[2])
          if nextTile then
            pushCreatureToTile(routeTarget, nextTile, pushDelay, rune, customMwall, nil, activeOneSqmPushMode)
          end
        end
      end
    end
  elseif #routeTiles >= 2 then
    for i = #routeTiles - 1, 1, -1 do
      if not isOk(routeTiles[i], routeTiles[i + 1]) then
        resetData()
        return
      end

      local routeSourceTile = g_map.getTile(routeTiles[i])
      local routeDestinationTile = g_map.getTile(routeTiles[i + 1])
      local routeTarget = getRouteTargetOnTile(routeSourceTile)
      if routeTarget and routeDestinationTile then
        pushCreatureToTile(routeTarget, routeDestinationTile, pushDelay, rune, customMwall, nil, #routeTiles == 2)
        return
      end
    end
  else
    if not pushTarget or not targetTile then return end
    if not pushCreatureToTile(pushTarget, targetTile, pushDelay, rune, customMwall, nil, oneSqmPushMode) and
      isOk(targetTile:getPosition(), pushTarget:getPosition()) then
      resetData()
    end
  end
end)
