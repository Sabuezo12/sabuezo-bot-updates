setDefaultTab("Main")

local panelName = "ComboLeaderPlus"
storage[panelName] = storage[panelName] or {}
local settings = storage[panelName]

local DEFAULT_COMBO_RUNE_ID = 3155
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
    settings.missileEnabled = true
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

settings.missileEnabled = true

local root = g_ui.getRootWidget()
local comboPlusWindow = UI.createWindow("ComboPlusWindow", root)
comboPlusWindow:hide()
comboPlusWindow.closeButton.onClick = function()
  comboPlusWindow:hide()
end

local ui = setupUI([[
Panel
  height: 19

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('Combo Leader')

  Button
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

local leftPanel = comboPlusWindow.content.left
local rightPanel = comboPlusWindow.content.right

local function applyTooltip(widget, tooltip)
  if not widget or not tooltip or not widget.setTooltip then return end
  pcall(function()
    widget:setTooltip(tooltip)
  end)
end

local function addCheckBox(id, title, defaultValue, dest, tooltip)
  local widget = UI.createWidget("ComboPlusCheckBox", dest)
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

addTextEdit("leader1", "Leader 1", "", leftPanel, "Nombre principal del leader que dispara el combo.")
addTextEdit("leader2", "Leader 2", "", leftPanel, "Segundo leader permitido. Se usa si este player esta visible.")
addTextEdit("leader3", "Leader 3", "", leftPanel, "Tercer leader permitido para equipos con varios callers.")
addTextEdit("textPrefix", "Text Prefix", ".", leftPanel, "Prefijo para target por texto. Ejemplo: .NombreDelTarget.")
addTextEdit("spellTriggerText", "Spell Trigger", "", leftPanel, "Texto naranja/spell del leader que activa tu combo sobre tu target actual. Puedes poner varios separados por coma: exura, utito tempo.")
addCheckBox("textEnabled", "Detect Text", true, leftPanel, "Permite que el leader marque target escribiendo el prefijo y el nombre.")
addCheckBox("attackTargetEnabled", "Attack Target", true, leftPanel, "Cambia tu target al mismo player que marco el leader.")
addCheckBox("ignoreFriends", "Ignore Friends", true, leftPanel, "Evita atacar o tirar runa a players en tu friend list.")
addCheckBox("commandsEnabled", "Leader Commands", true, leftPanel, "Permite comandos del leader: ue, sd,nombre y att,nombre.")
addCheckBox("comboRuneEnabled", "Use Combo Rune", true, leftPanel, "Usa la runa configurada cuando se detecta un combo.")
addItem("comboRuneId", "Combo Rune", DEFAULT_COMBO_RUNE_ID, leftPanel, "Runa usada para el combo normal. Por defecto es SD.")
addCheckBox("comboSpellEnabled", "Cast Combo Spell", false, leftPanel, "Castea el spell configurado cuando se activa el combo.")
addTextEdit("comboSpell", "Combo Spell", "", leftPanel, "Spell que se dira al comboear. Ejemplo: exevo gran mas vis.")
addScrollBar("comboCooldown", "Combo Cooldown", 0, 1000, 100, leftPanel, "Tiempo minimo entre combos normales, en milisegundos.")
addSection("Follow", leftPanel, "Sigue a un player y recuerda el ultimo sqm visto por piso para escaleras.")
local followSwitch = addCheckBox("followEnabled", "Follow Enabled", false, leftPanel, "Activa el seguimiento automatico del player escrito en Follow Name.")
followSwitch.onClick = function()
  followSwitch:setOn(not followSwitch:isOn())
  settings.followEnabled = followSwitch:isOn()
  if not settings.followEnabled and g_game and g_game.cancelFollow then
    pcall(function() g_game.cancelFollow() end)
  end
end
addTextEdit("followName", "Follow Name", "", leftPanel, "Nombre del player que quieres seguir. Puede subir y bajar escaleras usando la ultima posicion vista.")

addCheckBox("mwComboEnabled", "Combo MW", false, rightPanel, "Si el leader tira una MW, intentas tirar otra MW al lado.")
addModeButtons("mwPattern", "MW Pattern", "auto", rightPanel, "Auto tira a los lados de la MW. Half Circle intenta formar un medio circulo delante de la MW del leader.")
addItem("mwRuneId", "MW Rune", DEFAULT_MW_RUNE_ID, rightPanel, "Runa que usara tu char para responder con magic wall.")
addItem("mwObjectId", "MW Object 1", DEFAULT_MW_OBJECT_ID, rightPanel, "ID principal del objeto de magic wall que aparece en el piso.")
addItem("mwObjectId2", "MW Object 2", DEFAULT_MW_OBJECT_ID_2, rightPanel, "ID alternativo de magic wall para servers con sprites/custom IDs.")
addItem("mwObjectId3", "MW Object 3", DEFAULT_MW_OBJECT_ID_3, rightPanel, "Tercer ID de wall. Puede usarse para otra MW custom o wild growth.")
addTextEdit("mwSide", "MW Side", "auto", rightPanel, "Lado para responder: auto, left/right o izquierda/derecha.")
addScrollBar("mwReactDelay", "MW React Delay", 0, 500, 80, rightPanel, "Delay antes de tirar tu MW despues de detectar la del leader.")
addScrollBar("mwCooldown", "MW Cooldown", 200, 2000, 1000, rightPanel, "Exhaust/cooldown minimo entre tus magic walls, en milisegundos.")

local recentWallShots = {}
local lastComboAt = 0
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

local function textMatchesTrigger(text, triggerText)
  local lowerText = lower(text)
  if lowerText == "" then return false end

  for phrase in tostring(triggerText or ""):gmatch("[^,;|\n]+") do
    phrase = lower(phrase)
    if phrase ~= "" and lowerText == phrase then
      return true
    end
  end

  return false
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
      autoWalk(pos, 50, {ignoreNonPathable = true, precision = precision, ignoreStairs = false})
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
  if not settings.enabled or not settings.followEnabled then
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
    if creature and creature:isPlayer() and isLeader(creature:getName()) then
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
    local ok = pcall(function()
      g_game.useWith(visibleItem, targetThing, subType)
    end)
    if ok then return true end
  end

  if g_game and g_game.useInventoryItemWith then
    local ok = pcall(function()
      g_game.useInventoryItemWith(itemId, targetThing, subType)
    end)
    if ok then return true end
  end

  if type(useWith) == "function" then
    local ok = pcall(function()
      useWith(itemId, targetThing, subType)
    end)
    if ok then return true end
  end

  return false
end

local function triggerComboOnCreature(creature, castSpellFromTrigger)
  if not settings.enabled or not creature then return false end
  if creature:isLocalPlayer() or isFriend(creature) then return false end

  local time = getTime()
  if time - lastComboAt < (tonumber(settings.comboCooldown) or 0) then return false end
  lastComboAt = time

  local currentTarget = getCurrentTarget()
  if settings.attackTargetEnabled and (not currentTarget or not sameCreature(currentTarget, creature)) then
    pcall(function() g_game.attack(creature) end)
  end

  if settings.comboRuneEnabled then
    useItemWithId(settings.comboRuneId, creature)
  end

  if castSpellFromTrigger == true and settings.comboSpellEnabled and trim(settings.comboSpell):len() > 0 then
    say(settings.comboSpell)
  end

  refreshLeaderFollowAfterCombat()
  return true
end

local function triggerComboWithoutTarget()
  if not settings.enabled then return false end
  if not settings.comboSpellEnabled or trim(settings.comboSpell):len() == 0 then return false end

  local time = getTime()
  if time - lastComboAt < (tonumber(settings.comboCooldown) or 0) then return false end
  lastComboAt = time

  say(settings.comboSpell)
  return true
end

local function triggerComboFromLeaderText(text)
  if not settings.textEnabled then return false end
  if not textMatchesTrigger(text, settings.spellTriggerText) then return false end

  local currentTarget = getCurrentTarget()
  if currentTarget then
    return triggerComboOnCreature(currentTarget, true)
  end

  return triggerComboWithoutTarget()
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
    triggerComboOnCreature(targetCreature)
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

onTalk(function(name, level, mode, text)
  if not settings.enabled or not isLeader(name) then return end

  if settings.commandsEnabled then
    local lowerText = lower(text)
    if lowerText == "ue" and trim(settings.comboSpell):len() > 0 then
      say(settings.comboSpell)
      return
    end

    local command, targetName = text:match("^([%a]+)%s*,%s*(.+)$")
    if command and targetName then
      command = lower(command)
      targetName = trim(targetName)
      local commandTarget = getCreatureByName(targetName)
      if commandTarget then
        if command == "sd" then
          useItemWithId(settings.comboRuneId, commandTarget)
          refreshLeaderFollowAfterCombat()
        elseif command == "att" then
          triggerComboOnCreature(commandTarget)
        end
      end
    end
  end

  if triggerComboFromLeaderText(text) then return end

  if not settings.textEnabled then return end
  local prefix = tostring(settings.textPrefix or ".")
  if prefix == "" then prefix = "." end
  if text:sub(1, prefix:len()) ~= prefix then return end

  local targetName = trim(text:sub(prefix:len() + 1))
  if targetName == "" then return end

  local textTarget = getCreatureByName(targetName)
  if textTarget then
    triggerComboOnCreature(textTarget)
  end
end)

macro(200, function()
  ui.title:setOn(settings.enabled == true)
  pruneRecentWallShots()
end)
