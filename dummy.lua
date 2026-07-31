-- ========================================================================
-- SCRIPT DUMMY INTELIGENTE - Versão 2.3 (LIMPO - SEM LOGS)
-- Versão final sem logs/debugs no console
-- ========================================================================

addSeparator()
setDefaultTab("Main")

local panelName = "Dummy Train Smart"
local ui = setupUI([[
Panel
  height: 50

  BotItem
    id: item
    anchors.top: parent.top
    anchors.left: parent.left

  BotItem
    id: Target
    anchors.top: parent.top
    anchors.right: parent.right
    margin-left: 2

  BotSwitch
    id: title
    anchors.top: Target.top
    anchors.left: item.right
    anchors.right: parent.right
    anchors.bottom: Target.bottom
    text-align: center
    !text: tr('Dummy Smart')
    margin-top: 4
    margin-left: 6
    margin-right: 40

  Label
    id: status
    anchors.top: title.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    text-align: center
    text: Status: Desligado
    font: verdana-11px-antialised
    color: #888888
    margin-top: 2

]], parent)
ui:setId(panelName)

-- Configurações padrão
if not storage[panelName] then
  storage[panelName] = {
      id = 28557,        -- Item de exercício (ex: varinha)
      id2 = 28559,       -- Dummy alvo
      enabled = false    -- Estado do macro
  }
end

-- =========================[ VARIÁVEIS DE CONTROLE ]======================
local isCurrentlyTraining = false  -- Estado de treinamento
local lastClickTime = 0            -- Timestamp do último clique
local trainingStartTime = 0        -- Quando começou a treinar
local nextTrainingAttempt = 0      -- Bloqueio imposto pelo servidor
local waitingDummyKey = nil        -- Dummy usado para iniciar a espera estacionária
local lastPlayerPosition = nil     -- Posição usada para detectar movimento
local lastPlayerObject = player    -- Nova instância indica login/relogin
local CLICK_COOLDOWN = 3000        -- 3 segundos entre cliques no dummy
local CANCEL_RESTART_DELAY = 30000 -- 30 segundos após cancelar/interromper

-- =========================[ FUNÇÕES AUXILIARES ]==========================

local function updateStatus(text, color)
    ui.status:setText("Status: " .. text)
    ui.status:setColor(color or "#888888")
end

local function copyPosition(pos)
    if not pos then return nil end
    return {x = pos.x, y = pos.y, z = pos.z}
end

local function positionsMatch(first, second)
    return first and second and
           first.x == second.x and
           first.y == second.y and
           first.z == second.z
end

local function getDummyKey(dummy)
    if not dummy or not dummy.getPosition then return nil end
    local pos = dummy:getPosition()
    if not pos then return nil end
    return pos.x .. ":" .. pos.y .. ":" .. pos.z
end

local function scheduleStationaryWait()
    nextTrainingAttempt = now + CANCEL_RESTART_DELAY
    updateStatus("Espera: 30s", "#FFAA00")
end

local function stopTraining(reason)
    if reason ~= "cancelled" and not isCurrentlyTraining then return end

    isCurrentlyTraining = false
    trainingStartTime = 0
    lastClickTime = 0

    if reason == "cancelled" then
        scheduleStationaryWait()
        updateStatus("Cancelado: 30s", "#FFAA00")
    else
        nextTrainingAttempt = 0
        updateStatus("Treino terminou - reiniciando...", "#FFAA00")
    end
end

local function updateTrainingStatus()
    if not isCurrentlyTraining then return end

    local trainingTime = math.floor((now - trainingStartTime) / 1000)
    updateStatus("Treinando (" .. trainingTime .. "s)", "#66FF66")
end

local function findNearbyDummy()
    -- Procura por dummies próximos (até 7 SQMs)
    local playerPos = player:getPosition()
    if not playerPos then return nil end
    
    for _, tile in ipairs(g_map.getTiles(playerPos.z)) do
        local tilePos = tile:getPosition()
        local distance = getDistanceBetween(playerPos, tilePos)
        
        if distance <= 7 then
            local items = tile.getItems and tile:getItems() or {}
            for _, item in ipairs(items) do
                if item:getId() == storage[panelName].id2 then
                    return item
                end
            end
        end
    end
    
    return nil
end

local function hasExerciseItem()
    -- Verifica se o jogador tem o item de exercício
    local exercise = findItem(storage[panelName].id)
    return exercise ~= nil
end

local function useExerciseItem(exercise, dummy)
    local subtype = 0
    if g_game and g_game.getClientVersion and g_game.getClientVersion() < 860 then
        subtype = 1
    end

    if g_game and g_game.useWith then
        local ok = pcall(function()
            g_game.useWith(exercise, dummy, subtype)
        end)
        if ok then return true end
    end

    if g_game and g_game.useInventoryItemWith then
        local ok = pcall(function()
            g_game.useInventoryItemWith(storage[panelName].id, dummy, subtype)
        end)
        if ok then return true end
    end

    if type(useWith) == "function" then
        local ok = pcall(function()
            useWith(storage[panelName].id, dummy, subtype)
        end)
        if ok then return true end
    end

    return false
end

local function attackDummy(dummy)
    -- Ataca o dummy uma única vez com cooldown
    if not dummy then return false end
    
    -- Verificar cooldown
    if now - lastClickTime < CLICK_COOLDOWN then
        return false
    end
    
    local exercise = findItem(storage[panelName].id)
    if not exercise then
        updateStatus("Item de exercício não encontrado", "#FF6666")
        return false
    end
    
    if not useExerciseItem(exercise, dummy) then
        updateStatus("Nao foi possivel usar a barita", "#FF6666")
        return false
    end

    isCurrentlyTraining = true
    trainingStartTime = now
    nextTrainingAttempt = 0
    lastClickTime = now
    updateStatus("Treinando - aguardando fim...", "#66FF66")
    return true
end

-- =========================[ DETECÇÃO DE MENSAGENS ]======================

local function containsAny(text, patterns)
    for _, pattern in ipairs(patterns) do
        if text:find(pattern, 1, true) then
            return true
        end
    end
    return false
end

local trainingStartedMessages = {
    "you started training with an exercise weapon",
    "you started training",
    "you have started training",
    "you are already training",
    "you are now training",
    "comecou a treinar",
    "começou a treinar",
    "comenzaste a entrenar",
    "has comenzado a entrenar"
}

local trainingCancelledMessages = {
    "you can't move while you train, the training has stopped",
    "training has stopped",
    "this exercise dummy can only be used after a 30 seconds cooldown",
    "exercise dummy can only be used after a 30 seconds cooldown",
    "30 seconds cooldown",
    "you stopped training",
    "you have stopped training",
    "you stop training",
    "you are no longer training",
    "training interrupted",
    "training has been interrupted",
    "training canceled",
    "training cancelled",
    "you canceled training",
    "you cancelled training",
    "you must wait 30 seconds",
    "wait 30 seconds",
    "treino cancelado",
    "treino interrompido",
    "parou de treinar",
    "deixou de treinar",
    "dejaste de entrenar",
    "entrenamiento cancelado",
    "entrenamiento interrumpido"
}

local trainingCompletedMessages = {
    "training has ended",
    "training ended",
    "training finished",
    "finished training",
    "exercise weapon has disappeared",
    "exercise weapon broke",
    "exercise weapon is no longer usable",
    "training weapon has disappeared",
    "training weapon broke",
    "ran out of charges",
    "no charges left",
    "treino terminou",
    "entrenamiento termino",
    "entrenamiento terminó",
    "entrenamiento finalizo",
    "entrenamiento finalizó"
}

-- Somente uma mensagem explicita de fim libera um novo uso da barita.
onTextMessage(function(_, text)
    if not storage[panelName].enabled then return end
    if not text then return end
    
    local lowerText = text:lower()

    if containsAny(lowerText, trainingCancelledMessages) then
        stopTraining("cancelled")
        return
    end

    if containsAny(lowerText, trainingCompletedMessages) then
        stopTraining("completed")
        return
    end

    if containsAny(lowerText, trainingStartedMessages) then
        if not isCurrentlyTraining then
            trainingStartTime = now
        end
        isCurrentlyTraining = true
        nextTrainingAttempt = 0
        updateStatus("Treinando - aguardando fim...", "#66FF66")
    end
end)

-- =========================[ LÓGICA PRINCIPAL ]============================

local function smartDummyLogic()
    if not storage[panelName].enabled then
        updateStatus("Desligado", "#888888")
        return
    end

    local currentPlayer = player
    if currentPlayer ~= lastPlayerObject then
        lastPlayerObject = currentPlayer
        isCurrentlyTraining = false
        trainingStartTime = 0
        nextTrainingAttempt = 0
        waitingDummyKey = nil
        lastPlayerPosition = nil
    end

    local currentPosition = currentPlayer and currentPlayer:getPosition()
    if not currentPosition then return end

    local playerMoved = lastPlayerPosition and
                        not positionsMatch(lastPlayerPosition, currentPosition)
    lastPlayerPosition = copyPosition(currentPosition)

    -- Enquanto estiver treinando, nunca procurar nem usar outra barita.
    if isCurrentlyTraining then
        updateTrainingStatus()
        return
    end

    local dummy = findNearbyDummy()
    if not dummy then
        waitingDummyKey = nil
        updateStatus("Sin dummy", "#FF6666")
        return
    end

    if not hasExerciseItem() then
        waitingDummyKey = nil
        updateStatus("Sin barita", "#FF6666")
        return
    end

    local dummyKey = getDummyKey(dummy)
    if dummyKey ~= waitingDummyKey then
        waitingDummyKey = dummyKey
        scheduleStationaryWait()
    elseif playerMoved then
        scheduleStationaryWait()
    end

    if now < nextTrainingAttempt then
        local secondsLeft = math.ceil((nextTrainingAttempt - now) / 1000)
        updateStatus("Espera: " .. secondsLeft .. "s", "#FFAA00")
        return
    end

    attackDummy(dummy)
end

-- =========================[ MACRO PRINCIPAL ]============================

-- Macro principal - executa a cada 1 segundo
dummySmart = macro(1000, function()
    smartDummyLogic()
end)

-- =========================[ INTERFACE E EVENTOS ]======================

onPlayerPositionChange(function(newPosition, oldPosition)
    lastPlayerPosition = copyPosition(newPosition)

    if not storage[panelName].enabled or isCurrentlyTraining then return end
    if not waitingDummyKey or positionsMatch(newPosition, oldPosition) then return end

    scheduleStationaryWait()
end)

-- Configurar UI inicial
ui.title:setOn(storage[panelName].enabled)
ui.title.onClick = function(widget)
    storage[panelName].enabled = not storage[panelName].enabled
    widget:setOn(storage[panelName].enabled)
    
    if storage[panelName].enabled then
        updateStatus("Ativado", "#66FF66")
        -- Reset do estado quando ativar
        isCurrentlyTraining = false
        lastClickTime = 0
        trainingStartTime = 0
        nextTrainingAttempt = 0
        waitingDummyKey = nil
        lastPlayerPosition = copyPosition(player and player:getPosition())
        lastPlayerObject = player
    else
        updateStatus("Desligado", "#888888")
        isCurrentlyTraining = false
        trainingStartTime = 0
        waitingDummyKey = nil
    end
end

ui.item.onItemChange = function(widget)
    storage[panelName].id = widget:getItemId()
    waitingDummyKey = nil
end
ui.item:setItemId(storage[panelName].id)

ui.Target.onItemChange = function(widget)
    storage[panelName].id2 = widget:getItemId()
    waitingDummyKey = nil
end
ui.Target:setItemId(storage[panelName].id2)

-- =========================[ FUNÇÕES DE CONTROLE ]======================

function setDummySmartOff()
    storage[panelName].enabled = false
    ui.title:setOn(false)
    updateStatus("Desligado", "#888888")
    isCurrentlyTraining = false
    waitingDummyKey = nil
end

function setDummySmartOn()
    storage[panelName].enabled = true
    ui.title:setOn(true)
    updateStatus("Ativado", "#66FF66")
    isCurrentlyTraining = false
    lastClickTime = 0
    trainingStartTime = 0
    nextTrainingAttempt = 0
    waitingDummyKey = nil
    lastPlayerPosition = copyPosition(player and player:getPosition())
    lastPlayerObject = player
end

local editorLoaded, editorError = pcall(function()
    dofile("/vBot/ingame_editor.lua")
end)
if not editorLoaded then
    warn("In-Game Script Editor no pudo cargarse:\n" .. tostring(editorError))
end

