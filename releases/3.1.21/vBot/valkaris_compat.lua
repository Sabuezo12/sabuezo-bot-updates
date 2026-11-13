-- Valkaris adapter, scoped to this bot executor.
-- Keep the shared client tables intact when Helper installs its wrappers.
local nativeResources=g_resources
local nativeUI=g_ui
g_resources=setmetatable({}, {__index=nativeResources})
g_ui=setmetatable({}, {__index=nativeUI})
local nativeImportStyle=nativeUI.importStyle
local folder='/bot/'..modules.game_bot.contentsPanel.config:getCurrentOption().text
local fileIO=modules.corelib and modules.corelib.io
assert(type(fileIO)=='table' and type(fileIO.open)=='function',
  'Valkaris: no esta disponible la lectura de archivos locales del Helper.')
local writeRoot=nativeResources.getWriteDir():gsub('\\','/'):gsub('/+$','')
local function scoped(path)
  if type(path)~='string' then return false end
  path=path:gsub('^/*','/'):gsub('/+','/')
  return path:sub(1,#folder+1)==folder..'/'
end

-- PhysFS write operations take paths relative to the write directory.
-- Create every parent in the writable tree even when a mounted package
-- already makes directoryExists return true.
local function writePath(path)
  assert(type(path)=='string' and not path:find('\\',1,true), 'Valkaris: ruta de escritura invalida.')
  path=path:gsub('^/+','')
  for part in path:gmatch('[^/]+') do
    assert(part~='..' and part~='.', 'Valkaris: ruta de escritura invalida.')
  end
  return path
end
local function directory(path)
  path=writePath(path)
  local parent=''
  for part in path:gmatch('[^/]+') do
    parent=parent=='' and part or parent..'/'..part
    nativeResources.makeDir(parent)
  end
  return nativeResources.directoryExists('/'..path)
end
g_resources.makeDir=directory
local function physical(path) return writeRoot..'/'..writePath(path) end
g_resources.fileExists=function(path)
  if not scoped(path) then return nativeResources.fileExists(path) end
  local file=fileIO.open(physical(path),'rb')
  if not file then return false end
  file:close()
  return true
end
g_resources.readFileContents=function(path)
  if not scoped(path) then return nativeResources.readFileContents(path) end
  local file,reason=fileIO.open(physical(path),'rb')
  assert(file,'Valkaris: no se pudo leer '..tostring(path)..': '..tostring(reason))
  local contents=file:read('*a')
  file:close()
  assert(type(contents)=='string','Valkaris: lectura incompleta de '..tostring(path))
  return contents
end
-- The bot's built-in dofile closes over the client's original resource table.
-- Keep every Helper submodule on the same raw local reader as its profiles.
local compile=loadstring or load
dofile=function(path)
  assert(type(path)=='string','Valkaris: ruta de modulo invalida.')
  local full=folder..'/'..writePath(path)
  local source=g_resources.readFileContents(full)
  if ValkarisFontLua then source=ValkarisFontLua(source)end
  return assert(compile(source))()
end
g_resources.writeFileContents=function(path,contents)
  if not scoped(path) then return nativeResources.writeFileContents(path,contents) end
  path=writePath(path)
  local parent=path:match('^(.*)/[^/]+$')
  if parent then assert(directory(parent), 'Valkaris: no se pudo preparar '..parent) end
  local file,reason=fileIO.open(physical(path),'wb')
  assert(file,'Valkaris: no se pudo guardar '..path..': '..tostring(reason))
  local written,writeError=file:write(contents)
  local closed,closeError=file:close()
  assert(written and closed~=false,'Valkaris: escritura incompleta: '..tostring(writeError or closeError))
  return true
end

-- A small local startup trace survives native client crashes.
local tracePath=physical(folder..'/_helper_dev/startup.log')
local trace=fileIO.open(tracePath,'wb')
if trace then trace:write('Valkaris Helper startup\n');trace:close() end
ValkarisTrace=function(message)
  local file=fileIO.open(tracePath,'ab')
  if file then file:write(tostring(message)..'\n');file:close() end
end
ValkarisTrace('raw file adapter ready')

-- Fail before Helper wraps live widgets if persistence is unavailable.
local checkPath=folder..'/_helper_dev/compatibility-check.json'
local checkData='{"adapter":1,"client":"Valkaris"}'
ValkarisTrace('before persistence check')
assert(g_resources.writeFileContents(checkPath,checkData)~=false and
  g_resources.fileExists(checkPath) and g_resources.readFileContents(checkPath)==checkData,
  'Valkaris: no se puede verificar el guardado del Helper. Revisa la carpeta del bot.')
ValkarisTrace('persistence check passed')

-- Valkaris exposes file-based style import, but no string-based importer.
-- HelperAppearance already makes the source's image paths absolute.
if type(nativeUI.importStyleFromString)~='function' then
  local directory=folder..'/_valkaris_styles'
  local cache={}
  local nextStyle=0
  g_ui.importStyleFromString=function(source)
    assert(type(source)=='string','Valkaris: estilo invalido.')
    if ValkarisFontStyles then source=ValkarisFontStyles(source) end
    if type(nativeUI.loadUIFromString)=='function' then
      ValkarisTrace('before style string parse')
      local widget=nativeUI.loadUIFromString(source..'\nUIWidget\n  visible: false\n  size: 0 0\n')
      assert(widget,'Valkaris: no se pudieron importar los estilos del Helper.')
      widget:destroy()
      ValkarisTrace('after style string parse')
      return true
    end
    local path=cache[source]
    if not path then
      if not g_resources.directoryExists(directory) then g_resources.makeDir(directory) end
      assert(g_resources.directoryExists(directory),'Valkaris: no se pudo crear la carpeta de estilos.')
      nextStyle=nextStyle+1
      path=directory..'/style-'..nextStyle..'.otui'
      assert(g_resources.writeFileContents(path,source)~=false and g_resources.fileExists(path),
        'Valkaris: no se pudo guardar el estilo temporal.')
      cache[source]=path
    end
    ValkarisTrace('before native style import '..path)
    local result=nativeImportStyle(path)
    ValkarisTrace('after native style import '..path)
    return result
  end
end

local function styleSource(source,path)
  local parent=path:match('^(.*)/[^/]+$')
  return (source..'\n'):gsub('([^\n]*)\n',function(line)
    local indent,value=line:match('^(%s*)image%-source:%s*(.-)%s*$')
    if value and value~='' and value:sub(1,1)~='/' and parent then
      return indent..'image-source: '..parent..'/'..value..'\n'
    end
    return line..'\n'
  end)
end
g_ui.importStyle=function(path,...)
  if scoped(path) then
    ValkarisTrace('import raw style '..path)
    return g_ui.importStyleFromString(styleSource(g_resources.readFileContents(path),path))
  end
  return nativeImportStyle(path,...)
end

-- Use the client's supported TTF renderer with its shipped font files.
-- Only Helper-owned styles and fresh Helper widgets use these names.
-- Verified in this client's shipped gamelib/const.lua and gameinterface.lua.
-- This fork omits the constant from game_bot's executor globals. Availability
-- still requires g_game.getFeature(83); this does not enable a server feature.
if HelperClient then
  HelperClient.nativeFeatures=HelperClient.nativeFeatures or {}
  HelperClient.nativeFeatures.GameThingQuickLoot=83
end
-- The packaged bitmap definition is named Verdana-9px (capital V), while
-- legacy bot item styles request verdana-9px. Keep the texture and metrics;
-- add only the missing spelling through the client's public font importer.
local uiRoot=nativeUI.getRootWidget()
if not uiRoot._helperValkarisCountFontAlias then
  local importer=modules.client_styles and modules.client_styles.importResources
  local originalFont='/data/fonts/otfont/verdana-9px.otfont'
  if type(importer)=='function' and nativeResources.fileExists(originalFont) then
    local aliasSource=nativeResources.readFileContents(originalFont)
    aliasSource=aliasSource:gsub('name:%s*Verdana%-9px','name: verdana-9px')
    aliasSource=aliasSource:gsub('texture:%s*verdana%-9px','texture: /data/fonts/otfont/verdana-9px.png')
    local aliasDir=folder..'/_helper_client/font-cache'
    assert(directory(aliasDir),'Valkaris: no se pudo preparar la fuente de contadores.')
    local aliasPath=aliasDir..'/verdana-9px.otfont'
    assert(nativeResources.writeFileContents(writePath(aliasPath),aliasSource)~=false,'Valkaris: no se pudo guardar la fuente de contadores.')
    importer(aliasDir:gsub('^/+',''),'otfont')
    uiRoot._helperValkarisCountFontAlias=true
  end
end
local fontMap={}
local definitions={
  {'rinobot-classic-sans16','/data/fonts/ttf/arialb.ttf',16},
  {'rinobot-classic-verdana11','/data/fonts/ttf/Verdana.ttf',11},
  {'rinobot-classic-verdana9','/data/fonts/ttf/Verdana.ttf',9},
  {'rinobot-classic-rounded11','/data/fonts/ttf/verdana-bold.ttf',11}
}
for _,definition in ipairs(definitions) do
  ValkarisTrace('before TTF '..definition[1])
  local widget=nativeUI.createWidget('UIWidget')
  assert(widget and type(widget.setTTFFont)=='function','Valkaris: no esta disponible el renderizado TTF.')
  widget:setTTFFont(definition[2],definition[3],0,'#000000')
  fontMap[definition[1]]=widget:getFont()
  widget:destroy()
  ValkarisTrace('after TTF '..definition[1]..' = '..tostring(fontMap[definition[1]]))
end
-- Shared source retains its usual font names; only this adapter maps them.
fontMap['sans-bold-16px']=fontMap['rinobot-classic-sans16']
fontMap['verdana-16px-rounded']=fontMap['rinobot-classic-sans16']
fontMap['verdana-11px-antialised']=fontMap['rinobot-classic-verdana11']
fontMap['verdana-9px']=fontMap['rinobot-classic-verdana9']
fontMap['verdana-11px-rounded']=fontMap['rinobot-classic-rounded11']
ValkarisFontName=function(name)return fontMap[name] or name end
ValkarisFontStyles=function(source)
  return source:gsub('(font:%s*)([%w%-_]+)',function(prefix,name)return prefix..ValkarisFontName(name)end)
end
ValkarisApplyFont=function(widget)
  if widget._valkarisFontAdapter or type(widget.setFont)~='function' then return end
  widget._valkarisFontAdapter=true
  local original=widget.setFont
  widget.setFont=function(self,name,...)return original(self,ValkarisFontName(name),...)end
  local name=widget:getFont()
  if fontMap[name] then original(widget,fontMap[name]) end
end
ValkarisHelperCompatibility={version=3}

ValkarisFontLua=function(source)
  source=ValkarisFontStyles(source)
  for name,value in pairs(fontMap)do
    local pattern=name:gsub('([^%w])','%%%1')
    source=source:gsub("'"..pattern.."'", "'"..value.."'")
    source=source:gsub('"'..pattern..'"','"'..value..'"')
  end
  return source
end

-- Direct Helper factories also create labels whose font is changed later.
local fontCreate=g_ui.createWidget
local function applyFonts(widget)
  ValkarisApplyFont(widget)
  for _,child in ipairs(widget:getChildren())do applyFonts(child)end
end
g_ui.createWidget=function(...)
  local widget=fontCreate(...);applyFonts(widget);return widget
end
