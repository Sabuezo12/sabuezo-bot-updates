-- Reload cache: strings and numbers only. Native styles are still imported.
-- The transform sources are compared without hashing them in a Lua byte loop.
HelperAppearanceStyleCache = function(options)
  local version = 1
  local maxBytes, maxEntries = options.maxBytes or 2097152, options.maxEntries or 128
  local initialized, cache = false, nil
  local stats = {hits = 0, misses = 0}
  local result = {stats = stats}
  local function initialize()
    if initialized then return cache end
    initialized = true
    if type(options.host) ~= "table" then return end
    local ok, appearance, skin = pcall(options.revisions)
    if not ok or type(appearance) ~= "string" or type(skin) ~= "string" or
        appearance == "" or skin == "" then return end
    local base = #appearance + #skin + #options.scope
    if base > maxBytes then return end
    local old = options.host._rinoAppearanceTextCache
    local reusable = type(old) == "table" and old.version == version and old.scope == options.scope and
        old.appearance == appearance and old.skin == skin and type(old.entries) == "table" and
        type(old.bytes) == "number" and old.bytes >= base and old.bytes <= maxBytes and
        type(old.count) == "number" and old.count >= 0 and old.count <= maxEntries and
        type(old.clock) == "number" and old.clock >= 0 and old.clock < math.huge
    if reusable then
      local bytes, count = base, 0
      for path, entry in pairs(old.entries) do
        if type(path) ~= "string" or type(entry) ~= "table" or type(entry.source) ~= "string" or
            type(entry.key) ~= "string" or type(entry.text) ~= "string" or
            type(entry.used) ~= "number" or entry.used < 0 or entry.used > old.clock or
            entry.used ~= entry.used or entry.bytes ~= #path + #entry.key + #entry.source + #entry.text then
          reusable = false; break
        end
        bytes, count = bytes + entry.bytes, count + 1
      end
      reusable = reusable and bytes == old.bytes and count == old.count
    end
    if reusable then
      cache = old
    else
      cache = {version = version, scope = options.scope, appearance = appearance, skin = skin,
        entries = {}, bytes = base, count = 0, clock = 0}
      options.host._rinoAppearanceTextCache = cache
    end
    return cache
  end
  local function remove(c, path)
    local entry = c.entries[path]
    if entry then
      c.bytes, c.count = c.bytes - entry.bytes, c.count - 1
      c.entries[path] = nil
    end
  end
  function result.transform(path, source, key, transform)
    local c = initialize()
    local entry = c and c.entries[path]
    if entry and entry.source == source and entry.key == key then
      stats.hits = stats.hits + 1
      c.clock = c.clock + 1; entry.used = c.clock
      return entry.text
    end
    stats.misses = stats.misses + 1
    local text = transform(source, path)
    if not c or type(text) ~= "string" then return text end
    remove(c, path)
    local size = #path + #key + #source + #text
    local base = #c.appearance + #c.skin + #c.scope
    if size + base > maxBytes or maxEntries < 1 then return text end
    while c.count >= maxEntries or c.bytes + size > maxBytes do
      local oldest, stamp
      for candidate, value in pairs(c.entries) do
        if not stamp or value.used < stamp then oldest, stamp = candidate, value.used end
      end
      if not oldest then return text end
      remove(c, oldest)
    end
    c.clock = c.clock + 1
    c.entries[path] = {source = source, key = key, text = text, bytes = size, used = c.clock}
    c.bytes, c.count = c.bytes + size, c.count + 1
    return text
  end
  return result
end
return HelperAppearanceStyleCache
