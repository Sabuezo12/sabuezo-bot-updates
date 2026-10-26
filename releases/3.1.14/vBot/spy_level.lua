-- config

local keyUp = "="
local keyDown = nil
setDefaultTab("Tools")
storage.helperSpyLevel = storage.helperSpyLevel or {}
if storage.helperSpyLevel.enabled == nil then storage.helperSpyLevel.enabled = true end
if storage.helperSpyLevel.up ~= nil then keyUp = storage.helperSpyLevel.up end
if storage.helperSpyLevel.down ~= nil then keyDown = storage.helperSpyLevel.down end
SpyLevelBridge = {
  getConfig = function() return {up = keyUp, down = keyDown} end,
  applyConfig = function(up, down)
    keyUp = tostring(up or "")
    keyDown = tostring(down or "")
    storage.helperSpyLevel.up, storage.helperSpyLevel.down = keyUp, keyDown
  end
}


-- script

local lockedLevel = pos().z
SpyLevelBridge.isOn = function() return storage.helperSpyLevel.enabled == true end
SpyLevelBridge.setOn = function() storage.helperSpyLevel.enabled = true end
SpyLevelBridge.setOff = function()
    storage.helperSpyLevel.enabled = false
    lockedLevel = pos().z
    modules.game_interface.getMapPanel():unlockVisibleFloor()
end

onPlayerPositionChange(function(newPos, oldPos)
    lockedLevel = pos().z
    modules.game_interface.getMapPanel():unlockVisibleFloor()
end)

local function changeFloor(delta)
    local map = modules and modules.game_interface and modules.game_interface.getMapPanel()
    if not map or not map.lockVisibleFloor then return false end
    local level = math.max(0,math.min(15,lockedLevel + delta))
    if level == lockedLevel then return false end
    lockedLevel = level
    map:lockVisibleFloor(lockedLevel)
    return true
end
SpyLevelBridge.stepUp = function() return changeFloor(-1) end
SpyLevelBridge.stepDown = function() return changeFloor(1) end
SpyLevelBridge.getFloor = function() return lockedLevel end

onKeyPress(function(keys)
    if not SpyLevelBridge.isOn() then return end
    if keyDown and keys == keyDown then
        SpyLevelBridge.stepDown()
    elseif keys == keyUp then
        SpyLevelBridge.stepUp()
    end
end)
