-- Sabuezo public installer. Downloads and validates all files before changing the bot.
local httpDownloadSerial = 0
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


local origin = "https://raw.githubusercontent.com/Sabuezo12/sabuezo-bot-updates/"
local name = modules.game_bot.contentsPanel.config:getCurrentOption().text
assert(type(name) == "string" and name ~= "" and not name:find("[/\\]") and
  not name:find("..", 1, true), "No se pudo identificar la carpeta activa del bot")
local root = "/bot/" .. name
local statusPanel
if type(setupUI) == "function" then
  setDefaultTab("Main")
  statusPanel = setupUI([[
Label
  height: 40
  text-wrap: true
  text-align: center
  color: #ffd166
  text: Preparando Sabuezo...
]])
end
local stopped = false
local function status(text)
  if statusPanel then statusPanel:setText(text) end
end
local function stop(text)
  stopped = true
  status("Instalacion detenida:\n" .. text)
  if type(warn) == "function" then warn("Sabuezo: " .. text) end
end
local function allowed(path)
  if type(path) ~= "string" or path == "" or path:sub(1, 1) == "/" or
    path:find("..", 1, true) or path:find("[^%w_.%-%s/]") then return false end
  if path == "_Loader.lua" or path == "dummy.lua" then return true end
  return path:match("^vBot/") or path:match("^cavebot/") or
    path:match("^targetbot/") or path:match("^zFreeScripts/") or path:match("^zPaidScripts/")
end
local function directory(path)
  local current = ""
  for part in path:gmatch("[^/]+") do
    current = current .. "/" .. part
    if not g_resources.directoryExists(current) then
      local result = g_resources.makeDir(current)
      assert(result ~= false and g_resources.directoryExists(current), "No se pudo crear una carpeta")
    end
  end
end
local function write(path, contents)
  directory(path:match("^(.*)/[^/]+$"))
  assert(g_resources.writeFileContents(path, contents) ~= false, "No se pudo guardar un archivo")
end
local function shutdown(contents)
  local header = "One-time update: keep every published Lua file, " .. "with no code inside."
  return contents:find(header, 1, true) ~= nil
end
local originals = {}
local changed = {}
local function rollback()
  for index = #changed, 1, -1 do
    local path = changed[index]
    if originals[path] ~= nil then
      pcall(g_resources.writeFileContents, path, originals[path])
    end
  end
end
local function install(manifest)
  if type(manifest) ~= "table" or type(manifest.version) ~= "string" or
    not manifest.version:match("^[%w_.-]+$") or manifest.version == "3.0.17" or
    type(manifest.files) ~= "table" or #manifest.files == 0 or #manifest.files > 1000 then
    stop("Manifest invalido o version de cierre bloqueada")
    return
  end
  local files, seen, total = {}, {}, 0
  for _, entry in ipairs(manifest.files) do
    if not allowed(entry.path) or seen[entry.path:lower()] or type(entry.url) ~= "string" or
      entry.url:sub(1, #origin) ~= origin or entry.url:find("cleanup_payload", 1, true) or
      type(entry.size) ~= "number" or entry.size < 0 or entry.size > 5 * 1024 * 1024 or
      type(entry.sha256) ~= "string" or #entry.sha256 ~= 64 or entry.sha256:find("[^a-f0-9]") then
      stop("Archivo invalido en el manifest")
      return
    end
    seen[entry.path:lower()] = true
    total = total + entry.size
    files[#files + 1] = entry
  end
  if total > 30 * 1024 * 1024 or not seen["_loader.lua"] or not seen["vbot/updater.lua"] then
    stop("Paquete incompleto o demasiado grande")
    return
  end
  table.sort(files, function(a, b)
    if a.path == "_Loader.lua" then return false end
    if b.path == "_Loader.lua" then return true end
    return a.path < b.path
  end)
  local payloads = {}
  local function commit(index)
    if stopped then return end
    local backup = root .. "/_updates/bootstrap_" .. manifest.version
    local last = math.min(index + 3, #files)
    for current = index, last do
      local entry = files[current]
      local target = root .. "/" .. entry.path
      local ok = pcall(function()
        if g_resources.fileExists(target) then
          originals[target] = g_resources.readFileContents(target)
          write(backup .. "/" .. entry.path, originals[target])
        end
        changed[#changed + 1] = target
        write(target, payloads[current])
      end)
      if not ok then
        rollback()
        stop("Error al guardar. Se restauraron los archivos anteriores; respaldo en _updates.")
        return
      end
    end
    if last == #files then
      storage.sabuezoUpdater = storage.sabuezoUpdater or {}
      storage.sabuezoUpdater.version = manifest.version
      storage.sabuezoUpdater.fileHashes = {}
      for _, entry in ipairs(files) do
        storage.sabuezoUpdater.fileHashes[entry.path] = entry.sha256
      end
      stopped = true
      status("Sabuezo " .. manifest.version .. " instalado.\nRecarga el bot para aplicar los cambios.")
      if type(warn) == "function" then warn("Sabuezo instalado. Recarga el bot.") end
      return
    end
    status("Aplicando Sabuezo " .. last .. "/" .. #files)
    schedule(50, function() commit(last + 1) end)
  end
  local function download(index)
    if stopped then return end
    if index > #files then commit(1); return end
    local entry = files[index]
    status("Descargando Sabuezo " .. index .. "/" .. #files)
    local replied = false
    schedule(20000, function()
      if stopped or replied then return end
      replied = true
      stop("Tiempo de espera agotado. El bot anterior sigue intacto.")
    end)
    httpGet(entry.url, function(contents, err)
      if stopped or replied then return end
      replied = true
      if not contents or #contents ~= entry.size or shutdown(contents) then
        stop("Descarga invalida o incompleta. El bot anterior sigue intacto.")
        return
      end
      payloads[index] = contents
      schedule(30, function() download(index + 1) end)
    end, true)
  end
  download(1)
end
local manifestReplied = false
schedule(20000, function()
  if stopped or manifestReplied then return end
  manifestReplied = true
  stop("GitHub no respondio. Intenta de nuevo.")
end)
local stamp = tostring(os and os.time and os.time() or now or 0)
httpGet(origin .. "main/manifest.json?sabuezoInstall=" .. stamp, function(contents, err)
  if stopped or manifestReplied then return end
  manifestReplied = true
  if not contents then stop("No se pudo consultar GitHub"); return end
  local ok, manifest = pcall(json.decode, contents)
  if not ok then stop("GitHub devolvio un manifest invalido"); return end
  install(manifest)
end)
