-- Route-local emergency exit. PZ releases the emergency without a manual rearm;
-- only the immediate monster obstruction may receive a controlled attack.
CaveBot.Flee = {}
local F = CaveBot.Flee
local T = assert(CaveBot.FleeTools, "Huida: falta el planificador de salida.")
local state={phase='idle'}
local session=0
local wakePending=false
local zoneCompletion
-- Retire the old persisted rearm latch. Engine ON/OFF choices stay untouched.
storage.caveBotFleeHold=nil
local offsets = {{0,-1},{1,0},{0,1},{-1,0},{1,-1},{1,1},{-1,1},{-1,-1}}
local tools = {[3003]=true,[3457]=true,[3308]=true,[9596]=true,[9598]=true,[9594]=true}
local function time() return tonumber(now) or 0 end
local function config(id) return CaveBot.Config.values[id] end
local function copy(p) return p and {x=p.x,y=p.y,z=p.z} end
local function same(a,b) return a and b and a.x==b.x and a.y==b.y and a.z==b.z end
local function distance(a,b)
  if not a or not b or a.z~=b.z then return math.huge end
  return math.max(math.abs(a.x-b.x),math.abs(a.y-b.y))
end
local function position(value)
  local x,y,z,precision=tostring(value or ''):match('^%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*,?%s*(%d*)%s*$')
  x,y,z=tonumber(x),tonumber(y),tonumber(z)
  if not z or x>65535 or y>65535 or z>15 then return nil end
  return {x=x,y=y,z=z},tonumber(precision)
end
local function status(message)
  if state.message==message then return end
  state.message=message
  if CaveBot.Diagnostics and CaveBot.Diagnostics.setSupplyStatus then
    CaveBot.Diagnostics.setSupplyStatus('Huida PvP: '..message,'#ffcc66')
  end
  if type(info)=='function' then info('[Huida PvP] '..message) end
  F.refreshUi()
end
function F.blocksCombat() return state.phase~='idle' end
function F.isEscaping() return state.phase=='check' or state.phase=='exit' end
function F.getItemJob()
  if F.isEscaping()and config('fleePlayers')==true and CaveBot.isOn()and g_game.isOnline()
    and player and player:getHealthPercent()>0 then return state.itemJob end
end
function F.itemPending()
  local p=state.pending
  return p and(p.kind=='clean'and p.action or p.kind=='push'and'push')or nil
end
local function itemReady(action,paired)
  if PushMax and type(PushMax.fleeItemReady)=='function'then
    local ready,why=PushMax.fleeItemReady(action,paired)
    if not ready then status(why or 'Turno de objeto antes del empuje.');return false end
  end
  return true
end
local function itemRequest(action,fn,...)
  if PushMax and type(PushMax.performFleeItem)=='function'and F.getItemJob()then
    return PushMax.performFleeItem(action,fn,...)
  end
  return fn(...)
end
function F.getStatus() return state.message or (F.blocksCombat() and 'Ruta detenida; activa CaveBot para reintentar.' or 'Lista; deteccion solo con CaveBot ON.') end
local function stopWalking()
  state.pending=nil
  CaveBot.resetWalking()
  if g_game and g_game.stop then pcall(g_game.stop) end
end
local stopMonster, monsterAllowed
local function suppressCombat()
  -- The engine guards suspend targeting without rewriting its saved switch.
  if TargetBot and TargetBot.walkTo then TargetBot.walkTo(nil)end
  local allowed=state.monster and monsterAllowed()
  if state.monster and not allowed then stopMonster() end
  local current=g_game.getAttackingCreature()
  if current and not (allowed and current:getId()==state.monster.id) then
    g_game.cancelAttackAndFollow()
  elseif g_game.getFollowingCreature() then
    if allowed and g_game.cancelFollow then g_game.cancelFollow()
    else g_game.cancelAttackAndFollow() end
  end
end
function F.hold(message)
  zoneCompletion=nil
  stopMonster()
  state.phase='stopped'
  stopWalking()
  if CaveBot.CancelNpcConversation then CaveBot.CancelNpcConversation() end
  status(message)
  if CaveBot.isOn and CaveBot.isOn() then CaveBot.setOff() end
end
function F.finish(message)
  stopMonster()
  stopWalking()
  if CaveBot.CancelNpcConversation then CaveBot.CancelNpcConversation()end
  state={phase='idle'}
  storage.caveBotFleeHold=nil
  status(message or 'Huida finalizada; la ruta continua.')
  if CaveBot.wakeRoute then CaveBot.wakeRoute()end
end
local function destinationName()return state.destination=='zonapz'and'ZonaPZ'or'Supply Check'end
local function restText(milliseconds)
  local seconds=math.ceil(math.max(0,milliseconds)/1000)
  return string.format('%02d:%02d',math.floor(seconds/60),seconds%60)
end
local function startZoneRest(row,minutes)
  stopMonster();stopWalking()
  state.phase='rest';state.checkpoint=row;state.route=CaveBot.getCurrentProfile()
  state.restIndex=CaveBot.actionList:getChildIndex(row)
  state.zoneValue=row.value;state.remaining=minutes*60000;state.restAt=time()
  status('ZonaPZ: esperando '..restText(state.remaining)..' antes de retomar la ruta.')
end
local function resettableZone()
  if state.phase~='rest'or config('fleePlayers')~=true then return nil end
  local row=state.checkpoint
  if not g_game.isOnline()or not player or player:getHealthPercent()<=0 or not isInPz()
    or CaveBot.getCurrentProfile()~=state.route or not row or not CaveBot.actionList:getChildIndex(row)
    or row.action~='zonapz'or row.value~=state.zoneValue then return nil end
  local zone=T.zoneConfig(row.value)
  return zone and zone.minutes>0 and zone or nil
end
function F.resetZoneRest()
  local zone=resettableZone()
  if not zone then F.refreshUi();return false end
  state.remaining=zone.minutes*60000;state.restAt=time()
  local paused=not CaveBot.isOn()or HelperPause and HelperPause.isPaused()
  status(paused and 'ZonaPZ: espera pausada; quedan '..restText(state.remaining)..'.'
    or 'ZonaPZ: esperando '..restText(state.remaining)..' antes de retomar la ruta.')
  F.refreshUi()
  return true
end
local function pollZoneRest()
  if not g_game.isOnline()or not player or player:getHealthPercent()<=0 then F.hold('ZonaPZ: espera detenida por desconexion o muerte.');return end
  local row=state.checkpoint
  if CaveBot.getCurrentProfile()~=state.route or not row or not CaveBot.actionList:getChildIndex(row)
    or row.action~='zonapz'or row.value~=state.zoneValue then F.hold('ZonaPZ: la accion o la ruta cambio durante la espera.');return end
  if not isInPz()then F.hold('ZonaPZ: saliste de PZ durante la espera. Revisa el punto y activa CaveBot para volver.');return end
  local paused=not CaveBot.isOn()or HelperPause and HelperPause.isPaused()
  local n=time()
  if not paused then state.remaining=math.max(0,state.remaining-math.max(0,n-state.restAt))end
  state.restAt=n
  if paused then status('ZonaPZ: espera pausada; quedan '..restText(state.remaining)..'.');return end
  if state.remaining>0 then status('ZonaPZ: esperando '..restText(state.remaining)..' antes de retomar la ruta.');return end
  zoneCompletion={row=row,value=row.value,route=state.route}
  CaveBot.actionList:focusChild(row)
  F.finish('ZonaPZ: espera terminada; CaveBot continua por la ruta.')
end
-- A dedicated destination is exact, even when another PZ lies on the way.
-- Wait for the server's protection-state acknowledgement before releasing combat.
local function arrived()
  if state.destination~='zonapz'then
    if isInPz()then F.finish('En PZ; CaveBot continua por la ruta.');return true end
    return false
  end
  local row=state.checkpoint
  if not row or row.action~='zonapz'or not CaveBot.actionList:getChildIndex(row)then
    F.hold('ZonaPZ fue eliminada de la ruta. Revisa el destino.');return true
  end
  local zone=T.zoneConfig(row.value)
  if not zone then F.hold('ZonaPZ tiene coordenadas o minutos invalidos.');return true end
  local goal=zone.pos
  if not same(player:getPosition(),goal)then state.arrivedAt=nil;return false end
  stopMonster()
  if not state.arrivedAt then stopWalking();state.arrivedAt=time()end
  if not isInPz()then
    if time()-state.arrivedAt>=1500 then F.hold('ZonaPZ alcanzada sin proteccion PZ. Corrige ese punto de la ruta.')
    else status('ZonaPZ alcanzada; esperando confirmacion PZ del cliente.')end
    return true
  end
  CaveBot.actionList:focusChild(row)
  if zone.minutes>0 then startZoneRest(row,zone.minutes);return true end
  F.finish('ZonaPZ alcanzada; CaveBot continua por la ruta.')
  return true
end
local function movement() return TargetBot and TargetBot.Movement end
local function manual() local m=movement();return m and m.isManual(time(),true) end
local function floorSafe(p,tile)
  local m=movement()
  return m and m.floorSafe(p,tile)==true
end
local function clearTile(p)
  return T.free(T.tile(p))==true
end
local function destination(p,dir)
  local o=offsets[(tonumber(dir) or -1)+1]
  return o and {x=p.x+o[1],y=p.y+o[2],z=p.z}
end
local function safeMonster(creature,p,from)
  if not creature or creature==player or not creature.isMonster or not creature:isMonster() or creature:isPlayer() then return false end
  local cpos=creature:getPosition()
  if not cpos or not same(cpos,from) or distance(p,cpos)~=1 or creature:getHealthPercent()<=0 then return false end
  if creature.getType and g_game.getClientVersion and g_game.getClientVersion()>=960 and creature:getType()>=3 then return false end
  return true -- basic native attacks do not require a projectile-line prefilter
end
-- The normal combat engines stay suspended. Only a single-target SD may
-- supplement this immediate monster obstruction. Basic area ammunition is
-- allowed here even with nearby players, as requested for emergency escape.
local attackGroupUntil=0
if type(onGroupSpellCooldown)=='function' then
  onGroupSpellCooldown(function(group,duration)
    if tonumber(group)==1 then
      attackGroupUntil=time()+math.max(0,tonumber(duration)or 0)
      local pending=state.monsterRune
      if pending and time()-pending.at<=1000 and tonumber(duration)and duration>0 then
        pending.confirmed=true
      end
    end
  end)
end
local function sdSupply()
  local item=type(findItem)=='function'and findItem(3155)or nil
  local count
  if type(player.getInventoryCount)=='function' then
    local ok,n=pcall(player.getInventoryCount,player,3155,0)
    if ok then count=tonumber(n)end
  end
  return item or count and count>0,item,count
end
local function attackGroupBusy()
  if time()<attackGroupUntil then return true end
  local cooldown=modules and modules.game_cooldown
  if cooldown and type(cooldown.isGroupCooldownIconActive)=='function' then
    local ok,active=pcall(cooldown.isGroupCooldownIconActive,1)
    if ok and active then return true end
  end
  return false
end
local function useMonsterRune(creature)
  if time()<(state.runeUntil or 0)or attackGroupBusy() then return end
  if creature.canShoot then local ok,shoot=pcall(creature.canShoot,creature);if not ok or not shoot then return end end
  if not itemReady('monster')then return end
  local available,item,count=sdSupply()
  if not available then return end
  local pending=state.monsterRune
  local failures=state.monsterRuneFailures or 0
  if pending then
    if pending.confirmed or count and pending.count and count<pending.count then failures=0
    else failures=failures+1 end
    state.monsterRune=nil;state.monsterRuneFailures=failures
    if failures>=3 then
      state.monsterRuneFailures=0;state.runeUntil=time()+1500
      status('SD al bloqueo sin confirmar; revisando disponibilidad y otro paso.');return
    end
  end
  local sent=false
  if type(g_game.useInventoryItemWith)=='function' then
    local ok,result=pcall(itemRequest,'monster',g_game.useInventoryItemWith,3155,creature,0);sent=ok and result~=false
  elseif item and type(g_game.useWith)=='function' then
    local ok,result=pcall(itemRequest,'monster',g_game.useWith,item,creature,0);sent=ok and result~=false
  elseif type(useWith)=='function' then
    local ok,result=pcall(itemRequest,'monster',useWith,3155,creature,0);sent=ok and result~=false
  end
  -- This timestamp throttles requests; it does not claim damage or a cast.
  state.runeUntil=time()+(sent and 2000 or 1000)
  state.monsterRune={at=time(),count=count}
  status(sent and 'Antitrap: SD dirigida a '..creature:getName()..'; buscando paso libre.'
    or 'No se pudo enviar SD al monstruo que bloquea; reintento limitado.')
end
stopMonster=function()
  local owned=state.monster
  if not owned then return end
  state.monster=nil
  local current=g_game.getAttackingCreature()
  if current and current:getId()==owned.id then
    if g_game.cancelAttack then g_game.cancelAttack() else g_game.cancelAttackAndFollow() end
  end
  if owned.chaseBefore~=nil and g_game.getChaseMode and g_game.setChaseMode and g_game.getChaseMode()==0 then
    g_game.setChaseMode(owned.chaseBefore)
  end
end
monsterAllowed=function()
  local owned=state.monster
  if not owned or not F.isEscaping() or config('fleePlayers')~=true or not CaveBot.isOn() or not g_game.isOnline()
    or not player or player:getHealthPercent()<=0 or isInPz() or manual() or HelperPause and HelperPause.isPaused() then return false end
  if not same(player:getPosition(),owned.origin) or CaveBot.actionList:getFocusedChild()~=owned.action then return false end
  local creature=getCreatureById(owned.id)
  return safeMonster(creature,player:getPosition(),owned.from)
    and g_game.getChaseMode and g_game.getChaseMode()==0
end
local function tryMonster(p,dir,goal)
  if config('fleePlayers')~=true then return false end
  local blocked=destination(p,dir)
  local tile=blocked and g_map.getTile(blocked)
  if not tile or not floorSafe(blocked,tile) then return false end
  local creatures=tile:getCreatures() or {}
  local creature
  for _,candidate in ipairs(creatures)do
    -- A player, NPC or summon on this stack is not a monster exit to attack.
    if not safeMonster(candidate,p,blocked)then return false end
    if not creature or state.monster and candidate:getId()==state.monster.id
      or not state.monster and candidate:getHealthPercent()<creature:getHealthPercent()then creature=candidate end
  end
  if not creature then return false end
  local rune=sdSupply()
  local retry=state.monsterRetry
  local attackRetry=retry and retry.id==creature:getId() and time()<retry.after
  if attackRetry and not rune then return false end
  local owned=state.monster
  if owned and (owned.id~=creature:getId() or not same(owned.from,blocked) or not same(owned.goal,goal)) then stopMonster();owned=nil end
  if not owned then
    if not g_game.getChaseMode or not g_game.setChaseMode then return false end
    stopWalking()
    owned={id=creature:getId(),from=copy(blocked),origin=copy(p),goal=copy(goal),
      action=CaveBot.actionList:getFocusedChild(),chaseBefore=g_game.getChaseMode(),lastRequest=-math.huge,requests=0,
      bestHealth=creature:getHealthPercent(),progressAt=time()}
    state.monster=owned
    g_game.setChaseMode(0) -- Never chase a monster that leaves the route obstruction.
  end
  if not monsterAllowed() then stopMonster();return false end
  if creature:getHealthPercent()<owned.bestHealth then owned.bestHealth=creature:getHealthPercent();owned.progressAt=time()end
  if time()-owned.progressAt>=5000 then
    state.monsterRetry={id=owned.id,after=time()+2000};stopMonster()
    status('Monstruo sin dano confirmado; buscando otra abertura.');return false
  end
  local current=g_game.getAttackingCreature()
  useMonsterRune(creature)
  if attackRetry then stopMonster();return false end
  if type(g_game.attack)~='function'then return true end
  if current and current:getId()==owned.id then return true end
  if time()-owned.lastRequest<500 then return true end
  if owned.requests>=3 then
    state.monsterRetry={id=owned.id,after=time()+5000};stopMonster()
    status('Ataque al bloqueo sin confirmar; buscando otro bloqueador.');return false
  end
  owned.requests=owned.requests+1;owned.lastRequest=time()
  local ok,result=pcall(g_game.attack,creature)
  if not ok or result==false then
    state.monsterRetry={id=owned.id,after=time()+1000};stopMonster()
    status('No se pudo atacar al monstruo que bloquea.');return false
  end
  status('Antitrap: atacando a '..creature:getName()..'; saldra en cuanto se abra el paso.')
  return true
end
local function validPush(context,p)
  local creature=context and getCreatureById(context.id)
  return creature and creature~=player and creature:isPlayer() and creature:getHealthPercent()>0
    and same(p,context.origin)and same(creature:getPosition(),context.from)
    and distance(p,context.from)>0 and distance(p,context.from)<=5 and CaveBot.actionList:getFocusedChild()==context.action
    and CaveBot.getCurrentProfile()==context.route and state.route==context.route
    and CaveBot.actionList:getChildIndex(context.action)and context.action.value==context.actionValue
    and context.action.action==context.actionName and state.checkpoint==context.checkpoint
    and context.checkpoint and CaveBot.actionList:getChildIndex(context.checkpoint)
    and context.checkpoint.value==context.checkpointValue
end
local function activePush(context)
  return F.isEscaping()and config('fleePlayers')==true and CaveBot.isOn()and g_game.isOnline()
    and player and player:getHealthPercent()>0 and not manual()
    and not(HelperPause and HelperPause.isPaused())and validPush(context,player:getPosition())
end
local function probeTrash(tile)
  local attempt=state.clearAttempts and state.clearAttempts[T.key(tile.pos)..':disintegrate']
  return attempt and attempt.probe==true
end
local function pushAttempt(context)
  local key=tostring(context.id)..':'..T.key(context.from)
  state.pushAttempts=state.pushAttempts or{}
  local count,oldest=0,nil
  for id,entry in pairs(state.pushAttempts)do
    if time()-entry.at>10000 then state.pushAttempts[id]=nil
    else count=count+1;if not oldest or entry.at<oldest.at then oldest=entry end end
  end
  local attempt=state.pushAttempts[key]
  if not attempt then
    if count>=16 and oldest then state.pushAttempts[oldest.key]=nil end
    attempt={key=key,count=0,nextAt=0,failed={}};state.pushAttempts[key]=attempt
  end
  attempt.at=time();state.pushAttempt=attempt
  return attempt,key
end
local function itemSerial()return PushMax and PushMax.fleeItemState and PushMax.fleeItemState()or 0 end
local function pushWindow(profileKey)
  local ping=math.max(30,math.min(1000,tonumber(g_game.getPing and g_game.getPing()or config('ping'))or 100))
  if state.responseSuspended and time()<(state.responseSuspended[profileKey]or 0)then return math.max(1200,ping*3+300),ping,false end
  local profile=state.pushResponses and state.pushResponses[profileKey]
  if profile and #profile>=6 then
    local peak=0
    for _,s in ipairs(profile)do
      if time()-s.at>120000 or math.abs(s.ping-ping)>math.max(20,ping*.25)then return 1200,ping,false end
      peak=math.max(peak,s.ms)
    end
    local base=math.max(1200,ping*3+300,math.min(5000,peak*1.5+ping*2))
    local window=math.min(base,math.max(400,ping*4+100,peak+math.max(200,ping*3)))
    return window,ping,window<base
  end
  return math.max(1200,ping*3+300),ping,false
end
local function sendPush(context,dest,paired)
  if not activePush(context)then return false end
  -- Re-read both squares just before sending. A queued cleanup never grants
  -- permission to push through a new wall, field, actor, floor or route edit.
  local source,target=T.tile(context.from),T.tile(dest)
  if not source or not target or not source.safe or not target.safe or source.hard or target.hard
    or #source.creatures~=1 or #target.creatures~=0 or not target.walkable
    or source.field or target.field or same(dest,context.origin)or distance(context.from,dest)~=1
    -- A walkable landing may contain ordinary items; only the source needs
    -- an antipush opening. Physical landing blockers are rejected above.
    or #source.trash>0 and not probeTrash(source)then return false end
  local attempt,key=pushAttempt(context)
  if time()<attempt.nextAt then return false end
  if attempt.count>=3 then attempt.count=0;attempt.nextAt=time()+750;return false end
  if not itemReady('push',paired)then return true end
  attempt.count=attempt.count+1
  local sqm=distance(context.origin,context.from)
  local profileKey=sqm..(paired and ':cleanup'or ':clear')
  local wait,ping,adaptive=pushWindow(profileKey);attempt.nextAt=time()+wait
  local creature=getCreatureById(context.id)
  stopMonster() -- release an alternative attack only when a legal push is ready
  local ok,result=pcall(g_game.move,creature,dest,1)
  if not ok or result==false then
    state.pending=nil
    attempt.nextAt=time()+math.max(100,math.min(250,ping*2))
    attempt.failed[T.key(dest)]=time()+1500
    local prior=state.clearAttempts and state.clearAttempts[T.key(context.from)..':disintegrate']
    if prior then prior.probe=false end
    status('Empuje rechazado; probando otra casilla de salida.');return true
  end
  state.pending={kind='push',id=context.id,from=copy(context.from),dest=copy(dest),origin=copy(context.origin),key=key,
    at=time(),untilAt=time()+wait,sqm=sqm,profileKey=profileKey,ping=ping,adaptive=adaptive,itemSerial=itemSerial(),bestDistance=sqm}
  status('Antitrap: esperando confirmacion del empuje de '..creature:getName()..'.')
  return true
end
local function serviceClean(pending,p)
  if not activePush(pending.push)then state.pending=nil;return false end
  local tile=T.tile(pending.pos)
  if not tile or not same(p,pending.origin)or tile.hard then state.pending=nil;return false end
  local landingReady=pending.action=='disintegrate'and not same(pending.pos,pending.push.from)
    and tile.walkable and not tile.field
  local cleared=pending.action=='destroy'and not tile.field or pending.action=='disintegrate'and(#tile.trash==0 or landingReady)
  local probe=pending.action=='disintegrate'and time()>=pending.probeAt
  if cleared or probe then
    local attempt=state.clearAttempts[pending.key]
    if cleared then state.clearAttempts[pending.key]=nil
    elseif attempt then attempt.probe=true end
    -- One bounded native move probe after Disintegrate, even if replacement
    -- coins are already visible. Never treat the rune request as push success.
    if sendPush(pending.push,pending.dest,true)then return true end
    if cleared then state.pending=nil;return false end
  end
  if time()<pending.untilAt then return true end
  state.pending=nil
  local attempt=state.clearAttempts[pending.key]
  if attempt and pending.action=='disintegrate'then attempt.probe=true end
  status('Limpieza sin confirmar; revisando otro paso.')
  return false
end
local function queueClean(pending)
  if type(schedule)~='function'or pending.scheduled then return end
  pending.scheduled=true
  schedule(20,function()
    pending.scheduled=false
    if state.pending~=pending or not F.isEscaping()then return end
    local ok,err=pcall(function()
      serviceClean(pending,player and player:getPosition())
      if state.pending==pending and time()<pending.untilAt then queueClean(pending)end
    end)
    if not ok then F.hold('Error al coordinar limpieza y empuje: '..tostring(err))end
  end)
end
local function failedTiles(p)
  local failed=state.failedSteps
  if not failed or not same(p,failed.origin)then state.failedSteps=nil;return nil end
  local avoid,any={},false
  for key,entry in pairs(failed.tiles)do
    if time()>=entry.untilAt then failed.tiles[key]=nil
    elseif clearTile(entry.pos)then avoid[key]=true;any=true end
  end
  return any and avoid or nil
end
local function rememberFailedStep(p,to)
  if not to then return end
  local failed=state.failedSteps
  if not failed or not same(p,failed.origin)then failed={origin=copy(p),tiles={}};state.failedSteps=failed end
  -- At most the eight neighboring destinations, retired after movement/TTL.
  local retry=math.max(400,math.min(1000,(tonumber(config('ping'))or 100)*3+200))
  failed.tiles[T.key(to)]={pos=copy(to),untilAt=time()+retry}
end
local function tickPending(p)
  local pending=state.pending
  if not pending then return false end
  if pending.kind=='clean' then
    return serviceClean(pending,p)
  end
  if pending.kind=='push' then
    local creature=getCreatureById(pending.id)
    if not creature or not same(creature:getPosition(),pending.from) then
      state.clearedPush={id=pending.id,origin=copy(p)}
      local a=state.pushAttempts and state.pushAttempts[pending.key]
      if a then a.count=0;a.nextAt=0;a.failed={}end
      local ping=tonumber(g_game.getPing and g_game.getPing()or config('ping'))or 100
      if creature and same(creature:getPosition(),pending.dest)and not pending.dirty and itemSerial()==pending.itemSerial and same(p,pending.origin)
        and math.abs(ping-pending.ping)<=math.max(20,pending.ping*.25)then
        state.pushResponses=state.pushResponses or{};local samples=state.pushResponses[pending.profileKey]or{}
        state.pushResponses[pending.profileKey]=samples;samples[#samples+1]={at=time(),ms=time()-pending.at,ping=pending.ping}
        if #samples>8 then table.remove(samples,1)end
      end
      state.pending=nil;status('Paso despejado; retomando salida.');return false
    end
    local ping=tonumber(g_game.getPing and g_game.getPing()or config('ping'))or 100
    local busy=not same(p,pending.origin)or itemSerial()~=pending.itemSerial or math.abs(ping-pending.ping)>math.max(20,pending.ping*.25)
    if busy then pending.dirty=true;pending.untilAt=math.max(pending.untilAt,pending.at+1200)end
    local remaining=distance(p,pending.from)
    if remaining<pending.bestDistance then pending.bestDistance=remaining;pending.untilAt=math.max(pending.untilAt,time()+1200)end
    if time()<pending.untilAt then return true end
    state.pending=nil
    if pending.adaptive and state.pushResponses then
      state.pushResponses[pending.profileKey]=nil;state.responseSuspended=state.responseSuspended or{}
      state.responseSuspended[pending.profileKey]=time()+30000
    end
    local attempt=state.pushAttempts and state.pushAttempts[pending.key]
    if attempt and attempt.key==pending.key then
      attempt.failed=attempt.failed or {};attempt.failed[T.key(pending.dest)]=time()+1500
      local source=state.clearAttempts[T.key(pending.from)..':disintegrate']
      if source then source.probe=false end
    end
    status('Empuje sin confirmar; buscando paso libre.')
    return false
  end
  if same(p,pending.dest) or p.z~=pending.from.z then state.pending=nil;return false end
  if not same(p,pending.last) then pending.last=copy(p);pending.progressAt=time()end
  if time()-pending.progressAt<pending.timeout then return true end
  if same(p,pending.from)then rememberFailedStep(p,pending.dest)end
  status('Paso sin avance confirmado; recalculando salida.')
  stopWalking()
  return false
end
local function tryClean(p,tile,action,push,dest)
  if not validPush(push,p)or not (same(tile and tile.pos,push.from)or distance(tile and tile.pos,push.from)==1)then return false end
  if not tile or not tile.safe or tile.hard or not tile.shootable then return false end
  if action~='destroy'and action~='disintegrate'then return false end
  local target=action=='destroy' and tile.field or tile.trash[#tile.trash]
  if not target or distance(p,tile.pos)>(action=='destroy' and 5 or 1) then return false end
  state.clearAttempts=state.clearAttempts or {}
  local key=T.key(tile.pos)..':'..action
  local attempt=state.clearAttempts[key]
  local count,oldest=0,nil
  for id,entry in pairs(state.clearAttempts)do
    if entry.at and time()-entry.at>10000 then state.clearAttempts[id]=nil
    else count=count+1;if not oldest or(entry.at or 0)<(oldest.at or 0)then oldest={key=id,at=entry.at}end end
  end
  attempt=state.clearAttempts[key]
  if not attempt then
    if count>=32 and oldest then state.clearAttempts[oldest.key]=nil end
    attempt={count=0,nextAt=0};state.clearAttempts[key]=attempt
  end
  attempt.at=time()
  if time()<attempt.nextAt or time()<(state.runeUntil or 0) then
    status('Esperando runa de limpieza; buscando otra abertura.');return false
  end
  if attempt.count>=3 then
    attempt.count=0;attempt.nextAt=time()+1500
    status('Limpieza rechazada o sin runas; buscando otra abertura.');return false
  end
  if not itemReady(action)then return true end
  -- Emergency mode never imports an offensive/field/wall rune from a custom
  -- Push Max setting. Only these known cleanup actions are allowed here.
  local id=action=='destroy' and 3148 or 3197
  if not same(tile.pos,push.from)then
    -- Preparing a landing spends the old source opening. Replacement coins
    -- under the creature require a fresh final Disintegrate before its push.
    local sourceAttempt=state.clearAttempts[T.key(push.from)..':disintegrate']
    if sourceAttempt then sourceAttempt.probe=false end
  end
  local sent=false
  if type(g_game.useInventoryItemWith)=='function' then
    local ok,result=pcall(itemRequest,action,g_game.useInventoryItemWith,id,target,0);sent=ok and result~=false
  end
  if not sent and type(findItem)=='function' and type(g_game.useWith)=='function' then
    local rune=findItem(id)
    if rune then local ok,result=pcall(itemRequest,action,g_game.useWith,rune,target,0);sent=ok and result~=false end
  end
  if not sent and type(useWith)=='function' then
    local ok,result=pcall(itemRequest,action,useWith,id,target,0);sent=ok and result~=false
  end
  attempt.count=attempt.count+1
  local ping=math.max(30,math.min(400,tonumber(config('ping')) or 100))
  attempt.nextAt=time()+math.max(350,ping*2+100)
  if not sent then
    attempt.probe=false
    status('No se pudo usar '..action..'; buscando otra abertura.');return false
  end
  -- Sending is not a cast acknowledgement. The actual field/items must vanish.
  state.runeUntil=time()+1000
  state.pending={kind='clean',action=action,pos=copy(tile.pos),origin=copy(p),key=key,push=push,
    dest=copy(dest),probeAt=time()+40,untilAt=time()+math.max(350,ping*2+100)}
  status(action=='destroy' and 'Antitrap: Destroy Field para empujar al jugador.' or 'Antitrap: Disintegrate para empujar al jugador.')
  queueClean(state.pending)
  return true
end
local function tryPush(p,dir,goal,at)
  if config('fleePlayers')~=true then return false end
  local blocked=at or destination(p,dir)
  local source=T.tile(blocked)
  if not source or not source.safe or source.hard or #source.creatures~=1 then return false end
  local creature=source.creatures[1]
  if creature==player or not creature:isPlayer() or creature:getHealthPercent()<=0 or distance(p,creature:getPosition())>5 then return false end
  if #source.trash>0 and distance(p,blocked)>1 then return false end -- never substitute Fire Field at range
  local row=CaveBot.actionList:getFocusedChild()
  local context={id=creature:getId(),from=copy(blocked),origin=copy(p),action=row,actionValue=row and row.value,actionName=row and row.action,
    route=CaveBot.getCurrentProfile(),checkpoint=state.checkpoint,checkpointValue=state.checkpoint and state.checkpoint.value}
  local attempt=pushAttempt(context)
  if time()<attempt.nextAt then return false end
  if attempt.count>=3 then attempt.count=0;attempt.nextAt=time()+750;return false end
  local choices={}
  for _,o in ipairs(offsets)do
    local dest={x=blocked.x+o[1],y=blocked.y+o[2],z=blocked.z}
    local tile=T.tile(dest)
    if not same(dest,p) and tile and tile.safe and not tile.hard and #tile.creatures==0 then
      local clear=tile.field and 'destroy' or #tile.trash>0 and not tile.walkable and 'disintegrate'
      if (tile.walkable or clear)and not(clear=='disintegrate'and distance(p,dest)>1)
        and time()>=(attempt.failed[T.key(dest)]or 0)then
        local ahead=(dest.x-blocked.x)*(blocked.x-p.x)+(dest.y-blocked.y)*(blocked.y-p.y)
        choices[#choices+1]={pos=dest,tile=tile,clear=clear,
          score=(clear and -100 or 0)+(time()<(attempt.failed[T.key(dest)] or 0) and -1000 or 0)+
            (ahead<=0 and 20 or 0)+distance(dest,goal)+distance(dest,p)*2}
      end
    end
  end
  table.sort(choices,function(a,b)return a.score>b.score end)
  if #choices==0 then return false end
  local choice=choices[1]
  -- Select the legal destination before cleaning the source, so the first
  -- removal/replacement-coin window can feed the move without another route tick.
  if source.field then return tryClean(p,source,'destroy',context,choice.pos)end
  if choice.clear then
    -- All usable landings need physical preparation. Do it before opening
    -- the player's antipush so that the final source rune can pair with move.
    for _,landing in ipairs(choices)do
      if landing.clear and tryClean(p,landing.tile,landing.clear,context,landing.pos)then return true end
    end
    return false
  end
  if #source.trash>0 and not probeTrash(source)then return tryClean(p,source,'disintegrate',context,choice.pos)end
  for _,choice in ipairs(choices)do
    if choice.clear then
      if tryClean(p,choice.tile,choice.clear,context,choice.pos)then return true end
    elseif sendPush(context,choice.pos)then return true end
  end
  return false
end
local function unblock(p,dir,goal)
  if state.monster and (not same(state.monster.goal,goal) or not monsterAllowed()) then stopMonster() end
  return tryPush(p,dir,goal) or tryMonster(p,dir,goal)
end
local function unblockNearby(p,goal)
  -- Losing a full minimap path must not prevent fighting the immediate trap.
  -- Inspect only visible adjacent blockers, ordered toward the exit. A free
  -- route still has priority in walkTo; this is never a general hunt scan.
  local choices,costs={},T.stepCosts()
  for dir=0,7 do
    local pos=destination(p,dir)
    local tile=T.tile(pos)
    if tile and tile.safe and not tile.hard and #tile.creatures>0 then
      local eligible,hp=true,0
      if distance(pos,goal)>distance(p,goal)then
        -- A backward blocker is useful only if it leads around the trap,
        -- without immediately returning through our current square.
        local around=T.localPath(pos,goal,true,0,{avoid={[T.key(p)]=true},partial=true})
        eligible=around and around[1]~=nil or false
      end
      for _,creature in ipairs(tile.creatures)do
        if not safeMonster(creature,p,pos)and not(#tile.creatures==1 and creature:isPlayer()and creature:getHealthPercent()>0)then eligible=false;break end
        hp=hp+creature:getHealthPercent()
      end
      if eligible then
        choices[#choices+1]={dir=dir,score=distance(pos,goal)*2+costs[dir+1]+hp/1000,
          owned=state.monster and same(state.monster.from,pos)}
      end
    end
  end
  table.sort(choices,function(a,b)
    if a.score~=b.score then return a.score<b.score end
    if a.owned~=b.owned then return a.owned==true end
    return a.dir<b.dir
  end)
  for _,choice in ipairs(choices)do if unblock(p,choice.dir,goal)then return true end end
  return false
end
function F.walkTo(dest,maxDist,params)
  if not F.isEscaping() then return nil end
  if not g_game.isOnline() or not player or player:getHealthPercent()<=0 or
      config('fleePlayers')~=true or not CaveBot.isOn() then
    F.hold('Salida detenida; revisa PZ, conexion y el interruptor de huida.');return true
  end
  if arrived()then return true end
  local p=player:getPosition()
  local row=CaveBot.actionList:getFocusedChild()
  state.walkRequest={dest=copy(dest),maxDist=maxDist,params=params,action=row,value=row and row.value,route=CaveBot.getCurrentProfile()}
  if HelperPause and HelperPause.isPaused() then stopMonster();state.pending=nil;return true end
  if manual() then stopMonster();state.pending=nil;return true end
  if tickPending(p) then return true end
  if dest.z~=p.z then return false end
  maxDist=math.max(40,math.min(192,tonumber(maxDist) or 192))
  local precision=params and tonumber(params.precision) or 0
  local color=tonumber(g_map.getMinimapColor(dest)) or 0
  local transition=row and row.action=='goto' and same(T.position(row.value),dest) and color>=210 and color<=213
  local avoid=failedTiles(p)
  local path
  if transition then
    path=getPath(p,dest,maxDist,{precision=0,ignoreCreatures=false,ignoreStairs=false,allowUnseen=true})
    path=T.refinePath(p,path,false,avoid)
  else path=T.path(p,dest,false,maxDist,precision,avoid) end
  if not path or not path[1] then
    local blockedPath
    if transition then
      blockedPath=getPath(p,dest,maxDist,{precision=0,ignoreCreatures=true,ignoreNonPathable=true,ignoreStairs=false,allowUnseen=true})
      blockedPath=T.refinePath(p,blockedPath,true,avoid)
    else blockedPath=T.path(p,dest,true,maxDist,precision,avoid) end
    if not blockedPath then state.pathLostAt=state.pathLostAt or time()else state.pathLostAt=nil end
    local partial=not blockedPath and T.localPath(p,dest,false,precision,{avoid=avoid,partial=true})or nil
    if partial and partial[1]then
      path=partial -- visible progress only; the complete route is retried after this step.
    elseif blockedPath and blockedPath[1] and clearTile(destination(p,blockedPath[1])) then
      path=blockedPath -- approach a more distant blocker through its free prefix.
    else
      local acted=blockedPath and blockedPath[1]and unblock(p,blockedPath[1],dest)
      if not acted then acted=unblockNearby(p,dest)end
      if not acted then
        stopMonster()
        state.waiting=true;status('Sin paso libre: buscando salida entre bloqueadores y paredes.')
      end
      return true
    end
  else state.pathLostAt=nil end
  path=T.cardinalFirst(p,path,dest,avoid)
  -- Try a visible player obstruction from native range before walking into its
  -- melee trap. A coin pile still requires Disintegrate at one SQM; no fire.
  local probe=copy(p)
  for i=1,math.min(5,#path)do
    probe=destination(probe,path[i]);local t=T.tile(probe)
    if not t or not t.safe or t.hard then break end
    if #t.creatures>0 then
      local cleared=state.clearedPush
      if i>1 and not(cleared and same(p,cleared.origin)and #t.creatures==1 and t.creatures[1]:getId()==cleared.id)
        and tryPush(p,path[i],dest,probe)then stopMonster();return true end
      break
    end
  end
  local first=destination(p,path[1])
  local tile=first and g_map.getTile(first)
  if transition and same(first,dest) and tile and tile:isWalkable(false) and #(tile:getCreatures() or {})==0 then
    -- This exact recorded entry must trigger its confirmed floor change.
    if safeBotWalk(path[1])~=false then
      state.pending={kind='walk',from=copy(p),last=copy(p),dest=copy(first),progressAt=time(),timeout=700}
    else rememberFailedStep(p,first)end
    return true
  end
  if not clearTile(first) then
    if not unblock(p,path[1],dest) then stopMonster();state.waiting=true;status('Paso bloqueado; revisando la salida.') end
    return true
  end
  if state.monster then stopMonster();status('Paso libre; continuando la salida.') end
  if state.approach and not clearTile(first) then
    state.waiting=true;status('Recalculando acceso directo a Supply Check.');return true
  end
  -- Ordinary native walking only. Confirm this step before sending another;
  -- cleanup, creatures, manual control and floor safety were checked above.
  if safeBotWalk(path[1])~=false then
    if state.waiting then state.waiting=false;status('Paso libre; continuando hacia la salida.')end
    local ok,duration=pcall(function()return player:getStepDuration(false,path[1])end)
    duration=ok and tonumber(duration)or 200
    state.pending={kind='walk',from=copy(p),last=copy(p),dest=copy(first),progressAt=time(),
      timeout=math.max(400,duration+2*(tonumber(config('ping'))or 100))}
  else
    rememberFailedStep(p,first)
    state.waiting=true;status('Paso rechazado; revisando la salida.')
  end
  return true
end
local function updatePlan(budget)
  local plan=state.plan
  local p=player:getPosition()
  if plan and plan.done and time()>=(state.replanAt or 0) and
    (distance(p,plan.origin)>=3 or state.pathLostAt and time()-state.pathLostAt>=1200)then
    state.plan=T.plan(CaveBot.actionList:getChildren(),CaveBot.actionList:getChildIndex(CaveBot.actionList:getFocusedChild()) or 1,p,state.destination)
    state.planBest=nil;state.replanAt=time()+750;plan=state.plan
  end
  if not plan or plan.done then return end
  local best=T.advancePlan(plan,p,budget)
  if best and (state.planBest~=best) then
    if not CaveBot.actionList:getChildIndex(best.row) or not CaveBot.actionList:getChildIndex(best.checkpoint) then
      F.hold('La ruta cambio durante el calculo de salida. Activa CaveBot para reintentar.');return
    end
    local changed=state.approach and not same(state.approach,best.goal)
    if changed then stopWalking() end
    state.planBest=best;state.approach=copy(best.goal);state.resume=best.row;state.checkpoint=best.checkpoint
    status('Ruta corta a '..destinationName()..': '..tostring(best.steps or math.floor(best.cost))..' pasos de mapa/ruta; movimiento normal.')
  end
end
local skipped={delay=true,waitstamina=true,lure=true,standlure=true,follow=true,setprofile=true}
local allowed={label=true,["goto"]=true,floorchange=true,stepdirection=true,use=true,usewith=true,
  gotolabel=true,opendoors=true,travel=true,poscheck=true,say=true,npcsay=true}
function F.action(current)
  if not F.isEscaping() then return nil end
  if arrived()then return 'retry'end
  if manual() then stopMonster();state.pending=nil;return 'retry' end
  if state.monster and not monsterAllowed() then stopMonster() end
  local checkGoal=current.action==state.destination and(state.destination=='zonapz'and T.zonePosition(current.value)or T.position(tostring(current.value):match('^[^,]*,(.*)$')))
  if state.phase=='check' and not (checkGoal and same(player:getPosition(),checkGoal)) then updatePlan(1) end
  if not F.isEscaping()then return 'retry'end
  if state.approach then
    if player:getPosition().z~=state.approach.z then
      F.hold('Cambio de piso inesperado hacia '..destinationName()..'. Revisa la salida.');return 'retry'
    end
    if same(player:getPosition(),state.approach) then
      state.approach=nil
      CaveBot.actionList:focusChild(state.resume or state.checkpoint)
      state.resume=nil
      CaveBot.wakeRoute()
    else
      F.walkTo(state.approach,192,{precision=0})
    end
    return 'retry'
  end
  local action,value=current.action,current.value
  if skipped[action] then return true end
  if action=='gotolabel' and state.phase=='check' then return true end
  if action=='zonapz'then
    local goal=T.zonePosition(value)
    if not goal then F.hold('ZonaPZ tiene coordenadas invalidas.');return 'retry'end
    if goal.z~=player:getPosition().z or distance(player:getPosition(),goal)>192 then
      F.hold('ZonaPZ requiere waypoints intermedios o una transicion de piso. Revisa la salida.');return 'retry'
    end
    F.walkTo(goal,192,{precision=0});return 'retry'
  end
  if action=='supplycheck' and state.destination=='zonapz'then return true end
  if action=='supplycheck' then
    if state.phase=='exit' then F.hold('El regreso encontro otro Supply Check antes de PZ. Revisa la ruta.');return 'retry' end
    local coords=tostring(value):match('^[^,]*,(.*)$')
    local goal=coords and position(coords)
    if coords and not goal then F.hold('Supply Check tiene coordenadas invalidas.');return 'retry' end
    if goal and not same(player:getPosition(),goal) then
      if goal.z~=player:getPosition().z or distance(player:getPosition(),goal)>192 then
        F.hold('Supply Check fuera de alcance o en otro piso. Revisa la salida.');return 'retry'
      end
      F.walkTo(goal,192);return 'retry'
    end
    state.huntLabel=tostring(value):match('^([^,]*)'):lower():gsub('^%s*(.-)%s*$','%1')
    state.phase='exit';state.checkpoint=nil
    status('Supply Check alcanzado: salida forzada hasta PZ.')
    return false -- Same branch as insufficient supplies, without changing saved supply flags.
  end
  if action=='goto' then
    local goal,precision=position(value)
    if not goal then F.hold('Waypoint de salida invalido.');return 'retry' end
    local p=player:getPosition()
    if p.z~=goal.z then
      if state.floorFrom==goal.z and time()-(state.floorAt or 0)<3000 then return true end
      F.hold('Waypoint de otro piso sin transicion confirmada. Revisa la ruta.');return 'retry'
    end
    local color=tonumber(g_map.getMinimapColor(goal)) or 0
    if color>=210 and color<=213 then precision=0 end
    if distance(p,goal)<=(precision or 0) then state.pending=nil;return true end
    if distance(p,goal)>192 then
      F.hold('Waypoint de salida demasiado lejos. Revisa la ruta.');return 'retry'
    end
    F.walkTo(goal,192,{precision=precision or 0});return 'retry'
  end
  if action=='usewith' then
    local id=tonumber(tostring(value):match('^%s*(%d+)'))
    if not tools[id] then F.hold('Use With no permitido durante huida. Usa acciones de escalera/puerta.');return 'retry' end
  end
  if action=='gotolabel' and state.phase=='exit' and tostring(value):lower():gsub('^%s*(.-)%s*$','%1')==state.huntLabel then
    F.hold('El regreso intenta volver a la hunt antes de PZ. Revisa la salida.');return 'retry'
  end
  if action=='say' then
    local words=tostring(value):lower():gsub('"',''):gsub('^%s*(.-)%s*$','%1')
    local movementWords={['exani hur up']=true,['exani hur down']=true,['exani tera']=true,
      ['utani hur']=true,['utani gran hur']=true,['utani tempo hur']=true,['utamo tempo san']=true}
    if not movementWords[words] then
      F.hold('Say no permitido durante huida. Usa NPC Say para dialogos o spells de movimiento.');return 'retry'
    end
  end
  if not allowed[action] then
    F.hold('La salida contiene '..tostring(action)..'. Usa acciones de movimiento nativas para este tramo.')
    return 'retry'
  end
  if action=='use' and not position(value) then
    F.hold('Use sin coordenadas durante huida. Indica el punto de escalera o puerta.');return 'retry'
  end
  return nil -- Route movement/doors/travel retain their native confirmation.
end
function F.onRouteLoaded(name)
  zoneCompletion=nil
  if state.phase=='rest'and name==state.route then
    local row=CaveBot.actionList:getChildren()[state.restIndex or 0]
    if row and row.action=='zonapz'and row.value==state.zoneValue then
      state.checkpoint=row;state.restAt=time();return -- Native ON/OFF rebuilds the same row widgets.
    end
  end
  if F.isEscaping()or state.phase=='rest'then F.hold('La ruta se recargo o cambio. Huida/espera detenida; activa CaveBot para reintentar.')end
end
function F.zoneAction(value)
  local zone=T.zoneConfig(value)
  if not zone then warn('CaveBot[ZonaPZ]: coordenadas o minutos invalidos.');return false end
  local row=CaveBot.actionList:getFocusedChild()or CaveBot.actionList:getChildren()[1]
  if row then CaveBot.actionList:focusChild(row)end
  if zoneCompletion and zoneCompletion.row==row and zoneCompletion.value==value
    and zoneCompletion.route==CaveBot.getCurrentProfile()and isInPz()then zoneCompletion=nil;return true end
  zoneCompletion=nil
  if F.blocksCombat()then return 'retry'end
  return true -- Only an observed player attack can begin the arrival/rest controller.
end
local function begin(attacker)
  session=session+1
  state={phase='check',route=CaveBot.getCurrentProfile(),started=time(),replanAt=time()+750,clearAttempts={}}
  state.itemJob={number='flee:'..session}
  if PushMax and type(PushMax.cancel)=='function'then PushMax.cancel('Prioridad Huida PvP')end
  if CaveBot.stopRecording then CaveBot.stopRecording() end
  if CaveBot.AutoExplorer and CaveBot.AutoExplorer.isOn() then CaveBot.AutoExplorer.disable() end
  stopWalking();suppressCombat()
  if CaveBot.CancelNpcConversation then CaveBot.CancelNpcConversation() end
  if TargetBot and TargetBot.Antitrap then TargetBot.Antitrap.reset() end
  if CaveBot.wakeRoute then CaveBot.wakeRoute() end
  local children=CaveBot.actionList:getChildren()
  local index=CaveBot.actionList:getChildIndex(CaveBot.actionList:getFocusedChild()) or 1
  index=math.max(1,index)
  state.destination='supplycheck'
  local hasZone=false
  for _,child in ipairs(children)do
    if child.action=='zonapz'then
      hasZone=true
      if T.zonePosition(child.value)then state.destination='zonapz'end
    end
  end
  if hasZone and state.destination~='zonapz'then F.hold('Ataque de '..attacker:getName()..'; ZonaPZ tiene coordenadas invalidas.');return end
  for offset=0,#children-1 do
    local child=children[(index+offset-1)%#children+1]
    if child.action==state.destination and(child.action~='zonapz'or T.zonePosition(child.value))then state.checkpoint=child;break end
  end
  if not state.checkpoint then F.hold('Ataque de '..attacker:getName()..'; agrega ZonaPZ a esta ruta.');return end
  state.plan=T.plan(children,index,player:getPosition(),state.destination)
  updatePlan(2)
  if not F.isEscaping()then return end
  status('Ataque de '..attacker:getName()..': hacia '..destinationName()..', combate suspendido.')
end
-- Wake only the last validated movement request. Native door/NPC/travel
-- callbacks and route focus advancement remain owned by the route executor.
local function liveWalkRequest()
  local r=state.walkRequest
  return r and r.route==CaveBot.getCurrentProfile()and r.action==CaveBot.actionList:getFocusedChild()
    and CaveBot.actionList:getChildIndex(r.action)and r.action.value==r.value and r or nil
end
function F.wake()
  if wakePending or type(schedule)~='function'or not F.getItemJob()then return end
  local job=state.itemJob
  wakePending=true
  schedule(0,function()
    wakePending=false
    if state.itemJob~=job or not F.getItemJob()or manual()or HelperPause and HelperPause.isPaused()then return end
    local r=liveWalkRequest()
    if not r or r.dest.z~=player:getPosition().z then return end
    local ok,err=pcall(F.walkTo,r.dest,r.maxDist,r.params)
    if not ok then status('Recalculando movimiento tras error: '..tostring(err):sub(1,100))end
  end)
end
function F.getSnapshot()
  local p=state.pending
  return {revision='R139',phase=state.phase,status=F.getStatus(),noFire=true,
    pending=p and p.kind,remainingMs=p and p.untilAt and math.max(0,p.untilAt-time()),
    playerDistance=p and p.sqm,adaptive=p and p.adaptive,watchdogRecoveries=state.watchdogRecoveries or 0}
end
function F.poll()
  if F.blocksCombat() then
    suppressCombat()
    if state.phase=='stopped'then
      if CaveBot.isOn() and g_game.isOnline() and player and player:getHealthPercent()>0 then
        F.finish('Ruta retomada; deteccion de ataques activa.')
      else F.refreshUi()end
      return
    end
    if config('fleePlayers')~=true then F.finish('Huida desactivada; la ruta continua.');return end
    if state.phase=='rest'then pollZoneRest();return end
    if not g_game.isOnline() or not player or player:getHealthPercent()<=0 then F.hold('Huida detenida: desconexion o muerte.');return end
    if arrived()then return end
    if not CaveBot.isOn() then F.hold('Huida pausada al apagar CaveBot. Activa CaveBot para reintentar.');return end
    if time()-state.started>600000 then F.hold('La salida no alcanzo PZ en 10 minutos. Revisa la ruta.');return end
    local p=player:getPosition()
    if not same(p,state.progressPos)then state.progressPos=copy(p);state.progressAt=time()end
    if not manual()and not(HelperPause and HelperPause.isPaused())and liveWalkRequest()
      and time()-(state.progressAt or time())>=750 and time()-(state.watchdogAt or 0)>=750 then
      state.watchdogAt=time();state.watchdogRecoveries=(state.watchdogRecoveries or 0)+1
      if CaveBot.wakeRoute then CaveBot.wakeRoute(false)end
      F.wake()
    end
    return
  end
  if config('fleePlayers')~=true or not CaveBot.isOn or not CaveBot.isOn() or not g_game.isOnline()
    or not player or player:getHealthPercent()<=0 or isInPz() or HelperPause and HelperPause.isPaused() then return end
  local p=player:getPosition()
  if not p then return end
  for _,creature in ipairs(getSpectators(false) or {})do
    if creature~=player and creature:isPlayer() and creature:getHealthPercent()>0 and creature.isTimedSquareVisible
      and distance(p,creature:getPosition())<=8 then
      local ok,attacking=pcall(function()return creature:isTimedSquareVisible()end)
      if ok and attacking==true then begin(creature);return end
    end
  end
end
function F.refreshUi()
  local ui=F.ui
  if ui then
    ui.statusCard.status:setText(F.getStatus())
    ui.resetRest:setEnabled(resettableZone()~=nil)
  end
end
function F.setup()
  local ui=UI.createWidget('CaveBotPvpFleePanel',CaveBot.Config.window.security.contents);F.ui=ui
  CaveBot.Config.add('fleePlayers','Huir si me ataca un jugador',true,ui.options)
  ui.resetRest.onClick=function()F.resetZoneRest()end
  F.refreshUi()
end
onPlayerPositionChange(function(newPos,oldPos)
  if not F.isEscaping() or not newPos or not oldPos then return end
  if not same(newPos,oldPos)then state.failedSteps=nil;state.pathLostAt=nil end
  if newPos.z~=oldPos.z then state.floorFrom=oldPos.z;state.floorAt=time() end
  arrived()
  F.wake()
end)
if type(onCreaturePositionChange)=='function'then onCreaturePositionChange(function(c)
  if F.isEscaping()and c then F.wake()end
end)end
local function mapChanged(tile)
  local p=tile and tile.getPosition and tile:getPosition()
  if F.isEscaping()and p and distance(p,player:getPosition())<=6 then F.wake()end
end
if type(onAddThing)=='function'then onAddThing(mapChanged)end
if type(onRemoveThing)=='function'then onRemoveThing(mapChanged)end
macro(100,function()
  local ok,err=pcall(F.poll)
  if not ok then F.hold('Error de huida: '..tostring(err));warn('[Huida PvP] '..tostring(err)) end
end)
