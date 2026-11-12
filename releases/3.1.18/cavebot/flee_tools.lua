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
local function flag(item,name)
  if type(item[name])~='function'then return false end
  local ok,value=pcall(item[name],item);return ok and value==true
end
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
-- Optional fourth field is rest minutes, never a coordinate/precision.
function T.zoneConfig(value)
  local text=tostring(value or '')
  local x,y,z,minutes=text:match('^%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*$')
  if not x then x,y,z=text:match('^%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*$');minutes='0'end
  if not x then return nil end
  local p=T.position(x..','..y..','..z);minutes=tonumber(minutes)
  if not p or p.x>=65535 or not minutes or minutes>10080 then return nil end
  return {pos=p,minutes=minutes}
end
function T.zonePosition(value)
  local config=T.zoneConfig(value);return config and config.pos or nil
end
function T.zoneValue(p,minutes)
  minutes=tonumber(minutes)
  if not p or not minutes or minutes<0 or minutes>10080 or minutes~=math.floor(minutes)then return nil end
  local value=p.x..','..p.y..','..p.z..(minutes>0 and ','..minutes or '')
  return T.zoneConfig(value)and value or nil
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
    elseif fields[id] or customFields[id] or flag(item,'isMagicField')then out.field=item
    elseif item~=ground and not flag(item,'isGround')and not flag(item,'isGroundBorder')then
      local movable=false
      if type(item.isNotMoveable)=='function'then local ok,no=pcall(item.isNotMoveable,item);movable=ok and no==false end
      if coins[id]or movable then out.trash[#out.trash+1]=item
      elseif flag(item,'isBlocking')then out.hard=true end
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
  -- Fire/poison/energy are ground to cross during an emergency, never a
  -- reason to spend a cleanup rune. Walls and static blockers remain hard.
  return t and t.safe and (t.walkable or t.field~=nil) and not t.hard and #t.creatures==0
end
local function allowed(t,relaxed)
  return T.free(t) or relaxed and t and t.safe and not t.hard and #t.creatures>0
end
-- Compare movement time, not just the number of SQM. Keep a small cardinal
-- preference when a client reports identical durations for every direction.
function T.stepCosts()
  local durations,base={},nil
  for dir=0,7 do
    if player and type(player.getStepDuration)=='function'then
      local ok,n=pcall(player.getStepDuration,player,false,dir)
      n=tonumber(n)
      if ok and n and n>0 then durations[dir+1]=n end
    end
    if dir<4 and durations[dir+1]then base=math.min(base or math.huge,durations[dir+1])end
  end
  local costs={}
  for dir=0,7 do
    costs[dir+1]=math.max(dir>=4 and 1.01 or 1,
      base and durations[dir+1]and durations[dir+1]/base or (dir>=4 and 3 or 1))
  end
  return costs
end
function T.pathCost(path,costs)
  costs=costs or T.stepCosts()
  local cost,diagonals,turns,previous=0,0,0,nil
  for _,dir in ipairs(path or {})do
    if not costs[dir+1]then return math.huge,math.huge,math.huge end
    cost=cost+costs[dir+1]
    if dir>=4 then diagonals=diagonals+1 end
    if previous and previous~=dir then turns=turns+1 end
    previous=dir
  end
  return cost,diagonals,turns
end
-- The loaded screen is small; cap every local search. Never scan an entire map.
local function searchPath(from,to,relaxed,precision,options)
  options=options or{}
  if not options.partial and T.distance(from,to)>12 then return nil end
  local costs=options.costs or T.stepCosts()
  local diagonal=math.min(2,costs[5],costs[6],costs[7],costs[8])
  local function heuristic(p)
    local dx=math.max(0,math.abs(p.x-to.x)-(precision or 0))
    local dy=math.max(0,math.abs(p.y-to.y)-(precision or 0))
    return math.max(dx,dy)+math.min(dx,dy)*(diagonal-1)
  end
  local open,best={{pos=T.copy(from),cost=0,estimate=heuristic(from),diagonals=0}},
    {[T.key(from)]={cost=0,diagonals=0}}
  local cache={}
  local approach,nearest=nil,T.distance(from,to)
  local function result(node)
    local reverse,path={},{}
    while node.parent do reverse[#reverse+1]=node.dir;node=node.parent end
    for i=#reverse,1,-1 do path[#path+1]=reverse[i]end
    return path
  end
  local function tileAt(p)
    local k=T.key(p)
    if cache[k]==nil then cache[k]=T.tile(p) or false end
    return cache[k] or nil
  end
  for _=1,320 do
    if #open==0 then break end
    local index=1
    for i=2,#open do
      if open[i].estimate<open[index].estimate or open[i].estimate==open[index].estimate and
        (open[i].diagonals<open[index].diagonals or open[i].diagonals==open[index].diagonals and open[i].cost>open[index].cost)then index=i end
    end
    local node=table.remove(open,index)
    local known=best[T.key(node.pos)]
    if node.cost==known.cost and node.diagonals==known.diagonals then
      if T.distance(node.pos,to)<=(precision or 0) then
        return result(node)
      end
      local remaining=T.distance(node.pos,to)
      if options.partial and (remaining<nearest or remaining==nearest and approach and
        (node.cost<approach.cost or node.cost==approach.cost and node.diagonals<approach.diagonals))then
        nearest=remaining;approach=node
      end
      for dir=0,options.cardinalOnly and 3 or 7 do
        local p=T.step(node.pos,dir)
        local t=T.distance(from,p)<=(options.partial and 6 or 12)and tileAt(p)or nil
        local pass=allowed(t,relaxed)and not(options.avoid and options.avoid[T.key(p)])
        if pass and dir>=4 then
          pass=allowed(tileAt({x=p.x,y=node.pos.y,z=p.z}),relaxed) or allowed(tileAt({x=node.pos.x,y=p.y,z=p.z}),relaxed)
        end
        if pass then
          local cost=node.cost+costs[dir+1]+(relaxed and #t.creatures>0 and 12 or 0)
          local diagonals=node.diagonals+(dir>=4 and 1 or 0)
          local k=T.key(p)
          if not best[k] or cost<best[k].cost or cost==best[k].cost and diagonals<best[k].diagonals then
            best[k]={cost=cost,diagonals=diagonals}
            open[#open+1]={pos=p,cost=cost,estimate=cost+heuristic(p),diagonals=diagonals,parent=node,dir=dir}
          end
        end
      end
    end
  end
  if approach then return result(approach)end
end
function T.localPath(from,to,relaxed,precision,options)
  local cardinal={}
  for key,value in pairs(options or{})do cardinal[key]=value end
  cardinal.cardinalOnly=true
  local path=searchPath(from,to,relaxed,precision,cardinal)
  if path or options and options.cardinalOnly then return path end
  -- Diagonal search is a fallback after the loaded cardinal search fails.
  cardinal.cardinalOnly=false
  return searchPath(from,to,relaxed,precision,cardinal)
end
-- Repair only a short, fully visible prefix. Distant native/minimap route and
-- recorded transitions stay intact; this never authorizes an unseen step.
function T.refinePath(from,path,relaxed,avoid)
  if not path or not path[1]then return path end
  local cursor,prefix,need=T.copy(from),{},false
  for i=1,math.min(6,#path)do
    local p=T.step(cursor,path[i])
    local tile=p and T.tile(p)
    if not allowed(tile,relaxed)then break end
    cursor=p;prefix[#prefix+1]=path[i]
    if path[i]>=4 or avoid and avoid[T.key(p)]then need=true end
  end
  if not need or #prefix==0 then return path end
  local costs=T.stepCosts()
  local replacement=T.localPath(from,cursor,relaxed,0,{avoid=avoid,costs=costs})
  if not replacement then
    if avoid and avoid[T.key(T.step(from,path[1]))]then return nil end
    return path
  end
  local a,ad,at=T.pathCost(replacement,costs)
  local b,bd,bt=T.pathCost(prefix,costs)
  -- A shorter-looking path through more monsters is not a free shortcut.
  local function blockers(start,route)
    local penalty,p=0,T.copy(start)
    for _,dir in ipairs(route)do p=T.step(p,dir);local t=T.tile(p);penalty=penalty+(t and #t.creatures>0 and 12 or 0)end
    return penalty
  end
  if relaxed then a=a+blockers(from,replacement);b=b+blockers(from,prefix)end
  local rejected=false
  if avoid then
    local p=T.copy(from)
    for _,dir in ipairs(prefix)do p=T.step(p,dir);if avoid[T.key(p)]then rejected=true;break end end
  end
  if not rejected and not(ad<bd or ad==bd and(a<b-0.0001 or math.abs(a-b)<0.0001 and at<bt))then return path end
  local result={}
  for _,dir in ipairs(replacement)do result[#result+1]=dir end
  for i=#prefix+1,#path do result[#result+1]=path[i]end
  return result
end
-- Final check also covers a native prefix the local search could not finish.
-- Split a diagonal into its two cardinal components whenever that exact
-- intermediate tile is safe. Recorded floor entries remain exact.
function T.cardinalFirst(from,path,goal,avoid)
  if not path or not path[1]or path[1]<4 then return path end
  local dest=T.step(from,path[1])
  if not T.free(T.tile(dest))or avoid and avoid[T.key(dest)]then return path end
  local dx,dy=dest.x-from.x,dest.y-from.y
  local horizontal=dx>0 and 1 or 3
  local vertical=dy>0 and 2 or 0
  local choices={}
  for _,pair in ipairs({{horizontal,vertical},{vertical,horizontal}})do
    local middle=T.step(from,pair[1])
    if T.free(T.tile(middle))and not(avoid and avoid[T.key(middle)])then
      choices[#choices+1]={first=pair[1],second=pair[2],distance=T.distance(middle,goal or dest)}
    end
  end
  table.sort(choices,function(a,b)if a.distance~=b.distance then return a.distance<b.distance end;return a.first<b.first end)
  if not choices[1]then return path end
  local result={choices[1].first,choices[1].second}
  for i=2,#path do result[#result+1]=path[i]end
  return result
end
function T.path(from,to,relaxed,maxDist,precision,avoid)
  if not from or not to or from.z~=to.z then return nil end
  if T.same(from,to) then return {} end
  local finder=relaxed and findPath or getPath or findPath
  local params={precision=precision or 0,ignoreCreatures=relaxed==true,
    ignoreNonPathable=true,ignoreNonWalkable=false,
    ignoreCost=true,ignoreStairs=true,allowUnseen=true,allowOnlyVisibleTiles=false}
  local limit=math.min(192,tonumber(maxDist) or 192)
  local path=finder(from,to,limit,params)
  if path then
    local cursor=T.copy(from)
    for _,dir in ipairs(path)do
      cursor=T.step(cursor,dir)
      if not cursor then return nil end
      local t=T.tile(cursor)
      -- Unknown map tiles may inform a route, but are never action targets.
      if t and not allowed(t,relaxed) then path=nil;break end
    end
    if path and T.distance(cursor,to)<=(precision or 0) then return T.refinePath(from,path,relaxed,avoid) end
  end
  return T.localPath(from,to,relaxed,precision,{avoid=avoid})
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
  if row.action=='zonapz'then return T.zonePosition(row.value)end
  if row.action=='supplycheck' then return T.position(tostring(row.value):match('^[^,]*,(.*)$')) end
end
-- Compare actual minimap paths to every same-floor check, including checks
-- behind the current route index. For another floor, compare approaches to
-- recorded anchors plus their remaining recorded distance/transitions.
function T.plan(rows,index,origin,checkpointAction)
  checkpointAction=checkpointAction or 'supplycheck'
  local plan={direct={},anchors={},cursor=1,stage='direct',best=nil,rows=rows,origin=T.copy(origin)}
  local remaining,last,checkpoint=0,nil,nil
  -- Two reverse passes cover a cyclic route in linear time. No per-waypoint
  -- walk around the entire route, including routes containing thousands of rows.
  for cursor=#rows*2,1,-1 do
    local i=(cursor-1)%#rows+1
    local row=rows[i]
    local goal=point(row)
    if row.action==checkpointAction then
      checkpoint=(checkpointAction~='zonapz'or goal)and row or nil;remaining=0;last=goal
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
    elseif not skipped[row.action] and not(checkpointAction=='zonapz' and row.action=='supplycheck')then checkpoint=nil;remaining=0;last=nil
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
          local cost=T.pathCost(path)+candidate.remaining
          if not plan.best or cost<plan.best.cost then
            plan.best={goal=T.copy(candidate.goal),row=candidate.row,checkpoint=candidate.checkpoint,
              cost=cost,steps=#path+candidate.remaining,direct=plan.stage=='direct'}
          end
        end
      end
    end
  end
  return plan.best
end
