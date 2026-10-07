-- ==========================================================
-- SuperHealth - perfiles RP / MS-ED / EK
-- ==========================================================
local CFG = {
    items = {
        adrenalina = 11846,
        manaRec    = 11766,
        healthRec  = 11767,
        inmortal   = 12081,
        manaMago   = 238,
        spiritPaly = 7642,
        healthEK   = 7643,
        manaEK     = 268
    },
    cds = {
        recovery    = 30000,
        adrenalina  = 10000,
        inmortal    = 330000,
        potions     = 1600,
        spells      = 1000,
        globalItem  = 2000,
        globalSpell = 1000
    }
}

local panelName = "superHealerAG_Final_V3"
if not storage[panelName] then
    storage[panelName] = { current = "Magos", enabled = true }
end

vBotActiveCDs = vBotActiveCDs or {}
local s = vBotActiveCDs
s.lastSpellCast = s.lastSpellCast or 0
s.pendingStrong = s.pendingStrong or {}
s.pendingPotion = s.pendingPotion or {}
s.lastStrongAttempt = s.lastStrongAttempt or {}
s.lastPotionAttempt = s.lastPotionAttempt or {}
s.strongRetryPause = s.strongRetryPause or {}
s.strongBlockedUntil = s.strongBlockedUntil or 0

-- ==========================================================
-- UI
-- ==========================================================
UI.Separator()
setDefaultTab("Hp")

local ui = setupUI([[
Panel
  height: 40
  margin-top: 2

  BotSwitch
    id: SuperHealth
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: SuperHealth
    height: 18

  Button
    id: Paladin
    anchors.top: SuperHealth.bottom
    anchors.left: parent.left
    margin-top: 3
    width: 42
    height: 17
    text: RP

  Button
    id: Magos
    anchors.top: SuperHealth.bottom
    anchors.left: prev.right
    margin-top: 3
    margin-left: 3
    width: 42
    height: 17
    text: MS/ED

  Button
    id: EK
    anchors.top: SuperHealth.bottom
    anchors.left: prev.right
    anchors.right: parent.right
    margin-top: 3
    margin-left: 3
    height: 17
    text: EK
]])

ui.SuperHealth:setOn(storage[panelName].enabled)
ui.SuperHealth.onClick = function(widget)
    storage[panelName].enabled = not storage[panelName].enabled
    widget:setOn(storage[panelName].enabled)
end

local function updateUI()
    local cur = storage[panelName].current
    ui.Paladin:setColor(cur == "RP" and "green" or "white")
    ui.Magos:setColor(cur == "Magos" and "green" or "white")
    ui.EK:setColor(cur == "EK" and "green" or "white")
end

ui.Paladin.onClick = function() storage[panelName].current = "RP"; updateUI() end
ui.Magos.onClick   = function() storage[panelName].current = "Magos"; updateUI() end
ui.EK.onClick      = function() storage[panelName].current = "EK"; updateUI() end
updateUI()

-- ==========================================================
-- Uso robusto de items
-- ==========================================================
local RETRY = {
    strong = 180,
    potion = 180,
    potionWindow = 900,
    fail = 1400,
    immortalNoDamage = 850,
    strongMaxAttempts = 6,
    recentDamage = 1600
}

local function selfPlayer()
    return player or (g_game and g_game.getLocalPlayer and g_game.getLocalPlayer())
end

local function getUseSubtype(itemId)
    if not g_game or not g_game.getClientVersion then return 0 end
    local thing = g_things and g_things.getThingType and g_things.getThingType(itemId)
    if not thing or not thing:isFluidContainer() then
        return g_game.getClientVersion() >= 860 and 0 or 1
    end
    return 0
end

local function useItemOnSelf(itemId, strongItem)
    local target = selfPlayer()
    if not itemId or not target then return false end

    local subType = getUseSubtype(itemId)

    if g_game and g_game.useInventoryItemWith then
        local ok = pcall(function()
            g_game.useInventoryItemWith(itemId, target, subType)
        end)
        if ok then return true end
    end

    if type(useWith) == "function" then
        local ok = pcall(function()
            useWith(itemId, target, subType)
        end)
        if ok then return true end
    end

    if g_game and g_game.getClientVersion and g_game.getClientVersion() < 780 and g_game.findPlayerItem and g_game.useWith then
        local item = g_game.findPlayerItem(itemId, subType)
        if item then
            local ok = pcall(function()
                g_game.useWith(item, target, subType)
            end)
            if ok then return true end
        end
    end

    if strongItem and findItem and g_game and g_game.useWith then
        local visibleItem = findItem(itemId)
        if not visibleItem then return false end
        local ok = pcall(function()
            g_game.useWith(visibleItem, target, subType)
        end)
        if ok then return true end
    end

    return false
end

local function updateDamageTracker(curHp)
    local t = now
    if not s.lastHpSeen then
        s.lastHpSeen = curHp
        s.lastHpSeenAt = t
        return
    end

    if curHp < s.lastHpSeen then
        s.lastDamageAt = t
        s.lastDamageHp = curHp
    end

    s.lastHpSeen = curHp
    s.lastHpSeenAt = t
end

local function strongConfirmed(p)
    if not p then return false end
    local curHp = hppercent()
    local curMp = manapercent()

    if p.kind == "mana" then
        return curMp >= p.beforeMp + 18 or curMp >= 85
    elseif p.kind == "health" then
        return curHp >= p.beforeHp + 18 or curHp >= 85
    elseif p.kind == "adrenaline" then
        return curHp >= p.beforeHp + 10 or curMp >= p.beforeMp + 10 or curHp >= 80 or curMp >= 80
    elseif p.kind == "inmortal" then
        local noDamageAfterUse = (s.lastDamageAt or 0) <= p.started
        local waitedEnough = now - p.started >= RETRY.immortalNoDamage
        return p.hadRecentDamage and noDamageAfterUse and waitedEnough
    end

    return false
end

local function updateStrongRetries()
    for key, p in pairs(s.pendingStrong) do
        if strongConfirmed(p) then
            s[key] = now
            s.pendingStrong[key] = nil
        elseif now - p.started >= RETRY.fail then
            s.pendingStrong[key] = nil
            s.strongRetryPause[key] = now + 350
        end
    end
end

local function updatePotionRetries()
    for key, p in pairs(s.pendingPotion) do
        if now - p.started >= RETRY.potionWindow then
            s.pendingPotion[key] = nil
        end
    end
end

local function strongAvailable(key, cooldown)
    local t = now
    if t - (s[key] or 0) < cooldown then return false end
    return true
end

local function tryStrong(key, itemId, cooldown, kind)
    local t = now
    if t - (s[key] or 0) < cooldown then return false end
    if t < (s.strongBlockedUntil or 0) then return false end
    if t < (s.strongRetryPause[key] or 0) then return false end

    local pending = s.pendingStrong[key]
    if pending and t - (pending.lastTry or 0) < RETRY.strong then return true end
    if pending and (pending.attempts or 0) >= RETRY.strongMaxAttempts then return true end
    if t - (s.lastStrongAttempt[key] or 0) < RETRY.strong then return true end

    local used = useItemOnSelf(itemId, true)
    if not used then
        s.strongRetryPause[key] = t + 350
        return false
    end

    s.lastStrongAttempt[key] = t
    pending = pending or {
        started = t,
        beforeHp = hppercent(),
        beforeMp = manapercent(),
        kind = kind,
        attempts = 0,
        hadRecentDamage = (s.lastDamageAt or 0) > 0 and t - s.lastDamageAt <= RETRY.recentDamage
    }
    pending.lastTry = t
    pending.attempts = (pending.attempts or 0) + 1
    s.pendingStrong[key] = pending

    if strongConfirmed(pending) then
        s[key] = t
        s.pendingStrong[key] = nil
    end

    return true
end

local function tryPotion(key, itemId)
    local t = now
    local pending = s.pendingPotion[key]
    if pending then
        if t - pending.started >= RETRY.potionWindow then
            s.pendingPotion[key] = nil
        elseif t - (pending.lastTry or 0) < RETRY.potion then
            return true
        else
            local used = useItemOnSelf(itemId, false)
            s.lastPotionAttempt[key] = t
            if used then
                pending.lastTry = t
                pending.attempts = (pending.attempts or 0) + 1
                return true
            end
            return false
        end
    end

    if t - (s[key] or 0) < CFG.cds.potions then return false end
    if t - (s.lastPotionAttempt[key] or 0) < RETRY.potion then return false end

    local used = useItemOnSelf(itemId, false)
    s.lastPotionAttempt[key] = t
    if not used then return false end

    s[key] = t
    s.lastPotionUse = t
    s.strongBlockedUntil = math.max(s.strongBlockedUntil or 0, t + CFG.cds.globalItem)
    s.pendingPotion[key] = {
        started = t,
        lastTry = t,
        attempts = 1
    }
    return true
end

local function castWords(words)
    if type(say) == "function" then
        local ok = pcall(function()
            say(words)
        end)
        if ok then return true end
    end

    if g_game and g_game.talk then
        local ok = pcall(function()
            g_game.talk(words)
        end)
        if ok then return true end
    end

    return false
end

local function trySpell(key, words, manaCost, cooldown)
    local t = now
    if mana() < manaCost then return false end
    if t - (s[key] or 0) < cooldown then return false end
    if t - (s.lastSpellCast or 0) < CFG.cds.globalSpell then return false end

    if not castWords(words) then return false end
    s[key] = t
    s.lastSpellCast = t
    return true
end

-- ==========================================================
-- Prioridades por vocacion
-- ==========================================================
macro(50, function()
    if not storage[panelName].enabled then return end

    local profile = tostring(storage[panelName].current)
    local hp = hppercent()
    local mp = manapercent()
    updateDamageTracker(hp)
    updateStrongRetries()
    updatePotionRetries()

    if profile == "Magos" then
        if hp <= 95 then
            trySpell("m_exura", "exura vita", 160, CFG.cds.spells)
        end

        local holdPotion = false
        if hp <= 45 then
            if tryStrong("m_hrec", CFG.items.healthRec, CFG.cds.recovery, "health") then return end
            if strongAvailable("m_hrec", CFG.cds.recovery) then holdPotion = true end
        end
        if mp <= 25 then
            if tryStrong("m_mrec", CFG.items.manaRec, CFG.cds.recovery, "mana") then return end
            if strongAvailable("m_mrec", CFG.cds.recovery) then holdPotion = true end
        end
        if hp <= 90 and mp <= 30 then
            if tryStrong("m_inmo", CFG.items.inmortal, CFG.cds.inmortal, "inmortal") then return end
            if strongAvailable("m_inmo", CFG.cds.inmortal) then holdPotion = true end
        end

        if mp <= 40 then
            if tryStrong("m_adren", CFG.items.adrenalina, CFG.cds.adrenalina, "adrenaline") then return end
            if strongAvailable("m_adren", CFG.cds.adrenalina) then holdPotion = true end
        end
        if not holdPotion and mp <= 80 and tryPotion("m_mana", CFG.items.manaMago) then return end

    elseif profile == "RP" then
        if hp <= 92 then
            trySpell("p_exura", "exura san", 210, CFG.cds.spells)
        end

        local holdPotion = false
        if hp <= 45 then
            if tryStrong("p_hrec", CFG.items.healthRec, CFG.cds.recovery, "health") then return end
            if strongAvailable("p_hrec", CFG.cds.recovery) then holdPotion = true end
        end
        if mp <= 30 then
            if tryStrong("p_mrec", CFG.items.manaRec, CFG.cds.recovery, "mana") then return end
            if strongAvailable("p_mrec", CFG.cds.recovery) then holdPotion = true end
        end
        if hp <= 40 and mp <= 30 then
            if tryStrong("p_inmo", CFG.items.inmortal, CFG.cds.inmortal, "inmortal") then return end
            if strongAvailable("p_inmo", CFG.cds.inmortal) then holdPotion = true end
        end

        if mp <= 50 then
            if tryStrong("p_adren", CFG.items.adrenalina, CFG.cds.adrenalina, "adrenaline") then return end
            if strongAvailable("p_adren", CFG.cds.adrenalina) then holdPotion = true end
        end
        if not holdPotion and (hp <= 85 or mp <= 85) and tryPotion("p_spirit", CFG.items.spiritPaly) then return end

    elseif profile == "EK" then
        if hp <= 40 then
            trySpell("k_ult", "ultimate tempo", 0, 200000)
        end

        if hp <= 92 then
            trySpell("k_exana", "exana mort", 20, CFG.cds.spells)
        end

        local holdPotion = false
        if hp <= 30 then
            if tryStrong("k_hrec", CFG.items.healthRec, CFG.cds.recovery, "health") then return end
            if strongAvailable("k_hrec", CFG.cds.recovery) then holdPotion = true end
        end
        if mp <= 25 then
            if tryStrong("k_mrec", CFG.items.manaRec, CFG.cds.recovery, "mana") then return end
            if strongAvailable("k_mrec", CFG.cds.recovery) then holdPotion = true end
        end
        if hp <= 40 then
            if tryStrong("k_inmo", CFG.items.inmortal, CFG.cds.inmortal, "inmortal") then return end
            if strongAvailable("k_inmo", CFG.cds.inmortal) then holdPotion = true end
        end

        if not holdPotion and hp <= 80 and tryPotion("k_hpot", CFG.items.healthEK) then return end
        if not holdPotion and mp <= 65 and hp > 85 and tryPotion("k_mpot", CFG.items.manaEK) then return end
    end
end)

UI.Separator()
