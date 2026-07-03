-- Training_ScriptManager.lua
-- v4.0 : Top floating bar + new cycling order

local re = re
local sdk = sdk
local imgui = imgui
local json = json
require("func/SharedHooks") -- error registry (_G.safe_load_json) + shared hooks
local RuntimeSafety = require("func/RuntimeSafety")
local GS = require("func/GameState")
local UIKit = require("func/UIKit")
local TrainingHotkeys = require("func/Training_Hotkeys")

-- ==========================================
-- CUSTOM TICKER SYSTEM
-- ==========================================
local _ticker = { mReq = nil, message = {}, queue = {} }
local TICKER_QUEUE_MAX = 20
local function _ticker_is_ready()
    local mgr = sdk.get_managed_singleton("app.bFlowManager")
    return mgr and mgr:get_MainFlowID() ~= 1
end
local function _ticker_init_req()
    if _ticker.mReq then return sdk.PreHookResult.CALL_ORIGINAL end
    _ticker.mReq = sdk.create_instance("app.TickerRequestData", true)
    _ticker.mReq:Init(112, nil)
    _ticker.mReq.TickerId = 1
end
local function show_custom_ticker(message, time, category)
    if category == nil then category = 6 end
    if time == nil or time <= 0 then time = 3.5 end
    if not _ticker_is_ready() then
        if #_ticker.queue >= TICKER_QUEUE_MAX then table.remove(_ticker.queue, 1) end
        _ticker.queue[#_ticker.queue + 1] = {message, time, category}
        return
    end
    sdk.find_type_definition("app.TickerUtil"):get_method(".cctor"):call(nil)
    if _ticker.mReq then
        _ticker.message[_ticker.mReq.RequestId.mData4L] = message
        _ticker.mReq.Category = category
        _ticker.mReq.DisplaySecond = time
        local manager = sdk.find_type_definition("app.helper.hTicker"):get_method("get_Manager"):call(nil)
        if manager then manager:call("RequestShowTicker(app.TickerRequestData)", _ticker.mReq) end
        _ticker.mReq = nil
    end
end
_G.show_custom_ticker = show_custom_ticker

sdk.hook(sdk.find_type_definition("app.TickerUtil"):get_method(".cctor"), _ticker_init_req)
sdk.hook(sdk.find_type_definition("app.TickerRequestData"):get_method("GetMessage"), function(args)
    local storage = thread.get_hook_storage()
    storage["message"] = nil

    local req = sdk.to_managed_object(args[2])
    local req_id = req and req.RequestId and req.RequestId.mData4L
    local v = req_id and _ticker.message[req_id]
    if v ~= nil then
        _ticker.message[req_id] = nil
        if type(v) == "function" then
            storage["message"] = v()
        else
            storage["message"] = v
        end
        return sdk.PreHookResult.SKIP_ORIGINAL
    end
end, function(retval)
    local m = thread.get_hook_storage()["message"]
    if m then return sdk.to_ptr(sdk.create_managed_string(m)) end
    return retval
end)
sdk.hook(sdk.find_type_definition("app.bBootFlow"):get_method("UpdatePhaseTransition"), function()
    if #_ticker.queue > 0 then
        for _, v in ipairs(_ticker.queue) do show_custom_ticker(table.unpack(v)) end
        _ticker.queue = {}
    end
end)

-- ==========================================
-- CONFIGURATION & SAVING
-- ==========================================
local CONFIG_FILE = "Training_ScriptManager_data/TrainingManager_Config.json"

local config = {
    btn_colors = { c1 = 0xFFFF0000, c2 = 0xFF019D00, c3 = 0xFF0000FF, c4 = 0xFFDC00FF },
    btn_alphas = { c1 = 200, c2 = 200, c3 = 200, c4 = 200 },
    -- Top bar colors (ARGB)
    top_colors = { switch = 0xFF0066FF, active = 0xFF019D00, inactive = 0xFF666666 },
    top_alphas = { switch = 170, active = 170, inactive = 120 },
    hide_btn = { x_pct = 0.4625, y_pct = 0.05, w_pct = 0.075, h_pct = 0.075 },
    distance_viewer_enabled = false,
    sheldons_boxes_enabled = false,
}

-- ARGB -> ABGR conversion
local argb_to_abgr = UIKit.argb_to_abgr

-- Build SC_COLORS style table from ARGB color + fill alpha
local function build_sc_color(argb, fill_alpha)
    local abgr = argb_to_abgr(argb)
    local rgb = abgr & 0x00FFFFFF
    return {
        text   = abgr,
        base   = (0xFF << 24) | rgb,
        hover  = (0xFF << 24) | rgb,
        active = (0xFF << 24) | rgb,
        border = 0xFFFFFFFF,
    }
end

local function publish_button_colors()
    _G.TrainingSCColors = {
        c1 = build_sc_color(config.btn_colors.c1, config.btn_alphas.c1),
        c2 = build_sc_color(config.btn_colors.c2, config.btn_alphas.c2),
        c3 = build_sc_color(config.btn_colors.c3, config.btn_alphas.c3),
        c4 = build_sc_color(config.btn_colors.c4, config.btn_alphas.c4),
    }
end

local function publish_passive_plugin_flags()
    _G.SF6_DistanceViewer_Enabled = config.distance_viewer_enabled == true
    _G.SheldonsBoxes_Enabled = config.sheldons_boxes_enabled == true
end

-- Load config
local function load_config()
    local data = _G.safe_load_json(CONFIG_FILE)
    if data then
        if data.btn_colors and type(data.btn_colors) == "table" then
            for k, v in pairs(data.btn_colors) do config.btn_colors[k] = v end
        end
        if data.btn_alphas and type(data.btn_alphas) == "table" then
            for k, v in pairs(data.btn_alphas) do config.btn_alphas[k] = v end
        end
        if data.top_colors and type(data.top_colors) == "table" then
            for k, v in pairs(data.top_colors) do config.top_colors[k] = v end
        end
        if data.top_alphas and type(data.top_alphas) == "table" then
            for k, v in pairs(data.top_alphas) do config.top_alphas[k] = v end
        end
        if data.distance_viewer_enabled ~= nil then config.distance_viewer_enabled = data.distance_viewer_enabled == true end
        if data.sheldons_boxes_enabled ~= nil then config.sheldons_boxes_enabled = data.sheldons_boxes_enabled == true end
    end
    publish_button_colors()
    publish_passive_plugin_flags()
end

local function save_config()
    json.dump_file(CONFIG_FILE, config)
    publish_button_colors()
    publish_passive_plugin_flags()
end

load_config()
_G.TrainingFuncButton = nil
_G.TrainingFuncHeld = false

local _tsm_hide_ref_menu_frames = 90
local function _tsm_force_hide_reframework_menu()
    if _tsm_hide_ref_menu_frames <= 0 then return end
    _tsm_hide_ref_menu_frames = _tsm_hide_ref_menu_frames - 1

    pcall(function()
        if reframework and reframework.set_draw_ui then
            reframework:set_draw_ui(false)
        end
    end)
    pcall(function()
        if reframework and reframework.draw_ui then
            reframework:draw_ui(false)
        end
    end)
    pcall(function()
        if reframework and reframework.set_menu_open then
            reframework:set_menu_open(false)
        end
    end)
end

-- ==========================================
-- 0.5. SCENE DETECTION (ABSOLUTE KILLSWITCH)
-- ==========================================
local TRAINING_MODE_CACHE_FRAMES = 60
local training_mode_cache = {
    value = false,
    frame = -TRAINING_MODE_CACHE_FRAMES,
    flow_id = nil,
    is_replay = false,
    is_battle_hub = false,
}

local function _tsm_frame_id()
    return (GS and GS.frame) or 0
end

local function _tsm_set_training_mode_cache(value, frame, flow_id, is_replay, is_battle_hub)
    training_mode_cache.value = value == true
    training_mode_cache.frame = frame or _tsm_frame_id()
    training_mode_cache.flow_id = flow_id
    training_mode_cache.is_replay = is_replay == true
    training_mode_cache.is_battle_hub = is_battle_hub == true
end

local function _tsm_invalidate_training_mode_cache()
    training_mode_cache.frame = -TRAINING_MODE_CACHE_FRAMES
end

local function _tsm_query_training_mode()
    local tm = sdk and sdk.get_managed_singleton and sdk.get_managed_singleton("app.training.TrainingManager")
    if not tm then return false end
    local tData = tm:get_field("_tData")
    return tData ~= nil
end

local function is_in_training_mode(flow_id, is_replay, is_battle_hub)
    local frame = _tsm_frame_id()
    local fid = flow_id
    if fid == nil then fid = _G.FlowMapID end

    local replay = (is_replay == true) or (_G.IsInReplay == true) or (fid == 10)
    local battle_hub = (is_battle_hub == true) or (_G.IsInBattleHub == true) or (fid == 9)
    if replay or battle_hub then
        _tsm_set_training_mode_cache(false, frame, fid, replay, battle_hub)
        return false
    end

    local context_changed =
        training_mode_cache.flow_id ~= fid or
        training_mode_cache.is_replay ~= replay or
        training_mode_cache.is_battle_hub ~= battle_hub

    if not context_changed and (frame - training_mode_cache.frame) < TRAINING_MODE_CACHE_FRAMES then
        return training_mode_cache.value
    end

    local ok, result = pcall(_tsm_query_training_mode)
    result = ok and result == true
    _tsm_set_training_mode_cache(result, frame, fid, replay, battle_hub)
    return result
end

-- ==========================================
-- 0.1 GUARD CONTROL UTILITIES (SAFE PATTERN)
-- ==========================================
local last_mode_state = 0
local saved_guard_state = 0 -- Default 0, stores the previous state
local is_guard_overridden = false

-- Guard IDs
local GUARD_NO = 0
local GUARD_AFTER_FIRST_HIT = 2
local GUARD_ALL = 3
local GUARD_RANDOM = 4

-- Safety function to avoid crashes
local function call_fresh(target_type, method, ...)
    local mgr = sdk.get_managed_singleton("app.training.TrainingManager")
    if not mgr then return false end
    
    local obj = nil
    if target_type == "TM" then 
        obj = mgr 
    elseif target_type == "Guard" then 
        local ok, guard = pcall(function() return mgr:call("get_GuardFunc") end)
        if ok and guard then obj = guard end
    end

    if not obj or sdk.to_int64(obj) == 0 then return false end
    
    local args = {...}
    return pcall(function() return obj:call(method, table.unpack(args)) end)
end

-- Apply guard type cleanly
local function set_guard_type(guard_id)
    -- 1. Apply the guard type to the Dummy (ID 1)
    call_fresh("Guard", "ChangeGuardType", 1, guard_id)
    -- 2. Force refresh
    call_fresh("TM", "set_IsReqRefresh", true)
end

local function update_guard_logic()
    local current_mode = _G.CurrentTrainerMode or 0
    
    -- If mode hasn't changed, do nothing
    if current_mode == last_mode_state then return end

    -- CHANGE LOGIC

    -- When switching from inactive (0) to active mode (1, 2, 3), save the guard state
    -- (Note: Without a reliable get_GuardType, we assume the user starts in No Guard or wants to return to it)
    if last_mode_state == 0 and current_mode ~= 0 then
        if not is_guard_overridden then
            saved_guard_state = 0 -- Will revert to 0 by default
            is_guard_overridden = true
        end
    end

    if current_mode == 1 then
        -- >>> REACTION DRILLS >>> NO GUARD (0)
        set_guard_type(GUARD_NO)

    elseif current_mode == 2 then
        -- >>> HIT CONFIRM >>> RANDOM GUARD (4)
        set_guard_type(GUARD_RANDOM)

    elseif current_mode == 3 then
        -- >>> POST GUARD >>> ALL GUARD (3)
        set_guard_type(GUARD_ALL)

    elseif current_mode == 4 then
        -- >>> COMBO TRIALS >>> use the guard type selected by the active trial
        local combo_guard_type = tonumber(_G.CT_COMBO_TRIALS_DUMMY_GUARD_TYPE)
        if combo_guard_type == nil or combo_guard_type < 0 or combo_guard_type > 4 then
            combo_guard_type = GUARD_AFTER_FIRST_HIT
        end
        set_guard_type(combo_guard_type)


    elseif current_mode == 0 then
        -- >>> DISABLED / COMBO TRIALS >>> RESTORE
        if is_guard_overridden then
            set_guard_type(saved_guard_state) -- Revert to 0 (or saved state)
            is_guard_overridden = false
        end
    end

    last_mode_state = current_mode
end

-- ==========================================
-- 1. MODE MANAGEMENT (TRAINER MANAGER)
-- ==========================================
if _G.CurrentTrainerMode == nil then
    _G.CurrentTrainerMode = 0
end

local _tsm_last_mode = _G.CurrentTrainerMode
local TSM_MODE_NAMES = {
    [0] = "已关闭",
    [2] = "确认训练",
    [4] = "连段训练",
}

local ENABLED_TRAINER_MODES = { [0] = true, [2] = true, [4] = true }
local function is_enabled_trainer_mode(mode)
    return ENABLED_TRAINER_MODES[mode or 0] == true
end

-- Cycling order: DISABLED → HIT CONFIRM → CUSTOM COMBO TRIALS → DISABLED
local MODE_CYCLE = { 0, 2, 4 }
local MODE_CYCLE_INDEX = {} -- reverse lookup: mode_id → position in cycle
for i, m in ipairs(MODE_CYCLE) do MODE_CYCLE_INDEX[m] = i end

local function cycle_next_mode()
    local cur = _G.CurrentTrainerMode or 0
    local idx = MODE_CYCLE_INDEX[cur] or 1
    idx = idx + 1
    if idx > #MODE_CYCLE then idx = 1 end
    _G.CurrentTrainerMode = MODE_CYCLE[idx]
end

local function toggle_global_ui_visibility()
    _G._tsm_hide_ui = not _G._tsm_hide_ui
    _G._tsm_hide_flash = 10
    _G._tsm_hide_cooldown = 3
    if _G.show_custom_ticker then
        _G.show_custom_ticker(_G._tsm_hide_ui and "UI 已隐藏" or "UI 已显示", 0.3)
    end
end

TrainingHotkeys.register_scope("script_manager", {
    title = "脚本总台",
    order = 0,
    enabled_default = false,
    actions = {
        {
            id = "cycle_mode",
            label = "循环切换训练模式",
            enabled = function() return RuntimeSafety.is_training_allowed() end,
            run = cycle_next_mode,
        },
        {
            id = "toggle_ui",
            label = "隐藏 / 显示训练 UI",
            enabled = function() return RuntimeSafety.is_training_allowed() end,
            run = toggle_global_ui_visibility,
        },
    },
})

-- ==========================================
-- 2. UI RESTORATION & HUD TRACKING LOGIC
-- ==========================================
_G.CurrentHudSuffix = "Default"

local function apply_infinite_visibility(control, should_hide)
    if not control then return end
    local name = control:call("get_Name")
    if name and string.match(name:lower(), "infinite") then
        -- We only force it invisible when needed. 
        -- We do NOT force it visible, letting the native game logic handle the ticking timer.
        control:call("set_ForceInvisible", should_hide)
    end
    local child = control:call("get_Child")
    while child do
        apply_infinite_visibility(child, should_hide)
        child = child:call("get_Next")
    end
end

local function safe_call(obj, method, arg)
    if not obj then return end
    pcall(obj.call, obj, method, arg)
end

local TSM_UI_VISIBILITY_REFRESH_FRAMES = 60
local _tsm_ui_visibility_last_active = nil
local _tsm_ui_visibility_refresh_wait = 0

local function _tsm_apply_widget_visibility(entries, scripts_active)
    local count = entries:call("get_Count")
    for i = 0, count - 1 do
        local entry = entries:call("get_Item", i)
        if entry then
            local widget_list = entry:get_field("value")
            if widget_list then
                local w_count = widget_list:call("get_Count")
                for j = 0, w_count - 1 do
                    local widget = widget_list:call("get_Item", j)
                    if widget then
                        local type_def = widget:get_type_definition()
                        if type_def then
                            local full_name = type_def:get_full_name()
                            if string.find(full_name, "TMAttackInfo") then
                                local attack_infos = widget:get_field("AttackInfos")
                                if attack_infos then
                                    local len = attack_infos:call("get_Length")
                                    for k = 0, len - 1 do
                                        local line = attack_infos:call("GetValue", k)
                                        if line then
                                            local left = line:get_field("LeftText")
                                            local center = line:get_field("CenterText")
                                            local right = line:get_field("RightText")
                                            if left then safe_call(left, "set_Visible", not scripts_active) end
                                            if center then safe_call(center, "set_Visible", not scripts_active) end
                                            if right then safe_call(right, "set_Visible", not scripts_active) end
                                        end
                                    end
                                end
                            end
                            if string.find(full_name, "UIWidget_TMTicker") then
                                if not scripts_active then
                                    safe_call(widget, "set_Visible", true)
                                    safe_call(widget, "set_ForceInvisible", false)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

local function manage_ui_visibility(scripts_active)
    if _tsm_ui_visibility_last_active == scripts_active and _tsm_ui_visibility_refresh_wait > 0 then
        _tsm_ui_visibility_refresh_wait = _tsm_ui_visibility_refresh_wait - 1
        return
    end

    _tsm_ui_visibility_last_active = scripts_active
    _tsm_ui_visibility_refresh_wait = TSM_UI_VISIBILITY_REFRESH_FRAMES

    local mgr = sdk.get_managed_singleton("app.training.TrainingManager")
    if mgr then
        local dict = mgr:get_field("_ViewUIWigetDict")
        local entries = dict and dict:get_field("_entries")

        if entries then
            pcall(_tsm_apply_widget_visibility, entries, scripts_active)
        end
    end
end

-- ==========================================
-- 3. DRAW HOOK (MASTER HUD TRACKER)
-- ==========================================
re.on_pre_gui_draw_element(function(element, context)
    if not is_in_training_mode() then return true end

    local game_object = element:call("get_GameObject")
    if not game_object then return true end
    
    local name = game_object:call("get_Name")
    
    -- GLOBAL FUZZY HUD DETECTION
    if name and string.find(name, "BattleHud_Timer") then
        -- 1. Extract suffix for ALL other scripts
        local suffix = string.match(name, "BattleHud_Timer(.*)")
        if suffix == "" or suffix == nil then suffix = "Default" end
        _G.CurrentHudSuffix = suffix
        
        -- 2. Manage infinite symbol visibility (Never hidden in mode 4)
        local hide_infinite = (_G.CurrentTrainerMode == 2)
        
        local view = element:call("get_View")
        apply_infinite_visibility(view, hide_infinite)
    end

    return true
end)

-- ==========================================
-- 3.5 TOP FLOATING BAR (mode switcher)
-- ==========================================
local SharedUI = require("func/Training_SharedUI")

-- Top bar button colors (rebuilt from config)
local SWITCH_COLOR  = build_sc_color(config.top_colors.switch, config.top_alphas.switch)
local MODE_ACTIVE   = build_sc_color(config.top_colors.active, config.top_alphas.active)
local MODE_INACTIVE = build_sc_color(config.top_colors.inactive, config.top_alphas.inactive)

local top_bar_width = 1.0
local top_bar_height = 0.0444

local MODE_BUTTONS = {
    { id = 0, label = "关闭训练" },
    { id = 2, label = "确认训练" },
    { id = 4, label = "连段训练" },
}

local function draw_top_floating_bar()
    local visible, sw, sh = SharedUI.begin_floating_window_top("TrainingModeSwitch##top", top_bar_width, top_bar_height)
    if not visible then
        SharedUI.end_floating_window_top(); return
    end
    SharedUI.draw_floating_bg_top()

    local scale = sh / 1080.0
    local sp = 4 * scale

    local train_count = 1 + #MODE_BUTTONS
    local train_x = sw * 0.125
    local train_group_w = sw * 0.345
    local btn_w = (train_group_w - sp * (train_count - 1)) / train_count
    if btn_w < 145 * scale then btn_w = 145 * scale end

    local passive_w = math.max(112 * scale, sw * 0.06)
    local feature_start_x = sw * 0.665
    local top_y = sh * 0.01

    imgui.set_cursor_pos(Vector2f.new(train_x, top_y))
    if SharedUI.sf6_button("切换训练模式##sw_top", SWITCH_COLOR, btn_w) then
        cycle_next_mode()
    end

    for _, btn in ipairs(MODE_BUTTONS) do
        imgui.same_line(0, sp)
        local is_active = (_G.CurrentTrainerMode == btn.id)
        local colors = is_active and MODE_ACTIVE or MODE_INACTIVE
        if SharedUI.sf6_button(btn.label .. "##top_" .. btn.id, colors, btn_w) then
            _G.CurrentTrainerMode = btn.id
        end
    end

    imgui.set_cursor_pos(Vector2f.new(feature_start_x, top_y))
    local dv_colors = (config.distance_viewer_enabled == true) and MODE_ACTIVE or MODE_INACTIVE
    if SharedUI.sf6_button("距离显示##top_distance_viewer", dv_colors, passive_w) then
        config.distance_viewer_enabled = not config.distance_viewer_enabled
        save_config()
        if _G.show_custom_ticker then _G.show_custom_ticker(config.distance_viewer_enabled and "距离显示已开启" or "距离显示已关闭", 0.3) end
    end

    imgui.same_line(0, sp)
    local sb_colors = (config.sheldons_boxes_enabled == true) and MODE_ACTIVE or MODE_INACTIVE
    if SharedUI.sf6_button("碰撞显示##top_sheldons_boxes", sb_colors, passive_w) then
        config.sheldons_boxes_enabled = not config.sheldons_boxes_enabled
        save_config()
        if _G.show_custom_ticker then _G.show_custom_ticker(config.sheldons_boxes_enabled and "碰撞显示已开启" or "碰撞显示已关闭", 0.3) end
    end

    SharedUI.end_floating_window_top()
end

-- ==========================================
-- 4. MAIN LOOP
-- ==========================================
local _tsm_replay_delay = 3.00  -- seconds before reactivating the script after a replay
local _tsm_replay_timer = 0
local _tsm_was_replay = false

local function _tsm_read_flowmap_id()
    local bfm = sdk.get_managed_singleton("app.bFlowManager")
    if not bfm then return nil end
    local work = bfm:get_field("m_flow_work")
    if work and work._FlowMap then return work._FlowMap._ID end
    return nil
end

local function get_flowmap_id()
    local ok, id = pcall(_tsm_read_flowmap_id)
    return ok and id or nil
end

-- ==========================================
-- REPLAY DETECTION HOOKS
-- ==========================================
pcall(function()
    local t_emote = sdk.find_type_definition("app.esports.bBattleFighterEmoteFlow")
    if t_emote then
        local m_setup = t_emote:get_method("setup")
        if m_setup then
            sdk.hook(m_setup, function(args)
                local obj = sdk.to_managed_object(args[2])
                if obj and obj.mInputType == 3 then
                    _G.IsInReplay = true
                end
            end, function(r) return r end)
        end
    end
    local t_flow = sdk.find_type_definition("app.battle.bBattleFlow")
    if t_flow then
        local m_end = t_flow:get_method("endReplay")
        if m_end then
            sdk.hook(m_end, function(args)
                _G.IsInReplay = false
            end, function(r) return r end)
        end
    end
end)

-- Hoisted to file scope to avoid per-frame closure allocations (hot path)
local function _tsm_update_hide_rect()
    local sw, sh = SharedUI.get_screen_size()
    local lb_off = SharedUI.get_letterbox_offset()
    local hb = config.hide_btn
    _G._tsm_hide_rect.x = sw * hb.x_pct
    _G._tsm_hide_rect.y = lb_off + (sh - lb_off * 2) * hb.y_pct
    _G._tsm_hide_rect.w = sw * hb.w_pct
    _G._tsm_hide_rect.h = (sh - lb_off * 2) * hb.h_pct
end

local _TSM_WEBSTATE_INACTIVE = { sf6_running = true, training_active = false, mode = 0 }
local TSM_WEBBRIDGE_FILE = "SF6_TrainingRemoteControl_data/TSM_WebBridge.json"
local TSM_INACTIVE_WEBSTATE_REFRESH_FRAMES = 300
local _tsm_inactive_webstate_reason = nil
local _tsm_inactive_webstate_wait = 0

local function _tsm_load_web_bridge()
    local ok_open, f = pcall(io.open, TSM_WEBBRIDGE_FILE, "r")
    if not ok_open or not f then return nil end

    local raw = f:read("*a") or ""
    f:close()

    local trimmed = raw:match("^%s*(.-)%s*$") or ""
    if trimmed == "" then return nil end
    if trimmed:sub(1, 1) ~= "{" then return nil end
    if not trimmed:match("}%s*$") then return nil end

    local ok_load, data = pcall(json.load_file, TSM_WEBBRIDGE_FILE)
    if ok_load and type(data) == "table" then return data end
    return nil
end

local function _tsm_dump_web_bridge(data)
    return json.dump_file(TSM_WEBBRIDGE_FILE, data)
end

local function _tsm_dump_webstate_inactive(reason)
    reason = reason or "inactive"
    if _tsm_inactive_webstate_reason == reason and _tsm_inactive_webstate_wait > 0 then
        _tsm_inactive_webstate_wait = _tsm_inactive_webstate_wait - 1
        return
    end

    json.dump_file("SF6_TrainingRemoteControl_data/TSM_WebState.json", _TSM_WEBSTATE_INACTIVE)
    _tsm_inactive_webstate_reason = reason
    _tsm_inactive_webstate_wait = TSM_INACTIVE_WEBSTATE_REFRESH_FRAMES
end

local function _tsm_mark_webstate_active()
    _tsm_inactive_webstate_reason = nil
    _tsm_inactive_webstate_wait = 0
end

local function _tsm_web_bridge_tick()
    _tsm_mark_webstate_active()
    json.dump_file("SF6_TrainingRemoteControl_data/TSM_WebState.json", {
        mode = _G.CurrentTrainerMode or 0,
        trial_file = _G.ComboTrials_CurrentFile or "",
        trial_step = _G.ComboTrials_CurrentStep or 0,
        trial_total = _G.ComboTrials_TotalSteps or 0,
        trial_playing = _G.ComboTrials_IsPlaying or false,
        trial_recording = _G.ComboTrials_IsRecording or false,
        trial_demo = _G.ComboTrials_IsDemo or false,
        trial_files = _G.ComboTrials_FileList or {},
        trial_file_idx = _G.ComboTrials_FileIdx or 1,
        trial_position = _G.ComboTrials_PositionIdx or 1,
        is_running = _G.TrainingSession_IsRunning or false,
        is_paused = _G.TrainingSession_IsPaused or false,
        timer = _G.TrainingSession_Timer or 0,
        trials = _G.TrainingSession_Trials or 0,
        session_mode = _G.TrainingSession_Mode or 2,
        hide_ui = _G._tsm_hide_ui or false,
        sf6_running = true,
        training_active = _G.TrainingModeActive or false,
    })
    local b = _tsm_load_web_bridge()
    if b and b._web_timestamp and (not _G._tsm_bridge_ts or b._web_timestamp > _G._tsm_bridge_ts) then
        _G._tsm_bridge_ts = b._web_timestamp
        if not _G.TrainingModeActive then
            b.cmd = nil
            _tsm_dump_web_bridge(b)
        end
        if _G.TrainingModeActive and b.mode ~= nil and is_enabled_trainer_mode(b.mode) then _G.CurrentTrainerMode = b.mode end
        if _G.TrainingModeActive and b.cmd then
            if b.cmd == "hide_ui" then
                _G._tsm_hide_ui = not _G._tsm_hide_ui
            else
                _G._tsm_web_cmd = b.cmd
            end
            b.cmd = nil
            _tsm_dump_web_bridge(b)
        end
        if _G.TrainingModeActive and b.teleport and _G._dv_teleport then
            pcall(_G._dv_teleport, b.teleport.distance)
            b.teleport = nil
            _tsm_dump_web_bridge(b)
        end
    end
end

re.on_frame(function()
    _tsm_force_hide_reframework_menu()

    SharedUI.clear_rects()
    _G.TrainingBarsDrawn = false
    _G.TrainingScriptManagerActiveThisFrame = false

    -- Mode change ticker
    local cur_mode = _G.CurrentTrainerMode or 0
    if cur_mode ~= _tsm_last_mode then
        local name = TSM_MODE_NAMES[cur_mode]
        if name and cur_mode ~= 0 and _G.show_custom_ticker then
            _G.show_custom_ticker(name .. "已启动", 0.3)
        end
        _tsm_last_mode = cur_mode
    end

    -- FlowMap detection
    local fid = get_flowmap_id()
    _G.FlowMapID = fid
    _G.IsInBattleHub = (fid == 9)
    local is_replay = (fid == 10) or (_G.IsInReplay == true)
    local in_training = is_in_training_mode(fid, is_replay, _G.IsInBattleHub)
    RuntimeSafety.begin_frame(fid, in_training, is_replay, _G.IsInBattleHub)

    -- HIDE UI BUTTON (works in training + replay)
    if not _G._tsm_hide_flash then _G._tsm_hide_flash = 0 end
    if not _G._tsm_hide_rect then _G._tsm_hide_rect = { x = 0, y = 0, w = 0, h = 0 } end
    pcall(_tsm_update_hide_rect)
    if not _G._tsm_hide_cooldown then _G._tsm_hide_cooldown = 0 end
    if _G._tsm_hide_cooldown > 0 then _G._tsm_hide_cooldown = _G._tsm_hide_cooldown - 1 end
    if RuntimeSafety.is_training_allowed() and _G._tsm_hide_cooldown == 0 and imgui.is_mouse_clicked(0) then
        local m = imgui.get_mouse()
        if m then
            local r = _G._tsm_hide_rect
            if r.w > 0 and m.x >= r.x and m.x <= r.x + r.w and m.y >= r.y and m.y <= r.y + r.h then
                toggle_global_ui_visibility()
            end
        end
    end

    -- BattleHub: always disabled
    if _G.IsInBattleHub then
        if _G.CurrentTrainerMode ~= 0 then _G.CurrentTrainerMode = 0 end
        RuntimeSafety.disable("battle_hub")
        pcall(_tsm_dump_webstate_inactive, "battle_hub")
        return
    end

    -- Replay: UI-only analysis is allowed; input injection stays disabled.
    if is_replay then
        if _tsm_was_replay == false then
            -- First detection
            _tsm_was_replay = "waiting"
            _tsm_replay_timer = 0
            if _G.CurrentTrainerMode ~= 0 then _G.CurrentTrainerMode = 0 end
            _G.TrainingFloatingBar = nil
            _G.TrainingFloatingBarTop = nil
            _G.TrainingModeActive = false
        end
        if _tsm_was_replay == "waiting" then
            _tsm_replay_timer = _tsm_replay_timer + (1.0 / 60.0)
            if _tsm_replay_timer >= _tsm_replay_delay then
                _tsm_was_replay = "done"
                _G.CurrentTrainerMode = 4
            end
        end
        -- In replay: always return, no top bar, no guard logic
        _G.TrainingFloatingBarTop = nil
        _G.TrainingModeActive = true
        RuntimeSafety.allow_replay()
        pcall(TrainingHotkeys.update, true)
        return
    end

    -- Reset when leaving replay
    if _tsm_was_replay ~= false then
        _tsm_was_replay = false
    end
    -- ABSOLUTE KILLSWITCH: No gamepad reading or logic outside training
    if not in_training then
        -- AUTO-RESET: Disable all active modes when leaving Training Mode
        if _G.CurrentTrainerMode ~= 0 then
            _G.CurrentTrainerMode = 0
        end
        RuntimeSafety.disable("not_training")
        pcall(_tsm_dump_webstate_inactive, "not_training")
        return
    end
    RuntimeSafety.allow_training()
    if not RuntimeSafety.is_training_allowed() then
        if _G.CurrentTrainerMode ~= 0 then
            _G.CurrentTrainerMode = 0
        end
        _tsm_invalidate_training_mode_cache()
        RuntimeSafety.disable("unsafe_training_context")
        pcall(_tsm_dump_webstate_inactive, "unsafe_training_context")
        return
    end
    _G.TrainingModeActive = true
    _G.TrainingScriptManagerActiveThisFrame = true
    pcall(TrainingHotkeys.update)

    if not is_enabled_trainer_mode(_G.CurrentTrainerMode or 0) then
        _G.CurrentTrainerMode = 0
    end

    -- Clear D2D floating bar when no training mode is active
    if _G.CurrentTrainerMode == 0 then
        _G.TrainingFloatingBar = nil
        if _G._tsm_last_mode and _G._tsm_last_mode ~= 0 then
            pcall(function()
                local mgr = sdk.get_managed_singleton("app.training.TrainingManager")
                local rec = mgr and mgr:call("get_RecordFunc")
                if rec then
                    local m1 = rec:get_type_definition():get_method("SetPlay")
                    if m1 then m1:call(rec, false) end
                end
            end)
        end
    end
    if _G._tsm_last_mode and _G._tsm_last_mode ~= _G.CurrentTrainerMode then
        pcall(function()
            local tm = sdk.get_managed_singleton("app.training.TrainingManager")
            if not tm then return end
            local tData = tm:get_field("_tData")
            if not tData then return end
            local sm = tData:get_field("SelectMenu")
            if not sm then return end
            sm.StartLocation = 3
            sm.PlayerDatas[0].ManualPosX = -150
            sm.PlayerDatas[1].ManualPosX = 150
            tm:call("set_IsReqRefresh", true)
        end)
    end
    _G._tsm_last_mode = _G.CurrentTrainerMode

    -- CHECK AUTOMATIC GUARD SWITCHING
    update_guard_logic()

    -- TOP FLOATING BAR (hide during pause menu)
    _G.TrainingGamePaused = GS.in_pause_menu
    if not GS.in_pause_menu and not _G._tsm_hide_ui then
        draw_top_floating_bar()
    elseif _G._tsm_hide_ui then
        _G.TrainingBarsDrawn = true
    end


    local scripts_active = (_G.CurrentTrainerMode == 2 or (_G.CurrentTrainerMode == 4 and _G.ComboTrials_HideNativeHUD))
    manage_ui_visibility(scripts_active)

    if not _G._tsm_web_counter then
        _G._tsm_web_counter = 0
        pcall(function()
            local b = _tsm_load_web_bridge()
            if b and b._web_timestamp then _G._tsm_bridge_ts = b._web_timestamp end
        end)
    end
    _G._tsm_web_counter = _G._tsm_web_counter + 1
    if _G._tsm_web_counter >= 30 then
        _G._tsm_web_counter = 0
        pcall(_tsm_web_bridge_tick)
    end
end)

-- ==========================================
-- 5. USER INTERFACE
-- ==========================================
-- Styled headers
local UI_THEME = {
    hdr_modes   = UIKit.THEME.hdr_gold,
    hdr_config  = UIKit.THEME.hdr_purple,
    hdr_help    = UIKit.THEME.hdr_blue,
}

local styled_header = UIKit.styled_header

local function _tsm_value_to_text(v)
    if v == nil then return "nil" end
    if type(v) == "boolean" then return v and "true" or "false" end
    return tostring(v)
end

local function _tsm_guess_control_label(name, value)
    local n = tostring(name or ""):lower()
    local num = tonumber(tostring(value))

    if n == "inputtype" or n == "input_type" then
        if num == 0 then return "经典" end
        if num == 1 then return "现代" end
    end

    if n:find("modern") then
        if value == true or num == 1 then return "现代" end
        if value == false or num == 0 then return "经典" end
    end

    if n:find("classic") then
        if value == true or num == 1 then return "经典" end
        if value == false or num == 0 then return "现代" end
    end

    if n:find("control") or n:find("operation") or n:find("style") or n:find("input") then
        if num == 0 then return "经典" end
        if num == 1 then return "现代" end
    end

    return nil
end

local function _tsm_get_field_value(obj, field_name)
    if not obj or not field_name then return nil, false end
    local ok, v = pcall(function()
        local td = obj:get_type_definition()
        local f = td and td:get_field(field_name)
        if not f then return nil end
        return f:get_data(obj)
    end)
    if ok and v ~= nil then return v, true end
    return nil, false
end

local function _tsm_collect_control_candidates(player_idx)
    local out = { label = "未知", source = "", fields = {}, seen = {} }
    pcall(function()
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        local tData = tm and tm:get_field("_tData")
        if not tData then return end

        local containers = {
            { name = "ParameterSetting", obj = tData:get_field("ParameterSetting") },
            { name = "SelectMenu", obj = tData:get_field("SelectMenu") },
        }
        local candidate_names = {
            "ControlType", "controlType", "Control_Type",
            "OperationType", "operationType", "Operation_Type",
            "InputType", "inputType", "Input_Type",
            "BattleInputType", "CommandType", "StyleType",
            "IsModern", "isModern", "IsClassic", "isClassic",
        }

        for _, c in ipairs(containers) do
            local pd = c.obj and c.obj.PlayerDatas and c.obj.PlayerDatas[player_idx]
            if pd then
                for _, fname in ipairs(candidate_names) do
                    local v, ok = _tsm_get_field_value(pd, fname)
                    if ok then
                        local text = c.name .. "." .. fname .. "=" .. _tsm_value_to_text(v)
                        if not out.seen[text] then
                            table.insert(out.fields, text)
                            out.seen[text] = true
                        end
                        local guessed = _tsm_guess_control_label(fname, v)
                        if guessed and out.label == "未知" then
                            out.label = guessed
                            out.source = text
                        end
                    end
                end

                local td = pd:get_type_definition()
                if td then
                    for _, f in ipairs(td:get_fields()) do
                        local fname = f:get_name()
                        local lower = fname and fname:lower() or ""
                        local looks_related =
                            lower:find("control") or lower:find("operation") or
                            lower:find("input") or lower:find("style") or
                            lower:find("modern") or lower:find("classic") or
                            lower:find("assist")
                        if looks_related then
                            local ok, v = pcall(function() return f:get_data(pd) end)
                            if ok and v ~= nil then
                                local text = c.name .. "." .. fname .. "=" .. _tsm_value_to_text(v)
                                if not out.seen[text] then
                                    table.insert(out.fields, text)
                                    out.seen[text] = true
                                end
                                local guessed = _tsm_guess_control_label(fname, v)
                                if guessed and out.label == "未知" then
                                    out.label = guessed
                                    out.source = text
                                end
                            end
                        end
                    end
                end
            end
        end
    end)
    return out
end

re.on_draw_ui(function()
    -- Publish REFramework menu window rect for overlap detection
    pcall(function()
        local wpos = imgui.get_window_pos()
        local wsz = imgui.get_window_size()
        if wpos and wsz and _G.FloatingRects then
            _G._ref_menu_rect = { x = wpos.x, y = wpos.y, w = wsz.x, h = wsz.y }
        end
    end)

    -- SCRIPT ERRORS PANEL (error registry from SharedHooks)
    local _errs = _G._mod_errors
    if _errs and _errs.count > 0 then
        imgui.text_colored(string.format("[!] %d 个脚本错误", _errs.count), 0xFF0000FF)
        imgui.same_line()
        if imgui.tree_node("详情##mod_errors") then
            for i = #_errs.list, math.max(1, #_errs.list - 14), -1 do
                local e = _errs.list[i]
                imgui.text_colored(string.format("[%.0fs] %s", e.t, e.ctx), 0xFF00A5FF)
                imgui.text("    " .. e.err)
            end
            if imgui.button("清除##mod_errors") then
                _errs.list = {}; _errs.count = 0; _errs.config_failures = {}
            end
            imgui.tree_pop()
        end
    end

    local _has_errors = _errs and _errs.count > 0
    if _has_errors then imgui.push_style_color(0, 0xFF0000FF) end
    local _tsm_open = imgui.tree_node("小吞 Street Fighter 6 全能训练MOD包 v0.9a" .. (_has_errors and " [!]" or ""))
    if _has_errors then imgui.pop_style_color(1) end
    if _tsm_open then

        -- If not in training, show a waiting message and block the UI
        if not RuntimeSafety.is_training_allowed() then
            imgui.text_colored("[!] 未激活：仅训练模式可用。", 0xFF00A5FF)
            imgui.tree_pop()
            return
        end

        -- ==========================================
        -- SECTION 1: MODE SELECTION
        -- ==========================================
        if styled_header("--- 训练模式 ---", UI_THEME.hdr_modes) then
            local c0, v0 = imgui.checkbox("关闭", _G.CurrentTrainerMode == 0)
            if c0 and v0 then _G.CurrentTrainerMode = 0 end

            local c2, v2 = imgui.checkbox("确认训练", _G.CurrentTrainerMode == 2)
            if c2 and v2 then _G.CurrentTrainerMode = 2 end

            local c4, v4 = imgui.checkbox("连段训练", _G.CurrentTrainerMode == 4)
            if c4 and v4 then _G.CurrentTrainerMode = 4 end
        end

        if styled_header("--- 操作模式诊断 ---", UI_THEME.hdr_config) then
            local p1_mode = _tsm_collect_control_candidates(0)
            local p2_mode = _tsm_collect_control_candidates(1)
            imgui.text("P1 操作模式: " .. p1_mode.label)
            if p1_mode.source ~= "" then imgui.text_colored("  " .. p1_mode.source, 0xFF888888) end
            imgui.text("P2 操作模式: " .. p2_mode.label)
            if p2_mode.source ~= "" then imgui.text_colored("  " .. p2_mode.source, 0xFF888888) end

            if imgui.tree_node("候选字段##tsm_control_mode_fields") then
                imgui.text_colored("切换经典/现代后，观察下面哪个字段发生变化。", 0xFF00FFFF)
                imgui.text_colored("如果 P1/P2 仍显示未知，把这里的字段值发给我。", 0xFF888888)
                imgui.separator()
                imgui.text_colored("P1", 0xFF00FF00)
                if #p1_mode.fields == 0 then
                    imgui.text("  未找到相关字段")
                else
                    for _, line in ipairs(p1_mode.fields) do imgui.text("  " .. line) end
                end
                imgui.separator()
                imgui.text_colored("P2", 0xFF00FF00)
                if #p2_mode.fields == 0 then
                    imgui.text("  未找到相关字段")
                else
                    for _, line in ipairs(p2_mode.fields) do imgui.text("  " .. line) end
                end
                imgui.tree_pop()
            end
        end

        -- ==========================================
        -- SECTION 2: HOTKEY SETTINGS
        -- ==========================================
        if styled_header("--- 快捷键设置 ---", UI_THEME.hdr_config) then
            TrainingHotkeys.draw_menu()
        end

        -- SECTION 3: MODE DESCRIPTIONS
        -- ==========================================
        if styled_header("--- 模式说明 ---", UI_THEME.hdr_help) then
            imgui.text_colored("确认训练", 0xFF00FF00)
            imgui.text("  练习命中确认接连段。")
            imgui.text("  木人随机防御；命中就继续连段。")
            imgui.text("  被防则停止保持安全，并统计准确率。")
            imgui.spacing()

            imgui.text_colored("连段训练", 0xFF00FF00)
            imgui.text("  录制并练习自己的连段。")
            imgui.text("  保存连段的伤害、斗气、SA 统计。")
            imgui.text("  支持原始位置、镜像位置或任意位置回放。")
        end


        imgui.separator()
        if not _G._hc_logging then
            if imgui.button("开始确认训练日志") then _G._hc_logging = true; _G._hc_log_lines = {} end
        else
            if imgui.button("停止并保存日志") then
                _G._hc_logging = false
                if _G._hc_log_lines then
                    local f = io.open("Stats/HitConfirm_Debug.txt", "w")
                    if f then f:write(table.concat(_G._hc_log_lines, "\n")); f:close() end
                end
            end
            imgui.same_line(); imgui.text(#(_G._hc_log_lines or {}) .. " 行")
        end
        imgui.tree_pop()
    end
end)

-- Session Recap D2D overlay (draws on top of everything)
local SessionRecap = require("func/Training_SessionRecap")

local function _tsm_draw_hide_flash()
    local r = _G._tsm_hide_rect
    if not r or r.w <= 0 then return end
    local flash = _G._tsm_hide_flash or 0
    if flash > 0 then
        _G._tsm_hide_flash = flash - 1
        local c = _G._tsm_hide_ui and 0x99FF4444 or 0x9944FF88
        d2d.fill_rect(r.x, r.y, r.w, r.h, c)
        d2d.outline_rect(r.x, r.y, r.w, r.h, 2, 0xFFFFFFFF)
    end
end

if d2d and d2d.register then
    d2d.register(function() end, function()
        if RuntimeSafety.is_training_allowed() and SessionRecap and SessionRecap.d2d_draw then
            SessionRecap.d2d_draw()
        end
        if RuntimeSafety.is_training_allowed() then
            pcall(_tsm_draw_hide_flash)
        end
    end)
end
