-- Apply the requested MythicOT rotation once, when AttackBot reads its config.
-- This avoids an open client saving its old list over an external JSON edit.
local C = AttackSpellCatalog

function C.applyMythicPaladinRotation(config, storageProfile)
  if tonumber(storageProfile) ~= 1 then return false end
  local profile = config.AttackBot and config.AttackBot[1]
  if not profile or C.normalize(profile.name) ~= "paladin" or
    profile.mythicPaladinRotation20261001 then return false end

  C.bindVocation(profile, "Paladin")
  local oldEntries = profile.attacksByVocation.Paladin
  local entries, used = {}, {}
  local function take(words, itemId)
    for i, entry in ipairs(oldEntries) do
      if not used[i] and ((itemId and entry.itemId == itemId) or
        (not itemId and C.normalize(entry.spell) == words)) then
        used[i] = true
        return C.copy(entry)
      end
    end
    local data = not itemId and C.find(words)
    return data and C.makeEntry(data) or nil
  end
  local function add(words, cooldown, count, orMore, geometry)
    local entry = take(words)
    if not entry then return end
    entry.spell, entry.enabled, entry.cooldown = words, true, cooldown
    entry.count, entry.orMore = count, orMore
    if geometry then
      entry.category, entry.patternCategory, entry.pattern = geometry[1], geometry[2], geometry[3]
    end
    entry.description = "[" .. (C.find(words) and C.models[entry.pattern].name or
      (entry.category == 5 and "Small Area" or "Target")) .. "] " .. words ..
      " (" .. count .. (orMore and "+" or "") .. ")"
    entries[#entries+1] = entry
  end

  -- Cooldowns confirmed by the user; Caldera and spears also match Mythic's web.
  add("exevo tempo mas san", 26000, 3, true, {6, 5, 16})
  add("exevo mas san", 4000, 2, true, {5, 4, 3})
  add("exori dir san", 4000, 2, true, {6, 5, 1})
  add("exori dir moe", 4000, 2, true, {6, 5, 1})
  local avalanche = take(nil, 3161)
  if avalanche then
    avalanche.enabled, avalanche.cooldown = true, 2000
    avalanche.count, avalanche.orMore = 2, true
    avalanche.description = "[Ball] Avalanche 3161 (2+)"
    entries[#entries+1] = avalanche
  end
  add("exori gran con", 8000, 1, false)
  add("exori con", 2000, 1, false)
  -- Retain other user entries, including disabled GFB/SD and custom settings.
  for i, entry in ipairs(oldEntries) do
    if not used[i] then entries[#entries+1] = C.copy(entry) end
  end
  profile.attacksByVocation.Paladin, profile.attackTable = entries, entries
  profile.Cooldown, profile.enabled = true, true
  profile.mythicPaladinRotation20261001 = true
  return true
end

-- Add support to the user's established rotation once, preserving subsequent
-- edits and every other vocation/profile. Never rewrite a live JSON externally.
function C.applyMythicDivineEmpowerment(config, storageProfile)
  if tonumber(storageProfile) ~= 1 then return false end
  local profile = config.AttackBot and config.AttackBot[1]
  if not profile or C.normalize(profile.name) ~= "paladin" or
    profile.divineEmpowermentImported20261002 then return false end
  C.bindVocation(profile)
  local oldEntries = profile.attacksByVocation and profile.attacksByVocation.Paladin
  if not oldEntries then return false end
  local entry
  local entries = {}
  for _, old in ipairs(oldEntries) do
    if C.isDivineEmpowerment(old) then
      entry = entry or C.copy(old)
    else
      entries[#entries+1] = old
    end
  end
  entry = entry or C.makeEntry(C.find("utevo grav san"), {count=3, orMore=true})
  entry.enabled, entry.cooldown = true, 32000
  entry.category, entry.patternCategory, entry.pattern = 6, 5, 17
  entry.spellRange = 3
  entry.tooltip = C.describe(C.find("utevo grav san"))
  entry.description = "[Divine Empowerment] utevo grav san (" .. entry.count .. (entry.orMore and "+" or "") .. ", 32s)"
  table.insert(entries, 1, entry)
  profile.attacksByVocation.Paladin = entries
  if profile.selectedVocation == "Paladin" then profile.attackTable = entries end
  profile.divineEmpowermentImported20261002 = true
  return true
end
