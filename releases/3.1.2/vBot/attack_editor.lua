-- Transactional front end. The existing AttackBot row list remains the runtime
-- model; drafts never change the active rotation until the user applies them.
-- Uses only APIs available in the bot sandbox (no next/unpack, native spinbox,
-- timers that rebuild widgets, or anchors between unrelated parents).
-- Zero-based clientId values for the native spell-icons-32x32 strip.
-- Fallback only: live client metadata and its own helpers take priority.
local standardSpellIcons = {
  ['exana amp res']=138,
  ['exeta amp res']=111,
  ['exeta res']=96,
  ['utori san']=52,
  ['utori kor']=56,
  ['exevo infir flam hur']=131,
  ['exori infir vis']=132,
  ['exori min flam']=126,
  ['exevo infir frigo hur']=135,
  ['exori infir tera']=136,
  ['exori moe ico']=16,

  ['exevo flam hur']=43,
  ['exevo frigo hur']=44,
  ['exevo gran flam hur']=102,
  ['exevo gran frigo hur']=45,
  ['exevo gran mas flam']=48,
  ['exevo gran mas frigo']=49,
  ['exevo gran mas tera']=47,
  ['exevo gran mas vis']=51,
  ['exevo gran vis lux']=41,
  ['exevo mas san']=39,
  ['exevo max mort']=157,
  ['exevo tempo mas san']=155,
  ['exevo tera hur']=46,
  ['exevo ulus frigo']=153,
  ['exevo ulus tera']=154,
  ['exevo vis hur']=42,
  ['exevo vis lux']=40,
  ['exori']=20,
  ['exori amp kor']=152,
  ['exori amp pug']=178,
  ['exori amp vis']=50,
  ['exori con']=17,
  ['exori flam']=25,
  ['exori frigo']=31,
  ['exori gran']=21,
  ['exori gran con']=58,
  ['exori gran flam']=26,
  ['exori gran frigo']=32,
  ['exori gran ico']=23,
  ['exori gran mas nia']=183,
  ['exori gran mas pug']=177,
  ['exori gran nia']=181,
  ['exori gran pug']=174,
  ['exori gran tera']=35,
  ['exori gran vis']=29,
  ['exori hur']=18,
  ['exori ico']=22,
  ['exori infir nia']=179,
  ['exori infir pug']=172,
  ['exori mas']=24,
  ['exori mas nia']=182,
  ['exori mas pug']=175,
  ['exori max flam']=27,
  ['exori max frigo']=33,
  ['exori max tera']=36,
  ['exori max vis']=30,
  ['exori med pug']=176,
  ['exori min']=19,
  ['exori mort']=37,
  ['exori nia']=180,
  ['exori pug']=173,
  ['exori san']=38,
  ['exori tera']=34,
  ['exori vis']=28,
  ['utamo tio']=169,
  ['utevo grav san']=158,
  ['utori flam']=54,
  ['utori mort']=53,
  ['utori pox']=57,
  ['utori vis']=55,
}

-- Original spell images for attacks missing from the client's standard strip.
-- Keep them local to the selected bot; never guess indexes in a native atlas.
local supplementalSpellIcons = {
  ['exori ico scu']={name='shieldbash',width=38,height=38},
  ['exori infir min']={name='lesserfrontsweep',width=38,height=38},
  ['exori infir con']={name='lesseretherealspear',width=38,height=38},

  ['exevo fur frigo']='forkedglacier',
  ['exevo fur tera']='forkedthorns',
  ['exevo mort ora']='deathecho',
  ['exori dir moe']='etherealbarrage',
  ['exori dir san']='divinebarrage',
  ['exori scu']='shieldslam',
  ['exori mas amp pug']='thousandfistblow',
  ['exori infir amp pug']='lessermysticrepulse',
}

dofile('/vBot/attack_spell_preview.lua')
AttackBotEditor = {}
function AttackBotEditor.create(ctx)
  local C, R = ctx.catalog, AttackRotation
  local win = UI.createWindow('AttackStudioWindow')
  local picker = UI.createWindow('AttackStudioPicker')
  local options = win.rotation.details
  local confirm = UI.createWindow('AttackStudioConfirm')
  win:hide(); picker:hide(); confirm:hide()
  local left, edit = win.rotation.listBox, win.rotation.editor
  local draft, profile, selected, dirty, loading, opened, lastStatus
  local visibleRows, mainNumbers, optionNumbers = {}, {}, {}
  local profileLabels={}
  local pickerChoices, pickerSelected, optionDraft, newOption, optionTarget, optionOwnerList
  local renderList, renderEditor, refreshSettings, loadOptions, commitOptions, requestClose
  local studio = {}

  local function text(widget, value) widget:setText(tostring(value or '')) end
  local function reveal(widget) widget:show(); widget:raise(); widget:focus() end
  local function notify(message, errorState)
    text(win.status, message)
    win.status:setColor(errorState and '#f0a18f' or '#a4b3af')
  end
  local function mark()
    if loading then return end
    dirty = true
    text(win.pending, 'Cambios sin aplicar')
    notify('Revisa tus ajustes y pulsa Aplicar cambios.')
  end
  local function name(entry)
    local spec = R and R.find(entry)
    local data = C.find(entry.spell)
    if spec and spec.name and spec.name ~= '' then return spec.name end
    if data then return data.name end
    if (entry.itemId or 0) > 100 then return 'Runa ' .. entry.itemId end
    return entry.spell and entry.spell ~= '' and entry.spell or 'Spell personalizado'
  end
  local function singleTarget(entry)
    return R and R.isSingleTarget and R.isSingleTarget(entry) or false
  end
  local function countHelp(entry)
    if singleTarget(entry) then
      return 'Cuenta los monstruos vivos en pantalla, del mismo piso y sin invocaciones. Los filtros de nombre y vida se aplican al objetivo. Sin "esa cantidad o mas": exactamente esa cantidad; activado: esa cantidad o mas.'
    end
    return 'Cuenta los monstruos alcanzados dentro del area real del spell. Sin "esa cantidad o mas": exactamente esa cantidad; activado: esa cantidad o mas.'
  end
  local function seconds(value)
    return string.format('%.3f', (tonumber(value) or 0)/1000):gsub('0+$', ''):gsub('%.$', '')
  end
  local function entryKey(entry)
    if (entry.itemId or 0) > 100 then return 'item:' .. entry.itemId end
    return C.normalize(entry.spell)
  end
  local function describe(entry)
    entry.description = '[' .. name(entry) .. '] ' ..
      ((entry.itemId or 0)>100 and ('rune ' .. entry.itemId) or entry.spell) ..
      ' (' .. entry.count .. (entry.orMore and '+' or '') .. ')'
  end
  local iconCache, imageCache = {}, {}
  local function helperCall(owner, method, ...)
    if type(owner) ~= 'table' or type(owner[method]) ~= 'function' then return nil end
    local ok,value,profile=pcall(owner[method],...)
    if ok then return value,profile end
  end
  local function imageExists(source)
    if type(source) ~= 'string' or source == '' then return false end
    if imageCache[source] ~= nil then return imageCache[source] end
    local resources=g_resources
    if not resources or type(resources.fileExists) ~= 'function' then return true end
    local ok,exists=pcall(resources.fileExists,source)
    if not ok or not exists then ok,exists=pcall(resources.fileExists,source..'.png') end
    imageCache[source]=ok and exists == true
    return imageCache[source]
  end
  local function nativeAppearance(lib,info,atlas)
    if type(info) ~= 'table' then return nil end
    local settings=lib.SpelllistSettings and lib.SpelllistSettings[atlas]
    -- Modern clients use a ZERO-based clientId and a horizontal strip. They
    -- have no SpellIcons table. Let native helpers supply custom atlas clips.
    local index=tonumber(info.clientId)
    if index and index >= 0 and index == math.floor(index) then
      local source=helperCall(lib.Spells,'getIconFileByProfile',atlas) or
        (settings and settings.iconFile) or '/images/game/spells/spell-icons-32x32'
      if imageExists(source) then
        local width=settings and settings.iconSize and settings.iconSize.width or 32
        local height=settings and settings.iconSize and settings.iconSize.height or 32
        return {source=source,clip=helperCall(lib.Spells,'getImageClip',index,atlas) or
          (index*width .. ' 0 ' .. width .. ' ' .. height)}
      end
    end
    -- Older OTC clients use named icons / one-based indexes in a 12-column
    -- sheet. Keep that compatibility without requiring it for modern clients.
    if settings and settings.iconSize then
      local mapping=lib.SpellIcons and lib.SpellIcons[info.icon]
      local id=tonumber(info.icon) or (type(mapping)=='table' and tonumber(mapping[1]))
      if id and id >= 1 and imageExists(settings.iconFile) then
        local width,height=settings.iconSize.width,settings.iconSize.height
        return {source=settings.iconFile,clip=helperCall(lib.Spells,'getImageClip',id,atlas) or
          (((id-1)%12)*width .. ' ' .. math.floor((id-1)/12)*height .. ' ' .. width .. ' ' .. height)}
      end
    end
  end
  local function spellAppearance(words)
    words=C.normalize(words)
    if iconCache[words] ~= nil then return iconCache[words] or nil end
    local lib=modules and modules.gamelib or {}
    local preferred=helperCall(modules and modules.game_tibia_spelllist,'getSpelllistProfile') or
      helperCall(modules and modules.game_spelllist,'getSpelllistProfile') or 'Default'
    local nativeInfo,nativeProfile=helperCall(lib.Spells,'getSpellByWords',words)
    local atlas=nativeProfile or helperCall(lib.Spells,'getSpellProfileByWords',words) or preferred
    local learned=helperCall({get=getSpellData},'get',words)
    local appearance=nativeAppearance(lib,learned,atlas) or nativeAppearance(lib,nativeInfo,atlas) or
      nativeAppearance(lib,helperCall(lib.Spells,'getSpellDataByWords',words),atlas)
    -- Learned spell data may contain cooldowns without any visual fields, or
    -- an empty legacy icon. Search complete spell-list data in that case.
    local profiles=lib.SpellInfo or {}
    local function scan(profile)
      for _,info in pairs(profiles[profile] or {}) do
        if type(info)=='table' and C.normalize(info.words)==words then
          local result=nativeAppearance(lib,info,profile)
          if result then return result end
        end
      end
    end
    appearance=appearance or scan(atlas)
    if not appearance and preferred~=atlas then appearance=scan(preferred) end
    if not appearance then
      for profile in pairs(profiles) do
        if profile~=atlas and profile~=preferred then
          appearance=scan(profile)
          if appearance then break end
        end
      end
    end
    -- Common spells remain identifiable if a server publishes incomplete
    -- SpellInfo. This uses the real atlas confirmed present in this client.
    local standard=standardSpellIcons[words]
    if not appearance and standard and imageExists('/images/game/spells/spell-icons-32x32') then
      appearance={source='/images/game/spells/spell-icons-32x32',clip=standard*32 .. ' 0 32 32'}
    end
    local supplemental=supplementalSpellIcons[words]
    if not appearance and supplemental then
      local directory=type(configDir)=='string' and configDir or '/bot/Sabuezo2'
      local source=directory..'/vBot/attack_spell_icons/'..(type(supplemental)=='table' and supplemental.name or supplemental)..'.png'
      if imageExists(source) then
        appearance={source=source,clip=type(supplemental)=='table' and ('0 0 '..supplemental.width..' '..supplemental.height) or '0 0 38 38'}
      end
    end
    iconCache[words]=appearance or false
    return appearance
  end
  local function setIcon(icon,item,entry)
    local isItem=(entry.itemId or 0)>100
    item:setVisible(isItem);icon:setVisible(not isItem)
    if isItem then item:setItemId(entry.itemId);return end
    local appearance=spellAppearance(entry.spell)
    icon:setText(appearance and '' or '?')
    icon:setImageSource(appearance and appearance.source or '')
    if appearance then icon:setImageClip(appearance.clip) end
  end
  local function bindNumber(widget, min, max, step, change, collection)
    local state = {widget=widget, value=min, valid=true, writing=false}
    collection[#collection+1] = state
    function state:set(value)
      self.value = math.max(min, math.min(max, tonumber(value) or min))
      self.valid, self.writing = true, true
      text(widget.input, self.value)
      widget.input:setColor('#dce5e2')
      self.writing = false
    end
    local function write(raw)
      if state.writing then return end
      local value = tonumber(raw)
      state.valid = value ~= nil and value == value and value >= min and value <= max and
        (step < 1 or value == math.floor(value))
      widget.input:setColor(state.valid and '#dce5e2' or '#f0a18f')
      if state.valid then
        state.value = value
        change(value)
      end
    end
    widget.input.onTextChange = function(_, value) write(value) end
    local function shift(amount)
      local value = math.max(min, math.min(max, state.value + amount))
      value = math.floor(value*1000+0.5)/1000
      state:set(value); change(value)
    end
    widget.minus.onClick = function() shift(-step) end
    widget.plus.onClick = function() shift(step) end
    local help=(widget:getTooltip() or '') .. '\n' .. min .. ' a ' .. max .. '. Puedes escribir el valor directamente.'
    widget.input:setTooltip(help)
    widget.minus:setTooltip(help .. '\nReduce el valor en ' .. step .. '.')
    widget.plus:setTooltip(help .. '\nAumenta el valor en ' .. step .. '.')
    return state
  end
  local function validNumbers(collection)
    for _, control in ipairs(collection) do
      if not control.valid then
        notify('Corrige el numero marcado en rojo antes de continuar.', true)
        control.widget.input:focus()
        return false
      end
    end
    return true
  end
  local function updateRows()
    for _, row in ipairs(visibleRows) do
      local entry = row.entry
      text(row.title, name(entry))
      text(row.words, (entry.itemId or 0)>100 and ('ID ' .. entry.itemId) or entry.spell)
      text(row.minimum, entry.count .. (entry.orMore and '+' or ''))
      row.minimum:setTooltip(countHelp(entry))
      text(row.cooldown, seconds(entry.cooldown) .. 's')
      row.enabled:setChecked(entry.enabled == true)
      row:setOn(entry == selected)
      row:setTooltip((entry.tooltip or name(entry)) .. '\n' .. (entry.spell or '') ..
        '\nSelecciona para editar. CD mostrado: tiempo de respaldo.')
    end
    local count, enabled, index = #draft.attackTable, 0
    for i, entry in ipairs(draft.attackTable) do
      if entry.enabled then enabled=enabled+1 end
      if entry == selected then index=i end
    end
    text(left.count, enabled .. '/' .. count .. ' activos')
    left.up:setEnabled(index ~= nil and index > 1)
    left.down:setEnabled(index ~= nil and index < count)
    left.remove:setEnabled(selected ~= nil)
  end
  renderList = function()
    left.entries:destroyChildren(); visibleRows = {}
    local filter = C.normalize(left.search:getText())
    for _, entry in ipairs(draft.attackTable) do
      if filter == '' or C.normalize(name(entry) .. ' ' .. (entry.spell or '') .. ' ' .. (entry.itemId or '')):find(filter,1,true) then
        local row = UI.createWidget('StudioEntry', left.entries)
        row.entry = entry; visibleRows[#visibleRows+1] = row
        setIcon(row.icon, row.item, entry)
        row.onClick = function()
          if not validNumbers(mainNumbers) or not commitOptions() then return end
          selected = entry; renderEditor(); updateRows()
        end
        row.enabled.onClick = function()
          entry.enabled = not entry.enabled
          mark(); updateRows()
          if entry == selected then edit.enabled:setChecked(entry.enabled) end
        end
      end
    end
    updateRows()
  end
  local countControl = bindNumber(edit.minimum, 1, 100, 1, function(value)
    if loading or not selected then return end
    selected.count=value; describe(selected); mark(); updateRows()
  end, mainNumbers)
  local manaControl = bindNumber(edit.mana, 0, 100, 1, function(value)
    if loading or not selected then return end
    selected.mana=value; mark()
  end, mainNumbers)
  local minControl = bindNumber(edit.minHp, 0, 100, 1, function(value)
    if loading or not selected then return end
    selected.minHp=value; mark()
  end, mainNumbers)
  local maxControl = bindNumber(edit.maxHp, 0, 100, 1, function(value)
    if loading or not selected then return end
    selected.maxHp=value; mark()
  end, mainNumbers)
  local cdControl = bindNumber(edit.cooldown, 0, 3600, 0.1, function(value)
    if loading or not selected then return end
    selected.cooldown=math.floor(value*1000+0.5); mark(); updateRows()
  end, mainNumbers)
  renderEditor = function()
    local wasLoading = loading; loading = true
    edit.enabled:setEnabled(selected ~= nil)
    edit.optionsButton:hide()
    for _, control in ipairs(mainNumbers) do control.widget:setEnabled(selected ~= nil) end
    edit.orMore:setEnabled(selected ~= nil)
    text(edit.title, selected and name(selected) or 'Selecciona un spell')
    text(edit.words, selected and ((selected.itemId or 0)>100 and ('Runa ID ' .. selected.itemId) or selected.spell) or '')
    if selected then setIcon(edit.icon, edit.item, selected) else edit.icon:hide(); edit.item:hide() end
    edit.enabled:setChecked(selected and selected.enabled == true or false)
    edit.orMore:setChecked(selected and selected.orMore == true or false)
    text(edit.minimumLabel, singleTarget(selected) and 'Monstruos en pantalla' or 'Monstruos alcanzados')
    edit.minimumLabel:setTooltip(countHelp(selected))
    edit.minimum:setTooltip(countHelp(selected))
    edit.minimum.input:setTooltip(countHelp(selected) .. '\n1 a 100. Puedes escribir el valor directamente.')
    edit.minimum.minus:setTooltip(countHelp(selected) .. '\nReduce la cantidad en 1.')
    edit.minimum.plus:setTooltip(countHelp(selected) .. '\nAumenta la cantidad en 1.')
    edit.orMore:setTooltip(countHelp(selected))
    countControl:set(selected and selected.count or 1)
    manaControl:set(selected and selected.mana or 0)
    minControl:set(selected and selected.minHp or 0)
    maxControl:set(selected and selected.maxHp or 100)
    cdControl:set(selected and (selected.cooldown or 0)/1000 or 0)
    edit.title:setTooltip(selected and (selected.tooltip or name(selected)) or '')
    loadOptions(selected,false)
    loading = wasLoading
  end
  edit.enabled.onClick = function()
    if not selected then return end
    selected.enabled=not selected.enabled; edit.enabled:setChecked(selected.enabled); mark(); updateRows()
  end
  edit.orMore.onClick = function()
    if not selected then return end
    selected.orMore=not selected.orMore; edit.orMore:setChecked(selected.orMore); describe(selected); mark(); updateRows()
  end
  left.search.onTextChange = function() if draft and not loading then renderList() end end
  local function move(amount)
    if not selected then return end
    for i, entry in ipairs(draft.attackTable) do
      if entry == selected and i+amount >= 1 and i+amount <= #draft.attackTable then
        table.remove(draft.attackTable,i); table.insert(draft.attackTable,i+amount,entry)
        mark(); renderList(); return
      end
    end
  end
  left.up.onClick = function() move(-1) end
  left.down.onClick = function() move(1) end
  left.remove.onClick = function()
    if not selected then return end
    for i, entry in ipairs(draft.attackTable) do
      if entry == selected then
        table.remove(draft.attackTable,i); selected=draft.attackTable[math.min(i,#draft.attackTable)]
        mark(); renderEditor(); renderList(); return
      end
    end
  end
  local function setTab(tab)
    win.rotation:setVisible(tab == 'rotation')
    win.safety:setVisible(tab == 'safety')
    win.advanced:setVisible(tab == 'advanced')
    win.rotationTab:setOn(tab == 'rotation')
    win.safetyTab:setOn(tab == 'safety')
    win.advancedTab:setOn(tab == 'advanced')
    win.rotationTab.indicator:setVisible(tab == 'rotation')
    win.safetyTab.indicator:setVisible(tab == 'safety')
    win.advancedTab.indicator:setVisible(tab == 'advanced')
  end
  win.rotationTab.onClick = function() setTab('rotation') end
  win.safetyTab.onClick = function() setTab('safety') end
  win.advancedTab.onClick = function() setTab('advanced') end
  local checks = {}
  local function check(widget, key)
    checks[#checks+1] = {widget=widget,key=key}
    widget.onClick = function()
      if not draft then return end
      draft[key]=not draft[key]
      if key == 'ClientCooldowns' and draft[key] then draft.Cooldown=true end
      if key == 'Cooldown' and not draft[key] then draft.ClientCooldowns=false end
      mark(); refreshSettings()
    end
  end
  check(win.pvpSafe, 'PvpSafe'); check(win.safety.pvpSafe, 'PvpSafe')
  check(win.safety.blacklist, 'BlackListSafe'); check(win.safety.kills, 'Kills')
  check(win.safety.training, 'Training')
  check(win.advanced.client, 'ClientCooldowns'); check(win.advanced.cooldown, 'Cooldown')
  win.advanced.client:setTooltip('Usa los tiempos recibidos del cliente. Si no estan disponibles, usa el respaldo configurado en cada spell.')
  win.advanced.cooldown:setTooltip('Control general de los tiempos de espera. Al desactivarlo tambien se desactivan los cooldowns del cliente.')
  check(win.advanced.requirements, 'ignoreMana'); check(win.advanced.rotate, 'Rotate')
  win.advanced.rotate:setTooltip('Prepara la posicion y el giro del proximo wave o beam durante el cooldown. Al activarlo y aplicar, enciende Face Monster en los objetivos del perfil activo de TargetBot. Respeta Keep Distance, Chase, Anchoring y la prioridad del antitrap.')
  check(win.advanced.visible, 'Visible'); check(win.advanced.oldSchool, 'OldSchool')
  local safetyNumbers = {}
  local rangeControl = bindNumber(win.safety.range, 1, 10, 1, function(value)
    if not loading then draft.AntiRsRange=value; mark() end
  end, safetyNumbers)
  local killsControl = bindNumber(win.safety.killsAmount, 1, 10, 1, function(value)
    if not loading then draft.KillsAmount=value; mark() end
  end, safetyNumbers)
  local function orderedOnly()
    return draft.pvpMode or not (R and R.supported[draft.selectedVocation])
  end
  local function selectionHelp()
    if orderedOnly() then return 'PvP / Personalizado: prioridad de arriba abajo.' end
    if draft.RotationMode=='priority' then return 'Prioridad: de arriba abajo. Si no esta listo, prueba el siguiente.' end
    return 'Automatica: mas monstruos entre spells listos. Dano para desempatar.'
  end
  refreshSettings = function()
    local wasLoading=loading; loading=true
    for _, item in ipairs(checks) do item.widget:setChecked(draft[item.key] == true) end
    win.mode:setCurrentOption(draft.pvpMode and 'PvP' or 'PvE')
    left.selectionMode:setCurrentOption((orderedOnly() or draft.RotationMode=='priority') and 'Prioridad por orden' or 'Automatica')
    left.selectionMode:setEnabled(not orderedOnly())
    left.selectionMode:setTooltip(selectionHelp())
    text(win.advanced.help,selectionHelp())
    text(win.advanced.name, draft.name)
    rangeControl:set(draft.AntiRsRange or 5); killsControl:set(draft.KillsAmount or 1)
    edit.cooldownHelp:setText(draft.ClientCooldowns and
      'Prioridad al cooldown del cliente.' or 'Usa el cooldown de respaldo.')
    win.advanced.restore:setEnabled(R and R.supported[draft.selectedVocation] == true or false)
    loading=wasLoading
  end
  win.advanced.name.onTextChange = function(_, value)
    if loading or not draft then return end
    draft.name=value; mark()
  end
  win.mode:addOption('PvE'); win.mode:addOption('PvP')
  win.mode.onOptionChange = function()
    if loading or not draft then return end
    draft.pvpMode=win.mode:getCurrentOption().text == 'PvP'; mark(); refreshSettings()
  end
  left.selectionMode:addOption('Automatica')
  left.selectionMode:addOption('Prioridad por orden')
  left.selectionMode.onOptionChange = function()
    if loading or not draft or orderedOnly() then return end
    draft.RotationMode=left.selectionMode:getCurrentOption().text=='Prioridad por orden' and 'priority' or 'automatic'
    mark(); refreshSettings(); notify(selectionHelp())
  end
  for _, vocation in ipairs(C.profileVocations) do win.vocation:addOption(vocation) end
  win.vocation.onOptionChange = function()
    if loading or not draft then return end
    local vocation=win.vocation:getCurrentOption().text
    if vocation == draft.selectedVocation then return end
    if not validNumbers(mainNumbers) or not validNumbers(safetyNumbers) or not commitOptions() then
      loading=true; win.vocation:setCurrentOption(draft.selectedVocation); loading=false; return
    end
    if R then R.selectVocation(draft,vocation) else C.bindVocation(draft,vocation) end
    picker:hide(); optionDraft=nil
    selected=draft.attackTable[1]
    loading=true; text(left.search,''); loading=false
    mark(); refreshSettings(); renderEditor(); renderList()
  end
  local function refreshProfiles()
    local wasLoading=loading; loading=true
    win.profile:clearOptions()
    for i=1,5 do
      profileLabels[i]=i .. ' - ' .. (ctx.getProfileName and ctx.getProfileName(i) or ('Perfil ' .. i))
      win.profile:addOption(profileLabels[i])
    end
    if profile then win.profile:setCurrentOption(profileLabels[profile]) end
    loading=wasLoading
  end
  refreshProfiles()
  local function confirmAction(message, acceptText, accept, discard)
    text(confirm.message,message); text(confirm.accept,acceptText)
    confirm.discard:setVisible(discard ~= nil)
    confirm.accept.onClick=function() if accept() ~= false then confirm:hide() end end
    confirm.discard.onClick=function() confirm:hide(); if discard then discard() end end
    confirm.cancel.onClick=function() confirm:hide() end
    confirm.onEscape=function() confirm:hide(); return true end
    reveal(confirm)
  end
  function studio.apply()
    if not draft or not validNumbers(mainNumbers) or not validNumbers(safetyNumbers) then return false end
    if ctx.getProfile() ~= profile then
      notify('El perfil activo cambio. Vuelve al perfil ' .. profile .. ' para aplicar esta edicion.',true); return false
    end
    if C.normalize(draft.name) == '' then notify('Escribe un nombre para este perfil.',true); return false end
    if not commitOptions() then return false end
    draft.attacksByVocation[draft.selectedVocation]=draft.attackTable
    for _, entries in pairs(draft.attacksByVocation) do
      for _, entry in ipairs(entries) do
        if (entry.minHp or 0) > (entry.maxHp or 100) then
          notify('La vida minima no puede superar la maxima: ' .. name(entry),true); return false
        end
      end
    end
    if R then R.saveVocationSettings(draft) end
    local ok, message=ctx.apply(C.copy(draft),profile)
    if not ok then notify(message or 'No se pudieron aplicar los cambios.',true); return false end
    dirty=false; text(win.pending,'Guardado')
    refreshProfiles()
    notify('Cambios aplicados a ' .. draft.name .. ' / ' .. draft.selectedVocation .. '.')
    return true
  end
  win.apply.onClick=studio.apply
  local function hideAll()
    opened=false; win:hide(); picker:hide(); confirm:hide()
    draft=nil; selected=nil; optionDraft=nil
  end
  requestClose=function()
    if not dirty then hideAll(); return end
    confirmAction('Hay cambios sin aplicar. Puedes guardarlos antes de cerrar o descartarlos.', 'Aplicar y cerrar',
      function() if studio.apply() then hideAll() else return false end end,hideAll)
  end
  win.closeButton.onClick=requestClose
  win.onEscape=function() requestClose(); return true end
  win.onClose=win.onEscape
  local function loadDraft()
    loading=true; lastStatus=nil; profile=ctx.getProfile(); draft=C.copy(ctx.getSettings()); C.bindVocation(draft)
    dirty=false; selected=draft.attackTable[1]
    text(left.search,''); win.vocation:setCurrentOption(draft.selectedVocation)
    refreshProfiles(); text(win.pending,'')
    loading=false
    refreshSettings(); renderEditor(); renderList()
    notify(selectionHelp())
  end
  function studio.requestProfile(n)
    n=tonumber(n)
    if not n or n < 1 or n > 5 or n ~= math.floor(n) then return end
    if not opened then ctx.switchProfile(n); return end
    if n == profile and ctx.getProfile() == profile then return end
    local function switch()
      ctx.switchProfile(n); picker:hide(); loadDraft()
    end
    loading=true; win.profile:setCurrentOption(profileLabels[profile]); loading=false
    if n == profile then ctx.switchProfile(n); return end
    if dirty then
      confirmAction('Aplica o descarta la edicion actual antes de cambiar de perfil.','Aplicar y cambiar',
        function() if studio.apply() then switch() else return false end end,switch)
    else switch() end
  end
  win.profile.onOptionChange=function()
    if loading then return end
    local chosen=win.profile:getCurrentOption().text
    for i,label in ipairs(profileLabels) do if label == chosen then studio.requestProfile(i); return end end
  end
  win.enabled.onClick=function()
    if ctx.getProfile() ~= profile then notify('Vuelve al perfil que estas editando para cambiar su estado.',true); return end
    if AttackBot.isOn() then AttackBot.setOff() else AttackBot.setOn() end
    draft.enabled=AttackBot.isOn(); studio.sync()
  end
  function studio.sync()
    if not opened then return end
    local matching=ctx.getProfile() == profile
    local enabled=matching and AttackBot.isOn()
    local status=not matching and 'Otro perfil activo' or
      (enabled and (AttackBot.isPaused() and 'En pausa' or 'Activado') or 'Desactivado')
    if lastStatus ~= status then
      win.enabled:setOn(enabled == true); text(win.enabled,not matching and "--" or enabled and "ON" or "OFF"); win.enabled:setTooltip(status .. '\nActiva o desactiva AttackBot inmediatamente. Los demas ajustes se guardan con Aplicar cambios.'); lastStatus=status
      if not matching then notify('Perfil activo: ' .. ctx.getProfile() .. '. Editando el perfil ' .. profile .. '.',true) end
    end
    -- On/off belongs to the running bot. Applying other edits must not undo an
    -- external pause/toggle made while this window was open.
    if matching then draft.enabled=AttackBot.isOn() end
  end
  function studio.show()
    if not opened then
      -- A later login can publish spell metadata that was absent previously.
      iconCache,imageCache={},{}
      loadDraft(); opened=true; setTab('rotation')
    end
    studio.sync(); reveal(win)
  end

  -- Spell details share the rotation draft. Switching rows validates and
  -- stores the current fields in that draft; only studio.apply touches runtime.
  local opt={}
  local previewDirection=0
  local refreshPreview
  local optionDirty=false
  local function changedOptions()
    if loading or not optionDraft then return end
    optionDirty=true; mark()
    if refreshPreview then refreshPreview() end
  end
  for _, spec in ipairs({{'itemId',0,65535,1},{'range',0,10,1},{'targets',0,20,1},
    {'jump',0,10,1},{'harmony',0,5,1},{'secondary',0,3600,0.1}}) do
    local key=spec[1]
    opt[key]=bindNumber(options[key],spec[2],spec[3],spec[4],function(value)
      if optionDraft and not loading then optionDraft[key]=value; changedOptions() end
    end,optionNumbers)
  end
  local function patternCategory(category)
    return category == 4 and 3 or category == 5 and 4 or category == 6 and 5 or category
  end
  local categoryNames={'Spell dirigido','Runa de area','Runa dirigida','Soporte / buff','Spell de area','Spell moderno / cadena'}
  for _, categoryName in ipairs(categoryNames) do options.category:addOption(categoryName) end
  local function fillPatterns()
    options.pattern:clearOptions()
    local group=ctx.patterns[patternCategory(optionDraft.category)]
    for _, value in ipairs(group) do options.pattern:addOption(value) end
    options.pattern:setCurrentOption(group[optionDraft.pattern] or group[1])
  end
  options.words.onTextChange=changedOptions
  options.names.onTextChange=changedOptions
  options.category.onOptionChange=function()
    if loading or not optionDraft then return end
    for i, value in ipairs(categoryNames) do
      if value == options.category:getCurrentOption().text then optionDraft.category=i end
    end
    optionDraft.pattern=1
    loading=true; fillPatterns(); loading=false; changedOptions()
  end
  options.pattern.onOptionChange=function()
    if loading or not optionDraft then return end
    for i, value in ipairs(ctx.patterns[patternCategory(optionDraft.category)]) do
      if value == options.pattern:getCurrentOption().text then optionDraft.pattern=i end
    end
    changedOptions()
  end
  loadOptions=function(entry, new)
    local wasLoading=loading; loading=true
    newOption=new == true; optionTarget=entry; optionOwnerList=draft.attackTable
    optionDirty=newOption; optionDraft=entry and C.copy(entry) or nil
    options:setEnabled(entry ~= nil)
    text(options.words,entry and entry.spell or '')
    text(options.names,entry and (entry.creatures or '*') or '')
    text(options.help,'Edita el spell seleccionado. 0 conserva cadena/CD originales. Aplicar cambios guarda toda la rotacion.')
    if entry then
      optionDraft.itemId=entry.itemId or 0
      optionDraft.range=entry.spellRange or 7
      optionDraft.targets=entry.chainTargets or 0; optionDraft.jump=entry.chainJump or 0
      optionDraft.harmony=entry.minimumHarmony or 0; optionDraft.secondary=(entry.secondaryCooldown or 0)/1000
      for key, control in pairs(opt) do control:set(optionDraft[key]) end
      options.category:setCurrentOption(categoryNames[entry.category]); fillPatterns()
    else
      for _, control in pairs(opt) do control:set(0) end
    end
    loading=wasLoading
    if refreshPreview then refreshPreview() end
  end
  refreshPreview=function()
    local entry=optionDraft and C.copy(optionDraft) or nil
    if entry then
      entry.spell=options.words:getText()
      entry.patternCategory=patternCategory(entry.category)
      entry.spellRange=entry.range
      entry.chainTargets=entry.targets and entry.targets>0 and entry.targets or nil
      entry.chainJump=entry.jump and entry.jump>0 and entry.jump or nil
    end
    AttackSpellPreview.render(options.preview,entry,ctx.spellPatterns or {},previewDirection)
  end
  options.preview.direction.onClick=function()
    previewDirection=(previewDirection+1)%4;refreshPreview()
  end
  local previewVisible=true
  local function showPreview()
    for _,child in ipairs(options:getChildren()) do
      local id=child:getId()
      child:setVisible(id=='heading' or id=='previewToggle' or
        id=='preview' and previewVisible or not previewVisible and id~='preview' and id~='namesHelp')
    end
    options.previewToggle:setText(previewVisible and 'Editar area' or 'Ver forma')
  end
  options.previewToggle.onClick=function() previewVisible=not previewVisible;showPreview() end
  showPreview()
  local function optionError(message,field)
    text(options.help,message); notify(message,true)
    win.rotationTab.onClick()
    if field then field:focus() end
    return false
  end
  commitOptions=function()
    if not optionDraft then return true end
    if not validNumbers(optionNumbers) then win.rotationTab.onClick(); return false end
    if not optionDirty then return true end
    if optionOwnerList ~= draft.attackTable then
      return optionError('La vocacion cambio. Selecciona de nuevo el spell.')
    end
    local exists=false
    for _, entry in ipairs(draft.attackTable) do if entry == optionTarget then exists=true end end
    if not exists then return optionError('Ese spell ya no esta en la lista.') end
    local words=C.normalize(options.words:getText())
    if optionDraft.itemId > 0 and optionDraft.itemId <= 100 then
      return optionError('El ID de una runa debe ser mayor de 100. Usa 0 para spells.',options.itemId.input)
    end
    -- Conditions and enabled state may have changed since these fields loaded.
    local candidate=C.copy(optionTarget)
    for _, key in ipairs({'itemId','category','pattern','range','targets','jump','harmony','secondary'}) do
      candidate[key]=optionDraft[key]
    end
    candidate.spell=words
    if candidate.itemId == 0 and (words == '' or not C.allowed(candidate,draft.selectedVocation)) then
      return optionError('Formula vacia o de otra vocacion. Para spells del servidor usa Personalizado.',options.words)
    end
    if candidate.itemId > 100 and candidate.category ~= 2 and candidate.category ~= 3 then
      return optionError('Para una runa elige Runa de area o Runa dirigida.',options.category)
    end
    if candidate.itemId == 0 and (candidate.category == 2 or candidate.category == 3) then
      return optionError('Ese tipo de ataque necesita el ID de una runa.',options.itemId.input)
    end
    for _, entry in ipairs(draft.attackTable) do
      if entry ~= optionTarget and entryKey(entry) == entryKey(candidate) then
        return optionError('Ese spell o runa ya existe en la rotacion.',options.words)
      end
    end
    local geometryChanged=newOption or candidate.category ~= optionTarget.category or candidate.pattern ~= optionTarget.pattern
    local identityChanged=newOption or entryKey(candidate) ~= entryKey(optionTarget)
    if identityChanged then
      for _, key in ipairs({'catalogSpell','catalogGeometryVersion','rotationPreset','msPreset','rotationPower',
        'barrageAimVersion','grenadeAimVersion'}) do candidate[key]=nil end
    end
    candidate.patternCategory=patternCategory(candidate.category)
    candidate.spellRange=candidate.range; candidate.minimumHarmony=candidate.harmony
    candidate.chainTargets=candidate.targets > 0 and candidate.targets or nil
    candidate.chainJump=candidate.jump > 0 and candidate.jump or nil
    candidate.secondaryCooldown=candidate.secondary > 0 and math.floor(candidate.secondary*1000+0.5) or nil
    if geometryChanged then candidate.customGeometry=true end
    if geometryChanged and candidate.category == 6 then
      local model=C.models[candidate.pattern]
      candidate.catalogGeometryVersion=C.version
      candidate.spellRange=model.range or candidate.spellRange
      candidate.chainTargets=model.maxTargets; candidate.chainJump=model.jump
    end
    local names=C.normalize(options.names:getText())
    candidate.creatures=names == '' and '*' or names; candidate.monsters=true
    if names ~= '' and names ~= '*' then
      candidate.monsters={}
      for value in names:gmatch('[^,]+') do
        value=C.normalize(value)
        if value ~= '' then candidate.monsters[#candidate.monsters+1]=value end
      end
    end
    for _, key in ipairs({'range','targets','jump','harmony','secondary'}) do candidate[key]=nil end
    describe(candidate)
    for key in pairs(optionTarget) do optionTarget[key]=nil end
    for key, value in pairs(candidate) do optionTarget[key]=value end
    optionDirty=false; newOption=false; mark()
    text(options.help,'Cambios en el borrador. Aplicar cambios guarda toda la rotacion.')
    renderEditor(); updateRows()
    return true
  end

  local function renderPicker()
    picker.entries:destroyChildren()
    local filter=C.normalize(picker.search:getText())
    for _, entry in ipairs(pickerChoices or {}) do
      if filter == '' or C.normalize(name(entry) .. ' ' .. (entry.spell or '') .. ' ' .. (entry.itemId or '')):find(filter,1,true) then
        local row=UI.createWidget('StudioEntry',picker.entries)
        text(row.title,name(entry)); text(row.words,(entry.itemId or 0)>100 and ('ID ' .. entry.itemId) or entry.spell)
        text(row.minimum,entry.count .. '+'); text(row.cooldown,seconds(entry.cooldown) .. 's')
        setIcon(row.icon,row.item,entry); row.enabled:hide()
        row:setOn(entry == pickerSelected)
        row:setTooltip(entry.tooltip or name(entry))
        row.onClick=function() pickerSelected=entry; renderPicker() end
      end
    end
    picker.add:setEnabled(pickerSelected ~= nil)
  end
  left.add.onClick=function()
    if not validNumbers(mainNumbers) or not commitOptions() then return end
    pickerChoices={}; local seen={}
    local function add(entry)
      local key=entryKey(entry)
      if not seen[key] then seen[key]=true; pickerChoices[#pickerChoices+1]=entry end
    end
    for _, entry in ipairs(R and R.entries(draft.selectedVocation) or {}) do add(entry) end
    for _, data in ipairs(C.list(draft.selectedVocation)) do add(C.makeEntry(data)) end
    if draft.selectedVocation == 'Personalizado' and R then
      for _, vocation in ipairs(C.profileVocations) do
        if R.supported[vocation] then for _, entry in ipairs(R.entries(vocation)) do add(entry) end end
      end
    end
    pickerSelected=nil; text(picker.search,''); renderPicker(); reveal(picker)
  end
  picker.search.onTextChange=function() if pickerChoices then renderPicker() end end
  picker.closeButton.onClick=function() picker:hide() end
  picker.onEscape=function() picker:hide(); return true end
  picker.add.onClick=function()
    if not pickerSelected or not validNumbers(mainNumbers) or not commitOptions() then return end
    for _, entry in ipairs(draft.attackTable) do
      if entryKey(entry) == entryKey(pickerSelected) then
        selected=entry; picker:hide(); renderEditor(); renderList(); notify('Ese spell ya estaba en la rotacion.'); return
      end
    end
    selected=C.copy(pickerSelected); selected.enabled=false
    draft.attackTable[#draft.attackTable+1]=selected
    loading=true; text(left.search,''); loading=false
    mark(); picker:hide(); renderEditor(); renderList()
  end
  picker.custom.onClick=function()
    if not validNumbers(mainNumbers) or not commitOptions() then return end
    selected={spell='',itemId=0,category=1,patternCategory=1,pattern=7,count=1,orMore=true,
      enabled=false,mana=1,minHp=0,maxHp=100,cooldown=2000,creatures='*',monsters=true}
    draft.attackTable[#draft.attackTable+1]=selected
    loading=true; text(left.search,''); loading=false
    mark(); picker:hide(); renderEditor(); renderList(); loadOptions(selected,true)
    win.rotationTab.onClick(); reveal(win); options.words:focus()
  end
  win.advanced.restore.onClick=function()
    if not R or not R.supported[draft.selectedVocation] then return end
    confirmAction('Se reemplazara la lista de ' .. draft.selectedVocation .. ' por su rotacion base. Puedes revisarla antes de aplicar.','Restaurar lista',function()
      draft.attackTable=R.entries(draft.selectedVocation)
      draft.attacksByVocation[draft.selectedVocation]=draft.attackTable
      selected=draft.attackTable[1]
      loading=true; text(left.search,''); loading=false
      mark(); renderEditor(); renderList(); return true
    end)
  end
  -- Cheap status synchronization only. It never recreates the spell list.
  macro(250,function() studio.sync() end)
  return studio
end
