-- Reduce camera/layout work from high frequency mouse events on large maps.
-- Keep the client's own drag calculation and flush the last position on release.

local minimapModule = modules and modules.game_minimap
if not minimapModule then return end

-- A destroyed OTC userdata may crash even when looking up isDestroyed.
-- Record destruction while onDestroy is still valid; later use only Lua keys.
local lifeOwner = minimapModule
-- OTC can return distinct Lua userdata for the same native widget.
-- Table keys use raw userdata identity, so match native equality explicitly.
local mapLife = lifeOwner._pruebasMapLife
if not mapLife or mapLife.version ~= 2 then
  local dead = mapLife and mapLife.dead or setmetatable({}, {__mode = "k"})
  mapLife = {version = 2, dead = dead, watched = {}, retiredMaps = {}}
  lifeOwner._pruebasMapLife = mapLife

  function mapLife.isDead(widget)
    if not widget then return true end
    for known in pairs(mapLife.dead) do if known == widget then return true end end
    for _, known in ipairs(mapLife.retiredMaps) do if known == widget then return true end end
    return false
  end

  local function callDestroy(callback, ...)
    if type(callback) == "function" then return callback(...) end
    if type(callback) == "table" then
      for _, handler in pairs(callback) do
        if type(handler) == "function" then
          local result = handler(...)
          if result then return result end
        end
      end
    end
  end

  function mapLife.watch(widget, owner, callback)
    if mapLife.isDead(widget) then return false end
    local entry
    for known, watched in pairs(mapLife.watched) do
      if known == widget then entry = watched; break end
    end
    if not entry then
      entry = {widget = widget, callbacks = {}, original = widget.onDestroy}
      mapLife.watched[widget] = entry
      widget.onDestroy = function(self, ...)
        local known = entry.widget
        mapLife.dead[known], mapLife.dead[self] = true, true
        mapLife.watched[known] = nil
        if entry.callbacks.drag or entry.callbacks.exiva or entry.callbacks.dragProfile then
          table.insert(mapLife.retiredMaps, known)
          if #mapLife.retiredMaps > 32 then table.remove(mapLife.retiredMaps, 1) end
        end
        -- Dispose the canonical Lua record, even if self is a fresh userdata.
        for _, dispose in pairs(entry.callbacks) do dispose(known) end
        return callDestroy(entry.original, self, ...)
      end
    end
    if owner and callback then entry.callbacks[owner] = callback end
    return true
  end
end


local CONTROLLER_KEY = "_pruebasMinimapDragController"
local FRAME_INTERVAL = 17
local MIN_WIDTH, MIN_HEIGHT = 560, 360
local previous = minimapModule[CONTROLLER_KEY]
if previous then
  if previous.lifetimeVersion == 2 then
    previous.stop()
  else
    -- Quiesce the old polling callback without inspecting any expired handles.
    previous.enabled = false
    for widget in pairs(previous.records or {}) do
      mapLife.dead[widget] = true
      previous.records[widget] = nil
    end
  end
end

storage.minimapDrag = storage.minimapDrag or {}
local settings = storage.minimapDrag
if settings.enabled == nil then settings.enabled = true end
local controller = {lifetimeVersion = 2, enabled = settings.enabled == true, records = {}}
minimapModule[CONTROLLER_KEY] = controller

local bot = modules.game_bot
local selector = bot and bot.contentsPanel and bot.contentsPanel.config
local selectorAlive = selector and not mapLife.isDead(selector)
local getProfile = selectorAlive and selector.getCurrentOption or nil
if selectorAlive then
  mapLife.watch(selector, "dragProfile", function() selectorAlive = false end)
end
local function activeProfile()
  if not selectorAlive or type(getProfile) ~= "function" then return false end
  local ok, option = pcall(getProfile, selector)
  return ok and option and option.text == "pruebas"
end

local function alive(widget)
  return widget and not mapLife.isDead(widget)
end

local function sameContext(widget, record)
  return widget.dragReference == record.reference and
    widget.dragCameraReference == record.cameraReference and
    widget:getZoom() == record.zoom
end

local function reset(record)
  record.pending = nil
  record.lastUpdate = nil
  record.reference = nil
  record.cameraReference = nil
  record.zoom = nil
end

local function flush(widget, record)
  local pending = record.pending
  record.pending = nil
  if pending and alive(widget) and sameContext(widget, record) then
    return record.original.onDragMove(widget, pending.pos, pending.moved)
  end
end

local function restore(widget, record)
  if alive(widget) then
    for event, wrapper in pairs(record.wrappers) do
      if widget[event] == wrapper then widget[event] = record.original[event] end
    end
  end
  reset(record)
  controller.records[record.widget] = nil
end

function controller.stop(flushPending)
  controller.enabled = false
  for widget, record in pairs(controller.records) do
    if flushPending ~= false and alive(widget) then flush(widget, record) end
    restore(widget, record)
  end
end

local function canLimit(widget)
  if not controller.enabled or minimapModule[CONTROLLER_KEY] ~= controller or not activeProfile() then
    return false
  end
  if not g_clock or type(g_clock.millis) ~= "function" then return false end
  local size = widget:getSize()
  -- Only throttle the standard absolute drag model; unknown handlers pass through.
  return (size.width >= MIN_WIDTH or size.height >= MIN_HEIGHT) and
    type(widget.dragReference) == "table" and type(widget.dragCameraReference) == "table"
end

local function copyPoint(point)
  return point and {x = point.x, y = point.y} or nil
end

local function combinedMove(pending, moved)
  local previousMove = pending and pending.moved
  if previousMove and moved then
    return {x = previousMove.x + moved.x, y = previousMove.y + moved.y}
  end
  return copyPoint(moved or previousMove)
end

local function attach(widget)
  if not alive(widget) then return end
  for known in pairs(controller.records) do
    if known == widget then return end
  end
  if type(widget.getSize) ~= "function" or type(widget.getZoom) ~= "function" or
    type(widget.onDragEnter) ~= "function" or type(widget.onDragMove) ~= "function" or
    type(widget.onDragLeave) ~= "function" then return end

  local record = {widget = widget, original = {}, wrappers = {}}
  for _, event in ipairs({"onDragEnter", "onDragMove", "onDragLeave", "onMouseWheel"}) do
    if type(widget[event]) == "function" then record.original[event] = widget[event] end
  end

  record.wrappers.onDragEnter = function(self, ...)
    reset(record)
    if not controller.enabled or not activeProfile() then restore(self, record) end
    return record.original.onDragEnter(self, ...)
  end

  record.wrappers.onDragMove = function(self, pos, moved)
    if not canLimit(self) or not pos then
      -- Apply any deferred delta first, even if the map was resized during dragging.
      flush(self, record)
      reset(record)
      if not controller.enabled or not activeProfile() then restore(self, record) end
      return record.original.onDragMove(self, pos, moved)
    end
    if not sameContext(self, record) then
      reset(record)
      record.reference = self.dragReference
      record.cameraReference = self.dragCameraReference
      record.zoom = self:getZoom()
    end

    local timestamp = g_clock.millis()
    local totalMove = combinedMove(record.pending, moved)
    if record.lastUpdate == nil or timestamp < record.lastUpdate or
      timestamp - record.lastUpdate >= FRAME_INTERVAL then
      record.pending = nil
      record.lastUpdate = timestamp
      record.lastResult = record.original.onDragMove(self, pos, totalMove)
      if record.lastResult ~= true then reset(record) end
      return record.lastResult
    end
    record.pending = {pos = copyPoint(pos), moved = totalMove}
    return true
  end

  record.wrappers.onDragLeave = function(self, ...)
    if controller.enabled and activeProfile() then flush(self, record) end
    reset(record)
    if not controller.enabled or not activeProfile() then restore(self, record) end
    return record.original.onDragLeave(self, ...)
  end

  if record.original.onMouseWheel then
    record.wrappers.onMouseWheel = function(self, ...)
      if controller.enabled and activeProfile() then flush(self, record) end
      reset(record)
      if not controller.enabled or not activeProfile() then restore(self, record) end
      return record.original.onMouseWheel(self, ...)
    end
  end
  mapLife.watch(widget, "drag", function(self)
    reset(record)
    controller.records[record.widget] = nil
  end)
  controller.records[widget] = record
  for event, wrapper in pairs(record.wrappers) do widget[event] = wrapper end
end

function controller.refresh()
  if not controller.enabled or minimapModule[CONTROLLER_KEY] ~= controller then return end
  if not activeProfile() then controller.stop() return end
  if type(minimapModule.getMiniMapUi) == "function" then
    local ok, widget = pcall(minimapModule.getMiniMapUi)
    if ok then attach(widget) end
  end
  attach(minimapModule.minimapWidget)
  local cyclopedia = modules.game_cyclopedia
  local map = cyclopedia and cyclopedia.MapCyclopedia
  if map and type(map.getMinimapWidget) == "function" then
    local ok, widget = pcall(map.getMinimapWidget)
    if ok then attach(widget) end
  end
end

local _, rightPanel = BotSettings.getColumns("basic")
local checkbox = UI.createWidget("BotSettingsCheckBox", rightPanel)
checkbox:setText("Mapa grande fluido")
checkbox:setTooltip("Agrupa el arrastre del mapa grande a unas 60 actualizaciones por segundo.\nDesactiva para comparar con el movimiento original del cliente.")
checkbox:setOn(controller.enabled)
checkbox.onClick = function(widget)
  settings.enabled = not widget:isOn()
  widget:setOn(settings.enabled)
  if settings.enabled then
    controller.enabled = true
    controller.refresh()
  else
    controller.stop()
  end
end
local originalDestroy = checkbox.onDestroy
checkbox.onDestroy = function(...)
  controller.stop(false)
  if type(originalDestroy) == "function" then return originalDestroy(...) end
end

controller.refresh()
macro(1000, function() controller.refresh() end)
