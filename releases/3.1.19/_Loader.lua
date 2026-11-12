-- Portable client bootstrap. Only this helper's executor is adapted.
-- Load profile: how long each start-up step takes. It is measuring only; it never changes
-- what is loaded. Result: console ("Carga") and _diagnostics/load-profile.json.
RinoLoadProfile={steps={},disabled=not(type(os)=='table' and type(os.clock)=='function')}
do
  local P=RinoLoadProfile
  local function clock()return os.clock()end
  if not P.disabled then P.t0=clock();P.last=P.t0 end
  local function ms(seconds)return math.floor(seconds*1000+0.5)end
  -- time since the previous step ended, under this label
  function P.mark(label)
    if P.disabled then return end
    local t=clock()
    P.steps[#P.steps+1]={label=label,ms=ms(t-P.last)}
    P.last=t
  end
  -- a module: total time (including Helper's per-module bookkeeping) and the file's own run time
  function P.add(label,started,runStarted,runEnded)
    if P.disabled then return end
    local t=clock()
    P.steps[#P.steps+1]={label=label,ms=ms(t-started),runMs=ms(runEnded-runStarted)}
    P.last=t
  end
  function P.finish(folder)
    if P.disabled or P.finished then return end
    P.finished=true
    local t=clock()
    local sum=0
    local sorted={}
    for i,step in ipairs(P.steps)do sum=sum+step.ms;sorted[i]=step end
    table.sort(sorted,function(a,b)return a.ms>b.ms end)
    P.totalMs,P.workMs,P.top=ms(t-P.t0),sum,{}
    for i=1,math.min(10,#sorted)do P.top[i]=sorted[i].label..' '..sorted[i].ms..' ms'end
    -- Helper's own bookkeeping, measured by HelperRegistry (inside the modules' run time).
    local hs=Helper and Helper.stats
    if type(hs)=='table' then
      P.helper={recordMs=ms((hs.recordMs or 0)/1000),recordCalls=hs.recordCalls or 0,
        tooltipMs=ms((hs.tooltipMs or 0)/1000),tooltipCalls=hs.tooltipCalls or 0,files={}}
      -- time inside each file, apart from the files it loads (nested dofile)
      local list={}
      for path,stat in pairs(hs.files or{})do
        list[#list+1]={path=path,selfMs=math.floor(stat.self+0.5),totalMs=math.floor(stat.total+0.5),calls=stat.calls}
      end
      table.sort(list,function(a,b)return a.selfMs>b.selfMs end)
      for i=1,math.min(15,#list)do P.helper.files[i]=list[i]end
    end
    pcall(function()
      local dir=folder..'/_diagnostics'
      if not g_resources.directoryExists(dir)then g_resources.makeDir(dir)end
      g_resources.writeFileContents(dir..'/load-profile.json',json.encode({
        at=os.date('%Y-%m-%d %H:%M:%S'),totalMs=P.totalMs,workMs=P.workMs,helper=P.helper,steps=P.steps,slowest=P.top},2))
    end)
    if RinoConsole and type(RinoConsole.log)=='function' then
      pcall(RinoConsole.log,'info','Carga',string.format('Bot cargado: %.1f s en total (%.1f s de trabajo). Mas lentos: %s%s',
        P.totalMs/1000,P.workMs/1000,table.concat(P.top,' | ',1,math.min(5,#P.top)),
        P.helper and string.format(' | H.record: %d ms (%d) | tooltips: %d ms (%d) | archivos: %s',P.helper.recordMs,
          P.helper.recordCalls,P.helper.tooltipMs,P.helper.tooltipCalls,
          (function()local out={}for i=1,math.min(3,#P.helper.files)do out[i]=P.helper.files[i].path..' '..P.helper.files[i].selfMs..' ms'end return table.concat(out,', ')end)()) or ''))
    end
  end
end
local helperConfig=modules.game_bot.contentsPanel.config:getCurrentOption().text
assert(type(helperConfig)=='string' and not helperConfig:find('[/\\%c]'),'Helper: carpeta invalida.')
local helperFolder='/bot/'..helperConfig
local nativeResources=g_resources
local helperWriteRoot=nativeResources.getWriteDir():gsub('\\','/'):gsub('/+$','')
local helperIO=modules.corelib and modules.corelib.io or io
local helperCompile=loadstring or load
assert(type(helperCompile)=='function','Helper: este cliente no permite cargar sus modulos Lua.')
local function ownPath(path)
  assert(type(path)=='string' and path:match('^[%w_%-/%.]+$') and not path:find('..',1,true) and path:sub(1,1)~='/',
    'Helper: ruta de adaptador invalida.')
  return helperFolder..'/'..path
end
local function ownExists(path)
  local full=ownPath(path)
  if helperIO and type(helperIO.open)=='function' then
    local file=helperIO.open(helperWriteRoot..full,'rb')
    if not file then return false end
    file:close();return true
  end
  return nativeResources.fileExists(full)
end
local function ownRead(path)
  local full=ownPath(path)
  if helperIO and type(helperIO.open)=='function' then
    local file=assert(helperIO.open(helperWriteRoot..full,'rb'),'Helper: falta '..path)
    local source=file:read('*a');file:close()
    assert(type(source)=='string','Helper: lectura incompleta de '..path)
    return source
  end
  assert(nativeResources.fileExists(full),'Helper: falta '..path)
  return nativeResources.readFileContents(full)
end
local function ownRun(path)
  local fn,reason=helperCompile(ownRead(path))
  assert(fn,'Helper: adaptador invalido '..path..': '..tostring(reason))
  return fn()
end
ownRun('vBot/client_registry.lua')
local path=(helperWriteRoot..'/'):lower()
local rules={}
if ownExists('_helper_client/clients.json') then
  local ok,data=pcall(json.decode,ownRead('_helper_client/clients.json'))
  assert(ok and type(data)=='table' and data.version==1 and type(data.clients)=='table','Helper: registro local de clientes invalido.')
  for _,entry in ipairs(data.clients) do rules[#rules+1]=entry end
end
for _,entry in ipairs(HelperClientRegistry) do rules[#rules+1]=entry end
local selected
for _,entry in ipairs(rules) do
  assert(type(entry)=='table' and type(entry.id)=='string' and entry.id:match('^[%w_%-]+$') and
    type(entry.name)=='string' and (entry.path==nil or type(entry.path)=='string'),'Helper: entrada de cliente invalida.')
  if entry.path==nil or path:find(entry.path:lower(),1,true) then selected=entry;break end
end
assert(selected,'Helper: falta el adaptador generico.')
HelperClient={id=selected.id,name=selected.name,managed=true,coreVersion='3.1.19',writeRoot=helperWriteRoot}
-- Native module environments expose their own constants even when game_bot
-- omits those constants from the executor's global namespace.
local nativeEnvironment=modules.gamelib or modules.game_interface or {}
HelperClient.nativeFeatures={}
for _,name in ipairs({'GameThingQuickLoot','GameQuickLoot','GameQuickLootFlags'})do
  local value=nativeEnvironment[name]
  if type(value)=='number'and value>0 and value<256 and value==math.floor(value)then HelperClient.nativeFeatures[name]=value end
end
if type(nativeEnvironment.MarketCategory)=='table'then HelperClient.marketCategories=nativeEnvironment.MarketCategory end
if selected.adapter then
  assert(type(selected.adapter)=='string' and selected.adapter:match('^vBot/[%w_/%-]+%.lua$'),'Helper: adaptador fuera de vBot.')
  ownRun(selected.adapter)
end
-- The shared guards validate against each client's own catalog, not Aurera IDs.
ownRun('vBot/aurera_compat.lua')
ownRun('vBot/aurera_ui.lua')
RinoLoadProfile.mark('arranque: registro de cliente y adaptadores')
assert(type(g_ui.importStyleFromString)=='function','Helper: este cliente necesita un adaptador de estilos.')
assert(type(g_things.getThingTypes)=='function','Helper: este cliente necesita un adaptador del catalogo de objetos.')
local report={version=1,client=HelperClient.id,name=HelperClient.name,core=HelperClient.coreVersion,
  safeItemCatalog=type(g_things.getThingTypes)=='function',styleStrings=type(g_ui.importStyleFromString)=='function',
  quickLootAction=type(g_game.sendQuickLoot)=='function' or type(g_game.quickLoot)=='function',
  nativeSpellAim=type(g_game.setNextTalkAim)=='function',rawLocalFiles=helperIO and type(helperIO.open)=='function' or false}
local reportDirectory=helperFolder..'/_helper_client'
if not g_resources.directoryExists(reportDirectory) then g_resources.makeDir(reportDirectory) end
g_resources.writeFileContents(reportDirectory..'/capabilities.json',json.encode(report,2))
RinoLoadProfile.mark('arranque: capabilities.json')


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
RinoLoadProfile.mark('arranque: updater (definicion y comprobacion)')
if RinoBotUpdateBoot=="restored" then
  warn("RinoBot: instalacion anterior recuperada. Actualizacion automatica pausada.")
  schedule(50,function() reload() end)
  return
end

-- Base release of this full loader; independent of a character's saved cache.
-- Release packaging advances this marker together with the full payload.
RinoBotSourceVersion = "3.1.19"

-- Select the interface before importing styles or building the native panels.
local configName = modules.game_bot.contentsPanel.config:getCurrentOption().text
-- A verified new release always starts Helper, including upgrades from Classic.
-- Profile loading below preserves this decision and confirmRelease saves it.
if RinoBotUpdateBoot=="validate" then
  storage.helperUI=type(storage.helperUI)=="table" and storage.helperUI or {}
  storage.helperUI.legacy=false
end
local helperLegacy = type(storage.helperUI) == "table" and storage.helperUI.legacy == true
-- R204: retire the removed Reconect feature before loading bot modules.
do
  local shared=modules and modules.game_bot
  local native=modules and modules.rinobot_reconnect
  local seen,retired={},false
  local function stop(api)
    if type(api)~='table' or api.version~=1 or api.build~=195 then return false end
    if seen[api] then return true end
    seen[api]=true;retired=true
    if type(api.setEnabled)=='function' then pcall(api.setEnabled,false) end
    if type(api.shutdown)=='function' then pcall(api.shutdown) end
    return true
  end
  if g_game and stop(g_game.rinoReconnectApi) then g_game.rinoReconnectApi=nil end
  if shared and stop(shared.rinoReconnectApi) then shared.rinoReconnectApi=nil end
  if native and stop(native.api) then native.api=nil end
  AutoReconnect=nil;RinoReconnectCore=nil;RinoReconnectHost=nil
  RinoReconnectNativeInit=nil;RinoReconnectNativeTerminate=nil
  if type(storage)=='table' and type(storage.helperUI)=='table' and storage.helperUI.autoReconnectEnabled~=nil then
    storage.helperUI.autoReconnectEnabled=nil;retired=true
  end
  local R=g_resources
  local function remove(path)
    local ok,present=pcall(R.fileExists,path)
    if not ok or not present then return end
    retired=true
    if type(R.deleteFile)=='function' then pcall(R.deleteFile,path) end
    local checked,remains=pcall(R.fileExists,path)
    if checked and remains and type(warn)=='function' then warn('Bot: no se pudo retirar un archivo antiguo: '..path) end
  end
  if R and type(R.fileExists)=='function' then
    -- Never read plaintext files through the native encrypted module loader.
    for _,name in ipairs({'rinobot_reconnect.otmod','core.lua','host.lua'})do
      remove('/modules/rinobot_reconnect/'..name)
    end
    local ok,name=pcall(function()return modules.game_bot.contentsPanel.config:getCurrentOption().text end)
    if ok and type(name)=='string' and not name:find('[/\\]') and type(R.readFileContents)=='function' then
      local official={["vBot/AutoReconnect.lua"]={["01931a42cefe28f1f495728f7ccae99d997dc7562cd46ac00598a7b02e97c6f3"]=true,["6cb3bd6d35ab90aee15d9e641316da043f95954676fbd1c24051657ae5f2b082"]=true},["vBot/reconnect/core.lua"]={["bcdc37ec5b86625dbca65262262a31a23761043ff5fafd30e478a6beab108f9c"]=true},["vBot/reconnect/host.lua"]={["1c304bf74acf507218e48eb47ef16a2a01820e12aa233deb6ba42a52eae17adb"]=true},["vBot/reconnect/module.txt"]={["faf0d8f063510f8713a3850f58555c6a8bfb7e9bd3d2f9d36522de0e7dbf28a0"]=true}}
      for relative,hashes in pairs(official)do
        local path='/bot/'..name..'/'..relative
        -- Aurera can abort natively when readFileContents opens a missing Lua file.
        -- Check existence before entering C++; pcall alone cannot protect this call.
        local read,data=false,nil
        if R.fileExists(path) then read,data=pcall(R.readFileContents,path) end
        if read and type(data)=='string' and #data<=65536 and hashes[RinoBotUpdateCore.sha256(data)] then remove(path) end
      end
    end
  end
  if g_settings then
    if type(g_settings.getBoolean)=='function' then
      local ok,enabled=pcall(g_settings.getBoolean,'rinoAutoReconnectEnabled',false)
      if ok and enabled then retired=true end
    end
    if retired and type(g_settings.set)=='function' then
      pcall(g_settings.set,'rinoAutoReconnectEnabled',false)
      if type(g_settings.save)=='function' then pcall(g_settings.save) end
    end
  end
end
-- End R204 retirement.

local function nativeBotWindow()
  local exported = modules.game_bot.botWindow
  if exported then return exported end
  local root = g_ui.getRootWidget()
  local contents = modules.game_bot.contentsPanel
  local widget = contents
  for _ = 1, 12 do
    if not widget or widget == root then return nil end
    local ok, label = pcall(function() return widget:getText() end)
    if ok and label == "Bot" then return widget end
    local gotParent, parent = pcall(function() return widget:getParent() end)
    if not gotParent or not parent then return nil end
    if parent == root then return widget ~= contents and widget or nil end
    widget = parent
  end
end
local nativeWindow = nativeBotWindow()
local function nativeBotButton()
  if modules.game_bot.botButton then return modules.game_bot.botButton end
  return g_ui.getRootWidget():recursiveGetChildById("botButton")
end
local nativeButton = nativeBotButton()
local function visible(widget, fallback)
  if not widget then return fallback end
  local ok, value = pcall(function() return widget:isVisible() end)
  return ok and value == true or not ok and fallback
end
local function setVisible(widget, value)
  if widget then pcall(function() widget:setVisible(value) end) end
end

local root = g_ui.getRootWidget()
local priorGuard = root._sabuezoHelperNativeGuard
local windowWasVisible = visible(nativeWindow, true)
local buttonWasVisible = visible(nativeButton, true)
if priorGuard then
  if not helperLegacy and priorGuard.window == nativeWindow then
    windowWasVisible, buttonWasVisible = priorGuard.windowWasVisible, priorGuard.buttonWasVisible
    priorGuard.release(false) -- Transfer ownership without showing the old panel.
  else priorGuard.release(true) end
end
local nativeGuard, startupRuntime
local initializing = true
local function wantsHelper()
  if type(storage.helperUI) == "table" and storage.helperUI.legacy == true then return false end
  -- A live Helper owns the interface until explicit mode change or cleanup.
  -- Temporary options while the client rebuilds its selector must not release it.
  if initializing or startupRuntime and startupRuntime.valid() then return true end
  local ok, option = pcall(function()
    return modules.game_bot.contentsPanel.config:getCurrentOption()
  end)
  -- The client briefly clears its selector during reload.
  return not ok or not option or option.text == configName
end
local startupGeneration = {}
root._sabuezoHelperStartup = startupGeneration
local function currentStartup()
  if root._sabuezoHelperStartup ~= startupGeneration then return false end
  local classic = type(storage.helperUI) == "table" and storage.helperUI.legacy == true
  if classic ~= helperLegacy then return false end
  local ok, option = pcall(function()
    return modules.game_bot.contentsPanel.config:getCurrentOption()
  end)
  if not ok or not option or option.text ~= configName then return false end
  return helperLegacy or startupRuntime and startupRuntime.valid()
end
if not helperLegacy then
  nativeGuard = {window=nativeWindow, windowWasVisible=windowWasVisible, buttonWasVisible=buttonWasVisible}
  local released, bindings, protected, buttons = false, {}, {}, {}
  nativeGuard.release = function(restore)
    if released then return end
    released = true
    for _, binding in ipairs(bindings) do
      if binding.widget[binding.name] == binding.wrapper then binding.widget[binding.name] = binding.original end
    end
    for button, state in pairs(buttons) do
      if button.onClick == state.wrapper then
        button.onClick = state.original
        pcall(function() button:setTooltip(state.tooltip);button:setOn(state.on) end)
      end
      if restore then pcall(state.setter,button,state.wasVisible) end
    end
    if root._sabuezoHelperNativeGuard == nativeGuard then root._sabuezoHelperNativeGuard = nil end
    if restore then
      for widget, state in pairs(protected) do pcall(state.setter, widget, state.wasVisible) end
    end
  end
  local function protect(widget)
    if not widget or protected[widget] then return end
    local state = {setter=widget.setVisible, wasVisible=visible(widget, true)}
    if widget == nativeWindow then state.wasVisible = windowWasVisible end
    protected[widget] = state
    for _, name in ipairs({"show", "open", "setVisible"}) do
      local original = widget[name]
      if type(original) == "function" then
        local binding = {widget=widget, name=name, original=original}
        binding.wrapper = function(w, ...)
          local requested = ...
          local showing = name ~= "setVisible" or requested == true
          if not released and showing then
            if wantsHelper() then nativeGuard.hide(); return end
            nativeGuard.release(true)
          end
          return original(w, ...)
        end
        bindings[#bindings+1] = binding;widget[name] = binding.wrapper
      end
    end
  end
  nativeGuard.syncButton = function()
    if released then return end
    local button=nativeBotButton() or nativeButton
    if not button then return end
    nativeButton=button
    local state=buttons[button]
    if not state then
      state={original=button.onClick,setter=button.setVisible,wasVisible=visible(button,true),tooltip=button:getTooltip(),on=button:isOn()}
      if button==nativeGuard.button then state.wasVisible=buttonWasVisible end
      state.wrapper=function()
        if not released and wantsHelper() and startupRuntime and startupRuntime.valid() and startupRuntime.toggleLauncher then
          startupRuntime.toggleLauncher()
        end
      end
      buttons[button]=state;button.onClick=state.wrapper
    end
    local shown=not(type(storage.helperUI)=="table" and storage.helperUI.launcherVisible==false)
    if not visible(button,false) then pcall(state.setter,button,true) end
    if button:isOn()~=shown then button:setOn(shown) end
    local tooltip=shown and "Ocultar icono RBot" or "Mostrar icono RBot"
    if button:getTooltip()~=tooltip then button:setTooltip(tooltip) end
  end
  nativeGuard.button=nativeButton
  protect(nativeWindow)
  nativeGuard.hide = function()
    if released then return end
    local currentWindow = nativeBotWindow() or nativeWindow
    protect(currentWindow);nativeWindow=currentWindow;nativeGuard.window=currentWindow
    if currentWindow then nativeGuard.windowWasVisible=protected[currentWindow].wasVisible end
    for widget,state in pairs(protected)do pcall(state.setter,widget,false)end
    -- The same native Bot button remains available to recover a hidden RBot.
    nativeGuard.syncButton()
  end
  root._sabuezoHelperNativeGuard = nativeGuard
  nativeGuard.hide()
end
local function recoverNativePanel()
  if root._sabuezoHelperStartup == startupGeneration then root._sabuezoHelperStartup = nil end
  if nativeGuard then nativeGuard.release(false) end
  if startupRuntime and startupRuntime.dispose then pcall(startupRuntime.dispose) end
  setVisible(nativeWindow, true)
  setVisible(nativeButton, true)
end

local function recoverRelease(message)
  if RinoBotUpdateBoot~="validate" then return false end
  local ok,reason=RinoBotUpdateSession.rollback()
  assert(ok,"RinoBot: recuperacion pendiente: " .. tostring(reason))
  storage.sabuezoUpdater=RinoBotUpdateSession.config
  warn("RinoBot: se recupero el codigo anterior: " .. tostring(message))
  schedule(50,function() reload() end)
  return true
end
local function confirmRelease()
  if HelperProfiles and HelperProfiles.valid() then assert(HelperProfiles.save()) end
  if type(saveConfig)=="function" then saveConfig() end
  RinoBotUpdateSession.confirm()
end
local function initialize()
dofile("/vBot/HelperProfiles.lua")
RinoLoadProfile.mark('HelperProfiles')
dofile("/vBot/HelperProfileCatalogs.lua")
RinoLoadProfile.mark('HelperProfileCatalogs')
if RinoBotUpdateBoot=="validate" or RinoBotUpdateBoot=="rolledBack" then storage.sabuezoUpdater=RinoBotUpdateSession.config end
-- Shared Helper components must be imported before module styles.

dofile("/vBot/HelperTheme.lua")
RinoLoadProfile.mark('HelperTheme')
dofile("/vBot/HelperAppearance.lua")
RinoLoadProfile.mark('HelperAppearance (tabla de estilos de 950 KB)')
dofile("/vBot/RinoSkin.lua")
RinoLoadProfile.mark('RinoSkin')
g_ui.importStyle("/bot/" .. configName .. "/vBot/HelperTheme.otui")
RinoLoadProfile.mark('importar HelperTheme.otui')

local configFiles = g_resources.listDirectoryFiles("/bot/" .. configName .. "/vBot", true, false)
for i, file in ipairs(configFiles) do
  local ext = file:split(".")
  if (ext[#ext]:lower() == "ui" or ext[#ext]:lower() == "otui") and not file:find("HelperTheme.otui", 1, true) then
    g_ui.importStyle(file)
  end
end

RinoLoadProfile.mark('importar todos los .otui de vBot ('..#configFiles..' archivos en la carpeta)')
g_ui.importStyle("/bot/" .. configName .. "/vBot/Inmortal.otui")
RinoLoadProfile.mark('importar Inmortal.otui')
local consoleLoaded,consoleError=pcall(dofile,"/vBot/RinoConsole.lua")
RinoLoadProfile.mark('RinoConsole')
if not consoleLoaded then
  local failedConsole=RinoConsole
  if failedConsole and type(failedConsole.dispose)=='function'then pcall(failedConsole.dispose)end
  local consoleRoot=g_ui.getRootWidget()
  if consoleRoot._rinoConsole==failedConsole then consoleRoot._rinoConsole=nil end
  RinoConsole=nil
  warn("RinoBot: consola omitida: "..tostring(consoleError))
end
dofile("/vBot/script_controls.lua")
RinoLoadProfile.mark('script_controls')

if helperLegacy then
  local previous = Helper or g_ui.getRootWidget()._sabuezoHelperRuntime
  if previous and previous.dispose then pcall(previous.dispose) end
  Helper, HelperPause = nil, nil
else
  dofile("/vBot/HelperRegistry.lua")
  RinoLoadProfile.mark('HelperRegistry (crea el panel del Helper)')
  startupRuntime = Helper
  local controlsNativePanel = true
  startupRuntime.hideNativePanel = function()
    if not controlsNativePanel or not startupRuntime.valid() then return end
    if type(storage.helperUI) == "table" and storage.helperUI.legacy == true then return end
    nativeGuard.hide()
    -- Keep the working refresh path independent of an early guard release.
    setVisible(nativeBotWindow() or nativeWindow, false)
    nativeGuard.syncButton()
  end
  startupRuntime.syncNativeButton = function() nativeGuard.syncButton() end
  startupRuntime.restoreNativePanel = function(keepHidden)
    if keepHidden and wantsHelper() then nativeGuard.hide()
    else controlsNativePanel = false; nativeGuard.release(true) end
  end
end

local function loadScript(name)
  local profileStarted = os.clock and os.clock() or 0
  local path = "/" .. name .. ".lua"
  -- Optional modules must be checked before the native file reader is called.
  if not g_resources.fileExists("/bot/" .. configName .. path) then
    warn("Bot: archivo faltante, se omitira hasta el siguiente update: " .. path)
    return nil
  end
  local scriptControls=RinoScriptControls
  local previousSource=scriptControls and scriptControls.source
  if scriptControls then scriptControls.source=name end
  local before = Helper and Helper.valid() and Helper.before(name)
  local runStarted = os.clock and os.clock() or 0
  local loaded, result = pcall(dofile, path)
  local runEnded = os.clock and os.clock() or 0
  if before then Helper.after(name, before) end
  if scriptControls then scriptControls.source=previousSource end
  RinoLoadProfile.add(name, profileStarted, runStarted, runEnded)
  if loaded then return result end

  local loadError = tostring(result)
  local normalizedError = loadError:lower()
  local missing = normalizedError:find("unable to open file", 1, true) or
    normalizedError:find("cannot open", 1, true) or
    normalizedError:find("no such file", 1, true)

  if missing then
    warn("Bot: archivo faltante, se omitira hasta el siguiente update: " .. path)
    return nil
  end

  assert(false,result)
end

-- Files are grouped by the tab where their visible panel belongs.
-- Keep the relative order inside each group; that order defines the visual order in the bot.
local loaderSections = {
  {
    name = "Core",
    files = {
      "vBot/runtime_watch",    -- NEW: makes caught (pcall) errors and slow macros visible
      "vBot/client_compat",
      "vBot/ClientDetector",   -- NEW: capability detection first
      "vBot/ServerDetector",   -- NEW: server fingerprinting
      "vBot/api_compat",       -- NEW: guarded g_game/g_things facade (used by TargetBot, Inmortal, HelperAPI)
      "vBot/key_capture",      -- NEW: pick a hotkey by pressing it (before the modules that ask for one)
      ---"vBot/layout_persistence",
      "vBot/items",
      "vBot/HelperAPI",        -- NEW: unified API (after items, needs item types)
      "vBot/vlib",
      "vBot/ItemCounter",
      ----"vBot/exivalast", -- replaced by pvp_support + iconos
      "vBot/new_cavebot_lib",
      "vBot/configs", -- do not change this and above
    }
  },
  {
    name = "Main",
    files = {
      "vBot/main",
      "vBot/Updater",
      "vBot/BotSettings",
      "vBot/ClientDiagnostics", -- NEW: client/server/DAT/feature diagnostics panel
      "vBot/extras",
      "vBot/minimap_drag",
      "vBot/extrasPvp",
      "vBot/GameBotServerTransport",
      "vBot/BotServer",
      "vBot/BotServerDashboard",
      "vBot/exiva_tracker",
      "vBot/playerlist",
      "vBot/combo_plus",
      ----"vBot/combo", -- replaced by combo_plus
      "vBot/TimerExecutor",
      ----"vBot/zzzz_ComboAttack", -- replaced by combo_plus
      "vBot/pushmax",
      ----"vBot/magicbag", -- disabled: automatic magic bag selling
      "vBot/BugMapMouse",
      "vBot/keepwall",
    }
  },
  {
    name = "Tools",
    files = {
      ---"vBot/Buffguild",
      "vBot/alarms",
      "vBot/recoge",
      "vBot/pullitems",
      "vBot/antipush1",
      "vBot/FireBomb",
      ---"vBot/Ering",
      ----"vBot/Dropper",
      "zFreeScripts/z_Auto-Party",
      ----"vBot/quiver_manager",
      ----"vBot/quiver_label",
      "vBot/tools",
      "vBot/forge_adapter",    -- NEW: Forge conversion adapter for clients without a native one
      "vBot/auto_forge_engine",
      "vBot/auto_forge",
      "vBot/fps_relog_engine",
      "vBot/fps_relog",
      "vBot/reconnect_engine",
      "vBot/reconnect",
      "vBot/ImbuementScrolls",
      "vBot/spy_level",
      "vBot/pvp_support",
      "vBot/dash",
      "vBot/custom_hotkeys",
    }
  },
  {
    name = "Cave",
    files = {
      "vBot/cave_target_settings",
      "vBot/cavebot",
      "vBot/exeta",
      "vBot/supplies",
      "vBot/depositer_config",
      "vBot/npc_talk",
      "vBot/cavebot_control_panel",
    }
  },
  {
    name = "Target",
    files = {
      "vBot/attack_spell_catalog",
      "vBot/attack_spell_vocations",
      "vBot/paladin_rotation_20261001",
      "vBot/attack_rotation",
      "vBot/aurera_spells",
      "vBot/AttackBot",
    }
  },
  {
    name = "HP",
    files = {
      ----"vBot/superhealth",
      "vBot/Inmortal",
      "vBot/Conditions",
      "vBot/Equipper",
      "vBot/friend_healer",
      ----"vBot/extrahealth",
      "zFreeScripts/zAutoBuff",
      "vBot/HealBot",
      -- "vBot/Heal-Old",
      ----"vBot/sio",
      ----"vBot/POT",
      "vBot/equip",
      "vBot/eat_food",
      "vBot/ManaTrainer",
    }
  },
  {
    name = "Final",
    files = {
      "vBot/console_ui",
      ---"vBot/analyzer",
      "vBot/container_layout",
      "vBot/ContainerManager",
      ----"vBot/xeno_menu", -- disabled: unused contextual menu
      "vBot/iconos",
      ----"vBot/bot_tabs", -- native tabs match vBot 4.8
      "zFreeScripts/CaveBotHUD",
    }
  }
}

for _, section in ipairs(loaderSections) do
  for _, file in ipairs(section.files) do
    loadScript(file)
  end
end

loadScript("vBot/HelperPause")
setDefaultTab("Main")
if helperLegacy then
  setVisible(nativeWindow, true)
  setVisible(nativeButton, true)
  if nativeButton then pcall(function() nativeButton:setOn(true) end) end
  local pauseButton
  pauseButton = UI.Button(HelperPause.isPaused() and "Reanudar Bot" or "Pausar Bot", function()
    HelperPause.setPaused(not HelperPause.isPaused())
    pauseButton:setText(HelperPause.isPaused() and "Reanudar Bot" or "Pausar Bot")
  end)
  UI.Button("Volver al modo Helper", function()
    storage.helperUI.legacy = false
    reload()
  end)
end

schedule(100, function()
  if not currentStartup() or vBot and vBot.InGameScriptManagerLoaded then return end

  local loaded, loadError = pcall(loadScript, "vBot/ingame_editor")
  if not loaded then
    warn("In-Game Script Editor no pudo cargarse:\n" .. tostring(loadError))
  end
end)

-- After the personal script editor has registered its native controls.
if not helperLegacy then
  schedule(250, function()
    if not currentStartup() then return end
    local ok, err = pcall(loadScript, "vBot/Helper")
    pcall(RinoLoadProfile.finish, helperFolder) -- last step of the start-up: write the profile
    if not ok or not startupRuntime.window or not startupRuntime.icon then
      recoverNativePanel()
      warn("Helper no pudo cargarse: " .. tostring(err or "interfaz incompleta"))
      recoverRelease(err or "interfaz incompleta")
    elseif RinoBotUpdateBoot=="validate" then
      confirmRelease()
      info("RinoBot actualizado. Tus perfiles fueron conservados. Respaldo: " .. tostring(storage.sabuezoUpdater.lastBackup))
    end
  end)
end
if helperLegacy and RinoBotUpdateBoot=="validate" then
  schedule(300,function() pcall(RinoLoadProfile.finish, helperFolder);confirmRelease();info("RinoBot actualizado en modo clasico. Tus perfiles fueron conservados.") end)
end
end
local initialized, initializationError = pcall(initialize)
initializing = false
if not initialized then
  recoverNativePanel()
  if not recoverRelease(initializationError) then assert(false,initializationError) end
end
