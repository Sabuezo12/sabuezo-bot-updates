-- A compact illustration compiled from the SAME footprint used by M.rank.
-- Chains illustrate range/links, not a promise about server target selection.
AttackSpellPreview = {}
dofile('/vBot/attack_spell_scene.lua')
local P = AttackSpellPreview
function P.describe(entry, patterns, direction)
  local C, M = AttackSpellCatalog, AttackRotation
  local result={cells={},rangeCells={},caster={x=0,y=0},directional=false,note='Selecciona un spell.',legend='P: tu personaje | T: objetivo / centro'}
  if not entry then return result end
  local spec, data=M.find(entry),C.find(entry.spell)
  local model=entry.category==6 and C.models[entry.pattern]
  local range=entry.spellRange or data and data.range or entry.pattern or 7
  if spec.support then
    result.kind='support'
    if data and data.supportTargets then
      range=entry.spellRange or data.range
      local targets=entry.chainTargets or data.supportTargets
      for x=-range,range do for y=-range,range do result.cells[#result.cells+1]={x=x,y=y,kind='range'} end end
      result.target={x=0,y=-math.min(3,range)}
      result.note='SOPORTE, sin dano. Hasta '..targets..' objetivos; salto '..(entry.chainJump or data.supportJump)..' SQM. Cadena estimada: el servidor elige monstruos a distancia.'
      result.legend='Azul: alcance | Turquesa: tu | Oro: ejemplo'
    elseif C.isDivineEmpowerment(entry) then
      for x=-1,1 do for y=-1,1 do result.cells[#result.cells+1]={x=x,y=y,kind='support'} end end
      result.note='SOPORTE: campo 3x3 de 5s para aumentar tu dano. No golpea monstruos.'
      result.legend='Amarillo: soporte | Turquesa: tu personaje'
    else
      result.note='SOPORTE. Condicion: monstruos a '..range..' SQM. No cuenta como dano en la rotacion.'
    end
  elseif model and model.chain then
    result.kind='chain'
    for x=-range,range do for y=-range,range do result.cells[#result.cells+1]={x=x,y=y,kind='range'} end end
    result.target={x=0,y=-math.min(3,range)}
    -- A small sample branch distinguishes a chain from a filled damage area.
    -- Distances/target totals stay in the text: actual monsters decide links.
    local example={{0,-3},{2,-3},{-2,-2},{3,-1},{-3,0},{2,1},{-1,2},{0,3}}
    for i=1,math.min(entry.chainTargets or model.maxTargets,#example) do
      local point=example[i]
      result.cells[#result.cells+1]={x=point[1],y=point[2],kind='chain'}
    end
    result.note=(model.fork and 'Desde el objetivo' or 'Cadena al mas cercano')..': hasta '..(entry.chainTargets or model.maxTargets)..' objetivos. Alcance '..range..'; salto '..(entry.chainJump or model.jump)..' SQM. Conteo estimado; ajusta Wheel.'
    result.legend='Azul: alcance inicial | Oro: cadena de ejemplo'
  elseif entry.category==1 or entry.category==3 then
    result.kind='target'; range=entry.pattern or range
    for x=-range,range do for y=-range,range do result.cells[#result.cells+1]={x=x,y=y,kind='range'} end end
    result.target={x=0,y=-math.min(3,range)}
    result.note='1 objetivo. Alcance '..range..' SQM. Las casillas azules son alcance, no dano de area.'
    result.legend='Azul: alcance | Turquesa: tu | Oro: objetivo'
  else
    local cells,directional=M.shape(entry,patterns,direction or 0)
    result.directional=directional==true
    for _,cell in ipairs(cells or {}) do result.cells[#result.cells+1]={x=cell.x,y=cell.y,kind='hit'} end
    -- Divine Grenade is planted on the caster's own tile, whatever the model's anchor says.
    local targeted=not C.isDivineGrenade(entry) and (entry.category==2 or model and model.anchor=='target')
    if targeted then
      result.target={x=0,y=0};result.caster={x=0,y=math.min(3,range)}
      for x=-range,range do for y=-range,range do
        result.rangeCells[#result.rangeCells+1]={x=x+result.caster.x,y=y+result.caster.y,kind='range'}
      end end
    end
    result.kind='area'
    result.note=#result.cells..' casillas de impacto. '..(targeted and 'Centro en T; alcance '..range..' SQM.' or directional and 'Se gira segun la direccion elegida.' or 'Centro en tu personaje.')
    if model==C.models[4] then result.note=result.note..' Hueco de 1 SQM: NO golpea las casillas adyacentes.' end
    if data and data.delayed then result.note=result.note..' Impacto diferido: '..data.delayed/1000 ..'s.' end
    result.legend='Verde: impacto | Turquesa: tu | Oro: centro'
  end
  result.range=range
  result.canShowReach=#result.rangeCells>0
  for _,point in ipairs(result.cells)do if point.kind=='range'then result.canShowReach=true end end
  return result
end

function P.render(panel, entry, patterns, direction)
  local info=P.describe(entry,patterns,direction)
  panel._info=info
  local showReach=panel._showReach
  if showReach==nil then showReach=info.kind~='area' end
  local minX,maxX,minY,maxY=-2,2,-2,2
  local filled={}
  local function include(point)
    if point.kind=='range'and not showReach then return end
    filled[point.x..':'..point.y]=point.kind
    minX=math.min(minX,point.x);maxX=math.max(maxX,point.x)
    minY=math.min(minY,point.y);maxY=math.max(maxY,point.y)
  end
  for _,point in ipairs(info.rangeCells)do include(point)end
  for _,point in ipairs(info.cells)do include(point)end
  minX=math.min(minX,info.caster.x);maxX=math.max(maxX,info.caster.x)
  minY=math.min(minY,info.caster.y);maxY=math.max(maxY,info.caster.y)
  if info.target then
    minX=math.min(minX,info.target.x);maxX=math.max(maxX,info.target.x)
    minY=math.min(minY,info.target.y);maxY=math.max(maxY,info.target.y)
  end
  minX,maxX,minY,maxY=minX-1,maxX+1,minY-1,maxY+1
  local cols,rows=maxX-minX+1,maxY-minY+1
  local cell=math.max(3,math.floor(math.min((panel.grid:getWidth()-4)/cols,(panel.grid:getHeight()-4)/rows)))
  local offsetX=math.floor((panel.grid:getWidth()-cols*cell)/2)
  local offsetY=math.floor((panel.grid:getHeight()-rows*cell)/2)
  local colors={hit='#318b66',range='#284a64',support='#a69046',chain='#dba04b'}
  local roles={hit='Impacto',range='Solo alcance; no es dano',support='Soporte; sin dano',chain='Enlace de ejemplo; el servidor decide'}
  local function hint(x,y,kind)
    local dx,dy=x-info.caster.x,y-info.caster.y
    return 'X '..dx..', Y '..dy..' | '..math.max(math.abs(dx),math.abs(dy))..' SQM | '..(roles[kind]or'Fuera del impacto')
  end
  local idle=info.directional and'Clic en la cuadricula para orientar la vista.'or'Pasa el raton para consultar cada casilla.'
  panel.hover:setText(idle)
  panel._cells=panel._cells or{}
  local index,hits=0,0
  for _,point in ipairs(info.cells)do if point.kind=='hit'then hits=hits+1 end end
  for y=minY,maxY do for x=minX,maxX do
    index=index+1
    local w=panel._cells[index]
    if not w then w=UI.createWidget('AttackPreviewCell',panel.grid);panel._cells[index]=w end
    w:show()
    w:setMarginLeft(offsetX+(x-minX)*cell);w:setMarginTop(offsetY+(y-minY)*cell)
    w:setSize({width=cell-1,height=cell-1})
    local kind=filled[x..':'..y]
    local color=colors[kind]or'#14232c'
    local marker=''
    if info.caster.x==x and info.caster.y==y then color='#49dbe1';marker='P'end
    if info.target and info.target.x==x and info.target.y==y then color='#f3cf80';marker='T'end
    w:setBackgroundColor(color)
    w:setColor('#10232b');w:setText(cell>=9 and marker or'')
    w:setBorderWidth(0)
    local detail=hint(x,y,kind)
    if marker~=''then detail=(marker=='P'and'Tu personaje | 'or'Objetivo / centro | ')..detail end
    w:setTooltip(detail)
    w.onHoverChange=function(widget,hovered)
      widget:setBorderWidth(hovered and 1 or 0);widget:setBorderColor('#ecf7fb')
      panel.hover:setText(hovered and detail or idle)
    end
    local dx,dy=x-info.caster.x,y-info.caster.y
    w.onClick=function()
      if not info.directional or dx==0 and dy==0 or not panel.onDirection then return true end
      local face
      if math.abs(dx)>math.abs(dy)then face=dx>0 and 1 or 3 else face=dy>0 and 2 or 0 end
      panel.onDirection(face);return true
    end
  end end
  for i=index+1,#panel._cells do panel._cells[i]:hide()end
  panel.grid:setTooltip('Cada casilla = 1 SQM. P: tu personaje. T: objetivo o centro.\n'..info.legend)
  local legend='Verde: impacto | Azul: alcance | P: tu | T: centro'
  if info.kind=='chain'then legend='Azul: alcance | Oro: cadena de ejemplo | P: tu'
  elseif info.kind=='support'then
    legend=info.canShowReach and'Azul: alcance | T: ejemplo | Soporte sin dano'or'Oro: soporte | P: tu | Sin dano'
  end
  panel.legend:setText(legend)
  local summary=info.kind=='area'and(hits..' casillas de impacto')or info.kind=='target'and('1 objetivo | '..(info.range or 0)..' SQM de alcance')or
    info.kind=='chain'and'Cadena de ejemplo; impacto estimado'or info.kind=='support'and'Soporte: sin dano directo'or'Selecciona un spell'
  panel.summary:setText(summary)
  panel.explanation:setText(info.note)
  panel.direction:setVisible(info.directional)
  panel.direction:setText('Girar: '..({'N','E','S','O'})[(direction or 0)+1])
  panel.reach:setVisible(info.canShowReach==true)
  panel.reach:setText(showReach and'Ocultar alcance'or'Ver alcance')
  panel.reach.onClick=function()
    panel._showReach=not showReach
    if panel.onReach then panel.onReach(panel._showReach)else P.render(panel,entry,patterns,direction)end
  end
  local available=AttackSpellScene.available(entry)
  local animated=not panel._diagram and available and AttackSpellScene.render(panel,entry,info,direction)
  if not animated then AttackSpellScene.stop(panel)end
  panel.scene:setVisible(animated==true)
  panel.grid:setVisible(not animated)
  panel.mode:setVisible(available==true)
  panel.mode:setText(panel._diagram and'Animacion'or'Esquema')
  panel.mode.onClick=function()
    panel._diagram=not panel._diagram
    if panel.onMode then panel.onMode(panel._diagram)else P.render(panel,entry,patterns,direction)end
  end
  panel.play:setVisible(animated==true)
  panel.play.onClick=function()
    local state=panel._spellScene;if state and state.replay then state.replay()end
  end
  if animated then
    panel.legend:setText('Escena del cliente | 1 casilla = 1 SQM')
    panel.hover:setText('Tu personaje y un objetivo de ejemplo.')
    panel.reach:hide()
  elseif entry and not available then
    panel.hover:setText('Este cliente no aporta animacion; se muestra el esquema.')
  end
end
