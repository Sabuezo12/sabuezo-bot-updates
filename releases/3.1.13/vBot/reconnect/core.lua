-- RinoBot own reconnect core R195. No credentials or native ON/OFF dependency.
RinoReconnectCore={version=1}
function RinoReconnectCore.new(P)
  local C={enabled=false,armed=false,target=nil,world=nil,phase='off',attempts=0,closed=false}
  local event,serial,busyUntil,waitUntil=nil,0,0,0
  local ownsLogin=false
  local messages={off='Desactivado',online='Conectado',waiting='Esperando para reconectar',
    connecting='Conectando',queue='Esperando la cola del servidor',manual='Logout manual: en pausa',
    death='Esperando aceptar la muerte',auth='Entra manualmente para renovar la sesion',
    update='El cliente necesita actualizarse',waiting_list='Esperando la lista de personajes',
    no_character='Conecta un personaje antes de activar Reconect',inactive='El script del bot ya no esta disponible',
    error='No se pudo programar la reconexion'}
  local function phase(value)
    if C.phase==value then return end
    C.phase=value
    if (value=='auth' or value=='update' or value=='error') and P.notify then P.notify(messages[value]) end
  end
  local function cancel()
    serial=serial+1
    if event then pcall(P.cancel,event);event=nil end
  end
  local function backoff()return math.min(15000,1500*2^math.min(4,math.max(0,C.attempts-1)))end
  local tick,schedule
  schedule=function(delay)
    cancel()
    if C.closed or not C.enabled or not C.armed then return end
    local generation=serial
    local ok,handle=pcall(P.after,function()
      if generation~=serial or C.closed then return end
      event=nil;tick()
    end,math.max(100,delay))
    if not ok or not handle then C.armed=false;phase('error');return end
    event=handle
  end
  local function capture()
    local name,world=P.character()
    if type(name)=='string' and name~='' then C.target,C.world=name,world;return true end
    return false
  end
  tick=function()
    if C.closed or not C.enabled or not C.armed then return end
    if P.online() then C:onStart();return end
    local t=P.clock()
    if t<waitUntil then schedule(waitUntil-t);return end
    if P.busy() then phase('connecting');schedule(1000);return end
    if t<busyUntil then schedule(busyUntil-t);return end
    local before,previousAttempts=serial,C.attempts
    C.attempts=C.attempts+1;ownsLogin=true
    local ok,result=pcall(P.login,C.target,C.world)
    if not ok then result='not_ready' end
    if serial~=before or C.closed or not C.enabled or not C.armed then return end
    if result=='sent' then
      busyUntil=t+15000;phase('connecting');schedule(1000)
    elseif result=='auth' or result=='update' or result=='manual' or result=='inactive' then
      ownsLogin=false;C.attempts=previousAttempts;C.armed=false;phase(result);cancel()
    else ownsLogin=false;C.attempts=previousAttempts;phase('waiting_list');schedule(5000) end
  end
  function C:setEnabled(value)
    if C.closed then return false,'Script cerrado' end
    value=value==true
    if P.persist then
      local ok,result=pcall(P.persist,value)
      if not ok or result==false then return false,'No se pudo guardar Reconect' end
    end
    cancel();self.enabled=value;busyUntil,waitUntil=0,0
    if not value then
      self.armed=false;phase('off')
      if ownsLogin and P.cancelLogin then pcall(P.cancelLogin) end
      ownsLogin=false;return true
    end
    self.attempts=0
    if P.online() then self.armed=capture();phase(self.armed and 'online' or 'no_character')
    elseif self.target then self.armed=true;phase('waiting');schedule(1500)
    else self.armed=false;phase('no_character') end
    return true
  end
  function C:onStart()
    if self.closed then return end
    cancel();busyUntil,waitUntil=0,0;self.attempts=0;ownsLogin=false
    local known=capture();self.armed=self.enabled and known
    phase(not self.enabled and 'off' or known and 'online' or 'no_character')
  end
  function C:onEnd()
    if self.closed or not self.enabled or not self.armed then return end
    busyUntil=0;phase('waiting');schedule(math.max(1500,waitUntil-P.clock()))
  end
  function C:onLogout()
    if self.closed then return end
    cancel();self.armed=false;ownsLogin=false;if self.enabled then phase('manual') end
  end
  function C:onDeath()
    if self.closed then return end
    cancel();self.armed=false;ownsLogin=false;if self.enabled then phase('death') end
  end
  function C:onError(message)
    if self.closed or not self.enabled or not self.armed then return end
    local s=tostring(message or ''):lower()
    if s:find('password',1,true) or s:find('authentic',1,true) or s:find('token',1,true) or
        s:find('banned',1,true) or s:find('banished',1,true) or
        (s:find('session',1,true) and (s:find('expired',1,true) or s:find('invalid',1,true))) then
      return self:onAuth()
    end
    if P.online() then return end
    ownsLogin=false;busyUntil=0;phase('waiting');schedule(math.max(backoff(),waitUntil-P.clock()))
  end
  function C:onWait(seconds)
    if self.closed or not self.enabled or not self.armed then return end
    seconds=tonumber(seconds)
    if not seconds or seconds~=seconds or seconds<0 or seconds>3600 then return end
    -- The native queue owns its scheduled resend. Let it run before considering
    -- another attempt, and never cancel its wait or submit a duplicate request.
    waitUntil=P.clock()+seconds*1000+2000;busyUntil=0;phase('queue');schedule(waitUntil-P.clock())
  end
  function C:onAuth()cancel();self.armed=false;if self.enabled then phase('auth') end end
  function C:onUpdate()cancel();self.armed=false;if self.enabled then phase('update') end end
  function C:status()
    return {available=not self.closed,enabled=self.enabled,armed=self.armed,phase=self.phase,
      message=messages[self.phase] or self.phase,character=self.target,attempts=self.attempts,version=1}
  end
  function C:shutdown()
    cancel();self.closed=true;self.armed=false
    if ownsLogin and P.cancelLogin then pcall(P.cancelLogin) end
    ownsLogin=false
  end
  C.enabled=P.enabled==true
  if P.online() then C:onStart() end
  return C
end
