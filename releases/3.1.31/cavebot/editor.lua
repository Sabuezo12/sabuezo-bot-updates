CaveBot.Editor = {}
CaveBot.Editor.Actions = {}

-- Route editor buttons in rows (changes 216-217). Each entry says the row (a HelperCaveGroupRow of
-- HelperCaveEditorPanel in vBot/Helper.otui), the position inside it and the tooltip. Captions and
-- colors are each action's own, as before. Action ids, their editors and the values saved in the
-- routes are the same. Actions missing here (new or optional extensions) go to the "buttons" panel
-- under the rows, which shows only when it has buttons.
CaveBot.Editor.GroupOrder = {groupEdit = 1, groupWalk = 2, groupRoute = 3, groupRefill = 4, groupTravel = 5, groupHunt = 6}
CaveBot.Editor.Layout = {
  ["Revisar ruta"] = {group = "groupEdit", order = 1,
    tip = "Revisa toda la ruta y lista errores y avisos: acciones desconocidas, labels vacios, repetidos o que faltan."},
  ["move up"] = {group = "groupEdit", order = 2, tip = "Sube el waypoint marcado un puesto."},
  edit = {group = "groupEdit", order = 3, tip = "Abre el waypoint marcado para cambiar su valor (tambien con doble clic en la lista)."},
  ["move down"] = {group = "groupEdit", order = 4, tip = "Baja el waypoint marcado un puesto."},
  remove = {group = "groupEdit", order = 5, tip = "Borra el waypoint marcado. No pide confirmacion."},

  ["goto"] = {group = "groupWalk", order = 1, tip = "Camina hasta la casilla x,y,z. Propone la casilla donde estas."},
  stepdirection = {group = "groupWalk", order = 2,
    tip = "Da un paso hacia norte, sur, este, oeste o diagonal, con reintentos y espera."},
  use = {group = "groupWalk", order = 3,
    tip = "Usa lo que hay en la casilla x,y,z (escalera, palanca, puerta) o un item del inventario por su id."},
  usewith = {group = "groupWalk", order = 4, tip = "Usa un item (id) sobre la casilla x,y,z, por ejemplo rope o shovel."},
  opendoors = {group = "groupWalk", order = 5, tip = "Abre la puerta de la casilla x,y,z; opcional el id de la llave."},
  cleartile = {group = "groupWalk", order = 6, tip = "Despeja la casilla x,y,z: rompe campos y aparta lo que bloquea el paso."},

  label = {group = "groupRoute", order = 1, tip = "Un nombre de punto de la ruta: go to label, supply check y otros saltan a el."},
  gotolabel = {group = "groupRoute", order = 2, tip = "Salta al label indicado y sigue la ruta desde ahi."},
  delay = {group = "groupRoute", order = 3, tip = "Espera esos milisegundos antes del siguiente paso. Opcional: % al azar (500,20)."},
  poscheck = {group = "groupRoute", order = 4,
    tip = "Si no estas cerca del punto x,y,z, vuelve al label indicado (last: al ultimo waypoint alcanzable)."},
  ["function"] = {group = "groupRoute", order = 5, tip = "Una regla visual o codigo Lua que decide que hacer en ese punto."},
  setprofile = {group = "groupRoute", order = 6, tip = "Carga otra ruta del CaveBot (una fija o una al azar entre varias)."},

  supplycheck = {group = "groupRefill", order = 1,
    tip = "Si alcanzan supplies y cap salta al label de la hunt; si no, sigue al refill."},
  depot = {group = "groupRefill", order = 2, tip = "Elige depositar, retirar o ambos en el depot."},
  bank = {group = "groupRefill", order = 3, tip = "Deposita, retira o transfiere oro con el NPC del banco."},
  sellall = {group = "groupRefill", order = 4, tip = "Vende todo al NPC, menos las excepciones que marques."},
  buysupplies = {group = "groupRefill", order = 5, tip = "Compra al NPC los supplies que faltan segun Supplies."},
  imbuing = {group = "groupRefill", order = 6, tip = "Renueva los imbuements de los items indicados."},

  npcsay = {group = "groupTravel", order = 1, tip = "Dice un texto en el canal de NPCs (hi, trade, yes...)."},
  say = {group = "groupTravel", order = 2, tip = "Dice un texto en el chat normal."},
  travel = {group = "groupTravel", order = 3,
    tip = "Viaja con un NPC (barco, alfombra...) a la ciudad indicada y confirma la llegada."},
  supremecube = {group = "groupTravel", order = 4,
    tip = "Viaja con el Supreme Cube a un destino fijo; espera el cooldown y confirma la llegada."},
  tasker = {group = "groupTravel", order = 5, tip = "Pide, revisa o entrega una task del NPC de tasks."},

  lure = {group = "groupHunt", order = 1,
    tip = "start apaga el TargetBot para juntar monstruos, stop lo enciende, toggle lo alterna."},
  rushlure = {group = "groupHunt", order = 2,
    tip = "Corre hasta x,y,z, espera esos ms y elige si el TargetBot ataca mientras tanto."},
  follow = {group = "groupHunt", order = 3, tip = "Sigue a una criatura por su nombre."},
  waitstamina = {group = "groupHunt", order = 4, tip = "Con la stamina bajo la minima espera hasta la maxima o va a un label."},
  zonapz = {group = "groupHunt", order = 5, tip = "Punto PZ y minutos de espera tras una huida PvP. En ruta normal no espera."}
}

-- Row panel for a button: its group's list, or the generic "buttons" panel (also in the classic editor,
-- which has no groups). A full row (6 buttons) sends the extra one to "buttons" so nothing is cut off.
local function editorButtonParent(place)
  local ui = CaveBot.Editor.ui
  local row = place and ui[place.group]
  local list = row and row.list
  if list and #list:getChildren() < 6 then return list end
  if not ui.buttons:isVisible() then ui.buttons:show() end
  return ui.buttons
end

-- also works as registerAction(action, params), then text == action
-- params are options for text editor or function to be executed when clicked
-- you have many examples how to use it bellow
CaveBot.Editor.registerAction = function(action, text, params)
  if type(text) ~= 'string' then
    params = text
    text = action
  end

  local color = nil
  if type(params) ~= 'function' then
    local raction = CaveBot.Actions[action]
    if not raction then
      return warn("CaveBot editor warn: action " .. action .. " doesn't exist")
    end
    CaveBot.Editor.Actions[action] = params
    color = raction.color
  end

  local place = CaveBot.Editor.Layout[action]
  local parent = editorButtonParent(place)
  local button = UI.createWidget('CaveBotEditorButton', parent)
  if place then
    -- Every row but the first adds a step to the route, always under the marked waypoint.
    button:setTooltip(place.group == "groupEdit" and place.tip or (place.tip .. "\nSe agrega debajo del waypoint marcado."))
    button.caveGroup = place.group
    button.caveRank = (CaveBot.Editor.GroupOrder[place.group] or 9) * 100 + place.order
    -- Extensions register in no fixed order: keep the layout's order. Buttons outside the layout
    -- stay after these, in the order they were registered.
    local index = 1
    for _, other in ipairs(parent:getChildren()) do
      if other ~= button and other.caveRank and other.caveRank < button.caveRank then index = index + 1 end
    end
    parent:moveChildToIndex(button, index)
  end
  -- Every caption starts with a capital letter (change 223): "Go to", "Step direction", "Npcsay"...
  -- Only the caption: action ids and the values saved in the routes stay as they are.
  text = text:sub(1, 1):upper() .. text:sub(2)
  button:setText(text)
  if color then
    button:setColor(color)
  end
  button:setFont('verdana-11px-rounded')
  button.onClick = function()    
    if type(params) == 'function' then
      params()
      return
    end
    CaveBot.Editor.edit(action, nil, function(action, value)
      local focusedAction = CaveBot.actionList:getFocusedChild()
      local index = CaveBot.actionList:getChildCount()
      if focusedAction then
        index = CaveBot.actionList:getChildIndex(focusedAction)
      end
      local widget = CaveBot.addAction(action, value)
      CaveBot.actionList:moveChildToIndex(widget, index + 1)
      CaveBot.actionList:focusChild(widget)
      CaveBot.save()
    end)
  end
  return button
end

CaveBot.Editor.getCaveBotProfiles = function()
  local profiles = Config.list("cavebot_configs")

  table.sort(profiles)
  return profiles
end

CaveBot.Editor.parseSetProfileValue = function(value)
  value = tostring(value or ""):trim()
  if value == "" or value == "profileName" then
    return {}
  end

  if value:sub(1, 7):lower() == "random:" then
    value = value:sub(8)
  end

  local selected = {}
  for profile in value:gmatch("[^,]+") do
    profile = profile:trim()
    if profile ~= "" then
      table.insert(selected, profile)
    end
  end

  return selected
end

CaveBot.Editor.formatSetProfileValue = function(profiles)
  if #profiles == 1 then
    return profiles[1]
  end

  return "random:" .. table.concat(profiles, ",")
end

CaveBot.Editor.editSetProfile = function(value, callback)
  local editor = UI.createWindow("CaveBotSetProfileEditorWindow")
  local profiles = CaveBot.Editor.getCaveBotProfiles()
  local selected = CaveBot.Editor.parseSetProfileValue(value)
  local selectedByName = {}
  local profileWidgets = {}

  for _, profile in ipairs(selected) do
    selectedByName[profile] = true
  end

  local function getSelectedProfiles()
    local result = {}
    for _, entry in ipairs(profileWidgets) do
      if entry.widget:isOn() then
        table.insert(result, entry.name)
      end
    end
    return result
  end

  local function updatePreview()
    local selectedProfiles = getSelectedProfiles()
    if #selectedProfiles == 0 then
      editor.preview:setText("Select at least one route.")
    elseif #selectedProfiles == 1 then
      editor.preview:setText("Next route: " .. selectedProfiles[1])
    else
      editor.preview:setText("Random route: " .. #selectedProfiles .. " selected")
    end
  end

  if #profiles == 0 then
    UI.Label("No cavebot configs found.", editor.profiles)
  else
    for _, profile in ipairs(profiles) do
      local widget = UI.createWidget("CaveBotSetProfileCheckBox", editor.profiles)
      widget:setText(profile)
      widget:setOn(selectedByName[profile] == true)
      widget.onClick = function()
        widget:setOn(not widget:isOn())
        updatePreview()
      end
      table.insert(profileWidgets, {name = profile, widget = widget})
    end
  end

  editor.cancel.onClick = function()
    editor:destroy()
  end
  editor.onEscape = editor.cancel.onClick

  editor.ok.onClick = function()
    local selectedProfiles = getSelectedProfiles()
    if #selectedProfiles == 0 then
      return
    end

    editor:destroy()
    callback(CaveBot.Editor.formatSetProfileValue(selectedProfiles))
  end

  updatePreview()
end

CaveBot.Editor.editZonePZ = function(value,callback)
  local zone=CaveBot.FleeTools.zoneConfig(value)
  local editor=UI.createWindow('CaveBotZonePZWindow')
  local p=zone and zone.pos or {x=posx(),y=posy(),z=posz()}
  editor.coordinates:setText(p.x..','..p.y..','..p.z)
  editor.minutes:setText(tostring(zone and zone.minutes or 0))
  editor.feedback:setText(zone and ''or 'Revisa el punto y los minutos antes de guardar.')
  editor.cancel.onClick=function()editor:destroy()end
  editor.onEscape=editor.cancel.onClick
  if editor.closeButton then editor.closeButton.onClick=editor.cancel.onClick end
  editor.ok.onClick=function()
    local position=CaveBot.FleeTools.zonePosition(editor.coordinates:getText())
    local text=editor.minutes:getText()
    if not position or not tostring(editor.coordinates:getText()):match('^%s*%d+%s*,%s*%d+%s*,%s*%d+%s*$')then
      editor.feedback:setText('Punto invalido: usa x,y,z de una casilla PZ.');return
    end
    if not tostring(text):match('^%s*%d+%s*$')then editor.feedback:setText('Espera: minutos enteros de 0 a 10080.');return end
    local encoded=CaveBot.FleeTools.zoneValue(position,tonumber(text))
    if not encoded then editor.feedback:setText('Espera: minutos enteros de 0 a 10080.');return end
    callback(encoded);editor:destroy()
  end
  editor.coordinates.onEnter=editor.ok.onClick;editor.minutes.onEnter=editor.ok.onClick
  return editor
end

CaveBot.Editor.editWaitStamina = function(value, callback)
  local config, message = CaveBot.WaitStamina.decode(value)
  config = config or CaveBot.WaitStamina.defaults()
  config.maximum=config.maximum or 2520
  local editor = UI.createWindow("CaveBotWaitStaminaWindow")
  editor.minimum:setText(CaveBot.WaitStamina.formatHours(config.minimum))
  editor.maximum:setText(CaveBot.WaitStamina.formatHours(config.maximum))
  editor.interval:setText(tostring(config.checkMs / 1000))
  editor.belowMode:addOption("Quedarse y esperar", "wait")
  editor.belowMode:addOption("Ir a un label", "label")
  editor.readyMode:addOption("Siguiente waypoint", "next")
  editor.readyMode:addOption("Ir a un label", "label")
  local function routeLabels()
    local names, seen = {}, {}
    for _, widget in ipairs(CaveBot.actionList:getChildren()) do
      if widget.action == "label" and type(widget.value) == "string" then
        local name = widget.value:trim()
        if name ~= "" and not seen[name:lower()] then names[#names+1]=name; seen[name:lower()]=name end
      end
    end
    return names, seen
  end
  local names, seen = routeLabels()
  local function populate(combo, selected)
    combo:addOption("Selecciona un label", "")
    for _, name in ipairs(names) do combo:addOption(name, name) end
    if selected ~= "" then
      local actual = seen[selected:lower()]
      if not actual then combo:addOption(selected .. " (no existe)", selected) end
      combo:setCurrentOptionByData(actual or selected)
    end
  end
  populate(editor.belowLabel, config.belowLabel)
  populate(editor.readyLabel, config.readyLabel)
  editor.belowMode:setCurrentOptionByData(config.below)
  editor.readyMode:setCurrentOptionByData(config.ready)
  local function selection(combo)
    local option = combo:getCurrentOption()
    return option and option.data or ""
  end
  local function updateModes()
    editor.belowLabel:setEnabled(selection(editor.belowMode) == "label")
    editor.readyLabel:setEnabled(selection(editor.readyMode) == "label")
    editor.feedback:setText("")
  end
  editor.belowMode.onOptionChange=updateModes
  editor.readyMode.onOptionChange=updateModes
  editor.belowLabel.onOptionChange=function() editor.feedback:setText("") end
  editor.readyLabel.onOptionChange=editor.belowLabel.onOptionChange
  updateModes()
  if message then editor.feedback:setText(message) end
  editor.cancel.onClick=function() editor:destroy() end
  editor.onEscape=editor.cancel.onClick
  if editor.closeButton then editor.closeButton.onClick=editor.cancel.onClick end
  editor.ok.onClick=function()
    local minimum = CaveBot.WaitStamina.parseHours(editor.minimum:getText())
    local maximum = CaveBot.WaitStamina.parseHours(editor.maximum:getText())
    local seconds = tonumber(editor.interval:getText())
    if not minimum then editor.feedback:setText("Stamina invalida. Usa HH:MM entre 00:00 y 42:00."); return end
    if not maximum or maximum < minimum then
      editor.feedback:setText("Maxima invalida: debe ser >= minima y <= 42:00."); return
    end
    if not seconds or seconds ~= seconds or seconds < 0.1 or seconds > 3600 then
      editor.feedback:setText("Intervalo invalido: de 0.1 a 3600 segundos."); return
    end
    local draft = {minimum=minimum, maximum=maximum, checkMs=math.floor(seconds * 1000 + 0.5),
      below=selection(editor.belowMode), belowLabel=selection(editor.belowLabel),
      ready=selection(editor.readyMode), readyLabel=selection(editor.readyLabel)}
    local _, currentLabels = routeLabels()
    for _, branch in ipairs({"below", "ready"}) do
      if draft[branch] == "label" and not currentLabels[draft[branch .. "Label"]:lower()] then
        editor.feedback:setText("Selecciona un label que exista en esta ruta."); return
      end
    end
    local encoded, errorText = CaveBot.WaitStamina.encode(draft)
    if not encoded then editor.feedback:setText(errorText); return end
    callback(encoded)
    editor:destroy()
  end
  editor.minimum.onEnter=editor.ok.onClick
  editor.maximum.onEnter=editor.ok.onClick
  editor.interval.onEnter=editor.ok.onClick
  return editor
end

-- The window is a new style: give it the same skin descriptors as the other CaveBot editor windows.
local function registerSellAllSkin()
  local appearance = HelperAppearance
  local styles = type(appearance) == "table" and type(appearance.metadata) == "table" and appearance.metadata.styles
  if type(styles) ~= "table" or styles.CaveBotSellAllWindow then return end
  local template = styles.CaveBotZonePZWindow
  if type(template) ~= "table" then return end
  local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = copy(v) end
    return result
  end
  local function node(kind, id)
    local base = styles[kind]
    local item = type(base) == "table" and copy(base) or {props = {}, states = {}}
    item.style, item.type, item.id, item.children = kind, kind, id, {}
    return item
  end
  local window = copy(template)
  window.style = "CaveBotSellAllWindow"
  window.children = {node("HelperThemeLabel", "npcTitle"), node("HelperThemeInput", "npc"), node("HelperThemeCheck", "delayed"),
    node("HelperThemeLabel", "exceptionsTitle"), node("BotContainer", "exceptions"), node("HelperThemeLabel", "globalNote"),
    node("HelperThemeLabel", "feedback"), node("HelperThemeButton", "cancel"), node("HelperThemeButton", "ok")}
  styles.CaveBotSellAllWindow = window
end

-- Name of the closest NPC on screen: a new action is almost always added next to the NPC it will use.
local function nearestNpcName()
  if type(getSpectators) ~= "function" or not player then return "" end
  local ok, spectators = pcall(getSpectators)
  if not ok or type(spectators) ~= "table" then return "" end
  local okPos, here = pcall(function() return player:getPosition() end)
  if not okPos or type(here) ~= "table" then return "" end
  local best, bestDistance = "", math.huge
  for _, creature in pairs(spectators) do
    local isNpc = false
    pcall(function() isNpc = creature:isNpc() == true end)
    if isNpc then
      local okC, there = pcall(function() return creature:getPosition() end)
      if okC and type(there) == "table" and there.z == here.z then
        local distance = math.max(math.abs(there.x - here.x), math.abs(there.y - here.y))
        local okName, name = pcall(function() return creature:getName() end)
        if okName and type(name) == "string" and name ~= "" and distance < bestDistance then best, bestDistance = name, distance end
      end
    end
  end
  return best
end

-- The grid always shows this many rows of slots (the container only makes 10 and adds slots as they fill up).
local SELL_ALL_SLOTS = 40

-- "Sell all": NPC, delay, and the items that must NOT be sold (dragged from a backpack onto the grid).
CaveBot.Editor.editSellAll = function(value, callback)
  local SellAll = CaveBot.Extensions and CaveBot.Extensions.SellAll
  local config = SellAll and SellAll.decode and SellAll.decode(value) or {npc = "", delayed = false, ids = {}, extra = {}}
  pcall(registerSellAllSkin)
  local editor = UI.createWindow("CaveBotSellAllWindow")
  editor.npc:setText(config.npc ~= "" and config.npc or nearestNpcName())
  editor.delayed:setChecked(config.delayed)
  local general = type(storage.cavebotSell) == "table" and #storage.cavebotSell or 0
  editor.globalNote:setText(general > 0
    and ("Ademas se conservan los " .. general .. " objetos de Depositos > Sell Exeptions.")
    or "La lista de Depositos > Sell Exeptions esta vacia.")
  if type(UI.Container) == "function" then UI.Container(function() end, true, nil, editor.exceptions) end
  -- Pad the list with empty entries (0) so the grid keeps SELL_ALL_SLOTS slots (4 rows). The container rebuilds
  -- itself through panel:setItems after every drop, so the padding goes in setItems, not in this call.
  local container = editor.exceptions
  local nativeSetItems = container.setItems
  if type(nativeSetItems) == "function" then
    container.setItems = function(self, items)
      if self ~= container then items = self end
      local list = {}
      for _, entry in ipairs(type(items) == "table" and items or {}) do list[#list + 1] = entry end
      while #list < SELL_ALL_SLOTS - 2 do list[#list + 1] = 0 end
      return nativeSetItems(container, list)
    end
  end
  container:setItems(config.ids)

  local function exceptionIds()
    local ids, seen = {}, {}
    for _, item in ipairs(editor.exceptions:getItems() or {}) do
      local id = tonumber(type(item) == "table" and (item.id or item[1]) or item)
      if id and id > 100 and id == math.floor(id) and not seen[id] then seen[id] = true; ids[#ids + 1] = id end
    end
    return ids
  end

  editor.cancel.onClick = function() editor:destroy() end
  editor.onEscape = editor.cancel.onClick
  if editor.closeButton then editor.closeButton.onClick = editor.cancel.onClick end
  editor.ok.onClick = function()
    local npc = tostring(editor.npc:getText() or ""):trim()
    if npc == "" then editor.feedback:setText("Escribe el nombre del NPC."); return end
    if npc:find(",", 1, true) then editor.feedback:setText("El nombre del NPC no puede llevar comas."); return end
    local encoded = SellAll.encode({npc = npc, delayed = editor.delayed:isChecked(), ids = exceptionIds(), extra = config.extra})
    callback(encoded)
    editor:destroy()
  end
  editor.npc.onEnter = editor.ok.onClick
  return editor
end

CaveBot.Editor.setup = function()
  CaveBot.Editor.ui = UI.createWidget(Helper and "HelperCaveEditorPanel" or "CaveBotEditorPanel")
  local ui = CaveBot.Editor.ui
  local registerAction = CaveBot.Editor.registerAction

  registerAction('Revisar ruta',function()CaveBot.Editor.reviewRoute()end)

  registerAction("move up", function()
    local action = CaveBot.actionList:getFocusedChild()
    if not action then return end
    local index = CaveBot.actionList:getChildIndex(action)
    if index < 2 then return end
    CaveBot.actionList:moveChildToIndex(action, index - 1)
    CaveBot.actionList:ensureChildVisible(action)
    CaveBot.save()
  end)
  registerAction("edit", function()
    local action = CaveBot.actionList:getFocusedChild()
    if not action or not action.onDoubleClick then return end
    action.onDoubleClick(action)
  end)
  registerAction("move down", function()
    local action = CaveBot.actionList:getFocusedChild()
    if not action then return end
    local index = CaveBot.actionList:getChildIndex(action)
    if index >= CaveBot.actionList:getChildCount() then return end
    CaveBot.actionList:moveChildToIndex(action, index + 1)
    CaveBot.actionList:ensureChildVisible(action)
    CaveBot.save()
  end)
  registerAction("remove", function()
    local action = CaveBot.actionList:getFocusedChild()
    if not action then return end
    action:destroy()
    CaveBot.save()
  end)
    
  registerAction("label", {
    value="labelName",
    title="Label",
    description="Add label",
    multiline=false   
  })
  registerAction("delay", {
    value="500",
    title="Delay",
    description="Delay next action (in milliseconds),randomness (in percent-optional)",
    multiline=false,
    validation="^[0-9]{1,10}$|^[0-9]{1,10},[0-9]{1,4}$"
  })
  registerAction("waitstamina", "wait stamina", {
    value=function() return CaveBot.WaitStamina.encode(CaveBot.WaitStamina.defaults()) end,
    title="Wait stamina",
    description="Solo bajo la minima espera o va al label; al esperar sigue hasta la maxima. Horas:minutos y destinos.",
    multiline=false
  })
  registerAction("zonapz", "ZonaPZ", {
    value=function() return posx() .. "," .. posy() .. "," .. posz() end,
    title="ZonaPZ",
    description="Punto PZ y espera solo tras una huida PvP. En ruta normal no espera. 0: sin espera.",
    multiline=false,
    validation="^\\s*[0-9]{1,5}\\s*,\\s*[0-9]{1,5}\\s*,\\s*[0-9]{1,2}\\s*(,\\s*[0-9]{1,5}\\s*)?$"
  })
  registerAction("stepdirection", "step direction", {
    value="sur,30,200",
    title="Step direction",
    description="Direction,max retries,delay in milliseconds",
    multiline=false,
    validation="^\\s*(n|north|norte|e|east|este|derecha|s|south|sur|w|west|oeste|izquierda|ne|northeast|north-east|noreste|nordeste|se|southeast|south-east|sureste|nw|northwest|north-west|noroeste|sw|southwest|south-west|suroeste)\\s*(,\\s*[0-9]+\\s*)?(,\\s*[0-9]+\\s*)?$"
  })
  registerAction("setprofile", "set profile", {
    value="profileName",
    title="Set CaveBot profile",
    description="Change CaveBot route config by profile name without .cfg",
    multiline=false,
    validation="^\\s*(random:)?[^,]+(\\s*,\\s*[^,]+)*\\s*$"
  })
  registerAction("gotolabel", "go to label", {
    value="labelName",
    title="Go to label",
    description="Go to label",
    multiline=false   
  })
  registerAction("goto", "go to", {
    value=function() return posx() .. "," .. posy() .. "," .. posz() end,
    title="Go to position",
    description="Go to position (x,y,z)",
    multiline=false,
    validation="^\\s*([0-9]+)\\s*,\\s*([0-9]+)\\s*,\\s*([0-9]+),?\\s*([0-9]?)$"
  })
  registerAction("use", {
    value=function() return posx() .. "," .. posy() .. "," .. posz() end,
    title="Use",
    description="Use item from position (x,y,z) or from inventory (itemId)",
    multiline=false   
  }) 
  -- Recorded entries can be edited by double-click without adding another
  -- button or changing the classic editor's layout/order.
  CaveBot.Editor.Actions.floorchange = {
    title="Paso de escalera grabado",
    description="Antes: x,y,z; entrada: x,y; llegada: x,y,z (8 numeros)",
    multiline=false,
    width=550,
    validation="^\\s*[0-9]+(\\s*,\\s*[0-9]+){7}\\s*$"
  }
  registerAction("usewith", "use with", {
    value=function() return "itemId," .. posx() .. "," .. posy() .. "," .. posz() end,
    title="Use with",
    description="Use item at position (itemid,x,y,z)",
    multiline=false,
    validation="^\\s*([0-9]+)\\s*,\\s*([0-9]+)\\s*,\\s*([0-9]+)\\s*,\\s*([0-9]+)$"
  })
  registerAction("say", {
    value="text",
    title="Say",
    description="Enter text to say",
    multiline=false   
  }) 
  registerAction("follow", {
    value="NPC name",
    title="Follow Creature",
    description="insert creature name to follow",
    multiline=false   
  })
  registerAction("npcsay", {
    value="text",
    title="NPC Say",
    description="Enter text to NPC say",
    multiline=false   
  }) 
  registerAction("function", {
    title="Edit bot function",
    multiline=true,
    value=CaveBot.Editor.ExampleFunctions[1][2],
    examples=CaveBot.Editor.ExampleFunctions,
    width=650
  })
  
  -- ui.autoRecording.onClick = function()
  --   if ui.autoRecording:isOn() then
  --     CaveBot.Recorder.disable()
  --   else
  --     CaveBot.Recorder.enable()
  --   end
  -- end
  
  -- callbacks
  -- Helper (changes 219-220): a small box centered under the waypoint list (HelperCaveBotPanel, the
  -- parent of the list's panel); classic: the editor's own "Position:" line.
  local listPanel = CaveBot.actionList and CaveBot.actionList:getParent()
  local waypoints = listPanel and listPanel:getParent()
  local box = waypoints and waypoints.cavePosition
  local posLabel = box or ui.pos
  local function showPosition(x, y, z)
    if not posLabel then return end
    posLabel:setText((box and "Posicion: " or "Position: ") .. x .. ", " .. y .. ", " .. z)
  end
  onPlayerPositionChange(function(pos) showPosition(pos.x, pos.y, pos.z) end)
  showPosition(posx(), posy(), posz())
end

-- Links row under the editor (vBot/Helper.lua, change 217): "Seguir desde aqui".
-- The route continues at the waypoint nearest to the character (the same choice as after a reload).
CaveBot.Editor.resumeHere = function()
  if type(CaveBot.resyncRoute) ~= "function" then return false end
  local ok, pick = CaveBot.resyncRoute("Seguir desde aqui")
  if not ok or type(pick) ~= "table" then
    warn("CaveBot: no hay un waypoint de esta ruta cerca de ti (" .. tostring(pick or "sin datos") .. ").")
    return false
  end
  -- resyncRoute marks the row before it (an action then advances); from a button the bot goes
  -- straight to the waypoint, so mark the waypoint itself.
  local list = CaveBot.actionList
  local target = list:getChildByIndex(pick.index)
  if target then
    list:focusChild(target)
    list:ensureChildVisible(target)
  end
  if type(CaveBot.wakeRoute) == "function" then CaveBot.wakeRoute() end
  return true
end

-- "Ir a label": the exact row chosen (two labels may share a name), as CaveBot.gotoLabel does.
CaveBot.Editor.jumpToLabel = function(index)
  local list = CaveBot.actionList
  local row = list:getChildByIndex(index)
  if not row or row.action ~= "label" then return false end
  list:focusChild(row)
  list:ensureChildVisible(row)
  local check = CaveBot.Extensions and CaveBot.Extensions.SupplyCheck
  if check and check.reachedLabel then pcall(check.reachedLabel, row.value) end
  if type(CaveBot.wakeRoute) == "function" then CaveBot.wakeRoute() end
  return true
end

-- Menu with the labels of the loaded route, opened on the button.
CaveBot.Editor.labelMenu = function(anchor)
  local labels = {}
  for index, child in ipairs(CaveBot.actionList:getChildren()) do
    local name = child.action == "label" and type(child.value) == "string" and child.value:trim() or ""
    if name ~= "" then labels[#labels + 1] = {index = index, name = name} end
  end
  if #labels == 0 then
    warn("CaveBot: esta ruta no tiene labels.")
    return false
  end
  local menu
  for _, style in ipairs({"HelperSelectorPopupMenu", "PopupMenu"}) do
    local ok, created = pcall(g_ui.createWidget, style)
    if ok and created and type(created.addOption) == "function" then menu = created; break end
  end
  if not menu then
    warn("CaveBot: no se pudo abrir la lista de labels.")
    return false
  end
  for _, entry in ipairs(labels) do
    menu:addOption(entry.index .. ". " .. entry.name, function() CaveBot.Editor.jumpToLabel(entry.index) end)
  end
  local shown = pcall(function()
    local at = anchor and anchor:getPosition()
    menu:display(at and {x = at.x, y = at.y} or nil)
  end)
  if not shown then
    pcall(function() menu:destroy() end)
    return false
  end
  return true
end

CaveBot.Editor.show = function()
  CaveBot.Editor.ui:show()
end


CaveBot.Editor.hide = function()
  CaveBot.Editor.ui:hide()
end

CaveBot.Editor.edit = function(action, value, callback) -- callback = function(action, value)
  local params = CaveBot.Editor.Actions[action]
  if not params then return end
  local newValue=value==nil
  if not value then
    if type(params.value) == 'function' then
      value = params.value()
    elseif type(params.value) == 'string' then
      value = params.value
    end
  end

  if action=='supremecube'and CaveBot.SupremeCube then
    return CaveBot.SupremeCube.edit(value,function(newText)callback(action,newText)end)
  end

  if action=='function' and (newValue or CaveBot.FunctionRules.decode(value))then
    return CaveBot.Editor.editRule(value,function(newText)callback(action,newText)end)
  end
  -- Lua functions: editor with templates and checks (cavebot/function_editor.lua); the
  -- plain text editor below stays as the fallback.
  if action=='function' and CaveBot.Editor.editFunction then
    local ok,window=pcall(CaveBot.Editor.editFunction,value,function(newText)callback(action,newText)end)
    if ok and window then return window end
    if not ok then warn('CaveBot: editor de funciones no disponible ('..tostring(window)..')') end
  end

  if action == "waitstamina" then
    return CaveBot.Editor.editWaitStamina(value, function(newText)
      callback(action, newText)
    end)
  end

  if action=='zonapz'then
    return CaveBot.Editor.editZonePZ(value,function(newText)callback(action,newText)end)
  end

  if action == "sellall" then
    return CaveBot.Editor.editSellAll(value, function(newText)
      callback(action, newText)
    end)
  end

  if action == "setprofile" then
    return CaveBot.Editor.editSetProfile(value, function(newText)
      callback(action, newText)
    end)
  end

  UI.EditorWindow(value, params, function(newText)
    callback(action, newText)
  end)   
end
