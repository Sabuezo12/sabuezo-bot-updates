---@diagnostic disable: undefined-global
setDefaultTab('Main')
local root=g_ui.getRootWidget()
local previous=root._rinoPushMax
if previous then
  -- The native reload may destroy Helper's forms before this script is loaded.
  -- Retire first: even a legacy dispose/cancel must not write to its dead window.
  previous.active=false
  if type(previous.clearMarkers)=='function'then pcall(previous.clearMarkers)end
  if root._rinoPushMax==previous then root._rinoPushMax=nil end
  if previous.engine and type(previous.engine.cancel)=='function' then pcall(previous.engine.cancel,'Recarga del bot') end
  if previous.observer and type(previous.observer.setOff)=='function' then pcall(previous.observer.setOff,previous.observer) end
  if type(previous.dispose)=='function' then pcall(previous.dispose) end
  if previous.window then pcall(function()
    if not previous.window:isDestroyed() then previous.window:destroy() end
  end)end
end
dofile('/vBot/pushmax_engine.lua')
local owner={active=true,wakePending=false,runeUntil=0}
root._rinoPushMax=owner
local function valid() return owner.active and root._rinoPushMax==owner end
local function time() return tonumber(now) or 0 end
local function consoleLog(level,message,detail)
  if RinoConsole and RinoConsole.valid()then RinoConsole.log(level,'Push Max',message,detail)end
end
local function equal(a,b) return a and b and a.x==b.x and a.y==b.y and a.z==b.z end
local function distance(a,b)
  if not a or not b or a.z~=b.z then return 999 end
  return math.max(math.abs(a.x-b.x),math.abs(a.y-b.y))
end
local DEFAULT_DESTROY_FIELD_IDS='2118,2119,2120,118,105,2121,2122,2123,2124,2125,2126,2131,2132,2133,2134,2135'
storage.pushmax=storage.pushmax or {}
local config=storage.pushmax
if config.destroyFieldRuneId==nil and config.destroyRuneId~=nil then config.destroyFieldRuneId=config.destroyRuneId end
-- Preserve the player's hotkey, retry delay and old fields; migrate only known defaults.
local defaults={enabled=true,pushDelay=190,pushMaxKey='PageUp',pushMaxRuneId=3188,disintegrateRuneId=3197,
  destroyFieldRuneId=3148,finalMwallRuneId=3180,mwallBlockId=2128,destroyFieldIds=DEFAULT_DESTROY_FIELD_IDS}
for k,v in pairs(defaults) do if config[k]==nil then config[k]=v end end
for _,old in ipairs({'2118,105,2122','2118,118,105,2122,2123,2124,2125',
  '2118,118,105,2121,2122,2123,2124,2125,2126,2131,2132,2133,2134,2135'}) do
  if config.destroyFieldIds==old then config.destroyFieldIds=DEFAULT_DESTROY_FIELD_IDS end
end
config.engineVersion=3
local ui=setupUI([[
Panel
  height: 19
  HelperThemePower
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    width: 130
    text: Push Max
  HelperThemeButton
    id: push
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 17
    text: Setup
]])
ui:setId('pushmax')
local pushWindow=UI.createWindow('PushMaxWindow',root)
owner.window=pushWindow
pushWindow:hide()
local function tooltip(widget,text) if widget and widget.setTooltip then widget:setTooltip(text) end end
tooltip(ui.title,'Activa Push Max.\nSelecciona al jugador y marca el destino.\nEscape cancela el intento y conserva al jugador.')
tooltip(ui.push,'Configura las runas y la tecla\nde Push Max.')
tooltip(pushWindow.delayText,'Estado del intento actual.\nEl intervalo solo regula reintentos\nsin confirmacion.')
tooltip(pushWindow.delay,'Espera minima entre reintentos.\nUn movimiento confirmado permite\ncontinuar de inmediato.')
tooltip(pushWindow.runeId,'Fire Field: antipush desde distancia.\nPegado al objetivo usa Disintegrate.\nHuida PvP nunca usa esta runa.')
tooltip(pushWindow.disintegrateRuneId,'Disintegrate: objetos y monedas.\nEncadena un intento de empuje sin esperar\na que desaparezcan las monedas repuestas.')
tooltip(pushWindow.destroyRuneId,'Destroy Field: limpia fields a su alcance.\nReconoce etapas y flags del cliente.')
tooltip(pushWindow.mwallId,'Objeto de Magic Wall que bloquea el paso.')
tooltip(pushWindow.finalMwallRuneId,'Magic Wall final.\nElige una casilla libre junto al objetivo\ny comprueba que la wall aparezca.')
tooltip(pushWindow.destroyFieldIds,'IDs de fields separados por comas.\nLas tres etapas del fuego\nse reconocen juntas.')
tooltip(pushWindow.hotkey,'Selecciona al jugador y apunta al destino.\nRecuerda esa seleccion si cesa el ataque.\nPulsa tu tecla. Escape cancela.')
pushWindow.label3:setText('Fire Field')
pushWindow.disintegrateLabel:setText('Disint.')
pushWindow.label2:setText('MW obj.')
pushWindow.label4:setText('MW final')
pushWindow.label5:setText('IDs de fields')
pushWindow.label1:setText('Tecla de Push Max')
pushWindow.closeButton.onClick=function()pushWindow:hide()end

-- UI bindings are kept independent of the native engine for borrowed PvP forms.
local function bindControls(pushWindow,config,onEdit)
  if pushWindow.delay.setRange then pushWindow.delay:setRange(10,2000) end
  if pushWindow.delay.setStep then pushWindow.delay:setStep(10) end
  local updateDelayText=function()pushWindow.delayText:setText('Reintento: '..config.pushDelay..' ms')end
  updateDelayText()
  pushWindow.delay.onValueChange=function(_,value)config.pushDelay=value;if onEdit then onEdit()end;updateDelayText()end
  pushWindow.delay:setValue(config.pushDelay)
  pushWindow.runeId.onItemChange=function(widget)config.pushMaxRuneId=widget:getItemId();if onEdit then onEdit()end end
  pushWindow.runeId:setItemId(config.pushMaxRuneId)
  pushWindow.disintegrateRuneId.onItemChange=function(widget)config.disintegrateRuneId=widget:getItemId();if onEdit then onEdit()end end
  pushWindow.disintegrateRuneId:setItemId(config.disintegrateRuneId)
  pushWindow.destroyRuneId.onItemChange=function(widget)config.destroyFieldRuneId=widget:getItemId();if onEdit then onEdit()end end
  pushWindow.destroyRuneId:setItemId(config.destroyFieldRuneId)
  pushWindow.mwallId.onItemChange=function(widget)config.mwallBlockId=widget:getItemId();if onEdit then onEdit()end end
  pushWindow.mwallId:setItemId(config.mwallBlockId)
  pushWindow.finalMwallRuneId.onItemChange=function(widget)config.finalMwallRuneId=widget:getItemId();if onEdit then onEdit()end end
  pushWindow.finalMwallRuneId:setItemId(config.finalMwallRuneId)
  pushWindow.destroyFieldIds.onTextChange=function(_,text)config.destroyFieldIds=text;if onEdit then onEdit()end end
  pushWindow.destroyFieldIds:setText(config.destroyFieldIds)
  pushWindow.hotkey.onTextChange=function(_,text)config.pushMaxKey=text;if onEdit then onEdit()end end
  pushWindow.hotkey:setText(config.pushMaxKey)
end
bindControls(pushWindow,config,function()
  if owner.engine and owner.engine.job then owner.engine.cancel('Configuracion modificada')end
end)

local fields,fieldSource={},nil
local function fieldIds()
  local text=tostring(config.destroyFieldIds or '')
  if text~=fieldSource then
    fields={};fieldSource=text
    for id in DEFAULT_DESTROY_FIELD_IDS:gmatch('%d+') do fields[tonumber(id)]=true end
    for id in text:gmatch('%d+') do fields[tonumber(id)]=true end
    if fields[2118] or fields[2119] or fields[2120] then fields[2118]=true;fields[2119]=true;fields[2120]=true end
  end
  return fields
end
local function isPushWall(id)
  return id>=2127 and id<=2130 or id>=58242 and id<=58250 or id==tonumber(config.mwallBlockId)
end
local function isField(item)
  if isPushWall(item:getId()) then return false end
  if fieldIds()[item:getId()] then return true end
  local ok,value=pcall(function()return item.isMagicField and item:isMagicField()end)
  return ok and value==true
end
local function creature(id)
  if not id then return nil end
  if g_map.getCreatureById then
    local value=g_map.getCreatureById(id)
    if value then return value end
  end
  if getSpectators then
    for _,who in ipairs(getSpectators() or {}) do if who:getId()==id then return who end end
  end
end
local function playerTarget(who)
  if not who then return nil,'no-selection' end
  local ok,reason=pcall(function()
    if not who:isPlayer() then return 'not-player' end
    if not player or who:getId()==player:getId() then return 'self' end
    local p,own=who:getPosition(),player:getPosition()
    if not p or not own then return 'not-visible' end
    if p.z~=own.z then return 'other-floor' end
    if who.isDead and who:isDead() or who.getHealthPercent and who:getHealthPercent()<=0 then return 'dead' end
  end)
  if not ok then return nil,'invalid-creature' end
  if reason then return nil,reason end
  return who
end
local function clearSelection()
  owner.selection=nil;owner.selectionCleared=true
end
local function remember(who,source)
  if not who then return nil,'no-selection' end
  local ok,id,name=pcall(function()
    if not who:isPlayer()then return nil,'not-player' end
    if not player or who:getId()==player:getId()then return nil,'self' end
    return who:getId(),type(who.getName)=='function'and who:getName()or nil
  end)
  if not ok then return nil,'invalid-creature' end
  if not id then return nil,name end
  -- Position visibility and attack cancellation are not identity changes.
  if not owner.selection or owner.selection.id~=id or owner.selection.name~=name then
    owner.selection={id=id,name=type(name)=='string'and name:sub(1,100)or nil,at=time(),source=source}
  end
  owner.selectionCleared=false
  return who
end
local function liveTarget()
  local function read(fn)
    if type(fn)~='function' then return nil end
    local ok,who=pcall(fn);if ok then return who end
  end
  local who=read(g_game.getAttackingCreature)
  if who then return who,'native' end
  who=read(target);if who then return who,'target' end
  who=read(getTarget);if who then return who,'getTarget' end
end
local function resolvePlayer()
  owner.blockingTarget=nil
  local who,source=liveTarget()
  if who then
    local selected,reason=remember(who,source)
    if selected then
      local visible,why=playerTarget(selected)
      return visible,source,why
    end
    local ok,id=pcall(function()return who:getId()end)
    owner.blockingTarget=ok and id or nil
    return nil,source,reason
  end
  if owner.selection then
    local selected,reason=playerTarget(creature(owner.selection.id))
    if selected and owner.selection.name and type(selected.getName)=='function'
      and selected:getName()~=owner.selection.name then return nil,'remembered','identity-changed' end
    if selected then return selected,'remembered' end
    return nil,'remembered',reason
  end
  return nil,'none','no-selection'
end
local function attacked()
  local who=resolvePlayer()
  return who and who:getId() or owner.blockingTarget
end
local function nativeTile(p,targetId)
  local tile=g_map.getTile(p)
  local ground=tile and tile:getGround()
  if not ground then return nil end
  local movement=TargetBot and TargetBot.Movement
  local safe=movement and movement.floorSafe and movement.floorSafe(p,tile)
  if safe==nil then
    local color=tonumber(g_map.getMinimapColor and g_map.getMinimapColor(p)) or 0
    safe=not (color>=210 and color<=213) and not (tile.hasElevation and tile:hasElevation(3))
  end
  -- Ignore creature occupancy in terrain classification. The selected player
  -- blocks isWalkable(false) outside PZ; actors are validated separately below.
  local out={safe=safe,walkable=tile:isWalkable(true)==true,trash=0,hard=false,other=false,selected=false,
    shootable=not tile.canShoot or tile:canShoot()~=false}
  local ownId=player and player:getId()
  local selectedId=targetId or owner.selection and owner.selection.id
  for _,who in ipairs(tile:getCreatures() or {}) do
    local id=who:getId()
    if id~=ownId and id~=selectedId then out.other=true end
    if id==selectedId then out.selected=true end
  end
  local ids=fieldIds()
  for _,item in ipairs(tile:getItems() or {}) do
    local id=item:getId()
    if isPushWall(id) then
      -- Same MythicOT color/retro family already used by the existing wall timers.
      out.hard=true;out.wall=true
    elseif isField(item) then
      out.field=id
      if id==2118 or id==2119 or id==2120 then out.fire=true end
    elseif item~=ground and not (item.isGround and item:isGround()) and not (item.isGroundBorder and item:isGroundBorder())
      and type(item.isNotMoveable)=='function' and not item:isNotMoveable() then
      out.trash=out.trash+1
    elseif type(item.isBlocking)=='function' and item:isBlocking() then out.hard=true end
  end
  if not out.walkable and not out.field and out.trash==0 then out.hard=true end
  return out
end
local directions={{0,-1},{1,0},{0,1},{-1,0},{1,-1},{1,1},{-1,1},{-1,-1}}
local function ownStepKey(from,to)
  return from.x..':'..from.y..':'..from.z..'>'..to.x..':'..to.y..':'..to.z
end
local function walkAvoided(from,to)
  local untilAt=owner.walkAvoid and owner.walkAvoid[ownStepKey(from,to)]
  return untilAt and untilAt>time()
end
local function walkFailed(from,to,reason)
  owner.walkPlan=nil;owner.walkRecoverySignature=nil
  local n=time();local entries={}
  owner.walkAvoid=owner.walkAvoid or {}
  for edge,untilAt in pairs(owner.walkAvoid)do
    if untilAt<=n then owner.walkAvoid[edge]=nil else entries[#entries+1]={edge=edge,untilAt=untilAt}end
  end
  if #entries>=16 then
    table.sort(entries,function(a,b)return a.untilAt<b.untilAt end)
    owner.walkAvoid[entries[1].edge]=nil
  end
  -- A refused step is temporary and directional, not proof that the tile or
  -- marked push destination is blocked. Keep this cache bounded to the session.
  owner.walkAvoid[ownStepKey(from,to)]=n+1500
end
local function freeOwnTile(p)
  local t=nativeTile(p)
  return t and t.safe and t.walkable and not t.hard and not t.other and not t.selected and not t.field
end
local function recoverWalk(own,target,excluded,range,choices,movement)
  local neighbors={}
  for i,offset in ipairs(directions)do
    local to={x=own.x+offset[1],y=own.y+offset[2],z=own.z}
    if not equal(to,target)and not equal(to,excluded)and not walkAvoided(own,to)
      and freeOwnTile(to)and movement.pathSafe(own,{i-1})then
      neighbors[#neighbors+1]={to=to,direction=i-1,cost=distance(to,target)+(i>4 and 0.1 or 0)}
    end
  end
  table.sort(neighbors,function(a,b)return a.cost<b.cost end)
  local total=#neighbors*#choices
  if total==0 then return end
  local signature=ownStepKey(own,target)..'/'..excluded.x..':'..excluded.y..'/'..range
  if owner.walkRecoverySignature~=signature then owner.walkRecoverySignature=signature;owner.walkRecoveryIndex=1 end
  -- Try alternate FIRST steps explicitly: changing the end square alone can
  -- return the same rejected first step from every shortest-path query.
  for _=1,math.min(2,total)do
    local index=((owner.walkRecoveryIndex or 1)-1)%total
    owner.walkRecoveryIndex=index+2
    local neighbor=neighbors[index%#neighbors+1]
    local choice=choices[math.floor(index/#neighbors)+1]
    local tail=equal(neighbor.to,choice.pos)and{}or movement.findPath(neighbor.to,choice.pos,11,{precision=0})
    if tail then
      local path={neighbor.direction};for _,dir in ipairs(tail)do path[#path+1]=dir end
      local steps={};local from=own;local valid=#path<=12
      for _,dir in ipairs(path)do
        local to=movement.destination(from,dir)
        if not to or equal(to,own)or equal(to,target)or equal(to,excluded)or walkAvoided(from,to)or not freeOwnTile(to)then valid=false;break end
        steps[#steps+1]={from=from,to=to,direction=dir};from=to
      end
      if valid and distance(from,target)<=range and movement.pathSafe(own,path)then
        owner.walkPlan={target={x=target.x,y=target.y,z=target.z},excluded={x=excluded.x,y=excluded.y,z=excluded.z},range=range,steps=steps}
        return steps[1].direction,steps[1].to
      end
    end
  end
end
local function walkStep(target,excluded,range)
  local movement=TargetBot and TargetBot.Movement
  local own=player:getPosition()
  if not movement or not movement.findPath then return nil end
  range=math.max(1,math.min(5,tonumber(range)or 1))
  local plan=owner.walkPlan
  if plan and equal(plan.target,target)and equal(plan.excluded,excluded)and plan.range==range then
    while plan.steps[1]and equal(own,plan.steps[1].to)do table.remove(plan.steps,1)end
    local step=plan.steps[1]
    local t=step and nativeTile(step.to)
    if step and equal(own,step.from)and not walkAvoided(own,step.to)and t and t.safe and t.walkable and not t.hard and not t.other and not t.selected and not t.field
      and movement.pathSafe(own,{step.direction})then return step.direction,step.to end
  end
  owner.walkPlan=nil
  local choices={}
  for radius=1,range do for i=1,8 do
    local p={x=target.x+directions[i][1]*radius,y=target.y+directions[i][2]*radius,z=target.z}
    if not equal(p,excluded) then
      local t=nativeTile(p)
      if t and t.safe and t.walkable and not t.hard and not t.other and not t.selected and not t.field then
        choices[#choices+1]={pos=p,cost=distance(own,p)+distance(p,excluded)*0.1}
      end
    end
  end end
  table.sort(choices,function(a,b)return a.cost<b.cost end)
  for _,offset in ipairs(directions)do
    local to={x=own.x+offset[1],y=own.y+offset[2],z=own.z}
    if walkAvoided(own,to)then return recoverWalk(own,target,excluded,range,choices,movement)end
  end
  local signature=target.x..':'..target.y..':'..excluded.x..':'..excluded.y..':'..own.x..':'..own.y
  if owner.walkSignature~=signature then owner.walkSignature=signature;owner.walkIndex=1 end
  -- Rotate over candidates: two bounded searches per cycle must not starve a reachable third side.
  local best
  for _=1,math.min(2,#choices) do
    local index=((owner.walkIndex or 1)-1)%#choices+1
    owner.walkIndex=index+1
    local choice=choices[index]
    local path=movement.findPath(own,choice.pos,12,{precision=0})
    if path and #path>0 and movement.pathSafe(own,path) then
      if not best or #path< #best then best=path end
    end
  end
  if best then
    local steps={};local from={x=own.x,y=own.y,z=own.z}
    for _,direction in ipairs(best)do
      local to=movement.destination(from,direction)
      if not to or equal(to,excluded)or equal(to,target)then return nil end
      steps[#steps+1]={from=from,to=to,direction=direction};from=to
    end
    owner.walkPlan={target={x=target.x,y=target.y,z=target.z},excluded={x=excluded.x,y=excluded.y,z=excluded.z},range=range,steps=steps}
    return steps[1].direction,steps[1].to
  end
end
local function retreatStep(target,excluded)
  local own=player and player:getPosition()
  local movement=TargetBot and TargetBot.Movement
  if not own or distance(own,target)~=1 or not movement or not movement.pathSafe then return end
  local best
  for i,offset in ipairs(directions)do
    local to={x=own.x+offset[1],y=own.y+offset[2],z=own.z}
    local t=nativeTile(to)
    if distance(to,target)==2 and not equal(to,excluded)and t and t.safe and t.walkable and not t.hard
      and not t.other and not t.selected and not t.field and not t.wall and t.trash==0
      and movement.pathSafe(own,{i-1})then
      local score=(i<=4 and 100 or 0)+offset[1]*(own.x-target.x)+offset[2]*(own.y-target.y)
      if not best or score>best.score then best={direction=i-1,to=to,score=score}end
    end
  end
  if best then return best.direction,best.to end
end
local tick,refreshMarkers,wake,armItemWake
-- Session-only, cooperative item turns. Never disable HealBot or intercept
-- the client's global item functions. Spells do not enter this coordinator.
local ITEM_TURN_AFTER=300
local ITEM_TURN_LENGTH=150
local itemTurn={reservedUntil=0,foreignUntil=0,serial=0,stats={deferred=0,requests=0,urgent=0,earlyConfirmed=0}}
local function itemSpacing()
  local ping=g_game.getPing and tonumber(g_game.getPing())or 0
  return math.max(140,math.min(300,(ping or 0)*2+40))
end
local function confirmedItemSpacing()
  local ping=g_game.getPing and tonumber(g_game.getPing())or 0
  return math.max(80,math.min(180,(ping or 0)+20))
end
local function fleeJob()
  local f=CaveBot and CaveBot.Flee
  return f and f.getItemJob and f.getItemJob()or nil
end
local function syncItemTurn()
  local n=time()
  if itemTurn.checkedAt and n<itemTurn.checkedAt then
    itemTurn.reservedUntil=0;itemTurn.foreignUntil=0;itemTurn.waitSince=nil
    itemTurn.dangerUntil=nil;itemTurn.healthAt=nil;itemTurn.health=nil
    itemTurn.healthPeak=nil;itemTurn.healthWindowAt=nil;owner.healUntil=0
    itemTurn.proof=nil;itemTurn.earlyProtection=nil
    itemTurn.demandAt=nil;itemTurn.yieldUntil=nil;itemTurn.granted=nil;itemTurn.emitters=nil;itemTurn.selectedSource=nil
  end
  itemTurn.checkedAt=n
  local job=fleeJob()or owner.engine and owner.engine.job
  local number=job and job.number
  if itemTurn.job~=number then
    itemTurn.job=number;itemTurn.waitSince=nil;itemTurn.reservedUntil=0;itemTurn.proof=nil;itemTurn.earlyProtection=nil
    itemTurn.demandAt=nil;itemTurn.yieldUntil=nil;itemTurn.granted=nil;itemTurn.emitters=nil;itemTurn.selectedSource=nil
  end
  return n,job
end
local function readPercent(method,fallback)
  local ok,value=pcall(function()
    if player and type(player[method])=='function'then return player[method](player)end
    if type(fallback)=='function'then return fallback()end
  end)
  value=ok and tonumber(value)or nil
  if value and value>=0 and value<=100 then return value end
end
local function sampleHealth(value)
  local n=syncItemTurn();value=tonumber(value)
  if not value or value<0 or value>100 then return end
  if not itemTurn.healthWindowAt or n-itemTurn.healthWindowAt>500 then
    itemTurn.healthWindowAt=n;itemTurn.healthPeak=value
  end
  itemTurn.healthPeak=math.max(itemTurn.healthPeak or value,value)
  local recentDrop=itemTurn.health and itemTurn.healthAt and n-itemTurn.healthAt<=500 and itemTurn.health-value or 0
  if math.max(recentDrop,itemTurn.healthPeak-value)>=10 and value<=85 then
    itemTurn.dangerUntil=n+600
  end
  itemTurn.health=value;itemTurn.healthAt=n
end
local function healingUrgent()
  local hp=readPercent('getHealthPercent',hppercent)
  sampleHealth(hp)
  local mp=readPercent('getManaPercent',manapercent)
  -- Unreadable health fails open for healing. Low mana also protects the
  -- resource used by healing spells/mana shield, regardless of item ID.
  if not hp then return true,'Vida no disponible',hp,mp end
  if hp<=60 then return true,'Vida <=60%',hp,mp end
  if mp and mp<=20 then return true,'Mana <=20%',hp,mp end
  if (itemTurn.dangerUntil or 0)>time()then return true,'Caida rapida de vida',hp,mp end
  return false,'Rutinario',hp,mp
end
local function coordinatingItems()
  if not valid()then return false end
  local fleeing=fleeJob()
  if not fleeing and(not config.enabled or not owner.engine or not owner.engine.job)then return false end
  if not fleeing and CaveBot and CaveBot.Flee and CaveBot.Flee.blocksCombat()then return false end
  if HelperPause and HelperPause.isPaused()then return false end
  local movement=TargetBot and TargetBot.Movement
  return not(movement and movement.isManual and movement.isManual(time(),true))
end
local function observeItemConsumption()
  local n,job=syncItemTurn();local proof=itemTurn.proof
  local protection=itemTurn.earlyProtection
  if protection then
    if not job or protection.serial~=itemTurn.serial or n>=protection.untilAt then itemTurn.earlyProtection=nil
    elseif healingUrgent()then
      itemTurn.foreignUntil=math.max(itemTurn.foreignUntil,protection.untilAt);itemTurn.earlyProtection=nil
    end
  end
  if not proof then return end
  if not job or job.number~=proof.job or proof.serial~=itemTurn.serial or n>=itemTurn.foreignUntil
    or healingUrgent()then itemTurn.proof=nil;return end
  local counter=vBot and vBot.ItemCounter
  local ok,used=pcall(function()return counter and counter.getUsed and counter.getUsed(proof.id)end)
  used=ok and tonumber(used)or nil
  -- A request, visible-stack change or newly discovered inventory count is
  -- insufficient: only the existing consumption counter can open this slot.
  if used and used%1==0 and used>proof.used then
    local untilAt=math.max(n,proof.notBefore)
    local saved=math.max(0,itemTurn.foreignUntil-untilAt)
    itemTurn.earlyProtection={serial=proof.serial,untilAt=itemTurn.foreignUntil}
    itemTurn.foreignUntil=math.min(itemTurn.foreignUntil,untilAt)
    itemTurn.stats.earlyConfirmed=itemTurn.stats.earlyConfirmed+1
    itemTurn.lastSavedMs=saved;itemTurn.proof=nil
  end
end
local function conflictingItemPending()
  local f=CaveBot and CaveBot.Flee
  if fleeJob()then return f.itemPending and f.itemPending()or nil end
  local pending=owner.engine and owner.engine.pending
  return pending and pending.action~='walk' and pending.action or nil
end
local function cleanupFollowup(action,n)
  if action~='push'then return false end
  local e=owner.engine;local job=e and e.job;local r=e and e.attempts[#e.attempts]
  local who=job and creature(job.id)
  local target=who and who:getPosition()
  return job and r and r.job==job.number and r.target==job.id and equal(r.from,target)
    and(r.action=='fire'or r.action=='disintegrate'or r.action=='destroy')
    and(r.result=='observed'or r.result=='paired move probe'or r.result=='paired fire move probe')
    and r.observedAt and n>=r.observedAt and n-r.observedAt<=100
    and(equal(r.to,target)or job.route and equal(r.to,job.route[1]))
end
local function nextEmitter(n)
  local selected
  for source,entry in pairs(itemTurn.emitters or{})do
    if n<entry.at or n-entry.at>1000 then itemTurn.emitters[source]=nil
    elseif not selected or entry.since<selected.entry.since or entry.since==selected.entry.since and entry.order<selected.entry.order then
      selected={source=source,entry=entry}
    end
  end
  return selected
end
local function requestEmitter(source,n)
  itemTurn.emitters=itemTurn.emitters or{}
  nextEmitter(n)
  local entry=itemTurn.emitters[source]
  if not entry then
    local count=0;for _ in pairs(itemTurn.emitters)do count=count+1 end
    if count>=16 then return false end
    itemTurn.emitterOrder=(itemTurn.emitterOrder or 0)+1
    entry={since=n,at=n,order=itemTurn.emitterOrder};itemTurn.emitters[source]=entry
  end
  entry.at=n
  local selected=nextEmitter(n)
  itemTurn.demandAt=selected and selected.entry.at
  itemTurn.waitSince=selected and selected.entry.since
  return true
end
local function offerHealTurn(n)
  if itemTurn.yieldUntil and n>=itemTurn.yieldUntil then
    local entry=itemTurn.emitters and itemTurn.emitters[itemTurn.selectedSource]
    if entry then entry.since=n end
    itemTurn.yieldUntil=nil;itemTurn.waitSince=n
  end
  local selected=nextEmitter(n)
  itemTurn.selectedSource=selected and selected.source
  itemTurn.demandAt=selected and selected.entry.at
  itemTurn.waitSince=selected and selected.entry.since
  if not itemTurn.demandAt or n<itemTurn.demandAt or n-itemTurn.demandAt>1000 then
    itemTurn.yieldUntil=nil;return false
  end
  if itemTurn.yieldUntil then return true end
  if not itemTurn.waitSince or n-itemTurn.waitSince<ITEM_TURN_AFTER then return false end
  itemTurn.yieldUntil=n+ITEM_TURN_LENGTH
  return true
end
local function actionReady(action,pairedFlee)
  local n=syncItemTurn()
  observeItemConsumption()
  if action~='walk'and n<itemTurn.foreignUntil then
    if armItemWake then armItemWake()end
    return false,'Espacio tras pocion/objeto'
  end
  if action~='walk'and not pairedFlee and not cleanupFollowup(action,n)and offerHealTurn(n)then
    if armItemWake then armItemWake()end
    return false,'Turno de objeto entre intentos'
  end
  return true
end
local function pushRequest(action,fn,...)
  owner.pushDispatch=(owner.pushDispatch or 0)+1
  local ok,value=pcall(fn,...)
  owner.pushDispatch=owner.pushDispatch-1
  if not ok then error(value)end
  if value~=false then
    local n=syncItemTurn()
    itemTurn.reservedUntil=math.max(itemTurn.reservedUntil,n+itemSpacing())
  end
  return value
end
local function noteItemRequest(id,source,urgent)
  if not valid()then return end
  local n=syncItemTurn()
  -- Native requests are distinct, even in the same millisecond. Only the
  -- additional HealBot notification merges with its native callback.
  if source=='Objeto externo'or itemTurn.lastAt~=n or itemTurn.lastId~=id then
    itemTurn.overlap=n<itemTurn.foreignUntil
    itemTurn.serial=itemTurn.serial+1;itemTurn.proof=nil;itemTurn.earlyProtection=nil
    itemTurn.stats.requests=itemTurn.stats.requests+1
  end
  itemTurn.lastAt=n;itemTurn.lastId=id;itemTurn.lastSource=source
  itemTurn.foreignUntil=math.max(itemTurn.foreignUntil,n+itemSpacing())
  itemTurn.waitSince=nil
  itemTurn.demandAt=nil;itemTurn.yieldUntil=nil
  if itemTurn.emitters then itemTurn.emitters[source]=nil end
  itemTurn.selectedSource=nil
  if urgent then
    itemTurn.proof=nil
    itemTurn.stats.urgent=itemTurn.stats.urgent+1
    owner.healUntil=math.max(owner.healUntil or 0,itemTurn.foreignUntil)
  end
  if armItemWake then armItemWake()end
  if wake then wake()end
end
local runes={fire='pushMaxRuneId',destroy='destroyFieldRuneId',disintegrate='disintegrateRuneId',wall='finalMwallRuneId'}
local function runeReady(action,to)
  local ready,reason=actionReady(action)
  if not ready then return false,reason end
  if action=='fire' and type(isInPz)=='function'and isInPz()then return false,'Fire Field no disponible en PZ',true end
  local n=time()
  if n<owner.runeUntil then return false,'Esperando cooldown de runa' end
  local id=tonumber(config[runes[action]]) or 0
  if id<=0 then return false,'Configura la runa',true end
  local own=player and player:getPosition()
  local limit=action=='disintegrate' and 1 or action=='destroy' and 5 or 7
  if distance(own,to)>limit then return false,'Fuera de alcance de runa' end
  local tile=g_map.getTile(to)
  if not tile or tile.canShoot and tile:canShoot()==false then return false,'Sin linea de tiro',action=='fire' end
  if player and type(player.getInventoryCount)=='function' then
    local ok,count=pcall(player.getInventoryCount,player,id,0)
    -- Some clients count only equipped items/open containers until a server
    -- cache arrives. Zero cannot veto a bounded inventory-by-ID request.
    if ok and tonumber(count) and count<=0 and type(g_game.useInventoryItemWith)~='function' then
      return false,'No hay runas disponibles',true
    end
  end
  return true
end
local function send(action,to,id,extra)
  if CaveBot and CaveBot.Flee and CaveBot.Flee.blocksCombat()then return false end
  if action=='push' then
    local who=playerTarget(creature(id))
    if not who then return false,'Jugador no disponible' end
    local from,own=who:getPosition(),player and player:getPosition()
    local range=extra.distancePush and 5 or 1
    if extra.from and not equal(from,extra.from) or distance(from,to)~=1
      or distance(own,from)>range or equal(own,to) then return false,'Posicion o alcance cambiaron' end
    local source,dest=nativeTile(from,id),nativeTile(to,id)
    if not source or not dest then return false,'Origen o destino sin suelo visible' end
    if not source.safe or not dest.safe then return false,'Piso inseguro o escalera' end
    if source.hard or dest.hard then return false,'Pared u objeto bloqueante' end
    if source.other or dest.other or dest.selected then return false,'Otro actor ocupa el paso' end
    if source.field and not(source.fire and source.field==extra.fireSourceField)or dest.field then
      return false,'Field pendiente de limpieza'
    end
    if not dest.walkable then return false,'Destino no caminable' end
    -- g_game.move is a native movement request, not a projectile. Keep rune
    -- line-of-sight checks in runeReady, without rejecting this request locally.
    return pushRequest('push',g_game.move,who,to,1)
  elseif action=='walk' then
    if player.isWalking and player:isWalking() then return false,'Paso propio en curso','busy' end
    local own=player and player:getPosition()
    local movement=TargetBot and TargetBot.Movement
    local expected=movement and movement.destination and movement.destination(own,extra.direction)
    local t=nativeTile(to,id)
    local who=extra.retreat and playerTarget(creature(id))or nil
    if not equal(expected,to)then return false,'Posicion propia cambio antes del paso' end
    if not t then return false,'Paso sin suelo visible' end
    if not t.safe then return false,'Paso inseguro o escalera' end
    if not t.walkable or t.hard then return false,'Paso con pared u objeto bloqueante' end
    if t.other or t.selected then return false,'Paso ocupado por un actor' end
    if t.field then return false,'Paso con field' end
    if extra.retreat and(not equal(own,extra.own)or not who or not equal(who:getPosition(),extra.targetFrom))then
      return false,'Contexto de retroceso cambio'
    end
    local sent=safeBotWalk(extra.direction)
    if sent==false then return false,'Cliente rechazo caminar' end
    return sent
  end
  local rune=tonumber(config[runes[action]])
  local tile=g_map.getTile(to)
  local target=tile and tile:getGround()
  if action=='fire' then
    target=playerTarget(creature(id))
    if not target or not equal(target:getPosition(),to) then return false end
  elseif tile and action=='destroy' then
    for _,item in ipairs(tile:getItems() or {}) do
      if isField(item) then target=item;break end
    end
  elseif tile and action=='disintegrate'then
    local items=tile:getItems()or{}
    for i=#items,1,-1 do
      local item=items[i]
      if item~=target and type(item.isNotMoveable)=='function'and not item:isNotMoveable()
        and not(item.isGround and item:isGround())and not(item.isGroundBorder and item:isGroundBorder())then target=item;break end
    end
  end
  if not target or not rune then return false end
  if rune==3188 and action~='fire'then return false end -- Do not accept Fire Field in a cleanup slot.
  local function requested(value)
    owner.runeUntil=math.max(owner.runeUntil,time()+1000)
    local pending=owner.engine and owner.engine.pending
    if (action=='disintegrate'or action=='fire')and pending then
      schedule(40,function()
        if valid()and owner.engine.pending==pending then tick()end
      end)
    end
    return value
  end
  if type(g_game.useInventoryItemWith)=='function' then
    local ok,value=pcall(pushRequest,action,g_game.useInventoryItemWith,rune,target,0)
    if ok and value~=false then return requested(value)end
  end
  if type(findItem)=='function' and type(g_game.useWith)=='function' then
    local item=findItem(rune)
    if item then
      local value=pushRequest(action,g_game.useWith,item,target,0)
      if value~=false then return requested(value)end
      return false
    end
  end
  return false
end
local engineConfig=setmetatable({allowFire=true,pairedCleanup=true,preferDistance=true,distanceRange=5,
  distanceCleanup=true,retreatOnSlow=true,avoidFailedPushEdges=true,adaptivePushAck=true,revision='R139-Sabuezo'},{__index=config})
local engine=RinoPushMaxEngine.new({
  time=time,
  ping=function()return g_game.getPing and g_game.getPing() or 0 end,
  player=function()
    if not player or player.isDead and player:isDead() or player.getHealthPercent and player:getHealthPercent()<=0 then return nil end
    return player:getPosition()
  end,
  target=function(id)
    local who=playerTarget(creature(id))
    if not who then return nil end
    return who:getPosition()
  end,
  attacking=attacked,tile=nativeTile,walkStep=walkStep,retreatStep=retreatStep,runeReady=runeReady,send=send,actionReady=actionReady,
  moving=function()return player and player.isWalking and player:isWalking()end,
  walkFailed=walkFailed,
  responseBusy=function(sentAt)return itemTurn.lastAt and itemTurn.lastAt>=sentAt and itemTurn.lastAt<=time()end,
  report=function(p,result)
    local duration=result=='requested' and '' or ' | '..tostring(time()-p.at)..' ms'
    if p.record.playerDistance then duration=duration..' | distancia='..p.record.playerDistance..' SQM'end
    if p.record.responseWindowMs then duration=duration..' | plazo='..p.record.responseWindowMs..' ms ('..(p.record.adaptiveResponse and 'adaptable'or 'respaldo')..')'end
    if p.record.spellAfterRequest then duration=duration..' | spell tras solicitud='..p.record.spellAfterRequest end
    local where=p.from.x..','..p.from.y..','..p.from.z..' -> '..p.to.x..','..p.to.y..','..p.to.z
    consoleLog((result=='timeout' or result=='request error' or result=='request rejected')and 'warn' or 'action',
      p.action..' / '..result,where..duration..(p.record.error and ' | '..p.record.error or '')
      ..(p.record.reason and ' | '..p.record.reason or ''))
  end,
  manual=function()
    local movement=TargetBot and TargetBot.Movement
    return movement and movement.isManual and movement.isManual(time(),true) or false
  end,
  urgent=function()return(owner.healUntil or 0)>time()end,
  paused=function()return HelperPause and HelperPause.isPaused()or false end,
  runeObserved=function(_,sentAt)
    -- Only a requested/observed Push Max rune advances this fallback. A spell
    -- group event cannot identify a rune and must not extend or clear it.
    owner.runeUntil=math.max(owner.runeUntil,sentAt+2000)
  end,
  state=function(text,detail)
    if valid() then
      if not pushWindow:isDestroyed() then
        pushWindow.delayText:setText(text)
        tooltip(pushWindow.delayText,text..'\n'..detail..'\nReintento: '..config.pushDelay..' ms')
      end
      if RinoLab and type(RinoLab.state)=='function'and (not RinoLab.valid or RinoLab.valid())then RinoLab.state('Push Max',text,detail)
      else consoleLog('state',text,detail)end
      if refreshMarkers then refreshMarkers()end
    end
  end
},engineConfig)
owner.engine=engine
local function clearMarkers()
  for _,mark in ipairs(owner.markers or{})do
    pcall(function()
      local tile=g_map.getTile(mark.pos)or mark.tile
      if tile and tile:getText()==mark.text then tile:setText(mark.before)end
    end)
  end
  owner.markers={};owner.markerSignature=nil
end
owner.clearMarkers=clearMarkers
refreshMarkers=function()
  local job=engine.job
  if not valid()or not job then clearMarkers();return end
  local wanted={};local target=creature(job.id)
  local from=target and target:getPosition()
  local route=job.route
  if from and route and not equal(from,job.dest)then
    wanted[#wanted+1]={pos=from,text='PUSH1'}
    for i,p in ipairs(route)do
      if equal(p,job.dest)or #wanted>=31 then break end
      wanted[#wanted+1]={pos=p,text='PUSH'..(i+1)}
    end
  end
  wanted[#wanted+1]={pos=job.dest,text='DEST'}
  local signature=tostring(job.number)
  for _,mark in ipairs(wanted)do signature=signature..'|'..mark.pos.x..','..mark.pos.y..','..mark.pos.z..':'..mark.text end
  if owner.markerSignature==signature then return end
  clearMarkers();owner.markerSignature=signature
  for _,mark in ipairs(wanted)do
    local tile=g_map.getTile(mark.pos)
    if tile and type(tile.getText)=='function'and type(tile.setText)=='function'then
      local before=tile:getText()or''
      local text=before==''and mark.text or before..'\n'..mark.text
      tile:setText(text)
      owner.markers[#owner.markers+1]={pos={x=mark.pos.x,y=mark.pos.y,z=mark.pos.z},text=text,before=before,tile=tile}
    end
  end
end
local executing=false
tick=function()
  if not valid() or not config.enabled or executing then return end
  syncItemTurn()
  observeItemConsumption()
  if itemTurn.lastAt and itemTurn.loggedSerial~=itemTurn.serial and engine.job and time()>=itemTurn.lastAt
    and time()-itemTurn.lastAt<=300 then
    itemTurn.loggedSerial=itemTurn.serial
    local d=itemTurn.lastDecision
    consoleLog('info','Item durante Push Max','id='..tostring(itemTurn.lastId)..' | origen='..tostring(itemTurn.lastSource)
      ..' | motivo='..tostring(itemTurn.lastSource=='HealBot'and itemTurn.lastReason or itemTurn.lastSource~='Objeto externo'and itemTurn.lastCooperativeReason or 'Uso externo observado')
      ..' | pendiente='..tostring(engine.pending and engine.pending.action or 'ninguno')
      ..(d and d.at==itemTurn.lastAt and ' | HP='..tostring(d.hp)..'% MP='..tostring(d.mp)..'%'or ''))
  end
  if armItemWake then armItemWake()end
  if CaveBot and CaveBot.Flee and CaveBot.Flee.blocksCombat()then engine.cancel('Prioridad Huida PvP');refreshMarkers();return end
  executing=true
  local ok,err=pcall(engine.tick)
  executing=false
  if not ok then
    engine.cancel('Error en Push Max')
    if warn then warn('Push Max: '..tostring(err)) end
  end
  refreshMarkers()
end
wake=function()
  if not valid() or owner.wakePending then return end
  owner.wakePending=true
  schedule(0,function()
    owner.wakePending=false
    if valid()then
      tick()
      local f=CaveBot and CaveBot.Flee
      if fleeJob()and f.wake then f.wake()end
    end
  end)
end
-- One logical deadline wake per owner; extensions reuse it and re-arm only
-- after it fires. The 50 ms observer remains a recovery path, not a busy loop.
armItemWake=function()
  if not valid()or not(fleeJob()or config.enabled and engine.job)or owner.itemWakeAt then return end
  local n=syncItemTurn()
  local due
  if fleeJob()and n<itemTurn.reservedUntil then due=itemTurn.reservedUntil end
  if n<itemTurn.foreignUntil then
    due=math.min(due or itemTurn.foreignUntil,itemTurn.foreignUntil)
    local firstCheck=(itemTurn.lastAt or n)+confirmedItemSpacing()
    if n<firstCheck then due=math.min(due,firstCheck)end
  end
  if itemTurn.yieldUntil and n<itemTurn.yieldUntil then due=math.min(due or itemTurn.yieldUntil,itemTurn.yieldUntil)end
  if not due then return end
  owner.itemWakeAt=due
  schedule(math.max(1,math.ceil(due-n)),function()
    owner.itemWakeAt=nil
    if valid()then
      if fleeJob()then local f=CaveBot.Flee;if f.wake then f.wake()end
      elseif config.enabled and engine.job then tick()end
    end
  end)
end
local api={}
api.experimentalDistanceFire=true
PushMax=api
function api.isOn()return valid() and config.enabled==true end
function api.setOn(value)
  if not valid() then return end
  config.enabled=value~=false;ui.title:setOn(config.enabled)
  if not config.enabled then engine.cancel('Push Max apagado') end
end
function api.setOff()api.setOn(false)end
function api.toggle()api.setOn(not api.isOn())end
function api.cancel(reason)if valid()then engine.cancel(reason or 'Cancelado')end end
function api.start(id,p)
  if not api.isOn() then return false end
  if CaveBot and CaveBot.Flee and CaveBot.Flee.blocksCombat()then return false end
  if not owner.selection or owner.selection.id~=id then
    if not remember(creature(id),'api') then return false end
  end
  local started=engine.start(id,p);if started then wake()end;return started
end
function api.ownsMovement()
  return valid()and config.enabled and engine.job~=nil
    and not(CaveBot and CaveBot.Flee and CaveBot.Flee.blocksCombat())
end
function api.noteHealing(id)
  if not valid()then return false end
  local n=syncItemTurn()
  -- Legacy callers did not distinguish speech from an item. Honor this hint
  -- only inside an already observed item's margin; never add a spell delay.
  if not itemTurn.lastAt or n<itemTurn.lastAt or n-itemTurn.lastAt>100 or n>=itemTurn.foreignUntil
    or not itemTurn.lastId or itemTurn.lastId<=100 or id~=nil and tonumber(id)~=itemTurn.lastId
    or not healingUrgent()then return false end
  owner.healUntil=math.max(owner.healUntil or 0,itemTurn.foreignUntil)
  return true
end
function api.isCoordinatingItems()return coordinatingItems()end
function api.fleeItemReady(action,paired)
  if not valid()or not fleeJob()then return true end
  if action~='push'and action~='destroy'and action~='disintegrate'and action~='monster'then return false,'Accion de huida no permitida'end
  if not paired and time()<itemTurn.reservedUntil then armItemWake();return false,'Espacio tras runa de huida'end
  return actionReady(action,paired==true and action=='push')
end
function api.performFleeItem(action,fn,...)
  if not valid()or not fleeJob()or type(fn)~='function'then return false end
  if action~='destroy'and action~='disintegrate'and action~='monster'then return false end
  return pushRequest(action,fn,...)
end
function api.fleeItemState()syncItemTurn();return itemTurn.serial,itemTurn.lastAt,itemTurn.foreignUntil end
local function fleeFireBlocked(source,id)
  local f=CaveBot and CaveBot.Flee
  return f and f.blocksCombat()and(source=='Fire Bomb'or tonumber(id)==3188 or tonumber(id)==3192)
end
function api.allowScriptItem(source,id,healing)
  if fleeFireBlocked(source,id)then return false,'Huida sin Fire Field'end
  if not coordinatingItems()then return true end
  source=tostring(source or 'Script'):sub(1,40)
  local n=syncItemTurn()
  local urgent,reason,hp,mp=healingUrgent()
  urgent=healing==true and urgent or healing=='urgent'or healing=='protection'
  local pending=conflictingItemPending()
  local function decision(allowed,why)
    itemTurn.lastDecision={at=n,id=id,source=source,allowed=allowed,reason=why,hp=hp,mp=mp,pending=pending}
    if allowed then itemTurn.granted={id=id,source=source,at=n,urgent=urgent,reason=why,hp=hp,mp=mp}end
    return allowed
  end
  if urgent then return decision(true,healing=='urgent'and 'Curacion urgente de aliado'or healing=='protection'and 'Proteccion urgente de escudo'or reason)end
  local registered=requestEmitter(source,n)
  local selected=nextEmitter(n)
  if registered and selected and selected.source==source and not pending and n>=itemTurn.foreignUntil
    and(n>=itemTurn.reservedUntil or n-itemTurn.waitSince>=ITEM_TURN_AFTER)then
    return decision(true,'Hueco entre intentos')
  end
  itemTurn.stats.deferred=itemTurn.stats.deferred+1
  if wake then wake()end
  return decision(false,pending and 'Esperando confirmacion de '..pending or 'Turno protegido del push/objeto')
end
function api.allowHealItem(id)return api.allowScriptItem('HealBot',id,true)end
-- Explicit cooperation by the calling script. Never wrap global client APIs
-- or retain callbacks/targets to execute a stale action after the turn changes.
function api.performItem(source,id,healing,fn,...)
  if type(fn)~='function'then return false end
  if type(id)~='number'and id and type(id.getId)=='function'then
    local ok,value=pcall(id.getId,id);id=ok and value or nil
  end
  if fleeFireBlocked(source,id)then return false,'Push Max: turno pendiente'end
  if not coordinatingItems()then return fn(...)end
  source=tostring(source or 'Script'):sub(1,40)
  if not api.allowScriptItem(source,id,healing)then return false,'Push Max: turno pendiente'end
  local granted=itemTurn.granted
  local previous=owner.itemDispatch
  if previous and not(granted and granted.urgent)then return false,'Push Max: turno pendiente'end
  local context={source=source,id=id,urgent=granted and granted.urgent==true,reason=granted and granted.reason}
  owner.itemDispatch=context
  local ok,value,detail=pcall(fn,...)
  owner.itemDispatch=previous
  if ok and value~=false then
    if not context.noted or itemTurn.lastSource==source then itemTurn.lastCooperativeReason=granted and granted.reason or 'Hueco entre intentos'end
    if not context.noted then noteItemRequest(id,source,context.urgent)end
  end
  if not ok then error(value)end
  return value,detail
end
function api.noteHealItem(id,before)
  if not valid()then return end
  id=tonumber(id);local urgent,reason=healingUrgent()
  local granted=itemTurn.granted
  if granted and granted.source=='HealBot'and granted.at==time()and granted.id==id and granted.urgent then urgent,reason=true,granted.reason end
  itemTurn.lastReason=reason
  noteItemRequest(id,'HealBot',urgent)
  local n,job=syncItemTurn()
  local used=type(before)=='table'and tonumber(before.used)or nil
  if job and not urgent and not itemTurn.overlap and used and used>=0 and used%1==0 then
    itemTurn.proof={id=id,used=used,serial=itemTurn.serial,job=job.number,notBefore=n+confirmedItemSpacing()}
    observeItemConsumption()
  end
end
function api.getStatus()
  local out=engine.snapshot()
  syncItemTurn()
  out.itemCoordination={routineTurnAfterMs=ITEM_TURN_AFTER,pendingItemExclusive=true,spacingMs=itemSpacing(),reservedUntil=itemTurn.reservedUntil,
    foreignUntil=itemTurn.foreignUntil,waitSince=itemTurn.waitSince,lastSource=itemTurn.lastSource,
    confirmedSpacingMs=confirmedItemSpacing(),lastSavedMs=itemTurn.lastSavedMs,turnUntil=itemTurn.yieldUntil,
    lastItemId=itemTurn.lastId,lastReason=itemTurn.lastSource=='HealBot'and itemTurn.lastReason or itemTurn.lastCooperativeReason,cooperativeEmitters=true,maxEmitters=16,spellSignalsDoNotPause=true,
    stats={deferred=itemTurn.stats.deferred,requests=itemTurn.stats.requests,urgent=itemTurn.stats.urgent,earlyConfirmed=itemTurn.stats.earlyConfirmed}}
  local waiting=0;for _ in pairs(itemTurn.emitters or{})do waiting=waiting+1 end
  out.itemCoordination.waitingEmitters=waiting;out.itemCoordination.selectedSource=itemTurn.selectedSource
  if itemTurn.lastDecision then
    out.itemCoordination.lastDecision={};for k,v in pairs(itemTurn.lastDecision)do out.itemCoordination.lastDecision[k]=v end
  end
  out.manualTraceAvailable=owner.manualTraceAvailable==true
  if owner.manualSample then
    out.manualDrag={}
    for k,v in pairs(owner.manualSample)do
      out.manualDrag[k]=type(v)=='table' and {x=v.x,y=v.y,z=v.z} or v
    end
  end
  if owner.selection then
    local who,reason=playerTarget(creature(owner.selection.id))
    out.selection={id=owner.selection.id,name=owner.selection.name,at=owner.selection.at,source=owner.selection.source,
      available=who~=nil,reason=reason}
  end
  if owner.input then
    out.input={key=owner.input.key,at=owner.input.at,outcome=owner.input.outcome,
      source=owner.input.source,target=owner.input.target,reason=owner.input.reason}
  end
  return out
end
function api.dispose()
  clearMarkers()
  if owner.restoreManualDrop then owner.restoreManualDrop()end
  if not owner.active then return end
  owner.active=false
  if root._rinoPushMax==owner then root._rinoPushMax=nil end
  clearSelection();engine.cancel('Recarga del bot')
  if owner.observer and owner.observer.setOff then pcall(owner.observer.setOff,owner.observer) end
  if owner.window then pcall(function()
    if not owner.window:isDestroyed() then owner.window:destroy() end
  end)end
end
owner.dispose=api.dispose
-- Compare a real native drag with bot requests. Delegate the existing handler
-- exactly once; never synthesize input or resend a manual request.
local function observeManualDrag()
  local sample=owner.manualSample
  if not sample or sample.result~='pending' then return end
  local who=playerTarget(creature(sample.target));local p=who and who:getPosition()
  if p and not equal(p,sample.from) then
    sample.result=equal(p,sample.to) and 'observed' or 'moved elsewhere'
  elseif not who then sample.result='target unavailable'
  elseif time()-sample.sentAt>=2500 then sample.result='timeout' end
  if sample.result~='pending' then
    sample.observedAt=time();sample.elapsedMs=math.max(0,time()-sample.sentAt)
    consoleLog('info','Arrastre manual / '..sample.result,tostring(sample.elapsedMs)..' ms | reloj executor | bot previo pendiente='..tostring(sample.botWasPending))
  end
end
local function mapPanel()
  local interface=modules and modules.game_interface
  if interface and type(interface.getMapPanel)=='function' then
    local ok,map=pcall(interface.getMapPanel)
    if ok and (type(map)=='table' or type(map)=='userdata') then return map end
  end
end
do
  local map=mapPanel();local original=map and map.onDrop
  if type(original)=='function' and type(map.getTile)=='function' then
    local wrapped
    wrapped=function(self,widget,mousePos,...)
      local candidate
      if valid() then
        pcall(function()
          local who=playerTarget(widget and widget.currentDragThing)
          local tile=self:getTile(mousePos);local from=who and who:getPosition();local to=tile and tile:getPosition()
          if who and from and to and not equal(from,to) then
            candidate={target=who:getId(),from={x=from.x,y=from.y,z=from.z},to={x=to.x,y=to.y,z=to.z},
              sentAt=time(),result='pending',botWasPending=engine.pending~=nil}
          end
        end)
      end
      local function finish(...)
        local accepted=...
        if valid() and accepted==true and candidate then
          pcall(function()
            owner.manualSample=candidate;engine.cancel('Arrastre manual')
            consoleLog('info','Arrastre manual / accepted','Reloj executor | bot previo pendiente='..tostring(candidate.botWasPending))
            observeManualDrag()
          end)
        end
        return ...
      end
      return finish(original(self,widget,mousePos,...))
    end
    map.onDrop=wrapped
    owner.restoreManualDrop=function()
      pcall(function()
        local current=mapPanel()
        if current==map and current.onDrop==wrapped then current.onDrop=original end
      end)
    end
    owner.manualTraceAvailable=true
  end
end
ui.title:setOn(config.enabled==true)
ui.title.onClick=function()api.toggle()end
ui.push.onClick=function()if valid()then pushWindow:show();pushWindow:raise();pushWindow:focus()end end
local keyHeld=false
local rejectionText={['no-selection']='Sin jugador seleccionado', ['not-player']='El objetivo no es un jugador',
  self='No puedes empujarte', ['not-visible']='Objetivo fuera de vista', ['other-floor']='Objetivo en otro piso',
  dead='Objetivo no disponible', ['invalid-creature']='Objetivo no disponible',['identity-changed']='Identidad del jugador no coincide'}
local function reject(text,reason)
  owner.input.outcome='rejected';owner.input.reason=reason
  engine.cancel(text)
  if type(info)=='function' and (not owner.lastNoticeAt or time()<owner.lastNoticeAt or time()-owner.lastNoticeAt>=1000) then
    owner.lastNoticeAt=time();pcall(info,'Push Max: '..text)
  end
end
onKeyDown(function(key)
  if not valid() then return end
  if key=='Escape' or key=='Esc' then engine.cancel('Escape');return end
  if tostring(key):lower()~=tostring(config.pushMaxKey):lower() or keyHeld then return end
  owner.input={key=tostring(key),at=time(),outcome='received'}
  consoleLog('info','Tecla recibida: '..tostring(key))
  if RinoLab then RinoLab.dirty=true end
  if not api.isOn() then reject('Push Max apagado','disabled');return end
  if pushWindow:isVisible() and pushWindow.hotkey.isFocused and pushWindow.hotkey:isFocused() then
    owner.input.outcome='editing-shortcut';return
  end
  keyHeld=true
  local who,source,reason=resolvePlayer()
  owner.input.source=source
  local tile=getTileUnderCursor()
  if not who then reject(rejectionText[reason] or 'Objetivo no disponible',reason);return end
  owner.input.target=who:getId()
  if not tile then reject('Apunta a una casilla del mapa','no-tile');return end
  if api.start(who:getId(),tile:getPosition()) then owner.input.outcome='started'
  else reject(engine.status,'invalid-destination')end
end)
if onKeyUp then onKeyUp(function(key)
  if valid() and tostring(key):lower()==tostring(config.pushMaxKey):lower() then keyHeld=false end
end) end
owner.observer=macro(50,function()
  if not valid() then return end
  observeManualDrag()
  if keyHeld and g_keyboard and g_keyboard.isKeyPressed and not g_keyboard.isKeyPressed(config.pushMaxKey) then keyHeld=false end
  tick()
end)
onCreaturePositionChange(function(who)
  if valid() and owner.manualSample and who:getId()==owner.manualSample.target then observeManualDrag()end
  if valid() and engine.job and who:getId()==engine.job.id then wake() end
end)
onPlayerPositionChange(function()wake()end)
onAttackingCreatureChange(function(newCreature,oldCreature)
  if not valid() then return end
  if newCreature then
    local selected=remember(newCreature,'attack-event')
    if engine.job and (not selected or selected:getId()~=engine.job.id) then engine.cancel('Cambio de objetivo') end
  elseif oldCreature and not owner.selection and not owner.selectionCleared then
    -- A server attack cancellation can arrive before the push key (for example in protection).
    -- Keep only the actual selected ID, never an arbitrary spectator or a name-based replacement.
    remember(oldCreature,'last-attack-event')
  end
  wake()
end)
local function changedTile(tile,thing,added)
  if not valid() or not engine.job then return end
  local p=tile and tile.getPosition and tile:getPosition()
  if added and p and thing and type(thing.getId)=='function' and engine.pending and engine.pending.action=='fire' then
    local id=thing:getId()
    if id==2118 or id==2119 or id==2120 then engine.changed(p,'fire') end
  end
  if not p or engine.job.waitingWall and p.z==engine.job.floor or distance(p,engine.job.dest)<=2
    or engine.pending and distance(p,engine.pending.to)<=1 then
    engine.changed();wake()
  end
end
onAddThing(function(tile,thing)changedTile(tile,thing,true)end)
onRemoveThing(function(tile)changedTile(tile)end)
-- Spell speech/cooldown groups do not own the push or item/rune turns.
if onGameEnd then onGameEnd(function()if valid()then clearSelection();engine.cancel('Desconexion')end end)end
if onPlayerHealthChange then onPlayerHealthChange(function(percent)if valid()then sampleHealth(percent)end end)end
local function foreignItem(_,id)
  if valid()and(owner.pushDispatch or 0)==0 then
    local context=owner.itemDispatch
    if context then
      context.noted=true;itemTurn.lastCooperativeReason=context.reason or 'Hueco entre intentos'
      noteItemRequest(tonumber(id)or context.id,context.source,context.urgent)
    else noteItemRequest(tonumber(id),'Objeto externo',false)end
  end
end
if onUse then onUse(foreignItem)end
if onUseWith then onUseWith(foreignItem)end
local function itemResponse()
  if valid()and itemTurn.proof then wake()end
end
if onContainerUpdateItem then onContainerUpdateItem(itemResponse)end
if onTextMessage then onTextMessage(itemResponse)end
if onTextMessage then onTextMessage(function(_,text)
  if not valid()or not engine.pending or type(text)~='string'then return end
  local lower=text:lower()
  if lower:find('not possible',1,true)or lower:find('cannot move',1,true)or lower:find('cannot be moved',1,true)
    or lower:find('have to wait',1,true)or lower:find('exhaust',1,true)then
    consoleLog('warn','Mensaje durante '..engine.pending.action,text)
  end
  -- Generic "not possible" / exhaust text can belong to healing or another
  -- script. Only move-specific messages qualify as a short-lived push hint.
  if engine.pending.action=='push' and (lower:find('cannot move',1,true)or lower:find('cannot be moved',1,true)
    or lower:find('cannot push',1,true)or lower:find('not moveable',1,true)or lower:find('not movable',1,true))then
    if engine.refused('push',text)then consoleLog('warn','Posible rechazo de push',text);wake()end
  end
end)end
if type(onTalk)=='function'then onTalk(function(name,_,_,text)
  if not valid()or not engine.job or type(text)~='string'then return end
  local ok,ownName=pcall(function()return player and player:getName()end)
  if not ok or not ownName or name~=ownName then return end
  local words=text:lower():gsub('^%s+',''):gsub('%s+$','')
  local prefix=words:match('^(%a+) ')
  if not words:match('^[a-z ]+$')or not({utani=true,utamo=true,utito=true,utana=true,utura=true,
    exura=true,exana=true,exevo=true,exori=true})[prefix]then return end
  if owner.lastSpellObservedAt and time()-owner.lastSpellObservedAt<100 then return end
  owner.lastSpellObservedAt=time()
  local p=engine.pending
  local detail=words:sub(1,60)..' | pendiente='..tostring(p and p.action or 'ninguno')
  if p then
    detail=detail..' | desde solicitud='..tostring(time()-p.at)..' ms'
    p.record.spellAfterRequest=words:sub(1,60)..' +'..tostring(time()-p.at)..' ms'
  end
  consoleLog('info','Spell propio observado',detail)
end)end
consoleLog('info','Modulo cargado R139 / Sabuezo','ON='..tostring(config.enabled)..' | tecla='..tostring(config.pushMaxKey)..' | spells libres | turnos de objetos compartidos con Huida | Huida sin Fire Field | respuesta adaptable con respaldo | visual PUSH/DEST')
