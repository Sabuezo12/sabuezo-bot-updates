-- Optional Windows companion. All generated files stay outside the public payload.
RinoAfkWindows={}
function RinoAfkWindows.new(host)
 local B={sequence=0,started=false,failed=false}
 local io,os=host.io,host.os
 local function read(path)
  if not io or type(io.open)~='function'then return end
  local ok,value=pcall(function()local f=io.open(path,'rb');if not f then return end;local s=f:read(8192);f:close();return s end)
  return ok and value or nil
 end
 local function write(path,text)
  local ok,result=pcall(function()local f=io.open(path,'wb');if not f then return false end;local result=f:write(text);f:close();return result~=nil end)
  return ok and result==true
 end
 local function lines(text)
  local out={};for line in (tostring(text or'')..'\n'):gmatch('(.-)\n')do out[#out+1]=line:gsub('\r$','')end
  return out
 end
 local function hash(text)
  local n=0;for i=1,#text do n=(n*31+text:byte(i))%2147483647 end;return tostring(n)
 end
 local function vbs(value)return'"'..value:gsub('"','""')..'"'end
 function B.command(command,minutes)
  if not B.control then return false end
  -- An old profile must not release a replacement profile's registration.
  local old=lines(read(B.control))
  if command=='release'and old[2]and old[2]~=B.token then return false end
  B.sequence=B.sequence+1
  return write(B.control,table.concat({'1',B.token,tostring(B.pid),tostring(minutes or B.minutes or 5),command,tostring(B.sequence),B.label},'\n')..'\n')
 end
 function B.start(minutes)
  B.minutes=minutes;B.failed=false;B.unavailable=nil;B.waitBeat=nil;B.heartbeat=nil;B.seenAt=nil;B.lastStatus=nil;B.startedAt=host.clock();B.started=true
  if not io or type(io.open)~='function'or not os or type(os.getenv)~='function'or
     not host.platform or type(host.platform.getProcessId)~='function'or type(host.platform.openUrl)~='function'then B.unavailable=true;return true end
  local localRoot=os.getenv('LOCALAPPDATA');local systemRoot=os.getenv('SystemRoot')
  if not localRoot or not systemRoot or os.getenv('OS')~='Windows_NT'then B.unavailable=true;return true end
  local source=host.source();if type(source)~='string'or source==''then B.unavailable=true;return true end
  B.pid=tonumber(host.platform.getProcessId());if not B.pid or B.pid<1 then B.unavailable=true;return true end
  B.token=tostring(B.pid)..'-'..tostring(host.clock())..'-'..tostring({}):gsub('[^%w]','')
  B.label=tostring(host.label()or'Cliente'):gsub('[\r\n]',' '):sub(1,60)
  B.folder=localRoot:gsub('\\','/')..'/RinoBot/AFK/'..hash(source)
  B.control=B.folder..'/'..B.pid..'.control';B.status=B.folder..'/'..B.pid..'.status'
  local private=host.privateFolder();if not private then B.unavailable=true;return true end
  local cs=private..'/source-'..B.pid..'.cs';local bootstrap=private..'/start-'..B.pid..'.vbs'
  if not write(cs,source)then B.unavailable=true;return true end
  -- The build lock is acquired by CreateTextFile(overwrite=false), and its
  -- compiler output uses a unique temporary filename before publication.
  local code=table.concat({
   'On Error Resume Next',
   'Set fs=CreateObject("Scripting.FileSystemObject")',
   'Set sh=CreateObject("WScript.Shell")',
   'Sub MakeDir(p)',
   ' If Not fs.FolderExists(p) Then MakeDir fs.GetParentFolderName(p): fs.CreateFolder p',
   'End Sub',
   'Function Q(s): Q=Chr(34)&s&Chr(34): End Function',
   'base='..vbs(B.folder),
   'base=Replace(base,"/","\\")',
   'MakeDir base',
   'binary=base&"\\RinoBotAfk.exe"',
   'source='..vbs(cs),
   'compiler='..vbs(systemRoot..'/Microsoft.NET/Framework/v4.0.30319/csc.exe'),
   'source=Replace(source,"/","\\"): compiler=Replace(compiler,"/","\\")',
   'If Not fs.FileExists(binary) Then',
   ' If Not fs.FileExists(compiler) Then WScript.Quit 2',
   ' If fs.FileExists(base&"\\build.lock") Then',
   '  If DateDiff("s",fs.GetFile(base&"\\build.lock").DateLastModified,Now)>120 Then fs.DeleteFile base&"\\build.lock",True',
   ' End If',
   ' Err.Clear',
   ' Set lock=fs.CreateTextFile(base&"\\build.lock",False)',
   ' If Err.Number=0 Then',
   '  temp=base&"\\build-"&Replace(CStr(Timer),".","-")&"-"&CStr(Int(Rnd*100000))&".exe"',
   '  cmd=Q(compiler)&" /nologo /target:winexe /optimize+ /platform:anycpu /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /out:"&Q(temp)&" "&Q(source)',
   '  result=sh.Run(cmd,0,True)',
   '  Set report=fs.CreateTextFile(base&"\\build.status",True): report.WriteLine CStr(result): report.Close',
   '  If result=0 And fs.FileExists(temp) Then fs.MoveFile temp,binary',
   '  lock.Close: fs.DeleteFile base&"\\build.lock",True',
   ' Else',
   '  For i=1 To 100',
   '   If fs.FileExists(binary) Then Exit For',
   '   WScript.Sleep 200',
   '  Next',
   ' End If',
   'End If',
   'If fs.FileExists(binary) Then sh.Run Q(binary)&" "&Q(base),0,False',
  },'\r\n')..'\r\n'
  if not write(bootstrap,code)then B.unavailable=true;return true end
  B.bootstrap=bootstrap
  -- The bootstrap creates the shared directory; command writing begins once it exists.
  B.pendingCommand='auto'
  local ok=pcall(host.platform.openUrl,bootstrap)
  if not ok then B.unavailable=true end
  return true
 end
 function B.read()
  if B.unavailable=='waiting'then
   -- The companion can start late (first compile, antivirus scan). Leave the
   -- graphics-only fallback as soon as its heartbeat starts moving.
   local beat=read(B.folder..'/heartbeat')
   if beat and beat~=B.waitBeat then B.unavailable=nil;B.heartbeat=beat;B.seenAt=host.clock()end
  end
  if B.unavailable then return host.fallback(B.minutes)end
  local now=host.clock()
  if B.pendingCommand and B.control then
   if B.command(B.pendingCommand,B.minutes)then B.pendingCommand=nil end
  end
  local heartbeat=read(B.folder..'/heartbeat')
  -- A missed read keeps the last value: only the age decides the companion is gone.
  if heartbeat and heartbeat~=B.heartbeat then B.heartbeat=heartbeat;B.seenAt=now end
  if not B.seenAt then
   if now-B.startedAt>25000 then B.unavailable='waiting';B.waitBeat=heartbeat;return host.fallback(B.minutes)end
   return
  end
  if now-B.seenAt>12000 then return{failed=true}end
  if not heartbeat then return end
  local p=lines(read(B.status))
  local states={active=true,prepare=true,afk=true,wake=true,paused=true}
  if p[1]~='1'or p[2]~=B.token or not tonumber(p[3])or not states[p[4]]or not tonumber(p[5])or not p[6]or not tonumber(p[7])then
   if B.lastStatus then
    if now-B.lastStatus>5000 then return{failed=true}end
   elseif now-B.startedAt>25000 then B.unavailable=true;return host.fallback(B.minutes)end
   return
  end
  B.lastStatus=now
  local stamp=tonumber(p[5]);local age=stamp and math.abs(os.time()-stamp)or math.huge
  return{state=p[4],fresh=age<=4,eco=p[6]}
 end
 function B.release()
  if B.control then B.command('release',B.minutes)end
  B.pendingCommand=nil
 end
 function B.rescue()
  if B.bootstrap then pcall(host.platform.openUrl,B.bootstrap)end
 end
 function B.send(command,minutes)
  B.minutes=minutes or B.minutes
  if B.unavailable then return host.fallbackCommand(command)end
  -- The newest command replaces a pending one; an old 'auto' must not
  -- overwrite a manual 'afk' before the companion has read it.
  if B.command(command,minutes)then B.pendingCommand=nil else B.pendingCommand=command end
 end
 return B
end
