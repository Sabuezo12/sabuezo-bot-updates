-- Observe manual moves without wrapping native window/drag callbacks. Only
-- newly opened BPs trigger a short, bounded placement recovery.
ContainerLayout = {}

function ContainerLayout.create(config, running, classify)
  if config.rememberPositions == nil then config.rememberPositions = true end
  if type(config.windowLayouts) ~= "table" then config.windowLayouts = {} end
  local records, owner, baseline = {}, nil, nil
  local settlingUntil, nextRestore, passes = 0, 0, 0
  local destroyed, dragging, applying, dirty, dirtyAt = false, false, false, false, 0
  local api = {}
  local function time() return g_clock and g_clock.millis() or now or 0 end
  local function call(object, method, ...)
    if not object or type(object[method]) ~= "function" then return nil end
    local ok, value = pcall(object[method], object, ...)
    if ok then return value end
  end
  local function id(widget) return call(widget, "getId") end
  local function active() return not destroyed and config.rememberPositions and running() end
  local function markDirty() dirty, dirtyAt = true, time() end
  local function flush()
    if dirty and not applying and not dragging and time()-dirtyAt >= 2000 and type(saveConfig) == "function" then
      dirty = false
      pcall(saveConfig)
    end
  end
  local function reset()
    records, baseline, settlingUntil, nextRestore, passes, dragging = {}, nil, 0, 0, 0, false
  end
  local function checkOwner()
    local player = g_game.getLocalPlayer and g_game.getLocalPlayer()
    local name = player and call(player, "getName") or nil
    if name ~= owner then reset(); owner = name end
    return owner ~= nil and owner ~= ""
  end
  local function layouts()
    local data = config.windowLayouts[owner]
    if type(data) ~= "table" then data = {}; config.windowLayouts[owner] = data end
    return data
  end
  local function alive(record)
    return record.container.window ~= nil and call(record.window, "isDestroyed") ~= true and
      id(record.window) == record.windowId
  end
  local function parentPath(parent)
    local root, path = g_ui.getRootWidget(), {}
    for _=1,24 do
      if parent == root or (id(parent) == id(root) and id(root) ~= "") then return path end
      local ancestor = call(parent, "getParent")
      if not ancestor then
        if id(parent) == id(root) and call(parent,"getClassName") == call(root,"getClassName") then return path end
        return nil
      end
      local name, class = id(parent), call(parent, "getClassName")
      if type(name) ~= "string" or type(class) ~= "string" then return nil end
      local ordinal, found = 0, false
      local parentIndex = call(ancestor, "getChildIndex", parent)
      for index, child in ipairs(call(ancestor, "getChildren") or {}) do
        if id(child) == name and call(child, "getClassName") == class then ordinal = ordinal+1 end
        if index == parentIndex or child == parent then found = true; break end
      end
      if not found or ordinal < 1 then return nil end
      table.insert(path, 1, {id=name, class=class, ordinal=ordinal})
      parent = ancestor
    end
  end
  local function pathKey(path)
    if type(path) ~= "table" then return nil end
    local parts = {}
    for _, step in ipairs(path) do
      if type(step) ~= "table" or type(step.id) ~= "string" or type(step.class) ~= "string" then return nil end
      parts[#parts+1] = #step.id..":"..step.id..#step.class..":"..step.class..":"..tostring(step.ordinal)
    end
    return table.concat(parts, "/")
  end
  local function resolve(path)
    if not pathKey(path) then return nil end
    local parent = g_ui.getRootWidget()
    for _, step in ipairs(path) do
      local found, ordinal = nil, 0
      for _, child in ipairs(call(parent, "getChildren") or {}) do
        if id(child) == step.id and call(child, "getClassName") == step.class then
          ordinal = ordinal+1
          if ordinal == step.ordinal then found = child; break end
        end
      end
      if not found then return nil end
      parent = found
    end
    return parent
  end
  local function signature(saved)
    if type(saved) ~= "table" then return nil end
    local parent = pathKey(saved.parent)
    if not parent then return nil end
    return parent.."|"..tostring(saved.docked).."|"..tostring(saved.index).."|"..tostring(saved.x).."|"..tostring(saved.y)
  end
  -- The previous observer had accumulated aliases of the same native window.
  -- Remove only identical placements for the same backpack type, once. Keep
  -- distinct slots/positions and never edit the storage JSON outside the client.
  if config.windowLayoutObserverVersion ~= 2 then
    for _, data in pairs(config.windowLayouts) do
      if type(data) == "table" then
        local keys, seen = {}, {}
        for key in pairs(data) do
          if type(key) == "string" and key:match("^bp:%d+:%d+$") then keys[#keys+1] = key end
        end
        table.sort(keys, function(a,b)
          local abase, an = a:match("^(bp:%d+):(%d+)$")
          local bbase, bn = b:match("^(bp:%d+):(%d+)$")
          if abase == bbase then return tonumber(an) < tonumber(bn) end
          return abase < bbase
        end)
        for _, key in ipairs(keys) do
          local sig = signature(data[key])
          if sig then
            local identity = key:match("^(bp:%d+):").."|"..sig
            if seen[identity] then data[key] = nil else seen[identity] = true end
          end
        end
      end
    end
    config.windowLayoutObserverVersion = 2
    markDirty()
  end
  local function position(record)
    if not alive(record) then return nil end
    local parent = call(record.window, "getParent")
    if not parent or call(record.window, "isDragging") == true then return nil end
    local path = parentPath(parent)
    if not path then return nil end
    local saved = {parent=path, docked=call(parent, "getClassName") == "UIMiniWindowContainer"}
    if saved.docked then
      saved.index = call(parent, "getChildIndex", record.window)
      if not saved.index or saved.index < 1 then return nil end
    else
      local point, origin = call(record.window, "getPosition"), call(parent, "getPosition")
      if not point or not origin then return nil end
      saved.x, saved.y = point.x-origin.x, point.y-origin.y
    end
    return saved
  end
  local function capture(missingOnly)
    if not active() or not checkOwner() or applying or dragging then return end
    local data = layouts()
    for _, record in pairs(records) do
      if not missingOnly or not data[record.key] then
        local saved = position(record)
        if saved and signature(saved) ~= signature(data[record.key]) then
          data[record.key] = saved; markDirty()
        end
      end
    end
  end
  local function observe()
    local frame = {positions={}, orders={}}
    for liveId, record in pairs(records) do
      local saved = position(record)
      if saved then
        frame.positions[liveId] = saved
        local key = pathKey(saved.parent)
        if saved.docked and not frame.orders[key] then
          local children, order, seen = call(call(record.window, "getParent"), "getChildren") or {}, {}, {}
          for _, child in ipairs(children) do
            local name = id(child)
            if type(name) == "string" and name ~= "" and not seen[name] then
              order[#order+1] = name; seen[name] = true
            end
          end
          frame.orders[key] = order
        end
      end
    end
    return frame
  end
  local function moved(frame)
    if not baseline then return false end
    for liveId, saved in pairs(frame.positions) do
      local old = baseline.positions[liveId]
      if old and (pathKey(old.parent) ~= pathKey(saved.parent) or
        not saved.docked and (old.x ~= saved.x or old.y ~= saved.y)) then return true end
    end
    -- Compare surviving siblings. Closing a window changes absolute indices
    -- but keeps their relative order; that shift must not become a new layout.
    for key, order in pairs(frame.orders) do
      local old = baseline.orders[key]
      if old then
        local oldSet, currentSet, a, b = {}, {}, {}, {}
        for _, name in ipairs(old) do oldSet[name] = true end
        for _, name in ipairs(order) do currentSet[name] = true end
        for _, name in ipairs(old) do if currentSet[name] then a[#a+1] = name end end
        for _, name in ipairs(order) do if oldSet[name] then b[#b+1] = name end end
        for i=1,#a do if a[i] ~= b[i] then return true end end
      end
    end
    return false
  end
  local function isDragging()
    for _, record in pairs(records) do
      if call(record.window, "isDragging") == true then return true end
    end
    return false
  end
  local function mouseBusy()
    if g_mouse and type(g_mouse.isPressed) == "function" then
      local ok, pressed = pcall(g_mouse.isPressed, 1)
      return ok and pressed == true
    end
    return false
  end
  function api.attach(container, previous)
    if not active() or not checkOwner() or not container.window or applying then return nil end
    local liveId, windowId, base = call(container, "getId"), id(container.window), classify(container)
    if liveId == nil or type(windowId) ~= "string" or not base then return nil end
    base = tostring(base)
    local existing = records[liveId]
    if not previous and existing and existing.windowId == windowId and existing.base == base and alive(existing) then
      existing.container, existing.window = container, container.window
      return existing
    end
    local previousId = previous and call(previous, "getId")
    local prior = previousId and records[previousId] or existing
    local key = prior and prior.base == base and prior.key or nil
    if prior then records[previousId or liveId] = nil end
    local used = {}
    for slot, record in pairs(records) do
      if not alive(record) then records[slot] = nil else used[record.key] = true end
    end
    if not key then
      local n = 1
      while used[base..":"..n] do n = n+1 end
      key = base..":"..n
    end
    local record = {container=container, window=container.window, windowId=windowId, base=base, key=key}
    records[liveId] = record
    settlingUntil, nextRestore, passes = time()+2200, time()+100, 0
    return record
  end
  local function watchOpen()
    local seen = {}
    for _, container in pairs(g_game.getContainers()) do
      local liveId = call(container, "getId")
      if liveId ~= nil and not seen[liveId] and api.attach(container) then seen[liveId] = true end
    end
    for liveId, record in pairs(records) do
      if not seen[liveId] or not alive(record) then records[liveId] = nil end
    end
  end
  function api.restore()
    if not active() or not checkOwner() or applying or dragging or isDragging() or mouseBusy() then return end
    local ordered, data = {}, layouts()
    for _, record in pairs(records) do
      local saved = data[record.key]
      if alive(record) and signature(saved) then ordered[#ordered+1] = {record=record, saved=saved} end
    end
    table.sort(ordered, function(a,b)
      local ai, bi = tonumber(a.saved.index) or 0, tonumber(b.saved.index) or 0
      if ai == bi then return a.record.key < b.record.key end
      return ai < bi
    end)
    applying = true
    local groups, budget = {}, 64
    for _, entry in ipairs(ordered) do
      local window, saved = entry.record.window, entry.saved
      local parent = resolve(saved.parent)
      if parent and call(window, "getParent") ~= parent and budget > 0 then
        budget = budget-1; call(parent, "addChild", window)
      end
      if parent and call(window, "getParent") == parent then
        if saved.docked then
          local key = pathKey(saved.parent)
          groups[key] = groups[key] or {parent=parent, entries={}}
          groups[key].entries[#groups[key].entries+1] = entry
        elseif type(saved.x) == "number" and type(saved.y) == "number" then
          local origin, point = call(parent, "getPosition"), call(window, "getPosition")
          if origin and point and (point.x ~= origin.x+saved.x or point.y ~= origin.y+saved.y) and budget > 0 then
            budget = budget-1; call(window, "setPosition", {x=origin.x+saved.x,y=origin.y+saved.y})
          end
        end
      end
    end
    for _, group in pairs(groups) do
      local parent, windows, desired, target = group.parent, {}, {}, {}
      for _, entry in ipairs(group.entries) do windows[entry.record.windowId] = entry.record.window end
      for _, child in ipairs(call(parent, "getChildren") or {}) do
        if not windows[id(child)] then desired[#desired+1] = child end
      end
      for _, entry in ipairs(group.entries) do
        local index = math.max(1, math.min(tonumber(entry.saved.index) or #desired+1, #desired+1))
        table.insert(desired,index,entry.record.window)
        entry.record.window.miniIndex = index
      end
      for index, child in ipairs(desired) do target[id(child)] = index end
      -- Only move managed windows. Unrelated panels retain their relative order.
      -- A failed native move exits immediately; there is no unbounded retry loop.
      for index, child in ipairs(desired) do
        local desiredId = id(child)
        if windows[desiredId] then
          if call(parent,"getChildIndex",windows[desiredId]) ~= index and budget > 0 then
            budget = budget-1; call(parent,"moveChildToIndex",windows[desiredId],index)
          end
        else
          while budget > 0 do
            local current = (call(parent,"getChildren") or {})[index]
            local currentId = id(current)
            if currentId == desiredId or not windows[currentId] then break end
            local destination = target[currentId]
            if not destination or destination <= index then break end
            budget = budget-1; call(parent,"moveChildToIndex",windows[currentId],destination)
            if call(parent,"getChildIndex",windows[currentId]) ~= destination then break end
          end
        end
        if budget <= 0 then break end
      end
      if budget <= 0 then break end
    end
    applying = false
    baseline = observe()
  end
  function api.beforeReopen()
    if not active() or applying or not checkOwner() then return end
    watchOpen()
    local frame = observe()
    if settlingUntil == 0 and moved(frame) then capture(false) else capture(true) end
    baseline = frame
  end
  function api.tick()
    if not active() or applying or not checkOwner() then return end
    watchOpen()
    if isDragging() then
      dragging, settlingUntil, passes = true, 0, 0
      return
    end
    if mouseBusy() then return end
    local frame = observe()
    if dragging then
      dragging, settlingUntil = false, 0
      capture(false)
    elseif settlingUntil > 0 then
      if time() >= nextRestore and passes < 4 then
        passes, nextRestore = passes+1, time()+500
        api.restore(); frame = observe()
      end
      if time() >= settlingUntil then settlingUntil = 0; capture(true) end
    elseif moved(frame) then
      -- Read/save only. A manual move never starts another restore cycle.
      capture(false)
    end
    baseline = frame
    flush()
  end
  function api.closed(container)
    local liveId = call(container,"getId")
    if liveId ~= nil then records[liveId] = nil end
  end
  function api.reset() reset() end
  local function onEnd() reset(); owner = nil end
  function api.cleanup()
    if destroyed then return end
    destroyed = true; reset()
    local listeners = g_game.onGameEnd
    if listeners == onEnd then g_game.onGameEnd = nil
    elseif type(listeners) == "table" then
      for i=#listeners,1,-1 do if listeners[i] == onEnd then table.remove(listeners,i) end end
      if #listeners == 1 then g_game.onGameEnd = listeners[1] end
    end
  end
  local shared = modules and modules.game_bot
  if shared and type(shared.sabuezoContainerLayoutCleanup) == "function" then shared.sabuezoContainerLayoutCleanup() end
  if shared then shared.sabuezoContainerLayoutCleanup = api.cleanup end
  local listeners = g_game.onGameEnd
  if listeners == nil then g_game.onGameEnd = onEnd
  elseif type(listeners) == "function" then g_game.onGameEnd = {listeners,onEnd}
  elseif type(listeners) == "table" then table.insert(listeners,onEnd) end
  return api
end
