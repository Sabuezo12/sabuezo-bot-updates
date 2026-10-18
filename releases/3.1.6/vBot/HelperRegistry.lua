-- Helper's UI inventory. Capture existing controls, never load a second engine.
local root = g_ui.getRootWidget()
local previous = root._sabuezoHelperRuntime
if previous and previous.dispose then pcall(previous.dispose) end

Helper = {modules = {}, order = {}, widgets = {}, windows = {}, source = nil,
  root = root, disposed = false, building = true, originals = {}, wrappers = {}, panelParents = {}}
local H = Helper
H.appearanceManager=HelperAppearance
if H.appearanceManager then H.appearanceManager.owner=H end
root._sabuezoHelperRuntime = H

H.sections = {"Inicio", "Combate", "Curacion", "Proteccion", "CaveBot", "Navi", "Inventario", "Herramientas", "Scripts", "Ajustes"}
H.sectionLabels = {Curacion="Curacion", Proteccion="Proteccion", Scripts="Scripts"}
local definitions = {
  {"attackbot", "AttackBot", "Combate", "Rotaciones, vocaciones, hechizos, runas, catalogo y seguridad", "AttackBot"},
  {"targetbot", "TargetBot", "Combate", "Criaturas, prioridades, distancias, movimiento, antitrap y loot", "TargetBot"},
  {"combo_plus", "Combo", "Combate", "Combos, seguimiento, runas y tiempos"},
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
  {"cavebot_control_panel", "Controles de ruta", "CaveBot", "Refill, Back & Stop, trainers y offline"},
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
  {"alarms", "Alarmas", "Herramientas", "Eventos, umbrales, sonidos e iconos"},
  {"z_auto-party", "Auto Party", "Herramientas", "Invitaciones y jugadores"},
  {"tools", "Gold Converter", "Herramientas", "Conversion de oro y mensajes"},
  {"eat_food", "Comida", "Curacion", "Comer y conjurar dentro de Condiciones"},
  {"spy_level", "Spy Level", "Herramientas", "Hotkeys para cambiar piso"},
  {"dash", "Dash", "Herramientas", "Movimiento y hotkey", "Dash"},
  {"dummy", "Dummy Smart", "Herramientas", "Items y dummies por prioridad, alternativas y confirmacion", "DummySmart"},
  {"botsettings", "Ajustes generales y PvP", "Ajustes", "Cliente, items, utilidades, hotkeys y PvP"},
  {"iconos", "Iconos", "Ajustes", "Posiciones, colores, modos y accesos"},
  {"ingame_editor", "Scripts", "Scripts", "Editor de scripts personales, importacion, estado y respaldos"},
  {"updater", "Updater", "Ajustes", "Novedades, historial, detalles y progreso"},
  {"console_ui", "Consola", "Ajustes", "Avisos, errores e historial local y estado del bot"},
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

local styleOwners = {
  TargetBotPanel = "targetbot", TargetBotLootingPanel = "targetbot", TargetBotCreatureEditorWindow = "targetbot",
  CaveBotConfigWindow = "cavebot", CaveBotSetProfileEditorWindow = "cavebot", CaveBotDepotActionWindow = "cavebot",
  BotSettingsWindow = "botsettings", CaveBotPanel = "cavebot", BotServerWindow = "botserver",
  ItemCounterWindow = "itemcounter", UpdaterWindow = "updater", CMUI = "containermanager",
  InGameScriptManagerWindow = "ingame_editor", IconEditorWindow = "iconos",
  AttackStudioWindow = "attackbot", AttackStudioPicker = "attackbot", AttackStudioOptions = "attackbot",
  AttackStudioConfirm = "attackbot", AttackBotWindow = "attackbot", AttackSpellCatalogWindow = "attackbot",
  HealWindowV3 = "healbot", AutoProtectWindow = "inmortal", ConditionsWindow = "conditions",
  SuppliesWindow = "supplies", DepositerPanel = "depositer_config", EquipWindow = "equipper",
  FriendHealer = "friend_healer", ComboPlusWindow = "combo_plus", TimerExecutorWindow = "timerexecutor", TimerExecutorConditionsWindow = "timerexecutor", DummySmartWindow = "dummy",
  PushMaxWindow = "pushmax", BugMapMouseWindow = "bugmapmouse", KeepWallWindow = "keepwall",
  RinoConsoleWindow = "console_ui",
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

function H.record(w, style, isWindow, source, defaultParent)
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
    local nativeTab=false
    for parent in pairs(H.panelParents) do if inside(w,parent) then nativeTab=true;break end end
    if not defaultParent and surface and not inside(w,surface) and not nativeTab and id~="dummy" then return end
    -- A row inside a captured form belongs to that form, not a separate page.
    for captured in pairs(H.widgets) do
      if inside(w,captured) or inside(captured,w) then return end
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

local depth = 0
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
    if depth == 0 then
      if HelperTheme then
        local themeStyle=(api=="createWindow" or api=="createWidget") and first or HelperTheme.types[api]
        if api=="createWidget" then themeStyle=HelperTheme.types[themeStyle] or themeStyle end
        HelperTheme.decorate(w,themeStyle or "Control",api=="setupUI" and first or nil)
      end
      local first,second,third = ...
      local style = type(first) == "string" and first:match("^([%w_]+)") or "Control"
      local explicitParent
      if api=="createWidget" or api=="setupUI" or api=="Label" or api=="Separator" then explicitParent=second
      elseif api=="Button" or api=="TextEdit" or api=="CheckBox" then explicitParent=third end
      H.record(w, style, isWindow, nil, explicitParent==nil)
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
dofile = function(path)
  local old = H.source
  H.source = path
  local ok, value = pcall(H.originals.dofile, path)
  H.source = old
  if not ok then error(value) end
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
local function snapshot(w, seen)
  if not H.live(w) then return end
  seen[w] = true
  local ok, children = pcall(function() return w:getChildren() end)
  if ok then for _, child in ipairs(children) do snapshot(child, seen) end end
end
function H.before(source)
  H.source = source
  local seen = {}
  local surface=botSurface()
  seen._surface=surface
  snapshot(surface, seen)
  for parent in pairs(H.panelParents) do snapshot(parent,seen) end
  return seen
end
function H.after(source, before)
  local nativeTabs={Main=true,Tools=true,Cave=true,Target=true,HP=true,Core=true,Final=true}
  local visited={}
  local function scan(w, newContainer)
    if not H.live(w) or visited[w] then return end
    visited[w]=true
    local parent=parentOf(w)
    local added=not before[w]
    if added and HelperTheme then HelperTheme.bindTooltip(w) end
    if added and (before[parent] or newContainer) then
      local label,id="",""
      pcall(function() label=w:getText() end)
      pcall(function() id=tostring(w:getId() or ""):lower() end)
      local container=nativeTabs[label] or id:find("tab",1,true) or id:find("contents",1,true)
      if not container then H.record(w,"NativeControl",false,source) end
      newContainer=container and true or false
    end
    local ok, children = pcall(function() return w:getChildren() end)
    if ok then for _, child in ipairs(children) do scan(child,newContainer) end end
  end
  scan(before._surface or botSurface())
  for parent in pairs(H.panelParents) do
    if not before[parent] then before[parent]=true end
    scan(parent)
  end
  H.source = nil
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
