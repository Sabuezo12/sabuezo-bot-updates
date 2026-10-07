-- Friend Healer (new_healer.lua) — Versión Reforzada
-- Ajustes principales aplicados:
-- 1) Puerta de auto-protección estricta (HP OR MP).
-- 2) Removido bloqueo global por canShoot.
-- 3) Vocación: lista de bloqueo.
-- 4) Remplazo seguro de 'me = g_game.getLocalPlayer()'.
-- 5) Normalización del nombre al añadir Custom Players.
-- 6) Uso de ítem de cura robusto.
-- 7) Mas Res (radio 3), cálculo inteligente de aliados en rango.
-- 8) Detector interno de vocación por LOOK + regex.
-- 9) Agregado slider independiente para maná de aliados.
-- 10) Ajuste definitivo forzado al hacer clic en Setup sin conflictos de globals.
-- 11) Reorganización visual de la interfaz.

setDefaultTab("Hp")
local panelName = "newHealer"
local ui = setupUI([[
Panel
  height: 19

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('Friend Healer')

  Button
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
-- Add the fifth vocation to existing profiles without resetting their settings.
if config.conditions.monks == nil then config.conditions.monks = true end

local englishTexts = {
    "Item Range: ",
    "Health Item ",
    "Mas Res Players: ",
    "Friend HP < %: ",
    "Gran Sio HP < %: ",
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

ui.title:setOn(config.enabled)
ui.title.onClick = function(widget)
    config.enabled = not config.enabled
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
        ui.title:setOn(false)
    end
}

ui.edit.onClick = function()
    -- Forzamos la altura deseada y usamos nuestra variable local protegida
    if miVentanaNuevaHealer then
        miVentanaNuevaHealer:setHeight(490)
    end
    
    if conditions then
        conditions:setHeight(230)
        if conditions.box then
            conditions.box:setHeight(380)
        end
    end

    miVentanaNuevaHealer:show()
    miVentanaNuevaHealer:raise()
    miVentanaNuevaHealer:focus()
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

for _, index in ipairs(displayOrder) do
    local setting = config.settings[index]
    local widget = UI.createWidget(setting.type, conditions.box)
    
    setting.text = englishTexts[index] or setting.text
    local text, val = setting.text, setting.value
    
    widget.text:setText(text)
    if setting.type == "HealScroll" then
        widget.text:setText(widget.text:getText()..val)
        if not (text:find("Range") or text:find("Mas Res")) then
            widget.text:setText(widget.text:getText().."%")
        end
        widget.scroll:setValue(val)
        widget.scroll.onValueChange = function(_, value)
            setting.value = value
            widget.text:setText(text..value..( (text:find("Range") or text:find("Mas Res")) and "" or "%"))
        end
        if text:find("Range") or text:find("Mas Res") then widget.scroll:setMaximum(10) end
    else
        widget.item:setItemId(val)
        widget.item:setShowCount(false)
        widget.item.onItemChange = function(w) setting.value = w:getItemId() end
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

for _, action in ipairs(config.priorities) do
    local widget = UI.createWidget("PriorityEntry", priority.list)
    
    if action.name == "Hechizo Propio" then action.name = "Custom Spell" end
    if action.name == "Item de Vida" then action.name = "Health Item" end
    if action.name == "Item de Mana" then action.name = "Mana Item" end
    
    widget:setText(action.name)
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
    widget.enabled:setChecked(action.enabled)
    widget:setColor(action.enabled and "#98BF64" or "#dfdfdf")
    widget.enabled.onClick = function()
        action.enabled = not action.enabled
        widget:setColor(action.enabled and "#98BF64" or "#dfdfdf")
        widget.enabled:setChecked(action.enabled)
    end
    if action.custom then
        widget.onDoubleClick = function()
            local window = modules.client_textedit.show(widget, {title = "Custom Spell", description = "Enter below formula for a custom healing spell"})
            schedule(50, function() window:raise(); window:focus() end)
        end
        widget.onTextChange = function(_, text) action.name = text end
        widget:setTooltip("Double click to set spell formula.")
    end
end
setCrementalButtons()

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
    for _, value in pairs(list or {}) do
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

local function isVipFriend(spec)
    if not spec then return false end
    local name = getCreatureName(spec); if not name then return false end
    if isPlayerListFriend(name) then return true end
    local me = g_game.getLocalPlayer(); if not me then return false end
    for _, vip in pairs(g_game.getVips()) do
        if vip[1] == name then
            local icon = tonumber(vip[3]) or 0
            local status = tonumber(vip[2]) or 0
            if icon > 0 or status == 2 then return true end
            return true
        end
    end
    return false
end

local function isGuildMemberOrAlly(spec)
    if not spec then return false end
    local ok, emblem = pcall(function() return spec:getEmblem() end)
    if ok and (emblem == 1 or emblem == 4) then return true end -- 1=ALLY, 4=MEMBER
    return isPlayerListGuild(getCreatureName(spec))
end

-- =========================
-- Cooldowns y Ayudante de Ítems
-- =========================
local lastItemUse, lastStrongHeal, lastMasRes, lastSio = 0, 0, 0, 0

local function tryUseHealItemOn(target, itemId)
    if g_game.useInventoryItemWith then g_game.useInventoryItemWith(itemId, target); return true end
    local it = findItem(itemId); if it then g_game.useWith(it, target); return true end
    return false
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
    if ok and type(voc) == "number" and
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
        if config.conditions.customPlayers and config.customPlayers[nm] then
            return true
        end
        return false
    end
    return true
end

-- =========================
-- Ejecución de las acciones de cura
-- =========================
local function friendHealerAction(spec)
    local me = g_game.getLocalPlayer(); if not me or not spec then return end

    local name   = spec:getName()
    local health = spec:getHealthPercent()
    local mana   = spec:getManaPercent()
    local dist   = distanceFromPlayer(spec:getPosition()) or 99

    local itemRange    = config.settings[1].value      
    local healItem     = config.settings[2].value      
    local masResAmount = config.settings[3].value      
    local normalHeal   = config.customPlayers[name] or config.settings[4].value
    local strongHeal   = config.customPlayers[name] and (normalHeal/2) or config.settings[5].value
    local manaItem     = config.settings[8].value      
    local friendMana   = config.settings[9].value

    for _, action in ipairs(config.priorities) do
        if not action.enabled then goto CONTINUE end

        -- ====== EXURA GRAN MAS RES ======
        if action.area and now > lastMasRes then
            local RADIUS = 3
            local othersNeeding = 0
            local selfNeed = (me:getHealthPercent() <= normalHeal) and 1 or 0

            for _, other in ipairs(getSpectators(posz())) do
                if other ~= me and other:isPlayer() then
                    local otherDist = distanceFromPlayer(other:getPosition()) or 99
                    if otherDist <= RADIUS then
                        local ohp = other:getHealthPercent()
                        local myShield = me:getShield()
                        local oShield  = other:getShield()
                        local inActiveParty = other:isPartyMember() and oShield > 0 and oShield <= 10 and myShield > 0 and myShield <= 10
                        local okParty  = config.conditions.party   and inActiveParty
                        local okFriend = config.conditions.friends and isVipFriend(other)
                        local okGuild  = config.conditions.guild   and isGuildMemberOrAlly(other)
                        local okVoc    = vocationAllowed(other)

                        if okVoc and (okParty or okFriend or okGuild) and ohp <= normalHeal then
                            othersNeeding = othersNeeding + 1
                        end
                    end
                end
            end

            local totalNeeding = selfNeed + othersNeeding
            if totalNeeding >= masResAmount and totalNeeding > 0 then
                if canCast('exura gran mas res', false, true) then
                    lastMasRes = now + 2000
                    return say('exura gran mas res')
                end
            end
        end

        -- *** CURA CON ÍTEM DE MANÁ ***
        if action.mana and mana <= friendMana and dist <= itemRange and (now - lastItemUse) >= 1000 then
            if tryUseHealItemOn(spec, manaItem) then
                lastItemUse = now
                return
            end
        end

        -- *** CURA CON ÍTEM DE HP ***
        if action.health and health <= normalHeal and dist <= itemRange and (now - lastItemUse) >= 1000 then
            if tryUseHealItemOn(spec, healItem) then
                lastItemUse = now
                return
            end
        end

        -- exura gran sio
        if action.strong and health <= strongHeal and now > lastStrongHeal then
            if canCast('exura gran sio', false, true) then
                lastStrongHeal = now + 60000
                return say('exura gran sio "' .. name .. '"')
            end
        end

        -- exura sio
        if (action.normal or action.custom) and health <= normalHeal and now > lastSio then
            if canCast('exura sio', false, true) then
                lastSio = now + 1000
                return say('exura sio "' .. name .. '"')
            end
        end

        ::CONTINUE::
    end
end

-- =========================
-- Selección de candidatos
-- =========================
local function isCandidate(spec)
    if not spec or not spec:isPlayer() or spec:isLocalPlayer() then return nil end

    local name  = spec:getName()
    local curHp = spec:getHealthPercent()
    local curMp = spec:getManaPercent()
    
    local normalHeal = config.customPlayers[name] or config.settings[4].value
    local friendMana = config.settings[9].value

    local needsHp = (curHp <= normalHeal)
    local needsMp = false

    for _, act in ipairs(config.priorities) do
        if act.mana and act.enabled then
            needsMp = (curMp <= friendMana)
            break
        end
    end

    if not needsHp and not needsMp then
        return nil
    end

    local hasRestrictions = not (config.conditions.knights and config.conditions.paladins and
                                 config.conditions.druids and config.conditions.sorcerers and
                                 config.conditions.monks)
    if hasRestrictions then
        local det,isK,isP,isS,isD,isM = detectVocation(spec)
        if det then
            if (isK and not config.conditions.knights) or
               (isP and not config.conditions.paladins) or
               (isS and not config.conditions.sorcerers) or
               (isD and not config.conditions.druids) or
               (isM and not config.conditions.monks) then
                if not (config.conditions.customPlayers and config.customPlayers[name]) then
                    return nil
                end
            end
        end
    end

    local me = g_game.getLocalPlayer(); if not me then return nil end
    local oShield  = spec:getShield()
    local myShield = me:getShield()
    local inActiveParty = spec:isPartyMember() and oShield > 0 and oShield <= 10 and myShield > 0 and myShield <= 10

    local okParty  = config.conditions.party   and inActiveParty
    local okFriend = config.conditions.friends and isVipFriend(spec)
    local okGuild  = config.conditions.guild   and isGuildMemberOrAlly(spec)
    local okCustom = config.conditions.customPlayers and (config.customPlayers[name] ~= nil)

    if not (okParty or okFriend or okGuild or okCustom) then
        return nil
    end

    local scoreHp = okCustom and (curHp/2) or curHp
    local dist    = distanceFromPlayer(spec:getPosition())
    return scoreHp, dist
end

-- =========================
-- Bucle principal (Macro)
-- =========================
macro(100, function()
    if not ui.title:isOn() then return end

    local minHp = config.settings[6].value   -- Pause if MY HP < %
    local minMp = config.settings[7].value   -- Pause if MY MP < %

    if hppercent() <= minHp or manapercent() <= minMp then
        return
    end

    pruneVocCache()

    local healTarget = {creature=nil, hp=101}
    for _, spec in ipairs(getSpectators(posz())) do
        local healthScore, dist = isCandidate(spec)
        if healthScore and dist then
            if healthScore < healTarget.hp then
                healTarget = {creature = spec, hp = healthScore}
            end
        end
    end

    if healTarget.creature then
        return friendHealerAction(healTarget.creature)
    end
end)
