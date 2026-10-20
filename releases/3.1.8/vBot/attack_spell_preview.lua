-- A compact illustration compiled from the SAME footprint used by M.rank.
-- Chains illustrate range/links, not a promise about server target selection.
AttackSpellPreview = {}
local P = AttackSpellPreview
function P.describe(entry, patterns, direction)
  local C, M = AttackSpellCatalog, AttackRotation
  local result={cells={},caster={x=0,y=0},directional=false,note='Selecciona un spell.',legend='Turquesa: tu | Oro: objetivo'}
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
    local targeted=entry.category==2 or model and model.anchor=='target'
    if targeted then result.target={x=0,y=0};result.caster={x=0,y=5} end
    result.kind='area'
    result.note=#result.cells..' casillas de impacto. '..(targeted and 'Centro en T; alcance '..range..' SQM.' or directional and 'Se gira segun la direccion elegida.' or 'Centro en tu personaje.')
    if model==C.models[4] then result.note=result.note..' Hueco de 1 SQM: NO golpea las casillas adyacentes.' end
    if data and data.delayed then result.note=result.note..' Impacto diferido: '..data.delayed/1000 ..'s.' end
    result.legend='Verde: impacto | Turquesa: tu | Oro: centro'
  end
  return result
end

function P.render(panel, entry, patterns, direction)
  local info=P.describe(entry,patterns,direction)
  panel.grid:destroyChildren()
  local minX,maxX,minY,maxY=-2,2,-2,2
  for _,point in ipairs(info.cells) do minX=math.min(minX,point.x);maxX=math.max(maxX,point.x);minY=math.min(minY,point.y);maxY=math.max(maxY,point.y) end
  minX=math.min(minX,info.caster.x);maxX=math.max(maxX,info.caster.x)
  minY=math.min(minY,info.caster.y);maxY=math.max(maxY,info.caster.y)
  local cell=math.max(3,math.floor(88/math.max(maxX-minX+1,maxY-minY+1)))
  local colors={hit='#36ad75',range='#314c62',support='#c6a94d',chain='#e9b950'}
  local filled={}
  for _,point in ipairs(info.cells) do filled[point.x..':'..point.y]=point.kind end
  for y=minY,maxY do for x=minX,maxX do
    local w=UI.createWidget('AttackPreviewCell',panel.grid)
    w:setMarginLeft((x-minX)*cell);w:setMarginTop((y-minY)*cell)
    w:setSize({width=cell-1,height=cell-1})
    local color=colors[filled[x..':'..y]] or '#1b262e'
    if info.caster.x==x and info.caster.y==y then color='#49dbe1' end
    if info.target and info.target.x==x and info.target.y==y then color='#f3cf80' end
    w:setBackgroundColor(color)
  end end
  panel.grid:setTooltip(info.note..'\nCada cuadrito equivale a 1 SQM. '..info.legend)
  panel.legend:setText(info.legend);panel.explanation:setText(info.note)
  panel.direction:setEnabled(info.directional)
  panel.direction:setText(info.directional and ('Girar: '..({'N','E','S','O'})[(direction or 0)+1]) or 'Sin direccion')
end
