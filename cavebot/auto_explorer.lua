-- Auto Explorer for CaveBot.
-- It walks reachable unvisited tiles inside a configured radius and can follow floor changes.
CaveBot.AutoExplorer = CaveBot.AutoExplorer or {}

local AutoExplorer = CaveBot.AutoExplorer
local THINK_INTERVAL = 50
local FAST_STEP_DELAY = 60
local SCAN_INTERVAL = 180
local EMPTY_SCAN_INTERVAL = 650
local MAX_PATH_CHECKS = 18
local BLOCK_TIME = 8000
local STUCK_TIME = 2200
local NO_PROGRESS_TIME = 3500
local COVERAGE_RADIUS = 2
local FRONTIER_RADIUS = 4
local RECENT_TARGET_TIME = 12000
local TARGETBOT_PAUSE_DELAY = 250
local PATROL_RECENT_TIME = 45000
local DEATH_START_GRACE = 2500
local DEATH_HP_CONFIRM_TIME = 1800
local DEATH_OFFLINE_CONFIRM_TIME = 4000
local DEATH_SAFE_HP = 5

local state = {
  enabled = false,
  anchors = {},
  visited = {},
  walkedAt = {},
  walkCount = {},
  blocked = {},
  recentTargets = {},
  target = nil,
  targetKey = nil,
  targetMode = "explore",
  targetStartedAt = 0,
  targetBestDistance = nil,
  targetNoProgressAt = 0,
  lastPosKey = nil,
  lastMoveAt = 0,
  startedAt = 0,
  nextThinkAt = 0,
  nextScanAt = 0,
  nextWalkAt = 0,
  deathLowHpSince = 0,
  deathOfflineSince = 0,
  deathHadSafeHp = false,
  status = "Off",
  statusColor = "#c8c8c8"
}

local function currentTime()
  if type(now) == "number" then return now end
  if g_clock and g_clock.millis then
    local ok, value = pcall(function() return g_clock.millis() end)
    if ok and type(value) == "number" then return value end
  end
  return os and os.clock and math.floor(os.clock() * 1000) or 0
end

local function hasPosition(pos)
  return pos and pos.x and pos.y and pos.z
end

local function copyPosition(pos)
  if not hasPosition(pos) then return nil end
  return {x = pos.x, y = pos.y, z = pos.z}
end

local function positionKey(pos)
  if not hasPosition(pos) then return nil end
  return tostring(pos.x) .. "," .. tostring(pos.y) .. "," .. tostring(pos.z)
end

local function samePosition(a, b)
  return hasPosition(a) and hasPosition(b) and a.x == b.x and a.y == b.y and a.z == b.z
end

local function distance2d(a, b)
  if not hasPosition(a) or not hasPosition(b) then return 9999 end
  return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

local function clampRadius(value)
  value = tonumber(value) or 30
  if value < 5 then return 5 end
  if value > 120 then return 120 end
  return math.floor(value)
end

local function getRadius()
  local values = CaveBot.Config and CaveBot.Config.values or {}
  return clampRadius(values.autoExplorerRadius)
end

local function allowFloorChanges()
  local values = CaveBot.Config and CaveBot.Config.values or {}
  return values.autoExplorerFloors ~= false
end

local function getAnchor(pos)
  if not hasPosition(pos) then return nil end
  if not state.anchors[pos.z] then
    state.anchors[pos.z] = copyPosition(pos)
  end
  return state.anchors[pos.z]
end

local function inCurrentRadius(pos)
  if not hasPosition(pos) then return false end
  local anchor = getAnchor(pos)
  return anchor and pos.z == anchor.z and distance2d(pos, anchor) <= getRadius()
end

local function isFloorChangeTile(pos)
  if not hasPosition(pos) or not g_map or not g_map.getMinimapColor then return false end
  local color = g_map.getMinimapColor(pos)
  return color and color >= 210 and color <= 213
end

local function tileHasCreature(tile)
  if not tile then return false end
  local ok, result = pcall(function()
    if tile.hasCreature then return tile:hasCreature() end
    local creatures = tile:getCreatures()
    return creatures and #creatures > 0
  end)
  return ok and result == true
end

local function isWalkableTile(tile)
  if not tile then return false end
  local ok, result = pcall(function() return tile:isWalkable() end)
  return ok and result == true
end

local function getTilePosition(tile)
  if not tile then return nil end
  local ok, pos = pcall(function() return tile:getPosition() end)
  return ok and pos or nil
end

local function canCoverTile(tile)
  if not isWalkableTile(tile) then return false end
  if tile.canShoot then
    local ok, result = pcall(function() return tile:canShoot() end)
    if ok then return result == true end
  end
  return true
end

local function isBlocked(key)
  if not key then return false end
  local untilTime = state.blocked[key]
  if not untilTime then return false end
  if untilTime <= currentTime() then
    state.blocked[key] = nil
    return false
  end
  return true
end

local function markBlocked(pos)
  local key = positionKey(pos)
  if key then state.blocked[key] = currentTime() + BLOCK_TIME end
end

local function isRecentTarget(key)
  if not key then return false end
  local untilTime = state.recentTargets[key]
  if not untilTime then return false end
  if untilTime <= currentTime() then
    state.recentTargets[key] = nil
    return false
  end
  return true
end

local function markRecentTarget(key)
  if key then state.recentTargets[key] = currentTime() + RECENT_TARGET_TIME end
end

local function markVisited(pos)
  local key = positionKey(pos)
  if key then state.visited[key] = true end
end

local function markWalked(pos)
  local key = positionKey(pos)
  if not key then return end
  state.walkedAt[key] = currentTime()
  state.walkCount[key] = (tonumber(state.walkCount[key]) or 0) + 1
  markVisited(pos)
end

local function markAreaCovered(centerPos)
  if not hasPosition(centerPos) or not g_map or not g_map.getTiles then return end

  local okTiles, tiles = pcall(function() return g_map.getTiles(centerPos.z) end)
  if not okTiles or type(tiles) ~= "table" then return end

  for _, tile in pairs(tiles) do
    local tilePos = getTilePosition(tile)
    if tilePos and tilePos.z == centerPos.z and distance2d(centerPos, tilePos) <= COVERAGE_RADIUS then
      if not isFloorChangeTile(tilePos) and inCurrentRadius(tilePos) and canCoverTile(tile) then
        markVisited(tilePos)
      end
    end
  end

  markVisited(centerPos)
end

local function countVisited()
  local total = 0
  for _ in pairs(state.visited) do
    total = total + 1
  end
  return total
end

local function compactStatus(text)
  text = tostring(text or "")
  local count = text:match("(%d+)%s+cubiertos")
  if text:find("Pausa: TargetBot", 1, true) then return "Pausa TB" end
  if text:find("Sin tiles nuevos", 1, true) then return count and ("Sin nuevos " .. count) or "Sin nuevos" end
  if text:find("Sin ruta disponible", 1, true) then return count and ("Sin ruta " .. count) or "Sin ruta" end
  if text:find("Recalculando", 1, true) then return "Recalculando" end
  if text:find("Ruta bloqueada", 1, true) then return "Bloqueado" end
  if text:find("^Piso") then return text:gsub(" | .*", "") end
  if text:find("^Patrulla") then return count and ("Patrulla " .. count) or "Patrulla" end
  if text:find("^On") then return count and ("On " .. count) or "On" end
  if text:find("^Off") then return count and ("Off " .. count) or "Off" end
  return text
end

local function setStatus(text, color)
  state.status = tostring(text or "")
  state.statusColor = color or "#ffffff"
  if AutoExplorer.panel and AutoExplorer.panel.statusRow and AutoExplorer.panel.statusRow.statusLabel then
    AutoExplorer.panel.statusRow.statusLabel:setText(compactStatus(state.status))
    AutoExplorer.panel.statusRow.statusLabel:setColor(state.statusColor)
    AutoExplorer.panel.statusRow.statusLabel:setTooltip(state.status)
  end
end

local function shouldPauseForTargetBot()
  if not TargetBot or not TargetBot.isActive then return false end

  local okActive, active = pcall(function() return TargetBot.isActive() end)
  if not okActive or active ~= true then return false end

  local allowed = false
  if TargetBot.isCaveBotActionAllowed then
    local okAllowed, value = pcall(function() return TargetBot.isCaveBotActionAllowed() end)
    allowed = okAllowed and value == true
  end

  return not allowed
end

local function looksLikeDeathText(text)
  if type(text) ~= "string" then return false end
  text = text:lower()
  return text:find("you are dead", 1, true) or
    text:find("you died", 1, true) or
    text:find("you were killed", 1, true)
end

local function resetDeathState()
  state.deathLowHpSince = 0
  state.deathOfflineSince = 0
  state.deathHadSafeHp = false
end

local function shouldDisableForDeath()
  if not state.enabled then return false end

  local time = currentTime()
  if state.startedAt and state.startedAt > 0 and time - state.startedAt < DEATH_START_GRACE then
    return false
  end

  if g_game and g_game.isOnline then
    local okOnline, online = pcall(function() return g_game.isOnline() end)
    if okOnline and online == false then
      if state.deathOfflineSince == 0 then state.deathOfflineSince = time end
      if time - state.deathOfflineSince >= DEATH_OFFLINE_CONFIRM_TIME then return true end
    else
      state.deathOfflineSince = 0
    end
  end

  if type(hppercent) == "function" then
    local okHp, hp = pcall(hppercent)
    hp = okHp and tonumber(hp) or nil
    if hp then
      if hp > DEATH_SAFE_HP then
        state.deathHadSafeHp = true
        state.deathLowHpSince = 0
      elseif hp <= 0 and state.deathHadSafeHp then
        if state.deathLowHpSince == 0 then state.deathLowHpSince = time end
        if time - state.deathLowHpSince >= DEATH_HP_CONFIRM_TIME then return true end
      else
        state.deathLowHpSince = 0
      end
    end
  end

  return false
end

local function updateButtons()
  if not AutoExplorer.panel then return end
  local button = AutoExplorer.panel.enabled
  button:setOn(state.enabled == true)
  pcall(function()
    button:setImageColor(state.enabled and "#663333" or "#225533")
  end)
end

local function resetRuntime(keepEnabled)
  state.anchors = {}
  state.visited = {}
  state.walkedAt = {}
  state.walkCount = {}
  state.blocked = {}
  state.recentTargets = {}
  state.target = nil
  state.targetKey = nil
  state.targetMode = "explore"
  state.targetStartedAt = 0
  state.targetBestDistance = nil
  state.targetNoProgressAt = 0
  state.lastPosKey = nil
  state.lastMoveAt = currentTime()
  state.startedAt = currentTime()
  state.nextThinkAt = 0
  state.nextScanAt = 0
  state.nextWalkAt = 0
  resetDeathState()

  if player and player.getPosition then
    local pos = player:getPosition()
    if hasPosition(pos) then
      state.anchors[pos.z] = copyPosition(pos)
      markAreaCovered(pos)
      markWalked(pos)
      state.lastPosKey = positionKey(pos)
    end
  end

  if keepEnabled then
    setStatus("On | " .. countVisited() .. " cubiertos", "#8cff9a")
  else
    setStatus("Off", "#c8c8c8")
  end
end

local function getPathParams()
  local ignoreFields = false
  if CaveBot.Config and CaveBot.Config.get then
    local ok, value = pcall(function() return CaveBot.Config.get("ignoreFields") end)
    ignoreFields = ok and value == true
  end

  return {
    ignoreNonPathable = true,
    ignoreCreatures = false,
    ignoreFields = ignoreFields,
    precision = 0,
    allowUnseen = false,
    allowOnlyVisibleTiles = true
  }
end

local function getPathTo(pos, maxDistance)
  if not getPath or not player or not player.getPosition then return nil end
  local ok, path = pcall(function()
    return getPath(player:getPosition(), pos, maxDistance, getPathParams())
  end)
  if ok and path and path[1] then return path end
  return nil
end

local function canUseTile(tile)
  local pos = getTilePosition(tile)
  if not inCurrentRadius(pos) then return false end
  if tileHasCreature(tile) then return false end
  if not isWalkableTile(tile) then return false end
  if isBlocked(positionKey(pos)) then return false end
  if isFloorChangeTile(pos) and not allowFloorChanges() then return false end
  return true
end

local function candidateScore(candidate, mode)
  local score = 0
  mode = mode or "explore"

  if mode == "patrol" then
    local age = candidate.lastWalkedAt > 0 and math.min(90000, currentTime() - candidate.lastWalkedAt) or 90000
    score = score + math.floor(age / 1000) * 5
    score = score - candidate.walkCount * 35
    score = score + math.min(candidate.distance, 10) * 8
    score = score + candidate.anchorDistance * 2
  else
    score = score + candidate.frontier * 30
    score = score + candidate.anchorDistance * 6
    score = score - candidate.distance * 3
  end

  if candidate.floorTile and allowFloorChanges() then
    score = score + 10
  end
  if isRecentTarget(candidate.key) then
    score = score - (mode == "patrol" and 220 or 120)
  end
  if candidate.lastWalkedAt > 0 and currentTime() - candidate.lastWalkedAt < PATROL_RECENT_TIME then
    score = score - (mode == "patrol" and 180 or 30)
  end

  return score
end

local function buildCandidates(mode)
  mode = mode or "explore"
  local playerPos = player and player.getPosition and player:getPosition() or nil
  if not hasPosition(playerPos) then return {} end
  getAnchor(playerPos)

  local candidates = {}
  local okTiles, tiles = pcall(function() return g_map.getTiles(posz()) end)
  if not okTiles or type(tiles) ~= "table" then return candidates end

  for _, tile in pairs(tiles) do
    if canUseTile(tile) then
      local tilePos = getTilePosition(tile)
      if tilePos and not samePosition(tilePos, playerPos) then
        local key = positionKey(tilePos)
        if key and (mode == "patrol" or not state.visited[key]) then
          local candidate = {
            pos = copyPosition(tilePos),
            key = key,
            distance = distance2d(playerPos, tilePos),
            anchorDistance = distance2d(getAnchor(playerPos), tilePos),
            floorTile = isFloorChangeTile(tilePos),
            lastWalkedAt = tonumber(state.walkedAt[key]) or 0,
            walkCount = tonumber(state.walkCount[key]) or 0,
            frontier = 0,
            score = 0
          }
          table.insert(candidates, candidate)
        end
      end
    end
  end

  for _, candidate in ipairs(candidates) do
    local frontier = 0
    for _, other in ipairs(candidates) do
      if distance2d(candidate.pos, other.pos) <= FRONTIER_RADIUS then
        frontier = frontier + 1
      end
    end
    candidate.frontier = frontier
    candidate.score = candidateScore(candidate, mode)
  end

  table.sort(candidates, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    if a.frontier ~= b.frontier then return a.frontier > b.frontier end
    if a.anchorDistance ~= b.anchorDistance then return a.anchorDistance > b.anchorDistance end
    return a.distance < b.distance
  end)

  return candidates
end

local function chooseTargetFromCandidates(candidates, mode)
  local radius = getRadius()
  local maxDistance = math.max(8, radius * 2 + 10)
  local checked = 0
  local best = nil

  for _, candidate in ipairs(candidates) do
    if checked >= MAX_PATH_CHECKS then break end
    checked = checked + 1

    local path = getPathTo(candidate.pos, maxDistance)
    if path then
      local pathScore = candidate.score - (#path * 2)
      if not best or pathScore > best.score then
        best = {pos = candidate.pos, key = candidate.key, path = path, score = pathScore}
      end
    else
      markBlocked(candidate.pos)
    end
  end

  if best then
    return best.pos, best.key, best.path, mode
  end

  return nil, nil, nil, mode
end

local function chooseTarget()
  local target, key, path, mode = chooseTargetFromCandidates(buildCandidates("explore"), "explore")
  if target then return target, key, path, mode end

  target, key, path, mode = chooseTargetFromCandidates(buildCandidates("patrol"), "patrol")
  if target then return target, key, path, mode end

  return nil, nil, nil, "idle"
end

local function setTarget(pos, key, mode)
  state.target = pos
  state.targetKey = key
  state.targetMode = mode or "explore"
  state.targetStartedAt = currentTime()
  state.targetBestDistance = player and player.getPosition and distance2d(player:getPosition(), pos) or nil
  state.targetNoProgressAt = currentTime()
end

local function clearTarget(remember)
  if remember then
    markRecentTarget(state.targetKey)
  end
  state.target = nil
  state.targetKey = nil
  state.targetMode = "explore"
  state.targetStartedAt = 0
  state.targetBestDistance = nil
  state.targetNoProgressAt = 0
end

local function walkToTarget(target)
  if not CaveBot.walkTo then return false end
  local radius = getRadius()
  local ok, result = pcall(function()
    return CaveBot.walkTo(target, math.max(8, radius * 2 + 10), getPathParams())
  end)
  return ok and result == true
end

local function processStuck(playerPos)
  if state.target then
    local distance = distance2d(playerPos, state.target)
    if not state.targetBestDistance or distance < state.targetBestDistance then
      state.targetBestDistance = distance
      state.targetNoProgressAt = currentTime()
    elseif currentTime() - (state.targetNoProgressAt or 0) > NO_PROGRESS_TIME then
      markBlocked(state.target)
      clearTarget(true)
      state.lastMoveAt = currentTime()
      setStatus("Recalculando sin progreso", "#ffd166")
      return true
    end
  end

  local key = positionKey(playerPos)
  if key ~= state.lastPosKey then
    state.lastPosKey = key
    state.lastMoveAt = currentTime()
    return false
  end

  if state.target and currentTime() - (state.lastMoveAt or 0) > STUCK_TIME then
    markBlocked(state.target)
    clearTarget(true)
    state.lastMoveAt = currentTime()
    setStatus("Recalculando ruta", "#ffd166")
    return true
  end

  return false
end

local function explorerTick()
  if not state.enabled then return end
  if currentTime() < (state.nextThinkAt or 0) then return end
  state.nextThinkAt = currentTime() + THINK_INTERVAL

  if shouldDisableForDeath() then
    AutoExplorer.disable()
    setStatus("Off | muerte detectada", "#ff7777")
    return
  end

  if not player or not player.getPosition or not g_map then return end
  local playerPos = player:getPosition()
  if not hasPosition(playerPos) then return end

  getAnchor(playerPos)
  markAreaCovered(playerPos)
  markWalked(playerPos)

  if state.target and state.targetKey and state.visited[state.targetKey] and distance2d(playerPos, state.target) <= COVERAGE_RADIUS then
    clearTarget(true)
    if CaveBot.resetWalking then pcall(CaveBot.resetWalking) end
  end

  if shouldPauseForTargetBot() then
    if CaveBot.resetWalking then pcall(CaveBot.resetWalking) end
    state.nextWalkAt = currentTime() + TARGETBOT_PAUSE_DELAY
    state.nextScanAt = currentTime() + TARGETBOT_PAUSE_DELAY
    setStatus("Pausa: TargetBot | " .. countVisited() .. " cubiertos", "#ffd166")
    return
  end

  if currentTime() >= (state.nextWalkAt or 0) and CaveBot.doWalking and CaveBot.doWalking() then
    state.nextWalkAt = currentTime() + FAST_STEP_DELAY
    local label = state.targetMode == "patrol" and "Patrulla" or "On"
    setStatus(label .. " | " .. countVisited() .. " cubiertos", state.targetMode == "patrol" and "#8fd3ff" or "#8cff9a")
    return
  end

  if currentTime() < (state.nextWalkAt or 0) then
    return
  end

  if processStuck(playerPos) then return end

  if state.target and samePosition(playerPos, state.target) then
    markAreaCovered(state.target)
    clearTarget(true)
  end

  if state.target and isBlocked(state.targetKey) then
    clearTarget(false)
  end

  if not state.target then
    if currentTime() < (state.nextScanAt or 0) then return end
    state.nextScanAt = currentTime() + SCAN_INTERVAL
    local target, key, _, mode = chooseTarget()
    if target then
      setTarget(target, key, mode)
    end
  end

  if not state.target then
    state.nextScanAt = currentTime() + EMPTY_SCAN_INTERVAL
    setStatus("Sin ruta disponible | " .. countVisited() .. " cubiertos", "#ffaa00")
    return
  end

  if not walkToTarget(state.target) then
    markBlocked(state.target)
    clearTarget(true)
    state.nextScanAt = currentTime() + SCAN_INTERVAL
    setStatus("Ruta bloqueada", "#ffd166")
    return
  end

  state.nextWalkAt = currentTime() + FAST_STEP_DELAY
  local label = state.targetMode == "patrol" and "Patrulla" or "On"
  setStatus(label .. " | " .. countVisited() .. " cubiertos", state.targetMode == "patrol" and "#8fd3ff" or "#8cff9a")
end

AutoExplorer.isOn = function()
  return state.enabled == true
end

AutoExplorer.enable = function()
  if state.enabled then return end
  if CaveBot.Recorder and CaveBot.Recorder.isOn and CaveBot.Recorder.isOn() then
    CaveBot.Recorder.disable()
  end
  if CaveBot.setOff then pcall(CaveBot.setOff) end
  if CaveBot.resetWalking then pcall(CaveBot.resetWalking) end

  state.enabled = true
  resetRuntime(true)
  updateButtons()
  warn("Auto Explorer activado. Radio: " .. getRadius() .. " sqm.")
end

AutoExplorer.disable = function()
  if not state.enabled then return end
  state.enabled = false
  if CaveBot.resetWalking then pcall(CaveBot.resetWalking) end
  clearTarget(false)
  setStatus("Off | " .. countVisited() .. " cubiertos", "#c8c8c8")
  updateButtons()
  warn("Auto Explorer detenido.")
end

AutoExplorer.reset = function()
  resetRuntime(state.enabled)
  if state.enabled then
    warn("Auto Explorer reiniciado desde la posicion actual.")
  end
  updateButtons()
end

local function registerExplorerNumber(id, defaultValue, widget, onSet)
  if CaveBot.Config.default_values[id] ~= nil then return end

  CaveBot.Config.value_setters[id] = function(value)
    value = clampRadius(value)
    CaveBot.Config.values[id] = value
    widget:setText(value, true)
    if onSet then onSet(value) end
  end

  CaveBot.Config.values[id] = defaultValue
  CaveBot.Config.default_values[id] = defaultValue
  CaveBot.Config.value_setters[id](defaultValue)

  widget.onTextChange = function(_, newValue)
    local value = tonumber(newValue)
    if not value then return end
    CaveBot.Config.values[id] = clampRadius(value)
    if onSet then onSet(CaveBot.Config.values[id]) end
    CaveBot.save()
  end
end

local function registerExplorerSwitch(id, defaultValue, widget, onSet)
  if CaveBot.Config.default_values[id] ~= nil then return end

  CaveBot.Config.value_setters[id] = function(value)
    value = value == true
    CaveBot.Config.values[id] = value
    widget:setOn(value, true)
    if onSet then onSet(value) end
  end

  CaveBot.Config.values[id] = defaultValue
  CaveBot.Config.default_values[id] = defaultValue
  CaveBot.Config.value_setters[id](defaultValue)

  widget.onClick = function(widget)
    widget:setOn(not widget:isOn())
    CaveBot.Config.values[id] = widget:isOn()
    if onSet then onSet(CaveBot.Config.values[id]) end
    CaveBot.save()
  end
end

AutoExplorer.setupMainPanel = function(panel)
  if not panel then return end
  AutoExplorer.panel = panel

  registerExplorerNumber("autoExplorerRadius", 30, panel.statusRow.radiusEdit, function()
    if state.enabled then AutoExplorer.reset() end
  end)
  registerExplorerSwitch("autoExplorerFloors", true, panel.optionsRow.floorSwitch, function()
    if state.enabled then state.target = nil end
  end)

  panel.enabled.onClick = function(widget)
    if state.enabled then
      AutoExplorer.disable()
    else
      AutoExplorer.enable()
    end
  end

  panel.optionsRow.resetButton.onClick = function()
    AutoExplorer.reset()
  end

  panel.enabled:setTooltip("Activa el explorador automatico. Apaga el CaveBot normal para evitar conflictos.")
  panel.optionsRow.resetButton:setTooltip("Limpia la memoria de tiles cubiertos y usa tu posicion actual como centro.")
  panel.statusRow.radiusEdit:setTooltip("Radio maximo de exploracion por piso. Minimo 5, maximo 120 sqm.")
  panel.optionsRow.floorSwitch:setTooltip("Permite que el explorador suba o baje escaleras/rampas dentro del radio.")

  updateButtons()
  setStatus(state.status, state.statusColor)
end

onPlayerPositionChange(function(newPos, oldPos)
  if not state.enabled then return end
  if hasPosition(oldPos) then markAreaCovered(oldPos) end
  if not hasPosition(newPos) then return end

  if hasPosition(oldPos) and newPos.z ~= oldPos.z then
    getAnchor(newPos)
    clearTarget(false)
    if CaveBot.resetWalking then pcall(CaveBot.resetWalking) end
    setStatus("Piso " .. tostring(newPos.z) .. " | " .. countVisited() .. " cubiertos", "#8cff9a")
  end

  markAreaCovered(newPos)
  markWalked(newPos)
end)

onTextMessage(function(mode, text)
  if not state.enabled then return end
  if not looksLikeDeathText(text) then return end
  AutoExplorer.disable()
  setStatus("Off | muerte detectada", "#ff7777")
end)

macro(THINK_INTERVAL, explorerTick)
