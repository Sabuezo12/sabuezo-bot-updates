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
   w.helperTrack.helperState:setMarginLeft(0)
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
function T.decorate(w,style,inline)
 if (type(w)~="table" and type(w)~="userdata") or type(w.getChildren)~="function" then return end
 if style and HelperAppearance then HelperAppearance.track(w,style,inline) end
 -- These children are declared by our own style; no native style introspection.
 if w.helperCaption and w.helperTrack then T.bindToggle(w) end
 for _,child in ipairs(w:getChildren()) do T.decorate(child) end
end
