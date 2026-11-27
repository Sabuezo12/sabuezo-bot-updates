-- auto recording for cavebot
CaveBot.Recorder = {}

local isEnabled = nil
local lastPos = nil
local lastTransition = nil
local lastInteraction = nil

local function copy(pos)
  return {x=pos.x,y=pos.y,z=pos.z}
end

-- Only the points needed (storage.extras.recordSmart, per profile; new profiles start ON):
-- after each step, the path the CaveBot itself would take from the last point to here is
-- compared with what was walked. While it stays on the walked track (2 SQM at most, 3 steps
-- longer at most) no point is needed; when it would leave it, the last tile that still matched
-- becomes the waypoint. At most SMART_MAX tiles apart. Off: one point every 5 tiles as before.
local SMART_MAX, SMART_DEVIATION, SMART_EXTRA = 10, 2, 3
local SMART_OFFSETS = {[0]={0,-1},{1,0},{0,1},{-1,0},{1,-1},{1,1},{-1,1},{-1,-1}}
local track, anchor = {}, nil
local function smart()
  return type(storage)=='table' and type(storage.extras)=='table' and storage.extras.recordSmart==true
end
local function chebyshev(a,b)
  return math.max(math.abs(a.x-b.x),math.abs(a.y-b.y))
end
-- A damage field (fire, energy, poison) the walker did not step on: the CaveBot ignores
-- fields when it plans, so a path across one is not the walked way round it.
local function fieldTile(p)
  local movement=TargetBot and TargetBot.Movement
  if not movement or type(movement.isDamageField)~='function' then return false end
  local ok,found=pcall(function()
    local tile=g_map.getTile(p)
    for _,item in ipairs(tile and tile:getItems() or {}) do
      if movement.isDamageField(item) then return true end
    end
    return false
  end)
  return ok and found==true
end
local function faithful(from,to,walked)
  local ok,path=pcall(findPath,from,to,SMART_MAX*3,{ignoreNonPathable=true,ignoreFields=true,
    ignoreCreatures=true,allowUnseen=true,allowOnlyVisibleTiles=false,precision=0})
  if not ok or type(path)~='table' then return false end
  if #path>#walked+SMART_EXTRA then return false end
  local stepped={}
  for _,q in ipairs(walked) do stepped[q.x..','..q.y]=true end
  local p=from
  for _,dir in ipairs(path) do
    local o=SMART_OFFSETS[dir]
    if not o then return false end
    p={x=p.x+o[1],y=p.y+o[2],z=p.z}
    local near=chebyshev(p,from)<=SMART_DEVIATION
    if not near then
      for _,q in ipairs(walked) do
        if chebyshev(p,q)<=SMART_DEVIATION then near=true;break end
      end
    end
    if not near then return false end
    if not stepped[p.x..','..p.y] and fieldTile(p) then return false end
  end
  return true
end
local function playerPos()
  local ok,pos=pcall(function() return player:getPosition() end)
  if ok and type(pos)=='table' and pos.x then return copy(pos) end
end
local function valid(pos)
  return type(pos)=='table' and type(pos.x)=='number' and type(pos.y)=='number' and type(pos.z)=='number' and pos.x~=0xFFFF
end
local function same(a,b)
  return a and b and a.x==b.x and a.y==b.y and a.z==b.z
end
local function stamp()
  return type(now)=='number' and now or 0
end
local function transitionUse(pos,toolId,targetId)
  local color=g_map and type(g_map.getMinimapColor)=='function' and tonumber(g_map.getMinimapColor(pos)) or 0
  if color and color>=210 and color<=213 then return true end
  local extras=storage and storage.extras or {}
  local ids
  if toolId==(extras.rope or 3003) then ids=Global and Global.ropeIds
  elseif toolId==(extras.shovel or 3457) then ids=Global and Global.shovelIds end
  for _,id in ipairs(ids or {})do if id==targetId then return true end end
  return false
end
-- Runes are combat, never part of a route: an avalanche thrown by AttackBot or
-- TargetBot while recording must not become a use/usewith step.
local RUNE_FIRST,RUNE_LAST=3147,3203
local RUNE_WINDOW=600
local lastRune=nil
local function isRune(itemId)
  local id=tonumber(itemId)
  if not id or id<=0 then return false end
  if id>=RUNE_FIRST and id<=RUNE_LAST then return true end
  if g_things and type(g_things.getThingType)=='function' then
    local ok,rune=pcall(function()
      local kind=g_things.getThingType(id,ThingCategoryItem or 0)
      return kind and kind.isRune and kind:isRune()
    end)
    if ok and rune then return true end
  end
  return false
end
local function hasMonster(pos)
  local ok,found=pcall(function()
    local tile=g_map and g_map.getTile and g_map.getTile(pos)
    for _,creature in ipairs(tile and tile:getCreatures() or {}) do
      if creature:isMonster() then return true end
    end
    return false
  end)
  return ok and found
end
-- Remembers a rune cast so the same click, reported again by the client as a
-- plain use of that tile, is not recorded either.
local function runeCast(itemId,pos)
  if not isRune(itemId) then return false end
  lastRune={pos=valid(pos) and copy(pos) or nil,at=stamp()}
  return true
end
local function afterRune(pos)
  if not lastRune or stamp()-lastRune.at>RUNE_WINDOW then return false end
  return not lastRune.pos or same(lastRune.pos,pos)
end
-- NPC trips and conversations. What the player types to an NPC is read from the
-- client's talk functions while recording (or from the server's echo of our own
-- words, where it sends one); the NPC's answers arrive as NPC speech. A
-- conversation followed by a far jump becomes one travel action (same rule the
-- travel action uses to confirm a trip); without a trip it becomes its npcsay
-- lines, placed before whatever is recorded next.
local TALK_REACH,TALK_IDLE,TRIP_WINDOW=4,30000,20000
local TALK_HOOK='rinoRecorderTalkHook'
local GREETING={hi=true,hello=true,hola=true,ola=true,oi=true,hey=true}
local AGREE={yes=true,si=true,['s\195\173']=true,sim=true,no=true}
local CLOSING={bye=true,farewell=true,adios=true,tchau=true}
local talk,lastNpc,heardTyped,talkWord=nil,nil,false,nil
local function modeOf(name,fallback)
  local value=type(MessageModes)=='table' and tonumber(MessageModes[name])
  return value or fallback
end
local function sayMode(mode)
  mode=tonumber(mode)
  return mode==nil or mode==modeOf('Say',1) or mode==modeOf('Whisper',2) or mode==modeOf('Yell',3)
end
local function selfName()
  local ok,name=pcall(function() return player:getName() end)
  return ok and type(name)=='string' and name or nil
end
local function cleanWord(text)
  if type(text)~='string' then return nil end
  text=text:match('^%s*(.-)%s*$')
  if #text<1 or #text>64 or text:find('%c') then return nil end
  return text
end
local function isSpell(word)
  if type(getSpellData)~='function' then return false end
  local ok,data=pcall(getSpellData,word)
  return ok and type(data)=='table'
end
-- The named NPC's position, if it is on screen; with pos, only within reach of it.
local function npcPosition(name,pos)
  if type(name)~='string' or type(getCreatureByName)~='function' then return nil end
  local ok,npcPos=pcall(function()
    local creature=getCreatureByName(name)
    if creature and creature:isNpc() then return creature:getPosition() end
  end)
  if not ok or type(npcPos)~='table' then return nil end
  if pos and (npcPos.z~=pos.z or chebyshev(npcPos,pos)>TALK_REACH) then return nil end
  return npcPos
end
local function nearestNpcName(pos)
  if not pos or type(getSpectators)~='function' then return nil end
  local ok,list=pcall(getSpectators,false)
  local best,bestDistance
  for _,creature in pairs(ok and type(list)=='table' and list or {}) do
    local okNpc,name,npcPos=pcall(function()
      if creature:isNpc() then return creature:getName(),creature:getPosition() end
    end)
    if okNpc and type(name)=='string' and type(npcPos)=='table' and npcPos.z==pos.z then
      local distance=chebyshev(npcPos,pos)
      if distance<=TALK_REACH and (not best or distance<bestDistance) then best,bestDistance=name,distance end
    end
  end
  return best
end
-- Wrappers on g_game.talkChannel/talkPrivate live only while recording. They are
-- kept in g_game so a bot reload can always put the client's own functions back.
local function unhookTalk()
  local game=g_game
  if type(game)~='table' then return end
  local ok,hook=pcall(function() return game[TALK_HOOK] end)
  if not ok or type(hook)~='table' then return end
  for method,entry in pairs(hook) do
    if type(entry)=='table' then
      entry.dead=true
      if game[method]==entry.wrapper and type(entry.original)=='function' then game[method]=entry.original end
    end
  end
  game[TALK_HOOK]=nil
end
local function hookTalk()
  unhookTalk()
  local game=g_game
  if type(game)~='table' or type(talkWord)~='function' then return end
  local hook,listener={},talkWord
  for _,method in ipairs({'talkChannel','talkPrivate'}) do
    local original=game[method]
    if type(original)=='function' then
      local entry={original=original}
      entry.wrapper=function(...)
        if not entry.dead then pcall(listener,method,...) end
        return original(...)
      end
      hook[method]=entry
    end
  end
  pcall(function()
    game[TALK_HOOK]=hook
    for method,entry in pairs(hook) do game[method]=entry.wrapper end
  end)
end
pcall(unhookTalk) -- wrappers left by a bot reloaded while recording

local function floorLabel(newPos,oldPos)
  local used={}
  for _,row in ipairs(CaveBot.actionList and CaveBot.actionList:getChildren() or {}) do
    if row.action=='label' then used[tostring(row.value):lower()]=true end
  end
  local direction=newPos.z<oldPos.z and 'Subir' or 'Bajar'
  local index,name=1
  repeat
    name=string.format('Auto_%s_%03d_Piso_%d',direction,index,newPos.z)
    index=index+1
  until not used[name:lower()]
  CaveBot.addAction('label',name,true)
end

local function setup()
  local function console(text)
    if RinoConsole and type(RinoConsole.log)=='function' then
      pcall(RinoConsole.log,'action','CaveBot','Grabador: '..text)
    end
  end
  local function alert(text)
    if type(warn)=='function' then pcall(warn,'CaveBot[Grabador]: '..text) end
  end
  local function usefulWords(t)
    for _,word in ipairs(t.words) do
      local key=word:lower()
      if not GREETING[key] and not AGREE[key] and not CLOSING[key] then return true end
    end
    return false
  end
  -- The conversation's npcsay lines, before the next recorded action.
  local function finishTalk()
    local t=talk
    talk=nil
    if not t then return end
    if usefulWords(t) then
      -- A greeting sent by a hotkey is not seen; the NPC answered, so there was one.
      if not GREETING[t.words[1]:lower()] then CaveBot.addAction('npcsay','hi',true) end
      for _,word in ipairs(t.words) do CaveBot.addAction('npcsay',word,true) end
      console('conversacion con '..t.npc..' grabada ('..#t.words..' npcsay)')
    elseif #t.words==0 and t.replies>0 and not t.warned then
      alert('hablaste con '..t.npc..' pero no pude leer tus frases; si hacian falta, anade los npcsay a mano.')
    end
  end
  local function addPosition(pos)
    finishTalk()
    CaveBot.addAction("goto", pos.x .. "," .. pos.y .. "," .. pos.z, true)
    lastPos = copy(pos)
    anchor,track = copy(pos),{}
  end
  local function addStairs(pos)
    finishTalk()
    CaveBot.addAction("goto", pos.x .. "," .. pos.y .. "," .. pos.z .. ",0", true)
    lastPos = copy(pos)
    anchor,track = copy(pos),{}
  end
  -- A conversation starts with a waypoint where the player stands, so the
  -- route is next to the NPC when it talks.
  local function startTalk(npcName)
    finishTalk()
    local pos=playerPos()
    if not pos then return end
    if not same(lastPos,pos) then addPosition(pos) end
    talk={npc=npcName,pos=pos,here=pos,at=stamp(),words={},replies=0}
  end
  local function ownWord(text,typed)
    if CaveBot.isOn() or not isEnabled then return end
    -- Typed words are exact; the server's echo is used only where typing is not seen.
    if typed then heardTyped=true elseif heardTyped then return end
    local word=cleanWord(text)
    if not word or isSpell(word) then return end
    local key,time,pos=word:lower(),stamp(),playerPos()
    if talk and time-talk.at>TALK_IDLE then finishTalk() end
    if talk and talk.lastWord==key and time-talk.lastWordAt<1000 then return end
    if GREETING[key] then
      local npcName=talk and npcPosition(talk.npc,pos) and talk.npc or nearestNpcName(pos)
      if not npcName then return end
      if not talk or talk.npc~=npcName then startTalk(npcName) end
    elseif not talk then
      -- More words after something else was recorded, while the NPC still listens.
      if not lastNpc or time-lastNpc.at>TALK_IDLE or not npcPosition(lastNpc.name,pos) then return end
      startTalk(lastNpc.name)
    end
    if not talk then return end
    talk.words[#talk.words+1]=word
    talk.at,talk.here,talk.lastWord,talk.lastWordAt=time,pos or talk.here,key,time
  end
  local function npcReply(name,text)
    if CaveBot.isOn() or not isEnabled then return end
    local pos=playerPos()
    if not npcPosition(name,pos) then return end
    local time=stamp()
    lastNpc={name=name,at=time}
    -- The greeting went to the nearest NPC; the one answering is the real one.
    if talk and talk.npc~=name and talk.replies==0 and time-talk.at<=5000 then talk.npc=name end
    if talk and (talk.npc~=name or time-talk.at>TALK_IDLE) then finishTalk() end
    if not talk then startTalk(name) end
    if not talk then return end
    talk.replies=talk.replies+1
    talk.at,talk.here=time,pos
    local parse=ComboFollowTravel and ComboFollowTravel.parseDestination
    if type(parse)=='function' then
      local ok,city=pcall(parse,text)
      if ok and type(city)=='string' then talk.offer=city end
    end
  end
  -- The trip's destination: the last thing the player asked for, else the city
  -- the NPC offered.
  local function tripDestination(t)
    for i=#t.words,1,-1 do
      local word=t.words[i]
      local key=word:lower()
      if not GREETING[key] and not AGREE[key] and not CLOSING[key] then
        if word:find(',',1,true) then break end
        if t.offer and key==t.offer:lower() then return t.offer end
        return word
      end
    end
    return t.offer
  end
  -- A jump right after talking, from where the conversation was: the NPC moved us.
  local function npcJump(newPos,oldPos)
    local t=talk
    if not t or stamp()-t.at>TRIP_WINDOW then return false end
    local here=t.here or t.pos
    if not here or here.z~=oldPos.z or chebyshev(here,oldPos)>1 then return false end
    local moved=newPos.z~=oldPos.z and math.huge or chebyshev(oldPos,newPos)
    if moved>=15 or (moved>=5 and not npcPosition(t.npc)) then
      local destination=tripDestination(t)
      if not destination then
        alert('viaje con '..t.npc..' grabado como salto: no supe a que ciudad. Cambialo por una accion travel.')
        t.warned=true
        return false
      end
      talk=nil
      CaveBot.addAction('travel',t.npc..', '..destination,true)
      console('viaje grabado: '..t.npc..', '..destination)
      addPosition(newPos)
      return true
    end
    -- A short move done by the NPC (a door, a pass): its words, then the arrival.
    if not usefulWords(t) then return false end
    finishTalk()
    addPosition(newPos)
    return true
  end
  talkWord=function(method,mode,target,message)
    if type(message)~='string' then return end
    if tonumber(mode)==modeOf('NpcTo',11) then return ownWord(message,true) end
    if method=='talkChannel' and sayMode(mode) and (target==nil or tonumber(target)==0) then
      return ownWord(message,true)
    end
  end
  if type(onTalk)=='function' then
    onTalk(function(name,level,mode,text)
      if CaveBot.isOn() or not isEnabled or type(name)~='string' then return end
      local me=selfName()
      if me and name:lower()==me:lower() then
        if sayMode(mode) or tonumber(mode)==modeOf('NpcTo',11) then pcall(ownWord,text,false) end
        return
      end
      mode=tonumber(mode)
      if mode==modeOf('NpcFrom',10) or mode==modeOf('NpcFromStartBlock',51) then pcall(npcReply,name,text) end
    end)
  end
  -- The finished last stretch, so the recording ends where the character stopped.
  CaveBot.Recorder.flush = function()
    finishTalk()
    if smart() and #track>0 then addPosition(track[#track]) end
  end

  onPlayerPositionChange(function(newPos, oldPos)
    if CaveBot.isOn() or not isEnabled or not valid(newPos) or not valid(oldPos) then return end
    if talk and (newPos.z~=oldPos.z or chebyshev(oldPos,newPos)>1) and npcJump(newPos,oldPos) then
      if newPos.z~=oldPos.z then
        lastTransition=oldPos.x..','..oldPos.y..','..oldPos.z..'>'..newPos.x..','..newPos.y..','..newPos.z
      end
      lastInteraction=nil
      return
    end
    if newPos.z~=oldPos.z then
      finishTalk()
      local transition=oldPos.x..','..oldPos.y..','..oldPos.z..'>'..newPos.x..','..newPos.y..','..newPos.z
      if transition==lastTransition and same(lastPos,newPos) then return end
      -- A recorded ladder/tool use already performs this crossing. Do not
      -- append a return to the old floor after that use action.
      local interaction=lastInteraction and stamp()-lastInteraction.at<=2000 and
        lastInteraction.pos.z==oldPos.z and
        math.max(math.abs(lastInteraction.pos.x-oldPos.x),math.abs(lastInteraction.pos.y-oldPos.y))<=1
      if not interaction then addStairs(oldPos) end
      floorLabel(newPos,oldPos)
      addPosition(newPos)
      lastTransition=transition;lastInteraction=nil
    elseif not lastPos then
      -- first step
      addPosition(oldPos)
      if smart() then track={copy(newPos)} end
    elseif math.abs(oldPos.x - newPos.x) > 1 or math.abs(oldPos.y - newPos.y) > 1 then
      -- stairs/teleport
      addStairs(oldPos)
      addPosition(newPos)
    elseif smart() then
      local from=anchor or lastPos
      track[#track+1]=copy(newPos)
      if chebyshev(from,newPos)>SMART_MAX then
        addPosition(newPos)
      elseif #track>=2 and not faithful(from,newPos,track) then
        -- The tile before still had a matching path: it becomes the waypoint.
        addPosition(track[#track-1])
        track={copy(newPos)}
      end
    elseif math.max(math.abs(lastPos.x - newPos.x), math.abs(lastPos.y - newPos.y)) > 5 then
      -- 5 steps from last pos
      addPosition(newPos)
    end
    if newPos.z==oldPos.z then
      lastTransition=nil
      if not same(newPos,oldPos) then lastInteraction=nil end
    end
  end)
  
  onUse(function(pos, itemId, stackPos, subType)
    if CaveBot.isOn() or not isEnabled then return end
    if runeCast(itemId,pos) or (valid(pos) and (afterRune(pos) or (hasMonster(pos) and not transitionUse(pos)))) then return end
    if valid(pos) then
      finishTalk()
      lastPos = copy(pos)
      anchor,track = playerPos() or copy(pos),{}
      lastInteraction=transitionUse(pos) and {pos=copy(pos),at=stamp()} or nil
      CaveBot.addAction("use", pos.x .. "," .. pos.y .. "," .. pos.z, true)
    end
  end)
  
  onUseWith(function(pos, itemId, target, subType)
    if CaveBot.isOn() or not isEnabled then return end
    local targetPos = target and target.getPosition and target:getPosition()
    if runeCast(itemId,targetPos) then return end
    if not target or not target:isItem() then return end
    if not valid(targetPos) or afterRune(targetPos) then return end
    local crossing=transitionUse(targetPos,itemId,target.getId and target:getId())
    if hasMonster(targetPos) and not crossing then return end
    finishTalk()
    lastPos = copy(targetPos)
    anchor,track = playerPos() or copy(targetPos),{}
    lastInteraction=crossing and {pos=copy(targetPos),at=stamp()} or nil
    CaveBot.addAction("usewith", itemId .. "," .. targetPos.x .. "," .. targetPos.y .. "," .. targetPos.z, true)
  end)
end

CaveBot.Recorder.isOn = function()
  return isEnabled
end

CaveBot.Recorder.enable = function()
  CaveBot.setOff()
  if isEnabled == nil then
    setup()
  end
  -- CaveBot.Editor.ui.autoRecording:setOn(true)
  isEnabled = true
  lastPos = nil
  lastTransition = nil
  lastInteraction = nil
  lastRune = nil
  anchor,track = nil,{}
  talk,lastNpc,heardTyped = nil,nil,false
  pcall(hookTalk)
end

CaveBot.Recorder.disable = function()
  if isEnabled == true then
    if CaveBot.Recorder.flush then pcall(CaveBot.Recorder.flush) end
    isEnabled = false
  end
  pcall(unhookTalk)
  -- CaveBot.Editor.ui.autoRecording:setOn(false)
  CaveBot.save()
end
