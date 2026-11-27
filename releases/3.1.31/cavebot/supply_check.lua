CaveBot.Extensions.SupplyCheck = {}

-- Refill trips for other modules (Auto Party leader relay, kicks while the leader is away):
-- seq grows each time a check sends the character to refill; away stays true until the route
-- reaches that check's hunt label again (label row or go to label). hits[label] = labelSeq of
-- the last time each label was reached, so a missed tick or a reload cannot lose the return.
local refillTrip = {seq = 0, labelSeq = 0, away = false, hits = {}}
CaveBot.Extensions.SupplyCheck.trip = refillTrip
CaveBot.Extensions.SupplyCheck.reachedLabel = function(value)
  if type(value) ~= "string" then return end
  local label = value:trim():lower()
  refillTrip.labelSeq = refillTrip.labelSeq + 1
  refillTrip.lastLabel = label
  refillTrip.hits[label] = refillTrip.labelSeq
  if refillTrip.away and label == refillTrip.label then refillTrip.away = false end
end
local function startRefillTrip(label, reason)
  refillTrip.seq = refillTrip.seq + 1
  refillTrip.label = tostring(label or ""):trim():lower()
  refillTrip.reason = reason
  refillTrip.at = now
  refillTrip.away = true
end

-- The supply check's own reasons to go on refill, read without running the check (for
-- the Follow/CaveBot coordinator: a follower whose route is paused never reaches its check).
-- The lap limit is left out: it counts laps of the route, not supplies.
CaveBot.Extensions.SupplyCheck.needsRefill = function()
  local ok, reason = pcall(function()
    local flags = storage.caveBot or {}
    if flags.forceRefill then return "refill forzado" end
    if flags.backStop or flags.backTrainers or flags.backOffline then return "vuelta a la ciudad pedida" end
    local info = Supplies.getAdditionalData()
    if info.imbues.enabled and player:getSkillLevel(11) == 0 then return "imbues" end
    if info.stamina.enabled and stamina() < tonumber(info.stamina.value) then return "stamina" end
    if info.softBoots.enabled and itemAmount(6529) + itemAmount(3549) < 1 then return "soft boots" end
    local missing = Supplies.hasEnough()
    if type(missing) == "table" then return "item " .. tostring(missing.id) end
    if info.capacity.enabled and freecap() < tonumber(info.capacity.value) then return "capacidad" end
  end)
  if ok then return reason end
end

local supplyRetries = 0
local missedChecks = 0
local rawRound = 0
local time = now
local CAVEBOT_DATA_LIMIT = 200
vBot.CaveBotData =
  vBot.CaveBotData or
  {
    refills = 0,
    rounds = 0,
    time = {},
    lastRefill = os.time(),
    refillTime = {}
  }
vBot.CaveBotData.time = vBot.CaveBotData.time or {}
vBot.CaveBotData.refillTime = vBot.CaveBotData.refillTime or {}

local function setSupplyStatus(text, color)
  if CaveBot and CaveBot.Diagnostics and CaveBot.Diagnostics.setSupplyStatus then
    CaveBot.Diagnostics.setSupplyStatus(text, color)
  end
end

local function trimData(t)
  while #t > CAVEBOT_DATA_LIMIT do
    table.remove(t, 1)
  end
end

local function setCaveBotData(hunting)
  if hunting then
    supplyRetries = supplyRetries + 1
  else
    supplyRetries = 0
    table.insert(vBot.CaveBotData.refillTime, os.difftime(os.time() - vBot.CaveBotData.lastRefill))
    trimData(vBot.CaveBotData.refillTime)
    vBot.CaveBotData.lastRefill = os.time()
    vBot.CaveBotData.refills = vBot.CaveBotData.refills + 1
  end

  table.insert(vBot.CaveBotData.time, rawRound)
  trimData(vBot.CaveBotData.time)
  vBot.CaveBotData.rounds = vBot.CaveBotData.rounds + 1
  missedChecks = 0
end

CaveBot.Extensions.SupplyCheck.setup = function()
  CaveBot.registerAction(
    "supplyCheck",
    "#db5a5a",
    function(value)
      local data = string.split(value, ",")
      local round = 0
      rawRound = 0
      local label = data[1]:trim()
      local pos = nil
      if #data == 4 then
        pos = {x = tonumber(data[2]), y = tonumber(data[3]), z = tonumber(data[4])}
      end

      if pos then
        local checkDistance = getDistanceBetween(player:getPosition(), pos)
        if checkDistance and checkDistance > 10 then
          missedChecks = missedChecks + 1
          print("CaveBot[SupplyCheck]: Away from saved check position (" .. checkDistance .. " sqm), checking supplies anyway.")
        else
          missedChecks = 0
        end
      end

      if time then
        rawRound = math.ceil((now - time) / 1000)
        round = rawRound .. "s"
      else
        round = ""
      end
      time = now

      local softCount = itemAmount(6529) + itemAmount(3549)
      local supplyData = Supplies.hasEnough()
      local supplyInfo = Supplies.getAdditionalData()

      if storage.caveBot.forceRefill then
        setSupplyStatus("Forced refill", "#ffaa00")
        print("CaveBot[SupplyCheck]: User forced, going back on refill. Last round took: " .. round)
        storage.caveBot.forceRefill = false
        startRefillTrip(label, "forced")
        supplyRetries = 0
        missedChecks = 0
        return false
      elseif storage.caveBot.backStop then
        setSupplyStatus("Back stop", "#ffaa00")
        print("CaveBot[SupplyCheck]: User forced, going back to city and turning off CaveBot. Last round took: " .. round)
        startRefillTrip(label, "backStop")
        supplyRetries = 0
        missedChecks = 0
        return false
      elseif storage.caveBot.backTrainers then
        setSupplyStatus("Back trainers", "#ffaa00")
        print("CaveBot[SupplyCheck]: User forced, going back to city, then on trainers. Last round took: " .. round)
        startRefillTrip(label, "backTrainers")
        supplyRetries = 0
        missedChecks = 0
        return false
      elseif storage.caveBot.backOffline then
        setSupplyStatus("Back offline", "#ffaa00")
        print("CaveBot[SupplyCheck]: User forced, going back to city, then on offline training. Last round took: " .. round)
        startRefillTrip(label, "backOffline")
        supplyRetries = 0
        missedChecks = 0
        return false
      elseif supplyRetries > (storage.extras.huntRoutes or 50) then
        setSupplyStatus("Refill: route limit", "#ff7777")
        print("CaveBot[SupplyCheck]: Round limit reached, going back on refill. Last round took: " .. round)
        setCaveBotData()
        startRefillTrip(label, "refill")
        return false
      elseif (supplyInfo.imbues.enabled and player:getSkillLevel(11) == 0) then
        setSupplyStatus("Refill: imbues", "#ff7777")
        print("CaveBot[SupplyCheck]: Imbues ran out. Going on refill. Last round took: " .. round)
        setCaveBotData()
        startRefillTrip(label, "refill")
        return false
      elseif (supplyInfo.stamina.enabled and stamina() < tonumber(supplyInfo.stamina.value)) then
        setSupplyStatus("Refill: stamina", "#ff7777")
        print("CaveBot[SupplyCheck]: Stamina ran out. Going on refill. Last round took: " .. round)
        setCaveBotData()
        startRefillTrip(label, "refill")
        return false
      elseif (supplyInfo.softBoots.enabled and softCount < 1) then
        setSupplyStatus("Refill: soft boots", "#ff7777")
        print("CaveBot[SupplyCheck]: No soft boots left. Going on refill. Last round took: " .. round)
        setCaveBotData()
        startRefillTrip(label, "refill")
        return false
      elseif type(supplyData) == "table" then
        setSupplyStatus("Refill: item " .. supplyData.id, "#ff7777")
        print("CaveBot[SupplyCheck]: Not enough item: " .. supplyData.id .. "(only " .. supplyData.amount .. " left; " ..
          tostring(supplyData.source) .. "). Going on refill. Last round took: " .. round)
        setCaveBotData()
        startRefillTrip(label, "refill")
        return false
      elseif (supplyInfo.capacity.enabled and freecap() < tonumber(supplyInfo.capacity.value)) then
        setSupplyStatus("Refill: cap", "#ff7777")
        print("CaveBot[SupplyCheck]: Not enough capacity. Going on refill. Last round took: " .. round)
        setCaveBotData()
        startRefillTrip(label, "refill")
        return false
      else
        setSupplyStatus("Hunting " .. (supplyRetries + 1) .. "/" .. (storage.extras.huntRoutes or 50), "#66ff66")
        -- Which amounts the decision used, so a wrong count shows in the log.
        local checked = Supplies.describeLastCheck and Supplies.describeLastCheck() or ""
        print("CaveBot[SupplyCheck]: Enough supplies. Hunting. Round (" .. supplyRetries .. "/" .. (storage.extras.huntRoutes or 50) .. "). Last round took: " .. round ..
          (checked ~= "" and (" | " .. checked) or " | sin items de supplies en el perfil"))
        setCaveBotData(true)
        refillTrip.away = false
        return CaveBot.gotoLabel(label)
      end
    end
  )

  CaveBot.Editor.registerAction(
    "supplycheck",
    "supply check",
    {
      value = function()
        return "startHunt," .. posx() .. "," .. posy() .. "," .. posz()
      end,
      title = "Supply check label",
      description = "Insert here hunting start label",
      validation = [[[^,]+,\d{1,5},\d{1,5},\d{1,2}$]]
    }
  )
end
