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
        eOpenNextEmpty = false,
        eRename = true,
        eResize = true,
        eItems = { 3027, 3028, 3029, 3030 },
      }
    }
  }
end
local config = storage[panelName]
if config.rememberPositions == nil then config.rememberPositions = true end
local layout
if type(config.inmortalSupplies) ~= "table" then
  config.inmortalSupplies = {}
end
config.inmortalSupplies.mightContainerId = tonumber(config.inmortalSupplies.mightContainerId) or 0
config.inmortalSupplies.ssaContainerId = tonumber(config.inmortalSupplies.ssaContainerId) or 0

-- Deposit-only entries override Container Manager's automatic opening paths.
-- Other engines keep their own explicit supply-recovery policy.
local function depositsWithoutOpening(id)
  for _,entry in ipairs(config.list)do
    if entry.eId==id then return entry.eDepositClosed==true end
  end
  return false
end

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

local openingsPaused,openingsPauseReason=false,nil
local CM
local function currentContainerWindow(container, expectedWindow)
  if cManager:isOff() or openingsPaused or not container or not expectedWindow or container.window ~= expectedWindow then return end
  if (g_game.getContainers() or {})[container:getId()] ~= container then return end
  if expectedWindow.isDestroyed then
    local ok, destroyed = pcall(function() return expectedWindow:isDestroyed() end)
    if not ok or destroyed then return end
  end
  return expectedWindow
end

-- A single manual/server Close is normal. Only repeated rapid closes following
-- distinct openings requested by this manager can stop automatic opening.
local cancelAutomaticOpening
local resetOpeningRetries
local batchClosing,managedWindows={},{}
local openingEvents={}
local openingOperation,openingActivity=0,nil
local openingCloseStrikes={}
local managerObservedOff=false
local rapidCloseWindow,closePatternWindow,closePatternLimit=4000,12000,3
local function updateOpeningStatus()
  local button=CM and CM.mainReopen
  if button then
    if type(button.setTooltip)=='function'then
      pcall(function()button:setTooltip(openingsPaused and
        ('Aperturas pausadas: '..tostring(openingsPauseReason)..'\nReanuda con OFF/ON del gestor o Re-Open All.') or
        'Re-Open All: reconstruir las mochilas configuradas y reanudar aperturas.')end)
    end
    if type(button.setText)=='function'then
      pcall(function()button:setText(openingsPaused and'Reanudar BPs' or'Re-Open All')end)
    end
  end
end
local function openingDiagnostic(event,item,reason,container)
  local position=item and item.getPosition and item:getPosition()
  local entry={at=now or 0,event=event,reason=reason}
  if item then entry.itemId=item:getId() end
  if position then entry.position={x=position.x,y=position.y,z=position.z}end
  if container then entry.containerId=container:getId()end
  openingEvents[#openingEvents+1]=entry
  while #openingEvents>30 do table.remove(openingEvents,1)end
  if type(g_resources)~='table' or type(g_resources.makeDir)~='function' or
    type(g_resources.writeFileContents)~='function' or type(json)~='table' or type(json.encode)~='function' then return end
  local base=type(configDir)=='string' and configDir:gsub('\\','/'):gsub('/+$','')
  if not base or not base:match('^/bot/[^/]+$') or base:find('..',1,true)then return end
  pcall(function()
    local path=base..'/_diagnostics'
    g_resources.makeDir(path)
    g_resources.writeFileContents(path..'/container-manager-state.json',json.encode({revision='R150',
      openingsPaused=openingsPaused,reason=openingsPauseReason,rapidCloseOperations=#openingCloseStrikes,events=openingEvents},2))
  end)
end
local function pauseAutomaticOpening(reason,item,container)
  if openingsPaused then return end
  openingsPaused,openingsPauseReason=true,reason
  if cancelAutomaticOpening then cancelAutomaticOpening()end
  updateOpeningStatus()
  openingDiagnostic('paused',item,reason,container)
  if type(info)=='function'then info('[Container Manager R150] Aperturas pausadas: '..reason..'. Reanuda con OFF/ON o Re-Open All.')end
end
local function resumeAutomaticOpening(reason)
  local paused=openingsPaused
  openingsPaused,openingsPauseReason=false,nil
  openingActivity,openingCloseStrikes=nil,{}
  managerObservedOff=false
  if resetOpeningRetries then resetOpeningRetries()end
  updateOpeningStatus()
  openingDiagnostic('resumed',nil,reason)
  if paused and type(info)=='function'then info('[Container Manager R150] Aperturas reanudadas: '..reason..'.')end
end
local function observeManagerSwitch()
  if cManager:isOff()then managerObservedOff=true;return false end
  if managerObservedOff then resumeAutomaticOpening('OFF/ON del gestor')end
  return true
end
local function recordRapidClose(item,container)
  local time=now or 0
  for i=#openingCloseStrikes,1,-1 do
    if time-openingCloseStrikes[i].at>closePatternWindow then table.remove(openingCloseStrikes,i)end
  end
  if cManager:isOff()or not openingActivity or time-openingActivity.at>rapidCloseWindow then return end
  for _,strike in ipairs(openingCloseStrikes)do
    if strike.operation==openingActivity.operation then return end
  end
  openingCloseStrikes[#openingCloseStrikes+1]={operation=openingActivity.operation,at=time}
  openingDiagnostic('rapid_close',item,'Apertura propia '..openingActivity.operation..'; '..#openingCloseStrikes..'/'..closePatternLimit,container)
  if #openingCloseStrikes>=closePatternLimit then
    pauseAutomaticOpening('3 operaciones distintas de apertura seguidas de cierre en 12 s',item,container)
  end
end

-- The new client can resize a container after onContainerOpen finishes. Reapply
-- minimize after layout settles so a hidden content panel cannot keep full height.
local function containerWindowIsMinimized(cWindow)
  if not cWindow then return false end
  for _,method in ipairs({'isMinimized','isOn'})do
    if type(cWindow[method])=='function'then
      local ok,value=pcall(function()return cWindow[method](cWindow)end)
      if ok then return value==true end
    end
  end
  return false
end
local function minimizeContainerAfterLayout(container)
  local expectedWindow = container and container.window
  local function getWindow()
    return currentContainerWindow(container, expectedWindow)
  end

  local function isMinimized(cWindow)
    return containerWindowIsMinimized(cWindow)
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
    -- maximize() calls the native sidebar fitAll and can close another BP.
    -- Reapply only minimize(), preserving the expanded height it overwrites.
    local expandedHeight=cWindow.maximizedHeight
    local minimizedHeight=tonumber(cWindow.minimizedHeight)or 0
    if (not tonumber(expandedHeight)or tonumber(expandedHeight)<=minimizedHeight)and type(cWindow.getSettings)=='function'then
      local ok,saved=pcall(function()return cWindow:getSettings('height')end)
      if ok and tonumber(saved)and tonumber(saved)>minimizedHeight then expandedHeight=tonumber(saved)end
    end
    if cWindow.minimize then
      pcall(function() cWindow:minimize() end)
      cWindow.maximizedHeight=expandedHeight
    end
  end

  schedule(50, applyInitialMinimize)
  schedule(defaultDelay + 50, settleMinimizedLayout)
end

local function resizeContainerAfterLayout(container)
  local expectedWindow = container and container.window
  local function applyResize()
    local cWindow = currentContainerWindow(container, expectedWindow)
    if not cWindow then return end
    if containerWindowIsMinimized(cWindow)then return end
    if cWindow.setContentHeight then
      local requested=34 -- Legacy clients without measurable content geometry.
      pcall(function()
        local panel=cWindow:getChildById('contentsPanel')
        local grid=panel and panel:getLayout()
        local cell=grid and grid:getCellSize()
        if not cell or not tonumber(cell.height) then return end
        local row=cell.height+(grid.getCellSpacing and tonumber(grid:getCellSpacing())or 0)
        local padding=panel:getPaddingTop()+panel:getPaddingBottom()
        -- New forks anchor content below a separate title bar and above the
        -- pager. Its margins no longer include that chrome. setContentHeight
        -- still only adds margins/padding, so passing 34 can leave 2px of items.
        local target=cWindow:getHeight()-panel:getHeight()+padding+row
        if cWindow.getMinimumHeight then target=math.max(target,cWindow:getMinimumHeight())end
        requested=math.max(1,target-panel:getMarginTop()-panel:getMarginBottom()-padding)
      end)
      pcall(function() cWindow:setContentHeight(requested) end)
    end
  end

  applyResize()
  schedule(50, applyResize)
  schedule(defaultDelay + 50, applyResize)
end

-- UI
CM = setupUI([[
Panel
  height: 36

  HelperThemePower
    id: onFullAfk
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 90
    height: 17
    !text: tr('Full AFK:')
    tooltip: Stop cavebot to reopen BPs and how many BPs should be open to proceed caveboting.

  HelperThemeSpin
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

  HelperThemeButton
    id: mainSetup
    anchors.top: onFullAfk.top
    anchors.left: prev.right
    margin-top: -1
    anchors.right: parent.right
    margin-left: 3
    height: 18
    text: Setup

  HelperThemeButton
    id: mainReopen
    !text: tr('Re-Open All')
    anchors.left: parent.left
    anchors.top: prev.bottom
    anchors.right: parent.horizontalCenter
    margin-right: 2
    height: 17
    margin-top: 3

  HelperThemeButton
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
BackpackName < HelperThemeLabel
  background-color: alpha
  text-offset: 18 2
  focusable: true
  height: 17
  font: verdana-11px-antialised

  HelperThemeCheck
    id: eEnabled
    anchors.left: parent.left
    anchors.top: parent.top
    width: 15
    height: 15
    margin-top: 1
    margin-left: 3

  $focus:
    background-color: #00000055

  HelperThemeButton
    id: eRemove
    !text: tr('X')
    font: verdana-11px-antialised
    !tooltip: tr('Remove')
    anchors.right: parent.right
    anchors.top: parent.top
    margin-top: 1
    margin-right: 15
    width: 15
    height: 15

  HelperThemeButton
    id: eMinimize
    !text: tr('M')
    font: verdana-11px-antialised
    anchors.right: eDepositClosed.left
    anchors.top: parent.top
    margin-top: 1
    margin-right: 1
    width: 15
    height: 15
    tooltip: Open Container Minimized

  HelperThemeButton
    id: eOpenNext
    !text: tr('O')
    font: verdana-11px-antialised
    anchors.right: eMinimize.left
    anchors.top: parent.top
    margin-top: 1
    margin-right: 1
    width: 15
    height: 15
    tooltip: Open Containers inside

  HelperThemeButton
    id: eOpenNextEmpty
    !text: tr('V')
    font: verdana-11px-antialised
    anchors.right: eOpenNext.left
    anchors.top: parent.top
    margin-top: 1
    margin-right: 1
    width: 15
    height: 15
    tooltip: Abrir la siguiente BP solo cuando quede esa BP dentro. Tiene prioridad sobre O y F.

  HelperThemeButton
    id: eResize
    !text: tr('S')
    font: verdana-11px-antialised
    anchors.right: eOpenNextEmpty.left
    anchors.top: parent.top
    margin-top: 1
    margin-right: 1
    width: 15
    height: 15
    tooltip: Resize Container (Open Small)

  HelperThemeButton
    id: eRename
    !text: tr('N')
    font: verdana-11px-antialised
    anchors.right: eResize.left
    anchors.top: parent.top
    margin-top: 1
    margin-right: 1
    width: 15
    height: 15
    tooltip: Rename Container

  HelperThemeButton
    id: eInfinite
    !text: tr('I')
    font: verdana-11px-antialised
    anchors.right: eRename.left
    anchors.top: parent.top
    margin-top: 1
    margin-right: 1
    width: 15
    height: 15
    tooltip: Inifinite Container: Move items even if it's full

  HelperThemeButton
    id: eFull
    !text: tr('F')
    font: verdana-11px-antialised
    anchors.right: eInfinite.left
    anchors.top: parent.top
    margin-top: 1
    margin-right: 1
    width: 15
    height: 15
    tooltip: Open Next Container (same id) only when it's full

  HelperThemeButton
    id: ePages
    !text: tr('P')
    font: verdana-11px-antialised
    anchors.right: eFull.left
    anchors.top: parent.top
    margin-top: 1
    margin-right: 1
    width: 15
    height: 15
    tooltip: Auto Next Page Container

  HelperThemeButton
    id: eDown
    !text: tr('v')
    font: verdana-11px-antialised
    anchors.right: ePages.left
    anchors.top: parent.top
    margin-top: 1
    margin-right: 1
    width: 15
    height: 15
    tooltip: Move backpack down

  HelperThemeButton
    id: eUp
    !text: tr('^')
    font: verdana-11px-antialised
    anchors.right: eDown.left
    anchors.top: parent.top
    margin-top: 1
    margin-right: 1
    width: 15
    height: 15
    tooltip: Move backpack up

  HelperThemeButton
    id: eDepositClosed
    text: C
    font: verdana-11px-antialised
    anchors.right: eRemove.left
    anchors.top: parent.top
    margin-top: 1
    margin-right: 1
    width: 15
    height: 15
    tooltip: Guardar con BP cerrada.

CMUI < HelperThemeWindow
  !text: tr('Container Manager - By Sabuezo')
  font: verdana-11px-antialised
  size: 601 345
  @onEscape: self:hide()

  HelperThemeList
    id: containerList
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: rememberPositions.top
    width: 301
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

  HelperThemeCheck
    id: rememberPositions
    anchors.left: parent.left
    anchors.bottom: separator.top
    margin-left: 3
    width: 190
    height: 15
    margin-bottom: 6
    text: Recordar posiciones
    tooltip: Guarda el panel y orden de cada BP al arrastrarla y los restaura al reabrir o reloguear.
    font: verdana-11px-antialised

  VerticalSeparator
    id: sep
    anchors.top: parent.top
    anchors.left: containerList.right
    anchors.bottom: separator.top
    margin-top: 3
    margin-bottom: 6
    margin-left: 10

  HelperThemeLabel
    id: lblName
    anchors.left: sep.right
    anchors.top: sep.top
    width: 70
    text: Name:
    margin-left: 10
    margin-top: 3
    font: verdana-11px-antialised

  HelperThemeInput
    id: contName
    anchors.left: lblName.right
    anchors.top: sep.top
    anchors.right: parent.right
    font: verdana-11px-antialised

  HelperThemeLabel
    id: lblCont
    anchors.left: lblName.left
    anchors.verticalCenter: contId.verticalCenter
    width: 70
    text: Container:
    font: verdana-11px-antialised

  BotItem
    id: contId
    anchors.left: contName.left
    anchors.top: contName.bottom
    margin-top: 3

  BotContainer
    id: sortList
    anchors.left: contId.left
    anchors.right: parent.right
    anchors.top: contId.bottom
    anchors.bottom: immortalSeparator.top
    margin-bottom: 6
    margin-top: 3

  HelperThemeLabel
    anchors.left: lblCont.left
    anchors.verticalCenter: sortList.verticalCenter
    width: 70
    text: Items: 
    font: verdana-11px-antialised

  HelperThemeButton
    id: addContainer
    anchors.right: contName.right
    anchors.top: contName.bottom
    margin-top: 5
    text: Add
    width: 40
    font: verdana-11px-antialised
    color: green

  HelperThemeButton
    id: clear
    anchors.right: addContainer.left
    anchors.top: contName.bottom
    margin-top: 5
    margin-right: 5
    text: Clear
    width: 40
    font: verdana-11px-antialised
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

    HelperThemeLabel
      id: immortalTitle
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: 17
      text: Inmortal BPs
      text-align: center
      color: #9dff9d
      font: verdana-11px-antialised

    HelperThemeLabel
      id: mightLabel
      anchors.left: parent.left
      anchors.top: immortalTitle.bottom
      width: 58
      height: 32
      text: Might BP:
      text-align: left
      font: verdana-11px-antialised

    BotItem
      id: mightContainer
      anchors.left: mightLabel.right
      anchors.verticalCenter: mightLabel.verticalCenter
      size: 32 32
      tooltip: Backpack used for Might Rings

    HelperThemeLabel
      id: ssaLabel
      anchors.left: parent.horizontalCenter
      anchors.top: immortalTitle.bottom
      width: 48
      height: 32
      text: SSA BP:
      text-align: left
      font: verdana-11px-antialised

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

  HelperThemeCheck
    id: sortItems
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    text: Sort Items
    tooltip: Sort items based on items widget
    width: 95
    height: 15
    margin-top: 2
    margin-left: 3
    font: verdana-11px-antialised    

  HelperThemeCheck
    id: openBack
    anchors.left: prev.right
    anchors.bottom: parent.bottom
    text: Main BP
    tooltip: Open Main Backpack
    width: 70
    height: 15
    margin-top: 2
    margin-left: 3
    font: verdana-11px-antialised

  HelperThemeCheck
    id: openPurse
    anchors.left: prev.right
    anchors.bottom: parent.bottom
    text: Purse
    tooltip: Open Purse (id 23396)
    width: 60
    height: 15
    margin-top: 2
    margin-left: 15
    font: verdana-11px-antialised

  HelperThemeCheck
    id: reopenAtLogin
    anchors.left: prev.right
    anchors.bottom: parent.bottom
    text: ReOpen
    tooltip: Close and Reopen all containers at login or bot restart
    width: 70
    height: 15
    margin-top: 2
    margin-left: 15
    font: verdana-11px-antialised

  HelperThemeCheck
    id: openQuiver
    anchors.left: prev.right
    anchors.bottom: parent.bottom
    text: Quiver
    !tooltip: tr("Open Quiver (Container on hand or ammo slot)")
    width: 70
    height: 15
    margin-top: 2
    margin-left: 15
    font: verdana-11px-antialised

  HelperThemeButton
    id: closeButton
    !text: tr('Close')
    font: verdana-11px-antialised
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    size: 45 21
    margin-top: 15
    font: verdana-11px-antialised

  HelperThemeButton
    id: credits
    !text: tr('Credits')
    font: verdana-11px-antialised
    anchors.right: closeButton.left
    anchors.bottom: parent.bottom
    color: yellow
    size: 50 21
    margin-top: 15
    margin-right: 5
    font: verdana-11px-antialised    
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
  updateOpeningStatus()

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

  CMUI.rememberPositions:setChecked(config.rememberPositions)
  CMUI.rememberPositions.onClick = function(widget)
    config.rememberPositions = not config.rememberPositions
    widget:setChecked(config.rememberPositions)
    if layout then layout.reset() end
  end

  -- Inmortal supply backpacks
  HelperClientCompat.setItemIdForDisplay(CMUI.inmortalSupplies.mightContainer,config.inmortalSupplies.mightContainerId)
  CMUI.inmortalSupplies.mightContainer.onItemChange = function(widget)
    config.inmortalSupplies.mightContainerId = HelperClientCompat.itemIdFromWidget(widget)
  end

  HelperClientCompat.setItemIdForDisplay(CMUI.inmortalSupplies.ssaContainer,config.inmortalSupplies.ssaContainerId)
  CMUI.inmortalSupplies.ssaContainer.onItemChange = function(widget)
    config.inmortalSupplies.ssaContainerId = HelperClientCompat.itemIdFromWidget(widget)
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

  local depositDraft=false
  local depositRows={}
  local function syncDeposit(entry)
    depositDraft=entry and entry.eDepositClosed==true or false
  end
  local function syncDepositRow(entry)
    local widget=depositRows[entry]
    if widget then
      widget:setChecked(entry.eDepositClosed==true)
      widget:setColor(entry.eDepositClosed==true and cGreen or cRed)
    end
  end
  local function setDepositClosed(entry,enabled)
    entry.eDepositClosed=enabled==true
    syncDepositRow(entry)
    if HelperClientCompat.itemIdFromWidget(CMUI.contId)==entry.eId then syncDeposit(entry) end
    parseTables()
  end
  CMUI.contId.onItemChange=function(widget)
    local index=findContainerConfig(HelperClientCompat.itemIdFromWidget(widget))
    syncDeposit(index and config.list[index])
  end
  syncDeposit()

  -- Containers List
  local refreshEntryList
  refreshEntryList = function(tFocus)
    depositRows={}
    -- Also clear the last removed entry; no stale row toggle may survive it.
    CMUI.containerList:destroyChildren()
    if config.list and #config.list > 0 then
      -- Entry List
      for e, entry in ipairs(config.list) do
        local entryIndex = e
        local entryConfig = entry
        -- Entry Config
        local label = g_ui.createWidget("BackpackName", CMUI.containerList)
        depositRows[entryConfig]=label.eDepositClosed
        syncDepositRow(entryConfig)
        label.eDepositClosed.onClick=function()
          setDepositClosed(entryConfig,entryConfig.eDepositClosed~=true)
          return true
        end
        label.onMouseRelease = function()
          clearErrors()
          HelperClientCompat.setItemIdForDisplay(CMUI.contId,entryConfig.eId)
          CMUI.contName:setText(entryConfig.eName)
          syncDeposit(entryConfig)
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
        -- Entry Open Next When Empty
        label.eOpenNextEmpty:setChecked(entryConfig.eOpenNextEmpty == true)
        label.eOpenNextEmpty.onClick = function(widget)
          entryConfig.eOpenNextEmpty = not entryConfig.eOpenNextEmpty
          label.eOpenNextEmpty:setChecked(entryConfig.eOpenNextEmpty)
          label.eOpenNextEmpty:setColor(entryConfig.eOpenNextEmpty and cGreen or cRed)
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
        label.eOpenNextEmpty:setColor(entryConfig.eOpenNextEmpty and cGreen or cRed)
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
    HelperClientCompat.setItemIdForDisplay(CMUI.contId,0)
    CMUI.contName:setText('')
    syncDeposit()
    CMUI.sortList:setItems({})
    refreshSortList()
    refreshEntryList()
  end

  -- Add New Container / Save
  CMUI.addContainer.onClick = function(widget)
    clearErrors()
    local id = HelperClientCompat.itemIdFromWidget(CMUI.contId)
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
        eOpenNextEmpty = defaultBool(c.eOpenNextEmpty, false),
        eDepositClosed = depositDraft,
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
  local i = destination:getSlotPosition(index or destination:getItemsCount())
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
  
  if mainId and containerItem and containerItem:getId() == mainId then
    local pos = type(containerItem.getPosition) == 'function' and containerItem:getPosition()
    -- EXIGIR que la coordenada exista y sea de inventario (< 64)
    if pos and pos.y and pos.y < 64 then
      return true
    end
    return false
  end
  return false
end
local function getQuiverSlots()
  local slots={}
  for _,getter in ipairs({getAmmo or false,getLeft or false,getRight or false})do
    if type(getter)=='function' then local item=getter();if item then slots[#slots+1]=item end end
  end
  return slots
end

layout = ContainerLayout.create(config, function() return cManager:isOn() and not openingsPaused end, function(container)
  if container.lootContainer then return nil end
  local item = container:getContainerItem()
  local id = item and item:getId()
  if not id then return nil end
  local index = findContainerConfig(id)
  local managed = index and config.list[index].eEnabled or
    isMainBackpackContainer(container) or (config.openPurse and id == purseId) or
    getExplicitSupplyRole(id)
  if not managed and config.openQuiver then
    for _, slot in pairs(getQuiverSlots()) do
      if slot and slot:isContainer() and slot:getId() == id then managed = true; break end
    end
  end
  return managed and ("bp:"..id) or nil
end)
local oldPanelDestroy = CM.onDestroy
CM.onDestroy = function(...)
  layout.cleanup()
  if type(oldPanelDestroy) == "function" then oldPanelDestroy(...) end
end
if type(onContainerClose) == "function" then
  onContainerClose(function(container) layout.closed(container) end)
end

-- Check if main backpack is open
local isItemContainerOpen,isInitialContainerSource
local function isMainOpened()
  return isItemContainerOpen(getBack())
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
  if quiverId then
    for _,slot in pairs(t)do
      if slot and slot:isContainer() then return isItemContainerOpen(slot) end
    end
  end
  return false
end

local mainOpenAfter = 0
local requestContainerOpen,resolveContainerOpen,resetContainerOpening,isOpeningFrom
local reopenGeneration=0

local function useMainContainer(item)
  if not item or depositsWithoutOpening(item:getId()) then return false end

  local time = now or 0
  if time < mainOpenAfter then return false end
  mainOpenAfter = time + (defaultDelay * 2)
  return requestContainerOpen(item, nil, true)
end

local function getPurseItem()
  if type(getPurse) == "function" then
    local ok, item = pcall(getPurse)
    if ok and item then return item end
  end

  local player = g_game.getLocalPlayer()
  local purseSlot = InventorySlotPurse or SlotPurse or 11
  if not player or not player.getInventoryItem then return nil end

  local ok, item = pcall(function()
    return player:getInventoryItem(purseSlot)
  end)
  return ok and item or nil
end

-- A type ID alone is not permission to open every copy carried by the player.
-- Equipped roots are authorized by their own switches, nested BPs by an
-- enabled rule or an explicit Inmortal supply assignment.
local function authorizedContainerItem(item)
  if not item or not item.isContainer or not item:isContainer() or depositsWithoutOpening(item:getId()) then return false end
  if config.openBack and getBack() == item then return true end
  if config.openPurse and getPurseItem() == item then return true end
  if config.openQuiver then
    for _,slot in pairs(getQuiverSlots())do if slot == item then return true end end
  end
  local index = findContainerConfig(item:getId())
  return index and config.list[index].eEnabled == true or getExplicitSupplyRole(item:getId()) ~= nil
end

-- Open Main Containers: Back, Purse, Bag and Quiver
local function openMain()
  if openingsPaused then return false end

  -- Open Main BackPack
  if config.openBack and not isMainOpened() then
    local back = getBack()
    if back and back:isContainer() and not depositsWithoutOpening(back:getId()) then
      return useMainContainer(back)
    end
  end

  -- Open Quiver
  if config.openQuiver and not isQuiverOpened() then
    local t = getQuiverSlots()
    for i=1,#t do
      local slot = t[i]
      if slot and slot:isContainer() and not depositsWithoutOpening(slot:getId()) then
        return useMainContainer(slot)
      end
    end
  end

  -- Open Purse
  local purse = config.openPurse and getPurseItem()
  if purse and not depositsWithoutOpening(purse:getId()) and not isItemContainerOpen(purse) then
    return useMainContainer(purse)
  end
  
end

-- Full AFK functions
-- Check if have enough opened containers to proceed
local function countManagedContainers()
  local count,seen = 0,{}
  for _,container in pairs(g_game.getContainers() or {})do
    local id = container:getId()
    local holder = container:getContainerItem()
    local typeId = holder and holder:getId()
    local index = typeId and findContainerConfig(typeId)
    local managed = index and config.list[index].eEnabled or getExplicitSupplyRole(typeId) or
      config.openBack and typeId == getMainBackpackId()
    local purse = config.openPurse and getPurseItem()
    if not managed and purse then managed = typeId == purse:getId() end
    if not managed and config.openQuiver then
      for _,slot in pairs(getQuiverSlots())do
        if slot and slot:isContainer() and slot:getId() == typeId then managed = true;break end
      end
    end
    if managed and not container.lootContainer and not seen[id] then count = count+1;seen[id] = true end
  end
  return count
end
local function checkBps(noWarn)
  if countManagedContainers() < config.qtdFullAfk then 
    warn(tag.."Not Enough BPs.. Retrying")
    -- Recover incrementally; never close healthy/manual windows to meet a count.
    if CaveBot.isOn()then CaveBot.setOff();config.pausedCave=true end
    openMain()
  else
    if not noWarn then
      warn(tag.."Enough BPs: Continue")
    end
    if config.pausedCave and not (HelperPause and HelperPause.isPaused()) then
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
local pageRequests = {}
local supplyRequestAfter = {}
local emptyOpenAfter = {}
local reopenAfter = 0

if type(onContainerClose) == "function" then
  onContainerClose(function(container)
    for i=#containersToOpen,1,-1 do
      if containersToOpen[i].source == container then table.remove(containersToOpen,i) end
    end
    for i=#pageContainers,1,-1 do
      if pageContainers[i] == container then table.remove(pageContainers,i) end
    end
    local pending = pageRequests[container:getId()]
    if pending and pending.container == container then pageRequests[container:getId()] = nil end
    emptyOpenAfter[container:getId()] = nil
  end)
end

local function getContainerItemId(container)
  if not container then return nil end
  local containerItem = container:getContainerItem()
  return containerItem and containerItem:getId() or nil
end

local function sourceMayOpenNested(container)
  if openingsPaused or not container or container.lootContainer or
    (g_game.getContainers() or {})[container:getId()] ~= container then return false end
  local id = getContainerItemId(container)
  local index = findContainerConfig(id)
  local settings = index and config.list[index]
  local role = getExplicitSupplyRole(id)
  if settings then
    return (settings.eEnabled or role) and not settings.eDepositClosed and not settings.eOpenNextEmpty and
      (settings.eOpenNext or role) and true or false
  end
  return isMainBackpackContainer(container) or config.openPurse and id == purseId or role ~= nil
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

local function queueContainerToOpen(item, source)
  if not authorizedContainerItem(item) or not source or
    (g_game.getContainers() or {})[source:getId()] ~= source then return false end
  local id = item:getId()
  if depositsWithoutOpening(id) then return false end
  local index = findContainerConfig(id)
  local explicitPriority = getExplicitSupplyPriority(id)
  if not index and not explicitPriority then return false end
  local settings = index and config.list[index] or nil
  if settings and not settings.eEnabled and not explicitPriority then return false end
  if getContainerByItem(id) then return false end
  local position = type(item.getPosition) == "function" and item:getPosition()
  if not position or position.x ~= 65535 or position.y ~= 64 + source:getId() then return false end

  for _, queued in ipairs(containersToOpen) do
    if queued.item == item then
      return false
    end
  end

  local sourceIndex = findContainerConfig(getContainerItemId(source))
  local queued = {
    item = item,
    source = source,
    sourceId = source:getId(),
    sourceRule = sourceIndex and config.list[sourceIndex] or nil,
    targetRule = settings,
    position = {x=position.x,y=position.y,z=position.z},
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
  if not sourceMayOpenNested(container) then return false end
  local queued = false

  for _, item in ipairs(container:getItems()) do
    if queueContainerToOpen(item, container) then
      queued = true
    end
  end

  return queued
end

local function getOnlyBackpackInside(container)
  if not container or container.lootContainer then return nil end
  local items = container:getItems()
  if #items ~= 1 then return nil end
  local item = items[1]
  if not item.isContainer or not item:isContainer() then return nil end
  -- getItems() only includes the visible page; getSize() is the total size.
  if container.hasPages and container:hasPages() then
    if not container.getSize or container:getSize() ~= 1 then return nil end
    if container.getFirstIndex and container:getFirstIndex() ~= 0 then return nil end
  end
  return item
end

local function openNextEmptyContainer(container)
  if openingsPaused then return false end
  if depositsWithoutOpening(getContainerItemId(container)) then return false end
  local item = getOnlyBackpackInside(container)
  if not authorizedContainerItem(item) or item:getId()~=getContainerItemId(container) then return false end
  local key = container:getId()
  local time = now or 0
  if time < (emptyOpenAfter[key] or 0) then return false end
  emptyOpenAfter[key] = time + 1000
  return requestContainerOpen(item,container,false,nil,nil,'empty_next')
end

-- Reopen Containers (this one must be Global)
function reopenContainers(manual)
  if cManager:isOff() then return end
  local explicit=manual~=false
  if not explicit and openingsPaused then return false end
  if (now or 0) < reopenAfter and not(explicit and openingsPaused)then return false end
  if explicit then
    resumeAutomaticOpening('Re-Open All manual')
    openingDiagnostic('manual_reopen',nil,'Re-Open All')
  end
  reopenAfter = (now or 0) + 2000
  reopenGeneration=reopenGeneration+1
  local generation=reopenGeneration
  resetContainerOpening()
  layout.beforeReopen()
  containersToOpen = {}
  pageContainers = {}
  pageRequests = {}
  emptyOpenAfter = {}
  mainOpenAfter = 0
  batchClosing={}
  for id,cont in pairs(g_game.getContainers())do batchClosing[id]=cont end
  for _,cont in pairs(batchClosing)do g_game.close(cont)end
  if config.onFullAfk then 
    schedule((config.qtdFullAfk + 2) * defaultDelay, function()
      if generation==reopenGeneration and cManager:isOn() and config.onFullAfk then pauseAfk()end
    end)
  end
  schedule(defaultDelay * 2,function()
    if generation==reopenGeneration and cManager:isOn() then openMain()end
  end)
  return true
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
  if not itemId or itemId <= 0 or cManager:isOff() or openingsPaused then return false end
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
  if depositsWithoutOpening(targetContainerId) then return false end

  if not hasExplicitContainer and (not settings or not settings.eEnabled or
    not (settings.eOpenNext or settings.eOpenNextEmpty)) then return false end

  local time = now or 0
  if time < (supplyRequestAfter[itemId] or 0) then return true end
  supplyRequestAfter[itemId] = time + 1000

  local current = getContainerByItem(targetContainerId)
  if settings and settings.eOpenNextEmpty then
    -- Supply requests must also wait while other items remain in a V backpack.
    local onlyBackpack = getOnlyBackpackInside(current)
    if not onlyBackpack or onlyBackpack:getId() ~= targetContainerId then return false end
    return openNextEmptyContainer(current)
  end
  local nextItem = findContainerItem(current, targetContainerId)

  if nextItem then
    return requestContainerOpen(nextItem,current)
  end

  for _, source in ipairs(getOrderedOpenContainers()) do
    if source ~= current then
      nextItem = findContainerItem(source, targetContainerId)
      if nextItem then
        return requestContainerOpen(nextItem,current)
      end
    end
  end

  return false
end

ContainerManager = ContainerManager or {}
-- Reuse the existing master macro even when its switch stays in a hidden tab.
ContainerManager.isOn = cManager.isOn
ContainerManager.setOn = function()
  local wasOff=cManager:isOff()
  local result=cManager.setOn()
  if wasOff and cManager:isOn()then resumeAutomaticOpening('OFF/ON del gestor')end
  return result
end
ContainerManager.setOff = function()
  managerObservedOff=true
  return cManager.setOff()
end
ContainerManager.requestItemContainer = openNextSupplyContainer
-- Equipment recovery must not explore every carried backpack. Only roots
-- selected by their switches and destinations explicitly assigned this supply
-- may be opened; O/V on an ammo BP never authorizes a ring search through it.
ContainerManager.requestSupplyParent=function(item,itemId)
  itemId=tonumber(itemId)
  if not item or not itemId or not authorizedContainerItem(item) then return false end
  local root=config.openBack and getBack()==item or config.openPurse and getPurseItem()==item
  if not root and config.openQuiver then
    for _,slot in pairs(getQuiverSlots())do if slot==item then root=true;break end end
  end
  local assigned=getExplicitSupplyRole(item:getId())~=nil
  local index=findContainerConfig(item:getId())
  local settings=index and config.list[index]
  if settings and settings.eEnabled and not settings.eDepositClosed then
    for _,entry in ipairs(settings.eItems or{})do
      if tonumber(type(entry)=='table' and entry.id or entry)==itemId then assigned=true;break end
    end
  end
  if not root and not assigned then return false end
  return requestContainerOpen(item,nil,false,nil,true,'supply_recovery')
end

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
  layout.attach(container, previousContainer)
  local cId = container:getContainerItem():getId()
  local isMainSource = isMainBackpackContainer(container)
  local isPurseSource = config.openPurse and cId == purseId
  local index = findContainerConfig(cId)
  local explicitRole = getExplicitSupplyRole(cId)
  if not index and not isMainSource and not isPurseSource and not explicitRole then return end
  local settings = index and config.list[index] or {
    eEnabled = true,
    eOpenNext = true,
    eResize = isPurseSource,
    eRename = false,
    eMinimize = false,
    ePages = false
  }
  if not settings.eEnabled and not explicitRole then return end
  managedWindows[container:getId()]=container

  if not container.window then return end
  local cWindow = container.window
  if settings.eResize or isPurseSource then resizeContainerAfterLayout(container) end
  if isMainSource then
    cWindow:setText("Main Bp")
  elseif isPurseSource and not index then
    cWindow:setText("Purse")
  elseif explicitRole and not index then
    cWindow:setText(explicitRole)
  elseif settings.eRename then
    cWindow:setText(settings.eName)
  end
  if settings.eMinimize then minimizeContainerAfterLayout(container) end

  -- auto next page
  if settings.ePages and not settings.eDepositClosed and container:hasPages() then
    local nextPageButton = container.window:recursiveGetChildById('nextPageButton')
    if nextPageButton then 
      local found = false
      for i=#pageContainers,1,-1 do
        if pageContainers[i] == container then found = true
        elseif pageContainers[i]:getId() == container:getId() then table.remove(pageContainers,i) end
      end
      if not found then table.insert(pageContainers,container) end
    end
  end

  if not settings.eDepositClosed and (settings.eOpenNext or explicitRole) then
    queueConfiguredContainersFrom(container)
  end
end)

-- Containers with pages
local nextPageMacro = macro(defaultDelay * 2, function()
  if not observeManagerSwitch() then pageRequests = {};return end
  resolveContainerOpen()
  if openingsPaused then return end
  -- Re-evaluate current rules and live objects. Editing P applies without a
  -- reopen, and repeated Open notifications cannot multiply paging requests.
  pageContainers = {}
  local activeRules = {}
  local live = g_game.getContainers() or {}
  for _,container in pairs(live)do
    local index = findContainerConfig(getContainerItemId(container))
    local settings = index and config.list[index]
    if settings and settings.eEnabled and settings.ePages and not settings.eDepositClosed then
      pageContainers[#pageContainers+1] = container
      activeRules[container:getId()] = settings
    end
  end
  for id,pending in pairs(pageRequests)do
    local current = live[id]
    if not current or not activeRules[id] or activeRules[id] ~= pending.rule or
      current.window ~= pending.window or getContainerItemId(current) ~= pending.typeId then
      pageRequests[id] = nil
    elseif current ~= pending.container then pending.container = current end
  end
  for c=#pageContainers,1,-1 do
    local container = pageContainers[c]
    local index = findContainerConfig(getContainerItemId(container))
    local settings = index and config.list[index]
    if currentContainerWindow(container,container.window) and settings and settings.eEnabled and settings.ePages and
      not settings.eDepositClosed and container:hasPages() then
      local nextPageButton = container.window:recursiveGetChildById('nextPageButton')
      local capacity,first = container:getCapacity(),container:getFirstIndex()
      local hasNext = capacity > 0 and first + capacity < container:getSize()
      local id,time = container:getId(),now or 0
      local pending = pageRequests[id]
      if pending and pending.first ~= first then pageRequests[id] = nil;pending = nil end
      if hasNext and not isOpeningFrom(container) and nextPageButton and nextPageButton:isEnabled() and type(nextPageButton.onClick) == 'function' and
        (not pending or pending.attempts < 3 and time >= pending.after) then
        pending = pending or {container=container,window=container.window,typeId=getContainerItemId(container),rule=settings,first=first,attempts=0}
        local ping = g_game.getPing and tonumber(g_game.getPing()) or 0
        pending.attempts,pending.after = pending.attempts+1,time+math.max(2000,math.min(6000,ping*3+300))
        pageRequests[id] = pending
        nextPageButton.onClick()
      elseif not hasNext then pageRequests[id] = nil end
    else
      table.remove(pageContainers,c)
    end
  end
end)

-- Recover the first enabled destination visible inside a selected equipped
-- root. This is separate from O (walking nested BPs) and V (empty replacement).
-- An open copy or in-flight receipt prevents opening any of its siblings.
local function openFirstConfiguredContainer()
  for _,source in ipairs(getOrderedOpenContainers())do
    if isInitialContainerSource(source) then
      for _,item in ipairs(source:getItems())do
        local index=findContainerConfig(item:getId())
        local entry=index and config.list[index]
        if (entry and entry.eEnabled or getExplicitSupplyRole(item:getId())) and
          authorizedContainerItem(item) and not getContainerByItem(item:getId()) and
          requestContainerOpen(item,nil,false,nil,true,'initial_configured') then return true end
      end
    end
  end
  return false
end

-- Containers to be opened
local openNextMacro = macro(defaultDelay,function()
  if not observeManagerSwitch() then containersToOpen = {};return end
  resolveContainerOpen()
  if openingsPaused then containersToOpen={};return end
  if openMain() or openFirstConfiguredContainer() then return delay(defaultDelay+5)end

  local openContainers = getOrderedOpenContainers()
  for _, container in ipairs(openContainers) do
    local index = findContainerConfig(getContainerItemId(container))
    local settings = index and config.list[index] or nil
    if settings and settings.eEnabled and not settings.eDepositClosed and settings.eOpenNextEmpty and
      openNextEmptyContainer(container) then
      return delay(defaultDelay + 5)
    end
  end

  while #containersToOpen > 0 do
    local entry = table.remove(containersToOpen, 1)
    local position = entry.item and entry.item:getPosition()
    local unchanged = entry.position and position and entry.position.x == position.x and entry.position.y == position.y and entry.position.z == position.z
    local sourceIndex = entry.source and findContainerConfig(getContainerItemId(entry.source))
    local targetIndex = findContainerConfig(entry.id)
    local sourceRule = sourceIndex and config.list[sourceIndex] or nil
    local targetRule = targetIndex and config.list[targetIndex] or nil
    if unchanged and sourceRule == entry.sourceRule and targetRule == entry.targetRule and
      sourceMayOpenNested(entry.source) and authorizedContainerItem(entry.item) and
      not getContainerByItem(entry.id) then
      local present = false
      for _,candidate in ipairs(entry.source:getItems())do if candidate == entry.item then present = true;break end end
      if present and requestContainerOpen(entry.item)then return delay(defaultDelay+5)end
    end
  end

  for _, container in ipairs(openContainers) do
    local shouldOpenInside = sourceMayOpenNested(container)
    if shouldOpenInside and queueConfiguredContainersFrom(container) then
      return delay(defaultDelay + 5)
    end
  end

  openMain()
end)

-- The destination is the BP item itself, not a slot inside a newly opened
-- window. Only fresh inventory positions are used; never cache a hidden bag's
-- old slot after its parent closes or changes page.
local closedDeposits={}
local closedStates,closedLogAt={},{}
local function closedNote(id,phase,message)
  closedStates[id]={phase=phase,message=message,at=now or 0}
  -- Keep routine inventory updates in diagnostics without flooding the console.
  if phase=='inventory'then return end
  local key=tostring(id)..':'..phase
  if (now or 0)<(closedLogAt[key]or 0)then return end
  closedLogAt[key]=(now or 0)+15000
  if type(info)=='function'then info('[Container Manager R150] BP '..tostring(id)..': '..message)end
end
local closedLinks,closedSearches,closedRejected={},{},{}
local closedSearchAfter=0
-- Native C++ objects can have a fresh Lua userdata on every getContainers()
-- read. __eq compares the native pointer, but Lua table keys use raw userdata
-- identity. Index by numeric container ID and verify the stored native object;
-- an ID reused by another window must never inherit its previous provenance.
local function linkedItem(container)
  local link=container and closedLinks[container:getId()]
  return link and link.container==container and link.item or nil
end
local function containerSeen(map,container)
  return container and map[container:getId()]==container
end
local function itemPosition(item)
  if not item or type(item.getPosition)~='function' then return nil end
  return item:getPosition()
end
local function samePosition(a,b)
  return a and b and a.x==b.x and a.y==b.y and a.z==b.z
end
local function sameItem(a,b)
  return a==b or a and b and a:getId()==b:getId() and samePosition(itemPosition(a),itemPosition(b))
end
isItemContainerOpen = function(item, excluded)
  if not item then return false end
  local position = itemPosition(item)
  local slot = position and position.x == 65535 and position.y > 0 and position.y < 64 and position.y
  
  for _, container in pairs(g_game.getContainers() or {}) do
    if container ~= excluded and not container.lootContainer then
      local linked = linkedItem(container)
      local link = closedLinks[container:getId()]
      local holder = linked or container:getContainerItem()
      
      -- Coincidencia exacta del ítem físico
      if holder == item then return true end
      
      -- Si el bot rastreó la apertura, verificar que sea estrictamente la principal y no una mochila anidada
      if linked and slot and link.rootCoverage and link.rootCoverage[slot] == item:getId() then 
         if holder == item then return true end
      end
      
      -- Si el rastreo falló (ej. apertura manual), obligar a que coincidan las posiciones exactas
      if not linked and holder and holder:getId() == item:getId() then 
         local hPos = itemPosition(holder)
         if hPos and position and hPos.x == position.x and hPos.y == position.y then
            return true
         end
      end
    end
  end
  return false
end
local function inventoryRoots()
  local roots={}
  for _,getter in ipairs({getBack or false,getPurseItem,getAmmo or false,getLeft or false,getRight or false})do
    if type(getter)=='function' then local ok,item=pcall(getter)
      if ok and item and item.isContainer and item:isContainer() then roots[#roots+1]=item end
    end
  end
  return roots
end
-- Keep root ownership separate from the current Item userdata. An inventory
-- update of the quiver/purse must not discard Main BP's acknowledged window.
local function rootSlotFor(item,containers,position)
  local seen={}
  local pos=position or itemPosition(item)
  while pos and pos.x==65535 and pos.y>0 do
    if pos.y<64 then return pos.y end
    local id=pos.y-64
    if seen[id]then return nil end
    seen[id]=true
    local parent=containers[id]
    if not parent then return nil end
    pos=itemPosition(linkedItem(parent) or parent:getContainerItem())
  end
end
local function carriedContainer(container,containers,roots,seen)
  if not container or container.lootContainer or containerSeen(closedRejected,container) or containerSeen(seen,container) then return false end
  seen[container:getId()]=container
  local item=linkedItem(container) or container:getContainerItem()
  for _,root in ipairs(roots)do if sameItem(root,item) then return true end end
  local pos=itemPosition(item)
  if not pos or pos.x~=65535 or pos.y<64 then return false end
  local parent=containers[pos.y-64]
  if not parent then return false end
  local observed=false
  for _,candidate in ipairs(parent:getItems())do
    if sameItem(candidate,item) then observed=true;break end
  end
  return observed and carriedContainer(parent,containers,roots,seen)
end
isInitialContainerSource=function(container)
  if not container or container.lootContainer or
    (g_game.getContainers()or{})[container:getId()]~=container then return false end
  local index=findContainerConfig(getContainerItemId(container))
  local entry=index and config.list[index]
  if entry and (not entry.eEnabled or entry.eDepositClosed or entry.eOpenNextEmpty)then return false end
  local holder=linkedItem(container)or container:getContainerItem()
  if config.openBack and holder==getBack() then return true end
  if config.openPurse and holder==getPurseItem() then return true end
  if config.openQuiver then
    for _,slot in pairs(getQuiverSlots())do if holder==slot then return true end end
  end
  return false
end
local function containsDestination(item,parent,containers)
  local seen={}
  while parent and not containerSeen(seen,parent)do
    seen[parent:getId()]=parent
    local holder=linkedItem(parent) or parent:getContainerItem()
    if sameItem(item,holder) then return true end
    local pos=itemPosition(holder)
    parent=pos and pos.x==65535 and pos.y>=64 and containers[pos.y-64] or nil
  end
  return false
end
local function closedTargets(id,containers,roots)
  local targets={}
  for _,root in ipairs(roots)do
    local pos=itemPosition(root)
    if root:getId()==id and pos and pos.x==65535 and pos.y>0 and pos.y<64 then
      targets[#targets+1]={item=root,pos=pos}
    end
  end
  for _,parent in ipairs(getOrderedOpenContainers())do
    if carriedContainer(parent,containers,roots,{}) then
      for _,candidate in ipairs(parent:getItems())do
        local pos=itemPosition(candidate)
        if candidate:getId()==id and candidate.isContainer and candidate:isContainer() and
          pos and pos.x==65535 and pos.y==64+parent:getId() then
          targets[#targets+1]={item=candidate,pos=pos,parent=parent}
        end
      end
    end
  end
  return targets
end
-- All openings sent by this manager share one acknowledgement. A nil native
-- return is a request, never proof that a new window exists. Keep provenance
-- even when a different closed-deposit rule becomes the next sorting task.
local containerOpenPending,containerOpenAttempts,containerOpenReceipts,containerOpenOwners=nil,{},{},{}
local containerOpenNotBefore={}
isOpeningFrom=function(container)
  for _,pending in pairs(containerOpenReceipts)do
    if pending.previous == container or pending.position.y == 64+container:getId() and
      pending.before[container:getId()] == container then return true end
  end
  return false
end
local function openKey(item)
  local p=itemPosition(item)
  return p and item:getId()..':'..p.x..':'..p.y..':'..p.z
end
local function observedOpenItem(item,position,containers,carriedOnly)
  if not samePosition(itemPosition(item),position) then return false end
  if position.x~=65535 or position.y<=0 then return false end
  if position.y<64 then
    for _,root in ipairs(inventoryRoots())do if root==item then return true end end
    return false
  end
  local parent=containers[position.y-64]
  if not parent or carriedOnly and not carriedContainer(parent,containers,inventoryRoots(),{})then return false end
  for _,candidate in ipairs(parent:getItems())do if candidate==item then return true end end
  return false
end
local function resolveReceipt(p)
  local function retire()
    if containerOpenPending==p then containerOpenPending=nil end
    if containerOpenReceipts[p.key]==p then containerOpenReceipts[p.key]=nil end
  end
  local containers=g_game.getContainers()
  -- Opening a nested BP into its own parent's window replaces that source.
  -- Its old inventory slot no longer identifies the requested physical item.
  local replacementId=p.previous and p.position.y==64+p.previous:getId() and p.previous:getId() or nil
  local expectedId=type(p.id)=='number' and p.id>=0 and p.id or replacementId
  local opened
  if expectedId then
    local c=containers[expectedId]
    if c and (p.before[c:getId()]~=c)then opened=c end
  else
    for _,c in pairs(containers)do
      local header=c:getContainerItem()
      if (p.before[c:getId()]~=c) and not c.lootContainer and header and header:getId()==p.item:getId()then
        if opened then opened=nil;break end
        opened=c
      end
    end
  end
  local header=opened and opened:getContainerItem()
  local replacedSource=replacementId and opened and opened:getId()==replacementId and
    p.before[replacementId]==p.previous and header and header:getId()==p.item:getId()
  if not replacedSource and not observedOpenItem(p.item,p.position,containers,p.carriedOnly)then retire();return end
  if opened and not opened.lootContainer and header and header:getId()==p.item:getId()then
    closedRejected[opened:getId()]=nil;closedLinks[opened:getId()]={container=opened,item=p.item,rootSlot=p.rootSlot,rootCoverage=p.rootCoverage}
    managedWindows[opened:getId()]=opened
    if p.operation and openingActivity and openingActivity.operation==p.operation then openingActivity.at=now or 0 end
    openingDiagnostic('ack',p.item,p.reason,opened)
    retire();containerOpenAttempts[p.key]=nil;containerOpenOwners[p.key]=nil
    if p.ready then p.ready(opened)end
  elseif (now or 0)>=p.expires then retire()
  elseif (now or 0)>=p.untilAt and containerOpenPending==p then
    containerOpenPending=nil -- retain provenance for a late native response
  end
end
resolveContainerOpen=function()
  local receipts={};for _,p in pairs(containerOpenReceipts)do receipts[#receipts+1]=p end
  for _,p in ipairs(receipts)do resolveReceipt(p)end
end
requestContainerOpen=function(item,previous,useItem,ready,carriedOnly,reason)
  resolveContainerOpen()
  local scrollSearch=reason=='imbuement_scroll'
  if openingsPaused or containerOpenPending then return false end
  if scrollSearch then
    if not item or not item.isContainer or not item:isContainer() or depositsWithoutOpening(item:getId()) then return false end
  elseif cManager:isOff() or not authorizedContainerItem(item) then return false end
  if previous and (g_game.getContainers() or {})[previous:getId()] ~= previous then return false end
  if isItemContainerOpen(item,previous) then return false end
  for _,p in pairs(containerOpenReceipts)do
    if p.item:getId()==item:getId()then return false end
  end
  local containers=g_game.getContainers()
  for _,c in pairs(containers)do
    local linked=linkedItem(c)
    local header=linked or c:getContainerItem()
    -- A proven link identifies a physical native item. Its former inventory
    -- position can now belong to the NEXT same-ID BP in this reused window.
    if not c.lootContainer and header and (header==item or not linked and sameItem(header,item))then return false end
    -- A detached header may predate this executor. Do not adopt it by ID,
    -- but do not let it block a request for an observed carried item either.
    -- An Open acknowledgement binds the actual item; a Close is settled below.
  end
  local key=openKey(item)
  if not key or (containerOpenAttempts[key] or 0)>=3 or(now or 0)<(containerOpenNotBefore[key]or 0)then return false end
  local position=itemPosition(item)
  if not observedOpenItem(item,position,containers,carriedOnly)then return false end
  local sourceId = position.y >= 64 and position.y-64
  local function pageBusy(page)
    return page and containers[page.container:getId()] == page.container and page.container.window == page.window and
      page.first == page.container:getFirstIndex() and (now or 0) < page.after
  end
  if pageBusy(sourceId and pageRequests[sourceId]) or pageBusy(previous and pageRequests[previous:getId()]) then return false end
  local before={};for _,c in pairs(containers)do before[c:getId()]=c end
  local ping=g_game.getPing and tonumber(g_game.getPing())or 0
  local coverage={}
  if position.y<64 then coverage[position.y]=item:getId()
  elseif previous then
    local prior=closedLinks[previous:getId()]
    if prior and prior.container==previous then
      for slot,id in pairs(prior.rootCoverage or{})do coverage[slot]=id end
    else
      -- A pre-existing detached root cannot identify its physical copy. Keep
      -- conservative opening coverage through V without adopting its identity.
      local priorHeader=previous:getContainerItem()
      for _,root in ipairs(inventoryRoots())do
        local pos=itemPosition(root)
        if priorHeader and pos and pos.x==65535 and pos.y>0 and pos.y<64 and priorHeader:getId()==root:getId()then
          coverage[pos.y]=root:getId()
        end
      end
    end
  end
  local p={item=item,key=key,position={x=position.x,y=position.y,z=position.z},before=before,ready=ready,carriedOnly=carriedOnly,previous=previous,useItem=useItem,rootSlot=rootSlotFor(item,containers,position),rootCoverage=coverage,
    reason=reason or(useItem and'root' or previous and'replace_configured' or'configured'),
    untilAt=(now or 0)+math.max(2000,math.min(4000,ping*3+300)),expires=(now or 0)+20000}
  containerOpenPending=p;containerOpenReceipts[key]=p
  closedNote(item:getId(),'opening','Comprobando padre del inventario; intento '..tostring((containerOpenAttempts[key]or 0)+1))
  containerOpenAttempts[key]=(containerOpenAttempts[key]or 0)+1;containerOpenOwners[key]=p.rootSlot
  openingOperation=openingOperation+1;p.operation=openingOperation
  openingActivity={operation=p.operation,at=now or 0}
  openingDiagnostic('request',item,p.reason,previous)
  local ok,result
  if useItem then ok,result=pcall(g_game.use,item)
  else ok,result=pcall(g_game.open,item,previous)end
  if not ok or result==false or type(result)=='number'and result<0 then
    if containerOpenPending==p then containerOpenPending=nil end
    if containerOpenReceipts[key]==p then containerOpenReceipts[key]=nil end
    return false
  end
  if containerOpenPending==p then p.id=result;resolveContainerOpen()end
  return true
end
function ContainerManager.requestScrollContainer(search)
  resolveContainerOpen()
  if openingsPaused or containerOpenPending then return 'waiting' end
  local time=now or 0
  if time<(search.nextAt or 0) then return 'waiting' end
  local containers=g_game.getContainers() or {}
  local roots=inventoryRoots()
  local function open(item)
    local key=openKey(item)
    if not key or search.tried[key] or isItemContainerOpen(item) then return false end
    if not requestContainerOpen(item,nil,false,nil,true,'imbuement_scroll') then return false end
    search.tried[key]=true
    search.nextAt=time+1200
    return true
  end
  for _,item in ipairs(roots)do if open(item) then return 'waiting' end end
  for _,container in pairs(containers)do
    if carriedContainer(container,containers,roots,{}) then
      for _,item in ipairs(container:getItems() or {})do
        if item.isContainer and item:isContainer() and open(item) then return 'waiting' end
      end
    end
  end
  return 'missing'
end
resetContainerOpening=function()
  containerOpenPending=nil;containerOpenAttempts={};containerOpenReceipts={};containerOpenOwners={}
  containerOpenNotBefore={}
  closedLinks,closedSearches,closedRejected={},{},{};closedSearchAfter=0
end
cancelAutomaticOpening=function()
  containerOpenPending=nil;containerOpenReceipts={}
  containersToOpen={};pageRequests={};pageContainers={};emptyOpenAfter={};supplyRequestAfter={}
  closedSearches={};closedSearchAfter=0
  reopenGeneration=reopenGeneration+1
end
resetOpeningRetries=function()
  cancelAutomaticOpening()
  containerOpenAttempts={};containerOpenOwners={};containerOpenNotBefore={}
end
-- Native responses can arrive between sorting ticks, or after the item which
-- triggered discovery has already disappeared. Do not leave those roots unbound.
onContainerOpen(function(container,previous)
  local header=container and container:getContainerItem()
  openingDiagnostic('open',header,previous and'replaced_window' or'native_response',container)
  resolveContainerOpen()
end)

-- Manual/in-game uses can also open carried parents. Observe their physical
-- inventory source before the native response, without replacing any callback
-- or wrapping g_game. A late use acknowledgement uses the same shared receipt.
if type(onUse)=='function' then
  onUse(function(position,id)
    observeManagerSwitch()
    if cManager:isOff() or openingsPaused or not position or position.x~=65535 then return end
    resolveContainerOpen()
    if containerOpenPending then return end
    local containers=g_game.getContainers()
    local item
    if position.y>0 and position.y<64 then
      for _,root in ipairs(inventoryRoots())do
        if root:getId()==id and samePosition(itemPosition(root),position)then item=root;break end
      end
    elseif position.y>=64 then
      local parent=containers[position.y-64]
      if parent and carriedContainer(parent,containers,inventoryRoots(),{})then
        for _,candidate in ipairs(parent:getItems())do
          if candidate:getId()==id and samePosition(itemPosition(candidate),position)then item=candidate;break end
        end
      end
    end
    if not item or not item.isContainer or not item:isContainer()then return end
    local key=openKey(item)
    if not key or containerOpenReceipts[key]then return end
    for _,p in pairs(containerOpenReceipts)do if p.item:getId()==id then return end end
    local before={};for _,c in pairs(containers)do before[c:getId()]=c end
    local coverage={}
    if position.y>0 and position.y<64 then coverage[position.y]=id end
    local p={item=item,key=key,position={x=position.x,y=position.y,z=position.z},before=before,carriedOnly=true,rootSlot=rootSlotFor(item,containers,position),rootCoverage=coverage,reason='observed_use',
      untilAt=(now or 0)+2000,expires=(now or 0)+20000}
    containerOpenPending=p;containerOpenReceipts[key]=p
  end)
end

-- The protocol exposes a destination only while its BP item is visible.
-- Discover its parents from equipped roots; never open the requested BP or
-- another entry marked C. Bind only fresh responses to witnessed inventory
-- requests; a container-window header alone cannot identify its physical BP.
local function knownClosedParent(item,containers,roots)
  for _,container in pairs(containers)do
    if not container.lootContainer and sameItem(linkedItem(container) or container:getContainerItem(),item) and
      carriedContainer(container,containers,roots,{}) then return container end
  end
end
local function discoverClosedTarget(id,containers,roots)
  local time=now or 0
  if time<closedSearchAfter then return end
  closedSearchAfter=time+500
  for containerId,link in pairs(closedLinks)do
    if containers[containerId]~=link.container then closedLinks[containerId]=nil end
  end
  local job=closedSearches[id]
  if job and time<(job.retryAfter or 0) then return end
  if not job or time>=job.expires or job.exhausted then
    job={expires=time+20000,rootCursor=1,queue={},head=1,seen={},opens=0}
    closedSearches[id]=job
  end
  local function enqueue(container,depth)
    if containerSeen(job.seen,container) then return end
    job.seen[container:getId()]=container
    -- Finish the confirmed branch before opening siblings. An unrelated
    -- sibling may already be open with a detached header (including the item
    -- source); using it needlessly would toggle away that source window.
    table.insert(job.queue,job.head,{container=container,depth=depth,cursor=1})
  end
  resolveContainerOpen()
  -- Do not consume root/child cursors while their native answer is pending.
  -- Otherwise an empty queue is marked exhausted before the callback can
  -- enqueue its confirmed parent, repeatedly adding the full search backoff.
  for _ in pairs(containerOpenReceipts)do return end
  local function openParent(item,depth)
    if item:getId()==id then return false end
    if not authorizedContainerItem(item) then job.unauthorized = true;return false end
    if isItemContainerOpen(item) then job.ambiguous = true;return false end
    local pos=itemPosition(item)
    if not pos or pos.x~=65535 or pos.y<=0 then return false end
    if pos.y>=64 then
      local parent=containers[pos.y-64]
      if not parent or not carriedContainer(parent,containers,roots,{}) then return false end
      local observed=false
      for _,candidate in ipairs(parent:getItems())do if sameItem(candidate,item)then observed=true;break end end
      if not observed then return false end
    else
      local equipped=false
      for _,root in ipairs(roots)do if sameItem(root,item)then equipped=true;break end end
      if not equipped then return false end
    end
    local total=0
    for _ in pairs(containers)do total=total+1 end
    if total>=16 or job.opens>=12 then return false end
    if requestContainerOpen(item,nil,false,function(opened)
      if carriedContainer(opened,g_game.getContainers(),inventoryRoots(),{})then enqueue(opened,depth)end
    end,true)then job.opens=job.opens+1;return true end
    return false
  end
  local work,started=0,os.clock()
  while work<32 and os.clock()-started<0.002 do
    local node=job.queue[job.head]
    if not node then
      local root=roots[job.rootCursor]
      if not root then job.exhausted=true;job.retryAfter=time+5000;return end
      job.rootCursor=job.rootCursor+1;work=work+1
      if root:getId()~=id then
        local opened=knownClosedParent(root,containers,roots)
        if opened then enqueue(opened,0)
        elseif openParent(root,0)then return end
      end
    elseif containers[node.container:getId()]~=node.container or
      not carriedContainer(node.container,containers,roots,{}) then job.head=job.head+1
    else
      local items=node.container:getItems()
      while node.cursor<=#items and work<32 and os.clock()-started<0.002 do
        local item=items[node.cursor];node.cursor=node.cursor+1;work=work+1
        local pos=itemPosition(item)
        if item.isContainer and item:isContainer() and pos and pos.x==65535 and pos.y==64+node.container:getId() then
          if item:getId()==id then return end
          if node.depth<6 then
            local opened=knownClosedParent(item,containers,roots)
            if opened then enqueue(opened,node.depth+1);return
            elseif openParent(item,node.depth+1)then return end
          end
        end
      end
      if node.cursor>#items then job.head=job.head+1 end
    end
  end
end
if type(onContainerClose)=='function' then
  onContainerClose(function(container)
    local containerId=container:getId()
    local link=closedLinks[containerId]
    if link and link.container~=container then link=nil end
    local header=container:getContainerItem()
    local expected=batchClosing[containerId]==container
    if expected then batchClosing[containerId]=nil end
    local intentionalReplacement=false
    local affected=link~=nil or managedWindows[containerId]==container
    -- Only the exact previous source is an expected replacement. A Close from
    -- some other same-ID window is an unexpected toggle, never a successful V.
    local canceled={}
    for key,p in pairs(containerOpenReceipts)do
      if p.previous==container then intentionalReplacement=true
      elseif p.before[containerId]==container and(header and header:getId()==p.item:getId()or p.position.y==64+containerId)then
        affected=true
        canceled[#canceled+1]=key
      end
    end
    for _,key in ipairs(canceled)do
      local pending=containerOpenReceipts[key]
      containerOpenNotBefore[key]=math.max(containerOpenNotBefore[key]or 0,pending.untilAt or 0)
      if containerOpenPending==containerOpenReceipts[key]then containerOpenPending=nil end
      containerOpenReceipts[key]=nil
    end
    openingDiagnostic('close',link and link.item or header,expected and'explicit_reopen_batch' or
      intentionalReplacement and'intentional_replacement' or'unexpected',container)
    if link then closedLinks[containerId]=nil end
    if managedWindows[containerId]==container then managedWindows[containerId]=nil end
    if closedRejected[containerId]==container then closedRejected[containerId]=nil end
    if not expected and not intentionalReplacement and affected then
      recordRapidClose(link and link.item or header,container)
    end
  end)
end
if type(onPlayerInventoryChange)=='function' then
  onPlayerInventoryChange(function(slot,item,oldItem)
    if slot==(SlotBack or InventorySlotBack or 3) or slot==(SlotPurse or InventorySlotPurse or 11) or
      (slot==(SlotAmmo or InventorySlotAmmo or 10) or slot==(SlotLeft or InventorySlotLeft or 6) or slot==(SlotRight or InventorySlotRight or 5)) and
        (item and item.isContainer and item:isContainer() or oldItem and oldItem.isContainer and oldItem:isContainer()) then
      -- Native equality, not ID/position equality: a real same-type BP swap
      -- still needs ownership validation; a duplicate notification does not.
      if item and oldItem and item==oldItem then return end
      local containers=g_game.getContainers()
      local affected={}
      for id,container in pairs(containers)do
        local link=closedLinks[id]
        if link and link.container~=container then link=nil end
        local holder=link and link.item or container:getContainerItem()
        local owner=rootSlotFor(holder,containers) or link and link.rootSlot
        local header=container:getContainerItem()
        local unknownMatch=not owner and header and
          (oldItem and header:getId()==oldItem:getId() or item and header:getId()==item:getId())
        if owner==slot or unknownMatch then affected[id]=container end
      end
      for key,p in pairs(containerOpenReceipts)do
        if p.rootSlot==slot or rootSlotFor(p.item,containers,p.position)==slot then
          if containerOpenPending==p then containerOpenPending=nil end
          containerOpenReceipts[key]=nil
        end
      end
      for key,owner in pairs(containerOpenOwners)do
        if owner==slot then containerOpenAttempts[key]=nil;containerOpenOwners[key]=nil end
      end
      for id,container in pairs(affected)do
        closedLinks[id]=nil;closedRejected[id]=container
      end
      -- Rebuild traversal cursors, preserving unrelated confirmed links and
      -- pending receipts. A pending Main reply survives a quiver update.
      closedSearches={};closedSearchAfter=0
      local changed=item or oldItem
      if changed then closedNote(changed:getId(),'inventory','Cambio de inventario en slot '..slot..'; solo se revalida esa rama.')end
    end
  end)
end

local function sourceUnchanged(pending,containers)
  local source=containers[pending.sourceId]
  if not source then return false end
  for _,item in ipairs(source:getItems())do
    if item:getId()==pending.itemId and samePosition(itemPosition(item),pending.pos) and
      (not item.getCount or item:getCount()==pending.count) then return true end
  end
  return false
end

local failedDeposits = {}

local function depositWithoutOpening(item,source,targets,containers)
  local time=now or 0
  
  local itemId = item:getId()
  if failedDeposits[itemId] and time < failedDeposits[itemId] then
     return false 
  end

  for key,pending in pairs(closedDeposits)do
    local unchanged=sourceUnchanged(pending,containers)
    if time>=pending.untilAt or not unchanged then
      if unchanged then 
         closedNote(pending.targetId,'unconfirmed','Sin confirmacion del deposito; revisa espacio y destino.')
         failedDeposits[pending.itemId] = time + 30000 
         if type(info)=='function' then 
             info('[Container Manager R150] Pausando intentos para el item '..pending.itemId..' por 30 segundos (Quiver/Contenedor lleno).') 
         end
      else 
         closedNote(pending.targetId,'source_changed','El objeto origen cambio tras la orden; destino cerrado sin inspeccionar.')
      end
      closedDeposits[key]=nil
    end
  end
  for _,target in ipairs(targets)do
    local pos=target.pos
    local key=target.item:getId()..':'..pos.x..':'..pos.y..':'..pos.z
    if not closedDeposits[key] and not sameItem(item,target.item) and not containsDestination(item,target.parent,containers) then
      local src=itemPosition(item)
      if src then
        local count=item:getCount()
        local ok,result=pcall(g_game.move,item,{x=pos.x,y=pos.y,z=pos.z},count)
        closedDeposits[key]={targetId=target.item:getId(),sourceId=source:getId(),itemId=item:getId(),count=count,
          pos={x=src.x,y=src.y,z=src.z},untilAt=time+1000}
        if ok and result~=false then
          closedNote(target.item:getId(),'sent','Orden de deposito: item '..item:getId()..' x'..count..'; destino '..pos.x..','..pos.y..','..pos.z..'. Esperando respuesta.')
          return true
        end
        closedNote(target.item:getId(),'rejected','El cliente rechazo la orden de deposito del item '..item:getId()..'.')
      end
    end
  end
  return false
end

local sortItemsMacro = macro(defaultDelay, function(m)
  observeManagerSwitch()
  if cManager:isOn() and config.sortItems then
    local lootPolicy=TargetBot and TargetBot.LootPolicy
    if lootPolicy and lootPolicy.active()and lootPolicy.waiting()then return end
    resolveContainerOpen()
    local containers=g_game.getContainers()
    local roots,targets=inventoryRoots(),{}
    for c, cont in pairs(containers) do
      if not cont.lootContainer then
        local containerItem = cont:getContainerItem()
        local srcId = containerItem and containerItem:getId() or 0
        for i, item in ipairs(cont:getItems()) do
          local toId = sList[item:getId()]
          local lootPolicy=TargetBot and TargetBot.LootPolicy
          local assignedLoot=lootPolicy and lootPolicy.isManagedItem(item,cont)
          if toId and toId ~= srcId and not assignedLoot then
            local toIndex = findContainerConfig(toId)
            if toIndex then
              local toConfig = config.list[toIndex]
              if toConfig and toConfig.eEnabled then
                if toConfig.eDepositClosed then
                  if not targets[toId] then targets[toId]=closedTargets(toId,containers,roots) end
                  if #targets[toId]==0 then
                    discoverClosedTarget(toId,containers,roots)
                    -- A synchronous open can make the BP item addressable now.
                    containers=g_game.getContainers()
                    targets[toId]=closedTargets(toId,containers,roots)
                  end
                  if #targets[toId]==0 then
                    local search=closedSearches[toId]
                    if search and search.unauthorized then
                      closedNote(toId,'configured_only','La busqueda no abre BPs no configuradas; habilita los padres necesarios o abrelos manualmente.')
                    elseif search and search.ambiguous then
                      closedNote(toId,'identity_unknown','Hay una BP del mismo ID abierta sin identidad comprobada; no se vuelve a usar. Re-Open All puede reconstruirla.')
                    else
                      closedNote(toId,'searching','Buscando el objeto de BP en el inventario; sin destino comprobado todavia.')
                    end
                  end
                  if depositWithoutOpening(item,cont,targets[toId],containers) then return end
                else
                  local destNotFull = getContainerByItem(toId, not toConfig.eInfinite)
                  if destNotFull then
                    return moveItem(item,destNotFull,toConfig.eInfinite and 0 or nil)
                  elseif toConfig.eFull and not toConfig.eOpenNextEmpty then
                    local destFull = getContainerByItem(toId)
                    if destFull then
                      for n, newCont in ipairs(destFull:getItems()) do
                        if newCont:getId() == toId then
                          return requestContainerOpen(newCont,destFull)
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
  end
end)

-- Full AFK loop
macro(20000,function()
  if cManager.isOn() and config.onFullAfk then
    checkBps(true)
	  delay(config.qtdFullAfk * defaultDelay)
  end
end)

macro(500, function() layout.tick() end)

ContainerManager.getStatus=function()
  local status={revision='R150',enabled=cManager:isOn(),sortItems=config.sortItems==true,
    openingsPaused=openingsPaused,openingsPauseReason=openingsPauseReason,reason=openingsPauseReason,openingEvents=openingEvents,
    rapidCloseOperations=#openingCloseStrikes,rapidCloseWindow=rapidCloseWindow,closePatternWindow=closePatternWindow,closePatternLimit=closePatternLimit,
    managedOpen=countManagedContainers(),requiredManaged=config.qtdFullAfk,automaticPolicy='configured_only',entries={}}
  for _,entry in ipairs(config.list)do
    if entry.eDepositClosed then
      local state=closedStates[entry.eId]
      local count=type(entry.eItems)=='table'and #entry.eItems or 0
      local message=not entry.eEnabled and 'Entrada apagada' or not config.sortItems and 'Sort Items apagado' or
        count==0 and 'Sin items configurados' or state and state.message or 'Esperando un item configurado visible'
      status.entries[#status.entries+1]={id=entry.eId,name=entry.eName,enabled=entry.eEnabled==true,items=count,message=message}
    end
  end
  return status
end
-- Read-only provenance for the loot router. A detached native header is not
-- sufficient to identify one of several carried backpacks with the same ID.
ContainerManager.getContainerSource=function(container)return linkedItem(container)end
if type(info)=='function'then
  local status=ContainerManager.getStatus()
  info('[Container Manager R150] Cargado; C='..#status.entries..'; gestor='..tostring(status.enabled)..'; Sort Items='..tostring(status.sortItems))
end
openingDiagnostic('loaded',nil,cManager:isOn() and'enabled'or'disabled')
if cManager.isOn() and config.reopenAtLogin then reopenContainers(false) end
