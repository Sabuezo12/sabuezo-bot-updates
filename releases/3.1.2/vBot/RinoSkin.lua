-- RinoBot RPG: one presentation layer for the shell and native forms.
-- No timers, game commands, widget style introspection or engine wrappers.
local A=HelperAppearance
RinoSkin={}
local S=RinoSkin
if not A or A.legacy then return end
S.prefix=A.prefix..'vBot/rpg_assets/'
S.brandSource=A.prefix..'vBot/botserver_assets/helper-sabuezo-cyan-suave-46.png'
S.clips={brand={0,0,46,46},home={350,60,239,239},combat={658,55,254,254},heal={977,66,232,232},shield={28,346,263,263},cave={357,359,238,238},navi={642,329,284,284},inventory={970,350,250,250},tools={37,648,260,260},scripts={357,651,249,249},settings={660,655,246,246},time={954,633,280,280},deaths={25,950,258,258},xp={345,942,257,257},route={664,949,238,238},target={972,940,264,264}}
S.sections={Inicio='home',Combate='combat',Curacion='heal',Proteccion='shield',CaveBot='cave',
 Navi='navi',Inventario='inventory',Herramientas='tools',Scripts='scripts',Ajustes='settings'}
S.modules={attackbot='combat',targetbot='target',healbot='heal',friend_healer='heal',conditions='heal',
 inmortal='shield',equipper='shield',equip='shield',cavebot='cave',supplies='inventory',
 botserver='navi',containermanager='inventory',itemcounter='inventory',imbuementscrolls='shield',
 pvp_support='target',antipush1='shield',keepwall='shield',timerexecutor='time',alarms='time',
 exivatarget='target',exivalast='navi',holdtarget='target',ingame_editor='scripts',updater='settings'}
local function clone(v)
 if type(v)~='table' then return v end
 local r={};for k,x in pairs(v)do r[k]=clone(x)end;return r
end
local function iconName(id,section) return S.modules[id] or S.sections[section] or 'tools' end
S.iconName=iconName
function S.icon(w,name)
 if not w or not S.clips[name] then return end
 local c=S.clips[name]
 w.rinoAssetKey=name
 w:mergeStyle({['image-source']=name=='brand' and S.brandSource or S.prefix..'icons.png',['image-clip']=table.concat(c,' '),
  -- OTClient's fixed-ratio branch samples the WHOLE texture, ignoring clip.
  -- The padded square clip preserves the symbol's proportions without it.
  -- Never set image-border here, even to zero: it enables native tiling.
  ['image-fixed-ratio']=false,['image-repeated']=false,
  ['image-auto-resize']=false,['image-smooth']=true,
  ['image-color']='#ffffffff',['background-color']='#00000000',phantom=w.rinoInteractive~=true})
end
function S.arrow(w)
 w:mergeStyle({text='', ['image-source']=S.prefix..'chrome-chevron.png',['image-clip']='0 0 16 16',
  ['image-size']='10 10',['image-fixed-ratio']=true,['image-color']=A.current.text})
end
function S.chromeGlyph(w,name,force)
 if not w then return end
 local signature=name..A.current.text
 if not force and w.rinoChromeSignature==signature then return end
 w.rinoChromeSignature=signature;w.rinoChromeGlyphKey=name
 w:mergeStyle({['image-source']=S.prefix..'chrome-'..name..'.png',['image-clip']='0 0 16 16',
  ['image-fixed-ratio']=true,['image-color']=A.current.text})
end
local surfaces={['#172126']=true,['#25333d']=true,['#1b2932']=true,['#263640']=true,
 ['#212e37']=true,['#0f1920']=true,['#18434a']=true,['#244b53']=true,['#1d5359']=true}
S.staticTypes={Button='HelperRpgButton',FlatPanel='HelperRpgFlat',TextList='HelperRpgList',
 Label='HelperRpgLabel',ComboBox='HelperRpgCombo',MultilineTextEdit='HelperRpgMultiline',
 TextEdit='HelperThemeInput',BotTextEdit='HelperRpgBotInput',SpinBox='HelperThemeSpin',CheckBox='HelperThemeCheck'}
function S.transformLine(line,path)
 if path and (path:find('/HelperTheme.otui',1,true) or path:find('/Helper.otui',1,true)) then return line end
 local space,name,base=line:match('^(%s*)([%w_]+)%s*<%s*([%w_]+)%s*$')
 if name and not name:match('^HelperTheme') and S.staticTypes[base] then
  return space..name..' < '..S.staticTypes[base]
 end
 local indent,kind=line:match('^(%s+)([%w_]+)%s*$')
 if kind and S.staticTypes[kind] then return indent..S.staticTypes[kind] end
 return line
end
local defaults={Button='#263640',FlatPanel='#25333d',TextList='#0f1920',TextEdit='#0f1920',
 MultilineTextEdit='#0f1920',ComboBox='#0f1920',SpinBox='#0f1920',
 UITextEdit='#0f1920',UIMultilineTextEdit='#0f1920',UIComboBox='#0f1920',UISpinBox='#0f1920'}
local function inheritedSurface(d)
 local seen={}
 while d and not seen[d] do
  seen[d]=true
  if defaults[d.style] then return defaults[d.style]end
  if defaults[d.type] then return defaults[d.type] end
  d=A.metadata.styles[d.type]
 end
end
local function buttonType(d)
 local seen={}
 while d and not seen[d] do
  seen[d]=true
  if d.type=='Button' or d.type=='UIButton' or d.type=='BotSwitch' then return true end
  d=A.metadata.styles[d.type]
 end
 return false
end
function S.paint(w,entry)
 if not S.prefix or not entry or entry.fixed or w.helperAppearanceFixed then return end
 if w.rinoAssetKey then S.icon(w,w.rinoAssetKey)end
 if w.rinoChromeGlyphKey then S.chromeGlyph(w,w.rinoChromeGlyphKey,true)end
 if w.rinoArrow then
  S.arrow(w.rinoArrow)
  if w.helperComboArrow then w.helperComboArrow:hide()end
 end
 local d=entry.descriptor;local source=(entry.manual and entry.manual['background-color']) or(d.props and d.props['background-color']) or inheritedSurface(d)
 -- Native spinbox arrows are Button children with their symbol in the
 -- background sprite. Other bare UIButton glyphs have no inferred surface.
 if d.style=='Button' and (d.id=='up' or d.id=='down') then return end
 if type(source)~='string' or not surfaces[source:lower()] then return end
 local style=d.style or '';local kind=d.type or ''
 if d.id=='levelBadge' then return end
 if style=='HelperFlatButton' then return end
 if kind=='UIProgressBar' or style=='HelperHomeMeter' or style=='HelperHomePortrait' or
    style=='HelperThemeScroll' or style=='HelperThemeDivider' or style=='HelperThemeVerticalDivider' then return end
 local pill=style=='HelperThemeSwitch' or style=='HelperSwitch'
 local button=buttonType(d)
 local asset=pill and 'pill.png' or button and 'button.png' or 'surface.png'
 local props={['image-source']=S.prefix..asset,['image-clip']='0 0 32 32',['image-border']=pill and 8 or 6,
  ['image-color']=A.color(source),['background-color']='#00000000',['border-width']=0}
 local neutralInput=not(entry.manual and entry.manual.color) and d.props and
  type(d.props.color)=='string' and d.props.color:sub(1,7):lower()=='#272727'
 if neutralInput then
  props.color=A.current.text;props['selection-color']=A.current.text;props['selection-background-color']=A.current.active
 end
 for state,values in pairs(d.states or{})do
  local color=values['background-color']
  if type(color)=='string' and surfaces[color:lower()] then
   props[state]={['image-source']=S.prefix..asset,['image-clip']='0 0 32 32',['image-border']=pill and 8 or 6,
    ['image-color']=A.color(color),['background-color']='#00000000',['border-width']=0}
  end
 end
 -- Native button styles use multi-row sprite clips. Always reset the clip
 -- for every inherited state when replacing that sprite with a 32px mask.
 local states={['$hover']=true,['$hover !disabled']=true,['$pressed']=true,['$on']=true,
  ['$off']=true,['$!on']=true,['$checked']=true,['$focus']=true,['$disabled']=true}
 for state in pairs(d.states or{})do states[state]=true end
 for state in pairs(states)do
  local color=button and ((state=='$on' or state=='$checked' or state=='$pressed') and '#18434a' or state:find('hover',1,true) and '#304650') or source
  if not props[state] then props[state]={['image-source']=S.prefix..asset,['image-clip']='0 0 32 32',
   ['image-border']=pill and 8 or 6,['image-color']=A.color(color),['background-color']='#00000000',['border-width']=0}end
 end
 if neutralInput then
  for state,values in pairs(d.states or{})do
   local color=values.color
   if type(color)=='string'and color:sub(1,7):lower()=='#272727'then
    props[state]=props[state]or{};props[state].color=A.current.text..color:sub(8)
   end
  end
 end
 w:mergeStyle(props)
 if w.rinoChrome then
  if w.rinoNativeText then w.rinoNativeText(w,'')end
  w.rinoChrome:mergeStyle({['image-color']=A.current.text})
 end
 if w.rinoKnob then w.rinoState=nil;S.syncSwitch(w,w:isOn())end
end
function S.syncSwitch(w,on)
 if not w or not w.rinoKnob then return end
 on=on==true
 local signature=tostring(on)..':'..w:getWidth()..':'..A.current.accent..':'..A.current.text
 if w.rinoState==signature then return end
 w.rinoState=signature
 w.rinoKnob:setMarginLeft(on and math.max(2,w:getWidth()-14) or 2)
 w.rinoKnob:mergeStyle({['image-color']=on and A.current.accent or A.current.text})
 local label=w.helperState or w.caption
 if label then label:setMarginLeft(on and 0 or 14);label:setMarginRight(on and 14 or 0)end
end
function S.decorate(w,style)
 if not S.prefix then return end
 if w.rinoArrow then
  S.arrow(w.rinoArrow)
  w.rinoArrow:setMarginRight(4-w:getPaddingRight())
  if w.helperComboArrow then w.helperComboArrow:hide()end
 end
 if w.rinoSelected and not w.rinoNavigation then
  w.rinoNavigation=true
  local setOn=w.setOn
  w.setOn=function(self,on)local r=setOn(self,on);self.rinoSelected:setVisible(on==true);return r end
  w.rinoSelected:setVisible(w:isOn())
 end
 if w.rinoKnob and not w.rinoSwitch then
  w.rinoSwitch=true
  local native=w.setOn
  w.setOn=function(self,on)
   local result=native(self,on);S.syncSwitch(self,on);return result
  end
  S.syncSwitch(w,w:isOn())
 end
end
function S.chrome(button,name,tooltip)
 if not S.prefix or not button then return end
 local glyph=(Helper and Helper.originals.createWidget or UI.createWidget)('HelperThemeIcon',button)
 glyph:mergeStyle({['anchors.horizontalCenter']='parent.horizontalCenter',['anchors.verticalCenter']='parent.verticalCenter',size='14 14'})
 button.rinoChrome=glyph
 local setText,getText=button.setText,button.getText
 button.rinoNativeText=setText
 local logical=getText(button)
 local function paint()
  local actual=name=='expand' and (logical=='[-]' and 'collapse' or 'expand') or name
  glyph:mergeStyle({['image-source']=S.prefix..'chrome-'..actual..'.png',['image-clip']='0 0 16 16',['image-color']=A.current.text})
 end
 button.setText=function(self,value)logical=tostring(value or '');setText(self,'');paint()end
 button.getText=function()return logical end
 button:setText(logical);button:setTooltip(tooltip)
end
function S.floating(widget,entry,enabled,bar)
 if not S.prefix or not widget or not entry then return end
 -- Standalone icons show only their item/text; explicit bars keep their style.
 -- No position, size, saved preference or gesture is changed by this layer.
 local color=entry.config and entry.config[enabled and 'onColor' or 'offColor'] or (enabled and A.current.accent or A.current.text)
 local opacity=bar and storage.iconEditor and storage.iconEditor.layout and tonumber(storage.iconEditor.layout.barOpacity) or 90
 opacity=math.max(0,math.min(100,opacity or 70))
 local source=bar and S.prefix..'button.png' or ''
 local tint=bar and A.current.panel..string.format('%02x',math.floor(opacity*255/100+0.5)) or '#ffffffff'
 local signature=(bar and 'bar:' or 'icon:')..source..tint..tostring(color)
 if entry.rinoSkinSignature==signature then return end
 entry.rinoSkinSignature=signature
 local function frame()
  local p={['image-source']=source,['image-color']=tint,['background-color']='#00000000',['border-width']=0}
  if bar then p['image-clip']='0 0 32 32';p['image-border']=6 end
  return p
 end
 local props=frame()
 -- Clear inherited button textures in every state; switching back to a bar
 -- restores its mask in those states too, without recreating the native icon.
 for _,state in ipairs({'$hover','$hover !disabled','$pressed','$on','$off','$!on','$checked','$focus','$disabled','$dragging'})do
  props[state]=frame()
 end
 widget:mergeStyle(props)
 if widget.text then widget.text:setColor(color)end
end
function S.installStyles()
 if S.stylesInstalled or not S.prefix then return end
 dofile('/vBot/rpg_styles.lua') -- Publishes S.styles; native dofile returns nil.
 for name,descriptor in pairs(S.styles or{})do A.metadata.styles[name]=descriptor end
 S.stylesInstalled=true
end
S.installStyles()
dofile('/vBot/RinoSession.lua')
-- This is an explicitly requested new theme. Preserve the previous palette
-- in the catalog, select RPG once, then honor later palette/opacity choices.
local theme={window='#10191F',panel='#1B2A33',button='#20343E',input='#101B23',text='#E8EEF2',
 accent='#46D9DB',border='#43636E',active='#17474D',opacity=100}
if A.settings.rpgVersion~=1 then
 local settings=clone(A.settings)
 if not settings.saved['Antes de RinoBot RPG'] then settings.saved['Antes de RinoBot RPG']=clone(A.applied)end
 settings.saved['RinoBot RPG']=clone(theme);settings.selected='RinoBot RPG';settings.remember=true;settings.rpgVersion=1
 local ok=true
 if A.profileManager and A.profileManager.valid() and A.profileManager.saveAppearance then
  ok=A.profileManager.saveAppearance(settings)
 end
 if ok then
  A.settings=settings;storage.helperUI.appearance=clone(settings)
  A.current=clone(theme);A.applied=clone(theme);A.appliedName='RinoBot RPG'
 end
end
