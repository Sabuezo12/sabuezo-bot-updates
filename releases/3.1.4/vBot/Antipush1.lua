setDefaultTab("tools")
UI.Separator()

local panelName = "antipushCoins"
local GOLD_COIN_ID = 3031
local PLATINUM_COIN_ID = 3035
local DEFAULT_WITHDRAW_TEXT = "!bank withdraw 20000"
local MIN_PLATINUM = 30
local WITHDRAW_DELAY = 5000
local STACK_LAYER_COUNT = 6
local DROP_AMOUNT = 2

if not storage[panelName] then
  storage[panelName] = {
    enabled = false,
    hotkey = "Numpad0",
    withdrawText = DEFAULT_WITHDRAW_TEXT,
    dropItems = { GOLD_COIN_ID }
  }
end

local config = storage[panelName]
config.hotkey = config.hotkey or "Numpad0"
config.withdrawText = config.withdrawText or DEFAULT_WITHDRAW_TEXT
config.dropItems = config.dropItems or { GOLD_COIN_ID }
if type(config.dropItems) ~= "table" then
  config.dropItems = { GOLD_COIN_ID }
end

local ui = setupUI([[
Panel
  height: 20

  HelperThemePower
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('AntiPush Coins')

  HelperThemeButton
    id: edit
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 18
    text: Edit
]])

local edit = setupUI([[
Panel
  height: 128
  margin-top: 2

  HelperThemeLabel
    id: itemsLabel
    anchors.top: parent.top
    anchors.left: parent.left
    text: Items to Drop:
    height: 18

  BotContainer
    id: DropItems
    anchors.top: itemsLabel.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    height: 56
    margin-top: 2

  HelperThemeLabel
    id: hotkeyLabel
    anchors.top: DropItems.bottom
    anchors.left: parent.left
    text: Hotkey:
    height: 18
    margin-top: 6

  HelperThemeButton
    id: HotkeyButton
    anchors.top: prev.top
    anchors.left: parent.horizontalCenter
    anchors.right: parent.right
    height: 18
    text-align: center
    text: Set

  HelperThemeLabel
    id: withdrawLabel
    anchors.top: hotkeyLabel.bottom
    anchors.left: parent.left
    text: Bank Text:
    height: 18
    margin-top: 6

  HelperThemeButton
    id: WithdrawButton
    anchors.top: prev.top
    anchors.left: parent.horizontalCenter
    anchors.right: parent.right
    height: 18
    text-align: center
    text: Edit
]])
edit:hide()

local showEdit = false
local waitingHotkey = false
local canonicalKey
local lastWithdrawAt = 0
local dropIds = {}
local dropSequence = {}
local nextDropIndex = 1
local lastPosKey = ""
local lastItemLayerCount = 0
local buildMoves = 0

local function getTime()
  if now then return now end
  if g_clock and g_clock.millis then return g_clock.millis() end
  return 0
end

local function trim(text)
  return tostring(text or ""):gsub("^%s*(.-)%s*$", "%1")
end

local function firstLine(text)
  text = tostring(text or ""):gsub("\r\n", "\n")
  return trim(text:match("([^\n]*)") or text)
end

local function addUnique(list, itemId)
  for _, id in ipairs(list) do
    if id == itemId then return end
  end
  table.insert(list, itemId)
end

local function refreshDropSequence()
  dropSequence = {}
  if #dropIds == 0 then return end

  local index = 1
  while #dropSequence < STACK_LAYER_COUNT do
    table.insert(dropSequence, dropIds[index])
    index = index + 1
    if index > #dropIds then
      index = 1
    end
  end

  if nextDropIndex > #dropSequence then
    nextDropIndex = 1
  end
end

local function refreshDropIds()
  dropIds = { GOLD_COIN_ID, PLATINUM_COIN_ID }
  local items = config.dropItems or {}

  for _, item in pairs(items) do
    local itemId = item
    if type(item) == "table" then
      itemId = item.id
    end
    itemId = tonumber(itemId)
    if itemId and itemId > 0 then
      addUnique(dropIds, itemId)
    end
  end

  refreshDropSequence()
end

local function dropIdsContain(itemId)
  for _, dropId in ipairs(dropIds) do
    if dropId == itemId then return true end
  end
  return false
end

local function sayText(text)
  if not text or text == "" then return false end
  if type(say) == "function" then
    local ok = pcall(function() say(text) end)
    if ok then return true end
  end
  if g_game and g_game.talk then
    g_game.talk(text)
    return true
  end
  return false
end

local function getItemCount(itemId)
  local total = 0
  if not getContainers then return total end

  for _, container in pairs(getContainers()) do
    for _, item in ipairs(container:getItems()) do
      if item:getId() == itemId then
        total = total + item:getCount()
      end
    end
  end
  return total
end

local function getPosKey(p)
  if not p then return "" end
  return p.x .. "," .. p.y .. "," .. p.z
end

local function getItemLayerCount(tile)
  local items = tile and tile:getItems()
  if not items then return 0 end
  return #items
end

-- AntiPush never converts currency or changes the separate Gold Converter.
-- Keep the existing, independently configured bank-withdrawal behavior.
local function ensureGold()
  local time = getTime()
  local needsPlatinum = dropIdsContain(GOLD_COIN_ID) or dropIdsContain(PLATINUM_COIN_ID)
  if needsPlatinum and getItemCount(PLATINUM_COIN_ID) < MIN_PLATINUM and time - lastWithdrawAt >= WITHDRAW_DELAY then
    if sayText(config.withdrawText) then lastWithdrawAt = time end
  end
  return true
end

local function updateSettingButtons()
  local displayKey=canonicalKey and canonicalKey(config.hotkey)or(config.hotkey or "")
  edit.HotkeyButton:setText(displayKey)
  edit.WithdrawButton:setText("Bank Text")
  if edit.HotkeyButton.setTooltip then
    edit.HotkeyButton:setTooltip("Hotkey: " .. displayKey)
  end
  if edit.WithdrawButton.setTooltip then
    edit.WithdrawButton:setTooltip(config.withdrawText or "")
  end
end

local function setEnabled(enabled)
  config.enabled = enabled == true
  ui.title:setOn(config.enabled)
  lastPosKey = ""
  lastItemLayerCount = 0
  buildMoves = 0
  nextDropIndex = 1
end

AntiPush = {
  isOn = function()
    return config.enabled == true
  end,
  setOn = function()
    return setEnabled(true)
  end,
  setOff = function()
    return setEnabled(false)
  end
}

ui.title:setOn(config.enabled)
ui.title.onClick = function()
  setEnabled(not config.enabled)
end

ui.edit.onClick = function()
  showEdit = not showEdit
  edit:setVisible(showEdit)
end

UI.Container(function()
  local currentItems = edit.DropItems:getItems()
  if currentItems then
    config.dropItems = currentItems
    refreshDropIds()
  end
end, true, nil, edit.DropItems)

schedule(100, function()
  if edit.DropItems and config.dropItems then
    edit.DropItems:setItems(config.dropItems)
    refreshDropIds()
  end
end)

refreshDropIds()
updateSettingButtons()

-- All listeners and polling share one press latch. The existing 20ms engine
-- supplies a physical-state fallback when a focused widget eats KeyDown.
local hotkeyHeld,captureUntil=false,0
local lastHotkeyAt,captureGuardUntil,physicalWasDown=-1000,0,false
canonicalKey=function(key,modifiers)
  if type(key)=='number' then
    if modifiers~=nil and type(determineKeyComboDesc)=='function' then
      local ok,value=pcall(determineKeyComboDesc,key,modifiers)
      if ok and value and value~='' then key=value end
    end
    if type(key)=='number' then key=KeyCodeDescs and KeyCodeDescs[key] or '' end
  end
  local ctrl,alt,shift,base=false,false,false,nil
  for part in tostring(key or ''):gmatch('[^+]+')do
    part=trim(part);local name=part:lower():gsub('%s+',''):gsub('_','')
    if name=='ctrl'or name=='control'then ctrl=true
    elseif name=='alt'then alt=true
    elseif name=='shift'then shift=true
    else
      local digit=name:match('^keynumpad(%d)$')or name:match('^numpad(%d)$')or
        name:match('^keypad(%d)$')or name:match('^num(%d)$')or name:match('^kp(%d)$')
      -- MythicOT reports the physical keypad zero as NIns in the user's
      -- capture. Keep the ordinary Insert key and top-row 0 distinct.
      if name=='nins' then digit='0'end
      base=digit and('Numpad'..digit)or(name=='esc'and'Escape'or part)
    end
  end
  local result={};if ctrl then result[#result+1]='Ctrl'end;if alt then result[#result+1]='Alt'end
  if shift then result[#result+1]='Shift'end;if base then result[#result+1]=base end
  return table.concat(result,'+'),base,ctrl,alt,shift
end
local function typingFocus()
  local widget=g_ui and g_ui.getRootWidget and g_ui.getRootWidget()
  for _=1,16 do
    if not widget then break end
    local class=widget.getClassName and widget:getClassName()or ''
    if tostring(class):lower():find('textedit',1,true)and(not widget.isVisible or widget:isVisible())then return true end
    widget=widget.getFocusedChild and widget:getFocusedChild()or nil
  end
  return false
end
local pollCache
local function physicalKey(key)
  local kb=g_keyboard
  if not kb or type(kb.isKeyPressed)~='function'then return nil end
  local normalized,base,ctrl,alt,shift=canonicalKey(key)
  if not base then return nil end
  if not pollCache or pollCache.name~=normalized then
    local codes={}
    for number,description in pairs(KeyCodeDescs or{})do
      if canonicalKey(description):lower()==canonicalKey(base):lower()then codes[#codes+1]=number end
    end
    -- Some clients expose separate native codes for NIns and Numpad0.
    -- Poll every matching code so an inactive alias cannot clear the latch.
    if #codes==0 then
      codes={base}
      if base=='Numpad0'then codes[#codes+1]='NIns'end
    end
    pollCache={name=normalized,codes=codes}
  end
  local readable,pressed=false,false
  for _,code in ipairs(pollCache.codes)do
    local ok,value=pcall(kb.isKeyPressed,code)
    if ok and type(value)=='boolean'then readable=true;pressed=pressed or value end
  end
  if not readable then return nil end
  if not pressed then return false,false end
  for _,check in ipairs({{'isCtrlPressed',ctrl},{'isAltPressed',alt},{'isShiftPressed',shift}})do
    if type(kb[check[1]])~='function'then return nil end
    local ok,value=pcall(kb[check[1]])
    if not ok then return nil end
    if(value==true)~=check[2]then return false,true end
  end
  return true,true
end
local function cancelHotkeyCapture()
  waitingHotkey=false;captureUntil=0;updateSettingButtons()
end
local function handleHotkey(key,modifiers,phase,repeatTicks)
  local normalized,base=canonicalKey(key,modifiers)
  if normalized==''then return false end
  if waitingHotkey then
    if normalized:lower()=='escape'then cancelHotkeyCapture();return true end
    if not base then return true end -- wait for the non-modifier key
    config.hotkey=normalized;waitingHotkey=false;captureUntil=0
    hotkeyHeld=true;pollCache=nil
    lastHotkeyAt=getTime();captureGuardUntil=getTime()+150
    updateSettingButtons()
    if type(saveConfig)=='function'then pcall(saveConfig)end
    return true -- assigning never also toggles AntiPush
  end
  if canonicalKey(config.hotkey):lower()~=normalized:lower()then return false end
  -- This explicitly assigned keypad shortcut must work while the console
  -- retains a text focus. Printable/custom shortcuts keep their edit guard.
  if base~='Numpad0'and typingFocus()then hotkeyHeld=true;return false end
  if phase=='press'and tonumber(repeatTicks)and tonumber(repeatTicks)>0 then return true end
  if phase=='down'then
    local _,down=physicalKey(config.hotkey)
    if down==true then physicalWasDown=true end
  end
  local time=getTime()
  if time<captureGuardUntil then return true end
  -- Down is a fresh native press, even if its previous Up was consumed by a
  -- focused widget. Keep a short shared-delivery guard for polling/Down/Press.
  if hotkeyHeld and not physicalWasDown and time-lastHotkeyAt>120 and
    (phase=='down'or phase=='press'and tonumber(repeatTicks)==0)then hotkeyHeld=false end
  if not hotkeyHeld then
    hotkeyHeld=true;lastHotkeyAt=time;setEnabled(not config.enabled)
  end
  return true
end
local function pollHotkey()
  if waitingHotkey then
    if getTime()>=captureUntil then cancelHotkeyCapture();return end
    -- Scan only while explicitly assigning a key. Never turn the top-row 0
    -- or Insert into a Numpad0 alias.
    local prefix=''
    for _,entry in ipairs({{'isCtrlPressed','Ctrl+'},{'isAltPressed','Alt+'},{'isShiftPressed','Shift+'}})do
      local fn=g_keyboard and g_keyboard[entry[1]]
      if type(fn)=='function'then local ok,value=pcall(fn);if ok and value then prefix=prefix..entry[2]end end
    end
    for _,name in pairs(KeyCodeDescs or{})do
      local _,base=canonicalKey(name)
      if base and physicalKey(prefix..base)==true then handleHotkey(prefix..base);return end
    end
    if physicalKey(config.hotkey)==true then handleHotkey(config.hotkey)end
    return
  end
  local pressed,down=physicalKey(config.hotkey)
  if pressed==true then physicalWasDown=true;handleHotkey(config.hotkey,nil,'poll')
  elseif down==true then physicalWasDown=true;hotkeyHeld=true -- keep modifier-release guard
  elseif pressed==false and physicalWasDown then
    -- A client can report false for an unsupported alias. Only a state we
    -- actually observed down may release the event latch via polling.
    physicalWasDown=false;hotkeyHeld=false;captureGuardUntil=0
  end
end
edit.HotkeyButton.onClick=function()
  waitingHotkey=true;captureUntil=getTime()+10000
  edit.HotkeyButton:setText('Pulsa tecla...')
  edit.HotkeyButton:setTooltip('Pulsa la tecla. Esc cancela.')
  if edit.HotkeyButton.focus then edit.HotkeyButton:focus()end
end
edit.HotkeyButton.onKeyDown=function(widget,keyCode,modifiers)
  if waitingHotkey then return handleHotkey(keyCode,modifiers,'down')end
  return false
end
edit.onVisibilityChange=function(widget,visible)
  if visible==false and waitingHotkey then cancelHotkeyCapture()end
end

-- Render the canonical label after its normalizer is initialized.
updateSettingButtons()

edit.WithdrawButton.onClick = function()
  UI.MultilineEditorWindow(config.withdrawText or "", {
    title = "AntiPush Bank Text",
    description = "Text to say when platinum coins are low."
  }, function(text)
    config.withdrawText = firstLine(text)
    updateSettingButtons()
  end)
end

macro(20, function()
  pollHotkey()
  if not config.enabled then return end
  if #dropSequence == 0 then return end

  local playerPos = pos()
  local currentPosKey = getPosKey(playerPos)
  if currentPosKey ~= lastPosKey then
    lastPosKey = currentPosKey
    lastItemLayerCount = 0
    buildMoves = 0
    nextDropIndex = 1
  end

  local tile = g_map.getTile(playerPos)
  if not tile then return end

  ensureGold()

  local itemLayerCount = getItemLayerCount(tile)
  if itemLayerCount ~= lastItemLayerCount then
    buildMoves = 0
  end
  lastItemLayerCount = itemLayerCount

  if itemLayerCount >= STACK_LAYER_COUNT then return end
  if tile:getThingCount() >= 10 then return end
  local missingLayers = STACK_LAYER_COUNT - itemLayerCount
  if buildMoves >= missingLayers then return end

  for _ = 1, #dropSequence do
    local itemId = dropSequence[nextDropIndex]
    nextDropIndex = nextDropIndex + 1
    if nextDropIndex > #dropSequence then
      nextDropIndex = 1
    end
    local item = findItem(itemId)
    if item then
      g_game.move(item, playerPos, DROP_AMOUNT)
      buildMoves = buildMoves + 1
      return
    end
  end
end)

onKeyDown(function(key)handleHotkey(key,nil,'down')end)
if type(onKeyPress)=='function'then onKeyPress(function(key,ticks)handleHotkey(key,nil,'press',ticks)end)end
if type(onKeyUp)=='function'then
  onKeyUp(function(key)
    local _,released=canonicalKey(key)
    local _,configured=canonicalKey(config.hotkey)
    if released and configured and released:lower()==configured:lower()then hotkeyHeld=false;physicalWasDown=false;captureGuardUntil=0 end
  end)
end

UI.Separator()
