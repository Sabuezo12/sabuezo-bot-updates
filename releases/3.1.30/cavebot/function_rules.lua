-- Structured rules remain ordinary function waypoints and coexist with custom Lua.
-- Version 1 (supplies, item, capacity, health, mana, team; next/label/wait) is read and run
-- exactly as before; a rule is written as version 2 only when it uses something newer:
-- more conditions, a second condition joined with "y"/"o", or the newer branch actions.
CaveBot.FunctionRules = {}
local F=CaveBot.FunctionRules
local marker='-- RinoRule v1: '
local function trim(value)return tostring(value or ''):match('^%s*(.-)%s*$')end
local function number(value,low,high)
  return type(value)=='number' and value==value and value>=low and value<=high
end
local function integer(value,low,high) return number(value,low,high) and value%1==0 end

-- id, text shown in the combo, threshold title, threshold range, flags.
F.CONDITIONS={
  {id='supplies',text='Faltan supplies configurados',v1=true},
  {id='item',text='Cantidad de un objeto por debajo del umbral',v1=true,threshold='Cantidad (<)',max=1e9,item=true},
  {id='capacity',text='Capacidad por debajo del umbral',v1=true,threshold='Capacidad (<)',max=1e9},
  {id='health',text='Vida por debajo del umbral (%)',v1=true,threshold='Vida % (<)',max=100},
  {id='mana',text='Mana por debajo del umbral (%)',v1=true,threshold='Mana % (<)',max=100},
  {id='team',text='Equipo reunido en el mismo piso',v1=true,team=true,range=true},
  {id='stamina',text='Stamina por debajo de (horas)',threshold='Horas (<)',max=42},
  {id='hunt',text='Tiempo cazando de al menos (minutos)',threshold='Minutos (>=)',min=1,max=100000},
  {id='laps',text='Cada N vueltas de la ruta',threshold='Cada N',min=1,max=1000,whole=true},
  {id='monsters',text='Monstruos alrededor, al menos N',threshold='Cantidad (>=)',min=1,max=50,whole=true,range=true,names=true},
  {id='players',text='Jugadores cerca (sin party, amigos ni guild)',threshold='Cantidad (>=)',min=1,max=20,whole=true,range=true},
  {id='pz',text='Con PZ bloqueado'},
  {id='skull',text='Con skull (blanca, roja, negra u naranja)'},
  {id='level',text='Nivel de al menos',threshold='Nivel (>=)',min=1,max=10000,whole=true},
  {id='gold',text='Oro en la mochila de al menos',threshold='Oro (>=)',max=1e10},
}
local byId={}
for _,c in ipairs(F.CONDITIONS)do byId[c.id]=c end
F.byId=byId

-- Branch actions: next, label and wait are version 1.
F.MODES={
  {id='next',text='Siguiente waypoint',v1=true},{id='label',text='Ir a un label',v1=true},
  {id='wait',text='Esperar y comprobar',v1=true},{id='say',text='Decir un texto y seguir'},
  {id='alarm',text='Sonar alarma y seguir'},{id='stop',text='Detener el CaveBot'},{id='logout',text='Logout'},
  {id='target_off',text='Apagar TargetBot y seguir'},{id='target_on',text='Encender TargetBot y seguir'},
  {id='attack_off',text='Apagar AttackBot y seguir'},{id='attack_on',text='Encender AttackBot y seguir'},
  {id='heal_off',text='Apagar HealBot y seguir'},{id='heal_on',text='Encender HealBot y seguir'},
}
local modeById={}
for _,m in ipairs(F.MODES)do modeById[m.id]=m end

function F.defaults()
  return {version=1,condition='supplies',itemId=268,threshold=100,names='',range=7,intervalMs=300,
    yes={mode='label',label=''},no={mode='next',label=''}}
end

-- One condition's own fields (also used for the second condition).
local function validateCondition(c,second)
  local meta=type(c)=='table' and byId[c.condition]
  if not meta then return false,'Condicion invalida.'end
  if second and meta.team then return false,'El equipo no puede ser la segunda condicion.'end
  if meta.item and not integer(c.itemId,1,65534)then return false,'Selecciona un objeto valido.'end
  if meta.threshold then
    if not number(c.threshold,meta.min or 0,meta.max)then
      return false,'Valor invalido para "'..meta.text..'" (de '..(meta.min or 0)..' a '..meta.max..').'
    end
    if meta.whole and c.threshold%1~=0 then return false,'El valor de "'..meta.text..'" debe ser un numero entero.'end
  end
  if meta.team and trim(tostring(c.names or ''):gsub(',',''))=='' then
    return false,'Escribe los nombres del equipo separados por comas.'
  end
  if meta.range and not integer(c.range,1,10)then return false,'El rango debe ser de 1 a 10 SQM.'end
  return true
end

function F.validate(config)
  if type(config)~='table' or (config.version~=1 and config.version~=2)then return false,'Condicion invalida.'end
  local ok,message=validateCondition(config)
  if not ok then return false,message end
  if not number(config.intervalMs,100,60000)then return false,'El intervalo debe estar entre 0.1 y 60 segundos.'end
  if config.second~=nil then
    if config.join~='and' and config.join~='or'then return false,'Elige Y u O para la segunda condicion.'end
    ok,message=validateCondition(config.second,true)
    if not ok then return false,'Segunda condicion: '..message end
  end
  for _,name in ipairs({'yes','no'})do
    local branch=config[name]
    if type(branch)~='table' or not modeById[branch.mode]then return false,'Accion de la condicion invalida.'end
    if branch.mode=='label' and trim(branch.label)==''then return false,'Selecciona el label de destino.'end
    if branch.mode=='say' and trim(branch.text)==''then return false,'Escribe el texto que se va a decir.'end
  end
  return true
end

-- Version 1 only for configs an older Helper can still run.
function F.version(config)
  if config.second~=nil then return 2 end
  if not(byId[config.condition]and byId[config.condition].v1)then return 2 end
  for _,name in ipairs({'yes','no'})do
    local branch=config[name]
    if not(branch and modeById[branch.mode]and modeById[branch.mode].v1)then return 2 end
  end
  return 1
end

function F.decode(value)
  if type(value)~='string' or value:sub(1,#marker)~=marker then return end
  local encoded=value:match('^[^\n]*'):sub(#marker+1)
  local ok,result=pcall(json.decode,encoded)
  if ok and F.validate(result)then return result end
end
function F.encode(config)
  if type(config)=='table' then config.version=F.version(config) end
  local valid,message=F.validate(config)
  if not valid then return nil,message end
  local encoded=json.encode(config)
  return marker..encoded..'\nreturn CaveBot.FunctionRules.run('..string.format('%q',encoded)..', retries)'
end

local function describeCondition(c)
  local meta=byId[c.condition]
  if not meta then return 'Condicion'end
  if c.condition=='item' then return 'Cantidad del objeto '..tostring(c.itemId)..' por debajo de '..tostring(c.threshold)end
  if c.condition=='capacity' then return 'Capacidad por debajo de '..tostring(c.threshold)end
  if c.condition=='health' or c.condition=='mana' then
    return (c.condition=='health' and 'Vida' or 'Mana')..' por debajo de '..tostring(c.threshold)..'%'
  end
  if c.condition=='supplies' then return 'Faltan supplies segun los minimos configurados'end
  if c.condition=='team' then return 'Todo el equipo esta cerca y en el mismo piso'end
  if c.condition=='stamina' then return 'Stamina por debajo de '..tostring(c.threshold)..' h'end
  if c.condition=='hunt' then return 'Cazando desde hace '..tostring(c.threshold)..' minutos o mas'end
  if c.condition=='laps' then return 'Cada '..tostring(c.threshold)..' vueltas de la ruta'end
  if c.condition=='monsters' then
    return tostring(c.threshold)..' o mas monstruos'..(trim(c.names)~='' and (' ('..trim(c.names)..')') or '')..
      ' a '..tostring(c.range)..' SQM'
  end
  if c.condition=='players' then return tostring(c.threshold)..' o mas jugadores a '..tostring(c.range)..' SQM'end
  if c.condition=='pz' then return 'Con PZ bloqueado'end
  if c.condition=='skull' then return 'Con skull'end
  if c.condition=='level' then return 'Nivel '..tostring(c.threshold)..' o mas'end
  if c.condition=='gold' then return tostring(c.threshold)..' de oro o mas'end
  return meta.text
end
function F.describe(config)
  local text=describeCondition(config)
  if config.second then text=text..(config.join=='or' and ' O ' or ' Y ')..describeCondition(config.second):lower()end
  local function branch(entry)
    if entry.mode=='label'then return 'ir a '..tostring(entry.label)end
    if entry.mode=='say'then return 'decir "'..tostring(entry.text)..'" y seguir'end
    if entry.mode=='wait'then return 'esperar y comprobar otra vez'end
    if entry.mode=='next'then return 'siguiente waypoint'end
    return (modeById[entry.mode]and modeById[entry.mode].text or entry.mode):lower()
  end
  return text..'\nSi se cumple: '..branch(config.yes)..'.\nSi no se cumple: '..branch(config.no)..'.'
end

local helpers=function()return CaveBot.FunctionHelpers or {} end
local function evaluateCondition(config)
  local c=config.condition
  if c=='supplies'then
    if type(hasSupplies)~='function'then return nil end
    local result=hasSupplies()
    if result==nil then return nil end
    return result~=true
  elseif c=='item'then
    local amount=tonumber(itemAmount(config.itemId))
    return amount and amount<config.threshold
  elseif c=='capacity'then
    local capacity=tonumber(freecap())
    return capacity and capacity<config.threshold
  elseif c=='health' or c=='mana'then
    local getter=c=='health' and hppercent or manapercent
    local amount=getter and tonumber(getter())
    return amount and amount<config.threshold
  elseif c=='team'then
    local origin=player and player:getPosition()
    if not origin then return nil end
    local visible={}
    for _,actor in pairs(getSpectators()or {})do
      if actor==player or actor:isPlayer()then
        local p=actor:getPosition()
        if p and p.z==origin.z and math.max(math.abs(p.x-origin.x),math.abs(p.y-origin.y))<=config.range then
          visible[trim(actor:getName()):lower()]=true
        end
      end
    end
    for name in config.names:gmatch('[^,]+')do
      if not visible[trim(name):lower()]then return false end
    end
    return true
  elseif c=='stamina'then
    local minutes=type(stamina)=='function' and tonumber(stamina())
    return minutes and minutes<config.threshold*60
  elseif c=='hunt'then
    return helpers().huntMinutes and helpers().huntMinutes()>=config.threshold
  elseif c=='laps'then
    local laps=helpers().laps and helpers().laps() or 0
    return laps>0 and laps%config.threshold==0
  elseif c=='monsters'then
    return helpers().monstersAround and helpers().monstersAround(config.range,config.names)>=config.threshold
  elseif c=='players'then
    return helpers().playersAround and helpers().playersAround(config.range)>=config.threshold
  elseif c=='pz'then
    return helpers().pzLocked and helpers().pzLocked()
  elseif c=='skull'then
    return helpers().hasSkull and helpers().hasSkull()
  elseif c=='level'then
    local level=type(lvl)=='function' and tonumber(lvl())
    return level and level>=config.threshold
  elseif c=='gold'then
    return helpers().goldCount and helpers().goldCount()>=config.threshold
  end
end
function F.evaluate(config)
  local a=evaluateCondition(config)
  if not config.second then return a end
  local b=evaluateCondition(config.second)
  if a==nil or b==nil then
    -- One side unknown: "y" with a known false is false, "o" with a known true is true.
    if config.join=='and' and (a==false or b==false)then return false end
    if config.join=='or' and (a==true or b==true)then return true end
    return nil
  end
  if config.join=='or'then return a or b end
  return a and b
end

local BOT_MODES={target_off={'target','off'},target_on={'target','on'},attack_off={'attack','off'},
  attack_on={'attack','on'},heal_off={'heal','off'},heal_on={'heal','on'}}
function F.run(encoded,retries)
  local ok,config=pcall(json.decode,encoded)
  local valid,message
  if ok then valid,message=F.validate(config)end
  if not valid then
    if retries==0 then warn('CaveBot[regla]: '..tostring(message or 'Configuracion invalida.'))end
    CaveBot.delay(500);return 'retry'
  end
  local success,result=pcall(F.evaluate,config)
  if not success or result==nil then CaveBot.delay(config.intervalMs);return 'retry'end
  local branch=result and config.yes or config.no
  if branch.mode=='next'then return true end
  if branch.mode=='label' and CaveBot.gotoLabel(branch.label)then return true end
  if branch.mode=='label' and retries==0 then warn('CaveBot[regla]: falta el label '..branch.label)end
  if branch.mode=='say'then say(branch.text);return true end
  if branch.mode=='alarm'then
    local alarm=helpers().alarm
    if alarm then alarm(trim(branch.text)~='' and branch.text or 'Regla del CaveBot')end
    return true
  end
  if branch.mode=='stop'then CaveBot.setOff();return true end
  if branch.mode=='logout'then
    if g_game and g_game.safeLogout then g_game.safeLogout()end
    CaveBot.delay(1000);return 'retry'
  end
  local bot=BOT_MODES[branch.mode]
  if bot then
    if helpers().setBot then helpers().setBot(bot[1],bot[2])end
    return true
  end
  CaveBot.delay(config.intervalMs)
  return 'retry'
end
