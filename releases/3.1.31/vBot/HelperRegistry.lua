-- Helper's UI inventory. Capture existing controls, never load a second engine.
local root = g_ui.getRootWidget()
local previous = root._sabuezoHelperRuntime
if previous and previous.dispose then pcall(previous.dispose) end

Helper = {modules = {}, order = {}, widgets = {}, windows = {}, source = nil,
  root = root, disposed = false, building = true, originals = {}, wrappers = {}, panelParents = {}, touched = {}}
local H = Helper
H.appearanceManager=HelperAppearance
if H.appearanceManager then H.appearanceManager.owner=H end
root._sabuezoHelperRuntime = H

H.sections = {"Inicio", "Combate", "Curacion", "Proteccion", "CaveBot", "Navi", "Inventario", "Herramientas", "Scripts", "Ajustes"}
H.sectionLabels = {Curacion="Curacion", Proteccion="Proteccion", Scripts="Scripts"}
local definitions = {
  {"attackbot", "AttackBot", "Combate", "Rotaciones, vocaciones, hechizos, runas, catalogo y seguridad", "AttackBot"},
  {"targetbot", "TargetBot", "Combate", "Criaturas, prioridades, distancias, movimiento, antitrap y loot", "TargetBot"},
  {"combo_plus", "Combo", "Combate", "Combos con el lider, runas, Magic Wall y tiempos"},
  -- Its own entry since change 212 (vBot/follow_panel.lua); the engine stays in combo_plus.lua.
  {"follow_panel", "Follow", "Combate", "Seguir a un jugador: leader, separacion, viajes, compras y CaveBot"},
  {"pushmax", "Push Max", "Combate", "Empuje, hotkeys, colas y condiciones"},
  {"keepwall", "Keep Wall", "Combate", "Runas, paredes y tiempos", "KeepWall"},
  {"firebomb", "Fire Bomb", "Combate", "Runa y posicion", "FireBomb"},
  {"holdtarget", "Hold Target", "Combate", "Mantener el objetivo actual", "HoldTarget"},
  {"healbot", "HealBot", "Curacion", "Hechizos, items, perfiles y condiciones", "HealBot"},
  {"friend_healer", "Friend Healer", "Curacion", "Grupos, vocaciones, nombres y umbrales", "FriendHealer"},
  {"conditions", "Condiciones", "Curacion", "Estados, recuperacion, prioridades y comida (comer/conjurar)"},
  {"manatrainer", "Mana Trainer", "Curacion", "Entrenamiento de mana y hechizos"},
  {"zautobuff", "Auto Buff", "Curacion", "Lista de hechizos y cooldowns", "AutoBuff"},
  {"inmortal", "Inmortal", "Proteccion", "SSA, Might Ring, Energy Ring y proteccion", "Inmortal"},
  {"equipper", "Equipper", "Proteccion", "Equipo, condiciones, bosses y seguridad PvP"},
  {"equip", "Equipo automatico", "Proteccion", "Equipo por salud y condiciones"},
  {"cavebot", "CaveBot", "CaveBot", "Rutas, grabador, editor, explorer, acciones, NPC y configuracion", "CaveBot"},
  {"cave_target_settings", "Cave y Target: ajustes", "CaveBot", "Seguimiento, muerte, frags, HUD y seguridad"},
  {"supplies", "Supplies", "CaveBot", "Perfiles, suministros, capacidad y stamina"},
  {"depositer_config", "Depositos", "CaveBot", "Aliases, destinos, items y cantidades"},
  {"cavebot_control_panel", "Controles de ruta", "CaveBot", "Volver y parar (Back & Stop), trainers y offline"},
  {"exeta", "Exeta", "CaveBot", "Provocar criaturas y condiciones"},
  {"botserver", "Navi", "Navi", "Companeros, mapa independiente, exiva, consumo y conexion"},
  {"containerManager", "Container Manager", "Inventario", "Contenedores, distribucion, Full AFK y posiciones"},
  {"itemcounter", "Item Counter", "Inventario", "Items, cantidades y contadores"},
  {"imbuementscrolls", "Imbuements", "Inventario", "Equipo, scrolls, perfiles y seguimiento", "ImbuementScrolls"},
  {"playerlist", "Player List", "Herramientas", "Amigos, enemigos, outfits y listas"},
  {"pvp_support", "CombatePvP", "Combate", "Push Max, Keep Wall, Fire Bomb, Hold Target, Exiva Target, Exiva Last, Pull Items y Anti Push"},
  {"exivatarget", "Exiva Target", "Combate", "Buscar el objetivo mediante exiva", "ExivaTarget"},
  {"exivalast", "Exiva Last", "Combate", "Buscar al ultimo jugador mediante exiva", "ExivaLast"},
  {"antipush1", "Anti Push", "Combate", "Items y proteccion de posicion", "AntiPush"},
  {"pullitems", "Pull Items", "Combate", "Recogida y distribucion de items", "PullItems"},
  {"recoge", "Recoge Todo", "Herramientas", "Items visibles y recogida", "RecogeTodo"},
  {"bugmapmouse", "Bug Map", "Herramientas", "Movimiento y hotkey", "BugMapMouse"},
  {"timerexecutor", "Timer Executor", "Herramientas", "Acciones, intervalos, condiciones y ejecucion", "TimerExecutor"},
  {"custom_hotkeys", "Hotkeys", "Herramientas", "Teclas, botones del raton y rueda, cada uno con su accion", "CustomHotkeys"},
  {"alarms", "Alarmas", "Herramientas", "Eventos, umbrales, sonidos e iconos"},
  {"z_auto-party", "Auto Party", "Herramientas", "Invitaciones y jugadores"},
  {"tools", "Gold Converter", "Herramientas", "Convierte stacks de monedas; pausa mientras AntiPush esta ON"},
  {"auto_forge", "Auto Forge", "Herramientas", "60 dust a 3 slivers y 50 slivers a 1 exalted core; espera confirmacion", "AutoForge"},
  {"fps_relog", "FPS Relog", "Herramientas", "Dice !fps cada X minutos solo en un momento seguro y mide cuanto tarda el relog", "FpsRelog"},
  {"afk_mode", "Modo AFK", "Herramientas", "Ahorro automatico por inactividad, bandeja y restauracion del cliente", "AfkMode"},
  {"reconnect", "Reconect", "Herramientas", "Si se cae la conexion, vuelve a entrar con el mismo personaje usando el login guardado del cliente", "Reconect"},
  {"eat_food", "Comida", "Curacion", "Comer y conjurar dentro de Condiciones"},
  {"spy_level", "Spy Level", "Herramientas", "Piso visible: icono izquierdo sube, derecho baja; hotkeys opcionales"},
  {"dash", "Dash", "Herramientas", "Movimiento y hotkey", "Dash"},
  {"dummy", "Dummy Smart", "Herramientas", "Items y dummies por prioridad, alternativas y confirmacion", "DummySmart"},
  {"botsettings", "Ajustes generales y PvP", "Ajustes", "Cliente, items, utilidades, hotkeys y PvP"},
  {"iconos", "Iconos", "Ajustes", "Posiciones, colores, modos y accesos"},
  {"ingame_editor", "Scripts", "Scripts", "Editor de scripts personales, importacion, estado y respaldos"},
  {"updater", "Updater", "Ajustes", "Novedades, historial, detalles y progreso"},
  {"licencia", "Licencia", "Ajustes", "Tu clave de RinoBot y el estado de la licencia en este PC"},
  {"console_ui", "Consola", "Ajustes", "Avisos, errores e historial local y estado del bot"},
  {"clientdiagnostics", "Diagnostico de cliente", "Ajustes", "Cliente, servidor, firma DAT y funciones disponibles"},
}
for _, d in ipairs(definitions) do
  local m = {id = d[1]:lower(), name = d[2], section = d[3], description = d[4],
    globalName = d[5], panels = {}, views = {}, available = false}
  H.modules[m.id] = m
  H.order[#H.order + 1] = m
end

-- Retain captured engines/data for Classic; these have no separate Helper row.
H.modules.dash.hidden=true
H.modules.eat_food.hidden=true
H.modules.eat_food.aliasOf="conditions"

-- One Helper entry; keep native identities and saved individual favorites.
H.pvpModuleIds={"pushmax","keepwall","firebomb","holdtarget","exivatarget","exivalast","pullitems","antipush1"}
for _,id in ipairs(H.pvpModuleIds) do H.modules[id].groupId="pvp_support" end


function H.live(widget)
  if not widget then return false end
  local ok, dead = pcall(function() return widget:isDestroyed() end)
  return not ok or not dead
end
function H.valid()
  return not H.disposed and root._sabuezoHelperRuntime == H
end
local function parentOf(w)
  if not H.live(w) then return nil end
  local ok, p = pcall(function() return w:getParent() end)
  if ok then return p end
end
local function inside(w, ancestor)
  for i = 1, 40 do
    if w == ancestor then return true end
    w = parentOf(w)
    if not w then return false end
  end
  return false
end
H.inside = inside

-- H.record used to compare every new control with every captured one (~600 by the end of the
-- load), climbing the parents both ways each time: 0.4-0.8 s of the load (change 161). Same
-- decisions, less work:
--  * the parents of the new control are read once (same walk and limit as inside());
--  * each captured control carries a mark in a Lua field of the native object, which the
--    client keeps for every reference to it, so "is it inside a captured control" is one
--    climb. Marks mirror H.widgets exactly (it is only written in H.record and never cleared).
--    They are used only after checking once that a field survives a new reference; until
--    then, or if a mark cannot be written, the old comparison is used.
local CAPTURE_MARK = "_rinoHelperCaptured"
local marksWork = nil -- nil = not verified yet, true = usable, false = never use
local function ancestorChain(w)
  local chain, node = {w}, w
  for _ = 2, 40 do
    node = parentOf(node)
    if not node then break end
    chain[#chain + 1] = node
  end
  return chain
end
local function chainHas(chain, x)
  for i = 1, #chain do if chain[i] == x then return true end end
  return false
end
local function markCaptured(w)
  if marksWork == false then return end
  local ok = pcall(function() w[CAPTURE_MARK] = H end)
  if not ok then marksWork = false;return end
  if marksWork == nil then
    -- Read the mark through a NEW reference to the same control (one of its parent's children).
    local verified = pcall(function()
      local parent = parentOf(w)
      if not parent then return end
      for _, child in ipairs(parent:getChildren()) do
        if child == w then marksWork = child[CAPTURE_MARK] == H;return end
      end
    end)
    if not verified then marksWork = false end
  end
end
-- true / false, or nil when the marks cannot be trusted (the caller compares instead).
local function capturedOnChain(chain)
  if marksWork ~= true then return nil end
  local ok, found = pcall(function()
    for i = 1, #chain do if chain[i][CAPTURE_MARK] == H then return true end end
    return false
  end)
  if not ok then marksWork = false;return nil end
  return found
end
local function hasChildren(w)
  local ok, count = pcall(w.getChildCount, w)
  return not ok or type(count) ~= "number" or count > 0
end

local styleOwners = {
  TargetBotPanel = "targetbot", TargetBotLootingPanel = "targetbot", TargetBotCreatureEditorWindow = "targetbot",
  CaveBotConfigWindow = "cavebot", CaveBotSetProfileEditorWindow = "cavebot", CaveBotDepotActionWindow = "cavebot",
  BotSettingsWindow = "botsettings", CaveBotPanel = "cavebot", BotServerWindow = "botserver",
  ItemCounterWindow = "itemcounter", UpdaterWindow = "updater", CMUI = "containermanager", AutoForgeWindow = "auto_forge", FpsRelogWindow = "fps_relog",
  AfkModeWindow = "afk_mode",
  InGameScriptManagerWindow = "ingame_editor", IconEditorWindow = "iconos",
  AttackStudioWindow = "attackbot", AttackStudioPicker = "attackbot", AttackStudioOptions = "attackbot",
  AttackStudioConfirm = "attackbot", AttackBotWindow = "attackbot", AttackSpellCatalogWindow = "attackbot",
  HealWindowV3 = "healbot", AutoProtectWindow = "inmortal", ConditionsWindow = "conditions",
  SuppliesWindow = "supplies", DepositerPanel = "depositer_config", EquipWindow = "equipper",
  FriendHealer = "friend_healer", ComboPlusWindow = "combo_plus", FollowWindow = "follow_panel", TimerExecutorWindow = "timerexecutor", TimerExecutorConditionsWindow = "timerexecutor", DummySmartWindow = "dummy",
  CustomHotkeysWindow = "custom_hotkeys",
  PushMaxWindow = "pushmax", BugMapMouseWindow = "bugmapmouse", KeepWallWindow = "keepwall",
  RinoConsoleWindow = "console_ui", CDUI = "clientdiagnostics",
  AlarmsWindow = "alarms", AutoPartyListWindow = "z_auto-party", spellListWindow = "zautobuff",
  ImbuementScrollWindow = "imbuementscrolls", ManaTrainerWindow = "manatrainer",
}
local function sourceOwner(path)
  path = tostring(path or ""):lower():gsub("\\", "/"):gsub("%.lua$", "")
  if path:find("/targetbot/", 1, true) or path:sub(1, 10) == "targetbot/" then return "targetbot" end
  if path:find("/cavebot/", 1, true) or path:sub(1, 8) == "cavebot/" then return "cavebot" end
  local id = path:match("([^/]+)$")
  local aliases = {extras = "botsettings", extraspvp = "botsettings", minimap_drag = "botsettings",
    botserverdashboard = "botserver", exiva_tracker = "botserver", container_layout = "containermanager",
    attack_editor = "attackbot", attack_alignment = "attackbot"}
  return aliases[id] or id
end
H.sourceOwner = sourceOwner

-- fresh: w was created by the UI call that records it (it cannot hold a captured control yet).
function H.record(w, style, isWindow, source, defaultParent, fresh)
  if type(w) ~= "userdata" and type(w) ~= "table" then return end
  if not H.valid() or H.building == false and H.disposed or not H.live(w) or H.widgets[w] then return end
  -- Compact Scripts uses the same manager/routing identity and native callbacks.
  if style == "HelperScriptsCompact" then style = "InGameScriptManagerWindow" end
  local id = styleOwners[style] or sourceOwner(source or H.source)
  if not H.modules[id] and tostring(style):find("CaveBot", 1, true) then id = "cavebot" end
  local m = H.modules[id]
  if not m then return end
  if not isWindow then
    -- Native tabs in this client are siblings of contentsPanel. The calling
    -- module supplies ownership; relying on contentsPanel loses its controls.
    local surface=H.botSurface and H.botSurface()
    local chain=ancestorChain(w) -- inside(w,x) == chainHas(chain,x)
    local nativeTab=false
    for parent in pairs(H.panelParents) do if chainHas(chain,parent) then nativeTab=true;break end end
    if not defaultParent and surface and not chainHas(chain,surface) and not nativeTab and id~="dummy" then return end
    -- A row inside a captured form belongs to that form, not a separate page.
    local captured=capturedOnChain(chain)
    if captured==true then return end
    if captured==nil then
      for other in pairs(H.widgets) do if chainHas(chain,other) then return end end
    end
    -- ...and a control holding a captured page is not one either. A control created by this
    -- very call, or one without children, cannot hold one.
    if not fresh and hasChildren(w) then
      for other in pairs(H.widgets) do if inside(other,w) then return end end
    end
    local parent=parentOf(w)
    if defaultParent and parent and parent~=root then H.panelParents[parent]=true end
  end
  local item = {widget = w, module = m, style = style, window = isWindow, parent = parentOf(w)}
  if isWindow then
    local ok,visible=pcall(function() return w:isVisible() end)
    item.wantShow=ok and visible==true
  end
  local ok, size = pcall(function() return w:getSize() end)
  if ok then item.size = {width = size.width, height = size.height} end
  H.widgets[w] = item
  markCaptured(w)
  if isWindow then m.views[#m.views + 1] = item; H.windows[#H.windows + 1] = item
  else m.panels[#m.panels + 1] = item end
  m.available = true
  if H.mount and not H.building then
    H.mount(item)
    if isWindow and item.wantShow then
      -- Native secondary editors open at construction, with no show() call.
      -- Give their constructor time to install callbacks and initialize fields.
      schedule(1,function()
        if H.valid() and H.live(w) and item.wantShow and H.openView then H.openView(item) end
      end)
    end
  end
  if H.audit and not H.building then H.audit() end
end

-- Measuring only (shown in the load profile): how much start-up time goes into H.record.
H.stats = {recordMs = 0, recordCalls = 0}
do
  local recordOriginal, clock = H.record, type(os) == "table" and os.clock
  if type(clock) == "function" then
    H.record = function(...)
      local started = clock()
      local result = recordOriginal(...)
      H.stats.recordMs = H.stats.recordMs + (clock() - started) * 1000
      H.stats.recordCalls = H.stats.recordCalls + 1
      return result
    end
  end
end

local depth = 0
-- Measuring only (load profile): theme/appearance time per created control. Defined here
-- because fileClock (further down) is not visible to wrap.
local wrapClock = type(os) == "table" and type(os.clock) == "function" and os.clock or nil
local function wrap(fn, isWindow, api)
  return function(...)
    depth = depth + 1
    local first,second,third = ...
    local ok,w
    if HelperTheme and api=="setupUI" then
      ok,w=pcall(fn,HelperTheme.inline(first),second)
    elseif HelperTheme and api=="createWidget" and HelperTheme.types[first] then
      ok,w=pcall(fn,HelperTheme.types[first],second)
    else
      ok,w=pcall(fn,...)
    end
    depth = depth - 1
    if not ok then error(w) end
    -- A container passed as the parent of a UI call may gain widgets: H.after looks there.
    local parentArgument
    if api=="createWidget" or api=="setupUI" or api=="Label" or api=="Separator" then parentArgument=second
    elseif api=="Button" or api=="TextEdit" or api=="CheckBox" then parentArgument=third end
    if type(parentArgument)=="userdata" or type(parentArgument)=="table" then H.touched[parentArgument]=true end
    if depth == 0 then
      if HelperTheme then
        local themeStyle=(api=="createWindow" or api=="createWidget") and first or HelperTheme.types[api]
        if api=="createWidget" then themeStyle=HelperTheme.types[themeStyle] or themeStyle end
        local decorateStarted = wrapClock and wrapClock()
        HelperTheme.decorate(w,themeStyle or "Control",api=="setupUI" and first or nil)
        if decorateStarted and type(H.stats) == "table" then
          H.stats.decorateMs = (H.stats.decorateMs or 0) + (wrapClock() - decorateStarted) * 1000
          H.stats.decorateCalls = (H.stats.decorateCalls or 0) + 1
        end
      end
      local first,second,third = ...
      local style = type(first) == "string" and first:match("^([%w_]+)") or "Control"
      local explicitParent
      if api=="createWidget" or api=="setupUI" or api=="Label" or api=="Separator" then explicitParent=second
      elseif api=="Button" or api=="TextEdit" or api=="CheckBox" then explicitParent=third end
      -- These factories always build a new control. Config, Container and the item/scroll
      -- panels can be handed an existing widget, so they keep the full check (change 161).
      local alwaysNew = api=="createWindow" or api=="createWidget" or api=="setupUI" or api=="Button" or
        api=="Label" or api=="Separator" or api=="TextEdit" or api=="CheckBox"
      H.record(w, style, isWindow, nil, explicitParent==nil, alwaysNew)
    end
    return w
  end
end
for _, name in ipairs({"createWindow", "createWidget", "Button", "Label", "Separator", "Config", "TextEdit", "CheckBox", "Container", "DualScrollItemPanel", "TwoItemsAndSlotPanel", "ScrollBar"}) do
  if type(UI[name]) == "function" then
    H.originals[name] = UI[name]
    UI[name] = wrap(UI[name], name == "createWindow",name)
    H.wrappers[name] = UI[name]
  end
end
H.originals.setupUI = setupUI
setupUI = wrap(setupUI, false,"setupUI")
H.wrappedSetupUI = setupUI
H.originals.dofile = dofile
-- Measuring only: time per file, own time apart from the files it loads (load profile).
H.stats.files = {}
local fileStack = {}
local fileClock = type(os) == "table" and type(os.clock) == "function" and os.clock or nil
dofile = function(path)
  local old = H.source
  H.source = path
  local frame
  if fileClock then
    frame = {start = fileClock(), children = 0}
    fileStack[#fileStack + 1] = frame
  end
  local ok, value = pcall(H.originals.dofile, path)
  if frame then
    fileStack[#fileStack] = nil
    local total = (fileClock() - frame.start) * 1000
    local parent = fileStack[#fileStack]
    if parent then parent.children = parent.children + total end
    local stat = H.stats.files[path]
    if not stat then stat = {self = 0, total = 0, calls = 0}; H.stats.files[path] = stat end
    stat.self, stat.total, stat.calls = stat.self + (total - frame.children), stat.total + total, stat.calls + 1
  end
  H.source = old
  if not ok then assert(false,value) end
  return value
end
H.wrappedDofile = dofile

-- Capture native macro switches and engine-owned controls created internally.
-- Do not inspect native styles or walk the game/map widget tree. This client's
-- getStyleName binding can throw a fatal C++ error that pcall cannot recover.
local function botSurface()
  local w=modules.game_bot.contentsPanel
  for _=1,12 do
    if not H.live(w) then return nil end
    local ok,label=pcall(function() return w:getText() end)
    if ok and label=="Bot" then return w end
    local parent=parentOf(w)
    if not parent or parent==root then return w end
    w=parent
  end
  return modules.game_bot.contentsPanel
end
H.botSurface=botSurface
-- Start-up used to walk the whole widget tree twice for EVERY module (before and after it
-- ran), with several protected calls per widget: 3.3 s of a 6 s load, growing with each
-- module (the tree keeps growing). Same inventory, far less work:
--  * a widget's children are remembered while its child count and last child are unchanged;
--  * the tree seen at the end of one module is the tree before the next one, checked with
--    the child counts of the tabs (any change there falls back to a fresh walk);
--  * a widget's parent is only looked up when the widget is new.
local childMemo = setmetatable({}, {__mode = "k"})
local lastChildWorks = nil -- unknown until the first widget is checked

local function alive(w)
  if not w then return false end
  local ok, dead = pcall(w.isDestroyed, w)
  return not ok or not dead
end

local function childrenOf(w)
  local entry = childMemo[w]
  if entry and lastChildWorks ~= false then
    local okCount, count = pcall(w.getChildCount, w)
    if okCount and count == entry.count then
      local okLast, last = pcall(w.getLastChild, w)
      if okLast then
        lastChildWorks = true
        if last == entry.last then return entry.kids end
      elseif lastChildWorks == nil then
        lastChildWorks = false -- this client cannot answer: always read the children
      end
    end
  end
  local ok, kids = pcall(w.getChildren, w)
  if not ok or type(kids) ~= "table" then return nil end
  -- The client hands out a NEW Lua reference for the same control on every call, and the
  -- inventory is keyed by reference. Keep the references already known for the children
  -- that did not change (native == compares the controls), or every control under a
  -- container that just gained a child looks new and its whole subtree is scanned again:
  -- whole tabs were rescanned for each module (up to 5,000 controls, 2026-11-22).
  if entry and type(entry.kids) == "table" and #entry.kids > 0 then
    pcall(function()
      local old, j = entry.kids, 1
      for i = 1, #kids do
        local kid = kids[i]
        -- Order is kept; a few removed or inserted controls are skipped over.
        for k = j, math.min(#old, j + 8) do
          if old[k] == kid then kids[i] = old[k]; j = k + 1; break end
        end
      end
    end)
  end
  local okCount, count = pcall(w.getChildCount, w)
  childMemo[w] = {count = okCount and count or #kids, last = kids[#kids], kids = kids}
  return kids
end

local walkedCount = 0 -- measuring only: widgets visited by the last full walk
local function snapshot(w, seen)
  if seen[w] or not alive(w) then return end
  seen[w] = true
  walkedCount = walkedCount + 1
  local kids = childrenOf(w)
  if kids then for _, child in ipairs(kids) do snapshot(child, seen) end end
end

-- Child counts of the surface and of every tab: what changes when a module adds a control.
local function fingerprint(surface)
  local fp, n = {}, 0
  local function add(parent)
    if not parent or fp[parent] ~= nil then return end
    local ok, count = pcall(parent.getChildCount, parent)
    fp[parent] = ok and count or -1
    n = n + 1
  end
  add(surface)
  for parent in pairs(H.panelParents) do add(parent) end
  fp._n = n
  return fp
end
local function unchanged(fp, surface)
  if not fp or fp._n == nil then return false end
  local n = 0
  for parent, count in pairs(fp) do
    if parent ~= "_n" then
      n = n + 1
      local ok, now = pcall(parent.getChildCount, parent)
      if not ok or now ~= count then return false end
    end
  end
  local tracked = 1
  for parent in pairs(H.panelParents) do if parent ~= surface then tracked = tracked + 1 end end
  return n == fp._n and tracked == fp._n
end

function H.before(source)
  local started = fileClock and fileClock()
  H.source = source
  H.touched = {}
  local surface=botSurface()
  local known = H._known
  if known and known._surface == surface and unchanged(H._knownFingerprint, surface) then
    if started then H.stats.lastBeforeMs, H.stats.lastFullWalk, H.stats.lastWalked = (fileClock() - started) * 1000, false, 0 end
    return known -- nothing was added since the previous module finished
  end
  local seen = {}
  seen._surface=surface
  walkedCount = 0
  snapshot(surface, seen)
  for parent in pairs(H.panelParents) do snapshot(parent,seen) end
  if started then H.stats.lastBeforeMs, H.stats.lastFullWalk, H.stats.lastWalked = (fileClock() - started) * 1000, true, walkedCount end
  return seen
end
function H.after(source, before)
  local started = fileClock and fileClock()
  local scanned = 0 -- measuring only: new widgets this module added
  local nativeTabs={Main=true,Tools=true,Cave=true,Target=true,HP=true,Core=true,Final=true}
  local visited={}
  local appearance=H.appearanceManager
  local function refreshVisibility(w)
    if appearance and type(appearance.rebindVisibility)=="function" then appearance.rebindVisibility(w) end
  end
  local function scan(w, newContainer, knownParent)
    if visited[w] or not alive(w) then return end
    visited[w]=true
    -- Constructors may assign their own visibility handler after decoration.
    -- Chain it once the module has finished, before returning to the renderer.
    refreshVisibility(w)
    if not before[w] then -- a widget this module added
      scanned = scanned + 1
      -- getParent() returns a fresh userdata in this client. The traversal
      -- already holds the parent's inventory reference, so keep that key.
      local parent=knownParent
      if HelperTheme then
        local started = fileClock and fileClock()
        HelperTheme.bindTooltip(w)
        if started then
          H.stats.tooltipMs = (H.stats.tooltipMs or 0) + (fileClock() - started) * 1000
          H.stats.tooltipCalls = (H.stats.tooltipCalls or 0) + 1
        end
      end
      if before[parent] or newContainer then
        local label,id="",""
        pcall(function() label=w:getText() end)
        pcall(function() id=tostring(w:getId() or ""):lower() end)
        local container=nativeTabs[label] or id:find("tab",1,true) or id:find("contents",1,true)
        if not container then H.record(w,"NativeControl",false,source) end
        newContainer=container and true or false
      end
    end
    local kids = childrenOf(w)
    if kids then for _, child in ipairs(kids) do scan(child,newContainer,w) end end
  end
  local surface = before._surface or botSurface()
  -- Where a module can have added widgets: the surface, every tab, and any container it
  -- passed as the parent of a UI call. Only the path down to those is walked (the tree has
  -- ~40,000 widgets by the end of the load); whatever is new below them is scanned in full,
  -- exactly as before, in the same order.
  local interesting, fallback = {}, {}
  local token={}
  local function isInteresting(w)
    if interesting[w] then return true end
    local ok,marked=pcall(function() return w._rinoHelperScanPath==token end)
    if ok and marked then return true end
    for _,candidate in ipairs(fallback) do if candidate==w then return true end end
    return false
  end
  local function mark(w)
    for _ = 1, 40 do
      if not w or isInteresting(w) then return end
      interesting[w] = true
      -- Ancestors from getParent() and children from getChildren() can be
      -- different Lua references. Native fields bridge that identity gap.
      local ok=false
      if marksWork==true then ok=pcall(function() w._rinoHelperScanPath=token end) end
      if not ok then fallback[#fallback+1]=w end
      if w == surface then return end
      w = parentOf(w)
    end
  end
  mark(surface)
  for parent in pairs(H.panelParents) do mark(parent) end
  -- Explicit parents can themselves be fresh aliases of an existing control.
  -- Marking a path only narrows the walk inside the owned bot surface; a new
  -- parent is still classified by scan, and outside surfaces are not traversed.
  for parent in pairs(H.touched) do mark(parent) end
  local function walk(w)
    if visited[w] or not alive(w) then return end
    visited[w]=true
    refreshVisibility(w)
    local kids = childrenOf(w)
    if not kids then return end
    for _, child in ipairs(kids) do
      if not before[child] then scan(child,false,w)
      elseif isInteresting(child) then walk(child) end
    end
  end
  walk(surface)
  for parent in pairs(H.panelParents) do
    if not before[parent] then before[parent]=true end
    walk(parent)
  end
  -- Everything seen now is known to the next module.
  for w in pairs(visited) do before[w] = true end
  before._surface = surface
  H._known, H._knownFingerprint = before, fingerprint(surface)
  H.touched = {}
  H.source = nil
  if started then H.stats.lastAfterMs, H.stats.lastScanned = (fileClock() - started) * 1000, scanned end
end

function H.dispose(destroying)
  if H.disposed then return end
  H.disposed = true
  if H.appearanceManager then pcall(H.appearanceManager.dispose) end
  if H.restoreNativePanel then pcall(H.restoreNativePanel, H.keepNativeHiddenOnDispose == true) end
  if H.unbind then pcall(H.unbind) end
  for name, wrapper in pairs(H.wrappers) do
    if UI[name] == wrapper then UI[name] = H.originals[name] end
  end
  if setupUI == H.wrappedSetupUI then setupUI = H.originals.setupUI end
  if dofile == H.wrappedDofile then dofile = H.originals.dofile end
  if UI.EditorWindow == H.editText then UI.EditorWindow = H.originals.EditorWindow end
  if UI.MultilineEditorWindow == H.editText then UI.MultilineEditorWindow = H.originals.MultilineEditorWindow end
  for _, widget in ipairs({H.window, H.icon}) do
    if widget ~= destroying and H.live(widget) then pcall(function() widget:destroy() end) end
  end
  for _,panel in ipairs(H.floatingPanels or {}) do
    panel.disposing=true
    if panel.widget~=destroying and H.live(panel.widget) then pcall(function() panel.widget:destroy() end) end
  end
  -- Native game_bot owns destruction of botWidget trees and schedule callbacks.
  if root._sabuezoHelperRuntime == H then root._sabuezoHelperRuntime = nil end
end
