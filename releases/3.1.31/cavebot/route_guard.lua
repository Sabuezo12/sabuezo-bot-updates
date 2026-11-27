-- Route guard: keeps the CaveBot from running its route out of place.
--
-- 1. Chains of failed gotos. vBot moves on to the next action when a goto fails. Once is
--    fine (after a stair the goto "fails" because the character is already on the next
--    floor). But when gotos keep failing while the character stays put, the route skips
--    ahead to actions far from where they belong: a sale, the Supreme Cube, a profile
--    change. From the second failure in a row without moving, the route goes back to where
--    the character really is: the first waypoint with a path from the first failed goto
--    onwards (that goto itself included), else the nearest just before it, else the nearest
--    anywhere in the route. With none, nothing changes.
-- 2. Place-dependent actions (sell, buy, depot, bank, imbuing, tasker, travel, Supreme Cube,
--    setprofile) run only if the last goto that ran arrived, a stair or teleport moved the
--    character since, or it stands within NEAR_SPOT SQM of the goto before the action.
--    Otherwise the route goes back to the stretch that leads to the action (from the last
--    supply check); with no waypoint near, the action is skipped, never run elsewhere.
-- Intentional jumps (go to label, a function's jump, wait stamina) are not failures.
CaveBot.RouteGuard = {}
local G = CaveBot.RouteGuard

G.PLACE = {sellall = true, buysupplies = true, depositor = true, deposit = true, withdraw = true,
  dpwithdraw = true, inwithdraw = true, depot = true, bank = true, imbuing = true, tasker = true,
  travel = true, supremecube = true, setprofile = true}
G.MOVERS = {travel = true, supremecube = true, use = true, usewith = true, floorchange = true,
  stepdirection = true, follow = true, lure = true}
-- Rows that do not move the character and can stand between a goto and its action.
local BETWEEN = {delay = true, ["function"] = true, waitstamina = true, say = true, npcsay = true,
  sayhello = true, zonapz = true}

local NEAR_SPOT = 4        -- SQM from the goto before a place action that counts as "there"
local APPROACH = 3         -- last gotos before a place action that count as its approach
local NEAR = 30            -- SQM: farther waypoints are not candidates to go back to
local FORWARD, BACKWARD = 25, 15
local SECTION_BACK = 60    -- rows searched back for the stretch that leads to an action
local CHAIN_GAP = 10000    -- ms between two failures of the same chain
local SAME_PLACE = 2       -- SQM the character may move (fighting) inside one chain
local REPEAT_MAX, REPEAT_WINDOW, PAUSE = 3, 60000, 60000
local PATH_CHECKS = 6

local state
function G.reset()
  state = {last = nil, chain = nil, repeats = {}, pausedUntil = 0, said = {}}
end
G.reset()

local function clock() return tonumber(now) or 0 end
local function copy(p) return {x = p.x, y = p.y, z = p.z} end
local function cheb(a, b) return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y)) end
local function manhattan(a, b) return math.abs(a.x - b.x) + math.abs(a.y - b.y) end
local function text(p) return p.x .. "," .. p.y .. "," .. p.z end

-- Also printed to the client's log file (where the bot's warnings already go), so a stuck
-- route can be read afterwards; the same line at most every 20 s.
local printed = {}
local function log(message)
  if RinoConsole and type(RinoConsole.log) == "function" then
    pcall(RinoConsole.log, "action", "CaveBot", message)
  end
  local t = tonumber(now) or 0
  if type(print) == "function" and (not printed[message] or t - printed[message] >= 20000 or t < printed[message]) then
    printed[message] = t
    pcall(print, "CaveBot[Ruta]: " .. message)
  end
end

local function position()
  local ok, p = pcall(function() return player:getPosition() end)
  if ok and type(p) == "table" and p.x then return copy(p) end
end

local function list() return CaveBot.actionList end
local function indexOf(row)
  local l = list()
  local ok, index = pcall(function() return l:getChildIndex(row) end)
  return ok and tonumber(index) or nil
end
local function rowAt(i) local l = list(); return l and l:getChildByIndex(i) end
local function rowCount() local l = list(); return l and l:getChildCount() or 0 end

local function gotoPos(row)
  if not row or row.action ~= "goto" then return nil end
  local x, y, z = tostring(row.value or ""):match("^%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)")
  if not z then return nil end
  return {x = tonumber(x), y = tonumber(y), z = tonumber(z)}
end

local function maxDist() return tonumber(storage.extras and storage.extras.gotoMaxDistance) or 24 end

local function hasPath(from, to)
  if from.x == to.x and from.y == to.y and from.z == to.z then return true end
  if type(findPath) ~= "function" then return true end
  -- Creatures move and the goto deals with them; walls and floors decide here.
  local ok, path = pcall(findPath, from, to, 40,
    {ignoreNonPathable = true, ignoreCreatures = true, allowUnseen = true, allowOnlyVisibleTiles = false})
  return ok and path ~= nil
end

-- Nearest goto with a path among rows first..last (either direction), or nil.
local function nearestIn(first, last, here)
  local step = first <= last and 1 or -1
  local found = {}
  for i = first, last, step do
    local wp = gotoPos(rowAt(i))
    if wp and wp.z == here.z and cheb(wp, here) <= NEAR and manhattan(wp, here) <= maxDist() then
      found[#found + 1] = {index = i, wp = wp, distance = cheb(wp, here), order = #found}
    end
  end
  table.sort(found, function(a, b)
    if a.distance ~= b.distance then return a.distance < b.distance end
    return a.order < b.order
  end)
  for n = 1, math.min(#found, PATH_CHECKS) do
    if hasPath(here, found[n].wp) then return found[n] end
  end
end

-- First goto with a path in route order among rows first..last: what vBot's own skipping
-- reaches, minus the actions in between (a jump to a label that relies on it still works).
local function firstIn(first, last, here)
  local checks = 0
  for i = first, last do
    local wp = gotoPos(rowAt(i))
    if wp and wp.z == here.z and cheb(wp, here) <= NEAR and manhattan(wp, here) <= maxDist() then
      if hasPath(here, wp) then return {index = i, wp = wp, distance = cheb(wp, here)} end
      checks = checks + 1
      if checks >= PATH_CHECKS * 2 then return nil end
    end
  end
end

local function anywhere(here)
  local R = CaveBot.RouteResume
  if not R or type(R.pick) ~= "function" then return nil end
  local entries = {}
  for i = 1, rowCount() do
    local row = rowAt(i)
    entries[i] = {action = row and row.action, value = row and row.value}
  end
  local ok, pick = pcall(R.pick, entries, here, {maxDist = maxDist(),
    hasPath = function(wp) return hasPath(here, wp) end})
  if ok and type(pick) == "table" and pick.verified then return pick end
end

-- The route continues at row `index` (the engine advances from the focused row).
local function continueAt(index)
  local l = list()
  if not l then return false end
  local before = index > 1 and rowAt(index - 1) or rowAt(rowCount())
  if not before then return false end
  l:focusChild(before)
  return true
end

local function where(pick)
  return "waypoint " .. pick.index .. " (" .. text(pick.wp) .. "), a " .. pick.distance .. " casillas de ti"
end

-- Same target too often in a row: give it a rest instead of looping on it.
local function tooOften(kind, index)
  local t = clock()
  local r = state.repeats[kind]
  if r and r.index == index and t - r.since < REPEAT_WINDOW then
    r.count = r.count + 1
    return r.count > REPEAT_MAX
  end
  state.repeats[kind] = {index = index, count = 1, since = t}
  return false
end

local function sayOnce(key, message)
  local t = clock()
  if (state.said[key] or -math.huge) > t then return end
  state.said[key] = t + 30000
  log(message)
end

local function reason(row, here)
  local wp = gotoPos(row)
  if not wp then return "valor" end
  if wp.z ~= here.z then return "floor" end
  if manhattan(wp, here) > maxDist() then return "far" end
  return "path"
end

local function breakChain(chain, here)
  if clock() < state.pausedUntil then return end
  local pick = firstIn(chain.first, math.min(rowCount(), chain.first + FORWARD), here) or
    (chain.first > 1 and nearestIn(chain.first - 1, math.max(1, chain.first - BACKWARD), here)) or
    anywhere(here)
  if not pick then
    sayOnce("chain-none", "Waypoints " .. chain.first .. " a " .. chain.last .. " fallaron sin moverte y no hay " ..
      "otro waypoint con camino cerca: la ruta sigue como antes.")
    return
  end
  if tooOften("chain", pick.index) then
    state.pausedUntil = clock() + PAUSE
    state.repeats.chain = nil
    log("No consigo pasar del waypoint " .. pick.index .. " (" .. text(pick.wp) .. ") tras " .. REPEAT_MAX ..
      " intentos: durante " .. (PAUSE / 1000) .. " s la ruta sigue como antes.")
    return
  end
  if continueAt(pick.index) then
    state.chain = nil
    log("Waypoints " .. chain.first .. " a " .. chain.last .. " fallaron sin moverte: no salto mas, la ruta " ..
      "vuelve al " .. where(pick) .. ".")
  end
end

-- After every action (cavebot.lua main loop).
function G.after(row, result)
  if not row then return end
  local action = row.action
  if action == "goto" then
    if result == true then
      state.last, state.chain = {ok = true}, nil
      state.repeats.chain = nil
      local here, index = position(), indexOf(row)
      state.arrived = here and index and {index = index, pos = here} or nil
      return
    end
    if result ~= false then return end -- still walking
    local here = position()
    local index = indexOf(row)
    if not here or not index then return end
    local why = reason(row, here)
    state.last = {ok = false, reason = why, spot = gotoPos(row)}
    local t = clock()
    local chain = state.chain
    if chain and chain.here.z == here.z and cheb(chain.here, here) <= SAME_PLACE and t - chain.at <= CHAIN_GAP then
      chain.count, chain.last, chain.at = chain.count + 1, index, t
      if chain.count >= 2 then breakChain(chain, here) end
    else
      state.chain = {count = 1, first = index, last = index, here = here, at = t}
    end
  elseif G.MOVERS[action] and result == true then
    state.last, state.chain = {moved = true}, nil
  end
end

-- The goto right before a place action (over delays, functions and talk); nil when a
-- label, a jump or a moving action stands in between (then the way here is unknown).
local function spotBefore(index)
  for i = index - 1, math.max(1, index - 16), -1 do
    local row = rowAt(i)
    local action = row and row.action
    if action == "goto" then return gotoPos(row) end
    if not BETWEEN[action] then return nil end
  end
end

-- One of the last APPROACH gotos before a place action (over delays, functions, talk and
-- other gotos; a label, jump or moving action ends the approach).
local function inApproach(index, target)
  local gotos = 0
  for i = index - 1, math.max(1, index - 16), -1 do
    local row = rowAt(i)
    local action = row and row.action
    if action == "goto" then
      if i == target then return true end
      gotos = gotos + 1
      if gotos >= APPROACH then return false end
    elseif not BETWEEN[action] then
      return false
    end
  end
  return false
end

-- Before an action runs (cavebot.lua main loop). nil = run it; true/false = its result.
function G.before(row, retries)
  if not row or retries ~= 0 or not G.PLACE[row.action] then return nil end
  local last = state.last
  if not last or last.ok ~= false then return nil end
  local here, index = position(), indexOf(row)
  if not here or not index then return nil end
  local spot = spotBefore(index)
  if not spot then return nil end
  if spot.z == here.z and cheb(spot, here) <= NEAR_SPOT then return nil end
  -- A stair or hole at that goto: it "failed" because it already took the character down/up.
  if last.reason == "floor" and last.spot and cheb(last.spot, here) <= 1 then return nil end
  -- The route did reach this action's approach and the character is still where it arrived:
  -- a later goto it cannot reach (a point recorded on the other side of a travel, for
  -- example) does not stop the action, as before the guard.
  local arrived = state.arrived
  if arrived and arrived.pos.z == here.z and cheb(arrived.pos, here) <= NEAR_SPOT and
      inApproach(index, arrived.index) then
    return nil
  end
  local name = row.action .. " (fila " .. index .. ")"
  local why = "el goto anterior no llego y estas a " ..
    (spot.z == here.z and (cheb(spot, here) .. " SQM de su punto (") or "otro piso de su punto (") .. text(spot) .. ")"
  if not tooOften("place" .. index, index) then
    local lo = math.max(1, index - SECTION_BACK)
    for i = index - 1, lo, -1 do
      local r = rowAt(i)
      if r and r.action == "supplycheck" then lo = i; break end
    end
    local pick = nearestIn(index - 1, lo, here) or anywhere(here)
    if pick and pick.index ~= index and continueAt(pick.index) then
      log("No ejecuto " .. name .. ": " .. why .. ". La ruta vuelve al " .. where(pick) .. ".")
      return true
    end
  end
  log("No ejecuto " .. name .. ": " .. why .. ". No hay waypoint con camino cerca; la salto.")
  return false
end
