-- Geometry/planning shared by the emergency exit, never by ordinary hunting.
-- Native minimap searches cover known ground; live tiles authorize each action.
CaveBot.FleeTools = {}
local T=CaveBot.FleeTools
T.offsets={{0,-1},{1,0},{0,1},{-1,0},{1,-1},{1,1},{-1,1},{-1,-1}}
local fields={[105]=true,[118]=true,[2118]=true,[2119]=true,[2120]=true,[2121]=true,[2122]=true,[2123]=true,
  [2124]=true,[2125]=true,[2126]=true,[2131]=true,[2132]=true,[2133]=true,[2134]=true,[2135]=true}
local walls={[2127]=true,[2128]=true,[2129]=true,[2130]=true}
local coins={[3031]=true,[3035]=true,[3043]=true}
local customFields,customSource={},nil
function T.copy(p) return p and {x=p.x,y=p.y,z=p.z} end
function T.key(p) return p.x..':'..p.y..':'..p.z end
function T.same(a,b) return a and b and a.x==b.x and a.y==b.y and a.z==b.z end
function T.distance(a,b)
  if not a or not b or a.z~=b.z then return math.huge end
  return math.max(math.abs(a.x-b.x),math.abs(a.y-b.y))
end
function T.step(p,dir)
  local o=T.offsets[(tonumber(dir) or -1)+1]
  return o and {x=p.x+o[1],y=p.y+o[2],z=p.z}
end
function T.position(value)
  local x,y,z=tostring(value or ''):match('^%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)')
  x,y,z=tonumber(x),tonumber(y),tonumber(z)
  if not z or x>65535 or y>65535 or z>15 then return nil end
  return {x=x,y=y,z=z}
end
function T.tile(p)
  local tile=p and g_map.getTile(p)
  if not tile then return nil end
  local m=TargetBot and TargetBot.Movement
  local out={tile=tile,pos=T.copy(p),safe=m and m.floorSafe(p,tile)==true,trash={},creatures={},hard=false,
    walkable=tile:isWalkable(false)==true,shootable=not tile.canShoot or tile:canShoot()~=false}
  local ground=tile.getGround and tile:getGround()
  local push=storage.pushmax or {}
  local text=tostring(push.destroyFieldIds or '')
  if text~=customSource then
    customFields={};customSource=text
    for id in text:gmatch('%d+')do customFields[tonumber(id)]=true end
  end
  for _,item in ipairs(tile:getItems() or {})do
    local id=item:getId()
    if walls[id] or id==tonumber(push.mwallBlockId) or id>=58242 and id<=58250 then out.hard=true
    elseif fields[id] or customFields[id] or item.isMagicField and item:isMagicField() then out.field=item
    elseif item~=ground and not (item.isGround and item:isGround()) and not (item.isGroundBorder and item:isGroundBorder()) then
      if coins[id] or item.isNotMoveable and not item:isNotMoveable() then out.trash[#out.trash+1]=item
      elseif item.isBlocking and item:isBlocking() then out.hard=true end
    end
  end
  for _,actor in ipairs(tile:getCreatures() or {})do
    if actor~=player then
      out.creatures[#out.creatures+1]=actor
      if not actor:isPlayer() and not (actor.isMonster and actor:isMonster()) then out.hard=true end
    end
  end
  if not out.walkable and not out.field and #out.trash==0 and #out.creatures==0 then out.hard=true end
  return out
end
function T.free(t)
  return t and t.safe and t.walkable and not t.hard and not t.field and #t.creatures==0
end
local function allowed(t,relaxed)
  return t and t.safe and not t.hard and (relaxed or T.free(t))
end
-- The loaded screen is small; cap every local search. Never scan an entire map.
function T.localPath(from,to,relaxed,precision)
  if T.distance(from,to)>12 then return nil end
  local open,best={{pos=T.copy(from),cost=0}},{[T.key(from)]=0}
  local cache={}
  local function tileAt(p)
    local k=T.key(p)
    if cache[k]==nil then cache[k]=T.tile(p) or false end
    return cache[k] or nil
  end
  for _=1,320 do
    if #open==0 then return nil end
    local index=1
    for i=2,#open do if open[i].cost<open[index].cost then index=i end end
    local node=table.remove(open,index)
    if node.cost==best[T.key(node.pos)] then
      if T.distance(node.pos,to)<=(precision or 0) then
        local reverse,path={},{}
        while node.parent do reverse[#reverse+1]=node.dir;node=node.parent end
        for i=#reverse,1,-1 do path[#path+1]=reverse[i] end
        return path
      end
      for dir=0,7 do
        local p=T.step(node.pos,dir)
        local t=T.distance(from,p)<=12 and tileAt(p) or nil
        local pass=allowed(t,relaxed)
        if pass and dir>=4 then
          pass=allowed(tileAt({x=p.x,y=node.pos.y,z=p.z}),relaxed) or allowed(tileAt({x=node.pos.x,y=p.y,z=p.z}),relaxed)
        end
        if pass then
          local cost=node.cost+1+(dir>=4 and 0.01 or 0)+(relaxed and ((t.field and 10 or 0)+(#t.trash>0 and 8 or 0)+(#t.creatures>0 and 12 or 0)) or 0)
          local k=T.key(p)
          if not best[k] or cost<best[k] then
            best[k]=cost;open[#open+1]={pos=p,cost=cost,parent=node,dir=dir}
          end
        end
      end
    end
  end
end
function T.path(from,to,relaxed,maxDist,precision)
  if not from or not to or from.z~=to.z then return nil end
  if T.same(from,to) then return {} end
  local finder=relaxed and findPath or getPath or findPath
  local path=finder(from,to,math.min(192,tonumber(maxDist) or 192),{precision=precision or 0,
    ignoreCreatures=relaxed==true,ignoreNonPathable=relaxed==true,ignoreNonWalkable=false,
    ignoreCost=true,ignoreStairs=true,allowUnseen=true,allowOnlyVisibleTiles=false})
  if path then
    local cursor=T.copy(from)
    for _,dir in ipairs(path)do
      cursor=T.step(cursor,dir)
      if not cursor then return nil end
      local t=T.tile(cursor)
      -- Unknown map tiles may inform a route, but are never action targets.
      if t and not allowed(t,relaxed) then path=nil;break end
    end
    if path and T.distance(cursor,to)<=(precision or 0) then return path end
  end
  return T.localPath(from,to,relaxed,precision)
end
local skipped={label=true,delay=true,waitstamina=true,lure=true,standlure=true,follow=true,setprofile=true,gotolabel=true}
local transitions={floorchange=true,use=true,usewith=true,opendoors=true,say=true,npcsay=true,travel=true,poscheck=true,stepdirection=true}
local tools={[3003]=true,[3457]=true,[3308]=true,[9596]=true,[9598]=true,[9594]=true}
local movementWords={['exani hur up']=true,['exani hur down']=true,['exani tera']=true,
  ['utani hur']=true,['utani gran hur']=true,['utani tempo hur']=true,['utamo tempo san']=true}
local function validTransition(row)
  if row.action=='usewith' then return tools[tonumber(tostring(row.value):match('^%s*(%d+)'))]==true end
  if row.action=='say' then return movementWords[tostring(row.value):lower():gsub('"',''):gsub('^%s*(.-)%s*$','%1')]==true end
  return true
end
local function point(row)
  if row.action=='goto' then
    if not tostring(row.value):match('^%s*%d+%s*,%s*%d+%s*,%s*%d+%s*,?%s*%d*%s*$') then return nil end
    return T.position(row.value)
  end
  if row.action=='floorchange' or row.action=='use' then return T.position(row.value) end
  if row.action=='usewith' then return T.position(tostring(row.value):match('^%s*%d+%s*,(.*)$')) end
  if row.action=='supplycheck' then return T.position(tostring(row.value):match('^[^,]*,(.*)$')) end
end
-- Compare actual minimap paths to every same-floor check, including checks
-- behind the current route index. For another floor, compare approaches to
-- recorded anchors plus their remaining recorded distance/transitions.
function T.plan(rows,index,origin)
  local plan={direct={},anchors={},cursor=1,stage='direct',best=nil,rows=rows,origin=T.copy(origin)}
  local remaining,last,checkpoint=0,nil,nil
  -- Two reverse passes cover a cyclic route in linear time. No per-waypoint
  -- walk around the entire route, including routes containing thousands of rows.
  for cursor=#rows*2,1,-1 do
    local i=(cursor-1)%#rows+1
    local row=rows[i]
    local goal=point(row)
    if row.action=='supplycheck' then
      checkpoint=row;remaining=0;last=goal
      if cursor<=#rows and goal and goal.z==origin.z then
        plan.direct[#plan.direct+1]={goal=goal,row=row,checkpoint=row,remaining=0,lower=T.distance(origin,goal),order=(i-index+#rows)%#rows}
      end
    elseif row.action=='goto' or transitions[row.action] then
      if not validTransition(row) then checkpoint=nil;remaining=0;last=nil end
      if checkpoint then
        if goal and last then remaining=remaining+(goal.z==last.z and T.distance(goal,last) or 4) end
        if transitions[row.action] then remaining=remaining+4 end
        if goal then last=goal end
        if cursor<=#rows and goal and goal.z==origin.z and T.distance(origin,goal)<=192 then
          plan.anchors[#plan.anchors+1]={goal=goal,row=row,checkpoint=checkpoint,remaining=remaining,
            lower=T.distance(origin,goal)+remaining,order=(i-index+#rows)%#rows}
        end
      end
    elseif not skipped[row.action] then checkpoint=nil;remaining=0;last=nil
    end
  end
  local function order(a,b)
    if a.lower~=b.lower then return a.lower<b.lower end
    return a.order<b.order
  end
  table.sort(plan.direct,order);table.sort(plan.anchors,order)
  return plan
end
function T.advancePlan(plan,origin,budget)
  if plan.done then return plan.best end
  local queries=0
  while queries<(budget or 1) and not plan.done do
    local list=plan.stage=='direct' and plan.direct or plan.anchors
    local candidate=list[plan.cursor]
    if not candidate then
      if plan.stage=='direct' then plan.stage='anchors';plan.cursor=1
      else plan.done=true;return plan.best end
    else
      if plan.best and candidate.lower>=plan.best.cost then plan.cursor=#list+1
      else
        plan.cursor=plan.cursor+1;queries=queries+1
        local path=T.path(origin,candidate.goal,false)
        if not path then path=T.path(origin,candidate.goal,true) end
        if path then
          local cost=#path+candidate.remaining
          if not plan.best or cost<plan.best.cost then
            plan.best={goal=T.copy(candidate.goal),row=candidate.row,checkpoint=candidate.checkpoint,cost=cost,direct=plan.stage=='direct'}
          end
        end
      end
    end
  end
  return plan.best
end
