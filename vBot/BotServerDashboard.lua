-- UI and local alerts for BotServer. Telemetry remains in the presence packet.
local config = storage.BOTserver
if type(config) ~= 'table' then return end
local generation = BotServer._rodMasterMainGeneration
local settings = config.dashboard
if type(settings) ~= 'table' then settings = {}; config.dashboard = settings end
if type(settings.favorites) ~= 'table' then settings.favorites = {} end
if type(settings.alerts) ~= 'table' then settings.alerts = {} end
local alerts = settings.alerts
alerts.enabled = alerts.enabled == true
alerts.sound = alerts.sound == true
alerts.hp = math.max(0, math.min(100, tonumber(alerts.hp) or 35))
alerts.mana = math.max(0, math.min(100, tonumber(alerts.mana) or 20))
settings.preview = settings.preview == true
settings.favoritesOnly = settings.favoritesOnly == true
settings.sameFloor = settings.sameFloor == true
local sortLabels = {name = 'Nombre', hp = 'Menor HP', mana = 'Menor mana'}
local sortValues = {['Nombre'] = 'name', ['Menor HP'] = 'hp', ['Menor mana'] = 'mana'}
if not sortLabels[settings.sort] then settings.sort = 'name' end

local FRESH_MS, POSITION_MS = 15000, 15000
local LEADERS = {['rod master'] = true, sabuezo = true, ['aeron knight'] = true}
local rows, cache, alarmState = {}, {}, {}
local selected, query, currentPage = nil, '', 'companions'
local lastAlert, lastAlertTime, lastSoundAt = nil, nil, -15000
local orderedNames, previewPosition = {}, nil
local previewExiva, activeExiva = nil, nil
local previewMarkers, previewDots = {}, {}
local previewOrder = nil
local MAX_PREVIEW_MARKERS, MAX_GUIDE_DOTS = 64, 18
local markerRoot = (configDir or '/bot/pruebas') .. '/vBot/map_markers/'
local alertsExpanded = false
local BASE_HEIGHT, MAP_EXPANSION = 460, 248
local previewZoom = 1
local assetRoot = (configDir or '/bot/pruebas') .. '/vBot/botserver_assets/'
local dashboard = {}

local function active()
  return generation == BotServer._rodMasterMainGeneration
end

local function clock()
  return tonumber(now) or (g_clock and g_clock.millis and g_clock.millis()) or 0
end

local function exivaClock()
  return (g_clock and g_clock.millis and g_clock.millis()) or clock()
end

local function key(name)
  return tostring(name or ''):lower():gsub('^%s+', ''):gsub('%s+$', '')
end

local function selfName()
  return name()
end

local function connected()
  if config.enabled ~= true or BotServer._websocket == nil then return false end
  if GameBotServerTransport and type(GameBotServerTransport.getStatus) == 'function' then
    local _, level = GameBotServerTransport.getStatus()
    return level == 'connected'
  end
  return true
end

local function position(value)
  if type(value) ~= 'table' then return nil end
  local x, y, z = tonumber(value.x), tonumber(value.y), tonumber(value.z)
  if not x or not y or not z or x ~= x or y ~= y or z ~= z or
    x < 0 or x > 65535 or y < 0 or y > 65535 or z < 0 or z > 15 then return nil end
  return {x = math.floor(x), y = math.floor(y), z = math.floor(z)}
end

local function positionText(pos)
  return pos and (pos.x .. ', ' .. pos.y .. ', ' .. pos.z) or '-'
end

local function age(at)
  if type(at) ~= 'number' then return nil end
  return math.max(0, clock() - at)
end

local function fresh(at, limit)
  local elapsed = age(at)
  return connected() and elapsed ~= nil and elapsed <= (limit or FRESH_MS)
end

local function recentValue(info, field)
  local value = tonumber(info and info[field])
  if value and value == value and value >= 0 and value <= 100 and
    fresh(info[field .. 'SeenAt']) then return value end
  return nil
end

local function recentPosition(info)
  if info and fresh(info.positionSeenAt or info.lastSeen, POSITION_MS) then
    return position(info.pos)
  end
end

local function memberPosition(all, who)
  local info = all[who]
  if info then return recentPosition(info), who end
  for memberName, entry in pairs(all) do
    if key(memberName) == key(who) then return recentPosition(entry), memberName end
  end
  return nil, who
end

local function snapshot()
  if type(BotServer.getMemberSnapshot) ~= 'function' then return {} end
  -- Visible health is needed by the open roster or enabled alerts, not map tracking.
  return BotServer.getMemberSnapshot((botServerWindow and botServerWindow:isVisible()) or alerts.enabled)
end

local function set(widget, method, value)
  if not widget then return end
  local values = cache[widget]
  if not values then values = {}; cache[widget] = values end
  if values[method] ~= value then
    widget[method](widget, value)
    values[method] = value
  end
end

local function visible()
  return botServerWindow and botServerWindow:isVisible()
end

local function shortName(who, length)
  who = tostring(who or '')
  length = length or 28
  return #who > length and who:sub(1, length - 3) .. '...' or who
end

local function clearCache(widget)
  if not widget then return end
  for _, child in ipairs(widget:getChildren()) do clearCache(child) end
  cache[widget] = nil
end

local function model(all)
  local result = {}
  local own = all[selfName()]
  local ownPos = own and position(own.pos)
  for who, info in pairs(all) do
    local favorite = settings.favorites[key(who)] == true
    local pos = recentPosition(info)
    if (query == '' or key(who):find(query, 1, true)) and
      (not settings.favoritesOnly or favorite) and
      (not settings.sameFloor or (ownPos and pos and ownPos.z == pos.z)) then
      result[#result + 1] = {name = who, info = info, favorite = favorite,
        hp = recentValue(info, 'hp'), mana = recentValue(info, 'mana'),
        pos = pos, fresh = fresh(info.lastSeen)}
    end
  end
  table.sort(result, function(a, b)
    -- Missing/stale values always sort after real values; 0% remains a real reading.
    if settings.sort ~= 'name' then
      local av, bv = a[settings.sort], b[settings.sort]
      if (av ~= nil) ~= (bv ~= nil) then return av ~= nil end
      if av ~= bv then return (av or 101) < (bv or 101) end
    else
      if a.fresh ~= b.fresh then return a.fresh end
      if a.favorite ~= b.favorite then return a.favorite end
    end
    return key(a.name) < key(b.name)
  end)
  return result
end

local function openNaviMap()
  if not active() or not botServerWindow or not connected() then return false end
  settings.preview = true
  previewPosition = nil
  botServerWindow:show()
  dashboard.showPage('companions')
  return true
end

function dashboard.locateMember(who)
  if not active() then return false end
  local info = snapshot()[who]
  local pos = recentPosition(info)
  if not pos then return false end
  selected, previewExiva = who, nil
  return openNaviMap()
end

local function updateWindowLayout()
  local window = botServerWindow
  local extraAlerts = currentPage == 'companions' and alertsExpanded and 66 or 0
  local extraMap = currentPage == 'companions' and settings.preview and MAP_EXPANSION or 0
  -- Grow downwards without making the roster smaller. Keep the window on screen.
  local ok, bounds = pcall(function() return g_ui.getRootWidget():getRect() end)
  if not ok or type(bounds) ~= 'table' then bounds = nil end
  local height = BASE_HEIGHT + extraAlerts + extraMap
  if bounds and tonumber(bounds.height) then
    height = math.min(height, math.max(BASE_HEIGHT, bounds.height - 16))
  end
  local positionOk, at = pcall(function() return window:getPosition() end)
  set(window, 'setHeight', height)
  local mapHeight = extraMap > 0 and math.max(88, height - BASE_HEIGHT - extraAlerts) or 0
  set(window.MembersPage.Selected, 'setHeight', 60 + mapHeight)
  if bounds and positionOk and type(at) == 'table' and tonumber(at.y) and tonumber(at.x) then
    local top = (tonumber(bounds.y) or 0) + 8
    local y = math.max(top, math.min(at.y, top + bounds.height - height - 16))
    if y ~= at.y then window:setPosition({x = at.x, y = y}) end
  end
end

local function hidePreviewMarkers()
  previewOrder = nil
  for _, marker in pairs(previewMarkers) do
    set(marker.widget, 'setVisible', false)
    set(marker.widget, 'setTooltip', '')
  end
  for _, dot in ipairs(previewDots) do set(dot.widget, 'setVisible', false) end
end

local function previewTarget(all, session, estimate)
  if not session then return end
  local pos = memberPosition(all, session.target)
  local kind = pos and 'exact' or estimate and estimate.locationType or 'approximate'
  if not pos and estimate and not estimate.unbounded then pos = position(estimate.position) end
  if not pos then return end
  return {name = session.target, pos = pos, kind = kind,
    state = kind == 'exact' and 'Posicion exacta' or kind == 'lastSeen' and 'Ultima posicion vista' or 'Posicion aproximada',
    color = kind == 'exact' and '#ff8080' or kind == 'lastSeen' and '#ffbb66' or '#ffffff'}
end

local function tileDistance(left, right)
  return math.max(math.abs(left.x - right.x), math.abs(left.y - right.y))
end

local function renderPreviewMarkers(panel, all, reference, referenceName, session, estimate, camera)
  local map = panel.Preview
  local ok, width, height, scale = pcall(function()
    local size = map:getSize()
    return tonumber(size.width), tonumber(size.height), tonumber(map:getScale())
  end)
  if not ok or not width or not height or not scale or width <= 0 or height <= 0 or scale <= 0 then
    hidePreviewMarkers(); return
  end
  local mapKey = positionText(camera) .. '|' .. scale .. '|' .. width .. '|' .. height
  local target = previewTarget(all, session, estimate)
  local order = key(referenceName) .. '|' .. (target and key(target.name) or '')
  local raiseMarkers = previewOrder ~= order
  local points, names, available = {}, {}, {}
  for who in pairs(all) do names[#names + 1] = who; available['member:' .. key(who)] = true end
  table.sort(names, function(a, b) return key(a) < key(b) end)
  for _, who in ipairs(names) do
    local pos = recentPosition(all[who])
    if pos and key(who) ~= key(referenceName) and (not target or key(who) ~= key(target.name)) and
      #points < MAX_PREVIEW_MARKERS - 2 then
      points[#points + 1] = {id = 'member:' .. key(who), name = who, pos = pos,
        image = markerRoot .. 'member-diamond.png', size = 13, color = '#ffffff'}
    end
  end
  if reference then
    points[#points + 1] = {id = 'member:' .. key(referenceName), name = referenceName, pos = reference,
      image = assetRoot .. 'status-green.png', size = 14, color = '#ffffff', reference = true}
  end
  if target then
    points[#points + 1] = {id = 'exiva', name = target.name, pos = target.pos,
      image = markerRoot .. 'exiva-target.png', size = 19, color = target.color, target = true}
  end

  -- Share the names at a tile, so stacked markers still identify every player.
  local atTile = {}
  for _, point in ipairs(points) do
    local tile = positionText(point.pos)
    local bucket = atTile[tile] or {}; atTile[tile] = bucket
    local duplicate = false
    for _, who in ipairs(bucket) do if key(who) == key(point.name) then duplicate = true; break end end
    if not duplicate then bucket[#bucket + 1] = point.name end
  end
  local wanted = {}
  for _, point in ipairs(points) do
    local x = width / 2 + (point.pos.x - camera.x) * scale
    local y = height / 2 + (point.pos.y - camera.y) * scale
    local half = point.size / 2
    if point.pos.z == camera.z and x >= half and x <= width - half and y >= half and y <= height - half then
      local marker = previewMarkers[point.id]
      if not marker then
        local widget = UI.createWidget('BotServerPreviewMarker', map)
        widget:setId('navi_' .. point.id:gsub('[^%w]', '_'))
        widget.onMousePress = function() return true end
        widget.onMouseRelease = function() return true end
        marker = {widget = widget}; previewMarkers[point.id] = marker
        raiseMarkers = true
      end
      wanted[point.id] = true
      if marker.size ~= point.size then
        marker.widget:setSize({width = point.size, height = point.size}); marker.size = point.size
      end
      set(marker.widget, 'setImageSource', point.image)
      set(marker.widget, 'setImageColor', point.color)
      local sameTile = {point.name}
      for _, who in ipairs(atTile[positionText(point.pos)]) do
        if key(who) ~= key(point.name) then sameTile[#sameTile + 1] = who end
      end
      local tooltip = table.concat(sameTile, '\n')
      if point.reference then tooltip = tooltip .. '\nReferencia de la vista'
      else
        if point.target then tooltip = tooltip .. '\n' .. target.state end
        local prefix = point.target and target.kind ~= 'exact' and 'Aprox. ' or ''
        if reference then
          tooltip = tooltip .. '\n' .. prefix .. tileDistance(reference, point.pos) .. ' casillas de ' .. referenceName
        end
      end
      if point.target then tooltip = tooltip .. '\n' .. positionText(point.pos) end
      set(marker.widget, 'setTooltip', tooltip)
      local where = mapKey .. '|' .. positionText(point.pos)
      if marker.where ~= where then map:centerInPosition(marker.widget, point.pos); marker.where = where end
      set(marker.widget, 'setVisible', true)
    end
  end
  for id, marker in pairs(previewMarkers) do
    if not wanted[id] then
      set(marker.widget, 'setVisible', false); set(marker.widget, 'setTooltip', '')
      if id ~= 'exiva' and not available[id] then
        clearCache(marker.widget); marker.widget:destroy(); previewMarkers[id] = nil
      end
    end
  end

  -- A short dotted bearing shows the visible part of the direction, never a path.
  local used = 0
  if target and reference and target.pos.z == reference.z and camera.z == reference.z then
    -- Either endpoint can be the camera center. Clip toward the other endpoint
    -- so a target-centered map keeps only the visible part of the same bearing.
    local origin, destination = reference, target.pos
    if positionText(camera) == positionText(target.pos) then origin, destination = target.pos, reference end
    local dx, dy = (destination.x - origin.x) * scale, (destination.y - origin.y) * scale
    local length = math.sqrt(dx * dx + dy * dy)
    if length > 0 then
      local part = math.min(1, dx ~= 0 and (width / 2 - 12) / math.abs(dx) or 1,
        dy ~= 0 and (height / 2 - 12) / math.abs(dy) or 1)
      local spacing = math.max(12, scale * 2)
      used = math.min(MAX_GUIDE_DOTS, math.floor(length * math.max(0, part) / spacing))
      for i = 1, used do
        local dot = previewDots[i]
        if not dot then
          local widget = UI.createWidget('BotServerPreviewGuideDot', map)
          widget:setId('navi_guide_' .. i)
          widget:setImageSource(markerRoot .. 'exiva-guide-dot.png')
          map:moveChildToIndex(widget, 1)
          dot = {widget = widget}; previewDots[i] = dot
        end
        local t = i * spacing / length
        local pos = {x = math.floor(origin.x + (destination.x - origin.x) * t + 0.5),
          y = math.floor(origin.y + (destination.y - origin.y) * t + 0.5), z = origin.z}
        local where = mapKey .. '|' .. positionText(pos)
        if dot.where ~= where then map:centerInPosition(dot.widget, pos); dot.where = where end
        set(dot.widget, 'setVisible', true)
      end
    end
  end
  for i = used + 1, #previewDots do set(previewDots[i].widget, 'setVisible', false) end
  if raiseMarkers then
    local referenceMarker = previewMarkers['member:' .. key(referenceName)]
    if referenceMarker then referenceMarker.widget:raise() end
    if wanted.exiva then previewMarkers.exiva.widget:raise() end
    previewOrder = order
  end

  local message, tooltip = '', 'Vista de ' .. referenceName
  if session then
    if target then
      local distance = not reference and ('piso ' .. target.pos.z) or
        target.pos.z ~= reference.z and ('piso ' .. target.pos.z) or
        ((target.kind ~= 'exact' and '~' or '') .. tileDistance(reference, target.pos) .. ' casillas')
      message = shortName(target.name, 12) .. ': ' .. distance
      tooltip = tooltip .. '\n' .. target.name .. ': ' .. target.state .. '\n' .. distance
    else
      message = shortName(session.target, 12) .. ': ' .. (estimate and estimate.unbounded and 'rumbo aprox.' or 'sin posicion')
      tooltip = tooltip .. '\n' .. message
    end
    tooltip = tooltip .. '\nIniciador: ' .. session.coordinator .. '\nLa guia muestra direccion, no un camino transitable.'
  elseif reference then
    local nearest, distance
    for _, who in ipairs(names) do
      local pos = recentPosition(all[who])
      if pos and pos.z == reference.z and key(who) ~= key(referenceName) then
        local d = tileDistance(reference, pos)
        if not distance or d < distance then nearest, distance = who, d end
      end
    end
    if nearest then message = shortName(nearest, 12) .. ': ' .. distance .. ' casillas'; tooltip = tooltip .. '\n' .. nearest .. ': ' .. distance .. ' casillas' end
  end
  set(panel.MapInfo, 'setText', message)
  set(panel.MapInfo, 'setTooltip', tooltip)
  set(panel.MapInfo, 'setColor', session and '#ffe38a' or '#a6b3bf')
end

local function updatePreview(panel, pos, all, referenceName, session, estimate, reference)
  local show = settings.preview and pos ~= nil
  set(panel.Preview, 'setVisible', show)
  set(panel.PreviewToggle, 'setOn', settings.preview)
  set(panel.PreviewToggle, 'setText', settings.preview and 'Ocultar mapa' or 'Mini mapa')
  set(panel.PreviewHint, 'setVisible', settings.preview and not show)
  set(panel.ZoomIn, 'setVisible', settings.preview)
  set(panel.ZoomOut, 'setVisible', settings.preview)
  set(panel.ZoomIn, 'setEnabled', show and previewZoom < 4)
  set(panel.ZoomOut, 'setEnabled', show and previewZoom > -2)
  set(panel.MapInfo, 'setVisible', show)
  if not show then previewPosition = nil; hidePreviewMarkers(); return end
  set(panel.Preview, 'setZoom', previewZoom)
  local id = positionText(pos)
  if previewPosition ~= id then
    -- This map belongs to this bot window and is never reparented or shared.
    -- Its camera and all its children belong exclusively to Navi.
    panel.Preview:setCameraPosition(pos)
    previewPosition = id
  end
  renderPreviewMarkers(panel, all, reference, referenceName, session, estimate, pos)
end

local function previewSession()
  if previewExiva then return activeExiva(nil, previewExiva.coordinator, previewExiva.target) end
  local session, estimate = activeExiva(nil, selected or selfName())
  if not session then return activeExiva() end
  return session, estimate
end

function dashboard.locateExivaTarget()
  if not active() then return false end
  local session, estimate = previewSession()
  if not previewTarget(snapshot(), session, estimate) then return false end
  selected, previewExiva = nil, {target = session.target, coordinator = session.coordinator, centerTarget = true}
  return openNaviMap()
end

local function renderSelected(all)
  local panel = botServerWindow.MembersPage.Selected
  local referenceName = previewExiva and previewExiva.coordinator or selected or selfName()
  local session, estimate = previewSession()
  local reference = memberPosition(all, referenceName)
  local target = previewTarget(all, session, estimate)
  local centerTarget = previewExiva and previewExiva.centerTarget and target ~= nil
  local pos = centerTarget and target.pos or reference
  local title = selected and shortName(selected, 32) or 'Selecciona un companero'
  local tooltip = selected or 'Selecciona una fila de la lista'
  if previewExiva then
    -- Follow repeat searches of this target by this initiator in the chosen view.
    title, tooltip = 'Vista: ' .. shortName(referenceName, 24), referenceName .. '\nExiva: ' .. previewExiva.target
    if centerTarget then
      title = 'Exiva: ' .. shortName(target.name, 24)
      tooltip = target.name .. '\n' .. target.state .. '\nIniciador: ' .. referenceName
    end
  end
  set(panel.Name, 'setText', title)
  set(panel.Name, 'setTooltip', tooltip)
  local displayPos
  if selected or previewExiva then displayPos = pos end
  set(panel.Position, 'setText', 'Posicion: ' .. positionText(displayPos))
  set(panel.Status, 'setText', pos and 'Posicion reciente compartida' or 'Sin posicion reciente')
  set(panel.Locate, 'setEnabled', (selected ~= nil or previewExiva ~= nil) and reference ~= nil)
  set(panel.TargetLocate, 'setEnabled', target ~= nil)
  set(panel.TargetLocate, 'setOn', centerTarget and true or false)
  set(panel.TargetLocate, 'setTooltip', target and
    ('Ver ' .. target.name .. ' en Navi: ' .. target.state .. '\n' .. positionText(target.pos)) or
    session and (estimate and estimate.unbounded and 'Solo hay rumbo; aun no hay un punto estimado' or
      'Esperando la posicion del exiveado') or 'Sin exiva activo')
  set(panel.PreviewHint, 'setText', 'Sin posicion reciente de ' .. referenceName)
  updatePreview(panel, pos, all, referenceName, session, estimate, reference)
end

local function renderMembers(all)
  local page = botServerWindow.MembersPage
  local items, allowed = model(all), {}
  for index, item in ipairs(items) do
    local who = item.name
    allowed[who] = true
    local row = rows[who]
    if not row then
      row = UI.createWidget('BotServerMemberRow', page.List)
      rows[who] = row
      row.onClick = function() selected, previewExiva = who, nil; dashboard.refresh(true) end
      row.Favorite.onClick = function()
        settings.favorites[key(who)] = not settings.favorites[key(who)] or nil
        dashboard.refresh(true)
      end
      row.Locate.onClick = function() dashboard.locateMember(who) end
    end
    set(row, 'setVisible', true)
    if orderedNames[index] ~= who then page.List:moveChildToIndex(row, index) end
    local leader = LEADERS[key(who)] == true
    local label = shortName(who, 20)
    set(row.Name, 'setText', label)
    set(row.Name, 'setColor', item.fresh and '#e0eaea' or '#8d9797')
    set(row.Name, 'setTooltip', who .. (leader and '\nLider autorizado para parar exivas' or ''))
    set(row.Leader, 'setVisible', leader)
    -- Measure only when the name changes, keeping the crown clear of the text.
    local labelCache = cache[row.Name]
    if leader and labelCache.crownFor ~= label then
      local textSize = row.Name:getTextSize()
      set(row.Leader, 'setMarginLeft', math.min(165, 32 + textSize.width))
      labelCache.crownFor = label
    end
    set(row.Favorite, 'setImageSource', assetRoot .. (item.favorite and 'star-filled.png' or 'star-outline.png'))
    set(row.Dot, 'setImageSource', assetRoot .. (item.fresh and 'status-green.png' or 'status-gray.png'))
    set(row.Freshness, 'setText', not item.fresh and 'Sin senal' or
      item.pos and ('Piso ' .. item.pos.z) or 'Sin posicion')
    for _, field in ipairs({'hp', 'mana'}) do
      local bar = field == 'hp' and row.Hp or row.Mana
      local value = item[field]
      set(bar.Frame.Fill, 'setWidth', math.max(1, math.floor(54 * (value or 0) / 100)))
      set(bar.Frame.Fill, 'setVisible', value ~= nil and value > 0)
      set(bar.Frame.Fill, 'setImageSource', assetRoot .. (field == 'hp' and 'hp-fill.png' or 'mana-fill.png'))
      set(bar.Value, 'setText', value ~= nil and (value .. '%') or '--')
      set(bar.Value, 'setColor', value == nil and '#8795a0' or '#e3edf6')
      local tooltip
      if value == nil then
        tooltip = field == 'hp' and
          'Sin HP compartido. Se puede leer si lo ves en pantalla; para verlo a distancia debe actualizar el bot.' or
          'Sin mana reciente compartido'
      else
        tooltip = (field == 'hp' and 'HP: ' or 'Mana: ') .. value .. '%'
        if field == 'hp' then tooltip = tooltip ..
          (item.info.hpSource == 'visible' and '\nLeido de tu pantalla' or '\nCompartido por el companero') end
      end
      set(bar, 'setTooltip', tooltip)
    end
    set(row.Locate, 'setEnabled', item.pos ~= nil)
    set(row, 'setOn', who == selected)
  end
  orderedNames = {}
  for _, item in ipairs(items) do orderedNames[#orderedNames + 1] = item.name end
  for who, row in pairs(rows) do
    if not all[who] then
      clearCache(row); row:destroy(); rows[who] = nil
    elseif not allowed[who] then set(row, 'setVisible', false) end
  end
  set(page.Empty, 'setVisible', #items == 0)
  if selected and not all[selected] then selected = nil end
  renderSelected(all)
end

activeExiva = function(wantedId, coordinator, target)
  local tracker = vBot.ExivaTracker
  if not connected() or not tracker or not BotServer.isExivaTrackerEnabled() or tracker.isPaused() then return end
  local latest, current = nil, exivaClock()
  for _, session in pairs(tracker.getSessions()) do
    if session.visualUntil and session.visualUntil > current and not session.castCancelled and
      (not wantedId or session.id == wantedId) and (not coordinator or key(session.coordinator) == key(coordinator)) and
      (not target or key(session.target) == key(target)) and
      (not latest or session.createdAt > latest.createdAt or
        (session.createdAt == latest.createdAt and session.id > latest.id)) then latest = session end
  end
  if not latest then return end
  local estimate = tracker.getEstimates()[key(latest.target)]
  if estimate and (estimate.expiresAt <= current or estimate.sessionId ~= latest.id) then estimate = nil end
  return latest, estimate
end

local function renderExiva(all)
  local panel, tracker = botServerWindow.ExivaActivity, vBot.ExivaTracker
  local control = tracker and tracker.getControlStatus and tracker.getControlStatus() or {}
  set(panel.Leader, 'setVisible', control.canStop == true)
  local session, estimate = activeExiva()
  set(panel.CurrentTarget, 'setText', 'Objetivo: ' .. (session and session.target or '-'))
  set(panel.CurrentInitiator, 'setText', 'Iniciador: ' .. (session and session.coordinator or '-'))
  set(panel.CurrentInitiator, 'setPhantom', false)
  local diagnostic = tracker and type(tracker.getDiagnostics) == 'function' and
    tracker.getDiagnostics(session and session.id) or nil
  local details = ''
  if diagnostic then
    details = 'Origen: ' .. (diagnostic.source or '-') ..
      '\nSeleccionados: ' .. (#diagnostic.selected > 0 and table.concat(diagnostic.selected, ', ') or '-') ..
      '\nRespondieron: ' .. (#diagnostic.answered > 0 and table.concat(diagnostic.answered, ', ') or '-') ..
      '\nTu personaje: ' .. diagnostic.reason ..
      '\nTus iconos: Target ' .. (diagnostic.exivaTarget and 'ON' or 'OFF') ..
      ' | Last ' .. (diagnostic.exivaLast and 'ON' or 'OFF')
  end
  set(panel.CurrentInitiator, 'setTooltip', details)
  local text = 'Posicion: sin busqueda activa'
  if session then
    if estimate then
      local state = estimate.locationType == 'exact' and 'Exacta' or
        estimate.locationType == 'lastSeen' and 'Ultima vista' or 'Aproximada'
      text = 'Posicion: ' .. state .. ' | ' .. positionText(position(estimate.position))
      if estimate.seenBy then text = text .. ' | visto por ' .. estimate.seenBy end
      if estimate.unbounded then text = 'Posicion: rumbo aproximado, sin distancia definida' end
    else text = 'Posicion: esperando respuesta' end
  end
  set(panel.CurrentPosition, 'setText', text)
  set(panel.CurrentPosition, 'setTooltip', text)
  local origin = session and memberPosition(all, session.coordinator)
  set(panel.Locate, 'setEnabled', origin ~= nil)
  set(panel.Locate, 'setTooltip', origin and ('Ver en Navi desde ' .. session.coordinator) or 'Sin posicion reciente del iniciador')
  local history = tracker and tracker.getActivity() or {}
  for index = 5, 8 do
    local row, entry = panel['Row' .. index], history[index]
    set(row.Time, 'setText', entry and entry.time or '-')
    set(row.Initiator, 'setText', entry and shortName(entry.initiator, 38) or '-')
    set(row.Target, 'setText', entry and shortName(entry.target, 38) or '-')
  end
end

local function updateTransport()
  local panel, mode = botServerWindow.Transport, config.transportMode
  set(panel.GuildChannelId, 'setVisible', mode == 'guild')
  set(panel.guildChannelLabel, 'setVisible', mode == 'guild')
  set(panel.GameChannelId, 'setVisible', mode == 'party')
  set(panel.gameChannelLabel, 'setVisible', mode == 'party')
  set(panel.ExtendedOpcode, 'setVisible', mode == 'opcode')
  set(panel.opcodeLabel, 'setVisible', mode == 'opcode')
  local hints = {websocket = 'WebSocket | Render | El canal identifica a tu grupo.',
    guild = 'Guild: canal de hermandad. Actualizaciones cada 3 s.',
    party = 'Party: canal del grupo. Actualizaciones cada 3 s.',
    opcode = 'Requiere relay compatible en el servidor.'}
  set(panel.Hint, 'setText', hints[mode] or '')
end

function dashboard.showPage(page)
  if not active() or not botServerWindow then return end
  currentPage = page
  local window = botServerWindow
  set(window.MembersPage, 'setVisible', page == 'companions')
  set(window.ExivaActivity, 'setVisible', page == 'exivas')
  for _, widget in ipairs({window.Data, window.Transport, window.Features, window.ConnectionNote}) do
    set(widget, 'setVisible', page == 'connection')
  end
  set(window.Tabs.Companions, 'setOn', page == 'companions')
  set(window.Tabs.Exivas, 'setOn', page == 'exivas')
  set(window.Tabs.Connection, 'setOn', page == 'connection')
  dashboard.refresh(true)
end

function dashboard.refresh(force)
  if not active() then return end
  local all = snapshot()
  local count = 0
  if connected() then for _ in pairs(all) do count = count + 1 end end
  local opener = vBot.BotServerOpener
  local status, color = 'Desconectado', '#e3242b'
  if connected() then status, color = 'Conectado', '#03ac13'
  elseif config.enabled then status, color = 'Conectando', '#fff380' end
  if opener then
    set(opener.memberBadge, 'setText', tostring(count))
    set(opener.connectionDot, 'setImageSource', assetRoot .. (connected() and 'status-green.png' or
      config.enabled and 'status-yellow.png' or 'status-red.png'))
    local names = {}
    if connected() then for who in pairs(all) do names[#names + 1] = who end end
    table.sort(names, function(a, b) return key(a) < key(b) end)
    local tooltip = status .. ' | ' .. count .. ' jugadores'
    if #names > 0 then tooltip = tooltip .. '\n' .. table.concat(names, '\n') end
    set(opener, 'setTooltip', tooltip)
  end
  if not visible() then return end
  local window = botServerWindow
  updateWindowLayout()
  set(window.Header.Status, 'setText', status)
  set(window.Header.Status, 'setColor', color)
  set(window.Header.Dot, 'setImageSource', assetRoot .. (connected() and 'status-green.png' or
    config.enabled and 'status-yellow.png' or 'status-red.png'))
  set(window.enabled.Dot, 'setImageSource', assetRoot .. (config.enabled and 'status-green.png' or 'status-gray.png'))
  set(window.enabled.Caption, 'setText', config.enabled and 'Navi: ON' or 'Navi: OFF')
  set(window.Header.Members, 'setText', count .. ' jugadores')
  set(window.Header.Channel, 'setText', tostring(storage.BotServerChannel or ''))
  set(window.Tabs.Companions, 'setText', 'Companeros (' .. count .. ')')
  if currentPage == 'companions' then renderMembers(all)
  elseif currentPage == 'exivas' then renderExiva(all)
  else updateTransport() end
  local alertPanel = window.MembersPage.Alerts
  set(alertPanel.Enabled, 'setOn', alerts.enabled)
  set(alertPanel.Enabled.Caption, 'setText', alerts.enabled and 'ON' or 'OFF')
  set(alertPanel.Enabled.Caption, 'setMarginLeft', alerts.enabled and 4 or 28)
  set(alertPanel, 'setHeight', alertsExpanded and 100 or 34)
  set(alertPanel.Fold.Arrow, 'setImageSource', assetRoot .. (alertsExpanded and 'chevron-down.png' or 'chevron-right.png'))
  for _, id in ipairs({'HpLabel', 'Hp', 'ManaLabel', 'Mana', 'Sound', 'Hint', 'Message'}) do
    set(alertPanel[id], 'setVisible', alertsExpanded)
  end
  local text = not alerts.enabled and 'Alertas desactivadas' or
    lastAlert and (lastAlert .. ' | hace ' .. math.floor((clock() - lastAlertTime) / 1000) .. ' s') or 'Sin alertas recientes'
  set(alertPanel.Message, 'setText', text)
  set(alertPanel.Message, 'setTooltip', text)
  set(alertPanel.Message, 'setColor', alerts.enabled and lastAlert and '#ffd166' or '#a0adae')
end

function dashboard.checkAlerts()
  if not active() or not alerts.enabled or not connected() then return end
  local all, triggered = snapshot(), {}
  for who, info in pairs(all) do
    if key(who) ~= key(selfName()) then
      local state = alarmState[key(who)]
      if not state then state = {}; alarmState[key(who)] = state end
      for _, field in ipairs({'hp', 'mana'}) do
        local value, threshold = recentValue(info, field), alerts[field]
        local previous = state[field]
        if not previous then previous = {low = false, last = -15000}; state[field] = previous end
        if value == nil or threshold <= 0 or (value > threshold and value >= math.min(100, threshold + 5)) then
          previous.low = false
        elseif value <= threshold and not previous.low then
          previous.low = true
          if clock() - previous.last >= 15000 then
            previous.last = clock()
            triggered[#triggered + 1] = who .. ' ' .. (field == 'hp' and 'HP ' or 'mana ') .. value .. '%'
          end
        end
      end
    end
  end
  for who in pairs(alarmState) do
    local present = false
    for name in pairs(all) do if key(name) == who then present = true; break end end
    if not present then alarmState[who] = nil end
  end
  if #triggered == 0 then return end
  table.sort(triggered)
  lastAlert, lastAlertTime = table.concat(triggered, ' | '), clock()
  if type(warn) == 'function' then warn('BotServer: ' .. lastAlert) end
  if alerts.sound and type(playSound) == 'function' and clock() - lastSoundAt >= 15000 then
    playSound('/sounds/alarm.ogg'); lastSoundAt = clock()
  end
end

function dashboard.getRows() return model(snapshot()) end
function dashboard.getSelected() return selected end
function dashboard.setSearch(text) query = key(text); dashboard.refresh(true) end
function dashboard.getActiveExiva() return activeExiva() end

vBot.BotServerDashboard = dashboard

if botServerWindow and botServerWindow.MembersPage then
  local window, page = botServerWindow, botServerWindow.MembersPage
  window.Tabs.Companions.onClick = function() dashboard.showPage('companions') end
  window.Tabs.Exivas.onClick = function() dashboard.showPage('exivas') end
  window.Tabs.Connection.onClick = function() dashboard.showPage('connection') end
  window.closeButton.onClick = function() if active() then window:hide() end end
  local powerClick = window.enabled.onClick
  window.enabled.onClick = function(widget)
    if not active() then return end
    powerClick(widget)
    dashboard.refresh(true)
  end
  page.Search.onTextChange = function(_, text) dashboard.setSearch(text) end
  page.Favorites:setOn(settings.favoritesOnly)
  page.Favorites.onClick = function(widget)
    settings.favoritesOnly = not settings.favoritesOnly; widget:setOn(settings.favoritesOnly); dashboard.refresh(true)
  end
  page.SameFloor:setOn(settings.sameFloor)
  page.SameFloor.onClick = function(widget)
    settings.sameFloor = not settings.sameFloor; widget:setOn(settings.sameFloor); dashboard.refresh(true)
  end
  page.Sort:setOption(sortLabels[settings.sort])
  page.Sort.onOptionChange = function(widget)
    settings.sort = sortValues[widget:getCurrentOption().text] or 'name'; dashboard.refresh(true)
  end
  page.Selected.Locate.onClick = function()
    if selected then dashboard.locateMember(selected)
    elseif previewExiva then previewExiva.centerTarget = nil; openNaviMap() end
  end
  page.Selected.TargetLocate.onClick = function() dashboard.locateExivaTarget() end
  page.Selected.PreviewToggle.onClick = function()
    settings.preview = not settings.preview; dashboard.refresh(true)
  end
  page.Selected.ZoomIn.onClick = function()
    if not active() then return end
    previewZoom = math.min(4, previewZoom + 1); dashboard.refresh(true)
  end
  page.Selected.ZoomOut.onClick = function()
    if not active() then return end
    previewZoom = math.max(-2, previewZoom - 1); dashboard.refresh(true)
  end
  local map = page.Selected.Preview
  if type(map.disableAutoWalk) == 'function' then map:disableAutoWalk() end
  map.onMousePress = function() return true end
  map.onMouseRelease = function() return true end
  map.onDragEnter = function() return false end
  map.onDragMove = function() return false end
  map.onMouseWheel = function(_, _, direction)
    if not active() then return true end
    if MouseWheelUp and direction == MouseWheelUp then previewZoom = math.min(4, previewZoom + 1)
    elseif MouseWheelDown and direction == MouseWheelDown then previewZoom = math.max(-2, previewZoom - 1) end
    dashboard.refresh(true)
    return true
  end
  page.Alerts.Enabled:setOn(alerts.enabled)
  page.Alerts.Fold.onClick = function()
    alertsExpanded = not alertsExpanded; dashboard.refresh(true)
  end
  page.Alerts.Enabled.onClick = function(widget)
    alerts.enabled = not alerts.enabled; widget:setOn(alerts.enabled)
    alarmState, lastAlert, lastAlertTime = {}, nil, nil
    dashboard.refresh(true)
  end
  page.Alerts.Hp:setValue(alerts.hp)
  page.Alerts.Mana:setValue(alerts.mana)
  page.Alerts.Hp.onValueChange = function(_, value) alerts.hp = math.max(0, math.min(100, tonumber(value) or 0)) end
  page.Alerts.Mana.onValueChange = function(_, value) alerts.mana = math.max(0, math.min(100, tonumber(value) or 0)) end
  page.Alerts.Sound:setChecked(alerts.sound)
  page.Alerts.Sound.onCheckChange = function(_, value) alerts.sound = value == true end
  window.ExivaActivity.Locate.onClick = function()
    if not active() then return end
    local session, estimate = activeExiva()
    if session then
      selected, previewExiva = nil, {id = session.id, target = session.target, coordinator = session.coordinator}
      openNaviMap()
    end
  end
  dashboard.showPage('companions')
end

macro(500, function() dashboard.refresh(false) end)
macro(1000, function() dashboard.checkAlerts() end)
