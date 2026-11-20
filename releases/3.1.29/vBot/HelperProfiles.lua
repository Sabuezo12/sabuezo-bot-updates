-- Named bot profiles are independent of the client's numeric UI profiles.
-- Keep the native storage table: game_bot.save holds this exact object.
local bot = modules.game_bot
local root = g_ui.getRootWidget()
local configName = bot.contentsPanel.config:getCurrentOption().text
local base = "/bot/" .. configName .. "/_helper_profiles"
local kinds = {heal="HealBot.json", atk="AttackBot.json", supply="Supplies.json"}
local sharedKeys = {sabuezoUpdater=true}
local sharedUI = {launcherVisible=true, legacy=true, window=true, icon=true, favorites=true, panels=true, hotkey=true, sizePreset=true, appearance=true, directIconControlsVersion=true, defaultFavoritesVersion=true}
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
  if g_resources.fileExists(path) and g_resources.readFileContents(path) == data then return data end
  if g_resources.writeFileContents(path, data) == false or
    not g_resources.fileExists(path) or g_resources.readFileContents(path) ~= data then
    fail("Perfiles: no se pudo guardar. Se conservan los datos actuales.")
  end
  return data
end
-- Change 129: plain-text history of when and why a character got its profile (created, recovered,
-- index rebuilt, deleted...), so a "my settings were reset" report can be explained from the file a
-- player sends: <bot folder>/_diagnostics/perfiles.txt. Writing it can never stop the load.
local notesPath = "/bot/" .. configName .. "/_diagnostics/perfiles.txt"
local notes, alerts = {}, {}
local function note(text) notes[#notes + 1] = tostring(text) end
-- Also shown in the client log (warn) and in the Helper console once it exists.
local function alert(level, text)
  note(text)
  alerts[#alerts + 1] = {level = level, text = tostring(text)}
end
local function flushNotes()
  if #notes == 0 then return end
  local pending = notes
  notes = {}
  pcall(function()
    local header = {}
    local okDate, date = pcall(function() return os.date("%Y-%m-%d %H:%M:%S") end)
    header[#header + 1] = okDate and tostring(date) or "?"
    header[#header + 1] = "bot/" .. configName
    local okDir, dir = pcall(function() return g_resources.getWriteDir() end)
    if okDir and type(dir) == "string" then
      header[#header + 1] = "escritura " .. dir:gsub("\\", "/"):gsub("([Uu]sers/)[^/]+", "%1*")
    end
    local okVersion, version = pcall(function() return g_game.getClientVersion() end)
    if okVersion and version then header[#header + 1] = "cliente " .. tostring(version) end
    local okSlot, slot = pcall(function() return g_settings.getNumber("profile") end)
    if okSlot and slot then header[#header + 1] = "slot " .. tostring(slot) end
    header[#header + 1] = "Helper " .. tostring(RinoBotSourceVersion or "?")
    local dirPath = "/bot/" .. configName .. "/_diagnostics"
    if not g_resources.directoryExists(dirPath) then g_resources.makeDir(dirPath) end
    local lines = {}
    if g_resources.fileExists(notesPath) then
      for line in (g_resources.readFileContents(notesPath) .. "\n"):gmatch("([^\n]*)\n") do
        if line ~= "" then lines[#lines + 1] = line end
      end
    end
    lines[#lines + 1] = "== " .. table.concat(header, " | ")
    for _, line in ipairs(pending) do lines[#lines + 1] = line end
    local first = math.max(1, #lines - 400 + 1)
    g_resources.writeFileContents(notesPath, table.concat(lines, "\n", first, #lines) .. "\n")
  end)
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
local index, indexBytes
local function find(id)
  for _, entry in ipairs(index.profiles) do if entry.id == id then return entry end end
end
local function profileDir(id)
  if type(id) ~= "string" or not id:match("^p%d+$") then fail("Perfiles: identificador invalido.") end
  return base .. "/profiles/" .. id
end
local function indexProblem(current)
  if type(current) ~= "table" or (current.version ~= 1 and current.version ~= 2) or
    type(current.profiles) ~= "table" or type(current.characters) ~= "table" or
    type(current.selected) ~= "table" or type(current.nextId) ~= "number" then
    return "Perfiles: indice invalido. No se han cambiado tus ajustes."
  end
  for _, entry in ipairs(current.profiles) do
    if type(entry) ~= "table" or type(entry.id) ~= "string" or not entry.id:match("^p%d+$") then
      return "Perfiles: identificador invalido."
    end
    if type(entry.name) ~= "string" or entry.name == "" then return "Perfiles: nombre invalido." end
  end
end
local function readIndexBytes()
  if g_resources.fileExists(indexPath) then
    local bytes = g_resources.readFileContents(indexPath)
    if not bytes then fail("Perfiles: no se pudo leer el indice.") end
    return bytes
  end
  return false
end
local function refreshIndex()
  local bytes = readIndexBytes()
  if index and indexBytes == bytes then return false end
  if index and not bytes then fail("Perfiles: no se encontro el indice actual.") end
  local current
  if bytes then
    current = json.decode(bytes)
  else
    current = {version=2, nextId=1, profiles={}, characters={}, selected={}}
  end
  local problem = indexProblem(current)
  if problem then fail(problem) end
  index, indexBytes = current, bytes
  return true
end
-- Change 129: copy of the last good index; a lost or damaged index.json is rebuilt from it.
local mirrorPath = base .. "/index.backup.json"
local function mirrorIndex(bytes)
  if type(bytes) ~= "string" then return end
  pcall(function()
    if g_resources.fileExists(mirrorPath) and g_resources.readFileContents(mirrorPath) == bytes then return end
    g_resources.writeFileContents(mirrorPath, bytes)
  end)
end
local function commit(nextIndex)
  if readIndexBytes() ~= indexBytes then
    fail("Perfiles: otro cliente cambio el indice. Vuelve a intentar.")
  end
  indexBytes = write(indexPath, nextIndex)
  index = nextIndex
  mirrorIndex(indexBytes)
end
local lockPath = base .. "/index.lock"
local core = modules.corelib or {}
local nativeIO, nativeOS = core.io or io, core.os or os
local lockFile = nativeIO and nativeIO.open and nativeOS and nativeOS.time and
  g_resources.getWriteDir and g_resources.deleteFile and
  g_resources.getWriteDir():gsub("[/\\]+$", "") .. lockPath
local function acquireIndex()
  if not lockFile then return end -- Older clients still compare the original index bytes before saving.
  local ok, file, _, code = pcall(nativeIO.open, lockFile, "wx")
  if ok and file then
    local stamped, ready = pcall(function() return file:write(tostring(nativeOS.time())) and file:flush() end)
    if stamped and ready then return file end
    file:close()
    g_resources.deleteFile(lockPath)
    fail("Perfiles: no se pudo reservar el indice.")
  end
  if code == 17 or g_resources.fileExists(lockPath) then
    local readStamp, value = pcall(g_resources.readFileContents, lockPath)
    local stamp = readStamp and tonumber(value)
    -- Windows keeps the open lock file from being deleted while its owner is writing.
    if stamp and nativeOS.time() - stamp > 60 then g_resources.deleteFile(lockPath) end
    fail("Perfiles: otro cliente esta editando el indice. Vuelve a intentar.")
  end
end
local function editIndex(change)
  local lock
  local ok, a, b, c, d = pcall(function()
    lock = acquireIndex()
    refreshIndex()
    return change()
  end)
  if lock then
    lock:close()
    g_resources.deleteFile(lockPath)
  end
  if not ok then return false, tostring(a) end
  return a, b, c, d
end
-- Change 129: recovery. Before, a lost or damaged index.json (or the Helper started from a new or
-- clean folder) gave every character a brand new profile from the template: all its settings looked
-- reset although the old profile folders were still on disk. Nothing here deletes or overwrites a file:
-- adopted folders are used as they are and copies only go to new, empty folders.
local indexState = "ok" -- ok | nuevo (no index yet) | restaurado (rebuilt at this load)
local function childNames(path)
  local names = {}
  if not g_resources.directoryExists(path) then return names end
  for _, name in ipairs(g_resources.listDirectoryFiles(path, false, false)) do
    name = tostring(name):match("([^/\\]+)$")
    if name then names[#names + 1] = name end
  end
  return names
end
-- The Updater copies the whole Helper folder (with _helper_profiles) before each install.
local function updaterBackups()
  local list, home = {}, "/bot/" .. configName .. "/_updates/transactions"
  for _, name in ipairs(childNames(home)) do
    local number = tonumber(name:match("^t(%d+)$"))
    if number then list[#list + 1] = {number = number, label = "_updates/transactions/" .. name,
      root = home .. "/" .. name .. "/backup/_helper_profiles", own = true} end
  end
  table.sort(list, function(a, b) return a.number > b.number end)
  return list
end
local function profileComplete(dir)
  if not g_resources.fileExists(dir .. "/storage.json") then return false end
  for _, filename in pairs(kinds) do
    if not g_resources.fileExists(dir .. "/" .. filename) then return false end
  end
  return true
end
-- Copies into a folder that must not exist yet; an existing file is never replaced.
local function copyTree(from, to, depth)
  depth = depth or 0
  if depth > 4 then return end
  directory(to)
  for _, name in ipairs(childNames(from)) do
    local source, target = from .. "/" .. name, to .. "/" .. name
    if g_resources.fileExists(source) then
      if not g_resources.fileExists(target) then
        local bytes = g_resources.readFileContents(source)
        if g_resources.writeFileContents(target, bytes) == false or not g_resources.fileExists(target) or
          g_resources.readFileContents(target) ~= bytes then
          fail("Perfiles: no se pudo copiar " .. target)
        end
      end
    elseif g_resources.directoryExists(source) then
      copyTree(source, target, depth + 1)
    end
  end
end
local function readCandidate(path)
  if not g_resources.fileExists(path) then return nil end
  local ok, value = pcall(function() return json.decode(g_resources.readFileContents(path)) end)
  if ok and not indexProblem(value) then return value end
end
local function deletedIds(value)
  local ids = {}
  if type(value) == "table" and type(value.deleted) == "table" then
    for _, entry in ipairs(value.deleted) do
      if type(entry) == "table" and type(entry.id) == "string" then ids[entry.id] = true end
    end
  end
  return ids
end
-- The Reconect module stores the last character that played with a profile in its storage.
local function lastCharacterOf(dir)
  local ok, value = pcall(function() return json.decode(g_resources.readFileContents(dir .. "/storage.json")) end)
  local name = ok and type(value) == "table" and type(value.helperReconnect) == "table" and value.helperReconnect.lastCharacter
  if type(name) == "string" and name ~= "" and #name <= 80 and not name:find("%c") then return name end
end
local function freeName(list, wanted, id)
  local taken = {}
  for _, entry in ipairs(list) do taken[entry.name:lower()] = true end
  for _, name in ipairs({wanted or "", tostring(wanted or "Perfil") .. " (recuperado " .. id .. ")",
    "Perfil recuperado " .. id}) do
    if name ~= "" and not taken[name:lower()] then return name end
  end
  return "Perfil recuperado " .. id .. " " .. tostring(#list + 1)
end
local function nextFreeId(nextIndex)
  local id
  repeat
    id = "p" .. nextIndex.nextId
    nextIndex.nextId = nextIndex.nextId + 1
  until not g_resources.directoryExists(profileDir(id)) and not find(id)
  return id
end
-- Rebuilds index.json from the newest copy that can be read. Profile folders on disk win (they hold
-- the latest saves); a folder missing on disk comes back from the Updater backup that lists it; a
-- complete pN folder no copy lists, and not deleted on purpose, comes back under the name of the last
-- character that used it (a character with that name is linked to it again at login).
local function backupFolderFor(id)
  for _, backup in ipairs(updaterBackups()) do
    local from = backup.root .. "/profiles/" .. id
    if profileComplete(from) then return from end
  end
end
local function restoreIndex(damaged)
  local sources = {{label = "index.backup.json", index = mirrorPath}}
  for _, backup in ipairs(updaterBackups()) do
    sources[#sources + 1] = {label = backup.label, index = backup.root .. "/index.json", profiles = backup.root .. "/profiles"}
  end
  sources[#sources + 1] = {label = "migration_v1/index.json", index = base .. "/migration_v1/index.json"}
  local chosen, source
  for _, candidate in ipairs(sources) do
    chosen = readCandidate(candidate.index)
    if chosen then source = candidate; break end
  end
  local folders = {}
  for _, name in ipairs(childNames(base .. "/profiles")) do
    if name:match("^p%d+$") and profileComplete(base .. "/profiles/" .. name) then folders[#folders + 1] = name end
  end
  table.sort(folders, function(a, b) return tonumber(a:sub(2)) < tonumber(b:sub(2)) end)
  if not chosen and #folders == 0 then return false end
  local restored = {version = 2, nextId = 1, profiles = {}, characters = {}, selected = {}}
  local kept, copied, dropped, orphans = {}, {}, {}, {}
  local deleted = deletedIds(chosen)
  if chosen then
    for _, key in ipairs({"deleted", "legacyImported", "legacyProfiles", "legacyClaimed", "siblingSource"}) do
      if chosen[key] ~= nil then restored[key] = type(chosen[key]) == "table" and copy(chosen[key]) or chosen[key] end
    end
    restored.version = chosen.version
    restored.nextId = math.max(1, math.floor(chosen.nextId))
    for _, entry in ipairs(chosen.profiles) do
      local dir = profileDir(entry.id)
      if not g_resources.directoryExists(dir) then
        local from = source.profiles and source.profiles .. "/" .. entry.id
        if not (from and profileComplete(from)) then from = backupFolderFor(entry.id) end
        if from then
          copyTree(from, dir)
          copied[#copied + 1] = entry.id
        end
      end
      if profileComplete(dir) and not kept[entry.id] then
        restored.profiles[#restored.profiles + 1] = {id = entry.id, name = entry.name}
        kept[entry.id] = true
      else
        dropped[#dropped + 1] = entry.id
      end
    end
    for _, map in ipairs({"characters", "selected"}) do
      for who, id in pairs(chosen[map]) do
        if type(who) == "string" and kept[id] then restored[map][who] = id end
      end
    end
  end
  for _, id in ipairs(folders) do
    if not kept[id] and not deleted[id] then
      restored.profiles[#restored.profiles + 1] = {id = id, name = freeName(restored.profiles, lastCharacterOf(profileDir(id)), id)}
      kept[id] = true
      orphans[#orphans + 1] = id
    end
  end
  if #restored.profiles == 0 then return false end
  for id in pairs(kept) do restored.nextId = math.max(restored.nextId, tonumber(id:sub(2)) + 1) end
  for _, id in ipairs(folders) do restored.nextId = math.max(restored.nextId, tonumber(id:sub(2)) + 1) end
  local at = (os and os.time) and os.time() or nil
  restored.restoredFrom = {source = source and source.label or "carpetas de perfiles", at = at}
  local keptAs
  if damaged then
    -- The damaged index stays on disk next to the rebuilt one.
    keptAs = "index.danado-" .. tostring(at or "copia") .. ".json"
    local keep = base .. "/" .. keptAs
    if not g_resources.fileExists(keep) and (g_resources.writeFileContents(keep, damaged) == false or
      not g_resources.fileExists(keep) or g_resources.readFileContents(keep) ~= damaged) then
      fail("Perfiles: no se pudo guardar una copia del indice danado.")
    end
  end
  write(indexPath, restored)
  local names = {}
  for _, entry in ipairs(restored.profiles) do names[#names + 1] = entry.id .. " " .. entry.name end
  alert("warn", "Indice de perfiles " .. (damaged and "danado" or "perdido") .. ": reconstruido desde " ..
    restored.restoredFrom.source .. " con " .. #restored.profiles .. " perfil(es). Nada se ha borrado.")
  if keptAs then note("  el indice danado queda guardado como _helper_profiles/" .. keptAs) end
  note("  perfiles: " .. table.concat(names, ", "))
  if #copied > 0 then note("  copiados del respaldo del Updater: " .. table.concat(copied, ", ")) end
  if #orphans > 0 then note("  carpetas sin indice recuperadas: " .. table.concat(orphans, ", ")) end
  if #dropped > 0 then note("  en la copia pero sin carpeta en disco (no recuperables): " .. table.concat(dropped, ", ")) end
  return true
end
-- Startup only: same lock as editIndex, but without reading the (missing or damaged) index first.
local function restoreLocked()
  local lock
  local ok, result = pcall(function()
    lock = acquireIndex()
    local bytes = readIndexBytes()
    if bytes then
      local decoded, value = pcall(json.decode, bytes)
      if decoded and not indexProblem(value) then return "fixed" end -- another client rebuilt it a moment ago
    end
    return restoreIndex(bytes or nil)
  end)
  if lock then
    lock:close()
    g_resources.deleteFile(lockPath)
  end
  if not ok then fail(tostring(result)) end
  return result
end
-- Other bot folders of this client (an older copy of the Helper left next to a new one).
local function siblingFolders()
  local list = {}
  for _, name in ipairs(childNames("/bot")) do
    local root = "/bot/" .. name .. "/_helper_profiles"
    if name ~= configName and not name:find("[/\\%c]") and g_resources.fileExists(root .. "/index.json") then
      list[#list + 1] = {label = "bot/" .. name, root = root}
    end
  end
  return list
end
-- What was on disk when a character had to get a new profile (for _diagnostics/perfiles.txt).
local function inventory()
  local listed, folders, orphans = {}, {}, {}
  for _, entry in ipairs(index.profiles) do listed[entry.id] = true end
  local deleted = deletedIds(index)
  for _, name in ipairs(childNames(base .. "/profiles")) do
    if name:match("^p%d+$") then
      folders[#folders + 1] = name
      if not listed[name] and not deleted[name] then orphans[#orphans + 1] = name end
    end
  end
  local known = {}
  for who in pairs(index.characters) do known[#known + 1] = who end
  table.sort(known)
  local backups, mention = {}, {}
  for _, backup in ipairs(updaterBackups()) do
    backups[#backups + 1] = "t" .. backup.number
    local other = readCandidate(backup.root .. "/index.json")
    if other and other.characters[character] then mention[#mention + 1] = "t" .. backup.number .. "=" .. tostring(other.characters[character]) end
  end
  local siblings = {}
  for _, sibling in ipairs(siblingFolders()) do
    local other = readCandidate(sibling.root .. "/index.json")
    siblings[#siblings + 1] = sibling.label .. (other and other.characters[character] and " (tiene a este personaje)" or "")
  end
  return "  disco: carpetas " .. (#folders > 0 and table.concat(folders, ",") or "ninguna") ..
    " | sin indice " .. (#orphans > 0 and table.concat(orphans, ",") or "ninguna") ..
    " | personajes en el indice " .. (#known > 0 and table.concat(known, ", ") or "ninguno") ..
    " | respaldos del Updater " .. (#backups > 0 and table.concat(backups, ",") or "ninguno") ..
    (#mention > 0 and (" (con este personaje: " .. table.concat(mention, ",") .. ")") or "") ..
    " | otras carpetas del bot con perfiles " .. (#siblings > 0 and table.concat(siblings, "; ") or "ninguna")
end
-- A character missing from the index gets back the profile it had: from the Updater backups of this
-- folder (its folder adopted if it is still on disk, or copied from the backup) or, the first time a
-- folder is used, from another Helper folder of this client. Profiles deleted on purpose stay deleted.
local function recoverCharacter()
  local sources = updaterBackups()
  local siblings = siblingFolders()
  for _, sibling in ipairs(siblings) do
    if indexState == "nuevo" or sibling.label == index.siblingSource then sources[#sources + 1] = sibling end
  end
  local deleted = deletedIds(index)
  for _, source in ipairs(sources) do
    local other = readCandidate(source.root .. "/index.json")
    local id = other and other.characters[character]
    if type(id) == "string" and id:match("^p%d+$") and not deletedIds(other)[id] and not (source.own and deleted[id]) then
      local from = source.root .. "/profiles/" .. id
      if source.own and find(id) then
        alert("info", "Perfil de " .. character .. ": se vuelve a enlazar con " .. id .. " (estaba en " .. source.label .. ")")
        return id
      end
      local nextIndex = copy(index)
      local target, how
      if source.own and not g_resources.directoryExists(profileDir(id)) and profileComplete(from) then
        target, how = id, "copiado de " .. source.label
        copyTree(from, profileDir(id))
      elseif source.own and profileComplete(profileDir(id)) then
        target, how = id, "su carpeta seguia en disco (" .. source.label .. ")"
      elseif profileComplete(from) then
        target = nextFreeId(nextIndex)
        how = "copiado de " .. source.label .. "/" .. id
        copyTree(from, profileDir(target))
      end
      if target then
        nextIndex.nextId = math.max(nextIndex.nextId, tonumber(target:sub(2)) + 1)
        nextIndex.profiles[#nextIndex.profiles + 1] = {id = target, name = freeName(nextIndex.profiles, character, target)}
        if not source.own and not nextIndex.siblingSource then nextIndex.siblingSource = source.label end
        commit(nextIndex)
        alert("warn", "Perfil de " .. character .. " recuperado: " .. target .. ", " .. how .. ". No se ha creado uno por defecto.")
        return target
      end
    end
  end
  -- A new folder next to exactly one older Helper: later characters look there too.
  if indexState == "nuevo" and #siblings == 1 and not index.siblingSource then return nil, siblings[1].label end
end
-- Upgrade the initial all-shared Helper UI schema without losing an active pause
-- or saved group selection if the client reloaded during this development step.
local function migrateSharedUI()
  if index.version ~= 1 then return end
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
local function vocationDefaults(defaults)
  local ok, id = pcall(function()
    local localPlayer = g_game.getLocalPlayer()
    return localPlayer and localPlayer:getVocation()
  end)
  if ok then id=HelperClientCompat.baseVocation(id) end
  local names = {[1]="Knight",[11]="Knight",[2]="Paladin",[12]="Paladin",[3]="Sorcerer",
    [13]="Sorcerer",[4]="Druid",[14]="Druid",[5]="Monk",[15]="Monk"}
  local name = ok and names[tonumber(id)] or nil
  local preset = name and defaults.vocationDefaults and defaults.vocationDefaults[name]
  if type(preset)=="table" then
    local heal = defaults.configs.heal
    heal.healbot[1].name = name
    heal.healbot[1].spellTable = copy(preset.spells)
    -- Potions climb with the level too (HealBot uses the best one in stock).
    if type(preset.items) == "table" then heal.healbot[1].itemTable = copy(preset.items) end
    for key, value in pairs(preset.conditions) do heal.ConditionPanel[key]=value end
    defaults.configs.atk.newProfileVocation = name
    defaults.storage.initialVocation = name
    -- Settings of other modules for this vocation, e.g. Friend Healer on for Druid and Monk.
    for key, values in pairs(type(preset.storage) == "table" and preset.storage or {}) do
      if type(defaults.storage[key]) ~= "table" then defaults.storage[key] = {} end
      for field, value in pairs(values) do defaults.storage[key][field] = type(value) == "table" and copy(value) or value end
    end
  elseif not name then
    -- Vocation not known yet (Rookgaard...): the module applies its vocation default once it is.
    defaults.storage.helperNewProfile = {friendHealerByVocation = true}
  end
  return defaults
end
local function create(name, seed, why)
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
    defaults = vocationDefaults(defaults)
    -- Marks a profile made from the template, even before its vocation is known.
    defaults.configs.atk.newProfile = true
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
  -- Only a template profile gets the new TargetBot defaults (HelperProfileCatalogs.lua).
  if defaults then write(path .. "/new-profile-v1.json", {version=1}) end
  nextIndex.profiles[#nextIndex.profiles+1] = {id=id, name=name}
  commit(nextIndex)
  note("NUEVO " .. id .. ' "' .. name .. '" ' .. (preserveLegacy and "con los ajustes clasicos de este cliente" or
    "con la plantilla por defecto") .. ": " .. tostring(why or "creado a mano"))
  return id
end
local function importProfiles()
  migrateSharedUI()
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
      for _,entry in ipairs(report.profiles) do
        note("IMPORTADO " .. entry.id .. ' "' .. entry.name .. '" desde la configuracion clasica (slot ' .. entry.nativeSlot .. ")")
      end
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

  if not index.characters[character] then
    local automatic, onlySibling
    for _, entry in ipairs(index.profiles) do if entry.name == character then automatic = entry.id; break end end
    if automatic then note("ENLAZADO " .. character .. " con el perfil " .. automatic .. " de su mismo nombre") end
    if not automatic then automatic, onlySibling = recoverCharacter() end
    if not automatic then
      local why = indexState == "nuevo" and "primera carga en esta carpeta (no habia _helper_profiles/index.json)" or
        "el personaje " .. character .. " no estaba en el indice"
      local okInventory, details = pcall(inventory)
      automatic = create(character, #index.profiles == 0, why)
      note(okInventory and details or ("  inventario no disponible: " .. tostring(details)))
      alert("info", "Perfil nuevo " .. automatic .. " para " .. character .. " con la configuracion por defecto (" .. why .. ").")
    end
    local nextIndex = copy(index)
    nextIndex.characters[character] = automatic
    nextIndex.selected[character] = automatic
    if onlySibling and not nextIndex.siblingSource then nextIndex.siblingSource = onlySibling end
    commit(nextIndex)
  end
  return true
end
local function startupFail(message)
  note("ERROR al cargar " .. character .. ": " .. tostring(message))
  flushNotes()
  fail(message)
end
do
  local found, problem = g_resources.fileExists(indexPath), nil
  if found then
    local readOk, bytes = pcall(readIndexBytes)
    local decoded, value = false, nil
    if readOk and bytes then decoded, value = pcall(json.decode, bytes) end
    problem = (not readOk and tostring(bytes)) or (not decoded and "Perfiles: indice danado (" .. tostring(value) .. ").") or
      indexProblem(value)
  end
  if not found or problem then
    local restoredOk, restored = pcall(restoreLocked)
    if not restoredOk then startupFail(restored) end
    if restored == true then indexState = "restaurado"
    elseif restored == "fixed" then note("  otro cliente reconstruyo el indice en este momento")
    elseif problem then startupFail(problem .. " No hay copia del indice para reconstruirlo.")
    else indexState = "nuevo" end
  end
end
local indexRead, indexError = pcall(refreshIndex)
if not indexRead then startupFail(indexError) end
mirrorIndex(indexBytes)
if index.version == 1 or not index.characters[character] then
  local ok, message = editIndex(importProfiles)
  if not ok then startupFail(message) end
end
local automatic = index.characters[character]
if not find(automatic) then startupFail("Perfiles: el perfil del personaje no existe.") end
local active = index.selected[character] or automatic
if not find(active) then startupFail("Perfiles: el perfil seleccionado no existe.") end
local function validate(id)
  local path = profileDir(id)
  local values = read(path .. "/storage.json")
  for _, filename in pairs(kinds) do read(path .. "/" .. filename) end
  return values
end
local validated, values = pcall(validate, active)
if not validated then startupFail(values) end
do
  local entry = find(active)
  note("CARGA " .. character .. " -> " .. active .. ' "' .. tostring(entry and entry.name) .. '"' ..
    (automatic ~= active and (" (el suyo es " .. automatic .. ")") or "") .. " | indice " .. indexState)
  flushNotes()
  if #alerts > 0 then
    local shown = alerts
    alerts = {}
    for _, item in ipairs(shown) do
      if item.level == "warn" then pcall(warn, "Perfiles: " .. item.text) end
    end
    pcall(schedule, 3000, function()
      if type(RinoConsole) == "table" and type(RinoConsole.valid) == "function" and RinoConsole.valid() then
        for _, item in ipairs(shown) do
          pcall(RinoConsole.log, item.level, "Perfiles", item.text, "Detalle: _diagnostics/perfiles.txt")
        end
      end
    end)
  end
end
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
function P.refreshList()
  local ok, updated = pcall(refreshIndex)
  if ok and updated then
    P.automaticId = index.characters[character] or active
    P.revision = P.revision + 1
  end
end
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
  local ok, id = editIndex(function()
    for _, entry in ipairs(index.profiles) do
      if entry.name:lower() == name:lower() then return false, "Ya existe un perfil con ese nombre." end
    end
    return true, create(name, false, "creado a mano con Nuevo perfil")
  end)
  if ok then P.revision = P.revision + 1 end
  flushNotes()
  return ok, id
end
-- Other parts of the bot (the CaveBot route row) listen here to refresh their profile lists.
P.listeners = {}
function P.onChange(fn)
  if type(fn) == "function" then P.listeners[#P.listeners + 1] = fn end
end
local function changed()
  for _, fn in ipairs(P.listeners) do pcall(fn) end
end
-- Returns the clean name, or nil + message (+ the clashing entry when the name is taken).
local function profileName(name, exceptId)
  name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then return nil, "Escribe un nombre para el perfil." end
  if #name > 80 or name:find("%c") then return nil, "Usa un nombre corto, sin saltos de linea." end
  for _, entry in ipairs(index.profiles) do
    if entry.id ~= exceptId and entry.name:lower() == name:lower() then
      return nil, "Ya existe un perfil con ese nombre.", entry
    end
  end
  return name
end
-- Characters that use a profile: as their own (automatic) one or as their current choice.
function P.links(id)
  local names, seen = {}, {}
  for _, map in ipairs({"characters", "selected"}) do
    for who, target in pairs(index[map]) do
      if target == id and not seen[who] then seen[who] = true; names[#names + 1] = who end
    end
  end
  table.sort(names)
  return names
end
-- Takes a profile out of the list. Its folder stays on disk untouched (recorded in
-- index.deleted), so a deleted or overwritten profile can still be recovered by hand and a
-- second client still running on it keeps a valid folder. Characters that pointed to it move
-- to `replacement` (an overwrite) or, on a plain delete, to the profile they have selected.
local function retire(nextIndex, id, reason, replacement)
  local name, kept = nil, {}
  for _, entry in ipairs(nextIndex.profiles) do
    if entry.id == id then name = entry.name else kept[#kept + 1] = entry end
  end
  nextIndex.profiles = kept
  for who, target in pairs(nextIndex.characters) do
    if target == id then
      local chosen = nextIndex.selected[who]
      if who == character then chosen = active end
      nextIndex.characters[who] = replacement or (chosen ~= id and chosen) or nil
    end
  end
  for who, target in pairs(nextIndex.selected) do
    if target == id then nextIndex.selected[who] = replacement or nextIndex.characters[who] end
  end
  nextIndex.deleted = type(nextIndex.deleted) == "table" and nextIndex.deleted or {}
  nextIndex.deleted[#nextIndex.deleted + 1] = {id = id, name = name, reason = reason, replacedBy = replacement,
    at = (os and os.time) and os.time() or nil}
end
local function overwriteCheck(conflict)
  if conflict.id == active then
    return "No se puede sobrescribir el perfil activo (" .. conflict.name .. "). Cambia antes a otro."
  end
end
-- Removes a profile from the list (see retire). Never the active one, never the last one.
function P.remove(id)
  if not P.valid() then return false, "El bot ya se ha cerrado." end
  local ok, message = editIndex(function()
    if not find(id) then return false, "El perfil no esta disponible." end
    if id == active then return false, "No se puede eliminar el perfil activo. Cambia antes a otro." end
    if #index.profiles <= 1 then return false, "No se puede eliminar el ultimo perfil." end
    local nextIndex = copy(index)
    retire(nextIndex, id, "eliminado")
    commit(nextIndex)
    note("ELIMINADO " .. id .. " desde " .. character .. " (su carpeta se conserva en disco)")
    return true
  end)
  flushNotes()
  if ok then P.automaticId = index.characters[character] or active; P.revision = P.revision + 1; changed() end
  return ok, message
end
-- Renaming changes only the label: the profile keeps its id, folder and character link.
-- With overwrite, a profile already called `name` leaves the list (kept on disk) and its
-- characters move to the renamed one.
function P.rename(id, name, overwriteId)
  if not P.valid() then return false, "El bot ya se ha cerrado." end
  local ok, result, conflictName, conflictId = editIndex(function()
    if not find(id) then return false, "El perfil no esta disponible." end
    local clean, message, conflict = profileName(name, id)
    local refused = conflict and overwriteCheck(conflict)
    if refused then return false, refused end
    if conflict and overwriteId ~= conflict.id and overwriteId ~= true then
      return false, message, conflict.name, conflict.id
    end
    if conflict then clean, message = profileName(name, conflict.id) end
    if not clean then return false, message end
    local nextIndex = copy(index)
    if conflict then retire(nextIndex, conflict.id, "sobrescrito", id) end
    for _, entry in ipairs(nextIndex.profiles) do if entry.id == id then entry.name = clean end end
    commit(nextIndex)
    note("RENOMBRADO " .. id .. ' a "' .. clean .. '"' .. (conflict and (" (sobrescribe a " .. conflict.id .. ")") or ""))
    return true
  end)
  flushNotes()
  if ok then P.automaticId = index.characters[character] or active; P.revision = P.revision + 1; changed() end
  return ok, result, conflictName, conflictId
end
-- Settings that describe what the bot was doing (position to resume from, death counters,
-- task progress), not how it is set up: a copy starts without them.
local runtimeKeys = {"_cavebotResume", "caveBotSafety", "caveBotFollowPause", "caveBotTasker"}
local function copyFile(from, to)
  local bytes = g_resources.readFileContents(from)
  if g_resources.fileExists(to) and g_resources.readFileContents(to) == bytes then return end
  if g_resources.writeFileContents(to, bytes) == false or not g_resources.fileExists(to) or
    g_resources.readFileContents(to) ~= bytes then
    fail("Perfiles: no se pudo copiar " .. to)
  end
end
-- A full copy of a profile under a new name: settings, HealBot / AttackBot / Supplies and
-- this profile's own CaveBot / TargetBot folders. Data is written before the profile is
-- registered, so a failed copy never shows up as a half-made profile. It does not switch.
-- With overwrite, the copy takes the place (and the characters) of the profile already
-- called `name`; that one leaves the list but its folder stays on disk (see retire).
function P.copy(sourceId, name, overwriteId)
  if not P.valid() then return false, "El bot ya se ha cerrado." end
  local ok, result, conflictName, conflictId = editIndex(function()
    if not find(sourceId) then return false, "El perfil no esta disponible." end
    local clean, message, conflict = profileName(name, nil)
    local refused = conflict and (conflict.id == sourceId and "Es el mismo perfil que se copia. Usa otro nombre." or
      overwriteCheck(conflict))
    if refused then return false, refused end
    if conflict and overwriteId ~= conflict.id and overwriteId ~= true then
      return false, message, conflict.name, conflict.id
    end
    if conflict then clean, message = profileName(name, conflict.id) end
    if not clean then return false, message end
    if sourceId == active then
      -- What is on screen right now, not the last saved state.
      local saved, savedMessage = P.save()
      if not saved then fail(savedMessage) end
    end
    local nextIndex = copy(index)
    local id
    repeat
      id = "p" .. nextIndex.nextId
      nextIndex.nextId = nextIndex.nextId + 1
    until not g_resources.directoryExists(profileDir(id)) and not find(id)
    local from, to = profileDir(sourceId), profileDir(id)
    local values = read(from .. "/storage.json")
    for _, key in ipairs(runtimeKeys) do values[key] = nil end
    if type(values.helperUI) == "table" then
      values.helperUI.paused, values.helperUI.pausedModules, values.helperUI.pausedAt = nil, nil, nil
    end
    directory(to)
    write(to .. "/storage.json", values)
    for _, filename in pairs(kinds) do write(to .. "/" .. filename, read(from .. "/" .. filename)) end
    for _, folder in ipairs({"cavebot_configs", "targetbot_configs"}) do
      if g_resources.directoryExists(from .. "/" .. folder) then
        directory(to .. "/" .. folder)
        for _, file in ipairs(g_resources.listDirectoryFiles(from .. "/" .. folder, false, false)) do
          if file:match("%.cfg$") or file:match("%.json$") then
            copyFile(from .. "/" .. folder .. "/" .. file, to .. "/" .. folder .. "/" .. file)
          end
        end
      end
    end
    local position = #nextIndex.profiles + 1
    if conflict then
      for i, entry in ipairs(nextIndex.profiles) do if entry.id == conflict.id then position = i end end
    end
    table.insert(nextIndex.profiles, position, {id = id, name = clean})
    if conflict then retire(nextIndex, conflict.id, "sobrescrito", id) end
    commit(nextIndex)
    note("COPIA " .. id .. ' "' .. clean .. '" de ' .. sourceId .. (conflict and (" (sobrescribe a " .. conflict.id .. ")") or ""))
    return true, id
  end)
  flushNotes()
  if ok then P.automaticId = index.characters[character] or active; P.revision = P.revision + 1; changed() end
  return ok, result, conflictName, conflictId
end

-- Selection is applied by the next executor, after native refresh clears engines.
-- Never replace settings underneath running macros or closures.
function P.select(id)
  if not P.valid() then return false, "El perfil no esta disponible." end
  return editIndex(function()
    if not find(id) then return false, "El perfil no esta disponible." end
    validate(id)
    local ok, message = P.save()
    if not ok then return false, message end
    local nextIndex = copy(index)
    nextIndex.selected[character] = id
    commit(nextIndex)
    note("ELEGIDO " .. id .. " por " .. character .. " (se aplica al recargar)")
    flushNotes()
    return true
  end)
end
function P.cancelSelection(id)
  return editIndex(function()
    if index.selected[character] ~= id then return true end
    local nextIndex = copy(index)
    nextIndex.selected[character] = find(active) and active or nil
    commit(nextIndex)
    return true
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
