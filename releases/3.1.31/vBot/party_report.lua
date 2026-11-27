-- Parse only complete server reports. Chat text is never a report source.
HelperPartyReport={}
local R=HelperPartyReport
local function trim(v)return tostring(v or''):match('^%s*(.-)%s*$')end
function R.parse(title,text)
  if trim(title):lower()~='party shared info'or type(text)~='string'or #text>16384 then return end
  local low=text:lower()
  local count=tonumber(low:match('players in party:%s*(%d+)'))
  local shared=trim(low:match('shared experience:%s*([^\r\n]+)'))
  if not count or count<1 or count>100 or(shared~='blocked'and shared~='enabled'and shared~='disabled')then return end
  local result={members={},byName={},requested=shared~='disabled',shared=shared,count=count}
  local slots={}
  for line in text:gmatch('[^\r\n]+')do
    if line:match('^%s*%d+%.')then
      local index,name,level,rest=line:match('^%s*(%d+)%.%s*(.-)%s+%-%s+[Ll][Ee][Vv][Ee][Ll]%s+(%d+)%s*%([^)]*%)%s+%-%s*(.-)%s*$')
      index=tonumber(index);name=trim(name)
      if not index or index<1 or index>count or slots[index]or name==''or #name>80 or name:find('[%c!%%]')then return end
      local key=name:lower();if result.byName[key]then return end
      local state=trim(rest):lower()
      local leader=state:match('^leader%s*%-')~=nil
      if leader then
        if result.leader then return end
        result.leader=name;state=trim(state:match('^leader%s*%-%s*(.*)$'))
      end
      local reason=state:match('^not sharing:%s*(.+)$')
      local notSharing
      if reason then notSharing=true
      elseif state=='ready'or state=='sharing'then notSharing=false end
      local member={name=name,level=tonumber(level),leader=leader,notSharing=notSharing,reason=reason,state=state}
      result.members[#result.members+1]=member;result.byName[key]=member;slots[index]=true
    end
  end
  if #result.members~=count or not result.leader then return end
  return result
end
return R
