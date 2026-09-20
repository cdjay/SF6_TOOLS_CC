local M = {}
local statuses = {idle="尚未分析", close_overlay="请收起面板，开始分析整场", first_round="正在返回第一局", rewinding="正在回到第一局开头",
    setting_speed="正在调整到8倍速", resuming="正在开始播放", recording="正在记录整场录像",
    analyzing="正在筛选位置", ready="位置筛选完成", stopped="分析已停止", loading_saved="正在读取上次分析"}
local reasons = {knockout="本局血量已归零", time_up="本局时间已结束", round_boundary="已阻止记录下一局",
    replay_end="回放已结束", result_open="请先退出结束窗口，回到录像并暂停",
    round_changed="局数已变化，请回到所分析的一局", replay_changed="录像已变化", overlay_open="面板已打开，分析中止",
    cancelled="已取消", paused_early="播放提前暂停", unsupported_analysis="此录像版本暂不支持筛选",
    export_failed="保存失败，原始记录仍在", conflicting_samples="同一帧的数据不一致", rewound_capture="记录中发生了倒退",
    missing_finish_state="未能读到血量或时间", speed_unavailable="无法确认播放速度", pause_first="请先用游戏按键暂停",
    not_confirmed="未确认游戏响应", position_unavailable="未能读到当前位置", capture_active="请先停止当前记录",
    saved_missing="这份录像还没有保存的记录", saved_read_failed="读取失败，请稍后重试",
    saved_invalid="保存的记录暂时无法使用"}
function M.new()
    local page = 1
    return function(imgui, analysis, controls, navigation, stable, press, control_labels)
        if not imgui.tree_node("整场反击位置") then return end
        if imgui.button("分析整场录像") then if analysis:start() then page=1 end end
        imgui.same_line()
        if imgui.button("停止分析") then analysis:cancel() end
        if imgui.button("读取上次分析") then if analysis:load_saved() then page=1 end end
        if analysis.load_error then imgui.text(reasons[analysis.load_error] or control_labels[analysis.load_error] or "暂时无法读取上次分析") end
        imgui.text(statuses[analysis.status] or "分析已停止")
        if analysis.stopped_phase then
            local phases={first_round="返回第一局",rewind="回退",boundary_check="确认回退下限",speed="设置8倍速",resuming="恢复播放",
                recording="记录整场"}
            imgui.text("结束于："..(phases[analysis.stopped_phase] or "分析"))
        end
        local speed = controls.snapshot and controls.snapshot.speed
        if analysis.active and type(speed) == "number" then
            imgui.text(string.format("当前速度：%.1f倍 / 目标：8倍",speed))
        end
        if analysis.active and analysis.current_round then imgui.text(string.format("正在记录第%d局",analysis.current_round+1)) end
        local reason = not analysis.previous_result and analysis.error or analysis.reason
        if reason and reason ~= "capture_end" then imgui.text(reasons[reason] or control_labels[reason] or "本次记录未完成") end
        if analysis.capture then
            if analysis.previous_result then imgui.text("以下保留的是上一次分析结果") end
            local capture = analysis.capture
            imgui.text(string.format("共记录%d条", #capture.samples))
            for _,round in ipairs(analysis.review and analysis.review.rounds or {}) do
                imgui.text(string.format("第%d局：%d～%d帧%s",round.round+1,round.first_frame,round.last_frame,
                    round.finish_frame and " / 已记录到局末" or " / 未确认局末"))
            end
            if analysis.review and analysis.status=="ready" then
                imgui.text(analysis.review.coverage_ok and "各局均记录到结束，未发现断帧；开头范围仍需核对。"
                    or "未通过完整性检查，请按各局实际记录范围核对。")
            end
            imgui.text(analysis.saved and "原始记录已保存" or "原始记录尚未保存")
            if analysis.reason == "replay_end" then
                imgui.text("请选择重新播放，再暂停；本次结果会保留，不会重新记录。")
            end
        end
        local items = analysis.items or {}
        if analysis.status == "ready" then
            imgui.text(string.format("找到%d处候选；仅筛选4帧和5帧以上。", #items))
            imgui.text("时间条件待实战核对，不保证打得到，也不代表玩家漏了确反。")
            if #items == 0 then imgui.text("未找到符合当前证据要求的位置，不等于本局没有确反机会。") end
        end
        if analysis.reason and analysis.reason ~= "replay_end" and analysis.capture and not analysis.previous_result then
            imgui.text("本次为未完成记录，以下只显示已记录范围内的候选。")
        end
        if analysis.capture and not analysis.active and controls.snapshot and not controls.snapshot.paused and not controls.snapshot.result_open then
            imgui.text("记录已停止；录像仍在播放，请用游戏暂停键暂停。")
        end
        local pages = math.max(1, math.ceil(#items/12))
        page = math.max(1, math.min(page, pages))
        if pages > 1 then
            if imgui.button("上一页##cfn_candidates") then page=math.max(1,page-1) end
            imgui.same_line(); imgui.text(string.format("%d / %d",page,pages)); imgui.same_line()
            if imgui.button("下一页##cfn_candidates") then page=math.min(pages,page+1) end
        end
        for i=(page-1)*12+1, math.min(page*12,#items) do
            local item=items[i]
            local label = item.kind == "four_frame_boundary" and "4帧 / 待核对" or "5帧以上 / 待核对"
            if imgui.button(string.format("第%d局  %d帧  %dP防守后  %s##cfn_candidate_%d",item.round+1,item.frame,item.defender,label,i)) then
                analysis:locate(item,stable,press)
            end
            imgui.text(string.format("观察到%s%d帧%s",item.lower_bound and "至少" or "",item.frames,
                item.distance and string.format(" / 位置间距%.2f（不等于射程）",item.distance) or ""))
        end
        if analysis.locate_reason then imgui.text(reasons[analysis.locate_reason] or "当前不能定位") end
        if analysis.locate_round then imgui.text(string.format("请先切到第%d局并暂停，再点击此位置。",analysis.locate_round+1)) end
        if navigation.active then imgui.text("请收起面板，定位到所选位置")
        elseif navigation.status == "reached" then imgui.text("已停在目标帧")
        elseif navigation.status == "stopped" or navigation.status == "cancelled" then
            imgui.text("定位已停止：" .. (control_labels[navigation.reason] or reasons[navigation.reason] or "请检查录像状态后重试"))
        end
        imgui.tree_pop()
    end
end
return M
