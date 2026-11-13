-- One source of truth for the collection method. Native capability checks do
-- not send packets; a module/window or a modern version alone is not proof.
TargetBot.LootMode={}
local M=TargetBot.LootMode
local rejected
local valid={auto=true,manual=true,native=true}
local featureReaders={}
local function featureValue(name,direct)
  if type(direct)=='number' then return direct end
  local advertised=HelperClient and HelperClient.nativeFeatures and HelperClient.nativeFeatures[name]
  if type(advertised)=='number'then return advertised end
  -- Some game_bot sandboxes omit feature constants while their supplied Lua
  -- loader can read them. Resolve only these fixed, read-only identifiers;
  -- never assume a numeric feature ID from another client fork.
  local reader=featureReaders[name]
  if reader==nil then
    local loader=loadstring or load
    local ok,value=pcall(loader,'return '..name)
    reader=ok and type(value)=='function' and value or false
    featureReaders[name]=reader
  end
  if reader then local ok,value=pcall(reader);if ok then return value end end
end
local function gameValue(name)
  if not g_game or type(g_game[name])~='function' then return nil end
  local ok,value=pcall(g_game[name]);if ok then return tonumber(value) end
end
function M.requested(cfg)
  cfg=cfg or TargetBot.LootPolicy and TargetBot.LootPolicy.current()
  if type(cfg)=='table' and cfg.version==3 and valid[cfg.engine] then return cfg.engine end
  -- Import the last legacy checkbox value, including changes made after the
  -- old version-2 manager was saved. Read-only drafts never migrate storage.
  local legacy=storage.extras and storage.extras.quickLootCorpses
  if legacy~=nil then return legacy and 'native' or 'manual' end
  if type(cfg)=='table' and valid[cfg.engine] then return cfg.engine end
  return 'auto'
end
function M.capabilities()
  local api
  if g_game and type(g_game.sendQuickLoot)=='function' then api='sendQuickLoot'
  elseif g_game and type(g_game.quickLoot)=='function' then api='quickLoot' end
  local confirmed=false
  if g_game and type(g_game.getFeature)=='function' then
    for _,feature in ipairs({featureValue('GameThingQuickLoot',GameThingQuickLoot) or false,
        featureValue('GameQuickLoot',GameQuickLoot) or false,
        featureValue('GameQuickLootFlags',GameQuickLootFlags) or false}) do
      if type(feature)=='number' and feature>0 and feature<256 and feature==math.floor(feature) then
        local ok,on=pcall(g_game.getFeature,feature)
        if ok and on==true then confirmed=true end
      end
    end
  end
  local version=gameValue('getProtocolVersion')
  if not version or version<=0 then version=gameValue('getClientVersion') or 0 end
  local reason
  if not api then reason='El cliente no expone una accion de Quick Loot.'
  elseif version>0 and version<=860 and not confirmed then reason='Este cliente 8.6 no anuncia Quick Loot.'
  elseif not confirmed then reason='El cliente no confirma soporte de Quick Loot.' end
  return {api=api,confirmed=confirmed,available=api~=nil and not(version>0 and version<=860 and not confirmed),reason=reason}
end
function M.resolve(requested)
  requested=requested or M.requested()
  if requested=='manual' then return 'manual','Seleccionado Tradicional.' end
  local cap=M.capabilities()
  if rejected then return 'manual',rejected end
  if not cap.available then return 'manual',cap.reason end
  if requested=='auto' and not cap.confirmed then return 'manual',cap.reason end
  return 'native',requested=='auto' and 'Quick Loot anunciado por el cliente.' or 'Seleccionado Quick Loot.'
end
function M.sync()
  local cfg=TargetBot.LootPolicy and TargetBot.LootPolicy.current()
  if cfg and cfg.version==3 then
    -- Compatibility mirror only. It can never override the saved selector.
    storage.extras.quickLootCorpses=M.resolve()=='native'
  end
end
function M.reset()rejected=nil;M.sync()end
function M.canSelect(requested)
  if not valid[requested] then return false,'Selecciona un metodo de recogida.' end
  if requested=='native' then
    local cap=M.capabilities()
    if not cap.available then return false,(cap.reason or 'Quick Loot no disponible.')..' Elige Automatico o Tradicional.' end
  end
  return true
end
function M.dispatch(corpse)
  local engine,reason=M.resolve()
  if engine~='native' then return false,reason end
  local api=M.capabilities().api
  local ok,result
  if api=='sendQuickLoot' then ok,result=pcall(g_game.sendQuickLoot,1,corpse)
  else ok,result=pcall(g_game.quickLoot,corpse) end
  if ok and result~=false then return true end -- dispatched, not server-confirmed
  rejected=ok and 'El cliente rechazo Quick Loot; se usa Tradicional.' or 'Fallo la accion de Quick Loot; se usa Tradicional.'
  M.sync()
  return false,rejected
end
function M.label(requested)
  requested=requested or M.requested()
  local engine,reason=M.resolve(requested)
  local label=engine=='native' and 'Quick Loot' or 'Tradicional'
  if requested=='auto' then label='Automatico: '..label end
  return label,reason
end
