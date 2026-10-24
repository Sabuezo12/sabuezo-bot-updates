-- RinoBot own reconnect frontend R195. Own retries, never a native-toggle mirror.
AutoReconnect={version=1}
local A=AutoReconnect
local shared=modules and modules.game_bot
local files={['core.lua']='core.lua',['host.lua']='host.lua',['rinobot_reconnect.otmod']='module.txt'}
local destination='/modules/rinobot_reconnect'
local installError
local function configRoot()
  if type(configDir)=='string' and configDir:match('^/bot/[^/]+$') then return configDir end
  local ok,name=pcall(function()return modules.game_bot.contentsPanel.config:getCurrentOption().text end)
  if ok and type(name)=='string' and not name:find('[/\\]') then return '/bot/'..name end
end
local base=configRoot()
local function install()
  if not base or not g_resources then return false,'No se encontro la carpeta del bot.' end
  local previous,planned={},{ }
  local ok,reason=pcall(function()
    for target,source in pairs(files) do
      local data=g_resources.readFileContents(base..'/vBot/reconnect/'..source)
      assert(type(data)=='string' and #data>0,'Falta un archivo del script de reconexion.')
      local path=destination..'/'..target
      local old=g_resources.fileExists(path) and g_resources.readFileContents(path) or false
      if old and old~=data then
        assert(old:find('RinoBot own reconnect',1,true),'Ya existe un modulo de reconexion ajeno.')
      end
      previous[path]=old;planned[path]=data
    end
    if not g_resources.directoryExists(destination) then g_resources.makeDir(destination) end
    assert(g_resources.directoryExists(destination),'No se pudo preparar el script persistente.')
    -- Activate discovery only after both Lua sources have been verified.
    for _,target in ipairs({'core.lua','host.lua','rinobot_reconnect.otmod'}) do
      local path=destination..'/'..target
      local data=planned[path]
      if previous[path]~=data then
        assert(g_resources.writeFileContents(path,data)~=false and g_resources.readFileContents(path)==data,'No se pudo instalar el script persistente.')
      end
    end
  end)
  if not ok then
    for path,data in pairs(previous) do
      if data then pcall(g_resources.writeFileContents,path,data) end
    end
    return false,'No se pudo preparar Reconect. Revisa permisos o archivos del bot.'
  end
  return true
end
local function backend()
  local native=modules and modules.rinobot_reconnect
  if native and native.api and native.api.version==1 and native.api.build==195 then return native.api end
  local exposed=g_game and g_game.rinoReconnectApi
  if exposed and exposed.version==1 and exposed.build==195 then return exposed end
  local service=shared and shared.rinoReconnectApi
  if service and service.version==1 and service.build==195 then return service end
end
function A.prepare()
  local service=backend()
  if service then
    if type(service.attach)=='function' and base then return service.attach(base..'/vBot/AutoReconnect.lua') end
    return true
  end
  local ok,message=install();if not ok then installError=message;return false,message end
  -- Load directly when a native dispatcher is exposed. Never use game_bot's
  -- macro/schedule executor, which is discarded on disconnect.
  local after=scheduleEvent
  if type(after)~='function' then
    local core=modules and modules.corelib
    after=core and core.scheduleEvent
  end
  if shared and type(after)=='function' then
    dofile('/vBot/reconnect/core.lua');dofile('/vBot/reconnect/host.lua')
    storage.helperUI=type(storage.helperUI)=='table' and storage.helperUI or {}
    local api,message=RinoReconnectHost.start({after=after,owner=base..'/vBot/AutoReconnect.lua',enabled=storage.helperUI.autoReconnectEnabled==true,
      save=function(value)
        storage.helperUI.autoReconnectEnabled=value
        if type(saveConfig)=='function' then saveConfig() end
        return true
      end})
    if api then shared.rinoReconnectApi=api;g_game.rinoReconnectApi=api;installError=nil;return true end
    installError=message
  end
  -- Some clients expose the native module loader without dispatcher globals.
  if g_modules and type(g_modules.discoverModules)=='function' and type(g_modules.ensureModuleLoaded)=='function' then
    pcall(function()g_modules.discoverModules();g_modules.ensureModuleLoaded('rinobot_reconnect')end)
    if backend() then installError=nil;return A.prepare() end
  end
  installError=installError or 'Reinicia el cliente una vez para cargar el script de reconexion.'
  return false,installError
end
function A.getStatus()
  local service=backend()
  if service then return service.getStatus() end
  return {available=false,enabled=false,phase='restart_required',message=installError or 'Reinicia el cliente una vez para cargar Reconect.'}
end
function A.setEnabled(value)
  local ready,message=A.prepare()
  if not ready then return false,message end
  local service=backend()
  if not service then return false,installError end
  return service.setEnabled(value==true)
end
function A.isOn()return A.getStatus().enabled==true end
function A.setOn()return A.setEnabled(true)end
function A.setOff()return A.setEnabled(false)end
A.prepare()
