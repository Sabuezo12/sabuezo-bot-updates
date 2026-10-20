local leftX = 206
local rightX = 274
local topY = 146
local spacingY = 48
local iconWidth = 58
local iconHeight = 46
local barWidth = 104
local barHeight = 26
local textAlignCenter = 48

local iconList = {
  {id = "ERingIcon", text = "Ering", itemId = 3088, botScript = ERing, x = leftX, y = topY - spacingY, offColor = "#ff3b3b"},
  {id = "InmortalIcon", text = "Inmortal", itemId = 3081, botScript = Inmortal, x = rightX, y = topY - spacingY, offColor = "#ff3b3b"},
  {id = "CavebotIcon", text = "Cave", itemId = 12548, botScript = CaveBot, x = leftX, y = topY, offColor = "#ffffff"},
  {id = "TargetIcon", text = "Target", itemId = 7438, botScript = TargetBot, x = rightX, y = topY, offColor = "#ffffff"},
  {id = "RecogeTodoIcon", text = "Recoge\nTodo", itemId = {id = 3043, count = 100}, botScript = RecogeTodo, x = leftX, y = topY + spacingY},
  {id = "AntiPushIcon", text = "Anti\nPush", itemId = {id = 3031, count = 100}, botScript = AntiPush, x = rightX, y = topY + spacingY},
  {id = "PullItemsIcon", text = "Pull\nItems", itemId = 2860, botScript = PullItems, x = leftX, y = topY + (spacingY * 2)},
  {id = "FriendHealerIcon", text = "Friend\nHeal", itemId = 3160, botScript = FriendHealer, x = rightX, y = topY + (spacingY * 2)},
  {id = "AutoBuffIcon", text = "Auto\nBuff", itemId = 3064, botScript = AutoBuff, x = leftX, y = topY + (spacingY * 3)},
  {id = "HoldTargetIcon", text = "Hold\nTarget", itemId = 3155, botScript = HoldTarget, x = rightX, y = topY + (spacingY * 3)},
  {id = "ExivaTargetIcon", text = "Exiva\nTarget", itemId = 3043, botScript = ExivaTarget, x = leftX, y = topY + (spacingY * 4)},
  {id = "ExivaLastIcon", text = "Exiva\nLast", itemId = 3035, botScript = ExivaLast, x = rightX, y = topY + (spacingY * 4)},
  {id = "FireBombIcon", text = "Fire\nBomb", itemId = 3192, botScript = FireBomb, x = leftX, y = topY + (spacingY * 5), offColor = "#ffffff"},
  {id = "BugMapIcon", text = "Bug\nMap", botScript = BugMapMouse, x = rightX, y = topY + (spacingY * 5), offColor = "#ffffff"},
  {id = "KeepWallIcon", text = "Keep\nWall", itemId = KeepWall and KeepWall.getRuneId and KeepWall.getRuneId() or 3180, botScript = KeepWall, x = leftX, y = topY + (spacingY * 6), offColor = "#ffffff"},
  {id = "TimerExecutorIcon", text = "Timer", itemId = 3053, botScript = TimerExecutor, x = rightX, y = topY + (spacingY * 6), offColor = "#ffffff"},
  {id = "AlarmsIcon", text = "Alarmas", itemId = 3456, botScript = Alarms, x = leftX, y = topY + (spacingY * 7), offColor = "#ff3b3b"},
  {id = "SpyLevelIcon", text = "Spy\nLevel", itemId = 3055, botScript = SpyLevelBridge, x = rightX, y = topY + (spacingY * 7), offColor = "#ffffff", action = true},
}

local layoutDefaults = {
  originX = leftX,
  originY = topY - spacingY,
  columns = 2,
  gapX = rightX - leftX,
  gapY = spacingY,
  gridSize = 2,
  snapEnabled = true,
  visualMode = "classic",
  barOpacity = 70,
  holdToMove = false
}

if type(storage.iconEditor) ~= "table" then storage.iconEditor = {} end
local editorConfig = storage.iconEditor
if type(editorConfig.icons) ~= "table" then editorConfig.icons = {} end
if type(editorConfig.layout) ~= "table" then editorConfig.layout = {} end

for key, value in pairs(layoutDefaults) do
  if editorConfig.layout[key] == nil then editorConfig.layout[key] = value end
end

local function effectiveVisualMode(entry)
  local mode = entry and entry.config and entry.config.visualMode or nil
  if mode == "bar" or mode == "classic" then return mode end
  return editorConfig.layout.visualMode == "bar" and "bar" or "classic"
end

local function isBarMode(entry)
  return effectiveVisualMode(entry) == "bar"
end

local function currentIconWidth(entry)
  return isBarMode(entry) and barWidth or iconWidth
end

local function currentIconHeight(entry)
  return isBarMode(entry) and barHeight or iconHeight
end

local activeIcons = {}
local iconById = {}
local editorRows = {}
local editorWindow
local selectedEntry
local selectedOnColor = "#00d43a"
local selectedOffColor = "#ff3b3b"
local editMode = false
local moveMode = "none"
local syncingSelectedControls = false
local syncingLayoutControls = false
local selectEditorEntry
local refreshEditorList

vBot = vBot or {}
vBot.IconPositionGeneration = (vBot.IconPositionGeneration or 0) + 1
local positionGeneration = vBot.IconPositionGeneration

local function liveIconWidget(widget)
  if not widget then return false end
  local ok, destroyed = pcall(function() return widget:isDestroyed() end)
  return not ok or not destroyed
end

-- addIcon creates a child of gameMapPanel. Its children translate when the
-- login sidebars/top bar move that panel, but the editor stores window pixels.
-- Use the same coordinate space for the icon and its saved position.
local function attachIconToWindow(widget)
  local root = g_ui and g_ui.getRootWidget and g_ui.getRootWidget() or nil
  if not root or not liveIconWidget(widget) then return false end
  local ok = pcall(function()
    widget.botWidget = true -- native bot cleanup also removes root children
    if widget:getParent() ~= root then widget:setParent(root, true) end
    widget:breakAnchors()
    widget:setMarginTop(0)
    widget:setMarginLeft(0)
    widget:setMarginRight(0)
    widget:setMarginBottom(0)
  end)
  return ok
end

local function clamp(value, minimum, maximum)
  value = tonumber(value) or minimum
  if value < minimum then return minimum end
  if maximum and value > maximum then return maximum end
  return value
end

local function barBackgroundColor()
  local opacity = clamp(editorConfig.layout.barOpacity, 10, 100)
  local alpha = math.floor((opacity * 255 / 100) + 0.5)
  return string.format("#181818%02x", alpha)
end

local function roundToGrid(value)
  local gridSize = math.max(1, tonumber(editorConfig.layout.gridSize) or 1)
  return math.floor((tonumber(value) or 0) / gridSize + 0.5) * gridSize
end

local function defaultItemId(data)
  if type(data.itemId) == "table" then return tonumber(data.itemId.id) or 0 end
  return tonumber(data.itemId) or 0
end

local function getIconConfig(id)
  if type(editorConfig.icons[id]) ~= "table" then editorConfig.icons[id] = {} end
  return editorConfig.icons[id]
end

local function effectiveText(entry)
  local text = entry.config.text
  if type(text) ~= "string" or text == "" then return entry.defaults.text end
  return text
end

local function effectiveItemId(entry)
  local configured = tonumber(entry.config.itemId)
  if configured ~= nil then return math.max(0, configured) end
  return defaultItemId(entry.defaults)
end

local function effectiveX(entry)
  return math.floor(tonumber(entry.config.x) or tonumber(entry.defaults.x) or 0)
end

local function effectiveY(entry)
  return math.floor(tonumber(entry.config.y) or tonumber(entry.defaults.y) or 0)
end

local function effectiveOnColor(entry)
  return tostring(entry.config.onColor or "#00d43a")
end

local function effectiveOffColor(entry)
  return tostring(entry.config.offColor or entry.defaults.offColor or "#ff3b3b")
end

local function isIconVisible(entry)
  return entry.config.visible ~= false
end

local function canDragEntry(entry)
  if not isIconVisible(entry) then return false end
  if editMode then
    if moveMode == "group" then return true end
    return moveMode == "selected" and entry == selectedEntry
  end
  return editorConfig.layout.holdToMove == true
end

-- The bot executor does not expose all application globals. Mouse buttons
-- are 1/2 in the client; use exported names only when they are available.
local leftMouseButton = MouseLeftButton or 1
local rightMouseButton = MouseRightButton or 2
local function currentIconRuntime(entry)
  return positionGeneration == vBot.IconPositionGeneration and liveIconWidget(entry.widget)
end
local function canStartDrag(entry)
  if not currentIconRuntime(entry) or not canDragEntry(entry) then return false end
  if editMode then return true end
  local gesture = entry.gesture
  return gesture and gesture.pressed and gesture.button == leftMouseButton
end

local iconModules = {
  InmortalIcon="inmortal", CavebotIcon="cavebot", TargetIcon="targetbot",
  RecogeTodoIcon="recoge", AntiPushIcon="antipush1", PullItemsIcon="pullitems",
  FriendHealerIcon="friend_healer", AutoBuffIcon="zautobuff",
  ExivaTargetIcon="exivatarget", ExivaLastIcon="exivalast", FireBombIcon="firebomb",
  BugMapIcon="bugmapmouse", KeepWallIcon="keepwall", TimerExecutorIcon="timerexecutor",
  SpyLevelIcon="spy_level", AlarmsIcon="alarms"
}
local function openIconConfiguration(entry)
  local id = iconModules[entry.id]
  if not id then return false end -- Hold Target is intentionally toggle-only.
  if Helper and Helper.valid and Helper.valid() then
    if type(Helper.openIconConfiguration)=="function" then return Helper.openIconConfiguration(id) end
    if Helper.openModule then Helper.openModule(id);return true end
  end
  return false
end

local function readScriptState(script)
  if not script or not script.isOn then return false end
  local ok, enabled = pcall(script.isOn)
  return ok and enabled == true
end

local function setWidgetPosition(widget, x, y)
  if not widget then return end

  x = math.max(0, math.floor(tonumber(x) or 0))
  y = math.max(0, math.floor(tonumber(y) or 0))
  local widgetWidth = currentIconWidth()
  local widgetHeight = currentIconHeight()
  pcall(function() widgetWidth = tonumber(widget:getWidth()) or widgetWidth end)
  pcall(function() widgetHeight = tonumber(widget:getHeight()) or widgetHeight end)

  local root = g_ui and g_ui.getRootWidget and g_ui.getRootWidget() or nil
  if root then
    local okWidth, rootWidth = pcall(function() return root:getWidth() end)
    local okHeight, rootHeight = pcall(function() return root:getHeight() end)
    rootWidth = tonumber(rootWidth)
    rootHeight = tonumber(rootHeight)
    if okWidth and rootWidth and rootWidth > widgetWidth then
      x = math.min(x, rootWidth - widgetWidth)
    end
    if okHeight and rootHeight and rootHeight > widgetHeight then
      y = math.min(y, rootHeight - widgetHeight)
    end
  end

  pcall(function() widget:breakAnchors() end)
  local positioned = false
  if widget.move then
    positioned = pcall(function() widget:move(x, y) end)
  end
  if not positioned and widget.setPosition then
    pcall(function() widget:setPosition({x = x, y = y}) end)
  end
  return {x = x, y = y}
end

local function getWidgetPosition(widget)
  if not widget then return nil end

  if widget.getX and widget.getY then
    local ok, x, y = pcall(function() return widget:getX(), widget:getY() end)
    x = tonumber(x)
    y = tonumber(y)
    if ok and x and y then return {x = math.floor(x), y = math.floor(y)} end
  end

  if not widget.getPosition then return nil end
  local ok, position = pcall(function() return widget:getPosition() end)
  if not ok or not position then return nil end
  local x = tonumber(position.x)
  local y = tonumber(position.y)
  if not x or not y then return nil end
  return {x = math.floor(x), y = math.floor(y)}
end

local function findOverlappingIcon(entry, x, y, visible)
  if visible == false then return nil end
  local widgetWidth = currentIconWidth(entry)
  local widgetHeight = currentIconHeight(entry)

  for _, other in ipairs(activeIcons) do
    if other ~= entry and isIconVisible(other) then
      local otherPosition = getWidgetPosition(other.widget) or {
        x = effectiveX(other),
        y = effectiveY(other)
      }
      local otherWidth = currentIconWidth(other)
      local otherHeight = currentIconHeight(other)
      if x < otherPosition.x + otherWidth and x + widgetWidth > otherPosition.x and
        y < otherPosition.y + otherHeight and y + widgetHeight > otherPosition.y then
        return other
      end
    end
  end

  return nil
end

local function setTextColor(entry, enabled)
  if not entry or not entry.widget then return end
  local color = enabled and effectiveOnColor(entry) or effectiveOffColor(entry)
  local widget = entry.widget
  local themed=RinoSkin and RinoSkin.prefix and RinoSkin.floating
  if widget.text and not themed then pcall(function() widget.text:setColor(color) end) end
  if isBarMode(entry) and not themed then
    pcall(function() widget:setBackgroundColor(barBackgroundColor()) end)
    pcall(function() widget:setBorderColor(color) end)
  elseif widget.setColor and not themed then
    pcall(function() widget:setColor(color) end)
  end
  if themed then RinoSkin.floating(widget,entry,enabled,isBarMode(entry)) end
end

local function saveIconState(id, enabled)
  storage._icons = storage._icons or {}
  storage._icons[id] = storage._icons[id] or {}
  storage._icons[id].enabled = enabled == true
end

local function syncIconSwitch(widget, enabled)
  -- addIcon overrides setOn with a Lua function on some clients. Update the
  -- native status widget directly to avoid different dot/colon conventions.
  if widget.status and widget.status.setOn then
    pcall(function() widget.status:setOn(enabled == true) end)
  elseif widget.setOn then
    pcall(function() widget:setOn(enabled == true) end)
  end
end

local function styleIcon(widget, entry)
  if not widget then return end
  local barMode = isBarMode(entry)
  local widgetWidth = currentIconWidth(entry)
  local widgetHeight = currentIconHeight(entry)
  pcall(function() widget:breakAnchors() end)
  pcall(function() widget:setSize({height = widgetHeight, width = widgetWidth}) end)
  pcall(function() widget:setBackgroundColor(barMode and barBackgroundColor() or "alpha") end)
  pcall(function() widget:setBorderWidth(barMode and 1 or 0) end)

  if widget.text then
    pcall(function() widget.text:breakAnchors() end)
    pcall(function() widget.text:setFont("verdana-11px-rounded") end)
    pcall(function() widget.text:setTextAlign(textAlignCenter) end)
    pcall(function() widget.text:setTextWrap(false) end)
    pcall(function() widget.text:setTextOffset({x = 0, y = 0}) end)
    pcall(function() widget.text:setMarginLeft(0) end)
    pcall(function() widget.text:setMarginRight(0) end)
    pcall(function() widget.text:setMarginTop(0) end)
    pcall(function() widget.text:setMarginBottom(0) end)
    if barMode then
      pcall(function() widget.text:setTextAutoResize(false) end)
      pcall(function() widget.text:setTextHorizontalAutoResize(false) end)
      pcall(function() widget.text:setTextVerticalAutoResize(false) end)
      pcall(function() widget.text:setSize({height = widgetHeight, width = widgetWidth}) end)
      pcall(function() widget.text:addAnchor(AnchorLeft, "parent", AnchorLeft) end)
      pcall(function() widget.text:addAnchor(AnchorRight, "parent", AnchorRight) end)
      pcall(function() widget.text:addAnchor(AnchorTop, "parent", AnchorTop) end)
      pcall(function() widget.text:addAnchor(AnchorBottom, "parent", AnchorBottom) end)
    else
      pcall(function() widget.text:setTextAutoResize(true) end)
      pcall(function() widget.text:addAnchor(AnchorHorizontalCenter, "parent", AnchorHorizontalCenter) end)
      pcall(function() widget.text:addAnchor(AnchorBottom, "parent", AnchorBottom) end)
    end
    pcall(function() widget.text:raise() end)
  end

  if widget.item then
    pcall(function() widget.item:setVisible(not barMode) end)
    if not barMode then
      pcall(function() widget.item:breakAnchors() end)
      pcall(function() widget.item:setSize({height = 32, width = 32}) end)
      pcall(function() widget.item:setMarginTop(0) end)
      pcall(function() widget.item:setMarginLeft(0) end)
      pcall(function() widget.item:setMarginRight(0) end)
      pcall(function() widget.item:addAnchor(AnchorTop, "parent", AnchorTop) end)
      pcall(function() widget.item:addAnchor(AnchorHorizontalCenter, "parent", AnchorHorizontalCenter) end)
      pcall(function() widget.item:raise() end)
      if widget.text then pcall(function() widget.text:raise() end) end
    end
  end
  if RinoSkin and RinoSkin.prefix and RinoSkin.floating then
    entry.rinoSkinSignature=nil
    RinoSkin.floating(widget,entry,readScriptState(entry.botScript),barMode)
  end
end

local function setIconDraggable(entry, enabled)
  if not entry then return end
  entry.dragEnabled = enabled == true
  entry.widget:setDraggable(entry.dragEnabled)
  local tooltip = "Clic izquierdo: activar o desactivar"
  if iconModules[entry.id] then tooltip = tooltip .. "\nClic derecho: abrir configuracion" end
  if editorConfig.layout.holdToMove == true then
    tooltip = tooltip .. "\nArrastrar: mover icono (sin espera)"
  end
  entry.widget:setTooltip(tooltip)
end

local function applyIconVisual(entry, includePosition, keepSavedPosition)
  if not entry or not entry.widget then return end
  local widget = entry.widget

  if widget.text then
    local text = effectiveText(entry)
    if isBarMode(entry) then text = text:gsub("\n", " ") end
    pcall(function() widget.text:setText(text) end)
    pcall(function() widget.text:setTextAlign(textAlignCenter) end)
  end

  if widget.item then
    pcall(function() widget.item:setItemId(effectiveItemId(entry)) end)
    -- Explicit virtual preview: rune/stackable subtypes and item visibility
    -- must not depend on the previous UIItem state or on a texture background.
    local previewCount=type(entry.defaults.itemId)=='table' and tonumber(entry.defaults.itemId.count) or 1
    pcall(function() widget.item:setItemCount(math.max(1,previewCount or 1)) end)
    pcall(function() widget.item:setItemVisible(true) end)
    pcall(function() widget.item:setShowCount(false) end)
  end

  pcall(function() widget:setVisible(isIconVisible(entry)) end)
  if entry.id == "AlarmsIcon" and type(entry.botScript.setIconVisible) == "function" then
    entry.botScript.setIconVisible(isIconVisible(entry))
  end
  setIconDraggable(entry, canDragEntry(entry))

  if includePosition ~= false then
    local position = setWidgetPosition(widget, effectiveX(entry), effectiveY(entry))
    if position and not keepSavedPosition then
      entry.config.x = position.x
      entry.config.y = position.y
    end
  end

  setTextColor(entry, readScriptState(entry.botScript))
end

local function saveDraggedPosition(entry)
  if not entry then return end
  local position = getWidgetPosition(entry.widget)
  if not position then return end

  if editorConfig.layout.snapEnabled ~= false then
    position.x = roundToGrid(position.x)
    position.y = roundToGrid(position.y)
  end

  -- Manual drops keep the chosen position, even when hit boxes overlap.
  -- Persist the final clamped/snapped pixels, not the previous layout origin.
  position = setWidgetPosition(entry.widget, position.x, position.y) or position
  entry.config.x = position.x
  entry.config.y = position.y

  local row = editorRows[entry.id]
  if row and row.coords then
    row.coords:setText(position.x .. ", " .. position.y)
  end

  if selectedEntry == entry and editorWindow then
    syncingSelectedControls = true
    editorWindow.selectedX:setValue(position.x)
    editorWindow.selectedY:setValue(position.y)
    syncingSelectedControls = false
    editorWindow.iconStatus:setText("Posicion guardada")
    editorWindow.iconStatus:setColor("#8cff9a")
  end
end

for _, data in ipairs(iconList) do
  if data.botScript then
    local initialEnabled = readScriptState(data.botScript)
    local guard = {booting = true, syncing = false}
    local config = getIconConfig(data.id)
    if data.id == "AlarmsIcon" and config.visible == nil and type(data.botScript.isIconVisible) == "function" then
      config.visible = data.botScript.isIconVisible()
    end
    local entry
    local params = {
      text = type(config.text) == "string" and config.text ~= "" and config.text or data.text,
      switchable = data.action ~= true,
      movable = false
    }

    local configuredItem = tonumber(config.itemId)
    if configuredItem ~= nil then
      params.item = math.max(0, configuredItem)
    else
      params.item = data.itemId or 0
    end

    local ok, widget = pcall(function()
      return addIcon(data.id, params, function(icon, on)
        if data.action then return end
        if guard.booting or guard.syncing then
          if entry then setTextColor(entry, initialEnabled) end
          return
        end

        if editMode then
          local actualEnabled = readScriptState(data.botScript)
          guard.syncing = true
          syncIconSwitch(icon, actualEnabled)
          guard.syncing = false
          saveIconState(data.id, actualEnabled)
          if entry then
            setTextColor(entry, actualEnabled)
            if selectEditorEntry then selectEditorEntry(entry) end
          end
          return
        end

        if on then
          if data.botScript.setOn then data.botScript.setOn() end
        else
          if data.botScript.setOff then data.botScript.setOff() end
        end
        saveIconState(data.id, on)
        if entry then setTextColor(entry, on) end
      end)
    end)
    guard.booting = false

    if ok and widget then
      entry = {
        id = data.id,
        defaults = data,
        config = config,
        widget = widget,
        botScript = data.botScript,
        guard = guard,
        dragEnabled = false
      }

      table.insert(activeIcons, entry)
      iconById[entry.id] = entry
      if entry.id == "AlarmsIcon" then
        -- Hand off only after successful creation; the legacy access stays a fallback.
        if type(entry.botScript.manageIcon) == "function" then entry.botScript.manageIcon() end
        entry.botScript.onIconVisibilityChange = function(value)
          entry.config.visible = value == true
          applyIconVisual(entry, false)
          if refreshEditorList then refreshEditorList() end
        end
      end

      widget.onGeometryChange = function() end
      attachIconToWindow(widget)
      styleIcon(widget, entry)

      widget.onDragEnter = function(changedWidget, mousePos)
        if not canStartDrag(entry) then return false end
        if entry.gesture then entry.gesture.dragged = true end
        local press = not editMode and entry.gesture and entry.gesture.position
        mousePos = press or mousePos

        changedWidget:breakAnchors()
        changedWidget.movingReference = {
          x = mousePos.x - changedWidget:getX(),
          y = mousePos.y - changedWidget:getY()
        }
        changedWidget.dragGroup = {
          x = changedWidget:getX(),
          y = changedWidget:getY(),
          entries = {},
          minX = nil,
          minY = nil,
          maxRight = nil,
          maxBottom = nil,
          layoutOriginX = tonumber(editorConfig.layout.originX) or layoutDefaults.originX,
          layoutOriginY = tonumber(editorConfig.layout.originY) or layoutDefaults.originY,
          deltaX = 0,
          deltaY = 0
        }

        local dragEntries = moveMode == "group" and activeIcons or {entry}
        for _, draggedEntry in ipairs(dragEntries) do
          local draggedWidget = draggedEntry.widget
          local position = getWidgetPosition(draggedWidget)
          if draggedWidget and position then
            pcall(function() draggedWidget:breakAnchors() end)
            local captured = {
              entry = draggedEntry,
              widget = draggedWidget,
              x = position.x,
              y = position.y,
              children = {}
            }

            for _, child in ipairs({draggedWidget.text, draggedWidget.item}) do
              if child then
                local childPosition = getWidgetPosition(child)
                if childPosition then
                  pcall(function() child:breakAnchors() end)
                  table.insert(captured.children, {
                    widget = child,
                    x = childPosition.x,
                    y = childPosition.y
                  })
                end
              end
            end

            table.insert(changedWidget.dragGroup.entries, captured)
            changedWidget.dragGroup.minX = math.min(changedWidget.dragGroup.minX or position.x, position.x)
            changedWidget.dragGroup.minY = math.min(changedWidget.dragGroup.minY or position.y, position.y)
            changedWidget.dragGroup.maxRight = math.max(changedWidget.dragGroup.maxRight or 0, position.x + draggedWidget:getWidth())
            changedWidget.dragGroup.maxBottom = math.max(changedWidget.dragGroup.maxBottom or 0, position.y + draggedWidget:getHeight())
          end
        end
        if selectEditorEntry then selectEditorEntry(entry) end
        return true
      end

      widget.onDragMove = function(changedWidget, mousePos)
        if not entry.dragEnabled or not changedWidget.movingReference then return false end

        local root = g_ui.getRootWidget()
        local rootWidth = root and tonumber(root:getWidth()) or 0
        local rootHeight = root and tonumber(root:getHeight()) or 0
        local group = changedWidget.dragGroup
        if not group then return false end
        local desiredX = mousePos.x - changedWidget.movingReference.x
        local desiredY = mousePos.y - changedWidget.movingReference.y
        local deltaX = desiredX - group.x
        local deltaY = desiredY - group.y

        deltaX = math.max(-(group.minX or 0), deltaX)
        deltaY = math.max(-(group.minY or 0), deltaY)
        if rootWidth > 0 then
          deltaX = math.min(rootWidth - (group.maxRight or rootWidth), deltaX)
        end
        if rootHeight > 0 then
          deltaY = math.min(rootHeight - (group.maxBottom or rootHeight), deltaY)
        end

        group.deltaX = math.floor(deltaX)
        group.deltaY = math.floor(deltaY)
        for _, captured in ipairs(group.entries) do
          local x = captured.x + group.deltaX
          local y = captured.y + group.deltaY
          pcall(function() captured.widget:move(x, y) end)
          for _, child in ipairs(captured.children) do
            pcall(function() child.widget:move(child.x + group.deltaX, child.y + group.deltaY) end)
          end

          local row = editorRows[captured.entry.id]
          if row and row.coords then row.coords:setText(x .. ", " .. y) end
          if selectedEntry == captured.entry and editorWindow then
            syncingSelectedControls = true
            editorWindow.selectedX:setValue(x)
            editorWindow.selectedY:setValue(y)
            syncingSelectedControls = false
            editorWindow.iconStatus:setText("X: " .. x .. "   Y: " .. y)
            editorWindow.iconStatus:setColor("#ffd166")
          end
        end

        if moveMode == "group" and editorWindow then
          syncingLayoutControls = true
          editorWindow.originX:setValue(group.layoutOriginX + group.deltaX)
          editorWindow.originY:setValue(group.layoutOriginY + group.deltaY)
          syncingLayoutControls = false
        end
        return true
      end

      widget.onDragLeave = function(changedWidget)
        if not changedWidget.movingReference then return false end
        local group = changedWidget.dragGroup
        changedWidget.movingReference = nil
        if group then
          for _, captured in ipairs(group.entries) do
            saveDraggedPosition(captured.entry)
            styleIcon(captured.widget, captured.entry)
            applyIconVisual(captured.entry, false)
          end

          if moveMode == "group" then
            local originX = group.layoutOriginX + group.deltaX
            local originY = group.layoutOriginY + group.deltaY
            if editorConfig.layout.snapEnabled ~= false then
              originX = roundToGrid(originX)
              originY = roundToGrid(originY)
            end
            editorConfig.layout.originX = math.max(0, originX)
            editorConfig.layout.originY = math.max(0, originY)
            if editorWindow then
              syncingLayoutControls = true
              editorWindow.originX:setValue(editorConfig.layout.originX)
              editorWindow.originY:setValue(editorConfig.layout.originY)
              syncingLayoutControls = false
              editorWindow.iconStatus:setText("Conjunto movido")
              editorWindow.iconStatus:setColor("#8cff9a")
            end
          end
        end
        changedWidget.dragGroup = nil
        if entry.gesture then entry.gesture.pressed = false end
        return true
      end

      -- Left release toggles; right press opens the original configuration.
      -- Native drag completion consumes the left click; suppress it as well
      -- when a client sends onClick after moving. No timers or hold threshold.
      local nativeClick = widget.onClick
      local function toggleIcon()
        if not currentIconRuntime(entry) or editMode then return end
        entry.guard.syncing = true
        syncIconSwitch(widget, readScriptState(entry.botScript))
        entry.guard.syncing = false
        if data.action then
          if type(entry.botScript.stepUp)=="function" then entry.botScript.stepUp() end
        elseif nativeClick then nativeClick(widget) end
      end
      if data.action and widget.setTooltip then
        widget:setTooltip("Spy Level: clic izquierdo sube, derecho baja. Mover iconos permite arrastrar.")
      end
      widget.onDoubleClick = function() return false end
      widget.onMousePress = function(changedWidget, mousePos, mouseButton)
        if not currentIconRuntime(entry) then return true end
        if mouseButton == rightMouseButton then
          if changedWidget.dragGroup then changedWidget.onDragLeave(changedWidget) end
          entry.gesture = {cancelled=true, pressed=false, button=rightMouseButton}
          if data.action then
            if editMode then
              if selectEditorEntry then selectEditorEntry(entry) end
            elseif type(entry.botScript.stepDown)=="function" then entry.botScript.stepDown() end
          else openIconConfiguration(entry) end
          return true
        end
        if mouseButton ~= leftMouseButton then return true end
        entry.gesture = {position={x=mousePos.x,y=mousePos.y},
          pressed=true, button=leftMouseButton, editing=editMode}
        if editMode and selectEditorEntry then selectEditorEntry(entry) end
        return true
      end
      widget.onMouseMove = function(changedWidget, mousePos)
        local gesture = entry.gesture
        if gesture and gesture.pressed then
          local dx,dy = mousePos.x-gesture.position.x,mousePos.y-gesture.position.y
          if dx*dx+dy*dy >= 16 then gesture.moved = true end
        end
        return true
      end
      widget.onMouseRelease = function(changedWidget, mousePos, mouseButton)
        if mouseButton ~= leftMouseButton then return true end
        if entry.gesture then entry.gesture.pressed = false end
        return true
      end
      widget.onClick = function(changedWidget)
        local gesture = entry.gesture
        entry.gesture = nil
        if not currentIconRuntime(entry) then return true end
        if gesture and (gesture.cancelled or gesture.button == rightMouseButton or gesture.editing or gesture.dragged or gesture.moved) then return true end
        toggleIcon()
        return true
      end

      -- A provisional login window can clamp the visible icon. Retain the
      -- requested coordinates so a later full-size window restores them.
      applyIconVisual(entry, true, true)
      guard.syncing = true
      syncIconSwitch(widget, initialEnabled)
      guard.syncing = false
      saveIconState(data.id, initialEnabled)
      setTextColor(entry, initialEnabled)
      setIconDraggable(entry, canDragEntry(entry))
    else
      warn("[Icon Editor] No se pudo crear: " .. data.id)
    end
  else
    print("[Icon Editor] Script no encontrado: " .. data.id)
  end
end

-- The editor changes presentation only; engine click/state/drag code stays native.
local function editorText(text) return tostring(text or ""):gsub("\n", " / ") end
local function iconText(text)
  return tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s*/%s*", "\n")
end
local function clone(value)
  if type(value) ~= "table" then return value end
  local result = {}; for key, item in pairs(value) do result[key] = clone(item) end
  return result
end
local undoState, changeKey, currentPage, syncingMovement = nil, nil, "icon", false
local fillSelectedEditor, fillLayoutControls, updatePreview, showPage
if editorConfig.layout.visibleOnly == nil then editorConfig.layout.visibleOnly = true end
local function status(message, color)
  if not editorWindow then return end
  editorWindow.iconStatus:setText(message)
  editorWindow.iconStatus:setColor(color or "#a9bbc6")
end
local function remember(key, force)
  if not force and key == changeKey then return end
  undoState = {icons=clone(editorConfig.icons), layout=clone(editorConfig.layout)}
  changeKey = key
  if editorWindow then editorWindow.undo:setEnabled(true) end
end
local function setPreviewColor(widget, color) if widget then widget:setBackgroundColor(color) end end
local function updateRow(entry)
  local row = entry and editorRows[entry.id]
  if not row then return end
  row.visible:setChecked(isIconVisible(entry)); row.item:setItemId(effectiveItemId(entry))
  row.name:setText(effectiveText(entry):gsub("\n", " "))
  row.coords:setText(effectiveX(entry) .. ", " .. effectiveY(entry))
  row.name:setColor(isIconVisible(entry) and "#e4edf3" or "#87979e")
  row:setBackgroundColor(entry == selectedEntry and "#1b4650" or "alpha")
  row:setTooltip(effectiveText(entry):gsub("\n", " ") .. " | X: " .. effectiveX(entry) .. " Y: " .. effectiveY(entry))
end
local lastPreview
updatePreview = function()
  if not editorWindow or not selectedEntry then return end
  local entry = selectedEntry
  local name = effectiveText(entry):gsub("\n", " ")
  local mode = effectiveVisualMode(entry)
  local signature = entry.id .. name .. mode .. effectiveItemId(entry) .. effectiveOnColor(entry) .. effectiveOffColor(entry) .. barBackgroundColor()
  if signature == lastPreview then return end
  lastPreview = signature
  for _, sample in ipairs({{editorWindow.previewOn,effectiveOnColor(entry)}, {editorWindow.previewOff,effectiveOffColor(entry)}}) do
    local w, color = sample[1], sample[2]
    w.item:setItemId(effectiveItemId(entry)); w.item:setVisible(mode ~= "bar")
    w.name:setText(name); w.name:setColor(color)
    w.name:setMarginBottom(mode == "bar" and 20 or 2)
    w:setBackgroundColor(mode == "bar" and barBackgroundColor() or "#0f1920")
    w:setBorderColor(color)
  end
end
fillSelectedEditor = function(entry)
  if not editorWindow or not entry then return end
  selectedOnColor, selectedOffColor = effectiveOnColor(entry), effectiveOffColor(entry)
  syncingSelectedControls = true
  editorWindow.selectedName:setText(editorText(effectiveText(entry)))
  editorWindow.selectedItem:setItemId(effectiveItemId(entry))
  editorWindow.selectedVisible:setChecked(isIconVisible(entry))
  editorWindow.selectedX:setValue(effectiveX(entry)); editorWindow.selectedY:setValue(effectiveY(entry))
  editorWindow.selectedVisualMode:setOption(entry.config.visualMode == "bar" and "Barra" or entry.config.visualMode == "classic" and "Icono" or "Del conjunto")
  editorWindow.onColorHex:setText(selectedOnColor); editorWindow.offColorHex:setText(selectedOffColor)
  syncingSelectedControls = false
  setPreviewColor(editorWindow.onColorPreview,selectedOnColor); setPreviewColor(editorWindow.offColorPreview,selectedOffColor)
  if currentPage == "icon" then editorWindow.selectedTitle:setText(effectiveText(entry):gsub("\n", " ")) end
  updatePreview()
end
selectEditorEntry = function(entry)
  if not entry then return end
  if selectedEntry ~= entry then changeKey = nil end
  local prior = selectedEntry; selectedEntry = entry
  fillSelectedEditor(entry); updateRow(prior); updateRow(entry)
  if moveMode == "selected" then
    for _, candidate in ipairs(activeIcons) do setIconDraggable(candidate,canDragEntry(candidate)) end
  end
  if editorRows[entry.id] then editorRows[entry.id]:focus() end
end
refreshEditorList = function()
  if not editorWindow then return end
  local query = editorWindow.search:getText():lower():gsub("^%s+", ""):gsub("%s+$", "")
  local matches = 0
  for _, entry in ipairs(activeIcons) do
    local row = editorRows[entry.id]
    if not row then
      row = g_ui.createWidget("IconEditorRow",editorWindow.iconList)
      if HelperTheme then HelperTheme.tooltips(row) end
      row:setId("iconEditorRow" .. entry.id); editorRows[entry.id] = row
      row.onClick = function() selectEditorEntry(entry); return true end
      row.onDoubleClick = function() showPage("icon"); selectEditorEntry(entry); editorWindow.selectedName:focus(); return true end
      row.visible.onClick = function()
        remember("visible:" .. entry.id,true)
        entry.config.visible = not isIconVisible(entry)
        applyIconVisual(entry,false); updateRow(entry)
        if entry == selectedEntry then fillSelectedEditor(entry) end
        status(isIconVisible(entry) and "Icono visible" or "Icono oculto; la funcion conserva su estado.")
      end
    end
    local found = query == "" or (effectiveText(entry) .. " " .. entry.defaults.text .. " " .. entry.id):lower():find(query,1,true)
    row:setVisible(found and true or false); if found then matches = matches + 1 end
    updateRow(entry)
  end
  editorWindow.listTitle:setText("Iconos (" .. matches .. "/" .. #activeIcons .. ")")
  if editorWindow.emptySearch then editorWindow.emptySearch:setVisible(matches == 0) end
  if not selectedEntry and activeIcons[1] then selectEditorEntry(activeIcons[1]) end
end

local rootWidget = g_ui and g_ui.getRootWidget and g_ui.getRootWidget() or nil
if rootWidget then
  local previousWindow = rootWidget:recursiveGetChildById("IconEditorWindow")
  if previousWindow then previousWindow:destroy() end
  local ok, window = pcall(function() return UI.createWindow("IconEditorWindow",rootWidget) end)
  if ok then editorWindow = window; editorWindow:hide()
  else warn("[Icon Editor] No se pudo cargar IconEditor.otui:\n" .. tostring(window)) end
end

local pageControls = {["icon"]={"nameLabel","selectedName","itemLabel","selectedItem","selectedVisible","selectedStyleLabel","selectedVisualMode","positionLabel","xLabel","selectedX","yLabel","selectedY","onColorLabel","onGreen","onLime","onCyan","onYellow","onColorHex","onColorPreview","offColorLabel","offRed","offWhite","offOrange","offYellow","offCyan","offColorHex","offColorPreview","previewLabel","previewOn","previewOff","resetIcon"},["layout"]={"styleLabel","visualMode","opacityLabel","barOpacity","snapEnabled","gridLabel","gridSize","layoutSeparator","layoutTitle","presetVertical","presetRow","presetColumns","columnsLabel","columns","visibleOnly","gapXLabel","gapX","gapYLabel","gapY","originXLabel","originX","originYLabel","originY","alignGrid","resetAll","layoutHint"},["helper"]={"helperHost","helperNotice"}}
showPage = function(page)
  if not editorWindow then return end
  page = pageControls[page] and page or "icon"
  if currentPage ~= page then changeKey = nil end
  currentPage = page
  for name, ids in pairs(pageControls) do
    for _, id in ipairs(ids) do editorWindow[id]:setVisible(name == page) end
  end
  editorWindow.iconTab:setOn(page == "icon"); editorWindow.layoutTab:setOn(page == "layout"); editorWindow.helperTab:setOn(page == "helper")
  editorWindow.helperNotice:setVisible(page == "helper" and editorWindow.helperAvailable ~= true)
  editorWindow.selectedTitle:setText(page == "layout" and "Conjunto de iconos" or page == "helper" and "Tecla y tamano del Helper" or selectedEntry and effectiveText(selectedEntry):gsub("\n", " ") or "Selecciona un icono")
end
local function setMoveMode(mode)
  if mode ~= "selected" and mode ~= "group" then mode = "none" end
  moveMode, editMode = mode, mode ~= "none"
  if editorWindow then
    editorWindow.moveSelected:setChecked(mode == "selected"); editorWindow.moveGroup:setChecked(mode == "group")
    syncingMovement = true
    editorWindow.movementMode:setOption(mode == "selected" and "Mover seleccionado" or mode == "group" and "Mover todos" or "Bloqueado")
    syncingMovement = false
  end
  for _, entry in ipairs(activeIcons) do setIconDraggable(entry,canDragEntry(entry)) end
  status(mode == "selected" and "Arrastra el icono seleccionado; no cambia su ON/OFF." or mode == "group" and "Arrastra un icono para mover el conjunto; no cambia ON/OFF." or editorConfig.layout.holdToMove == true and "Arrastra para mover iconos, incluso con este editor cerrado. Clic derecho abre su configuracion." or "Arrastre bloqueado. Activalo desde Ajustes > Mover iconos.")
end
fillLayoutControls = function()
  if not editorWindow then return end
  syncingLayoutControls = true
  for _, key in ipairs({"originX","originY","columns","gapX","gapY","gridSize","barOpacity"}) do
    editorWindow[key]:setValue(tonumber(editorConfig.layout[key]) or layoutDefaults[key])
  end
  editorWindow.visualMode:setOption(editorConfig.layout.visualMode == "bar" and "Barra" or "Icono")
  editorWindow.snapEnabled:setChecked(editorConfig.layout.snapEnabled ~= false)
  editorWindow.visibleOnly:setChecked(editorConfig.layout.visibleOnly ~= false)
  syncingLayoutControls = false
end
local function applyNameAndItem()
  if syncingSelectedControls or not selectedEntry then return end
  local name = iconText(editorWindow.selectedName:getText())
  local item = math.max(0,tonumber(editorWindow.selectedItem:getItemId()) or 0)
  if name == (selectedEntry.config.text or iconText(editorText(selectedEntry.defaults.text))) and item == effectiveItemId(selectedEntry) then return end
  remember("appearance:" .. selectedEntry.id)
  selectedEntry.config.text = name ~= "" and name or nil; selectedEntry.config.itemId = item
  applyIconVisual(selectedEntry,false); updateRow(selectedEntry); updatePreview()
  if currentPage == "icon" then editorWindow.selectedTitle:setText(effectiveText(selectedEntry):gsub("\n", " ")) end
  if editorWindow.search:getText():match("%S") then refreshEditorList() end
  status("Aspecto guardado", "#8cff9a")
end
local function applyColor(state,color)
  if not selectedEntry then return false end
  color = tostring(color or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if not color:match("^#%x%x%x%x%x%x$") then status("Color invalido: usa #RRGGBB y pulsa Enter.","#ff8a8a"); return false end
  local key = state == "on" and "onColor" or "offColor"
  if selectedEntry.config[key] ~= color then remember("appearance:" .. selectedEntry.id); selectedEntry.config[key] = color end
  if state == "on" then selectedOnColor = color else selectedOffColor = color end
  syncingSelectedControls = true; editorWindow[state .. "ColorHex"]:setText(color); syncingSelectedControls = false
  setPreviewColor(editorWindow[state .. "ColorPreview"],color)
  setTextColor(selectedEntry,readScriptState(selectedEntry.botScript)); updatePreview(); status("Color guardado", "#8cff9a")
  return true
end
local function applySelectedPosition()
  if syncingSelectedControls or not selectedEntry then return end
  local x,y = clamp(editorWindow.selectedX:getValue(),0,4000),clamp(editorWindow.selectedY:getValue(),0,4000)
  if x == effectiveX(selectedEntry) and y == effectiveY(selectedEntry) then return end
  remember("position:" .. selectedEntry.id)
  selectedEntry.config.x,selectedEntry.config.y = math.floor(x),math.floor(y)
  applyIconVisual(selectedEntry,true); updateRow(selectedEntry)
  syncingSelectedControls = true
  editorWindow.selectedX:setValue(effectiveX(selectedEntry)); editorWindow.selectedY:setValue(effectiveY(selectedEntry))
  syncingSelectedControls = false; status("Posicion guardada", "#8cff9a")
end
local function applyLayout()
  local values = clone(editorConfig.layout)
  local limits={originX={0,4000},originY={0,4000},columns={1,32},gapX={1,300},gapY={1,300}}
  for _, key in ipairs({"originX","originY","columns","gapX","gapY"}) do
    values[key] = math.floor(clamp(editorWindow[key]:getValue(),limits[key][1],limits[key][2]))
  end
  values.visibleOnly = editorWindow.visibleOnly:isChecked()
  local root = g_ui.getRootWidget(); local positions,index = {},0
  for _, entry in ipairs(activeIcons) do
    if not values.visibleOnly or isIconVisible(entry) then
      local x = values.originX + (index % values.columns) * values.gapX
      local y = values.originY + math.floor(index / values.columns) * values.gapY
      if x + currentIconWidth(entry) > root:getWidth() or y + currentIconHeight(entry) > root:getHeight() then
        status("No cabe en pantalla: reduce origen, columnas o pasos.","#ff8a8a"); return false
      end
      positions[#positions+1] = {entry=entry,x=x,y=y}; index = index + 1
    end
  end
  if #positions == 0 then status("No hay iconos visibles para ordenar.","#ffcf7c");return false end
  remember("layout",true)
  editorConfig.layout = values
  for _, p in ipairs(positions) do p.entry.config.x,p.entry.config.y = p.x,p.y; applyIconVisual(p.entry,true);updateRow(p.entry) end
  fillLayoutControls(); fillSelectedEditor(selectedEntry); status("Distribucion guardada. Deshacer permite volver.","#8cff9a");return true
end
local function setVisualMode(mode)
  mode = mode == "bar" and "bar" or "classic"
  local different = editorConfig.layout.visualMode ~= mode
  for _, entry in ipairs(activeIcons) do if entry.config.visualMode then different = true end end
  if not different then return end
  remember("global-style",true); editorConfig.layout.visualMode = mode
  for _, entry in ipairs(activeIcons) do
    entry.config.visualMode = nil; styleIcon(entry.widget,entry); applyIconVisual(entry,true); updateRow(entry)
  end
  fillSelectedEditor(selectedEntry); updatePreview(); status("Estilo aplicado a todos", "#8cff9a")
end
local function resetEntry(entry)
  if not entry then return end
  remember("reset:" .. entry.id,true); editorConfig.icons[entry.id] = {}; entry.config = editorConfig.icons[entry.id]
  styleIcon(entry.widget,entry);applyIconVisual(entry,true);updateRow(entry);fillSelectedEditor(selectedEntry)
  status("Icono restablecido. Puedes deshacerlo.","#ffcf7c")
end
local function setAllVisible(visible)
  remember("visibility-all",true)
  for _, entry in ipairs(activeIcons) do entry.config.visible = visible; applyIconVisual(entry,false);updateRow(entry) end
  fillSelectedEditor(selectedEntry);status(visible and "Todos los iconos visibles" or "Iconos ocultos; las funciones mantienen su estado.")
end
local function preset(columns)
  local width,height = 0,0
  for _, entry in ipairs(activeIcons) do width=math.max(width,currentIconWidth(entry));height=math.max(height,currentIconHeight(entry)) end
  syncingLayoutControls = true
  editorWindow.columns:setValue(math.min(32,columns));editorWindow.gapX:setValue(width+6);editorWindow.gapY:setValue(height+6)
  syncingLayoutControls = false; status("Distribucion preparada. Pulsa Ordenar.","#ffcf7c")
end

if editorWindow then
  editorWindow.iconTab.onClick=function()showPage("icon")end
  editorWindow.layoutTab.onClick=function()showPage("layout")end
  editorWindow.helperTab.onClick=function()showPage("helper")end
  editorWindow.search.onTextChange=refreshEditorList
  editorWindow.selectedName.onTextChange=applyNameAndItem
  editorWindow.selectedName.onEnter=function()applyNameAndItem();return true end
  editorWindow.selectedItem.onItemChange=applyNameAndItem
  editorWindow.selectedX.onValueChange=applySelectedPosition;editorWindow.selectedY.onValueChange=applySelectedPosition
  editorWindow.selectedVisualMode.onOptionChange=function(widget)
    if syncingSelectedControls or not selectedEntry then return end
    local option=widget:getCurrentOption();local mode=option and (option.text=="Barra" and "bar" or option.text=="Icono" and "classic" or nil)
    if mode==selectedEntry.config.visualMode then return end
    remember("appearance:" .. selectedEntry.id);selectedEntry.config.visualMode=mode
    styleIcon(selectedEntry.widget,selectedEntry);applyIconVisual(selectedEntry,true);updateRow(selectedEntry);updatePreview();status("Estilo guardado","#8cff9a")
  end
  editorWindow.selectedVisible.onClick=function()
    if not selectedEntry then return end
    remember("visible:"..selectedEntry.id,true);selectedEntry.config.visible=not isIconVisible(selectedEntry)
    editorWindow.selectedVisible:setChecked(isIconVisible(selectedEntry))
    applyIconVisual(selectedEntry,false);updateRow(selectedEntry)
    status(isIconVisible(selectedEntry) and "Icono visible" or "Icono oculto; la funcion conserva su estado.")
  end
  editorWindow.applyIcon.onClick=applyNameAndItem
  editorWindow.resetIcon.onClick=function()resetEntry(selectedEntry)end
  for _, item in ipairs({{"onGreen","on","#00d43a"},{"onLime","on","#77ff55"},{"onCyan","on","#32d8ff"},{"onYellow","on","#ffe45b"},{"offRed","off","#ff3b3b"},{"offWhite","off","#ffffff"},{"offOrange","off","#ff9f32"},{"offYellow","off","#ffe45b"},{"offCyan","off","#32d8ff"}}) do
    editorWindow[item[1]].onClick=function()applyColor(item[2],item[3])end
  end
  editorWindow.onColorHex.onEnter=function()return applyColor("on",editorWindow.onColorHex:getText())end
  editorWindow.offColorHex.onEnter=function()return applyColor("off",editorWindow.offColorHex:getText())end
  editorWindow.movementMode.onOptionChange=function(widget)
    if syncingMovement then return end
    local option=widget:getCurrentOption();setMoveMode(option and option.text=="Mover seleccionado" and "selected" or option and option.text=="Mover todos" and "group" or "none")
  end
  editorWindow.moveSelected.onClick=function()setMoveMode(moveMode=="selected" and "none" or "selected")end
  editorWindow.moveGroup.onClick=function()setMoveMode(moveMode=="group" and "none" or "group")end
  editorWindow.snapEnabled.onClick=function(widget)
    remember("snap",true);editorConfig.layout.snapEnabled=not(editorConfig.layout.snapEnabled~=false);widget:setChecked(editorConfig.layout.snapEnabled~=false)
  end
  editorWindow.gridSize.onValueChange=function(widget)
    if syncingLayoutControls then return end
    remember("grid-size");editorConfig.layout.gridSize=clamp(widget:getValue(),1,32)
  end
  for _, key in ipairs({"originX","originY","columns","gapX","gapY"}) do editorWindow[key].onValueChange=function()
    if not syncingLayoutControls then status("Valores preparados. Pulsa Ordenar para aplicarlos.","#ffcf7c") end
  end end
  editorWindow.visualMode.onOptionChange=function(widget)
    if syncingLayoutControls then return end
    local option=widget:getCurrentOption();setVisualMode(option and option.text=="Barra" and "bar" or "classic")
  end
  editorWindow.barOpacity.onValueChange=function(widget)
    if syncingLayoutControls then return end
    remember("opacity");editorConfig.layout.barOpacity=clamp(widget:getValue(),10,100)
    for _, entry in ipairs(activeIcons) do if isBarMode(entry) then setTextColor(entry,readScriptState(entry.botScript)) end end
    updatePreview()
  end
  editorWindow.presetVertical.onClick=function()preset(1)end
  editorWindow.presetRow.onClick=function()preset(math.max(1,#activeIcons))end
  editorWindow.presetColumns.onClick=function()preset(2)end
  editorWindow.alignGrid.onClick=applyLayout
  editorWindow.showAll.onClick=function()setAllVisible(true)end
  editorWindow.hideAll.onClick=function()setAllVisible(false)end
  editorWindow.resetAll.onClick=function()
    remember("reset-all",true);setMoveMode("none");editorConfig.icons={}
    for key,value in pairs(layoutDefaults)do editorConfig.layout[key]=value end
    editorConfig.layout.visibleOnly=true
    for _, entry in ipairs(activeIcons) do entry.config=getIconConfig(entry.id);styleIcon(entry.widget,entry);applyIconVisual(entry,true);updateRow(entry)end
    fillLayoutControls();fillSelectedEditor(selectedEntry);status("Iconos restablecidos. Deshacer permite recuperarlos.","#ffcf7c")
  end
  editorWindow.undo.onClick=function()
    if not undoState then return end
    setMoveMode("none");editorConfig.icons=clone(undoState.icons);editorConfig.layout=clone(undoState.layout)
    for _,entry in ipairs(activeIcons)do entry.config=getIconConfig(entry.id);styleIcon(entry.widget,entry);applyIconVisual(entry,true,true);updateRow(entry)end
    undoState,changeKey=nil,nil;editorWindow.undo:setEnabled(false);fillLayoutControls();fillSelectedEditor(selectedEntry);status("Operacion deshecha; ON/OFF no cambia.","#8cff9a")
  end
  for _, entry in ipairs(activeIcons) do
    local start=entry.widget.onDragEnter
    entry.widget.onDragEnter=function(widget,mouse)
      if canStartDrag(entry) then remember("drag",true) end
      return start(widget,mouse)
    end
  end
  local visibility=editorWindow.onVisibilityChange
  editorWindow.onVisibilityChange=function(widget,visible)
    if visibility then visibility(widget,visible)end
    if not visible then changeKey=nil;setMoveMode("none")end
  end
  fillLayoutControls();refreshEditorList();showPage("icon");setMoveMode("none")
end

setDefaultTab("Tools")
local editorButton
local function prepareIconEditor()
  if not editorWindow then return false end
  fillLayoutControls();refreshEditorList();fillSelectedEditor(selectedEntry);showPage(currentPage)
  editorWindow.helperTab:setEnabled(editorWindow.helperAvailable==true)
  return true
end
local function openIconEditor()
  if not prepareIconEditor() then warn("[Icon Editor] Ventana no disponible. Recarga el bot.");return end
  editorWindow:show();editorWindow:raise();editorWindow:focus()
end
vBot=vBot or {}
vBot.IconEditor={getWindow=function()return editorWindow end,getButton=function()return editorButton end,
  prepare=prepareIconEditor,close=function()setMoveMode("none")end,open=openIconEditor,showPage=showPage,
  isHoldToMove=function()return editorConfig.layout.holdToMove==true end,
  setHoldToMove=function(enabled)
    editorConfig.layout.holdToMove=enabled==true
    for _,entry in ipairs(activeIcons)do
      -- Legacy holdToMove storage now enables immediate dragging.
      -- Finish an in-progress drag before locking, keeping its final position.
      if entry.widget.dragGroup then entry.widget.onDragLeave(entry.widget) end
      if entry.gesture then entry.gesture.cancelled=true end
      setIconDraggable(entry,canDragEntry(entry))
    end
  end}
editorButton=UI.Button("Iconos",openIconEditor)
editorButton:setImageColor("#2de0d7");editorButton:setFont("verdana-11px-rounded")
editorButton:setTooltip("Busca un icono, cambia su aspecto y organiza el conjunto. Deshacer recupera la ultima operacion.")
pcall(function()local parent=editorButton:getParent();if parent and parent.moveChildToIndex then parent:moveChildToIndex(editorButton,1)end end)
setDefaultTab("Main")


local function restoreSavedIconPositions()
  if positionGeneration ~= vBot.IconPositionGeneration or editMode then return end
  if g_game and type(g_game.isOnline) == "function" and not g_game.isOnline() then return end
  for _, entry in ipairs(activeIcons) do
    if liveIconWidget(entry.widget) and not entry.widget.dragGroup and not (entry.gesture and entry.gesture.pressed) then
      attachIconToWindow(entry.widget)
      applyIconVisual(entry, true, true)
    end
  end
end

-- Native layout restoration continues for several seconds after login. These
-- passes use current saved values and never overwrite them or toggle scripts.
for _, delay in ipairs({250, 750, 1500, 3000, 6000}) do
  schedule(delay, restoreSavedIconPositions)
end

macro(200, function()
  for _, entry in ipairs(activeIcons) do
    local enabled = readScriptState(entry.botScript)
    local widget = entry.widget

    if widget and widget.isOn and widget:isOn() ~= enabled then
      entry.guard.syncing = true
      syncIconSwitch(widget, enabled)
      entry.guard.syncing = false
      saveIconState(entry.id, enabled)
    end
    setTextColor(entry, enabled)
  end
end)
