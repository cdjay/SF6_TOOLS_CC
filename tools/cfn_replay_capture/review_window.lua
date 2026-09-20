local M = {}
local statuses={idle="尚未分析",close_overlay="正在交还按键控制",first_round="正在返回第一局",
    rewinding="正在回到开头",setting_speed="正在调整播放速度",resuming="正在开始播放",
    recording="正在采集整场事实",analyzing="正在整理事实",ready="事实已就绪",stopped="采集已停止",loading_saved="正在读取已保存事实"}
local errors={missing_damage_data="这份记录缺少受击信息",unsupported_analysis="暂不支持这份录像",
    conflicting_samples="同一位置的记录不一致",rewound_capture="记录中存在重复播放",unavailable_review="这个位置暂时无法跳转",
    round_changed="请先切换到所选局",replay_changed="当前录像与分析结果不同",saved_missing="没有找到这份录像的分析记录"}
local fixed,stretch=1<<4,1<<3
function M.surface_size(ui)
    if type(ui.get_display_size)~="function" then return 1920,1080 end
    local a,b=ui.get_display_size()
    if type(a)~="number" then a,b=a and a.x,a and a.y end
    if type(a)~="number" or a<=0 or type(b)~="number" or b<=0 then return 1920,1080 end
    return a,b
end
function M.new(model,statistics_window,guard_window,statistics_popups)
    local w={model=model,visible=true,reset_position=true,view=1,stats_all=false}
    function w:draw(ui,analysis,controls,navigation,state,labels,sw,sh,vec,handoff,round_navigation)
        local c=controls.clock
        if not self.visible or not c or not c.position or state.render_tick-c.render_tick>2 then return end
        model:update(analysis,c)
        local width=math.min(720,sw-24)
        ui.set_next_window_size(vec(width,0),1)
        local layout=table.concat({self.view,model.selected or -1,model.player,model.priority,#model.items,analysis.status},":")
        if self.reset_position or self.layout~=layout then
            local anchor=not self.reset_position and self.anchor or nil
            ui.set_next_window_pos(vec(anchor and math.max(12,math.min(anchor.x,sw-width-12)) or (sw-width)/2,
                anchor and math.min(anchor.y,sh-12) or sh-12),1,vec(0,1))
            self.reset_position=false; self.layout=layout
        end
        local visible=ui.begin_window("录像分析##CFNReview",true,2|(1<<3)|(1<<4)|(1<<5)|(1<<6))
        local table_open=false
        local drawn,draw_error=pcall(function()
        if visible then
            local changing=round_navigation and round_navigation.active
            local busy=analysis.active or analysis.status=="analyzing" or analysis.status=="loading_saved" or navigation.active or changing
            if not busy then
                if ui.button("采集整场事实") then if analysis:start() then handoff() end end
                ui.same_line()
                if ui.button("读取已保存事实##review") then analysis:load_saved() end
            else
                if ui.button("停止##review") then
                    if changing then round_navigation:cancel() elseif navigation.active then navigation:cancel() else analysis:cancel() end
                end
            end
            ui.same_line()
            ui.text(changing and "正在换局" or navigation.active and
                (navigation.status=="close_overlay" and "正在交还按键控制" or "正在定位") or (statuses[analysis.status] or "等待录像"))
            if statistics_popups then
                statistics_popups:buttons(ui,model.selected)
                ui.push_item_width(100)
                local changed,view=ui.combo("##review_view",self.view==6 and 2 or 1,{"问题","防御"})
                ui.pop_item_width()
                if changed then self.view=view==2 and 6 or 1;self.reset_position=true end
                ui.same_line()
            elseif statistics_window then
                ui.push_item_width(100)
                local changed,view=ui.combo("##review_view",self.view,{"问题","总览","行为","伤害","资源","防御"})
                ui.pop_item_width()
                if changed then self.view=view; self.reset_position=true end
                ui.same_line()
            end
            local names,index={},1
            local offset=(self.view==1 or self.view==6) and 0 or 1
            if offset==1 then names[1]="整场" end
            for i,n in ipairs(model.rounds) do names[i+offset]="第"..(n+1).."局"; if n==model.selected then index=i+offset end end
            if offset==1 and self.stats_all then index=1 end
            ui.push_item_width(82)
            local changed,next_index=ui.combo("##review_round",index,names)
            ui.pop_item_width()
            if changed then
                self.stats_all=offset==1 and next_index==1
                if model.rounds[next_index-offset] then model:select(model.rounds[next_index-offset]); model:update(analysis,c) end
                self.reset_position=true
            end
            ui.same_line()
            if ui.button("前往该局") and not busy and round_navigation and model.selected~=model.current and not (offset==1 and self.stats_all) then
                if round_navigation:start(model.selected) then handoff() end
            end
            ui.same_line(); ui.push_item_width(88)
            local player_names={"1P","2P"}
            if c.local_side==1 or c.local_side==2 then player_names[c.local_side]=player_names[c.local_side].."（我）" end
            local pc,side=ui.combo("##review_player",model.player,player_names)
            ui.pop_item_width()
            if pc then model:select_player(side); model:update(analysis,c) end
            if self.view==1 then
                ui.same_line(); ui.push_item_width(105)
                local lc,level=ui.combo("##review_priority",model.priority+1,{"全部级别","P0","P1","P2","P3"})
                ui.pop_item_width()
                if lc then model.priority=level-1; model:update(analysis,c) end
            end
            ui.same_line(); ui.text(string.format("第%d局 · %d帧",c.position.round+1,c.position.frame))
            local reason=analysis.damage_error or analysis.load_error or analysis.locate_reason
            if not reason and analysis.status=="stopped" then reason=analysis.reason end
            if not reason and navigation.status=="stopped" then reason=navigation.reason end
            if not reason and round_navigation and round_navigation.status=="stopped" then reason=round_navigation.reason end
            if reason then ui.text(errors[reason] or labels[reason] or "暂时无法完成，请检查录像状态") end
            if state.review_restore_error then ui.text("面板未恢复，请按面板开关键") end
            if controls.speed_restore then
                ui.text(controls.restore_status=="restoring" and "正在恢复正常速度" or "等待录像可操作后恢复正常速度")
            elseif controls.restore_status and controls.restore_status~="restored" and controls.restore_status~="replay_changed" then
                ui.text("正常速度未恢复，请在游戏中调整为1倍速")
            end
            if analysis.confirmation_error then ui.text("确认记录与本场不符，仅显示自动结果") end
            if analysis.rule_error then ui.text(analysis.rule_error)
            elseif analysis.rule_name then ui.text("规则："..analysis.rule_name) end
            if analysis.reload_rules and analysis.status=="ready" and not busy then
                if ui.button("更新规则") then analysis:reload_rules() end
                ui.same_line()
                if ui.button("导出离线数据") then analysis:export_workbench() end
                ui.same_line()
                local changed,value=ui.checkbox("自动读取规则",analysis.auto_rules==true)
                if changed then analysis.auto_rules=value end
            end
            if analysis.rule_reload_message then ui.text(analysis.rule_reload_message) end
            if analysis.workbench_message then ui.text(analysis.workbench_message) end
            if self.view==6 then
                if guard_window then guard_window:draw(ui,analysis,model,controls,busy,handoff,vec) end
                return
            end
            if statistics_window and self.view~=1 then
                if not model.matching or analysis.status~="ready" then ui.text("请先采集或读取已保存事实"); return end
                local statistics_round=model.selected
                if self.stats_all then statistics_round=nil end
                statistics_window:draw(ui,analysis.statistics,self.view,statistics_round,model.player,width-24,vec,{
                    round=function(round) model:select(round); self.stats_all=false; self.reset_position=true end,
                    frame=function(round,frame)
                        if not busy and analysis:locate_statistics(round,frame) then handoff(); busy=true end
                    end,
                    item=function(item)
                        for _,candidate in ipairs(analysis.review_items or analysis.damage_items or {}) do
                            if item and candidate.id==item.id and not busy and model:can_locate(analysis,controls,candidate) then
                                if analysis:locate_review(candidate,1,45) then handoff(); busy=true end
                                return
                            end
                        end
                        if item and item.round~=model.current then analysis.locate_reason="round_changed" end
                    end,
                },c.position)
                return
            end
            local total=0
            for _,item in ipairs(model.items) do total=total+item.damage end
            ui.text(string.format("%d处 · 伤害%d · 点击问题定位",#model.items,total))
            if #model.items==0 then
                local empty_rules=analysis.rule_engine and analysis.rule_engine.document.include_system==false
                if empty_rules then for _,rule in ipairs(analysis.rule_engine.document.rules) do if rule.enabled then empty_rules=false;break end end end
                ui.text(model.matching and analysis.status=="ready" and (empty_rules and "当前配置尚未启用问题规则" or "没有符合筛选的问题") or "本局尚未分析")
            elseif ui.begin_table("##CFNReviewTableV2",5,(1<<3)|(1<<6)|(1<<7)|(1<<9),vec(0,0)) then
                table_open=true
                for _,col in ipairs({{"发生帧",fixed,62},{"问题级别",fixed,72},{"问题描述",stretch,1},{"伤害",fixed,62},{"硬直差",fixed,88}}) do
                    ui.table_setup_column(col[1],col[2],col[3])
                end
                ui.table_next_row(1)
                for i,name in ipairs({"发生帧","问题级别","问题描述","伤害","硬直差"}) do ui.table_set_column_index(i-1); ui.table_header(name) end
                if ui.table_get_sort_specs then
                    local specs=ui.table_get_sort_specs()
                    if specs and specs.specs_dirty then
                        local sort=specs:get_specs()[1]
                        model:sort(sort and sort.column_index,sort and sort.sort_direction==2)
                        model:update(analysis,c); specs.specs_dirty=false
                    end
                end
                for _,item in ipairs(model.items) do
                    local enabled=model:can_locate(analysis,controls,item) and not busy
                    local evidence=item.native_advantage
                    local advantage=evidence and string.format("原生 %+d",evidence.value) or item.native_snapshot and "未关联" or "未读取"
                    ui.table_next_row()
                    ui.table_set_column_index(0); ui.text(tostring(item.frame))
                    ui.table_set_column_index(1); ui.text(item.priority)
                    ui.table_set_column_index(2)
                    if ui.menu_item(item.classification.title.."##review_"..item.id,"",false,enabled) and enabled then
                        if analysis:locate_review(item,1,45) then handoff(); busy=true end
                    end
                    if ui.is_item_hovered() then ui.set_tooltip(string.format("第%d局 %d帧；定位到%d帧。%s%s",item.round+1,item.frame,item.review_frame,
                        item.human_review and "玩家已确认。" or item.custom_rule and "自定义规则："..item.custom_rule.title.."。不代表已确认失误。" or "自动复核建议，不代表已确认失误。",
                        evidence and "回看此次防御中最后一次硬直差变化。正负归属待核对。" or "未确认对应硬直差，回看动作起点。")) end
                    ui.table_set_column_index(3); ui.text(tostring(item.damage))
                    if item.kind=="confirmed_opportunity" and ui.is_item_hovered() then
                        ui.set_tooltip("此项是错失机会。伤害列统计受伤量，不估算错失的伤害。")
                    elseif item.native_combo_damage and ui.is_item_hovered() then
                        ui.set_tooltip(string.format("实际减少血量%d；末次掉血时游戏连段计数显示%d。倒地前演出中的伤害合并统计，不把超过剩余血量的部分重复加入。",item.damage,item.native_combo_damage))
                    end
                    ui.table_set_column_index(4); ui.text(advantage)
                    if ui.is_item_hovered() then
                        if evidence then ui.set_tooltip("显示相邻防御过程中新出现的游戏原始值；未确认属于哪一方，不等于已证明可以确反。")
                        elseif item.native_snapshot then ui.set_tooltip(string.format("第%d帧的画面原始读数为%+d，但未确认对应这次受击的防御片段。保留供核对，不作为确反依据或定位目标。",item.native_snapshot.frame,item.native_snapshot.value))
                        else ui.set_tooltip("这一帧没有同步的硬直差读数，不能用缺失数据填0。") end
                    end
                end
                ui.end_table(); table_open=false
            end
        end
        end)
        if table_open then ui.end_table() end
        if ui.get_window_pos and ui.get_window_size then
            local pos,size=ui.get_window_pos(),ui.get_window_size()
            self.anchor={x=pos.x,y=pos.y+size.y}
        end
        ui.end_window()
        if not drawn then error(draw_error) end
    end
    return w
end
return M
