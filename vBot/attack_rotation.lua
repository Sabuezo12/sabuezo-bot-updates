-- General level 400+ PvE area presets for five vocations. Weights estimate relative damage on neutral
-- targets; Mythic resistances, gear and Wheel damage bonuses can change them.
-- Native cooldown icons decide availability, not a hard-coded cast sequence.
AttackRotation = {}
local M, C = AttackRotation, AttackSpellCatalog
M.version = 20261007
M.timingVersion = 2026100702
M.selectorVersion = 1
M.presets = {}
M.supported = {Paladin=true,Sorcerer=true,Druid=true,Knight=true,Monk=true}
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
-- Relative weights compare spells within each vocation, not across vocations.
-- They are neutral-target estimates, not measured Mythic damage formulas.
M.presets.Knight = {
  spell('exori gran','Fierce Berserk',115,6000,340,90,5,1),
  spell('exori min','Front Sweep',80,6000,200,70,5,8),
  spell('exori','Berserk',60,4000,115,35,5,1),
  spell('exori mas','Groundshaker',42,8000,160,33,5,3),
  spell('exori gran ico','Annihilation',300,30000,300,110,1,1,{lock=4000}),
  spell('exori ico','Brutal Strike',65,6000,30,16,1,1),
  spell('exori hur','Whirlwind Throw',50,6000,40,28,1,5),
  spell('exori amp kor',"Executioner's Throw",180,18000,225,0,1,7,{optional=true}),
  spell('exori scu','Shield Slam',52,6000,110,30,1,1,{optional=true,shield=true}),
}
M.presets.Druid = {
  spell('exevo tera hur','Terra Wave',120,4000,170,38,5,2),
  -- Mythic's public listing still says 8s. Its native icon overrides this fallback.
  spell('exevo gran frigo hur','Strong Ice Wave',140,8000,170,40,5,9),
  spell('exevo fur tera','Forked Thorns',97,6000,180,80,6,5),
  spell('exevo fur frigo','Forked Glacier',90,6000,180,90,6,6),
  -- Mythic permits alternating these UEs after the 4s attack exhaust. Their
  -- individual cooldowns remain 40s; do not invent a 40s Focus lock between them.
  -- Any secondary group actually reported by the client is still checked.
  spell('exevo gran mas frigo','Eternal Winter',250,40000,1050,60,5,4,{lock=4000,count=6}),
  spell('exevo gran mas tera','Wrath of Nature',175,40000,700,55,5,5,{lock=4000,count=6}),
  spell('exevo ulus frigo','Ice Burst',150,22000,230,0,6,4,{optional=true,shared='Bursts Of Nature',sharedCd=22000}),
  spell('exevo ulus tera','Terra Burst',150,22000,230,0,6,4,{optional=true,shared='Bursts Of Nature',sharedCd=22000}),
  spell('exori max frigo','Ultimate Ice Strike',195,30000,100,100,1,7,{shared='Ultimate Strikes',sharedCd=30000,lock=4000}),
  spell('exori max tera','Ultimate Terra Strike',195,30000,100,90,1,7,{shared='Ultimate Strikes',sharedCd=30000,lock=4000}),
  spell('exori gran frigo','Strong Ice Strike',115,8000,60,80,1,7,{shared='Special',sharedCd=8000}),
  spell('exori gran tera','Strong Terra Strike',115,8000,60,70,1,7,{shared='Special',sharedCd=8000}),
  spell('exori frigo','Ice Strike',50,2000,20,15,1,3),
  spell('exori tera','Terra Strike',50,2000,20,13,1,3),
  spell('exori flam','Flame Strike',50,2000,20,14,1,3),
  spell('exori vis','Energy Strike',50,2000,20,12,1,3),
  spell('exevo frigo hur','Ice Wave',30,4000,25,18,5,10,{optional=true}),
  spell('utori pox','Envenom',30,30000,30,50,1,3,{optional=true}),
}
M.presets.Monk = {
  spell('exori gran mas pug','Greater Flurry of Blows',75,16000,300,90,6,10,{harmony='builder'}),
  spell('exori mas amp pug','Thousand Fist Blows',62,8000,145,120,6,2,{harmony='builder',aimed=true}),
  spell('exori med pug','Chained Penance',52,4000,180,70,6,7,{harmony='builder'}),
  spell('exori mas pug','Flurry of Blows',50,4000,110,35,6,9,{harmony='builder'}),
  spell('exori mas nia','Sweeping Takedown',95,8000,195,60,6,11,{harmony='spender'}),
  spell('exori gran mas nia','Spiritual Outburst',42,24000,425,0,6,8,{harmony='spender',echo=true,optional=true}),
  spell('exori gran nia','Devastating Knockout',180,8000,210,125,1,7,{harmony='spender'}),
  spell('exori gran pug','Forceful Uppercut',230,60000,325,110,1,1,{harmony='builder'}),
  spell('exori amp pug','Mystic Repulse',85,8000,150,30,1,7,{harmony='builder'}),
  spell('exori pug','Double Jab',40,4000,30,14,1,1,{harmony='builder'}),
  spell('exori nia','Greater Tiger Clash',75,8000,50,18,1,1,{harmony='spender'}),
  spell('exori infir amp pug','Lesser Mystic Repulse',25,20000,30,6,1,7,{harmony='builder',optional=true}),
  spell('exori infir pug','Swift Jab',10,2000,3,1,1,1,{harmony='builder',optional=true}),
  spell('exori infir nia','Tiger Clash',25,8000,18,1,1,1,{harmony='spender',optional=true}),
  spell('utamo tio','Focus Serenity',0,600000,500,150,4,7,{support=true,optional=true,count=3}),
}
M.presets.Paladin = {
  spell('exevo mas san','Divine Caldera',150,4000,160,50,5,3),
  spell('exori dir san','Divine Barrage',130,4000,175,70,6,16,{aimed=true}),
  spell('exori dir moe','Ethereal Barrage',110,4000,135,60,6,16,{aimed=true}),
  spell('exevo tempo mas san','Divine Grenade',300,26000,160,0,6,16,{aimed=true,grenade=true}),
  spell('utevo grav san','Divine Empowerment',0,32000,500,300,6,17,{support=true}),
  spell('exori gran con','Strong Ethereal Spear',125,8000,55,90,1,7),
  spell('exori con','Ethereal Spear',65,2000,25,23,1,7),
  spell('exori san','Divine Missile',70,2000,20,40,1,4),
}
function M.find(entry)
  if (entry.itemId or 0)>100 then
    return M.items[entry.itemId] or {itemId=entry.itemId,power=50,cooldown=entry.cooldown,lock=2000}
  end
  local words=C.normalize(entry.spell)
  return M.spells[words] or {words=words,name=words,power=tonumber(entry.rotationPower) or 50,
    cooldown=entry.cooldown,lock=2000,mana=0,level=0,support=entry.category==4}

end
local function describe(entry,spec)
  return '['..spec.name..'] '..(spec.words or tostring(spec.itemId))..' ('..
    entry.count..(entry.orMore and '+' or '')..')'
end
function M.entries(vocation)
  vocation=vocation or "Sorcerer"
  local result={}
  local function add(spec)
    local entry={spell=spec.words or '',itemId=spec.itemId or 0,category=spec.category,
      patternCategory=spec.category==6 and 5 or spec.category==5 and 4 or spec.category==2 and 2 or (spec.category==3 or spec.category==4) and 3 or 1,
      pattern=spec.pattern,spellRange=spec.range or 7,count=spec.count or (vocation=="Sorcerer" and (spec.category==5 or spec.category==6) and 2 or 1),
      orMore=true,mana=1,minHp=0,maxHp=100,monsters=true,creatures='*',cooldown=spec.cooldown,
      enabled=not spec.optional,rotationPreset=M.version,
      msPreset=vocation=="Sorcerer" and M.version or nil,
      minimumHarmony=spec.harmony=="spender" and 5 or 0,
      tooltip=spec.name..'\nPvE: compara dano estimado, enemigos alcanzados y exhaust del cliente.'..
        (spec.optional and '\nOpcional: activa si lo conoces / tienes Wheel.' or '')}
    entry.description=describe(entry,spec)
    if spec.category==6 then
      local data=C.find(spec.words)
      entry.catalogGeometryVersion=C.version;entry.catalogSpell=data and data.id
      local model=C.models[spec.pattern]
      if model then entry.chainTargets=model.maxTargets;entry.chainJump=model.jump;entry.spellRange=model.range or 7 end
    end
    result[#result+1]=entry
  end
  for _,spec in ipairs(vocation=="Sorcerer" and ordered or M.presets[vocation] or {}) do add(spec) end
  if vocation=="Sorcerer" or vocation=="Druid" then for _,spec in ipairs(runeSpecs) do add(spec) end end
  return result
end
-- Lists and attack settings follow the vocation selected in the existing
-- profile. Profile name and the main on/off switch still belong to the profile.
local settingKeys={'Cooldown','ClientCooldowns','RotationMode','Rotate','ignoreMana',
  'Visible','OldSchool','pvpMode','PvpSafe','Kills','KillsAmount','BlackListSafe','AntiRsRange','Training'}
local msDefaults={Cooldown=true,ClientCooldowns=true,RotationMode='automatic',Rotate=true,
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
local function installMSPreset(config)
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

-- Import only the three newly requested vocation shelves. Existing RP/MS rows,
-- thresholds, disabled choices and profile 2-5 content remain user-owned.
function M.installPreset(config)
  local changed=installMSPreset(config)
  local profile=config.AttackBot and config.AttackBot[1]
  if not profile then return changed end
  if profile.vocationRotationsVersion~=M.version then
    C.bindVocation(profile)
    M.saveVocationSettings(profile)
    for _,vocation in ipairs({'Knight','Druid','Monk'}) do
      local previous=profile.attacksByVocation[vocation] or {}
      local keep=false
      for _,entry in ipairs(previous) do if entry.enabled or entry.rotationPreset then keep=true;break end end
      local result,present={},{}
      if keep then
        for _,entry in ipairs(previous) do
          result[#result+1]=entry
          present[(entry.itemId or 0)>100 and 'item:'..entry.itemId or C.normalize(entry.spell)]=true
        end
      end
      for _,entry in ipairs(M.entries(vocation)) do
        local key=entry.itemId>100 and 'item:'..entry.itemId or C.normalize(entry.spell)
        if not present[key] then result[#result+1]=entry;present[key]=true end
      end
      if not keep then
        for _,entry in ipairs(previous) do
          local key=(entry.itemId or 0)>100 and 'item:'..entry.itemId or C.normalize(entry.spell)
          if not present[key] then result[#result+1]=entry;present[key]=true end
        end
      end
      profile.attacksByVocation[vocation]=result
      if not keep then profile.attackSettingsByVocation[vocation]=C.copy(msDefaults) end
    end
    profile.vocationRotationsVersion=M.version
    C.bindVocation(profile)
    local settings=profile.attackSettingsByVocation[profile.selectedVocation]
    if settings then applySettings(profile,settings) end
    changed=true
  end
  -- Run inside the client so a live configuration file is never overwritten.
  -- Timing refinement leaves edited thresholds, checkboxes and spell lists alone.
  if profile.rotationTimingVersion~=M.timingVersion then
    C.bindVocation(profile)
    profile.attackSettingsByVocation=profile.attackSettingsByVocation or {}
    M.saveVocationSettings(profile)
    for vocation in pairs(M.supported) do
      local settings=profile.attackSettingsByVocation[vocation] or C.copy(msDefaults)
      settings.Cooldown=true;settings.ClientCooldowns=true
      profile.attackSettingsByVocation[vocation]=settings
    end
    local settings=profile.attackSettingsByVocation[profile.selectedVocation]
    if settings then applySettings(profile,settings) end
    profile.rotationTimingVersion=M.timingVersion
    changed=true
  end
  for _,candidate in ipairs(config.AttackBot or {}) do
    if candidate.MSAdaptive~=nil then candidate.MSAdaptive=nil;changed=true end
    if candidate.defaultVocationAttackSettings and candidate.defaultVocationAttackSettings.MSAdaptive~=nil then
      candidate.defaultVocationAttackSettings.MSAdaptive=nil;changed=true
    end
    for _,settings in pairs(candidate.attackSettingsByVocation or {}) do
      if settings.MSAdaptive~=nil then settings.MSAdaptive=nil;changed=true end
    end
  end
  return changed
end

function M.newRuntime() return {attempts={},confirmed={},blocked={},shared={},spellReadyAt={},itemReadyAt=0,sendReadyAt=0,groupReadyAt=0,harmony=0,harmonyAt=0} end
function M.confirm(runtime,words,time,vocation)
  words=C.normalize(words)
  runtime.confirmed[words]=time;runtime.attempts[words]=nil;runtime.blocked[words]=nil
  local spec=M.spells[words]
  if spec then runtime.spellReadyAt[words]=time+spec.cooldown end
  if spec and spec.shared then runtime.shared[spec.shared]=time+spec.sharedCd end
  if spec and (not vocation or M.supported[vocation]) then
    if not spec.support then runtime.groupReadyAt=time+spec.lock end
    if time-runtime.harmonyAt>15000 then runtime.harmony=0 end
    if spec.harmony=='builder' then
      runtime.harmony=math.min(5,runtime.harmony+1);runtime.harmonyAt=time
    elseif spec.harmony=='spender' then
      local reduction=2000*runtime.harmony
      for builder,data in pairs(M.spells) do
        if data.harmony=='builder' and runtime.spellReadyAt[builder] then
          runtime.spellReadyAt[builder]=math.max(time,runtime.spellReadyAt[builder]-reduction)
        end
      end
      runtime.harmony=0;runtime.harmonyAt=time
    elseif words=='utamo tio' then
      runtime.harmony=5;runtime.harmonyAt=time
      for spender,data in pairs(M.spells) do
        if data.harmony=='spender' then runtime.spellReadyAt[spender]=time end
      end
    end
  end
end
function M.attempt(runtime,words,time)
  runtime.attempts[C.normalize(words)]=time
  runtime.sendReadyAt=time+200
end
function M.wait(runtime,entry,time,nativeSecondary,nativeKnown)
  local spec=M.find(entry)
  if not spec then return math.huge end
  local readyAt=runtime.sendReadyAt
  if not nativeKnown and not spec.support then readyAt=math.max(readyAt,runtime.groupReadyAt) end
  if spec.itemId then return math.max(0,readyAt-time,runtime.itemReadyAt-time) end
  local words=spec.words
  if runtime.attempts[words] then
    if time-runtime.attempts[words]<750 then readyAt=math.max(readyAt,runtime.attempts[words]+750)
    else runtime.attempts[words]=nil;runtime.blocked[words]=time+30000 end
  end
  readyAt=math.max(readyAt,runtime.blocked[words] or 0)
  if not nativeKnown and runtime.confirmed[words] then
    local adjusted=runtime.spellReadyAt[words] or runtime.confirmed[words]+spec.cooldown
    -- Preserve a user's fallback timer while applying confirmed Monk resets.
    readyAt=math.max(readyAt,adjusted+(entry.cooldown or spec.cooldown)-spec.cooldown)
  end
  if not nativeSecondary and spec.shared then readyAt=math.max(readyAt,runtime.shared[spec.shared] or 0) end
  return math.max(0,readyAt-time)
end
function M.ready(runtime,entry,time,nativeSecondary,nativeKnown)
  return M.wait(runtime,entry,time,nativeSecondary,nativeKnown)==0
end

-- Compare the actual attack slots lost to a longer exhaust over four seconds.
-- Monk separately searches a bounded five-builder phase, recalculated per cast.
-- At full Harmony also value the builder immediately enabled by a spender.
-- Normal 2s attacks retain their damage ranking; no walk/path queries or timers.
function M.plan(candidates,context)
  local pool,index,ready={},{},{}
  for _,candidate in ipairs(candidates) do
    local key=candidate.spec.itemId and 'rune' or candidate.spec.words
    if not index[key] and #pool<24 then pool[#pool+1]=candidate;index[key]=#pool end
    if candidate.timing.ready then ready[#ready+1]=candidate end
  end
  if #ready==0 then return ready end
  local harmony=math.max(0,math.min(5,math.floor(context.harmony or 0)))
  local bonus=context.harmonyBonus or (0.07+math.max(0,context.level or 0)*0.00005)
  local function allowed(candidate,points)
    return candidate.spec.harmony~='spender' or context.harmony~=nil and points>=(candidate.entry.minimumHarmony or 5)
  end
  local function damage(candidate,points)
    local value=candidate.damage
    if candidate.spec.words=='exori gran mas nia' and points<5 then value=candidate.baseDamage end
    return value*(candidate.spec.harmony=='spender' and 1+points*bonus or 1)
  end
  local function nextAttack(first,at)
    local points=harmony
    if first.spec.harmony=='builder' then points=math.min(5,points+1)
    elseif first.spec.harmony=='spender' then points=0 end
    local best=0
    for _,second in ipairs(pool) do
      local wait=second.timing.wait
      local same=first.spec.words and first.spec.words==second.spec.words or first.spec.itemId and second.spec.itemId
      if same then wait=math.max(wait,first.timing.cooldown) end
      for key,duration in pairs(first.timing.groups or {}) do
        if second.timing.groups and second.timing.groups[key] then wait=math.max(wait,duration) end
      end
      if first.spec.harmony=='spender' and second.spec.harmony=='builder' then wait=math.max(0,wait-2000*harmony) end
      if wait<=at and allowed(second,points) then
        best=math.max(best,damage(second,points)*math.min(1,2000/second.timing.lock))
      end
    end
    return best
  end
  local bestPair,bestFirst=0,nil
  for _,candidate in ipairs(ready) do
    if allowed(candidate,harmony) and candidate.timing.lock<=2000 then
      local pair=damage(candidate,harmony)+nextAttack(candidate,2000)
      if pair>bestPair then bestPair,bestFirst=pair,candidate end
    end
  end
  local longBest,longValue=nil,0
  for _,candidate in ipairs(ready) do
    if allowed(candidate,harmony) and candidate.timing.lock>2000 then
      local value=damage(candidate,harmony)*math.min(1,4000/candidate.timing.lock)
      if value>longValue then longBest,longValue=candidate,value end
    end
  end
  -- A 4s attack competes against BOTH 2s attacks it displaces, rather than
  -- against just the first hit. Do not reorder short-only rotations.
  local preferred
  -- A Harmony phase has a real end (five points followed by a spender).
  -- Search only that phase; unlike an arbitrary long horizon, it cannot keep
  -- postponing a ready spell to improve a fictional end-of-window score.
  if context.harmony~=nil and harmony<5 then
    local builders,spenders={},{}
    for i,candidate in ipairs(pool) do
      if candidate.spec.harmony=='builder' then builders[#builders+1]=i
      elseif candidate.spec.harmony=='spender' then spenders[#spenders+1]=i end
    end
    if #builders>0 and #spenders>0 then
      local cds={}
      for i,candidate in ipairs(pool) do cds[i]=candidate.timing.wait end
      local function when(state,i)
        local at=math.max(state.t,state.cds[i])
        for key in pairs(pool[i].timing.groups or {}) do at=math.max(at,state.groups[key] or 0) end
        return at
      end
      local function step(state,i,at)
        local nextState={t=at+pool[i].timing.lock,cds={},groups={},score=state.score+damage(pool[i],0)}
        for j=1,#pool do nextState.cds[j]=state.cds[j] end
        for key,value in pairs(state.groups) do nextState.groups[key]=value end
        nextState.cds[i]=at+pool[i].timing.cooldown
        for key,duration in pairs(pool[i].timing.groups or {}) do nextState.groups[key]=at+duration end
        return nextState
      end
      local function finish(state,left)
        if left==0 then
          local best=0
          for _,i in ipairs(spenders) do
            local at=when(state,i)
            if at<=state.t+2000 then best=math.max(best,(state.score+damage(pool[i],5))*2000/(at+pool[i].timing.lock)) end
          end
          return best
        end
        local choices={}
        for _,i in ipairs(builders) do
          local at=when(state,i)
          if at<=state.t+2000 then choices[#choices+1]={i=i,at=at} end
        end
        table.sort(choices,function(a,b)
          if a.at~=b.at then return a.at<b.at end
          if pool[a.i].damage~=pool[b.i].damage then return pool[a.i].damage>pool[b.i].damage end
          return a.i<b.i
        end)
        local best=0
        for j=1,math.min(3,#choices) do
          local choice=choices[j]
          best=math.max(best,finish(step(state,choice.i,choice.at),left-1))
        end
        return best
      end
      local initial={t=0,cds=cds,groups={},score=0}
      local best=0
      for _,i in ipairs(builders) do
        if pool[i].timing.ready then
          local value=finish(step(initial,i,0),4-harmony)
          if value>best then best,preferred=value,pool[i] end
        end
      end
    end
  end
  if longBest then
    preferred=longValue>bestPair and longBest or bestFirst
  elseif harmony>=5 then
    -- Only spenders alter subsequent builder availability. Compare them with
    -- the best current builder over the same 4s window, preserving ties.
    local base=ready[1]
    if base and allowed(base,harmony) then
      local basePair=damage(base,harmony)+nextAttack(base,base.timing.lock)
      for _,candidate in ipairs(ready) do
        if candidate.spec.harmony=='spender' and allowed(candidate,harmony) then
          local pair=damage(candidate,harmony)+nextAttack(candidate,candidate.timing.lock)
          if pair>basePair then basePair,preferred=pair,candidate end
        end
      end
    end
  end
  local result={}
  if preferred then result[1]=preferred end
  for _,candidate in ipairs(ready) do
    if candidate~=preferred and allowed(candidate,harmony) then result[#result+1]=candidate end
  end
  return result
end

-- Prefer native Harmony. Older Mythic clients do not expose getHarmony:
-- keep a conservative lower bound from confirmed OWN builders/spenders, never
-- from attempts. Forget it after a 15s gap, death/PZ, or a fresh bot load.
function M.readHarmony(runtime,time,native)
  if native~=nil then
    runtime.harmony=math.max(0,math.min(5,math.floor(native)));runtime.harmonyAt=time
    return runtime.harmony
  end
  if time-runtime.harmonyAt>15000 then runtime.harmony=0 end
  return runtime.harmony
end

-- Compile the existing AttackBot masks once. Directional candidates are
-- evaluated before turning, so an unaligned beam never causes walking or a stall.
local shapeCache={}
local function shape(entry,patterns,direction)
  if entry.category==5 and entry.pattern==8 then
    local cells={}
    for dx=-1,1 do
      local x,y=dx,-1
      if direction==1 then x,y=-y,x elseif direction==2 then x,y=-x,-y elseif direction==3 then x,y=y,-x end
      cells[#cells+1]={x=x,y=y}
    end
    return cells,true
  end
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
local function countAt(entry,anchor,cells,actors,safe,canHit)
  local count,echo=0,0
  for _,actor in ipairs(actors) do
    if actor.pos then
      if safe and actor.unsafePlayer and inside(actor.pos,anchor,cells,2) then return 0,0,true end
      if matches(entry,actor) and inside(actor.pos,anchor,cells,0) and (not canHit or canHit(anchor,actor.pos)) then
        count=count+1;echo=echo+(actor.walking and 0.2 or 0.5)
      end
    end
  end
  return count,echo,false
end
function M.isDirectional(entry,patterns)
  if entry.category~=5 and entry.category~=6 then return false end
  local _,directional=shape(entry,patterns,0)
  return directional==true
end
function M.isSingleTarget(entry)
  return entry~=nil and (entry.category==1 or entry.category==3)
end
function M.rank(entries,caster,targetActor,actors,patterns,context)
  local candidates={}
  local total,screenMonsters=0,0
  for _,actor in ipairs(actors) do
    if actor.monster and not actor.summon and actor.pos and actor.pos.z==caster.z and (actor.hp or 100)>0 then
      -- Individual attacks hit one target, but their count condition describes
      -- the visible scene. Do not hide extra monsters behind HP/name/LOS filters.
      screenMonsters=screenMonsters+1
      if C.distance(caster,actor.pos)<=7 then total=total+1 end
    end
  end
  for order,entry in ipairs(entries) do
    local spec=M.find(entry)
    local harmonyAllowed=context.timing or spec.harmony~="spender" or context.harmony~=nil and context.harmony>=(entry.minimumHarmony or 5)
    local timing=entry.enabled and not spec.support and context.timing and context.timing(entry,spec)
    if entry.enabled and spec and not spec.support and harmonyAllowed and (context.timing and timing or not context.timing and context.ready(entry,spec)) and not (spec.singleOnly and total>2) then
      local function offer(amount,echo,unsafe,direction,aim)
        local conditionAmount=M.isSingleTarget(entry) and screenMonsters or amount
        local enough=entry.orMore and conditionAmount>=entry.count or not entry.orMore and conditionAmount==entry.count
        if amount==0 or not enough or unsafe then return end
        local lock=timing and timing.lock or context.lock and context.lock(entry,spec) or spec.lock
        local power=tonumber(entry.rotationPower or entry.msPower) or spec.power
        local damage=power*(amount+(spec.echo and echo or 0))
        local value=damage*2000/math.max(1000,lock or 2000)
        if spec.harmony=='spender' then
          -- Maximum Harmony is reserved for the strongest available spender.
          value=value*(1+(context.harmony or 0)*(context.harmonyBonus or 0.07+(context.level or 0)*0.00005))
        elseif spec.harmony=='builder' and context.harmony and context.harmony<5 then
          value=value+35 -- value of one generated point, regardless of hits
        end
        candidates[#candidates+1]={entry=entry,spec=spec,score=value,damage=damage,baseDamage=power*amount,timing=timing,amount=amount,order=order,direction=direction,aim=aim}
      end
      local model=entry.category==6 and C.models[entry.pattern]
      if spec.grenade and context.grenade then
        local best=context.grenade(entry)
        if best then offer(best.amount,0,false,nil,best.pos) end
      elseif model and model.chain then
        local chainActors={}
        for _,actor in ipairs(actors) do if actor.shootable~=false or actor.unsafePlayer then chainActors[#chainActors+1]=actor end end
        local amount,unsafe,hit=C.evaluate(entry,caster,targetActor,chainActors,context.direction,context.safe)
        local echo=0
        for _,actor in ipairs(hit or {}) do if matches(entry,actor) then echo=echo+(actor.walking and 0.2 or 0.375) end end
        offer(amount,echo,unsafe)
      elseif entry.category==1 or entry.category==3 then
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
            local amount,echo,unsafe=countAt(entry,caster,cells,actors,context.safe,context.canHit)
            offer(amount,echo,unsafe,directional and direction or nil)
          end
          if not directional then break end
        end
      end
    end
  end
  table.sort(candidates,function(a,b)
    if context.priorityOrder and a.order~=b.order then return a.order<b.order end
    if a.score~=b.score then return a.score>b.score end
    if a.amount~=b.amount then return a.amount>b.amount end
    local aFacing,bFacing=a.direction==context.direction,b.direction==context.direction
    if aFacing~=bFacing then return aFacing end
    if a.order~=b.order then return a.order<b.order end
    return (a.direction or -1)<(b.direction or -1)
  end)
  for i,candidate in ipairs(candidates) do candidate.rankOrder=i end
  if context.collectCandidates then return candidates end
  if context.priorityOrder then
    -- List order chooses the spell; area ranking still chooses its best aim.
    -- Never wait for a preferred spell while a lower entry is ready. Do not
    -- invoke the damage planner, which deliberately reorders automatic casts.
    local available={}
    for _,candidate in ipairs(candidates) do
      local harmonyAllowed=candidate.spec.harmony~='spender' or context.harmony~=nil and
        context.harmony>=(candidate.entry.minimumHarmony or 5)
      if harmonyAllowed and (not context.timing or candidate.timing.ready) then
        available[#available+1]=candidate
      end
    end
    return available
  end
  return context.timing and M.plan(candidates,context) or candidates
end
