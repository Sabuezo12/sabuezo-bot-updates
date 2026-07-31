local function getEditorConfigName()
  if type(configName) == "string" and configName ~= "" then return configName end
  if type(botConfigName) == "string" and botConfigName ~= "" then return botConfigName end
  if storage and type(storage._configName) == "string" and storage._configName ~= "" then
    return storage._configName
  end

  local ok, currentName = pcall(function()
    return modules.game_bot.contentsPanel.config:getCurrentOption().text
  end)
  if ok and type(currentName) == "string" and currentName ~= "" then return currentName end

  return "Default"
end

local editorConfigName = getEditorConfigName()
local backupDir = "/bot/" .. editorConfigName .. "/_script_editor_backups"
local unpackArgs = unpack or table.unpack
local baseMacro = macro
local baseHotkey = hotkey
local baseSchedule = schedule
local baseAddEvent = addEvent
local baseCycleEvent = cycleEvent
local baseSetDefaultTab = setDefaultTab
local debugLibrary = debug

local function setMainAsDefaultTab()
  if type(baseSetDefaultTab) ~= "function" then return false end
  local ok = pcall(baseSetDefaultTab, "Main")
  return ok
end

local function resolveHostEnvironment()
  if type(_G) == "table" then return _G end

  local getters = {}
  if type(getfenv) == "function" then table.insert(getters, getfenv) end
  if debugLibrary and type(debugLibrary.getfenv) == "function" then
    table.insert(getters, debugLibrary.getfenv)
  end

  local sources = {baseMacro, baseSchedule, pcall}
  for _, getter in ipairs(getters) do
    local ok, environment = pcall(getter, 1)
    if ok and type(environment) == "table" then return environment end

    for _, source in ipairs(sources) do
      if type(source) == "function" then
        ok, environment = pcall(getter, source)
        if ok and type(environment) == "table" then return environment end
      end
    end
  end

  return nil
end

local hostEnvironment = resolveHostEnvironment()
local environmentSetter = setfenv or (debugLibrary and debugLibrary.setfenv)
local supportsManagedEnvironment =
  type(hostEnvironment) == "table" and type(environmentSetter) == "function"

local function trim(text)
  return tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function safeTimestamp()
  return os.date("%Y%m%d-%H%M%S")
end

local function safeFileName(text)
  local result = trim(text):gsub("[^%w_%-]", "_")
  if result == "" then result = "script" end
  return result
end

local function compileScript(text, chunkName, environment)
  local loader = loadstring or load
  if not loader then
    return false, "Este cliente no tiene load/loadstring disponible."
  end

  local ok, chunkOrError = pcall(function()
    return loader(text or "", "@ingame/" .. safeFileName(chunkName or "script"))
  end)
  if not ok then return false, chunkOrError end
  if type(chunkOrError) ~= "function" then return false, tostring(chunkOrError) end

  if environment and environmentSetter then
    local envOk, envError = pcall(environmentSetter, chunkOrError, environment)
    if not envOk then return false, envError end
  end

  return true, chunkOrError
end

local function saveBackup(scriptEntry, previousText)
  if type(previousText) ~= "string" or previousText:len() == 0 then return end

  storage.ingame_script_backups = storage.ingame_script_backups or {}
  table.insert(storage.ingame_script_backups, 1, {
    time = safeTimestamp(),
    name = scriptEntry and scriptEntry.name or "Script",
    text = previousText
  })

  while #storage.ingame_script_backups > 20 do
    table.remove(storage.ingame_script_backups)
  end

  if not g_resources or not g_resources.makeDir or not g_resources.writeFileContents then return end

  if not g_resources.directoryExists(backupDir) then
    pcall(function() g_resources.makeDir(backupDir) end)
  end

  local fileName = backupDir .. "/" .. safeFileName(scriptEntry and scriptEntry.name) ..
    "-" .. safeTimestamp() .. ".lua"
  pcall(function() g_resources.writeFileContents(fileName, previousText) end)
end

storage.ingame_script_manager = storage.ingame_script_manager or {}
local managerConfig = storage.ingame_script_manager
managerConfig.scripts = type(managerConfig.scripts) == "table" and managerConfig.scripts or {}
managerConfig.nextId = math.max(1, tonumber(managerConfig.nextId) or 1)

local usedIds = {}
for index = #managerConfig.scripts, 1, -1 do
  local entry = managerConfig.scripts[index]
  if type(entry) ~= "table" or type(entry.code) ~= "string" then
    table.remove(managerConfig.scripts, index)
  else
    local id = tonumber(entry.id)
    if not id or usedIds[id] then
      id = managerConfig.nextId
      managerConfig.nextId = managerConfig.nextId + 1
    end
    entry.id = id
    usedIds[id] = true
    managerConfig.nextId = math.max(managerConfig.nextId, id + 1)
    entry.name = trim(entry.name)
    if entry.name == "" then entry.name = "Script " .. tostring(id) end
    entry.enabled = entry.enabled == true
    entry.lastError = type(entry.lastError) == "string" and entry.lastError or nil
  end
end

if not managerConfig.legacyMigrated then
  local legacyCode = storage.ingame_hotkeys
  if type(legacyCode) == "string" and legacyCode:len() > 3 then
    table.insert(managerConfig.scripts, {
      id = managerConfig.nextId,
      name = "Script importado",
      code = legacyCode,
      enabled = true
    })
    managerConfig.nextId = managerConfig.nextId + 1
  end
  managerConfig.legacyMigrated = true
end

vBot = vBot or {}
vBot.InGameScriptManager = vBot.InGameScriptManager or {}
local sharedRuntime = vBot.InGameScriptManager
sharedRuntime.generation = (sharedRuntime.generation or 0) + 1
local managerGeneration = sharedRuntime.generation

for _, previousRuntime in pairs(sharedRuntime.runtimes or {}) do
  previousRuntime.active = false
  for _, handle in ipairs(previousRuntime.handles or {}) do
    pcall(function()
      if handle.setOff then handle.setOff() end
    end)
  end
end
sharedRuntime.runtimes = {}

local managerWindow
local managerButton
local selectedScriptId
local refreshList

local function findScript(scriptId)
  for index, entry in ipairs(managerConfig.scripts) do
    if entry.id == scriptId then return entry, index end
  end
  return nil
end

local function setStatus(text, color)
  if not managerWindow or not managerWindow.status then return end
  managerWindow.status:setText(text or "")
  managerWindow.status:setColor(color or "#b8c7cc")
end

local function setHandleEnabled(handle, enabled)
  if not handle then return end
  local method = enabled and handle.setOn or handle.setOff
  if not method then return end

  local ok = pcall(method)
  if not ok then pcall(method, handle) end
end

local function stopRuntime(runtime, destroySwitches)
  if not runtime then return end
  runtime.active = false

  for _, handle in ipairs(runtime.handles or {}) do
    setHandleEnabled(handle, false)
    if destroySwitches then
      pcall(function()
        if handle.switch and handle.switch.destroy then handle.switch:destroy() end
      end)
    end
  end
end

local function reportRuntimeError(runtime, errorText)
  if not runtime or runtime.failed then return end
  runtime.failed = true
  stopRuntime(runtime, false)

  local entry = findScript(runtime.scriptId)
  if entry then
    entry.enabled = false
    entry.lastError = tostring(errorText)
  end

  warn("[Script Manager] " .. tostring(runtime.name) .. " desactivado:\n" .. tostring(errorText))
  if refreshList then
    schedule(1, function()
      if sharedRuntime.generation == managerGeneration then refreshList() end
    end)
  end
end

local function guardCallback(runtime, callback)
  if type(callback) ~= "function" then return callback end

  return function(...)
    if not runtime.active or sharedRuntime.generation ~= managerGeneration then return end

    local results = {pcall(callback, ...)}
    if not results[1] then
      reportRuntimeError(runtime, results[2])
      return
    end

    table.remove(results, 1)
    return unpackArgs(results)
  end
end

local function wrapCallbackArgument(runtime, baseFunction, ...)
  local args = {...}
  for index = #args, 1, -1 do
    if type(args[index]) == "function" then
      args[index] = guardCallback(runtime, args[index])
      break
    end
  end
  return baseFunction(unpackArgs(args))
end

local function createScriptEnvironment(runtime)
  if not supportsManagedEnvironment then
    runtime.native = true
    return nil
  end

  local environment = {}
  local wrapperCache = {}

  local function createTimedHandle(baseFunction, ...)
    local handle = wrapCallbackArgument(runtime, baseFunction, ...)
    if handle then table.insert(runtime.handles, handle) end
    return handle
  end

  environment._G = environment
  environment.macro = function(...)
    return createTimedHandle(baseMacro, ...)
  end

  if type(baseHotkey) == "function" then
    environment.hotkey = function(...)
      return createTimedHandle(baseHotkey, ...)
    end
  end

  if type(baseSchedule) == "function" then
    environment.schedule = function(...)
      return wrapCallbackArgument(runtime, baseSchedule, ...)
    end
  end

  if type(baseAddEvent) == "function" then
    environment.addEvent = function(...)
      return wrapCallbackArgument(runtime, baseAddEvent, ...)
    end
  end

  if type(baseCycleEvent) == "function" then
    environment.cycleEvent = function(...)
      return wrapCallbackArgument(runtime, baseCycleEvent, ...)
    end
  end

  environment.setDefaultTab = function()
    setMainAsDefaultTab()
  end

  setmetatable(environment, {
    __index = function(_, key)
      local value = hostEnvironment[key]
      if type(value) == "function" and tostring(key):match("^on[A-Z]") then
        if not wrapperCache[key] then
          wrapperCache[key] = function(...)
            return wrapCallbackArgument(runtime, value, ...)
          end
        end
        return wrapperCache[key]
      end
      return value
    end
  })

  return environment
end

local function startScript(entry)
  if not entry or not entry.enabled then return false end

  local existing = sharedRuntime.runtimes[entry.id]
  if existing and not existing.failed then
    existing.active = true
    for _, handle in ipairs(existing.handles or {}) do
      setHandleEnabled(handle, true)
    end
    entry.lastError = nil
    return true
  end
  if existing then
    stopRuntime(existing, true)
    sharedRuntime.runtimes[entry.id] = nil
  end

  local runtime = {
    scriptId = entry.id,
    name = entry.name,
    active = true,
    failed = false,
    handles = {}
  }
  sharedRuntime.runtimes[entry.id] = runtime

  local envOk, environmentOrError = pcall(createScriptEnvironment, runtime)
  if not envOk then
    reportRuntimeError(runtime, environmentOrError)
    return false
  end
  runtime.environment = environmentOrError

  local valid, chunkOrError = compileScript(entry.code, entry.name, runtime.environment)
  if not valid then
    reportRuntimeError(runtime, chunkOrError)
    return false
  end

  setMainAsDefaultTab()
  local ok, runtimeError = pcall(chunkOrError)
  if not ok then
    reportRuntimeError(runtime, runtimeError)
    return false
  end

  entry.lastError = nil
  return true
end

local function setScriptEnabled(entry, enabled)
  if not entry then return false end

  if enabled then
    local valid, compileError = compileScript(entry.code, entry.name)
    if not valid then
      entry.enabled = false
      entry.lastError = tostring(compileError)
      setStatus("Error de sintaxis: " .. tostring(compileError), "#ff6666")
      return false
    end

    entry.enabled = true
    if not startScript(entry) then return false end
    setStatus(entry.name .. " activado", "#66ff66")
  else
    entry.enabled = false
    entry.lastError = nil
    local runtime = sharedRuntime.runtimes[entry.id]
    stopRuntime(runtime, false)
    setStatus(entry.name .. " desactivado", "#d0d0d0")
    if runtime and runtime.native and type(reload) == "function" then
      schedule(50, reload)
    end
  end

  return true
end

local rootWidget = g_ui.getRootWidget()
if rootWidget then
  local oldWindow = rootWidget:recursiveGetChildById("InGameScriptManagerWindow")
  if oldWindow then oldWindow:destroy() end
end

managerWindow = UI.createWindow("InGameScriptManagerWindow", rootWidget)
managerWindow:hide()

local function selectScript(entry)
  selectedScriptId = entry and entry.id or nil
  managerWindow.scriptName:setText(entry and entry.name or "")
end

local function editScript(entry)
  if not entry then return end
  selectScript(entry)

  UI.MultilineEditorWindow(entry.code or "", {
    title = "Editar: " .. entry.name,
    description = "El codigo se valida antes de guardarse. Los cambios reemplazan la ejecucion actual."
  }, function(text)
    local valid, compileError = compileScript(text, entry.name)
    if not valid then
      setStatus("No guardado: " .. tostring(compileError), "#ff6666")
      warn("[Script Manager] No se guardo " .. entry.name .. ":\n" .. tostring(compileError))
      return
    end

    saveBackup(entry, entry.code)
    stopRuntime(sharedRuntime.runtimes[entry.id], true)
    sharedRuntime.runtimes[entry.id] = nil
    entry.code = text
    entry.lastError = nil

    if entry.enabled then startScript(entry) end
    setStatus(entry.name .. " guardado", "#66ff66")
    refreshList()
  end)
end

local function removeScript(entry)
  if not entry then return end

  saveBackup(entry, entry.code)
  stopRuntime(sharedRuntime.runtimes[entry.id], true)
  sharedRuntime.runtimes[entry.id] = nil

  local _, index = findScript(entry.id)
  if index then table.remove(managerConfig.scripts, index) end
  if selectedScriptId == entry.id then selectScript(nil) end

  setStatus(entry.name .. " eliminado; respaldo creado", "#ffcc66")
  refreshList()
end

refreshList = function()
  if not managerWindow or not managerWindow.scriptList then return end
  managerWindow.scriptList:destroyChildren()

  local visibleRows = math.max(3, math.min(8, #managerConfig.scripts))
  pcall(function()
    managerWindow:setWidth(380)
    managerWindow:setHeight(174 + visibleRows * 22)
  end)

  for _, entry in ipairs(managerConfig.scripts) do
    local row = g_ui.createWidget("InGameScriptRow", managerWindow.scriptList)
    row:setId("ingameScript" .. tostring(entry.id))
    row.name:setText(entry.name)
    row.enabled:setChecked(entry.enabled)

    if entry.lastError then
      row.name:setColor("#ff6666")
      row:setTooltip(entry.lastError)
    elseif entry.enabled then
      row.name:setColor("#66ff66")
      row:setTooltip("Activo")
    else
      row.name:setColor("#d0d0d0")
      row:setTooltip("Desactivado")
    end

    row.onClick = function()
      selectScript(entry)
      row:focus()
    end

    row.onDoubleClick = function()
      editScript(entry)
      return true
    end

    row.enabled.onClick = function(widget)
      setScriptEnabled(entry, not entry.enabled)
      widget:setChecked(entry.enabled)
      refreshList()
    end

    row.edit.onClick = function()
      editScript(entry)
    end

    row.remove.onClick = function()
      removeScript(entry)
    end

    if selectedScriptId == entry.id then row:focus() end
  end

  if #managerConfig.scripts == 0 then
    setStatus("Escribe un nombre y pulsa Nuevo", "#b8c7cc")
  end
end

managerWindow.addButton.onClick = function()
  local scriptName = trim(managerWindow.scriptName:getText())
  if scriptName == "" then
    setStatus("Escribe el nombre del nuevo script", "#ffcc66")
    return
  end

  UI.MultilineEditorWindow("", {
    title = "Nuevo: " .. scriptName,
    description = "El script se guardara y activara si el codigo Lua es valido."
  }, function(text)
    local valid, compileError = compileScript(text, scriptName)
    if not valid then
      setStatus("No guardado: " .. tostring(compileError), "#ff6666")
      return
    end

    local entry = {
      id = managerConfig.nextId,
      name = scriptName,
      code = text,
      enabled = true
    }
    managerConfig.nextId = managerConfig.nextId + 1
    table.insert(managerConfig.scripts, entry)
    selectedScriptId = entry.id

    startScript(entry)
    setStatus(scriptName .. " creado y activado", "#66ff66")
    refreshList()
  end)
end

managerWindow.renameButton.onClick = function()
  local entry = findScript(selectedScriptId)
  if not entry then
    setStatus("Selecciona un script para renombrarlo", "#ffcc66")
    return
  end

  local newName = trim(managerWindow.scriptName:getText())
  if newName == "" then
    setStatus("El nombre no puede estar vacio", "#ffcc66")
    return
  end

  entry.name = newName
  local runtime = sharedRuntime.runtimes[entry.id]
  if runtime then runtime.name = newName end
  setStatus("Script renombrado", "#66ff66")
  refreshList()
end

managerWindow.closeButton.onClick = function()
  managerWindow:hide()
end

setMainAsDefaultTab()
UI.Separator()
managerButton = UI.Button("In-Game Script Editor", function()
  refreshList()
  managerWindow:show()
  managerWindow:raise()
  managerWindow:focus()
end)
managerButton:setImageColor("#2de0d7")
managerButton:setFont("verdana-11px-rounded")
managerButton:setTooltip("Administra scripts Lua guardados y activa cada uno con su checkbox.")
UI.Separator()

for _, entry in ipairs(managerConfig.scripts) do
  if entry.enabled then startScript(entry) end
end

refreshList()
