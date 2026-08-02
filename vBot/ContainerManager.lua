setDefaultTab("Main")

-- general settings
local cGreen = '#00FF00' -- green color for UI
local cRed = '#FF0000' -- red color for UI
local tag = "[Container Manager]\n" -- used for console log
local purseId = 23396 -- purse ID
local defaultDelay = 300 -- never less than 250

-- End of basic settings.

-- Original made by Lee#7225
-- https://trainorcreations.com/coding/otclient/36
-- Improved by Vithrax
-- Revamped by F.Almeida

-- vBot scripting services: F.Almeida#8019
-- if you like it, consider making a donation:
-- https://www.paypal.com/donate/?business=8XSU4KTS2V9PN&no_recurring=0&item_name=OTC+AND+OTS+SCRIPTS&currency_code=USD

-- ATTENTION:
-- Don't edit below this line unless you know what you're doing.
-- ATENÇÃO:
-- Não mexa em nada daqui para baixo, a não ser que saiba o que está fazendo.
-- ATENCIÓN:
-- No cambies nada desde aquí, solamente si sabes lo que estás haciendo.

-- default storage
local panelName = "cManager"
if type(storage[panelName]) ~= "table" then
  storage[panelName] = {
    openBack = true,
    openPurse = false,
    reopenAtLogin = true,
    openQuiver = false,
    sortItems = true,
    qtdFullAfk = 1,
    onFullAfk = false,
    pausedCave = false,
    list = {
      {
        eId = 2854,
        eName = "Main Bp",
        eEnabled = true,
        eMinimize = false,
        eInfinite = false,
        ePages = false,
        eFull = false,
        eOpenNext = true,
        eRename = true,
        eResize = true,
        eItems = { 3027, 3028, 3029, 3030 },
      }
    }
  }
end
local config = storage[panelName]
if type(config.inmortalSupplies) ~= "table" then
  config.inmortalSupplies = {}
end
config.inmortalSupplies.mightContainerId = tonumber(config.inmortalSupplies.mightContainerId) or 0
config.inmortalSupplies.ssaContainerId = tonumber(config.inmortalSupplies.ssaContainerId) or 0

local function getExplicitSupplyContainerId(supplyKey)
  if supplyKey == "might" then
    return config.inmortalSupplies.mightContainerId
  elseif supplyKey == "ssa" then
    return config.inmortalSupplies.ssaContainerId
  end
  return 0
end

local function getExplicitSupplyRole(containerId)
  containerId = tonumber(containerId)
  if not containerId or containerId <= 0 then return nil end

  local isMight = config.inmortalSupplies.mightContainerId == containerId
  local isSsa = config.inmortalSupplies.ssaContainerId == containerId
  if isMight and isSsa then return "Inmortal BP" end
  if isMight then return "Might BP" end
  if isSsa then return "SSA BP" end
  return nil
end

local function getExplicitSupplyPriority(containerId)
  local role = getExplicitSupplyRole(containerId)
  if role == "Might BP" or role == "Inmortal BP" then return #config.list + 1 end
  if role == "SSA BP" then return #config.list + 2 end
  return nil
end

-- default switch
UI.Separator()
local cManager = macro(10000, "Container Manager", function() end)

-- The new client can resize a container after onContainerOpen finishes. Reapply
-- minimize after layout settles so a hidden content panel cannot keep full height.
local function minimizeContainerAfterLayout(container)
  local function getWindow()
    if not container or not container.window then return end
    return container.window
  end

  local function isMinimized(cWindow)
    if not cWindow then return false end
    if cWindow.isMinimized then
      local ok, value = pcall(function() return cWindow:isMinimized() end)
      return ok and value == true
    end
    return false
  end

  local function applyInitialMinimize()
    local cWindow = getWindow()
    if cWindow and not isMinimized(cWindow) and cWindow.minimize then
      pcall(function() cWindow:minimize() end)
    end
  end

  local function settleMinimizedLayout()
    local cWindow = getWindow()
    -- A manual maximize must win over the delayed layout correction.
    if not cWindow or not isMinimized(cWindow) then return end
    if cWindow.maximize then
      pcall(function() cWindow:maximize() end)
    end
    if cWindow.minimize then
      pcall(function() cWindow:minimize() end)
    end
  end

  schedule(50, applyInitialMinimize)
  schedule(defaultDelay + 50, settleMinimizedLayout)
end

local function resizeContainerAfterLayout(container)
  local function applyResize()
    if not container or not container.window then return end
    local cWindow = container.window
    if cWindow.isMinimized then
      local ok, minimized = pcall(function() return cWindow:isMinimized() end)
      if ok and minimized then return end
    end
    if cWindow.setContentHeight then
      pcall(function() cWindow:setContentHeight(34) end)
    end
  end

  applyResize()
  schedule(50, applyResize)
  schedule(defaultDelay + 50, applyResize)
end

-- UI
local CM = setupUI([[
Panel
  height: 36

  BotSwitch
    id: onFullAfk
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 90
    height: 17
    !text: tr('Full AFK:')
    tooltip: Stop cavebot to reopen BPs and how many BPs should be open to proceed caveboting.

  SpinBox
    id: qtdFullAfk
    anchors.top: onFullAfk.top
    anchors.left: onFullAfk.right
    text-align: left
    width: 40
    height: 18
    margin-left: 3
    minimum: 1
    maximum: 15
    step: 1
    editable: true
    tooltip: How many BPs should be open to proceed caveboting

  Button
    id: mainSetup
    anchors.top: onFullAfk.top
    anchors.left: prev.right
    margin-top: -1
    anchors.right: parent.right
    margin-left: 3
    height: 18
    text: Setup

  Button
    id: mainReopen
    !text: tr('Re-Open All')
    anchors.left: parent.left
    anchors.top: prev.bottom
    anchors.right: parent.horizontalCenter
    margin-right: 2
    height: 17
    margin-top: 3

  Button
    id: mainMinimize
    !text: tr('Minimize All')
    anchors.top: prev.top
    anchors.left: parent.horizontalCenter
    anchors.right: parent.right
    margin-right: 2
    height: 17
  ]])
CM:setId(panelName)

g_ui.loadUIFromString([[
BackpackName < Label
  background-color: alpha
  text-offset: 18 2
  focusable: true
  height: 17
  font: verdana-11px-rounded

  CheckBox
    id: eEnabled
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: 15
    height: 15
    margin-top: 1
    margin-left: 3

  $focus:
    background-color: #00000055

  Button
    id: eRemove
    !text: tr('X')
    font: verdana-11px-rounded
    !tooltip: tr('Remove')
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    margin-right: 15
    width: 15
    height: 15

  Button
    id: eMinimize
    !text: tr('M')
    font: verdana-11px-rounded
    anchors.right: eRemove.left
    anchors.verticalCenter: parent.verticalCenter
    margin-right: 1
    width: 15
    height: 15
    tooltip: Open Container Minimized

  Button
    id: eOpenNext
    !text: tr('O')
    font: verdana-11px-rounded
    anchors.right: eMinimize.left
    anchors.verticalCenter: parent.verticalCenter
    margin-right: 1
    width: 15
    height: 15
    tooltip: Open Containers inside

  Button
    id: eResize
    !text: tr('S')
    font: verdana-11px-rounded
    anchors.right: eOpenNext.left
    anchors.verticalCenter: parent.verticalCenter
    margin-right: 1
    width: 15
    height: 15
    tooltip: Resize Container (Open Small)

  Button
    id: eRename
    !text: tr('N')
    font: verdana-11px-rounded
    anchors.right: eResize.left
    anchors.verticalCenter: parent.verticalCenter
    margin-right: 1
    width: 15
    height: 15
    tooltip: Rename Container

  Button
    id: eInfinite
    !text: tr('I')
    font: verdana-11px-rounded
    anchors.right: eRename.left
    anchors.verticalCenter: parent.verticalCenter
    margin-right: 1
    width: 15
    height: 15
    tooltip: Inifinite Container: Move items even if it's full

  Button
    id: eFull
    !text: tr('F')
    font: verdana-11px-rounded
    anchors.right: eInfinite.left
    anchors.verticalCenter: parent.verticalCenter
    margin-right: 1
    width: 15
    height: 15
    tooltip: Open Next Container (same id) only when it's full

  Button
    id: ePages
    !text: tr('P')
    font: verdana-11px-rounded
    anchors.right: eFull.left
    anchors.verticalCenter: parent.verticalCenter
    margin-right: 1
    width: 15
    height: 15
    tooltip: Auto Next Page Container

  Button
    id: eDown
    !text: tr('v')
    font: verdana-11px-rounded
    anchors.right: ePages.left
    anchors.verticalCenter: parent.verticalCenter
    margin-right: 1
    width: 15
    height: 15
    tooltip: Move backpack down

  Button
    id: eUp
    !text: tr('^')
    font: verdana-11px-rounded
    anchors.right: eDown.left
    anchors.verticalCenter: parent.verticalCenter
    margin-right: 1
    width: 15
    height: 15
    tooltip: Move backpack up

CMUI < MainWindow
  !text: tr('Container Manager - By Sabuezo')
  font: verdana-11px-rounded
  size: 585 315
  @onEscape: self:hide()

  TextList
    id: containerList
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: separator.top
    width: 285
    margin-bottom: 6
    margin-top: 3
    margin-left: 3
    vertical-scrollbar: containerListScrollBar

  VerticalScrollBar
    id: containerListScrollBar
    anchors.top: containerList.top
    anchors.bottom: containerList.bottom
    anchors.right: containerList.right
    step: 14
    pixels-scroll: true

  VerticalSeparator
    id: sep
    anchors.top: parent.top
    anchors.left: containerList.right
    anchors.bottom: separator.top
    margin-top: 3
    margin-bottom: 6
    margin-left: 10

  Label
    id: lblName
    anchors.left: sep.right
    anchors.top: sep.top
    width: 70
    text: Name:
    margin-left: 10
    margin-top: 3
    font: verdana-11px-rounded

  TextEdit
    id: contName
    anchors.left: lblName.right
    anchors.top: sep.top
    anchors.right: parent.right
    font: verdana-11px-rounded

  Label
    id: lblCont
    anchors.left: lblName.left
    anchors.verticalCenter: contId.verticalCenter
    width: 70
    text: Container:
    font: verdana-11px-rounded

  BotItem
    id: contId
    anchors.left: contName.left
    anchors.top: contName.bottom
    margin-top: 3

  BotContainer
    id: sortList
    anchors.left: prev.left
    anchors.right: parent.right
    anchors.top: prev.bottom
    anchors.bottom: immortalSeparator.top
    margin-bottom: 6
    margin-top: 3

  Label
    anchors.left: lblCont.left
    anchors.verticalCenter: sortList.verticalCenter
    width: 70
    text: Items: 
    font: verdana-11px-rounded

  Button
    id: addContainer
    anchors.right: contName.right
    anchors.top: contName.bottom
    margin-top: 5
    text: Add
    width: 40
    font: verdana-11px-rounded
    color: green

  Button
    id: clear
    anchors.right: addContainer.left
    anchors.top: contName.bottom
    margin-top: 5
    margin-right: 5
    text: Clear
    width: 40
    font: verdana-11px-rounded
    color: red

  HorizontalSeparator
    id: immortalSeparator
    anchors.left: lblName.left
    anchors.right: parent.right
    anchors.bottom: inmortalSupplies.top
    margin-bottom: 4

  Panel
    id: inmortalSupplies
    anchors.left: lblName.left
    anchors.right: parent.right
    anchors.bottom: separator.top
    height: 54
    margin-bottom: 4

    Label
      id: immortalTitle
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: 17
      text: Inmortal BPs
      text-align: center
      color: #9dff9d
      font: verdana-11px-rounded

    Label
      id: mightLabel
      anchors.left: parent.left
      anchors.top: immortalTitle.bottom
      width: 58
      height: 32
      text: Might BP:
      text-align: left
      font: verdana-11px-rounded

    BotItem
      id: mightContainer
      anchors.left: mightLabel.right
      anchors.verticalCenter: mightLabel.verticalCenter
      size: 32 32
      tooltip: Backpack used for Might Rings

    Label
      id: ssaLabel
      anchors.left: parent.horizontalCenter
      anchors.top: immortalTitle.bottom
      width: 48
      height: 32
      text: SSA BP:
      text-align: left
      font: verdana-11px-rounded

    BotItem
      id: ssaContainer
      anchors.left: ssaLabel.right
      anchors.verticalCenter: ssaLabel.verticalCenter
      size: 32 32
      tooltip: Backpack used for Stone Skin Amulets

  HorizontalSeparator
    id: separator
    anchors.right: parent.right
    anchors.left: parent.left
    anchors.bottom: closeButton.top
    margin-bottom: 8

  CheckBox
    id: sortItems
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    text: Sort Items
    tooltip: Sort items based on items widget
    width: 95
    height: 15
    margin-top: 2
    margin-left: 3
    font: verdana-11px-rounded    

  CheckBox
    id: openBack
    anchors.left: prev.right
    anchors.bottom: parent.bottom
    text: Main BP
    tooltip: Open Main Backpack
    width: 70
    height: 15
    margin-top: 2
    margin-left: 3
    font: verdana-11px-rounded

  CheckBox
    id: openPurse
    anchors.left: prev.right
    anchors.bottom: parent.bottom
    text: Purse
    tooltip: Open Purse (id 23396)
    width: 60
    height: 15
    margin-top: 2
    margin-left: 15
    font: verdana-11px-rounded

  CheckBox
    id: reopenAtLogin
    anchors.left: prev.right
    anchors.bottom: parent.bottom
    text: ReOpen
    tooltip: Close and Reopen all containers at login or bot restart
    width: 70
    height: 15
    margin-top: 2
    margin-left: 15
    font: verdana-11px-rounded

  CheckBox
    id: openQuiver
    anchors.left: prev.right
    anchors.bottom: parent.bottom
    text: Quiver
    !tooltip: tr("Open Quiver (Container on hand or ammo slot)")
    width: 70
    height: 15
    margin-top: 2
    margin-left: 15
    font: verdana-11px-rounded

  Button
    id: closeButton
    !text: tr('Close')
    font: cipsoftFont
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    size: 45 21
    margin-top: 15
    font: verdana-11px-rounded

  Button
    id: credits
    !text: tr('Credits')
    font: cipsoftFont
    anchors.right: closeButton.left
    anchors.bottom: parent.bottom
    color: yellow
    size: 50 21
    margin-top: 15
    margin-right: 5
    font: verdana-11px-rounded    
    !tooltip: tr('Container Manager - By Sabuezo')

  ResizeBorder
    id: bottomResizeBorder
    anchors.fill: separator
    height: 3
    minimum: 170
    maximum: 310
    margin-left: 3
    margin-right: 3
    background: #ffffff88
]])

-- core functions
-- parse container list in a proper table
local cList = {}
local function parseContainerList()
  cList = {}
  for _, entry in ipairs(config.list) do
    if entry.eEnabled then
      table.insert(cList, entry.eId)
    end
  end
  return cList
end
parseContainerList()

-- parse list of sort items in a proper table
local sList = {}
local function parseSortItems()
  sList = {}
  for _, entry in ipairs(config.list) do
    if entry.eEnabled and entry.eItems then
      for _, item in ipairs(entry.eItems) do
        local id = type(item) == 'table' and item.id or item
        if id then
          sList[id] = entry.eId
        end
      end
    end
  end
  return sList
end
parseSortItems()

local function parseTables()
  parseContainerList()
  parseSortItems()
end

local function defaultBool(value, default)
  if value == nil then
    return default
  end
  return value
end

-- find container config by ID
local function findContainerConfig(id)
  for e, entry in ipairs(config.list) do
    if entry.eId == id then
      return e
    end
  end
  return false
end

-- UI FUNCTIONS
rootWidget = g_ui.getRootWidget()
if rootWidget then

  -- create CM Window
  CMUI = UI.createWindow('CMUI', rootWidget)
  CMUI:hide()

  -- panel buttons
  -- main 'settings/setup'
  CM.mainSetup.onClick = function(widget)
    CMUI:show()
    CMUI:raise()
    CMUI:focus()
  end

  -- reopen all
  CM.mainReopen.onClick = function(widget)
    reopenContainers()
  end

  -- minimize all
  CM.mainMinimize.onClick = function(widget)
    for i, container in pairs(g_game.getContainers()) do
      minimizeContainerAfterLayout(container)
    end
  end

  -- Full AFK
  CM.onFullAfk:setOn(config.onFullAfk)
  CM.onFullAfk.onClick = function(widget)
    config.onFullAfk = not config.onFullAfk
    widget:setOn(config.onFullAfk)
  end

  -- Qntd Full AFK
  CM.qtdFullAfk:setValue(config.qtdFullAfk)
  CM.qtdFullAfk.onValueChange = function(widget, value)
    config.qtdFullAfk = value
  end

  -- CM Window Buttons
  -- Close Window
  CMUI.closeButton.onClick = function(widget)
    CMUI:hide()
  end

  -- Sort Items
  CMUI.sortItems.onClick = function(widget)
    config.sortItems = not config.sortItems
    CMUI.sortItems:setChecked(config.sortItems)
  end
  CMUI.sortItems:setChecked(config.sortItems)

  -- Open Back
  CMUI.openBack.onClick = function(widget)
    config.openBack = not config.openBack
    CMUI.openBack:setChecked(config.openBack)
  end
  CMUI.openBack:setChecked(config.openBack)

  -- Open Purse
  CMUI.openPurse.onClick = function(widget)
    config.openPurse = not config.openPurse
    CMUI.openPurse:setChecked(config.openPurse)
  end
  CMUI.openPurse:setChecked(config.openPurse)
  
  -- Open Loot Bag
  CMUI.reopenAtLogin.onClick = function(widget)
    config.reopenAtLogin = not config.reopenAtLogin
    CMUI.reopenAtLogin:setChecked(config.reopenAtLogin)
  end
  CMUI.reopenAtLogin:setChecked(config.reopenAtLogin)

  -- Open Quiver
  CMUI.openQuiver.onClick = function(widget)
    config.openQuiver = not config.openQuiver
    CMUI.openQuiver:setChecked(config.openQuiver)
  end
  CMUI.openQuiver:setChecked(config.openQuiver)

  -- Inmortal supply backpacks
  CMUI.inmortalSupplies.mightContainer:setItemId(config.inmortalSupplies.mightContainerId)
  CMUI.inmortalSupplies.mightContainer.onItemChange = function(widget)
    config.inmortalSupplies.mightContainerId = widget:getItemId()
  end

  CMUI.inmortalSupplies.ssaContainer:setItemId(config.inmortalSupplies.ssaContainerId)
  CMUI.inmortalSupplies.ssaContainer.onItemChange = function(widget)
    config.inmortalSupplies.ssaContainerId = widget:getItemId()
  end

  -- Refresh Sort Items Panel
  local function refreshSortList(k, t)
    t = t or {}
    UI.Container(function()
      t = CMUI.sortList:getItems()
      if k then
        config.list[k].eItems = t
        parseTables()
      end
    end, true, nil, CMUI.sortList) 
    CMUI.sortList:setItems(t)
  end
  refreshSortList() -- create first empty panel

  -- Clear Errors
  local function clearErrors()
    CMUI.contName:setColor('white')
    CMUI.contName:setImageColor('#ffffff')
    CMUI.contId:setImageColor('#ffffff')
  end

  -- Containers List
  local refreshEntryList
  refreshEntryList = function(tFocus)
    if config.list and #config.list > 0 then
      -- Clear List
      CMUI.containerList:destroyChildren()
      -- Entry List
      for e, entry in ipairs(config.list) do
        local entryIndex = e
        local entryConfig = entry
        -- Entry Config
        local label = g_ui.createWidget("BackpackName", CMUI.containerList)
        label.onMouseRelease = function()
          clearErrors()
          CMUI.contId:setItemId(entryConfig.eId)
          CMUI.contName:setText(entryConfig.eName)
          entryConfig.eItems = entryConfig.eItems or {}
          -- CMUI.sortList:setItems(entry.eItems)
          refreshSortList(entryIndex, entryConfig.eItems)
        end
        -- Entry Enabled
        label.eEnabled.onClick = function(widget)
          entryConfig.eEnabled = not entryConfig.eEnabled
          label.eEnabled:setChecked(entryConfig.eEnabled)
          label.eEnabled:setImageColor(entryConfig.eEnabled and cGreen or cRed)
          parseTables()
        end
        -- Entry Remove
        label.eRemove.onClick = function(widget)
          table.remove(config.list, entryIndex)
          parseTables()
          refreshEntryList()
        end
        -- Entry Order
        label.eUp.onClick = function()
          if entryIndex <= 1 then return end
          config.list[entryIndex - 1], config.list[entryIndex] = config.list[entryIndex], config.list[entryIndex - 1]
          parseTables()
          refreshEntryList(entryIndex - 1)
        end
        label.eDown.onClick = function()
          if entryIndex >= #config.list then return end
          config.list[entryIndex + 1], config.list[entryIndex] = config.list[entryIndex], config.list[entryIndex + 1]
          parseTables()
          refreshEntryList(entryIndex + 1)
        end
        -- Entry Minimized
        label.eMinimize:setChecked(entryConfig.eMinimize)
        label.eMinimize.onClick = function(widget)
          entryConfig.eMinimize = not entryConfig.eMinimize
          label.eMinimize:setChecked(entryConfig.eMinimize)
          label.eMinimize:setColor(entryConfig.eMinimize and cGreen or cRed)
        end
        -- Entry OpenNext
        label.eOpenNext.onClick = function(widget)
          entryConfig.eOpenNext = not entryConfig.eOpenNext
          label.eOpenNext:setChecked(entryConfig.eOpenNext)
          label.eOpenNext:setColor(entryConfig.eOpenNext and cGreen or cRed)
          parseTables()
        end
        -- Entry Resize
        label.eResize.onClick = function(widget)
          entryConfig.eResize = not entryConfig.eResize
          label.eResize:setChecked(entryConfig.eResize)
          label.eResize:setColor(entryConfig.eResize and cGreen or cRed)
        end
        -- Entry Rename
        label.eRename.onClick = function(widget)
          entryConfig.eRename = not entryConfig.eRename
          label.eRename:setChecked(entryConfig.eRename)
          label.eRename:setColor(entryConfig.eRename and cGreen or cRed)
        end
        -- Entry Infinite
        label.eInfinite.onClick = function(widget)
          entryConfig.eInfinite = not entryConfig.eInfinite
          label.eInfinite:setChecked(entryConfig.eInfinite)
          label.eInfinite:setColor(entryConfig.eInfinite and cGreen or cRed)
        end
        -- Entry Open Next if Full
        label.eFull.onClick = function(widget)
          entryConfig.eFull = not entryConfig.eFull
          label.eFull:setChecked(entryConfig.eFull)
          label.eFull:setColor(entryConfig.eFull and cGreen or cRed)
        end
        -- Entry Pages
        label.ePages.onClick = function(widget)
          entryConfig.ePages = not entryConfig.ePages
          label.ePages:setChecked(entryConfig.ePages)
          label.ePages:setColor(entryConfig.ePages and cGreen or cRed)
        end
        -- Show Entry
        label:setText(entryConfig.eName)
        label.eEnabled:setChecked(entryConfig.eEnabled)
        label.eEnabled:setImageColor(entryConfig.eEnabled and cGreen or cRed)
        label.eMinimize:setColor(entryConfig.eMinimize and cGreen or cRed)
        label.eOpenNext:setColor(entryConfig.eOpenNext and cGreen or cRed)
        label.eRename:setColor(entryConfig.eRename and cGreen or cRed)
        label.eInfinite:setColor(entryConfig.eInfinite and cGreen or cRed)
        label.eFull:setColor(entryConfig.eFull and cGreen or cRed)
        label.ePages:setColor(entryConfig.ePages and cGreen or cRed)
        label.eResize:setColor(entryConfig.eResize and cGreen or cRed)
        label.eUp:setEnabled(entryIndex > 1)
        label.eDown:setEnabled(entryIndex < #config.list)

        -- Focus Entry
        if tFocus == entryIndex then
          CMUI.containerList:focusChild(label)
        end
      end
    end
  end
  refreshEntryList()

  -- Clear Panel
  local function clearPanel()
    clearErrors()
    CMUI.contId:setItemId(0)
    CMUI.contName:setText('')
    CMUI.sortList:setItems({})
    refreshSortList()
    refreshEntryList()
  end

  -- Add New Container / Save
  CMUI.addContainer.onClick = function(widget)
    clearErrors()
    local id = CMUI.contId:getItemId()
    local name = CMUI.contName:getText()
    local items = CMUI.sortList:getItems()

    -- is valid?
    if id > 100 and name:len() > 0 then
      local index = findContainerConfig(id)
      local c = index and config.list[index] or {}
      local t = {
        eId = id,
        eName = name,
        eEnabled = defaultBool(c.eEnabled, true),
        eMinimize = defaultBool(c.eMinimize, false),
        eOpenNext = defaultBool(c.eOpenNext, true),
        eRename = defaultBool(c.eRename, true),
        eInfinite = defaultBool(c.eInfinite, false),
        ePages = defaultBool(c.ePages, false),
        eFull = defaultBool(c.eFull, false),
        eResize = defaultBool(c.eResize, true),
        eItems = items or c.eItems or {},
      }
      
      if index then -- update entry
        config.list[index] = t
      else -- new entry
        table.insert(config.list,t)
      end
      refreshEntryList(index or #config.list)
      parseTables()
    else
      if id <= 100 then CMUI.contId:setImageColor('red') end
      if name:len() == 0 then 
        CMUI.contName:setImageColor('red')
        CMUI.contName:setColor('red')
      end
    end
  end

  -- Clear Button
  CMUI.clear.onClick = function(widget)
    clearPanel()
  end
  
  -- On Visibility Change, we update parsed tables
  CMUI.onVisibilityChange = function(widget, visible)
    parseTables()
  end
else
  warn(tag.."ERROR!")
end
-- End of UI Functions


-- Move item
local function moveItem(item, destination, index)
  local i = index or destination:getSlotPosition(destination:getItemsCount()+1)
  g_game.move(item, i, item:getCount())
end

local function getMainBackpackId()
  local slot = getBack()
  if slot and slot:isContainer() then
    return slot:getId()
  end
  return nil
end

local function isMainBackpackContainer(container)
  if not config.openBack or not container then return false end
  local mainId = getMainBackpackId()
  local containerItem = container:getContainerItem()
  return mainId and containerItem and containerItem:getId() == mainId
end

local function getQuiverSlots()
  return {getAmmo(), getLeft(), getRight()}
end

-- Check if main backpack is open
local function isMainOpened()
  local mainId = getMainBackpackId()
  if mainId and getContainerByItem(mainId) then
    return true
  end
  return false
end

-- Check if quiver is open
local function isQuiverOpened()
  local quiverId = nil
  local t = getQuiverSlots()
  for i=1,#t do
    local slot = t[i]
    if slot and slot:isContainer() then
      quiverId = slot:getId()
      break
    end
  end
  if quiverId and getContainerByItem(quiverId) then
    return true
  end
  return false
end

-- Open Main Containers: Back, Purse, Bag and Quiver
local function openMain()

  -- Open Main BackPack
  if config.openBack and not isMainOpened() then
    local back = getBack()
    if back and back:isContainer() then
      return g_game.use(back)
    end
  end

  -- Open Quiver
  if config.openQuiver and not isQuiverOpened() then
    local t = getQuiverSlots()
    for i=1,#t do
      local slot = t[i]
      if slot and slot:isContainer() then
        return g_game.use(slot)
      end
    end
  end

  -- Open Purse
  if config.openPurse and not getContainerByItem(purseId) then
    local purse = getPurse()
    if purse and purse:isContainer() then
      return g_game.use(purse)
    end
  end
  
end

-- Full AFK functions
-- Check if have enough opened containers to proceed
local function checkBps(noWarn)
  if table.size(g_game.getContainers()) < config.qtdFullAfk then 
    warn(tag.."Not Enough BPs.. Retrying")
    reopenContainers()
  else
    if not noWarn then
      warn(tag.."Enough BPs: Continue")
    end
    if config.pausedCave then
      CaveBot.setOn()
      config.pausedCave = false
    end
  end
end

-- Pause CaveBot to reopen containers
local function pauseAfk()
  if CaveBot.isOn() then
    CaveBot.setOff()
    config.pausedCave = true
  end

  checkBps()
end

-- Open Next Table
local containersToOpen = {}
-- Containers with pages table
local pageContainers = {}
local supplyRequestAfter = {}

local function getContainerItemId(container)
  if not container then return nil end
  local containerItem = container:getContainerItem()
  return containerItem and containerItem:getId() or nil
end

local function getOrderedOpenContainers()
  local containers = {}

  for _, container in pairs(g_game.getContainers()) do
    if not container.lootContainer then
      table.insert(containers, container)
    end
  end

  table.sort(containers, function(a, b)
    local aId = getContainerItemId(a)
    local bId = getContainerItemId(b)
    local aIndex = isMainBackpackContainer(a) and 0 or (findContainerConfig(aId) or getExplicitSupplyPriority(aId) or 10000)
    local bIndex = isMainBackpackContainer(b) and 0 or (findContainerConfig(bId) or getExplicitSupplyPriority(bId) or 10000)
    return aIndex < bIndex
  end)

  return containers
end

local function queueContainerToOpen(item)
  if not item then return false end
  local id = item:getId()
  local index = findContainerConfig(id)
  local explicitPriority = getExplicitSupplyPriority(id)
  if not index and not explicitPriority then return false end
  local settings = index and config.list[index] or nil
  if settings and not settings.eEnabled and not explicitPriority then return false end
  if getContainerByItem(id) then return false end

  for _, queued in ipairs(containersToOpen) do
    if queued.item == item then
      return false
    end
  end

  local queued = {
    item = item,
    id = id,
    priority = index or explicitPriority
  }
  local insertAt = #containersToOpen + 1

  for position, current in ipairs(containersToOpen) do
    if queued.priority < current.priority then
      insertAt = position
      break
    end
  end

  table.insert(containersToOpen, insertAt, queued)
  return true
end

local function queueConfiguredContainersFrom(container)
  if not container or container.lootContainer then return false end
  local queued = false

  for _, item in ipairs(container:getItems()) do
    if queueContainerToOpen(item) then
      queued = true
    end
  end

  return queued
end

-- Reopen Containers (this one must be Global)
function reopenContainers()
  if cManager:isOff() then return end
  containersToOpen = {}
  pageContainers = {}
  for _, cont in pairs(g_game.getContainers()) do g_game.close(cont) end
  if config.onFullAfk then 
    schedule((config.qtdFullAfk + 2) * defaultDelay, function()
      pauseAfk()
    end)
  end
  schedule(defaultDelay * 2,function()
    openMain()
  end)
end

local function findContainerItem(container, containerId)
  if not container then return nil end

  for _, item in ipairs(container:getItems()) do
    if item:getId() == containerId and (not item.isContainer or item:isContainer()) then
      return item
    end
  end

  return nil
end

local function openedContainersHaveItem(itemId)
  for _, container in ipairs(getOrderedOpenContainers()) do
    for _, item in ipairs(container:getItems()) do
      if item:getId() == itemId then
        return true
      end
    end
  end

  return false
end

local function openNextSupplyContainer(itemId, hintedContainerId, relatedItemIds, supplyKey)
  itemId = tonumber(itemId)
  if not itemId or itemId <= 0 or cManager:isOff() then return false end
  if openedContainersHaveItem(itemId) then return false end

  local explicitContainerId = getExplicitSupplyContainerId(supplyKey)
  local hasExplicitContainer = explicitContainerId and explicitContainerId > 100
  local targetContainerId = hasExplicitContainer and explicitContainerId or (sList[itemId] or tonumber(hintedContainerId))

  if not targetContainerId and type(relatedItemIds) == "table" then
    for _, relatedItemId in ipairs(relatedItemIds) do
      targetContainerId = sList[tonumber(relatedItemId)]
      if targetContainerId then break end
    end
  end

  local targetIndex = targetContainerId and findContainerConfig(targetContainerId) or false
  local settings = targetIndex and config.list[targetIndex] or nil

  if not hasExplicitContainer and (not settings or not settings.eEnabled or not settings.eOpenNext) then return false end

  local time = now or 0
  if time < (supplyRequestAfter[itemId] or 0) then return true end
  supplyRequestAfter[itemId] = time + 1000

  local current = getContainerByItem(targetContainerId)
  local nextItem = findContainerItem(current, targetContainerId)

  if nextItem then
    g_game.open(nextItem, current)
    return true
  end

  for _, source in ipairs(getOrderedOpenContainers()) do
    if source ~= current then
      nextItem = findContainerItem(source, targetContainerId)
      if nextItem then
        g_game.open(nextItem, current)
        return true
      end
    end
  end

  return false
end

ContainerManager = ContainerManager or {}
ContainerManager.requestItemContainer = openNextSupplyContainer
ContainerManager.getOrder = function()
  local order = {}
  for index, entry in ipairs(config.list) do
    order[index] = entry.eId
  end
  return order
end

onContainerOpen(function(container, previousContainer)
  if cManager:isOff() then return end
  if container.lootContainer then return end
  local cId = container:getContainerItem():getId()
  local isMainSource = isMainBackpackContainer(container)
  local index = findContainerConfig(cId)
  local explicitRole = getExplicitSupplyRole(cId)
  if not index and not isMainSource and not explicitRole then return end
  local settings = index and config.list[index] or {
    eEnabled = true,
    eOpenNext = true,
    eResize = false,
    eRename = false,
    eMinimize = false,
    ePages = false
  }
  if not settings.eEnabled and not explicitRole then return end

  if not container.window then return end
  local cWindow = container.window
  if settings.eResize then resizeContainerAfterLayout(container) end
  if isMainSource then
    cWindow:setText("Main Bp")
  elseif explicitRole and not index then
    cWindow:setText(explicitRole)
  elseif settings.eRename then
    cWindow:setText(settings.eName)
  end
  if settings.eMinimize then minimizeContainerAfterLayout(container) end

  -- auto next page
  if settings.ePages and container:hasPages() then
    local nextPageButton = container.window:recursiveGetChildById('nextPageButton')
    if nextPageButton then 
      table.insert(pageContainers,container)
    end
  end

  if settings.eOpenNext or explicitRole then
    queueConfiguredContainersFrom(container)
  end
end)

-- Containers with pages
local nextPageMacro = macro(defaultDelay * 2, function()
  if cManager:isOff() then return end
  for c, container in pairs(pageContainers) do
    if container.window and container:hasPages() then
      local nextPageButton = container.window:recursiveGetChildById('nextPageButton')
      if nextPageButton then nextPageButton.onClick() end
    else
      table.remove(pageContainers,c)
    end
  end
end)

-- Containers to be opened
local openNextMacro = macro(defaultDelay,function()
  if cManager:isOff() then return end

  while #containersToOpen > 0 do
    local entry = table.remove(containersToOpen, 1)
    if entry.item and not getContainerByItem(entry.id) then
      g_game.open(entry.item, nil)
      return delay(defaultDelay + 5)
    end
  end

  local openContainers = getOrderedOpenContainers()
  for _, container in ipairs(openContainers) do
    local containerId = getContainerItemId(container)
    local containerIndex = findContainerConfig(containerId)
    local containerSettings = containerIndex and config.list[containerIndex] or nil
    local shouldOpenInside = containerSettings and containerSettings.eEnabled and
      containerSettings.eOpenNext or getExplicitSupplyRole(containerId)
    if shouldOpenInside and queueConfiguredContainersFrom(container) then
      return delay(defaultDelay + 5)
    end
  end

  if #openContainers == 0 then openMain() end
end)

local sortItemsMacro = macro(defaultDelay, function(m)
  if cManager:isOn() and config.sortItems then
    for c, cont in pairs(g_game.getContainers()) do
      if not cont.lootContainer then
        local containerItem = cont:getContainerItem()
        local srcId = containerItem and containerItem:getId() or 0
        for i, item in ipairs(cont:getItems()) do
          local toId = sList[item:getId()]
          if toId and toId ~= srcId then
            local toIndex = findContainerConfig(toId)
            if toIndex then
              local toConfig = config.list[toIndex]
              if toConfig and toConfig.eEnabled then
                local destNotFull = getContainerByItem(toId, not toConfig.eInfinite)
                if destNotFull then
                  return moveItem(item,destNotFull,toConfig.eInfinite and 0 or nil)
                elseif toConfig.eFull then
                  local destFull = getContainerByItem(toId)
                  if destFull then
                    for n, newCont in ipairs(destFull:getItems()) do
                      if newCont:getId() == toId then
                        return g_game.open(newCont,destFull)
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end)

-- Full AFK loop
macro(20000,function()
  if cManager.isOn() and config.onFullAfk then
    checkBps(true)
	  delay(config.qtdFullAfk * defaultDelay)
  end
end)

if cManager.isOn() and config.reopenAtLogin then reopenContainers() end
