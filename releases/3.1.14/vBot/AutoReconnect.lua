-- RinoBot own reconnect frontend R195. Own retries, never a native-toggle mirror.
-- R202: never install plaintext native modules; the encrypted loader rejects them.
AutoReconnect={version=1,build=202}
local A=AutoReconnect
local shared=modules and modules.game_bot
local installError,unavailablePhase
local function configRoot()
  if type(configDir)=='string' and configDir:match('^/bot/[^/]+$') then return configDir end
  local ok,name=pcall(function()return modules.game_bot.contentsPanel.config:getCurrentOption().text end)
  if ok and type(name)=='string' and not name:find('[/\\]') then return '/bot/'..name end
end
local base=configRoot()
local function retireLegacyDescriptor()
  local path='/modules/rinobot_reconnect/rinobot_reconnect.otmod'
  local resources=g_resources
  if not resources or type(resources.fileExists)~='function' then return true end
  local ok,present=pcall(resources.fileExists,path)
  if ok and not present then return true end
  -- Do not read this file: the client's decrypt failure can be fatal before
  -- Lua pcall gets control. Retire only our old autoload descriptor by name.
  if ok and present and type(resources.deleteFile)=='function' then
    pcall(resources.deleteFile,path)
    local checked,remains=pcall(resources.fileExists,path)
    if checked and not remains then return true end
  end
  return false,'Cierra el cliente y elimina modules/rinobot_reconnect/rinobot_reconnect.otmod antes de volver a abrirlo.'
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
  local retired,message=retireLegacyDescriptor()
  if not retired then installError=message;unavailablePhase='cleanup_required';return false,message end
  local service=backend()
  if service then
    installError=nil;unavailablePhase=nil
    if type(service.attach)=='function' and base then return service.attach(base..'/vBot/AutoReconnect.lua') end
    return true
  end
  -- Keep the service in memory only with a native dispatcher. The bot's own
  -- macro/schedule lifetime ends on disconnect and cannot provide this role.
  local after=scheduleEvent
  if type(after)~='function' then
    local core=modules and modules.corelib
    after=core and core.scheduleEvent
  end
  if shared and base and type(after)=='function' then
    local loaded,api,reason=pcall(function()
      dofile('/vBot/reconnect/core.lua');dofile('/vBot/reconnect/host.lua')
      storage.helperUI=type(storage.helperUI)=='table' and storage.helperUI or {}
      return RinoReconnectHost.start({after=after,owner=base..'/vBot/AutoReconnect.lua',enabled=storage.helperUI.autoReconnectEnabled==true,
        save=function(value)
          storage.helperUI.autoReconnectEnabled=value
          if type(saveConfig)=='function' then saveConfig() end
          return true
        end})
    end)
    if loaded and api then
      shared.rinoReconnectApi=api;g_game.rinoReconnectApi=api
      installError=nil;unavailablePhase=nil;return true
    end
    installError=loaded and reason or 'No se pudo cargar el servicio de Reconect en memoria.'
  else
    installError='Este cliente no expone un temporizador nativo para Reconect.'
  end
  unavailablePhase='unsupported'
  return false,installError
end
function A.getStatus()
  local service=backend()
  if unavailablePhase=='cleanup_required' then
    local current=service and service.getStatus()
    return {available=false,enabled=current and current.enabled==true or false,phase=unavailablePhase,message=installError}
  end
  if service then return service.getStatus() end
  return {available=false,enabled=false,phase=unavailablePhase or 'unsupported',message=installError or 'Reconect no esta disponible en este cliente.'}
end
function A.setEnabled(value)
  local existing=backend()
  if value==false and existing then return existing.setEnabled(false) end
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
