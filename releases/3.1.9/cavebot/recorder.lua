-- auto recording for cavebot
CaveBot.Recorder = {}

local isEnabled = nil
local lastPos = nil
local lastTransition = nil
local lastInteraction = nil

local function copy(pos)
  return {x=pos.x,y=pos.y,z=pos.z}
end
local function valid(pos)
  return type(pos)=='table' and type(pos.x)=='number' and type(pos.y)=='number' and type(pos.z)=='number' and pos.x~=0xFFFF
end
local function same(a,b)
  return a and b and a.x==b.x and a.y==b.y and a.z==b.z
end
local function stamp()
  return type(now)=='number' and now or 0
end
local function transitionUse(pos,toolId,targetId)
  local color=g_map and type(g_map.getMinimapColor)=='function' and tonumber(g_map.getMinimapColor(pos)) or 0
  if color and color>=210 and color<=213 then return true end
  local extras=storage and storage.extras or {}
  local ids
  if toolId==(extras.rope or 3003) then ids=Global and Global.ropeIds
  elseif toolId==(extras.shovel or 3457) then ids=Global and Global.shovelIds end
  for _,id in ipairs(ids or {})do if id==targetId then return true end end
  return false
end
local function floorLabel(newPos,oldPos)
  local used={}
  for _,row in ipairs(CaveBot.actionList and CaveBot.actionList:getChildren() or {}) do
    if row.action=='label' then used[tostring(row.value):lower()]=true end
  end
  local direction=newPos.z<oldPos.z and 'Subir' or 'Bajar'
  local index,name=1
  repeat
    name=string.format('Auto_%s_%03d_Piso_%d',direction,index,newPos.z)
    index=index+1
  until not used[name:lower()]
  CaveBot.addAction('label',name,true)
end

local function setup()
  local function addPosition(pos)
    CaveBot.addAction("goto", pos.x .. "," .. pos.y .. "," .. pos.z, true)
    lastPos = copy(pos)
  end
  local function addStairs(pos)
    CaveBot.addAction("goto", pos.x .. "," .. pos.y .. "," .. pos.z .. ",0", true)
    lastPos = copy(pos)
  end

  onPlayerPositionChange(function(newPos, oldPos)
    if CaveBot.isOn() or not isEnabled or not valid(newPos) or not valid(oldPos) then return end
    if newPos.z~=oldPos.z then
      local transition=oldPos.x..','..oldPos.y..','..oldPos.z..'>'..newPos.x..','..newPos.y..','..newPos.z
      if transition==lastTransition and same(lastPos,newPos) then return end
      -- A recorded ladder/tool use already performs this crossing. Do not
      -- append a return to the old floor after that use action.
      local interaction=lastInteraction and stamp()-lastInteraction.at<=2000 and
        lastInteraction.pos.z==oldPos.z and
        math.max(math.abs(lastInteraction.pos.x-oldPos.x),math.abs(lastInteraction.pos.y-oldPos.y))<=1
      if not interaction then addStairs(oldPos) end
      floorLabel(newPos,oldPos)
      addPosition(newPos)
      lastTransition=transition;lastInteraction=nil
    elseif not lastPos then
      -- first step
      addPosition(oldPos)
    elseif math.abs(oldPos.x - newPos.x) > 1 or math.abs(oldPos.y - newPos.y) > 1 then
      -- stairs/teleport
      addStairs(oldPos)
      addPosition(newPos)
    elseif math.max(math.abs(lastPos.x - newPos.x), math.abs(lastPos.y - newPos.y)) > 5 then
      -- 5 steps from last pos
      addPosition(newPos)
    end
    if newPos.z==oldPos.z then
      lastTransition=nil
      if not same(newPos,oldPos) then lastInteraction=nil end
    end
  end)
  
  onUse(function(pos, itemId, stackPos, subType)
    if CaveBot.isOn() or not isEnabled then return end
    if valid(pos) then
      lastPos = copy(pos)
      lastInteraction=transitionUse(pos) and {pos=copy(pos),at=stamp()} or nil
      CaveBot.addAction("use", pos.x .. "," .. pos.y .. "," .. pos.z, true)
    end
  end)
  
  onUseWith(function(pos, itemId, target, subType)
    if CaveBot.isOn() or not isEnabled then return end
    if not target or not target:isItem() then return end
    local targetPos = target:getPosition()
    if not valid(targetPos) then return end
    lastPos = copy(targetPos)
    lastInteraction=transitionUse(targetPos,itemId,target.getId and target:getId()) and {pos=copy(targetPos),at=stamp()} or nil
    CaveBot.addAction("usewith", itemId .. "," .. targetPos.x .. "," .. targetPos.y .. "," .. targetPos.z, true)
  end)
end

CaveBot.Recorder.isOn = function()
  return isEnabled
end

CaveBot.Recorder.enable = function()
  CaveBot.setOff()
  if isEnabled == nil then
    setup()
  end
  -- CaveBot.Editor.ui.autoRecording:setOn(true)
  isEnabled = true
  lastPos = nil
  lastTransition = nil
  lastInteraction = nil
end

CaveBot.Recorder.disable = function()
  if isEnabled == true then
    isEnabled = false
  end
  -- CaveBot.Editor.ui.autoRecording:setOn(false)
  CaveBot.save()
end
