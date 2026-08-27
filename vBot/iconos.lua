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
  barOpacity = 70
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
  if not editMode or not isIconVisible(entry) then return false end
  if moveMode == "group" then return true end
  return moveMode == "selected" and entry == selectedEntry
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
  if widget.text then pcall(function() widget.text:setColor(color) end) end
  if isBarMode(entry) then
    pcall(function() widget:setBackgroundColor(barBackgroundColor()) end)
    pcall(function() widget:setBorderColor(color) end)
  elseif widget.setColor then
    pcall(function() widget:setColor(color) end)
  end
end

local function saveIconState(id, enabled)
  storage._icons = storage._icons or {}
  storage._icons[id] = storage._icons[id] or {}
  storage._icons[id].enabled = enabled == true
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
      pcall(function() widget.item:lower() end)
    end
  end
end

local function setIconDraggable(entry, enabled)
  if not entry then return end
  entry.dragEnabled = enabled == true
end

local function applyIconVisual(entry, includePosition)
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
  end

  pcall(function() widget:setVisible(isIconVisible(entry)) end)
  setIconDraggable(entry, canDragEntry(entry))

  if includePosition ~= false then
    local position = setWidgetPosition(widget, effectiveX(entry), effectiveY(entry))
    if position then
      entry.config.x = position.x
      entry.config.y = position.y
    end
  end

  setTextColor(entry, readScriptState(entry.botScript))
end

local function saveDraggedPosition(entry, allowOverlap)
  if not entry or not editMode then return end
  local position = getWidgetPosition(entry.widget)
  if not position then return end

  if editorConfig.layout.snapEnabled ~= false then
    position.x = roundToGrid(position.x)
    position.y = roundToGrid(position.y)
  end

  local overlapping = not allowOverlap and findOverlappingIcon(entry, position.x, position.y, isIconVisible(entry)) or nil
  if overlapping then
    setWidgetPosition(entry.widget, effectiveX(entry), effectiveY(entry))
    if editorWindow then
      editorWindow.iconStatus:setText("Espacio ocupado por " .. effectiveText(overlapping):gsub("\n", " "))
      editorWindow.iconStatus:setColor("#ff8a8a")
    end
    return
  end

  setWidgetPosition(entry.widget, position.x, position.y)
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
    local entry
    local params = {
      text = type(config.text) == "string" and config.text ~= "" and config.text or data.text,
      switchable = true,
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
        if guard.booting or guard.syncing then
          if entry then setTextColor(entry, initialEnabled) end
          return
        end

        if editMode then
          local actualEnabled = readScriptState(data.botScript)
          guard.syncing = true
          if icon.setOn then pcall(function() icon:setOn(actualEnabled) end) end
          guard.syncing = false
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

      styleIcon(widget, entry)
      widget.onGeometryChange = function() end

      widget.onDragEnter = function(changedWidget, mousePos)
        if not entry.dragEnabled then return false end

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
            styleIcon(captured.widget, captured.entry)
            applyIconVisual(captured.entry, false)
            saveDraggedPosition(captured.entry, moveMode == "group")
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
        return true
      end

      local previousMousePress = widget.onMousePress
      widget.onMousePress = function(changedWidget, mousePos, mouseButton)
        if editMode and selectEditorEntry then selectEditorEntry(entry) end
        if previousMousePress then
          return previousMousePress(changedWidget, mousePos, mouseButton)
        end
      end

      applyIconVisual(entry, true)
      guard.syncing = true
      if widget.setOn then pcall(function() widget:setOn(initialEnabled) end) end
      guard.syncing = false
      saveIconState(data.id, initialEnabled)
      setTextColor(entry, initialEnabled)
      setIconDraggable(entry, false)
    else
      warn("[Icon Editor] No se pudo crear: " .. data.id)
    end
  else
    warn("[Icon Editor] Script no encontrado: " .. data.id)
  end
end

local function editorText(text)
  return tostring(text or ""):gsub("\n", " / ")
end

local function iconText(text)
  text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
  text = text:gsub("%s*/%s*", "\n")
  return text
end

local function setPreviewColor(widget, color)
  if not widget then return end
  pcall(function() widget:setBackgroundColor(color) end)
end

local function updateRow(entry)
  local row = entry and editorRows[entry.id] or nil
  if not row then return end

  row.visible:setChecked(isIconVisible(entry))
  row.item:setItemId(effectiveItemId(entry))
  row.name:setText(effectiveText(entry):gsub("\n", " "))
  row.coords:setText(effectiveX(entry) .. ", " .. effectiveY(entry))
  row.name:setColor(isIconVisible(entry) and "#ffffff" or "#888888")
end

local function fillSelectedEditor(entry)
  if not editorWindow or not entry then return end

  selectedOnColor = effectiveOnColor(entry)
  selectedOffColor = effectiveOffColor(entry)
  syncingSelectedControls = true
  editorWindow.selectedName:setText(editorText(effectiveText(entry)))
  editorWindow.selectedItem:setItemId(effectiveItemId(entry))
  editorWindow.selectedVisible:setChecked(isIconVisible(entry))
  editorWindow.selectedX:setValue(effectiveX(entry))
  editorWindow.selectedY:setValue(effectiveY(entry))
  if editorWindow.selectedVisualMode then
    editorWindow.selectedVisualMode:setOption(isBarMode(entry) and "Barra" or "Icono")
  end
  syncingSelectedControls = false
  setPreviewColor(editorWindow.onColorPreview, selectedOnColor)
  setPreviewColor(editorWindow.offColorPreview, selectedOffColor)
  editorWindow.iconStatus:setText(effectiveX(entry) .. ", " .. effectiveY(entry))
  editorWindow.iconStatus:setColor("#b8c7cc")
end

selectEditorEntry = function(entry)
  if not entry then return end
  selectedEntry = entry
  fillSelectedEditor(entry)

  if moveMode == "selected" then
    for _, candidate in ipairs(activeIcons) do
      setIconDraggable(candidate, canDragEntry(candidate))
    end
  end

  local row = editorRows[entry.id]
  if row then pcall(function() row:focus() end) end
end

refreshEditorList = function()
  if not editorWindow or not editorWindow.iconList then return end
  if editorWindow.listTitle then
    editorWindow.listTitle:setText("Iconos (" .. #activeIcons .. ")")
  end
  editorWindow.iconList:destroyChildren()
  editorRows = {}

  for _, entry in ipairs(activeIcons) do
    local row = g_ui.createWidget("IconEditorRow", editorWindow.iconList)
    row:setId("iconEditorRow" .. entry.id)
    editorRows[entry.id] = row

    row.onClick = function()
      selectEditorEntry(entry)
      return true
    end

    row.onDoubleClick = function()
      selectEditorEntry(entry)
      editorWindow.selectedName:focus()
      return true
    end

    row.visible.onClick = function(widget)
      local newVisible = not isIconVisible(entry)
      entry.config.visible = newVisible
      widget:setChecked(isIconVisible(entry))
      applyIconVisual(entry, false)
      updateRow(entry)
      if selectedEntry == entry then fillSelectedEditor(entry) end
    end

    updateRow(entry)
  end

  if selectedEntry and iconById[selectedEntry.id] then
    selectEditorEntry(selectedEntry)
  elseif activeIcons[1] then
    selectEditorEntry(activeIcons[1])
  end
end

local rootWidget = g_ui and g_ui.getRootWidget and g_ui.getRootWidget() or nil
if rootWidget then
  local previousWindow = rootWidget:recursiveGetChildById("IconEditorWindow")
  if previousWindow then previousWindow:destroy() end

  local ok, createdWindow = pcall(function()
    return UI.createWindow("IconEditorWindow", rootWidget)
  end)
  if ok then
    editorWindow = createdWindow
    editorWindow:hide()
  else
    warn("[Icon Editor] No se pudo cargar IconEditor.otui:\n" .. tostring(createdWindow))
  end
end

local function setMoveMode(mode)
  if mode ~= "selected" and mode ~= "group" then mode = "none" end
  moveMode = mode
  editMode = moveMode ~= "none"
  if editorWindow then
    editorWindow.moveSelected:setChecked(moveMode == "selected")
    editorWindow.moveGroup:setChecked(moveMode == "group")
  end

  for _, entry in ipairs(activeIcons) do
    setIconDraggable(entry, canDragEntry(entry))
  end

  if editorWindow then
    local status = "Movimiento desactivado"
    if moveMode == "selected" then status = "Arrastra el icono seleccionado" end
    if moveMode == "group" then status = "Arrastra cualquier icono para mover todos" end
    editorWindow.iconStatus:setText(status)
    editorWindow.iconStatus:setColor(editMode and "#ffd166" or "#b8c7cc")
  end
end

local function readLayoutControls()
  if not editorWindow then return end
  local layout = editorConfig.layout
  layout.originX = clamp(editorWindow.originX:getValue(), 0, 4000)
  layout.originY = clamp(editorWindow.originY:getValue(), 0, 4000)
  layout.columns = clamp(editorWindow.columns:getValue(), 1, 8)
  layout.gapX = clamp(editorWindow.gapX:getValue(), 1, 300)
  layout.gapY = clamp(editorWindow.gapY:getValue(), 1, 300)
  layout.gridSize = clamp(editorWindow.gridSize:getValue(), 1, 32)
  if editorWindow.barOpacity then
    layout.barOpacity = clamp(editorWindow.barOpacity:getValue(), 10, 100)
  end
end

local function fillLayoutControls()
  if not editorWindow then return end
  local layout = editorConfig.layout
  syncingLayoutControls = true
  editorWindow.originX:setValue(tonumber(layout.originX) or layoutDefaults.originX)
  editorWindow.originY:setValue(tonumber(layout.originY) or layoutDefaults.originY)
  editorWindow.columns:setValue(tonumber(layout.columns) or layoutDefaults.columns)
  editorWindow.gapX:setValue(tonumber(layout.gapX) or layoutDefaults.gapX)
  editorWindow.gapY:setValue(tonumber(layout.gapY) or layoutDefaults.gapY)
  editorWindow.gridSize:setValue(tonumber(layout.gridSize) or layoutDefaults.gridSize)
  editorWindow.snapEnabled:setChecked(layout.snapEnabled ~= false)
  editorWindow.moveSelected:setChecked(moveMode == "selected")
  editorWindow.moveGroup:setChecked(moveMode == "group")
  if editorWindow.visualMode then
    editorWindow.visualMode:setOption(isBarMode() and "Barra" or "Icono")
  end
  if editorWindow.barOpacity then
    editorWindow.barOpacity:setValue(clamp(layout.barOpacity, 10, 100))
  end
  syncingLayoutControls = false
end

local function alignIconsToGrid(useStoredLayout, keepControlFocus)
  if not editorWindow then return end
  if not useStoredLayout then readLayoutControls() end
  local layout = editorConfig.layout
  local columns = math.max(1, tonumber(layout.columns) or 2)
  local positions = {}
  local root = g_ui and g_ui.getRootWidget and g_ui.getRootWidget() or nil
  local rootWidth
  local rootHeight

  if root then
    pcall(function() rootWidth = tonumber(root:getWidth()) end)
    pcall(function() rootHeight = tonumber(root:getHeight()) end)
  end

  for index, entry in ipairs(activeIcons) do
    local column = (index - 1) % columns
    local row = math.floor((index - 1) / columns)
    local x = math.floor(layout.originX + column * layout.gapX)
    local y = math.floor(layout.originY + row * layout.gapY)
    local widgetWidth = currentIconWidth(entry)
    local widgetHeight = currentIconHeight(entry)

    if rootWidth and x + widgetWidth > rootWidth then
      editorWindow.iconStatus:setText("La distribucion excede el ancho")
      editorWindow.iconStatus:setColor("#ff8a8a")
      if not keepControlFocus then fillLayoutControls() end
      return
    end
    if rootHeight and y + widgetHeight > rootHeight then
      editorWindow.iconStatus:setText("La distribucion excede el alto")
      editorWindow.iconStatus:setColor("#ff8a8a")
      if not keepControlFocus then fillLayoutControls() end
      return
    end

    positions[index] = {entry = entry, x = x, y = y}
  end

  for _, position in ipairs(positions) do
    position.entry.config.x = position.x
    position.entry.config.y = position.y
    applyIconVisual(position.entry, true)
  end

  if not keepControlFocus then fillLayoutControls() end
  refreshEditorList()
  editorWindow.iconStatus:setText("Iconos alineados")
  editorWindow.iconStatus:setColor("#8cff9a")
end

local changingVisualMode = false
local function setVisualMode(mode)
  mode = mode == "bar" and "bar" or "classic"
  if changingVisualMode then return end
  changingVisualMode = true

  readLayoutControls()
  editorConfig.layout.visualMode = mode

  for _, entry in ipairs(activeIcons) do
    entry.config.visualMode = nil
    styleIcon(entry.widget, entry)
    applyIconVisual(entry, true)
  end

  fillLayoutControls()
  refreshEditorList()

  editorWindow.iconStatus:setText(mode == "bar" and "Modo Barra aplicado" or "Modo Icono aplicado")
  editorWindow.iconStatus:setColor("#8cff9a")
  changingVisualMode = false
end

local function resetEntry(entry)
  if not entry then return end
  editorConfig.icons[entry.id] = {}
  entry.config = editorConfig.icons[entry.id]
  styleIcon(entry.widget, entry)
  applyIconVisual(entry, true)
  updateRow(entry)
  if selectedEntry == entry then fillSelectedEditor(entry) end
end

local function applySelectedPositionFromControls()
  if syncingSelectedControls or not editorWindow or not selectedEntry then return end
  local x = clamp(editorWindow.selectedX:getValue(), 0, 4000)
  local y = clamp(editorWindow.selectedY:getValue(), 0, 4000)
  selectedEntry.config.x = math.floor(x)
  selectedEntry.config.y = math.floor(y)
  applyIconVisual(selectedEntry, true)
  updateRow(selectedEntry)
  editorWindow.iconStatus:setText("X: " .. selectedEntry.config.x .. "   Y: " .. selectedEntry.config.y)
  editorWindow.iconStatus:setColor("#8cff9a")
end

local function previewLayoutFromControls()
  if syncingLayoutControls or changingVisualMode or not editorWindow then return end
  readLayoutControls()
  alignIconsToGrid(true, true)
end

if editorWindow then
  local onSwatches = {
    {widget = editorWindow.onGreen, color = "#00d43a"},
    {widget = editorWindow.onLime, color = "#77ff55"},
    {widget = editorWindow.onCyan, color = "#32d8ff"},
    {widget = editorWindow.onYellow, color = "#ffe45b"}
  }
  local offSwatches = {
    {widget = editorWindow.offRed, color = "#ff3b3b"},
    {widget = editorWindow.offWhite, color = "#ffffff"},
    {widget = editorWindow.offOrange, color = "#ff9f32"},
    {widget = editorWindow.offYellow, color = "#ffe45b"},
    {widget = editorWindow.offCyan, color = "#32d8ff"}
  }

  for _, swatch in ipairs(onSwatches) do
    swatch.widget.onClick = function()
      selectedOnColor = swatch.color
      setPreviewColor(editorWindow.onColorPreview, selectedOnColor)
    end
  end

  for _, swatch in ipairs(offSwatches) do
    swatch.widget.onClick = function()
      selectedOffColor = swatch.color
      setPreviewColor(editorWindow.offColorPreview, selectedOffColor)
    end
  end

  editorWindow.selectedX.onValueChange = function()
    applySelectedPositionFromControls()
  end

  editorWindow.selectedY.onValueChange = function()
    applySelectedPositionFromControls()
  end

  if editorWindow.selectedVisualMode then
    editorWindow.selectedVisualMode.onOptionChange = function(widget)
      if syncingSelectedControls or not selectedEntry then return end
      local option = widget:getCurrentOption()
      local mode = option and option.text == "Barra" and "bar" or "classic"
      if mode == effectiveVisualMode(selectedEntry) then return end
      selectedEntry.config.visualMode = mode
      styleIcon(selectedEntry.widget, selectedEntry)
      applyIconVisual(selectedEntry, true)
      updateRow(selectedEntry)
      editorWindow.iconStatus:setText(mode == "bar" and "Barra aplicada" or "Icono aplicado")
      editorWindow.iconStatus:setColor("#8cff9a")
    end
  end

  editorWindow.selectedVisible.onClick = function(widget)
    if not selectedEntry then return end
    selectedEntry.config.visible = not isIconVisible(selectedEntry)
    widget:setChecked(isIconVisible(selectedEntry))
    applyIconVisual(selectedEntry, false)
    updateRow(selectedEntry)
  end

  editorWindow.applyIcon.onClick = function()
    if not selectedEntry then return end

    local configuredText = iconText(editorWindow.selectedName:getText())
    local newVisible = editorWindow.selectedVisible:isChecked()

    selectedEntry.config.text = configuredText ~= "" and configuredText or nil
    selectedEntry.config.itemId = math.max(0, tonumber(editorWindow.selectedItem:getItemId()) or 0)
    selectedEntry.config.visible = newVisible
    selectedEntry.config.onColor = selectedOnColor
    selectedEntry.config.offColor = selectedOffColor

    applyIconVisual(selectedEntry, true)
    updateRow(selectedEntry)
    fillSelectedEditor(selectedEntry)
    editorWindow.iconStatus:setText("Cambios guardados")
    editorWindow.iconStatus:setColor("#8cff9a")
  end

  editorWindow.resetIcon.onClick = function()
    if not selectedEntry then return end
    resetEntry(selectedEntry)
    editorWindow.iconStatus:setText("Icono restablecido")
    editorWindow.iconStatus:setColor("#ffd166")
  end

  editorWindow.moveSelected.onClick = function()
    setMoveMode(moveMode == "selected" and "none" or "selected")
  end

  editorWindow.moveGroup.onClick = function()
    setMoveMode(moveMode == "group" and "none" or "group")
  end

  editorWindow.snapEnabled.onClick = function(widget)
    editorConfig.layout.snapEnabled = not (editorConfig.layout.snapEnabled ~= false)
    widget:setChecked(editorConfig.layout.snapEnabled ~= false)
  end

  editorWindow.gridSize.onValueChange = function(widget, value)
    if syncingLayoutControls then return end
    editorConfig.layout.gridSize = clamp(value, 1, 32)
  end

  editorWindow.originX.onValueChange = previewLayoutFromControls
  editorWindow.originY.onValueChange = previewLayoutFromControls
  editorWindow.columns.onValueChange = previewLayoutFromControls
  editorWindow.gapX.onValueChange = previewLayoutFromControls
  editorWindow.gapY.onValueChange = previewLayoutFromControls

  if editorWindow.visualMode then
    editorWindow.visualMode.onOptionChange = function(widget)
      if changingVisualMode or syncingLayoutControls then return end
      local option = widget:getCurrentOption()
      local mode = option and option.text == "Barra" and "bar" or "classic"
      if mode ~= editorConfig.layout.visualMode then setVisualMode(mode) end
    end
  end

  if editorWindow.barOpacity then
    editorWindow.barOpacity.onValueChange = function(widget, value)
      if syncingLayoutControls then return end
      editorConfig.layout.barOpacity = clamp(value, 10, 100)
      for _, entry in ipairs(activeIcons) do
        if isBarMode(entry) then
          setTextColor(entry, readScriptState(entry.botScript))
        end
      end
    end
  end

  editorWindow.alignGrid.onClick = function()
    alignIconsToGrid(false)
  end

  editorWindow.resetAll.onClick = function()
    setMoveMode("none")
    editorConfig.icons = {}
    for key, value in pairs(layoutDefaults) do editorConfig.layout[key] = value end
    editorConfig.layout.snapEnabled = true

    for _, entry in ipairs(activeIcons) do
      entry.config = getIconConfig(entry.id)
      styleIcon(entry.widget, entry)
      applyIconVisual(entry, true)
    end

    fillLayoutControls()
    refreshEditorList()
    editorWindow.iconStatus:setText("Todos los iconos restablecidos")
    editorWindow.iconStatus:setColor("#ffd166")
  end

  local previousVisibilityChange = editorWindow.onVisibilityChange
  editorWindow.onVisibilityChange = function(widget, visible)
    if previousVisibilityChange then previousVisibilityChange(widget, visible) end
    if not visible then setMoveMode("none") end
  end

  fillLayoutControls()
  refreshEditorList()
end

setDefaultTab("Tools")
local editorButton = UI.Button("Icon Editor", function()
  if not editorWindow then
    warn("[Icon Editor] La ventana no esta disponible. Recarga el bot para importar IconEditor.otui.")
    return
  end

  fillLayoutControls()
  refreshEditorList()
  editorWindow:show()
  editorWindow:raise()
  editorWindow:focus()
end)
editorButton:setImageColor("#2de0d7")
editorButton:setFont("verdana-11px-rounded")
editorButton:setTooltip("Edita nombre, item, colores, visibilidad y posicion de los iconos.")
pcall(function()
  local parent = editorButton:getParent()
  if parent and parent.moveChildToIndex then
    parent:moveChildToIndex(editorButton, 1)
  end
end)
setDefaultTab("Main")

macro(200, function()
  for _, entry in ipairs(activeIcons) do
    local enabled = readScriptState(entry.botScript)
    local widget = entry.widget

    if widget and widget.isOn and widget:isOn() ~= enabled then
      entry.guard.syncing = true
      pcall(function() widget:setOn(enabled) end)
      entry.guard.syncing = false
      saveIconState(entry.id, enabled)
    end
    setTextColor(entry, enabled)
  end
end)
