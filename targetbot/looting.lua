TargetBot.Looting = {}
TargetBot.Looting.list = {} -- list of containers to loot

local ui
local items = {}
local containers = {}
local itemsById = {}
local containersById = {}
local dontSave = false
local globalLootStorageKey = "targetBotGlobalLoot"

local cloneLootList = function(list)
  local result = {}
  if type(list) ~= "table" then return result end
  for _, entry in ipairs(list) do
    if type(entry) == "table" then
      local copy = {}
      for key, value in pairs(entry) do
        copy[key] = value
      end
      table.insert(result, copy)
    end
  end
  return result
end

local hasLootEntries = function(list)
  return type(list) == "table" and #list > 0
end

local getCurrentBotConfigName = function()
  local ok, name = pcall(function()
    return modules.game_bot.contentsPanel.config:getCurrentOption().text
  end)
  return ok and name or nil
end

local loadPreferredGlobalLoot = function()
  if not g_resources or not g_resources.fileExists or not g_resources.readFileContents or not json then
    return nil
  end

  local botConfigName = getCurrentBotConfigName()
  if not botConfigName then return nil end

  for _, profileName in ipairs({"Mounstros", "Monsters", "monsters"}) do
    local path = "/bot/" .. botConfigName .. "/targetbot_configs/" .. profileName .. ".json"
    local existsOk, exists = pcall(function() return g_resources.fileExists(path) end)
    if existsOk and exists then
      local readOk, contents = pcall(function() return g_resources.readFileContents(path) end)
      if readOk and contents then
        local decodeOk, profile = pcall(function() return json.decode(contents) end)
        local looting = decodeOk and type(profile) == "table" and profile.looting or nil
        if type(looting) == "table" and (hasLootEntries(looting.items) or hasLootEntries(looting.containers)) then
          return {
            items = cloneLootList(looting.items),
            containers = cloneLootList(looting.containers)
          }
        end
      end
    end
  end

  return nil
end

local ensureGlobalLootStorage = function(profileLooting)
  storage.extras = storage.extras or {}

  local globalLoot = storage.extras[globalLootStorageKey]
  if type(globalLoot) ~= "table" or globalLoot.version ~= 1 then
    local seed = loadPreferredGlobalLoot() or profileLooting or {}
    globalLoot = {
      version = 1,
      items = cloneLootList(seed.items),
      containers = cloneLootList(seed.containers)
    }
    storage.extras[globalLootStorageKey] = globalLoot
  end

  if type(globalLoot.items) ~= "table" then globalLoot.items = {} end
  if type(globalLoot.containers) ~= "table" then globalLoot.containers = {} end

  return globalLoot
end

local saveGlobalLootFromUi = function()
  local globalLoot = ensureGlobalLootStorage({})
  globalLoot.items = cloneLootList(ui.items:getItems())
  globalLoot.containers = cloneLootList(ui.containers:getItems())
  return globalLoot
end

local normalizeIgnoreCreatureName = function(text)
  local name = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
  return name:gsub("%s+", " ")
end

local parseIgnoreCreatureNames = function(text)
  local list = {}
  local seen = {}
  for rawName in tostring(text or ""):gmatch("[^,]+") do
    local name = normalizeIgnoreCreatureName(rawName)
    local key = name:lower()
    if name:len() > 0 and not seen[key] then
      seen[key] = true
      table.insert(list, name)
    end
  end
  return list
end

local ensureIgnoreCreaturesStorage = function()
  storage.extras = storage.extras or {}
  if storage.extras.ignoreCreatures == nil then
    storage.extras.ignoreCreatures = "deer,rabbit"
  end
end

local getIgnoreCreatures = function()
  ensureIgnoreCreaturesStorage()
  return parseIgnoreCreatureNames(storage.extras.ignoreCreatures)
end

local saveIgnoreCreatures = function()
  if not ui or not ui.ignoreCreaturesPanel then return end
  ensureIgnoreCreaturesStorage()
  local list = {}
  local seen = {}
  for _, child in ipairs(ui.ignoreCreaturesPanel.ignoreCreaturesList:getChildren()) do
    local name = normalizeIgnoreCreatureName(child.value or child:getText())
    local key = name:lower()
    if name:len() > 0 and not seen[key] then
      seen[key] = true
      table.insert(list, name)
    end
  end
  storage.extras.ignoreCreatures = table.concat(list, ",")
  if TargetBot.Creature and TargetBot.Creature.resetConfigsCache then
    TargetBot.Creature.resetConfigsCache()
  end
end

local ignoreCreatureNameExists = function(name, exceptEntry)
  if not ui or not ui.ignoreCreaturesPanel then return false end
  local key = normalizeIgnoreCreatureName(name):lower()
  for _, child in ipairs(ui.ignoreCreaturesPanel.ignoreCreaturesList:getChildren()) do
    if child ~= exceptEntry and normalizeIgnoreCreatureName(child.value or child:getText()):lower() == key then
      return true
    end
  end
  return false
end

local addIgnoreCreatureEntry = function(name, focus)
  name = normalizeIgnoreCreatureName(name)
  if name:len() < 1 or ignoreCreatureNameExists(name) then return nil end

  local widget = UI.createWidget("TargetBotEntry", ui.ignoreCreaturesPanel.ignoreCreaturesList)
  widget:setText(name)
  widget.value = name
  widget.onDoubleClick = function(entry)
    schedule(20, function()
      TargetBot.Looting.editIgnoreCreature(entry)
    end)
  end

  if focus then
    widget:focus()
    ui.ignoreCreaturesPanel.ignoreCreaturesList:ensureChildVisible(widget)
  end
  return widget
end

local refreshIgnoreCreatures = function()
  ui.ignoreCreaturesPanel.ignoreCreaturesList:destroyChildren()
  for _, name in ipairs(getIgnoreCreatures()) do
    addIgnoreCreatureEntry(name)
  end
end

TargetBot.Looting.editIgnoreCreature = function(entry)
  local currentName = entry and entry.value or ""
  UI.EditorWindow(currentName, {
    title = entry and "Edit ignored creature" or "Add ignored creature",
    description = "Enter one monster name to ignore.",
    multiline = false
  }, function(newText)
    local names = parseIgnoreCreatureNames(newText)
    if #names < 1 then return end
    if entry then
      local name = names[1]
      if ignoreCreatureNameExists(name, entry) then return end
      entry:setText(name)
      entry.value = name
      for i = 2, #names do
        addIgnoreCreatureEntry(names[i])
      end
    else
      local focusFirst = true
      for _, name in ipairs(names) do
        local widget = addIgnoreCreatureEntry(name, focusFirst)
        if widget then focusFirst = false end
      end
    end
    saveIgnoreCreatures()
  end)
end

TargetBot.Looting.setup = function()
  ui = UI.createWidget("TargetBotLootingPanel")
  UI.Container(TargetBot.Looting.onItemsUpdate, true, nil, ui.items)
  UI.Container(TargetBot.Looting.onContainersUpdate, true, nil, ui.containers) 
  refreshIgnoreCreatures()
  ui.ignoreCreaturesButtons.add.onClick = function()
    TargetBot.Looting.editIgnoreCreature(nil)
  end
  ui.ignoreCreaturesButtons.edit.onClick = function()
    local entry = ui.ignoreCreaturesPanel.ignoreCreaturesList:getFocusedChild()
    if not entry then return end
    TargetBot.Looting.editIgnoreCreature(entry)
  end
  ui.ignoreCreaturesButtons.remove.onClick = function()
    local entry = ui.ignoreCreaturesPanel.ignoreCreaturesList:getFocusedChild()
    if not entry then return end
    entry:destroy()
    saveIgnoreCreatures()
  end
  ui.everyItem.onClick = function()
    ui.everyItem:setOn(not ui.everyItem:isOn())
    TargetBot.save()
  end
  ui.maxDangerPanel.value.onTextChange = function()
    local value = tonumber(ui.maxDangerPanel.value:getText())
    if not value then
      ui.maxDangerPanel.value:setText(0)
    end
    if dontSave then return end
    TargetBot.save()
  end
  ui.minCapacityPanel.value.onTextChange = function()
    local value = tonumber(ui.minCapacityPanel.value:getText())
    if not value then
      ui.minCapacityPanel.value:setText(0)
    end
    if dontSave then return end
    TargetBot.save()
  end
end

TargetBot.Looting.onItemsUpdate = function()
  if dontSave then return end
  TargetBot.save()
  TargetBot.Looting.updateItemsAndContainers()
end

TargetBot.Looting.onContainersUpdate = function()
  if dontSave then return end
  TargetBot.save()
  TargetBot.Looting.updateItemsAndContainers()
end

local updateVBotLootLists = function()
  vBot.lootConainers = {}
  vBot.lootItems = {}
  for i, item in ipairs(ui.containers:getItems()) do
    table.insert(vBot.lootConainers, item['id'])
  end
  for i, item in ipairs(ui.items:getItems()) do
    table.insert(vBot.lootItems, item['id'])
  end
end

TargetBot.Looting.update = function(data)
  data = data or {}
  dontSave = true
  TargetBot.Looting.list = {}
  local globalLoot = ensureGlobalLootStorage(data)
  ui.items:setItems(cloneLootList(globalLoot.items))
  ui.containers:setItems(cloneLootList(globalLoot.containers))
  ui.everyItem:setOn(data['everyItem'])
  ui.maxDangerPanel.value:setText(data['maxDanger'] or 10)
  ui.minCapacityPanel.value:setText(data['minCapacity'] or 100)
  TargetBot.Looting.updateItemsAndContainers()
  dontSave = false
  updateVBotLootLists()
end

TargetBot.Looting.save = function(data)
  local globalLoot = saveGlobalLootFromUi()
  data['items'] = cloneLootList(globalLoot.items)
  data['containers'] = cloneLootList(globalLoot.containers)
  data['maxDanger'] = tonumber(ui.maxDangerPanel.value:getText())
  data['minCapacity'] = tonumber(ui.minCapacityPanel.value:getText())
  data['everyItem'] = ui.everyItem:isOn()
end

TargetBot.Looting.updateItemsAndContainers = function()
  items = ui.items:getItems()
  containers = ui.containers:getItems()
  itemsById = {}
  containersById = {}
  for i, item in ipairs(items) do
    itemsById[item.id] = 1
  end
  for i, container in ipairs(containers) do
    containersById[container.id] = 1
  end
  if not dontSave then
    updateVBotLootLists()
  end
end

local waitTill = 0
local waitingForContainer = nil
local status = ""
local lastFoodConsumption = 0

TargetBot.Looting.getStatus = function()
  return status
end

TargetBot.Looting.process = function(targets, dangerLevel)
  if (not items[1] and not ui.everyItem:isOn()) or not containers[1] then
    status = ""
    return false
  end
  if dangerLevel > tonumber(ui.maxDangerPanel.value:getText()) then
    status = "High danger"
    return false
  end
  if player:getFreeCapacity() < tonumber(ui.minCapacityPanel.value:getText()) then
    status = "No cap"
    TargetBot.Looting.list = {}
    return false
  end
  local loot = storage.extras.lootLast and TargetBot.Looting.list[#TargetBot.Looting.list] or TargetBot.Looting.list[1]
  if loot == nil then
    status = ""
    return false
  end

  if waitTill > now then
    return true
  end
  local containers = g_game.getContainers()
  local lootContainers = TargetBot.Looting.getLootContainers(containers)

  -- check if there's container for loot and has empty space for it
  if not lootContainers[1] then
    -- there's no space, don't loot
    status = "No space"
    return false
  end

  status = "Looting"

  for index, container in pairs(containers) do
    if container.lootContainer then
      TargetBot.Looting.lootContainer(lootContainers, container)
      return true
    end
  end

  local pos = player:getPosition()
  local dist = math.max(math.abs(pos.x-loot.pos.x), math.abs(pos.y-loot.pos.y))
  local maxRange = storage.extras.looting or 40
  if loot.tries > 30 or loot.pos.z ~= pos.z or dist > maxRange then
    table.remove(TargetBot.Looting.list, storage.extras.lootLast and #TargetBot.Looting.list or 1)
    return true
  end

  local tile = g_map.getTile(loot.pos)
  if dist >= 3 or not tile then
    loot.tries = loot.tries + 1
    TargetBot.walkTo(loot.pos, 20, { ignoreNonPathable = true, precision = 2 })
    return true
  end

  local container = tile:getTopUseThing()
  if not container or not container:isContainer() then
    table.remove(TargetBot.Looting.list, storage.extras.lootLast and #TargetBot.Looting.list or 1)
    return true
  end

  g_game.open(container)
  waitTill = now + (storage.extras.lootDelay or 200)
  waitingForContainer = container:getId()

  return true
end

TargetBot.Looting.getLootContainers = function(containers)
  local lootContainers = {}
  local openedContainersById = {}
  local toOpen = nil
  for index, container in pairs(containers) do
    openedContainersById[container:getContainerItem():getId()] = 1
    if containersById[container:getContainerItem():getId()] and not container.lootContainer then
      if container:getItemsCount() < container:getCapacity() or container:hasPages() then
        table.insert(lootContainers, container)
      else -- it's full, open next container if possible
        for slot, item in ipairs(container:getItems()) do
          if item:isContainer() and containersById[item:getId()] then
            toOpen = {item, container}
            break
          end
        end
      end
    end
  end
  if not lootContainers[1] then
    if toOpen then
      g_game.open(toOpen[1], toOpen[2])
      waitTill = now + 500 -- wait 0.5s
      return lootContainers
    end
    -- check containers one more time, maybe there's any loot container
    for index, container in pairs(containers) do
      if not containersById[container:getContainerItem():getId()] and not container.lootContainer then
        for slot, item in ipairs(container:getItems()) do
          if item:isContainer() and containersById[item:getId()] then
            g_game.open(item)
            waitTill = now + 500 -- wait 0.5s
            return lootContainers
          end
        end
      end
    end
    -- can't find any lootContainer, let's check slots, maybe there's one
    for slot = InventorySlotFirst, InventorySlotLast do
      local item = getInventoryItem(slot)
      if item and item:isContainer() and not openedContainersById[item:getId()] then
        -- container which is not opened yet, let's open it
        g_game.open(item)
        waitTill = now + 500 -- wait 0.5s
        return lootContainers
      end
    end
  end
  return lootContainers
end

TargetBot.Looting.lootContainer = function(lootContainers, container)
  -- loot items
  local nextContainer = nil
  for i, item in ipairs(container:getItems()) do
    if item:isContainer() and not itemsById[item:getId()] then
      nextContainer = item
    elseif itemsById[item:getId()] or (ui.everyItem:isOn() and not item:isContainer()) then
      item.lootTries = (item.lootTries or 0) + 1
      if item.lootTries < 5 then -- if can't be looted within 0.5s then skip it
        return TargetBot.Looting.lootItem(lootContainers, item)
      end
    elseif storage.foodItems and storage.foodItems[1] and lastFoodConsumption + 5000 < now then
      for _, food in ipairs(storage.foodItems) do
        if item:getId() == food.id then
          g_game.use(item)
          lastFoodConsumption = now
          return
        end
      end
    end
  end

  -- no more items to loot, open next container
  if nextContainer then
    nextContainer.lootTries = (nextContainer.lootTries or 0) + 1
    if nextContainer.lootTries < 2 then -- max 0.6s to open it
      g_game.open(nextContainer, container)
      waitTill = now + 300 -- give it 0.3s to open
      waitingForContainer = nextContainer:getId()
      return
    end
  end
  
  -- looting finished, remove container from list
  container.lootContainer = false
  g_game.close(container)
  table.remove(TargetBot.Looting.list, storage.extras.lootLast and #TargetBot.Looting.list or 1) 
end

onTextMessage(function(mode, text)
  if TargetBot.isOff() then return end
  if #TargetBot.Looting.list == 0 then return end
  if string.find(text:lower(), "you are not the owner") then -- if we are not the owners of corpse then its a waste of time to try to loot it
    table.remove(TargetBot.Looting.list, storage.extras.lootLast and #TargetBot.Looting.list or 1)
  end
end)

TargetBot.Looting.lootItem = function(lootContainers, item)
  if item:isStackable() then
    local count = item:getCount()
    for _, container in ipairs(lootContainers) do
      for slot, citem in ipairs(container:getItems()) do
        if item:getId() == citem:getId() and citem:getCount() < 100 then
          g_game.move(item, container:getSlotPosition(slot - 1), count)
          waitTill = now + 300 -- give it 0.3s to move item
          return
        end
      end
    end
  end

  local container = lootContainers[1]
  g_game.move(item, container:getSlotPosition(container:getItemsCount()), 1)
  waitTill = now + 300 -- give it 0.3s to move item
end

onContainerOpen(function(container, previousContainer)
  if container:getContainerItem():getId() == waitingForContainer then
    container.lootContainer = true
    waitingForContainer = nil
  end
end)

onCreatureDisappear(function(creature)
  if isInPz() then return end
  if not TargetBot.isOn() then return end
  if not creature:isMonster() then return end
  local config = TargetBot.Creature.calculateParams(creature, {}) -- return {craeture, config, danger, priority}
  if not config.config or config.config.dontLoot then
    return
  end
  local pos = player:getPosition()
  local mpos = creature:getPosition()
  local name = creature:getName()
  if not mpos then return end
  if pos.z ~= mpos.z or math.max(math.abs(pos.x-mpos.x), math.abs(pos.y-mpos.y)) > 6 then return end
  schedule(20, function() -- check in 20ms if there's container (dead body) on that tile
    if not containers[1] then return end
    if TargetBot.Looting.list[20] then return end -- too many items to loot
    local tile = g_map.getTile(mpos)
    if not tile then return end
    local container = tile:getTopUseThing()
    if not container or not container:isContainer() then return end
    if not findPath(player:getPosition(), mpos, 6, {ignoreNonPathable=true, ignoreCreatures=true, ignoreCost=true}) then return end
    table.insert(TargetBot.Looting.list, {pos=mpos, creature=name, container=container:getId(), added=now, tries=0})

    table.sort(TargetBot.Looting.list, function(a,b) 
      a.dist = distanceFromPlayer(a.pos)
      b.dist = distanceFromPlayer(b.pos)

      return a.dist > b.dist
    end)
    container:setMarked('#000088')
  end)
end)
