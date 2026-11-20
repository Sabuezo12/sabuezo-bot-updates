setDefaultTab("HP")
---UI.Separator()
if type(storage.foodItems) ~= "table" then
  storage.foodItems = {3607, 3592, 3600, 3601, 3725, 3582, 3577, 3578, 3583, 3723, 3731, 3732, 3595, 3593}
end
-- The default list holds bare item ids, but the container widget (and the looting code)
-- store {id=, count=}. Reading a bare id as a table made this macro fail on every tick
-- (tens of thousands of log lines); keep a single shape.
for index, entry in ipairs(storage.foodItems) do
  if type(entry) == "number" then storage.foodItems[index] = {id = entry, count = 1} end
end

local FALLBACK_DEFAULT = "exevo pan"
-- The word is said only after this long hungry with nothing to eat, so a hunger that clears by
-- itself (a food gets opened, you eat by hand) never triggers it. It then repeats every 5 s.
local FALLBACK_DELAY_MS = 15000
local FALLBACK_REPEAT_MS = 5000

local helperFood = Helper and Helper.valid() and not (storage.helperUI and storage.helperUI.legacy == true)
if helperFood then storage.helperUI=type(storage.helperUI)=="table" and storage.helperUI or {} end

local function consoleLog(level, message, detail)
  if type(RinoConsole) ~= "table" or type(RinoConsole.valid) ~= "function" then return end
  local ok, valid = pcall(RinoConsole.valid)
  if ok and valid then pcall(RinoConsole.log, level, "Eat Food", message, detail) end
end

local function hungry()
  return player:getRegenerationTime() <= 400
end

-- First configured food found in the open containers, or nil. Both "nothing configured"
-- and "configured but none in the open containers" mean there is nothing to eat.
local function findFood()
  local list = storage.foodItems
  if type(list) ~= "table" or not list[1] then return nil end
  local wanted = {}
  for _, foodItem in ipairs(list) do
    local foodId = type(foodItem) == "table" and foodItem.id or foodItem
    if foodId then wanted[foodId] = true end
  end
  for _, container in pairs(g_game.getContainers()) do
    for _, item in ipairs(container:getItems()) do
      if wanted[item:getId()] then return item end
    end
  end
  return nil
end

local eatFoodMacro = macro(5000, "Eat Food", function()
  if not hungry() then return end
  local item = findFood()
  if not item then return end
  if PushMax and type(PushMax.performItem)=='function'then return PushMax.performItem('Eat Food',item,false,g_game.use,item)end
  return g_game.use(item)
end)

local foodContainer = UI.Container(function(widget, items)
  storage.foodItems = items
end, true)
foodContainer:setHeight(56)
foodContainer:setItems(storage.foodItems)

-- The word/spell said when the bot is hungry and has nothing to eat. It lives next to
-- the "choice" flag; legacy (non-Helper) mode keeps it in storage and uses the default.
local function settingsTable()
  if helperFood then return storage.helperUI end
  return storage
end
local function fallbackWord()
  local word = settingsTable().foodFallbackWord
  if type(word) ~= "string" then word = FALLBACK_DEFAULT end
  word = word:gsub("^%s+", "")
  word = word:gsub("%s+$", "")
  return word
end

local function isKnownSpell(word)
  if type(getSpellData) ~= "function" then return false end
  local ok, data = pcall(getSpellData, word)
  return ok and type(data) == "table"
end

local function sayFallback(word)
  -- A real spell goes through cast() (cooldown/mana aware); any other word (a command, an
  -- NPC phrase) is just said.
  if isKnownSpell(word) and type(cast) == "function" then return cast(word, 5000) end
  if type(say) == "function" then return say(word) end
end

-- One log line per hunger episode, not one per tick.
local reportedEpisode = false
local noFoodSince, lastSaid, lastTick
local function clockMs() return tonumber(now) or os.time() * 1000 end
local conjureFoodMacro = macro(1000, "Conjure Food", function()
  local current = clockMs()
  -- A gap means the macro was OFF or paused: the next hunger starts its wait from zero.
  if lastTick and current - lastTick > 3000 then noFoodSince, lastSaid = nil, nil end
  lastTick = current
  -- In Helper, this needs the user's explicit choice and food master ON.
  if helperFood and (storage.helperUI.foodConjureChoice~=true or not eatFoodMacro.isOn()) then return end
  if not hungry() then reportedEpisode = false; noFoodSince, lastSaid = nil, nil; return end
  -- Something to eat: Eat Food handles it, nothing to say.
  if findFood() then reportedEpisode = false; noFoodSince, lastSaid = nil, nil; return end
  noFoodSince = noFoodSince or current
  if current - noFoodSince < FALLBACK_DELAY_MS then return end
  local word = fallbackWord()
  if word == "" then return end
  if lastSaid and current - lastSaid < FALLBACK_REPEAT_MS then return end
  lastSaid = current
  sayFallback(word)
  if not reportedEpisode then
    reportedEpisode = true
    consoleLog("action", "Sin comida que comer: dije '" .. word .. "'",
      "Espero " .. (FALLBACK_DELAY_MS / 1000) .. " s sin comida antes de decirlo y lo repito cada " ..
      (FALLBACK_REPEAT_MS / 1000) .. " s. Busca solo en los contenedores abiertos. Cambia la palabra o desmarca la opcion en Condiciones > Comida.")
  end
end)

UI.Separator()
-- Separate the master (eating) from the explicit "no food" choice.
-- Ignore the old combined ON choice; it did not mean the user chose a spell.
if helperFood and (storage.helperUI.foodConjureChoice~=true or not eatFoodMacro.isOn()) then conjureFoodMacro.setOff() end
local function setFoodMacro(handle,value)
  if handle.isOn()~=value then
    if value then handle.setOn() else handle.setOff() end
  end
end
HelperFoodBridge = {}
function HelperFoodBridge.getPowers()
  return {{key="eat",read=function() return eatFoodMacro.isOn()==true end,
    set=function(value)
      setFoodMacro(eatFoodMacro,value)
      if helperFood then
        setFoodMacro(conjureFoodMacro,value and storage.helperUI.foodConjureChoice==true)
      end
    end}}
end
function HelperFoodBridge.isConjureSelected()
  if helperFood then return storage.helperUI.foodConjureChoice==true end
  return conjureFoodMacro.isOn()==true
end
function HelperFoodBridge.setConjureSelected(value)
  value=value==true
  if helperFood then
    storage.helperUI.foodConjureChoice=value
    setFoodMacro(conjureFoodMacro,value and eatFoodMacro.isOn())
  else setFoodMacro(conjureFoodMacro,value) end
end
function HelperFoodBridge.getFallbackWord()
  return fallbackWord()
end
function HelperFoodBridge.getFallbackDelay()
  return FALLBACK_DELAY_MS / 1000
end
function HelperFoodBridge.setFallbackWord(word)
  settingsTable().foodFallbackWord = tostring(word or "")
end
function HelperFoodBridge.getFoodCount()
  return type(storage.foodItems) == "table" and #storage.foodItems or 0
end
