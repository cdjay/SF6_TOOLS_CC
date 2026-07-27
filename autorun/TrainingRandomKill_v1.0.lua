local re = re
local imgui = imgui
local json = json

require("func/SharedHooks")
local RuntimeSafety = require("func/RuntimeSafety")
local GS = require("func/GameState")
local SharedUI = require("func/Training_SharedUI")
local TrainingMenuRegistry = require("func/Training_MenuRegistry")
local SessionRecap = require("func/Training_SessionRecap")
local DynamicRecords = require("func/DynamicRecords")
local Scenario = require("func/RandomKill/Scenario")
local RandomKillRuntime = require("func/RandomKill/Runtime")
local RandomKillStats = require("func/RandomKill/Stats")

local MODE_ID = 5
local RYU_FIGHTER_ID = 1
local CONFIG_PATH = "TrainingRandomKill_data/TrainingRandomKill_Config.json"
local PRESET_PATH = "TrainingRandomKill_data/Ryu_20260727_170833.json"
local IMPORT_OPTIONS = {
    only_import_valid = false,
    clear_empty_slots = true,
    reject_fighter_mismatch = true,
    force_apply_after_import = true,
}

local config = {
    schema_version = 1,
    edge_weight = 80,
    mid_weight = 20,
    low_health_chance = 50,
    show_floating = true,
}

local function load_config()
    local document = _G.safe_load_json and _G.safe_load_json(CONFIG_PATH) or nil
    local source = type(document) == "table" and document.user or nil
    if type(source) == "table" then
        if source.edge_weight ~= nil then
            config.edge_weight = math.max(
                0,
                math.min(100, math.floor(tonumber(source.edge_weight) or 80))
            )
        end
        if source.mid_weight ~= nil then
            config.mid_weight = math.max(
                0,
                math.min(100, math.floor(tonumber(source.mid_weight) or 20))
            )
        end
        if config.edge_weight + config.mid_weight <= 0 then
            config.edge_weight = 80
            config.mid_weight = 20
        end
        if source.low_health_chance ~= nil then
            config.low_health_chance = math.max(
                0,
                math.min(100, math.floor(tonumber(source.low_health_chance) or 50))
            )
        end
        if source.show_floating ~= nil then
            config.show_floating = source.show_floating == true
        end
    end
end

local function save_config()
    pcall(json.dump_file, CONFIG_PATH, {
        schema = "sf6cc.random_kill_config.v1",
        user = config,
    })
end

load_config()

local preset_summary = {
    valid = false,
    error = nil,
    title = "",
    valid_slots = 0,
    active_reversals = 0,
}

local function count_numbered_slots(entries, expected)
    if type(entries) ~= "table" then return 0, false end
    local seen = {}
    local count = 0
    for _, entry in pairs(entries) do
        local slot = type(entry) == "table" and tonumber(entry.slot or entry.index) or nil
        if slot and slot >= 1 and slot <= expected and slot == math.floor(slot)
            and not seen[slot] then
            seen[slot] = true
            count = count + 1
        end
    end
    return count, count == expected
end

local function inspect_preset()
    local loaded, data = pcall(json.load_file, PRESET_PATH)
    if not loaded or type(data) ~= "table" then
        preset_summary.valid = false
        preset_summary.error = "固定预设无法读取"
        return
    end
    if data.schema ~= DynamicRecords.SCHEMA
        or tonumber(data.fighter_id) ~= RYU_FIGHTER_ID
        or data.source_player ~= "P2" then
        preset_summary.valid = false
        preset_summary.error = "固定预设不是P2隆的v2训练配置"
        return
    end
    if type(data.slots) ~= "table"
        or type(data.reversals) ~= "table"
        or type(data.reversals.down) ~= "table"
        or type(data.reversals.guard) ~= "table"
        or type(data.reversals.damage) ~= "table" then
        preset_summary.valid = false
        preset_summary.error = "固定预设缺少录像槽或反击组"
        return
    end

    local valid_slots = 0
    for _, slot in pairs(data.slots) do
        if type(slot) == "table" and slot.is_valid == true then
            valid_slots = valid_slots + 1
        end
    end
    local active_reversals = 0
    for _, group_name in ipairs({ "down", "guard", "damage" }) do
        for _, reversal in pairs(data.reversals[group_name]) do
            if type(reversal) == "table" and reversal.active == true then
                active_reversals = active_reversals + 1
            end
        end
    end
    local record_count, records_complete = count_numbered_slots(data.slots, 8)
    local down_count, down_complete = count_numbered_slots(data.reversals.down, 10)
    local guard_count, guard_complete = count_numbered_slots(data.reversals.guard, 10)
    local damage_count, damage_complete = count_numbered_slots(data.reversals.damage, 10)
    preset_summary.valid = records_complete and down_complete and guard_complete
        and damage_complete
    if preset_summary.valid then
        preset_summary.error = nil
    else
        preset_summary.error = string.format(
            "固定预设槽位数量不完整（录像%d/8，倒地%d/10，格挡%d/10，受伤%d/10）",
            record_count,
            down_count,
            guard_count,
            damage_count
        )
    end
    preset_summary.title = tostring(data.title or "随机斩杀训练")
    preset_summary.valid_slots = valid_slots
    preset_summary.active_reversals = active_reversals
end

inspect_preset()

local session = {
    phase = "idle",
    active = false,
    scenario = nil,
    runtime_backup = nil,
    record_backup_path = nil,
    enter_delay = 0,
    cleanup_delay = 0,
    retry_delay = 0,
    last_mode = _G.CurrentTrainerMode or 0,
    status = "待机",
    status_ok = true,
    rng_seed = (os.time() + math.floor(os.clock() * 1000)) % 2147483647,
    sample_start_hp = nil,
    sample_min_hp = nil,
}

local damage_stats = RandomKillStats.new()

local function ticker(message)
    if _G.show_custom_ticker then
        _G.show_custom_ticker(tostring(message), 0.8)
    end
end

local function set_status(ok, message, show_ticker)
    session.status_ok = ok == true
    session.status = tostring(message or "")
    if show_ticker then ticker(session.status) end
end

local function scenario_config()
    return {
        corner_x = 730,
        distance = 100,
        edge_weight = config.edge_weight,
        mid_weight = config.mid_weight,
        normal_hp_min = 30,
        normal_hp_max = 100,
        low_hp = 20,
        low_health_chance = config.low_health_chance,
        drive_min = 1,
        drive_max = 6,
        super_min = 1,
        super_max = 3,
    }
end

local function scenario_text(scenario)
    if type(scenario) ~= "table" then return "等待生成题目" end
    local hp_text = tostring(scenario.hp_pct) .. "%HP"
    if scenario.is_low_health then hp_text = hp_text .. "(CA)" end
    return table.concat({
        scenario.zone_label,
        scenario.p1_side_label,
        hp_text,
        "斗气" .. tostring(scenario.drive_bars) .. "格",
        "SA" .. tostring(scenario.super_bars) .. "格",
    }, " · ")
end

local function reset_damage_tracking()
    session.sample_start_hp = nil
    session.sample_min_hp = nil
end

local function begin_damage_tracking()
    local ok, vital = pcall(RandomKillRuntime.read_p2_vital)
    if not ok or vital == nil then
        reset_damage_tracking()
        return false
    end
    session.sample_start_hp = vital
    session.sample_min_hp = vital
    return true
end

local function update_damage_tracking()
    if session.phase ~= "ready" or not session.active then return end
    local ok, vital = pcall(RandomKillRuntime.read_p2_vital)
    if not ok or vital == nil then return end
    if session.sample_start_hp == nil then
        session.sample_start_hp = vital
        session.sample_min_hp = vital
        return
    end
    if session.sample_min_hp == nil or vital < session.sample_min_hp then
        session.sample_min_hp = vital
    end
end

local function finalize_damage_sample()
    if session.phase ~= "ready" or type(session.scenario) ~= "table"
        or session.sample_start_hp == nil then
        reset_damage_tracking()
        return false
    end
    update_damage_tracking()
    local minimum = session.sample_min_hp or session.sample_start_hp
    local damage = math.max(0, session.sample_start_hp - minimum)
    RandomKillStats.record(damage_stats, session.scenario, damage)
    reset_damage_tracking()
    return true
end

local function current_p2_is_ryu()
    local ok, context = pcall(DynamicRecords.get_context)
    if not ok then
        return false, { error = tostring(context), fighter_name = "未识别" }
    end
    return tonumber(context and context.fighter_id) == RYU_FIGHTER_ID, context
end

local begin_cleanup

local function import_records(path)
    local called, imported, message, backup_path = pcall(
        DynamicRecords.import_from_file,
        path,
        IMPORT_OPTIONS
    )
    if not called then return false, tostring(imported), nil end
    return imported == true, message, backup_path
end

local function apply_new_scenario(reuse_current)
    if not session.runtime_backup then return false end
    reset_damage_tracking()
    if not reuse_current or type(session.scenario) ~= "table" then
        session.scenario, session.rng_seed = Scenario.generate(scenario_config(), session.rng_seed)
    end
    local called, ok, err = pcall(RandomKillRuntime.apply_scenario, session.scenario)
    if not called or not ok then
        if not called then err = ok end
        set_status(false, "题目应用失败：" .. tostring(err), true)
        begin_cleanup("scenario_apply_failed")
        _G.CurrentTrainerMode = 0
        return false
    end
    session.phase = "applying"
    session.active = true
    set_status(true, "正在生成：" .. scenario_text(session.scenario), false)
    return true
end

local function start_session()
    if session.phase == "cleanup_wait" or session.phase == "runtime_restore" then return false end
    if not preset_summary.valid then
        session.phase = "error"
        set_status(false, preset_summary.error or "固定预设无效", true)
        return false
    end

    local is_ryu = current_p2_is_ryu()
    if not is_ryu then
        local first_notice = session.phase ~= "waiting_ryu"
        session.phase = "waiting_ryu"
        session.retry_delay = 30
        set_status(false, "2P必须选择隆；切换后将自动启动", first_notice)
        return false
    end

    local capture_ok, runtime_backup, runtime_err = pcall(RandomKillRuntime.capture)
    if not capture_ok or not runtime_backup then
        if not capture_ok then runtime_err = runtime_backup end
        session.phase = "waiting_runtime"
        session.retry_delay = 30
        set_status(false, "等待训练状态：" .. tostring(runtime_err), false)
        return false
    end
    session.runtime_backup = runtime_backup

    local import_ok, import_message, backup_path = import_records(PRESET_PATH)
    session.record_backup_path = backup_path
    if not import_ok then
        set_status(false, "隆反击预设导入失败：" .. tostring(import_message), true)
        if backup_path then
            begin_cleanup("preset_import_failed")
            _G.CurrentTrainerMode = 0
        else
            session.runtime_backup = nil
            session.phase = "error"
        end
        return false
    end

    return apply_new_scenario(false)
end

begin_cleanup = function(reason)
    reset_damage_tracking()
    if not session.runtime_backup and not session.record_backup_path then
        session.active = false
        session.scenario = nil
        session.phase = "idle"
        return
    end
    pcall(RandomKillRuntime.cancel_pending)
    session.active = false
    session.phase = "cleanup_wait"
    session.cleanup_delay = 2
    session.cleanup_reason = reason
    set_status(true, "正在恢复进入训练前的设置", false)
end

local function process_cleanup()
    if session.phase ~= "cleanup_wait" then return end
    if session.cleanup_delay > 0 then
        session.cleanup_delay = session.cleanup_delay - 1
        return
    end

    if session.record_backup_path then
        local is_ryu = current_p2_is_ryu()
        if not is_ryu then
            session.cleanup_delay = 60
            set_status(false, "恢复录像设置需要2P为隆，请切回隆", true)
            return
        end
        local restored, message = import_records(session.record_backup_path)
        if not restored then
            session.cleanup_delay = 60
            set_status(false, "录像设置恢复失败，将重试：" .. tostring(message), true)
            return
        end
        session.record_backup_path = nil
    end

    if session.runtime_backup then
        local called, restored, restore_err = pcall(
            RandomKillRuntime.restore,
            session.runtime_backup
        )
        if not called or not restored then
            if not called then restore_err = restored end
            session.cleanup_delay = 30
            set_status(false, "训练状态恢复失败，将重试：" .. tostring(restore_err), false)
            return
        end
        session.phase = "runtime_restore"
        return
    end

    session.phase = "idle"
    session.scenario = nil
    set_status(true, "已恢复进入训练前的设置", true)
end

local function process_runtime()
    if session.phase ~= "applying" and session.phase ~= "runtime_restore" then return end
    local called, result, err = pcall(RandomKillRuntime.update)
    if not called then
        err = result
        result = "error"
    end
    if result == "waiting" or result == "settling" then return end
    if result == "idle" then
        result = "error"
        err = "pending runtime operation disappeared"
    end
    if result == "ready" then
        session.phase = "ready"
        session.active = true
        begin_damage_tracking()
        set_status(true, scenario_text(session.scenario), true)
        return
    end
    if result == "restored" then
        session.runtime_backup = nil
        session.scenario = nil
        session.phase = "idle"
        set_status(true, "已恢复进入训练前的设置", true)
        if (_G.CurrentTrainerMode or 0) == MODE_ID then
            session.phase = "enter_delay"
            session.enter_delay = 2
        end
        return
    end
    set_status(false, "运行时状态处理失败：" .. tostring(err), true)
    if session.phase == "runtime_restore" then
        session.phase = "cleanup_wait"
        session.cleanup_delay = 30
    else
        begin_cleanup("runtime_error")
        _G.CurrentTrainerMode = 0
    end
end

local function stop_session()
    begin_cleanup("user_stop")
    _G.CurrentTrainerMode = 0
end

local function next_scenario()
    if session.active then finalize_damage_sample() end
    return apply_new_scenario(false)
end

local function draw_controls(use_shared_buttons, width)
    local button = function(label, active)
        if use_shared_buttons then
            return SharedUI.sf6_rect_button(label, active, width)
        end
        return imgui.button(label)
    end

    if button("下一题##random_kill_next", false) and session.active then
        next_scenario()
    end
    imgui.same_line()
    if button("重试本题##random_kill_retry", false) and session.active then
        apply_new_scenario(true)
    end
    imgui.same_line()
    if button("停止并恢复##random_kill_stop", true) then
        stop_session()
    end
end

local function draw_floating_controls()
    local visible = SharedUI.begin_floating_window("随机斩杀##float")
    if not visible then
        config.show_floating = false
        save_config()
        SharedUI.end_floating_window()
        return
    end
    SharedUI.draw_floating_bg()
    local size = imgui.get_window_size()
    local description = session.scenario and scenario_text(session.scenario) or session.status
    imgui.text(description)
    imgui.same_line(0, 8)
    draw_controls(true, size.x * 0.105)
    SharedUI.end_floating_window()
end

local function draw_config_panel()
    local is_ryu, context = current_p2_is_ryu()
    imgui.text("固定预设：" .. tostring(preset_summary.title))
    imgui.text("预设内容：有效录像槽 " .. tostring(preset_summary.valid_slots)
        .. "，启用反击 " .. tostring(preset_summary.active_reversals))
    imgui.text_colored(
        "当前2P：" .. tostring(context and context.fighter_name or "未识别"),
        is_ryu and 0xFF88FF88 or 0xFF00A5FF
    )
    if not is_ryu then
        imgui.text_colored("2P必须选择隆；脚本在角色正确前不会修改任何设置。", 0xFF00A5FF)
    end
    if preset_summary.error then
        imgui.text_colored(preset_summary.error, 0xFF0000FF)
    end

    imgui.separator()
    imgui.text("位置：版边与版中按下方权重随机；版边内部左右各半，P1左右等概率。")
    local edge_changed, edge_weight = imgui.drag_int(
        "版边随机权重",
        config.edge_weight,
        1,
        0,
        100
    )
    if edge_changed then
        config.edge_weight = math.max(0, math.min(100, edge_weight))
        if config.edge_weight + config.mid_weight <= 0 then config.edge_weight = 1 end
        save_config()
    end
    local mid_changed, mid_weight = imgui.drag_int(
        "版中随机权重",
        config.mid_weight,
        1,
        0,
        100
    )
    if mid_changed then
        config.mid_weight = math.max(0, math.min(100, mid_weight))
        if config.edge_weight + config.mid_weight <= 0 then config.mid_weight = 1 end
        save_config()
    end
    local position_weight_total = config.edge_weight + config.mid_weight
    local edge_probability = config.edge_weight * 100 / position_weight_total
    imgui.text(string.format(
        "实际概率：版边 %.1f%%（左右各 %.1f%%），版中 %.1f%%。",
        edge_probability,
        edge_probability / 2,
        100 - edge_probability
    ))
    imgui.text("资源：斗气1～6格，SA1～3格，普通血量30%～100%。")
    local chance_changed, chance = imgui.drag_int(
        "SA3时黄血出现概率 (%)",
        config.low_health_chance,
        1,
        0,
        100
    )
    if chance_changed then
        config.low_health_chance = math.max(0, math.min(100, chance))
        save_config()
    end
    imgui.text("黄血题固定为20%体力；只有SA3时参与随机。")
    local floating_changed, floating = imgui.checkbox("显示浮动控制栏", config.show_floating)
    if floating_changed then
        config.show_floating = floating
        save_config()
    end

    imgui.separator()
    imgui.text_colored("状态：" .. session.status, session.status_ok and 0xFF88FF88 or 0xFF00A5FF)
    if session.scenario then imgui.text("当前题：" .. scenario_text(session.scenario)) end
    local stats_summary = RandomKillStats.summary(damage_stats)
    imgui.text(string.format(
        "伤害统计：%d 个样本，%d 种资源组合%s",
        stats_summary.samples,
        stats_summary.groups,
        stats_summary.average_damage
            and string.format("，总平均伤害 %.1f", stats_summary.average_damage)
            or ""
    ))
    if imgui.button("打开伤害统计面板##random_kill_stats") then
        local opened = SessionRecap.show_bars(
            "随机斩杀 - 资源组合平均伤害",
            RandomKillStats.bars(damage_stats),
            {
                x_label = "X轴：资源组合（斗气 / SA·CA）",
                y_label = "Y轴：平均伤害",
            }
        )
        if not opened then ticker("暂无伤害统计；完成一题后点击“下一题”记入样本") end
    end
    imgui.same_line()
    if imgui.button("重置伤害统计##random_kill_stats_reset") then
        RandomKillStats.reset(damage_stats)
        SessionRecap.hide()
        ticker("随机斩杀伤害统计已重置")
    end
    if session.active then draw_controls(false) end
end

TrainingMenuRegistry.register("random_kill_config", draw_config_panel)

re.on_frame(function()
    local mode = _G.CurrentTrainerMode or 0
    if mode ~= session.last_mode then
        if session.last_mode == MODE_ID and mode ~= MODE_ID then
            begin_cleanup("mode_changed")
        elseif mode == MODE_ID then
            if session.phase == "idle" or session.phase == "error"
                or session.phase == "waiting_ryu" or session.phase == "waiting_runtime" then
                session.phase = "enter_delay"
                session.enter_delay = 2
                set_status(true, "正在初始化随机斩杀训练", false)
            end
        end
        session.last_mode = mode
    end

    if not RuntimeSafety.is_training_allowed() then return end
    process_cleanup()
    process_runtime()

    if mode ~= MODE_ID then return end
    if GS.in_pause_menu then return end
    update_damage_tracking()

    if session.phase == "enter_delay" then
        session.enter_delay = session.enter_delay - 1
        if session.enter_delay <= 0 then start_session() end
    elseif session.phase == "waiting_ryu" or session.phase == "waiting_runtime" then
        session.retry_delay = session.retry_delay - 1
        if session.retry_delay <= 0 then start_session() end
    elseif session.active and (GS.frame % 60 == 0) then
        local is_ryu = current_p2_is_ryu()
        if not is_ryu then
            set_status(false, "检测到2P已不是隆，训练已停止", true)
            begin_cleanup("p2_changed")
            _G.CurrentTrainerMode = 0
            return
        end
    end

    if config.show_floating and not _G._tsm_hide_ui then
        draw_floating_controls()
    end
end)

return {
    mode_id = MODE_ID,
    preset_path = PRESET_PATH,
    get_session = function() return session end,
    get_stats_summary = function() return RandomKillStats.summary(damage_stats) end,
    next_scenario = next_scenario,
    retry_scenario = function() return apply_new_scenario(true) end,
    stop = stop_session,
}
