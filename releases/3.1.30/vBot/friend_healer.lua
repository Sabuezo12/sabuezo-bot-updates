-- Friend Healer (new_healer.lua) — Versión Reforzada
-- Ajustes principales aplicados:
-- 1) Puerta de auto-protección estricta (HP OR MP).
-- 2) Removido bloqueo global por canShoot.
-- 3) Vocación: lista de bloqueo.
-- 4) Remplazo seguro de 'me = g_game.getLocalPlayer()'.
-- 5) Normalización del nombre al añadir Custom Players.
-- 6) Uso de ítem de cura robusto.
-- 7) Curas grupales y conteo de aliados en su area.
-- 8) Detector interno de vocación por LOOK + regex.
-- 9) Agregado slider independiente para maná de aliados.
-- 10) Ajuste definitivo forzado al hacer clic en Setup sin conflictos de globals.
-- 11) Reorganización visual de la interfaz.
-- R141: aliados explícitos, veto de enemigos y cura de área sin jugadores ajenos.

setDefaultTab("Hp")
local panelName = "newHealer"
local ui = setupUI([[
Panel
  height: 19

  HelperThemePower
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('Friend Healer')

  HelperThemeButton
    id: edit
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 17
    text: Setup

]])
ui:setId(panelName)

-- =========================
-- Config / Storage por defecto (Con Control de Versiones)
-- =========================
local SCRIPT_VERSION = 2.0

local needsReset = not storage[panelName] or not storage[panelName].priorities or storage[panelName].version ~= SCRIPT_VERSION

if needsReset then
    local savedCustomPlayers = storage[panelName] and storage[panelName].customPlayers or {}
    local savedConditions = storage[panelName] and storage[panelName].conditions or nil

    storage[panelName] = {
        version = SCRIPT_VERSION,
        enabled = false,
        customPlayers = savedCustomPlayers,
        vocations = {},
        groups = {},
        priorities = {
            {name="Custom Spell",           enabled=false, custom=true},
            {name="Exura Gran Sio",         enabled=true,  strong = true},
            {name="Exura Sio",              enabled=true,  normal = true},
            {name="Exura Gran Mas Res",     enabled=true,  area   = true},
            {name="Health Item",            enabled=true,  health = true},
            {name="Mana Item",              enabled=true,  mana   = true},
        },
        settings = {
            {type="HealScroll",     text="Item Range: ",                 value=6},    -- [1]
            {type="HealItem",       text="Health Item ",                 value=3160}, -- [2]
            {type="HealScroll",     text="Mas Res Players: ",            value=2},    -- [3]
            {type="HealScroll",     text="Friend HP < %: ",              value=80},   -- [4]
            {type="HealScroll",     text="Gran Sio HP < %: ",            value=30},   -- [5]
            {type="HealScroll",     text="If MY HP < %: ",               value=90},   -- [6]
            {type="HealScroll",     text="If MY MP < %: ",               value=30},   -- [7]
            {type="HealItem",       text="Mana Item ",                   value=268},  -- [8]
            {type="HealScroll",     text="Friend MP < %: ",              value=50},   -- [9]
        },
        conditions = savedConditions or {
            knights = true,
            paladins = true,
            druids = false,
            sorcerers = false,
            monks = true,
            party = true,
            guild = false,
            friends = false,
            customPlayers = true
        }
    }
end

local config = storage[panelName]
local clientId = HelperClient and HelperClient.id
local thornia = clientId == "thornia"
local nextGen = clientId == "valkaris-ng"
-- Area rows are half-widths by distance from the caster's row, starting at zero.
local vocationSpells = {
    Druid = {
        normal = {label="Exura Sio", words="exura sio", id=84, level=18, mana=120, cooldown=1000, range=7},
        strong = {label="Exura Gran Sio", words="exura gran sio", id=242, level=(thornia or nextGen) and 275 or 300,
            mana=400, cooldown=60000, range=7},
        area = {label="Exura Gran Mas Res", words="exura gran mas res", id=82, level=36, mana=150, cooldown=2000,
            rows={3, 3, 2, 1}}
    },
    Monk = {
        normal = {label="Exura Tio Sio", words="exura tio sio", id=297, level=18, mana=120, cooldown=2000, range=7},
        area = {label="Exura Mas Nia", words="exura mas nia", id=296, level=150, mana=thornia and 400 or 250,
            cooldown=thornia and 12000 or 8000, groupCooldown=nextGen and 2000 or 1000, rows={4, 4, 3, 2, 1}}
    }
}

local function casterVocation()
    local ok, id = pcall(function() return HelperClientCompat.baseVocation(player:getVocation()) end)
    id = ok and tonumber(id) or nil
    if not id or id == 0 then return nil end -- no vocation yet (Rookgaard) or not readable
    return ({[4]="Druid", [14]="Druid", [5]="Monk", [15]="Monk"})[id] or "Other"
end

local function friendSpells()
    return vocationSpells[casterVocation()]
end
-- A new profile whose vocation was not known yet when it was made (a Rookgaard character, for
-- example): Druid and Monk get the Friend Healer on once, the first time the vocation is seen,
-- unless the switch was already used in this profile.
do
    local pending = storage.helperNewProfile
    if type(pending) == "table" and pending.friendHealerByVocation then
        local vocation = casterVocation()
        if vocation then
            if (vocation == "Druid" or vocation == "Monk") and config.enabled ~= true and not pending.friendHealerTouched then
                config.enabled = true
            end
            pending.friendHealerByVocation = nil
        end
    end
end
-- Add the fifth vocation to existing profiles without resetting their settings.
if config.conditions.monks == nil then config.conditions.monks = true end
-- Urgent group healing is on unless the user turned it off.
if config.emergencyMasRes == nil then config.emergencyMasRes = true end

local englishTexts = {
    "Item Range: ",
    "Health Item ",
    "Aliados para area: ",
    "Friend HP: ",
    "Gran Sio HP: ",
    "If MY HP < %: ",
    "If MY MP < %: ",
    "Mana Item ",
    "Friend MP < %: "
}

-- Cambio de nombre a la ventana para evitar colisiones con el script viejo
local miVentanaNuevaHealer = UI.createWindow('FriendHealer')
miVentanaNuevaHealer:hide()
miVentanaNuevaHealer:setId(panelName)

local conditions = miVentanaNuevaHealer.conditions
local targetSettings = miVentanaNuevaHealer.targetSettings
local customList = miVentanaNuevaHealer.customList
local priority = miVentanaNuevaHealer.priority
local refreshSpellLabels

ui.title:setOn(config.enabled)
ui.title.onClick = function(widget)
    config.enabled = not config.enabled
    if type(storage.helperNewProfile) == "table" then storage.helperNewProfile.friendHealerTouched = true end
    widget:setOn(config.enabled)

    if config.enabled then
      local hasRestrictions = not (config.conditions.knights and config.conditions.paladins and
                                   config.conditions.druids and config.conditions.sorcerers and
                                   config.conditions.monks)
      if hasRestrictions then
        storage.extras = storage.extras or {}
        storage.extras.checkPlayer = true
      end
    end
end

-- =======================================================
-- AJUSTE FORZADO EN EL BOTÓN DE SETUP (Solución Anti-Conflictos)
-- =======================================================
FriendHealer = {
    isOn = function()
        return config.enabled == true
    end,
    setOn = function()
        config.enabled = true
        if type(storage.helperNewProfile) == "table" then storage.helperNewProfile.friendHealerTouched = true end
        ui.title:setOn(true)
        local hasRestrictions = not (config.conditions.knights and config.conditions.paladins and
                                     config.conditions.druids and config.conditions.sorcerers and
                                     config.conditions.monks)
        if hasRestrictions then
            storage.extras = storage.extras or {}
            storage.extras.checkPlayer = true
        end
    end,
    setOff = function()
        config.enabled = false
        if type(storage.helperNewProfile) == "table" then storage.helperNewProfile.friendHealerTouched = true end
        ui.title:setOn(false)
    end
}

ui.edit.onClick = function()
    if refreshSpellLabels then refreshSpellLabels() end
    -- Forzamos la altura deseada y usamos nuestra variable local protegida
    if miVentanaNuevaHealer then
        miVentanaNuevaHealer:setHeight(296)
    end
    
    if conditions then
        conditions:setHeight(140)
        if conditions.box then
            conditions.box:setHeight(118)
        end
    end

    miVentanaNuevaHealer:show()
    miVentanaNuevaHealer:raise()
    miVentanaNuevaHealer:focus()
end

-- Keep the stored switch for existing profiles.
local emergencyBox = miVentanaNuevaHealer.emergencyMasRes
if emergencyBox then
    emergencyBox:setChecked(config.emergencyMasRes == true)
    emergencyBox.onClick = function(widget)
        config.emergencyMasRes = not config.emergencyMasRes
        widget:setChecked(config.emergencyMasRes)
    end
    emergencyBox:setTooltip("Con tu HP en 'If MY HP' o menos y al menos un companero de party herido en el area, intenta la cura grupal habilitada de tu vocacion. Respeta el mana y el cooldown.")
end
-- =======================================================

-- =========================
-- Custom Players UI
-- =========================
local function capitalizeFirstLetter(str) return (string.gsub(str, "^%l", string.upper)) end
local function normalizeName(raw)
  local words = string.split(raw or "", " ")
  local parts = {}
  for _, w in ipairs(words) do if w and w:len() > 0 then parts[#parts+1] = capitalizeFirstLetter(w:lower()) end end
  return table.concat(parts, " ")
end

for name, health in pairs(config.customPlayers) do
    local widget = UI.createWidget("HealerPlayerEntry", customList.playerList.list)
    widget.remove.onClick = function() config.customPlayers[name] = nil; widget:destroy() end
    widget:setText("["..health.."%]  "..name)
end

customList.playerList.onDoubleClick = function() customList.playerList:hide() end
local function clearFields()
    customList.addPanel.name:setText("friend name")
    customList.addPanel.health:setText("1")
    customList.playerList:show()
end
customList.addPanel.add.onClick = function()
    local raw = customList.addPanel.name:getText()
    local health = tonumber(customList.addPanel.health:getText())
    local name = normalizeName(raw)
    if not health then clearFields(); return warn("[Friend Healer] Please enter health percent value!") end
    if name:len() == 0 or name:lower() == "friend name" then clearFields(); return warn("[Friend Healer] Please enter friend name to be added!") end
    if config.customPlayers[name] or config.customPlayers[name:lower()] then clearFields(); return warn("[Friend Healer] Player already added to custom list.") end
    config.customPlayers[name] = health
    local widget = UI.createWidget("HealerPlayerEntry", customList.playerList.list)
    widget.remove.onClick = function() config.customPlayers[name] = nil; widget:destroy() end
    widget:setText("["..health.."%]  "..name)
    clearFields()
end

-- =========================
-- Validación visual
-- =========================
local function validate(widget, category)
    local list = widget:getParent()
    local label = list:getParent().title
    category = category or 0
    if category == 2 and storage.extras and storage.extras.checkPlayer == false then
        label:setColor("#d9321f")
        label:setTooltip("! WARNING ! \nTurn on check players in extras to use this feature!")
        return
    else
        label:setColor("#dfdfdf")
        label:setTooltip("")
    end
    local checked = false
    for _, child in ipairs(list:getChildren()) do
        if (category == 1 and child.enabled:isChecked()) or child:isChecked() then checked = true end
    end
    if not checked then
        label:setColor("#d9321f")
        label:setTooltip("! WARNING ! \nNo category selected!")
    else
        label:setColor("#dfdfdf")
        label:setTooltip("")
    end
end

-- =========================
-- Vocaciones / Grupos (UI)
-- =========================
targetSettings.vocations.box.knights:setChecked(config.conditions.knights)
targetSettings.vocations.box.knights.onClick = function(w) config.conditions.knights = not config.conditions.knights; w:setChecked(config.conditions.knights); validate(w, 2) end
targetSettings.vocations.box.paladins:setChecked(config.conditions.paladins)
targetSettings.vocations.box.paladins.onClick = function(w) config.conditions.paladins = not config.conditions.paladins; w:setChecked(config.conditions.paladins); validate(w, 2) end
targetSettings.vocations.box.druids:setChecked(config.conditions.druids)
targetSettings.vocations.box.druids.onClick = function(w) config.conditions.druids = not config.conditions.druids; w:setChecked(config.conditions.druids); validate(w, 2) end
targetSettings.vocations.box.sorcerers:setChecked(config.conditions.sorcerers)
targetSettings.vocations.box.sorcerers.onClick = function(w) config.conditions.sorcerers = not config.conditions.sorcerers; w:setChecked(config.conditions.sorcerers); validate(w, 2) end
if targetSettings.vocations.box.monks then
    targetSettings.vocations.box.monks:setChecked(config.conditions.monks)
    targetSettings.vocations.box.monks.onClick = function(w) config.conditions.monks = not config.conditions.monks; w:setChecked(config.conditions.monks); validate(w, 2) end
end

targetSettings.groups.box.friends:setChecked(config.conditions.friends)
targetSettings.groups.box.friends.onClick = function(w) config.conditions.friends = not config.conditions.friends; w:setChecked(config.conditions.friends); validate(w) end
targetSettings.groups.box.party:setChecked(config.conditions.party)
targetSettings.groups.box.party.onClick   = function(w) config.conditions.party   = not config.conditions.party;   w:setChecked(config.conditions.party);   validate(w) end
targetSettings.groups.box.guild:setChecked(config.conditions.guild)
targetSettings.groups.box.guild.onClick   = function(w) config.conditions.guild   = not config.conditions.guild;   w:setChecked(config.conditions.guild);   validate(w) end
if targetSettings.groups.box.customPlayers then
    targetSettings.groups.box.customPlayers:setChecked(config.conditions.customPlayers)
    targetSettings.groups.box.customPlayers.onClick = function(w) config.conditions.customPlayers = not config.conditions.customPlayers; w:setChecked(config.conditions.customPlayers); validate(w) end
end
targetSettings.groups.box.botserver:hide()

validate(targetSettings.vocations.box.knights)
validate(targetSettings.groups.box.friends)
validate(targetSettings.vocations.box.sorcerers, 2)

-- =========================
-- Ajustes (Sliders e ítems) CON ORDEN PERSONALIZADO
-- =========================
local displayOrder = {
    2, -- Health Item
    8, -- Mana Item
    4, -- Friend HP
    9, -- Friend MP
    5, -- Gran Sio
    3, -- Mas Res Players
    6, -- Pause if MY HP
    7, -- Pause if MY MP
    1  -- Item Range (Al final)
}

local settingTips = {
    [3] = "Companeros de party heridos que deben estar dentro del area. La cura urgente requiere al menos uno.",
    [4] = "HP para la cura individual normal y para contar aliados en el area. La lista personalizada puede fijar otro HP por aliado.",
    [5] = "HP maximo del aliado para lanzar Exura Gran Sio, tambien en la lista personalizada.",
    [6] = "Con tu HP en este porcentaje o menos, HealBot tiene prioridad. La cura grupal urgente puede curarte a ti y a un aliado.",
    [7] = "Con tu mana en este porcentaje o menos, se pausa Friend Healer, incluida la cura grupal urgente."
}

for _, index in ipairs(displayOrder) do
    local setting = config.settings[index]
    local widget = UI.createWidget(setting.type, conditions.box)

    setting.text = englishTexts[index] or setting.text
    local text, val = setting.text, setting.value

    widget.text:setText(text)
    if settingTips[index] then widget:setTooltip(settingTips[index]) end
    if setting.type == "HealScroll" then
        widget.text:setText(widget.text:getText()..val)
        local countSetting = index == 1 or index == 3
        if not countSetting then
            widget.text:setText(widget.text:getText().."%")
        end
        widget.scroll:setValue(val)
        widget.scroll.onValueChange = function(_, value)
            setting.value = value
            widget.text:setText(text..value..(countSetting and "" or "%"))
        end
        if countSetting then widget.scroll:setMaximum(10) end
    else
        HelperClientCompat.setItemIdForDisplay(widget.item,val)
        widget.item:setShowCount(false)
        widget.item.onItemChange = function(w) setting.value = HelperClientCompat.itemIdFromWidget(w) end
    end
end

-- =========================
-- Prioridades (UI)
-- =========================
local function setCrementalButtons()
    local children = priority.list:getChildren()
    local last = #children
    for i, child in ipairs(children) do
        if i == 1 then child.increment:disable(); child.decrement:enable()
        elseif i == last then child.increment:enable(); child.decrement:disable()
        else child.increment:enable(); child.decrement:enable() end
    end
end

local spellWidgets = {}
for _, action in ipairs(config.priorities) do
    local widget = UI.createWidget("PriorityEntry", priority.list)
    
    if action.name == "Hechizo Propio" then action.name = "Custom Spell" end
    if action.name == "Item de Vida" then action.name = "Health Item" end
    if action.name == "Item de Mana" then action.name = "Mana Item" end
    
    widget:setText(action.name)
    local role = action.strong and "strong" or action.normal and "normal" or action.area and "area"
    if role then spellWidgets[role] = {widget = widget, action = action} end
    widget.increment.onClick = function()
        local index = priority.list:getChildIndex(widget)
        local t = config.priorities
        priority.list:moveChildToIndex(widget, index-1)
        t[index], t[index-1] = t[index-1], t[index]
        setCrementalButtons()
    end
    widget.decrement.onClick = function()
        local index = priority.list:getChildIndex(widget)
        local t = config.priorities
        priority.list:moveChildToIndex(widget, index+1)
        t[index], t[index+1] = t[index+1], t[index]
        setCrementalButtons()
    end
    widget.enabled:setChecked(action.enabled == true)
    widget:setColor(action.enabled and "#98BF64" or "#dfdfdf")
    widget.enabled.onCheckChange = function(_, checked)
        action.enabled = checked == true
        widget:setColor(action.enabled and "#98BF64" or "#dfdfdf")
        if type(saveConfig) == "function" then saveConfig() end
    end
    if action.custom then
        widget.onDoubleClick = function()
            local window = (Helper and Helper.editText or modules.client_textedit.show)(widget, {title = "Custom Spell", description = "Enter below formula for a custom healing spell"})
            schedule(50, function() window:raise(); window:focus() end)
        end
        widget.onTextChange = function(_, text) action.name = text end
        widget:setTooltip("Double click to set spell formula.")
    end
end
setCrementalButtons()

refreshSpellLabels = function()
    local spells = friendSpells()
    for role, row in pairs(spellWidgets) do
        local spell = spells and spells[role]
        local label = spell and spell.label or row.action.name
        if not spell and role == "strong" then label = "Gran Sio (solo Druid)" end
        row.widget:setText(label)
        row.widget:setTooltip(spell and "" or "Hechizo de otra vocacion. La casilla guarda tu preferencia.")
    end
end
refreshSpellLabels()
-- =========================
-- Ayudantes (grupos)
-- =========================
local function normalizeFriendName(name)
    return tostring(name or ""):gsub("^%s*(.-)%s*$", "%1"):lower()
end

local function getCreatureName(spec)
    if not spec then return nil end
    local ok, name = pcall(function() return spec:getName() end)
    return ok and name or nil
end

local function isNameInList(list, name)
    local key = normalizeFriendName(name)
    if key == "" or type(list) ~= "table" then return false end
    for _, value in pairs(list) do
        if normalizeFriendName(value) == key then return true end
    end
    return false
end

local function isPlayerListFriend(name)
    if PlayerList and PlayerList.isFriend then
        local ok, result = pcall(function() return PlayerList.isFriend(name) end)
        if ok and result then return true end
    end

    local cfg = storage.playerList
    return cfg and isNameInList(cfg.friendList, name)
end

local function isPlayerListGuild(name)
    if PlayerList and PlayerList.isGuildMember then
        local ok, result = pcall(function() return PlayerList.isGuildMember(name) end)
        if ok and result then return true end
    end

    local cfg = storage.playerList
    local key = normalizeFriendName(name)
    return cfg and cfg.guildMembers and cfg.guildMembers[key] == true
end

-- VIP is an online/contact list, not an authorization to heal.
local function customPlayerHP(name)
    local key = normalizeFriendName(name)
    for playerName, value in pairs(config.customPlayers) do
        if normalizeFriendName(playerName) == key then return tonumber(value) end
    end
end

local function isHostilePlayer(spec, name)
    local lists = storage.playerList or {}
    if isNameInList(lists.enemyList, name) or isNameInList(lists.blackList, name) then return true end
    -- Read live hostility before any positive group, without the shared friend cache.
    if spec.getEmblem then
        local ok, emblem = pcall(function() return spec:getEmblem() end)
        if not ok or emblem == 2 then return true end
    end
    if spec.isTimedSquareVisible then
        local ok, attacking = pcall(function() return spec:isTimedSquareVisible() end)
        if not ok or attacking then return true end
    end
    if g_game.getAttackingCreature then
        local ok, attacked = pcall(g_game.getAttackingCreature)
        if not ok then return true end
        if attacked and (attacked == spec or normalizeFriendName(getCreatureName(attacked)) == normalizeFriendName(name)) then return true end
    end
    return false
end

local function isGuildMemberOrAlly(spec)
    if not spec then return false end
    local ok, emblem = pcall(function() return spec:getEmblem() end)
    if ok and (emblem == 1 or emblem == 4) then return true end -- 1=ALLY, 4=MEMBER
    return isPlayerListGuild(getCreatureName(spec))
end

-- Positive membership is separate from vocation filters: an excluded vocation
-- remains an ally for area safety, but does not count as a heal candidate.
local function isHealingAlly(spec)
    local me = g_game.getLocalPlayer()
    if not me or not spec or not spec:isPlayer() or spec:isLocalPlayer() or spec:getHealthPercent() <= 0 then return false end
    local name = getCreatureName(spec)
    local position, mine = spec:getPosition(), me:getPosition()
    if normalizeFriendName(name) == "" or not position or not mine or position.z ~= mine.z or isHostilePlayer(spec, name) then return false end
    local myShield, otherShield = me:getShield(), spec:getShield()
    local party = config.conditions.party and spec:isPartyMember() and
        myShield > 0 and myShield <= 10 and otherShield > 0 and otherShield <= 10
    return party or
        (config.conditions.friends and isPlayerListFriend(name)) or
        (config.conditions.guild and isGuildMemberOrAlly(spec)) or
        (config.conditions.customPlayers and customPlayerHP(name) ~= nil) or false
end

targetSettings.groups.box.friends:setTooltip("Solo amigos de Player List. La lista VIP no autoriza curaciones. Enemigos y jugadores hostiles tienen prioridad de exclusion.")
if targetSettings.groups.box.customPlayers then
    targetSettings.groups.box.customPlayers:setTooltip("Lista personalizada de aliados; no permite curar enemigos ni jugadores hostiles.")
end

-- =========================
-- Cooldowns y Ayudante de Ítems
-- =========================
local lastItemUse = 0

local function tryUseHealItemOn(target, itemId)
    -- Revalidate at the actual item boundary, including after a cooperative grant.
    if not ui.title:isOn() or not isHealingAlly(target) then return false end
    if g_game.useInventoryItemWith then
        local ok, result = pcall(g_game.useInventoryItemWith, itemId, target)
        return ok and result ~= false
    end
    local it = findItem(itemId)
    if it then
        local ok, result = pcall(g_game.useWith, it, target)
        return ok and result ~= false
    end
    return false
end

-- Cooperate only at this script's item boundary; protective equipment/spells stay independent.
local native_tryUseHealItemOn=tryUseHealItemOn
tryUseHealItemOn=function(target, itemId)
  if PushMax and type(PushMax.performItem)=='function'then
    return PushMax.performItem('Friend Healer',itemId,target and target.getHealthPercent and target:getHealthPercent()<=60 and 'urgent'or true,native_tryUseHealItemOn,target, itemId)
  end
  return native_tryUseHealItemOn(target, itemId)
end

-- ==================================================================
-- *** Detector interno de vocación ***
-- ==================================================================
local INTERNAL_VOC_DETECT = true
local vocCache = {}     
local lastLookAt = 0
local LOOK_PERIOD = 800
local LOOK_RETRY_PERIOD = 5000
local SUPPRESS_WINDOW = 600 
local VOC_CACHE_TTL = 30 * 60 * 1000
local MAX_VOC_CACHE = 150
local lastVocCacheCleanup = 0
local pendingLooks = {}

local function pruneVocCache(force)
    if not force and now - lastVocCacheCleanup < 60 * 1000 then return end
    lastVocCacheCleanup = now

    local count = 0
    for name, data in pairs(vocCache) do
        count = count + 1
        if not data.ts or now - data.ts > VOC_CACHE_TTL then
            vocCache[name] = nil
            pendingLooks[name] = nil
            count = count - 1
        end
    end

    if count <= MAX_VOC_CACHE then return end
    for name, _ in pairs(vocCache) do
        vocCache[name] = nil
        count = count - 1
        if count <= MAX_VOC_CACHE then break end
    end

    for name, ts in pairs(pendingLooks) do
        if now - ts > LOOK_RETRY_PERIOD then
            pendingLooks[name] = nil
        end
    end
end

local lookRegex = [[You see ([^\(]*) \(Level ([0-9]*)\)((?:.)* of the ([\w ]*),|)]]

local lastLookMessageAt = 0
onTextMessage(function(mode, text)
    if not INTERNAL_VOC_DETECT then return end
    local re = regexMatch(text, lookRegex)
    if #re ~= 0 then
        local name = re[1][2]
        local low = text:lower()
        local ek = low:find("knight") ~= nil
        local rp = low:find("paladin") ~= nil
        local ms = low:find("sorcerer") ~= nil or low:find("mage") ~= nil
        local ed = low:find("druid") ~= nil
        local mk = low:find("monk") ~= nil
        vocCache[name] = {isKnight=ek, isPaladin=rp, isSorcerer=ms, isDruid=ed, isMonk=mk, ts=now}
        pendingLooks[name] = nil
        pruneVocCache()
        local internalLook = now - lastLookAt <= SUPPRESS_WINDOW
        lastLookMessageAt = now
        if internalLook and modules.game_textmessage and modules.game_textmessage.clearMessages then
            modules.game_textmessage.clearMessages()
        end
    end
end)

local function queueLook(spec)
    if not INTERNAL_VOC_DETECT then return end
    local nm = spec:getName()
    if pendingLooks[nm] and now - pendingLooks[nm] < LOOK_RETRY_PERIOD then return end
    if now - lastLookAt < LOOK_PERIOD then return end
    pendingLooks[nm] = now
    lastLookAt = now
    g_game.look(spec, true)  
end

local function detectVocation(spec)
    local ok, voc = pcall(function() return spec:getVocation() end)
    if ok then voc=HelperClientCompat.baseVocation(voc) end
    if ok and type(voc) == "number" and voc%1==0 and
       ((voc >= 1 and voc <= 5) or (voc >= 11 and voc <= 15)) then
        return true,
          (voc==1 or voc==11),(voc==2 or voc==12),(voc==3 or voc==13),
          (voc==4 or voc==14),(voc==5 or voc==15)
    end
    local nm = spec:getName()
    if PlayerList and type(PlayerList.getVocation) == "function" then
        local storedOk, stored = pcall(PlayerList.getVocation, nm)
        if storedOk and (stored == "knight" or stored == "paladin" or stored == "sorcerer" or
                         stored == "druid" or stored == "monk") then
            return true, stored == "knight", stored == "paladin", stored == "sorcerer",
              stored == "druid", stored == "monk"
        end
    end
    local cached = vocCache[nm]
    if cached then
        return true, cached.isKnight, cached.isPaladin, cached.isSorcerer, cached.isDruid, cached.isMonk
    end
    queueLook(spec)
    return false
end

local function vocationAllowed(spec)
    local allOn = (config.conditions.knights and config.conditions.paladins and
                   config.conditions.druids and config.conditions.sorcerers and
                   config.conditions.monks)
    if allOn then return true end
    local det,isK,isP,isS,isD,isM = detectVocation(spec)
    if not det then return true end 
    if (isK and not config.conditions.knights) or
       (isP and not config.conditions.paladins) or
       (isS and not config.conditions.sorcerers) or
       (isD and not config.conditions.druids) or
       (isM and not config.conditions.monks) then
        local nm = spec:getName()
        if config.conditions.customPlayers and customPlayerHP(nm) ~= nil then
            return true
        end
        return false
    end
    return true
end

-- =========================
-- Alcance y seleccion de aliados
-- =========================
local function healingScene()
    local me = g_game.getLocalPlayer()
    local mine = me and me:getPosition()
    if not mine then return end
    local specs = g_map and g_map.getSpectatorsInRange and g_map.getSpectatorsInRange(mine, false, 7, 7)
    return {me = me, position = mine, spectators = specs or getSpectators()}
end

local function hasPartyShield(creature)
    local shield = tonumber(creature:getShield())
    return shield and shield >= 3 and shield <= 10
end

local function areaHealCount(scene, spell)
    if not scene or not config.conditions.party or not hasPartyShield(scene.me) then return 0 end
    local mine = scene.position
    local low = 0
    for _, other in ipairs(scene.spectators) do
        if other ~= scene.me and other:isPlayer() and not other:isLocalPlayer() then
            local position = other:getPosition()
            if not position then return nil end
            local halfWidth = spell.rows[math.abs(position.y - mine.y) + 1]
            if position.z == mine.z and halfWidth and math.abs(position.x - mine.x) <= halfWidth then
                if not isHealingAlly(other) then return nil end
                if hasPartyShield(other) and other:isPartyMember() then
                    local threshold = customPlayerHP(other:getName()) or config.settings[4].value
                    if other:getHealthPercent() <= threshold and vocationAllowed(other) then low = low + 1 end
                end
            end
        end
    end
    return low
end

-- HealBot uses the same area and party check for group spells in its own rules.
function FriendHealer.hasAreaHealTarget(words)
    local spells = friendSpells()
    local area = spells and spells.area
    return area and area.words == words and (areaHealCount(healingScene(), area) or 0) >= 1
end

local function healingCandidates(scene)
    local candidates = {}
    local mine = scene.position
    for _, spec in ipairs(scene.spectators) do
        if isHealingAlly(spec) then
            local position = spec:getPosition()
            local name, hp = spec:getName(), spec:getHealthPercent()
            local customHP = customPlayerHP(name)
            local normal = hp <= (customHP or config.settings[4].value)
            local strong = hp <= config.settings[5].value
            local mp = tonumber(spec:getManaPercent())
            local needsMana = mp and mp <= config.settings[9].value
            if (normal or strong or needsMana) and vocationAllowed(spec) then
                candidates[#candidates + 1] = {
                    creature = spec, name = name, score = customHP and hp / 2 or hp,
                    distance = math.max(math.abs(position.x - mine.x), math.abs(position.y - mine.y)),
                    normal = normal, strong = strong, mana = needsMana
                }
            end
        end
    end
    return candidates
end

local function chooseAlly(candidates, need, range, requireSight)
    local best
    for _, ally in ipairs(candidates) do
        if ally[need] and ally.distance <= range and
            (not best or ally.score < best.score or ally.score == best.score and ally.distance < best.distance) then
            if not requireSight or not ally.creature.canShoot or ally.creature:canShoot() then best = ally end
        end
    end
    return best
end

-- =========================
-- Requisitos y cooldowns
-- =========================
local HEALING_GROUP = 2
local spellDeadline, groupDeadline, staleSince = {}, {}, {}
local spellStates, spellDataCache = {}, {}
local castUntil, urgentUntil = 0, 0
local observesSpellCooldown = type(onSpellCooldown) == "function"

local function consoleLog(level, message, detail)
    if type(RinoConsole) ~= "table" or type(RinoConsole.valid) ~= "function" then return end
    local ok, valid = pcall(RinoConsole.valid)
    if ok and valid then pcall(RinoConsole.log, level, "Friend Healer", message, detail) end
end

local function spellData(spell)
    local cached = spellDataCache[spell.words]
    if cached and now < cached.untilAt then return cached.data end
    local data
    if type(getSpellData) == "function" then
        local ok, native = pcall(getSpellData, spell.words)
        if ok and type(native) == "table" and native.words == spell.words then data = native end
    end
    spellDataCache[spell.words] = {data = data, untilAt = now + 1000}
    return data
end

if observesSpellCooldown then
    onSpellCooldown(function(id, duration)
        id, duration = tonumber(id), tonumber(duration)
        if not id or not duration then return end
        spellDeadline[id] = now + math.max(0, duration)
        for _, state in pairs(spellStates) do
            if state.id == id then
                if state.pendingUntil and now >= (groupDeadline[HEALING_GROUP] or 0) then
                    groupDeadline[HEALING_GROUP] = now + state.groupCooldown
                end
                state.pendingUntil, state.retryAt, state.misses = nil, 0, 0
            end
        end
    end)
end

if type(onGroupSpellCooldown) == "function" then
    onGroupSpellCooldown(function(id, duration)
        id, duration = tonumber(id), tonumber(duration)
        if id and duration then groupDeadline[id] = now + math.max(0, duration) end
    end)
end

local function cooldownActive(key, readIcon, id, deadline, expected)
    if deadline then return now < deadline end
    if type(readIcon) ~= "function" then return false end
    local ok, active = pcall(readIcon, id)
    if not ok or active ~= true then staleSince[key] = nil; return false end
    staleSince[key] = staleSince[key] or now
    return now - staleSince[key] < math.max(300, tonumber(expected) or 1000)
end

local function spellReady(spell)
    if now < castUntil then return false end
    local data = spellData(spell)
    local id = data and tonumber(data.id) or spell.id
    local state = spellStates[spell.words]
    local cd = modules and modules.game_cooldown
    local selfCd = spell.cooldown
    if state and state.pendingUntil then
        if now < state.pendingUntil then return false end
        state.pendingUntil = nil
        state.misses = state.misses + 1
        state.retryAt = now + math.min(10000, 2000 * state.misses)
        consoleLog("warn", spell.label .. " sin confirmacion", "Reintento en " .. math.floor((state.retryAt - now) / 1000) .. " s.")
    end
    if state and now < state.retryAt then return false end

    -- Thornia and Next Gen publish these requirements in their spell archives.
    -- Other clients can provide their own through the native spell table.
    local requiredLevel, requiredMana = spell.level, spell.mana
    if data and not thornia and not nextGen then
        requiredLevel = tonumber(data.level) or requiredLevel
        requiredMana = tonumber(data.mana) or requiredMana
        selfCd = tonumber(data.exhaustion) or selfCd
    end
    if level() < requiredLevel or mana() < requiredMana then return false end
    if cooldownActive("spell:" .. id, cd and cd.isCooldownIconActive, id, spellDeadline[id], selfCd) then return false end

    local groups = data and data.group
    if type(groups) == "table" then
        for key, cooldown in pairs(groups) do
            local group = tonumber(key)
            if group and group ~= HEALING_GROUP and cooldownActive("group:" .. group,
                cd and cd.isGroupCooldownIconActive, group, groupDeadline[group], cooldown) then return false end
        end
    end
    if cooldownActive("group:" .. HEALING_GROUP, cd and cd.isGroupCooldownIconActive, HEALING_GROUP,
        groupDeadline[HEALING_GROUP], spell.groupCooldown or 1000) then return false end
    return true, id, selfCd
end

local function sendFriendSpell(spell, id, cooldown, ally, urgent)
    local state = spellStates[spell.words] or {misses = 0, retryAt = 0}
    spellStates[spell.words] = state
    state.id = id
    state.groupCooldown = spell.groupCooldown or 1000
    if observesSpellCooldown then state.pendingUntil = now + 1500 end
    castUntil = now + 450
    local words = ally and (spell.words .. ' "' .. ally.name .. '"') or spell.words
    local ok, result = pcall(say, words)
    if not ok or result == false then
        castUntil, state.pendingUntil, state.retryAt = 0, nil, now + 500
        return false
    end
    if not observesSpellCooldown then
        spellDeadline[id] = now + cooldown
        groupDeadline[HEALING_GROUP] = now + state.groupCooldown
    end
    if urgent then urgentUntil = castUntil end
    if spell.rows or spell == vocationSpells.Druid.strong then
        consoleLog("action", spell.label .. (urgent and " urgente" or ""), ally and ally.name)
    end
    return true
end

local function areaPriorityEnabled()
    for _, action in ipairs(config.priorities) do
        if action.area then return action.enabled == true end
    end
    return false
end

-- =========================
-- Cura grupal urgente
-- =========================
local emergencyCache = {at = -1}
local function urgentArea()
    if not config.emergencyMasRes or hppercent() > config.settings[6].value or
        manapercent() <= config.settings[7].value or not areaPriorityEnabled() then return end
    local spells = friendSpells()
    if not spells then return end
    local area = spells.area
    if emergencyCache.at ~= now or emergencyCache.spell ~= area then
        emergencyCache.at, emergencyCache.spell = now, area
        emergencyCache.low = areaHealCount(healingScene(), area)
    end
    if emergencyCache.low and emergencyCache.low >= 1 then return area end
end

local function tryUrgentArea()
    local spell = urgentArea()
    if not spell then return false end
    local ready, id, cooldown = spellReady(spell)
    return ready and sendFriendSpell(spell, id, cooldown, nil, true) or false
end

-- Only HealBot's spells yield for an urgent group heal.
local HOLD_MAX, HOLD_PAUSE = 700, 2000
local holdSince, holdPausedUntil = nil, 0
FriendHealer.holdsPriority = function()
    if not ui.title:isOn() or not config.emergencyMasRes then holdSince = nil; return false end
    if now < holdPausedUntil then return false end
    local spell = urgentArea()
    if not spell or (now >= urgentUntil and not spellReady(spell)) then holdSince = nil; return false end
    holdSince = holdSince or now
    if now - holdSince > HOLD_MAX then
        holdSince, holdPausedUntil = nil, now + HOLD_PAUSE
        return false
    end
    return true
end

-- =========================
-- Bucle principal
-- =========================
local function tryDirectedHeal(candidates, kind, spell)
    if not spell then return false end
    local ally = chooseAlly(candidates, kind, spell.range, true)
    if not ally then return false end
    local ready, id, cooldown = spellReady(spell)
    return ready and sendFriendSpell(spell, id, cooldown, ally) or false
end

macro(100, function()
    if not ui.title:isOn() then return end
    if tryUrgentArea() then return end
    if hppercent() <= config.settings[6].value or manapercent() <= config.settings[7].value then return end

    pruneVocCache()
    local scene = healingScene()
    if not scene then return end
    local spells = friendSpells()
    local candidates = healingCandidates(scene)
    local areaPending = spells and areaPriorityEnabled()

    for _, action in ipairs(config.priorities) do
        if action.enabled then
            if action.strong and spells and tryDirectedHeal(candidates, "strong", spells.strong) then return end

            if action.area or action.normal or action.custom then
                -- A qualifying group heal takes precedence over the basic targeted heal.
                if areaPending then
                    areaPending = false
                    local area = spells.area
                    local ready, id, cooldown = spellReady(area)
                    if ready then
                        local low = areaHealCount(scene, area)
                        if low and low >= math.max(1, config.settings[3].value) and sendFriendSpell(area, id, cooldown) then return end
                    end
                end
                if (action.normal or action.custom) and spells and tryDirectedHeal(candidates, "normal", spells.normal) then return end
            end

            if (action.mana or action.health) and now - lastItemUse >= 1000 then
                local ally = chooseAlly(candidates, action.mana and "mana" or "normal", config.settings[1].value)
                local item = config.settings[action.mana and 8 or 2].value
                if ally and tryUseHealItemOn(ally.creature, item) then
                    lastItemUse = now
                    return
                end
            end
        end
    end
end)

local lastHandlerErrorAt = -100000
if type(onPlayerHealthChange) == "function" then
    onPlayerHealthChange(function()
        if not ui.title:isOn() or not config.emergencyMasRes then return end
        emergencyCache.at = -1
        local ok, err = pcall(tryUrgentArea)
        if not ok and now - lastHandlerErrorAt > 10000 then
            lastHandlerErrorAt = now
            consoleLog("error", "Cura grupal urgente: " .. tostring(err))
        end
    end)
end
