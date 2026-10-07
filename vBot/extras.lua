setDefaultTab("Main")

-- securing storage namespace
local panelName = "extras"
storage[panelName] = storage[panelName] or {}
local settings = storage[panelName]

-- Bot Settings keeps this script's storage and controls, but shares one window.
extrasWindow = BotSettings.window
local leftPanel, rightPanel = BotSettings.getColumns("basic")

-- objects made by Kondrah - taken from creature editor, minor changes to adapt
local addCheckBox = function(id, title, defaultValue, dest, tooltip)
  local widget = UI.createWidget('BotSettingsCheckBox', dest)
  widget.onClick = function()
    widget:setOn(not widget:isOn())
    settings[id] = widget:isOn()
    if id == "checkPlayer" then
      local label = rootWidget.newHealer.targetSettings.vocations.title
      if not widget:isOn() then
        label:setColor("#d9321f")
        label:setTooltip("! WARNING ! \nTurn on check players in extras to use this feature!")
      else
          label:setColor("#dfdfdf")
          label:setTooltip("")
      end
    end
  end
  widget:setText(title)
  widget:setTooltip(tooltip)
  if settings[id] == nil then
    widget:setOn(defaultValue)
  else
    widget:setOn(settings[id])
  end
  settings[id] = widget:isOn()
  return widget
end

local addItem = function(id, title, defaultItem, dest, tooltip)
  local widget = UI.createWidget('BotSettingsItem', dest)
  widget.text:setText(title)
  widget.text:setTooltip(tooltip)
  widget.item:setTooltip(tooltip)
  widget.item:setItemId(settings[id] or defaultItem)
  widget.item.onItemChange = function(widget)
    settings[id] = widget:getItemId()
  end
  settings[id] = settings[id] or defaultItem
end

local addTextEdit = function(id, title, defaultValue, dest, tooltip)
  local widget = UI.createWidget('BotSettingsTextEdit', dest)
  widget.text:setText(title)
  widget.textEdit:setText(settings[id] or defaultValue or "")
  widget.text:setTooltip(tooltip)
  widget.textEdit.onTextChange = function(widget,text)
    settings[id] = text
  end
  settings[id] = settings[id] or defaultValue or ""
end

local addScrollBar = function(id, title, min, max, defaultValue, dest, tooltip)
  local widget = UI.createWidget('BotSettingsScrollBar', dest)
  widget.text:setTooltip(tooltip)
  widget.scroll:setRange(min, max)
  widget.scroll.onValueChange = function(scroll, value)
    widget.text:setText(title .. ": " .. value)
    if value == 0 then
      value = 1
    end
    settings[id] = value
  end
  widget.scroll:setTooltip(tooltip)
  if max-min > 1000 then
    widget.scroll:setStep(100)
  elseif max-min > 100 then
    widget.scroll:setStep(10)
  end
  widget.scroll:setValue(settings[id] or defaultValue)
  widget.scroll.onValueChange(widget.scroll, widget.scroll:getValue())
end

addItem("rope", "Rope Item", 3003, leftPanel, "This item will be used in various bot related scripts as default rope item.")
addItem("shovel", "Shovel Item", 3457, leftPanel, "This item will be used in various bot related scripts as default shovel item.")
addItem("machete", "Machete Item", 3308, leftPanel, "This item will be used in various bot related scripts as default machete item.")
addItem("scythe", "Scythe Item", 3453, leftPanel, "This item will be used in various bot related scripts as default scythe item.")
addScrollBar("maxUseDist", "Max Distance To Use", 1, 10, 2, leftPanel, "Max distance to 'Use All' hotkey.")

if not settings.useAll or settings.useAll == "" or settings.useAll == "space" then
  settings.useAll = "|"
end

addTextEdit("useAll", "Use All Hotkey", "|", rightPanel,
  "Set hotkey for universal actions - rope, shovel, scythe, use, open doors")
if true then
  local useId = Global.useIds
  local shovelId = Global.shovelIds
  local ropeId = Global.ropeIds
  local macheteId = Global.macheteIds
  local scytheId = Global.scytheIds
  local lastUseAll = -1000

  setDefaultTab("Tools")

  local function clockMillis()
    if now then
      return now
    elseif g_clock and g_clock.millis then
      return g_clock.millis()
    end
    return 0
  end

  local function normalizeKey(key)
    key = tostring(key or ""):lower()
    if key == "spacebar" then
      return "space"
    end
    return key
  end

  local function useAllKeyMatches(key)
    local wanted = normalizeKey(settings.useAll)
    local pressed = normalizeKey(key)

    if wanted == "|" then
      return pressed == "|" or pressed == "\\" or pressed == "backslash" or
        pressed == "oem_5" or pressed == "oem5"
    end

    return wanted ~= "" and pressed == wanted
  end

  local function directionPriority(tilePos)
    local playerPos = pos()
    local dir = player:getDirection()
    local front = { x = playerPos.x, y = playerPos.y, z = playerPos.z }

    if dir == 0 then
      front.y = front.y - 1
    elseif dir == 1 then
      front.x = front.x + 1
    elseif dir == 2 then
      front.y = front.y + 1
    elseif dir == 3 then
      front.x = front.x - 1
    end

    if tilePos.x == front.x and tilePos.y == front.y and tilePos.z == front.z then
      return 0
    elseif tilePos.x == playerPos.x and tilePos.y == playerPos.y and tilePos.z == playerPos.z then
      return 1
    end

    return 2
  end

  local function safeUse(func, ...)
    if not func then
      return false
    end
    local ok, result = pcall(func, ...)
    return ok and result ~= false
  end

  local function useAllTiles()
    local tiles = {}
    local maxDistance = settings.maxUseDist or 2

    for _, tile in pairs(g_map.getTiles(posz())) do
      local distance = distanceFromPlayer(tile:getPosition())
      if distance <= maxDistance then
        table.insert(tiles, {
          tile = tile,
          distance = distance,
          priority = directionPriority(tile:getPosition())
        })
      end
    end

    table.sort(tiles, function(a, b)
      if a.priority ~= b.priority then
        return a.priority < b.priority
      end
      return a.distance < b.distance
    end)

    for _, entry in ipairs(tiles) do
      local topUseThing = entry.tile:getTopUseThing()
      if topUseThing and table.find(Global.doorIds or {}, topUseThing:getId()) then
        if safeUse(use, topUseThing) then return true end
      end

      for _, item in pairs(entry.tile:getItems()) do
        local id = item:getId()
        if table.find(useId, id) then
          if safeUse(use, item) then return true end
        elseif table.find(shovelId, id) then
          if safeUse(useWith, settings.shovel, item) then return true end
        elseif table.find(ropeId, id) then
          if safeUse(useWith, settings.rope, item) then return true end
        elseif table.find(macheteId, id) then
          if safeUse(useWith, settings.machete, item) then return true end
        elseif table.find(scytheId, id) then
          if safeUse(useWith, settings.scythe, item) then return true end
        end
      end
    end
    return false
  end

  local function triggerUseAll()
    local currentTime = clockMillis()
    if currentTime - lastUseAll < 150 then
      return
    end
    lastUseAll = currentTime
    useAllTiles()
  end

  onKeyDown(function(key)
    if useAllKeyMatches(key) then
      triggerUseAll()
    end
  end)
end

addCheckBox("title", "Custom Window Title", true, rightPanel, "Personalize OTCv8 window name according to character specific.")
if true then
  local vocText = ""

  if voc() == 1 or voc() == 11 then
      vocText = "- EK"
  elseif voc() == 2 or voc() == 12 then
      vocText = "- RP"
  elseif voc() == 3 or voc() == 13 then
      vocText = "- MS"
  elseif voc() == 4 or voc() == 14 then
      vocText = "- ED"
  end

  macro(5000, function()
    if settings.title then
      if hppercent() > 0 then
          g_window.setTitle("Tibia - " .. name() .. " - " .. lvl() .. "lvl " .. vocText)
      else
          g_window.setTitle("Tibia - " .. name() .. " - DEAD")
      end
    else
      g_window.setTitle("Tibia - " .. name())
    end
  end)
end

addCheckBox("separatePm", "Open PM's in new Window", true, rightPanel, "PM's will be automatically opened in new tab after receiving one.")
if true then
  onTalk(function(name, level, mode, text, channelId, pos)
    if mode == 4 and settings.separatePm then
        local g_console = modules.game_console
        -- Algunos clientes personalizados no exportan getTab/addTab. En ese
        -- caso dejamos que la consola nativa maneje el mensaje privado.
        if not g_console or type(g_console.getTab) ~= "function" or
           type(g_console.addTab) ~= "function" or
           type(g_console.addPrivateText) ~= "function" then
          return
        end
        local privateTab = g_console.getTab(name)
        if privateTab == nil then
            privateTab = g_console.addTab(name, true)
            g_console.addPrivateText(g_console.applyMessagePrefixies(name, level, text), g_console.SpeakTypesSettings['private'], name, false, name)
        end
        return
    end
  end)
end

addCheckBox("antiKick", "Anti - Kick", true, rightPanel, "Turn every 10 minutes to prevent kick.")
if true then
  macro(600*1000, function()
    if not settings.antiKick then return end
    local dir = player:getDirection()
    turn((dir + 1) % 4)
    schedule(50, function() turn(dir) end)
  end)
end

addCheckBox("oberon", "Auto Reply Oberon", true, rightPanel, "Auto reply to Grand Master Oberon talk minigame.")
if true then
  onTalk(function(name, level, mode, text, channelId, pos)
    if not settings.oberon then return end
    if mode == 34 then
        if string.find(text, "world will suffer for") then
            say("Are you ever going to fight or do you prefer talking?")
        elseif string.find(text, "feet when they see me") then
            say("Even before they smell your breath?")
        elseif string.find(text, "from this plane") then
            say("Too bad you barely exist at all!") 
        elseif string.find(text, "ESDO LO") then
            say("SEHWO ASIMO, TOLIDO ESD") 
        elseif string.find(text, "will soon rule this world") then
            say("Excuse me but I still do not get the message!") 
        elseif string.find(text, "honourable and formidable") then
            say("Then why are we fighting alone right now?") 
        elseif string.find(text, "appear like a worm") then
            say("How appropriate, you look like something worms already got the better of!") 
        elseif string.find(text, "will be the end of mortal") then
            say("Then let me show you the concept of mortality before it!") 
        elseif string.find(text, "virtues of chivalry") then
            say("Dare strike up a Minnesang and you will receive your last accolade!") 
        end
    end
  end)
end

addCheckBox("autoOpenDoors", "Auto Open Doors", true, rightPanel, "Open doors when trying to step on them.")
if true then

  local doorsIds = {
     5007, 8265,31570, 1629, 1632, 5129, 6252, 6249, 7715, 7712, 7714,
    7719, 6256, 1669, 1672, 5125, 5115, 5124, 17701, 17710, 1642,
    6260, 5107, 4912, 6251, 5291, 1683, 1696, 1692, 5006, 2179, 5116,
    11705, 30772, 30774, 6248, 5735, 5732, 5120, 23873, 5736,
    6264, 5122, 30049, 30042, 7727, 5293, 9567, 34847, 1764, 21051,
    30823, 5282, 20453, 2772, 27260, 2773, 5281, 1968, 31116, 31120,
    30742, 31115, 31118, 20474, 5733, 31202, 31228, 31199, 31200,
    33262, 30824, 5126, 8257, 8258, 8255, 8256, 30777, 30776,
    23877, 31130, 25803, 16277, 5098, 5104, 5102, 5106, 5109, 5111,
    5113, 5118, 5100, 1638, 1640, 19250, 3500, 3497, 3498, 3499,
    2177, 17709, 23875, 1644, 5131, 28546, 6254, 30364, 30365,
    30367, 30368, 30363, 30366, 31139, 31138, 31136, 31137, 4981,
    4977, 11714, 7771, 9558, 9559, 20475, 2909, 2907, 8618, 31366,
    1646, 1648, 4997, 22506, 8259, 27503, 27505, 27507, 31476, 31477,
     31475, 31474, 8363, 5097, 11237, 11246, 9874, 33634, 33633,
     22632, 22639, 1631, 1628, 20446, 20443, 20444, 2334, 9357, 9355, 1687, 1698}

  Global.doorIds = doorsIds
  Global.useIds = Global.useIds or {}
  for _, doorId in ipairs(doorsIds) do
    local exists = false
    for _, useId in ipairs(Global.useIds) do
      if useId == doorId then
        exists = true
        break
      end
    end
    if not exists then
      table.insert(Global.useIds, doorId)
    end
  end

  function checkForDoors(pos)
    if not pos then return false end
    local tile = g_map.getTile(pos)
    if tile then
      local useThing = tile:getTopUseThing()
      if useThing and table.find(doorsIds, useThing:getId()) then
        local ok = pcall(function() g_game.use(useThing) end)
        return ok
      end
    end
    return false
  end

  onKeyPress(function(keys)
    local wsadWalking = false
    if modules.game_console and modules.game_console.isEnabledWASD then
      wsadWalking = modules.game_console.isEnabledWASD()
    elseif modules.game_walking then
      wsadWalking = modules.game_walking.wsadWalking
    end
    if not settings.autoOpenDoors then return end
    local pos = player:getPosition()
    if not pos then return end
    if keys == 'Up' or (wsadWalking and keys == 'W') then
      pos.y = pos.y - 1
    elseif keys == 'Down' or (wsadWalking and keys == 'S') then
      pos.y = pos.y + 1
    elseif keys == 'Left' or (wsadWalking and keys == 'A') then
      pos.x = pos.x - 1
    elseif keys == 'Right' or (wsadWalking and keys == 'D') then
      pos.x = pos.x + 1
    elseif wsadWalking and keys == "Q" then
      pos.y = pos.y - 1
      pos.x = pos.x - 1
    elseif wsadWalking and keys == "E" then
      pos.y = pos.y - 1
      pos.x = pos.x + 1
    elseif wsadWalking and keys == "Z" then
      pos.y = pos.y + 1
      pos.x = pos.x - 1
    elseif wsadWalking and keys == "C" then
      pos.y = pos.y + 1
      pos.x = pos.x + 1
    end
    checkForDoors(pos)
  end)
end

local blessControl = addCheckBox("bless", "Bless: comprobando...", true, rightPanel,
  "Comprueba las 8 bendiciones del cliente. Compra con !bless si faltan y vuelve a verificar al morir.")
if true then
  local START_DELAY, RESPONSE_DELAY, MAX_ATTEMPTS = 4, 8, 3
  local session, waitingForRevival, destroyed = nil, false, false
  local hooks, blessButton = {}, nil
  local required = {
    {"Twist of Fate", "TwistOfFate", 2},
    {"Wisdom of Solitude", "WisdomOfSolitude", 4},
    {"Spark of the Phoenix", "SparkOfPhoenix", 8},
    {"Fire of the Suns", "FireOfSuns", 16},
    {"Spiritual Shielding", "SpiritualShielding", 32},
    {"Embrace of Tibia", "EmbraceOfTibia", 64},
    {"Heart of the Mountain", "HeartOfMountain", 128},
    {"Blood of the Mountain", "BloodOfMountain", 256}
  }
  local allNames = {}
  for _, entry in ipairs(required) do allNames[#allNames+1] = entry[1] end
  local function callPlayer(character, method)
    local ok, value = pcall(function() return character[method](character) end)
    if ok then return value end
  end
  local function normalized(text)
    return text:lower():gsub("%s+", " "):match("^%s*(.-)%s*$")
  end
  local function fromList(text)
    if type(text) ~= "string" then return end
    local message = normalized(text)
    if message:find("you are currently not protected by any blessing", 1, true) then
      return 0, "cliente: lista", table.concat(allNames, "\n")
    end
    if not message:find("you are protected by the following blessings:", 1, true) then return end
    local present, count, missing = {}, 0, {}
    for line in text:gmatch("[^\r\n]+") do
      present[normalized(line):gsub("^%-%s*", "")] = true
    end
    for _, entry in ipairs(required) do
      if present[entry[1]:lower()] then count = count+1
      else missing[#missing+1] = entry[1] end
    end
    return count, "cliente: lista", table.concat(missing, "\n")
  end
  local function clientBlessings(character)
    -- Mythic sends a separate visual status; getBlessings() can remain zero.
    -- An unknown native state also invalidates the old inventory tooltip after death.
    local known = callPlayer(character, "isBlessStatusKnown")
    if known == false then return nil, "cliente: esperando datos" end
    local mask = tonumber(callPlayer(character, "getBlessings"))
    if mask and mask > 0 and mask == math.floor(mask) then
      local count, missing = 0, {}
      for _, entry in ipairs(required) do
        local flag = Blessings and tonumber(Blessings[entry[2]]) or entry[3]
        if flag and flag > 0 and math.floor(mask/flag)%2 == 1 then count = count+1
        else missing[#missing+1] = entry[1] end
      end
      return count, "cliente: flags", table.concat(missing, "\n")
    end
    local ok, tooltip = pcall(function()
      if not blessButton or blessButton:isDestroyed() then
        blessButton = g_ui.getRootWidget():recursiveGetChildById("blessedButton")
      end
      return blessButton and blessButton:getTooltip()
    end)
    if not ok then blessButton = nil end
    if ok then return fromList(tooltip) end
  end
  local function showStatus(text, color, detail)
    blessControl:setText(text)
    blessControl:setColor(color)
    blessControl:setTooltip("Comprueba las 8 bless y compra con !bless si faltan.\n" .. (detail or ""))
  end
  local function recordBless(stage)
    storage.sabuezoBlessDiagnostic = {
      stage=stage, attempts=session and session.attempts or 0,
      current=session and tonumber(callPlayer(session.character, "getBlessings")) or nil,
      nativeStatus=session and tonumber(callPlayer(session.character, "getBlessStatus")) or nil,
      count=session and session.count or nil, source=session and session.source or nil,
      missing=session and session.missing or nil, reason=session and session.reason or nil,
      time=os.time()
    }
  end
  local function confirm(source)
    if session.confirmed and session.source == source then return end
    session.confirmed, session.finished, session.count, session.source = true, true, 8, source
    session.missing = ""
    recordBless("confirmed")
    showStatus("Bless: 8/8 activas", "#55dd77", "Las 8 confirmadas mediante " .. source .. ".")
  end
  local function sendBless()
    session.attempts, session.sentAt = session.attempts+1, os.time()
    recordBless("sent")
    local ok, err = pcall(function() say("!bless") end)
    if not ok then
      session.finished = true
      recordBless("send_failed")
      showStatus("Bless: error al comprar", "#ff7777", tostring(err))
      warn("Auto bless: !bless no se pudo enviar: " .. tostring(err))
    end
  end
  local function cleanup()
    if destroyed then return end
    destroyed, session = true, nil
    for event, callback in pairs(hooks) do
      local listeners = g_game[event]
      if listeners == callback then g_game[event] = nil
      elseif type(listeners) == "table" then
        for i=#listeners,1,-1 do if listeners[i] == callback then table.remove(listeners,i) end end
        if #listeners == 1 then g_game[event] = listeners[1] end
      end
    end
  end
  local shared = modules and modules.game_bot
  if shared and type(shared.sabuezoBlessCleanup) == "function" then shared.sabuezoBlessCleanup() end
  if shared then shared.sabuezoBlessCleanup = cleanup end
  local function addSignal(event, callback)
    local listeners = g_game[event]
    if listeners == nil then g_game[event] = callback
    elseif type(listeners) == "function" then g_game[event] = {listeners,callback}
    elseif type(listeners) == "table" then table.insert(listeners,callback)
    else return end
    hooks[event] = callback
  end
  local function markDead()
    if waitingForRevival then return end
    local character = g_game.getLocalPlayer()
    if character then callPlayer(character, "invalidateBlessStatus") end
    session, waitingForRevival = nil, true
    if settings.bless then
      recordBless("waiting_for_respawn")
      showStatus("Bless: esperando revivir", "#ffcc55", "Al revivir se comprueban y se reponen las bless.")
    end
  end
  addSignal("onDeath", markDead)
  addSignal("onGameEnd", function() session, blessButton = nil, nil end)
  addSignal("onGameStart", function() session, waitingForRevival, blessButton = nil, false, nil end)
  local originalDestroy = blessControl.onDestroy
  blessControl.onDestroy = function(...)
    cleanup()
    if shared and shared.sabuezoBlessCleanup == cleanup then shared.sabuezoBlessCleanup = nil end
    if type(originalDestroy) == "function" then originalDestroy(...) end
  end
  local function deathState(character)
    if g_game.isDead then
      local ok, value = pcall(function() return g_game.isDead() end)
      if ok and type(value) == "boolean" then return value end
    end
    local hp = tonumber(callPlayer(character, "getHealth"))
    if hp then return hp <= 0 end
    return waitingForRevival
  end
  onTextMessage(function(mode, text)
    if destroyed or not settings.bless or not session or waitingForRevival or type(text) ~= "string" then return end
    local count, source = fromList(text)
    if count == 8 then confirm("lista del servidor"); return end
    if session.attempts == 0 or session.confirmed then return end
    local message = normalized(text)
    -- Only an explicit ALL-blessings reply can substitute for missing client data.
    if message:find("already have all blessings",1,true) or
        message:find("received all blessings",1,true) or
        message:find("bought all blessings",1,true) or
        message:find("purchased all blessings",1,true) then
      local current = clientBlessings(session.character)
      if current == nil then confirm("respuesta del servidor") end
    elseif message:find("bless",1,true) and
        (message:find("not enough",1,true) or message:find("insufficient",1,true)) then
      session.finished = true
      recordBless("insufficient_funds")
      showStatus("Bless: faltan monedas", "#ff7777", session.missing)
      warn("Auto bless: el servidor indicó que faltan monedas.")
    end
  end)
  macro(1000, function()
    if destroyed then return end
    local ok, online = pcall(function() return g_game.isOnline() end)
    local character = ok and online and g_game.getLocalPlayer() or nil
    if not character then
      session, blessButton = nil, nil
      showStatus("Bless: sin conexión", "#aaaaaa")
      return
    end
    if deathState(character) then markDead(); return end
    local reason = waitingForRevival and "respawn" or "login"
    waitingForRevival = false
    if not settings.bless then
      session = nil
      showStatus("Bless: desactivado", "#aaaaaa")
      return
    end
    local characterName = callPlayer(character, "getName") or "current"
    if not session or session.characterName ~= characterName then
      session = {character=character, characterName=characterName, loginAt=os.time(),
        attempts=0, sentAt=0, finished=false, confirmed=false, reason=reason}
      recordBless("waiting_for_client")
      showStatus("Bless: comprobando...", "#ffcc55")
    end
    session.character = character
    local elapsed = os.time()
    if elapsed-session.loginAt < START_DELAY then return end
    -- Keep reading even after success or exhausted attempts: a late packet can confirm,
    -- and losing a blessing must start a new purchase cycle.
    local count, source, missing = clientBlessings(character)
    if count == 8 then confirm(source); return end
    if count ~= nil then
      if session.confirmed then
        session.attempts, session.finished, session.confirmed = 0, false, false
        session.reason, session.loginAt = "blessings_lost", elapsed
      end
      if session.count ~= count or session.missing ~= missing then
        session.count, session.source, session.missing = count, source, missing
        recordBless("missing_blessings")
        showStatus("Bless: " .. count .. "/8", "#ffcc55", "Faltan:\n" .. missing)
      end
    elseif session.confirmed and session.source ~= "cliente: flags" and session.source ~= "cliente: lista" then
      return -- Explicit server confirmation remains valid until death or new client data.
    elseif session.confirmed then
      session.confirmed, session.finished, session.attempts = false, false, 0
      session.count, session.source = nil, source
      showStatus("Bless: comprobando...", "#ffcc55", "Esperando datos actuales del cliente.")
    end
    if session.finished then return end
    if session.attempts == 0 then sendBless(); return end
    if elapsed-session.sentAt < RESPONSE_DELAY then return end
    if session.attempts < MAX_ATTEMPTS then sendBless(); return end
    session.finished = true
    recordBless("unconfirmed")
    showStatus("Bless: sin confirmar", "#ff7777", missing or "El cliente aún no confirmó las 8 bendiciones.")
    warn("Auto bless: no se confirmaron las 8 bless; revisa las que faltan antes de cazar.")
  end)
end

addCheckBox("reUse", "Keep Crosshair", false, rightPanel, "Keep crosshair after using with item")
if true then
  local excluded = {268, 237, 238, 23373, 266, 236, 239, 7643, 23375, 7642, 23374, 5908, 5942} 

  onUseWith(function(pos, itemId, target, subType)
    if settings.reUse and not table.find(excluded, itemId) then
      schedule(50, function()
        item = findItem(itemId)
        if item then
          modules.game_interface.startUseWith(item)
        end
      end)
    end
  end)
end

addCheckBox("checkPlayer", "Check Players", true, rightPanel, "Auto look on players and mark level and vocation on character model")
if true then
  local found
  local lastLookAt = {}
  local lastLookAnyAt = 0
  local LOOK_INTERVAL = 250
  local LOOK_RETRY_INTERVAL = 5000

  local vocationAliases = {
    { code = "MS", aliases = { "master sorcerer", "hell wizard", "sorcerer", "wizard" } },
    { code = "RP", aliases = { "royal paladin", "force archer", "paladin", "guardian" } },
    { code = "ED", aliases = { "elder druid", "high saintes", "high saintess", "druid", "prophet", "saintes", "saintess" } },
    { code = "EK", aliases = { "elite knight", "titan blader", "knight", "champion", "blader" } },
    { code = "MK", aliases = { "exalted monk", "monk" } }
  }

  local function trim(value)
    value = tostring(value or "")
    return value:match("^%s*(.-)%s*$") or value
  end

  local function detectVocation(text)
    text = tostring(text or ""):lower():gsub("%s+", " ")
    -- Read the vocation sentence, not vocation words in the name or guild.
    text = text:match("%f[%a]you are (.-)%.") or
           text:match("%f[%a]he is (.-)%.") or
           text:match("%f[%a]she is (.-)%.") or ""

    for _, vocation in ipairs(vocationAliases) do
      for _, alias in ipairs(vocation.aliases) do
        if text:find(alias, 1, true) then
          return vocation.code
        end
      end
    end

    return ""
  end

  local function getCreatureKey(creature)
    if not creature then return nil end
    local ok, name = pcall(function() return creature:getName() end)
    if ok and name then
      return tostring(name):lower()
    end
    return nil
  end

  local function requestPlayerLook(creature)
    if not creature or creature == player then return false end
    if not creature:isPlayer() or creature:getPosition().z ~= posz() then return false end
    local currentText = creature:getText()
    -- Recheck old Check Players labels that have a level but no vocation tag.
    if currentText ~= "" and not currentText:match("^\n%d+\n") then return false end

    local key = getCreatureKey(creature)
    if not key then return false end
    if lastLookAt[key] and now - lastLookAt[key] < LOOK_RETRY_INTERVAL then return false end
    if now - lastLookAnyAt < LOOK_INTERVAL then return false end

    g_game.look(creature)
    found = now
    lastLookAt[key] = now
    lastLookAnyAt = now
    return true
  end

  local function checkPlayers()
    for i, spec in ipairs(getSpectators()) do
      if requestPlayerLook(spec) then
        return true
      end
    end
    return false
  end
  if settings.checkPlayer then 
    schedule(500, function()
      checkPlayers()
    end)
  end

  macro(500, function()
    if settings.checkPlayer then
      checkPlayers()
    end
  end)

  onPlayerPositionChange(function(x,y)
    if not settings.checkPlayer then return end
    if x.z ~= y.z then
      schedule(20, function() checkPlayers() end)
    end
  end)

  onCreatureAppear(function(creature)
    if not settings.checkPlayer then return end
    requestPlayerLook(creature)
  end)

  local regex = [[You see ([^\(]*) \(Level ([0-9]*)\)((?:.)* of the ([\w ]*),|)]]
  onTextMessage(function(mode, text)
    if not settings.checkPlayer then return end

    local re = regexMatch(text, regex)
    if #re ~= 0 then
        local name = trim(re[1][2])
        local level = trim(re[1][3])
        local guild = trim(re[1][5] or "")

        if guild:len() > 10 then
          guild = guild:sub(1,10) -- change to proper (last) values
          guild = guild.."..."
        end
        local voc = ""
        local vocationCode = detectVocation(text)
        if vocationCode ~= "" then
            voc = ": " .. vocationCode
            if PlayerList and type(PlayerList.setVocation) == "function" then
                pcall(PlayerList.setVocation, name, vocationCode)
            end
        end
        local creature = getCreatureByName(name)
        if creature then
            creature:setText("\n"..level..voc.."\n"..guild)
        end
        if found and now - found < 500 then
          modules.game_textmessage.clearMessages()
        end
    end
  end)
end

addCheckBox("highlightTarget", "Highlight Current Target", true, rightPanel, "Additionaly hightlight current target with red glow")
if true then
  local function forceMarked(creature)
    if target() == creature then
        creature:setMarked("red")
        return schedule(333, function() forceMarked(creature) end)
    end
  end

  onAttackingCreatureChange(function(newCreature, oldCreature)
    if not settings.highlightTarget then return end
      if oldCreature then
          oldCreature:setMarked('')
      end
      if newCreature then
          forceMarked(newCreature)
      end
  end)
end
