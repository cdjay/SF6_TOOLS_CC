local re = re
local sdk = sdk
local imgui = imgui
local json = json

require("func/SharedHooks")
local RuntimeSafety = require("func/RuntimeSafety")
local GS = require("func/GameState")
local UIKit = require("func/UIKit")
local SharedUI = require("func/Training_SharedUI")
local SessionRecap = require("func/Training_SessionRecap")
local TrainingMenuRegistry = require("func/Training_MenuRegistry")
local TrainingHotkeys = require("func/Training_Hotkeys")
local HitConfirmHotkeys = require("func/HitConfirm_Hotkeys")
local MoveCatalog = require("func/HitConfirm/MoveCatalog")
local CaseCatalog = require("func/HitConfirm/CaseCatalog")
local Engine = require("func/HitConfirm/Engine")
local History = require("func/HitConfirm/History")
local OpponentStrategies = require("func/HitConfirm/OpponentStrategies")
local Sampler = require("func/HitConfirm/Sampler")
local Stats = require("func/HitConfirm/Stats")
local Telemetry = require("func/HitConfirm/Telemetry")

local CONFIG_FILENAME = "TrainingHitConfirm_data/TrainingHitConfirm_Config.json"
local MODE_ID = 2
local COLORS = UIKit.COLORS

local user_config = {
    schema_version = 3,
    move_selections = {},
    session_mode = "trials",
    timer_minutes = 2,
    trial_count = 10,
    show_floating = true,
    show_hit_pct = true,
    show_block_pct = true,
    hud_base_size = 20.24,
    hud_auto_scale = true,
    hud_n_global_y = -0.337,
    hud_n_spacing_y = 0.02800000086426735,
    hud_n_spread_score = 0.09000000357627869,
    hud_n_spread_stats = 0.09000000357627869,
    hud_n_offset_score = 0.0,
    hud_n_offset_total = 0.0,
    hud_n_offset_timer = 0.0,
    hud_n_offset_hit = 0.0,
    hud_n_offset_blk = 0.0,
    hud_n_offset_status_y = 0.0,
    timer_hud_y = -0.46,
    timer_font_size = 80,
    timer_offset_x = 0.0
}

local config_needs_migration = false

local function load_config()
    local document = _G.safe_load_json and _G.safe_load_json(CONFIG_FILENAME) or nil
    config_needs_migration = type(document) ~= "table"
        or document.schema ~= "sf6cc.hit_confirm_config.v3"
        or type(document.user) ~= "table"
        or tonumber(document.user.schema_version) ~= 3
    local source = type(document) == "table" and document.user or nil
    if type(source) == "table" then
        for key in pairs(user_config) do
            if source[key] ~= nil then user_config[key] = source[key] end
        end
    end
    if type(user_config.move_selections) ~= "table" then user_config.move_selections = {} end
    if user_config.session_mode ~= "timer" then user_config.session_mode = "trials" end
    user_config.timer_minutes = math.max(1, math.min(60, tonumber(user_config.timer_minutes) or 2))
    user_config.trial_count = math.max(5, math.min(200, tonumber(user_config.trial_count) or 10))
end

local function save_config()
    json.dump_file(CONFIG_FILENAME, { schema = "sf6cc.hit_confirm_config.v3", user = user_config })
    config_needs_migration = false
end

load_config()

local active_catalog = {
    character = nil,
    moves = {},
    labels = {},
    starter_labels = {},
    followup_labels = {}
}
local active_character_key = nil
local starter_index = nil
local followup_index = nil
local selected_case = CaseCatalog.empty()
local detector = Engine.new(selected_case)
local sampler = Sampler.new(GS)
local telemetry = Telemetry.new()
local current_sample = nil
local last_mode = _G.CurrentTrainerMode or 0

local session = {
    is_running = false,
    is_paused = false,
    is_time_up = false,
    time_up_delay = 0,
    time_rem = user_config.timer_minutes * 60,
    score = 0,
    total = 0,
    hit_ok = 0,
    hit_tot = 0,
    blk_ok = 0,
    blk_tot = 0,
    score_col = COLORS.White,
    score_timer = 0,
    feedback = { text = "等待当前角色出招表", color = COLORS.White, timer = 0 },
    last_clock = os.clock()
}
Stats.reset(session, user_config.timer_minutes * 60)

local function set_feedback(text, color, duration)
    session.feedback.text = text or ""
    session.feedback.color = color or COLORS.White
    session.feedback.timer = tonumber(duration) or 0
end

local function ticker(text)
    if type(_G.show_custom_ticker) == "function" then pcall(_G.show_custom_ticker, text, 0.3) end
end

local function selected_starter()
    return starter_index and active_catalog.moves[starter_index] or nil
end

local function selected_followup()
    return followup_index and active_catalog.moves[followup_index] or nil
end

local function exercise_text()
    local starter = selected_starter()
    local followup = selected_followup()
    if not starter or not followup then return "等待选择前置与后续" end
    return tostring(starter.command) .. " → " .. tostring(followup.command)
end

local function telemetry_context()
    local sample = current_sample or {}
    return {
        control_mode = sample.control_mode or "unknown",
        player_character_id = sample.character_id,
        player_character_key = sample.character_key,
        session_mode = user_config.session_mode,
        target_attempts = user_config.session_mode == "trials" and user_config.trial_count or nil,
        target_seconds = user_config.session_mode == "timer" and (user_config.timer_minutes * 60) or nil
    }
end

local function reset_session(preserve_feedback)
    telemetry:discard_session()
    SessionRecap.hide()
    Stats.reset(session, user_config.timer_minutes * 60)
    detector:reset()
    session.is_running = false
    session.is_paused = false
    session.is_time_up = false
    session.time_up_delay = 0
    session.score_col = COLORS.White
    session.score_timer = 0
    session.last_clock = os.clock()
    if not preserve_feedback then
        set_feedback("准备：" .. exercise_text() .. "；命中后出后续，被防时收手", COLORS.White, 0)
    end
end

local function finish_session(reason, feedback_text, feedback_color)
    local was_running = session.is_running
    local has_results = session.total > 0
    local should_recap = reason == "attempt_target_reached"
        or reason == "time_target_reached"
        or reason == "stopped"
    if telemetry.session and has_results then
        local summary = Stats.summary(session)
        summary.duration_seconds = math.max(0, os.time() - (session.started_at_epoch or os.time()))
        telemetry:finish_session(selected_case, summary, reason, telemetry_context())
    elseif telemetry.session then
        telemetry:discard_session()
    end
    session.is_running = false
    session.is_paused = false
    session.is_time_up = reason == "attempt_target_reached" or reason == "time_target_reached"
    detector:reset()

    if was_running and has_results and should_recap then
        local history_ok, history_error = History.append(session, user_config)
        if history_ok then
            SessionRecap.show("确认训练", History.PATH, "hitconfirm")
        else
            pcall(print, "[HitConfirm.History] append failed: " .. tostring(history_error))
        end
    end
    if feedback_text then set_feedback(feedback_text, feedback_color, 0) end
    if was_running and feedback_text then ticker(feedback_text) end
end

local function rebuild_selected_case()
    local starter = selected_starter()
    local followup = selected_followup()
    if active_catalog.character and starter and followup then
        selected_case = CaseCatalog.build(active_catalog.character, starter, followup)
    else
        selected_case = CaseCatalog.empty()
    end
    detector:set_case(selected_case)
end

local function remember_selection()
    local character = active_catalog.character
    local starter = selected_starter()
    local followup = selected_followup()
    if not character or not starter or not followup then return end
    user_config.move_selections[character.name] = {
        starter_action_id = starter.action_id,
        followup_action_id = followup.action_id
    }
end

local function refresh_character_moves(force)
    local raw_info = _G._shared_player_info and _G._shared_player_info[0] or nil
    local character = MoveCatalog.resolve_character(raw_info)
    local new_key = character and character.key or nil
    if not force and new_key == active_character_key then return true end

    if session.is_running then
        finish_session("character_changed", "角色已变化，确认训练自动停止", COLORS.Red)
    end
    active_character_key = new_key
    if not character then
        active_catalog = {
            character = nil,
            moves = {},
            labels = {},
            starter_labels = {},
            followup_labels = {}
        }
        starter_index, followup_index = nil, nil
        rebuild_selected_case()
        reset_session(true)
        set_feedback("等待识别当前 P1 角色", COLORS.White, 0)
        return false
    end

    local catalog, load_error = MoveCatalog.load(character)
    active_catalog = catalog
    if #catalog.moves == 0 then
        starter_index, followup_index = nil, nil
        rebuild_selected_case()
        reset_session(true)
        set_feedback("未找到 " .. character.display_name .. " 的出招表", COLORS.Red, 0)
        if load_error then pcall(print, "[HitConfirm.MoveCatalog] " .. tostring(load_error)) end
        return false
    end

    local remembered = user_config.move_selections[character.name]
    local starter_id = type(remembered) == "table" and tonumber(remembered.starter_action_id) or nil
    local followup_id = type(remembered) == "table" and tonumber(remembered.followup_action_id) or nil
    starter_index = MoveCatalog.find_index(catalog.moves, starter_id)
        or MoveCatalog.default_starter_index(catalog.moves)
    followup_index = MoveCatalog.find_index(catalog.moves, followup_id)
        or MoveCatalog.default_followup_index(catalog.moves, starter_index)
    rebuild_selected_case()
    remember_selection()
    reset_session(true)
    set_feedback("准备：" .. exercise_text() .. "；命中后出后续，被防时收手", COLORS.White, 0)
    OpponentStrategies.apply(selected_case)
    if config_needs_migration or not remembered then save_config() end
    return true
end

local function select_move(kind, index)
    index = math.max(1, math.min(#active_catalog.moves, tonumber(index) or 1))
    local current = kind == "starter" and starter_index or followup_index
    if index == current then return end
    if session.is_running then finish_session("move_changed", nil, nil) end
    if kind == "starter" then starter_index = index else followup_index = index end
    rebuild_selected_case()
    remember_selection()
    OpponentStrategies.apply(selected_case)
    reset_session(true)
    set_feedback("已选择：" .. exercise_text(), COLORS.Cyan, 1.5)
    save_config()
end

local function sample_matches_case(sample)
    local actual = sample and tonumber(sample.character_id) or nil
    local expected = selected_case.character and tonumber(selected_case.character.id) or nil
    if not actual or actual <= 0 or not expected then return true end
    return actual == expected
end

local function start_training()
    if not refresh_character_moves(false) or not selected_starter() or not selected_followup() then
        set_feedback("当前角色没有可用的出招选择", COLORS.Red, 2.0)
        return false
    end
    current_sample = sampler:read(selected_case)
    if not sample_matches_case(current_sample) then
        refresh_character_moves(true)
        set_feedback("角色信息正在刷新，请重新开始", COLORS.Red, 2.0)
        return false
    end
    reset_session(true)
    OpponentStrategies.apply(selected_case)
    session.is_running = true
    session.last_clock = os.clock()
    telemetry:begin_session(selected_case, telemetry_context())
    set_feedback("开始：观察 " .. tostring(selected_case.starter.command) .. " 是命中还是被防", COLORS.Green, 1.5)
    ticker("确认训练已开始")
    return true
end

local function stop_or_reset()
    if session.is_running then
        finish_session("stopped", "训练已停止", COLORS.Red)
    else
        reset_session()
        set_feedback("训练数据已重置", COLORS.White, 1.0)
        ticker("会话已重置")
    end
end

local function pause_or_start()
    if not session.is_running then
        start_training()
        return
    end
    session.is_paused = not session.is_paused
    session.last_clock = os.clock()
    set_feedback(session.is_paused and "训练已暂停" or "训练已继续", COLORS.Yellow, 1.0)
    ticker(session.is_paused and "训练已暂停" or "训练已继续")
end

local function adjust_training_amount(direction)
    if session.is_running then return end
    if user_config.session_mode == "timer" then
        user_config.timer_minutes = math.max(1, math.min(60, user_config.timer_minutes + direction))
        session.time_rem = user_config.timer_minutes * 60
    else
        user_config.trial_count = math.max(5, math.min(200, user_config.trial_count + direction * 5))
    end
    save_config()
end

HitConfirmHotkeys.init({
    decrease_amount = function() adjust_training_amount(-1) end,
    increase_amount = function() adjust_training_amount(1) end,
    reset_or_stop = stop_or_reset,
    start_or_pause = pause_or_start
}, TrainingHotkeys)

local function feedback_for_result(result)
    local starter = tostring(selected_case.starter.command or "前置")
    local followup = tostring(result.followup_command or (selected_followup() and selected_followup().command) or "后续")
    if result.correct and result.stimulus == "hit" then
        return "命中确认成功：" .. starter .. " → " .. followup, COLORS.Green
    end
    if result.correct and result.stimulus == "block" then
        return "被防后收手：安全", COLORS.Cyan
    end
    if result.failure_code == "blocked_misconfirm" then
        return "误确认：" .. starter .. " 被防后仍出了 " .. followup, COLORS.Red
    end
    if result.failure_code == "followup_did_not_combo" then
        return "确认过晚：" .. followup .. " 没有形成连段", COLORS.Red
    end
    return "漏确认：" .. starter .. " 命中后未接 " .. followup, COLORS.Red
end

local function handle_result(result)
    Stats.record(session, result)
    telemetry:record_attempt(selected_case, result, telemetry_context())
    session.score_col = result.correct and COLORS.Green or COLORS.Red
    session.score_timer = 30
    local text, color = feedback_for_result(result)
    set_feedback(text, color, 1.5)
    if user_config.session_mode == "trials" and session.total >= user_config.trial_count then
        finish_session("attempt_target_reached", "本轮完成", COLORS.Green)
    end
end

local function update_session()
    local now = os.clock()
    local delta = math.max(0, now - (session.last_clock or now))
    session.last_clock = now
    if session.feedback.timer > 0 then
        session.feedback.timer = math.max(0, session.feedback.timer - delta)
        if session.feedback.timer == 0 and session.is_running and not session.is_paused then
            set_feedback("等待 " .. tostring(selected_case.starter.command) .. " 接触", COLORS.White, 0)
        end
    end
    if session.score_timer > 0 then
        session.score_timer = session.score_timer - 1
        if session.score_timer <= 0 then session.score_col = COLORS.White end
    end
    if not session.is_running or session.is_paused then return end

    current_sample = sampler:read(selected_case)
    if not sample_matches_case(current_sample) then
        refresh_character_moves(true)
        return
    end
    if user_config.session_mode == "timer" then
        session.time_rem = math.max(0, session.time_rem - delta)
        if session.time_rem <= 0 then
            finish_session("time_target_reached", "计时完成", COLORS.Green)
            return
        end
    end
    local result = detector:step(current_sample)
    if result then handle_result(result) end
end

local function hit_percentage()
    return Stats.percentage(session.hit_ok, session.hit_tot)
end

local function block_percentage()
    return Stats.percentage(session.blk_ok, session.blk_tot)
end

local function draw_hud()
    local is_trials = user_config.session_mode == "trials"
    local mode_label = "确认训练 · " .. exercise_text()
    SharedUI.draw_standard_hud("HitConfirm_FreeHUD", user_config, session, mode_label, not is_trials,
        function(center_x, y, screen_width, screen_height)
            if is_trials then
                local remaining = math.max(0, user_config.trial_count - session.total)
                local text = tostring(remaining)
                SharedUI.pop_main()
                SharedUI.push_timer()
                local width = imgui.calc_text_size(text).x
                local hud = SharedUI.HUD_CONFIG[_G.CurrentHudSuffix or "Default"] or SharedUI.HUD_CONFIG.Default
                SharedUI.draw_timer(text, center_x - width / 2 + hud.x * screen_width,
                    SharedUI.get_letterbox_offset() + screen_height / 2 + hud.y * screen_height,
                    session.is_time_up and COLORS.Green or COLORS.White)
                SharedUI.pop_timer()
                SharedUI.push_main()
            end
            local spread = (user_config.hud_n_spread_stats or 0.09) * screen_width
            local left = string.format("命中确认 %.0f%% (%d/%d)", hit_percentage(), session.hit_ok, session.hit_tot)
            local right = string.format("被防收手 %.0f%% (%d/%d)", block_percentage(), session.blk_ok, session.blk_tot)
            SharedUI.draw_text(left, center_x - spread - imgui.calc_text_size(left).x, y, COLORS.White)
            SharedUI.draw_text(right, center_x + spread, y, COLORS.White)
        end)
end

local function draw_move_combo(kind, id_suffix, width, prefixed)
    local labels = active_catalog.labels
    if prefixed then
        labels = kind == "starter" and active_catalog.starter_labels or active_catalog.followup_labels
    end
    local index = kind == "starter" and starter_index or followup_index
    if width then imgui.push_item_width(width) end
    if not index or #labels == 0 then
        imgui.combo("##HitConfirmMove" .. kind .. tostring(id_suffix or ""), 1, { "等待当前角色出招表" })
    else
        local changed, new_index = imgui.combo("##HitConfirmMove" .. kind .. tostring(id_suffix or ""), index, labels)
        if changed then select_move(kind, new_index) end
    end
    if width then imgui.pop_item_width() end
end

local function draw_floating_controls()
    local visible, screen_width, screen_height = SharedUI.begin_floating_window("确认训练##float")
    if not visible then
        user_config.show_floating = false
        save_config()
        SharedUI.end_floating_window()
        return
    end
    SharedUI.draw_floating_bg()
    local size = imgui.get_window_size()
    local spacing = 5 * (screen_height / 1080)
    local combo_width = size.x * 0.255
    local button_width = size.x * 0.105

    draw_move_combo("starter", "Float", combo_width, true)
    imgui.same_line(0, spacing)
    draw_move_combo("followup", "Float", combo_width, true)
    imgui.same_line(0, spacing)
    if SharedUI.sf6_button(session.is_running and "停止训练##hc_float" or "开始训练##hc_float",
            session.is_running and SharedUI.SC_COLORS.c3 or SharedUI.SC_COLORS.c4, button_width) then
        if session.is_running then finish_session("stopped", "训练已停止", COLORS.Red) else start_training() end
    end
    imgui.same_line(0, spacing)
    if SharedUI.sf6_button(session.is_paused and "继续##hc_float" or "暂停##hc_float",
            SharedUI.SC_COLORS.c2, button_width) and session.is_running then
        pause_or_start()
    end
    imgui.same_line(0, spacing)
    if SharedUI.sf6_button("重置##hc_float", SharedUI.SC_COLORS.c1, button_width) then
        if session.is_running then finish_session("reset", nil, nil) end
        reset_session()
    end
    imgui.same_line(0, spacing)
    local amount = user_config.session_mode == "timer"
        and (tostring(user_config.timer_minutes) .. " 分钟")
        or (tostring(user_config.trial_count) .. " 次")
    imgui.text(amount)
    SharedUI.end_floating_window()
end

local function draw_training_controls()
    local mode_index = user_config.session_mode == "trials" and 1 or 2
    local mode_changed, new_mode_index = imgui.combo("训练方式", mode_index, { "按次数", "按时间" })
    if mode_changed and not session.is_running then
        user_config.session_mode = new_mode_index == 2 and "timer" or "trials"
        reset_session()
        save_config()
    end
    if user_config.session_mode == "trials" then
        imgui.text("本轮次数：" .. tostring(user_config.trial_count))
    else
        imgui.text("本轮时间：" .. tostring(user_config.timer_minutes) .. " 分钟")
    end
    imgui.same_line()
    if imgui.button("-##hc_amount") then adjust_training_amount(-1) end
    imgui.same_line()
    if imgui.button("+##hc_amount") then adjust_training_amount(1) end

    if not session.is_running then
        if imgui.button("开始训练##hc_config") then start_training() end
    else
        if imgui.button("停止训练##hc_config") then finish_session("stopped", "训练已停止", COLORS.Red) end
        imgui.same_line()
        if imgui.button((session.is_paused and "继续" or "暂停") .. "##hc_config") then pause_or_start() end
    end
    imgui.same_line()
    if imgui.button("重置统计##hc_config") then
        if session.is_running then finish_session("reset", nil, nil) end
        reset_session()
    end
end

local function draw_hit_confirm_config()
    if UIKit.plain_header("--- 出招选择 ---") then
        local character_name = active_catalog.character and active_catalog.character.display_name or "等待识别"
        imgui.text("当前 P1：" .. tostring(character_name) .. "（经典与现代共用完整出招表）")
        imgui.text("前置")
        draw_move_combo("starter", "Config", -1, false)
        imgui.text("命中后的后续")
        draw_move_combo("followup", "Config", -1, false)
        local followup = selected_followup()
        if followup and followup.is_derived then
            imgui.text_colored("当前后续为派生动作，按独立 Action ID 识别。", COLORS.Cyan)
        end
        imgui.text("规则：命中时接后续；被防时不出后续。")
        imgui.text("2P 行为：" .. OpponentStrategies.describe(selected_case))
    end

    imgui.separator()
    if UIKit.plain_header("--- 训练配置 ---") then
        local floating_changed, floating = imgui.checkbox("显示浮动控制栏", user_config.show_floating)
        if floating_changed then user_config.show_floating = floating; save_config() end
        if not user_config.show_floating then draw_training_controls() end
    end

    imgui.separator()
    if UIKit.plain_header("--- 本轮统计 ---") then
        local summary = Stats.summary(session)
        imgui.text(string.format("总正确率：%.1f%%（%d / %d）", summary.accuracy_pct, summary.correct, summary.attempts))
        imgui.text(string.format("命中确认：%.1f%%（%d / %d）", summary.hit.accuracy_pct,
            summary.hit.correct, summary.hit.attempts))
        imgui.text(string.format("被防收手：%.1f%%（%d / %d）", summary.block.accuracy_pct,
            summary.block.correct, summary.block.attempts))
        imgui.text(string.format("误确认：%d　漏确认：%d　后续未连段：%d",
            summary.errors.blocked_misconfirm, summary.errors.missed_confirm,
            summary.errors.followup_did_not_combo))
        imgui.text(string.format("所选后续成功使用：%d 次", summary.followups.selected or 0))
        if summary.reaction_frames.average then
            imgui.text(string.format("命中确认平均反应：%.1f 帧（最快 %d / 最慢 %d）",
                summary.reaction_frames.average, summary.reaction_frames.minimum,
                summary.reaction_frames.maximum))
        else
            imgui.text_colored("命中确认平均反应：暂无样本", COLORS.DarkGrey)
        end
        if imgui.button("查看最近成功率曲线##hc_recap") then
            SessionRecap.show("确认训练", History.PATH, "hitconfirm")
        end
    end
end

TrainingMenuRegistry.register("confirm_config", draw_hit_confirm_config)

local function process_web_command()
    local command = _G._tsm_web_cmd
    if not command then return end
    _G._tsm_web_cmd = nil
    if command == "start" then start_training()
    elseif command == "stop" then finish_session("stopped", "训练已停止", COLORS.Red)
    elseif command == "reset" then reset_session()
    elseif command == "pause" and session.is_running then pause_or_start()
    elseif command == "timer_up" or command == "trials_up" then adjust_training_amount(1)
    elseif command == "timer_down" or command == "trials_down" then adjust_training_amount(-1)
    elseif command == "switch_mode" and not session.is_running then
        user_config.session_mode = user_config.session_mode == "timer" and "trials" or "timer"
        reset_session()
        save_config()
    end
end

re.on_frame(function()
    if not RuntimeSafety.is_training_allowed() then return end
    local mode = _G.CurrentTrainerMode or 0
    if mode ~= last_mode then
        if last_mode == MODE_ID and session.is_running then finish_session("mode_changed", nil, nil) end
        if mode == MODE_ID then
            refresh_character_moves(true)
            OpponentStrategies.apply(selected_case)
            session.last_clock = os.clock()
        end
        last_mode = mode
    end
    if mode ~= MODE_ID then return end

    local manager = sdk.get_managed_singleton("app.training.TrainingManager")
    if not manager then return end
    refresh_character_moves(false)
    process_web_command()

    _G.TrainingSession_IsRunning = session.is_running
    _G.TrainingSession_IsPaused = session.is_paused
    _G.TrainingSession_Timer = user_config.timer_minutes
    _G.TrainingSession_Trials = user_config.trial_count
    _G.TrainingSession_Mode = user_config.session_mode
    _G.TrainingSession_CaseId = selected_case.id

    if GS.in_pause_menu then
        if session.is_running and not session.is_paused then
            session.is_paused = true
            session._auto_paused = true
            session.last_clock = os.clock()
        end
        return
    end
    if session._auto_paused then
        session._auto_paused = false
        session.is_paused = false
        session.last_clock = os.clock()
    end

    update_session()
    draw_hud()
    if user_config.show_floating and not _G._tsm_hide_ui then draw_floating_controls() end
end)

return {
    get_case = function() return selected_case end,
    get_session = function() return session end,
    get_detector = function() return detector end,
    get_move_catalog = function() return active_catalog end
}
