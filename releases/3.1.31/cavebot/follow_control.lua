-- One movement owner. Pauses are runtime only; route configuration is not toggled.
local M={}
function M.new(host)
  local S={owner='idle',probeAt=0,good=0,failures=0}
  local C={state=S}
  local function point(p)return p and(p.x..','..p.y..','..p.z)or''end
  local function distance(a,b)return a and b and a.z==b.z and math.max(math.abs(a.x-b.x),math.abs(a.y-b.y))or math.huge end
  local function log(text)if host.log then host.log(text)end end
  local function pause(value)if host.pause then host.pause(value)end end
  local function resetProgress(s,t)
    S.position=point(s.origin);S.progressAt=t;S.planAt=t;S.plan=s.plan
    S.seen={[S.position]=true};S.seenCount=1;S.goal=s.goal;S.best=distance(s.origin,s.goal)
  end
  local function claim(s,t)
    S.owner='follow';S.name=s.name;S.since=t;S.good=0;S.noFollow=nil;S.steps=0;S.hold=nil
    resetProgress(s,t)
    pause(true)
    if host.stopCave then host.stopCave()end
    S.reason='Follow controla el movimiento; ruta pausada en su waypoint actual.'
    log(S.reason)
  end
  local function release(t,reason,stop,cause)
    local was=S.owner
    S.owner='cave';S.since=t;S.good=0;S.probeAt=t+2000;S.reason=reason
    if stop and host.stopFollow then host.stopFollow(cause)end
    pause(false)
    -- The character walked with the leader: the route goes on from where it stands now.
    if was=='follow'and host.resume then host.resume(reason,S.hint)end
    log(reason)
  end
  -- Reasons to hand movement to CaveBot at once instead of waiting 10 s without progress.
  -- While one holds, Follow does not take movement back.
  local function hold(s)
    -- Follow waits to see the leader (vBot/follow_wait.lua): after a death or with him too far.
    if s.waiting then
      return 'wait',s.waiting=='death'and'Follow en espera porque moriste: continua CaveBot hasta ver al leader en pantalla.'or
        'Follow en espera, el leader esta muy lejos: continua CaveBot hasta verlo en pantalla.'
    end
    if s.ownRefill then return 'refill','Refill propio ('..tostring(s.ownRefill)..'): continua CaveBot; Follow vuelve al terminar el refill.'end
    if s.leaderTrip and s.keepHunting then return 'trip','El leader salio a refill: sigo cazando con mi ruta hasta que vuelva.'end
    if s.leaderGone then return 'gone','El leader no responde por Navi (desconectado o con el bot apagado): continua CaveBot.'end
    if s.leaderPz then return 'pz','El leader esta en zona protegida (ciudad o templo): continua CaveBot.'end
  end
  function C.tick(s,t)
    if C.updating then return S.owner end
    C.updating=true
    local ok,result=pcall(function()
      if not host.enabled()then
        if S.owner=='follow'then pause(false)end
        S.owner='idle';S.name=nil;S.noFollow=nil;S.good=0;S.failures=0;return S.owner
      end
      if not s.intent and S.owner~='follow'then S.owner='idle';S.name=nil;S.good=0;S.failures=0;return S.owner end
      if host.blocked and host.blocked()then
        -- Escape/death/stamina/manual pauses keep their existing authority.
        pause(false);S.suspended=true;S.progressAt=t;S.planAt=t
        return 'blocked'
      end
      if S.suspended then
        S.suspended=nil
        if S.owner=='follow'then pause(true);resetProgress(s,t)end
      end
      if not s.intent then
        if S.owner=='follow'then
          S.noFollow=S.noFollow or t
          if t-S.noFollow<5000 then return S.owner end
          release(t,'Follow desactivado: continua la ruta.',false)
        end
        S.owner='idle';S.name=nil;S.good=0;S.failures=0;return S.owner
      end
      S.noFollow=nil
      if S.name~=s.name then
        if S.owner=='follow'then release(t,'Cambio de leader: reiniciando coordinacion.',true)end
        S.owner='idle';S.name=s.name;S.failures=0;S.hint=nil;S.stallGoal=nil
      end
      if s.hint then S.hint=s.hint end
      local cause,text=hold(s)
      if S.owner=='idle'then
        if host.caveBusy and host.caveBusy()then return 'cave'end
        if cause then
          -- The route was not paused: it keeps its waypoint; only Follow stops.
          S.owner='cave';S.since=t;S.good=0;S.probeAt=t+2000;S.hold=cause;S.reason=text
          if host.stopFollow then host.stopFollow(cause)end
          log(text);return S.owner
        end
        claim(s,t);return S.owner
      end
      if S.owner=='follow'then
        -- A purchase, boat trip or object use in progress finishes first.
        if cause and not(s.busyUntil and t<s.busyUntil)then
          release(t,text,true,cause);S.hold=cause
          return S.owner
        end
        pause(true)
        if t<(S.progressAt or t)then resetProgress(s,t)end
        local key=point(s.origin)
        if distance(S.goal,s.goal)>3 then S.goal=s.goal;S.best=distance(s.origin,s.goal)end
        if key~=''and key~=S.position then
          local closer=distance(s.origin,s.goal)<S.best
          if not S.seen[key]or closer then S.progressAt=t;S.steps=S.steps+1;if S.steps>=4 then S.failures=0 end end
          if not S.seen[key]then S.seenCount=S.seenCount+1 end
          S.seen[key]=true;S.position=key;S.best=math.min(S.best,distance(s.origin,s.goal))
          if S.seenCount>512 then S.seen={[key]=true};S.seenCount=1 end
        end
        if s.settled or s.busyUntil and t<s.busyUntil then
          if s.settled then S.failures=0 end
          resetProgress(s,t);return S.owner
        end
        if s.plan and s.plan~=S.plan then S.plan=s.plan;S.planAt=t end
        local stalled=t-S.progressAt>=10000
        local calculating=s.planning and t-S.planAt<2000 and t-S.progressAt<30000
        if stalled and not calculating then
          S.failures=S.failures+1
          S.stallGoal=s.goal
          release(t,'Leader sin acceso o sin avance durante 10 s: continua CaveBot; Follow espera un camino comprobado.',true,'stalled')
          S.probeAt=t+math.min(30000,2000*2^math.min(S.failures-1,4))
        end
        return S.owner
      end
      if cause then
        if S.hold~=cause then S.hold=cause;S.reason=text;log(text)end
        S.good=0;return S.owner
      end
      S.hold=nil
      -- While CaveBot owns movement, a passive probe cannot send steps or stops.
      if host.caveBusy and host.caveBusy()then return S.owner end
      -- Leader in sight and close: one fresh path is enough and there is no 2 s wait,
      -- unless the last stall was right here (a leader behind a wall stays visible).
      local near=s.visible and distance(s.origin,s.goal)<=7 and
        (S.failures==0 or distance(s.goal,S.stallGoal)>3)
      if t<S.probeAt and not near then return S.owner end
      local reachable=host.probe and host.probe(s,t)
      if reachable==nil then S.probeAt=t+200;return S.owner end
      S.probeAt=t+2000
      S.good=reachable==true and S.good+1 or 0
      if S.good>=(near and 1 or 2)then claim(s,t)end
      return S.owner
    end)
    C.updating=false
    if not ok then
      -- Fail closed for Follow while preserving the route's explicit on/off state.
      if S.owner=='follow'and host.stopFollow then pcall(host.stopFollow,'error')end
      S.owner='cave';S.good=0;S.probeAt=t+2000;pause(false)
      if host.error and(not S.errorAt or t-S.errorAt>=2000)then S.errorAt=t;host.error(result)end
    end
    return ok and result or 'blocked'
  end
  return C
end

local runtime,binding,paused,lastSample
-- "Pausar al seguir" is a profile option since change 214 (storage.extras.followPausesCave), ON
-- unless switched OFF. It was a route option, OFF in the route files, and Follow and CaveBot
-- then both walked the character.
function M.pauseOn()
  local extras=storage.extras
  return not(type(extras)=='table'and extras.followPausesCave==false)
end
local function call(o,k,...)
  if not o or type(o[k])~='function'then return end
  local ok,v=pcall(o[k],...);if ok then return v end
end
local function method(o,k)if not o then return end;local ok,v=pcall(function()return o[k](o)end);if ok then return v end end
local function clock()
  return tonumber(now)or call(g_clock,'millis')or math.floor(os.clock()*1000)
end
local function navigation()return ComboFollowCombat and ComboFollowCombat.navigation end
local function blocked()
  local move=TargetBot and TargetBot.Movement
  local trap=TargetBot and TargetBot.Antitrap
  local safety=CaveBot.Config and CaveBot.Config.safety or{}
  return call(HelperPause,'isPaused')or call(CaveBot.Flee,'blocksCombat')or
    call(CaveBot.WaitStamina,'isBlocking')or call(move,'isManual')or call(trap,'ownsMovement')or
    call(PushMax,'ownsMovement')or(tonumber(safety.deathWaitUntil)or 0)>clock() or safety.deathPolicyActive or
    method(player,'getHealthPercent')==0 or(g_game and type(g_game.isOnline)=='function'and not call(g_game,'isOnline'))
end
local function sample(t)
  local nav=navigation()
  local s
  if nav and nav.snapshot then
    local ok,value=pcall(nav.snapshot,t)
    if not ok then error(value)end
    s=value
  end
  if s and s.intent then return s end
  local target=call(g_game,'getFollowingCreature')
  local isPlayer=target and target~=player and method(target,'isPlayer')==true
  local origin=method(player,'getPosition')
  local goal=isPlayer and method(target,'getPosition')
  local intent=isPlayer and call(g_game,'isFollowing')~=false
  local settled=goal and origin and origin.z==goal.z and math.max(math.abs(origin.x-goal.x),math.abs(origin.y-goal.y))<=1
  return {intent=intent==true,name='native:'..tostring(method(target,'getId')or''),kind='native',origin=origin,goal=goal,settled=settled}
end
function M.bind(api)
  binding=api
  runtime=M.new({
    enabled=function()return M.pauseOn()and api.enabled()end,
    blocked=blocked,caveBusy=api.busy,
    pause=function(value)paused=value;api.pause(value)end,
    stopCave=api.stop,
    resume=api.resume,
    stopFollow=function(reason)
      local nav=navigation()
      if lastSample and lastSample.kind=='combo'then call(nav,'stop',reason)
      else call(g_game,'cancelFollow');call(g_game,'stop')end
    end,
    probe=function(s,t)if s.kind=='combo'then return call(navigation(),'probe',s,t)end;return false end,
    log=function(text)
      CaveBot.Diagnostics=CaveBot.Diagnostics or{};CaveBot.Diagnostics.followStatus=text
      if RinoConsole and RinoConsole.log then pcall(RinoConsole.log,'action','CaveBot / Follow',text)end
      -- Each change of owner also goes to the client log, to read it after a session.
      if type(info)=='function'then pcall(info,'[CaveBot / Follow] '..text)end
    end,
    error=function(err)if type(warn)=='function'then warn('Coordinacion de Follow: '..tostring(err))end end
  })
  -- The old pause serialized OFF without enough information to prove ownership.
  -- Discard that stale flag; never turn an explicitly disabled route ON on reload.
  storage.caveBotFollowPause={pausedByConfig=false,noFollowSince=0}
end
function M.poll()
  if not runtime then return 'idle'end
  local t=clock()
  if not M.pauseOn()or not binding.enabled()then return runtime.tick({intent=false},t)end
  local ok,s=pcall(sample,t)
  if not ok then
    if runtime.state.owner=='follow'then
      call(navigation(),'stop','error');call(g_game,'cancelFollow');call(g_game,'stop')
      paused=false;binding.pause(false)
    end
    runtime.state.owner='cave';runtime.state.good=0;runtime.state.probeAt=t+2000
    if not M.errorAt or t-M.errorAt>=2000 then
      M.errorAt=t;if type(warn)=='function'then warn('Coordinacion de Follow: '..tostring(s))end
    end
    return 'cave'
  end
  lastSample=s
  -- Own supplies, read at most every 2 s (the same rules as the route's supply check).
  if s.intent and binding.ownRefill then
    if not M.refillAt or t<M.refillAt or t-M.refillAt>=2000 then
      M.refillAt=t
      local okRefill,reason=pcall(binding.ownRefill)
      M.refill=okRefill and reason or nil
    end
    s.ownRefill=M.refill
  end
  return runtime.tick(lastSample,t)
end
function M.allowsFollow()
  if not runtime then return true end
  if runtime.updating then return false end
  local owner=M.poll()
  return owner~='cave'and owner~='blocked'
end
function M.beforeCave()
  if not runtime then return true end
  if runtime.updating then return false end
  local owner=M.poll()
  if owner=='blocked'then return call(CaveBot.Flee,'isEscaping')==true or call(CaveBot.WaitStamina,'isBlocking')==true end
  return owner~='follow'
end
function M.isYielding()return runtime and runtime.state.owner=='cave'and binding.enabled()and M.pauseOn()end
function M.isPaused()return paused==true end
function M.getState()return runtime and runtime.state or{owner='idle'}end
CaveBot.FollowControl=M
return M
