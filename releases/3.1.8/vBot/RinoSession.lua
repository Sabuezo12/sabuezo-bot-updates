-- Small read-only runtime summary. Deliberately independent of the disabled
-- full Analyzer and of inventory/container scans. No macro or game commands.
local S=RinoSkin
if not S or not S.prefix then return end
local shared=modules.game_bot
shared.rinoRpgSessions=type(shared.rinoRpgSessions)=='table' and shared.rinoRpgSessions or {}
local sessions=shared.rinoRpgSessions
local profile=HelperProfiles and tostring(HelperProfiles.activeId or '') or ''
S.Session={}
function S.Session.read(character,time)
  local name=character:getName()
  local key=S.prefix..profile..':'..name
  local deaths=CaveBot and CaveBot.Config and CaveBot.Config.safety and tonumber(CaveBot.Config.safety.deathCounter) or 0
  local xp=tonumber(character:getExperience())
  local level=tonumber(character:getLevel()) or 0
  -- Some initial packets have level but not experience yet. Do not turn that
  -- placeholder 0 into a lifetime-XP gain on the next packet.
  if not xp or xp<0 or xp==0 and level>1 then xp=nil end
  local state=sessions[key]
  if type(state)~='table' or state.version~=1 or not state.started or time<state.started then
    state={version=1,started=time,lastDeaths=deaths,deaths=0,baseXp=xp,xp=xp}
    sessions[key]=state
  end
  if deaths<state.lastDeaths then state.deaths=0
  else state.deaths=state.deaths+deaths-state.lastDeaths end
  state.lastDeaths=deaths
  if xp then state.baseXp=state.baseXp or xp;state.xp=xp end
  return {seconds=math.max(0,(time-state.started)/1000),deaths=state.deaths,
    xp=state.baseXp and state.xp and state.xp-state.baseXp or nil}
end
