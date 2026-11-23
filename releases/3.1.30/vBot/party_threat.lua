-- Who is attacking an ally? Evidence for the Knight's Challenge (exeta res) and Chivalrous
-- Challenge (exeta amp res) while hunting with allies. A monster threatens an ally when:
--   * it shoots a missile at an ally,
--   * an ally next to it loses health,
--   * an ally reports over Navi that it hit them ("You lose N hitpoints due to an attack by X"),
--   * it stays next to an ally, away from the knight, for 500 ms (T.scanAdjacent).
-- Allies are party members and Navi members. Evidence expires after THREAT_TTL ms.
-- It also learns at which health each monster runs away, for Challenge while hunting alone.
-- Read-only: nothing here casts or walks.
PartyThreat = {}
local T = PartyThreat
local THREAT_TTL = 2500
local REPORT_GAP = 1500
local REPORT_MIN_GAP = 1000
local NAVI_LAG = 500
local reportReadyAt = 0
local ADJACENT_HOLD = 500
local MELEE_HOLD = 1000
local FLEE_MAX_HP = 30
local FLEE_CONFIRM_MS = 1500
local threats, notes = {}, 0
local reportAt, reports = {}, 0
local allyHp = {}
local adjacentSince, meleeSince = {}, {}
local fleeStep, fleeSeen = {}, {}
local naviNames, naviAt = {}, -10000

local function cheb(a, b)
  if not a or not b or a.z ~= b.z then return math.huge end
  return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end
local function selfPos() return player and player:getPosition() end
local function realMonster(creature)
  return creature:isMonster() and (g_game.getClientVersion() < 960 or (tonumber(creature:getType()) or 0) < 3)
end

local function naviMembers()
  if now - naviAt < 2000 then return naviNames end
  naviAt, naviNames = now, {}
  if BotServer and BotServer.getMemberSnapshot then
    local ok, snapshot = pcall(BotServer.getMemberSnapshot)
    if ok and type(snapshot) == 'table' then
      for name in pairs(snapshot) do naviNames[tostring(name):lower()] = true end
    end
  end
  return naviNames
end

local function rememberHealth(creature)
  local id = creature:getId()
  if allyHp[id] then return end
  local count = 0
  for _ in pairs(allyHp) do count = count + 1 end
  if count >= 32 then allyHp = {} end
  allyHp[id] = creature:getHealthPercent()
end

function T.isAlly(creature)
  if not creature or not creature:isPlayer() or creature:isLocalPlayer() then return false end
  local ok, party = pcall(creature.isPartyMember, creature)
  local name = creature:getName()
  local ally = ok and party or name ~= nil and naviMembers()[name:lower()] == true
  -- Known health from the first sighting: the first change can then be read as damage or healing.
  if ally then rememberHealth(creature) end
  return ally
end

-- 'pegado' (next to an ally) is only a hint; missiles, health and Navi reports are direct hits.
function T.note(id, source, ally)
  if type(id) ~= 'number' then return end
  local entry = threats[id] or {}
  entry.at, entry.source, entry.ally = now, source, ally
  -- A Navi report travels ally -> server -> knight: date it NAVI_LAG ms back, so a hit sent
  -- before a challenge never counts as a hit after it.
  if source ~= 'pegado' then entry.hitAt, entry.hitSource, entry.hitAlly = now - (source == 'navi' and NAVI_LAG or 0), source, ally end
  threats[id] = entry
  notes = notes + 1
  if notes >= 64 then
    notes = 0
    for key, value in pairs(threats) do if now - value.at > THREAT_TTL then threats[key] = nil end end
  end
end

-- Current evidence, or only evidence newer than `since` (a hit after the last challenge).
-- direct: only missiles, health and Navi reports, as {at, source, ally}.
function T.get(id, since, direct)
  local entry = threats[id]
  if not entry then return nil end
  if now - entry.at > THREAT_TTL then threats[id] = nil;return nil end
  if direct then
    if not entry.hitAt or now - entry.hitAt > THREAT_TTL or since and entry.hitAt <= since then return nil end
    return {at = entry.hitAt, source = entry.hitSource, ally = entry.hitAlly}
  end
  if since and entry.at <= since then return nil end
  return entry
end

-- A monster next to an ally and not next to the knight for ADJACENT_HOLD ms.
function T.scanAdjacent(monsters, allies, me)
  local seen = {}
  for _, monster in ipairs(monsters) do
    if monster.pos and cheb(monster.pos, me) > 1 then
      for _, ally in ipairs(allies) do
        if cheb(ally.pos, monster.pos) <= 1 then
          seen[monster.id] = true
          adjacentSince[monster.id] = adjacentSince[monster.id] or now
          if now - adjacentSince[monster.id] >= ADJACENT_HOLD then T.note(monster.id, 'pegado', ally.name) end
          break
        end
      end
    end
  end
  for id in pairs(adjacentSince) do if not seen[id] then adjacentSince[id] = nil end end
end
function T.resetAdjacent() adjacentSince = {} end

-- Monsters next to the knight; a melee monster that steps away at low health is running away.
function T.watchMelee(monsters, me)
  local seen = {}
  for _, monster in ipairs(monsters) do
    if monster.pos and cheb(monster.pos, me) <= 1 then
      seen[monster.id] = true
      meleeSince[monster.id] = meleeSince[monster.id] or now
    end
  end
  for id in pairs(meleeSince) do if not seen[id] and now - meleeSince[id] > 3000 then meleeSince[id] = nil end end
  for id, step in pairs(fleeStep) do if now - step.at > FLEE_CONFIRM_MS then fleeStep[id] = nil end end
end

-- Learned running-away health by monster name (percent), kept in the profile storage.
function T.fleeHealth(name)
  local learned = storage.exetaFleeHp
  return type(learned) == 'table' and name and learned[name:lower()] or nil
end

-- A new running-away health needs two sightings by two different monsters of that name within
-- 10 minutes; the lower one is kept.
local function learnFlee(creature, hp)
  storage.exetaFleeHp = type(storage.exetaFleeHp) == 'table' and storage.exetaFleeHp or {}
  local name = creature:getName():lower()
  local learned = storage.exetaFleeHp[name]
  if learned and hp <= learned then return end
  local seen = fleeSeen[name]
  if not seen or seen.id == creature:getId() or now - seen.at > 600000 then
    local count = 0
    for _ in pairs(fleeSeen) do count = count + 1 end
    if count >= 64 then fleeSeen = {} end
    fleeSeen[name] = {hp = hp, id = creature:getId(), at = now}
    return
  end
  fleeSeen[name] = nil
  local value = math.min(seen.hp, hp)
  if learned and value <= learned then return end
  local count = 0
  for _ in pairs(storage.exetaFleeHp) do count = count + 1 end
  if not learned and count >= 200 then return end
  storage.exetaFleeHp[name] = value
  if RinoConsole and RinoConsole.valid and RinoConsole.valid() then
    pcall(RinoConsole.log, 'action', 'AttackBot', 'Exeta Res: ' .. name .. ' huye con ' .. value .. '% de vida',
      'se provocara antes de llegar a esa vida')
  end
end

-- Running away: a melee monster (next to the knight for 1 s) at low health steps away and keeps
-- going one more step within 1.5 s. A single step (a push, a reposition) is not enough.
onCreaturePositionChange(function(creature, newPos, oldPos)
  if not creature or not newPos or not oldPos then return end
  local id = creature:getId()
  local step = fleeStep[id]
  local since = meleeSince[id]
  if not step and not since then return end
  local me = selfPos()
  if not me then return end
  if step then
    fleeStep[id] = nil
    if now - step.at <= FLEE_CONFIRM_MS and cheb(newPos, me) > cheb(oldPos, me) then learnFlee(creature, step.hp) end
    return
  end
  if now - since < MELEE_HOLD or cheb(oldPos, me) > 1 or cheb(newPos, me) <= cheb(oldPos, me) then return end
  local hp = creature:getHealthPercent()
  if not hp or hp <= 0 or hp > FLEE_MAX_HP then return end
  meleeSince[id] = nil
  fleeStep[id] = {hp = hp, at = now}
end)

onMissle(function(missile)
  local me = selfPos()
  local source, destination = missile:getSource(), missile:getDestination()
  if not me or not source or not destination or source.z ~= me.z or destination.z ~= me.z or cheb(source, me) > 8 then return end
  local fromTile, toTile = g_map.getTile(source), g_map.getTile(destination)
  if not fromTile or not toTile then return end
  local ally
  for _, creature in ipairs(toTile:getCreatures()) do
    if T.isAlly(creature) then ally = creature;break end
  end
  if not ally then return end
  for _, creature in ipairs(fromTile:getCreatures()) do
    if realMonster(creature) then T.note(creature:getId(), 'proyectil', ally:getName()) end
  end
end)

onCreatureHealthPercentChange(function(creature, healthPercent)
  if not creature or not creature:isPlayer() or creature:isLocalPlayer() then return end
  local id = creature:getId()
  local before = allyHp[id] -- read before T.isAlly, which seeds unknown allies with the new value
  if not T.isAlly(creature) then return end
  allyHp[id] = healthPercent
  if not before or healthPercent >= before then return end
  local position = creature:getPosition()
  if not position then return end
  for _, monster in ipairs(g_map.getSpectatorsInRange(position, false, 1, 1)) do
    if realMonster(monster) then T.note(monster:getId(), 'vida', creature:getName()) end
  end
end)

-- A knight is the one who challenges: it never reports its own hits.
local function isKnight()
  local ok, vocation = pcall(function()
    local value = player:getVocation()
    if HelperClientCompat and HelperClientCompat.baseVocation then value = HelperClientCompat.baseVocation(value) end
    return value
  end)
  return ok and (vocation == 1 or vocation == 11)
end

-- Ally side: tell the knight over Navi which monster is hitting this character. At most one report
-- every REPORT_MIN_GAP ms, and only with an ally in sight: Navi traffic stays small.
local function reportAttack(name)
  if not (BotServer and BotServer.announceThreat) or now < reportReadyAt or isKnight() then return end
  local me = selfPos()
  if not me then return end
  -- The message names the attacker, not which one: report it only when it is unambiguous
  -- (the only one of that name next to this character, else the only one in sight).
  local adjacent, inSight, best, allyNear = 0, 0, nil, false
  local nearest
  for _, creature in ipairs(g_map.getSpectatorsInRange(me, false, 8, 6)) do
    if realMonster(creature) then
      if creature:getName():lower() == name then
        inSight = inSight + 1;best = creature
        if cheb(creature:getPosition(), me) <= 1 then adjacent = adjacent + 1;nearest = creature end
      end
    elseif not allyNear and T.isAlly(creature) then allyNear = true end
  end
  if not allyNear then return end
  if adjacent == 1 then best = nearest elseif adjacent > 1 or inSight ~= 1 then return end
  local id = best:getId()
  if (reportAt[id] or 0) > now then return end
  reportReadyAt = now + REPORT_MIN_GAP
  reports = reports + 1
  if reports >= 128 then
    reports = 0
    for key, at in pairs(reportAt) do if at <= now then reportAt[key] = nil end end
  end
  reportAt[id] = now + REPORT_GAP
  pcall(BotServer.announceThreat, {v = 1, id = id, name = name})
end

onTextMessage(function(mode, text)
  -- Hitpoints or mana (a druid under utamo vita loses mana).
  if type(text) ~= 'string' or not text:find('^You lose %d+ ') then return end
  local name = text:match('due to an attack by (.+)%.$')
  if not name then return end
  name = name:lower():gsub('^an? ', '')
  reportAttack(name)
end)

-- Knight side: an ally reported a hit.
-- Accepted only from a Navi member in sight of the knight, about a monster in sight with that name.
function T.onNavi(sender, message)
  if type(sender) ~= 'string' or #sender > 64 or type(message) ~= 'table' or message.v ~= 1 or
    type(message.id) ~= 'number' or type(message.name) ~= 'string' or #message.name > 64 then return end
  local own = player and player:getName()
  local who = sender:lower()
  if own and who == own:lower() or not naviMembers()[who] then return end
  local me = selfPos()
  if not me then return end
  local monster, ally
  for _, creature in ipairs(g_map.getSpectatorsInRange(me, false, 8, 6)) do
    if creature:getId() == message.id then
      if realMonster(creature) and creature:getName():lower() == message.name:lower() then monster = creature end
    elseif creature:isPlayer() and creature:getName():lower() == who then ally = creature end
  end
  if monster and ally then T.note(message.id, 'navi', ally:getName()) end
end
