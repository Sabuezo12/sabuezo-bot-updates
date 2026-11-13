-- Convert opcode-indexed maps before using the client's strict JSON serializer.
MythicOpcodeDiagnosticNormalizeReport = function(report)
  local function object(map)
    local result={}
    for key,value in pairs(type(map)=='table' and map or {}) do result[tostring(key)]=value end
    return result
  end
  for _,field in ipairs({'attempts','skipped','incoming','blocked'}) do report[field]=object(report[field]) end
  local foreign=report.foreign
  if type(foreign)=='table' then
    local isMap=false
    for _,value in pairs(foreign) do if type(value)=='boolean' then isMap=true; break end end
    if isMap then
      local list={}
      for code,value in pairs(foreign) do
        if value and tonumber(code) then list[#list+1]=tonumber(code) end
      end
      table.sort(list); report.foreign=list
    end
  end
  return report
end

-- A two-character diagnostic. A local control channel carries readiness/reports;
-- confirmation requires an acknowledgement received through extended opcode.
MythicOpcodeDiagnosticFactory = function(api)
  local D = {
    armed=false, running=false, disposed=false, dirty=true,
    build='20261013-3', status='Sin iniciar', attempts={}, confirmed={},
    echoes={}, oneWay={}, skipped={}, incoming={}, foreign={}, ackQueue={},
    format='navi', nextSequence=0, received={}
  }
  local PREFIX, TAG = '#SB2#', 'mythicot-navi-opcode-diagnostic'
  local CONTROL = '__mythic_opcode_diag_v1'
  local PROBE, ACK = '__mythic_diag_probe', '__mythic_diag_ack'
  local INTERVAL, TIMEOUT, LIFETIME = 2500, 10000, 15*60*1000
  local ownName, peerName, pinnedProtocol, room, adapter, controlOff
  local nonce, allowedSession, armedAt, heartbeatAt
  local waiting, scan, current, nextSendAt

  local function lower(value) return tostring(value or ''):lower() end
  local function setStatus(text) D.status=text; D.dirty=true end
  local function isCurrent()
    return not D.disposed and api.isOwner() and api.online() and
      api.protocol()==pinnedProtocol and lower(api.name())==lower(ownName) and
      api.room()==room
  end
  local function keys(map)
    local result={}
    for key in pairs(map or {}) do result[#result+1]=tonumber(key) end
    table.sort(result)
    return result
  end
  local function control(action, extra)
    local message=extra or {}
    message.action=action; message.tag=TAG; message.version=1
    message.room=room; message.from=ownName; message.to=peerName
    return api.controlSend(CONTROL, message)
  end
  local function detach()
    if adapter then pcall(adapter.detach); adapter=nil end
    if controlOff then pcall(controlOff); controlOff=nil end
  end
  local function count(map)
    local total=0; for _ in pairs(map or {}) do total=total+1 end
    return total
  end
  function D.report()
    return MythicOpcodeDiagnosticNormalizeReport({
      server='MythicOT', diagnostic=D.build, character=ownName or api.name(),
      peer=peerName, date=api.date(), metadata=api.metadata(), format=D.format,
      status=D.status, attemptedCalls=count(D.attempts),
      confirmed=keys(D.confirmed), echoed=keys(D.echoes),
      oneWay=keys(D.oneWay), received=keys(D.received),
      control='local files, same PC', skipped=D.skipped, attempts=D.attempts,
      availableCallbacks=D.availableCount, blocked=D.localBlocked,
      callbackAdapter=D.adapterMode,
      incoming=D.incoming, foreign=D.foreign,
      note='An attempted native call does not prove the packet was sent. Only an opcode acknowledgement from the other character confirms round-trip delivery.'
    })
  end
  local function save()
    local ok,err=pcall(api.save, D.report())
    D.saveError=not ok and tostring(err) or nil
    D.dirty=true
  end
  function D.stop(reason)
    if D.armed and nonce then control('cancel', {session=nonce}) end
    D.running=false; D.armed=false; waiting=nil; current=nil; scan=nil
    allowedSession=nil; D.ackQueue={}; detach()
    setStatus(reason or 'Detenido'); save()
  end
  function D.cleanup()
    D.disposed=true; D.running=false; D.armed=false
    waiting=nil; current=nil; scan=nil; allowedSession=nil; D.ackQueue={}
    detach()
  end
  local function encode(topic, session, sequence, opcode, format)
    local payload={tag=TAG,session=session,seq=sequence,opcode=opcode,
      from=ownName,to=peerName}
    local packet={v=2,r=room,t=topic,d=payload,n=ownName,
      i=ownName..':'..session..':'..sequence..':'..topic}
    local ok, value=pcall(api.encode, packet)
    if not ok or type(value)~='string' then return nil end
    return (format=='navi' and PREFIX or '')..value
  end
  local function decode(buffer)
    if type(buffer)~='string' or #buffer>2048 then return nil end
    local format='json'
    if buffer:sub(1,#PREFIX)==PREFIX then
      format='navi'; buffer=buffer:sub(#PREFIX+1)
    elseif buffer:sub(1,1)~='{' then return nil end
    local ok, envelope=pcall(api.decode, buffer)
    if not ok or type(envelope)~='table' or envelope.v~=2 or
      envelope.r~=room or (envelope.t~=PROBE and envelope.t~=ACK) or
      type(envelope.d)~='table' or envelope.d.tag~=TAG then return nil end
    local data=envelope.d
    if type(data.session)~='string' or #data.session>100 or
      type(data.seq)~='number' or data.seq<1 or data.seq%1~=0 or
      type(data.opcode)~='number' or lower(envelope.n)~=lower(data.from) then
      return nil
    end
    return envelope,format
  end
  local function send(opcode, packet)
    if not isCurrent() or not packet or not adapter or not adapter.free[opcode] then
      return false,'No preparado o codigo ocupado'
    end
    if D.foreign[opcode] or (adapter.canUse and not adapter.canUse(opcode)) then
      return false,'Ahora pertenece a una funcion del cliente'
    end
    local ok, result=pcall(api.sendOpcode, pinnedProtocol, opcode, packet)
    if not ok then return false,tostring(result):sub(1,180) end
    if result==false then return false,'La API rechazo la llamada' end
    -- Native OTCv8 returns nil even if sending is disabled. This is an attempt.
    return true
  end
  function D.receiveOpcode(protocol, opcode, buffer)
    if not D.armed or not isCurrent() or protocol~=pinnedProtocol then return end
    if api.clock()-(D.lastTick or 0)>3000 then D.cleanup(); return end
    opcode=tonumber(opcode)
    if not opcode or opcode<8 or opcode>255 or opcode%1~=0 then return end
    D.incoming[opcode]=(D.incoming[opcode] or 0)+1
    local envelope,format=decode(buffer)
    if not envelope then
      -- Do not store game payloads; observing ordinary activity reserves a code.
      D.foreign[opcode]=true; D.dirty=true; return
    end
    local data=envelope.d
    if data.opcode~=opcode then return end
    if envelope.t==PROBE and lower(data.from)==lower(ownName) and
      lower(data.to)==lower(peerName) and data.session==nonce then
      local attempt=D.attempts[opcode]
      if attempt and attempt.sequence==data.seq then
        D.echoes[opcode]=true; attempt.echo=true; D.dirty=true
      end
      return
    end
    if lower(data.from)~=lower(peerName) or lower(data.to)~=lower(ownName) then return end
    if envelope.t==PROBE then
      if data.session~=allowedSession or not adapter.free[opcode] or D.foreign[opcode] or
        (adapter.canUse and not adapter.canUse(opcode)) then return end
      local duplicate=allowedSession..':'..data.seq..':'..opcode
      if D.seenProbe==duplicate then return end
      D.seenProbe=duplicate
      D.received[opcode]=true
      -- Replies run from the bot timer, never recursively from a native callback.
      if #D.ackQueue<8 then
        D.ackQueue[#D.ackQueue+1]={opcode=opcode,session=data.session,
          sequence=data.seq,format=format}
        setStatus('Recibido por opcode '..opcode..' desde '..peerName)
      end
      return
    end
    local attempt=D.attempts[opcode]
    if data.session~=nonce or not attempt or attempt.sequence~=data.seq or
      attempt.format~=format or not D.running or waiting then return end
    D.confirmed[opcode]=true
    attempt.roundTripMs=math.max(0,api.clock()-attempt.at)
    attempt.confirmed=true
    D.stop('CONFIRMADO: opcode '..opcode..' | '..attempt.roundTripMs..' ms')
  end
  local function receiveControl(sender, message)
    if not D.armed or not isCurrent() or type(message)~='table' or
      message.tag~=TAG or message.version~=1 or message.room~=room or
      lower(sender)~=lower(peerName) or lower(message.from)~=lower(sender) or
      lower(message.to)~=lower(ownName) then return end
    if api.clock()-(D.lastTick or 0)>3000 then D.cleanup(); return end
    if message.action=='query' and not D.running and type(message.session)=='string' and
      #message.session<=100 then
      allowedSession=message.session; D.seenProbe=nil; D.received={}
      local free={}
      for opcode in pairs(adapter.free) do
        if not D.foreign[opcode] and (not adapter.canUse or adapter.canUse(opcode)) then
          free[#free+1]=opcode
        end
      end
      table.sort(free)
      control('ready',{session=allowedSession,free=free,diagnostic=D.build})
      setStatus('Escuchando a '..peerName..'; preparado')
    elseif message.action=='ready' and waiting and message.session==nonce then
      if message.diagnostic~=D.build or type(message.free)~='table' or #message.free>248 then
        D.stop('El otro personaje tiene otro diagnostico'); return
      end
      D.peerFree={}
      for _,opcode in ipairs(message.free) do
        if type(opcode)=='number' and opcode>=8 and opcode<=255 and opcode%1==0 then
          D.peerFree[opcode]=true
        end
      end
      waiting=nil; nextSendAt=api.clock()
      setStatus('Ambos preparados; probando '..D.format)
    elseif message.action=='observed' and message.session==nonce then
      local opcode=tonumber(message.opcode)
      local attempt=opcode and D.attempts[opcode]
      if attempt and attempt.sequence==message.seq then
        D.oneWay[opcode]=true; attempt.peerReceived=true; D.dirty=true
      end
    elseif message.action=='cancel' and message.session==allowedSession then
      allowedSession=nil; D.ackQueue={}; setStatus('Escuchando; prueba finalizada')
    end
  end
  function D.arm()
    if D.disposed or not api.isOwner() then return false end
    if D.armed then return true end
    ownName=api.name()
    if lower(ownName)=='sabuezo' then peerName='Rod Master'
    elseif lower(ownName)=='rod master' then peerName='Sabuezo'
    else setStatus('Usa Sabuezo o Rod Master'); return false end
    pinnedProtocol=api.protocol(); room=api.room()
    if not api.online() or not pinnedProtocol then
      setStatus('Conecta el personaje al juego'); return false
    end
    if not api.controlConnected() then
      setStatus('No disponible la coordinacion local'); return false
    end
    local ok,result=pcall(api.attachOpcodes, D.receiveOpcode)
    if not ok or type(result)~='table' then
      setStatus('No se pudo preparar: '..tostring(result)); return false
    end
    adapter=result; D.adapterMode=adapter.mode; D.localBlocked=adapter.blocked
    D.availableCount=count(adapter.free)
    if D.availableCount==0 then
      detach()
      setStatus('NO SE PROBO: 248 codigos ocupados. Reinicia ambos clientes.')
      save(); return false
    end
    local listenOk,off=pcall(api.controlListen,CONTROL,receiveControl)
    if not listenOk or type(off)~='function' then
      detach(); setStatus('No se pudo escuchar la coordinacion local'); return false
    end
    controlOff=off; D.armed=true; armedAt=api.clock(); heartbeatAt=armedAt
    D.lastTick=armedAt
    setStatus('Escuchando; listo para '..peerName)
    return true
  end
  function D.start(kind, format)
    if D.running then return false end
    if not D.arm() then return false end
    if lower(ownName)~='sabuezo' then
      setStatus('Inicia la prueba desde Sabuezo'); return false
    end
    D.format=format=='json' and 'json' or 'navi'
    D.attempts={}; D.confirmed={}; D.echoes={}; D.oneWay={}; D.skipped={}
    D.peerFree={}; D.ackQueue={}; D.nextSequence=D.nextSequence+1
    nonce=tostring(api.clock())..':'..tostring(D.nextSequence)..':'..api.random()
    scan={order={},index=1}
    if kind=='single' then scan.order={201}
    else
      scan.order={201}
      local first=kind=='all' and 8 or 200
      for opcode=first,255 do if opcode~=201 then scan.order[#scan.order+1]=opcode end end
    end
    D.running=true; current=nil; waiting=api.clock()+TIMEOUT
    if not control('query',{session=nonce,diagnostic=D.build}) then
      D.stop('No se pudo escribir la coordinacion local'); return false
    end
    setStatus('Esperando que Rod Master pulse Escuchar')
    return true
  end
  function D.tick()
    if not D.armed or D.disposed then return end
    local clock=api.clock()
    D.lastTick=clock
    if not isCurrent() then D.stop('Detenido: cambio de personaje o conexion'); return end
    if clock-armedAt>LIFETIME then D.stop('Detenido: limite de 15 minutos'); return end
    if api.controlPoll then api.controlPoll() end
    if not D.armed then return end
    if clock-heartbeatAt>=5000 then
      heartbeatAt=clock
      if not api.controlConnected() then D.stop('Detenido: coordinacion local no disponible'); return end
    end
    if #D.ackQueue>0 then
      local item=table.remove(D.ackQueue,1)
      if item.session==allowedSession then
        local packet=encode(ACK,item.session,item.sequence,item.opcode,item.format)
        local ok,err=send(item.opcode,packet)
        control('observed',{session=item.session,seq=item.sequence,opcode=item.opcode})
        if not ok then setStatus('Llego '..item.opcode..'; respuesta rechazada: '..err) end
      end
    end
    if not D.running then return end
    if waiting then
      if clock>=waiting then D.stop('Sin prueba: Rod Master no confirmo que esta preparado') end
      return
    end
    if current then
      if clock<nextSendAt then return end
      current=nil
    end
    local opcode
    while scan.index<=#scan.order do
      local candidate=scan.order[scan.index]; scan.index=scan.index+1
      if adapter.free[candidate] and D.peerFree[candidate] and not D.foreign[candidate] and
        (not adapter.canUse or adapter.canUse(candidate)) then
        opcode=candidate; break
      end
      D.skipped[candidate]=D.foreign[candidate] and 'Actividad normal observada' or
        adapter.blocked[candidate] or 'Ocupado o no disponible en Rod Master'
    end
    if not opcode then
      if count(D.oneWay)>0 then D.stop('Solo ida: llego a Rod Master; sin confirmacion por opcode')
      elseif count(D.echoes)>0 then D.stop('Solo eco local; sin comunicacion confirmada entre personajes')
      elseif count(D.attempts)==0 then D.stop('NO SE PROBO: los candidatos estan ocupados')
      else D.stop('Sin respuestas con este formato; relay no confirmado') end
      return
    end
    D.nextSequence=D.nextSequence+1
    local packet=encode(PROBE,nonce,D.nextSequence,opcode,D.format)
    local attempt={sequence=D.nextSequence,format=D.format,at=clock}
    -- Install the attempt before native send; a callback may fire synchronously.
    D.attempts[opcode]=attempt; current=opcode
    local ok,err=send(opcode,packet)
    attempt.callAccepted=ok; attempt.error=err
    if not D.running then return end
    nextSendAt=clock+INTERVAL
    -- The final candidate gets an additional reply window.
    if scan.index>#scan.order then nextSendAt=clock+5000 end
    if D.running then
      setStatus('Probando '..opcode..' | '..count(D.attempts)..' intentos | '..D.format)
    end
  end
  function D.summary()
    local function list(map)
      local sorted=keys(map)
      for i,v in ipairs(sorted) do sorted[i]=tostring(v) end
      return #sorted>0 and table.concat(sorted,', ') or '-'
    end
    local meta=api.metadata()
    return table.concat({
      'MythicOT | '..D.build,
      (ownName or api.name())..' -> '..(peerName or 'el otro personaje'),
      'Protocolo: '..tostring(meta.protocol)..' | cliente: '..tostring(meta.client),
      D.status,
      'Intentos: '..count(D.attempts)..' | omitidos: '..count(D.skipped),
      'Confirmados ida/vuelta: '..list(D.confirmed),
      'Llegaron al otro: '..list(D.oneWay)..' | ecos locales: '..list(D.echoes),
      'Recibidos de '..(peerName or 'otro personaje')..': '..list(D.received),
      'Sin respuesta no descarta otro formato ni confirma que el paquete salio.'
    },'\n')
  end
  return D
end
