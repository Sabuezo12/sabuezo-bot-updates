local type, pairs, ipairs, pcall, tostring, tonumber, error = type, pairs, ipairs, pcall, tostring, tonumber, error
local Hotkeys={}
local OPTIONS_PATH='/settings/clientoptions.json'
local LOCK_PATH='/settings/.helper-hotkey-save.lock'

local function copy(value)
  if type(value)~='table' then return value end
  local result={}
  for key,child in pairs(value) do result[key]=copy(child) end
  return result
end

local function same(a,b)
  if a==b then return true end
  if type(a)~='table' or type(b)~='table' then return false end
  for key,value in pairs(a) do if not same(value,b[key]) then return false end end
  for key in pairs(b) do if a[key]==nil then return false end end
  return true
end

local function data(array)
  local hotkeys=type(array)=='table' and array.hotkeyOptions
  if type(hotkeys)=='table' and type(hotkeys.hotkeySets)=='table' and type(array.profiles)=='table' then
    return hotkeys,hotkeys.hotkeySets
  end
end

local function readDisk(api)
  if not api.resources.fileExists(OPTIONS_PATH) then return end
  local ok,value=pcall(function() return api.json.decode(api.resources.readFileContents(OPTIONS_PATH)) end)
  if ok and data(value) then return value end
end

local function merge(array,disk,baseline)
  local current,ours=data(array)
  local _,theirs=data(disk)
  local sets={}
  for name,preset in pairs(theirs) do sets[name]=preset end
  for name,preset in pairs(ours) do
    if not same(preset,baseline[name]) then sets[name]=preset end
  end
  for name in pairs(baseline) do
    if ours[name]==nil then sets[name]=nil end
  end
  local names,seen={},{}
  for _,list in ipairs({disk.profiles,array.profiles}) do
    for _,name in ipairs(list) do
      if sets[name] and not seen[name] then
        names[#names+1]=name
        seen[name]=true
      end
    end
  end
  local hotkeys={}
  for key,value in pairs(current) do hotkeys[key]=value end
  hotkeys.hotkeySets=sets
  if not sets[hotkeys.currentHotkeySetName] then hotkeys.currentHotkeySetName=names[1] end
  return hotkeys,names
end

-- Serializes the native JSON read/modify/write across the local Next Gen instances.
local function acquire(state)
  local api=state.api
  if not api.lockFile then return true end
  local file,_,code=api.io.open(api.lockFile,'wx')
  if file then
    local wrote=file:write(tostring(api.time()))
    file:flush()
    if wrote then return file end
    file:close()
    api.resources.deleteFile(LOCK_PATH)
    return true
  end
  if code~=17 and not api.resources.fileExists(LOCK_PATH) then return true end
  local now=api.time()
  local ok,value=pcall(api.resources.readFileContents,LOCK_PATH)
  local stamped=ok and tonumber(value)
  state.lockSeenAt=state.lockSeenAt or now
  if now-(stamped or state.lockSeenAt)>15 then
    api.resources.deleteFile(LOCK_PATH)
    state.lockSeenAt=nil
  end
end

local function save(state)
  if state.saving then return end
  local lock=acquire(state)
  if not lock then
    if not state.retry then
      state.retry=true
      state.api.schedule(function()
        state.retry=false
        state.save()
      end,75)
    end
    return
  end
  state.lockSeenAt=nil
  state.saving=true
  local options=state.api.options
  local array=options.array
  local originalHotkeys,ours=data(array)
  local originalNames=array and array.profiles
  local written
  local ok,err=pcall(function()
    local disk=ours and readDisk(state.api)
    if disk then array.hotkeyOptions,array.profiles=merge(array,disk,state.baseline) end
    state.originalSave()
    if ours then
      local _,saved=data(readDisk(state.api))
      written=same(saved,array.hotkeyOptions.hotkeySets)
    end
  end)
  if originalHotkeys then array.hotkeyOptions,array.profiles=originalHotkeys,originalNames end
  if lock~=true then
    lock:close()
    state.api.resources.deleteFile(LOCK_PATH)
  end
  state.saving=false
  if not ok then error(err,0) end
  if written then state.baseline=copy(ours) end
end

local function findPreset(names,character)
  local wanted=character:lower()
  for _,name in ipairs(names) do
    if type(name)=='string' and name:lower()==wanted then return name end
  end
end

local function apply(state,player)
  local id=player:getId()
  if state.appliedTo==id then return true end
  local api=state.api
  local options,settings,loaded=api.options,api.settings,api.loadedPlayer
  if not loaded:isLoaded() or loaded:getId()~=id then return false end
  local name=player:getName()
  if type(name)~='string' or type(loaded:getName())~='string' or loaded:getName():lower()~=name:lower() then return false end
  if not options.getAutoSwtichPreset() then
    state.appliedTo=id
    return true
  end
  local array=options.array
  local _,sets=data(array)
  if not sets then return false end
  local profile=findPreset(array.profiles,name)
  if not profile or type(sets[profile])~='table' then
    state.appliedTo=id
    return true
  end

  local disk=readDisk(api)
  local _,saved=data(disk)
  if saved and type(saved[profile])=='table' and same(sets[profile],state.baseline[profile]) and
      not same(sets[profile],saved[profile]) then
    sets[profile]=saved[profile]
    state.baseline[profile]=copy(saved[profile])
    state.refreshProfile=true
  end
  if state.refreshProfile or options.currentHotkeySetName~=profile or options.currentHotkeySet~=sets[profile] then
    state.refreshProfile=true
    settings.autoSwitchHotkey()
    if options.currentHotkeySetName~=profile then return false end
    api.keyBinds:setupAndReset(profile, options.isChatOnEnabled and 'chatOn' or 'chatOff')
    settings.configureGeneralHotkeys()
    settings.CustomHotkeys.createList(true)
    settings.ActionHotkey.configureActionBarHotkeys()
    state.refreshProfile=nil
  end
  state.appliedTo=id
  return true
end

function Hotkeys.install(host,api)
  local options=api.options
  local _,sets=data(options.array)
  if not sets then return nil end
  local state=host.hotkeys
  if not state or state.options~=options then
    state={options=options,baseline=copy(sets)}
    host.hotkeys=state
    state.wrapper=function() return state.save() end
  end
  state.api=api
  state.save=function() return save(state) end
  state.apply=function(player) return apply(state,player) end
  if options.saveData~=state.wrapper then
    state.originalSave=options.saveData
    options.saveData=state.wrapper
  end
  return state
end

return Hotkeys
