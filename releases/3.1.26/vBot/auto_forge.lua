setDefaultTab('Tools')
storage.helperAutoForge=type(storage.helperAutoForge)=='table'and storage.helperAutoForge or{}
local config=storage.helperAutoForge
if config.defaultOnInitialized~=true then
  -- Older versions saved automatic stops as OFF, indistinguishable from the switch.
  config.enabled=true
  config.defaultOnInitialized=true
end

local reasons={unsupported='Auto Forge no esta disponible en este cliente.',offline='Sin conexion al juego.',
  balances_unavailable='No se pudieron leer los recursos Forge.',invalid_rates='No se pudieron confirmar los costes Forge.',
  rates_not_ready='Abre Forge una vez para confirmar las conversiones del servidor.',
  busy='Forge esta ocupado con otra accion.',pending='Esperando confirmacion del servidor...',
  unconfirmed='Sin confirmacion; revisa Forge antes de continuar.',
  insufficient_dust='Esperando 60 dust.',insufficient_slivers='Esperando 50 slivers.',
  dust_limit_changed='Forge actualizo el limite o el costo; se volvera a comprobar.',
  request_failed='El cliente no pudo enviar la conversion.',request_in_flight='La solicitud sigue en curso; espera antes de restablecer.',
  explicit_confirmation_required='Revisa Forge antes de restablecer la espera.'}
local function reasonText(reason)
  if reason=='rates_not_ready' and HelperClient and HelperClient.id=='thornia' then
    return 'Esperando los costes y saldos de Forge del servidor.'
  end
  return reasons[reason]or reason
end
local function adapter()
  local forge=modules and modules.game_forge
  local conversion=forge and forge.ForgeController and forge.ForgeController.conversion
  if type(conversion)=='table'and(tonumber(conversion.safeAdapterVersion)or 0)>=20261104 and
      type(conversion.safeAutoConvert)=='function'and type(conversion.autoSnapshot)=='function'then
    return conversion
  end
  -- Clients without the native adapter (e.g. Valkaris): use Helper's own, which
  -- only reads the Forge controller's public state and sends the window's request.
  if HelperForgeAdapter and HelperForgeAdapter.available()then return HelperForgeAdapter end
  return nil,'Auto Forge no esta disponible en este cliente.','unsupported'
end
local function snapshot()
  local conversion,reason,code=adapter()
  if not conversion then return nil,reason,code end
  local current,readReason
  if conversion == HelperForgeAdapter then
    current,readReason=conversion.autoSnapshot(config.enabled,config.pending~=nil,config.dustLimitTarget>0)
  else
    current,readReason=conversion.autoSnapshot()
  end
  return current,reasonText(readReason),readReason
end
local function request(kind,nextLimit,target)
  local conversion,reason=adapter()
  if not conversion then return false,reason end
  local sent,sendReason,token,info
  if conversion == HelperForgeAdapter then
    sent,sendReason,token,info=conversion.safeAutoConvert(kind,nextLimit,target)
  else
    sent,sendReason,token,info=conversion.safeAutoConvert(kind)
  end
  return sent,reasonText(sendReason),token,info
end
local function resetPending(afterReview)
  local conversion=adapter()
  if not conversion then return false end
  if type(conversion.resetAutoPending)=='function'then
    local reset,resetReason=conversion.resetAutoPending(afterReview==true)
    return reset,reasonText(resetReason)
  end
  local current=conversion.autoSnapshot()
  return current and current.pending==false or false
end

-- Every decision (request, confirmation, stop and why) goes to the console under "Acciones".
local function log(message)
  if RinoConsole and type(RinoConsole.log)=='function'then pcall(RinoConsole.log,'action','AutoForge',message)end
end
local engine=HelperAutoForgeEngine.new({config=config,clock=function()return now or 0 end,
  snapshot=snapshot,request=request,resetPending=resetPending,pauseMs=1500,timeoutMs=20000,graceMs=60000,log=log,
  ignoreGoldChange=HelperClient and HelperClient.id=='thornia'})
local panel=UI.createWidget('AutoForgePanel')
local window=UI.createWindow('AutoForgeWindow')
window:hide()
AutoForge={controller=engine,panel=panel,window=window}
function AutoForge.isOn()return engine.isOn()end
function AutoForge.setOn()return engine.setEnabled(true)end
function AutoForge.setOff()return engine.setEnabled(false)end
local function text(widget,value)if widget:getText()~=value then widget:setText(value)end end
local function loadRules()
  text(window.dustThreshold,tostring(config.dustThreshold))
  text(window.sliverThreshold,tostring(config.sliverThreshold))
  text(window.dustLimitTarget,tostring(config.dustLimitTarget))
  text(window.rulesFeedback,'0 desactiva la accion.')
end
local function limitInfo(current)
  if not current then return 'Esperando datos de Forge.' end
  local limit=current.limit
  if not limit then return 'Este cliente no ofrece el aumento automatico del limite.' end
  if not limit.current then return 'Esperando el limite de dust del servidor.' end
  if limit.maximum and limit.current>=limit.maximum then return 'Limite maximo: '..limit.current..' dust.' end
  if limit.next and limit.cost then
    if config.dustLimitTarget>limit.current and config.dustLimitTarget<limit.next then
      return 'La siguiente mejora supera tu meta. Limite actual: '..limit.current..'.'
    end
    return string.format('Siguiente mejora a %d por %d dust.',limit.next,limit.cost)
  end
  return 'Esperando el costo de la siguiente mejora.'
end
local function refresh()
  local status=engine.state
  panel.title:setOn(engine.isOn());window.enabled:setOn(engine.isOn())
  text(panel.status,status.message)
  text(window.status,status.message)
  local current=status.snapshot
  if current then
    local limit=current.limit and current.limit.current
    local dust=limit and current.dust..' / '..limit or tostring(current.dust)
    text(window.resources,string.format('Dust: %s | Slivers: %d | Cores: %d',dust,current.slivers,current.cores))
  else text(window.resources,'Dust: - | Slivers: - | Cores: -')end
  text(window.limitInfo,limitInfo(current))
  text(window.confirmed,string.format('Confirmadas | Dust: %d | Cores: %d | Aumentos: %d',
    config.confirmed.dust,config.confirmed.core,config.confirmed.limit))
  local canReview=not engine.isOn() or status.kind=='blocked'
  window.review:setEnabled(canReview and (config.pending~=nil or current and current.pending==true))
end
local function toggle()
  engine.setEnabled(not engine.isOn())
  engine.tick();refresh()
end
panel.title.onClick=toggle
window.enabled.onClick=toggle
panel.settings.onClick=function()loadRules();engine.tick();refresh();window:show();window:raise();window:focus()end
window.apply.onClick=function()
  local ok,reason=engine.setRules(window.dustThreshold:getText(),window.sliverThreshold:getText(),window.dustLimitTarget:getText())
  if ok then loadRules();engine.tick();refresh()end
  text(window.rulesFeedback,ok and 'Guardado en este perfil. 0 desactiva la accion.' or reason)
end
window.closeButton.onClick=function()window:hide()end
window.onEscape=window.closeButton.onClick
window.review.onClick=function()
  local ok,reason=engine.resetAfterReview()
  if not ok then engine.state.kind='blocked';engine.state.message=reason end
  refresh()
end
AutoForge.open=panel.settings.onClick
macro(500,function()engine.tick();refresh()end)
loadRules();engine.tick();refresh()
