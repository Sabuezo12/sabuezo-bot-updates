TargetBot.Creature.edit = function(config, callback)
  config = config or {}
  local editor = UI.createWindow('TargetBotCreatureEditorWindow')
  local fields, values = {}, {}
  local loading = true
  local movement = editor.content.movement.fields
  local pull = editor.content.pull.fields
  local combat = editor.content.combat.fields
  editor.content.movement.title:setText('Movimiento y distancias')
  editor.content.pull.title:setText('Pull / Lure')
  editor.content.combat.title:setText('Combate y loot')
  editor.name:setText(config.name or '')

  local function updatePreview()
    if loading then return end
    if fields.dynamicLure:isOn() and fields.lureMin.scroll:getValue() >= fields.lureMax.scroll:getValue() then
      editor.message:setText('Dynamic Lure: el minimo debe ser menor que el maximo.')
    else
      editor.message:setText('Keep Distance incluye antitrap. Guardar aplica los cambios.')
    end
  end

  local function addNumber(parent, id, title, minimum, maximum, defaultValue, tooltip, suffix)
    local row = UI.createWidget('TargetBotCreatureEditorAmount', parent)
    row:setId(id)
    row:setTooltip(tooltip)
    row.scroll:setTooltip(tooltip)
    -- Apply ranges here only; generic OTUI range limits can overwrite individual controls.
    row.scroll:setRange(minimum, maximum)
    row.scroll:setStep(maximum - minimum > 100 and 10 or 1)
    row.scroll:setValue(config[id] == nil and defaultValue or config[id])
    local function refresh()
      row.caption:setText(title .. ': ' .. row.scroll:getValue() .. (suffix or ''))
      updatePreview()
    end
    row.scroll.onValueChange = refresh
    fields[id] = row
    values[#values + 1] = {id, function() return row.scroll:getValue() end}
    refresh()
  end

  local function addOption(parent, id, title, defaultValue, tooltip)
    local button = UI.createWidget('TargetBotCreatureEditorOption', parent)
    button:setId(id)
    button:setText(title)
    button:setTooltip(tooltip)
    button:setOn(config[id] == nil and defaultValue or config[id] == true)
    button.onClick = function()
      button:setOn(not button:isOn())
      updatePreview()
    end
    fields[id] = button
    values[#values + 1] = {id, function() return button:isOn() end}
  end

  addNumber(movement, 'priority', 'Prioridad', 0, 20, 1, 'Prioridad de este objetivo frente a los demas.')
  addNumber(movement, 'danger', 'Peligro', 0, 10, 1, 'Valor de peligro asignado a esta criatura.')
  addNumber(movement, 'maxDistance', 'Max distance', 1, 10, 10, 'Distancia maxima para considerar este objetivo.', ' SQM')
  addOption(movement, 'chase', 'Chase', true, 'Acercarse al objetivo cuando se usa el movimiento clasico.')
  addOption(movement, 'keepDistance', 'Keep Distance + Antitrap', false, 'Mantener distancia y buscar una salida antes de quedar rodeado. Este boton activa ambas funciones.')
  addNumber(movement, 'keepDistanceRange', 'Distancia', 1, 5, 1, 'Distancia deseada respecto al objetivo. El antitrap prioriza una salida libre.', ' SQM')
  addOption(movement, 'anchor', 'Anchoring', false, 'Conservar el mismo centro durante el combate. Se libera al reunir la siguiente pull.')
  addNumber(movement, 'anchorRange', 'Radio', 1, 10, 3, 'El antitrap puede salir del radio. Vuelve al mismo centro cuando hay entrada segura.', ' SQM')
  addOption(movement, 'rePosition', 'rePosition to better tile', false, 'Buscar una casilla con mas espacio. El movimiento clasico no lo combina con Keep Distance.')
  addNumber(movement, 'rePositionAmount', 'Min tiles to rePosition', 0, 7, 5, 'Umbral de espacio alrededor para la opcion rePosition.')
  addOption(movement, 'faceMonster', 'Face monsters', false, 'Orientarse hacia el objetivo.')
  addOption(movement, 'avoidAttacks', 'Avoid wave attacks', false, 'Buscar posiciones laterales para evitar ataques en linea.')

  addOption(pull, 'dynamicLure', 'Dynamic Lure', false, 'Usar los limites minimo y maximo para reunir monstruos y retomar CaveBot.')
  addNumber(pull, 'lureMin', 'Minimo', 0, 29, 1, 'Cantidad de monstruos para retomar el lure clasico.')
  addNumber(pull, 'lureMax', 'Maximo', 1, 30, 3, 'Cantidad de monstruos para detener el lure clasico.')
  addOption(pull, 'dynamicLureDelay', 'Dynamic lure delay', false, 'Aplicar el delay al movimiento clasico de Dynamic Lure.')
  addNumber(pull, 'lureDelay', 'Pausa', 100, 1000, 250, 'Pausa entre pasos del Dynamic Lure clasico.', ' ms')
  addNumber(pull, 'delayFrom', 'Desde', 1, 29, 2, 'Cantidad desde la que se aplica el delay clasico.', ' monstruos')
  addOption(pull, 'lure', 'Lure', false, 'Reunir monstruos con el lure clasico.')
  addNumber(pull, 'lureCount', 'Classic Lure', 0, 5, 1, 'Objetivo de monstruos del lure clasico.')
  addOption(pull, 'lureCavebot', 'Lure using CaveBot', false, 'Permitir que CaveBot reuna los monstruos.')
  addOption(pull, 'closeLure', 'Close Pulling Monsters', false, 'Dar paso al CaveBot al alcanzar Close Pull Until.')
  addNumber(pull, 'closeLureAmount', 'Close Pull Until', 0, 8, 3, 'Cantidad de monstruos a 1 SQM que permite continuar CaveBot con Close Pulling Monsters.')

  addOption(combat, 'dontLoot', "Don't loot", false, 'Excluir del loot los cuerpos de esta criatura.')
  addOption(combat, 'diamondArrows', 'D-Arrows priority', false, 'Conservar la prioridad especial de Diamond Arrows.')
  addOption(combat, 'burstArrows', 'Burst Arrows priority', false, 'Conservar la prioridad especial de Burst Arrows.')
  addOption(combat, 'rpSafe', 'RP PVP SAFE - Arrows', false, 'Mantener la opcion de seguridad PvP para flechas.')
  addOption(combat, 'antitrapBugMap', 'BugMap si no hay salida', false, 'Con Keep Distance activo, intentar usar una casilla libre cuando ya no queda una salida caminando. Solo como emergencia.')
  addNumber(combat, 'antitrapBugMapDelay', 'Espera sin salida', 300, 3000, 600, 'Tiempo sin salida antes de intentar BugMap. Los intentos se espacian como minimo 800 ms.', ' ms')

  editor.footer.help.onClick = function()
    editor.message:setText('Keep Distance activa el antitrap. Dynamic Lure conserva sus limites min/max. Verde: activo; rojo: apagado.')
  end
  editor.footer.cancel.onClick = function() editor:destroy() end
  editor.onEscape = editor.footer.cancel.onClick
  editor.footer.ok.onClick = function()
    -- Preserve custom spells and any other settings that this editor does not expose.
    local newConfig = {}
    for key, value in pairs(config) do newConfig[key] = value end
    newConfig.name = editor.name:getText()
    for _, value in ipairs(values) do newConfig[value[1]] = value[2]() end
    if not newConfig.name:find('%S') then
      editor.message:setText('Escribe el nombre de un objetivo.')
      return
    end
    if newConfig.dynamicLure and newConfig.lureMin >= newConfig.lureMax then
      editor.message:setText('Dynamic Lure: el minimo debe ser menor que el maximo.')
      return
    end
    newConfig.regex = ''
    for part in string.gmatch(newConfig.name, '[^,]+') do
      if newConfig.regex:len() > 0 then newConfig.regex = newConfig.regex .. '|' end
      newConfig.regex = newConfig.regex .. '^' .. part:trim():lower():gsub('%*', '.*'):gsub('%?', '.?') .. '$'
    end
    editor:destroy()
    callback(newConfig)
  end
  loading = false
  updatePreview()
end
