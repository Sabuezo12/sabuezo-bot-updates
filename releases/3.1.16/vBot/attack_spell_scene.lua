-- Independent UI-only spell stage. Uses this client's Magical Archive metadata;
-- never invokes its shared preview controller or adds effects to the game map.
AttackSpellScene={}
local S=AttackSpellScene
local catalog,byWords,byRune={},nil,nil
local function valid(id,category)
 if type(id)~='number'or id<=0 or id%1~=0 then return false end
 if not catalog[category]then
  local ids={};local ok,all=pcall(g_things.getThingTypes,category)
  if ok and type(all)=='table'then for _,thing in pairs(all)do ids[thing:getId()]=true end end
  catalog[category]=ids
 end
 return catalog[category][id]==true
end
S.valid=valid
local function call(w,m,...)
 if not w or type(w[m])~='function'then return end
 local ok,value=pcall(w[m],w,...);if ok then return value end
end
local function alive(w)return w and not w:isDestroyed()end
local function visible(w)
 for i=1,32 do
  if not alive(w)or not w:isVisible()then return false end
  w=w:getParent();if not w then return true end
 end
 return false
end
local function normalize(words)return tostring(words or''):lower():gsub('^%s+',''):gsub('%s+$','')end
local function readJson(name)
 for _,root in ipairs({'/modules/game_cyclopedia/tab/magicalArchives/','/game_cyclopedia/tab/magicalArchives/'})do
  local p=root..name
  if g_resources.fileExists(p)then
   local ok,value=pcall(function()return json.decode(g_resources.readFileContents(p))end)
   if ok and type(value)=='table'then return value end
  end
 end
end
local function metadata(entry)
 if not byWords then
  byWords,byRune={},{}
  local descriptions,previews=readJson('spells.json'),readJson('spells-preview.json')
  for _,data in pairs(descriptions or{})do
   if type(data)=='table'then
    local preview=previews and(previews[tostring(data.spellid)]or previews[data.spellid])
    if type(preview)=='table'then
     byWords[normalize(data.formulaWithoutParams)]=preview
     if type(data.runeParams)=='table'then byRune[tonumber(data.runeParams.runeType)or 0]=preview end
    end
   end
  end
 end
 return (entry.itemId or 0)>100 and byRune[entry.itemId]or byWords[normalize(entry.spell)]
end
local function palette(entry)
 local data=metadata(entry);if not data then return end
 local counts={effect={},object={},missile={}}
 local keys={fieldEffect={'effect','effectID',2},objecttype={'object','objecttypeID',0},missile={'missile','missileID',3}}
 for _,stamp in ipairs(data.timestamps or{})do
  for _,a in ipairs(stamp.actions or{})do
   local spec=keys[a.action]
   if spec then
    local id=tonumber(a[spec[2]])
    if valid(id,spec[3])then local group=counts[spec[1]];group[id]=(group[id]or 0)+1 end
   end
  end
 end
 local result={}
 for key,group in pairs(counts)do
  local best=0
  for id,count in pairs(group)do if count>best then best=count;result[key]=id end end
 end
 if not(result.effect or result.object or result.missile)then return end
 return result
end
function S.available(entry)return entry~=nil and palette(entry)~=nil end
local styles={UIWidget='AttackSceneCanvas',UIItem='AttackSceneItem',UICreature='AttackSceneActor',
 Effect='AttackSceneEffectView',Missile='AttackSceneMissileView',UILabel='AttackSceneLabel'}
local stylesReady=false
local function prepareStyles()
 if stylesReady then return true end
 -- OTUI resolves native anchor constants even when game_bot omits them.
 local ok=pcall(g_ui.importStyleFromString,[[
AttackSceneCanvas < UIWidget
  anchors.left: parent.left
  anchors.top: parent.top
  phantom: true
AttackSceneItem < UIItem
  anchors.left: parent.left
  anchors.top: parent.top
  virtual: true
  phantom: true
AttackSceneActor < UICreature
  anchors.left: parent.left
  anchors.top: parent.top
  phantom: true
AttackSceneEffectView < Effect
  anchors.left: parent.left
  anchors.top: parent.top
  phantom: true
AttackSceneMissileView < Missile
  anchors.left: parent.left
  anchors.top: parent.top
  phantom: true
AttackSceneLabel < HelperThemeLabel
  anchors.left: parent.left
  anchors.top: parent.top
  phantom: true
]])
 stylesReady=ok;return ok
end
local function widget(kind,parent)
 local ok,w=pcall(UI.createWidget,styles[kind]or kind,parent);if ok then return w end
end
local function position(w,x,y,size)
 w:setSize({width=size,height=size});w:setMarginLeft(math.floor(x));w:setMarginTop(math.floor(y))
 w:setPhantom(true)
end
local function virtualItem(parent,id,x,y,size)
 if not valid(id,0)then return end
 local w=widget('UIItem',parent);if not w then return end
 position(w,x,y,size);w:setVirtual(true);w:setItemId(id)
 call(w,'setShowCount',false);call(w,'setFixedItemSize',true)
 return w
end
local function ownOutfit()
 local p=g_game.getLocalPlayer();local outfit=p and p:getOutfit()
 if type(outfit)~='table'or not valid(outfit.type,1)then return end
 local clean={type=outfit.type}
 for _,k in ipairs({'head','body','legs','feet','addons'})do
  local v=tonumber(outfit[k])or 0;clean[k]=math.max(0,math.min(k=='addons'and 3 or 132,math.floor(v)))
 end
 return clean
end
local function roundPixel(value)
 return value<0 and math.ceil(value-0.5)or math.floor(value+0.5)
end
function S.tilePlacement(x,y,tile,sourceSize)
 sourceSize=math.max(32,tonumber(sourceSize)or 32)
 local size=math.max(1,roundPixel(sourceSize*tile/32))
 -- Creature/effect framebuffers put their base 32px map tile at bottom-right.
 -- Keep that same map-cell anchor instead of centering each sprite rectangle.
 return {x=roundPixel(x+tile-size),y=roundPixel(y+tile-size),size=size,
  sourceSize=sourceSize,scale=size/sourceSize,tileX=x,tileY=y,tileSize=tile}
end
function S.actorPlacement(x,y,tile,sourceSize,bounds)
 sourceSize=math.max(64,math.min(255,math.ceil(tonumber(sourceSize)or 64)))
 local size=math.max(1,roundPixel(sourceSize*tile/32))
 local scale=size/sourceSize
 local width=math.min(sourceSize,math.max(1,tonumber(bounds and bounds.width)or 32))
 local height=math.min(sourceSize,math.max(1,tonumber(bounds and bounds.height)or 32))
 -- UICreature centers its actual sprite inside a larger source frame. Place
 -- that visible sprite's bottom/right on the caster tile, as the archive does.
 return {x=roundPixel(x+tile-(sourceSize+width)/2*scale),
  y=roundPixel(y+tile-(sourceSize+height)/2*scale),size=size,scale=scale,
  sourceSize=sourceSize,width=width,height=height,tileX=x,tileY=y,tileSize=tile}
end
function S.stop(panel)
 local state=panel._spellScene
 if state then state.retired=true;panel._spellScene=nil end
 if panel.scene and alive(panel.scene)then panel.scene:destroyChildren()end
end
function S.render(panel,entry,info,direction)
 if not entry or not panel.scene then return false end
 local colors=palette(entry);local outfit=ownOutfit()
 if not colors or not outfit or not prepareStyles()then S.stop(panel);return false end
 -- A newly shown sibling anchor may still have its old zero-size rectangle.
 -- Size this independent stage explicitly before calculating sprite positions.
 panel.scene:setSize(panel.grid:getSize())
 local key=json.encode({spell=entry.spell,item=entry.itemId,category=entry.category,pattern=entry.pattern,
  range=entry.spellRange,dir=direction,outfit=outfit,width=panel.scene:getWidth(),height=panel.scene:getHeight()})
 local current=panel._spellScene
 if current and current.key==key and not current.retired then return true end
 S.stop(panel)
 local frame=panel.scene
 local state={key=key,retired=false,effects={},objects={},frames=0,casts=0,palette=colors}
 panel._spellScene=state
 call(frame,'setClipping',true)
 local ground=widget('UIWidget',frame);local objects=widget('UIWidget',frame)
 local actors=widget('UIWidget',frame);local effects=widget('UIWidget',frame)
 if not(ground and objects and actors and effects)then S.stop(panel);return false end
 state.ground=ground
 for _,layer in ipairs({ground,objects,actors,effects})do
  layer:setSize(frame:getSize())
  layer:setPhantom(true);call(layer,'setClipping',true)
 end
 local caster={x=info.caster.x,y=info.caster.y}
 local target=info.target and{x=info.target.x,y=info.target.y}or nil
 local points={}
 if info.kind=='target'then caster={x=0,y=0};target={x=math.min(10,info.range or 7),y=0}end
 for _,p in ipairs(info.cells)do if p.kind~='range'then points[#points+1]={x=p.x,y=p.y}end end
 if info.kind=='target'then points={target}end
 if #points==0 and target then points={target}end
 local minX,maxX,minY,maxY=caster.x,caster.x,caster.y,caster.y
 local function bounds(p)
  minX=math.min(minX,p.x);maxX=math.max(maxX,p.x);minY=math.min(minY,p.y);maxY=math.max(maxY,p.y)
 end
 for _,p in ipairs(points)do bounds(p)end;if target then bounds(target)end
 minX,maxX,minY,maxY=minX-1,maxX+1,minY-1,maxY+1
 local cols,rows=maxX-minX+1,maxY-minY+1
 local tile=math.max(4,math.min(32,math.floor(math.min(frame:getWidth()/cols,frame:getHeight()/rows))))
 local ox=math.floor((frame:getWidth()-cols*tile)/2)-minX*tile
 local oy=math.floor((frame:getHeight()-rows*tile)/2)-minY*tile
 local function pos(p)return ox+p.x*tile,oy+p.y*tile end
 state.tileSize=tile;state.pointCount=#points;state.origin={x=ox,y=oy}
 local nativeAssets=HelperClient and HelperClient.id=='valkaris'
 for y=minY,maxY do for x=minX,maxX do
  local cell=widget('UIWidget',ground)
  local px,py=pos({x=x,y=y});position(cell,px,py,tile)
  cell:setPhantom(false);cell:setBackgroundColor('#6c7c80');cell:setBorderWidth(1);cell:setBorderColor('#bdc9cc')
  if nativeAssets then virtualItem(cell,8284,0,0,tile)end
  local dx,dy=x-caster.x,y-caster.y
  cell.onHoverChange=function(w,on)
   w:setBorderColor(on and'#fff1bb'or'#bdc9cc')
   panel.hover:setText(on and('X '..dx..', Y '..dy..' | '..math.max(math.abs(dx),math.abs(dy))..' SQM')or'Escena ilustrativa del spell seleccionado.')
  end
  cell.onClick=function()
   if info.directional and panel.onDirection and(dx~=0 or dy~=0)then
    local face=math.abs(dx)>math.abs(dy)and(dx>0 and 1 or 3)or(dy>0 and 2 or 0)
    panel.onDirection(face)
   end
   return true
  end
 end end
 local px,py=pos(caster)
 local creature=widget('UICreature',actors)
 if not creature then S.stop(panel);return false end
 creature:setOutfit(outfit)
 local face=info.directional and(direction or 0)or target and 1 or 2
 local internal=call(creature,'getCreature')
 if internal then internal:setDirection(face)end
 local bounds
 if type(g_things.getCreatureBoundingBox)=='function'then
  local ok,value=pcall(g_things.getCreatureBoundingBox,outfit.type,0,face,0)
  if ok and type(value)=='table'and(tonumber(value.width)or 0)>0 and(tonumber(value.height)or 0)>0 then bounds=value end
 end
 local sourceSize=math.max(64,tonumber(call(internal,'getExactSize'))or 64)
 local scalable=type(creature.setFixedCreatureSize)=='function'
 call(creature,'setCenter',scalable);call(creature,'setCenterByBoundingBox',scalable)
 call(creature,'setFixedCreatureSize',false)
 -- Older UICreature::draw treats a nonzero creature-size as an absolute
 -- pixel override. Zero scales its 64px source framebuffer into our rect.
 call(creature,'setCreatureSize',scalable and 100 or 0)
 call(creature,'setBaseScale',false);call(creature,'setIgnoreDisplacementShift',false)
 call(creature,'setCreatureSmooth',tile<32)
 if not scalable then sourceSize=64;bounds=nil end
 local layout=scalable and S.actorPlacement(px,py,tile,sourceSize,bounds)or S.tilePlacement(px,py,tile,64)
 layout.mode=scalable and'bounds'or'tile';layout.nativeSize=scalable and 100 or 0
 position(creature,layout.x,layout.y,layout.size)
 state.actorLayout=layout
 state.creature=creature
 if target then
  local x,y=pos(target)
  if nativeAssets then virtualItem(actors,5787,x,y,tile)
  else
   local label=widget('UILabel',actors);position(label,x,y,tile);label:setText('T');label:setColor('#ffd07a')
  end
 end
 local function active()return not state.retired and panel._spellScene==state and alive(frame)end
 local function later(delay,fn)
  schedule(delay,function()if active()then fn()end end)
 end
 local function clear()
  if alive(effects)then effects:destroyChildren()end
  if alive(objects)then objects:destroyChildren()end
 end
 local function drawEffects()
  state.effectLayouts={}
  for _,p in ipairs(points)do
   local x,y=pos(p)
   if colors.object then virtualItem(objects,colors.object,x,y,tile)end
   if colors.effect then
    local w=widget('Effect',effects)
    if w and type(w.setEffectId)=='function'then
     w:setEffectId(colors.effect)
     local thing=g_things.getThingType(colors.effect,2)
     local internalEffect=call(w,'getEffect')
     local exact=call(internalEffect,'getExactSize')or call(thing,'getExactSize')or 32
     local layout=S.tilePlacement(x,y,tile,exact)
     layout.point={x=p.x,y=p.y};layout.widget=w
     state.effectLayouts[#state.effectLayouts+1]=layout
     position(w,layout.x,layout.y,layout.size)
     call(w,'setEffectVisible',true)
     state.frames=state.frames+1
    elseif w then w:destroy()end
   end
  end
 end
 local function cast()
  if not active()or not visible(frame)then return end
  clear();state.casts=state.casts+1;state.castEpoch=(state.castEpoch or 0)+1
  local epoch=state.castEpoch
  local function cue(delay,fn)later(delay,function()if state.castEpoch==epoch then fn()end end)end
  local delay=0
  if colors.missile and target then
   local w=widget('Missile',effects)
   if w and type(w.setMissileId)=='function'then
    local x,y=pos(caster);local tx,ty=pos(target)
    local dx,dy=target.x-caster.x,target.y-caster.y
    local face=dy==0 and(dx>0 and 1 or 3)or dx==0 and(dy>0 and 2 or 0)or
      dx>0 and(dy>0 and 5 or 4)or(dy>0 and 6 or 7)
    position(w,x,y,tile);w:setMissileId(colors.missile);call(w,'setDirection',face);call(w,'setMissileVisible',true)
    delay=math.max(100,math.max(math.abs(target.x-caster.x),math.abs(target.y-caster.y))*50)
    local steps=math.max(1,math.floor(delay/40))
    for i=1,steps do
     cue(i*delay/steps,function()
      if alive(w)then w:setMarginLeft(math.floor(x+(tx-x)*i/steps));w:setMarginTop(math.floor(y+(ty-y)*i/steps))end
     end)
    end
    cue(delay+40,function()if alive(w)then w:destroy()end end)
   elseif w then w:destroy()end
  end
  cue(delay,drawEffects)
 end
 state.replay=cast
 local function loop()
  if not active()then return end
  if visible(frame)then cast();later(2000,loop)else later(500,loop)end
 end
 later(100,loop)
 return true
end
