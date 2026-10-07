
TargetBot.Creature = {}
TargetBot.Creature.configsCache = {}
TargetBot.Creature.cached = 0
local reachableContext = nil
local reachableDirections = {{0,-1},{1,0},{0,1},{-1,0},{1,-1},{1,1},{-1,1},{-1,-1}}
local REACHABLE_NODE_LIMIT = 512
local function reachableKey(position) return position.x..':'..position.y end
local function validPosition(position)
  return type(position)=='table' and type(position.x)=='number' and type(position.y)=='number'
    and type(position.z)=='number' and position.x==math.floor(position.x) and position.x>=0 and position.x<=65535
    and position.y==math.floor(position.y) and position.y>=0 and position.y<=65535
    and position.z==math.floor(position.z) and position.z>=0 and position.z<=15
end
local function reachableDistance(a,b) return math.max(math.abs(a.x-b.x),math.abs(a.y-b.y)) end
local function reachabilityContext()
  local origin=player and player:getPosition()
  if not validPosition(origin) then reachableContext=nil;return nil end
  local range=tonumber(storage.extras.looting)
  if not range or range~=range or range==math.huge or range==-math.huge then range=40 end
  range=math.max(0,math.min(50,math.floor(range)))
  local cached=reachableContext
  if cached and now~=nil and cached.time==now and cached.range==range
    and cached.origin.x==origin.x and cached.origin.y==origin.y and cached.origin.z==origin.z then return cached end
  local ctx={origin={x=origin.x,y=origin.y,z=origin.z},range=range,time=now,occupied={},free={}}
  for _,actor in ipairs(g_map.getSpectatorsInRange(ctx.origin,false,7,7)) do
    local position=actor:getPosition()
    if actor~=player and validPosition(position) and position.z==ctx.origin.z then
      ctx.occupied[reachableKey(position)]=true
    end
  end
  reachableContext=ctx
  return ctx
end
local function reachableTile(ctx,position)
  local id=reachableKey(position)
  if ctx.free[id]~=nil then return ctx.free[id] end
  if position.x==ctx.origin.x and position.y==ctx.origin.y then ctx.free[id]=true;return true end
  local tile=validPosition(position) and not ctx.occupied[id] and g_map.getTile(position)
  ctx.free[id]=tile and tile:isWalkable(false)==true and (not tile.isPathable or tile:isPathable()==true) or false
  return ctx.free[id]
end
local function walkableExistingPath(ctx,destination,path)
  if type(path)~='table' then return false end
  local position={x=ctx.origin.x,y=ctx.origin.y,z=ctx.origin.z}
  for i=0,math.min(#path,ctx.range) do
    if reachableDistance(position,destination)<=1 then return true end
    local direction=path[i+1]
    local offset=type(direction)=='number' and reachableDirections[direction+1] or nil
    if not offset then return false end
    position={x=position.x+offset[1],y=position.y+offset[2],z=position.z}
    if not reachableTile(ctx,position) then return false end
  end
  return false
end
local function reachedDestination(ctx,destination)
  for x=-1,1 do for y=-1,1 do
    if ctx.nodes[(destination.x+x)..':'..(destination.y+y)]~=nil then return true end
  end end
  return false
end
local function buildReachableMap(ctx,destination)
  if not ctx.nodes then
    ctx.nodes={[reachableKey(ctx.origin)]=0}
    ctx.queue,ctx.head={{position=ctx.origin,depth=0}},1
  end
  if reachedDestination(ctx,destination) then return true end
  -- Expand the same bounded search only until this target is reached. Later
  -- targets can resume it; no live tiles or creatures survive into a new cycle.
  while ctx.head<=#ctx.queue do
    local node=ctx.queue[ctx.head];ctx.head=ctx.head+1
    local reached=false
    if node.depth<ctx.range then
      for _,offset in ipairs(reachableDirections) do
        local position={x=node.position.x+offset[1],y=node.position.y+offset[2],z=ctx.origin.z}
        local id=reachableKey(position)
        if ctx.nodes[id]==nil and reachableTile(ctx,position) then
          if #ctx.queue<REACHABLE_NODE_LIMIT then
            ctx.nodes[id]=node.depth+1
            ctx.queue[#ctx.queue+1]={position=position,depth=node.depth+1}
            if reachableDistance(position,destination)<=1 then reached=true end
          else ctx.truncated=true end
        end
      end
    end
    -- Finish this node before stopping so that resuming never skips neighbors.
    if reached then return true end
  end
  return false
end

-- The client's native second findPath call can raise a fatal C++ error here.
-- Reuse the already validated path, then share one bounded Lua map per cycle.
TargetBot.Creature.isReachable = function(creature,path)
  local destination=creature and creature:getPosition()
  local ctx=reachabilityContext()
  if not ctx or not validPosition(destination) or destination.z~=ctx.origin.z then return nil end
  if reachableDistance(ctx.origin,destination)<=1 then return true end
  if reachableDistance(ctx.origin,destination)>ctx.range+1 then return false end
  if walkableExistingPath(ctx,destination,path) then return true end
  if buildReachableMap(ctx,destination) then return true end
  if ctx.truncated then return nil end -- An incomplete search must not downgrade a target.
  return false
end

TargetBot.Creature.resetConfigs = function()
  TargetBot.targetList:destroyChildren()
  TargetBot.Creature.resetConfigsCache()
end

TargetBot.Creature.resetConfigsCache = function()
  reachableContext = nil
  TargetBot.Creature.configsCache = {}
  TargetBot.Creature.cached = 0
end

TargetBot.Creature.addConfig = function(config, focus)
  if type(config) ~= 'table' or type(config.name) ~= 'string' then
    return error("Invalid targetbot creature config (missing name)")
  end
  TargetBot.Creature.resetConfigsCache()

  if not config.regex then
    config.regex = ""
    for part in string.gmatch(config.name, "[^,]+") do
      if config.regex:len() > 0 then
        config.regex = config.regex .. "|"
      end
      config.regex = config.regex .. "^" .. part:trim():lower():gsub("%*", ".*"):gsub("%?", ".?") .. "$"
    end
  end

  local widget = UI.createWidget("TargetBotEntry", TargetBot.targetList)
  widget:setText(config.name)
  widget.value = config

  widget.onDoubleClick = function(entry) -- edit on double click
    schedule(20, function() -- schedule to have correct focus
      TargetBot.Creature.edit(entry.value, function(newConfig)
        entry:setText(newConfig.name)
        entry.value = newConfig
        TargetBot.Creature.resetConfigsCache()
        TargetBot.save()
      end)
    end)
  end

  if focus then
    widget:focus()
    TargetBot.targetList:ensureChildVisible(widget)
  end
  return widget
end

local ignoreSource = nil
local ignoreNames = {}
TargetBot.Creature.getConfigs = function(creature)
  if not creature then return {} end
  local name = creature:getName():trim():lower()
  -- ignore list
  local source = storage.extras.ignoreCreatures
  if ignoreSource ~= source then
    ignoreSource, ignoreNames = source, {}
    local ignoreList = source and string.split(source, ",") or {}
    for k, v in ipairs(ignoreList) do
      ignoreNames[v:lower():trim()] = true
    end
  end
  if ignoreNames[name] then
    creature:setText("ignore")
    return {}
  end
  -- this function may be slow, so it will be using cache
  if TargetBot.Creature.configsCache[name] then
    return TargetBot.Creature.configsCache[name]
  end
  local configs = {}
  for _, config in ipairs(TargetBot.targetList:getChildren()) do
    if regexMatch(name, config.value.regex)[1] then
      table.insert(configs, config.value)
    end
  end
  if TargetBot.Creature.cached > 1000 then 
    TargetBot.Creature.resetConfigsCache() -- too big cache size, reset
  end
  TargetBot.Creature.configsCache[name] = configs -- add to cache
  TargetBot.Creature.cached = TargetBot.Creature.cached + 1
  return configs
end

TargetBot.Creature.calculateParams = function(creature, path, cycle)
  local configs = TargetBot.Creature.getConfigs(creature)
  local priority = 0
  local danger = 0
  local selectedConfig = nil
  for _, config in ipairs(configs) do
    local config_priority = TargetBot.Creature.calculatePriority(creature, config, path, cycle)
    if config_priority > priority then
      priority = config_priority
      danger = TargetBot.Creature.calculateDanger(creature, config, path)
      selectedConfig = config
    end
  end
  if selectedConfig and storage.extras.reachable and TargetBot.Creature.isReachable(creature,path)==false then
    priority = 1
  end
  if priority > 0 and not selectedConfig then
    priority = 0
  end
  return {
    config = selectedConfig,
    creature = creature,
    danger = danger,
    priority = priority
  }
end

TargetBot.Creature.calculateDanger = function(creature, config, path)
  -- config is based on creature_editor
  return config.danger
end
