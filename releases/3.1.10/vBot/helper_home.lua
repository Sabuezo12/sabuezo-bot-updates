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

function Home.render(parent,create)
  if closed then return end
  card=create('HelperHomeCard',parent)
  for _,id in ipairs({'frame','outfit','name','vocation','guild','mount','mountStatus'})do card[id]=card.identity[id]end
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
  local voc=tonumber(p:getVocation())
  local label=vocations[voc] or (vocationText~='' and vocationText) or (voc and 'ID '..voc) or '--'
  text(card.vocation,label);tip(card.vocation,'Vocacion: '..label)
  local level=tonumber(p:getLevel())
  text(card.level,tostring(level or '--'));tip(card.level,'Nivel '..tostring(level or '--'))
  fitValue(card.level)
  updateSummary()
  local guildText=guild==nil and 'Consultando...' or guild=='' and 'Sin guild' or guild
  if guild==nil and not queryGuild and (not lookSentAt or time-lookSentAt>3000) then guildText='Mira tu personaje para actualizar' end
  text(card.guild,guildText)
  tip(card.guild,guild==nil and 'Se obtiene al mirar a tu propio personaje.' or guildText)
  local outfit=p:getOutfit()
  if type(outfit)=='table' then
    local keys,parts={},{}
    for k,v in pairs(outfit) do if type(v)~='table' then keys[#keys+1]=k end end
    table.sort(keys)
    for _,k in ipairs(keys) do parts[#parts+1]=tostring(k)..'='..tostring(outfit[k]) end
    local signature=table.concat(parts,';')
    if card.outfitSignature~=signature then card.outfit:setOutfit(outfit);card.outfitSignature=signature end
    card.outfit:show()
  end
  card.mount:setOn(config.keepMounted)
  text(card.mountStatus,mountStatus)
  tip(card.mount,'Mantiene la montura elegida en el cliente.\nEstado: '..mountStatus..'\nOFF detiene los intentos sin bajarte de la montura.')
  if queryGuild and time>=nextLook and (not g_game.isDead or not g_game.isDead()) and tonumber(p:getHealth()) and p:getHealth()>0 then
    queryGuild=false;nextLook=time+60000
    if type(g_game.look)=='function' then lookSentAt=time;g_game.look(p) end
  end
end
