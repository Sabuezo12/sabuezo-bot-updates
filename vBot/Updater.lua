setDefaultTab("Main")

local panelName = "sabuezoUpdater"
if type(storage[panelName]) ~= "table" then storage[panelName] = {} end

local config = storage[panelName]
local rawManifestUrl = "https://raw.githubusercontent.com/Sabuezo12/sabuezo-bot-updates/main/manifest.json"
local refsManifestUrl = "https://raw.githubusercontent.com/Sabuezo12/sabuezo-bot-updates/refs/heads/main/manifest.json"
local githubRawManifestUrl = "https://github.com/Sabuezo12/sabuezo-bot-updates/raw/main/manifest.json"
local jsDelivrManifestUrl = "https://cdn.jsdelivr.net/gh/Sabuezo12/sabuezo-bot-updates@main/manifest.json"
local defaultManifestUrl = "https://api.github.com/repos/Sabuezo12/sabuezo-bot-updates/contents/manifest.json?ref=main"
if not config.manifestUrl or config.manifestUrl == refsManifestUrl or config.manifestUrl == rawManifestUrl or
  config.manifestUrl == githubRawManifestUrl or config.manifestUrl == jsDelivrManifestUrl then
  config.manifestUrl = defaultManifestUrl
end
config.version = config.version or "none"
if type(config.fileHashes) ~= "table" then config.fileHashes = {} end
if config.autoInstall == nil then config.autoInstall = true end
if config.autoReload == nil then config.autoReload = true end

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
local autoReloadScheduled = false

local function trim(text)
  return tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function wrapTextLine(text, maxLen)
  text = tostring(text or "")
  maxLen = tonumber(maxLen) or 64
  if text:len() <= maxLen then return { text } end

  local lead = text:match("^%s*") or ""
  local isBullet = text:match("^%s*[-+]") ~= nil
  local prefix = isBullet and (lead .. "- ") or lead
  local continuation = isBullet and (lead .. "  ") or lead
  local content = trim(text)
  if isBullet then content = content:gsub("^[-+]%s*", "") end

  local lines = {}
  local current = ""
  local currentPrefix = prefix

  for word in content:gmatch("%S+") do
    local limit = math.max(12, maxLen - currentPrefix:len())
    if current == "" then
      current = word
    elseif current:len() + word:len() + 1 <= limit then
      current = current .. " " .. word
    else
      table.insert(lines, currentPrefix .. current)
      currentPrefix = continuation
      current = word
    end
  end

  if current ~= "" then table.insert(lines, currentPrefix .. current) end
  return lines
end

local function setPanelStatus(text, color)
  if ui.status then
    ui.status:setText(text)
    ui.status:setColor(color or "#cfd3d7")
  end
end

local function setDetailsStatus(text, color)
  if detailsWindow and detailsWindow.status then
    detailsWindow.status:setText(text)
    detailsWindow.status:setColor(color or "#cfd3d7")
  end
end

local function setStatus(text, color)
  setDetailsStatus(text, color)
end

local function reloadAfterAutoInstall()
  if autoReloadScheduled or not config.autoReload then return end
  autoReloadScheduled = true

  setPanelStatus("Version: " .. tostring(config.version or "none") .. "\nRecargando bot...", "#8cff9a")
  setStatus("Update instalado. Recargando bot...", "#8cff9a")

  schedule(800, function()
    if type(reload) == "function" then
      local ok, err = pcall(reload)
      if not ok then
        setPanelStatus("Version: " .. tostring(config.version or "none") .. "\nReloguea para aplicar", "#ffd166")
        setStatus("Update instalado. Reloguea para aplicar.\n" .. tostring(err), "#ffd166")
      end
    else
      setPanelStatus("Version: " .. tostring(config.version or "none") .. "\nReloguea para aplicar", "#ffd166")
      setStatus("Update instalado. Reloguea para aplicar.", "#ffd166")
    end
  end)
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

local httpDownloadSerial = 0
local httpRequestSerial = 0

local function withCacheBuster(url)
  url = tostring(url or "")
  httpRequestSerial = httpRequestSerial + 1

  local stamp = "0"
  if os and os.time then
    stamp = tostring(os.time())
  end
  stamp = stamp .. "-" .. tostring(now or 0) .. "-" .. tostring(httpRequestSerial)

  local separator = url:find("?", 1, true) and "&" or "?"
  return url .. separator .. "sabuezoCache=" .. stamp
end

local function decodeBase64(data)
  data = tostring(data or ""):gsub("%s", "")
  if data:len() == 0 then return nil end

  local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  data = data:gsub("[^" .. alphabet .. "=]", "")

  local bits = data:gsub(".", function(char)
    if char == "=" then return "" end
    local index = alphabet:find(char, 1, true)
    if not index then return "" end

    local value = index - 1
    local result = ""
    for i = 6, 1, -1 do
      result = result .. ((value % (2 ^ i) - value % (2 ^ (i - 1)) > 0) and "1" or "0")
    end
    return result
  end)

  return bits:gsub("%d%d%d?%d?%d?%d?%d?%d?", function(byte)
    if byte:len() ~= 8 then return "" end

    local value = 0
    for i = 1, 8 do
      if byte:sub(i, i) == "1" then
        value = value + 2 ^ (8 - i)
      end
    end
    return string.char(value)
  end)
end

local function decodeGithubContentResponse(data)
  if type(data) ~= "string" or not data:find('"content"', 1, true) then return data end

  local ok, payload = pcall(function()
    return json.decode(data)
  end)
  if not ok or type(payload) ~= "table" or type(payload.content) ~= "string" then return data end

  local decoded = decodeBase64(payload.content)
  if type(decoded) == "string" and decoded:len() > 0 then return decoded end
  return data
end

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

  local function responseIsSuccess(value)
    if type(value) ~= "table" then return false end

    local err = value.error or value.err
    if err ~= nil and tostring(err):len() > 0 then return false end

    local status = tonumber(value.status or value.statusCode or value.code)
    return status == nil or (status >= 200 and status < 300)
  end

  local function tablePayload(value)
    if type(value) ~= "table" then return nil end
    local keys = {"body", "data", "content", "response", "result", "text"}
    for _, key in ipairs(keys) do
      if type(value[key]) == "string" and value[key]:len() > 0 and
        (responseIsSuccess(value) or looksLikeData(value[key])) then
        return value[key]
      end
    end
    for _, item in pairs(value) do
      if type(item) == "string" and item:len() > 0 and
        (responseIsSuccess(value) or looksLikeData(item)) then
        return item
      end
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
      ["User-Agent"] = "Mozilla/5.0",
      ["Cache-Control"] = "no-cache",
      Pragma = "no-cache"
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

    if type(first) == "string" and first:len() > 0 and
      (second == nil or tostring(second):len() == 0) then
      callback(first)
      return
    end
    if type(second) == "string" and second:len() > 0 and
      (first == nil or tostring(first):len() == 0) then
      callback(second)
      return
    end
    if looksLikeData(first) then
      callback(first)
      return
    end
    if looksLikeData(second) then
      callback(second)
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
    local text = line.text or line
    local color = line.color
    for _, wrapped in ipairs(wrapTextLine(text, 60)) do
      addListLine(parent, wrapped, color)
    end
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

  fillList(detailsWindow.changesList, buildChangeLines(manifest or {}), "No hay notas para esta version.")
  fillList(detailsWindow.filesList, buildFileLines(lastPendingFiles), "No hay archivos pendientes.")

  if manifest then
    if remoteVersion == localVersion and #lastPendingFiles == 0 then
      detailsWindow.status:setText("Ultima version")
      detailsWindow.status:setColor("#8cff9a")
    else
      detailsWindow.status:setText("Archivos pendientes: " .. #lastPendingFiles)
      detailsWindow.status:setColor("#ffd166")
    end
  else
    detailsWindow.status:setText("Usa Check para revisar actualizaciones")
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

local function buildManifestUrls()
  local urls = {}
  local seen = {}

  local function add(url)
    url = tostring(url or "")
    if url:len() == 0 or seen[url] then return end
    seen[url] = true
    table.insert(urls, url)
  end

  add(config.manifestUrl)
  add(defaultManifestUrl)
  add(githubRawManifestUrl)
  add(jsDelivrManifestUrl)
  add(refsManifestUrl)
  add(rawManifestUrl)

  return urls
end

local function fetchManifest(callback)
  local finished = false
  local attempts = buildManifestUrls()
  local attemptIndex = 0
  local activeAttempt = 0
  local lastError = nil

  setPanelStatus("Version: " .. tostring(config.version or "none") .. "\nRevisando...", "#ffd166")
  setStatus("Revisando actualizaciones...", "#ffd166")

  local function fail()
    if finished then return end
    finished = true
    setPanelStatus("Version: " .. tostring(config.version or "none") .. "\nError al revisar", "#ff8a8a")
    setStatus("Manifest error: " .. tostring(lastError or "no response"), "#ff8a8a")
    if callback then callback(nil) end
  end

  local function tryNextManifest()
    if finished then return end

    attemptIndex = attemptIndex + 1
    local url = attempts[attemptIndex]
    if not url then
      fail()
      return
    end

    activeAttempt = activeAttempt + 1
    local token = activeAttempt
    local requestUrl = withCacheBuster(url)

    setPanelStatus("Version: " .. tostring(config.version or "none") .. "\nRevisando " ..
      tostring(attemptIndex) .. "/" .. tostring(#attempts), "#ffd166")

    if type(schedule) == "function" then
      schedule(12000, function()
        if finished or token ~= activeAttempt then return end
        lastError = "timeout en ruta " .. tostring(attemptIndex)
        tryNextManifest()
      end)
    end

    httpGet(requestUrl, function(data, err)
      if finished or token ~= activeAttempt then return end

      if not data then
        lastError = err or ("ruta " .. tostring(attemptIndex) .. " sin respuesta")
        tryNextManifest()
        return
      end

      data = decodeGithubContentResponse(data)

      local ok, manifest = pcall(function()
        return json.decode(data)
      end)
      if not ok or type(manifest) ~= "table" or type(manifest.files) ~= "table" then
        lastError = "manifest invalido en ruta " .. tostring(attemptIndex)
        tryNextManifest()
        return
      end

      finished = true
      config.manifestUrl = url
      lastManifest = manifest
      lastPendingFiles = getPendingFiles(manifest)
      refreshDetailsWindow(manifest)
      if callback then callback(manifest) end
    end)
  end

  if #attempts == 0 then
    fail()
  else
    tryNextManifest()
  end
end

local function finishInstall(manifest, installed, skipped, autoMode)
  installing = false
  config.version = tostring(manifest.version or config.version)
  rememberExistingHashes(manifest)
  lastPendingFiles = getPendingFiles(manifest)
  if ensureDetailsWindow then ensureDetailsWindow() end
  refreshDetailsWindow(manifest)

  local skippedText = skipped > 0 and (" | skipped " .. skipped) or ""
  setPanelStatus("Version: " .. config.version .. "\nUltima version", "#8cff9a")
  setStatus("Actualizado a " .. config.version .. "\nArchivos: " .. installed .. skippedText, "#8cff9a")

  if autoMode and installed > 0 then
    reloadAfterAutoInstall()
  end
end

local function installFileList(manifest, files, index, installed, skipped, autoMode)
  if index > #files then
    finishInstall(manifest, installed, skipped, autoMode)
    return
  end

  local entry = files[index]
  local path = normalizePath(entry and entry.path)
  local url = entry and entry.url

  if not isAllowedPath(path) or type(url) ~= "string" or url:len() == 0 then
    installFileList(manifest, files, index + 1, installed, skipped + 1, autoMode)
    return
  end

  setPanelStatus("Version: " .. tostring(config.version or "none") .. "\nActualizando...", "#ffd166")
  setStatus("Descargando " .. index .. "/" .. #files .. "\n" .. path, "#cfd3d7")

  local finished = false
  local requestUrl = withCacheBuster(url)
  if type(schedule) == "function" then
    schedule(20000, function()
      if finished then return end
      finished = true
      installing = false
      setPanelStatus("Version: " .. tostring(config.version or "none") .. "\nError al actualizar", "#ff8a8a")
      setStatus("Download timeout:\n" .. path .. "\nIntenta de nuevo.", "#ff8a8a")
    end)
  end

  httpGet(requestUrl, function(contents, err)
    if finished then return end
    finished = true

    if not contents then
      installing = false
      setPanelStatus("Version: " .. tostring(config.version or "none") .. "\nError al actualizar", "#ff8a8a")
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
      setPanelStatus("Version: " .. tostring(config.version or "none") .. "\nError al actualizar", "#ff8a8a")
      setStatus("Write failed:\n" .. path .. "\n" .. tostring(writeErr), "#ff8a8a")
      return
    end

    local hash = tostring(entry.sha256 or "")
    if hash:len() > 0 then config.fileHashes[path] = hash end

    schedule(50, function()
      installFileList(manifest, files, index + 1, installed + 1, skipped, autoMode)
    end)
  end)
end

local function installManifest(manifest, autoMode)
  if installing then return end

  lastPendingFiles = getPendingFiles(manifest)
  refreshDetailsWindow(manifest)

  if #lastPendingFiles == 0 then
    config.version = tostring(manifest.version or config.version)
    rememberExistingHashes(manifest)
    refreshDetailsWindow(manifest)
    setPanelStatus("Version: " .. tostring(config.version or "none") .. "\nUltima version", "#8cff9a")
    setStatus("Ultima version", "#8cff9a")
    return
  end

  installing = true
  installFileList(manifest, lastPendingFiles, 1, 0, 0, autoMode == true)
end

local function showManifestStatus(manifest)
  if not manifest then return end

  local remoteVersion = tostring(manifest.version or "unknown")
  local localVersion = tostring(config.version or "none")
  lastPendingFiles = getPendingFiles(manifest)

  if remoteVersion == localVersion and #lastPendingFiles == 0 then
    rememberExistingHashes(manifest)
    setPanelStatus("Version: " .. localVersion .. "\nUltima version", "#8cff9a")
    setStatus("Ultima version", "#8cff9a")
  else
    setPanelStatus("Instalada: " .. localVersion .. "\nDisponible: " .. remoteVersion .. "\nUpdate disponible", "#ffd166")
    setStatus("Archivos pendientes: " .. #lastPendingFiles, "#ffd166")
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

local function autoUpdateOnLogin()
  if installing then return end
  if not config.autoInstall then
    checkUpdates(false)
    return
  end

  fetchManifest(function(manifest)
    if not manifest then return end

    lastPendingFiles = getPendingFiles(manifest)
    if #lastPendingFiles > 0 then
      setPanelStatus("Version: " .. tostring(config.version or "none") .. "\nActualizando...", "#ffd166")
      setStatus("Actualizacion automatica: " .. #lastPendingFiles .. " archivos pendientes", "#ffd166")
      installManifest(manifest, true)
    else
      showManifestStatus(manifest)
    end
  end)
end

local function runInstall()
  if installing then
    setStatus("Update already running...", "#ffd166")
    return
  end

  if lastManifest then
    installManifest(lastManifest, false)
    return
  end

  fetchManifest(function(manifest)
    if manifest then installManifest(manifest, false) end
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
    setPanelStatus("Version: " .. tostring(config.version or "none") .. "\nError OTUI", "#ff8a8a")
    setStatus("No se cargo Updater.otui\nRecarga el bot o actualiza de nuevo", "#ff8a8a")
  end
end

setPanelStatus("Version: " .. tostring(config.version or "none") .. "\nRevisando...")

schedule(100, function()
  if not installing then
    autoUpdateOnLogin()
  end
end)

UI.Separator()
