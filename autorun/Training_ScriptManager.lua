-- Training_ScriptManager.lua
-- v4.0 : Top floating bar + new cycling order

local re = re
local sdk = sdk
local imgui = imgui
local json = json
require("func/SharedHooks") -- error registry (_G.safe_load_json) + shared hooks
local SF6CCVersion = require("func/SF6CC_Version")
local RuntimeSafety = require("func/RuntimeSafety")
local GS = require("func/GameState")
local UIKit = require("func/UIKit")
local ImGuiCanvas = require("func/ImGuiCanvas")
local TrainingHotkeys = require("func/Training_Hotkeys")
local TrainingMenuRegistry = require("func/Training_MenuRegistry")

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
        -- >>> COMBO TRIALS >>> TrainingComboTrials is the sole owner.
        -- Do not call ChangeGuardType here: mode 2 (guard after first hit)
        -- is reset to no guard by that API, while direct GuardSetting+bApply works.


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
-- This list owns both the top-bar order and hotkey cycle order. New training
-- modules belong here; the close button is rendered separately after the list.
local TRAINING_MODE_MODULES = {
    { id = 4, label = "连段训练" },
    { id = 2, label = "确认训练" },
}

local TSM_MODE_NAMES = { [0] = "已关闭" }
local ENABLED_TRAINER_MODES = { [0] = true }
local MODE_CYCLE = { 0 }
for _, module in ipairs(TRAINING_MODE_MODULES) do
    TSM_MODE_NAMES[module.id] = module.label
    ENABLED_TRAINER_MODES[module.id] = true
    MODE_CYCLE[#MODE_CYCLE + 1] = module.id
end

local function is_enabled_trainer_mode(mode)
    return ENABLED_TRAINER_MODES[mode or 0] == true
end

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

local top_bar_width = 1.0
local top_bar_height = 0.0444

local function draw_top_floating_bar()
    local visible, sw, sh = SharedUI.begin_floating_window_top("TrainingModeSwitch##top", top_bar_width, top_bar_height)
    if not visible then
        SharedUI.end_floating_window_top(); return
    end
    SharedUI.draw_floating_bg_top()

    local scale = sh / 1080.0
    local sp = 0

    local train_x = sw * 0.125
    local mode_btn_w = math.max(124 * scale, sw * 0.073)
    local control_h = math.max(1, sh * (top_bar_height - 0.02))
    local close_size = control_h

    local passive_w = mode_btn_w
    local feature_start_x = sw * 0.665
    local top_y = sh * 0.01

    imgui.set_cursor_pos(Vector2f.new(train_x, top_y))
    for index, btn in ipairs(TRAINING_MODE_MODULES) do
        if index > 1 then imgui.same_line(0, sp) end
        local is_active = (_G.CurrentTrainerMode == btn.id)
        if SharedUI.sf6_rect_button(btn.label .. "##top_" .. btn.id, is_active, mode_btn_w, control_h) then
            _G.CurrentTrainerMode = btn.id
        end
    end

    imgui.same_line(0, sp)
    if SharedUI.sf6_rect_button(
            "X##top_close_all_modes",
            _G.CurrentTrainerMode == 0,
            close_size,
            close_size,
            "close"
        ) then
        _G.CurrentTrainerMode = 0
    end

    imgui.set_cursor_pos(Vector2f.new(feature_start_x, top_y))
    if SharedUI.sf6_rect_button(
            "距离显示##top_distance_viewer",
            config.distance_viewer_enabled == true,
            passive_w,
            control_h
        ) then
        config.distance_viewer_enabled = not config.distance_viewer_enabled
        save_config()
        if _G.show_custom_ticker then _G.show_custom_ticker(config.distance_viewer_enabled and "距离显示已开启" or "距离显示已关闭", 0.3) end
    end

    imgui.same_line(0, sp)
    if SharedUI.sf6_rect_button(
            "碰撞显示##top_sheldons_boxes",
            config.sheldons_boxes_enabled == true,
            passive_w,
            control_h
        ) then
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
-- BATTLE INPUT TYPE / REPLAY DETECTION HOOKS
-- ==========================================
pcall(function()
    local t_emote = sdk.find_type_definition("app.esports.bBattleFighterEmoteFlow")
    if t_emote then
        local m_setup = t_emote:get_method("setup")
        if m_setup then
            RuntimeSafety.trace("battle_input_hook=registered")
            sdk.hook(m_setup, function(args)
                local obj = sdk.to_managed_object(args[2])
                if obj then
                    local raw_input_type = obj.mInputType
                    local input_type = tonumber(tostring(raw_input_type))
                    RuntimeSafety.trace("battle_setup raw_input_type=" .. tostring(raw_input_type)
                        .. " normalized=" .. tostring(input_type))
                    if input_type ~= nil then
                        RuntimeSafety.set_battle_input_type(input_type)
                        _G.IsInReplay = input_type == 3
                    end
                else
                    RuntimeSafety.trace("battle_setup object=nil")
                end
            end, function(r) return r end)
        else
            RuntimeSafety.trace("battle_input_hook=missing_setup_method")
        end
    else
        RuntimeSafety.trace("battle_input_hook=missing_type")
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

    -- Clear the floating training bar when no training mode is active
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


    local scripts_active = (_G.CurrentTrainerMode == 2)
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
    hdr_root = UIKit.THEME.hdr_dark_purple,
    hdr_combo_config = UIKit.THEME.hdr_rainbow_red,
    hdr_confirm_config = UIKit.THEME.hdr_rainbow_orange,
    hdr_training_config = UIKit.THEME.hdr_rainbow_yellow,
    hdr_distance_viewer = UIKit.THEME.hdr_rainbow_green,
    hdr_collision_boxes = UIKit.THEME.hdr_rainbow_blue,
    hdr_hotkeys = UIKit.THEME.hdr_rainbow_violet,
}

local styled_header = UIKit.styled_header

local function draw_replay_analysis_menu()
    imgui.text_colored("录像回放分析模式：仅开放视觉显示与连段录制。", 0xFF00A5FF)
    imgui.text_colored("传送、自动操作和训练输入保持关闭。", 0xFF888888)
    imgui.spacing()

    local changed_distance, distance_enabled = imgui.checkbox(
        "启用距离显示##replay_distance_viewer",
        config.distance_viewer_enabled == true
    )
    if changed_distance then
        config.distance_viewer_enabled = distance_enabled
        save_config()
    end

    local changed_boxes, boxes_enabled = imgui.checkbox(
        "启用碰撞显示##replay_sheldons_boxes",
        config.sheldons_boxes_enabled == true
    )
    if changed_boxes then
        config.sheldons_boxes_enabled = boxes_enabled
        save_config()
    end

    imgui.separator()
    if styled_header("距离查看器", UI_THEME.hdr_distance_viewer) then
        TrainingMenuRegistry.draw("distance_viewer")
    end

    if styled_header("碰撞框查看器(by Sheldon)", UI_THEME.hdr_collision_boxes) then
        TrainingMenuRegistry.draw("sheldons_boxes")
    end

    imgui.separator()
    imgui.text_colored("连段录制可通过画面底部的“录制 P1 / 录制 P2”操作。", 0xFF88FF88)
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
    local _tsm_open = styled_header(
        "小吞街霸6全能训练MOD包 v" .. SF6CCVersion.PRODUCT_VERSION
            .. (_has_errors and " [!]" or ""),
        UI_THEME.hdr_root
    )
    if _has_errors then imgui.pop_style_color(1) end
    if _tsm_open then
        imgui.indent(12)

        local training_allowed = RuntimeSafety.is_training_allowed()
        local replay_allowed = RuntimeSafety.is_replay_allowed()

        if replay_allowed then
            draw_replay_analysis_menu()
            imgui.unindent(12)
            return
        end

        -- Outside an allowed training/replay context, show a waiting message and block the UI.
        if not training_allowed then
            imgui.text_colored("[!] 未激活：仅训练模式可用。", 0xFF00A5FF)
            imgui.unindent(12)
            return
        end

        -- Mode selection stays at the root and on one line.
        imgui.text("切换模式：")
        imgui.same_line()
        local c0, v0 = imgui.checkbox("关闭", _G.CurrentTrainerMode == 0)
        if c0 and v0 then _G.CurrentTrainerMode = 0 end
        imgui.same_line()
        local c2, v2 = imgui.checkbox("确认训练", _G.CurrentTrainerMode == 2)
        if c2 and v2 then _G.CurrentTrainerMode = 2 end
        imgui.same_line()
        local c4, v4 = imgui.checkbox("连段训练", _G.CurrentTrainerMode == 4)
        if c4 and v4 then _G.CurrentTrainerMode = 4 end

        imgui.separator()
        if styled_header("连段训练配置", UI_THEME.hdr_combo_config) then
            if _G.CurrentTrainerMode ~= 4 then
                imgui.text_colored("当前未启用连段训练。", 0xFF888888)
                imgui.text_colored("勾选顶部栏“连段训练”后显示配置。", 0xFF888888)
            else
                TrainingMenuRegistry.draw("combo_config")
            end
        end

        if styled_header("确认训练配置", UI_THEME.hdr_confirm_config) then
            if _G.CurrentTrainerMode ~= 2 then
                imgui.text_colored("当前未启用确认训练。", 0xFF888888)
                imgui.text_colored("勾选顶部栏“确认训练”后显示配置。", 0xFF888888)
            else
                TrainingMenuRegistry.draw("confirm_config")
            end
        end

        if styled_header("木人库配置管理", UI_THEME.hdr_training_config) then
            TrainingMenuRegistry.draw("training_config")
        end

        if styled_header("距离查看器", UI_THEME.hdr_distance_viewer) then
            TrainingMenuRegistry.draw("distance_viewer")
        end

        if styled_header("碰撞框查看器(by Sheldon)", UI_THEME.hdr_collision_boxes) then
            TrainingMenuRegistry.draw("sheldons_boxes")
        end

        if styled_header("快捷键设置", UI_THEME.hdr_hotkeys) then
            TrainingHotkeys.draw_menu()
        end

        imgui.separator()
        imgui.text_colored("https://sf6cm.sctrip.asia", 0xFFFFFF00)
        imgui.text_colored("可在此网站下载、管理连段和木人库配置。", 0xFF888888)

        imgui.spacing()
        imgui.separator()
        if imgui.tree_node("高级/调试") then
            if imgui.tree_node("动作 ID 探针") then
                TrainingMenuRegistry.draw("action_id_probe")
                imgui.tree_pop()
            end
            imgui.tree_pop()
        end
        imgui.unindent(12)
    end
end)

-- Session recap pure ImGui overlay (drawn after the training modules)
local SessionRecap = require("func/Training_SessionRecap")

local function _tsm_draw_hide_flash()
    local r = _G._tsm_hide_rect
    if not r or r.w <= 0 then return end
    local flash = _G._tsm_hide_flash or 0
    if flash > 0 then
        _G._tsm_hide_flash = flash - 1
        local c = _G._tsm_hide_ui and 0x99FF4444 or 0x9944FF88
        ImGuiCanvas.fill_rect(r.x, r.y, r.w, r.h, c)
        ImGuiCanvas.outline_rect(r.x, r.y, r.w, r.h, 2, 0xFFFFFFFF)
    end
end

re.on_frame(function()
    if not RuntimeSafety.is_training_allowed() then return end
    if not ImGuiCanvas.begin_frame() then return end
    if SessionRecap and SessionRecap.imgui_draw then
        pcall(SessionRecap.imgui_draw)
    end
    pcall(_tsm_draw_hide_flash)
end)
