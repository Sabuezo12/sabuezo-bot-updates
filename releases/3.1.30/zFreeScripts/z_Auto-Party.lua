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
    text: Configurar

  HelperThemeButton
    id: ptLeave
    text: Salir y pausar
    anchors.left: parent.left
    anchors.top: prev.bottom
    width: 100
    height: 17
    margin-top: 3
    color: #ee0000
    font: verdana-11px-antialised

  HelperThemePower
    id: ptShare
    text: Auto XP
    anchors.left: prev.right
    anchors.bottom: prev.bottom
    margin-left: 4
    height: 17
    width: 86
  
]], parent)

importStyle('/vBot/party_manager.otui')
if not HelperPartyContext then dofile('/vBot/party_context.lua') end
dofile('/vBot/party_engine.lua')
dofile('/vBot/party_report.lua')
dofile('/vBot/party_monitor.lua')
dofile('/vBot/party_echo.lua')
-- Extend both skin descriptors so newly added controls keep the current palette.
local controls={partySummary='HelperThemeLabel',membersTitle='HelperThemeLabel',partyInfo='HelperThemeButton',
 currentMember='HelperThemeCombo',kickMember='HelperThemeButton',passMember='HelperThemeButton',leaveParty='HelperThemeButton',
 addTeam='HelperThemeButton',messageListOnly='HelperThemeCheck',protectedTitle='HelperThemeLabel',protectedNames='HelperThemeInput',
 serverCommands='HelperThemeCheck',partyStatus='HelperThemeLabel',reinviteList='HelperThemeButton',
 autoEnabled='HelperThemeCheck',autoShare='HelperThemeCheck'}
local function extendSkin(styles)
 local desc=styles and styles.AutoPartyListWindow
 if not desc then return end
 desc.children=desc.children or{}
 local existing={};for _,child in ipairs(desc.children)do existing[child.id]=true end
 for id,kind in pairs(controls)do
  if not existing[id]then
   local base=styles[kind]or{}
   local props={};for k,v in pairs(base.props or{})do props[k]=v end
   desc.children[#desc.children+1]={id=id,type=kind,style=kind,props=props,states=base.states or{},children={}}
  end
 end
end
extendSkin(HelperAppearance and HelperAppearance.metadata and HelperAppearance.metadata.styles)
extendSkin(RinoSkin and RinoSkin.styles)

local defaults={leaderName='Leader',autoPartyList={},enabled=false,inviteTxt='party me',autoShare=false,
 onMsg=false,kickNoShare=false,passLeader=false,passLeaderName='',protectedNames='',messageListOnly=false,
 serverCommands=HelperClient and(HelperClient.id=='thornia'or HelperClient.id=='aurera')or false}
if type(storage.autoParty)~='table'then storage.autoParty={}end
local config=storage.autoParty
for k,v in pairs(defaults)do if config[k]==nil then config[k]=v end end
config.kickNoShareSeconds=math.max(15,math.min(3600,tonumber(config.kickNoShareSeconds)or(tonumber(config.kickNoShareMinutes)or 1)*60))
local normalize=HelperPartyEngine.normalize
if config.passLeaderName==''and config.passLeaderText and normalize(config.passLeaderText)~='pass leader'then
 config.passLeaderName=tostring(config.passLeaderText)
end
local seen,clean={},{}
for _,n in ipairs(type(config.autoPartyList)=='table'and config.autoPartyList or{})do
 local k=normalize(n)
 if type(n)=='string'and k~=''and not seen[k]then seen[k]=true;clean[#clean+1]=n:match('^%s*(.-)%s*$')end
end
config.autoPartyList=clean
local function timeMs()
 if type(now)=='number'then return now end
 if g_clock and type(g_clock.millis)=='function'then local ok,t=pcall(g_clock.millis);if ok then return tonumber(t)end end
end
local function localPlayer()return g_game.getLocalPlayer and g_game.getLocalPlayer()or player end
local function spectators()return getSpectators(false)or{}end
local partyEcho=HelperPartyEcho.new({time=timeMs,player=localPlayer,member=HelperPartyContext.isMember})
pcall(partyEcho.install)
local lastPartyCommandAt,shareMonitor
local function sendCommand(text)
 local sender=type(say)=='function'and say or g_game.talk
 if type(sender)~='function'then return false end
 local prepared,echo=pcall(partyEcho.prepare,text)
 if not prepared then echo=nil end
 local ok,result=pcall(sender,text)
 if ok and result~=false then lastPartyCommandAt=timeMs();return true end
 pcall(partyEcho.cancel,echo)
 return false
end
local function canSendPartyCommand(time)
 return not lastPartyCommandAt or time<lastPartyCommandAt or time-lastPartyCommandAt>=1500
end
local adapter={partyInfo=function()if shareMonitor then return shareMonitor.requestInfo()end;return sendCommand('!party')end,
 canAutoKick=canSendPartyCommand}
local function syncAdapter()
 adapter.kickMember=config.serverCommands and function(_,name)
  if type(name)~='string'or name==''or #name>80 or name:find('[%c!%%]')then return false end
  return sendCommand('!partykick '..name)
 end or nil
 adapter.leaveParty=config.serverCommands and function()return sendCommand('!partyexit')end or nil
end
syncAdapter()
local controller=HelperPartyEngine.new({config=config,game=g_game,adapter=adapter})
shareMonitor=HelperPartyMonitor.new({config=config,controller=controller,time=timeMs,player=localPlayer,send=sendCommand,canSend=canSendPartyCommand})
local window=UI.createWindow('AutoPartyListWindow',g_ui.getRootWidget())
window:hide()
local feedbackUntil=0
local function paintStatus(result,manual)
 if not result then return end
 local time=timeMs()or 0
 if manual then feedbackUntil=time+4000 elseif time<feedbackUntil then return end
 window.partyStatus:setText(result.message)
 window.partyStatus:setColor(result.kind=='warning'and'#e8b466'or result.kind=='success'and'#8ac976'or'#c6d6dc')
end
local function powers()
 autopartyui.status:setOn(config.enabled==true);window.autoEnabled:setChecked(config.enabled==true)
 autopartyui.ptShare:setOn(config.autoShare==true);window.autoShare:setChecked(config.autoShare==true)
end
local function reset()
 syncAdapter();controller.reset();powers()
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
local function addName(n)
 if type(n)~='string'or n:find('%c')then return false end
 n=n:match('^%s*(.-)%s*$')
 if n==''or #n>80 or listed(n)or #config.autoPartyList>=100 then return false end
 config.autoPartyList[#config.autoPartyList+1]=n;addRow(n);return true
end
for _,n in ipairs(config.autoPartyList)do addRow(n)end
window.addPlayer.onClick=function()addName(window.playerName:getText());window.playerName:setText('');reset()end
window.playerName.onTextChange=function(_,text)window.addPlayer:setColor(listed(text)and'red'or'green')end
window.playerName.onKeyPress=function(_,key)if key==5 then window.addPlayer.onClick();return true end;return false end

local rosterKey=nil
local function selected()
 local option=window.currentMember:getCurrentOption();return option and option.data or''
end
local function refreshButtons(snapshot)
 snapshot=snapshot or HelperPartyContext.snapshot()
 local target=snapshot.byName[normalize(selected())]
 local eligible=snapshot.leader==true and target~=nil and target.self~=true
 window.kickMember:setEnabled(eligible and controller.kickAvailable() and (config.serverCommands==true or type(target.id)=='number'))
 window.passMember:setEnabled(eligible and target.visible==true and type(g_game.partyPassLeadership)=='function')
 window.leaveParty:setEnabled(snapshot.inParty==true)
end
local function refreshParty()
 local snapshot=HelperPartyContext.snapshot()
 local summary=not snapshot.inParty and'Sin party.'or(#snapshot.members..' miembros | '..(snapshot.leader and'Lider'or'Miembro')..
  (snapshot.sharing and(snapshot.eligible and' | XP compartida'or' | XP pendiente')or' | XP desactivada'))
 window.partySummary:setText(summary)
 local fingerprint={tostring(snapshot.inParty),snapshot.ownName}
 for _,entry in ipairs(snapshot.members)do fingerprint[#fingerprint+1]=entry.name..':'..tostring(entry.shield)..':'..tostring(entry.visible)end
 local key=table.concat(fingerprint,'|')
 if rosterKey~=key then
  local before=selected();window.currentMember:clearOptions();window.currentMember:addOption('Selecciona un miembro','')
  for _,entry in ipairs(snapshot.members)do
   local label=entry.name..(entry.self and' [tu]'or'')..(entry.leader and' - Lider'or'')..
    (entry.visible and(entry.eligible==false and' - Sin share'or'')or' - Fuera de pantalla')
   window.currentMember:addOption(label,entry.name)
  end
  local current=snapshot.byName[normalize(before)]
  window.currentMember:setCurrentOptionByData(current and current.name or'');rosterKey=key
 end
 refreshButtons(snapshot)
 return snapshot
end
window.currentMember.onOptionChange=function()refreshButtons()end
local function request(action)
 HelperPartyContext.invalidate();local snapshot=HelperPartyContext.snapshot()
 if action=='leave'then config.enabled=false;powers()end
 local result=controller.request(action,localPlayer(),spectators(),selected(),timeMs(),snapshot)
 paintStatus(result,true);refreshParty()
end
window.partyInfo.onClick=function()request('info')end
window.kickMember.onClick=function()request('kick')end
window.passMember.onClick=function()request('pass')end
window.leaveParty.onClick=function()request('leave')end
autopartyui.ptLeave.onClick=window.leaveParty.onClick
window.addTeam.onClick=function()
 HelperPartyContext.invalidate();local count=0
 for _,entry in ipairs(HelperPartyContext.snapshot().members)do if not entry.self and addName(entry.name)then count=count+1 end end
 reset();paintStatus({message=count..' miembros agregados a la lista.'},true)
end
window.reinviteList.onClick=function()
 controller.reinvite();controller.resume();config.enabled=true;powers()
 paintStatus({message='Auto Party activo: se permiten de nuevo las invitaciones de tu lista.'},true)
end
local function toggle(widget,field,checkbox)
 widget.onClick=function()
  config[field]=not config[field]
  if field=='enabled'and config[field]then controller.resume()end
  if checkbox then widget:setChecked(config[field])else widget:setOn(config[field])end
  reset()
 end
 if checkbox then widget:setChecked(config[field]==true)else widget:setOn(config[field]==true)end
end
toggle(autopartyui.status,'enabled');toggle(autopartyui.ptShare,'autoShare')
toggle(window.autoEnabled,'enabled',true);toggle(window.autoShare,'autoShare',true)
for _,entry in ipairs({{'inviteMsg','onMsg'},{'kickNoShare','kickNoShare'},{'passLeader','passLeader'},
 {'messageListOnly','messageListOnly'},{'serverCommands','serverCommands'}})do toggle(window[entry[1]],entry[2],true)end
local function input(widget,field)
 widget:setText(tostring(config[field]or''))
 widget.onTextChange=function(_,text)config[field]=text:match('^%s*(.-)%s*$');reset()end
end
input(window.txtLeader,'leaderName');input(window.inviteTxt,'inviteTxt')
input(window.passLeaderName,'passLeaderName');input(window.protectedNames,'protectedNames')
window.kickNoShareMinutes:setText(tostring(config.kickNoShareSeconds))
window.kickNoShareMinutes.onTextChange=function(_,text)
 local number=tonumber(text)
 if number and number>=15 and number<=3600 then config.kickNoShareSeconds=math.floor(number);controller.reset()end
end
window.closeButton.onClick=function()window:hide()end
autopartyui.editPlayerList.onClick=function()HelperPartyContext.invalidate();refreshParty();powers();window:show();window:raise();window:focus()end
HelperAutoParty={controller=controller,window=window,panel=autopartyui,config=config,request=request,refreshParty=refreshParty,monitor=shareMonitor,echo=partyEcho}
macro(500,function()
 pcall(partyEcho.install)
 shareMonitor.poll()
 local result=controller.tick(localPlayer(),spectators(),timeMs())
 if shareMonitor.status then result={message=shareMonitor.status,kind='warning'}end
 refreshParty();paintStatus(result)
end)
onTalk(function(sender,level,mode,text)controller.talk(localPlayer(),spectators(),sender,text,timeMs())end)
refreshParty();reset()
UI.Separator()
