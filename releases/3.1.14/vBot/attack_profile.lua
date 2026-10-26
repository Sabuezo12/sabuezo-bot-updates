-- One AttackBot configuration per named character profile. Vocation shelves
-- remain editable independently; old numeric slots are retained as an archive.
AttackProfile = {}
local C, R = AttackSpellCatalog, AttackRotation
local function copy(value) return C.copy(value) end
local function defaults()
  return {enabled=false,name="Principal",attackTable={},ignoreMana=true,Kills=false,Rotate=true,
    Cooldown=true,ClientCooldowns=true,Visible=false,OldSchool=false,pvpMode=false,
    KillsAmount=1,PvpSafe=true,BlackListSafe=false,AntiRsRange=5,Training=true,RotationMode="automatic"}
end
local function currentVocation()
  local ok, id = pcall(function() return voc() end)
  return ok and ({[1]="Knight",[11]="Knight",[2]="Paladin",[12]="Paladin",[3]="Sorcerer",
    [13]="Sorcerer",[4]="Druid",[14]="Druid",[5]="Monk",[15]="Monk"})[tonumber(id)] or "Personalizado"
end
function AttackProfile.single(config)
  local profiles = config.AttackBot
  local fresh = type(profiles)~="table" or type(profiles[1])~="table"
  if fresh then
    local profile=defaults()
    profile.selectedVocation=R.supported[config.newProfileVocation] and config.newProfileVocation or currentVocation()
    profile.attacksByVocation={Personalizado={}}
    profile.attackSettingsByVocation={}
    for _, name in ipairs(C.profileVocations) do
      if name~="Personalizado" then profile.attacksByVocation[name]=R.entries(name) end
      local settings=defaults();settings.attackTable=nil
      profile.attackSettingsByVocation[name]=settings
    end
    profile.msVocationRotationVersion=R.selectorVersion
    profile.vocationRotationsVersion=R.version
    profile.rotationTimingVersion=R.timingVersion
    profile.attackCatalogVersion=C.version
    C.bindVocation(profile,profile.selectedVocation)
    config.AttackBot={profile}
  elseif config.singleProfileVersion~=1 or #profiles>1 then
    local index=tonumber(config.currentBotProfile) or 1
    local active=profiles[index] or profiles[1]
    if #profiles>1 and not config.legacyAttackProfiles then
      config.legacyAttackProfiles={version=1,selected=config.currentBotProfile,profiles=copy(profiles)}
    elseif #profiles>1 then
      config.legacyAttackProfilesAfterMigration={version=1,selected=config.currentBotProfile,profiles=copy(profiles)}
    end
    active=copy(active)
    C.bindVocation(active)
    -- Preserve the active slot's exact choices. Recover missing vocation
    -- shelves from other slots without replacing an existing (even empty) one.
    for _, previous in ipairs(profiles) do
      if type(previous)=="table" then
        local other=copy(previous);C.bindVocation(other)
        for name, entries in pairs(other.attacksByVocation) do
          if active.attacksByVocation[name]==nil then
            active.attacksByVocation[name]=copy(entries)
            if other.attackSettingsByVocation and other.attackSettingsByVocation[name] then
              active.attackSettingsByVocation=active.attackSettingsByVocation or {}
              active.attackSettingsByVocation[name]=copy(other.attackSettingsByVocation[name])
            end
          end
        end
      end
    end
    active.attackSettingsByVocation=active.attackSettingsByVocation or {}
    for _, name in ipairs(C.profileVocations) do
      if active.attacksByVocation[name]==nil then
        active.attacksByVocation[name]=name=="Personalizado" and {} or R.entries(name)
      end
      if active.attackSettingsByVocation[name]==nil then
        local settings=defaults();settings.attackTable=nil
        active.attackSettingsByVocation[name]=settings
      end
    end
    -- The copied shelves are now authoritative, including explicit OFF and
    -- empty choices. Do not run old slot-1 preset imports over these choices.
    active.msVocationRotationVersion=R.selectorVersion
    active.vocationRotationsVersion=R.version
    active.rotationTimingVersion=R.timingVersion
    active.attackCatalogVersion=C.version
    C.bindVocation(active)
    config.AttackBot={active}
  else
    config.currentBotProfile=1
    return false
  end
  config.currentBotProfile=1
  config.singleProfileVersion=1
  config.newProfileVocation=nil
  return true
end
