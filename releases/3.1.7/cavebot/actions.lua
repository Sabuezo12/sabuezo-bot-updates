CaveBot.Actions = {}
vBot.lastLabel = ""
local oldTibia = g_game.getClientVersion() < 960
local nextTile = nil
local CAVEBOT_MAX_STAMINA_MINUTES = 2520 -- 42h

local noPath = 0

-- antistuck f()
local nextPos = nil -- creature
local nextPosF = nil -- furniture
local function modPos(dir)
    local y = 0
    local x = 0

    if dir == 0 then
        y = -1
    elseif dir == 1 then
        x = 1
    elseif dir == 2 then
        y = 1
    elseif dir == 3 then
        x = -1
    elseif dir == 4 then
        y = -1
        x = 1
    elseif dir == 5 then
        y = 1
        x = 1
    elseif dir == 6 then
        y = 1
        x = -1
    elseif dir == 7 then
        y = -1
        x = -1
    end

    return {x, y}
end

-- stack-covered antystuck, in & out pz
local lastMoved = now - 200
onTextMessage(function(mode, text)
  if CaveBot and CaveBot.Flee and CaveBot.Flee.blocksCombat() then return end
  if text ~= 'There is not enough room.' then return end
  if CaveBot.isOff() then return end

  local tiles = getNearTiles(pos())

  for i, tile in ipairs(tiles) do
    if not tileHasCreature(tile) and tile:isWalkable() and #tile:getItems() > 9 then
      local topThing = tile:getTopThing()
      if not isInPz() then
        return useWith(3197, tile:getTopThing()) -- disintegrate
      else
        if now < lastMoved + 200 then return end -- delay to prevent clogging
        local nearTiles = getNearTiles(tile:getPosition())
        for i, tile in ipairs(nearTiles) do
          local tpos = tile:getPosition()
          if pos() ~= tpos then
            if tile:isWalkable() then
              lastMoved = now
              return g_game.move(topThing, tpos) -- move item
            end
          end
        end
      end
    end
  end
end)

local furnitureIgnore = { 2986 }
local function breakFurniture(destPos)
  if isInPz() then return false end
  local candidate = {thing=nil, dist=100}
  local playerPos = player:getPosition()
  for i, tile in ipairs(g_map.getTiles(posz())) do
    local walkable = tile:isWalkable()
    local topThing = tile:getTopThing()
    local isWg = topThing and topThing:getId() == 2130
    if topThing and (isWg or not table.find(furnitureIgnore, topThing:getId()) and topThing:isItem()) then
      local moveable = not topThing:isNotMoveable()
      if isWg or (not walkable and moveable) then
        local tpos = tile:getPosition()
        if getDistanceBetween(playerPos, tpos) <= 7 then
          local path = findPath(playerPos, tpos, 7, { ignoreNonPathable = true, precision = 1 })
          if path then
            local distance = getDistanceBetween(destPos, tpos)

            if distance < candidate.dist then
              candidate = {thing=topThing, dist=distance}
            end
          end
        end
      end
    end
  end

  local thing = candidate.thing
  if thing then
    useWith(3197, thing)
    return true
  end
  
  return false
end

local function pushPlayer(creature)
  local cpos = creature:getPosition()
  local tiles = getNearTiles(cpos)

  for i, tile in ipairs(tiles) do
    local pos = tile:getPosition()
    local minimapColor = g_map.getMinimapColor(pos)
    local stairs = (minimapColor >= 210 and minimapColor <= 213)

    if not stairs and tile:isWalkable() then
      g_game.move(creature, pos)
    end
  end

end

local function pathfinder()
  if not storage.extras.pathfinding then return end
  if noPath < 10 then return end

  if not CaveBot.gotoNextWaypointInRange() then
    if getConfigFromName and getConfigFromName() then
      local profile = CaveBot.getCurrentProfile()
      local config = getConfigFromName()
      local newProfile = profile == '#Unibase' and config or '#Unibase'
      
      CaveBot.setCurrentProfile(newProfile)
    end
  end
  noPath = 0
  return true
end

-- it adds an action widget to list
CaveBot.addAction = function(action, value, focus)
  action = action:lower()
  local raction = CaveBot.Actions[action]
  if not raction then
    return warn("Invalid cavebot action: " .. action)
  end
  if type(value) == 'number' then
    value = tostring(value)
  end
  local widget = UI.createWidget("CaveBotAction", CaveBot.actionList)
  local preview = action == "waitstamina" and CaveBot.WaitStamina.describe(value) or value:split("\n")[1]
  widget:setText((action == "zonapz" and "ZonaPZ" or action) .. ":" .. preview)
  if action == "waitstamina" then widget:setTooltip(preview .. "\nDoble clic para configurar horas, espera y destinos.") end
  widget.action = action
  widget.value = value
  if raction.color then
    widget:setColor(raction.color)
  end
  widget.onDoubleClick = function(cwidget) -- edit on double click
    if CaveBot.Editor then
      schedule(20, function() -- schedule to have correct focus
        CaveBot.Editor.edit(cwidget.action, cwidget.value, function(action, value)
          CaveBot.editAction(cwidget, action, value)
          CaveBot.save()
        end)
      end)
    end
  end
  if CaveBot.Waypoints then CaveBot.Waypoints.track(widget) end
  if focus then
    widget:focus()
    CaveBot.actionList:ensureChildVisible(widget)
  end
  return widget
end

-- it updates existing widget, you should call CaveBot.save() later
CaveBot.editAction = function(widget, action, value)
  action = action:lower()
  local raction = CaveBot.Actions[action]
  if not raction then
    return warn("Invalid cavebot action: " .. action)
  end
  
  if not widget.action or not widget.value then
    return warn("Invalid cavebot action widget, has missing action or value")  
  end
  
  local preview = action == "waitstamina" and CaveBot.WaitStamina.describe(value) or value:split("\n")[1]
  widget:setText((action == "zonapz" and "ZonaPZ" or action) .. ":" .. preview)
  if action == "waitstamina" then widget:setTooltip(preview .. "\nDoble clic para configurar horas, espera y destinos.") end
  widget.action = action
  widget.value = value
  if raction.color then
    widget:setColor(raction.color)
  end
  if CaveBot.Waypoints then CaveBot.Waypoints.changed() end
  return widget
end

--[[
registerAction:
action - string, color - string, callback = function(value, retries, prev)
value is a string value of action, retries is number which will grow by 1 if return is "retry"
prev is a true when previuos action was executed succesfully, false otherwise
it must return true if executed correctly, false otherwise
it can also return string "retry", then the function will be called again in 20 ms
]]--
CaveBot.registerAction = function(action, color, callback) 
  action = action:lower()
  if CaveBot.Actions[action] then
    return warn("Duplicated acction: " .. action)
  end
  CaveBot.Actions[action] = {
    color=color,
    callback=callback
  }
end

CaveBot.FunctionHelpers = CaveBot.FunctionHelpers or {}

local cavebotStepDirections = {
  n = {dir = North, x = 0, y = -1},
  north = {dir = North, x = 0, y = -1},
  norte = {dir = North, x = 0, y = -1},
  e = {dir = East, x = 1, y = 0},
  east = {dir = East, x = 1, y = 0},
  este = {dir = East, x = 1, y = 0},
  derecha = {dir = East, x = 1, y = 0},
  s = {dir = South, x = 0, y = 1},
  south = {dir = South, x = 0, y = 1},
  sur = {dir = South, x = 0, y = 1},
  w = {dir = West, x = -1, y = 0},
  west = {dir = West, x = -1, y = 0},
  oeste = {dir = West, x = -1, y = 0},
  izquierda = {dir = West, x = -1, y = 0},
  ne = {dir = NorthEast, x = 1, y = -1},
  northeast = {dir = NorthEast, x = 1, y = -1},
  ["north-east"] = {dir = NorthEast, x = 1, y = -1},
  noreste = {dir = NorthEast, x = 1, y = -1},
  nordeste = {dir = NorthEast, x = 1, y = -1},
  se = {dir = SouthEast, x = 1, y = 1},
  southeast = {dir = SouthEast, x = 1, y = 1},
  ["south-east"] = {dir = SouthEast, x = 1, y = 1},
  sureste = {dir = SouthEast, x = 1, y = 1},
  nw = {dir = NorthWest, x = -1, y = -1},
  northwest = {dir = NorthWest, x = -1, y = -1},
  ["north-west"] = {dir = NorthWest, x = -1, y = -1},
  noroeste = {dir = NorthWest, x = -1, y = -1},
  sw = {dir = SouthWest, x = -1, y = 1},
  southwest = {dir = SouthWest, x = -1, y = 1},
  ["south-west"] = {dir = SouthWest, x = -1, y = 1},
  suroeste = {dir = SouthWest, x = -1, y = 1}
}

local function cavebotFunctionWarn(message, retries)
  if retries == 0 then
    warn(message)
  end
end

local function normalizeHealBotMode(value)
  value = tostring(value or ""):trim():lower()
  if value == "1" or value == "true" or value == "yes" or value == "on" or value == "enable" or value == "enabled" or value == "activar" or value == "prender" or value == "encender" then
    return "on"
  end
  if value == "0" or value == "false" or value == "no" or value == "off" or value == "disable" or value == "disabled" or value == "desactivar" or value == "apagar" then
    return "off"
  end
  if value == "toggle" or value == "switch" or value == "cambiar" then
    return "toggle"
  end
end

-- Versioned action values keep legacy minutes,delay routes and function helpers intact.
CaveBot.WaitStamina = {}
local waitStamina = CaveBot.WaitStamina

waitStamina.formatHours = function(minutes)
  return string.format("%02d:%02d", math.floor(minutes / 60), minutes % 60)
end

waitStamina.parseHours = function(text)
  text = tostring(text or ""):trim()
  local hours, minutes = text:match("^(%d%d?):(%d%d)$")
  if not hours and text:match("^%d%d?$") then hours, minutes = text, "0" end
  hours, minutes = tonumber(hours), tonumber(minutes)
  if not hours or not minutes or minutes > 59 then return nil end
  local total = hours * 60 + minutes
  if total > CAVEBOT_MAX_STAMINA_MINUTES then return nil end
  return total
end

local function validateWaitStamina(config, ranged)
  if type(config) ~= "table" then return nil, "Ajustes de stamina invalidos." end
  local minimum, checkMs = config.minimum, config.checkMs
  if type(minimum) ~= "number" or minimum ~= math.floor(minimum) or minimum < 0 or minimum > CAVEBOT_MAX_STAMINA_MINUTES then
    return nil, "Usa una stamina entre 00:00 y 42:00."
  end
  local maximum = minimum
  if ranged then maximum=config.maximum end
  if type(maximum) ~= "number" or maximum ~= math.floor(maximum) or maximum < minimum or maximum > CAVEBOT_MAX_STAMINA_MINUTES then
    return nil, "La maxima debe ser >= minima y no superar 42:00."
  end
  if type(checkMs) ~= "number" or checkMs ~= math.floor(checkMs) or checkMs < 100 or checkMs > 3600000 then
    return nil, "El intervalo debe ser de 0.1 a 3600 segundos."
  end
  if config.below ~= "wait" and config.below ~= "label" then return nil, "Accion con stamina baja invalida." end
  if config.ready ~= "next" and config.ready ~= "label" then return nil, "Accion con stamina suficiente invalida." end
  local belowLabel = type(config.belowLabel) == "string" and config.belowLabel:trim() or ""
  local readyLabel = type(config.readyLabel) == "string" and config.readyLabel:trim() or ""
  if config.below == "label" and belowLabel == "" or config.ready == "label" and readyLabel == "" then
    return nil, "Selecciona el label de destino."
  end
  local valid = {minimum=minimum, checkMs=checkMs, below=config.below, belowLabel=belowLabel, ready=config.ready, readyLabel=readyLabel}
  if ranged then valid.maximum=maximum end
  return valid
end

waitStamina.decode = function(value)
  value = tostring(value or "")
  if value:sub(1, 3) == "v2:" or value:sub(1, 3) == "v3:" then
    local ok, config = pcall(json.decode, value:sub(4))
    if not ok then return nil, "No se pudieron leer los ajustes de stamina." end
    return validateWaitStamina(config, value:sub(1, 3) == "v3:")
  end
  local data = string.split(value, ",")
  local minimum = tonumber(data[1] and data[1]:trim())
  if not minimum then return nil, "No se pudo leer la stamina minima." end
  local checkMs = tonumber(data[2] and data[2]:trim()) or 60000
  -- Normalize only the editor draft; the legacy executor below is unchanged.
  return {minimum=math.max(0, math.min(CAVEBOT_MAX_STAMINA_MINUTES, math.floor(minimum))),
    checkMs=math.max(100, math.min(3600000, math.floor(checkMs))), below="wait", belowLabel="", ready="next", readyLabel=""}
end

waitStamina.encode = function(config)
  local ranged = type(config) == "table" and config.maximum ~= nil
  local valid, message = validateWaitStamina(config, ranged)
  if not valid then return nil, message end
  return (ranged and "v3:" or "v2:") .. json.encode(valid)
end

waitStamina.describe = function(value)
  local config = waitStamina.decode(value)
  if not config then return "Ajustes invalidos (doble clic para editar)" end
  local low = config.below == "wait" and "esperar" or "label " .. config.belowLabel
  local ready = config.ready == "next" and "siguiente" or "label " .. config.readyLabel
  if config.maximum then
    return waitStamina.formatHours(config.minimum) .. " -> " .. waitStamina.formatHours(config.maximum) .. " | " .. low .. " / " .. ready
  end
  return waitStamina.formatHours(config.minimum) .. " | < " .. low .. " | >= " .. ready
end


waitStamina.defaults = function()
  return {minimum=2340, maximum=2520, checkMs=60000, below="wait", belowLabel="", ready="next", readyLabel=""}
end

-- One flag per route/waypoint in the active bot profile; no polling is added.
local function waitStaminaSlot()
  local list = CaveBot.actionList
  if not list then return end
  local widget = list:getFocusedChild() or list:getFirstChild()
  if not widget then return end
  local index = list:getChildIndex(widget)
  if not index then return end
  local route = CaveBot.getCurrentProfile and CaveBot.getCurrentProfile() or ""
  return tostring(route or ""), tostring(index)
end

waitStamina.isWaiting = function(value)
  local route, index = waitStaminaSlot()
  local states = storage._cavebotStaminaWaitRange
  local entries = type(states) == "table" and states[route] or nil
  local entry = type(entries) == "table" and entries[index] or nil
  return type(entry) == "table" and entry.value == value and entry.waiting == true
end

waitStamina.setWaiting = function(value, waiting)
  local route, index = waitStaminaSlot()
  if not route then return end
  local states = storage._cavebotStaminaWaitRange
  if waiting then
    if type(states) ~= "table" then states={}; storage._cavebotStaminaWaitRange=states end
    if type(states[route]) ~= "table" then states[route]={} end
    local entry = states[route][index]
    if type(entry) ~= "table" or entry.value ~= value or entry.waiting ~= true then
      states[route][index]={value=value, waiting=true}
    end
  elseif type(states) == "table" and type(states[route]) == "table" then
    states[route][index]=nil
    for _ in pairs(states[route]) do return end
    states[route]=nil
  end
end


-- Ordinary route movement is held only by the configured wait branch.
-- An emergency exit may pass this waypoint to reach its independent ZonaPZ.
local blockingValue,blockingConfig
waitStamina.isBlocking=function()
  if CaveBot.Flee and CaveBot.Flee.isEscaping()then return false end
  if CaveBot.isOn and not CaveBot.isOn()then return false end
  local list=CaveBot.actionList
  local row=list and(list:getFocusedChild()or list:getFirstChild())
  if not row or row.action~='waitstamina'then return false end
  if blockingValue~=row.value then blockingValue=row.value;blockingConfig=waitStamina.decode(row.value)end
  local config=blockingConfig
  local current=type(stamina)=='function'and stamina()or nil
  if not config or type(current)~='number'or current<0 or current~=current then return true end
  local waiting=current<config.minimum
  if config.maximum then
    if current>=config.maximum then waiting=false
    elseif current<config.minimum then waiting=true
    else waiting=waitStamina.isWaiting(row.value)end
  end
  return waiting and config.below=='wait'
end

CaveBot.FunctionHelpers.waitStamina = function(minMinutes, waitMs)
  minMinutes = tonumber(minMinutes)
  waitMs = tonumber(waitMs) or 60000

  if not minMinutes then
    warn("CaveBot[waitStamina]: minMinutes must be a number")
    return false
  end
  if minMinutes > CAVEBOT_MAX_STAMINA_MINUTES then
    if storage._cavebotWaitStaminaMaxWarn ~= minMinutes then
      warn("CaveBot[waitStamina]: max stamina is 2520 minutes (42h), clamping " .. minMinutes .. " to 2520")
      storage._cavebotWaitStaminaMaxWarn = minMinutes
    end
    minMinutes = CAVEBOT_MAX_STAMINA_MINUTES
  end
  if type(stamina) ~= "function" then
    warn("CaveBot[waitStamina]: stamina() is not available")
    return false
  end

  local currentStamina = stamina()
  if currentStamina and currentStamina >= minMinutes then
    return true
  end

  CaveBot.delay(waitMs)
  return "retry"
end

CaveBot.FunctionHelpers.setHealBot = function(mode)
  mode = normalizeHealBotMode(mode)
  if not mode then
    warn("CaveBot[setHealBot]: use on, off or toggle")
    return false
  end
  if not HealBot then
    warn("CaveBot[setHealBot]: HealBot is not available")
    return false
  end

  if mode == "toggle" then
    if not HealBot.isOn then
      warn("CaveBot[setHealBot]: HealBot state is not available")
      return false
    end
    mode = HealBot.isOn() and "off" or "on"
  end

  if mode == "on" then
    if HealBot.setOnSilent then
      HealBot.setOnSilent()
    elseif HealBot.setOn then
      HealBot.setOn()
    else
      warn("CaveBot[setHealBot]: HealBot setOn is not available")
      return false
    end
    return true
  end

  if HealBot.setOffSilent then
    HealBot.setOffSilent()
  elseif HealBot.setOff then
    HealBot.setOff()
  else
    warn("CaveBot[setHealBot]: HealBot setOff is not available")
    return false
  end
  return true
end

CaveBot.FunctionHelpers.stepDirection = function(directionName, retries, maxRetries, waitMs)
  directionName = tostring(directionName or ""):trim():lower()
  local step = cavebotStepDirections[directionName]
  maxRetries = tonumber(maxRetries)
  if maxRetries == nil then
    maxRetries = 30
  end
  waitMs = tonumber(waitMs) or 200

  if not step then
    cavebotFunctionWarn("CaveBot[stepDirection]: invalid direction '" .. directionName .. "'", retries)
    return false
  end

  local key = "_cavebotStepDirection"
  local playerPos = player:getPosition()

  if retries == 0 or not storage[key] or storage[key].direction ~= directionName or not storage[key].target then
    storage[key] = {
      direction = directionName,
      target = {
        x = playerPos.x + step.x,
        y = playerPos.y + step.y,
        z = playerPos.z
      }
    }
  end

  local target = storage[key].target
  if playerPos.x == target.x and playerPos.y == target.y and playerPos.z == target.z then
    storage[key] = nil
    return true
  end

  if maxRetries and maxRetries > 0 and retries >= maxRetries then
    storage[key] = nil
    cavebotFunctionWarn("CaveBot[stepDirection]: could not step to " .. directionName, 0)
    return false
  end

  if CaveBot.protectStep and not CaveBot.protectStep(step.dir) then
    storage[key]=nil -- Resume this direction from the position reached after the escape.
    return "retry"
  end
  safeBotWalk(step.dir)
  CaveBot.delay(waitMs)
  return "retry"
end

CaveBot.registerAction("label", "yellow", function(value, retries, prev)
  vBot.lastLabel = value
  return true
end)

CaveBot.registerAction("gotolabel", "#FFFF55", function(value, retries, prev)
  return CaveBot.gotoLabel(value) 
end)

CaveBot.registerAction("delay", "#AAAAAA", function(value, retries, prev)
  if retries == 0 then
    local data = string.split(value, ",")
    local val = tonumber(data[1]:trim())
    local random
    local final


    if #data == 2 then
      random = tonumber(data[2]:trim())
    end

    if random then
      local diff = (val/100) * random
      local min = val - diff
      local max = val + diff
      final = math.random(min, max)
    end
    final = final or val

    CaveBot.delay(final) 
    return "retry"
  end
  return true
end)

CaveBot.registerAction("waitstamina", "#55DDFF", function(value, retries, prev)
  if value:sub(1, 3) ~= "v2:" and value:sub(1, 3) ~= "v3:" then
    local data = string.split(value, ",")
    local minMinutes = tonumber(data[1] and data[1]:trim())
    local waitMs = tonumber(data[2] and data[2]:trim()) or 60000

    return CaveBot.FunctionHelpers.waitStamina(minMinutes, waitMs)
  end

  local config, message = CaveBot.WaitStamina.decode(value)
  local function hold(reason)
    if reason and retries == 0 then warn("CaveBot[wait stamina]: " .. reason) end
    CaveBot.delay(config and config.checkMs or 60000)
    return "retry"
  end
  if not config then return hold(message) end
  local current = type(stamina) == "function" and stamina() or nil
  if type(current) ~= "number" or current < 0 or current ~= current then
    return hold("No se pudo leer la stamina; se mantiene este waypoint.")
  end
  local sufficient = current >= config.minimum
  if config.maximum then
    local waiting = CaveBot.WaitStamina.isWaiting(value)
    if current < config.minimum then
      waiting=true
    elseif current >= config.maximum then
      waiting=false
    end
    CaveBot.WaitStamina.setWaiting(value, waiting)
    sufficient=not waiting
  end
  local mode = sufficient and config.ready or config.below
  if mode == "next" then return true end
  if mode == "wait" then return hold() end
  local label = sufficient and config.readyLabel or config.belowLabel
  if CaveBot.gotoLabel(label) then return true end
  return hold("No existe el label '" .. label .. "'; se mantiene este waypoint.")
end)

-- A route marker: only the emergency controller navigates to this point.
CaveBot.registerAction("zonapz", "#50E6C0", function(value)
  if not CaveBot.FleeTools.zonePosition(value)then
    warn('CaveBot[ZonaPZ]: usa coordenadas x,y,z validas.');return false
  end
  return true
end)

CaveBot.registerAction("stepdirection", "#55FF88", function(value, retries, prev)
  local data = string.split(value, ",")
  local direction = data[1] and data[1]:trim()
  local maxRetries = tonumber(data[2] and data[2]:trim()) or 30
  local waitMs = tonumber(data[3] and data[3]:trim()) or 200

  return CaveBot.FunctionHelpers.stepDirection(direction, retries, maxRetries, waitMs)
end)

local function parseSetProfileValue(value)
  value = tostring(value or ""):trim()
  local random = false

  if value:sub(1, 7):lower() == "random:" then
    random = true
    value = value:sub(8)
  end

  local profiles = {}
  for profile in value:gmatch("[^,]+") do
    profile = profile:trim()
    if profile ~= "" then
      table.insert(profiles, profile)
    end
  end

  if #profiles > 1 then
    random = true
  end

  return profiles, random
end

CaveBot.registerAction("setprofile", "#66CCFF", function(value, retries, prev)
  local profiles, random = parseSetProfileValue(value)
  if #profiles == 0 then
    warn("CaveBot[setprofile]: profile name is empty")
    return false
  end

  for _, candidate in ipairs(profiles) do
    if not Config.fileExists("cavebot_configs", candidate) then
      warn("CaveBot[setprofile]: profile does not exist: " .. candidate)
      return false
    end
  end

  local profile = profiles[1]
  if random and #profiles > 1 then
    profile = profiles[math.random(1, #profiles)]
  end

  CaveBot._profileChangedByAction = true
  CaveBot.setCurrentProfile(profile)
  return true
end)

CaveBot.registerAction("follow", "#FF8400", function(value, retries, prev)
  local c = getCreatureByName(value)
  if not c then
    print("CaveBot[follow]: can't find creature to follow")
    return false
  end
  local cpos = c:getPosition()
  local pos = pos()
  if getDistanceBetween(cpos, pos) < 2 then
    g_game.cancelFollow()
    return true
  else
    follow(c)
    delay(200)
    return "retry"
  end
end)

CaveBot.registerAction("function", "red", function(value, retries, prev)
  local prefix = "local retries = " .. retries .. "\nlocal prev = " .. tostring(prev) .. "\nlocal delay = CaveBot.delay\nlocal gotoLabel = CaveBot.gotoLabel\n"
  prefix = prefix .. "local waitStamina = CaveBot.FunctionHelpers.waitStamina\n"
  prefix = prefix .. "local setHealBot = CaveBot.FunctionHelpers.setHealBot\n"
  prefix = prefix .. "local stepDirection = function(direction, maxRetries, waitMs) return CaveBot.FunctionHelpers.stepDirection(direction, retries, maxRetries, waitMs) end\n"
  prefix = prefix .. "local macro = function() warn('Macros inside cavebot functions are not allowed') end\n"
  for extension, callbacks in pairs(CaveBot.Extensions) do
    prefix = prefix .. "local " .. extension .. " = CaveBot.Extensions." .. extension .. "\n"
  end
  local status, result = pcall(function() 
    return assert(load(prefix .. value, "cavebot_function"))()
  end)
  if not status then
    warn("warn in cavebot function:\n" .. result)
    return false
  end  
  return result
end)

CaveBot.registerAction("goto", "green", function(value, retries, prev)
  if retries==0 then CaveBot._safetySteppedGoto=false end
  local pos = regexMatch(value, "\\s*([0-9]+)\\s*,\\s*([0-9]+)\\s*,\\s*([0-9]+),?\\s*([0-9]?)")
  if not pos[1] then
    warn("Invalid cavebot goto action value. It should be position (x,y,z), is: " .. value)
    return false
  end

  -- reset pathfinder
  nextPosF = nil
  nextPos = nil
  
  if CaveBot.Config.get("mapClick") and not CaveBot._safetySteppedGoto then
    if retries >= 5 then
      noPath = noPath + 1
      pathfinder()
      return false -- tried 5 times, can't get there
    end
  else
    if retries >= 100 then
      noPath = noPath + 1
      pathfinder()
      return false -- tried 100 times, can't get there
    end  
  end

  local precision = tonumber(pos[1][5])
  pos = {x=tonumber(pos[1][2]), y=tonumber(pos[1][3]), z=tonumber(pos[1][4])}  
  local playerPos = player:getPosition()
  if pos.z ~= playerPos.z then 
    noPath = noPath + 1
    pathfinder()
    return false -- different floor
  end

  local maxDist = tonumber(storage.extras.gotoMaxDistance) or 24
  local directDistance = math.abs(pos.x-playerPos.x) + math.abs(pos.y-playerPos.y)
  -- Preserve the configured waypoint limit without making a short blocked step
  -- explore the full radius on every retry.
  local pathSearchDist = math.min(maxDist, math.max(20, directDistance + 10))
  
  if directDistance > maxDist then
    noPath = noPath + 1
    pathfinder()
    return false -- too far way
  end

  local minimapColor = g_map.getMinimapColor(pos)
  local stairs = (minimapColor >= 210 and minimapColor <= 213)
  
  if stairs then
    if math.abs(pos.x-playerPos.x) == 0 and math.abs(pos.y-playerPos.y) <= 0 then
      noPath = 0
      return true -- already at position
    end
  elseif math.abs(pos.x-playerPos.x) == 0 and math.abs(pos.y-playerPos.y) <= (precision or 1) then
      noPath = 0
      return true -- already at position
  end

  -- Fast path: try to walk before running the heavier diagnostic path checks.
  -- The old order calculated multiple paths even when the first walk attempt could succeed.
  if not CaveBot.Config.get("ignoreFields") and CaveBot.walkTo(pos, 40) then
    return "retry"
  end
  
  if CaveBot.walkTo(pos, pathSearchDist, { ignoreNonPathable = true, allowUnseen = true, allowOnlyVisibleTiles = false }) then
    return "retry"
  end

  -- check if there's a path to that place, ignore creatures and fields
  local path = findPath(playerPos, pos, pathSearchDist, { ignoreNonPathable = true, precision = 1, ignoreCreatures = true, allowUnseen = true, allowOnlyVisibleTiles = false  })
  if not path then
    if breakFurniture(pos, storage.extras.machete) then
      CaveBot.delay(1000)
      retries = 0
      return "retry"
    end
    noPath = noPath + 1
    pathfinder()
    return false -- there's no way
  end

  -- check if there's a path to destination but consider Creatures (attack only if trapped)
  local path2 = findPath(playerPos, pos, pathSearchDist, { ignoreNonPathable = true, precision = 1 })
  if not path2 then
    local foundMonster = false
    for i, dir in ipairs(path) do
      local dirs = modPos(dir)
      nextPos = nextPos or playerPos
      nextPos.x = nextPos.x + dirs[1]
      nextPos.y = nextPos.y + dirs[2]
  
      local tile = g_map.getTile(nextPos)
      if tile then
          if tileHasCreature(tile) then
              local creature = tile:getCreatures()[1]
              local hppc = creature:getHealthPercent()
              if creature:isMonster() and (hppc and hppc > 0) and (oldTibia or creature:getType() < 3) then
                  -- real blocking creature can not meet those conditions - ie. it could be player, so just in case check if the next creature is reachable
                  local path = findPath(playerPos, creature:getPosition(), 7, { ignoreNonPathable = true, precision = 1 }) 
                  if path then
                      foundMonster = true
                      if g_game.getAttackingCreature() ~= creature then
                        if distanceFromPlayer(creature:getPosition()) > 3 then
                          CaveBot.walkTo(creature:getPosition(), 7, { ignoreNonPathable = true, precision = 1 })
                        else
                          attack(creature)
                        end
                      end
                      g_game.setChaseMode(1)
                      CaveBot.delay(100)
                      retries = 0 -- reset retries, we are trying to unclog the cavebot
                      break
                  end
              end
          end
      end
    end

    if not foundMonster then
      foundMonster = false
      return false -- no other way
    end
  end
  if retries >= 3 then
    -- try to lower precision, find something close to final position
    local precison = retries - 1
    if stairs then
      precison = 0
    end
    if CaveBot.walkTo(pos, 50, { ignoreNonPathable = true, precision = precison, allowUnseen = true, allowOnlyVisibleTiles = false }) then
      return "retry"
    end    
  end
  
  if not CaveBot.Config.get("mapClick") and retries >= 5 then
    noPath = noPath + 1
    pathfinder()
    return false
  end
  
  if CaveBot.Config.get("skipBlocked") then
    noPath = noPath + 1
    pathfinder()
    return false
  end

  -- everything else failed, try to walk ignoring creatures, maybe will work
  CaveBot.walkTo(pos, pathSearchDist, { ignoreNonPathable = true, precision = 1, ignoreCreatures = true, allowUnseen = true, allowOnlyVisibleTiles = false })
  return "retry"
end)

-- Recorded stair entry: approach the pre-step tile, take the actual observed
-- direction, then require the expected floor. Ordinary goto cannot do this
-- because the server can skip the stair tile in its position notifications.
local recordedFloorChange = nil
CaveBot.registerAction("floorchange", "#55DDFF", function(value, retries, prev)
  local ox, oy, oz, ex, ey, ax, ay, az = tostring(value):match(
    '^%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*$')
  ox, oy, oz, ex, ey, ax, ay, az = tonumber(ox), tonumber(oy), tonumber(oz), tonumber(ex), tonumber(ey), tonumber(ax), tonumber(ay), tonumber(az)
  local function stop(reason)
    recordedFloorChange = nil
    CaveBot.setOff()
    warn('[CaveBot escalera] ' .. reason)
    return false
  end
  if not az or ox >= 65535 or oy >= 65535 or ex >= 65535 or ey >= 65535 or
    ax >= 65535 or ay >= 65535 or oz > 15 or az > 15 or math.abs(az - oz) ~= 1 then
    return stop('Punto invalido; vuelve a grabar este tramo.')
  end
  local dx, dy = ex - ox, ey - oy
  if math.max(math.abs(dx), math.abs(dy)) ~= 1 then
    return stop('La entrada debe estar a un paso del punto anterior.')
  end
  local position = player and player:getPosition()
  if not position then return stop('No hay posicion del personaje.') end
  if position.z == az and math.max(math.abs(position.x - ax), math.abs(position.y - ay)) <= 3 then
    recordedFloorChange = nil
    return true
  end
  if position.z ~= oz then return stop('Llegada inesperada; revisa este tramo de la ruta.') end
  local time = tonumber(now) or os.time() * 1000
  if retries == 0 or not recordedFloorChange or recordedFloorChange.value ~= value then
    recordedFloorChange = {value = value, started = time, attempts = 0}
  end
  local state = recordedFloorChange
  if retries >= 60 or time - state.started >= 30000 then
    return stop('No se confirmo el cambio de piso; CaveBot se detuvo.')
  end
  -- A sent step may land briefly on the entry tile before the floor update.
  -- Wait there; never walk back or keep advancing on the wrong floor.
  if position.x ~= ox or position.y ~= oy then
    if state.attempts > 0 then
      if time - state.lastStep >= 5000 then return stop('El paso no cambio de piso.') end
      CaveBot.delay(500)
      return 'retry'
    end
    local maxDist = tonumber(storage.extras.gotoMaxDistance) or 24
    if math.max(math.abs(position.x - ox), math.abs(position.y - oy)) > maxDist then
      return stop('El punto de entrada esta demasiado lejos.')
    end
    if CaveBot.walkTo({x = ox, y = oy, z = oz}, maxDist,
      {precision = 0, ignoreNonPathable = true, allowUnseen = true, allowOnlyVisibleTiles = false}) then
      return 'retry'
    end
    return stop('No se puede alcanzar el punto anterior a la escalera.')
  end
  if state.nextStep and time < state.nextStep then
    CaveBot.delay(state.nextStep - time)
    return 'retry'
  end
  if state.attempts >= 8 then return stop('La escalera no respondio; CaveBot se detuvo.') end
  local directions = {{NorthWest, North, NorthEast}, {West, nil, East}, {SouthWest, South, SouthEast}}
  local direction = directions[dy + 2][dx + 2]
  if CaveBot.protectStep and not CaveBot.protectStep(direction) then return 'retry' end
  state.attempts = state.attempts + 1
  state.lastStep = time
  safeBotWalk(direction)
  local stepDuration = 0
  pcall(function() stepDuration = tonumber(player:getStepDuration(false, direction)) or 0 end)
  local wait = math.max(500, stepDuration + (tonumber(CaveBot.Config.get('ping')) or 0) + 150)
  state.nextStep = time + wait
  CaveBot.delay(wait)
  return 'retry'
end)

CaveBot.registerAction("use", "#FFB272", function(value, retries, prev)
  local pos = regexMatch(value, "\\s*([0-9]+)\\s*,\\s*([0-9]+)\\s*,\\s*([0-9]+)")
  if not pos[1] then
    local itemid = tonumber(value)
    if not itemid then
      warn("Invalid cavebot use action value. It should be (x,y,z) or item id, is: " .. value)
      return false
    end
    use(itemid)
    return true
  end

  pos = {x=tonumber(pos[1][2]), y=tonumber(pos[1][3]), z=tonumber(pos[1][4])}  
  local playerPos = player:getPosition()
  if pos.z ~= playerPos.z then 
    return false -- different floor
  end

  if math.max(math.abs(pos.x-playerPos.x), math.abs(pos.y-playerPos.y)) > 7 then
    return false -- too far way
  end

  local tile = g_map.getTile(pos)
  if not tile then
    return false
  end

  local topThing = tile:getTopUseThing()
  if not topThing then
    return false
  end

  use(topThing)
  CaveBot.delay(CaveBot.Config.get("useDelay") + CaveBot.Config.get("ping"))
  return true
end)

CaveBot.registerAction("usewith", "#EEB292", function(value, retries, prev)
  local pos = regexMatch(value, "\\s*([0-9]+)\\s*,\\s*([0-9]+)\\s*,\\s*([0-9]+)\\s*,\\s*([0-9]+)")
  if not pos[1] then
    if not itemid then
      warn("Invalid cavebot usewith action value. It should be (itemid,x,y,z) or item id, is: " .. value)
      return false
    end
    use(itemid)
    return true
  end

  local itemid = tonumber(pos[1][2])
  pos = {x=tonumber(pos[1][3]), y=tonumber(pos[1][4]), z=tonumber(pos[1][5])}  
  local playerPos = player:getPosition()
  if pos.z ~= playerPos.z then 
    return false -- different floor
  end

  if math.max(math.abs(pos.x-playerPos.x), math.abs(pos.y-playerPos.y)) > 7 then
    return false -- too far way
  end

  local tile = g_map.getTile(pos)
  if not tile then
    return false
  end

  local topThing = tile:getTopUseThing()
  if not topThing then
    return false
  end

  usewith(itemid, topThing)
  CaveBot.delay(CaveBot.Config.get("useDelay") + CaveBot.Config.get("ping"))
  return true
end)

CaveBot.registerAction("say", "#FF55FF", function(value, retries, prev)
  say(value)
  return true
end)
CaveBot.registerAction("npcsay", "#FF55FF", function(value, retries, prev)
  CaveBot.NpcSay(value)
  return true
end)
