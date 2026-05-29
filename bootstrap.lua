local manifestUrl = "https://raw.githubusercontent.com/Sabuezo12/sabuezo-bot-updates/main/manifest.json"

local function log(text)
  if warn then
    warn("[Sabuezo Updater] " .. text)
  else
    print("[Sabuezo Updater] " .. text)
  end
end

local httpDownloadSerial = 0

local function httpGet(url, callback)
  local http = modules and modules.corelib and modules.corelib.HTTP or HTTP
  local function resolveRawHttp()
    local function usable(candidate)
      return type(candidate) == "table" and (candidate.get or candidate.download)
    end

    if usable(g_http) then return g_http end
    if rawget and type(_G) == "table" and usable(rawget(_G, "g_http")) then
      return rawget(_G, "g_http")
    end
    if modules and modules.corelib then
      if usable(modules.corelib.g_http) then return modules.corelib.g_http end
      if type(modules.corelib.HTTP) == "table" and usable(modules.corelib.HTTP.g_http) then
        return modules.corelib.HTTP.g_http
      end
    end

    local envSources = {}
    if http then
      table.insert(envSources, http.get)
      table.insert(envSources, http.download)
      table.insert(envSources, http.post)
    end

    local envGetters = {}
    if getfenv then table.insert(envGetters, getfenv) end
    if debug and debug.getfenv then table.insert(envGetters, debug.getfenv) end

    for _, source in ipairs(envSources) do
      if type(source) == "function" then
        for _, getter in ipairs(envGetters) do
          local ok, env = pcall(getter, source)
          if ok and type(env) == "table" and usable(env.g_http) then
            return env.g_http
          end
        end
      end
    end

    return nil
  end

  local rawHttp = resolveRawHttp()

  if (not http or (not http.get and not http.download)) and
    (not rawHttp or (not rawHttp.get and not rawHttp.download)) then
    callback(nil, "HTTP unavailable")
    return
  end

  local function shortError(err)
    err = tostring(err or "HTTP request failed")
    err = err:gsub("\r", " "):gsub("\n", " "):gsub("%s+", " ")
    err = err:gsub("^.-ERROR:%s*", "")
    if err:len() > 180 then err = err:sub(1, 180) .. "..." end
    return err
  end

  local function looksLikeData(value)
    return type(value) == "string" and value:match("^%s*[%{%[]")
  end

  local function tablePayload(value)
    if type(value) ~= "table" then return nil end
    local keys = {"data", "body", "content", "response", "result", "text"}
    for _, key in ipairs(keys) do
      if looksLikeData(value[key]) then return value[key] end
    end
    for _, item in pairs(value) do
      if looksLikeData(item) then return item end
    end
    return nil
  end

  local function describeValue(value)
    if type(value) ~= "table" then return shortError(value) end

    local parts = {}
    local count = 0
    for key, item in pairs(value) do
      count = count + 1
      if count > 8 then
        table.insert(parts, "...")
        break
      end

      local itemText = tostring(item)
      itemText = itemText:gsub("\r", " "):gsub("\n", " "):gsub("%s+", " ")
      if itemText:len() > 60 then itemText = itemText:sub(1, 60) .. "..." end
      table.insert(parts, tostring(key) .. "=" .. itemText)
    end

    if #parts == 0 then return "empty table" end
    return "table {" .. table.concat(parts, ", ") .. "}"
  end

  local function makeHeaders()
    return {
      Accept = "*/*",
      ["User-Agent"] = "Mozilla/5.0"
    }
  end

  local function readDownloadedFile(path, fallback)
    local candidates = {}
    local function add(candidate)
      if type(candidate) ~= "string" or candidate:len() == 0 then return end
      table.insert(candidates, candidate)
      if candidate:sub(1, 1) ~= "/" then
        table.insert(candidates, "/downloads/" .. candidate)
      end
    end

    add(path)
    add(fallback)

    for _, candidate in ipairs(candidates) do
      local ok, contents = pcall(function()
        return g_resources.readFileContents(candidate)
      end)
      if ok and type(contents) == "string" and contents:len() > 0 then
        return contents
      end
    end

    return nil
  end

  local function onResponse(first, second)
    if looksLikeData(first) then
      callback(first)
      return
    end
    if looksLikeData(second) then
      callback(second)
      return
    end
    local firstPayload = tablePayload(first)
    if firstPayload then
      callback(firstPayload)
      return
    end
    local secondPayload = tablePayload(second)
    if secondPayload then
      callback(secondPayload)
      return
    end

    local err = second or first
    if err and describeValue(err):len() > 0 then
      callback(nil, describeValue(err))
      return
    end

    callback(nil, "empty response")
  end

  local lastError
  local function hasStdMapError()
    return type(lastError) == "string" and lastError:find("std::map", 1, true) ~= nil
  end

  if rawHttp and rawHttp.get then
    local headers = makeHeaders()
    local timeout = tonumber(http and (http.timeout or http.TIMEOUT)) or 60
    local rawAttempts = {
      {name = "g_http.get timeout headers", call = function() return rawHttp.get(url, timeout, headers) end},
      {name = "g_http.get headers timeout", call = function() return rawHttp.get(url, headers, timeout) end},
      {name = "g_http.get old timeout", old = true, call = function() return rawHttp.get(url, timeout) end}
    }

    http.operations = http.operations or {}
    for _, attempt in ipairs(rawAttempts) do
      if not attempt.old or not hasStdMapError() then
        local ok, operation = pcall(attempt.call)
        if ok and operation ~= nil then
          http.operations[operation] = {type = "get", url = url, callback = onResponse}
          return operation
        end
        if ok then
          lastError = attempt.name .. " returned nil"
        else
          lastError = attempt.name .. ": " .. shortError(operation)
        end
      end
    end
  end

  if (not rawHttp or not rawHttp.get) and http and http.get then
    local headers = makeHeaders()
    local attempts = {
      {"HTTP.get callback headers", function() return http.get(url, onResponse, headers) end},
      {"HTTP.get headers callback", function() return http.get(url, headers, onResponse) end}
    }

    for _, attempt in ipairs(attempts) do
      local ok, result = pcall(attempt[2])
      if ok and result ~= nil then return result end
      if ok then
        lastError = attempt[1] .. " returned nil"
      else
        lastError = attempt[1] .. ": " .. shortError(result)
      end
    end
  end

  if g_resources and g_resources.readFileContents then
    httpDownloadSerial = httpDownloadSerial + 1
    local downloadFile = "sabuezo_updater_" .. tostring(httpDownloadSerial) .. ".tmp"
    local function onDownload(path, checksum, err)
      if err and tostring(err):len() > 0 then
        callback(nil, shortError(err))
        return
      end

      local contents = readDownloadedFile(path, downloadFile)
      if looksLikeData(contents) then
        callback(contents)
      else
        callback(nil, "download finished but file could not be read")
      end
    end

    if rawHttp and rawHttp.download then
      local headers = makeHeaders()
      local timeout = tonumber(http and (http.timeout or http.TIMEOUT)) or 60
      local rawDownloads = {
        {name = "g_http.download timeout headers", call = function() return rawHttp.download(url, downloadFile, timeout, headers) end},
        {name = "g_http.download headers timeout", call = function() return rawHttp.download(url, downloadFile, headers, timeout) end},
        {name = "g_http.download old timeout", old = true, call = function() return rawHttp.download(url, downloadFile, timeout) end}
      }

      http.operations = http.operations or {}
      for _, attempt in ipairs(rawDownloads) do
        if not attempt.old or not hasStdMapError() then
          local ok, operation = pcall(attempt.call)
          if ok and operation ~= nil then
            http.operations[operation] = {type = "download", url = url, file = downloadFile, callback = onDownload}
            return operation
          end
          if ok then
            lastError = attempt.name .. " returned nil"
          else
            lastError = attempt.name .. ": " .. shortError(operation)
          end
        end
      end
    end

    if not rawHttp or not rawHttp.download then
      lastError = tostring(lastError or "No direct g_http access") .. " | HTTP.download wrapper skipped"
    end
  end

  callback(nil, tostring(lastError or "HTTP request failed"))
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
