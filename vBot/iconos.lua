local leftX = 206
local rightX = 274
local topY = 146
local spacingY = 48
local iconWidth = 58
local iconHeight = 46

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
}

local layoutDefaults = {
  originX = leftX,
  originY = topY - spacingY,
  columns = 2,
  gapX = rightX - leftX,
  gapY = spacingY,
  gridSize = 2,
  snapEnabled = true
}

if type(storage.iconEditor) ~= "table" then storage.iconEditor = {} end
local editorConfig = storage.iconEditor
if type(editorConfig.icons) ~= "table" then editorConfig.icons = {} end
if type(editorConfig.layout) ~= "table" then editorConfig.layout = {} end

for key, value in pairs(layoutDefaults) do
  if editorConfig.layout[key] == nil then editorConfig.layout[key] = value end
end

local activeIcons = {}
local iconById = {}
local editorRows = {}
local editorWindow
local selectedEntry
local selectedOnColor = "#00d43a"
local selectedOffColor = "#ff3b3b"
local editMode = false
local selectEditorEntry
local refreshEditorList

local function clamp(value, minimum, maximum)
  value = tonumber(value) or minimum
  if value < minimum then return minimum end
  if maximum and value > maximum then return maximum end
  return value
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

local function readScriptState(script)
  if not script or not script.isOn then return false end
  local ok, enabled = pcall(script.isOn)
  return ok and enabled == true
end

local function setWidgetPosition(widget, x, y)
  if not widget then return end

  x = math.max(0, math.floor(tonumber(x) or 0))
  y = math.max(0, math.floor(tonumber(y) or 0))

  local root = g_ui and g_ui.getRootWidget and g_ui.getRootWidget() or nil
  if root then
    local okWidth, rootWidth = pcall(function() return root:getWidth() end)
    local okHeight, rootHeight = pcall(function() return root:getHeight() end)
    rootWidth = tonumber(rootWidth)
    rootHeight = tonumber(rootHeight)
    if okWidth and rootWidth and rootWidth > iconWidth then
      x = math.min(x, rootWidth - iconWidth)
    end
    if okHeight and rootHeight and rootHeight > iconHeight then
      y = math.min(y, rootHeight - iconHeight)
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

  for _, other in ipairs(activeIcons) do
    if other ~= entry and isIconVisible(other) then
      local otherPosition = getWidgetPosition(other.widget) or {
        x = effectiveX(other),
        y = effectiveY(other)
      }
      if math.abs(x - otherPosition.x) < iconWidth and math.abs(y - otherPosition.y) < iconHeight then
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
  if widget.setColor then pcall(function() widget:setColor(color) end) end
end

local function saveIconState(id, enabled)
  storage._icons = storage._icons or {}
  storage._icons[id] = storage._icons[id] or {}
  storage._icons[id].enabled = enabled == true
end

local function styleIcon(widget)
  if not widget then return end
  pcall(function() widget:breakAnchors() end)
  pcall(function() widget:setSize({height = iconHeight, width = iconWidth}) end)

  if widget.text then
    pcall(function() widget.text:breakAnchors() end)
    pcall(function() widget.text:setFont("verdana-11px-rounded") end)
    pcall(function() widget.text:setTextAlign(AlignCenter) end)
    pcall(function() widget.text:setSize({height = 24, width = iconWidth}) end)
    pcall(function() widget.text:setWidth(iconWidth) end)
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

local function setIconDraggable(entry, enabled)
  if not entry then return end
  entry.dragEnabled = enabled == true
end

local function applyIconVisual(entry, includePosition)
  if not entry or not entry.widget then return end
  local widget = entry.widget

  if widget.text then
    pcall(function() widget.text:setText(effectiveText(entry)) end)
  end

  if widget.item then
    pcall(function() widget.item:setItemId(effectiveItemId(entry)) end)
  end

  pcall(function() widget:setVisible(isIconVisible(entry)) end)
  setIconDraggable(entry, editMode and isIconVisible(entry))

  if includePosition ~= false then
    local position = setWidgetPosition(widget, effectiveX(entry), effectiveY(entry))
    if position then
      entry.config.x = position.x
      entry.config.y = position.y
    end
  end

  setTextColor(entry, readScriptState(entry.botScript))
end

local function saveDraggedPosition(entry)
  if not entry or not editMode then return end
  local position = getWidgetPosition(entry.widget)
  if not position then return end

  if editorConfig.layout.snapEnabled ~= false then
    position.x = roundToGrid(position.x)
    position.y = roundToGrid(position.y)
  end

  local overlapping = findOverlappingIcon(entry, position.x, position.y, isIconVisible(entry))
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
    editorWindow.selectedX:setValue(position.x)
    editorWindow.selectedY:setValue(position.y)
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

      styleIcon(widget)
      widget.onGeometryChange = function() end

      widget.onDragEnter = function(changedWidget, mousePos)
        if not entry.dragEnabled then return false end

        changedWidget:breakAnchors()
        changedWidget.movingReference = {
          x = mousePos.x - changedWidget:getX(),
          y = mousePos.y - changedWidget:getY()
        }
        if selectEditorEntry then selectEditorEntry(entry) end
        return true
      end

      widget.onDragMove = function(changedWidget, mousePos)
        if not entry.dragEnabled or not changedWidget.movingReference then return false end

        local root = g_ui.getRootWidget()
        local rootWidth = root and tonumber(root:getWidth()) or 0
        local rootHeight = root and tonumber(root:getHeight()) or 0
        local maxX = math.max(0, rootWidth - changedWidget:getWidth())
        local maxY = math.max(0, rootHeight - changedWidget:getHeight())
        local x = math.min(math.max(0, mousePos.x - changedWidget.movingReference.x), maxX)
        local y = math.min(math.max(0, mousePos.y - changedWidget.movingReference.y), maxY)

        changedWidget:move(x, y)
        return true
      end

      widget.onDragLeave = function(changedWidget)
        if not changedWidget.movingReference then return false end
        changedWidget.movingReference = nil
        saveDraggedPosition(entry)
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
  editorWindow.selectedName:setText(editorText(effectiveText(entry)))
  editorWindow.selectedItem:setItemId(effectiveItemId(entry))
  editorWindow.selectedVisible:setChecked(isIconVisible(entry))
  editorWindow.selectedX:setValue(effectiveX(entry))
  editorWindow.selectedY:setValue(effectiveY(entry))
  setPreviewColor(editorWindow.onColorPreview, selectedOnColor)
  setPreviewColor(editorWindow.offColorPreview, selectedOffColor)
  editorWindow.iconStatus:setText(entry.id)
  editorWindow.iconStatus:setColor("#b8c7cc")
end

selectEditorEntry = function(entry)
  if not entry then return end
  selectedEntry = entry
  fillSelectedEditor(entry)

  local row = editorRows[entry.id]
  if row then pcall(function() row:focus() end) end
end

refreshEditorList = function()
  if not editorWindow or not editorWindow.iconList then return end
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
      local overlapping = findOverlappingIcon(entry, effectiveX(entry), effectiveY(entry), newVisible)
      if overlapping then
        widget:setChecked(false)
        if editorWindow then
          editorWindow.iconStatus:setText("Espacio ocupado por " .. effectiveText(overlapping):gsub("\n", " "))
          editorWindow.iconStatus:setColor("#ff8a8a")
        end
        return
      end

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

local function setEditMode(enabled)
  editMode = enabled == true
  if editorWindow and editorWindow.moveMode then
    editorWindow.moveMode:setChecked(editMode)
  end

  for _, entry in ipairs(activeIcons) do
    setIconDraggable(entry, editMode and isIconVisible(entry))
  end

  if editorWindow then
    editorWindow.iconStatus:setText(editMode and "Arrastra los iconos" or "Movimiento desactivado")
    editorWindow.iconStatus:setColor(editMode and "#ffd166" or "#b8c7cc")
  end
end

local function readLayoutControls()
  if not editorWindow then return end
  local layout = editorConfig.layout
  layout.originX = clamp(editorWindow.originX:getValue(), 0, 4000)
  layout.originY = clamp(editorWindow.originY:getValue(), 0, 4000)
  layout.columns = clamp(editorWindow.columns:getValue(), 1, 8)
  layout.gapX = clamp(editorWindow.gapX:getValue(), iconWidth, 200)
  layout.gapY = clamp(editorWindow.gapY:getValue(), iconHeight, 200)
  layout.gridSize = clamp(editorWindow.gridSize:getValue(), 1, 32)
end

local function fillLayoutControls()
  if not editorWindow then return end
  local layout = editorConfig.layout
  editorWindow.originX:setValue(tonumber(layout.originX) or layoutDefaults.originX)
  editorWindow.originY:setValue(tonumber(layout.originY) or layoutDefaults.originY)
  editorWindow.columns:setValue(tonumber(layout.columns) or layoutDefaults.columns)
  editorWindow.gapX:setValue(tonumber(layout.gapX) or layoutDefaults.gapX)
  editorWindow.gapY:setValue(tonumber(layout.gapY) or layoutDefaults.gapY)
  editorWindow.gridSize:setValue(tonumber(layout.gridSize) or layoutDefaults.gridSize)
  editorWindow.snapEnabled:setChecked(layout.snapEnabled ~= false)
  editorWindow.moveMode:setChecked(editMode)
end

local function alignIconsToGrid()
  if not editorWindow then return end
  readLayoutControls()
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

    if rootWidth and x + iconWidth > rootWidth then
      editorWindow.iconStatus:setText("La distribucion excede el ancho")
      editorWindow.iconStatus:setColor("#ff8a8a")
      fillLayoutControls()
      return
    end
    if rootHeight and y + iconHeight > rootHeight then
      editorWindow.iconStatus:setText("La distribucion excede el alto")
      editorWindow.iconStatus:setColor("#ff8a8a")
      fillLayoutControls()
      return
    end

    positions[index] = {entry = entry, x = x, y = y}
  end

  for _, position in ipairs(positions) do
    position.entry.config.x = position.x
    position.entry.config.y = position.y
    applyIconVisual(position.entry, true)
  end

  fillLayoutControls()
  refreshEditorList()
  editorWindow.iconStatus:setText("Iconos alineados")
  editorWindow.iconStatus:setColor("#8cff9a")
end

local function resetEntry(entry)
  if not entry then return end
  editorConfig.icons[entry.id] = {}
  entry.config = editorConfig.icons[entry.id]
  applyIconVisual(entry, true)
  updateRow(entry)
  if selectedEntry == entry then fillSelectedEditor(entry) end
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

  editorWindow.applyIcon.onClick = function()
    if not selectedEntry then return end

    local configuredText = iconText(editorWindow.selectedName:getText())
    local newVisible = editorWindow.selectedVisible:isChecked()
    local newX = clamp(editorWindow.selectedX:getValue(), 0, 4000)
    local newY = clamp(editorWindow.selectedY:getValue(), 0, 4000)

    if editorConfig.layout.snapEnabled ~= false then
      newX = roundToGrid(newX)
      newY = roundToGrid(newY)
    end

    local overlapping = findOverlappingIcon(selectedEntry, newX, newY, newVisible)
    if overlapping then
      editorWindow.iconStatus:setText("Espacio ocupado por " .. effectiveText(overlapping):gsub("\n", " "))
      editorWindow.iconStatus:setColor("#ff8a8a")
      return
    end

    selectedEntry.config.text = configuredText ~= "" and configuredText or nil
    selectedEntry.config.itemId = math.max(0, tonumber(editorWindow.selectedItem:getItemId()) or 0)
    selectedEntry.config.visible = newVisible
    selectedEntry.config.x = newX
    selectedEntry.config.y = newY
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

  editorWindow.moveMode.onClick = function(widget)
    setEditMode(not editMode)
    widget:setChecked(editMode)
  end

  editorWindow.snapEnabled.onClick = function(widget)
    editorConfig.layout.snapEnabled = not (editorConfig.layout.snapEnabled ~= false)
    widget:setChecked(editorConfig.layout.snapEnabled ~= false)
  end

  editorWindow.gridSize.onValueChange = function(widget, value)
    editorConfig.layout.gridSize = clamp(value, 1, 32)
  end

  editorWindow.alignGrid.onClick = alignIconsToGrid

  editorWindow.resetAll.onClick = function()
    editorConfig.icons = {}
    for key, value in pairs(layoutDefaults) do editorConfig.layout[key] = value end
    editorConfig.layout.snapEnabled = true

    for _, entry in ipairs(activeIcons) do
      entry.config = getIconConfig(entry.id)
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
    if not visible then setEditMode(false) end
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
