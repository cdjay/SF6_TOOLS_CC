local M={}
local function number(v) return type(v)=="number" and v==v and math.abs(v)<math.huge end
function M.new(capture,schema,rules)
 local rows={};local ix=schema.index
 for _,row in ipairs(capture.samples) do
  local round,frame=row[ix.round],row[ix.replay_frame]
  if round==row[ix.battle_round] then rows[round]=rows[round] or {};rows[round][frame]=row end
 end
 local function context(item,kind)
  local row=rows[item.round] and rows[item.round][item.frame]
  local before=rows[item.round] and rows[item.round][item.frame-1]
  if before and (not row or before[ix.stage_frame]+1~=row[ix.stage_frame] or before[ix.fight_st]~=row[ix.fight_st]) then before=nil end
  local c={kind=kind,frame=item.frame,round=item.round+1,side=item.receiver,damage=item.damage,
   duration=(item.last_frame or item.frame)-item.frame+1,base_rule=(item.base_classification or item.classification or {}).rule}
  local f=item.facts or {}
  for _,key in ipairs({"attack_start_observed","active_seen","contact_seen","reaction_preceded_by_guard","facing_changed"}) do if type(f[key])=="boolean" then c[key]=f[key] end end
  if f.attack_start_observed then c.active_seen=not not f.active_seen;c.contact_seen=not not f.contact_seen end
  if f.flags then c.counter=f.flags.counter;c.punish=f.flags.punish;c.guard_flag=f.flags.guard end
  if f.previous_state~=nil then c.previous_attack=rules.attack(f.previous_state);c.previous_guard=rules.guard(f.previous_state) end
  if number(f.source_observed) then c.source_opponent=f.source_observed==3-item.receiver end
  if f.guard_end then c.guard_elapsed=item.frame-f.guard_end end
  if f.wakeup_last_frame then c.wakeup_elapsed=item.frame-f.wakeup_last_frame end
  if item.native_advantage then c.native_advantage=item.native_advantage.value;c.native_abs=math.abs(item.native_advantage.value) end
  if kind=="guard" then
   c.guard_complete=item.complete==true
   if item.response then
    c.response_delay=item.response.delay
    if item.response.frame then c.response_observed=true elseif item.response.reason=="limit" then c.response_observed=false end
   end
   if item.window then c.window_frames=item.window.frames;c.window_complete=item.window.lower_bound==false end
  end
  for _,side in ipairs({"self","other"}) do
   local s=side=="self" and item.receiver or 3-item.receiver
   local p=(capture.metadata.players or {})[s] or {}
   c[side..".fighter_id"]=p.playing_fighter_id or p.fighter_id;c[side..".control_mode"]=p.control_mode
   for _,time in ipairs({"current","previous"}) do
    local r
    if time=="current" then r=row else r=before end
    if r then
     local prefix=side.."."..time.."."
     for name,index in pairs(ix) do local field=name:match("^p"..s.."%.(.+)$");if field and number(r[index]) then c[prefix..field]=r[index] end end
     for name,fields in pairs({health_pct={"vital_new","vital_max"},drive_pct={"focus_new","focus_max"},super_pct={"mSuperGauge","mSuperGaugeMax"}}) do
      local v,max=c[prefix..fields[1]],c[prefix..fields[2]]
      if number(v) and number(max) and max>0 and v>=0 and v<=max then c[prefix..name]=v/max*100 end
     end
     local direction=rules.direction(c[prefix.."pl_input_new"],c[prefix.."facing_right"])
     if direction then for k,v in pairs(direction) do c[prefix..k]=v end end
    end
   end
  end
  for _,time in ipairs({"current","previous"}) do
   local r
   if time=="current" then r=row else r=before end
   if r then for name,index in pairs(ix) do if not name:find(".",1,true) and number(r[index]) then c["clock."..time.."."..name]=r[index] end end end
  end
  local a,b=c["self.current.x_raw"],c["other.current.x_raw"]
  if number(a) and number(b) then c.distance=math.abs(a-b)/65536 end
  return c
 end
 return context,rows
end
function M.apply(engine,context,items,kind)
 for _,item in ipairs(items) do
  local r=engine:match(kind,context(item,kind))
  if r then
   item.custom_rule={id=r.id,title=r.title,priority=r.priority,profile=engine.document.name}
   if kind=="damage" then
    item.base_classification=item.classification
    item.classification={rule="custom_"..r.id,title=r.title,level="inferred"}
   else
    item.custom_title=r.title
    if r.opportunity~=nil then item.candidate=r.opportunity end
   end
  end
 end
end
return M
