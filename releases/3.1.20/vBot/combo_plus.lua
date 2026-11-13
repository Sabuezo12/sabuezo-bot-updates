setDefaultTab("Main")

local panelName = "ComboLeaderPlus"
storage[panelName] = storage[panelName] or {}
local settings = storage[panelName]

local DEFAULT_COMBO_RUNE_ID = 3155
-- Standard TFS CONST_ANI_SUDDENDEATH; configurable for custom servers.
local DEFAULT_SD_MISSILE_ID = 32
local DEFAULT_MW_RUNE_ID = 3180
local DEFAULT_MW_OBJECT_ID = 2129
local DEFAULT_MW_OBJECT_ID_2 = 2128
local DEFAULT_MW_OBJECT_ID_3 = 2130
-- Placed Magic Walls registered by this Helper (classic, color and retro).
local KNOWN_MW_OBJECT_IDS = {2128, 2129, 58242, 58243, 58244, 58245, 58246, 58247, 58248, 58249, 58250}
local MW_SIDE_SPREAD_LIMIT = 6

local defaults = {
  enabled = true,
  leader1 = "",
  leader2 = "",
  leader3 = "",
  missileEnabled = true,
  sdMissileId = DEFAULT_SD_MISSILE_ID,
  textEnabled = true,
  textPrefix = ".",
  spellTriggerText = "",
  attackTargetEnabled = true,
  shareTargetEnabled = true,
  ignoreFriends = true,
  comboRuneEnabled = true,
  comboRuneId = DEFAULT_COMBO_RUNE_ID,
  comboSpellEnabled = false,
  comboSpell = "",
  comboCooldown = 100,
  mwComboEnabled = false,
  mwRuneId = DEFAULT_MW_RUNE_ID,
  mwObjectId = DEFAULT_MW_OBJECT_ID,
  mwObjectId2 = DEFAULT_MW_OBJECT_ID_2,
  mwObjectId3 = DEFAULT_MW_OBJECT_ID_3,
  mwPattern = "auto",
  mwSide = "auto",
  mwReactDelay = 80,
  mwCooldown = 1000,
  followEnabled = false,
  followCombatPriority = true,
  followName = "",
  followDistance = 1,
  followIgnoreFields = true,
  commandsEnabled = true
}

for key, value in pairs(defaults) do
  if settings[key] == nil then
    settings[key] = value
  end
end

-- Follow ignores fields and traps by default now. Profiles that saved the old default (false)
-- are switched once; after that the checkbox is the user's to change.
if settings._followIgnoreFieldsAlways ~= true then
  settings.followIgnoreFields = true
  settings._followIgnoreFieldsAlways = true
end

if not settings._migratedFromOldCombo then
  local oldLeader = storage.ComboMultiLeader or {}
  local oldCombo = storage.combobot or {}

  if oldLeader.enabled ~= nil then
    settings.enabled = oldLeader.enabled == true
  elseif oldCombo.enabled ~= nil then
    settings.enabled = oldCombo.enabled == true
  end

  if settings.leader1 == "" and oldLeader.LeaderName and oldLeader.LeaderName ~= "name" then
    settings.leader1 = oldLeader.LeaderName
  end
  if settings.leader2 == "" and oldLeader.LeaderName2 and oldLeader.LeaderName2 ~= "name" then
    settings.leader2 = oldLeader.LeaderName2
  end
  if settings.leader3 == "" and oldLeader.LeaderName3 and oldLeader.LeaderName3 ~= "name" then
    settings.leader3 = oldLeader.LeaderName3
  end

  if settings.leader1 == "" then
    settings.leader1 = oldCombo.shootLeader or oldCombo.sayLeader or oldCombo.castLeader or ""
  end
  if oldCombo.item and tonumber(oldCombo.item) then
    settings.comboRuneId = tonumber(oldCombo.item)
  end
  local oldSpell = tostring(oldCombo.spell or "")
  if oldSpell:len() > 0 then
    settings.comboSpell = oldSpell
  end
  if oldCombo.attackItemEnabled ~= nil then
    settings.comboRuneEnabled = oldCombo.attackItemEnabled == true
  end
  if oldCombo.attackSpellEnabled ~= nil then
    settings.comboSpellEnabled = oldCombo.attackSpellEnabled == true
  end
  if oldLeader.Animation ~= nil then
    settings.missileEnabled = oldLeader.Animation == true
  end
  if oldLeader.Text ~= nil then
    settings.textEnabled = oldLeader.Text == true
  end
  if settings.spellTriggerText == "" and oldCombo.sayPhrase and oldCombo.sayPhrase ~= "" then
    settings.spellTriggerText = oldCombo.sayPhrase
  end

  if storage.extrasPvp then
    if storage.extrasPvp.mwRune then settings.mwRuneId = storage.extrasPvp.mwRune end
    if storage.extrasPvp.mwObj then settings.mwObjectId = storage.extrasPvp.mwObj end
    if storage.extrasPvp.mwObj2 then settings.mwObjectId2 = storage.extrasPvp.mwObj2 end
  end

  settings._migratedFromOldCombo = true
end

-- Preserve explicit OFF values. Old nonempty filters retain their meaning.
if settings.triggerMode == nil then
  settings.triggerMode = tostring(settings.spellTriggerText or ''):match('%S') and 'list' or 'offensive'
end
if settings.triggerMode ~= 'list' then settings.triggerMode = 'offensive' end

-- The cooperative formation is the requested default for existing profiles too.
-- Rune IDs, on/off preferences and delays are preserved.
if not settings._cooperativeMwDefault then
  settings.mwSide='auto';settings.mwPattern='auto'
  settings._cooperativeMwDefault=true
end

local function parseWallObjectIds(value)
  local ids,seen={},{}
  for token in tostring(value or ''):gmatch('[^,;|%s]+') do
    local id=tonumber(token)
    if id and id>=100 and id<=65535 and id==math.floor(id) and not seen[id] then
      seen[id]=true;ids[#ids+1]=id
    end
  end
  return ids
end

-- Seed only once. Keep the three saved choices and previous built-in fallbacks;
-- later edits, including an empty list, are authoritative and survive reloads.
if settings.mwObjectIds==nil then
  local entries={}
  for _,id in ipairs(KNOWN_MW_OBJECT_IDS)do entries[#entries+1]=tostring(id)end
  for _,key in ipairs({'mwObjectId','mwObjectId2','mwObjectId3'})do
    if settings[key]~=nil then entries[#entries+1]=tostring(settings[key])end
  end
  entries[#entries+1]='2130';entries[#entries+1]='11754'
  settings.mwObjectIds=table.concat(parseWallObjectIds(table.concat(entries,', ')),', ')
end

local root = g_ui.getRootWidget()
local comboPlusWindow = UI.createWindow("ComboPlusWindow", root)
comboPlusWindow:hide()
comboPlusWindow.closeButton.onClick = function()
  comboPlusWindow:hide()
end

local ui = setupUI([[
Panel
  height: 19

  HelperThemePower
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('Combo Leader')

  HelperThemeButton
    id: setup
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 17
    text: Setup
]])

ui.title:setOn(settings.enabled)
ui.title.onClick = function(widget)
  settings.enabled = not settings.enabled
  widget:setOn(settings.enabled)
end

ui.setup.onClick = function()
  comboPlusWindow:show()
  comboPlusWindow:raise()
  comboPlusWindow:focus()
end

local leftPanel = comboPlusWindow.comboPage.body
local followPanel = comboPlusWindow.followPage.body
local showLeaderPicker, learnLastSpell, refreshDiagnostics
local diagnostic = {signal='Sin senal recibida', result='Selecciona un lider y tu respuesta.'}
local lastLeaderSpell, pendingSpell
local function report(signal, result)
  if signal then diagnostic.signal=signal end
  if result then diagnostic.result=result end
end
local stopDistanceFollow
local stopFollowSearch
local chaseFollowName
local lastMasterValue
local function refreshMaster()
  if lastMasterValue==settings.enabled then return end
  lastMasterValue=settings.enabled
  comboPlusWindow.master:setOn(settings.enabled==true)
  comboPlusWindow.master:setText(settings.enabled and 'Combo ON' or 'Combo OFF')
  ui.title:setOn(settings.enabled==true)
end
comboPlusWindow.master.onClick=function()
  settings.enabled=not settings.enabled
  refreshMaster()
  if not settings.enabled and stopDistanceFollow then stopDistanceFollow() end
end
ui.title.onClick=function()
  settings.enabled=not settings.enabled
  refreshMaster()
  if not settings.enabled and stopDistanceFollow then stopDistanceFollow() end
end
local function showComboPage(name)
  for _,id in ipairs({'combo','follow'})do
    comboPlusWindow[id..'Page']:setVisible(id==name)
    comboPlusWindow.tabs[id]:setOn(id==name)
    comboPlusWindow[id..'Scroll']:setVisible(id==name)
  end
end
for _,id in ipairs({'combo','follow'})do
  local page=id
  comboPlusWindow.tabs[id].onClick=function()showComboPage(page)end
end
showComboPage('combo')
refreshMaster()

local function applyTooltip(widget, tooltip)
  if not widget or not tooltip or not widget.setTooltip then return end
  pcall(function()
    widget:setTooltip(tooltip)
  end)
end

local function addCheckBox(id, title, defaultValue, dest, tooltip)
  local widget = UI.createWidget("ComboPlusCheckBox", dest)
  widget:setId(id)
  tooltip = tooltip or title
  widget:setText(title)
  applyTooltip(widget, tooltip)
  if settings[id] == nil then settings[id] = defaultValue end
  widget:setOn(settings[id] == true)
  widget.onClick = function()
    widget:setOn(not widget:isOn())
    settings[id] = widget:isOn()
  end
  return widget
end

local function addItem(id, title, defaultItem, dest, tooltip)
  local widget = UI.createWidget("ComboPlusItem", dest)
  widget:setId(id)
  tooltip = tooltip or title
  widget.text:setText(title)
  applyTooltip(widget, tooltip)
  applyTooltip(widget.text, tooltip)
  applyTooltip(widget.item, tooltip)
  if settings[id] == nil then settings[id] = defaultItem end
  HelperClientCompat.setItemIdForDisplay(widget.item,tonumber(settings[id]) or defaultItem)
  widget.item.onItemChange = function(itemWidget)
    settings[id] = HelperClientCompat.itemIdFromWidget(itemWidget)
  end
  return widget
end

local function addTextEdit(id, title, defaultValue, dest, tooltip)
  local widget = UI.createWidget("ComboPlusTextEdit", dest)
  widget:setId(id)
  tooltip = tooltip or title
  widget.text:setText(title)
  applyTooltip(widget, tooltip)
  applyTooltip(widget.text, tooltip)
  applyTooltip(widget.textEdit, tooltip)
  if settings[id] == nil then settings[id] = defaultValue or "" end
  widget.textEdit:setText(tostring(settings[id] or ""))
  widget.textEdit.onTextChange = function(_, text)
    settings[id] = text
  end
  return widget
end

local function addScrollBar(id, title, minValue, maxValue, defaultValue, dest, tooltip)
  local widget = UI.createWidget("ComboPlusScrollBar", dest)
  widget:setId(id)
  tooltip = tooltip or title
  applyTooltip(widget, tooltip)
  applyTooltip(widget.text, tooltip)
  applyTooltip(widget.scroll, tooltip)
  widget.scroll:setRange(minValue, maxValue)
  if maxValue - minValue > 1000 then
    widget.scroll:setStep(100)
  elseif maxValue - minValue > 100 then
    widget.scroll:setStep(10)
  end
  if settings[id] == nil then settings[id] = defaultValue end
  widget.scroll.onValueChange = function(_, value)
    widget.text:setText(title .. ": " .. value)
    settings[id] = value
  end
  widget.scroll:setValue(tonumber(settings[id]) or defaultValue)
  widget.scroll.onValueChange(widget.scroll, widget.scroll:getValue())
  return widget
end

local function addSection(title, dest, tooltip)
  local widget = UI.createWidget("ComboPlusSection", dest)
  widget:setText(title)
  applyTooltip(widget, tooltip or title)
  return widget
end

local function addModeButtons(id, title, defaultValue, dest, tooltip)
  local widget = UI.createWidget("ComboPlusModeRow", dest)
  widget:setId(id)
  tooltip = tooltip or title
  widget.text:setText(title)
  applyTooltip(widget, tooltip)
  applyTooltip(widget.text, tooltip)
  applyTooltip(widget.autoButton, tooltip)
  applyTooltip(widget.halfButton, tooltip)
  if settings[id] == nil then settings[id] = defaultValue or "auto" end

  local function refresh()
    local mode = tostring(settings[id] or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
    if mode ~= "half" then mode = "auto" end
    settings[id] = mode
    widget.autoButton:setOn(mode == "auto")
    widget.halfButton:setOn(mode == "half")
  end

  widget.autoButton.onClick = function()
    settings[id] = "auto"
    refresh()
  end

  widget.halfButton.onClick = function()
    settings[id] = "half"
    refresh()
  end

  refresh()
  return widget
end

applyTooltip(ui.title, "Activa o desactiva todo el Combo Leader+.")
applyTooltip(ui.setup, "Abre la configuracion de combo, leaders y combo MW.")
applyTooltip(comboPlusWindow, "Combo, Magic Wall y todos sus ajustes en el mismo panel. Follow separado.")

local function addGroup(id,title)
  local group=UI.createWidget('ComboPlusGroup',leftPanel)
  group:setId(id)
  local heading=UI.createWidget('HelperThemeSectionTitle',group)
  heading:setText(title)
  heading:setHeight(18)
  return group
end

local leadersPanel=addGroup('leadersGroup','1. Lideres y objetivo')
local leaderRow=UI.createWidget('ComboPlusLeaderRow',leadersPanel)
leaderRow:setId('leader1')
leaderRow.textEdit:setText(tostring(settings.leader1 or ''))
leaderRow.textEdit.onTextChange=function(_,text) settings.leader1=text;lastLeaderSpell=nil end
leaderRow.choose.onClick=function() if showLeaderPicker then showLeaderPicker(leaderRow.choose) end end
applyTooltip(leaderRow.choose,'Elige un jugador visible o escribe su nombre.\nDebajo puedes configurar dos lideres alternativos.')
addTextEdit('leader2','Lider alternativo 2','',leadersPanel)
addTextEdit('leader3','Lider alternativo 3','',leadersPanel)
addSection('Objetivo y Navi',leadersPanel)
addCheckBox('attackTargetEnabled','Copiar objetivo: solo seleccionar',true,leadersPanel,'Copia el objetivo del lider conectado a Navi.\nSeleccionar nunca lanza SD ni UE.')
addCheckBox('shareTargetEnabled','Compartir mi objetivo por Navi',true,leadersPanel,'Activalo tambien en el Helper del lider.\nAmbos deben usar esta version y estar conectados al mismo grupo de Navi.')
addCheckBox('ignoreFriends','Proteger amigos',true,leadersPanel)
addSection('Comandos del lider',leadersPanel)
addCheckBox('commandsEnabled','Aceptar ue / sd,nombre / att,nombre',true,leadersPanel,'Solo acepta tus lideres.\nue solicita UE; sd,nombre solicita SD; att,nombre solo selecciona.')
addTextEdit('textPrefix','Prefijo de objetivo','.',leadersPanel,'Ejemplo: .NombreDelTarget.\nSolo selecciona; no lanza UE ni SD por si mismo.')

local combatPanel=addGroup('combatGroup','2. Runas y hechizos')
addSection('Runas: responder a la SD del lider',combatPanel)
addCheckBox('comboRuneEnabled','Si el lider tira SD: responder con SD',true,combatPanel)
addItem('comboRuneId','Mi runa de SD',DEFAULT_COMBO_RUNE_ID,combatPanel)
addCheckBox('missileEnabled','Detectar SD del lider',true,combatPanel,'Solo acepta el proyectil de SD configurado.\nFlechas, bolts, wand y otros proyectiles no activan el combo.')
addTextEdit('sdMissileId','Proyectil SD (ID)',32,combatPanel,'ID de animacion, no el ID de la runa.\nReferencia estandar: 32. Solo cambialo si el servidor usa otro.')
addSection('Hechizos: responder a la UE del lider',combatPanel)
addCheckBox('comboSpellEnabled','Si el lider tira UE: responder con mi UE',false,combatPanel)
addTextEdit('comboSpell','Mi hechizo UE','',combatPanel,'Escribe la UE de tu vocacion.\nSolo responde a la UE o lista elegida; no a una SD.')
addCheckBox('textEnabled','Detectar UE / lista por voz',true,combatPanel)
local triggerRow=UI.createWidget('ComboPlusTriggerRow',combatPanel)
triggerRow:setId('triggerMode')
local function refreshTriggerMode()
  triggerRow.offensive:setOn(settings.triggerMode=='offensive')
  triggerRow.list:setOn(settings.triggerMode=='list')
end
triggerRow.offensive.onClick=function()settings.triggerMode='offensive';refreshTriggerMode()end
triggerRow.list.onClick=function()settings.triggerMode='list';refreshTriggerMode()end
refreshTriggerMode()
applyTooltip(triggerRow.offensive,'Reacciona solo a las formulas UE reconocidas del lider.\nExcluye strikes, waves, curaciones y conversacion.')
applyTooltip(triggerRow.list,'Solo las formulas que hayas elegido expresamente.\nUsala para una UE personalizada del servidor.')
local triggerEdit=addTextEdit('spellTriggerText','Lista de hechizos','',combatPanel)
local learnButton=UI.createWidget('HelperThemeButton',combatPanel)
learnButton:setId('learnSpell');learnButton:setText('Agregar ultimo hechizo del lider')
learnButton:setHeight(22)
learnButton.onClick=function()if learnLastSpell then learnLastSpell()end end

addScrollBar('comboCooldown','Pausa de combo (ms)',0,1000,100,combatPanel)
applyTooltip(combatPanel,'Objetivo: solo seleccionar. SD: solo mi runa. UE: solo mi hechizo.\nCada respuesta respeta su interruptor.')

local wallPanel=addGroup('wallsGroup','3. Magic Wall')
addCheckBox("mwComboEnabled", "Responder a la Magic Wall del lider", false, wallPanel)
addItem("mwRuneId", "Mi runa de Magic Wall", DEFAULT_MW_RUNE_ID, wallPanel)
addModeButtons("mwPattern", "Distribucion de paredes", "auto", wallPanel, "Auto: completa ambos lados y extiende las paredes existentes.\nSemicirculo conserva la forma curva y busca huecos libres.")
addScrollBar("mwReactDelay", "Reaccion de MW (ms)", 0, 500, 80, wallPanel)
addScrollBar("mwCooldown", "Pausa entre paredes (ms)", 200, 2000, 1000, wallPanel)
local wallIdsEditor=UI.createWidget('ComboPlusWallIds',wallPanel)
wallIdsEditor:setId('mwObjectIds')
wallIdsEditor.text:setText('IDs reconocidos (separados por comas)')
wallIdsEditor.textEdit:setText(tostring(settings.mwObjectIds or ''))
wallIdsEditor.textEdit.onTextChange=function(_,text)settings.mwObjectIds=text end
applyTooltip(wallIdsEditor.textEdit,'Incluye las variantes clasicas, de color y retro registradas por Helper.\nPuedes agregar o quitar IDs, separados por comas, espacios o saltos de linea.')
applyTooltip(wallPanel,'Las variantes conocidas ya estan incluidas y se conservan tus IDs anteriores.\nLos IDs repetidos o invalidos se ignoran.')

addSection("Seguir a un jugador",followPanel)
local followSwitch = addCheckBox("followEnabled", "Seguimiento", false, followPanel)
followSwitch.onClick = function()
  followSwitch:setOn(not followSwitch:isOn())
  settings.followEnabled = followSwitch:isOn()
  if not settings.followEnabled then
    if stopDistanceFollow then stopDistanceFollow() end
    if g_game and g_game.cancelFollow then pcall(g_game.cancelFollow) end
  end
end
addTextEdit("followName", "Jugador a seguir", "", followPanel, "Recuerda su ultima posicion para recuperar escaleras y cambios de piso.")
local function configuredFollowDistance()
  return math.max(1,math.min(5,math.floor(tonumber(settings.followDistance) or 1)))
end
settings.followDistance=configuredFollowDistance()
addScrollBar("followDistance", "Separacion (SQM)", 1, 5, 1, followPanel, "Distancia deseada de 1 a 5 SQM.\nEn escaleras se acerca para cruzar y recupera la separacion al ver al leader.")
addCheckBox("followIgnoreFields", "Ignorar fields y trampas", true, followPanel, "Camina sobre fire, energy y poison y por casillas que el cliente marca como no transitables (trampas) si el camino lo necesita.\nNo atraviesa magic wall, paredes ni criaturas.")
addCheckBox("followCombatPriority", "Priorizar Follow al caminar", true, followPanel,
  "Permite girar y acomodarse al parar el leader; margen de 1 SQM extra.")
addCheckBox('followBoat','Seguir viajes en barco',false,followPanel,
  'Viaja si el salto reciente del leader coincide con una ruta Travel de este perfil de CaveBot. El NPC cobra su tarifa normal.')
addCheckBox('followSupplies','Comprar supplies con el lider',true,followPanel,
  'Con Navi, compra tus supplies en la misma tienda cuando el lider usa Buy Supplies. Despues retoma el Follow.')
local followStatus=addSection("Seguimiento apagado",followPanel)
followStatus:setId('followStatus')
applyTooltip(followPanel,'Recupera Follow si se pierde. Fuera de pantalla busca su posicion reciente en Navi y su rastro de pisos.\nNecesita mapa transitable; ambos Helpers actualizados comparten accesos entre pisos.\nReintenta si no avanza. Los barcos requieren una ruta de transporte.')

local recentWallShots = {}
local comboBursts = {}
local followPositions = {}
local followFloorReturns = {}
local followSearch
local activeFollowName = ""
local lastFollowPosition = nil
local lastFollowTransitionPosition = nil
local lastFollowTransitionArrival = nil
local lastFollowWalkAt = 0
local lastFollowUseAt = 0
local lastFollowProgressAt = 0
local lastPlayerPositionKey = ""
local followWasActive = false
local lastFollowSeenAt = 0
local lastFollowRequestAt, lastFollowRequestName = 0, ""
local lastFollowTransitionAt = 0
local lastFollowRecoveryAt = 0
local followFreedAfterLost = false
local spacing = {}
local lastFollowStatus = ''
-- Read-only measurement of the Follow (console: Acciones / Combo Follow, every 30 s while it is on):
-- time between own steps, how fast we answer a leader step, how long a lost leader takes to be seen
-- again, and the share of time per status. One table keeps the main chunk's local count low.
local followTrace = {}
do
  local function traceNow()
    if now then return now end
    if g_clock and g_clock.millis then return g_clock.millis() end
    return 0
  end
  local data = {statusAt = 0, spent = {}, steps = {}, reactions = {}, recoveries = {}, lostAt = nil,
    wasVisible = false, leaderMovedAt = nil, lastStepAt = 0, lostCount = 0, summaryAt = 0}
  local function ringAdd(ring, value)
    ring[#ring + 1] = value
    while #ring > 20 do table.remove(ring, 1) end
  end
  local function stats(ring)
    if #ring == 0 then return 'sin datos' end
    local sorted = {}
    for i, v in ipairs(ring) do sorted[i] = v end
    table.sort(sorted)
    return 'mediana ' .. sorted[math.ceil(#sorted / 2)] .. ' ms (min ' .. sorted[1] .. ', max ' .. sorted[#sorted] .. ', n ' .. #sorted .. ')'
  end
  local function statusKey(text)
    local key = tostring(text):gsub('[%d%-]+', ''):gsub('%s+', ' ')
    return key:sub(1, 36)
  end
  function followTrace.status(old, new)
    local t = traceNow()
    if data.statusAt > 0 and old ~= '' then
      local key = statusKey(old)
      data.spent[key] = (data.spent[key] or 0) + (t - data.statusAt)
    end
    data.statusAt = t
  end
  function followTrace.visible(visible)
    local t = traceNow()
    if visible then
      if data.lostAt then
        ringAdd(data.recoveries, t - data.lostAt)
        data.lostAt = nil
      end
      data.wasVisible = true
    elseif data.wasVisible and not data.lostAt then
      data.lostAt = t
      data.lostCount = data.lostCount + 1
    end
  end
  function followTrace.leaderMoved()
    if not data.leaderMovedAt then data.leaderMovedAt = traceNow() end
  end
  function followTrace.ownStep()
    local t = traceNow()
    if data.lastStepAt > 0 and t - data.lastStepAt < 3000 then ringAdd(data.steps, t - data.lastStepAt) end
    data.lastStepAt = t
    if data.leaderMovedAt then
      ringAdd(data.reactions, t - data.leaderMovedAt)
      data.leaderMovedAt = nil
    end
  end
  function followTrace.summary(currentStatus)
    local t = traceNow()
    if t - data.summaryAt < 30000 then return end
    if #data.steps < 6 and data.lostCount == 0 then return end
    if not (RinoConsole and RinoConsole.valid and RinoConsole.valid()) then return end
    data.summaryAt = t
    pcall(RinoConsole.log, 'action', 'Combo Follow', 'ritmo de seguimiento',
      'entre pasos: ' .. stats(data.steps) .. ' | del paso del leader al mio: ' .. stats(data.reactions))
    pcall(RinoConsole.log, 'action', 'Combo Follow', 'leader perdido: ' .. data.lostCount .. ' veces',
      'tiempo en recuperarlo: ' .. stats(data.recoveries))
    -- Share of the last 30 s per status (the open status counts up to now).
    if data.statusAt > 0 and currentStatus and currentStatus ~= '' then
      local key = statusKey(currentStatus)
      data.spent[key] = (data.spent[key] or 0) + (t - data.statusAt)
      data.statusAt = t
    end
    local list, total = {}, 0
    for key, ms in pairs(data.spent) do list[#list + 1] = {key = key, ms = ms}; total = total + ms end
    table.sort(list, function(a, b) return a.ms > b.ms end)
    local parts = {}
    for i = 1, math.min(4, #list) do
      parts[#parts + 1] = list[i].key .. ' ' .. math.floor(list[i].ms * 100 / math.max(1, total)) .. '%'
    end
    if #parts > 0 then
      pcall(RinoConsole.log, 'action', 'Combo Follow', 'tiempo por estado', table.concat(parts, ' | '))
    end
    data.spent = {}
  end
  -- A measurement error must never stop the Follow itself.
  for name, fn in pairs(followTrace) do
    followTrace[name] = function(...) pcall(fn, ...) end
  end
end
local function setFollowStatus(text)
  if text~=lastFollowStatus then followTrace.status(lastFollowStatus,text);followStatus:setText(text);lastFollowStatus=text end
end
stopDistanceFollow=function()
  -- Spacing sends one checked step, never a queued native follow/autowalk.
  spacing={}
end
local FOLLOW_STICKY_WALK_RETRY_MS = 150
local FOLLOW_STUCK_RECOVERY_MS = 550
local FOLLOW_TRANSITION_RECOVERY_MS = 180
local FOLLOW_TRANSITION_TTL_MS = 8000
local FOLLOW_DOOR_IDS = {
  5007, 8265, 31570, 1629, 1632, 5129, 6252, 6249, 7715, 7712, 7714,
  7719, 6256, 1669, 1672, 5125, 5115, 5124, 17701, 17710, 1642,
  6260, 5107, 4912, 6251, 5291, 1683, 1696, 1692, 5006, 2179, 5116,
  11705, 30772, 30774, 6248, 5735, 5732, 5120, 23873, 5736,
  6264, 5122, 30049, 30042, 7727, 5293, 9567, 34847, 1764, 21051,
  30823, 5282, 20453, 2772, 27260, 2773, 5281, 1968, 31116, 31120,
  30742, 31115, 31118, 20474, 5733, 31202, 31228, 31199, 31200,
  33262, 30824, 5126, 8257, 8258, 8255, 8256, 30777, 30776,
  23877, 31130, 25803, 16277, 5098, 5104, 5102, 5106, 5109, 5111,
  5113, 5118, 5100, 1638, 1640, 19250, 3500, 3497, 3498, 3499,
  2177, 17709, 23875, 1644, 5131, 28546, 6254, 30364, 30365,
  30367, 30368, 30363, 30366, 31139, 31138, 31136, 31137, 4981,
  4977, 11714, 7771, 9558, 9559, 20475, 2909, 2907, 8618, 31366,
  1646, 1648, 4997, 22506, 8259, 27503, 27505, 27507, 31476, 31477,
  31475, 31474, 8363, 5097, 11237, 11246, 9874, 33634, 33633,
  22632, 22639, 1631, 1628, 20446, 20443, 20444, 2334, 9357, 9355,
  1687, 1698
}

local function getTime()
  if now then return now end
  if g_clock and g_clock.millis then return g_clock.millis() end
  return 0
end

local function trim(value)
  return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function lower(value)
  return trim(value):lower()
end

local function normalized(value)
  return lower(value):gsub('%s+',' ')
end

local function formulaOnly(value)
  -- A quoted spell parameter is not part of its formula. Keep unquoted suffixes
  -- significant: exori gran must never accidentally match exori gran frigo.
  return normalized(value):gsub('%s+["].*$', '')
end

local function textMatchesTrigger(text, triggerText)
  local message=normalized(text)
  if message=='' then return false end
  for phrase in tostring(triggerText or ''):gmatch('[^,;|\n\r]+') do
    phrase=normalized(phrase)
    if phrase~='' and (message==phrase or message:sub(1,#phrase+2)==phrase..' "') then return true end
  end
  return false
end

local function offensiveSpell(text)
  local words=formulaOnly(text)
  -- Prefer the installed catalog. Fallback covers custom offensive formula
  -- families without treating heals, support or arbitrary chat as triggers.
  if words=='exori' or words:match('^exori%s') or words:match('^utori%s') then return true end
  if not words:match('^exevo%s') then return false end
  if AttackRotation and AttackRotation.spells and AttackRotation.spells[words] then return true end
  if AttackSpellCatalog and AttackSpellCatalog.find and AttackSpellCatalog.find(words) then return true end
  return words=='exevo max mort' or words:match('^exevo .+ mas ')~=nil or words:match('^exevo ulus ')~=nil
    or words:match(' hur$')~=nil or words:match(' lux$')~=nil or words:match(' ora$')~=nil
end

-- Exact known UE/burst formulas. Never classify every damaging spell as
-- an ultimate, and never infer a spell merely from a normal attack missile.
-- Explicit custom voice lists remain opt-in and retain their saved formulas.
local ueFormulas={
  ['exevo gran mas flam']=true,['exevo gran mas vis']=true,
  ['exevo gran mas frigo']=true,['exevo gran mas tera']=true,
  ['exevo mas san']=true,['exevo ulus frigo']=true,['exevo ulus tera']=true,
  ['exori gran mas nia']=true
}
local function ultimateSpell(text)
  return ueFormulas[formulaOnly(text)]==true
end
local function sdMissile(missile)
  local wanted=tonumber(settings.sdMissileId)
  if not wanted or wanted~=math.floor(wanted) or wanted<1 or wanted>65535 then return false end
  if not missile or type(missile.getId)~='function' then return false end
  local ok,id=pcall(missile.getId,missile)
  return ok and tonumber(id)==wanted
end

local function hasPosition(pos)
  return pos and pos.x and pos.y and pos.z
end

local function copyPosition(pos)
  if not hasPosition(pos) then return nil end
  return {x = pos.x, y = pos.y, z = pos.z}
end

local function positionKey(pos)
  if not hasPosition(pos) then return "" end
  return pos.x .. "," .. pos.y .. "," .. pos.z
end

local function sameCreature(a, b)
  if not a or not b then return false end
  return lower(a:getName()) == lower(b:getName())
end

local function getCurrentTarget()
  if type(getTarget) == "function" then
    local ok, creature = pcall(getTarget)
    if ok and creature then return creature end
  end
  if type(target) == "function" then
    local ok, creature = pcall(target)
    if ok and creature then return creature end
  end
  if g_game and g_game.getAttackingCreature then
    local ok, creature = pcall(function() return g_game.getAttackingCreature() end)
    if ok and creature then return creature end
  end
  return nil
end

local function getLeaders()
  local leaders = {}
  for _, key in ipairs({"leader1", "leader2", "leader3"}) do
    local name = trim(settings[key])
    if name ~= "" and name ~= "name" then
      table.insert(leaders, lower(name))
    end
  end
  return leaders
end

local function isLeader(name)
  local nameLower = lower(name)
  if nameLower == "" then return false end
  for _, leader in ipairs(getLeaders()) do
    if leader == nameLower then return true end
  end
  return false
end

local function getPlayerZ()
  if type(posz) == "function" then return posz() end
  local playerPos = player and player:getPosition()
  return playerPos and playerPos.z
end

local function getPlayerPosition()
  if player and player.getPosition then
    local ok, pos = pcall(function() return player:getPosition() end)
    if ok then return pos end
  end
  return nil
end

local function getPositionKey(pos)
  if not hasPosition(pos) then return "" end
  return pos.x .. "," .. pos.y .. "," .. pos.z
end

local function distanceBetween(a, b)
  if not hasPosition(a) or not hasPosition(b) or a.z ~= b.z then return 999 end
  return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

local function samePosition(a, b)
  return hasPosition(a) and hasPosition(b) and a.x == b.x and a.y == b.y and a.z == b.z
end

local function getFollowName()
  local name = trim(settings.followName)
  if name == "" or lower(name) == "name" then return "" end
  return name
end

-- Some OTC bindings look up visible players with case-sensitive names.
local function findFollowCreature(observedOnly)
  local name=getFollowName();if name=='' then return nil end
  local function matches(creature)
    return creature and creature.isPlayer and creature:isPlayer() and
      not (creature.isRemoved and creature:isRemoved()) and
      creature.getName and lower(creature:getName())==lower(name) and
      creature.getPosition and creature:getPosition() and
      not (creature.isLocalPlayer and creature:isLocalPlayer())
  end
  local cached
  if type(getCreatureByName)=='function' then
    local ok,creature=pcall(getCreatureByName,name)
    if ok and matches(creature) then cached=creature end
  end
  local recovering=followSearch and followSearch.source=='navi'
  if cached and not observedOnly and not recovering then return cached end
  if type(getSpectators)=='function' then
    local ok,actors=pcall(getSpectators,false)
    if ok and type(actors)=='table' then
      local count=0
      for _,creature in pairs(actors)do
        count=count+1;if count>256 then break end
        if matches(creature) then return creature end
      end
      return nil -- An absent visible actor must not cancel a running Navi route.
    end
  end
  return cached -- Older clients without a working spectators API.
end

local function resetFollowMemoryIfNeeded()
  local name = lower(getFollowName())
  if activeFollowName == name then return end
  activeFollowName = name
  if stopFollowSearch then stopFollowSearch() end
  stopDistanceFollow()
  followPositions = {}
  followFloorReturns = {}
  lastFollowPosition = nil
  lastFollowTransitionPosition = nil
  lastFollowTransitionArrival = nil
  lastFollowSeenAt = 0
  lastFollowTransitionAt = 0
  lastFollowRecoveryAt = 0
  followFreedAfterLost = false
  if g_game and g_game.cancelFollow then
    pcall(function() g_game.cancelFollow() end)
  end
end

local function rememberFollowPosition(pos)
  if hasPosition(pos) then
    local copied = copyPosition(pos)
    followPositions[pos.z] = copied
    lastFollowPosition = copied
  end
end

local function isFollowCreature(creature)
  local name = getFollowName()
  return name ~= "" and creature and creature:isPlayer() and lower(creature:getName()) == lower(name)
end

local function getFollowingCreature()
  if not g_game or not g_game.getFollowingCreature then return nil end
  local ok, creature = pcall(function() return g_game.getFollowingCreature() end)
  return ok and creature or nil
end

local function cancelWrongFollow(name)
  local following = getFollowingCreature()
  if following and lower(following:getName()) ~= lower(name) and g_game and g_game.cancelFollow then
    pcall(function() g_game.cancelFollow() end)
  end
end

local function followCreature(creature)
  if not creature then return false end
  cancelWrongFollow(creature:getName())
  local following = getFollowingCreature()
  if following and sameCreature(following, creature) then return true end
  local time=getTime();local name=lower(creature:getName())
  if lastFollowRequestName==name and time>=lastFollowRequestAt and time-lastFollowRequestAt<150 then return true end
  lastFollowRequestName=name;lastFollowRequestAt=time
  if g_game and g_game.follow then
    local ok, result = pcall(function() return g_game.follow(creature) end)
    if ok then return result~=false end
  end
  if type(follow) == "function" then
    local ok = pcall(function() follow(creature) end)
    if ok then return true end
  end
  return false
end

local function safeUse(func, ...)
  if not func then return false end
  local ok, result = pcall(func, ...)
  return ok and result ~= false
end

local function tryUseThing(thing)
  if not thing then return false end
  if safeUse(use, thing) then return true end
  if g_game and g_game.use and safeUse(function(target) g_game.use(target) end, thing) then return true end
  return false
end

local function tryUseTool(toolId, thing)
  toolId = tonumber(toolId)
  if not toolId or toolId <= 0 or not thing then return false end
  if safeUse(useWith, toolId, thing) then return true end
  if g_game and g_game.useInventoryItemWith then
    return safeUse(function(id, target) g_game.useInventoryItemWith(id, target, 0) end, toolId, thing)
  end
  return false
end

local function isFollowDoorThing(thing, global)
  if not thing or not thing.getId then return false end
  local id = thing:getId()
  return table.find(global.doorIds or {}, id) or
    table.find(global.doorsIds or {}, id) or
    table.find(global.openDoorIds or {}, id) or
    table.find(FOLLOW_DOOR_IDS, id)
end

local function tryOpenFollowDoor(tile, global)
  if not tile then return false end

  local topUseThing = tile.getTopUseThing and tile:getTopUseThing()
  if isFollowDoorThing(topUseThing, global) and tryUseThing(topUseThing) then return true end

  local items = tile.getItems and tile:getItems() or {}
  for _, item in ipairs(items) do
    if isFollowDoorThing(item, global) and tryUseThing(item) then return true end
  end

  local topThing = tile.getTopThing and tile:getTopThing()
  if isFollowDoorThing(topThing, global) and tryUseThing(topThing) then return true end

  return false
end

local function followSign(value)
  if value > 0 then return 1 end
  if value < 0 then return -1 end
  return 0
end

local function followDirectionTo(fromPos, toPos)
  if not hasPosition(fromPos) or not hasPosition(toPos) then return nil end
  local dx = followSign(toPos.x - fromPos.x)
  local dy = followSign(toPos.y - fromPos.y)

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

local function stepIntoFollowPosition(pos)
  if not hasPosition(pos) or pos.z ~= getPlayerZ() then return false end
  local playerPos = getPlayerPosition()
  local distance = distanceBetween(playerPos, pos)
  if distance > 1 then return false end

  if distance == 0 then return false end

  local time = getTime()
  if player and player.isWalking and player:isWalking() and time - lastFollowWalkAt < 250 then
    return true
  end

  local dir = followDirectionTo(playerPos, pos)
  if dir == nil then return false end

  if g_game and g_game.walk then
    local ok, result = pcall(g_game.walk, dir, false)
    if ok then
      if result ~= false then lastFollowWalkAt = time end
      return result ~= false
    end
  end

  if type(walk) == "function" then
    local ok = pcall(function() walk(dir) end)
    if ok then
      lastFollowWalkAt = time
      return true
    end
  end

  return false
end

local function addFollowUseTile(tiles, seen, pos, priority, origin)
  if not hasPosition(pos) or pos.z ~= getPlayerZ() then return end
  if hasPosition(origin) and distanceBetween(origin, pos) > 2 then return end
  local key = getPositionKey(pos)
  if key == "" or seen[key] then return end

  local tile = g_map and g_map.getTile and g_map.getTile(pos)
  if not tile then return end

  seen[key] = true
  table.insert(tiles, {
    tile = tile,
    distance = distanceBetween(getPlayerPosition(), pos),
    priority = priority or 10
  })
end

local function followUseTilesAround(pos)
  local tiles = {}
  local seen = {}
  local playerPos = getPlayerPosition()

  addFollowUseTile(tiles, seen, pos, 0, pos)
  addFollowUseTile(tiles, seen, playerPos, 1, pos)

  if hasPosition(pos) then
    for dx = -1, 1 do
      for dy = -1, 1 do
        addFollowUseTile(tiles, seen, {x = pos.x + dx, y = pos.y + dy, z = pos.z}, 2, pos)
      end
    end
  end

  if hasPosition(playerPos) then
    for dx = -1, 1 do
      for dy = -1, 1 do
        addFollowUseTile(tiles, seen, {x = playerPos.x + dx, y = playerPos.y + dy, z = playerPos.z}, 3, pos)
      end
    end
  end

  table.sort(tiles, function(a, b)
    if a.priority ~= b.priority then return a.priority < b.priority end
    return a.distance < b.distance
  end)

  return tiles
end

local function tryUseFollowTransition(pos, force, knownOnly, markedTile)
  if not hasPosition(pos) then return false end
  local playerPos = getPlayerPosition()
  if distanceBetween(playerPos, pos) > 2 then return false end

  local time = getTime()
  local useCooldown = force and 120 or 350
  if time - lastFollowUseAt < useCooldown then return false end
  lastFollowUseAt = time

  local extras = storage.extras or {}
  local global = Global or {}
  local shovel = extras.shovel or 3457
  local rope = extras.rope or 3003
  local machete = extras.machete or 3308
  local scythe = extras.scythe or 3453
  local tiles = markedTile and {{tile=markedTile}} or followUseTilesAround(pos)

  local explorer = CaveBot and CaveBot.AutoExplorer
  if markedTile and explorer and explorer.getFloorChangeThing then
    local thing, action = explorer.getFloorChangeThing(markedTile)
    if thing then
      local id = thing:getId()
      if action == "rope" or table.find(global.ropeIds or {}, id) then return tryUseTool(rope, thing) end
      if action == "shovel" or table.find(global.shovelIds or {}, id) then return tryUseTool(shovel, thing) end
      return tryUseThing(thing)
    end
  end

  for _, entry in ipairs(tiles) do
    local tile = entry.tile
    if tryOpenFollowDoor(tile, global) then return true end

    local items = tile.getItems and tile:getItems() or {}
    for _, item in ipairs(items) do
      local id = item:getId()
      if isFollowDoorThing(item, global) then
        if tryUseThing(item) then return true end
      elseif table.find(global.useIds or {}, id) then
        if tryUseThing(item) then return true end
      elseif table.find(global.shovelIds or {}, id) then
        if tryUseTool(shovel, item) then return true end
      elseif table.find(global.ropeIds or {}, id) then
        if tryUseTool(rope, item) then return true end
      elseif table.find(global.macheteIds or {}, id) then
        if tryUseTool(machete, item) then return true end
      elseif table.find(global.scytheIds or {}, id) then
        if tryUseTool(scythe, item) then return true end
      end
    end
  end

  -- Only try an unlisted use target when the map itself marked this access.
  if markedTile then return tryUseThing(markedTile.getTopUseThing and markedTile:getTopUseThing()) end
  if knownOnly then return false end
  local usedFallback = false
  local usedThings = {}
  for _, entry in ipairs(tiles) do
    local tile = entry.tile
    local tilePos = tile.getPosition and tile:getPosition()
    local tileKey = getPositionKey(tilePos)
    local fallbackThings = {}
    local function addFallbackThing(thing)
      if thing then table.insert(fallbackThings, thing) end
    end
    addFallbackThing(tile.getTopUseThing and tile:getTopUseThing())
    addFallbackThing(tile.getTopThing and tile:getTopThing())
    addFallbackThing(tile.getGround and tile:getGround())

    for _, thing in ipairs(fallbackThings) do
      if thing and thing.getId then
        local id = thing:getId()
        local key = id .. ":" .. tileKey
        if not usedThings[key] and tryUseThing(thing) then
          usedThings[key] = true
          usedFallback = true
        end
      end
    end
  end

  return usedFallback
end

-- Follow owns movement until its visible player has stopped and we have
-- arrived. A short spell route may borrow movement until that player moves.
ComboFollowCombat = {}
local followCombat = ComboFollowCombat
local restock = {queue={}, seen={}, seenIds={}}
function followCombat.isRestocking() return restock.active~=nil end
local combatLeader, combatPosition, combatMovedAt = nil, nil, 0
local combatBorrowed, combatCache, combatChase = false, nil, nil
local combatSpellUntil, combatWaveWalk = 0, false
local combatCross
local function combatSafety()
  local movement=TargetBot and TargetBot.Movement
  local safety=TargetBot and TargetBot.Antitrap
  return not (movement and movement.isManual and movement.isManual()) and
    not (safety and safety.ownsMovement and safety.ownsMovement()) and
    not (CaveBot and CaveBot.Flee and CaveBot.Flee.blocksCombat()) and
    not (CaveBot and CaveBot.WaitStamina and CaveBot.WaitStamina.isBlocking()) and
    not (type(isInPz)=='function' and isInPz())
end
local function releaseCombat(fromAttack)
  local borrowed=combatBorrowed
  combatBorrowed=false;combatCache=nil;combatSpellUntil=0;combatWaveWalk=false;combatCross=nil
  if borrowed and not fromAttack and AttackAlignment and AttackAlignment.yieldToFollow then
    AttackAlignment.yieldToFollow()
  end
  if combatChase~=nil then
    local safety=TargetBot and TargetBot.Antitrap
    if not (safety and safety.ownsMovement and safety.ownsMovement()) and
      g_game and g_game.getChaseMode and g_game.setChaseMode then
      local ok,mode=pcall(g_game.getChaseMode)
      if ok and mode==0 then pcall(g_game.setChaseMode,combatChase) end
    end
    combatChase=nil
  end
end
function followCombat.getState()
  local time=getTime()
  if restock.active then
    releaseCombat()
    return {active=true,ready=false,time=time}
  end
  local name=lower(getFollowName())
  local active=settings.enabled and settings.followEnabled and settings.followCombatPriority and name~=''
  if not active then
    releaseCombat();combatLeader=nil;combatPosition=nil
    return {active=false,ready=false}
  end
  if combatCache and combatCache.time==time then return combatCache end
  local creature=findFollowCreature()
  local leaderPos=creature and copyPosition(creature:getPosition())
  local origin=getPlayerPosition()
  local desired=configuredFollowDistance()
  local valid=creature and isFollowCreature(creature) and leaderPos and origin and leaderPos.z==origin.z
  if not valid then
    releaseCombat();combatLeader=nil;combatPosition=nil
    combatCache={active=true,ready=false,time=time};return combatCache
  end
  local identity=name..':'..tostring(creature.getId and creature:getId() or creature)
  if combatLeader~=identity or not samePosition(combatPosition,leaderPos) or time<combatMovedAt then
    releaseCombat();combatLeader=identity;combatPosition=copyPosition(leaderPos);combatMovedAt=time
  end
  if creature.isWalking and creature:isWalking() then combatMovedAt=time end
  if combatSpellUntil>0 and time>=combatSpellUntil then releaseCombat() end
  local dist=distanceBetween(origin,leaderPos)
  local wavePositioning=AttackBot and AttackBot.canAlignWhileFollowing and AttackBot.canAlignWhileFollowing()
  local holdingCross=wavePositioning and combatCross and samePosition(origin,combatCross)
  if combatCross and not holdingCross then releaseCombat() end
  local minimum=wavePositioning and math.max(1,desired-1) or 0
  local radius=desired+1
  local within=dist>=minimum and dist<=radius
  local settledDistance=dist==desired or desired==1 and dist<=1
  if wavePositioning then
    -- Waves reach several SQM: once the leader stops, start from wherever the
    -- follower is (up to 3 SQM past the separation, any separation 1-5)
    -- instead of first finishing the Follow approach.
    settledDistance=dist>=1 and dist<=desired+3
  end
  local onSpellRoute=wavePositioning and combatWaveWalk and dist>=1
  local arrived=combatBorrowed and (within or onSpellRoute or holdingCross) or not combatBorrowed and settledDistance and
    not (player.isWalking and player:isWalking())
  local ready=combatSafety() and arrived and time-combatMovedAt>=200
  if not ready then releaseCombat() end
  combatCache={active=true,ready=ready==true,anchor=copyPosition(leaderPos),
    minimum=minimum,radius=radius,desired=desired,wavePositioning=wavePositioning,
    borrowed=combatBorrowed,cross=ready and holdingCross,time=time}
  return combatCache
end
function followCombat.acquire(spellDeadline)
  local state=followCombat.getState()
  if not state.active then return true end
  if not state.ready or not combatSafety() then return false end
  if state.wavePositioning and (spellDeadline or not combatCross) then
    combatSpellUntil=math.max(combatSpellUntil,spellDeadline or state.time+300)
    if spellDeadline then combatWaveWalk=true;combatCross=nil;state.cross=false end
  end
  if not combatBorrowed then
    combatBorrowed=true;state.borrowed=true
    stopDistanceFollow()
    local following=getFollowingCreature()
    if following and isFollowCreature(following) and g_game and g_game.cancelFollow then
      pcall(g_game.cancelFollow)
    end
    if g_game and g_game.getChaseMode and g_game.setChaseMode then
      local ok,mode=pcall(g_game.getChaseMode)
      if ok then combatChase=mode;if mode~=0 then pcall(g_game.setChaseMode,0) end end
    end
  end
  return true
end
-- anyTile: also keep a tile off the leader's row/column where a wave was just cast.
function followCombat.holdCross(position, anyTile)
  local state=followCombat.getState()
  local leader=state.anchor
  if not state.ready or not state.wavePositioning or not leader or not samePosition(position,getPlayerPosition()) or
    position.z~=leader.z or samePosition(position,leader) or
    not anyTile and position.x~=leader.x and position.y~=leader.y or not followCombat.acquire() then return false end
  combatCross=copyPosition(position)
  combatSpellUntil=0;combatWaveWalk=false
  state.cross=true
  return true
end
function followCombat.releaseSpell(includeCross)
  if combatSpellUntil>0 or includeCross and combatCross then releaseCombat(true) end
end
function followCombat.allowsPosition(position, spellRoute)
  local state=followCombat.getState()
  if not state.active then return true end
  if not state.ready or not position or not state.anchor or position.z~=state.anchor.z then return false end
  local dist=distanceBetween(position,state.anchor)
  if spellRoute and state.wavePositioning then return dist>=1 end
  return dist>=state.minimum and dist<=state.radius
end
function followCombat.invalidate(moved)
  releaseCombat()
  if moved then combatMovedAt=getTime() end
end

local function walkToFollowPosition(pos, precision, maxDist)
  local currentZ = getPlayerZ()
  if not hasPosition(pos) or not currentZ or pos.z ~= currentZ then return false end
  local time = getTime()
  local walkingCooldown = precision and precision > 0 and 250 or 500
  if player and player.isWalking and player:isWalking() and time - lastFollowWalkAt < walkingCooldown then return true end
  precision = precision or 0

  if CaveBot and CaveBot.walkTo then
    local ok, walking = pcall(function()
      return CaveBot.walkTo(pos, maxDist or 50, {
        ignoreFields = settings.followIgnoreFields == true,
        ignoreNonPathable = true,
        precision = precision,
        ignoreStairs = false,
        allowUnseen = true,
        allowOnlyVisibleTiles = false
      })
    end)
    if ok and walking then
      lastFollowWalkAt = time
      return true
    end
  end

  if type(autoWalk) == "function" then
    local ok, result = pcall(function()
      return autoWalk(pos, maxDist or 50, {
        ignoreFields = settings.followIgnoreFields == true,
        ignoreNonPathable = true,
        precision = precision,
        ignoreStairs = false
      })
    end)
    if ok and (result~=false and result~=nil or player.isWalking and player:isWalking()) then
      lastFollowWalkAt = time
      return true
    end
  end

  -- Never fall through to LocalPlayer:autoWalk: it bypasses the bot's
  -- distance bound and may synchronously search all the way to another city.
  return false
end

-- Persistent recovery uses fresh Navi coordinates, not Exiva estimates.
dofile("/vBot/follow_route.lua")
local followRoutePlanner=ComboFollowRoutePlanner
dofile('/vBot/follow_travel.lua')
local followTravel=ComboFollowTravel
followSearch={pollAt=0,nextWalk=0,failures=0}
stopFollowSearch=function(cancelQueuedWalk)
  local owned=followSearch.active;followSearch.active=false;followSearch.goal=nil;followSearch.leg=nil;followSearch.job=nil;followSearch.path=nil;followSearch.journey=nil
  followSearch.prefetch=nil
  local movement=TargetBot and TargetBot.Movement
  local safety=TargetBot and TargetBot.Antitrap
  if owned and not (movement and movement.isManual and movement.isManual()) and
    not (safety and safety.ownsMovement and safety.ownsMovement()) and
    not (CaveBot and CaveBot.Flee and CaveBot.Flee.blocksCombat()) and
    (cancelQueuedWalk or player and player.isWalking and player:isWalking()) and g_game and g_game.stop then pcall(g_game.stop) end
end
local function validFollowPosition(pos)
  if type(pos)~='table' then return nil end
  local x,y,z=tonumber(pos.x),tonumber(pos.y),tonumber(pos.z)
  if not x or not y or not z or x~=x or y~=y or z~=z or x%1~=0 or y%1~=0 or z%1~=0 or
    x<0 or x>65535 or y<0 or y>65535 or z<0 or z>15 then return nil end
  return {x=x,y=y,z=z}
end
local function freshFollowRoute(route,time)
  if type(route)~='table' then return nil end
  local pos=validFollowPosition(route.pos)
  -- Older Navi snapshots carry only lastSeen; never replace an existing
  -- position timestamp with a newer presence/list timestamp.
  local at=tonumber(route.positionSeenAt)
  if route.positionSeenAt==nil then at=tonumber(route.lastSeen) end
  local age=at and time-at
  if not pos or not age or age~=age or age<0 or age>90000 then return nil end
  local trail={}
  if type(route.trail)=='table' and #route.trail<=48 then
    for i=1,#route.trail do
      local p=validFollowPosition(route.trail[i]);if not p then trail={};break end
      trail[#trail+1]=p
    end
  end
  local links={}
  if type(route.links)=='table' and #route.links<=32 then
    for _,edge in ipairs(route.links)do
      local a=type(edge)=='table' and validFollowPosition(edge.from)
      local b=type(edge)=='table' and validFollowPosition(edge.to)
      if a and b and a.z~=b.z and math.max(math.abs(a.x-b.x),math.abs(a.y-b.y))<=8 then
        links[#links+1]={from=a,to=b}
      end
    end
  end
  local jump
  if type(route.jump)=='table' then
    local a,b=validFollowPosition(route.jump.from),validFollowPosition(route.jump.to)
    if a and b and math.max(math.abs(a.x-b.x),math.abs(a.y-b.y))>8 then
      jump={from=a,to=b}
      local at,sequence=route.jump.at,route.jump.sequence
      if type(at)=='number' and time>=at and time-at<=followTravel.maxAge and type(sequence)=='number' then
        jump.at=at;jump.sequence=sequence
      end
    end
  end
  return {pos=pos,trail=trail,links=links,jump=jump,positionSeenAt=at}
end
local function readFollowNavi(name,time)
  local socket=BotServer and BotServer._websocket
  local enabled=not storage.BOTserver or storage.BOTserver.enabled~=false
  local status
  if BotServer and type(BotServer.getFollowStatus)=='function' then
    local ok,value=pcall(BotServer.getFollowStatus,name)
    if ok and type(value)=='table' then status=value;enabled=value.enabled==true end
  end
  if followSearch.name~=lower(name) or followSearch.socket~=socket then
    followTravel.cancel(followSearch.transport,CaveBot)
    stopFollowSearch()
    followSearch={name=lower(name),socket=socket,pollAt=0,nextWalk=0,failures=0}
  end
  local reason
  if not enabled then reason='Navi apagado: activalo para buscar'
  elseif not socket or status and not status.connected then reason='Navi desconectado: esperando conexion'
  elseif status and status.selfTarget then reason='Follow: elige otro jugador' end
  if reason then
    followTravel.cancel(followSearch.transport,CaveBot)
    if followSearch.source=='navi' or followSearch.source=='boat' then stopFollowSearch(true) end
    followSearch.route=nil;followSearch.reason=reason;return nil
  end
  if type(BotServer.requestFollowRoute)=='function' then pcall(BotServer.requestFollowRoute,name) end
  if time<followSearch.pollAt then return followSearch.route end
  followSearch.pollAt=time+250;followSearch.route=nil
  if type(BotServer.getMemberFollowRoute)=='function' then
    local ok,route=pcall(BotServer.getMemberFollowRoute,name)
    if ok then followSearch.route=freshFollowRoute(route,time) end
  end
  -- A present API can return nil, throw, or still be waiting for its optional
  -- listeners. The normal Navi snapshot remains an independent position source.
  if not followSearch.route and type(BotServer.getMemberSnapshot)=='function' then
    local ok,snapshot=pcall(BotServer.getMemberSnapshot)
    if ok and type(snapshot)=='table' then
      for who,info in pairs(snapshot)do
        if type(who)=='string' and lower(who)==lower(name) then
          followSearch.route=freshFollowRoute(info,time)
          if followSearch.route then break end
        end
      end
    end
  end
  if not followSearch.route then
    followTravel.cancel(followSearch.transport,CaveBot)
    if followSearch.source=='navi' or followSearch.source=='boat' then stopFollowSearch(true) end
    followSearch.reason='Navi: '..name..' sin posicion reciente'
    return nil
  end
  followSearch.reason=nil
  return followSearch.route
end

local function safeFollowDetour(pos)
  local tile=g_map.getTile(pos)
  if not tile or not tile:isWalkable(false) then return false end
  local movement=TargetBot and TargetBot.Movement
  if not movement or not movement.floorSafe or not movement.floorSafe(pos,tile) then return false end
  if settings.followIgnoreFields~=true and movement.isDamageField and tile.getItems then
    for _,item in ipairs(tile:getItems() or {}) do
      if movement.isDamageField(item) then return false end
    end
  end
  return true
end

local function queryFollowPath(time,cardinalOnly,from,to,limit,near)
  if type(getPath)~='function' then return nil end
  followSearch.queryAt=time+75
  local ignoreFields=settings.followIgnoreFields==true
  local path=getPath(from,to,limit,{precision=near,ignoreFields=ignoreFields,
    ignoreNonPathable=not cardinalOnly or ignoreFields,ignoreStairs=false,
    allowUnseen=not cardinalOnly,allowOnlyVisibleTiles=false})
  if cardinalOnly then return followRoutePlanner.cardinalPath(from,path,safeFollowDetour) end
  return path
end

local function queryFollowArea(time,cardinalOnly,from,limit)
  followSearch.queryAt=time+75
  local ignoreFields=settings.followIgnoreFields==true
  return findAllPaths(from,limit,{ignoreFields=ignoreFields,ignoreNonPathable=not cardinalOnly or ignoreFields,
    ignoreStairs=false,allowUnseen=not cardinalOnly,allowOnlyVisibleTiles=false})
end

-- Route searches run in short bursts: up to 4 path queries per tick while
-- they take less than 4 ms in total (it used to be one query every 75 ms).
-- os.clock advances inside a tick; g_clock.millis is fixed for the whole
-- frame, so it can never end a burst (that caused freezes of 100-300 ms).
local FOLLOW_PLAN_BUDGET_MS,FOLLOW_PLAN_STEPS=4,4
local followPlanClock=type(os)=='table' and type(os.clock)=='function' and function() return os.clock()*1000 end or nil
local function advanceFollowPlan(job,time)
  if time<(followSearch.queryAt or 0) then return nil,'planning' end
  local query=function(...) return queryFollowPath(time,job.cardinalOnly,...) end
  local flood=type(findAllPaths)=='function' and function(...) return queryFollowArea(time,job.cardinalOnly,...) end or nil
  return followRoutePlanner.advanceWithin(function() return followRoutePlanner.advance(job,time,query,flood) end,
    job,followPlanClock,FOLLOW_PLAN_BUDGET_MS,FOLLOW_PLAN_STEPS)
end

local function usableFollowPrefetch(job,from,goal,precision)
  if not job or job.precision~=precision or not samePosition(job.from,from) then return false end
  local old=job.goal
  return samePosition(old,goal) or distanceBetween(old,goal)<=12 and distanceBetween(from,old)>precision and
    (old.x-from.x)*(goal.x-from.x)+(old.y-from.y)*(goal.y-from.y)>0
end

local function walkFollowMap(goal,precision,time,source,trail)
  local origin=getPlayerPosition()
  if not origin or not goal or origin.z~=goal.z then return false end
  source=source or 'seen'
  local cardinalOnly=source=='navi' and followSearch.cardinalOnly
  if followSearch.source~=source then
    stopFollowSearch();followSearch.nextWalk=0;followSearch.failures=0;followSearch.source=source
  end
  if followSearch.leg and followSearch.leg.z~=origin.z then
    followSearch.leg=nil;followSearch.path=nil;followSearch.job=nil;followSearch.prefetch=nil;followSearch.nextWalk=0
  end
  if distanceBetween(origin,goal)<=precision then return true end
  local currentGoal=goal
  if followSearch.leg and samePosition(followSearch.leg,origin) then
    local ready=followSearch.prefetch
    followSearch.leg=nil;followSearch.prefetch=nil;followSearch.nextWalk=0
    if not followSearch.path and usableFollowPrefetch(ready,origin,goal,precision) then
      followSearch.goal=copyPosition(ready.goal)
      if ready.path then followSearch.path=ready.path;followSearch.index=1
      elseif not ready.done then followSearch.job=ready
      else followSearch.unreachable={from=copyPosition(origin),goal=copyPosition(ready.goal),at=time} end
    end
  end
  local changed=not followSearch.goal or followSearch.goal.z~=goal.z or distanceBetween(goal,followSearch.goal)>3
  local committed=followSearch.job or followSearch.path or followSearch.leg and distanceBetween(origin,followSearch.leg)>0
  if committed and followSearch.goal and followSearch.goal.z==goal.z and distanceBetween(origin,followSearch.goal)>precision then
    local old,new=followSearch.goal,goal
    if (old.x-origin.x)*(new.x-origin.x)+(old.y-origin.y)*(new.y-origin.y)>0 then
      goal=old;changed=false -- Finish a useful checkpoint before chasing newer Navi coordinates.
    end
  end
  if changed then
    followSearch.job=nil;followSearch.path=nil;followSearch.nextWalk=0
    followSearch.goal=copyPosition(goal)
  end
  local inLeg=followSearch.leg and distanceBetween(origin,followSearch.leg)>0
  local grace=math.max(800,player and player.getStepDuration and player:getStepDuration()*3 or 0)
  if inLeg and time-math.max(lastFollowProgressAt,followSearch.sentAt or 0)<grace then
    -- Plan from the queued endpoint, then adopt that plan only after reaching it.
    local endpoint=followSearch.leg
    if source=='navi' and not followSearch.path and distanceBetween(endpoint,currentGoal)>precision then
      if not usableFollowPrefetch(followSearch.prefetch,endpoint,currentGoal,precision) then
        followSearch.prefetch=followRoutePlanner.new(endpoint,currentGoal,precision,trail,cardinalOnly)
      end
      if not followSearch.prefetch.done then advanceFollowPlan(followSearch.prefetch,time) end
    end
    return true
  end
  if time<followSearch.nextWalk then return followSearch.failures==0 end
  if inLeg then
    -- The packet was accepted but no position changed. Discard that route;
    -- a fresh query sees doors/creatures that have changed since the request.
    followSearch.path=nil;followSearch.job=nil;followSearch.prefetch=nil;followSearch.stalls=(followSearch.stalls or 0)+1
    if followSearch.active and g_game and g_game.stop then pcall(g_game.stop) end
    followSearch.active=false
  end
  followSearch.leg=nil
  if not followSearch.path then
    if not followSearch.job or not samePosition(followSearch.job.from,origin) or followSearch.job.precision~=precision then
      followSearch.job=followRoutePlanner.new(origin,goal,precision,trail,cardinalOnly)
    end
    local path,state=advanceFollowPlan(followSearch.job,time)
    if state=='planning' then setFollowStatus('Calculando ruta de Follow por tramos');return true end
    followSearch.job=nil
    if state=='failed'then followSearch.unreachable={from=copyPosition(origin),goal=copyPosition(goal),at=time}end
    if path then followSearch.path=path;followSearch.index=1 end
  end
  local path=followSearch.path;local sent=false
  if path then
    local offsets={{0,-1},{1,0},{0,1},{-1,0},{1,-1},{1,1},{-1,1},{-1,-1}}
    local chunk,finish={},copyPosition(origin)
    local index=followSearch.index or 1
    local arrived=false
    for i=index,math.min(index+23,#path)do
      local dir=path[i];local offset=type(dir)=='number' and (not cardinalOnly or dir<4) and offsets[dir+1]
      if not offset then chunk={};break end
      chunk[#chunk+1]=dir;finish.x=finish.x+offset[1];finish.y=finish.y+offset[2]
      if distanceBetween(finish,currentGoal)<=precision then arrived=true;break end
    end
    if #chunk>0 then
      if CaveBot and CaveBot.protectStep and not CaveBot.protectStep(chunk[1]) then return true end
      if getFollowingCreature() and g_game and g_game.cancelFollow then pcall(g_game.cancelFollow) end
      local walker=type(autoWalk)=='function' and autoWalk or g_game and g_game.autoWalk
      if type(walker)=='function' then
        local accepted,result
        if walker==autoWalk then accepted,result=pcall(walker,chunk)
        else accepted,result=pcall(walker,chunk,{x=0,y=0,z=0}) end
        sent=accepted and result~=false
      end
      if sent then
        followSearch.leg=finish;followSearch.prefetch=nil;followSearch.index=index+#chunk;followSearch.sentAt=time
        if arrived or followSearch.index>#path then followSearch.path=nil end
      end
    end
  end
  followSearch.nextWalk=time+100
  if sent then
    lastFollowWalkAt=time;followSearch.failures=0;followSearch.active=true;return true
  end
  followSearch.path=nil;followSearch.failures=math.min(4,followSearch.failures+1)
  followSearch.nextWalk=time+math.min(1500,250*2^(followSearch.failures-1))
  return false
end
local function crossFollowFloor(goal,arrival,time,inferred,returning)
  local origin=getPlayerPosition()
  if not hasPosition(origin) or origin.z~=goal.z or not g_map or not g_map.getTile then return false end
  local search=followSearch.crossing
  if not search or not samePosition(search.goal,goal) or search.returning~=returning or time>=search.expires then
    search={goal=copyPosition(goal),returning=returning,tried={},used={},expires=time+FOLLOW_TRANSITION_TTL_MS}
    followSearch.crossing=search
  end
  if search.pending then
    if time<search.pending.untilAt and samePosition(origin,search.pending.from) then return true end
    search.pending=nil
  end
  if time-lastFollowWalkAt<120 then return not inferred end
  if time<(search.nextAt or 0) then return search.handled==true end
  search.nextAt=time+120
  search.handled=false
  local candidates,seen={},{}
  local projected=arrival and {x=arrival.x,y=arrival.y,z=origin.z}
  local explorer=CaveBot and CaveBot.AutoExplorer
  local originTile=origin.z>0 and (not arrival or arrival.z==origin.z-1) and g_map.getTile(origin)
  local elevated=originTile and originTile.hasElevation and originTile:hasElevation(3)
  local function mapMarked(pos)
    local color=g_map.getMinimapColor and tonumber(g_map.getMinimapColor(pos)) or 0
    return color>=210 and color<=213
  end
  local function add(pos)
    if pos.x<0 or pos.x>65535 or pos.y<0 or pos.y>65535 then return end
    local key=getPositionKey(pos)
    local distance=distanceBetween(origin,pos)
    if seen[key] or distance>(returning and 3 or 2) then return end
    seen[key]=true
    local tile=g_map.getTile(pos)
    local ground=tile and tile.getGround and tile:getGround()
    local floorTile=tile and tile.hasElevation and tile:hasElevation(3)
    local liveColor=tile and tile.getMinimapColorByte and tonumber(tile:getMinimapColorByte()) or 0
    local marked=floorTile or (liveColor>=210 and liveColor<=213) or mapMarked(pos)
    if tile and not marked then
      for _,method in ipairs({'isFloorChange','isFloorChangeUp','isFloorChangeDown'})do
        if type(tile[method])=='function' and tile[method](tile) then marked=true;break end
      end
    end
    -- Next Gen's manual walk detects a drop from the raised tile below the
    -- step, even when the upper square has no ground or no map tile.
    local drop,rise
    if not tile or tile.getGround and not ground or tile.isWalkable and not tile:isWalkable(false) then
      if origin.z<15 and (not arrival or arrival.z==origin.z+1) then
        local below=g_map.getTile({x=pos.x,y=pos.y,z=origin.z+1})
        drop=below and below.hasElevation and below:hasElevation(3)
      end
      if elevated and distance==1 then
        local above=g_map.getTile({x=pos.x,y=pos.y,z=origin.z-1})
        rise=above and above.isWalkable and above:isWalkable()
      end
    end
    local known=tile and explorer and explorer.getFloorChangeThing and explorer.getFloorChangeThing(tile)
    local exact=projected and samePosition(pos,projected)
    local isGoal=samePosition(pos,goal)
    local rank=(drop or rise) and (exact and 1 or 3) or known and (exact and 2 or 4) or marked and 5 or
      not inferred and exact and 6 or not inferred and isGoal and 7
    if rank then candidates[#candidates+1]={pos=pos,tile=tile,marked=marked,known=known,key=key,rank=rank,distance=distance} end
  end
  if projected then add(projected) end
  add(goal)
  local radius=returning and 2 or 1
  for dx=-radius,radius do for dy=-radius,radius do add({x=goal.x+dx,y=goal.y+dy,z=goal.z})end end
  table.sort(candidates,function(a,b)
    if a.rank~=b.rank then return a.rank<b.rank end
    if a.distance~=b.distance then return a.distance<b.distance end
    return a.key<b.key
  end)
  local wait=math.max(350,player and player.getStepDuration and player:getStepDuration()*2 or 0)
  local function attempt(action,...)
    search.pending={from=origin,untilAt=time+wait,floor=arrival and arrival.z}
    if action(...) then return true end
    search.pending=nil
    return false
  end
  local underfoot
  for _,entry in ipairs(candidates)do
    local tile=entry.tile
    if entry.distance<=1 then
      local blocked=tile and tile.isWalkable and not tile:isWalkable(false)
      local uses=search.used[entry.key] or 0
      if tile and (entry.known or entry.marked and (entry.distance==0 or blocked)) and
        uses<(entry.known and 2 or 1) and time-lastFollowUseAt>=120 then
        search.used[entry.key]=uses+1
        if attempt(tryUseFollowTransition,entry.pos,true,true,tile) then return true end
      end
      local attempts=search.tried[entry.key] or 0
      if entry.distance==1 and attempts<2 then
        search.tried[entry.key]=attempts+1
        if attempt(stepIntoFollowPosition,entry.pos) then return true end
      end
      if returning and entry.distance==0 and entry.marked and not blocked then underfoot=entry end
    elseif (not inferred or returning) and (search.tried[entry.key] or 0)<2 and
      walkFollowMap(entry.pos,1,time,followSearch.source=='navi' and 'navi' or 'stairs') then
      search.handled=true
      return true
    end
  end
  if underfoot and not search.steppedOff then
    search.steppedOff=true
    for _,offset in ipairs({{0,-1},{1,0},{0,1},{-1,0},{1,-1},{1,1},{-1,1},{-1,-1}}) do
      local nextPos={x=origin.x+offset[1],y=origin.y+offset[2],z=origin.z}
      if safeFollowDetour(nextPos) and attempt(stepIntoFollowPosition,nextPos) then return true end
    end
  end
  if inferred then return false end
  if not search.used.fallback then
    search.used.fallback=true
    if attempt(tryUseFollowTransition,goal,true,true) then return true end
  end
  return false
end

local function returnFollowFloor(name,origin,time)
  local entry=followFloorReturns[#followFloorReturns]
  if not entry or entry.goal.z~=origin.z or time<(entry.retryAt or entry.at+300) then return false end
  local route=readFollowNavi(name,time)
  if route and route.pos.z==origin.z and (route.positionSeenAt or 0)>=entry.at then
    followFloorReturns={}
    return false
  end
  setFollowStatus('Follow: regresando por el ultimo acceso de piso')
  local distance=distanceBetween(origin,entry.goal)
  if distance<=3 and crossFollowFloor(entry.goal,entry.arrival,time,true,true) then return true end
  if distance>1 and walkFollowMap(entry.goal,1,time,'stairs') then return true end
  entry.retryAt=time+1500
  followSearch.crossing=nil
  return false
end

local function floorLinks(route)
  if #route.links>0 then return route.links end
  local links={}
  for i=1,#route.trail-1 do
    local a,b=route.trail[i],route.trail[i+1]
    if a.z~=b.z and math.max(math.abs(a.x-b.x),math.abs(a.y-b.y))<=2 then
      links[#links+1]={from=a,to=b}
      if #links>32 then table.remove(links,1)end
    end
  end
  return links
end
local function seekFollowJourney(route,origin,time)
  local journey=followSearch.journey
  if journey and (route.pos.z~=journey.goal.z or distanceBetween(route.pos,journey.goal)>64)then
    followSearch.journey=nil;journey=nil
  end
  if not journey then
    local links=floorLinks(route)
    local failed=followSearch.unreachable
    local directFailed=failed and time-failed.at<=5000 and samePosition(origin,failed.from)and
      failed.goal.z==route.pos.z and distanceBetween(failed.goal,route.pos)<=3
    local job=followSearch.job
    directFailed=directFailed or job and job.directTried and job.phase=='graph' and
      samePosition(origin,job.from) and distanceBetween(job.goal,route.pos)<=3
    if not directFailed or time<(followSearch.nextJourney or 0)or origin.z~=route.pos.z or
      distanceBetween(origin,route.pos)<=configuredFollowDistance() or
      not followRoutePlanner.hasFloorReturn(links,origin.z)then return false end
    if followSearch.active and followSearch.leg and followSearch.leg.z==origin.z then
      local remaining=distanceBetween(origin,followSearch.leg)
      local grace=math.max(800,player and player.getStepDuration and player:getStepDuration()*3 or 0)
      if remaining==0 and (followSearch.path or followSearch.prefetch) or remaining>0 and
        time-math.max(lastFollowProgressAt,followSearch.sentAt or 0)<grace then return false end
    end
    stopFollowSearch();followSearch.source='navi'
    local blocked={}
    for k,untilAt in pairs(followSearch.blockedFloors or{})do
      if untilAt>time then blocked[k]=true else followSearch.blockedFloors[k]=nil end
    end
    journey={job=followRoutePlanner.newJourney(origin,route.pos,links,blocked,directFailed,followSearch.cardinalOnly),
      goal=copyPosition(route.pos),index=1}
    followSearch.journey=journey
    followSearch.job=nil;followSearch.path=nil
    if g_game and g_game.cancelFollow then pcall(g_game.cancelFollow)end
  end
  if not journey.steps then
    setFollowStatus('Follow: calculando accesos entre zonas')
    if time<(followSearch.queryAt or 0)then return true end
    local job=journey.job
    local query=function(...) return queryFollowPath(time,job.cardinalOnly,...) end
    local flood=type(findAllPaths)=='function' and function(...) return queryFollowArea(time,job.cardinalOnly,...) end or nil
    local steps,state=followRoutePlanner.advanceWithin(function() return followRoutePlanner.advanceJourney(job,time,query,flood) end,
      job,followPlanClock,FOLLOW_PLAN_BUDGET_MS,FOLLOW_PLAN_STEPS)
    if state=='planning'then return true end
    if not steps then
      followSearch.journey=nil;followSearch.nextJourney=time+1500;return false
    end
    journey.steps=steps;journey.job=nil
  end
  for _=1,8 do
    local step=journey.steps[journey.index]
    if not step then
      followSearch.journey=nil;followSearch.nextJourney=time+500;return false
    end
    if step.kind=='floor'then
      if origin.z==step.to.z and distanceBetween(origin,step.to)<=3 then
        journey.index=journey.index+1;journey.crossAt=nil
        followSearch.leg=nil;followSearch.path=nil;followSearch.job=nil;followSearch.prefetch=nil;followSearch.nextWalk=0
      elseif origin.z~=step.from.z then
        followSearch.journey=nil;return false
      else
        setFollowStatus('Follow: acceso piso '..step.from.z..' -> '..step.to.z)
        if distanceBetween(origin,step.from)>1 then walkFollowMap(step.from,1,time,'navi');return true end
        journey.crossAt=journey.crossAt or time
        if time-journey.crossAt>5000 then
          followSearch.blockedFloors=followSearch.blockedFloors or{}
          followSearch.blockedFloors[step.key]=time+10000
          followSearch.journey=nil;followSearch.nextJourney=time+250;return true
        end
        crossFollowFloor(step.from,step.to,time);return true
      end
    elseif origin.z~=step.to.z then
      followSearch.journey=nil;return false
    else
      local final=journey.index==#journey.steps
      local goal=final and route.pos or step.to
      local precision=final and configuredFollowDistance() or 1
      if distanceBetween(origin,goal)<=precision then
        journey.index=journey.index+1
      else
        if not step.started then
          step.started=true;followSearch.goal=copyPosition(goal)
          followSearch.leg=nil;followSearch.job=nil;followSearch.path=nil;followSearch.prefetch=nil;followSearch.nextWalk=0
          if samePosition(goal,step.to) and samePosition(origin,step.from) then followSearch.path=step.path;followSearch.index=1 end
        end
        setFollowStatus('Follow: caminando hacia acceso / destino')
        if not walkFollowMap(goal,precision,time,'navi',final and route.trail or nil)then setFollowStatus('Follow: tramo bloqueado, reintentando')end
        return true
      end
    end
  end
  return true
end
local function followBoat(transport,origin,time)
  if not settings.followBoat then
    stopFollowSearch(true)
    setFollowStatus('Leader viajo: activa Seguir viajes en barco')
    return true
  end
  local jump=transport.jump
  if not jump.sequence or not jump.at then
    stopFollowSearch(true)
    setFollowStatus('Leader viajo: Navi no confirmo un salto reciente')
    return true
  end
  if transport.attempted then
    if transport.revision and time<transport.deadline and CaveBot.IsNpcConversationCurrent(transport.revision) then
      setFollowStatus('Viajando a '..transport.trip.destination..': esperando llegada')
    else
      followTravel.cancel(transport,CaveBot)
      setFollowStatus('No se confirmo el viaje a '..transport.trip.destination)
    end
    return true
  end
  if not transport.lookup then transport.lookup=followTravel.begin(jump,Config) end
  if not transport.result then
    local trip,result=followTravel.advance(transport.lookup,Config)
    if result=='scanning' then setFollowStatus('Buscando viaje del leader en rutas CaveBot');return true end
    transport.trip,transport.result=trip,result
  end
  if not transport.trip then
    setFollowStatus(transport.result=='ambiguous' and 'Viaje ambiguo en rutas CaveBot' or 'Leader viajo: falta ruta Travel en CaveBot')
    return true
  end
  if origin.z~=jump.from.z or not CaveBot or type(CaveBot.Travel)~='function' then
    setFollowStatus('No se puede abordar el barco desde aqui')
    return true
  end
  local trip=transport.trip
  if not followTravel.near(origin,jump.from,3) or not followTravel.findNpc(trip.npc,origin,getSpectators()) then
    setFollowStatus('Buscando a '..trip.npc..' para viajar a '..trip.destination)
    walkFollowMap(jump.from,0,time,'boat')
    return true
  end
  stopFollowSearch(true)
  transport.attempted=true
  local ok,duration,revision=pcall(CaveBot.Travel,trip.destination)
  if ok and type(revision)=='number' then
    transport.revision=revision
    transport.deadline=time+(tonumber(duration) or 3000)+5000
    setFollowStatus('Viajando a '..trip.destination..': esperando llegada')
  else
    setFollowStatus('No se pudo iniciar el viaje a '..trip.destination)
  end
  return true
end

local function seekFollowNavi(name,time,accessOnly,visiblePos,outOfSight)
  local route=readFollowNavi(name,time)
  if not route then return false end
  local origin=getPlayerPosition();if not origin then return false end
  if visiblePos and visiblePos.z==origin.z and distanceBetween(origin,visiblePos)<=32 then
    route={pos=copyPosition(visiblePos),links=route.links,trail=route.trail,jump=route.jump,positionSeenAt=time}
  end
  if accessOnly and not followSearch.journey and not followRoutePlanner.hasFloorReturn(floorLinks(route),origin.z)then return false end
  local goal,transition,arrival=route.pos,false,nil
  local jump=route.jump
  local previous=followSearch.lastNaviPosition or lastFollowPosition
  if not jump and previous and previous.z==origin.z and route.pos.z==previous.z and
    distanceBetween(previous,route.pos)>128 and distanceBetween(origin,previous)<=32 then
    jump={from=previous,to=route.pos}
  end
  followSearch.lastNaviPosition=copyPosition(route.pos)
  local transport=followSearch.transport
  if transport then
    local prior=transport.jump
    if followTravel.near(origin,prior.to,16) or followTravel.near(origin,route.pos,32) or
        time>=transport.expires then
      followTravel.cancel(transport,CaveBot)
      followSearch.finishedJump=prior
      followSearch.transport=nil;transport=nil
    end
  end
  if not transport and jump and followTravel.near(origin,jump.from,48) and not followTravel.near(route.pos,jump.from,32) and
      math.max(math.abs(jump.from.x-jump.to.x),math.abs(jump.from.y-jump.to.y))>(jump.sequence and 32 or 128) and
      not followTravel.sameJump(jump,followSearch.finishedJump) then
    stopFollowSearch(true)
    transport={jump=jump,expires=(jump.at or time)+followTravel.maxAge}
    followSearch.transport=transport
  end
  if transport and followBoat(transport,origin,time) then return true end
  -- A stale snapshot or one that repeats the last sighting cannot confirm
  -- that we have caught up. Approach the last sighting at stair precision.
  if outOfSight and not visiblePos and lastFollowPosition and route.pos.z==origin.z and lastFollowPosition.z==origin.z and
    time-lastFollowSeenAt<=FOLLOW_TRANSITION_TTL_MS and
    (lastFollowSeenAt>(route.positionSeenAt or 0) or samePosition(route.pos,lastFollowPosition)) then return false end
  local gap=math.max(math.abs(origin.x-goal.x),math.abs(origin.y-goal.y))
  -- Keep a cardinal leg already in flight when crossing the distance threshold.
  local continuesCardinal=followSearch.cardinalOnly and followSearch.source=='navi' and
    (followSearch.path~=nil or followSearch.prefetch~=nil or followSearch.leg and
      followSearch.leg.z==origin.z and not samePosition(followSearch.leg,origin))
  local cardinalOnly=outOfSight==true and configuredFollowDistance()>1 and (gap>12 or continuesCardinal==true)
  if followSearch.cardinalOnly~=cardinalOnly then
    if followSearch.cardinalOnly~=nil then
      stopFollowSearch(true)
      followSearch.nextWalk=0;followSearch.failures=0;followSearch.unreachable=nil
    end
    followSearch.cardinalOnly=cardinalOnly
  end
  if seekFollowJourney(route,origin,time)then return true end
  if goal.z~=origin.z then
    goal=nil
    -- Use the last departure from this floor. Choosing the closest old exit
    -- can bounce forever on a hunt that revisits a floor before going deeper.
    for i=#route.trail-1,1,-1 do
      local p,q=route.trail[i],route.trail[i+1]
      if p.z==origin.z and q.z~=p.z and math.max(math.abs(p.x-q.x),math.abs(p.y-q.y))<=2 then
        goal=p;transition=true;arrival=q;break
      end
    end
    if not goal then
      -- Floor links are retained separately from the short movement trail.
      -- Take the latest departure with a forward chain to the leader's floor.
      for i=#route.links,1,-1 do
        local edge=route.links[i]
        if edge.from.z==origin.z then
          local floor=edge.to.z
          for j=i+1,#route.links do if route.links[j].from.z==floor then floor=route.links[j].to.z end end
          if floor==route.pos.z then goal=edge.from;transition=true;arrival=edge.to;break end
        end
      end
    end
    if not goal then return false end
  end
  setFollowStatus(transition and 'Buscando por Navi: cambio de piso' or 'Buscando por Navi: '..goal.x..','..goal.y..','..goal.z)
  local distance=distanceBetween(origin,goal)
  if transition and distance<=1 then
    -- Ladders/rope spots often cannot be entered by walking. Use their known
    -- action before retrying a step that would otherwise mask it forever.
    return crossFollowFloor(goal,arrival,time)
  end
  local precision=transition and 1 or configuredFollowDistance()
  if not walkFollowMap(goal,precision,time,'navi',not transition and route.trail or nil) then
    setFollowStatus('Sin ruta a Navi: reintentando')
  elseif not transition and distance<=precision then
    stopFollowSearch(true)
    setFollowStatus('En posicion Navi: esperando al jugador')
  end
  return true
end
do
  local pending=false
  followCombat.onNaviRoute=function(name)
    if not settings.enabled or not settings.followEnabled or lower(name)~=lower(getFollowName()) then return end
    followSearch.pollAt=0
    if pending then return end
    pending=true
    schedule(1,function()pending=false;chaseFollowName()end)
  end
end

local function isRecentFollowTransition(pos, time)
  return hasPosition(pos) and lastFollowTransitionPosition and
    samePosition(pos, lastFollowTransitionPosition) and
    time - lastFollowTransitionAt <= FOLLOW_TRANSITION_TTL_MS
end

local function recoverFollowPath(pos, distance, urgent)
  if not hasPosition(pos) then return false end
  local time = getTime()
  local stuckFor = time - lastFollowProgressAt
  local recoveryDelay = urgent and FOLLOW_TRANSITION_RECOVERY_MS or FOLLOW_STUCK_RECOVERY_MS
  if stuckFor < recoveryDelay then return false end

  local retryCooldown = urgent and 120 or 300
  if time - lastFollowRecoveryAt < retryCooldown then return false end
  lastFollowRecoveryAt = time

  if g_game and g_game.cancelFollow then
    pcall(function() g_game.cancelFollow() end)
  end

  if distance > 1 and walkToFollowPosition(pos, urgent and 0 or 1) then return true end
  if distance <= 1 and stepIntoFollowPosition(pos) then return true end
  if distance <= 2 and tryUseFollowTransition(pos, urgent) then return true end
  if distance > 1 then return walkToFollowPosition(pos, 0) end
  return false
end

local function followVisibleTarget(creature, name)
  if not creature then return false end
  local targetPos = copyPosition(creature:getPosition())
  local playerPos = getPlayerPosition()
  local followDistance = distanceBetween(playerPos, targetPos)
  if followDistance>32 then return false end
  local time = getTime()
  rememberFollowPosition(targetPos)
  lastFollowTransitionPosition = nil
  lastFollowTransitionArrival = nil
  followFloorReturns={}
  followSearch.crossing=nil

  lastFollowSeenAt = time
  followFreedAfterLost = false

  local combat=followCombat.getState()
  if combat.active and combat.ready and combat.borrowed then
    stopFollowSearch(true);stopDistanceFollow()
    local onAxis=playerPos and (playerPos.x==targetPos.x or playerPos.y==targetPos.y)
    setFollowStatus(combat.cross and (onAxis and 'En cruz con el leader' or 'Leader quieto: casilla del wave') or
      'Leader quieto: posicion de ataque');return true
  end
  local desired=configuredFollowDistance()
  local recovering=followSearch.journey or followSearch.source=='navi' and
    (followSearch.job or followSearch.path or followSearch.leg)
  local function recoverViaNavi()
    local observed=findFollowCreature(true)
    return seekFollowNavi(name,time,false,observed and observed:getPosition())
  end
  if spacing.desired~=desired or time<(spacing.leaderMovedAt or 0) then spacing={desired=desired} end
  if desired>1 then
    if getFollowingCreature() and g_game and g_game.cancelFollow then pcall(g_game.cancelFollow) end
    if not samePosition(spacing.leader,targetPos) then
      spacing.leader=targetPos;spacing.leaderMovedAt=time;spacing.waiting=nil
      if spacing.blockedAt then spacing.nextProbe=nil end
    end
    if spacing.pending and (not samePosition(playerPos,spacing.pending.from) or time>=spacing.pending.retryAt) then
      spacing.pending=nil
    end
    if followDistance==desired then
      stopFollowSearch(true);spacing.blockedAt=nil;spacing.waiting=nil
      setFollowStatus('Separacion: '..desired..' SQM');return true
    end
    -- A one-tile change as the leader passes should not trigger a retreat.
    if followDistance<desired and (time-spacing.leaderMovedAt<300 or creature.isWalking and creature:isWalking()) then
      stopFollowSearch(true);spacing.blockedAt=nil;spacing.waiting=nil
      setFollowStatus('Esperando al leader: '..followDistance..' SQM');return true
    end

    if spacing.pending then return true end
    local walking=player and player.isWalking and player:isWalking()
    local canWalk=player and type(player.canWalk)=='function' and player.canWalk
    if walking and not followSearch.active and not canWalk then return true end
    if spacing.nextProbe and time<spacing.nextProbe then
      if spacing.blockedAt and followDistance>desired and recovering then recoverViaNavi() end
      return true
    end
    local function stepReady(direction)
      if canWalk then
        local ok, allowed=pcall(canWalk,player,direction)
        if ok and type(allowed)=='boolean' then return allowed end
      end
      return not walking
    end
    local waiting=spacing.waiting
    if waiting and time<waiting.recheckAt and samePosition(waiting.from,playerPos) and not stepReady(waiting.direction) then return true end
    -- The client is ready. Recheck the tile and route before sending a step.
    spacing.waiting=nil
    local movement=TargetBot and TargetBot.Movement
    local ignoreFields=settings.followIgnoreFields==true
    local function safeTile(p)
      if p.x<0 or p.y<0 or p.x>65535 or p.y>65535 then return false end
      local tile=g_map.getTile(p)
      if not tile or not tile:isWalkable(false) then return false end
      if tile.getCreatures and #(tile:getCreatures() or {})>0 then return false end
      if not ignoreFields and movement and movement.isDamageField and tile.getItems then
        for _,item in ipairs(tile:getItems() or {}) do
          if movement.isDamageField(item) then return false end
        end
      end
      if movement and movement.floorSafe then return movement.floorSafe(p,tile) end
      local color=tonumber(g_map.getMinimapColor and g_map.getMinimapColor(p)) or 0
      return not (tile.hasElevation and tile:hasElevation(3)) and not (color>=210 and color<=213)
    end
    local function queryPath()
      if type(getPath)=='function' then
        -- Traps are tiles the client marks as not pathable; safeTile still rejects walls and creatures.
        return getPath(playerPos,targetPos,50,{precision=desired,ignoreFields=ignoreFields,
          ignoreNonPathable=ignoreFields,ignoreStairs=false,allowOnlyVisibleTiles=true})
      end
    end
    local direction=followRoutePlanner.spacingStep(playerPos,targetPos,desired,safeTile,queryPath)
    if direction==nil then
      spacing.nextProbe=time+100
      spacing.blockedAt=spacing.blockedAt or time
      if followDistance>desired and (recovering or time-spacing.blockedAt>=800) and recoverViaNavi() then return true end
      setFollowStatus('Sin camino seguro para '..desired..' SQM');return true
    end
    spacing.blockedAt=nil
    local wasRecovering=followSearch.active
    stopFollowSearch(true)
    if wasRecovering then return true end
    if not stepReady(direction) then
      spacing.waiting={from=copyPosition(playerPos),direction=direction,recheckAt=time+75}
      return true
    end
    if CaveBot and CaveBot.protectStep and not CaveBot.protectStep(direction) then
      spacing.nextProbe=time+75
      setFollowStatus('Pausa: paso protegido');return true
    end
    -- Position progress releases this guard. The timer only retries a step
    -- that was rejected or never produced a position change.
    local duration=player and player.getStepDuration and tonumber(player:getStepDuration(false,direction)) or 150
    spacing.pending={from=copyPosition(playerPos),retryAt=time+math.max(120,math.min(350,duration))}
    local sent=false
    if type(safeBotWalk)=='function' then sent=safeBotWalk(direction)~=false
    elseif g_game and g_game.walk then
      local ok,result=pcall(g_game.walk,direction,false)
      sent=ok and result~=false
    end
    if sent then setFollowStatus('Ajustando a '..desired..' SQM')
    else spacing.pending=nil;spacing.nextProbe=time+50 end
    return true
  end
  if followDistance<=1 then spacing.nativeGapAt=nil
  else
    spacing.nativeGapAt=spacing.nativeGapAt or time
    local stalled=time-math.max(lastFollowProgressAt,spacing.nativeGapAt)>=800
    if (recovering or stalled) and recoverViaNavi() then return true end
  end
  stopFollowSearch(true)
  setFollowStatus('Follow nativo: 1 SQM')

  followCreature(creature)

  if followDistance <= 1 then return true end

  if time - lastFollowWalkAt >= FOLLOW_STICKY_WALK_RETRY_MS then
    walkToFollowPosition(targetPos, 1)
  end

  local urgent = isRecentFollowTransition(targetPos, time)
  recoverFollowPath(targetPos, followDistance, urgent)
  return true
end

local function pauseFollowBoat()
  followTravel.cancel(followSearch.transport,CaveBot)
  if followSearch.source=='boat' then stopFollowSearch(true) end
end

do
  local function buyer()
    return CaveBot and CaveBot.Extensions and CaveBot.Extensions.BuySupplies
  end
  local function supplyNpc(visit)
    for _,actor in pairs(getSpectators(false) or {})do
      if actor:isNpc() and lower(actor:getName())==lower(visit.npc) and
        followTravel.near(actor:getPosition(),visit.pos,3) then return actor end
    end
  end

  function restock.clear(keepQueue)
    local api=buyer()
    if restock.active then
      if api then api.cancelFollowVisit() end
      stopFollowSearch(true)
      followSearch.pollAt=0
      followSearch.nextWalk=0
      lastFollowSeenAt=0
    end
    restock.active=nil
    if not keepQueue and #restock.queue>0 then restock.queue={} end
  end

  function followCombat.onSupplyVisit(sender,message)
    if not settings.enabled or not settings.followEnabled or settings.followSupplies==false or
      type(sender)~='string' or lower(sender)~=lower(getFollowName()) or
      type(message)~='table' or message.v~=1 or type(message.id)~='string' or
      #message.id>64 or not message.id:match('^%d+:%d+:%d+$') or
      type(message.npc)~='string' or #message.npc>64 or
      not message.npc:match("^[%w %.'%-]+$") or not message.npc:find('%w') then return end
    local position=validFollowPosition(message.pos)
    local origin=getPlayerPosition()
    if not position or not origin or math.max(math.abs(origin.x-position.x),math.abs(origin.y-position.y))>32 then return end
    local time=getTime()
    local id=lower(sender)..':'..message.id
    if restock.seen[id] or #restock.queue>=4 then return end
    restock.seen[id]=true
    restock.seenIds[#restock.seenIds+1]=id
    if #restock.seenIds>32 then restock.seen[table.remove(restock.seenIds,1)]=nil end
    local shop=(message.shop=='potions' or message.shop=='runes') and message.shop or nil
    restock.queue[#restock.queue+1]={leader=lower(sender),socket=BotServer._websocket,shop=shop,
      npc=message.npc,pos=position,expires=time+25000,nextAt=0}
  end

  function restock.tick(name,origin,time)
    local api=buyer()
    local visit=restock.active or restock.queue[1]
    if not visit or not api or not api.beginFollowVisit or not Supplies or not Supplies.getItemsData then return false end
    local safety=TargetBot and TargetBot.Antitrap
    local blocked=safety and safety.ownsMovement and safety.ownsMovement() or
      PushMax and PushMax.ownsMovement and PushMax.ownsMovement()
    if blocked or visit.leader~=lower(name) or not BotServer or visit.socket~=BotServer._websocket or
      not origin or time>=visit.expires or
      (restock.active and origin.z~=visit.pos.z) then
      if restock.active then restock.clear(not blocked) else table.remove(restock.queue,1) end
      return false
    end
    if time<visit.nextAt then return restock.active~=nil end
    visit.nextAt=time+250
    -- Keep the leader's route current while the follower is occupied at the shop.
    if restock.active and BotServer.requestFollowRoute then pcall(BotServer.requestFollowRoute,name) end
    if not restock.active then
      if followSearch.transport or origin.z~=visit.pos.z then return false end
      local action=CaveBot.isOn and CaveBot.isOn() and CaveBot.actionList and CaveBot.actionList:getFocusedChild()
      if action and (action.action=='buysupplies' or action.action=='sellall' or action.action=='travel' or action.action=='bank') then
        return false
      end
      table.remove(restock.queue,1)
      local configured=false
      for _,supply in pairs(Supplies.getItemsData())do
        if (tonumber(supply.max)or 0)>0 then configured=true;break end
      end
      if not configured then return false end
      restock.active=visit
      visit.expires=time+180000
      visit.approachUntil=time+20000
      stopFollowSearch(true)
      stopDistanceFollow()
      followCombat.invalidate(true)
      if g_game and g_game.cancelFollow then pcall(g_game.cancelFollow) end
      if g_game and g_game.stop then pcall(g_game.stop) end
      followFreedAfterLost=true
      setFollowStatus('Comprando supplies: '..visit.npc)
      return true
    end
    local npc=supplyNpc(visit)
    if not visit.started then
      if time>=visit.approachUntil then restock.clear(true);return false end
      local position=npc and npc:getPosition() or visit.pos
      if distanceBetween(origin,position)>2 then
        walkFollowMap(position,2,time,'supplies')
        return true
      end
      if not npc then return true end
      stopFollowSearch(true)
      if not api.beginFollowVisit(visit.npc,npc,visit.shop) then restock.clear(true);return false end
      visit.started=true
      visit.actorId=npc:getId()
    end
    if not npc or npc:getId()~=visit.actorId or distanceBetween(origin,npc:getPosition())>3 then
      restock.clear(true)
      return false
    end
    local result=api.stepFollowVisit()
    if result=='retry' then return true end
    restock.clear(true)
    if RinoConsole and RinoConsole.log then
      pcall(RinoConsole.log,'action','Combo Follow',
        (result and 'Compra terminada en ' or 'Compra interrumpida en ')..visit.npc..'; buscando al lider')
    end
    return false
  end
end

chaseFollowName=function()
  followCombat.getState()
  if CaveBot and CaveBot.Flee and CaveBot.Flee.blocksCombat() then restock.clear();pauseFollowBoat();return end
  if HelperPause and HelperPause.isPaused() then restock.clear();return end
  if settings.followSupplies==false then restock.clear() end
  if not settings.followBoat then pauseFollowBoat() end
  if not settings.enabled or not settings.followEnabled then
    restock.clear()
    pauseFollowBoat()
    stopFollowSearch()
    stopDistanceFollow()
    followFloorReturns={}
    setFollowStatus(settings.enabled and 'Seguimiento apagado' or 'Combo apagado')
    if followWasActive and g_game and g_game.cancelFollow then
      pcall(function() g_game.cancelFollow() end)
    end
    followWasActive = false
    return
  end
  followWasActive = true
  followTrace.summary(lastFollowStatus)

  resetFollowMemoryIfNeeded()
  local name = getFollowName()
  if followSearch.name and followSearch.name~=lower(name) then pauseFollowBoat() end
  if name == "" then
    restock.clear()
    setFollowStatus('Escribe el jugador a seguir')
    if g_game and g_game.cancelFollow then
      pcall(function() g_game.cancelFollow() end)
    end
    return
  end

  local playerPos = getPlayerPosition()
  local playerPosKey = getPositionKey(playerPos)
  local time = getTime()
  if playerPosKey ~= "" and playerPosKey ~= lastPlayerPositionKey then
    lastPlayerPositionKey = playerPosKey
    lastFollowProgressAt = time
  end

  local movement=TargetBot and TargetBot.Movement
  local safety=TargetBot and TargetBot.Antitrap
  if movement and movement.isManual and movement.isManual() then restock.clear();pauseFollowBoat();setFollowStatus('Pausa: movimiento manual');return end
  if safety and safety.ownsMovement and safety.ownsMovement() then restock.clear();pauseFollowBoat();setFollowStatus('Pausa: escape de seguridad');return end
  if CaveBot and CaveBot.WaitStamina and CaveBot.WaitStamina.isBlocking() then restock.clear();pauseFollowBoat();setFollowStatus('Pausa: stamina');return end
  if player and player.getHealthPercent and player:getHealthPercent()<=0 then restock.clear();pauseFollowBoat();return end
  if restock.tick(name,playerPos,time) then return end
  cancelWrongFollow(name)

  local departure = lastFollowTransitionPosition
  local recentDeparture = isRecentFollowTransition(departure,time)
  local followTarget = findFollowCreature(recentDeparture)
  if recentDeparture and followTarget and lastFollowPosition and
    lastFollowPosition.z~=departure.z and samePosition(followTarget:getPosition(),departure) then
    followTarget=nil -- The departure event is newer than the creature still being removed.
  end
  followTrace.visible(followTarget ~= nil)
  if followTarget and followVisibleTarget(followTarget, name) then
    if followSearch.transport then
      pauseFollowBoat()
      followSearch.finishedJump=followSearch.transport.jump
      followSearch.transport=nil
    end
    return
  end

  stopDistanceFollow()
  if not followFreedAfterLost then
    if g_game and g_game.cancelFollow then pcall(g_game.cancelFollow) end
    followFreedAfterLost=true
  end
  local currentZ = getPlayerZ()
  local lastPos = currentZ and followPositions[currentZ]
  if recentDeparture and departure.z==currentZ then
    -- Keep requesting newer positions, but the staircase we just saw takes
    -- precedence over an old Navi target on this floor.
    readFollowNavi(name,time)
    setFollowStatus('Follow: cruzando el cambio de piso del leader')
    if distanceBetween(playerPos,departure)<=1 then
      if time-lastFollowWalkAt<120 then return end
      if crossFollowFloor(departure,lastFollowTransitionArrival,time) then return end
    elseif walkFollowMap(departure,1,time,'stairs') then return end
    -- Let Navi suggest another access once the locally observed one is exhausted.
    lastFollowTransitionPosition=nil
    lastFollowTransitionArrival=nil
    lastPos=departure
  end
  if not lastPos and lastFollowPosition and lastFollowPosition.z == currentZ then
    lastPos = lastFollowPosition
  end
  if hasPosition(playerPos) and returnFollowFloor(name,playerPos,time) then return end
  if seekFollowNavi(name,time,nil,nil,true) then return end

  -- Some clients only remove the creature from view on a floor change.
  -- Try a marked access beside the last sighting while it is still fresh.
  if lastPos and lastFollowPosition and samePosition(lastPos,lastFollowPosition) and
    time-lastFollowSeenAt<=FOLLOW_TRANSITION_TTL_MS and distanceBetween(playerPos,lastPos)<=1 and
    crossFollowFloor(lastPos,nil,time,true) then
    setFollowStatus('Follow: probando acceso junto al ultimo punto')
    return
  end
  if lastPos then
    setFollowStatus('Recuperando el ultimo punto / cambio de piso')
    local followDistance = distanceBetween(playerPos, lastPos)
    local urgent = isRecentFollowTransition(lastPos, time)
    local knownTransition=urgent
    if followDistance==0 and not knownTransition then
      setFollowStatus('Ultimo punto alcanzado: buscando al leader');return
    end
    local walking = false

    if urgent and followDistance <= 1 then
      if stepIntoFollowPosition(lastPos) then return end
      if tryUseFollowTransition(lastPos, true) then return end
    end

    walking = walkFollowMap(lastPos, 0, time)

    if followDistance <= 1 and time - lastFollowProgressAt > 300 then
      if stepIntoFollowPosition(lastPos) then return end
    end

    if knownTransition and not walking and followDistance <= 2 then
      tryUseFollowTransition(lastPos)
    end

    if knownTransition and followDistance == 0 and time - lastFollowProgressAt > 450 then
      tryUseFollowTransition(lastPos, true)
    end

    if knownTransition and followDistance <= 1 and time - lastFollowProgressAt > 850 then
      if not stepIntoFollowPosition(lastPos) then
        tryUseFollowTransition(lastPos, true)
      end
    end

    if knownTransition then recoverFollowPath(lastPos, followDistance, urgent) end
  else
    setFollowStatus(followSearch.route and 'Leader en otro piso: esperando acceso conocido' or followSearch.reason or 'Buscando al leader: esperando posicion de Navi')
  end
end

do
  local lastCheckAt
  macro(10, function()
    local time=getTime()
    if not spacing.pending and not spacing.waiting and lastCheckAt and time>=lastCheckAt and time-lastCheckAt<25 then return end
    lastCheckAt=time
    chaseFollowName()
  end)
end

local followWakePending=false
local function wakeFollow()
  if followWakePending then return end
  followWakePending=true
  schedule(1,function()followWakePending=false;chaseFollowName()end)
end

-- Native Follow can be cleared by attack, target or a rejected path. Keep the
-- intent ON and wake the existing recovery loop without reentrant follow calls.
if type(onFollowingCreatureChange)=='function' then
  onFollowingCreatureChange(function()
    if followWakePending or not settings.enabled or not settings.followEnabled then return end
    local state=followCombat.getState()
    if state.borrowed then return end
    local following=getFollowingCreature()
    if following and isFollowCreature(following) then return end
    lastFollowRequestAt=0
    wakeFollow()
  end)
end

onCreaturePositionChange(function(creature, newPos, oldPos)
  if not settings.enabled or not settings.followEnabled then return end
  if not isFollowCreature(creature) then return end
  local followMoved=not samePosition(newPos,oldPos)
  if followMoved then followTrace.leaderMoved() end
  if followMoved and settings.followCombatPriority then followCombat.invalidate(true) end
  if oldPos then rememberFollowPosition(oldPos) end
  if newPos then rememberFollowPosition(newPos) end
  if oldPos and newPos and oldPos.z ~= newPos.z then
    local playerZ = getPlayerZ()
    if oldPos.z == playerZ and math.abs(oldPos.z-newPos.z)==1 and
      math.max(math.abs(oldPos.x-newPos.x),math.abs(oldPos.y-newPos.y))<=8 then
      followSearch.crossing=nil
      lastFollowTransitionAt = getTime()
      lastFollowTransitionPosition = copyPosition(oldPos)
      lastFollowTransitionArrival = copyPosition(newPos)
      followPositions[playerZ] = lastFollowTransitionPosition
    end
  end
  -- Record a floor entry before recovery reads it.
  if followMoved then chaseFollowName() end
  if oldPos and newPos and oldPos.z ~= newPos.z and type(schedule) == "function" then
    schedule(40, chaseFollowName)
    schedule(100, chaseFollowName)
    schedule(220, chaseFollowName)
    schedule(400, chaseFollowName)
    schedule(700, chaseFollowName)
  end
end)

do
  local function leaderVisibilityChanged(creature)
    if settings.enabled and settings.followEnabled and isFollowCreature(creature) then wakeFollow() end
  end
  if type(onCreatureDisappear)=='function' then onCreatureDisappear(leaderVisibilityChanged) end
  if type(onCreatureAppear)=='function' then onCreatureAppear(leaderVisibilityChanged) end
end

onPlayerPositionChange(function(newPos, oldPos)
  combatCache=nil
  followCombat.getState()
  if not settings.enabled or not settings.followEnabled or not oldPos or not newPos then return end
  if oldPos.z == newPos.z then
    followTrace.ownStep()
    if spacing.pending and not samePosition(spacing.pending.from,newPos) or
      followSearch.active and samePosition(followSearch.leg,newPos) then wakeFollow() end
    return
  end
  local time=getTime()
  local pending=followSearch.crossing and followSearch.crossing.pending
  local crossing=pending and time<=pending.untilAt and samePosition(oldPos,pending.from) and
    (not pending.floor or newPos.z==pending.floor)
  local arrival=lastFollowTransitionArrival
  local followingLeader=isRecentFollowTransition(lastFollowTransitionPosition,time) and
    arrival and newPos.z==arrival.z and distanceBetween(newPos,arrival)<=3
  local previous=followFloorReturns[#followFloorReturns]
  -- Save the landing and departure for a return even if the leader sent no Navi route.
  local leaderPos=lastFollowPosition or followSearch.route and followSearch.route.pos
  if math.abs(newPos.z-oldPos.z)~=1 or math.max(math.abs(newPos.x-oldPos.x),math.abs(newPos.y-oldPos.y))>8 then
    followFloorReturns={}
  elseif previous and newPos.z==previous.arrival.z and distanceBetween(newPos,previous.arrival)<=8 then
    table.remove(followFloorReturns)
  elseif not crossing and not followingLeader and (previous or leaderPos and leaderPos.z==oldPos.z) then
    followFloorReturns[#followFloorReturns+1]={goal=copyPosition(newPos),arrival=copyPosition(oldPos),at=time}
    if #followFloorReturns>6 then table.remove(followFloorReturns,1) end
  end
  local journey=followSearch.journey
  local leg=journey and journey.steps and journey.steps[journey.index]
  if not leg or leg.kind~='floor' or distanceBetween(newPos,leg.to)>3 then journey=nil end
  stopFollowSearch(true)
  followSearch.journey=journey
  followSearch.nextWalk=0
  followSearch.failures=0
  lastFollowTransitionPosition = nil
  lastFollowTransitionArrival = nil
  followSearch.crossing=nil
  followSearch.pollAt=0
  if g_game and g_game.cancelFollow then
    pcall(function() g_game.cancelFollow() end)
  end
  lastFollowProgressAt = time
  -- The leader is usually in view the moment the new floor loads: look at once, not 120 ms later.
  chaseFollowName()
  schedule(40, chaseFollowName)
  schedule(120, chaseFollowName)
  schedule(350, chaseFollowName)
  schedule(650, chaseFollowName)
end)

local function refreshLeaderFollowAfterCombat()
  if not settings.enabled or not settings.followEnabled or getFollowName() == "" then return end

  chaseFollowName()
  if type(schedule) == "function" then
    schedule(60, chaseFollowName)
    schedule(160, chaseFollowName)
    schedule(320, chaseFollowName)
  end
end

local function findLeaderOnTile(tile)
  if not tile then return nil end
  for _, creature in ipairs(tile:getCreatures()) do
    if creature and creature:isPlayer() and not creature:isLocalPlayer() and isLeader(creature:getName()) then
      return creature
    end
  end
  return nil
end

local function isFriend(creature)
  if not settings.ignoreFriends or not creature then return false end
  local friendList = storage.playerList and storage.playerList.friendList
  return friendList and table.find(friendList, creature:getName(), true)
end

local function getUseSubtype(itemId)
  local thing = g_things and g_things.getThingType and g_things.getThingType(itemId)
  if not thing or not thing:isFluidContainer() then
    return g_game.getClientVersion() >= 860 and 0 or 1
  end
  return 0
end

local function useItemWithId(itemId, targetThing)
  itemId = tonumber(itemId)
  if not itemId or itemId < 100 or not targetThing then return false end

  local subType = getUseSubtype(itemId)
  local visibleItem = findItem(itemId)
  if visibleItem and g_game and g_game.useWith then
    local ok, result = pcall(function()
      return g_game.useWith(visibleItem, targetThing, subType)
    end)
    if ok and result ~= false then return true end
  end

  if g_game and g_game.useInventoryItemWith then
    local ok, result = pcall(function()
      return g_game.useInventoryItemWith(itemId, targetThing, subType)
    end)
    if ok and result ~= false then return true end
  end

  if type(useWith) == "function" then
    local ok, result = pcall(function()
      return useWith(itemId, targetThing, subType)
    end)
    if ok and result ~= false then return true end
  end

  return false
end

-- Cooperate only at this script's item boundary; protective equipment/spells stay independent.
local native_useItemWithId=useItemWithId
useItemWithId=function(itemId, targetThing)
  if PushMax and type(PushMax.performItem)=='function'then
    return PushMax.performItem('Combo',itemId,false,native_useItemWithId,itemId, targetThing)
  end
  return native_useItemWithId(itemId, targetThing)
end

-- Navi shares selection only. It never carries a request to cast or use a rune.
local TARGET_TOPIC='combo_target_v1'
local targetSync={owner={},sequence=0,received={}}
targetSync.session=tostring(os.time())..':'..tostring(targetSync.owner)..':'..tostring(getTime())
if BotServer then
  targetSync.server=BotServer
  BotServer._helperComboTargetOwner=targetSync.owner
end
local function targetIdentity(creature)
  if not creature then return '' end
  local id=creature.getId and creature:getId() or 0
  return tostring(id)..':'..lower(creature:getName())
end
local function selectLeaderTarget(creature)
  local previous=targetSync.suppressed
  targetSync.suppressed=targetIdentity(creature)
  local ok,result=pcall(g_game.attack,creature)
  if not ok or result==false then targetSync.suppressed=previous;return false end
  return true
end

-- One dispatcher for voice, projectiles and explicit leader commands. Sending
-- an API request or its speech echo is not proof of server-side damage.
local function triggerCombo(creature, signal, kind, leaderName)
  if CaveBot and CaveBot.Flee and CaveBot.Flee.blocksCombat() then return end
  if not settings.enabled then report(nil,'Combo OFF: activa el interruptor principal.');return false end
  if creature and (creature:isLocalPlayer() or isFriend(creature)) then
    report(nil,'Objetivo protegido: propio personaje o amigo.');return false
  end
  if creature and creature.getPosition then
    local p=creature:getPosition()
    if p and p.z~=getPlayerZ() then report(nil,'Objetivo en otro piso.');return false end
  end
  if creature and creature.getHealthPercent and creature:getHealthPercent()<=0 then
    report(nil,'El objetivo ya no tiene vida.');return false
  end
  -- A signal has exactly one response type. Unknown signals cannot request
  -- both actions. Keep duplicate protection separate for SD and UE.
  if kind~='rune' and kind~='spell' then return false end
  local time=getTime()
  local gap=math.max(100,math.min(1000,tonumber(settings.comboCooldown) or 100))
  local key=kind..':'..lower(leaderName)
  local previous=comboBursts[key]
  local targetKey=kind=='rune' and creature and targetIdentity(creature) or ''
  local grouped=previous and previous.target==targetKey and time-previous.at<gap
  local burst=grouped and previous or {at=time,target=targetKey,spell=false,rune=false}
  local sent,blocked={},{}
  local marked=false
  local function markTarget()
    if marked then return end
    marked=true
    if creature and settings.attackTargetEnabled then
      local current=getCurrentTarget()
      if not current or not sameCreature(current,creature) then selectLeaderTarget(creature) end
    end
  end
  local words=trim(settings.comboSpell)
  local spellRequested=kind=='spell' and settings.comboSpellEnabled and words~=''
  if spellRequested and burst.spell then blocked[#blocked+1]='spell ya solicitado'
  elseif spellRequested then
    local ready=true
    if type(canCast)=='function' then local ok,v=pcall(canCast,words,false,false);ready=ok and v==true end
    if not ready then
      blocked[#blocked+1]='spell en cooldown o sin requisitos'
    else
      markTarget()
      local ok,v=pcall(say,words)
      if ok and v~=false then
        sent[#sent+1]='spell';burst.spell=true;pendingSpell={words=formulaOnly(words),at=time}
      else blocked[#blocked+1]='no se pudo enviar el spell' end
    end
  elseif kind=='spell' then blocked[#blocked+1]='spell OFF o formula vacia' end
  if kind=='rune' and settings.comboRuneEnabled then
    if burst.rune then blocked[#blocked+1]='runa ya solicitada'
    elseif not creature then blocked[#blocked+1]='sin target para la runa'
    else
      markTarget()
      if useItemWithId(settings.comboRuneId,creature) then sent[#sent+1]='runa';burst.rune=true
      else blocked[#blocked+1]='no se pudo solicitar la runa' end
    end
  elseif kind=='rune' then blocked[#blocked+1]='runa OFF' end
  if #sent>0 then
    comboBursts[key]=burst
    refreshLeaderFollowAfterCombat()
    report(nil,'Solicitado: '..table.concat(sent,' + ')..(#blocked>0 and ' | '..table.concat(blocked,'; ') or ''))
    return true
  end
  report(nil,'Sin envio: '..table.concat(blocked,'; '))
  return false
end

-- Targeting messages are not combat triggers. In particular a leader's
-- auto-announced .target must not cast on every ordinary attack.
local function markLeaderTarget(creature)
  if CaveBot and CaveBot.Flee and CaveBot.Flee.blocksCombat() then return end
  if not settings.enabled or not settings.attackTargetEnabled then report(nil,'Marcar objetivo OFF.');return false end
  if not creature or creature:isLocalPlayer() or isFriend(creature) then report(nil,'Objetivo no visible o protegido.');return false end
  local pos=creature.getPosition and creature:getPosition()
  if pos and pos.z~=getPlayerZ() then report(nil,'Objetivo en otro piso.');return false end
  if creature.getHealthPercent and creature:getHealthPercent()<=0 then report(nil,'Objetivo sin vida.');return false end
  local current=getCurrentTarget()
  if not current or not sameCreature(current,creature) then
    local ok=selectLeaderTarget(creature)
    if not ok then report(nil,'No se pudo marcar el objetivo.');return false end
  end
  report(nil,'Objetivo marcado; esperando UE o SD del lider.')
  return true
end

local function validInteger(value,minimum,maximum)
  return type(value)=='number' and value==math.floor(value) and value>=minimum and value<=maximum
end
local function receiveLeaderTarget(name,message)
  if not settings.enabled or not settings.attackTargetEnabled then return end
  if type(name)~='string' or lower(name)==lower(player:getName()) or not isLeader(name) then return end
  if type(message)~='table' or message.v~=1
    or type(message.session)~='string' or #message.session>100 or #message.session==0
    or not validInteger(message.seq,1,2147483647)
    or not validInteger(message.floor,0,15) then return end
  local data=message.target
  if data~=false and (type(data)~='table' or type(data.name)~='string'
    or #data.name==0 or #data.name>64 or not validInteger(data.id,0,4294967295)) then return end
  local sender=lower(name)
  local previous=targetSync.received[sender]
  if previous and previous.session==message.session and message.seq<=previous.seq then return end
  targetSync.received[sender]={session=message.session,seq=message.seq}
  -- A leader clearing target must not cancel an unrelated manual attack.
  if data==false then return end
  if message.floor~=getPlayerZ() then report(nil,'Objetivo Navi del lider en otro piso.');return end
  local creature
  if data.id>0 and g_map.getCreatureById then creature=g_map.getCreatureById(data.id) end
  if not creature then creature=getCreatureByName(data.name) end
  -- Resolve against this client's visible creature, never trust remote objects.
  if not creature or lower(creature:getName())~=lower(data.name)
    or data.id>0 and (not creature.getId or creature:getId()~=data.id) then
    report(nil,'Objetivo Navi del lider no visible.');return
  end
  local pos=creature:getPosition()
  if not pos or pos.z~=getPlayerZ() then report(nil,'Objetivo Navi no visible en este piso.');return end
  report(name..' > objetivo: '..creature:getName()..' [Navi]')
  markLeaderTarget(creature)
end

local function refreshTargetSync(creature,fromEvent)
  local server=BotServer
  if not server or type(server.listen)~='function' or type(server.send)~='function' then return end
  if not targetSync.server then
    targetSync.server=server;server._helperComboTargetOwner=targetSync.owner
  end
  if targetSync.server~=server or server._helperComboTargetOwner~=targetSync.owner then return end
  local socket=server._websocket
  if not socket then targetSync.socket=nil;targetSync.lastObserved=nil;return end
  if targetSync.socket~=socket then
    local ok,result=pcall(server.listen,TARGET_TOPIC,function(name,message)
      if server._helperComboTargetOwner~=targetSync.owner or server._websocket~=socket then return end
      receiveLeaderTarget(name,message)
    end)
    if not ok or result==false then return end
    targetSync.socket=socket;targetSync.lastObserved=nil
  end
  if not settings.enabled or not settings.shareTargetEnabled then targetSync.lastObserved=nil;return end
  if not fromEvent then creature=getCurrentTarget() end
  local identity=targetIdentity(creature)
  if identity==targetSync.suppressed then targetSync.lastObserved=identity;return end
  if identity==targetSync.lastObserved then return end
  targetSync.suppressed=nil
  local data=false
  if creature then
    local p=creature:getPosition()
    local name=creature:getName()
    local id=creature.getId and creature:getId() or 0
    if not p or p.z~=getPlayerZ() or type(name)~='string' or #name==0 or #name>64
      or not validInteger(id,0,4294967295) then return end
    data={id=id,name=name}
  elseif targetSync.lastObserved==nil then
    -- An idle connection needs no empty target announcement.
    targetSync.lastObserved=identity;return
  end
  targetSync.sequence=targetSync.sequence+1
  local ok,result=pcall(server.send,TARGET_TOPIC,{
    v=1,session=targetSync.session,seq=targetSync.sequence,floor=getPlayerZ(),target=data
  })
  if ok and result~=false then targetSync.lastObserved=identity end
end
if type(onAttackingCreatureChange)=='function' then
  onAttackingCreatureChange(function(creature)refreshTargetSync(creature,true)end)
end


showLeaderPicker=function(button)
  local list={};local seen={}
  local actors=type(getSpectators)=='function' and getSpectators(false) or {}
  for _,creature in ipairs(actors or {}) do
    if creature:isPlayer() and not creature:isLocalPlayer() then
      local name=trim(creature:getName());local p=creature:getPosition()
      if #list<80 and name~='' and p and p.z==getPlayerZ() and not seen[lower(name)] then
        seen[lower(name)]=true;list[#list+1]=name
      end
    end
  end
  table.sort(list,function(a,b)return lower(a)<lower(b)end)
  local menu=g_ui.createWidget('PopupMenu')
  if #list==0 then menu:addOption('Sin jugadores visibles: escribe el nombre',function()end) end
  for _,name in ipairs(list) do
    local chosen=name
    menu:addOption(chosen,function()leaderRow.textEdit:setText(chosen);report(nil,'Lider elegido. Esperando su spell o proyectil.')end)
  end
  local pos=button:getPosition();menu:display({x=pos.x,y=pos.y+button:getHeight()})
end

learnLastSpell=function()
  if not lastLeaderSpell or getTime()-lastLeaderSpell.at>30000 or not isLeader(lastLeaderSpell.name) then
    report(nil,'Sin spell reciente de tus lideres. Haz que uno lance un spell.');return
  end
  local words=lastLeaderSpell.words
  if not textMatchesTrigger(words,settings.spellTriggerText) then
    local old=trim(settings.spellTriggerText)
    triggerEdit.textEdit:setText(old=='' and words or old..', '..words)
  end
  settings.triggerMode='list';refreshTriggerMode()
  report(nil,'Agregado a tu lista: '..words)
end

local lastDiagnosticText=''
local function statusLine(text)
  text=tostring(text):gsub('[\r\n]+',' ')
  return #text>76 and text:sub(1,73)..'...' or text
end
refreshDiagnostics=function()
  if not comboPlusWindow:isVisible() then return end
  local leaders={}
  for _,key in ipairs({'leader1','leader2','leader3'})do
    local name=trim(settings[key]);if name~='' then leaders[#leaders+1]=name end
  end
  local config=''
  if not settings.enabled then config='Combo OFF'
  elseif #leaders==0 then config='Falta elegir lider'
  elseif not settings.comboSpellEnabled and not settings.comboRuneEnabled and not settings.mwComboEnabled then
    config=settings.attackTargetEnabled and 'Solo copiar objetivo (SD y UE OFF)' or 'Respuestas OFF'
  else config='Lider: '..table.concat(leaders,', ') end
  local value=config..'\n'..diagnostic.signal..'\n'..diagnostic.result
  if value~=lastDiagnosticText then
    lastDiagnosticText=value
    comboPlusWindow.status:setText(statusLine(config)..'\n'..statusLine(diagnostic.signal)..'\n'..statusLine(diagnostic.result))
    applyTooltip(comboPlusWindow.status,value)
  end
end

local wallIdsCacheText,wallIdsCache
local function wallObjectIds()
  local text=tostring(settings.mwObjectIds or '')
  if text~=wallIdsCacheText then
    wallIdsCacheText=text
    wallIdsCache=parseWallObjectIds(text)
  end
  return wallIdsCache
end

local function tileHasMagicWall(tile)
  if not tile then return false end
  local ids = wallObjectIds()
  for _, item in ipairs(tile:getItems()) do
    if table.find(ids, item:getId()) then return true end
  end
  local topThing = tile:getTopThing()
  return topThing and topThing:isItem() and table.find(ids, topThing:getId())
end

local function canUseMwallOn(tile)
  if not tile then return false end
  if tileHasMagicWall(tile) then return false end
  if tile.hasCreature and tile:hasCreature() then return false end
  if tile.getGround and not tile:getGround() then return false end
  if tile.isWalkable and not tile:isWalkable() then return false end
  if tile.canShoot and not tile:canShoot() then return false end
  return true
end

local function sign(value)
  if value > 0 then return 1 end
  if value < 0 then return -1 end
  return 0
end

local function distanceToPlayer(pos)
  local playerPos = player:getPosition()
  if not hasPosition(pos) or not hasPosition(playerPos) or pos.z ~= playerPos.z then return 999 end
  return math.max(math.abs(pos.x - playerPos.x), math.abs(pos.y - playerPos.y))
end

local function addCandidate(candidates, seen, basePos, offset)
  local pos = {x = basePos.x + offset.x, y = basePos.y + offset.y, z = basePos.z}
  local key = positionKey(pos)
  if key ~= "" and not seen[key] then
    seen[key] = true
    table.insert(candidates, pos)
  end
end

local function isHalfCircleMwPattern()
  local mode = lower(settings.mwPattern)
  return mode == "half" or mode == "half circle" or mode == "halfcircle" or mode == "medio circulo" or mode == "semicircle"
end

local function addHalfCircleCandidates(candidates, seen, basePos, forward, firstSide, secondSide)
  if not forward or (forward.x == 0 and forward.y == 0) then return false end
  if not firstSide or not secondSide then return false end

  addCandidate(candidates, seen, basePos, firstSide)
  addCandidate(candidates, seen, basePos, secondSide)
  addCandidate(candidates, seen, basePos, {x = forward.x + firstSide.x, y = forward.y + firstSide.y})
  addCandidate(candidates, seen, basePos, forward)
  addCandidate(candidates, seen, basePos, {x = forward.x + secondSide.x, y = forward.y + secondSide.y})
  addCandidate(candidates, seen, basePos, {x = forward.x * 2 + firstSide.x, y = forward.y * 2 + firstSide.y})
  addCandidate(candidates, seen, basePos, {x = forward.x * 2, y = forward.y * 2})
  addCandidate(candidates, seen, basePos, {x = forward.x * 2 + secondSide.x, y = forward.y * 2 + secondSide.y})

  for distance = 2, MW_SIDE_SPREAD_LIMIT do
    addCandidate(candidates, seen, basePos, {x = firstSide.x * distance, y = firstSide.y * distance})
    addCandidate(candidates, seen, basePos, {x = secondSide.x * distance, y = secondSide.y * distance})
  end

  return true
end

-- One bounded response per observed leader wall. Requests remain pending until
-- the map confirms them, so a rejected occupied square can be reassigned.
local MW={queue={},seen={},leases={},serial=0,topic='combo_mw_v1'}
root._helperComboWallOwner=MW
function MW.valid()return root._helperComboWallOwner==MW end
function MW.name()return lower(player:getName())end
function MW.hash()
  local h=0
  for i=1,#MW.name()do h=(h*31+MW.name():byte(i))%65521 end
  return h
end
function MW.allowed()
  return MW.valid() and settings.enabled and settings.mwComboEnabled
    and not(CaveBot and CaveBot.Flee and CaveBot.Flee.blocksCombat())
end
function MW.distance(a,b)
  if not hasPosition(a)or not hasPosition(b)or a.z~=b.z then return 999 end
  return math.max(math.abs(a.x-b.x),math.abs(a.y-b.y))
end
function MW.liveLease(pos,job)
  local key=positionKey(pos);local lease=MW.leases[key]
  if lease and lease.expires<=getTime()then MW.leases[key]=nil;lease=nil end
  return lease
end
function MW.available(pos,job)
  if distanceToPlayer(pos)>7 or pos.z~=getPlayerZ()then return false end
  if job.failed[positionKey(pos)]and job.failed[positionKey(pos)]>getTime()then return false end
  local lease=MW.liveLease(pos,job)
  if lease and lease.owner~=MW.name()then return false end
  return canUseMwallOn(g_map.getTile(pos))
end
function MW.candidates(job)
  local candidates,seen={},{}
  local dx=sign(job.anchor.x-job.from.x);local dy=sign(job.anchor.y-job.from.y)
  if dx==0 and dy==0 then return candidates end
  local first={x=dy,y=-dx};local second={x=-dy,y=dx}
  if MW.hash()%2==1 then first,second=second,first end
  if isHalfCircleMwPattern()then
    addHalfCircleCandidates(candidates,seen,job.anchor,{x=dx,y=dy},first,second)
  else
    -- Each side contributes only its first gap. Never jump over a creature,
    -- terrain or an unconfirmed reservation and leave a hole in the wall line.
    for side,offset in ipairs({first,second})do
      for step=1,MW_SIDE_SPREAD_LIMIT do
        local pos={x=job.anchor.x+offset.x*step,y=job.anchor.y+offset.y*step,z=job.anchor.z}
        local tile=g_map.getTile(pos)
        if not tileHasMagicWall(tile)then
          if MW.available(pos,job)then pos.step=step;pos.side=side;candidates[#candidates+1]=pos end
          break
        end
      end
    end
    table.sort(candidates,function(a,b)
      if a.step~=b.step then return a.step<b.step end
      local da,db=distanceToPlayer(a),distanceToPlayer(b)
      if da~=db then return da<db end
      return a.side<b.side
    end)
  end
  local available={}
  for _,pos in ipairs(candidates)do if MW.available(pos,job)then available[#available+1]=pos end end
  return available
end
function MW.send(kind,job,pos,token)
  if not MW.socket or not BotServer or BotServer._websocket~=MW.socket then return false end
  local ok,result=pcall(BotServer.send,MW.topic,{v=1,kind=kind,anchor=copyPosition(job.anchor),pos=copyPosition(pos),token=token,ttl=2500})
  return ok and result~=false
end
function MW.release(job)
  if not job.pos or not job.token then return end
  local key=positionKey(job.pos);local lease=MW.leases[key]
  if lease and lease.owner==MW.name()and lease.token==job.token then MW.leases[key]=nil end
  MW.send('release',job,job.pos,job.token)
  job.token=nil
end
function MW.retry(job,reason)
  if job.pos then job.failed[positionKey(job.pos)]=getTime()+700 end
  MW.release(job)
  job.phase='search';job.nextAt=getTime()+60;job.pos=nil;job.ownShot=false;job.blockedHint=nil
  report(nil,'MW: '..reason..'; buscando otro hueco.')
end
function MW.finish(job,confirmed)
  if confirmed then
    MW.lastSuccess=job.requestedAt or getTime()
    if job.ownShot then MW.send('placed',job,job.pos,job.token)end
    report(nil,job.ownShot and 'MW confirmada; espacio completado.' or 'MW observada en la casilla solicitada.')
  end
  MW.release(job)
  MW.seen[job.key]=getTime()+3500
  for i,entry in ipairs(MW.queue)do if entry==job then table.remove(MW.queue,i);break end end
end
function MW.cancel()
  for _,job in ipairs(MW.queue)do MW.release(job)end
  MW.queue={}
end
function MW.receive(name,message)
  if not MW.allowed()or type(name)~='string'or #name>64 or trim(name)==''or lower(name)==MW.name()then return end
  if type(message)~='table'or message.v~=1 or type(message.token)~='string'or #message.token==0 or #message.token>140 then return end
  local function position(p)
    return type(p)=='table'and validInteger(p.x,0,65535)and validInteger(p.y,0,65535)and validInteger(p.z,0,15)
  end
  if not position(message.anchor)or not position(message.pos)
    or MW.distance(message.anchor,message.pos)<1 or MW.distance(message.anchor,message.pos)>MW_SIDE_SPREAD_LIMIT then return end
  local anchorKey=positionKey(message.anchor)
  local job
  for _,entry in ipairs(MW.queue)do if entry.key==anchorKey then job=entry;break end end
  if not job then return end -- Navi cannot create a combat job.
  local key=positionKey(message.pos);local previous=MW.leases[key];local sender=lower(name)
  if message.kind=='release'then
    if previous and previous.owner==sender and previous.token==message.token then MW.leases[key]=nil end
    return
  end
  if message.kind=='placed'then
    if job.phase=='await'and positionKey(job.pos)==key and not job.ownShot and tileHasMagicWall(g_map.getTile(message.pos))then
      MW.retry(job,'un companero completo esa casilla')
    end
    return
  end
  if message.kind~='claim'and message.kind~='attempt'then return end
  if not validInteger(message.ttl,100,2500)then return end
  if previous and previous.expires>getTime()and previous.owner~=sender then
    -- An in-flight placement keeps its lease. Simultaneous tentative claims
    -- use the same name ordering on every client, rather than both yielding.
    if previous.sent and message.kind=='claim'then return end
    if previous.sent==(message.kind=='attempt')and previous.owner<sender then return end
    if not previous.sent and message.kind=='claim'and previous.owner<sender then return end
  end
  MW.leases[key]={owner=sender,token=message.token,anchor=anchorKey,expires=getTime()+message.ttl,sent=message.kind=='attempt'}
end
function MW.attach()
  local server=BotServer
  if not server or type(server.listen)~='function'or type(server.send)~='function'
    or server._helperComboTargetOwner~=targetSync.owner then MW.socket=nil;return end
  local socket=server._websocket
  if not socket then MW.socket=nil;return end
  if MW.socket==socket then return end
  local ok,result=pcall(server.listen,MW.topic,function(name,message)
    if MW.valid()and server._websocket==socket and server._helperComboTargetOwner==targetSync.owner then MW.receive(name,message)end
  end)
  if ok and result~=false then MW.socket=socket end
end
function MW.request(job)
  -- Check the frontier again after the reservation interval; a teammate may
  -- have completed it while our client was waiting for the relay.
  local stillAvailable=false
  for _,pos in ipairs(MW.candidates(job))do if positionKey(pos)==positionKey(job.pos)then stillAvailable=true;break end end
  if not stillAvailable then MW.retry(job,'la casilla cambio');return end
  local tile=g_map.getTile(job.pos)
  local thing=tile and (tile:getTopUseThing()or tile:getGround()or tile:getTopThing())
  if not thing then MW.retry(job,'destino no disponible');return end
  job.requestedAt=getTime();job.source=copyPosition(player:getPosition());job.ownShot=false;job.blockedHint=nil
  if not useItemWithId(settings.mwRuneId,thing)then MW.retry(job,'orden no enviada');return end
  job.attempts=job.attempts+1;job.phase='await'
  local ping=g_game.getPing and tonumber(g_game.getPing())or 0
  job.confirmUntil=getTime()+math.max(600,math.min(2200,(ping or 0)*2+350))
  local lease=MW.liveLease(job.pos,job)
  if lease and lease.owner==MW.name()then lease.sent=true;lease.expires=getTime()+2500 end
  MW.send('attempt',job,job.pos,job.token)
  report(nil,'MW solicitada; esperando confirmacion de la casilla.')
end
function MW.tick()
  if not MW.valid()then return end
  MW.attach()
  local now=getTime()
  for key,lease in pairs(MW.leases)do if lease.expires<=now then MW.leases[key]=nil end end
  for key,expires in pairs(MW.seen)do if expires<=now then MW.seen[key]=nil end end
  if not MW.allowed()then MW.cancel();return end
  local job=MW.queue[1]
  if not job then return end
  if now>job.deadline or job.anchor.z~=getPlayerZ()or not tileHasMagicWall(g_map.getTile(job.anchor))then
    report(nil,'MW: ciclo finalizado; sin otro hueco valido.');MW.finish(job,false);return
  end
  if job.phase=='await'then
    local wall=tileHasMagicWall(g_map.getTile(job.pos))
    if job.blockedHint and not job.ownShot and now-job.blockedHint<=600 and not canUseMwallOn(g_map.getTile(job.pos))then
      MW.retry(job,'hueco ocupado o rechazado')
    elseif wall and job.ownShot then MW.finish(job,true)
    elseif now>=job.confirmUntil then
      if wall then MW.finish(job,true)else MW.retry(job,'sin confirmacion')end
    end
    return
  end
  if now<job.nextAt then return end
  local cooldown=math.max(200,math.min(2000,tonumber(settings.mwCooldown)or 1000))
  if MW.lastSuccess and now-MW.lastSuccess<cooldown then return end
  if job.attempts>=4 then report(nil,'MW: limite de reintentos alcanzado.');MW.finish(job,false);return end
  if job.phase=='claim'then MW.request(job);return end
  local candidates=MW.candidates(job)
  if #candidates==0 then report(nil,'MW: esperando un hueco junto a las paredes.');return end
  job.pos=copyPosition(candidates[1]);MW.serial=MW.serial+1
  job.token=targetSync.session..':'..MW.serial
  MW.leases[positionKey(job.pos)]={owner=MW.name(),token=job.token,anchor=job.key,expires=now+2500,sent=false}
  job.phase='claim'
  if MW.send('claim',job,job.pos,job.token)then
    local ping=g_game.getPing and tonumber(g_game.getPing())or 0
    job.nextAt=now+math.max(80,math.min(220,(ping or 0)+60))+MW.hash()%61
  else MW.request(job)end
end
function MW.begin(wallPos,fromPos)
  if not MW.allowed()or not hasPosition(wallPos)or not hasPosition(fromPos)then return end
  local key=positionKey(wallPos)
  if MW.seen[key]and MW.seen[key]>getTime()then return end
  for _,job in ipairs(MW.queue)do if job.key==key then return end end
  if #MW.queue>=4 then return end
  MW.queue[#MW.queue+1]={key=key,anchor=copyPosition(wallPos),from=copyPosition(fromPos),phase='search',
    nextAt=getTime(),deadline=getTime()+4500,failed={},attempts=0}
  MW.tick()
end
function MW.observeThing(tile)
  if not MW.valid()then return end
  local job=MW.queue[1]
  if job and job.phase=='await'and positionKey(tile:getPosition())==positionKey(job.pos)and job.ownShot
    and tileHasMagicWall(tile)then MW.finish(job,true)end
end
function MW.observeMissile(missile)
  if not MW.valid()then return end
  local job=MW.queue[1]
  if not job or job.phase~='await'then return end
  local src,dest=missile:getSource(),missile:getDestination()
  if positionKey(dest)~=positionKey(job.pos)then return end
  if positionKey(src)~=positionKey(job.source)and positionKey(src)~=positionKey(player:getPosition())then return end
  local tile=g_map.getTile(src);local actors=tile and tile:getCreatures()or{}
  if #actors~=1 or not actors[1]:isLocalPlayer()then return end
  job.ownShot=true;MW.tick()
end
function MW.message(text)
  if not MW.allowed()then return end
  local job=MW.queue[1]
  if not job or job.phase~='await'or getTime()-job.requestedAt>1400 then return end
  text=lower(text)
  if text:find('protection zone',1,true)or text:find('zona de protec',1,true)then
    MW.finish(job,false);return
  end
  -- Generic exhaustion can belong to an automatic heal or another module.
  -- Do not let an unrelated spell postpone or redirect an outstanding wall.
  local blocked=text:find('not enough room',1,true)or text:find('not enough space',1,true)
    or text:find('cannot throw',1,true)or text:find("can't throw",1,true)
    or text:find('no hay espacio',1,true)or text:find('no puedes lanzar',1,true)
  local generic=text:find('not possible',1,true)or text:find('no es posible',1,true)
  if (blocked or generic)and not job.ownShot then
    job.blockedHint=getTime()
    if not canUseMwallOn(g_map.getTile(job.pos))then MW.retry(job,'hueco ocupado o rechazado')end
  end
end
macro(50,MW.tick)
if type(onTextMessage)=='function'then onTextMessage(function(_,text)MW.message(text)end)end

local function pruneRecentWallShots()
  local now=getTime()
  for key,data in pairs(recentWallShots)do if not data.time or now-data.time>1500 then recentWallShots[key]=nil end end
end
local function registerLeaderWallShot(destPos,fromPos)
  if not MW.allowed()or not hasPosition(destPos)then return end
  pruneRecentWallShots()
  local key=positionKey(destPos);local shotTime=getTime()
  recentWallShots[key]={pos=copyPosition(destPos),from=copyPosition(fromPos),time=shotTime}
  schedule(tonumber(settings.mwReactDelay)or 80,function()
    local data=recentWallShots[key]
    if not MW.valid()or not data or data.time~=shotTime then return end
    if tileHasMagicWall(g_map.getTile(data.pos))then MW.begin(data.pos,data.from);recentWallShots[key]=nil end
  end)
end

onMissle(function(missile)
  MW.observeMissile(missile)
  if CaveBot and CaveBot.Flee and CaveBot.Flee.blocksCombat() then return end
  if not settings.enabled then return end

  local src = missile:getSource()
  local dest = missile:getDestination()
  if not hasPosition(src) or not hasPosition(dest) or src.z ~= posz() then return end

  local fromTile = g_map.getTile(src)
  local toTile = g_map.getTile(dest)
  if not fromTile or not toTile then return end

  local leader = findLeaderOnTile(fromTile)
  if not leader then return end

  local targetCreature = nil
  for _, creature in ipairs(toTile:getCreatures()) do
    if creature and not creature:isLocalPlayer() then
      targetCreature = creature
      break
    end
  end

  if targetCreature then
    if not settings.missileEnabled or not sdMissile(missile) then return end
    -- The packet identifies source coordinates, not the shooter. A stacked
    -- source is ambiguous; do not attribute another creature's SD to leader.
    local actors=fromTile:getCreatures()
    if #actors~=1 then report(nil,'Origen de SD compartido; no se puede identificar al lider.');return end
    report(leader:getName()..' > SD a '..targetCreature:getName())
    triggerCombo(targetCreature,'projectile','rune',leader:getName())
    return
  end

  registerLeaderWallShot(dest, src)
end)

onAddThing(function(tile, thing)
  if not MW.allowed()then return end
  if not tile or not thing or not thing:isItem() then return end
  if not table.find(wallObjectIds(), thing:getId()) then return end
  MW.observeThing(tile)

  pruneRecentWallShots()
  local tilePos = tile:getPosition()
  local key = positionKey(tilePos)
  local data = recentWallShots[key]
  if not data then return end

  MW.begin(data.pos, data.from)
  recentWallShots[key] = nil
end)

onTalk(function(name, level, mode, text, channelId, pos)
  if CaveBot and CaveBot.Flee and CaveBot.Flee.blocksCombat() then return end
  -- The client delivers spell speech through onTalk. Do not bind detection to
  -- a hardcoded mode number or the orange rendering used by this server.
  text=tostring(text or ''):sub(1,512)
  if lower(name)==lower(player:getName()) then
    if pendingSpell and getTime()-pendingSpell.at<=2000 and formulaOnly(text)==pendingSpell.words then
      report(nil,'Eco de mi spell recibido: '..pendingSpell.words);pendingSpell=nil
    end
    return
  end
  if not isLeader(name) then return end
  local words=formulaOnly(text)
  local detected=offensiveSpell(text) or textMatchesTrigger(text,settings.spellTriggerText)
  report(tostring(name)..' > '..text:sub(1,100)..' [voz '..tostring(mode)..']')
  if pos and pos.z and pos.z~=getPlayerZ() then report(nil,'Voz del lider en otro piso.');return end
  if detected then lastLeaderSpell={name=name,words=words,at=getTime()} end
  if not settings.enabled then report(nil,'Combo OFF: activa el interruptor principal.');return end
  local message=normalized(text)
  if settings.commandsEnabled then
    if message=='ue' then triggerCombo(getCurrentTarget(),'command','spell',name);return end
    local command,targetName=text:match('^%s*([%a]+)%s*,%s*(.+)$')
    command=lower(command)
    if command=='sd' or command=='att' then
      local creature=getCreatureByName(trim(targetName))
      if creature then
        if command=='att' then markLeaderTarget(creature) else triggerCombo(creature,'command','rune',name) end
      else report(nil,'Objetivo del comando no visible.') end
      return
    end
  end
  if not settings.textEnabled then report(nil,'Voz OFF en Ajustes.');return end
  local matches=settings.triggerMode=='list' and textMatchesTrigger(text,settings.spellTriggerText)
    or settings.triggerMode=='offensive' and ultimateSpell(text)
  -- A packet may carry several spell lines. Evaluate each formula separately.
  if not matches and text:find('[\r\n]') then
    for line in text:gmatch('[^\r\n]+')do
      if settings.triggerMode=='list' and textMatchesTrigger(line,settings.spellTriggerText)
        or settings.triggerMode=='offensive' and ultimateSpell(line) then matches=true;break end
    end
  end
  if matches then triggerCombo(getCurrentTarget(),'voice','spell',name);return end
  local prefix=tostring(settings.textPrefix or '.')
  if prefix~='' and text:sub(1,#prefix)==prefix then
    local creature=getCreatureByName(trim(text:sub(#prefix+1)))
    if creature then markLeaderTarget(creature) else report(nil,'Objetivo del prefijo no visible.') end
  elseif detected then report(nil,settings.triggerMode=='offensive' and 'Spell recibido; no es una UE del modo Solo UE.' or 'Spell recibido fuera de tu lista personalizada.')
  else report(nil,'Texto recibido; no coincide con un disparador.') end
end)

macro(200, function()
  refreshMaster()
  refreshTargetSync()
  pruneRecentWallShots()
  refreshDiagnostics()
end)
refreshDiagnostics()
