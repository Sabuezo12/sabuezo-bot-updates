-- Route numbers are a separate label: getText(), action and value remain
-- unchanged for route execution, recovery, extensions and saved .cfg files.
CaveBot.Waypoints = {}
local W = CaveBot.Waypoints
local buckets, marks = {}, {}
local dirty, queued, closed = true, false, false
local displayMacro
local BUCKET_SIZE = 16

-- Keep the existing palette's child descriptors aligned with the added controls.
-- This is presentation metadata only; missing metadata must not block startup.
local function appearanceChild(style,after,kind,id,color)
  local styles=HelperAppearance and HelperAppearance.metadata and HelperAppearance.metadata.styles
  if type(styles)~='table' or type(styles[style])~='table' or type(styles[kind])~='table' then return end
  local function copy(value)
    if type(value)~='table' then return value end
    local result={}
    for k,v in pairs(value) do result[k]=copy(v) end
    return result
  end
  local parent=styles[style]
  parent.children=parent.children or {}
  local index=#parent.children+1
  for i,child in ipairs(parent.children) do
    if child.id==id then return end
    if child.id==after then index=i+1 end
  end
  local child=copy(styles[kind])
  child.id=id
  if color then child.props=child.props or {};child.props.color=color end
  table.insert(parent.children,index,child)
end
appearanceChild('CaveBotAction',nil,'HelperThemeLabel','waypointNumber','#a9bbc6')
appearanceChild('CaveBotPanel','autoRecording','HelperThemePower','showWaypoints')
appearanceChild('HelperCaveBotPanel','autoRecording','HelperThemeToggle','showWaypoints')

local function key(position)
  return position.x..','..position.y..','..position.z
end

local function chain(widget,event,callback)
  local previous=widget[event]
  widget[event]=function(...)
    if type(previous)=='function' then previous(...)
    elseif type(previous)=='table' then
      for _,fn in ipairs(previous) do fn(...) end
    end
    callback(...)
  end
end

-- Only actions with a defined coordinate schema can create a map marker.
function W.position(action,value)
  local offset,minimum,maximum
  if action=='zonapz'then offset,minimum,maximum=1,3,3
  elseif action=='goto' then offset,minimum,maximum=1,3,4
  elseif action=='use' then offset,minimum,maximum=1,3,3
  elseif action=='usewith' then offset,minimum,maximum=2,4,4
  elseif action=='floorchange' then offset,minimum,maximum=1,8,8
  elseif action=='poscheck' then offset,minimum,maximum=3,5,5
  elseif action=='cleartile' then offset,minimum=1,3
  else return nil end
  if type(value)~='string' then return nil end
  local fields={}
  for part in (value..','):gmatch('(.-),') do fields[#fields+1]=part end
  if #fields<minimum or (maximum and #fields>maximum) then return nil end
  local position={x=tonumber(fields[offset]),y=tonumber(fields[offset+1]),z=tonumber(fields[offset+2])}
  for _,axis in ipairs({'x','y','z'}) do
    local n=position[axis]
    if not n or n~=math.floor(n) or n<0 or n>(axis=='z' and 15 or 65535) then return nil end
  end
  if position.x==65535 then return nil end -- Inventory positions are not map tiles.
  return position
end

local function erase(mark)
  local tile=g_map.getTile(mark.position)
  if tile and tile:getText()==mark.text then tile:setText('') end
end

function W.clear()
  for _,mark in pairs(marks) do erase(mark) end
  marks={}
end

local function markerText(cell,focused)
  local lines,line={},'WP '
  for index,number in ipairs(cell.numbers) do
    local part=number==focused and '['..number..']' or tostring(number)
    if #line+#part+1>22 then
      lines[#lines+1]=line
      line=''
      if #lines==3 then
        lines[3]=lines[3]..' +'..(#cell.numbers-index+1)
        return table.concat(lines,'\n')
      end
    end
    line=line..(line~='' and line~='WP ' and ', ' or '')..part
  end
  lines[#lines+1]=line
  return table.concat(lines,'\n')
end

function W.draw()
  if closed or storage.rinoWaypointPreview~=true then W.clear();return end
  local origin=player and player:getPosition()
  if not origin then W.clear();return end
  local range=type(g_map.getAwareRange)=='function' and g_map.getAwareRange() or {}
  local rx=math.min(32,math.ceil((tonumber(range.width) or 18)/2)+1)
  local ry=math.min(32,math.ceil((tonumber(range.height) or 14)/2)+1)
  local floor=buckets[origin.z] or {}
  local focused=CaveBot.actionList:getChildIndex(CaveBot.actionList:getFocusedChild())
  local visible={}
  for x=math.floor((origin.x-rx)/BUCKET_SIZE),math.floor((origin.x+rx)/BUCKET_SIZE) do
    for y=math.floor((origin.y-ry)/BUCKET_SIZE),math.floor((origin.y+ry)/BUCKET_SIZE) do
      for _,cell in ipairs(floor[x..','..y] or {}) do
        local position=cell.position
        if math.abs(position.x-origin.x)<=rx and math.abs(position.y-origin.y)<=ry then
          local tile=g_map.getTile(position)
          local id=key(position)
          local old=marks[id]
          local text=tile and tile:getText()
          -- Do not overwrite Push/KeepWall or other scripts' tile annotations.
          if tile and (text=='' or (old and text==old.text)) then
            local wanted=markerText(cell,focused)
            if text~=wanted then tile:setText(wanted) end
            visible[id]={position=position,text=wanted}
          end
        end
      end
    end
  end
  for id,mark in pairs(marks) do if not visible[id] then erase(mark) end end
  marks=visible
end

function W.refresh()
  if closed then return end
  buckets={}
  local cells={}
  for index,widget in ipairs(CaveBot.actionList:getChildren()) do
    if widget.waypointNumber then widget.waypointNumber:setText(index..'.') end
    local position=W.position(widget.action,widget.value)
    if position then
      local id=key(position)
      local cell=cells[id]
      if not cell then
        cell={position=position,numbers={}}
        cells[id]=cell
        buckets[position.z]=buckets[position.z] or {}
        local bucket=math.floor(position.x/BUCKET_SIZE)..','..math.floor(position.y/BUCKET_SIZE)
        local floor=buckets[position.z]
        floor[bucket]=floor[bucket] or {}
        floor[bucket][#floor[bucket]+1]=cell
      end
      cell.numbers[#cell.numbers+1]=index
    end
  end
  dirty=false
  W.draw()
end

function W.changed()
  if closed then return end
  dirty=true
  if queued then return end
  queued=true
  schedule(20,function()
    queued=false
    if dirty and not closed then W.refresh() end
  end)
end

function W.track(widget)
  if widget.waypointNumber then widget.waypointNumber:setText(CaveBot.actionList:getChildCount()..'.') end
  chain(widget,'onDestroy',W.changed)
  W.changed()
end

function W.setup(ui)
  local button=ui.showWaypoints
  button:setOn(storage.rinoWaypointPreview==true)
  button:setTooltip('Muestra los numeros de esta ruta sobre sus casillas.\nEl waypoint seleccionado aparece entre corchetes.\nTambien funciona con CaveBot apagado.')
  displayMacro=macro(250,function()
    if closed then return end
    if dirty then W.refresh() else W.draw() end
  end)
  displayMacro.setOn(storage.rinoWaypointPreview==true)
  button.onClick=function()
    local enabled=not button:isOn()
    storage.rinoWaypointPreview=enabled
    button:setOn(enabled)
    displayMacro.setOn(enabled)
    if enabled then
      if dirty then W.refresh() else W.draw() end
    else W.clear() end
  end
  chain(ui.list,'onChildFocusChange',function()
    if not dirty then W.draw() end
  end)
  chain(ui,'onDestroy',function()
    closed=true
    displayMacro.setOff()
    W.clear()
  end)
end
