--[[
  ServerDetector - Server fingerprinting for Open Tibia Client forks
  Identifies server via DAT signature, connected IP/host, world name, and servers.json database.
]]

ServerDetector = ServerDetector or {}

local function readServerConfigFile()
  local candidates = {
    "_helper_client/servers.json",
    "/_helper_client/servers.json"
  }
  if configName then
    table.insert(candidates, "/bot/" .. configName .. "/_helper_client/servers.json")
  end
  table.insert(candidates, "/bot/Helper/_helper_client/servers.json")

  for _, path in ipairs(candidates) do
    if g_resources and type(g_resources.fileExists) == 'function' and g_resources.fileExists(path) then
      local ok, contents = pcall(g_resources.readFileContents, path)
      if ok and type(contents) == 'string' and contents ~= '' then
        ServerDetector.configSource = path
        return contents
      end
    end
  end

  -- Fallback to raw local IO if available
  local fileIO = (type(io) == 'table' and type(io.open) == 'function' and io)
    or (modules and modules.corelib and type(modules.corelib.io) == 'table' and modules.corelib.io)
    or (type(helperIO) == 'table' and helperIO)

  if fileIO and g_resources and type(g_resources.getWriteDir) == 'function' then
    local ok, writeDir = pcall(g_resources.getWriteDir)
    if ok and type(writeDir) == 'string' then
      local base = writeDir:gsub('\\', '/'):gsub('/+$', '')
      local fullPaths = {
        base .. '/_helper_client/servers.json',
        base .. '/bot/Helper/_helper_client/servers.json'
      }
      for _, fpath in ipairs(fullPaths) do
        local f = fileIO.open(fpath, 'rb')
        if f then
          local data = f:read('*a')
          f:close()
          if type(data) == 'string' and data ~= '' then
            ServerDetector.configSource = fpath
            return data
          end
        end
      end
    end
  end

  return nil
end

local warnedConfig = false
local function configProblem(message)
  ServerDetector.configError = message
  if not warnedConfig then
    warnedConfig = true
    if type(warn) == 'function' then pcall(warn, 'ServerDetector: ' .. message) end
  end
end

local function loadServersList()
  ServerDetector.configError = nil
  ServerDetector.configSource = nil
  local raw = readServerConfigFile()
  if not raw then
    configProblem('no se pudo leer _helper_client/servers.json')
    return {}
  end
  if not json or type(json.decode) ~= 'function' then
    configProblem('json.decode no esta disponible')
    return {}
  end
  local ok, data = pcall(json.decode, raw)
  if ok and type(data) == 'table' and type(data.servers) == 'table' then
    return data.servers
  end
  configProblem('servers.json tiene un formato invalido')
  return {}
end

-- Signatures may be written as decimal numbers, decimal strings or 0x hex
-- strings. Compare them all in one canonical decimal form.
local function normalizeSignature(value)
  if value == nil then return nil end
  local n = tonumber(value)
  if n and n == n and n >= 0 and n % 1 == 0 then
    return string.format('%.0f', n)
  end
  return tostring(value):lower()
end

local function getDatSignature()
  if g_things and type(g_things.getDatSignature) == 'function' then
    local ok, sig = pcall(g_things.getDatSignature)
    -- Clients that load protobuf appearances (e.g. Valkaris 15.30) report 0:
    -- that is "no signature", not a value that could identify a server.
    if ok and sig and tonumber(sig) ~= 0 then return sig end
  end
  return nil
end

local function getServerHost()
  if g_game and type(g_game.getServerHost) == 'function' then
    local ok, host = pcall(g_game.getServerHost)
    if ok and type(host) == 'string' and host ~= '' then return host end
  end
  if modules and modules.client_entergame and modules.client_entergame.EnterGame then
    local eg = modules.client_entergame.EnterGame
    if eg.server and type(eg.server) == 'string' and eg.server ~= '' then return eg.server end
    if eg.host and type(eg.host) == 'string' and eg.host ~= '' then return eg.host end
  end
  if G and G.host and type(G.host) == 'string' and G.host ~= '' then
    return G.host
  end
  return nil
end

local function getWorldName()
  if g_game and type(g_game.getWorldName) == 'function' then
    local ok, name = pcall(g_game.getWorldName)
    if ok and type(name) == 'string' and name ~= '' then return name end
  end
  return nil
end

function ServerDetector.detect()
  local datSig = getDatSignature()
  local host = getServerHost()
  local world = getWorldName()
  local servers = loadServersList()

  local matchedServer = nil

  if datSig or host or world then
    for _, s in ipairs(servers) do
      if type(s) == 'table' then
        -- 1. Match by DAT signature
        if datSig and type(s.datSignatures) == 'table' then
          for _, sig in ipairs(s.datSignatures) do
            if normalizeSignature(sig) == normalizeSignature(datSig) then
              matchedServer = s
              ServerDetector.matchedBy = 'datSignature'
              break
            end
          end
        end

        -- 2. Match by host / IP
        if not matchedServer and host then
          if type(s.host) == 'string' and s.host:lower() == host:lower() then
            matchedServer = s
            ServerDetector.matchedBy = 'host'
          elseif type(s.hosts) == 'table' then
            for _, h in ipairs(s.hosts) do
              if tostring(h):lower() == host:lower() then
                matchedServer = s
                ServerDetector.matchedBy = 'host'
                break
              end
            end
          end
        end

        -- 3. Match by world name
        if not matchedServer and world and type(s.worldNames) == 'table' then
          for _, w in ipairs(s.worldNames) do
            if tostring(w):lower() == world:lower() then
              matchedServer = s
              ServerDetector.matchedBy = 'worldName'
              break
            end
          end
        end

        if matchedServer then break end
      end
    end
  end

  -- The stable updater preserves private servers.json files. Ship the known
  -- Valkaris world match here so it also works on older or fresh installs.
  if not matchedServer and world and world:lower() == 'valkaris ot' then
    matchedServer = {id='valkaris', name='Valkaris OT', protocol='auto'}
    ServerDetector.matchedBy = 'worldName'
  end

  -- A client is not a server: the same client can connect to any server, so
  -- the client id is never used to guess the server. It is only reported.
  ServerDetector.clientId = ClientDetector and ClientDetector.id or nil
  ServerDetector.datSignature = datSig
  ServerDetector.host = host
  ServerDetector.world = world

  if matchedServer then
    ServerDetector.serverId   = matchedServer.id
    ServerDetector.serverName = matchedServer.name or matchedServer.id
    ServerDetector.profile    = matchedServer
  else
    ServerDetector.matchedBy  = nil
    ServerDetector.serverId   = 'unknown'
    ServerDetector.serverName = 'Unknown Server'
    ServerDetector.profile    = {}
  end

  return ServerDetector
end

-- Re-run detection (for example after a reconnect or after editing servers.json).
function ServerDetector.refresh()
  return ServerDetector.detect()
end

function ServerDetector.getServerId()
  return ServerDetector.serverId or 'unknown'
end

function ServerDetector.getServerName()
  return ServerDetector.serverName or 'Unknown Server'
end

function ServerDetector.getDatSignature()
  return ServerDetector.datSignature
end

-- Run initial detection
ServerDetector.detect()

return ServerDetector
