-- Safety for Keep Distance and close grouping: move before nearby creatures close the exits.
-- There are no pulls, route profiles, orbit centres or combat phases.
TargetBot.Antitrap = {}
local A = TargetBot.Antitrap
local dirs = {{0,-1,0},{1,0,1},{0,1,2},{-1,0,3},{1,-1,4},{1,1,5},{-1,1,6},{-1,-1,7}}
local tracks, visits, chaseBefore = {}, {}, nil
local context, managed, ownedUntil = nil, false, 0
local pending = nil
local stuckPos, stuckSince, lastBugMap = nil, nil, 0
local bugMapAt = nil -- boxed in with "BugMap sin salida": when its BugMap is due
local blindAt = 0 -- change 229: last BugMap tried without a known path (fallback)
-- Change 230: boxed-in / nearly boxed-in episodes, kept in storage.antitrapLog (last 20).
local TRAP_LOG = 20
local episode = nil
-- Change 232: monsters that fight from a distance, learned by name (storage.antitrapRanged).
local rangedBook, rangedWatch = nil, {}
local DEAD_END = 10 -- change 231: fewer free tiles than this within 5 steps of an escape = a dead end
local returnAfter = 0
-- "BugMap sin salida": Espera from 60 ms (80 by default); a failed BugMap is retried after 400 ms.
local BUGMAP_MIN_DELAY, BUGMAP_DEFAULT_DELAY, BUGMAP_RETRY = 60, 80, 400
local function bugMapDelay(config)
  return math.max(BUGMAP_MIN_DELAY, tonumber(config and config.antitrapBugMapDelay) or BUGMAP_DEFAULT_DELAY)
end
-- Anclaje: an escape from crowding/pressure may leave the radius by this many
-- SQM to reposition; the centre does not move and the character comes back as
-- soon as a step back is not crowded. All other movement keeps the radius.
local ESCAPE_MARGIN = 2
local EMERGENCY_MARGIN = 4 -- only when boxed in by more monsters than "Agrupar cercanos" allows
local RETURN_DELAY = 100
local function manualMovement()
  return TargetBot.Movement and TargetBot.Movement.isManual and TargetBot.Movement.isManual()
end
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
local finishEpisode -- defined below (change 230)
function A.reset()
  if episode and finishEpisode then finishEpisode(episode.last, 'se acabo el combate') end
  if chaseBefore~=nil and g_game.getChaseMode then
    local ok,mode=pcall(function() return g_game.getChaseMode() end)
    if ok and mode==0 then safeChase(chaseBefore) end
  end
  tracks,visits,chaseBefore={}, {}, nil
  context,managed,ownedUntil=nil,false,0
  pending=nil
  stuckPos,stuckSince,lastBugMap=nil,nil,0
  bugMapAt=nil
  returnAfter=0
end
function A.ownsMovement() return context~=nil and managed end
-- true when a boxed-in character's BugMap is due (target.lua then checks every 20 ms).
function A.bugMapDue(time) return bugMapAt~=nil and (tonumber(time) or 0)>=bugMapAt end
function A.protecting()
  if not context then return false end
  if managed then return true end
  if context.surroundOnly then return false end
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
  local ctx={pos=point(pos),config=config,time=time,occupied={},threats={},cache={},metrics={},firstSteps={},room={},ground={}}
  if config.anchor then
    ctx.combatAnchor=anchor and anchor.z==pos.z and point(anchor) or nil
    ctx.anchor=ctx.combatAnchor -- Gathering has no combat centre yet.
  end
  ctx.radius=math.max(1,tonumber(config.anchorRange) or 3)
  ctx.escapeRadius=ctx.radius+ESCAPE_MARGIN
  ctx.range=math.max(1,tonumber(config.keepDistanceRange) or 1)
  -- "Agrupar cercanos": distance (SQM) at which monsters are counted. 1 = only
  -- adjacent (diagonals included), the previous behaviour and the default.
  ctx.crowdRange=math.max(1,math.min(5,math.floor(tonumber(config.closeLureRange) or 1)))
  -- Anclado with Lure dinamico, still gathering along the route: the pack trailing behind
  -- is the lure itself. Counted at 2+ SQM it turned every route step into an escape and
  -- CaveBot walked straight back (back and forth, into corners). Only adjacent ones count.
  if config.anchor==true and config.dynamicLure==true and not ctx.combatAnchor then ctx.crowdRange=1 end
  -- "Tirar hacia la ruta": the next CaveBot waypoint ahead breaks ties between
  -- equally safe steps (escapes and returns lean towards where the route goes).
  local movement=TargetBot.Movement
  if config.routePull==true and movement and movement.routeAhead then ctx.ahead=movement.routeAhead(pos) end
  local currentTracks={}
  for _,spec in ipairs(specs) do
    local p=spec:getPosition()
    local hp=spec:getHealthPercent()
    if spec~=player and p and p.z==pos.z and (not hp or hp>0) then
      ctx.occupied[key(p)]=true
      local monster=spec:isMonster()
      local kind=monster and spec.getType and tonumber(spec:getType())
      if monster and (config.keepDistance==true or kind~=3 and kind~=4) then
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
        local name=spec.getName and spec:getName() or nil
        ctx.threats[#ctx.threats+1]={pos=point(p),future=future,creature=spec,hp=hp or 100,id=id,name=name,
          ranged=A.isRangedName(name)}
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
    local movement=TargetBot.Movement
    local physical=tile and tile:isWalkable(false)==true
    if movement and movement.walkableTile then physical=movement.walkableTile(tile,false) end
    if physical and not reachable and movement and movement.fieldPath then
      reachable=movement.fieldPath(ctx.pos,p,3,{ignoreCreatures=false})~=nil
    end
    ctx.cache[id]=not ctx.occupied[id] and reachable and physical
      and (not TargetBot.Movement or TargetBot.Movement.floorSafe(p,tile))
  end
  return ctx.cache[id]
end
-- radius: ctx.escapeRadius (default) for the antitrap's own escape/return
-- steps; ctx.radius for ordinary TargetBot movement it guards.
local function withinAnchor(ctx,from,to,radius)
  if not ctx.anchor then return true end
  radius=radius or ctx.escapeRadius or ctx.radius
  local before,after=distance(from,ctx.anchor),distance(to,ctx.anchor)
  return to.z==ctx.anchor.z and (after<=radius or before>radius and after<=before)
end
local function canStep(ctx,from,to)
  if not withinAnchor(ctx,from,to) then return false end
  local movement=TargetBot.Movement
  if ctx.surroundOnly and movement and movement.withinBounds and not movement.withinBounds(from,to) then return false end
  if not free(ctx,to) then return false end
  if from.x==ctx.pos.x and from.y==ctx.pos.y then
    local id=key(to)
    if ctx.firstSteps[id]==nil then
      local path
      if ctx.paths then path=translateAllPathsToPath(ctx.paths,to)
      else path=findPath(ctx.pos,to,2,{ignoreCreatures=false,ignoreNonPathable=true,ignoreCost=true,ignoreStairs=false,allowOnlyVisibleTiles=true,precision=0}) end
      if not path and TargetBot.Movement and TargetBot.Movement.fieldPath then path=TargetBot.Movement.fieldPath(ctx.pos,to,2,{}) end
      ctx.firstSteps[id]=path~=nil and #path==1
    end
    return ctx.firstSteps[id]
  end
  return true
end
-- Open ground around p: tiles reachable from it in two steps, creatures ignored (a thin
-- wall hides the other side). 25 in the open, 20 one tile off a wall, 15 against it,
-- 9 in a corner.
local function room(ctx,p)
  local id=key(p)
  if ctx.room[id] then return ctx.room[id] end
  local movement=TargetBot.Movement
  local function open(q)
    local qid=key(q)
    if ctx.ground[qid]==nil then
      local tile=g_map.getTile(q)
      if movement and movement.walkableTile then ctx.ground[qid]=movement.walkableTile(tile,true)==true
      else ctx.ground[qid]=tile~=nil and tile:isWalkable(true)==true end
    end
    return ctx.ground[qid]
  end
  local queue,head,seen={{pos=p,depth=0}},1,{[id]=true}
  while head<=#queue do
    local node=queue[head];head=head+1
    if node.depth<2 then
      for _,dir in ipairs(dirs) do
        local q={x=node.pos.x+dir[1],y=node.pos.y+dir[2],z=p.z}
        if not seen[key(q)] and open(q) then seen[key(q)]=true;queue[#queue+1]={pos=q,depth=node.depth+1} end
      end
    end
  end
  ctx.room[id]=#queue
  return #queue
end
local function nearby(ctx,p)
  local adjacent,future,near,crowd,crowdFuture=0,0,0,0,0
  local range=ctx.crowdRange or 1
  for _,threat in ipairs(ctx.threats) do
    local d=distance(p,threat.pos)
    if d<=1 then adjacent=adjacent+1 end
    -- Change 232: a monster learned to fight from a distance only counts when adjacent (it
    -- does not come to close the exits; counting it made the character walk for nothing).
    if not threat.ranged or d<=1 then
      if d<=2 then near=near+1 end
      if d<=range then crowd=crowd+1 end
      local f=distance(p,threat.future)
      if f<=1.1 then future=future+1 end
      if f<=range+0.1 then crowdFuture=crowdFuture+1 end
    end
  end
  return adjacent,future,near,crowd,crowdFuture
end
-- Change 231: free tiles reachable from p within 5 steps (monsters' tiles and the character's
-- own tile excluded), up to 40. A corridor that ends at a wall gives few.
local function space(ctx,p)
  ctx.space=ctx.space or {}
  local id=key(p)
  if ctx.space[id] then return ctx.space[id] end
  local movement=TargetBot.Movement
  ctx.pass=ctx.pass or {}
  local function passable(q)
    local qid=key(q)
    if ctx.pass[qid]==nil then
      local tile=not ctx.occupied[qid] and not same(q,ctx.pos) and g_map.getTile(q)
      local ok=tile and tile:isWalkable(false)==true or false
      if tile and movement and movement.walkableTile then ok=movement.walkableTile(tile,false)==true end
      if ok and movement and not movement.floorSafe(q,tile) then ok=false end
      ctx.pass[qid]=ok
    end
    return ctx.pass[qid]
  end
  local queue,head,seen={{pos=p,depth=0}},1,{[id]=true}
  while head<=#queue and #queue<40 do
    local node=queue[head];head=head+1
    if node.depth<5 then
      for _,dir in ipairs(dirs) do
        local q={x=node.pos.x+dir[1],y=node.pos.y+dir[2],z=p.z}
        if not seen[key(q)] and passable(q) then seen[key(q)]=true;queue[#queue+1]={pos=q,depth=node.depth+1} end
      end
    end
  end
  ctx.space[id]=#queue
  return #queue
end
local function measure(ctx,p)
  local id=key(p)
  if ctx.metrics[id] then return ctx.metrics[id] end
  local adjacent,future,near,crowd,crowdFuture=nearby(ctx,p)
  -- crowd/crowdFuture: monsters within the "Agrupar cercanos" distance (equal
  -- to adjacent/future at 1 SQM).
  local value={adjacent=adjacent,future=future,near=near,crowd=crowd,crowdFuture=crowdFuture,exits=0,safeExits=0}
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
-- "BugMap sin salida" ON means: never get boxed in. The trap is closing when the
-- free exits left, minus the monsters about to step next to the character,
-- reach 1 (2+ already adjacent) or 0 (1 adjacent). Independent of Agrupar's limit.
local function freeAfter(m) return m.exits-math.max(0,m.future-m.adjacent) end
local function trapRisk(ctx,m)
  if ctx.config.antitrapBugMap~=true then return false end
  -- Monsters still one step away count too: a pack arriving together closes
  -- every exit in a single step.
  if math.max(m.adjacent,m.future)>=2 and freeAfter(m)<=1 then return true end
  -- A pocket (corner, wall nook): only a few exits and a monster next to each of
  -- them, so the pack can fill them all next step. Leave it (or do not enter it)
  -- while the way out is open, even before one of them is adjacent. A corridor with
  -- the pack on one side keeps its far exit free, so it is not a pocket.
  return m.exits<=3 and m.safeExits==0 and m.near>=1
end
-- Every exit of this tile has a monster next to it: the pack can close it in one move.
local function closable(m) return m.safeExits==0 end
-- "Agrupar cercanos": more monsters than the limit within its distance (or
-- about to be), or the limit already near and the exits closing.
local function crowded(ctx,m)
  if trapRisk(ctx,m) then return true end
  if ctx.config.closeLure~=true then return false end
  local limit=math.max(1,tonumber(ctx.config.closeLureAmount) or 3)
  return m.crowd>limit or m.crowdFuture>limit or m.near>=limit and m.exits<=2
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
          if not path and TargetBot.Movement and TargetBot.Movement.fieldPath then path=TargetBot.Movement.fieldPath(ctx.pos,p,2,{}) end
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
          -- "Agrupar cercanos" beyond 1 SQM: fewer monsters within that distance
          -- comes first (at 1 SQM it equals the adjacent count, so nothing changes).
          local wide=ctx.crowdRange>1 and ctx.config.closeLure==true
          if wide then
            safety={-immediate.crowd,-immediate.crowdFuture,-immediate.adjacent,-immediate.future,
              pressure(immediate) and 0 or 1,immediate.safeExits>0 and 1 or 0,
              -finish.crowd,-finish.adjacent,-finish.future,pressure(finish) and 0 or 1,finish.safeExits>0 and 1 or 0}
          end
          local score={}
          local eligible=true
          -- "BugMap sin salida" ON: a tile the monsters nearby can close in one move
          -- comes last (corners and wall nooks hold fewer monsters, so the crowd count
          -- alone used to prefer them), then open ground first (fleeing along a wall
          -- ended in a corner). While a trap is closing, getting out of it comes before
          -- anything (a step next to a monster is fine if it keeps exits open).
          -- Change 231: then not into a dead end (a corridor that ends at a wall).
          local trapLead,openLead,roomLead,spaceLead
          if ctx.config.antitrapBugMap==true and not returning then
            openLead=(trapRisk(ctx,immediate) or closable(immediate)) and 0 or 1
            spaceLead=space(ctx,first)>=DEAD_END and 1 or 0
            roomLead=math.min(20,room(ctx,first))
          end
          if ctx.trapMode and not returning then
            trapLead={trapRisk(ctx,immediate) and 0 or 1,freeAfter(immediate)}
            score[#score+1]=trapLead[1];score[#score+1]=openLead or 0;score[#score+1]=spaceLead or 0
            score[#score+1]=roomLead or 0;score[#score+1]=trapLead[2]
          elseif openLead then
            score[#score+1]=openLead;score[#score+1]=spaceLead;score[#score+1]=roomLead
          end
          -- Anclaje lead: returning, closer first steps win; escaping, a step
          -- inside the radius that already ends the crowding/pressure beats any
          -- step outside (otherwise safety decides and it may leave by the margin).
          local lead
          if returning then
            lead=-distance(first,ctx.anchor)
          elseif ctx.anchor then
            lead=distance(first,ctx.anchor)<=ctx.radius and not crowded(ctx,immediate)
              and (ctx.surroundOnly or not pressure(immediate)) and 1 or 0
          end
          if lead then score[#score+1]=lead end
          if returning then
            -- Anclaje: come back quickly. Any step towards the centre is fine
            -- unless it crowds the character again ("Agrupar cercanos") or, with
            -- Keep Distance, puts it under pressure.
            eligible=distance(p,ctx.anchor)<distance(ctx.pos,ctx.anchor)
              and immediate.exits>0 and not crowded(ctx,immediate)
              and (ctx.surroundOnly or not pressure(immediate))
          elseif ctx.trapMode then
            local current=measure(ctx,ctx.pos)
            eligible=immediate.exits>0 and (not trapRisk(ctx,immediate) or freeAfter(immediate)>freeAfter(current))
          elseif ctx.surroundOnly then
            local current=measure(ctx,ctx.pos)
            -- Fewer monsters within the chosen distance counts as an improvement
            -- (the ranking above prefers it); it is not required, or a pack around
            -- the character at every side would leave no step at all.
            eligible=immediate.exits>0 and immediate.adjacent<=current.adjacent and immediate.future<=current.future
              and (immediate.crowd<current.crowd or immediate.crowdFuture<current.crowdFuture
                or immediate.adjacent<current.adjacent or immediate.future<current.future
                or immediate.safeExits>current.safeExits or immediate.exits>current.exits or immediate.near<current.near
                or item.depth==2 and finish.exits>0 and (finish.adjacent<current.adjacent
                  or finish.future<current.future or finish.safeExits>current.safeExits or finish.near<current.near))
          end
          for _,value in ipairs(safety) do score[#score+1]=value end
          -- An escape leaves the radius only when that is safer than staying inside.
          if ctx.anchor and not returning then score[#score+1]=distance(first,ctx.anchor)<=ctx.radius and 1 or 0 end
          if ctx.ahead then score[#score+1]=-distance(first,ctx.ahead) end
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
                immediateSafety={trapLead and trapLead[1] or 0,openLead or 0,spaceLead or 0,roomLead or 0,trapLead and trapLead[2] or 0,lead or 0,wide and -immediate.crowd or 0,-immediate.adjacent,-immediate.future,pressure(immediate) and 0 or 1,immediate.exits>0 and 1 or 0}}
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
-- "Agrupar cercanos" at 2+ SQM: is there a tile one step away (inside the Anclaje radius)
-- where no more than its maximum would be that close, now and one step later?
local function calmReachable(ctx)
  local limit=math.max(1,tonumber(ctx.config.closeLureAmount) or 3)
  for _,dir in ipairs(dirs) do
    local p={x=ctx.pos.x+dir[1],y=ctx.pos.y+dir[2],z=ctx.pos.z}
    if (not ctx.anchor or distance(p,ctx.anchor)<=ctx.radius) and canStep(ctx,ctx.pos,p) then
      local _,_,_,crowd,crowdFuture=nearby(ctx,p)
      if crowd<=limit and crowdFuture<=limit then return true end
    end
  end
  return false
end
local function engage(time)
  local started=not managed
  managed,ownedUntil=true,time+200
  if started then
    if CaveBot and CaveBot.resetWalking then CaveBot.resetWalking() end
    if player and player:isWalking() and g_game.stop then pcall(function() g_game.stop() end) end
  end
end
local function bugMapExit(ctx,blind)
  local rawCache,best={},nil
  local function rawFree(p)
    local id=key(p)
    if rawCache[id]==nil then
      local tile=g_map.getTile(p)
      local color=g_map.getMinimapColor and g_map.getMinimapColor(p) or 0
      local movement=TargetBot.Movement
      local physical=tile and tile:isWalkable(false)==true
      if movement and movement.walkableTile then physical=movement.walkableTile(tile,false) end
      rawCache[id]=withinAnchor(ctx,ctx.pos,p) and not ctx.occupied[id] and physical
        and tile:getGround()~=nil and not (color>=210 and color<=213)
        and (not TargetBot.Movement or TargetBot.Movement.floorSafe(p,tile))
    end
    return rawCache[id]
  end
  local function reachable(p,maxD)
    if type(findPath)~='function' then return true end
    local ok,path=pcall(findPath,ctx.pos,p,maxD+3,{ignoreCreatures=false,ignoreNonPathable=true,ignoreCost=true,
      ignoreStairs=false,allowOnlyVisibleTiles=true,precision=0})
    return ok and path~=nil
  end
  -- A boxed player has no native walk path. Jump clear of the pack: the safest
  -- tile 3-4 SQM away (3 when equally safe); a 2-SQM tile only when nothing
  -- farther is usable (a tight cave). Afterwards the usual movement takes over.
  local function search(minD,maxD)
    best=nil
    for dx=-maxD,maxD do
      for dy=-maxD,maxD do
        local p={x=ctx.pos.x+dx,y=ctx.pos.y+dy,z=ctx.pos.z}
        local d=distance(p,ctx.pos)
        if d>=minD and d<=maxD and rawFree(p) then
          local adjacent,future,near=nearby(ctx,p)
          local exits=0
          for _,dir in ipairs(dirs) do
            if rawFree({x=p.x+dir[1],y=p.y+dir[2],z=p.z}) then exits=exits+1 end
          end
          local score={-adjacent,-future,exits,-near,
            visits[key(p)] and -(2000-(ctx.time-visits[key(p)]))/1000 or 0,-d}
          -- Change 229: the server walks a BugMap only along a free path (monsters block it), so
          -- a tile it cannot reach is useless: "There is no way".
          if exits>=2 and better(score,best and best.score) and (blind or reachable(p,maxD)) then best={pos=p,score=score} end
        end
      end
    end
    return best and best.pos
  end
  return search(3,4) or search(2,2)
end
-- "Romper el encierro" (change 229): boxed in, the adjacent monster to kill first: the one whose
-- tile opens the most way out (free tiles around it, then open ground), then the weakest.
local function breakoutBlocker(ctx)
  local movement=TargetBot.Movement
  local best,bestScore
  for _,threat in ipairs(ctx.threats) do
    if threat.creature and distance(threat.pos,ctx.pos)<=1 then
      local beyond=0
      for _,dir in ipairs(dirs) do
        local q={x=threat.pos.x+dir[1],y=threat.pos.y+dir[2],z=threat.pos.z}
        if not same(q,ctx.pos) and not ctx.occupied[key(q)] then
          local tile=g_map.getTile(q)
          local open=tile and tile:isWalkable(false)==true
          if movement and movement.walkableTile then open=movement.walkableTile(tile,false) end
          if open and (not movement or movement.floorSafe(q,tile)) then beyond=beyond+1 end
        end
      end
      local score={beyond,room(ctx,threat.pos),-(tonumber(threat.hp) or 100)}
      if better(score,bestScore) then best,bestScore=threat.creature,score end
    end
  end
  return best
end
function A.breakout() return context and context.breakout or nil end
function A.update(specs,pos,config,time,targetPos,anchor)
  if manualMovement() then A.reset();return nil end
  -- "BugMap sin salida" alone also keeps the anti-trap on (never boxed in, even without Agrupar).
  if not config or not pos or not (config.keepDistance==true or config.closeLure==true or config.antitrapBugMap==true) then A.reset();return nil end
  local surroundOnly=config.keepDistance~=true
  if context and (context.pos.z~=pos.z or time<context.time or context.surroundOnly~=surroundOnly) then A.reset() end
  if not surroundOnly then holdChase() end
  context=makeContext(specs,pos,config,time,anchor)
  context.target=targetPos and point(targetPos) or nil
  context.surroundOnly=surroundOnly
  if #context.threats==0 then A.reset();return nil end
  local current=measure(context,pos)
  A.learnRanged(context,current,time)
  local crowding=crowded(context,current)
  -- "Agrupar cercanos" beyond 1 SQM with a pack too big for it (8 monsters, maximum 3
  -- at 2 SQM): when no tile one step away keeps that count, walking only drags the
  -- limit around (it kited non-stop). Then only adjacent monsters count, until a step
  -- that keeps it exists again. The trap guard ("BugMap sin salida") is unchanged.
  if crowding and context.crowdRange>1 and not trapRisk(context,current) and not calmReachable(context) then
    context.crowdRange=1
    context.metrics={}
    current=measure(context,pos)
    crowding=crowded(context,current)
  end
  -- "BugMap sin salida" with Agrupar cercanos: completely boxed in (no walking
  -- exit) counts as an emergency even below the Agrupar limit.
  local boxed=surroundOnly and config.antitrapBugMap==true and current.exits==0 and current.adjacent>=2
  -- Boxed in (any rule with the anti-trap on): the TargetBot attacks the blocker to open a way.
  context.breakout=current.exits==0 and current.adjacent>=2 and breakoutBlocker(context) or nil
  A.watchEpisode(context,current,time)
  if crowding or boxed or not surroundOnly and pressure(current) then
    context.trapMode=trapRisk(context,current)
    local best=findExit(context,targetPos)
    if not best and crowding and context.anchor then
      -- Anclaje: boxed in at the edge of the margin. Being body-blocked is
      -- worse than one more step out, up to the emergency margin (a hard
      -- limit, so a pack as fast as the character cannot drag it away). The
      -- centre stays and the return follows.
      context.escapeRadius=context.radius+EMERGENCY_MARGIN
      context.metrics,context.firstSteps={},{}
      best=findExit(context,targetPos)
    end
    if surroundOnly and not best then
      if config.antitrapBugMap==true and current.exits==0 and current.adjacent>=2
        and BugMapMouse and type(BugMapMouse.tryUsePosition)=='function' then
        if not same(stuckPos,pos) then stuckPos,stuckSince=point(pos),time end
        bugMapAt=math.max(stuckSince+bugMapDelay(config),lastBugMap+BUGMAP_RETRY)
        if time>=bugMapAt then
          -- Last resort: being boxed in is worse than leaving the Anclaje area;
          -- the centre stays and the way back follows.
          context.escapeRadius=math.huge
          local destination=bugMapExit(context)
          -- Fallback (change 229): still boxed after 1.5 s, one try every 2 s without a known
          -- path, in case this server lets it through ("There is no way" when it does not).
          if not destination and stuckSince and time-stuckSince>=1500 and time-blindAt>=2000 then
            destination=bugMapExit(context,true)
            if destination then blindAt=time end
          end
          if destination then
            engage(time)
            return {bugMap=destination,anywhere=true,metrics=current,status='Anti-trap: intentando BugMap'}
          end
          bugMapAt=time+BUGMAP_RETRY -- nowhere to jump yet: look again later, not every 20 ms
        end
      else
        stuckPos,stuckSince,bugMapAt=nil,nil,nil
      end
      managed,pending=false,nil
      return nil
    end
    returnAfter=time+RETURN_DELAY -- Do not immediately walk back into a recent escape.
    engage(time)
    if best then stuckPos,stuckSince,bugMapAt=nil,nil,nil
    elseif not same(stuckPos,pos) then stuckPos,stuckSince=point(pos),time end
    if not best and config.antitrapBugMap==true and current.exits==0 and current.adjacent>=2
      and BugMapMouse and type(BugMapMouse.tryUsePosition)=='function' then
      bugMapAt=math.max(stuckSince+bugMapDelay(config),lastBugMap+BUGMAP_RETRY)
      if time>=bugMapAt then
        local destination=bugMapExit(context)
        if destination then return {bugMap=destination,metrics=current,status='Anti-trap: intentando BugMap'} end
        bugMapAt=time+BUGMAP_RETRY
      end
    end
    return {step=best and best.dir,position=best and best.pos,metrics=current,
      status=best and (trapRisk(context,current) and 'Anti-trap: evito el encierro' or 'Anti-trap') or 'Anti-trap: sin salida'}
  end
  stuckPos,stuckSince,bugMapAt=nil,nil,nil
  if context.combatAnchor and distance(pos,context.combatAnchor)>context.radius then
    engage(time)
    local best=time>=returnAfter and choose(context,targetPos,true) or nil
    return {step=best and best.dir,position=best and best.pos,metrics=current,
      status=best and 'Anclaje: volviendo al area' or 'Anclaje: esperando hueco para volver'}
  end
  if managed and time<ownedUntil and player:isWalking() then return {status='Anti-trap',metrics=current} end
  managed=false
  pending=nil
  return nil
end
-- Read-only, for calm TargetBot movement ("Tirar hacia la ruta"): false when p is closer
-- to the pack than here (more monsters within 2 SQM or within the "Agrupar cercanos"
-- distance), would count as crowded or, with "BugMap sin salida", is a tile the monsters
-- nearby can close. Leaning into the pack undid the last escape every other tick.
function A.calmSpot(pos,p)
  if not context or not pos or not p or not same(pos,context.pos) or #context.threats==0 then return true end
  local here,there=measure(context,context.pos),measure(context,p)
  if there.near>here.near or there.crowd>here.crowd or there.adjacent>here.adjacent then return false end
  if crowded(context,there) then return false end
  if context.config.antitrapBugMap==true and there.near>0 and space(context,p)<DEAD_END then return false end
  return not (context.config.antitrapBugMap==true and there.adjacent+there.future>0 and closable(there))
end
-- Read-only, for the AttackBot's spell positioning (change 210): false when p breaks what
-- this antitrap keeps, so it would flee from p at once: more monsters than "Agrupar
-- cercanos" allows within its distance, or with "BugMap sin salida" a tile the pack can
-- close. Unlike calmSpot it may get closer to the pack within those limits (a spell needs it).
function A.spellSpot(pos,p)
  if not context or not pos or not p or not same(pos,context.pos) or #context.threats==0 then return true end
  local m=measure(context,p)
  if crowded(context,m) then return false end
  -- Change 231, "BugMap sin salida" ON: not into a dead end with monsters close.
  return not (context.config.antitrapBugMap==true and m.near>0 and space(context,p)<DEAD_END)
end
-- Change 230: one entry per boxed-in or nearly boxed-in episode, so real cases can be studied.
-- "encerrado": no free tile around and 2+ adjacent; "casi": BugMap sin salida saw the trap
-- closing with one exit or none. Closed 1 s after it ends (or when the fight ends).
local function clock()
  return os and os.date and os.date("%Y-%m-%d %H:%M:%S") or tostring(now)
end
finishEpisode=function(time,why)
  local e=episode
  episode=nil
  if not e then return end
  local ms=math.max(0,(tonumber(time) or e.last)-e.start)
  if e.kind=='casi' and ms<200 then return end
  local pos=player and player:getPosition()
  local moved=pos and not same(pos,e.pos)
  local how=why or (e.bugmaps>0 and moved and 'BugMap') or (moved and 'caminando') or
    (e.blocker and 'matando al que tapaba') or 'se abrio solo'
  local entry={at=clock(),pos=e.pos.x..','..e.pos.y..','..e.pos.z,tipo=e.kind,ms=ms,pegados=e.adjacent,
    cerca=e.near,salidas=e.exits,espacio=e.room,pasos=e.steps,bugmaps=e.bugmaps,tapaba=e.blocker,
    salio=how,bugmapSinSalida=e.bugMapOn,agrupar=e.agrupar}
  if type(storage)=='table' then
    local log=type(storage.antitrapLog)=='table' and storage.antitrapLog or {}
    log[#log+1]=entry
    while #log>TRAP_LOG do table.remove(log,1) end
    storage.antitrapLog=log
  end
  if RinoConsole and RinoConsole.valid and RinoConsole.valid() then
    pcall(RinoConsole.log,'action','Antitrap',(e.kind=='encerrado' and 'Encerrado ' or 'Casi encerrado ')..
      string.format('%.1f s en %s',ms/1000,entry.pos),
      'pegados '..e.adjacent..' | salidas '..e.exits..' | espacio '..e.room..' | sale: '..how..
      (e.blocker and (' | ataca a '..e.blocker) or ''))
  end
end
function A.watchEpisode(ctx,current,time)
  local boxed=current.exits==0 and current.adjacent>=2
  local closing=ctx.config.antitrapBugMap==true and current.exits<=1 and trapRisk(ctx,current)
  if boxed or closing then
    if not episode then
      local cfg=ctx.config
      episode={start=time,last=time,pos=point(ctx.pos),kind='casi',adjacent=0,near=0,exits=8,
        room=room(ctx,ctx.pos),steps=0,bugmaps=0,bugMapOn=cfg.antitrapBugMap==true,
        agrupar=cfg.closeLure==true and ((tonumber(cfg.closeLureAmount) or 3)..' a '..(tonumber(cfg.closeLureRange) or 1)..' SQM') or 'no'}
    end
    episode.last=time
    if boxed then episode.kind='encerrado' end
    episode.adjacent=math.max(episode.adjacent,current.adjacent)
    episode.near=math.max(episode.near,current.near)
    episode.exits=math.min(episode.exits,current.exits)
    local blocker=ctx.breakout
    if blocker then
      local ok,name=pcall(function() return blocker:getName() end)
      if ok and name then episode.blocker=name end
    end
  elseif episode and time-episode.last>=1000 then
    finishEpisode(episode.last)
  end
end
-- Change 232: which monsters fight from a distance, learned by name and kept per profile. Each
-- step a monster takes AWAY from the character (with 50%+ health, so not fleeing) counts for its
-- name, at most 2 per monster: melee monsters only come closer. A monster adjacent for 2 s counts
-- once as melee. A name is ranged with 3+ such steps and 3 times more than melee sightings.
local function book()
  if rangedBook then return rangedBook end
  if type(storage)=='table' then
    if type(storage.antitrapRanged)~='table' then storage.antitrapRanged={} end
    rangedBook=storage.antitrapRanged
  else rangedBook={} end
  return rangedBook
end
function A.isRangedName(name)
  local entry=name and book()[name]
  if type(entry)~='table' then return false end
  local r,m=tonumber(entry.r) or 0,tonumber(entry.m) or 0
  return r>=3 and r>=3*m
end
local function note(name,field)
  local entry=book()[name]
  if type(entry)~='table' then entry={};book()[name]=entry end
  entry[field]=(tonumber(entry[field]) or 0)+1
end
function A.learnRanged(ctx,current,time)
  local pos=ctx.pos
  for _,threat in ipairs(ctx.threats) do
    local id,name=threat.id,threat.name
    if id and name then
      local w=rangedWatch[id]
      if not w then w={retreats=0,last=point(threat.pos)};rangedWatch[id]=w end
      w.seen=time
      if not w.judged then
        local d=distance(threat.pos,pos)
        if d<=1 then
          w.adjacent=w.adjacent or time
          if time-w.adjacent>=2000 then w.judged=true;note(name,'m') end
        else
          w.adjacent=nil
          if not same(w.last,threat.pos) then
            if (tonumber(threat.hp) or 100)>=50 and d>distance(w.last,pos) and w.retreats<2 then
              w.retreats=w.retreats+1;note(name,'r')
            end
            w.last=point(threat.pos)
          end
        end
      end
    end
  end
  for id,w in pairs(rangedWatch) do if time-(w.seen or 0)>10000 then rangedWatch[id]=nil end end
end
-- This is called by a separate timer, so spell/route pauses cannot suspend safety.
function A.refresh(pos,time)
  if manualMovement() then A.reset();return nil end
  if not context then return nil end
  if not pos or pos.z~=context.pos.z then A.reset();return nil end
  -- Standing still it re-checks every 100 ms, except when a boxed-in BugMap is due.
  if same(pos,context.pos) and time>=context.time and time-context.time<100 and not A.bugMapDue(time) then return nil end
  return A.update(g_map.getSpectatorsInRange(pos,false,6,6),pos,context.config,time,context.target,context.combatAnchor)
end
function A.poll(time) return A.refresh(player and player:getPosition(),time) end
function A.send(plan,time)
  if manualMovement() then A.reset();return false end
  if not plan or not context then return false end
  local pos=player:getPosition()
  if not same(pos,context.pos) then return false end
  if plan.bugMap then
    if not plan.anywhere and not withinAnchor(context,pos,plan.bugMap) then return false end
    if TargetBot.Movement and not TargetBot.Movement.floorSafe(plan.bugMap) then return false end
    if time-lastBugMap<BUGMAP_RETRY or not BugMapMouse or type(BugMapMouse.tryUsePosition)~='function' then return false end
    lastBugMap=time
    if episode then episode.bugmaps=episode.bugmaps+1 end
    bugMapAt=time+BUGMAP_RETRY -- still boxed in after this: try again then
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
  if result~=false and episode then episode.steps=episode.steps+1 end
  return result~=false
end
-- Read-only lookahead for a short native route. Do not refresh context at a
-- hypothetical future position or engage/send an escape while scoring it.
function A.canRouteStep(pos,direction)
  if manualMovement() then return false end
  if TargetBot.Movement and not TargetBot.Movement.canStep(pos,direction) then return false end
  if not context or context.surroundOnly and not managed then return true end
  local offset=dirs[(tonumber(direction) or -1)+1]
  if not offset then return false end
  local destination={x=pos.x+offset[1],y=pos.y+offset[2],z=pos.z}
  if not withinAnchor(context,pos,destination,context.radius) then return false end
  if #context.threats==0 then return true end
  if not canStep(context,pos,destination) then return false end
  local current,nextMetrics=measure(context,pos),measure(context,destination)
  return nextMetrics.exits>0 and not(pressure(nextMetrics)and not pressure(current))
    and not(nextMetrics.adjacent>=2 and nextMetrics.adjacent>current.adjacent)
    and not(nextMetrics.future>=2 and nextMetrics.future>current.future)
end

function A.guardStep(pos,direction)
  if manualMovement() then return nil end
  if not context then return direction end
  -- Applies even without encirclement: keeping distance must never use a stair.
  if TargetBot.Movement and not TargetBot.Movement.canStep(pos,direction) then return nil end
  A.refresh(pos,now or context.time)
  if not context then return direction end
  local dir
  for _,item in ipairs(dirs) do if item[3]==direction then dir=item;break end end
  if not dir then return nil end
  local destination={x=pos.x+dir[1],y=pos.y+dir[2],z=pos.z}
  -- Ordinary TargetBot movement keeps the radius; only escapes use the margin.
  if not withinAnchor(context,pos,destination,context.radius) then return nil end
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
  returnAfter=context.time+RETURN_DELAY
  engage(context.time)
  return best.dir
end
