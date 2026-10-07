CaveBot.Extensions.ClearTile = {}

CaveBot.Extensions.ClearTile.setup = function()
  local DESTROY_FIELD_RUNE_ID = 3148
  local DESTROY_FIELD_IDS = {
    2118, 118, 105, 2121, 2122, 2123, 2124, 2125, 2126, 2131, 2132, 2133, 2134, 2135
  }

  local function hasPosition(pos)
    return pos and pos.x and pos.y and pos.z
  end

  local function getFieldThing(tile)
    if not tile then return nil end

    for _, item in ipairs(tile:getItems()) do
      if table.find(DESTROY_FIELD_IDS, item:getId()) then
        return item
      end
    end

    return nil
  end

  CaveBot.registerAction("ClearTile", "#00FFFF", function(value, retries)
    local data = string.split(value, ",")
    local pos = {x=tonumber(data[1]), y=tonumber(data[2]), z=tonumber(data[3])}
    local doors = false
    local stand = false
    local pPos = player:getPosition()


    for i, value in ipairs(data) do
      value = value:lower():trim()
      if value == "stand" then
        stand = true
      elseif value == "doors" then
        doors = true
      end
    end


    if not hasPosition(pos) then
      warn("CaveBot[ClearTile]: invalid value. It should be position (x,y,z), is: " .. value)
      return false
    end

    if retries >= 20 then
      print("CaveBot[ClearTile]: too many tries, can't clear it")
      return false -- tried 20 times, can't clear it
    end

    if getDistanceBetween(player:getPosition(), pos) == 0 then
      print("CaveBot[ClearTile]: tile reached, proceeding")
      return true
    end
    local tile = g_map.getTile(pos)
    if not tile then
      print("CaveBot[ClearTile]: can't find tile or tile is unreachable, skipping")
      return false
    end
    local tPos = tile:getPosition()

    local fieldThing = getFieldThing(tile)
    if fieldThing then
      if not CaveBot.MatchPosition(tPos, 7) then
        CaveBot.GoTo(tPos, 7)
        return "retry"
      end

      if tile:canShoot() then
        print("CaveBot[ClearTile]: destroying field... " .. fieldThing:getId() .. " on tile")
        useWith(DESTROY_FIELD_RUNE_ID, fieldThing)
        delay(700)
        return "retry"
      end
    end

    -- no items on tile and walkability means we are done
    local topUseThing = tile:getTopUseThing()
    if tile:isWalkable() and topUseThing and topUseThing:isNotMoveable() and not tile:hasCreature() and not doors then
      if stand then
        if not CaveBot.MatchPosition(tPos, 0) then
          CaveBot.GoTo(tPos, 0)
          return "retry"
        end
      end
      print("CaveBot[ClearTile]: tile clear, proceeding")
      return true
    end

    if not CaveBot.MatchPosition(tPos, 3) then
      CaveBot.GoTo(tPos, 3)
      return "retry"
    end

    if retries > 0 then
      delay(1100)
    end

    -- monster
    if tile:hasCreature() then
      local c = tile:getCreatures()[1]
      if c:isMonster() then
        attack(c)
        return "retry"
      end
    end

    -- moveable item
    local item = tile:getTopMoveThing()
    if item and item:isItem() then
      if item and not item:isNotMoveable() then
        print("CaveBot[ClearTile]: moving item... " .. item:getId().. " from tile")
        g_game.move(item, pPos, item:getCount())
        return "retry"
      end   
    end

    -- player

      -- push creature
      if tile:hasCreature() then
        local c = tile:getCreatures()[1]
        if c and c:isPlayer() then

          local candidates = {}
          for _, tile in ipairs(g_map.getTiles(posz())) do
            local tPos = tile:getPosition()
            if getDistanceBetween(c:getPosition(), tPos) == 1 and tPos ~= pPos and tile:isWalkable() then
              table.insert(candidates, tPos)
            end
          end

          if #candidates == 0 then
            print("CaveBot[ClearTile]: can't find tile to push, cannot clear way, skipping")
            return false
          else
            print("CaveBot[ClearTile]: pushing player... " .. c:getName() .. " out of the way")
            local pos = candidates[math.random(1,#candidates)]
            local tile = g_map.getTile(pos)
            tile:setText("here")
            schedule(500, function() tile:setText("") end)
            g_game.move(c, pos, 1)
            return "retry"
          end
        end
      end

    -- doors
    if doors then
      use(tile:getTopUseThing())
      return "retry"
    end

    return "retry"
  end)

  CaveBot.Editor.registerAction("cleartile", "clear tile", {
    value=function() return posx() .. "," .. posy() .. "," .. posz() end,
    title="position of tile to clear",
    description="tile position (x,y,z), doors/stand - optional",
    multiline=false
})
end
