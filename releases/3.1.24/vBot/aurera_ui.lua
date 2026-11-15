-- Aurera adapters stay inside this bot's sandbox and leave saved IDs intact.
local C=HelperClientCompat
if not C or not C.active then return end

-- A missing file must raise a Lua assertion before entering Aurera's reader.
local resources=g_resources
local checkedResources={}
for key,value in pairs(resources) do checkedResources[key]=value end
checkedResources.readFileContents=function(path,...)
  assert(type(path)=='string' and resources.fileExists(path),
    'Helper: archivo no disponible: '..tostring(path))
  return resources.readFileContents(path,...)
end
g_resources=setmetatable(checkedResources,{__index=resources})
local nativeDofile=dofile
local config=modules.game_bot.contentsPanel.config:getCurrentOption().text
dofile=function(path)
  assert(type(path)=='string','Helper: ruta de script invalida')
  local full='/bot/'..config..'/'..path:gsub('^/+','')
  assert(resources.fileExists(full),'Helper: archivo de script no disponible: '..full)
  return nativeDofile(path)
end

-- Native context helpers can retain references to the unwrapped game API.
local function actionHelper(original)
  return function(value,...)
    local id
    if type(value)=='number' or type(value)=='string' then id=value
    elseif value then
      local ok,result=pcall(function() return value:getId() end)
      if ok then id=result end
    end
    if id~=nil and not C.allowItemAction(id) then return false end
    return original(value,...)
  end
end
if type(use)=='function' then use=actionHelper(use) end
if type(useWith)=='function' then useWith=actionHelper(useWith) end
if type(voc)=='function' then
  local nativeVoc=voc
  voc=function() return C.baseVocation(nativeVoc()) end
end

-- BotContainer's native closure creates items with the client's original Item
-- class. Build its rows here so foreign IDs never reach that constructor.
-- Empty placeholders retain their original entry until the user edits them.
local nativeContainer=UI.Container
local function copyEntry(entry)
  if type(entry)=='number' then return {id=entry,count=1} end
  if type(entry)~='table' then return nil end
  local result={};for key,value in pairs(entry) do result[key]=value end
  return result
end
UI.Container=function(callback,unique,parent,widget)
  local panel=nativeContainer(function() end,unique,parent,widget)
  local setting=false
  local function collect()
    local result,duplicates={},{}
    for _,child in ipairs(panel.items:getChildren()) do
      local id=child:getItemId()
      local entry
      if id>=100 and C.isValidItemId(id) then
        entry={id=id,count=child:getItemCountOrSubType()}
      elseif child._aureraPreservedEntry then entry=copyEntry(child._aureraPreservedEntry) end
      if entry and (not unique or not duplicates[entry.id]) then
        result[#result+1]=entry;duplicates[entry.id]=true
      end
    end
    return result
  end
  panel.getItems=function() return collect() end
  panel.setItems=function(self,items)
    if self~=panel then items=self end
    items=type(items)=='table' and items or {}
    setting=true
    panel.items:destroyChildren()
    local size=math.max(10,#items+2)
    size=size+(5-size%5)%5
    for i=1,size do
      local child=g_ui.createWidget('BotItem',panel.items)
      local entry=copyEntry(items[i])
      if entry and C.isValidItemId(entry.id) then
        local count=tonumber(entry.count) or 1
        if count~=count or count==math.huge or count==-math.huge then count=1 end
        count=math.max(0,math.min(65535,math.floor(count)))
        child:setItem(C.createItem(entry.id,count))
      elseif entry and tonumber(entry.id) and tonumber(entry.id)~=0 then
        C.itemIdForDisplay(entry.id)
        child:setItem(nil)
        child._aureraPreservedEntry=entry
        child:setTooltip('ID '..tostring(entry.id)..' no disponible en este cliente. Arrastra su reemplazo para actualizarlo.')
      end
    end
    for _,child in ipairs(panel.items:getChildren()) do
      local row=child
      row.onItemChange=function()
        if setting then return end
        row._aureraPreservedEntry=nil
        local updated=collect()
        if type(callback)=='function' then callback(panel,updated) end
        panel:setItems(updated)
      end
    end
    setting=false
  end
  panel:setItems({})
  return panel
end
