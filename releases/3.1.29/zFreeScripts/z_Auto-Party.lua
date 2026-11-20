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

  HelperThemePower
    id: status
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    height: 18
    text: Auto Party

  HelperThemeButton
    id: editPlayerList
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 18
    text: Setup

  HelperThemeButton
    id: ptLeave
    text: Leave Party
    anchors.left: parent.left
    anchors.top: prev.bottom
    width: 86
    height: 17
    margin-top: 3
    color: #ee0000
    font: verdana-11px-antialised

  HelperThemePower
    id: ptShare
    text: Auto Share
    anchors.left: prev.right
    anchors.bottom: prev.bottom
    margin-left: 4
    height: 17
    width: 86
  
]], parent)

g_ui.loadUIFromString([[
AutoPartyName < HelperThemeLabel
  background-color: alpha
  text-offset: 2 0
  focusable: true
  height: 16

  $focus:
    background-color: #00000055

  HelperThemeButton
    id: remove
    text: x
    anchors.right: parent.right
    margin-right: 15
    width: 15
    height: 15

AutoPartyListWindow < HelperThemeWindow
  text: Auto Party
  size: 260 450
  @onEscape: self:hide()

  HelperThemeLabel
    id: lblLeader
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.right: parent.right
    text-align: center
    text: Leader Names

  HelperThemeInput
    id: txtLeader
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: prev.bottom
    margin-top: 5
    tooltip: Escribe uno o varios leaders separados por coma o punto y coma. Ejemplo: Sabuezo, Rod Master, Aeron Knight

  HelperThemeLabel
    id: lblParty
    anchors.left: parent.left
    anchors.top: prev.bottom
    anchors.right: parent.right
    margin-top: 5
    text-align: center
    text: Party List

  HelperThemeList
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

  HelperThemeInput
    id: playerName
    anchors.left: parent.left
    anchors.top: lstAutoParty.bottom
    margin-top: 5
    width: 120
    tooltip: Nombre del player que quieres agregar a Party List.

  HelperThemeButton
    id: addPlayer
    text: +
    font: verdana-11px-antialised
    anchors.right: parent.right
    anchors.left: prev.right
    anchors.top: prev.top
    anchors.bottom: prev.bottom
    margin-left: 3
    tooltip: Agrega el nombre escrito a Party List.

  HorizontalSeparator
    id: optionsSeparator
    anchors.right: parent.right
    anchors.left: parent.left
    anchors.top: prev.bottom
    margin-top: 8

  HelperThemeCheck
    id: inviteMsg
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: prev.bottom
    margin-top: 6
    text: Invite/Accept on Msg:
    tooltip: Invita al jugador visible que escriba exactamente la frase. Para aceptar, debe ser uno de tus leaders y haberte enviado una invitacion. No distingue mayusculas/minusculas.

  HelperThemeInput
    id: inviteTxt
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: inviteMsg.bottom
    margin-top: 5
    width: 148
    tooltip: Frase para invitar o aceptar party. No distingue mayusculas/minusculas. Si queda vacia, no hace nada.

  HelperThemeCheck
    id: kickNoShare
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: inviteTxt.bottom
    margin-top: 6
    text: Kick no share (60 s)
    tooltip: Espera 60 segundos continuos sin share. Requiere ser lider real, share activado y soporte de expulsion del cliente/servidor. Al recuperar share, desaparecer o apagar Auto Party, el contador se reinicia.

  HelperThemeLabel
    id: kickNoShareMinutes
    text: Espera: 1 minuto continuo
    height: 18
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: kickNoShare.bottom
    margin-top: 5
    width: 148
    tooltip: El tiempo es fijo: 60 segundos. Solo se cuenta mientras el miembro esta visible, sin share y en tu party. No se expulsa a los nombres protegidos de Leader Names.

  HelperThemeCheck
    id: passLeader
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: kickNoShareMinutes.bottom
    margin-top: 6
    text: Pass leader to name
    tooltip: Si eres el lider real, solicita pasar leader al nombre indicado, visible y ya dentro de tu party. Espera la confirmacion del servidor antes de otras acciones.

  HelperThemeInput
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

  HelperThemeLabel
    id: partyStatus
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: separator.top
    margin-bottom: 6
    height: 34
    text-wrap: true
    text: Auto Party desactivado.

  HelperThemeButton
    id: closeButton
    text: Close
    font: verdana-11px-antialised
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    size: 45 21

  HelperThemeButton
    id: info
    text: Credits
    font: verdana-11px-antialised
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    size: 45 21
    color: yellow
    !tooltip: tr('Original made by Lee#7225\nModified by F.Almeida#8019')
    @onClick: g_platform.openUrl("https://www.paypal.com/donate/?business=8XSU4KTS2V9PN&no_recurring=0&item_name=OTC+AND+OTS+SCRIPTS&currency_code=USD")
]])

dofile('/vBot/party_engine.lua')
local defaults={leaderName='Leader',autoPartyList={},enabled=false,inviteTxt='party me',
 autoShare=false,onMsg=false,kickNoShare=false,kickNoShareMinutes=1,passLeader=false,passLeaderName=''}
if type(storage.autoParty)~='table'then storage.autoParty={}end
local config=storage.autoParty
for k,v in pairs(defaults)do if config[k]==nil then config[k]=v end end
local normalize=HelperPartyEngine.normalize
if config.passLeaderName==''and config.passLeaderText and normalize(config.passLeaderText)~='pass leader'then
 config.passLeaderName=tostring(config.passLeaderText)
end
config.kickNoShareMinutes=1 -- User-selected policy: exactly one continuous minute.
local seen,clean={},{}
for _,n in ipairs(type(config.autoPartyList)=='table'and config.autoPartyList or{})do
 local k=normalize(n)
 if type(n)=='string'and k~=''and not seen[k]then seen[k]=true;clean[#clean+1]=n:gsub('^%s+',''):gsub('%s+$','')end
end
config.autoPartyList=clean
local controller=HelperPartyEngine.new({config=config,game=g_game,adapter=HelperPartyActions})
local root=g_ui.getRootWidget()
local window=UI.createWindow('AutoPartyListWindow',root)
window:hide()
local function timeMs()
 if type(now)=='number'then return now end
 if g_clock and type(g_clock.millis)=='function'then
  local ok,t=pcall(g_clock.millis);if ok and type(t)=='number'then return t end
 end
end
local function localPlayer()
 return g_game.getLocalPlayer and g_game.getLocalPlayer()or player
end
local function spectators()return getSpectators()or{}end
local function paintStatus(result)
 if not result then return end
 window.partyStatus:setText(result.message)
 window.partyStatus:setColor(result.kind=='warning'and'#e8b466'or result.kind=='success'and'#8ac976'or'#c6d6dc')
end
local function reset()
 controller.reset()
 paintStatus({message=config.enabled and'Auto Party listo.'or'Auto Party desactivado.'})
end
local function listed(text)
 local k=normalize(text)
 for _,n in ipairs(config.autoPartyList)do if normalize(n)==k then return true end end
 for n in tostring(config.leaderName):gmatch('[^,;]+')do if normalize(n)==k then return true end end
 return false
end
local function addRow(n)
 local row=g_ui.createWidget('AutoPartyName',window.lstAutoParty);row:setText(n)
 row.remove.onClick=function()
  for i=#config.autoPartyList,1,-1 do if normalize(config.autoPartyList[i])==normalize(n)then table.remove(config.autoPartyList,i)end end
  row:destroy();reset()
 end
end
for _,n in ipairs(config.autoPartyList)do addRow(n)end
window.addPlayer.onClick=function()
 local n=window.playerName:getText():gsub('^%s+',''):gsub('%s+$','')
 if n~=''and not listed(n)then config.autoPartyList[#config.autoPartyList+1]=n;addRow(n);reset()end
 window.playerName:setText('')
end
window.playerName.onTextChange=function(_,text)window.addPlayer:setColor(listed(text)and'red'or'green')end
window.playerName.onKeyPress=function(_,key)
 if key==5 then window.addPlayer.onClick();return true end
 return false
end
autopartyui.editPlayerList.onClick=function()window:show();window:raise();window:focus()end
window.closeButton.onClick=function()window:hide()end
autopartyui.ptLeave.onClick=function()
 reset()
 if type(g_game.partyLeave)=='function'then pcall(g_game.partyLeave)end
end
local function power(widget,field)
 widget:setOn(config[field]==true)
 widget.onClick=function()config[field]=not config[field];widget:setOn(config[field]);reset()end
end
power(autopartyui.status,'enabled');power(autopartyui.ptShare,'autoShare')
local function check(widget,field)
 widget:setChecked(config[field]==true)
 widget.onClick=function()config[field]=not config[field];widget:setChecked(config[field]);reset()end
end
check(window.inviteMsg,'onMsg');check(window.kickNoShare,'kickNoShare');check(window.passLeader,'passLeader')
local function input(widget,field)
 widget:setText(tostring(config[field]or''))
 widget.onTextChange=function(_,text)config[field]=text:gsub('^%s+',''):gsub('%s+$','');reset()end
end
input(window.txtLeader,'leaderName');input(window.inviteTxt,'inviteTxt');input(window.passLeaderName,'passLeaderName')
local kickHelp='Espera 60 s continuos sin share. Al recuperar share o dejar de estar visible se reinicia. Los leaders configurados y el destinatario de Pass Leader estan protegidos.'
if not controller.kickAvailable()then kickHelp=kickHelp..' Este cliente no ofrece expulsar miembros; se mostrara el aviso sin enviar otras acciones.'end
window.kickNoShare:setTooltip(kickHelp)
HelperAutoParty={controller=controller,window=window,panel=autopartyui,config=config}
macro(500,function()paintStatus(controller.tick(localPlayer(),spectators(),timeMs()))end)
onTalk(function(sender,level,mode,text)
 controller.talk(localPlayer(),spectators(),sender,text,timeMs())
end)
reset()
UI.Separator()
