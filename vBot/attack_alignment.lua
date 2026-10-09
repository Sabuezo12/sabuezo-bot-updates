-- Cooperative, bounded preparation of the NEXT directional attack. No native
-- path search, bot delays, per-tile macros or movement while gathering/looting.
AttackAlignment = {}
local A=AttackAlignment
local dirs={{0,-1,0},{1,0,1},{0,1,2},{-1,0,3},{1,-1,4},{1,1,5},{-1,1,6},{-1,-1,7}}
local motion,plan,lastSearch,lastOrigin=nil,nil,0,nil
local chaseBefore,avoidUntil,lastTurn=nil,0,0
local pendingStep=nil
local function point(p) return {x=p.x,y=p.y,z=p.z} end
local function same(a,b) return a and b and a.x==b.x and a.y==b.y and a.z==b.z end
local function distance(a,b) return math.max(math.abs(a.x-b.x),math.abs(a.y-b.y)) end
local function key(p) return p.x..':'..p.y..':'..p.z end
local function emergency()
  local safety=TargetBot and TargetBot.Antitrap
  return safety and safety.ownsMovement and safety.ownsMovement()
end
local function restoreChase()
  if chaseBefore==nil or emergency() then return end
  if g_game.getChaseMode and g_game.setChaseMode then
    local ok,value=pcall(g_game.getChaseMode)
    if ok and value==0 then pcall(g_game.setChaseMode,chaseBefore) end
  end
  chaseBefore=nil
end
local function holdChase()
  if not g_game.getChaseMode or not g_game.setChaseMode then return end
  local ok,value=pcall(g_game.getChaseMode)
  if not ok then return end
  if chaseBefore==nil then chaseBefore=value end
  if value~=0 then pcall(g_game.setChaseMode,0) end
end
function A.reset(clearContext)
  plan=nil;pendingStep=nil
  if clearContext then motion=nil;lastSearch=0;lastOrigin=nil;avoidUntil=0;lastTurn=0 end
  restoreChase()
end
function A.sync()
  if motion and (now<motion.time or now-motion.time>400) then A.reset(true) end
  if plan and (now>plan.expires or emergency()) then A.reset(false) end
  if not plan then restoreChase() end
end
function A.setContext(creature,config)
  if not creature or not config or not player then A.reset(true);return end
  local targetPos,origin=creature:getPosition(),player:getPosition()
  if not targetPos or not origin or targetPos.z~=origin.z then A.reset(true);return end
  local id=creature:getId()
  if motion and (motion.id~=id or motion.origin.z~=origin.z) then A.reset(true) end
  local anchor=TargetBot.Creature.getAnchorPosition and TargetBot.Creature.getAnchorPosition()
  motion={id=id,time=now,origin=point(origin),target=point(targetPos),
    keepDistance=config.keepDistance==true,chase=config.chase==true,
    range=config.keepDistance and math.max(1,tonumber(config.keepDistanceRange) or 1) or
      config.chase and 1 or distance(origin,targetPos),
    anchor=config.anchor and anchor and point(anchor) or nil,radius=tonumber(config.anchorRange) or 3}
end
local function inside(p,target)
  return distance(p,target)==motion.range and
    (not motion.anchor or distance(p,motion.anchor)<=motion.radius)
end
local function walkable(p,occupied,cache)
  local id=key(p)
  if cache[id]~=nil then return cache[id] end
  local tile=p.x>=0 and p.x<=65535 and p.y>=0 and p.y<=65535 and not occupied[id] and g_map.getTile(p)
  local color=tonumber(g_map.getMinimapColor and g_map.getMinimapColor(p)) or 0
  cache[id]=tile and tile:isWalkable(false)==true and
    (not tile.isPathable or tile:isPathable()==true) and
    (not tile.hasElevation or not tile:hasElevation(3)) and not (color>=210 and color<=213) and
    (not TargetBot.Movement or TargetBot.Movement.floorSafe(p,tile)) or false
  return cache[id]
end
local function routes(origin,target,actors)
  local occupied,cache,monsters={},{},{}
  for _,actor in ipairs(actors) do
    if actor.pos and actor.pos.z==origin.z then
      occupied[key(actor.pos)]=true
      if actor.monster and (actor.hp or 100)>0 then monsters[#monsters+1]=actor.pos end
    end
  end
  local function adjacent(p)
    local count=0
    for _,monster in ipairs(monsters) do if distance(p,monster)<=1 then count=count+1 end end
    return count
  end
  local currentPressure=adjacent(origin)
  local function safe(p)
    if adjacent(p)>currentPressure or adjacent(p)>=2 then return false end
    local exits=0
    for _,dir in ipairs(dirs) do
      local neighbor={x=p.x+dir[1],y=p.y+dir[2],z=p.z}
      if same(neighbor,origin) or walkable(neighbor,occupied,cache) then exits=exits+1 end
    end
    return exits>=2
  end
  local function scan(limit)
    local queue,head={{pos=point(origin),path={},depth=0,diagonals=0}},1
    local seen={[key(origin)]=true}
    while head<=#queue do
      local node=queue[head];head=head+1
      if node.depth<4 then
        for index=1,limit do
          local dir=dirs[index]
          local p={x=node.pos.x+dir[1],y=node.pos.y+dir[2],z=origin.z}
          local valid=not seen[key(p)] and inside(p,target) and walkable(p,occupied,cache)
          -- A conservative diagonal cannot cut a corner or step through a mob.
          if valid and dir[1]~=0 and dir[2]~=0 then
            valid=walkable({x=node.pos.x+dir[1],y=node.pos.y,z=origin.z},occupied,cache) and
              walkable({x=node.pos.x,y=node.pos.y+dir[2],z=origin.z},occupied,cache)
          end
          if valid and safe(p) then
            seen[key(p)]=true
            local path={}
            for _,step in ipairs(node.path) do path[#path+1]=step end
            path[#path+1]={from=point(node.pos),pos=point(p),direction=dir[3]}
            queue[#queue+1]={pos=p,path=path,depth=node.depth+1,diagonals=node.diagonals+(dir[3]>=4 and 1 or 0)}
          end
        end
      end
    end
    return queue
  end
  -- Retain a straight two-step route even when the same square has a one-step
  -- diagonal shortcut. Add diagonal-only destinations after the straight scan.
  local result,seen=scan(4),{}
  for _,node in ipairs(result) do seen[key(node.pos)]=true end
  for _,node in ipairs(scan(8)) do
    if not seen[key(node.pos)] then result[#result+1]=node end
  end
  return result -- At most 81 squares / four steps, including the current one.
end
local function preferable(candidate,previous)
  if not previous then return true end
  if motion.keepDistance and (candidate.diagonals==0)~=(previous.diagonals==0) then return candidate.diagonals==0 end
  if candidate.score~=previous.score then return candidate.score>previous.score end
  if candidate.amount~=previous.amount then return candidate.amount>previous.amount end
  if candidate.diagonals~=previous.diagonals then return candidate.diagonals<previous.diagonals end
  if candidate.depth~=previous.depth then return candidate.depth<previous.depth end
  if plan then
    local a=same(candidate.position,plan.position) and candidate.direction==plan.direction
    local b=same(previous.position,plan.position) and previous.direction==plan.direction
    if a~=b then return a end
  end
  local facing=player:getDirection()
  if (candidate.direction==facing)~=(previous.direction==facing) then return candidate.direction==facing end
  return false
end
function A.update(entries,origin,target,actors,patterns,context)
  A.sync()
  if not motion or not target or motion.id~=target.id or not context.rotate or emergency() or
    now<avoidUntil or not inside(origin,target.pos) or
    not TargetBot or not TargetBot.isOn or not TargetBot.isOn() then A.reset(false);return nil end
  if plan and now>plan.deadline then avoidUntil=now+400;A.reset(false);return nil end
  if now-lastSearch<200 and same(lastOrigin,origin) then return plan end
  lastSearch=now;lastOrigin=point(origin)
  local M=AttackRotation
  local timing,order,directional={}, {}, {}
  local ctx={}
  for name,value in pairs(context) do ctx[name]=value end
  ctx.collectCandidates=true
  local sightCache={}
  ctx.canHit=function(from,to)
    if same(from,origin) then return true end -- Actors already passed native canShoot here.
    local id=key(from)..'>'..key(to)
    if sightCache[id]~=nil then return sightCache[id] end
    local clear=true
    if type(g_map.isSightClear)=='function' then
      local ok,value=pcall(g_map.isSightClear,from,to,true)
      clear=ok and value==true
    else
      -- Conservative tile ray for older sandboxes without the native LOS API.
      local x,y=from.x,from.y
      local dx,dy=math.abs(to.x-x),math.abs(to.y-y)
      local sx,sy=x<to.x and 1 or -1,y<to.y and 1 or -1
      local error=dx-dy
      for _=1,15 do
        if x==to.x and y==to.y then break end
        local twice=2*error
        if twice>-dy then error=error-dy;x=x+sx end
        if twice<dx then error=error+dx;y=y+sy end
        if x~=to.x or y~=to.y then
          local tile=g_map.getTile({x=x,y=y,z=from.z})
          if not tile or tile.isBlocking and tile:isBlocking() then clear=false;break end
        end
      end
    end
    sightCache[id]=clear;return clear
  end
  ctx.timing=function(entry)
    local cached=timing[entry]
    if cached==nil then cached=context.timing(entry,M.find(entry)) or false;timing[entry]=cached end
    return cached or nil
  end
  for index,entry in ipairs(entries) do
    order[entry]=index
    if entry.enabled and M.isDirectional(entry,patterns) then directional[#directional+1]=entry end
  end
  if #directional==0 then A.reset(false);return nil end
  local soonest=math.huge
  for _,entry in ipairs(entries) do
    if entry.enabled then
      local t=ctx.timing(entry)
      if t then soonest=math.min(soonest,t.wait) end
    end
  end
  if soonest>2000 then A.reset(false);return nil end
  local shiftedActors={}
  for _,actor in ipairs(actors) do
    local copied={}
    for name,value in pairs(actor) do copied[name]=value end
    copied.shootable=true -- LOS is checked from the hypothetical origin below.
    shiftedActors[#shiftedActors+1]=copied
  end
  local options,best,current={},{},{}
  local reserved
  local stepTime=200
  if player.getStepDuration then
    local ok,value=pcall(player.getStepDuration,player,false,0)
    if ok and tonumber(value) then stepTime=math.max(100,math.min(600,tonumber(value))) end
  end
  for index,node in ipairs(routes(origin,target.pos,actors)) do
    local source=index==1 and entries or directional
    for _,candidate in ipairs(M.rank(source,node.pos,target,index==1 and actors or shiftedActors,patterns,ctx)) do
      candidate.order=order[candidate.entry];candidate.position=node.pos;candidate.path=node.path;candidate.depth=node.depth;candidate.diagonals=node.diagonals
      if index==1 and preferable(candidate,current[candidate.entry]) then current[candidate.entry]=candidate end
      if plan and candidate.entry==plan.entry and same(node.pos,plan.position) and
        candidate.timing.wait<=plan.deadline-now and preferable(candidate,reserved) then reserved=candidate end
      -- Anticipate during exhaust; permit at most 600ms of additional travel
      -- when a spell becomes ready late. Do not restart that allowance mid-walk.
      local enoughTime=node.depth==0 or node.depth*stepTime<=candidate.timing.wait+600
      if enoughTime and preferable(candidate,best[candidate.entry]) then best[candidate.entry]=candidate end
    end
  end
  if reserved then
    local here=current[reserved.entry]
    if same(origin,plan.position) or not here or reserved.score>here.score then
      -- Keep the destination across cooldown expiry and partial hits. Refresh
      -- its mask/path, but retain the original deadline so failures cannot stall.
      plan.direction=reserved.direction;plan.path=reserved.path;plan.amount=reserved.amount;plan.expires=now+350
      return plan
    end
  end
  local earliest=math.huge
  for _,entry in ipairs(entries) do
    local candidate=best[entry]
    local harmonyAllowed=candidate and (candidate.spec.harmony~='spender' or context.harmony~=nil and
      context.harmony>=(candidate.entry.minimumHarmony or 5))
    if candidate and harmonyAllowed then
      local t=candidate.timing
      -- Compare SPELL readiness at the next attack slot, not arrival time.
      -- Otherwise an instant rune always beats a wave requiring any movement.
      candidate.timing={wait=t.wait,cooldown=t.cooldown,lock=t.lock,groups=t.groups}
      earliest=math.min(earliest,candidate.timing.wait)
      options[#options+1]=candidate
    end
  end
  if earliest>2000 then A.reset(false);return nil end
  for _,candidate in ipairs(options) do
    candidate.timing.wait=math.max(0,candidate.timing.wait-earliest)
    candidate.timing.ready=candidate.timing.wait<=50
  end
  table.sort(options,function(a,b)
    if context.priorityOrder and a.order~=b.order then return a.order<b.order end
    if a.score~=b.score then return a.score>b.score end
    if a.amount~=b.amount then return a.amount>b.amount end
    return a.order<b.order
  end)
  local selected
  if context.priorityOrder then
    for _,candidate in ipairs(options) do if candidate.timing.ready then selected=candidate;break end end
  else selected=M.plan(options,context)[1] end
  if not selected or not M.isDirectional(selected.entry,patterns) then A.reset(false);return nil end
  local deadline=plan and plan.entry==selected.entry and plan.deadline or
    now+math.max(earliest,selected.depth*stepTime)+700
  plan={entry=selected.entry,position=point(selected.position),direction=selected.direction,path=selected.path,
    amount=selected.amount,deadline=deadline,expires=now+350,target=motion.id}
  return plan
end
function A.getPlan() A.sync();return plan end
function A.face(direction)
  if emergency() or direction==nil or now-lastTurn<100 then return false end
  if type(turn)=='function' then turn(direction)
  elseif type(g_game.turn)=='function' then g_game.turn(direction)
  else return false end
  lastTurn=now;return true
end
function A.consume(entry)
  if plan and plan.entry==entry then A.reset(false);lastSearch=0 end
end
function A.move(creature,config)
  A.sync()
  if not plan or not motion or creature:getId()~=plan.target or emergency() then return false end
  local origin,target=player:getPosition(),creature:getPosition()
  if not origin or not target or origin.z~=plan.position.z or not inside(origin,target) then A.reset(false);return false end
  holdChase()
  if not same(origin,plan.position) then
    if player:isWalking() then
      if pendingStep and same(pendingStep.from,origin) and now-pendingStep.time>900 then
        if g_game.stop then pcall(g_game.stop) end
        avoidUntil=now+500;A.reset(false);return false
      end
      return true
    end
    local step
    for _,item in ipairs(plan.path) do if same(item.from,origin) then step=item;break end end
    if not step or not inside(step.pos,target) or not walkable(step.pos,{}, {}) then A.reset(false);return false end
    if step.pos.x~=origin.x and step.pos.y~=origin.y and
      (not walkable({x=step.pos.x,y=origin.y,z=origin.z},{},{}) or
       not walkable({x=origin.x,y=step.pos.y,z=origin.z},{},{})) then A.reset(false);return false end
    local safety=TargetBot.Antitrap
    local guarded=step.direction
    if safety and safety.guardStep then guarded=safety.guardStep(origin,step.direction) end
    if guarded~=step.direction then
      A.reset(false)
      if guarded~=nil and safety and safety.ownsMovement() then safety.send({step=guarded},now) end
      return true
    end
    if pendingStep and same(pendingStep.from,origin) then
      if now-pendingStep.time<500 then return true end
      avoidUntil=now+500;A.reset(false);return false
    end
    if CaveBot and CaveBot.resetWalking then CaveBot.resetWalking() end
    if safeBotWalk(step.direction)~=false then pendingStep={from=point(origin),time=now} end
    return true
  end
  pendingStep=nil
  if player:isWalking() then return true end
  if player:getDirection()~=plan.direction then A.face(plan.direction) end
  return true -- Protect this facing from Target's faceMonster / native Chase.
end

AttackBot.setSpellMovementContext=A.setContext
AttackBot.clearSpellMovement=function() A.reset(true) end
AttackBot.prepareSpellMovement=A.move
