-- Count the native local-player death event, not a sampled HP percentage.
-- All persisted fields are ordinary bot storage; never retain player userdata.
local C=CaveBot.Config
local safety=C.safety
local D={}
C.Deaths=D
local closed=false
local seenAlive=false
local hooks={}
local shared=modules and modules.game_bot

if safety.deathTrackerVersion~=1 then
  -- The old wasDead flag meant HP <= 1%, including living players. It was
  -- not evidence of a counted death and cannot be imported as one.
  safety.deathTrackerVersion=1
  safety.deathCounted=false
  safety.wasDead=false
  safety.pendingDeathPolicy=false
end

function D.persist()
  if type(saveConfig)=='function' then pcall(saveConfig) end
end

local function lifeState()
  if type(g_game.isOnline)=='function' and g_game.isOnline()==false then return nil end
  if type(g_game.isDead)=='function' and g_game.isDead()==true then return 'dead' end
  local character
  if type(g_game.getLocalPlayer)=='function' then character=g_game.getLocalPlayer() else character=player end
  if not character then return nil end
  local hp=tonumber(character:getHealth())
  if hp and hp==0 and seenAlive then return 'dead' end
  if hp and hp>0 then seenAlive=true;return 'alive' end
end

local function rearm()
  if safety.deathCounted or safety.wasDead then
    safety.deathCounted=false
    safety.wasDead=false
    D.persist()
  end
end

function D.record(source)
  if closed or safety.deathCounted then return false end
  safety.deathCounted=true
  safety.wasDead=true
  safety.deathCounter=(tonumber(safety.deathCounter) or 0)+1
  safety.lastDeathSource=source
  safety.lastDeathAt=os.time()
  -- Statistics include deaths with CaveBot OFF or the limit disabled. The
  -- existing hunt policy is eligible only if CaveBot was active at death.
  local active=CaveBot.isOn and CaveBot.isOn() or false
  safety.pendingDeathPolicy=safety.pendingDeathPolicy==true or active==true
  D.persist() -- Before an auto-accept/reconnect handler can clear this context.
  C.updateDeathLabel()
  warn('Muerte detectada. Llevas: '..safety.deathCounter)
  return true
end

function D.poll()
  if closed then return false end
  local state=lifeState()
  if state=='dead' then D.record('estado del cliente / HP 0');return false end
  if state=='alive' then rearm();return true end
  return false -- Offline/unknown is neither a death nor proof of revival.
end

function D.takePolicy()
  if safety.pendingDeathPolicy~=true then return false end
  safety.pendingDeathPolicy=false
  D.persist()
  return true
end

function D.cleanup()
  if closed then return end
  closed=true
  for event,callback in pairs(hooks) do
    local listeners=g_game[event]
    if listeners==callback then g_game[event]=nil
    elseif type(listeners)=='table' then
      local remaining={}
      for _,fn in ipairs(listeners) do if fn~=callback then remaining[#remaining+1]=fn end end
      if #remaining==1 then g_game[event]=remaining[1]
      elseif #remaining==0 then g_game[event]=nil
      else g_game[event]=remaining end
    end
  end
  if shared and shared.rinoDeathCounterCleanup==D.cleanup then shared.rinoDeathCounterCleanup=nil end
end

function D.attach(window)
  local previous=window.onDestroy
  window.onDestroy=function(...)
    D.cleanup()
    if type(previous)=='function' then previous(...)
    elseif type(previous)=='table' then for _,fn in ipairs(previous) do fn(...) end end
  end
end

if shared and type(shared.rinoDeathCounterCleanup)=='function' then shared.rinoDeathCounterCleanup() end
if shared then shared.rinoDeathCounterCleanup=D.cleanup end
local function listen(event,callback)
  local listeners=g_game[event]
  -- Observe before death-window/auto-accept listeners can log out or reload.
  if listeners==nil then g_game[event]=callback
  elseif type(listeners)=='function' then g_game[event]={callback,listeners}
  elseif type(listeners)=='table' then
    local ordered={callback}
    for _,fn in ipairs(listeners) do ordered[#ordered+1]=fn end
    g_game[event]=ordered
  else return end
  hooks[event]=callback
end
listen('onDeath',function()D.record('evento onDeath')end)
listen('onGameStart',function()
  seenAlive=false
  if closed or (type(g_game.isOnline)=='function' and g_game.isOnline()==false) then return end
  if type(g_game.isDead)=='function' and g_game.isDead()==true then return end
  -- A new game session is a new life even before its first HP packet arrives.
  rearm()
end)
-- A new bot context commonly starts after onGameStart has already fired.
if lifeState()=='alive' or (type(g_game.isOnline)=='function' and g_game.isOnline()==true and
    type(g_game.isDead)=='function' and g_game.isDead()==false) then rearm() end
