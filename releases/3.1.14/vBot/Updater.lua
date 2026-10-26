local UpdateTx = (function()
-- RinoBot transactional installer. Uses only the public game_bot context.
local Tx = {protocol=1}
local B = bit32 or bit
assert(B and B.band and B.bxor and B.rshift, "Updater: faltan operaciones de bits.")
local band, bxor, bnot, rshift = B.band, B.bxor, B.bnot, B.rshift
local rotate = B.rrotate or B.ror
assert(rotate, "Updater: falta la rotacion de bits.")
local K={0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2}
local MOD=4294967296
local function word(n)
  return string.char(math.floor(n/16777216)%256,math.floor(n/65536)%256,math.floor(n/256)%256,n%256)
end
function Tx.sha256Stepper(s)
  assert(type(s)=="string", "Updater: contenido invalido.")
  local length=#s
  s=s..string.char(128)..string.rep(string.char(0),(55-length)%64)..word(math.floor(length/536870912))..word((length*8)%MOD)
  local h={0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19}
  local offset=1
  return function(blocks)
  local last=math.min(#s,offset+64*blocks-1)
  while offset<=last do
    local w={}
    for i=0,15 do
      local a,b,c,d=s:byte(offset+i*4,offset+i*4+3);w[i]=a*16777216+b*65536+c*256+d
    end
    for i=16,63 do
      local a,b=w[i-15],w[i-2]
      w[i]=(w[i-16]+bxor(rotate(a,7),rotate(a,18),rshift(a,3))+w[i-7]+bxor(rotate(b,17),rotate(b,19),rshift(b,10)))%MOD
    end
    local a,b,c,d,e,f,g,j=h[1],h[2],h[3],h[4],h[5],h[6],h[7],h[8]
    for i=0,63 do
      local t1=(j+bxor(rotate(e,6),rotate(e,11),rotate(e,25))+bxor(band(e,f),band(bnot(e),g))+K[i+1]+w[i])%MOD
      local t2=(bxor(rotate(a,2),rotate(a,13),rotate(a,22))+bxor(band(a,b),band(a,c),band(b,c)))%MOD
      j,g,f,e,d,c,b,a=g,f,e,(d+t1)%MOD,c,b,a,(t1+t2)%MOD
    end
    local v={a,b,c,d,e,f,g,j};for i=1,8 do h[i]=(h[i]+v[i])%MOD end
    offset=offset+64
  end
  if offset<=#s then return nil end
  local out="";for i=1,8 do out=out..string.format("%08x",h[i]) end;return out
  end
end
function Tx.sha256(s) return Tx.sha256Stepper(s)(math.huge) end
local function relative(p)
  assert(type(p)=="string" and #p>0 and #p<240 and not p:find("[^%w%._%-%s/]"),"Updater: ruta invalida.")
  assert(p:sub(1,1)~="/" and p:sub(-1)~="/" and not p:find("..",1,true) and not p:find("//",1,true),"Updater: ruta insegura.")
  return p
end
local function backupRelative(p)
  assert(type(p)=="string" and #p>0 and #p<1024 and p:sub(1,1)~="/" and not p:find("[\\:%c]") and not p:find("..",1,true) and not p:find("//",1,true),"Updater: ruta de respaldo invalida.")
  return p
end
function Tx.allowed(p)
  local ok=pcall(relative,p);if not ok then return false end
  if p=="_Loader.lua" or p=="dummy.lua" then return true end
  if not (p:match("^vBot/") or p:match("^cavebot/") or p:match("^targetbot/") or p:match("^zFreeScripts/") or p:match("^zPaidScripts/")) then return false end
  for part in p:gmatch("[^/]+") do
    local low=part:lower()
    if low=="storage" or low=="profiles" or low=="_helper_profiles" or low=="vbot_configs" or low=="cavebot_configs" or low=="targetbot_configs" or low:sub(1,1)=="_" then return false end
  end
  local ext=p:match("%.([%w]+)$")
  return ext=="lua" or ext=="otui" or ext=="ui" or ext=="png" or ext=="otfont" or ext=="txt" or p=="vBot/HelperProfileDefaults.json"
end
local function digest(v) return type(v)=="string" and #v==64 and not v:find("[^0-9a-f]") end
function Tx.new(R,J,base,config)
  assert(type(base)=="string" and base:match("^/bot/[^/]+$") and not base:find("..",1,true),"Updater: carpeta invalida.")
  local T={root=base,config=config}
  local home=base.."/_updates/transactions"
  local current=base.."/_updates/pending.json"
  local function read(p) return assert(R.readFileContents(p),"Updater: no se puede leer "..p) end
  local function dirs(p)
    local v="";for part in p:gmatch("[^/]+") do
      v=v.."/"..part
      if not R.directoryExists(v) then R.makeDir(v) end
      assert(R.directoryExists(v),"Updater: no se puede crear "..v)
    end
  end
  local function write(p,s)
    dirs(p:match("^(.*)/[^/]+$"))
    assert(R.writeFileContents(p,s)~=false and R.fileExists(p) and read(p)==s,"Updater: escritura incompleta "..p)
  end
  local function put(p,v) write(p,J.encode(v,2)) end
  local function get(p) return J.decode(read(p)) end
  local function locked() return R.fileExists(base.."/_helper_dev/development.lock") end
  local function hashed(p) return R.fileExists(p) and Tx.sha256(read(p)) or false end
  T.locked=locked;T.write=write
  -- Both planners use the same validation and conflict rules. Only the
  -- background reader yields; commit/rollback still re-read actual disk data.
  local function planner(manifest)
    assert(type(manifest)=="table" and type(manifest.files)=="table" and #manifest.files>0 and #manifest.files<=2000,"Updater: manifest vacio o invalido.")
    assert(type(manifest.version)=="string" and #manifest.version<80 and manifest.version~="3.0.17","Updater: version invalida.")
    assert(not manifest.installProtocol or manifest.installProtocol==1,"Updater: protocolo incompatible.")
    local pending,seen,total={}, {},0
    local function validate(e)
      assert(type(e)=="table" and Tx.allowed(e.path),"Updater: archivo no permitido: "..tostring(e and e.path))
      local key=e.path:lower();assert(not seen[key],"Updater: ruta duplicada.");seen[key]=true
      assert(digest(e.sha256) and type(e.size)=="number" and e.size>=0 and e.size%1==0 and e.size<=100*1024*1024,"Updater: hash o tamano invalido: "..e.path)
      assert(type(e.url)=="string" and e.url:match("^https://"),"Updater: descarga insegura.")
      total=total+e.size;assert(total<=256*1024*1024,"Updater: paquete demasiado grande.")
    end
    local function accept(e,old)
      if old~=e.sha256 then
        if old then
          local known=type(config.fileHashes)=="table" and config.fileHashes[e.path]==old
          for _,hash in ipairs(e.acceptedSha256 or {}) do assert(digest(hash),"Updater: hash de origen invalido.");known=known or old==hash end
          assert(known,"Archivo personalizado: "..e.path..". Se conserva; revisalo antes de actualizar.")
        end
        pending[#pending+1]=e
      end
    end
    return pending,validate,accept
  end
  function T.plan(manifest)
    local pending,validate,accept=planner(manifest)
    for _,e in ipairs(manifest.files) do validate(e);accept(e,hashed(base.."/"..e.path)) end
    return pending
  end
  function T.planAsync(manifest,enqueue,complete,valid)
    local index,entry,step,pending,validate,accept=0
    local hashes,finished={},false
    local function batch()
      if finished or valid and not valid() then finished=true;return end
      local ready=false
      local ok,message=pcall(function()
        if not pending then pending,validate,accept=planner(manifest) end
        local started,work=os.clock(),0
        repeat
          if not entry then
            index=index+1;entry=manifest.files[index]
            if not entry then ready=true;return end
            validate(entry)
            local path=base.."/"..entry.path
            if R.fileExists(path) then step=Tx.sha256Stepper(read(path)) end
          end
          local hash=false
          if step then hash=step(8) end
          if hash~=nil then
            hashes[entry.path]=hash;accept(entry,hash)
            entry,step=nil,nil
          end
          work=work+1
        until work>=64 or os.clock()-started>=0.002
      end)
      if not ok then finished=true;complete(false,tostring(message))
      elseif ready then finished=true;complete(true,pending,hashes)
      else enqueue(20,batch) end
    end
    enqueue(20,batch)
  end
  function T.begin(manifest,files)
    assert(not locked(),"Updater: desarrollo protegido.")
    if R.fileExists(current) then
    local previous=get(current)
      assert(previous.status=="complete" or previous.status=="rolledBack" or previous.status=="aborted","Updater: hay una instalacion pendiente de recuperar.")
    end
    dirs(home)
    local n=1;while R.directoryExists(home.."/t"..n) do n=n+1 end
    local path=home.."/t"..n;dirs(path)
    local S={path=path,manifest=manifest,files=files,status="download",staged={}}
    function S.stage(e,data)
      assert(not locked(),"Updater: desarrollo protegido.")
      assert(type(data)=="string" and #data==e.size and Tx.sha256(data)==e.sha256,"Updater: descarga incompleta o hash incorrecto: "..e.path)
      if e.path:match("%.lua$") then
        assert(#data>0 and not data:find("One-time update: keep every published ".."Lua file",1,true),"Updater: codigo vacio o retirado.")
        assert(loadstring(data),"Updater: Lua invalido: "..e.path)
      end
      write(path.."/stage/"..e.path,data);S.staged[e.path]=true
    end
    function S.apply(barrierPrefix)
      assert(not locked(),"Updater: desarrollo protegido.")
      local still=T.plan(manifest);assert(#still==#files,"Updater: los archivos cambiaron durante la descarga; vuelve a intentar.")
      local entries,hasLoader={},false
      for _,e in ipairs(files) do
        assert(S.staged[e.path] and hashed(path.."/stage/"..e.path)==e.sha256,"Updater: falta una descarga verificada.")
        entries[#entries+1]={path=e.path,after=e.sha256,before=hashed(base.."/"..e.path)}
        hasLoader=hasLoader or e.path=="_Loader.lua"
      end
      local oldLoader=read(base.."/_Loader.lua")
      if not hasLoader then
        local hash=Tx.sha256(oldLoader);entries[#entries+1]={path="_Loader.lua",before=hash,after=hash}
        write(path.."/stage/_Loader.lua",oldLoader)
      end
      -- Snapshot all personal files and current code after download, before replacement.
      local inventory,total={},0
      local skip={_updates=true,_helper_dev=true,_archive=true,Sabuezo2=true}
      local function walk(dir,rel,depth)
        assert(depth<30,"Updater: demasiadas carpetas.")
        for _,name in ipairs(R.listDirectoryFiles(dir,false,false)) do
          if name:sub(1,#dir+1)==dir.."/" then name=name:sub(#dir+2) end
          assert(not name:find("/",1,true),"Updater: listado de carpeta invalido.")
          local sub=rel=="" and name or rel.."/"..name
          backupRelative(sub)
          if not (rel=="" and skip[name]) then
            local source=base.."/"..sub
            if R.fileExists(source) then
              local data=read(source);total=total+#data;assert(total<=512*1024*1024,"Updater: respaldo demasiado grande.")
              write(path.."/backup/"..sub,data)
              inventory[#inventory+1]={path=sub,sha256=Tx.sha256(data),size=#data}
            elseif R.directoryExists(source) then walk(source,sub,depth+1) end
          end
        end
      end
      walk(base,"",0)
      local backupMap={};for _,e in ipairs(inventory) do backupMap[e.path]=e.sha256 end
      for _,e in ipairs(entries) do assert(not e.before or backupMap[e.path]==e.before,"Updater: archivo cambio al respaldar: "..e.path) end
      put(path.."/backup-index.json",inventory)
      local barrier=assert(barrierPrefix)..oldLoader
      local journal={protocol=1,path=path,status="applying",version=manifest.version,previousVersion=config.version or "none",entries=entries,
        backupIndexSha256=hashed(path.."/backup-index.json"),barrierSha256=Tx.sha256(barrier),awaitBoot=manifest.awaitBoot==true}
      put(path.."/journal.json",journal);put(current..".previous",journal);put(current,journal)
      S.status="applying"
      local ok,message=pcall(function()
        -- The loader guard recovers a power loss before any mixed-version module loads.
        write(base.."/_Loader.lua",barrier)
        for _,e in ipairs(entries) do
          if e.path~="_Loader.lua" then
            assert(not locked(),"Updater: desarrollo protegido.")
            write(base.."/"..e.path,read(path.."/stage/"..e.path))
          end
        end
        write(base.."/_Loader.lua",read(path.."/stage/_Loader.lua"))
        journal.status=journal.awaitBoot and "pendingBoot" or "complete"
        put(current,journal)
      end)
      if not ok then
        local restored,reason=T.rollback()
        assert(restored,tostring(message).."; recuperacion pendiente: "..tostring(reason))
        assert(false,tostring(message))
      end
      config.fileHashes=config.fileHashes or {}
      for _,e in ipairs(manifest.files) do config.fileHashes[e.path]=e.sha256 end
      config.version=manifest.version;config.lastBackup=path;config.failedVersion=nil
      S.status=journal.status;return path
    end
    return S
  end
  local function journal()
    local ok,j=pcall(get,current)
    if not ok and R.fileExists(current..".previous") then j=get(current..".previous") end
    assert(type(j)=="table" and j.protocol==1 and type(j.path)=="string" and j.path:match("^"..home:gsub("(%W)","%%%1").."/t%d+$") and type(j.entries)=="table","Updater: registro de recuperacion invalido.")
    return j
  end
  function T.rollback()
    local ok,message=pcall(function()
      assert(not locked(),"Updater: desarrollo protegido.")
      local j=journal()
      assert(hashed(j.path.."/backup-index.json")==j.backupIndexSha256,"Updater: respaldo alterado.")
      -- Verify every required backup and destination before restoring anything.
      for _,e in ipairs(j.entries) do
        assert(Tx.allowed(e.path) and digest(e.after) and (e.before==false or digest(e.before)),"Updater: registro inseguro.")
        if e.before then assert(hashed(j.path.."/backup/"..e.path)==e.before,"Updater: respaldo incompleto.") end
        local h=hashed(base.."/"..e.path)
        assert(h==e.before or h==e.after or (e.path=="_Loader.lua" and h==j.barrierSha256) or j.status=="applying","Updater: cambio posterior detectado: "..e.path)
      end
      -- Restore loader last, so interrupted recovery is itself recoverable.
      for pass=1,2 do for _,e in ipairs(j.entries) do
        if (e.path=="_Loader.lua")== (pass==2) then
          if e.before then write(base.."/"..e.path,read(j.path.."/backup/"..e.path))
          elseif R.fileExists(base.."/"..e.path) then
            assert(R.deleteFile(base.."/"..e.path)~=false and not R.fileExists(base.."/"..e.path),"Updater: no se pudo retirar "..e.path)
          end
        end
      end end
      j.status="rolledBack";put(current,j)
      config.version=j.previousVersion;config.fileHashes={};config.autoInstall=false;config.lastBackup=j.path;config.failedVersion=j.version
    end)
    return ok,message
  end
  function T.boot()
    if not R.fileExists(current) then return false end
    local j=journal()
    if j.status=="applying" or j.status=="booting" then
      local ok,message=T.rollback();assert(ok,message);return "restored"
    end
    if j.status=="rolledBack" then
      config.version=j.previousVersion;config.autoInstall=false;config.fileHashes={};config.lastBackup=j.path;config.failedVersion=j.version
      return "rolledBack"
    end
    if j.status~="pendingBoot" then return false end
    for _,e in ipairs(j.entries) do assert(hashed(base.."/"..e.path)==e.after,"Updater: instalacion incompleta: "..e.path) end
    config.version=j.version;config.lastBackup=j.path
    config.fileHashes=type(config.fileHashes)=="table" and config.fileHashes or {}
    for _,e in ipairs(j.entries) do config.fileHashes[e.path]=e.after end
    j.status="booting";put(current,j);return "validate"
  end
  function T.confirm()
    if not R.fileExists(current) then return end
    local j=journal();assert(j.status=="booting","Updater: inicio no validado.")
    j.status="complete";put(current,j)
    local report={version=j.version,backup=j.path,completedAt=os.date("!%Y-%m-%dT%H:%M:%SZ"),status="complete"}
    local migration=base.."/_helper_profiles/migration-report.json"
    if R.fileExists(migration) then report.profiles=get(migration).profiles end
    put(base.."/_updates/last-result.json",report)
  end
  return T
end
return Tx

end)()
local recoveryLoaderPrefix = [====[
-- RinoBot recovery runs before loading engines or migrating profiles.
local RinoBotUpdateCore = (function()
-- RinoBot transactional installer. Uses only the public game_bot context.
local Tx = {protocol=1}
local B = bit32 or bit
assert(B and B.band and B.bxor and B.rshift, "Updater: faltan operaciones de bits.")
local band, bxor, bnot, rshift = B.band, B.bxor, B.bnot, B.rshift
local rotate = B.rrotate or B.ror
assert(rotate, "Updater: falta la rotacion de bits.")
local K={0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2}
local MOD=4294967296
local function word(n)
  return string.char(math.floor(n/16777216)%256,math.floor(n/65536)%256,math.floor(n/256)%256,n%256)
end
function Tx.sha256(s)
  assert(type(s)=="string", "Updater: contenido invalido.")
  local length=#s
  s=s..string.char(128)..string.rep(string.char(0),(55-length)%64)..word(math.floor(length/536870912))..word((length*8)%MOD)
  local h={0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19}
  for offset=1,#s,64 do
    local w={}
    for i=0,15 do
      local a,b,c,d=s:byte(offset+i*4,offset+i*4+3);w[i]=a*16777216+b*65536+c*256+d
    end
    for i=16,63 do
      local a,b=w[i-15],w[i-2]
      w[i]=(w[i-16]+bxor(rotate(a,7),rotate(a,18),rshift(a,3))+w[i-7]+bxor(rotate(b,17),rotate(b,19),rshift(b,10)))%MOD
    end
    local a,b,c,d,e,f,g,j=h[1],h[2],h[3],h[4],h[5],h[6],h[7],h[8]
    for i=0,63 do
      local t1=(j+bxor(rotate(e,6),rotate(e,11),rotate(e,25))+bxor(band(e,f),band(bnot(e),g))+K[i+1]+w[i])%MOD
      local t2=(bxor(rotate(a,2),rotate(a,13),rotate(a,22))+bxor(band(a,b),band(a,c),band(b,c)))%MOD
      j,g,f,e,d,c,b,a=g,f,e,(d+t1)%MOD,c,b,a,(t1+t2)%MOD
    end
    local v={a,b,c,d,e,f,g,j};for i=1,8 do h[i]=(h[i]+v[i])%MOD end
  end
  local out="";for i=1,8 do out=out..string.format("%08x",h[i]) end;return out
end
local function relative(p)
  assert(type(p)=="string" and #p>0 and #p<240 and not p:find("[^%w%._%-%s/]"),"Updater: ruta invalida.")
  assert(p:sub(1,1)~="/" and p:sub(-1)~="/" and not p:find("..",1,true) and not p:find("//",1,true),"Updater: ruta insegura.")
  return p
end
local function backupRelative(p)
  assert(type(p)=="string" and #p>0 and #p<1024 and p:sub(1,1)~="/" and not p:find("[\\:%c]") and not p:find("..",1,true) and not p:find("//",1,true),"Updater: ruta de respaldo invalida.")
  return p
end
function Tx.allowed(p)
  local ok=pcall(relative,p);if not ok then return false end
  if p=="_Loader.lua" or p=="dummy.lua" then return true end
  if not (p:match("^vBot/") or p:match("^cavebot/") or p:match("^targetbot/") or p:match("^zFreeScripts/") or p:match("^zPaidScripts/")) then return false end
  for part in p:gmatch("[^/]+") do
    local low=part:lower()
    if low=="storage" or low=="profiles" or low=="_helper_profiles" or low=="vbot_configs" or low=="cavebot_configs" or low=="targetbot_configs" or low:sub(1,1)=="_" then return false end
  end
  local ext=p:match("%.([%w]+)$")
  return ext=="lua" or ext=="otui" or ext=="ui" or ext=="png" or ext=="otfont" or ext=="txt" or p=="vBot/HelperProfileDefaults.json"
end
local function digest(v) return type(v)=="string" and #v==64 and not v:find("[^0-9a-f]") end
function Tx.new(R,J,base,config)
  assert(type(base)=="string" and base:match("^/bot/[^/]+$") and not base:find("..",1,true),"Updater: carpeta invalida.")
  local T={root=base,config=config}
  local home=base.."/_updates/transactions"
  local current=base.."/_updates/pending.json"
  local function read(p) return assert(R.readFileContents(p),"Updater: no se puede leer "..p) end
  local function dirs(p)
    local v="";for part in p:gmatch("[^/]+") do
      v=v.."/"..part
      if not R.directoryExists(v) then R.makeDir(v) end
      assert(R.directoryExists(v),"Updater: no se puede crear "..v)
    end
  end
  local function write(p,s)
    dirs(p:match("^(.*)/[^/]+$"))
    assert(R.writeFileContents(p,s)~=false and R.fileExists(p) and read(p)==s,"Updater: escritura incompleta "..p)
  end
  local function put(p,v) write(p,J.encode(v,2)) end
  local function get(p) return J.decode(read(p)) end
  local function locked() return R.fileExists(base.."/_helper_dev/development.lock") end
  local function hashed(p) return R.fileExists(p) and Tx.sha256(read(p)) or false end
  T.locked=locked;T.write=write
  function T.plan(manifest)
    assert(type(manifest)=="table" and type(manifest.files)=="table" and #manifest.files>0 and #manifest.files<=2000,"Updater: manifest vacio o invalido.")
    assert(type(manifest.version)=="string" and #manifest.version<80 and manifest.version~="3.0.17","Updater: version invalida.")
    assert(not manifest.installProtocol or manifest.installProtocol==1,"Updater: protocolo incompatible.")
    local pending,seen,total={}, {},0
    for _,e in ipairs(manifest.files) do
      assert(type(e)=="table" and Tx.allowed(e.path),"Updater: archivo no permitido: "..tostring(e and e.path))
      local key=e.path:lower();assert(not seen[key],"Updater: ruta duplicada.");seen[key]=true
      assert(digest(e.sha256) and type(e.size)=="number" and e.size>=0 and e.size%1==0 and e.size<=100*1024*1024,"Updater: hash o tamano invalido: "..e.path)
      assert(type(e.url)=="string" and e.url:match("^https://"),"Updater: descarga insegura.")
      total=total+e.size;assert(total<=256*1024*1024,"Updater: paquete demasiado grande.")
      local old=hashed(base.."/"..e.path)
      if old~=e.sha256 then
        if old then
          local known=type(config.fileHashes)=="table" and config.fileHashes[e.path]==old
          for _,hash in ipairs(e.acceptedSha256 or {}) do assert(digest(hash),"Updater: hash de origen invalido.");known=known or old==hash end
          assert(known,"Archivo personalizado: "..e.path..". Se conserva; revisalo antes de actualizar.")
        end
        pending[#pending+1]=e
      end
    end
    return pending
  end
  function T.begin(manifest,files)
    assert(not locked(),"Updater: desarrollo protegido.")
    if R.fileExists(current) then
    local previous=get(current)
      assert(previous.status=="complete" or previous.status=="rolledBack" or previous.status=="aborted","Updater: hay una instalacion pendiente de recuperar.")
    end
    dirs(home)
    local n=1;while R.directoryExists(home.."/t"..n) do n=n+1 end
    local path=home.."/t"..n;dirs(path)
    local S={path=path,manifest=manifest,files=files,status="download",staged={}}
    function S.stage(e,data)
      assert(not locked(),"Updater: desarrollo protegido.")
      assert(type(data)=="string" and #data==e.size and Tx.sha256(data)==e.sha256,"Updater: descarga incompleta o hash incorrecto: "..e.path)
      if e.path:match("%.lua$") then
        assert(#data>0 and not data:find("One-time update: keep every published ".."Lua file",1,true),"Updater: codigo vacio o retirado.")
        assert(loadstring(data),"Updater: Lua invalido: "..e.path)
      end
      write(path.."/stage/"..e.path,data);S.staged[e.path]=true
    end
    function S.apply(barrierPrefix)
      assert(not locked(),"Updater: desarrollo protegido.")
      local still=T.plan(manifest);assert(#still==#files,"Updater: los archivos cambiaron durante la descarga; vuelve a intentar.")
      local entries,hasLoader={},false
      for _,e in ipairs(files) do
        assert(S.staged[e.path] and hashed(path.."/stage/"..e.path)==e.sha256,"Updater: falta una descarga verificada.")
        entries[#entries+1]={path=e.path,after=e.sha256,before=hashed(base.."/"..e.path)}
        hasLoader=hasLoader or e.path=="_Loader.lua"
      end
      local oldLoader=read(base.."/_Loader.lua")
      if not hasLoader then
        local hash=Tx.sha256(oldLoader);entries[#entries+1]={path="_Loader.lua",before=hash,after=hash}
        write(path.."/stage/_Loader.lua",oldLoader)
      end
      -- Snapshot all personal files and current code after download, before replacement.
      local inventory,total={},0
      local skip={_updates=true,_helper_dev=true,_archive=true,Sabuezo2=true}
      local function walk(dir,rel,depth)
        assert(depth<30,"Updater: demasiadas carpetas.")
        for _,name in ipairs(R.listDirectoryFiles(dir,false,false)) do
          if name:sub(1,#dir+1)==dir.."/" then name=name:sub(#dir+2) end
          assert(not name:find("/",1,true),"Updater: listado de carpeta invalido.")
          local sub=rel=="" and name or rel.."/"..name
          backupRelative(sub)
          if not (rel=="" and skip[name]) then
            local source=base.."/"..sub
            if R.fileExists(source) then
              local data=read(source);total=total+#data;assert(total<=512*1024*1024,"Updater: respaldo demasiado grande.")
              write(path.."/backup/"..sub,data)
              inventory[#inventory+1]={path=sub,sha256=Tx.sha256(data),size=#data}
            elseif R.directoryExists(source) then walk(source,sub,depth+1) end
          end
        end
      end
      walk(base,"",0)
      local backupMap={};for _,e in ipairs(inventory) do backupMap[e.path]=e.sha256 end
      for _,e in ipairs(entries) do assert(not e.before or backupMap[e.path]==e.before,"Updater: archivo cambio al respaldar: "..e.path) end
      put(path.."/backup-index.json",inventory)
      local barrier=assert(barrierPrefix)..oldLoader
      local journal={protocol=1,path=path,status="applying",version=manifest.version,previousVersion=config.version or "none",entries=entries,
        backupIndexSha256=hashed(path.."/backup-index.json"),barrierSha256=Tx.sha256(barrier),awaitBoot=manifest.awaitBoot==true}
      put(path.."/journal.json",journal);put(current..".previous",journal);put(current,journal)
      S.status="applying"
      local ok,message=pcall(function()
        -- The loader guard recovers a power loss before any mixed-version module loads.
        write(base.."/_Loader.lua",barrier)
        for _,e in ipairs(entries) do
          if e.path~="_Loader.lua" then
            assert(not locked(),"Updater: desarrollo protegido.")
            write(base.."/"..e.path,read(path.."/stage/"..e.path))
          end
        end
        write(base.."/_Loader.lua",read(path.."/stage/_Loader.lua"))
        journal.status=journal.awaitBoot and "pendingBoot" or "complete"
        put(current,journal)
      end)
      if not ok then
        local restored,reason=T.rollback()
        assert(restored,tostring(message).."; recuperacion pendiente: "..tostring(reason))
        assert(false,tostring(message))
      end
      config.fileHashes=config.fileHashes or {}
      for _,e in ipairs(manifest.files) do config.fileHashes[e.path]=e.sha256 end
      config.version=manifest.version;config.lastBackup=path;config.failedVersion=nil
      S.status=journal.status;return path
    end
    return S
  end
  local function journal()
    local ok,j=pcall(get,current)
    if not ok and R.fileExists(current..".previous") then j=get(current..".previous") end
    assert(type(j)=="table" and j.protocol==1 and type(j.path)=="string" and j.path:match("^"..home:gsub("(%W)","%%%1").."/t%d+$") and type(j.entries)=="table","Updater: registro de recuperacion invalido.")
    return j
  end
  function T.rollback()
    local ok,message=pcall(function()
      assert(not locked(),"Updater: desarrollo protegido.")
      local j=journal()
      assert(hashed(j.path.."/backup-index.json")==j.backupIndexSha256,"Updater: respaldo alterado.")
      -- Verify every required backup and destination before restoring anything.
      for _,e in ipairs(j.entries) do
        assert(Tx.allowed(e.path) and digest(e.after) and (e.before==false or digest(e.before)),"Updater: registro inseguro.")
        if e.before then assert(hashed(j.path.."/backup/"..e.path)==e.before,"Updater: respaldo incompleto.") end
        local h=hashed(base.."/"..e.path)
        assert(h==e.before or h==e.after or (e.path=="_Loader.lua" and h==j.barrierSha256) or j.status=="applying","Updater: cambio posterior detectado: "..e.path)
      end
      -- Restore loader last, so interrupted recovery is itself recoverable.
      for pass=1,2 do for _,e in ipairs(j.entries) do
        if (e.path=="_Loader.lua")== (pass==2) then
          if e.before then write(base.."/"..e.path,read(j.path.."/backup/"..e.path))
          elseif R.fileExists(base.."/"..e.path) then
            assert(R.deleteFile(base.."/"..e.path)~=false and not R.fileExists(base.."/"..e.path),"Updater: no se pudo retirar "..e.path)
          end
        end
      end end
      j.status="rolledBack";put(current,j)
      config.version=j.previousVersion;config.fileHashes={};config.autoInstall=false;config.lastBackup=j.path;config.failedVersion=j.version
    end)
    return ok,message
  end
  function T.boot()
    if not R.fileExists(current) then return false end
    local j=journal()
    if j.status=="applying" or j.status=="booting" then
      local ok,message=T.rollback();assert(ok,message);return "restored"
    end
    if j.status=="rolledBack" then
      config.version=j.previousVersion;config.autoInstall=false;config.fileHashes={};config.lastBackup=j.path;config.failedVersion=j.version
      return "rolledBack"
    end
    if j.status~="pendingBoot" then return false end
    for _,e in ipairs(j.entries) do assert(hashed(base.."/"..e.path)==e.after,"Updater: instalacion incompleta: "..e.path) end
    config.version=j.version;config.lastBackup=j.path
    config.fileHashes=type(config.fileHashes)=="table" and config.fileHashes or {}
    for _,e in ipairs(j.entries) do config.fileHashes[e.path]=e.after end
    j.status="booting";put(current,j);return "validate"
  end
  function T.confirm()
    if not R.fileExists(current) then return end
    local j=journal();assert(j.status=="booting","Updater: inicio no validado.")
    j.status="complete";put(current,j)
    local report={version=j.version,backup=j.path,completedAt=os.date("!%Y-%m-%dT%H:%M:%SZ"),status="complete"}
    local migration=base.."/_helper_profiles/migration-report.json"
    if R.fileExists(migration) then report.profiles=get(migration).profiles end
    put(base.."/_updates/last-result.json",report)
  end
  return T
end
return Tx

end)()
RinoBotUpdateStartup = true
storage.sabuezoUpdater = type(storage.sabuezoUpdater)=="table" and storage.sabuezoUpdater or {}
local RinoBotUpdateSession=RinoBotUpdateCore.new(g_resources,json,"/bot/" .. modules.game_bot.contentsPanel.config:getCurrentOption().text,storage.sabuezoUpdater)
local RinoBotUpdateBoot=RinoBotUpdateSession.boot()
if RinoBotUpdateBoot=="restored" then
  warn("RinoBot: instalacion anterior recuperada. Actualizacion automatica pausada.")
  schedule(50,function() reload() end)
  return
end
]====]
local updatePlanError
setDefaultTab("Main")

local panelName = "sabuezoUpdater"
if type(storage[panelName]) ~= "table" then storage[panelName] = {} end

local config = storage[panelName]
local rawManifestUrl = "https://raw.githubusercontent.com/Sabuezo12/sabuezo-bot-updates/main/rinobot/manifest.json"
local refsManifestUrl = "https://raw.githubusercontent.com/Sabuezo12/sabuezo-bot-updates/refs/heads/main/rinobot/manifest.json"
local githubRawManifestUrl = "https://github.com/Sabuezo12/sabuezo-bot-updates/raw/main/rinobot/manifest.json"
local jsDelivrManifestUrl = "https://cdn.jsdelivr.net/gh/Sabuezo12/sabuezo-bot-updates@main/rinobot/manifest.json"
local apiManifestUrl = "https://api.github.com/repos/Sabuezo12/sabuezo-bot-updates/contents/rinobot/manifest.json?ref=main"
local defaultManifestUrl = rawManifestUrl
-- Move the stock classic updater endpoint to the full RinoBot channel.
local classicManifestUrls = {["https://raw.githubusercontent.com/Sabuezo12/sabuezo-bot-updates/main/manifest.json"]=true,["https://raw.githubusercontent.com/Sabuezo12/sabuezo-bot-updates/refs/heads/main/manifest.json"]=true,["https://github.com/Sabuezo12/sabuezo-bot-updates/raw/main/manifest.json"]=true,["https://cdn.jsdelivr.net/gh/Sabuezo12/sabuezo-bot-updates@main/manifest.json"]=true,["https://api.github.com/repos/Sabuezo12/sabuezo-bot-updates/contents/manifest.json?ref=main"]=true}
if classicManifestUrls[config.manifestUrl or ""] then config.manifestUrl=defaultManifestUrl end
if not config.manifestUrl or config.manifestUrl == refsManifestUrl or config.manifestUrl == rawManifestUrl or
  config.manifestUrl == githubRawManifestUrl or config.manifestUrl == jsDelivrManifestUrl or
  config.manifestUrl == apiManifestUrl then
  config.manifestUrl = defaultManifestUrl
end
config.version = config.version or "none"
local installedVersion
if type(config.fileHashes) ~= "table" then config.fileHashes = {} end
-- Official updates are always automatic; recovery holds are per failed version.
config.autoInstall = true
-- Every completed update reloads the bot, including manual installs.
config.autoReload = true

-- The repository's 3.0.17 release intentionally empties the bot's Lua files.
-- Keep that retired release out of both automatic and manual installs.
local shutdownPayloadHash = "1447f280354d810b36b3b74d9b123a92238e01ef217b043e3e32ebad03db8a06"
local function isShutdownManifest(manifest)
  if type(manifest) ~= "table" then return false end
  if tostring(manifest.version or "") == "3.0.17" then return true end
  for _, entry in ipairs(manifest.files or {}) do
    if type(entry) == "table" then
      local url = tostring(entry.url or ""):lower()
      local hash = tostring(entry.sha256 or ""):lower()
      if url:find("cleanup_payload", 1, true) or hash == shutdownPayloadHash then
        return true
      end
    end
  end
  return false
end

local function isShutdownPayload(contents)
  if type(contents) ~= "string" then return false end
  local shutdownHeader = "One-time update: keep every published ".."Lua file, " .. "with no code inside."
  local emptyLoader = "empty(" .. '"_Loader.lua"' .. ")"
  return contents:find(shutdownHeader, 1, true) ~= nil or
    (contents:find(emptyLoader, 1, true) ~= nil and
      contents:find("Lua vacios:", 1, true) ~= nil)
end

local ui = setupUI([[UpdaterPanel
]], parent)
ui:setId(panelName)

local installing = false
local checking = false
local lastManifest = nil
local lastPendingFiles = {}
local lastVerifiedHashes = {}
local decodedManifestCache, verifiedPublication
local notesManifest, notesVersion
local newsDirty, historyDirty = true, true
local updateRoot=g_ui.getRootWidget()
local updateGeneration={}
updateRoot._rinoUpdaterGeneration=updateGeneration
local function currentExecutor() return updateRoot._rinoUpdaterGeneration==updateGeneration end
local detailsWindow = nil
local ensureDetailsWindow
local autoReloadScheduled = false
local activeTab = "News"
local state = {kind = "idle", title = "Buscar actualizaciones", detail = "",
  color = "#dce6ef", done = 0, total = 0, phase = ""}
local renderState

local function trim(text)
  return tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function wrapTextLine(text, maxLen)
  text = tostring(text or "")
  maxLen = tonumber(maxLen) or 64
  if text:len() <= maxLen then return { text } end

  local lead = text:match("^%s*") or ""
  local isBullet = text:match("^%s*[-+]") ~= nil
  local prefix = isBullet and (lead .. "- ") or lead
  local continuation = isBullet and (lead .. "  ") or lead
  local content = trim(text)
  if isBullet then content = content:gsub("^[-+]%s*", "") end

  local lines = {}
  local current = ""
  local currentPrefix = prefix

  for word in content:gmatch("%S+") do
    local limit = math.max(12, maxLen - currentPrefix:len())
    if current == "" then
      current = word
    elseif current:len() + word:len() + 1 <= limit then
      current = current .. " " .. word
    else
      table.insert(lines, currentPrefix .. current)
      currentPrefix = continuation
      current = word
    end
  end

  if current ~= "" then table.insert(lines, currentPrefix .. current) end
  return lines
end

local function setPanelStatus(text, color)
  if ui.status then
    ui.status:setText(text)
    ui.status:setColor(color or "#dce6ef")
  end
  if ui.open.setTooltip then ui.open:setTooltip(text) end
end

local function setState(kind, title, detail, color)
  state.kind = kind
  state.title = title
  state.detail = detail or ""
  state.color = color or "#dce6ef"
  setPanelStatus("Version: " .. installedVersion() .. "\n" .. title, state.color)
  if renderState then renderState() end
end

local function reloadAfterInstall()
  if autoReloadScheduled then return end
  autoReloadScheduled = true
  state.phase = "reload"
  setState("reloading", "Recargando bot...", "El bot se recargara al terminar.", "#8cff9a")

  schedule(800, function()
    local ok, err = false, nil
    if type(reload) == "function" then ok, err = pcall(reload) end
    if not ok then
      autoReloadScheduled = false
      setState("warning", "Reloguea para aplicar", "Actualizacion instalada. Reloguea para aplicar." ..
        (err and ("\n" .. tostring(err)) or ""), "#ffd166")
    end
  end)
end

local function parseVersion(version)
  version = tostring(version or "")
  local parts = {}
  for part in version:gmatch("%d+") do
    table.insert(parts, tonumber(part) or 0)
  end
  if #parts == 0 then return nil end
  return parts
end

local function compareVersions(left, right)
  local a = parseVersion(left)
  local b = parseVersion(right)
  if not a and not b then return 0 end
  if not a then return -1 end
  if not b then return 1 end

  local maxParts = math.max(#a, #b)
  for i = 1, maxParts do
    local av = a[i] or 0
    local bv = b[i] or 0
    if av > bv then return 1 end
    if av < bv then return -1 end
  end
  return 0
end

-- The full loader identifies its code even after a manual installation. A
-- classic bridge has no marker and continues to display its recorded version.
-- Do not rewrite transaction versions/hashes or turn this into a verification.
installedVersion = function()
  local source = RinoBotSourceVersion
  if type(source) == "string" and source:match("^%d+%.%d+%.%d+$") and
    not config.failedVersion and compareVersions(source, config.version) > 0 then
    return source
  end
  return tostring(config.version or "none")
end

local function isNewerVersion(version, baseVersion)
  return compareVersions(version, baseVersion) > 0
end

local httpDownloadSerial = 0
local httpRequestSerial = 0

local function withCacheBuster(url)
  url = tostring(url or "")
  httpRequestSerial = httpRequestSerial + 1

  local stamp = "0"
  if os and os.time then
    stamp = tostring(os.time())
  end
  stamp = stamp .. "-" .. tostring(now or 0) .. "-" .. tostring(httpRequestSerial)

  local separator = url:find("?", 1, true) and "&" or "?"
  return url .. separator .. "sabuezoCache=" .. stamp
end

local function decodeBase64(data)
  data = tostring(data or ""):gsub("%s", "")
  if data:len() == 0 then return nil end

  local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  data = data:gsub("[^" .. alphabet .. "=]", "")

  local bits = data:gsub(".", function(char)
    if char == "=" then return "" end
    local index = alphabet:find(char, 1, true)
    if not index then return "" end

    local value = index - 1
    local result = ""
    for i = 6, 1, -1 do
      result = result .. ((value % (2 ^ i) - value % (2 ^ (i - 1)) > 0) and "1" or "0")
    end
    return result
  end)

  return bits:gsub("%d%d%d?%d?%d?%d?%d?%d?", function(byte)
    if byte:len() ~= 8 then return "" end

    local value = 0
    for i = 1, 8 do
      if byte:sub(i, i) == "1" then
        value = value + 2 ^ (8 - i)
      end
    end
    return string.char(value)
  end)
end

local function decodeGithubContentResponse(data)
  if type(data) ~= "string" or not data:find('"content"', 1, true) then return data end

  local ok, payload = pcall(function()
    return json.decode(data)
  end)
  if not ok or type(payload) ~= "table" or type(payload.content) ~= "string" then return data end

  local decoded = decodeBase64(payload.content)
  if type(decoded) == "string" and decoded:len() > 0 then return decoded end
  return data
end

local function normalizeJsonPayload(data)
  data = tostring(data or "")
  data = data:gsub("^\239\187\191", "")
  data = data:gsub("^%s+", ""):gsub("%s+$", "")

  if data:sub(1, 1) == "{" or data:sub(1, 1) == "[" then
    return data
  end

  local firstObject = data:find("{", 1, true)
  local lastObject = data:match("^.*()}")
  if firstObject and lastObject and lastObject >= firstObject then
    return data:sub(firstObject, lastObject)
  end

  local firstArray = data:find("[", 1, true)
  local lastArray = data:match("^.*()%]")
  if firstArray and lastArray and lastArray >= firstArray then
    return data:sub(firstArray, lastArray)
  end

  return data
end

local function httpGet(url, callback, allowPlainText)
  local http = modules and modules.corelib and modules.corelib.HTTP or HTTP
  local function resolveRawHttp()
    local function usable(candidate)
      return type(candidate) == "table" and (candidate.get or candidate.download)
    end

    if usable(g_http) then return g_http end
    if rawget and type(_G) == "table" and usable(rawget(_G, "g_http")) then
      return rawget(_G, "g_http")
    end
    if modules and modules.corelib then
      if usable(modules.corelib.g_http) then return modules.corelib.g_http end
      if type(modules.corelib.HTTP) == "table" and usable(modules.corelib.HTTP.g_http) then
        return modules.corelib.HTTP.g_http
      end
    end

    local envSources = {}
    if http then
      table.insert(envSources, http.get)
      table.insert(envSources, http.download)
      table.insert(envSources, http.post)
    end

    local envGetters = {}
    if getfenv then table.insert(envGetters, getfenv) end
    if debug and debug.getfenv then table.insert(envGetters, debug.getfenv) end

    for _, source in ipairs(envSources) do
      if type(source) == "function" then
        for _, getter in ipairs(envGetters) do
          local ok, env = pcall(getter, source)
          if ok and type(env) == "table" and usable(env.g_http) then
            return env.g_http
          end
        end
      end
    end

    return nil
  end

  local rawHttp = resolveRawHttp()

  if (not http or (not http.get and not http.download)) and
    (not rawHttp or (not rawHttp.get and not rawHttp.download)) then
    callback(nil, "HTTP unavailable")
    return
  end

  local function shortError(err)
    err = tostring(err or "HTTP request failed")
    err = err:gsub("\r", " "):gsub("\n", " "):gsub("%s+", " ")
    err = err:gsub("^.-ERROR:%s*", "")
    if err:len() > 180 then err = err:sub(1, 180) .. "..." end
    return err
  end

  local function looksLikeData(value)
    return type(value) == "string" and (allowPlainText or value:match("^%s*[%{%[]"))
  end

  local function responseIsSuccess(value)
    if type(value) ~= "table" then return false end

    local err = value.error or value.err
    if err ~= nil and tostring(err):len() > 0 then return false end

    local status = tonumber(value.status or value.statusCode or value.code)
    return status == nil or (status >= 200 and status < 300)
  end

  local function tablePayload(value)
    if type(value) ~= "table" then return nil end
    local keys = {"body", "data", "content", "response", "result", "text"}
    for _, key in ipairs(keys) do
      if type(value[key]) == "string" and value[key]:len() > 0 and
        (responseIsSuccess(value) or looksLikeData(value[key])) then
        return value[key]
      end
    end
    for _, item in pairs(value) do
      if type(item) == "string" and item:len() > 0 and
        (responseIsSuccess(value) or looksLikeData(item)) then
        return item
      end
    end
    return nil
  end

  local function describeValue(value)
    if type(value) ~= "table" then return shortError(value) end

    local parts = {}
    local count = 0
    for key, item in pairs(value) do
      count = count + 1
      if count > 8 then
        table.insert(parts, "...")
        break
      end

      local itemText = tostring(item)
      itemText = itemText:gsub("\r", " "):gsub("\n", " "):gsub("%s+", " ")
      if itemText:len() > 60 then itemText = itemText:sub(1, 60) .. "..." end
      table.insert(parts, tostring(key) .. "=" .. itemText)
    end

    if #parts == 0 then return "empty table" end
    return "table {" .. table.concat(parts, ", ") .. "}"
  end

  local function makeHeaders()
    return {
      Accept = "*/*",
      ["User-Agent"] = "Mozilla/5.0",
      ["Cache-Control"] = "no-cache",
      Pragma = "no-cache"
    }
  end

  local function readDownloadedFile(path, fallback)
    local candidates = {}
    local function add(candidate)
      if type(candidate) ~= "string" or candidate:len() == 0 then return end
      table.insert(candidates, candidate)
      if candidate:sub(1, 1) ~= "/" then
        table.insert(candidates, "/downloads/" .. candidate)
      end
    end

    add(path)
    add(fallback)

    for _, candidate in ipairs(candidates) do
      local ok, contents = pcall(function()
        return g_resources.readFileContents(candidate)
      end)
      if ok and type(contents) == "string" and contents:len() > 0 then
        return contents
      end
    end

    return nil
  end

  local function onResponse(first, second)
    local firstPayload = tablePayload(first)
    if firstPayload then
      callback(firstPayload)
      return
    end
    local secondPayload = tablePayload(second)
    if secondPayload then
      callback(secondPayload)
      return
    end

    if type(first) == "string" and first:len() > 0 and
      (second == nil or tostring(second):len() == 0) then
      callback(first)
      return
    end
    if type(second) == "string" and second:len() > 0 and
      (first == nil or tostring(first):len() == 0) then
      callback(second)
      return
    end
    if looksLikeData(first) then
      callback(first)
      return
    end
    if looksLikeData(second) then
      callback(second)
      return
    end

    local err = second or first
    if err and describeValue(err):len() > 0 then
      callback(nil, describeValue(err))
      return
    end

    callback(nil, "empty response")
  end

  local lastError
  local function hasStdMapError()
    return type(lastError) == "string" and lastError:find("std::map", 1, true) ~= nil
  end

  if http and http.get then
    local attempts = {
      {"HTTP.get callback", function() return http.get(url, onResponse) end},
      {"HTTP.get callback headers", function() return http.get(url, onResponse, makeHeaders()) end},
      {"HTTP.get headers callback", function() return http.get(url, makeHeaders(), onResponse) end}
    }

    for _, attempt in ipairs(attempts) do
      local ok, result = pcall(attempt[2])
      if ok and result ~= nil then return result end
      if ok then
        lastError = attempt[1] .. " returned nil"
      else
        lastError = attempt[1] .. ": " .. shortError(result)
      end
    end
  end

  if rawHttp and rawHttp.get then
    local headers = makeHeaders()
    local timeout = tonumber(http and (http.timeout or http.TIMEOUT)) or 60
    local rawAttempts = {
      {name = "g_http.get timeout headers", call = function() return rawHttp.get(url, timeout, headers) end},
      {name = "g_http.get headers timeout", call = function() return rawHttp.get(url, headers, timeout) end},
      {name = "g_http.get old timeout", old = true, call = function() return rawHttp.get(url, timeout) end}
    }

    http.operations = http.operations or {}
    for _, attempt in ipairs(rawAttempts) do
      if not attempt.old or not hasStdMapError() then
        local ok, operation = pcall(attempt.call)
        if ok and operation ~= nil then
          http.operations[operation] = {type = "get", url = url, callback = onResponse}
          return operation
        end
        if ok then
          lastError = attempt.name .. " returned nil"
        else
          lastError = attempt.name .. ": " .. shortError(operation)
        end
      end
    end
  end

  if g_resources and g_resources.readFileContents then
    httpDownloadSerial = httpDownloadSerial + 1
    local downloadFile = "sabuezo_updater_" .. tostring(httpDownloadSerial) .. ".tmp"
    local function onDownload(path, checksum, err)
      if err and tostring(err):len() > 0 then
        callback(nil, shortError(err))
        return
      end

      local contents = readDownloadedFile(path, downloadFile)
      if looksLikeData(contents) then
        callback(contents)
      else
        callback(nil, "download finished but file could not be read")
      end
    end

    if rawHttp and rawHttp.download then
      local headers = makeHeaders()
      local timeout = tonumber(http and (http.timeout or http.TIMEOUT)) or 60
      local rawDownloads = {
        {name = "g_http.download timeout headers", call = function() return rawHttp.download(url, downloadFile, timeout, headers) end},
        {name = "g_http.download headers timeout", call = function() return rawHttp.download(url, downloadFile, headers, timeout) end},
        {name = "g_http.download old timeout", old = true, call = function() return rawHttp.download(url, downloadFile, timeout) end}
      }

      http.operations = http.operations or {}
      for _, attempt in ipairs(rawDownloads) do
        if not attempt.old or not hasStdMapError() then
          local ok, operation = pcall(attempt.call)
          if ok and operation ~= nil then
            http.operations[operation] = {type = "download", url = url, file = downloadFile, callback = onDownload}
            return operation
          end
          if ok then
            lastError = attempt.name .. " returned nil"
          else
            lastError = attempt.name .. ": " .. shortError(operation)
          end
        end
      end
    end

    if not rawHttp or not rawHttp.download then
      lastError = tostring(lastError or "No direct g_http access") .. " | HTTP.download wrapper skipped"
    end
  end

  callback(nil, tostring(lastError or "HTTP request failed"))
end

local function getConfigName()
  local ok, name = pcall(function()
    return modules.game_bot.contentsPanel.config:getCurrentOption().text
  end)
  if ok and type(name) == "string" and name:len() > 0 then
    return name
  end
  return "Sabuezo"
end

local function developmentLocked()
  return g_resources.fileExists("/bot/" .. getConfigName() .. "/_helper_dev/development.lock")
end

local function lockedNotice()
  setState("protected", "Helper protegido", "Desarrollo local: instalacion bloqueada. Consulta novedades e historial.", "#ffd166")
end

local function safeName(text)
  text = tostring(text or "unknown")
  text = text:gsub("[^%w%._%-]", "_")
  if text:len() == 0 then return "unknown" end
  return text
end

local function normalizePath(path)
  path = tostring(path or ""):gsub("\\", "/")
  path = path:gsub("^/+", ""):gsub("/+$", "")
  return path
end

local function isAllowedPath(path) return UpdateTx.allowed(path) end
local transaction = UpdateTx.new(g_resources,json,"/bot/" .. getConfigName(),config)
if not RinoBotUpdateStartup then
  local recovered=transaction.boot()
  if recovered=="restored" then warn("RinoBot: actualizacion interrumpida recuperada.") end
end

local function makeTargetPath(path)
  return "/bot/" .. getConfigName() .. "/" .. normalizePath(path)
end

local function localFileExists(path)
  if not isAllowedPath(path) then return false end
  return g_resources.fileExists(makeTargetPath(path))
end

local function ensureDir(path)
  if not g_resources.directoryExists(path) then
    g_resources.makeDir(path)
  end
end

local function ensureParent(path)
  local current = ""
  local directory = path:match("^(.*)/[^/]+$") or ""
  for part in directory:gmatch("[^/]+") do
    current = current .. "/" .. part
    ensureDir(current)
  end
end

local function backupExisting(configName, filePath, version)
  local targetPath = "/bot/" .. configName .. "/" .. filePath
  if not g_resources.fileExists(targetPath) then return end

  local backupRoot = "/bot/" .. configName .. "/_updates"
  local backupDir = backupRoot .. "/backup_" .. safeName(version)
  ensureDir(backupRoot)
  ensureDir(backupDir)

  local ok, contents = pcall(function()
    return g_resources.readFileContents(targetPath)
  end)
  if not ok or not contents then return end

  local backupFile = backupDir .. "/" .. filePath:gsub("[/\\]", "__")
  pcall(function()
    g_resources.writeFileContents(backupFile, contents)
  end)
end

local function getHistoryEntries(manifest, fromVersion)
  local entries = {}
  if type(manifest) ~= "table" or type(manifest.history) ~= "table" then return entries end

  for _, entry in ipairs(manifest.history) do
    if type(entry) == "table" and isNewerVersion(entry.version, fromVersion) then
      table.insert(entries, entry)
    end
  end

  table.sort(entries, function(a, b)
    return compareVersions(a.version, b.version) < 0
  end)
  return entries
end

local function getHistoryPathSet(manifest, fromVersion)
  local set = {}
  local count = 0
  for _, historyEntry in ipairs(getHistoryEntries(manifest, fromVersion)) do
    if type(historyEntry.files) == "table" then
      for _, path in ipairs(historyEntry.files) do
        local normalized = normalizePath(path)
        if isAllowedPath(normalized) and not set[normalized] then
          set[normalized] = true
          count = count + 1
        end
      end
    end
  end
  return set, count
end

local function scanManifest(manifest,callback)
  verifiedPublication=nil
  checking=true
  updatePlanError=nil
  transaction.planAsync(manifest,schedule,function(ok,files,hashes)
    if not currentExecutor() then return end
    checking=false
    updatePlanError=not ok and tostring(files) or nil
    lastPendingFiles=ok and files or {}
    lastVerifiedHashes=ok and hashes or {}
    callback(manifest)
  end,currentExecutor)
end
local function rememberExistingHashes(manifest)
  if type(manifest)~="table" then return end
  for _,entry in ipairs(manifest.files or {}) do
    if lastVerifiedHashes[entry.path]==entry.sha256 then
      config.fileHashes[entry.path]=entry.sha256
    end
  end
end

local function addListLine(parent, text, color)
  if not parent then return end
  local ok, widget = pcall(function() return UI.createWidget("UpdaterListLabel", parent) end)
  if not ok or not widget then return end
  widget:setText(tostring(text or ""))
  widget:setColor(color or "#dce6ef")
  return widget
end

local listRows = {}
local function fillList(parent, lines, emptyText)
  if not parent then return end
  local wrapped = {}
  if #lines == 0 then
    wrapped[1] = {text = emptyText or "Sin datos", color = "#a8bac7"}
  else for _, line in ipairs(lines) do
    local text = type(line) == "table" and line.text or line
    local color = type(line) == "table" and line.color or nil
    for _, textLine in ipairs(wrapTextLine(text, 65)) do
      table.insert(wrapped, {text = textLine, color = color or "#dce6ef"})
    end
  end end
  -- Reuse labels so file progress does not rebuild the whole UI or reset scrolling.
  local rows = listRows[parent] or {}
  listRows[parent] = rows
  for index, line in ipairs(wrapped) do
    local row = rows[index]
    if not row then
      local widget = addListLine(parent, line.text, line.color)
      if widget then rows[index] = {widget = widget, text = line.text, color = line.color} end
    else
      if row.text ~= line.text then row.widget:setText(line.text); row.text = line.text end
      if row.color ~= line.color then row.widget:setColor(line.color); row.color = line.color end
    end
  end
  for index = #rows, #wrapped + 1, -1 do
    rows[index].widget:destroy()
    rows[index] = nil
  end
end

local function allHistory(manifest)
  local entries = {}
  for _, entry in ipairs(manifest and manifest.history or {}) do
    if type(entry) == "table" then table.insert(entries, entry) end
  end
  table.sort(entries, function(a, b) return compareVersions(a.version, b.version) > 0 end)
  return entries
end

local function appendNotes(lines, entry, showInstalled)
  local version = tostring(entry.version or "?")
  local title = trim(entry.title)
  local heading = version .. (title ~= "" and (" - " .. title) or "")
  if showInstalled and version == installedVersion() then heading = heading .. " (instalada)" end
  table.insert(lines, {text = heading, color = "#7cc9d1"})
  if entry.date or entry.updatedAt then
    table.insert(lines, {text = tostring(entry.date or entry.updatedAt), color = "#a8bac7"})
  end
  if type(entry.changes) == "table" then
    for _, change in ipairs(entry.changes) do
      change = trim(change)
      if change ~= "" then table.insert(lines, "- " .. change) end
    end
  elseif type(entry.summary) == "string" then
    for line in entry.summary:gmatch("[^\n]+") do table.insert(lines, "- " .. trim(line)) end
  end
  table.insert(lines, "")
end

local function buildChangeLines(manifest)
  local lines = {}
  local entries = getHistoryEntries(manifest, installedVersion())
  -- Keep the latest release notes visible after a successful installation.
  if #entries == 0 then
    for _, entry in ipairs(allHistory(manifest)) do
      if tostring(entry.version) == tostring(manifest.version) then entries = {entry}; break end
    end
  end
  for index = #entries, 1, -1 do appendNotes(lines, entries[index], false) end
  if #lines == 0 then
    local summary = manifest.summary
    if type(summary) == "table" then
      for _, line in ipairs(summary) do table.insert(lines, "- " .. trim(line)) end
    elseif type(summary) == "string" then
      for line in summary:gmatch("[^\n]+") do table.insert(lines, "- " .. trim(line)) end
    end
  end
  return lines
end

local function buildHistoryLines(manifest)
  local lines = {}
  for _, entry in ipairs(allHistory(manifest)) do appendNotes(lines, entry, true) end
  return lines
end

local function buildDetailLines()
  local lines = {
    {text = "Perfil: " .. getConfigName(), color = "#7cc9d1"},
    "Instalada: " .. installedVersion(),
    "Disponible: " .. tostring(lastManifest and lastManifest.version or "-"),
    "Recarga automatica: activada", ""
  }
  if lastManifest and lastManifest.updatedAt then
    table.insert(lines, "Publicacion: " .. tostring(lastManifest.updatedAt))
  end
  if state.detail ~= "" then
    for line in state.detail:gmatch("[^\n]+") do
      table.insert(lines, {text = line, color = state.color})
    end
    table.insert(lines, "")
  end
  table.insert(lines, {text = "Archivos pendientes: " .. #lastPendingFiles, color = "#7cc9d1"})
  for _, entry in ipairs(lastPendingFiles) do table.insert(lines, "- " .. normalizePath(entry.path)) end
  if #lastPendingFiles == 0 then table.insert(lines, "No hay archivos pendientes.") end
  return lines
end

local function isBusy()
  return checking or installing or autoReloadScheduled
end

local function updateProgressWidth()
  if not detailsWindow then return end
  local frame = detailsWindow.Body.Progress.Frame
  local size = frame:getSize()
  local available = math.max(1, (tonumber(size.width) or 0) - 6)
  local fraction = state.total > 0 and state.done / state.total or 0
  frame.Fill:setWidth(math.max(1, math.floor(available * math.min(1, fraction))))
  frame.Fill:setVisible(fraction > 0)
end

renderState = function()
  local dot = state.kind == "error" and "red" or
    (state.kind == "current" or state.kind == "reloading") and "green" or
    (state.kind == "available" or state.kind == "checking" or state.kind == "installing" or
     state.kind == "warning" or state.kind == "blocked") and "yellow" or "gray"
  if ui.open.Dot then ui.open.Dot:setImageSource("/bot/" .. getConfigName() ..
    "/vBot/botserver_assets/status-" .. dot .. ".png") end
  if ui.open.Badge then ui.open.Badge:setText(installedVersion()) end
  if not detailsWindow or not detailsWindow:isVisible() then return end
  local w = detailsWindow
  local busy = isBusy()
  local locked = developmentLocked()
  w.Banner.Status:setText(state.title)
  w.Banner.Status:setColor(state.color)
  w.Banner.Dot:setImageSource("/bot/" .. getConfigName() .. "/vBot/botserver_assets/status-" .. dot .. ".png")
  w.Banner:setTooltip(state.detail ~= "" and state.detail or state.title)
  w.Versions.Local.Value:setText(installedVersion())
  w.Versions.Remote.Value:setText(tostring(lastManifest and lastManifest.version or "-"))
  for _, name in ipairs({"News", "History", "Details"}) do
    w.Tabs[name]:setOn(name == activeTab)
    w.Body[name]:setVisible(name == activeTab)
  end
  w.Options.Auto:setOn(true)
  w.Options.Auto.Caption:setText("ON")
  w.Options.Auto.Caption:setMarginLeft(0)
  w.Options.Auto:setEnabled(false)
  w.Options.Auto:setTooltip(locked and "Desarrollo protegido: instalacion bloqueada." or "Siempre automatico. Comprueba cada 5 minutos; al actualizar abre Helper.")
  w.check:setEnabled(not busy)
  local available = lastManifest and (#lastPendingFiles > 0 or tostring(lastManifest.version) ~= tostring(config.version))
  w.install:setEnabled(not busy and not locked and available ~= nil and available ~= false)
  local installText = state.kind == "reloading" and "Recargando..." or
    installing and "Actualizando..." or available and
    ("Actualizar a " .. tostring(lastManifest.version)) or lastManifest and "Todo actualizado" or "Actualizar"
  w.install.Caption:setText(locked and "Helper protegido" or installText)
  w.install:setTooltip(locked and "Desarrollo local: no se permite reemplazar los archivos del Helper." or "Descargar solo los archivos pendientes y recargar el bot")
  local pendingCount = installing and math.max(0, state.total - state.done) or #lastPendingFiles
  w.Body.News.Footer:setText(pendingCount == 0 and "Sin archivos pendientes" or
    (pendingCount .. (pendingCount == 1 and " archivo pendiente" or " archivos pendientes")))
  local progressVisible = state.total > 0
  w.Body.Progress:setVisible(progressVisible)
  for _, name in ipairs({"News", "History", "Details"}) do
    w.Body[name]:setMarginBottom(progressVisible and 64 or 0)
  end
  w.Body.Progress.Count:setText(state.done .. " de " .. state.total .. " archivos listos")
  w.Body.Progress.Percent:setText((state.total > 0 and math.floor(100 * state.done / state.total) or 0) .. "%")
  local phase = state.phase == "reload" and "Descargar  >  Instalar  >  [Recargar]" or
    state.phase == "install" and "Descargar  >  [Instalar]  >  Recargar" or
    "[Descargar]  >  Instalar  >  Recargar"
  if state.kind == "error" or state.kind == "blocked" then phase = "Interrumpido - revisa Detalles" end
  if state.kind == "warning" then phase = "Instalado - recarga pendiente" end
  w.Body.Progress.Phase:setText(phase)
  updateProgressWidth()
  if activeTab=="Details" then
    fillList(w.Body.Details.List, buildDetailLines())
  elseif activeTab=="News" and newsDirty then
    fillList(w.Body.News.List,buildChangeLines(notesManifest or {}),"Revisa si hay una nueva version.")
    newsDirty=false
  elseif activeTab=="History" and historyDirty then
    fillList(w.Body.History.List,buildHistoryLines(notesManifest or {}),"El historial se cargara al buscar actualizaciones.")
    historyDirty=false
  end
end

local function refreshDetailsWindow(manifest)
  local version=installedVersion()
  if notesManifest~=manifest or notesVersion~=version then
    notesManifest,notesVersion=manifest,version
    newsDirty,historyDirty=true,true
  end
  renderState()
end

local function blockShutdownUpdate()
  checking = false
  installing = false
  lastManifest = nil
  lastPendingFiles = {}
  lastVerifiedHashes = {}
  updatePlanError=nil
  refreshDetailsWindow(nil)
  setState("blocked", "Actualizacion de cierre bloqueada",
    "Esta version vacia los scripts y se ha bloqueado para conservar el bot.", "#ffd166")
end

local function buildManifestUrls()
  local urls = {}
  local seen = {}

  local function add(url)
    url = tostring(url or "")
    if url:len() == 0 or seen[url] then return end
    seen[url] = true
    table.insert(urls, url)
  end

  add(config.manifestUrl)
  add(defaultManifestUrl)
  add(apiManifestUrl)
  add(refsManifestUrl)
  add(githubRawManifestUrl)
  add(jsDelivrManifestUrl)
  add(rawManifestUrl)

  return urls
end

local function previewText(text)
  text = tostring(text or "")
  text = text:gsub("\r", " "):gsub("\n", " "):gsub("%s+", " ")
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  if text:len() > 90 then text = text:sub(1, 90) .. "..." end
  if text:len() == 0 then return "empty" end
  return text
end

local function fetchManifest(callback,lightCheck)
  if isBusy() then return end
  checking = true
  state.done, state.total, state.phase = 0, 0, ""
  local finished = false
  local attempts = buildManifestUrls()
  local attemptIndex, activeAttempt = 0, 0
  local lastError = nil
  setState("checking", "Buscando actualizaciones...", "Consultando las versiones publicadas.", "#ffd166")

  local function fail()
    if finished or not currentExecutor() then return end
    finished, checking = true, false
    setState("error", "No se pudo buscar la actualizacion", tostring(lastError or "Sin respuesta") ..
      "\nPuedes volver a intentarlo.", "#ff8a8a")
    if callback then callback(nil) end
  end

  local function tryNextManifest()
    if finished or not currentExecutor() then return end
    attemptIndex = attemptIndex + 1
    local url = attempts[attemptIndex]
    if not url then fail(); return end
    activeAttempt = activeAttempt + 1
    local token = activeAttempt
    if type(schedule) == "function" then
      schedule(6000, function()
        if finished or not currentExecutor() or token ~= activeAttempt then return end
        lastError = "Tiempo de espera agotado en ruta " .. attemptIndex
        tryNextManifest()
      end)
    end
    httpGet(withCacheBuster(url), function(data, err)
      if finished or not currentExecutor() or token ~= activeAttempt then return end
      if not data then
        lastError = "Ruta " .. attemptIndex .. ": " .. tostring(err or "sin respuesta")
        tryNextManifest(); return
      end
      -- Cache only in this executor, keyed by the exact response bytes.
      -- Manual checks always audit the disk, even when parsing can be reused.
      local cached=decodedManifestCache and decodedManifestCache.data==data and decodedManifestCache
      local payload=data
      local ok,manifest
      if cached then ok,manifest=true,cached.manifest
      else
        payload=normalizeJsonPayload(decodeGithubContentResponse(data))
        ok,manifest=pcall(function() return json.decode(payload) end)
      end
      if not ok or type(manifest) ~= "table" or type(manifest.files) ~= "table" then
        lastError = "Ruta " .. attemptIndex .. ": manifest invalido: " .. previewText(payload)
        tryNextManifest(); return
      end
      if isShutdownManifest(manifest) then
        finished = true
        blockShutdownUpdate()
        if callback then callback(nil) end
        return
      end
      finished=true
      config.manifestUrl = url
      lastManifest = manifest
      decodedManifestCache={data=data,manifest=manifest}
      if lightCheck and verifiedPublication and verifiedPublication.data==data and
        verifiedPublication.version==tostring(config.version) and not config.failedVersion then
        checking=false
        setState("current","Sin nuevas versiones","La publicacion sigue igual; se conserva la verificacion de esta sesion.","#8cff9a")
        if callback then callback(manifest,true) end
        return
      end
      setState("checking","Verificando archivos...","Comprobacion en segundo plano; el juego sigue disponible.","#ffd166")
      scanManifest(manifest,function(verified)
        if not updatePlanError and #lastPendingFiles==0 and
          tostring(verified.version)==tostring(config.version) and not config.failedVersion then
          verifiedPublication={data=data,version=tostring(config.version)}
        else verifiedPublication=nil end
        refreshDetailsWindow(verified)
        if callback then callback(verified) end
      end)
    end)
  end
  tryNextManifest()
end

local function installManifest(manifest)
  if developmentLocked() then lockedNotice(); return end
  if isBusy() then return end
  if isShutdownManifest(manifest) then blockShutdownUpdate(); return end
  if compareVersions(manifest.version,installedVersion())<0 then
    setState("current","Version mas reciente instalada","Se conserva la version actual; no se instala una version anterior.","#8cff9a");return
  end
  refreshDetailsWindow(manifest)
  if updatePlanError then setState("error","Actualizacion detenida",updatePlanError,"#ff8a8a");return end
  if #lastPendingFiles==0 then
    local changed=tostring(config.version)~=tostring(manifest.version)
    config.version=manifest.version;rememberExistingHashes(manifest)
    if changed then
      storage.helperUI=type(storage.helperUI)=="table" and storage.helperUI or {}
      storage.helperUI.legacy=false;config.failedVersion=nil
      if type(saveConfig)=="function" then saveConfig() end
      reloadAfterInstall()
    else setState("current","Todo actualizado","Todos los archivos estan verificados.","#8cff9a") end
    return
  end
  -- Every successful install is checked by the loader before selecting its UI.
  manifest.awaitBoot=true
  local ok,session=pcall(function() return transaction.begin(manifest,lastPendingFiles) end)
  if not ok then setState("error","No se pudo preparar",tostring(session),"#ff8a8a");return end
  installing=true
  local files=lastPendingFiles
  state.done,state.total=0,#files
  local function failed(message)
    installing=false
    setState("error","Actualizacion detenida",tostring(message),"#ff8a8a")
  end
  local function download(index)
    if developmentLocked() then failed("Desarrollo protegido.");return end
    if index>#files then
      state.phase="install"
      setState("installing","Respaldando e instalando...","Descarga completa y verificada.","#ffd166")
      local applied,backup=pcall(function()
        -- Flush the native cache before taking the verified personal-data backup.
        if type(saveConfig)=="function" then saveConfig() end
        return session.apply(recoveryLoaderPrefix)
      end)
      if not applied then failed(backup);return end
      local saved,message=pcall(function()
        if type(saveConfig)=="function" then saveConfig() end
      end)
      if not saved then
        local restored,reason=transaction.rollback()
        failed(tostring(message)..(restored and "\nCodigo anterior recuperado." or "\n"..tostring(reason)));return
      end
      installing=false;state.done=#files
      lastPendingFiles={};lastVerifiedHashes={};updatePlanError=nil
      refreshDetailsWindow(manifest)
      setState("current","Actualizacion instalada","Version "..manifest.version.."\nRespaldo verificado: "..backup,"#8cff9a")
      reloadAfterInstall();return
    end
    local entry=files[index]
    state.phase="download"
    setState("installing","Descargando y verificando...",index.."/"..#files.."\n"..entry.path,"#ffd166")
    local finished=false
    schedule(20000,function()
      if finished then return end
      finished=true;failed("Tiempo de descarga agotado: "..entry.path..". El codigo actual se conserva.")
    end)
    httpGet(entry.url,function(contents,message)
      if finished then return end
      finished=true
      if not contents then failed("No se pudo descargar "..entry.path..": "..tostring(message));return end
      if isShutdownPayload(contents) then installing=false;blockShutdownUpdate();return end
      local staged,reason=pcall(function() session.stage(entry,contents) end)
      if not staged then failed(reason);return end
      state.done=index;renderState()
      schedule(50,function() download(index+1) end)
    end)
  end
  download(1)
end

local function showManifestStatus(manifest)
  if not manifest then return end
  refreshDetailsWindow(manifest)
  if updatePlanError then setState("error","Actualizacion detenida",updatePlanError,"#ff8a8a");return end
  if tostring(manifest.version) == tostring(config.version) and #lastPendingFiles == 0 then
    rememberExistingHashes(manifest)
    setState("current", "Todo actualizado", "Ya tienes la ultima version.", "#8cff9a")
  else
    setState("available", "Actualizacion disponible", #lastPendingFiles .. " archivos pendientes.", "#ffd166")
  end
end

local function checkUpdates(showDetails,lightCheck)
  if isBusy() then return end
  if g_resources.fileExists("/bot/" .. getConfigName() .. "/_updates/pilot.marker") then
    setState("current","RinoBot piloto","Copia piloto protegida: la actualizacion publica no se instala aqui.","#8cff9a")
    return
  end
  fetchManifest(function(manifest,unchanged)
    if not manifest then return end
    if not unchanged then showManifestStatus(manifest) end
    if showDetails and detailsWindow then
      detailsWindow:show();refreshDetailsWindow(manifest);detailsWindow:raise();detailsWindow:focus()
    end
  end,lightCheck)
end

local function autoUpdateOnLogin()
  if isBusy() then return end
  if g_resources.fileExists("/bot/" .. getConfigName() .. "/_updates/pilot.marker") then checkUpdates(false);return end
  if developmentLocked() then checkUpdates(false,true); return end
  config.autoInstall=true
  fetchManifest(function(manifest,unchanged)
    if not manifest or unchanged then return end
    if config.failedVersion==manifest.version then
      setState("warning","Esperando version corregida","La version "..manifest.version.." fallo al iniciar; se conserva la recuperacion y se buscan nuevas versiones.","#ffd166")
      return
    end
    if compareVersions(manifest.version,installedVersion())<0 then
      setState("current","Version mas reciente instalada","Se conserva la version actual.","#8cff9a");return
    end
    local pending=lastPendingFiles
    if not updatePlanError and (#pending>0 or tostring(manifest.version)~=tostring(config.version)) then installManifest(manifest)
    else showManifestStatus(manifest) end
  end,true)
end
local function runInstall()
  if g_resources.fileExists("/bot/" .. getConfigName() .. "/_updates/pilot.marker") then checkUpdates(false);return end
  if developmentLocked() then lockedNotice(); return end
  if isBusy() then return end
  if lastManifest then
    setState("checking","Verificando archivos...","Comprobando los archivos actuales antes de instalar.","#ffd166")
    scanManifest(lastManifest,function(manifest) installManifest(manifest) end)
    return
  end
  fetchManifest(function(manifest) if manifest then installManifest(manifest) end end)
end

local function bindDetailsWindow(window)
  detailsWindow = window
  window:hide()
  window.check.onClick = function() checkUpdates(false) end
  window.install.onClick = runInstall
  window.closeButton.onClick = function() window:hide() end
  for _, name in ipairs({"News", "History", "Details"}) do
    local tab = name
    window.Tabs[tab].onClick = function() activeTab = tab; renderState() end
  end
  window.Options.Auto.onClick = function()
    config.autoInstall=true
    renderState()
  end
  window.Body.Progress.Frame.onGeometryChange = updateProgressWidth
  refreshDetailsWindow(lastManifest)
end

ensureDetailsWindow = function()
  if detailsWindow then return true end
  local rootWidget = g_ui.getRootWidget()
  if not rootWidget then return false end
  pcall(function() g_ui.importStyle("/bot/" .. getConfigName() .. "/vBot/Updater.otui") end)
  local ok, window = pcall(function() return UI.createWindow("UpdaterWindow", rootWidget) end)
  if not ok or not window then return false end
  bindDetailsWindow(window)
  return true
end

ui.open.onClick = function()
  if ensureDetailsWindow() then
    detailsWindow:show()
    refreshDetailsWindow(lastManifest)
    detailsWindow:raise(); detailsWindow:focus()
  else
    setState("error", "No se pudo abrir Updater", "No se cargo Updater.otui. Recarga el bot.", "#ff8a8a")
  end
end

-- Keep the Suite's existing API, including its status text and public history.
SabuezoUpdaterBridge = {
  getVersion = installedVersion,
  getAvailableVersion = function() return lastManifest and tostring(lastManifest.version or "-") or "-" end,
  getStatus = function() return ui.status and ui.status:getText() or "-" end,
  check = function() checkUpdates(false) end,
  install = runInstall,
  open = function() ui.open.onClick() end,
  fetchHistory = function(callback)
    return httpGet(withCacheBuster("https://raw.githubusercontent.com/Sabuezo12/sabuezo-bot-updates/main/changelog.txt"), callback, true)
  end
}

setState("idle", "Buscar actualizaciones", "La configuracion personal se conserva.")
-- One low-frequency chain per executor; old chains stop on reload.
local function automaticCheck()
  if updateRoot._rinoUpdaterGeneration~=updateGeneration then return end
  schedule(300000,automaticCheck)
  autoUpdateOnLogin()
end
schedule(100,automaticCheck)
UI.Separator()
