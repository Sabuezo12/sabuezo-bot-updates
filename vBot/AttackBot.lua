-- setDefaultTab(storage.extras.joinBot and "Cave" or "Target")
setDefaultTab("Target")
-- UI.Separator()
--locales
local panelName = "AttackBot"
local currentSettings
-- One-way activation: committed spell positioning enables Target's normal
-- alignment. Turning positioning off never undoes a user's Target preference.
local function syncTargetFacing()
  if currentSettings and currentSettings.Rotate == true and TargetBot and
    type(TargetBot.enableFaceMonsters) == 'function' then
    return TargetBot.enableFaceMonsters()
  end
  return 0
end
local showSettings = false
local showItem = false
local category = 1
local patternCategory = 1
local pattern = 1
local mainWindow
local catalog = AttackSpellCatalog
local catalogEditFields
local catalogAttempts, catalogSecondary = {}, {}
local grenadeHistory, grenadeScene = {}, nil
local empowermentReadyAt, attackGroupReadyAt = 0, 0

-- label library

local categories = {
  "Targeted Spell (exori hur, exori flam, etc)",
  "Area Rune (avalanche, great fireball, etc)",
  "Targeted Rune (sudden death, icycle, etc)",
  "Empowerment (utito tempo, etc)",
  "Absolute Spell (exori, hells core, etc)",
  "Modern Spell (target area, chain, monk)",
}

local function categoryPattern(value)
  return value == 4 and 3 or value == 5 and 4 or value == 6 and 5 or value
end

local patterns = {
  -- targeted spells
  {
    "1 Sqm Range (exori ico)",
    "2 Sqm Range",
    "3 Sqm Range (strike spells)",
    "4 Sqm Range (exori san)",
    "5 Sqm Range (exori hur)",
    "6 Sqm Range",
    "7 Sqm Range (exori con)",
    "8 Sqm Range",
    "9 Sqm Range",
    "10 Sqm Range"
  },
  -- area runes
  {
    "Cross (explosion)",
    "Bomb (fire bomb)",
    "Ball (gfb, avalanche)"
  },
  -- empowerment/targeted rune
  {
    "1 Sqm Range",
    "2 Sqm Range",
    "3 Sqm Range",
    "4 Sqm Range",
    "5 Sqm Range",
    "6 Sqm Range",
    "7 Sqm Range",
    "8 Sqm Range",
    "9 Sqm Range",
    "10 Sqm Range",
  },
  -- absolute
  {
    "Adjacent (exori, exori gran)",
    "3x3 Wave (vis hur, tera hur)", 
    "Small Area (mas san, exori mas)",
    "Medium Area (mas flam, mas frigo)",
    "Large Area (mas vis, mas tera)",
    "Short Beam (vis lux)", 
    "Large Beam (gran vis lux)", 
    "Sweep (exori min)", -- 8
    "Small Wave (gran frigo hur)",
    "Big Wave (flam hur, frigo hur)",
    "Huge Wave (gran flam hur)",
  }
}

patterns[5] = catalog.patternNames

  -- spellPatterns[category][pattern][1 - normal, 2 - safe]
local spellPatterns = {
  {}, -- blank, wont be used
  -- Area Runes,
  { 
    {     -- cross
     [[ 
      010
      111
      010
     ]],
     -- cross SAFE
     [[
       01110
       01110
       11111
       11111
       11111
       01110
       01110
     ]]
    },
    { -- bomb
      [[
        111
        111
        111
      ]],
      -- bomb SAFE
      [[
        11111
        11111
        11111
        11111
        11111
      ]]
    },
    { -- ball
      [[
        0011100
        0111110
        1111111
        1111111
        1111111
        0111110
        0011100
      ]],
      -- ball SAFE
      [[
        000111000
        001111100
        011111110
        111111111
        111111111
        111111111
        011111110
        001111100
        000111000
      ]]
    },
  },
  {}, -- blank, wont be used
  -- Absolute
  {
    {-- adjacent
      [[
        111
        111
        111
      ]],
      -- adjacent SAFE
      [[
        11111
        11111
        11111
        11111
        11111
      ]]
    },
    { -- 3x3 Wave
      [[
        0000NNN0000
        0000NNN0000
        0000NNN0000
        00000N00000
        WWW00N00EEE
        WWWWW0EEEEE
        WWW00S00EEE
        00000S00000
        0000SSS0000
        0000SSS0000
        0000SSS0000
      ]],
      -- 3x3 Wave SAFE
      [[
        0000NNNNN0000
        0000NNNNN0000
        0000NNNNN0000
        0000NNNNN0000
        WWWW0NNN0EEEE
        WWWWWNNNEEEEE
        WWWWWW0EEEEEE
        WWWWWSSSEEEEE
        WWWW0SSS0EEEE
        0000SSSSS0000
        0000SSSSS0000
        0000SSSSS0000
        0000SSSSS0000
      ]]
    },
    { -- small area
      [[
        0011100
        0111110
        1111111
        1111111
        1111111
        0111110
        0011100
      ]],
      -- small area SAFE
      [[
        000111000
        001111100
        011111110
        111111111
        111111111
        111111111
        011111110
        001111100
        000111000
      ]]
    },
    { -- medium area
      [[
        00000100000
        00011111000
        00111111100
        01111111110
        01111111110
        11111111111
        01111111110
        01111111110
        00111111100
        00001110000
        00000100000
      ]],
      -- medium area SAFE
      [[
        0000011100000
        0000111110000
        0001111111000
        0011111111100
        0111111111110
        0111111111110
        1111111111111
        0111111111110
        0111111111110
        0011111111100
        0001111111000
        0000111110000
        0000011100000
      ]]
    },
    { -- large area
      [[
        0000001000000
        0000011100000
        0000111110000
        0001111111000
        0011111111100
        0111111111110
        1111111111111
        0111111111110
        0011111111100
        0001111111000
        0000111110000
        0000011100000
        0000001000000
      ]],
      -- large area SAFE
      [[
        000000010000000
        000000111000000
        000001111100000
        000011111110000
        000111111111000
        001111111111100
        011111111111110
        111111111111111
        011111111111110
        001111111111100
        000111111111000
        000011111110000
        000001111100000
        000000111000000
        000000010000000
      ]]
    },
    { -- short beam
      [[
        00000N00000
        00000N00000
        00000N00000
        00000N00000
        00000N00000
        WWWWW0EEEEE
        00000S00000
        00000S00000
        00000S00000
        00000S00000
        00000S00000
      ]],
      -- short beam SAFE
      [[
        00000NNN00000
        00000NNN00000
        00000NNN00000
        00000NNN00000
        00000NNN00000
        WWWWWNNNEEEEE
        WWWWWW0EEEEEE
        00000SSS00000
        00000SSS00000
        00000SSS00000
        00000SSS00000
        00000SSS00000
        00000SSS00000
      ]]
    },
    { -- large beam
      [[
        0000000N0000000
        0000000N0000000
        0000000N0000000
        0000000N0000000
        0000000N0000000
        0000000N0000000
        0000000N0000000
        WWWWWWW0EEEEEEE
        0000000S0000000
        0000000S0000000
        0000000S0000000
        0000000S0000000
        0000000S0000000
        0000000S0000000
        0000000S0000000
      ]],
      -- large beam SAFE
      [[
        0000000NNN0000000
        0000000NNN0000000
        0000000NNN0000000
        0000000NNN0000000
        0000000NNN0000000
        0000000NNN0000000
        0000000NNN0000000
        WWWWWWWNNNEEEEEEE
        WWWWWWWW0EEEEEEEE
        WWWWWWWSSSEEEEEEE
        0000000SSS0000000
        0000000SSS0000000
        0000000SSS0000000
        0000000SSS0000000
        0000000SSS0000000
        0000000SSS0000000
        0000000SSS0000000
      ]],
    },
    {}, -- sweep, wont be used
    { -- small wave
      [[
        00NNN00
        00NNN00
        WW0N0EE
        WWW0EEE
        WW0S0EE
        00SSS00
        00SSS00
      ]],
      -- small wave SAFE
      [[
        00NNNNN00
        00NNNNN00
        WWNNNNNEE
        WWWWNEEEE
        WWWW0EEEE
        WWWWSEEEE
        WWSSSSSEE
        00SSSSS00
        00SSSSS00
      ]]
    },
    { -- large wave
      [[
        000NNNNN000
        000NNNNN000
        0000NNN0000
        WW00NNN00EE
        WWWW0N0EEEE
        WWWWW0EEEEE
        WWWW0S0EEEE
        WW00SSS00EE
        0000SSS0000
        000SSSSS000
        000SSSSS000
      ]],
      [[
        000NNNNNNN000
        000NNNNNNN000
        000NNNNNNN000
        WWWWNNNNNEEEE
        WWWWNNNNNEEEE
        WWWWWNNNEEEEE
        WWWWWW0EEEEEE
        WWWWWSSSEEEEE
        WWWWSSSSSEEEE
        WWWWSSSSSEEEE
        000SSSSSSS000
        000SSSSSSS000
        000SSSSSSS000
      ]]
    },
    { -- huge wave
      [[
        0000NNNNN0000
        0000NNNNN0000
        00000NNN00000
        00000NNN00000
        WW0000N0000EE
        WWWW00N00EEEE
        WWWWWW0EEEEEE
        WWWW00S00EEEE
        WW0000S0000EE
        00000SSS00000
        00000SSS00000
        0000SSSSS0000
        0000SSSSS0000
      ]],
      [[
        0000000NNN0000000
        0000000NNN0000000
        0000000NNN0000000
        0000000NNN0000000
        0000000NNN0000000
        0000000NNN0000000
        0000000NNN0000000
        WWWWWWWNNNEEEEEEE
        WWWWWWWW0EEEEEEEE
        WWWWWWWSSSEEEEEEE
        0000000SSS0000000
        0000000SSS0000000
        0000000SSS0000000
        0000000SSS0000000
        0000000SSS0000000
        0000000SSS0000000
        0000000SSS0000000
      ]]
    }
  }
}

-- direction patterns
local ek = (voc() == 1 or voc() == 11) and true

local posN = ek and [[
  111
  000
  000
]] or [[
  00011111000
  00011111000
  00011111000
  00011111000
  00000100000
  00000000000
  00000000000
  00000000000
  00000000000
  00000000000
  00000000000
]]

local posE = ek and [[
  001
  001
  001
]] or   [[
  00000000000
  00000000000
  00000000000
  00000001111
  00000001111
  00000011111
  00000001111
  00000001111
  00000000000
  00000000000
  00000000000
]]
local posS = ek and [[
  000
  000
  111
]] or   [[
  00000000000
  00000000000
  00000000000
  00000000000
  00000000000
  00000000000
  00000100000
  00011111000
  00011111000
  00011111000
  00011111000
]]
local posW = ek and [[
  100
  100
  100
]] or   [[
  00000000000
  00000000000
  00000000000
  11110000000
  11110000000
  11111000000
  11110000000
  11110000000
  00000000000
  00000000000
  00000000000
]]

-- AttackBotConfig
-- create blank profiles 
if not AttackBotConfig[panelName] or not AttackBotConfig[panelName][1] or #AttackBotConfig[panelName] ~= 5 then
  AttackBotConfig[panelName] = {
    [1] = {
      enabled = false,
      attackTable = {},
      ignoreMana = true,
      Kills = false,
      Rotate = false,
      name = "Profile #1",
      Cooldown = true,
      Visible = true,
      OldSchool = false,
      pvpMode = false,
      KillsAmount = 1,
      PvpSafe = true,
      BlackListSafe = false,
      AntiRsRange = 5
    },
    [2] = {
      enabled = false,
      attackTable = {},
      ignoreMana = true,
      Kills = false,
      Rotate = false,
      name = "Profile #2",
      Cooldown = true,
      Visible = true,
      OldSchool = false,
      pvpMode = false,
      KillsAmount = 1,
      PvpSafe = true,
      BlackListSafe = false,
      AntiRsRange = 5
    },
    [3] = {
      enabled = false,
      attackTable = {},
      ignoreMana = true,
      Kills = false,
      Rotate = false,
      name = "Profile #3",
      Cooldown = true,
      Visible = true,
      OldSchool = false,
      pvpMode = false,
      KillsAmount = 1,
      PvpSafe = true,
      BlackListSafe = false,
      AntiRsRange = 5
    },
    [4] = {
      enabled = false,
      attackTable = {},
      ignoreMana = true,
      Kills = false,
      Rotate = false,
      name = "Profile #4",
      Cooldown = true,
      Visible = true,
      OldSchool = false,
      pvpMode = false,
      KillsAmount = 1,
      PvpSafe = true,
      BlackListSafe = false,
      AntiRsRange = 5
    },
    [5] = {
      enabled = false,
      attackTable = {},
      ignoreMana = true,
      Kills = false,
      Rotate = false,
      name = "Profile #5",
      Cooldown = true,
      Visible = true,
      OldSchool = false,
      pvpMode = false,
      KillsAmount = 1,
      PvpSafe = true,
      BlackListSafe = false,
      AntiRsRange = 5
    },
  }
end
  
if not AttackBotConfig.currentBotProfile or AttackBotConfig.currentBotProfile == 0 or AttackBotConfig.currentBotProfile > 5 then 
  AttackBotConfig.currentBotProfile = 1
end

local catalogChanged = false
for _, profile in ipairs(AttackBotConfig[panelName]) do
  for _, entry in ipairs(profile.attackTable or {}) do
    if catalog.migrateEntry(entry) then catalogChanged = true end
  end
  if catalog.normalize(profile.name):find("paladin", 1, true) and not profile.newSpellsImported20261001 then
    local present = {}
    for _, entry in ipairs(profile.attackTable or {}) do present[catalog.normalize(entry.spell)] = true end
    profile.attackTable = profile.attackTable or {}
    for _, data in ipairs(catalog.list("Paladin")) do
      if not present[data.words] then table.insert(profile.attackTable, catalog.makeEntry(data)) end
    end
    profile.newSpellsImported20261001 = true
    catalogChanged = true
  end
  if catalog.bindVocation(profile) then catalogChanged = true end
end
if catalog.applyMythicPaladinRotation and
  catalog.applyMythicPaladinRotation(AttackBotConfig, g_settings.getNumber("profile")) then
  catalogChanged = true
end
if catalog.applyMythicDivineEmpowerment and
  catalog.applyMythicDivineEmpowerment(AttackBotConfig, g_settings.getNumber("profile")) then
  catalogChanged = true
end
-- Add the MS rotation to profile 1's existing vocation selector once. Keep its
-- RP list and settings; later edits to either vocation belong to the user.
if AttackRotation and AttackRotation.installPreset(AttackBotConfig) then catalogChanged = true end
-- JSON restores each vocation shelf separately from attackTable. Migrate the
-- saved shelves too, after any one-time rotation import has populated them.
for _, profile in ipairs(AttackBotConfig[panelName]) do
  local function migrateAimedSpells(entries)
    for _, entry in ipairs(entries or {}) do
      if (catalog.isBarrage(entry) or catalog.isDivineGrenade(entry)) and catalog.migrateEntry(entry) then catalogChanged=true end
    end
  end
  migrateAimedSpells(profile.attackTable)
  for _, entries in pairs(profile.attacksByVocation or {}) do migrateAimedSpells(entries) end
end
if catalogChanged then vBotConfigSave("atk") end

-- create panel UI
ui = UI.createWidget("AttackBotBotPanel")
-- Reorder only this panel; keep the module load order and attack logic intact.
local attackPanelParent = ui:getParent()
if attackPanelParent then
  attackPanelParent:moveChildToIndex(ui, 1)
end

-- finding correct table, manual unfortunately
local setActiveProfile = function()
  local n = AttackBotConfig.currentBotProfile
  currentSettings = AttackBotConfig[panelName][n]
  catalog.bindVocation(currentSettings)
  syncTargetFacing()
end
setActiveProfile()

if not currentSettings.AntiRsRange then
  currentSettings.AntiRsRange = 5 
end

local setProfileName = function()
  local vocation = currentSettings.selectedVocation
  local name = currentSettings.name
  ui.name:setText(vocation ~= "Personalizado" and catalog.normalize(name) ~= catalog.normalize(vocation) and name .. " / " .. vocation or name)
  if mainWindow then mainWindow.shooterLabel:setText("Spells - " .. vocation) end
end

-- small UI elements
ui.title.onClick = function(widget)
  currentSettings.enabled = not currentSettings.enabled
  local paused = AttackBot and AttackBot.isPaused and AttackBot.isPaused()
  widget:setOn(currentSettings.enabled and not paused)
  vBotConfigSave("atk")
end
  
ui.settings.onClick = function(widget)
  mainWindow:show()
  mainWindow:raise()
  mainWindow:focus()
end

  mainWindow = UI.createWindow("AttackBotWindow")
  mainWindow:hide()

  local panel = mainWindow.mainPanel
  local settingsUI = mainWindow.settingsPanel
  local pendingEdit
  local updatingVocation = false
  local function restorePendingEdit()
    if not pendingEdit then return end
    local label = UI.createWidget("AttackEntry", panel.entryList)
    label.params = pendingEdit.params
    setupWidget(label)
    panel.entryList:moveChildToIndex(label, pendingEdit.index)
    pendingEdit = nil
  end
  local function saveAttackEntries()
    restorePendingEdit()
    currentSettings.attackTable = {}
    for _, child in ipairs(panel.entryList:getChildren()) do
      table.insert(currentSettings.attackTable, child.params)
    end
    currentSettings.attacksByVocation[currentSettings.selectedVocation] = currentSettings.attackTable
    if AttackRotation then AttackRotation.saveVocationSettings(currentSettings) end
    vBotConfigSave("atk")
  end

  mainWindow.onVisibilityChange = function(widget, visible)
    if not visible then
      saveAttackEntries()
    end
  end

  -- main panel

    -- functions
    function toggleSettings()
      panel:setVisible(not showSettings)
      mainWindow.shooterLabel:setVisible(not showSettings)
      settingsUI:setVisible(showSettings)
      mainWindow.settingsLabel:setVisible(showSettings)
      mainWindow.settings:setText(showSettings and "Back" or "Settings")
    end
    toggleSettings()

    mainWindow.settings.onClick = function()
      showSettings = not showSettings
      toggleSettings()
    end

    function toggleItem()
      panel.monsters:setWidth(showItem and 405 or 341)
      panel.itemId:setVisible(showItem)
      panel.spellName:setVisible(not showItem)
    end
    toggleItem()

    function setCategoryText()
      panel.category.description:setText(categories[category])
    end
    setCategoryText()

    function setPatternText()
      panel.range.description:setText(patterns[patternCategory][pattern])
    end
    setPatternText()

    -- in/de/crementation buttons
    panel.previousCategory.onClick = function()
      if category == 1 then
        category = #categories
      else
        category = category - 1
      end

      showItem = (category == 2 or category == 3) and true or false
      patternCategory = categoryPattern(category)
      pattern = 1
      toggleItem()
      setPatternText()
      setCategoryText()
    end
    panel.nextCategory.onClick = function()
      if category == #categories then
        category = 1 
      else
        category = category + 1
      end

      showItem = (category == 2 or category == 3) and true or false
      patternCategory = categoryPattern(category)
      pattern = 1
      toggleItem()
      setPatternText()
      setCategoryText()
    end
    panel.previousSource.onClick = function()
      warn("[AttackBot] TODO, reserved for future use.")
    end
    panel.nextSource.onClick = function()
      warn("[AttackBot] TODO, reserved for future use.")
    end
    panel.previousRange.onClick = function()
      local t = patterns[patternCategory]
      if pattern == 1 then
        pattern = #t 
      else
        pattern = pattern - 1
      end
      setPatternText()
    end
    panel.nextRange.onClick = function()
      local t = patterns[patternCategory]
      if pattern == #t then
        pattern = 1 
      else
        pattern = pattern + 1
      end
      setPatternText()
    end
    -- eo in/de/crementation

  ------- [[core table function]] -------
    function setupWidget(widget)
      local params = widget.params

      widget:setText(params.description)
      if params.itemId > 0 then
        widget.spell:setVisible(false)
        widget.id:setVisible(true)
        widget.id:setItemId(params.itemId)
      end
      widget:setTooltip(params.tooltip)
      widget.remove.onClick = function()
        panel.up:setEnabled(false)
        panel.down:setEnabled(false)
        widget:destroy()
      end
      widget.enabled:setChecked(params.enabled)
      widget.enabled.onClick = function()
        params.enabled = not params.enabled
        widget.enabled:setChecked(params.enabled)
      end
      -- will serve as edit
      widget.onDoubleClick = function(widget)
        restorePendingEdit()
        pendingEdit = {params=params, index=panel.entryList:getChildIndex(widget)}
        panel.monsters:setText(params.creatures)
        panel.manaPercent:setValue(params.mana)
        panel.creatures:setValue(params.count)
        panel.minHp:setValue(params.minHp)
        panel.maxHp:setValue(params.maxHp)
        panel.cooldown:setValue(params.cooldown)
        showItem = params.itemId > 100 and true or false
        panel.itemId:setItemId(params.itemId)
        panel.spellName:setText(params.spell or "")
        panel.orMore:setChecked(params.orMore)
        catalogEditFields = {catalogSpell=params.catalogSpell,
          catalogGeometryVersion=params.catalogGeometryVersion,
          spellRange=params.spellRange, chainTargets=params.chainTargets,
          chainJump=params.chainJump, minimumHarmony=params.minimumHarmony,
          secondaryCooldown=params.secondaryCooldown}
        toggleItem()
        category = params.category
        patternCategory = params.patternCategory
        pattern = params.pattern
        setPatternText()
        setCategoryText()
        widget:destroy()
      end
      widget.onClick = function(widget)
        if #panel.entryList:getChildren() == 1 then
          panel.up:setEnabled(false)
          panel.down:setEnabled(false)
        elseif panel.entryList:getChildIndex(widget) == 1 then
          panel.up:setEnabled(false)
          panel.down:setEnabled(true)
        elseif panel.entryList:getChildIndex(widget) == panel.entryList:getChildCount() then
          panel.up:setEnabled(true)
          panel.down:setEnabled(false)
        else
          panel.up:setEnabled(true)
          panel.down:setEnabled(true)
        end
      end
    end


    -- refreshing values
    function refreshAttacks()
      if not currentSettings.attackTable then return end

      panel.entryList:destroyChildren()
      for i, entry in pairs(currentSettings.attackTable) do
        local label = UI.createWidget("AttackEntry", panel.entryList)
        label.params = entry
        setupWidget(label)
      end
    end
    refreshAttacks()
    panel.up:setEnabled(false)
    panel.down:setEnabled(false)

    -- adding values
    panel.addEntry.onClick = function(wdiget)
      -- first variables
      local creatures = panel.monsters:getText():lower()
      local monsters = (creatures:len() == 0 or creatures == "*" or creatures == "monster names") and true or string.split(creatures, ",")
      local mana = panel.manaPercent:getValue()
      local count = panel.creatures:getValue()
      local minHp = panel.minHp:getValue()
      local maxHp = panel.maxHp:getValue()
      local cooldown = panel.cooldown:getValue()
      local itemId = panel.itemId:getItemId()
      local spell = panel.spellName:getText()
      local tooltip = monsters ~= true and creatures
      local orMore = panel.orMore:isChecked()

      -- validation
      if showItem and itemId < 100 then
        return warn("[AttackBot]: please fill item ID!")
      elseif not showItem and (spell:lower() == "spell name" or spell:len() == 0) then
        return warn("[AttackBot]: please fill spell name!")
      end
      if not showItem and not catalog.allowed({spell=spell,itemId=0}, currentSettings.selectedVocation) then
        return warn("[AttackBot] Ese spell no corresponde a " .. currentSettings.selectedVocation .. ". Usa Personalizado para spells propios del servidor.")
      end

      local regex = patternCategory ~= 1 and [[^[^\(]+]] or [[^[^R]+]]
      local type = regexMatch(patterns[patternCategory][pattern], regex)[1][1]:trim()
      regex = [[^[^ ]+]]
      local categoryName = regexMatch(categories[category], regex)[1][1]:trim():lower()
      local specificMonsters = monsters == true and "Any Creatures" or "Creatures"
      local attackType = showItem and "rune "..itemId or spell

      local countDescription = orMore and count.."+" or count

      local params = {
        creatures = creatures,
        monsters = monsters,
        mana = mana,
        count = count,
        minHp = minHp,
        maxHp = maxHp,
        cooldown = cooldown,
        itemId = itemId,
        spell = spell,
        enabled = true,
        category = category,
        patternCategory = patternCategory,
        pattern = pattern,
        tooltip = tooltip,
        orMore = orMore,
        description = '['..type..'] '..countDescription.. ' '..specificMonsters..': '..attackType..', '..categoryName..' ('..minHp..'%-'..maxHp..'%)'
      }

      if catalogEditFields then
        for key, value in pairs(catalogEditFields) do params[key] = value end
      end
      if category == 6 and not params.spellRange then
        local model = catalog.models[pattern]
        params.spellRange, params.chainTargets, params.chainJump = model.range or 7, model.maxTargets, model.jump
      end
      catalog.migrateEntry(params)

      local label = UI.createWidget("AttackEntry", panel.entryList)
      label.params = params
      setupWidget(label)
      pendingEdit = nil
      resetFields()
    end

    -- moving values
    -- up
    panel.up.onClick = function(widget)
      local focused = panel.entryList:getFocusedChild()
      local n = panel.entryList:getChildIndex(focused)

      if n-1 == 1 then
        widget:setEnabled(false)
      end
      panel.down:setEnabled(true)
      panel.entryList:moveChildToIndex(focused, n-1)
      panel.entryList:ensureChildVisible(focused)
    end
    -- down
    panel.down.onClick = function(widget)
      local focused = panel.entryList:getFocusedChild()
      local n = panel.entryList:getChildIndex(focused)

      if n + 1 == panel.entryList:getChildCount() then
        widget:setEnabled(false)
      end
      panel.up:setEnabled(true)
      panel.entryList:moveChildToIndex(focused, n+1)
      panel.entryList:ensureChildVisible(focused)
    end

  -- [[settings panel]] --
  settingsUI.profileName.onTextChange = function(widget, text)
    currentSettings.name = text
    setProfileName()
  end
  settingsUI.IgnoreMana.onClick = function(widget)
    currentSettings.ignoreMana = not currentSettings.ignoreMana
    settingsUI.IgnoreMana:setChecked(currentSettings.ignoreMana)
  end
  settingsUI.Rotate.onClick = function(widget)
    currentSettings.Rotate = not currentSettings.Rotate
    settingsUI.Rotate:setChecked(currentSettings.Rotate)
    syncTargetFacing()
  end
  settingsUI.Kills.onClick = function(widget)
    currentSettings.Kills = not currentSettings.Kills
    settingsUI.Kills:setChecked(currentSettings.Kills)
  end
  settingsUI.Cooldown.onClick = function(widget)
    currentSettings.Cooldown = not currentSettings.Cooldown
    settingsUI.Cooldown:setChecked(currentSettings.Cooldown)
    if not currentSettings.Cooldown then
      currentSettings.ClientCooldowns = false
      settingsUI.ClientCooldowns:setChecked(false)
    end
  end
  settingsUI.ClientCooldowns.onClick = function(widget)
    currentSettings.ClientCooldowns = not currentSettings.ClientCooldowns
    settingsUI.ClientCooldowns:setChecked(currentSettings.ClientCooldowns)
    if currentSettings.ClientCooldowns then
      currentSettings.Cooldown = true
      settingsUI.Cooldown:setChecked(true)
    end
    vBotConfigSave("atk")
  end
  settingsUI.Visible.onClick = function(widget)
    currentSettings.Visible = not currentSettings.Visible
    settingsUI.Visible:setChecked(currentSettings.Visible)
  end
  settingsUI.OldSchool.onClick = function(widget)
    currentSettings.OldSchool = not currentSettings.OldSchool
    settingsUI.OldSchool:setChecked(currentSettings.OldSchool)
  end
  settingsUI.PvpMode.onClick = function(widget)
    currentSettings.pvpMode = not currentSettings.pvpMode
    settingsUI.PvpMode:setChecked(currentSettings.pvpMode)
  end
  settingsUI.PvpSafe.onClick = function(widget)
    currentSettings.PvpSafe = not currentSettings.PvpSafe
    settingsUI.PvpSafe:setChecked(currentSettings.PvpSafe)
  end
  settingsUI.Training.onClick = function(widget)
    currentSettings.Training = not currentSettings.Training
    settingsUI.Training:setChecked(currentSettings.Training)
  end
  settingsUI.BlackListSafe.onClick = function(widget)
    currentSettings.BlackListSafe = not currentSettings.BlackListSafe
    settingsUI.BlackListSafe:setChecked(currentSettings.BlackListSafe)
  end
  settingsUI.KillsAmount.onValueChange = function(widget, value)
    currentSettings.KillsAmount = value
  end
  settingsUI.AntiRsRange.onValueChange = function(widget, value)
    currentSettings.AntiRsRange = value
  end


   -- window elements
  mainWindow.closeButton.onClick = function()
    showSettings = false
    toggleSettings()
    resetFields()
    mainWindow:hide()
  end

  -- core functions
  function resetFields()
    catalogEditFields = nil
    showItem = false
    toggleItem()
    pattern = 1
    patternCategory = 1
    category = 1
    setPatternText()
    setCategoryText()
    panel.manaPercent:setText(1)
    panel.creatures:setText(1)
    panel.minHp:setValue(0)
    panel.maxHp:setValue(100)
    panel.cooldown:setText(2000)
    panel.monsters:setText("monster names")
    panel.itemId:setItemId(0)
    panel.spellName:setText("spell name")
    panel.orMore:setChecked(false)
  end
  resetFields()

  local catalogWindow = UI.createWindow("AttackSpellCatalogWindow")
  catalogWindow:hide()
  local catalogChoices = {}
  local function selectedCatalogSpell()
    local choice = catalogWindow.spellChoice:getCurrentOption()
    return choice and catalogChoices[choice.text]
  end
  local function refreshCatalogDetails()
    local data = selectedCatalogSpell()
    catalogWindow.addSelected:setEnabled(data ~= nil)
    catalogWindow.addVocation:setEnabled(data ~= nil)
    if not data then
      catalogWindow.details:setText("No hay nuevos presets para esta vocacion. Puedes configurar sus ataques en la lista principal.")
      return
    end
    local model = data.pattern and catalog.models[data.pattern]
    local existing
    for _, child in ipairs(panel.entryList:getChildren()) do
      if catalog.normalize(child.params.spell) == data.words then existing = child.params; break end
    end
    catalogWindow.details:setText(catalog.describe(data))
    catalogWindow.spellRange:setValue(existing and existing.spellRange or model and model.range or data.range)
    catalogWindow.chainTargets:setValue(existing and existing.chainTargets or model and model.maxTargets or 1)
    catalogWindow.chainJump:setValue(existing and existing.chainJump or model and model.jump or 1)
    catalogWindow.chainTargets:setEnabled(model and model.chain or false)
    catalogWindow.chainJump:setEnabled(model and model.chain or false)
    catalogWindow.minimumHarmony:setEnabled(data.harmony == "spender")
    catalogWindow.minimumHarmony:setValue(existing and existing.minimumHarmony or 0)
  end
  local function refreshCatalogChoices()
    local vocation = catalogWindow.vocation:getCurrentOption()
    if not vocation then return end
    catalogWindow.spellChoice:clearOptions()
    catalogChoices = {}
    for _, data in ipairs(catalog.list(vocation.text)) do
      catalogChoices[data.name] = data
      catalogWindow.spellChoice:addOption(data.name)
    end
    refreshCatalogDetails()
  end
  catalogWindow.vocation.onOptionChange = refreshCatalogChoices
  catalogWindow.spellChoice.onOptionChange = refreshCatalogDetails
  local function addCatalogSpell(data, overrides)
    if currentSettings.selectedVocation ~= "Personalizado" and data.vocation ~= currentSettings.selectedVocation then return false end
    for _, child in ipairs(panel.entryList:getChildren()) do
      if catalog.normalize(child.params.spell) == data.words then return false end
    end
    local label = UI.createWidget("AttackEntry", panel.entryList)
    label.params = catalog.makeEntry(data, overrides)
    setupWidget(label)
    return true
  end
  catalogWindow.addSelected.onClick = function()
    local data = selectedCatalogSpell()
    if not data then return end
    if currentSettings.selectedVocation ~= "Personalizado" and data.vocation ~= currentSettings.selectedVocation then return end
    local overrides = {spellRange=catalogWindow.spellRange:getValue(),
      minimumHarmony=catalogWindow.minimumHarmony:getValue()}
    local model = data.pattern and catalog.models[data.pattern]
    if model and model.chain then
      overrides.chainTargets, overrides.chainJump = catalogWindow.chainTargets:getValue(), catalogWindow.chainJump:getValue()
    end
    if data.category == 1 then overrides.pattern = overrides.spellRange end
    if addCatalogSpell(data, overrides) then
      saveAttackEntries()
      catalogWindow.status:setText("Agregado desactivado a " .. currentSettings.name .. ". Activalo en la lista y ajusta CD/patron con doble clic.")
    else
      for _, child in ipairs(panel.entryList:getChildren()) do
        if catalog.normalize(child.params.spell) == data.words then
          for key, value in pairs(overrides) do child.params[key] = value end
          saveAttackEntries()
          catalogWindow.status:setText("Ajustes guardados para " .. data.name .. ". Su estado, orden, conteo y CD se conservan.")
          break
        end
      end
    end
  end
  catalogWindow.addVocation.onClick = function()
    local vocation = catalogWindow.vocation:getCurrentOption()
    if not vocation then return end
    local amount = 0
    for _, data in ipairs(catalog.list(vocation.text)) do
      if addCatalogSpell(data) then amount = amount+1 end
    end
    saveAttackEntries()
    catalogWindow.status:setText(amount .. " spells agregados desactivados a " .. currentSettings.name .. ". Activa los que conoces y usa Move Up para ordenar.")
  end
  catalogWindow.closeButton.onClick = function() catalogWindow:hide() end
  mainWindow.spellCatalog.onClick = function()
    if currentSettings.selectedVocation ~= "Personalizado" then
      catalogWindow.vocation:setCurrentOption(currentSettings.selectedVocation)
    end
    catalogWindow.vocation:setEnabled(currentSettings.selectedVocation == "Personalizado")
    refreshCatalogChoices()
    catalogWindow:show()
    catalogWindow:raise()
    catalogWindow:focus()
  end
  refreshCatalogChoices()

  function loadSettings()
    -- BOT panel
    local paused = AttackBot and AttackBot.isPaused and AttackBot.isPaused()
    ui.title:setOn(currentSettings.enabled and not paused)
    setProfileName()
    updatingVocation = true
    mainWindow.vocation:setCurrentOption(currentSettings.selectedVocation)
    updatingVocation = false
    -- main panel
    refreshAttacks()
    -- settings
    settingsUI.profileName:setText(currentSettings.name)
    settingsUI.Visible:setChecked(currentSettings.Visible)
    settingsUI.OldSchool:setChecked(currentSettings.OldSchool)
    settingsUI.Cooldown:setChecked(currentSettings.Cooldown)
    settingsUI.ClientCooldowns:setChecked(currentSettings.ClientCooldowns == true)
    settingsUI.PvpMode:setChecked(currentSettings.pvpMode)
    settingsUI.PvpSafe:setChecked(currentSettings.PvpSafe)
    settingsUI.BlackListSafe:setChecked(currentSettings.BlackListSafe)
    settingsUI.AntiRsRange:setValue(currentSettings.AntiRsRange)
    settingsUI.IgnoreMana:setChecked(currentSettings.ignoreMana)
    settingsUI.Rotate:setChecked(currentSettings.Rotate)
    settingsUI.Kills:setChecked(currentSettings.Kills)
    settingsUI.KillsAmount:setValue(currentSettings.KillsAmount)
    settingsUI.Training:setChecked(currentSettings.Training)
  end
  loadSettings()

  mainWindow.vocation.onOptionChange = function(widget, option)
    if updatingVocation then return end
    local selected = widget:getCurrentOption()
    if not selected or selected.text == currentSettings.selectedVocation then return end
    saveAttackEntries()
    if AttackRotation then
      AttackRotation.selectVocation(currentSettings, selected.text)
    else
      catalog.bindVocation(currentSettings, selected.text)
    end
    catalogWindow:hide()
    resetFields()
    loadSettings()
    syncTargetFacing()
    vBotConfigSave("atk")
  end

  local activeProfileColor = function()
    for i=1,5 do
      if i == AttackBotConfig.currentBotProfile then
        ui[i]:setColor("green")
      else
        ui[i]:setColor("white")
      end
    end
  end
  activeProfileColor()

  local profileChange = function()
    saveAttackEntries()
    catalogWindow:hide()
    setActiveProfile()
    activeProfileColor()
    loadSettings()
    resetFields()
    vBotConfigSave("atk")
  end

  for i=1,5 do
    local button = ui[i]
      button.onClick = function()
      AttackBotConfig.currentBotProfile = i
      profileChange()
    end
  end

    -- public functions
    AttackBot = {} -- global table
    AttackBot.syncTargetFacing = syncTargetFacing
    AttackBot.pauseReasons = {}

    AttackBot.isPaused = function()
      for _, paused in pairs(AttackBot.pauseReasons) do
        if paused then return true end
      end
      return false
    end

    AttackBot.setPause = function(reason, paused)
      reason = tostring(reason or "default")
      local wasPaused = AttackBot.isPaused()
      AttackBot.pauseReasons[reason] = paused == true or nil
      local isPaused = AttackBot.isPaused()

      if wasPaused ~= isPaused and ui and ui.title then
        ui.title:setOn(currentSettings.enabled and not isPaused)
      end
    end
  
    AttackBot.isOn = function()
      return currentSettings.enabled
    end
    
    AttackBot.isOff = function()
      return not currentSettings.enabled
    end
    
    AttackBot.setOff = function()
      currentSettings.enabled = false
      ui.title:setOn(currentSettings.enabled and not AttackBot.isPaused())
      vBotConfigSave("atk")
    end
    
    AttackBot.setOn = function()
      currentSettings.enabled = true
      ui.title:setOn(currentSettings.enabled and not AttackBot.isPaused())
      vBotConfigSave("atk")
    end

    AttackBot.getActiveProfile = function()
      return AttackBotConfig.currentBotProfile -- returns number 1-5
    end
  
    AttackBot.setActiveProfile = function(n)
      if not n or not tonumber(n) or n < 1 or n > 5 then
        return error("[AttackBot] wrong profile parameter! should be 1 to 5 is " .. n)
      else
        AttackBotConfig.currentBotProfile = n
        profileChange()
      end
    end

    AttackBot.show = function()
      mainWindow:show()
      mainWindow:raise()
      mainWindow:focus()
    end

-- Redesigned editor, installed only in the pruebas bot. The original widgets
-- stay hidden and continue to supply the same attack entries to the engine.
dofile('/vBot/attack_editor.lua')
local attackEditor = AttackBotEditor.create({
  catalog=catalog, patterns=patterns,
  getSettings=function() return currentSettings end,
  getProfile=function() return AttackBotConfig.currentBotProfile end,
  getProfileName=function(n) return AttackBotConfig[panelName][n].name end,
  switchProfile=function(n) AttackBot.setActiveProfile(n) end,
  apply=function(draft, expectedProfile)
    if expectedProfile ~= AttackBotConfig.currentBotProfile then
      return false, 'El perfil activo cambio. Vuelve a abrir el editor.'
    end
    restorePendingEdit()
    local enableFacing = draft.Rotate == true and
      (currentSettings.Rotate ~= true or draft.selectedVocation ~= currentSettings.selectedVocation)
    draft.enabled=currentSettings.enabled
    for key in pairs(currentSettings) do currentSettings[key]=nil end
    for key, value in pairs(draft) do currentSettings[key]=value end
    currentSettings.attacksByVocation[currentSettings.selectedVocation]=currentSettings.attackTable
    loadSettings()
    saveAttackEntries()
    if enableFacing then syncTargetFacing() end
    return true
  end,
})
ui.settings.onClick=function() attackEditor.show() end
AttackBot.show=function() attackEditor.show() end
for i=1,5 do
  local n=i
  ui[i].onClick=function() attackEditor.requestProfile(n) end
end

-- otui covered, now support functions
function getPattern(category, pattern, safe)
  safe = safe and 2 or 1

  return spellPatterns[category][pattern][safe]
end

-- These snapshots belong only to the current macro call. External callers of
-- the public helpers still read the live client when no cycle is supplied.
local catalogActor
local function attackEntries(cycle)
  return cycle and cycle.entries or panel.entryList:getChildren()
end
local function attackSpectators(cycle, anchor, pattern)
  if not cycle then return getSpectators(anchor, pattern) end
  local position, direction
  if anchor and anchor.getPosition then
    position, direction = anchor:getPosition(), anchor:getDirection()
  elseif anchor then position, direction = anchor, 8
  else position, direction = pos(), player:getDirection() end
  if not position then return getSpectators(anchor, pattern) end
  local key = position.x..":"..position.y..":"..position.z..":"..direction..":"..(pattern or "")
  if not cycle.spectators[key] then cycle.spectators[key] = getSpectators(anchor, pattern) end
  return cycle.spectators[key]
end
local function attackMonster(spec, cycle)
  if cycle then
    local actor = catalogActor(spec, cycle)
    return actor.hp, actor.name:lower(), actor.monster and not actor.summon
  end
  return spec:getHealthPercent(), spec:getName():lower(), spec:isMonster() and
    (g_game.getClientVersion() < 960 or spec:getType() < 3)
end

local function isFriendlyPlayerUncached(spec)
  if not spec or spec == player then return true end
  if not spec:isPlayer() then return false end
  if spec:isLocalPlayer() then return true end
  if spec:isPartyMember() then return true end

  local name = spec:getName()
  if not name then return false end

  if PlayerList then
    if PlayerList.isFriend then
      local ok, result = pcall(function() return PlayerList.isFriend(name) end)
      if ok and result then return true end
    end
    if PlayerList.isGuildMember then
      local ok, result = pcall(function() return PlayerList.isGuildMember(name) end)
      if ok and result then return true end
    end
  end

  if isFriend then
    local ok, result = pcall(function() return isFriend(spec) end)
    if ok and result then return true end
  end

  return false
end

local function isAttackBotFriendlyPlayer(spec, cycle)
  if not cycle or not spec then return isFriendlyPlayerUncached(spec) end
  local id = spec:getId()
  if cycle.friends[id] == nil then cycle.friends[id] = isFriendlyPlayerUncached(spec) end
  return cycle.friends[id]
end

local function hasUnsafePlayerInAttackBotRange(range, cycle)
  range = range or 10
  for _, spec in pairs(attackSpectators(cycle)) do
    if spec ~= player and spec:isPlayer() and distanceFromPlayer(spec:getPosition()) <= range and
      not isAttackBotFriendlyPlayer(spec, cycle) then
      return true
    end
  end
  return false
end


function getMonstersInArea(category, posOrCreature, pattern, minHp, maxHp, safePattern, monsterNamesTable, cycle)
  -- monsterNamesTable can be nil
  local monsters = 0
  local t = {}
  if monsterNamesTable == true or not monsterNamesTable then
    t = {}
  else
    t = monsterNamesTable
  end

  if safePattern then
    for i, spec in pairs(attackSpectators(cycle, posOrCreature, safePattern)) do
      if spec ~= player and spec:isPlayer() and not isAttackBotFriendlyPlayer(spec, cycle) then
        return 0
      end
    end
  end 

  if category == 1 or category == 3 or category == 4 then
    if category == 1 or category == 3 then
      local name = getTarget() and getTarget():getName()
      if #t ~= 0 and not table.find(t, name, true) then
        return 0
      end
    end
    for i, spec in pairs(attackSpectators(cycle)) do
      local specHp, name, monster = attackMonster(spec, cycle)
      monsters = monster and specHp >= minHp and specHp <= maxHp and (#t == 0 or table.find(t, name, true)) and
                 monsters + 1 or monsters
    end
    return monsters
  end

  for i, spec in pairs(attackSpectators(cycle, posOrCreature, pattern)) do
      if spec ~= player then
        local specHp, name, monster = attackMonster(spec, cycle)
        monsters = monster and specHp >= minHp and specHp <= maxHp and (#t == 0 or table.find(t, name)) and
                   monsters + 1 or monsters
      end
  end

  return monsters
end

-- for area runes only
-- should return valid targets number (int) and position
function getBestTileByPattern(pattern, minHp, maxHp, safePattern, monsterNamesTable, cycle)
  local tiles = cycle and cycle.runeTiles
  if not tiles then
    tiles = {}
    local origin = pos()
    -- Only these 49 squares can satisfy the original distance < 4 rule.
    for x=math.max(0,origin.x-3),math.min(65535,origin.x+3) do
      for y=math.max(0,origin.y-3),math.min(65535,origin.y+3) do
        local position = {x=x,y=y,z=origin.z}
        local tile = g_map.getTile(position)
        if tile and tile:canShoot() and tile:isWalkable() then tiles[#tiles+1] = position end
      end
    end
    if cycle then cycle.runeTiles = tiles end
  end
  local targetTile = {amount=0,pos=false}

  for _, tPos in ipairs(tiles) do
    local amount = getMonstersInArea(2, tPos, pattern, minHp, maxHp, safePattern, monsterNamesTable, cycle)
    if amount > targetTile.amount then
      targetTile = {amount=amount,pos=tPos}
    end
  end

  return targetTile.amount > 0 and targetTile or false
end

-- Client cooldown mode reads the same native spell/group icons as the HUD.
-- Keep the legacy timers as fallback, and never change shared vlib behavior.
local clientSpellCache, clientCastPending, clientSpellReadyAt, clientGroupReadyAt = {}, {}, {}, {}
local clientLearnedSpells, clientLastSpell, clientLastSpellAt, clientLastSpellIcon = {}, nil, 0, false
local clientPendingAcks = {}
local rotationRuntime

local function confirmAttackBotSpell(words, speech)
  local pending = clientPendingAcks[words]
  local recent = pending and now-pending.at <= 2000
  local duplicate = recent and pending.confirmed and (not speech or not pending.speech)
  if recent then
    pending.confirmed = true
    if speech then pending.speech = true end
  end
  if not duplicate and AttackRotation then
    rotationRuntime = rotationRuntime or AttackRotation.newRuntime()
    AttackRotation.confirm(rotationRuntime, words, now, currentSettings.selectedVocation)
  end
end

local function attackClientSpellInfo(words)
  local cooldowns = modules.game_cooldown
  if not currentSettings.ClientCooldowns or not currentSettings.Cooldown or
    type(cooldowns.isCooldownIconActive) ~= "function" or
    type(cooldowns.isGroupCooldownIconActive) ~= "function" or g_game.getClientVersion() < 960 then return nil end
  words = catalog.normalize(words)
  local data = clientSpellCache[words]
  if not data and getSpellData then
    data = getSpellData(words)
    if type(data) == "table" then clientSpellCache[words] = data else data = nil end
  end
  -- Prefer packets observed after confirmed own spell speech. vlib's learned
  -- IDs remain useful before this AttackBot session has seen the first cast.
  local observed = clientLearnedSpells[words]
  local learned = vBot and vBot.customCooldowns and vBot.customCooldowns[words]
  local id = tonumber(observed and observed.id or learned and learned.id or data and data.id)
  if not id or id <= 0 then return nil end
  local groups, durations, secondary = {}, {}, false
  if observed and observed.group then
    for groupId,duration in pairs(observed.group) do groups[groupId] = true;durations[groupId]=tonumber(duration) end
  else
    for groupId,duration in pairs(data and data.group or {}) do groups[groupId] = true;durations[groupId]=tonumber(duration) end
    for groupId,duration in pairs(learned and learned.group or {}) do groups[groupId] = true;durations[groupId]=tonumber(duration) or durations[groupId] end
  end
  for groupId in pairs(groups) do
    if tonumber(groupId) and tonumber(groupId) > 3 then secondary = true end
  end
  return {words=words, id=id, group=groups, durations=durations, secondary=secondary,
    duration=observed and observed.duration,
    level=tonumber(data and data.level) or 0, mana=tonumber(data and data.mana) or 0,
    requirements=data~=nil and not (learned and data.level==1 and data.mana==1)}
end

local function attackClientSpellWait(info)
  local cooldowns = modules.game_cooldown
  local wait = math.max(0, (clientCastPending[info.words] or 0)-now)
  if cooldowns.isCooldownIconActive(info.id) then
    wait = math.max(wait, clientSpellReadyAt[info.id] and math.max(100, clientSpellReadyAt[info.id]-now) or 2001)
  end
  for groupId in pairs(info.group) do
    groupId = tonumber(groupId)
    if groupId and cooldowns.isGroupCooldownIconActive(groupId) then
      wait = math.max(wait, clientGroupReadyAt[groupId] and math.max(100, clientGroupReadyAt[groupId]-now) or 2001)
    end
  end
  return wait
end

local function attackSpellReady(words, forceCooldown)
  local info = attackClientSpellInfo(words)
  if info then
    if currentSettings.ignoreMana and (level() < info.level or mana() < info.mana) then return false end
    return attackClientSpellWait(info) == 0
  end
  return canCast(words, not currentSettings.ignoreMana, not forceCooldown and not currentSettings.Cooldown)
end

function executeAttackBotAction(categoryOrPos, idOrFormula, cooldown, aimPosition)
  cooldown = cooldown or 0
  if categoryOrPos == 4 or categoryOrPos == 5 or categoryOrPos == 6 or categoryOrPos == 1 then
    local data = catalog.find(idOrFormula)
    local nativeInfo = attackClientSpellInfo(idOrFormula)
    if nativeInfo and not attackSpellReady(idOrFormula) then return false end
    local function sendSpell()
      if nativeInfo then
        -- Wait briefly for the server response instead of spamming failed casts.
        clientCastPending[nativeInfo.words] = now+500
        clientPendingAcks[nativeInfo.words] = {id=nativeInfo.id, at=now}
        cast(idOrFormula)
      else
        cast(idOrFormula, cooldown)
      end
    end
    if aimPosition then
      -- Mythic's native API appends this position to the NEXT speech packet.
      -- Never leave an aim pending when cast() skips a cooldown or throws.
      if type(g_game.setNextTalkAim) ~= "function" or g_game.getClientVersion() < 1525 then return false end
      local words = catalog.normalize(idOrFormula)
      local recorded = SpellCastTable and SpellCastTable[words]
      if not nativeInfo and cooldown >= 100 and recorded and recorded.d == cooldown and now-recorded.t < cooldown then return false end
      if data then catalogAttempts[data.words] = now end
      local ok, err = pcall(function()
        g_game.setNextTalkAim({x=aimPosition.x, y=aimPosition.y, z=aimPosition.z})
        sendSpell()
      end)
      -- This is the same invalid-position sentinel the native sender resets to.
      pcall(g_game.setNextTalkAim, {x=65535, y=65535, z=255})
      if not ok then print("[AttackBot] No se pudo apuntar " .. words .. ": " .. tostring(err)) end
      return ok
    end
    if data then catalogAttempts[data.words] = now end
    sendSpell()
  elseif categoryOrPos == 3 then
    if currentSettings.OldSchool then
      local item = findItem(idOrFormula)
      if item then
        useWith(item, target())
      end
    else
      useWith(idOrFormula, target())
    end
  end
end

-- Native spell speech confirms cooldowns for shared groups missing from older
-- client SpellInfo tables. Failed attempts only receive a short retry throttle.
onTalk(function(name, level, mode, text)
  if name ~= player:getName() then return end
  local words = catalog.normalize(text)
  -- Custom clients can report spell speech in a different talk mode. Only
  -- accept known formulas or a spell we actually sent, never ordinary chat.
  if mode ~= 44 and not (AttackRotation and AttackRotation.spells[words] or
    catalog.find(words) or clientPendingAcks[words]) then return end
  clientLastSpell, clientLastSpellAt, clientLastSpellIcon = words, now, false
  clientCastPending[clientLastSpell] = now+100
  local observed = clientLearnedSpells[clientLastSpell]
  clientLearnedSpells[clientLastSpell] = observed or {}
  clientLearnedSpells[clientLastSpell].refreshGroups = true
  confirmAttackBotSpell(clientLastSpell, true)
  local data = catalog.find(text)
  if data and data.secondary then catalogSecondary[data.secondary] = now end
  if data and data.support then empowermentReadyAt = math.max(empowermentReadyAt, now+32000) end
end)

if onSpellCooldown then
  onSpellCooldown(function(iconId, duration)
    clientSpellReadyAt[iconId] = now+math.max(0, duration)
    -- An individual icon with the exact ID of our pending cast confirms it
    -- even if spell speech is missing. Group icons alone cannot identify it.
    for words, pending in pairs(clientPendingAcks) do
      if now-pending.at > 2000 then
        clientPendingAcks[words] = nil
      elseif pending.id == iconId and duration > 0 and not pending.confirmed then
        confirmAttackBotSpell(words, false)
      end
      if pending.id == iconId and duration > 0 and now-pending.at<=250 then
        local observed=clientLearnedSpells[words] or {}
        observed.id=iconId;observed.duration=duration
        clientLearnedSpells[words]=observed
      end
    end
    if clientLastSpell and not clientLastSpellIcon and now-clientLastSpellAt <= 250 and duration > 0 then
      local observed=clientLearnedSpells[clientLastSpell]
      local native=getSpellData and getSpellData(clientLastSpell)
      local expected=tonumber(observed.id or type(native)=='table' and native.id)
      -- Monk spenders may send several shortened builder icons. They must
      -- never be mistaken for the spender's ID or its original cooldown.
      if not expected or expected==iconId then
        observed.id=iconId;observed.duration=duration
        clientLastSpellIcon = true
      end
    end
    if iconId == 268 then empowermentReadyAt = math.max(empowermentReadyAt, now+math.max(32000, duration)) end
  end)
end
if onGroupSpellCooldown then
  onGroupSpellCooldown(function(groupId, duration)
    clientGroupReadyAt[groupId] = now+math.max(0, duration)
    if clientLastSpell and now-clientLastSpellAt <= 250 and duration > 0 then
      local observed = clientLearnedSpells[clientLastSpell]
      if observed.refreshGroups then observed.group={};observed.refreshGroups=nil end
      observed.group = observed.group or {}
      observed.group[groupId] = duration
    end
    if groupId == 1 then attackGroupReadyAt = now+duration end
  end)
end

local function readCatalogHarmony()
  if not player.getHarmony then
    rotationRuntime=rotationRuntime or AttackRotation and AttackRotation.newRuntime()
    return rotationRuntime and AttackRotation.readHarmony(rotationRuntime,now) or nil
  end
  local ok, value = pcall(function() return player:getHarmony() end)
  local native=ok and tonumber(value) or nil
  if AttackRotation then
    rotationRuntime=rotationRuntime or AttackRotation.newRuntime()
    return AttackRotation.readHarmony(rotationRuntime,now,native)
  end
  return native
end

local function attackCatalogState(words)
  local info = attackClientSpellInfo(words)
  return {now=now, level=level(), mana=mana(), harmony=readCatalogHarmony(),
    secondary=catalogSecondary, attempts=catalogAttempts, nativeSecondary=info and info.secondary}
end

catalogActor = function(creature, cycle)
  local id = creature:getId()
  if cycle and cycle.actors[id] then return cycle.actors[id] end
  local monster = creature:isMonster()
  local actor = {id=id, name=creature:getName(), pos=creature:getPosition(),
    hp=creature:getHealthPercent(), monster=monster,
    summon=g_game.getClientVersion() >= 960 and monster and creature:getType() >= 3,
    unsafePlayer=creature:isPlayer() and not isAttackBotFriendlyPlayer(creature, cycle)}
  if cycle then cycle.actors[id] = actor end
  return actor
end

local function prepareCatalogAttack(entry)
  local model = catalog.models[entry.pattern]
  if not model or not model.directional or not currentSettings.Rotate then return true end
  local creature = target()
  if not creature or not TargetBot or not TargetBot.Creature then return true end
  if model.beam and TargetBot.Creature.alignAndFace then
    return TargetBot.Creature.alignAndFace(creature, {
      desiredRange=math.min(distanceFromPlayer(creature:getPosition()), model.beam),
      maxRange=model.beam, maxPath=10}) == true
  end
  if TargetBot.Creature.faceCreature then return TargetBot.Creature.faceCreature(creature) == true end
  return true
end

local function evaluateCatalogAttack(entry, cycle)
  local creature = target()
  if not creature then return 0, false end
  local direction = player:getDirection()
  local cached = cycle and cycle.evaluations[entry]
  if cached and cached.direction == direction then return cached.amount, cached.unsafe, cached.aim end
  local actors = cycle and cycle.scene or catalog.isDivineGrenade(entry) and grenadeScene or nil
  if not actors then
    actors = {}
    for _, spec in pairs(attackSpectators(cycle)) do
      if spec ~= player then table.insert(actors, catalogActor(spec, cycle)) end
    end
    if cycle then cycle.scene = actors end
  end
  if catalog.isBarrage(entry) or catalog.isDivineGrenade(entry) then
    if type(g_game.setNextTalkAim) ~= "function" or g_game.getClientVersion() < 1525 then return 0, false end
    local function canAim(position)
      local key = position.x..":"..position.y..":"..position.z
      if cycle and cycle.aimable[key] ~= nil then return cycle.aimable[key] end
      local tile = g_map.getTile(position)
      local allowed = tile and tile:getGround() and tile:canShoot() or false
      if cycle then cycle.aimable[key] = allowed end
      return allowed
    end
    local best
    if catalog.isDivineGrenade(entry) then
      best = catalog.bestGrenade(entry, pos(), catalogActor(creature, cycle), actors,
        currentSettings.PvpSafe, grenadeHistory, now, canAim)
    else
      best = catalog.bestBarrage(entry, pos(), catalogActor(creature, cycle), actors,
        currentSettings.PvpSafe, canAim)
    end
    local amount, aim = best and best.amount or 0, best and best.pos or nil
    if cycle then cycle.evaluations[entry] = {direction=direction,amount=amount,unsafe=false,aim=aim} end
    return amount, false, aim
  end
  local amount, unsafe = catalog.evaluate(entry, pos(), catalogActor(creature, cycle), actors,
    direction, currentSettings.PvpSafe)
  if cycle then cycle.evaluations[entry] = {direction=direction,amount=amount,unsafe=unsafe} end
  return amount, unsafe
end

local function attackEntryMatchesTarget(entry, creature, ignoreNames)
  if not creature then return false end
  local hp = creature:getHealthPercent()
  if hp < entry.minHp or hp > entry.maxHp then return false end
  if ignoreNames or type(entry.monsters) ~= "table" or #entry.monsters == 0 then return true end
  return table.find(entry.monsters, creature:getName():lower(), true) and true or false
end

local function prepareDirectionalAttack(entry, bestDir, bestSide, ignoreNames)
  if not currentSettings.Rotate or entry.patternCategory ~= 4 then return true end

  if entry.pattern == 6 or entry.pattern == 7 then
    local creature = target()
    if not attackEntryMatchesTarget(entry, creature, ignoreNames) then return true end
    if not TargetBot or not TargetBot.Creature or not TargetBot.Creature.alignAndFace then return true end

    local beamRange = entry.pattern == 6 and 5 or 7
    local currentRange = distanceFromPlayer(creature:getPosition())
    local ready = TargetBot.Creature.alignAndFace(creature, {
      desiredRange = math.min(currentRange, beamRange),
      maxRange = beamRange,
      maxPath = 10
    })
    return ready == true
  end

  local directionalPattern = entry.pattern == 2 or entry.pattern == 8 or entry.pattern >= 9
  if not directionalPattern then return true end

  local creature = target()
  if not creature or not TargetBot or not TargetBot.Creature then return true end
  if ignoreNames and TargetBot.Creature.faceCreature then
    local ready = TargetBot.Creature.faceCreature(creature)
    return ready == true
  end
  if bestDir and bestSide > 0 and TargetBot.Creature.faceDirection then
    local ready = TargetBot.Creature.faceDirection(creature, bestDir)
    return ready == true
  end
  if TargetBot.Creature.faceCreature then
    local ready = TargetBot.Creature.faceCreature(creature)
    return ready == true
  end
  return true
end

-- A support cast uses group 3, so it can fit between two attack-group casts.
-- Require an attack which can benefit soon, rather than spending the field on
-- an empty/disabled rotation or when every useful attack is still cooling down.
local function hasEmpowermentAttack(cycle)
  local creature = target()
  local groupWait = modules.game_cooldown.isGroupCooldownIconActive(1) and
    math.max(0, attackGroupReadyAt > now and attackGroupReadyAt-now or 2000) or 0
  for _, child in ipairs(attackEntries(cycle)) do
    local entry = child.params
    if entry.enabled and entry.category ~= 4 and not catalog.isDivineEmpowerment(entry) and
      catalog.allowed(entry, currentSettings.selectedVocation) and manapercent() >= entry.mana and
      (entry.itemId <= 100 or not currentSettings.Visible or findItem(entry.itemId)) then
      local data = catalog.find(entry.spell)
      local nativeData = entry.itemId <= 100 and getSpellData and getSpellData(entry.spell)
      local attackMana = tonumber(nativeData and nativeData.mana or data and data.mana) or 0
      local recorded = SpellCastTable and SpellCastTable[catalog.normalize(entry.spell)]
      local nativeInfo = entry.itemId <= 100 and attackClientSpellInfo(entry.spell)
      local spellWait = nativeInfo and attackClientSpellWait(nativeInfo) or
        currentSettings.Cooldown and recorded and math.max(0, recorded.t+recorded.d-now) or 0
      local wait = math.max(groupWait, spellWait)
      -- Leave a small margin before the 5s field expires; a grenade needs its
      -- additional 3s fuse to land inside the same window.
      local impact = wait+(data and data.delayed or 0)
      if wait <= 2000 and impact < 4800 and mana() >= 500+attackMana and
        (not currentSettings.ignoreMana or not data or level() >= data.level and mana() >= data.mana) then
        local amount, unsafe = 0, false
        if entry.category == 6 then
          amount, unsafe = evaluateCatalogAttack(entry, cycle)
        elseif entry.category == 5 then
          local pCat = entry.patternCategory
          local pattern = spellPatterns[pCat] and spellPatterns[pCat][entry.pattern]
          if pattern then
            local safe = currentSettings.PvpSafe and pattern[2] or false
            amount = getMonstersInArea(5, pos(), pattern[1], entry.minHp, entry.maxHp, safe, entry.monsters, cycle)
          end
        elseif (entry.category == 1 or entry.category == 3) and
          distanceFromPlayer(creature:getPosition()) <= entry.pattern then
          amount = getMonstersInArea(entry.category, nil, nil, entry.minHp, entry.maxHp, false, entry.monsters, cycle)
        elseif entry.category == 2 then
          local pattern = spellPatterns[entry.patternCategory] and spellPatterns[entry.patternCategory][entry.pattern]
          if pattern then
            local tile = getBestTileByPattern(pattern[1], entry.minHp, entry.maxHp,
              currentSettings.PvpSafe and pattern[2] or false, entry.monsters, cycle)
            amount = tile and tile.amount or 0
          end
        end
        if not unsafe and (entry.orMore and amount >= entry.count or not entry.orMore and amount == entry.count) then
          return true
        end
      end
    end
  end
  return false
end

local function tryDivineEmpowerment(cycle)
  local creature = target()
  local nativeInfo = attackClientSpellInfo("utevo grav san")
  if not creature or not creature:isMonster() or not creature:canShoot() or
    (not nativeInfo and now < empowermentReadyAt) or modules.game_cooldown.isGroupCooldownIconActive(3) or
    (not nativeInfo and modules.game_cooldown.isCooldownIconActive and modules.game_cooldown.isCooldownIconActive(268)) or
    (currentSettings.BlackListSafe and isBlackListedPlayerInRange(currentSettings.AntiRsRange)) or
    (currentSettings.Kills and killsToRs() <= currentSettings.KillsAmount) then return false end
  for _, child in ipairs(attackEntries(cycle)) do
    local entry = child.params
    if entry.enabled and catalog.isDivineEmpowerment(entry) and
      catalog.allowed(entry, currentSettings.selectedVocation) and manapercent() >= entry.mana and
      mana() >= catalog.find(entry.spell).mana and catalog.ready(entry, currentSettings, attackCatalogState(entry.spell)) and
      attackSpellReady(entry.spell, true) then
      local amount = catalog.evaluateEmpowerment(entry, pos(), grenadeScene or {}, grenadeHistory, now)
      if (entry.orMore and amount >= entry.count or not entry.orMore and amount == entry.count) and
        hasEmpowermentAttack(cycle) then
        executeAttackBotAction(6, entry.spell, math.max(32000, entry.cooldown))
        return true
      end
    end
  end
  return false
end

local function tryMonkSupport(cycle)
  if not AttackRotation or currentSettings.selectedVocation~="Monk" or currentSettings.pvpMode then return false end
  local creature=target()
  local harmony=readCatalogHarmony()
  if not creature or not creature:isMonster() or not creature:canShoot() or harmony==nil or harmony>=5 or
    modules.game_cooldown.isGroupCooldownIconActive(3) or
    (currentSettings.BlackListSafe and isBlackListedPlayerInRange(currentSettings.AntiRsRange)) or
    (currentSettings.Kills and killsToRs()<=currentSettings.KillsAmount) then return false end
  local support,spenders=nil,false
  for _,child in ipairs(attackEntries(cycle)) do
    local entry=child.params
    if entry.enabled then
      if catalog.normalize(entry.spell)=="utamo tio" then support=entry end
      if AttackRotation.find(entry).harmony=="spender" then spenders=true end
    end
  end
  if not support or not spenders or manapercent()<support.mana then return false end
  local count=0
  for _,spec in pairs(attackSpectators(cycle)) do
    local actor=catalogActor(spec,cycle)
    if actor.monster and not actor.summon and actor.pos and catalog.distance(pos(),actor.pos)<=3 then count=count+1 end
  end
  if not (support.orMore and count>=support.count or not support.orMore and count==support.count) then return false end
  rotationRuntime=rotationRuntime or AttackRotation.newRuntime()
  local spec=AttackRotation.find(support)
  local nativeInfo=attackClientSpellInfo(support.spell)
  if mana()<(nativeInfo and nativeInfo.requirements and nativeInfo.mana or spec.mana) or level()<(nativeInfo and nativeInfo.requirements and nativeInfo.level or spec.level) or
    not AttackRotation.ready(rotationRuntime,support,now,false,nativeInfo~=nil) or not attackSpellReady(support.spell,true) then return false end
  AttackRotation.attempt(rotationRuntime,support.spell,now)
  executeAttackBotAction(4,support.spell,support.cooldown)
  return true
end

-- Preserve explicitly enabled category-4 buffs in custom vocation lists.
local function tryConfiguredSupport(cycle)
  if not AttackRotation or not AttackRotation.supported[currentSettings.selectedVocation] or currentSettings.pvpMode then return false end
  local creature=target()
  if not creature or not creature:isMonster() or not creature:canShoot() or
    (currentSettings.BlackListSafe and isBlackListedPlayerInRange(currentSettings.AntiRsRange)) or
    (currentSettings.Kills and killsToRs()<=currentSettings.KillsAmount) then return false end
  for _,child in ipairs(attackEntries(cycle)) do
    local entry=child.params
    if entry.enabled and entry.category==4 and catalog.normalize(entry.spell)~="utamo tio" and
      catalog.allowed(entry,currentSettings.selectedVocation) and manapercent()>=entry.mana then
      local amount=0
      for _,spec in pairs(attackSpectators(cycle)) do
        local actor=catalogActor(spec,cycle)
        if actor.monster and not actor.summon and actor.pos and catalog.distance(pos(),actor.pos)<=entry.pattern and
          attackEntryMatchesTarget(entry,spec) then amount=amount+1 end
      end
      local nativeInfo=attackClientSpellInfo(entry.spell)
      local data=AttackRotation.find(entry)
      rotationRuntime=rotationRuntime or AttackRotation.newRuntime()
      if (entry.orMore and amount>=entry.count or not entry.orMore and amount==entry.count) and
        (not currentSettings.ignoreMana or level()>=(nativeInfo and nativeInfo.requirements and nativeInfo.level or data.level) and
          mana()>=(nativeInfo and nativeInfo.requirements and nativeInfo.mana or data.mana)) and
        AttackRotation.ready(rotationRuntime,entry,now,nativeInfo and nativeInfo.secondary,nativeInfo~=nil) and
        attackSpellReady(entry.spell,true) then
        AttackRotation.attempt(rotationRuntime,entry.spell,now)
        executeAttackBotAction(4,entry.spell,entry.cooldown)
        return true
      end
    end
  end
  return false
end

-- All five PvE vocations share geometry, conditions and native timing. The
-- automatic mode compares damage and following slots; priority mode follows
-- the user's list without waiting for an unavailable entry.
dofile('/vBot/attack_alignment.lua')
local function tryAdaptiveRotation(cycle, attackCoolingDown)
  local M, creature = AttackRotation, target()
  if not creature or not creature:isMonster() or not creature:canShoot() or
    (currentSettings.BlackListSafe and isBlackListedPlayerInRange(currentSettings.AntiRsRange)) or
    (currentSettings.Kills and killsToRs() <= currentSettings.KillsAmount) then AttackAlignment.reset(true);return end
  rotationRuntime = rotationRuntime or M.newRuntime()
  local entries, actors = {}, {}
  for _,child in ipairs(attackEntries(cycle)) do entries[#entries+1]=child.params end
  for _,spec in pairs(attackSpectators(cycle)) do
    if spec ~= player then
      local actor = catalogActor(spec, cycle)
      actor.shootable = not spec.canShoot or spec:canShoot()
      actor.walking = spec.isWalking and spec:isWalking() or false
      actors[#actors+1]=actor
    end
  end
  local rotationContext = {
    priorityOrder=currentSettings.RotationMode=='priority',
    direction=player:getDirection(), rotate=currentSettings.Rotate, safe=currentSettings.PvpSafe,
    harmony=readCatalogHarmony(), level=level(),
    grenade=function(entry)
      return catalog.bestGrenade(entry,pos(),catalogActor(creature,cycle),actors,currentSettings.PvpSafe,grenadeHistory,now,function(position)
        local key=position.x..":"..position.y..":"..position.z
        if cycle.aimable[key]==nil then
          local tile=g_map.getTile(position)
          cycle.aimable[key]=tile and tile:getGround() and tile:canShoot() or false
        end
        return cycle.aimable[key]
      end)
    end,
    canAim=function(position)
      local key=position.x..":"..position.y..":"..position.z
      if cycle.aimable[key]==nil then
        local tile=g_map.getTile(position)
        cycle.aimable[key]=tile and tile:getGround() and tile:canShoot() or false
      end
      return cycle.aimable[key]
    end,
    timing=function(entry,spec)
      if not catalog.allowed(entry,currentSettings.selectedVocation) or manapercent()<entry.mana then return nil end
      if spec.itemId then
        if currentSettings.OldSchool or currentSettings.Visible then
          if not findItem(spec.itemId) then return nil end
        elseif type(player.getInventoryCount)=="function" then
          -- Native totals include closed backpacks; visible container counts
          -- alone cannot prove that a rune is missing.
          local ok,amount=pcall(player.getInventoryCount,player,spec.itemId,0)
          if ok and tonumber(amount)==0 then return nil end
        end
        -- Runes share the native attack exhaust too. Without this wait a
        -- ready rune steals every future wave/beam while its group is active.
        local groupWait=modules.game_cooldown.isGroupCooldownIconActive(1) and
          (attackGroupReadyAt>now and attackGroupReadyAt-now or 2001) or 0
        local wait=math.max(M.wait(rotationRuntime,entry,now,nil,
          currentSettings.ClientCooldowns and currentSettings.Cooldown),groupWait)
        return {wait=wait,ready=wait==0,cooldown=math.max(2000,entry.cooldown or 2000),lock=2000}
      end
      if spec.aimed and (type(g_game.setNextTalkAim)~="function" or g_game.getClientVersion()<1525) then return nil end
      local nativeInfo=attackClientSpellInfo(entry.spell)
      if currentSettings.ignoreMana and (level()<(nativeInfo and nativeInfo.requirements and nativeInfo.level or spec.level) or
        mana()<(nativeInfo and nativeInfo.requirements and nativeInfo.mana or spec.mana)) then return nil end
      if spec.shield and not getLeft() then return nil end
      local state=attackCatalogState(entry.spell)
      -- Native level/mana and group packets are authoritative on this server.
      local conditions=nativeInfo and nativeInfo.requirements and {ignoreMana=false,Cooldown=currentSettings.Cooldown} or currentSettings
      local ready=M.ready(rotationRuntime,entry,now,nativeInfo and nativeInfo.secondary,nativeInfo~=nil) and
        catalog.ready(entry,conditions,state) and attackSpellReady(entry.spell)
      local wait=M.wait(rotationRuntime,entry,now,nativeInfo and nativeInfo.secondary,nativeInfo~=nil)
      local groups={}
      local lock=spec.lock
      if nativeInfo then
        wait=math.max(wait,attackClientSpellWait(nativeInfo))
        lock=nativeInfo.durations[1] or lock
        for id,duration in pairs(nativeInfo.durations) do
          if tonumber(id) and tonumber(id)>3 and duration and duration>0 then groups['native:'..id]=duration end
        end
      elseif rotationRuntime.confirmed[spec.words] then
        wait=math.max(wait,rotationRuntime.confirmed[spec.words]+(entry.cooldown or spec.cooldown)-now)
      end
      local data=catalog.find(entry.spell)
      if not (nativeInfo and nativeInfo.secondary) then
        if spec.shared then groups[spec.shared]=spec.sharedCd end
        if data and data.secondary and catalogSecondary[data.secondary] then
          wait=math.max(wait,catalogSecondary[data.secondary]+(entry.secondaryCooldown or math.min(entry.cooldown,data.secondaryCooldown))-now)
        end
      end
      if spec.shared then
        -- The game_bot sandbox exposes pairs, but not Lua's global next.
        local hasSharedGroup=false
        for _ in pairs(groups) do hasSharedGroup=true;break end
        if not hasSharedGroup then groups[spec.shared]=spec.sharedCd end
      end
      if catalogAttempts[spec.words] then wait=math.max(wait,catalogAttempts[spec.words]+1000-now) end
      -- Unknown external restrictions cannot be scheduled as a future cast.
      if not ready and wait<=0 and (spec.harmony~='spender' or (state.harmony or 0)>=(entry.minimumHarmony or 5)) then return nil end
      return {wait=math.max(0,wait),ready=ready,cooldown=math.max(100,nativeInfo and nativeInfo.duration or entry.cooldown or spec.cooldown),
        lock=math.max(1000,lock),groups=groups}
    end,
  }
  local prepared=AttackAlignment.update(entries,pos(),catalogActor(creature,cycle),actors,spellPatterns,rotationContext)
  if attackCoolingDown then return end
  local candidates=M.rank(entries,pos(),catalogActor(creature,cycle),actors,spellPatterns,rotationContext)
  if prepared then
    local origin=pos()
    -- update() has revalidated the goal's area, timing and safe route. A rune
    -- at the CURRENT square must not interrupt this bounded movement lease.
    if origin.x~=prepared.position.x or origin.y~=prepared.position.y or
      (player.isWalking and player:isWalking()) then return end
    local reserved={}
    for _,candidate in ipairs(candidates) do
      if candidate.entry==prepared.entry then reserved[#reserved+1]=candidate end
    end
    if #reserved>0 then
      -- Revalidate the actual mask and best facing immediately before firing.
      prepared.direction=reserved[1].direction
      candidates=reserved
    elseif #candidates==0 then return
    else AttackAlignment.reset(false) end
  end
  local directionalSeen={}
  for _,candidate in ipairs(candidates) do
    local entry,spec=candidate.entry,candidate.spec
    local duplicateDirection=candidate.direction~=nil and directionalSeen[entry]
    directionalSeen[entry]=candidate.direction~=nil or directionalSeen[entry]
    local aligned=not duplicateDirection and (candidate.direction==nil or candidate.direction==player:getDirection())
    if not duplicateDirection and not aligned then
      local antitrap=TargetBot and TargetBot.Antitrap
      local movementOwned=antitrap and antitrap.ownsMovement and antitrap.ownsMovement()
      if not movementOwned and (type(turn)=="function" or type(g_game.turn)=="function") then
        -- Reserve the chosen attack until its BEST facing is confirmed. A
        -- lower-scoring direction / filler must not steal the same attack slot.
        AttackAlignment.face(candidate.direction)
        return
      end
    end
    if aligned then
      if spec.itemId then
        local thing=creature
        if candidate.aim then
          local tile=g_map.getTile(candidate.aim)
          thing=tile and tile:getTopUseThing()
        end
        local item=(currentSettings.OldSchool or currentSettings.Visible) and findItem(spec.itemId) or spec.itemId
        if item and thing then
          useWith(item,thing)
          rotationRuntime.itemReadyAt=now+math.max(2000,entry.cooldown)
          rotationRuntime.groupReadyAt=math.max(rotationRuntime.groupReadyAt,now+2000)
          rotationRuntime.sendReadyAt=now+200
          return
        end
      else
        M.attempt(rotationRuntime,entry.spell,now)
        local sent=executeAttackBotAction(entry.category,entry.spell,entry.cooldown,candidate.aim)
        if sent~=false then AttackAlignment.consume(entry);return end
        rotationRuntime.attempts[catalog.normalize(entry.spell)]=nil
      end
    end
  end
end

-- support function covered, now the main loop
macro(100, function()
  AttackAlignment.sync()
  if AttackBot and AttackBot.isPaused and AttackBot.isPaused() then AttackAlignment.reset(true);return end
  if not currentSettings.enabled then AttackAlignment.reset(true);return end
  if player:getHealthPercent()<=0 then
    AttackAlignment.reset(true)
    if rotationRuntime then rotationRuntime.harmony=0;rotationRuntime.harmonyAt=now end
    return
  end
  if #currentSettings.attackTable == 0 or isInPz() then
    AttackAlignment.reset(true)
    if rotationRuntime then rotationRuntime.harmony=0;rotationRuntime.harmonyAt=now end
    grenadeHistory, grenadeScene = {}, nil
    return
  end
  local cycle = {entries=panel.entryList:getChildren(), spectators={}, actors={}, friends={}, aimable={}, evaluations={}}

  -- Observe during the two-second attack cooldown too. Sampling only when a
  -- spell is ready loses the movements and damage needed for the grenade.
  grenadeScene = nil
  for _, child in ipairs(attackEntries(cycle)) do
    if child.params.enabled and (catalog.isDivineGrenade(child.params) or catalog.isDivineEmpowerment(child.params)) then
      grenadeScene = {}
      for _, spec in pairs(attackSpectators(cycle)) do
        if spec ~= player then grenadeScene[#grenadeScene+1] = catalogActor(spec, cycle) end
      end
      cycle.scene = grenadeScene
      catalog.observeGrenade(grenadeHistory, pos(), grenadeScene, now)
      break
    end
  end
  if not grenadeScene then grenadeHistory = {} end
  if not target() then AttackAlignment.reset(true);return end

  if currentSettings.Training and target() and target():getName():lower():find("training") then AttackAlignment.reset(true);return end

  -- Send support on its own tick, without consuming or waiting for an attack
  -- cooldown. The normal damage rotation resumes on the next 100ms tick.
  if tryDivineEmpowerment(cycle) or tryMonkSupport(cycle) or tryConfiguredSupport(cycle) then return end
  local attackCoolingDown=modules.game_cooldown.isGroupCooldownIconActive(1)

  -- Prepare the next wave / beam during the shared cooldown, while TargetBot
  -- owns actual walking and its antitrap keeps precedence over offensive moves.
  if AttackRotation and AttackRotation.supported[currentSettings.selectedVocation] and not currentSettings.pvpMode then
    tryAdaptiveRotation(cycle,attackCoolingDown)
    return
  end
  AttackAlignment.reset(true)
  if attackCoolingDown then return end

  if g_game.getClientVersion() < 960 or not currentSettings.Cooldown then
    delay(400)
  end

  local monstersN = 0
  local monstersE = 0
  local monstersS = 0
  local monstersW = 0
  local needsSides = false
  for _, child in ipairs(attackEntries(cycle)) do
    local entry = child.params
    if entry.enabled and entry.category == 5 and
      (entry.pattern == 8 or currentSettings.Rotate and entry.patternCategory == 4) then needsSides=true;break end
  end
  if needsSides then
    monstersN = getCreaturesInArea(pos(), posN, 2)
    monstersE = getCreaturesInArea(pos(), posE, 2)
    monstersS = getCreaturesInArea(pos(), posS, 2)
    monstersW = getCreaturesInArea(pos(), posW, 2)
  end
  local posTable = {monstersE, monstersN, monstersS, monstersW}
  local bestSide = 0
  local bestDir
  -- pulling out the biggest number
  for i, v in pairs(posTable) do
    if v > bestSide then
        bestSide = v
    end
  end
  -- associate biggest number with turn direction
  if monstersN == bestSide then bestDir = 0
    elseif monstersE == bestSide then bestDir = 1
    elseif monstersS == bestSide then bestDir = 2
    elseif monstersW == bestSide then bestDir = 3
  end

  -- support functions done, main spells now
          --[[
           entry = {
              creatures = creatures,
              monsters = monsters, (formatted creatures)
              mana = mana,
              count = count,
              minHp = minHp,
              maxHp = maxHp,
              cooldown = cooldown,
              itemId = itemId,
              spell = spell,
              enabled = true,
              category = category,
              patternCategory = patternCategory,
              pattern = pattern,
              tooltip = tooltip,
              description = '['..type..'] '..count.. 'x '..specificMonsters..': '..attackType..', '..categoryName..' ('..minHp..'%-'..maxHp..'%)'
          }
          ]]

  for i, child in ipairs(attackEntries(cycle)) do
    local entry = child.params
    local attackData = entry.itemId > 100 and entry.itemId or entry.spell
    local catalogReady = entry.enabled and (not catalog.find(entry.spell) or catalog.ready(entry, currentSettings, attackCatalogState(entry.spell)))
    if entry.enabled and not catalog.isDivineEmpowerment(entry) and catalog.allowed(entry, currentSettings.selectedVocation) and manapercent() >= entry.mana and catalogReady then
      if (type(attackData) == "string" and attackSpellReady(entry.spell)) or (entry.itemId > 100 and (not currentSettings.Visible or findItem(entry.itemId))) then
        -- first PVP scenario
        if entry.category ~= 6 and currentSettings.pvpMode and target():getHealthPercent() >= entry.minHp and target():getHealthPercent() <= entry.maxHp and target():canShoot() then
          if entry.category == 2 then
            return warn("[AttackBot] Area Runes cannot be used in PVP situation!")
          else
            if entry.category == 5 and not prepareDirectionalAttack(entry, bestDir, bestSide, true) then return end
            return executeAttackBotAction(entry.category, attackData, entry.cooldown)
          end
        end
        -- empowerment
        if entry.category == 6 then
          local aimedSpell = catalog.isBarrage(entry) or catalog.isDivineGrenade(entry)
          if (aimedSpell or target():canShoot()) and prepareCatalogAttack(entry) then
            local monsterAmount, unsafe, aimPosition = evaluateCatalogAttack(entry, cycle)
            local countMatches = entry.orMore and monsterAmount >= entry.count or not entry.orMore and monsterAmount == entry.count
            -- Apply the same Anti-RS controls to target areas and chains.
            if countMatches and not unsafe and
              (not currentSettings.BlackListSafe or not isBlackListedPlayerInRange(currentSettings.AntiRsRange)) and
              (not currentSettings.Kills or killsToRs() > currentSettings.KillsAmount) then
              if aimedSpell then
                local minimumCooldown = catalog.isDivineGrenade(entry) and 26000 or 4000
                if aimPosition and executeAttackBotAction(entry.category, attackData, math.max(minimumCooldown, entry.cooldown), aimPosition) then return end
              else
                return executeAttackBotAction(entry.category, attackData, entry.cooldown)
              end
            end
          end
        elseif entry.category == 4 and not isBuffed() then
          local monsterAmount = getMonstersInArea(entry.category, nil, nil, entry.minHp, entry.maxHp, false, entry.monsters, cycle)
          if (entry.orMore and monsterAmount >= entry.count or not entry.orMore and monsterAmount == entry.count) and distanceFromPlayer(target():getPosition()) <= entry.pattern then
            return executeAttackBotAction(entry.category, attackData, entry.cooldown)
          end
        --
        elseif entry.category == 1 or entry.category == 3 then
          local monsterAmount = getMonstersInArea(entry.category, nil, nil, entry.minHp, entry.maxHp, false, entry.monsters, cycle)
          if (entry.orMore and monsterAmount >= entry.count or not entry.orMore and monsterAmount == entry.count) and distanceFromPlayer(target():getPosition()) <= entry.pattern then
            return executeAttackBotAction(entry.category, attackData, entry.cooldown)
          end
        elseif entry.category == 5 then
          local pCat = entry.patternCategory
          local pattern = entry.pattern
          if not prepareDirectionalAttack(entry, bestDir, bestSide) then return end
          local anchorParam = (pattern == 2 or pattern == 6 or pattern == 7 or pattern > 9) and player or pos()
          local safe = currentSettings.PvpSafe and spellPatterns[pCat][entry.pattern][2] or false
          local monsterAmount = pCat ~= 8 and getMonstersInArea(entry.category, anchorParam, spellPatterns[pCat][entry.pattern][1], entry.minHp, entry.maxHp, safe, entry.monsters, cycle)
          if (pattern ~= 8 and (entry.orMore and monsterAmount >= entry.count or not entry.orMore and monsterAmount == entry.count)) or (pattern == 8 and bestSide >= entry.count and (not currentSettings.PvpSafe or not hasUnsafePlayerInAttackBotRange(2, cycle))) then
            if (not currentSettings.BlackListSafe or not isBlackListedPlayerInRange(currentSettings.AntiRsRange)) and (not currentSettings.Kills or killsToRs() > currentSettings.KillsAmount) then
              return executeAttackBotAction(entry.category, attackData, entry.cooldown)
            end
          end
        elseif entry.category == 2 then
          local pCat = entry.patternCategory
          local safe = currentSettings.PvpSafe and spellPatterns[pCat][entry.pattern][2] or false
          local data = getBestTileByPattern(spellPatterns[pCat][entry.pattern][1], entry.minHp, entry.maxHp, safe, entry.monsters, cycle)
          local monsterAmount
          local pos
          if data then
            monsterAmount = data.amount
            pos = data.pos
          end
          if monsterAmount and (entry.orMore and monsterAmount >= entry.count or not entry.orMore and monsterAmount == entry.count) then
            if (not currentSettings.BlackListSafe or not isBlackListedPlayerInRange(currentSettings.AntiRsRange)) and (not currentSettings.Kills or killsToRs() > currentSettings.KillsAmount) then
              return useWith(attackData, g_map.getTile(pos):getTopUseThing())
            end
          end
        end
      end
    end
  end
end)
UI.Separator()
