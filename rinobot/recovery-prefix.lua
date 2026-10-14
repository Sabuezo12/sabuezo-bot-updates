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
        assert(#data>0 and not data:find("One-time update: keep every published Lua file",1,true),"Updater: codigo vacio o retirado.")
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
      config.version=manifest.version;config.lastBackup=path
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
      config.version=j.previousVersion;config.fileHashes={};config.autoInstall=false;config.lastBackup=j.path
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
      config.version=j.previousVersion;config.autoInstall=false;config.fileHashes={};config.lastBackup=j.path
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
