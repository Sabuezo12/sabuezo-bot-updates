-- Follow en espera (change 214). After a death, or with the leader too far away to reach by
-- walking (another city), Follow stops chasing him and waits until he is on screen again;
-- then it follows as usual. Only the rules and the saved state live here: vBot/combo_plus.lua
-- binds the context and calls W.check() from its Follow loop. The state is kept in the Follow
-- settings, so the reload that comes after a death (relog) keeps waiting.
HelperFollowWait = {}
local W = HelperFollowWait
W.FAR_SQM = 200     -- leader this far by Navi (x/y, any floor)...
W.FAR_MS = 10000    -- ...for this long: walking there is not following him any more.
W.CHECK_MS = 500    -- how often the Navi distance is read
local ctx, farSince, farCheckAt

local function settings() return ctx and ctx.settings end
local function lower(text) return tostring(text or ''):lower() end
local function state()
  local s = settings()
  local value = s and s.followWait
  if type(value) == 'table' and (value.reason == 'death' or value.reason == 'far') and
    type(value.name) == 'string' then return value end
end
local function note(text)
  if type(info) == 'function' then pcall(info, '[Combo Follow] ' .. text) end
  if RinoConsole and RinoConsole.log then pcall(RinoConsole.log, 'action', 'Combo Follow', text) end
end
local function deathCount()
  local count = ctx and ctx.deaths and tonumber(ctx.deaths())
  return count
end

function W.bind(value) ctx = value end
-- The option "Esperar a ver al leader si muero o se va lejos" (ON unless switched OFF).
function W.enabled() local s = settings(); return s ~= nil and s.followWaitSight ~= false end
function W.isWaiting() return W.enabled() and state() ~= nil end
function W.reason() local s = W.isWaiting() and state(); return s and s.reason or nil end

-- Forget the wait. The death counter is taken as seen, so a death from before (Follow OFF,
-- another leader) never starts a new wait later.
function W.clear(why)
  farSince = nil
  local s = settings()
  if not s then return end
  local count = deathCount()
  if count then s.followDeaths = count end
  local old = state()
  s.followWait = nil
  if old and why then note(why) end
end

local function start(reason, name, gap)
  local s = settings(); if not s then return end
  local old = state()
  if old and old.reason == reason and old.name == lower(name) then return end
  s.followWait = {reason = reason, name = lower(name), at = os.time(), gap = gap}
  farSince = nil
  if ctx.stop then pcall(ctx.stop) end
  if reason == 'death' then
    note('En espera: moriste. El Follow no busca a ' .. name .. ' hasta verlo en pantalla.')
  else
    note('En espera: ' .. name .. ' esta a ' .. tostring(gap) .. ' SQM, demasiado lejos para seguirlo ' ..
      'caminando. El Follow sigue cuando lo veas.')
  end
end

function W.noteDeath(name)
  if W.enabled() and lower(name) ~= '' then start('death', name) end
end

-- CaveBot counts every death (also the one before a relog/reload): a higher count is a death.
local function countedDeath(name, active)
  local count = deathCount()
  local s = settings()
  if not count or not s then return end
  local seen = tonumber(s.followDeaths)
  if seen == nil or count < seen or not active then s.followDeaths = count; return end
  if count > seen then s.followDeaths = count; W.noteDeath(name) end
end

-- Short line for the Follow status.
function W.text(name)
  local s = W.isWaiting() and state()
  if not s then return nil end
  if s.reason == 'death' then return 'En espera: moriste. Sigue al ver a ' .. tostring(name) end
  return 'En espera: ' .. tostring(name) .. ' muy lejos (' .. tostring(s.gap or '?') .. ' SQM). Sigue al verlo'
end

-- Called on every Follow tick with the leader name, the player position and the time in ms.
-- Returns true while Follow waits: the caller then does not chase the leader.
function W.check(name, origin, time)
  if not ctx then return false end
  local key = lower(name)
  local active = W.enabled() and key ~= ''
  countedDeath(name, active)
  if not active then farSince = nil; return false end
  local s = state()
  if s and s.name ~= key then W.clear(); s = nil end -- another leader: start fresh
  if ctx.dead and ctx.dead() then
    if not s then W.noteDeath(name); s = state() end
    return s ~= nil
  end
  if s then
    if not (ctx.visible and ctx.visible()) then return true end
    W.clear('Fin de la espera: ' .. name .. ' a la vista, el Follow sigue.')
    return false
  end
  -- Too far: by Navi, the leader stays more than FAR_SQM away for FAR_MS (read every CHECK_MS).
  if farCheckAt and time >= farCheckAt and time - farCheckAt < W.CHECK_MS then return false end
  farCheckAt = time
  if ctx.visible and ctx.visible() then farSince = nil; return false end
  local pos = ctx.leader and ctx.leader(name, time)
  local gap = type(pos) == 'table' and type(origin) == 'table' and tonumber(pos.x) and tonumber(origin.x) and
    math.max(math.abs(pos.x - origin.x), math.abs(pos.y - origin.y))
  if gap and gap >= W.FAR_SQM and not (ctx.exempt and ctx.exempt(time)) then
    if not farSince or time < farSince then farSince = time end
    if time - farSince >= W.FAR_MS then start('far', name, gap); return true end
  else
    farSince = nil
  end
  return false
end
return W
