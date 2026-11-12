CaveBot.Extensions.SellAll = {}

local sellAllCap = 0

-- The value of the action is "NPC, yes, id, id": the NPC's name, "yes" to sell with a delay, then the IDs of
-- the items that must NOT be sold (exceptions). The editor panel reads and writes it through these two.
local function trim(text)
  return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Returns {npc, delayed, ids, extra}. `extra` keeps any other word, so nothing typed by hand is lost.
CaveBot.Extensions.SellAll.decode = function(value)
  local result = {npc = "", delayed = false, ids = {}, extra = {}}
  local seen, first = {}, true
  for part in (tostring(value or "") .. ","):gmatch("([^,]*),") do
    part = trim(part)
    if part ~= "" then
      if first then
        first = false
        -- "NPC" is only the placeholder of a new action, not a name.
        result.npc = part == "NPC" and "" or part
      elseif part:lower() == "yes" then
        result.delayed = true
      else
        local id = tonumber(part)
        if id and id > 100 and id == math.floor(id) then
          if not seen[id] then seen[id] = true; result.ids[#result.ids + 1] = id end
        else
          result.extra[#result.extra + 1] = part
        end
      end
    end
  end
  return result
end

CaveBot.Extensions.SellAll.encode = function(config)
  local parts = {trim(config.npc)}
  if config.delayed then parts[#parts + 1] = "yes" end
  for _, id in ipairs(config.ids or {}) do parts[#parts + 1] = tostring(id) end
  for _, word in ipairs(config.extra or {}) do parts[#parts + 1] = tostring(word) end
  return table.concat(parts, ", ")
end
CaveBot.Extensions.SellAll.setup = function()
  CaveBot.registerAction("SellAll", "#C300FF", function(value, retries)
    local val = string.split(value, ",")
    local wait

    -- table formatting
    for i, v in ipairs(val) do
      v = v:trim()
      v = tonumber(v) or v
      val[i] = v
    end

    if table.find(val, "yes", true) then
      wait = true
    end

    local npcName = val[1]
    local npc = getCreatureByName(npcName)
    if not npc then 
      print("CaveBot[SellAll]: NPC not found! skipping")
      return false 
    end

    if retries > 10 then
      print("CaveBot[SellAll]: can't sell, skipping")
      return false
    end

    if freecap() == sellAllCap then
      sellAllCap = 0 
      CaveBot.FinishNpcConversation(0)
      print("CaveBot[SellAll]: Sold everything, proceeding")
      return true
    end

    delay(800)
    if not CaveBot.ReachNPC(npcName) then
      return "retry"
    end

    if not NPC.isTrading() then
      CaveBot.OpenNpcTrade()
      delay(storage.extras.talkDelay*2)
      return "retry"
    else
      sellAllCap = freecap()
    end

    storage.cavebotSell = storage.cavebotSell or {}
    for i, item in ipairs(storage.cavebotSell) do
      local data = type(item) == 'number' and item or item.id
      if not table.find(val, data) then
        table.insert(val, data)
      end
    end

    table.dump(val)
    local kept = 0
    for _, entry in ipairs(val) do if type(entry) == "number" then kept = kept + 1 end end
    print("CaveBot[SellAll]: se conservan " .. kept .. " objetos (excepciones)")

    modules.game_npctrade.sellAll(wait, val)
    if wait then
      print("CaveBot[SellAll]: Sold All with delay")
    else
      print("CaveBot[SellAll]: Sold All without delay")
    end

    return "retry"
  end)

 CaveBot.Editor.registerAction("sellall", "sell all", {
  value="NPC",
  title="Sell All",
  description="NPC Name, 'yes' if sell with delay, exceptions: id separated by comma (the panel edits them)",
 })
end
