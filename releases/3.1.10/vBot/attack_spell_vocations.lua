-- Vocation membership from Tibia spell listings, checked 2026-10-01.
-- Used only to filter existing attacks; no new rotations or spells are created here.
local vocationWords = {
  Paladin = [=[adito grav|adito tera|adori san|exana amp res|exana ina|exana mort|exana pox|exani hur|exani tera|exeta con|exevo con|exevo con flam|exevo infir con|exevo mas san|exevo tempo mas san|exiva|exiva moe res|exori con|exori dir moe|exori dir san|exori gran con|exori infir con|exori san|exura|exura gran|exura gran san|exura infir|exura san|utamo mas sio|utamo tempo san|utani hur|uteta res sac|utevo gran lux|utevo gran res sac|utevo grav san|utevo lux|utori con|utori hur|utori san|utura|utura gran]=],
  Monk = [=[adito grav|adito tera|exana pox|exani hur|exani tera|exiva|exiva moe res|exori amp pug|exori gran mas nia|exori gran mas pug|exori gran nia|exori gran pug|exori infir amp pug|exori infir nia|exori infir pug|exori mas amp pug|exori mas nia|exori mas pug|exori mas res|exori med pug|exori nia|exori pug|exura|exura gran|exura gran tio|exura infir|exura mas nia|exura tio sio|utamo tio|utani gran hur|utani hur|uteta res tio|utevo gran lux|utevo gran res tio|utevo lux|utevo mas sio|utevo nia|utito virtu|utori kor|utori virtu|utura tio]=],
  Sorcerer = [=[adana mort|adevo grav flam|adevo grav pox|adevo grav tera|adevo grav vis|adevo mas flam|adevo mas grav flam|adevo mas grav pox|adevo mas grav vis|adevo mas hur|adevo mas vis|adevo res flam|adito grav|adito tera|adori flam|adori gran mort|adori mas flam|adori mas vis|adori min vis|adori tera|adori vis|exana pox|exana vita|exani hur|exani tera|exevo flam hur|exevo gran flam hur|exevo gran mas flam|exevo gran mas vis|exevo gran mort|exevo gran vis lux|exevo infir flam hur|exevo max mort|exevo mort ora|exevo vis hur|exevo vis lux|exiva|exiva moe res|exori amp vis|exori flam|exori frigo|exori gran flam|exori gran vis|exori infir vis|exori kor tempo|exori max flam|exori max vis|exori min flam|exori moe tempo|exori mort|exori tera|exori vis|exura|exura gran|exura infir|exura max vita|exura vita|utamo vita|utana vid|utani gran hur|utani hur|uteta flam|uteta mort|uteta res ven|uteta vis|utevo gran lux|utevo gran res ven|utevo lux|utevo res|utevo res ina|utevo vis lux|utori flam|utori mas sio|utori mort|utori vis]=],
  Druid = [=[adana ani|adana mort|adana pox|adeta sio|adevo grav flam|adevo grav pox|adevo grav vis|adevo grav vita|adevo ina|adevo mas flam|adevo mas grav flam|adevo mas grav pox|adevo mas grav vis|adevo mas hur|adevo mas pox|adevo res flam|adito grav|adito tera|adori frigo|adori mas frigo|adori mas tera|adori min vis|adori tera|adori vis|adura gran|adura vita|exana flam|exana kor|exana pox|exana vis|exana vita|exani hur|exani tera|exevo frigo hur|exevo fur frigo|exevo fur tera|exevo gran frigo hur|exevo gran mas frigo|exevo gran mas tera|exevo infir frigo hur|exevo pan|exevo tera hur|exevo ulus frigo|exevo ulus tera|exiva|exiva moe res|exori flam|exori frigo|exori gran frigo|exori gran tera|exori infir tera|exori max frigo|exori max tera|exori min flam|exori moe ico|exori tera|exori vis|exura|exura gran|exura gran mas res|exura gran sio|exura infir|exura max vita|exura sio|exura vita|utamo vita|utana vid|utani gran hur|utani hur|uteta res dru|utevo gran lux|utevo gran res dru|utevo lux|utevo res|utevo res ina|utevo vis lux|utito dru|utori pox|utura mas sio|utura sio]=],
  Knight = [=[exana kor|exana pox|exani hur|exani tera|exeta amp res|exeta res|exiva|exiva moe res|exori|exori amp kor|exori gran|exori gran ico|exori hur|exori ico|exori ico scu|exori infir min|exori mas|exori min|exori scu|exura gran ico|exura ico|exura infir ico|exura med ico|utamo tempo|utani hur|utani tempo hur|uteta res eq|utevo gran lux|utevo gran res eq|utevo lux|utito mas sio|utito tempo|utori kor|utura|utura gran]=],
}

local C = AttackSpellCatalog
C.profileVocations = {"Paladin", "Monk", "Sorcerer", "Druid", "Knight", "Personalizado"}
local memberships = {}
local function baseWords(words)
  return C.normalize(C.normalize(words):match('^[^"]+') or words)
end
for vocation, formulas in pairs(vocationWords) do
  for words in formulas:gmatch("[^|]+") do
    local key = baseWords(words)
    memberships[key] = memberships[key] or {}
    memberships[key][vocation] = true
  end
end
-- Keep older formulas used on custom servers available in their own vocation.
memberships["utito tempo san"] = {Paladin=true}
memberships["exori moe"] = {Sorcerer=true}
memberships["exori kor"] = {Sorcerer=true}

local function copy(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, child in pairs(value) do result[key] = copy(child) end
  return result
end
C.copy = copy

function C.allowed(entry, vocation)
  if vocation == "Personalizado" then return true end
  if (entry.itemId or 0) > 100 then return true end
  local data = C.find(entry.spell)
  if data then return data.vocation == vocation end
  local vocations = memberships[baseWords(entry.spell)]
  return vocations and vocations[vocation] == true or false
end

local function validVocation(vocation)
  for _, name in ipairs(C.profileVocations) do if vocation == name then return true end end
  return false
end

local function inferVocation(profile)
  local name = C.normalize(profile.name)
  for _, vocation in ipairs(C.profileVocations) do
    if name:find(vocation:lower(), 1, true) then return vocation end
  end
  local exclusive
  for _, entry in ipairs(profile.attackTable or {}) do
    if (entry.itemId or 0) <= 100 then
      local data = C.find(entry.spell)
      local vocations = data and {[data.vocation]=true} or memberships[baseWords(entry.spell)]
      local count, owner = 0, nil
      for vocation in pairs(vocations or {}) do count=count+1; owner=vocation end
      if count == 1 then
        if exclusive and exclusive ~= owner then return "Personalizado" end
        exclusive = owner
      elseif count == 0 then return "Personalizado" end
    end
  end
  return exclusive or "Personalizado"
end

function C.bindVocation(profile, vocation)
  local changed = false
  if type(profile.attacksByVocation) ~= "table" then
    profile.selectedVocation = inferVocation(profile)
    profile.attacksByVocation = {Personalizado=copy(profile.attackTable or {})}
    changed = true
  end
  vocation = vocation or profile.selectedVocation
  if not validVocation(vocation) then vocation = "Personalizado" end
  if type(profile.attacksByVocation[vocation]) ~= "table" then
    local entries, present = {}, {}
    for _, entry in ipairs(profile.attacksByVocation.Personalizado or {}) do
      if C.allowed(entry, vocation) then
        entries[#entries+1] = copy(entry)
        present[C.normalize(entry.spell)] = true
      end
    end
    for _, data in ipairs(C.list(vocation)) do
      if not present[data.words] then entries[#entries+1] = C.makeEntry(data) end
    end
    profile.attacksByVocation[vocation] = entries
    changed = true
  end
  profile.selectedVocation = vocation
  profile.attackTable = profile.attacksByVocation[vocation]
  return changed
end
