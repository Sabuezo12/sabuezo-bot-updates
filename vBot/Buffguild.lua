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
config.boostEnabled = true
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
  height: 88
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
  Label
    id: boostStatus
    anchors.top: title.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 3
    height: 18
    text: ExuraBoost: ON
    text-align: center
    color: #00FF00
  BotSwitch
    id: switchHaste
    anchors.top: boostStatus.bottom
    anchors.left: parent.left
    margin-top: 3
    width: 88
    height: 18
    text: ExuraHaste
  BotSwitch
    id: switchTempo
    anchors.top: boostStatus.bottom
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
]])

ui.switchHaste:setOn(config.hasteEnabled)
ui.switchTempo:setOn(config.tempoEnabled)

local function updateManaLabel()
    ui.manaLabel:setText("Stop Mana <= " .. config.manaStop .. "%")
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

local function isGuildAlly(c)
    if not c or not c:isPlayer() or c == player then return false end
    local ok, emblem = pcall(function() return c:getEmblem() end)
    return ok and emblem == 1
end

-- ==========================================================
-- 4. LANZAMIENTO DE BOOST (Dueño de la prioridad)
-- ==========================================================
local function castBoost()
    if not config.boostEnabled then return end
    if not enoughMana() then return end
    if now < lastGlobalBoost then return end 

    local targets = {}
    for _, c in pairs(g_map.getSpectators(player:getPosition(), false)) do
        if isGuildAlly(c) then
            local vocType = getVocType(c:getName())
            
            local prio = 99
            if vocType == "paladin" then prio = 1
            elseif vocType == "knight" then prio = 2
            elseif vocType == "sorcerer" then prio = 3
            elseif vocType == "druid" then prio = 4 end

            if prio < 99 then
                table.insert(targets, {c = c, prio = prio})
            end
        end
    end

    table.sort(targets, function(a,b) return a.prio < b.prio end)

    for _, t in ipairs(targets) do
        local name = t.c:getName()
        if now > (lastCastBoost[name] or 0) then
            say('exura boost "'..name..'"')
            lastCastBoost[name] = now + cdBoost
            lastGlobalBoost = now + globalCdBoost
            return
        end
    end
end

-- ==========================================================
-- 5. LANZAMIENTO DE HASTE/TEMPO (Sincronizado)
-- ==========================================================
local function castSpeed()
    local cfg = config
    if not (cfg.hasteEnabled or cfg.tempoEnabled) then return end
    if not enoughMana() then return end
    if now < lastGlobalSpeed then return end

    -- 🔥 SINCRONIZACIÓN DE EXHAUST (EL SECRETO) 🔥
    local timeUntilBoost = lastGlobalBoost - now
    
    -- isSafeToSpeed será 'true' SOLO SI:
    -- 1. Acabamos de castear Boost hace menos de 400ms (van pegados, Boost va primero)
    -- 2. O Boost está listo y esperando, pero NADIE lo necesita en este momento.
    local isSafeToSpeed = timeUntilBoost > 1800
    
    -- Si Boost está cargando y casi listo (ej. falta 1 segundo), nos esperamos. 
    -- Si tiramos Speed ahora, le meteríamos 2 segundos de exhaust a Boost.
    if not isSafeToSpeed then return end

    local targets = {}
    for _, c in pairs(g_map.getSpectators(player:getPosition(), false)) do
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
            
            return
        end
    end
end

-- ==========================================================
-- 6. MACRO PRINCIPAL
-- ==========================================================
macro(200, function()
    -- CastBoost siempre va primero. Si actua, prepara el terreno seguro para CastSpeed.
    castBoost()   
    castSpeed()   
end)
