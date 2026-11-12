-- Native creature previews. Never pass an unverified looktype to UICreature:
-- some client forks abort in C++ instead of raising a catchable Lua error.
TargetBot.Portraits = {revision=0}
local P=TargetBot.Portraits
local valid={}
if g_things and type(g_things.getThingTypes)=='function' then
  local ok,things=pcall(g_things.getThingTypes,1)
  if ok and type(things)=='table' then
    for _,thing in pairs(things) do
      local id=thing:getId()
      if type(id)=='number' and id>0 then valid[id]=true end
    end
  end
end
local function key(name)
  return tostring(name or ''):gsub('^%s+',''):gsub('%s+$',''):gsub('%s+',' '):lower()
end
local function integer(value,low,high)
  value=tonumber(value)
  if not value or value~=value or value~=math.floor(value) or value<low or value>high then return low end
  return value
end
function P.sanitize(outfit)
  if type(outfit)~='table' or not valid[outfit.type] then return nil end
  return {type=outfit.type,head=integer(outfit.head,0,132),body=integer(outfit.body,0,132),
    legs=integer(outfit.legs,0,132),feet=integer(outfit.feet,0,132),addons=integer(outfit.addons,0,3)}
end
local function signature()
  local version=g_game and g_game.getClientVersion and g_game.getClientVersion() or 0
  local dat=''
  if g_things and type(g_things.getDatSignature)=='function' then
    local ok,value=pcall(g_things.getDatSignature);if ok then dat=tostring(value) end
  end
  return tostring(version)..':'..dat
end
storage.extras=storage.extras or {}
local stored=storage.extras.targetBotPortraits
local cache={version=1,signature=signature(),outfits={}}
if type(stored)=='table' and stored.version==1 and stored.signature==cache.signature and type(stored.outfits)=='table' then
  local count=0
  for name,outfit in pairs(stored.outfits) do
    local clean=P.sanitize(outfit)
    if type(name)=='string' and #name<=128 and clean and count<1024 then
      cache.outfits[key(name)]=clean;count=count+1
    end
  end
end
storage.extras.targetBotPortraits=cache
-- Conventional Tibia appearances, used only until a live creature is seen.
-- Reference: https://github.com/hampusborgos/rme/blob/master/data/1041/creatures.xml
local defaults={
  ["badger"]={type=105},
  ["barbaria"]={type=264,head=78,body=116,legs=95,feet=121},
  ["barbarian bloodwalker"]={type=255,head=114,body=132,legs=132,feet=132},
  ["barbarian brutetamer"]={type=264,head=78,body=116,legs=95,feet=121},
  ["barbarian headsplitter"]={type=253,head=115,body=105,legs=119,feet=132},
  ["barbarian skullhunter"]={type=254,head=0,body=77,legs=77,feet=114},
  ["behemoth"]={type=55},
  ["big boss trolliver"]={type=281},
  ["blightwalker"]={type=246},
  ["bog raider"]={type=299},
  ["butterfly"]={type=227,head=20,body=30,legs=40,feet=50},
  ["cyclops"]={type=22},
  ["deer"]={type=31},
  ["defiler"]={type=238},
  ["demodras"]={type=204},
  ["demon"]={type=35},
  ["dragon"]={type=34},
  ["dragon lord"]={type=39},
  ["draken elite"]={type=362},
  ["elf"]={type=62},
  ["fire elemental"]={type=49},
  ["frost dragon"]={type=248},
  ["fury"]={type=149,head=94,body=77,legs=96,feet=0},
  ["green frog"]={type=224,head=69,body=66,legs=69,feet=66},
  ["grim reaper"]={type=300},
  ["hellhound"]={type=240},
  ["hellspawn"]={type=322},
  ["hero"]={type=73},
  ["hydra"]={type=121},
  ["leaf golem"]={type=567},
  ["medusa"]={type=330},
  ["nightmare"]={type=245},
  ["old widow"]={type=208},
  ["orc"]={type=5},
  ["orshabaal"]={type=201},
  ["quara pincher scout"]={type=77},
  ["quara predator"]={type=20},
  ["rabbit"]={type=74},
  ["rat"]={type=21},
  ["rotworm"]={type=26},
  ["serpent spawn"]={type=220},
  ["skeleton warrior"]={type=298},
  ["snake"]={type=28},
  ["son of verminor"]={type=19},
  ["the abomination"]={type=238},
  ["the old widow"]={type=208},
  ["thornback tortoise"]={type=198},
  ["troll"]={type=15},
  ["undead gladiator"]={type=306},
  ["wasp"]={type=44},
}
function P.resolve(name)
  name=key(name)
  if name=='' or name:find('[*?,]') then return nil end
  return P.sanitize(cache.outfits[name]) or P.sanitize(defaults[name])
end
function P.remember(actor)
  if not actor or not actor:isMonster() then return false end
  local name=key(actor:getName())
  if name=='' or #name>128 then return false end
  local outfit=P.sanitize(actor:getOutfit());if not outfit then return false end
  local old=cache.outfits[name]
  if old then
    local same=true
    for field,value in pairs(outfit) do if old[field]~=value then same=false;break end end
    if same then return false end
  else
    local count=0;for _ in pairs(cache.outfits) do count=count+1 end
    if count>=1024 then return false end
  end
  cache.outfits[name]=outfit;P.revision=P.revision+1
  return true
end
function P.scan()
  if type(getSpectators)~='function' then return end
  for _,actor in ipairs(getSpectators()) do P.remember(actor) end
end
if type(onCreatureAppear)=='function' then onCreatureAppear(P.remember) end
-- This runs with the editor closed too. Storage is persisted by game_bot.
macro(1500,P.scan)
P.scan()
