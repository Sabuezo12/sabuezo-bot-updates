local dest
local maxDist
local params

-- Shared by distance keeping, face alignment, antitrap and spell preparation.
-- Check the live tile as well as minimap colour: a native path can accept its
-- destination even when that destination is a stair tile.
TargetBot.Movement = {}
local movement=TargetBot.Movement
local manualCheckedAt,manualUntil=nil,0
local pointerCheckedAt,pointerUntil=nil,0
local walkKeys={'Up','Right','Down','Left','Numpad8','Numpad9','Numpad6','Numpad3','Numpad2','Numpad1','Numpad4','Numpad7'}
local letterKeys={'W','D','S','A','E','Q','C','Z'}
-- Keyboard, native click-to-walk and manual BugMap own the next steps.
-- Native player:autoWalk has a destination; CaveBot's autoWalk(path) sends
-- g_game.autoWalk directly and does not create that native player destination.
function movement.isPointerManual(time)
  time=tonumber(time) or tonumber(now) or 0
  if pointerCheckedAt and time<pointerCheckedAt then pointerUntil=0 end
  pointerCheckedAt=time
  -- Read these live even in the same executor timestamp: a mouse callback
  -- may start movement after the first keyboard check of that frame.
  local mouseWalking=false
  if player and type(player.isAutoWalking)=='function' then
    local ok,on=pcall(player.isAutoWalking,player)
    mouseWalking=ok and on==true
  end
  local bugMapManual=false
  if BugMapMouse and type(BugMapMouse.isManualMovement)=='function' then
    local ok,on=pcall(BugMapMouse.isManualMovement)
    bugMapManual=ok and on==true
  end
  if mouseWalking or bugMapManual then
    pointerUntil=math.max(pointerUntil,time+250)
  end
  return time<pointerUntil
end
-- Do not infer manual intent from isWalking(): bot steps use it too. Cache
-- keyboard scanning per executor timestamp, keeping live pointer signals.
function movement.isManual(time,ignorePushMax)
  if not ignorePushMax and PushMax and PushMax.ownsMovement and PushMax.ownsMovement()then return true end
  time=tonumber(time) or tonumber(now) or 0
  local checked=manualCheckedAt==time
  if manualCheckedAt and time<manualCheckedAt then manualUntil=0 end
  manualCheckedAt=time
  if movement.isPointerManual(time) then return true end
  if checked then return time<manualUntil end
  local walking=modules and modules.game_walking
  local recent=walking and tonumber(walking.lastManualWalk)
  if recent and recent>0 and time>=recent and time-recent<500 then
    manualUntil=math.max(manualUntil,recent+500)
  end
  local function held(keys)
    if not g_keyboard or type(g_keyboard.isKeyPressed)~='function' then return false end
    for _,key in ipairs(keys)do
      local ok,pressed=pcall(g_keyboard.isKeyPressed,key)
      if ok and pressed then return true end
    end
    return false
  end
  if held(walkKeys) or walking and walking.wsadWalking==true and held(letterKeys) then
    manualUntil=math.max(manualUntil,time+250)
  end
  return time<manualUntil
end
local offsets={{0,-1},{1,0},{0,1},{-1,0},{1,-1},{1,1},{-1,1},{-1,-1}}
local damageFields={[105]=true,[118]=true,[2118]=true,[2119]=true,[2120]=true,[2121]=true,[2122]=true,
  [2123]=true,[2124]=true,[2125]=true,[2126]=true,[2131]=true,[2132]=true,[2133]=true,[2134]=true,[2135]=true}
local customFields,customFieldSource={},nil
local function itemFlag(item,name)
  if not item or type(item[name])~='function' then return nil end
  local ok,value=pcall(item[name],item)
  if ok and type(value)=='boolean' then return value end
end
function movement.isDamageField(item)
  if not item or type(item.getId)~='function' then return false end
  local id=item:getId();local push=storage and storage.pushmax or {}
  if id>=2127 and id<=2130 or id>=58242 and id<=58250 or id==tonumber(push.mwallBlockId) then return false end
  local source=tostring(push.destroyFieldIds or '')
  if source~=customFieldSource then
    customFieldSource=source;customFields={}
    for value in source:gmatch('%d+') do customFields[tonumber(value)]=true end
  end
  return damageFields[id]==true or customFields[id]==true or
    itemFlag(item,'isMagicField')==true and itemFlag(item,'isBlocking')==false
end

-- Some server data marks damage fields as non-walkable as well as
-- non-pathable. Only recognized damage fields may bypass that tile flag;
-- every other solid object and creature keeps blocking the square.
function movement.walkableTile(tile,ignoreCreatures)
  if not tile then return false end
  if tile:isWalkable(ignoreCreatures==true)==true then return true end
  local ground=tile.getGround and tile:getGround()
  if not ground or not tile.getItems then return false end
  if not ignoreCreatures then
    if tile.getCreatures then
      for _,actor in ipairs(tile:getCreatures() or {}) do if actor~=player then return false end end
    elseif tile.hasCreature and tile:hasCreature() then return false end
  end
  local function solid(item)
    local flag=itemFlag(item,'isNotWalkable')
    if flag~=nil then return flag end
    return itemFlag(item,'isBlocking')~=false
  end
  if solid(ground) then return false end
  local field=false
  for _,item in ipairs(tile:getItems() or {}) do
    if movement.isDamageField(item) then field=true
    elseif item~=ground and solid(item) then return false end
  end
  return field
end
function movement.floorSafe(p,tile)
  if not p or p.x<0 or p.x>65535 or p.y<0 or p.y>65535 or p.z<0 or p.z>15 then return false end
  tile=tile or g_map.getTile(p)
  if not tile then return false end
  if tile.getGround and not tile:getGround() then return false end
  if tile.hasElevation and tile:hasElevation(3) then return false end
  local liveColor=tonumber(tile.getMinimapColorByte and tile:getMinimapColorByte()) or 0
  local mapColor=tonumber(g_map.getMinimapColor and g_map.getMinimapColor(p)) or 0
  return not (liveColor>=210 and liveColor<=213) and not (mapColor>=210 and mapColor<=213)
end
function movement.destination(from,direction)
  local offset=offsets[(tonumber(direction) or -1)+1]
  if not from or not offset then return nil end
  return {x=from.x+offset[1],y=from.y+offset[2],z=from.z}
end
function movement.canStep(from,direction)
  local to=movement.destination(from,direction)
  if not to or to.x<0 or to.x>65535 or to.y<0 or to.y>65535 or to.z<0 or to.z>15 then return false end
  local explorer=CaveBot and CaveBot.AutoExplorer
  if explorer and explorer.canMoveTo and not explorer.canMoveTo(to,from) then return false end
  local tile=g_map.getTile(to)
  return movement.walkableTile(tile,false) and movement.floorSafe(to,tile)
end
function movement.withinBounds(from,to,boundary)
  local explorer=CaveBot and CaveBot.AutoExplorer
  if explorer and explorer.canMoveTo and not explorer.canMoveTo(to,from) then return false end
  if not boundary then return true end
  local centre,radius=boundary[1],tonumber(boundary[2]) or 0
  if not centre or from.z~=centre.z or to.z~=centre.z then return false end
  local before=math.max(math.abs(from.x-centre.x),math.abs(from.y-centre.y))
  local after=math.max(math.abs(to.x-centre.x),math.abs(to.y-centre.y))
  -- An external push/manual move may put us outside. Only a return is allowed.
  return after<=radius or before>radius and after<=before
end
function movement.pathSafe(from,path,boundary)
  for _,direction in ipairs(path or {}) do
    if not movement.canStep(from,direction) then return false end
    local to=movement.destination(from,direction)
    if not movement.withinBounds(from,to,boundary) then return false end
    from=to
  end
  return path~=nil
end

function movement.preferPath(path,previous)
  if not previous then return true end
  local diagonals,oldDiagonals=0,0
  for _,direction in ipairs(path) do if direction>=4 then diagonals=diagonals+1 end end
  for _,direction in ipairs(previous) do if direction>=4 then oldDiagonals=oldDiagonals+1 end end
  if diagonals~=oldDiagonals then return diagonals<oldDiagonals end
  return #path<#previous
end

-- Native ground costs can still prefer a diagonal, even with ignoreCost=false.
-- Search cardinal routes explicitly (at most 221 squares / ten steps), then
-- retain the native diagonal fallback only when no cardinal route is available.
function movement.findPath(from,to,maxDistance,options)
  options=options or {}
  if not from or not to or from.z~=to.z then return nil end
  local limit=math.max(1,math.min(10,tonumber(maxDistance) or 10))
  local boundary=options.maxDistanceFrom
  local function goal(p)
    local d=math.max(math.abs(p.x-to.x),math.abs(p.y-to.y))
    if options.marginMin and options.marginMax then return d>=options.marginMin and d<=options.marginMax end
    return d<=(tonumber(options.precision) or 0)
  end
  local function id(p) return p.x..':'..p.y end
  local queue,head={{pos=from,depth=0}},1
  local seen,cache={[id(from)]=true},{}
  while head<=#queue do
    local node=queue[head];head=head+1
    if goal(node.pos) then
      local reverse,path={},{}
      while node.previous do reverse[#reverse+1]=node.direction;node=node.previous end
      for i=#reverse,1,-1 do path[#path+1]=reverse[i] end
      return path
    end
    if node.depth<limit then
      for direction=0,3 do
        local p=movement.destination(node.pos,direction)
        local name=id(p)
        if not seen[name] and movement.withinBounds(node.pos,p,boundary) then
          if cache[name]==nil then cache[name]=movement.canStep(node.pos,direction) end
          if cache[name] then
            seen[name]=true
            queue[#queue+1]={pos=p,depth=node.depth+1,direction=direction,previous=node}
          end
        end
      end
    end
  end
  local nativeOptions={}
  for name,value in pairs(options) do nativeOptions[name]=value end
  local path=getPath(from,to,limit,nativeOptions)
  if movement.pathSafe(from,path,boundary) then return path end
  return nil
end

-- Bounded visible-tile fallback for clients whose native finder still rejects
-- fields. Share the physical map for this executor timestamp and flag set.
local fieldMaps,fieldMapTime={},nil
function movement.fieldPath(from,to,maxDistance,options)
  options=options or {}
  if not from or not to or from.z~=to.z then return nil end
  local limit=math.max(1,math.min(10,tonumber(maxDistance) or 10))
  if fieldMapTime~=now then fieldMaps={};fieldMapTime=now end
  local boundary=options.maxDistanceFrom
  local name=from.x..':'..from.y..':'..from.z..':'..limit..':'..tostring(options.ignoreCreatures==true or options.ignoreCreatures==1)
  if boundary then name=name..':'..boundary[1].x..':'..boundary[1].y..':'..tostring(boundary[2]) end
  local ctx=fieldMaps[name]
  local function key(p)return p.x..':'..p.y end
  if not ctx then
    local start={pos={x=from.x,y=from.y,z=from.z},depth=0}
    ctx={nodes={[key(from)]=start},queue={start},head=1,free={}}
    fieldMaps[name]=ctx
    local function free(p)
      local id=key(p)
      if ctx.free[id]==nil then
        local tile=g_map.getTile(p)
        ctx.free[id]=movement.walkableTile(tile,options.ignoreCreatures==true or options.ignoreCreatures==1) and movement.floorSafe(p,tile)
      end
      return ctx.free[id]
    end
    while ctx.queue[ctx.head] and #ctx.queue<512 do
      local node=ctx.queue[ctx.head];ctx.head=ctx.head+1
      if node.depth<limit then
        for direction,offset in ipairs(offsets) do
          local pos={x=node.pos.x+offset[1],y=node.pos.y+offset[2],z=from.z}
          local id=key(pos)
          local allowed=not ctx.nodes[id] and movement.withinBounds(node.pos,pos,boundary) and free(pos)
          if allowed and direction>4 then
            local a={x=pos.x,y=node.pos.y,z=from.z};local b={x=node.pos.x,y=pos.y,z=from.z}
            allowed=movement.withinBounds(node.pos,a,boundary) and movement.withinBounds(node.pos,b,boundary) and free(a) and free(b)
          end
          if allowed then
            local nextNode={pos=pos,depth=node.depth+1,previous=node,direction=direction-1}
            ctx.nodes[id]=nextNode;ctx.queue[#ctx.queue+1]=nextNode
          end
        end
      end
    end
  end
  local best
  for _,node in ipairs(ctx.queue) do
    local distance=math.max(math.abs(node.pos.x-to.x),math.abs(node.pos.y-to.y))
    local goal
    if options.marginMin and options.marginMax then goal=distance>=options.marginMin and distance<=options.marginMax
    else goal=distance<=(tonumber(options.precision) or 0) end
    if goal and (not best or node.depth<best.depth) then best=node end
  end
  if not best then return nil end
  local path={}
  while best.previous do table.insert(path,1,best.direction);best=best.previous end
  return path
end

-- Selection still runs at 100ms; only an explicit classic chase request uses
-- this 20ms walker. Its short native packets retain server walking cadence.
local follow={pending=nil,chain=nil,nextAt=0,retryAt=0,requestedAt=0,taken=false}
local function followPoint(p)return{x=p.x,y=p.y,z=p.z}end
local function followSame(a,b)return a and b and a.x==b.x and a.y==b.y and a.z==b.z end
local function cancelFollow()
  local pending=follow.pending
  follow.pending,follow.chain,follow.taken=nil,nil,false
  if pending and pending.native and pending.active and not movement.isPointerManual() and
      g_game and type(g_game.stop)=='function' then pcall(g_game.stop) end
end

local function observeFollow(pos)
  local pending=follow.pending
  if not pending then return end
  for index=pending.confirmed+1,#pending.positions do
    if followSame(pos,pending.positions[index]) then
      pending.confirmed=index
      if index==#pending.positions then
        follow.pending=nil
        if pending.native then follow.chain={pos=followPoint(pos),untilAt=now+500};follow.nextAt=now end
      end
      return
    end
  end
  local previous=pending.confirmed>0 and pending.positions[pending.confirmed] or pending.from
  if not followSame(pos,previous) then cancelFollow() end
end

local function followStep(from,direction)
  local to=movement.destination(from,direction)
  if not to or not movement.canStep(from,direction) then return nil end
  if direction>=4 then
    local horizontal=to.x>from.x and 1 or 3
    local vertical=to.y>from.y and 2 or 0
    if not movement.canStep(from,horizontal) or not movement.canStep(from,vertical) then return nil end
  end
  return to
end

local function followTick()
  if not dest or not params or not params.followFast then cancelFollow();if not dest then params=nil end;return end
  local safety=TargetBot.Antitrap
  if not player or movement.isManual() or
      TargetBot.isOn and not TargetBot.isOn() or
      TargetBot.canFollowNow and not TargetBot.canFollowNow() or now-follow.requestedAt>250 or
      HelperPause and HelperPause.isPaused() or
      CaveBot and CaveBot.Flee and CaveBot.Flee.blocksCombat() or
      safety and safety.ownsMovement and safety.ownsMovement() or
      AttackBot and AttackBot.isSpellMovementCommitted and AttackBot.isSpellMovementCommitted() or
      type(isInPz)=='function' and isInPz() then cancelFollow();dest,params=nil,nil;return end
  local explorer=CaveBot and CaveBot.AutoExplorer
  if AttackBot and AttackBot.isOn and AttackBot.isOn() and CaveBot and CaveBot.isOff and CaveBot.isOff() and
      not (explorer and explorer.isOn and explorer.isOn()) then cancelFollow();dest,params=nil,nil;return end
  local creature=params.followCreature
  local hp=creature and tonumber(creature:getHealthPercent())
  if not hp or hp<=0 or
      g_game.getAttackingCreature and g_game.getAttackingCreature()~=creature then cancelFollow();dest,params=nil,nil;return end
  local pos,target=player:getPosition(),creature:getPosition()
  if not pos or not target or pos.z~=target.z then cancelFollow();dest,params=nil,nil;return end
  dest=followPoint(target)
  observeFollow(pos)
  local distance=math.max(math.abs(pos.x-target.x),math.abs(pos.y-target.y))
  local precision=tonumber(params.precision) or 1
  if distance<=precision then cancelFollow();return end
  local pending=follow.pending
  if pending then
    if now>=pending.deadline then
      cancelFollow();follow.retryAt=now+1000;follow.nextAt=now+100;return
    end
    local from=pos
    for index=pending.confirmed+1,#pending.positions do
      local to=followStep(from,pending.directions[index])
      local guarded=not safety or not safety.canRouteStep or safety.canRouteStep(from,pending.directions[index])
      if not to or not followSame(to,pending.positions[index]) or not guarded then cancelFollow();return end
      from=to
    end
    -- Replan a short packet if the target changes direction substantially.
    if math.max(math.abs(target.x-pending.target.x),math.abs(target.y-pending.target.y))>=2 then cancelFollow() end
    return
  end
  if now<follow.nextAt then return end
  if explorer and explorer.yieldNativeMovement then explorer.yieldNativeMovement(100) end
  if not follow.taken then
    follow.taken=true
    if CaveBot and CaveBot.resetWalking then CaveBot.resetWalking() end
    if player:isWalking() then
      if g_game and type(g_game.stop)=='function' then pcall(g_game.stop) end
      return
    end
  end
  local native=type(autoWalk)=='function' and autoWalk or g_game and type(g_game.autoWalk)=='function' and g_game.autoWalk
  local chain=native and g_game and type(g_game.stop)=='function' and now>=follow.retryAt and
    follow.chain and now<=follow.chain.untilAt and followSame(pos,follow.chain.pos)
  if player:isWalking() and not chain then return end
  if player.canWalk then
    local ok,ready=pcall(player.canWalk,player)
    if ok and ready==false and not chain then return end
  end
  local options={ignoreNonPathable=true,ignoreFields=true,ignoreCreatures=false,ignoreStairs=false,
    precision=precision,allowOnlyVisibleTiles=true,allowUnseen=false}
  local path=getPath(pos,target,maxDist or 10,options)
  if not path then path=movement.fieldPath(pos,target,maxDist or 10,options) end
  if not path or not path[1] then follow.nextAt=now+100;return end
  local direction=path[1]
  local guarded=direction
  if safety and safety.guardStep then guarded=safety.guardStep(pos,direction) end
  if guarded~=direction then cancelFollow();return end
  if not followStep(pos,direction) then follow.nextAt=now+100;return end
  local protected=safety and safety.protecting and safety.protecting()
  local useNative=native and g_game and type(g_game.stop)=='function' and now>=follow.retryAt and
    (not protected or safety.canRouteStep)
  local directions,positions,from,duration={},{},pos,0
  for index=1,math.min(#path,useNative and 3 or 1) do
    local step=followStep(from,path[index])
    if not step or followSame(step,target) or safety and safety.canRouteStep and not safety.canRouteStep(from,path[index]) then break end
    directions[#directions+1]=path[index];positions[#positions+1]=step
    local ms=player.getStepDuration and tonumber(player:getStepDuration(false,path[index])) or 150
    duration=duration+math.max(20,ms or 150);from=step
    if math.max(math.abs(step.x-target.x),math.abs(step.y-target.y))<=precision then break end
  end
  if #directions==0 then follow.nextAt=now+100;return end
  pending={native=useNative and true or false,active=false,confirmed=0,positions=positions,directions=directions,
    from=followPoint(pos),target=followPoint(target),deadline=now+math.max(1000,duration*3+500)}
  follow.pending=pending
  local ok,sent
  if useNative then ok,sent=pcall(native,directions) else ok,sent=pcall(safeBotWalk,direction) end
  if ok and sent~=false or pending.confirmed>0 then
    pending.active=true;follow.chain=nil
    if not useNative then follow.nextAt=now+duration end
  else
    follow.pending=nil
    if useNative then follow.retryAt=now+1000 end
    follow.nextAt=now+20
  end
end

onPlayerPositionChange(function(pos)
  if pos and follow.pending then observeFollow(pos) end
end)
macro(20,function()if follow.pending or params and params.followFast then followTick() end end)

TargetBot.walkTo = function(_dest, _maxDist, _params)
  local refresh=not _dest and _params and _params.refresh
  if refresh then dest=nil;return end
  if not refresh and (not _dest or not _params or not _params.followFast or
      params and params.followCreature~=_params.followCreature) then cancelFollow() end
  dest = _dest
  maxDist = _maxDist
  params = _params
  if _dest and _params and _params.followFast then follow.requestedAt=now end
end

-- called every 100ms if targeting or looting is active
TargetBot.walk = function()
  if params and params.followFast then followTick();return end
  if movement.isManual() then dest=nil;return end
  if not dest then return end
  local pos = player:getPosition()
  if pos.z ~= dest.z then return end
  local dist = math.max(math.abs(pos.x-dest.x), math.abs(pos.y-dest.y))
  if params.precision and params.precision >= dist then return end
  if params.marginMin and params.marginMax then
    if dist >= params.marginMin and dist <= params.marginMax then 
      return
    end
  end
  local explorer=CaveBot and CaveBot.AutoExplorer
  if explorer and explorer.yieldNativeMovement then explorer.yieldNativeMovement(100) end
  if player:isWalking() then return end
  local path
  if params.preferCardinal then path=movement.findPath(pos,dest,maxDist,params)
  else path=getPath(pos,dest,maxDist,params) end
  if not path then path=movement.fieldPath(pos,dest,maxDist,params) end
  if path and path[1] ~= nil then
    local direction = TargetBot.Antitrap.guardStep(pos, path[1])
    local explorer=CaveBot and CaveBot.AutoExplorer
    if direction~=nil and explorer and explorer.canMoveTo and
      not explorer.canMoveTo(movement.destination(pos,direction),pos) then return end
    if params.avoidFloorChange and not movement.canStep(pos,direction) then return end
    if direction ~= nil then safeBotWalk(direction) end
  end
end
