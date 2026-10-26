-- Event-driven Push Max. Native requests are never treated as acknowledgements.
-- All deadlines use the injected executor clock; one dependent action is in flight.
RinoPushMaxEngine = {}
local offsets={{0,-1},{1,0},{0,1},{-1,0},{1,-1},{1,1},{-1,1},{-1,-1}}
local function copy(p) return p and {x=p.x,y=p.y,z=p.z} end
local function same(a,b) return a and b and a.x==b.x and a.y==b.y and a.z==b.z end
local function key(p) return p.x..':'..p.y..':'..p.z end
local function distance(a,b)
  if not a or not b or a.z~=b.z then return 999 end
  return math.max(math.abs(a.x-b.x),math.abs(a.y-b.y))
end
local function adjacent(p,i)
  return {x=p.x+offsets[i][1],y=p.y+offsets[i][2],z=p.z}
end
local function position(p)
  return type(p)=='table' and type(p.x)=='number' and type(p.y)=='number' and type(p.z)=='number'
    and p.x%1==0 and p.y%1==0 and p.z%1==0 and p.x>=0 and p.y>=0 and p.z>=0
    and p.x<=65535 and p.y<=65535 and p.z<=15
end

function RinoPushMaxEngine.new(world,config)
  local e={job=nil,pending=nil,status='Listo',detail='',sequence=0,attempts={},stats={
    jobs=0,pushSent=0,pushObserved=0,walkSent=0,walkObserved=0,
    destroySent=0,destroyObserved=0,disintegrateSent=0,disintegrateObserved=0,fireSent=0,fireObserved=0,
    wallSent=0,wallObserved=0,timeouts=0,refusals=0,cancelled=0,finished=0,pushEarlyTimeouts=0,spellRecoveries=0,cancelReasons={}},timings={},pushByDistance={},responseProfiles={}}
  local function clock() return world.time() end
  local function state(text,detail)
    detail=tostring(detail or '')
    if e.status~=text or e.detail~=detail then
      e.status,e.detail=text,detail
      if world.state then world.state(text,detail) end
    end
  end
  local function ping() return math.max(0,math.min(1000,world.ping() or 0)) end
  local function retryDelay() return math.max(10,math.min(2000,tonumber(config.pushDelay) or 190)) end
  local function observedTiming(action,elapsed)
    local t=e.timings[action]
    if not t then t={count=0,total=0,min=elapsed,max=elapsed,recent={}};e.timings[action]=t end
    t.count=t.count+1;t.total=t.total+elapsed;t.min=math.min(t.min,elapsed);t.max=math.max(t.max,elapsed)
    t.recent[#t.recent+1]=elapsed
    if #t.recent>8 then table.remove(t.recent,1) end
  end
  local function acknowledgementWindow(action)
    local base=action=='push' and math.max(1200,ping()*3+300)
      or action=='walk' and math.max(500,ping()*3+250) or math.max(350,ping()*3+200)
    -- A fast sample is not proof of the server's minimum push delay. Only
    -- enlarge the safe deadline after consistently observed slow responses.
    local t=e.timings[action]
    if t and #t.recent>=3 then
      local peak=0;for _,ms in ipairs(t.recent)do peak=math.max(peak,ms)end
      base=math.max(base,math.min(5000,peak*1.5+ping()*2))
    end
    return base
  end
  local function responseProfile(from,extra)
    local sqm=math.min(12,math.max(0,distance(world.player(),from)))
    local anti=e.job and e.job.anti[key(from)]
    local cleanup=extra and extra.fireSourceField or anti and anti.probe and not anti.blocked
    return sqm..(cleanup and ':cleanup'or ':clear')
  end
  local function pushWindow(from,extra)
    local base=acknowledgementWindow('push')
    if not config.adaptivePushAck then return base end
    local id=responseProfile(from,extra);local profile=e.responseProfiles[id];local n=clock();local latency=ping()
    if not profile or #profile.samples<6 or n<(profile.suspendedUntil or 0)then return base,id,false end
    local peak=0
    for _,sample in ipairs(profile.samples)do
      if n<sample.at or n-sample.at>120000 or math.abs(latency-sample.ping)>math.max(20,sample.ping*0.25)then return base,id,false end
      peak=math.max(peak,sample.ms)
    end
    -- This is a bounded response deadline, not a server cooldown estimate.
    -- Keep jitter/ping headroom and never make a slower profile more aggressive.
    local window=math.ceil(math.max(400,latency*4+100,peak+math.max(200,latency*3)))
    return math.min(base,window),id,window<base
  end
  local function rememberResponse(p,elapsed)
    if not config.adaptivePushAck or p.action~='push'or not p.responseProfile or p.responseDirty then return end
    local profile=e.responseProfiles[p.responseProfile]
    if not profile then profile={samples={}};e.responseProfiles[p.responseProfile]=profile end
    profile.samples[#profile.samples+1]={ms=elapsed,ping=p.sentPing,at=clock()}
    if #profile.samples>8 then table.remove(profile.samples,1)end
  end
  local function tile(p) return world.tile(p,e.job and e.job.id) end
  local function available(t)
    return t and t.safe and not t.hard and not t.other and (t.walkable or t.field or (t.trash or 0)>0)
  end
  -- Coins/items on a walkable landing square do not by themselves require
  -- a rune. Reserve the anti-push opening for the creature's current square.
  local function destinationNeedsDisintegrate(t)
    return t and (t.trash or 0)>0 and not(config.sourceAntipushPriority and t.walkable)
  end
  local function finish(reason)
    e.job=nil;e.pending=nil;e.stats.finished=e.stats.finished+1
    state(reason)
  end
  local function result(p,text)
    p.record.result=text;p.record.observedAt=clock()
    if world.report then pcall(world.report,p,text)end
    e.pending=nil
  end
  function e.cancel(reason)
    if e.job then
      e.stats.cancelled=e.stats.cancelled+1
      reason=reason or 'Cancelado'
      e.stats.cancelReasons[reason]=(e.stats.cancelReasons[reason] or 0)+1
      if e.pending then result(e.pending,'cancelled: '..reason) end
    end
    e.job=nil;e.pending=nil;state(reason or 'Cancelado')
  end
  function e.start(id,destination)
    local target=world.target(id)
    local own=world.player()
    -- Repeating the key for the same goal must not discard an outstanding move
    -- or restart the lifetime. A genuinely different goal still replaces it.
    if e.job and e.job.id==id and position(destination) and same(e.job.dest,destination)
      and target and own and target.z==e.job.floor and own.z==e.job.floor then return true end
    e.cancel('Nuevo destino')
    if not target or not own or not position(destination) or distance(target,destination)>12
      or target.z~=destination.z or target.z~=own.z then
      state('Destino no valido','Mismo piso, hasta 12 SQM');return false
    end
    local targetTile=tile(destination)
    if not available(targetTile) and not (targetTile and targetTile.safe and targetTile.wall and not targetTile.other) then
      state('Destino bloqueado');return false
    end
    e.sequence=e.sequence+1;e.stats.jobs=e.stats.jobs+1
    e.job={number=e.sequence,id=id,dest=copy(destination),floor=own.z,started=clock(),
      pushed=0,failures=0,retries={},banned={},avoidedEdges={},anti={},spellRecoveries={},readyAt=0,last=copy(target)}
    state('Calculando ruta');return true
  end
  function e.changed(p,kind)
    if e.pending and e.pending.action=='fire' and kind=='fire' and same(p,e.pending.to) then
      e.pending.fireEvent=true
    end
    if e.job and e.job.waitingWall then
      e.job.readyAt=0;e.job.search=nil;e.job.waitingWall=nil
    end
    if e.job then e.job.wallCandidates=nil end
  end
  function e.refused(action,reason)
    local p=e.pending
    -- Text messages have no request ID. Accept only a narrowly correlated
    -- hint, preserve a grace period, and always observe the map before retrying.
    if not e.job or not p or p.action~=action or p.refusal or world.manual() or world.urgent() then return false end
    local age=clock()-p.at
    if age<0 or age>math.max(250,math.min(600,ping()*3)) then return false end
    p.refusal=tostring(reason or 'Solicitud rechazada'):sub(1,120)
    p.deadline=math.min(p.deadline,clock()+math.max(100,ping()*2))
    return true
  end
  local function spellRecoveryKey(p)
    return key(p.from)..'>'..key(p.to)..(p.extra and p.extra.distancePush and ':approach' or ':adjacent')
  end
  function e.spellObserved()
    local job,p=e.job,e.pending
    if not config.recoverAfterSpell or not job or not p or p.action~='push' or p.spellRecoveryAt then return false end
    local edge=spellRecoveryKey(p)
    if job.spellRecoveries[edge] then return false end
    local delay=math.max(100,math.min(300,ping()+50))
    if clock()+delay>=p.deadline then return false end
    -- Own speech can interrupt the server's queued move while approaching.
    -- Keep the old request during a short acknowledgement grace; never turn
    -- speech itself into proof that a push succeeded or definitely failed.
    p.spellRecoveryAt=clock()+delay;p.record.spellRecoveryWaitMs=delay
    return true,delay
  end
  local function record(action,from,to)
    local r={job=e.job.number,target=e.job.id,action=action,from=copy(from),to=copy(to),sentAt=clock(),result='pending'}
    e.attempts[#e.attempts+1]=r
    if #e.attempts>24 then table.remove(e.attempts,1) end
    return r
  end
  local function blockedAnti(p)
    if config.distanceCleanup and p.action=='fire' then
      local anti=e.job.anti[key(p.to)]
      if anti then anti.probe=false;anti.blocked=true end
    end
    if p.action~='push'then return end
    for _,pos in ipairs({p.from,p.to})do
      local anti=e.job.anti[key(pos)]
      if anti then anti.blocked=true end
    end
  end
  local function requestRetreat(p)
    if config.retreatOnSlow and p.action=='push' and distance(p.own,p.from)==1
      and e.job.retreatFor~=key(p.from) then e.job.retreatWanted=copy(p.from) end
  end
  local function distanceBucket(p)
    if p.action~='push'then return nil end
    local sqm=math.min(12,math.max(0,distance(p.own,p.from)))
    local bucket=e.pushByDistance[sqm]
    if not bucket then
      bucket={sent=0,observed=0,rejected=0,unconfirmed=0,total=0,recent={}}
      e.pushByDistance[sqm]=bucket
    end
    return bucket
  end
  local function send(action,from,to,extra)
    if world.actionReady then
      local ready,reason=world.actionReady(action)
      if not ready then state(reason or 'Espacio tras objeto');return false end
    end
    local n=clock()
    local timeout,profile,adaptive
    if action=='push'then timeout,profile,adaptive=pushWindow(from,extra)else timeout=acknowledgementWindow(action)end
    local pending={action=action,from=copy(from),to=copy(to),own=copy(world.player()),at=n,deadline=n+timeout,
      extra=extra,record=record(action,from,to),responseProfile=profile,adaptiveResponse=adaptive,sentPing=ping()}
    local recovery=e.job.spellRecoveryFor
    if action=='push' and recovery then
      if same(from,recovery.from) and same(to,recovery.to) then
        -- A late answer may belong to the preceding request. It is a real
        -- map acknowledgement, but not a clean latency-training sample.
        pending.responseDirty=true;pending.record.recoveredAfterSpell=true
      end
      e.job.spellRecoveryFor=nil
    end
    if action=='push'and config.adaptivePushAck then
      pending.record.responseWindowMs=timeout;pending.record.adaptiveResponse=adaptive==true
    end
    local bucket=distanceBucket(pending)
    if bucket then
      bucket.sent=bucket.sent+1;pending.bestDistance=distance(pending.own,pending.from)
      pending.record.playerDistance=pending.bestDistance
    end
    e.pending=pending -- register before calling native code (it may emit events synchronously)
    e.stats[action..'Sent']=e.stats[action..'Sent']+1
    if action=='wall' then e.job.wallAttempts=(e.job.wallAttempts or 0)+1 end
    if world.report then pcall(world.report,pending,'requested')end
    local ok,sent,reason,kind=pcall(world.send,action,to,e.job.id,extra)
    if not ok or sent==false then
      if e.pending==pending then
        if not ok then pending.record.error=tostring(sent):sub(1,180)end
        if ok and reason then pending.record.reason=tostring(reason):sub(1,160)end
        if bucket then bucket.rejected=bucket.rejected+1 end
        if action=='push'and extra and extra.distancePush then e.job.distanceFallback=copy(from)end
        if action=='walk'and ok and kind=='busy'then
          result(pending,'deferred: walk in progress')
          e.job.readyAt=n+math.max(50,math.min(150,ping()))
          state('Esperando mi paso',pending.record.reason);return false
        end
        result(pending,ok and 'request rejected' or 'request error')
        blockedAnti(pending)
        requestRetreat(pending)
        local delay=retryDelay()
        if action=='walk'and world.walkFailed then
          pcall(world.walkFailed,pending.from,pending.to,pending.record.reason or 'request error')
          delay=math.max(delay,math.max(100,math.min(250,ping()*2)))
        end
        e.job.readyAt=n+delay;e.job.failures=e.job.failures+1
        state('No se pudo enviar',action..(pending.record.reason and ' / '..pending.record.reason or ''))
      end
      return false
    end
    return true
  end
  local function runeReady(action,to)
    local ready,reason=world.runeReady(action,to)
    if not ready then state(reason or 'Esperando runa',action);return false end
    return true
  end
  local function clean(action,p,t,ready)
    if action=='fire'and config.allowFire==false then return false end
    if not ready and not runeReady(action,p) then return false end
    local from=world.target(e.job.id)
    if not from then return false end
    if config.sourceAntipushPriority and action=='disintegrate' and not same(p,from)then
      -- A genuinely blocked landing may need preparation, but its rune must
      -- never retain permission from an older cleanup under a replenishing player.
      local anti=e.job.anti[key(from)]
      if anti then anti.probe=false end
    end
    state(action=='fire' and 'Fire Field contra antipush' or action=='destroy' and 'Limpiando field' or 'Limpiando objetos')
    return send(action,from,p,{field=t.field,trash=t.trash or 0})
  end
  local function markDisintegrateProbe(p)
    if not config.pairedCleanup then return end
    e.job.anti[key(p.to)]={probe=true,blocked=false,from=copy(p.from),disintegrate=true}
  end
  local function markFireProbe(p,t)
    local anti=e.job.anti[key(p.to)] or {}
    anti.probe=true;anti.blocked=false;anti.fire=true;anti.fireTried=true
    anti.from=copy(p.from);anti.field=t and t.fire and t.field or nil
    e.job.anti[key(p.to)]=anti
  end
  local function ownFire(target,t)
    local anti=e.job.anti[key(target)]
    return config.distanceCleanup and t and t.fire and anti and anti.fire
      and anti.probe and not anti.blocked and same(anti.from,target) and anti.field==t.field
  end
  local function observe(target,own)
    local p=e.pending
    if not p then return end
    local action=p.action
    local observed=false
    if config.pairedCleanup and(action=='disintegrate'or action=='destroy'or config.distanceCleanup and action=='fire')and not same(target,p.from)then
      result(p,'target moved during cleanup');e.job.route=nil;e.job.search=nil
      e.job.last=copy(target);e.job.readyAt=0;return
    end
    if action=='push' then
      local busy=world.manual()or world.urgent()or world.paused and world.paused()
        or world.responseBusy and world.responseBusy(p.at)or not same(own,p.own)
      local unstable=math.abs(ping()-p.sentPing)>math.max(20,p.sentPing*0.25)
      if busy or unstable then
        p.responseDirty=true
        if p.adaptiveResponse then
          p.adaptiveResponse=false;p.record.adaptiveRestored=true
          p.deadline=math.max(p.deadline,p.at+acknowledgementWindow('push'))
        end
      end
      if p.extra and p.extra.distancePush and same(target,p.from)then
        local remaining=distance(own,target)
        if remaining<(p.bestDistance or math.huge)then
          p.bestDistance=remaining
          p.deadline=math.max(p.deadline,clock()+acknowledgementWindow('push'))
        end
      end
      if not same(target,p.from) then
        e.job.distanceFallback=nil
        if same(target,p.to) then
          observed=true;e.job.pushed=e.job.pushed+1
          e.job.previous=copy(p.from)
          if e.job.route and same(e.job.route[1],p.to) then table.remove(e.job.route,1) end
          e.job.last=copy(target)
        else
          result(p,'target moved elsewhere');e.job.route=nil;e.job.search=nil
          e.job.wallCandidates=nil;e.job.last=copy(target);e.job.readyAt=0
          state('Objetivo se movio','Recalculando');return
        end
      end
    elseif action=='walk' then
      if same(own,p.to) then observed=true
      elseif not same(own,p.from) then result(p,'player moved elsewhere');return end
    else
      local t=tile(p.to)
      if action=='fire' then observed=t~=nil and (p.fireEvent or t.fire and t.field~=p.extra.field or (t.trash or 0)<p.extra.trash)
      elseif action=='destroy' then observed=t~=nil and not t.field
      elseif action=='disintegrate' then observed=t~=nil and (t.trash or 0)<p.extra.trash
      elseif action=='wall' then observed=t~=nil and t.wall==true end
    end
    if observed then
      if action=='disintegrate'then markDisintegrateProbe(p)end
      if config.distanceCleanup and action=='fire'then markFireProbe(p,tile(p.to))end
      observedTiming(action,math.max(0,clock()-p.at))
      rememberResponse(p,math.max(0,clock()-p.at))
      local bucket=distanceBucket(p)
      if bucket then
        local elapsed=math.max(0,clock()-p.at)
        bucket.observed=bucket.observed+1;bucket.total=bucket.total+elapsed
        bucket.min=math.min(bucket.min or elapsed,elapsed);bucket.max=math.max(bucket.max or elapsed,elapsed)
        bucket.recent[#bucket.recent+1]=elapsed
        if #bucket.recent>8 then table.remove(bucket.recent,1)end
      end
      result(p,'observed')
      e.stats[action..'Observed']=e.stats[action..'Observed']+1
      e.job.readyAt=0;e.job.failures=0
      if action~='push' and action~='walk' and world.runeObserved then world.runeObserved(action,p.at) end
      if action=='wall' then
        if same(target,p.from) then finish('Wall confirmada');return end
        e.job.wallCandidates=nil
        state('Objetivo se movio','Buscando nuevo cierre');return
      end
    elseif clock()>=p.deadline then
      local bucket=distanceBucket(p)
      if bucket then bucket.unconfirmed=bucket.unconfirmed+1 end
      if p.adaptiveResponse and p.responseProfile then
        local profile=e.responseProfiles[p.responseProfile]
        if profile then profile.samples={};profile.suspendedUntil=clock()+30000 end
        p.record.adaptiveFallback=true;e.stats.pushEarlyTimeouts=e.stats.pushEarlyTimeouts+1
      end
      if action=='push'and p.extra and p.extra.distancePush then e.job.distanceFallback=copy(p.from)end
      result(p,p.refusal and 'refusal hint: '..p.refusal or 'timeout')
      if p.refusal then e.stats.refusals=e.stats.refusals+1 else e.stats.timeouts=e.stats.timeouts+1 end
      blockedAnti(p)
      requestRetreat(p)
      if action=='walk'and world.walkFailed then pcall(world.walkFailed,p.from,p.to,'Sin confirmacion del paso')end
      e.job.failures=e.job.failures+1
      local edge=key(p.from)..'>'..key(p.to)..':'..action
      e.job.retries[edge]=(e.job.retries[edge] or 0)+1
      if e.job.retries[edge]>=3 then
        if action=='push'and config.avoidFailedPushEdges then
          -- A failed direction does not prove that the tile itself cannot be
          -- reached. Preserve the marked destination and try a different entry.
          e.job.avoidedEdges[key(p.from)..'>'..key(p.to)]=true
          e.job.route=nil;e.job.search=nil
        elseif action=='push' or action=='destroy' or action=='disintegrate' then
          e.job.banned[key(p.to)]=true;e.job.route=nil;e.job.search=nil
        end
      end
      e.job.readyAt=clock()+retryDelay()*math.min(3,e.job.retries[edge])
      state(p.refusal and 'Solicitud no confirmada' or 'Sin confirmacion',action..' / reintento limitado')
    end
  end
  local function newSearch(from)
    local node={pos=copy(from),cost=0,score=distance(from,e.job.dest)*1000}
    e.job.search={open={node},best={[key(from)]=node},count=0,origin=copy(from),cache={}}
  end
  -- A* is split over ticks. No map-wide scan, recursive search or sleep loop.
  local function search(from)
    local job=e.job
    if not job.search or not same(job.search.origin,from) then newSearch(from) end
    local s=job.search
    local function cached(p)
      local k=key(p)
      if s.cache[k]==nil then
        s.cache[k]=tile(p) or false
        if s.cache[k] and s.cache[k].wall then s.temporary=true end
      end
      return s.cache[k] or nil
    end
    for _=1,16 do
      if #s.open==0 or s.count>=256 then
        if s.temporary then
          job.search=nil;job.waitingWall=true;job.readyAt=clock()+200
          state('Esperando wall','Ruta temporalmente cerrada')
        else finish('Sin ruta viable') end
        return nil
      end
      local index=1
      for i=2,#s.open do if s.open[i].score<s.open[index].score then index=i end end
      local node=table.remove(s.open,index)
      if not node.closed then
        node.closed=true;s.count=s.count+1
        if same(node.pos,job.dest) then
          local path={}
          while node.parent do table.insert(path,1,copy(node.pos));node=node.parent end
          job.route=path;job.search=nil;return path
        end
        for i=1,8 do
          local p=adjacent(node.pos,i)
          local edgeAllowed=not(config.avoidFailedPushEdges and job.avoidedEdges[key(node.pos)..'>'..key(p)])
          local t=distance(from,p)<=12 and not job.banned[key(p)] and edgeAllowed and cached(p) or nil
          local valid=available(t)
          if valid and i>=5 then
            local a=cached({x=p.x,y=node.pos.y,z=p.z})
            local b=cached({x=node.pos.x,y=p.y,z=p.z})
            valid=available(a) or available(b)
          end
          if valid then
            local cost=node.cost+1000+(i>=5 and 10 or 0)+(t.field and 2800 or 0)
              +((t.trash or 0)>0 and 2500 or 0)
            local k=key(p);local previous=s.best[k]
            if not previous or cost<previous.cost then
              local nextNode={pos=p,cost=cost,score=cost+distance(p,job.dest)*1000,parent=node}
              s.best[k]=nextNode;s.open[#s.open+1]=nextNode
            end
          end
        end
      end
    end
    state('Calculando ruta');return nil
  end
  local function approach(target,nextPos,range)
    local own=world.player()
    if distance(own,target)<=range and not same(own,nextPos) then return true end
    if world.moving and world.moving() then state('Esperando mi paso');return false end
    local direction,to=world.walkStep(target,nextPos,range)
    if direction~=nil and to then
      state('Acercandome al objetivo')
      send('walk',own,to,{direction=direction})
    else state('Sin posicion para empujar','Acercate al objetivo') end
    return false
  end
  local function clearSource(target,t)
    if not t or (t.trash or 0)==0 then return true end
    local k=key(target);local anti=e.job.anti[k]
    -- Fire is attempted once per source tile. After its observation/deadline,
    -- probe a push without waiting for rune cooldown or for every coin to vanish.
    -- A rejected/unconfirmed probe falls back to Disintegrate, never a fire loop.
    if anti and anti.probe and not anti.blocked then return true end
    if config.distanceCleanup then
      -- Keep the real melee range of Disintegrate. A distant antipush gets
      -- one Fire request; a refusal/timeout switches to the melee fallback.
      if distance(world.player(),target)>1 then
        if (tonumber(config.pushMaxRuneId)or 0)>0 and not(anti and anti.fireTried) then
          local ready,reason,unavailable=world.runeReady('fire',target)
          if ready then
            anti=anti or {};anti.fireTried=true;anti.probe=false;e.job.anti[k]=anti
            clean('fire',target,t,true)
          elseif unavailable then
            anti=anti or {};anti.fireTried=true;e.job.anti[k]=anti
            state('Fire Field no disponible','Acercamiento para Disintegrate')
          else state(reason or 'Esperando Fire Field','Antipush')end
        end
        return false
      end
      clean('disintegrate',target,t);return false
    end
    if not anti and config.allowFire~=false and (tonumber(config.pushMaxRuneId) or 0)>0 then
      local ready,reason,unavailable=world.runeReady('fire',target)
      if ready then
        anti={probe=true};e.job.anti[k]=anti
        if not clean('fire',target,t,true) then anti.probe=false end
        return false
      elseif not unavailable then
        state(reason or 'Esperando Fire Field','Antipush');return false
      end
    end
    clean('disintegrate',target,t);return false
  end
  local function wallCandidates(target,own)
    local candidates={}
    for i=1,8 do
      local p=adjacent(target,i);local t=tile(p)
      if t and t.safe and t.walkable and not t.hard and not t.other and not t.field and not t.wall
        and (t.trash or 0)==0 and not same(p,own) and t.shootable~=false then
        local score=i<=4 and 20 or 0
        if same(p,e.job.previous) then score=score+35 end
        local walls=0
        for j=1,8 do
          local q=adjacent(p,j);local side=tile(q)
          if side and (side.hard or side.wall) then walls=walls+1 end
        end
        score=score+walls*12-distance(p,own)
        -- Do not close our only immediately available escape square.
        local escape=0
        for j=1,8 do
          local q=adjacent(own,j)
          if not same(q,p) and not same(q,target) then
            local side=tile(q)
            if side and side.safe and side.walkable and not side.hard and not side.other and not side.field then escape=escape+1 end
          end
        end
        if escape>0 then candidates[#candidates+1]={pos=p,score=score} end
      end
    end
    table.sort(candidates,function(a,b)return a.score>b.score end)
    return candidates
  end
  local function close(target,own)
    local job=e.job
    if not job.closingAt then job.closingAt=clock();job.route=nil end
    if clock()-job.closingAt>=8000 or (job.wallAttempts or 0)>=3 then finish('Cierre sin confirmar');return end
    if not job.wallCandidates or not same(job.wallFor,target) or not same(job.wallOwn,own) then
      job.wallCandidates=wallCandidates(target,own);job.wallFor=copy(target);job.wallOwn=copy(own)
    end
    local candidates=job.wallCandidates
    if #candidates==0 then
      job.wallCandidates=nil;state('Sin casilla para wall','Esperando una casilla libre');return
    end
    local validCandidates=0
    for _,candidate in ipairs(candidates) do
      local t=tile(candidate.pos)
      if t and t.safe and t.walkable and not t.hard and not t.other and not t.field and not t.wall
        and (t.trash or 0)==0 and not same(candidate.pos,own) then
        validCandidates=validCandidates+1
        local ready,reason=world.runeReady('wall',candidate.pos)
        if ready then
          state('Cerrando con wall');send('wall',target,candidate.pos,{})
          return
        end
        state(reason or 'Esperando runa','MW final')
      end
    end
    if validCandidates==0 then job.wallCandidates=nil end
  end
  function e.tick()
    local job=e.job
    if not job then return end
    local target,own=world.target(job.id),world.player()
    if not own or not target then e.cancel('Objetivo no disponible');return end
    if target.z~=job.floor or own.z~=job.floor then e.cancel('Cambio de piso');return end
    if world.attacking()~=job.id then e.cancel('Cambio de objetivo');return end
    if clock()<job.started or clock()-job.started>60000 then e.cancel('Tiempo agotado');return end
    observe(target,own)
    job=e.job
    if not job then return end
    if world.inPz and world.inPz() and (same(target,job.dest) or job.closingAt) then
      finish('Cierre sin MW (PZ)');return
    end
    if world.paused and world.paused()then state('Bot en pausa');return end
    -- Observe acknowledgements even during manual motion/healing, but never send then.
    if world.manual() then state('Movimiento manual','Push en pausa');return end
    if world.urgent() then state('Prioridad de curacion');return end
    local pending=e.pending
    if pending and pending.action=='push' and pending.spellRecoveryAt and clock()>=pending.spellRecoveryAt
      and same(target,pending.from) then
      -- Map observations above win the race. Replace only the still unchanged
      -- edge, once per approach/adjacent phase, and let the planner revalidate
      -- current positions, obstacles and item turns before another request.
      local edge=spellRecoveryKey(pending)
      if not job.spellRecoveries[edge] then
        job.spellRecoveries[edge]=true;e.stats.spellRecoveries=e.stats.spellRecoveries+1
        local bucket=distanceBucket(pending);if bucket then bucket.recovered=(bucket.recovered or 0)+1 end
        job.spellRecoveryFor={from=copy(pending.from),to=copy(pending.to)}
        -- Repeating a far native move repeats its interrupted server approach.
        -- Walk to the actual adjacent tile first, then request the push there.
        if pending.extra and pending.extra.distancePush then job.distanceFallback=copy(target) end
        result(pending,'requeued after own spell');job.readyAt=0
        state('Reanudando tras spell','Acercamiento y posiciones revalidados; sin confirmar movimiento')
        pending=nil
      end
    end
    if config.distanceCleanup and pending and pending.action=='fire' and clock()-pending.at>=40
      and same(target,pending.from)and same(own,pending.own)and job.route and job.route[1]then
      local dest=job.route[1];local sourceTile,destTile=tile(target),tile(dest)
      local correlated=sourceTile and (not sourceTile.field or sourceTile.fire
        and(pending.fireEvent or sourceTile.field~=pending.extra.field))
      if distance(own,target)>1 and distance(own,target)<=5 and distance(target,dest)==1 and not same(own,dest)
        and sourceTile and sourceTile.safe and not sourceTile.hard and not sourceTile.wall and not sourceTile.other and correlated
        and destTile and destTile.safe and destTile.walkable and not destTile.hard and not destTile.wall
        and not destTile.other and not destTile.field and not destinationNeedsDisintegrate(destTile)then
        markFireProbe(pending,sourceTile)
        result(pending,'paired fire move probe');job.readyAt=0
      end
    end
    if config.pairedCleanup and pending and pending.action=='disintegrate'and clock()-pending.at>=40
      and same(target,pending.from)and same(own,pending.own)and job.route and job.route[1]then
      local dest=job.route[1];local sourceTile,destTile=tile(target),tile(dest)
      local cleansSource=same(pending.to,target)
      if distance(own,target)<=1 and not same(own,dest)and distance(target,dest)==1
        and sourceTile and sourceTile.safe and not sourceTile.hard and not sourceTile.wall and not sourceTile.other and not sourceTile.field
        and destTile and destTile.safe and destTile.walkable and not destTile.hard and not destTile.wall and not destTile.other and not destTile.field
        and(cleansSource or same(pending.to,dest))
        and(cleansSource or (sourceTile.trash or 0)==0)
        and(not cleansSource or not destinationNeedsDisintegrate(destTile))then
        markDisintegrateProbe(pending)
        result(pending,'paired move probe') -- A request is not a rune/map acknowledgement.
        job.readyAt=0
      end
    end
    if e.pending then
      if e.pending.action=='push' and same(e.pending.to,job.dest) and not job.wallCandidates then
        job.previous=copy(e.pending.from)
        job.wallCandidates=wallCandidates(job.dest,own)
        job.wallFor=copy(job.dest);job.wallOwn=copy(own)
      end
      return
    end
    if not job.closingAt and not same(target,job.last) then
      -- A late acknowledgement or another real displacement invalidates the
      -- old retry delay as well as its path. Continue from the observed tile.
      job.route=nil;job.search=nil;job.wallCandidates=nil
      job.last=copy(target);job.readyAt=0
      job.distanceFallback=nil
    end
    if clock()<job.readyAt then return end
    if job.failures>=8 then e.cancel('Intentos agotados');return end
    if same(target,job.dest) or job.closingAt then close(target,own);return end
    local endTile=tile(job.dest)
    if endTile and endTile.wall then
      job.waitingWall=true;state('Esperando wall','Destino temporalmente cerrado');return
    end
    job.waitingWall=nil
    -- Matching acknowledgements already consumed the route in observe(). Any
    -- external displacement was invalidated before the retry gate above.
    local route=job.route or search(target)
    if not e.job or not route or #route==0 then return end
    local destination=route[1]
    if distance(target,destination)~=1 then
      job.route=nil;job.search=nil;state('Ruta desactualizada','Recalculando');return
    end
    local t=tile(destination)
    if not available(t) then job.route=nil;job.search=nil;state('Ruta obstruida');return end
    local source=tile(target)
    if job.retreatWanted then
      local wanted=job.retreatWanted;job.retreatWanted=nil
      if same(wanted,target)and distance(own,target)==1 and job.retreatFor~=key(target)then
        job.retreatFor=key(target)
        local direction,to
        if world.retreatStep then direction,to=world.retreatStep(target,destination)end
        local back=to and tile(to)
        if direction~=nil and to and distance(own,to)==1 and distance(to,target)==2 and not same(to,destination)
          and back and back.safe and back.walkable and not back.hard and not back.other and not back.field and not back.wall
          and(back.trash or 0)==0 and not(world.moving and world.moving())then
          job.distanceFallback=nil;state('Retroceso de 1 SQM','Reintentando desde distancia')
          send('walk',own,to,{direction=direction,retreat=true,own=copy(own),targetFrom=copy(target)});return
        end
      end
    end
    if source and source.field and (config.allowFire==false or config.distanceCleanup and not ownFire(target,source)) then
      if not approach(target,destination,5)then return end
      clean('destroy',target,source);return
    end
    if t.field then
      -- Borrow the stable cleaner's actual Destroy range: do not require
      -- reaching the player before clearing a field already in rune range.
      if not approach(destination,target,5) then return end
      clean('destroy',destination,t);return
    end
    if config.sourceAntipushPriority and destinationNeedsDisintegrate(t)then
      -- Prepare an actually non-walkable landing before spending the final
      -- anti-push rune under the player. A walkable landing never enters here.
      if not approach(destination,target,1)then return end
      clean('disintegrate',destination,t);return
    end
    if source and (source.trash or 0)>0 then
      local anti=job.anti[key(target)]
      local probe=anti and anti.probe and not anti.blocked
      local range=config.distanceCleanup and not probe and (tonumber(config.pushMaxRuneId)or 0)>0
        and not(anti and anti.fireTried) and not same(job.distanceFallback,target) and 5 or 1
      if not(probe and config.distanceCleanup) and not approach(target,destination,range) then return end
      if not clearSource(target,source) then return end
    end
    local prior=job.anti[key(destination)]
    if destinationNeedsDisintegrate(t) and not(config.pairedCleanup and prior and prior.disintegrate and prior.probe and not prior.blocked and same(prior.from,target))then
      -- Disintegrate has a short range on standard servers: stand beside the destination too.
      if not approach(destination,target,1) then return end
      clean('disintegrate',destination,t);return
    end
    local pushRange=config.preferDistance and not same(job.distanceFallback,target)
      and math.max(1,math.min(5,tonumber(config.distanceRange)or 5))or 1
    if not approach(target,destination,pushRange) then return end
    -- In-range coordinates suffice for a move request. Walking animations can
    -- outlive position acknowledgements; waiting for them adds a pause per SQM.
    local distancePush=distance(own,target)>1
    state((distancePush and 'Empujando a distancia 'or 'Empujando ')..(job.pushed+1)..'/'..(job.pushed+#route))
    send('push',target,destination,{from=copy(target),distancePush=distancePush,
      fireSourceField=ownFire(target,source)and source.field or nil})
  end
  function e.snapshot()
    local out={engineRevision=config.revision or(config.preferDistance and 'R129-Sabuezo'or config.pairedCleanup and 'R128-Sabuezo'or 'R118'),status=e.status,detail=e.detail,active=e.job~=nil,stats={},attempts={},timings={},pushByDistance={}}
    out.responsePolicy={enabled=config.adaptivePushAck==true,minimumSamples=6,maxSamples=8,maxAgeMs=120000,fallbackPauseMs=30000,profiles={},
      spellRecovery={enabled=config.recoverAfterSpell==true,minimumGraceMs=100,maximumGraceMs=300,maxPerEdge=2,maxPerPhase=1}}
    for id,profile in pairs(e.responseProfiles)do
      out.responsePolicy.profiles[id]={samples=#profile.samples,suspendedUntil=profile.suspendedUntil}
    end
    for sqm,bucket in pairs(e.pushByDistance)do
      local b={};for k,v in pairs(bucket)do
        if k~='recent'then b[k]=v end
      end
      b.recent={};for i,v in ipairs(bucket.recent)do b.recent[i]=v end
      b.mean=b.observed>0 and math.floor(b.total/b.observed)or nil
      out.pushByDistance[sqm]=b
    end
    for action,t in pairs(e.timings)do
      local recent={};for i,ms in ipairs(t.recent)do recent[i]=ms end
      out.timings[action]={count=t.count,min=t.min,max=t.max,mean=math.floor(t.total/t.count),recent=recent,
        acknowledgementWindow=acknowledgementWindow(action)}
    end
    for k,v in pairs(e.stats) do
      if type(v)=='table' then out.stats[k]={};for a,b in pairs(v) do out.stats[k][a]=b end
      else out.stats[k]=v end
    end
    for i,v in ipairs(e.attempts) do
      out.attempts[i]={}
      for k,a in pairs(v) do out.attempts[i][k]=type(a)=='table' and copy(a) or a end
    end
    if e.job then
      out.job={number=e.job.number,target=e.job.id,destination=copy(e.job.dest),pushed=e.job.pushed,
        phase=e.job.closingAt and 'wall' or 'push',started=e.job.started}
    end
    return out
  end
  return e
end
