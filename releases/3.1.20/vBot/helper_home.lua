-- Inicio owns presentation and one optional mount preference, never a second
-- combat executor. Reuse Helper's existing poll and game_bot's text callback.
local H=Helper
if not H or not H.valid() then return end
local Home={}
H.Home=Home
local settings=storage.helperUI
settings.home=type(settings.home)=='table' and settings.home or {}
local config=settings.home
if type(config.keepMounted)~='boolean' then config.keepMounted=false end
local card,closed,lastTick=nil,false,-math.huge
local characterName,guild,vocationText=nil,nil,nil
local nextLook,queryGuild=0,false
local lookSentAt
local nextMount,waitingMount=0,nil
local hasMount,mountStatus=nil,'Desactivada'
local sessionSummary
local hooks={}
local shared=modules and modules.game_bot
local vocations={
  [0]='Sin vocacion', [1]='Knight', [11]='Elite Knight',
  [2]='Paladin', [12]='Royal Paladin', [3]='Sorcerer', [13]='Master Sorcerer',
  [4]='Druid', [14]='Elder Druid', [5]='Monk', [15]='Exalted Monk'
}
local function clock() return tonumber(now) or os.time()*1000 end
local function currentPlayer()
  if not g_game or (g_game.isOnline and not g_game.isOnline()) then return nil end
  return g_game.getLocalPlayer and g_game.getLocalPlayer() or nil
end
local function live(w) return w and H.live(w) end
local function text(w,value)
  value=tostring(value or '')
  if live(w) and w:getText()~=value then w:setText(value) end
end
local function tip(w,value)
  if live(w) and w:getTooltip()~=value then w:setTooltip(value) end
end
local function portraitOption(widget,method,value)
  if not widget or type(widget[method])~='function' then return false end
  return pcall(widget[method],widget,value)
end
local function fitPortrait(frame,widget,variant)
  portraitOption(frame,'setClipping',true)
  if type(ApiCompat)=='table' and type(ApiCompat.applyPortraitOptions)=='function' then
    -- The settings depend on the variant (see ApiCompat.portraitVariants).
    ApiCompat.applyPortraitOptions(widget,variant)
    return
  end
  portraitOption(widget,'setClipping',true)
  -- The modern renderer treats 100 as percent of its viewport. Older
  -- UICreature implementations treat nonzero creature-size as absolute pixels;
  -- zero lets their 64px source framebuffer scale into the viewport instead.
  local scalable=type(widget.setFixedCreatureSize)=='function'
  portraitOption(widget,'setCenter',true)
  portraitOption(widget,'setCenterByBoundingBox',true)
  portraitOption(widget,'setFixedCreatureSize',false)
  portraitOption(widget,'setCreatureSize',scalable and 100 or 0)
  portraitOption(widget,'setBaseScale',false)
  portraitOption(widget,'setIgnoreDisplacementShift',false)
  portraitOption(widget,'setCreatureSmooth',true)
end
-- The way the portrait is drawn. Saved once the user picks one by clicking the portrait; until then the
-- Valkaris Next Gen client starts with the plain widget moved to the middle of the frame (8) and the others
-- with the adjusted one (1).
local function portraitVariant()
  if type(ApiCompat)~='table' or type(ApiCompat.portraitVariant)~='function' then return 1 end
  local index=tonumber(config.portraitVariant)
  if not index then index=(type(ClientDetector)=='table' and ClientDetector.id=='valkaris-ng') and 8 or 1 end
  return (ApiCompat.portraitVariant(index))
end
local function makePortraitFloor(frame)
  local floor=frame and frame.floor
  if not floor or not g_ui or type(g_ui.createWidget)~='function' then return end
  local groundId
  if g_things and type(g_things.getThingType)=='function' then
    for _,id in ipairs({430,436})do
      local ok,ground=pcall(function()
        local t=g_things.getThingType(id,0)
        return t and t:getId()==id and t:isGround()
      end)
      if ok and ground then groundId=id;break end
    end
  end
  -- The floor panel is 72x68 (the frame minus its margin): 22px tiles make a 66x66 grid, centered, with the
  -- middle tile right where the creature's center is. 24px tiles cut the bottom row.
  local tileSize,left,top=22,3,1
  for y=0,2 do for x=0,2 do
    local ok,tile=pcall(g_ui.createWidget,groundId and 'HelperHomeFloorTile' or 'HelperHomeFloorCell',floor)
    if ok and tile then
      tile:setPhantom(true);tile:setFocusable(false)
      tile:setMarginLeft(left+x*tileSize);tile:setMarginTop(top+y*tileSize)
      tile:setSize({width=tileSize,height=tileSize})
      if groundId then tile:setVirtual(true);tile:setItemId(groundId)
      else tile:setBackgroundColor((x+y)%2==0 and '#747b7d' or '#6e7577');tile:setBorderWidth(1);tile:setBorderColor('#969d9e')end
    end
  end end
end
local function trim(value) return tostring(value or ''):gsub('^%s+',''):gsub('%s+$','') end
local function reset(name)
  characterName,guild,vocationText=name,nil,nil
  nextLook,queryGuild=0,true
  lookSentAt=nil
  nextMount,waitingMount,hasMount=0,nil,nil
end

-- The look packet contains the actual guild. Player List's editable guild is
-- a classification preference, so it must not be shown as verified char data.
function Home.onText(_,message)
  if closed or not H.valid() or type(message)~='string' then return end
  local p=currentPlayer()
  if not p then return end
  local name=p:getName()
  if characterName~=name then reset(name) end
  local line=message:gsub('[\r\n]',' ')
  if line:find('You see yourself',1,true) then
    guild=trim(line:match('%s[Oo]f the (.-),%s*[Ww]hich has%s+%d+%s+members?') or
      line:match('%s[Oo]f (.-),%s*[Ww]hich has%s+%d+%s+members?') or
      line:match('[Mm]ember of the ([^%.]+)%.') or line:match('[Mm]ember of ([^%.]+)%.'))
    vocationText=trim(line:match('[Yy]ou are an? ([^%.]+)%.') or line:match('[Yy]ou are ([^%.]+)%.'))
    queryGuild=false;lookSentAt=nil
  end
  if config.keepMounted and waitingMount then
    local lower=line:lower()
    if lower:find('do not have any mount',1,true) or lower:find("don't have any mount",1,true) or
        lower:find('no mount selected',1,true) or lower:find('select a mount',1,true) then
      hasMount=false;waitingMount=nil
      mountStatus='Elige una montura en el cliente'
    end
  end
end
if type(onTextMessage)=='function' then onTextMessage(Home.onText) end

function Home.cleanup()
  if closed then return end
  closed=true;card=nil
  for event,callback in pairs(hooks) do
    local listeners=g_game[event]
    if listeners==callback then g_game[event]=nil
    elseif type(listeners)=='table' then
      local remaining={}
      for _,fn in ipairs(listeners) do if fn~=callback then remaining[#remaining+1]=fn end end
      if #remaining==1 then g_game[event]=remaining[1]
      elseif #remaining==0 then g_game[event]=nil
      else g_game[event]=remaining end
    end
  end
  if shared and shared.rinoHomeCleanup==Home.cleanup then shared.rinoHomeCleanup=nil end
end
if shared and type(shared.rinoHomeCleanup)=='function' then shared.rinoHomeCleanup() end
if shared then shared.rinoHomeCleanup=Home.cleanup end
local function listen(event,callback)
  local listeners=g_game and g_game[event]
  if listeners==nil then g_game[event]=callback
  elseif type(listeners)=='function' then g_game[event]={listeners,callback}
  elseif type(listeners)=='table' then
    local list={};for _,fn in ipairs(listeners) do list[#list+1]=fn end
    list[#list+1]=callback;g_game[event]=list
  else return end
  hooks[event]=callback
end
listen('onOpenOutfitWindow',function(_,_,mounts)
  if closed or not H.valid() or type(mounts)~='table' then return end
  hasMount=false
  for _,entry in pairs(mounts) do
    if type(entry)=='table' and (tonumber(entry[1]) or 0)>0 then hasMount=true;break end
  end
  nextMount,waitingMount=0,nil
end)
listen('onGameStart',function() if not closed then reset(nil);lastTick=-math.huge end end)

local function portraitTip()
  if not live(card) or not live(card.frame) then return end
  local total=type(ApiCompat)=='table' and type(ApiCompat.portraitVariants)=='table' and #ApiCompat.portraitVariants or 1
  local index,info=1,nil
  if total>1 then index,info=ApiCompat.portraitVariant(portraitVariant()) end
  tip(card.frame,total>1 and ('Retrato: forma '..index..' de '..total..' ('..tostring(info and info.name)..').\nSi no ves a tu personaje, haz clic para probar otra forma de pintarlo.\nEl detalle queda en _diagnostics/portrait.txt.') or '')
end
local function reportPortrait(info)
  if type(ApiCompat)~='table' or type(ApiCompat.portraitReport)~='function' or not live(card) then return end
  if type(RinoConsole)=='table' and type(RinoConsole.log)=='function' and type(ApiCompat.describePortrait)=='function' then
    pcall(RinoConsole.log,'info','Inicio',ApiCompat.describePortrait(info))
  end
  if type(ApiCompat.writeDiagnostic)=='function' then
    local ok,text=pcall(ApiCompat.portraitReport,info,card.outfit,card.frame)
    if ok and text then pcall(ApiCompat.writeDiagnostic,'portrait.txt',text) end
  end
end
-- A UICreature cannot go back to the client's defaults, so a new variant means a new widget.
local function rebuildPortrait(variant)
  if not live(card) or not live(card.frame) or type(ApiCompat)~='table' or type(ApiCompat.newPortraitWidget)~='function' then return false end
  local old=card.outfit
  local fresh=ApiCompat.newPortraitWidget(card.frame,variant)
  if not fresh then return false end
  if old then pcall(function() old:destroy() end) end
  pcall(function() fresh:setId('outfit') end)
  card.outfit=fresh
  portraitOption(fresh,'setAnimate',false)
  portraitOption(fresh,'setDirection',2) -- South, only the preview; never turn the char.
  fitPortrait(card.frame,fresh,variant)
  return true
end
local function cyclePortrait()
  if closed or not live(card) or type(ApiCompat)~='table' or type(ApiCompat.portraitVariants)~='table' then return end
  local index=portraitVariant()%#ApiCompat.portraitVariants+1
  if not rebuildPortrait(index) then return end
  config.portraitVariant=index
  portraitTip()
  lastTick=-math.huge;Home.tick()
end

function Home.render(parent,create)
  if closed then return end
  card=create('HelperHomeCard',parent)
  for _,id in ipairs({'frame','name','vocation','guild','mount','mountStatus'})do card[id]=card.identity[id]end
  card.outfit=card.frame.outfit
  card.level=card.identity.levelBadge.value
  if RinoSkin then
    RinoSkin.icon(card.identity.guildIcon,'shield')
    for _,key in ipairs({'time','deaths','xp'})do RinoSkin.icon(card.stats[key].glyph,key)end
    RinoSkin.icon(card.route.glyph,'route')
  end
  text(card.stats.time.caption,'Tiempo');text(card.stats.deaths.caption,'Muertes');text(card.stats.xp.caption,'Niveles')
  local function fitStats(w)
    local width=math.max(1,math.floor((w:getWidth()-12)/3))
    if w.homeCellWidth==width then return end
    local layout=w:getLayout()
    if layout then layout:setCellSize({width=width,height=48});w.homeCellWidth=width end
  end
  card.stats.onGeometryChange=fitStats;fitStats(card.stats)
  card.onDestroy=function(w) if card==w then card=nil end end
  card.outfit:setAnimate(false)
  card.outfit:setDirection(2) -- South, only the preview; never turn the char.
  local variant=portraitVariant()
  if variant~=1 then
    -- The OTUI widget is the adjusted one (variant 1); any other variant starts from a fresh widget.
    if not rebuildPortrait(variant) then fitPortrait(card.frame,card.outfit,1) end
  else
    fitPortrait(card.frame,card.outfit,1)
  end
  makePortraitFloor(card.frame)
  portraitOption(card.frame,'setPhantom',false) -- clickable: tries another way of drawing the portrait
  card.frame.onClick=cyclePortrait
  portraitTip()
  card.mount:setOn(config.keepMounted)
  card.mount:setTooltip('ON: vuelve a montar si te bajas. Usa la montura elegida en el cliente.\nEspera fuera de proteccion y mientras el personaje esta muerto. OFF detiene los intentos.')
  card.mount.onClick=function()
    config.keepMounted=not config.keepMounted
    nextMount,waitingMount=0,nil
    -- A second explicit ON permits a new availability probe.
    if config.keepMounted and hasMount==false then hasMount=nil end
    card.mount:setOn(config.keepMounted)
    lastTick=-math.huge;Home.tick()
  end
  queryGuild=true;lastTick=-math.huge
  Home.tick()
  return card
end

local function mount(p,time)
  if not config.keepMounted then mountStatus='Desactivada';waitingMount=nil;return end
  local hp=tonumber(p:getHealth())
  if (g_game.isDead and g_game.isDead()) or not hp or hp<=0 then mountStatus='Esperando a revivir';return end
  local outfit=p:getOutfit() or {}
  if (tonumber(outfit.mount) or 0)>0 then
    hasMount=true;waitingMount=nil;mountStatus='Montura activa';return
  end
  if GamePlayerMounts and g_game.getFeature and not g_game.getFeature(GamePlayerMounts) then
    mountStatus='Monturas no disponibles';return
  end
  local states=tonumber(p:getStates()) or 0
  local pz=PlayerStates and PlayerStates.Pz or 16384
  if math.floor(states/pz)%2==1 then mountStatus='Esperando salir de proteccion';return end
  if hasMount==false then mountStatus='Elige una montura en el cliente';return end
  if waitingMount and time-waitingMount>=3000 then
    nextMount=math.max(nextMount,waitingMount+3000+(hasMount and 10000 or 60000))
    waitingMount=nil
  end
  if time<nextMount then mountStatus=waitingMount and 'Activando montura...' or 'Esperando para volver a intentar';return end
  -- One initial probe is needed when outfit.mount is 0: that field means
  -- unmounted, not that the player owns no mounts. The server checks ownership.
  p:mount()
  waitingMount,nextMount=time,time+5000
  mountStatus='Activando montura...'
end

local function fitValue(w)
  local signature=w:getText()..':'..w:getWidth()
  if w.homeTextSignature==signature then return end
  w.homeTextSignature=signature
  w:setFont('sans-bold-16px')
  if w:getTextSize().width>w:getWidth() then
    w:setFont('verdana-11px-antialised')
    if w:getTextSize().width>w:getWidth() then w:setFont('verdana-9px')end
  end
end
local function updateSummary()
  local stats=sessionSummary
  local seconds=stats and tonumber(stats.seconds)
  text(card.stats.time.value,seconds and string.format('%02d:%02d',math.floor(seconds/3600),math.floor(seconds/60)%60) or '--:--')
  text(card.stats.deaths.value,stats and tostring(math.max(0,math.floor(tonumber(stats.deaths) or 0))) or '--')
  local levels=stats and tonumber(stats.levels)
  text(card.stats.xp.value,levels and (levels>0 and '+' or '')..tostring(levels) or '--')
  for _,key in ipairs({'time','deaths','xp'})do fitValue(card.stats[key].value)end
  tip(card.stats.time,'Sesion de este perfil en el cliente.\nContinua al recargar el bot; se reinicia al cerrar el cliente.')
  tip(card.stats.deaths,'Muertes de esta sesion. Reiniciar el contador de muertes tambien reinicia este valor.')
  local levelTip='Esperando datos de nivel del personaje'
  if levels then
    levelTip='Balance de niveles de la sesion: '..(levels>0 and '+' or '')..tostring(levels)..
      '\nNivel inicial: '..tostring(stats.baseLevel)..' | Nivel actual: '..tostring(stats.level)..
      '\nContinua al recargar el bot; se reinicia al cerrar el cliente.'
    if stats.levelStarted then levelTip=levelTip..'\nContado desde la activacion: no habia un nivel inicial verificable.'end
  end
  tip(card.stats.xp,levelTip)
  local route=CaveBot and CaveBot.getCurrentProfile and CaveBot.getCurrentProfile() or ''
  local list=CaveBot and CaveBot.actionList
  local total=list and list:getChildCount() or 0
  local focused=list and list:getFocusedChild()
  local index=focused and list:getChildIndex(focused) or 0
  text(card.route.name,route~='' and route or total>0 and 'Ruta sin guardar' or 'Sin ruta')
  tip(card.route.name,route~='' and route or 'Selecciona o graba una ruta desde CaveBot')
  text(card.route.step,total>0 and (index>0 and 'Paso '..index..' de '..total or total..' waypoints') or 'No hay waypoints cargados')
  local paused=HelperPause and HelperPause.isPaused()
  text(card.route.status,paused and 'PAUSA' or CaveBot and CaveBot.isOn and CaveBot.isOn() and 'ON' or 'OFF')
end

function Home.tick()
  if closed or not H.valid() then return end
  local time=clock()
  if time-lastTick<1000 then return end
  lastTick=time
  local p=currentPlayer()
  if not p then
    if live(card) and card:isVisible() then
      text(card.name,'Sin personaje');text(card.vocation,'Vocacion: --');text(card.level,'--')
      text(card.stats.time.value,'--:--');text(card.stats.deaths.value,'--');text(card.stats.xp.value,'--')
      text(card.guild,'Sin conexion');text(card.mountStatus,'Esperando conexion');card.outfit:hide()
    end
    return
  end
  local name=p:getName()
  if name~=characterName then reset(name) end
  if RinoSkin and RinoSkin.Session then sessionSummary=RinoSkin.Session.read(p,time)end
  mount(p,time)
  if not live(card) or not card:isVisible() then return end
  text(card.name,name);tip(card.name,name)
  local rawVoc=tonumber(p:getVocation())
  local voc=HelperClientCompat.baseVocation(rawVoc)
  local labelId=rawVoc
  if HelperClientCompat.isAurera and rawVoc and rawVoc%1==0 and rawVoc>=6 and rawVoc<=10 then
    labelId=voc+10 -- Aurera promotions share the existing 11..15 labels.
  end
  local label=vocations[labelId] or vocations[voc] or (vocationText~='' and vocationText) or (rawVoc and 'ID '..rawVoc) or '--'
  text(card.vocation,label);tip(card.vocation,'Vocacion: '..label)
  local level=tonumber(p:getLevel())
  text(card.level,tostring(level or '--'));tip(card.level,'Nivel '..tostring(level or '--'))
  fitValue(card.level)
  updateSummary()
  local guildText=guild==nil and 'Consultando...' or guild=='' and 'Sin guild' or guild
  if guild==nil and not queryGuild and (not lookSentAt or time-lookSentAt>3000) then guildText='Mira tu personaje para actualizar' end
  text(card.guild,guildText)
  tip(card.guild,guild==nil and 'Se obtiene al mirar a tu propio personaje.' or guildText)
  -- The portrait: ApiCompat reads the outfit whatever the client returns and, if the widget keeps no
  -- creature, draws the character itself. What it did is kept for the diagnostics panel.
  if type(ApiCompat)=='table' and type(ApiCompat.paintPortrait)=='function' then
    local before=card.outfit._portraitSignature
    local info=ApiCompat.paintPortrait(card.outfit,p,portraitVariant())
    if info and before~=card.outfit._portraitSignature then reportPortrait(info) end
  else
    local outfit=p:getOutfit()
    if type(outfit)=='table' then
      card.outfit:setOutfit(outfit)
      card.outfit:show()
    end
  end
  card.mount:setOn(config.keepMounted)
  text(card.mountStatus,mountStatus)
  tip(card.mount,'Mantiene la montura elegida en el cliente.\nEstado: '..mountStatus..'\nOFF detiene los intentos sin bajarte de la montura.')
  if queryGuild and time>=nextLook and (not g_game.isDead or not g_game.isDead()) and tonumber(p:getHealth()) and p:getHealth()>0 then
    queryGuild=false;nextLook=time+60000
    if type(g_game.look)=='function' then lookSentAt=time;g_game.look(p) end
  end
end
