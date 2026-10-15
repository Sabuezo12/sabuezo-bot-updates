setDefaultTab("Tools")

local key = "imbuementScrolls"
storage[key] = type(storage[key]) == "table" and storage[key] or {}
local config = storage[key]
config.enabled = config.enabled == true
config.onlyPz = config.onlyPz == true
config.rules = type(config.rules) == "table" and config.rules or {}
config.nextId = tonumber(config.nextId) or 1

local slots = {{1,"Casco"},{2,"Collar"},{3,"Mochila"},{4,"Armadura"},
  {5,"Mano derecha"},{6,"Mano izquierda"},{7,"Piernas"},{8,"Botas"},{9,"Anillo"},{10,"Municion"}}
local effects = {"Void","Vampirism","Strike","Precision","Epiphany","Slash","Chop","Bash",
  "Blockade","Punch","Featherweight","Swiftness","Vibrancy","Lich Shroud","Snake Skin",
  "Dragon Hide","Quara Scale","Cloud Fabric","Demon Presence","Reap","Scorch","Frost","Venom","Electrify"}
local aliases = {void={"manaleech","manaleach"}, vampirism={"lifeleech","lifeleach"}, strike={"criticalhit"}}
local function normalized(text) return tostring(text or ""):lower():gsub("[^%w]", "") end
local function effectMatches(wanted, name)
  local wantedKey, nameKey = normalized(wanted), normalized(name)
  if wantedKey=="block" then wantedKey="blockade" end
  if wantedKey == "" then return false end
  if wantedKey == nameKey then return true end
  local base = nameKey:gsub("^powerful", ""):gsub("^intricate", ""):gsub("^basic", "")
  if base=="block" then base="blockade" end
  for _, effect in ipairs(effects) do
    if normalized(effect) == wantedKey then
      if base == wantedKey then return true end
      for _, alias in ipairs(aliases[wantedKey] or {}) do if base == alias then return true end end
    end
  end
  return false
end
local function number(value, default) return tonumber(value) or default end
for _, rule in ipairs(config.rules) do
  rule.uid = number(rule.uid, config.nextId)
  config.nextId = math.max(config.nextId, rule.uid+1)
  rule.enabled = rule.enabled == true
  rule.slot = math.max(1, math.min(10, number(rule.slot, 1)))
  rule.itemId, rule.scrollId = number(rule.itemId, 0), number(rule.scrollId, 0)
  rule.effect = tostring(rule.effect or "")
  rule.name = tostring(rule.name or "")
  rule.attempts, rule.retryAt = number(rule.attempts, 0), number(rule.retryAt, 0)
end
if type(config.pending) ~= "table" or not tonumber(config.pending.createdAt) then config.pending = nil end

-- Reference: nExBot's public cavebot/imbuing.lua groups effects by equipment
-- item and processes items sequentially. Here profiles hold whole equipment
-- sets, and MythicOT's direct scroll use replaces its shrine workflow.
if config.profilesVersion ~= 1 then
  local profile = {uid=1,name="Principal",equipment={},rules=config.rules}
  for slot=1,10 do profile.equipment[slot]=0 end
  for _, rule in ipairs(profile.rules) do
    if profile.equipment[rule.slot]==0 then profile.equipment[rule.slot]=rule.itemId end
  end
  config.profiles={profile}
  config.currentProfileId,config.nextProfileId,config.profilesVersion=1,2,1
end
config.profiles=type(config.profiles)=="table" and config.profiles or {}
config.nextProfileId=number(config.nextProfileId,1)
local usedRuleIds,usedProfileIds = {},{}
for _, profile in ipairs(config.profiles) do
  profile.uid=number(profile.uid,config.nextProfileId)
  if usedProfileIds[profile.uid] then profile.uid=config.nextProfileId end
  usedProfileIds[profile.uid]=true
  config.nextProfileId=math.max(config.nextProfileId,profile.uid+1)
  profile.name=tostring(profile.name or "Perfil "..profile.uid)
  profile.equipment=type(profile.equipment)=="table" and profile.equipment or {}
  for slot=1,10 do
    profile.equipment[slot]=number(profile.equipment[slot] or profile.equipment[tostring(slot)],0)
    profile.equipment[tostring(slot)]=nil
  end
  profile.rules=type(profile.rules)=="table" and profile.rules or {}
  for _, rule in ipairs(profile.rules) do
    rule.uid=number(rule.uid,config.nextId)
    if usedRuleIds[rule.uid] then rule.uid=config.nextId end
    usedRuleIds[rule.uid]=true;config.nextId=math.max(config.nextId,rule.uid+1)
    rule.slot=math.max(1,math.min(10,number(rule.slot,1)))
    rule.itemId,rule.scrollId=number(rule.itemId,0),number(rule.scrollId,0)
    rule.effect=tostring(rule.effect or "")
    rule.enabled=rule.enabled==true
    rule.attempts,rule.retryAt=number(rule.attempts,0),number(rule.retryAt,0)
  end
end
if #config.profiles==0 then
  config.profiles[1]={uid=config.nextProfileId,name="Principal",equipment={},rules={}}
  for slot=1,10 do config.profiles[1].equipment[slot]=0 end
  config.nextProfileId=config.nextProfileId+1
end
local function profileById(id)
  for _, profile in ipairs(config.profiles) do if profile.uid==id then return profile end end
end
local currentProfile=profileById(config.currentProfileId) or config.profiles[1]
config.currentProfileId=currentProfile.uid
config.rules=currentProfile.rules
local function ruleById(id)
  for _, profile in ipairs(config.profiles) do
    for _, rule in ipairs(profile.rules) do if rule.uid==id then return rule,profile end end
  end
end

local ui = UI.createWidget("ImbuementScrollPanel")
ui:setId(key)
local window = UI.createWindow("ImbuementScrollWindow")
window:hide()
local generation = tostring(ui)
local snapshot, capacity, rows = nil, {}, {}
local revision, nextRequest, binding, destroyed = 0, 0, false, false
local previousPlayer = g_game.getLocalPlayer()

local function equipped(slot)
  local current = g_game.getLocalPlayer()
  return current and current:getInventoryItem(slot) or nil
end
local function itemId(item)
  if not item then return nil end
  local ok, id = pcall(function() return item:getId() end)
  return ok and tonumber(id) or nil
end
local function character()
  local current = g_game.getLocalPlayer()
  return current and current:getName() or ""
end
local function online() return g_game.getLocalPlayer() ~= nil and (not g_game.isOnline or g_game.isOnline()) end

-- This is the same native signal format used by corelib connect/disconnect.
-- The bot sandbox does not expose connect in every client. Keep all existing
-- listeners, including the client's Imbuements window, and remove ours on reload.
local hooks = {}
local function removeSignal(event, callback)
  local listeners = g_game[event]
  if listeners == callback then g_game[event] = nil
  elseif type(listeners) == "table" then
    for i=#listeners,1,-1 do if listeners[i] == callback then table.remove(listeners,i) end end
    if #listeners == 1 then g_game[event] = listeners[1] end
  end
end
local function cleanup()
  if destroyed then return end
  destroyed = true
  for event, callback in pairs(hooks) do removeSignal(event, callback) end
end
local shared = modules.game_bot
if shared and shared.sabuezoImbuementScrollCleanup then shared.sabuezoImbuementScrollCleanup() end
if shared then shared.sabuezoImbuementScrollCleanup = cleanup end
local function addSignal(event, callback)
  local listeners = g_game[event]
  if listeners == nil then g_game[event] = callback
  elseif type(listeners) == "function" then g_game[event] = {listeners,callback}
  elseif type(listeners) == "table" then table.insert(listeners,callback)
  else return false end
  hooks[event] = callback
  return true
end

local function capture(items)
  if destroyed or type(items) ~= "table" then return end
  local data = {}
  for _, raw in pairs(items) do
    if type(raw) == "table" and tonumber(raw.slot) and itemId(raw.item) and type(raw.slots) == "table" then
      local slot, id = tonumber(raw.slot), itemId(raw.item)
      local record = {itemId=id, slots={}, totalSlots=tonumber(raw.totalSlots)}
      local inferred = 0
      for _, buff in pairs(raw.slots) do
        if type(buff) == "table" and tonumber(buff.id) and tonumber(buff.duration) and type(buff.name) == "string" then
          record.slots[#record.slots+1] = {id=tonumber(buff.id), name=buff.name,
            duration=math.max(0,tonumber(buff.duration)), iconId=tonumber(buff.iconId), state=buff.state}
          inferred = math.max(inferred, tonumber(buff.id)+1)
        else record.invalid = true end
      end
      local known = capacity[slot]
      if record.totalSlots then capacity[slot] = {itemId=id, count=record.totalSlots}
      elseif known and known.itemId == id then record.totalSlots = math.max(known.count,inferred)
      elseif inferred > 0 then record.totalSlots = inferred end
      if record.totalSlots then capacity[slot] = {itemId=id,count=record.totalSlots} end
      data[slot] = record
    end
  end
  revision = revision+1
  snapshot = {items=data, at=os.time(), revision=revision, owner=character()}
end
local attached = addSignal("onUpdateImbuementTracker", capture)
addSignal("onGameEnd", function() snapshot, capacity, previousPlayer = nil, {}, nil end)
addSignal("onGameStart", function() snapshot, capacity, nextRequest = nil, {}, 0 end)
local oldDestroy = ui.onDestroy
ui.onDestroy = function(...)
  cleanup()
  if shared and shared.sabuezoImbuementScrollCleanup == cleanup then shared.sabuezoImbuementScrollCleanup = nil end
  if type(oldDestroy) == "function" then oldDestroy(...) end
end

local function requestData(force)
  local time = os.time()
  if not online() or (not force and time < nextRequest) then return end
  nextRequest = time + (config.pending and 2 or 10)
  if type(g_game.imbuementDurations) == "function" then
    pcall(function() g_game.imbuementDurations(true) end)
  end
end
local function fresh()
  return snapshot and snapshot.owner == character() and os.time()-snapshot.at >= 0 and os.time()-snapshot.at <= 20
end
local function activeEffect(record, effect)
  if not record then return nil end
  for _, buff in ipairs(record.slots) do
    if buff.duration > 0 and effectMatches(effect,buff.name) then return buff end
  end
end
local function formatDuration(seconds)
  seconds = math.max(0,math.floor(seconds))
  if seconds >= 3600 then return string.format("%dh %02dm",math.floor(seconds/3600),math.floor(seconds%3600/60)) end
  if seconds >= 60 then return string.format("%dm %02ds",math.floor(seconds/60),seconds%60) end
  return seconds.."s"
end
local function findScroll(id)
  if type(findItem) == "function" then
    local ok, item = pcall(function() return findItem(id) end)
    if ok and item and itemId(item) == id then return item end
  end
  for _, container in pairs(g_game.getContainers()) do
    for _, item in ipairs(container:getItems()) do if itemId(item) == id then return item end end
  end
end
local function stateFor(rule)
  if rule.itemId <= 0 or rule.scrollId <= 0 or rule.effect == "" then return "Arrastra equipo/scroll y elige efecto" end
  local gear = equipped(rule.slot)
  if itemId(gear) ~= rule.itemId then return "Esta pieza no esta equipada en ese lugar" end
  if not fresh() then return "Esperando datos recientes del cliente" end
  local record = snapshot.items[rule.slot]
  if not record or record.itemId ~= rule.itemId then return "El cliente aun no informo esta pieza" end
  if record.invalid then return "Datos incompletos: esperando otra lectura" end
  local buff = activeEffect(record,rule.effect)
  if buff then
    rule.attempts,rule.retryAt,rule.blockReason,rule.lastUseError = 0,0,nil,nil
    return buff.name..": "..formatDuration(buff.duration), false
  end
  if not record.totalSlots then return "Esperando capacidad de imbuements" end
  if rule.blockReason then return rule.blockReason end
  local occupied = 0
  for _, current in ipairs(record.slots) do if current.duration > 0 then occupied=occupied+1 end end
  if occupied >= record.totalSlots then return "Sin espacio libre para "..rule.effect end
  if rule.attempts >= 3 then return (rule.lastUseError or "Sin confirmar")..": pulsa Reintentar" end
  if os.time() < rule.retryAt then
    return (rule.lastUseError and rule.lastUseError..". " or "").."Reintento en "..(rule.retryAt-os.time()).."s"
  end
  if config.onlyPz and not isInPz() then return "Terminado/falta: esperando PZ" end
  if not findScroll(rule.scrollId) then
    if type(g_game.useInventoryItemWith) ~= "function" then
      return "Sin scroll disponible en las BP abiertas"
    end
    -- Inventory hotkey use lets the server resolve this ID in carried bags,
    -- including closed ones. Availability is confirmed by the resulting buff,
    -- not by the presence of the API or a successful Lua call.
    return "Terminado/falta: comprobar scroll en BP cerradas", true
  end
  return "Terminado/falta: listo para aplicar", true
end
local function pendingResult()
  local pending = config.pending
  if not pending then return end
  local rule = ruleById(pending.uid)
  local newData = fresh() and (pending.generation ~= generation or snapshot.revision > number(pending.revision,0))
  local record = newData and snapshot.items[pending.slot]
  if pending.owner == character() and record and record.itemId == pending.itemId and activeEffect(record,pending.effect) then
    if rule then rule.attempts,rule.retryAt,rule.lastUseError = 0,0,nil end
    config.pending = nil
    return
  end
  if pending.owner == character() and record and record.itemId == pending.itemId and not record.invalid then
    for _, buff in ipairs(record.slots) do
      if buff.duration > 0 and not (pending.beforeEffects or {})[buff.id..":"..buff.name] then
        if rule and rule.itemId == pending.itemId and rule.effect == pending.effect then
          rule.blockReason="Otro efecto recibido: "..buff.name..". Revisa scroll/efecto."
          rule.attempts=3
        end
        config.pending=nil
        return
      end
    end
  end
  if os.time()-pending.createdAt >= 10 or os.time() < pending.createdAt or pending.owner ~= character() then
    if rule then
      rule.retryAt = os.time()+30
      rule.lastUseError = pending.source == "inventory_id" and
        "Sin confirmacion: falta scroll o el servidor rechazo su uso por ID" or
        "Sin confirmacion del efecto"
    end
    config.pending = nil
    nextRequest = 0
  end
end
local function apply(rule)
  -- Recheck equipment, fresh server state and scroll immediately before use.
  local _, ready = stateFor(rule)
  if not ready or config.pending then return false end
  local gear, scroll = equipped(rule.slot), findScroll(rule.scrollId)
  if itemId(gear) ~= rule.itemId then return false end
  if scroll then
    if itemId(scroll) ~= rule.scrollId then return false end
  elseif type(g_game.useInventoryItemWith) ~= "function" then return false end
  rule.lastUseError=nil
  rule.attempts = rule.attempts+1
  config.pending = {uid=rule.uid, slot=rule.slot, itemId=rule.itemId, effect=rule.effect,
    owner=character(), createdAt=os.time(), revision=snapshot.revision, generation=generation,
    source=scroll and "open_container" or "inventory_id", beforeEffects={}}
  for _, buff in ipairs(snapshot.items[rule.slot].slots) do
    if buff.duration > 0 then config.pending.beforeEffects[buff.id..":"..buff.name]=true end
  end
  local ok, sent = pcall(function()
    if scroll then return g_game.useWith(scroll,gear) end
    return g_game.useInventoryItemWith(rule.scrollId,gear,0)
  end)
  if not ok or sent == false then
    config.pending=nil;rule.retryAt=os.time()+30
    rule.lastUseError=ok and "El cliente rechazo el uso del scroll" or "Error al usar scroll: "..tostring(sent)
  end
  requestData(true)
  return ok and sent~=false
end

local function effectOptions(rule, widget)
  local wanted, available = rule.effect, {"Elegir efecto"}
  local seen = {}
  for _, effect in ipairs(effects) do available[#available+1]=effect;seen[effect]=true end
  local record = fresh() and snapshot.items[rule.slot]
  if record and record.itemId == rule.itemId then
    for _, buff in ipairs(record.slots) do
      if buff.name ~= "" and not seen[buff.name] then available[#available+1]=buff.name;seen[buff.name]=true end
    end
  end
  if wanted ~= "" and not seen[wanted] then available[#available+1]=wanted end
  binding = true
  widget:clearOptions()
  for _, effect in ipairs(available) do widget:addOption(effect) end
  widget:setCurrentOption(wanted ~= "" and wanted or "Elegir efecto")
  binding = false
end
local eqPanel,piecePanel=window.setup,window.piece
local slotIds={"head","neck","back","body","right-hand","left-hand","legs","feet","finger","ammo"}
local slotWidgets, equipmentRows, effectRows = {},{},{piecePanel.effect1,piecePanel.effect2,piecePanel.effect3}
for slot,id in ipairs(slotIds) do
  local row=UI.createWidget("ImbuementScrollEquipmentRow",eqPanel.list)
  row:setId("eqslot"..slot)
  equipmentRows[slot],slotWidgets[slot]=row,row.gear
end
local drafts,labels = {},{}
local selectedSlot=1
local draft
local render,selectProfile,refreshProfiles

local function family(name)
  for _, effect in ipairs(effects) do if effectMatches(effect,name) then return effect end end
  return name
end
-- IDs from Canary are candidates only. Auto-fill requires a matching name
-- from this client's market/appearance data; customized IDs can be discovered
-- from its market catalog or a real scroll in an open container.
local scrollCatalog,scrollFamilies={},{}
local function catalogName(thing)
  if not thing then return end
  local ok,name=pcall(function() return thing:getMarketData().name end)
  if ok and type(name)=="string" and name~="" then return name end
  ok,name=pcall(function() return thing:getName() end)
  if ok and type(name)=="string" and name~="" then return name end
end
local function registerScroll(thing,id)
  local name=catalogName(thing)
  if not name then return end
  local tier,effect=name:lower():match("^(%a+)%s+(.+)%s+scroll$")
  if tier~="powerful" and tier~="intricate" and tier~="basic" then return end
  effect=family(effect)
  local valid=false
  for _,known in ipairs(effects) do if effect==known then valid=true;break end end
  if not valid then return end
  if not id then local ok,value=pcall(function() return thing:getId() end);id=ok and tonumber(value) end
  if not id or id<=0 or scrollCatalog[id] then return end
  scrollCatalog[id]={id=id,name=name,effect=effect,tier=tier}
  scrollFamilies[effect]=scrollFamilies[effect] or {}
  scrollFamilies[effect][tier]=scrollFamilies[effect][tier] or {}
  table.insert(scrollFamilies[effect][tier],id)
end
local function refreshScrollCatalog()
  if g_things and type(g_things.findThingTypeByAttr)=="function" and ThingAttrMarket then
    local ok,types=pcall(function() return g_things.findThingTypeByAttr(ThingAttrMarket,0) end)
    if ok and type(types)=="table" then for _,thing in pairs(types) do registerScroll(thing) end end
  end
  if g_things and type(g_things.getThingType)=="function" then
    for _,range in ipairs({{51444,51467},{51724,51747}}) do
      for id=range[1],range[2] do
        local ok,thing=pcall(function() return g_things.getThingType(id,ThingCategoryItem or 0) end)
        if ok then registerScroll(thing,id) end
      end
    end
  end
  for _,container in pairs(g_game.getContainers()) do
    for _,item in ipairs(container:getItems()) do registerScroll(item,itemId(item)) end
  end
end
local function catalogScroll(effect,preferredName)
  local tiers=scrollFamilies[family(effect)]
  if not tiers then return 0 end
  local tier=tostring(preferredName or ""):lower():match("^(%a+)%s") or "powerful"
  if tier~="powerful" and tier~="intricate" and tier~="basic" then tier="powerful" end
  local candidates=tiers[tier] or {}
  local available
  for _,id in ipairs(candidates) do
    if findScroll(id) then if available then return 0 end;available=id end
  end
  return available or (#candidates==1 and candidates[1] or 0)
end
local function copyBinding(rule)
  return {uid=rule.uid,effect=rule.effect,scrollId=rule.scrollId,enabled=rule.enabled}
end
local function slotBindings(profile,slot,id)
  local result={}
  for _, rule in ipairs(profile.rules) do
    if rule.slot==slot and rule.itemId==id and rule.effect~="" then result[#result+1]=copyBinding(rule) end
  end
  for index=#result+1,3 do result[index]={effect="",scrollId=0,enabled=false} end
  return result
end
local function createDraft(profile)
  local result={name=profile.name,equipment={},bindings={},dirty=false}
  for slot=1,10 do
    result.equipment[slot]=profile.equipment[slot] or 0
    result.bindings[slot]=slotBindings(profile,slot,result.equipment[slot])
  end
  return result
end
local function markDirty()
  draft.dirty=true
  piecePanel.status:setText("Cambios sin guardar: pulsa Guardar.")
end
local function knownScroll(effect,preferredName)
  local found
  for _, profile in ipairs(config.profiles) do
    for _, rule in ipairs(profile.rules) do
      if rule.scrollId>0 and family(rule.effect)==family(effect) then
        if found and found~=rule.scrollId then return 0 end
        found=rule.scrollId
      end
    end
  end
  return found or catalogScroll(effect,preferredName)
end
local function knownEffect(scrollId)
  if scrollCatalog[scrollId] then return scrollCatalog[scrollId].effect end
  local found
  for _, profile in ipairs(config.profiles) do
    for _, rule in ipairs(profile.rules) do
      if rule.scrollId==scrollId and rule.effect~="" then
        local effect=family(rule.effect)
        if found and found~=effect then return nil end
        found=effect
      end
    end
  end
  return found
end
-- Read every equipped piece as the native Imbuement Tracker does. Only fill
-- missing effects; expiry and subsequent tracker frames never erase a setup.
local function detectAll()
  if not fresh() then return false end
  local changed=false
  for slot=1,10 do
    local record=snapshot.items[slot]
    if record and not record.invalid and record.itemId==draft.equipment[slot] then
      local ordered={}
      for _, buff in ipairs(record.slots) do if buff.duration>0 then ordered[#ordered+1]=buff end end
      table.sort(ordered,function(a,b) return a.id<b.id end)
      for _, buff in ipairs(ordered) do
        local effect,found,empty=family(buff.name),false,nil
        for _, entry in ipairs(draft.bindings[slot]) do
          if family(entry.effect)==effect then found=true end
          if entry.effect=="" and not empty then empty=entry end
        end
        if not found and empty then
          empty.effect,empty.enabled=effect,true
          if empty.scrollId==0 then empty.scrollId=knownScroll(effect,buff.name) end
          changed=true
        end
      end
    end
  end
  for slot,entries in ipairs(draft.bindings) do
    local record=snapshot.items[slot]
    for _,entry in ipairs(entries) do
      if entry.effect~="" and entry.scrollId==0 then
        local buff=record and record.itemId==draft.equipment[slot] and activeEffect(record,entry.effect)
        local id=knownScroll(entry.effect,buff and buff.name)
        if id>0 then entry.scrollId=id;changed=true end
      end
    end
  end
  if changed then markDirty() end
  return changed
end
local function setDraftGear(slot,id)
  if draft.equipment[slot]~=id then
    draft.equipment[slot]=id
    draft.bindings[slot]=slotBindings(currentProfile,slot,id)
    markDirty()
  end
end
local defaultTrackerSlots={[1]=true,[3]=true,[4]=true,[5]=true,[6]=true,[8]=true}
local function compactDuration(seconds)
  if seconds>=3600 then return math.floor(seconds/3600).."h" end
  if seconds>=60 then return math.floor(seconds/60).."m" end
  return math.floor(seconds).."s"
end

-- Mythic's tracker uses different image resources from the public OTClient
-- icons/<id> layout. Read the actual native slot's source AND atlas clip: the
-- native artwork already contains the effect symbol and its tier dots.
local nativeIcons = {}
local function widgetCall(widget, method, ...)
  if not widget or type(widget[method])~="function" then return nil end
  local ok,value=pcall(widget[method],widget,...)
  return ok and value or nil
end
local function childById(widget,id)
  return widgetCall(widget,"getChildById",id) or widgetCall(widget,"recursiveGetChildById",id)
end
local function nativeTracker()
  local trackerModule=modules.game_imbuementtracker
  if trackerModule and trackerModule.imbuementTracker then return trackerModule.imbuementTracker end
  local root=g_ui.getRootWidget()
  return childById(root,"imbuementTracker") or childById(root,"imbuementtracker")
end
local function iconKey(buff)
  return tostring(buff.iconId or "")..":"..normalized(buff.name)
end
local function readNativeIcons()
  if not fresh() then return end
  local contents=childById(nativeTracker(),"contentsPanel")
  for _,row in ipairs(widgetCall(contents,"getChildren") or {}) do
    local gear=childById(row,"item")
    local gearId=widgetCall(gear,"getItemId") or itemId(widgetCall(gear,"getItem"))
    local holder=childById(row,"imbuementSlots")
    local children=widgetCall(holder,"getChildren") or {}
    if gearId and holder then
      for _,record in pairs(snapshot.items) do
        if record.itemId==gearId then
          for _,buff in ipairs(record.slots) do
            if buff.duration>0 then
              local nativeSlot=childById(holder,"slot"..buff.id) or children[buff.id+1]
              local source=widgetCall(nativeSlot,"getImageSource")
              if type(source)=="string" and source~="" and not source:find("slot_inactive",1,true) then
                nativeIcons[iconKey(buff)]={source=source,clip=widgetCall(nativeSlot,"getImageClip")}
              end
            end
          end
        end
      end
    end
  end
end
local function imageExists(path)
  if not g_resources or type(g_resources.fileExists)~="function" then return true end
  local ok,exists=pcall(g_resources.fileExists,path..".png")
  return ok and exists==true
end
local function effectAppearance(buff)
  -- Ship the actual 64x64 effect artwork with the bot. Mythic does not contain
  -- the public icons/<id> files, and its hidden tracker can expose only a frame.
  -- These PNGs include the effect AND tier dots, so no native window is needed.
  if buff.iconId then
    local directory=(type(configDir)=="string" and configDir or "/bot/Sabuezo2").."/vBot/imbuement_icons/"
    local path=directory..buff.iconId
    if imageExists(path) then return {source=path,clip={x=0,y=0,width=64,height=64}} end
  end
  local appearance=nativeIcons[iconKey(buff)]
  if appearance then return appearance end
  -- Other clients can still use the public individual-icon layout. Check it
  -- first so this client never repeatedly logs missing icon textures.
  if buff.iconId then
    local path="/images/game/imbuing/icons/"..buff.iconId
    if imageExists(path) then return {source=path,clip={x=0,y=0,width=64,height=64}} end
  end
end
local function setEffectImage(cell,appearance)
  local source=appearance and appearance.source or "/images/game/imbuing/slot_inactive"
  if cell.imbuementImageSource~=source then cell:setImageSource(source);cell.imbuementImageSource=source end
  if type(cell.setImageClip)=="function" then
    cell:setImageClip(appearance and appearance.clip or {x=0,y=0,width=64,height=64})
  end
end
local function renderEquipment()
  readNativeIcons()
  local position=0
  for slot,row in ipairs(equipmentRows) do
    local id=draft.equipment[slot]
    local record=fresh() and snapshot.items[slot]
    if record and record.itemId~=id then record=nil end
    local configured=false
    for _,entry in ipairs(draft.bindings[slot]) do if entry.effect~="" then configured=true;break end end
    local tracked=record and ((record.totalSlots or 0)>0 or #record.slots>0)
    local shown=slot==selectedSlot or configured or (id>0 and
      (tracked or (not fresh() and defaultTrackerSlots[slot])))
    row:setVisible(shown)
    if shown then row:setMarginTop(position);position=position+37 end
    row:setTooltip(slots[slot][2]..": clic para configurar sus scrolls")
    local count=record and record.totalSlots or 0
    if not record then
      for _,entry in ipairs(draft.bindings[slot]) do if entry.effect~="" then count=count+1 end end
    end
    for index=1,3 do
      local cell=row["buff"..index]
      local buff
      if record then for _,entry in ipairs(record.slots) do if entry.id==index-1 then buff=entry;break end end end
      cell:setVisible(index<=math.min(3,count))
      if buff and buff.duration>0 then
        setEffectImage(cell,effectAppearance(buff))
        cell.duration:setText(compactDuration(buff.duration))
        cell.duration:setColor(buff.duration<3600 and "#ff5555" or buff.duration<10800 and "#ffff00" or "#ffffff")
        cell:setTooltip(buff.name..": "..formatDuration(buff.duration))
      else
        setEffectImage(cell)
        cell.duration:setText("")
        cell:setTooltip(record and "Slot de imbuement libre" or "Esperando tiempos del cliente")
      end
    end
  end
end
render = function()
  binding=true
  window.name:setText(draft.name)
  for slot,widget in ipairs(slotWidgets) do
    widget:setItemId(draft.equipment[slot])
    widget:setOn(draft.equipment[slot]>0)
    widget:setChecked(slot==selectedSlot)
  end
  binding=false
  renderEquipment()
  eqPanel.selectedPiece:setText("Pieza: "..slots[selectedSlot][2])
  piecePanel.title:setText(slots[selectedSlot][2])
  local record=fresh() and snapshot.items[selectedSlot]
  local count=3
  if record and record.itemId==draft.equipment[selectedSlot] and record.totalSlots then
    count=math.max(0,math.min(3,record.totalSlots))
  end
  for index,entry in ipairs(draft.bindings[selectedSlot]) do
    if entry.effect~="" then count=math.max(count,index) end
  end
  for index,row in ipairs(effectRows) do
    local entry=draft.bindings[selectedSlot][index]
    binding=true
    row.enabled:setChecked(entry.enabled)
    row.scroll:setItemId(entry.scrollId)
    local scroll=scrollCatalog[entry.scrollId]
    row.scroll:setTooltip(scroll and scroll.name.." (ID "..entry.scrollId..")" or
      entry.scrollId>0 and "Scroll ID "..entry.scrollId or "Arrastra el scroll de este efecto")
    row:setVisible(index<=count)
    binding=false
    effectOptions({slot=selectedSlot,itemId=draft.equipment[selectedSlot],effect=entry.effect},row.effect)
  end
end
refreshProfiles = function()
  binding=true
  window.profiles:clearOptions()
  labels={}
  local seen={}
  for _, profile in ipairs(config.profiles) do
    local text=profile.name
    if seen[text] then text=text.." ("..profile.uid..")" end
    seen[text]=true;labels[profile.uid]=text
    window.profiles:addOption(text)
  end
  window.profiles:setCurrentOption(labels[currentProfile.uid])
  binding=false
end
selectProfile = function(profile)
  currentProfile=profile
  config.currentProfileId=profile.uid
  config.rules=profile.rules
  draft=drafts[profile.uid] or createDraft(profile)
  drafts[profile.uid]=draft
  selectedSlot=1
  detectAll();render()
  refreshProfiles()
end
local function copyEquipment()
  for slot=1,10 do setDraftGear(slot,itemId(equipped(slot)) or 0) end
  detectAll();render();requestData(true)
end
for slot,widget in ipairs(slotWidgets) do
  local inventorySlot=slot
  widget:setTooltip(slots[slot][2]..": clic para configurar sus scrolls. Arrastra otra pieza para cambiarla.")
  widget.onClick=function() selectedSlot=inventorySlot;detectAll();render() end
  equipmentRows[slot].onClick=widget.onClick
  for index=1,3 do equipmentRows[slot]["buff"..index].onClick=widget.onClick end
  widget.onItemChange=function()
    widget:setOn(widget:getItemId()>0)
    if binding then return end
    setDraftGear(inventorySlot,widget:getItemId())
    selectedSlot=inventorySlot
    detectAll();render();requestData(true)
  end
end
for index,row in ipairs(effectRows) do
  local effectIndex=index
  row.enabled.onClick=function()
    local entry=draft.bindings[selectedSlot][effectIndex]
    entry.enabled=not entry.enabled;row.enabled:setChecked(entry.enabled);markDirty()
  end
  row.scroll.onItemChange=function(widget)
    if binding then return end
    local entry=draft.bindings[selectedSlot][effectIndex]
    entry.scrollId=widget:getItemId()
    if entry.effect=="" then
      local guessed=knownEffect(entry.scrollId)
      if guessed then entry.effect=guessed;entry.enabled=true end
    end
    markDirty();render()
  end
  row.effect.onOptionChange=function(_,text)
    if binding then return end
    local entry=draft.bindings[selectedSlot][effectIndex]
    local wasEmpty=entry.effect==""
    entry.effect=text=="Elegir efecto" and "" or text
    if wasEmpty and entry.effect~="" then entry.enabled=true end
    if entry.scrollId==0 and entry.effect~="" then entry.scrollId=knownScroll(entry.effect) end
    markDirty();render()
  end
end
window.name.onTextChange=function(_,text)
  if binding then return end
  draft.name=tostring(text or "");markDirty()
end
window.profiles.onOptionChange=function(_,text)
  if binding then return end
  for _, profile in ipairs(config.profiles) do if labels[profile.uid]==text then selectProfile(profile);break end end
end
window.addProfile.onClick=function()
  if #config.profiles>=20 then piecePanel.status:setText("Limite de 20 perfiles");return end
  local profile={uid=config.nextProfileId,name="Perfil "..config.nextProfileId,equipment={},rules={}}
  for slot=1,10 do profile.equipment[slot]=0 end
  config.nextProfileId=config.nextProfileId+1
  config.profiles[#config.profiles+1]=profile
  selectProfile(profile);copyEquipment()
end
window.removeProfile.onClick=function()
  for index,profile in ipairs(config.profiles) do
    if profile==currentProfile then
      drafts[profile.uid]=nil;table.remove(config.profiles,index);break
    end
  end
  if #config.profiles==0 then
    local profile={uid=config.nextProfileId,name="Principal",equipment={},rules={}}
    for slot=1,10 do profile.equipment[slot]=0 end
    config.profiles[1]=profile;config.nextProfileId=config.nextProfileId+1
  end
  selectProfile(config.profiles[1])
end
local function saveProfile()
  if config.pending then
    local _,ownerProfile=ruleById(config.pending.uid)
    if ownerProfile==currentProfile then piecePanel.status:setText("Espera la confirmacion del scroll enviado");return false end
  end
  local name=draft.name:gsub("^%s+", ""):gsub("%s+$", ""):sub(1,40)
  if name=="" then piecePanel.status:setText("Pon un nombre al perfil");return false end
  for _, profile in ipairs(config.profiles) do
    if profile~=currentProfile and profile.name==name then piecePanel.status:setText("Ese nombre ya pertenece a otro perfil");return false end
  end
  -- Validate first, so a failed save never changes an active profile halfway.
  for slot,entries in ipairs(draft.bindings) do
    local seen={}
    for _, entry in ipairs(entries) do
      if entry.effect~="" then
        local key=family(entry.effect)
        if seen[key] then piecePanel.status:setText("Efecto repetido en "..slots[slot][2]);return false end
        seen[key]=true
      end
      if entry.scrollId>0 and (entry.effect=="" or draft.equipment[slot]==0) then
        piecePanel.status:setText("Falta pieza o efecto para un scroll");return false
      end
      local scroll=scrollCatalog[entry.scrollId]
      if scroll and family(entry.effect)~=scroll.effect then
        piecePanel.status:setText("Ese scroll es de "..scroll.effect..", revisa el efecto");return false
      end
    end
  end
  local newRules,alternates={},{}
  for _, old in ipairs(currentProfile.rules) do
    if old.itemId>0 and old.itemId~=currentProfile.equipment[old.slot] then alternates[#alternates+1]=old end
  end
  for slot,entries in ipairs(draft.bindings) do
    for _, entry in ipairs(entries) do
      if entry.effect~="" and draft.equipment[slot]>0 then
        local old,owner=ruleById(entry.uid)
        local rule=owner==currentProfile and old or nil
        if not rule then
          rule={uid=config.nextId,attempts=0,retryAt=0};config.nextId=config.nextId+1
        end
        local changed=rule.slot~=slot or rule.itemId~=draft.equipment[slot] or
          rule.effect~=entry.effect or rule.scrollId~=entry.scrollId
        rule.slot,rule.itemId,rule.effect,rule.scrollId=slot,draft.equipment[slot],entry.effect,entry.scrollId
        rule.enabled=entry.enabled
        if changed then rule.attempts,rule.retryAt,rule.blockReason,rule.lastUseError=0,0,nil,nil end
        newRules[#newRules+1]=rule
      end
    end
  end
  -- Preserve imported alternate pieces which the old flat list allowed in a slot.
  local used={}
  for _, rule in ipairs(newRules) do used[rule.uid]=true end
  for _, old in ipairs(alternates) do
    if not used[old.uid] then newRules[#newRules+1]=old;used[old.uid]=true end
  end
  currentProfile.name,currentProfile.rules=name,newRules
  for slot=1,10 do currentProfile.equipment[slot]=draft.equipment[slot] end
  config.rules=newRules
  drafts[currentProfile.uid]=nil
  selectProfile(currentProfile)
  piecePanel.status:setText("Perfil guardado")
  requestData(true)
  return true
end
window.saveProfile.onClick=saveProfile
local function setEnabled(value)
  config.enabled=value
  ui.title:setOn(value)
  window.enabled:setOn(value)
  window.enabled:setText(value and "Activo" or "Activar")
  if value then requestData(true) end
end
ui.title.onClick=function()
  if config.enabled then setEnabled(false);return end
  if draft.dirty and not saveProfile() then return end
  setEnabled(true)
end
window.enabled.onClick=ui.title.onClick
setEnabled(config.enabled)
window.onlyPz:setChecked(config.onlyPz)
window.onlyPz.onCheckChange=function(_,checked) config.onlyPz=checked==true end
ui.settings.onClick=function()
  window:show();window:raise();window:focus()
  refreshScrollCatalog()
  local any=false
  for _, id in ipairs(draft.equipment) do if id>0 then any=true;break end end
  if not any then copyEquipment() else detectAll();render();requestData(true) end
end
eqPanel.cloneEq.onClick=copyEquipment
window.refresh.onClick=function() refreshScrollCatalog();detectAll();render();requestData(true) end
window.retry.onClick=function()
  for _, rule in ipairs(config.rules) do
    if rule.slot==selectedSlot and rule.itemId==draft.equipment[selectedSlot] then rule.attempts,rule.retryAt,rule.blockReason,rule.lastUseError=0,0,nil,nil end
  end
  requestData(true)
end
window.close.onClick=function() window:hide() end
refreshScrollCatalog()
selectProfile(currentProfile)

local seenRevision=-1
macro(500,function()
  if destroyed then return end
  local current=g_game.getLocalPlayer()
  if current~=previousPlayer then previousPlayer=current;snapshot=nil;capacity={};nextRequest=0 end
  if not online() then ui.status:setText("Desconectado");return end
  if config.enabled or window:isVisible() or config.pending then requestData(false) end
  pendingResult()
  if snapshot and snapshot.revision~=seenRevision then
    seenRevision=snapshot.revision
    detectAll()
    -- Keep renewal data current while hunting, and rebuild the equipment and
    -- effect selectors only when the settings window is actually visible.
    -- Opening settings already renders the latest snapshot.
    if window:isVisible() then render() end
  end
  local readyRule,enabledCount=nil,0
  for _, rule in ipairs(config.rules) do
    local _,ready=stateFor(rule)
    if rule.enabled then enabledCount=enabledCount+1;if ready and not readyRule then readyRule=rule end end
  end
  for index,row in ipairs(effectRows) do
    local entry=draft.bindings[selectedSlot][index]
    local text,ready
    if entry.effect=="" then text="Sin configurar"
    elseif entry.scrollId==0 then
      local record=fresh() and snapshot.items[selectedSlot]
      local buff=record and record.itemId==draft.equipment[selectedSlot] and activeEffect(record,entry.effect)
      text=(buff and formatDuration(buff.duration).." - " or "").."Arrastra su scroll"
    else
      local saved,owner=ruleById(entry.uid)
      local preview={slot=selectedSlot,itemId=draft.equipment[selectedSlot],effect=entry.effect,
        scrollId=entry.scrollId,attempts=0,retryAt=0}
      local matches=owner==currentProfile and saved and saved.slot==selectedSlot and
        saved.itemId==preview.itemId and saved.effect==entry.effect and
        saved.scrollId==entry.scrollId and saved.enabled==entry.enabled
      text,ready=stateFor(matches and saved or preview)
      if ready and not matches then text,ready="Sin guardar: pulsa Guardar",false end
      if matches and config.pending and config.pending.uid==saved.uid then text="Confirmando scroll" end
    end
    row.duration:setText((not entry.enabled and entry.effect~="" and "[Off] " or "")..text)
    row.duration:setTooltip(text)
    row.duration:setColor(ready and "#ffcc66" or "#aaaaaa")
  end
  local sourceText=fresh() and "Renovar cuando termine el efecto." or "Esperando tiempos del cliente."
  if not attached then sourceText="No se pudo conectar el lector de imbuements." end
  piecePanel.status:setText(draft.dirty and "Cambios sin guardar: pulsa Guardar." or sourceText)
  if not config.enabled then ui.status:setText("Desactivado")
  elseif config.pending then ui.status:setText("Confirmando scroll")
  elseif enabledCount==0 then ui.status:setText(draft.dirty and "Pulsa Guardar" or "Guarda equipo y scrolls")
  elseif not fresh() then ui.status:setText("Esperando datos del cliente")
  elseif readyRule then
    local sent=apply(readyRule)
    ui.status:setText(sent and "Aplicando "..readyRule.effect or "Uso del scroll rechazado")
  else ui.status:setText(currentProfile.name) end
end)

ImbuementScrolls={show=function() ui.settings.onClick() end,cleanup=cleanup,
  getSnapshot=function() return snapshot end,getScrollCatalog=function() return scrollCatalog end}
