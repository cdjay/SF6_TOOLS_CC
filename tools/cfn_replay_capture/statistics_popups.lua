-- Display-only reuse: never import training lifecycle, history or input hooks.
local UIKit=require("func/UIKit")
local Charts=require("func/CFNReplayCapture/statistics_charts")
local Stats=require("func/CFNReplayCapture/statistics")
local Presentation=require("func/CFNReplayCapture/presentation")
local M={}
local titles={"1P统计","2P统计","双方对比"}
local views={"总览","行为","伤害","资源"}
Charts.players={UIKit.COLORS.Blue,UIKit.COLORS.Orange}
function M.sides(id) return id==3 and {1,2} or {id} end
function M.layout(sw,sh,id)
    local width=math.min(680,math.floor((sw-36)/2))
    if width<480 then width=math.min(600,sw-24) end
    local height=math.min(650,sh-48)
    local x=id==1 and 12 or id==2 and sw-width-12 or (sw-width)/2
    return {x=x,y=24,w=width,h=height}
end
local function num(v,d) return type(v)=="number" and string.format("%."..(d or 0).."f",v) or "未知" end
local function percent(n,d) return d and d>0 and string.format("%.1f%%",(n or 0)/d*100) or "未知" end
local function choose(ui,id,value,names,width)
    ui.push_item_width(width or 150)
    local changed,next_value=ui.combo(id,value,names)
    ui.pop_item_width()
    return changed and next_value or value
end
local function tooltip(ui,message) if ui.is_item_hovered() then ui.set_tooltip(message) end end
local function clipped_text(ui,value,width)
    local full=value
    while #value>0 and ui.calc_text_size(value).x>width do value=value:sub(1,(utf8.offset(value,-1) or 1)-1) end
    ui.text(value)
    if value~=full then tooltip(ui,full) end
end
local function table_rows(ui,id,sides,rows,vec)
    if not ui.begin_table(id,#sides+1,(1<<6)|(1<<9),vec(0,0)) then return end
    local ok,err=pcall(function()
        ui.table_setup_column("项目",1<<3,1.35)
        for _,side in ipairs(sides) do ui.table_setup_column(side.."P",1<<3,1) end
        ui.table_next_row(1);ui.table_set_column_index(0);ui.table_header("项目")
        for j,side in ipairs(sides) do
            ui.table_set_column_index(j);ui.push_style_color(0,Charts.players[side]);ui.table_header(side.."P");ui.pop_style_color(1)
        end
        for _,row in ipairs(rows) do
            ui.table_next_row();ui.table_set_column_index(0);ui.text(row.label);if row.tip then tooltip(ui,row.tip) end
            for j,side in ipairs(sides) do ui.table_set_column_index(j);ui.text(row.values[side]);if row.tip then tooltip(ui,row.tip) end end
        end
    end)
    ui.end_table();if not ok then error(err) end
end
local function metric(rows,label,players,fn,tip)
    rows[#rows+1]={label=label,values={fn(players[1]),fn(players[2])},tip=tip}
end
local function overview(ui,w,scope,report,sides,width,vec)
    local rows,p={},scope.players
    w.overview=choose(ui,"##overview_mode",w.overview,{"战况总览","玩家与记录"})
    if w.overview==2 then
        local players=report.metadata.players or {}
        for _,field in ipairs({{"玩家编号","short_id"},{"MR","master_rating"},{"LP","league_point"}}) do
            local values={}
            for side=1,2 do local value=(players[side] or {})[field[2]];values[side]=value~=nil and value~=false and tostring(value) or "未知" end
            rows[#rows+1]={label=field[1],values=values}
        end
        metric(rows,"方向记录覆盖",p,function(q) return percent(q.direction_frames,scope.frames) end)
        metric(rows,"方向变化次数",p,function(q) return q.direction_frames>0 and num(q.direction_changes) or "未知" end)
        metric(rows,"方向多样性",p,function(q) return percent(q.direction_entropy,1) end,"香农熵除以 log2(9)。0表示单一方向，100%表示九方向均匀出现，不评价水平。")
        metric(rows,"普通康新记录",p,function(q) return q.signal_frames>0 and num(q.signals.counter or 0) or "未知" end,"按新出现标记计数；持续标记不重复，不能当作完整接触次数。")
        metric(rows,"确反康新记录",p,function(q) return q.signal_frames>0 and num(q.signals.punish or 0) or "未知" end)
        metric(rows,"防御新记录",p,function(q) return q.signal_frames>0 and num(q.signals.guard or 0) or "未知" end)
        table_rows(ui,"##identity",sides,rows,vec)
        ui.text("重复记录已排除 "..report.duplicates.."；已记录 "..#report.rounds.."局")
        return
    end
    metric(rows,"造成伤害",p,function(q) return num(q.damage_dealt) end)
    metric(rows,"受到伤害",p,function(q) return num(q.damage_received) end)
    metric(rows,"伤害净差",p,function(q) return string.format("%+d",q.damage_dealt-q.damage_received) end,"造成伤害减去受到伤害，不等于胜负或能力。")
    metric(rows,"受伤段数",p,function(q) return num(q.segments) end,"连续追击合并成一段，不把每次掉血都算成一次失误。")
    metric(rows,"每段平均 / 中位",p,function(q) return num(q.loss_distribution.mean).." / "..num(q.loss_distribution.median) end)
    metric(rows,"最大受伤段",p,function(q) return num(q.loss_distribution.max) end)
    metric(rows,"P0 / P1",p,function(q) return (q.priorities.P0 or 0).." / "..(q.priorities.P1 or 0) end)
    metric(rows,"P2 / P3",p,function(q) return (q.priorities.P2 or 0).." / "..(q.priorities.P3 or 0) end)
    metric(rows,"方向记录覆盖",p,function(q) return percent(q.direction_frames,scope.frames) end)
    table_rows(ui,"##overview",sides,rows,vec)
    ui.text("各局受伤量")
    local bars={}
    for _,r in ipairs(report.rounds) do if scope.round==nil or r.round==scope.round then
        bars[#bars+1]={label="第"..(r.round+1).."局",values={r.players[1].damage_received,r.players[2].damage_received}}
    end end
    Charts.paired_bars(ui,"##round_losses",bars,sides,width,vec)
end
local function behavior(ui,w,scope,sides,width,vec)
    w.behavior=choose(ui,"##behavior",w.behavior,{"行为占比","状态分布","方向习惯","距离分布","行为雷达"})
    local rows={}
    if w.behavior==1 or w.behavior==5 then
        for _,key in ipairs({"forward","backward","air","attack","guard","parry"}) do
            local row={label=({forward="前走",backward="后走",air="空中",attack="出招",guard="防御",parry="蓝防"})[key],values={},displays={}}
            for side=1,2 do
                local q=scope.players[side];local count=q.feature_valid[key] or 0
                row.values[side]=count>0 and (q.features[key] or 0)/count*100 or nil
                row.displays[side]=percent(q.features[key],count)
            end
            row.tooltip="按该行为有效记录帧计占比；空中、出招等维度可重叠，不是能力评分。"
            rows[#rows+1]=row
        end
        if w.behavior==5 then Charts.paired_radar(ui,"##features_radar",rows,sides,width,vec)
        else Charts.paired_bars(ui,"##features",rows,sides,width,vec,100) end
    elseif w.behavior==2 then
        w.states=choose(ui,"##states",w.states,{"移动与进攻","防御与其他"})
        local keys=w.states==1 and {"forward","backward","walk","attack","air","dash","neutral"} or {"guard","parry","throw","reaction","down","other","unknown"}
        for _,key in ipairs(keys) do
            local a,b=scope.players[1].behavior[key] or 0,scope.players[2].behavior[key] or 0
            rows[#rows+1]={label=Stats.labels[key],values={a/scope.frames*100,b/scope.frames*100},displays={percent(a,scope.frames),percent(b,scope.frames)}}
        end
        Charts.paired_bars(ui,"##states_bars",rows,sides,width,vec,100)
    elseif w.behavior==3 then
        for i,label in ipairs({"下后","下","下前","后","无方向","前","上后","上","上前"}) do
            local row={label=label,values={},displays={}}
            for side=1,2 do
                local q=scope.players[side]
                row.values[side]=q.direction_frames>0 and (q.directions[i] or 0)/q.direction_frames*100 or nil
                row.displays[side]=percent(q.directions[i],q.direction_frames)
            end
            rows[#rows+1]=row
        end
        Charts.paired_bars(ui,"##directions",rows,sides,width,vec,100)
        tooltip(ui,"方向随角色朝向转换为前后，不按屏幕左右统计。")
    else
        Charts.histogram(ui,"##distance",scope.distance_bins,{"<50","50-99","100-149","150-199","200-299","300-399","400-599","600+"},width,vec)
        local d=scope.distance_distribution
        ui.text("平均 "..num(d.mean,1).." / 中位 "..num(d.median,1).." / 九成不超过 "..num(d.p90,1))
        ui.text("双方横向间距，不代表招式射程")
    end
end
local function damage(ui,w,scope,sides,width,vec,callbacks)
    local p=scope.players
    w.damage=choose(ui,"##damage",w.damage,{"受伤分布","主要受伤原因"})
    if w.damage==1 then
        local bars={}
        for i,label in ipairs({"少于500","500～999","1000～1999","2000～2999","3000～4999","5000以上"}) do
            bars[#bars+1]={label=label,values={p[1].damage_bins[i] or 0,p[2].damage_bins[i] or 0},tooltip="此伤害区间内的受伤段数，双方共用计数刻度。"}
        end
        Charts.paired_bars(ui,"##loss_bins",bars,sides,width,vec)
        Charts.paired_boxplot(ui,"##loss_box",{p[1].loss_distribution,p[2].loss_distribution},sides,width,vec)
        local rows={}
        metric(rows,"九成受伤段不超过",p,function(q) return num(q.loss_distribution.p90) end)
        metric(rows,"最大三段占总受伤",p,function(q) return percent(q.loss_distribution.top3_share,1) end)
        table_rows(ui,"##loss_details",sides,rows,vec)
    else
        local by_title={}
        for _,side in ipairs(sides) do for _,cause in pairs(p[side].causes) do
            local row=by_title[cause.title] or {label=cause.title,values={0,0},items={}}
            row.values[side]=cause.damage;row.items[side]=cause.items;by_title[cause.title]=row
        end end
        local bars={};for _,row in pairs(by_title) do bars[#bars+1]=row end
        table.sort(bars,function(a,b) local x,y=a.values[1]+a.values[2],b.values[1]+b.values[2];return x>y or x==y and a.label<b.label end)
        local top={}
        for i=1,math.min(7,#bars) do
            local row=bars[i];top[i]=row
            local lines={row.label.."；自动归类，仍需回看确认。"}
            for _,side in ipairs(sides) do
                lines[#lines+1]=side.."P "..#(row.items[side] or {}).."段，伤害"..row.values[side].."，占本方受伤"..percent(row.values[side],p[side].damage_received)
            end
            row.tooltip=table.concat(lines,"\n")
        end
        if #top==0 then ui.text("没有受伤原因记录") else Charts.paired_bars(ui,"##causes",top,sides,width,vec) end
        ui.text("按所选玩家合计伤害排列前7类")
    end
    for _,side in ipairs(sides) do
        if ui.button("回看"..side.."P最大受伤段") and p[side].largest then callbacks.item(p[side].largest) end
        if #sides==2 and side==1 then ui.same_line() end
    end
end
local function resources(ui,w,scope,report,sides,width,vec,current,callbacks)
    w.resource=choose(ui,"##resource",w.resource,{"血量","斗气","能量"})
    local key=({"health","drive","super"})[w.resource]
    local round_scope=scope
    if scope.round==nil then
        local names,index={},1
        for i,r in ipairs(report.rounds) do names[i]="第"..(r.round+1).."局曲线";if r.round==w.chart_round then index=i end end
        ui.same_line();index=choose(ui,"##chart_round",index,names,130)
        round_scope=report.rounds[index];w.chart_round=round_scope and round_scope.round
    end
    if not round_scope then ui.text("没有曲线记录");return end
    local frame=Charts.paired_timeline(ui,"##resource_timeline",round_scope.series[key],sides,width,176,round_scope.first_frame,round_scope.last_frame,
        current and current.round==round_scope.round and current.frame or nil,vec)
    if frame then callbacks.frame(round_scope.round,frame) end
    local rows={}
    local function resource(label,fn,tip) metric(rows,label,scope.players,function(q) return fn(q.resources[key]) end,tip) end
    resource("平均持有",function(r) return r.mean and num(r.mean,1).."%" or "未知" end)
    resource("最低 / 最高",function(r) return num(r.min,1).." / "..num(r.max,1) end)
    resource("不高于25%占比",function(r) return percent(r.low,r.frames) end)
    resource("归零 / 满条占比",function(r) return percent(r.zero,r.frames).." / "..percent(r.full,r.frames) end)
    resource("累计减少",function(r) return r.delta_frames and num(r.drop,1).."%" or "未知" end,"减少不等同主动消耗，归零不直接证明耗尽；累计变化可超过100%。")
    resource("累计增加",function(r) return r.delta_frames and num(r.gain,1).."%" or "未知" end)
    resource("持有量标准差",function(r) return num(r.sd,1) end,"衡量本场持有量波动，不是管理能力评分。")
    resource("有效记录覆盖",function(r) return percent(r.frames,scope.frames) end)
    table_rows(ui,"##resource_metrics",sides,rows,vec)
    tooltip(ui,"按各自满条折算为100%；缺失记录断线。曲线每30帧聚合，悬停显示区间，不假装是逐帧精度。")
end
function M.new()
    local manager={windows={}}
    for id=1,3 do manager.windows[id]={visible=false,view=1,overview=1,behavior=1,states=1,damage=1,resource=2,reset=true} end
    function manager:open(id,round)
        local w=assert(self.windows[id]);if not w.visible then w.round=round;w.reset=true end;w.visible=true
    end
    function manager:close(id) self.windows[id].visible=false end
    function manager:any_visible() for _,w in ipairs(self.windows) do if w.visible then return true end end;return false end
    function manager:buttons(ui,round)
        for id,title in ipairs(titles) do
            if id>1 then ui.same_line() end
            if UIKit.styled_button(title.."##open_stats",UIKit.THEME.btn_neutral,id<3 and Charts.players[id] or UIKit.COLORS.White) then self:open(id,round) end
        end
    end
    function manager:draw(ui,report,sw,sh,vec,current,callbacks)
        for id,w in ipairs(self.windows) do if w.visible then
            local r=M.layout(sw,sh,id);local screen=sw..":"..sh
            if w.reset or w.screen~=screen then
                ui.set_next_window_size(vec(r.w,r.h),1);ui.set_next_window_pos(vec(r.x,r.y),1)
                w.reset=false;w.screen=screen
            end
            local expanded,open=ui.begin_window(titles[id].."##CFNStatistics"..id,true,2|(1<<5))
            if open==false then w.visible=false end
            local ok,err=pcall(function()
                if not expanded or not w.visible then return end
                if ui.button("关闭##statistics"..id) then w.visible=false;return end
                ui.same_line();w.view=choose(ui,"##stats_view",w.view,views,96)
                if not report or not report.finished or report.error then ui.text("请先完成录像分析");return end
                local names,index={"整场"},1
                for i,q in ipairs(report.rounds) do names[i+1]="第"..(q.round+1).."局";if q.round==w.round then index=i+1 end end
                ui.same_line();index=choose(ui,"##stats_round",index,names,96)
                w.round=index>1 and report.rounds[index-1].round or nil
                local scope=w.round~=nil and report.by_round[w.round] or report.all
                if not scope or scope.frames==0 then ui.text("所选范围没有可用记录");return end
                local width=r.w-32
                local sides=M.sides(id)
                for _,side in ipairs(sides) do
                    ui.push_style_color(0,Charts.players[side])
                    local player=(report.metadata.players or {})[side] or {}
                    local name=type(player.name)=="string" and player.name:gsub("[%c]"," ") or "未知玩家"
                    clipped_text(ui,side.."P · "..name.." · "..Presentation.player_title(report.metadata,side),width)
                    ui.pop_style_color(1)
                end
                clipped_text(ui,string.format("%s · %d帧记录 · %.1f秒",w.round~=nil and "第"..(w.round+1).."局" or "整场",scope.frames,scope.frames/60),width)
                tooltip(ui,"录像 "..tostring(report.metadata.replay_id or "未知").."；时间按60帧/秒换算，包含开场等待和停顿。")
                if w.view==1 then overview(ui,w,scope,report,sides,width,vec)
                elseif w.view==2 then behavior(ui,w,scope,sides,width,vec)
                elseif w.view==3 then damage(ui,w,scope,sides,width,vec,callbacks)
                else resources(ui,w,scope,report,sides,width,vec,current,callbacks) end
                if (report.gaps or 0)>0 or not report.playback_finished then
                    clipped_text(ui,"记录缺口 "..(report.gaps or 0).."；"..(report.playback_finished and "已记录回放结束" or "未记录正常结束"),width)
                end
            end)
            ui.end_window()
            if not ok then w.visible=false;error(err) end
        end end
    end
    return manager
end
return M
