-- Hotkeys: teclas, botones del raton y rueda, cada uno con su accion (say, usar objeto,
-- funcion del bot o script). La lista se guarda por perfil en storage.customHotkeys.
setDefaultTab("Main")

local panelName = "customHotkeys"
if type(storage[panelName]) ~= "table" then storage[panelName] = {enabled = true, list = {}} end
local config = storage[panelName]
if type(config.list) ~= "table" then config.list = {} end
if config.enabled == nil then config.enabled = true end
config.enabled = config.enabled == true

-- Name of an item for the window and the "last action" line. nil when the client does not know it.
local function itemName(id)
  if type(vBot) == "table" and type(vBot.ItemCounter) == "table" and type(vBot.ItemCounter.getName) == "function" then
    local ok, name = pcall(vBot.ItemCounter.getName, id)
    if ok and type(name) == "string" and name ~= "" and name ~= tostring(id) then return name end
  end
  if type(Item) == "table" and type(Item.create) == "function" then
    local ok, item = pcall(Item.create, id)
    if ok and item then
      local okData, data = pcall(function() return item:getMarketData() end)
      if okData and type(data) == "table" and type(data.name) == "string" and data.name ~= "" then return data.name end
      local okName, name = pcall(function() return item:getName() end)
      if okName and type(name) == "string" and name ~= "" then return name end
    end
  end
  return nil
end

-- BEGIN CORE (se prueba fuera del juego)
local KIND_LABELS = {say = "Say", use = "Usar objeto", self = "Usar en mi",
  target = "Usar en objetivo", func = "Funcion", script = "Script"}
local KIND_ORDER = {"say", "use", "self", "target", "func", "script"}
-- These three act on an item: the row shows a slot to drop it on (and its ID), not a text box.
local ITEM_KINDS = {use = true, self = true, target = true}
local FUNCTION_LABELS = {pause = "Pausar Bot", resume = "Reanudar Bot", pausetoggle = "Pausar/Reanudar Bot",
  cave_on = "Cave ON", cave_off = "Cave OFF", cave_toggle = "Cave ON/OFF",
  target_on = "Target ON", target_off = "Target OFF", target_toggle = "Target ON/OFF"}
local FUNCTION_ORDER = {"pause", "resume", "pausetoggle", "cave_on", "cave_off", "cave_toggle",
  "target_on", "target_off", "target_toggle"}
local DEBOUNCE_MS = 100

local function trim(text)
  return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Item ID in a stored value, or nil when it is not a valid one (a whole number above 100).
local function itemIdOf(value)
  local id = tonumber(trim(value))
  if id and id > 100 and id == math.floor(id) then return id end
  return nil
end

local function clockMs()
  return tonumber(now) or os.time() * 1000
end

local function consoleLog(level, message, detail)
  if type(RinoConsole) ~= "table" or type(RinoConsole.valid) ~= "function" then return end
  local ok, valid = pcall(RinoConsole.valid)
  if ok and valid then pcall(RinoConsole.log, level, "Hotkeys", message, detail) end
end

local function safeCall(fn, ...)
  if type(fn) ~= "function" then return false end
  local ok, result = pcall(fn, ...)
  return ok and result ~= false
end

-- ---------------------------------------------------------------- nombres de teclas
-- Canonico: Ctrl+Alt+Shift+Base. Las teclas del teclado vienen del cliente ("Ctrl+F1"); el raton y la
-- rueda los pone este modulo: MouseN (N = numero de boton del cliente), WheelUp y WheelDown.
local function canonicalKey(key)
  if type(key) == "number" then key = KeyCodeDescs and KeyCodeDescs[key] or "" end
  local ctrl, alt, shift, base = false, false, false, nil
  for part in tostring(key or ""):gmatch("[^+]+") do
    part = trim(part)
    local name = part:lower():gsub("%s+", ""):gsub("_", "")
    if name == "ctrl" or name == "control" then ctrl = true
    elseif name == "alt" then alt = true
    elseif name == "shift" then shift = true
    elseif part ~= "" then
      local digit = name:match("^keynumpad(%d)$") or name:match("^numpad(%d)$") or
        name:match("^keypad(%d)$") or name:match("^kp(%d)$")
      -- Algunos clientes dan NIns para el 0 del teclado numerico.
      if name == "nins" then digit = "0" end
      if name == "esc" then base = "Escape"
      elseif digit then base = "Numpad" .. digit
      elseif name:match("^f%d%d?$") then base = name:upper()
      elseif #part == 1 then base = part:upper()
      else base = part end
    end
  end
  local out = {}
  if ctrl then out[#out + 1] = "Ctrl" end
  if alt then out[#out + 1] = "Alt" end
  if shift then out[#out + 1] = "Shift" end
  if base then out[#out + 1] = base end
  return table.concat(out, "+"), base
end

local function displayKey(canonical)
  canonical = tostring(canonical or "")
  if canonical == "" then return "Sin tecla" end
  local out = {}
  for part in canonical:gmatch("[^+]+") do
    if part == "WheelUp" then part = "Rueda arriba"
    elseif part == "WheelDown" then part = "Rueda abajo"
    elseif part:match("^Mouse%d+$") then part = "Raton " .. part:match("%d+") end
    out[#out + 1] = part
  end
  return table.concat(out, "+")
end

local function modifierPrefix()
  local prefix = ""
  local kb = g_keyboard
  for _, entry in ipairs({{"isCtrlPressed", "Ctrl+"}, {"isAltPressed", "Alt+"}, {"isShiftPressed", "Shift+"}}) do
    local fn = kb and kb[entry[1]]
    if type(fn) == "function" then
      local ok, value = pcall(fn)
      if ok and value == true then prefix = prefix .. entry[2] end
    end
  end
  return prefix
end

local function mouseKey(button)
  if type(button) ~= "number" or button <= 2 then return nil end -- izquierdo y derecho son del juego
  return modifierPrefix() .. "Mouse" .. tostring(math.floor(button))
end

local function wheelKey(direction)
  local up = type(MouseWheelUp) == "number" and MouseWheelUp or 1
  local down = type(MouseWheelDown) == "number" and MouseWheelDown or 2
  if direction == up then return modifierPrefix() .. "WheelUp" end
  if direction == down then return modifierPrefix() .. "WheelDown" end
  return nil
end

-- Con el foco en un campo de texto solo valen F1 a F12 y lo que lleve Ctrl o Alt.
local function typingFocus()
  local widget = g_ui and g_ui.getRootWidget and g_ui.getRootWidget()
  for _ = 1, 16 do
    if not widget then break end
    local class = widget.getClassName and widget:getClassName() or ""
    if tostring(class):lower():find("textedit", 1, true) and (not widget.isVisible or widget:isVisible()) then return true end
    widget = widget.getFocusedChild and widget:getFocusedChild() or nil
  end
  return false
end

local function allowedWhileTyping(canonical)
  local _, base = canonicalKey(canonical)
  if base and base:match("^F%d%d?$") then return true end
  return canonical:find("Ctrl+", 1, true) ~= nil or canonical:find("Alt+", 1, true) ~= nil
end

-- ---------------------------------------------------------------- lista
local function ensureRow(row)
  if type(row) ~= "table" then row = {} end
  if not row.id then row.id = tostring(os.time()) .. "-" .. tostring(math.random(100000, 999999)) end
  row.enabled = row.enabled ~= false
  row.key = canonicalKey(row.key or "")
  -- "Hechizo" ya no existe: era lo mismo que Say. Las filas guardadas con ese tipo pasan a Say.
  if row.kind == "cast" then row.kind = "say" end
  if not KIND_LABELS[row.kind] then row.kind = "say" end
  row.value = tostring(row.value or "")
  if row.kind == "func" and not FUNCTION_LABELS[row.value] then row.value = FUNCTION_ORDER[1] end
  return row
end

local function normalizeList()
  for index, row in ipairs(config.list) do config.list[index] = ensureRow(row) end
end

local function newRow()
  local row = ensureRow({enabled = true, key = "", kind = "say", value = ""})
  config.list[#config.list + 1] = row
  return row
end

-- ---------------------------------------------------------------- acciones
-- Say vale para una frase, una palabra magica o un hechizo. El texto se manda tal cual lo escribiste
-- (sin pasarlo a minusculas). Si es un hechizo conocido que esta en cooldown o sin mana, no se manda:
-- asi mantener la tecla no llena el chat de "You are exhausted". Un texto que no es hechizo siempre sale.
local function safeSay(text)
  text = trim(text)
  if text == "" then return false, "texto vacio" end
  if type(canCast) == "function" then
    local ok, ready = pcall(canCast, text)
    if ok and ready == false then return false, "cooldown" end
  end
  if safeCall(say, text) then return true end
  if g_game and g_game.talk and safeCall(function(words) return g_game.talk(words) end, text) then return true end
  return false, "no se pudo decir"
end

local function visibleItem(itemId)
  if type(findItem) ~= "function" then return nil end
  local ok, item = pcall(findItem, itemId)
  if ok and item then return item end
end

local function useItemId(itemId)
  itemId = tonumber(itemId)
  if not itemId or itemId <= 100 then return false, "id de objeto no valido" end
  local item = visibleItem(itemId)
  if item and (safeCall(use, item) or (g_game and g_game.use and safeCall(function(thing) return g_game.use(thing) end, item))) then
    return true
  end
  if g_game and g_game.useInventoryItem and safeCall(g_game.useInventoryItem, itemId) then return true end
  return false, "objeto no encontrado"
end

local function useItemWith(itemId, targetThing)
  itemId = tonumber(itemId)
  if not itemId or itemId <= 100 then return false, "id de objeto no valido" end
  if not targetThing then return false, "sin destino" end
  if g_game and g_game.useInventoryItemWith and safeCall(g_game.useInventoryItemWith, itemId, targetThing, 0) then return true end
  if safeCall(useWith, itemId, targetThing, 0) then return true end
  local item = visibleItem(itemId)
  if item and g_game and g_game.useWith and
    safeCall(function(source, destination) return g_game.useWith(source, destination, 0) end, item, targetThing) then
    return true
  end
  return false, "no se pudo usar"
end

local function currentTarget()
  if type(target) == "function" then
    local ok, creature = pcall(target)
    if ok and creature then return creature end
  end
  if g_game and g_game.getAttackingCreature then
    local ok, creature = pcall(function() return g_game.getAttackingCreature() end)
    if ok and creature then return creature end
  end
end

local function runFunction(id)
  if id == "pause" or id == "resume" or id == "pausetoggle" then
    if not (HelperPause and type(HelperPause.setPaused) == "function") then return false, "Pausar Bot no esta disponible" end
    local paused = type(HelperPause.isPaused) == "function" and HelperPause.isPaused() == true
    local want = id == "pause" or (id == "pausetoggle" and not paused)
    HelperPause.setPaused(want)
    return true
  end
  local engine, action = tostring(id):match("^(%a+)_(%a+)$")
  local api = engine == "cave" and CaveBot or engine == "target" and TargetBot or nil
  if not api then return false, "funcion desconocida" end
  if action == "toggle" then
    local on = type(api.isOn) == "function" and api.isOn() == true
    action = on and "off" or "on"
  end
  local method = action == "on" and "setOn" or action == "off" and "setOff" or nil
  if method and safeCall(api[method]) then return true end
  return false, "control no disponible"
end

local function runScript(code)
  code = trim(code)
  if code == "" then return false, "script vacio" end
  if type(loadstring) ~= "function" then return false, "loadstring no disponible" end
  local chunk, err = loadstring(code)
  if not chunk then return false, tostring(err or "error de Lua") end
  local ok, result = pcall(chunk)
  if not ok then return false, tostring(result or "error de Lua") end
  if result == false then return false, "el script devolvio false" end
  return true
end

local function execute(row)
  local kind, value = row.kind, tostring(row.value or "")
  if kind == "say" then return safeSay(value)
  elseif kind == "use" then return useItemId(value)
  elseif kind == "self" then return useItemWith(value, player)
  elseif kind == "target" then return useItemWith(value, currentTarget())
  elseif kind == "func" then return runFunction(value)
  elseif kind == "script" then return runScript(value) end
  return false, "tipo desconocido"
end

local function describe(row)
  local label = KIND_LABELS[row.kind] or row.kind
  if row.kind == "func" then return label .. " " .. (FUNCTION_LABELS[row.value] or row.value) end
  if row.kind == "script" then return label end
  if ITEM_KINDS[row.kind] then
    local id = itemIdOf(row.value)
    local name = id and itemName(id)
    if name then return label .. " " .. name .. " (" .. id .. ")" end
  end
  return label .. " " .. row.value
end

-- ---------------------------------------------------------------- disparo
local lastFired, lastError, announced = {}, {}, {}
local lastResult
local capturing -- fila que espera una tecla (la ventana la pone y la quita)

local function trigger(canonical)
  if not config.enabled or canonical == "" then return false end
  local current = clockMs()
  local matches = {}
  for _, row in ipairs(config.list) do
    if row.enabled ~= false and row.key == canonical then matches[#matches + 1] = row end
  end
  if #matches == 0 then return false end
  -- Una pulsacion puede llegar por mas de un camino (Down y Press) o la rueda en rafaga.
  if lastFired[canonical] and current - lastFired[canonical] < DEBOUNCE_MS then return true end
  lastFired[canonical] = current
  for _, row in ipairs(matches) do
    local ok, done, reason = pcall(execute, row)
    local success = ok and done == true
    local why = ok and reason or done
    lastResult = {at = current, key = canonical, text = describe(row), ok = success, reason = why}
    if success then
      -- Solo las tres primeras veces por tecla: son acciones manuales, no hace falta llenar la consola.
      announced[canonical] = (announced[canonical] or 0) + 1
      if announced[canonical] <= 3 then consoleLog("action", displayKey(canonical) .. " -> " .. describe(row)) end
    elseif why ~= "cooldown" and (not lastError[canonical] or current - lastError[canonical] >= 3000) then
      lastError[canonical] = current
      consoleLog("action", displayKey(canonical) .. ": no se pudo (" .. tostring(why) .. ")", describe(row))
    end
  end
  return true
end

-- Teclado: devuelve true si la pulsacion se uso (captura o hotkey).
local function handleKey(keys)
  local canonical, base = canonicalKey(keys)
  if not base then return false end -- solo modificadores
  if capturing then return false end -- la captura la resuelve la ventana
  if KeyCapture and KeyCapture.active() then return false end -- se esta eligiendo una tecla en otro campo
  if typingFocus() and not allowedWhileTyping(canonical) then return false end
  return trigger(canonical)
end
-- END CORE

-- ---------------------------------------------------------------- aspecto
-- La ventana y sus filas se pintan como las del resto de herramientas (tema y skin): se registran sus
-- descriptores a partir de los de la ventana del Timer Executor. Si algo falta, todo sigue funcionando.
local function registerSkin()
  local A = HelperAppearance
  local styles = type(A) == "table" and type(A.metadata) == "table" and A.metadata.styles
  if type(styles) ~= "table" then return false end
  if styles.CustomHotkeysWindow then return true end
  local template = styles.TimerExecutorWindow
  if type(template) ~= "table" then return false end
  local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = copy(v) end
    return result
  end
  local function node(kind, id)
    local base = styles[kind]
    if type(base) ~= "table" then return nil end
    local item = copy(base)
    item.style, item.type, item.id, item.children = kind, kind, id, {}
    return item
  end
  local function list(specs)
    local out = {}
    for _, spec in ipairs(specs) do out[#out + 1] = node(spec[1], spec[2]) end
    return out
  end
  local window = copy(template)
  window.style = "CustomHotkeysWindow"
  window.children = list({{"HelperThemeCheck", "master"}, {"HelperThemeButton", "add"}, {"HelperThemeLabel", "summary"},
    {"HelperThemeLabel", "colKey"}, {"HelperThemeLabel", "colKind"}, {"HelperThemeLabel", "colValue"},
    {"HelperThemeScroll", "list"}, {"HelperThemeLabel", "empty"}, {"HelperThemeLabel", "last"}, {"HelperThemeLabel", "hint"}})
  styles.CustomHotkeysWindow = window
  -- The item box holds the slot (BotItem, like every other item slot of the bot), its ID and its name.
  local function plain(kind, id)
    return node(kind, id) or {style = kind, type = kind, id = id, props = {}, states = {}, children = {}}
  end
  local itemBox = plain("Panel", "itemBox")
  itemBox.children = {plain("BotItem", "item"), plain("HelperThemeInput", "itemId"), plain("HelperThemeLabel", "itemName")}
  local row = {style = "CustomHotkeyRow", type = "Panel", props = {}, states = {},
    children = list({{"HelperThemeCheck", "enabled"}, {"HelperThemeButton", "key"}, {"HelperThemeCombo", "kind"},
      {"HelperThemeButton", "remove"}, {"HelperThemeInput", "value"}, {"HelperThemeCombo", "func"},
      {"HelperThemeButton", "script"}})}
  row.children[#row.children + 1] = itemBox
  styles.CustomHotkeyRow = row
  return true
end
pcall(registerSkin)

-- ---------------------------------------------------------------- ventana
local ui = setupUI([[
Panel
  height: 20

  HelperThemePower
    id: enabled
    anchors.left: parent.left
    anchors.top: parent.top
    width: 130
    height: 18
    text-align: center
    text: Hotkeys

  HelperThemeButton
    id: setup
    anchors.left: prev.right
    anchors.right: parent.right
    anchors.top: prev.top
    margin-left: 3
    height: 18
    text: Setup
]], parent)

local window
local rowWidgets = {}

local function activeCount()
  local count = 0
  for _, row in ipairs(config.list) do if row.enabled ~= false and row.key ~= "" then count = count + 1 end end
  return count
end

local function updateSummary()
  if not window then return end
  local total = #config.list
  window.master:setChecked(config.enabled)
  ui.enabled:setOn(config.enabled)
  window.empty:setVisible(total == 0)
  local text
  if total == 0 then text = "Sin hotkeys"
  else text = total .. (total == 1 and " hotkey" or " hotkeys") .. " | " .. activeCount() .. " activas" end
  if not config.enabled then text = "Apagadas | " .. text end
  window.summary:setText(text)
  window.summary:setColor(config.enabled and "#9dd1ce" or "#ffd166")
end

local function setKeyText(row, entry)
  local text = capturing == entry and "Pulsa tecla..." or displayKey(entry.key)
  row.key:setText(text)
  row.key:setColor(capturing == entry and "#f0b55b" or (entry.key == "" and "#8aa0ad" or "#e4edf3"))
end

-- The slot is a BotItem: the user drags the item onto it from a backpack. Read and write it the way the rest
-- of the bot does (HelperClientCompat), falling back to the plain widget calls.
local function slotItemId(widget)
  if type(HelperClientCompat) == "table" and type(HelperClientCompat.itemIdFromWidget) == "function" then
    local ok, id = pcall(HelperClientCompat.itemIdFromWidget, widget)
    if ok then return tonumber(id) or 0 end
  end
  local ok, id = pcall(function() return widget:getItemId() end)
  return ok and tonumber(id) or 0
end

local function setSlotItem(widget, id)
  if type(HelperClientCompat) == "table" and type(HelperClientCompat.setItemIdForDisplay) == "function" then
    pcall(HelperClientCompat.setItemIdForDisplay, widget, id)
  else
    pcall(function() widget:setItemId(id) end)
  end
end

local ITEM_HINT = "Arrastra aqui un objeto de tu mochila, o escribe su ID"

-- Paint the slot, the ID box and the name from entry.value. `skip` is the control the user is editing.
local function refreshItemView(row, entry, skip)
  local box = row.itemBox
  if not box then return end
  local id = itemIdOf(entry.value)
  row._hotkeySync = true
  if skip ~= "slot" then setSlotItem(box.item, id or 0) end
  if skip ~= "text" and tostring(box.itemId:getText() or "") ~= entry.value then box.itemId:setText(entry.value) end
  row._hotkeySync = false
  if id then
    local name = itemName(id)
    box.itemName:setText(name and (name .. " (id " .. id .. ")") or ("Objeto " .. id))
    box.itemName:setColor("#9dd1ce")
  elseif entry.value ~= "" then
    box.itemName:setText("ID no valido (un numero mayor que 100)")
    box.itemName:setColor("#f0b55b")
  else
    box.itemName:setText(ITEM_HINT)
    box.itemName:setColor("#8aa0ad")
  end
end

local function showInputs(row, entry)
  local itemKind = ITEM_KINDS[entry.kind] == true
  row.value:setVisible(entry.kind == "say")
  if row.itemBox then row.itemBox:setVisible(itemKind) end
  row.func:setVisible(entry.kind == "func")
  row.script:setVisible(entry.kind == "script")
  if entry.kind == "say" then row.value:setTooltip("Lo que dice el personaje: una frase, un comando (!bless) o un hechizo (exori gran). Un hechizo en cooldown no se manda.") end
  if itemKind then refreshItemView(row, entry) end
end

local function finishCapture(canonical)
  local entry = capturing
  capturing = nil
  if entry and canonical then entry.key = canonical end
  for _, item in ipairs(rowWidgets) do setKeyText(item.row, item.entry) end
  updateSummary()
end

local function editScript(entry)
  local title = "Script de " .. displayKey(entry.key)
  local function save(text) entry.value = tostring(text or "") end
  if type(UI.MultilineEditorWindow) == "function" then
    UI.MultilineEditorWindow(entry.value, {title = title, description = "Codigo Lua. Si devuelve false, se anota como fallo."}, save)
  end
end

local refreshRows
local function bindRow(row, entry)
  row.enabled:setChecked(entry.enabled)
  row.enabled.onClick = function(widget)
    entry.enabled = not entry.enabled
    widget:setChecked(entry.enabled)
    updateSummary()
  end

  setKeyText(row, entry)
  row.key.onClick = function()
    if capturing == entry then finishCapture(nil) return end
    capturing = entry
    for _, item in ipairs(rowWidgets) do setKeyText(item.row, item.entry) end
  end
  -- Raton y rueda: solo llegan al boton si el cursor esta sobre el. Izquierdo y derecho no se usan.
  row.key.onMousePress = function(_, _, button)
    if capturing == entry and type(button) == "number" and button > 2 then
      finishCapture(mouseKey(button))
      return true
    end
    return false
  end
  row.key.onMouseWheel = function(_, _, direction)
    if capturing == entry then
      local key = wheelKey(direction)
      if key then finishCapture(key) return true end
    end
    return false
  end
  row.key:setTooltip("Clic y pulsa la tecla. Para la rueda o un boton del raton (central, laterales), hazlo con el cursor sobre este boton. Esc cancela. El numero de Raton lo da el cliente.")

  if row.kind.setOption then row.kind:setOption(KIND_LABELS[entry.kind]) end
  row.kind.onOptionChange = function(widget)
    local option = widget:getCurrentOption()
    local chosen
    for id, label in pairs(KIND_LABELS) do if option and option.text == label then chosen = id end end
    entry.kind = chosen or "say"
    -- El valor de un tipo no sirve en otro (un codigo no es un texto para decir).
    if entry.kind == "func" then entry.value = FUNCTION_ORDER[1]; row.func:setOption(FUNCTION_LABELS[entry.value])
    else entry.value = ""; row.value:setText("") end
    showInputs(row, entry)
  end

  row.value:setText(entry.kind == "say" and entry.value or "")
  row.value.onTextChange = function(_, text)
    if entry.kind == "say" then entry.value = tostring(text or "") end
  end

  -- Item actions: drop the item on the slot, or type its ID. Each one updates the other.
  local box = row.itemBox
  if box then
    box.item:setTooltip("Arrastra aqui el objeto desde tu mochila. Para vaciarla, borra el ID.")
    box.itemId:setTooltip("ID del objeto: se rellena solo al soltar el objeto en la casilla.")
    box.item.onItemChange = function(widget)
      if row._hotkeySync or not ITEM_KINDS[entry.kind] then return end
      local id = slotItemId(widget)
      entry.value = id > 100 and tostring(id) or ""
      refreshItemView(row, entry, "slot")
    end
    box.itemId.onTextChange = function(_, text)
      if row._hotkeySync or not ITEM_KINDS[entry.kind] then return end
      entry.value = trim(text)
      refreshItemView(row, entry, "text")
    end
  end

  if row.func.setOption then row.func:setOption(FUNCTION_LABELS[entry.kind == "func" and entry.value or FUNCTION_ORDER[1]]) end
  row.func.onOptionChange = function(widget)
    local option = widget:getCurrentOption()
    for id, label in pairs(FUNCTION_LABELS) do if option and option.text == label then entry.value = id end end
  end

  row.script.onClick = function() editScript(entry) end
  row.remove.onClick = function()
    for index, candidate in ipairs(config.list) do
      if candidate == entry then table.remove(config.list, index) break end
    end
    if capturing == entry then capturing = nil end
    refreshRows()
  end
  showInputs(row, entry)
end

refreshRows = function()
  if not window then return end
  normalizeList()
  window.list:destroyChildren()
  rowWidgets = {}
  for _, entry in ipairs(config.list) do
    local row = UI.createWidget("CustomHotkeyRow", window.list)
    bindRow(row, entry)
    rowWidgets[#rowWidgets + 1] = {row = row, entry = entry}
  end
  updateSummary()
end

local function setEnabled(value)
  config.enabled = value == true
  if not config.enabled then capturing = nil end
  updateSummary()
end

local rootWidget = g_ui.getRootWidget()
if rootWidget then
  local previous = rootWidget:recursiveGetChildById("CustomHotkeysWindow")
  if previous then previous:destroy() end
  window = UI.createWindow("CustomHotkeysWindow", rootWidget)
  window:hide()
  window.add.onClick = function()
    newRow()
    refreshRows()
  end
  window.master.onClick = function() setEnabled(not config.enabled) end
  window.onVisibilityChange = function(_, visible)
    if not visible and capturing then finishCapture(nil) end
  end
  refreshRows()
end

ui.enabled:setOn(config.enabled)
ui.enabled.onClick = function() setEnabled(not config.enabled) end
ui.setup.onClick = function()
  if not window then return end
  refreshRows()
  window:show()
  window:raise()
  window:focus()
end

-- ---------------------------------------------------------------- entradas
-- Teclado. Mientras se captura, la tecla se queda como nueva tecla de la fila (Esc cancela).
onKeyDown(function(keys)
  if capturing then
    local canonical, base = canonicalKey(keys)
    if not base then return end -- esperar a la tecla que no es un modificador
    if canonical == "Escape" then finishCapture(nil) else finishCapture(canonical) end
    return
  end
  handleKey(keys)
end)

-- Raton y rueda sobre el juego, con el mismo gancho que Bug Map. Se desenvuelve el nuestro de una
-- carga anterior y se conserva lo que haya puesto otro modulo. Un boton que se usa no llega al juego.
do
  local root = modules and modules.game_interface and modules.game_interface.gameRootPanel
  if root then
    local state = root.rinoHotkeyHooks
    local previousPress, previousWheel = root.onMousePress, root.onMouseWheel
    if state and previousPress == state.press then previousPress = state.previousPress end
    if state and previousWheel == state.wheel then previousWheel = state.previousWheel end
    local hooks = {previousPress = previousPress, previousWheel = previousWheel}
    hooks.press = function(widget, mousePos, mouseButton)
      local key = mouseKey(mouseButton)
      if key and trigger(key) then return true end
      if previousPress then return previousPress(widget, mousePos, mouseButton) end
      return false
    end
    hooks.wheel = function(widget, mousePos, direction)
      local key = wheelKey(direction)
      if key and trigger(key) then return true end
      if previousWheel then return previousWheel(widget, mousePos, direction) end
      return false
    end
    root.rinoHotkeyHooks = hooks
    root.onMousePress = hooks.press
    root.onMouseWheel = hooks.wheel
  end
end

-- La ultima accion se ve en la ventana.
macro(250, function()
  ui.enabled:setOn(config.enabled)
  if window and window:isVisible() and lastResult then
    local result = lastResult
    local text = displayKey(result.key) .. " -> " .. result.text .. (result.ok and " (ok)" or (" (" .. tostring(result.reason or "fallo") .. ")"))
    window.last:setText("Ultima: " .. text)
    window.last:setColor(result.ok and "#9dd1ce" or "#ffb873")
  end
end)

CustomHotkeys = {
  isOn = function() return config.enabled == true end,
  setOn = function() setEnabled(true) end,
  setOff = function() setEnabled(false) end,
  show = function() if ui.setup and ui.setup.onClick then ui.setup.onClick() end end,
  getStatus = function() return {enabled = config.enabled, count = #config.list, active = activeCount(), last = lastResult} end,
}
