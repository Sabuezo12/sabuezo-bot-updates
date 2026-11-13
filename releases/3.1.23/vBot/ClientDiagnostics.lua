--[[
  ClientDiagnostics - panel showing which client and server Helper is running on.

  Shows: client, server, host/world, DAT signature, detected capabilities, which
  g_game/g_things functions exist, and every call ApiCompat had to default or
  that failed. "Copiar entrada servers.json" builds a ready-to-paste server
  entry (with the live DAT signature) so new servers can be registered without
  editing by hand. "Guardar informe" writes _diagnostics/client-report.json.
]]

setDefaultTab("Main")

local function safe(fn, ...)
  -- The panel's own probes are expected to fail sometimes; keep them out of "Errores ocultos".
  local ok, a = (HelperErrors and HelperErrors.originalPcall or pcall)(fn, ...)
  if ok then return a end
  return nil
end

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t or {}) do keys[#keys + 1] = tostring(k) end
  table.sort(keys)
  return keys
end

local function formatSignature(sig)
  if sig == nil then return 'no disponible' end
  local n = tonumber(sig)
  if n == 0 then return '0 (este cliente no usa firma DAT; el servidor se identifica por host o mundo)' end
  if n and n >= 0 and n % 1 == 0 then
    return string.format('%.0f (0x%08X)', n, n)
  end
  return tostring(sig)
end

-- 0 means "no signature" and must never be written to servers.json.
local function decimalSignature(sig)
  local n = tonumber(sig)
  if n == 0 then return nil end
  if n and n >= 0 and n % 1 == 0 then return string.format('%.0f', n) end
  return sig ~= nil and tostring(sig) or nil
end

local function listNames(map, wanted)
  local names = {}
  for _, name in ipairs(sortedKeys(map)) do
    if (map[name] == true) == wanted then names[#names + 1] = name end
  end
  if #names == 0 then return '-' end
  return table.concat(names, ', ')
end

-- ---------------------------------------------------------------------------
-- Configuration check: settings that are contradictory or that change nothing.
-- Reads the live Inmortal settings and the active TargetBot profile; read-only.
-- ---------------------------------------------------------------------------
local function configWarnings()
  local items = {}
  local function warnItem(text) items[#items + 1] = 'AVISO: ' .. text end
  local function infoItem(text) items[#items + 1] = 'Info: ' .. text end

  -- Inmortal
  local inmortal = type(storage) == 'table' and storage.autoProtect_Ultra or nil
  if type(inmortal) == 'table' then
    if inmortal.enabled ~= true then
      infoItem('Inmortal esta OFF.')
    else
      local sections = {{'ering', 'Energy Ring'}, {'ring', 'Might Ring'}, {'amulet', 'SSA/Amuleto'}}
      local active = 0
      for _, entry in ipairs(sections) do
        local section, name = inmortal[entry[1]], entry[2]
        if type(section) == 'table' then
          if section.enabled ~= true then
            infoItem('Inmortal: ' .. name .. ' esta OFF; no actuara.')
          else
            active = active + 1
            local usesItem = entry[1] ~= 'ering' or section.mode ~= 'spell'
            if usesItem and (tonumber(section.dangerItem) or 0) <= 0 then
              warnItem('Inmortal: ' .. name .. ' esta ON pero sin objeto de peligro configurado.')
            end
            local hpAt = tonumber(section.hpAt)
            if hpAt and hpAt >= 100 then
              warnItem('Inmortal: ' .. name .. ' con umbral de vida ' .. hpAt .. '%: se activara siempre.')
            end
            if entry[1] == 'ering' then
              local removeAt = tonumber(section.removeAt)
              if hpAt and removeAt and removeAt <= hpAt then
                warnItem('Inmortal: Energy Ring se quita a ' .. removeAt .. '% pero se pone a ' .. hpAt .. '%.')
              end
            end
          end
        end
      end
      if active == 0 then
        warnItem('Inmortal esta ON pero Energy Ring, Might Ring y SSA/Amuleto estan OFF: no hara nada.')
      end
    end
  end

  -- TargetBot: rules of the active profile (including unsaved edits).
  local rules, profile
  pcall(function()
    local instance = TargetBot and TargetBot.Unified and TargetBot.Unified.instance
    profile = TargetBot and TargetBot.getCurrentProfile and TargetBot.getCurrentProfile()
    local state = instance and instance.states and profile and instance.states[profile]
    rules = state and state.rules
  end)
  if type(rules) == 'table' then
    for _, rule in ipairs(rules) do
      local label = 'TargetBot [' .. tostring(rule.name or '?') .. ']: '
      local minimum, maximum = tonumber(rule.lureMin), tonumber(rule.lureMax)
      if rule.dynamicLure then
        if minimum and maximum and minimum >= maximum then
          warnItem(label .. 'Lure dinamico con minimo >= maximo.')
        end
        if not rule.dynamicLureDelay then
          infoItem(label .. 'Pausa dinamica esta OFF; el lure no se pausa.')
        elseif maximum and tonumber(rule.delayFrom) and tonumber(rule.delayFrom) > maximum then
          warnItem(label .. 'Pausa dinamica "Desde ' .. tostring(rule.delayFrom) ..
            '" supera el maximo del lure (' .. maximum .. '): casi nunca se aplicara.')
        end
      end
      if rule.closeLure then
        local limit = tonumber(rule.closeLureAmount) or 3
        if limit < 1 then
          warnItem(label .. 'Agrupar cercanos con limite 0: se trata como 1.')
        else
          infoItem(label .. 'Agrupar cercanos (anti-rodeo) activo, limite ' .. limit .. ' pegados.')
        end
      end
    end
  else
    infoItem('No se pudieron leer las reglas de TargetBot (perfil ' .. tostring(profile) .. ').')
  end
  return items
end

local function buildConfigText()
  local ok, items = pcall(configWarnings)
  local lines = {'CONFIGURACION: avisos de ajustes contradictorios o sin efecto', ''}
  if not ok then
    lines[#lines + 1] = 'No se pudo revisar la configuracion: ' .. tostring(items)
  elseif #items == 0 then
    lines[#lines + 1] = 'Sin avisos: no se detecto configuracion contradictoria.'
  else
    for i = 1, math.min(#items, 22) do lines[#lines + 1] = items[i] end
    if #items > 22 then lines[#lines + 1] = '... y ' .. (#items - 22) .. ' mas.' end
  end
  lines[#lines + 1] = ''
  lines[#lines + 1] = 'Solo se revisan Inmortal y las reglas del perfil activo de TargetBot.'
  return table.concat(lines, '\n')
end

-- ---------------------------------------------------------------------------
-- File check: compiles every .lua of this bot without running it, so a syntax
-- error is found before it breaks a reload. Logic errors are not detected.
-- ---------------------------------------------------------------------------
local function checkFiles()
  local result = {checked = 0, skipped = 0, failures = {}}
  local base = type(configDir) == 'string' and configDir:gsub('\\', '/'):gsub('/+$', '') or nil
  if not base or not base:match('^/bot/[^/]+$') then
    result.error = 'ruta de configuracion no valida'
    return result
  end
  if type(g_resources) ~= 'table' or type(g_resources.listDirectoryFiles) ~= 'function' or type(loadstring) ~= 'function' then
    result.error = 'este cliente no permite listar o compilar archivos'
    return result
  end
  local skip = {_updates = true, _helper_dev = true, _archive = true, _script_editor_backups = true}
  local function walk(dir, rel, depth)
    if depth > 12 then return end
    local ok, names = pcall(g_resources.listDirectoryFiles, dir, false, false)
    if not ok or type(names) ~= 'table' then return end
    for _, name in ipairs(names) do
      if name:sub(1, #dir + 1) == dir .. '/' then name = name:sub(#dir + 2) end
      if not name:find('/', 1, true) and not (rel == '' and skip[name]) then
        local sub = rel == '' and name or (rel .. '/' .. name)
        local path = dir .. '/' .. name
        if g_resources.fileExists(path) then
          if name:lower():sub(-4) == '.lua' then
            local readOk, data = pcall(g_resources.readFileContents, path)
            if readOk and type(data) == 'string' then
              result.checked = result.checked + 1
              local fn, err = loadstring(data, '=' .. sub)
              if not fn then result.failures[#result.failures + 1] = sub .. ': ' .. tostring(err) end
            else
              result.skipped = result.skipped + 1
            end
          end
        elseif g_resources.directoryExists(path) then
          walk(path, sub, depth + 1)
        end
      end
    end
  end
  walk(base, '', 0)
  return result
end

local function buildFilesText(result)
  local lines = {'COMPROBAR ARCHIVOS: compilacion de cada .lua (no se ejecuta nada)', ''}
  if result.error then
    lines[#lines + 1] = 'No se pudo comprobar: ' .. result.error
  else
    lines[#lines + 1] = 'Archivos comprobados: ' .. result.checked .. ' | con errores: ' .. #result.failures ..
      (result.skipped > 0 and (' | no se pudieron leer: ' .. result.skipped) or '')
    lines[#lines + 1] = ''
    if #result.failures == 0 then
      lines[#lines + 1] = 'Todos compilan sin errores de sintaxis.'
    else
      for i = 1, math.min(#result.failures, 12) do lines[#lines + 1] = result.failures[i]:sub(1, 150) end
      if #result.failures > 12 then lines[#lines + 1] = '... y ' .. (#result.failures - 12) .. ' mas.' end
    end
  end
  lines[#lines + 1] = ''
  lines[#lines + 1] = 'Solo detecta errores de sintaxis; un error de logica no aparece aqui.'
  return table.concat(lines, '\n')
end

-- Plain-data snapshot, used both for the text view and the JSON report.
local function snapshot()
  if ServerDetector and type(ServerDetector.refresh) == 'function' then safe(ServerDetector.refresh) end
  local api = ApiCompat and safe(ApiCompat.report) or nil
  local compat = HelperClientCompat and type(HelperClientCompat.status) == 'function' and safe(HelperClientCompat.status) or nil
  local sig = ServerDetector and ServerDetector.datSignature
  if sig == nil and ApiCompat then sig = safe(ApiCompat.datSignature) end

  -- What the client says is equipped, read two independent ways.
  local equipment = {}
  if HelperAPI and type(HelperAPI.getSlotItem) == 'function' then
    for slot = 1, 11 do
      local item = safe(HelperAPI.getSlotItem, slot)
      equipment[slot] = item and safe(function() return item:getId() end) or 0
    end
  end
  local function nativeSlotId(fn)
    if type(fn) ~= 'function' then return nil end
    return safe(function() local item = fn(); return item and item:getId() or 0 end)
  end
  -- What the client's Forge module exposes at runtime (names only, nothing is called).
  local function keysOf(object)
    local out = {}
    if type(object) ~= 'table' then return out end
    for key, value in pairs(object) do out[#out + 1] = tostring(key) .. (type(value) == 'function' and '()' or (':' .. type(value))) end
    table.sort(out)
    while #out > 120 do table.remove(out) end
    return out
  end
  local forgeModule = safe(function() return modules and modules.game_forge end)
  local forgeController = type(forgeModule) == 'table' and safe(function() return forgeModule.ForgeController end) or nil
  local forgeConversion = type(forgeController) == 'table' and safe(function() return forgeController.conversion end) or nil
  local forgeGame = {}
  if type(g_game) == 'table' then
    for key, value in pairs(g_game) do
      local name = tostring(key):lower()
      if name:find('forge', 1, true) or name:find('dust', 1, true) or name:find('sliver', 1, true) or
          name:find('exalt', 1, true) or name:find('fusion', 1, true) then
        forgeGame[#forgeGame + 1] = tostring(key) .. (type(value) == 'function' and '()' or (':' .. type(value)))
      end
    end
    table.sort(forgeGame)
  end
  -- Values (not just names) of the plain data Forge keeps: numbers, booleans, short
  -- strings, and nested tables two levels deep. Functions are only named, never called.
  local function describe(object, depth)
    local out = {}
    if type(object) ~= 'table' then return out end
    local count = 0
    for key, value in pairs(object) do
      count = count + 1
      if count > 40 then out['...'] = 'mas claves'; break end
      local kind = type(value)
      if kind == 'number' or kind == 'boolean' then out[tostring(key)] = value
      elseif kind == 'string' then out[tostring(key)] = value:sub(1, 60)
      elseif kind == 'function' then out[tostring(key)] = 'function'
      elseif kind == 'table' and depth > 0 then out[tostring(key)] = describe(value, depth - 1)
      else out[tostring(key)] = kind end
    end
    return out
  end
  -- The Forge window, if open: ids/styles/state only, so the real controls can be identified.
  local function windowTree()
    local result = {found = false, tree = {}}
    local root = g_ui and g_ui.getRootWidget and safe(g_ui.getRootWidget)
    if not root then return result end
    local function add(widget, depth)
      if #result.tree >= 160 or depth > 6 then return end
      local id = safe(function() return widget:getId() end) or '?'
      local style = safe(function() return widget:getStyleName() end) or '?'
      local enabled = safe(function() return widget:isEnabled() end)
      local visible = safe(function() return widget:isVisible() end)
      local text = safe(function() return widget.getText and widget:getText() or nil end)
      result.tree[#result.tree + 1] = string.rep('  ', depth) .. tostring(id) .. ' [' .. tostring(style) .. ']' ..
        (enabled == false and ' disabled' or '') .. (visible == false and ' hidden' or '') ..
        (type(text) == 'string' and text ~= '' and (' "' .. text:sub(1, 30) .. '"') or '')
      for _, child in ipairs(safe(function() return widget:getChildren() end) or {}) do add(child, depth + 1) end
    end
    for _, child in ipairs(safe(function() return root:getChildren() end) or {}) do
      local id = tostring(safe(function() return child:getId() end) or ''):lower()
      if id:find('forge', 1, true) and not result.found then
        result.found = true
        add(child, 0)
      end
    end
    return result
  end
  local forge = {
    moduleLoaded = type(forgeModule) == 'table',
    module = keysOf(forgeModule),
    controller = keysOf(forgeController),
    conversion = keysOf(forgeConversion),
    adapterVersion = type(forgeConversion) == 'table' and forgeConversion.safeAdapterVersion or nil,
    game = forgeGame,
    conversionValues = describe(forgeConversion, 2),
    controllerValues = describe(forgeController, 1),
    gameForgeData = type(g_game) == 'table' and describe(g_game.forgeData, 2) or {},
    helpers = keysOf(type(forgeModule) == 'table' and forgeModule.Helpers or nil),
    window = windowTree(),
    -- What Auto Forge decided (requests, confirmations, stops and why), most recent last.
    autoForge = safe(function()
      local engine = type(AutoForge) == 'table' and AutoForge.controller or nil
      if type(engine) ~= 'table' then return nil end
      local lines = {}
      for _, entry in ipairs(engine.trace or {}) do
        lines[#lines + 1] = tostring(math.floor((entry.at or 0) / 1000)) .. 's ' .. tostring(entry.text)
      end
      return {enabled = engine.isOn(), kind = engine.state.kind, message = engine.state.message, trace = lines}
    end),
  }
  local survey = ApiCompat and type(ApiCompat.survey) == 'function' and safe(ApiCompat.survey) or nil
  local methods = ApiCompat and type(ApiCompat.surveyMethods) == 'function' and safe(ApiCompat.surveyMethods) or nil
  local nativeModules = ApiCompat and type(ApiCompat.surveyModules) == 'function' and safe(ApiCompat.surveyModules) or nil
  return {
    configWarnings = safe(configWarnings),
    -- How long the last start-up took, step by step (the loader measures it).
    loadProfile = safe(function()
      local P = RinoLoadProfile
      if type(P) ~= 'table' or not P.totalMs then return nil end
      return {totalMs = P.totalMs, workMs = P.workMs, slowest = P.top}
    end),
    forge = forge,
    methodSurvey = methods,
    nativeModules = nativeModules,
    portrait = ApiCompat and type(ApiCompat.portrait) == 'table' and ApiCompat.portrait or nil,
    survey = survey and {total = survey.total, absent = survey.absent, missing = survey.missing} or nil,
    hiddenErrors = HelperErrors and type(HelperErrors.summary) == 'function' and safe(HelperErrors.summary, 8) or nil,
    slowMacros = HelperPerf and type(HelperPerf.summary) == 'function' and safe(HelperPerf.summary, 8) or nil,
    stalls = HelperPerf and type(HelperPerf.stallSummary) == 'function' and safe(HelperPerf.stallSummary) or nil,
    memory = HelperPerf and type(HelperPerf.memorySummary) == 'function' and safe(HelperPerf.memorySummary) or nil,
    firewall = HelperFirewall and type(HelperFirewall.summary) == 'function' and safe(HelperFirewall.summary) or nil,
    equipment = equipment,
    nativeFinger = nativeSlotId(getFinger),
    nativeNeck = nativeSlotId(getNeck),
    equipTrace = HelperAPI and HelperAPI.trace or {},
    client = {
      id = ClientDetector and ClientDetector.id or (HelperClient and HelperClient.id) or 'desconocido',
      name = ClientDetector and ClientDetector.name or (HelperClient and HelperClient.name) or 'desconocido',
      helperCore = HelperClient and HelperClient.coreVersion or nil,
      clientVersion = api and api.clientVersion or nil,
      protocolVersion = api and api.protocolVersion or nil,
      versionAssumed = api and api.versionAssumed or nil,
    },
    server = {
      id = ServerDetector and ServerDetector.serverId or 'unknown',
      name = ServerDetector and ServerDetector.serverName or 'Unknown Server',
      matchedBy = ServerDetector and ServerDetector.matchedBy or nil,
      host = ServerDetector and ServerDetector.host or nil,
      world = ServerDetector and ServerDetector.world or nil,
      configSource = ServerDetector and ServerDetector.configSource or nil,
      configError = ServerDetector and ServerDetector.configError or nil,
    },
    datSignature = sig,
    datSignatureDecimal = decimalSignature(sig),
    capabilities = ClientDetector and ClientDetector.caps or {},
    probe = api and api.probe or nil,
    missingCalls = api and api.missing or {},
    failedCalls = api and api.failed or {},
    itemCatalog = compat,
  }
end

local function buildText(s)
  local lines = {}
  local function add(text) lines[#lines + 1] = text end

  add('CLIENTE: ' .. tostring(s.client.name) .. ' [' .. tostring(s.client.id) .. ']')
  add('Version: ' .. tostring(s.client.clientVersion or '?') .. ' | protocolo ' .. tostring(s.client.protocolVersion or '?') ..
    (s.client.versionAssumed and ' (version asumida: el cliente no la informa)' or ''))
  add('')
  add('SERVIDOR: ' .. tostring(s.server.name) .. ' [' .. tostring(s.server.id) .. ']' ..
    (s.server.matchedBy and (' - coincide por ' .. s.server.matchedBy) or ' - sin coincidencia en servers.json'))
  add('Host: ' .. tostring(s.server.host or 'no disponible') .. ' | Mundo: ' .. tostring(s.server.world or 'no disponible'))
  add('Firma DAT: ' .. formatSignature(s.datSignature))
  add('servers.json: ' .. (s.server.configError and ('ERROR - ' .. s.server.configError) or tostring(s.server.configSource or 'no leido')))
  add('')

  local capTrue, capFalse = {}, {}
  for _, name in ipairs(sortedKeys(s.capabilities)) do
    local value = s.capabilities[name]
    if type(value) == 'boolean' then
      if value then capTrue[#capTrue + 1] = name else capFalse[#capFalse + 1] = name end
    end
  end
  add('CAPABILITIES activas: ' .. (#capTrue > 0 and table.concat(capTrue, ', ') or '-'))
  add('CAPABILITIES ausentes: ' .. (#capFalse > 0 and table.concat(capFalse, ', ') or '-'))
  add('')

  if s.probe then
    add('g_game disponibles: ' .. listNames(s.probe.game, true))
    add('g_game FALTAN: ' .. listNames(s.probe.game, false))
    add('g_things disponibles: ' .. listNames(s.probe.things, true))
    add('g_things FALTAN: ' .. listNames(s.probe.things, false))
  else
    add('api_compat no esta cargado.')
  end
  add('')

  local missing = {}
  for _, key in ipairs(sortedKeys(s.missingCalls)) do
    missing[#missing + 1] = key .. ' x' .. tostring(s.missingCalls[key].count)
  end
  add('Llamadas a funciones ausentes: ' .. (#missing > 0 and table.concat(missing, ', ') or 'ninguna'))
  local failed = {}
  for _, key in ipairs(sortedKeys(s.failedCalls)) do
    local entry = s.failedCalls[key]
    failed[#failed + 1] = key .. ' x' .. tostring(entry.count) .. ' (' .. tostring(entry.error):sub(1, 60) .. ')'
  end
  add('Llamadas que fallaron: ' .. (#failed > 0 and table.concat(failed, '; ') or 'ninguna'))

  if s.hiddenErrors then
    local h = s.hiddenErrors
    add('ERRORES OCULTOS (capturados por pcall): ' .. tostring(h.total) .. ' en total, ' .. tostring(h.distinct) ..
      ' distintos' .. (h.overflow > 0 and (' (+' .. h.overflow .. ' sin contar)') or '') ..
      '. Muchos son sondeos a proposito; mira los que se repiten.')
    for i = 1, math.min(3, #h.top) do
      add('  x' .. tostring(h.top[i].count) .. '  ' .. tostring(h.top[i].message):sub(1, 95))
    end
  end
  if s.slowMacros then
    local m = s.slowMacros
    add('MACROS LENTOS (>= ' .. tostring(m.threshold) .. ' ms): ' .. tostring(m.totalSlow) .. ' veces')
    for i = 1, math.min(3, #m.top) do
      add('  ' .. tostring(m.top[i].label):sub(1, 70) .. ' | maximo ' .. tostring(m.top[i].max) .. ' ms (' .. tostring(m.top[i].count) .. ' veces)')
    end
  end
  if type(s.stalls) == 'table' then
    local t = s.stalls
    add('TIRONES (parones del bot >= ' .. tostring(t.thresholdMs) .. ' ms): ' .. tostring(t.count) .. ', el peor ' .. tostring(t.worst) ..
      ' ms; ' .. tostring(t.collector) .. ' con bajada de memoria (recolector) | memoria de Lua ' .. tostring(t.heapMB or '?') ..
      ' MB (pico ' .. tostring(t.peakMB or '?') .. ' MB)')
  end
  if type(s.memory) == 'table' then
    local m = s.memory
    local boots = {}
    for _, b in ipairs(m.boots or {}) do
      boots[#boots + 1] = '#' .. tostring(b.instance) .. ': ' .. (b.processMB and (tostring(b.processMB) .. ' MB') or ('Lua ' .. tostring(b.luaMB or '?') .. ' MB'))
    end
    add('MEMORIA: Lua ' .. tostring(m.luaMB or '?') .. ' MB (pico ' .. tostring(m.peakLuaMB or '?') .. ') | proceso ' ..
      (m.processAvailable and (tostring(m.processMB or '?') .. ' MB (pico ' .. tostring(m.peakProcessMB or '?') .. ')')
        or 'no disponible en este cliente') .. ' | cargas del bot en esta sesion: ' .. tostring(m.loadsThisSession) ..
      (#boots > 0 and (' | memoria al arrancar cada carga: ' .. table.concat(boots, ', '):sub(1, 150)) or ''))
  end
  if type(s.firewall) == 'table' then
    local fw = s.firewall
    for i = 1, math.min(3, #fw.incidents) do
      local incident = fw.incidents[i]
      add('CORTAFUEGOS: ' .. tostring(incident.label):sub(1, 60) .. ' fallo ' .. tostring(incident.count) .. ' veces seguidas' ..
        (incident.recovered and ' (ya se recupero)' or '') .. (incident.essential and ' [esencial: solo aviso]' or '') ..
        ' - ' .. tostring(incident.message):sub(1, 70))
    end
    if #fw.previousInstances > 0 then
      add('INSTANCIAS ANTERIORES: siguen ejecutandose macros de una carga anterior del bot: ' ..
        table.concat(fw.previousInstances, ', '):sub(1, 140))
    end
  end
  if type(s.loadProfile) == 'table' then
    local lp = s.loadProfile
    add(string.format('CARGA: %.1f s en total (%.1f s de trabajo) | mas lentos: %s', (lp.totalMs or 0) / 1000,
      (lp.workMs or 0) / 1000, table.concat(lp.slowest or {}, ' | ', 1, math.min(4, #(lp.slowest or {})))))
  end
  if s.forge then
    local f = s.forge
    add('FORGE: modulo ' .. (f.moduleLoaded and 'cargado' or 'no cargado') .. ' (' .. #f.module .. ' claves)' ..
      ' | ForgeController ' .. #f.controller .. ' | conversion ' .. (#f.conversion > 0 and (#f.conversion .. ' claves') or 'ausente') ..
      ' | adaptador v' .. tostring(f.adapterVersion or 'ninguno') .. ' (AutoForge pide >= 20261104)' ..
      ' | g_game forge: ' .. (#f.game > 0 and table.concat(f.game, ', ') or 'ninguna'))
    if type(f.autoForge) == 'table' then
      add('AUTOFORGE: ' .. (f.autoForge.enabled and 'activado' or 'desactivado') .. ' | ' .. tostring(f.autoForge.message))
      local trace = f.autoForge.trace or {}
      for i = math.max(1, #trace - 7), #trace do add('  ' .. trace[i]) end
    end
  end
  if s.survey then
    local parts = {}
    for _, tableName in ipairs(sortedKeys(s.survey.missing)) do
      local names = s.survey.missing[tableName]
      if #names > 0 then parts[#parts + 1] = tableName .. ': ' .. table.concat(names, ', ') end
    end
    add('SONDEO: el bot usa ' .. tostring(s.survey.total) .. ' funciones del cliente; faltan ' .. tostring(s.survey.absent) ..
      (#parts > 0 and (' -> ' .. table.concat(parts, ' | ')) or ''))
  end
  if s.methodSurvey then
    local parts, unprobed = {}, {}
    for _, class in ipairs(sortedKeys(s.methodSurvey.subjects)) do
      if s.methodSurvey.subjects[class] == false then
        unprobed[#unprobed + 1] = class
      else
        local names = s.methodSurvey.missing[class] or {}
        if #names > 0 then parts[#parts + 1] = class .. ': ' .. table.concat(names, ', ') end
      end
    end
    add('METODOS: faltan ' .. tostring(s.methodSurvey.absent) .. ' de ' .. tostring(s.methodSurvey.total) ..
      (#parts > 0 and (' -> ' .. table.concat(parts, ' | ')) or '') ..
      (#unprobed > 0 and (' | sin probar: ' .. table.concat(unprobed, ', ')) or ''))
  end
  if s.portrait and ApiCompat and type(ApiCompat.describePortrait) == 'function' then
    local line = ApiCompat.describePortrait(s.portrait)
    if line then add(line) end
  end
  if s.nativeModules and ApiCompat and type(ApiCompat.describeModules) == 'function' then
    local line = ApiCompat.describeModules(s.nativeModules)
    if line then add(line) end
  end
  add('')
  local slots = {}
  for slot = 1, 11 do slots[#slots + 1] = slot .. ':' .. tostring(s.equipment[slot] or '?') end
  add('EQUIPO (slot:id): ' .. table.concat(slots, ' '))
  local caps = s.capabilities or {}
  add('getFinger()/getNeck() nativos: ' .. tostring(s.nativeFinger) .. ' / ' .. tostring(s.nativeNeck) ..
    '  | slots usados: dedo=' .. tostring(caps.fingerSlot) .. ' cuello=' .. tostring(caps.neckSlot))
  local trace = s.equipTrace or {}
  if #trace == 0 then
    add('Intentos de equipar: ninguno desde la carga')
  else
    add('Ultimos intentos de equipar (id metodos | antes -> despues, dedo/cuello):')
    for i = math.max(1, #trace - 5), #trace do
      local e = trace[i]
      local b, a = e.before or {}, e.after
      add('  ' .. tostring(e.itemId) .. ' ' .. table.concat(e.tried or {}, ',') .. (e.cached and ' (cache)' or '') ..
        ' | ' .. tostring(b.finger) .. '/' .. tostring(b.neck) .. ' -> ' ..
        (a and (tostring(a.finger) .. '/' .. tostring(a.neck)) or '(sin confirmar)'))
    end
  end

  if s.itemCatalog then
    add('')
    add('Catalogo de objetos: ' .. (s.itemCatalog.ready and ('listo, ' .. tostring(s.itemCatalog.items) .. ' IDs') or 'no disponible') ..
      ' | valores omitidos: ' .. tostring(s.itemCatalog.skipped))
  end
  return table.concat(lines, '\n')
end

local function serverEntry(s)
  local world = s.server.world
  local id = s.server.id ~= 'unknown' and s.server.id
    or (world and world:lower():gsub('[^%w_%-]+', '-'))
    or (s.server.host and s.server.host:lower():gsub('[^%w_%-]+', '-'))
    or 'nuevo-servidor'
  local entry = {
    id = id,
    name = s.server.name ~= 'Unknown Server' and s.server.name or (world or s.server.host or 'Nuevo servidor'),
    datSignatures = s.datSignatureDecimal and {s.datSignatureDecimal} or {},
    protocol = 'auto',
  }
  if s.server.host then entry.hosts = {s.server.host} end
  if world then entry.worldNames = {world} end
  return entry
end

local function toJson(value)
  if type(json) == 'table' and type(json.encode) == 'function' then
    local ok, text = pcall(json.encode, value, 2)
    if ok then return text end
  end
  return nil
end

local function copyToClipboard(text)
  if g_window and type(g_window.setClipboardText) == 'function' then
    return pcall(g_window.setClipboardText, text)
  end
  return false
end

local function saveReport(s)
  local text = toJson(s)
  if not text then return false, 'json.encode no disponible' end
  if type(g_resources) ~= 'table' or type(g_resources.makeDir) ~= 'function' or type(g_resources.writeFileContents) ~= 'function' then
    return false, 'no se puede escribir en este cliente'
  end
  local base = type(configDir) == 'string' and configDir:gsub('\\', '/'):gsub('/+$', '')
  if not base or not base:match('^/bot/[^/]+$') or base:find('..', 1, true) then
    return false, 'ruta de configuracion no valida'
  end
  local ok, err = pcall(function()
    g_resources.makeDir(base .. '/_diagnostics')
    g_resources.writeFileContents(base .. '/_diagnostics/client-report.json', text)
  end)
  if not ok then return false, tostring(err) end
  return true, base .. '/_diagnostics/client-report.json'
end

local panel = setupUI([[
Panel
  height: 19

  HelperThemeButton
    id: open
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: 17
    text: Diagnostico de cliente
    tooltip: Cliente, servidor, firma DAT y funciones disponibles.
]])
panel:setId("clientDiagnosticsPanel")

g_ui.loadUIFromString([[
CDUI < HelperThemeWindow
  !text: tr('Diagnostico de cliente')
  font: verdana-11px-antialised
  size: 580 520
  @onEscape: self:hide()

  Label
    id: info
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: viewState.top
    margin-left: 6
    margin-right: 6
    margin-top: 4
    margin-bottom: 8
    text-wrap: true
    text-align: topLeft
    color: #e4edf3
    font: verdana-11px-antialised

  HelperThemeButton
    id: viewState
    anchors.left: parent.left
    anchors.bottom: refreshButton.top
    margin-left: 6
    margin-bottom: 4
    size: 90 21
    text: Estado
    font: verdana-11px-antialised

  HelperThemeButton
    id: viewConfig
    anchors.left: prev.right
    anchors.bottom: refreshButton.top
    margin-left: 4
    margin-bottom: 4
    size: 110 21
    text: Configuracion
    font: verdana-11px-antialised

  HelperThemeButton
    id: viewFiles
    anchors.left: prev.right
    anchors.bottom: refreshButton.top
    margin-left: 4
    margin-bottom: 4
    size: 150 21
    text: Comprobar archivos
    font: verdana-11px-antialised

  HelperThemeButton
    id: refreshButton
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    margin-left: 6
    size: 80 21
    text: Actualizar
    font: verdana-11px-antialised

  HelperThemeButton
    id: copyButton
    anchors.left: prev.right
    anchors.bottom: parent.bottom
    margin-left: 4
    size: 185 21
    text: Copiar entrada servers.json
    font: verdana-11px-antialised

  HelperThemeButton
    id: saveButton
    anchors.left: prev.right
    anchors.bottom: parent.bottom
    margin-left: 4
    size: 100 21
    text: Guardar informe
    font: verdana-11px-antialised

  HelperThemeButton
    id: closeButton
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    margin-right: 6
    size: 50 21
    text: Cerrar
    font: verdana-11px-antialised
]])

local rootWidget = g_ui.getRootWidget()
if rootWidget then
  local window = UI.createWindow('CDUI', rootWidget)
  window:hide()

  local current = nil
  local view = 'estado'
  local filesText = "Pulsa 'Comprobar archivos' para compilar todos los .lua sin ejecutarlos."
  local function render()
    if view == 'config' then
      window.info:setText(buildConfigText())
    elseif view == 'archivos' then
      window.info:setText(filesText)
    else
      window.info:setText(buildText(current))
    end
  end
  local function refresh()
    current = snapshot()
    render()
  end

  panel.open.onClick = function()
    refresh()
    window:show()
    window:raise()
    window:focus()
  end
  window.refreshButton.onClick = function()
    if view == 'archivos' then filesText = buildFilesText(checkFiles()) end
    refresh()
  end
  window.viewState.onClick = function() view = 'estado'; refresh() end
  window.viewConfig.onClick = function() view = 'config'; render() end
  window.viewFiles.onClick = function()
    view = 'archivos'
    filesText = buildFilesText(checkFiles())
    render()
  end
  window.closeButton.onClick = function() window:hide() end

  window.copyButton.onClick = function()
    refresh()
    local text = toJson(serverEntry(current))
    if text and copyToClipboard(text) then
      warn('Diagnostico: entrada de servers.json copiada al portapapeles.')
    else
      warn('Diagnostico: no se pudo copiar; usa "Guardar informe" y toma la firma de client-report.json.')
    end
  end

  window.saveButton.onClick = function()
    refresh()
    local ok, info = saveReport(current)
    warn(ok and ('Diagnostico: informe guardado en ' .. info) or ('Diagnostico: no se pudo guardar (' .. tostring(info) .. ')'))
  end
end

-- Keep a fresh report on disk after every load, so a log + client-report.json
-- pair is always available when something looks wrong.
pcall(function() saveReport(snapshot()) end)
