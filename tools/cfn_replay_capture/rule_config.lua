-- Pure, bounded user rules over copied evidence. No expressions or executable code.
local Schema=require("func/CFNReplayCapture/schema")
local M={schema="sf6cc.replay-rules.v1",build=20004000,path="cfn-replay-rules.json"}
local labels={vital_new="血量",vital_old="上次血量",vital_max="血量上限",heal_new="可恢复血量原值",focus_new="斗气原值",focus_max="斗气上限",
 mSuperGauge="能量原值",mSuperGaugeMax="能量上限",mSingleDamage="游戏单次伤害",mComboDamage="游戏连段伤害",mComboCount="游戏连击计数",
 action_id="动作编号",action_frame_raw="动作进度原值",x_raw="横向位置原值",y_raw="高度原值",z_raw="纵向位置原值",facing_right="朝向原值",
 act_st="行动状态编号",hit_st="受击标记原值",hit_st_old="上次受击标记",hit_stop="停顿剩余",damage_type="伤害类型原值",damage_source="伤害来源玩家",
 combo_cnt="另一连击计数",pl_input_new="方向与按键原值",pl_sw_new="新按键原值",display_current_frame="显示当前帧",display_prev_action_frame="显示动作帧",
 display_atk_margin="显示动作余量",display_hit_id="显示命中编号",guard_time="防御剩余",damage_time="受击剩余",pose_st="姿态编号",free_to_move="行动许可原值",
 engine_action_id="引擎动作编号",engine_action_frame_raw="引擎动作进度原值",engine_frame_num_raw="引擎动作长度原值",engine_margin_start_raw="引擎余量起点原值",
 engine_speed_raw="引擎速度原值",engine_state_flags="引擎状态标记",engine_battle_version="战斗版本",engine_loop_count="动作循环次数",engine_style_index="动作形态编号",
 display_meter_size="计测表大小",display_meter_index="计测表位置",display_meter_type="计测格类型",display_meter_empty="计测格为空",
 display_meter_changed="计测格变化",display_meter_end="计测格结束",display_meter_not_add="计测格未新增",display_meter_not_whole="计测格不完整",
 round="局数原值",replay_frame="录像帧",battle_round="战斗局数原值",stage_frame="战斗帧",render_tick="渲染计数",thread_id="采样线程编号",update_result="更新结果原值",
 fight_st="比赛阶段编号",play_timer="倒计时秒",play_timer_ms="倒计时子帧",display_prev_frame="显示同步帧",display_stun_frame="硬直差原始读数",
 display_attack_side="显示攻击方原值",meter_frame="计测表帧",meter_start_frame="计测表起点",meter_stop_frame="计测表停止帧",meter_active="计测表活动状态"}
M.settings={
 {key="wakeup_frames",label="起身后抢招范围（帧）",value=8,min=1,max=30},
 {key="guard_frames",label="防御后抢招范围（帧）",value=15,min=1,max=30},
 {key="response_frames",label="防御后行动观察范围（帧，不含终点）",value=30,min=1,max=120},
 {key="advantage_min",label="防御机会：硬直差绝对值下限",value=4,min=1,max=120}}
M.fields={};local index={}
local function field(key,label,kind,group,options)
 local f={key=key,label=label,type=kind,group=group,options=options};M.fields[#M.fields+1]=f;index[key]=f
end
local base_rules={
 {"guard_damage","防住了，但仍然掉血"},{"parry_caught","蓝防后受伤（类型待确认）"},{"attack_caught","出招后受伤（类型待确认）"},{"caught","受伤类型待确认"},
 {"wakeup_hit","起身时被压中"},{"wakeup_button_counter","起身后抢招被打断"},{"whiff_punish_candidate","出招落空后被惩罚"},{"attack_punished","出招过程中被确反康"},
 {"air_attack_counter","空中出招被打断"},{"air_ground_counter","空中出招时被地面对手打中"},{"guard_button_counter","防御后抢招被打断"},{"attack_counter","出招被对手抢先打断"},
 {"guard_reaction_followup","防御后陷入受击状态，被继续追击"},{"reaction_followup","受击过程中继续掉血"},{"side_change_air_hit","换边时没有挡住空中进攻"},
 {"guard_not_held","防御后没有继续维持后方向"},{"crouch_guard_air_hit","蹲防没有挡住后续空中进攻"},{"guard_broken","防御转入受击"},{"dash_intercepted","冲刺途中被截停"},
 {"forward_walk_hit","前走时被打中"},{"movement_hit","移动时被打中"},{"air_hit","空中被打中"},{"unresolved","掉血来源或原因未确定"}}
M.builtins=base_rules
field("base_rule","系统原分类","enum","事件",base_rules)
field("kind","记录类型","enum","事件",{{"damage","受伤段"},{"guard","防御段"}})
for _,f in ipairs({{"frame","发生帧"},{"round","第几局（从1开始）"},{"side","分析对象（1P或2P）"},{"damage","本段实际掉血"},{"duration","本段长度（帧）"},
 {"guard_elapsed","距离防御结束（帧）"},{"wakeup_elapsed","距离最近起身（帧）"},{"response_delay","防御结束到出招间隔（帧）"},
 {"native_advantage","已关联硬直差（正负归属未确认）"},{"native_abs","已关联硬直差绝对值"},{"window_frames","计测表收招窗口（帧）"},
 {"distance","双方横向间距（游戏单位）"}}) do field(f[1],f[2],"number","事件") end
for _,f in ipairs({{"counter","新出现普通康"},{"punish","新出现确反康"},{"guard_flag","新出现防御标记"},{"facing_changed","本帧换边"},
 {"previous_attack","掉血前正在出招"},{"previous_guard","掉血前正在防御"},{"attack_start_observed","看到了本次出招起点"},{"active_seen","看到了攻击判定"},
 {"contact_seen","观察到本次出招接触对手"},{"reaction_preceded_by_guard","受击状态之前是防御"},{"guard_complete","防御段起止完整"},
 {"response_observed","观察到防御后出招"},{"window_complete","收招窗口完整结束"},{"source_opponent","伤害来源确认为对手"}}) do field(f[1],f[2],"boolean","事件") end
for _,side in ipairs({"self","other"}) do
 local title=side=="self" and "分析对象" or "对手"
 for _,time in ipairs({"current","previous"}) do
  local group=title..(time=="current" and "·发生帧" or "·前一帧")
  for _,name in ipairs(Schema.player_columns) do field(side.."."..time.."."..name,labels[name] or name,"number",group) end
  for _,name in ipairs({"health_pct","drive_pct","super_pct"}) do field(side.."."..time.."."..name,({health_pct="血量百分比",drive_pct="斗气百分比",super_pct="能量百分比"})[name],"number",group) end
  for _,name in ipairs({"back","forward","down"}) do field(side.."."..time.."."..name,({back="输入后方向",forward="输入前方向",down="输入下方向"})[name],"boolean",group) end
 end
 field(side..".fighter_id",title.."角色编号（当前版本）","number","玩家")
 field(side..".control_mode",title.."操作模式","enum","玩家",{{0,"经典"},{1,"现代"}})
end
for _,time in ipairs({"current","previous"}) do for _,name in ipairs(Schema.clock_columns) do
 field("clock."..time.."."..name,labels[name] or name,"number",time=="current" and "全局·发生帧" or "全局·前一帧")
end end
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
local function keys(t,allowed) for k in pairs(t) do assert(allowed[k],"不支持的设置项："..tostring(k)) end end
local function array(t,max)
 assert(type(t)=="table" and #t<=max,"列表格式或数量不正确")
 local count=0;for k in pairs(t) do assert(type(k)=="number" and k%1==0 and k>=1 and k<=#t,"列表格式不正确");count=count+1 end
 assert(count==#t,"列表有缺项")
end
function M.defaults() return {schema=M.schema,build=M.build,name="我的录像规则",include_system=true,settings={wakeup_frames=8,guard_frames=15,response_frames=30,advantage_min=4},rules={}} end
function M.validate(doc)
 local ok,err=pcall(function()
  assert(type(doc)=="table","规则必须是配置对象")
  keys(doc,{schema=true,build=true,name=true,include_system=true,settings=true,rules=true})
  assert(doc.include_system==nil or type(doc.include_system)=="boolean","包含系统规则必须是开关")
  assert(doc.schema==M.schema and doc.build==M.build,"规则格式或游戏版本不匹配")
  assert(type(doc.name)=="string" and #doc.name>0 and #doc.name<=180 and not doc.name:find("%c"),"规则名称不正确")
  local allowed={};for _,s in ipairs(M.settings) do allowed[s.key]=true end
  assert(type(doc.settings)=="table","缺少时间范围设置");keys(doc.settings,allowed)
  for _,s in ipairs(M.settings) do local v=doc.settings[s.key];assert(finite(v) and v%1==0 and v>=s.min and v<=s.max,"范围不正确："..s.label) end
  array(doc.rules,100);local ids={};local total=0
  local function condition(c,depth)
   total=total+1;assert(total<=2000 and depth<=6,"条件过多或嵌套过深")
   assert(type(c)=="table","条件格式不正确")
   if c.all or c.any or c["not"] then
    keys(c,{all=true,any=true,["not"]=true});local count=(c.all and 1 or 0)+(c.any and 1 or 0)+(c["not"] and 1 or 0);assert(count==1,"条件组合只能选一种")
    if c["not"] then condition(c["not"],depth+1) else local list=c.all or c.any;array(list,32);assert(#list>0,"条件组不能为空");for _,child in ipairs(list) do condition(child,depth+1) end end
   else
    keys(c,{field=true,op=true,value=true,value_field=true});local f=index[c.field];assert(f,"未知条件字段")
    local op=c.op
    assert(op=="exists" or op=="missing" or op=="eq" or op=="ne" or (f.type=="number" and (op=="gt" or op=="ge" or op=="lt" or op=="le" or op=="between" or op=="bits_any" or op=="bits_all")),"条件比较方式不正确")
    if c.value_field~=nil then
     assert(f.type=="number" and index[c.value_field] and index[c.value_field].type=="number" and c.value==nil
      and (op=="eq" or op=="ne" or op=="gt" or op=="ge" or op=="lt" or op=="le"),"字段比较需要两个数值字段")
     return
    end
    if op=="exists" or op=="missing" then assert(c.value==nil,"存在性条件不带比较值");return end
    if op=="between" then array(c.value,2);assert(#c.value==2 and finite(c.value[1]) and finite(c.value[2]) and c.value[1]<=c.value[2],"范围上下限不正确")
    elseif f.type=="number" then assert(finite(c.value) and math.abs(c.value)<=9007199254740991,"数值无效")
    elseif f.type=="boolean" then assert(type(c.value)=="boolean","请选择是或否")
    else local found=false;for _,v in ipairs(f.options) do if v[1]==c.value then found=true end end;assert(found,"选项不存在") end
    if op=="bits_any" or op=="bits_all" then assert(c.value%1==0 and c.value>0 and c.value<=2147483647,"标记值必须是正整数") end
   end
  end
  for _,r in ipairs(doc.rules) do
   keys(r,{id=true,title=true,enabled=true,scope=true,priority=true,when=true,opportunity=true})
   assert(type(r.id)=="string" and r.id:match("^[A-Za-z][A-Za-z0-9_-]*$") and #r.id<=64 and not ids[r.id],"规则编号重复或不正确");ids[r.id]=true
   assert(type(r.title)=="string" and #r.title>0 and #r.title<=180 and not r.title:find("%c"),"问题描述长度不正确")
   assert(type(r.enabled)=="boolean" and (r.scope=="damage" or r.scope=="guard"),"规则类型不正确")
   assert(r.priority=="P1" or r.priority=="P2" or r.priority=="P3","自定义规则不能设为人工确认P0")
   assert(r.opportunity==nil or r.scope=="guard" and type(r.opportunity)=="boolean","机会设置只用于防御规则")
   condition(r.when,1)
  end
 end)
 return ok,ok and nil or tostring(err):gsub("^.-:%d+: ","")
end
-- Unknown is a third truth value: NOT unknown must not become a match.
function M.matches(c,ctx)
 if c["not"] then local v=M.matches(c["not"],ctx);if v==nil then return nil end;return not v end
 if c.all or c.any then
  local unknown=false
  for _,child in ipairs(c.all or c.any) do
   local v=M.matches(child,ctx)
   if c.all and v==false then return false elseif c.any and v==true then return true end
   if v==nil then unknown=true end
  end
  if unknown then return nil end;return c.all~=nil
 end
 local v=ctx[c.field];local f=index[c.field]
 local known=f and ((f.type=="number" and finite(v)) or (f.type=="boolean" and type(v)=="boolean") or f.type=="enum" and v~=nil)
 if c.op=="exists" then return not not known elseif c.op=="missing" then return not known end
 if not known then return nil end
 local op,n=c.op,c.value
 if c.value_field then n=ctx[c.value_field];if not finite(n) then return nil end end
 if op=="eq" then return v==n elseif op=="ne" then return v~=n elseif op=="gt" then return v>n elseif op=="ge" then return v>=n
 elseif op=="lt" then return v<n elseif op=="le" then return v<=n elseif op=="between" then return v>=n[1] and v<=n[2]
 elseif op=="bits_any" or op=="bits_all" then if v%1~=0 or math.abs(v)>9007199254740991 then return nil end;local bits=v & n;return op=="bits_any" and bits~=0 or op=="bits_all" and bits==n end
end
function M.equal(a,b)
 if type(a)~=type(b) then return false end
 if type(a)~="table" then return a==b end
 for k,v in pairs(a) do if not M.equal(v,b[k]) then return false end end
 for k in pairs(b) do if a[k]==nil then return false end end
 return true
end
function M.compile(doc)
 local ok,err=M.validate(doc);if not ok then return nil,err end
 -- Freeze the JSON-shaped input so edits cannot change an analysis in progress.
 local function copy(v) if type(v)~="table" then return v end;local out={};for k,x in pairs(v) do out[k]=copy(x) end;return out end
 local frozen=copy(doc)
 return {document=frozen,includes=function(_,item)
  return frozen.include_system~=false or item.custom_rule~=nil
 end,match=function(_,scope,ctx)
  for _,r in ipairs(frozen.rules) do if r.enabled and r.scope==scope and M.matches(r.when,ctx)==true then return r end end
 end}
end
return M
