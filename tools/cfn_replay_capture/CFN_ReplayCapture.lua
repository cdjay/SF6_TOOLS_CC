-- Experimental entry: deploy explicitly, never included in the production package.
if _G.SF6CC_CFNReplayCaptureExperiment then return end

local Schema = require("func/CFNReplayCapture/schema")
local Sessions = require("func/CFNReplayCapture/session")
local Sampler = require("func/CFNReplayCapture/sampler")
local Runtime = require("func/CFNReplayCapture/runtime")
local Presentation = require("func/CFNReplayCapture/presentation")
local Controls = require("func/CFNReplayCapture/controls")
local Keyboard = require("func/CFNReplayCapture/keyboard")
local Keybindings = require("func/CFNReplayCapture/keybindings")
local Navigation = require("func/CFNReplayCapture/navigation")
local RoundNavigation = require("func/CFNReplayCapture/round_navigation")
local ReplaySpeed = require("func/CFNReplayCapture/replay_speed")
local Candidates = require("func/CFNReplayCapture/candidates")
local MatchReview = require("func/CFNReplayCapture/match_review")
local SavedCapture = require("func/CFNReplayCapture/saved_capture")
local Analysis = require("func/CFNReplayCapture/analysis")
local DamageReview = require("func/CFNReplayCapture/damage_review")
local DamageRules = require("func/CFNReplayCapture/damage_rules")
local RuleConfig = require("func/CFNReplayCapture/rule_config")
local RuleContext = require("func/CFNReplayCapture/rule_context")
local Workbench = require("func/CFNReplayCapture/workbench")
local RuleEvaluation = require("func/CFNReplayCapture/rule_evaluation")
local GuardReview = require("func/CFNReplayCapture/guard_review")
local GuardWindow = require("func/CFNReplayCapture/guard_window")
local ReviewAssessments = require("func/CFNReplayCapture/review_assessments")
local Statistics = require("func/CFNReplayCapture/statistics")
local StatisticsPopups = require("func/CFNReplayCapture/statistics_popups")
local ReviewWindow = require("func/CFNReplayCapture/review_window")
local statistics_popups=StatisticsPopups.new()
local review_window = ReviewWindow.new(require("func/CFNReplayCapture/review_model").new(),nil,GuardWindow.new(),statistics_popups)
local review_font, review_font_attempted
local draw_review = require("func/CFNReplayCapture/review_panel").new()
local deps = {
    schema = Schema, sessions = Sessions, replay_speed = ReplaySpeed.new(sdk), match_review = MatchReview, saved_capture = SavedCapture,
    damage_review = DamageReview, damage_rules = DamageRules, review_assessments = ReviewAssessments, statistics = Statistics,
    guard_review = GuardReview,
    rule_config=RuleConfig,rule_context=RuleContext,workbench=Workbench,rule_evaluation=RuleEvaluation,
    sdk = sdk, re = re, thread = thread, json = json, fs = fs, date = os.date, reframework = reframework,
    report = function(message) log.error("[CFN capture] " .. tostring(message)) end,
    analysis_report = function(r)
        log.info(string.format("[CFN analysis] event=%s phase=%s action=%s reason=%s round=%s frame=%s speed=%s control=%s end_check=%s",
            r.event,r.phase or "none",r.action or "none",r.reason or "none",tostring(r.round),tostring(r.frame),tostring(r.speed),r.control_status,r.end_check or "none"))
    end,
    navigation_report = function(r)
        log.info(string.format("[CFN navigation] status=%s reason=%s stable=%d round=%d start=%d target=%d actual=%d seconds=%.3f presses=%d ticks=%d prepare=%d release=%d confirm=%d press_ms=%d held_ms=%.3f held_samples=%d",
            r.status, r.reason or "none", r.stable_frames, r.round, r.start_frame, r.target, r.current,
            r.seconds, r.presses, r.render_ticks, r.prepare_ticks, r.release_ticks, r.confirm_ticks,
            r.press_ms, r.held_ms, r.held_samples))
    end,
}
local ok, state = pcall(function()
    deps.sampler = Sampler.new(sdk)
    return Runtime.attach(deps)
end)
if not ok then log.error("[CFN capture] " .. tostring(state)) end
_G.SF6CC_CFNReplayCaptureExperiment = ok and state or { failed = true }
local controls_ok, controls, navigation_ok, navigation
local analysis_ok, analysis
local round_navigation
if ok then
    deps.review_input_blocked = function() return state.render_tick <= (state.review_block_until or -1) end
    local loaded, overrides = pcall(json.load_file, "cfn-keyboard-bindings.json")
    deps.bindings = Keybindings.new(sdk, loaded and type(overrides) == "table" and overrides or {})
    deps.keyboard = Keyboard.new(deps)
    re.on_script_reset(function() deps.keyboard:cancel_handoff() end)
    controls_ok, controls = pcall(Controls.attach, deps, state)
    if not controls_ok then deps.report(controls) end
    if controls_ok then
        navigation_ok, navigation = pcall(Navigation.attach, deps, state, controls)
        if not navigation_ok then deps.report(navigation) end
        if navigation_ok then
            round_navigation=RoundNavigation.attach(deps,state,controls)
            analysis_ok, analysis = pcall(Analysis.attach, deps, state, controls, navigation, Candidates)
            if not analysis_ok then deps.report(analysis) end
        end
    end
end

local labels = {
    ready = "尚未开始", waiting = "等待录像播放", capturing = "正在记录",
    stopped = "已停止", saved = "已保存", empty = "还没有记录到内容",
    stop_first = "请先停止记录", export_first = "请先保存上一份记录",
    export_failed = "保存失败，记录仍保留", capacity = "记录已满，已停止",
    left_replay = "已离开录像，记录停止", replay_changed = "录像已切换，记录停止",
    thread_changed = "记录中断，请保存本次结果", read_error = "读取失败，已停止记录",
    overlapping_update = "记录中断，请保存本次结果",
    callback_thread_mismatch = "记录中断，请保存本次结果",
    unpaired_callback = "记录中断，请保存本次结果", wait_update = "请稍后再点开始记录",
}
local speed = 1
local live = true
local target_frame_text = "0"
local navigation_stable_frames, navigation_press_ms = 1, 45
local control_labels = { waiting = "等待录像界面", ready = "录像已暂停，可以操作", queued = "等待执行",
    setting_speed = "正在设置播放速度", speed_unavailable = "无法设置指定播放速度",
    speed_list_unavailable = "暂时无法读取播放速度", speed_target_missing = "未找到需要的播放速度",
    speed_ambiguous = "无法确认播放速度", speed_change_denied = "当前无法切换播放速度",
    key_queued = "准备发送按键", key_sent = "按键已发送，正在核对结果", confirmed = "已确认游戏响应",
    not_confirmed = "操作结果尚未确认，请核对下方录像位置", close_overlay = "请收起 REFramework 面板，随后执行一次按键",
    key_unavailable = "无法确定按键，请在按键设置中指定", keyboard_unavailable = "按键控制暂不可用，请稍后重试；仍无效请重启游戏",
    position_unavailable = "尚未读到录像帧数", position_changed = "录像位置已变化，操作取消",
    focus_lost = "游戏不在前台，操作取消", key_held = "请松开键盘按键后重试", send_failed = "按键发送失败",
    release_failed = "按键释放失败，请手动按下并松开该键", cancelled = "操作已取消", stale = "操作已过期，请重试",
    update_busy = "画面仍在更新，请暂停后重试",
    menu_open = "请先关闭录像设置菜单", dialog_open = "请先关闭游戏弹窗", list_open = "请先关闭录像列表",
    result_open = "请先关闭录像结果菜单", settings_open = "请先关闭对战设置", hud_open = "请先关闭画面显示设置",
    round_changing = "请等待换局结束", takeover_active = "请先结束玩家接管", capture_active = "请先停止记录",
    expired = "操作未执行，请重试", outside = "当前不在录像中",
    control_busy = "另一项操作尚未结束", round_changed = "局数已变化，定位停止",
    navigation_limit = "未能到达目标，定位已停止",
    overlay_open = "打开面板，已停止定位",
    press_unavailable = "按键助手不支持此速度，请重新启动游戏",
    replay_changed = "录像已切换，操作取消", pause_first = "请先用游戏按键暂停", round_unavailable = "当前不能切换到这一局", failed = "控制已停用，请重启游戏", disabled = "控制已停用" }
local navigation_labels = { idle = "尚未定位", close_overlay = "请收起 REFramework 面板，开始定位",
    seeking = "正在定位", settling = "正在确认目标帧", reached = "已到达目标帧", cancelled = "定位未完成，已取消",
    invalid_target = "请输入有效的非负整数帧数", stopped = "定位已停止" }
re.on_draw_ui(function()
    if not imgui.tree_node("录像采集试验") then return end
    if not ok then
        imgui.text("采集未能启动，请关闭游戏后检查。")
        imgui.tree_pop()
        return
    end
    local changed
    changed, live = imgui.checkbox("显示当前录像信息", live)
    if live then state:request_preview() end
    if state.latest then
        imgui.text(state.render_tick - state.latest.render_tick <= 2 and "最近读取的信息" or "上次读取的信息（当前未刷新）")
        Presentation.draw(imgui, state.latest, Schema)
    else imgui.text(state.preview_failed and "信息读取已停止，请重启游戏" or "等待录像更新") end
    imgui.separator()
    if imgui.tree_node("录像控制") then
        if controls_ok then
            state:request_preview()
            imgui.text(control_labels[controls.status] or "等待录像界面")
            local snapshot = controls.snapshot
            if snapshot then
                imgui.text((snapshot.paused and "原生界面：暂停" or "原生界面：播放")
                    .. " / 速度读数：" .. tostring(snapshot.speed or "未知")
                    .. (state.render_tick - snapshot.render_tick > 2 and "（上次读取）" or ""))
            end
            local clock = controls.clock
            if clock and clock.position then
                local label = state.render_tick - clock.render_tick <= 2 and "录像位置：" or "上次读到的位置："
                imgui.text(string.format("%s第%d局 / 第%d帧", label, clock.position.round + 1, clock.position.frame))
            else imgui.text("录像位置：等待读取") end
            local result = controls.last_result
            if result then
                imgui.text(string.format("上次操作：第%d局 %d帧 → 第%d局 %d帧", result.before.round + 1,
                    result.before.frame, result.after.round + 1, result.after.frame))
                if result.before.round == result.after.round then imgui.text(string.format("实际变化：%+d帧", result.after.frame - result.before.frame)) end
                if result.after_speed then
                    imgui.text(string.format("速度：%.1f倍 → %.1f倍",result.before_speed,result.after_speed))
                end
                local key = result.key
                if key then
                    local name = key >= 0x30 and key <= 0x5a and string.char(key) or tostring(key)
                    imgui.text("使用按键：" .. name .. (result.source == "game" and "（游戏设置）" or "（手动设置）"))
                end
            end
            if imgui.button("继续播放") then controls:request("resume") end
            for i, item in ipairs({
                { "前进一帧", "step" }, { "后退一帧", "back" },
                { "中步前进", "medium_forward" }, { "中步后退", "medium_back" },
                { "向前跳进（大步）", "forward" }, { "向后回退（大步）", "rewind" },
                { "上一局", "previous_round" }, { "下一局", "next_round" },
                { "降低速度", "slower" }, { "提高速度", "faster" }, { "恢复正常速度", "normal_speed" },
                { "打开原生接管选择", "takeover" } }) do
                if i % 2 == 0 then imgui.same_line() end
                if imgui.button(item[1]) then controls:request(item[2]) end
            end
            imgui.separator()
            if navigation_ok then
                changed, target_frame_text = imgui.input_text("目标帧（当前局）", target_frame_text)
                if imgui.button("定位到此帧") then
                    local digits = target_frame_text:match("^%s*(%d+)%s*$")
                    navigation:start(digits and tonumber(digits) or nil, navigation_stable_frames, navigation_press_ms)
                end
                imgui.same_line()
                if imgui.button("取消定位") then navigation:cancel() end
                local message = navigation_labels[navigation.status] or "定位已停止"
                if navigation.reason then message = message .. "：" .. (control_labels[navigation.reason] or "请检查录像状态后重试") end
                imgui.text(message)
                if navigation.target then
                    imgui.text(string.format("第%d局 / 目标%d帧 / 已读到%d帧", navigation.round + 1,
                        navigation.target, navigation.current))
                    if navigation.status ~= "reached" then
                        imgui.text(string.format("距离目标：%d帧", math.abs(navigation.target - navigation.current)))
                    end
                end
                if navigation.elapsed then
                    imgui.text(string.format("本次耗时：%.2f秒 / 按键%d次", navigation.elapsed, navigation.steps))
                end
            else imgui.text("定位未能启动，单次控制仍可使用") end
            if imgui.tree_node("按键设置（留空为读取游戏设置）") then
                for _, item in ipairs({ { "向前跳进", "forward" }, { "向后回退", "rewind" },
                    { "中步前进", "medium_forward" }, { "中步后退", "medium_back" },
                    { "前进一帧", "step" }, { "后退一帧", "back" }, { "继续播放", "resume" },
                    { "上一局", "previous_round" }, { "下一局", "next_round" }, { "降低速度", "slower" },
                    { "提高速度", "faster" }, { "恢复正常速度", "normal_speed" }, { "接管选择", "takeover" } }) do
                    local edited, value = imgui.input_text(item[1], deps.bindings.overrides[item[2]] or "")
                    if edited then
                        deps.bindings.overrides[item[2]] = value
                        pcall(json.dump_file, "cfn-keyboard-bindings.json", deps.bindings.overrides, -1)
                    end
                end
                imgui.tree_pop()
            end
        else imgui.text("录像控制未能启动，信息查看和采集仍可使用") end
        imgui.tree_pop()
    end
    imgui.separator()
    if analysis_ok then
        state:request_preview()
        local visibility_changed, visible = imgui.checkbox("显示录像分析浮窗", review_window.visible)
        if visibility_changed then review_window.visible = visible end
        if imgui.button("恢复浮窗位置") then review_window.reset_position = true; review_window.visible = true end
        if imgui.tree_node("旧版候选检查（调试）") then
            draw_review(imgui, analysis, controls, navigation, navigation_stable_frames,
                navigation_press_ms, control_labels)
            imgui.tree_pop()
        end
    end
    changed, speed = imgui.combo("手动记录标记（不调速）", speed, { "正常速度", "8倍速度" })
    if imgui.button("开始记录") then state:start(speed == 1 and "1x" or "8x") end
    if imgui.button("停止记录") then state:stop() end
    if imgui.button("保存记录") then state:save() end
    imgui.text(labels[state.status] or "记录中断，请保存本次结果")
    local session = state.session
    if session then
        imgui.text("已记录：" .. #session.samples)
        local count = 0
        for _, value in pairs(session.issue_counts) do count = count + value end
        imgui.text("待核对处：" .. count)
    end
    imgui.tree_pop()
end)

re.on_frame(function()
    if analysis_ok then
        local restored,restore_err=pcall(deps.keyboard.update_handoff,deps.keyboard,
            analysis.active or navigation.active or round_navigation.active
                or controls.owner~=nil or controls.pending~=nil or controls.awaiting~=nil)
        if not restored then
            deps.keyboard.restore_owned=nil
            deps.report(tostring(restore_err))
        end
        state.review_restore_error=not restored or deps.keyboard.restore_error
    end
    if not analysis_ok or not state.alive or not (review_window.visible or statistics_popups:any_visible()) then return end
    state:request_preview()
    local ui_ok, err = pcall(function()
        local sw, sh = ReviewWindow.surface_size(imgui)
        if not review_font_attempted then
            review_font_attempted=true
            review_font=imgui.load_font("msyh.ttc",18)
        end
        if review_font then imgui.push_font(review_font) end
        local function handoff()
                state.review_block_until = state.render_tick + 2
                state.review_handoff_requested=true
        end
        local drawn, draw_err = pcall(function()
            if controls.clock and controls.clock.position then review_window.model:update(analysis,controls.clock) end
            review_window:draw(imgui, analysis, controls, navigation, state, control_labels, sw, sh, Vector2f.new, handoff, round_navigation)
            local function can_seek()
                local c=controls.clock
                return c and c.position and state.render_tick-c.render_tick<=2 and review_window.model.matching
                    and analysis.status=="ready" and not analysis.active and not navigation.active and not round_navigation.active
                    and not state.review_handoff_requested
            end
            statistics_popups:draw(imgui,analysis.statistics,sw,sh,Vector2f.new,controls.clock and controls.clock.position,{
                frame=function(round,frame)
                    if can_seek() and analysis:locate_statistics(round,frame) then handoff() end
                end,
                item=function(item)
                    if not item or not can_seek() then return end
                    for _,candidate in ipairs(analysis.review_items or analysis.damage_items or {}) do
                        if candidate.id==item.id and review_window.model:can_locate(analysis,controls,candidate) then
                            if analysis:locate_review(candidate,1,45) then handoff() end
                            return
                        end
                    end
                    if item.round~=controls.clock.position.round then analysis.locate_reason="round_changed" end
                end,
            })
        end)
        if review_font then imgui.pop_font() end
        if not drawn then error(draw_err) end
        if state.review_handoff_requested then
            state.review_handoff_requested=nil
            if not deps.keyboard:hide_overlay() then
                if navigation.active then navigation:cancel() end
                if round_navigation and round_navigation.active then round_navigation:cancel() end
                if analysis.active then analysis:cancel() end
                analysis.locate_reason=deps.keyboard.hide_error or "close_overlay"
            end
        end
    end)
    if not ui_ok then
        review_window.visible = false
        deps.report(err)
    end
end)
