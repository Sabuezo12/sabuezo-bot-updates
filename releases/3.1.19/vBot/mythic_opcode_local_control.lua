-- Readiness/report coordination for two clients on the same PC.
-- These files never transport the probe or its opcode acknowledgement.
MythicOpcodeLocalControlFactory = function(api)
  local C={listeners={},serial=0,nextPoll=0,lastSeen=nil,error=nil}
  local boot=api.identity..':'..api.clock()..':'..api.random()
  function C.available()
    local ok,value=pcall(api.ensureDirectory)
    return ok and value~=false
  end
  function C.send(topic,message)
    if not C.available() then C.error='No se pudo crear la carpeta local'; return false end
    C.serial=C.serial+1
    local envelope={id=boot..':'..C.serial,topic=topic,sender=api.identity,message=message}
    local ok,err=pcall(function()
      local encoded=api.encode(envelope)
      assert(type(encoded)=='string','JSON local no disponible')
      local value=api.write(encoded)
      assert(value~=false,'El cliente rechazo escribir la coordinacion local')
    end)
    if not ok then C.error=tostring(err):sub(1,180); return false end
    C.error=nil
    return true
  end
  function C.listen(topic,callback)
    C.listeners[topic]=callback
    return function()
      if C.listeners[topic]==callback then C.listeners[topic]=nil end
    end
  end
  function C.poll()
    local hasListener=false
    for _ in pairs(C.listeners) do hasListener=true; break end
    if not hasListener or api.clock()<C.nextPoll then return end
    C.nextPoll=api.clock()+250
    local ok,raw=pcall(api.read)
    if not ok or type(raw)~='string' or #raw==0 or #raw>12000 then return end
    local decodeOk,envelope=pcall(api.decode,raw)
    -- A concurrent write may be incomplete. Retry it on the next poll.
    if not decodeOk or type(envelope)~='table' or type(envelope.id)~='string' or
      #envelope.id>180 or envelope.id==C.lastSeen or
      tostring(envelope.sender or ''):lower()~=api.peer:lower() or
      type(envelope.topic)~='string' or type(envelope.message)~='table' then return end
    local callback=C.listeners[envelope.topic]
    if not callback then return end
    C.lastSeen=envelope.id
    callback(envelope.sender,envelope.message)
  end
  return C
end
