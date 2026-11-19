-- Return to the current waypoint after an unexpected displacement.
CaveBot.RouteRecovery = {}
local R = CaveBot.RouteRecovery
local recent, departure, job, trackedRow, trackedGoal, trackedRange, lastOnRoute
local offsets = {{0,-1},{1,0},{0,1},{-1,0},{1,-1},{1,1},{-1,1},{-1,-1}}

local function key(p) return p.x..','..p.y..','..p.z end
local function point(p) return {x=p.x,y=p.y,z=p.z} end
local function distance(a,b) return math.max(math.abs(a.x-b.x),math.abs(a.y-b.y)) end
local function inRange(position,goal,limit)
  return position.z==goal.z and math.abs(position.x-goal.x)+math.abs(position.y-goal.y)<=limit
end
local function offset(p,dx,dy) return {x=p.x+dx,y=p.y+dy,z=p.z} end
local function changeColor(value)
  local color=tonumber(value) or 0
  return color>=210 and color<=213
end

function R.reset()
  recent,departure,job,trackedRow,trackedGoal,trackedRange,lastOnRoute=nil,nil,nil,nil,nil,nil,nil
end

function R.observe(newPos,oldPos)
  if not newPos or not oldPos then return end
  local displaced=newPos.z~=oldPos.z or distance(newPos,oldPos)>4
  if displaced then recent={from=point(oldPos),to=point(newPos),at=now} end
  if job or departure or not trackedGoal then return end
  if inRange(oldPos,trackedGoal,trackedRange) and
    (displaced or not inRange(newPos,trackedGoal,trackedRange)) then
    -- Keep the first departure, even if the character changes floors again
    -- while CaveBot is waiting for combat or manual movement to end.
    departure={from=point(oldPos),to=point(newPos),at=now}
  elseif inRange(newPos,trackedGoal,trackedRange) then
    lastOnRoute=point(newPos)
  end
end

local function plannedLanding(goal,nextGoal,position,change)
  if not change or now-change.at>6000 or not nextGoal or nextGoal.z~=position.z then return false end
  return change.from.z==goal.z and change.to.z==position.z and
    distance(change.from,goal)<=2 and distance(change.to,nextGoal)<=12 and distance(position,change.to)<=4
end

local function nativeFlag(object,name)
  if not object or type(object[name])~='function' then return false end
  local ok,value=pcall(object[name],object)
  return ok and value==true
end

local function isRope(thing)
  if not thing then return false end
  local id=thing:getId()
  for _,ropeId in ipairs(Global and Global.ropeIds or {}) do
    if id==ropeId then return true end
  end
  return false
end

local function describeExit(p,wanted,entrance)
  local tile=g_map.getTile(p)
  if not tile then return end
  local explorer=CaveBot.AutoExplorer
  local thing,action
  if explorer and explorer.getFloorChangeThing then thing,action=explorer.getFloorChangeThing(tile) end
  if isRope(thing) then action='rope' end
  local up=wanted<p.z
  if action=='rope' and not up or action=='shovel' and up then return end
  local floorUp=nativeFlag(tile,'isFloorChangeUp')
  local floorDown=nativeFlag(tile,'isFloorChangeDown')
  if (not action or action=='use') and (up and floorDown and not floorUp or not up and floorUp and not floorDown) then return end
  local marked=floorUp or floorDown or nativeFlag(tile,'isFloorChange') or
    changeColor(tile.getMinimapColorByte and tile:getMinimapColorByte()) or
    changeColor(g_map.getMinimapColor and g_map.getMinimapColor(p))
  -- An elevated landing can be the unmarked reverse of a regular stair.
  local raised=entrance and distance(p,entrance)<=1 and tile.hasElevation and tile:hasElevation(3)
  if not action and not marked and not raised then return end
  return {position=p,action=action or 'step',thing=thing,knownDirection=up and floorUp or not up and floorDown}
end

local function approach(origin,goal,limit,precision,visible)
  local route=findPath(origin,goal,limit,{ignoreNonPathable=true,ignoreFields=true,ignoreStairs=false,
    ignoreCreatures=false,precision=precision,allowOnlyVisibleTiles=visible,allowUnseen=not visible})
  local movement=TargetBot and TargetBot.Movement
  if route and route[1] and (not movement or
    (visible and movement.pathSafe(origin,route) or not visible and movement.canStep(origin,route[1]))) then return route[1] end
end

local function walkStep(direction,changingFloor)
  if not changingFloor and CaveBot.protectStep and not CaveBot.protectStep(direction) then return false end
  return safeBotWalk(direction)~=false
end

local function selectExit(origin,goal,entrance)
  local candidates={}
  local range=g_map.getAwareRange and g_map.getAwareRange() or {}
  local rx,ry=math.min(8,tonumber(range.left) or 8),math.min(6,tonumber(range.top) or 6)
  for x=-rx,rx do
    for y=-ry,ry do
      local p=offset(origin,x,y)
      if p.x>=0 and p.x<65535 and p.y>=0 and p.y<65535 and (job.failed[key(p)] or 0)<=now then
        local exit=describeExit(p,goal.z,entrance)
        if exit then
          local nearby=entrance and distance(entrance,p) or 99
          exit.distance=distance(origin,p)
          exit.priority=(nearby<=1 and nearby or 3)+(exit.knownDirection and 0 or 1)
          candidates[#candidates+1]=exit
        end
      end
    end
  end
  table.sort(candidates,function(a,b)
    if a.priority~=b.priority then return a.priority<b.priority end
    return a.distance<b.distance
  end)
  for i=1,math.min(#candidates,8) do
    local exit=candidates[i]
    if exit.distance<=1 then return exit end
    local dir=approach(origin,exit.position,16,1,true)
    if dir then exit.approach=dir;return exit end
  end
end

local function attemptExit(exit,origin)
  if exit.approach then return walkStep(exit.approach),false end
  if exit.action=='rope' then
    return useWith(tonumber(storage.extras and storage.extras.rope) or 3003,exit.thing)~=false,true
  elseif exit.action=='shovel' then
    return useWith(tonumber(storage.extras and storage.extras.shovel) or 3457,exit.thing)~=false,true
  elseif exit.action=='use' then
    return use(exit.thing)~=false,true
  end
  local movement=TargetBot and TargetBot.Movement
  if exit.distance==0 then
    for i=1,#offsets do
      if movement and movement.canStep(origin,i-1) then return walkStep(i-1),false end
    end
  else
    local p=exit.position
    for i,o in ipairs(offsets) do
      if p.x-origin.x==o[1] and p.y-origin.y==o[2] then return walkStep(i-1,true),true end
    end
  end
  return false,false
end

-- The route cursor stays on the pending goto throughout recovery.
function R.update(row,nextGoal,origin,maxDistance,log)
  local goal=row and row.action=='goto' and CaveBot.Waypoints.position(row.action,row.value)
  if trackedRow~=row then trackedRow,departure,lastOnRoute,job=row,nil,nil,nil end
  trackedGoal,trackedRange=goal,maxDistance
  if not goal or not origin then return end
  local change=recent and now-recent.at<=60000 and recent or nil
  local inside=inRange(origin,goal,maxDistance)
  local changedFloor=origin.z~=goal.z
  if not job and not inside and plannedLanding(goal,nextGoal,origin,departure or change) then
    recent,departure=nil,nil
    return 'advance'
  end
  if not job and inside and not departure then
    lastOnRoute=point(origin)
    return
  end

  local left=departure or (change and inRange(change.from,goal,maxDistance) and change.to.z==origin.z and change)
  if not job and not left and not lastOnRoute and
    (not changedFloor or distance(origin,goal)>math.min(maxDistance,24)) then return end
  local movement=TargetBot and TargetBot.Movement
  if movement and movement.isManual and movement.isManual() then return 'hold' end
  local here=key(origin)
  if not job then
    local anchor=left and left.from or lastOnRoute or goal
    job={anchor=point(anchor),position=here,progressAt=now,failed={},nextAt=0}
    if CaveBot.stopPathWalk then CaveBot.stopPathWalk() end
    CaveBot.resetWalking()
    log('Personaje fuera de ruta. Volviendo al punto donde salió.',key(anchor))
  end
  local anchor=job.anchor
  if here==key(anchor) then
    if player:isWalking() then return 'hold' end
    job,recent,departure,lastOnRoute=nil,nil,nil,point(origin)
    log('Punto de salida recuperado. Continúa el mismo waypoint.',here)
    return 'resume'
  end
  changedFloor=origin.z~=anchor.z
  if here~=job.position then job.position,job.progressAt=here,now end
  if job.pending then
    if origin.z==job.pending.floor and now<job.pending.untilAt then return 'hold' end
    local wrongFloor=origin.z~=job.pending.floor and
      math.abs(origin.z-anchor.z)>=math.abs(job.pending.floor-anchor.z)
    job.failed[job.pending.key]=wrongFloor and math.huge or now+4000
    job.pending=nil
  end
  if now<job.nextAt or player:isWalking() then return 'hold' end
  job.nextAt=now+200

  if changedFloor then
    local entrance=change and change.to.z==origin.z and change.to or nil
    local exit=selectExit(origin,anchor,entrance)
    if exit and now-job.progressAt<5000 then
      local sent,crossing=attemptExit(exit,origin)
      if sent and crossing then
        job.pending={key=key(exit.position),floor=origin.z,untilAt=now+1200}
      elseif not sent then job.failed[key(exit.position)]=now+4000 end
      if sent then return 'hold' end
    end
  else
    local limit=math.min(120,math.max(40,maxDistance+24))
    local dir=now-job.progressAt<5000 and approach(origin,anchor,limit,0,false)
    if dir and walkStep(dir) then return 'hold' end
  end
  if not job.reported then
    job.reported=true
    log('El punto de salida aún no es alcanzable. Se mantiene el waypoint pendiente.',key(anchor))
  end
  job.nextAt=now+1000
  -- Recheck as the visible map and occupancy change.
  if now-job.progressAt>=5000 then job.progressAt=now end
  return 'hold'
end
