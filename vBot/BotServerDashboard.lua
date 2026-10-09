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
local alertsExpanded = false
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

local function centerMap(pos)
  pos = position(pos)
  if not pos or not connected() then return false end
  -- Resolve the existing map only for this click. Never retain its native userdata.
  local module = modules and modules.game_minimap
  if not module then return false end
  local map
  if type(module.getMiniMapUi) == 'function' then map = module.getMiniMapUi() end
  map = map or module.minimapWidget
  if not map then return false end
  if module.minimapWindow and not module.fullmapView then
    module.minimapWindow:open()
    if module.minimapButton then module.minimapButton:setOn(true) end
  end
  map:setCameraPosition(pos)
  -- Leave the player's cross at the player's position. Existing member markers identify the peer.
  return true
end

function dashboard.locateMember(who)
  if not active() then return false end
  local info = snapshot()[who]
  local pos = recentPosition(info)
  if not pos then return false end
  selected = who
  local ok = centerMap(pos)
  dashboard.refresh(true)
  return ok
end

local function updatePreview(panel, pos)
  local show = settings.preview and pos ~= nil
  set(panel.Preview, 'setVisible', show)
  set(panel, 'setHeight', settings.preview and 82 or 60)
  set(panel.PreviewToggle, 'setOn', settings.preview)
  if not show then previewPosition = nil; return end
  local id = positionText(pos)
  if previewPosition ~= id then
    -- This map belongs to this bot window and is never reparented or shared.
    -- It is passive: no dragging, tile polling, guide overlay, or auto-walk hooks.
    panel.Preview:setZoom(0)
    panel.Preview:setCameraPosition(pos)
    previewPosition = id
  end
end

local function renderSelected(all)
  local panel = botServerWindow.MembersPage.Selected
  local info = selected and all[selected]
  local pos = recentPosition(info)
  set(panel.Name, 'setText', selected and shortName(selected, 32) or 'Selecciona un companero')
  set(panel.Name, 'setTooltip', selected or 'Selecciona una fila de la lista')
  set(panel.Position, 'setText', 'Posicion: ' .. positionText(pos))
  set(panel.Status, 'setText', not selected and '' or pos and 'Posicion reciente compartida' or 'Sin posicion reciente')
  set(panel.Locate, 'setEnabled', pos ~= nil)
  updatePreview(panel, pos)
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
      row.onClick = function() selected = who; dashboard.refresh(true) end
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

local function activeExiva()
  local tracker = vBot.ExivaTracker
  if not connected() or not tracker or not BotServer.isExivaTrackerEnabled() or tracker.isPaused() then return end
  local latest, current = nil, exivaClock()
  for _, session in pairs(tracker.getSessions()) do
    if session.visualUntil and session.visualUntil > current and
      (not latest or session.createdAt > latest.createdAt or
        (session.createdAt == latest.createdAt and session.id > latest.id)) then latest = session end
  end
  if not latest then return end
  local estimate = tracker.getEstimates()[key(latest.target)]
  if estimate and (estimate.expiresAt <= current or estimate.sessionId ~= latest.id) then estimate = nil end
  return latest, estimate
end

local function renderExiva()
  local panel, tracker = botServerWindow.ExivaActivity, vBot.ExivaTracker
  local control = tracker and tracker.getControlStatus and tracker.getControlStatus() or {}
  set(panel.Leader, 'setVisible', control.canStop == true)
  local session, estimate = activeExiva()
  set(panel.CurrentTarget, 'setText', 'Objetivo: ' .. (session and session.target or '-'))
  set(panel.CurrentInitiator, 'setText', 'Iniciador: ' .. (session and session.coordinator or '-'))
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
  set(panel.Locate, 'setEnabled', estimate ~= nil and not estimate.unbounded and position(estimate.position) ~= nil)
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
  set(window.Header.Status, 'setText', status)
  set(window.Header.Status, 'setColor', color)
  set(window.Header.Dot, 'setImageSource', assetRoot .. (connected() and 'status-green.png' or
    config.enabled and 'status-yellow.png' or 'status-red.png'))
  set(window.enabled.Dot, 'setImageSource', assetRoot .. (config.enabled and 'status-green.png' or 'status-gray.png'))
  set(window.Header.Members, 'setText', count .. ' jugadores')
  set(window.Header.Channel, 'setText', tostring(storage.BotServerChannel or ''))
  set(window.Tabs.Companions, 'setText', 'Companeros (' .. count .. ')')
  if currentPage == 'companions' then renderMembers(all)
  elseif currentPage == 'exivas' then renderExiva()
  else updateTransport() end
  local alertPanel = window.MembersPage.Alerts
  set(alertPanel.Enabled, 'setOn', alerts.enabled)
  set(alertPanel.Enabled, 'setText', alerts.enabled and 'ON' or 'OFF')
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
  window.titleClose.onClick = function() window:hide() end
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
  page.Selected.Locate.onClick = function() if selected then dashboard.locateMember(selected) end end
  page.Selected.PreviewToggle.onClick = function()
    settings.preview = not settings.preview; dashboard.refresh(true)
  end
  page.Selected.Preview.Target:setImageSource((configDir or '/bot/pruebas') .. '/vBot/map_markers/member-diamond.png')
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
    local _, estimate = activeExiva()
    if estimate and not estimate.unbounded then centerMap(estimate.position) end
  end
  dashboard.showPage('companions')
end

macro(500, function() dashboard.refresh(false) end)
macro(1000, function() dashboard.checkAlerts() end)
