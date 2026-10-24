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

local layoutDefaults = {visualMode="classic",barOpacity=70,holdToMove=false}

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
local editMode = false
local syncingSelectedControls = false
local selectEditorEntry
local rememberIconChange
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
  return isIconVisible(entry) and (editMode or editorConfig.layout.holdToMove == true)
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
  if entry.target and vBot.IconSources then return vBot.IconSources.open(entry.id) end
  local id = iconModules[entry.id]
  if not id then return false end -- Hold Target is intentionally toggle-only.
  if Helper and Helper.valid and Helper.valid() then
    if type(Helper.openIconConfiguration)=="function" then return Helper.openIconConfiguration(id) end
    if Helper.openModule then Helper.openModule(id);return true end
  end
  return false
end

local lastRightEntry
local function openAttackFromTargetIcon()
  if Helper and Helper.valid and Helper.valid() then
    if type(Helper.openAttackFromTargetIcon)=='function' then return Helper.openAttackFromTargetIcon() end
    if type(Helper.openIconConfiguration)=='function' then return Helper.openIconConfiguration('attackbot') end
    if type(Helper.openModule)=='function' then Helper.openModule('attackbot');return true end
  end
  return false
end
local function gestureTime()
  if type(now)=='number' then return now end
  if g_clock and type(g_clock.millis)=='function' then return g_clock.millis() end
  return os.clock()*1000
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
  if iconModules[entry.id] or entry.target then tooltip = tooltip .. "\nClic derecho: abrir configuracion" end
  if entry.id=="TargetIcon" then tooltip=tooltip.."\nDoble clic derecho: AttackBot" end
  if entry.target and entry.target.state()==nil then tooltip="Clic: abrir "..entry.target.name end
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


  -- Manual drops keep the chosen position, even when hit boxes overlap.
  -- Persist the final window pixels of this icon only.
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

local function createIcon(data)
  if iconById[data.id] then return iconById[data.id] end
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
        local actual=readScriptState(data.botScript)
        guard.syncing=true;syncIconSwitch(icon,actual);guard.syncing=false
        saveIconState(data.id,actual)
        if entry then setTextColor(entry,actual)end
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

      widget.onDragEnter = function(changedWidget,mousePos)
        if not canStartDrag(entry) then return false end
        if rememberIconChange then rememberIconChange(entry) end
        if entry.gesture then entry.gesture.dragged=true end
        mousePos=not editMode and entry.gesture and entry.gesture.position or mousePos
        local p=getWidgetPosition(changedWidget)
        changedWidget:breakAnchors()
        changedWidget.movingReference={x=mousePos.x-p.x,y=mousePos.y-p.y}
        changedWidget.dragState={x=p.x,y=p.y,children={}}
        for _,child in ipairs({changedWidget.text,changedWidget.item}) do
          local pos=getWidgetPosition(child)
          if pos then child:breakAnchors();changedWidget.dragState.children[#changedWidget.dragState.children+1]={widget=child,x=pos.x,y=pos.y} end
        end
        if selectEditorEntry then selectEditorEntry(entry) end
        return true
      end
      widget.onDragMove = function(changedWidget,mousePos)
        if not currentIconRuntime(entry) or not entry.dragEnabled or not changedWidget.movingReference then return false end
        local drag=changedWidget.dragState
        if not drag then return false end
        local pos=setWidgetPosition(changedWidget,mousePos.x-changedWidget.movingReference.x,mousePos.y-changedWidget.movingReference.y)
        for _,child in ipairs(drag.children) do child.widget:move(child.x+pos.x-drag.x,child.y+pos.y-drag.y) end
        return true
      end
      widget.onDragLeave = function(changedWidget)
        if not changedWidget.movingReference then return false end
        changedWidget.movingReference=nil;changedWidget.dragState=nil
        saveDraggedPosition(entry);styleIcon(changedWidget,entry);applyIconVisual(entry,false)
        if entry.gesture then entry.gesture.pressed=false end
        return true
      end

      -- Left release toggles; right press opens the original configuration.
      -- Native drag completion consumes the left click; suppress it as well
      -- when a client sends onClick after moving. No timers or hold threshold.
      local nativeClick = widget.onClick
      local function toggleIcon()
        if not currentIconRuntime(entry) or editMode then return end
        if entry.target and not entry.target.available() then
          if vBot.IconSources then vBot.IconSources.notify("Origen no disponible; se conserva el icono.") end
          return
        end
        entry.guard.syncing = true
        syncIconSwitch(widget, readScriptState(entry.botScript))
        entry.guard.syncing = false
        if data.action then
          if type(entry.botScript.stepUp)=="function" then entry.botScript.stepUp() end
        elseif entry.target and entry.target.state()==nil then (entry.target.run or entry.target.open)()
        elseif nativeClick then nativeClick(widget) end
      end
      if data.action and widget.setTooltip then
        widget:setTooltip("Spy Level: clic izquierdo sube, derecho baja. Mover iconos permite arrastrar.")
      end
      widget.onDoubleClick = function() return false end
      widget.onMousePress = function(changedWidget, mousePos, mouseButton)
        if not currentIconRuntime(entry) then return true end
        if lastRightEntry and (lastRightEntry~=entry or mouseButton~=rightMouseButton or editMode) then
          lastRightEntry.lastRightClick=nil;lastRightEntry=nil
        end
        if mouseButton == rightMouseButton then
          if changedWidget.dragState then changedWidget.onDragLeave(changedWidget) end
          entry.gesture = {cancelled=true, pressed=false, button=rightMouseButton}
          if editMode then
            if selectEditorEntry then selectEditorEntry(entry) end
            return true
          end
          if data.action then
            if editMode then
              if selectEditorEntry then selectEditorEntry(entry) end
            elseif type(entry.botScript.stepDown)=="function" then entry.botScript.stepDown() end
          elseif entry.id=='TargetIcon' and not editMode then
            local current=gestureTime()
            local last=entry.lastRightClick
            local dx=last and mousePos.x-last.x or 0
            local dy=last and mousePos.y-last.y or 0
            if last and current>=last.at and current-last.at<=400 and dx*dx+dy*dy<=64 then
              entry.lastRightClick=nil;lastRightEntry=nil
              openAttackFromTargetIcon()
            else
              entry.lastRightClick={at=current,x=mousePos.x,y=mousePos.y}
              lastRightEntry=entry
              openIconConfiguration(entry)
            end
          else entry.lastRightClick=nil;openIconConfiguration(entry) end
          return true
        end
        entry.lastRightClick=nil
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
      return entry
    else
      warn("[Icon Editor] No se pudo crear: " .. data.id)
    end
  else
    print("[Icon Editor] Script no encontrado: " .. data.id)
  end
end


for _,data in ipairs(iconList) do if data.botScript then createIcon(data) end end

-- One catalog and one form. Every drag moves one icon only.
dofile('/vBot/icon_sources.lua')
local Sources=vBot.IconSources
editorConfig.bindings=type(editorConfig.bindings)=='table' and editorConfig.bindings or {}
local selectedTarget,signature,undo,changing
local lastCatalogAt=0
local function editorStatus(message)
  if editorWindow then editorWindow.iconStatus:setText(message);editorWindow.iconStatus:setColor('#a9bbc6')end
end
Sources.onStatus=editorStatus
local function rememberEntry(entry)
  if not entry then return end
  local copy={};for k,v in pairs(entry.config)do copy[k]=v end
  undo={id=entry.id,config=copy}
  if editorWindow then editorWindow.undo:setEnabled(true)end
end
rememberIconChange=rememberEntry
local function initialPosition()
  local index=#activeIcons;local root=g_ui.getRootWidget()
  return math.max(0,math.floor(root:getWidth()/2)-30+(index%3)*64),math.max(0,math.floor(root:getHeight()/2)-40+math.floor(index%9/3)*50)
end
local function ensureIcon(target)
  local entry=iconById[target.id]
  if not entry then
    local x,y=initialPosition()
    entry=createIcon({id=target.id,text=target.name,itemId=3053,x=x,y=y,botScript=Sources.proxy(target.id)})
  end
  if entry then entry.target=target end
  return entry
end
-- Color selection edits the current form only; Guardar icono persists it.
local colorWindow,colorKey,colorTarget,colorDraft,colorEditing
local iconColors={
  {'Blanco','#ffffff'},{'Gris claro','#cbd5e1'},{'Gris','#94a3b8'},{'Gris oscuro','#475569'},
  {'Negro','#000000'},{'Crema','#fff1c2'},{'Amarillo','#ffdf00'},{'Dorado','#f0b55b'},
  {'Verde original','#00d43a'},{'Verde lima','#a3e635'},{'Verde claro','#8cff9a'},{'Esmeralda','#10b981'},
  {'Turquesa','#50d7d4'},{'Cian','#22d3ee'},{'Celeste','#38bdf8'},{'Azul','#3b82f6'},
  {'Rojo original','#ff3b3b'},{'Rojo claro','#f87171'},{'Naranja','#f97316'},{'Coral','#fb7185'},
  {'Rosa','#f472b6'},{'Fucsia','#d946ef'},{'Violeta','#8b5cf6'},{'Lavanda','#c4b5fd'}
}
local function iconColor(value)
  local color=tostring(value or''):gsub('^%s+',''):gsub('%s+$','')
  if color:match('^#%x%x%x%x%x%x$')then return color:lower()end
end
local function paintColorButton(button,color)
  button.helperAppearanceFixed=true
  button:setBackgroundColor(color)
  if type(button.mergeStyle)=='function'then
    button:mergeStyle({['background-color']=color,['$hover !disabled']={['background-color']=color},['$pressed']={['background-color']=color}})
  end
end
local function closeColorPalette()
  colorKey,colorTarget,colorDraft=nil,nil,nil
  if colorWindow and liveIconWidget(colorWindow)then colorWindow:hide()end
end
local function validColorOwner()
  return positionGeneration==vBot.IconPositionGeneration and selectedTarget and selectedTarget.id==colorTarget
    and editorWindow and liveIconWidget(editorWindow)and editorWindow:isVisible()
end
local function openColorPalette(key)
  if not selectedTarget or positionGeneration~=vBot.IconPositionGeneration then return false end
  if not editorWindow:isVisible()then return false end
  if not colorWindow or not liveIconWidget(colorWindow)then
    colorWindow=g_ui.createWidget('IconEditorColorWindow',g_ui.getRootWidget())
    colorWindow.botWidget=true;colorWindow:hide()
    if HelperTheme and HelperTheme.decorate then HelperTheme.decorate(colorWindow,'IconEditorColorWindow')end
    colorWindow.preview.helperAppearanceFixed=true
    local function preview(color)
      colorDraft=color;colorWindow.preview:setColor(color)
      colorWindow.feedback:setText('Color listo para usar.')
      colorWindow.useColor:setEnabled(true)
    end
    for i,spec in ipairs(iconColors)do
      local color,name=spec[2],spec[1]
      local button=colorWindow['color'..i]
      paintColorButton(button,color);button:setTooltip(name..' ('..color..')')
      button.onClick=function()
        if not validColorOwner()then closeColorPalette();return end
        colorWindow.colorHex:setText(color)
      end
    end
    colorWindow.colorHex.onTextChange=function(field)
      if colorEditing then return end
      local color=iconColor(field:getText())
      if color then preview(color)
      else colorDraft=nil;colorWindow.useColor:setEnabled(false);colorWindow.feedback:setText('Elige una muestra o escribe #RRGGBB.')end
    end
    colorWindow.useColor.onClick=function()
      if not validColorOwner()then closeColorPalette();return false end
      local color=iconColor(colorWindow.colorHex:getText())
      if not color then return false end
      editorWindow[colorKey..'ColorHex']:setText(color)
      closeColorPalette();editorStatus('Color elegido. Pulsa Guardar icono.');return true
    end
    colorWindow.cancel.onClick=closeColorPalette
    colorWindow.closeButton.onClick=closeColorPalette
    colorWindow.onEscape=closeColorPalette
    colorWindow.onClose=function()closeColorPalette();return true end
  end
  colorKey,colorTarget=key,selectedTarget.id
  colorWindow.heading:setText(key=='on'and'Texto activo'or'Texto inactivo')
  colorDraft=iconColor(editorWindow[key..'ColorHex']:getText())or(key=='on'and'#00d43a'or'#ff3b3b')
  colorEditing=true;colorWindow.colorHex:setText(colorDraft);colorEditing=false
  colorWindow.preview:setColor(colorDraft);colorWindow.feedback:setText('Elige un color de la paleta.')
  colorWindow.useColor:setEnabled(true)
  local root=g_ui.getRootWidget();local bounds=root:getRect();local size=colorWindow:getSize()
  local origin=editorWindow:getPosition()
  colorWindow:breakAnchors()
  colorWindow:setPosition({x=math.max(bounds.x,math.min(origin.x+130,bounds.x+bounds.width-size.width)),
    y=math.max(bounds.y,math.min(origin.y+50,bounds.y+bounds.height-size.height))})
  colorWindow:show();colorWindow:raise();colorWindow:focus();return true
end

local function showTarget(target)
  if not editorWindow or not target then return end
  closeColorPalette()
  selectedTarget=target
  selectedEntry=iconById[target.id]
  local config=selectedEntry and selectedEntry.config or editorConfig.icons[target.id]or{}
  changing=true
  editorWindow.selectedTitle:setText(target.name)
  editorWindow.source:setText(target.kind=='bot'and('Bot / '..target.source)or target.kind=='script'and'Mis scripts' or('Macro / '..target.source))
  editorWindow.selectedName:setText((config.text or target.legacy and target.legacy.text or target.name):gsub('\n',' / '))
  editorWindow.selectedItem:setItemId(selectedEntry and effectiveItemId(selectedEntry)or tonumber(config.itemId)or 3053)
  editorWindow.selectedVisible:setChecked(selectedEntry~=nil and isIconVisible(selectedEntry))
  editorWindow.selectedVisualMode:setOption((selectedEntry and effectiveVisualMode(selectedEntry)or config.visualMode)=='bar'and'Barra'or'Icono')
  editorWindow.onColorHex:setText(selectedEntry and effectiveOnColor(selectedEntry)or config.onColor or'#00d43a')
  editorWindow.offColorHex:setText(selectedEntry and effectiveOffColor(selectedEntry)or config.offColor or'#ff3b3b')
  local x,y=initialPosition()
  editorWindow.selectedX:setValue(selectedEntry and effectiveX(selectedEntry)or tonumber(config.x)or x)
  editorWindow.selectedY:setValue(selectedEntry and effectiveY(selectedEntry)or tonumber(config.y)or y)
  editorWindow.sourceHint:setText(target.note or(target.run and'Clic: ejecutar. Clic derecho: configuracion.'or target.state()==nil and'Clic: abrir. Clic derecho: configuracion.'or'Clic: ON/OFF. Clic derecho: configuracion.'))
  editorWindow.openSource:setEnabled(target.available())
  changing=false
end
selectEditorEntry=function(entry)
  local target=Sources.targets[entry.id]
  if target then showTarget(target)end
end
local function refreshCatalog(force)
  local current=Sources.collect(iconList,iconModules,editorConfig.bindings)
  for id in pairs(editorConfig.bindings)do
    local target=Sources.targets[id]
    if target then ensureIcon(target)end
  end
  for _,entry in ipairs(activeIcons)do
    entry.target=Sources.targets[entry.id]
    if entry.target and not entry.target.legacy and entry.defaults.text~=entry.target.name then
      entry.defaults.text=entry.target.name;applyIconVisual(entry,false)
    end
  end
  if current~=signature or force then
    signature=current
    if refreshEditorList then refreshEditorList(true)end
  end
end
refreshEditorList=function(preserveSelected)
  if not editorWindow then return end
  local query=editorWindow.search:getText():lower():gsub('^%s+',''):gsub('%s+$','')
  local choice=editorWindow.filter:getCurrentOption();local filter=choice and choice.text or'Todo'
  local present,count={},0
  for _,target in ipairs(Sources.ordered)do
    present[target.id]=true
    local row=editorRows[target.id]
    if not row then
      row=g_ui.createWidget('IconEditorRow',editorWindow.iconList);editorRows[target.id]=row
      row:setId('iconEditorRow'..target.id)
      row.onClick=function()showTarget(Sources.targets[target.id]);return true end
      row.visible.onClick=function()
        showTarget(Sources.targets[target.id]);editorWindow.selectedVisible.onClick();return true
      end
    end
    local entry=iconById[target.id]
    local title=entry and effectiveText(entry):gsub('\n',' ')or target.name
    local visible=entry and isIconVisible(entry)or false
    row.name:setText(title);row.coords:setText(target.kind=='bot'and'Bot'or target.kind=='script'and'Script'or'Macro')
    row.visible:setChecked(visible)
    row.item:setItemId(entry and effectiveItemId(entry)or 3053)
    row:setTooltip(target.name..'\n'..target.source..(target.note and'\n'..target.note or''))
    local matches=(filter=='Todo'or filter=='Mis iconos'and visible or filter=='Bot'and target.kind=='bot'or filter=='Mis scripts'and target.kind=='script'or filter=='Macros'and target.kind=='macro')
      and(query==''or(title..' '..target.name..' '..target.source):lower():find(query,1,true))
    row:setVisible(matches and true or false)
    if matches then count=count+1 end
  end
  for id,row in pairs(editorRows)do if not present[id]then row:hide()end end
  editorWindow.listTitle:setText('Funciones ('..count..')')
  editorWindow.emptySearch:setVisible(count==0)
  if selectedTarget then
    local target=Sources.targets[selectedTarget.id]
    if target then selectedTarget=target;if preserveSelected~=true then showTarget(target)end end
  elseif Sources.ordered[1]then showTarget(Sources.ordered[1])end
end
local function saveFields()
  if changing or not selectedTarget then return end
  local target=selectedTarget
  local name=editorWindow.selectedName:getText():gsub('^%s+',''):gsub('%s+$',''):gsub('%s*/%s*','\n')
  local on,off=editorWindow.onColorHex:getText(),editorWindow.offColorHex:getText()
  if not on:match('^#%x%x%x%x%x%x$')or not off:match('^#%x%x%x%x%x%x$')then editorStatus('Color invalido: usa #RRGGBB.');return false end
  local entry=ensureIcon(target);if not entry then return false end
  rememberEntry(entry)
  local cfg=entry.config
  cfg.text=name~=''and name or nil;cfg.itemId=math.max(0,tonumber(editorWindow.selectedItem:getItemId())or 0)
  local option=editorWindow.selectedVisualMode:getCurrentOption();cfg.visualMode=option and option.text=='Barra'and'bar'or'classic'
  cfg.onColor,cfg.offColor=on,off
  cfg.x,cfg.y=math.max(0,editorWindow.selectedX:getValue()),math.max(0,editorWindow.selectedY:getValue())
  editorConfig.bindings[target.id]={kind=target.kind,key=target.key,name=target.name}
  styleIcon(entry.widget,entry);applyIconVisual(entry,true);refreshEditorList();editorStatus('Icono guardado.');return true
end
local rootWidget=g_ui.getRootWidget()
local previous=rootWidget:recursiveGetChildById('IconEditorWindow')
if previous then previous:destroy()end
editorWindow=UI.createWindow('IconEditorWindow',rootWidget)
editorWindow.simpleIcons=true;editorWindow:hide()
local oldPalette=rootWidget:recursiveGetChildById('IconEditorColorWindow')
if oldPalette then oldPalette:destroy()end
for _,key in ipairs({'on','off'})do
  local field,button=editorWindow[key..'ColorHex'],editorWindow[key..'ColorPick']
  field.onTextChange=function()local color=iconColor(field:getText());if color then paintColorButton(button,color)end end
  button.onClick=function()return openColorPalette(key)end
end
editorWindow.search.onTextChange=refreshEditorList
editorWindow.filter.onOptionChange=refreshEditorList
editorWindow.applyIcon.onClick=saveFields
editorWindow.selectedVisible.onClick=function()
  if not selectedTarget then return end
  local target=selectedTarget;local existing=iconById[target.id]
  local was=existing and isIconVisible(existing)or false
  local entry=ensureIcon(target)
  if not entry then return end
  rememberEntry(entry)
  entry.config.visible=not was
  editorConfig.bindings[target.id]={kind=target.kind,key=target.key,name=target.name}
  applyIconVisual(entry,false);showTarget(target);refreshEditorList()
  editorStatus(was and'Icono oculto; la funcion conserva su estado.'or'Icono visible. Arrastralo a su posicion.')
end
editorWindow.openSource.onClick=function()if selectedTarget then Sources.open(selectedTarget.id)end end
editorWindow.helperSetup.onClick=function()if Helper and Helper.valid()and Helper.openHelperSettings then Helper.openHelperSettings()end end
editorWindow.resetIcon.onClick=function()
  if not selectedEntry then return end
  rememberEntry(selectedEntry)
  local cfg=selectedEntry.config
  editorConfig.icons[selectedEntry.id]={visible=cfg.visible,x=cfg.x,y=cfg.y};selectedEntry.config=editorConfig.icons[selectedEntry.id]
  styleIcon(selectedEntry.widget,selectedEntry);applyIconVisual(selectedEntry,true);refreshEditorList();editorStatus('Aspecto restablecido.')
end
editorWindow.undo.onClick=function()
  if not undo then return end
  local entry=iconById[undo.id]
  if entry then editorConfig.icons[entry.id]=undo.config;entry.config=undo.config;styleIcon(entry.widget,entry);applyIconVisual(entry,true)end
  undo=nil;editorWindow.undo:setEnabled(false);refreshEditorList();editorStatus('Cambio deshecho.')
end
local function setDragging(enabled)
  editorConfig.layout.holdToMove=enabled==true
  for _,entry in ipairs(activeIcons)do
    if entry.widget.dragState then entry.widget.onDragLeave(entry.widget)end
    if entry.gesture then entry.gesture.cancelled=true end
    setIconDraggable(entry,canDragEntry(entry))
  end
  editorWindow.moveIcons:setChecked(editorConfig.layout.holdToMove)
end
editorWindow.moveIcons.onClick=function()setDragging(not editorConfig.layout.holdToMove)end
editorWindow.onVisibilityChange=function(_,visible)
  if not visible then closeColorPalette()end
  editMode=visible==true
  for _,entry in ipairs(activeIcons)do setIconDraggable(entry,canDragEntry(entry))end
end
editorWindow.closeButton.onClick=function()editorWindow:hide()end
local function prepare()
  refreshCatalog(true);editorWindow.moveIcons:setChecked(editorConfig.layout.holdToMove==true)
  return true
end
local function open()
  prepare();editorWindow:show();editorWindow:raise();editorWindow:focus()
end
setDefaultTab('Tools')
local editorButton=UI.Button('Iconos',open)
editorButton:setTooltip('Elige una funcion o script y crea su icono. Cada icono se mueve por separado.')
setDefaultTab('Main')
vBot.IconEditor={version=2,getWindow=function()return editorWindow end,getButton=function()return editorButton end,
  prepare=prepare,open=open,close=function()editorWindow:hide()end,
  showPage=function()prepare()end,isHoldToMove=function()return editorConfig.layout.holdToMove==true end,setHoldToMove=setDragging,
  refresh=function()refreshCatalog(true)end,
  register=function(id,api)if RinoScriptControls and RinoScriptControls.registerIcon then return RinoScriptControls.registerIcon(id,api)end;return false end}
refreshCatalog(true)
setDragging(editorConfig.layout.holdToMove==true)
local function restorePositions()
  if positionGeneration~=vBot.IconPositionGeneration then return end
  for _,entry in ipairs(activeIcons)do
    if liveIconWidget(entry.widget)and not entry.widget.dragState then attachIconToWindow(entry.widget);applyIconVisual(entry,true,true)end
  end
end
for _,delay in ipairs({250,750,1500,3000,6000})do schedule(delay,restorePositions)end
macro(200,function()
  if positionGeneration~=vBot.IconPositionGeneration then return end
  local time=gestureTime()
  if time-lastCatalogAt>=1000 then lastCatalogAt=time;refreshCatalog(false)end
  for _,entry in ipairs(activeIcons)do
    local enabled=readScriptState(entry.botScript)
    if liveIconWidget(entry.widget)then
      if entry.widget.isOn and entry.widget:isOn()~=enabled then
        entry.guard.syncing=true;syncIconSwitch(entry.widget,enabled);entry.guard.syncing=false;saveIconState(entry.id,enabled)
      end
      setTextColor(entry,enabled)
    end
  end
end)
