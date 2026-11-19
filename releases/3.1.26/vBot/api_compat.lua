--[[
  api_compat - guarded facade over g_game / g_things.

  Helper modules call these functions instead of g_game.* / g_things.* when
  the native function may not exist (or may fail) in another OTC client.
  Nothing is patched on g_game or g_things: this file only reads them, so it
  composes with aurera_compat's proxies and never changes the client.

  A missing or failing native function never raises an error here. It returns
  a safe default and is recorded in ApiCompat.missing / ApiCompat.failed, which
  the diagnostics panel (vBot/ClientDiagnostics.lua) shows.
]]

ApiCompat = ApiCompat or {}
local A = ApiCompat

A.missing = A.missing or {}   -- "g_game.name" -> times it was called while absent
A.failed  = A.failed  or {}   -- "g_game.name" -> {count=n, error=last message}
A.assumedVersion = 1300       -- used only when the client reports no version

local warnLimit, warned = 8, 0
local warnedKeys = {}
local function warnOnce(key, message)
  if warnedKeys[key] then return end
  warnedKeys[key] = true
  warned = warned + 1
  if warned > warnLimit or type(warn) ~= 'function' then return end
  pcall(warn, 'ApiCompat: ' .. message)
end

-- Probe lists for the diagnostics panel.
A.gameProbe = {
  'getClientVersion', 'getProtocolVersion', 'getFeature', 'getContainers', 'getPing',
  'getLocalPlayer', 'getAttackingCreature', 'getChaseMode', 'setChaseMode',
  'attack', 'cancelAttack', 'cancelAttackAndFollow', 'isAttacking',
  'open', 'use', 'useWith', 'useInventoryItem', 'useInventoryItemWith',
  'findPlayerItem', 'equipItem', 'equipItemId', 'move', 'stop', 'walk', 'autoWalk',
  'talk', 'sendQuickLoot', 'quickLoot', 'setNextTalkAim',
}
A.thingsProbe = { 'getThingType', 'getThingTypes', 'isDatLoaded', 'getDatSignature' }

local function owner(name)
  if name == 'g_game' then return g_game end
  if name == 'g_things' then return g_things end
  return nil
end

local function record(tbl, key, extra)
  local entry = tbl[key]
  if type(entry) ~= 'table' then
    entry = {count = 0}
    tbl[key] = entry
  end
  entry.count = entry.count + 1
  if extra then entry.error = extra end
end

-- Generic guarded call. Looks the function up on every call, so late-installed
-- functions and replaced proxies are honoured.
local function invoke(ownerName, fname, default, ...)
  local object = owner(ownerName)
  local fn = object and object[fname]
  local key = ownerName .. '.' .. fname
  if type(fn) ~= 'function' then
    record(A.missing, key)
    warnOnce('missing:' .. key, key .. ' no existe en este cliente; se usa un valor por defecto')
    return default
  end
  -- Failures are recorded right here (A.failed); keep them out of "Errores ocultos" too.
  local ok, result = (HelperErrors and HelperErrors.originalPcall or pcall)(fn, ...)
  if not ok then
    record(A.failed, key, tostring(result))
    warnOnce('failed:' .. key, key .. ' fallo: ' .. tostring(result))
    return default
  end
  if result == nil then return default end
  return result
end

function A.callGame(fname, default, ...)   return invoke('g_game', fname, default, ...) end
function A.callThings(fname, default, ...) return invoke('g_things', fname, default, ...) end

function A.has(fname)       return type(g_game) ~= 'nil' and type(g_game[fname]) == 'function' end
function A.hasThings(fname) return type(g_things) ~= 'nil' and type(g_things[fname]) == 'function' end

-- ---------------------------------------------------------------------------
-- Versions
-- ---------------------------------------------------------------------------
local cachedClientVersion, cachedProtocolVersion

function A.clientVersion()
  if cachedClientVersion then return cachedClientVersion end
  local v = tonumber(A.callGame('getClientVersion', nil))
  if not v or v <= 0 then v = tonumber(A.callGame('getProtocolVersion', nil)) end
  if v and v > 0 then
    cachedClientVersion = v
    return v
  end
  return A.assumedVersion
end

function A.protocolVersion()
  if cachedProtocolVersion then return cachedProtocolVersion end
  local v = tonumber(A.callGame('getProtocolVersion', nil))
  if v and v > 0 then
    cachedProtocolVersion = v
    return v
  end
  return A.clientVersion()
end

-- ---------------------------------------------------------------------------
-- g_game
-- ---------------------------------------------------------------------------
function A.getContainers()
  local list = A.callGame('getContainers', nil)
  if type(list) == 'table' then return list end
  return {}
end

function A.ping()
  return tonumber(A.callGame('getPing', 0)) or 0
end

function A.open(container, previous)
  if previous ~= nil then return A.callGame('open', false, container, previous) end
  return A.callGame('open', false, container)
end

function A.useWith(item, target, subType)
  return A.callGame('useWith', false, item, target, subType)
end

function A.findPlayerItem(itemId, subType)
  return A.callGame('findPlayerItem', nil, itemId, subType)
end

function A.stop()
  return A.callGame('stop', false)
end

function A.move(item, destination, count)
  return A.callGame('move', false, item, destination, count or 1)
end

-- ---------------------------------------------------------------------------
-- g_things
-- ---------------------------------------------------------------------------
function A.getThingType(id, category)
  if category == nil then return A.callThings('getThingType', nil, id) end
  return A.callThings('getThingType', nil, id, category)
end

function A.datLoaded()
  return A.callThings('isDatLoaded', false) == true
end

function A.datSignature()
  if not A.hasThings('getDatSignature') then return nil end
  local ok, sig = pcall(g_things.getDatSignature)
  if ok then return sig end
  return nil
end

-- ---------------------------------------------------------------------------
-- Reporting (read by the diagnostics panel)
-- ---------------------------------------------------------------------------
function A.probe()
  local result = {game = {}, things = {}}
  for _, name in ipairs(A.gameProbe)   do result.game[name]   = A.has(name) end
  for _, name in ipairs(A.thingsProbe) do result.things[name] = A.hasThings(name) end
  return result
end

function A.report()
  return {
    clientVersion = A.clientVersion(),
    protocolVersion = A.protocolVersion(),
    versionAssumed = not (cachedClientVersion ~= nil),
    probe = A.probe(),
    missing = A.missing,
    failed = A.failed,
  }
end

-- ---------------------------------------------------------------------------
-- GENERATED by scanning every client function this bot calls (g_game, g_map, ...).
-- survey() checks which of them exist in the running client.
-- Names defined by the bot itself (client_compat shims) can show as present.
-- ---------------------------------------------------------------------------
A.surveyList = {
  g_game = {'attack', 'autoWalk', 'buyItem', 'cancelAttack', 'cancelAttackAndFollow', 'cancelFollow', 'close', 'equipItem', 'equipItemId', 'findPlayerItem', 'follow', 'getAttackingCreature', 'getCharacterName', 'getChaseMode', 'getClientVersion', 'getContainers', 'getFeature', 'getFollowingCreature', 'getImbuementDurations', 'getInventoryItem', 'getLocalPlayer', 'getPing', 'getProtocolGame', 'getServerHost', 'getUnjustifiedPoints', 'getWorldName', 'imbuementDurations', 'isAttacking', 'isDead', 'isFollowing', 'isOnline', 'joinChannel', 'leaveChannel', 'look', 'move', 'onGameEnd', 'onSupplyTracker', 'open', 'partyLeave', 'quickLoot', 'requestStashRetrieveItem', 'rinoReconnectApi', 'safeLogout', 'sendQuickLoot', 'setChaseMode', 'setNextTalkAim', 'stashWithdraw', 'stop', 'talk', 'talkChannel', 'turn', 'unequipItem', 'use', 'useInventoryItem', 'useInventoryItemWith', 'useWith', 'walk'},
  g_things = {'findThingTypeByAttr', 'getCreatureBoundingBox', 'getDatSignature', 'getThingType', 'getThingTypes', 'isDatLoaded'},
  g_map = {'getAwareRange', 'getCreatureById', 'getMinimapColor', 'getSpectators', 'getSpectatorsInRange', 'getTile', 'getTiles', 'isSightClear'},
  g_ui = {'createWidget', 'getRootWidget', 'importStyle', 'importStyleFromString', 'loadUIFromString'},
  g_resources = {'directoryExists', 'fileExists', 'getWriteDir', 'listDirectoryFiles', 'makeDir', 'readFileContents', 'writeFileContents'},
  g_window = {'flash', 'setClipboardText', 'setTitle'},
  g_settings = {'getBoolean', 'getNumber', 'save', 'set'},
  g_clock = {'millis'},
  g_keyboard = {'isKeyPressed'},
  g_mouse = {'isPressed'},
  g_platform = {'openUrl'},
  g_app = {'getOs'},
  g_http = {'download', 'get'},
}

-- Returns {present = {table = {names}}, missing = {table = {names}}, total = n, absent = n}
function A.survey()
  local result = {present = {}, missing = {}, total = 0, absent = 0}
  -- Explicit references: the bot sandbox does not expose _G by name.
  local objects = {g_game = g_game, g_things = g_things, g_map = g_map, g_ui = g_ui,
    g_resources = g_resources, g_window = g_window, g_settings = g_settings, g_clock = g_clock,
    g_keyboard = g_keyboard, g_mouse = g_mouse, g_platform = g_platform, g_app = g_app, g_http = g_http}
  for tableName, names in pairs(A.surveyList) do
    local object = objects[tableName]
    result.present[tableName], result.missing[tableName] = {}, {}
    for _, name in ipairs(names) do
      result.total = result.total + 1
      local exists = false
      if object ~= nil then
        local ok, value = pcall(function() return object[name] end)
        exists = ok and type(value) == 'function'
      end
      local bucket = exists and result.present or result.missing
      bucket[tableName][#bucket[tableName] + 1] = name
      if not exists then result.absent = result.absent + 1 end
    end
  end
  return result
end

-- ---------------------------------------------------------------------------
-- GENERATED: object methods the bot calls as player:x(), creature:x(), tile:x(),
-- item:x() and container:x() (variable-name based, so a few names may belong to
-- other objects). surveyMethods() checks them against live objects.
-- ---------------------------------------------------------------------------
A.methodList = {
  player = {'autoWalk', 'getDirection', 'getExperience', 'getFreeCapacity', 'getHealthPercent', 'getId', 'getInventoryItem', 'getItem', 'getItemsCount', 'getLevel', 'getLevelPercent', 'getMagicLevel', 'getMagicLevelPercent', 'getMana', 'getManaPercent', 'getManaShield', 'getMaxMana', 'getName', 'getPosition', 'getRegenerationTime', 'getSkillBaseLevel', 'getSkillLevel', 'getSkillLevelPercent', 'getStepDuration', 'getVocation', 'isDead', 'isWalking'},
  creature = {'attachEffect', 'canShoot', 'detachEffect', 'getAttachedEffects', 'getDirection', 'getEmblem', 'getHealthPercent', 'getId', 'getManaPercent', 'getName', 'getOutfit', 'getPosition', 'getShield', 'getText', 'getType', 'getVocation', 'gsub', 'isItem', 'isLocalPlayer', 'isMonster', 'isNpc', 'isPartyMember', 'isPlayer', 'isTimedSquareVisible', 'isWalking', 'lower', 'match', 'setMarked', 'setOutfit', 'setText', 'setTooltip'},
  tile = {'canShoot', 'getCreatures', 'getGround', 'getItems', 'getMinimapColorByte', 'getPosition', 'getText', 'getThingCount', 'getTopCreature', 'getTopMoveThing', 'getTopThing', 'getTopUseThing', 'hasCreature', 'hasElevation', 'isBlocking', 'isWalkable', 'setBackgroundColor', 'setBorderColor', 'setBorderWidth', 'setFocusable', 'setItemId', 'setMarginLeft', 'setMarginTop', 'setPhantom', 'setSize', 'setText', 'setTimer', 'setVirtual'},
  item = {'addAnchor', 'breakAnchors', 'getCount', 'getId', 'getMarketData', 'getName', 'getPosition', 'getTooltip', 'hide', 'isAmmo', 'isBlocking', 'isContainer', 'isGround', 'isGroundBorder', 'isItem', 'isMagicField', 'isNotMoveable', 'isPickupable', 'isStackable', 'len', 'raise', 'setItemCount', 'setItemVisible', 'setMarginLeft', 'setMarginRight', 'setMarginTop', 'setOpacity', 'setShowCount', 'setSize', 'setTooltip', 'setVisible'},
  container = {'getCapacity', 'getChildByIndex', 'getContainerItem', 'getFirstIndex', 'getId', 'getItems', 'getItemsCount', 'getName', 'getSize', 'getSlotPosition', 'hasPages', 'isContainer', 'setMarked'},
}

local function firstOf(fn)
  local ok, value = pcall(fn)
  if ok then return value end
  return nil
end

-- Returns {subjects = {class = 'what was probed' | false}, missing = {class = {names}}, total, absent}
function A.surveyMethods()
  local result = {subjects = {}, missing = {}, total = 0, absent = 0}
  local lp = player
  local subjects = {player = lp}
  subjects.creature = firstOf(function()
    for _, spec in pairs(getSpectators()) do
      if spec ~= lp and spec:isMonster() then return spec end
    end
    return nil
  end) or lp
  subjects.tile = firstOf(function() return g_map.getTile(lp:getPosition()) end)
  subjects.item = firstOf(function()
    for slot = 1, 11 do
      local item = lp:getInventoryItem(slot)
      if item then return item end
    end
    return nil
  end)
  subjects.container = firstOf(function()
    for _, container in pairs(g_game.getContainers()) do return container end
    return nil
  end)
  local labels = {creature = (subjects.creature ~= lp) and 'monstruo visible' or 'solo el jugador (sin monstruos cerca)'}
  for class, names in pairs(A.methodList) do
    local subject = subjects[class]
    if subject == nil then
      result.subjects[class] = false
    else
      result.subjects[class] = labels[class] or 'objeto real'
      result.missing[class] = {}
      for _, name in ipairs(names) do
        result.total = result.total + 1
        local ok, value = pcall(function() return subject[name] end)
        local present = ok and type(value) == 'function'
        -- A monster legitimately lacks Player-only methods (isPartyMember, ...):
        -- count a creature method as missing only if the player lacks it too.
        if not present and class == 'creature' and subject ~= lp and lp ~= nil then
          local okPlayer, valuePlayer = pcall(function() return lp[name] end)
          present = okPlayer and type(valuePlayer) == 'function'
        end
        if not present then
          result.absent = result.absent + 1
          result.missing[class][#result.missing[class] + 1] = name
        end
      end
    end
  end
  return result
end

-- ---------------------------------------------------------------------------
-- GENERATED by scanning the bot for modules.<name>.<member>: the native client modules it reaches
-- into. Unlike the g_* functions above, these differ a lot between clients (a module can be renamed,
-- missing, or not export the same members). surveyModules() reports what the running client has.
-- Modules the bot guards and can live without: game_hotkeys, game_imbuementtracker, game_spelllist /
-- game_tibia_spelllist (one of them), game_supplystash, game_actionbar / game_actionbars.
-- ---------------------------------------------------------------------------
A.moduleList = {
  client_entergame = {'CharacterList', 'EnterGame'},
  client_styles = {'importResources'},
  client_terminal = {'addLine'},
  client_textedit = {'show'},
  client_topmenu = {'addRightGameToggleButton', 'getButton'},
  corelib = {'HTTP', 'g_http', 'io'},
  game_actionbar = {},
  game_actionbars = {},
  game_bot = {'botButton', 'botWindow', 'connect', 'contentsPanel', 'g_app'},
  game_buttons = {'buttonsWindow'},
  game_console = {'isEnabledWASD'},
  game_cooldown = {'isCooldownIconActive', 'isGroupCooldownIconActive'},
  game_cyclopedia = {'MapCyclopedia'},
  game_forge = {},
  game_hotkeys = {'useHotkeyItem', 'useHotkeyItemWith'},
  game_imbuementtracker = {},
  game_interface = {'forceExit', 'gameRootPanel', 'getMapPanel', 'getRootPanel', 'startUseWith'},
  game_minimap = {'getMiniMapUi', 'minimapWidget'},
  game_npcmodal = {'onNpcTradeBuyClick'},
  game_npctrade = {'controllerNpcTrader', 'sellAll'},
  game_playerdeath = {},
  game_quickloot = {},
  game_sidebars = {},
  game_skills = {'skillsWindow'},
  game_spelllist = {},
  game_supplystash = {},
  game_textmessage = {'clearMessages', 'displayBroadcastMessage', 'displayFailureMessage', 'displayGameMessage', 'displayStatusMessage'},
  game_tibia_spelllist = {},
  game_topbar = {},
  game_walking = {'bindTurnKeys', 'smartWalk', 'stopSmartWalk', 'unbindTurnKeys', 'walk', 'wsadWalking'},
  gamelib = {'PlayerStates', 'ProtocolGame', 'SpellInfo'},
}
-- Members the shop code reads from the trader controller (Buy Supplies sizes its batches with them).
A.moduleNested = {
  ['game_npctrade.controllerNpcTrader'] = {'isLegacyMode', 'legacyMode', 'MAX_AMOUNT_STACKABLE', 'MAX_AMOUNT_NORMAL', 'getPlayerMoney'},
}

local function field(object, name)
  if object == nil then return nil end
  local ok, value = pcall(function() return object[name] end)
  if ok then return value end
  return nil
end

-- Returns {present = {module = {names}}, missing = {module = {names}}, absentModules = {names},
--          total = n, absent = n}. A module that does not exist counts once, not once per member.
function A.surveyModules()
  local result = {present = {}, missing = {}, absentModules = {}, total = 0, absent = 0}
  local registry = modules
  local names = {}
  for name in pairs(A.moduleList) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do
    result.total = result.total + 1
    local module = field(registry, name)
    if module == nil then
      result.absent = result.absent + 1
      result.absentModules[#result.absentModules + 1] = name
    else
      result.present[name], result.missing[name] = {}, {}
      for _, member in ipairs(A.moduleList[name]) do
        result.total = result.total + 1
        if field(module, member) ~= nil then
          result.present[name][#result.present[name] + 1] = member
        else
          result.absent = result.absent + 1
          result.missing[name][#result.missing[name] + 1] = member
        end
      end
    end
  end
  for path, members in pairs(A.moduleNested) do
    local moduleName, memberName = path:match('^([^.]+)%.(.+)$')
    local parent = field(field(registry, moduleName), memberName)
    if parent ~= nil then
      result.present[path], result.missing[path] = {}, {}
      for _, member in ipairs(members) do
        result.total = result.total + 1
        if field(parent, member) ~= nil then
          result.present[path][#result.present[path] + 1] = member
        else
          result.absent = result.absent + 1
          result.missing[path][#result.missing[path] + 1] = member
        end
      end
    end
  end
  return result
end

-- ---------------------------------------------------------------------------
-- A creature's outfit and its portrait (Inicio, the AttackBot spell preview).
-- OTCv8 returns the outfit as a plain table; other clients may return an Outfit object with getters.
-- ---------------------------------------------------------------------------
local OUTFIT_KEYS = {'type', 'head', 'body', 'legs', 'feet', 'addons', 'mount', 'auxType'}
local OUTFIT_GETTERS = {
  type = {'getId', 'getType', 'getLookType'}, head = {'getHead'}, body = {'getBody'}, legs = {'getLegs'},
  feet = {'getFeet'}, addons = {'getAddons'}, mount = {'getMount'}, auxType = {'getAuxId', 'getAuxType'},
}

-- Returns outfit (a plain table, or nil), how it was read, and what getOutfit() returned.
function A.playerOutfit(creature)
  if creature == nil then return nil, 'sin personaje', nil end
  local okRaw, raw = pcall(function() return creature:getOutfit() end)
  if not okRaw then raw = nil end
  if type(raw) == 'table' then
    -- Keep every key (wings, aura, shader...): the widget draws what it is given.
    local out = {}
    for key, value in pairs(raw) do out[key] = value end
    out.type = tonumber(out.type) or tonumber(raw.lookType) or tonumber(raw.id)
    if out.type and out.type > 0 then return out, 'tabla', raw end
    return nil, 'tabla sin type', raw
  end
  if raw ~= nil then
    local out = {}
    for _, key in ipairs(OUTFIT_KEYS) do
      for _, name in ipairs(OUTFIT_GETTERS[key]) do
        local ok, value = pcall(function() return raw[name](raw) end)
        if ok and tonumber(value) then out[key] = tonumber(value); break end
      end
      if out[key] == nil then
        local ok, value = pcall(function() return raw[key] end)
        if ok and tonumber(value) then out[key] = tonumber(value) end
      end
    end
    if out.type and out.type > 0 then return out, 'metodos', raw end
    return nil, 'objeto ilegible', raw
  end
  local okLook, look = pcall(function() return creature:getLookType() end)
  if okLook and tonumber(look) and tonumber(look) > 0 then return {type = tonumber(look)}, 'getLookType', nil end
  return nil, 'sin outfit', nil
end

local function widgetCall(widget, method, ...)
  if type(widget[method]) ~= 'function' then return false, nil end
  return pcall(widget[method], widget, ...)
end

-- Ways of drawing the portrait. A UICreature that draws nothing gives no error, so when a client shows an
-- empty frame the user can click the portrait to try the next one (Inicio keeps the choice).
--   options: which UICreature settings are applied ('fit' = the sizing set made for the modern renderer,
--            'none' = the widget as the client creates it, 'old' = the old scaling mode)
--   paint:   'outfit' = setOutfit with the outfit read, 'live' = setCreature with the character itself
--   shift:   {dx, dy} the widget is moved inside the frame (negative margins), to put the sprite where the
--            client does not.
-- Valkaris Next Gen has setCenter, setFixedCreatureSize and setOldScaling (portrait.txt lists the methods);
-- variant 2 draws the sprite there, but about 6 px right and 8 px below the middle of the frame. Variants 3 to 6
-- try the combinations of those three settings, 8 moves variant 2 by hand. 1 is the setting made for the old
-- Valkaris client (blank in the new one).
A.portraitVariants = {
  {name = 'ajustado', options = 'fit', paint = 'outfit'},
  {name = 'sin ajustes', options = 'none', paint = 'outfit'},
  {name = 'centrado', options = 'center', paint = 'outfit'},
  {name = 'escala antigua', options = 'old', paint = 'outfit'},
  {name = 'centrado y escala antigua', options = 'centerold', paint = 'outfit'},
  {name = 'tamano libre', options = 'free', paint = 'outfit'},
  {name = 'personaje en vivo', options = 'none', paint = 'live'},
  {name = 'sin ajustes y desplazado', options = 'none', paint = 'outfit', shift = {-6, -8}},
}

-- Ordered settings of the partial variants.
local OPTION_SETS = {
  center = {{'setClipping', true}, {'setCenter', true}},
  centerold = {{'setClipping', true}, {'setCenter', true}, {'setOldScaling', true}},
  free = {{'setClipping', true}, {'setFixedCreatureSize', false}},
}

-- Returns a valid variant number and its description (anything else becomes 1).
function A.portraitVariant(index)
  index = tonumber(index)
  if not index or index ~= math.floor(index) or index < 1 or index > #A.portraitVariants then index = 1 end
  return index, A.portraitVariants[index]
end

-- Applies the UICreature settings of a variant. Every call is optional: a client without that method is skipped.
function A.applyPortraitOptions(widget, variant)
  if widget == nil then return end
  local _, v = A.portraitVariant(variant)
  if v.options == 'fit' then
    -- The modern renderer treats 100 as percent of its viewport. Older UICreature implementations treat a
    -- nonzero creature-size as absolute pixels; zero lets their 64px source framebuffer scale instead.
    local scalable = type(widget.setFixedCreatureSize) == 'function'
    widgetCall(widget, 'setClipping', true)
    widgetCall(widget, 'setCenter', true)
    widgetCall(widget, 'setCenterByBoundingBox', true)
    widgetCall(widget, 'setFixedCreatureSize', false)
    widgetCall(widget, 'setCreatureSize', scalable and 100 or 0)
    widgetCall(widget, 'setBaseScale', false)
    widgetCall(widget, 'setIgnoreDisplacementShift', false)
    widgetCall(widget, 'setCreatureSmooth', true)
  elseif v.options == 'old' then
    widgetCall(widget, 'setClipping', true)
    widgetCall(widget, 'setOldScaling', true)
  elseif OPTION_SETS[v.options] then
    for _, setting in ipairs(OPTION_SETS[v.options]) do widgetCall(widget, setting[1], setting[2]) end
  end
end

-- A fresh UICreature inside `frame`, filling it with the OTUI's margin (3) moved by the variant's shift (the
-- opposite margin grows by the same amount, so the size does not change). A widget cannot be put back to the
-- client's defaults, so changing variant means building a new one.
function A.newPortraitWidget(frame, variant)
  if frame == nil or type(g_ui) ~= 'table' or type(g_ui.createWidget) ~= 'function' then return nil end
  local ok, fresh = pcall(g_ui.createWidget, 'UICreature', frame)
  if not ok or fresh == nil then return nil end
  widgetCall(fresh, 'fill', 'parent')
  local _, v = A.portraitVariant(variant)
  local dx, dy = 0, 0
  if type(v.shift) == 'table' then dx, dy = tonumber(v.shift[1]) or 0, tonumber(v.shift[2]) or 0 end
  widgetCall(fresh, 'setMarginLeft', 3 + dx)
  widgetCall(fresh, 'setMarginRight', 3 - dx)
  widgetCall(fresh, 'setMarginTop', 3 + dy)
  widgetCall(fresh, 'setMarginBottom', 3 - dy)
  widgetCall(fresh, 'setPhantom', true)
  widgetCall(fresh, 'setFocusable', false)
  return fresh
end

-- Paints `creature` on a UICreature widget. Tries, in order: setOutfit with a table, setOutfit with the
-- client's own object, setCreature with the creature itself (the widget then draws the live character; the
-- caller must never turn it). The 'live' variant goes straight to setCreature. Repaints only when the outfit
-- (or the variant) changes. Returns the diagnostic table (also kept in ApiCompat.portrait for the
-- diagnostics panel).
function A.paintPortrait(widget, creature, variant)
  if widget == nil then return nil end
  local variantIndex, variantInfo = A.portraitVariant(variant)
  local outfit, source, raw = A.playerOutfit(creature)
  local parts = {}
  if outfit then
    for key, value in pairs(outfit) do if type(value) ~= 'table' then parts[#parts + 1] = tostring(key) .. '=' .. tostring(value) end end
    table.sort(parts)
  end
  local signature = (outfit and table.concat(parts, ';') or ('sin:' .. tostring(source) .. ':' .. tostring(raw))) .. '|v' .. variantIndex
  if widget._portraitSignature == signature and A.portrait then
    -- Inicio hides the widget while offline; showing an already visible one costs nothing.
    if widget._portraitApplied and type(widget.show) == 'function' then pcall(widget.show, widget) end
    return A.portrait
  end
  widget._portraitSignature = signature
  local info = {
    source = source, rawType = type(raw), outfit = table.concat(parts, ';'):sub(1, 160),
    hasSetOutfit = type(widget.setOutfit) == 'function', hasSetCreature = type(widget.setCreature) == 'function',
    hasGetCreature = type(widget.getCreature) == 'function', variant = variantIndex, variantName = variantInfo.name,
  }
  local applied
  if variantInfo.paint == 'live' and creature ~= nil and info.hasSetCreature and widgetCall(widget, 'setCreature', creature) then
    applied = 'setCreature'
  end
  if not applied and outfit and info.hasSetOutfit and widgetCall(widget, 'setOutfit', outfit) then applied = 'setOutfit' end
  if not applied and raw ~= nil and type(raw) ~= 'table' and info.hasSetOutfit and widgetCall(widget, 'setOutfit', raw) then
    applied = 'setOutfit (objeto del cliente)'
  end
  -- setOutfit makes the widget build its own creature, so it can be faced south (a front view) without
  -- touching the character. Never done after setCreature: that one is the real character.
  if applied and applied:find('setOutfit', 1, true) == 1 then widgetCall(widget, 'setDirection', 2) end
  local holds
  if applied and info.hasGetCreature then
    local ok, held = widgetCall(widget, 'getCreature')
    holds = ok and held ~= nil
  end
  if (not applied or holds == false) and info.hasSetCreature and creature ~= nil and widgetCall(widget, 'setCreature', creature) then
    applied = 'setCreature'
    holds = nil
  end
  info.applied = applied or 'nada'
  info.holdsCreature = holds
  local okW, width = widgetCall(widget, 'getWidth')
  local okH, height = widgetCall(widget, 'getHeight')
  info.width, info.height = okW and width or nil, okH and height or nil
  A.portrait = info
  widget._portraitApplied = applied ~= nil
  if applied and type(widget.show) == 'function' then pcall(widget.show, widget) end
  return info
end

-- One text line for the diagnostics panel.
function A.describePortrait(info)
  if type(info) ~= 'table' then return nil end
  local function yes(value) return value and 'si' or 'no' end
  return 'RETRATO (Inicio): outfit leido por ' .. tostring(info.source) .. ' (getOutfit devuelve ' .. tostring(info.rawType) ..
    ') | UICreature: setOutfit ' .. yes(info.hasSetOutfit) .. ', setCreature ' .. yes(info.hasSetCreature) ..
    ', getCreature ' .. yes(info.hasGetCreature) .. ' | pintado con: ' .. tostring(info.applied) ..
    (info.holdsCreature == false and ' (el widget no guarda criatura)' or '') ..
    ' | tamano ' .. tostring(info.width) .. 'x' .. tostring(info.height) ..
    (info.variant and (' | variante ' .. tostring(info.variant) .. ' (' .. tostring(info.variantName) .. ')') or '')
end

-- What a widget reports about itself, as text ("no existe" when the client has no such method).
local function probe(widget, method)
  if widget == nil or type(widget[method]) ~= 'function' then return 'no existe' end
  local ok, value = pcall(widget[method], widget)
  if not ok then return 'error' end
  if value == nil then return 'nil' end
  local kind = type(value)
  if kind == 'number' or kind == 'boolean' or kind == 'string' then return tostring(value) end
  return kind
end

-- Several lines for a text file: what was painted and what the widgets say about themselves. A UICreature
-- that draws nothing raises no error, so these numbers are the only way to tell why (size 0, hidden, no
-- creature kept...).
function A.portraitReport(info, widget, frame)
  local lines = {A.describePortrait(info) or 'RETRATO: sin datos'}
  local function add(label, target, methods)
    local parts = {}
    for _, method in ipairs(methods) do parts[#parts + 1] = method:gsub('^get', ''):gsub('^is', '') .. '=' .. probe(target, method) end
    lines[#lines + 1] = label .. ': ' .. table.concat(parts, ', ')
  end
  add('UICreature', widget, {'isVisible', 'getX', 'getY', 'getWidth', 'getHeight', 'getCreature', 'getCreatureSize',
    'isFixedCreatureSize', 'getOpacity', 'getMarginTop', 'getMarginLeft', 'getDirection', 'isAnimate', 'getRotation'})
  local have = {}
  for _, method in ipairs({'setCenter', 'setCenterByBoundingBox', 'setFixedCreatureSize', 'setCreatureSize', 'setBaseScale',
    'setIgnoreDisplacementShift', 'setCreatureSmooth', 'setOldScaling', 'setDirection', 'setAnimate', 'setRotation', 'setOffset'}) do
    have[#have + 1] = method:gsub('^set', '') .. '=' .. ((widget ~= nil and type(widget[method]) == 'function') and 'si' or 'no')
  end
  lines[#lines + 1] = 'Metodos: ' .. table.concat(have, ', ')
  lines[#lines + 1] = 'Outfit: ' .. ((type(info) == 'table' and info.outfit ~= '') and info.outfit or '(sin datos)')
  add('Marco', frame, {'isVisible', 'getWidth', 'getHeight', 'isClipping'})
  local okP, parent = false, nil
  if frame ~= nil and type(frame.getParent) == 'function' then okP, parent = pcall(frame.getParent, frame) end
  if okP and parent ~= nil then add('Tarjeta', parent, {'isVisible', 'getWidth', 'getHeight'}) end
  lines[#lines + 1] = 'Cliente: ' .. tostring(type(ClientDetector) == 'table' and ClientDetector.id or 'desconocido')
  return table.concat(lines, '\n')
end

-- Writes a small text file in the bot's _diagnostics folder (the same place as client-report.json).
-- Returns true, or false and the reason. Never raises.
function A.writeDiagnostic(name, text)
  if type(name) ~= 'string' or not name:match('^[%w_%-]+%.txt$') then return false, 'nombre no valido' end
  if type(g_resources) ~= 'table' or type(g_resources.makeDir) ~= 'function' or type(g_resources.writeFileContents) ~= 'function' then
    return false, 'no se puede escribir en este cliente'
  end
  local base = type(configDir) == 'string' and configDir:gsub('\\', '/'):gsub('/+$', '')
  if not base or not base:match('^/bot/[^/]+$') or base:find('..', 1, true) then return false, 'ruta de configuracion no valida' end
  local ok, err = pcall(function()
    g_resources.makeDir(base .. '/_diagnostics')
    g_resources.writeFileContents(base .. '/_diagnostics/' .. name, tostring(text))
  end)
  if not ok then return false, tostring(err) end
  return true
end

-- One text line for the diagnostics panel.
function A.describeModules(survey)
  if type(survey) ~= 'table' then return nil end
  local parts = {}
  if #survey.absentModules > 0 then
    parts[#parts + 1] = 'modulos ausentes: ' .. table.concat(survey.absentModules, ', ')
  end
  local keys = {}
  for name, list in pairs(survey.missing) do if #list > 0 then keys[#keys + 1] = name end end
  table.sort(keys)
  for _, name in ipairs(keys) do
    parts[#parts + 1] = name .. ': ' .. table.concat(survey.missing[name], ', ')
  end
  return 'MODULOS NATIVOS: el bot toca ' .. tostring(survey.total) .. ' elementos del cliente; faltan ' ..
    tostring(survey.absent) .. (#parts > 0 and (' -> ' .. table.concat(parts, ' | ')) or '')
end

return A
