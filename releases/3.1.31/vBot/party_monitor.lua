-- Queries the server's informational !party modal. Only our own complete,
-- validated responses can be acknowledged without opening a window.
HelperPartyMonitor={}
local M=HelperPartyMonitor
local LATE_REPLY=10000 -- ms after the 5 s wait in which a reply is still our own query
function M.new(options)
  local self={nextPoll=0}
  local function time()return options.time()or 0 end
  local function identity()
    local me=options.player()
    if not me then return end
    local ok,n,id=pcall(function()return me:getName(),me:getId()end)
    if ok then return n,id end
  end
  local function parse(title,message)return HelperPartyReport.parse(title,message)end
  local function okButton(buttons,choices)
    if type(buttons)~='table'or #buttons~=1 or type(choices)~='table'then return end
    for _ in pairs(choices)do return end
    local b=buttons[1]
    if type(b)~='table'then return end
    local id,label=tonumber(b[1]or b.id),b[2]or b.text
    if id and id>=0 and id<=255 and tostring(label or''):lower()=='ok'then return id end
  end
  function self.receive(id,title,message,buttons,enter,escape,choices,priority)
    if self.disposed then return false end
    local report=parse(title,message)
    if not report then
      if self.pending and tostring(title):lower()=='party shared info'then
        self.pending=nil;self.disabled=true;self.retryAt=nil;self.status='No pude interpretar !party; pulsa Info para revisarlo.'
      end
      return false
    end
    local t=time();local name,ownerId=identity()
    local accepted=options.controller.observeSharedReport(report,options.player(),t)
    local pending=self.pending
    self.pending=nil
    if accepted then self.supported=true;self.disabled=false;self.failures=0;self.retryAt=nil;self.status=nil end
    if not accepted and pending then
      self.failures=(self.failures or 0)+1;self.nextPoll=t+15000
      if self.failures>=3 then self.disabled=true;self.retryAt=t+60000 end
    end
    -- Our own silent query is closed even when its answer arrives late (high ping) or
    -- cannot be used (for example the leadership just changed); a manual Info stays open.
    local own=pending
    if not own and self.late and t<=self.late.untilAt+LATE_REPLY then own=self.late end
    if not own or t<own.at or t>own.untilAt+(own==self.late and LATE_REPLY or 0) or
       ownerId~=own.ownerId or name~=own.name or self.manualUntil and t<self.manualUntil then return false end
    if own==self.late then self.late=nil end
    local button=okButton(buttons,choices)
    local game=self.bridge and self.bridge.game
    if not button or not game or type(game.answerModalDialog)~='function'then
      self.disabled=true;self.retryAt=nil;self.status='!party recibido; cierre automatico no disponible. Usa Info.';return false
    end
    local ok,value=pcall(game.answerModalDialog,id,button,255)
    if not ok or value==false then self.disabled=true;self.retryAt=nil;return false end
    return true
  end
  function self.detach()
    self.pending=nil
    local b=self.bridge
    if b then
      pcall(b.disconnect,b.game,{onModalDialog=b.wrapper})
      if modules.game_modaldialog==b.module and b.module.onModalDialog==b.wrapper then
        b.module.onModalDialog=b.original;pcall(b.connect,b.game,{onModalDialog=b.original})
      end
      self.bridge=nil
    end
    if self.root and self.root._rinoPartyMonitor==self then self.root._rinoPartyMonitor=nil end
    if self.owner and self.owner.unbind==self.unbindWrapper then self.owner.unbind=self.previousUnbind end
  end
  function self.dispose()
    if self.disposed then return end
    self.disposed=true;self.detach()
  end
  function self.install()
    if self.bridge then
      if modules.game_modaldialog==self.bridge.module and self.bridge.module.onModalDialog==self.bridge.wrapper then return true end
      self.detach()
    end
    if not Helper or type(Helper.valid)~='function'or not Helper.valid()then return false end
    local root=g_ui.getRootWidget()
    local previous=root._rinoPartyMonitor
    if previous and previous~=self and previous.dispose then previous.dispose()end
    local module=modules and modules.game_modaldialog
    local original=module and module.onModalDialog
    if type(original)~='function'then return false end
    local env=module
    if type(getfenv)=='function'then local ok,value=pcall(getfenv,original);if ok then env=value end end
    local game=env and env.g_game or module.g_game or g_game
    local on,off=env and env.connect or module.connect,env and env.disconnect or module.disconnect
    if not game or type(on)~='function'or type(off)~='function'then return false end
    local owner=Helper
    local wrapper
    wrapper=function(...)
      if self.disposed or not owner.valid()then self.dispose();return original(...)end
      local ok,handled=pcall(self.receive,...)
      if ok and handled then return end
      return original(...)
    end
    local ok=pcall(function()
      off(game,{onModalDialog=original});module.onModalDialog=wrapper
      on(game,{onModalDialog=wrapper})
    end)
    if not ok then module.onModalDialog=original;pcall(on,game,{onModalDialog=original});return false end
    self.bridge={module=module,game=game,original=original,wrapper=wrapper,connect=on,disconnect=off}
    self.root=root;root._rinoPartyMonitor=self
    local previousUnbind=owner.unbind
    self.owner,self.previousUnbind=owner,previousUnbind
    self.unbindWrapper=function(...)
      self.dispose()
      if previousUnbind then return previousUnbind(...)end
    end
    owner.unbind=self.unbindWrapper
    return true
  end
  function self.requestInfo()
    local t=time()
    self.pending=nil;self.late=nil;self.manualUntil=t+5000;self.nextPoll=t+6000;self.disabled=false;self.retryAt=nil;self.failures=0
    return options.send('!party')
  end
  function self.poll()
    if self.disposed then return end
    local cfg=options.config
    -- No queries during the leader's own refill trip: kicks wait for the return anyway.
    local away=type(options.away)=='function'and options.away()==true
    if not cfg.enabled or not cfg.kickNoShare or not cfg.serverCommands or not HelperPartyContext.isLeader()or away then
      if self.pending then self.late=self.pending end
      self.pending=nil;self.status=nil;return
    end
    local t=time()
    if self.bridge and(modules.game_modaldialog~=self.bridge.module or self.bridge.module.onModalDialog~=self.bridge.wrapper)then
      self.detach();self.nextPoll=t+1000
    end
    if self.pending then
      if t<=self.pending.untilAt then return end
      self.late=self.pending;self.pending=nil
      self.failures=(self.failures or 0)+1
      if not self.supported or self.failures>=3 then
        self.disabled=true;self.retryAt=self.supported and t+60000 or nil
        self.status='Sin respuesta de !party. Pulsa Info para comprobarlo.'
      end
    end
    if self.disabled and self.retryAt and t>=self.retryAt then self.disabled=false;self.failures=0;self.retryAt=nil end
    if self.disabled or t<self.nextPoll or self.manualUntil and t<self.manualUntil then return end
    if not self.install()then self.status='Para revisar miembros lejanos, abre Info !party.';self.nextPoll=t+5000;return end
    local dialog=self.bridge.module.modalDialog
    if dialog then
      local ok,title=pcall(function()return dialog:getText()end)
      if not ok or tostring(title):lower()~='party shared info'then return end
    end
    if options.canSend and not options.canSend(t)then return end
    local name,ownerId=identity()
    if not name or not ownerId then return end
    self.nextPoll=t+5000
    self.pending={at=t,untilAt=t+5000,name=name,ownerId=ownerId}
    if not options.send('!party')then self.pending=nil;self.status='No se pudo solicitar !party.'end
  end
  self.install()
  if not self.bridge and type(onModalDialog)=='function'then
    onModalDialog(function(...)if not self.disposed and not self.bridge then self.receive(...)end end)
  end
  return self
end
return M
