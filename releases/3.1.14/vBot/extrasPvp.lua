setDefaultTab("Main")

-- securing storage namespace
local panelName = "extrasPvp"
storage[panelName] = storage[panelName] or {}
local settings = storage[panelName]

-- Bot Settings keeps this script's storage and controls, but shares one window.
extrasPvp = BotSettings.window
local leftPanel, rightPanel = BotSettings.getColumns("pvp")

-- objects made by Kondrah - taken from creature editor, minor changes to adapt
local addCheckBox = function(id, title, defaultValue, dest, tooltip)
  local widget = UI.createWidget('BotSettingsCheckBox', dest)
  widget.onClick = function()
    widget:setOn(not widget:isOn())
    settings[id] = widget:isOn()
  end
  widget:setText(title)
  widget:setTooltip(tooltip)
  if settings[id] == nil then
    widget:setOn(defaultValue)
  else
    widget:setOn(settings[id])
  end
  settings[id] = widget:isOn()
end

local addItem = function(id, title, defaultItem, dest, tooltip)
  local widget = UI.createWidget('BotSettingsItem', dest)
  widget.text:setText(title)
  widget.text:setTooltip(tooltip)
  widget.item:setTooltip(tooltip)
  widget.item:setItemId(settings[id] or defaultItem)
  widget.item.onItemChange = function(widget)
    settings[id] = widget:getItemId()
  end
  settings[id] = settings[id] or defaultItem
end

local addTextEdit = function(id, title, defaultValue, dest, tooltip)
  local widget = UI.createWidget('BotSettingsTextEdit', dest)
  widget.text:setText(title)
  widget.textEdit:setText(settings[id] or defaultValue or "")
  widget.text:setTooltip(tooltip)
  widget.textEdit.onTextChange = function(widget,text)
    settings[id] = text
  end
  settings[id] = settings[id] or defaultValue or ""
end

local addScrollBar = function(id, title, min, max, defaultValue, dest, tooltip)
  local widget = UI.createWidget('BotSettingsScrollBar', dest)
  widget.text:setTooltip(tooltip)
  widget.scroll:setRange(min, max)
  widget.scroll.onValueChange = function(scroll, value)
    widget.text:setText(title .. ": " .. value)
    if value == 0 then
      value = 1
    end
    settings[id] = value
  end
  widget.scroll:setTooltip(tooltip)
  if max-min > 1000 then
    widget.scroll:setStep(100)
  elseif max-min > 100 then
    widget.scroll:setStep(10)
  end
  widget.scroll:setValue(settings[id] or defaultValue)
  widget.scroll.onValueChange(widget.scroll, widget.scroll:getValue())
end

addItem("mwRune", "Runa Magic Wall", 3180, leftPanel, "Magic Wall Rune.")
addItem("mwObj", "Objeto Magic Wall", 2128, leftPanel, "Magic Wall Object.")
addScrollBar("mwTime", "Magic Wall (segundos)", 1, 60, 20, leftPanel, "Default Magic Wall Time.")
addItem("wgRune", "Runa Wild Growth", 3156, leftPanel, "Wild Growth Rune.")
addItem("wgObj", "Objeto Wild Growth", 2130, leftPanel, "Wild Growth Object.")
addScrollBar("wgTime", "Wild Growth (segundos)", 1, 60, 45, leftPanel, "Default Magic Wall Time.")

-- Placed Magic Walls, including MythicOT's color and retro variants.
local magicWallIds = {
  [2128] = true, [2129] = true,
  [58242] = true, [58243] = true, [58244] = true,
  [58245] = true, [58246] = true, [58247] = true,
  [58248] = true, [58249] = true, [58250] = true
}

local function isMagicWall(id)
  id=tonumber(id)
  return id~=nil and (id == tonumber(settings.mwObj) or magicWallIds[id] == true)
end

local function isPlacedWall(id)
  return isMagicWall(id) or id==tonumber(settings.wgObj) or id==2130
end

addCheckBox("timers", "Mostrar tiempos de paredes", true, rightPanel, "Show times for Magic Walls and Wild Growths.")
if true then
  local activeTimers = {}
  local mwTime = settings.mwTime * 1000
  local wgTime = settings.wgTime * 1000

  local function pruneActiveTimers()
    for pos, expires in pairs(activeTimers) do
      if not expires or expires < now then
        activeTimers[pos] = nil
      end
    end
  end

  macro(5000, function()
    if not settings.timers then return end
    pruneActiveTimers()
  end)

  onAddThing(function(tile, thing)
    if not settings.timers then return end
    if not thing:isItem() then return end
    pruneActiveTimers()
    local timer = 0
    if isMagicWall(thing:getId()) then
      timer = mwTime
    elseif thing:getId() == settings.wgObj then
      timer = wgTime
    else 
      return
    end

    local pos = tile:getPosition().x .. "," .. tile:getPosition().y .. "," .. tile:getPosition().z
    if not activeTimers[pos] or activeTimers[pos] < now then    
      activeTimers[pos] = now + timer
    end
    tile:setTimer(activeTimers[pos] - now)
  end)

  onRemoveThing(function(tile, thing)
    if not settings.timers then return end
    if not thing:isItem() then return end
    if (isMagicWall(thing:getId()) or thing:getId() == settings.wgObj) and tile:getGround() then
      local pos = tile:getPosition().x .. "," .. tile:getPosition().y .. "," .. tile:getPosition().z
      activeTimers[pos] = nil
      tile:setTimer(0)
    end  
  end)
end

addCheckBox("holdMwall", "Mantener pared", false, rightPanel, "Marca casillas con las teclas de abajo. Intervalo fijo de 2000 ms entre solicitudes; reparte los turnos entre casillas y confirma cada pared.")
addTextEdit("holdMwHot", "Tecla Magic Wall", "Ctrl+F9", rightPanel)
addTextEdit("holdWgHot", "Tecla Wild Growth", "Ctrl+F10", rightPanel)
do
  local shared = modules and modules.game_bot or g_game
  if shared and type(shared.sabuezoHoldWallCleanup) == 'function' then shared.sabuezoHoldWallCleanup() end
  local session=shared and shared.sabuezoHoldWallSession or {}
  if type(session)~='table' then session={} end
  if shared then shared.sabuezoHoldWallSession=session end
  local active, busy, adopted = true, false, false
  local marks, pending, lastSend = {}, nil, session.lastSend
  local carriedPending=session.pending
  local carriedInflight=session.inflight
  local order, scanAt, retryAt, lastDispatchAt = 0, 0, 0, session.lastDispatchAt or -1
  local cooldownMs,clockFloor=2000,0
  local wakeAt, wakeToken, m = nil, 0, nil
  local pump
  local stats = {requests=0, appearances=0, observedAfterRequest=0, timeouts=0, localFailures=0,
    deferrals=0, scans=0, errors=0, resumed=0}
  local events = {}
  local function time()
    local value=g_clock and type(g_clock.millis)=='function' and g_clock.millis() or tonumber(now) or 0
    return math.max(value,clockFloor)
  end
  local function key(p) return p and p.x..','..p.y..','..p.z end
  local function point(p) return {x=p.x,y=p.y,z=p.z} end
  local function persist()
    -- Discard the old dynamic gates when migrating from R182.
    session.nativeSerial=nil;session.nativeReadyAt=nil;session.nativeTimer=nil;session.barCooldown=nil
    session.lastDispatchAt=lastDispatchAt
    session.lastSend=lastSend and {at=lastSend.at,rune=lastSend.rune} or nil
    session.pending=pending and {pos=point(pending.mark.pos),at=pending.at,rune=pending.rune,
      deadline=pending.deadline,missingAt=pending.mark.missingAt} or carriedPending
    local inflight={}
    for _,mark in pairs(marks) do
      local request=mark.inflight
      if request then inflight[#inflight+1]={pos=point(mark.pos),at=request.at,rune=request.rune,
        deadline=request.deadline,missingAt=mark.missingAt} end
    end
    session.inflight=adopted and inflight or carriedInflight
  end
  local function visible(p)
    local origin=player and player:getPosition()
    return p and origin and p.z==origin.z and math.max(math.abs(p.x-origin.x),math.abs(p.y-origin.y))<=7
  end
  local function text(kind) return kind=='mw' and 'HOLD MW' or 'HOLD WG' end
  local function note(kind,mark,t,extra)
    local entry={event=kind,at=t,pos=mark and point(mark.pos) or nil}
    for name,value in pairs(extra or {}) do entry[name]=value end
    events[#events+1]=entry
    if #events>24 then table.remove(events,1) end
  end
  local function nextOrder() order=order+1;return order end
  local function hasMarks()
    for _ in pairs(marks) do return true end
    return false
  end
  local function wallOn(tile)
    if not tile then return nil end
    for _,item in ipairs(tile:getItems() or {}) do
      if isPlacedWall(item:getId()) then return item:getId() end
    end
    local top=tile:getTopUseThing()
    if top and isPlacedWall(top:getId()) then return top:getId() end
  end
  local function sameKind(id,kind)
    return kind=='mw' and isMagicWall(id) or kind=='wg' and (id==tonumber(settings.wgObj) or id==2130)
  end
  local function drop(mark,clearText)
    marks[key(mark.pos)]=nil
    if pending and pending.mark==mark then pending=nil end
    mark.inflight=nil
    if clearText then
      local tile=g_map.getTile(mark.pos)
      if tile and tile:getText()==text(mark.kind) then tile:setText('') end
    end
  end
  local function clear()
    if not adopted and player and player:getPosition() then
      for _,tile in ipairs(g_map.getTiles(player:getPosition().z)) do
        if tile:getText()=='HOLD MW' or tile:getText()=='HOLD WG' then tile:setText('') end
      end
    end
    adopted=true;carriedPending=nil;carriedInflight=nil
    local old=marks
    for _,mark in pairs(old) do drop(mark,true) end
    marks={};pending=nil
    wakeAt=nil;wakeToken=wakeToken+1
    persist()
  end
  local function refresh(mark,tile,t)
    if not visible(mark.pos) or not tile then drop(mark,true);return false end
    local id=wallOn(tile)
    local request=mark.inflight or pending and pending.mark==mark and pending
    if id then
      if mark.present==false then
        stats.appearances=stats.appearances+1
        note('appeared',mark,t,{objectId=id,gapMs=mark.missingAt and t-mark.missingAt or nil})
      end
      if request then
        if sameKind(id,mark.kind) then
          stats.observedAfterRequest=stats.observedAfterRequest+1
          note('observed after request',mark,t,{objectId=id,requestMs=t-request.at,gapMs=mark.missingAt and t-mark.missingAt or nil})
        end
        if pending==request then pending=nil end
        mark.inflight=nil -- An ally's wall also covers this square; ownership is not inferred.
      end
      mark.present=true;mark.missingAt=nil;mark.failures=0;mark.retryAt=0
    elseif mark.present~=false then
      mark.present=false;mark.missingAt=t;mark.order=nextOrder();mark.retryAt=0
      note('empty',mark,t)
    end
    if not id and request and t>=request.deadline then
      if pending==request then pending=nil end
      mark.inflight=nil;stats.timeouts=stats.timeouts+1;mark.order=nextOrder()
      mark.failures=mark.failures+1;mark.retryAt=request.at+cooldownMs
      note('unconfirmed',mark,t,{requestMs=t-request.at})
    end
    return true
  end
  local function track(tile,kind,t)
    local p=tile:getPosition()
    if not visible(p) then return nil end
    local mark={pos=point(p),kind=kind,order=nextOrder(),failures=0,retryAt=0}
    marks[key(p)]=mark
    tile:setText(text(kind));refresh(mark,tile,t)
    return mark
  end
  local function arm(at)
    if not active or not settings.holdMwall or type(schedule)~='function' then return end
    at=math.max(time()+1,at)
    if wakeAt and wakeAt<=at then return end
    wakeAt=at;wakeToken=wakeToken+1
    local token=wakeToken
    local ok=pcall(schedule,math.max(1,at-time()),function()
      if not active or token~=wakeToken then return end
      wakeAt=nil;pump(false)
    end)
    if not ok then wakeAt=nil end -- The periodic watchdog remains available.
  end
  local function readyAt()
    return math.max(lastSend and lastSend.at+cooldownMs or 0,retryAt,lastDispatchAt+1),'fixed_2000'
  end
  local function startCooldown(request,remaining)
    local timer={expired=remaining<=0};request.timer=timer
    if remaining<=0 then return end
    local ok=type(schedule)=='function' and pcall(schedule,remaining,function()
      timer.expired=true
      if active and lastSend==request then
        clockFloor=math.max(clockFloor,request.at+cooldownMs)
        pump(false)
      end
    end)
    if not ok then timer.noScheduler=true end
  end
  local function sample(fn)
    if type(fn)~='function' then return nil end
    local ok,value=pcall(fn);value=ok and tonumber(value) or nil
    if value and value==value and value~=math.huge and value~=-math.huge then return value end
  end
  local function healingUrgent()
    if not HealBot or type(HealBot.isOn)~='function' or not HealBot.isOn() then return false end
    local cfg=HealBotConfig
    local profile=cfg and cfg.healbot and cfg.healbot[cfg.currentHealBotProfile]
    if not profile or type(profile.itemTable)~='table' then return false end
    local hpValue=sample(hppercent) or player and sample(function()return player:getHealthPercent()end)
    local mpValue=sample(manapercent)
    if hpValue and hpValue>60 and (not mpValue or mpValue>20) then return false end
    local readers={['HP%']=function()return hpValue end,['MP%']=function()return mpValue end,
      HP=hp,MP=mana,burst=burstDamageValue}
    local function matches(origin,sign,value)
      local current=sample(readers[origin]);value=tonumber(value)
      if current==nil or not value then return false end
      return sign=='<' and current<=value or sign=='>' and current>=value or sign=='=' and current==value
    end
    for _,entry in pairs(profile.itemTable) do
      if entry.enabled then
        local eligible=matches(entry.origin,entry.sign,entry.value)
        if entry.extraEnabled then
          local extra=matches(entry.extraOrigin,entry.extraSign,entry.extraValue)
          local relation=tostring(entry.extraRelation):lower():gsub('^%s+',''):gsub('%s+$','')
          if relation=='or' or relation=='o' then eligible=eligible or extra else eligible=eligible and extra end
        end
        if eligible or hpValue==nil then return true end
      end
    end
    return false
  end
  -- Observe healing while the item channel is busy, so its opportunity runs
  -- alongside the exhaust. The healer publishes its ACTUAL pending reply time.
  local healOpportunity,healOpportunityUntil=false,0
  local function healingPriorityUntil(t)
    if not healingUrgent() then healOpportunity=false;healOpportunityUntil=0;return 0 end
    local state
    if type(HealBot.getItemCooldownState)=='function' then
      local ok,value=pcall(HealBot.getItemCooldownState)
      if ok and type(value)=='table' then state=value end
    end
    if not healOpportunity then
      healOpportunity=true;healOpportunityUntil=t+20
    end
    local remaining=state and tonumber(state.pendingRemainingMs) or 0
    if remaining and remaining>0 then return math.max(healOpportunityUntil,t+remaining) end
    return healOpportunityUntil
  end
  local function eligible(tile,mark)
    return tile and visible(mark.pos) and not wallOn(tile) and tile:getTopUseThing()
      and tile:canShoot() and tile:isWalkable(false)
  end
  local function timeout()
    local ping=sample(g_game and g_game.getPing) or sample(getPing) or 100
    return math.max(250,math.min(2000,ping*2+180))
  end
  local function cycle(forceScan)
    if not active then return end
    if not settings.holdMwall or m and m.isOff() then pending=nil;return end
    local t=time()
    if not player or g_game and g_game.isOnline and not g_game.isOnline() or
      player:getHealthPercent()<=0 then return end
    if not adopted then
      adopted=true
      for _,tile in ipairs(g_map.getTiles(player:getPosition().z)) do
        local label=tile:getText()
        if (label=='HOLD MW' or label=='HOLD WG') and not marks[key(tile:getPosition())] then
          track(tile,label=='HOLD MW' and 'mw' or 'wg',t)
        end
      end
      local inherited=carriedInflight or (carriedPending and {carriedPending}) or {}
      for _,entry in ipairs(inherited) do
        local mark=marks[key(entry.pos)]
        if mark and mark.present==false then
          local request={mark=mark,at=entry.at,rune=entry.rune,deadline=entry.deadline}
          mark.inflight=request
          if carriedPending and key(entry.pos)==key(carriedPending.pos) then pending=request end
          mark.missingAt=entry.missingAt or mark.missingAt;stats.resumed=stats.resumed+1
        end
      end
      carriedPending=nil;carriedInflight=nil
    end
    if not hasMarks() then return end
    local healUntil=healingPriorityUntil(t)
    if forceScan or t>=scanAt then
      stats.scans=stats.scans+1;scanAt=t+20
      for _,mark in pairs(marks) do refresh(mark,g_map.getTile(mark.pos),t) end
    end
    if isInPz() or HelperPause and HelperPause.isPaused() or
      CaveBot and CaveBot.Flee and CaveBot.Flee.blocksCombat() then return end
    local at,source=readyAt()
    if lastSend and lastSend.timer and not lastSend.timer.expired and not lastSend.timer.noScheduler then
      arm(math.max(t+1,at));return
    end
    if t<at then arm(at);return end
    if t<healUntil then arm(healUntil);return end
    local selected,selectedTile,soon
    for _,mark in pairs(marks) do
      if mark.present==false then
        if mark.inflight and t<mark.inflight.deadline then soon=math.min(soon or mark.inflight.deadline,mark.inflight.deadline)
        elseif t<(mark.retryAt or 0) then soon=math.min(soon or mark.retryAt,mark.retryAt)
        elseif not selected or mark.order<selected.order then
          local tile=g_map.getTile(mark.pos)
          if refresh(mark,tile,t) and mark.present==false and not mark.inflight and t>=(mark.retryAt or 0) and eligible(tile,mark) then selected,selectedTile=mark,tile end
        end
      end
    end
    if not selected then if soon then arm(soon) end;return end
    local rune=tonumber(selected.kind=='mw' and settings.mwRune or settings.wgRune)
    if not rune or rune<=0 then return end
    local request={mark=selected,at=t,rune=rune,deadline=t+timeout()}
    local previous=lastSend
    pending=request;selected.inflight=request;lastSend=request -- Reserve before entering any API that can emit signals.
    local emitted=false
    local function send()
      local sentAt=time()
      request.at=sentAt;request.deadline=sentAt+timeout()
      startCooldown(request,cooldownMs)
      emitted=true;lastDispatchAt=sentAt;selected.order=nextOrder()
      stats.requests=stats.requests+1
      note('requested',selected,sentAt,{runeId=rune,queuedMs=sentAt-(selected.missingAt or sentAt),
        cooldownSource=source,readyAt=at,readyLateMs=source~='idle' and math.max(0,sentAt-at) or nil,
        intervalMs=previous and sentAt-previous.at or nil})
      return useWith(rune,selectedTile:getTopUseThing())
    end
    local ok,result=pcall(function()
      if PushMax and type(PushMax.performItem)=='function' then return PushMax.performItem('Mantener pared',rune,false,send) end
      return send()
    end)
    if not emitted then
      if pending==request then pending=nil end
      if selected.inflight==request then selected.inflight=nil end
      if lastSend==request then lastSend=previous end
      stats.deferrals=stats.deferrals+1;retryAt=t+20;arm(retryAt)
    elseif not ok or result==false then
      if pending==request then pending=nil end
      if selected.inflight==request then selected.inflight=nil end
      if lastSend==request then lastSend=previous end
      stats.localFailures=stats.localFailures+1
      selected.failures=selected.failures+1;selected.retryAt=t+math.min(2000,250*2^math.min(3,selected.failures-1))
      retryAt=t+100;note('local failure',selected,t);arm(retryAt)
    else
      arm((readyAt()))
    end
  end
  pump=function(forceScan)
    if not active or busy then return end
    busy=true;local ok,err=pcall(cycle,forceScan);busy=false
    persist()
    if not ok then
      stats.errors=stats.errors+1;retryAt=time()+250
      note('engine error',nil,time(),{detail=tostring(err):sub(1,160)});arm(retryAt)
    end
  end
  if lastSend then startCooldown(lastSend,math.max(0,lastSend.at+cooldownMs-time())) end
  local function gameEnd()
    if not active then return end
    clear();adopted=false;lastSend=nil;clockFloor=0
    retryAt=0;lastDispatchAt=-1;scanAt=0
    healOpportunity=false;healOpportunityUntil=0
    carriedPending=nil;carriedInflight=nil;persist()
  end
  local function addListener(name,fn)
    local listeners=g_game[name]
    if listeners==nil then g_game[name]=fn
    elseif type(listeners)=='function' then g_game[name]={listeners,fn}
    elseif type(listeners)=='table' then table.insert(listeners,fn)
    else return false end
    return true
  end
  local function removeListener(name,fn)
    local listeners=g_game[name]
    if listeners==fn then g_game[name]=nil
    elseif type(listeners)=='table' then
      for i=#listeners,1,-1 do if listeners[i]==fn then table.remove(listeners,i) end end
      if #listeners==1 then g_game[name]=listeners[1] end
    end
  end
  local function cleanup()
    if not active then return end
    persist() -- A reload must not immediately duplicate an in-flight use.
    active=false;wakeToken=wakeToken+1;wakeAt=nil;pending=nil
    removeListener('onGameEnd',gameEnd)
    if shared and shared.sabuezoHoldWallCleanup==cleanup then shared.sabuezoHoldWallCleanup=nil end
  end
  pcall(addListener,'onGameEnd',gameEnd)
  if shared then shared.sabuezoHoldWallCleanup=cleanup end
  local oldDestroy=extrasPvp and extrasPvp.onDestroy
  if extrasPvp then extrasPvp.onDestroy=function(widget)
    cleanup()
    if type(oldDestroy)=='function' then return oldDestroy(widget)
    elseif type(oldDestroy)=='table' then for _,fn in pairs(oldDestroy) do if fn(widget) then return true end end end
  end end
  m=macro(20,function()pump(false);return true end)
  onRemoveThing(function(tile,thing)
    if not active or not tile or not thing or not thing:isItem() or not isPlacedWall(thing:getId()) then return end
    local mark=marks[key(tile:getPosition())]
    if mark then
      refresh(mark,tile,time());pump(false)
      -- Some clients notify removal before updating the tile snapshot. Retry
      -- once after the callback returns, rather than waiting for a full scan.
      if mark.present and marks[key(mark.pos)]==mark and not mark.recheckQueued and type(schedule)=='function' then
        mark.recheckQueued=true
        local ok=pcall(schedule,1,function()
          mark.recheckQueued=nil
          if active and marks[key(mark.pos)]==mark then pump(true) end
        end)
        if not ok then mark.recheckQueued=nil end
      end
    end
  end)
  onAddThing(function(tile,thing)
    if not active or not tile or not thing or not thing:isItem() or not isPlacedWall(thing:getId()) then return end
    local mark=marks[key(tile:getPosition())]
    if mark then refresh(mark,tile,time());pump(false) end
  end)
  onKeyDown(function(keys)
    if not active then return end
    if keys=='Escape' or keys=='Esc' then clear();return end
    if not settings.holdMwall or m.isOff() or not modules.game_walking.wsadWalking then return end
    if keys~=settings.holdMwHot and keys~=settings.holdWgHot then return end
    local tile=getTileUnderCursor()
    if not tile then return end
    local mark=marks[key(tile:getPosition())]
    if mark then drop(mark,true);persist()
    else track(tile,keys==settings.holdMwHot and 'mw' or 'wg',time());pump(false) end
  end)
  onKeyPress(function(keys)if active and (keys=='Escape' or keys=='Esc') then clear() end end)
  if type(onPlayerPositionChange)=='function' then onPlayerPositionChange(function()pump(true)end) end
  HoldWall={clear=clear,getStatus=function()
    local t=time();local at,source=readyAt()
    local result={revision='R184',fixedCooldownMs=cooldownMs,active=active,enabled=settings.holdMwall==true,
      cooldownSource=source,
      readyInMs=math.max(0,at-t),marked=0,waiting=0,inflight=0,stats={},events={}}
    for name,value in pairs(stats) do result.stats[name]=value end
    for _,mark in pairs(marks) do
      result.marked=result.marked+1;if mark.present==false then result.waiting=result.waiting+1 end
      if mark.inflight then result.inflight=result.inflight+1 end
    end
    if pending then result.pending={pos=point(pending.mark.pos),ageMs=t-pending.at} end
    for _,entry in ipairs(events) do
      local copy={};for name,value in pairs(entry) do copy[name]=name=='pos' and point(value) or value end
      result.events[#result.events+1]=copy
    end
    return result
  end}
  HoldWall.report=function()
    local status=HoldWall.getStatus()
    local function emit(message)
      if RinoConsole and type(RinoConsole.log)=='function' then pcall(RinoConsole.log,'info','Mantener pared',message)
      elseif type(info)=='function' then pcall(info,'[Mantener pared] '..message) end
    end
    emit('R184 | intervalo fijo=2000 ms | listo en='..status.readyInMs..' ms | solicitudes='..stats.requests..' | errores='..stats.errors)
    for i=math.max(1,#events-7),#events do
      local entry=events[i]
      emit(entry.at..' | '..entry.event..(entry.pos and ' | '..key(entry.pos) or '')..
        (entry.cooldownSource and ' | fuente='..entry.cooldownSource or '')..
        (entry.intervalMs and ' | entre solicitudes='..entry.intervalMs..' ms' or '')..
        (entry.readyAt and ' | listo='..entry.readyAt or '')..
        (entry.readyLateMs and ' | tras disponibilidad='..entry.readyLateMs..' ms' or '')..
        (entry.requestMs and ' | respuesta='..entry.requestMs..' ms' or '')..
        (entry.detail and ' | '..entry.detail or ''))
    end
  end
  local diagnostic=UI.createWidget('HelperThemeButton',rightPanel)
  if diagnostic.setHeight then diagnostic:setHeight(28) end
  if diagnostic.setEnabled then diagnostic:setEnabled(true) end
  diagnostic:setText('Ver tiempos MW')
  diagnostic:setTooltip('Muestra los tiempos en la consola. Mantener pared usa un intervalo fijo de 2000 ms entre solicitudes.')
  diagnostic.onClick=function()if active then HoldWall.report() end end
end


-- PUSH MAX
if false then
addItem("vsRune", "Runa para Anti Push", 3188, leftPanel, "Field rune to throw on target if trashed, to allow pushing.")
addScrollBar("vsDelay", "Espera al empujar", 1, 3000, 1100, leftPanel, "Default delay for pushing.")
addCheckBox("pushMax", "Push Max", false, rightPanel, "Mark players and destionations with below hotkey to push target.")
addTextEdit("pushHot", "Tecla Push Max", "PageUp", rightPanel)
if true then
  local config = {}

  local function syncConfig()
    config.enabled = settings.pushMax
    config.pushDelay = settings.vsDelay
    config.pushMaxRuneId = settings.vsRune
    config.mwallBlockId = tonumber(settings.mwObj) or settings.mwObj
    config.pushMaxKey = settings.pushHot
    return config
  end

  syncConfig()

    -- variables for config
  local fieldTable = {2118, 105, 2122}
  local cleanTile = nil

  -- scripts 

  local targetTile
  local pushTarget

  local resetData = function()
    for i, tile in pairs(g_map.getTiles(posz())) do
      if tile:getText() == "TARGET" or tile:getText() == "DEST" or tile:getText() == "CLEAR" then
        tile:setText('')
      end
    end
    pushTarget = nil
    targetTile = nil
    cleanTile = nil
  end

  local getCreatureById = function(id)
    for i, spec in ipairs(getSpectators()) do
      if spec:getId() == id then
        return spec
      end
    end
    return false
  end

  local isNotOk = function(t,tile)
    local tileItems = {}

    for i, item in pairs(tile:getItems()) do
      table.insert(tileItems, item:getId())
    end
    for i, field in ipairs(t) do
      if table.find(tileItems, field) then
        return true
      end
    end
    return false
  end

  local isOk = function(a,b)
    return getDistanceBetween(a,b) == 1
  end

  -- to mark
  local hold = 0
  onKeyDown(function(keys)
    syncConfig()
    if not config.enabled then return end
    if keys ~= config.pushMaxKey then return end
    hold = now
    local tile = getTileUnderCursor()
    if not tile then return end
    if pushTarget and targetTile then
      resetData()
      return
    end
    local creature = tile:getCreatures()[1]
    if not pushTarget and creature then
      pushTarget = creature
      if pushTarget then
        tile:setText('TARGET')
        pushTarget:setMarked('#00FF00')
      end
    elseif not targetTile and pushTarget then
      if pushTarget and getDistanceBetween(tile:getPosition(),pushTarget:getPosition()) ~= 1 then
        resetData()
        return
      else
        tile:setText('DEST')
        targetTile = tile
      end
    end
  end)

  -- mark tile to throw anything from it
  onKeyPress(function(keys)
    syncConfig()
    if not config.enabled then return end
    if keys ~= config.pushMaxKey then return end
    local tile = getTileUnderCursor()
    if not tile then return end

    if (hold - now) < -2500 then
      if cleanTile and tile ~= cleanTile then
        resetData()
      elseif not cleanTile then
        cleanTile = tile
        tile:setText("CLEAR")
      end
    end
    hold = 0
  end)

  onCreaturePositionChange(function(creature, newPos, oldPos)
    syncConfig()
    if not config.enabled then return end
    if creature == player then
      resetData()
    end
    if not pushTarget or not targetTile then return end
    if creature == pushTarget and newPos == targetTile then
      resetData()
    end
  end)

  macro(50, function()
    syncConfig()
    if not config.enabled then return end

    local pushDelay = tonumber(config.pushDelay) or 1100
    local rune = tonumber(config.pushMaxRuneId) or 3188
    local customMwall = config.mwallBlockId

    if cleanTile then
      local tilePos = cleanTile:getPosition()
      local pPos = player:getPosition()
      if not isOk(tilePos, pPos) then
        resetData()
        return
      end

      if not cleanTile:hasCreature() then return end
      local tiles = getNearTiles(tilePos)
      local destTile
      local forbidden = {}
      -- unfortunately double loop
      for i, tile in pairs(tiles) do
        local minimapColor = g_map.getMinimapColor(tile:getPosition())
        local stairs = (minimapColor >= 210 and minimapColor <= 213)
        if stairs then
          table.insert(forbidden, tile:getPosition())
        end
      end
      for i, tile in pairs(tiles) do
        local minimapColor = g_map.getMinimapColor(tile:getPosition())
        local stairs = (minimapColor >= 210 and minimapColor <= 213)
        if tile:isWalkable() and not isNotOk(fieldTable, tile) and not tile:hasCreature() and not stairs then
          local tooClose = false
          if #forbidden ~= 0 then
            for i=1,#forbidden do
              local pos = forbidden[i]
              if isOk(pos, tile:getPosition()) then
                tooClose = true
                break
              end
            end
          end
          if not tooClose then
            destTile = tile
            break
          end
        end
      end

      if not destTile then return end
      local parcel = cleanTile:getCreatures()[1]
      if parcel then
        test()
        g_game.move(parcel,destTile:getPosition())
        delay(2000)
      end
    else
      if not pushTarget or not targetTile then return end
      local tilePos = targetTile:getPosition()
      local targetPos = pushTarget:getPosition()
      if not isOk(tilePos,targetPos) then return end
      
      local tileOfTarget = g_map.getTile(targetPos)
      
      if not targetTile:isWalkable() then
        local topThing = targetTile:getTopUseThing()
        if not topThing then return resetData() end
        local topThingId = topThing:getId()
        if topThingId == 2129 or topThingId == 2130 or topThingId == customMwall then
          if targetTile:getTimer() < pushDelay+500 then
            vBot.isUsing = true
            schedule(pushDelay+700, function()
              vBot.isUsing = false
            end)
          end
          if targetTile:getTimer() > pushDelay then
            return
          end
        else
          return resetData()
        end
      end

      local targetThing = tileOfTarget and tileOfTarget:getTopUseThing()
      if targetThing and not targetThing:isNotMoveable() and targetTile:getTimer() < pushDelay+500 then
        return useWith(rune, pushTarget)
      end
      if isNotOk(fieldTable, targetTile) then
        if targetTile:canShoot() then
          return useWith(3148, targetTile:getTopUseThing())
        else
          return
        end
      end
        g_game.move(pushTarget,tilePos)
        delay(2000)
    end
  end)
end
end
