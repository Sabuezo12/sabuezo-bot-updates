-- Back to the route after an unplanned floor change: a hole, stairs or a ramp taken by
-- mistake, a push onto a ladder. The route used to stand still there, because every goto
-- of another floor just failed and the route went round without moving.
--
-- Runs only from the goto action when the route cannot continue (cavebot/actions.lua):
--   * wrongFloor(): the goto is on another floor and the route has no goto on this one
--     within reach (a planned staircase always has its next goto on the landing floor),
--     confirmed for 1.5 s; or no goto of the route worked for a whole lap;
--   * lost(): back on the route floor but the goto is out of reach, or no goto of the
--     route worked for a whole lap (stuck without a route).
-- Ordinary walking is never touched. Option per profile: storage.extras.caveFloorReturn
-- (CaveBot > Config > "Volver a la ruta al cambiar de piso"; new profiles start ON).
CaveBot.FloorReturn = {}
local F = CaveBot.FloorReturn

local SCAN_X, SCAN_Y = 8, 6        -- visible area searched for a way back
local PATH_CHECKS = 4              -- candidate exits checked for a real path, best first
local MAX_FLOOR_GAP = 3            -- farther floors are not a fall: no attempt
local CONFIRM_TIME = 1500          -- the wrong floor must last this long before acting
local JOB_TIME = 180000            -- active time allowed to get back to the route floor
local MAX_CROSSINGS = 8
local MAX_FAILURES = 8
local NO_EXIT_TIME = 10000         -- nothing usable in sight for this long: give up
local PENDING_TIME = 2000          -- wait for the floor change after a step or a use
local FAILED_TIME = 20000          -- an exit that did nothing is skipped this long
local WRONG_TIME = 120000          -- an exit that leads away from the route floor
local STALL_TIME = 6000            -- approaching an exit without moving
local ANCHOR_RANGE = 60            -- path search back to the departure tile
local ANCHOR_TIME = 90000
local LINK_LIMIT = 6
local COOLDOWNS = {30000, 60000, 120000, 300000}
local REPEAT_LIMIT, REPEAT_WINDOW = 4, 300000  -- this many returns in 5 min: the route itself drops us
local MAGIC_ROPE = "exani tera"    -- magic rope: standing on a rope spot, level 9, 20 mana
local STEP_MEMORY = 6              -- bot steps kept to explain an unplanned floor change
local FLOOR_LOG = 10               -- explained floor changes kept in storage.caveFloorLog
-- Out of sight: the route's own floor changes, then floor changes of the explored minimap.
local FAR_RANGE = 50               -- farthest target (SQM)
local FAR_PATH = 70                -- path search to it
local FAR_CHECKS = 3               -- targets checked for a real path per choice
local FAR_FAILED_TIME = 60000
local MINIMAP_RANGE = 30           -- minimap searched around the character
local FAR_TEXT = {ruta = "la escalera de la ruta", llegada = "la llegada de la ruta a este piso",
  minimapa = "un cambio de piso del minimapa"}

-- Ladders, sewer grates and trapdoors (cavebot/auto_explorer.lua), rope spots excluded.
local USE_IDS = {
  [432] = true, [433] = true, [435] = true,
  [1947] = true, [1948] = true, [1968] = true, [1969] = true,
  [1386] = true, [1387] = true, [1388] = true, [1390] = true, [1391] = true, [1392] = true, [1394] = true,
  [5007] = true, [4911] = true, [5107] = true, [5108] = true, [5116] = true, [5117] = true,
  [5120] = true, [5122] = true, [5125] = true, [5126] = true, [5542] = true, [5733] = true,
  [5734] = true, [5736] = true, [5737] = true, [6250] = true, [6252] = true, [6253] = true,
  [6256] = true, [6257] = true, [6264] = true, [7131] = true, [7132] = true, [7727] = true,
  [8255] = true, [8256] = true, [8257] = true, [8258] = true
}
local OFFSETS = {[0] = {0, -1}, {1, 0}, {0, 1}, {-1, 0}, {1, -1}, {1, 1}, {-1, 1}, {-1, -1}}
local KIND_TEXT = {step = "escalera o hueco", rope = "soga", shovel = "pala", use = "escalera de mano",
  spell = MAGIC_ROPE}

local state

local function clock() return tonumber(now) or 0 end
local function copy(p) return {x = p.x, y = p.y, z = p.z} end
local function key(p) return p.x .. "," .. p.y .. "," .. p.z end
local function cheb(a, b) return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y)) end
local function manhattan(a, b) return math.abs(a.x - b.x) + math.abs(a.y - b.y) end
local function sign(v) return v > 0 and 1 or v < 0 and -1 or 0 end
local function text(p) return p and (p.x .. "," .. p.y .. "," .. p.z) or "?" end

function F.reset()
  state = {
    links = {},          -- floor crossings since the route was last followed
    lastGood = nil,      -- last tile in reach of the route's goto (exact departure point)
    learned = {},        -- exit key -> floor delta seen this session
    failed = {},         -- exit key -> time until it may be tried again
    job = nil,           -- getting back to the route floor
    anchor = nil,        -- walking back to the departure tile on the route floor
    fails = 0,           -- goto failures in a row (a whole lap = stuck)
    cooldownUntil = 0, giveUps = 0,
    gotoCount = nil, gotoCountFor = nil,
    starts = {},         -- when the last returns started (stops a route that keeps dropping us)
  }
end
F.reset()

local function log(message, detail)
  if RinoConsole and type(RinoConsole.log) == "function" then
    pcall(RinoConsole.log, "action", "CaveBot", message, detail)
  end
end
-- Rare events: warn() reaches the client log and the RinoBot console (Avisos).
local function alert(message)
  if type(warn) == "function" then pcall(warn, "[CaveBot] " .. message) else log(message) end
end

function F.enabled()
  local extras = storage and storage.extras
  return type(extras) == "table" and extras.caveFloorReturn == true
end

-- A wrong floor seen in the last second and still being confirmed.
local function suspecting()
  local suspect = state.suspect
  return suspect ~= nil and clock() - suspect.seen <= 1000
end

function F.busy()
  return state.job ~= nil or state.anchor ~= nil or suspecting()
end

function F.status()
  return state
end

local function maxDistance()
  return tonumber(storage and storage.extras and storage.extras.gotoMaxDistance) or 24
end

-- Flee, Follow and the player's own hands own their floor changes.
local function othersMoving()
  if CaveBot.Flee and CaveBot.Flee.blocksCombat and CaveBot.Flee.blocksCombat() then return true end
  if ComboFollowCombat and type(ComboFollowCombat.isFollowing) == "function" then
    local ok, on = pcall(ComboFollowCombat.isFollowing)
    if ok and on then return true end
  end
  if g_game and type(g_game.isFollowing) == "function" then
    local ok, on = pcall(g_game.isFollowing)
    if ok and on then return true end
  end
  return false
end

local function manual()
  local movement = TargetBot and TargetBot.Movement
  if movement and type(movement.isManual) == "function" then
    local ok, on = pcall(movement.isManual)
    return ok and on == true
  end
  return false
end

local function walking()
  local ok, on = pcall(function() return player:isWalking() end)
  return ok and on == true
end

-- Route reading ------------------------------------------------------------
local gotoCache = {}
local function gotoPos(row)
  if not row or row.action ~= "goto" then return nil end
  local value = tostring(row.value or "")
  local hit = gotoCache[value]
  if hit == nil then
    local x, y, z = value:match("^%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)")
    hit = z and {x = tonumber(x), y = tonumber(y), z = tonumber(z)} or false
    gotoCache[value] = hit
  end
  return hit or nil
end

local function routeRows()
  local list = CaveBot.actionList
  if not list then return nil end
  local rows = list:getChildren()
  local index = list:getChildIndex(list:getFocusedChild() or list:getFirstChild())
  return rows, index
end

-- The route has a goto on this floor within its reach: a planned floor change (the next
-- goto is on the landing floor) or a part of the route the old cycling can resume. Only
-- a floor with no route at hand is "off the route".
local function routeOnFloor(position)
  local rows = routeRows()
  if not rows then return false end
  local limit = maxDistance()
  for _, row in ipairs(rows) do
    local wp = gotoPos(row)
    if wp and wp.z == position.z and manhattan(wp, position) <= limit then return true end
  end
  return false
end

-- Every goto of the route failed once in a row: the route cannot continue from here.
local function lapReached()
  if state.fails < 6 then return false end
  local list = CaveBot.actionList
  local count = list and list:getChildCount() or 0
  if state.gotoCountFor ~= count then
    local n = 0
    for _, row in ipairs(list and list:getChildren() or {}) do if gotoPos(row) then n = n + 1 end end
    state.gotoCount, state.gotoCountFor = n, count
  end
  return state.gotoCount > 0 and state.fails > state.gotoCount
end

-- Map reading ----------------------------------------------------------------
local function listed(list, id)
  for _, value in ipairs(list or {}) do if tonumber(value) == id then return true end end
  return false
end

local function stairColor(value)
  value = tonumber(value) or 0
  return value >= 210 and value <= 213
end

local function flagged(object, name)
  if not object or type(object[name]) ~= "function" then return false end
  local ok, value = pcall(object[name], object)
  return ok and value == true
end

-- kind ("step", "rope", "shovel", "use"), the thing to use, and the known floor delta.
local function exitKind(p, tile)
  if not tile and g_map and g_map.getTile then tile = g_map.getTile(p) end
  local things = {}
  if tile then
    local ground = tile.getGround and tile:getGround()
    if ground then things[1] = ground end
    for _, item in ipairs(tile.getItems and tile:getItems() or {}) do things[#things + 1] = item end
  end
  local extras = storage and storage.extras or {}
  local ropeTool, shovelTool = tonumber(extras.rope) or 3003, tonumber(extras.shovel) or 3457
  local global = Global or {}
  for _, thing in ipairs(things) do
    local id = thing.getId and tonumber(thing:getId())
    if id then
      if id ~= ropeTool and id ~= 3003 and listed(global.ropeIds, id) then return "rope", thing, -1 end
      if id ~= shovelTool and id ~= 3457 and listed(global.shovelIds, id) then return "shovel", thing, 1 end
      if USE_IDS[id] then return "use", thing, nil end
    end
  end
  local live
  if tile and tile.getMinimapColorByte then
    local ok, value = pcall(tile.getMinimapColorByte, tile)
    if ok then live = value end
  end
  local known = g_map and g_map.getMinimapColor and g_map.getMinimapColor(p)
  if stairColor(live) or stairColor(known) then return "step", nil, nil end
  if flagged(tile, "isFloorChange") then return "step", nil, nil end
  for _, thing in ipairs(things) do
    if flagged(thing, "isFloorChange") then return "step", nil, nil end
  end
  return nil
end

local function occupied(tile)
  local creatures = tile and tile.getCreatures and tile:getCreatures() or {}
  for _, creature in ipairs(creatures) do if creature ~= player then return true end end
  return false
end

local function directionTo(a, b)
  local dx, dy = b.x - a.x, b.y - a.y
  for dir = 0, 7 do
    local o = OFFSETS[dir]
    if o[1] == dx and o[2] == dy then return dir end
  end
end

-- The floor-change tile a crossing went through, when only one is next to the departure.
local function guessEntry(oldPos)
  local found
  for dx = -1, 1 do
    for dy = -1, 1 do
      if dx ~= 0 or dy ~= 0 then
        local p = {x = oldPos.x + dx, y = oldPos.y + dy, z = oldPos.z}
        if exitKind(p) == "step" then
          if found then return nil end
          found = p
        end
      end
    end
  end
  return found
end

local function pathTo(from, to, limit, precision)
  local ok, path = pcall(findPath, from, to, limit, {ignoreNonPathable = true, ignoreFields = true,
    precision = precision, allowUnseen = true, allowOnlyVisibleTiles = false})
  return ok and path ~= nil
end

-- Best way toward the target floor among the visible exits. The reverse of the crossing
-- that brought us here (next to where we landed) goes first.
local function selectExit(job, position)
  local want = sign(job.target - position.z)
  local t = clock()
  local link = state.links[#state.links]
  if link and link.landing.z ~= position.z then link = nil end
  local projected = link and (link.entry or link.landing)
  local candidates = {}
  for dx = -SCAN_X, SCAN_X do
    for dy = -SCAN_Y, SCAN_Y do
      local p = {x = position.x + dx, y = position.y + dy, z = position.z}
      local id = key(p)
      if (state.failed[id] or 0) <= t then
        local kind, thing, delta = exitKind(p)
        delta = state.learned[id] or delta
        local distance = cheb(p, position)
        if kind and (delta == nil or delta == want) and not (kind == "step" and distance == 0) then
          local score = distance
          if projected then
            score = score + 5 * cheb(p, projected) + 2 * cheb(p, link.landing)
          end
          if delta == want then score = score - 10 end
          if kind == "use" and delta == nil then score = score + 4 end
          candidates[#candidates + 1] = {pos = p, key = id, kind = kind, score = score, distance = distance}
        end
      end
    end
  end
  table.sort(candidates, function(a, b)
    if a.score ~= b.score then return a.score < b.score end
    return a.distance < b.distance
  end)
  local checks = 0
  for _, exit in ipairs(candidates) do
    if exit.distance <= 1 then return exit end
    checks = checks + 1
    if pathTo(position, exit.pos, 20, 1) then return exit end
    state.failed[exit.key] = t + FAILED_TIME
    if checks >= PATH_CHECKS then break end
  end
  return nil
end

-- Nothing usable in sight: look again from where we landed (the way back is usually
-- there) or from below/above the departure tile.
local function lookout(job, position)
  local spots = {}
  for i = #state.links, 1, -1 do
    local link = state.links[i]
    if link.landing.z == position.z then spots[#spots + 1] = link.landing end
  end
  local anchor = state.anchor and state.anchor.pos or state.lastGood
  if anchor then spots[#spots + 1] = {x = anchor.x, y = anchor.y, z = position.z} end
  for _, spot in ipairs(spots) do
    if cheb(spot, position) > 1 and not job.looked[key(spot)] and pathTo(position, spot, 30, 1) then
      return copy(spot)
    end
  end
end

-- The route's own floor changes: goto + goto on another floor (the recorder writes the last
-- tile of the old floor, the stairs or the tile before them), use / usewith + goto on another
-- floor, and recorded floorchange actions. They tell where a way between floors is and which
-- way it goes, even far out of sight.
local function routeAccesses()
  local rows = routeRows()
  local found = {}
  if not rows or #rows < 2 then return found end
  local extras = storage and storage.extras or {}
  local ropeTool, shovelTool = tonumber(extras.rope) or 3003, tonumber(extras.shovel) or 3457
  local function nextGoto(i)
    for step = 1, math.min(6, #rows - 1) do
      local row = rows[(i - 1 + step) % #rows + 1]
      local wp = gotoPos(row)
      if wp then return wp end
      if row.action == "use" or row.action == "usewith" or row.action == "floorchange" then return nil end
    end
  end
  local function add(pos, landing, how)
    if pos and landing and landing.z ~= pos.z then
      found[#found + 1] = {pos = pos, toZ = landing.z, landing = landing, how = how}
    end
  end
  for i, row in ipairs(rows) do
    local value = tostring(row.value or "")
    if row.action == "goto" then
      local wp = gotoPos(row)
      if wp then add(wp, nextGoto(i), "step") end
    elseif row.action == "use" then
      local x, y, z = value:match("^%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)")
      if z then add({x = tonumber(x), y = tonumber(y), z = tonumber(z)}, nextGoto(i), "use") end
    elseif row.action == "usewith" then
      local tool, x, y, z = value:match("^%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)")
      tool = tonumber(tool)
      if z then
        add({x = tonumber(x), y = tonumber(y), z = tonumber(z)}, nextGoto(i),
          (tool == ropeTool or tool == 3003) and "rope" or (tool == shovelTool or tool == 3457) and "shovel" or "use")
      end
    elseif row.action == "floorchange" then
      local n = {}
      for number in value:gmatch("%d+") do n[#n + 1] = tonumber(number) end
      if #n == 8 then add({x = n[4], y = n[5], z = n[3]}, {x = n[6], y = n[7], z = n[8]}, "step") end
    end
  end
  return found
end

-- Targets out of sight, best first: the route's way toward the wanted floor (direction
-- known), where the route arrives on this floor from that side (its way back is next to it),
-- then explored minimap floor changes (direction unknown, learnt by trying).
local function farTargets(job, position)
  local want = sign(job.target - position.z)
  local t = clock()
  local list, seen = {}, {}
  local function add(pos, source, delta, prio)
    local id = key(pos)
    if seen[id] or job.looked[id] or (state.failed[id] or 0) > t then return end
    local learned = state.learned[id]
    if learned ~= nil and learned ~= want then return end
    local distance = cheb(pos, position)
    if distance <= 1 or distance > FAR_RANGE then return end
    seen[id] = true
    list[#list + 1] = {pos = copy(pos), source = source, delta = delta, prio = prio, distance = distance}
  end
  job.accesses = job.accesses or routeAccesses()
  for _, access in ipairs(job.accesses) do
    if access.pos.z == position.z and sign(access.toZ - access.pos.z) == want then
      add(access.pos, "ruta", access.toZ - access.pos.z, 1)
    end
  end
  for _, access in ipairs(job.accesses) do
    if access.landing.z == position.z and sign(access.pos.z - access.landing.z) == want then
      add(access.landing, "llegada", nil, 2)
    end
  end
  job.minimap = job.minimap or {}
  local spots = job.minimap[position.z]
  if not spots and g_map and g_map.getMinimapColor then
    spots = {}
    for dx = -MINIMAP_RANGE, MINIMAP_RANGE do
      for dy = -MINIMAP_RANGE, MINIMAP_RANGE do
        if math.abs(dx) > SCAN_X or math.abs(dy) > SCAN_Y then
          local p = {x = position.x + dx, y = position.y + dy, z = position.z}
          if stairColor(g_map.getMinimapColor(p)) then spots[#spots + 1] = p end
        end
      end
    end
    job.minimap[position.z] = spots
  end
  for _, p in ipairs(spots or {}) do add(p, "minimapa", nil, 3) end
  table.sort(list, function(a, b)
    if a.prio ~= b.prio then return a.prio < b.prio end
    return a.distance < b.distance
  end)
  return list
end

local function pickFar(job, position)
  local checks = 0
  for _, far in ipairs(farTargets(job, position)) do
    checks = checks + 1
    if pathTo(position, far.pos, FAR_PATH, 1) then return far end
    state.failed[key(far.pos)] = clock() + FAR_FAILED_TIME
    if checks >= FAR_CHECKS then break end
  end
end

-- At a route access: its floor change (the tile itself, or the only one next to it) is
-- known to lead the wanted way, so the local search takes it first.
local function hint(far)
  if not far.delta then return end
  local function learn(p)
    if state.learned[key(p)] == nil then state.learned[key(p)] = far.delta end
  end
  if exitKind(far.pos) then learn(far.pos); return end
  local found
  for dir = 0, 7 do
    local o = OFFSETS[dir]
    local p = {x = far.pos.x + o[1], y = far.pos.y + o[2], z = far.pos.z}
    if exitKind(p) then
      if found then return end
      found = p
    end
  end
  if found then learn(found) end
end

-- Floor return job ---------------------------------------------------------------
local function giveUp(job, reason)
  state.giveUps = state.giveUps + 1
  local wait = COOLDOWNS[math.min(state.giveUps, #COOLDOWNS)]
  state.cooldownUntil = clock() + wait
  state.job, state.anchor = nil, nil
  alert(string.format("No pude volver a la ruta (piso %d): %s. La ruta queda quieta; reintento en %d s.",
    job and job.target or -1, reason, math.floor(wait / 1000)))
  return false
end

local function startJob(target, position, why, lap)
  if math.abs(target - position.z) > MAX_FLOOR_GAP then
    state.giveUps = state.giveUps + 1
    local wait = COOLDOWNS[math.min(state.giveUps, #COOLDOWNS)]
    state.cooldownUntil = clock() + wait
    alert(string.format("%s: estas en el piso %d y la ruta esta en el piso %d; demasiado lejos para volver solo " ..
      "(reviso de nuevo en %d s).", why, position.z, target, math.floor(wait / 1000)))
    return false
  end
  local t = clock()
  -- A waypoint on a staircase to a floor without route drops us again after every return.
  local starts = {}
  for _, at in ipairs(state.starts) do if t - at < REPEAT_WINDOW then starts[#starts + 1] = at end end
  state.starts = starts
  if #starts >= REPEAT_LIMIT then
    state.starts = {}
    state.giveUps = #COOLDOWNS
    state.cooldownUntil = t + COOLDOWNS[#COOLDOWNS]
    alert(string.format("El cambio de piso se repite (%d veces en 5 min): revisa la ruta cerca de %s; " ..
      "puede haber un waypoint sobre una escalera. No vuelvo durante 5 min.", #starts + 1,
      text(state.lastGood or position)))
    return false
  end
  starts[#starts + 1] = t
  state.job = {target = target, started = t, lastTick = t, crossings = 0, failures = 0,
    lastMoveAt = t, lastPos = key(position), lap = lap, nextAt = 0, looked = {}}
  if state.lastGood and state.lastGood.z == target then
    state.anchor = {pos = copy(state.lastGood), started = t, lastTick = t}
  end
  if CaveBot.stopPathWalk then pcall(CaveBot.stopPathWalk) end
  CaveBot.resetWalking()
  alert(string.format("%s: estas en el piso %d y la ruta sigue en el piso %d. Busco el camino de vuelta%s.",
    why, position.z, target, state.lastGood and state.lastGood.z == target and
      (" a " .. text(state.lastGood)) or ""))
  return true
end

local function finishJob(position)
  state.job = nil
  log("Regreso de piso: de vuelta en el piso " .. position.z, text(position) ..
    (state.anchor and (" -> punto de salida " .. text(state.anchor.pos)) or ""))
end

local function useTool(toolId, thing)
  if not thing then return false end
  local ok, result = pcall(useWith, toolId, thing)
  if ok and result ~= false then return true end
  if g_game and g_game.useInventoryItemWith then
    ok = pcall(g_game.useInventoryItemWith, toolId, thing, 0)
    return ok
  end
  return false
end

local function useThing(thing)
  if not thing then return false end
  local ok, result = pcall(use, thing)
  if ok and result ~= false then return true end
  if g_game and g_game.use then return (pcall(g_game.use, thing)) end
  return false
end

local function configNumber(id, default)
  local ok, value = pcall(CaveBot.Config.get, id)
  return ok and tonumber(value) or default
end

local function stepDuration(dir)
  local ok, value = pcall(function() return player:getStepDuration(false, dir) end)
  return ok and tonumber(value) or 0
end

-- A rope spot is climbed with the rope from the backpack or with exani tera standing on
-- it. When the client counts no rope the spell goes first; each way is tried once.
local function ropeModes()
  local extras = storage and storage.extras or {}
  local count
  if player and type(player.getInventoryCount) == "function" then
    local ok, value = pcall(player.getInventoryCount, player, tonumber(extras.rope) or 3003, 0)
    if ok then count = tonumber(value) end
  end
  local spell = true
  local okLevel, level = pcall(function() return player:getLevel() end)
  if okLevel and tonumber(level) and tonumber(level) < 9 then spell = false end
  local okMana, mana = pcall(function() return player:getMana() end)
  if okMana and tonumber(mana) and tonumber(mana) < 20 then spell = false end
  if not spell then return {"tool"} end
  if count == 0 then return {"spell", "tool"} end
  return {"tool", "spell"}
end

-- Acts on the chosen exit; returns false when it could not be used.
local function cross(job, exit, position)
  local t = clock()
  local tile = g_map.getTile(exit.pos)
  local kind, thing = exitKind(exit.pos, tile)
  if exit.dug then kind = "step" end -- the dug pile is a hole now
  if not kind then return false end
  local ping = configNumber("ping", 100)
  local mode = kind
  if kind == "rope" then
    exit.ropeModes = exit.ropeModes or ropeModes()
    if exit.ropeModes[exit.ropeStep or 1] == "spell" then mode = "spell" end
  end
  if mode == "spell" then
    if position.x ~= exit.pos.x or position.y ~= exit.pos.y then
      -- exani tera works standing on the rope spot: step onto it first.
      exit.stepTries = (exit.stepTries or 0) + 1
      if exit.stepTries > 3 or occupied(tile) then return false end
      local dir = directionTo(position, exit.pos)
      if not dir then return false end
      local ok, sent = pcall(safeBotWalk, dir)
      if not ok or sent == false then return false end
      local wait = math.max(400, stepDuration(dir) + ping + 100)
      job.nextAt = t + wait
      CaveBot.delay(wait)
      return true
    end
    if not pcall(say, MAGIC_ROPE) then return false end
    local wait = math.max(400, ping + 400)
    job.pending = {key = exit.key, exit = copy(exit.pos), from = copy(position), untilAt = t + wait + PENDING_TIME,
      rope = "spell"}
    CaveBot.delay(wait)
  elseif kind == "step" then
    if occupied(tile) then
      job.waitedAt = job.waitedAt or t
      if t - job.waitedAt > 5000 then return false end
      CaveBot.delay(300)
      return true
    end
    local dir = directionTo(position, exit.pos)
    if not dir then return false end
    -- Antitrap refuses steps onto floor changes; this one is the point of the job.
    local ok, sent = pcall(safeBotWalk, dir)
    if not ok or sent == false then return false end
    local wait = math.max(500, stepDuration(dir) + ping + 150)
    job.pending = {key = exit.key, exit = copy(exit.pos), from = copy(position), untilAt = t + wait + PENDING_TIME}
    CaveBot.delay(wait)
  else
    local extras = storage and storage.extras or {}
    local used
    if kind == "rope" then used = useTool(tonumber(extras.rope) or 3003, thing)
    elseif kind == "shovel" then used = useTool(tonumber(extras.shovel) or 3457, thing)
    else used = useThing(thing) end
    if not used then return false end
    local wait = math.max(400, configNumber("useDelay", 400) + ping)
    if kind == "shovel" then
      -- The pile becomes a hole: step into it on the next turn.
      exit.dug = true
      job.nextAt = t + wait
    else
      job.pending = {key = exit.key, exit = copy(exit.pos), from = copy(position), untilAt = t + wait + PENDING_TIME,
        rope = kind == "rope" and "tool" or nil}
    end
    CaveBot.delay(wait)
  end
  job.waitedAt = nil
  log(string.format("Regreso de piso: uso %s en %s", KIND_TEXT[mode] or mode, text(exit.pos)),
    "piso " .. position.z .. " -> " .. job.target)
  return true
end

-- Nothing in sight and no lookout left: walk to a way out of sight. true = walking.
local function farTurn(job, position, t)
  local far = job.far
  if far and cheb(far.pos, position) <= 1 then
    hint(far)
    job.looked[key(far.pos)] = true
    job.far = nil
    log("Regreso de piso: llegue a " .. (FAR_TEXT[far.source] or far.source) .. "; busco la salida aqui", text(far.pos))
    return true
  end
  if far and t - (job.farMovedAt or t) > STALL_TIME then
    state.failed[key(far.pos)] = t + FAR_FAILED_TIME
    job.failures = job.failures + 1
    job.far, far = nil, nil
    log("Regreso de piso: no avanzo hacia ese destino; pruebo otro")
  end
  if not far then
    far = pickFar(job, position)
    job.far = far
    if not far then return false end
    job.lookoutsDone = true
    hint(far) -- known direction: the local search prefers it once it is in sight
    job.farMovedAt = t
    log(string.format("Regreso de piso: no veo salida; voy a %s en %s (%d casillas)",
      FAR_TEXT[far.source] or far.source, text(far.pos), far.distance), "piso " .. position.z .. " -> " .. job.target)
  end
  if CaveBot.walkTo(far.pos, FAR_PATH, {precision = 1, allowUnseen = true, allowOnlyVisibleTiles = false}) then
    return true
  end
  state.failed[key(far.pos)] = t + FAR_FAILED_TIME
  job.failures = job.failures + 1
  job.far = nil
  return false
end

-- One turn of the job. true = the goto waits ("retry"), false = job ended or gave up.
local function runJob(position)
  local job = state.job
  local t = clock()
  -- Time spent fighting (TargetBot holds the route) does not count.
  local gap = t - (job.lastTick or t)
  if gap > 1000 then
    job.started = job.started + gap
    job.lastMoveAt = job.lastMoveAt + gap
    if job.farMovedAt then job.farMovedAt = job.farMovedAt + gap end
    if job.noExitSince then job.noExitSince = job.noExitSince + gap end
    if job.pending then job.pending.untilAt = job.pending.untilAt + gap end
  end
  job.lastTick = t
  if t - job.started > JOB_TIME then return giveUp(job, "se agoto el tiempo") end
  if job.crossings >= MAX_CROSSINGS then return giveUp(job, "demasiados cambios de piso") end
  if job.failures >= MAX_FAILURES then return giveUp(job, "ningun acceso cercano funciono") end
  if manual() then CaveBot.delay(200); return true end
  if walking() then CaveBot.delay(100); return true end

  local here = key(position)
  if here ~= job.lastPos then job.lastPos, job.lastMoveAt, job.farMovedAt = here, t, t end

  local pending = job.pending
  if pending then
    if t < pending.untilAt then return true end
    job.pending = nil
    local exit = job.exit
    local nextMode = pending.rope and exit and exit.key == pending.key and exit.ropeModes and
      exit.ropeModes[(exit.ropeStep or 1) + 1]
    if nextMode then
      -- Same rope spot, the other way up (no rope in the backpack, or the spell failed).
      exit.ropeStep = (exit.ropeStep or 1) + 1
      log(nextMode == "spell" and ("Regreso de piso: la soga no subio; pruebo " .. MAGIC_ROPE) or
        ("Regreso de piso: " .. MAGIC_ROPE .. " no subio; pruebo la soga"), text(exit.pos))
    else
      state.failed[pending.key] = t + FAILED_TIME
      job.failures = job.failures + 1
      job.exit = nil
      log("Regreso de piso: ese acceso no cambio de piso; pruebo otro", text(pending.exit))
    end
  end
  if t < job.nextAt then return true end
  job.nextAt = t + 250

  local exit = job.exit
  if exit and (state.failed[exit.key] or 0) > t then exit = nil end
  if not exit then
    exit = selectExit(job, position)
    job.exit = exit
    job.lastMoveAt = t
    if not exit then
      local spot = job.lookout
      if spot and cheb(spot, position) <= 1 then job.looked[key(spot)] = true; spot = nil end
      -- Once walking to a way out of sight, the nearby lookouts are behind us (until the next crossing).
      if not spot and not job.far and not job.lookoutsDone then
        spot = lookout(job, position)
        if spot then log("Regreso de piso: no veo salida desde aqui; busco desde " .. text(spot)) end
      end
      job.lookout = spot
      if spot then
        if CaveBot.walkTo(spot, 30, {precision = 1, allowUnseen = true, allowOnlyVisibleTiles = false}) then
          job.noExitSince = nil
          return true
        end
        job.looked[key(spot)] = true
        job.lookout = nil
      end
      if not spot and farTurn(job, position, t) then
        job.noExitSince = nil
        return true
      end
      job.noExitSince = job.noExitSince or t
      if t - job.noExitSince > NO_EXIT_TIME then
        return giveUp(job, "no encuentro escaleras, huecos, soga ni escaleras de mano hacia ese piso " ..
          "(ni cerca, ni en la ruta, ni en el minimapa)")
      end
      job.nextAt = t + 500
      return true
    end
    job.noExitSince = nil
    log(string.format("Regreso de piso: voy a %s en %s", KIND_TEXT[exit.kind] or exit.kind, text(exit.pos)),
      "piso " .. position.z .. " -> " .. job.target)
  end

  if cheb(position, exit.pos) <= 1 and not (exit.kind == "step" and cheb(position, exit.pos) == 0) then
    if cross(job, exit, position) then return true end
    state.failed[exit.key] = t + FAILED_TIME
    job.failures = job.failures + 1
    job.exit = nil
    return true
  end
  if t - job.lastMoveAt > STALL_TIME then
    state.failed[exit.key] = t + FAILED_TIME
    job.failures = job.failures + 1
    job.exit = nil
    log("Regreso de piso: no avanzo hacia el acceso; pruebo otro", text(exit.pos))
    return true
  end
  if CaveBot.walkTo(exit.pos, 20, {precision = 1, allowUnseen = true, allowOnlyVisibleTiles = false}) then
    return true
  end
  state.failed[exit.key] = t + FAILED_TIME
  job.failures = job.failures + 1
  job.exit = nil
  return true
end

-- After a whole lap of failures the route cursor is anywhere: put it back on the goto
-- the character was following when it last stood on the route.
local function restoreCursor()
  local row, list = state.lastGoodRow, CaveBot.actionList
  if not row or not list or list:getFocusedChild() == row then return end
  local index = list:getChildIndex(row)
  if not index or index < 1 then return end
  list:focusChild(row)
  log("Regreso a la ruta: vuelvo al waypoint " .. index, "el que seguia al salir de la ruta")
end

-- Keeps an active job going; false once it ended (or the character is on its floor).
local function continueJob(position)
  local job = state.job
  if not job then return false end
  if position.z == job.target then finishJob(position); return false end
  return runJob(position)
end

-- Public API used by the goto action ------------------------------------------------
-- The goto's waypoint is on another floor. true = the goto waits ("retry").
local function wrongFloor(goal, position)
  if not F.enabled() or not goal or not position or othersMoving() then return false end
  local job = state.job
  if job then
    if not job.lap and goal.z ~= job.target then job.target = goal.z end
    return continueJob(position)
  end
  local t = clock()
  if t < state.cooldownUntil then state.fails = state.fails + 1; return false end
  if routeOnFloor(position) then
    -- The route goes on from this floor, unless no goto worked for a whole lap.
    state.suspect = nil
    state.fails = state.fails + 1
    local last = state.lastGood
    if lapReached() and last and last.z ~= position.z and
        startJob(last.z, position, "La ruta no continua en este piso", true) then
      restoreCursor()
      return runJob(position)
    end
    return false
  end
  -- Hold the goto a moment first: after a route's own rope/ladder use the server may
  -- still be moving the character to the floor this goto expects.
  local suspect = state.suspect
  if not suspect or suspect.z ~= position.z or suspect.goal ~= goal.z or t - suspect.seen > 1000 then
    state.suspect = {at = t, seen = t, z = position.z, goal = goal.z}
    return true
  end
  suspect.seen = t
  if t - suspect.at < CONFIRM_TIME then return true end
  state.suspect = nil
  if not startJob(goal.z, position, "Cambio de piso fuera de la ruta") then
    state.fails = state.fails + 1
    return false
  end
  return runJob(position)
end

-- Same floor, but the goto is out of reach. Returns "retry" (walking back), "advance"
-- (CaveBot.resyncRoute moved the route to the nearest waypoint) or nil (old behaviour).
local function lost(goal, position)
  if not F.enabled() or not goal or not position or othersMoving() then return nil end
  state.suspect = nil
  if state.job and continueJob(position) then return "retry" end
  state.fails = state.fails + 1
  local t = clock()
  local anchor = state.anchor
  if not anchor then
    local last = state.lastGood
    if not last or t < state.cooldownUntil or not lapReached() then return nil end
    if last.z ~= position.z then
      if startJob(last.z, position, "Ningun waypoint de la ruta es alcanzable", true) then
        restoreCursor()
        if runJob(position) then return "retry" end
      end
      return nil
    end
    if cheb(last, position) <= 1 then return nil end
    anchor = {pos = copy(last), started = t, lastTick = t}
    state.anchor = anchor
    alert("Ningun waypoint de la ruta es alcanzable desde aqui. Vuelvo a la ultima posicion de la ruta (" ..
      text(last) .. ").")
    restoreCursor()
  end
  if anchor.pos.z ~= position.z then state.anchor = nil; return nil end
  local gap = t - (anchor.lastTick or t)
  if gap > 1000 then anchor.started = anchor.started + gap end
  anchor.lastTick = t
  local function nearest(reason)
    state.anchor = nil
    local ok, moved = pcall(function() return CaveBot.resyncRoute and CaveBot.resyncRoute(reason) end)
    if ok and moved then state.fails = 0; return "advance" end
    giveUp({target = position.z}, "ni el punto de salida (" .. text(anchor.pos) .. ") ni otro waypoint cercano tienen camino")
    return nil
  end
  if cheb(anchor.pos, position) <= 1 then
    log("Regreso a la ruta: estoy donde deje la ruta, pero el waypoint sigue sin camino", text(goal))
    return nearest("Regreso a la ruta")
  end
  if t - anchor.started > ANCHOR_TIME then return nearest("Regreso a la ruta (tiempo agotado)") end
  if manual() then CaveBot.delay(200); return "retry" end
  if walking() then CaveBot.delay(100); return "retry" end
  if CaveBot.walkTo(anchor.pos, ANCHOR_RANGE, {precision = 1, allowUnseen = true, allowOnlyVisibleTiles = false}) then
    return "retry"
  end
  return nearest("Regreso a la ruta (sin camino al punto de salida)")
end

-- The goto is walking normally on its floor: the character is on the route.
local function progress(position)
  state.fails = 0
  state.giveUps = 0
  state.suspect = nil
  if state.job or state.anchor then
    state.job, state.anchor = nil, nil
    alert("De vuelta en la ruta (" .. text(position) .. "); sigue el waypoint pendiente.")
  end
  if #state.links > 0 then state.links = {} end
end

-- The goto's retry count without the turns spent here, so its own give-up limits
-- (5 with map click, 100 by steps) start again once the character is back.
local function retries(count)
  count = tonumber(count) or 0
  if count == 0 then state.retryBase = nil end
  if state.job or state.anchor or suspecting() then state.retryBase = count end
  return count - (state.retryBase or 0)
end

-- Diagnostics: who moved the character right before an unplanned floor change --------
-- Passive, also with the return switched off. The last bot steps are remembered with the
-- part of the bot that sent them; each unplanned floor change (CaveBot on, no route on
-- the new floor) is explained in the console and kept in storage.caveFloorLog.
local ROUTE_TAG, RETURN_TAG = "CaveBot (ruta)", "Regreso de piso"
local steps = {}
local mover, moverAt = nil, -1

local function released(...)
  mover = nil
  return ...
end

-- Names the steps sent while fn runs; the outermost name wins (a return that walks
-- through CaveBot.walkTo is still the return).
local function tagged(name, fn)
  if type(fn) ~= "function" then return fn end
  return function(...)
    local t = clock()
    if mover and moverAt == t then return fn(...) end
    mover, moverAt = name, t
    return released(fn(...))
  end
end

local function noteSteps(dirs, dest)
  local pos = player and player:getPosition()
  if not pos then return end
  local t = clock()
  local ctx = moverAt == t and mover or nil
  -- On the wrong floor the route's walker only carries the return's own path.
  if ctx == ROUTE_TAG and state.job and pos.z ~= state.job.target then ctx = RETURN_TAG end
  steps[#steps + 1] = {at = t, from = copy(pos), dirs = dirs, dest = dest, ctx = ctx}
  if #steps > STEP_MEMORY then table.remove(steps, 1) end
end

-- TargetBot and AttackBot load after CaveBot: their movers are named on the first step.
local lateDone = false
local function installLate()
  lateDone = true
  local function wrap(owner, field, name)
    if type(owner) == "table" and type(owner[field]) == "function" then owner[field] = tagged(name, owner[field]) end
  end
  wrap(TargetBot, "walkTo", "TargetBot (perseguir o mantener distancia)")
  wrap(TargetBot, "walk", "TargetBot (perseguir o mantener distancia)")
  wrap(TargetBot and TargetBot.Creature, "alignAndFace", "TargetBot (alinearse con el monstruo)")
  wrap(TargetBot and TargetBot.Antitrap, "send", "Antitrap (salir de un encierro)")
  wrap(AttackAlignment, "move", "AttackBot (reposicion para waves o beams)")
end

-- Every bot step goes through these globals; manual walking (keyboard, map click) does not.
local function installStepWatch()
  if type(safeBotWalk) == "function" then
    local original = safeBotWalk
    local wrapped = function(dir, ...)
      if not lateDone then pcall(installLate) end
      pcall(noteSteps, {dir})
      return original(dir, ...)
    end
    -- Keep `walk` identical to safeBotWalk (client_compat sets walk = safeBotWalk):
    -- HelperAPI.walk only tries walk() as a second attempt when the two differ.
    if walk == original then walk = wrapped end
    safeBotWalk = wrapped
  end
  if type(autoWalk) == "function" then
    local original = autoWalk
    autoWalk = function(target, ...)
      pcall(function()
        if type(target) ~= "table" then return end
        if type(target[1]) == "number" then
          local dirs = {}
          for i, dir in ipairs(target) do dirs[i] = dir end
          noteSteps(dirs)
        elseif target.x then
          noteSteps(nil, copy(target))
        end
      end)
      return original(target, ...)
    end
  end
  CaveBot.walkTo = tagged(ROUTE_TAG, CaveBot.walkTo)
  CaveBot.doWalking = tagged(ROUTE_TAG, CaveBot.doWalking)
end

-- The bot step (or path) that left from oldPos, and the tile it was going to. A single
-- step from there is the cause; a longer path only when its next tile is a floor change
-- (a path merely passing by does not explain a push).
local function stepFrom(oldPos, t)
  for i = #steps, 1, -1 do
    local s = steps[i]
    if s.dirs and t - s.at <= 1500 + 600 * #s.dirs then
      local p = s.from
      for _, dir in ipairs(s.dirs) do
        local o = OFFSETS[dir]
        if not o then break end
        local nextPos = {x = p.x + o[1], y = p.y + o[2], z = p.z}
        if p.x == oldPos.x and p.y == oldPos.y and p.z == oldPos.z then
          if #s.dirs == 1 or exitKind(nextPos) then return s, nextPos end
          break
        end
        p = nextPos
      end
    elseif s.dest and i == #steps and t - s.at <= 10000 then
      return s, nil -- a click-walk to a position: its path is not known
    end
  end
end

local function owners()
  local found = {}
  local function check(name, fn)
    local ok, on = pcall(fn)
    if ok and on then found[#found + 1] = name end
  end
  check("Antitrap activo", function() return TargetBot.Antitrap.ownsMovement() end)
  check("Push Max activo", function() return PushMax.ownsMovement() end)
  check("AutoExplorer encendido", function() return CaveBot.AutoExplorer.isOn() end)
  check("Pausa dinamica", function() return TargetBot.Creature.isHerdWaiting() end)
  local ok, name = pcall(function()
    local creature = g_game.getAttackingCreature()
    return creature and creature:getName()
  end)
  if ok and name then found[#found + 1] = "atacando a " .. tostring(name) end
  return found
end

local function manualRecent(t)
  local movement = TargetBot and TargetBot.Movement
  if movement and type(movement.isManual) == "function" then
    local ok, on = pcall(movement.isManual, t, true)
    if ok and on then return true end
  end
  local walking = modules and modules.game_walking
  local last = walking and tonumber(walking.lastManualWalk)
  return last ~= nil and last > 0 and t >= last and t - last < 1500
end

local function diagnose(newPos, oldPos)
  if not CaveBot.isOn() or othersMoving() then return end
  local job = state.job
  if job and job.pending and job.pending.from.z == oldPos.z then return end -- the return's own crossing
  if routeOnFloor(newPos) then return end -- the route goes on there: planned
  local t = clock()
  local step, entry = stepFrom(oldPos, t)
  local around = owners()
  local extra = #around > 0 and (" (" .. table.concat(around, ", ") .. ")") or ""
  local cause
  if step and step.ctx then
    cause = "paso del bot enviado por " .. step.ctx .. extra
  elseif step then
    cause = "paso del bot de otro modulo" .. (#around > 0 and extra or " o script")
  elseif manualRecent(t) then
    cause = "movimiento manual (teclado o clic en el mapa)"
  else
    cause = "ningun paso del bot ni tuyo: empujon de un jugador, teletransporte o el servidor" .. extra
  end
  if step and not step.dirs then cause = cause .. ", caminando con clic hacia " .. text(step.dest) end
  entry = entry or guessEntry(oldPos)
  local list = CaveBot.actionList
  local row = list and list:getFocusedChild()
  local index = row and list:getChildIndex(row) or 0
  alert(string.format("Cambio de piso no planeado (piso %d -> %d) desde %s%s, siguiendo el waypoint %d. " ..
    "Causa probable: %s.", oldPos.z, newPos.z, text(oldPos), entry and (" por " .. text(entry)) or "", index, cause))
  if type(storage) == "table" then
    local history = type(storage.caveFloorLog) == "table" and storage.caveFloorLog or {}
    history[#history + 1] = {at = os.date("%Y-%m-%d %H:%M:%S"), from = text(oldPos), to = text(newPos),
      entry = entry and text(entry) or nil, cause = cause, waypoint = index}
    while #history > FLOOR_LOG do table.remove(history, 1) end
    storage.caveFloorLog = history
  end
end

local diagnoseErrorAt = nil

-- Watch every crossing while CaveBot runs: where the route was left and how.
local function observe(newPos, oldPos)
  if not newPos or not oldPos then return end
  if newPos.z ~= oldPos.z then
    local ok, err = pcall(diagnose, newPos, oldPos)
    if not ok and (not diagnoseErrorAt or clock() - diagnoseErrorAt > 60000) then
      diagnoseErrorAt = clock()
      if RinoConsole and type(RinoConsole.log) == "function" then
        pcall(RinoConsole.log, "error", "CaveBot", "Diagnostico de cambio de piso: error interno", tostring(err))
      end
    end
  end
  if not F.enabled() then return end
  if not CaveBot.isOn() or othersMoving() then return end
  if newPos.z == oldPos.z then
    if not state.job and not state.anchor then
      local list = CaveBot.actionList
      local wp = gotoPos(list and list:getFocusedChild())
      if wp and wp.z == newPos.z and manhattan(wp, newPos) <= maxDistance() then
        local last = state.lastGood
        if not last or last.x ~= newPos.x or last.y ~= newPos.y or last.z ~= newPos.z then
          state.lastGood = copy(newPos)
        end
        state.lastGoodRow = list:getFocusedChild()
      end
    end
    return
  end
  local job = state.job
  local pending = job and job.pending
  local entry
  if pending and pending.from.z == oldPos.z then
    entry = pending.exit
    local delta = newPos.z - oldPos.z
    state.learned[pending.key] = delta
    job.pending = nil
    job.exit = nil
    job.far = nil
    job.lookoutsDone = nil -- a new floor: look around its landing again
    job.crossings = job.crossings + 1
    if math.abs(newPos.z - job.target) < math.abs(oldPos.z - job.target) then
      log("Regreso de piso: ahora en el piso " .. newPos.z, "objetivo " .. job.target)
    else
      state.failed[pending.key] = clock() + WRONG_TIME
      log("Regreso de piso: ese acceso lleva lejos de la ruta; vuelvo por donde vine", text(pending.exit))
    end
  else
    entry = guessEntry(oldPos)
    if entry and state.learned[key(entry)] == nil then state.learned[key(entry)] = newPos.z - oldPos.z end
  end
  local links = state.links
  local top = links[#links]
  if top and newPos.z == top.source.z then
    links[#links] = nil
  else
    links[#links + 1] = {source = copy(oldPos), landing = copy(newPos), entry = entry and copy(entry) or nil}
    if #links > LINK_LIMIT then table.remove(links, 1) end
  end
end

-- A mistake in here must never break the goto or a position callback: report it once a
-- minute, drop the job and fall back to the old behaviour for 5 minutes.
local errorAt = nil
local function guard(name, fn, fallback)
  return function(...)
    local ok, result = pcall(fn, ...)
    if ok then return result end
    local t = clock()
    if not errorAt or t - errorAt > 60000 then
      errorAt = t
      if RinoConsole and type(RinoConsole.log) == "function" then
        pcall(RinoConsole.log, "error", "CaveBot", "Regreso de piso: error interno en " .. name ..
          "; queda en pausa 5 min", tostring(result))
      end
    end
    state.job, state.anchor, state.suspect = nil, nil, nil
    state.cooldownUntil = math.max(state.cooldownUntil or 0, t + 300000)
    return fallback
  end
end
F.wrongFloor = guard("wrongFloor", tagged(RETURN_TAG, wrongFloor), false)
F.lost = guard("lost", tagged(RETURN_TAG, lost), nil)
F.progress = guard("progress", progress, nil)
local safeRetries = guard("retries", retries, nil)
F.retries = function(count) return safeRetries(count) or count end
onPlayerPositionChange(guard("observe", observe, nil))
local watching, watchError = pcall(installStepWatch)
if not watching and RinoConsole and type(RinoConsole.log) == "function" then
  pcall(RinoConsole.log, "error", "CaveBot", "Diagnostico de cambio de piso: no se pudo instalar", tostring(watchError))
end

return F
