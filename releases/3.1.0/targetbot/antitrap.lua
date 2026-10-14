-- Keep Distance safety: inspect the whole nearby group and move before exits close.
-- There are no pulls, route profiles, orbit centres or combat phases.
TargetBot.Antitrap = {}
local A = TargetBot.Antitrap
local dirs = {{0,-1,0},{1,0,1},{0,1,2},{-1,0,3},{1,-1,4},{1,1,5},{-1,1,6},{-1,-1,7}}
local tracks, visits, chaseBefore = {}, {}, nil
local context, managed, ownedUntil = nil, false, 0
local pending = nil
local stuckPos, stuckSince, lastBugMap = nil, nil, 0
local returnAfter = 0
local function key(p) return p.x..':'..p.y end
local function distance(a,b) return math.max(math.abs(a.x-b.x),math.abs(a.y-b.y)) end
local function point(p) return {x=p.x,y=p.y,z=p.z} end
local function same(a,b) return a and b and a.x==b.x and a.y==b.y and a.z==b.z end
local function better(a,b)
  if not b then return true end
  for i=1,#a do if a[i]~=b[i] then return a[i]>b[i] end end
  return false
end
local function safeChase(mode)
  if g_game.setChaseMode then pcall(function() g_game.setChaseMode(mode) end) end
end
function A.reset()
  if chaseBefore~=nil and g_game.getChaseMode then
    local ok,mode=pcall(function() return g_game.getChaseMode() end)
    if ok and mode==0 then safeChase(chaseBefore) end
  end
  tracks,visits,chaseBefore={}, {}, nil
  context,managed,ownedUntil=nil,false,0
  pending=nil
  stuckPos,stuckSince,lastBugMap=nil,nil,0
  returnAfter=0
end
function A.ownsMovement() return context~=nil and managed end
function A.protecting()
  if not context then return false end
  if managed then return true end
  for _,threat in ipairs(context.threats) do
    if distance(context.pos,threat.pos)<=3 then return true end
  end
  return false
end
local function holdChase()
  if not g_game.getChaseMode then return end
  local ok,mode=pcall(function() return g_game.getChaseMode() end)
  if not ok then return end
  if chaseBefore==nil then chaseBefore=mode end
  if mode~=0 then safeChase(0) end -- Native Chase cannot walk into a Keep Distance target.
end
local function makeContext(specs,pos,config,time,anchor)
  local ctx={pos=point(pos),config=config,time=time,occupied={},threats={},cache={},metrics={},firstSteps={}}
  if config.anchor then
    ctx.combatAnchor=anchor and anchor.z==pos.z and point(anchor) or nil
    ctx.anchor=ctx.combatAnchor -- Gathering has no combat centre yet.
  end
  ctx.radius=math.max(1,tonumber(config.anchorRange) or 3)
  ctx.range=math.max(1,tonumber(config.keepDistanceRange) or 1)
  local currentTracks={}
  for _,spec in ipairs(specs) do
    local p=spec:getPosition()
    local hp=spec:getHealthPercent()
    if spec~=player and p and p.z==pos.z and (not hp or hp>0) then
      ctx.occupied[key(p)]=true
      if spec:isMonster() then
        local id=spec:getId()
        local previous=tracks[id]
        local future=point(p)
        local vx,vy,movedAt=0,0,time
        if previous and previous.pos.z==p.z and time>previous.time and time-previous.time<=700 then
          local elapsed=time-previous.time
          if not same(previous.pos,p) then
            vx=math.max(-1,math.min(1,(p.x-previous.pos.x)*300/elapsed))
            vy=math.max(-1,math.min(1,(p.y-previous.pos.y)*300/elapsed))
          elseif previous.movedAt and time-previous.movedAt<=350 then
            vx,vy,movedAt=previous.vx,previous.vy,previous.movedAt
          end
        end
        future.x,future.y=future.x+vx,future.y+vy
        ctx.threats[#ctx.threats+1]={pos=point(p),future=future}
        currentTracks[id]={pos=point(p),time=time,vx=vx,vy=vy,movedAt=movedAt}
      end
    end
  end
  tracks=currentTracks -- Do not retain dead or off-screen creatures.
  -- Keep one-step diagonal reachability for emergencies. Selection below prefers
  -- straight steps when they are equally safe. ignoreStairs=false BLOCKS stairs.
  if type(findAllPaths)=='function' and type(translateAllPathsToPath)=='function' then
    ctx.paths=findAllPaths(pos,3,{ignoreCreatures=false,ignoreNonPathable=true,ignoreCost=true,ignoreStairs=false,allowOnlyVisibleTiles=true})
  end
  for id,seen in pairs(visits) do if time-seen>2000 then visits[id]=nil end end
  visits[key(pos)]=time
  return ctx
end
local function free(ctx,p)
  if p.x==ctx.pos.x and p.y==ctx.pos.y then return true end
  local id=key(p)
  if ctx.cache[id]==nil then
    local tile=g_map.getTile(p)
    local reachable=not ctx.paths or ctx.paths[p.x..','..p.y..','..p.z]~=nil
    ctx.cache[id]=not ctx.occupied[id] and reachable and tile~=nil and tile:isWalkable(false)==true
      and (not TargetBot.Movement or TargetBot.Movement.floorSafe(p,tile))
  end
  return ctx.cache[id]
end
local function withinAnchor(ctx,from,to)
  if not ctx.anchor then return true end
  local before,after=distance(from,ctx.anchor),distance(to,ctx.anchor)
  return to.z==ctx.anchor.z and (after<=ctx.radius or before>ctx.radius and after<=before)
end
local function canStep(ctx,from,to)
  if not withinAnchor(ctx,from,to) then return false end
  if not free(ctx,to) then return false end
  if from.x==ctx.pos.x and from.y==ctx.pos.y then
    local id=key(to)
    if ctx.firstSteps[id]==nil then
      local path
      if ctx.paths then path=translateAllPathsToPath(ctx.paths,to)
      else path=findPath(ctx.pos,to,2,{ignoreCreatures=false,ignoreNonPathable=true,ignoreCost=true,ignoreStairs=false,allowOnlyVisibleTiles=true,precision=0}) end
      ctx.firstSteps[id]=path~=nil and #path==1
    end
    return ctx.firstSteps[id]
  end
  return true
end
local function nearby(ctx,p)
  local adjacent,future,near=0,0,0
  for _,threat in ipairs(ctx.threats) do
    local d=distance(p,threat.pos)
    if d<=1 then adjacent=adjacent+1 end
    if d<=2 then near=near+1 end
    if distance(p,threat.future)<=1.1 then future=future+1 end
  end
  return adjacent,future,near
end
local function measure(ctx,p)
  local id=key(p)
  if ctx.metrics[id] then return ctx.metrics[id] end
  local adjacent,future,near=nearby(ctx,p)
  local value={adjacent=adjacent,future=future,near=near,exits=0,safeExits=0}
  for _,dir in ipairs(dirs) do
    local nextPos={x=p.x+dir[1],y=p.y+dir[2],z=p.z}
    -- Going back to the square we are leaving is not an onward escape route.
    if not (not same(p,ctx.pos) and same(nextPos,ctx.pos)) and canStep(ctx,p,nextPos) then
      value.exits=value.exits+1
      local nextAdjacent,nextFuture=nearby(ctx,nextPos)
      if nextAdjacent==0 and nextFuture==0 then value.safeExits=value.safeExits+1 end
    end
  end
  ctx.metrics[id]=value
  return value
end
local function pressure(m)
  return m.adjacent>=2 or m.future>=2 or m.adjacent>0 and m.exits<=2
    or m.near>=3 and m.safeExits<=2 or m.near>=2 and m.exits<=3
    or m.adjacent>0 and m.safeExits==0
end
local function choose(ctx,target,returning)
  local queue,head,seen={{pos=ctx.pos,depth=0}},1,{}
  local straight,diagonal
  while head<=#queue do
    local node=queue[head];head=head+1
    if node.depth<2 then -- At most 25 tiles / 65 two-step route records.
      for _,dir in ipairs(dirs) do
        local p={x=node.pos.x+dir[1],y=node.pos.y+dir[2],z=ctx.pos.z}
        local validRoute=true
        if ctx.paths and node.depth>0 and dir[3]>=4 then
          local path=translateAllPathsToPath(ctx.paths,p)
          validRoute=path and #path==2 and path[1]==node.dir and path[2]==dir[3]
        end
        -- A native diagonal shortcut to the same endpoint must not discard a
        -- safe two-cardinal route. Keep distinct first steps; both affect safety.
        local routeKey=key(p)..':'..(node.dir or dir[3])
        if validRoute and not same(p,ctx.pos) and not seen[routeKey] and canStep(ctx,node.pos,p) then
          seen[routeKey]=true
          local first=node.first or p
          local item={pos=p,depth=node.depth+1,first=first,dir=node.dir or dir[3]}
          queue[#queue+1]=item
          local immediate,finish=measure(ctx,first),measure(ctx,p)
          -- Fewer adjacent/predicted attackers and a viable onward exit beat
          -- direction preference. Extra open tiles alone do not justify a diagonal.
          local safety={-immediate.adjacent,-immediate.future,pressure(immediate) and 0 or 1,immediate.safeExits>0 and 1 or 0,
            -finish.adjacent,-finish.future,pressure(finish) and 0 or 1,finish.safeExits>0 and 1 or 0}
          local score={}
          local eligible=true
          if returning then
            local current=measure(ctx,ctx.pos)
            eligible=distance(p,ctx.anchor)<distance(ctx.pos,ctx.anchor)
              and not pressure(immediate) and not pressure(finish)
              and immediate.adjacent<=current.adjacent and immediate.future<=current.future
              and finish.adjacent<=current.adjacent and finish.future<=current.future
              and immediate.safeExits>0 and finish.safeExits>0
          end
          for _,value in ipairs(safety) do score[#score+1]=value end
          score[#score+1]=item.dir<4 and 1 or 0
          if returning then score[#score+1]=-distance(p,ctx.anchor) end
          score[#score+1]=immediate.safeExits;score[#score+1]=immediate.exits
          score[#score+1]=finish.safeExits;score[#score+1]=finish.exits
          local d=target and distance(p,target) or ctx.range
          local penalty=d<ctx.range and ctx.range-d or d>ctx.range+1 and d-ctx.range-1 or 0
          score[#score+1]=-penalty
          score[#score+1]=visits[key(first)] and -(2000-(ctx.time-visits[key(first)]))/1000 or 0
          score[#score+1]=-item.depth
          if eligible then
            local previous=item.dir<4 and straight or diagonal
            if better(score,previous and previous.score) then
              local candidate={dir=item.dir,pos=first,score=score,metrics=immediate,
                immediateSafety={-immediate.adjacent,-immediate.future,pressure(immediate) and 0 or 1,immediate.exits>0 and 1 or 0}}
              if item.dir<4 then straight=candidate else diagonal=candidate end
            end
          end
        end
      end
    end
  end
  -- Hypothetical second-step improvements or more open tiles do not justify a
  -- diagonal. It must reduce immediate danger or be the only usable first step.
  if diagonal and (not straight or better(diagonal.immediateSafety,straight.immediateSafety)) then return diagonal end
  return straight
end
local function findExit(ctx,target)
  return choose(ctx,target)
end
local function engage(time)
  local started=not managed
  managed,ownedUntil=true,time+200
  if started then
    if CaveBot and CaveBot.resetWalking then CaveBot.resetWalking() end
    if player and player:isWalking() and g_game.stop then pcall(function() g_game.stop() end) end
  end
end
local function bugMapExit(ctx)
  local rawCache,best={},nil
  local function rawFree(p)
    local id=key(p)
    if rawCache[id]==nil then
      local tile=g_map.getTile(p)
      local color=g_map.getMinimapColor and g_map.getMinimapColor(p) or 0
      rawCache[id]=withinAnchor(ctx,ctx.pos,p) and not ctx.occupied[id] and tile~=nil and tile:isWalkable(false)==true
        and tile:getGround()~=nil and not (color>=210 and color<=213)
        and (not TargetBot.Movement or TargetBot.Movement.floorSafe(p,tile))
    end
    return rawCache[id]
  end
  -- A boxed player has no native walk path; inspect only the two/three-square ring.
  for dx=-3,3 do
    for dy=-3,3 do
      local p={x=ctx.pos.x+dx,y=ctx.pos.y+dy,z=ctx.pos.z}
      local d=distance(p,ctx.pos)
      if d>=2 and rawFree(p) then
        local adjacent,future,near=nearby(ctx,p)
        local exits=0
        for _,dir in ipairs(dirs) do
          if rawFree({x=p.x+dir[1],y=p.y+dir[2],z=p.z}) then exits=exits+1 end
        end
        local score={-adjacent,-future,exits,-near,
          visits[key(p)] and -(2000-(ctx.time-visits[key(p)]))/1000 or 0,-d}
        if exits>=2 and better(score,best and best.score) then best={pos=p,score=score} end
      end
    end
  end
  return best and best.pos
end
function A.update(specs,pos,config,time,targetPos,anchor)
  if not config or config.keepDistance~=true or not pos then A.reset();return nil end
  if context and (context.pos.z~=pos.z or time<context.time) then A.reset() end
  holdChase()
  context=makeContext(specs,pos,config,time,anchor)
  context.target=targetPos and point(targetPos) or nil
  if #context.threats==0 then A.reset();return nil end
  local current=measure(context,pos)
  if pressure(current) then
    returnAfter=time+400 -- Do not immediately walk back into a recent escape.
    local best=findExit(context,targetPos)
    engage(time)
    if best then stuckPos,stuckSince=nil,nil
    elseif not same(stuckPos,pos) then stuckPos,stuckSince=point(pos),time end
    if not best and config.antitrapBugMap==true and current.exits==0 and current.adjacent>=2
      and BugMapMouse and type(BugMapMouse.tryUsePosition)=='function'
      and time-stuckSince>=math.max(300,tonumber(config.antitrapBugMapDelay) or 600)
      and time-lastBugMap>=800 then
      local destination=bugMapExit(context)
      if destination then return {bugMap=destination,metrics=current,status='Anti-trap: intentando BugMap'} end
    end
    return {step=best and best.dir,position=best and best.pos,metrics=current,status=best and 'Anti-trap' or 'Anti-trap: sin salida'}
  end
  stuckPos,stuckSince=nil,nil
  if context.combatAnchor and distance(pos,context.combatAnchor)>context.radius then
    engage(time)
    local best=time>=returnAfter and choose(context,targetPos,true) or nil
    return {step=best and best.dir,position=best and best.pos,metrics=current,
      status=best and 'Anchoring: volviendo al area' or 'Anchoring: esperando entrada segura'}
  end
  if managed and time<ownedUntil and player:isWalking() then return {status='Anti-trap',metrics=current} end
  managed=false
  pending=nil
  return nil
end
-- This is called by a separate timer, so spell/route pauses cannot suspend safety.
function A.refresh(pos,time)
  if not context then return nil end
  if not pos or pos.z~=context.pos.z then A.reset();return nil end
  if same(pos,context.pos) and time>=context.time and time-context.time<100 then return nil end
  return A.update(g_map.getSpectatorsInRange(pos,false,6,6),pos,context.config,time,context.target,context.combatAnchor)
end
function A.poll(time) return A.refresh(player and player:getPosition(),time) end
function A.send(plan,time)
  if not plan or not context then return false end
  local pos=player:getPosition()
  if not same(pos,context.pos) then return false end
  if plan.bugMap then
    if not withinAnchor(context,pos,plan.bugMap) then return false end
    if TargetBot.Movement and not TargetBot.Movement.floorSafe(plan.bugMap) then return false end
    if time-lastBugMap<800 or not BugMapMouse or type(BugMapMouse.tryUsePosition)~='function' then return false end
    lastBugMap=time
    if player:isWalking() and g_game.stop then pcall(function() g_game.stop() end) end
    local ok,result=pcall(function() return BugMapMouse.tryUsePosition(plan.bugMap) end)
    visits[key(plan.bugMap)]=time
    pending=nil
    return ok and result==true
  end
  if plan.step==nil then return false end
  local offset=dirs[plan.step+1]
  if not offset or not withinAnchor(context,pos,{x=pos.x+offset[1],y=pos.y+offset[2],z=pos.z}) then return false end
  if TargetBot.Movement and not TargetBot.Movement.canStep(pos,plan.step) then return false end
  local duration=150
  if player.getStepDuration then
    local ok,value=pcall(function() return player:getStepDuration(false,plan.step) end)
    if ok and tonumber(value) then duration=math.max(100,tonumber(value)) end
  end
  if pending and same(pos,pending.from) then
    local timeout=player:isWalking() and math.max(750,duration*2+250) or 100
    if time-pending.time<timeout then return false end
    -- A refused/server-stalled step must not leave isWalking blocking every retry.
    if player:isWalking() and g_game.stop then pcall(function() g_game.stop() end) end
    pending=nil
  else
    pending=nil
  end
  if player:isWalking() then return false end
  local result=safeBotWalk(plan.step)
  if result~=false then pending={from=point(pos),time=time};ownedUntil=math.max(ownedUntil,time+duration+150) end
  return result~=false
end
function A.guardStep(pos,direction)
  if not context then return direction end
  -- Applies even without encirclement: keeping distance must never use a stair.
  if TargetBot.Movement and not TargetBot.Movement.canStep(pos,direction) then return nil end
  A.refresh(pos,now or context.time)
  if not context then return direction end
  local dir
  for _,item in ipairs(dirs) do if item[3]==direction then dir=item;break end end
  if not dir then return nil end
  local destination={x=pos.x+dir[1],y=pos.y+dir[2],z=pos.z}
  if not withinAnchor(context,pos,destination) then return nil end
  if not A.protecting() then return direction end
  local current=measure(context,pos)
  if canStep(context,pos,destination) then
    local nextMetrics=measure(context,destination)
    if nextMetrics.exits>0 and not (pressure(nextMetrics) and not pressure(current))
      and not (nextMetrics.adjacent>=2 and nextMetrics.adjacent>current.adjacent)
      and not (nextMetrics.future>=2 and nextMetrics.future>current.future) then return direction end
  end
  local best=findExit(context,nil)
  if not best or best.metrics.adjacent>current.adjacent or best.metrics.exits==0 then return nil end
  returnAfter=context.time+400
  engage(context.time)
  return best.dir
end
