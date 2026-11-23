-- Keep party information queries quiet; move our other command echoes to NPCs.
-- The server transport stays unchanged: no command is sent to an NPC.
HelperPartyEcho={}
function HelperPartyEcho.new(options)
 local self={pending={}}
 local function time()return options.time()or 0 end
 local function identity()
  local me=options.player()
  if not me then return end
  local ok,n,id=pcall(function()return me:getName(),me:getId()end)
  if ok then return n,id end
 end
 local function prune(t)
  for i=#self.pending,1,-1 do
   local p=self.pending[i]
   if t<p.at or t-p.at>8000 then table.remove(self.pending,i)end
  end
 end
 function self.receive(name,level,mode,text)
  if self.disposed or not self.bridge then return false end
  local b=self.bridge
  local t=time();prune(t)
  local own,id=identity()
  if text=='!party'and b.speechModes[mode]and type(name)=='string'then
   local mine=type(own)=='string'and name:lower()==own:lower()
   local member=false
   if not mine and type(options.member)=='function'then
    local ok,value=pcall(options.member,name);member=ok and value==true
   end
   if mine or member then
    -- Queries are silent even on followers that never send a command. Skip
    -- the native handler before it creates both Default text and map speech.
    if mine then
     for i=#self.pending,1,-1 do
      local p=self.pending[i]
      if p.text==text and p.ownerId==id and p.name==own then table.remove(self.pending,i)end
     end
    end
    return true
   end
  end
  if mode~=b.sayMode then return false end
  if name~=own then return false end
  for i,p in ipairs(self.pending)do
   if p.name==name and p.ownerId==id and p.text==text then
    table.remove(self.pending,i)
    -- Use the console's normal formatting and rendering, without changing
    -- selection, NPC recipient, message history, or other onTalk listeners.
    local module=b.module
    local formatted=module.applyMessagePrefixies(name,level,text)
    local tab=module.getTab('NPCs')
    if not tab then tab=module.addTab('NPCs',false);if tab then tab.npcChat=true end end
    if not tab then return false end
    local result=module.addTabText(formatted,b.style,tab,name)
    if result==false then return false end
    return true
   end
  end
  return false
 end
 function self.detach()
  self.pending={}
  local b=self.bridge
  if b then
   pcall(b.disconnect,b.game,{onTalk=b.wrapper})
   if modules.game_console==b.module and b.module.onTalk==b.wrapper then
    b.module.onTalk=b.original;pcall(b.connect,b.game,{onTalk=b.original})
   end
   self.bridge=nil
  end
  if self.root and self.root._rinoPartyEcho==self then self.root._rinoPartyEcho=nil end
 end
 function self.dispose()
  if self.disposed then return end
  self.disposed=true;self.detach()
  if self.owner and self.owner.unbind==self.unbindWrapper then self.owner.unbind=self.previousUnbind end
 end
 function self.install()
  if self.disposed then return false end
  if self.bridge then
   if modules.game_console==self.bridge.module and self.bridge.module.onTalk==self.bridge.wrapper then return true end
   self.detach()
  end
  if not Helper or type(Helper.valid)~='function'or not Helper.valid()then return false end
  local root=g_ui.getRootWidget()
  local previous=root._rinoPartyEcho
  if previous and previous~=self and previous.dispose then previous.dispose()end
  local module=modules and modules.game_console
  local original=module and module.onTalk
  if type(original)~='function'then return false end
  local env=module
  if type(getfenv)=='function'then local ok,value=pcall(getfenv,original);if ok then env=value end end
  local game=env and env.g_game or module.g_game or g_game
  local on,off=env and env.connect or module.connect,env and env.disconnect or module.disconnect
  local modes=env and env.MessageModes or module.MessageModes
  local styles=env and env.SpeakTypesSettings or module.SpeakTypesSettings
  local style=styles and(styles.privatePlayerToNpc or styles.say)
  if not game or type(on)~='function'or type(off)~='function'or not modes or not modes.Say or not style then return false end
  for _,method in ipairs({'getTab','addTab','addTabText','applyMessagePrefixies'})do
   if type(module[method])~='function'then return false end
  end
  local owner=Helper
  local wrapper=function(...)
   if self.disposed or not owner.valid()then self.dispose();return original(...)end
   local ok,handled=pcall(self.receive,...)
   if ok and handled then return end
   return original(...)
  end
  local ok=pcall(function()
   off(game,{onTalk=original});module.onTalk=wrapper;on(game,{onTalk=wrapper})
  end)
  if not ok then module.onTalk=original;pcall(on,game,{onTalk=original});return false end
  local speechModes={}
  for _,name in ipairs({'Say','Whisper','Yell','NpcTo'})do if modes[name]then speechModes[modes[name]]=true end end
  self.bridge={module=module,game=game,original=original,wrapper=wrapper,connect=on,disconnect=off,sayMode=modes.Say,style=style,speechModes=speechModes}
  self.root=root;root._rinoPartyEcho=self
  if not self.unbindWrapper then
   local previousUnbind=owner.unbind
   self.owner,self.previousUnbind=owner,previousUnbind
   self.unbindWrapper=function(...)
    self.dispose()
    if previousUnbind then return previousUnbind(...)end
   end
   owner.unbind=self.unbindWrapper
  end
  return true
 end
 function self.prepare(text)
  if type(text)~='string'or not(text=='!party'or text=='!partyexit'or text:match('^!partykick [^%c!%%]+$'))then return end
  if not self.install()then return end
  local n,id=identity();if not n or not id then return end
  local t=time();prune(t)
  if #self.pending>=16 then table.remove(self.pending,1)end
  local token={name=n,ownerId=id,text=text,at=t}
  self.pending[#self.pending+1]=token
  return token
 end
 function self.cancel(token)
  for i=#self.pending,1,-1 do if self.pending[i]==token then table.remove(self.pending,i);return end end
 end
 return self
end
return HelperPartyEcho
