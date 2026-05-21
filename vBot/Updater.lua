setDefaultTab("Main")

local panelName = "sabuezoUpdater"
storage[panelName] = storage[panelName] or {}

local config = storage[panelName]
config.manifestUrl = config.manifestUrl or "https://raw.githubusercontent.com/Sabuezo12/sabuezo-bot-updates/main/manifest.json"
config.version = config.version or "none"

local ui = setupUI([[
Panel
  height: 55

  Label
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    width: 86
    height: 17
    text-align: center
    font: verdana-11px-rounded
    background: #006060
    color: #ffffff
    text: Updater

  Button
    id: check
    anchors.top: title.top
    anchors.left: title.right
    width: 48
    height: 17
    margin-left: 3
    text: Check

  Button
    id: install
    anchors.top: title.top
    anchors.left: check.right
    anchors.right: parent.right
    height: 17
    margin-left: 3
    text: Update

  Label
    id: status
    anchors.top: title.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    height: 33
    margin-top: 4
    text-align: center
    font: verdana-11px-rounded
    background: #292A2A
    color: #cfd3d7
    text-wrap: true
]])
ui:setId(panelName)

local installing = false
local lastManifest = nil

local function setStatus(text, color)
  ui.status:setText(text)
  ui.status:setColor(color or "#cfd3d7")
end

local function httpGet(url, callback)
  local http = modules and modules.corelib and modules.corelib.HTTP or HTTP
  if not http or not http.get then
    callback(nil, "HTTP unavailable")
    return
  end

  http.get(url, function(data, err)
    if err and tostring(err):len() > 0 then
      callback(nil, tostring(err))
      return
    end
    if not data or tostring(data):len() == 0 then
      callback(nil, "empty response")
      return
    end
    callback(data)
  end)
end

local function getConfigName()
  local ok, name = pcall(function()
    return modules.game_bot.contentsPanel.config:getCurrentOption().text
  end)
  if ok and type(name) == "string" and name:len() > 0 then
    return name
  end
  return "Sabuezo"
end

local function safeName(text)
  text = tostring(text or "unknown")
  text = text:gsub("[^%w%._%-]", "_")
  if text:len() == 0 then return "unknown" end
  return text
end

local function normalizePath(path)
  path = tostring(path or ""):gsub("\\", "/")
  path = path:gsub("^/+", ""):gsub("/+$", "")
  return path
end

local function isAllowedPath(path)
  path = normalizePath(path)
  if path:len() == 0 then return false end
  if path:find("%.%.", 1, true) then return false end
  if path:find("[^%w%._%-%s/]") then return false end
  if path:match("^vBot_configs/") or path:match("^cavebot_configs/") or path:match("^targetbot_configs/") then return false end
  if path:match("^storage/") or path:match("^_archive/") then return false end
  if path == "_Loader.lua" then return true end
  if path:match("^vBot/") then return true end
  if path:match("^cavebot/") then return true end
  if path:match("^targetbot/") then return true end
  if path:match("^zFreeScripts/") then return true end
  return false
end

local function ensureDir(path)
  if not g_resources.directoryExists(path) then
    g_resources.makeDir(path)
  end
end

local function backupExisting(configName, filePath, version)
  local targetPath = "/bot/" .. configName .. "/" .. filePath
  if not g_resources.fileExists(targetPath) then return end

  local backupRoot = "/bot/" .. configName .. "/_updates"
  local backupDir = backupRoot .. "/backup_" .. safeName(version)
  ensureDir(backupRoot)
  ensureDir(backupDir)

  local ok, contents = pcall(function()
    return g_resources.readFileContents(targetPath)
  end)
  if not ok or not contents then return end

  local backupFile = backupDir .. "/" .. filePath:gsub("[/\\]", "__")
  pcall(function()
    g_resources.writeFileContents(backupFile, contents)
  end)
end

local function fetchManifest(callback)
  setStatus("Checking updates...", "#ffd166")
  httpGet(config.manifestUrl, function(data, err)
    if not data then
      setStatus("Manifest error: " .. tostring(err), "#ff8a8a")
      callback(nil)
      return
    end

    local ok, manifest = pcall(function()
      return json.decode(data)
    end)
    if not ok or type(manifest) ~= "table" or type(manifest.files) ~= "table" then
      setStatus("Invalid manifest", "#ff8a8a")
      callback(nil)
      return
    end

    lastManifest = manifest
    callback(manifest)
  end)
end

local function installFile(manifest, index, installed, skipped)
  local files = manifest.files or {}
  if index > #files then
    installing = false
    config.version = tostring(manifest.version or config.version)
    setStatus("Updated to " .. config.version .. " (" .. installed .. " files)", "#8cff9a")
    return
  end

  local entry = files[index]
  local path = normalizePath(entry and entry.path)
  local url = entry and entry.url

  if not isAllowedPath(path) or type(url) ~= "string" or url:len() == 0 then
    installFile(manifest, index + 1, installed, skipped + 1)
    return
  end

  setStatus("Downloading " .. index .. "/" .. #files .. "\n" .. path, "#cfd3d7")
  httpGet(url, function(contents, err)
    if not contents then
      installing = false
      setStatus("Download failed:\n" .. path .. "\n" .. tostring(err), "#ff8a8a")
      return
    end

    local configName = getConfigName()
    backupExisting(configName, path, config.version)

    local targetPath = "/bot/" .. configName .. "/" .. path
    local ok, writeErr = pcall(function()
      g_resources.writeFileContents(targetPath, contents)
    end)
    if not ok then
      installing = false
      setStatus("Write failed:\n" .. path .. "\n" .. tostring(writeErr), "#ff8a8a")
      return
    end

    schedule(50, function()
      installFile(manifest, index + 1, installed + 1, skipped)
    end)
  end)
end

local function installManifest(manifest)
  if installing then return end
  installing = true
  installFile(manifest, 1, 0, 0)
end

ui.check.onClick = function()
  fetchManifest(function(manifest)
    if not manifest then return end
    local remoteVersion = tostring(manifest.version or "unknown")
    local localVersion = tostring(config.version or "none")
    if remoteVersion == localVersion then
      setStatus("Already updated\n" .. localVersion, "#8cff9a")
    else
      setStatus("New version: " .. remoteVersion .. "\nInstalled: " .. localVersion, "#ffd166")
    end
  end)
end

ui.install.onClick = function()
  if installing then
    setStatus("Update already running...", "#ffd166")
    return
  end

  if lastManifest then
    installManifest(lastManifest)
    return
  end

  fetchManifest(function(manifest)
    if manifest then installManifest(manifest) end
  end)
end

setStatus("Installed: " .. tostring(config.version or "none"))
UI.Separator()
