vBot = vBot or {}
if vBot.InGameScriptManagerLoaded then return end

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
local function unpackValues(values,first,last)
  first,last=first or 1,last or #values
  if first>last then return end
  return values[first],unpackValues(values,first+1,last)
end
local unpackArgs = unpack or table.unpack or unpackValues
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
local nativeGetters={}
local function nativeValue(name)
  if hostEnvironment then return hostEnvironment[name] end
  if type(name)~='string' or not name:match('^[%a_][%w_]*$') then return nil end
  local getter=nativeGetters[name]
  if getter==nil then
    local loader=loadstring or load
    local ok,value=pcall(loader,'return '..name)
    getter=ok and type(value)=='function' and value or false
    nativeGetters[name]=getter
  end
  if getter then local ok,value=pcall(getter);if ok then return value end end
end

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
  -- Retain saved installer text and ON/OFF; it must not overwrite RinoBot
  -- when the personal script manager runs it again after a migration.
  local publicSnippet = "modules.corelib.HTTP.get('https://raw.githubusercontent.com/Sabuezo12/sabuezo-bot-updates/main/bootstrap.lua', function(script, err) if err or not script then warn('No se pudo descargar Sabuezo') return end assert(loadstring(script))() end)"
  if type(text)=="string" then
    local normalized=text:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " "):gsub('"', "'")
    local fullInstaller=text:find("-- Sabuezo public installer. Downloads and validates all files before changing the bot.",1,true) and
      text:find("/_updates/bootstrap_",1,true) and text:find("sabuezoInstall=",1,true)
    if normalized==publicSnippet or fullInstaller then
      text="if HelperProfiles and HelperProfiles.valid() then warn('RinoBot: instalador clasico conservado; usa Updater para actualizar.'); return end\n" .. text
    end
  end
  local loader = loadstring or load
  if not loader then
    return false, "Este cliente no tiene load/loadstring disponible."
  end

  local names,values={},{}
  if environment and not supportsManagedEnvironment then
    -- OTC's context.load can bind its own context but expose no setfenv/_G.
    -- Lexical arguments retain the managed callbacks in that native loader.
    for _,name in ipairs({'_G','macro','hotkey','schedule','addEvent','cycleEvent','setDefaultTab'}) do
      if environment[name]~=nil then names[#names+1]=name;values[#values+1]=environment[name] end
    end
    for _,name in ipairs(environment.callbackNames or {}) do
      names[#names+1]=name;values[#values+1]=environment[name]
    end
    text='return function('..table.concat(names,',')..',...)\n'..(text or '')..'\nend'
  end
  local ok, chunkOrError = pcall(function()
    return loader(text or "", "@ingame/" .. safeFileName(chunkName or "script"))
  end)
  if not ok then return false, chunkOrError end
  if type(chunkOrError) ~= "function" then return false, tostring(chunkOrError) end

  if environment and supportsManagedEnvironment then
    local envOk, envError = pcall(environmentSetter, chunkOrError, environment)
    if not envOk then return false, envError end
  end
  if environment and not supportsManagedEnvironment then
    local built,factory=pcall(chunkOrError)
    if not built or type(factory)~='function' then return false,tostring(factory) end
    return true,function()return factory(unpackArgs(values))end
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
    -- R162 could turn availability OFF when OTC exposed neither unpack API.
    -- Recover only that exact manager failure, leaving the function paused.
    if entry.lastError and entry.lastError:find('/vBot/ingame_editor.lua',1,true) and
        entry.lastError:find("attempt to call upvalue 'unpackArgs' (a nil value)",1,true) then
      local valid=compileScript(entry.code,entry.name)
      if valid then entry.enabled,entry.running,entry.lastError=true,false,nil end
    end
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

-- Ejecutar el Ok del cliente: el modulo se encarga de aceptar y volver a entrar.
-- El editor y el boton de Main comparten el mismo estado enabled.
local deathDialogCode = [=[
local accepted = setmetatable({}, {__mode="k"})
local function isLiveWindow(window)
  return window and not (window.isDestroyed and window:isDestroyed()) and
    (not window.isVisible or window:isVisible())
end

macro(250, function()
  local deathModule = modules and modules.game_playerdeath
  local window = deathModule and deathModule.deathWindow
  if not isLiveWindow(window) then
    local root = g_ui.getRootWidget()
    window = root and root:recursiveGetChildById("deathWindow")
  end
  if not isLiveWindow(window) or accepted[window] then return end

  local button = window:getChildById("buttonOk")
  local action = button and button.onClick
  local receiver = button
  if type(action) ~= "function" then
    action, receiver = window.onEnter, window
  end
  if type(action) ~= "function" then return end

  -- Una sola aceptacion por ventana, aunque el login tarde en completarse.
  -- No destruirla: Ok conserva toda la secuencia nativa de reconexion.
  accepted[window] = true
  action(receiver)
end)
]=]

-- Importar/actualizar desde el bot; no editar el JSON de un cliente abierto.
if not managerConfig.deathDialogImported20261002 then
  table.insert(managerConfig.scripts, {
    id=managerConfig.nextId, name="Aceptar muerte", enabled=true,
    builtin="acceptDeath", code=deathDialogCode
  })
  managerConfig.deathDialogScriptId = managerConfig.nextId
  managerConfig.nextId = managerConfig.nextId+1
  managerConfig.deathDialogImported20261002 = true
end
if not managerConfig.deathDialogAcceptImported20261003 then
  for _, entry in ipairs(managerConfig.scripts) do
    if entry.id == managerConfig.deathDialogScriptId or entry.builtin == "acceptDeath" or
      entry.name == "Cerrar pantalla de muerte" or
      (entry.code:find("local function removeDeathWindow", 1, true) and entry.code:find('"deathWindow"', 1, true)) then
      if entry.code ~= deathDialogCode then saveBackup(entry, entry.code) end
      entry.code, entry.name, entry.builtin = deathDialogCode, "Aceptar muerte", "acceptDeath"
      entry.lastError = nil
      managerConfig.deathDialogScriptId = entry.id
      break
    end
  end
  managerConfig.deathDialogAcceptImported20261003 = true
end

-- Importar una sola vez: las ediciones posteriores pertenecen al usuario.
if not managerConfig.cosmeticVisibilityImported20261006 then
  local cosmeticEntry
  for _, entry in ipairs(managerConfig.scripts) do
    if entry.builtin == "hideAurasAndPets" or entry.builtin == "hidePets" or entry.id == managerConfig.cosmeticsScriptId then
      cosmeticEntry = entry
      break
    end
  end
  if not cosmeticEntry then
    local path = "/bot/" .. editorConfigName .. "/vBot/cosmetic_visibility.lua"
    local ok, code = pcall(function() return g_resources.readFileContents(path) end)
    local valid = ok and type(code) == "string" and compileScript(code, "Ocultar mascotas")
    if valid then
      cosmeticEntry = {
        id=managerConfig.nextId, name="Ocultar mascotas",
        enabled=not (storage.extras and storage.extras.hideAurasAndPets == false),
        builtin="hidePets", code=code
      }
      managerConfig.nextId = managerConfig.nextId + 1
      local insertAt = #managerConfig.scripts + 1
      for index, entry in ipairs(managerConfig.scripts) do
        if entry.id == managerConfig.deathDialogScriptId then insertAt = index + 1; break end
      end
      table.insert(managerConfig.scripts, insertAt, cosmeticEntry)
    else
      warn("[Script Manager] No se pudo importar Ocultar mascotas desde " .. path)
    end
  end
  if cosmeticEntry then
    managerConfig.cosmeticsScriptId = cosmeticEntry.id
    managerConfig.cosmeticVisibilityImported20261006 = true
  end
end

-- Actualizar tambien la copia ya guardada en el editor, conservando su estado.
if not managerConfig.cosmeticPetsOnlyRestored20261006 then
  local updated = true
  for _, entry in ipairs(managerConfig.scripts) do
    if entry.builtin == "hideAurasAndPets" or entry.builtin == "hidePets" or entry.id == managerConfig.cosmeticsScriptId then
      local path = "/bot/" .. editorConfigName .. "/vBot/cosmetic_visibility.lua"
      local ok, code = pcall(function() return g_resources.readFileContents(path) end)
      local valid = ok and type(code) == "string" and compileScript(code, entry.name)
      if valid then
        if entry.code ~= code then saveBackup(entry, entry.code) end
        entry.code = code
        entry.name = "Ocultar mascotas"
        entry.builtin = "hidePets"
        entry.lastError = nil
      else
        updated = false
        warn("[Script Manager] No se pudo restaurar Ocultar mascotas desde " .. path)
      end
    end
  end
  if updated then
    managerConfig.cosmeticPetsOnlyRestored20261006 = true
  end
end

-- Optimizar solo la copia original de mascotas; conservar las ediciones propias.
if not managerConfig.cosmeticPerformanceImported20261006 then
  local updated = true
  for _, entry in ipairs(managerConfig.scripts) do
    if entry.builtin == "hidePets" or entry.id == managerConfig.cosmeticsScriptId then
      local original = entry.code:gsub("\r\n", "\n")
      -- Firma Adler32 del script de mascotas distribuido antes de esta mejora.
      local a, b = 1, 0
      if #original == 4339 then
        for index = 1, #original do
          a = (a + original:byte(index)) % 65521
          b = (b + a) % 65521
        end
      end
      if #original == 4339 and b * 65536 + a == 4266568697 then
        local path = "/bot/" .. editorConfigName .. "/vBot/cosmetic_visibility.lua"
        local ok, code = pcall(function() return g_resources.readFileContents(path) end)
        local valid = ok and type(code) == "string" and compileScript(code, entry.name)
        if valid then
          saveBackup(entry, entry.code)
          entry.code, entry.lastError = code, nil
        else
          updated = false
          warn("[Script Manager] No se pudo optimizar Ocultar mascotas desde " .. path)
        end
      end
    end
  end
  if updated then managerConfig.cosmeticPerformanceImported20261006 = true end
end

-- Limpiar la ejecucion anterior de Bot Settings al migrar al editor.
local clientBot = modules and modules.game_bot
if clientBot and type(clientBot.sabuezoCosmeticsCleanup) == "function" then
  pcall(clientBot.sabuezoCosmeticsCleanup)
  clientBot.sabuezoCosmeticsCleanup = nil
end

vBot = vBot or {}
vBot.InGameScriptManager = vBot.InGameScriptManager or {}
local sharedRuntime = vBot.InGameScriptManager
sharedRuntime.codeEditor = nil -- no conservar callbacks de un editor anterior
if sharedRuntime.deathSwitch then
  pcall(function() sharedRuntime.deathSwitch:destroy() end)
  sharedRuntime.deathSwitch = nil
end
if sharedRuntime.cosmeticsSwitch then
  pcall(function() sharedRuntime.cosmeticsSwitch:destroy() end)
  sharedRuntime.cosmeticsSwitch = nil
end
sharedRuntime.generation = (sharedRuntime.generation or 0) + 1
local managerGeneration = sharedRuntime.generation

for _, previousRuntime in pairs(sharedRuntime.runtimes or {}) do
  previousRuntime.active = false
  for _, handle in ipairs(previousRuntime.handles or {}) do
    pcall(function()
      if handle.setOff then handle.setOff() end
    end)
  end
  for _, cleanup in ipairs(previousRuntime.cleanups or {}) do pcall(cleanup) end
  previousRuntime.cleanups = {}
end
sharedRuntime.runtimes = {}
sharedRuntime.startingRuntime = nil
sharedRuntime.registerCleanup = function(callback)
  local runtime = sharedRuntime.startingRuntime
  if not runtime or type(callback) ~= "function" then return false end
  table.insert(runtime.cleanups, callback)
  return true
end

local managerWindow
local managerButton
local deathQuickSwitch
local cosmeticsQuickSwitch
local selectedScriptId
local refreshList
local refreshControls

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
  local entry=findScript(runtime.scriptId)
  if runtime.active then
    runtime.resumeStates=runtime.resumeStates or {}
    for index,handle in ipairs(runtime.handles or {})do
      if type(handle.isOn)=='function' then
        local ok,on=pcall(handle.isOn)
        if ok then
          runtime.resumeStates[index]=on==true
          local key=runtime.handleKeys and runtime.handleKeys[index]
          if entry and key then
            entry.macroStates=type(entry.macroStates)=='table' and entry.macroStates or {}
            entry.macroStates[key]=on==true
          end
        end
      end
    end
  end
  runtime.active = false
  if destroySwitches and RinoScriptControls then RinoScriptControls.retire(runtime) end

  for _, handle in ipairs(runtime.handles or {}) do
    setHandleEnabled(handle, false)
    if destroySwitches then
      pcall(function()
        if handle.switch and handle.switch.destroy then handle.switch:destroy() end
      end)
    end
  end
  if #(runtime.cleanups or {}) > 0 then
    runtime.restartOnEnable = true
    local cleanups = runtime.cleanups
    runtime.cleanups = {}
    for _, cleanup in ipairs(cleanups) do pcall(cleanup) end
  end
end

local function reportRuntimeError(runtime, errorText)
  if not runtime or runtime.failed then return end
  runtime.failed = true
  stopRuntime(runtime, false)

  local entry = findScript(runtime.scriptId)
  if entry then
    entry.running = false
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

    local last=1
    for index in pairs(results) do if type(index)=='number' and index>last then last=index end end
    return unpackArgs(results,2,last)
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
  local environment = {}
  local wrapperCache = {}

  local function createTimedHandle(baseFunction, ...)
    local handle = wrapCallbackArgument(runtime, baseFunction, ...)
    if handle then
      table.insert(runtime.handles, handle)
      if baseFunction==baseMacro and RinoScriptControls then
        local index=#runtime.handles
        local name=type(handle.name)=='string' and handle.name~='' and handle.name or 'Macro '..index
        local key=tostring(index)..':'..name
        runtime.handleKeys=runtime.handleKeys or {};runtime.handleKeys[index]=key
        local entry=findScript(runtime.scriptId)
        if entry and type(entry.macroStates)=='table' and entry.macroStates[key]~=nil then
          setHandleEnabled(handle,entry.macroStates[key]==true)
        end
        RinoScriptControls.claim(handle,runtime,name,index,function(on)
          local entry=findScript(runtime.scriptId)
          if entry then
            entry.macroStates=type(entry.macroStates)=='table' and entry.macroStates or {}
            entry.macroStates[key]=on
          end
        end)
      end
    end
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
      local value = nativeValue(key)
      if type(value) == "function" and tostring(key):match("^on[A-Z]") then
        if not wrapperCache[key] then
          wrapperCache[key] = function(...)
            runtime.registeredCallbacks=true
            return wrapCallbackArgument(runtime, value, ...)
          end
        end
        return wrapperCache[key]
      end
      return value
    end
  })

  environment.callbackNames={}
  local callbacks=type(_callbacks)=='table' and _callbacks or {onTalk=true,onTextMessage=true,onCreatureAppear=true,onCreatureDisappear=true}
  for name in pairs(callbacks) do
    if type(name)=='string' and name:match('^on[A-Z][%w_]*$') and type(nativeValue(name))=='function' then
      environment.callbackNames[#environment.callbackNames+1]=name
    end
  end
  table.sort(environment.callbackNames)

  return environment
end

local function startScript(entry)
  if not entry or not entry.enabled then return false end

  local existing = sharedRuntime.runtimes[entry.id]
  if existing and not existing.failed and not existing.restartOnEnable then
    existing.active = true
    for index, handle in ipairs(existing.handles or {}) do
      local key=existing.handleKeys and existing.handleKeys[index]
      local desired
      if key and type(entry.macroStates)=='table' then desired=entry.macroStates[key] end
      if desired==nil and existing.resumeStates then desired=existing.resumeStates[index] end
      setHandleEnabled(handle, desired~=false)
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
    handles = {},
    cleanups = {}
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
  local previousStartingRuntime = sharedRuntime.startingRuntime
  sharedRuntime.startingRuntime = runtime
  local ok, runtimeError = pcall(chunkOrError)
  sharedRuntime.startingRuntime = previousStartingRuntime
  if not ok then
    reportRuntimeError(runtime, runtimeError)
    return false
  end

  -- A script may call :setOn() immediately after declaring a macro. Apply
  -- explicit user choices once initialization finishes, including anonymous macros.
  for index,handle in ipairs(runtime.handles)do
    local key=runtime.handleKeys and runtime.handleKeys[index]
    if key and type(entry.macroStates)=='table' and entry.macroStates[key]~=nil then
      setHandleEnabled(handle,entry.macroStates[key]==true)
    end
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

    stopRuntime(sharedRuntime.runtimes[entry.id],false)
    entry.enabled,entry.running,entry.lastError=true,false,nil
    setStatus(entry.name .. " disponible; pulsa ON en su panel", "#66ff66")
  else
    entry.enabled = false
    entry.running = false
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

local function scriptIsRunning(entry)
  if sharedRuntime.generation~=managerGeneration then return false end
  local runtime=sharedRuntime.runtimes[entry.id]
  if not entry.enabled or entry.running==false or not runtime or not runtime.active or runtime.failed then return false end
  local timed=false
  for _,handle in ipairs(runtime.handles or {}) do
    if type(handle.isOn)=='function' then
      timed=true
      local ok,on=pcall(handle.isOn)
      if ok and on==true then return true end
    end
  end
  return not timed or runtime.registeredCallbacks==true
end
local function setScriptRunning(entry,on)
  if sharedRuntime.generation~=managerGeneration or not entry or findScript(entry.id)~=entry or not entry.enabled then return false end
  entry.running=on==true
  if on then
    if not startScript(entry) then return false end
    local runtime=sharedRuntime.runtimes[entry.id]
    -- A named macro may start OFF in Classic; an explicit panel ON starts it.
    if not scriptIsRunning(entry) then
      for index,handle in ipairs(runtime.handles or {}) do
        setHandleEnabled(handle,true)
        local key=runtime.handleKeys and runtime.handleKeys[index]
        if key then
          entry.macroStates=entry.macroStates or {};entry.macroStates[key]=true
        end
      end
    end
  else
    -- Includes cleanup such as restoring pets; the file remains loaded.
    stopRuntime(sharedRuntime.runtimes[entry.id],false)
  end
  return true
end

local rootWidget = g_ui.getRootWidget()
if rootWidget then
  local oldWindow = rootWidget:recursiveGetChildById("InGameScriptManagerWindow")
  if oldWindow then oldWindow:destroy() end
end

local helperCompact = Helper and Helper.valid() and not (storage.helperUI and storage.helperUI.legacy == true)
managerWindow = UI.createWindow(helperCompact and "HelperScriptsCompact" or "InGameScriptManagerWindow", rootWidget)
managerWindow.helperCompact = helperCompact == true
managerWindow.closeButton:setVisible(not helperCompact)
managerWindow:hide()

local controlRows={}
local controlsRevision,controlsQuery=-1,nil
local function resizeScriptLists()
  local size=rootWidget:getSize()
  local embedded=managerWindow.helperCompact==true
  local maxWidth=math.max(280,size.width-(embedded and 172 or 32))
  local maxHeight=math.max(320,size.height-(embedded and 224 or 48))
  local columns=maxWidth>=620
  local large=managerConfig.workspaceExpanded==true
  local width=math.min(maxWidth,columns and (large and 760 or 660) or 520)
  local height=math.min(maxHeight,columns and (large and 480 or 360) or (large and 560 or 440))
  if managerWindow.workspaceColumns~=columns then
    managerWindow.workspaceColumns=columns
    managerWindow.filesCard:mergeStyle({
      ['anchors.right']=columns and 'workspaceSplit.left' or 'parent.right',
      ['anchors.bottom']=columns and 'closeButton.top' or 'workspaceSplit.top',
      ['margin-right']=columns and 6 or 0,['margin-bottom']=columns and 8 or 6})
    managerWindow.liveControls:mergeStyle({
      ['anchors.left']=columns and 'workspaceSplit.right' or 'parent.left',
      ['anchors.top']=columns and 'status.bottom' or 'workspaceSplit.bottom',
      ['margin-left']=columns and 6 or 0,['margin-top']=6})
  end
  local visibleFiles=math.min(large and 6 or 4,math.max(2,math.floor((height-290)/22)),math.max(2,#managerConfig.scripts))
  managerWindow.workspaceSplit:setMarginTop(44+visibleFiles*22+11)
  managerWindow.filesHeading:setText('Tus scripts ('..#managerConfig.scripts..')')
  managerWindow.liveControls:setVisible(true)
  managerWindow.liveControls.emptyState:setVisible(#controlRows==0)
  managerWindow.layoutButton:setText(large and 'Reducir' or 'Ampliar')
  managerWindow.layoutButton:setTooltip(large and 'Volver al espacio normal para scripts y paneles.' or 'Ampliar ambas listas para ver mas scripts y controles.')
  if managerWindow:getWidth()~=width or managerWindow:getHeight()~=height then
    managerWindow:setSize({width=width,height=height})
  end
end
managerWindow.layoutButton.onClick=function()
  managerConfig.workspaceExpanded=not(managerConfig.workspaceExpanded==true)
  resizeScriptLists()
  local view=Helper and Helper.valid() and Helper.widgets and Helper.widgets[managerWindow]
  if view and view.mounted and Helper.openView then Helper.openView(view) end
end
refreshControls=function(force)
  if sharedRuntime.generation~=managerGeneration or not managerWindow then return end
  if RinoScriptControls and not RinoScriptControls.valid() then return end
  local panel=managerWindow.liveControls
  if not panel then return end
  local controls=RinoScriptControls
  local query=trim(panel.search:getText()):lower()
  local revision=controls and controls.revision or 0
  if force or revision~=controlsRevision or query~=controlsQuery then
    panel.list:destroyChildren();controlRows={}
    local total=0
    local allControls=controls and controls.list() or {}
    for _,script in ipairs(managerConfig.scripts) do
      if script.enabled then
      local owned={}
      local description=script.name
      for _,entry in ipairs(allControls) do
        local owner=entry.owner
        if owner and owner.scriptId==script.id and sharedRuntime.runtimes[script.id]==owner then
          owned[#owned+1]=entry;description=description..' '..entry.name
        end
      end
      if query=='' or description:lower():find(query,1,true) then
        total=total+1
        if #controlRows<200 then
          local row=g_ui.createWidget('ScriptControlRow',panel.list)
          if HelperTheme then HelperTheme.tooltips(row) end
          row.name:setText(script.name)
          row.name:setTooltip(script.name)
          row:setTooltip(script.lastError or 'ON/OFF enciende o apaga este script. Su casilla en la lista lo deja disponible aqui.')
          row.power.onClick=function()
            if setScriptRunning(script,not scriptIsRunning(script)) then refreshList() end
          end
          controlRows[#controlRows+1]={widget=row,script=script}
          -- Multiple macros retain their individual controls under the panel.
          if #owned>1 then
            for _,entry in ipairs(owned) do
              if #controlRows>=200 then break end
              local detail=g_ui.createWidget('ScriptControlRow',panel.list)
              if HelperTheme then HelperTheme.tooltips(detail) end
              detail.name:setText('  '..entry.name)
              detail.name:setTooltip(entry.name)
              detail:setTooltip('Macro de '..script.name..'. Cambia solo este macro.')
              detail.power.onClick=function()
                if controls.setEnabled(entry,not controls.isOn(entry)) then refreshControls(false) end
              end
              controlRows[#controlRows+1]={widget=detail,entry=entry}
            end
          end
        end
      end
      end
    end
    panel.heading:setText('Paneles de tus scripts ('..total..')')
    panel.empty:setText(#controlRows>=200 and 'Filtra para ver los demas controles.' or 'Casilla: disponible. ON/OFF: encender o apagar.')
    panel.emptyState:setText(query~='' and 'Sin coincidencias. Cambia la busqueda.' or 'Marca un script en la lista para mostrar su panel ON/OFF.')
    controlsRevision,controlsQuery=revision,query
  end
  for _,item in ipairs(controlRows)do
    local script=item.script
    local available,on
    if script then
      available=script.enabled
      on=scriptIsRunning(script)
      item.widget.source:setText(script.lastError and 'Error: pulsa ON para reintentar' or on and 'Encendido' or 'Disponible; apagado')
    else
      available=controls and controls.available(item.entry)
      on=available and controls.isOn(item.entry)
      item.widget.source:setText((available and 'Macro de ' or 'Funcion OFF: ')..tostring(item.entry.source or ''))
    end
    item.widget.power:setOn(on==true)
    item.widget.power:setText(on and 'ON' or 'OFF')
    item.widget.power:setEnabled(available==true)
  end
  resizeScriptLists()
end
managerWindow.liveControls.search.onTextChange=function()refreshControls(true)end
local previousVisibility=managerWindow.onVisibilityChange
managerWindow.onVisibilityChange=function(widget,visible)
  if type(previousVisibility)=='function' then previousVisibility(widget,visible) end
  if visible then refreshControls(false) end
end
macro(500,function()
  if sharedRuntime.generation~=managerGeneration then return end
  if RinoScriptControls and not RinoScriptControls.valid() then return end
  if managerWindow and managerWindow:isVisible() then refreshControls(false) end
end)

local function openCodeEditor(text, options, callback)
  return UI.MultilineEditorWindow(text, options, callback)
end

local function selectScript(entry)
  selectedScriptId = entry and entry.id or nil
  managerWindow.scriptName:setText(entry and entry.name or "")
end

local function editScript(entry)
  if not entry then return end
  selectScript(entry)

  openCodeEditor(entry.code or "", {
    title = "Editar: " .. entry.name,
    description = "El codigo se valida antes de guardarse. Los cambios reemplazan la ejecucion actual."
  }, function(text)
    if findScript(entry.id) ~= entry then
      setStatus("Este script ya no existe; cancela la edicion", "#ff6666")
      return false
    end
    local valid, compileError = compileScript(text, entry.name)
    if not valid then
      setStatus("No guardado: " .. tostring(compileError), "#ff6666")
      warn("[Script Manager] No se guardo " .. entry.name .. ":\n" .. tostring(compileError))
      return false
    end

    saveBackup(entry, entry.code)
    stopRuntime(sharedRuntime.runtimes[entry.id], true)
    sharedRuntime.runtimes[entry.id] = nil
    entry.code = text
    entry.lastError = nil

    if entry.enabled and entry.running~=false then startScript(entry) end
    setStatus(entry.name .. " guardado", "#66ff66")
    refreshList()
    return true
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
  sharedRuntime.iconRevision=(sharedRuntime.iconRevision or 0)+1
  if not managerWindow or not managerWindow.scriptList then return end
  if deathQuickSwitch then
    local entry = findScript(managerConfig.deathDialogScriptId)
    deathQuickSwitch:setVisible(entry ~= nil)
    deathQuickSwitch:setOn(entry and scriptIsRunning(entry) or false)
    deathQuickSwitch:setEnabled(entry and entry.enabled==true or false)
  end
  if cosmeticsQuickSwitch then
    local entry = findScript(managerConfig.cosmeticsScriptId)
    cosmeticsQuickSwitch:setVisible(entry ~= nil)
    cosmeticsQuickSwitch:setOn(entry and scriptIsRunning(entry) or false)
    cosmeticsQuickSwitch:setEnabled(entry and entry.enabled==true or false)
  end
  managerWindow.scriptList:destroyChildren()

  resizeScriptLists()

  for _, entry in ipairs(managerConfig.scripts) do
    local row = g_ui.createWidget("InGameScriptRow", managerWindow.scriptList)
    if HelperTheme then HelperTheme.tooltips(row) end
    row:setId("ingameScript" .. tostring(entry.id))
    row.name:setText(entry.name)
    row.name:setTooltip(entry.name)
    row.enabled:setChecked(entry.enabled)

    if entry.lastError then
      row.name:setColor("#ff6666")
      row:setTooltip(entry.lastError)
    elseif entry.enabled then
      row.name:setColor("#66ff66")
      row:setTooltip("Disponible en sus paneles ON/OFF para encenderlo o apagarlo.")
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
  if managerWindow:isVisible() then refreshControls(true) else controlsRevision=-1 end
end

managerWindow.addButton.onClick = function()
  local scriptName = trim(managerWindow.scriptName:getText())
  if scriptName == "" then
    setStatus("Escribe el nombre del nuevo script", "#ffcc66")
    return
  end

  openCodeEditor("", {
    title = "Nuevo: " .. scriptName,
    description = "El script se guardara y activara si el codigo Lua es valido."
  }, function(text)
    local valid, compileError = compileScript(text, scriptName)
    if not valid then
      setStatus("No guardado: " .. tostring(compileError), "#ff6666")
      return false
    end

    local entry = {
      id = managerConfig.nextId,
      name = scriptName,
      code = text,
      enabled = true,
      running = false
    }
    managerConfig.nextId = managerConfig.nextId + 1
    table.insert(managerConfig.scripts, entry)
    selectedScriptId = entry.id

    setStatus(scriptName .. " disponible; pulsa ON en su panel", "#66ff66")
    refreshList()
    return true
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
local function openManagerWindow()
  refreshList()
  managerWindow:show()
  managerWindow:raise()
  managerWindow:focus()
end

sharedRuntime.open = openManagerWindow
sharedRuntime.getWindow = function() return managerWindow end
sharedRuntime.getButton = function() return managerButton end
sharedRuntime.prepare = function() refreshList(); return true end
-- Stable icon bindings refer to saved script IDs, never list positions/code.
sharedRuntime.listIconTargets=function()
  local result={}
  if sharedRuntime.generation~=managerGeneration then return result end
  for _,entry in ipairs(managerConfig.scripts) do result[#result+1]={id=tostring(entry.id),name=entry.name} end
  return result
end
sharedRuntime.getIconState=function(id)
  if sharedRuntime.generation~=managerGeneration then return nil end
  local entry=findScript(tonumber(id) or id)
  if entry then return entry.enabled==true end
  return nil
end
sharedRuntime.setIconState=function(id,enabled)
  if sharedRuntime.generation~=managerGeneration then return false end
  local entry=findScript(tonumber(id) or id);if not entry then return false end
  local ok=setScriptEnabled(entry,enabled==true);refreshList();return ok
end
sharedRuntime.openIconSource=function(id)
  if sharedRuntime.generation~=managerGeneration then return false end
  local entry=findScript(tonumber(id) or id);if not entry then return false end
  selectScript(entry);openManagerWindow();return true
end

managerButton = UI.Button("In-Game Script Editor", openManagerWindow)
managerButton:setImageColor("#2de0d7")
managerButton:setFont("verdana-11px-rounded")
managerButton:setTooltip("Administra scripts Lua guardados y activa cada uno con su checkbox.")
UI.Separator()

for _, entry in ipairs(managerConfig.scripts) do
  if entry.enabled and entry.running~=false then startScript(entry) end
end

-- Mismo estilo que Mantener Cast; situado en Main, despues de sus macros.
if findScript(managerConfig.deathDialogScriptId) then
  setMainAsDefaultTab()
  deathQuickSwitch = UI.createWidget("BotSwitch")
  deathQuickSwitch:setId("ingameAcceptDeathSwitch")
  deathQuickSwitch:setText("Aceptar muerte")
  deathQuickSwitch:setTooltip("Acepta el Ok de la pantalla de muerte. ON/OFF comparte el estado con su panel de Scripts.")
  deathQuickSwitch.onClick = function()
    local entry = findScript(managerConfig.deathDialogScriptId)
    if entry then setScriptRunning(entry, not scriptIsRunning(entry)); refreshList() end
  end
  sharedRuntime.deathSwitch = deathQuickSwitch
end
sharedRuntime.getDeathButton = function() return deathQuickSwitch end

-- Debajo de Aceptar muerte; ambos controles usan el estado del editor.
if findScript(managerConfig.cosmeticsScriptId) then
  setMainAsDefaultTab()
  cosmeticsQuickSwitch = UI.createWidget("BotSwitch")
  cosmeticsQuickSwitch:setId("ingameHidePetsSwitch")
  cosmeticsQuickSwitch:setText("Ocultar mascotas")
  cosmeticsQuickSwitch:setTooltip("Oculta las mascotas. ON/OFF comparte el estado con su panel de Scripts.")
  cosmeticsQuickSwitch.onClick = function()
    local entry = findScript(managerConfig.cosmeticsScriptId)
    if entry then setScriptRunning(entry, not scriptIsRunning(entry)); refreshList() end
  end
  cosmeticsQuickSwitch.onDestroy = function()
    if sharedRuntime.generation == managerGeneration then
      stopRuntime(sharedRuntime.runtimes[managerConfig.cosmeticsScriptId], false)
    end
  end
  sharedRuntime.cosmeticsSwitch = cosmeticsQuickSwitch
end
sharedRuntime.getCosmeticsButton = function() return cosmeticsQuickSwitch end

refreshList()
vBot.InGameScriptManagerLoaded = true
