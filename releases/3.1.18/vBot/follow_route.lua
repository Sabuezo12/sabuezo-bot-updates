-- R196: incremental route planning. No native query grows with city distance.
local M={}
local MAX_ROUTE_NODES=8192
local offsets={{0,-1},{1,0},{0,1},{-1,0},{1,-1},{1,1},{-1,1},{-1,-1}}
local function copy(p)return {x=p.x,y=p.y,z=p.z}end
local function distance(a,b)return math.max(math.abs(a.x-b.x),math.abs(a.y-b.y))end
local function key(p)return p.x..','..p.y..','..p.z end
local function priority(cost,p,goal)
  return cost+distance(p,goal)*1.2+(math.abs(p.x-goal.x)+math.abs(p.y-goal.y))*.001
end
local function push(heap,node)
  local i=#heap+1
  while i>1 do
    local parent=math.floor(i/2)
    if heap[parent].score<=node.score then break end
    heap[i]=heap[parent];i=parent
  end
  heap[i]=node
end
local function pop(heap)
  local first=heap[1];local last=table.remove(heap)
  if #heap>0 then
    local i=1
    while i*2<=#heap do
      local c=i*2
      if heap[c+1] and heap[c+1].score<heap[c].score then c=c+1 end
      if heap[c].score>=last.score then break end
      heap[i]=heap[c];i=c
    end
    heap[i]=last
  end
  return first
end
local function checked(path,from,to,precision)
  if type(path)~='table' or #path>192 then return nil end
  local p=copy(from)
  for _,dir in ipairs(path)do
    local o=type(dir)=='number' and offsets[dir+1]
    if not o then return nil end
    p.x=p.x+o[1];p.y=p.y+o[2]
  end
  if distance(p,to)>(precision or 0) then return nil end
  return path
end
function M.new(from,goal,precision)
  local node={pos=copy(from),cost=0,score=distance(from,goal)}
  return {from=copy(from),goal=copy(goal),precision=precision or 1,heap={node},
    costs={[key(from)]=0},count=1,queries=0,nextQuery=0,phase='direct'}
end
local function result(job,node,tail)
  local legs={tail}
  while node and node.parent do legs[#legs+1]=node.path;node=node.parent end
  local path={}
  for i=#legs,1,-1 do for _,d in ipairs(legs[i])do path[#path+1]=d end end
  job.path=path;job.done=true;return path,'ready'
end
local function floodPath(paths,target,from)
  local reverse,seen={},{}
  local k=key(target)
  for _=1,192 do
    if k==key(from) then
      local path={};for i=#reverse,1,-1 do path[#path+1]=reverse[i]end
      return path
    end
    if seen[k] then return nil end
    seen[k]=true
    local node=paths[k]
    if type(node)~='table' then return nil end
    if type(node[3])~='number' then return nil end
    if node[3]<0 then return nil end
    if not offsets[node[3]+1] or type(node[4])~='string' then return nil end
    reverse[#reverse+1]=node[3];k=node[4]
  end
end
local function advanceFlood(job,time,flood)
  if job.flood then
    local scan=job.flood
    for _=1,512 do
      local k,node=scan.iterator(scan.state,scan.cursor);scan.cursor=k
      if not k or scan.count>=8192 then
        for _,candidate in pairs(scan.candidates)do
          if job.count>=MAX_ROUTE_NODES then break end
          local path=floodPath(scan.paths,candidate.pos,scan.node.pos)
          if path and #path>0 and checked(path,scan.node.pos,candidate.pos,0) then
            local cost=scan.node.cost+#path;local ck=key(candidate.pos)
            if not job.costs[ck] or cost<job.costs[ck] then
              job.costs[ck]=cost;job.count=job.count+1
              push(job.heap,{pos=candidate.pos,cost=cost,score=priority(cost,candidate.pos,job.goal),
                parent=scan.node,path=path})
            end
          end
        end
        job.flood=nil;return nil,'planning'
      end
      scan.count=scan.count+1
      if type(k)=='string' and #k<32 and type(node)=='table' then
        local x,y,z=k:match('^(%d+),(%d+),(%d+)$')
        local p=x and {x=tonumber(x),y=tonumber(y),z=tonumber(z)}
        if p and p.z==scan.node.pos.z and distance(p,scan.node.pos)<=24 then
          if distance(p,job.goal)<=job.precision then
            local path=floodPath(scan.paths,p,scan.node.pos)
            if path and checked(path,scan.node.pos,p,0) then return result(job,scan.node,path)end
          end
          local dx,dy=p.x-scan.node.pos.x,p.y-scan.node.pos.y
          if math.max(math.abs(dx),math.abs(dy))>=8 and not job.costs[k] then
            -- Actual reachable endpoints in each sector also cover narrow,
            -- winding corridors where fixed grid intersections are walls.
            local sector=math.floor(dx/8)..','..math.floor(dy/8)
            local score=distance(p,job.goal)
            local prior=scan.candidates[sector]
            if not prior or score<prior.score or score==prior.score and k<key(prior.pos)then
              scan.candidates[sector]={pos=p,score=score}
            end
          end
        end
      end
    end
    return nil,'planning'
  end
  if job.queries>=512 then job.done=true;return nil,'failed' end
  for _=1,64 do
    local node=pop(job.heap)
    if not node then job.done=true;return nil,'failed' end
    if job.costs[key(node.pos)]==node.cost then
      job.nextQuery=time+75;job.queries=job.queries+1
      local ok,paths=pcall(flood,node.pos,24)
      if ok and type(paths)=='table' then
        -- The bot exposes pairs, not global next. Retain its iterator/state.
        local iterator,state,cursor=pairs(paths)
        job.flood={paths=paths,node=node,count=0,candidates={},iterator=iterator,state=state,cursor=cursor}
      end
      return nil,'planning'
    end
  end
  return nil,'planning'
end
function M.advance(job,time,query,flood)
  if job.done then return job.path,job.path and 'ready' or 'failed' end
  if time<job.nextQuery then return nil,'planning' end
  -- One bounded native query per advance; all other work is also bounded.
  local function ask(from,to,limit,precision)
    job.nextQuery=time+75;job.queries=job.queries+1
    local ok,path=pcall(query,from,to,limit,precision)
    if ok then return checked(path,from,to,precision) end
  end
  if job.phase=='direct' then
    job.phase='graph'
    if distance(job.from,job.goal)<=60 then
      local path=ask(job.from,job.goal,64,job.precision)
      if path then return result(job,nil,path) end
      return nil,'planning'
    end
  end
  if type(flood)=='function' then return advanceFlood(job,time,flood) end
  if job.queries>=4096 then job.done=true;return nil,'failed' end
  for _=1,64 do
    if not job.node then
      local node=pop(job.heap)
      if not node then job.done=true;return nil,'failed' end
      if job.costs[key(node.pos)]==node.cost then
        job.node=node;job.neighbor=0
        job.order={}
        for dir,o in ipairs(offsets)do
          local p={x=node.pos.x+o[1]*24,y=node.pos.y+o[2]*24,z=node.pos.z}
          if p.x>=0 and p.x<=65535 and p.y>=0 and p.y<=65535 then
            job.order[#job.order+1]={pos=p,score=distance(p,job.goal),dir=dir}
          end
        end
        table.sort(job.order,function(a,b)if a.score~=b.score then return a.score<b.score end;return a.dir<b.dir end)
      end
    else
      local node=job.node
      if job.neighbor==0 then
        job.neighbor=1
        if distance(node.pos,job.goal)<=60 then
          local path=ask(node.pos,job.goal,64,job.precision)
          if path then return result(job,node,path) end
          return nil,'planning'
        end
      end
      local edge=job.order[job.neighbor];job.neighbor=job.neighbor+1
      if not edge then job.node=nil
      elseif not job.costs[key(edge.pos)] and job.count<MAX_ROUTE_NODES then
        local path=ask(node.pos,edge.pos,48,0)
        if path and #path>0 then
          local cost=node.cost+#path;local child={pos=edge.pos,cost=cost,
            score=priority(cost,edge.pos,job.goal),parent=node,path=path}
          job.costs[key(edge.pos)]=cost;job.count=job.count+1;push(job.heap,child)
        end
        return nil,'planning'
      end
    end
  end
  return nil,'planning'
end
-- R198: floor numbers are not connected regions. Validate walking segments
-- between observed stair endpoints before committing to a floor excursion.
function M.hasFloorReturn(links,floor)
  local queue,seen={},{}
  for _,e in ipairs(links)do if e.from.z==floor then queue[#queue+1]=e.to.z;seen[e.to.z]=true end end
  local head=1
  while queue[head]do
    local z=queue[head];head=head+1
    for _,e in ipairs(links)do if e.from.z==z then
      if e.to.z==floor then return true end
      if not seen[e.to.z] then seen[e.to.z]=true;queue[#queue+1]=e.to.z end
    end end
  end
  return false
end
function M.newJourney(from,goal,links,blocked,directFailed)
  local j={nodes={},ids={},walks={},stairs={},phase='quick',nextQuery=0,queries=0}
  local function add(pos)
    local k=key(pos)
    if not j.ids[k] then j.nodes[#j.nodes+1]=copy(pos);j.ids[k]=#j.nodes end
    return j.ids[k]
  end
  j.start=add(from);j.finish=add(goal);j.goal=copy(goal)
  j.directFailed=directFailed==true
  for i=1,math.min(32,#links)do
    local e=links[i];local k=key(e.from)..'>'..key(e.to)
    if not(blocked and blocked[k]) then
      local a,b=add(e.from),add(e.to)
      j.stairs[a]=j.stairs[a]or{}
      j.stairs[a][b]={kind='floor',from=e.from,to=e.to,a=a,b=b,cost=4,key=k}
    end
  end
  return j
end
local function journeyCandidate(j)
  local costs,used,parents={[j.start]=0},{},{}
  local function visit(a,b,edge)
    if used[b]then return end
    local cost=costs[a]+edge.cost
    if not costs[b]or cost<costs[b]then costs[b]=cost;parents[b]=edge end
  end
  for _=1,#j.nodes do
    local a
    for i=1,#j.nodes do if not used[i]and costs[i]and(not a or costs[i]<costs[a])then a=i end end
    if not a then return nil end
    if a==j.finish then
      local reverse,route={},{}
      while a~=j.start do local e=parents[a];if not e then return nil end;reverse[#reverse+1]=e;a=e.a end
      for i=#reverse,1,-1 do route[#route+1]=reverse[i]end
      return route
    end
    used[a]=true
    for b,pos in ipairs(j.nodes)do if b~=a and pos.z==j.nodes[a].z then
      local k=a..'>'..b;local e=j.walks[k]
      if not e then
        e={kind='walk',from=j.nodes[a],to=pos,a=a,b=b,cost=math.max(1,distance(j.nodes[a],pos))}
        if j.directFailed and a==j.start and b==j.finish then e.state='failed'end
        j.walks[k]=e
      end
      if e.state~='failed'and(j.phase=='full'or e.state~='deferred')then visit(a,b,e)end
    end end
    for b,e in pairs(j.stairs[a]or{})do visit(a,b,e)end
  end
end
function M.advanceJourney(j,time,query,flood)
  if j.done then return j.route,j.route and'ready'or'failed' end
  if time<j.nextQuery then return nil,'planning' end
  if j.queries>=1024 then j.done=true;return nil,'failed' end
  local function ask(from,to,limit,precision)
    j.queries=j.queries+1;j.nextQuery=time+75
    return query(from,to,limit,precision)
  end
  local floodQuery=type(flood)=='function'and function(from,limit)
    j.queries=j.queries+1;j.nextQuery=time+75;return flood(from,limit)
  end or nil
  if j.edgeJob then
    local e=j.edgeJob.edge
    local path,state=M.advance(j.edgeJob.job,time,ask,floodQuery)
    if state~='planning'then
      e.state=path and'proven'or'failed';e.path=path
      if path then e.cost=math.max(1,#path+1)end
      j.edgeJob=nil
    end
    return nil,'planning'
  end
  -- Lazy shortest-path validation: cheap direct queries first, then bounded
  -- incremental searches only for segments that need a longer detour.
  local route=journeyCandidate(j)
  if not route then
    if j.phase=='quick'then j.phase='full';return nil,'planning'end
    j.done=true;return nil,'failed'
  end
  for _,e in ipairs(route)do if e.kind=='walk'and e.state~='proven'then
    if not e.state then
      if distance(e.from,e.to)<=60 then
        local ok,path=pcall(ask,e.from,e.to,64,1)
        path=ok and checked(path,e.from,e.to,1)or nil
        e.state=path and'proven'or'deferred';e.path=path
        if path then e.cost=math.max(1,#path+1)end
        if path and #route==1 then j.done=true;j.route=route;return route,'ready'end
      else e.state='deferred'end
    else j.edgeJob={edge=e,job=M.new(e.from,e.to,1)}end
    return nil,'planning'
  end end
  j.done=true;j.route=route;return route,'ready'
end
ComboFollowRoutePlanner=M
return M
