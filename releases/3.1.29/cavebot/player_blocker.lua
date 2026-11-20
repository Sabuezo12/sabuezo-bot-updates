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
  if state.pending then
    if now<state.pending.untilAt then CaveBot.delay(100);return true end
    state.failed[key(state.pending.destination)]=now+3000
    state.pending=nil
  end
  if now<state.nextAt or player:isWalking()then CaveBot.delay(100);return true end
  if distance(origin,position)>1 then
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
  if not choice then state.nextAt=now+500;CaveBot.delay(250);return true end
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
function B.reset()state=nil end
function B.isActive()return state~=nil end
function B.tick(row)
  if not state then return false end
  if state.row~=row or row.action~='goto'then B.reset();return false end
  return service()
end
function B.tryClear(actor,goal,path)
  local row=currentRow()
  local origin=player:getPosition()
  local position=livingPlayer(actor)and actor:getPosition()
  if not row or row.action~='goto'or not goal or not position or position.z~=origin.z then return false end
  if not state or state.row~=row or state.creature~=actor or not same(state.from,position)then
    state={row=row,creature=actor,from=copy(position),goal=copy(goal),route=routeTiles(origin,path),failed={},nextAt=0}
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
  for _,actor in ipairs(tile:getCreatures()or{})do
    if livingPlayer(actor)then return B.tryClear(actor,goal,remaining)end
  end
  return false
end
