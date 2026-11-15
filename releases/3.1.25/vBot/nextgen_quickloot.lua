-- Next Gen normally saves the filter only from its native logout callback.
-- Save edits while the character is still loaded, using the same native file.
local type, pairs, pcall, table = type, pairs, pcall, table

local function itemListSignature(items)
  if type(items) ~= "table" then return nil end
  local count = 0
  for index, id in pairs(items) do
    if type(index) ~= "number" or index < 1 or index > #items or index % 1 ~= 0 or
      type(id) ~= "number" or id <= 0 or id % 1 ~= 0 then return nil end
    count = count + 1
  end
  if count ~= #items then return nil end
  return table.concat(items, ",")
end

local function signature(data)
  if type(data) ~= "table" then return nil end
  local mode = data.listType or "blacklist"
  if mode ~= "blacklist" and mode ~= "whitelist" then return nil end
  local skipped = itemListSignature(data.blacklistTypes or {})
  local accepted = itemListSignature(data.whitelistTypes or {})
  if not skipped or not accepted then return nil end
  return mode .. ":" .. skipped .. ":" .. accepted, skipped == "" and accepted == ""
end

local function playerId(value)
  if type(value) == "number" and value > 0 and value % 1 == 0 then return value end
end

return function(host, dependencies)
  local loot = dependencies.quickloot
  local loadedPlayer = dependencies.loadedPlayer
  local game = dependencies.game
  local resources = dependencies.resources
  local json = dependencies.json
  if type(host) ~= "table" or type(loot) ~= "table" or type(loadedPlayer) ~= "table" or
    type(loadedPlayer.getId) ~= "function" or type(game) ~= "table" or
    type(game.isOnline) ~= "function" or type(game.getLocalPlayer) ~= "function" or
    type(resources) ~= "table" or type(resources.fileExists) ~= "function" or
    type(resources.readFileContents) ~= "function" or type(json) ~= "table" or
    type(json.decode) ~= "function" or type(loot.loadData) ~= "function" or
    type(loot.saveData) ~= "function" or type(loot.updateLootItems) ~= "function" or
    type(loot.start) ~= "function" then return nil end

  local installed = host._helperNextGenQuickLoot
  if installed and installed.loot == loot and installed.save == loot.saveData then return installed end

  local nativeLoad, nativeSave, nativeUpdate = loot.loadData, loot.saveData, loot.updateLootItems
  local owner, observed, persisted, dirty
  local initial = true

  local function loadedId()
    local ok, id = pcall(loadedPlayer.getId, loadedPlayer)
    if ok then return playerId(id) end
  end

  local function currentId()
    local ok, id = pcall(function()
      if not game.isOnline() then return nil end
      local player = game.getLocalPlayer()
      return player and player:getId()
    end)
    if ok then return playerId(id) end
  end

  local function readDisk(id)
    local path = "/characterdata/" .. id .. "/lootBlackWhitelist.json"
    local ok, exists = pcall(resources.fileExists, path)
    if not ok then return nil, "unreadable" end
    if not exists then return nil, "missing" end
    local read, data = pcall(function() return json.decode(resources.readFileContents(path)) end)
    if not read then return nil, "unreadable" end
    local saved = signature(data)
    return saved, saved and "saved" or "unreadable"
  end

  local function remember(id, current, saved)
    owner, observed, persisted, dirty = id, current, saved, false
  end

  function loot.loadData(...)
    -- A login can dispatch the Quick Loot callback before LoadedPlayer is updated.
    remember(nil, nil, nil)
    initial = false
    local id = currentId()
    if not id or loadedId() ~= id then return end
    local saved, status = readDisk(id)
    if status == "unreadable" then return end
    local ok, result = pcall(nativeLoad, ...)
    if not ok then return end
    local current = signature(loot.lootData)
    if current and (current == saved or status == "missing" and current == "blacklist::") then
      remember(id, current, saved)
    end
    return result
  end

  local function persist(id, ...)
    if not id or id ~= owner or loadedId() ~= id then return end
    local current = signature(loot.lootData)
    if not current or current == persisted then return end
    if not dirty and current == observed and persisted == nil then return end
    local saved, status = readDisk(id)
    -- If another instance has just updated this character, keep its version.
    if status == "unreadable" or saved ~= persisted then return end
    local ok, result = pcall(nativeSave, ...)
    if ok and readDisk(id) == current then
      observed, persisted, dirty = current, current, false
    end
    if ok then return result end
  end

  function loot.saveData(...)
    -- Native finish can run after g_game drops its local player.
    local onlineId = currentId()
    if onlineId and onlineId ~= owner then return end
    return persist(owner, ...)
  end

  function loot.updateLootItems(...)
    local result = nativeUpdate(...)
    local id = currentId()
    if id and id == owner and loadedId() == id then
      local current = signature(loot.lootData)
      if current and current ~= observed then
        observed, dirty = current, true
        persist(id)
      end
    end
    return result
  end

  local function tick()
    local id = currentId()
    if not id or loadedId() ~= id then return end
    if id == owner then
      if dirty then persist(id) end
      return
    end
    local saved, status = readDisk(id)
    if status == "unreadable" then return end
    if initial then
      initial = false
      local current, empty = signature(loot.lootData)
      -- This is the already-running character. Keep any edits in memory unless
      -- the client failed to load an existing list and still shows a default.
      if current and (current == saved or not empty or status == "missing") then
        remember(id, current, saved)
        return
      end
    end
    -- Use native start for the late load, selected radio button, and server sync.
    pcall(loot.start)
  end

  local bridge = {loot = loot, save = loot.saveData, tick = tick}
  host._helperNextGenQuickLoot = bridge
  tick()
  return bridge
end
