-- Timer filters use only the globals exported by game_bot. No arbitrary code
-- is evaluated for conditions, and missing readings never count as a match.
TimerExecutorConditions={}
local C=TimerExecutorConditions
local function finite(v)return type(v)=='number'and v==v and v~=math.huge and v~=-math.huge end
local function call(fn,...)
  if type(fn)~='function'then return nil end
  local ok,v=pcall(fn,...);if ok then return v end
end
function C.time(text,clock)
  if type(text)=='number'and not clock then return finite(text)and text>=0 and text or nil end
  local h,m=tostring(text or''):match('^%s*(%d%d?):(%d%d)%s*$');h,m=tonumber(h),tonumber(m)
  if not h or m>59 or h>(clock and 23 or 99)then return nil end
  return h*60+m
end
function C.format(value)
  value=math.max(0,math.floor(tonumber(value)or 0));return string.format('%02d:%02d',math.floor(value/60),value%60)
end
function C.normalize(action)
  if type(action.conditions)~='table'then action.conditions={}end
  local c=action.conditions
  for key,values in pairs({stamina={'00:00','42:00'},hp={0,100},mana={0,100},monsters={0,50},capacity={0,''},items={1,''},clock={'00:00','23:59'}})do
    if type(c[key])~='table'then c[key]={}end
    local r=c[key];r.enabled=r.enabled==true
    if r.min==nil then r.min=values[1]end
    if r.max==nil then r.max=values[2]end
  end
  c.items.id=tonumber(c.items.id)or 0
  if c.pz==nil then c.pz=action.skipPz and 'Fuera de PZ'or'Cualquiera'end
  if c.combat==nil then c.combat=action.skipAttack and 'Sin atacar'or'Cualquiera'end
  if c.cave==nil then c.cave='Cualquiera'end
  if c.target==nil then c.target='Cualquiera'end
  action.skipPz=c.pz=='Fuera de PZ';action.skipAttack=c.combat=='Sin atacar'
  return c
end
function C.copy(value)
  if type(value)~='table'then return value end
  local out={};for k,v in pairs(value)do out[k]=C.copy(v)end;return out
end
function C.count(action)
  local c=C.normalize(action);local n=0
  for _,key in ipairs({'stamina','hp','mana','capacity','monsters','items','clock'})do if c[key].enabled then n=n+1 end end
  for _,key in ipairs({'pz','combat','cave','target'})do if c[key]~='Cualquiera'then n=n+1 end end
  return n
end
local function cached(cache,key,fn)
  if cache[key]==nil then local v=fn();cache[key]=v==nil and false or v end
  return cache[key]~=false and cache[key]or nil
end
local function reading(cache,key)
  return cached(cache,key,function()
    if key=='stamina'then return call(stamina)or player and call(player.getStamina,player)end
    if key=='hp'then return call(hppercent)end
    if key=='mana'then return call(manapercent)end
    if key=='capacity'then return call(freecap)or player and call(player.getFreeCapacity,player)end
    if key=='monsters'then
      local actors=call(getSpectators,false);local p=player and call(player.getPosition,player)
      if type(actors)~='table'or not p then return nil end
      local n=0
      for _,actor in ipairs(actors)do
        local pos=call(actor.getPosition,actor)
        if call(actor.isMonster,actor)==true and call(actor.getHealthPercent,actor)~=0 and pos and pos.z==p.z and
          math.max(math.abs(pos.x-p.x),math.abs(pos.y-p.y))<=7 then n=n+1 end
      end
      return n
    end
  end)
end
local function itemCount(id)
  if not g_game or type(g_game.getContainers)~='function'then return nil end
  local containers=call(g_game.getContainers);if type(containers)~='table'then return nil end
  local n=0
  local function add(item)
    if item and call(item.getId,item)==id then n=n+math.max(1,tonumber(call(item.getCount,item))or 1)end
  end
  for _,container in pairs(containers)do for _,item in ipairs(container:getItems())do add(item)end end
  if player and type(player.getInventoryItem)=='function'then for slot=1,11 do add(call(player.getInventoryItem,player,slot))end end
  return n
end
function C.check(action,cache)
  cache=cache or{};local c=C.normalize(action)
  if g_game and type(g_game.isOnline)=='function'and call(g_game.isOnline)~=true then return false,'Desconectado'end
  if not player then return false,'Sin personaje'end
  if call(player.getHealthPercent,player)==0 then return false,'Personaje muerto'end
  for _,entry in ipairs({{'stamina','Stamina'},{'hp','Vida %'},{'mana','Mana %'},{'capacity','Capacidad'},{'monsters','Monstruos'}})do
    local key,name=entry[1],entry[2];local r=c[key]
    if r.enabled then
      local lo=key=='stamina'and C.time(r.min)or tonumber(r.min)
      local unbounded=key=='capacity'and tostring(r.max):match('^%s*$')~=nil
      local hi=unbounded and math.huge or key=='stamina'and C.time(r.max)or tonumber(r.max)
      if not finite(lo)or lo<0 or not(finite(hi)or unbounded)or hi<lo then return false,name..': rango invalido'end
      local v=reading(cache,key)
      if not finite(v)then return false,name..': lectura no disponible'end
      if v<lo or v>hi then return false,name..': '..(key=='stamina'and C.format(v)or tostring(v))..' fuera del rango'end
    end
  end
  if c.items.enabled then
    local id,minimum=tonumber(c.items.id),tonumber(c.items.min)
    local unbounded=tostring(c.items.max):match('^%s*$')~=nil
    local maximum=unbounded and math.huge or tonumber(c.items.max)
    if not finite(id)or id<=100 or not finite(minimum)or minimum<0 or not(finite(maximum)or unbounded)or maximum<minimum then return false,'Configura item y rango de cantidad'end
    local n=cached(cache,'item:'..id,function()return itemCount(id)end)
    if not finite(n)then return false,'Cantidad visible no disponible'end
    if n<minimum or n>maximum then return false,'Item '..id..': '..n..' visibles, fuera del rango'end
  end
  if c.clock.enabled then
    local lo,hi=C.time(c.clock.min,true),C.time(c.clock.max,true)
    local t=cached(cache,'clock',function()return os and call(os.date,'*t')end)
    if not lo or not hi then return false,'Horario invalido: usa HH:MM'end
    if type(t)~='table'or not t.hour or not t.min then return false,'Hora local no disponible'end
    local v=t.hour*60+t.min
    local match=lo<=hi and v>=lo and v<=hi or lo>hi and(v>=lo or v<=hi)
    if not match then return false,'Fuera del horario local'end
  end
  if c.pz~='Cualquiera'then
    local value=call(isInPz)
    if type(value)~='boolean'then return false,'PZ no disponible'end
    if c.pz~='En PZ'and c.pz~='Fuera de PZ'then return false,'Condicion PZ invalida'end
    if value~=(c.pz=='En PZ')then return false,'Requiere '..c.pz end
  end
  if c.combat~='Cualquiera'then
    local value=g_game and call(g_game.isAttacking)
    if type(value)~='boolean'then return false,'Estado de ataque no disponible'end
    if c.combat~='Atacando'and c.combat~='Sin atacar'then return false,'Condicion de ataque invalida'end
    if value~=(c.combat=='Atacando')then return false,'Requiere '..c.combat end
  end
  for _,entry in ipairs({{'cave',CaveBot,'CaveBot'},{'target',TargetBot,'TargetBot'}})do
    local selected=c[entry[1]]
    if selected~='Cualquiera'then
      if selected~='ON'and selected~='OFF'then return false,'Estado invalido: '..entry[3]end
      local value=entry[2]and call(entry[2].isOn)
      if type(value)~='boolean'then return false,entry[3]..' no disponible'end
      if value~=(selected=='ON')then return false,'Requiere '..entry[3]..' '..selected end
    end
  end
  return true,'Condiciones cumplidas'
end
