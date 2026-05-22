setDefaultTab("Main")

local panelName = "sabuezoUpdater"
if type(storage[panelName]) ~= "table" then storage[panelName] = {} end

local config = storage[panelName]
config.manifestUrl = config.manifestUrl or "https://raw.githubusercontent.com/Sabuezo12/sabuezo-bot-updates/main/manifest.json"
config.version = config.version or "none"
if type(config.fileHashes) ~= "table" then config.fileHashes = {} end

local ui = setupUI([[
Panel
  height: 82

  Label
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    width: 90
    height: 17
    text-align: center
    font: verdana-11px-rounded
    background: #006060
    color: #ffffff
    text: Updater

  Button
    id: open
    anchors.top: title.top
    anchors.left: title.right
    anchors.right: parent.right
    height: 17
    margin-left: 3
    text: Check
    tooltip: Abrir ventana de actualizaciones

  Label
    id: status
    anchors.top: title.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    height: 58
    margin-top: 4
    text-align: center
    font: verdana-11px-rounded
    background: #292A2A
    color: #cfd3d7
    text-wrap: true
]], parent)
ui:setId(panelName)

local installing = false
local lastManifest = nil
local lastPendingFiles = {}
local detailsWindow = nil
local ensureDetailsWindow

local function trim(text)
  return tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function setStatus(text, color)
  if ui.status then
    ui.status:setText(text)
    ui.status:setColor(color or "#cfd3d7")
  end
  if detailsWindow and detailsWindow.status then
    detailsWindow.status:setText(text)
    detailsWindow.status:setColor(color or "#cfd3d7")
  end
end

local function parseVersion(version)
  version = tostring(version or "")
  local parts = {}
  for part in version:gmatch("%d+") do
    table.insert(parts, tonumber(part) or 0)
  end
  if #parts == 0 then return nil end
  return parts
end

local function compareVersions(left, right)
  local a = parseVersion(left)
  local b = parseVersion(right)
  if not a and not b then return 0 end
  if not a then return -1 end
  if not b then return 1 end

  local maxParts = math.max(#a, #b)
  for i = 1, maxParts do
    local av = a[i] or 0
    local bv = b[i] or 0
    if av > bv then return 1 end
    if av < bv then return -1 end
  end
  return 0
end

local function isNewerVersion(version, baseVersion)
  return compareVersions(version, baseVersion) > 0
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

local function makeTargetPath(path)
  return "/bot/" .. getConfigName() .. "/" .. normalizePath(path)
end

local function localFileExists(path)
  if not isAllowedPath(path) then return false end
  return g_resources.fileExists(makeTargetPath(path))
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

local function getHistoryEntries(manifest, fromVersion)
  local entries = {}
  if type(manifest) ~= "table" or type(manifest.history) ~= "table" then return entries end

  for _, entry in ipairs(manifest.history) do
    if type(entry) == "table" and isNewerVersion(entry.version, fromVersion) then
      table.insert(entries, entry)
    end
  end

  table.sort(entries, function(a, b)
    return compareVersions(a.version, b.version) < 0
  end)
  return entries
end

local function getHistoryPathSet(manifest, fromVersion)
  local set = {}
  local count = 0
  for _, historyEntry in ipairs(getHistoryEntries(manifest, fromVersion)) do
    if type(historyEntry.files) == "table" then
      for _, path in ipairs(historyEntry.files) do
        local normalized = normalizePath(path)
        if isAllowedPath(normalized) and not set[normalized] then
          set[normalized] = true
          count = count + 1
        end
      end
    end
  end
  return set, count
end

local function getPendingFiles(manifest)
  local pending = {}
  if type(manifest) ~= "table" or type(manifest.files) ~= "table" then return pending end

  local remoteVersion = tostring(manifest.version or "unknown")
  local localVersion = tostring(config.version or "none")
  local sameVersion = remoteVersion == localVersion
  local historyPaths, historyCount = getHistoryPathSet(manifest, localVersion)
  local useHistoryPaths = not sameVersion and localVersion ~= "none" and historyCount > 0

  for _, entry in ipairs(manifest.files) do
    local path = normalizePath(entry and entry.path)
    local hash = tostring(entry and entry.sha256 or "")
    if isAllowedPath(path) and type(entry.url) == "string" and entry.url:len() > 0 then
      local storedHash = config.fileHashes[path]
      local missing = not localFileExists(path)
      local changedHash = hash:len() > 0 and storedHash and storedHash ~= hash

      if sameVersion then
        if missing or changedHash then table.insert(pending, entry) end
      elseif useHistoryPaths then
        if historyPaths[path] or missing or changedHash then table.insert(pending, entry) end
      else
        if missing or not storedHash or changedHash then table.insert(pending, entry) end
      end
    end
  end

  return pending
end

local function rememberExistingHashes(manifest)
  if type(manifest) ~= "table" or type(manifest.files) ~= "table" then return end
  for _, entry in ipairs(manifest.files) do
    local path = normalizePath(entry and entry.path)
    local hash = tostring(entry and entry.sha256 or "")
    if isAllowedPath(path) and hash:len() > 0 and localFileExists(path) then
      config.fileHashes[path] = hash
    end
  end
end

local function addListLine(parent, text, color)
  if not parent then return end
  local ok, widget = pcall(function()
    return UI.createWidget("UpdaterListLabel", parent)
  end)
  if not ok or not widget then return end
  widget:setText(tostring(text or ""))
  widget:setColor(color or "#cfd3d7")
end

local function fillList(parent, lines, emptyText)
  if not parent then return end
  parent:destroyChildren()
  if #lines == 0 then
    addListLine(parent, emptyText or "No data", "#777777")
    return
  end
  for _, line in ipairs(lines) do
    addListLine(parent, line.text or line, line.color)
  end
end

local function buildChangeLines(manifest, maxLines)
  local lines = {}
  local history = getHistoryEntries(manifest, tostring(config.version or "none"))

  for _, entry in ipairs(history) do
    local version = tostring(entry.version or "?")
    local title = trim(entry.title or "")
    if title ~= "" then
      table.insert(lines, { text = version .. " - " .. title, color = "#9dd1ce" })
    else
      table.insert(lines, { text = version, color = "#9dd1ce" })
    end

    if type(entry.changes) == "table" then
      for _, change in ipairs(entry.changes) do
        change = trim(change)
        if change ~= "" then table.insert(lines, "  - " .. change) end
      end
    elseif type(entry.summary) == "string" then
      for change in entry.summary:gmatch("[^\n]+") do
        change = trim(change)
        if change ~= "" then table.insert(lines, "  - " .. change) end
      end
    end
  end

  if #lines == 0 then
    local summary = manifest and manifest.summary
    if type(summary) == "table" then
      for _, line in ipairs(summary) do
        line = trim(line)
        if line ~= "" then table.insert(lines, "- " .. line) end
      end
    elseif type(summary) == "string" then
      for line in summary:gmatch("[^\n]+") do
        line = trim(line)
        if line ~= "" then table.insert(lines, "- " .. line) end
      end
    end
  end

  local limit = tonumber(maxLines)
  if limit and #lines > limit then
    local limited = {}
    for i = 1, limit do table.insert(limited, lines[i]) end
    table.insert(limited, "+" .. (#lines - limit) .. " more in details")
    return limited
  end

  return lines
end

local function buildFileLines(pendingFiles)
  local lines = {}
  for _, entry in ipairs(pendingFiles or {}) do
    table.insert(lines, "- " .. normalizePath(entry.path))
  end
  return lines
end

local function refreshDetailsWindow(manifest)
  if not detailsWindow then return end

  local remoteVersion = manifest and tostring(manifest.version or "unknown") or "-"
  local localVersion = tostring(config.version or "none")
  lastPendingFiles = manifest and getPendingFiles(manifest) or {}

  detailsWindow.installed:setText(localVersion)
  detailsWindow.remote:setText(remoteVersion)

  fillList(detailsWindow.changesList, buildChangeLines(manifest or {}), "No update notes for this version.")
  fillList(detailsWindow.filesList, buildFileLines(lastPendingFiles), "No files pending.")

  if manifest then
    if remoteVersion == localVersion and #lastPendingFiles == 0 then
      detailsWindow.status:setText("Already updated")
      detailsWindow.status:setColor("#8cff9a")
    else
      detailsWindow.status:setText("Pending files: " .. #lastPendingFiles)
      detailsWindow.status:setColor("#ffd166")
    end
  else
    detailsWindow.status:setText("Press Check to load update info")
    detailsWindow.status:setColor("#cfd3d7")
  end
end

local function formatSummary(manifest, maxLines)
  local lines = buildChangeLines(manifest or {}, maxLines)
  local visible = {}
  for _, line in ipairs(lines) do
    if type(line) == "table" then
      table.insert(visible, line.text)
    else
      table.insert(visible, line)
    end
  end
  return table.concat(visible, "\n")
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
    lastPendingFiles = getPendingFiles(manifest)
    refreshDetailsWindow(manifest)
    callback(manifest)
  end)
end

local function finishInstall(manifest, installed, skipped)
  installing = false
  config.version = tostring(manifest.version or config.version)
  rememberExistingHashes(manifest)
  lastPendingFiles = getPendingFiles(manifest)
  if ensureDetailsWindow then ensureDetailsWindow() end
  refreshDetailsWindow(manifest)

  local skippedText = skipped > 0 and (" | skipped " .. skipped) or ""
  setStatus("Updated to " .. config.version .. "\nDownloaded " .. installed .. " files" .. skippedText, "#8cff9a")
end

local function installFileList(manifest, files, index, installed, skipped)
  if index > #files then
    finishInstall(manifest, installed, skipped)
    return
  end

  local entry = files[index]
  local path = normalizePath(entry and entry.path)
  local url = entry and entry.url

  if not isAllowedPath(path) or type(url) ~= "string" or url:len() == 0 then
    installFileList(manifest, files, index + 1, installed, skipped + 1)
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

    local hash = tostring(entry.sha256 or "")
    if hash:len() > 0 then config.fileHashes[path] = hash end

    schedule(50, function()
      installFileList(manifest, files, index + 1, installed + 1, skipped)
    end)
  end)
end

local function installManifest(manifest)
  if installing then return end

  lastPendingFiles = getPendingFiles(manifest)
  refreshDetailsWindow(manifest)

  if #lastPendingFiles == 0 then
    config.version = tostring(manifest.version or config.version)
    rememberExistingHashes(manifest)
    refreshDetailsWindow(manifest)
    setStatus("Already updated\n" .. tostring(config.version or "none"), "#8cff9a")
    return
  end

  installing = true
  installFileList(manifest, lastPendingFiles, 1, 0, 0)
end

local function showManifestStatus(manifest)
  if not manifest then return end

  local remoteVersion = tostring(manifest.version or "unknown")
  local localVersion = tostring(config.version or "none")
  lastPendingFiles = getPendingFiles(manifest)

  if remoteVersion == localVersion and #lastPendingFiles == 0 then
    rememberExistingHashes(manifest)
    local summary = formatSummary(manifest, 3)
    if summary:len() > 0 then
      setStatus("Already updated: " .. localVersion .. "\n" .. summary, "#8cff9a")
    else
      setStatus("Already updated\n" .. localVersion, "#8cff9a")
    end
  else
    local summary = formatSummary(manifest, 4)
    if summary:len() > 0 then
      setStatus("New: " .. remoteVersion .. " | Installed: " .. localVersion .. "\nFiles: " .. #lastPendingFiles .. "\n" .. summary, "#ffd166")
    else
      setStatus("New version: " .. remoteVersion .. "\nInstalled: " .. localVersion .. "\nFiles: " .. #lastPendingFiles, "#ffd166")
    end
  end

  refreshDetailsWindow(manifest)
end

local function checkUpdates(showDetails)
  fetchManifest(function(manifest)
    if not manifest then return end
    showManifestStatus(manifest)
    if showDetails and detailsWindow then
      detailsWindow:show()
      detailsWindow:raise()
      detailsWindow:focus()
    end
  end)
end

local function runInstall()
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

local function bindDetailsWindow(window)
  detailsWindow = window
  detailsWindow:hide()

  detailsWindow.check.onClick = function()
    checkUpdates(false)
  end

  detailsWindow.install.onClick = function()
    runInstall()
  end

  detailsWindow.closeButton.onClick = function()
    detailsWindow:hide()
  end

  refreshDetailsWindow(nil)
end

ensureDetailsWindow = function()
  if detailsWindow then return true end

  local rootWidget = g_ui.getRootWidget()
  if not rootWidget then return false end

  local stylePath = "/bot/" .. getConfigName() .. "/vBot/Updater.otui"
  pcall(function()
    g_ui.importStyle(stylePath)
  end)

  local ok, window = pcall(function()
    return UI.createWindow("UpdaterWindow", rootWidget)
  end)

  if not ok or not window then return false end

  bindDetailsWindow(window)
  return true
end

ensureDetailsWindow()

ui.open.onClick = function()
  if ensureDetailsWindow() then
    refreshDetailsWindow(lastManifest)
    detailsWindow:show()
    detailsWindow:raise()
    detailsWindow:focus()
  else
    setStatus("No se cargo Updater.otui\nRecarga el bot o actualiza de nuevo", "#ff8a8a")
  end
end

setStatus("Installed: " .. tostring(config.version or "none"))

schedule(1500, function()
  if not installing then
    checkUpdates(false)
  end
end)

UI.Separator()
