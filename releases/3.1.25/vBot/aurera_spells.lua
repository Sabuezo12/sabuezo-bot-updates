-- Client-backed defaults and selected-target Barrages for this Aurera install.
-- Saved rules, learned cooldown packets and other clients keep their own data.
AureraSpellCompat = {version=1, active=HelperClientCompat and HelperClientCompat.isAurera == true}
local S, C, M = AureraSpellCompat, AttackSpellCatalog, AttackRotation
S.supportsTargetFallback=function() return false end
S.canCastAt=function() return false end
S.evaluateTarget=function() return 0,false end
S.alignMetadata=function() return 0 end
if not S.active or not C or not M then return end

local function copy(value)
  local result={}
  for key,child in pairs(value or {}) do result[key]=child end
  return result
end
local function number(value)
  value=tonumber(value)
  return value and value==value and value>=0 and value<math.huge and value or nil
end
local clientDefinitions={}

function S.alignMetadata()
  local gamelib=modules and modules.gamelib
  local defaults=gamelib and gamelib.SpellInfo and gamelib.SpellInfo.Default
  if type(defaults)~='table' then return 0 end
  local native={}
  for _,data in pairs(defaults) do
    if type(data)=='table' and type(data.words)=='string' then native[C.normalize(data.words)]=data end
  end
  clientDefinitions=native
  local changed=0
  local function align(spec)
    local data=spec and native[C.normalize(spec.words)]
    if not data then return end
    for field,source in pairs({mana='mana',level='level',cooldown='exhaustion'}) do
      local value=number(data[source])
      if value and (field~='cooldown' or value>0) and spec[field]~=value then
        spec[field]=value;changed=changed+1
      end
    end
  end
  -- These are definitions used to construct new rules; no stored entry is visited.
  for _,spec in pairs(M.spells or {}) do align(spec) end
  for _,list in pairs(M.presets or {}) do for _,spec in ipairs(list) do align(spec) end end
  for _,spec in ipairs(C.spells or {}) do align(spec) end
  S.metadataChanges=changed
  return changed
end
S.alignMetadata()
local entries=M.entries
M.entries=function(vocation)
  local result=entries(vocation)
  -- Sorcerer's ordered list is private to attack_rotation. This function
  -- returns fresh defaults, so aligning them cannot change an existing rule.
  for _,entry in ipairs(result) do
    local native=clientDefinitions[C.normalize(entry.spell)]
    local cooldown=native and number(native.exhaustion)
    if cooldown and cooldown>0 then entry.cooldown=cooldown end
  end
  return result
end

local barrageWords={['exori dir san']=true,['exori dir moe']=true}
function S.supportsTargetFallback(words)
  if not S.active or not barrageWords[C.normalize(words)] then return false end
  return type(g_game.setNextTalkAim)~='function' or g_game.getClientVersion()<1525
end
local function samePosition(a,b)
  return a and b and a.x==b.x and a.y==b.y and a.z==b.z
end

-- Ordinary spell speech uses Aurera's documented selected-target mode. Never
-- invent a cursor coordinate or fall back to the caster when the target vanished.
local function targetSnapshot(words,expected)
  if not S.supportsTargetFallback(words) then return nil end
  local ok,aim=pcall(function()
    if type(g_game.isOnline)=='function' and not g_game.isOnline() then return end
    local player=g_game.getLocalPlayer()
    local target=g_game.getAttackingCreature()
    if not player or not target or type(target.canShoot)~='function' or not target:canShoot() then return end
    local caster,position=player:getPosition(),target:getPosition()
    local id=target:getId()
    if not caster or not position or caster.z~=position.z then return end
    if type(target.getHealthPercent)=='function' and target:getHealthPercent()<=0 then return end
    local range=math.min(7,number(expected and expected.aureraRange) or 7)
    if math.max(math.abs(position.x-caster.x),math.abs(position.y-caster.y))>range then return end
    if expected then
      local expectedId=expected.aureraTargetId or expected.id
      local expectedPosition=expected.pos or expected.x and expected
      if expectedId and expectedId~=id or expectedPosition and not samePosition(position,expectedPosition) then return end
    end
    return {x=position.x,y=position.y,z=position.z,aureraTargetId=id,aureraRange=range}
  end)
  return ok and aim or nil
end

function S.canCastAt(words,aim)
  -- The ID binds the validation to the exact target used for the area count.
  return type(aim)=='table' and aim.aureraTargetId~=nil and targetSnapshot(words,aim)~=nil
end

function S.evaluateTarget(entry,caster,targetActor,actors,pvpSafe,canAim)
  if not entry or (entry.itemId or 0)>100 or not targetActor then return 0,false end
  local aim=targetSnapshot(entry.spell,targetActor)
  local read,currentCaster=pcall(function() return g_game.getLocalPlayer():getPosition() end)
  if not aim or not read or not samePosition(caster,currentCaster) then return 0,false end
  local range=math.min(7,number(entry.spellRange) or 7)
  aim.aureraRange=range
  if math.max(math.abs(aim.x-caster.x),math.abs(aim.y-caster.y))>range then return 0,false end
  if type(canAim)=='function' and not canAim(aim) then return 0,false end
  if not C.models[1] or not C.models[16] then return 0,false end
  local counted=copy(entry)
  counted.category,counted.pattern,counted.spellRange=6,1,range
  local amount,unsafe=C.evaluate(counted,caster,targetActor,actors,0,pvpSafe)
  if pvpSafe then
    -- Count the documented 13 cells; retain the wider 21-cell safety envelope
    -- and the catalog's existing two-tile player margin.
    local protected=copy(counted);protected.pattern=16
    local _,widerUnsafe=C.evaluate(protected,caster,targetActor,actors,0,true)
    unsafe=unsafe or widerUnsafe
  end
  return amount,unsafe,aim
end

-- The automatic planner normally searches arbitrary centers. Give it temporary
-- 13-cell rules and admit only the current target's cell for these two spells.
-- Preserve original entry identity for alignment, priority and user controls.
local rank=M.rank
M.rank=function(entries,caster,targetActor,actors,patterns,context)
  local original,prepared,any={},{},false
  for _,entry in ipairs(entries or {}) do
    if (entry.itemId or 0)<=100 and S.supportsTargetFallback(entry.spell) then
      local runtime=copy(entry)
      runtime.category,runtime.patternCategory,runtime.pattern=6,5,1
      original[runtime]=entry;prepared[#prepared+1]=runtime;any=true
    else prepared[#prepared+1]=entry end
  end
  if not any or not context then return rank(entries,caster,targetActor,actors,patterns,context) end
  local adapted,current=copy(context),nil
  local function permitted(entry)
    current=entry
    if not original[entry] then return true end
    local amount,unsafe,aim=S.evaluateTarget(entry,caster,targetActor,actors,context.safe,context.canAim)
    return amount>0 and not unsafe and aim~=nil
  end
  if context.timing then
    adapted.timing=function(entry,spec)
      if not permitted(entry) then return nil end
      return context.timing(entry,spec)
    end
  elseif context.ready then
    adapted.ready=function(entry,spec)
      return permitted(entry) and context.ready(entry,spec)
    end
  end
  adapted.canAim=function(position)
    if current and original[current] then
      local aim=targetSnapshot(current.spell,targetActor)
      if not aim or not samePosition(position,aim) then return false end
    end
    return type(context.canAim)=='function' and context.canAim(position) or false
  end
  local result=rank(prepared,caster,targetActor,actors,patterns,adapted)
  local currentCandidates={}
  for _,candidate in ipairs(result or {}) do
    local valid=true
    if original[candidate.entry] then
      local source=original[candidate.entry]
      local aim=targetSnapshot(source.spell,targetActor)
      candidate.entry=source
      if aim then aim.aureraRange=math.min(7,number(source.spellRange) or 7) end
      candidate.aim=aim
      valid=aim~=nil
    end
    if valid then currentCandidates[#currentCandidates+1]=candidate end
  end
  return currentCandidates
end
