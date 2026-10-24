-- Keep a ranged target until its next autoattack actually leaves the player.
-- No elapsed-time estimate: spell/rune missiles must not release this hold.
TargetBot.ShotLock = {}
local S = TargetBot.ShotLock
local targetId, fired, lastPosition, previousPosition, observedAt, previousAt
local projectiles = {
  [1]=true, [2]=true, [3]=true, [6]=true, [7]=true, [8]=true, [9]=true,
  [10]=true, [12]=true, [13]=true, [14]=true, [16]=true, [17]=true,
  [18]=true, [19]=true, [20]=true, [21]=true, [22]=true, [23]=true,
  [24]=true, [33]=true, [34]=true, [35]=true, [40]=true, [44]=true,
  [45]=true, [48]=true, [49]=true, [50]=true, [51]=true, [53]=true,
  [54]=true, [56]=true, [57]=true, [58]=true, [59]=true
}

local function samePosition(a,b)
  return a and b and a.x==b.x and a.y==b.y and a.z==b.z
end

local function observe(position)
  if not samePosition(position,lastPosition) then
    previousPosition=lastPosition
    previousAt=observedAt
    lastPosition=position and {x=position.x,y=position.y,z=position.z} or nil
  end
  observedAt=now
end

function S.reset()
  targetId,fired,lastPosition,previousPosition,observedAt,previousAt=nil,false,nil,nil,nil,nil
end

function S.applies(config)
  if type(onMissle)~='function' or not config then return false end
  if config.diamondArrows or config.burstArrows then return true end
  -- MythicOT's client vocation IDs, also used by vBot/extras.lua.
  local id=type(voc)=='function' and voc() or nil
  return id==2 or id==12
end

local function prime(params)
  S.reset()
  if params and S.applies(params.config) then
    targetId=params.creature:getId()
    observe(params.creature:getPosition())
  end
  return params
end

function S.choose(best,currentParams)
  local current=g_game.getAttackingCreature()
  local config=currentParams and currentParams.config
  local position=current and current:getPosition()
  local origin=player and player:getPosition()
  local hp=current and current:getHealthPercent()
  -- Safety, range and disappearance can always release a target. Never hold
  -- one that cannot be shot just to wait for a projectile that cannot arrive.
  if not current or not currentParams or currentParams.creature~=current or
      not S.applies(config) or currentParams.priority<=0 or not current:isMonster() or
      not hp or hp<=0 or not position or not origin or position.z~=origin.z or
      (currentParams.pathLength or 0)>(tonumber(config.maxDistance) or 10) or
      not current:canShoot() then
    return prime(best)
  end
  if targetId~=current:getId() then prime(currentParams) end
  observe(position)
  if not fired then return currentParams end
  -- Spend this shot even when the best target stays the same. It cannot be
  -- reused for repeated switches between two subsequent autoattacks.
  return prime(best or currentParams)
end

if type(onMissle)=='function' then
  onMissle(function(missile)
    if not targetId or not player or not TargetBot.isOn or not TargetBot.isOn() or
        not projectiles[missile:getId()] then return end
    local current=g_game.getAttackingCreature()
    if not current or current:getId()~=targetId then return end
    local source,destination=missile:getSource(),missile:getDestination()
    if not samePosition(source,player:getPosition()) then return end
    local recent=observedAt and now and now-observedAt<=300
    local previousRecent=previousAt and now and now-previousAt<=300
    if samePosition(destination,current:getPosition()) or
        (recent and samePosition(destination,lastPosition)) or
        (previousRecent and samePosition(destination,previousPosition)) then
      fired=true
    end
  end)
end
