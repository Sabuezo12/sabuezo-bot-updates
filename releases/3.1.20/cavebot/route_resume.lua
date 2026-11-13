-- Where a route should continue from, given where the character is standing.
--
-- Used when the bot is reloaded (the route used to restart at waypoint 1 whatever
-- the position was) and by Travel when the NPC cannot be found. Pure logic: it only
-- looks at the list of actions and a position, so it can be tested without the game.
CaveBot.RouteResume = {}
local R = CaveBot.RouteResume

local SAVED_WINDOW = 5      -- waypoints around the remembered one that are tried first
local SAVED_MAX_AGE = 1800  -- seconds a remembered position stays valid
local NEAR = 30             -- SQM: farther than this is not "near the route"
local PATH_CHECKS = 6       -- candidates checked for a real path, nearest first
local START_NEAR = 8        -- SQM: this close to the first waypoint means "at the start"

R.NEAR = NEAR

local function parseGoto(entry)
  if type(entry) ~= "table" or entry.action ~= "goto" then return nil end
  local x, y, z = tostring(entry.value or ""):match("^%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)")
  if not z then return nil end
  return {x = tonumber(x), y = tonumber(y), z = tonumber(z)}
end

-- entries: {{action=, value=}, ...} in route order; pos: {x=,y=,z=}.
-- opts: maxDist (goto's own limit, Manhattan), route, saved (what was remembered),
--       now (os.time), after (only waypoints after this index), hasPath(wp) -> bool.
-- Returns {index, wp, distance, tier, verified} or nil plus the reason.
function R.pick(entries, pos, opts)
  opts = opts or {}
  if type(entries) ~= "table" or #entries == 0 then return nil, "la ruta esta vacia" end
  if type(pos) ~= "table" or not pos.x then return nil, "sin posicion del personaje" end
  local maxDist = tonumber(opts.maxDist) or 24
  local after = tonumber(opts.after) or 0

  -- The remembered waypoint says which part of the route we were in, which a position
  -- alone cannot: the same corridor is often walked on the way out and on the way back.
  local savedIndex
  local saved = opts.saved
  if type(saved) == "table" and saved.route == opts.route and tonumber(saved.index) and
      tonumber(saved.count) == #entries and type(saved.at) == "number" and
      (tonumber(opts.now) or 0) - saved.at <= SAVED_MAX_AGE and
      saved.index >= 1 and saved.index <= #entries then
    savedIndex = saved.index
  end

  local candidates = {}
  local firstGotoIndex
  for i, entry in ipairs(entries) do
    local wp = i > after and parseGoto(entry) or nil
    if wp and not firstGotoIndex then firstGotoIndex = i end
    if wp and wp.z == pos.z then
      local dx, dy = math.abs(wp.x - pos.x), math.abs(wp.y - pos.y)
      if math.max(dx, dy) <= NEAR and dx + dy <= maxDist then
        candidates[#candidates + 1] = {
          index = i, wp = wp, distance = math.max(dx, dy),
          fromSaved = savedIndex and math.abs(i - savedIndex) or nil,
        }
      end
    end
  end
  if #candidates == 0 then
    return nil, "ningun waypoint de este piso esta a menos de " .. NEAR .. " casillas"
  end

  local function nearestFirst(a, b)
    if a.distance ~= b.distance then return a.distance < b.distance end
    if a.fromSaved and b.fromSaved and a.fromSaved ~= b.fromSaved then return a.fromSaved < b.fromSaved end
    return a.index < b.index
  end

  local function choose(list, tier)
    table.sort(list, nearestFirst)
    local first
    for n = 1, math.min(#list, PATH_CHECKS) do
      local candidate = list[n]
      first = first or candidate
      if type(opts.hasPath) ~= "function" or opts.hasPath(candidate.wp) then
        candidate.tier, candidate.verified = tier, type(opts.hasPath) == "function"
        return candidate
      end
    end
    -- No path could be confirmed (map not loaded yet?): the nearest one is still the
    -- best guess, and the goto action itself skips a waypoint it cannot reach.
    first.tier, first.verified = tier, false
    return first
  end

  if savedIndex then
    local window = {}
    for _, candidate in ipairs(candidates) do
      if candidate.fromSaved <= SAVED_WINDOW then window[#window + 1] = candidate end
    end
    if #window > 0 then return choose(window, "guardado") end
  end

  -- Standing at the very start of the route: that is where it begins, even if a later
  -- waypoint (the way back) happens to be a step closer.
  if after == 0 and not savedIndex then
    for _, candidate in ipairs(candidates) do
      if candidate.index == firstGotoIndex and candidate.distance <= START_NEAR and
          (type(opts.hasPath) ~= "function" or opts.hasPath(candidate.wp)) then
        candidate.tier, candidate.verified = "inicio", type(opts.hasPath) == "function"
        return candidate
      end
    end
  end
  return choose(candidates, "posicion")
end

return R
