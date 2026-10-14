-- Named bot profiles are independent of the client's numeric UI profiles.
-- Keep the native storage table: game_bot.save holds this exact object.
local bot = modules.game_bot
local root = g_ui.getRootWidget()
local configName = bot.contentsPanel.config:getCurrentOption().text
local base = "/bot/" .. configName .. "/_helper_profiles"
local kinds = {heal="HealBot.json", atk="AttackBot.json", supply="Supplies.json"}
local sharedKeys = {sabuezoUpdater=true}
local sharedUI = {legacy=true, window=true, icon=true, favorites=true, panels=true, hotkey=true, sizePreset=true, appearance=true, directIconControlsVersion=true}
local interfaceLegacy = type(storage.helperUI) == "table" and storage.helperUI.legacy == true
local function fail(message) assert(false, message) end -- context.error only logs.
local character = g_game.getCharacterName()
if type(character) ~= "string" or character == "" then fail("Perfiles: no hay personaje conectado.") end

local function copy(value) return json.decode(json.encode(value)) end
local function directory(path)
  if not g_resources.directoryExists(path) then g_resources.makeDir(path) end
  if not g_resources.directoryExists(path) then fail("Perfiles: no se pudo crear la carpeta.") end
end
local function read(path, optional)
  if not g_resources.fileExists(path) then
    if optional then return nil end
    fail("Perfiles: falta un archivo de ajustes. Se conservan los datos actuales.")
  end
  local value = json.decode(g_resources.readFileContents(path))
  if type(value) ~= "table" then fail("Perfiles: archivo de ajustes invalido.") end
  return value
end
local function write(path, value)
  local data = json.encode(value, 2)
  if #data > 100 * 1024 * 1024 then fail("Perfiles: archivo demasiado grande.") end
  if g_resources.fileExists(path) and g_resources.readFileContents(path) == data then return end
  if g_resources.writeFileContents(path, data) == false or
    not g_resources.fileExists(path) or g_resources.readFileContents(path) ~= data then
    fail("Perfiles: no se pudo guardar. Se conservan los datos actuales.")
  end
end
local function snapshot()
  local values, shared = {}, {}
  for key, value in pairs(storage) do
    if key == "helperUI" and type(value) == "table" then
      values.helperUI, shared.helperUI = {}, {}
      for name, setting in pairs(value) do
        if sharedUI[name] then shared.helperUI[name] = setting else values.helperUI[name] = setting end
      end
    elseif sharedKeys[key] then shared[key] = value else values[key] = value end
  end
  return values, shared
end
directory(base); directory(base .. "/profiles")
local indexPath = base .. "/index.json"
local index = read(indexPath, true) or {version=2, nextId=1, profiles={}, characters={}, selected={}}
if (index.version ~= 1 and index.version ~= 2) or type(index.profiles) ~= "table" or type(index.characters) ~= "table" or
  type(index.selected) ~= "table" or type(index.nextId) ~= "number" then
  fail("Perfiles: indice invalido. No se han cambiado tus ajustes.")
end
local function find(id)
  for _, entry in ipairs(index.profiles) do if entry.id == id then return entry end end
end
local function profileDir(id)
  if type(id) ~= "string" or not id:match("^p%d+$") then fail("Perfiles: identificador invalido.") end
  return base .. "/profiles/" .. id
end
for _, entry in ipairs(index.profiles) do
  profileDir(entry.id)
  if type(entry.name) ~= "string" or entry.name == "" then fail("Perfiles: nombre invalido.") end
end
local function commit(nextIndex)
  write(indexPath, nextIndex)
  index = nextIndex
end
-- Upgrade the initial all-shared Helper UI schema without losing an active pause
-- or saved group selection if the client reloaded during this development step.
if index.version == 1 then
  local oldShared = read(base .. "/shared.json", true) or {}
  local oldUI = type(oldShared.helperUI) == "table" and oldShared.helperUI or {}
  local backup = base .. "/migration_v1"
  directory(backup)
  if not g_resources.fileExists(backup .. "/index.json") then write(backup .. "/index.json", index) end
  if not g_resources.fileExists(backup .. "/shared.json") then write(backup .. "/shared.json", oldShared) end
  for _, entry in ipairs(index.profiles) do
    local path = profileDir(entry.id) .. "/storage.json"
    local values = read(path)
    if not g_resources.fileExists(backup .. "/" .. entry.id .. ".json") then write(backup .. "/" .. entry.id .. ".json", values) end
    values.helperUI = type(values.helperUI) == "table" and values.helperUI or {}
    for key, value in pairs(oldUI) do
      if not sharedUI[key] and values.helperUI[key] == nil then values.helperUI[key] = value end
    end
    write(path, values)
  end
  oldShared.helperUI = copy(oldUI)
  for key in pairs(oldShared.helperUI) do if not sharedUI[key] then oldShared.helperUI[key] = nil end end
  write(base .. "/shared.json", oldShared)
  local nextIndex = copy(index); nextIndex.version = 2
  commit(nextIndex)
end
local function hasProfileValues(value)
  if type(value) ~= "table" then return value ~= nil end
  for _, child in pairs(value) do if hasProfileValues(child) then return true end end
  return false
end
local function create(name, seed)
  local nextIndex = copy(index)
  local id
  repeat
    id = "p" .. nextIndex.nextId
    nextIndex.nextId = nextIndex.nextId + 1
  until not g_resources.directoryExists(profileDir(id)) and not find(id)
  local path = profileDir(id)
  local values, shared, defaults, legacyConfigs = {}, nil, nil, {}
  local preserveLegacy = false
  if seed then
    values, shared = snapshot()
    preserveLegacy = hasProfileValues(values)
    for kind, filename in pairs(kinds) do
      local legacy = "/bot/" .. configName .. "/vBot_configs/profile_" ..
        g_settings.getNumber("profile") .. "/" .. filename
      legacyConfigs[kind] = read(legacy, true) or {}
      preserveLegacy = preserveLegacy or hasProfileValues(legacyConfigs[kind])
    end
  end
  if not preserveLegacy then
    -- A fresh first character also receives the template; actual legacy data
    -- is adopted unchanged instead. Shared UI/updater preferences stay shared.
    -- Only creation reads this template; existing profiles are never filled
    -- or reset when new defaults are added later.
    defaults = read("/bot/" .. configName .. "/vBot/HelperProfileDefaults.json")
    if defaults.schema ~= 1 or type(defaults.storage) ~= "table" or type(defaults.configs) ~= "table" then
      fail("Perfiles: la plantilla de ajustes iniciales es invalida.")
    end
    for kind in pairs(kinds) do
      if type(defaults.configs[kind]) ~= "table" then
        fail("Perfiles: falta una configuracion en la plantilla de ajustes iniciales.")
      end
    end
    values = copy(defaults.storage)
  end
  directory(path)
  -- Write data before registering the profile; a failed write cannot activate it.
  write(path .. "/storage.json", values)
  for kind, filename in pairs(kinds) do
    local config = defaults and copy(defaults.configs[kind]) or {}
    if preserveLegacy then config = legacyConfigs[kind] end
    write(path .. "/" .. filename, config)
  end
  if shared then write(base .. "/shared.json", shared) end
  nextIndex.profiles[#nextIndex.profiles+1] = {id=id, name=name}
  commit(nextIndex)
  return id
end
-- Import every occupied native slot once. Original files remain untouched.
-- Existing named profiles are authoritative; native storage is their cache.
if #index.profiles == 0 and not index.legacyImported then
  local candidates = {}
  local slot = g_settings.getNumber("profile")
  for number=1,10 do
    local values, shared, configs, originals = {}, nil, {}, {}
    local storagePath = "/bot/" .. configName .. "/storage/profile_" .. number .. ".json"
    if number == slot then
      values, shared = snapshot()
      if g_resources.fileExists(storagePath) then
        -- Validate the disk source too; never silently ignore damaged settings.
        read(storagePath)
        originals["storage/profile_" .. number .. ".json"] = g_resources.readFileContents(storagePath)
      end
    elseif g_resources.fileExists(storagePath) then
      values = read(storagePath)
      originals["storage/profile_" .. number .. ".json"] = g_resources.readFileContents(storagePath)
      -- Interface geometry and updater are already installation-wide settings.
      values.sabuezoUpdater = nil
      if type(values.helperUI) == "table" then
        for key in pairs(sharedUI) do values.helperUI[key] = nil end
      end
    end
    local occupied = hasProfileValues(values)
    for kind,filename in pairs(kinds) do
      local rel = "vBot_configs/profile_" .. number .. "/" .. filename
      local source = "/bot/" .. configName .. "/" .. rel
      configs[kind] = read(source,true) or {}
      occupied = occupied or hasProfileValues(configs[kind])
      if g_resources.fileExists(source) then originals[rel] = g_resources.readFileContents(source) end
    end
    if occupied then candidates[#candidates+1]={slot=number,values=values,shared=shared,configs=configs,originals=originals} end
  end
  -- All sources are decoded before registering even the first imported profile.
  if #candidates > 0 then
    local nextIndex = copy(index)
    nextIndex.legacyProfiles, nextIndex.legacyClaimed = {}, {}
    local report = {version=1,profiles={},activeSlot=slot,originalsPreserved=true}
    local migration = base .. "/migration_classic"
    directory(migration)
    local function parents(path)
      local current=""
      for part in path:gmatch("[^/]+") do current=current .. "/" .. part;directory(current) end
    end
    for _,candidate in ipairs(candidates) do
      for rel,data in pairs(candidate.originals) do
        local target=migration .. "/originals/" .. rel
        parents(target:match("^(.*)/[^/]+$"))
        if not g_resources.fileExists(target) then
          if g_resources.writeFileContents(target,data)==false or not g_resources.fileExists(target) or g_resources.readFileContents(target)~=data then
            fail("Perfiles: no se pudo verificar el respaldo clasico.")
          end
        end
      end
      local id
      repeat
        id="p" .. nextIndex.nextId;nextIndex.nextId=nextIndex.nextId+1
      until not g_resources.directoryExists(profileDir(id))
      local path=profileDir(id);directory(path)
      write(path .. "/storage.json",candidate.values)
      for kind,filename in pairs(kinds) do write(path .. "/" .. filename,candidate.configs[kind]) end
      local name=candidate.slot==slot and character or "Perfil clasico " .. candidate.slot
      nextIndex.profiles[#nextIndex.profiles+1]={id=id,name=name}
      nextIndex.legacyProfiles[tostring(candidate.slot)]=id
      if candidate.slot==slot then
        nextIndex.characters[character]=id;nextIndex.selected[character]=id
        nextIndex.legacyClaimed[tostring(slot)]=character
        if candidate.shared then write(base .. "/shared.json",candidate.shared) end
      end
      report.profiles[#report.profiles+1]={id=id,name=name,nativeSlot=candidate.slot}
    end
    nextIndex.legacyImported=1
    -- One index commit: failed writes leave only unregistered copies, never a
    -- half-imported chooser. Retrying allocates fresh IDs without duplication.
    write(base .. "/migration-report.json",report)
    commit(nextIndex)
  end
end

-- A newly connected character can adopt its previously unclaimed native slot.
-- Characters sharing a claimed slot receive new defaults as before.
if not index.characters[character] and type(index.legacyProfiles)=="table" then
  local key=tostring(g_settings.getNumber("profile"))
  local imported=index.legacyProfiles[key]
  local claimed=index.legacyClaimed or {}
  local matchingName=false
  for _,entry in ipairs(index.profiles) do matchingName=matchingName or entry.name==character end
  if imported and find(imported) and not claimed[key] and not matchingName then
    local nextIndex=copy(index)
    nextIndex.legacyClaimed=nextIndex.legacyClaimed or {}
    nextIndex.legacyClaimed[key]=character
    for _,entry in ipairs(nextIndex.profiles) do if entry.id==imported then entry.name=character end end
    nextIndex.characters[character]=imported;nextIndex.selected[character]=imported
    commit(nextIndex)
  end
end

local automatic = index.characters[character]
if not automatic then
  for _, entry in ipairs(index.profiles) do if entry.name == character then automatic = entry.id; break end end
  automatic = automatic or create(character, #index.profiles == 0)
  local nextIndex = copy(index)
  nextIndex.characters[character] = automatic
  nextIndex.selected[character] = automatic
  commit(nextIndex)
end
if not find(automatic) then fail("Perfiles: el perfil del personaje no existe.") end
local active = index.selected[character] or automatic
if not find(active) then fail("Perfiles: el perfil seleccionado no existe.") end
local function validate(id)
  local path = profileDir(id)
  local values = read(path .. "/storage.json")
  for _, filename in pairs(kinds) do read(path .. "/" .. filename) end
  return values
end
local values = validate(active)
local _, currentShared = snapshot()
local shared = read(base .. "/shared.json", true) or currentShared
-- Palettes have their own verified catalog; generic profile/cache saves cannot
-- drop them. Old shared preferences are adopted when there is no catalog yet.
local appearancePath = base .. "/appearance.json"
local appearanceBackup = base .. "/appearance.previous.json"
local function appearanceValue(value)
  return type(value) == "table" and type(value.saved) == "table" and
    type(value.selected) == "string" and value or nil
end
local function readAppearance(path)
  local ok, value = pcall(read, path, true)
  if not ok then warn("Apariencia: no se pudo leer el catalogo; se intentara recuperar el respaldo.") end
  return ok and appearanceValue(value) or nil
end
local sharedAppearance = type(shared.helperUI) == "table" and appearanceValue(shared.helperUI.appearance)
local appearanceSaved = readAppearance(appearancePath) or readAppearance(appearanceBackup) or sharedAppearance
appearanceSaved = appearanceSaved and copy(appearanceSaved) or nil
-- Previous hooks belong to the old executor. Remove them before installing ours.
local previous = root._sabuezoHelperProfiles
if previous and previous.dispose then previous.dispose() end
for key in pairs(storage) do storage[key] = nil end
for key, value in pairs(values) do if not sharedKeys[key] then storage[key] = value end end
storage.helperUI = type(storage.helperUI) == "table" and storage.helperUI or {}
for key, value in pairs(shared) do
  if key == "helperUI" and type(value) == "table" then
    for name, setting in pairs(value) do if sharedUI[name] then storage.helperUI[name] = setting end end
  elseif sharedKeys[key] then storage[key] = value end
end
if appearanceSaved then storage.helperUI.appearance = copy(appearanceSaved) end
storage.helperUI.legacy = interfaceLegacy -- The native loader already chose the interface.
storage._macros = type(storage._macros) == "table" and storage._macros or {}

local P = {character=character, activeId=active, automaticId=automatic, revision=1, disposed=false}
HelperProfiles = P
root._sabuezoHelperProfiles = P
function P.valid() return not P.disposed and root._sabuezoHelperProfiles == P end
function P.list()
  local list = {}
  for _, entry in ipairs(index.profiles) do list[#list+1] = {id=entry.id, name=entry.name} end
  return list
end
function P.name() local entry = find(active); return entry and entry.name or "?" end
function P.configPath(kind) return profileDir(active) .. "/" .. assert(kinds[kind]) end
local function attempt(fn)
  local ok, value = pcall(fn)
  if not ok then return false, tostring(value) end
  return true, value
end
function P.saveAppearance(value)
  if not P.valid() then return false, "Apariencia: este bot ya se ha cerrado." end
  if not appearanceValue(value) then return false, "Apariencia: catalogo invalido." end
  return attempt(function()
    local nextAppearance = copy(value)
    if appearanceSaved then write(appearanceBackup, appearanceSaved) end
    local ok, message = pcall(write, appearancePath, nextAppearance)
    if not ok then
      -- A failed/partial native write must not replace the last saved catalog.
      if appearanceSaved then pcall(write, appearancePath, appearanceSaved) end
      fail(tostring(message))
    end
    appearanceSaved = nextAppearance
    storage.helperUI.appearance = copy(nextAppearance)
  end)
end
function P.save()
  if not P.valid() then return false, "Perfiles: este bot ya se ha cerrado." end
  return attempt(function()
    local values, shared = snapshot()
    if appearanceSaved then
      shared.helperUI = type(shared.helperUI) == "table" and shared.helperUI or {}
      shared.helperUI.appearance = copy(appearanceSaved)
      -- Migrate a pre-catalog palette only when an explicit save is requested.
      if not g_resources.fileExists(appearancePath) then write(appearancePath, appearanceSaved) end
    end
    write(profileDir(active) .. "/storage.json", values)
    write(base .. "/shared.json", shared)
    local configs = {heal=HealBotConfig, atk=AttackBotConfig, supply=SuppliesConfig}
    for kind, filename in pairs(kinds) do
      local value = configs[kind]
      if type(value) == "table" then write(profileDir(active) .. "/" .. filename, value) end
    end
  end)
end
function P.create(name)
  if not P.valid() then return false, "El bot ya se ha cerrado." end
  name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then return false, "Escribe un nombre para el perfil." end
  if #name > 80 or name:find("%c") then return false, "Usa un nombre corto, sin saltos de linea." end
  for _, entry in ipairs(index.profiles) do
    if entry.name:lower() == name:lower() then return false, "Ya existe un perfil con ese nombre." end
  end
  local ok, id = attempt(function() return create(name, false) end)
  if ok then P.revision = P.revision + 1 end
  return ok, id
end
-- Selection is applied by the next executor, after native refresh clears engines.
-- Never replace settings underneath running macros or closures.
function P.select(id)
  if not P.valid() or not find(id) then return false, "El perfil no esta disponible." end
  local ok, message = attempt(function() validate(id) end)
  if not ok then return false, message end
  ok, message = P.save()
  if not ok then return false, message end
  return attempt(function()
    local nextIndex = copy(index)
    nextIndex.selected[character] = id
    commit(nextIndex)
  end)
end
function P.cancelSelection()
  return attempt(function()
    local nextIndex = copy(index)
    nextIndex.selected[character] = active
    commit(nextIndex)
  end)
end

local nativeSave, contextSave = bot.save, saveConfig
local function flush()
  local ok, message = P.save()
  if not ok then warn(message) end
end
local saveWrapper
saveWrapper = function(...)
  if P.valid() then flush() end
  if type(nativeSave) == "function" then return nativeSave(...) end
end
bot.save = saveWrapper
local contextWrapper = function(...)
  if P.valid() then flush() end
  if type(contextSave) == "function" then return contextSave(...) end
end
saveConfig = contextWrapper
function P.dispose()
  if P.disposed then return end
  P.disposed = true
  if bot.save == saveWrapper then bot.save = nativeSave end
  if saveConfig == contextWrapper then saveConfig = contextSave end
  if root._sabuezoHelperProfiles == P then root._sabuezoHelperProfiles = nil end
end
