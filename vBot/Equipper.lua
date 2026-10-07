local panelName = "EquipperPanel"
local ui = setupUI([[
Panel
  height: 19

  BotSwitch
    id: switch
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('EQ Manager')

  Button
    id: setup
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 17
    text: Setup
]])
ui:setId(panelName)

if not storage[panelName] or not storage[panelName].bosses then -- no bosses - old ver
    storage[panelName] = {
        enabled = false,
        rules = {},
        bosses = {}
    }
end

local config = storage[panelName]

ui.switch:setOn(config.enabled)
ui.switch.onClick = function(widget)
  config.enabled = not config.enabled
  widget:setOn(config.enabled)
end

local conditions = { -- always add new conditions at the bottom
    "Item is available and not worn.", -- nothing 1
    "Monsters around is more than:", -- spinbox 2
    "Monsters around is less than:", -- spinbox 3
    "Health percent is below:", -- spinbox 4
    "Health percent is above:", -- spinbox 5
    "Mana percent is below:", -- spinbox 6
    "Mana percent is above:", -- spinbox 7
    "Target name is:", -- BotTextEdit 8
    "Hotkey is being pressed:", -- BotTextEdit 9
    "Player is paralyzed", -- nothing 10
    "Player is in protection zone", -- nothing 11
    "Players around is more than:", -- spinbox 12
    "Players around is less than:", -- spinbox 13
    "TargetBot Danger is above:", -- spinbox 14
    "Blacklist player in range (sqm)", -- spinbox 15
    "Target is Boss", -- nothing 16
    "Player is NOT in protection zone", -- nothing 17
    "CaveBot is ON, TargetBot is OFF" -- nothing 18
}

local function migrateUnsafePlayerCondition(rule, conditionKey, valueKey)
    if not rule then return end
    if rule[conditionKey] == 19 then
        rule[conditionKey] = 12
        rule.pvpSafe = true
    elseif rule[conditionKey] == 20 then
        rule[conditionKey] = 13
        rule.pvpSafe = true
    elseif rule[conditionKey] == 21 then
        rule[conditionKey] = 13
        rule[valueKey] = 1
        rule.pvpSafe = true
    end
end

for _, rule in ipairs(config.rules) do
    migrateUnsafePlayerCondition(rule, "mainCondition", "mainValue")
    migrateUnsafePlayerCondition(rule, "optionalCondition", "optValue")
    if rule.mainIgnoreSafe or rule.optIgnoreSafe then
        rule.pvpSafe = true
    end
end

local conditionNumber = 1
local optionalConditionNumber = 2

local mainWindow = UI.createWindow("EquipWindow")
mainWindow:hide()

ui.setup.onClick = function()
    mainWindow:show()
    mainWindow:raise()
    mainWindow:focus()
end

local inputPanel = mainWindow.inputPanel
local listPanel = mainWindow.listPanel
local namePanel = mainWindow.profileName
local eqPanel = mainWindow.setup
local bossPanel = mainWindow.bossPanel

local slotWidgets = {eqPanel.head, eqPanel.body, eqPanel.legs, eqPanel.feet, eqPanel.neck, eqPanel["left-hand"], eqPanel["right-hand"], eqPanel.finger, eqPanel.ammo} -- back is disabled

local function setPvpSafeToggle(value)
    if not mainWindow.pvpSafe then return end
    mainWindow.pvpSafe.eqPvpSafe = value == true
    if mainWindow.pvpSafe.setOn then
        mainWindow.pvpSafe:setOn(mainWindow.pvpSafe.eqPvpSafe)
    end
end

local function getPvpSafeToggle()
    return mainWindow.pvpSafe and mainWindow.pvpSafe.eqPvpSafe == true
end

if mainWindow.pvpSafe then
    setPvpSafeToggle(false)
    mainWindow.pvpSafe.onClick = function()
        setPvpSafeToggle(not getPvpSafeToggle())
    end
end

local function setCondition(first, n)
    local widget
    local spinBox 
    local textEdit

    if first then
        widget = inputPanel.condition.description.text
        spinBox = inputPanel.condition.spinbox
        textEdit = inputPanel.condition.text
    else
        widget = inputPanel.optionalCondition.description.text
        spinBox = inputPanel.optionalCondition.spinbox
        textEdit = inputPanel.optionalCondition.text
    end

    -- reset values after change
    spinBox:setValue(0)
    textEdit:setText('')

    if n == 1 or n == 10 or n == 11 or n == 16 or n == 17 or n == 18 then
        spinBox:hide()
        textEdit:hide()
    elseif n == 9 or n == 8 then
        spinBox:hide()
        textEdit:show()
        if n == 9 then
            textEdit:setWidth(75)
        else
            textEdit:setWidth(200)
        end
    else
        spinBox:show()
        textEdit:hide()
    end
    widget:setText(conditions[n])
end

local function resetFields()
    conditionNumber = 1
    optionalConditionNumber = 2
    setCondition(false, optionalConditionNumber)
    setCondition(true, conditionNumber)
    for i, widget in ipairs(slotWidgets) do
        widget:setItemId(0)
        widget:setChecked(false)
    end
    for i, child in ipairs(listPanel.list:getChildren()) do
        child.display = false
    end
    namePanel.profileName:setText("")
    inputPanel.condition.text:setText('')
    inputPanel.condition.spinbox:setValue(0)
    setPvpSafeToggle(false)
    inputPanel.useSecondCondition:setText('-')
    inputPanel.optionalCondition.text:setText('')
    inputPanel.optionalCondition.spinbox:setValue(0)
    inputPanel.optionalCondition:hide()
    bossPanel:hide()
    listPanel:show()
    mainWindow.bossList:setText('Bosses')
    bossPanel.name:setText('')
end
resetFields()

mainWindow.closeButton.onClick = function()
    resetFields()
    mainWindow:hide()
end

inputPanel.optionalCondition:hide()
inputPanel.useSecondCondition.onOptionChange = function(widget, option, data)
    if option ~= "-" then
        inputPanel.optionalCondition:show()
    else
        inputPanel.optionalCondition:hide()
    end
end

-- add default text & windows
setCondition(true, 1)
setCondition(false, 2)

-- in/de/crementation buttons
inputPanel.condition.nex.onClick = function()
    local max = #conditions

    if inputPanel.optionalCondition:isVisible() then
        if conditionNumber == max then
            if optionalConditionNumber == 1 then
                conditionNumber = 2
            else
                conditionNumber = 1
            end
        else
            local futureNumber = conditionNumber + 1
            local safeFutureNumber = conditionNumber + 2 > max and 1 or conditionNumber + 2
            conditionNumber = futureNumber ~= optionalConditionNumber and futureNumber or safeFutureNumber
        end
    else
        conditionNumber = conditionNumber == max and 1 or conditionNumber + 1
        if optionalConditionNumber == conditionNumber then
            optionalConditionNumber = optionalConditionNumber == max and 1 or optionalConditionNumber + 1
            setCondition(false, optionalConditionNumber)
        end
    end
    setCondition(true, conditionNumber)
end

inputPanel.condition.pre.onClick = function()
    local max = #conditions

    if inputPanel.optionalCondition:isVisible() then
        if conditionNumber == 1 then
            if optionalConditionNumber == max then
                conditionNumber = max-1
            else
                conditionNumber = max
            end
        else
            local futureNumber = conditionNumber - 1
            local safeFutureNumber = conditionNumber - 2 < 1 and max or conditionNumber - 2
            conditionNumber = futureNumber ~= optionalConditionNumber and futureNumber or safeFutureNumber
        end
    else
        conditionNumber = conditionNumber == 1 and max or conditionNumber - 1
        if optionalConditionNumber == conditionNumber then
            optionalConditionNumber = optionalConditionNumber == 1 and max or optionalConditionNumber - 1
            setCondition(false, optionalConditionNumber)
        end
    end
    setCondition(true, conditionNumber)
end

inputPanel.optionalCondition.nex.onClick = function()
    local max = #conditions

    if optionalConditionNumber == max then
        if conditionNumber == 1 then
            optionalConditionNumber = 2
        else
            optionalConditionNumber = 1
        end
    else
        local futureNumber = optionalConditionNumber + 1
        local safeFutureNumber = optionalConditionNumber + 2 > max and 1 or optionalConditionNumber + 2
        optionalConditionNumber = futureNumber ~= conditionNumber and futureNumber or safeFutureNumber
    end
    setCondition(false, optionalConditionNumber)
end

inputPanel.optionalCondition.pre.onClick = function()
    local max = #conditions

    if optionalConditionNumber == 1 then
        if conditionNumber == max then
            optionalConditionNumber = max-1
        else
            optionalConditionNumber = max
        end
    else
        local futureNumber = optionalConditionNumber - 1
        local safeFutureNumber = optionalConditionNumber - 2 < 1 and max or optionalConditionNumber - 2
        optionalConditionNumber = futureNumber ~= conditionNumber and futureNumber or safeFutureNumber
    end
    setCondition(false, optionalConditionNumber)
end

listPanel.up.onClick = function(widget)
    local focused = listPanel.list:getFocusedChild()
    local n = listPanel.list:getChildIndex(focused)
    local t = config.rules

    t[n], t[n-1] = t[n-1], t[n]
    if n-1 == 1 then
      widget:setEnabled(false)
    end
    listPanel.down:setEnabled(true)
    listPanel.list:moveChildToIndex(focused, n-1)
    listPanel.list:ensureChildVisible(focused)
end

listPanel.down.onClick = function(widget)
    local focused = listPanel.list:getFocusedChild()    
    local n = listPanel.list:getChildIndex(focused)
    local t = config.rules

    t[n], t[n+1] = t[n+1], t[n]
    if n + 1 == listPanel.list:getChildCount() then
      widget:setEnabled(false)
    end
    listPanel.up:setEnabled(true)
    listPanel.list:moveChildToIndex(focused, n+1)
    listPanel.list:ensureChildVisible(focused)
end

eqPanel.cloneEq.onClick = function(widget)
    eqPanel.head:setItemId(getHead() and getHead():getId() or 0)
    eqPanel.body:setItemId(getBody() and getBody():getId() or 0)
    eqPanel.legs:setItemId(getLeg() and getLeg():getId() or 0)
    eqPanel.feet:setItemId(getFeet() and getFeet():getId() or 0)  
    eqPanel.neck:setItemId(getNeck() and getNeck():getId() or 0)   
    eqPanel["left-hand"]:setItemId(getLeft() and getLeft():getId() or 0)
    eqPanel["right-hand"]:setItemId(getRight() and getRight():getId() or 0)
    eqPanel.finger:setItemId(getFinger() and getFinger():getId() or 0)    
    eqPanel.ammo:setItemId(getAmmo() and getAmmo():getId() or 0)    
end

eqPanel.default.onClick = resetFields

ui.setup:setTooltip("Abrir reglas avanzadas del EQ Manager.")
inputPanel.condition.nex:setTooltip("Siguiente condicion.")
inputPanel.condition.pre:setTooltip("Condicion anterior.")
inputPanel.condition.description:setTooltip("Usa la rueda del mouse para cambiar la condicion.")
inputPanel.optionalCondition.nex:setTooltip("Siguiente condicion secundaria.")
inputPanel.optionalCondition.pre:setTooltip("Condicion secundaria anterior.")
inputPanel.optionalCondition.description:setTooltip("Usa la rueda del mouse para cambiar la condicion secundaria.")
inputPanel.useSecondCondition:setTooltip("Combina la condicion principal con una segunda condicion.")
inputPanel.add:setTooltip("Agregar o reemplazar la regla con la configuracion actual.")
if mainWindow.pvpSafe then
    mainWindow.pvpSafe:setTooltip("Cuando esta activo, las condiciones de players cerca ignoran friends, guild y party del PlayerList.")
end
listPanel.up:setTooltip("Subir prioridad de la regla seleccionada.")
listPanel.down:setTooltip("Bajar prioridad de la regla seleccionada.")
eqPanel.cloneEq:setTooltip("Copiar el equipo que tienes puesto actualmente.")
eqPanel.default:setTooltip("Limpiar todos los campos de la regla actual.")
mainWindow.bossList:setTooltip("Cambiar entre lista de reglas y lista de bosses.")
if listPanel.statusLabel then
    listPanel.statusLabel:setText("Status: waiting for rule")
    listPanel.statusLabel:setTooltip("Muestra la ultima regla activa o la razon por la que no cambio el equipo.")
end

-- buttons disabled by default
listPanel.up:setEnabled(false)
listPanel.down:setEnabled(false)

-- correct background image
for i, widget in ipairs(slotWidgets) do
    widget:setTooltip("Click derecho para marcar este slot como quitar equipo.")
    widget.onItemChange = function(widget)
        local selfId = widget:getItemId()
        widget:setOn(selfId > 100)
        if widget:isChecked() then
            widget:setChecked(selfId < 100)
        end
    end
    widget.onMouseRelease = function(widget, mousePos, mouseButton)
        if mouseButton == 2 then
            local clearItem = widget:isChecked() == false
            widget:setChecked(not widget:isChecked())
            if clearItem then
                widget:setItemId(0)
            end
        end
    end
end

inputPanel.condition.description.onMouseWheel = function(widget, mousePos, scroll)
    if scroll == 1 then
        inputPanel.condition.nex.onClick()
    else
        inputPanel.condition.pre.onClick()
    end
end

inputPanel.optionalCondition.description.onMouseWheel = function(widget, mousePos, scroll)
    if scroll == 1 then
        inputPanel.optionalCondition.nex.onClick()
    else
        inputPanel.optionalCondition.pre.onClick()
    end
end

namePanel.profileName.onTextChange = function(widget, text)
    local button = inputPanel.add
    text = text:lower()

    for i, child in ipairs(listPanel.list:getChildren()) do
        local name = child:getText():lower()

        button:setText(name == text and "Overwrite" or "Add Rule")
        button:setTooltip(name == text and "Reemplazar regla existente: "..name or "Agregar nueva regla.")
    end
end

local function setupPreview(display, data)
    namePanel.profileName:setText('')
    if not display then
        resetFields()
    else
        for i, value in ipairs(data) do
            local widget = slotWidgets[i]
            if value == false then
                widget:setChecked(false)
                widget:setItemId(0)
            elseif value == true then
                widget:setChecked(true)
                widget:setItemId(0)
            else
                widget:setChecked(false)
                widget:setItemId(value)       
            end
        end
    end
end

local function refreshRules()
    local list = listPanel.list

    list:destroyChildren()
    for i,v in ipairs(config.rules) do
        local widget = UI.createWidget('Rule', list)
        widget:setId(v.name)
        widget:setText(v.name)
        widget.ruleData = v
        widget.remove.onClick = function()
            widget:destroy()
            table.remove(config.rules, table.find(config.rules, v))
            listPanel.up:setEnabled(false)
            listPanel.down:setEnabled(false)
            refreshRules()
        end
        widget.visible:setColor(v.visible and "green" or "red")
        widget.visible:setTooltip("Verde: el item debe estar visible. Rojo: intenta equipar por ID.")
        widget.visible.onClick = function()
            v.visible = not v.visible
            widget.visible:setColor(v.visible and "green" or "red")
        end
        widget.enabled:setTooltip("Activar o desactivar esta regla.")
        widget.enabled:setChecked(v.enabled)
        widget.enabled.onClick = function()
            v.enabled = not v.enabled
            widget.enabled:setChecked(v.enabled)
        end
        widget.onHoverChange = function(widget, hover)
            for i, child in ipairs(list:getChildren()) do
                if child.display then return end
            end
            setupPreview(hover, widget.ruleData.data)
        end
        widget.onDoubleClick = function(widget)
            local ruleData = widget.ruleData
            widget.display = true
            setupPreview(true, ruleData.data)
            conditionNumber = ruleData.mainCondition
            optionalConditionNumber = ruleData.optionalCondition
            setCondition(false, optionalConditionNumber)
            setCondition(true, conditionNumber)
            inputPanel.useSecondCondition:setOption(ruleData.relation)
            namePanel.profileName:setText(v.name)

            if type(ruleData.mainValue) == "string" then
                inputPanel.condition.text:setText(ruleData.mainValue)
            elseif type(ruleData.mainValue) == "number" then
                inputPanel.condition.spinbox:setValue(ruleData.mainValue)
            end

            if type(ruleData.optValue) == "string" then
                inputPanel.optionalCondition.text:setText(ruleData.optValue)
            elseif type(ruleData.optValue) == "number" then
                inputPanel.optionalCondition.spinbox:setValue(ruleData.optValue)
            end
            setPvpSafeToggle(ruleData.pvpSafe == true or ruleData.mainIgnoreSafe == true or ruleData.optIgnoreSafe == true)
        end
        widget.onClick = function()
            local panel = listPanel
            if #panel.list:getChildren() == 1 then
                panel.up:setEnabled(false)
                panel.down:setEnabled(false)
            elseif panel.list:getChildIndex(panel.list:getFocusedChild()) == 1 then
                panel.up:setEnabled(false)
                panel.down:setEnabled(true)
            elseif panel.list:getChildIndex(panel.list:getFocusedChild()) == #panel.list:getChildren() then
                panel.up:setEnabled(true)
                panel.down:setEnabled(false)
            else
                panel.up:setEnabled(true)
                panel.down:setEnabled(true)
            end
        end
    end
end
refreshRules()

inputPanel.add.onClick = function(widget)
    local mainVal
    local optVal
    local t = {}
    local relation = inputPanel.useSecondCondition:getText()
    local profileName = namePanel.profileName:getText()
    local pvpSafe = getPvpSafeToggle()
    if profileName:len() == 0 then
        return warn("Please fill profile name!")
    end

    for i, widget in ipairs(slotWidgets) do
        local checked = widget:isChecked()
        local id = widget:getItemId()

        if checked then
            table.insert(t, true) -- unequip selected slot
        elseif id then
            table.insert(t, id) -- equip selected item
        else
            table.insert(t, false) -- ignore slot
        end
    end

    if conditionNumber == 1 then
        mainVal = nil
    elseif conditionNumber == 8 then
        mainVal = inputPanel.condition.text:getText()
        if mainVal:len() == 0 then
            return warn("[vBot Equipper] Please fill the name of the creature.")
        end
    elseif conditionNumber == 9 then
        mainVal = inputPanel.condition.text:getText()
        if mainVal:len() == 0 then
            return warn("[vBot Equipper] Please set correct hotkey.")
        end
    else
        mainVal = inputPanel.condition.spinbox:getValue()
    end

    if relation ~= "-" then
        if optionalConditionNumber == 1 then
            optVal = nil
        elseif optionalConditionNumber == 8 then
            optVal = inputPanel.optionalCondition.text:getText()
            if optVal:len() == 0 then
                return warn("[vBot Equipper] Please fill the name of the creature.")
            end
        elseif optionalConditionNumber == 9 then
            optVal = inputPanel.optionalCondition.text:getText()
            if optVal:len() == 0 then
                return warn("[vBot Equipper] Please set correct hotkey.")
            end
        else
            optVal = inputPanel.optionalCondition.spinbox:getValue()
        end
    end

    local index
    for i, v in ipairs(config.rules) do
        if v.name == profileName then
            index = i   -- search if there's already rule with this name
        end
    end

    local ruleData = {
        name = profileName, 
        data = t,
        enabled = true,
        visible = true,
        mainCondition = conditionNumber,
        optionalCondition = optionalConditionNumber,
        mainValue = mainVal,
        optValue = optVal,
        relation = relation,
        pvpSafe = pvpSafe,
    }

    if index then
        config.rules[index] = ruleData -- overwrite
    else
        table.insert(config.rules, ruleData) -- create new one
    end

    for i, child in ipairs(listPanel.list:getChildren()) do
        child.display = false
    end
    resetFields()
    refreshRules()
end

mainWindow.bossList.onClick = function(widget)
    if bossPanel:isVisible() then
        bossPanel:hide()
        listPanel:show()
        widget:setText('Bosses')
    else
        bossPanel:show()
        listPanel:hide()
        widget:setText('Rules')

    end
end

-- create boss labels
for i, v in ipairs(config.bosses) do
    local widget = UI.createWidget("BossLabel", bossPanel.list)
    widget:setText(v)
    widget.remove.onClick = function()
        table.remove(config.bosses, table.find(config.bosses, v))
        widget:destroy()
    end
end

bossPanel.add.onClick = function()
    local name = bossPanel.name:getText()

    if name:len() == 0 then
        return warn("[Equipped] Please enter boss name!")
    elseif table.find(config.bosses, name:lower(), true) then
        return warn("[Equipper] Boss already added!")
    end

    local widget = UI.createWidget("BossLabel", bossPanel.list)
    widget:setText(name)
    widget.remove.onClick = function()
        table.remove(config.bosses, table.find(config.bosses, name))
        widget:destroy()
    end    

    table.insert(config.bosses, name)
    bossPanel.name:setText('')
end

local runtimeStats = {
    monsters = 0,
    players = 0,
    friendlyPlayers = 0,
    unsafePlayers = 0,
    unsafeNames = {}
}

local activeRuleName = nil
local activeStatusText = nil
local activeWindowVisible = false

local function safeCreatureFlag(creature, method)
    if not creature or not creature[method] then return false end
    local ok, result = pcall(function() return creature[method](creature) end)
    return ok and result or false
end

local function safeCreatureValue(creature, method, default)
    if not creature or not creature[method] then return default end
    local ok, result = pcall(function() return creature[method](creature) end)
    if ok then return result end
    return default
end

local function safeDistanceFromPlayer(position)
    if not position then return 999 end
    local ok, distance = pcall(function() return distanceFromPlayer(position) end)
    return ok and distance or 999
end

local function isEquipFriendlyPlayer(creature)
    if not creature or creature == player then return true end
    if not safeCreatureFlag(creature, "isPlayer") then return false end
    if safeCreatureFlag(creature, "isLocalPlayer") then return true end
    if safeCreatureFlag(creature, "isPartyMember") then return true end

    local name = safeCreatureValue(creature, "getName", nil)
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
        local ok, result = pcall(function() return isFriend(name) end)
        if ok and result then return true end
        ok, result = pcall(function() return isFriend(creature) end)
        if ok and result then return true end
    end

    return false
end

local function shouldCountAsLegacyPlayer(creature)
    local shield = safeCreatureValue(creature, "getShield", 0)
    local emblem = safeCreatureValue(creature, "getEmblem", 0)
    local party = safeCreatureFlag(creature, "isPartyMember")
    return not ((shield ~= 1 and party) or emblem == 1)
end

local function rebuildRuntimeStats()
    runtimeStats.monsters = 0
    runtimeStats.players = 0
    runtimeStats.friendlyPlayers = 0
    runtimeStats.unsafePlayers = 0
    runtimeStats.unsafeNames = {}

    for _, spec in pairs(getSpectators()) do
        if spec ~= player then
            local specPos = safeCreatureValue(spec, "getPosition", nil)
            local distance = safeDistanceFromPlayer(specPos)

            if distance <= 10 then
                if safeCreatureFlag(spec, "isMonster") and
                    (g_game.getClientVersion() < 960 or safeCreatureValue(spec, "getType", 0) < 3) then
                    runtimeStats.monsters = runtimeStats.monsters + 1
                elseif safeCreatureFlag(spec, "isPlayer") and not safeCreatureFlag(spec, "isLocalPlayer") then
                    if shouldCountAsLegacyPlayer(spec) then
                        runtimeStats.players = runtimeStats.players + 1
                    end

                    if isEquipFriendlyPlayer(spec) then
                        runtimeStats.friendlyPlayers = runtimeStats.friendlyPlayers + 1
                    else
                        runtimeStats.unsafePlayers = runtimeStats.unsafePlayers + 1
                        table.insert(runtimeStats.unsafeNames, safeCreatureValue(spec, "getName", "?"))
                    end
                end
            end
        end
    end
end

local function setManagerStatus(rule, text, color)
    local ruleName = rule and rule.name or nil
    local windowVisible = mainWindow:isVisible()
    if activeRuleName == ruleName and activeStatusText == text and activeWindowVisible == windowVisible then return end

    activeRuleName = ruleName
    activeStatusText = text
    activeWindowVisible = windowVisible

    if listPanel.statusLabel then
        listPanel.statusLabel:setText("Status: " .. text)
        listPanel.statusLabel:setColor(color or "#d7d7d7")
    end

    if windowVisible then
        for _, child in ipairs(listPanel.list:getChildren()) do
            if rule and child.ruleData == rule then
                child:setColor(color or "#03C04A")
            else
                child:setColor("white")
            end
        end
    end
end

local function interpreteCondition(n, v, ignoreSafePlayers)

    if n == 1 then
        return true
    elseif n == 2 then
        return runtimeStats.monsters > v
    elseif n == 3 then
        return runtimeStats.monsters < v
    elseif n == 4 then
        return hppercent() < v
    elseif n == 5 then
        return hppercent() > v
    elseif n == 6 then
        return manapercent() < v
    elseif n == 7 then
        return manapercent() > v
    elseif n == 8 then
        return target() and target():getName():lower() == v:lower() or false
    elseif n == 9 then
        return g_keyboard.isKeyPressed(v)
    elseif n == 10 then
        return isParalyzed()
    elseif n == 11 then
        return isInPz()
    elseif n == 12 then
        return (ignoreSafePlayers and runtimeStats.unsafePlayers or runtimeStats.players) > v
    elseif n == 13 then
        return (ignoreSafePlayers and runtimeStats.unsafePlayers or runtimeStats.players) < v
    elseif n == 14 then
        return TargetBot.Danger() > v and TargetBot.isOn()
    elseif n == 15 then
        return isBlackListedPlayerInRange(v)
    elseif n == 16 then
        return target() and table.find(config.bosses, target():getName():lower(), true) and true or false
    elseif n == 17 then
        return not isInPz()
    elseif n == 18 then
        return CaveBot.isOn() and TargetBot.isOff()
    end
end

local function finalCheck(first,relation,second)
    if relation == "-" then
        return first
    elseif relation == "and" then
        return first and second
    elseif relation == "or" then
        return first or second
    end
end

local function isEquipped(id)
    local t = {getNeck(), getHead(), getBody(), getRight(), getLeft(), getLeg(), getFeet(), getFinger(), getAmmo()}
    local ids = {id, getInactiveItemId(id), getActiveItemId(id)}

    for i, slot in pairs(t) do
        if slot and table.find(ids, slot:getId()) then
            return true
        end
    end
    return false
end

local function unequipItem(table)
    local slots = {getHead(), getBody(), getLeg(), getFeet(), getNeck(), getLeft(), getRight(), getFinger(), getAmmo()}

    if type(table) ~= "table" then return end
    for i, slot in ipairs(table) do
        local physicalSlot = slots[i]

        if slot == true and physicalSlot then
            local id = physicalSlot:getId()

            if g_game.getClientVersion() >= 910 then
                -- new tibia
                g_game.equipItemId(id)
            else
                -- old tibia
                local dest
                for i, container in ipairs(getContainers()) do
                    local cname = container:getName()
                    if not containerIsFull(container) then
                        if not cname:find("loot") and (cname:find("backpack") or cname:find("bag") or cname:find("chess")) then
                            dest = container
                        end
                        break
                    end
                end

                if not dest then return true end
                local pos = dest:getSlotPosition(dest:getItemsCount())
                g_game.move(physicalSlot, pos, physicalSlot:getCount())
            end
            return true
        end
    end
    return false
end

local function equipItem(id, slot)
    -- need to correct slots...
    if slot == 2 then
        slot = 4
    elseif slot == 3 then
        slot = 7
    elseif slot == 8 then
        slot = 9
    elseif slot == 5 then
        slot = 2
    elseif slot == 4 then
        slot = 8
    elseif slot == 9 then
        slot = 10
    elseif slot == 7 then
        slot = 5
    end


    if g_game.getClientVersion() >= 910 then
        -- new tibia
        return g_game.equipItemId(id)
    else
        -- old tibia
        local item = findItem(id)
        return moveToSlot(item, slot)
    end
end


local missingItem = false
local lastRule = false
local correctEq = false
EquipManager = macro(100, function()
    if not config.enabled then
        setManagerStatus(nil, "off", "#d7d7d7")
        return
    end
    if #config.rules == 0 then
        setManagerStatus(nil, "no rules", "#d7d7d7")
        return
    end

    rebuildRuntimeStats()

    for i, widget in ipairs(listPanel.list:getChildren()) do
            local rule = widget.ruleData
        if rule.enabled then

            -- conditions
            local rulePvpSafe = rule.pvpSafe == true or rule.mainIgnoreSafe == true or rule.optIgnoreSafe == true
            local firstCondition = interpreteCondition(rule.mainCondition, rule.mainValue, rulePvpSafe)
            local optionalCondition = nil
            if rule.relation ~= "-" then
                optionalCondition = interpreteCondition(rule.optionalCondition, rule.optValue, rulePvpSafe)
            end

            -- checks
            if finalCheck(firstCondition, rule.relation, optionalCondition) then

                -- performance edits, loop reset
                local resetLoop = not missingItem and correctEq and lastRule ==  rule
                if resetLoop then
                    setManagerStatus(rule, "active rule: " .. rule.name, "#03C04A")
                    return
                end

                -- reset executed rule


                -- first check unequip
                if unequipItem(rule.data) == true then
                    lastRule = rule
                    correctEq = false
                    setManagerStatus(rule, "unequipping: " .. rule.name, "#FABD02")
                    delay(200)
                    return
                end

                -- equiploop 
                for slot, item in ipairs(rule.data) do
                    if type(item) == "number" and item > 100 then
                        if not isEquipped(item) then
                            if rule.visible then
                                if findItem(item) then
                                    missingItem = false
                                    lastRule = rule
                                    correctEq = false
                                    setManagerStatus(rule, "equipping: " .. rule.name, "#FABD02")
                                    delay(200)
                                    return equipItem(item, slot)
                                else
                                    missingItem = true
                                    setManagerStatus(rule, "item not visible: " .. item, "#FF7777")
                                end
                            else
                                missingItem = false
                                lastRule = rule
                                correctEq = false
                                setManagerStatus(rule, "equipping by ID: " .. rule.name, "#FABD02")
                                delay(200)
                                return equipItem(item, slot)
                            end
                        end
                    end
                end

                correctEq = not missingItem and true or false
                lastRule = rule
                if correctEq then
                    setManagerStatus(rule, "active rule: " .. rule.name, "#03C04A")
                end
                -- even if nothing was done, exit function to hold rule
                return
            end


        end
    end

    missingItem = false
    correctEq = false
    lastRule = false
    setManagerStatus(nil, "no active rule", "#d7d7d7")
end)
