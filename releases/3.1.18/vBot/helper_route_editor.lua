-- Editor de rutas por lineas, con el color de cada accion del CaveBot.
-- Solo presentacion: el resultado es el mismo texto de la ruta de siempre y lo
-- interpreta la misma funcion de guardado (Config.parse). El modo "Texto" es el
-- editor de texto de antes, sin cambios.
local H = Helper
if not H or not H.valid() then return end
local R = {}
H.routeEditor = R

local COLOR_UNKNOWN = "#8aa0ad"
local COLOR_BLANK = "#5f7380"
local COLOR_CONFIG = "#a79bd6"
local SELECTED = "#50d7d433"
local NORMAL = "#00000000"
local HINT_LINES = "Clic en una linea para editarla. Enter pasa a la siguiente."
local HINT_BLOCK = "Bloque de codigo: se edita en el modo Texto. Aqui puedes moverlo, duplicarlo o borrarlo entero."
local HINT_TEXT = "Modo texto: pega o cambia muchas lineas de golpe."

-- ---------------------------------------------------------------- texto y lineas
-- Una entrada es una linea de la ruta. Un valor entre [[ y ]] (por ejemplo el codigo de
-- "function") ocupa varias lineas fisicas y es UNA sola entrada, con saltos de linea dentro.
local function opensBlock(line)
  local value = line:match("^%s*[%w_%-]+%s*:%s*(.*)$")
  return value ~= nil and value:sub(1, 2) == "[[" and not value:find("]]", 3, true)
end

function R.isBlock(entry)
  return type(entry) == "string" and entry:find("\n", 1, true) ~= nil
end

function R.split(text)
  local physical = {}
  text = tostring(text or ""):gsub("\r", "")
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do physical[#physical + 1] = line end
  local entries, i = {}, 1
  while i <= #physical do
    local line = physical[i]
    if opensBlock(line) then
      local block, j, closed = {line}, i + 1, false
      while j <= #physical do
        block[#block + 1] = physical[j]
        if physical[j]:match("%]%]%s*$") then closed = true; break end
        j = j + 1
      end
      -- Sin cierre: llega al final del texto, pero sin arrastrar las lineas en blanco finales.
      if not closed then
        while #block > 1 and block[#block]:match("^%s*$") do block[#block] = nil end
      end
      entries[#entries + 1] = table.concat(block, "\n")
      i = j + 1
    else
      entries[#entries + 1] = line
      i = i + 1
    end
  end
  while #entries > 0 and entries[#entries]:match("^%s*$") do entries[#entries] = nil end
  return entries
end

-- Las lineas en blanco no son parte de la ruta: no se guardan.
function R.join(lines)
  local out = {}
  for _, line in ipairs(lines) do
    if not line:match("^%s*$") then out[#out + 1] = line end
  end
  return table.concat(out, "\n")
end

-- Una ruta .cfg son lineas "accion:valor". Si el texto es JSON se usa el editor de texto.
function R.supports(text)
  local first = tostring(text or ""):match("^%s*(%S)")
  return first ~= "{" and first ~= "["
end

function R.actionOf(line)
  local action = tostring(line or ""):match("^%s*([%w_%-]+)%s*:")
  return action and action:lower() or nil
end

-- El mismo color que da el CaveBot a cada accion al registrarla.
function R.colorOf(line)
  if tostring(line or ""):match("^%s*$") then return COLOR_BLANK end
  local action = R.actionOf(line)
  local registry = CaveBot and CaveBot.Actions
  local entry = action and type(registry) == "table" and registry[action] or nil
  if entry and entry.color then return entry.color end
  -- "config:" y "extensions:" guardan ajustes de la ruta; no son waypoints.
  return (action == "config" or action == "extensions") and COLOR_CONFIG or COLOR_UNKNOWN
end

function R.insertAfter(lines, index, text)
  local at = (type(index) == "number" and index >= 1 and index <= #lines) and index + 1 or #lines + 1
  table.insert(lines, at, text or "")
  return at
end

function R.duplicate(lines, index)
  if not lines[index] then return nil end
  table.insert(lines, index + 1, lines[index])
  return index + 1
end

-- Devuelve la linea que queda seleccionada (0 si no queda ninguna).
function R.remove(lines, index)
  if not lines[index] then return nil end
  table.remove(lines, index)
  return #lines == 0 and 0 or math.min(index, #lines)
end

function R.swap(lines, index, other)
  if not lines[index] or not lines[other] then return nil end
  lines[index], lines[other] = lines[other], lines[index]
  return other
end

-- ---------------------------------------------------------------- descriptores del skin
-- Los controles nuevos del dialogo se pintan igual que el resto de botones y campos.
local function registerStyle()
  local A = HelperAppearance
  local styles = A and A.metadata and A.metadata.styles
  local dialog = type(styles) == "table" and styles.HelperTextDialog
  if type(dialog) ~= "table" then return false end
  dialog.children = dialog.children or {}
  for _, child in ipairs(dialog.children) do
    if child.id == "linesPanel" then return true end
  end
  local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = copy(v) end
    return result
  end
  local function node(kind, id, children)
    local base = styles[kind]
    if type(base) ~= "table" then return nil end
    local item = copy(base)
    item.style, item.type, item.id = kind, kind, id
    item.children = children or {}
    return item
  end
  local inner = {}
  for _, spec in ipairs({
    {"HelperThemeList", "list"}, {"HelperThemeInput", "lineEdit"},
    {"HelperThemeButton", "insert"}, {"HelperThemeButton", "duplicate"},
    {"HelperThemeButton", "up"}, {"HelperThemeButton", "down"}, {"HelperThemeButton", "remove"},
  }) do
    inner[#inner + 1] = node(spec[1], spec[2])
  end
  local panel = {style = "Panel", type = "Panel", props = {}, states = {}, id = "linesPanel", children = inner}
  for _, item in ipairs({
    node("HelperThemePower", "modeLines"), node("HelperThemePower", "modeText"),
    node("HelperLabel", "routeHint"), panel,
  }) do
    dialog.children[#dialog.children + 1] = item
  end
  return true
end
pcall(registerStyle)

-- ---------------------------------------------------------------- dialogo
local create = (H.originals and H.originals.createWidget) or UI.createWidget

local function paintRow(S, i)
  local row, line = S.rows[i], S.lines[i]
  if not row or not line then return end
  row.number:setText(i .. ".")
  local shown = line
  if R.isBlock(line) then
    local _, breaks = line:gsub("\n", "\n")
    shown = line:match("^[^\n]*") .. "  ... (" .. (breaks + 1) .. " lineas)"
  elseif line:match("^%s*$") then
    shown = "(linea vacia)"
  end
  row:setText(shown)
  row:setColor(R.colorOf(line))
  row:setBackgroundColor(i == S.sel and SELECTED or NORMAL)
end

-- Cada fila es solo una vista de lines[i]: se ajusta el numero de filas y se repintan.
local function sync(S)
  S.building = true
  local list = S.panel.list
  while #S.rows < #S.lines do S.rows[#S.rows + 1] = create("HelperRouteLine", list) end
  while #S.rows > #S.lines do
    S.rows[#S.rows]:destroy()
    S.rows[#S.rows] = nil
  end
  for i = 1, #S.rows do paintRow(S, i) end
  S.building = false
end

local function choose(S, index, focusEdit)
  if type(index) ~= "number" or index < 1 or index > #S.lines then index = 0 end
  local old = S.sel
  S.sel = index
  if S.rows[old] then S.rows[old]:setBackgroundColor(NORMAL) end
  -- Un bloque de varias lineas no cabe en la caja: se edita en el modo Texto.
  local entry = S.lines[index]
  local block = R.isBlock(entry)
  S.loading = true
  S.panel.lineEdit:setText(block and "(bloque de codigo: editalo en el modo Texto)" or entry or "")
  S.loading = false
  S.panel.lineEdit:setEnabled(index > 0 and not block)
  if S.hint then S.hint:setText(block and HINT_BLOCK or HINT_LINES) end
  if S.rows[index] then
    S.rows[index]:setBackgroundColor(SELECTED)
    pcall(function() S.panel.list:ensureChildVisible(S.rows[index]) end)
  end
  if focusEdit and index > 0 and not block then S.panel.lineEdit:focus() end
end

local function showLines(w, S)
  S.mode = "lines"
  w.editor:setVisible(false)
  w.editorScroll:setVisible(false)
  w.linesPanel:setVisible(true)
  w.modeLines:setOn(true)
  w.modeText:setOn(false)
  S.hint = w.routeHint
  S.panel.list:destroyChildren()
  S.rows, S.sel = {}, 0
  sync(S)
  choose(S, #S.lines > 0 and 1 or 0)
end

local function showText(w, S)
  S.mode = "text"
  w.linesPanel:setVisible(false)
  w.editor:setVisible(true)
  w.editorScroll:setVisible(true)
  w.modeLines:setOn(false)
  w.modeText:setOn(true)
  w.routeHint:setText(HINT_TEXT)
  w.editor:focus()
end

local function bind(w)
  if w.routeBound then return true end
  local panel = w.linesPanel
  if not panel or not w.modeLines or not w.modeText or not w.routeHint then return false end
  w.routeBound = true
  local function state()
    local S = w.routeState
    if S and S.mode == "lines" then return S end
  end
  local previous = panel.list.onChildFocusChange
  panel.list.onChildFocusChange = function(list, focused, ...)
    if type(previous) == "function" then previous(list, focused, ...)
    elseif type(previous) == "table" then for _, fn in ipairs(previous) do fn(list, focused, ...) end end
    local S = state()
    if not S or S.building or not focused then return end
    local index = list:getChildIndex(focused)
    if index and index ~= S.sel then choose(S, index, true) end
  end
  panel.lineEdit.onTextChange = function(_, text)
    local S = state()
    if not S or S.loading or S.sel == 0 or R.isBlock(S.lines[S.sel]) then return end
    S.lines[S.sel] = tostring(text or "")
    paintRow(S, S.sel)
  end
  panel.lineEdit.onEnter = function()
    local S = state()
    if S and S.sel > 0 and S.sel < #S.lines then choose(S, S.sel + 1, true) end
    return true
  end
  panel.insert.onClick = function()
    local S = state(); if not S then return end
    local at = R.insertAfter(S.lines, S.sel, "")
    sync(S); choose(S, at, true)
  end
  panel.duplicate.onClick = function()
    local S = state(); if not S then return end
    local at = R.duplicate(S.lines, S.sel)
    if at then sync(S); choose(S, at, true) end
  end
  panel.up.onClick = function()
    local S = state(); if not S or S.sel < 2 then return end
    local at = R.swap(S.lines, S.sel, S.sel - 1)
    if at then S.sel = at; sync(S); choose(S, at, true) end
  end
  panel.down.onClick = function()
    local S = state(); if not S or S.sel < 1 or S.sel >= #S.lines then return end
    local at = R.swap(S.lines, S.sel, S.sel + 1)
    if at then S.sel = at; sync(S); choose(S, at, true) end
  end
  panel.remove.onClick = function()
    local S = state(); if not S then return end
    local at = R.remove(S.lines, S.sel)
    if at then S.sel = 0; sync(S); choose(S, at, true) end
  end
  w.modeLines.onClick = function()
    local S = w.routeState
    if not S or S.mode == "lines" then return end
    S.lines = R.split(w.editor:getText())
    showLines(w, S)
  end
  w.modeText.onClick = function()
    local S = w.routeState
    if not S or S.mode == "text" then return end
    w.editor:setText(R.join(S.lines))
    showText(w, S)
  end
  panel.insert:setTooltip("Agrega una linea vacia debajo de la seleccionada.")
  panel.duplicate:setTooltip("Copia la linea seleccionada justo debajo.")
  panel.up:setTooltip("Sube la linea seleccionada.")
  panel.down:setTooltip("Baja la linea seleccionada.")
  panel.remove:setTooltip("Borra la linea seleccionada.")
  w.modeLines:setTooltip("Una linea por waypoint, con el color de su accion. Se edita en la caja de abajo.")
  w.modeText:setTooltip("Editor de texto completo: para pegar o cambiar muchas lineas de golpe.")
  return true
end

-- Se llama cada vez que se abre el dialogo. contents=nil -> editor de texto de siempre.
-- Devuelve true si queda activo el modo por lineas.
function R.attach(w, contents)
  if not bind(w) then return false end
  local wanted = contents ~= nil and R.supports(contents)
  w.modeLines:setVisible(wanted)
  w.modeText:setVisible(wanted)
  w.routeHint:setVisible(wanted)
  if not wanted then
    w.routeState = nil
    w.linesPanel:setVisible(false)
    w.editor:setVisible(true)
    w.editorScroll:setVisible(true)
    return false
  end
  local S = {mode = "lines", lines = R.split(contents), rows = {}, sel = 0, panel = w.linesPanel}
  w.routeState = S
  showLines(w, S)
  return true
end

-- Texto final si el modo por lineas esta activo; nil si manda el editor de texto.
function R.text(w)
  local S = w.routeState
  if S and S.mode == "lines" then return R.join(S.lines) end
  return nil
end

-- Donde poner el foco al abrir.
function R.focusTarget(w)
  local S = w.routeState
  if S and S.mode == "lines" then return w.linesPanel.lineEdit end
  return w.editor
end
