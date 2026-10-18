-- Presentation only: keep the native callbacks and native ON/OFF state.
HelperTheme = {}
local T=HelperTheme
T.types={Button="HelperThemeButton",TextEdit="HelperThemeInput",MultilineTextEdit="HelperThemeMultiline",
 Label="HelperThemeLabel",FlatPanel="HelperThemeCard",TextList="HelperThemeList",
 ScrollablePanel="HelperThemeScroll",ComboBox="HelperThemeCombo",CheckBox="HelperThemeCheck",
 BotSwitch="HelperThemePower",BotTextEdit="HelperThemeInput",SpinBox="HelperThemeSpin",
 HorizontalSeparator="HelperThemeDivider",VerticalSeparator="HelperThemeVerticalDivider"}
function T.inline(value)
 if type(value)~="string" then return value end
 -- Change declarations only. Leave IDs, values and embedded Lua untouched.
 local result=value:gsub("([^\n]+)",function(line)
   local space,kind=line:match("^(%s*)([%w_]+)%s*$")
   if kind and T.types[kind] then return space..T.types[kind] end
   return line
 end)
 if HelperAppearance and not HelperAppearance.legacy then result=HelperAppearance.transform(result) end
 return result
end
function T.bindToggle(w)
 if w.helperThemed or not w.helperCaption or not w.helperTrack then return end
 w.helperThemed=true
 local setText,getText,setOn,setColor=w.setText,w.getText,w.setOn,w.setColor
 local label=getText(w) or ""
 local function paint()
   local on=w:isOn()
   w.helperTrack:setOn(on)
   w.helperTrack.helperState:setText(on and "ON" or "OFF")
   if RinoSkin and RinoSkin.syncSwitch then RinoSkin.syncSwitch(w.helperTrack,on)
   else w.helperTrack.helperState:setMarginLeft(0) end
 end
 w.setText=function(self,value)
   label=tostring(value or "")
   self.helperCaption:setText(label)
   setText(self,"")
 end
 w.getText=function() return label end
 w.setOn=function(self,value)
   local result=setOn(self,value)
   paint()
   return result
 end
 w.setOff=function(self) return self:setOn(false) end
 w.setColor=function(self,color)
   self.helperCaption:setColor(color)
   return setColor(self,color)
 end
 -- Legacy color fills carry no state. The native flag above remains authoritative.
 w.setImageColor=function() end
 w:setText(label)
 paint()
end
-- Native tooltips resize to their text. Explicit newlines keep their width
-- bounded without changing the game's shared tooltip widget or adding timers.
T.tooltipColumns=50
function T.formatTooltip(value)
 if type(value)~='string' or value=='' then return value end
 value=value:gsub('\r\n','\n'):gsub('\r','\n')
 local function length(text) return #(text:gsub('[\128-\191]','')) end
 local result={}
 for paragraph in (value..'\n'):gmatch('(.-)\n') do
  if length(paragraph)<=T.tooltipColumns then result[#result+1]=paragraph
  else
   local line,size='',0
   for word in paragraph:gmatch('%S+') do
    local count=length(word)
    if size>0 and size+1+count>T.tooltipColumns then result[#result+1]=line;line,size='',0 end
    -- Extremely long paths/identifiers still fit; never split a UTF-8 glyph.
    if count>T.tooltipColumns then
     local i=1
     while i<=#word do
      local b=word:byte(i)
      local bytes=b>=240 and b<=244 and 4 or b>=224 and b<=239 and 3 or b>=194 and b<=223 and 2 or 1
      for at=i+1,i+bytes-1 do local nextByte=word:byte(at);if not nextByte or nextByte<128 or nextByte>191 then bytes=1;break end end
      if size==T.tooltipColumns then result[#result+1]=line;line,size='',0 end
      line=line..word:sub(i,i+bytes-1);size=size+1;i=i+bytes
     end
    else
     line=line..(size>0 and ' ' or '')..word;size=size+(size>0 and 1 or 0)+count
    end
   end
   result[#result+1]=line
  end
 end
 return table.concat(result,'\n')
end
function T.bindTooltip(w)
 if w.helperTooltipBinding or type(w.setTooltip)~='function' or type(w.getTooltip)~='function' then return end
 local setter,getter,hover=w.setTooltip,w.getTooltip,w.onHoverChange
 local binding={};w.helperTooltipBinding=binding
 local function set(self,value)
  if type(value)=='string' then
   if value~=binding.source and value~=binding.wrapped then binding.source=value;binding.wrapped=T.formatTooltip(value) end
   value=binding.wrapped
  end
  return setter(self,value)
 end
 w.setTooltip=set
 local initial=getter(w);if initial~=nil then set(w,initial) end
 w.onHoverChange=function(self,hovered,...)
  -- onStyleApply can restore an OTUI tooltip's original single line. Format
  -- before delegating to the native tooltip hover handler, including signals.
  if hovered then local value=getter(self);if value~=nil then set(self,value) end end
  if type(hover)=='function' then return hover(self,hovered,...) end
  if type(hover)=='table' then for _,fn in pairs(hover) do if fn(self,hovered,...) then return true end end end
  return false
 end
end
function T.tooltips(w)
 if (type(w)~='table' and type(w)~='userdata') or type(w.getChildren)~='function' then return end
 T.bindTooltip(w)
 for _,child in ipairs(w:getChildren()) do T.tooltips(child) end
end
function T.decorate(w,style,inline)
 if (type(w)~="table" and type(w)~="userdata") or type(w.getChildren)~="function" then return end
 if style and HelperAppearance then HelperAppearance.track(w,style,inline) end
 T.bindTooltip(w)
 -- These children are declared by our own style; no native style introspection.
 if w.helperCaption and w.helperTrack then T.bindToggle(w) end
 if RinoSkin and RinoSkin.decorate then RinoSkin.decorate(w,style) end
 for _,child in ipairs(w:getChildren()) do T.decorate(child) end
end

-- These APIs belong to this bot context. Cover classic mode, native popup
-- helpers and icons too, without replacing global client UI/tooltip functions.
local function tooltipResult(...)
 local widget=...
 T.tooltips(widget)
 return ...
end
local function withTooltips(original)
 return function(...) return tooltipResult(original(...)) end
end
if type(UI)=='table' then for name,fn in pairs(UI) do if type(fn)=='function' then UI[name]=withTooltips(fn) end end end
if type(setupUI)=='function' then setupUI=withTooltips(setupUI) end
if type(addIcon)=='function' then addIcon=withTooltips(addIcon) end
