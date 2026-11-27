setDefaultTab('Tools')
local H=Helper
local core=modules.corelib or modules.game_bot or{}
local nativeApp=core.g_app or g_app
local nativeWindow=core.g_window or g_window
local platform=core.g_platform or g_platform
local resources=core.g_resources or g_resources
local nativeIO,nativeOS=core.io or io,core.os or os
local nativeClock=core.g_clock or g_clock
local scheduleNative=core.scheduleEvent or modules.game_bot.scheduleEvent
local removeNative=core.removeEvent or modules.game_bot.removeEvent
local connectNative,disconnectNative=core.connect,core.disconnect
RinoAfkGraphics.releasePrevious({app=nativeApp,debug=core.debug,getfenv=core.getfenv})
local function clock()return nativeClock and nativeClock.millis and nativeClock.millis()or os.time()*1000 end
local function map()
 local module=modules.game_interface
 return module and type(module.getMapPanel)=='function'and module.getMapPanel()or nil
end
storage.helperAfk=type(storage.helperAfk)=='table'and storage.helperAfk or{}
local config=storage.helperAfk
local panel=UI.createWidget('AfkModePanel')
local window=UI.createWindow('AfkModeWindow');window:hide()
local graphics=RinoAfkGraphics.new({app=nativeApp,map=map})
local fallback={state='active',lastInput=clock(),manual=false}
local engine,bridge,stopped,event,runtime,cleanup
local function human()
 fallback.lastInput=clock()
 if fallback.state=='afk'then fallback.state='wake'end
 if engine and engine.active and engine.state=='afk'and type(nativeWindow.hasFocus)=='function'and nativeWindow.hasFocus()then engine.wake()end
end
local function fallbackRead(minutes)
 local focused=type(nativeWindow.hasFocus)=='function'and nativeWindow.hasFocus()
 local point=type(nativeWindow.getMousePosition)=='function'and nativeWindow.getMousePosition()
 if focused and(not fallback.focused or(point and fallback.point and(point.x~=fallback.point.x or point.y~=fallback.point.y)))then human()end
 fallback.focused=focused;fallback.point=point
 if fallback.state=='active'and clock()-fallback.lastInput>minutes*60000 then fallback.state='prepare'end
 return{state=fallback.state,fresh=true,limited=true}
end
local configName=modules.game_bot.contentsPanel.config:getCurrentOption().text
local prefix='/bot/'..configName
bridge=RinoAfkWindows.new({io=nativeIO,os=nativeOS,clock=clock,platform=platform,
 source=function()return resources.readFileContents(prefix..'/vBot/afk_windows_source.txt')end,
 label=function()return g_game.getCharacterName()end,
 privateFolder=function()
  local path=prefix..'/_helper_afk';resources.makeDir(path)
  return resources.getWriteDir():gsub('[/\\]+$','')..path
 end,
 fallback=fallbackRead,
 fallbackCommand=function(command)
  if command=='afk'then fallback.state='prepare'
  elseif command=='ready'then fallback.state='afk'
  elseif command=='auto'then fallback.state='active';fallback.lastInput=clock()
  elseif command=='wake'or command=='release'then fallback.state='active';fallback.lastInput=clock()end
  return true
 end})
local function restore(confirmed)
 graphics.restore()
 -- A wake reported by the companion already showed the window with its real
 -- state. g_window.show() would use the client's own flag, which is stale for
 -- a window minimized before AFK. Keep it only as rescue (failure/reload/off).
 if not confirmed and not bridge.unavailable and type(nativeWindow.show)=='function'then pcall(nativeWindow.show)end
end
local function running(bot)
 if type(bot)~='table'or type(bot.isOn)~='function'then return false end
 local ok,on=pcall(bot.isOn);return ok and on==true
end
engine=RinoAfkEngine.new({config=config,clock=clock,
 -- CaveBot or TargetBot ON: no Windows power saving (EcoQoS/priority) in AFK.
 busy=function()return running(CaveBot)or running(TargetBot)end,
 start=function(minutes)
  fallback.lastInput=clock();fallback.state='active'
  if type(nativeWindow.isFullscreen)=='function'and nativeWindow.isFullscreen()then bridge.unavailable=true;return true end
  return bridge.start(minutes)
 end,
 command=bridge.send,read=bridge.read,
 enter=graphics.enter,maintain=graphics.maintain,restore=restore,
 hide=function()
  if bridge.unavailable then fallback.state='afk';return true end
  -- Fullscreen keeps its window visible; the companion still manages power.
  if type(nativeWindow.isFullscreen)=='function'and nativeWindow.isFullscreen()then return false end
  -- The companion hides it on 'ready' and keeps the Win32 maximized/minimized
  -- state. g_window.hide() would leave the client's hidden flag set after a
  -- tray restore (later resize/move would hide it again); drawing ignores it.
  return true
 end,
 release=function()bridge.release();fallback.state='active';fallback.lastInput=clock()end,
 rescue=bridge.rescue})
runtime={controller=engine,bridge=bridge,graphics=graphics,panel=panel,window=window}
AfkMode=runtime
function AfkMode.isOn()return config.enabled==true end
local messages={off='Desactivado',loading='Preparando ahorro...',entering='Activando modo AFK...',active='Ahorro automatico preparado',
 afk='Modo AFK activo',limited='Ahorro parcial: bandeja no disponible'}
local lastState
local function refresh()
 local state=engine.state..':'..tostring(config.enabled)..':'..tostring(bridge.unavailable)..':'..tostring(engine.relaxed)
 if state==lastState then return end;lastState=state
 local message=messages[engine.state]or engine.state
 if engine.state=='afk'and engine.relaxed and not bridge.unavailable then message='Modo AFK activo (CPU completa para el bot)'end
 if bridge.unavailable and engine.state=='active'then message='Ahorro grafico preparado; bandeja no disponible'end
 panel.title:setOn(config.enabled==true);window.enabled:setOn(config.enabled==true)
 panel.status:setText(message);window.status:setText(message)
end
function AfkMode.setOn()engine.setEnabled(true);refresh()end
-- Double click on the floating "Modo AFK" icon: turn it on and enter now.
function AfkMode.enterNow()engine.enterNow();refresh();return engine.failed~=true end
function AfkMode.setOff()engine.setEnabled(false);refresh()end
local function toggle()engine.setEnabled(not config.enabled);refresh()end
panel.title.onClick=toggle;window.enabled.onClick=toggle
window.minutes:setValue(config.minutes)
window.minutes.onValueChange=function(_,v)engine.setMinutes(v)end
panel.settings.onClick=function()refresh();window:show();window:raise();window:focus()end
AfkMode.open=panel.settings.onClick
window.enterNow.onClick=function()engine.enterNow();refresh()end
window.wake.onClick=function()engine.wake();refresh()end
window.closeButton.onClick=function()window:hide()end;window.onEscape=window.closeButton.onClick
local root=g_ui.getRootWidget()
local inputs={onKeyPress=human,onMousePress=human,onMouseWheel=human}
local game=core.g_game or g_game
local gameEvents={onGameEnd=function()if cleanup then cleanup()end end}
if type(connectNative)=='function'then
 connectNative(root,inputs);connectNative(game,gameEvents)
end
cleanup=function()
 if stopped then return end;stopped=true
 pcall(engine.dispose)
 if nativeApp._rinoAfkRuntime==runtime then nativeApp._rinoAfkRuntime=nil end
 if event and type(removeNative)=='function'then pcall(removeNative,event)end
 if type(disconnectNative)=='function'then pcall(disconnectNative,root,inputs);pcall(disconnectNative,game,gameEvents)end
end
local previous=H and H.unbind
if H then H.unbind=function(...)cleanup();if previous then return previous(...)end end end
AfkMode.dispose=cleanup
nativeApp._rinoAfkRuntime=AfkMode
local function tick()
 if stopped then return end
 local ok=pcall(function()
  if nativeApp._rinoAfkRuntime~=runtime or(H and not H.valid())or panel:isDestroyed()then cleanup();return end
  engine.tick();refresh()
 end)
 if not ok then cleanup();return end
 if not stopped and type(scheduleNative)=='function'then event=scheduleNative(tick,config.enabled and 250 or 1500)end
end
tick()
