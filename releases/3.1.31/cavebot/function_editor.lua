-- Editor for the Lua of CaveBot "function" waypoints: templates by category, the list of
-- available functions, a syntax/label check, a dry run and personal templates
-- (storage.caveFunctionTemplates, per profile). Visual rules keep their own editor
-- (cavebot/route_tools.lua); "Regla visual" switches to it.
importStyle('/cavebot/function_editor.otui')
CaveBot.FunctionEditor = {}
local E = CaveBot.FunctionEditor
local R = CaveBot.FunctionRuntime

local function trim(value) return tostring(value or ""):match("^%s*(.-)%s*$") end

-- Functions and variables available in a function waypoint: {shown name, inserted text, help}.
E.functions = {
  {"return true", "return true", "Termina la funcion y sigue con el siguiente waypoint."},
  {'return "retry"', 'return "retry"', "Repite esta funcion en el siguiente ciclo. Llama antes a delay(ms) para esperar."},
  {"gotoLabel(nombre)", 'gotoLabel("refill")', 'Salta a un label de esta ruta. Usalo con return: return gotoLabel("refill").'},
  {"gotoWaypoint(n)", "gotoWaypoint(1)", "Sigue la ruta en el waypoint numero n. Usalo con return."},
  {"delay(ms)", "delay(1000)", "Espera esos milisegundos antes de la siguiente accion del CaveBot."},
  {"waitUntil(funcion, ms, cada)", "waitUntil(function() return monstersAround(7) == 0 end, 30000, 500)",
    "Espera en este waypoint hasta que la funcion devuelva true (devuelve true) o pase el tiempo (devuelve false). Usalo con return."},
  {"waitStamina(min, ms)", "waitStamina(2520, 60000)", "Espera aqui hasta tener esos minutos de stamina (2520 = 42 h)."},
  {"stepDirection(dir, intentos, ms)", 'stepDirection("sur", 30, 200)',
    "Da un paso: norte, sur, este, oeste, noreste, sureste, suroeste o noroeste."},
  {"itemCount(id)", "itemCount(268)", "Cantidad de un objeto; cuenta tambien mochilas cerradas si el cliente puede."},
  {"goldCount()", "goldCount()", "Oro en monedas: gold, platinum (x100) y crystal (x10000)."},
  {"freecap()", "freecap()", "Capacidad libre."},
  {"hppercent()", "hppercent()", "Vida en porcentaje."},
  {"manapercent()", "manapercent()", "Mana en porcentaje."},
  {"stamina()", "stamina()", "Stamina en minutos (2520 = 42 h)."},
  {"lvl()", "lvl()", "Nivel del personaje."},
  {"isInPz()", "isInPz()", "true si estas en zona de proteccion."},
  {"pzLocked()", "pzLocked()", "true si tienes el PZ bloqueado (despues de atacar jugadores)."},
  {"hasSkull()", "hasSkull()", "true si tienes skull blanca, roja, negra o naranja."},
  {"monstersAround(rango, nombres)", "monstersAround(7)",
    'Monstruos vivos a ese rango en tu piso. Nombres opcionales: monstersAround(7, "Dragon, Dragon Lord").'},
  {"playersAround(rango)", "playersAround(8)",
    "Otros jugadores a ese rango, sin party, amigos ni guild. playersAround(8, true) los cuenta a todos."},
  {"huntMinutes()", "huntMinutes()", "Minutos desde que encendiste la ruta."},
  {"laps()", "laps()", "Vueltas completas de la ruta desde que la encendiste."},
  {"setBot(bot, modo)", 'setBot("target", "off")',
    'Enciende o apaga un bot: "target", "attack", "heal" o "cave", con "on", "off" o "toggle".'},
  {"setHealBot(modo)", 'setHealBot("on")', 'Enciende o apaga el HealBot: "on", "off" o "toggle".'},
  {"say(texto)", 'say("hi")', "Dice el texto en el chat."},
  {"reopenBps(bp)", 'return reopenBps("todas")',
    'Cierra y vuelve a abrir BPs con el Container Manager, desde la de arriba: "todas", el nombre de una BP de su lista ("Ammo") o su ID (2872). Espera a que se abran. Usalo con return.'},
  {"SupremeCube.run(destino, retries)", 'return SupremeCube.run("Cities, Thais", retries)',
    'Viaja con Supreme Cube (31633), espera su cooldown y confirma la llegada. Tambien disponible como waypoint Supreme Cube.'},
  {"alarm(texto)", 'alarm("Jugador cerca")', "Suena la alarma, parpadea la ventana y escribe el aviso en la consola."},
  {"log(texto)", 'log("paso por aqui")', "Escribe una linea en la consola del bot (Acciones). Util para revisar tu funcion."},
  {"prev", "prev", "Resultado de la accion anterior (true o false)."},
  {"retries", "retries", 'Veces que esta funcion se repitio con "retry" (empieza en 0).'},
  {"storage", "storage.miValor", "Guarda valores entre llamadas (por perfil)."},
  {"CaveBot.setOff()", "CaveBot.setOff()", "Apaga el CaveBot."},
  {"TargetBot.enableLuring()", "TargetBot.enableLuring()", "Activa el luring del TargetBot (disableLuring lo quita)."},
}

E.categories = {"Supplies y refill", "Seguridad", "Tiempo y stamina", "Monstruos y lure", "Bots", "Movimiento",
  "Equipo", "Viajes", "Utilidades"}

-- Templates: {category, title, code}. ASCII only, comments explain what to change.
E.templates = {
  {"Supplies y refill", "Ir a refill si faltan pociones", [[
-- Si quedan menos pociones de las indicadas, ir al label de refill.
local pocion = 268   -- id de la pocion (268 = mana potion)
local minimo = 200
if itemCount(pocion) < minimo then
  return gotoLabel("refill")
end
return true]]},
  {"Supplies y refill", "Ir a refill si falta capacidad", [[
-- Si la capacidad libre baja de este valor, ir al label de refill.
if freecap() < 100 then
  return gotoLabel("refill")
end
return true]]},
  {"Supplies y refill", "Ir a refill si faltan supplies configurados", [[
-- Usa los minimos configurados en Supplies del Helper.
if hasSupplies() ~= true then
  return gotoLabel("refill")
end
return true]]},
  {"Supplies y refill", "Depositar si llevo mucho oro", [[
-- Con mas oro que este (gold, platinum y crystal), ir al label del deposito.
if goldCount() >= 50000 then
  return gotoLabel("deposito")
end
return true]]},
  {"Supplies y refill", "Comprar pociones a un NPC", [[
-- Camina hasta el NPC, abre el trade y compra. Cambia el nombre, el id y la cantidad.
local npcName = "Eryn"
local pocion = 268
local cantidad = 100
local npc = getCreatureByName(npcName)
if not npc or retries > 10 then
  return false
end
local pos, npcPos = player:getPosition(), npc:getPosition()
if math.max(math.abs(pos.x - npcPos.x), math.abs(pos.y - npcPos.y)) > 3 then
  autoWalk(npcPos, {precision = 3})
  delay(300)
  return "retry"
end
if not NPC.isTrading() then
  NPC.say("hi")
  NPC.say("trade")
  delay(300)
  return "retry"
end
NPC.buy(pocion, cantidad)
delay(1000)
return true]]},
  {"Supplies y refill", "Cerrar y reabrir BPs (despues de comprar)", [[
-- Ponlo despues de buy supplies: cierra la BP y el Container Manager la vuelve a abrir
-- desde la de arriba, donde quedan las flechas nuevas. "todas" = todas las ventanas;
-- o el nombre de una BP de la lista del Container Manager ("Ammo") o su ID (2872).
return reopenBps("Ammo")]]},
  {"Supplies y refill", "Cerrar contenedores de loot", [[
CaveBot.CloseAllLootContainers()
delay(3000)
return true]]},
  {"Seguridad", "Esperar a perder el PZ", [[
-- Espera aqui mientras el PZ siga bloqueado (como mucho 25 intentos de 8 s).
if retries > 25 or not pzLocked() then
  return true
end
delay(8000)
return "retry"]]},
  {"Seguridad", "Salir de la caza si hay un jugador cerca", [[
-- Con un jugador (sin party, amigos ni guild) a 8 casillas, suena la alarma y va a "salida".
if playersAround(8) > 0 then
  alarm("Jugador cerca de la caza")
  return gotoLabel("salida")
end
return true]]},
  {"Seguridad", "Logout si hay un jugador cerca", [[
-- Sale del juego si hay un jugador cerca y el PZ no esta bloqueado.
if playersAround(8) > 0 and not pzLocked() then
  g_game.safeLogout()
  delay(1000)
  return "retry"
end
return true]]},
  {"Seguridad", "Parar el bot si la stamina esta baja", [[
-- Con menos de 15 horas de stamina (900 min), avisa y apaga el CaveBot.
if stamina() < 900 then
  alarm("Stamina baja: CaveBot apagado")
  CaveBot.setOff()
  return false
end
return true]]},
  {"Seguridad", "Avisar si tengo skull", [[
if hasSkull() then
  alarm("Tienes skull")
end
return true]]},
  {"Tiempo y stamina", "Esperar stamina", [[
-- Espera aqui hasta tener esta stamina (minutos; 2520 = 42 h). Comprueba cada minuto.
return waitStamina(2520, 60000)]]},
  {"Tiempo y stamina", "Cazar un tiempo y volver", [[
-- Despues de estos minutos desde que encendiste la ruta, ir al label "volver".
if huntMinutes() >= 120 then
  return gotoLabel("volver")
end
return true]]},
  {"Tiempo y stamina", "Cada N vueltas ir a un label", [[
-- Cada 3 vueltas completas de la ruta, ir al label "refill".
local cada = 3
if laps() > 0 and laps() % cada == 0 then
  return gotoLabel("refill")
end
return true]]},
  {"Tiempo y stamina", "Salir a una hora", [[
-- A partir de esta hora del reloj del PC, ir al label "salida".
local hora = tonumber(os.date("%H"))
if hora >= 23 then
  return gotoLabel("salida")
end
return true]]},
  {"Monstruos y lure", "Esperar a que no queden monstruos", [[
-- Espera hasta 30 s a que no haya monstruos a 7 casillas.
return waitUntil(function() return monstersAround(7) == 0 end, 30000, 500)]]},
  {"Monstruos y lure", "Esperar a juntar monstruos (lure)", [[
-- Espera hasta 15 s a tener al menos 5 monstruos a 4 casillas.
return waitUntil(function() return monstersAround(4) >= 5 end, 15000, 300)]]},
  {"Monstruos y lure", "Escapar si hay demasiados", [[
-- Con 8 monstruos o mas a 6 casillas, ir al label "escape".
if monstersAround(6) >= 8 then
  return gotoLabel("escape")
end
return true]]},
  {"Monstruos y lure", "Contar solo ciertos monstruos", [[
-- Cuenta solo los monstruos con estos nombres.
if monstersAround(7, "Dragon, Dragon Lord") >= 2 then
  return gotoLabel("dragones")
end
return true]]},
  {"Bots", "Apagar TargetBot", [[return setBot("target", "off")]]},
  {"Bots", "Encender TargetBot", [[return setBot("target", "on")]]},
  {"Bots", "Apagar AttackBot", [[return setBot("attack", "off")]]},
  {"Bots", "Encender AttackBot", [[return setBot("attack", "on")]]},
  {"Bots", "Apagar HealBot", [[return setHealBot("off")]]},
  {"Bots", "Encender HealBot", [[return setHealBot("on")]]},
  {"Bots", "Activar el luring", [[
TargetBot.enableLuring()
return true]]},
  {"Bots", "Quitar el luring", [[
TargetBot.disableLuring()
return true]]},
  {"Movimiento", "Dar un paso", [[
-- Direcciones: norte, sur, este, oeste, noreste, sureste, suroeste, noroeste.
return stepDirection("sur", 30, 200)]]},
  {"Movimiento", "Ir al waypoint N", [[
-- La ruta sigue en el waypoint numero 1.
return gotoWaypoint(1)]]},
  {"Equipo", "Esperar a un companero", [[
-- Espera hasta 60 s a que este jugador este en pantalla.
local nombre = "Nombre del amigo"
return waitUntil(function() return getCreatureByName(nombre) ~= nil end, 60000, 1000)]]},
  {"Utilidades", "Decir algo varias veces", [[
-- Dice el texto 5 veces con una pausa creciente.
if retries >= 5 then
  return true
end
say("hola")
delay(100 + retries * 100)
return "retry"]]},
  {"Utilidades", "Escribir en la consola", [[
log("Paso por este waypoint con " .. freecap() .. " de capacidad")
return true]]},
  {"Utilidades", "Sonar una alarma", [[
alarm("Llegue a este punto de la ruta")
return true]]},
  {"Utilidades", "Logout", [[
g_game.safeLogout()
delay(1000)
return "retry"]]},
  {"Utilidades", "Funcion vacia", [[
-- Variables: retries (repeticiones), prev (resultado anterior), storage (tus datos).
-- Devuelve true (seguir), false (fallo, sigue) o "retry" (repetir).
return true]]},
}

-- Personal templates ------------------------------------------------------------------
E.templates[#E.templates+1]={"Viajes","Viajar con Supreme Cube",[[
-- Mas sencillo: agrega un waypoint Supreme Cube y elige el destino en su lista.
-- En Lua se usa Categoria, Destino: Cities, Bosses, Trainer o House.
-- Respeta el cooldown y no sigue la ruta hasta confirmar el viaje.
return SupremeCube.run("Cities, Thais", retries)]]}

local MAX_MINE = 60
local function mine()
  local list = type(storage) == "table" and storage.caveFunctionTemplates
  if type(list) ~= "table" then return {} end
  local valid = {}
  for _, entry in ipairs(list) do
    if type(entry) == "table" and type(entry.name) == "string" and type(entry.code) == "string" then
      valid[#valid + 1] = entry
    end
  end
  return valid
end
function E.saveMine(name, code)
  name = trim(name)
  if name == "" or trim(code) == "" then return false end
  local list = mine()
  for _, entry in ipairs(list) do
    if entry.name:lower() == name:lower() then entry.code = code; storage.caveFunctionTemplates = list; return true end
  end
  if #list >= MAX_MINE then return false, "Ya tienes " .. MAX_MINE .. " plantillas; borra alguna." end
  list[#list + 1] = {name = name, code = code}
  storage.caveFunctionTemplates = list
  return true
end
function E.deleteMine(name)
  local list = mine()
  for i, entry in ipairs(list) do
    if entry.name == name then table.remove(list, i); storage.caveFunctionTemplates = list; return true end
  end
  return false
end

-- The list shown for a category and a search text: {kind, title, text, help, header}.
function E.entries(category, search)
  search = trim(search):lower()
  local out = {}
  local function matches(...)
    if search == "" then return true end
    for _, value in ipairs({...}) do
      if tostring(value or ""):lower():find(search, 1, true) then return true end
    end
    return false
  end
  local function header(text) out[#out + 1] = {header = true, title = text} end
  local function templates(name)
    local found = {}
    for _, t in ipairs(E.templates) do
      if t[1] == name and matches(t[2], t[3]) then found[#found + 1] = {kind = "template", title = t[2], text = t[3]} end
    end
    if #found > 0 then
      if category == "all" then header(name) end
      for _, entry in ipairs(found) do out[#out + 1] = entry end
    end
  end
  local function personal()
    local found = {}
    for _, t in ipairs(mine()) do
      if matches(t.name, t.code) then found[#found + 1] = {kind = "mine", title = t.name, text = t.code} end
    end
    if #found > 0 then
      if category == "all" then header("Mis plantillas") end
      for _, entry in ipairs(found) do out[#out + 1] = entry end
    end
  end
  local function functions()
    local found = {}
    for _, f in ipairs(E.functions) do
      if matches(f[1], f[3]) then found[#found + 1] = {kind = "function", title = f[1], text = f[2], help = f[3]} end
    end
    if #found > 0 then
      if category == "all" then header("Funciones disponibles") end
      for _, entry in ipairs(found) do out[#out + 1] = entry end
    end
  end
  if category == "all" or category == "mine" then personal() end
  for _, name in ipairs(E.categories) do
    if category == "all" or category == name then templates(name) end
  end
  if category == "all" or category == "functions" then functions() end
  return out
end

-- Character index of the start of a line, for moving the cursor to an error.
function E.lineStart(text, line)
  line = tonumber(line) or 1
  local index, current = 0, 1
  while current < line do
    local nl = text:find("\n", index + 1, true)
    if not nl then break end
    index, current = nl, current + 1
  end
  return index
end

-- Skin: the Helper paints windows from descriptors; these two are new styles.
if CaveBot.Editor.skinWindow then
  pcall(CaveBot.Editor.skinWindow, "CaveBotFunctionWindow", {
    {"HelperThemeInput", "search"}, {"HelperThemeCombo", "category"},
    {"HelperThemeScroll", "itemList"}, {"VerticalScrollBar", "itemScroll"},
    {"HelperThemeMultiline", "code"}, {"VerticalScrollBar", "codeScroll"},
    {"HelperThemeLabel", "status"}, {"HelperThemeLabel", "help"},
    {"HelperThemeButton", "check"}, {"HelperThemeButton", "dryRun"}, {"HelperThemeButton", "saveTemplate"},
    {"HelperThemeButton", "deleteTemplate"}, {"HelperThemeButton", "visual"},
    {"HelperThemeButton", "cancel"}, {"HelperThemeButton", "ok"}})
end
pcall(function()
  local styles = HelperAppearance and HelperAppearance.metadata and HelperAppearance.metadata.styles
  if type(styles) ~= "table" or styles.CaveBotFunctionItem then return end
  styles.CaveBotFunctionItem = {style = "CaveBotFunctionItem", type = "HelperThemeLabel", children = {},
    props = {["background-color"] = "alpha", ["color"] = "#e4edf3"},
    states = {["$disabled"] = {["color"] = "#dfdfdf88"}, ["$focus"] = {["background-color"] = "#18434a", ["color"] = "#dcffff"}}}
end)

local OK_COLOR, WARN_COLOR, INFO_COLOR = "#8fe39a", "#ffcd80", "#a9d8d4"
local KIND_COLOR = {template = "#e4edf3", mine = "#ffd84d", ["function"] = "#8fd3ff"}

function CaveBot.Editor.editFunction(value, callback)
  local window = UI.createWindow("CaveBotFunctionWindow")
  local code = window.code
  local state = {pristine = tostring(value or ""), selected = nil, force = false, confirm = nil, lastLoaded = nil}
  code:setText(state.pristine)

  local function status(text, color)
    window.status:setText(text or "")
    window.status:setColor(color or INFO_COLOR)
  end
  local function help(text) window.help:setText(text or "") end

  window.category:addOption("Todo", "all")
  for _, name in ipairs(E.categories) do window.category:addOption("Plantillas: " .. name, name) end
  window.category:addOption("Mis plantillas", "mine")
  window.category:addOption("Funciones disponibles", "functions")
  window.category:setCurrentOptionByData("all")

  local function insertAtCursor(text)
    if pcall(function() code:paste(text) end) then return end
    local current = code:getText()
    local position = #current
    pcall(function() position = math.min(#current, tonumber(code:getCursorPos()) or #current) end)
    code:setText(current:sub(1, position) .. text .. current:sub(position + 1))
    pcall(function() code:setCursorPos(position + #text) end)
  end

  local function loadEntry(entry)
    if entry.kind == "function" then
      insertAtCursor(entry.text)
      status("Insertado: " .. entry.text, INFO_COLOR)
      return
    end
    local current = code:getText()
    local untouched = trim(current) == "" or current == state.pristine and trim(state.pristine) == "return true" or
      current == state.lastLoaded
    if not untouched and state.confirm ~= entry then
      state.confirm = entry
      status("Tu codigo se reemplazara por \"" .. entry.title .. "\". Haz doble clic otra vez para confirmar.", WARN_COLOR)
      return
    end
    state.confirm = nil
    code:setText(entry.text)
    state.lastLoaded = entry.text
    status("Plantilla cargada: " .. entry.title .. ". Cambia los valores marcados en los comentarios.", INFO_COLOR)
  end

  local function select(entry)
    state.selected = entry
    if entry.kind == "function" then
      help(entry.title .. ": " .. tostring(entry.help) .. "  (doble clic para insertarla)")
    else
      local first = entry.text:match("^%-%-%s*([^\n]+)")
      help((entry.kind == "mine" and "Tu plantilla: " or "Plantilla: ") .. entry.title ..
        (first and (". " .. first) or "") .. "  (doble clic para cargarla)")
    end
  end

  local function refresh()
    window.itemList:destroyChildren()
    local option = window.category:getCurrentOption()
    local entries = E.entries(option and option.data or "all", window.search:getText())
    for _, entry in ipairs(entries) do
      local item = UI.createWidget("CaveBotFunctionItem", window.itemList)
      if entry.header then
        item:setText(entry.title)
        item:setColor("#a9bbc6")
        item:setFocusable(false)
      else
        item:setText("  " .. entry.title)
        item:setColor(KIND_COLOR[entry.kind] or "#e4edf3")
        item:setTooltip(entry.help or entry.text)
        item.onClick = function() select(entry) end
        item.onDoubleClick = function() select(entry); loadEntry(entry) end
      end
    end
    if #entries == 0 then help("Nada coincide con la busqueda.") end
  end

  local function check()
    local result = R.check(code:getText())
    if result.error then
      status(result.error, WARN_COLOR)
      if result.line then pcall(function() code:setCursorPos(E.lineStart(code:getText(), result.line)) end) end
      return result
    end
    local notes = {}
    for _, name in ipairs(result.missingLabels) do notes[#notes + 1] = 'falta el label "' .. name .. '" en esta ruta' end
    if result.noReturn then notes[#notes + 1] = "no devuelve nada; termina con return true" end
    if #notes > 0 then
      status("Sintaxis correcta, pero " .. table.concat(notes, "; ") .. ".", WARN_COLOR)
    else
      status("Sintaxis correcta.", OK_COLOR)
    end
    return result
  end

  window.category.onOptionChange = refresh
  window.search.onTextChange = refresh
  code.onTextChange = function() state.force = false end
  window.check.onClick = function() check() end
  window.dryRun.onClick = function()
    local result = R.dryRun(code:getText())
    if not result.ok then
      status("Error al probar: " .. tostring(result.error), WARN_COLOR)
      return
    end
    local actions = result.actions or {}
    local shown = {}
    for i = 1, math.min(#actions, 4) do shown[i] = actions[i] end
    local did = #actions == 0 and "Sin acciones." or ("Haria: " .. table.concat(shown, "; ") ..
      (#actions > 4 and (" y " .. (#actions - 4) .. " mas") or "") .. ".")
    status("Resultado " .. R.describeResult(result.result) .. ". " .. did, OK_COLOR)
  end
  window.saveTemplate.onClick = function()
    local text = code:getText()
    if trim(text) == "" then status("Escribe algo antes de guardarlo como plantilla.", WARN_COLOR); return end
    local suggested = text:match("^%s*%-%-%s*([^\n]+)") or ("Mi plantilla " .. (#mine() + 1))
    UI.EditorWindow(suggested:sub(1, 40), {title = "Nombre de la plantilla", multiline = false}, function(name)
      local ok, message = E.saveMine(name, text)
      if not ok then return false end
      if window and not (window.isDestroyed and window:isDestroyed()) then
        window.category:setCurrentOptionByData("mine")
        refresh()
        status("Plantilla guardada en Mis plantillas: " .. trim(name), OK_COLOR)
      end
    end)
  end
  window.deleteTemplate.onClick = function()
    local entry = state.selected
    if not entry or entry.kind ~= "mine" then
      status("Selecciona una de tus plantillas (Mis plantillas) para borrarla.", WARN_COLOR)
      return
    end
    E.deleteMine(entry.title)
    state.selected = nil
    refresh()
    status("Plantilla borrada: " .. entry.title, INFO_COLOR)
  end
  window.visual.onClick = function()
    local text = code:getText()
    window:destroy()
    CaveBot.Editor.editRule(text, callback)
  end
  window.cancel.onClick = function() window:destroy() end
  window.onEscape = window.cancel.onClick
  if window.closeButton then window.closeButton.onClick = window.cancel.onClick end
  window.ok.onClick = function()
    local result = R.check(code:getText())
    if result.error and not state.force then
      state.force = true
      status(result.error .. "  Pulsa Guardar otra vez para guardarla igual.", WARN_COLOR)
      return
    end
    callback(code:getText())
    window:destroy()
  end

  refresh()
  help("Elige una plantilla o una funcion a la izquierda: un clic la explica, doble clic la carga o la inserta.")
  status(trim(state.pristine) == "" and "Escribe tu funcion o carga una plantilla." or "", INFO_COLOR)
  pcall(function() code:focus() end)
  return window
end
