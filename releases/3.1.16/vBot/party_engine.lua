-- Shared party controller. Only client-confirmed shields establish roles.
-- Native action success means a request was sent, never server confirmation.
HelperPartyEngine={}
local E=HelperPartyEngine
local leaders={[4]=true,[6]=true,[8]=true,[10]=true}
local members={[3]=true,[5]=true,[7]=true,[9]=true}
local sharedEnabled={[6]=true,[8]=true,[10]=true}
local noShare={[7]=true,[9]=true}
local kickMethods={'partyKick','partyKickMember','partyKickPlayer','partyRemoveMember','partyRemove'}
local function trim(s)return tostring(s or''):gsub('^%s+',''):gsub('%s+$','')end
local function key(s)return trim(s):lower()end
local function call(object,name,...)
 if not object or type(object[name])~='function'then return end
 local ok,value=pcall(object[name],object,...);if ok then return value end
end
local function id(c)
 local n=call(c,'getId');if type(n)=='number'and n>0 and n==math.floor(n)then return n end
end
local function player(c)return c and call(c,'isPlayer')==true and id(c)~=nil end
local function name(c)return trim(call(c,'getName'))end
local function shield(c)return call(c,'getShield')end
local function listNames(text)
 local out,seen={},{}
 for raw in tostring(text or''):gmatch('[^,;]+')do
  local k=key(raw);if k~=''and not seen[k]then out[#out+1]=k;seen[k]=true end
 end
 return out,seen
end
E.normalize=key
function E.new(options)
 local C={timers={},actions={},pending=nil,lastTick=nil,lastLocal=nil,blockedInvites={}}
 local game=options.game or{}
 local function config()return options.config end
 local function status(text,kind)return{message=text,kind=kind or'info'}end
 function C.reset()
  C.timers={};C.actions={};C.pending=nil;C.lastTick=nil;C.lastLocal=nil;C.blockedInvites={}
 end
 function C.kickAvailable()
  local adapter=options.adapter
  if adapter and type(adapter.kickMember)=='function'then return true end
  for _,method in ipairs(kickMethods)do if type(game[method])=='function'then return true end end
  return false
 end
 local function native(method,...)
  if type(game[method])~='function'then return false,'unavailable'end
  local ok,result=pcall(game[method],...)
  return ok and result~=false,ok and'rejected'or'error'
 end
 local function ready(action,target,time,delay)
  local k=action..':'..tostring(target)
  local previous=C.actions[k]
  if previous and time-previous<delay then return false end
  C.actions[k]=time;return true
 end
 local function kick(c)
  local adapter=options.adapter
  if adapter and type(adapter.kickMember)=='function'then
   local ok,result=pcall(adapter.kickMember,id(c),name(c));return ok and result~=false
  end
  -- Choose one exported action. Never try unrelated invitation/leave actions
  -- or multiple signatures/packets after a rejection.
  for _,method in ipairs(kickMethods)do
   if type(game[method])=='function'then return native(method,id(c))end
  end
  return false
 end
 local function listed(n)
  for _,v in ipairs(config().autoPartyList or{})do if key(v)==key(n)then return true end end
  return false
 end
 local function canInvite(localShield,localName)
  local _,names=listNames(config().leaderName)
  return leaders[localShield]==true or ((localShield==0 or localShield==1 or localShield==2)and names[key(localName)]==true)
 end
 function C.talk(localPlayer,creatures,sender,text,time)
  local cfg=config()
  if not cfg.enabled or not cfg.onMsg or not player(localPlayer)or type(time)~='number'then return end
  local phrase=key(cfg.inviteTxt)
  if phrase==''or key(text)~=phrase or key(sender)==key(name(localPlayer))then return end
  local _,trusted=listNames(cfg.leaderName)
  local localShield=shield(localPlayer)
  for _,c in pairs(creatures or{})do
   if player(c)and id(c)~=id(localPlayer)and key(name(c))==key(sender)then
    if canInvite(localShield,name(localPlayer))and shield(c)==0 and not C.blockedInvites[key(sender)]then
     if ready('invite',key(sender),time,5000)then native('partyInvite',id(c))end
    elseif not(leaders[localShield]or members[localShield])and trusted[key(sender)]and shield(c)==1 then
     if ready('join',key(sender),time,5000)then native('partyJoin',id(c))end
    end
    return
   end
  end
 end
 function C.tick(localPlayer,creatures,time)
  local cfg=config()
  if not cfg.enabled then C.reset();return status('Auto Party desactivado.')end
  if not player(localPlayer)or type(time)~='number'then C.reset();return status('Esperando personaje.')end
  local localId=id(localPlayer)
  -- Gaps/offline periods cannot prove one continuous minute without share.
  if C.lastLocal~=localId or not C.lastTick or time<C.lastTick or time-C.lastTick>1500 then C.reset()end
  C.lastLocal=localId;C.lastTick=time
  local localShield=shield(localPlayer)
  local leader=leaders[localShield]==true
  local visible,byName={},{ }
  for _,c in pairs(creatures or{})do
   if player(c)and id(c)~=localId then visible[#visible+1]=c;byName[key(name(c))]=c end
  end
  table.sort(visible,function(a,b)return key(name(a))<key(name(b))end)
  local ordered,trusted=listNames(cfg.leaderName)
  local passName=cfg.passLeader and key(cfg.passLeaderName)or''
  local message=status(leader and'Eres el lider de la party.'or'Esperando invitaciones de tus lideres.')
  if C.pending then
   if not leader then
    C.pending=nil;C.timers={};return status('El liderazgo ya no esta en tu personaje.','success')
   elseif time-C.pending.at<5000 then
    C.timers={};return status('Leader solicitado a '..C.pending.name..'; esperando confirmacion.')
   else C.pending=nil end
  end
  if leader and cfg.passLeader then
   if passName==''then message=status('Pass Leader: escribe el nombre del destinatario.','warning')
   elseif passName==key(name(localPlayer))then message=status('Pass Leader: el destinatario eres tu.','warning')
   else
    local target=byName[passName]
    if target and members[shield(target)]then
     if type(game.partyPassLeadership)~='function'then message=status('Este cliente no permite pasar leader.','warning')
     elseif ready('pass',id(target),time,5000)then
      local sent=native('partyPassLeadership',id(target))
      if sent then
       C.pending={id=id(target),name=name(target),at=time};C.timers={}
       return status('Leader solicitado a '..name(target)..'; esperando confirmacion.')
      end
      return status('Pass Leader rechazado; se reintentara con pausa.','warning')
     end
    else message=status('Pass Leader: '..trim(cfg.passLeaderName)..' debe estar visible y en tu party.','warning')end
   end
  end
  if not leader or not cfg.kickNoShare then C.timers={}
  elseif not sharedEnabled[localShield]then
   C.timers={};message=status('Kick no share: primero activa el share de la party.','warning')
  else
   local observed={};local oldest
   for _,c in ipairs(visible)do
    local k=key(name(c))
    if noShare[shield(c)]and not trusted[k]and k~=passName then
     observed[k]=true
     local timer=C.timers[k]
     if not timer or timer.id~=id(c)then timer={id=id(c),since=time};C.timers[k]=timer end
     local elapsed=time-timer.since
     if not oldest or elapsed>oldest.elapsed then oldest={creature=c,elapsed=elapsed}end
     if elapsed>=60000 and C.kickAvailable()and ready('kick',id(c),time,10000)then
      if kick(c)then
       -- A client can lag before showing removal. Suppress immediate auto-invite
       -- of an excluded player until this session/configuration is reset.
       C.blockedInvites[k]=true
       return status('Expulsion solicitada para '..name(c)..'; esperando al servidor.')
      end
      return status('El cliente rechazo la expulsion de '..name(c)..'.','warning')
     end
    else C.timers[k]=nil end
   end
   for k in pairs(C.timers)do if not observed[k]then C.timers[k]=nil end end
   if oldest then
    local seconds=math.min(60,math.floor(oldest.elapsed/1000))
    message=status(name(oldest.creature)..' sin share: '..seconds..'/60 s.'..
     (C.kickAvailable()and''or' Kick no disponible en este cliente.'),C.kickAvailable()and'info'or'warning')
   elseif not C.kickAvailable()then message=status('Kick no disponible: el cliente no ofrece expulsar miembros.','warning')end
  end
  -- Sharing requested already (yellow shields 6/8/10) must not be toggled
  -- repeatedly just because the group is temporarily ineligible for XP.
  if leader and cfg.autoShare and not sharedEnabled[localShield]and ready('share',localId,time,3000)then
   if native('partyShareExperience',true)then return status('Activacion de share solicitada.')end
   return status('No se pudo activar el share en este cliente.','warning')
  end
  if canInvite(localShield,name(localPlayer))then
   for _,c in ipairs(visible)do
    local k=key(name(c))
    if shield(c)==0 and listed(k)and not C.blockedInvites[k]and not trusted[k]and ready('invite',k,time,5000)then
     if native('partyInvite',id(c))then return status('Invitacion solicitada para '..name(c)..'.')end
     return status('No se pudo invitar a '..name(c)..'.','warning')
    end
   end
  elseif not(leaders[localShield]or members[localShield])then
   for _,k in ipairs(ordered)do
    local c=byName[k]
    if c and shield(c)==1 and ready('join',k,time,5000)then
     if native('partyJoin',id(c))then return status('Aceptando invitacion de '..name(c)..'.')end
     return status('No se pudo aceptar la invitacion de '..name(c)..'.','warning')
    end
   end
  end
  return message
 end
 return C
end
return E
