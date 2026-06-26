setDefaultTab("Tools")

local panelName = "caveBotHud"
if type(storage[panelName]) ~= "table" then
  storage[panelName] = {
    maxSupplies = 5
  }
end
local config = storage[panelName]
config.enabled = true
config.maxSupplies = tonumber(config.maxSupplies) or 5

local hudPanel = setupUI([[
CaveBotHudLabel < Label
  height: 12
  background-color: #00000055
  opacity: 0.92
  text-auto-resize: true
  font: verdana-11px-rounded
  anchors.left: parent.left
  $first:
    anchors.top: parent.top
  $!first:
    anchors.top: prev.bottom

Panel
  id: caveBotHudPanel
  height: 12
  width: 220
  anchors.left: parent.left
  anchors.bottom: parent.bottom
  margin-bottom: 5
  margin-left: 5
]], modules.game_interface.getMapPanel())

local lines = {}

local function formatNumber(value)
  local n = tonumber(value) or 0
  local sign = n < 0 and "-" or ""
  local text = tostring(math.floor(math.abs(n)))
  while true do
    local updated, count = text:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
    text = updated
    if count == 0 then break end
  end
  return sign .. text
end

local function formatDuration(seconds)
  local value = math.max(0, math.floor(tonumber(seconds) or 0))
  local hours = math.floor(value / 3600)
  local minutes = math.floor((value % 3600) / 60)
  local secs = value % 60

  if hours > 0 then
    return string.format("%02dh %02dm", hours, minutes)
  end
  return string.format("%02dm %02ds", minutes, secs)
end

local function shortName(text, limit)
  text = tostring(text or "")
  limit = tonumber(limit) or 14
  if #text <= limit then return text end
  return text:sub(1, math.max(1, limit - 1)) .. "."
end

local function isOn(mod)
  if not mod or not mod.isOn then return false end
  local ok, result = pcall(mod.isOn)
  return ok and result == true
end

local function compactText(text, limit)
  text = tostring(text or "-")
  limit = tonumber(limit) or 28
  if #text <= limit then return text end
  return text:sub(1, math.max(1, limit - 1)) .. "."
end

local function getCurrentProfile()
  if CaveBot and CaveBot.getCurrentProfile then
    local ok, profile = pcall(CaveBot.getCurrentProfile)
    if ok and profile and tostring(profile) ~= "" then
      return tostring(profile)
    end
  end

  if storage and storage._configs and storage._configs.cavebot_configs then
    local profile = storage._configs.cavebot_configs.selected
    if profile and tostring(profile) ~= "" then return tostring(profile) end
  end

  return "-"
end

local function getActionText()
  local list = CaveBot and CaveBot.actionList
  if not list then return "-" end

  local current = list:getFocusedChild() or list:getFirstChild()
  if not current then return "-" end

  local index = list:getChildIndex(current) or 0
  local total = list:getChildCount() or 0
  local text = index .. "/" .. total .. " " .. tostring(current.action or "-")

  if current.value and tostring(current.value) ~= "" then
    text = text .. ":" .. tostring(current.value):split("\n")[1]
  end

  return compactText(text, 34)
end

local function getLabelText()
  local lastLabel = CaveBot and CaveBot.lastReachedLabel and CaveBot.lastReachedLabel() or ""
  local nextLabel = CaveBot and CaveBot.getNextLabel and CaveBot.getNextLabel() or ""
  if tostring(lastLabel) == "" then lastLabel = "-" end
  if tostring(nextLabel) == "" then nextLabel = "-" end
  return compactText(tostring(lastLabel) .. " > " .. tostring(nextLabel), 34)
end

local function getStats()
  if SabuezoAnalyzer and SabuezoAnalyzer.getCaveBotStats then
    local ok, stats = pcall(SabuezoAnalyzer.getCaveBotStats)
    if ok and type(stats) == "table" then
      stats.supplies = type(stats.supplies) == "table" and stats.supplies or {}
      return stats
    end
  end

  local data = vBot and vBot.CaveBotData or {}
  return {
    rounds = tonumber(data.rounds) or 0,
    deaths = 0,
    deathLimit = 0,
    refills = tonumber(data.refills) or 0,
    avgRound = 0,
    avgRefill = 0,
    lastRefill = os.time() - (tonumber(data.lastRefill) or os.time()),
    supplies = {}
  }
end

local function getTrackedItemAmount(id)
  id = tonumber(id)
  if not id then return 0 end

  local visible = 0
  if player and player.getItemsCount then
    visible = tonumber(player:getItemsCount(id)) or 0
  end

  if vBot and vBot.ItemCounter and vBot.ItemCounter.getAmountInfo then
    local ok, current = pcall(vBot.ItemCounter.getAmountInfo, id, visible)
    if ok then return tonumber(current) or 0 end
  end
  if itemAmount then
    local ok, amount = pcall(itemAmount, id)
    if ok then return tonumber(amount) or visible end
  end
  return visible
end

local function registerSupplyHudItem(id, data)
  id = tonumber(id)
  if not id or id <= 100 then return end

  if vBot and vBot.ItemCounter then
    if vBot.ItemCounter.registerSupplyItem then
      pcall(vBot.ItemCounter.registerSupplyItem, id, data or {})
    elseif vBot.ItemCounter.registerItemId then
      pcall(vBot.ItemCounter.registerItemId, id)
    end
  end
end

local function getSupplyItemName(id)
  local name = tostring(id)
  if vBot and vBot.ItemCounter and vBot.ItemCounter.getName then
    local ok, value = pcall(vBot.ItemCounter.getName, id)
    if ok and value and tostring(value) ~= "" then
      name = tostring(value)
    end
  end
  return name
end

local function getSupplyItemUsed(id)
  if vBot and vBot.ItemCounter and vBot.ItemCounter.getUsed then
    local ok, used = pcall(vBot.ItemCounter.getUsed, id)
    if ok then return tonumber(used) or 0 end
  end
  return 0
end

local function buildSupplyStatsFromData(data)
  local items = {}
  if type(data) ~= "table" then return items end

  for id, values in pairs(data) do
    local numericId = tonumber(id)
    if numericId and numericId > 100 and type(values) == "table" then
      registerSupplyHudItem(numericId, values)
      table.insert(items, {
        id = numericId,
        name = getSupplyItemName(numericId),
        current = getTrackedItemAmount(numericId),
        used = getSupplyItemUsed(numericId)
      })
    end
  end

  table.sort(items, function(a, b)
    return tostring(a.name):lower() < tostring(b.name):lower()
  end)
  return items
end

local function getSupplyDataFromConfig()
  local profiles = SuppliesConfig and SuppliesConfig.supplies
  if type(profiles) ~= "table" then return nil end

  local profileName = profiles.currentProfile
  local profile = profileName and profiles[profileName] or nil
  if type(profile) ~= "table" then
    for key, value in pairs(profiles) do
      if key ~= "currentProfile" and type(value) == "table" then
        profile = value
        break
      end
    end
  end

  if type(profile) ~= "table" then return nil end
  return profile.items
end

local function getHudSupplyItems(stats)
  if Supplies and Supplies.getItemsData then
    local ok, data = pcall(Supplies.getItemsData)
    if ok then
      local items = buildSupplyStatsFromData(data)
      if #items > 0 then return items end
    end
  end

  local configItems = buildSupplyStatsFromData(getSupplyDataFromConfig())
  if #configItems > 0 then return configItems end

  local supplies = stats and stats.supplies or nil
  if type(supplies) == "table" and #supplies > 0 then
    return supplies
  end

  return {}
end

local function ensureLine(index)
  if not lines[index] then
    local label = UI.createWidget("CaveBotHudLabel", hudPanel)
    label:setId("line" .. index)
    lines[index] = label
  end
  lines[index]:setVisible(true)
  return lines[index]
end

local function hideUnused(fromIndex)
  for i = fromIndex, #lines do
    if lines[i] then
      lines[i]:setVisible(false)
    end
  end
end

local function setLine(index, parts)
  local label = ensureLine(index)
  label:setColoredText(parts)
end

local function updateHud()
  local caveOn = isOn(CaveBot)
  hudPanel:setVisible(caveOn == true)
  if not caveOn then
    return
  end

  local stats = getStats()
  local line = 1
  local targetOn = isOn(TargetBot)
  local deaths = tonumber(stats.deaths) or 0
  local deathLimit = tonumber(stats.deathLimit) or 0
  local deathText = deathLimit > 0 and (deaths .. "/" .. deathLimit) or tostring(deaths)

  setLine(line, {"~ Perfil: ", "#9dd1ce", compactText(getCurrentProfile(), 26), "#ffffff"})
  line = line + 1
  setLine(line, {"~ Accion: ", "#9dd1ce", getActionText(), "#ffffff"})
  line = line + 1
  setLine(line, {"~ Labels: ", "#9dd1ce", getLabelText(), "#ffffff"})
  line = line + 1
  setLine(line, {"~ CaveBot: ", "#9dd1ce", "ON", "green", "  Target: ", "#9dd1ce", targetOn and "ON" or "OFF", targetOn and "green" or "red"})
  line = line + 1
  setLine(line, {"~ Supply: ", "#9dd1ce", compactText(CaveBot.Diagnostics and CaveBot.Diagnostics.supplyStatus or "-", 28), CaveBot.Diagnostics and CaveBot.Diagnostics.supplyColor or "#cfd3d7"})
  line = line + 1
  setLine(line, {"~ Rondas: ", "white", formatNumber(stats.rounds), "#ffd166", "  Muertes: ", "white", deathText, deaths > 0 and "#ff6b6b" or "#74B73E"})
  line = line + 1
  setLine(line, {"~ Refills: ", "white", formatNumber(stats.refills), "#ffd166", "  Ult: ", "white", formatDuration(stats.lastRefill), "#9dd1ce"})
  line = line + 1
  setLine(line, {"~ Prom ronda: ", "white", formatDuration(stats.avgRound), "#9dd1ce", "  Refill: ", "white", formatDuration(stats.avgRefill), "#9dd1ce"})
  line = line + 1

  local supplies = getHudSupplyItems(stats)
  if #supplies > 0 then
    setLine(line, {"~ Supplies ", "#9dd1ce", "Actual/Gastado", "#ffd166"})
    line = line + 1

    local maxSupplies = math.max(1, tonumber(config.maxSupplies) or 5)
    for i, item in ipairs(supplies) do
      if i > maxSupplies then break end
      setLine(line, {
        "~ " .. shortName(item.name or item.id, 14) .. ": ", "white",
        formatNumber(item.current), "#ffffff",
        " / ", "#9dd1ce",
        formatNumber(item.used), "#ffd166"
      })
      line = line + 1
    end
  else
    setLine(line, {"~ Supplies: ", "#9dd1ce", "sin items configurados", "#cfd3d7"})
    line = line + 1
  end

  hideUnused(line)
  hudPanel:setHeight(math.max(12, (line - 1) * 13))
end

macro(1000, function()
  updateHud()
end)

updateHud()
