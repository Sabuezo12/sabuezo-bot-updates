setDefaultTab("Main")

local function getEditorConfigName()
  if type(configName) == "string" and configName ~= "" then return configName end
  if type(botConfigName) == "string" and botConfigName ~= "" then return botConfigName end
  if storage and type(storage._configName) == "string" and storage._configName ~= "" then return storage._configName end

  local ok, currentName = pcall(function()
    return modules.game_bot.contentsPanel.config:getCurrentOption().text
  end)
  if ok and type(currentName) == "string" and currentName ~= "" then return currentName end

  return "Sabuezo"
end

local editorConfigName = getEditorConfigName()
local backupDir = "/bot/" .. editorConfigName .. "/_script_editor_backups"

local function compileScript(text)
  local loader = load or loadstring
  if not loader then
    return false, "Este cliente no tiene load/loadstring disponible."
  end

  local ok, chunkOrError = pcall(function()
    return loader(text or "", "ingame_editor")
  end)
  if not ok then return false, chunkOrError end
  if type(chunkOrError) ~= "function" then return false, tostring(chunkOrError) end

  return true, chunkOrError
end

local function safeTimestamp()
  return os.date("%Y%m%d-%H%M%S")
end

local function saveBackup(previousText)
  if type(previousText) ~= "string" or previousText:len() == 0 then return end

  storage.ingame_hotkeys_backups = storage.ingame_hotkeys_backups or {}
  table.insert(storage.ingame_hotkeys_backups, 1, {
    time = safeTimestamp(),
    text = previousText
  })

  while #storage.ingame_hotkeys_backups > 10 do
    table.remove(storage.ingame_hotkeys_backups)
  end

  if g_resources and g_resources.makeDir and g_resources.writeFileContents then
    if not g_resources.directoryExists(backupDir) then
      pcall(function() g_resources.makeDir(backupDir) end)
    end

    local fileName = backupDir .. "/ingame_hotkeys-" .. safeTimestamp() .. ".lua"
    pcall(function() g_resources.writeFileContents(fileName, previousText) end)
  end
end

-- allows to test/edit bot lua scripts ingame, you can have multiple scripts like this, just change storage.ingame_lua
local btIn = UI.Button("In-Game Script Editor", function(newText)
  UI.MultilineEditorWindow(storage.ingame_hotkeys or "", {title="In-Game Macro/Script Editor", description="Valida Lua antes de guardar y conserva los ultimos 10 respaldos."}, function(text)
    local valid, result = compileScript(text)
    if not valid then
      warn("In-Game Script Editor: script not saved.\n" .. tostring(result))
      return
    end

    saveBackup(storage.ingame_hotkeys or "")
    storage.ingame_hotkeys = text
    warn("In-Game Script Editor: script saved. Backup created.")
    reload()
  end)
end)
btIn:setImageColor('#2de0d7')
    
for _, scripts in pairs({storage.ingame_hotkeys}) do
  if type(scripts) == "string" and scripts:len() > 3 then
    UI.Separator()
    local label = UI.Label("In-Game Scripts:")
    label:setColor('#9dd1ce')
    label:setFont('verdana-11px-rounded')
    local status, result = pcall(function()
      local valid, chunkOrError = compileScript(scripts)
      assert(valid, chunkOrError)
      chunkOrError()
    end)
    if not status then 
      error("Ingame editor error:\n" .. result)
    end
  end
end

UI.Separator()
