-- Client presentation only. Combat, movement, network and game timers keep running.
RinoAfkEngine={}
function RinoAfkEngine.new(host)
 local E={state='off',active=false,disposed=false,lastTick=host.clock(),enteredAt=0,relaxed=false}
 local cfg=host.config
 cfg.enabled=cfg.enabled==true
 cfg.minutes=math.max(1,math.min(240,math.floor(tonumber(cfg.minutes)or 5)))
 -- confirmed: the companion reported this wake and already showed the window.
 local function restore(confirmed)
  if E.active then pcall(host.restore,confirmed==true);E.active=false end
 end
 local function release()
  restore();pcall(host.release)
 end
 function E.setEnabled(value)
  value=value==true
  if cfg.enabled==value and not E.failed then return end
  release();cfg.enabled=value;E.failed=nil;E.relaxed=false
  E.state=value and'loading'or'off'
  if value then
   local ok,result=pcall(host.start,cfg.minutes)
   if not ok or result==false then E.state='limited';E.failed=true end
  end
 end
 function E.setMinutes(value)
  cfg.minutes=math.max(1,math.min(240,math.floor(tonumber(value)or 5)))
  if cfg.enabled and not E.failed then pcall(host.command,'auto',cfg.minutes)end
 end
 function E.enterNow()
  if not cfg.enabled or E.failed then E.setEnabled(true)end
  if not E.failed then pcall(host.command,'afk',cfg.minutes)end
 end
 function E.wake()
  restore()
  if cfg.enabled and not E.failed then pcall(host.command,'wake',cfg.minutes)end
  E.state=cfg.enabled and(E.failed and'limited'or'active')or'off'
 end
 function E.tick()
  if E.disposed then return end
  local time=host.clock();local gap=time-E.lastTick;E.lastTick=time
  if not cfg.enabled then return end
  if E.failed then
   -- Lost companion: rescue relaunched it; register again later (20 s, 40 s...
   -- up to 5 min) instead of staying limited until the bot is reloaded.
   if E.retryAt and time>=E.retryAt then E.retryAt=nil;E.setEnabled(true)end
   return
  end
  local ok,status=pcall(host.read)
  if not ok or(status and status.failed)then
   release();E.state='limited';E.failed=true;pcall(host.rescue)
   E.retries=(E.retries or 0)+1;E.retryAt=time+math.min(300000,10000*2^E.retries);return
  end
  if not status then return end
  E.retries=0
  if E.active and(status.state=='prepare'or status.state=='afk')and host.maintain then pcall(host.maintain)end
  if status.state=='prepare'then
   if not E.active and status.fresh then
    local painted,reason=pcall(host.enter)
    if not painted or reason==false then
     -- Entry may have changed some graphics before an optional API failed.
     pcall(host.restore);release();E.state='limited';E.failed=true;return
    end
    E.active=true;E.enteredAt=time;E.relaxed=false
    -- A tray icon already exists. Hide only after that acknowledgement.
    local hidden,result=pcall(host.hide)
    if not hidden or result==false then release();E.state='limited';E.failed=true;return end
    host.command('ready',cfg.minutes);E.state='entering'
   end
  elseif status.state=='afk'then
   if not E.active then
    -- Never attach a previous context's AFK state to a new profile.
    host.command('wake',cfg.minutes);E.state='active';return
   end
   E.state='afk'
   -- 'afk' means the companion already hid the window, so relax cannot replace
   -- that command. A hunting bot keeps full CPU: EcoQoS + below normal made the
   -- same Lua work about 1.4x slower. Graphics savings stay in both cases.
   if not E.relaxed then
    local ok,busy=pcall(host.busy)
    if ok and busy==true or time-E.enteredAt>5000 and gap>1000 then
     E.relaxed=true;pcall(host.command,'relax',cfg.minutes)
    end
   end
  elseif status.state=='wake'or status.state=='active'then
   restore(true);E.state='active'
   if status.state=='wake'then host.command('auto',cfg.minutes)end
  elseif status.state=='paused'then
   restore(true);cfg.enabled=false;E.state='off';pcall(host.release)
  end
 end
 function E.dispose()
  if E.disposed then return end
  E.disposed=true;release();E.state='off'
 end
 if cfg.enabled then
  cfg.enabled=false;E.setEnabled(true)
 end
 return E
end
