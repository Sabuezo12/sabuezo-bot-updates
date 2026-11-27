RinoAfkGraphics={}
function RinoAfkGraphics.releasePrevious(host)
 local app=host.app
 if not app then return end
 local previous=app._rinoAfkRuntime
 if type(previous)=='table'and type(previous.dispose)=='function'then pcall(previous.dispose)end
 -- Migrate the first AFK builds, which did not register a runtime owner.
 -- Only recognize our own guard; leave unrelated FPS hooks intact.
 local debug=host.debug;local seen={}
 local function visit(fn,depth)
  if type(fn)~='function'or seen[fn]or depth>6 or not debug or type(debug.getupvalue)~='function'then return end
  seen[fn]=true
  for i=1,24 do
   local ok,name,value=pcall(debug.getupvalue,fn,i)
   if not ok or not name then break end
   if type(value)=='table'and value.fpsGuard==fn and type(value.enter)=='function'and type(value.maintain)=='function'and type(value.saved)=='table'and type(value.restore)=='function'and type(value.fpsSetter)=='function'then
    local normal=value.requestedFps~=1 and value.requestedFps or value.fps
    if type(host.getfenv)=='function'then
     local ok,env=pcall(host.getfenv,fn);local owner=ok and type(env)=='table'and env.AfkMode
     if type(owner)=='table'and owner.graphics==value and type(owner.dispose)=='function'then pcall(owner.dispose)end
    end
    pcall(value.restore)
    if type(normal)=='number'and normal~=1 and type(app.getMaxFps)=='function'and type(app.setMaxFps)=='function'then
     local ok,current=pcall(app.getMaxFps);if ok and current==1 then pcall(app.setMaxFps,normal)end
    end
   elseif type(value)=='function'then visit(value,depth+1)end
  end
 end
 visit(app.setMaxFps,0)
end
function RinoAfkGraphics.new(host)
 local G={saved={},map=nil,active=false}
 local pairs={
  {'getDrawFlags','setDrawFlags',0}, {'getShader','setShader',''},
  {'isDrawingLights','setDrawLights',false}, {'isDrawingNames','setDrawNames',false},
  {'isDrawingTexts','setDrawTexts',false}, {'isDrawingHealthBars','setDrawHealthBars',false},
  {'isDrawingManaBar','setDrawManaBar',false}, {'isDrawingHarmony','setDrawHarmony',false}
 }
 local function call(fn,...)
  if type(fn)~='function'then return false end
  return pcall(fn,...)
 end
 function G.enter()
  if G.active then return true end
  G.active=true;G.saved={};G.map=host.map()
  local app=host.app
  if app then
   local previous=app._rinoAfkGraphics
   if previous and previous~=G and type(previous.restore)=='function'then pcall(previous.restore)end
   app._rinoAfkGraphics=G
   local ok,value=call(app.getMaxFps)
   if ok and type(value)=='number'and type(app.setMaxFps)=='function'then
    G.fps=value;local setter=app.setMaxFps;G.fpsSetter=setter;G.requestedFps=nil
    -- Thornia's options timer reapplies its cap repeatedly, even when hidden.
    -- Own this setter only for the AFK interval and retain the latest request
    -- for restoration. Gameplay dispatchers are independent of this cap.
    local guard
    guard=function(v,...)
     if G.active and G.fpsGuard==guard and app._rinoAfkGraphics==G then
      if type(v)=='number'then G.requestedFps=v end
      return setter(1,...)
     end
     return setter(v,...)
    end
    G.fpsGuard=guard
    app.setMaxFps=G.fpsGuard
    call(G.fpsSetter,1) -- zero means unlimited, never use it for AFK.
   end
  end
  if G.map then
   for _,p in ipairs(pairs)do
    local ok,value=call(G.map[p[1]],G.map)
    if ok and value~=nil and type(G.map[p[2]])=='function'then
     local applied=call(G.map[p[2]],G.map,p[3])
     if applied then G.saved[#G.saved+1]={getter=p[1],setter=p[2],before=value,applied=p[3]}end
    end
   end
  end
  return true
 end
 function G.maintain()
  -- Thornia reapplies its usual FPS cap on focus changes after hide().
  -- Reapply only that saved value, preserving unrelated later changes.
  if not G.active or G.fps==nil or not host.app then return end
  local ok,value=call(host.app.getMaxFps)
  if ok and value==G.fps and value~=1 then call(G.fpsSetter,1)end
 end
 function G.restore()
  if not G.active then return end
  G.active=false
  local app=host.app
  local owned=app and app._rinoAfkGraphics==G
  if app and app.setMaxFps==G.fpsGuard then app.setMaxFps=G.fpsSetter end
  if owned and G.fps~=nil then
   local ok,value=call(app.getMaxFps)
   -- A client can echo the current AFK cap back through its options timer.
   -- That echo must not replace the normal cap captured before AFK.
   local normal=G.requestedFps~=1 and G.requestedFps or G.fps
   if ok and value==1 then call(app.setMaxFps,normal)end
  end
  if owned then app._rinoAfkGraphics=nil end
  local ok,current=pcall(host.map);if not ok then current=nil end
  -- Only query the current live map; never dereference a cached old widget.
  if current and current==G.map then
   for i=#G.saved,1,-1 do
    local p=G.saved[i];local ok,value=call(current[p.getter],current)
    if ok and value==p.applied then call(current[p.setter],current,p.before)end
   end
  end
  G.fps=nil;G.map=nil;G.saved={}
 end
 return G
end
