-- Route/target catalogs belong to a named character profile, in both interfaces.
-- Keep configDir (code/assets) and storage._configs' logical keys unchanged.
local P = assert(HelperProfiles, "Perfiles: falta el gestor de perfiles.")
assert(P.valid(), "Perfiles: el gestor ya se ha cerrado.")
local scoped = {cavebot_configs=true, targetbot_configs=true}
local base = configDir .. "/_helper_profiles"
local function directory(path)
  if not g_resources.directoryExists(path) then g_resources.makeDir(path) end
  assert(g_resources.directoryExists(path), "Perfiles: no se pudo crear " .. path)
end
local function write(path, bytes)
  assert(type(bytes)=="string" and #bytes<=100*1024*1024, "Perfiles: catalogo demasiado grande.")
  if g_resources.fileExists(path) and g_resources.readFileContents(path)==bytes then return end
  assert(g_resources.writeFileContents(path, bytes)~=false and g_resources.fileExists(path) and
    g_resources.readFileContents(path)==bytes, "Perfiles: no se pudo verificar " .. path)
end
local function readJSON(path)
  local value = json.decode(g_resources.readFileContents(path))
  assert(type(value)=="table", "Perfiles: catalogo invalido: " .. path)
  return value
end
local function profilePath(id)
  assert(type(id)=="string" and id:match("^p%d+$"), "Perfiles: identificador invalido.")
  return base .. "/profiles/" .. id
end
local function validName(name)
  return type(name)=="string" and #name>0 and name~="." and name~=".." and not name:find("[/\\%c]")
end
local function catalogFile(file)
  local name, ext = file:match("^(.*)%.([^.]+)$")
  return validName(name) and (ext=="cfg" or ext=="json")
end
-- TargetBot starts from this config in every new profile (and replaces the old shared "Todo" when
-- profiles stop sharing): the one Rod Master had. One catch-all rule; exactly its saved file.
local DEFAULT_TARGETBOT_FILE = "Todo.json"
local DEFAULT_TARGETBOT = [==[{"looting":{"everyItem":false,"minCapacity":100,"items":[],"containers":[],"maxDanger":10},"targeting":[{"antitrapBugMapDelay":600,"delayFrom":2,"closeLure":false,"danger":1,"maxDistance":10,"regex":"^.*$","dontLoot":false,"keepDistance":false,"avoidAttacks":false,"anchorRange":3,"rePositionAmount":5,"rePosition":false,"antitrapBugMap":false,"chase":true,"lure":false,"lureMax":5,"anchor":false,"rpSafe":false,"lureDelay":250,"priority":1,"lureCavebot":false,"lureCount":1,"dynamicLureDelay":true,"closeLureAmount":3,"lureMin":2,"keepDistanceRange":3,"dynamicLure":true,"name":"*"}]}]==]
-- Freeze the old common files once. Later profiles start from this snapshot,
-- never from another character's subsequently edited routes/monster rules.
local seedPath = base .. "/catalog-seed-v1.json"
local seed
if g_resources.fileExists(seedPath) then
  seed = readJSON(seedPath)
else
  seed = {version=1, catalogs={}}
  for dir in pairs(scoped) do
    local files, path = {}, configDir .. "/" .. dir
    if g_resources.directoryExists(path) then
      for _, file in ipairs(g_resources.listDirectoryFiles(path, false, false)) do
        if catalogFile(file) then files[file] = g_resources.readFileContents(path .. "/" .. file) end
      end
    end
    seed.catalogs[dir] = files
  end
  write(seedPath, json.encode(seed, 2))
end
assert(seed.version==1 and type(seed.catalogs)=="table", "Perfiles: semilla de catalogos invalida.")
for dir in pairs(scoped) do
  assert(type(seed.catalogs[dir])=="table", "Perfiles: falta un catalogo en la semilla.")
  for file, bytes in pairs(seed.catalogs[dir]) do
    assert(type(file)=="string" and catalogFile(file) and type(bytes)=="string",
      "Perfiles: archivo invalido en la semilla.")
  end
end
local receipt = "RinoBot profile catalogs v1\n"
for _, entry in ipairs(P.list()) do
  local path = profilePath(entry.id)
  local ready, pending = path .. "/catalogs-v1.ready", path .. "/catalogs-v1.pending.json"
  if g_resources.fileExists(ready) then
    assert(g_resources.readFileContents(ready)==receipt, "Perfiles: comprobante de catalogos invalido.")
  else
    local plan
    if g_resources.fileExists(pending) then
      plan = readJSON(pending)
    else
      plan = {version=1, modes={}}
      for dir in pairs(scoped) do
        plan.modes[dir] = g_resources.directoryExists(path .. "/" .. dir) and "adopt" or "seed"
      end
      -- Journal before any copies: a failed write can be retried without
      -- treating an incomplete migration as an intentionally empty catalog.
      write(pending, json.encode(plan, 2))
    end
    assert(plan.version==1 and type(plan.modes)=="table", "Perfiles: migracion invalida.")
    for dir in pairs(scoped) do
      local mode = plan.modes[dir]
      assert(mode=="adopt" or mode=="seed", "Perfiles: modo de migracion invalido.")
      directory(path .. "/" .. dir)
      if mode=="seed" and dir=="targetbot_configs" then
        -- A new profile's TargetBot is the default config, not the old common files.
        local target = path .. "/" .. dir .. "/" .. DEFAULT_TARGETBOT_FILE
        if not g_resources.fileExists(target) then write(target, DEFAULT_TARGETBOT) end
      elseif mode=="seed" then
        for file, bytes in pairs(seed.catalogs[dir]) do
          local target = path .. "/" .. dir .. "/" .. file
          if g_resources.fileExists(target) then
            assert(g_resources.readFileContents(target)==bytes,
              "Perfiles: copia incompleta o modificada; se conserva " .. target)
          else
            write(target, bytes)
          end
        end
      end
    end
    write(ready, receipt)
  end
  -- Once ready, deleted files stay deleted, including an empty catalog.
  for dir in pairs(scoped) do directory(path .. "/" .. dir) end
end

-- Where each catalog lives. Both are private to each profile: an edit in one profile never changes
-- another's. A CaveBot route is copied between profiles from the CaveBot row ("Traer ruta"). Earlier
-- versions merged both into base/shared_catalogs; the splits below give every profile its own again
-- and never delete anything (the shared folder stays as it was, the per-profile folders too).
-- base/catalogs-private.flag skips those splits: every profile then just uses its own folders.
local SHARED_RECEIPT = "RinoBot shared catalogs v1\n"
local CAVEBOT_RECEIPT = "RinoBot cavebot private v1\n"
local TARGETBOT_RECEIPT = "RinoBot targetbot private v1\n"
local sharedBase = base .. "/shared_catalogs"
local sharedReceipt = sharedBase .. "/catalogs-shared-v1.ready"
local cavebotReceipt = sharedBase .. "/cavebot-private-v1.ready"
local targetbotReceipt = base .. "/targetbot-private-v1.ready"
local targetbotBackup = base .. "/targetbot_backup_v1"
local privateFlag = base .. "/catalogs-private.flag"

local function fileParts(file) return file:match("^(.*)%.([^.]+)$") end
local function deepEqual(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not deepEqual(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end
-- Two JSON files with the same data but a different key order are the same file.
local function sameContent(a, b, ext)
  if a == b then return true end
  if ext ~= "json" then return false end
  local okA, valueA = pcall(json.decode, a)
  local okB, valueB = pcall(json.decode, b)
  return okA and okB and type(valueA)=="table" and type(valueB)=="table" and deepEqual(valueA, valueB)
end
local function nameTag(name)
  local text = tostring(name):gsub("[^%w_%-]", "_"):gsub("_+", "_"):gsub("^_", ""):gsub("_$", "")
  if text == "" then text = "perfil" end
  return text:sub(1, 20)
end
local function receiptValid(path, text)
  return g_resources.fileExists(path) and g_resources.readFileContents(path) == text
end
local function readOptionalJSON(path)
  if not g_resources.fileExists(path) then return nil end
  local ok, value = pcall(json.decode, g_resources.readFileContents(path))
  return ok and type(value) == "table" and value or nil
end
local function listCatalog(path)
  local files = {}
  if g_resources.directoryExists(path) then
    for _, file in ipairs(g_resources.listDirectoryFiles(path, false, false)) do
      if catalogFile(file) then files[file] = g_resources.readFileContents(path .. "/" .. file) end
    end
  end
  return files
end
local function sortedKeys(map)
  local keys = {}
  for key in pairs(map) do keys[#keys+1] = key end
  table.sort(keys)
  return keys
end

-- CaveBot routes were merged into the shared folder by an earlier version. Give every profile its
-- routes back: the originals are still in each profile's folder; an edit made while they were shared
-- replaces the original (it is the latest version); routes created while shared that nobody owned go
-- to the active profile; and each profile keeps the route it has selected. Idempotent, receipt last.
local function splitCavebot()
  local dir = "cavebot_configs"
  local profiles = P.list()
  local shared = listCatalog(sharedBase .. "/" .. dir)
  local origin = {}
  local data = readOptionalJSON(sharedBase .. "/migration-report.json")
  if data and type(data.entries) == "table" then
    for _, entry in ipairs(data.entries) do
      if entry.folder == dir and type(entry.file) == "string" and type(entry.shared) == "string" then
        origin[tostring(entry.profile) .. "|" .. entry.file] = entry.shared
      end
    end
  end
  local owned, restored, assigned = {}, {}, {}
  for _, profile in ipairs(profiles) do
    local mine = profilePath(profile.id) .. "/" .. dir
    directory(mine)
    for file, current in pairs(listCatalog(mine)) do
      local sharedName = origin[profile.name .. "|" .. file] or file
      owned[sharedName] = true
      local latest = shared[sharedName]
      if latest ~= nil and latest ~= current then
        write(mine .. "/" .. file, latest)
        restored[#restored+1] = {profile = profile.name, file = file}
      end
    end
  end
  -- Routes created while shared that no profile owned: they stay with the active profile.
  local activeFolder = profilePath(P.activeId) .. "/" .. dir
  directory(activeFolder)
  local activeFiles = listCatalog(activeFolder)
  local activeName
  for _, profile in ipairs(profiles) do if profile.id == P.activeId then activeName = profile.name end end
  for _, file in ipairs(sortedKeys(shared)) do
    if not owned[file] then
      local name, ext = fileParts(file)
      local target
      for attempt = 1, 50 do
        local candidate = attempt == 1 and file or (name .. "_" .. nameTag(activeName) .. (attempt > 2 and ("_" .. attempt) or "") .. "." .. ext)
        if activeFiles[candidate] == nil then
          write(activeFolder .. "/" .. candidate, shared[file])
          activeFiles[candidate] = shared[file]
          target = candidate
          break
        elseif activeFiles[candidate] == shared[file] then target = candidate; break end
      end
      assert(target, "Perfiles: demasiadas versiones de " .. file)
      assigned[#assigned+1] = {profile = activeName, file = target, reason = "creada mientras se compartia"}
    end
  end
  -- Each profile keeps the route it has selected (and the one it was running), even if another
  -- profile created it.
  for _, profile in ipairs(profiles) do
    local values = profile.id == P.activeId and storage or readOptionalJSON(profilePath(profile.id) .. "/storage.json")
    local settings = type(values) == "table" and type(values._configs) == "table" and values._configs[dir]
    local inUse = {}
    if type(settings) == "table" and type(settings.selected) == "string" then inUse[#inUse+1] = settings.selected end
    if type(values) == "table" and type(values._cavebotResume) == "table" and type(values._cavebotResume.route) == "string" then
      inUse[#inUse+1] = values._cavebotResume.route
    end
    local mine = profilePath(profile.id) .. "/" .. dir
    for _, name in ipairs(inUse) do
      if validName(name) then
        local have = listCatalog(mine)
        for _, ext in ipairs({"cfg", "json"}) do
          local file = name .. "." .. ext
          if have[name .. ".cfg"] == nil and have[name .. ".json"] == nil and shared[file] ~= nil then
            write(mine .. "/" .. file, shared[file])
            assigned[#assigned+1] = {profile = profile.name, file = file, reason = "la ruta que tenia seleccionada o en uso"}
            break
          end
        end
      end
    end
  end
  write(sharedBase .. "/cavebot-split-report.json", json.encode({version = 1, restored = restored, assigned = assigned}, 2))
  write(cavebotReceipt, CAVEBOT_RECEIPT)
  return {kind = "split", restored = #restored, assigned = #assigned}
end

-- TargetBot rules were merged into one shared folder by an earlier version (every profile ran the same
-- "Todo"). Give every profile its own again, starting from the default config (Rod Master's):
--   * nothing is deleted: everything that exists (each profile's own folder and the shared one) is
--     copied once to base/targetbot_backup_v1 first, and the shared folder stays where it is;
--   * each profile's "Todo" becomes the default; what it was running (the shared Todo) is kept next to
--     it as "Todo_anterior" when it differs;
--   * files created while shared that no profile owned go to the active profile, and a profile keeps
--     the config it has selected even if that one only existed in the shared folder.
-- Idempotent (a failed run converges on the next start); the receipt is written last.
local function writeOnce(path, bytes)
  if not g_resources.fileExists(path) then write(path, bytes) end
end
-- First free name (base, base2, base3...) in a folder listing, or the one that already holds these bytes.
local function freeName(files, name, ext, bytes)
  for attempt = 1, 50 do
    local file = (attempt == 1 and name or (name .. attempt)) .. "." .. ext
    if files[file] == nil or sameContent(files[file], bytes, ext) then return file, files[file] ~= nil end
  end
end
local function splitTargetbot()
  local dir = "targetbot_configs"
  local profiles = P.list()
  local shared = listCatalog(sharedBase .. "/" .. dir)
  local sharedTodo = shared[DEFAULT_TARGETBOT_FILE]
  -- Names the merge itself produced (its own Todo and the renamed copies): not files somebody created.
  local produced = {}
  local data = readOptionalJSON(sharedBase .. "/migration-report.json")
  if data and type(data.entries) == "table" then
    for _, entry in ipairs(data.entries) do
      if entry.folder == dir and type(entry.shared) == "string" then produced[entry.shared] = true end
    end
  end
  -- 1. Backup first, and only once: a retry after a failure in a later step must not copy the files
  -- this split wrote (Todo_anterior...) as if they were originals. The marker is written last.
  local backupDone = targetbotBackup .. "/copia-completa.ready"
  if not g_resources.fileExists(backupDone) then
    directory(targetbotBackup)
    writeOnce(targetbotBackup .. "/LEEME.txt", "Copia de seguridad de los targets de TargetBot antes de hacerlos privados por perfil.\n" ..
      "compartido = la carpeta que usaban todos los perfiles; p1, p2... = la carpeta propia de cada perfil.\n" ..
      "Para recuperar uno, copia el archivo a la carpeta targetbot_configs del perfil.\n")
    directory(targetbotBackup .. "/compartido")
    for file, bytes in pairs(shared) do writeOnce(targetbotBackup .. "/compartido/" .. file, bytes) end
    for _, profile in ipairs(profiles) do
      directory(targetbotBackup .. "/" .. profile.id)
      for file, bytes in pairs(listCatalog(profilePath(profile.id) .. "/" .. dir)) do
        writeOnce(targetbotBackup .. "/" .. profile.id .. "/" .. file, bytes)
      end
    end
    write(backupDone, "ok\n")
  end
  -- 2. Every profile: its Todo is the default; what it was running stays as Todo_anterior.
  local kept = {}
  for _, profile in ipairs(profiles) do
    local mine = profilePath(profile.id) .. "/" .. dir
    directory(mine)
    if sharedTodo ~= nil and not sameContent(sharedTodo, DEFAULT_TARGETBOT, "json") then
      local file, present = freeName(listCatalog(mine), "Todo_anterior", "json", sharedTodo)
      assert(file, "Perfiles: demasiadas versiones de Todo_anterior")
      if not present then write(mine .. "/" .. file, sharedTodo) end
      kept[#kept+1] = {profile = profile.name, file = file}
    end
    write(mine .. "/" .. DEFAULT_TARGETBOT_FILE, DEFAULT_TARGETBOT)
  end
  -- 3. Files created while shared that no profile owned: they stay with the active profile.
  local activeFolder = profilePath(P.activeId) .. "/" .. dir
  directory(activeFolder)
  local activeFiles = listCatalog(activeFolder)
  local activeName
  for _, profile in ipairs(profiles) do if profile.id == P.activeId then activeName = profile.name end end
  local assigned = {}
  for _, file in ipairs(sortedKeys(shared)) do
    if file ~= DEFAULT_TARGETBOT_FILE and not produced[file] then
      local name, ext = fileParts(file)
      local target, present = freeName(activeFiles, name, ext, shared[file])
      assert(target, "Perfiles: demasiadas versiones de " .. file)
      if not present then
        write(activeFolder .. "/" .. target, shared[file])
        activeFiles[target] = shared[file]
      end
      assigned[#assigned+1] = {profile = activeName, file = target, reason = "creado mientras se compartia"}
    end
  end
  -- 4. A profile keeps the config it has selected, even if only the shared folder had it.
  for _, profile in ipairs(profiles) do
    local values = profile.id == P.activeId and storage or readOptionalJSON(profilePath(profile.id) .. "/storage.json")
    local settings = type(values) == "table" and type(values._configs) == "table" and values._configs[dir]
    local selected = type(settings) == "table" and settings.selected
    if type(selected) == "string" and validName(selected) then
      local mine = profilePath(profile.id) .. "/" .. dir
      local have = listCatalog(mine)
      if have[selected .. ".json"] == nil and have[selected .. ".cfg"] == nil then
        for _, ext in ipairs({"json", "cfg"}) do
          local file = selected .. "." .. ext
          if shared[file] ~= nil then
            write(mine .. "/" .. file, shared[file])
            assigned[#assigned+1] = {profile = profile.name, file = file, reason = "el target que tenia seleccionado"}
            break
          end
        end
      end
    end
  end
  write(base .. "/targetbot-split-report.json", json.encode({version = 1, backup = "_helper_profiles/targetbot_backup_v1",
    kept = kept, assigned = assigned}, 2))
  write(targetbotReceipt, TARGETBOT_RECEIPT)
  return {kind = "targetbot", profiles = #profiles, kept = #kept, assigned = #assigned}
end

-- Run the pending splits once. A fresh install, or one that never shared anything, has nothing to move:
-- every profile already owns its folders (a new profile starts on the default TargetBot config).
if not g_resources.fileExists(privateFlag) then
  local ok, result = pcall(function()
    if receiptValid(targetbotReceipt, TARGETBOT_RECEIPT) then return nil end
    if not receiptValid(sharedReceipt, SHARED_RECEIPT) then
      write(targetbotReceipt, TARGETBOT_RECEIPT)
      return nil
    end
    local outcome = {}
    if not receiptValid(cavebotReceipt, CAVEBOT_RECEIPT) then outcome[#outcome+1] = splitCavebot() end
    outcome[#outcome+1] = splitTargetbot()
    return outcome
  end)
  if ok then
    if result and type(schedule) == "function" then
      for _, done in ipairs(result) do
        local text, detail
        if done.kind == "split" then
          text = "Rutas de CaveBot: vuelven a ser privadas por perfil"
          detail = done.restored .. " ruta(s) con cambios recuperadas, " .. done.assigned ..
            " asignada(s). Detalle: _helper_profiles/shared_catalogs/cavebot-split-report.json"
        else
          text = "TargetBot: cada perfil tiene el suyo (config de Rod Master)"
          detail = "Antes lo compartian todos. Lo que usaban queda como Todo_anterior" ..
            (done.assigned > 0 and (" y " .. done.assigned .. " target(s) creado(s) mientras se compartia pasan al perfil activo") or "") ..
            ". Copia de seguridad: _helper_profiles/targetbot_backup_v1"
        end
        -- Say once, after the console exists, what was done.
        pcall(schedule, 3000, function()
          if type(RinoConsole) == "table" and type(RinoConsole.valid) == "function" and RinoConsole.valid() then
            RinoConsole.log("info", "Perfiles", text, detail)
          end
        end)
      end
    end
  else
    warn("Perfiles: no se pudieron preparar las rutas y targets (" .. tostring(result) ..
      "); cada perfil usa los suyos hasta que se repare.")
  end
end
local perProfile = "_helper_profiles/profiles/" .. P.activeId .. "/"
local function relativeFor(dir)
  return perProfile
end
local native = {}
for _, key in ipairs({"exist", "create", "list", "load", "loadRaw", "save", "remove", "setup"}) do
  native[key] = assert(Config[key])
end
for _, key in ipairs({"exist", "create", "load", "loadRaw", "save", "remove"}) do
  local original = native[key]
  Config[key] = function(dir, ...)
    if not scoped[dir] then return original(dir, ...) end
    if not P.valid() then return nil end
    if key=="load" or key=="loadRaw" or key=="save" or key=="remove" then
      assert(validName((...)), "Perfiles: nombre de configuracion invalido.")
    end
    return original(relativeFor(dir) .. dir, ...)
  end
end
Config.list = function(dir)
  if not scoped[dir] then return native.list(dir) end
  if not P.valid() then return {} end
  local list, seen = {}, {}
  for _, file in ipairs(g_resources.listDirectoryFiles(configDir .. "/" .. relativeFor(dir) .. dir, false, false)) do
    if catalogFile(file) then
      local name = file:gsub("%.[^.]+$", "")
      if not seen[name] then list[#list+1]=name; seen[name]=true end
    end
  end
  table.sort(list)
  return list
end
-- Consumers must use the same resolver as the editor/recorder, including
-- setprofile actions, loot defaults and supplies/depot's TargetBot reader.
Config.fileExists = function(dir, name, extension)
  if not scoped[dir] or not P.valid() or not validName(name) then return false end
  if extension~=nil and extension~="json" and extension~="cfg" then return false end
  local path = configDir .. "/" .. relativeFor(dir) .. dir .. "/" .. name
  if extension then return g_resources.fileExists(path .. "." .. extension) end
  return g_resources.fileExists(path .. ".json") or g_resources.fileExists(path .. ".cfg")
end

local function consoleLog(level, message, detail)
  if type(RinoConsole) ~= "table" or type(RinoConsole.valid) ~= "function" then return end
  local ok, valid = pcall(RinoConsole.valid)
  if ok and valid then pcall(RinoConsole.log, level, "CaveBot", message, detail) end
end

-- Native Config.setup's Add callback writes configDir directly. Provide the
-- same interface here so dialogs, edits and deletes all use the right scope.
Config.setup = function(dir, widget, extension, callback)
  if not scoped[dir] then return native.setup(dir, widget, extension, callback) end
  assert(extension=="cfg" or extension=="json", "Perfiles: extension invalida.")
  storage._configs = type(storage._configs)=="table" and storage._configs or {}
  storage._configs[dir] = type(storage._configs[dir])=="table" and storage._configs[dir] or {enabled=false, selected=""}
  local settings = storage._configs[dir]
  widget.switch:setOn(settings.enabled==true)
  local refreshing = false
  local function refresh()
    if not P.valid() then return end
    refreshing = true
    local configs, index = Config.list(dir), 1
    widget.list:clear()
    for i, name in ipairs(configs) do
      widget.list:addOption(name)
      if name==settings.selected then index=i end
    end
    local data
    if #configs>0 then
      widget.list:setCurrentIndex(index)
      settings.selected = configs[index]
      data = Config.load(dir, settings.selected)
    else
      settings.selected = nil
    end
    settings.enabled = widget.switch:isOn()
    refreshing = false
    callback(settings.selected, settings.enabled, data)
  end
  -- Rebuild the route list without reloading the running route.
  local function relist()
    if not P.valid() then return end
    refreshing = true
    local configs, index = Config.list(dir), 1
    widget.list:clear()
    for i, name in ipairs(configs) do
      widget.list:addOption(name)
      if name==settings.selected then index=i end
    end
    if #configs>0 then widget.list:setCurrentIndex(index) end
    refreshing = false
  end
  widget.list.onOptionChange = function(list)
    if not P.valid() or refreshing then return end
    local option = list:getCurrentOption()
    settings.selected = option and option.text or nil
    refresh()
  end
  widget.switch.onClick = function()
    if not P.valid() then return end
    widget.switch:setOn(not widget.switch:isOn())
    refresh()
  end
  widget.add.onClick = function()
    if not P.valid() then return end
    UI.SinglelineEditorWindow("config_name", {title="Enter config name"}, function(name)
      if not P.valid() then return end
      name = tostring(name or ""):gsub("%s+", "_")
      if not validName(name) or #name>=30 then return error("Invalid config name") end
      if Config.fileExists(dir, name) then return error("Config " .. name .. " already exists") end
      if not Config.save(dir, name, {}, extension) then return end
      settings.selected = name
      widget.switch:setOn(false)
      refresh()
    end)
  end
  widget.edit.onClick = function()
    local name = settings.selected
    if not P.valid() or not name then return end
    local heading = (dir == "cavebot_configs" and "Editar ruta: " or "Editar target: ") .. name
    -- CaveBot routes open as colored lines (Helper); TargetBot and the classic client keep the text editor.
    UI.MultilineEditorWindow(Config.loadRaw(dir, name), {title=heading, lines=(dir == "cavebot_configs")}, function(value)
      if not P.valid() then return end
      local data = Config.parse(value)
      if type(data)~="table" then return end
      if Config.save(dir, name, data, extension) then refresh() end
    end)
  end
  widget.remove.onClick = function()
    local name = settings.selected
    if not P.valid() or not name then return end
    UI.ConfirmationWindow("Config removal", "Do you want to remove config " .. name .. " from " .. dir .. "?", function()
      if not P.valid() then return end
      Config.remove(dir, name)
      widget.switch:setOn(false)
      refresh()
    end)
  end

  -- CaveBot's route row: "Renombrar" and "Copiar a" exist only in that row's widget.
  local function routeFile(name)
    for _, ext in ipairs({"cfg", "json"}) do
      local path = configDir .. "/" .. relativeFor(dir) .. dir .. "/" .. name .. "." .. ext
      if g_resources.fileExists(path) then return path, ext end
    end
  end
  local function trimmed(text) return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
  if widget.rename then
    -- set profile actions in this profile's other routes keep pointing at the renamed route.
    local function repointRoutes(old, new)
      local folder = configDir .. "/" .. relativeFor(dir) .. dir
      for _, file in ipairs(g_resources.listDirectoryFiles(folder, false, false)) do
        if file:match("%.cfg$") then
          local bytes = g_resources.readFileContents(folder .. "/" .. file)
          local changed = false
          local out = ("\n" .. bytes):gsub("(\n)setprofile:([^\r\n]*)", function(newline, value)
            if trimmed(value) == old then changed = true; return newline .. "setprofile:" .. new end
          end)
          if changed then write(folder .. "/" .. file, out:sub(2)) end
        end
      end
    end
    local function renameRoute(text)
      local old = settings.selected
      if not old then return false, "Elige una ruta primero." end
      local new = trimmed(text):gsub("%s+", "_")
      if new == "" then return false, "Escribe un nombre para la ruta." end
      if #new >= 30 then return false, "Usa un nombre de menos de 30 caracteres." end
      if not validName(new) or new:find('[/\\:*?"<>|]') then return false, "Evita / \\ : * ? y otros caracteres de archivo." end
      if new == old then return false, "Es el mismo nombre." end
      for _, existing in ipairs(Config.list(dir)) do
        if existing:lower() == new:lower() then return false, "Ya existe una ruta con ese nombre." end
      end
      local path, ext = routeFile(old)
      if not path then return false, "No se encuentra la ruta " .. old .. "." end
      write(configDir .. "/" .. relativeFor(dir) .. dir .. "/" .. new .. "." .. ext, g_resources.readFileContents(path))
      Config.remove(dir, old)
      repointRoutes(old, new)
      if type(storage._cavebotResume) == "table" and storage._cavebotResume.route == old then storage._cavebotResume.route = new end
      settings.selected = new
      refresh()
      consoleLog("action", "Ruta " .. old .. " renombrada a " .. new)
      return true
    end
    widget.rename.onClick = function()
      local current = settings.selected
      if not P.valid() or not current then return end
      local H = Helper
      if H and type(H.valid) == "function" and H.valid() and type(H.editText) == "function" and H.modules and H.modules.cavebot then
        local previous = H.textOwner
        H.textOwner = H.modules.cavebot
        local dialog
        dialog = H.editText(current, {title = "Renombrar ruta", description = "Nuevo nombre para la ruta " .. current .. ".", multiline = false}, function(text)
          local ok, message = renameRoute(text)
          if not ok then
            if dialog and dialog.feedback then dialog.feedback:setText(tostring(message)) end
            return false
          end
          return true
        end)
        H.textOwner = previous
        if dialog and dialog.accept then dialog.accept:setText("Renombrar") end
      else
        UI.SinglelineEditorWindow(current, {title = "Renombrar ruta"}, function(text)
          local ok, message = renameRoute(text)
          if not ok then return error(message) end
        end)
      end
    end
  end

  if widget.copyTo then
    -- The selector keeps its id (copyTo) but now PULLS. Step 1: choose a profile (only the OTHER
    -- profiles that have routes). Step 2: a menu opens with just that profile's routes and "Traer
    -- todas"; the chosen one is copied into this profile. "Duplicar esta ruta" duplicates the shown route
    -- inside this profile. Nothing is ever written to another profile.
    local label = "Traer ruta"
    local filling, stamp = false, 0
    -- Short feedback on the button itself.
    local function flash(text)
      stamp = stamp + 1
      local mine = stamp
      widget.copyTo:setText(text)
      if type(schedule) == "function" then
        pcall(schedule, 2500, function()
          if stamp == mine and P.valid() then widget.copyTo:setText(label) end
        end)
      end
    end
    local function routeNames(folder)
      local names, seen = {}, {}
      if g_resources.directoryExists(folder) then
        for _, file in ipairs(g_resources.listDirectoryFiles(folder, false, false)) do
          local name = catalogFile(file) and fileParts(file)
          if name and not seen[name] then seen[name] = true; names[#names + 1] = name end
        end
      end
      table.sort(names, function(x, y) return x:lower() < y:lower() end)
      return names
    end
    -- Rebuilt on load, when the profile list changes and every time the selector is opened, because
    -- another client (another character) can add routes to its own profile at any time.
    local function fillTargets()
      if not P.valid() then return end
      filling = true
      widget.copyTo:clearOptions()
      widget.copyTo:addOption(label, "none")
      widget.copyTo:addOption("Duplicar esta ruta", "self")
      for _, entry in ipairs(P.list()) do
        if entry.id ~= P.activeId then
          local count = #routeNames(profilePath(entry.id) .. "/" .. dir)
          if count > 0 then widget.copyTo:addOption(entry.name .. " (" .. count .. ")", "profile:" .. entry.id) end
        end
      end
      widget.copyTo:setCurrentIndex(1)
      filling = false
    end
    -- A copy never overwrites a route of the same name (Windows ignores case): a clash becomes
    -- name_copia, name_copia2...
    local function freeName(folder, name)
      local taken = {}
      for _, existing in ipairs(routeNames(folder)) do taken[existing:lower()] = true end
      local copyName = name
      if taken[copyName:lower()] then
        copyName = name .. "_copia"
        local number = 2
        while taken[copyName:lower()] do copyName = name .. "_copia" .. number; number = number + 1 end
      end
      return copyName
    end
    local function copyInto(folder, name, ext, bytes)
      directory(folder)
      local copyName = freeName(folder, name)
      write(folder .. "/" .. copyName .. "." .. ext, bytes)
      return copyName
    end
    local function duplicateRoute()
      local name = settings.selected
      if not name then return false, "Elige una ruta primero." end
      local path, ext = routeFile(name)
      if not path then return false, "No se encuentra la ruta " .. name .. "." end
      return true, copyInto(profilePath(P.activeId) .. "/" .. dir, name, ext, g_resources.readFileContents(path))
    end
    local function pullRoute(sourceId, routeName)
      local sourceFolder = profilePath(sourceId) .. "/" .. dir
      for _, ext in ipairs({"cfg", "json"}) do
        local path = sourceFolder .. "/" .. routeName .. "." .. ext
        if g_resources.fileExists(path) then
          local bytes = g_resources.readFileContents(path)
          return true, copyInto(profilePath(P.activeId) .. "/" .. dir, routeName, ext, bytes), bytes
        end
      end
      return false, "No se encuentra la ruta " .. routeName .. " en ese perfil."
    end
    -- Pulled routes can send the CaveBot to routes (set profile) that only the other profile has.
    -- Checked after everything was copied, so routes pulled together resolve each other.
    local function missingRoutes(allBytes)
      local missing, seen = {}, {}
      for _, bytes in ipairs(allBytes) do
        for line in ((bytes:gsub("\r", "")) .. "\n"):gmatch("([^\n]*)\n") do
          local value = line:match("^%s*setprofile:(.*)$")
          value = value and trimmed(value)
          if value and value ~= "" and value ~= "profileName" and not seen[value] then
            seen[value] = true
            if not routeFile(value) then missing[#missing + 1] = value end
          end
        end
      end
      return missing
    end
    local function pullRoutes(sourceId, sourceName, names)
      local pulled, renamed, failed, allBytes = 0, {}, {}, {}
      for _, routeName in ipairs(names) do
        local ok, done, copyName, bytes = pcall(pullRoute, sourceId, routeName)
        if ok and done then
          pulled = pulled + 1
          allBytes[#allBytes + 1] = bytes
          if copyName ~= routeName then renamed[#renamed + 1] = routeName .. " -> " .. copyName end
        else
          failed[#failed + 1] = routeName .. ": " .. tostring(ok and copyName or done)
        end
      end
      if pulled == 0 then
        flash("Error")
        warn("CaveBot: " .. (failed[1] or "no se pudo traer la ruta."))
        consoleLog("error", "No se pudo traer " .. (#names == 1 and ("la ruta " .. names[1]) or "las rutas") .. " de " .. sourceName,
          table.concat(failed, " | "))
        return
      end
      relist()
      flash(#failed == 0 and "Traida" or "Traida con fallos")
      local notes = {}
      if #renamed > 0 then notes[#notes + 1] = "Ya tenias: " .. table.concat(renamed, ", ") .. "." end
      local missing = missingRoutes(allBytes)
      if #missing > 0 then
        notes[#notes + 1] = "Usa set profile hacia rutas que no tienes: " .. table.concat(missing, ", ") ..
          ". Traelas tambien, o la ruta se parara en esa accion."
      end
      if #failed > 0 then notes[#notes + 1] = "Fallaron: " .. table.concat(failed, " | ") end
      local title
      if #names == 1 then
        title = "Ruta " .. names[1] .. " traida de " .. sourceName .. (#renamed > 0 and (" como " .. renamed[1]:match("%-> (.*)$")) or "")
      else
        title = pulled .. " rutas traidas de " .. sourceName
      end
      consoleLog("action", title, #notes > 0 and table.concat(notes, " ") or nil)
    end
    -- Own popup menu (the selector's one is as wide as the button and cuts the names). Themed like the
    -- selector's; falls back to the plain popup if that style does not exist.
    local function newMenu()
      for _, style in ipairs({"HelperSelectorPopupMenu", "PopupMenu"}) do
        local ok, menu = pcall(g_ui.createWidget, style)
        if ok and menu and type(menu.addOption) == "function" then return menu end
      end
    end
    local function showRoutes(sourceId, sourceName)
      local names = routeNames(profilePath(sourceId) .. "/" .. dir)
      if #names == 0 then flash("Sin rutas"); return end
      local menu = newMenu()
      if not menu then
        flash("Error")
        warn("CaveBot: no se pudo abrir el menu de rutas.")
        return
      end
      pcall(function() menu:setId("rinoPullRouteMenu") end)
      menu:addOption("Traer todas (" .. #names .. ")", function() pullRoutes(sourceId, sourceName, names) end)
      if type(menu.addSeparator) == "function" then pcall(menu.addSeparator, menu) end
      for _, routeName in ipairs(names) do
        local text = routeName .. (routeFile(routeName) and "   [ya tienes una]" or "")
        menu:addOption(text, function() pullRoutes(sourceId, sourceName, {routeName}) end)
      end
      local position = widget.copyTo:getPosition()
      menu:display({x = position.x, y = position.y + widget.copyTo:getHeight()})
    end
    widget.copyTo.onOptionChange = function(combo)
      if filling or not P.valid() then return end
      local option = combo:getCurrentOption()
      local target = option and option.data
      filling = true
      combo:setCurrentIndex(1)
      filling = false
      if not target or target == "none" then return end
      if target == "self" then
        local name = settings.selected
        local ok, done, copyName = pcall(duplicateRoute)
        if not ok or not done then
          local message = ok and tostring(copyName) or tostring(done)
          flash("Error")
          warn("CaveBot: " .. message)
          consoleLog("error", "No se pudo duplicar la ruta " .. tostring(name), message)
          return
        end
        relist()
        flash("Duplicada")
        consoleLog("action", "Ruta " .. name .. " duplicada como " .. copyName)
        return
      end
      local sourceId = tostring(target):match("^profile:(p%d+)$")
      if not sourceId then return end
      local sourceName = tostring(option.text):match("^(.*) %(%d+%)$") or sourceId
      -- Open the routes menu once the selector's own popup is gone.
      local function open() pcall(showRoutes, sourceId, sourceName) end
      if type(schedule) == "function" then pcall(schedule, 1, open) else open() end
    end
    -- Refresh just before the selector opens; if the class has no handler, nothing else changes.
    local nativePress = widget.copyTo.onMousePress
    widget.copyTo.onMousePress = function(self, ...)
      pcall(fillTargets)
      if type(nativePress) == "function" then return nativePress(self, ...) end
    end
    widget.copyTo:setTooltip("Trae a este perfil rutas de otro perfil: elige el perfil y luego la ruta (o Traer todas). Si ya tienes una con ese nombre, queda como nombre_copia. No toca las originales. Duplicar esta ruta hace una copia de la ruta que ves, en este mismo perfil, con el nombre nombre_copia (por ejemplo para probar cambios sin perder la original).")
    fillTargets()
    if type(P.onChange) == "function" then P.onChange(fillTargets) end
  end

  local function setOn(value)
    if P.valid() and widget.switch:isOn()~=(value~=false) then widget.switch:onClick() end
  end
  refresh()
  return {
    isOn=function() return widget.switch:isOn() end,
    isOff=function() return not widget.switch:isOn() end,
    setOn=setOn, setOff=function(value) setOn(value==false) end,
    save=function(data)
      if P.valid() and settings.selected then return Config.save(dir, settings.selected, data, extension) end
    end,
    refresh=refresh, reload=refresh, getActiveConfigName=function() return settings.selected end
  }
end
