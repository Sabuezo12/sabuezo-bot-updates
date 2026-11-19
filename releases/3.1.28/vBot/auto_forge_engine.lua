-- Conversion controller. A successful send never counts as server confirmation.
HelperAutoForgeEngine = {}
local E = HelperAutoForgeEngine
local DUST2SLIVER, SLIVER2CORE, UPGRADE_LIMIT = 2, 3, 4
local DUST_COST, SLIVER_COST = 60, 50
local function integer(value)
  value = tonumber(value)
  if value and value == value and value >= 0 and value <= 9007199254740991 and value == math.floor(value) then return value end
end
local function copyBalances(snapshot)
  return {dust=snapshot.dust, slivers=snapshot.slivers, cores=snapshot.cores, gold=snapshot.gold}
end
-- The client has not loaded its Forge data yet. Report these failures as waiting.
local WAIT_CODES = {balances_unavailable=true, rates_not_ready=true, invalid_rates=true}
local function snapshot(raw)
  if type(raw) ~= 'table' or type(raw.sessionId) ~= 'string' or raw.sessionId == '' then
    return nil, 'No hay una sesion Forge confirmada.', 'invalid'
  end
  if type(raw.pending)~='boolean'then return nil,'No se pudo confirmar si Forge tiene una solicitud pendiente.','invalid'end
  local result={sessionId=raw.sessionId,pending=raw.pending,refreshed=raw.refreshed,pendingState=raw.pendingState,pendingOwner=raw.pendingOwner,lastConfirmedToken=raw.lastConfirmedToken,
    lastConfirmedKind=raw.lastConfirmedKind}
  for _,key in ipairs({'dust','slivers','cores','gold'})do
    result[key]=integer(raw[key]);if result[key]==nil then return nil,'No se pudieron leer todos los recursos Forge.','balances_unavailable' end
  end
  if raw.dustCost~=DUST_COST or raw.sliverGain~=3 or raw.sliverCost~=SLIVER_COST or raw.coreGain~=1 then
    return nil,'Las conversiones de este servidor no son 60/3 y 50/1.','mismatch'
  end
  if type(raw.limit)=='table' then
    result.limit={current=integer(raw.limit.current),next=integer(raw.limit.next),
      cost=integer(raw.limit.cost),maximum=integer(raw.limit.maximum)}
  end
  return result
end
local function threshold(value, minimum)
  value=integer(value)
  if value and (value==0 or value>=minimum) then return value end
end
function E.new(options)
  local C={config=assert(options.config),state={kind='off',message='Desactivado'},nextAllowed=0,trace={}}
  local config=C.config
  config.enabled=config.enabled~=false
  config.dustThreshold=threshold(config.dustThreshold,DUST_COST) or DUST_COST
  config.sliverThreshold=threshold(config.sliverThreshold,SLIVER_COST) or SLIVER_COST
  config.dustLimitTarget=integer(config.dustLimitTarget) or 0
  config.confirmed=type(config.confirmed)=='table'and config.confirmed or {dust=0,core=0}
  config.confirmed.dust=integer(config.confirmed.dust)or 0
  config.confirmed.core=integer(config.confirmed.core)or 0
  config.confirmed.limit=integer(config.confirmed.limit)or 0
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
  local function read()
    local ok,raw,reason,code=pcall(options.snapshot)
    if not ok then return nil,'No se pudo consultar Forge.','failed'end
    if not raw then return nil,reason or'No disponible en este cliente.',code end
    return snapshot(raw)
  end
  local function validPending(pending)
    return type(pending)=='table'and(pending.kind==DUST2SLIVER or pending.kind==SLIVER2CORE or
      pending.kind==UPGRADE_LIMIT and type(pending.nextLimit)=='number' and
        integer(pending.nextLimit) and pending.nextLimit>0)and
      type(pending.sessionId)=='string'and integer(pending.at)~=nil and type(pending.before)=='table'and
      integer(pending.before.dust)~=nil and integer(pending.before.slivers)~=nil and
      integer(pending.before.cores)~=nil and integer(pending.before.gold)~=nil
  end
  if config.pending~=nil and not validPending(config.pending)then
    config.pending=nil
    C.nextAllowed=(options.clock()or 0)+pause
    note('Se descarto un registro de conversion incompleto.')
  end
  function C.isOn()return config.enabled==true end
  function C.setRules(dust,slivers,limit)
    dust,slivers,limit=threshold(dust,DUST_COST),threshold(slivers,SLIVER_COST),integer(limit)
    if dust==nil then return false,'Umbral de dust: escribe 0 o un entero desde 60.' end
    if slivers==nil then return false,'Umbral de slivers: escribe 0 o un entero desde 50.' end
    if limit==nil then return false,'Meta del limite: escribe un entero mayor o igual a 0.' end
    config.dustThreshold,config.sliverThreshold,config.dustLimitTarget=dust,slivers,limit
    return true
  end
  function C.setEnabled(enabled)
    config.enabled=enabled==true
    C.failSince=nil
    note(config.enabled and 'Auto Forge activado' or 'Auto Forge desactivado por el usuario')
    return true
  end
  function C.resetAfterReview()
    if config.enabled and C.state.kind~='blocked' then return false,'Desactiva Auto Forge antes de restablecer.'end
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
    state(config.enabled and 'pause' or 'off','Espera restablecida.')
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
          pending.blocked=true
          return state('blocked','Sin confirmacion; detenido para evitar conversiones repetidas.')
        end
        return state('waiting','Esperando datos de Forge para confirmar la conversion...')
      end
      if WAIT_CODES[code]then return state('waiting',reason)end
      if now-C.failSince>=grace then
        return state('unavailable',reason)
      end
      return state('waiting','Esperando datos de Forge...')
    end
    if C.failSince then note('Forge responde de nuevo');C.failSince=nil end
    C.state.snapshot=current
    local pending=config.pending
    if pending then
      if pending.sessionId~=current.sessionId then
        if current.refreshed==false or current.pending then
          return state(pending.blocked and 'blocked' or 'waiting','Esperando saldos actualizados de Forge para reanudar.')
        end
        config.pending=nil
        C.nextAllowed=now+pause
        note('Saldos revisados en la sesion nueva. Se descarto la solicitud anterior.')
        return state(config.enabled and 'pause' or 'off','Saldos actualizados. Espera anterior restablecida.')
      end
      local before=pending.before
      local nativeConfirmed=pending.token~=nil and current.lastConfirmedToken==pending.token and
        current.lastConfirmedKind==pending.kind
      local counted=pending.kind==DUST2SLIVER and current.dust<=before.dust-DUST_COST and
        current.slivers>=before.slivers+3 and current.cores==before.cores or
        pending.kind==SLIVER2CORE and current.slivers<=before.slivers-SLIVER_COST and
        current.cores>=before.cores+1 and current.dust>=before.dust or
        pending.kind==UPGRADE_LIMIT and current.limit and current.limit.current and current.limit.current>=pending.nextLimit
      if current.gold<before.gold and not options.ignoreGoldChange then
        pending.blocked=true
        return state('blocked','El oro cambio durante la espera; revisa Forge antes de seguir.')
      end
      if nativeConfirmed or counted then
        config.pending=nil
        C.nextAllowed=now+pause
        if pending.kind==UPGRADE_LIMIT then
          config.confirmed.limit=config.confirmed.limit+1
          local message='Limite de dust aumentado a '..pending.nextLimit..'.'
          note(message)
          return state('confirmed',message)
        end
        local key=pending.kind==DUST2SLIVER and'dust'or'core'
        config.confirmed[key]=config.confirmed[key]+1
        note(string.format('Confirmado %s: dust %d>%d, slivers %d>%d, cores %d>%d',
          pending.kind==2 and'60 dust > 3 slivers'or'50 slivers > 1 core',
          before.dust,current.dust,before.slivers,current.slivers,before.cores,current.cores))
        return state('confirmed',pending.kind==2 and'Confirmado: 60 dust convertidos en 3 slivers.'or'Confirmado: 50 slivers convertidos en 1 exalted core.')
      end
      if pending.blocked or current.pending and current.pendingState=='unconfirmed'or now-pending.at>=timeout then
        if not pending.blocked then
          note(string.format('Sin cambio de saldos en %d s (dust %d, slivers %d, cores %d)',
            math.floor((now-pending.at)/1000),current.dust,current.slivers,current.cores))
        end
        pending.blocked=true
        return state('blocked','Sin confirmacion; detenido para evitar conversiones repetidas.')
      end
      return state('waiting','Esperando confirmacion del servidor...')
    end
    if current.pending and current.pendingState=='unconfirmed'then
      return state('blocked','Forge tiene una conversion sin confirmar; revisala antes de continuar.')
    end
    if not config.enabled then return state('off','Desactivado')end
    if now<C.nextAllowed then return state('pause','Pausa entre conversiones.')end
    if current.pending then return state('waiting','Forge ocupado con otra solicitud.')end
    local kind,nextLimit
    local limit,target=current.limit,config.dustLimitTarget
    if target>0 then
      if not limit then return state('waiting','Limite de dust no compatible en este cliente. Usa meta 0 para convertir.') end
      if not limit.current then return state('waiting','Esperando el limite de dust del servidor.') end
      if limit.current<target and (not limit.maximum or limit.current<limit.maximum) then
        if not limit.next or not limit.cost or limit.cost<1 or limit.next<=limit.current then
          return state('waiting','Esperando el costo y el siguiente limite de dust.')
        end
        if limit.next<=target then
          if current.dust<limit.cost then
            return state('waiting',string.format('Faltan %d dust para subir el limite a %d.',
              limit.cost-current.dust,limit.next))
          end
          kind,nextLimit=UPGRADE_LIMIT,limit.next
        end
      end
    end

    local dust,slivers=config.dustThreshold,config.sliverThreshold
    kind=kind or (slivers>0 and current.slivers>=slivers and SLIVER2CORE) or
      (dust>0 and current.dust>=dust and DUST2SLIVER)
    if not kind then
      if dust==0 and slivers==0 then return state('ready','Conversiones desactivadas en los umbrales.')end
      if dust>0 and limit and limit.current and dust>limit.current then
        return state('ready',string.format('El umbral de %d dust supera tu limite actual de %d.',dust,limit.current))
      end
      local dustText=dust>0 and dust..' dust' or nil
      local sliverText=slivers>0 and slivers..' slivers' or nil
      return state('ready','Esperando '..(dustText and sliverText and dustText..' o '..sliverText or dustText or sliverText)..'.')
    end
    -- Persist before the call: even a Lua failure after sending must not replay it.
    pending={kind=kind,at=now,sessionId=current.sessionId,before=copyBalances(current),nextLimit=nextLimit}
    config.pending=pending
    local ok,sent,sendReason,token,info=pcall(options.request,kind,nextLimit,target)
    if ok and(type(token)=='string'or integer(token))then pending.token=token end
    if ok and sent==true then
      C.lastRefusal=nil
      if kind==UPGRADE_LIMIT then
        local message='Aumento solicitado a '..nextLimit..' dust. Esperando confirmacion.'
        note(message)
        return state('waiting',message)
      end
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
    pending.blocked=true
    return state('blocked','Resultado de envio desconocido; revisa Forge antes de seguir.')
  end
  function C.readSnapshot()return read()end
  return C
end
