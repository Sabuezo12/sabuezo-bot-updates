--[[
vBot Scripting Services / Serviços de script / Servicios de scripting:
Discord: F.Almeida#8019

(ENG) If you like it, consider making a donation:
(PT) Se você gostou, considere fazer uma doação:
(ESP) Si le gusta, considere hacer una donación:
https://www.paypal.com/donate/?business=8XSU4KTS2V9PN&no_recurring=0&item_name=OTC+AND+OTS+SCRIPTS&currency_code=USD

The original UI of this module was created by Lee#7225
https://trainorcreations.com/coding/otclient/27
--]]

-- ATTENTION:
-- Don't edit below this line unless you know what you're doing.
-- ATENÇÃO:
-- Não mexa em nada daqui para baixo, a não ser que saiba o que está fazendo.
-- ATENCIÓN:
-- No cambies nada desde aquí, solamente si sabes lo que estás haciendo.

setDefaultTab("HP")

local buffUi = setupUI([[
Panel
  height: 20

  HelperThemePower
    id: status
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    height: 18
    text: Auto Buff

  HelperThemeButton
    id: editSpellList
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 18
    text: Setup
  
]], parent)

g_ui.loadUIFromString([[
SpellName < HelperThemeLabel
  background-color: alpha
  text-offset: 2 0
  focusable: true
  height: 16

  $focus:
    background-color: #00000055

  HelperThemeButton
    id: remove
    text: x
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    margin-right: 1
    width: 14
    height: 14

spellListWindow < HelperThemeWindow
  padding-bottom: 8
  padding-top: 8
  padding: 8
  text: Auto Buff by F.Almeida
  size: 340 214
  @onEscape: self:hide()

  HelperThemeLabel
    visible: false
    height: 10
    width: 10
    margin-top: 0
    margin-left: 0
    anchors.top: parent.top
    anchors.left: parent.left
    id: lblPos
    text-align: center
    text: Icon Position:

  HelperThemeLabel
    visible: false
    margin-top: 0
    margin-left: 0
    anchors.top: parent.top
    anchors.left: parent.left
    id: lblPosX
    text-align: center
    width: 10
    height: 10
    !text: ('Pos X: ')

  HelperThemeSpin
    visible: false
    height: 10
    margin-top: 0
    margin-left: 0
    anchors.top: parent.top
    anchors.left: parent.left
    id: ipx
    minimum: 0
    maximum: 2000
    width: 10
    step: 10
    editable: true
    focusable: true

  HelperThemeLabel
    visible: false
    height: 10
    margin-top: 0
    margin-left: 0
    anchors.top: parent.top
    anchors.left: parent.left
    id: lblPosY
    text-align: center
    width: 10
    !text: ('Pos Y: ')

  HelperThemeSpin
    visible: false
    height: 10
    margin-top: 0
    margin-left: 0
    anchors.top: parent.top
    anchors.left: parent.left
    id: ipy
    minimum: 0
    maximum: 2000
    width: 10
    step: 10
    editable: true
    focusable: true

  HelperThemeLabel
    width: 210
    margin-top: 0
    margin-left: 0
    anchors.top: parent.top
    anchors.left: parent.left
    id: lblEx
    height: 20
    text-align: left
    text: Default Exhausted:

  HelperThemeSpin
    height: 20
    margin-top: 0
    margin-left: 254
    anchors.top: parent.top
    anchors.left: parent.left
    id: ex
    minimum: 0
    maximum: 5000
    width: 70
    step: 100
    editable: true
    focusable: true
    text-align: center

  HelperThemeLabel
    height: 14
    width: 324
    margin-top: 24
    margin-left: 0
    anchors.top: parent.top
    anchors.left: parent.left
    id: lblSpells
    text-align: center
    text: Spells List
    
  HelperThemeList
    fit-children: false
    padding-right: 16
    width: 324
    margin-top: 40
    margin-left: 0
    anchors.top: parent.top
    anchors.left: parent.left
    id: lstSpells
    padding: 2
    height: 60
    vertical-scrollbar: AutoBuffVScroll
    
  VerticalScrollBar
    height: 60
    width: 12
    margin-top: 40
    margin-left: 312
    anchors.top: parent.top
    anchors.left: parent.left
    id: AutoBuffVScroll
    step: 14
    pixels-scroll: true

  HelperThemeLabel
    height: 14
    width: 324
    margin-top: 104
    margin-left: 0
    anchors.top: parent.top
    anchors.left: parent.left
    id: lblExample
    text-align: center
    text: Example: Utito Tempo, 10
    
  HelperThemeInput
    height: 20
    margin-top: 122
    margin-left: 0
    anchors.top: parent.top
    anchors.left: parent.left
    id: spellEntry
    width: 278

  HelperThemeButton
    height: 20
    width: 42
    margin-top: 122
    margin-left: 282
    anchors.top: parent.top
    anchors.left: parent.left
    id: addSpell
    text: +
    font: verdana-11px-antialised
  

  HorizontalSeparator
    height: 1
    width: 324
    margin-top: 146
    margin-left: 0
    anchors.top: parent.top
    anchors.left: parent.left
    id: optionsSeparator

  HelperThemeCheck
    height: 16
    width: 158
    margin-top: 150
    margin-left: 0
    anchors.top: parent.top
    anchors.left: parent.left
    id: checkAtk
    text: Stop if attacking
    tooltip: Only cast buff if not attacking any creature.

  HelperThemeCheck
    height: 16
    width: 158
    margin-top: 150
    margin-left: 166
    anchors.top: parent.top
    anchors.left: parent.left
    id: checkPz
    text: Stop if in PZ
    tooltip: Only cast buff if not in Protection Zone.

  HelperThemeCheck
    visible: false
    height: 10
    width: 10
    margin-top: 0
    margin-left: 0
    anchors.top: parent.top
    anchors.left: parent.left
    id: createIcon
    text: Create Icon

  HorizontalSeparator
    height: 1
    width: 324
    margin-top: 170
    margin-left: 0
    anchors.top: parent.top
    anchors.left: parent.left
    id: separator

  HelperThemeButton
    height: 20
    width: 60
    margin-top: 176
    margin-left: 264
    anchors.top: parent.top
    anchors.left: parent.left
    id: closeButton
    text: Close
    font: verdana-11px-antialised

  HelperThemeButton
    height: 20
    width: 60
    margin-top: 176
    margin-left: 0
    anchors.top: parent.top
    anchors.left: parent.left
    id: info
    text: Credits
    font: verdana-11px-antialised
    color: yellow
    !tooltip: tr('Created by F.Almeida#8019\nClick to contribute.')
    @onClick: g_platform.openUrl("https://www.paypal.com/donate/?business=8XSU4KTS2V9PN&no_recurring=0&item_name=OTC+AND+OTS+SCRIPTS&currency_code=USD")
]])

local panelName = "autoBuff"

if not storage[panelName] then
  storage[panelName] = {
    exhausted = 1001,
    spellList = {"set some spell first, 10"},
    enabled = false,
    atk = false,
    pz = true,
  }
end

local config = storage[panelName]

rootWidget = g_ui.getRootWidget()
if rootWidget then

  spellListWindow = UI.createWindow('spellListWindow', rootWidget)
  spellListWindow:hide()
  for _, widgetId in ipairs({"lblPos", "lblPosX", "ipx", "lblPosY", "ipy", "createIcon"}) do
    if spellListWindow[widgetId] then
      spellListWindow[widgetId]:hide()
    end
  end

  buffUi.editSpellList.onClick = function(widget)
    spellListWindow:show()
    spellListWindow:raise()
    spellListWindow:focus()
  end

  spellListWindow.closeButton.onClick = function(widget)
    spellListWindow:hide()
  end

  if config.spellList and #config.spellList > 0 then
    for _, pName in ipairs(config.spellList) do
      local label = g_ui.createWidget("SpellName", spellListWindow.lstSpells)
      label.remove.onClick = function(widget)
        table.removevalue(config.spellList, label:getText())
        label:destroy()
      end
      label:setText(pName)
      label.onDoubleClick = function(widget)
        table.removevalue(config.spellList, label:getText())
        spellListWindow.spellEntry:setText(label:getText())
        label:destroy()
      end
    end
  end
  spellListWindow.addSpell.onClick = function(widget)
    local spellEntry = spellListWindow.spellEntry:getText():lower()
    if spellEntry:len() > 0 and not table.contains(config.spellList, spellEntry, true) then
      if string.find(spellEntry,",") then
        if not tonumber(spellEntry:split(",")[2]) then
          warn('You must insert: spell name, cooldown (in ms: 1000 = 1s)')
        else
          table.insert(config.spellList, spellEntry)
          local label = g_ui.createWidget("SpellName", spellListWindow.lstSpells)
          label.remove.onClick = function(widget)
            table.removevalue(config.spellList, label:getText())
            label:destroy()
          end
          label:setText(spellEntry)
          spellListWindow.spellEntry:setText('')
          label.onDoubleClick = function(widget)
            table.removevalue(config.spellList, label:getText())
            spellListWindow.spellEntry:setText(label:getText())
            label:destroy()
          end
        end
      else
        warn('You must insert: spell name, cooldown (in seconds)')
      end
    end
  end

  buffUi.status:setOn(config.enabled)
  buffUi.status.onClick = function(widget)
    config.enabled = not config.enabled
    widget:setOn(config.enabled)
  end

  AutoBuff = {
    isOn = function()
      return config.enabled == true
    end,
    setOn = function()
      config.enabled = true
      buffUi.status:setOn(true)
    end,
    setOff = function()
      config.enabled = false
      buffUi.status:setOn(false)
    end
  }

  spellListWindow.checkAtk:setChecked(config.atk)
  spellListWindow.checkAtk.onClick = function(widget)
    config.atk = not config.atk
    widget:setChecked(config.atk)
  end

  spellListWindow.checkPz:setChecked(config.pz)
  spellListWindow.checkPz.onClick = function(widget)
    config.pz = not config.pz
    widget:setChecked(config.pz)
  end

  spellListWindow.spellEntry.onKeyPress = function(self, keyCode, keyboardModifiers)
    if not (keyCode == 5) then
      return false
    end
    spellListWindow.addSpell.onClick()
    return true
  end

  spellListWindow.spellEntry.onTextChange = function(widget, text)
    if table.contains(config.spellList, text, true) then
      spellListWindow.addSpell:setColor("red")
    elseif text:len() > 0 then
      spellListWindow.addSpell:setColor("green")
    else
      spellListWindow.addSpell:setColor("white")
    end
  end

  -- default exhausted
  spellListWindow.ex:setValue(config.exhausted)
  spellListWindow.ex.onValueChange = function(widget, value)
    config.exhausted = value
  end

  -- main loops
  -- switches
  macro(1000,function()
    buffUi.status:setOn(config.enabled)
  end)
  -- auto buff
  macro(500,function()
    if not config.enabled then return end
    if g_game.isAttacking() and config.atk then return end
    if isInPz() and config.pz then return end

    for e, entry in pairs(config.spellList) do
      local spell = entry:split(",")[1]
      local cd = tonumber(entry:split(",")[2]) * 1000
      -- fix for vbot bug
      local a,b,c = modules.gamelib.Spells.getSpellByWords(spell)
      local Spells = modules.gamelib.SpellInfo['Default']
      local s = Spells[c]
      if s then
        if type(s.mana) == 'string' then
          s.mana = 1
        end
      end
      -- end fix
      if canCast(spell) then
        cast(spell,cd)
        delay(config.exhausted)
        return
      end
    end

  end)
end

-- UI.Separator()
