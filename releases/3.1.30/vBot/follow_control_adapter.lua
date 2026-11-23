-- Observations and bounded path probes; these functions never send movement.
HelperFollowNavigation={}
function HelperFollowNavigation.bind(ctx)
  local nav={}
  local cachedRoute,routeAt,routeName,probe,lastName
  local function copy(p)return p and{x=p.x,y=p.y,z=p.z}end
  local function gap(a,b)return a and b and a.z==b.z and math.max(math.abs(a.x-b.x),math.abs(a.y-b.y))or math.huge end
  local function key(p)return p and(p.x..','..p.y..','..p.z)or''end
  local function nativeRoute(name,t)
    if routeName==name and routeAt and t>=routeAt and t-routeAt<250 then return cachedRoute end
    routeName,routeAt,cachedRoute=name,t,nil
    if not BotServer then return end
    local status
    if BotServer.getFollowStatus then
      local ok,value=pcall(BotServer.getFollowStatus,name);if ok then status=value end
    end
    if status and(status.enabled~=true or status.connected~=true or status.selfTarget)then return end
    if BotServer.requestFollowRoute then pcall(BotServer.requestFollowRoute,name)end
    if BotServer.getMemberFollowRoute then
      local ok,value=pcall(BotServer.getMemberFollowRoute,name)
      if ok then cachedRoute=ctx.fresh(value,t)end
    end
    if not cachedRoute and BotServer.getMemberSnapshot then
      local ok,list=pcall(BotServer.getMemberSnapshot)
      if ok and type(list)=='table'then
        for who,value in pairs(list)do
          if type(who)=='string'and who:lower()==name:lower()then cachedRoute=ctx.fresh(value,t);break end
        end
      end
    end
    return cachedRoute
  end
  function nav.snapshot(t)
    local name=ctx.name()
    local intent=ctx.settings.enabled==true and ctx.settings.followEnabled==true and name~=''
    local origin=ctx.position()
    if not intent then probe=nil;return{intent=false,name=name,origin=origin}end
    if lastName~=name then probe=nil;nav.failedAccess=nil;nav.retryAccessAt=nil;lastName=name end
    local actor=ctx.visible()
    local goal=actor and actor:getPosition()
    if goal and origin and goal.z~=origin.z then actor,goal=nil,nil end
    local route
    if not actor then local ok,value=pcall(nativeRoute,name,t);if ok then route=value end end
    goal=goal or route and route.pos
    local search=ctx.search()
    local job=search.job or search.journey and search.journey.job or search.prefetch
    local plan=job and(table.concat({tostring(job),tostring(job.phase),tostring(job.queries),tostring(job.count)},':'))
    local busy=ctx.busy(t)
    local combat=actor and ctx.combat and ctx.combat()or{}
    return{kind='combo',intent=true,name=name:lower(),origin=copy(origin),goal=copy(goal),
      visible=actor~=nil,route=route,distance=ctx.distance(),
      settled=actor~=nil and(gap(origin,goal)<=ctx.distance()or combat.active==true and combat.ready==true),
      plan=plan,planning=job~=nil and not job.done,busyUntil=busy}
  end
  local function query(from,to,limit,precision)
    if type(getPath)~='function'then return nil end
    return getPath(from,to,limit,{precision=precision,ignoreFields=ctx.settings.followIgnoreFields==true,
      ignoreNonPathable=false,ignoreStairs=false,allowUnseen=true,allowOnlyVisibleTiles=false})
  end
  local function connector(from,to,precision)
    local path=query(from,to,16,precision)
    if type(path)~='table'or #path>16 then return false end
    local offsets={{0,-1},{1,0},{0,1},{-1,0},{1,-1},{1,1},{-1,1},{-1,-1}}
    local position=copy(from)
    for _,direction in ipairs(path)do
      local offset=offsets[direction+1];if not offset then return false end
      position.x=position.x+offset[1];position.y=position.y+offset[2]
    end
    return gap(position,to)<=precision
  end
  local function access(s)
    local goal=s.goal
    if not goal or not s.origin then return end
    if goal.z==s.origin.z then return goal,s.distance end
    local route=s.route
    if not route then return end
    local links=ctx.links(route)
    for i=#links,1,-1 do
      local edge=links[i]
      if edge.from.z==s.origin.z then
        local floor=edge.to.z
        for j=i+1,#links do if links[j].from.z==floor then floor=links[j].to.z end end
        if floor==goal.z then return edge.from,1 end
      end
    end
  end
  function nav.probe(s,t)
    local goal,precision=access(s)
    if not goal then probe=nil;return false end
    if s.goal.z~=s.origin.z and nav.failedAccess==key(goal)..':'..s.goal.z and t<(nav.retryAccessAt or 0)then return false end
    if gap(s.origin,goal)<=precision then
      -- Being next to an access that just failed does not prove the crossing.
      if s.goal.z~=s.origin.z and nav.failedAccess==key(goal)..':'..s.goal.z and t<(nav.retryAccessAt or 0)then return false end
      return true
    end
    if not probe or probe.name~=s.name or gap(probe.job.goal,goal)>8 or
      gap(probe.job.from,s.origin)>8 or probe.precision~=precision or t-probe.at>10000 then
      probe={name=s.name,at=t,precision=precision,job=ctx.planner.new(s.origin,goal,precision,nil,false)}
    end
    local started=os.clock()*1000
    local path,state=ctx.planner.advanceWithin(function()
      return ctx.planner.advance(probe.job,t,query)
    end,probe.job,function()return os.clock()*1000 end,2,2)
    if state=='planning'then return nil end
    if not path then probe=nil;return false end
    -- A route planned from a nearby earlier tile still needs a connector from
    -- the current tile, and a moving leader needs a valid final connector.
    if gap(s.origin,probe.job.from)>0 then
      if os.clock()*1000-started>=4 then return nil end
      if not connector(s.origin,probe.job.from,0)then probe=nil;return false end
    end
    if gap(goal,probe.job.goal)>0 then
      if os.clock()*1000-started>=4 then return nil end
      if not connector(probe.job.goal,goal,precision)then probe=nil;return false end
    end
    probe=nil -- Each positive confirmation must come from a newly calculated path.
    return true
  end
  function nav.stop(reason)
    local s=nav.snapshot(ctx.time())
    local goal=access(s)
    if reason=='stalled'and goal and s.goal and s.origin and s.goal.z~=s.origin.z and gap(s.origin,goal)<=1 then
      nav.failedAccess=key(goal)..':'..s.goal.z;nav.retryAccessAt=ctx.time()+30000
    end
    probe=nil;ctx.stop()
  end
  ctx.follow.navigation=nav
  return nav
end
return HelperFollowNavigation
