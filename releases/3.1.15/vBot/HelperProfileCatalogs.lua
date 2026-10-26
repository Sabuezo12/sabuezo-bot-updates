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
      if mode=="seed" then
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

local relative = "_helper_profiles/profiles/" .. P.activeId .. "/"
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
    return original(relative .. dir, ...)
  end
end
Config.list = function(dir)
  if not scoped[dir] then return native.list(dir) end
  if not P.valid() then return {} end
  local list, seen = {}, {}
  for _, file in ipairs(g_resources.listDirectoryFiles(configDir .. "/" .. relative .. dir, false, false)) do
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
  local path = configDir .. "/" .. relative .. dir .. "/" .. name
  if extension then return g_resources.fileExists(path .. "." .. extension) end
  return g_resources.fileExists(path .. ".json") or g_resources.fileExists(path .. ".cfg")
end

-- Native Config.setup's Add callback writes configDir directly. Provide the
-- same interface here so dialogs, edits and deletes all use the private scope.
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
    UI.MultilineEditorWindow(Config.loadRaw(dir, name), {title="Config editor - " .. name .. " in " .. dir}, function(value)
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
