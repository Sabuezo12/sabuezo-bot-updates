-- Shared party controller. Only client-confirmed shields establish roles.
-- Native action success means a request was sent, never server confirmation.
HelperPartyEngine={}
local E=HelperPartyEngine
local leaders={[4]=true,[6]=true,[8]=true,[10]=true}
local members={[3]=true,[5]=true,[7]=true,[9]=true}
local sharedEnabled={[6]=true,[8]=true,[10]=true}
local noShare={[7]=true,[9]=true}
local kickMethods={'partyKick','partyKickMember','partyKickPlayer','partyRemoveMember','partyRemove'}
local function trim(s)return (tostring(s or''):gsub('^%s+',''):gsub('%s+$',''))end
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
 local C={timers={},actions={},pending=nil,lastTick=nil,lastLocal=nil,blockedInvites={},returning={}}
 local game=options.game or{}
 local function config()return options.config end
 local function status(text,kind)return{message=text,kind=kind or'info'}end
 function C.reset()
  -- Configuration edits and lag reset observations, not anti-spam or exclusions.
  C.timers={};C.pending=nil;C.lastTick=nil;C.sharedReport=nil
 end
 function C.resume() C.paused=false;C.reset() end
 function C.reinvite() C.blockedInvites={};C.returning={};C.timers={} end
 local function blocked(n,time)
  local k=key(n);local untilAt=C.blockedInvites[k]
  if untilAt==true then return true end
  if type(untilAt)=='number'and untilAt>time then return true end
  C.blockedInvites[k]=nil;C.returning[k]=nil;return false
 end
 local function exclude(n,time,visible)
  local k=key(n)
  C.blockedInvites[k]=time+600000
  -- An off-screen member may return immediately. A visible member must first
  -- leave sight; the delayed shield update after kicking is not a return.
  C.returning[k]={absent=not visible}
 end
 local function session(localId)
  if C.sessionId~=localId then
   C.actions={};C.blockedInvites={};C.returning={};C.pending=nil;C.sessionId=localId;C.paused=false;C.sharedReport=nil;C.nextAutoKickAt=0
  end
 end
 local function protected(n)
  local _,names=listNames(config().protectedNames)
  return names[key(n)]==true
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
 local function kickTarget(targetId,targetName)
  local adapter=options.adapter
  if adapter and type(adapter.kickMember)=='function'then
   local ok,result=pcall(adapter.kickMember,targetId,targetName);return ok and result~=false
  end
  -- Choose one exported action. Never try unrelated invitation/leave actions
  -- or multiple signatures/packets after a rejection.
  if not targetId then return false end
  for _,method in ipairs(kickMethods)do
   if type(game[method])=='function'then return native(method,targetId)end
  end
  return false
 end
 local function kick(c) return kickTarget(id(c),name(c)) end
 local function listed(n)
  for _,v in ipairs(config().autoPartyList or{})do if key(v)==key(n)then return true end end
  return false
 end
 -- A complete !party modal is authoritative even when members are off screen.
 -- Duration advances on fresh server observations, never just on local elapsed time.
 function C.observeSharedReport(report,localPlayer,time)
  if not player(localPlayer)or not leaders[shield(localPlayer)]or type(time)~='number'or
     time~=time or type(report)~='table'or key(report.leader)~=key(name(localPlayer))or type(report.members)~='table'or
     report.count~=#report.members or not report.byName or not report.byName[key(name(localPlayer))]or
     report.byName[key(name(localPlayer))].leader~=true then return false end
  session(id(localPlayer))
  local previous=C.sharedReport
  local nextReport={at=time,requested=report.requested==true,entries={}}
  for _,entry in ipairs(report.members)do
   local k=key(entry.name)
   local before=previous and previous.entries[k]
   local continuous=previous and time>=previous.at and time-previous.at<=12000 and
     previous.requested and before and before.notSharing==true
   nextReport.entries[k]={name=entry.name,notSharing=entry.notSharing,reason=entry.reason,
    since=entry.notSharing==true and continuous and before.since or time,
    observations=entry.notSharing==true and continuous and before.observations+(time-previous.at>=1000 and 1 or 0)or 1}
  end
  C.sharedReport=nextReport
  return true
 end
 local function canInvite(localShield,localName)
  local _,names=listNames(config().leaderName)
  return leaders[localShield]==true or ((localShield==0 or localShield==1 or localShield==2)and names[key(localName)]==true)
 end
 function C.talk(localPlayer,creatures,sender,text,time)
  local cfg=config()
  if not cfg.enabled or C.paused or not cfg.onMsg or not player(localPlayer)or type(time)~='number'then return end
  local phrase=key(cfg.inviteTxt)
  if phrase==''or key(text)~=phrase or key(sender)==key(name(localPlayer))then return end
  local _,trusted=listNames(cfg.leaderName)
  if cfg.messageListOnly and not trusted[key(sender)]and not listed(sender)then return end
  local localShield=shield(localPlayer)
  for _,c in pairs(creatures or{})do
   if player(c)and id(c)~=id(localPlayer)and key(name(c))==key(sender)then
    if canInvite(localShield,name(localPlayer))and shield(c)==0 and not blocked(sender,time)then
     if ready('invite',key(sender),time,5000)then native('partyInvite',id(c))end
    elseif (localShield==0 or localShield==1 or localShield==2)and trusted[key(sender)]and shield(c)==1 then
     if ready('join',key(sender),time,5000)then native('partyJoin',id(c))end
    end
    return
   end
  end
 end
 -- Deliberate UI actions also work with automation off. Roles and membership
 -- are revalidated at the click; names never come from an unverified text field.
 function C.request(action,localPlayer,creatures,targetName,time,party)
  if not player(localPlayer)or type(time)~='number'then return status('Esperando personaje.','warning')end
  session(id(localPlayer))
  local mine=shield(localPlayer)
  if action=='leave'then
   if not(leaders[mine]or members[mine])then return status('No estas en una party.','warning')end
   if not ready('leave',id(localPlayer),time,5000)then return status('La salida ya fue solicitada; espera al servidor.')end
   C.paused=true;C.timers={};C.pending=nil
   local adapter=options.adapter
   local sent
   if adapter and type(adapter.leaveParty)=='function'then
    local ok,value=pcall(adapter.leaveParty);sent=ok and value~=false
   else sent=native('partyLeave')end
   return status(sent and'Salida solicitada. Auto Party queda pausado hasta que lo actives.'or'No se pudo solicitar la salida. Auto Party queda pausado.',sent and'info'or'warning')
  elseif action=='info'then
   local adapter=options.adapter
   if not ready('info',id(localPlayer),time,3000)then return status('Informacion solicitada; espera la respuesta.')end
   local ok,sent=false,false
   if adapter and type(adapter.partyInfo)=='function'then ok,sent=pcall(adapter.partyInfo)end
   return status(ok and sent~=false and'Informacion de party solicitada.'or'Informacion de party no disponible.',ok and sent~=false and'info'or'warning')
  end
  if not leaders[mine]then return status('Debes ser el lider de la party.','warning')end
  local target,known
  for _,c in pairs(creatures or{})do
   if player(c)and key(name(c))==key(targetName)and (members[shield(c)]or leaders[shield(c)])then target=c;break end
  end
  if party and party.inParty and type(party.byName)=='table'then known=party.byName[key(targetName)]end
  if not target and not(known and known.confirmed)then return status('Selecciona un miembro confirmado de tu party.','warning')end
  local who=target and name(target)or known.name
  local targetId=target and id(target)or known.id
  if key(who)==key(name(localPlayer))then return status('Para salir usa Salir y pausar.','warning')end
  if #who>80 or who:find('[%c!%%]')then return status('Nombre de miembro invalido.','warning')end
  if action=='kick'then
   if not C.kickAvailable()then return status('Expulsar no esta disponible. Activa los comandos del servidor.','warning')end
   if not ready('kick',key(who),time,10000)then return status('La expulsion de '..who..' ya fue solicitada.')end
   if kickTarget(targetId,who)then
    exclude(who,time,target~=nil);C.timers[key(who)]=nil
    return status('Expulsion solicitada para '..who..'; esperando al servidor.')
   end
   return status('No se pudo enviar la expulsion de '..who..'.','warning')
  elseif action=='pass'then
   if not target then return status('Para pasar liderazgo, el miembro debe estar en pantalla.','warning')end
   if not ready('pass',targetId,time,5000)then return status('El liderazgo ya fue solicitado; espera al servidor.')end
   if native('partyPassLeadership',targetId)then
    C.pending={id=targetId,name=who,at=time};C.timers={}
    return status('Liderazgo solicitado para '..who..'; esperando al servidor.')
   end
   return status('No se pudo solicitar el cambio de liderazgo.','warning')
  end
  return status('Accion de party desconocida.','warning')
 end
 function C.tick(localPlayer,creatures,time)
  local cfg=config()
  if not cfg.enabled then C.reset();return status('Auto Party desactivado.')end
  if not player(localPlayer)or type(time)~='number'then C.reset();return status('Esperando personaje.')end
  local localId=id(localPlayer)
  -- Gaps/offline periods cannot prove one continuous minute without share.
  session(localId)
  if C.paused then C.timers={};return status('Auto Party pausado tras salir; vuelve a activarlo para continuar.')end
  if C.lastLocal~=localId or not C.lastTick or time<C.lastTick or time-C.lastTick>1500 then
   C.timers={}
   if C.lastTick and(time<C.lastTick or time-C.lastTick>1500)then C.sharedReport=nil;C.nextAutoKickAt=0 end
  end
  for action,at in pairs(C.actions)do if time<at or time-at>60000 then C.actions[action]=nil end end
  for who,untilAt in pairs(C.blockedInvites)do
   if type(untilAt)=='number'and untilAt<=time then C.blockedInvites[who]=nil;C.returning[who]=nil end
  end
  C.lastLocal=localId;C.lastTick=time
  local localShield=shield(localPlayer)
  local leader=leaders[localShield]==true
  local visible,byName={},{ }
  for _,c in pairs(creatures or{})do
   if player(c)and id(c)~=localId then visible[#visible+1]=c;byName[key(name(c))]=c end
  end
  table.sort(visible,function(a,b)return key(name(a))<key(name(b))end)
  for k,entry in pairs(C.returning)do
   if not byName[k]then entry.absent=true
   elseif entry.absent and listed(k)and shield(byName[k])==0 then
    C.blockedInvites[k]=nil;C.returning[k]=nil;C.timers[k]=nil
    -- Returning starts a new attendance interval, including after rejoining.
    if C.sharedReport then C.sharedReport.entries[k]=nil end
   end
  end
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
  local report=C.sharedReport
  if report and(time<report.at or time-report.at>12000)then C.sharedReport=nil;report=nil end
  if not leader or not cfg.kickNoShare then C.timers={};C.sharedReport=nil
  elseif report then
   C.timers={}
   if not report.requested then message=status('El servidor indica shared desactivado; no se expulsa por actividad.','warning')
   else
    local candidates={}
    for k,entry in pairs(report.entries)do
     if entry.notSharing==true and not entry.requested and k~=key(name(localPlayer))and not trusted[k]and k~=passName and not protected(k)then
      candidates[#candidates+1]={key=k,entry=entry}
     end
    end
    table.sort(candidates,function(a,b)
     if a.entry.since~=b.entry.since then return a.entry.since<b.entry.since end
     return a.key<b.key
    end)
    local limit=math.max(15,math.min(3600,tonumber(cfg.kickNoShareSeconds)or 60))*1000
    for _,candidate in ipairs(candidates)do
     local entry,k=candidate.entry,candidate.key
     local duration=report.at-entry.since
     local adapter=options.adapter
     local canSend=not adapter or not adapter.canAutoKick or adapter.canAutoKick(time)
     if entry.observations>=2 and duration>=limit and C.kickAvailable()and canSend and
        time>=(C.nextAutoKickAt or 0)and ready('kick',k,time,10000)then
      local actor=byName[k]
      C.nextAutoKickAt=time+1500
      if kickTarget(actor and id(actor),entry.name)then
       entry.requested=true
       exclude(k,time,actor~=nil)
       return status('Expulsion solicitada para '..entry.name..' (!party: '..tostring(entry.reason)..').')
      end
      return status('No se pudo solicitar la expulsion de '..entry.name..'.','warning')
     end
    end
    local first=candidates[1]
    if first then
     local entry=first.entry
     message=status(entry.name..': '..tostring(entry.reason)..' | '..math.floor((report.at-entry.since)/1000)..'/'..(limit/1000)..' s (!party).')
    else message=status('!party: todos los miembros revisados estan listos o protegidos.')end
   end
  elseif not sharedEnabled[localShield]then
   C.timers={};message=status('Kick no share: primero activa el share de la party.','warning')
  else
   local observed={};local oldest
   for _,c in ipairs(visible)do
    local k=key(name(c))
    if noShare[shield(c)]and not trusted[k]and k~=passName and not protected(k)then
     observed[k]=true
     local timer=C.timers[k]
     if not timer or timer.id~=id(c)then timer={id=id(c),since=time};C.timers[k]=timer end
     local elapsed=time-timer.since
     if not oldest or elapsed>oldest.elapsed then oldest={creature=c,elapsed=elapsed}end
     local limit=math.max(15,math.min(3600,tonumber(cfg.kickNoShareSeconds)or 60))*1000
     local adapter=options.adapter
     local canSend=not adapter or not adapter.canAutoKick or adapter.canAutoKick(time)
     if elapsed>=limit and C.kickAvailable()and canSend and ready('kick',k,time,10000)then
      if kick(c)then
       -- Require a real leave/reappearance before inviting a visible member.
       exclude(k,time,true)
       return status('Expulsion solicitada para '..name(c)..'; esperando al servidor.')
      end
      return status('El cliente rechazo la expulsion de '..name(c)..'.','warning')
     end
    else C.timers[k]=nil end
   end
   for k in pairs(C.timers)do if not observed[k]then C.timers[k]=nil end end
   if oldest then
    local limit=math.max(15,math.min(3600,tonumber(cfg.kickNoShareSeconds)or 60))
    local seconds=math.min(limit,math.floor(oldest.elapsed/1000))
    message=status(name(oldest.creature)..' sin share: '..seconds..'/'..limit..' s.'..
     (C.kickAvailable()and''or' Kick no disponible en este cliente.'),C.kickAvailable()and'info'or'warning')
   elseif not C.kickAvailable()then message=status('Kick no disponible: el cliente no ofrece expulsar miembros.','warning')end
  end
  -- Sharing requested already (yellow shields 6/8/10) must not be toggled
  -- repeatedly just because the group is temporarily ineligible for XP.
  if leader and cfg.autoShare and not sharedEnabled[localShield]and not(report and report.requested)and ready('share',localId,time,3000)then
   if native('partyShareExperience',true)then return status('Activacion de share solicitada.')end
   return status('No se pudo activar el share en este cliente.','warning')
  end
  if canInvite(localShield,name(localPlayer))then
   for _,c in ipairs(visible)do
    local k=key(name(c))
    if shield(c)==0 and listed(k)and not blocked(k,time)and not trusted[k]and ready('invite',k,time,5000)then
     if native('partyInvite',id(c))then return status('Invitacion solicitada para '..name(c)..'.')end
     return status('No se pudo invitar a '..name(c)..'.','warning')
    end
   end
  elseif (localShield==0 or localShield==1 or localShield==2)then
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
