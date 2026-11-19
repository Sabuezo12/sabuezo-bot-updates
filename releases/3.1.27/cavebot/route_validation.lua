CaveBot.RouteValidation = {}
local V=CaveBot.RouteValidation
local function trim(value)return tostring(value or ''):match('^%s*(.-)%s*$')end
local function row(entry)
  return tostring(entry.action or entry[1] or ''):lower(),tostring(entry.value or entry[2] or '')
end
function V.entries()
  return CaveBot.actionList and CaveBot.actionList:getChildren() or {}
end
function V.inspect(entries)
  local report={errors=0,warnings=0,transitions=0,issues={},count=0}
  local rows,labels={},{}
  local function issue(index,level,message,target)
    report.issues[#report.issues+1]={index=index,level=level,message=message,target=target}
    if level=='error'then report.errors=report.errors+1 elseif level=='warning'then report.warnings=report.warnings+1 end
  end
  for _,entry in ipairs(entries or {})do
    local action,value=row(entry)
    if action~='config' and action~='extensions'then
      rows[#rows+1]={action=action,value=value}
      local i=#rows
      if not CaveBot.Actions[action]then issue(i,'error','Accion desconocida: '..action)end
      if action=='label'then
        local name=trim(value):lower()
        if name==''then issue(i,'error','Label vacio.')
        elseif labels[name]then issue(i,'warning','Label repetido: '..value,labels[name])
        else labels[name]=i end
      end
    end
  end
  report.count=#rows
  local function target(index,name)
    if not labels[trim(name):lower()]then issue(index,'error','No existe el label "'..tostring(name)..'".')end
  end
  local previous
  for i,entry in ipairs(rows)do
    local a,value=entry.action,entry.value
    if a=='gotolabel'then target(i,value)end
    if a=='goto' or a=='zonapz' or a=='floorchange' or a=='usewith' or a=='use' and value:find(',',1,true)then
      local position=CaveBot.Waypoints.position(a,value)
      if not position then issue(i,'error','Coordenadas invalidas en '..a..'.')end
      if a=='floorchange' and CaveBot.Transitions and not CaveBot.Transitions.floor(value)then
        issue(i,'error','Escalera invalida: la entrada debe quedar a un paso del origen.')
      end
      if a=='goto' and position then
        if previous then
          local p=previous.position
          local limit=tonumber(storage.extras and storage.extras.gotoMaxDistance)or 24
          if p.z~=position.z or math.abs(p.x-position.x)+math.abs(p.y-position.y)>limit then
            report.transitions=report.transitions+1
            issue(previous.index,'warning','Cambio de piso o salto largo hasta WP '..i..': comprobar portal o escalera.',i)
          end
        end
        previous={position=position,index=i}
      elseif a~='label'then previous=nil end
    elseif a~='label'then previous=nil end
    if a=='function'then
      local compile=loadstring or load
      local compiled,chunk,errorText=pcall(compile,'local retries,prev=0,true\n'..value,'route_validation')
      if not compiled then errorText,chunk=chunk,nil end
      if not chunk then issue(i,'error','Error de Lua: '..tostring(errorText):sub(1,180))end
      local rules=CaveBot.FunctionRules
      local config=rules and rules.decode(value)
      if not config and value:match('^%-%- RinoRule v1:')then issue(i,'error','Configuracion de regla invalida.')end
      if config then
        local valid,message=rules.validate(config)
        if not valid then issue(i,'error',message)end
        for _,branch in ipairs({'yes','no'})do
          if type(config[branch])=='table' and config[branch].mode=='label'then target(i,config[branch].label)end
        end
      else
        for quote,name in value:gmatch('gotoLabel%s*%(%s*(["\'])(.-)%1%s*%)')do target(i,name)end
      end
    elseif a=='travel'then
      if not value:match('^%s*[^,]+%s*,%s*[^,]+')then issue(i,'error','Travel requiere nombre del NPC y ciudad.')end
    elseif a=='waitstamina' and CaveBot.WaitStamina then
      local config,message=CaveBot.WaitStamina.decode(value)
      if not config then issue(i,'error',message or 'Stamina invalida.')
      else
        for _,branch in ipairs({'below','ready'})do if config[branch]=='label'then target(i,config[branch..'Label'])end end
      end
    elseif a=='supplycheck'then
      target(i,value:match('^%s*([^,]+)')or '')
    end
  end
  -- Only report provable cycles: labels and unconditional jumps without work.
  local reported={}
  for start,entry in ipairs(rows)do
    if entry.action=='gotolabel'then
      local seen,index={},start
      while rows[index] and not seen[index] and not reported[index]do
        seen[index]=true
        local item=rows[index]
        if item.action=='label'then index=index+1
        elseif item.action=='gotolabel'then index=labels[trim(item.value):lower()]
        else break end
      end
      if index and seen[index]then
        issue(start,'error','Bucle de labels sin movimiento, espera ni condicion.',index)
        for i in pairs(seen)do reported[i]=true end
      end
    end
  end
  report.ok=report.errors==0
  return report
end
function V.refresh(entries,announce)
  local report=V.inspect(entries or V.entries())
  V.last=report
  if announce and (report.errors>0 or report.warnings>0)then
    warn('CaveBot: revision de ruta: '..report.errors..' errores, '..report.warnings..' avisos. Abre Revisar ruta en el editor.')
  end
  return report
end
function V.text(report)
  local lines={'Ruta: '..report.count..' waypoints | '..report.errors..' errores | '..report.warnings..' avisos'}
  if #report.issues==0 then lines[#lines+1]='No se encontraron errores en la estructura de la ruta.'end
  for _,entry in ipairs(report.issues)do
    lines[#lines+1]=('WP %d [%s] %s'):format(entry.index,entry.level=='error' and 'ERROR'or 'AVISO',entry.message)
  end
  return table.concat(lines,'\n')
end
