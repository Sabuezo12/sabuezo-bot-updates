-- What a Follow leader tells its followers over Navi, besides its position: protection zone,
-- refill trip of its own supply check, and the CaveBot route and waypoint it is at.
-- collect() reads this character; read() validates what another Helper sent.
-- Followers use it (cavebot/follow_control.lua) to know when CaveBot should take movement
-- (leader in town, gone to refill) and where the route should go on (the leader's waypoint).
HelperFollowState = {}
local S = HelperFollowState

local function safe(fn)
  local ok, value = pcall(fn)
  if ok then return value end
end

function S.collect()
  local state = {}
  if safe(function() return type(isInPz) == "function" and isInPz() == true end) then state.pz = true end
  local check = CaveBot and CaveBot.Extensions and CaveBot.Extensions.SupplyCheck
  if check and type(check.trip) == "table" and check.trip.away == true then state.trip = true end
  -- Only while this character's own route runs (a paused follower is not a leader).
  state.cave = safe(function()
    if not CaveBot or type(CaveBot.isOn) ~= "function" or not CaveBot.isOn() then return nil end
    local list = CaveBot.actionList
    local route = type(CaveBot.getCurrentProfile) == "function" and CaveBot.getCurrentProfile()
    local child = list and list:getFocusedChild()
    if not child or type(route) ~= "string" or route == "" or #route > 64 then return nil end
    local index, count = list:getChildIndex(child), list:getChildCount()
    if type(index) ~= "number" or index < 1 or count < index then return nil end
    return {r = route, i = index, n = count}
  end)
  return state
end

-- nil when the message is not a valid state.
function S.read(value)
  if type(value) ~= "table" then return nil end
  local state = {pz = value.pz == true, trip = value.trip == true}
  local cave = value.cave
  if type(cave) == "table" and type(cave.r) == "string" and #cave.r >= 1 and #cave.r <= 64 and
      type(cave.i) == "number" and type(cave.n) == "number" and cave.i % 1 == 0 and cave.n % 1 == 0 and
      cave.i >= 1 and cave.n >= cave.i and cave.n <= 5000 then
    state.cave = {r = cave.r, i = cave.i, n = cave.n}
  end
  return state
end

return S
