-- Structured rules remain ordinary function waypoints and coexist with custom Lua.
CaveBot.FunctionRules = {}
local F=CaveBot.FunctionRules
local marker='-- RinoRule v1: '
local conditions={item=true,supplies=true,capacity=true,health=true,mana=true,team=true}
local function trim(value)return tostring(value or ''):match('^%s*(.-)%s*$')end
local function number(value,low,high)
  return type(value)=='number' and value==value and value>=low and value<=high
end
function F.defaults()
  return {version=1,condition='supplies',itemId=268,threshold=100,names='',range=7,intervalMs=300,
    yes={mode='label',label=''},no={mode='next',label=''}}
end
function F.validate(config)
  if type(config)~='table' or config.version~=1 or not conditions[config.condition]then return false,'Condicion invalida.'end
  if not number(config.intervalMs,100,60000)then return false,'El intervalo debe estar entre 0.1 y 60 segundos.'end
  if config.condition=='item' and (not number(config.itemId,1,65534)or config.itemId%1~=0)then return false,'Selecciona un objeto valido.'end
  if config.condition=='item' or config.condition=='capacity' or config.condition=='health' or config.condition=='mana'then
    local maximum=(config.condition=='health' or config.condition=='mana')and 100 or 1000000000
    if not number(config.threshold,0,maximum)then return false,'Umbral invalido para esta condicion.'end
  end
  if config.condition=='team'then
    if trim(tostring(config.names or ''):gsub(',',''))==''then return false,'Escribe los nombres del equipo separados por comas.'end
    if not number(config.range,1,10)or config.range%1~=0 then return false,'El rango del equipo debe ser de 1 a 10 SQM.'end
  end
  for _,name in ipairs({'yes','no'})do
    local branch=config[name]
    if type(branch)~='table' or (branch.mode~='next' and branch.mode~='wait' and branch.mode~='label')then return false,'Accion de la condicion invalida.'end
    if branch.mode=='label' and trim(branch.label)==''then return false,'Selecciona el label de destino.'end
  end
  return true
end
function F.decode(value)
  if type(value)~='string' or value:sub(1,#marker)~=marker then return end
  local encoded=value:match('^[^\n]*'):sub(#marker+1)
  local ok,result=pcall(json.decode,encoded)
  if ok and F.validate(result)then return result end
end
function F.encode(config)
  local valid,message=F.validate(config)
  if not valid then return nil,message end
  local encoded=json.encode(config)
  return marker..encoded..'\nreturn CaveBot.FunctionRules.run('..string.format('%q',encoded)..', retries)'
end
local descriptions={item='Cantidad del objeto por debajo de ',capacity='Capacidad por debajo de ',
  health='Vida por debajo de ',mana='Mana por debajo de ',supplies='Faltan supplies segun los minimos configurados',
  team='Todo el equipo esta cerca y en el mismo piso'}
function F.describe(config)
  local text=descriptions[config.condition]or 'Condicion'
  if config.condition=='item' or config.condition=='capacity' or config.condition=='health' or config.condition=='mana'then
    text=text..tostring(config.threshold)..((config.condition=='health' or config.condition=='mana')and '%'or '')
  end
  local function branch(entry)
    if entry.mode=='label'then return 'ir a '..tostring(entry.label)end
    return entry.mode=='wait' and 'esperar y comprobar otra vez'or 'siguiente waypoint'
  end
  return text..'\nSi se cumple: '..branch(config.yes)..'.\nSi no se cumple: '..branch(config.no)..'.'
end
function F.evaluate(config)
  if config.condition=='supplies'then
    if type(hasSupplies)~='function'then return nil end
    local result=hasSupplies()
    if result==nil then return nil end
    return result~=true
  elseif config.condition=='item'then
    local amount=tonumber(itemAmount(config.itemId))
    return amount and amount<config.threshold
  elseif config.condition=='capacity'then
    local capacity=tonumber(freecap())
    return capacity and capacity<config.threshold
  elseif config.condition=='health' or config.condition=='mana'then
    local getter=config.condition=='health' and hppercent or manapercent
    local amount=getter and tonumber(getter())
    return amount and amount<config.threshold
  elseif config.condition=='team'then
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
  end
end
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
  CaveBot.delay(config.intervalMs)
  return 'retry'
end
