local S=CaveBot.SupremeCube
importStyle('/cavebot/supreme_cube_editor.otui')
dofile('/cavebot/supreme_cube_catalog.lua')
local function key(s)return tostring(s or''):lower()end
function S.edit(value,callback)
 local config,errorText=S.decode(value)
 local invalid=config==nil
 config=config or{category='Cities'}
 local window=UI.createWindow('CaveBotCubeWindow')
 window:setText('CaveBot | Supreme Cube');window.cubeItem:setItemId(S.ITEM_ID)
 window.intro:setTooltip('Para viajar con una condicion, coloca un label antes de este waypoint y usa una funcion para ir a ese label.')
 if invalid then window.help:setText(errorText..' Selecciona un destino para corregirlo.')end
 for _,section in ipairs(S.sections)do window.category:addOption(section.text,section.id)end
 window.category:setCurrentOptionByData(config.category)
 local chosen=config.destination
 local initial=true
 local function select(name)
  chosen=name;window.selected:setText(name and('Destino: '..name)or'Selecciona un destino.')
  window.ok:setEnabled(name~=nil)
  for _,row in ipairs(window.destinations:getChildren())do row:setOn(name~=nil and key(row.destinationName)==key(name))end
 end
 local function refresh()
  local option=window.category:getCurrentOption();local category=option and option.data
  local query=key(window.search:getText())
  local list,seen={},{}
  for _,name in ipairs(S.catalog[category]or{})do
   if type(name)=='string'and not seen[key(name)]then list[#list+1]=name;seen[key(name)]=true end
  end
  -- Older routes may contain a newer server destination than this catalog.
  if initial and chosen and not seen[key(chosen)]then list[#list+1]=chosen end
  window.destinations:destroyChildren()
  local selectedRow,count=nil,0
  for _,name in ipairs(list)do
   if key(name):find(query,1,true)then
    local row=UI.createWidget('CaveBotCubeDestination',window.destinations)
    row:setText(name);row.destinationName=name;count=count+1
    row:setOn(chosen~=nil and key(chosen)==key(name))
    row.onFocusChange=function(_,focused)if focused then select(name)end end
    row.onClick=function()window.destinations:focusChild(row);select(name)end
    if chosen and key(chosen)==key(name)then selectedRow=row end
   end
  end
  if selectedRow then window.destinations:focusChild(selectedRow)
  elseif count==0 then window.selected:setText('Sin coincidencias. Cambia la busqueda.');window.ok:setEnabled(false)
  else window.selected:setText('Selecciona un destino de la lista.');window.ok:setEnabled(false)end
 end
 window.category.onOptionChange=function()initial=false;select(nil);window.search:setText('');refresh()end
 window.search.onTextChange=refresh
 window.cancel.onClick=function()window:destroy()end
 window.onEscape=window.cancel.onClick
 if window.closeButton then window.closeButton.onClick=window.cancel.onClick end
 window.ok.onClick=function()
  if not chosen or not window.ok:isEnabled()then return end
  local category=window.category:getCurrentOption().data
  local encoded,message=S.encode({category=category,destination=chosen})
  if not encoded then window.selected:setText(message);return end
  callback(encoded);window:destroy()
 end
 select(chosen);refresh()
 return window
end
