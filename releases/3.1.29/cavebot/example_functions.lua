CaveBot.Editor.ExampleFunctions = {}

local function addExampleFunction(title, text)
  return table.insert(CaveBot.Editor.ExampleFunctions, {title, text:trim()})
end

addExampleFunction("Click to browse example functions", [[
-- available functions/variables:
-- prev - result of previous action (true or false)
-- retries - number of retries of current function, goes up by one when you return "retry"
-- delay(number) - delays bot next action, value in milliseconds
-- gotoLabel(string) - goes to specific label, return true if label exists
-- waitStamina(minutes, waitMs) - waits here until stamina reaches minutes
-- setHealBot(on/off/toggle) - enables, disables or toggles HealBot
-- stepDirection(direction, maxRetries, waitMs) - walks one sqm from current position
--   directions: north/norte, south/sur, east/este, west/oeste,
--   northeast/noreste, southeast/sureste, southwest/suroeste, northwest/noroeste
-- you can easily access bot extensions, Depositer.run() instead of CaveBot.Extensions.Depositer.run()
-- also you can access bot global variables, like CaveBot, TargetBot
-- use storage variable to store date between calls

-- function should return false, true or "retry"
-- if "retry" is returned, function will be executed again in 20 ms (so better call delay before)

return true
]])

addExampleFunction("Wait stamina before next waypoint", [[
-- stamina is in minutes. 2520 = 42h.
local minStamina = 2520
local checkEveryMs = 60000

return waitStamina(minStamina, checkEveryMs)
]])

addExampleFunction("Disable HealBot", [[
return setHealBot("off")
]])

addExampleFunction("Enable HealBot", [[
return setHealBot("on")
]])

addExampleFunction("Step one tile by direction", [[
-- Change direction to: norte, sur, este, oeste, noreste, sureste, suroeste, noroeste.
local direction = "sur"
local maxRetries = 30
local retryEveryMs = 200

return stepDirection(direction, maxRetries, retryEveryMs)
]])

addExampleFunction("Check for PZ and wait until dropped", [[
if retries > 25 or not isPzLocked() then
  return true
else
  if isPoisioned() then
      say("exana pox")
  end
  if isPzLocked() then
      delay(8000)
  end
  return "retry"
end
]])

addExampleFunction("Stop bot if stamina or imbues are low", [[
if stamina() < 900 or player:getSkillLevel(11) == 0 then
  CaveBot.setOff()
  return false
end

return true
]])

addExampleFunction("buy 200 mana potion from npc Eryn", [[
--buy 200 mana potions
local npc = getCreatureByName("Eryn")
if not npc then 
  return false 
end
if retries > 10 then
  return false
end
local pos = player:getPosition()
local npcPos = npc:getPosition()
if math.max(math.abs(pos.x - npcPos.x), math.abs(pos.y - npcPos.y)) > 3 then
  autoWalk(npcPos, {precision=3})
  delay(300)
  return "retry"
end
if not NPC.isTrading() then
  NPC.say("hi")
  NPC.say("trade")
  delay(200)
  return "retry"
end
NPC.buy(268, 100)
schedule(1000, function()
  -- buy again in 1s
  NPC.buy(268, 100)
  NPC.closeTrade()
  NPC.say("bye")
end)
delay(1200)
return true
]])

addExampleFunction("Say hello 5 times with some delay", [[
--say hello
if retries > 5 then
  return true -- finish
end
say("hello")
delay(100 + retries * 100)
return "retry"
]])

addExampleFunction("Disable TargetBot", [[
TargetBot.setOff()
return true
]])

addExampleFunction("Enable TargetBot", [[
TargetBot.setOn()
return true
]])

addExampleFunction("Enable TargetBot luring", [[
TargetBot.enableLuring()
return true
]])

addExampleFunction("Disable TargetBot luring", [[
TargetBot.disableLuring()
return true
]])

addExampleFunction("Logout", [[
g_game.safeLogout()
delay(1000)
return "retry"
]])

addExampleFunction("Close Loot Containers", [[
CaveBot.CloseAllLootContainers()
delay(3000)
return true
]])
