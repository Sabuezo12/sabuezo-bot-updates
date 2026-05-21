local manifestUrl = "https://raw.githubusercontent.com/Sabuezo12/sabuezo-bot-updates/main/manifest.json"

local function log(text)
  if warn then
    warn("[Sabuezo Updater] " .. text)
  else
    print("[Sabuezo Updater] " .. text)
  end
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
  local backupDir = backupRoot .. "/bootstrap_backup_" .. safeName(version)
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

local function installFiles(manifest, index, installed)
  local files = manifest.files or {}
  if index > #files then
    storage.sabuezoUpdater = storage.sabuezoUpdater or {}
    storage.sabuezoUpdater.version = tostring(manifest.version or "unknown")
    storage.sabuezoUpdater.manifestUrl = manifestUrl
    log("Installed version " .. tostring(manifest.version or "unknown") .. ". Restart the client/bot.")
    return
  end

  local entry = files[index]
  local path = normalizePath(entry and entry.path)
  local url = entry and entry.url

  if not isAllowedPath(path) or type(url) ~= "string" or url:len() == 0 then
    installFiles(manifest, index + 1, installed)
    return
  end

  log("Downloading " .. index .. "/" .. #files .. ": " .. path)
  httpGet(url, function(contents, err)
    if not contents then
      log("Failed: " .. path .. " - " .. tostring(err))
      return
    end

    local configName = getConfigName()
    backupExisting(configName, path, "before_bootstrap")

    local targetPath = "/bot/" .. configName .. "/" .. path
    local ok, writeErr = pcall(function()
      g_resources.writeFileContents(targetPath, contents)
    end)
    if not ok then
      log("Write failed: " .. path .. " - " .. tostring(writeErr))
      return
    end

    schedule(50, function()
      installFiles(manifest, index + 1, installed + 1)
    end)
  end)
end

log("Fetching manifest...")
httpGet(manifestUrl, function(data, err)
  if not data then
    log("Manifest error: " .. tostring(err))
    return
  end

  local ok, manifest = pcall(function()
    return json.decode(data)
  end)
  if not ok or type(manifest) ~= "table" or type(manifest.files) ~= "table" then
    log("Invalid manifest")
    return
  end

  installFiles(manifest, 1, 0)
end)
