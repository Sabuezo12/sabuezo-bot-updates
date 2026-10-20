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
local MW_SIDE_SPREAD_LIMIT = 4

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
  followName = "",
  followDistance = 1,
  followIgnoreFields = false,
  commandsEnabled = true
}

for key, value in pairs(defaults) do
  if settings[key] == nil then
    settings[key] = value
  end
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
local rightPanel = comboPlusWindow.wallPage.body
local followPanel = comboPlusWindow.followPage.body
local optionsPanel = comboPlusWindow.optionsPage.body
local showLeaderPicker, learnLastSpell, refreshDiagnostics
local diagnostic = {signal='Sin senal recibida', result='Selecciona un lider y tu respuesta.'}
local lastLeaderSpell, pendingSpell
local function report(signal, result)
  if signal then diagnostic.signal=signal end
  if result then diagnostic.result=result end
end
local stopDistanceFollow
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
  for _,id in ipairs({'combo','options','wall','follow'})do
    comboPlusWindow[id..'Page']:setVisible(id==name)
    comboPlusWindow.tabs[id]:setOn(id==name)
    comboPlusWindow[id..'Scroll']:setVisible(id==name)
  end
end
for _,id in ipairs({'combo','options','wall','follow'})do
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
  widget.item:setItemId(tonumber(settings[id]) or defaultItem)
  widget.item.onItemChange = function(itemWidget)
    settings[id] = itemWidget:getItemId()
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
applyTooltip(comboPlusWindow, "Combo unificado: ataque por leader, comandos y magic wall al lado.")

addSection("1. Elige al lider",leftPanel)
local leaderRow=UI.createWidget('ComboPlusLeaderRow',leftPanel)
leaderRow:setId('leader1')
leaderRow.textEdit:setText(tostring(settings.leader1 or ''))
leaderRow.textEdit.onTextChange=function(_,text) settings.leader1=text;lastLeaderSpell=nil end
leaderRow.choose.onClick=function() if showLeaderPicker then showLeaderPicker(leaderRow.choose) end end
applyTooltip(leaderRow.choose,'Elige un jugador visible o escribe su nombre.\nLos alternativos estan en Ajustes.')
addSection("2. Detectar spells (voz)",leftPanel)
local triggerRow=UI.createWidget('ComboPlusTriggerRow',leftPanel)
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
local triggerEdit=addTextEdit('spellTriggerText','Lista personalizada (separada por comas)','',leftPanel)
local learnButton=UI.createWidget('HelperThemeButton',leftPanel)
learnButton:setId('learnSpell');learnButton:setText('Agregar ultimo spell del lider a la lista')
learnButton:setHeight(22)
learnButton.onClick=function()if learnLastSpell then learnLastSpell()end end
addSection("3. Tu respuesta",leftPanel)
addCheckBox('comboSpellEnabled','Lanzar mi spell',false,leftPanel)
addTextEdit('comboSpell','Formula de mi spell','',leftPanel,'Escribe un spell de tu vocacion.\nPuede ser distinto del spell del lider.')
addCheckBox('comboRuneEnabled','Lanzar mi runa',true,leftPanel)
addItem('comboRuneId','Runa',DEFAULT_COMBO_RUNE_ID,leftPanel)

addSection('Senales y seguridad',optionsPanel)
addCheckBox('textEnabled','Detectar UE / lista por voz',true,optionsPanel)
addCheckBox('missileEnabled','Detectar SD del lider',true,optionsPanel,'Solo acepta el proyectil de SD configurado.\nFlechas, bolts, wand y otros proyectiles no activan el combo.')
addTextEdit('sdMissileId','ID del proyectil de SD',32,optionsPanel,'ID de animacion, no el ID de la runa.\nReferencia estandar: 32. Solo cambialo si el servidor usa otro.')
addCheckBox('attackTargetEnabled','Marcar el objetivo observado',true,optionsPanel,'En un proyectil usa la criatura de destino.\nPor voz usa tu objetivo actual; no puede leer el target remoto.')
addCheckBox('ignoreFriends','Proteger amigos',true,optionsPanel)
addScrollBar('comboCooldown','Separacion minima (ms)',0,1000,100,optionsPanel)
addSection('Lideres alternativos',optionsPanel)
addTextEdit('leader2','Lider alternativo 2','',optionsPanel)
addTextEdit('leader3','Lider alternativo 3','',optionsPanel)
addSection('Comandos del lider',optionsPanel)
addCheckBox('commandsEnabled','Aceptar ue / sd,nombre / att,nombre',true,optionsPanel,'Solo acepta tus lideres.\nue / sd,nombre solicitan su accion. att,nombre solo marca target.')
addTextEdit('textPrefix','Prefijo de objetivo','.',optionsPanel,'Ejemplo: .NombreDelTarget.\nSolo marca target; no lanza spell ni runa por si mismo.')
local targetHint=UI.createWidget('ComboPlusHint',optionsPanel)
targetHint:setText('UE por voz: usa tu target actual para la runa.\nSD: obtiene el target de su proyectil. Los ataques normales se ignoran.\nEl estado muestra solicitudes y ecos; el servidor decide su ejecucion.')

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
settings.followDistance=math.max(1,math.min(5,math.floor(tonumber(settings.followDistance) or 1)))
addScrollBar("followDistance", "Separacion (SQM)", 1, 5, 1, followPanel, "Distancia deseada de 1 a 5 SQM.\nEn escaleras se acerca para cruzar y recupera la separacion al ver al leader.")
addCheckBox("followIgnoreFields", "Permitir cruzar fields", false, followPanel, "Permite caminar sobre fire, energy y poison si el camino lo necesita.")
local followStatus=addSection("Seguimiento apagado",followPanel)
followStatus:setId('followStatus')
local followHint=UI.createWidget('ComboPlusHint',followPanel)
followHint:setText('1 SQM conserva el follow nativo. De 2 a 5 mantiene la separacion con pasos controlados.\nSi el leader cambia de piso, intenta recuperar su ultimo punto visible.')

addSection("Responder a las Magic Walls del leader",rightPanel)
addCheckBox("mwComboEnabled", "Combo Magic Wall", false, rightPanel)
addModeButtons("mwPattern", "Distribucion de paredes", "auto", rightPanel, "Auto responde a los lados.\nSemicirculo rodea la MW del leader.")
addItem("mwRuneId", "Runa de Magic Wall", DEFAULT_MW_RUNE_ID, rightPanel)
addSection("Objetos de pared del servidor",rightPanel)
addItem("mwObjectId", "Objeto principal", DEFAULT_MW_OBJECT_ID, rightPanel)
addItem("mwObjectId2", "Objeto alternativo 2", DEFAULT_MW_OBJECT_ID_2, rightPanel)
addItem("mwObjectId3", "Objeto alternativo 3", DEFAULT_MW_OBJECT_ID_3, rightPanel)
addTextEdit("mwSide", "Lado: auto / izquierda / derecha", "auto", rightPanel)
addSection("Tiempos",rightPanel)
addScrollBar("mwReactDelay", "Reaccion (ms)", 0, 500, 80, rightPanel)
addScrollBar("mwCooldown", "Pausa entre paredes (ms)", 200, 2000, 1000, rightPanel)

local recentWallShots = {}
local comboBurst
local lastMwAt = 0
local followPositions = {}
local activeFollowName = ""
local lastFollowPosition = nil
local lastFollowTransitionPosition = nil
local lastFollowWalkAt = 0
local lastFollowUseAt = 0
local lastFollowProgressAt = 0
local lastPlayerPositionKey = ""
local followWasActive = false
local lastFollowSeenAt = 0
local lastFollowTransitionAt = 0
local lastFollowRecoveryAt = 0
local followFreedAfterLost = false
local spacingLastStepAt = 0
local spacingWasActive = false
local lastFollowStatus = ''
local function setFollowStatus(text)
  if text~=lastFollowStatus then followStatus:setText(text);lastFollowStatus=text end
end
stopDistanceFollow=function()
  -- Spacing sends one checked step, never a queued native follow/autowalk.
  spacingWasActive=false;spacingLastStepAt=0
end
local FOLLOW_STICKY_WALK_RETRY_MS = 150
local FOLLOW_STUCK_RECOVERY_MS = 550
local FOLLOW_TRANSITION_RECOVERY_MS = 180
local FOLLOW_TRANSITION_TTL_MS = 8000
local FOLLOW_LOST_FREE_MS = 8000
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

local function resetFollowMemoryIfNeeded()
  local name = lower(getFollowName())
  if activeFollowName == name then return end
  activeFollowName = name
  followPositions = {}
  lastFollowPosition = nil
  lastFollowTransitionPosition = nil
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
  if g_game and g_game.follow then
    local ok = pcall(function() g_game.follow(creature) end)
    if ok then return true end
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
    local ok = pcall(function() g_game.walk(dir, false) end)
    if ok then
      lastFollowWalkAt = time
      return true
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

local function tryUseFollowTransition(pos, force)
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
  local tiles = followUseTilesAround(pos)

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

local function walkToFollowPosition(pos, precision)
  local currentZ = getPlayerZ()
  if not hasPosition(pos) or not currentZ or pos.z ~= currentZ then return false end
  local time = getTime()
  local walkingCooldown = precision and precision > 0 and 250 or 500
  if player and player.isWalking and player:isWalking() and time - lastFollowWalkAt < walkingCooldown then return true end
  precision = precision or 0

  if CaveBot and CaveBot.walkTo then
    local ok, walking = pcall(function()
      return CaveBot.walkTo(pos, 50, {
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
    local ok = pcall(function()
      autoWalk(pos, 50, {
        ignoreFields = settings.followIgnoreFields == true,
        ignoreNonPathable = true,
        precision = precision,
        ignoreStairs = false
      })
    end)
    if ok then
      lastFollowWalkAt = time
      return true
    end
  end

  if player and player.autoWalk then
    local ok = pcall(function() player:autoWalk(pos) end)
    if ok then
      lastFollowWalkAt = time
      return true
    end
  end

  return false
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

  if distance > 1 and walkToFollowPosition(pos, 1) then return true end
  if distance <= 1 and stepIntoFollowPosition(pos) then return true end
  if distance <= 2 and tryUseFollowTransition(pos, urgent) then return true end
  if distance > 1 then return walkToFollowPosition(pos, 0) end
  return false
end

local function followVisibleTarget(creature)
  if not creature then return false end
  local targetPos = copyPosition(creature:getPosition())
  rememberFollowPosition(targetPos)
  if not targetPos or targetPos.z ~= getPlayerZ() then return false end

  local time = getTime()
  local playerPos = getPlayerPosition()
  local followDistance = distanceBetween(playerPos, targetPos)
  lastFollowSeenAt = time
  followFreedAfterLost = false

  local desired=math.max(1,math.min(5,math.floor(tonumber(settings.followDistance) or 1)))
  if desired>1 then
    local following=getFollowingCreature()
    if following and g_game and g_game.cancelFollow then pcall(g_game.cancelFollow) end
    local movement=TargetBot and TargetBot.Movement
    if movement and movement.isManual and movement.isManual() then
      stopDistanceFollow();setFollowStatus('Pausa: movimiento manual');return true
    end
    local safety=TargetBot and TargetBot.Antitrap
    if safety and safety.ownsMovement and safety.ownsMovement() then
      setFollowStatus('Pausa: escape de seguridad');return true
    end
    if followDistance==desired then
      stopDistanceFollow();setFollowStatus('Separacion: '..desired..' SQM');return true
    end
    local duration=player and player.getStepDuration and tonumber(player:getStepDuration()) or 150
    local interval=math.max(100,math.min(350,duration or 150))
    if spacingWasActive and time-spacingLastStepAt<interval then return true end
    spacingLastStepAt=time;spacingWasActive=true
    local function safeTile(p)
      if p.x<0 or p.y<0 or p.x>65535 or p.y>65535 then return false end
      local tile=g_map.getTile(p)
      if not tile or not tile:isWalkable(false) then return false end
      if tile.getCreatures and #tile:getCreatures()>0 then return false end
      if movement and movement.floorSafe then return movement.floorSafe(p,tile) end
      local color=tonumber(g_map.getMinimapColor and g_map.getMinimapColor(p)) or 0
      return not (tile.hasElevation and tile:hasElevation(3)) and not (color>=210 and color<=213)
    end
    local goals={}
    if followDistance>desired then goals[1]={pos=targetPos,precision=desired}
    else
      for dx=-desired,desired do for dy=-desired,desired do
        if math.max(math.abs(dx),math.abs(dy))==desired then
          local p={x=targetPos.x+dx,y=targetPos.y+dy,z=targetPos.z}
          if safeTile(p) then goals[#goals+1]={pos=p,precision=0} end
        end
      end end
      table.sort(goals,function(a,b)
        local da,db=distanceBetween(playerPos,a.pos),distanceBetween(playerPos,b.pos)
        if da~=db then return da<db end
        if a.pos.x~=b.pos.x then return a.pos.x<b.pos.x end
        return a.pos.y<b.pos.y
      end)
    end
    local directions={{0,-1},{1,0},{0,1},{-1,0},{1,-1},{1,1},{-1,1},{-1,-1}}
    for i=1,math.min(3,#goals)do
      local goal=goals[i]
      local path=type(getPath)=='function' and getPath(playerPos,goal.pos,50,{
        precision=goal.precision,ignoreFields=settings.followIgnoreFields==true,
        ignoreNonPathable=false,ignoreStairs=false,allowOnlyVisibleTiles=true})
      local direction=path and path[1]
      local offset=direction and directions[direction+1]
      if offset then
        local nextPos={x=playerPos.x+offset[1],y=playerPos.y+offset[2],z=playerPos.z}
        local nextDistance=distanceBetween(nextPos,targetPos)
        local diagonal=offset[1]~=0 and offset[2]~=0
        local corners=not diagonal or safeTile({x=nextPos.x,y=playerPos.y,z=playerPos.z}) and safeTile({x=playerPos.x,y=nextPos.y,z=playerPos.z})
        if safeTile(nextPos) and corners and (followDistance>=desired or nextDistance>=followDistance) then
          if CaveBot and CaveBot.protectStep and not CaveBot.protectStep(direction) then
            setFollowStatus('Pausa: paso protegido');return true
          end
          local sent=false
          if type(safeBotWalk)=='function' then sent=safeBotWalk(direction)~=false
          elseif g_game and g_game.walk then sent=pcall(g_game.walk,direction) end
          if sent then setFollowStatus('Ajustando a '..desired..' SQM');return true end
        end
      end
    end
    setFollowStatus('Sin camino seguro para '..desired..' SQM');return true
  end
  stopDistanceFollow()
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

local function chaseFollowName()
  if CaveBot and CaveBot.Flee and CaveBot.Flee.blocksCombat() then return end
  if not settings.enabled or not settings.followEnabled then
    stopDistanceFollow()
    setFollowStatus(settings.enabled and 'Seguimiento apagado' or 'Combo apagado')
    if followWasActive and g_game and g_game.cancelFollow then
      pcall(function() g_game.cancelFollow() end)
    end
    followWasActive = false
    return
  end
  followWasActive = true

  resetFollowMemoryIfNeeded()
  local name = getFollowName()
  if name == "" then
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

  cancelWrongFollow(name)

  local followTarget = getCreatureByName(name)
  if followTarget then
    if followVisibleTarget(followTarget) then return end
  end

  if lastFollowSeenAt > 0 and time - lastFollowSeenAt > FOLLOW_LOST_FREE_MS then
    setFollowStatus('Leader perdido: esperando que reaparezca')
    if not followFreedAfterLost and g_game and g_game.cancelFollow then
      pcall(function() g_game.cancelFollow() end)
    end
    followFreedAfterLost = true
    return
  end

  local currentZ = getPlayerZ()
  local lastPos = currentZ and followPositions[currentZ]
  if lastFollowTransitionPosition and lastFollowTransitionPosition.z == currentZ then
    lastPos = lastFollowTransitionPosition
  end
  if not lastPos and lastFollowPosition and lastFollowPosition.z == currentZ then
    lastPos = lastFollowPosition
  end
  if lastPos then
    stopDistanceFollow()
    setFollowStatus('Recuperando el ultimo punto / cambio de piso')
    local followDistance = distanceBetween(playerPos, lastPos)
    local urgent = isRecentFollowTransition(lastPos, time)
    local walking = false

    if urgent and followDistance <= 1 then
      if stepIntoFollowPosition(lastPos) then return end
      if tryUseFollowTransition(lastPos, true) then return end
    end

    walking = walkToFollowPosition(lastPos, 0)

    if not walking and followDistance > 1 then
      walking = walkToFollowPosition(lastPos, 1)
    end

    if followDistance <= 1 and time - lastFollowProgressAt > 300 then
      if stepIntoFollowPosition(lastPos) then return end
    end

    if not walking and followDistance <= 2 then
      tryUseFollowTransition(lastPos)
    end

    if followDistance == 0 and time - lastFollowProgressAt > 450 then
      tryUseFollowTransition(lastPos, true)
    end

    if followDistance <= 1 and time - lastFollowProgressAt > 850 then
      if not stepIntoFollowPosition(lastPos) then
        tryUseFollowTransition(lastPos, true)
      end
    end

    recoverFollowPath(lastPos, followDistance, urgent)
  else
    setFollowStatus('Esperando al jugador en pantalla')
  end
end

macro(50, function()
  chaseFollowName()
end)

onCreaturePositionChange(function(creature, newPos, oldPos)
  if not settings.enabled or not settings.followEnabled then return end
  if not isFollowCreature(creature) then return end
  if oldPos then rememberFollowPosition(oldPos) end
  if newPos then rememberFollowPosition(newPos) end
  if oldPos and newPos and oldPos.z ~= newPos.z then
    lastFollowTransitionAt = getTime()
    local playerZ = getPlayerZ()
    if oldPos.z == playerZ then
      lastFollowTransitionPosition = copyPosition(oldPos)
      followPositions[playerZ] = lastFollowTransitionPosition
    elseif newPos.z == playerZ then
      lastFollowTransitionPosition = copyPosition(newPos)
      followPositions[playerZ] = lastFollowTransitionPosition
    end
  end
  if oldPos and newPos and oldPos.z ~= newPos.z and type(schedule) == "function" then
    schedule(40, chaseFollowName)
    schedule(100, chaseFollowName)
    schedule(220, chaseFollowName)
    schedule(400, chaseFollowName)
    schedule(700, chaseFollowName)
  end
end)

onPlayerPositionChange(function(newPos, oldPos)
  if not settings.enabled or not settings.followEnabled or not oldPos or not newPos or oldPos.z == newPos.z then return end
  lastFollowTransitionPosition = nil
  if g_game and g_game.cancelFollow then
    pcall(function() g_game.cancelFollow() end)
  end
  lastFollowProgressAt = getTime()
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

-- One dispatcher for voice, projectiles and explicit leader commands. Sending
-- an API request or its speech echo is not proof of server-side damage.
local function triggerCombo(creature, signal, kind)
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
  local time=getTime()
  -- Group voice/projectile echoes per action, not the entire event. A voice
  -- response without a target may cast once, then its projectile can provide
  -- the missing rune target without repeating that spell.
  local gap=math.max(100,math.min(1000,tonumber(settings.comboCooldown) or 100))
  local grouped=comboBurst and (time-comboBurst.at<gap or signal~=comboBurst.signal and time-comboBurst.at<250)
  local burst=grouped and comboBurst or {at=time,signal=signal,spell=false,rune=false}
  local sent,blocked={},{}
  local marked=false
  local function markTarget()
    if marked then return end
    marked=true
    if creature and settings.attackTargetEnabled then
      local current=getCurrentTarget()
      if not current or not sameCreature(current,creature) then pcall(g_game.attack,creature) end
    end
  end
  local words=trim(settings.comboSpell)
  local spellRequested=kind~='rune' and settings.comboSpellEnabled and words~=''
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
  elseif kind~='rune' then blocked[#blocked+1]='spell OFF o formula vacia' end
  if kind~='spell' and settings.comboRuneEnabled then
    if burst.rune then blocked[#blocked+1]='runa ya solicitada'
    elseif not creature then blocked[#blocked+1]='sin target para la runa'
    else
      markTarget()
      if useItemWithId(settings.comboRuneId,creature) then sent[#sent+1]='runa';burst.rune=true
      else blocked[#blocked+1]='no se pudo solicitar la runa' end
    end
  elseif kind~='spell' then blocked[#blocked+1]='runa OFF' end
  if #sent>0 then
    comboBurst=burst
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
    local ok,result=pcall(g_game.attack,creature)
    if not ok or result==false then report(nil,'No se pudo marcar el objetivo.');return false end
  end
  report(nil,'Objetivo marcado; esperando UE o SD del lider.')
  return true
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
  elseif not settings.textEnabled and not settings.missileEnabled then config='Deteccion de UE y SD OFF'
  elseif not settings.comboSpellEnabled and not settings.comboRuneEnabled then config='Respuesta OFF: elige spell o runa'
  else config='Lider: '..table.concat(leaders,', ') end
  local value=config..'\n'..diagnostic.signal..'\n'..diagnostic.result
  if value~=lastDiagnosticText then
    lastDiagnosticText=value
    comboPlusWindow.status:setText(statusLine(config)..'\n'..statusLine(diagnostic.signal)..'\n'..statusLine(diagnostic.result))
    applyTooltip(comboPlusWindow.status,value)
  end
end

local function wallObjectIds()
  local ids = {}
  local function add(id)
    id = tonumber(id)
    if id and id > 0 and not table.find(ids, id) then
      table.insert(ids, id)
    end
  end
  add(settings.mwObjectId)
  add(settings.mwObjectId2)
  add(settings.mwObjectId3)
  add(2128)
  add(2129)
  add(2130)
  add(11754)
  return ids
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

local function addSideLineCandidates(candidates, seen, basePos, offset)
  if not offset or (offset.x == 0 and offset.y == 0) then return end
  for distance = 1, MW_SIDE_SPREAD_LIMIT do
    addCandidate(candidates, seen, basePos, {
      x = offset.x * distance,
      y = offset.y * distance
    })
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

local function getWallSideCandidates(wallPos, fromPos)
  local candidates = {}
  local seen = {}
  local dx = 0
  local dy = 0

  if hasPosition(fromPos) then
    dx = sign(wallPos.x - fromPos.x)
    dy = sign(wallPos.y - fromPos.y)
  end

  local left = {x = dy, y = -dx}
  local right = {x = -dy, y = dx}
  local side = lower(settings.mwSide)

  if (left.x ~= 0 or left.y ~= 0) and (right.x ~= 0 or right.y ~= 0) then
    local firstSide = left
    local secondSide = right

    if side == "left" or side == "izquierda" then
      firstSide = left
      secondSide = right
    elseif side == "right" or side == "derecha" then
      firstSide = right
      secondSide = left
    else
      local sideCandidates = {
        {offset = left, distance = distanceToPlayer({x = wallPos.x + left.x, y = wallPos.y + left.y, z = wallPos.z})},
        {offset = right, distance = distanceToPlayer({x = wallPos.x + right.x, y = wallPos.y + right.y, z = wallPos.z})}
      }
      table.sort(sideCandidates, function(a, b) return a.distance < b.distance end)
      firstSide = sideCandidates[1].offset
      secondSide = sideCandidates[2].offset
    end

    if isHalfCircleMwPattern() then
      addHalfCircleCandidates(candidates, seen, wallPos, {x = dx, y = dy}, firstSide, secondSide)
    else
      addSideLineCandidates(candidates, seen, wallPos, firstSide)
      addSideLineCandidates(candidates, seen, wallPos, secondSide)
    end
  end

  local fallback = {
    {x = 0, y = -1},
    {x = 1, y = 0},
    {x = 0, y = 1},
    {x = -1, y = 0}
  }
  table.sort(fallback, function(a, b)
    local posA = {x = wallPos.x + a.x, y = wallPos.y + a.y, z = wallPos.z}
    local posB = {x = wallPos.x + b.x, y = wallPos.y + b.y, z = wallPos.z}
    return distanceToPlayer(posA) < distanceToPlayer(posB)
  end)

  for _, offset in ipairs(fallback) do
    addCandidate(candidates, seen, wallPos, offset)
  end

  return candidates
end

local function castMwallBeside(wallPos, fromPos)
  if CaveBot and CaveBot.Flee and CaveBot.Flee.blocksCombat() then return end
  if not settings.enabled or not settings.mwComboEnabled then return false end
  if not hasPosition(wallPos) then return false end

  local time = getTime()
  if time - lastMwAt < (tonumber(settings.mwCooldown) or 1000) then return false end

  for _, castPos in ipairs(getWallSideCandidates(wallPos, fromPos)) do
    local tile = g_map.getTile(castPos)
    if canUseMwallOn(tile) then
      local thing = tile:getTopUseThing()
      if not thing and tile.getGround then
        thing = tile:getGround()
      end
      if not thing then
        thing = tile:getTopThing()
      end
      if thing and useItemWithId(settings.mwRuneId, thing) then
        lastMwAt = time
        return true
      end
    end
  end

  return false
end

local function pruneRecentWallShots()
  local time = getTime()
  for key, data in pairs(recentWallShots) do
    if not data.time or time - data.time > 1500 then
      recentWallShots[key] = nil
    end
  end
end

local function registerLeaderWallShot(destPos, fromPos)
  if not settings.mwComboEnabled or not hasPosition(destPos) then return end

  pruneRecentWallShots()
  local key = positionKey(destPos)
  local shotTime = getTime()
  recentWallShots[key] = {
    pos = copyPosition(destPos),
    from = copyPosition(fromPos),
    time = shotTime
  }

  local delayMs = tonumber(settings.mwReactDelay) or 80
  schedule(delayMs, function()
    local data = recentWallShots[key]
    if not data or data.time ~= shotTime then return end
    local tile = g_map.getTile(data.pos)
    if tileHasMagicWall(tile) then
      castMwallBeside(data.pos, data.from)
      recentWallShots[key] = nil
    end
  end)
end

onMissle(function(missile)
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
    triggerCombo(targetCreature,'projectile')
    return
  end

  registerLeaderWallShot(dest, src)
end)

onAddThing(function(tile, thing)
  if not settings.enabled or not settings.mwComboEnabled then return end
  if not tile or not thing or not thing:isItem() then return end
  if not table.find(wallObjectIds(), thing:getId()) then return end

  pruneRecentWallShots()
  local tilePos = tile:getPosition()
  local key = positionKey(tilePos)
  local data = recentWallShots[key]
  if not data then return end

  castMwallBeside(data.pos, data.from)
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
    if message=='ue' then triggerCombo(getCurrentTarget(),'command','spell');return end
    local command,targetName=text:match('^%s*([%a]+)%s*,%s*(.+)$')
    command=lower(command)
    if command=='sd' or command=='att' then
      local creature=getCreatureByName(trim(targetName))
      if creature then
        if command=='att' then markLeaderTarget(creature) else triggerCombo(creature,'command','rune') end
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
  if matches then triggerCombo(getCurrentTarget(),'voice');return end
  local prefix=tostring(settings.textPrefix or '.')
  if prefix~='' and text:sub(1,#prefix)==prefix then
    local creature=getCreatureByName(trim(text:sub(#prefix+1)))
    if creature then markLeaderTarget(creature) else report(nil,'Objetivo del prefijo no visible.') end
  elseif detected then report(nil,settings.triggerMode=='offensive' and 'Spell recibido; no es una UE del modo Solo UE.' or 'Spell recibido fuera de tu lista personalizada.')
  else report(nil,'Texto recibido; no coincide con un disparador.') end
end)

macro(200, function()
  refreshMaster()
  pruneRecentWallShots()
  refreshDiagnostics()
end)
refreshDiagnostics()
