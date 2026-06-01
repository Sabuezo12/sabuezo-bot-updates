-- ==========================================================
-- 1. CONFIGURACIÓN Y BASE DE DATOS
-- ==========================================================
local panelName = "GuildBuff"
setDefaultTab("Tools") 

if not storage[panelName] then
    storage[panelName] = {
        boostEnabled = true,
        hasteEnabled = false,
        tempoEnabled = false,
        manaStop = 30
    }
end

local config = storage[panelName]
if config.simplifiedVersion ~= 24 then
    config.boostEnabled = true
    config.simplifiedVersion = 24
end
if config.boostEnabled == nil then config.boostEnabled = true end
config.vorEnabled = nil
if config.hasteEnabled and config.tempoEnabled then config.hasteEnabled = false end
config.manaStop = tonumber(config.manaStop) or 30

-- 🔥 BASE DE DATOS DE LA GUILD (Modo Estricto) 🔥
local guildLists = {
    
    paladin = {
        "zestor", "decidueye", "mara", "sabuezo", "zaamy tank", "zesttop", 
        "ya lloroooooooo", "obscuram mors", "winkle blaze", "salo pushmax", 
        "rotsez", "super man", "hot starfire", "arterster", "pitofo", "zerocx", 
        "mueble o algo", "always army", "kata", "david of skalibur", "gunslinger", 
        "shadowbolt", "don pamfilo", "sweet dram", "guardian azteca", "chuhco'de rush", 
        "nfkvbdfjk", "relaxado do salo", "blunt de mole"
    },

    knight = {
        "menblack", "valente alfaro", "lord gastly", "godhammer", "nvsta", 
        "secret", "kaelthar el silencios", "aeron knight", "zestop", "zesttor", 
        "the best", "gt king", "picachu", "fallen", "kakalaxe cp", "cristobal culon", 
        "tommy shelby", "desquiciado", "teniente herrada", "dumbo", "buap", 
        "mighty mask", "deivid forthe win", "simba", "knight onpazzur", "eresmiperra", 
        "chucho'do rush"
    },

    sorcerer = {
        "suden death", "interfernal", "headhunter", "incineratus", "gm fierrov", 
        "panfilo", "mordisquito", "ertrex mage", "shackk soulfs", "infernia", 
        "wicked claws", "bat man", "delorian", "daenerys targaryen", "kleiton", 
        "oficina salo", "mystic", "blueberry yum yum", "nenez", "gravidade", 
        "bubba", "vinz demonslayer", "agness", "carlos abdiel", "matanobs", 
        "chucho'da rush", "mesfarif", "salo blindado"
    },

    druid = {
        "meowscarada", "jerome valeska", "morgan blood", "forge", "daniiell te", 
        "soraka", "dissaster", "sir enzo", "corrupted blade", "kevin costner", 
        "my boo", "operativa salo", "rod master", "persefone", "rom baron", 
        "kiara", "inmortal", "chucho'di rush"
    }
}

if PlayerList and PlayerList.importVocations then
    PlayerList.importVocations(guildLists)
    if PlayerList.autoAddVisibleGuildMembers then
        PlayerList.autoAddVisibleGuildMembers()
    end
end

-- COOLDOWNS INDIVIDUALES 
local cdBoost = 11000
local cdHaste = 4000
local cdTempo = 3000

-- COOLDOWNS GLOBALES 
local globalCdBoost = 2000
local globalCdSpeed = 2000 

local lastGlobalBoost = 0
local lastGlobalSpeed = 0 

local lastCastBoost = {}
local lastCastSpeed = {} 

-- ==========================================================
-- 2. DETECCIÓN DE VOCACIÓN (Estricta)
-- ==========================================================
local function getVocType(name)
    if PlayerList and PlayerList.getVocation then
        local voc = PlayerList.getVocation(name)
        if voc then return voc end
    end

    local n = name and name:lower() or ""

    for voc, list in pairs(guildLists) do
        for _, dbName in ipairs(list) do
            if n:find(dbName, 1, true) then return voc end
        end
    end
    return "none"
end

-- ==========================================================
-- 3. INTERFAZ VISUAL
-- ==========================================================
UI.Separator()
local ui = setupUI([[
Panel
  height: 108
  margin-top: 2
  Label
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    text: -- GUILD BUFF V23 --
    text-align: center
    font: verdana-11px-rounded
    color: #FFD700
  BotSwitch
    id: switchBoost
    anchors.top: title.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 3
    height: 18
    text: ExuraBoost
  BotSwitch
    id: switchHaste
    anchors.top: switchBoost.bottom
    anchors.left: parent.left
    margin-top: 3
    width: 88
    height: 18
    text: ExuraHaste
  BotSwitch
    id: switchTempo
    anchors.top: switchBoost.bottom
    anchors.right: parent.right
    margin-top: 3
    width: 88
    height: 18
    text: ExuraTempo

  Label
    id: manaLabel
    anchors.top: switchHaste.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 4
    text-align: center
    font: verdana-11px-rounded

  HorizontalScrollBar
    id: manaStop
    anchors.top: manaLabel.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 3
    minimum: 0
    maximum: 100
    step: 1

  Label
    id: boostStatus
    anchors.top: manaStop.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 4
    text-align: center
    font: verdana-11px-rounded
    color: #9DD1CE
]])

ui.switchBoost:setOn(config.boostEnabled)
ui.switchHaste:setOn(config.hasteEnabled)
ui.switchTempo:setOn(config.tempoEnabled)

local function updateManaLabel()
    ui.manaLabel:setText("Stop Mana <= " .. config.manaStop .. "%")
end

ui.switchBoost.onClick = function(widget)
    config.boostEnabled = not config.boostEnabled
    widget:setOn(config.boostEnabled)
end

ui.switchHaste.onClick = function(widget)
    config.hasteEnabled = not config.hasteEnabled
    if config.hasteEnabled then
        config.tempoEnabled = false
        ui.switchTempo:setOn(false)
    end
    widget:setOn(config.hasteEnabled)
end

ui.switchTempo.onClick = function(widget)
    config.tempoEnabled = not config.tempoEnabled
    if config.tempoEnabled then
        config.hasteEnabled = false
        ui.switchHaste:setOn(false)
    end
    widget:setOn(config.tempoEnabled)
end

ui.manaStop:setValue(config.manaStop)
ui.manaStop.onValueChange = function(scroll, value)
    config.manaStop = value
    updateManaLabel()
end
updateManaLabel()

local function enoughMana()
    return manapercent() > (tonumber(config.manaStop) or 0)
end

local boostStatusText = ""
local nextGuildBuffCastAt = 0
local recentGuildBuffAttempt = nil
local retryAfterExhaust = 450

local function setBoostStatus(text)
    if boostStatusText == text then return end
    boostStatusText = text
    ui.boostStatus:setText(text)
    if ui.boostStatus.setTooltip then ui.boostStatus:setTooltip(text) end
end

local function getBuffSpectators()
    local ok, spectators = pcall(function() return getSpectators() end)
    if ok and type(spectators) == "table" then return spectators end
    return g_map.getSpectators(player:getPosition(), false)
end

local function rememberGuildBuffAttempt(kind, name, globalCooldown)
    recentGuildBuffAttempt = {kind = kind, name = name, at = now}
    nextGuildBuffCastAt = now + globalCooldown
end

local function playerListMatches(c, method)
    if not PlayerList or type(PlayerList[method]) ~= "function" then return false end
    local ok, result = pcall(function() return PlayerList[method](c) end)
    return ok and result == true
end

local function isGuildAlly(c)
    if not c or not c:isPlayer() or c == player then return false end
    if playerListMatches(c, "isFriend") or playerListMatches(c, "isGuildMember") then return true end
    local ok, emblem = pcall(function() return c:getEmblem() end)
    return ok and emblem == 1
end

-- ==========================================================
-- 4. LANZAMIENTO DE BOOST (Dueño de la prioridad)
-- ==========================================================
local function castBoost()
    if not config.boostEnabled then
        setBoostStatus("Boost: OFF")
        return false
    end
    if not enoughMana() then
        setBoostStatus("Boost: mana bajo")
        return false
    end

    local targets = {}
    for _, c in pairs(getBuffSpectators()) do
        if isGuildAlly(c) then
            local vocType = getVocType(c:getName())
            
            local prio = 5
            if vocType == "paladin" then prio = 1
            elseif vocType == "knight" then prio = 2
            elseif vocType == "sorcerer" then prio = 3
            elseif vocType == "druid" then prio = 4 end

            table.insert(targets, {c = c, prio = prio})
        end
    end

    table.sort(targets, function(a,b) return a.prio < b.prio end)

    if #targets == 0 then
        setBoostStatus("Boost: sin aliados")
        return false
    end
    if now < nextGuildBuffCastAt or now < lastGlobalBoost then
        setBoostStatus("Boost: espera | Aliados: " .. #targets)
        return false
    end

    for _, t in ipairs(targets) do
        local name = t.c:getName()
        if now > (lastCastBoost[name] or 0) then
            say('exura boost "'..name..'"')
            lastCastBoost[name] = now + cdBoost
            lastGlobalBoost = now + globalCdBoost
            rememberGuildBuffAttempt("boost", name, globalCdBoost)
            setBoostStatus("Boost > " .. name)
            return true
        end
    end

    setBoostStatus("Boost: cooldown | Aliados: " .. #targets)
    return false
end

-- ==========================================================
-- 5. LANZAMIENTO DE HASTE/TEMPO (Sincronizado)
-- ==========================================================
local function castSpeed()
    local cfg = config
    if not (cfg.hasteEnabled or cfg.tempoEnabled) then return false end
    if not enoughMana() then return false end
    if now < nextGuildBuffCastAt or now < lastGlobalSpeed then return false end

    local targets = {}
    for _, c in pairs(getBuffSpectators()) do
        if isGuildAlly(c) then
            local vocType = getVocType(c:getName())
            
            if vocType == "knight" or vocType == "paladin" then
                local spell = nil
                local prio = 99
                local cd = 0

                if vocType == "knight" then
                    if cfg.tempoEnabled then spell = "exura tempo"; prio = 1; cd = cdTempo
                    elseif cfg.hasteEnabled then spell = "exura haste"; prio = 2; cd = cdHaste end
                
                elseif vocType == "paladin" then
                    if cfg.hasteEnabled then spell = "exura haste"; prio = 1; cd = cdHaste
                    elseif cfg.tempoEnabled then spell = "exura tempo"; prio = 2; cd = cdTempo end
                end

                if spell then
                    table.insert(targets, {c = c, prio = prio, spell = spell, cd = cd})
                end
            end
        end
    end

    table.sort(targets, function(a,b) return a.prio < b.prio end)

    for _, t in ipairs(targets) do
        local name = t.c:getName()
        if now > (lastCastSpeed[name] or 0) then
            say(t.spell .. ' "' .. name .. '"')
            lastCastSpeed[name] = now + t.cd
            lastGlobalSpeed = now + globalCdSpeed
            rememberGuildBuffAttempt("speed", name, globalCdSpeed)
            return true
        end
    end

    return false
end

onTextMessage(function(mode, text)
    if type(text) ~= "string" or not text:lower():find("you are exhausted", 1, true) then return end

    local attempt = recentGuildBuffAttempt
    if not attempt or now - attempt.at > 900 then return end

    if attempt.kind == "boost" then
        lastCastBoost[attempt.name] = 0
        lastGlobalBoost = now + retryAfterExhaust
    else
        lastCastSpeed[attempt.name] = 0
        lastGlobalSpeed = now + retryAfterExhaust
    end

    nextGuildBuffCastAt = now + retryAfterExhaust
    recentGuildBuffAttempt = nil
    setBoostStatus("Reintento: exhaust")
end)

-- ==========================================================
-- 6. MACRO PRINCIPAL
-- ==========================================================
macro(200, function()
    -- Boost es prioritario. Haste/Tempo esperan al siguiente espacio global libre.
    if not castBoost() then castSpeed() end
end)
