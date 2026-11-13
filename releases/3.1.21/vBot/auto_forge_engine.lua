-- Conversion controller. A successful send never counts as server confirmation.
HelperAutoForgeEngine = {}
local E = HelperAutoForgeEngine
local function integer(value)
  value = tonumber(value)
  if value and value == value and value >= 0 and value <= 9007199254740991 and value == math.floor(value) then return value end
end
local function copyBalances(snapshot)
  return {dust=snapshot.dust, slivers=snapshot.slivers, cores=snapshot.cores, gold=snapshot.gold}
end
-- Read failures that only mean "the client has not loaded its Forge data yet" (just logged
-- in, bot reloaded, window rebuilding). While enabled the engine keeps waiting for them
-- instead of switching itself off; any other failure switches it off after graceMs.
local WAIT_CODES = {balances_unavailable=true, rates_not_ready=true, invalid_rates=true}
local function snapshot(raw)
  if type(raw) ~= 'table' or type(raw.sessionId) ~= 'string' or raw.sessionId == '' then
    return nil, 'No hay una sesion Forge confirmada.', 'invalid'
  end
  if type(raw.pending)~='boolean'then return nil,'No se pudo confirmar si Forge tiene una solicitud pendiente.','invalid'end
  local result={sessionId=raw.sessionId,pending=raw.pending,pendingState=raw.pendingState,pendingOwner=raw.pendingOwner,lastConfirmedToken=raw.lastConfirmedToken,
    lastConfirmedKind=raw.lastConfirmedKind}
  for _,key in ipairs({'dust','slivers','cores','gold'})do
    result[key]=integer(raw[key]);if result[key]==nil then return nil,'No se pudieron leer todos los recursos Forge.','balances_unavailable' end
  end
  if raw.dustCost~=60 or raw.sliverGain~=3 or raw.sliverCost~=50 or raw.coreGain~=1 then
    return nil,'Las conversiones de este servidor no son 60/3 y 50/1.','mismatch'
  end
  return result
end
function E.new(options)
  local C={config=assert(options.config),state={kind='off',message='Desactivado'},nextAllowed=0,trace={}}
  local config=C.config
  config.enabled=config.enabled==true
  config.confirmed=type(config.confirmed)=='table'and config.confirmed or {dust=0,core=0}
  config.confirmed.dust=integer(config.confirmed.dust)or 0
  config.confirmed.core=integer(config.confirmed.core)or 0
  local pause=options.pauseMs or 1500
  local timeout=options.timeoutMs or 20000
  local grace=options.graceMs or 15000
  -- Every decision that matters is kept (last 30) and sent to options.log, so a stop
  -- always leaves its reason behind (console "Acciones" and the diagnostics report).
  local function note(text)
    local at=math.floor(options.clock and options.clock()or 0)
    C.trace[#C.trace+1]={at=at,text=text}
    while #C.trace>30 do table.remove(C.trace,1)end
    if options.log then pcall(options.log,text)end
  end
  local function state(kind,message)
    C.state.kind,C.state.message=kind,message
    if kind=='blocked'or kind=='unavailable'then
      if C.lastLogged~=message then C.lastLogged=message;note(message)end
    else C.lastLogged=nil end
    return C.state
  end
  local function disable(why)
    if config.enabled then note('Auto Forge se desactivo: '..tostring(why))end
    config.enabled=false
  end
  local function read()
    local ok,raw,reason,code=pcall(options.snapshot)
    if not ok then return nil,'No se pudo consultar Forge.','failed'end
    if not raw then return nil,reason or'No disponible en este cliente.',code end
    return snapshot(raw)
  end
  local function validPending(pending)
    return type(pending)=='table'and(pending.kind==2 or pending.kind==3)and
      type(pending.sessionId)=='string'and integer(pending.at)~=nil and type(pending.before)=='table'and
      integer(pending.before.dust)~=nil and integer(pending.before.slivers)~=nil and
      integer(pending.before.cores)~=nil and integer(pending.before.gold)~=nil
  end
  if config.pending~=nil and not validPending(config.pending)then
    config.pending=nil;config.enabled=false
    state('blocked','Espera anterior invalida; activa Auto Forge manualmente.')
  end
  function C.isOn()return config.enabled==true end
  function C.setEnabled(enabled)
    if not enabled then
      if config.enabled then note('Auto Forge desactivado por el usuario')end
      config.enabled=false;return true
    end
    local current,reason,code=read()
    if not current then
      if WAIT_CODES[code]then
        -- Forge has not published its data yet: stay on and start as soon as it does.
        config.enabled=true;C.failSince=nil
        note('Activado; Forge aun no tiene datos: '..tostring(reason))
        state('waiting',reason);return true
      end
      config.enabled=false;state('unavailable',reason);return false,reason
    end
    local pending=config.pending
    if pending and pending.blocked then
      config.enabled=false;return false,'Revisa la conversion anterior antes de reactivar.'
    end
    if current.pending and current.pendingState=='unconfirmed'then
      config.enabled=false;state('blocked','Forge tiene una conversion sin confirmar; revisala antes de continuar.')
      return false,C.state.message
    end
    config.enabled=true;C.failSince=nil
    note(string.format('Auto Forge activado (dust %d, slivers %d, cores %d)',current.dust,current.slivers,current.cores))
    state('ready','Activado; esperando recursos suficientes.');return true
  end
  function C.resetAfterReview()
    if config.enabled then return false,'Desactiva Auto Forge antes de restablecer.'end
    local current,reason=read()
    if not current then return false,reason end
    if options.resetPending then
      local ok,result,resetReason=pcall(options.resetPending,true)
      if not ok or result~=true then return false,resetReason or'El cliente no permite restablecer la solicitud.'end
      local after,afterReason=read()
      if not after then return false,afterReason end
      if after.sessionId~=current.sessionId then return false,'La sesion cambio durante la revision; vuelve a comprobar Forge.'end
      current=after
    end
    if current.pending~=false then return false,'El cliente aun tiene una solicitud pendiente. Revisa Forge o vuelve a entrar.'end
    config.pending=nil
    C.state.snapshot=current
    C.nextAllowed=(options.clock()or 0)+pause
    note('Espera restablecida tras revisar Forge')
    state('off','Espera restablecida; Auto Forge sigue desactivado.')
    return true
  end
  function C.tick()
    local now=math.floor(options.clock()or 0)
    local current,reason,code=read()
    if not current then
      C.state.snapshot=nil
      if not config.enabled then C.failSince=nil;return state('unavailable',reason)end
      if not C.failSince then C.failSince=now;note('Sin datos de Forge: '..tostring(reason))end
      local pending=config.pending
      if pending then
        -- A request is out and cannot be checked: never resend; the wait limit still applies.
        if pending.blocked or now-pending.at>=timeout then
          pending.blocked=true;disable('no se pudo confirmar la conversion pendiente')
          return state('blocked','Sin confirmacion; detenido para evitar conversiones repetidas.')
        end
        return state('waiting','Esperando datos de Forge para confirmar la conversion...')
      end
      if WAIT_CODES[code]then return state('waiting',reason)end
      if now-C.failSince>=grace then
        disable(reason);return state('unavailable',reason)
      end
      return state('waiting','Esperando datos de Forge...')
    end
    if C.failSince then note('Forge responde de nuevo');C.failSince=nil end
    C.state.snapshot=current
    local pending=config.pending
    if pending then
      if pending.sessionId~=current.sessionId then
        config.pending=nil;disable('nueva sesion con una conversion sin cerrar')
        return state('off','Nueva sesion; activa Auto Forge manualmente.')
      end
      local before=pending.before
      local nativeConfirmed=pending.token~=nil and current.lastConfirmedToken==pending.token and
        current.lastConfirmedKind==pending.kind
      local counted=pending.kind==2 and current.dust<=before.dust-60 and current.slivers>=before.slivers+3 and current.cores==before.cores or
        pending.kind==3 and current.slivers<=before.slivers-50 and current.cores>=before.cores+1 and current.dust>=before.dust
      if current.gold<before.gold then
        pending.blocked=true;disable('el oro bajo de '..before.gold..' a '..current.gold..' durante la espera')
        return state('blocked','El oro cambio durante la espera; revisa Forge antes de seguir.')
      end
      if nativeConfirmed or counted then
        config.pending=nil
        local key=pending.kind==2 and'dust'or'core'
        config.confirmed[key]=config.confirmed[key]+1
        C.nextAllowed=now+pause
        note(string.format('Confirmado %s: dust %d>%d, slivers %d>%d, cores %d>%d',
          pending.kind==2 and'60 dust > 3 slivers'or'50 slivers > 1 core',
          before.dust,current.dust,before.slivers,current.slivers,before.cores,current.cores))
        return state('confirmed',pending.kind==2 and'Confirmado: 60 dust convertidos en 3 slivers.'or'Confirmado: 50 slivers convertidos en 1 exalted core.')
      end
      if pending.blocked or current.pending and current.pendingState=='unconfirmed'or now-pending.at>=timeout then
        pending.blocked=true
        disable(string.format('sin cambio de saldos en %d s (dust %d, slivers %d, cores %d)',
          math.floor((now-pending.at)/1000),current.dust,current.slivers,current.cores))
        return state('blocked','Sin confirmacion; detenido para evitar conversiones repetidas.')
      end
      return state('waiting','Esperando confirmacion del servidor...')
    end
    if current.pending and current.pendingState=='unconfirmed'then
      disable('Forge tiene una conversion sin confirmar')
      return state('blocked','Forge tiene una conversion sin confirmar; revisala antes de continuar.')
    end
    if not config.enabled then return state('off','Desactivado')end
    if now<C.nextAllowed then return state('pause','Pausa entre conversiones.')end
    if current.pending then return state('waiting','Forge ocupado con otra solicitud.')end
    local kind=current.slivers>=50 and 3 or current.dust>=60 and 2
    if not kind then return state('ready','Esperando 60 dust o 50 slivers.')end
    -- Persist before the call: even a Lua failure after sending must not replay it.
    pending={kind=kind,at=now,sessionId=current.sessionId,before=copyBalances(current)}
    config.pending=pending
    local ok,sent,sendReason,token,info=pcall(options.request,kind)
    if ok and(type(token)=='string'or integer(token))then pending.token=token end
    if ok and sent==true then
      C.lastRefusal=nil
      note(string.format('Solicitud: %s (dust %d, slivers %d)%s',kind==2 and'60 dust > 3 slivers'or'50 slivers > 1 core',
        current.dust,current.slivers,info and(' - '..tostring(info))or''))
      return state('waiting',kind==2 and'Solicitado: 60 dust a 3 slivers. Esperando confirmacion.'or'Solicitado: 50 slivers a 1 core. Esperando confirmacion.')
    end
    if ok and sent==false then
      config.pending=nil;C.nextAllowed=now+pause
      local why=sendReason or'El cliente no envio la solicitud; se esperara.'
      if C.lastRefusal~=why then C.lastRefusal=why;note(string.format('Solicitud no enviada (dust %d, slivers %d): %s',current.dust,current.slivers,why))end
      return state('waiting',why)
    end
    pending.blocked=true;disable('resultado de envio desconocido')
    return state('blocked','Resultado de envio desconocido; revisa Forge antes de seguir.')
  end
  function C.readSnapshot()return read()end
  return C
end
