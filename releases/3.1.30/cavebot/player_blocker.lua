-- Clear a player from the current goto without changing the route cursor.
CaveBot.PlayerBlocker = {}
local B=CaveBot.PlayerBlocker
local state
local offsets={{0,-1},{1,0},{0,1},{-1,0},{1,-1},{1,1},{-1,1},{-1,-1}}
local function copy(p)return {x=p.x,y=p.y,z=p.z}end
local function key(p)return p.x..','..p.y..','..p.z end
local function same(a,b)return a and b and key(a)==key(b)end
local function distance(a,b)return math.max(math.abs(a.x-b.x),math.abs(a.y-b.y))end
local function currentRow()
  local list=CaveBot.actionList
  return list and (list:getFocusedChild()or list:getFirstChild())
end
local function livingPlayer(actor)
  if not actor or actor==player or not actor.isPlayer or not actor:isPlayer()then return false end
  local health=actor.getHealthPercent and actor:getHealthPercent()
  return not health or health>0
end
local function flag(object,name)
  if not object or type(object[name])~='function'then return false end
  local ok,value=pcall(object[name],object)
  return ok and value==true
end
-- Inside a protection zone players can be walked through: they are crossed (see
-- crossTick), not pushed, unless the server refused to let us through there.
local function inPz()
  if type(isInPz)~='function'then return false end
  local ok,value=pcall(isInPz)
  return ok and value==true
end
B.inPz=inPz
local function actorId(actor)
  local ok,id=pcall(function() return actor:getId() end)
  return ok and id or actor
end
-- A player this goto gave up on (could not go round or move it): treated as
-- before the push existed until the goto changes or the player moves.
local skipped=nil
local function isSkipped(actor,row)
  local position=skipped and actor and actor.getPosition and actor:getPosition()
  return skipped~=nil and skipped.row==row and skipped.id==actorId(actor) and same(skipped.from,position)
end
local function landing(p,origin)
  if p.x<0 or p.x>=65535 or p.y<0 or p.y>=65535 or same(p,origin)then return false end
  local tile=g_map.getTile(p)
  if not tile or not tile:getGround() or not tile:isWalkable(false)then return false end
  for _,actor in ipairs(tile.getCreatures and tile:getCreatures()or{})do if actor then return false end end
  local movement=TargetBot and TargetBot.Movement
  if movement and movement.floorSafe and not movement.floorSafe(p,tile)then return false end
  local color=tonumber(g_map.getMinimapColor and g_map.getMinimapColor(p))or 0
  if color>=210 and color<=213 or tile.hasElevation and tile:hasElevation(3)then return false end
  for _,name in ipairs({'isFloorChange','isFloorChangeUp','isFloorChangeDown'})do
    if flag(tile,name)then return false end
  end
  local explorer=CaveBot.AutoExplorer
  if explorer and explorer.getFloorChangeThing and explorer.getFloorChangeThing(tile)then return false end
  local things=tile.getItems and tile:getItems()or{}
  for _,thing in ipairs(things)do
    if flag(thing,'isFloorChange')or flag(thing,'isMagicField')or
      movement and movement.isDamageField and movement.isDamageField(thing)then return false end
  end
  return not flag(tile:getGround(),'isFloorChange')
end
-- Go round first: a player in the way is pushed only when no path that avoids
-- creatures reaches the waypoint, or that path is a long detour and the push has
-- not worked for DETOUR_AFTER ms. The detour uses the goto's own first search.
-- After DETOUR_AFTER ms with no way round and the player still there, the push
-- gives up and the goto goes on as it did before the push existed (no endless wait).
local DETOUR_EXTRA,DETOUR_AFTER,DETOUR_CHECK,OBSTACLE_RETRY=8,5000,500,2000
local obstacles={}
-- The client may count players inside a protection zone as passable, so a path it
-- finds "avoiding creatures" can still go through them: that is not a way round.
local function crossesPlayer(origin,path)
  local p=copy(origin)
  for _,direction in ipairs(path)do
    local o=offsets[direction+1]
    if not o then return true end
    p={x=p.x+o[1],y=p.y+o[2],z=p.z}
    local tile=g_map.getTile(p)
    for _,actor in ipairs(tile and tile.getCreatures and tile:getCreatures()or{})do
      if livingPlayer(actor)then return true end
    end
  end
  return false
end
B.crossesPlayer=crossesPlayer
local function detour(origin,goal)
  if not origin or not goal or goal.z~=origin.z or type(findPath)~='function' then return nil end
  local limit=tonumber(storage.extras and storage.extras.gotoMaxDistance)or 24
  local ok,path=pcall(findPath,origin,goal,limit,
    {ignoreFields=true,ignoreNonPathable=true,allowUnseen=true,allowOnlyVisibleTiles=false})
  if ok and type(path)=='table' and path[1] and not crossesPlayer(origin,path) then return path end
end
-- Drop the planned steps; the goto plans again (round the blocker) on its next run.
local function goRound()
  state=nil
  CaveBot.resetWalking()
  CaveBot.delay(50)
  return true
end
local function giveUp()
  local actor,goal=state.creature,state.goal
  skipped={row=state.row,id=actorId(actor),from=copy(state.from)}
  state=nil
  if type(warn)=='function' then
    local ok,name=pcall(function() return actor:getName() end)
    pcall(warn,'CaveBot: '..(ok and tostring(name) or 'un jugador')..' tapa el paso hacia '..goal.x..','..goal.y..','..goal.z..
      '; no se pudo rodear ni apartar en '..(DETOUR_AFTER/1000)..' s, sigo sin esperarlo.')
  end
  return false
end
-- Something other than a crossable player on the tile, or the tile itself blocks.
local function blocked(tile,pz)
  local ok,walkable=pcall(function() return tile:isWalkable(true) end)
  if ok and walkable==false then return true end
  for _,actor in ipairs(tile:getCreatures()or{})do
    if actor~=player and not flag(actor,'isLocalPlayer') and not (pz and flag(actor,'isPlayer')) then return true end
  end
  return false
end
-- Crossing a player inside a protection zone. The server (TFS/Canary
-- Player::canWalkthrough) refuses the first two steps into the same player with
-- "Sorry, not possible." and lets the next one through when they come within 2 s,
-- which is what holding the arrow key does. Planned steps sent after a refused one
-- start from the wrong tile and hit other players or walls, so the count could
-- restart forever. While crossing, the same step is repeated and nothing else is
-- sent. A player not crossed in CROSS_LIMIT ms (the server does not allow it there)
-- is treated as outside a protection zone for CROSS_FORGET ms: way round, push, 5 s limit.
-- A step sent while the server still waits a step's time after the last attempt only
-- replaces that pending step, so a short CROSS_EVERY never loses an attempt.
local CROSS_EVERY,CROSS_LIMIT,CROSS_FORGET=250,3500,10000
B.PZ_FREE_EXTRA=4 -- also used by CaveBot.walkTo (cavebot/walking.lua) to pick the path
local crossing=nil
local refused={}
local function report(text)
  if RinoConsole and type(RinoConsole.log)=='function' then pcall(RinoConsole.log,'action','CaveBot',text) end
end
function B.crossRefused(p)
  return p~=nil and (refused[key(p)]or 0)>now
end
local function crossTick(row)
  local c=crossing
  if c.row~=row or row.action~='goto' or not same(player:getPosition(),c.origin) or not inPz() then
    crossing=nil;return false
  end
  -- Not serviced for a while (the route was paused): the time limit starts again.
  if now-c.seen>1000 then c.since,c.sent=now,0 end
  c.seen=now
  if now-c.since>=CROSS_LIMIT then
    refused[key(c.target)]=now+CROSS_FORGET
    crossing=nil
    report('PZ: no pude atravesar a '..c.name..' en '..(CROSS_LIMIT/1000)..' s ('..c.sent..
      ' intentos, el servidor no lo deja); lo rodeo o lo aparto')
    return false
  end
  if now>=c.nextAt then
    local ok,sent=pcall(safeBotWalk,c.direction)
    if ok and sent~=false then c.sent=c.sent+1;c.nextAt=now+CROSS_EVERY else c.nextAt=now+100 end
  end
  CaveBot.delay(50)
  return true
end
local function startCross(row,direction,origin,target,actor)
  if not crossing or crossing.row~=row or not same(crossing.origin,origin) or not same(crossing.target,target) then
    local ok,name=pcall(function() return actor:getName() end)
    crossing={row=row,direction=direction,origin=copy(origin),target=copy(target),since=now,seen=now,nextAt=0,sent=0,
      name=ok and tostring(name)or'un jugador'}
  end
  return crossTick(row)
end
-- The server confirmed our crossing step (true), or we moved some other way (false).
function B.crossed(newPos,oldPos)
  local c=crossing
  if not c or not same(oldPos,c.origin) then return false end
  crossing=nil
  if not same(newPos,c.target) then return false end
  report('PZ: atravese a '..c.name..' ('..c.sent..' intentos, '..(now-c.since)..' ms)')
  return true
end
local function routeTiles(origin,path)
  local tiles,p={},copy(origin)
  for _,direction in ipairs(path or{})do
    local o=offsets[direction+1]
    if not o then break end
    p={x=p.x+o[1],y=p.y+o[2],z=p.z};tiles[key(p)]=true
  end
  return tiles
end
local function service()
  local movement=TargetBot and TargetBot.Movement
  if movement and movement.isManual and movement.isManual()then CaveBot.delay(100);return true end
  local origin=player:getPosition()
  local actor=state.creature
  local position=actor and actor:getPosition()
  -- A changed source square is the server confirmation, not move()'s return.
  if not livingPlayer(actor)or not same(position,state.from)or origin.z~=state.from.z then
    state=nil;return false
  end
  -- A way round (opened now, or long and the push is not working): take it.
  if now>=(state.detourAt or 0)then
    state.detourAt=now+DETOUR_CHECK
    local around=detour(origin,state.goal)
    if around and(#around<=state.length+DETOUR_EXTRA or now-state.since>=DETOUR_AFTER)then return goRound()end
    state.around=around~=nil
  end
  if now-state.since>=DETOUR_AFTER then return giveUp()end
  if state.pending then
    if now<state.pending.untilAt then CaveBot.delay(100);return true end
    state.failed[key(state.pending.destination)]=now+3000
    state.pending=nil
  end
  if now<state.nextAt or player:isWalking()then CaveBot.delay(100);return true end
  if distance(origin,position)>1 then
    state.since=now -- the 5 s for pushing count from when we stand next to it
    CaveBot.walkTo(position,tonumber(storage.extras and storage.extras.gotoMaxDistance)or 24,
      {precision=1,ignoreNonPathable=true,ignoreCreatures=false,allowUnseen=true,allowOnlyVisibleTiles=false})
    CaveBot.delay(100);return true
  end
  local choices={}
  for i,o in ipairs(offsets)do
    local p={x=position.x+o[1],y=position.y+o[2],z=position.z}
    if (state.failed[key(p)]or 0)<=now and landing(p,origin)then
      choices[#choices+1]={position=p,score=(state.route[key(p)]and 100 or 0)+(i>4 and 2 or 0)+distance(p,state.goal)*0.01,index=i}
    end
  end
  table.sort(choices,function(a,b)if a.score==b.score then return a.index<b.index end;return a.score<b.score end)
  local choice=choices[1]
  if not choice then
    -- Nowhere to push it: any way round is better than waiting.
    if state.around then return goRound()end
    state.nextAt=now+500;CaveBot.delay(250);return true
  end
  local destination=choice.position
  local ok,result=pcall(g_game.move,actor,destination,1)
  local wait=math.max(2000,(tonumber(CaveBot.Config.get('ping'))or 100)*4+500)
  if ok and result~=false then
    state.pending={destination=destination,untilAt=now+wait}
    state.nextAt=now+wait
  else
    state.failed[key(destination)]=now+3000
    state.nextAt=now+350
  end
  CaveBot.delay(100)
  return true
end
function B.reset()state=nil;crossing=nil end
function B.isActive()return state~=nil or crossing~=nil end
function B.tick(row)
  if crossing then return crossTick(row) end
  if not state then return false end
  if state.row~=row or row.action~='goto'then B.reset();return false end
  return service()
end
function B.tryClear(actor,goal,path)
  local row=currentRow()
  local origin=player:getPosition()
  local position=livingPlayer(actor)and actor:getPosition()
  if not row or row.action~='goto'or not goal or not position or position.z~=origin.z then return false end
  if (inPz() and not B.crossRefused(position)) or isSkipped(actor,row) then return false end
  if not state or state.row~=row or state.creature~=actor or not same(state.from,position)then
    state={row=row,creature=actor,from=copy(position),goal=copy(goal),route=routeTiles(origin,path),failed={},nextAt=0,
      since=now,length=#(path or{})}
  end
  return service()
end
function B.beforeStep(direction,path,index)
  local row=currentRow()
  if not row or row.action~='goto'then return false end
  local o=offsets[direction+1]
  local origin=player:getPosition()
  if not o then return false end
  local tile=g_map.getTile({x=origin.x+o[1],y=origin.y+o[2],z=origin.z})
  if not tile then return false end
  local goal=CaveBot.Waypoints.position(row.action,row.value)
  local remaining={}
  for i=index or 1,#(path or{})do remaining[#remaining+1]=path[i]end
  if #remaining==0 then remaining[1]=direction end
  local target={x=origin.x+o[1],y=origin.y+o[2],z=origin.z}
  -- Inside a protection zone a player is walked through, unless the server already
  -- refused it here (then it is gone round or pushed like outside).
  local pz=inPz()
  local through=pz and not B.crossRefused(target)
  for _,actor in ipairs(tile:getCreatures()or{})do
    if livingPlayer(actor)then
      if through then
        if blocked(tile,true)then break end
        -- Crossing costs a few refused steps: a free way at most PZ_FREE_EXTRA steps longer is quicker.
        if not crossing then
          local around=detour(origin,goal)
          if around and #around<=#remaining+B.PZ_FREE_EXTRA then return goRound()end
        end
        return startCross(row,direction,origin,target,actor)
      end
      if not isSkipped(actor,row)then
        if not state then
          local around=detour(origin,goal)
          if around and #around<=#remaining+DETOUR_EXTRA then return goRound()end
        end
        return B.tryClear(actor,goal,remaining)
      end
      -- Inside a protection zone the client may plan through players: one the server
      -- would not let us cross and that could not be gone round or moved closes this
      -- way (second result), so the goto goes on instead of stepping into it again.
      if pz and not blocked(tile,true)then return false,true end
    end
  end
  -- Something else now blocks the planned step (a monster, an NPC, an item; not
  -- a player inside a protection zone): plan again instead of walking into it.
  -- Once per tile every OBSTACLE_RETRY ms.
  if blocked(tile,through)then
    local stepKey=key(target)
    if now-(obstacles[stepKey]or -OBSTACLE_RETRY)>=OBSTACLE_RETRY then
      obstacles={[stepKey]=now}
      return goRound()
    end
  end
  return false
end
