local targetbotMacro = nil
local config = nil
local hasConfig = false
local lastAction = 0
local cavebotAllowance = 0
local lureEnabled = true
local dangerValue = 0
local looterStatus = ""

-- ui
local configWidget = UI.Config()
local ui = UI.createWidget("TargetBotPanel")

ui.list = ui.listPanel.list -- shortcut
TargetBot.targetList = ui.list
TargetBot.Looting.setup()

ui.status.left:setText("Status:")
ui.status.right:setText("Off")
ui.target.left:setText("Target:")
ui.target.right:setText("-")
ui.config.left:setText("Config:")
ui.config.right:setText("-")
ui.danger.left:setText("Danger:")
ui.danger.right:setText("0")

-- ui.editor.debug.onClick = function()
--   local on = ui.editor.debug:isOn()
--   ui.editor.debug:setOn(not on)
--   if on then
--     for _, spec in ipairs(getSpectators()) do
--       spec:clearText()
--     end
--   end
-- end

local oldTibia = g_game.getClientVersion() < 960

local function setText(widget, text)
  text = tostring(text)
  if widget:getText() ~= text then widget:setText(text) end
end

-- All target paths use the same origin, range and flags. Share the native map
-- for this tick only; new walls and creature positions are read on the next one.
local function targetPath(cycle, origin, destination)
  local options = {ignoreLastCreature=true, ignoreNonPathable=true, ignoreCost=true, ignoreCreatures=true}
  local range = cycle.pathRange or 7
  if cycle.sharePaths then
    if not cycle.pathsReady then
      cycle.paths = findAllPaths(origin, range, options)
      cycle.pathsReady = true
    end
    if type(cycle.paths) == "table" then
      local key = destination.x..","..destination.y..","..destination.z
      if not cycle.paths[key] then return nil end
      return translateAllPathsToPath(cycle.paths, destination)
    end
  end
  return findPath(origin, destination, range, options)
end

-- The crowded-scene shortlist must not drop the monster already being followed.
-- Extend only that Keep Distance target, while visible and within its rule range.
local function keepFollowingTarget(creatures, specs, pos)
  local current = g_game.getAttackingCreature()
  if not current or not current:isMonster() or not TargetBot.Creature.getConfigs then return creatures end
  for _,actor in ipairs(creatures) do if actor == current then return creatures end end
  local destination = current:getPosition()
  local hp = current:getHealthPercent()
  if not destination or destination.z ~= pos.z or not hp or hp <= 0 then return creatures end
  local distance = math.max(math.abs(pos.x-destination.x), math.abs(pos.y-destination.y))
  local range = 0
  for _,rule in ipairs(TargetBot.Creature.getConfigs(current)) do
    if rule.keepDistance then range = math.max(range, math.min(10, tonumber(rule.maxDistance) or 10)) end
  end
  if range == 0 or distance > range then return creatures end
  local visible = false
  for _,actor in ipairs(specs) do if actor == current then visible = true;break end end
  if not visible then
    for _,actor in ipairs(g_map.getSpectatorsInRange(pos, false, range, range)) do
      if actor == current then visible = true;break end
    end
  end
  if not visible then return creatures end
  local candidates = {}
  for _,actor in ipairs(creatures) do candidates[#candidates+1] = actor end
  candidates[#candidates+1] = current
  return candidates, 10
end

-- main loop, controlled by config
targetbotMacro = macro(100, function()
  if isInPz() then
    -- Do not leave an old attack/walking status active while in protection.
    TargetBot.walkTo(nil)
    TargetBot.Antitrap.reset()
    TargetBot.Creature.resetAnchor()
    if g_game.isAttacking() then g_game.cancelAttack() end
    lastAction, dangerValue, looterStatus = 0, 0, ""
    setText(ui.target.right, "-")
    setText(ui.config.right, "-")
    setText(ui.danger.right, "0")
    TargetBot.setStatus("Protection zone")
    return
  end
  if not player then TargetBot.Antitrap.reset();TargetBot.Creature.resetAnchor();return end
  local pos = player:getPosition()
  if not pos or not g_map.getTile(pos) then TargetBot.Antitrap.reset();TargetBot.Creature.resetAnchor();return end
  local specs = g_map.getSpectatorsInRange(pos, false, 6, 6)
  local creatures = 0
  for i, spec in ipairs(specs) do
    if spec:isMonster() then
      creatures = creatures + 1
    end
  end
  if creatures > 10 then -- The safety check below still uses the full scene.
    creatures = g_map.getSpectatorsInRange(pos, false, 3, 3) -- 6x6 area
  else
    creatures = specs
  end
  local followPathRange
  creatures, followPathRange = keepFollowingTarget(creatures, specs, pos)
  local cycle = {creatures=creatures, positions={}, origin=pos, pathRange=followPathRange,
    sharePaths=#creatures > 1 and type(findAllPaths)=="function" and type(translateAllPathsToPath)=="function"}
  local highestPriority = 0
  local dangerLevel = 0
  local targets = 0
  local highestPriorityParams = nil
  for i, creature in ipairs(creatures) do
    if creature:isMonster() and (oldTibia or creature:getType() < 3) then
      local hppc = creature:getHealthPercent()
      local creaturePos = cycle.positions[creature] or creature:getPosition()
      cycle.positions[creature] = creaturePos
      if hppc and hppc > 0 and creaturePos and creaturePos.z == pos.z and g_map.getTile(creaturePos) then
        local rules = TargetBot.Creature.getConfigs and TargetBot.Creature.getConfigs(creature)
        local path = (not rules or #rules > 0) and targetPath(cycle, pos, creaturePos)
        if path then
          local params = TargetBot.Creature.calculateParams(creature, path, cycle) -- return {creature, config, danger, priority}
          dangerLevel = dangerLevel + params.danger
          if params.priority > 0 and params.config then
            targets = targets + 1
            if params.priority > highestPriority then
              highestPriority = params.priority
              highestPriorityParams = params
            end
            if storage.extras.showTargetPriority then
              creature:setText(params.config.name .. "\n" .. params.priority)
            end
          end
        end
      end
    end
  end

  -- reset walking
  TargetBot.walkTo(nil)

  -- looting
  local activeConfig = highestPriorityParams and highestPriorityParams.config
  local activeCreature = highestPriorityParams and highestPriorityParams.creature
  local activePosition = highestPriorityParams and highestPriorityParams.creature:getPosition()
  -- A temporarily unshootable target (for example PvP-safe arrows) still needs distance safety.
  if not activeConfig and TargetBot.Creature.getConfigs then
    local closest
    for _,actor in ipairs(specs) do
      local actorPos=actor:getPosition()
      local actorHp=actor:getHealthPercent()
      if actor:isMonster() and actorPos and actorPos.z==pos.z and actorHp and actorHp>0 then
        local dist=math.max(math.abs(pos.x-actorPos.x),math.abs(pos.y-actorPos.y))
        if not closest or dist<closest then
          for _,rule in ipairs(TargetBot.Creature.getConfigs(actor)) do
            if rule.keepDistance==true and dist<=(tonumber(rule.maxDistance) or 10) then
              activeConfig,activePosition,closest=rule,actorPos,dist
              activeCreature=actor
              break
            end
          end
        end
      end
    end
  end
  TargetBot.Creature.prepareMovement(activeCreature,activeConfig,highestPriorityParams and targets or nil)
  local anchor = TargetBot.Creature.getAnchorPosition()
  if anchor then cavebotAllowance=0 end -- End the previous gather allowance at combat entry.
  local escape = TargetBot.Antitrap.update(specs, pos, activeConfig, now, activePosition, anchor)
  local looting = false
  if not escape then looting=TargetBot.Looting.process(targets, dangerLevel) end
  local lootingStatus = TargetBot.Looting.getStatus()
  looterStatus = TargetBot.Looting.getStatus()
  dangerValue = dangerLevel

  setText(ui.danger.right, dangerLevel)
  if escape then
    cavebotAllowance=0
    if highestPriorityParams and highestPriorityParams.config then
      setText(ui.target.right, highestPriorityParams.creature:getName())
      setText(ui.config.right, highestPriorityParams.config.name)
      TargetBot.Creature.attack(highestPriorityParams, targets, false, true)
    else
      setText(ui.target.right, "-");setText(ui.config.right, "-")
    end
    TargetBot.Antitrap.send(escape,now)
    TargetBot.setStatus(escape.status)
    lastAction=now
    return
  end
  if highestPriorityParams and highestPriorityParams.config and not isInPz() then
    setText(ui.target.right, highestPriorityParams.creature:getName())
    setText(ui.config.right, highestPriorityParams.config.name)
    TargetBot.Creature.attack(highestPriorityParams, targets, looting)    
    if lootingStatus:len() > 0 then
      TargetBot.setStatus("Attack & " .. lootingStatus)
    elseif cavebotAllowance > now then
      TargetBot.setStatus("Luring using CaveBot")
    else
      TargetBot.setStatus("Attacking")
      if not lureEnabled then
        TargetBot.setStatus("Attacking (luring off)")      
      end
    end
    TargetBot.walk()
    lastAction = now
    return
  elseif isInPz() then
    if g_game.isAttacking() then
      g_game.cancelAttack()
      return
    end
  end

  setText(ui.target.right, "-")
  setText(ui.config.right, "-")
  if looting then
    TargetBot.walk()
    lastAction = now
  end
  if lootingStatus:len() > 0 then
    TargetBot.setStatus(lootingStatus)
  else
    TargetBot.setStatus("Waiting")
  end
end)

-- Keep the safety check independent of TargetBot.delay used by directional spells.
macro(100, function()
  if not TargetBot.isOn or not TargetBot.isOn() or isInPz() then
    TargetBot.Antitrap.reset()
    TargetBot.Creature.resetAnchor()
    return
  end
  local escape=TargetBot.Antitrap.poll(now)
  if escape then
    TargetBot.Antitrap.send(escape,now)
    cavebotAllowance=0
    lastAction=now
    TargetBot.setStatus(escape.status)
  end
end)

-- config, its callback is called immediately, data can be nil
config = Config.setup("targetbot_configs", configWidget, "json", function(name, enabled, data)
  hasConfig = type(data) == 'table'
  TargetBot.Antitrap.reset()
  TargetBot.Creature.resetAnchor()
  cavebotAllowance=0
  if not data then
    setText(ui.status.right, "Off")
    return targetbotMacro.setOff() 
  end
  TargetBot.Creature.resetConfigs()
  for _, value in ipairs(data["targeting"] or {}) do
    TargetBot.Creature.addConfig(value)
  end
  TargetBot.Looting.update(data["looting"] or {})

  -- add configs
  if enabled then
    setText(ui.status.right, "On")
  else
    setText(ui.status.right, "Off")
  end

  targetbotMacro.setOn(enabled)
  targetbotMacro.delay = nil
  lureEnabled = true
  if AttackBot and AttackBot.syncTargetFacing then AttackBot.syncTargetFacing() end
end)

-- setup ui
ui.editor.buttons.add.onClick = function()
  TargetBot.Creature.edit(nil, function(newConfig)
    TargetBot.Creature.addConfig(newConfig, true)
    TargetBot.save()
  end)
end

ui.editor.buttons.edit.onClick = function()
  local entry = ui.list:getFocusedChild()
  if not entry then return end
  TargetBot.Creature.edit(entry.value, function(newConfig)
    entry:setText(newConfig.name)
    entry.value = newConfig
    TargetBot.Creature.resetConfigsCache()
    TargetBot.save()
  end)
end

ui.editor.buttons.remove.onClick = function()
  local entry = ui.list:getFocusedChild()
  if not entry then return end
  entry:destroy()
  TargetBot.Creature.resetConfigsCache()
  TargetBot.save()
end

-- public function, you can use them in your scripts
TargetBot.isActive = function() -- return true if attacking or looting takes place
  return TargetBot.Antitrap.ownsMovement() or lastAction + 300 > now
end

TargetBot.isCaveBotActionAllowed = function()
  if TargetBot.Antitrap.ownsMovement() then return false end
  return cavebotAllowance > now
end

TargetBot.setStatus = function(text)
  return setText(ui.status.right, text)
end

TargetBot.getStatus = function()
  return ui.status.right:getText()
end

TargetBot.isOn = function()
  return config and config.isOn and config.isOn() or false
end

TargetBot.isOff = function()
  return not config or not config.isOff or config.isOff()
end

TargetBot.setOn = function(val)
  if val == false then  
    return TargetBot.setOff(true)
  end
  if not config or not config.setOn then return end
  config.setOn()
end

TargetBot.setOff = function(val)
  if val == false then  
    return TargetBot.setOn(true)
  end
  if not config or not config.setOff then return end
  config.setOff()
end

TargetBot.getCurrentProfile = function()
  return storage._configs.targetbot_configs.selected
end

local botConfigName = modules.game_bot.contentsPanel.config:getCurrentOption().text
TargetBot.setCurrentProfile = function(name)
  if not g_resources.fileExists("/bot/"..botConfigName.."/targetbot_configs/"..name..".json") then
    return warn("there is no targetbot profile with that name!")
  end
  TargetBot.setOff()
  storage._configs.targetbot_configs.selected = name
  TargetBot.setOn()
end

TargetBot.delay = function(value)
  targetbotMacro.delay = now + value
end

TargetBot.save = function()
  local data = {targeting={}, looting={}}
  for _, entry in ipairs(ui.list:getChildren()) do
    table.insert(data.targeting, entry.value)
  end
  TargetBot.Looting.save(data.looting)
  config.save(data)
end

-- Operate only on the loaded Target profile and save once for all its rules.
-- No timer or attack-cycle writes; identical settings are a no-op.
TargetBot.enableFaceMonsters = function()
  if not config or not hasConfig then return 0 end
  local changed = 0
  for _, entry in ipairs(ui.list:getChildren()) do
    if type(entry.value) == 'table' and entry.value.faceMonster ~= true then
      entry.value.faceMonster = true
      changed = changed + 1
    end
  end
  if changed > 0 then
    TargetBot.Creature.resetConfigsCache()
    TargetBot.save()
  end
  return changed
end
-- Config.setup calls its first callback before the save API is ready.
if AttackBot and AttackBot.syncTargetFacing then AttackBot.syncTargetFacing() end

TargetBot.allowCaveBot = function(time)
  if TargetBot.Antitrap.ownsMovement() then return end
  cavebotAllowance = now + time
end

TargetBot.disableLuring = function()
  lureEnabled = false
end

TargetBot.enableLuring = function()
  lureEnabled = true
end

TargetBot.Danger = function()
  return dangerValue
end

TargetBot.lootStatus = function()
  return looterStatus
end


-- attacks
local lastSpell = 0
local lastAttackSpell = 0

TargetBot.saySpell = function(text, delay)
  if type(text) ~= 'string' or text:len() < 1 then return end
  if not delay then delay = 500 end
  if g_game.getProtocolVersion() < 1090 then
    lastAttackSpell = now -- pause attack spells, healing spells are more important
  end
  if lastSpell + delay < now then
    say(text)
    lastSpell = now
    return true
  end
  return false
end

TargetBot.sayAttackSpell = function(text, delay)
  if type(text) ~= 'string' or text:len() < 1 then return end
  if not delay then delay = 2000 end
  if lastAttackSpell + delay < now then
    say(text)
    lastAttackSpell = now
    return true
  end
  return false
end

local lastItemUse = 0
local lastRuneAttack = 0

TargetBot.useItem = function(item, subType, target, delay)
  if not delay then delay = 200 end
  if lastItemUse + delay < now then
    local thing = g_things.getThingType(item)
    if not thing or not thing:isFluidContainer() then
      subType = g_game.getClientVersion() >= 860 and 0 or 1
    end
    if g_game.getClientVersion() < 780 then
      local tmpItem = g_game.findPlayerItem(item, subType)
      if not tmpItem then return end
      g_game.useWith(tmpItem, target, subType) -- using item from bp
    else
      g_game.useInventoryItemWith(item, target, subType) -- hotkey
    end
    lastItemUse = now
  end
end

TargetBot.useAttackItem = function(item, subType, target, delay)
  if not delay then delay = 2000 end
  if lastRuneAttack + delay < now then
    local thing = g_things.getThingType(item)
    if not thing or not thing:isFluidContainer() then
      subType = g_game.getClientVersion() >= 860 and 0 or 1
    end
    if g_game.getClientVersion() < 780 then
      local tmpItem = g_game.findPlayerItem(item, subType)
      if not tmpItem then return end
      g_game.useWith(tmpItem, target, subType) -- using item from bp  
    else
      g_game.useInventoryItemWith(item, target, subType) -- hotkey
    end
    lastRuneAttack = now
  end
end

TargetBot.canLure = function()
  return lureEnabled
end

UI.Separator()
