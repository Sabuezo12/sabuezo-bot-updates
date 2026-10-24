local targetbotMacro = nil
local config = nil
local hasConfig = false
local lastAction = 0
local cavebotAllowance = 0
local lureEnabled = true
local dangerValue = 0
local looterStatus = ""
local loadedProfileData = {}
local loadedProfileName = nil
local unifiedEditor = nil

-- ui
dofile("/targetbot/shot_lock.lua")
dofile("/targetbot/unified.lua")
local ui = UI.createWidget("TargetBotPanel")
local configWidget = ui.profile
ui.details=ui.body.details
ui.monsters=ui.body.monsters
ui.status=ui.live.status
ui.target=ui.live.target
ui.config=ui.live.config
ui.danger=ui.live.danger

ui.list = ui.listPanel.list -- shortcut
TargetBot.targetList = ui.list
TargetBot.Looting.setup(ui.lootHost)

ui.status.left:setText("Estado:")
ui.status.right:setText("Off")
ui.target.left:setText("Objetivo:")
ui.target.right:setText("-")
ui.config.left:setText("Regla:")
ui.config.right:setText("-")
ui.danger.left:setText("Peligro:")
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
  if widget:getText() ~= text then widget:setText(text);widget:setTooltip(text) end
end

-- All target paths use the same origin, range and flags. Share the native map
-- for this tick only; new walls and creature positions are read on the next one.
local function targetPath(cycle, origin, destination)
  cycle.targetPaths=cycle.targetPaths or{}
  local pathKey=destination.x..','..destination.y..','..destination.z
  if cycle.targetPaths[pathKey]~=nil then return cycle.targetPaths[pathKey]or nil end
  local function remember(path)cycle.targetPaths[pathKey]=path or false;return path end
  local options = {ignoreLastCreature=true, ignoreNonPathable=true, ignoreCost=true, ignoreCreatures=true}
  local range = cycle.pathRange or 7
  if cycle.sharePaths then
    if not cycle.pathsReady then
      cycle.paths = findAllPaths(origin, range, options)
      cycle.pathsReady = true
    end
    if type(cycle.paths) == "table" then
      local key = destination.x..","..destination.y..","..destination.z
      if not cycle.paths[key] then
        local movement=TargetBot.Movement
        return remember(movement and movement.fieldPath and movement.fieldPath(origin,destination,range,options) or nil)
      end
      return remember(translateAllPathsToPath(cycle.paths,destination))
    end
  end
  local path=findPath(origin,destination,range,options)
  if not path and TargetBot.Movement and TargetBot.Movement.fieldPath then
    path=TargetBot.Movement.fieldPath(origin,destination,range,options)
  end
  return remember(path)
end

-- The crowded-scene shortlist must not drop the monster already being followed.
-- Retain Keep Distance and ranged targets while visible and within rule range.
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
    if rule.keepDistance or rule.chase or TargetBot.ShotLock.applies(rule) then
      range = math.max(range, math.min(10, tonumber(rule.maxDistance) or 10))
    end
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

-- Lure limits describe the full visible pull, not the cheaper priority
-- shortlist used when crowded. Count each reachable, matched monster once;
-- do not run arrow/HP/priority evaluation again for the outer ring.
local function countLureTargets(specs,origin,cycle)
  local total=0
  for _,creature in ipairs(specs)do
    if creature:isMonster()and(oldTibia or creature:getType()<3)then
      local hp=creature:getHealthPercent()
      local p=cycle.positions[creature]or creature:getPosition()
      cycle.positions[creature]=p
      if hp and hp>0 and p and p.z==origin.z and g_map.getTile(p)then
        local rules=TargetBot.Creature.getConfigs(creature)
        if rules and #rules>0 then
          local path=targetPath(cycle,origin,p)
          if path then
            for _,rule in ipairs(rules)do
              if #path<=(tonumber(rule.maxDistance)or 10)then total=total+1;break end
            end
          end
        end
      end
    end
  end
  return total
end

-- main loop, controlled by config
targetbotMacro = macro(100, function()
  if CaveBot and CaveBot.Flee and CaveBot.Flee.blocksCombat() then return end
  if HelperPause and HelperPause.isPaused() then return end
  if isInPz() then
    TargetBot.ShotLock.reset()
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
  if not player then TargetBot.ShotLock.reset();TargetBot.Antitrap.reset();TargetBot.Creature.resetAnchor();return end
  local pos = player:getPosition()
  if not pos or not g_map.getTile(pos) then TargetBot.ShotLock.reset();TargetBot.Antitrap.reset();TargetBot.Creature.resetAnchor();return end
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
    sharePaths=#specs > 1 and type(findAllPaths)=="function" and type(translateAllPathsToPath)=="function"}
  local highestPriority = 0
  local dangerLevel = 0
  local targets = 0
  local highestPriorityParams = nil
  local currentTarget = g_game.getAttackingCreature()
  local currentParams = nil
  -- Remember input before priority checks: an existing PvP safety cancellation
  -- can clear the native mouse destination while evaluating this same tick.
  local pointerManual = TargetBot.Movement and TargetBot.Movement.isPointerManual and TargetBot.Movement.isPointerManual()
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
          if creature == currentTarget then
            params.pathLength = #path
            currentParams = params
          end
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

  -- A new native attack cancels click-to-walk. Keep the current valid target
  -- during manual mouse/BugMap movement; no acquisition if it has disappeared.
  -- Keyboard running retains the normal projectile-gated retarget behavior.
  if pointerManual or TargetBot.Movement and TargetBot.Movement.isPointerManual and TargetBot.Movement.isPointerManual() then
    highestPriorityParams = currentParams and currentParams.config and currentParams.priority>0 and currentParams or nil
  end
  highestPriorityParams = TargetBot.ShotLock.choose(highestPriorityParams, currentParams)

  -- reset walking
  TargetBot.walkTo(nil,nil,{refresh=true})

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
            if (rule.keepDistance==true or rule.dynamicLure==true) and dist<=(tonumber(rule.maxDistance) or 10) then
              activeConfig,activePosition,closest=rule,actorPos,dist
              activeCreature=actor
              break
            end
          end
        end
      end
    end
  end
  local lureTargets=activeConfig and activeConfig.dynamicLure and countLureTargets(specs,pos,cycle)or targets
  if highestPriorityParams then highestPriorityParams.lureTargets=lureTargets end
  TargetBot.Creature.prepareMovement(activeCreature,activeConfig,activeConfig and lureTargets or nil)
  local lureHolding=activeConfig and activeConfig.dynamicLure and TargetBot.Creature.isLureHolding and TargetBot.Creature.isLureHolding()
  if lureHolding then TargetBot.holdCaveBot()end
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
    TargetBot.setStatus(lureHolding and("Lure detenido: "..lureTargets.." / "..activeConfig.lureMax)or"Waiting")
  end
end)

-- Keep the safety check independent of TargetBot.delay used by directional spells.
macro(100, function()
  if CaveBot and CaveBot.Flee and CaveBot.Flee.blocksCombat() or not TargetBot.isOn or not TargetBot.isOn() or isInPz() then
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
  TargetBot.ShotLock.reset()
  hasConfig = type(data) == 'table'
  loadedProfileName = name
  loadedProfileData = type(data)=='table' and TargetBot.Unified.copy(data) or {}
  TargetBot.Antitrap.reset()
  TargetBot.Creature.resetAnchor()
  cavebotAllowance=0
  if not data then
    TargetBot.Creature.resetConfigs()
    if unifiedEditor then unifiedEditor.load(name, nil) end
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
  if unifiedEditor then unifiedEditor.load(name, data) end
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
  if not Config.fileExists("targetbot_configs", name) then
    return warn("there is no targetbot profile with that name!")
  end
  TargetBot.setOff()
  storage._configs.targetbot_configs.selected = name
  TargetBot.setOn()
end

TargetBot.delay = function(value)
  targetbotMacro.delay = now + value
end

TargetBot.canFollowNow = function()
  return TargetBot.isOn() and (not targetbotMacro.delay or targetbotMacro.delay <= now)
end

TargetBot.save = function()
  local data = TargetBot.Unified.copy(loadedProfileData)
  data.targeting = {}
  data.looting = type(data.looting)=='table' and data.looting or {}
  for _, entry in ipairs(ui.list:getChildren()) do
    table.insert(data.targeting, entry.value)
  end
  TargetBot.Looting.save(data.looting)
  return config.save(data)
end

-- Legacy callers remain harmless; AttackBot owns spell facing and alignment.
TargetBot.enableFaceMonsters = function() return 0 end

-- The engine's existing rows stay private; the unified list edits a draft.
unifiedEditor = TargetBot.Unified.create(ui, {
  getProfile=function() return loadedProfileName end,
  getProfiles=function() return Config.list('targetbot_configs') end,
  canSave=function() return hasConfig and loadedProfileName~=nil end,
  getRules=function()
    local result={}
    for _,entry in ipairs(ui.list:getChildren()) do result[#result+1]=TargetBot.Unified.copy(entry.value) end
    return result
  end,
  apply=function(rules)
    if not hasConfig then return false, 'Crea o selecciona un perfil de TargetBot.' end
    local previous={}
    for _,entry in ipairs(ui.list:getChildren()) do previous[#previous+1]=entry.value end
    TargetBot.Creature.resetConfigs()
    for _,rule in ipairs(rules) do TargetBot.Creature.addConfig(TargetBot.Unified.copy(rule)) end
    local ok,result=pcall(TargetBot.save)
    if not ok or result==false then
      TargetBot.Creature.resetConfigs()
      for _,rule in ipairs(previous) do TargetBot.Creature.addConfig(rule) end
      return false,'No se pudo guardar: '..tostring(result)
    end
    loadedProfileData.targeting=TargetBot.Unified.copy(rules)
    return true
  end,
  createProfile=function(name)
    for _,existing in ipairs(Config.list('targetbot_configs')) do
      if existing:lower()==name:lower() then return false,'Ya existe un perfil con ese nombre.' end
    end
    Config.save('targetbot_configs',name,{targeting={},looting={}},'json')
    storage._configs.targetbot_configs.selected=name
    configWidget.switch:setOn(false)
    config.reload()
    return true
  end,
  close=function()
    local item=Helper and Helper.widgets and Helper.widgets[ui]
    if item and item.floatingPanel and Helper.closeFloatingPanel then
      Helper.closeFloatingPanel(item.floatingPanel,true)
    else ui:hide() end
  end,
})
TargetBot.Unified.instance=unifiedEditor

unifiedEditor.load(loadedProfileName,hasConfig and loadedProfileData or nil)

TargetBot.holdCaveBot=function(stop)
  cavebotAllowance=0;lastAction=now
  if stop then
    TargetBot.walkTo(nil)
    if CaveBot and CaveBot.resetWalking then CaveBot.resetWalking()end
    local emergency=TargetBot.Antitrap and TargetBot.Antitrap.ownsMovement()
    if not emergency and player and player.isWalking and player:isWalking()and g_game.stop then pcall(g_game.stop)end
  end
end

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
