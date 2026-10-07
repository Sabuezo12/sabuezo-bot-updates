-- Spell requirements: Tibia library, checked 2026-10-01. Areas: reference OT
-- implementations (Crystal/Canary). Mythic can override them; presets are editable.
AttackSpellCatalog = {}
local C = AttackSpellCatalog
C.version = 20261001
C.vocations = {"Paladin", "Monk", "Sorcerer", "Druid"}

C.models = {
  {name="Target diamond (13 tiles)", anchor="target", mask="00100/01110/11@11/01110/00100", range=7},
  {name="Target circle (37 tiles)", anchor="target", mask="0011100/0111110/1111111/111@111/1111111/0111110/0011100", range=7},
  {name="Target square (5x5)", anchor="target", mask="11111/11111/11@11/11111/11111", range=7},
  {name="Caster ring (burst)", anchor="caster", mask="000111000/001111100/011111110/111000111/1110C0111/111000111/011111110/001111100/000111000"},
  {name="Forked Thorns (6 targets)", anchor="target", chain=true, fork=true, range=7, jump=5, maxTargets=6},
  {name="Forked Glacier (7 targets)", anchor="target", chain=true, fork=true, range=7, jump=5, maxTargets=7},
  {name="Chained Penance (nearest chain)", anchor="caster", chain=true, range=4, jump=3, maxTargets=3},
  {name="Spiritual Outburst (nearest chain)", anchor="caster", chain=true, range=3, jump=3, maxTargets=4},
  {name="Flurry of Blows (directional)", anchor="caster", mask="00000/00100/01110/01C10/01010", directional=true},
  {name="Greater Flurry (directional)", anchor="caster", mask="00100/01110/01110/11C11/01010", directional=true},
  {name="Sweeping Takedown (directional)", anchor="caster", mask="01110/11111/11111/11C11/11011", directional=true},
  {name="Death Beam (5 ahead)", anchor="caster", mask="1/1/1/1/1/C", directional=true, beam=5},
  {name="Death Beam (6 ahead)", anchor="caster", mask="1/1/1/1/1/1/C", directional=true, beam=6},
  {name="Death Beam (7 ahead)", anchor="caster", mask="1/1/1/1/1/1/1/C", directional=true, beam=7},
  {name="Flurry enlarged (Wheel)", anchor="caster", mask="00100/01110/11111/11C11/11011", directional=true},
  {name="Target circle (21 tiles)", anchor="target", mask="01110/11111/11@11/11111/01110", range=7},
  {name="Divine Empowerment (5s support)", anchor="caster", support=true, range=3},
}
C.patternNames = {}
for i, model in ipairs(C.models) do C.patternNames[i] = model.name end

local function spell(vocation, name, words, level, mana, cooldown, pattern, note, extra)
  local data = {vocation=vocation, name=name, words=words, level=level, mana=mana,
    cooldown=cooldown, pattern=pattern, note=note, category=pattern and 6 or 1,
    range=7, id=words:gsub(" ", "_")}
  for key, value in pairs(extra or {}) do data[key] = value end
  return data
end
C.spells = {
  spell("Paladin", "Ethereal Barrage", "exori dir moe", 60, 135, 4000, 16,
    "Fisico; escala con distance fighting. Apunta a la mejor casilla: 21 SQM (5x5 sin esquinas), radio 2; alcance hasta 7 SQM."),
  spell("Paladin", "Divine Barrage", "exori dir san", 70, 175, 4000, 16,
    "Holy; escala con magic level. Apunta a la mejor casilla: 21 SQM (5x5 sin esquinas), radio 2; alcance hasta 7 SQM."),
  spell("Paladin", "Divine Grenade", "exevo tempo mas san", 0, 160, 26000, 16,
    "Holy; apunta a la mejor casilla para alcanzar monstruos vivos dentro de 3 segundos. Alcance hasta 7 SQM. Requiere Wheel of Destiny.", {wheel=true, delayed=3000}),
  spell("Paladin", "Divine Empowerment", "utevo grav san", 300, 500, 32000, 17,
    "Campo 3x3 durante 5s: aumenta TU dano mientras estes dentro. Espera a estar quieto y a tener un ataque util proximo. Conteo: monstruos cercanos, no casillas del campo. Requiere Wheel.",
    {wheel=true, support=true, duration=5000, spellId=268, group=3}),
  spell("Sorcerer", "Death Echo", "exevo mort ora", 120, 150, 6000, 3,
    "Area 5x5; segundo impacto al segundo (50%). Elemento segun stance.", {delayed=1000}),
  spell("Sorcerer", "Great Death Beam", "exevo max mort", 66, 140, 6000, 12,
    "Beam direccional. Wheel puede aumentar longitud y agregar beams laterales.", {secondary="Great Beams", secondaryCooldown=6000}),
  spell("Druid", "Forked Thorns", "exevo fur tera", 80, 180, 6000, 5,
    "Earth; objetivo + hasta 5 enemigos cercanos. Wheel agrega un objetivo."),
  spell("Druid", "Forked Glacier", "exevo fur frigo", 90, 180, 6000, 6,
    "Ice; objetivo + hasta 6 enemigos cercanos. Wheel agrega un objetivo."),
  spell("Druid", "Ice Burst", "exevo ulus frigo", 0, 230, 22000, 4,
    "Ice; anillo alrededor del personaje. Requiere Wheel; comparte CD con Terra Burst.", {wheel=true, secondary="Bursts Of Nature", secondaryCooldown=22000}),
  spell("Druid", "Terra Burst", "exevo ulus tera", 0, 230, 22000, 4,
    "Earth; anillo alrededor del personaje. Requiere Wheel; comparte CD con Ice Burst.", {wheel=true, secondary="Bursts Of Nature", secondaryCooldown=22000}),
  spell("Monk", "Swift Jab", "exori infir pug", 1, 3, 2000, nil,
    "Builder: genera Harmony. Golpea un objetivo adyacente.", {range=1, harmony="builder"}),
  spell("Monk", "Double Jab", "exori pug", 14, 30, 4000, nil,
    "Builder: genera Harmony. Golpea un objetivo adyacente.", {range=1, harmony="builder"}),
  spell("Monk", "Lesser Mystic Repulse", "exori infir amp pug", 6, 30, 20000, nil,
    "Builder a distancia; genera Harmony.", {harmony="builder"}),
  spell("Monk", "Mystic Repulse", "exori amp pug", 30, 150, 8000, nil,
    "Builder a distancia; genera Harmony. CD oficial actualizado en septiembre.", {harmony="builder"}),
  spell("Monk", "Flurry of Blows", "exori mas pug", 35, 110, 4000, 9,
    "Builder direccional; genera Harmony. Selecciona patron Wheel si tienes area ampliada.", {harmony="builder"}),
  spell("Monk", "Greater Flurry of Blows", "exori gran mas pug", 90, 300, 16000, 10,
    "Builder direccional de area mayor; genera Harmony.", {harmony="builder"}),
  spell("Monk", "Forceful Uppercut", "exori gran pug", 110, 325, 60000, nil,
    "Builder; golpe fuerte a un enemigo adyacente. Requiere aprenderlo en shrine.", {range=1, harmony="builder"}),
  spell("Monk", "Tiger Clash", "exori infir nia", 1, 18, 8000, nil,
    "Spender: consume Harmony. Golpea un objetivo adyacente.", {range=1, harmony="spender"}),
  spell("Monk", "Greater Tiger Clash", "exori nia", 18, 50, 8000, nil,
    "Spender: consume Harmony. Golpea un objetivo adyacente.", {range=1, harmony="spender"}),
  spell("Monk", "Chained Penance", "exori med pug", 70, 180, 4000, 7,
    "Builder; inicia cerca del personaje y encadena al enemigo mas cercano. Conteo estimado.", {harmony="builder"}),
  spell("Monk", "Sweeping Takedown", "exori mas nia", 60, 195, 8000, 11,
    "Spender direccional; consume Harmony y alcanza dos zonas consecutivas.", {harmony="spender"}),
  spell("Monk", "Devastating Knockout", "exori gran nia", 125, 210, 8000, nil,
    "Spender a distancia. CD 8s y rango 7 en el ajuste oficial de septiembre.", {harmony="spender"}),
  spell("Monk", "Spiritual Outburst", "exori gran mas nia", 0, 425, 24000, 8,
    "Spender en cadena desde el personaje. Requiere Wheel; con 5 Harmony repite el golpe.", {harmony="spender", wheel=true}),
  spell("Monk", "Thousand Fist Blows", "exori mas amp pug", 120, 145, 8000, 2,
    "Builder; area alrededor del objetivo. CD oficial actualizado en septiembre.", {harmony="builder"}),
}

function C.normalize(words)
  return tostring(words or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
end
C.byWords = {}
for _, data in ipairs(C.spells) do C.byWords[data.words] = data end
function C.find(words) return C.byWords[C.normalize(words)] end
function C.isBarrage(entry)
  local words = C.normalize(entry.spell)
  return (entry.itemId or 0) <= 100 and (words == "exori dir moe" or words == "exori dir san")
end
function C.list(vocation)
  local result = {}
  for _, data in ipairs(C.spells) do
    if data.vocation == vocation then table.insert(result, data) end
  end
  return result
end

function C.describe(data)
  local model = data.pattern and C.models[data.pattern]
  return data.name .. "\n" .. data.words .. "\n" ..
    "Level: " .. (data.level > 0 and data.level or "Wheel / inicial") ..
    " | Mana: " .. data.mana .. " | CD: " .. data.cooldown / 1000 .. "s\n" ..
    (model and model.name or "Target, range " .. data.range) .. "\n" .. data.note
end

function C.makeEntry(data, overrides)
  local entry = {creatures="*", monsters=true, mana=1, count=1, minHp=0, maxHp=100,
    cooldown=data.cooldown, itemId=0, spell=data.words, enabled=false, category=data.category,
    patternCategory=data.pattern and 5 or 1, pattern=data.pattern or data.range,
    orMore=true, catalogSpell=data.id, catalogGeometryVersion=C.version, spellRange=data.range,
    minimumHarmony=0, tooltip=C.describe(data)}
  local model = data.pattern and C.models[data.pattern]
  if model then
    entry.spellRange = model.range or 7
    entry.chainTargets, entry.chainJump = model.maxTargets, model.jump
  end
  for key, value in pairs(overrides or {}) do entry[key] = value end
  entry.description = "[" .. (model and model.name or "Target") .. "] " .. data.words ..
    " (" .. entry.count .. (entry.orMore and "+" or "") .. ")"
  return entry
end

-- Convert the old screen-count entry to the target-area category once. Preserve
-- user's thresholds, ordering, enabled state and custom cooldown.
function C.migrateEntry(entry)
  local data = C.find(entry.spell)
  if data and C.isDivineGrenade(entry) and entry.grenadeAimVersion ~= 20261004 then
    entry.category, entry.patternCategory, entry.pattern = 6, 5, 16
    entry.spellRange = math.max(0, math.min(7, tonumber(entry.spellRange) or 7))
    entry.grenadeAimVersion = 20261004
    entry.catalogGeometryVersion, entry.catalogSpell = C.version, data.id
    entry.description = "[Mejor casilla en 3s] " .. entry.spell .. " (" .. entry.count .. (entry.orMore and "+" or "") .. ")"
    entry.tooltip = C.describe(data)
    return true
  end
  if data and C.isBarrage(entry) and entry.barrageAimVersion ~= 20261003 then
    entry.category, entry.patternCategory, entry.pattern = 6, 5, 16
    entry.spellRange = math.min(7, tonumber(entry.spellRange) or 7)
    entry.barrageAimVersion = 20261003
    entry.catalogGeometryVersion, entry.catalogSpell = C.version, data.id
    entry.description = "[Mejor casilla: area 21] " .. entry.spell .. " (" .. entry.count .. (entry.orMore and "+" or "") .. ")"
    entry.tooltip = C.describe(data)
    return true
  end
  if not data or not data.pattern or entry.catalogGeometryVersion == C.version then return false end
  if entry.category ~= 1 and entry.category ~= 5 then return false end
  entry.category, entry.patternCategory, entry.pattern = 6, 5, data.pattern
  entry.catalogGeometryVersion, entry.catalogSpell = C.version, data.id
  local model = C.models[data.pattern]
  entry.spellRange = model.range or 7
  entry.chainTargets, entry.chainJump = model.maxTargets, model.jump
  entry.description = "[" .. model.name .. "] " .. entry.spell .. " (" .. entry.count .. (entry.orMore and "+" or "") .. ")"
  entry.tooltip = C.describe(data)
  return true
end

-- Geometry is independent of OTC APIs so it can be checked with map fixtures.
local function distance(a, b)
  if not a or not b or a.z ~= b.z then return math.huge end
  return math.max(math.abs(a.x-b.x), math.abs(a.y-b.y))
end
C.distance = distance
local function offsets(mask)
  local rows, originX, originY = {}, 0, 0
  for row in mask:gmatch("[^/]+") do
    rows[#rows+1] = row
    local x = row:find("[@C]")
    if x then originX, originY = x, #rows end
  end
  local result = {}
  for y, row in ipairs(rows) do
    for x=1,#row do
      local cell = row:sub(x,x)
      if cell == "1" or cell == "@" then result[#result+1] = {x=x-originX,y=y-originY} end
    end
  end
  return result
end
for _, model in ipairs(C.models) do if model.mask then model.offsets = offsets(model.mask) end end

local function matches(entry, actor)
  if not actor.monster or actor.summon then return false end
  if actor.hp < entry.minHp or actor.hp > entry.maxHp then return false end
  if type(entry.monsters) ~= "table" or #entry.monsters == 0 then return true end
  for _, name in ipairs(entry.monsters) do
    if C.normalize(name) == C.normalize(actor.name) then return true end
  end
  return false
end
local function rotated(offset, direction)
  if direction == 1 then return -offset.y, offset.x end
  if direction == 2 then return -offset.x, -offset.y end
  if direction == 3 then return offset.y, -offset.x end
  return offset.x, offset.y
end

-- Aimable Barrages hit the same 21-tile area as diamond arrows. Generate
-- only centres which can hit a matching monster, instead of scanning the map.
-- An empty/occupied centre is legal: line of sight matters, walkability does not.
function C.bestBarrage(entry, caster, targetActor, actors, pvpSafe, canAim)
  local area = C.models[16].offsets
  local range = math.max(0, math.min(7, tonumber(entry.spellRange) or 7))
  local candidates, players = {}, {}
  for _, actor in ipairs(actors) do
    if actor.pos and actor.pos.z == caster.z then
      if pvpSafe and actor.unsafePlayer then players[#players+1] = actor.pos end
      if matches(entry, actor) then
        for _, offset in ipairs(area) do
          local x, y = actor.pos.x-offset.x, actor.pos.y-offset.y
          if math.max(math.abs(x-caster.x), math.abs(y-caster.y)) <= range then
            local key = x .. ":" .. y
            local point = candidates[key]
            if not point then
              point = {pos={x=x,y=y,z=caster.z}, amount=0, spread=0, hitsTarget=false}
              candidates[key] = point
            end
            point.amount = point.amount+1
            point.spread = point.spread+math.abs(offset.x)+math.abs(offset.y)
            if targetActor and actor.id == targetActor.id then point.hitsTarget=true end
          end
        end
      end
    end
  end
  local best
  for _, point in pairs(candidates) do
    local enough = entry.orMore and point.amount >= entry.count or not entry.orMore and point.amount == entry.count
    if enough then
      local unsafe = false
      for _, position in ipairs(players) do
        if distance(position, point.pos) <= 4 then
          -- Keep AttackBot's existing two-tile Anti-RS margin around the area.
          for _, offset in ipairs(area) do
            if math.max(math.abs(position.x-point.pos.x-offset.x),
              math.abs(position.y-point.pos.y-offset.y)) <= 2 then unsafe=true; break end
          end
        end
        if unsafe then break end
      end
      if not unsafe then
        point.targetDistance = targetActor and distance(point.pos, targetActor.pos) or math.huge
        point.castDistance = distance(caster, point.pos)
        local better = not best or point.amount > best.amount
        if best and point.amount == best.amount then
          if point.hitsTarget ~= best.hitsTarget then better = point.hitsTarget
          elseif point.spread ~= best.spread then better = point.spread < best.spread
          elseif point.targetDistance ~= best.targetDistance then better = point.targetDistance < best.targetDistance
          elseif point.castDistance ~= best.castDistance then better = point.castDistance < best.castDistance
          elseif point.pos.x ~= best.pos.x then better = point.pos.x < best.pos.x
          else better = point.pos.y < best.pos.y end
        end
        -- A tile which cannot improve the current choice needs no native
        -- line-of-sight query. Retain exactly the same ranking and tie breaks.
        if better and canAim(point.pos) then best=point end
      end
    end
  end
  return best
end

function C.evaluate(entry, caster, targetActor, actors, direction, pvpSafe)
  local model = C.models[entry.pattern]
  if not model then return 0, false end
  local anchor = model.anchor == "target" and targetActor and targetActor.pos or caster
  if not anchor or (model.anchor == "target" and distance(caster, anchor) > (entry.spellRange or model.range or 7)) then return 0, false end
  local count, unsafe = 0, false
  local hit, visited = {}, {}
  local function add(actor)
    visited[actor.id] = true
    hit[#hit+1] = actor
    if matches(entry, actor) then count = count+1 end
    if actor.unsafePlayer then unsafe = true end
  end
  if not model.chain then
    local cells = {}
    for _, offset in ipairs(model.offsets) do
      local x,y = rotated(offset, model.directional and direction or 0)
      cells[(anchor.x+x) .. ":" .. (anchor.y+y)] = true
    end
    for _, actor in ipairs(actors) do
      if actor.pos.z == anchor.z and cells[actor.pos.x .. ":" .. actor.pos.y] then add(actor) end
      -- Delayed areas use the existing two-tile PVP safety margin.
      if pvpSafe and actor.unsafePlayer and actor.pos.z == anchor.z then
        for _, offset in ipairs(model.offsets) do
          local x,y = rotated(offset, model.directional and direction or 0)
          if distance(actor.pos,{x=anchor.x+x,y=anchor.y+y,z=anchor.z}) <= 2 then unsafe=true; break end
        end
      end
    end
  else
    local maxTargets = entry.chainTargets or model.maxTargets
    local jump = entry.chainJump or model.jump
    local current = anchor
    if model.anchor == "target" and targetActor then add(targetActor) end
    while #hit < maxTargets do
      local nearest, nearestDistance
      local range = #hit == 0 and (entry.spellRange or model.range) or jump
      for _, actor in ipairs(actors) do
        local d = distance(current, actor.pos)
        if actor.monster and not actor.summon and not visited[actor.id] and d <= range and
          (not nearestDistance or d < nearestDistance or d == nearestDistance and actor.id < nearest.id) then
          nearest, nearestDistance = actor, d
        end
      end
      if not nearest then break end
      add(nearest)
      if not model.fork then current = nearest.pos end
    end
    -- Server paths and tie-breaking can differ. Check all reachable chain branches
    -- for players, rather than only the predicted route used for the count.
    if pvpSafe then
      local frontier = {{pos=anchor, range=model.anchor == "caster" and (entry.spellRange or model.range) or jump}}
      local reachable = {}
      for depth=1,maxTargets do
        local nextFrontier = {}
        for _, point in ipairs(frontier) do
          for _, actor in ipairs(actors) do
            if distance(point.pos,actor.pos) <= point.range then
              if actor.unsafePlayer then unsafe=true end
              if actor.monster and not actor.summon and not reachable[actor.id] then
                reachable[actor.id]=true
                nextFrontier[#nextFrontier+1]={pos=actor.pos,range=jump}
              end
            end
          end
        end
        if model.fork then break end
        frontier = nextFrontier
      end
    end
  end
  return count, pvpSafe and unsafe or false, hit
end

-- Divine Grenade explodes at its original tile after three seconds. Keep short,
-- copied observations; neither a moving target nor a changing OTC position
-- object may move the predicted explosion centre after the spell is planted.
function C.isDivineGrenade(entry)
  return (entry.itemId or 0) <= 100 and C.normalize(entry.spell) == "exevo tempo mas san"
end

function C.isDivineEmpowerment(entry)
  return (entry.itemId or 0) <= 100 and C.normalize(entry.spell) == "utevo grav san"
end

function C.observeGrenade(history, caster, actors, time)
  if not history.last or time < history.last or time-history.last > 1000 or
    history.floor ~= caster.z then history.actors = {} end
  history.last, history.floor = time, caster.z
  local seen = {}
  local function observe(key, actor)
    seen[key] = true
    local track = history.actors[key]
    local last = track and track.samples[#track.samples]
    if not last or track.name ~= actor.name or time-last.time > 500 or
      distance(last.pos, actor.pos) > 2 then
      track = {name=actor.name, samples={}, movedAt=time}
      history.actors[key] = track
      last = nil
    end
    if last and distance(last.pos, actor.pos) > 0 then track.movedAt = time end
    if not last or time > last.time then
      track.samples[#track.samples+1] = {time=time, hp=actor.hp,
        pos={x=actor.pos.x, y=actor.pos.y, z=actor.pos.z}}
    end
    -- Retain the sample just before the window boundary for health trends.
    while #track.samples > 2 and track.samples[2].time < time-2000 do
      table.remove(track.samples, 1)
    end
  end
  observe("caster", {name="caster", pos=caster})
  for _, actor in ipairs(actors) do observe(actor.id, actor) end
  for key in pairs(history.actors) do if not seen[key] then history.actors[key] = nil end end
end

local function grenadeVelocity(track, time)
  local samples = track.samples
  local last, first = samples[#samples], samples[1]
  if time-track.movedAt >= 400 then return 0, 0 end
  for _, sample in ipairs(samples) do
    if time-sample.time >= 400 and time-sample.time <= 1000 then first=sample; break end
  end
  local elapsed = last.time-first.time
  if elapsed <= 0 then return 0, 0 end
  return (last.pos.x-first.pos.x)/elapsed, (last.pos.y-first.pos.y)/elapsed
end

-- A monster approaching a stationary character normally stops in the adjacent
-- squares. Clip that forecast at the box instead of extrapolating through it.
local function grenadeApproachTime(position, vx, vy, caster, delay)
  local enter, leave = 0, delay
  for _, axis in ipairs({{position.x, vx, caster.x}, {position.y, vy, caster.y}}) do
    local p, speed, centre = axis[1], axis[2], axis[3]
    if speed == 0 then
      if math.abs(p-centre) > 1 then return delay end
    else
      local a, b = (centre-1-p)/speed, (centre+1-p)/speed
      enter, leave = math.max(enter, math.min(a,b)), math.min(leave, math.max(a,b))
      if enter > leave then return delay end
    end
  end
  return math.max(0, enter)
end

-- Forecast once per decision, then score all possible centres against that same
-- scene. Keep current HP for the user's filters; exclude likely deaths entirely.
local function grenadeForecast(entry, caster, actors, history, time)
  local casterTrack = history.actors and history.actors.caster
  if not casterTrack then return {} end
  local delay = C.find(entry.spell).delayed
  local casterStill = time-casterTrack.movedAt >= 400
  local casterVX, casterVY = grenadeVelocity(casterTrack, time)
  local predicted = {}
  for _, actor in ipairs(actors) do
    local forecast = {}
    for key, value in pairs(actor) do forecast[key] = value end
    forecast.pos = {x=actor.pos.x, y=actor.pos.y, z=actor.pos.z}
    local track = history.actors[actor.id]
    local observed = track and time-track.samples[1].time or 0
    if track and observed >= 400 then
      local vx, vy = grenadeVelocity(track, time)
      local travel = delay
      if actor.monster and not actor.summon then
        if casterStill and (caster.x-actor.pos.x)*vx+(caster.y-actor.pos.y)*vy > 0 then
          travel = grenadeApproachTime(actor.pos, vx, vy, caster, delay)
        elseif not casterStill and distance(caster, actor.pos) <= 1 then
          -- Adjacent monsters are likely to follow a running character even if
          -- their next step has not yet arrived from the server.
          vx, vy = casterVX, casterVY
        end
      end
      forecast.pos.x = math.floor(actor.pos.x+vx*travel+0.5)
      forecast.pos.y = math.floor(actor.pos.y+vy*travel+0.5)
      if actor.monster then
        local first = track.samples[1]
        local remaining
        if observed >= 800 then
          local loss = math.max(0, (first.hp or actor.hp)-actor.hp)
          remaining = actor.hp-loss*delay/observed
        else
          -- With little damage history, save the long cooldown on weak mobs.
          remaining = actor.hp >= 25 and actor.hp or 0
        end
        if remaining <= 5 then forecast.monster = false end
      end
    elseif actor.monster then
      -- Brief observation also avoids firing during a newly arriving pull.
      forecast.monster = false
    end
    predicted[#predicted+1] = forecast
  end
  return predicted
end

function C.bestGrenade(entry, caster, targetActor, actors, pvpSafe, history, time, canAim)
  local predicted = grenadeForecast(entry, caster, actors, history, time)
  local futureTarget
  for _, actor in ipairs(predicted) do
    if targetActor and actor.id == targetActor.id then futureTarget=actor end
  end
  if pvpSafe then
    -- Protect players at both their current and projected positions. Forecasts
    -- are estimates, so movement must not cancel an existing Anti-RS exclusion.
    for _, actor in ipairs(actors) do
      if actor.unsafePlayer then
        predicted[#predicted+1] = {pos=actor.pos, unsafePlayer=true}
      end
    end
  end
  -- Grenade and Barrages share the confirmed 21-tile footprint. This searches
  -- reachable centres, including empty tiles, without changing the attack target.
  return C.bestBarrage(entry, caster, futureTarget, predicted, pvpSafe, canAim)
end

-- Compatibility check for a fixed current-target centre. AttackBot selects
-- new Grenade casts with bestGrenade, which searches the forecast scene.
function C.evaluateGrenade(entry, caster, targetActor, actors, direction, pvpSafe, history, time)
  local current, unsafe = C.evaluate(entry, caster, targetActor, actors, direction, pvpSafe)
  local enough = entry.orMore and current >= entry.count or not entry.orMore and current == entry.count
  if not enough then return 0, unsafe end
  local predicted = grenadeForecast(entry, caster, actors, history, time)
  -- The target position deliberately stays CURRENT. Moving it to the predicted
  -- target would incorrectly make the planted grenade follow that creature.
  local count, futureUnsafe = C.evaluate(entry, caster, targetActor, predicted, direction, pvpSafe)
  return count, unsafe or futureUnsafe
end

-- The 3x3 field buffs the caster, rather than damaging monsters on those tiles.
-- Save its long cooldown until the character has stopped and a living pack is
-- close enough for the existing AoE rotation. Movement remains unrestricted.
function C.evaluateEmpowerment(entry, caster, actors, history, time)
  local casterTrack = history.actors and history.actors.caster
  if not casterTrack or time-casterTrack.movedAt < 800 then return 0 end
  local count = 0
  for _, actor in ipairs(actors) do
    if matches(entry, actor) and distance(caster, actor.pos) <= (entry.spellRange or 3) then
      local track = history.actors[actor.id]
      local observed = track and time-track.samples[1].time or 0
      local remaining = 0
      if observed >= 800 then
        local first = track.samples[1]
        local loss = math.max(0, (first.hp or actor.hp)-actor.hp)
        remaining = actor.hp-loss*3000/observed
      elseif observed >= 400 and actor.hp >= 25 then
        remaining = actor.hp
      end
      if remaining > 5 then count = count+1 end
    end
  end
  return count
end

-- Requirements are checked even after vlib has registered the spell's cooldown.
-- Respect the existing RL-conditions switch for custom-server mana/level values.
function C.ready(entry, settings, state)
  local data = C.find(entry.spell)
  if not data then return true end
  if settings.ignoreMana and (state.level < data.level or state.mana < data.mana) then return false end
  if (entry.minimumHarmony or 0) > 0 and (state.harmony == nil or state.harmony < entry.minimumHarmony) then return false end
  if settings.Cooldown and data.secondary and state.secondary[data.secondary] and
    state.now-state.secondary[data.secondary] < (entry.secondaryCooldown or math.min(entry.cooldown, data.secondaryCooldown)) then return false end
  return not state.attempts[data.words] or state.now-state.attempts[data.words] >= 1000
end
