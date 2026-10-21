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
  local tile=g_map.getTile(to)
  return tile~=nil and tile:isWalkable(false)==true and movement.floorSafe(to,tile)
end
function movement.withinBounds(from,to,boundary)
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

TargetBot.walkTo = function(_dest, _maxDist, _params)
  dest = _dest
  maxDist = _maxDist
  params = _params
end

-- called every 100ms if targeting or looting is active
TargetBot.walk = function()
  if movement.isManual() then dest=nil;return end
  if not dest then return end
  if player:isWalking() then return end
  local pos = player:getPosition()
  if pos.z ~= dest.z then return end
  local dist = math.max(math.abs(pos.x-dest.x), math.abs(pos.y-dest.y))
  if params.precision and params.precision >= dist then return end
  if params.marginMin and params.marginMax then
    if dist >= params.marginMin and dist <= params.marginMax then 
      return
    end
  end
  local path
  if params.preferCardinal then path=movement.findPath(pos,dest,maxDist,params)
  else path=getPath(pos,dest,maxDist,params) end
  if path and path[1] ~= nil then
    local direction = TargetBot.Antitrap.guardStep(pos, path[1])
    if params.avoidFloorChange and not movement.canStep(pos,direction) then return end
    if direction ~= nil then safeBotWalk(direction) end
  end
end
