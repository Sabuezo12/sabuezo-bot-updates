-- Small read-only runtime summary. Deliberately independent of the disabled
-- full Analyzer and of inventory/container scans. No macro or game commands.
local S=RinoSkin
if not S or not S.prefix then return end
local shared=modules.game_bot
shared.rinoRpgSessions=type(shared.rinoRpgSessions)=='table' and shared.rinoRpgSessions or {}
local sessions=shared.rinoRpgSessions
local profile=HelperProfiles and tostring(HelperProfiles.activeId or '') or ''
S.Session={}
-- Only used once when upgrading an already-running XP-only session. Match
-- the existing Analyzer curve, and require it to fit the current native level.
local function experienceForLevel(level)
  return math.floor((50*level*level*level)/3-100*level*level+(850*level)/3-200)
end
local function initialLevelFromXp(baseXp,xp,level)
  if not baseXp or baseXp<0 or not xp or xp<experienceForLevel(level) or xp>=experienceForLevel(level+1)then return nil end
  local low,high=1,math.max(2,level+1)
  for _=1,24 do
    if experienceForLevel(high)>baseXp then break end
    high=high*2
  end
  if experienceForLevel(high)<=baseXp then return nil end
  while high-low>1 do
    local mid=math.floor((low+high)/2)
    if experienceForLevel(mid)<=baseXp then low=mid else high=mid end
  end
  return low
end
function S.Session.read(character,time)
  local name=character:getName()
  local key=S.prefix..profile..':'..name
  local deaths=CaveBot and CaveBot.Config and CaveBot.Config.safety and tonumber(CaveBot.Config.safety.deathCounter) or 0
  local xp=tonumber(character:getExperience())
  local level=tonumber(character:getLevel())
  if not level or level<1 then level=nil else level=math.floor(level)end
  -- Some initial packets have level but not experience yet. Do not turn that
  -- placeholder 0 into a lifetime-XP gain on the next packet.
  if not xp or xp<0 or xp==0 and (not level or level>1)then xp=nil end
  local state=sessions[key]
  if type(state)~='table' or state.version~=1 or not state.started or time<state.started then
    state={version=1,started=time,lastDeaths=deaths,deaths=0,baseXp=xp,xp=xp,baseLevel=level}
    sessions[key]=state
  end
  if deaths<state.lastDeaths then state.deaths=0
  else state.deaths=state.deaths+deaths-state.lastDeaths end
  state.lastDeaths=deaths
  if level and not state.baseLevel then
    state.baseLevel=initialLevelFromXp(tonumber(state.baseXp),xp,level)
    if not state.baseLevel then state.baseLevel=level;state.levelStarted=time end
  end
  if xp then state.baseXp=state.baseXp or xp;state.xp=xp end
  return {seconds=math.max(0,(time-state.started)/1000),deaths=state.deaths,
    levels=level and state.baseLevel and level-state.baseLevel or nil,
    baseLevel=state.baseLevel,level=level,levelStarted=state.levelStarted,
    xp=state.baseXp and state.xp and state.xp-state.baseXp or nil}
end
