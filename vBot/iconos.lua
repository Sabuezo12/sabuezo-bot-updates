local leftX = 206
local rightX = 274
local topY = 146
local spacingY = 48

local iconList = {
  {id = "ERingIcon", text = "Ering", itemId = 3088, botScript = ERing, x = rightX, y = topY - 34, offColor = "red"},
  {id = "CavebotIcon", text = "Cave", itemId = 12548, botScript = CaveBot, x = leftX, y = topY, offColor = "white"},
  {id = "TargetIcon", text = "Target", itemId = 7438, botScript = TargetBot, x = rightX, y = topY, offColor = "white"},
  {id = "RecogeTodoIcon", text = "Recoge\nTodo", itemId = {id = 3043, count = 100}, botScript = RecogeTodo, x = leftX, y = topY + spacingY},
  {id = "AntiPushIcon", text = "Anti\nPush", itemId = {id = 3031, count = 100}, botScript = AntiPush, x = rightX, y = topY + spacingY},
  {id = "PullItemsIcon", text = "Pull\nItems", itemId = 2860, botScript = PullItems, x = leftX, y = topY + (spacingY * 2)},
  {id = "FriendHealerIcon", text = "Friend\nHeal", itemId = 3160, botScript = FriendHealer, x = rightX, y = topY + (spacingY * 2)},
  {id = "HoldTargetIcon", text = "Hold\nTarget", itemId = 3155, botScript = HoldTarget, x = rightX, y = topY + (spacingY * 3)},
  {id = "ExivaTargetIcon", text = "Exiva\nTarget", itemId = 3043, botScript = ExivaTarget, x = leftX, y = topY + (spacingY * 4)},
  {id = "ExivaLastIcon", text = "Exiva\nLast", itemId = 3035, botScript = ExivaLast, x = rightX, y = topY + (spacingY * 4)},
  {id = "AutoBuffIcon", text = "Auto\nBuff", itemId = 3064, botScript = AutoBuff, x = leftX, y = topY + (spacingY * 3)},
  {id = "FireBombIcon", text = "Fire\nBomb", itemId = 3192, botScript = FireBomb, x = leftX, y = topY + (spacingY * 5), offColor = "white"},
  {id = "BugMapIcon", text = "Bug\nMap", botScript = BugMapMouse, x = rightX, y = topY + (spacingY * 5), offColor = "white"},
  {id = "KeepWallIcon", text = "Keep\nWall", itemId = KeepWall and KeepWall.getRuneId and KeepWall.getRuneId() or 3180, botScript = KeepWall, x = leftX, y = topY + (spacingY * 6), offColor = "white"},
}

local activeIcons = {}

local function setTextColor(widget, enabled, offColor)
  local color = enabled and "green" or (offColor or "red")
  if widget and widget.text then
    widget.text:setColor(color)
  end
  if widget and widget.setColor then
    widget:setColor(color)
  end
end

local function saveIconState(id, enabled)
  storage._icons = storage._icons or {}
  storage._icons[id] = storage._icons[id] or {}
  storage._icons[id].enabled = enabled == true
end

local function styleIcon(widget)
  if not widget then return end
  widget:breakAnchors()
  widget:setSize({height = 46, width = 58})
  if widget.text then
    pcall(function() widget.text:breakAnchors() end)
    widget.text:setFont("verdana-11px-rounded")
    widget.text:setColor("red")
    pcall(function() widget.text:setTextAlign(AlignCenter) end)
    pcall(function() widget.text:setSize({height = 24, width = 58}) end)
    pcall(function() widget.text:setWidth(58) end)
    pcall(function() widget.text:setMarginLeft(0) end)
    pcall(function() widget.text:setMarginRight(0) end)
    pcall(function() widget.text:move(0, 23) end)
  end
  if widget.item then
    pcall(function() widget.item:breakAnchors() end)
    pcall(function() widget.item:setSize({height = 32, width = 32}) end)
    pcall(function() widget.item:setMarginTop(0) end)
    pcall(function() widget.item:setMarginLeft(13) end)
    pcall(function() widget.item:setMarginRight(13) end)
    pcall(function() widget.item:move(13, 0) end)
    pcall(function() widget.item:lower() end)
  end
end

for index, data in ipairs(iconList) do
  if data.botScript then
    local initialEnabled = false
    local okState, result = pcall(function()
      return data.botScript.isOn and data.botScript.isOn()
    end)
    initialEnabled = okState and result == true

    local guard = { booting = true, syncing = false }
    local params = {
      text = data.text,
      switchable = true
    }
    if data.itemId then
      params.item = data.itemId
    end

    local ok, widget = pcall(function()
      return addIcon(data.id, params, function(icon, on)
        if guard.booting or guard.syncing then
          setTextColor(icon, initialEnabled, data.offColor)
          return
        end
        if on then
          if data.botScript.setOn then data.botScript.setOn() end
        else
          if data.botScript.setOff then data.botScript.setOff() end
        end
        saveIconState(data.id, on)
        setTextColor(icon, on, data.offColor)
      end)
    end)
    guard.booting = false

    if ok and widget then
      styleIcon(widget)
      widget:move(data.x, data.y)
      guard.syncing = true
      if widget.setOn then
        pcall(function() widget:setOn(initialEnabled) end)
      end
      guard.syncing = false
      saveIconState(data.id, initialEnabled)
      setTextColor(widget, initialEnabled, data.offColor)

      table.insert(activeIcons, {
        widget = widget,
        botScript = data.botScript,
        offColor = data.offColor,
        id = data.id,
        guard = guard
      })
    else
      warn("[Pruebas Icons] No se pudo crear: " .. data.id)
    end
  else
    warn("[Pruebas Icons] Script no encontrado: " .. data.id)
  end
end

macro(200, function()
  for _, data in ipairs(activeIcons) do
    local widget = data.widget
    local script = data.botScript
    local enabled = false

    if script and script.isOn then
      local ok, result = pcall(script.isOn)
      enabled = ok and result == true
    end

    if widget and widget.isOn and widget:isOn() ~= enabled then
      data.guard.syncing = true
      pcall(function() widget:setOn(enabled) end)
      data.guard.syncing = false
      saveIconState(data.id, enabled)
    end
    setTextColor(widget, enabled, data.offColor)
  end
end)
