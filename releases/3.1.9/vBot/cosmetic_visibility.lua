-- Local visibility of pet attachments; outfits and auras stay unchanged.
-- Imported as editable code by the In-Game Script Editor.
local manager = vBot and vBot.InGameScriptManager
if not manager or type(manager.registerCleanup) ~= "function" then return end

local hidden = {}
local disposed = false
local playerTypes = setmetatable({}, {__mode = "k"})
local queued, pending = {}, {}
local queueHead, queueTail = 1, 0
local workerScheduled = false

local function isPlayerCreature(creature)
  if not creature then return false end
  if playerTypes[creature] ~= nil then return playerTypes[creature] end
  local ok, value = pcall(function() return creature:isPlayer() end)
  if not ok then return false end
  playerTypes[creature] = value == true
  return value == true
end

local function attachedEffects(creature)
  local ok, effects = pcall(function() return creature:getAttachedEffects() end)
  return ok and type(effects) == "table" and effects or {}
end

local function restoreEffect(creature, effect, record)
  local ok, restored = pcall(function()
    if creature:detachEffect(effect) then
      creature:attachEffect(record.original)
      return true
    end
    return false
  end)
  if not ok or not restored then pcall(function() effect:setOpacity(record.opacity) end) end
end

local function restoreCreature(creature)
  pending[creature] = nil
  local records = hidden[creature]
  if not records then return end
  local attached = {}
  for _, effect in ipairs(attachedEffects(creature)) do attached[effect] = true end
  for effect, record in pairs(records) do
    -- A server removal must not resurrect an old cosmetic when disabling this.
    if attached[effect] then
      restoreEffect(creature, effect, record)
    end
  end
  hidden[creature] = nil
end

local function restoreAll()
  local creatures = {}
  for creature in pairs(hidden) do creatures[#creatures + 1] = creature end
  for _, creature in ipairs(creatures) do restoreCreature(creature) end
end

local function isCosmetic(effect, wings, aura)
  local ok, result, id = pcall(function()
    if effect:isTransform() or effect:isHidedOwner() then return false end
    local effectId = effect:getId()
    if wings > 0 and effectId == wings then return false end
    if aura > 0 and effectId == aura then return false end
    local name = tostring(effect:getName() or ""):lower()
    if name:find("wing", 1, true) or name:find("asas", 1, true) then return false end
    if name:find("aura", 1, true) then return false end
    -- Timed or finite-loop attachments can be combat effects.
    return effect:getDuration() == 0 and (effect:isPermanent() or effect:getLoop() < 0), effectId
  end)
  return ok and result, id
end

local function hideCreature(creature)
  if disposed or not creature then return end
  if not isPlayerCreature(creature) then return end
  local effects = attachedEffects(creature)
  if #effects == 0 then
    hidden[creature] = nil
    return
  end
  local okOutfit, outfit = pcall(function() return creature:getOutfit() end)
  local wings = okOutfit and type(outfit) == "table" and tonumber(outfit.wings) or 0
  local aura = okOutfit and type(outfit) == "table" and tonumber(outfit.aura) or 0
  local records = hidden[creature] or {}
  local present = {}
  for _, effect in ipairs(effects) do
    present[effect] = true
    local record = records[effect]
    -- The outfit can start using an attachment as its aura or wings later.
    if record and ((wings and wings > 0 and record.id == wings) or
        (aura and aura > 0 and record.id == aura)) then
      restoreEffect(creature, effect, record)
      records[effect] = nil
    else
      local cosmetic, id = record ~= nil, record and record.id
      if not record then cosmetic, id = isCosmetic(effect, wings or 0, aura or 0) end
      if cosmetic then
        if not record then
          local ok, original, opacity = pcall(function() return effect:clone(), effect:getOpacity() end)
          if ok and original and type(opacity) == "number" then
            record = {original = original, opacity = opacity, id = id}
            records[effect] = record
          end
        end
        if record then
          local ok, opacity = pcall(function() return effect:getOpacity() end)
          if not record.masked or not ok or opacity ~= 0 then
            local masked = pcall(function()
              -- Keep the original clone for restoration; avoid repeated writes
              -- while the same attachment is already invisible.
              effect:setFade(0, 0, 0)
              effect:setOpacity(0)
            end)
            record.masked = masked
          end
        end
      end
    end
  end
  local hasRecords = false
  for effect in pairs(records) do
    if not present[effect] then
      records[effect] = nil
    else
      hasRecords = true
    end
  end
  hidden[creature] = hasRecords and records or nil
end

local drainQueue
local function scheduleWorker()
  if workerScheduled or disposed or type(schedule) ~= "function" then return end
  workerScheduled = true
  schedule(10, drainQueue)
end

local function enqueueCreature(creature)
  if disposed or not isPlayerCreature(creature) or pending[creature] then return end
  queueTail = queueTail+1
  queued[queueTail], pending[creature] = creature, true
  scheduleWorker()
end

drainQueue = function()
  workerScheduled = false
  if disposed then return end
  -- A town/teleport appearance burst must not process every player at once.
  for _ = 1, 4 do
    if queueHead > queueTail then break end
    local creature = queued[queueHead]
    queued[queueHead], queueHead = nil, queueHead+1
    if pending[creature] then
      pending[creature] = nil
      hideCreature(creature)
    end
  end
  if queueHead > queueTail then
    queued, queueHead, queueTail = {}, 1, 0
  else
    scheduleWorker()
  end
end

local function refresh()
  if disposed then return end
  local ok, spectators = pcall(function()
    local localPlayer = g_game.getLocalPlayer()
    if not localPlayer then return {} end
    return g_map.getSpectators(localPlayer:getPosition(), false)
  end)
  if not ok or type(spectators) ~= "table" then return end
  local visible = {}
  for _, creature in ipairs(spectators) do
    visible[creature] = true
    enqueueCreature(creature)
  end
  local gone = {}
  for creature in pairs(pending) do
    if not visible[creature] then pending[creature] = nil end
  end
  for creature in pairs(hidden) do
    if not visible[creature] then gone[#gone + 1] = creature end
  end
  for _, creature in ipairs(gone) do restoreCreature(creature) end
end

local function cleanup()
  if disposed then return end
  disposed = true
  queued, pending, playerTypes = {}, {}, setmetatable({}, {__mode = "k"})
  queueHead, queueTail, workerScheduled = 1, 0, false
  restoreAll()
end
if not manager.registerCleanup(cleanup) then return end

onCreatureAppear(enqueueCreature)
onCreatureDisappear(restoreCreature)
macro(250, function()
  refresh()
  if type(schedule) ~= "function" then drainQueue() end
end)
refresh()
