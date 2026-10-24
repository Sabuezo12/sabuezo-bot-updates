-- RinoBot own reconnect host R195. Runs independently from the bot executor.
RinoReconnectHost={version=1}
local Host=RinoReconnectHost
local function live(w)
  if not w then return false end
  if type(w.isDestroyed)=='function' then local ok,v=pcall(w.isDestroyed,w);return ok and not v end
  return true
end
local function callable(value)
  if type(value)=='function' then return value end
  if type(value)=='table' then for _,fn in ipairs(value) do if type(fn)=='function' then return fn end end end
end
local function normalize(value)return type(value)=='string' and value:lower():gsub('^%s+',''):gsub('%s+$','') or ''end
function Host.start(options)
  options=options or {}
  local after=options.after or scheduleEvent
  if type(after)~='function' then return nil,'Reinicia el cliente una vez para cargar el script de reconexion.' end
  local game=g_game
  local owner=options.owner
  local function validOwner()
    if not owner then return not options.requireOwner end
    if type(owner)~='string' or not owner:match('^/bot/[^/]+/vBot/AutoReconnect%.lua$') or owner:find('..',1,true) then return false end
    local ok,data=pcall(function()return g_resources.readFileContents(owner)end)
    return ok and type(data)=='string' and data:find('-- RinoBot own reconnect frontend R195.',1,true)==1
  end
  local function clock()
    if g_clock and type(g_clock.millis)=='function' then return g_clock.millis() end
    return os.time()*1000 -- Never use the frozen bot-context now while offline.
  end
  local function online()return game and game.isOnline and game.isOnline()==true end
  local function busy()
    if game and type(game.isLogging)=='function' then
      local ok,v=pcall(game.isLogging);if ok and v then return true end
    end
    local ok,v=pcall(function()
      local p=game.getProtocolGame and game.getProtocolGame()
      return p and p.isConnecting and p:isConnecting()
    end)
    return ok and v==true
  end
  local function character()
    local p=game.getLocalPlayer and game.getLocalPlayer()
    local name=p and p:getName() or (game.getCharacterName and game.getCharacterName())
    local world
    if type(game.getWorldName)=='function' then local ok,v=pcall(game.getWorldName);if ok then world=v end end
    return name,type(world)=='string' and world or nil
  end
  local function root()return g_ui and g_ui.getRootWidget and g_ui.getRootWidget()end
  local function locate(id)
    local r=root();return r and r:recursiveGetChildById(id)
  end
  local function listAndWindow()
    local window=locate('charactersWindow') or locate('characterListWindow')
    for _,id in ipairs({'characters','characterList','characterListPanel'}) do
      local list=(window and window:recursiveGetChildById(id)) or locate(id)
      if live(list) and type(list.getChildren)=='function' then return list,window end
    end
  end
  local function rowName(row)
    if type(row.characterName)=='string' then return row.characterName end
    local label=row:getChildById('characterName') or row:getChildById('name')
    if label and type(label.getText)=='function' then return label:getText() end
  end
  local function classicApi()
    if type(CharacterList)=='table' then return CharacterList end
    local entry=modules and modules.client_entergame
    if entry and type(entry.CharacterList)=='table' then return entry.CharacterList end
    if entry and type(entry.doLogin)=='function' then return entry end
  end
  local pendingError=false
  local function clearConnectionError()
    if not pendingError then return end
    pendingError=false
    local r=root();local children=r and r:getChildren() or {}
    for i=#children,math.max(1,#children-32),-1 do
      local w=children[i]
      if live(w) and type(w.ok)=='function' and callable(w.onOk) and type(w.getText)=='function' then
        local title=normalize(w:getText())
        if title:find('connection',1,true) or title:find('conex',1,true) or title:find('login error',1,true) then
          pcall(w.ok,w);return
        end
      end
    end
  end
  local nativeMuted=false
  local function muteNativeReconnect()
    if nativeMuted then return end
    nativeMuted=true
    -- This script owns retries. Silence a built-in toggle if one exists, but
    -- neither its existence nor its saved setting is required by this service.
    for _,id in ipairs({'autoReconnect','autoReconnectButton','autoReconnectSwitch','autoReconnectCheckBox'}) do
      local button=locate(id)
      if live(button) then
        if callable(button.onCheckChange) and type(button.setChecked)=='function' then pcall(button.setChecked,button,false)
        elseif type(button.setOn)=='function' then pcall(button.setOn,button,false) end
      end
    end
    if g_settings and type(g_settings.set)=='function' then
      pcall(g_settings.set,'autoReconnect',false)
    end
  end
  local function login(name,world)
    -- A native companion left behind by rollback must not keep logging in when
    -- the matching bot frontend has been removed or replaced.
    if not validOwner() then return 'inactive' end
    if online() or busy() then return 'not_ready' end
    clearConnectionError();nativeMuted=false;muteNativeReconnect()
    local list,window=listAndWindow()
    if not list then return 'not_ready' end
    local found,matches=nil,0
    for i,row in ipairs(list:getChildren()) do
      if i>256 then break end
      if normalize(rowName(row))==normalize(name) and
          (not world or not row.worldName or normalize(row.worldName)==normalize(world)) then
        found=row;matches=matches+1
      end
    end
    if matches~=1 then return 'not_ready' end
    if type(list.focusChild)=='function' then list:focusChild(found,KeyboardFocusReason)
    elseif type(found.focus)=='function' then found:focus() else return 'not_ready' end
    local api=classicApi()
    if api and type(api.doLogin)=='function' then api.doLogin();return 'sent' end
    local action=callable(found.onDoubleClick)
    if action then action(found);return 'sent' end
    action=window and callable(window.onEnter)
    if action then action(window);return 'sent' end
    return 'not_ready'
  end
  local function cancelLogin()
    if online() then return end
    if type(game.cancelLogin)=='function' then pcall(game.cancelLogin) end
    local api=classicApi()
    if api and type(api.cancelWait)=='function' then pcall(api.cancelWait) end
  end
  local function notify(message)
    local entry=modules and modules.game_textmessage
    if entry and type(entry.displayStatusMessage)=='function' then pcall(entry.displayStatusMessage,'Reconect: '..message) end
  end
  local preference='rinoAutoReconnectEnabled'
  local function persist(value)
    if g_settings and type(g_settings.set)=='function' then
      if g_settings.set(preference,value)==false then return false end
      if type(g_settings.save)=='function' then pcall(g_settings.save) end
    elseif options.save then return options.save(value)
    else return false end
    return true
  end
  local enabled=options.enabled==true
  if g_settings and type(g_settings.getBoolean)=='function' then
    local ok,value=pcall(g_settings.getBoolean,preference,false)
    if ok and type(value)=='boolean' then enabled=value end
  end
  local C=RinoReconnectCore.new({clock=clock,after=after,cancel=function(e)if e and e.cancel then e:cancel() end end,
    online=online,busy=busy,character=character,login=login,cancelLogin=cancelLogin,persist=persist,enabled=enabled,notify=notify})
  local hooks={}
  local function listen(object,event,callback)
    if not object then return end
    local old=object[event]
    if old==nil then object[event]=callback
    elseif type(old)=='function' then object[event]={old,callback}
    elseif type(old)=='table' then
      local callbacks={};for _,fn in ipairs(old) do callbacks[#callbacks+1]=fn end
      callbacks[#callbacks+1]=callback;object[event]=callbacks
    else return end
    hooks[#hooks+1]={object,event,callback}
  end
  listen(game,'onGameStart',function()nativeMuted=false;C:onStart()end)
  listen(game,'onGameEnd',function()nativeMuted=false;if C.enabled then muteNativeReconnect() end;C:onEnd()end)
  listen(game,'onLogout',function()C:onLogout()end)
  listen(game,'onDeath',function()C:onDeath()end)
  listen(game,'onConnectionError',function(message)pendingError=true;C:onError(message)end)
  listen(game,'onLoginError',function(message)pendingError=true;C:onError(message)end)
  listen(game,'onLoginWait',function(_,seconds)C:onWait(seconds)end)
  listen(game,'onLoginToken',function()C:onAuth()end)
  listen(game,'onUpdateNeeded',function()C:onUpdate()end)
  local result={version=1,build=195}
  function result.attach(path)
    local previous=owner;owner=path
    if not validOwner() then owner=previous;return false,'El script de reconexion no coincide con este bot.' end
    return true
  end
  function result.getStatus()return C:status()end
  function result.setEnabled(value)
    local ok,message=C:setEnabled(value)
    if ok and value then nativeMuted=false;muteNativeReconnect() end
    return ok,message
  end
  function result.shutdown()
    C:shutdown()
    if game.rinoReconnectApi==result then game.rinoReconnectApi=nil end
    for _,hook in ipairs(hooks) do
      local object,event,callback=hook[1],hook[2],hook[3]
      local old=object[event]
      if old==callback then object[event]=nil
      elseif type(old)=='table' then
        local remaining={};for _,fn in ipairs(old) do if fn~=callback then remaining[#remaining+1]=fn end end
        object[event]=#remaining==1 and remaining[1] or #remaining>0 and remaining or nil
      end
    end
    hooks={}
  end
  listen(g_app,'onTerminate',result.shutdown)
  return result
end

-- The companion module is loaded by the client, outside executeBot's lifetime.
function RinoReconnectNativeInit()
  if api and api.shutdown then api.shutdown() end
  local old=modules and modules.game_bot and modules.game_bot.rinoReconnectApi
  if old and old.shutdown then old.shutdown();modules.game_bot.rinoReconnectApi=nil end
  local exposed=g_game and g_game.rinoReconnectApi
  if exposed and exposed~=old and exposed.shutdown then exposed.shutdown() end
  api=Host.start({requireOwner=true})
  if g_game then g_game.rinoReconnectApi=api end
end
function RinoReconnectNativeTerminate()if api and api.shutdown then api.shutdown() end;api=nil end
