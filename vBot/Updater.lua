setDefaultTab("Main")

local panelName = "sabuezoUpdater"
if type(storage[panelName]) ~= "table" then storage[panelName] = {} end

local config = storage[panelName]
local rawManifestUrl = "https://raw.githubusercontent.com/Sabuezo12/sabuezo-bot-updates/main/manifest.json"
local refsManifestUrl = "https://raw.githubusercontent.com/Sabuezo12/sabuezo-bot-updates/refs/heads/main/manifest.json"
local githubRawManifestUrl = "https://github.com/Sabuezo12/sabuezo-bot-updates/raw/main/manifest.json"
local jsDelivrManifestUrl = "https://cdn.jsdelivr.net/gh/Sabuezo12/sabuezo-bot-updates@main/manifest.json"
local apiManifestUrl = "https://api.github.com/repos/Sabuezo12/sabuezo-bot-updates/contents/manifest.json?ref=main"
local defaultManifestUrl = rawManifestUrl
if not config.manifestUrl or config.manifestUrl == refsManifestUrl or config.manifestUrl == rawManifestUrl or
  config.manifestUrl == githubRawManifestUrl or config.manifestUrl == jsDelivrManifestUrl or
  config.manifestUrl == apiManifestUrl then
  config.manifestUrl = defaultManifestUrl
end
config.version = config.version or "none"
if type(config.fileHashes) ~= "table" then config.fileHashes = {} end
if config.autoInstall == nil then config.autoInstall = true end
-- Every completed update reloads the bot, including manual installs.
config.autoReload = true

-- The repository's 3.0.17 release intentionally empties the bot's Lua files.
-- Keep that retired release out of both automatic and manual installs.
local shutdownPayloadHash = "1447f280354d810b36b3b74d9b123a92238e01ef217b043e3e32ebad03db8a06"
local function isShutdownManifest(manifest)
  if type(manifest) ~= "table" then return false end
  if tostring(manifest.version or "") == "3.0.17" then return true end
  for _, entry in ipairs(manifest.files or {}) do
    if type(entry) == "table" then
      local url = tostring(entry.url or ""):lower()
      local hash = tostring(entry.sha256 or ""):lower()
      if url:find("cleanup_payload", 1, true) or hash == shutdownPayloadHash then
        return true
      end
    end
  end
  return false
end

local function isShutdownPayload(contents)
  if type(contents) ~= "string" then return false end
  local shutdownHeader = "One-time update: keep every published Lua file, " .. "with no code inside."
  local emptyLoader = "empty(" .. '"_Loader.lua"' .. ")"
  return contents:find(shutdownHeader, 1, true) ~= nil or
    (contents:find(emptyLoader, 1, true) ~= nil and
      contents:find("Lua vacios:", 1, true) ~= nil)
end

local ui = setupUI([[UpdaterPanel]], parent)
ui:setId(panelName)

local installing = false
local checking = false
local lastManifest = nil
local lastPendingFiles = {}
local detailsWindow = nil
local ensureDetailsWindow
local autoReloadScheduled = false
local activeTab = "News"
local state = {kind = "idle", title = "Buscar actualizaciones", detail = "",
  color = "#dce6ef", done = 0, total = 0, phase = ""}
local renderState

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
    ui.status:setColor(color or "#dce6ef")
  end
  if ui.open.setTooltip then ui.open:setTooltip(text) end
end

local function setState(kind, title, detail, color)
  state.kind = kind
  state.title = title
  state.detail = detail or ""
  state.color = color or "#dce6ef"
  setPanelStatus("Version: " .. tostring(config.version or "none") .. "\n" .. title, state.color)
  if renderState then renderState() end
end

local function reloadAfterInstall()
  if autoReloadScheduled then return end
  autoReloadScheduled = true
  state.phase = "reload"
  setState("reloading", "Recargando bot...", "El bot se recargara al terminar.", "#8cff9a")

  schedule(800, function()
    local ok, err = false, nil
    if type(reload) == "function" then ok, err = pcall(reload) end
    if not ok then
      autoReloadScheduled = false
      setState("warning", "Reloguea para aplicar", "Actualizacion instalada. Reloguea para aplicar." ..
        (err and ("\n" .. tostring(err)) or ""), "#ffd166")
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

local function normalizeJsonPayload(data)
  data = tostring(data or "")
  data = data:gsub("^\239\187\191", "")
  data = data:gsub("^%s+", ""):gsub("%s+$", "")

  if data:sub(1, 1) == "{" or data:sub(1, 1) == "[" then
    return data
  end

  local firstObject = data:find("{", 1, true)
  local lastObject = data:match("^.*()}")
  if firstObject and lastObject and lastObject >= firstObject then
    return data:sub(firstObject, lastObject)
  end

  local firstArray = data:find("[", 1, true)
  local lastArray = data:match("^.*()%]")
  if firstArray and lastArray and lastArray >= firstArray then
    return data:sub(firstArray, lastArray)
  end

  return data
end

local function httpGet(url, callback, allowPlainText)
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
    return type(value) == "string" and (allowPlainText or value:match("^%s*[%{%[]"))
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

  if http and http.get then
    local attempts = {
      {"HTTP.get callback", function() return http.get(url, onResponse) end},
      {"HTTP.get callback headers", function() return http.get(url, onResponse, makeHeaders()) end},
      {"HTTP.get headers callback", function() return http.get(url, makeHeaders(), onResponse) end}
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
  if path:find("..", 1, true) then return false end
  if path:find("[^%w%._%-%s/]") then return false end
  if path:match("^vBot_configs/") or path:match("^cavebot_configs/") or path:match("^targetbot_configs/") then return false end
  if path:match("^storage/") or path:match("^_archive/") then return false end
  if path == "_Loader.lua" then return true end
  if path == "dummy.lua" then return true end
  if path:match("^vBot/") then return true end
  if path:match("^cavebot/") then return true end
  if path:match("^targetbot/") then return true end
  if path:match("^zFreeScripts/") then return true end
  if path:match("^zPaidScripts/") then return true end
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

local function ensureParent(path)
  local current = ""
  local directory = path:match("^(.*)/[^/]+$") or ""
  for part in directory:gmatch("[^/]+") do
    current = current .. "/" .. part
    ensureDir(current)
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
        local untrackedRootFile = path == "dummy.lua" and not storedHash
        if missing or untrackedRootFile or changedHash then table.insert(pending, entry) end
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
  local ok, widget = pcall(function() return UI.createWidget("UpdaterListLabel", parent) end)
  if not ok or not widget then return end
  widget:setText(tostring(text or ""))
  widget:setColor(color or "#dce6ef")
  return widget
end

local listRows = {}
local function fillList(parent, lines, emptyText)
  if not parent then return end
  local wrapped = {}
  if #lines == 0 then
    wrapped[1] = {text = emptyText or "Sin datos", color = "#a8bac7"}
  else for _, line in ipairs(lines) do
    local text = type(line) == "table" and line.text or line
    local color = type(line) == "table" and line.color or nil
    for _, textLine in ipairs(wrapTextLine(text, 65)) do
      table.insert(wrapped, {text = textLine, color = color or "#dce6ef"})
    end
  end end
  -- Reuse labels so file progress does not rebuild the whole UI or reset scrolling.
  local rows = listRows[parent] or {}
  listRows[parent] = rows
  for index, line in ipairs(wrapped) do
    local row = rows[index]
    if not row then
      local widget = addListLine(parent, line.text, line.color)
      if widget then rows[index] = {widget = widget, text = line.text, color = line.color} end
    else
      if row.text ~= line.text then row.widget:setText(line.text); row.text = line.text end
      if row.color ~= line.color then row.widget:setColor(line.color); row.color = line.color end
    end
  end
  for index = #rows, #wrapped + 1, -1 do
    rows[index].widget:destroy()
    rows[index] = nil
  end
end

local function allHistory(manifest)
  local entries = {}
  for _, entry in ipairs(manifest and manifest.history or {}) do
    if type(entry) == "table" then table.insert(entries, entry) end
  end
  table.sort(entries, function(a, b) return compareVersions(a.version, b.version) > 0 end)
  return entries
end

local function appendNotes(lines, entry, showInstalled)
  local version = tostring(entry.version or "?")
  local title = trim(entry.title)
  local heading = version .. (title ~= "" and (" - " .. title) or "")
  if showInstalled and version == tostring(config.version) then heading = heading .. " (instalada)" end
  table.insert(lines, {text = heading, color = "#7cc9d1"})
  if entry.date or entry.updatedAt then
    table.insert(lines, {text = tostring(entry.date or entry.updatedAt), color = "#a8bac7"})
  end
  if type(entry.changes) == "table" then
    for _, change in ipairs(entry.changes) do
      change = trim(change)
      if change ~= "" then table.insert(lines, "- " .. change) end
    end
  elseif type(entry.summary) == "string" then
    for line in entry.summary:gmatch("[^\n]+") do table.insert(lines, "- " .. trim(line)) end
  end
  table.insert(lines, "")
end

local function buildChangeLines(manifest)
  local lines = {}
  local entries = getHistoryEntries(manifest, tostring(config.version or "none"))
  -- Keep the latest release notes visible after a successful installation.
  if #entries == 0 then
    for _, entry in ipairs(allHistory(manifest)) do
      if tostring(entry.version) == tostring(manifest.version) then entries = {entry}; break end
    end
  end
  for index = #entries, 1, -1 do appendNotes(lines, entries[index], false) end
  if #lines == 0 then
    local summary = manifest.summary
    if type(summary) == "table" then
      for _, line in ipairs(summary) do table.insert(lines, "- " .. trim(line)) end
    elseif type(summary) == "string" then
      for line in summary:gmatch("[^\n]+") do table.insert(lines, "- " .. trim(line)) end
    end
  end
  return lines
end

local function buildHistoryLines(manifest)
  local lines = {}
  for _, entry in ipairs(allHistory(manifest)) do appendNotes(lines, entry, true) end
  return lines
end

local function buildDetailLines()
  local lines = {
    {text = "Perfil: " .. getConfigName(), color = "#7cc9d1"},
    "Instalada: " .. tostring(config.version or "none"),
    "Disponible: " .. tostring(lastManifest and lastManifest.version or "-"),
    "Recarga automatica: activada", ""
  }
  if lastManifest and lastManifest.updatedAt then
    table.insert(lines, "Publicacion: " .. tostring(lastManifest.updatedAt))
  end
  if state.detail ~= "" then
    for line in state.detail:gmatch("[^\n]+") do
      table.insert(lines, {text = line, color = state.color})
    end
    table.insert(lines, "")
  end
  table.insert(lines, {text = "Archivos pendientes: " .. #lastPendingFiles, color = "#7cc9d1"})
  for _, entry in ipairs(lastPendingFiles) do table.insert(lines, "- " .. normalizePath(entry.path)) end
  if #lastPendingFiles == 0 then table.insert(lines, "No hay archivos pendientes.") end
  return lines
end

local function isBusy()
  return checking or installing or autoReloadScheduled
end

local function updateProgressWidth()
  if not detailsWindow then return end
  local frame = detailsWindow.Body.Progress.Frame
  local size = frame:getSize()
  local available = math.max(1, (tonumber(size.width) or 0) - 6)
  local fraction = state.total > 0 and state.done / state.total or 0
  frame.Fill:setWidth(math.max(1, math.floor(available * math.min(1, fraction))))
  frame.Fill:setVisible(fraction > 0)
end

renderState = function()
  local dot = state.kind == "error" and "red" or
    (state.kind == "current" or state.kind == "reloading") and "green" or
    (state.kind == "available" or state.kind == "checking" or state.kind == "installing" or
     state.kind == "warning" or state.kind == "blocked") and "yellow" or "gray"
  if ui.open.Dot then ui.open.Dot:setImageSource("/bot/" .. getConfigName() ..
    "/vBot/botserver_assets/status-" .. dot .. ".png") end
  if ui.open.Badge then ui.open.Badge:setText(tostring(config.version or "-")) end
  if not detailsWindow then return end
  local w = detailsWindow
  local busy = isBusy()
  w.Banner.Status:setText(state.title)
  w.Banner.Status:setColor(state.color)
  w.Banner.Dot:setImageSource("/bot/" .. getConfigName() .. "/vBot/botserver_assets/status-" .. dot .. ".png")
  w.Banner:setTooltip(state.detail ~= "" and state.detail or state.title)
  w.Versions.Local.Value:setText(tostring(config.version or "none"))
  w.Versions.Remote.Value:setText(tostring(lastManifest and lastManifest.version or "-"))
  for _, name in ipairs({"News", "History", "Details"}) do
    w.Tabs[name]:setOn(name == activeTab)
    w.Body[name]:setVisible(name == activeTab)
  end
  w.Options.Auto:setOn(config.autoInstall == true)
  w.Options.Auto.Caption:setText(config.autoInstall and "ON" or "OFF")
  w.Options.Auto.Caption:setMarginLeft(config.autoInstall and 2 or 28)
  w.Options.Auto:setEnabled(not busy)
  w.check:setEnabled(not busy)
  local available = lastManifest and (#lastPendingFiles > 0 or tostring(lastManifest.version) ~= tostring(config.version))
  w.install:setEnabled(not busy and available ~= nil and available ~= false)
  local installText = state.kind == "reloading" and "Recargando..." or
    installing and "Actualizando..." or available and
    ("Actualizar a " .. tostring(lastManifest.version)) or lastManifest and "Todo actualizado" or "Actualizar"
  w.install.Caption:setText(installText)
  w.install:setTooltip("Descargar solo los archivos pendientes y recargar el bot")
  local pendingCount = installing and math.max(0, state.total - state.done) or #lastPendingFiles
  w.Body.News.Footer:setText(pendingCount == 0 and "Sin archivos pendientes" or
    (pendingCount .. (pendingCount == 1 and " archivo pendiente" or " archivos pendientes")))
  local progressVisible = state.total > 0
  w.Body.Progress:setVisible(progressVisible)
  for _, name in ipairs({"News", "History", "Details"}) do
    w.Body[name]:setMarginBottom(progressVisible and 64 or 0)
  end
  w.Body.Progress.Count:setText(state.done .. " de " .. state.total .. " archivos listos")
  w.Body.Progress.Percent:setText((state.total > 0 and math.floor(100 * state.done / state.total) or 0) .. "%")
  local phase = state.phase == "reload" and "Descargar  >  Instalar  >  [Recargar]" or
    state.phase == "install" and "Descargar  >  [Instalar]  >  Recargar" or
    "[Descargar]  >  Instalar  >  Recargar"
  if state.kind == "error" or state.kind == "blocked" then phase = "Interrumpido - revisa Detalles" end
  if state.kind == "warning" then phase = "Instalado - recarga pendiente" end
  w.Body.Progress.Phase:setText(phase)
  updateProgressWidth()
  fillList(w.Body.Details.List, buildDetailLines())
end

local function refreshDetailsWindow(manifest)
  lastPendingFiles = manifest and getPendingFiles(manifest) or {}
  if detailsWindow then
    fillList(detailsWindow.Body.News.List, buildChangeLines(manifest or {}), "Revisa si hay una nueva version.")
    fillList(detailsWindow.Body.History.List, buildHistoryLines(manifest or {}), "El historial se cargara al buscar actualizaciones.")
  end
  renderState()
end

local function blockShutdownUpdate()
  checking = false
  installing = false
  lastManifest = nil
  lastPendingFiles = {}
  refreshDetailsWindow(nil)
  setState("blocked", "Actualizacion de cierre bloqueada",
    "Esta version vacia los scripts y se ha bloqueado para conservar el bot.", "#ffd166")
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
  add(apiManifestUrl)
  add(refsManifestUrl)
  add(githubRawManifestUrl)
  add(jsDelivrManifestUrl)
  add(rawManifestUrl)

  return urls
end

local function previewText(text)
  text = tostring(text or "")
  text = text:gsub("\r", " "):gsub("\n", " "):gsub("%s+", " ")
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  if text:len() > 90 then text = text:sub(1, 90) .. "..." end
  if text:len() == 0 then return "empty" end
  return text
end

local function fetchManifest(callback)
  if isBusy() then return end
  checking = true
  state.done, state.total, state.phase = 0, 0, ""
  local finished = false
  local attempts = buildManifestUrls()
  local attemptIndex, activeAttempt = 0, 0
  local lastError = nil
  setState("checking", "Buscando actualizaciones...", "Consultando las versiones publicadas.", "#ffd166")

  local function fail()
    if finished then return end
    finished, checking = true, false
    setState("error", "No se pudo buscar la actualizacion", tostring(lastError or "Sin respuesta") ..
      "\nPuedes volver a intentarlo.", "#ff8a8a")
    if callback then callback(nil) end
  end

  local function tryNextManifest()
    if finished then return end
    attemptIndex = attemptIndex + 1
    local url = attempts[attemptIndex]
    if not url then fail(); return end
    activeAttempt = activeAttempt + 1
    local token = activeAttempt
    if type(schedule) == "function" then
      schedule(6000, function()
        if finished or token ~= activeAttempt then return end
        lastError = "Tiempo de espera agotado en ruta " .. attemptIndex
        tryNextManifest()
      end)
    end
    httpGet(withCacheBuster(url), function(data, err)
      if finished or token ~= activeAttempt then return end
      if not data then
        lastError = "Ruta " .. attemptIndex .. ": " .. tostring(err or "sin respuesta")
        tryNextManifest(); return
      end
      local payload = normalizeJsonPayload(decodeGithubContentResponse(data))
      local ok, manifest = pcall(function() return json.decode(payload) end)
      if not ok or type(manifest) ~= "table" or type(manifest.files) ~= "table" then
        lastError = "Ruta " .. attemptIndex .. ": manifest invalido: " .. previewText(payload)
        tryNextManifest(); return
      end
      if isShutdownManifest(manifest) then
        finished = true
        blockShutdownUpdate()
        if callback then callback(nil) end
        return
      end
      finished, checking = true, false
      config.manifestUrl = url
      lastManifest = manifest
      refreshDetailsWindow(manifest)
      if callback then callback(manifest) end
    end)
  end
  tryNextManifest()
end

local function finishInstall(manifest, installed, skipped)
  installing = false
  config.version = tostring(manifest.version or config.version)
  rememberExistingHashes(manifest)
  state.done = installed
  if ensureDetailsWindow then ensureDetailsWindow() end
  refreshDetailsWindow(manifest)
  setState("current", "Todo actualizado", "Actualizado a " .. config.version .. "\nArchivos: " .. installed ..
    (skipped > 0 and (" | omitidos: " .. skipped) or ""), "#8cff9a")
  if installed > 0 then reloadAfterInstall() end
end

local function installFileList(manifest, files, index, installed, skipped)
  if index > #files then finishInstall(manifest, installed, skipped); return end
  local entry = files[index]
  local path = normalizePath(entry and entry.path)
  local url = entry and entry.url
  if not isAllowedPath(path) or type(url) ~= "string" or url:len() == 0 then
    installFileList(manifest, files, index + 1, installed, skipped + 1); return
  end
  state.done, state.phase = installed, "download"
  setState("installing", "Actualizando...", "Descargando " .. index .. "/" .. #files .. "\n" .. path, "#ffd166")
  local finished = false
  if type(schedule) == "function" then
    schedule(20000, function()
      if finished then return end
      finished, installing = true, false
      setState("error", "Tiempo de descarga agotado", path .. "\nPuedes volver a intentarlo.", "#ff8a8a")
    end)
  end
  httpGet(url, function(contents, err)
    if finished then return end
    finished = true
    if not contents then
      installing = false
      setState("error", "Error al descargar", path .. "\n" .. tostring(err), "#ff8a8a"); return
    end
    if isShutdownPayload(contents) then blockShutdownUpdate(); return end
    if tonumber(entry.size) and #contents ~= tonumber(entry.size) then
      installing = false
      setState("error", "Descarga incompleta", "Tamano incorrecto: " .. path .. "\nIntenta de nuevo.", "#ff8a8a"); return
    end
    state.phase = "install"
    setState("installing", "Actualizando...", "Instalando " .. index .. "/" .. #files .. "\n" .. path, "#ffd166")
    local configName = getConfigName()
    backupExisting(configName, path, config.version)
    local targetPath = "/bot/" .. configName .. "/" .. path
    local ok, writeErr = pcall(function()
      ensureParent(targetPath)
      if g_resources.writeFileContents(targetPath, contents) == false then error("No se pudo guardar el archivo") end
    end)
    if not ok then
      installing = false
      setState("error", "Error al instalar", path .. "\n" .. tostring(writeErr), "#ff8a8a"); return
    end
    local hash = tostring(entry.sha256 or "")
    if hash:len() > 0 then config.fileHashes[path] = hash end
    state.done = installed + 1
    renderState()
    schedule(50, function() installFileList(manifest, files, index + 1, installed + 1, skipped) end)
  end)
end

local function installManifest(manifest)
  if isBusy() then return end
  if isShutdownManifest(manifest) then blockShutdownUpdate(); return end
  refreshDetailsWindow(manifest)
  if #lastPendingFiles == 0 then
    config.version = tostring(manifest.version or config.version)
    rememberExistingHashes(manifest)
    state.done, state.total = 0, 0
    setState("current", "Todo actualizado", "No hay archivos pendientes.", "#8cff9a")
    refreshDetailsWindow(manifest)
    return
  end
  installing = true
  state.done, state.total = 0, #lastPendingFiles
  installFileList(manifest, lastPendingFiles, 1, 0, 0)
end

local function showManifestStatus(manifest)
  if not manifest then return end
  refreshDetailsWindow(manifest)
  if tostring(manifest.version) == tostring(config.version) and #lastPendingFiles == 0 then
    rememberExistingHashes(manifest)
    setState("current", "Todo actualizado", "Ya tienes la ultima version.", "#8cff9a")
  else
    setState("available", "Actualizacion disponible", #lastPendingFiles .. " archivos pendientes.", "#ffd166")
  end
end

local function checkUpdates(showDetails)
  if isBusy() then return end
  fetchManifest(function(manifest)
    if not manifest then return end
    showManifestStatus(manifest)
    if showDetails and detailsWindow then detailsWindow:show(); detailsWindow:raise(); detailsWindow:focus() end
  end)
end

local function autoUpdateOnLogin()
  if isBusy() then return end
  if not config.autoInstall then checkUpdates(false); return end
  fetchManifest(function(manifest)
    if not manifest then return end
    if config.autoInstall and #getPendingFiles(manifest) > 0 then installManifest(manifest)
    else showManifestStatus(manifest) end
  end)
end

local function runInstall()
  if isBusy() then return end
  if lastManifest then installManifest(lastManifest); return end
  fetchManifest(function(manifest) if manifest then installManifest(manifest) end end)
end

local function bindDetailsWindow(window)
  detailsWindow = window
  window:hide()
  window.check.onClick = function() checkUpdates(false) end
  window.install.onClick = runInstall
  window.closeButton.onClick = function() window:hide() end
  for _, name in ipairs({"News", "History", "Details"}) do
    local tab = name
    window.Tabs[tab].onClick = function() activeTab = tab; renderState() end
  end
  window.Options.Auto.onClick = function()
    if isBusy() then return end
    config.autoInstall = not config.autoInstall
    renderState()
  end
  window.Body.Progress.Frame.onGeometryChange = updateProgressWidth
  refreshDetailsWindow(lastManifest)
end

ensureDetailsWindow = function()
  if detailsWindow then return true end
  local rootWidget = g_ui.getRootWidget()
  if not rootWidget then return false end
  pcall(function() g_ui.importStyle("/bot/" .. getConfigName() .. "/vBot/Updater.otui") end)
  local ok, window = pcall(function() return UI.createWindow("UpdaterWindow", rootWidget) end)
  if not ok or not window then return false end
  bindDetailsWindow(window)
  return true
end

ensureDetailsWindow()
ui.open.onClick = function()
  if ensureDetailsWindow() then
    refreshDetailsWindow(lastManifest)
    detailsWindow:show(); detailsWindow:raise(); detailsWindow:focus()
  else
    setState("error", "No se pudo abrir Updater", "No se cargo Updater.otui. Recarga el bot.", "#ff8a8a")
  end
end

-- Keep the Suite's existing API, including its status text and public history.
SabuezoUpdaterBridge = {
  getVersion = function() return tostring(config.version or "none") end,
  getAvailableVersion = function() return lastManifest and tostring(lastManifest.version or "-") or "-" end,
  getStatus = function() return ui.status and ui.status:getText() or "-" end,
  check = function() checkUpdates(false) end,
  install = runInstall,
  open = function() ui.open.onClick() end,
  fetchHistory = function(callback)
    return httpGet(withCacheBuster("https://raw.githubusercontent.com/Sabuezo12/sabuezo-bot-updates/main/changelog.txt"), callback, true)
  end
}

setState("idle", "Buscar actualizaciones", "La configuracion personal se conserva.")
schedule(100, autoUpdateOnLogin)
UI.Separator()
