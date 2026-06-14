--[[
vBot Scripting Services / Serviços de script / Servicios de scripting:
Discord: F.Almeida#8019

(ENG) If you like it, consider making a donation:
(PT) Se você gostou, considere fazer uma doação:
(ESP) Si le gusta, considere hacer una donación:
https://www.paypal.com/donate/?business=8XSU4KTS2V9PN&no_recurring=0&item_name=OTC+AND+OTS+SCRIPTS&currency_code=USD


Original made by Lee#7225
https://trainorcreations.com/coding/otclient/27
--]]

-- ATTENTION:
-- Don't edit below this line unless you know what you're doing.
-- ATENÇÃO:
-- Não mexa em nada daqui para baixo, a não ser que saiba o que está fazendo.
-- ATENCIÓN:
-- No cambies nada desde aquí, solamente si sabes lo que estás haciendo.
setDefaultTab("Tools")
-- UI.Separator()

local autopartyui = setupUI([[
Panel
  height: 38

  BotSwitch
    id: status
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    height: 18
    text: Auto Party

  Button
    id: editPlayerList
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 18
    text: Setup

  Button
    id: ptLeave
    text: Leave Party
    anchors.left: parent.left
    anchors.top: prev.bottom
    width: 86
    height: 17
    margin-top: 3
    color: #ee0000
    font: verdana-11px-rounded

  BotSwitch
    id: ptShare
    text: Auto Share
    anchors.left: prev.right
    anchors.bottom: prev.bottom
    margin-left: 4
    height: 17
    width: 86
  ]], parent)

g_ui.loadUIFromString([[
AutoPartyName < Label
  background-color: alpha
  text-offset: 2 0
  focusable: true
  height: 16

  $focus:
    background-color: #00000055

  Button
    id: remove
    text: x
    anchors.right: parent.right
    margin-right: 15
    width: 15
    height: 15

AutoPartyListWindow < MainWindow
  text: Auto Party
  size: 220 430
  @onEscape: self:hide()

  Label
    id: lblLeader
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.right: parent.right
    text-align: center
    text: Leader Names

  TextEdit
    id: txtLeader
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: prev.bottom
    margin-top: 5
    tooltip: Escribe uno o varios leaders separados por coma o punto y coma. Ejemplo: Sabuezo, Rod Master, Aeron Knight

  Label
    id: lblParty
    anchors.left: parent.left
    anchors.top: prev.bottom
    anchors.right: parent.right
    margin-top: 5
    text-align: center
    text: Party List

  TextList
    id: lstAutoParty
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 5
    margin-bottom: 5
    padding: 1
    height: 100
    vertical-scrollbar: AutoPartyListListScrollBar
    tooltip: Lista de players permitidos para invitar automaticamente. Los leaders no van aqui, van arriba en Leader Names.

  VerticalScrollBar
    id: AutoPartyListListScrollBar
    anchors.top: lstAutoParty.top
    anchors.bottom: lstAutoParty.bottom
    anchors.right: lstAutoParty.right
    step: 14
    pixels-scroll: true

  TextEdit
    id: playerName
    anchors.left: parent.left
    anchors.top: lstAutoParty.bottom
    margin-top: 5
    width: 120
    tooltip: Nombre del player que quieres agregar a Party List.

  Button
    id: addPlayer
    text: +
    font: verdana-11px-rounded
    anchors.right: parent.right
    anchors.left: prev.right
    anchors.top: prev.top
    anchors.bottom: prev.bottom
    margin-left: 3
    tooltip: Agrega el nombre escrito a Party List.

  HorizontalSeparator
    id: separator
    anchors.right: parent.right
    anchors.left: parent.left
    anchors.top: prev.bottom
    margin-top: 8

  CheckBox
    id: inviteMsg
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: prev.bottom
    margin-top: 6
    text: Invite/Accept on Msg:
    tooltip: Si eres leader, invita al player que diga la frase. Si no eres leader, acepta party cuando uno de tus leaders diga la frase.

  TextEdit
    id: inviteTxt
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: inviteMsg.bottom
    margin-top: 5
    width: 148
    tooltip: Frase para invitar o aceptar party. No distingue mayusculas/minusculas. Si queda vacia, no hace nada.

  CheckBox
    id: kickNoShare
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: inviteTxt.bottom
    margin-top: 6
    text: Kick no share
    tooltip: Si eres leader, intenta expulsar miembros de party que duren demasiado sin shared exp activo.

  TextEdit
    id: kickNoShareMinutes
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: kickNoShare.bottom
    margin-top: 5
    width: 148
    tooltip: Minutos antes de expulsar a un miembro que no tenga shared exp. Minimo recomendado: 1.

  CheckBox
    id: passLeader
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: kickNoShareMinutes.bottom
    margin-top: 6
    text: Pass leader to name
    tooltip: Si eres party leader, transfiere automaticamente el liderazgo al player escrito abajo cuando este visible.

  TextEdit
    id: passLeaderName
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: passLeader.bottom
    margin-top: 5
    width: 148
    tooltip: Nombre exacto del player que recibira leader. Ejemplo: Rod Master. Debe estar visible y dentro de la party.

  HorizontalSeparator
    id: separator
    anchors.right: parent.right
    anchors.left: parent.left
    anchors.bottom: closeButton.top
    margin-bottom: 6

  Button
    id: closeButton
    text: Close
    font: cipsoftFont
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    size: 45 21

  Button
    id: info
    text: Credits
    font: cipsoftFont
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    size: 45 21
    color: yellow
    !tooltip: tr('Original made by Lee#7225\nModified by F.Almeida#8019')
    @onClick: g_platform.openUrl("https://www.paypal.com/donate/?business=8XSU4KTS2V9PN&no_recurring=0&item_name=OTC+AND+OTS+SCRIPTS&currency_code=USD")
]])

local panelName = "autoParty"

if not storage[panelName] then
  storage[panelName] = {
    leaderName = 'Leader',
    autoPartyList = {},
    enabled = false,
    inviteTxt = 'party me',
    autoShare = false,
    onMsg = false,
    kickNoShare = false,
    kickNoShareMinutes = 2,
    passLeader = false,
    passLeaderName = '',
  }
end

local config = storage[panelName]

local INVITE_COOLDOWN_MS = 5000
local JOIN_COOLDOWN_MS = 5000
local SHARE_COOLDOWN_MS = 3000
local KICK_COOLDOWN_MS = 10000
local PASS_LEADER_COOLDOWN_MS = 5000
local lastPartyAction = {}
local lastShareAt = 0
local noShareSince = {}
local missingKickWarned = false
local missingPassLeaderWarned = false

local function getTimeMs()
  if type(now) == "number" then return now end
  if g_clock and g_clock.millis then
    local ok, value = pcall(function() return g_clock.millis() end)
    if ok and type(value) == "number" then return value end
  end
  return os and os.clock and math.floor(os.clock() * 1000) or 0
end

local function trimText(value)
  return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function normalizeName(value)
  return trimText(value):lower()
end

if config.passLeaderName == nil then
  local oldPassText = trimText(config.passLeaderText)
  config.passLeaderName = oldPassText ~= "pass leader" and oldPassText or ""
end

local function getLeaderNames()
  local leaders = {}
  local seen = {}

  for rawName in tostring(config.leaderName or ""):gmatch("[^,;]+") do
    local name = trimText(rawName)
    local key = normalizeName(name)
    if key ~= "" and not seen[key] then
      seen[key] = true
      table.insert(leaders, key)
    end
  end

  return leaders
end

local function isLeaderName(name)
  local normalized = normalizeName(name)
  if normalized == "" then return false end

  for _, leaderName in ipairs(getLeaderNames()) do
    if leaderName == normalized then
      return true
    end
  end

  return false
end

local function isLocalLeader()
  return player and player.getName and isLeaderName(player:getName())
end

local function isPartyLeader()
  if player and player.isPartyLeader then
    local ok, result = pcall(function() return player:isPartyLeader() end)
    if ok then return result == true end
  end

  return player and player.getShield and player:getShield() == 4
end

local function isListedPlayer(name)
  local targetName = normalizeName(name)
  if targetName == "" then return false end

  for _, listedName in ipairs(config.autoPartyList or {}) do
    if normalizeName(listedName) == targetName then
      return true
    end
  end

  return false
end

local function canRunPartyAction(action, name, cooldown)
  local key = tostring(action or "") .. ":" .. normalizeName(name)
  local time = getTimeMs()
  if lastPartyAction[key] and time - lastPartyAction[key] < cooldown then
    return false
  end

  lastPartyAction[key] = time
  return true
end

local function invitePlayer(creature)
  if not creature or not g_game or not g_game.partyInvite then return end
  local name = creature:getName()
  if not canRunPartyAction("invite", name, INVITE_COOLDOWN_MS) then return end
  pcall(function() g_game.partyInvite(creature:getId()) end)
end

local function joinPlayerParty(creature)
  if not creature or not g_game or not g_game.partyJoin then return end
  local name = creature:getName()
  if not canRunPartyAction("join", name, JOIN_COOLDOWN_MS) then return end
  pcall(function() g_game.partyJoin(creature:getId()) end)
end

local function passPartyLeadership(creature)
  if not creature or not g_game or not g_game.partyPassLeadership then
    if not missingPassLeaderWarned then
      missingPassLeaderWarned = true
      warn("AutoParty: este cliente no expone una funcion compatible para transferir leader.")
    end
    return false
  end

  local name = creature:getName()
  if not canRunPartyAction("passleader", name, PASS_LEADER_COOLDOWN_MS) then return true end

  local ok = false
  if creature.getId then
    ok = pcall(function() g_game.partyPassLeadership(creature:getId()) end)
  end
  if ok then return true end

  ok = pcall(function() g_game.partyPassLeadership(creature) end)
  return ok
end

local function kickPartyMember(creature)
  if not creature or not g_game then return false end
  local name = creature:getName()
  if not canRunPartyAction("kick", name, KICK_COOLDOWN_MS) then return true end

  local kickMethods = {"partyKick", "partyKickMember", "partyKickPlayer", "partyRemoveMember", "partyRemove"}
  for _, method in ipairs(kickMethods) do
    if type(g_game[method]) == "function" then
      local ok = pcall(function() g_game[method](creature:getId()) end)
      if ok then return true end
    end
  end

  if not missingKickWarned then
    missingKickWarned = true
    warn("AutoParty: este cliente no expone una funcion compatible para expulsar miembros de party.")
  end
  return false
end

local function isSharedExpShield(shield)
  return shield == 5 or shield == 6
end

local function isNoSharedExpShield(shield)
  return shield == 3 or shield == 4 or shield == 7 or shield == 8 or shield == 9 or shield == 10
end

local function processNoShareKick(creature, time)
  if not config.kickNoShare or not isLocalLeader() then return end
  if not creature or creature == player or not creature:isPlayer() then return end
  if isLeaderName(creature:getName()) then return end
  if not creature:isPartyMember() then
    noShareSince[normalizeName(creature:getName())] = nil
    return
  end

  local shield = creature:getShield()
  local key = normalizeName(creature:getName())
  if key == "" then return end

  if isSharedExpShield(shield) then
    noShareSince[key] = nil
    return
  end

  if not isNoSharedExpShield(shield) then return end

  if not noShareSince[key] then
    noShareSince[key] = time
    return
  end

  local minutes = tonumber(config.kickNoShareMinutes) or 2
  if minutes < 1 then minutes = 1 end
  if time - noShareSince[key] >= minutes * 60000 then
    if kickPartyMember(creature) then
      noShareSince[key] = time
    end
  end
end

rootWidget = g_ui.getRootWidget()
if rootWidget then
  tcAutoParty = autopartyui.status
  tcAutoShare = autopartyui.ptShare

  autoPartyListWindow = UI.createWindow('AutoPartyListWindow', rootWidget)
  autoPartyListWindow:hide()

  autopartyui.editPlayerList.onClick = function(widget)
    autoPartyListWindow:show()
    autoPartyListWindow:raise()
    autoPartyListWindow:focus()
  end

  autopartyui.ptLeave.onClick = function(widget)
    if g_game and g_game.partyLeave then
      pcall(function() g_game.partyLeave() end)
    end
  end

  autoPartyListWindow.closeButton.onClick = function(widget)
    autoPartyListWindow:hide()
  end

  if config.autoPartyList and #config.autoPartyList > 0 then
    for _, pName in ipairs(config.autoPartyList) do
      local label = g_ui.createWidget("AutoPartyName", autoPartyListWindow.lstAutoParty)
      label.remove.onClick = function(widget)
        table.removevalue(config.autoPartyList, label:getText())
        label:destroy()
      end
      label:setText(pName)
    end
  end
  autoPartyListWindow.addPlayer.onClick = function(widget)
    local playerName = trimText(autoPartyListWindow.playerName:getText())
    if playerName:len() > 0 and not (isListedPlayer(playerName) or isLeaderName(playerName)) then
      table.insert(config.autoPartyList, playerName)
      local label = g_ui.createWidget("AutoPartyName", autoPartyListWindow.lstAutoParty)
      label.remove.onClick = function(widget)
        table.removevalue(config.autoPartyList, label:getText())
        label:destroy()
      end
      label:setText(playerName)
      autoPartyListWindow.playerName:setText('')
    end
  end

  autopartyui.status:setOn(config.enabled)
  autopartyui.status.onClick = function(widget)
    config.enabled = not config.enabled
    widget:setOn(config.enabled)
  end

  autopartyui.ptShare:setOn(config.autoShare)
  autopartyui.ptShare.onClick = function(widget)
    config.autoShare = not config.autoShare
    widget:setOn(config.autoShare)
  end

  autoPartyListWindow.inviteMsg:setChecked(config.onMsg)
  autoPartyListWindow.inviteMsg.onClick = function(widget)
    config.onMsg = not config.onMsg
    widget:setChecked(config.onMsg)
  end

  autoPartyListWindow.kickNoShare:setChecked(config.kickNoShare)
  autoPartyListWindow.kickNoShare.onClick = function(widget)
    config.kickNoShare = not config.kickNoShare
    widget:setChecked(config.kickNoShare)
    noShareSince = {}
  end

  autoPartyListWindow.kickNoShareMinutes.onTextChange = function(widget, text)
    local minutes = tonumber(text)
    if not minutes then return end
    if minutes < 1 then minutes = 1 end
    config.kickNoShareMinutes = minutes
  end
  autoPartyListWindow.kickNoShareMinutes:setText(tostring(config.kickNoShareMinutes or 2))

  autoPartyListWindow.passLeader:setChecked(config.passLeader)
  autoPartyListWindow.passLeader.onClick = function(widget)
    config.passLeader = not config.passLeader
    widget:setChecked(config.passLeader)
  end

  autoPartyListWindow.passLeaderName.onTextChange = function(widget, text)
    config.passLeaderName = trimText(text)
  end
  autoPartyListWindow.passLeaderName:setText(config.passLeaderName or '')

  autoPartyListWindow.playerName.onKeyPress = function(self, keyCode, keyboardModifiers)
    if not (keyCode == 5) then
      return false
    end
    autoPartyListWindow.addPlayer.onClick()
    return true
  end

  autoPartyListWindow.playerName.onTextChange = function(widget, text)
    if isListedPlayer(text) then
      autoPartyListWindow.addPlayer:setColor("red")
    else
      autoPartyListWindow.addPlayer:setColor("green")
    end
  end

  autoPartyListWindow.txtLeader.onTextChange = function(widget, text)
    config.leaderName = trimText(text)
  end
  autoPartyListWindow.txtLeader:setText(config.leaderName)

  autoPartyListWindow.inviteTxt.onTextChange = function(widget, text)
    config.inviteTxt = trimText(text)
  end
  autoPartyListWindow.inviteTxt:setText(config.inviteTxt)
  
  -- main loop
  macro(500,function()
    if not config.enabled then return true end

    local time = getTimeMs()
    local passLeaderName = normalizeName(config.passLeaderName)
    local lider = isLocalLeader()
    for s, spec in pairs(getSpectators()) do
      if spec:isPlayer() and spec ~= player then
        if config.passLeader and passLeaderName ~= "" and isPartyLeader() and normalizeName(spec:getName()) == passLeaderName then
          passPartyLeadership(spec)
        end
        processNoShareKick(spec, time)
        if lider then
          if spec:getShield() == 0 then
            if isListedPlayer(spec:getName()) then
              invitePlayer(spec)
            end
          end
        else
          if spec:getShield() == 1 then
           if isLeaderName(spec:getName()) then
            joinPlayerParty(spec)
           end
          end
        end
      end
    end
    if lider and config.autoShare then
      if time - lastShareAt >= SHARE_COOLDOWN_MS and not player:isPartySharedExperienceActive() then
        lastShareAt = time
        if g_game and g_game.partyShareExperience then
          pcall(function() g_game.partyShareExperience(true) end)
        end
      end
    end
  end)

  -- invite on msg
  onTalk(function(name, level, mode, text, channelId, pos)
    if not config.enabled then return true end
    local c = getCreatureByName(name)

    local inviteText = trimText(config.inviteTxt)
    if not config.onMsg or inviteText == "" then return true end
    if not tostring(text or ""):lower():find(inviteText:lower(), 1, true) then return true end
    if c then 
      if c:isPlayer() and c ~= player then
        if isLocalLeader() and c:getShield() == 0 then
          invitePlayer(c)
        elseif isLeaderName(c:getName()) and c:getShield() == 1 then
          joinPlayerParty(c)
        end
      end
    end
  end)
end

UI.Separator()
