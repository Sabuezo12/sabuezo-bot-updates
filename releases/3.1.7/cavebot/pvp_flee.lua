-- Route-local emergency exit. PZ releases the emergency without a manual rearm;
-- only the immediate monster obstruction may receive an owned basic attack.
CaveBot.Flee = {}
local F = CaveBot.Flee
local T = assert(CaveBot.FleeTools, "Huida: falta el planificador de salida.")
local state={phase='idle'}
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
  local goal=T.zonePosition(row.value)
  if not goal then F.hold('ZonaPZ tiene coordenadas invalidas.');return true end
  if not same(player:getPosition(),goal)then state.arrivedAt=nil;return false end
  stopMonster()
  if not state.arrivedAt then stopWalking();state.arrivedAt=time()end
  if not isInPz()then
    if time()-state.arrivedAt>=1500 then F.hold('ZonaPZ alcanzada sin proteccion PZ. Corrige ese punto de la ruta.')
    else status('ZonaPZ alcanzada; esperando confirmacion PZ del cliente.')end
    return true
  end
  CaveBot.actionList:focusChild(row)
  F.finish('ZonaPZ alcanzada; CaveBot continua por la ruta.')
  return true
end
local function movement() return TargetBot and TargetBot.Movement end
local function manual() local m=movement();return m and m.isManual(time()) end
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
  return not creature.canShoot or creature:canShoot()
end
local singleAmmo={[3447]=true,[3448]=true,[763]=true,[761]=true,[7365]=true,[762]=true,[21470]=true,
  [7364]=true,[14251]=true,[15793]=true,[774]=true,[16143]=true,[6528]=true,[7363]=true,[3450]=true,
  [16141]=true,[35902]=true,[14252]=true,[3446]=true,[16142]=true}
local function monsterShotSafe(creature)
  local ammo=type(getAmmo)=='function' and getAmmo() or nil
  local id=ammo and ammo:getId()
  local vocation=type(voc)=='function' and voc() or nil
  -- A closed quiver does not reveal its ammunition. For a paladin with unknown
  -- ammo, apply the larger arrow area rather than assume a single-target shot.
  local radius=0
  if id==3449 then radius=1
  elseif id==35901 or id==25757 or (vocation==2 or vocation==12) and not singleAmmo[id] then radius=2 end
  if radius==0 then return true end
  local centre=creature:getPosition()
  for _,actor in ipairs(getSpectators(false) or {})do
    if actor~=player and actor:isPlayer() then
      local p=actor:getPosition()
      local dx,dy=p and math.abs(p.x-centre.x),p and math.abs(p.y-centre.y)
      if p and p.z==centre.z and dx<=radius and dy<=radius and not (radius==2 and dx==2 and dy==2) then return false end
    end
  end
  return true
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
  return safeMonster(creature,player:getPosition(),owned.from) and monsterShotSafe(creature)
    and g_game.getChaseMode and g_game.getChaseMode()==0
end
local function tryMonster(p,dir,goal)
  if config('fleePlayers')~=true then return false end
  local blocked=destination(p,dir)
  local tile=blocked and g_map.getTile(blocked)
  if not tile or not floorSafe(blocked,tile) then return false end
  local creatures=tile:getCreatures() or {}
  local creature=#creatures==1 and creatures[1]
  if not safeMonster(creature,p,blocked) then return false end
  if not monsterShotSafe(creature) then
    stopMonster();status('Monstruo bloqueando: flechas de area cerca de jugadores; esperando paso seguro.');return true
  end
  local retry=state.monsterRetry
  if retry and retry.id==creature:getId() and time()<retry.after then return true end
  local owned=state.monster
  if owned and (owned.id~=creature:getId() or not same(owned.from,blocked) or not same(owned.goal,goal)) then stopMonster();owned=nil end
  if not owned then
    if not g_game.getChaseMode or not g_game.setChaseMode or not g_game.attack then return false end
    stopWalking()
    owned={id=creature:getId(),from=copy(blocked),origin=copy(p),goal=copy(goal),
      action=CaveBot.actionList:getFocusedChild(),chaseBefore=g_game.getChaseMode(),lastRequest=-math.huge,requests=0}
    state.monster=owned
    g_game.setChaseMode(0) -- Never chase a monster that leaves the route obstruction.
  end
  if not monsterAllowed() then stopMonster();return false end
  local current=g_game.getAttackingCreature()
  if current and current:getId()==owned.id then return true end
  if time()-owned.lastRequest<500 then return true end
  if owned.requests>=3 then
    state.monsterRetry={id=owned.id,after=time()+5000};stopMonster()
    status('Ataque al bloqueo sin confirmar; esperando otro paso.');return true
  end
  owned.requests=owned.requests+1;owned.lastRequest=time()
  local ok,result=pcall(g_game.attack,creature)
  if not ok or result==false then
    state.monsterRetry={id=owned.id,after=time()+1000};stopMonster()
    status('No se pudo atacar al monstruo que bloquea.');return true
  end
  status('Antitrap: atacando a '..creature:getName()..'; saldra en cuanto se abra el paso.')
  return true
end
local function tickPending(p)
  local pending=state.pending
  if not pending then return false end
  if pending.kind=='clean' then
    local tile=T.tile(pending.pos)
    local cleared=tile and (pending.action=='destroy' and not tile.field or pending.action=='disintegrate' and #tile.trash==0)
    if cleared then
      state.pending=nil;state.clearAttempts[pending.key]=nil
      status('Casilla despejada; continuando salida.');return false
    end
    if not same(p,pending.origin) or not tile or tile.hard then state.pending=nil;return false end
    if time()<pending.untilAt then return true end
    state.pending=nil
    local attempt=state.clearAttempts[pending.key]
    if attempt and pending.action=='disintegrate' then attempt.probe=true end
    status('Limpieza sin confirmar; revisando otro paso.')
    return false
  end
  if pending.kind=='push' then
    local creature=getCreatureById(pending.id)
    if not creature or not same(creature:getPosition(),pending.from) then
      state.pending=nil;status('Paso despejado; retomando salida.');return false
    end
    if time()<pending.untilAt then return true end
    state.pending=nil
    local attempt=state.pushAttempt
    if attempt and attempt.key==pending.key then
      attempt.failed=attempt.failed or {};attempt.failed[T.key(pending.dest)]=time()+1500
      local source=state.clearAttempts[T.key(pending.from)..':disintegrate']
      if source then source.probe=false end
    end
    status('Empuje sin confirmar; buscando paso libre.')
    return false
  end
  if same(p,pending.dest) or p.z~=pending.from.z then state.pending=nil;state.shortBug=nil;return false end
  if not same(p,pending.last) then
    pending.last=copy(p);pending.progressAt=time()
    if pending.kind=='bugmap' and distance(p,pending.dest)<=2 then
      state.pending=nil;return false -- extend the ground-use run before it stops.
    end
  end
  if time()-pending.progressAt<pending.timeout then return true end
  if pending.kind=='bugmap' then
    state.shortBug=true
    status('BugMap sin avance; reintentando con un tramo corto.')
  end
  stopWalking()
  return false
end
local function tryClean(p,tile,action)
  if not tile or not tile.safe or tile.hard or not tile.shootable then return false end
  local target=action=='destroy' and tile.field or tile.trash[#tile.trash]
  if not target or distance(p,tile.pos)>(action=='destroy' and 5 or 1) then return false end
  state.clearAttempts=state.clearAttempts or {}
  local key=T.key(tile.pos)..':'..action
  local attempt=state.clearAttempts[key]
  if not attempt then attempt={count=0,nextAt=0};state.clearAttempts[key]=attempt end
  if time()<attempt.nextAt or time()<(state.runeUntil or 0) then
    status('Esperando runa de limpieza para liberar la salida.');return true
  end
  if attempt.count>=3 then
    attempt.count=0;attempt.nextAt=time()+1500
    status('Limpieza rechazada o sin runas; reintento limitado.');return true
  end
  -- Emergency mode never imports an offensive/field/wall rune from a custom
  -- Push Max setting. Only these known cleanup actions are allowed here.
  local id=action=='destroy' and 3148 or 3197
  local sent=false
  if type(g_game.useInventoryItemWith)=='function' then
    local ok,result=pcall(g_game.useInventoryItemWith,id,target,0);sent=ok and result~=false
  end
  if not sent and type(findItem)=='function' and type(g_game.useWith)=='function' then
    local rune=findItem(id)
    if rune then local ok,result=pcall(g_game.useWith,rune,target,0);sent=ok and result~=false end
  end
  if not sent and type(useWith)=='function' then
    local ok,result=pcall(useWith,id,target,0);sent=ok and result~=false
  end
  attempt.count=attempt.count+1
  local ping=math.max(30,math.min(400,tonumber(config('ping')) or 100))
  attempt.nextAt=time()+math.max(350,ping*2+100)
  if not sent then
    if action=='disintegrate' then attempt.probe=true end
    status('No se pudo usar '..action..'; esperando runa.');return true
  end
  -- Sending is not a cast acknowledgement. The actual field/items must vanish.
  state.runeUntil=time()+1000
  state.pending={kind='clean',action=action,pos=copy(tile.pos),origin=copy(p),key=key,
    untilAt=time()+math.max(350,ping*2+100)}
  status(action=='destroy' and 'Antitrap: Destroy Field sobre el campo de la salida.' or 'Antitrap: Disintegrate sobre los objetos del bloqueo.')
  return true
end
local function tryPush(p,dir,goal)
  if config('fleePlayers')~=true then return false end
  local blocked=destination(p,dir)
  local source=T.tile(blocked)
  if not source or not source.safe or source.hard or #source.creatures~=1 then return false end
  local creature=source.creatures[1]
  if creature==player or not creature:isPlayer() or creature:getHealthPercent()<=0 or distance(p,creature:getPosition())~=1 then return false end
  if source.field then return tryClean(p,source,'destroy') end
  local sourceClean=state.clearAttempts and state.clearAttempts[T.key(blocked)..':disintegrate']
  if #source.trash>0 and not (sourceClean and sourceClean.probe) then return tryClean(p,source,'disintegrate') end
  local key=tostring(creature:getId())..':'..T.key(blocked)
  local attempt=state.pushAttempt
  if not attempt or attempt.key~=key then attempt={key=key,count=0,nextAt=0,failed={}};state.pushAttempt=attempt end
  if time()<attempt.nextAt then return false end
  if attempt.count>=3 then attempt.count=0;attempt.nextAt=time()+750;return false end
  local choices={}
  for _,o in ipairs(offsets)do
    local dest={x=blocked.x+o[1],y=blocked.y+o[2],z=blocked.z}
    local tile=T.tile(dest)
    if not same(dest,p) and tile and tile.safe and not tile.hard and #tile.creatures==0 then
      local clear=tile.field and 'destroy' or #tile.trash>0 and 'disintegrate'
      local prior=state.clearAttempts and state.clearAttempts[T.key(dest)..':disintegrate']
      if clear=='disintegrate' and tile.walkable and prior and prior.probe then clear=nil end
      if tile.walkable or clear then
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
  if choice.clear then return tryClean(p,choice.tile,choice.clear) end
  attempt.count=attempt.count+1
  local ping=math.max(30,math.min(400,tonumber(config('ping')) or 100))
  local wait=math.max(200,ping*2+60)
  attempt.nextAt=time()+wait
  local ok,result=pcall(g_game.move,creature,choice.pos,1)
  if not ok or result==false then
    attempt.failed[T.key(choice.pos)]=time()+1500
    status('Empuje rechazado; probando otra casilla de salida.');return true
  end
  state.pending={kind='push',id=creature:getId(),from=copy(blocked),dest=copy(choice.pos),key=key,untilAt=time()+wait}
  status('Antitrap: esperando confirmacion del empuje de '..creature:getName()..'.')
  return true
end
local function unblock(p,dir,goal)
  if state.monster and (not same(state.monster.from,destination(p,dir)) or not same(state.monster.goal,goal) or not monsterAllowed()) then stopMonster() end
  local tile=T.tile(destination(p,dir))
  if tile and tile.safe and not tile.hard then
    if tile.field then return tryClean(p,tile,'destroy') end
    if #tile.creatures==0 and #tile.trash>0 then return tryClean(p,tile,'disintegrate') end
  end
  return tryPush(p,dir,goal) or tryMonster(p,dir,goal)
end
function F.walkTo(dest,maxDist,params)
  if not F.isEscaping() then return nil end
  if not g_game.isOnline() or not player or player:getHealthPercent()<=0 or
      config('fleePlayers')~=true or not CaveBot.isOn() then
    F.hold('Salida detenida; revisa PZ, conexion y el interruptor de huida.');return true
  end
  if arrived()then return true end
  local p=player:getPosition()
  if HelperPause and HelperPause.isPaused() then stopMonster();state.pending=nil;return true end
  if manual() then stopMonster();state.pending=nil;return true end
  if tickPending(p) then return true end
  if dest.z~=p.z then return false end
  maxDist=math.max(40,math.min(192,tonumber(maxDist) or 192))
  local precision=params and tonumber(params.precision) or 0
  local row=CaveBot.actionList:getFocusedChild()
  local color=tonumber(g_map.getMinimapColor(dest)) or 0
  local transition=row and row.action=='goto' and same(T.position(row.value),dest) and color>=210 and color<=213
  local path
  if transition then
    path=getPath(p,dest,maxDist,{precision=0,ignoreCreatures=false,ignoreStairs=false,allowUnseen=true})
  else path=T.path(p,dest,false,maxDist,precision) end
  if not path or not path[1] then
    local blockedPath
    if transition then blockedPath=getPath(p,dest,maxDist,{precision=0,ignoreCreatures=true,ignoreNonPathable=true,ignoreStairs=false,allowUnseen=true})
    else blockedPath=T.path(p,dest,true,maxDist,precision) end
    if blockedPath and blockedPath[1] and clearTile(destination(p,blockedPath[1])) then
      path=blockedPath -- approach a more distant blocker through its free prefix.
    else
      if not (blockedPath and blockedPath[1] and unblock(p,blockedPath[1],dest)) then
        stopMonster()
        state.waiting=true;status('Sin paso libre hacia la salida; esperando un hueco o limpieza.')
      end
      return true
    end
  end
  local first=destination(p,path[1])
  local tile=first and g_map.getTile(first)
  if transition and same(first,dest) and tile and tile:isWalkable(false) and #(tile:getCreatures() or {})==0 then
    -- This exact recorded entry must trigger its floor change. Ground-use
    -- shortcuts cannot replace a confirmed stair step.
    if safeBotWalk(path[1])~=false then
      state.pending={kind='walk',from=copy(p),last=copy(p),dest=copy(first),progressAt=time(),timeout=700}
    end
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
  -- Only a verified, visible, level path may be accelerated. A stair entry is
  -- a single ordinary step; it must never be skipped by a ground use.
  local endpoint=copy(p)
  local segment={}
  for i=1,math.min(#path,state.shortBug and 1 or 7)do
    if i>1 and path[i]~=path[1] then break end -- use only the next verified straight segment.
    local candidate=destination(endpoint,path[i])
    if not candidate or not clearTile(candidate) then break end
    endpoint=candidate;segment[#segment+1]=path[i]
  end
  local kind='bugmap'
  local sent=false
  if #segment>=1 and config('fleePlayers')==true then
    if BugMapMouse and BugMapMouse.tryUsePosition then
      sent=BugMapMouse.tryUsePosition(endpoint)==true
      if not sent then return true end -- cooldown/manual rejection must not turn into ordinary walking.
    elseif tile and tile.getGround and tile:getGround() then
      local useGround=use or g_game.use
      if type(useGround)=='function' then
        local ok,result=pcall(useGround,g_map.getTile(endpoint):getGround());sent=ok and result~=false
      end
    end
  end
  if not sent then
    -- Compatibility only when this client exposes no ground-use API.
    endpoint=first;kind='walk';sent=safeBotWalk(path[1])~=false
  end
  if sent then
    if state.waiting then state.waiting=false;status('Paso libre; continuando hacia la salida.') end
    local duration=tonumber(player:getStepDuration(false,path[1])) or 200
    state.pending={kind=kind,from=copy(p),last=copy(p),dest=copy(endpoint),progressAt=time(),
      timeout=math.max(400,duration+2*(tonumber(config('ping')) or 100))}
  end
  return true
end
local function updatePlan(budget)
  local plan=state.plan
  local p=player:getPosition()
  if plan and plan.done and time()>=(state.replanAt or 0) and distance(p,plan.origin)>=3 then
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
    status('Ruta corta a '..destinationName()..': '..tostring(math.floor(best.cost))..' pasos de mapa/ruta; BugMap activo.')
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
  if F.isEscaping() then F.hold('La ruta se recargo o cambio. Huida detenida; activa CaveBot para reintentar.') end
end
local function begin(attacker)
  state={phase='check',route=CaveBot.getCurrentProfile(),started=time(),replanAt=time()+750,clearAttempts={}}
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
  for _,child in ipairs(children)do
    if child.action=='zonapz'then
      if not T.zonePosition(child.value)then F.hold('Ataque de '..attacker:getName()..'; ZonaPZ tiene coordenadas invalidas.');return end
      state.destination='zonapz'
    end
  end
  for offset=0,#children-1 do
    local child=children[(index+offset-1)%#children+1]
    if child.action==state.destination then state.checkpoint=child;break end
  end
  if not state.checkpoint then F.hold('Ataque de '..attacker:getName()..'; agrega ZonaPZ a esta ruta.');return end
  state.plan=T.plan(children,index,player:getPosition(),state.destination)
  updatePlan(2)
  if not F.isEscaping()then return end
  status('Ataque de '..attacker:getName()..': hacia '..destinationName()..', combate suspendido.')
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
    if not g_game.isOnline() or not player or player:getHealthPercent()<=0 then F.hold('Huida detenida: desconexion o muerte.');return end
    if arrived()then return end
    if not CaveBot.isOn() then F.hold('Huida pausada al apagar CaveBot. Activa CaveBot para reintentar.');return end
    if config('fleePlayers')~=true then F.finish('Huida desactivada; la ruta continua.');return end
    if time()-state.started>600000 then F.hold('La salida no alcanzo PZ en 10 minutos. Revisa la ruta.');return end
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
  if ui then ui.statusCard.status:setText(F.getStatus())end
end
function F.setup()
  local ui=UI.createWidget('CaveBotPvpFleePanel',CaveBot.Config.window.security.contents);F.ui=ui
  CaveBot.Config.add('fleePlayers','Huir si me ataca un jugador',true,ui.options)
  F.refreshUi()
end
onPlayerPositionChange(function(newPos,oldPos)
  if not F.isEscaping() or not newPos or not oldPos then return end
  if newPos.z~=oldPos.z then state.floorFrom=oldPos.z;state.floorAt=time() end
  arrived()
end)
macro(100,function()
  local ok,err=pcall(F.poll)
  if not ok then F.hold('Error de huida: '..tostring(err));warn('[Huida PvP] '..tostring(err)) end
end)
