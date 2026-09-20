local Charts=require("func/CFNReplayCapture/statistics_charts")
local Stats=require("func/CFNReplayCapture/statistics")
local Presentation=require("func/CFNReplayCapture/presentation")
local M={}
local function n(v,places) return type(v)=="number" and string.format("%."..(places or 0).."f",v) or "未知" end
local function pct(a,b) return b and b>0 and string.format("%.1f%%",(a or 0)/b*100) or "未知" end
local function signal(p,key) return p.signal_frames>0 and n(p.signals[key] or 0) or "未知" end
local function grid(ui,id,rows,vec)
    if not ui.begin_table(id,4,(1<<6)|(1<<9),vec(0,0)) then return end
    local ok,err=pcall(function()
        for _,col in ipairs({{"项目",1<<3,1.35},{"数值",1<<3,1},{"项目",1<<3,1.35},{"数值",1<<3,1}}) do ui.table_setup_column(col[1],col[2],col[3]) end
        for _,row in ipairs(rows) do
            ui.table_next_row()
            for i=1,4 do ui.table_set_column_index(i-1); ui.text(tostring(row[i] or "")) end
        end
    end)
    ui.end_table(); if not ok then error(err) end
end
local function chooser(ui,id,current,names)
    ui.push_item_width(165); local changed,value=ui.combo(id,current,names); ui.pop_item_width()
    return changed and value or current
end
function M.new()
    local w={behavior=1,damage=1,resource=2}
    function w:draw(ui,report,view,round,side,width,vec,callbacks,current)
        if not report or not report.finished then ui.text("请先分析录像或读取上次分析"); return end
        if report.error then ui.text("记录存在冲突，暂不生成统计"); return end
        local scope=round~=nil and report.by_round[round] or report.all
        if not scope or scope.frames==0 then ui.text("所选局没有可用记录"); return end
        local p=scope.players[side]
        local meta=(report.metadata.players or {})[side] or {}
        if view==2 then
            ui.text(Presentation.player_title(report.metadata,side))
            grid(ui,"##stats_identity",{{"玩家编号",tostring(meta.short_id or "未知"),"MR / LP",n(meta.master_rating).." / "..n(meta.league_point)}},vec)
            grid(ui,"##stats_summary",{
                {"记录帧数",n(scope.frames),"录像时间",n(scope.frames/60,1).." 秒"},
                {"受到伤害",n(p.damage_received),"造成伤害",n(p.damage_dealt)},
                {"受伤段数",n(p.segments),"掉血记录",n(p.damage_observations)},
                {"最大受伤段",n(p.loss_distribution.max),"平均受伤段",n(p.loss_distribution.mean,1)},
                {"普通康新记录",signal(p,"counter"),"确反康新记录",signal(p,"punish" )},
                {"防御新记录",signal(p,"guard"),"其他状态占比",pct(p.behavior.other,scope.frames)},
                {"P0 / P1",(p.priorities.P0 or 0).." / "..(p.priorities.P1 or 0),"P2 / P3",(p.priorities.P2 or 0).." / "..(p.priorities.P3 or 0)},
            },vec)
            if ui.is_item_hovered() then ui.set_tooltip("康与防御按新出现的标记统计，持续标记不重复，不能当作完整接触次数。录像时间按60帧/秒换算，包含开场等待和停顿，不等于比赛倒计时。") end
            ui.text("各局汇总")
            local rows={}
            for _,r in ipairs(report.rounds) do
                if round==nil or r.round==round then
                    local q=r.players[side]
                    rows[#rows+1]={label="第"..(r.round+1).."局",value=q.damage_received,display=tostring(q.damage_received),
                        tooltip="受伤 "..q.damage_received.."，造成伤害 "..q.damage_dealt.."；"..
                            (({p1_zero="1P血量归零",p2_zero="2P血量归零",both_zero="双方血量归零",timeout="时间结束"})[r.ending] or "未观察到局末"),round=r.round}
                end
            end
            local clicked=Charts.bars(ui,"##stats_round_damage",rows,width,vec)
            if clicked then callbacks.round(rows[clicked].round) end
            ui.text("已记录"..#report.rounds.."局；缺失区间 "..report.gaps.."；重复记录已排除 "..report.duplicates)
            ui.text("范围：已记录的开场至血量归零或时间结束")
            if not report.playback_finished then ui.text("未记录正常回放结束，不宣称整场采集完整") end
        elseif view==3 then
            self.behavior=chooser(ui,"##stats_behavior",self.behavior,{"状态分布","行为雷达","方向习惯","距离分布"})
            if self.behavior==1 then
                local rows={}
                for _,key in ipairs(Stats.categories) do
                    local value=p.behavior[key] or 0
                    rows[#rows+1]={label=Stats.labels[key],value=value,display=pct(value,scope.frames),
                        tooltip=Stats.labels[key].."："..value.."帧；观察到进入 "..(p.entries[key] or 0).." 次。片段不等于招式使用次数。"}
                end
                Charts.bars(ui,"##stats_states",rows,width,vec)
            elseif self.behavior==2 then
                local axes={}
                for _,key in ipairs({"forward","backward","air","attack","guard","parry"}) do
                    local valid=p.feature_valid[key] or 0
                    axes[#axes+1]={label=({forward="前走",backward="后走",air="空中",attack="出招",guard="防御",parry="蓝防"})[key],
                        value=valid>0 and (p.features[key] or 0)/valid or nil}
                end
                Charts.radar(ui,"##stats_radar",axes,width,vec)
                ui.text("行为时间占比，不是能力评分；空中和出招等维度可重叠")
            elseif self.behavior==3 then
                Charts.histogram(ui,"##stats_direction",p.directions,{"下后","下","下前","后","无","前","上后","上","上前"},width,vec)
                grid(ui,"##stats_direction_summary",{
                    {"方向变化",n(p.direction_changes),"有效方向帧",n(p.direction_frames)},
                    {"方向多样性",pct(p.direction_entropy,1),"每千帧变化",p.direction_frames>0 and n(p.direction_changes/p.direction_frames*1000,1) or "未知"},
                },vec)
                if ui.is_item_hovered() then ui.set_tooltip("方向按角色朝向转换为前后。多样性采用香农熵除以 log2(9)，0表示单一方向，100%表示九方向均匀出现；不评价操作水平。") end
            else
                ui.text("双方横向间距；游戏距离单位，不代表招式射程")
                Charts.histogram(ui,"##stats_distance",scope.distance_bins,{"<50","50-99","100-149","150-199","200-299","300-399","400-599","600+"},width,vec)
                local d=scope.distance_distribution
                grid(ui,"##stats_distance_summary",{{"平均间距",n(d.mean,1),"中位间距",n(d.median,1)},
                    {"间距波动",n(d.sd,1),"九成间距不超过",n(d.p90,1)}},vec)
            end
        elseif view==4 then
            self.damage=chooser(ui,"##stats_damage",self.damage,{"伤害分布","受伤原因"})
            local d=p.loss_distribution
            if self.damage==1 then
                ui.text("每段受伤的血量损失；连续追击合并，不重复算失误")
                Charts.histogram(ui,"##stats_damage_hist",p.damage_bins,{"<500","500-999","1000-1999","2000-2999","3000-4999","5000+"},width,vec)
                Charts.boxplot(ui,"##stats_damage_box",d,width,vec)
                grid(ui,"##stats_damage_summary",{
                    {"平均 / 中位",n(d.mean,1).." / "..n(d.median,1),"标准差",n(d.sd,1)},
                    {"最小 / 最大",n(d.min).." / "..n(d.max),"九成不超过",n(d.p90)},
                    {"下 / 上四分位",n(d.q1,1).." / "..n(d.q3,1),"最大三段占比",pct(d.top3_share,1)},
                },vec)
                if ui.is_item_hovered() then ui.set_tooltip("箱体为25%到75%分位，中线为中位数，须为最小到最大；分位数线性插值，九成值采用排序后第ceil(0.9N)项。标准差按本场总体计算，不外推到玩家长期水平。") end
                if p.largest and ui.button("回看最大受伤段") then callbacks.item(p.largest) end
            else
                local rows={}
                for _,cause in pairs(p.causes) do rows[#rows+1]=cause end
                table.sort(rows,function(a,b) return a.damage>b.damage or a.damage==b.damage and a.title<b.title end)
                local bars,cumulative={},0
                for _,cause in ipairs(rows) do
                    cumulative=cumulative+cause.damage
                    local largest
                    for _,item in ipairs(cause.items) do if not largest or item.damage>largest.damage then largest=item end end
                    bars[#bars+1]={label=cause.title,value=cause.damage,display=n(cause.damage),target=largest,
                        tooltip=cause.title.."："..cause.count.."段，占总伤害 "..pct(cause.damage,p.damage_received)..
                            "，累计 "..pct(cumulative,p.damage_received).."。点击回看此类最大受伤段。"}
                end
                local clicked=Charts.bars(ui,"##stats_causes",bars,width,vec)
                if clicked then callbacks.item(bars[clicked].target) end
            end
        elseif view==5 then
            self.resource=chooser(ui,"##stats_resource",self.resource,{"血量曲线","斗气曲线","能量曲线"})
            local key=({"health","drive","super"})[self.resource]; local r=p.resources[key]
            grid(ui,"##stats_resource_summary",{
                {"平均持有",r.mean and n(r.mean,1).."%" or "未知","最低 / 最高",n(r.min,1).." / "..n(r.max,1)},
                {"累计减少",r.delta_frames and n(r.drop,1).."%" or "未知","累计增加",r.delta_frames and n(r.gain,1).."%" or "未知"},
                {"不高于25%占比",pct(r.low,r.frames),"归零占比",pct(r.zero,r.frames)},
                {"满条占比",pct(r.full,r.frames),"持有量波动",n(r.sd,1)},
            },vec)
            if ui.is_item_hovered() then ui.set_tooltip("按各自满条归一为100%；累计变化可超过100%。只对连续且上限一致的记录求差，不跨换局相减。减少不等同主动消耗，归零不直接认定耗尽状态。") end
            local rounds=round~=nil and {scope} or report.rounds
            for _,rinfo in ipairs(rounds) do
                ui.text("第"..(rinfo.round+1).."局 · 百分比")
                local frame=Charts.timeline(ui,"##stats_timeline_"..rinfo.round,rinfo.series[key][side],width,#rounds>1 and 86 or 152,
                    rinfo.first_frame,rinfo.last_frame,current and current.round==rinfo.round and current.frame or nil,vec)
                if frame then callbacks.frame(rinfo.round,frame) end
            end
        end
    end
    return w
end
return M
