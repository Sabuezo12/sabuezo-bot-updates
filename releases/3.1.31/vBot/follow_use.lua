-- Change 113: Ctrl+Shift+right click on the game map = the leader uses that
-- object (lever, ladder, door, grate...) and, over Navi, the characters that
-- follow it with Combo Follow use the same object ("Usar objetos del leader").
-- Loaded by vBot/combo_plus.lua, which binds its Follow helpers with U.bind.
local U={}
ComboFollowUse=U

local RANGE=14            -- followers act within this many SQM, same floor
local ORDER_TTL=20000     -- an order older than this is dropped
local LEADER_WAIT=10000   -- leader: announce once it reaches the object
local VERIFY_MS=1500      -- follower: no error in this time = done
local RETRY_MS=700        -- follower: pause before a retry after an error
local MAX_TRIES=3
local WALK_GIVEUP=12000   -- follower: then try once from where it stands
local SAME_ID_RADIUS=2    -- object moved: same ID this close to the click

local host
local seq=0
local leader={}           -- pending announcement {pos,item,at,id,z}
local state={queue={},seen={},seenIds={}}
U.state=state

local function clock()
  if now then return now end
  if g_clock and g_clock.millis then return g_clock.millis() end
  return 0
end
local function lower(value) return tostring(value or ''):lower():match('^%s*(.-)%s*$') end
local function copy(p) return p and {x=p.x,y=p.y,z=p.z} end
local function dist(a,b)
  if not a or not b or a.z~=b.z then return 999 end
  return math.max(math.abs(a.x-b.x),math.abs(a.y-b.y))
end
local function selfPosition()
  local ok,pos=pcall(function() return player:getPosition() end)
  return ok and type(pos)=='table' and copy(pos) or nil
end
local function log(text,detail)
  if RinoConsole and type(RinoConsole.log)=='function' then
    pcall(RinoConsole.log,'action','Combo Follow',text,detail)
  end
end
local function call(method,...)
  if g_game and type(g_game[method])=='function' then return pcall(g_game[method],...) end
  return false
end
local function itemId(thing)
  local ok,id=pcall(function() return thing:getId() end)
  return ok and tonumber(id) or nil
end
local function isCreature(thing)
  local ok,value=pcall(function() return thing:isCreature() end)
  return ok and value==true
end
local function tileAt(pos)
  if not g_map or type(g_map.getTile)~='function' then return nil end
  local ok,tile=pcall(g_map.getTile,pos)
  return ok and tile or nil
end
local function items(tile)
  local ok,list=pcall(function() return tile:getItems() end)
  return ok and type(list)=='table' and list or {}
end

-- The object on that tile with that ID (ground included).
local function itemOn(pos,id)
  local tile=tileAt(pos)
  if not tile then return nil,nil end
  for _,item in ipairs(items(tile))do
    if itemId(item)==id then return item,tile end
  end
  local ok,ground=pcall(function() return tile:getGround() end)
  if ok and ground and itemId(ground)==id then return ground,tile end
  return nil,tile
end

-- Non-ground objects on the tile (a lever pulled or a door opened is still there
-- with another ID; an empty tile means the object is elsewhere).
local function hasObjects(tile)
  for _,item in ipairs(items(tile))do
    local ok,floor=pcall(function() return item:isGround() or item:isGroundBorder() end)
    if ok and not floor then return true end
  end
  return false
end

-- Where to use it: the clicked tile; if that tile is empty now, the nearest
-- object with the same ID next to it. nil + 'changed' when it changed state.
local function target(order,origin)
  local item,tile=itemOn(order.pos,order.item)
  if item then return item,order.pos end
  if not tile then return nil,nil,'unknown' end
  if hasObjects(tile) then return nil,nil,'changed' end
  local best,bestPos
  for dx=-SAME_ID_RADIUS,SAME_ID_RADIUS do
    for dy=-SAME_ID_RADIUS,SAME_ID_RADIUS do
      local pos={x=order.pos.x+dx,y=order.pos.y+dy,z=order.pos.z}
      local found=(dx~=0 or dy~=0) and itemOn(pos,order.item)
      if found and (not bestPos or dist(origin,pos)<dist(origin,bestPos)) then best,bestPos=found,pos end
    end
  end
  if best then return best,bestPos end
  return nil,nil,'missing'
end

local function useThing(thing)
  if type(use)=='function' then
    local ok,result=pcall(use,thing)
    if ok and result~=false then return true end
  end
  local ok=call('use',thing)
  return ok==true
end

function U.bind(functions)
  host=functions
end

local function enabled()
  return host and host.settings and host.settings.followUse~=false
end

----------------------------------------------------------------- leader side
local function announce(pending)
  leader.pending=nil
  if not BotServer or type(BotServer.announceFollowUse)~='function' then return end
  local ok,sent=pcall(BotServer.announceFollowUse,pending.id,pending.pos,pending.item)
  log(ok and sent and ('Objeto usado: aviso a los followers (ID '..pending.item..')') or
    'Objeto usado; Navi no esta conectado, los followers no reciben el aviso')
end

-- Announce once the leader stands next to it (the server walks it there when
-- clicked from afar), it changed floor, or the object changed state.
function U.leaderTick()
  local pending=leader.pending
  if not pending then return end
  local time=clock()
  if time-pending.at>LEADER_WAIT then
    leader.pending=nil
    log('Objeto no alcanzado en 10 s: no aviso a los followers')
    return
  end
  local pos=selfPosition()
  if not pos then return end
  local item=itemOn(pending.pos,pending.item)
  if dist(pos,pending.pos)<=1 or pos.z~=pending.z or not item then announce(pending) end
end

function U.leaderClick(tile)
  if not enabled() or not tile then return false end
  local okThing,thing=pcall(function() return tile:getTopUseThing() end)
  local okPos,pos=pcall(function() return tile:getPosition() end)
  if not okThing or not thing or isCreature(thing) or not okPos or not pos then return false end
  local id=itemId(thing)
  if not id or id<1 or id>65535 then return false end
  local time=clock()
  if leader.lastClick and time-leader.lastClick<250 then return true end
  leader.lastClick=time
  if not useThing(thing) then return true end
  local me=selfPosition()
  seq=seq+1
  leader.pending={pos=copy(pos),item=id,at=time,id=tostring(math.floor(time))..':'..seq,z=me and me.z or pos.z}
  if me and dist(me,pos)<=1 then announce(leader.pending) end
  return true
end

local function modifiers()
  local kb=g_keyboard
  if not kb then return false end
  local function pressed(name)
    if type(kb[name])~='function' then return false end
    local ok,value=pcall(kb[name])
    return ok and value==true
  end
  return pressed('isCtrlPressed') and pressed('isShiftPressed') and not pressed('isAltPressed')
end

local function rightButton(button)
  return button==(MouseRightButton or 2)
end

function U.onMapPress(widget,mousePos,mouseButton)
  if not enabled() or not rightButton(mouseButton) or not modifiers() then return false end
  local tile
  if widget and type(widget.getTile)=='function' then
    local ok,value=pcall(widget.getTile,widget,mousePos)
    if ok then tile=value end
  end
  if not tile and type(getTileUnderCursor)=='function' then
    local ok,value=pcall(getTileUnderCursor)
    if ok then tile=value end
  end
  return U.leaderClick(tile)
end

-- Hook only Ctrl+Shift+right click on the map widget; anything else goes on to
-- the client's own handler. A hook from an older bot load is unwrapped, or, if
-- something wrapped it meanwhile, it just passes the event on.
local function install()
  local gi=modules and modules.game_interface
  if not gi then return false end
  local map
  if type(gi.getMapPanel)=='function' then
    local ok,value=pcall(gi.getMapPanel)
    if ok then map=value end
  end
  map=map or gi.gameMapPanel
  if not map then return false end
  local old=map.rinoFollowUseHook
  local previousPress,previousRelease=map.onMousePress,map.onMouseRelease
  if old and previousPress==old.press then previousPress=old.previousPress end
  if old and previousRelease==old.release then previousRelease=old.previousRelease end
  local hook={previousPress=previousPress,previousRelease=previousRelease}
  hook.press=function(widget,mousePos,mouseButton)
    if map.rinoFollowUseHook==hook then
      local ok,used=pcall(U.onMapPress,widget,mousePos,mouseButton)
      if ok and used then
        widget.allowNextRelease=false
        hook.swallow=clock()+3000
        return true
      end
    end
    if hook.previousPress then return hook.previousPress(widget,mousePos,mouseButton) end
    return false
  end
  hook.release=function(widget,mousePos,mouseButton)
    if map.rinoFollowUseHook==hook and hook.swallow and rightButton(mouseButton) then
      local active=clock()<=hook.swallow
      hook.swallow=nil
      if active then return true end
    end
    if hook.previousRelease then return hook.previousRelease(widget,mousePos,mouseButton) end
    return false
  end
  map.rinoFollowUseHook=hook
  map.onMousePress=hook.press
  map.onMouseRelease=hook.release
  return true
end
local okInstall,installed=pcall(install)
U.installed=okInstall and installed==true

--------------------------------------------------------------- follower side
function U.clear(reason)
  local order=state.active
  state.active=nil
  if order and host then pcall(host.stopSearch,true) end
  if order and reason then log('Objeto del leader: '..reason) end
end

-- A Follow pause (manual movement, safety escape, stamina, flee, Pausar Bot) drops the order
-- and the queue: they are not carried out after the pause.
function U.drop(reason)
  local had=state.active~=nil or #state.queue>0
  state.queue={}
  U.clear(had and reason or nil)
end

function U.onNavi(sender,message)
  if not enabled() or not host.settings.followEnabled then return end
  if type(sender)~='string' or lower(sender)~=lower(host.getFollowName()) then return end
  if type(message)~='table' or message.v~=1 or type(message.id)~='string' or #message.id>32 or
      not message.id:match('^%d+:%d+$') then return end
  local item=tonumber(message.item)
  local pos=host.validPosition and host.validPosition(message.pos)
  if not item or item%1~=0 or item<1 or item>65535 or not pos then return end
  local origin=selfPosition()
  if not origin or dist(origin,pos)>RANGE then return end
  local key=lower(sender)..':'..message.id
  if state.seen[key] or #state.queue>=4 then return end
  state.seen[key]=true
  state.seenIds[#state.seenIds+1]=key
  if #state.seenIds>32 then state.seen[table.remove(state.seenIds,1)]=nil end
  state.queue[#state.queue+1]={leader=lower(sender),pos=pos,item=item,expires=clock()+ORDER_TTL}
end

local function failed(text)
  text=lower(text)
  for _,needle in ipairs({'not possible','there is no way','exhausted','cannot use','too far','first go',
      'no es posible','no hay camino','agotado','no puedes usar','muy lejos'})do
    if text:find(needle,1,true) then return true end
  end
  return false
end
if type(onTextMessage)=='function' then
  onTextMessage(function(mode,text)
    local order=state.active
    if order and order.sentAt and type(text)=='string' and failed(text) then order.failedAt=clock() end
  end)
end

local function begin(order,time)
  state.active=order
  order.startAt=time;order.nextAt=0;order.tries=0;order.walkFails=0
  host.stopSearch(true)
  host.stopSpacing()
  pcall(host.invalidate)
  call('cancelFollow')
  call('stop')
  host.setStatus('Usando objeto del leader (ID '..order.item..')')
end

local function walking()
  local ok,value=pcall(function() return player:isWalking() end)
  return ok and value==true
end

-- true while an order owns the follower (Follow waits).
function U.busyUntil()
  return state.active and state.active.expires or nil
end

function U.tick(name,origin,time)
  if not host or not origin then return false end
  -- The Follow macro paused (manual movement, safety escape, stamina...):
  -- an order interrupted that way is not resumed later.
  if state.lastTick and time-state.lastTick>1500 then U.drop('interrumpido por una pausa') end
  state.lastTick=time
  if not enabled() then state.queue={};U.clear();return false end
  local order=state.active
  if not order then
    -- Busy (boat, NPC visit): the queue waits; its orders still expire after ORDER_TTL.
    if host.isBusy and host.isBusy() then return false end
    order=table.remove(state.queue,1)
    while order and (time>=order.expires or order.leader~=lower(name)) do order=table.remove(state.queue,1) end
    if not order then return false end
    if origin.z~=order.pos.z or dist(origin,order.pos)>RANGE then return false end
    begin(order,time)
  end
  if order.leader~=lower(name) then U.clear('cambio el jugador a seguir');return false end
  if time>=order.expires then U.clear('tiempo agotado sin usarlo');return false end
  if order.sentAt then
    -- Done: floor change or teleport, or the object changed state.
    local movedAway=not order.remote and dist(origin,order.from)>1
    if origin.z~=order.from.z or movedAway or not itemOn(order.usedPos,order.item) then
      U.clear('usado (ID '..order.item..')');return false
    end
    if order.failedAt then
      if order.tries>=MAX_TRIES then U.clear('el servidor no dejo usarlo tras '..order.tries..' intentos');return false end
      order.sentAt=nil;order.failedAt=nil;order.nextAt=time+RETRY_MS
      host.setStatus('Objeto del leader: reintentando')
      return true
    end
    if time-order.sentAt>=(order.remote and 4000 or VERIFY_MS) then U.clear('usado (ID '..order.item..')');return false end
    return true
  end
  if origin.z~=order.pos.z then U.clear('estoy en otro piso');return false end
  if time<order.nextAt then return true end
  local thing,pos,why=target(order,origin)
  if why=='changed' then U.clear('ya cambio de estado (palanca movida o puerta abierta), no lo uso');return false end
  if why=='missing' then U.clear('ya no esta en su sitio');return false end
  local goal=pos or order.pos
  local gap=dist(origin,goal)
  local remote=false
  if gap>1 then
    if time-order.startAt<WALK_GIVEUP and order.walkFails<8 then
      host.setStatus('Caminando al objeto del leader (ID '..order.item..')')
      if not host.walk(goal,1,time,'use') then order.walkFails=order.walkFails+1 end
      return true
    end
    if not thing then U.clear('no consigo llegar');return false end
    remote=true -- the server walks there by itself on most OT servers
  elseif not thing then
    U.clear('no lo veo en su sitio');return false
  end
  if not remote and walking() then return true end
  host.stopSearch(true)
  if not useThing(thing) then U.clear('el cliente no pudo usarlo');return false end
  order.tries=order.tries+1;order.sentAt=time;order.failedAt=nil
  order.from=copy(origin);order.usedPos=copy(goal);order.remote=remote
  host.setStatus('Usando objeto del leader (ID '..order.item..')')
  return true
end

if type(macro)=='function' then macro(100,function() pcall(U.leaderTick) end) end

return U
