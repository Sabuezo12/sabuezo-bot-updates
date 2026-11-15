-- Independent UI-only spell stage. Uses this client's Magical Archive metadata;
-- never invokes its shared preview controller or adds effects to the game map.
AttackSpellScene={}
local S=AttackSpellScene
local catalog,byWords,byRune={},nil,nil
local function valid(id,category)
 if type(id)~='number'or id<=0 or id%1~=0 then return false end
 if not catalog[category]then
  local ids,ready={};local ok,all=pcall(g_things.getThingTypes,category)
  if ok and type(all)=='table'then
   for _,thing in pairs(all)do
    local thingId=thing:getId()
    if thingId>0 then ids[thingId]=true;ready=true end
   end
  end
  -- The editor may open before the client's appearance catalog is ready.
  if not ready then return false end
  catalog[category]=ids
 end
 return catalog[category][id]==true
end
S.valid=valid
local function call(w,m,...)
 if not w or type(w[m])~='function'then return nil end
 local ok,value=pcall(w[m],w,...);if ok then return value end
 return nil
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
local archiveRoots={
 '/mods/game_cyclopedia/classes/magical_archive/',
 '/modules/game_cyclopedia/tab/magicalArchives/',
 '/game_cyclopedia/tab/magicalArchives/',
}
local function readJson(path)
 if g_resources.fileExists(path)then
  local ok,value=pcall(function()return json.decode(g_resources.readFileContents(path))end)
  if ok and type(value)=='table'then return value end
 end
end
local function readArchive()
 for _,root in ipairs(archiveRoots)do
  local descriptions=readJson(root..'spells.json')
  local previews=descriptions and readJson(root..'spells-preview.json')
  if previews then return descriptions,previews end
 end
end
local function metadata(entry)
 if not byWords then
  local descriptions,previews=readArchive()
  if not previews then return end
  byWords,byRune={},{}
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
 local result={centerEffects=data.fieldEffectsCenteredOnTiles==true}
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
 local p=g_game.getLocalPlayer()
 -- ApiCompat reads the outfit whatever the client returns (a table, or an object with getters).
 local outfit=p and(type(ApiCompat)=='table'and type(ApiCompat.playerOutfit)=='function'and ApiCompat.playerOutfit(p)or p:getOutfit())
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
 -- The classic creature framebuffer anchors its base tile at bottom-right.
 return {x=roundPixel(x+tile-size),y=roundPixel(y+tile-size),size=size,
  sourceSize=sourceSize,scale=size/sourceSize,tileX=x,tileY=y,tileSize=tile}
end
local function effectPlacement(x,y,tile,thing,centerOnTile)
 local exact=math.max(32,tonumber(call(thing,'getExactSize'))or 32)
 local size=math.max(1,math.floor(exact*tile/32))
 -- Classic clients still use the archive's effect offsets.
 local inset=math.floor((size-tile)/2)
 if centerOnTile then inset=inset+math.floor(tile/2)end
 return {x=x-inset,y=y-inset,size=size,tileX=x,tileY=y,tileSize=tile}
end
local function effectDuration(thing)
 local duration=tonumber(call(thing,'getIdleAnimationDuration'))or 0
 if duration>0 then return duration end
 local phases=tonumber(call(thing,'getAnimationPhases'))or 0
 return phases>0 and math.max(100,phases*75)or 1000
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
local function previewActor(parent,outfit,face,x,y,tile,nextGen)
 local creature=widget('UICreature',parent)
 if not creature then return end
 creature:setOutfit(outfit)
 call(creature,'setDirection',face)
 local internal=call(creature,'getCreature')
 call(internal,'setDirection',face)
 local bounds
 if type(g_things.getCreatureBoundingBox)=='function'then
  local ok,value=pcall(g_things.getCreatureBoundingBox,outfit.type,0,face,0)
  if ok and type(value)=='table'and(tonumber(value.width)or 0)>0 and(tonumber(value.height)or 0)>0 then bounds=value end
 end
 local sourceSize=math.max(64,tonumber(call(internal,'getExactSize'))or 64)
 local scalable=type(creature.setFixedCreatureSize)=='function'
 call(creature,'setCenter',scalable);call(creature,'setCenterByBoundingBox',scalable)
 -- Next Gen's Magical Archive draws actors with fixed sizing enabled.
 call(creature,'setFixedCreatureSize',nextGen)
 call(creature,'setCreatureSize',scalable and 100 or 0)
 call(creature,'setScale',1)
 call(creature,'setBaseScale',false);call(creature,'setIgnoreDisplacementShift',false)
 call(creature,'setCreatureSmooth',tile<32)
 local layout=scalable and S.actorPlacement(x,y,tile,sourceSize,bounds)or S.tilePlacement(x,y,tile,64)
 position(creature,layout.x,layout.y,layout.size)
 return creature,layout
end
local function facingToward(from,to)
 local dx,dy=to.x-from.x,to.y-from.y
 if math.abs(dx)>math.abs(dy)then return dx>0 and 1 or 3 end
 return dy<0 and 0 or 2
end
local function exampleTarget(info,caster,direction)
 if info.kind~='area'then return end
 local forward=({{x=0,y=-1},{x=1,y=0},{x=0,y=1},{x=-1,y=0}})[(direction or 0)+1]
 local best,bestScore
 for _,p in ipairs(info.cells)do
  local x,y=p.x-caster.x,p.y-caster.y
  if p.kind=='hit'and(x~=0 or y~=0)then
   local along=x*forward.x+y*forward.y
   local across=math.abs(x*forward.y-y*forward.x)
   local score=info.directional and (math.abs(along-3)+across*2)or(math.abs(x-1)+math.abs(y-1))
   if not best or score<bestScore then best,bestScore=p,score end
  end
 end
 return best
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
 local state={key=key,retired=false,frames=0,casts=0,palette=colors}
 panel._spellScene=state
 call(frame,'setClipping',true)
 local ground=widget('UIWidget',frame);local objects=widget('UIWidget',frame)
 local effects=widget('UIWidget',frame);local actors=widget('UIWidget',frame)
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
 local dummy=target or exampleTarget(info,caster,direction)
 local minX,maxX,minY,maxY=caster.x,caster.x,caster.y,caster.y
 local function bounds(p)
  minX=math.min(minX,p.x);maxX=math.max(maxX,p.x);minY=math.min(minY,p.y);maxY=math.max(maxY,p.y)
 end
 for _,p in ipairs(points)do bounds(p)end;if dummy then bounds(dummy)end
 minX,maxX,minY,maxY=minX-1,maxX+1,minY-1,maxY+1
 local cols,rows=maxX-minX+1,maxY-minY+1
 local tile=math.max(4,math.min(32,math.floor(math.min(frame:getWidth()/cols,frame:getHeight()/rows))))
 local ox=math.floor((frame:getWidth()-cols*tile)/2)-minX*tile
 local oy=math.floor((frame:getHeight()-rows*tile)/2)-minY*tile
 local function pos(p)return ox+p.x*tile,oy+p.y*tile end
 state.tileSize=tile;state.pointCount=#points;state.origin={x=ox,y=oy}
 local clientId=ClientDetector and ClientDetector.id or HelperClient and HelperClient.id
 local nativeAssets=clientId=='valkaris' or clientId=='valkaris-ng'
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
 local face=info.directional and(direction or 0)or dummy and facingToward(caster,dummy)or 2
 local nextGen=clientId=='valkaris-ng'
 local creature,layout=previewActor(actors,outfit,face,px,py,tile,nextGen)
 if not creature then S.stop(panel);return false end
 state.actorLayout=layout
 state.creature=creature
 if dummy then
  local x,y=pos(dummy)
  -- Use the public exercise dummy from the client, with the Archive's
  -- target marker as a fallback on catalogs without the dummy.
  local marker=nativeAssets and virtualItem(actors,28558,x,y,tile)or virtualItem(actors,5787,x,y,tile)
  if not marker then
   marker=widget('UILabel',actors)
   if marker then position(marker,x,y,tile);marker:setText('T');marker:setColor('#ffd07a')end
  end
  state.targetMarker=marker
 end
 local function active()return not state.retired and panel._spellScene==state and alive(frame)end
 local function later(delay,fn)
  schedule(delay,function()if active()then fn()end end)
 end
 local function clear()
  if alive(effects)then effects:destroyChildren()end
  if alive(objects)then objects:destroyChildren()end
 end
 local grenade=AttackSpellCatalog.isDivineGrenade(entry) and AttackSpellCatalog.find(entry.spell)
 local thing=colors.effect and g_things.getThingType(colors.effect,2)
 local spriteSize=call(thing,'getSize')
 local oversized=(tonumber(call(thing,'getExactSize'))or 0)>32 or
  (type(spriteSize)=='table'and math.max(tonumber(spriteSize.width)or 0,tonumber(spriteSize.height)or 0)>1)
 local duration=colors.effect and effectDuration(thing)or 1500
 local function drawEffects()
  state.effectLayouts={}
  for _,p in ipairs(points)do
   local x,y=pos(p)
   if colors.object and not grenade then virtualItem(objects,colors.object,x,y,tile)end
   if colors.effect then
    local clip=nextGen and widget('UIWidget',effects)
    if clip then
     -- Next Gen can draw overhanging sprites. Mark the exact footprint
     -- and fit the illustration to the same cell in both preview sizes.
     position(clip,x,y,tile);call(clip,'setClipping',true)
     clip:setBorderWidth(1);clip:setBorderColor('#a9df92')
    end
    local w=widget('Effect',clip or effects)
    if w and type(w.setEffectId)=='function'then
     w:setEffectId(colors.effect)
     local layout
     if clip then
      local size=oversized and math.max(1,roundPixel(tile*0.75))or tile
      local inset=math.floor((tile-size)/2)
      layout={x=inset,y=inset,size=size,tileX=x,tileY=y,tileSize=tile}
     else
      layout=effectPlacement(x,y,tile,thing,colors.centerEffects)
     end
     layout.point={x=p.x,y=p.y};layout.widget=w
     state.effectLayouts[#state.effectLayouts+1]=layout
     position(w,layout.x,layout.y,layout.size)
     call(w,'setEffectVisible',true)
     call(w,'setEffectSmooth',tile<32)
     state.frames=state.frames+1
    elseif w then w:destroy()end
   end
  end
 end
 local cast
 cast=function()
  if not active()then return end
  state.castEpoch=(state.castEpoch or 0)+1
  local epoch=state.castEpoch
  local function cue(delay,fn)later(delay,function()if state.castEpoch==epoch then fn()end end)end
  if not visible(frame)then cue(500,cast);return end
  clear();state.casts=state.casts+1
  local function impact()
   if visible(frame)then drawEffects()end
   cue(duration,function()
    clear()
    cue(1500,cast)
   end)
  end
  if grenade then
   if colors.object then virtualItem(objects,colors.object,px,py,tile)end
   cue(grenade.delayed,function()clear();impact()end)
   return
  end
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
  cue(delay,impact)
 end
 state.replay=cast
 later(100,function()if not state.castEpoch then cast()end end)
 return true
end
