-- Energy Ring Bot - ULTRA FAST VERSION
setDefaultTab("tools")

local panelName = "autoERing_Ultra"
local ui = setupUI([[
Panel
  height: 142
  margin-top: 2
  background-color: #292A2A
  border: 1 black

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: Energy Ring
    height: 18
    color: #ffffff

  Panel
    id: body
    anchors.top: title.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    margin: 5

    Label
      id: labelEquip
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      color: #77D390
      text-align: center
      font: verdana-11px-rounded

    HorizontalScrollBar
      id: scrollEquip
      anchors.top: labelEquip.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      margin-top: 3
      minimum: 1
      maximum: 100
      step: 1

    Label
      id: labelRemove
      anchors.top: scrollEquip.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      margin-top: 8
      color: #ff5959
      text-align: center
      font: verdana-11px-rounded

    HorizontalScrollBar
      id: scrollRemove
      anchors.top: labelRemove.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      margin-top: 3
      minimum: 1
      maximum: 100
      step: 1

    Label
      id: labelNormal
      anchors.top: scrollRemove.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      margin-top: 8
      margin-right: 40
      color: #dfdfdf
      text-align: center
      text: Ring normal
      font: verdana-11px-rounded

    BotItem
      id: normalRing
      anchors.top: scrollRemove.bottom
      anchors.right: parent.right
      margin-top: 4
      width: 32
      height: 32
]])

if not storage[panelName] then
    storage[panelName] = { enabled = false, equipAt = 75, removeAt = 90, normalRing = 3004 }
end

local config = storage[panelName]
config.normalRing = config.normalRing or 3004
local energy_ring = 3051
local energy_ring_equiped = 3088
local safeDelay = 2000
local damageSampleMs = 250
local heavyDamagePercent = 8

local function updateLabels()
    ui.body.labelEquip:setText("Equipar Ring <= " .. config.equipAt .. "%")
    ui.body.labelRemove:setText("Quitar Ring >= " .. config.removeAt .. "%")
end

local icon

local function saveIconState(enabled)
    storage._icons = storage._icons or {}
    storage._icons.ERingIcon = storage._icons.ERingIcon or {}
    storage._icons.ERingIcon.enabled = enabled == true
end

local function updateIconVisual(widget, enabled)
    if not widget then return end
    if widget.text then widget.text:setColor(enabled and "green" or "red") end
    if widget.setColor then widget:setColor(enabled and "green" or "red") end
end

local function setEnabled(enabled, fromIcon)
    config.enabled = enabled == true
    ui.title:setOn(config.enabled)
    saveIconState(config.enabled)

    if icon then
        if not fromIcon and icon.setOn then
            syncingIcon = true
            pcall(function() icon:setOn(config.enabled) end)
            syncingIcon = false
        end
        updateIconVisual(icon, config.enabled)
    end
end

ERing = {
    isOn = function()
        return config.enabled == true
    end,
    setOn = function()
        setEnabled(true)
    end,
    setOff = function()
        setEnabled(false)
    end
}

setEnabled(config.enabled == true)

ui.title:setOn(config.enabled)
ui.title.onClick = function(widget)
    setEnabled(not config.enabled)
end

ui.body.scrollEquip:setValue(config.equipAt)
ui.body.scrollEquip.onValueChange = function(scroll, value)
    config.equipAt = value
    updateLabels()
end

ui.body.scrollRemove:setValue(config.removeAt)
ui.body.scrollRemove.onValueChange = function(scroll, value)
    config.removeAt = value
    updateLabels()
end

ui.body.normalRing:setItemId(config.normalRing)
ui.body.normalRing.onItemChange = function(widget)
    config.normalRing = widget:getItemId()
end

updateLabels()

-- MACRO ACELERADO (20ms)
local lastRingMove = 0
local lastDangerAt = now or 0
local lastHpSampleAt = now or 0
local lastHpSample = hppercent() or 100

local function canMoveRing()
    local pingDelay = g_game.getPing and g_game.getPing() * 2 or 0
    local moveDelay = math.max(pingDelay, 150)
    if now - lastRingMove < moveDelay then return false end
    lastRingMove = now
    return true
end

local function moveRingToFinger(itemId)
    if not itemId or itemId <= 0 then return false end
    local ring = findItem(itemId)
    if ring and canMoveRing() then
        g_game.move(ring, {x=65535, y=SlotFinger, z=0}, 1)
        return true
    end
    return false
end

macro(20, function()
    if not config.enabled then return end

    local finger = getFinger()
    local fingerId = finger and finger:getId() or 0
    local hp = hppercent()

    if now - lastHpSampleAt >= damageSampleMs then
        if lastHpSample - hp >= heavyDamagePercent then
            lastDangerAt = now
        end
        lastHpSample = hp
        lastHpSampleAt = now
    end

    -- Verificación de Seguridad
    if config.removeAt <= config.equipAt then
        config.removeAt = config.equipAt + 2
        ui.body.scrollRemove:setValue(config.removeAt)
    end

    -- ACCIÓN ULTRA RÁPIDA
    if hp <= config.equipAt then
        lastDangerAt = now
        if fingerId ~= energy_ring_equiped then
            moveRingToFinger(energy_ring)
        end
    else
        if fingerId == energy_ring_equiped and hp >= config.removeAt then
            -- Movimiento de regreso a cualquier mochila abierta
            if canMoveRing() then
                g_game.move(finger, {x=65535, y=SlotBack, z=0}, 1)
            end
        elseif fingerId == 0 and now - lastDangerAt >= safeDelay then
            moveRingToFinger(config.normalRing)
        end
    end
end)

UI.Separator()
