--[[
  Player List + vocation tags.

  Vocation can be set manually from the list context menu, imported by other
  scripts, or detected from BotServer / visible guild members when available.
]]

local link = "https://www.gunzodus.net/character/show/"
local spacing = "_"

setDefaultTab("Tools")
UI.Separator()

UI.Button("Zoom In map", function() zoomIn() end)
UI.Button("Zoom Out map", function() zoomOut() end)

UI.Separator()

local tabs = {"Friends", "Enemies", "BlackList"}
local panelName = "playerList"
local colors = {"#03C04A", "#fc4c4e", "orange"}
local defaultGuildName = ""

if not storage[panelName] then
  storage[panelName] = {
    enemyList = {},
    friendList = {},
    blackList = {},
    vocations = {},
    groupMembers = true,
    autoGuildMembers = true,
    guildMembers = {},
    guildName = defaultGuildName,
    autoDetectGuild = true,
    outfits = false,
    marks = false,
    highlight = false
  }
end

local config = storage[panelName]
config.enemyList = config.enemyList or {}
config.friendList = config.friendList or {}
config.blackList = config.blackList or {}
config.vocations = config.vocations or {}
config.guildMembers = config.guildMembers or {}
config.manualFriendList = config.manualFriendList or {}
config.guildName = config.guildName or defaultGuildName
if config.autoDetectGuild == nil then config.autoDetectGuild = true end
if config.groupMembers == nil then config.groupMembers = true end
if config.autoGuildMembers == nil then config.autoGuildMembers = true end

local playerTables = {config.friendList, config.enemyList, config.blackList}
local friendListWidget
local ListWindow
local playerLabels = {}

local vocInfo = {
  knight = {label = "EK", color = "#e8b15b", outfit = 131},
  paladin = {label = "RP", color = "#b8e85b", outfit = 129},
  sorcerer = {label = "MS", color = "#ff6b6b", outfit = 130},
  druid = {label = "ED", color = "#65d6ff", outfit = 144}
}

local function trim(text)
  return tostring(text or ""):gsub("^%s*(.-)%s*$", "%1")
end

local function normalizeName(name)
  return trim(name):lower()
end

local function cleanGuildName(name)
  name = trim(name)
  while name:find("%s*%b()%s*$") do
    local cleaned = trim(name:gsub("%s*%b()%s*$", ""))
    if cleaned == name then break end
    name = cleaned
  end
  return name
end

config.guildName = cleanGuildName(config.guildName or defaultGuildName)

local vocationAliases = {
  knight = { "ek", "knight", "elite knight", "titan blader", "guardian" },
  paladin = { "rp", "paladin", "royal paladin", "force archer", "champion" },
  sorcerer = { "ms", "sorc", "sorcerer", "master sorcerer", "hell wizard", "mage", "wizard" },
  druid = { "ed", "druid", "elder druid", "high saintes", "high saintess", "saintes", "saintess", "prophet" }
}

local function cleanVocationName(value)
  local voc = normalizeName(value)
  voc = voc:gsub("%b[]", " "):gsub("%b()", " "):gsub("[{}]", " ")
  voc = trim(voc:gsub("%s+", " "))

  while voc:find("^supreme%s+") do
    voc = trim(voc:gsub("^supreme%s+", ""))
  end

  return voc
end

local function vocationMatches(voc, aliases)
  for _, alias in ipairs(aliases) do
    if voc == alias then return true end
  end
  return false
end

local function normalizeVocation(value)
  if type(value) == "number" then
    if value == 1 or value == 11 then return "knight" end
    if value == 2 or value == 12 then return "paladin" end
    if value == 3 or value == 13 then return "sorcerer" end
    if value == 4 or value == 14 then return "druid" end
    return nil
  end

  local voc = cleanVocationName(value)
  if vocationMatches(voc, vocationAliases.knight) then return "knight" end
  if vocationMatches(voc, vocationAliases.paladin) then return "paladin" end
  if vocationMatches(voc, vocationAliases.sorcerer) then return "sorcerer" end
  if vocationMatches(voc, vocationAliases.druid) then return "druid" end
  return nil
end

local function clearCachedPlayers()
  CachedFriends = {}
  CachedEnemies = {}
end

local function getStoredVocation(name)
  local key = normalizeName(name)
  return normalizeVocation(config.vocations[key] or config.vocations[name])
end

local function getBotServerVocation(name)
  if not vBot or not vBot.BotServerMembers then return nil end
  local voc = normalizeVocation(vBot.BotServerMembers[name])
  if voc then return voc end

  local key = normalizeName(name)
  for memberName, memberVoc in pairs(vBot.BotServerMembers) do
    if normalizeName(memberName) == key then
      return normalizeVocation(memberVoc)
    end
  end
end

local function getPlayerVocation(name)
  return getStoredVocation(name) or getBotServerVocation(name)
end

local function getVocationLabel(name)
  local voc = getPlayerVocation(name)
  return voc and vocInfo[voc] and vocInfo[voc].label or nil
end

local function refreshPlayerLabels(name)
  local labels = playerLabels[normalizeName(name)] or {}
  for _, label in ipairs(labels) do
    if label then
      local playerName = label.playerName or name
      local tag = getVocationLabel(playerName)
      pcall(function()
        label:setText(tag and ("[" .. tag .. "] " .. playerName) or playerName)
        label:setTooltip(tag and ("Vocation: " .. tag) or "Vocation: not set")
      end)
    end
  end
end

local function refreshAllPlayerLabels()
  for nameKey in pairs(playerLabels) do
    refreshPlayerLabels(nameKey)
  end
end

local function setPlayerVocation(name, vocation)
  name = trim(name)
  if name == "" then return end

  local key = normalizeName(name)
  local voc = normalizeVocation(vocation)
  if voc then
    if config.vocations[key] == voc then return voc end
    config.vocations[key] = voc
  else
    if config.vocations[key] == nil then return nil end
    config.vocations[key] = nil
  end
  refreshPlayerLabels(name)
  return voc
end

local function unregisterPlayerLabel(name, label)
  local labels = playerLabels[normalizeName(name)]
  if not labels then return end
  for i = #labels, 1, -1 do
    if labels[i] == label then
      table.remove(labels, i)
    end
  end
end

local function detectCreatureVocation(creature)
  if not creature or not creature:isPlayer() then return nil end
  local name = creature:getName()
  local voc = getPlayerVocation(name)
  if voc then return voc end

  local ok, value = pcall(function() return creature:getVocation() end)
  voc = ok and normalizeVocation(value)
  if voc then return voc end
end

local function isGuildMember(creature)
  if not creature or not creature:isPlayer() or creature:isLocalPlayer() then return false end
  local ok, emblem = pcall(function() return creature:getEmblem() end)
  return ok and emblem == 1
end

local function findPlayerIndex(playerList, name)
  local key = normalizeName(name)
  for i, playerName in ipairs(playerList or {}) do
    if normalizeName(playerName) == key then
      return i
    end
  end
end

local function addUniquePlayer(playerList, name)
  if findPlayerIndex(playerList, name) then return false end
  table.insert(playerList, name)
  clearCachedPlayers()
  return true
end

local function isManualFriend(name)
  return findPlayerIndex(config.manualFriendList, name) ~= nil
end

local function addManualFriend(name)
  if findPlayerIndex(config.manualFriendList, name) then return false end
  table.insert(config.manualFriendList, name)
  return true
end

local function removeManualFriend(name)
  local index = findPlayerIndex(config.manualFriendList, name)
  if index then table.remove(config.manualFriendList, index) end
end

if not config.manualFriendListInitialized then
  for _, name in ipairs(config.friendList) do
    local key = normalizeName(name)
    if not config.guildMembers[key] then
      addManualFriend(name)
    end
  end
  config.manualFriendListInitialized = true
else
  for _, name in ipairs(config.manualFriendList) do
    addUniquePlayer(config.friendList, name)
  end
end

local function createPlayerLabel(list, playerList, name)
  local label = UI.createWidget("PlayerLabel", list)
  label.playerName = name
  local key = normalizeName(name)
  playerLabels[key] = playerLabels[key] or {}
  table.insert(playerLabels[key], label)
  refreshPlayerLabels(name)

  label.remove.onClick = function()
    local index = findPlayerIndex(playerList, name)
    if index then table.remove(playerList, index) end
    if playerList == config.friendList then
      removeManualFriend(name)
    end
    unregisterPlayerLabel(name, label)
    label:destroy()
    clearCachedPlayers()
    refreshStatus()
  end

  label.onMouseRelease = function(widget, mousePos, mouseButton)
    if mouseButton ~= 2 then return false end
    local child = g_ui.getRootWidget():recursiveGetChildByPos(mousePos)
    if child ~= widget then return false end

    local playerName = widget.playerName or widget:getText()
    local menu = g_ui.createWidget("PopupMenu")
    menu:setId("playerListMenu")
    menu:setGameMenu(true)
    menu:addOption("Set EK", function() setPlayerVocation(playerName, "knight") end, "")
    menu:addOption("Set RP", function() setPlayerVocation(playerName, "paladin") end, "")
    menu:addOption("Set MS", function() setPlayerVocation(playerName, "sorcerer") end, "")
    menu:addOption("Set ED/Druid", function() setPlayerVocation(playerName, "druid") end, "")
    menu:addOption("Clear Vocation", function() setPlayerVocation(playerName, nil) end, "")
    menu:addOption("Check Player", function()
      g_platform.openUrl(link .. playerName:gsub(" ", spacing))
    end, "")
    menu:addOption("Copy Name", function()
      g_window.setClipboardText(playerName)
    end, "")
    menu:display(mousePos)
    return true
  end

  return label
end

local function addFriendLabelIfVisible(name)
  if friendListWidget then
    createPlayerLabel(friendListWidget, config.friendList, name)
  end
end

local function removeFriendLabels(name)
  local key = normalizeName(name)
  local labels = playerLabels[key]
  if not labels then return end

  for i = #labels, 1, -1 do
    local label = labels[i]
    local isFriendLabel = false
    pcall(function()
      isFriendLabel = label and label:getParent() == friendListWidget
    end)

    if isFriendLabel then
      table.remove(labels, i)
      pcall(function() label:destroy() end)
    end
  end

  if #labels == 0 then
    playerLabels[key] = nil
  end
end

local function removeAutoGuildMembers()
  for i = #config.friendList, 1, -1 do
    local name = config.friendList[i]
    local key = normalizeName(name)
    if config.guildMembers[key] and not isManualFriend(name) then
      table.remove(config.friendList, i)
      config.vocations[key] = nil
      removeFriendLabels(name)
    end
  end

  config.guildMembers = {}
  clearCachedPlayers()
  refreshAllPlayerLabels()
end

local function updateGuildName(name)
  local newName = cleanGuildName(name)
  local oldKey = normalizeName(config.guildName or "")
  local newKey = normalizeName(newName)
  config.guildName = newName

  if ListWindow and ListWindow.settings and ListWindow.settings.GuildName then
    pcall(function()
      if ListWindow.settings.GuildName:getText() ~= newName then
        ListWindow.settings.GuildName:setText(newName)
      end
    end)
  end

  if oldKey ~= newKey then
    removeAutoGuildMembers()
    refreshStatus()
  end
end

local function guildNameMatches(name)
  local wanted = normalizeName(config.guildName or "")
  return wanted ~= "" and normalizeName(cleanGuildName(name)) == wanted
end

local function addGuildFriend(name, vocation)
  if not config.autoGuildMembers then return false end
  name = trim(name)
  if name == "" then return false end

  local voc = normalizeVocation(vocation)
  if voc then setPlayerVocation(name, voc) end

  config.guildMembers[normalizeName(name)] = true
  if addUniquePlayer(config.friendList, name) then
    addFriendLabelIfVisible(name)
    return true
  end
  return false
end

local function autoAddGuildMember(creature)
  if not config.autoGuildMembers then return end
  if not isGuildMember(creature) then return end

  local name = creature:getName()
  local voc = detectCreatureVocation(creature)

  addGuildFriend(name, voc)
end

local function applyStatus(creature)
  if not creature:isPlayer() or creature:isLocalPlayer() then return end
  autoAddGuildMember(creature)

  local creatureName = creature:getName()
  local outfit = creature:getOutfit()

  if isFriend(creatureName) then
    if config.highlight then
      creature:setMarked("#0000FF")
    end
    if config.outfits then
      outfit.head = 88
      outfit.body = 88
      outfit.legs = 88
      outfit.feet = 88

      local voc = getPlayerVocation(creatureName)
      if storage.BOTserver and storage.BOTserver.outfit and voc and vocInfo[voc] then
        outfit.addons = 3
        outfit.type = vocInfo[voc].outfit
      end
      creature:setOutfit(outfit)
    end
  elseif isEnemy(creatureName) then
    if config.highlight then
      creature:setMarked("#FF0000")
    end
    if config.outfits then
      outfit.head = 94
      outfit.body = 94
      outfit.legs = 94
      outfit.feet = 94
      creature:setOutfit(outfit)
    end
  end
end

function refreshStatus()
  for _, spec in ipairs(getSpectators()) do
    applyStatus(spec)
  end
end

local function parsePlayerEntry(text)
  local name, voc = text:match("^(.-)%s*[:%-]%s*(%a+)%s*$")
  if name and normalizeVocation(voc) then
    return trim(name), normalizeVocation(voc)
  end
  return trim(text), nil
end

local function getLocalPlayerName()
  local localPlayer
  if g_game and g_game.getLocalPlayer then
    local ok, result = pcall(function() return g_game.getLocalPlayer() end)
    if ok then localPlayer = result end
  end
  if not localPlayer and player then localPlayer = player end
  if not localPlayer then return nil end

  local ok, name = pcall(function() return localPlayer:getName() end)
  return ok and name or nil
end

local function parseLookText(text)
  text = tostring(text or ""):gsub("\n", " ")
  if not text:find("You see") then return nil end

  local isSelf = text:find("You see yourself", 1, true) ~= nil
  local name
  if isSelf then
    name = getLocalPlayerName()
  else
    name = text:match("You see ([^%(%.]+)%s*%(") or text:match("You see ([^%.]+)%.")
  end

  name = trim(name)
  if name == "" then return nil end

  local voc = text:match("[Yy]ou are an ([^%.]+)%.") or
              text:match("[Yy]ou are a ([^%.]+)%.") or
              text:match("[Hh]e is an ([^%.]+)%.") or
              text:match("[Hh]e is a ([^%.]+)%.") or
              text:match("[Ss]he is an ([^%.]+)%.") or
              text:match("[Ss]he is a ([^%.]+)%.")
  local guild = text:match("[Mm]ember of the ([^%.]+)%.") or
                text:match("[Mm]ember of ([^%.]+)%.")

  return name, normalizeVocation(voc), cleanGuildName(guild), isSelf
end

local function handleLookText(text)
  local name, voc, guild, isSelf = parseLookText(text)
  if not name or guild == "" then return false end

  if isSelf then
    if config.autoDetectGuild then
      updateGuildName(guild)
    end
    if voc then setPlayerVocation(name, voc) end
    return true
  end

  if guildNameMatches(guild) then
    addGuildFriend(name, voc)
    return true
  end
  return false
end

local function importGuildVocations(parsed)
  local imported, added, removed = 0, 0, 0
  local previousGuildMembers = config.guildMembers or {}
  local currentGuildMembers = {}

  for name in pairs(parsed or {}) do
    currentGuildMembers[normalizeName(name)] = true
  end

  for i = #config.friendList, 1, -1 do
    local name = config.friendList[i]
    local key = normalizeName(name)
    if previousGuildMembers[key] and not currentGuildMembers[key] and not isManualFriend(name) then
      table.remove(config.friendList, i)
      config.vocations[key] = nil
      removeFriendLabels(name)
      removed = removed + 1
    end
  end

  for name, voc in pairs(parsed or {}) do
    setPlayerVocation(name, voc)
    imported = imported + 1
    if addUniquePlayer(config.friendList, name) then
      added = added + 1
      addFriendLabelIfVisible(name)
    end
  end

  config.guildMembers = currentGuildMembers

  clearCachedPlayers()
  refreshAllPlayerLabels()
  refreshStatus()
  return imported, added, removed
end

local function syncGuildVocations()
  return 0, 0, 0
end

PlayerList = PlayerList or {}
PlayerList.getVocation = getPlayerVocation
PlayerList.setVocation = setPlayerVocation
PlayerList.normalizeVocation = normalizeVocation
PlayerList.getVocationLabel = getVocationLabel
PlayerList.refreshStatus = refreshStatus
PlayerList.syncGuildVocations = syncGuildVocations
PlayerList.getGuildName = function() return config.guildName end
PlayerList.setGuildName = updateGuildName
PlayerList.handleLookText = handleLookText
PlayerList.isFriend = function(name)
  if type(name) ~= "string" and name then
    local ok, creatureName = pcall(function() return name:getName() end)
    if ok then name = creatureName end
  end
  return findPlayerIndex(config.friendList, name) ~= nil
end
PlayerList.isManualFriend = isManualFriend
PlayerList.isGuildMember = function(name)
  if type(name) ~= "string" and name then
    local ok, creatureName = pcall(function() return name:getName() end)
    if ok then name = creatureName end
  end
  return config.guildMembers[normalizeName(name)] == true
end
PlayerList.importVocations = function(vocationLists)
  if type(vocationLists) ~= "table" then return end
  for voc, list in pairs(vocationLists) do
    local normalizedVoc = normalizeVocation(voc)
    if normalizedVoc and type(list) == "table" then
      for _, playerName in ipairs(list) do
        if playerName and playerName ~= "" then
          config.vocations[normalizeName(playerName)] = normalizedVoc
        end
      end
    end
  end
  refreshAllPlayerLabels()
end

PlayerList.autoAddVisibleGuildMembers = function()
  for _, spec in ipairs(getSpectators()) do
    autoAddGuildMember(spec)
  end
end

refreshStatus()

local rootWidget = g_ui.getRootWidget()
if rootWidget then
  local oldWindow = rootWidget:recursiveGetChildById("PlayerListWindow")
  if oldWindow then oldWindow:destroy() end

  ListWindow = UI.createWindow("PlayerListWindow", rootWidget)
  ListWindow:hide()

  UI.Button("Player Lists", function()
    ListWindow:show()
    ListWindow:raise()
    ListWindow:focus()
  end)

  ListWindow.settings.Members:setChecked(config.groupMembers)
  ListWindow.settings.Members.onClick = function(widget)
    config.groupMembers = not config.groupMembers
    if not config.groupMembers then
      clearCachedPlayers()
    end
    refreshStatus()
    widget:setChecked(config.groupMembers)
  end

  ListWindow.settings.AutoGuildVoc:setChecked(config.autoGuildMembers)
  ListWindow.settings.AutoGuildVoc.onClick = function(widget)
    config.autoGuildMembers = not config.autoGuildMembers
    widget:setChecked(config.autoGuildMembers)
    PlayerList.autoAddVisibleGuildMembers()
    refreshStatus()
  end

  ListWindow.settings.Outfit:setChecked(config.outfits)
  ListWindow.settings.Outfit.onClick = function(widget)
    config.outfits = not config.outfits
    widget:setChecked(config.outfits)
    refreshStatus()
  end

  ListWindow.settings.NeutralsAreEnemy:setChecked(config.marks)
  ListWindow.settings.NeutralsAreEnemy.onClick = function(widget)
    config.marks = not config.marks
    widget:setChecked(config.marks)
  end

  ListWindow.settings.Highlight:setChecked(config.highlight)
  ListWindow.settings.Highlight.onClick = function(widget)
    config.highlight = not config.highlight
    widget:setChecked(config.highlight)
  end

  ListWindow.settings.AutoAdd:setChecked(config.autoAdd)
  ListWindow.settings.AutoAdd.onClick = function(widget)
    config.autoAdd = not config.autoAdd
    widget:setChecked(config.autoAdd)
  end

  ListWindow.settings.AutoDetectGuild:setChecked(config.autoDetectGuild)
  ListWindow.settings.AutoDetectGuild.onClick = function(widget)
    config.autoDetectGuild = not config.autoDetectGuild
    widget:setChecked(config.autoDetectGuild)
  end

  ListWindow.settings.GuildName:setText(config.guildName or "")
  ListWindow.settings.GuildName.onTextChange = function(widget, text)
    updateGuildName(text)
  end

  ListWindow.settings.ClearGuild.onClick = function()
    updateGuildName("")
  end

  local TabBar = ListWindow.tmpTabBar
  TabBar:setContentWidget(ListWindow.tmpTabContent)
  local blacklistList

  for v = 1, 3 do
    local listPanel = g_ui.createWidget("tPanel")
    local playerList = playerTables[v]
    listPanel:setId(tabs[v] .. "Tab")
    TabBar:addTab(tabs[v], listPanel)

    local addButton = listPanel.add
    local nameTab = listPanel.name
    local list = listPanel.list
    if v == 1 then friendListWidget = list end
    if v == 3 then blacklistList = list end

    for _, name in ipairs(playerList) do
      createPlayerLabel(list, playerList, name)
    end

    local tabButton = TabBar.buttonsPanel:getChildren()[v]
    tabButton.onStyleApply = function(widget)
      if TabBar:getCurrentTab() == widget then
        widget:setColor(colors[v])
      end
    end

    addButton.onClick = function()
      local names = string.split(nameTab:getText(), ",")
      if #names == 0 then
        warn("vBot[PlayerList]: Name is missing!")
        return
      end

      for i = 1, #names do
        local name, voc = parsePlayerEntry(names[i])
        if name:len() == 0 then
          warn("vBot[PlayerList]: Name is missing!")
        elseif not findPlayerIndex(playerList, name) then
          table.insert(playerList, name)
          if v == 1 then addManualFriend(name) end
          if voc then setPlayerVocation(name, voc) end
          createPlayerLabel(list, playerList, name)
          nameTab:setText("")
        else
          if v == 1 then addManualFriend(name) end
          warn("vBot[PlayerList]: Player " .. name .. " is already added!")
          nameTab:setText("")
        end
        clearCachedPlayers()
        refreshStatus()
      end
    end

    nameTab.onKeyPress = function(widget, keyCode, keyboardModifiers)
      if keyCode ~= 5 then
        return false
      end
      addButton.onClick()
      return true
    end
  end

  function addBlackListPlayer(name)
    if findPlayerIndex(config.blackList, name) then return end
    table.insert(config.blackList, name)
    if blacklistList then
      createPlayerLabel(blacklistList, config.blackList, name)
    end
    clearCachedPlayers()
  end

  PlayerList.autoAddVisibleGuildMembers()
end

onTextMessage(function(mode, text)
  handleLookText(text)
  if not config.autoAdd then return end
  if CaveBot.isOff() or TargetBot.isOff() then return end
  if not text:find("Warning! The murder of") then return end

  local killedName = text:match("Warning! The murder of (.-) was not justified")
  if killedName and addBlackListPlayer then
    addBlackListPlayer(trim(killedName))
  end
end)

onCreatureAppear(function(creature)
  applyStatus(creature)
end)

onPlayerPositionChange(function(x, y)
  if x.z ~= y.z then
    schedule(20, function()
      refreshStatus()
    end)
  end
end)

macro(1000, function()
  if config.autoGuildMembers then
    PlayerList.autoAddVisibleGuildMembers()
  else
    for name, voc in pairs(vBot.BotServerMembers or {}) do
      local normalizedVoc = normalizeVocation(voc)
      if normalizedVoc and getStoredVocation(name) ~= normalizedVoc then
        setPlayerVocation(name, normalizedVoc)
      end
    end
  end
end)
