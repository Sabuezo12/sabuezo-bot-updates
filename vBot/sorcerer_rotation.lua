-- General MS 400+ PvE preset. Weights estimate relative damage on neutral
-- targets; Mythic resistances, gear and Wheel damage bonuses can change them.
-- Native cooldown icons decide availability, not a hard-coded cast sequence.
SorcererRotation = {}
local M, C = SorcererRotation, AttackSpellCatalog
M.version = 20261007
M.selectorVersion = 1
M.spells, M.items = {}, {}
local function spell(words, name, power, cooldown, mana, level, category, pattern, extra)
  local spec={words=words,name=name,power=power,cooldown=cooldown,mana=mana,level=level,
    category=category,pattern=pattern,range=7,lock=2000}
  for key,value in pairs(extra or {}) do spec[key]=value end
  M.spells[words]=spec
  return spec
end
local ordered = {
  spell('exevo vis hur','Energy Wave',160,8000,170,38,5,2),
  spell('exevo gran flam hur','Great Fire Wave',100,4000,120,38,5,11),
  spell('exevo mort ora','Death Echo',75,6000,150,120,6,3,{echo=true,aimed=true}),
  spell('exevo gran vis lux','Great Energy Beam',155,6000,110,29,5,7,{shared='Great Beams',sharedCd=6000}),
  spell('exevo max mort','Great Death Beam',155,6000,140,66,6,12,{shared='Great Beams',sharedCd=6000}),
  spell('exevo gran mas flam',"Hell's Core",230,40000,1100,60,5,4,{shared='Focus',sharedCd=40000,lock=4000,count=6}),
  spell('exevo gran mas vis','Rage of the Skies',175,40000,600,55,5,5,{shared='Focus',sharedCd=40000,lock=4000,count=6}),
  spell('exori max vis','Ultimate Energy Strike',210,30000,100,100,1,7,{shared='Ultimate Strikes',sharedCd=30000}),
  spell('exori max flam','Ultimate Flame Strike',210,30000,100,90,1,7,{shared='Ultimate Strikes',sharedCd=30000}),
  spell('exori gran vis','Strong Energy Strike',125,8000,60,80,1,7,{shared='Special',sharedCd=8000}),
  spell('exori gran flam','Strong Flame Strike',125,8000,60,70,1,7,{shared='Special',sharedCd=8000}),
  -- Count only the selected target until Mythic's extra Lightning jumps are verified.
  spell('exori amp vis','Lightning',110,8000,60,55,1,7,{shared='Special',sharedCd=8000}),
  spell('exori mort','Death Strike',50,1000,20,16,1,3,{lock=1000}),
  spell('exori vis','Energy Strike',50,2000,20,12,1,3),
  spell('exori flam','Flame Strike',50,2000,20,14,1,3),
  spell('exori frigo','Ice Strike',50,2000,20,15,1,3),
  spell('exori tera','Terra Strike',50,2000,20,13,1,3),
  spell('exevo vis lux','Energy Beam',75,4000,40,23,5,6,{optional=true}),
  spell('exevo flam hur','Fire Wave',30,4000,25,18,5,10,{optional=true}),
  spell('utori mort','Curse',40,40000,30,75,1,3,{optional=true}),
  spell('utori flam','Ignite',30,30000,30,26,1,3,{optional=true}),
  spell('utori vis','Electrify',30,30000,30,34,1,3,{optional=true}),
}
local runeSpecs = {
  {id=3161,name='Avalanche',power=50,category=2,pattern=3,count=2},
  {id=3155,name='Sudden Death',power=120,category=3,pattern=7,count=1,singleOnly=true},
  {id=3191,name='Great Fireball',power=50,category=2,pattern=3,count=2,optional=true},
  {id=3202,name='Thunderstorm',power=50,category=2,pattern=3,count=2,optional=true},
  {id=3175,name='Stone Shower',power=50,category=2,pattern=3,count=2,optional=true},
}
for _,spec in ipairs(runeSpecs) do spec.itemId=spec.id;spec.cooldown=2000;spec.lock=2000;M.items[spec.id]=spec end
function M.find(entry)
  return (entry.itemId or 0)>100 and M.items[entry.itemId] or M.spells[C.normalize(entry.spell)]
end
local function describe(entry,spec)
  return '['..spec.name..'] '..(spec.words or tostring(spec.itemId))..' ('..
    entry.count..(entry.orMore and '+' or '')..')'
end
function M.entries()
  local result={}
  local function add(spec)
    local entry={spell=spec.words or '',itemId=spec.itemId or 0,category=spec.category,
      patternCategory=spec.category==6 and 5 or spec.category==5 and 4 or spec.category==2 and 2 or spec.category==3 and 3 or 1,
      pattern=spec.pattern,spellRange=spec.range or 7,count=spec.count or ((spec.category==5 or spec.category==6) and 2 or 1),
      orMore=true,mana=1,minHp=0,maxHp=100,monsters=true,creatures='*',cooldown=spec.cooldown,
      enabled=not spec.optional,msPreset=M.version,
      tooltip=spec.name..'\nRotacion MS: compara area y exhaust del cliente.'}
    entry.description=describe(entry,spec)
    if spec.category==6 then
      local data=C.find(spec.words)
      entry.catalogGeometryVersion=C.version;entry.catalogSpell=data and data.id
    end
    result[#result+1]=entry
  end
  for _,spec in ipairs(ordered) do add(spec) end
  for _,spec in ipairs(runeSpecs) do add(spec) end
  return result
end
-- Lists and attack settings follow the vocation selected in the existing
-- profile. Profile name and the main on/off switch still belong to the profile.
local settingKeys={'Cooldown','ClientCooldowns','MSAdaptive','Rotate','ignoreMana',
  'Visible','OldSchool','pvpMode','PvpSafe','Kills','KillsAmount','BlackListSafe','AntiRsRange','Training'}
local msDefaults={Cooldown=true,ClientCooldowns=true,MSAdaptive=true,Rotate=true,
  ignoreMana=true,Visible=false,OldSchool=false,pvpMode=false,PvpSafe=true,Kills=false,
  KillsAmount=1,BlackListSafe=false,AntiRsRange=5,Training=true}
local function captureSettings(profile)
  local settings={}
  for _,key in ipairs(settingKeys) do settings[key]=profile[key] end
  return settings
end
local function applySettings(profile,settings)
  for _,key in ipairs(settingKeys) do profile[key]=settings[key] end
end
function M.saveVocationSettings(profile)
  if not profile.attackSettingsByVocation then return end
  profile.attackSettingsByVocation[profile.selectedVocation]=captureSettings(profile)
end
function M.selectVocation(profile,vocation)
  M.saveVocationSettings(profile)
  C.bindVocation(profile,vocation)
  if profile.attackSettingsByVocation then
    local settings=profile.attackSettingsByVocation[vocation]
    if not settings then
      settings=C.copy(profile.defaultVocationAttackSettings or captureSettings(profile))
      profile.attackSettingsByVocation[vocation]=settings
    end
    applySettings(profile,settings)
  end
end
function M.installPreset(config)
  local profile=config.AttackBot and config.AttackBot[1]
  if not profile or profile.msVocationRotationVersion==M.selectorVersion then return false end
  C.bindVocation(profile)
  local source
  for _,candidate in ipairs(config.AttackBot) do
    if candidate.msRotationVersion then source=candidate;break end
  end
  local sourceEntries=source and source.attacksByVocation and source.attacksByVocation.Sorcerer or
    source and source.selectedVocation=='Sorcerer' and source.attackTable or M.entries()
  local previous=profile.attacksByVocation.Sorcerer or {}
  local keepExisting=false
  for _,entry in ipairs(previous) do if entry.enabled or entry.msPreset then keepExisting=true;break end end
  local function entryKey(entry)
    return (entry.itemId or 0)>100 and 'item:'..entry.itemId or 'spell:'..C.normalize(entry.spell)
  end
  local oldByKey,present,entries={},{},{}
  for _,entry in ipairs(previous) do oldByKey[entryKey(entry)]=entry end
  for _,entry in ipairs(sourceEntries) do
    local key=entryKey(entry)
    local copied=C.copy(keepExisting and oldByKey[key] or entry)
    local spec=M.find(copied)
    if spec and copied.description=='[MS] '..spec.name then copied.description=describe(copied,spec) end
    entries[#entries+1]=copied;present[key]=true
  end
  for _,entry in ipairs(previous) do
    if not present[entryKey(entry)] then entries[#entries+1]=C.copy(entry) end
  end
  profile.attacksByVocation.Sorcerer=entries
  local original=captureSettings(profile)
  profile.defaultVocationAttackSettings=profile.defaultVocationAttackSettings or C.copy(original)
  profile.attackSettingsByVocation=profile.attackSettingsByVocation or {}
  for vocation in pairs(profile.attacksByVocation) do
    if vocation~='Sorcerer' and not profile.attackSettingsByVocation[vocation] then
      profile.attackSettingsByVocation[vocation]=C.copy(original)
    end
  end
  if not profile.attackSettingsByVocation.Paladin then profile.attackSettingsByVocation.Paladin=C.copy(original) end
  if not profile.attackSettingsByVocation.Sorcerer then
    profile.attackSettingsByVocation.Sorcerer=captureSettings(source or msDefaults)
  end
  profile.msVocationRotationVersion=M.selectorVersion
  C.bindVocation(profile)
  if profile.selectedVocation=='Sorcerer' then applySettings(profile,profile.attackSettingsByVocation.Sorcerer) end
  return true,1
end

function M.newRuntime() return {attempts={},confirmed={},blocked={},shared={},itemReadyAt=0,sendReadyAt=0} end
function M.confirm(runtime,words,time)
  words=C.normalize(words)
  runtime.confirmed[words]=time;runtime.attempts[words]=nil;runtime.blocked[words]=nil
  local spec=M.spells[words]
  if spec and spec.shared then runtime.shared[spec.shared]=time+spec.sharedCd end
end
function M.attempt(runtime,words,time)
  runtime.attempts[C.normalize(words)]=time
  runtime.sendReadyAt=time+200
end
function M.ready(runtime,entry,time,nativeSecondary)
  local spec=M.find(entry)
  if not spec or time<runtime.sendReadyAt then return false end
  if spec.itemId then return time>=runtime.itemReadyAt end
  local words=spec.words
  if runtime.attempts[words] then
    if time-runtime.attempts[words]<750 then return false end
    runtime.attempts[words]=nil;runtime.blocked[words]=time+30000
  end
  if time<(runtime.blocked[words] or 0) then return false end
  if not nativeSecondary and spec.shared and time<(runtime.shared[spec.shared] or 0) then return false end
  return true
end

-- Compile the existing AttackBot masks once. Directional candidates are
-- evaluated before turning, so an unaligned beam never causes walking or a stall.
local shapeCache={}
local function shape(entry,patterns,direction)
  if entry.category==6 then
    local model=C.models[entry.pattern]
    if not model or not model.offsets then return nil end
    local cells={}
    for _,offset in ipairs(model.offsets) do
      local x,y=offset.x,offset.y
      if model.directional then
        if direction==1 then x,y=-y,x elseif direction==2 then x,y=-x,-y elseif direction==3 then x,y=y,-x end
      end
      cells[#cells+1]={x=x,y=y}
    end
    return cells,model.directional
  end
  local key=tostring(entry.patternCategory)..':'..tostring(entry.pattern)..':'..direction
  if shapeCache[key] then return shapeCache[key].cells,shapeCache[key].directional end
  local pattern=patterns[entry.patternCategory] and patterns[entry.patternCategory][entry.pattern]
  if not pattern then return nil end
  local rows={}
  for line in pattern[1]:gmatch('[^\n]+') do
    line=line:gsub('%s','');if #line>0 then rows[#rows+1]=line end
  end
  local cells,dir={},false
  local letter=({'N','E','S','W'})[direction+1]
  local cy=math.floor(#rows/2)+1
  for y,row in ipairs(rows) do
    local cx=math.floor(#row/2)+1
    for x=1,#row do
      local value=row:sub(x,x)
      if value=='N' or value=='E' or value=='S' or value=='W' then dir=true end
      if value=='1' or value==letter then cells[#cells+1]={x=x-cx,y=y-cy} end
    end
  end
  shapeCache[key]={cells=cells,directional=dir}
  return cells,dir
end
local function matches(entry,actor)
  if not actor.monster or actor.summon or actor.shootable==false or not actor.pos then return false end
  if actor.hp<entry.minHp or actor.hp>entry.maxHp then return false end
  if type(entry.monsters)=='table' and #entry.monsters>0 then
    for _,name in ipairs(entry.monsters) do if C.normalize(name)==C.normalize(actor.name) then return true end end
    return false
  end
  return true
end
local function inside(position,anchor,cells,margin)
  if position.z~=anchor.z then return false end
  for _,cell in ipairs(cells) do
    if math.max(math.abs(position.x-anchor.x-cell.x),math.abs(position.y-anchor.y-cell.y))<=margin then return true end
  end
  return false
end
local function countAt(entry,anchor,cells,actors,safe)
  local count,echo=0,0
  for _,actor in ipairs(actors) do
    if actor.pos then
      if safe and actor.unsafePlayer and inside(actor.pos,anchor,cells,2) then return 0,0,true end
      if matches(entry,actor) and inside(actor.pos,anchor,cells,0) then
        count=count+1;echo=echo+(actor.walking and 0.2 or 0.5)
      end
    end
  end
  return count,echo,false
end
function M.rank(entries,caster,targetActor,actors,patterns,context)
  local candidates={}
  local total=0
  for _,actor in ipairs(actors) do if actor.monster and not actor.summon and actor.pos and C.distance(caster,actor.pos)<=7 then total=total+1 end end
  for order,entry in ipairs(entries) do
    local spec=M.find(entry)
    if entry.enabled and spec and context.ready(entry,spec) and not (spec.singleOnly and total>2) then
      local function offer(amount,echo,unsafe,direction,aim)
        local enough=entry.orMore and amount>=entry.count or not entry.orMore and amount==entry.count
        if amount==0 or not enough or unsafe then return end
        local lock=context.lock and context.lock(entry,spec) or spec.lock
        local power=tonumber(entry.msPower) or spec.power
        local value=power*(amount+(spec.echo and echo or 0))*2000/math.max(1000,lock or 2000)
        candidates[#candidates+1]={entry=entry,spec=spec,score=value,amount=amount,order=order,direction=direction,aim=aim}
      end
      if entry.category==1 or entry.category==3 then
        if targetActor and matches(entry,targetActor) and C.distance(caster,targetActor.pos)<=(entry.pattern or spec.range) then offer(1,0,false) end
      elseif entry.category==2 or spec.aimed then
        local cells=shape(entry,patterns,0) or {}
        local centers={}
        for _,actor in ipairs(actors) do
          if matches(entry,actor) and actor.pos.z==caster.z then
            for _,offset in ipairs(cells) do
              local x,y=actor.pos.x-offset.x,actor.pos.y-offset.y
              if x>=0 and x<=65535 and y>=0 and y<=65535 and math.max(math.abs(x-caster.x),math.abs(y-caster.y))<=math.min(7,entry.spellRange or 7) then centers[x..':'..y]={x=x,y=y,z=caster.z} end
            end
          end
        end
        local best
        for _,center in pairs(centers) do
          local amount,echo,unsafe=countAt(entry,center,cells,actors,context.safe)
          local enough=entry.orMore and amount>=entry.count or not entry.orMore and amount==entry.count
          local value=amount+(spec.echo and echo or 0)
          if enough and not unsafe and (not best or value>best.value or value==best.value and C.distance(caster,center)<C.distance(caster,best.pos)) and context.canAim(center) then
            best={pos=center,amount=amount,echo=echo,value=value}
          end
        end
        if best then offer(best.amount,best.echo,false,nil,best.pos) end
      else
        for direction=0,3 do
          local cells,directional=shape(entry,patterns,direction)
          if cells and (context.rotate or not directional or direction==context.direction) then
            local amount,echo,unsafe=countAt(entry,caster,cells,actors,context.safe)
            offer(amount,echo,unsafe,directional and direction or nil)
          end
          if not directional then break end
        end
      end
    end
  end
  table.sort(candidates,function(a,b)
    if a.score~=b.score then return a.score>b.score end
    if a.amount~=b.amount then return a.amount>b.amount end
    local aFacing,bFacing=a.direction==context.direction,b.direction==context.direction
    if aFacing~=bFacing then return aFacing end
    if a.order~=b.order then return a.order<b.order end
    return (a.direction or -1)<(b.direction or -1)
  end)
  return candidates
end
