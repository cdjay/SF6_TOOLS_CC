local sdk = sdk
local imgui = imgui
local re = re
local json = json
require("func/SharedHooks")
local RuntimeSafety = require("func/RuntimeSafety")
local GS = require("func/GameState")
local ComboTrialsModules = {
    DebugTrace = require("func/ComboTrials/DebugTrace"),
    ActionMatcher = require("func/ComboTrials/ActionMatcher"),
    CharacterRules = require("func/ComboTrials/CharacterRules"),
    Validator = require("func/ComboTrials/Validator"),
    PendingAbsorb = require("func/ComboTrials/PendingAbsorb")
}
local DebugTrace = ComboTrialsModules.DebugTrace
local ActionMatcher = ComboTrialsModules.ActionMatcher
local CharacterRules = ComboTrialsModules.CharacterRules
local Validator = ComboTrialsModules.Validator

-- DEV ONLY / DO NOT COMMIT ENABLED.
-- Temporary self-contained HP restore test mode for Jamie 1000/10000 HP.
CT_DEV_HP_RESTORE_TEST = false
if CT_DEV_HP_RESTORE_TEST then
    _G.CT_HP_RESTORE_TRACE = true
end

local function ct_default_global_flag(name, value)
    if rawget(_G, name) == nil then _G[name] = value end
end

ct_default_global_flag("CT_HP_RESTORE_TRACE", false)
ct_default_global_flag("CT_UNIQUE_TRACE", false)
ct_default_global_flag("CT_DEMO_TRACE", false)
ct_default_global_flag("CT_VERIFY_TRACE", false)
ct_default_global_flag("CT_HONDA_NORMAL_DUMP", false)
ct_default_global_flag("CT_SAME_ACTION_TRACE", false)
ct_default_global_flag("CT_SAME_ACTION_TRACE_FILE", false)
ct_default_global_flag("CT_AUTO_FILE_SCAN", false)
ct_default_global_flag("CT_SAVE_STATE_POC", false)

pcall(function()
    if fs and fs.create_dir then fs.create_dir("TrainingComboTrials_data/exceptions") end
end)

local _td_gBattle = sdk.find_type_definition("gBattle")
local _td_sfix = sdk.find_type_definition("via.sfix")
local _td_gamepad = sdk.find_type_definition("via.hid.GamePad")


local ui_state = { viewed_player = 0 }

-- EXACT FRAME COUNTER (Lag-independent, synced to engine)
local engine_frame_count = 0
local _pf = {}

local DIR_MAP = {
    [0] = "5",
    [1] = "8",
    [2] = "2",
    [4] = "4",
    [8] = "6",
    [5] = "7",
    [6] = "1",
    [9] = "9",
    [10] = "3",
    [15] = "*"
}
local BTN_MASKS = { [16] = "LP", [32] = "MP", [64] = "HP", [128] = "LK", [256] = "MK", [512] = "HK" }

local esf_names_map = {
    ["ESF_001"] = "Ryu",
    ["ESF_002"] = "Luke",
    ["ESF_003"] = "Kimberly",
    ["ESF_004"] = "ChunLi",
    ["ESF_005"] = "Manon",
    ["ESF_006"] = "Zangief",
    ["ESF_007"] = "JP",
    ["ESF_008"] = "Dhalsim",
    ["ESF_009"] = "Cammy",
    ["ESF_010"] = "Ken",
    ["ESF_011"] = "DeeJay",
    ["ESF_012"] = "Lily",
    ["ESF_013"] = "AKI",
    ["ESF_014"] = "Rashid",
    ["ESF_015"] = "Blanka",
    ["ESF_016"] = "Juri",
    ["ESF_017"] = "Marisa",
    ["ESF_018"] = "Guile",
    ["ESF_019"] = "Ed",
    ["ESF_020"] = "EHonda",
    ["ESF_021"] = "Jamie",
    ["ESF_022"] = "Akuma",
    ["ESF_025"] = "Sagat",
    ["ESF_026"] = "MBison",
    ["ESF_027"] = "Terry",
    ["ESF_028"] = "Mai",
    ["ESF_029"] = "Elena",
    ["ESF_030"] = "CViper",
    ["ESF_031"] = "Alex",
	["ESF_032"]="Ingrid" 
}


local common_exceptions = CharacterRules.load_common()

local DR_IDS = { [500]=true, [501]=true, [502]=true, [504]=true, [730]=true, [731]=true, [739]=true, [740]=true, [741]=true, [760]=true, [761]=true }

local unique_resources = {
    by_fighter_id = {
        [1] = {
        name = "Ryu",
        resources = {
            { id = "timer_0_001", kind = "timer", min = 0, max = 2 }
        }
    },
    [3] = {
        name = "Kimberly",
        resources = {
            { id = "stock_0_003", kind = "stock", min = 0, max = 2, allow_infinite = true }
        }
    },
    [5] = {
        name = "Manon",
        resources = {
            { id = "stock_0_005", kind = "stock", min = 0, max = 4 }
        }
    },
    [12] = {
        name = "Lily",
        resources = {
            { id = "stock_0_012", kind = "stock", min = 0, max = 3, allow_infinite = true }
        }
    },
    [15] = {
        name = "Blanka",
        resources = {
            { id = "timer_0_015", kind = "timer", min = 0, max = 2 },
            { id = "stock_0_015", kind = "stock", min = 0, max = 3, allow_infinite = true }
        }
    },
    [16] = {
        name = "Juri",
        resources = {
            { id = "timer_0_016", kind = "timer", min = 0, max = 2 },
            { id = "stock_0_016", kind = "stock", min = 0, max = 3, allow_infinite = true }
        }
    },
    [18] = {
        name = "Guile",
        resources = {
            { id = "timer_0_018", kind = "timer", min = 0, max = 2 }
        }
    },
    [20] = {
        name = "EHonda",
        resources = {
            { id = "stock_0_020", kind = "stock", min = 0, max = 1, allow_infinite = true }
        }
    },
    [21] = {
        name = "Jamie",
        resources = {
            { id = "timer_0_021", kind = "timer", min = 0, max = 2 },
            { id = "stock_0_021", kind = "stock", min = 0, max = 4 }
        }
    },
    [28] = {
        name = "Mai",
        resources = {
            { id = "stock_0_028", kind = "stock", min = 0, max = 5, reject_infinite = true, setter = "SetUnique028_stock_0" }
        }
    },
    [30] = {
        name = "CViper",
        resources = {
            { id = "timer_0_030", kind = "timer", min = 0, max = 2 }
        }
    },
    [32] = {
        name = "Ingrid",
        resources = {
            { id = "stock_0_032", kind = "stock", min = 0, max = 4, allow_infinite = true }
        }
    }
    },
    by_id = nil
}

function unique_resources.resource_by_id(resource_id)
    if not unique_resources.by_id then
        local by_id = {}
        for _, char_data in pairs(unique_resources.by_fighter_id) do
            for _, resource in ipairs(char_data.resources or {}) do
                by_id[resource.id] = resource
            end
        end
        unique_resources.by_id = by_id
    end
    return unique_resources.by_id[resource_id]
end

function unique_resources.fighter_id_for_resource(resource_id)
    for fighter_id, char_data in pairs(unique_resources.by_fighter_id) do
        for _, resource in ipairs(char_data.resources or {}) do
            if resource.id == resource_id then return fighter_id end
        end
    end
    return nil
end

local function is_drive_rush_id(act_id)
    return DR_IDS[act_id] == true
end

local function is_drive_rush_motion(motion)
    if not motion then return false end
    local m = motion:upper()
    return m == "DRIVE RUSH" or m == "DRC" or m == "RAW DR"
end

local function is_parry_action(motion_str, real_input_str, act_name)
    return (motion_str and motion_str:upper():match("PARRY") ~= nil) or
           (real_input_str and real_input_str:upper():match("PARRY") ~= nil) or
           (act_name and act_name:upper():match("PARRY") ~= nil)
end

local players = {
    [0] = {
        log = {}, prev_act_id = -1, prev_act_frame = -1, last_combo_count = 0,
        action_instance_counter = 0, current_action_instance = 0, buffer_action_instance = 0,
        bcm_cache = {}, trigger_mask_cache = {}, cache_built = false,
        last_bcm_ptr = "", last_direct_input = 0, input_history_queue = {},
        profile_name = "Unknown", last_profile_name = "", exceptions = {},
        editing_id = -1, edit_ignore = false, edit_force = false, edit_text = "",
		edit_is_common = false, edit_holdable = false, edit_absorb_ids = "",
        edit_charge_min = "", edit_charge_max = "", enable_deep_logging = false,
        edit_ignore_prev_id = "", edit_ignore_prev_frames = "5"
    },
    [1] = {
        log = {}, prev_act_id = -1, prev_act_frame = -1, last_combo_count = 0,
        action_instance_counter = 0, current_action_instance = 0, buffer_action_instance = 0,
        bcm_cache = {}, trigger_mask_cache = {}, cache_built = false,
        last_bcm_ptr = "", last_direct_input = 0, input_history_queue = {},
        profile_name = "Unknown", last_profile_name = "", exceptions = {},
        editing_id = -1, edit_ignore = false, edit_force = false, edit_text = "",
		edit_is_common = false, edit_holdable = false, edit_absorb_ids = "",
        edit_charge_min = "", edit_charge_max = "", enable_deep_logging = false,
        edit_ignore_prev_id = "", edit_ignore_prev_frames = "5"
    }
}

-- GLOBAL COMBO TRIAL STATE
local trial_state = {
    is_recording = false,
    recording_player = 0,
    is_playing = false,
    playing_player = 0,
    sequence = {},
    current_step = 1,
    success_timer = 0,
    fail_timer = 0,
    fail_reason = nil,
    manual_reset_pending = false,
    last_recorded_frame = 0,
    last_played_frame = 0,
    start_pos_p1 = nil,
    start_pos_p2 = nil,
    start_pos_p1_raw = nil,
    start_pos_p2_raw = nil,
    recording_start_pos_p1 = nil,
    recording_start_pos_p2 = nil,
    recording_start_pos_p1_raw = nil,
    recording_start_pos_p2_raw = nil,
    first_action_pos_p1 = nil,
    first_action_pos_p2 = nil,
    first_action_pos_p1_raw = nil,
    first_action_pos_p2_raw = nil,
    pending_exact_pos = 0,
    pending_exact_timeout = 0,
    saved_start_location = nil,
    flip_inputs = false,   -- Whether to visually flip the input display
    _rec_gauges = nil,     -- Gauge snapshot at recording start
    _rec_hp_snapshot = nil,
    _rec_hit_type = nil,   -- CH/PC detected on first hit
    _rec_scene_state = nil,
    _saved_unique_resources = nil,
    _saved_drive_settings = nil,
    _saved_vital_p1 = nil,
    _saved_vital_p2 = nil,
    _pending_victim_hp = nil,
    _pending_attacker_hp = nil,
    _hp_inject_frames = 0,
    _hp_restore_token = 0,
    _hp_restore = nil,
    _hp_restore_debug = nil,
    _hp_training_setting_backup = nil,
    _hp_snapshot_applied_current_session = false,
    _hp_setting_restore_debug = nil,
    _rec_pending_snapshot = 0,
    _was_playing = false,   -- Previous state for detecting transitions
    _step1_wrong_pending = false,
    _pending_current_absorb = nil,
    _pending_block_outcome = nil,
    _demo_backup_slot = nil
}

local XT_SETTINGS_FILE = "TrainingComboTrials_data/XT_Settings.json"
local xt_settings = {
    default_author = "佚名"
}

local function load_xt_settings()
    if type(_G.safe_load_json) ~= "function" then return end
    local ok, loaded = pcall(_G.safe_load_json, XT_SETTINGS_FILE)
    if not ok then return end
    if type(loaded) == "table" then
        if type(loaded.default_author) == "string" and loaded.default_author ~= "" then
            xt_settings.default_author = loaded.default_author
        end
    end
end

local function save_xt_settings()
    if fs and fs.create_dir then pcall(fs.create_dir, "TrainingComboTrials_data") end
    json.dump_file(XT_SETTINGS_FILE, xt_settings)
end

local function read_player_input_type(player_idx)
    local input_type = nil
    pcall(function()
        local tm = sdk and sdk.get_managed_singleton and sdk.get_managed_singleton("app.training.TrainingManager")
        local t_data = tm and tm:get_field("_tData")
        if not t_data then return end

        local containers = {
            t_data:get_field("SelectMenu"),
            t_data:get_field("ParameterSetting"),
        }

        for _, container in ipairs(containers) do
            local player_data = container and container.PlayerDatas and container.PlayerDatas[player_idx or 0]
            if player_data then
                local ok, value = pcall(function()
                    local td = player_data:get_type_definition()
                    local field = td and td:get_field("InputType")
                    if field then return field:get_data(player_data) end
                    return nil
                end)
                if not ok or value == nil then
                    ok, value = pcall(function() return player_data.InputType end)
                end
                if ok and value ~= nil then
                    input_type = tonumber(value) or tonumber(tostring(value))
                    if input_type == nil and sdk and sdk.to_int64 then
                        pcall(function() input_type = tonumber(sdk.to_int64(value)) end)
                    end
                    if input_type ~= nil then return end
                end
            end
        end
    end)
    return input_type
end

local function control_type_from_input_type(input_type)
    if tonumber(input_type) == 1 then return "modern" end
    return "classic"
end

local function build_auto_xt_meta(recording_player)
    local input_type = read_player_input_type(recording_player or trial_state.recording_player or 0)
    local control_type = control_type_from_input_type(input_type)
    return {
        title = "",
        note = "",
        author = xt_settings.default_author or "佚名",
        tags = {},
        created_at = os.date("%Y-%m-%d %H:%M:%S"),
        schema = 1,
        control_type = control_type,
        timeline_input_profile = control_type,
        input_type = input_type
    }
end

load_xt_settings()

local function counter_type_from_hit_type(hit_type)
    if hit_type == "PC" then return 2 end
    if hit_type == "CH" then return 1 end
    return 0
end

-- =========================================================
-- DEMO ENGINE STATE
-- =========================================================
local demo_state = {
    is_playing = false,
    current_frame = 0,
    current_step = 1,
    sequence = {},
    p1_mask = 0
}
local p_id_stack = {}
local tick_done_this_frame = false



-- =========================================================
-- INPUT LOGGER (JSON EXPORT)
-- =========================================================
local logger_state = {
    rec_p1 = { active = false, has_started = false, data = {}, facing_right = false, char_name = "P1_Waiting" },
    rec_p2 = { active = false, has_started = false, data = {}, facing_right = false, char_name = "P2_Waiting" },
    dual_active = false,
    window_open = false,
    last_export_name = nil,
    last_export_name_2 = nil
}

local function logger_update_char_names()
    if players[0].profile_name ~= "Unknown" then
        logger_state.rec_p1.char_name = players[0].profile_name
    end
    if players[1].profile_name ~= "Unknown" then
        logger_state.rec_p2.char_name = players[1].profile_name
    end
end

local function logger_get_numpad_notation(dir_val)
    local u = (dir_val & 1) ~= 0
    local d = (dir_val & 2) ~= 0
    local r = (dir_val & 4) ~= 0
    local l = (dir_val & 8) ~= 0

    if u and l then return "7"
    elseif u and r then return "9"
    elseif d and l then return "1"
    elseif d and r then return "3"
    elseif u then return "8"
    elseif d then return "2"
    elseif l then return "4"
    elseif r then return "6"
    end
    return "5"
end

local function logger_get_btn_string(val)
    local str = ""
    if (val & 16) ~= 0  then str = str .. "+LP" end
    if (val & 128) ~= 0 then str = str .. "+LK" end
    if (val & 32) ~= 0  then str = str .. "+MP" end
    if (val & 256) ~= 0 then str = str .. "+MK" end
    if (val & 64) ~= 0  then str = str .. "+HP" end
    if (val & 512) ~= 0 then str = str .. "+HK" end
    return str
end

function _G.ComboTrials_sanitize_filename_component(value, max_chars, fallback)
    if fallback == nil then fallback = "UNKNOWN" end

    local function local_trim_string(v)
        return (tostring(v or ""):match("^%s*(.-)%s*$") or "")
    end

    local function local_truncate_utf8(v, max_len)
        local s = tostring(v or "")
        if s == "" then return s end
        local out, count = {}, 0
        for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
            count = count + 1
            if count > max_len then break end
            out[#out + 1] = ch
        end
        if #out == 0 then return s:sub(1, max_len) end
        return table.concat(out)
    end

    local reserved = _G.ComboTrials_windows_reserved_filenames
    if not reserved then
        reserved = {
            CON = true, PRN = true, AUX = true, NUL = true,
            COM1 = true, COM2 = true, COM3 = true, COM4 = true, COM5 = true,
            COM6 = true, COM7 = true, COM8 = true, COM9 = true,
            LPT1 = true, LPT2 = true, LPT3 = true, LPT4 = true, LPT5 = true,
            LPT6 = true, LPT7 = true, LPT8 = true, LPT9 = true,
        }
        _G.ComboTrials_windows_reserved_filenames = reserved
    end

    local s = local_trim_string(value)
    if max_chars then s = local_truncate_utf8(s, max_chars) end
    s = s:gsub("[%c]", "")
    s = s:gsub("%s+", "_")
    s = s:gsub("[<>:\"/\\|%?%*%.]", "_")

    local out = {}
    for i = 1, #s do
        local b = s:byte(i)
        if (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 45 or b == 95 then
            out[#out + 1] = s:sub(i, i)
        elseif b < 128 then
            out[#out + 1] = "_"
        end
    end

    s = table.concat(out)
    s = s:gsub("_+", "_")
    s = s:gsub("^_+", ""):gsub("_+$", "")
    if s == "" then return fallback end
    if reserved[s:upper()] then
        s = s .. "_FILE"
    end
    return s
end

local function logger_export(rec_struct, suffix)
    local output = { 
        ReplayInputRecord = true, 
        timeline = {} 
    }
    
    for i, entry in ipairs(rec_struct.data) do
        local frame_str = tostring(entry.frames) .. "f"
        local dir_str = logger_get_numpad_notation(entry.dir)
        local btn_str = logger_get_btn_string(entry.btn)
        local line = string.format("%s : %s%s", frame_str, dir_str, btn_str)
        table.insert(output.timeline, line)
    end
    
    local timestamp = os.date("%Y%m%d%H%M%S")
    local name = rec_struct.char_name or "Unknown"
    local safe_name = _G.ComboTrials_sanitize_filename_component(name, 32, "Unknown")
    if suffix then
        local safe_suffix = _G.ComboTrials_sanitize_filename_component(suffix, 16, "")
        if safe_suffix ~= "" then safe_name = safe_name .. "_" .. safe_suffix end
    end
    
    local short_filename = "ReplayInputRecord_" .. safe_name .. "_" .. timestamp .. ".json"
    local full_path = "TrainingComboTrials_data/ReplayRecords/" .. short_filename
    
    if fs.create_dir then fs.create_dir("TrainingComboTrials_data/ReplayRecords") end
    json.dump_file(full_path, output)

    return short_filename
end

local function logger_update_recording(rec_table, current_dir, current_btn)
    local buffer = rec_table.data
    local last_entry = buffer[#buffer] 
    local is_same = false
    
    if last_entry and last_entry.dir == current_dir and last_entry.btn == current_btn then 
        is_same = true 
    end
    
    if is_same then
        last_entry.frames = last_entry.frames + 1
    else
        table.insert(buffer, { dir=current_dir, btn=current_btn, frames=1 })
    end
end

local function logger_process_game_state()
    logger_update_char_names()

    local player_mgr = GS.sP
    if not player_mgr then return end

    local is_paused = GS.in_pause_menu

    local function process_player(index, rec_struct)
        local p = (index == 0) and GS.p1 or GS.p2
        if not p then return end
        
        local is_facing_right = p:get_field("rl_dir")
        rec_struct.facing_right = is_facing_right

        if rec_struct.active and not is_paused then
            local f_input = p:get_type_definition():get_field("pl_input_new")
            local f_sw = p:get_type_definition():get_field("pl_sw_new")
            
            local d = (f_input and f_input:get_data(p)) or 0
            local b = (f_sw and f_sw:get_data(p)) or 0
            
            if not is_facing_right then
                local has_right = (d & 4) ~= 0 
                local has_left  = (d & 8) ~= 0 
                d = d & ~4 
                d = d & ~8 
                if has_right then d = d | 8 end 
                if has_left  then d = d | 4 end 
            end
            
            -- Wait for the first real action (direction or button) to start the timeline
            if not rec_struct.has_started then
                if d == 0 and b == 0 then
                    return -- Ignore all initial neutral frames until an action
                else
                    rec_struct.has_started = true -- Let's go!
                end
            end
            
            logger_update_recording(rec_struct, d, b)
        end
    end

    process_player(0, logger_state.rec_p1)
    process_player(1, logger_state.rec_p2)
end

local file_system = {
    saved_combos_display_p1 = {},
    saved_combos_paths_p1 = {},
    saved_combos_control_p1 = {},
    saved_combos_all_display_p1 = {},
    saved_combos_all_paths_p1 = {},
    saved_combos_all_control_p1 = {},
    skipped_combos_p1 = 0,
    selected_file_idx_p1 = 1,

    saved_combos_display_p2 = {},
    saved_combos_paths_p2 = {},
    saved_combos_control_p2 = {},
    saved_combos_all_display_p2 = {},
    saved_combos_all_paths_p2 = {},
    saved_combos_all_control_p2 = {},
    skipped_combos_p2 = 0,
    selected_file_idx_p2 = 1,

    last_p1_id = -1,
    auto_load = true,
    forced_position_options = { "GAME SETTINGS", "FORCED", "MIRROR" },
    combo_control_filter = "auto",

    combo_list_auto_refresh_enabled = false,
    combo_list_auto_refresh_frames = 600,
    combo_list_auto_refresh_counter = 0,
    combo_list_was_active = false,
    combo_list_pending_save_refreshed = false,
    combo_list_refresh_pending = false,
    combo_list_refresh_pending_reload = false,
    combo_list_refresh_pending_reason = nil,
    combo_list_refresh_deferred_logged = false,
    combo_list_last_signature = nil,
    combo_list_signature_warn_counter = 0,
    trialhub_sync_poll_frames = 90,
    trialhub_sync_counter = 0,
    trialhub_last_marker = nil,
    trialhub_sync_warn_counter = 0,
    trialhub_signal_last_path = nil,
    trialhub_signal_last_raw = nil,
    trialhub_signal_last_data = nil,
    trialhub_signal_last_error = nil,
    replay_bridge_poll_frames = 10,
    replay_bridge_poll_counter = nil,

    diag_enabled = false,
    diag_frame = 0,
    diag_last_runtime_allowed = nil,
    diag_last_mode = nil,
    diag_last_busy_reason = nil,
    diag_no_signal_counter = 0,
    diag_invalid_signal_counter = 0,
    diag_signature_counter = 0
}

local function clear_pending_position_injection()
    trial_state.exact_inject_r1 = nil
    trial_state.exact_inject_r2 = nil
    trial_state.override_inject_r1 = nil
    trial_state.override_inject_r2 = nil
    trial_state.pending_exact_pos = nil
    trial_state.pending_exact_timeout = nil
    trial_state._pause_live_r1 = nil
    trial_state._pause_live_r2 = nil
    trial_state._unpause_delay = nil
end

-- =========================================================
-- D2D VISUALIZER CONFIGURATION
-- =========================================================
local D2D_CONFIG_FILE = "TrainingComboTrials_data/CommandLogger_Visualizer.json"
local d2d_cfg = {
    enabled = true,
    auto_load = true,
    forced_position_idx = 1,
    show_p1 = true,
    show_p2 = true,
    raw_p1 = false,
    raw_p2 = false,
    mirror_p1 = false,
    mirror_p2 = false,
    show_combo_count = true,
    pos_p1 = { x = 0.050, y = 0.350 },
    pos_p2 = { x = 0.850, y = 0.350 },
    raw_pos_p1 = { x = 0.050, y = 0.350 },
    raw_pos_p2 = { x = 0.850, y = 0.350 },
    pos_trial_p1 = { x = 0.050, y = 0.350 },
    pos_trial_p2 = { x = 0.850, y = 0.350 },
    pos_trial = { x = 0.400, y = 0.150 },
    cartouche_width = 0.220,
    cartouche_height = 0.5,
    cartouche_offset_x = 0.000,
    cartouche_offset_y = 0.000,
    icon_size = 0.035,
    font_size = 0.028,
    trial_title_show = true,
    show_trial_notes = false,
    auto_next_trial = true,
    trial_title_font_size = 0.030,
    spacing_y = 0.045,
    spacing_x = 0.005,
    text_y_offset = 0.000,
    max_history = 10,
    special_icon_scale = 1.0,
    trial_visible_steps = 7,
    ignore_auto = true,

    -- Separate config for IDLE mode (no active record/trial)
    idle_show_p1 = true,
    idle_show_p2 = true,
    idle_raw_p1 = false,
    idle_raw_p2 = false,
    idle_mirror_p1 = false,
    idle_mirror_p2 = false,
    idle_pos_p1 = { x = 0.050, y = 0.350 },
    idle_pos_p2 = { x = 0.850, y = 0.350 },
    idle_max_history = 10,
    raw_max_history = 19,
    idle_raw_max_history = 19,

    -- Raw Input display settings (shared across all modes)
    raw = {
        icon_size     = 0.030,
        font_size     = 0.028,
        spacing_y     = 0.040,
        text_y_offset = 0.002,
        col_frame     = 0.000,
        col_dir       = 0.050,
        slot1         = 0.100,
        slot2         = 0.140,
        slot3         = 0.180,
        slot4         = 0.220,
        slot5         = 0.260,
        slot6         = 0.300,
    },

    show_live_single_p1 = true,
    show_live_single_p2 = true,
    pos_live_single_p1 = { x = 0.050, y = 0.800 },
    pos_live_single_p2 = { x = 0.850, y = 0.800 },

    pos_trial_header = { x = 0.500, y = 0.050 },
    pos_combo_stats = { x = 0.500, y = 0.085 },
    fail_display_frames = 120,

    -- HUD Overlay (text on native lines, same positions as HitConfirm)
    hud_global_y = -0.337,
    hud_spacing_y = 0.028,
    hud_show = true,
    hud_font_size = 20,

    colors = {
        shadow             = 0xFF000000,
        text_live          = 0xFF00FFFF,
        text_normal        = 0xFFFFFFFF,
        text_cond          = 0xFFFFCC00,
        text_dark          = 0xFF888888,
        text_dr            = 0xFF00FF00,
        bg_active          = 0xA0601070,
        bg_active_line     = 0xFFD030F0,
        bg_success         = 0x25A03080,
        bg_success_line    = 0xFFD050B0,
        bg_fail            = 0x90600000,
        bg_fail_line       = 0xFFB00000,
        bg_overlay         = 0x85000000, -- Dark shadow for fails
        bg_overlay_success = 0x40D050B0  -- NEW: Light pink tint for completed steps
    }
}

local function load_d2d_config()
    local loaded = _G.safe_load_json(D2D_CONFIG_FILE)
    if loaded then
        for k, v in pairs(loaded) do
            if type(v) == "table" and type(d2d_cfg[k]) == "table" then
                for k2, v2 in pairs(v) do d2d_cfg[k][k2] = v2 end
            else
                d2d_cfg[k] = v
            end
        end
    end
end

local function save_d2d_config()
    return json.dump_file(D2D_CONFIG_FILE, d2d_cfg)
end
load_d2d_config()

-- =========================================================
-- COMPLETED TRIALS TRACKING (runtime file, not committed)
-- Wrapped in do..end and attached to file_system: the main chunk
-- is close to Lua's 200-local limit, so no new top-level locals.
-- =========================================================
do
    local COMPLETED_TRIALS_FILE = "TrainingComboTrials_data/CompletedTrials.json"
    local completed_trials = {}

    local function completed_trial_key(path)
        return (tostring(path or ""):gsub("\\", "/")):lower()
    end

    local function save_completed_trials()
        if fs and fs.create_dir then pcall(fs.create_dir, "TrainingComboTrials_data") end
        json.dump_file(COMPLETED_TRIALS_FILE, completed_trials)
    end

    file_system.is_trial_completed = function(path)
        local key = completed_trial_key(path)
        return key ~= "" and completed_trials[key] == true
    end

    file_system.mark_trial_completed = function(path)
        local key = completed_trial_key(path)
        if key == "" or completed_trials[key] then return false end
        completed_trials[key] = true
        save_completed_trials()
        return true
    end

    file_system.clear_completed_trials = function()
        completed_trials = {}
        save_completed_trials()
    end

    if type(_G.safe_load_json) == "function" then
        local ok, loaded = pcall(_G.safe_load_json, COMPLETED_TRIALS_FILE)
        if ok and type(loaded) == "table" then
            for key, value in pairs(loaded) do
                if type(key) == "string" and value then completed_trials[key] = true end
            end
        end
    end
end


-- =========================================================
-- SHARED CONTEXT & D2D MODULE
-- =========================================================
local ctx = {
    d2d_cfg = d2d_cfg,
    trial_state = trial_state,
    players = players,
    file_system = file_system,
    ui_state = ui_state,
    demo_state = demo_state,
    sf6_menu_state = nil, -- set later when sf6_menu_state is created
    cached_sw = 1920,
    cached_sh = 1080,
}

ctx.stop_demo_playback = function(reason, old_file, new_file, stop_trial)
    if not demo_state then return end
    local old_sequence_len = (type(demo_state.sequence) == "table") and #demo_state.sequence or 0
    local was_playing = demo_state.is_playing == true
    local old_play_index = demo_state.current_step or 1
    local old_frame = demo_state.current_frame or 0
    local had_demo_state = was_playing or old_sequence_len > 0 or (demo_state.p1_mask or 0) ~= 0
    if not had_demo_state then return end

    demo_state.is_playing = false
    trial_state._demo_timing_ui_baseline = false
    demo_state.current_frame = 0
    demo_state.current_step = 1
    demo_state.countdown = 0
    demo_state.sequence = {}
    demo_state.p1_mask = 0
    demo_state._last_tick_frame = nil
    demo_state._state_reinjected = false
    demo_state._total_frames = 0
    demo_state._piyo_waiting = false
    demo_state._piyo_triggered = false
    demo_state.current_file = nil
    demo_state.current_file_path = nil
    demo_state.current_file_name = nil

    if stop_trial == true then
        trial_state.is_playing = false
        trial_state._was_playing = false
        trial_state.success_timer = 0
        trial_state.fail_timer = 0
        trial_state.fail_reason = nil
        trial_state.manual_reset_pending = false
        trial_state.pending_auto_check = nil
        trial_state._pending_current_absorb = nil
    end
    clear_pending_position_injection()

    if rawget(_G, "CT_DEMO_TRACE") == true then
        local old_name = tostring(old_file or ""):match("([^/\\]+)$") or tostring(old_file or "")
        local new_name = tostring(new_file or ""):match("([^/\\]+)$") or tostring(new_file or "")
        pcall(print, string.format(
            "[ComboTrials.Demo] event=auto_demo_stopped reason=%s old_trial_name=%s new_trial_name=%s old_file=%s new_file=%s was_playing=%s old_play_index=%s old_frame=%s cleared_buffer=%s",
            tostring(reason or "manual_stop"),
            tostring(old_name),
            tostring(new_name),
            tostring(old_file or ""),
            tostring(new_file or ""),
            tostring(was_playing),
            tostring(old_play_index),
            tostring(old_frame),
            tostring(old_sequence_len > 0)
        ))
    end
end

ctx.on_combo_file_change = function(info)
    info = info or {}
    local old_file = info.old_file or trial_state.current_file_path or trial_state.current_file
    local new_file = info.new_file
    local reason = info.reason or "trial_changed"
    local same_file = old_file and new_file and tostring(old_file) == tostring(new_file)
    if same_file and reason == "trial_changed" and info.force ~= true then return end
    ctx.stop_demo_playback(reason, old_file, new_file, true)
end

local ComboTrials_D2D = require("func/ComboTrials_D2D")
ComboTrials_D2D.init(ctx)

-- (D2D rendering code is now in ComboTrials_D2D.lua)

-- =========================================================
-- ORIGINAL COMMAND LOGGER (CONTINUED)
-- =========================================================

-- Player info from shared hook (0_SharedHooks.lua)
re.on_frame(function()
    if _G._shared_player_info then
        for i = 0, 1 do
            local info = _G._shared_player_info[i]
            if info and info.key then
                players[i].profile_name = esf_names_map[info.key] or "Unknown"
            end
        end
    end
end)

local act_id_reverse_enum = {}
do
    local td = sdk.find_type_definition("nBattle.ACT_ID")
    if td then
        for _, field in ipairs(td:get_fields()) do
            if field:is_static() and field:get_data() ~= nil then act_id_reverse_enum[field:get_data()] = field:get_name() end
        end
    end
end

local function get_exc_filename(name)
    return CharacterRules.get_exception_filename(name)
end

local function format_charge_motion(notation)
    local opposite = { ["6"] = "4", ["8"] = "2", ["4"] = "6", ["2"] = "8", ["9"] = "1", ["3"] = "7" }
    if #notation == 2 then
        local release = notation:sub(1, 1); local press = notation:sub(2, 2); local hold = opposite[press]
        if hold then return "[" .. hold .. "]" .. press end
    end
    return notation
end

local function decode_button_mask(mask)
    local parts = {}
    if (mask & 16) ~= 0 then table.insert(parts, "LP") end
    if (mask & 32) ~= 0 then table.insert(parts, "MP") end
    if (mask & 64) ~= 0 then table.insert(parts, "HP") end
    if (mask & 128) ~= 0 then table.insert(parts, "LK") end
    if (mask & 256) ~= 0 then table.insert(parts, "MK") end
    if (mask & 512) ~= 0 then table.insert(parts, "HK") end
    return table.concat(parts, "+")
end

local function decode_ok_key(ok_key, ok_key_cond)
    local btn_count = ((ok_key_cond >> 6) & 3) + 1
    if ok_key == 144 then return "Throw" end
    if ok_key == 288 then return "Parry" end
    if ok_key == 576 then return "DI" end

    local base_btn = ""
    if ok_key == 112 then
        if btn_count == 3 then base_btn = "PPP" elseif btn_count == 2 then base_btn = "PP" else base_btn = "P" end
    elseif ok_key == 896 then
        if btn_count == 3 then base_btn = "KKK" elseif btn_count == 2 then base_btn = "KK" else base_btn = "K" end
    else
        base_btn = decode_button_mask(ok_key)
    end
    return base_btn
end

local function build_bcm_cache(player_idx)
    local gBattle = _td_gBattle
    if not gBattle then return false end
    local cmd_obj = gBattle:get_field("Command"):get_data(nil)
    if not cmd_obj then return false end

    local cmd_data = {}
    pcall(function()
        local pCommand = cmd_obj:get_field("mpBCMResource")[player_idx]:get_field("pCommand")
        for i, entry in pairs(pCommand._entries) do
            if entry and entry.value then
                local cmds = entry.value:get_elements()
                for ci = 1, #cmds do
                    local c = cmds[ci]
                    if c then
                        local inum = c:get_field("input_num")
                        local charge_bit = c:get_field("charge_bit")
                        if inum and inum > 0 then
                            local dirs, has_charge, elems = {}, false, c:get_field("inputs"):get_elements()
                            for j = 1, math.min(#elems, inum) do
                                pcall(function()
                                    table.insert(dirs,
                                        DIR_MAP[elems[j]:get_field("normal"):get_field("ok_key_flags") & 0xF] or "5")
                                    if elems[j]:get_field("charge"):get_field("id") > 0 then has_charge = true end
                                end)
                            end
                            local raw_motion = table.concat(dirs, "")
                            raw_motion = raw_motion:gsub("23626", "236236"):gsub("21424", "214214"):gsub("626", "623")
                                :gsub("424", "421"):gsub("6314", "63214"):gsub("4136", "41236")
                            if has_charge or (charge_bit and charge_bit ~= 0) then
                                raw_motion = format_charge_motion(
                                    raw_motion)
                            end
                            if not cmd_data[entry.key] then cmd_data[entry.key] = raw_motion end
                        end
                    end
                end
            end
        end
    end)

    local cache = {}
    local mask_cache = {}
    local trigger_count = 0
    pcall(function()
        local trigs = cmd_obj:call("get_mUserEngine")[player_idx]:call("GetTrigger()"):get_elements()
        for i = 1, #trigs do
            local t = trigs[i]
            if t then
                local aid = t.action_id
                if aid > 0 then
                    local norm_ng = false
                    pcall(function() norm_ng = t:get_field("norm_NG") == true end)

                    local cmd_src = nil
                    if not norm_ng then
                        pcall(function() cmd_src = t:get_field("norm") end)
                    else
                        local use_sprt, sprt_ng = false, true
                        pcall(function() use_sprt = t:get_field("use_sprt") == true end)
                        pcall(function() sprt_ng = t:get_field("sprt_NG") == true end)
                        if use_sprt and not sprt_ng then pcall(function() cmd_src = t:get_field("sprt") end) end
                    end

                    if cmd_src then
                        local ok_key = cmd_src:get_field("ok_key_flags") or 0
                        local cmd_no = cmd_src:get_field("command_no") or -1
                        local ok_key_cond = cmd_src:get_field("ok_key_cond_flags") or 0
                        local dc_exc = cmd_src:get_field("dc_exc_flags") or 0

                        local btn = decode_ok_key(ok_key, ok_key_cond)


                        local owner_state = t:get_field("cond_owner_state_flags") or 0
                        local cat_flags = t:get_field("category_flags") or 0
                        local is_air = (owner_state == 4) or ((cat_flags & 0x40000000) ~= 0)
                        local air_prefix = is_air and "j." or ""

                        local new_str = ""
                        if cmd_no >= 0 and cmd_data[cmd_no] then
                            new_str = air_prefix .. cmd_data[cmd_no] .. (btn ~= "" and "+" .. btn or "")
                        else
                            local req_dir = ""
                            local exc_dir_bit = dc_exc & 0xF
                            if exc_dir_bit ~= 0 and exc_dir_bit ~= 5 then
                                req_dir = DIR_MAP[exc_dir_bit] or ""
                            else
                                local ok_dir_bit = ok_key & 0xF
                                if ok_dir_bit ~= 0 and ok_dir_bit ~= 15 and ok_dir_bit ~= 5 then
                                    req_dir = DIR_MAP
                                        [ok_dir_bit] or ""
                                end
                            end
                            new_str = air_prefix .. req_dir .. (btn ~= "" and btn or "Normal")
                        end

                        if not cache[aid] then
                            cache[aid] = new_str
                        end
                        mask_cache[aid] = (mask_cache[aid] or 0) | ok_key
                        trigger_count = trigger_count + 1
                    end
                end
            end
        end
    end)

    if trigger_count < 10 then return false end
    players[player_idx].bcm_cache = cache
    players[player_idx].trigger_mask_cache = mask_cache
    players[player_idx].cache_built = true
    return true
end

local skip_fields = {
    ["Owner"] = true,
    ["OwnerAdrs"] = true,
    ["mpOwner"] = true,
    ["ActionPart"] = true,
    ["_Engine"] = true,
    ["_EngineAdrs"] = true,
    ["pPlayer"] = true,
    ["Battle"] = true,
    ["Collision"] = true,
    ["Place"] = true,
    ["PartsParam"] = true,
    ["VFXSpawnID"] = true
}

local function dump_object(obj, depth, max_depth, visited)
    if not obj then return "null" end
    if type(obj) ~= "userdata" then return tostring(obj) end
    if depth > max_depth then return "<Max Depth Reached>" end

    pcall(function() obj = sdk.to_managed_object(obj) or obj end)

    local ptr_str = tostring(obj)
    if visited[ptr_str] then return "<Already explored>" end
    visited[ptr_str] = true

    local tdef = obj:get_type_definition()
    if not tdef then return tostring(obj) end

    local tname = tdef:get_name()
    if tname == "sfix" or tname == "Sfix" then
        local val = "unknown"
        pcall(function() val = tostring(tdef:get_field("v"):get_data(obj)) end)
        return "sfix(" .. val .. ")"
    end

    local data = {}
    data["_type"] = tname

    local is_array = false
    pcall(function() if obj.get_elements then is_array = true end end)

    if is_array then
        local s, elements = pcall(function() return obj:get_elements() end)
        if s and elements then
            local arr = {}
            for i = 1, math.min(#elements, 25) do
                if elements[i] ~= nil then
                    table.insert(arr, dump_object(elements[i], depth + 1, max_depth, visited))
                end
            end
            if #elements > 25 then table.insert(arr, "<... and " .. tostring(#elements - 25) .. " more>") end
            data["_elements"] = arr
            return data
        end
    end

    while tdef do
        for _, f in ipairs(tdef:get_fields()) do
            local fname = f:get_name()
            if not skip_fields[fname] and not data[fname] then
                local s, v = pcall(function() return f:get_data(obj) end)
                if s and v ~= nil then
                    data[fname] = dump_object(v, depth + 1, max_depth, visited)
                end
            end
        end
        tdef = tdef:get_parent_type()
    end

    return data
end

local function capture_deep_action_data(p_char)
    local dump = {}
    pcall(function()
        local visited = {}
        local act_param = p_char:get_field("mpActParam")
        if act_param then
            local branch = act_param:get_field("Branch")
            if branch then dump.ActParam_Branch = dump_object(branch, 0, 5, visited) end

            local trigger = act_param:get_field("Trigger")
            if trigger then dump.ActParam_Trigger = dump_object(trigger, 0, 5, visited) end

            local action_part = act_param:get_field("ActionPart")
            if action_part then
                local engine = action_part:get_field("_Engine")
                if engine then
                    local mParam = engine:get_field("mParam")
                    if mParam then
                        local action_obj = mParam:get_field("action")
                        if action_obj then
                            local keys = action_obj:get_field("Keys")
                            if keys then dump.Engine_Keys = dump_object(keys, 0, 5, visited) end
                        end
                    end
                end
            end
        end
    end)
    return dump
end

local function get_elements_safe(obj)
    if not obj then return nil end
    local s, arr = pcall(function() return obj:get_elements() end)
    if s and arr then return arr end
    pcall(function()
        local items = obj:get_field("_items")
        if items then arr = items:get_elements() end
    end)
    return arr
end

local function auto_detect_charge_min(p_char)
    local min_frame = nil
    pcall(function()
        local engine = p_char:get_field("mpActParam"):get_field("ActionPart"):get_field("_Engine")
        local keys_obj = engine:get_field("mParam"):get_field("action"):get_field("Keys")

        local groups = get_elements_safe(keys_obj)
        if groups then
            for _, group in ipairs(groups) do
                local keys = get_elements_safe(group)
                if keys then
                    for _, key in ipairs(keys) do
                        local tdef = key:get_type_definition()
                        if tdef and tdef:get_name() == "BranchKey" then
                            local type_val = key:get_field("Type")
                            if type_val and tonumber(type_val) == 100 then
                                local p00_val = key:get_field("Param00") or 0
                                if tonumber(p00_val) == 0 then
                                    local af_val = key:get_field("ActionFrame")
                                    if af_val then
                                        min_frame = tonumber(af_val)
                                        return min_frame
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end)
    return min_frame
end

local function get_luke_charge_windows(p_char)
    local windows = { perfect_min = nil, perfect_max = nil }
    pcall(function()
        local engine = p_char:get_field("mpActParam"):get_field("ActionPart"):get_field("_Engine")
        local keys_obj = engine:get_field("mParam"):get_field("action"):get_field("Keys")

        local groups = get_elements_safe(keys_obj)
        if groups then
            local frames_by_act = {}
            for _, group in ipairs(groups) do
                local keys = get_elements_safe(group)
                if keys then
                    for _, key in ipairs(keys) do
                        local tdef = key:get_type_definition()
                        if tdef and tdef:get_name() == "BranchKey" then
                            local type_val = key:get_field("Type")
                            if type_val and tonumber(type_val) == 100 then
                                local act = tonumber(key:get_field("Action"))
                                local frm = tonumber(key:get_field("ActionFrame"))
                                if act and frm then
                                    if not frames_by_act[act] then frames_by_act[act] = {} end
                                    frames_by_act[act][frm] = true
                                end
                            end
                        end
                    end
                end
            end

            for act, frames in pairs(frames_by_act) do
                local min_f, max_f = 9999, -1
                local count = 0
                for f, _ in pairs(frames) do
                    if f < min_f then min_f = f end
                    if f > max_f then max_f = f end
                    count = count + 1
                end
                if count >= 2 then
                    windows.perfect_min = min_f
                    windows.perfect_max = max_f
                end
            end
        end
    end)
    return windows
end

-- Hoisted hot-path helper (no per-call closure). Scratch table preserves
-- partial-write semantics if an SDK call errors mid-body.
local _ct_action_scratch = { act_id = -1, frame = 0, state_flags = -1, action_code = 0, direct_input = 0, branch_type = 0 }
local function _ct_read_action_data(p_obj)
    local r = _ct_action_scratch
    local p_def = p_obj:get_type_definition()
    local d = (p_def:get_field("pl_input_new"):get_data(p_obj)) or 0
    local b = (p_def:get_field("pl_sw_new"):get_data(p_obj)) or 0
    r.direct_input = d | b

    local act_param = p_obj:get_field("mpActParam")
    if not act_param then return end
    local action_part = act_param:get_field("ActionPart")
    if action_part then
        local engine = action_part:get_field("_Engine")
        if engine then
            r.act_id = engine:call("get_ActionID") or -1
            local sf = engine:call("get_ActionFrame")
            if sf then r.frame = tonumber(sf:call("ToString()")) or 0 end
            local m_param = engine:get_field("mParam")
            if m_param then
                local sf_field = m_param:get_type_definition():get_field("state_flags")
                if sf_field then r.state_flags = tonumber(sf_field:get_data(m_param)) or -1 end
            end
        end
    end
    local ki_field = act_param:get_type_definition():get_field("KeyInput")
    if ki_field then
        local ki_data = ki_field:get_data(act_param)
        if ki_data then
            local a_field = ki_data:get_type_definition():get_field("Action")
            if a_field then r.action_code = tonumber(a_field:get_data(ki_data)) or 0 end
        end
    end
    local branch = act_param:get_field("Branch")
    if branch then
        local bt_field = branch:get_type_definition():get_field("BranchType")
        if bt_field then r.branch_type = tonumber(bt_field:get_data(branch)) or 0 end
    end
end

local function get_action_data(p_obj)
    if not p_obj then return -1, 0, -1, 0, 0, 0 end
    local r = _ct_action_scratch
    r.act_id, r.frame, r.state_flags, r.action_code, r.direct_input, r.branch_type = -1, 0, -1, 0, 0, 0
    pcall(_ct_read_action_data, p_obj)
    return r.act_id, r.frame, r.state_flags, r.action_code, r.direct_input, r.branch_type
end

local function get_damage_type_safe(p_char)
    if not p_char then return 0 end

    local result = 0
    pcall(function()
        -- Direct syntax via REFramework's syntactic sugar
        local act_val = tonumber(p_char.act_st)

        if act_val == 27 or act_val == 32 or act_val == 35 or act_val == 38 then
            result = 1
        end
    end)

    return result
end

local function check_is_projectile(attacker_idx, attacker_obj, gBattle)
    local attacker_hs = 0
    pcall(function()
        local f_hs = attacker_obj:get_type_definition():get_field("hit_stop")
        if f_hs then attacker_hs = f_hs:get_data(attacker_obj) or 0 end
    end)
    return (attacker_hs == 0)
end

local function _ct_read_combo_cnt(p_obj)
    return p_obj:get_type_definition():get_field("combo_cnt"):get_data(p_obj) or 0
end
local function get_combo_count(p_obj)
    if not p_obj then return 0 end
    local s, res = pcall(_ct_read_combo_cnt, p_obj)
    return s and res or 0
end

function normalize_hp_value(value)
    local n = tonumber(value)
    if n == nil then return nil end
    return math.floor(n + 0.5)
end

function read_player_hp_snapshot(player)
    if not player then return nil end
    local current_hp, max_hp, heal_hp = nil, nil, nil
    pcall(function() current_hp = normalize_hp_value(player.vital_new) end)
    pcall(function() max_hp = normalize_hp_value(player.vital_max) end)
    pcall(function() heal_hp = normalize_hp_value(player.heal_new) end)
    if current_hp == nil then return nil end
    if max_hp == nil or max_hp <= 0 then max_hp = current_hp end

    local snapshot = {
        current_hp = current_hp,
        max_hp = max_hp
    }
    if heal_hp ~= nil then snapshot.heal_hp = heal_hp end
    return snapshot
end

function hp_snapshot_is_damaged(snapshot)
    if type(snapshot) ~= "table" then return false end
    local current_hp = tonumber(snapshot.current_hp)
    local max_hp = tonumber(snapshot.max_hp)
    return current_hp ~= nil and max_hp ~= nil and current_hp < max_hp
end

function copy_hp_snapshot(snapshot)
    if type(snapshot) ~= "table" then return nil end
    local current_hp = normalize_hp_value(snapshot.current_hp)
    if current_hp == nil then return nil end
    local out = { current_hp = current_hp }
    local max_hp = normalize_hp_value(snapshot.max_hp)
    local heal_hp = normalize_hp_value(snapshot.heal_hp)
    if max_hp ~= nil then out.max_hp = max_hp end
    if heal_hp ~= nil then out.heal_hp = heal_hp end
    return out
end

function capture_trial_hp_snapshot(attacker_idx)
    local victim_idx = 1 - attacker_idx
    local attacker = (attacker_idx == 0) and GS.p1 or GS.p2
    local victim = (victim_idx == 0) and GS.p1 or GS.p2
    if not attacker or not victim then return nil end
    return {
        attacker = read_player_hp_snapshot(attacker),
        victim = read_player_hp_snapshot(victim)
    }
end

-- Gauge snapshot (same pattern as SheldonsBoxes)
-- attacker_idx = 0 or 1 (the player performing the combo)
local function snapshot_gauges(attacker_idx)
    local result = nil
    pcall(function()
        local victim_idx = 1 - attacker_idx
        local victim = (victim_idx == 0) and GS.p1 or GS.p2
        local attacker = (attacker_idx == 0) and GS.p1 or GS.p2
        if not victim or not attacker then return end
        local gB = _td_gBattle
        if not gB then return end
        local BT = gB:get_field("Team"):get_data(nil)
        if not BT or not BT.mcTeam then return end

        local atk_team = BT.mcTeam[attacker_idx]

        if not victim or not attacker or not atk_team then return end

        local v_hp = victim.vital_new
        local a_dr = attacker.focus_new
        local a_sa = atk_team.mSuperGauge
        local d_dr = victim.focus_new
        local hp_snapshot = capture_trial_hp_snapshot(attacker_idx)
        local d_burnout = nil
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        local t_data = tm and tm:get_field("_tData")
        local parameter_setting = t_data and t_data:get_field("ParameterSetting")
        local player_datas = parameter_setting and parameter_setting.PlayerDatas
        local defender_params = player_datas and player_datas[victim_idx]
        if defender_params and defender_params.Is_DG_Break ~= nil then
            d_burnout = defender_params.Is_DG_Break == true or defender_params.Is_DG_Break == 1
        end

        if v_hp == nil or a_dr == nil or a_sa == nil then return end

        result = {
            victim_hp = v_hp,
            attacker_drive = a_dr,
            attacker_super = a_sa,
            defender_drive = d_dr,
            defender_burnout = d_burnout,
            hp_attacker = hp_snapshot and hp_snapshot.attacker or nil,
            hp_victim = hp_snapshot and hp_snapshot.victim or nil,
            -- Min trackers (updated each frame in on_frame)
            min_victim_hp = v_hp,
            min_atk_drive = a_dr,
            min_atk_super = a_sa
        }
    end)
    return result
end

function clear_trial_vital_state()
    trial_state._pending_victim_hp = nil
    trial_state._pending_attacker_hp = nil
    trial_state._hp_inject_frames = 0
    trial_state._saved_vital_p1 = nil
    trial_state._saved_vital_p2 = nil
end

-- Combo playback must use the training room's current health settings.
function apply_trial_vital()
    clear_trial_vital_state()
end

function reinject_trial_vital()
    clear_trial_vital_state()
end

DRIVE_SETTING_FIELDS = {
    "DG_Type",
    "DG_Stock",
    "DG_Point",
    "Is_DG_Point_Lock",
    "Is_DG_Break",
    "Is_DG_Recovery_Timer",
    "DG_Timer"
}

function restore_trial_vital(skip_hp_setting_restore)
    clear_trial_vital_state()
    if skip_hp_setting_restore ~= true and type(restore_hp_training_setting_if_needed) == "function" then
        restore_hp_training_setting_if_needed("restore_trial_vital", trial_state.playing_player)
    end

    local saved_drive_settings = trial_state._saved_drive_settings
    if type(saved_drive_settings) ~= "table" then return end

    local tm = sdk.get_managed_singleton("app.training.TrainingManager")
    if not tm then return end

    local t_data = tm:get_field("_tData")
    if not t_data then return end

    local parameter_setting = t_data:get_field("ParameterSetting")
    if not parameter_setting then return end

    local player_datas = parameter_setting.PlayerDatas
    if not player_datas then return end

    local changed = false
    for idx, settings in pairs(saved_drive_settings) do
        local params = player_datas[idx]
        if params and type(settings) == "table" then
            for _, field_name in ipairs(DRIVE_SETTING_FIELDS) do
                if settings[field_name] ~= nil then
                    params[field_name] = settings[field_name]
                    changed = true
                end
            end
        end
    end

    trial_state._saved_drive_settings = nil
    if changed then tm._IsReqRefresh = true end
end

HP_RESTORE_DEBUG_PATH = "TrainingComboTrials_data/LastHpRestoreDebug.json"
CT_DEV_HP_TEST_TITLE = "【HP测试】Jamie attacker 1000HP"
CT_DEV_HP_TEST_FILENAME = "Jamie_DEV_HP_RESTORE_TEST_1000.json"
CT_DEV_HP_TEST_PATH = "TrainingComboTrials_data/CustomCombos/Jamie/" .. CT_DEV_HP_TEST_FILENAME
ct_dev_hp_restore_test_state = {
    enabled = CT_DEV_HP_RESTORE_TEST == true,
    test_json_path = CT_DEV_HP_TEST_PATH,
    test_title = CT_DEV_HP_TEST_TITLE,
    source_template_path = nil,
    test_json_write_ok = false,
    test_json_write_error = nil,
    attempted = false,
    attempt_count = 0
}

function read_player_hp_fields_for_debug(player)
    if not player then return { missing_player = true } end
    local out = {}
    local ok
    ok, out.vital_new = pcall(function() return player.vital_new end)
    out.vital_new_ok = ok == true
    ok, out.vital_old = pcall(function() return player.vital_old end)
    out.vital_old_ok = ok == true
    ok, out.heal_new = pcall(function() return player.heal_new end)
    out.heal_new_ok = ok == true
    ok, out.vital_max = pcall(function() return player.vital_max end)
    out.vital_max_ok = ok == true
    return out
end

VITAL_PARAM_FIELDS = {
    "Vital_Type",
    "Vital_Point",
    "Vital_Point_Type",
    "Vital_Timer",
    "Is_Vital_Infinity",
    "Is_Vital_No_Recovery",
    "Is_Vital_Recovery_Timer",
    "Is_KO",
    "Is_Point_Lock"
}

function read_player_vital_params_for_debug(player_params)
    if not player_params then return { missing_player_params = true } end
    local out = {}
    for _, field_name in ipairs(VITAL_PARAM_FIELDS) do
        local ok, value = pcall(function() return player_params[field_name] end)
        out[field_name] = ok and value or nil
        out[field_name .. "_ok"] = ok == true
    end
    return out
end

function hp_snapshot_to_vital_point(snapshot)
    if type(snapshot) ~= "table" then return nil end
    local current_hp = tonumber(snapshot.current_hp)
    if current_hp == nil then return nil end
    local max_hp = tonumber(snapshot.max_hp)
    local point = nil
    if max_hp ~= nil and max_hp > 0 then
        point = math.floor((current_hp * 100 / max_hp) + 0.5)
    elseif current_hp >= 0 and current_hp <= 100 then
        point = math.floor(current_hp + 0.5)
    end
    if point == nil then return nil end
    if point < 0 then point = 0 end
    if point > 100 then point = 100 end
    return point
end

_tf_parameter_setting_cache = nil
function get_tf_parameter_setting()
    if _tf_parameter_setting_cache then return _tf_parameter_setting_cache end
    local fallback = nil
    pcall(function()
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        if not tm then return end
        local dict = tm:get_field("_tfFuncs")
        if not dict then return end
        local entries = dict:get_field("_entries")
        if not entries then return end
        pcall(function()
            local entry = entries:call("get_Item", 6)
            fallback = entry and entry:get_field("value") or nil
        end)
        local count = entries:call("get_Count")
        for i = 0, count - 1 do
            local entry = entries:call("get_Item", i)
            local val = entry and entry:get_field("value") or nil
            if val then
                local td = val:get_type_definition()
                local full_name = td and td:get_full_name() or ""
                if full_name:find("tf_ParameterSetting") or full_name:find("ParameterSetting") then
                    _tf_parameter_setting_cache = val
                    return
                end
            end
        end
    end)
    _tf_parameter_setting_cache = _tf_parameter_setting_cache or fallback
    return _tf_parameter_setting_cache
end

function describe_re_object_for_debug(obj)
    if not obj then return nil end
    local ok, name = pcall(function()
        local td = obj:get_type_definition()
        return td and td:get_full_name() or nil
    end)
    return ok and name or nil
end

function get_training_parameter_probe_objects(attacker_idx)
    local out = {
        attacker_idx = attacker_idx,
        attacker_label = attacker_idx == 1 and "p2" or "p1"
    }
    pcall(function()
        out.tm = sdk.get_managed_singleton("app.training.TrainingManager")
        if not out.tm then return end
        out.training_data = out.tm:get_field("_tData")
        if not out.training_data then return end
        out.parameter_setting = out.training_data:get_field("ParameterSetting")
        if out.parameter_setting then
            pcall(function() out.param_func = out.parameter_setting:get_field("ParamFunc") end)
            if not out.param_func then pcall(function() out.param_func = out.parameter_setting.ParamFunc end) end
            local player_datas = out.parameter_setting.PlayerDatas
            out.player_params = player_datas and player_datas[attacker_idx] or nil
        end
        if not out.param_func then
            pcall(function() out.param_func = out.training_data:get_field("ParamFunc") end)
            if not out.param_func then pcall(function() out.param_func = out.training_data.ParamFunc end) end
        end
        out.tf_ps = get_tf_parameter_setting()
    end)
    return out
end

function probe_method_exists(obj, method_name)
    if not obj then return false, "missing_object" end
    local ok, method = pcall(function()
        local td = obj:get_type_definition()
        return td and td:get_method(method_name) or nil
    end)
    if not ok then return false, tostring(method) end
    return method ~= nil, method ~= nil and nil or "missing_method"
end

function ct_hp_copy_vital_setting_fields(player_params)
    local fields = {}
    if not player_params then return fields end
    for _, field_name in ipairs(VITAL_PARAM_FIELDS) do
        local ok, value = pcall(function() return player_params[field_name] end)
        if ok and value ~= nil then fields[field_name] = value end
    end
    return fields
end

function ct_hp_backup_training_setting_once(player_idx, phase)
    player_idx = tonumber(player_idx or 0) or 0
    if player_idx ~= 1 then player_idx = 0 end

    if type(trial_state._hp_training_setting_backup) ~= "table" then
        trial_state._hp_training_setting_backup = {
            has_backup = false,
            players = {}
        }
    end

    local backup = trial_state._hp_training_setting_backup
    backup.players = backup.players or {}
    if type(backup.players[player_idx]) == "table" then
        return backup.players[player_idx]
    end

    local objects = get_training_parameter_probe_objects(player_idx)
    local fields = ct_hp_copy_vital_setting_fields(objects.player_params)
    local item = {
        player_index = player_idx,
        player_side = player_idx == 1 and "p2" or "p1",
        fields = fields,
        has_backup = next(fields) ~= nil,
        backup_source_phase = phase,
        before = read_player_vital_params_for_debug(objects.player_params)
    }
    backup.players[player_idx] = item
    backup.has_backup = backup.has_backup or item.has_backup
    backup.player_index = backup.player_index or player_idx
    backup.player_side = backup.player_side or item.player_side
    backup.fields = backup.fields or fields
    backup.backup_source_phase = backup.backup_source_phase or phase
    return item
end

function ct_hp_write_vital_setting_fields(player_params, fields)
    local result = { ok = true, errors = {} }
    if not player_params then
        result.ok = false
        result.errors.missing_player_params = true
        return result
    end
    for field_name, value in pairs(fields or {}) do
        local ok, err = pcall(function() player_params[field_name] = value end)
        if not ok then
            result.ok = false
            result.errors[field_name] = tostring(err)
        end
    end
    return result
end

function ct_hp_default_full_vital_fields()
    return {
        Vital_Point = 100,
        Is_Vital_Infinity = false,
        Is_Vital_No_Recovery = false,
        Is_Vital_Recovery_Timer = false,
        Is_KO = false,
        Is_Point_Lock = false
    }
end

function restore_hp_training_setting_if_needed(reason, preferred_player_idx)
    local backup = trial_state._hp_training_setting_backup
    local had_backup = type(backup) == "table" and backup.has_backup == true and type(backup.players) == "table"
    local applied = trial_state._hp_snapshot_applied_current_session == true
    local debug = {
        called = false,
        reason = reason,
        had_backup = had_backup,
        hp_snapshot_applied_current_session = applied,
        switching_from_hp_snapshot_to_plain_trial = (reason or ""):find("plain_trial", 1, true) ~= nil and (had_backup or applied),
        restores = {}
    }

    if not had_backup and not applied then
        debug.skip_reason = "no_hp_snapshot_state"
        trial_state._hp_setting_restore_debug = debug
        if type(write_hp_restore_debug_dump) == "function" then
            pcall(write_hp_restore_debug_dump, "hp_setting_restore_skipped", { hp_setting_restore = debug })
        end
        return debug
    end

    debug.called = true
    local restored_any = false
    local bapply_target = nil

    if had_backup then
        for player_idx, item in pairs(backup.players) do
            local idx = tonumber(player_idx) or tonumber(item.player_index or 0) or 0
            if idx ~= 1 then idx = 0 end
            local objects = get_training_parameter_probe_objects(idx)
            local restore_item = {
                player_index = idx,
                player_side = idx == 1 and "p2" or "p1",
                fields = item.fields or {},
                before = read_player_vital_params_for_debug(objects.player_params)
            }
            local write_result = ct_hp_write_vital_setting_fields(objects.player_params, item.fields or {})
            restore_item.write_ok = write_result.ok == true
            restore_item.write_errors = write_result.errors
            restore_item.after = read_player_vital_params_for_debug(objects.player_params)
            table.insert(debug.restores, restore_item)
            debug.player_index = debug.player_index or idx
            debug.player_side = debug.player_side or restore_item.player_side
            debug.fields = debug.fields or restore_item.fields
            debug.before = debug.before or restore_item.before
            debug.after = debug.after or restore_item.after
            restored_any = true
            bapply_target = bapply_target or objects.tf_ps
        end
    else
        local idx = tonumber(preferred_player_idx or trial_state.playing_player or 0) or 0
        if idx ~= 1 then idx = 0 end
        local objects = get_training_parameter_probe_objects(idx)
        local fallback_fields = ct_hp_default_full_vital_fields()
        local restore_item = {
            player_index = idx,
            player_side = idx == 1 and "p2" or "p1",
            fallback_full_hp = true,
            fields = fallback_fields,
            before = read_player_vital_params_for_debug(objects.player_params)
        }
        local write_result = ct_hp_write_vital_setting_fields(objects.player_params, fallback_fields)
        restore_item.write_ok = write_result.ok == true
        restore_item.write_errors = write_result.errors
        restore_item.after = read_player_vital_params_for_debug(objects.player_params)
        table.insert(debug.restores, restore_item)
        debug.player_index = idx
        debug.player_side = restore_item.player_side
        debug.fields = fallback_fields
        debug.before = restore_item.before
        debug.after = restore_item.after
        restored_any = true
        bapply_target = objects.tf_ps
    end

    if bapply_target then
        local bapply_ok, bapply_err = pcall(function()
            bapply_target:call("bApply")
        end)
        debug.bapply_called = true
        debug.bapply_ok = bapply_ok == true
        if not bapply_ok then debug.bapply_error = tostring(bapply_err) end
    else
        debug.bapply_called = false
        debug.bapply_ok = false
        debug.bapply_error = "missing_tf_parameter_setting"
    end

    debug.restored_any = restored_any
    if debug.bapply_ok == true then
        trial_state._hp_snapshot_applied_current_session = false
        trial_state._hp_training_setting_backup = nil
        debug.backup_cleared = true
    else
        debug.backup_cleared = false
    end
    trial_state._hp_setting_restore_debug = debug
    if type(write_hp_restore_debug_dump) == "function" then
        pcall(write_hp_restore_debug_dump, "hp_setting_restore", { hp_setting_restore = debug })
    end
    return debug
end

function current_trial_title()
    local first = trial_state.sequence and trial_state.sequence[1]
    if type(first) ~= "table" then return nil end
    local xt_meta = type(first._xt_meta) == "table" and first._xt_meta or nil
    if xt_meta and xt_meta.title then return xt_meta.title end
    local wtt_meta = type(first._wtt_cn_meta) == "table" and first._wtt_cn_meta or nil
    if wtt_meta and wtt_meta.title then return wtt_meta.title end
    return nil
end

function build_hp_restore_debug_dump(phase, extra)
    local first = trial_state.sequence and trial_state.sequence[1]
    local read_snapshot, read_skip_reason = read_attacker_hp_restore_snapshot()
    local tm = sdk.get_managed_singleton("app.training.TrainingManager")
    local target_idx = trial_state._hp_restore and trial_state._hp_restore.target_player or trial_state.playing_player or 0
    local target_player = target_idx == 1 and GS.p2 or GS.p1
    local param_probe = get_training_parameter_probe_objects(target_idx)
    local loaded_title = current_trial_title()
    local runtime_inject = extra and extra.runtime_inject or nil
    local dump = {
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
        frame = engine_frame_count or 0,
        phase = phase,
        dev_test = ct_dev_hp_restore_test_state,
        trial_file = trial_state.current_file or trial_state.current_file_path,
        trial_filename = trial_state.current_file_name,
        trial_title = loaded_title,
        loaded_trial = {
            loaded_title = loaded_title,
            loaded_filename = trial_state.current_file_name,
            sequence_length = trial_state.sequence and #trial_state.sequence or 0,
            first_step_id = type(first) == "table" and first.id or nil,
            first_step_motion = type(first) == "table" and first.motion or nil,
            first_snapshot_gauges = type(first) == "table" and first.snapshot_gauges or nil
        },
        playing_player = trial_state.playing_player,
        current_step = trial_state.current_step,
        pending_reinject_settings = trial_state._pending_reinject_settings == true,
        tm_is_req_refresh = tm and tm:get_field("_IsReqRefresh") or nil,
        first_snapshot_gauges = type(first) == "table" and first.snapshot_gauges or nil,
        read_attacker_hp_restore_snapshot = {
            snapshot = read_snapshot,
            skip_reason = read_skip_reason
        },
        snapshot_parsing = {
            snapshot_found = type(read_snapshot) == "table",
            snapshot_current_hp = read_snapshot and read_snapshot.current_hp or nil,
            snapshot_max_hp = read_snapshot and read_snapshot.max_hp or nil,
            snapshot_heal_hp = read_snapshot and read_snapshot.heal_hp or nil,
            skip_reason = read_skip_reason
        },
        hp_restore_state = trial_state._hp_restore,
        training_setting_probe = trial_state._hp_restore and trial_state._hp_restore.training_probe or nil,
        runtime_inject = runtime_inject,
        hp_setting_backup = {
            exists = type(trial_state._hp_training_setting_backup) == "table"
                and trial_state._hp_training_setting_backup.has_backup == true,
            player_index = type(trial_state._hp_training_setting_backup) == "table"
                and trial_state._hp_training_setting_backup.player_index or nil,
            fields = type(trial_state._hp_training_setting_backup) == "table"
                and trial_state._hp_training_setting_backup.fields or nil,
            players = type(trial_state._hp_training_setting_backup) == "table"
                and trial_state._hp_training_setting_backup.players or nil
        },
        hp_setting_restore = trial_state._hp_setting_restore_debug,
        hp_snapshot_applied_current_session = trial_state._hp_snapshot_applied_current_session == true,
        switching_from_hp_snapshot_to_plain_trial = trial_state._hp_setting_restore_debug
            and trial_state._hp_setting_restore_debug.switching_from_hp_snapshot_to_plain_trial or false,
        safety = {
            did_call_reset = false,
            did_call_reload = false,
            did_call_start_trial = false,
            did_set_IsReqRefresh = false,
            no_hp_snapshot_skip_old_json = read_snapshot == nil
        },
        target_player = target_idx == 1 and "p2" or "p1",
        target_player_idx = target_idx,
        target_hp_now = read_player_hp_fields_for_debug(target_player),
        target_vital_params_now = read_player_vital_params_for_debug(param_probe.player_params),
        param_func_exists = param_probe.param_func ~= nil,
        param_func_type = describe_re_object_for_debug(param_probe.param_func),
        tf_parameter_setting_exists = param_probe.tf_ps ~= nil,
        tf_parameter_setting_type = describe_re_object_for_debug(param_probe.tf_ps)
    }
    if type(extra) == "table" then
        for k, v in pairs(extra) do dump[k] = v end
    end
    return dump
end

function write_hp_restore_debug_dump(phase, extra)
    if rawget(_G, "CT_HP_RESTORE_TRACE") ~= true and CT_DEV_HP_RESTORE_TEST ~= true then return end
    local dump = build_hp_restore_debug_dump(phase, extra)
    trial_state._hp_restore_debug_file = dump
    pcall(function()
        json.dump_file(HP_RESTORE_DEBUG_PATH, dump)
    end)
end

function hp_restore_trace(event)
    if type(event) ~= "table" then return end
    event.frame = engine_frame_count or 0
    trial_state._hp_restore_debug = event
    write_hp_restore_debug_dump(event.phase or "trace", { trace_event = event })

    if rawget(_G, "CT_HP_RESTORE_TRACE") ~= true then return end
    local msg = "[HPRestore]"
        .. " phase=" .. tostring(event.phase)
        .. " token=" .. tostring(event.token)
        .. " found=" .. tostring(event.found)
        .. " restored=" .. tostring(event.restored)
        .. " retry=" .. tostring(event.retry_count)
        .. " target=" .. tostring(event.target_player)
        .. " skip=" .. tostring(event.skip_reason)
        .. " refresh_before=" .. tostring(event.refresh_before)
        .. " refresh_after=" .. tostring(event.refresh_after)
        .. " restore_count=" .. tostring(event.restore_count)
    if file_system and file_system.diag_log then
        pcall(file_system.diag_log, msg)
    else
        pcall(print, msg)
    end
end

function record_hp_restore_state(state, phase, extra)
    if type(state) ~= "table" then return end
    local event = {
        phase = phase,
        token = state.token,
        found = state.found,
        snapshot = state.snapshot,
        restored = state.restored,
        retry_count = state.retry_count,
        target_player = state.target_player,
        skip_reason = state.skip_reason,
        restore_count = state.restore_count
    }
    if type(extra) == "table" then
        for k, v in pairs(extra) do event[k] = v end
    end
    hp_restore_trace(event)
end

function read_attacker_hp_restore_snapshot()
    local first = trial_state.sequence and trial_state.sequence[1]
    if type(first) ~= "table" then return nil, "missing_first_step" end
    local gauges = first.snapshot_gauges
    if type(gauges) ~= "table" then return nil, "missing_snapshot_gauges" end
    local attacker = gauges.attacker
    if type(attacker) ~= "table" then return nil, "missing_attacker_hp_snapshot" end
    local snapshot = copy_hp_snapshot(attacker)
    if not snapshot or snapshot.current_hp == nil then return nil, "missing_attacker_current_hp" end
    return snapshot, nil
end

function init_hp_restore_attempt(phase, player_idx)
    trial_state._hp_restore_token = (trial_state._hp_restore_token or 0) + 1
    local snapshot, skip_reason = read_attacker_hp_restore_snapshot()
    local found = type(snapshot) == "table"
    local state = {
        token = trial_state._hp_restore_token,
        found = found,
        snapshot = snapshot,
        target_player = tonumber(player_idx or trial_state.playing_player or 0) or 0,
        restored = false,
        finished = not found,
        retry_count = 0,
        max_retries = 5,
        restore_count = 0,
        training_setting_applied = false,
        training_setting_apply_count = 0,
        training_refresh_request_count = 0,
        last_phase = phase,
        skip_reason = found and nil or skip_reason
    }
    trial_state._hp_restore = state
    if not found then
        local restore_debug = restore_hp_training_setting_if_needed("plain_trial_" .. tostring(phase or "attempt"), state.target_player)
        state.hp_setting_restore = restore_debug
        state.switching_from_hp_snapshot_to_plain_trial = restore_debug and restore_debug.switching_from_hp_snapshot_to_plain_trial or false
    end
    record_hp_restore_state(state, phase or "init")
end

function apply_hp_restore_training_setting_once(phase)
    local state = trial_state._hp_restore
    if type(state) ~= "table" or state.found ~= true then return false end
    if state.training_setting_applied == true then return false end

    state.training_setting_applied = true
    state.training_setting_apply_count = (state.training_setting_apply_count or 0) + 1

    local snapshot = state.snapshot
    local vital_point = hp_snapshot_to_vital_point(snapshot)
    local attacker_idx = tonumber(state.target_player or trial_state.playing_player or 0) or 0
    if attacker_idx ~= 1 then attacker_idx = 0 end

    local objects = get_training_parameter_probe_objects(attacker_idx)
    local tm = objects.tm or sdk.get_managed_singleton("app.training.TrainingManager")
    local refresh_before = tm and tm:get_field("_IsReqRefresh")
    local probe = {
        phase = phase,
        recorded_by = trial_state.sequence and trial_state.sequence[1] and trial_state.sequence[1].recorded_by or nil,
        playing_player = trial_state.playing_player,
        target_player_idx = attacker_idx,
        target_player = attacker_idx == 1 and "p2" or "p1",
        snapshot = snapshot,
        vital_point = vital_point,
        vital_point_percent = vital_point,
        param_func_exists = objects.param_func ~= nil,
        param_func_type = describe_re_object_for_debug(objects.param_func),
        tf_parameter_setting_exists = objects.tf_ps ~= nil,
        tf_parameter_setting_type = describe_re_object_for_debug(objects.tf_ps),
        player_params_exists = objects.player_params ~= nil,
        before_params = read_player_vital_params_for_debug(objects.player_params),
        refresh_before = refresh_before
    }

    probe.set_vital_point_exists, probe.set_vital_point_method_error = probe_method_exists(objects.param_func, "SetVitalPoint")
    probe.set_vital_type_exists, probe.set_vital_type_method_error = probe_method_exists(objects.param_func, "SetVitalType")
    probe.set_vital_infinity_exists, probe.set_vital_infinity_method_error = probe_method_exists(objects.param_func, "SetVitalInfinity")
    probe.set_vital_no_recovery_exists, probe.set_vital_no_recovery_method_error = probe_method_exists(objects.param_func, "SetVitalNoRecovery")

    if vital_point == nil then
        state.training_setting_skip_reason = "missing_vital_point"
        probe.skip_reason = state.training_setting_skip_reason
    elseif not objects.player_params then
        state.training_setting_skip_reason = "missing_player_params"
        probe.skip_reason = state.training_setting_skip_reason
    else
        probe.hp_setting_backup = ct_hp_backup_training_setting_once(attacker_idx, phase)
        if objects.param_func then
            probe.set_vital_point_called = true
            local call_ok, call_result = pcall(function()
                return objects.param_func:call("SetVitalPoint", attacker_idx, vital_point)
            end)
            probe.set_vital_point_call_ok = call_ok == true
            if not call_ok then probe.set_vital_point_call_error = tostring(call_result) end
        else
            probe.set_vital_point_called = false
            probe.set_vital_point_call_error = "missing_param_func"
        end

        local write_ok, write_err = pcall(function()
            objects.player_params.Vital_Point = vital_point
        end)
        probe.write_vital_point_ok = write_ok == true
        if not write_ok then probe.write_vital_point_error = tostring(write_err) end
    end

    probe.after_write_params = read_player_vital_params_for_debug(objects.player_params)

    if objects.tf_ps then
        local bapply_ok, bapply_err = pcall(function()
            objects.tf_ps:call("bApply")
        end)
        probe.bapply_called = true
        probe.bapply_ok = bapply_ok == true
        if not bapply_ok then probe.bapply_error = tostring(bapply_err) end
    else
        probe.bapply_called = false
        probe.bapply_error = "missing_tf_parameter_setting"
    end

    probe.refresh_after = tm and tm:get_field("_IsReqRefresh")
    if refresh_before ~= true and probe.refresh_after == true then
        state.training_refresh_request_count = (state.training_refresh_request_count or 0) + 1
    end
    probe.refresh_request_count = state.training_refresh_request_count or 0
    probe.after_apply_params = read_player_vital_params_for_debug(objects.player_params)
    if probe.write_vital_point_ok == true or probe.set_vital_point_call_ok == true then
        trial_state._hp_snapshot_applied_current_session = true
        state.hp_snapshot_applied_current_session = true
    end

    state.training_probe = probe
    record_hp_restore_state(state, phase or "training_setting_probe", { hp_training_probe = probe })
    return probe.write_vital_point_ok == true or probe.set_vital_point_call_ok == true
end

function apply_pending_hp_restore_once(phase)
    local state = trial_state._hp_restore
    if type(state) ~= "table" or state.finished == true then return false end
    state.last_phase = phase
    state.apply_called = true

    if state.restored == true then
        state.finished = true
        state.skip_reason = "already_restored"
        return false
    end

    local tm = sdk.get_managed_singleton("app.training.TrainingManager")
    local refresh_before = tm and tm:get_field("_IsReqRefresh")
    if refresh_before == true then
        state.skip_reason = "training_refresh_active"
        record_hp_restore_state(state, phase, { refresh_before = refresh_before })
        return false
    end

    local target = state.target_player == 1 and GS.p2 or GS.p1
    if not target then
        state.retry_count = (state.retry_count or 0) + 1
        state.skip_reason = "missing_player_object"
        if state.retry_count >= (state.max_retries or 5) then
            state.finished = true
            state.skip_reason = "retry_limit_missing_player_object"
        end
        record_hp_restore_state(state, phase, { refresh_before = refresh_before })
        return false
    end

    local hp = normalize_hp_value(state.snapshot and state.snapshot.current_hp)
    if hp == nil then
        state.finished = true
        state.skip_reason = "missing_current_hp"
        record_hp_restore_state(state, phase, { refresh_before = refresh_before })
        return false
    end

    local before = read_player_hp_snapshot(target)
    local before_fields = read_player_hp_fields_for_debug(target)
    local heal_hp = normalize_hp_value(state.snapshot.heal_hp) or hp
    local write_vital_new_ok, write_vital_new_err = pcall(function() target.vital_new = hp end)
    local write_vital_old_ok, write_vital_old_err = pcall(function() target.vital_old = hp end)
    local write_heal_new_ok, write_heal_new_err = pcall(function() target.heal_new = heal_hp end)
    local after = read_player_hp_snapshot(target)
    local after_fields = read_player_hp_fields_for_debug(target)
    local refresh_after = tm and tm:get_field("_IsReqRefresh")

    state.restored = true
    state.finished = true
    state.restore_count = (state.restore_count or 0) + 1
    state.skip_reason = nil
    local write_errors = {
        vital_new = write_vital_new_ok and nil or tostring(write_vital_new_err),
        vital_old = write_vital_old_ok and nil or tostring(write_vital_old_err),
        heal_new = write_heal_new_ok and nil or tostring(write_heal_new_err)
    }
    local runtime_inject = {
        phase = phase,
        did_call_runtime_inject = true,
        before_fields = before_fields,
        after_fields = after_fields,
        write_vital_new_ok = write_vital_new_ok == true,
        write_vital_old_ok = write_vital_old_ok == true,
        write_heal_new_ok = write_heal_new_ok == true,
        write_errors = write_errors,
        restore_count = state.restore_count
    }
    record_hp_restore_state(state, phase, {
        before = before,
        before_fields = before_fields,
        after = after,
        after_fields = after_fields,
        did_call_runtime_inject = true,
        write_results = {
            vital_new = write_vital_new_ok == true,
            vital_old = write_vital_old_ok == true,
            heal_new = write_heal_new_ok == true
        },
        write_vital_new_ok = write_vital_new_ok == true,
        write_vital_old_ok = write_vital_old_ok == true,
        write_heal_new_ok = write_heal_new_ok == true,
        write_errors = write_errors,
        runtime_inject = runtime_inject,
        refresh_before = refresh_before,
        refresh_after = refresh_after
    })
    return true
end

-- Sets the Dummy Counter state (0=Normal, 1=Counter, 2=Punish Counter)
-- Cache tf_CounterSetting from _tfFuncs
local _tf_counter_cache = nil
local function get_tf_counter()
    if _tf_counter_cache then return _tf_counter_cache end
    pcall(function()
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        if not tm then return end
        local dict = tm:get_field("_tfFuncs")
        if not dict then return end
        local entries = dict:get_field("_entries")
        if not entries then return end
        local count = entries:call("get_Count")
        for i = 0, count - 1 do
            local entry = entries:call("get_Item", i)
            if entry then
                local val = entry:get_field("value")
                if val then
                    local td = val:get_type_definition()
                    if td:get_full_name():find("tf_CounterSetting") then
                        _tf_counter_cache = val
                        return
                    end
                end
            end
        end
    end)
    return _tf_counter_cache
end

-- 0=Normal, 1=CH, 2=PC (via DummyData + bApply, instant without refresh)
local function set_dummy_counter_type(counter_val)
    pcall(function()
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        if not tm then return end
        local tData = tm:get_field("_tData")
        if not tData then return end
        local cs = tData:get_field("CounterSetting")
        if not cs then return end
        local dd = cs:get_field("DummyData")
        if not dd then return end
        if counter_val == 2 then
            dd.NC_TYPE = 0; dd.PC_TYPE = 1
        elseif counter_val == 1 then
            dd.NC_TYPE = 1; dd.PC_TYPE = 0
        else
            dd.NC_TYPE = 0; dd.PC_TYPE = 0
        end
    end)
    local tc = get_tf_counter()
    if tc then pcall(function() tc:call("bApply") end) end
end

-- Read the current counter state
local function read_dummy_counter_type()
    local result = 0
    pcall(function()
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        if not tm then return end
        local tData = tm:get_field("_tData")
        if not tData then return end
        local cs = tData:get_field("CounterSetting")
        if not cs then return end
        local dd = cs:get_field("DummyData")
        if not dd then return end
        if dd.PC_TYPE == 1 then result = 2
        elseif dd.NC_TYPE == 1 then result = 1 end
    end)
    return result
end

local function save_dummy_counter_type()
    trial_state._saved_counter_type = read_dummy_counter_type()
end

local function restore_dummy_counter_type()
    if trial_state._saved_counter_type ~= nil then
        set_dummy_counter_type(trial_state._saved_counter_type)
        trial_state._saved_counter_type = nil
    end
end

-- Cache tf_GuardSetting from _tfFuncs
local _tf_guard_cache = nil
local function get_tf_guard()
    if _tf_guard_cache then return _tf_guard_cache end
    pcall(function()
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        if not tm then return end
        local dict = tm:get_field("_tfFuncs")
        if not dict then return end
        local entries = dict:get_field("_entries")
        if not entries then return end
        local count = entries:call("get_Count")
        for i = 0, count - 1 do
            local entry = entries:call("get_Item", i)
            if entry then
                local val = entry:get_field("value")
                if val and val:get_type_definition():get_full_name():find("tf_GuardSetting") then
                    _tf_guard_cache = val
                    return
                end
            end
        end
    end)
    return _tf_guard_cache
end

local function set_dummy_guard_type(guard_val)
    pcall(function()
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        if not tm then return end
        local guard_func = tm:call("get_GuardFunc")
        if guard_func then pcall(function() guard_func:call("ChangeGuardType", 1, guard_val) end) end
        local tData = tm:get_field("_tData")
        local gs = tData:get_field("GuardSetting")
        local dd = gs:get_field("DummyData")
        dd.GuardType = guard_val
    end)
    local tg = get_tf_guard()
    if tg then pcall(function() tg:call("bApply") end) end
end

local function read_dummy_guard_type()
    local result = 0
    pcall(function()
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        if not tm then return end
        local tData = tm:get_field("_tData")
        local gs = tData:get_field("GuardSetting")
        local dd = gs:get_field("DummyData")
        result = dd.GuardType or 0
    end)
    return result
end

local function save_dummy_guard_type()
    trial_state._saved_guard_type = read_dummy_guard_type()
end

local function restore_dummy_guard_type()
    if trial_state._saved_guard_type ~= nil then
        set_dummy_guard_type(trial_state._saved_guard_type)
        trial_state._saved_guard_type = nil
    end
end

-- DummyStatus.DummyActionType: 0=stand, 1=crouch. Jump variants are controlled by JumpType.
local DUMMY_ACTION_STAND = 0
local DUMMY_ACTION_CROUCH = 1

local _tf_dummy_status_cache = nil
local function get_tf_dummy_status()
    if _tf_dummy_status_cache then return _tf_dummy_status_cache end
    pcall(function()
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        if not tm then return end
        local dict = tm:get_field("_tfFuncs")
        if not dict then return end
        local entries = dict:get_field("_entries")
        if not entries then return end
        local count = entries:call("get_Count")
        for i = 0, count - 1 do
            local entry = entries:call("get_Item", i)
            if entry then
                local val = entry:get_field("value")
                if val and val:get_type_definition():get_full_name():find("tf_DummyStatus") then
                    _tf_dummy_status_cache = val
                    return
                end
            end
        end
    end)
    return _tf_dummy_status_cache
end

local function set_dummy_action_type(action_type, jump_type)
    pcall(function()
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        if not tm then return end
        local tData = tm:get_field("_tData")
        if not tData then return end
        local ds = tData:get_field("DummyStatus")
        if not ds then return end
        local dd = ds:get_field("DummyData")
        if not dd then return end
        dd.DummyActionType = action_type
        if jump_type ~= nil then
            dd.JumpType = jump_type
        elseif action_type ~= DUMMY_ACTION_STAND then
            dd.JumpType = 0
        end
    end)

    local td = get_tf_dummy_status()
    if td then pcall(function() td:call("bApply") end) end
end

local function read_dummy_action_state()
    local action_type = DUMMY_ACTION_STAND
    local jump_type = 0
    pcall(function()
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        if not tm then return end
        local tData = tm:get_field("_tData")
        if not tData then return end
        local ds = tData:get_field("DummyStatus")
        if not ds then return end
        local dd = ds:get_field("DummyData")
        if not dd then return end
        action_type = dd.DummyActionType or DUMMY_ACTION_STAND
        jump_type = dd.JumpType or 0
    end)
    return action_type, jump_type
end

function unique_resources.request_training_refresh()
    pcall(function()
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        if tm then tm._IsReqRefresh = true end
    end)
end

function unique_resources.trace_restore(event)
    if type(event) ~= "table" then return end

    trial_state._unique_restore_debug = event

    if rawget(_G, "CT_UNIQUE_TRACE") ~= true then return end
    if not (file_system and file_system.diag_log) then return end

    file_system.diag_log(
        "[UniqueRestore]"
        .. " character=" .. tostring(event.character)
        .. " side=" .. tostring(event.side)
        .. " unique_key=" .. tostring(event.unique_key)
        .. " expected_stock=" .. tostring(event.expected_stock)
        .. " current_before_restore=" .. tostring(event.current_before_restore)
        .. " current_after_restore=" .. tostring(event.current_after_restore)
        .. " restore_success=" .. tostring(event.restore_success)
        .. " restore_method=" .. tostring(event.restore_method)
        .. " reason=" .. tostring(event.reason)
    )
end

function unique_resources.get_training_data_objects()
    local result = {}
    pcall(function()
        result.training_manager = sdk.get_managed_singleton("app.training.TrainingManager")
        if not result.training_manager then return end
        result.training_data = result.training_manager:get_field("_tData")
        if not result.training_data then return end
        result.parameter_setting = result.training_data:get_field("ParameterSetting")
        result.select_menu = result.training_data:get_field("SelectMenu")
    end)
    if result.parameter_setting then
        pcall(function() result.unique_data = result.parameter_setting:get_field("UniqueData") end)
        if not result.unique_data then
            pcall(function() result.unique_data = result.parameter_setting.UniqueData end)
        end
        pcall(function() result.param_func = result.parameter_setting:get_field("ParamFunc") end)
        if not result.param_func then
            pcall(function() result.param_func = result.parameter_setting.ParamFunc end)
        end
    end
    if not result.param_func and result.training_data then
        pcall(function() result.param_func = result.training_data:get_field("ParamFunc") end)
        if not result.param_func then
            pcall(function() result.param_func = result.training_data.ParamFunc end)
        end
    end
    return result
end

function unique_resources.read_training_fighter_id(player_idx)
    local fighter_id = nil
    pcall(function()
        local data = unique_resources.get_training_data_objects()
        local sm = data.select_menu
        if not sm or not sm.PlayerDatas then return end
        local player_data = sm.PlayerDatas[player_idx]
        if not player_data then return end
        fighter_id = tonumber(player_data.FighterID)
    end)
    return fighter_id
end

function unique_resources.read_value(unique_data, resource_id)
    if not unique_data or not resource_id then return nil end

    local ok, value = pcall(function() return unique_data[resource_id] end)
    if ok and value ~= nil then return tonumber(value) end

    ok, value = pcall(function() return unique_data:get_field(resource_id) end)
    if ok and value ~= nil then return tonumber(value) end

    return nil
end

function unique_resources.call_setter(data, resource, value)
    if not data or not resource or not resource.setter then return false, "setter_missing" end

    local param_func = data.param_func
    if not param_func then return false, "setter_missing" end

    local ok = pcall(function()
        param_func:call(resource.setter, value)
    end)
    if ok then return true, resource.setter end

    ok = pcall(function()
        param_func[resource.setter](param_func, value)
    end)
    if ok then return true, resource.setter end

    ok = pcall(function()
        param_func[resource.setter](value)
    end)
    if ok then return true, resource.setter end

    return false, "setter_missing"
end

function unique_resources.write_value(unique_data, resource_id, value, data)
    if not unique_data or not resource_id or value == nil then return false end

    local resource = unique_resources.resource_by_id(resource_id)
    if resource and resource.setter and data then
        local setter_ok, setter_method = unique_resources.call_setter(data, resource, value)
        if setter_ok then return true, setter_method end
    end

    local ok = pcall(function()
        unique_data[resource_id] = value
    end)
    if ok then return true, "existing_unique_setter" end

    ok = pcall(function()
        unique_data:set_field(resource_id, value)
    end)
    if ok then return true, "existing_unique_setter" end

    return false, resource and resource.setter and "setter_missing" or "write_failed"
end

function unique_resources.normalize_value(resource, value)
    if not resource then return nil end
    local n = tonumber(value)
    if n == nil then return nil end
    n = math.floor(n + 0.5)

    if n == 7 then
        if resource.allow_infinite then
            return 7
        end
        if resource.reject_infinite then
            return nil, "invalid_value"
        end
    end

    local min_value = resource.min or 0
    local max_value = resource.max or min_value
    if n < min_value then n = min_value end
    if n > max_value then n = max_value end
    return n
end

function unique_resources.capture_for_fighter(fighter_id, unique_data, side_key)
    local char_data = unique_resources.by_fighter_id[tonumber(fighter_id)]
    if not char_data or not unique_data then return nil end

    local unique = {}
    for _, resource in ipairs(char_data.resources or {}) do
        local raw_value = unique_resources.read_value(unique_data, resource.id)
        local value, reason = unique_resources.normalize_value(resource, raw_value)
        if value ~= nil then
            unique[resource.id] = value
        elseif resource.id == "stock_0_028" then
            unique_resources.trace_restore({
                character = "Mai",
                side = side_key or "unknown",
                unique_key = resource.id,
                expected_stock = raw_value,
                current_before_restore = raw_value,
                current_after_restore = nil,
                restore_success = false,
                restore_method = resource.setter,
                reason = reason or "invalid_value"
            })
        end
    end

    if next(unique) == nil then return nil end
    return unique
end

function unique_resources.capture_by_side()
    local data = unique_resources.get_training_data_objects()
    local unique_data = data.unique_data
    if not unique_data then return nil end

    local players_state = {}
    local has_unique = false

    for player_idx = 0, 1 do
        local fighter_id = unique_resources.read_training_fighter_id(player_idx)
        local side_key = player_idx == 0 and "p1" or "p2"
        local side_state = nil

        if fighter_id ~= nil then
            local unique = unique_resources.capture_for_fighter(fighter_id, unique_data, side_key)
            if unique then
                side_state = {
                    fighter_id = fighter_id,
                    unique = unique
                }
                has_unique = true
            end
        end

        if side_state then
            players_state[side_key] = side_state
        end
    end

    if not has_unique then return nil end
    return players_state
end

function unique_resources.capture_scene_state(recorded_by)
    local players_state = unique_resources.capture_by_side()
    if not players_state then return nil end

    return {
        schema = "xt.combo_trial.scene.v1",
        capture_mode = "portable",
        recorded_by = recorded_by,
        players = players_state
    }
end

function unique_resources.merge_recorded_table(out, unique_table)
    if type(unique_table) ~= "table" then return end
    for resource_id, value in pairs(unique_table) do
        local resource = unique_resources.resource_by_id(resource_id)
        local normalized = unique_resources.normalize_value(resource, value)
        if normalized ~= nil then
            out[resource_id] = normalized
        end
    end
end

function unique_resources.collect_recorded()
    local first = trial_state.sequence and trial_state.sequence[1]
    if type(first) ~= "table" then return nil end

    local out = {}
    local scene_state = type(first.scene_state) == "table" and first.scene_state or nil
    local meta = type(first._xt_meta) == "table" and first._xt_meta or nil

    if not scene_state and meta and type(meta.scene_state) == "table" then
        scene_state = meta.scene_state
    end

    if scene_state and type(scene_state.players) == "table" then
        local recorded_by = tonumber(first.recorded_by or scene_state.recorded_by or 0) or 0
        local first_side = recorded_by == 1 and "p2" or "p1"
        local second_side = recorded_by == 1 and "p1" or "p2"

        local function merge_side(side_key)
            local side = scene_state.players[side_key]
            if type(side) == "table" then
                unique_resources.merge_recorded_table(out, side.unique)
            end
        end

        merge_side(second_side)
        merge_side(first_side)
    end

    if meta and type(meta.environment) == "table" then
        local env = meta.environment
        if type(env.unique) == "table" then
            unique_resources.merge_recorded_table(out, env.unique)
            if type(env.unique.p1) == "table" then unique_resources.merge_recorded_table(out, env.unique.p1.unique) end
            if type(env.unique.p2) == "table" then unique_resources.merge_recorded_table(out, env.unique.p2.unique) end
        end
        if type(env.players) == "table" then
            if type(env.players.p1) == "table" then unique_resources.merge_recorded_table(out, env.players.p1.unique) end
            if type(env.players.p2) == "table" then unique_resources.merge_recorded_table(out, env.players.p2.unique) end
        end
    end

    if next(out) == nil then return nil end
    return out
end

function unique_resources.add_recorded_entries(entries, unique_table, side_key, fighter_id, source)
    if type(unique_table) ~= "table" then return end

    for resource_id, value in pairs(unique_table) do
        local resource = unique_resources.resource_by_id(resource_id)
        local normalized, reason = unique_resources.normalize_value(resource, value)
        if normalized ~= nil then
            table.insert(entries, {
                resource_id = resource_id,
                value = normalized,
                resource = resource,
                side_key = side_key,
                fighter_id = fighter_id,
                source = source
            })
        elseif resource_id == "stock_0_028" then
            unique_resources.trace_restore({
                character = "Mai",
                side = side_key or "unknown",
                unique_key = resource_id,
                expected_stock = value,
                current_before_restore = nil,
                current_after_restore = nil,
                restore_success = false,
                restore_method = resource and resource.setter or nil,
                reason = reason or "invalid_value"
            })
        end
    end
end

function unique_resources.trace_missing_mai_stock(side_key, side)
    if type(side) ~= "table" then return end
    if tonumber(side.fighter_id) ~= 28 then return end
    if type(side.unique) == "table" and side.unique.stock_0_028 ~= nil then return end

    unique_resources.trace_restore({
        character = "Mai",
        side = side_key or "unknown",
        unique_key = "stock_0_028",
        expected_stock = nil,
        current_before_restore = nil,
        current_after_restore = nil,
        restore_success = false,
        restore_method = "SetUnique028_stock_0",
        reason = "missing_field"
    })
end

function unique_resources.collect_recorded_entries()
    local first = trial_state.sequence and trial_state.sequence[1]
    if type(first) ~= "table" then return nil end

    local entries = {}
    local scene_state = type(first.scene_state) == "table" and first.scene_state or nil
    local meta = type(first._xt_meta) == "table" and first._xt_meta or nil

    if not scene_state and meta and type(meta.scene_state) == "table" then
        scene_state = meta.scene_state
    end

    if scene_state and type(scene_state.players) == "table" then
        local recorded_by = tonumber(first.recorded_by or scene_state.recorded_by or 0) or 0
        local first_side = recorded_by == 1 and "p2" or "p1"
        local second_side = recorded_by == 1 and "p1" or "p2"

        local function add_side(side_key)
            local side = scene_state.players[side_key]
            if type(side) == "table" then
                unique_resources.trace_missing_mai_stock(side_key, side)
                unique_resources.add_recorded_entries(entries, side.unique, side_key, side.fighter_id, "scene_state")
            end
        end

        add_side(second_side)
        add_side(first_side)
    end

    if meta and type(meta.environment) == "table" then
        local env = meta.environment
        if type(env.unique) == "table" then
            unique_resources.add_recorded_entries(entries, env.unique, nil, nil, "meta.environment.unique")
            if type(env.unique.p1) == "table" then
                unique_resources.add_recorded_entries(entries, env.unique.p1.unique, "p1", env.unique.p1.fighter_id, "meta.environment.unique.p1")
            end
            if type(env.unique.p2) == "table" then
                unique_resources.add_recorded_entries(entries, env.unique.p2.unique, "p2", env.unique.p2.fighter_id, "meta.environment.unique.p2")
            end
        end
        if type(env.players) == "table" then
            if type(env.players.p1) == "table" then
                unique_resources.add_recorded_entries(entries, env.players.p1.unique, "p1", env.players.p1.fighter_id, "meta.environment.players.p1")
            end
            if type(env.players.p2) == "table" then
                unique_resources.add_recorded_entries(entries, env.players.p2.unique, "p2", env.players.p2.fighter_id, "meta.environment.players.p2")
            end
        end
    end

    if #entries == 0 then return nil end
    return entries
end

function unique_resources.side_to_player_idx(side_key)
    if side_key == "p1" then return 0 end
    if side_key == "p2" then return 1 end
    return nil
end

function unique_resources.any_current_fighter_is(fighter_id)
    for player_idx = 0, 1 do
        if tonumber(unique_resources.read_training_fighter_id(player_idx)) == tonumber(fighter_id) then
            return true
        end
    end
    return false
end

function unique_resources.should_apply_entry(entry)
    if type(entry) ~= "table" then return false, "invalid_entry" end
    local owner_fighter_id = unique_resources.fighter_id_for_resource(entry.resource_id)
    if not owner_fighter_id then return false, "unknown_resource" end

    if entry.fighter_id ~= nil and tonumber(entry.fighter_id) ~= tonumber(owner_fighter_id) then
        return false, "wrong_resource_owner"
    end

    local player_idx = unique_resources.side_to_player_idx(entry.side_key)
    if player_idx ~= nil then
        if tonumber(unique_resources.read_training_fighter_id(player_idx)) ~= tonumber(owner_fighter_id) then
            return false, "current_side_character_mismatch"
        end
        return true
    end

    if unique_resources.any_current_fighter_is(owner_fighter_id) then return true end
    return false, "current_character_mismatch"
end

function unique_resources.save_current()
    if trial_state._saved_unique_resources then return end

    local data = unique_resources.get_training_data_objects()
    local unique_data = data.unique_data
    if not unique_data then return end

    local saved = {}
    unique_resources.resource_by_id("")
    for resource_id, resource in pairs(unique_resources.by_id or {}) do
        local owner_fighter_id = unique_resources.fighter_id_for_resource(resource_id)
        if owner_fighter_id and unique_resources.any_current_fighter_is(owner_fighter_id) then
            local value = unique_resources.normalize_value(resource, unique_resources.read_value(unique_data, resource_id))
            if value ~= nil then saved[resource_id] = value end
        end
    end

    if next(saved) ~= nil then
        trial_state._saved_unique_resources = saved
    end
end

function unique_resources.restore()
    local saved = trial_state._saved_unique_resources
    if type(saved) ~= "table" then return end

    local data = unique_resources.get_training_data_objects()
    local unique_data = data.unique_data
    if unique_data then
        local changed = false
        for resource_id, value in pairs(saved) do
            local owner_fighter_id = unique_resources.fighter_id_for_resource(resource_id)
            if owner_fighter_id and unique_resources.any_current_fighter_is(owner_fighter_id) then
                if unique_resources.write_value(unique_data, resource_id, value, data) then
                    changed = true
                end
            end
        end
        if changed then unique_resources.request_training_refresh() end
    end

    trial_state._saved_unique_resources = nil
end

function unique_resources.apply_recorded()
    local entries = unique_resources.collect_recorded_entries()
    if type(entries) ~= "table" then return false end

    local data = unique_resources.get_training_data_objects()
    local unique_data = data.unique_data
    if not unique_data then return false end

    unique_resources.save_current()

    local changed = false
    for _, entry in ipairs(entries) do
        local should_apply, skip_reason = unique_resources.should_apply_entry(entry)
        local before = nil
        if entry.resource_id == "stock_0_028" then
            before = unique_resources.read_value(unique_data, entry.resource_id)
        end

        if should_apply then
            local ok, method = unique_resources.write_value(unique_data, entry.resource_id, entry.value, data)
            if ok then
                changed = true
            end

            if entry.resource_id == "stock_0_028" then
                unique_resources.trace_restore({
                    character = "Mai",
                    side = entry.side_key or "unknown",
                    unique_key = entry.resource_id,
                    expected_stock = entry.value,
                    current_before_restore = before,
                    current_after_restore = unique_resources.read_value(unique_data, entry.resource_id),
                    restore_success = ok == true,
                    restore_method = method,
                    reason = ok and "applied" or (method or "setter_missing")
                })
            end
        elseif entry.resource_id == "stock_0_028" then
            unique_resources.trace_restore({
                character = "Mai",
                side = entry.side_key or "unknown",
                unique_key = entry.resource_id,
                expected_stock = entry.value,
                current_before_restore = before,
                current_after_restore = before,
                restore_success = false,
                restore_method = entry.resource and entry.resource.setter or "SetUnique028_stock_0",
                reason = skip_reason or "not_mai"
            })
        end
    end

    return changed
end

local function capture_trial_environment()
    local action_type, jump_type = read_dummy_action_state()
    local stance = (action_type == DUMMY_ACTION_CROUCH) and "crouch" or "stand"
    local env = {
        schema = "xt.training_environment.v1",
        dummy_action_type = action_type,
        dummy_jump_type = jump_type,
        dummy_stance = stance,
    }
    local players_state = unique_resources.capture_by_side()
    if players_state then
        env.players = players_state
        env.unique = players_state
    end
    return env
end

local function save_dummy_action_type()
    if trial_state._saved_dummy_action_type == nil then
        local action_type, jump_type = read_dummy_action_state()
        trial_state._saved_dummy_action_type = action_type
        trial_state._saved_dummy_jump_type = jump_type
    end
end

local function restore_dummy_action_type()
    if trial_state._saved_dummy_action_type ~= nil then
        set_dummy_action_type(trial_state._saved_dummy_action_type, trial_state._saved_dummy_jump_type)
        trial_state._saved_dummy_action_type = nil
        trial_state._saved_dummy_jump_type = nil
    end
end

local function value_requests_dummy_crouch(value)
    if type(value) == "boolean" then return value end
    if type(value) == "number" then return value == DUMMY_ACTION_CROUCH end
    if type(value) ~= "string" then return false end
    local text = value:lower()
    return text == "crouch" or text == "crouching" or text == "cr" or text == "down" or text == "low"
        or text:find("crouch", 1, true) ~= nil
        or text:find("蹲姿", 1, true) ~= nil
end

local function text_mentions_dummy_crouch(value)
    if type(value) ~= "string" then return false end
    local text = value:lower()
    return text:find("蹲姿", 1, true) ~= nil
        or text:find("蹲限定", 1, true) ~= nil
        or text:find("crouch", 1, true) ~= nil
end

local function has_recorded_dummy_action_environment(env)
    return type(env) == "table"
        and (env.dummy_action_type ~= nil
            or env.dummy_stance ~= nil
            or env.dummy_posture ~= nil
            or env.dummy_action ~= nil)
end

local function environment_requests_dummy_crouch(env)
    if not has_recorded_dummy_action_environment(env) then return false end
    if tonumber(env.dummy_action_type) == DUMMY_ACTION_CROUCH then return true end
    if value_requests_dummy_crouch(env.dummy_stance) then return true end
    if value_requests_dummy_crouch(env.dummy_posture) then return true end
    if value_requests_dummy_crouch(env.dummy_action) then return true end
    return false
end

local function apply_recording_environment_to_meta(meta)
    meta = (type(meta) == "table") and meta or {}
    local env = trial_state._rec_environment
    if type(env) ~= "table" then env = capture_trial_environment() end

    meta.environment = env
    meta.dummy_stance = env.dummy_stance
    meta.dummy_action_type = env.dummy_action_type

    if environment_requests_dummy_crouch(env) then
        meta.requires_dummy_crouch = true
    else
        meta.requires_dummy_crouch = false
    end

    return meta
end

local function trial_requires_dummy_crouch()
    local first = trial_state.sequence and trial_state.sequence[1]
    if type(first) ~= "table" then return false end

    if first.requires_dummy_crouch == true then return true end
    if value_requests_dummy_crouch(first.dummy_stance) then return true end
    if value_requests_dummy_crouch(first.dummy_posture) then return true end
    if value_requests_dummy_crouch(first.dummy_action) then return true end

    local meta = type(first._xt_meta) == "table" and first._xt_meta or nil
    if meta then
        if has_recorded_dummy_action_environment(meta.environment) then
            return environment_requests_dummy_crouch(meta.environment)
        end
        if meta.requires_dummy_crouch == true then return true end
        if value_requests_dummy_crouch(meta.dummy_stance) then return true end
        if value_requests_dummy_crouch(meta.dummy_posture) then return true end
        if value_requests_dummy_crouch(meta.dummy_action) then return true end
        if text_mentions_dummy_crouch(meta.title) or text_mentions_dummy_crouch(meta.note) then return true end
    end

    return false
end

CT_TRIAL_DEFENSE_FIELDS = {
    "DR_Type",
    "DP_Type",
    "DR_Guard_Weight",
    "DR_Getup_Weight",
    "DR_No_Weight"
}

_ct_tf_defense_system_cache = nil
function ct_get_tf_defense_system()
    if _ct_tf_defense_system_cache then return _ct_tf_defense_system_cache end
    pcall(function()
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        if not tm then return end
        local dict = tm:get_field("_tfFuncs")
        if not dict then return end
        local entries = dict:get_field("_entries")
        if not entries then return end
        local count = entries:call("get_Count")
        for i = 0, count - 1 do
            local entry = entries:call("get_Item", i)
            local val = entry and entry:get_field("value") or nil
            if val then
                local td = val:get_type_definition()
                local full_name = td and td:get_full_name() or ""
                if full_name:find("tf_DefenseSystem") then
                    _ct_tf_defense_system_cache = val
                    return
                end
            end
        end
    end)
    return _ct_tf_defense_system_cache
end

function ct_get_trial_defense_objects(player_idx)
    local out = { player_idx = tonumber(player_idx or 1) or 1 }
    if out.player_idx ~= 1 then out.player_idx = 0 end
    pcall(function()
        out.tm = sdk.get_managed_singleton("app.training.TrainingManager")
        out.defense_func = out.tm and out.tm:call("get_DefenseFunc") or nil
        local t_data = out.tm and out.tm:get_field("_tData") or nil
        out.defense_system = t_data and t_data:get_field("DefenseSystem") or nil
        if out.defense_system then
            out.dummy_data = out.defense_system.DummyData
            out.player_data = out.defense_system.PlayerDatas and out.defense_system.PlayerDatas[out.player_idx] or nil
        end
        out.tf_defense = ct_get_tf_defense_system()
    end)
    return out
end

function ct_copy_trial_defense_fields(obj)
    local fields = {}
    if not obj then return fields end
    for _, field_name in ipairs(CT_TRIAL_DEFENSE_FIELDS) do
        local ok, value = pcall(function() return obj[field_name] end)
        if ok and value ~= nil then fields[field_name] = value end
    end
    return fields
end

function ct_write_trial_defense_fields(obj, fields)
    if not obj then return end
    for field_name, value in pairs(fields or {}) do
        pcall(function() obj[field_name] = value end)
    end
end

function ct_backup_trial_defense_settings(defender_idx)
    defender_idx = tonumber(defender_idx or 1) or 1
    if defender_idx ~= 1 then defender_idx = 0 end
    if type(trial_state._trial_defense_backup) == "table" then return end
    local objects = ct_get_trial_defense_objects(defender_idx)
    trial_state._trial_defense_backup = {
        player_idx = defender_idx,
        dummy = ct_copy_trial_defense_fields(objects.dummy_data),
        player = ct_copy_trial_defense_fields(objects.player_data)
    }
end

function restore_trial_defense_settings()
    local backup = trial_state._trial_defense_backup
    if type(backup) ~= "table" then return false end
    local objects = ct_get_trial_defense_objects(backup.player_idx)
    ct_write_trial_defense_fields(objects.dummy_data, backup.dummy)
    ct_write_trial_defense_fields(objects.player_data, backup.player)
    if objects.tf_defense then pcall(function() objects.tf_defense:call("bApply") end) end
    trial_state._trial_defense_backup = nil
    return true
end

function apply_trial_defense_cleanup()
    local attacker_idx = tonumber(trial_state.playing_player or 0) or 0
    if attacker_idx ~= 1 then attacker_idx = 0 end
    local defender_idx = 1 - attacker_idx
    ct_backup_trial_defense_settings(defender_idx)

    local objects = ct_get_trial_defense_objects(defender_idx)
    if objects.defense_func then
        pcall(function() objects.defense_func:call("SetDriveParry", defender_idx, 0) end)
        pcall(function() objects.defense_func:call("ChangeDRType", defender_idx, 0) end)
        pcall(function() objects.defense_func:call("SetDR_Guard_Weight", defender_idx, 0) end)
        pcall(function() objects.defense_func:call("SetDR_Getup_Weight", defender_idx, 0) end)
        pcall(function() objects.defense_func:call("SetDR_No_Weight", defender_idx, 100) end)
    end

    local disabled = {
        DR_Type = 0,
        DP_Type = 0,
        DR_Guard_Weight = 0,
        DR_Getup_Weight = 0,
        DR_No_Weight = 100
    }
    ct_write_trial_defense_fields(objects.dummy_data, disabled)
    ct_write_trial_defense_fields(objects.player_data, disabled)
    if objects.tf_defense then pcall(function() objects.tf_defense:call("bApply") end) end
end

function ct_trial_dummy_guard_type()
    local first_step = trial_state.sequence and trial_state.sequence[1]
    if type(first_step) ~= "table" then return 2 end

    local meta = type(first_step._xt_meta) == "table" and first_step._xt_meta or nil
    local env = meta and type(meta.environment) == "table" and meta.environment or nil
    local guard_type = tonumber(first_step.dummy_guard_type)
        or (meta and tonumber(meta.dummy_guard_type) or nil)
        or (env and tonumber(env.dummy_guard_type) or nil)

    if guard_type == nil then
        local guard_name = first_step.dummy_guard
            or (meta and meta.dummy_guard or nil)
            or (env and env.dummy_guard or nil)
        if type(guard_name) == "string" then
            local guard_text = guard_name:lower()
            if guard_text == "none" or guard_text == "no" or guard_text == "off" then
                guard_type = 0
            elseif guard_text == "after_first_hit" or guard_text == "after-first-hit" or guard_text == "after first hit" then
                guard_type = 2
            elseif guard_text == "all" or guard_text == "guard_all" or guard_text == "full" then
                guard_type = 3
            elseif guard_text == "random" then
                guard_type = 4
            end
        end
    end

    if guard_type == nil or guard_type < 0 or guard_type > 4 then guard_type = 2 end
    return guard_type
end

local function apply_trial_training_environment(skip_refresh_settings)
    local first_ct = trial_state.sequence and trial_state.sequence[1] and trial_state.sequence[1].counter_type or 0
    local apply_refresh_settings = skip_refresh_settings ~= true
    if apply_refresh_settings then unique_resources.apply_recorded() end
    local first_step = trial_state.sequence and trial_state.sequence[1]
    local snapshot_gauges = type(first_step) == "table" and first_step.snapshot_gauges or nil
    if apply_refresh_settings and type(snapshot_gauges) == "table" and snapshot_gauges.defender_burnout == true then
        local attacker_idx = tonumber(trial_state.playing_player or 0) or 0
        local defender_idx = 1 - attacker_idx
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        local t_data = tm and tm:get_field("_tData")
        local parameter_setting = t_data and t_data:get_field("ParameterSetting")
        local player_datas = parameter_setting and parameter_setting.PlayerDatas
        local defender_params = player_datas and player_datas[defender_idx]
        if defender_params then
            if type(trial_state._saved_drive_settings) ~= "table" then
                trial_state._saved_drive_settings = {}
            end
            if trial_state._saved_drive_settings[defender_idx] == nil then
                local saved_drive = {}
                for _, field_name in ipairs(DRIVE_SETTING_FIELDS) do
                    local value = defender_params[field_name]
                    if value ~= nil then saved_drive[field_name] = value end
                end
                if next(saved_drive) ~= nil then trial_state._saved_drive_settings[defender_idx] = saved_drive end
            end
            local defender_drive = math.max(0, tonumber(snapshot_gauges.defender_drive) or 0)
            defender_params.DG_Point = defender_drive
            defender_params.DG_Stock = math.floor((defender_drive + 5000) / 10000)
            defender_params.Is_DG_Break = true
            if tm then tm._IsReqRefresh = true end
        end
    end
    if trial_requires_dummy_crouch() then
        set_dummy_action_type(DUMMY_ACTION_CROUCH)
    else
        set_dummy_action_type(DUMMY_ACTION_STAND)
    end
    set_dummy_counter_type(first_ct or 0)
    local dummy_guard_type = ct_trial_dummy_guard_type()
    _G.CT_COMBO_TRIALS_DUMMY_GUARD_TYPE = dummy_guard_type
    set_dummy_guard_type(dummy_guard_type)
    apply_trial_defense_cleanup()
end

local function capture_current_positions()
    local p1_pos, p2_pos, p1_raw, p2_raw = nil, nil, nil, nil
    local p1 = GS.p1
    local p2 = GS.p2

    -- UNIVERSAL FORMULA: Raw value / 65536 = Meters (e.g. 1.31)
    if p1 and p1.pos and p1.pos.x and p1.pos.x.v then
        p1_raw = p1.pos.x.v
        p1_pos = p1_raw / 6553600.0
    end
    if p2 and p2.pos and p2.pos.x and p2.pos.x.v then
        p2_raw = p2.pos.x.v
        p2_pos = p2_raw / 6553600.0
    end
    return p1_pos, p2_pos, p1_raw, p2_raw
end

local function save_native_position_settings(sm)
    if trial_state._native_position_settings or not sm or not sm.PlayerDatas then return end
    local p1d = sm.PlayerDatas[0]
    local p2d = sm.PlayerDatas[1]
    trial_state._native_position_settings = {
        StartLocation = sm.StartLocation,
        P1ManualPosX = p1d and p1d.ManualPosX,
        P2ManualPosX = p2d and p2d.ManualPosX,
    }
end

local function request_training_refresh()
    pcall(function()
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        if tm then tm._IsReqRefresh = true end
    end)
end

local function restore_native_position_settings(request_refresh)
    clear_pending_position_injection()
    local saved = trial_state._native_position_settings
    if not saved then
        if request_refresh then request_training_refresh() end
        return
    end

    pcall(function()
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        if not tm then return end
        local tData = tm:get_field("_tData")
        if not tData then return end
        local sm = tData:get_field("SelectMenu")
        if not sm then return end

        if saved.StartLocation ~= nil then sm.StartLocation = saved.StartLocation end
        if sm.PlayerDatas then
            local p1d = sm.PlayerDatas[0]
            local p2d = sm.PlayerDatas[1]
            if p1d and saved.P1ManualPosX ~= nil then p1d.ManualPosX = saved.P1ManualPosX end
            if p2d and saved.P2ManualPosX ~= nil then p2d.ManualPosX = saved.P2ManualPosX end
        end

        if request_refresh then tm._IsReqRefresh = true end
    end)

    trial_state._native_position_settings = nil
end

-- Calculate the facing direction of the active player at trial start
local function update_trial_flip_state(skip_mirror)
    local r1, r2

    if d2d_cfg.forced_position_idx == 1 then
        -- 1. FORCED POS OFF: destination positions (live_start if playing, else live)
        if trial_state.is_playing and trial_state.live_start_pos_p1_raw and trial_state.live_start_pos_p2_raw then
            r1 = trial_state.live_start_pos_p1_raw
            r2 = trial_state.live_start_pos_p2_raw
        else
            local _, _, live_p1, live_p2 = capture_current_positions()
            if not live_p1 or not live_p2 then
                trial_state.flip_inputs = false
                return
            end
            r1 = live_p1
            r2 = live_p2
        end
    else
        -- 2. FORCED POS ON or MIRRORED: Read saved position (game will teleport us there)
        if not trial_state.start_pos_p1_raw or not trial_state.start_pos_p2_raw then
            trial_state.flip_inputs = false
            return
        end
        
        local recorded_by = 0
        if trial_state.sequence and trial_state.sequence[1] and trial_state.sequence[1].recorded_by then
            recorded_by = trial_state.sequence[1].recorded_by
        end

        r1 = trial_state.start_pos_p1_raw
        r2 = trial_state.start_pos_p2_raw

        -- Swap if the playing player is not the one who recorded
        if trial_state.is_playing and trial_state.playing_player ~= recorded_by then
            local temp = r1
            r1 = r2
            r2 = temp
        end

        -- Automatic mathematical inversion if MIRRORED is selected
        if d2d_cfg.forced_position_idx == 3 and not skip_mirror then
            r1 = -r1
            r2 = -r2
        end
    end

    -- Determine final facing direction (P1 or P2)
    if trial_state.playing_player == 0 then
        -- P1 faces left if physically to the right of P2
        trial_state.flip_inputs = (r1 > r2)
    else
        -- P2 faces left if physically to the right of P1
        trial_state.flip_inputs = (r2 > r1)
    end
end


local function apply_forced_position(skip_mirror)
    if not RuntimeSafety.is_training_allowed() then return end

    -- SYNCHRONIZATION: Always update visual flip state before injecting position
    update_trial_flip_state(skip_mirror)

    if d2d_cfg.forced_position_idx == 1 then
        restore_native_position_settings(true)
        return
    end

    local tm = sdk.get_managed_singleton("app.training.TrainingManager")
    if not tm then return end

    local tData = tm:get_field("_tData")
    if not tData then return end

    local sm = tData:get_field("SelectMenu")
    if not sm then return end

    save_native_position_settings(sm)

    local pos1, pos2, raw1, raw2

    if not trial_state.start_pos_p1 or not trial_state.start_pos_p2 then return end

    local recorded_by = 0
    if trial_state.sequence and trial_state.sequence[1] and trial_state.sequence[1].recorded_by then
        recorded_by = trial_state.sequence[1].recorded_by
    end

    local p1_pos = trial_state.start_pos_p1
    local p2_pos = trial_state.start_pos_p2
    local p1_raw = trial_state.start_pos_p1_raw
    local p2_raw = trial_state.start_pos_p2_raw

    if trial_state.is_playing and trial_state.playing_player ~= recorded_by then
        p1_pos = trial_state.start_pos_p2
        p2_pos = trial_state.start_pos_p1
        p1_raw = trial_state.start_pos_p2_raw
        p2_raw = trial_state.start_pos_p1_raw
    end

    pos1 = p1_pos
    pos2 = p2_pos
    raw1 = p1_raw
    raw2 = p2_raw

    if d2d_cfg.forced_position_idx == 3 and not skip_mirror then
        pos1 = -pos1
        pos2 = -pos2
        raw1 = -raw1
        raw2 = -raw2
    end

    sm.StartLocation = 3
    sm.PlayerDatas[0].ManualPosX = math.floor((pos1 * 100) + 0.5)
    sm.PlayerDatas[1].ManualPosX = math.floor((pos2 * 100) + 0.5)

    tm._IsReqRefresh = true
    -- Store exact sfix values for post-refresh correction
    trial_state.exact_inject_r1 = raw1
    trial_state.exact_inject_r2 = raw2
    trial_state.pending_exact_pos = 10
    trial_state.pending_exact_timeout = 45
end

local function apply_exact_position_now()
    local r1 = trial_state.exact_inject_r1
    local r2 = trial_state.exact_inject_r2
    if not r1 or not r2 then return false end

    local p1 = GS.p1
    local p2 = GS.p2
    if not p1 or not p2 then return false end

    local sfix_type = _td_sfix
    if not sfix_type then return false end
    local sfix_from = sfix_type:get_method("From(System.Double)")
    if not sfix_from then return false end

    -- r1/r2 are raw sfix values (pos.x.v). In cm: raw / 65536.0
    if p1.POS_SETx then p1:POS_SETx(sfix_from:call(nil, r1 / 65536.0)) end
    if p2.POS_SETx then p2:POS_SETx(sfix_from:call(nil, r2 / 65536.0)) end
    return true
end
-- =========================================================
-- HELPER FUNCTIONS (Shared by UI buttons and external actions)
-- =========================================================

local function reset_positions_to_default()
    if not RuntimeSafety.is_training_allowed() then return end
    restore_native_position_settings(true)
end

local function apply_current_position_refresh()
    if not RuntimeSafety.is_training_allowed() then return end
    restore_native_position_settings(true)
end


local function assign_groups(sequence)
    local gid = 0
    for i, step in ipairs(sequence) do
        local motion = (step.motion or ""):match("^%s*(.-)%s*$") or ""
        local is_followup = motion:sub(1, 1) == ">"

        -- Juri: the hit after 1218 is not a real follow-up, break the group
        if is_followup and i > 1 and sequence[i - 1].id == 1218 then
            is_followup = false
            step.motion = motion:gsub("^>%s*", "")
        end

        if is_followup and i > 1 then
            step.group_id = sequence[i - 1].group_id
        else
            gid = gid + 1
            step.group_id = gid
        end
    end
end

CTTimelineSequenceNormalizer = CTTimelineSequenceNormalizer or {}
CTTimelineSequenceNormalizer.button_order = { "LP", "MP", "HP", "LK", "MK", "HK" }
CTTimelineSequenceNormalizer.button_set = { LP = true, MP = true, HP = true, LK = true, MK = true, HK = true }

function CTTimelineSequenceNormalizer.compact_motion(value)
    return tostring(value or ""):upper():gsub("%s+", "")
end

function CTTimelineSequenceNormalizer.button_table_key(buttons)
    if type(buttons) ~= "table" then return "" end
    local out = {}
    for _, btn in ipairs(CTTimelineSequenceNormalizer.button_order) do
        if buttons[btn] then out[#out + 1] = btn end
    end
    return table.concat(out, "+")
end

function CTTimelineSequenceNormalizer.parse_input(rest)
    local dir = "5"
    local buttons = {}
    for part in tostring(rest or ""):gmatch("[^+]+") do
        local token = tostring(part:match("^%s*(.-)%s*$") or ""):upper()
        if token:match("^[1-9]$") then
            dir = token
        elseif CTTimelineSequenceNormalizer.button_set[token] then
            buttons[token] = true
        elseif token == "P" then
            buttons.LP = true; buttons.MP = true; buttons.HP = true
        elseif token == "K" then
            buttons.LK = true; buttons.MK = true; buttons.HK = true
        end
    end
    return dir, buttons
end

function CTTimelineSequenceNormalizer.build_press_events(timeline)
    local events = {}
    local frame = 0
    local prev_buttons = {}
    if type(timeline) ~= "table" then return events end

    for idx, line in ipairs(timeline) do
        local frames_str, rest = tostring(line or ""):match("^(%d+)f%s*:%s*(.*)$")
        local duration = tonumber(frames_str)
        if duration then
            local dir, buttons = CTTimelineSequenceNormalizer.parse_input(rest)
            local newly_pressed = {}
            for btn, pressed in pairs(buttons) do
                if pressed and not prev_buttons[btn] then newly_pressed[btn] = true end
            end
            local new_key = CTTimelineSequenceNormalizer.button_table_key(newly_pressed)
            if new_key ~= "" then
                events[#events + 1] = {
                    index = idx,
                    start_frame = frame,
                    duration = duration,
                    dir = dir,
                    input = tostring(rest or ""),
                    buttons = buttons,
                    button_key = CTTimelineSequenceNormalizer.button_table_key(buttons),
                    new_buttons = newly_pressed,
                    new_button_key = new_key
                }
            end
            frame = frame + duration
            prev_buttons = buttons
        end
    end

    return events
end

function CTTimelineSequenceNormalizer.simple_motion_parts(step)
    local motion = CTTimelineSequenceNormalizer.compact_motion(step and step.motion or ""):gsub("^J%.", "")
    local dir, btn = motion:match("^([1-9])([LMH][PK])$")
    if dir and btn then return dir, btn end
    btn = motion:match("^([LMH][PK])$")
    if btn then return "5", btn end
    return nil, nil
end

function CTTimelineSequenceNormalizer.mirror_dir(dir)
    return ({ ["1"] = "3", ["3"] = "1", ["4"] = "6", ["6"] = "4", ["7"] = "9", ["9"] = "7" })[tostring(dir or "")] or tostring(dir or "")
end

function CTTimelineSequenceNormalizer.direction_matches(event_dir, step_dir)
    event_dir = tostring(event_dir or "5")
    step_dir = tostring(step_dir or "5")
    if step_dir == "2" and (event_dir == "1" or event_dir == "2" or event_dir == "3") then return true end
    return event_dir == step_dir or event_dir == CTTimelineSequenceNormalizer.mirror_dir(step_dir)
end

function CTTimelineSequenceNormalizer.motion_anchor_parts(step)
    local motion = CTTimelineSequenceNormalizer.compact_motion(step and step.motion or ""):gsub("^J%.", "")
    local dirs, btn = motion:match("^([1-9]+)%+(.+)$")
    if not dirs or not btn then dirs, btn = motion:match("^([1-9]+)(PP)$") end
    if not dirs or not btn then dirs, btn = motion:match("^([1-9]+)(KK)$") end
    if not dirs or not btn then dirs, btn = motion:match("^([1-9]+)([LMH][PK])$") end
    if not dirs or not btn then dirs, btn = motion:match("^([1-9]+)([PK])$") end
    if not dirs or not btn then return nil, nil end

    local normalized_buttons = {}
    local button_parts = {}
    if btn == "P" or btn == "K" or btn == "PP" or btn == "KK" then
        return dirs:sub(-1), btn
    end

    for part in tostring(btn or ""):gmatch("[^+]+") do
        local token = tostring(part or ""):upper()
        if not CTTimelineSequenceNormalizer.button_set[token] then return nil, nil end
        normalized_buttons[token] = true
    end
    for _, button in ipairs(CTTimelineSequenceNormalizer.button_order) do
        if normalized_buttons[button] then button_parts[#button_parts + 1] = button end
    end
    if #button_parts == 0 then return nil, nil end
    return dirs:sub(-1), table.concat(button_parts, "+")
end

function CTTimelineSequenceNormalizer.button_matches_token(event, token)
    if type(event) ~= "table" then return false end
    token = tostring(token or ""):upper()
    if token == "P" then
        return event.new_button_key == "LP" or event.new_button_key == "MP" or event.new_button_key == "HP"
    elseif token == "K" then
        return event.new_button_key == "LK" or event.new_button_key == "MK" or event.new_button_key == "HK"
    elseif token == "PP" then
        local count = 0
        for _, button in ipairs({ "LP", "MP", "HP" }) do
            if event.new_buttons and event.new_buttons[button] then count = count + 1 end
        end
        return count >= 2
    elseif token == "KK" then
        local count = 0
        for _, button in ipairs({ "LK", "MK", "HK" }) do
            if event.new_buttons and event.new_buttons[button] then count = count + 1 end
        end
        return count >= 2
    elseif token:find("+", 1, true) then
        for part in token:gmatch("[^+]+") do
            if not (event.new_buttons and event.new_buttons[part]) then return false end
        end
        return true
    end
    return event.new_button_key == token
end

function CTTimelineSequenceNormalizer.is_drive_rush_step(step)
    local motion = CTTimelineSequenceNormalizer.compact_motion(step and step.motion or "")
    return motion == "DRC" or motion:find("DRIVERUSH", 1, true) ~= nil
        or is_drive_rush_id(step and step.id)
end

function CTTimelineSequenceNormalizer.is_simple_button_step(step)
    if type(step) ~= "table" or CTTimelineSequenceNormalizer.is_drive_rush_step(step) then return false end
    local dir, btn = CTTimelineSequenceNormalizer.simple_motion_parts(step)
    return dir ~= nil and btn ~= nil
end

function CTTimelineSequenceNormalizer.simple_button_step_key(step)
    if not CTTimelineSequenceNormalizer.is_simple_button_step(step) then return nil end
    local action_id = step and step.id
    if action_id ~= nil then return "id:" .. tostring(action_id) end
    return "motion:" .. CTTimelineSequenceNormalizer.compact_motion(step and step.motion or "")
end

function CTTimelineSequenceNormalizer.build_single_hit_evidence(sequence)
    local evidence = {}
    if type(sequence) ~= "table" then return evidence end

    local prev_combo = 0
    for _, step in ipairs(sequence) do
        local final_combo = tonumber(step and step.expected_combo) or 0
        local key = CTTimelineSequenceNormalizer.simple_button_step_key(step)
        if key and final_combo - prev_combo == 1 then
            evidence[key] = true
        end
        prev_combo = final_combo
    end

    return evidence
end

function CTTimelineSequenceNormalizer.event_matches_step(event, step)
    if type(event) ~= "table" or type(step) ~= "table" then return false end
    if CTTimelineSequenceNormalizer.is_drive_rush_step(step) then
        return event.new_buttons and event.new_buttons.MP and event.new_buttons.MK
            and event.new_button_key == "MP+MK"
    end

    local dir, btn = CTTimelineSequenceNormalizer.simple_motion_parts(step)
    if dir and btn then
        return event.new_button_key == btn and CTTimelineSequenceNormalizer.direction_matches(event.dir, dir)
    end

    dir, btn = CTTimelineSequenceNormalizer.motion_anchor_parts(step)
    if not dir or not btn then return false end
    return CTTimelineSequenceNormalizer.button_matches_token(event, btn)
        and (event.dir == "5" or CTTimelineSequenceNormalizer.direction_matches(event.dir, dir))
end

function CTTimelineSequenceNormalizer.find_event_for_step(events, start_idx, step)
    for i = math.max(1, tonumber(start_idx) or 1), #events do
        if CTTimelineSequenceNormalizer.event_matches_step(events[i], step) then return i end
    end
    return nil
end

function CTTimelineSequenceNormalizer.clone_step(step)
    local clone = {}
    for k, v in pairs(step) do
        if k ~= "_xt_meta" and k ~= "_wtt_cn_meta" and k ~= "timeline"
            and k ~= "scene_state" and k ~= "snapshot_gauges" then
            if k == "motion_aliases" and type(v) == "table" then
                local aliases = {}
                for i, alias in ipairs(v) do aliases[i] = alias end
                clone[k] = aliases
            else
                clone[k] = v
            end
        end
    end
    clone._ct_timeline_expanded = true
    return clone
end

function CTTimelineSequenceNormalizer.repeat_combo_value(prev_combo, final_combo, occurrence, repeat_count)
    prev_combo = tonumber(prev_combo) or 0
    final_combo = tonumber(final_combo) or 0
    if final_combo <= prev_combo or repeat_count <= 1 then return final_combo end
    if occurrence >= repeat_count then return final_combo end
    local value = prev_combo + occurrence
    if value > final_combo then value = final_combo end
    return value
end

function CTTimelineSequenceNormalizer.expand(sequence)
    if type(sequence) ~= "table" or type(sequence[1]) ~= "table" then return end
    local timeline = sequence[1].timeline
    if type(timeline) ~= "table" or #timeline == 0 then return end

    local events = CTTimelineSequenceNormalizer.build_press_events(timeline)
    if #events == 0 then return end
    local single_hit_evidence = CTTimelineSequenceNormalizer.build_single_hit_evidence(sequence)

    local matches = {}
    local search_idx = 1
    for i, step in ipairs(sequence) do
        local event_idx = CTTimelineSequenceNormalizer.find_event_for_step(events, search_idx, step)
        matches[i] = event_idx
        if event_idx then search_idx = event_idx + 1 end
    end

    local expanded = {}
    local changed = false
    local last_expanded_event_idx = nil
    local last_expanded_was_inserted = false

    for i, step in ipairs(sequence) do
        local prev_combo = #expanded > 0 and (tonumber(expanded[#expanded].expected_combo) or 0) or 0
        local final_combo = tonumber(step.expected_combo) or 0
        local duplicate_events = {}
        local step_event_idx = matches[i]

        local combo_delta = final_combo - prev_combo
        local simple_step_key = CTTimelineSequenceNormalizer.simple_button_step_key(step)
        local can_expand_repeated_simple = combo_delta <= 1
            or (combo_delta > 1 and simple_step_key and single_hit_evidence[simple_step_key] == true)
        if CTTimelineSequenceNormalizer.is_simple_button_step(step) and step_event_idx and can_expand_repeated_simple then
            local next_event_idx = nil
            for j = i + 1, #sequence do
                if matches[j] then next_event_idx = matches[j]; break end
            end
            if next_event_idx then
                local scan_end = next_event_idx - 1
                for event_idx = step_event_idx + 1, scan_end do
                    if CTTimelineSequenceNormalizer.event_matches_step(events[event_idx], step) then
                        duplicate_events[#duplicate_events + 1] = event_idx
                    end
                end
            end
        end
        local max_extra_events = math.max(0, final_combo - prev_combo - 1)
        while #duplicate_events > max_extra_events do
            table.remove(duplicate_events)
        end

        local repeat_count = 1 + #duplicate_events
        if repeat_count > 1 then
            step.expected_combo = CTTimelineSequenceNormalizer.repeat_combo_value(prev_combo, final_combo, 1, repeat_count)
            changed = true
        end

        if step_event_idx and last_expanded_event_idx and last_expanded_was_inserted then
            step.delay_from_prev = math.max(0, (events[step_event_idx].start_frame or 0) - (events[last_expanded_event_idx].start_frame or 0))
            changed = true
        end

        expanded[#expanded + 1] = step
        if step_event_idx then
            last_expanded_event_idx = step_event_idx
            last_expanded_was_inserted = false
        end

        local previous_event_idx = step_event_idx
        for occurrence, event_idx in ipairs(duplicate_events) do
            local clone = CTTimelineSequenceNormalizer.clone_step(step)
            clone.expected_combo = CTTimelineSequenceNormalizer.repeat_combo_value(prev_combo, final_combo, occurrence + 1, repeat_count)
            clone.delay_from_prev = previous_event_idx and math.max(0, (events[event_idx].start_frame or 0) - (events[previous_event_idx].start_frame or 0)) or 0
            clone._ct_timeline_source_step = i
            clone._ct_timeline_event_index = events[event_idx].index
            expanded[#expanded + 1] = clone
            previous_event_idx = event_idx
            last_expanded_event_idx = event_idx
            last_expanded_was_inserted = true
        end
    end

    if not changed then return end
    for i = #sequence, 1, -1 do sequence[i] = nil end
    for i, step in ipairs(expanded) do sequence[i] = step end
end

local function normalize_sequence_counter_types(sequence)
    if type(sequence) ~= "table" or type(sequence[1]) ~= "table" then return end
    CTTimelineSequenceNormalizer.expand(sequence)
    local first = sequence[1]
    if (first.counter_type == nil or first.counter_type == 0) and type(first.combo_stats) == "table" then
        local inferred = counter_type_from_hit_type(first.combo_stats.hit_type)
        if inferred ~= 0 then first.counter_type = inferred end
    end
    for _, step in ipairs(sequence) do
        if step.counter_type == nil then step.counter_type = 0 end
        if type(step.motion_aliases) ~= "table" then step.motion_aliases = {} end
        local motion = tostring(step.motion or ""):upper():gsub("%s+", "")
        local dirs, btns = motion:match("^(%d+)%+?(.*)$")
        if dirs == "236236" or dirs == "214214" then
            local seen = {}
            for _, alias in ipairs(step.motion_aliases) do seen[tostring(alias):upper():gsub("%s+", "")] = true end
            local suffix = (btns ~= "" and "+" .. btns or "")
            local aliases = (dirs == "236236") and { "36", "236" } or { "14", "214" }
            for _, alias_dirs in ipairs(aliases) do
                local alias = alias_dirs .. suffix
                if not seen[alias] then
                    table.insert(step.motion_aliases, alias)
                    seen[alias] = true
                end
            end
        end
    end
end

function ct_is_ingrid_charge_stock_action(char_name, act_id)
    return tostring(char_name or "") == "Ingrid" and tonumber(act_id) == 969
end

local ComboTrials_Files = require("func/ComboTrials_Files")
ComboTrials_Files.init(ctx, {
    normalize_sequence_counter_types = normalize_sequence_counter_types,
    assign_groups = assign_groups,
    restore_trial_dummy_action_type = restore_dummy_action_type,
})

local function load_combo_from_file(path, force)
    restore_dummy_action_type()
    local ok = ComboTrials_Files.load_combo_from_file(path, force)
    if ok and type(read_attacker_hp_restore_snapshot) == "function"
        and type(restore_hp_training_setting_if_needed) == "function" then
        local snapshot = read_attacker_hp_restore_snapshot()
        if type(snapshot) ~= "table" then
            restore_hp_training_setting_if_needed("load_plain_trial", trial_state.playing_player)
        end
    end
    return ok
end

local function clear_combo_state()
    restore_dummy_action_type()
    local ok = ComboTrials_Files.clear_combo_state()
    if type(restore_hp_training_setting_if_needed) == "function" then
        restore_hp_training_setting_if_needed("clear_combo_state", trial_state.playing_player)
    end
    return ok
end

local function reset_player_action_buffers(p_state)
    if not p_state then return end
    local direct_input = _pf.direct_input or 0
    local act_id = _pf.act_id or -1
    local act_frame = _pf.act_frame or -1
    p_state.log = {}
    p_state.input_history_queue = {}
    p_state.prev_act_id = -1
    p_state.prev_act_frame = -1
    p_state.last_direct_input = direct_input
    p_state.last_combo_count = 0
    p_state.action_instance_counter = p_state.action_instance_counter or 0
    p_state.current_action_instance = p_state.action_instance_counter
    p_state.buffer_act_id = act_id
    p_state.buffer_act_frame = act_frame
    p_state.buffer_action_instance = p_state.current_action_instance
    p_state.buffer_start_frame = engine_frame_count
    p_state.buffer_flags = _pf.flags or 0
    p_state.buffer_action_code = _pf.action_code or 0
    p_state.buffer_direct_input = direct_input
    p_state.buffer_b_type = _pf.b_type or 0
    p_state.buffer_hold_frames = 0
    p_state.buffer_is_committed = true
end

local function begin_trial_action_grace(frames)
    trial_state._action_grace = frames or 90
    trial_state._action_grace_min = 12
    trial_state._reset_wait_refresh = true
end

local function should_hold_trial_action_grace()
    if trial_state._reset_wait_refresh then
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        if tm and tm:get_field("_IsReqRefresh") == true then
            return true
        end
        trial_state._reset_wait_refresh = false
    end

    local min_frames = trial_state._action_grace_min or 0
    if min_frames > 0 then
        trial_state._action_grace_min = min_frames - 1
        return true
    end

    local act_id = _pf.act_id or -1
    local buttons = (_pf.direct_input or 0) & 0xFFF0
    local neutral_action = (act_id <= 50) or act_id == 17 or act_id == 18 or act_id == 36 or act_id == 37 or act_id == 38
    return not (neutral_action and buttons == 0)
end

local function is_trial_action_grace_active()
    return trial_state._action_grace and trial_state._action_grace > 0
end

local reset_combo_visual_runtime
local step_combo_reset_gc

local function clear_trial_attempt_state(player_idx, phase)
    trial_state.success_timer = 0
    trial_state.fail_timer = 0
    trial_state.fail_reason = nil
    trial_state.manual_reset_pending = false
    trial_state._success_latched = false
    trial_state._auto_next_countdown = nil
    trial_state._fail_captured = false
    trial_state.active_universal_hold = nil
    trial_state.pending_auto_check = nil
    trial_state.current_step = 1
    trial_state.ui_visual_step = 1
    trial_state.floating_info = nil
    trial_state.floating_color = nil
    trial_state._step1_wrong_pending = false
    trial_state._first_hit_landed = false
    trial_state._pending_hit_cc = nil
    trial_state._hit_grace = 0
    trial_state._reset_grace = 15
    trial_state._final_finish_max_observed_combo = nil
    trial_state._pending_current_absorb = nil
    trial_state._pending_block_outcome = nil
    trial_state._consumed_action_instances = nil
    trial_state._last_matched_action_instance = nil
    trial_state._ui_step_hold_step = nil
    trial_state._ui_step_hold_until_frame = nil
    trial_state.last_played_frame = engine_frame_count
    begin_trial_action_grace()
    init_hp_restore_attempt(phase or "attempt", player_idx or trial_state.playing_player)

    reset_player_action_buffers(players[player_idx or trial_state.playing_player])
    for _, item in ipairs(trial_state.sequence) do
        item.actual_combo = 0
        item.has_hit = false
        item.last_frame_diff = nil
        item.ui_result_text = nil
        item.ui_result_kind = nil
    end
    reset_combo_visual_runtime()
    step_combo_reset_gc()
end

reset_combo_visual_runtime = function()
    if not ComboTrials_D2D then return end
    pcall(function() ComboTrials_D2D.reset_anim() end)
    pcall(function() ComboTrials_D2D.reset_raw() end)
end

step_combo_reset_gc = function()
    pcall(function() collectgarbage("step", 16) end)
end

-- =========================================================
-- END DEMO PLAYBACK AREA
-- =========================================================


local function start_recording(player_idx)
    trial_state.is_recording = true
    trial_state.recording_player = player_idx
    trial_state.sequence = {}
    trial_state.current_step = 1
    trial_state.last_recorded_frame = engine_frame_count
    trial_state._xt_pending_save = false
    trial_state._xt_pending_save_player = nil
    trial_state._xt_pending_save_error = nil
    trial_state._xt_meta_input_hint_shown = false
    trial_state._rec_environment = capture_trial_environment()
    trial_state._rec_scene_state = unique_resources.capture_scene_state(player_idx)

    players[player_idx].log = {}
    players[player_idx].input_history_queue = {}
    players[player_idx].prev_act_id = -1
    players[player_idx].prev_act_frame = -1
    players[player_idx].last_combo_count = 0
    players[player_idx].last_direct_input = 0
    reset_combo_visual_runtime()

    -- LOGGER EXPORT RECORDING INIT
    if player_idx == 0 then
        logger_state.rec_p1.data = {}
        logger_state.rec_p1.has_started = false
        logger_state.rec_p1.wait_neutral = true
        logger_state.rec_p1.active = true
    else
        logger_state.rec_p2.data = {}
        logger_state.rec_p2.has_started = false
        logger_state.rec_p2.wait_neutral = true
        logger_state.rec_p2.active = true
    end

    -- Capture live position and refresh (same behavior as start_trial)
    trial_state.start_pos_p1, trial_state.start_pos_p2, trial_state.start_pos_p1_raw, trial_state.start_pos_p2_raw =
        capture_current_positions()
    trial_state.recording_start_pos_p1 = trial_state.start_pos_p1
    trial_state.recording_start_pos_p2 = trial_state.start_pos_p2
    trial_state.recording_start_pos_p1_raw = trial_state.start_pos_p1_raw
    trial_state.recording_start_pos_p2_raw = trial_state.start_pos_p2_raw
    trial_state.first_action_pos_p1 = nil
    trial_state.first_action_pos_p2 = nil
    trial_state.first_action_pos_p1_raw = nil
    trial_state.first_action_pos_p2_raw = nil
    trial_state._rec_hp_snapshot = capture_trial_hp_snapshot(player_idx)
    apply_forced_position(true) -- skip_mirror: record in normal position

    trial_state._rec_gauges = nil
    trial_state._rec_pending_snapshot = 8
    trial_state._rec_hit_type = nil
    trial_state._piyo_detected = false
    trial_state._piyo_frame = nil
    trial_state._rec_frame_count = 0
end

local function start_trial(player_idx)
    restore_dummy_action_type()
    local was_playing = trial_state.is_playing
    clear_pending_position_injection()
    if was_playing then
        trial_state._pending_victim_hp = nil
        trial_state._pending_attacker_hp = nil
        trial_state._hp_inject_frames = 0
    else
        local starting_hp_snapshot = type(read_attacker_hp_restore_snapshot()) == "table"
        restore_trial_vital(starting_hp_snapshot)
        unique_resources.restore()
    end
    trial_state.is_recording = false
    trial_state._rec_gauges = nil
    trial_state._rec_hp_snapshot = nil
    trial_state._rec_hit_type = nil
    trial_state._rec_environment = nil
    trial_state._rec_scene_state = nil
    trial_state.is_playing = true
    trial_state.playing_player = player_idx
    trial_state._was_playing = false
    trial_state._hp_inject_frames = 0
    clear_trial_attempt_state(player_idx, "start_trial")

    trial_state.live_start_pos_p1, trial_state.live_start_pos_p2, trial_state.live_start_pos_p1_raw, trial_state.live_start_pos_p2_raw = capture_current_positions()

    -- Full display reset (Text log + D2D Raw and Animated)
    reset_combo_visual_runtime()

    save_dummy_counter_type()
    save_dummy_guard_type()
    save_dummy_action_type()

    -- INJECT FIRST-STEP TRAINING ENVIRONMENT
    apply_trial_training_environment()
    apply_hp_restore_training_setting_once("start_trial_training_setting")
    update_trial_flip_state()
    apply_forced_position()
    trial_state._pending_reinject_settings = true
end

local function clear_recording_logger(player_idx)
    local rec = (player_idx == 0) and logger_state.rec_p1 or logger_state.rec_p2
    if not rec then return end
    rec.active = false
    rec.has_started = false
    rec.wait_neutral = false
    rec.data = {}
end

local function cancel_recording()
    local canceled_player = trial_state.recording_player
    trial_state.is_recording = false
    trial_state.is_playing = false
    trial_state.sequence = {}
    trial_state.current_step = 1
    trial_state._xt_pending_save = false
    trial_state._xt_pending_save_player = nil
    trial_state._xt_pending_save_error = nil
    trial_state._rec_environment = nil
    trial_state._rec_scene_state = nil
    trial_state._rec_hp_snapshot = nil
    clear_recording_logger(canceled_player)
    -- Flush displayed input history
    reset_combo_visual_runtime()
    step_combo_reset_gc()
end

local function cancel_recording_due_to_menu(reason)
    if not trial_state.is_recording then return false end

    local canceled_player = trial_state.recording_player
    cancel_recording()

    _G.ComboTrials_ReplaySavePlayer = nil
    _G.ComboTrials_SaveFailedPlayer = nil
    _G.ComboTrials_LastSavedFilename = nil
    _G.ComboTrials_LastSavedPlayer = nil
    _G.ComboTrials_PendingSaveCanceled = canceled_player
    trial_state._recording_cancel_reason = reason or "menu"
    return true
end

local function stop_recording_and_save()
    -- Check if logger has data (for replay/BH mode where sequence stays empty)
    local logger_has_data = false
    if trial_state.recording_player == 0 then
        logger_has_data = logger_state.rec_p1.has_started and #logger_state.rec_p1.data > 0
    else
        logger_has_data = logger_state.rec_p2.has_started and #logger_state.rec_p2.data > 0
    end

    -- If nothing was recorded anywhere, act exactly like Cancel
    if #trial_state.sequence == 0 and not logger_has_data then
        local canceled_player = trial_state.recording_player
        cancel_recording()

        if canceled_player == 0 then
            logger_state.rec_p1.active = false
            logger_state.rec_p1.has_started = false
            logger_state.rec_p1.data = {}
        else
            logger_state.rec_p2.active = false
            logger_state.rec_p2.has_started = false
            logger_state.rec_p2.data = {}
        end

        _G.ComboTrials_PendingSaveCanceled = canceled_player
        return
    end

    local saved_player = trial_state.recording_player
    trial_state.is_recording = false

    -- MERGE LOGGER TIMELINE IN MEMORY (no intermediate file)
    local rec = saved_player == 0 and logger_state.rec_p1 or logger_state.rec_p2
    if rec.has_started and #rec.data > 0 and trial_state.sequence and #trial_state.sequence > 0 then
        local timeline = {}
        for _, entry in ipairs(rec.data) do
            local frame_str = tostring(entry.frames) .. "f"
            local dir_str = logger_get_numpad_notation(entry.dir)
            local btn_str = logger_get_btn_string(entry.btn)
            table.insert(timeline, string.format("%s : %s%s", frame_str, dir_str, btn_str))
        end
        trial_state.sequence[1].timeline = timeline
    end
    rec.active = false
    rec.has_started = false
    rec.data = {}

    if #trial_state.sequence == 0 then
        cancel_recording()
        _G.ComboTrials_PendingSaveCanceled = saved_player
        return
    end

    trial_state.recording_player = saved_player
    local ok, saved_path = pcall(save_trial_sequence, build_auto_xt_meta(saved_player))
    if not ok or not saved_path then
        trial_state._xt_pending_save_error = ok and "save returned no path" or tostring(saved_path)
        _G.ComboTrials_SaveFailedPlayer = saved_player
    end
end



local function load_and_start_trial(player_idx)
    if trial_state._xt_pending_save then return end
    local paths = (player_idx == 0) and file_system.saved_combos_paths_p1 or file_system.saved_combos_paths_p2
    local idx = (player_idx == 0) and (file_system.selected_file_idx_p1 or 1) or (file_system.selected_file_idx_p2 or 1)
    local path = (#paths > 0) and paths[idx] or nil
    if not path or not load_combo_from_file(path) then
        clear_combo_state()
        return
    end
    start_trial(player_idx)
end

local function reset_trial_steps()
    clear_pending_position_injection()
    clear_trial_attempt_state(trial_state.playing_player, "reset_trial")
    -- Keep the training room's health settings for the next attempt
    reinject_trial_vital()
    apply_trial_training_environment()
    apply_hp_restore_training_setting_once("reset_trial_training_setting")
    update_trial_flip_state()
    -- Reset positions if forced pos / mirror is active
    apply_forced_position()
    trial_state._pending_reinject_settings = true
end

local function refresh_combo_list_preserve_selection(reload_current_file)
    return ComboTrials_Files.refresh_combo_list_preserve_selection(reload_current_file)
end

local function refresh_combo_list(recent_saved_player)
    return ComboTrials_Files.refresh_combo_list(recent_saved_player)
end

local function combo_list_refresh_busy()
    return trial_state.is_recording
        or (demo_state and demo_state.is_playing)
        or (trial_state.pending_exact_pos and trial_state.pending_exact_pos > 0)
        or trial_state._pending_reinject_settings == true
        or is_trial_action_grace_active()
end

function file_system.log_combo_refresh(message)
    pcall(print, "[ComboTrials.Refresh] " .. tostring(message))
end

function file_system.log_combo_save(message)
    pcall(print, "[ComboTrials.Save] " .. tostring(message))
end

function file_system.diag_log(message)
    if not file_system.diag_enabled then return end
    pcall(print, "[ComboTrials.Diag] " .. tostring(message))
end

file_system.diag_log("diagnostic build loaded")

function file_system.combo_list_busy_reason(include_playing)
    if trial_state.is_recording then return "recording" end
    if include_playing and trial_state.is_playing then return "playing" end
    if demo_state and demo_state.is_playing then return "demo_playing" end
    if trial_state._xt_pending_save then return "xt_pending_save" end
    if trial_state.pending_exact_pos and trial_state.pending_exact_pos > 0 then
        return "pending_exact_pos=" .. tostring(trial_state.pending_exact_pos)
    end
    if trial_state._pending_reinject_settings == true then return "pending_reinject_settings" end
    if is_trial_action_grace_active() then return "action_grace" end
    return nil
end

function file_system.combo_list_total_count()
    return #(file_system.saved_combos_paths_p1 or {}) + #(file_system.saved_combos_paths_p2 or {})
end

function file_system.selected_combo_path_for_view()
    local player_idx = ui_state.viewed_player or trial_state.playing_player or 0
    local paths = (player_idx == 0) and file_system.saved_combos_paths_p1 or file_system.saved_combos_paths_p2
    local idx = (player_idx == 0) and (file_system.selected_file_idx_p1 or 1) or (file_system.selected_file_idx_p2 or 1)
    return paths and paths[idx] or nil
end

function file_system.request_combo_list_refresh(reason, reload_current_file)
    if reload_current_file == true and demo_state and demo_state.is_playing and ctx.stop_demo_playback then
        local current_file = trial_state.current_file_path or trial_state.current_file
        ctx.stop_demo_playback("combo_list_refresh", current_file, current_file, true)
    end
    file_system.combo_list_refresh_pending = true
    file_system.combo_list_refresh_pending_reload = file_system.combo_list_refresh_pending_reload or (reload_current_file == true)
    file_system.combo_list_refresh_pending_reason = file_system.combo_list_refresh_pending_reason or reason or "external change"
    file_system.diag_log("refresh requested reason=" .. tostring(reason)
        .. " reload=" .. tostring(reload_current_file)
        .. " pending_reload=" .. tostring(file_system.combo_list_refresh_pending_reload))
end

function ct_dev_hp_state_patch(fields)
    if type(fields) ~= "table" then return end
    for k, v in pairs(fields) do
        ct_dev_hp_restore_test_state[k] = v
    end
end

function ct_dev_deep_copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do
        out[ct_dev_deep_copy(k)] = ct_dev_deep_copy(v)
    end
    return out
end

function ct_dev_sequence_title(sequence)
    local first = type(sequence) == "table" and sequence[1] or nil
    if type(first) ~= "table" then return "" end
    local meta = type(first._xt_meta) == "table" and first._xt_meta or first._wtt_cn_meta
    if type(meta) == "table" and meta.title then return tostring(meta.title) end
    return ""
end

function ct_dev_candidate_score(path, sequence)
    local hay = tostring(path or "") .. " " .. ct_dev_sequence_title(sequence)
    local first = type(sequence) == "table" and sequence[1] or nil
    if type(first) == "table" then
        local meta = type(first._xt_meta) == "table" and first._xt_meta or first._wtt_cn_meta
        if type(meta) == "table" then
            hay = hay .. " " .. tostring(meta.note or "") .. " " .. tostring(meta.character or "")
        end
    end
    for _, step in ipairs(sequence or {}) do
        if type(step) == "table" then
            hay = hay .. " " .. tostring(step.id or "") .. " " .. tostring(step.motion or "")
        end
    end
    hay = hay:lower()

    local score = 0
    if hay:find("jamie", 1, true) then score = score + 20 end
    if hay:find("sa3", 1, true) then score = score + 50 end
    if hay:find("ca", 1, true) then score = score + 30 end
    if hay:find("236236", 1, true) then score = score + 40 end
    if hay:find("5482", 1, true) then score = score + 40 end
    if tostring(path or ""):find(CT_DEV_HP_TEST_FILENAME, 1, true) then score = score - 1000 end
    return score
end

function ct_dev_minimal_hp_test_sequence()
    return {
        {
            id = 5482,
            motion = "236236P",
            motion_aliases = {},
            delay_from_prev = 0,
            counter_type = 0,
            recorded_by = 0,
            _xt_meta = {
                title = CT_DEV_HP_TEST_TITLE,
                note = "DEV HP restore test, attacker current_hp=1000",
                author = "DEV",
                tags = { "dev", "hp_restore" },
                schema = 1
            },
            snapshot_gauges = {
                attacker = {
                    current_hp = 1000,
                    max_hp = 10000,
                    heal_hp = 1000
                }
            }
        }
    }
end

function ct_dev_find_hp_restore_template()
    local best_path, best_sequence, best_score = nil, nil, -100000

    if type(trial_state.sequence) == "table" and type(trial_state.sequence[1]) == "table" then
        local current_path = trial_state.current_file_path or trial_state.current_file or "current_loaded_sequence"
        local score = ct_dev_candidate_score(current_path, trial_state.sequence)
        if score > 0 and not tostring(current_path):find(CT_DEV_HP_TEST_FILENAME, 1, true) and score > best_score then
            best_path = current_path
            best_sequence = ct_dev_deep_copy(trial_state.sequence)
            best_score = score
        end
    end

    local glob_ok, files = false, nil
    if fs and fs.glob then
        glob_ok, files = pcall(fs.glob, "TrainingComboTrials_data\\\\CustomCombos\\\\Jamie\\\\.*json")
    end
    if glob_ok and type(files) == "table" then
        for _, path in ipairs(files) do
            if type(path) == "string"
                and not path:find("_FAIL_", 1, true)
                and not path:find(CT_DEV_HP_TEST_FILENAME, 1, true) then
                local ok, sequence = pcall(json.load_file, path)
                if ok and type(sequence) == "table" and type(sequence[1]) == "table" then
                    local score = ct_dev_candidate_score(path, sequence)
                    if score > best_score then
                        best_path = path
                        best_sequence = sequence
                        best_score = score
                    end
                end
            end
        end
    end

    if best_sequence then return best_path, best_sequence, best_score end
    return "generated_minimal_fallback", ct_dev_minimal_hp_test_sequence(), 0
end

function ct_dev_patch_hp_test_sequence(sequence)
    if type(sequence) ~= "table" or type(sequence[1]) ~= "table" then
        return nil, "template is not a combo sequence"
    end
    local out = ct_dev_deep_copy(sequence)
    local first = out[1]

    if type(first._xt_meta) ~= "table" then first._xt_meta = {} end
    first._xt_meta.title = CT_DEV_HP_TEST_TITLE
    local old_note = tostring(first._xt_meta.note or "")
    local dev_note = "DEV HP restore test, attacker current_hp=1000"
    if old_note:find(dev_note, 1, true) then
        first._xt_meta.note = old_note
    elseif old_note ~= "" then
        first._xt_meta.note = old_note .. "\n" .. dev_note
    else
        first._xt_meta.note = dev_note
    end

    local snapshot = type(first.snapshot_gauges) == "table" and first.snapshot_gauges or {}
    snapshot.attacker = {
        current_hp = 1000,
        max_hp = 10000,
        heal_hp = 1000
    }
    first.snapshot_gauges = snapshot
    return out, nil
end

function ct_dev_write_hp_restore_test_combo()
    if CT_DEV_HP_RESTORE_TEST ~= true then return false end
    if ct_dev_hp_restore_test_state.test_json_write_ok == true then return true end

    ct_dev_hp_state_patch({
        enabled = true,
        attempted = true,
        attempt_count = (ct_dev_hp_restore_test_state.attempt_count or 0) + 1,
        test_json_path = CT_DEV_HP_TEST_PATH,
        test_title = CT_DEV_HP_TEST_TITLE
    })

    if fs and fs.create_dir then
        pcall(fs.create_dir, "TrainingComboTrials_data/CustomCombos")
        pcall(fs.create_dir, "TrainingComboTrials_data/CustomCombos/Jamie")
    end

    local source_path, source_sequence, source_score = ct_dev_find_hp_restore_template()
    local test_sequence, patch_error = ct_dev_patch_hp_test_sequence(source_sequence)
    if not test_sequence then
        ct_dev_hp_state_patch({
            source_template_path = source_path,
            source_template_score = source_score,
            test_json_write_ok = false,
            test_json_write_error = patch_error or "patch failed"
        })
        write_hp_restore_debug_dump("dev_test_json_patch_failed", { dev_test = ct_dev_hp_restore_test_state })
        return false
    end

    local write_ok, write_error = pcall(json.dump_file, CT_DEV_HP_TEST_PATH, test_sequence)
    ct_dev_hp_state_patch({
        source_template_path = source_path,
        source_template_score = source_score,
        test_json_write_ok = write_ok == true,
        test_json_write_error = write_ok and nil or tostring(write_error)
    })

    file_system.diag_log("[HPRestoreDev] test_json_path=" .. tostring(CT_DEV_HP_TEST_PATH)
        .. " source=" .. tostring(source_path)
        .. " title=" .. tostring(CT_DEV_HP_TEST_TITLE)
        .. " write_ok=" .. tostring(write_ok)
        .. " error=" .. tostring(write_error))

    if write_ok then
        file_system.request_combo_list_refresh("dev hp restore test generated", false)
    end
    write_hp_restore_debug_dump(write_ok and "dev_test_json_written" or "dev_test_json_write_failed", {
        dev_test = ct_dev_hp_restore_test_state
    })
    return write_ok == true
end

function ct_dev_hp_restore_test_tick()
    if CT_DEV_HP_RESTORE_TEST ~= true then return end
    if ct_dev_hp_restore_test_state.test_json_write_ok == true then return end
    local now = engine_frame_count or 0
    if ct_dev_hp_restore_test_state.next_attempt_frame and now < ct_dev_hp_restore_test_state.next_attempt_frame then return end
    ct_dev_hp_restore_test_state.next_attempt_frame = now + 120
    ct_dev_write_hp_restore_test_combo()
end

function file_system.combo_list_external_refresh_busy()
    return file_system.combo_list_busy_reason(true) ~= nil
end

function file_system.combo_file_signature_for_player(player_idx)
    local p_state = players[player_idx]
    if not p_state then return "P" .. tostring(player_idx) .. ":missing" end

    local char_name = p_state.profile_name
    if char_name == "Unknown" then return "P" .. tostring(player_idx) .. ":Unknown" end

    if fs.create_dir then
        pcall(fs.create_dir, "TrainingComboTrials_data/CustomCombos")
        pcall(fs.create_dir, "TrainingComboTrials_data/CustomCombos/" .. char_name)
    end

    local glob_ok, files = pcall(fs.glob, "TrainingComboTrials_data\\\\CustomCombos\\\\" .. char_name .. "\\\\.*json")
    if not glob_ok or type(files) ~= "table" then
        return nil, glob_ok and "glob returned invalid data" or tostring(files)
    end

    local paths = {}
    for _, filepath in ipairs(files) do
        if type(filepath) == "string" and not filepath:find("_FAIL_", 1, true) then
            paths[#paths + 1] = filepath:gsub("\\", "/"):lower()
        end
    end
    table.sort(paths)
    file_system["diag_signature_char_p" .. tostring(player_idx)] = char_name
    file_system["diag_signature_count_p" .. tostring(player_idx)] = #paths

    return "P" .. tostring(player_idx) .. ":" .. tostring(char_name) .. ":" .. tostring(#paths) .. ":" .. table.concat(paths, "|")
end

function file_system.build_combo_file_signature()
    local p1_sig, p1_err = file_system.combo_file_signature_for_player(0)
    if not p1_sig then return nil, p1_err end
    local p2_sig, p2_err = file_system.combo_file_signature_for_player(1)
    if not p2_sig then return nil, p2_err end
    file_system.combo_list_signature_warn_counter = 0
    file_system.diag_signature_counter = file_system.diag_signature_counter + 1
    if file_system.diag_signature_counter == 1 or file_system.diag_signature_counter >= 10 then
        file_system.diag_log("signature check p1=" .. tostring(file_system.diag_signature_char_p0)
            .. " count=" .. tostring(file_system.diag_signature_count_p0)
            .. " p2=" .. tostring(file_system.diag_signature_char_p1)
            .. " count=" .. tostring(file_system.diag_signature_count_p1))
        file_system.diag_signature_counter = 1
    end
    return p1_sig .. "\n" .. p2_sig
end

function file_system.warn_combo_signature_failure(reason)
    file_system.combo_list_signature_warn_counter = file_system.combo_list_signature_warn_counter + 1
    if file_system.combo_list_signature_warn_counter == 1 or file_system.combo_list_signature_warn_counter >= 600 then
        file_system.log_combo_refresh("signature check failed: " .. tostring(reason))
        file_system.combo_list_signature_warn_counter = 1
    end
end

function file_system.run_pending_combo_list_refresh()
    if not file_system.combo_list_refresh_pending then return false end
    if not trial_state._vital_initialized or file_system.combo_list_external_refresh_busy() then
        if not file_system.combo_list_refresh_deferred_logged then
            local reason = file_system.combo_list_busy_reason(true)
            if not trial_state._vital_initialized then reason = "not_initialized" end
            file_system.log_combo_refresh("refresh deferred: busy reason=" .. tostring(reason))
            file_system.combo_list_refresh_deferred_logged = true
        end
        return true
    end

    local old_count = file_system.combo_list_total_count()
    local reload_current_file = file_system.combo_list_refresh_pending_reload
    local reason = file_system.combo_list_refresh_pending_reason or "external change"
    file_system.combo_list_refresh_pending = false
    file_system.combo_list_refresh_pending_reload = false
    file_system.combo_list_refresh_pending_reason = nil
    file_system.combo_list_refresh_deferred_logged = false

    refresh_combo_list_preserve_selection(reload_current_file)

    local refreshed_signature, signature_error = file_system.build_combo_file_signature()
    if refreshed_signature then
        file_system.combo_list_last_signature = refreshed_signature
    elseif signature_error then
        file_system.warn_combo_signature_failure(signature_error)
    end

    local new_count = file_system.combo_list_total_count()
    file_system.log_combo_refresh("refresh completed old_count=" .. tostring(old_count) .. " new_count=" .. tostring(new_count) .. " reason=" .. tostring(reason))

    local restored_path = file_system.selected_combo_path_for_view()
    if restored_path then
        file_system.log_combo_refresh("selection restored path=" .. tostring(restored_path))
    end

    return true
end

local function trim_string(value)
    return (tostring(value or ""):match("^%s*(.-)%s*$") or "")
end

function file_system.sanitize_filename_component(value, max_chars, fallback)
    return _G.ComboTrials_sanitize_filename_component(value, max_chars, fallback)
end

function file_system.file_exists(path)
    local f = io.open(path, "rb")
    if not f then return false end
    f:close()
    return true
end

function file_system.get_safe_filename_motion(sequence)
    local raw_motion = sequence and sequence[1] and sequence[1].motion or ""
    local motion = trim_string(raw_motion)
    if motion == "" then return "UNKNOWN" end

    motion = motion:gsub("^>%s*", "")
    motion = motion:gsub("%s*%(([^%)]*)%)", function(tag)
        local upper_tag = tostring(tag or ""):upper()
        if tag == "空挥" or tag == "绌烘尌" or tag == "打康" or tag == "确反康"
            or upper_tag == "WHIFF" or upper_tag == "CH" or upper_tag == "PC"
            or upper_tag == "COUNTER" or upper_tag == "COUNTER HIT"
            or upper_tag == "PUNISH" or upper_tag == "PUNISH COUNTER" then
            return ""
        end
        return "(" .. tag .. ")"
    end)
    motion = motion:gsub("空挥", "")
    motion = motion:gsub("绌烘尌", "")
    motion = motion:gsub("打康", "")
    motion = motion:gsub("确反康", "")
    motion = motion:gsub("%f[%a][Ww][Hh][Ii][Ff][Ff]%f[%A]", "")
    motion = motion:gsub("%f[%a][Cc][Hh]%f[%A]", "")
    motion = motion:gsub("%f[%a][Pp][Cc]%f[%A]", "")
    motion = motion:gsub("%f[%a][Cc][Oo][Uu][Nn][Tt][Ee][Rr]%s+[Hh][Ii][Tt]%f[%A]", "")
    motion = motion:gsub("%f[%a][Pp][Uu][Nn][Ii][Ss][Hh]%s+[Cc][Oo][Uu][Nn][Tt][Ee][Rr]%f[%A]", "")
    motion = motion:gsub("%f[%a][Cc][Oo][Uu][Nn][Tt][Ee][Rr]%f[%A]", "")
    motion = motion:gsub("%f[%a][Pp][Uu][Nn][Ii][Ss][Hh]%f[%A]", "")

    local motion_id = file_system.sanitize_filename_component(motion, nil, "")
    if motion_id == "" then return "UNKNOWN" end
    return motion_id
end

local POS_TICKER_NAMES = { "任意位置", "原始位置", "镜像位置" }
local function ct_ticker(msg)
    if _G.show_custom_ticker then _G.show_custom_ticker(msg, 0.3) end
end

-- =========================================================
-- UNIVERSAL CHARGE STATE MACHINE
-- =========================================================
local function evaluate_charge_status(char_name, frames, c_min, c_max, p_min, p_max)
    if char_name == "Luke" and p_min then
        local insta_threshold = c_min or (p_min - 5)
        if frames <= insta_threshold then return "Instant" end
        if frames >= p_min and frames <= (p_max or p_min+2) then return "PERFECT!" end
        if frames < p_min then return "Partial" end
        return "LATE"
    elseif char_name == "JP" then
        if c_min and frames <= c_min then return "Instant" end
        if c_max and frames >= c_max then return "FAKE" end
        return "Partial"
    elseif char_name == "Lily" then
        if c_min and frames <= c_min then return "Lv1" end
        if c_max and frames >= c_max then return "Lv3" end
        return "Lv2"
    else
        if c_min and frames <= c_min then return "Instant" end
        if c_max and frames >= c_max then return "Maxed" end
        if frames > 0 then return "Partial" end
        return "Instant"
    end
end

-- =========================================================
-- SKIP K.O. & ROUND END ANIMATIONS (Ported from ReplayLabs)
-- =========================================================
local function setup_hook(type_name, method_name, pre_func, post_func)
    local type_def = sdk.find_type_definition(type_name)
    if type_def then
        local method = type_def:get_method(method_name)
        if method then
            pcall(function() sdk.hook(method, pre_func, post_func) end)
        end
    end
end

setup_hook("app.battle.bBattleFlow", "updateKO", nil, function(retval)
    if trial_state.is_playing or trial_state.is_recording or (demo_state and demo_state.is_playing) then
        -- Skip KO animation, but do not mark a trial as complete until the
        -- sequence validation has actually reached the final step.
        if trial_state.is_playing and not (demo_state and demo_state.is_playing) and trial_state.success_timer == 0 then
            local seq = trial_state.sequence or {}
            local last_step = seq[#seq]
            local attacker = (trial_state.playing_player == 1) and GS.p2 or GS.p1
            local combo_count = math.max(get_combo_count(attacker) or 0, last_step and (last_step.actual_combo or 0) or 0)
            if #seq > 0 and trial_state.current_step > #seq and last_step
                and (not last_step.expected_combo or last_step.expected_combo == 0 or combo_count >= last_step.expected_combo) then
                trial_state.success_timer = d2d_cfg.fail_display_frames or 120
            end
        end
        return sdk.to_ptr(2) -- 2 = Skip animation
    end
    return retval
end)

setup_hook("app.battle.bBattleFlow", "updateRoundResult", nil, function(retval)
    if trial_state.is_playing or trial_state.is_recording or (demo_state and demo_state.is_playing) then
        return sdk.to_ptr(2)
    end
    return retval
end)

-- =========================================================
-- HOISTED HOT-PATH HELPERS (no per-frame closure allocations)
-- =========================================================
local function _ct_track_live_combo()
    local p1 = GS.p1
    if not p1 then return end
    local cc = p1:get_type_definition():get_field("combo_cnt"):get_data(p1) or 0

    if not trial_state._onframe_last_cc then trial_state._onframe_last_cc = 0 end

    if trial_state._pending_hit_delay and trial_state._pending_hit_delay > 0 then
        trial_state._pending_hit_delay = trial_state._pending_hit_delay - 1
        if trial_state._pending_hit_delay == 0 and trial_state.is_recording and #trial_state.sequence > 0 then
            local last = trial_state.sequence[#trial_state.sequence]
            last.has_hit = true
            last.expected_combo = trial_state._pending_hit_cc
            trial_state._pending_hit_cc = nil
        end
    end

    if cc > trial_state._onframe_last_cc then
        trial_state._hit_grace = 5
        if trial_state.is_recording and #trial_state.sequence > 0 then
            trial_state._pending_hit_cc = cc
            trial_state._pending_hit_delay = 2
        end
    end

    if trial_state._hit_grace and trial_state._hit_grace > 0 then
        trial_state._hit_grace = trial_state._hit_grace - 1
    end

    trial_state._onframe_last_cc = cc
end

local function _ct_update_flip_live()
    local p1 = GS.p1
    local p2 = GS.p2
    if not p1 or not p2 then return end
    local r1 = p1.pos.x.v
    local r2 = p2.pos.x.v
    local facing_left = false
    if trial_state.playing_player == 0 then
        facing_left = (r1 > r2)
    else
        facing_left = (r2 > r1)
    end
    trial_state.flip_inputs = facing_left
end

local function _ct_replay_bridge_poll()
    local frames = file_system.replay_bridge_poll_frames or 10
    file_system.replay_bridge_poll_counter = (file_system.replay_bridge_poll_counter or frames) + 1
    if file_system.replay_bridge_poll_counter < frames then return end
    file_system.replay_bridge_poll_counter = 0

    local b = json.load_file("SF6_TrainingRemoteControl_data/Replay_WebBridge.json")
    if b and b._web_timestamp then
        if not _G._replay_bridge_ts then _G._replay_bridge_ts = 0 end
        if b._web_timestamp > _G._replay_bridge_ts then
            _G._replay_bridge_ts = b._web_timestamp
            if b.cmd == "record_p1" then _G.ComboTrials_ReplaySavePlayer = 0; start_recording(0) end
            if b.cmd == "record_p2" then _G.ComboTrials_ReplaySavePlayer = 1; start_recording(1) end
            if b.cmd == "stop_save" then _G.ComboTrials_ReplaySavePlayer = trial_state.recording_player; stop_recording_and_save() end
            if b.cmd == "cancel" then
                local cp = trial_state.recording_player
                cancel_recording()
                _G.ComboTrials_ReplayCanceled = cp
            end
            if b.cmd == "hide_ui" then _G._tsm_hide_ui = not _G._tsm_hide_ui end
        end
    end
end

local function _ct_detect_piyo()
    local p2 = GS.p2
    if not p2 then return end
    local eng = p2.mpActParam.ActionPart._Engine
    if eng and (eng:get_ActionID() == 293 or eng:get_ActionID() == 294) then
        trial_state._piyo_detected = true
        trial_state._piyo_frame = trial_state._rec_frame_count
    end
end

local function _ct_check_first_hit()
    local attacker_char = (trial_state.playing_player == 0) and GS.p1 or GS.p2
    if attacker_char and get_combo_count(attacker_char) > 0 then
        trial_state._first_hit_landed = true
    end
end

local function _ct_get_player(player_obj, idx)
    return player_obj:call("getPlayer", idx)
end

local function _ct_track_rec_gauges(victim, p_char, p_idx)
    local BT = _td_gBattle:get_field("Team"):get_data(nil)
    if victim and BT and BT.mcTeam then
        local v_hp = victim.vital_new
        local a_dr = p_char.focus_new
        local a_sa = BT.mcTeam[p_idx].mSuperGauge

        local rg = trial_state._rec_gauges
        if v_hp and rg.min_victim_hp then rg.min_victim_hp = math.min(rg.min_victim_hp, v_hp) end
        if a_dr and rg.min_atk_drive then rg.min_atk_drive = math.min(rg.min_atk_drive, a_dr) end
        if a_sa and rg.min_atk_super then rg.min_atk_super = math.min(rg.min_atk_super, a_sa) end
    end
end

local function _ct_capture_rec_hit_type(victim_obj)
    if victim_obj then
        local pc = victim_obj:get_type_definition():get_field("counter_fw_flag"):get_data(victim_obj)
        local ch = victim_obj:get_type_definition():get_field("counter_dm_flag"):get_data(victim_obj)
        if pc == true then
            trial_state._rec_hit_type = "PC"
        elseif ch == true and trial_state._rec_hit_type ~= "PC" then
            trial_state._rec_hit_type = "CH"
        end
    end
end

local function _ct_check_knockdown(victim_obj)
    if not victim_obj then return false end
    local pose_st = victim_obj:get_type_definition():get_field("pose_st"):get_data(victim_obj)
    return (pose_st or 0) == 3
end

local function is_pressure_tail_step(step)
    return Validator.is_pressure_tail_step(step)
end

local function is_post_hit_setup_step(step_idx)
    if not trial_state.sequence or not step_idx or step_idx < 1 then return false end
    local step = trial_state.sequence[step_idx]
    if not step or step.expected_combo ~= 0 then return false end
    if is_pressure_tail_step(step) then return false end
    if step.has_hit == true then return false end
    local step_damage = tonumber(step.damage_at_step) or 0
    local prev = step_idx > 1 and trial_state.sequence[step_idx - 1] or nil
    local prev_damage = prev and (tonumber(prev.damage_at_step) or 0) or 0
    if step_damage > prev_damage then return false end
    for i = 1, step_idx - 1 do
        local earlier = trial_state.sequence[i]
        if earlier and (earlier.expected_combo or 0) > 0 then
            return true
        end
    end
    return false
end

local function is_same_action_continuation_step(prev_step, step, combo_count, current_action_instance)
    if not prev_step or not step then return false end
    if prev_step.id == nil or step.id == nil then return false end
    if prev_step.id ~= step.id then return false end
    local timeline_expanded_repeat = step._ct_timeline_expanded == true
    if prev_step.action_instance and current_action_instance
        and prev_step.action_instance == current_action_instance
        and not timeline_expanded_repeat then
        return false
    end

    local prev_combo = tonumber(prev_step.expected_combo) or 0
    local expected_combo = tonumber(step.expected_combo) or 0
    local current_combo = combo_count or 0
    if expected_combo <= 0 or expected_combo <= prev_combo then return false end
    if current_combo < expected_combo then return false end
    return true
end

function ct_is_zero_combo_pressure_validation_step(step)
    if type(step) ~= "table" then return false end
    if step.display_only == true then return false end
    if (tonumber(step.expected_combo) or 0) ~= 0 then return false end
    if step.hit_result == "block" then return true end

    local motion = tostring(step.motion or "")
    local motion_upper = motion:upper()
    if motion:find("空挥", 1, true) ~= nil or motion_upper:find("WHIFF", 1, true) ~= nil then
        return true
    end
    return step.has_hit ~= true and (tonumber(step.damage_at_step) or 0) == 0
end

function ct_is_unreported_same_action_pressure_step(prev_step, step)
    if not prev_step or not step then return false end
    if prev_step.id == nil or step.id == nil then return false end
    if prev_step.id ~= step.id then return false end
    return ct_is_zero_combo_pressure_validation_step(prev_step)
        and ct_is_zero_combo_pressure_validation_step(step)
end

function ct_should_ignore_duplicate_previous_pressure_action(prev_step, expected, act_id, candidate_action_instance)
    if not prev_step or not expected then return false end
    if prev_step.id == nil or expected.id == nil or act_id == nil then return false end
    if prev_step.id ~= act_id then return false end
    if expected.id == act_id then return false end
    if prev_step.action_instance and candidate_action_instance
        and prev_step.action_instance ~= candidate_action_instance then
        return false
    end
    return ct_is_zero_combo_pressure_validation_step(prev_step)
end

function ct_try_skip_unreported_same_action_pressure_step(args)
    if type(args) ~= "table" then return nil end
    if not args.expected or args.action_match_matched then return nil end
    if not ct_is_unreported_same_action_pressure_step(args.prev_step, args.expected) then return nil end

    local state = args.state
    local sequence = state and state.sequence or nil
    local current_step = state and state.current_step or nil
    if type(sequence) ~= "table" or not current_step then return nil end

    local next_step_idx = current_step + 1
    local next_expected = sequence[next_step_idx]
    if not next_expected then return nil end

    local next_action_match = args.ActionMatcher.match_expected_action(
        next_expected,
        args.act_id,
        args.motion,
        args.input
    )
    if not next_action_match or not next_action_match.matched then return nil end

    local validation_frame = args.synthetic and (args.synthetic_frame or engine_frame_count) or engine_frame_count
    local last_played = state.last_played_frame or validation_frame
    local virtual_frame = validation_frame - (tonumber(next_expected.delay_from_prev) or 0)
    local min_virtual_frame = last_played + (tonumber(args.expected.delay_from_prev) or 0)
    if virtual_frame < min_virtual_frame then virtual_frame = min_virtual_frame end

    args.expected.actual_combo = math.max(tonumber(args.expected.actual_combo) or 0, args.combo_count or 0)
    local raw_frame_diff = args.Validator.calculate_frame_diff(
        virtual_frame - last_played,
        args.expected.delay_from_prev
    )
    args.expected.last_frame_diff = raw_frame_diff
    ComboTrialsModules.PendingAbsorb.set_timing_ui_result(state, current_step, args.expected.last_frame_diff)
    state.last_played_frame = virtual_frame
    state.current_step = next_step_idx
    state.ui_visual_step = state.current_step
    state.floating_info = nil

    local probe = args.match_probe
    if probe then
        probe.branch = "pressure_same_action_unreported_skip"
        probe.reject_reason = nil
        probe.skipped_step = next_step_idx - 1
        probe.skipped_expected_id = args.expected.id
        probe.skipped_expected_motion = args.expected.motion
        probe.next_step = next_step_idx
        probe.next_expected_id = next_expected.id
        probe.next_expected_motion = next_expected.motion
        probe.next_action_match = {
            matched = next_action_match.matched,
            match_reason = next_action_match.match_reason,
            expected_id = next_action_match.expected_id,
            actual_action_id = next_action_match.actual_action_id
        }
        args.DebugTrace.record_match_probe(state, probe)
    end

    return {
        expected = next_expected,
        action_match = next_action_match,
        prev_step = state.current_step > 1 and sequence[state.current_step - 1] or nil
    }
end

local function build_same_action_auto_advance_debug(prev_step, step, combo_count, call_site)
    local current_player = players[trial_state.playing_player or 0]
    local current_action_instance = current_player and current_player.current_action_instance or nil
    local prev_combo = prev_step and (tonumber(prev_step.expected_combo) or 0) or nil
    local expected_combo = step and (tonumber(step.expected_combo) or 0) or nil
    local current_combo = combo_count or 0
    local same_id = prev_step and step and prev_step.id ~= nil and step.id ~= nil and prev_step.id == step.id
    local combo_progression = expected_combo ~= nil and prev_combo ~= nil and expected_combo > 0 and expected_combo > prev_combo
    local timeline_expanded_repeat = step and step._ct_timeline_expanded == true
    local block_reason = nil

    if not prev_step or not step then
        block_reason = "missing_prev_or_step"
    elseif prev_step.id == nil or step.id == nil then
        block_reason = "missing_step_id"
    elseif prev_step.id ~= step.id then
        block_reason = "different_action_id"
    elseif prev_step.action_instance and current_action_instance
        and prev_step.action_instance == current_action_instance
        and not timeline_expanded_repeat then
        block_reason = "same_action_instance_duplicate"
    elseif expected_combo <= 0 then
        block_reason = "expected_combo_not_positive"
    elseif expected_combo <= prev_combo then
        block_reason = "expected_combo_not_greater_than_prev"
    elseif current_combo < expected_combo then
        if prev_step.has_hit ~= true then
            block_reason = "previous_step_not_hit_and_combo_not_reached"
        else
            block_reason = "combo_not_reached"
        end
    elseif prev_step.has_hit ~= true then
        block_reason = "combo_progress_confirmed_without_previous_hit"
    else
        block_reason = "would_advance"
    end

    return {
        auto_advance_candidate = same_id and combo_progression or false,
        auto_advance_triggered = false,
        auto_advance_prev_step = trial_state.current_step and (trial_state.current_step - 1) or nil,
        auto_advance_step = trial_state.current_step,
        auto_advance_prev_id = prev_step and prev_step.id or nil,
        auto_advance_step_id = step and step.id or nil,
        auto_advance_prev_combo = prev_combo,
        auto_advance_expected_combo = expected_combo,
        auto_advance_current_combo = current_combo,
        auto_advance_combo_count = current_combo,
        auto_advance_prev_action_instance = prev_step and prev_step.action_instance or nil,
        auto_advance_current_action_instance = current_action_instance,
        auto_advance_timeline_expanded_repeat = timeline_expanded_repeat,
        auto_advance_block_reason = block_reason,
        auto_advance_call_site = call_site,
        auto_advance_checked_at_frame = engine_frame_count
    }
end

local function advance_same_action_continuation_steps(combo_count, call_site)
    call_site = call_site or "unknown"
    if not trial_state.sequence or not trial_state.current_step then
        DebugTrace.record_auto_advance(trial_state, {
            auto_advance_candidate = false,
            auto_advance_triggered = false,
            auto_advance_current_combo = combo_count or 0,
            auto_advance_combo_count = combo_count or 0,
            auto_advance_block_reason = "missing_sequence_or_current_step",
            auto_advance_call_site = call_site,
            auto_advance_checked_at_frame = engine_frame_count
        })
        return false
    end

    local advanced = false
    if trial_state.current_step <= 1 then
        DebugTrace.record_auto_advance(trial_state, {
            auto_advance_candidate = false,
            auto_advance_triggered = false,
            auto_advance_step = trial_state.current_step,
            auto_advance_current_combo = combo_count or 0,
            auto_advance_combo_count = combo_count or 0,
            auto_advance_block_reason = "current_step_not_after_first_step",
            auto_advance_call_site = call_site,
            auto_advance_checked_at_frame = engine_frame_count
        })
    elseif trial_state.current_step > #trial_state.sequence then
        DebugTrace.record_auto_advance(trial_state, {
            auto_advance_candidate = false,
            auto_advance_triggered = false,
            auto_advance_step = trial_state.current_step,
            auto_advance_current_combo = combo_count or 0,
            auto_advance_combo_count = combo_count or 0,
            auto_advance_block_reason = "current_step_past_sequence",
            auto_advance_call_site = call_site,
            auto_advance_checked_at_frame = engine_frame_count
        })
    end

    while trial_state.current_step > 1 and trial_state.current_step <= #trial_state.sequence do
        local prev_step = trial_state.sequence[trial_state.current_step - 1]
        local step = trial_state.sequence[trial_state.current_step]
        local auto_advance_debug = build_same_action_auto_advance_debug(prev_step, step, combo_count, call_site)
        local current_player = players[trial_state.playing_player or 0]
        local current_action_instance = current_player and current_player.current_action_instance or nil
        if not is_same_action_continuation_step(prev_step, step, combo_count, current_action_instance) then
            if not advanced then
                DebugTrace.record_auto_advance(trial_state, auto_advance_debug)
            end
            break
        end
        auto_advance_debug.auto_advance_triggered = true
        auto_advance_debug.auto_advance_block_reason = "advanced"
        DebugTrace.record_auto_advance(trial_state, auto_advance_debug)

        step.has_hit = true
        step.actual_combo = math.max(tonumber(step.actual_combo) or 0, combo_count or 0)
        step.action_instance = current_action_instance
        if current_action_instance ~= nil then
            trial_state._consumed_action_instances = trial_state._consumed_action_instances or {}
            trial_state._consumed_action_instances[current_action_instance] = trial_state.current_step
            trial_state._last_matched_action_instance = current_action_instance
        end
        step.last_frame_diff = 0
        ComboTrialsModules.PendingAbsorb.set_timing_ui_result(trial_state, trial_state.current_step, step.last_frame_diff)
        trial_state.current_step = trial_state.current_step + 1
        trial_state.last_played_frame = engine_frame_count
        trial_state.ui_visual_step = trial_state.current_step
        trial_state.floating_info = nil

        local next_step = trial_state.sequence[trial_state.current_step]
        if next_step and next_step.counter_type then
            set_dummy_counter_type(next_step.counter_type)
        else
            set_dummy_counter_type(0)
        end

        advanced = true
    end

    return advanced
end

-- =========================================================
-- PER-FRAME PLAYER CONTEXT (reused each player-loop iteration)
-- =========================================================
local _replay_cleaned = false

-- =========================================================
-- EXTRACTED ON_FRAME SUBSYSTEMS
-- =========================================================

local function ct_handle_web_commands()
    if _G.CurrentTrainerMode == 4 and _G._tsm_web_cmd then
        local cmd = _G._tsm_web_cmd; _G._tsm_web_cmd = nil
        if cmd == "record" then start_recording(0); ct_ticker("录制中") end
        if cmd == "start_trial" then load_and_start_trial(0); ct_ticker("连段训练已启动") end
        if cmd == "stop_trial" then
            if ctx.stop_demo_playback then
                ctx.stop_demo_playback(
                    "manual_stop",
                    demo_state.current_file_path or trial_state.current_file_path or trial_state.current_file,
                    nil,
                    true
                )
            end
            trial_state.is_playing = false; ct_ticker("连段训练已停止")
            restore_trial_defense_settings()
        end
        if cmd == "toggle_position" then
            d2d_cfg.forced_position_idx = (d2d_cfg.forced_position_idx or 1) + 1
            if d2d_cfg.forced_position_idx > 3 then d2d_cfg.forced_position_idx = 1 end
            apply_forced_position()
            ct_ticker("位置模式：" .. (POS_TICKER_NAMES[d2d_cfg.forced_position_idx] or ""))
        end
        if cmd == "cancel_record" then
            _G.ComboTrials_ReplayCancelPlayer = trial_state.recording_player or 0
            cancel_recording(); ct_ticker("录制已取消")
        end
        if cmd == "stop_record" then stop_recording_and_save(); ct_ticker("录制已保存") end
        if cmd == "reset_trial" then
            local ok, err = pcall(function()
                if not trial_state.is_playing then return end
                local curr_player = trial_state.playing_player
                if #trial_state.sequence > 0 then
                    trial_state.is_playing = true
                    trial_state.playing_player = curr_player
                    reset_trial_steps()
                end
            end)
        end
        if cmd == "demo" then
            pcall(function()
                if not trial_state.is_playing then return end
                if ctx.start_demo then ctx.start_demo() end
            end)
        end
        if cmd == "restart_demo" then
            pcall(function()
                if ctx.start_demo then ctx.start_demo() end
            end)
        end
        if cmd == "quit_demo" then
            pcall(function()
                if ctx.stop_demo then ctx.stop_demo() end
            end)
        end
        if cmd == "mirror" and trial_state.is_playing then
            d2d_cfg.forced_position_idx = d2d_cfg.forced_position_idx == 3 and 2 or 3
            if apply_forced_position then apply_forced_position() end
        end
        if type(cmd) == "string" and cmd:match("^select_file:") then
            local idx = tonumber(cmd:match("^select_file:(%d+)"))
            if idx then
                local p = trial_state.playing_player or 0
                if p == 0 then file_system.selected_file_idx_p1 = idx
                else file_system.selected_file_idx_p2 = idx end
                if trial_state.is_playing then
                    load_and_start_trial(p)
                end
            end
        end
    end
end

local function ct_auto_refresh_combo_list()
    if file_system.diag_last_mode ~= _G.CurrentTrainerMode then
        file_system.diag_last_mode = _G.CurrentTrainerMode
        file_system.diag_log("mode changed current=" .. tostring(_G.CurrentTrainerMode))
    end

    if _G.CurrentTrainerMode ~= 4 then
        file_system.combo_list_pending_save_refreshed = false
        file_system.combo_list_auto_refresh_counter = 0
        file_system.combo_list_was_active = false
        file_system.combo_list_last_signature = nil
        return
    end

    local busy = combo_list_refresh_busy()
    local busy_reason = file_system.combo_list_busy_reason(false)
    if file_system.diag_last_busy_reason ~= busy_reason then
        file_system.diag_last_busy_reason = busy_reason
        file_system.diag_log("refresh busy reason=" .. tostring(busy_reason or "none"))
    end

    if not file_system.combo_list_was_active then
        file_system.combo_list_was_active = true
        file_system.combo_list_auto_refresh_counter = 0
        file_system.combo_list_pending_save_refreshed = false
        file_system.diag_log("combo list became active viewed_player=" .. tostring(ui_state.viewed_player)
            .. " p1=" .. tostring(players[0] and players[0].profile_name)
            .. " p2=" .. tostring(players[1] and players[1].profile_name))
        if not busy and not trial_state._xt_pending_save then
            refresh_combo_list_preserve_selection(true)
            local signature, signature_error = file_system.build_combo_file_signature()
            if signature then
                file_system.combo_list_last_signature = signature
            elseif signature_error then
                file_system.warn_combo_signature_failure(signature_error)
            end
        end
    end

    if trial_state._xt_pending_save then
        if file_system.combo_list_pending_save_refreshed then return end
        file_system.combo_list_pending_save_refreshed = true
        file_system.diag_log("xt pending save refresh path")
        refresh_combo_list_preserve_selection(false)
        return
    end

    file_system.combo_list_pending_save_refreshed = false
    if file_system.run_pending_combo_list_refresh() then return end
    if busy then return end
    if not file_system.combo_list_auto_refresh_enabled and rawget(_G, "CT_AUTO_FILE_SCAN") ~= true then return end

    file_system.combo_list_auto_refresh_counter = file_system.combo_list_auto_refresh_counter + 1
    if file_system.combo_list_auto_refresh_counter >= file_system.combo_list_auto_refresh_frames then
        file_system.combo_list_auto_refresh_counter = 0
        local signature, signature_error = file_system.build_combo_file_signature()
        if not signature then
            file_system.warn_combo_signature_failure(signature_error or "unknown signature error")
            return
        end
        if file_system.combo_list_last_signature == nil then
            file_system.combo_list_last_signature = signature
            file_system.diag_log("signature baseline initialized")
            return
        end
        if signature ~= file_system.combo_list_last_signature then
            file_system.log_combo_refresh("external file signature changed")
            file_system.request_combo_list_refresh("external file signature changed", true)
            file_system.run_pending_combo_list_refresh()
        end
    end
end

local function read_trialhub_sync_signal()
    local paths = {
        "TrainingComboTrials_data/../TrialHub/sync_signal.json",
        "TrialHub/sync_signal.json"
    }
    for _, path in ipairs(paths) do
        local ok_open, f = pcall(io.open, path, "r")
        if ok_open and f then
            local raw = f:read("*a") or ""
            f:close()
            local trimmed = raw:match("^%s*(.-)%s*$") or ""
            if trimmed ~= "" then
                if file_system.trialhub_signal_last_path == path
                    and file_system.trialhub_signal_last_raw == raw then
                    return file_system.trialhub_signal_last_data, file_system.trialhub_signal_last_error, path
                end

                local ok, data = pcall(json.load_file, path)
                file_system.trialhub_signal_last_path = path
                file_system.trialhub_signal_last_raw = raw
                if ok and type(data) == "table" then
                    file_system.trialhub_signal_last_data = data
                    file_system.trialhub_signal_last_error = nil
                    file_system.trialhub_sync_warn_counter = 0
                    return data, nil, path
                elseif not ok then
                    file_system.trialhub_signal_last_data = nil
                    file_system.trialhub_signal_last_error = data
                    return nil, data, path
                else
                    file_system.trialhub_signal_last_data = nil
                    file_system.trialhub_signal_last_error = nil
                end
            end
        elseif not ok_open then
            return nil, f, path
        end
    end
    return nil, nil, nil
end

local function ct_poll_trialhub_sync_signal()
    if _G.CurrentTrainerMode ~= 4 then
        file_system.trialhub_sync_counter = 0
        return
    end

    file_system.trialhub_sync_counter = file_system.trialhub_sync_counter + 1
    if file_system.trialhub_sync_counter < file_system.trialhub_sync_poll_frames then return end
    file_system.trialhub_sync_counter = 0

    local signal, read_error, signal_path = read_trialhub_sync_signal()
    if not signal then
        if read_error then
            file_system.trialhub_sync_warn_counter = file_system.trialhub_sync_warn_counter + 1
            if file_system.trialhub_sync_warn_counter == 1 or file_system.trialhub_sync_warn_counter >= 20 then
                file_system.log_combo_refresh("sync signal read failed path=" .. tostring(signal_path) .. " error=" .. tostring(read_error))
                file_system.trialhub_sync_warn_counter = 1
            end
        else
            file_system.diag_no_signal_counter = file_system.diag_no_signal_counter + 1
            if file_system.diag_no_signal_counter == 1 or file_system.diag_no_signal_counter >= 20 then
                file_system.diag_log("sync signal not found")
                file_system.diag_no_signal_counter = 1
            end
        end
        return
    end
    file_system.diag_no_signal_counter = 0

    local version = signal.version
    local time_value = signal.time or signal.updated_at
    if version == nil and time_value == nil then
        file_system.diag_invalid_signal_counter = file_system.diag_invalid_signal_counter + 1
        if file_system.diag_invalid_signal_counter == 1 or file_system.diag_invalid_signal_counter >= 20 then
            file_system.diag_log("sync signal invalid path=" .. tostring(signal_path)
                .. " version=nil time=nil updated_at=nil")
            file_system.diag_invalid_signal_counter = 1
        end
        return
    end
    file_system.diag_invalid_signal_counter = 0

    local marker = tostring(version or "") .. "|" .. tostring(time_value or "")
    if not file_system.trialhub_last_marker then
        file_system.trialhub_last_marker = marker
        file_system.request_combo_list_refresh("marker initialized", true)
        file_system.log_combo_refresh("marker initialized, refresh requested")
        file_system.diag_log("sync marker initialized path=" .. tostring(signal_path)
            .. " marker=" .. tostring(marker))
        return
    end
    if marker == file_system.trialhub_last_marker then return end

    file_system.diag_log("sync marker changed path=" .. tostring(signal_path)
        .. " old=" .. tostring(file_system.trialhub_last_marker)
        .. " new=" .. tostring(marker))
    file_system.trialhub_last_marker = marker
    local busy = trial_state.is_recording or trial_state.is_playing or trial_state._xt_pending_save or (demo_state and demo_state.is_playing)
    if busy then
        file_system.request_combo_list_refresh("external sync marker changed", true)
        ct_ticker("训练库已更新")
        return
    end

    file_system.request_combo_list_refresh("external sync marker changed", true)
end

local function ct_handle_replay_cleanup(_in_replay)
    if _in_replay and not _replay_cleaned then
        _replay_cleaned = true
        if trial_state.is_playing then
            trial_state.is_playing = false
            trial_state._was_playing = false
        end
        if demo_state and demo_state.is_playing then demo_state.is_playing = false end
        trial_state.flip_inputs = false
        trial_state.floating_info = nil
        trial_state._vital_initialized = false
        trial_state._pause_live_r1 = nil
        trial_state._pause_live_r2 = nil
        trial_state._unpause_delay = nil
        trial_state.pending_exact_pos = nil
        _G.ComboTrials_HideNativeHUD = false
    elseif not _in_replay then
        _replay_cleaned = false
    end
end

local function ct_handle_mode_exit()
    if _G.CurrentTrainerMode ~= 4 then
        _G.ComboTrialsD2DEnabled = false
        _G.ComboTrials_HideNativeHUD = false
        _G._ct_bar_geometry = nil
        _G.TrainingBarsDrawn = false
        reset_combo_visual_runtime()
        -- Clean shutdown if switching scripts during an active Trial/Demo
        if trial_state.is_playing or (demo_state and demo_state.is_playing) then
            trial_state.is_playing = false
            trial_state._was_playing = false
            if demo_state then demo_state.is_playing = false end

            restore_trial_vital()
            unique_resources.restore()
            restore_trial_defense_settings()
            restore_dummy_counter_type()
            restore_dummy_guard_type()
            restore_dummy_action_type()
            apply_current_position_refresh()
        elseif trial_state.is_recording then
            cancel_recording()
        end
        trial_state._vital_initialized = false
        return
    end
end

local function ct_handle_first_frame_init()
    if not trial_state._vital_initialized then
        trial_state._vital_initialized = true

        -- Force stop everything lingering from a previous session
        if trial_state.is_playing then
            trial_state.is_playing = false
            trial_state._was_playing = false
        end
        if demo_state and demo_state.is_playing then demo_state.is_playing = false end
        if trial_state.is_recording then cancel_recording() end
        trial_state.flip_inputs = false
        trial_state.floating_info = nil
        _G.ComboTrials_HideNativeHUD = false

        restore_trial_vital()
        unique_resources.restore()
    end

end

local function ct_handle_pause_positions(is_game_paused, _in_replay)
    local should_restore_pause_position = (d2d_cfg.forced_position_idx ~= 1) and
        (trial_state.is_playing or (demo_state and demo_state.is_playing))

    if not should_restore_pause_position then
        trial_state._pause_live_r1 = nil
        trial_state._pause_live_r2 = nil
        trial_state._unpause_delay = nil
        trial_state._was_game_paused = is_game_paused
        return
    end

    -- Entering pause → capture live positions
    if is_game_paused and not trial_state._was_game_paused then
        pcall(function()
            local p1 = GS.p1
            local p2 = GS.p2
            if not p1 or not p2 then return end
            trial_state._pause_live_r1 = p1.pos.x.v
            trial_state._pause_live_r2 = p2.pos.x.v
        end)
    end

    -- Leaving pause → inject captured live positions
    if not is_game_paused and trial_state._was_game_paused then
        if trial_state._pause_live_r1 and trial_state._pause_live_r2 then
            trial_state._unpause_delay = 5
        end
    end
    trial_state._was_game_paused = is_game_paused

    -- Delayed inject after unpause (skip in replay)
    if not _in_replay and trial_state._unpause_delay and trial_state._unpause_delay > 0 then
        trial_state._unpause_delay = trial_state._unpause_delay - 1
        if trial_state._unpause_delay == 0 and trial_state._pause_live_r1 and trial_state._pause_live_r2 then
            pcall(function()
                local p1 = GS.p1
                local p2 = GS.p2
                if not p1 or not p2 then return end
                local sfix_type = _td_sfix
                if not sfix_type then return end
                local sfix_from = sfix_type:get_method("From(System.Double)")
                if not sfix_from then return end
                if p1.POS_SETx then p1:POS_SETx(sfix_from:call(nil, trial_state._pause_live_r1 / 65536.0)) end
                if p2.POS_SETx then p2:POS_SETx(sfix_from:call(nil, trial_state._pause_live_r2 / 65536.0)) end
            end)
            trial_state._pause_live_r1 = nil
            trial_state._pause_live_r2 = nil
        end
    end

end

local function ct_handle_playing_transition()
    -- Detect is_playing transitions for trial environment setup
    local now_playing = trial_state.is_playing
    if now_playing and not trial_state._was_playing then
        -- Transition OFF -> ON: clear legacy HP injection state
        apply_trial_vital()
    elseif not now_playing and trial_state._was_playing then
        -- Transition ON -> OFF: restore trial-only settings and reset positions to default
        restore_trial_vital()
        unique_resources.restore()
        restore_trial_defense_settings()
        trial_state._pending_reinject_settings = false
        restore_dummy_action_type()
        set_dummy_counter_type(0)
        set_dummy_guard_type(0)
        trial_state._saved_counter_type = nil
        trial_state._saved_guard_type = nil
        trial_state._saved_dummy_action_type = nil
        reset_positions_to_default()
    end
    trial_state._was_playing = now_playing
end

local function ct_handle_position_correction(_in_replay)
    local hp_restore_checked = false
    if d2d_cfg.forced_position_idx == 1 then
        clear_pending_position_injection()
    end

    -- POST-REFRESH EXACT POSITION CORRECTION (skip in replay)
    if not _in_replay and trial_state.pending_exact_pos and trial_state.pending_exact_pos > 0 then
        local tm_check = sdk.get_managed_singleton("app.training.TrainingManager")
        local refresh_done = tm_check and tm_check:get_field("_IsReqRefresh") == false
        local force_finish = false

        if refresh_done then
            trial_state.pending_exact_pos = trial_state.pending_exact_pos - 1
        else
            trial_state.pending_exact_timeout = (trial_state.pending_exact_timeout or 45) - 1
            if trial_state.pending_exact_timeout <= 0 then
                force_finish = true
                trial_state.pending_exact_pos = 0
                if tm_check then
                    pcall(function()
                        tm_check:set_field("_IsReqRefresh", false)
                    end)
                end
            end
        end

        if trial_state.pending_exact_pos == 0 then
            pcall(apply_exact_position_now)
            trial_state.pending_exact_timeout = nil
        elseif force_finish then
            trial_state.pending_exact_timeout = nil
        end
    end

    if trial_state._pending_reinject_settings and trial_state.is_playing then
        local tm_s = sdk.get_managed_singleton("app.training.TrainingManager")
        if tm_s and tm_s:get_field("_IsReqRefresh") == false then
            trial_state._pending_reinject_settings = false
            apply_trial_training_environment(true)
            apply_pending_hp_restore_once("post_refresh_reinject")
            hp_restore_checked = true
        end
    end

    if trial_state.is_playing and not trial_state._pending_reinject_settings and not hp_restore_checked then
        apply_pending_hp_restore_once("post_refresh_retry")
    end
end

local function ct_handle_hp_injection()
    if trial_state.is_playing and trial_state.current_step == 1 then
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        local is_refreshing = tm and tm:get_field("_IsReqRefresh")
        -- Detect first hit and latch it (check combo_cnt on ATTACKER)
        -- Skip for a few frames after reset (combo_cnt may still be stale)
        if trial_state._reset_grace and trial_state._reset_grace > 0 then
            trial_state._reset_grace = trial_state._reset_grace - 1
        elseif not trial_state._first_hit_landed and not is_refreshing then
            pcall(_ct_check_first_hit)
        end
        if trial_state._first_hit_landed then
            trial_state._hp_inject_frames = 0
        end
    end

end

local function ct_player_init(p_idx, p_state)
    --- Global Trial Timers (Success & Fail animations)
    if p_idx == trial_state.playing_player then
        if trial_state.success_timer > 0 then
            trial_state.success_timer = trial_state.success_timer - 1
            if trial_state.success_timer <= 0 then
                trial_state.success_timer = 0
            end
        end

        if trial_state.fail_timer and trial_state.fail_timer > 0 then
            -- CAPTURE: Take a snapshot on the very first frame of the fail state
            if not trial_state._fail_captured then
                DebugTrace.record_last_fail(
                    trial_state,
                    DebugTrace.build_fail_dump(trial_state, players),
                    "TrainingComboTrials_data/LastFail.json"
                )
                trial_state._fail_captured = true
            end

            trial_state.fail_timer = trial_state.fail_timer - 1
            if trial_state.fail_timer <= 0 then
                trial_state.fail_timer = 0
                trial_state.manual_reset_pending = true
            end
        end
    	end

    if p_state.profile_name ~= p_state.last_profile_name then
        p_state.last_profile_name = p_state.profile_name
        p_state.log = {}
        p_state.input_history_queue = {}
        p_state.action_instance_counter = 0
        p_state.current_action_instance = 0
        p_state.buffer_action_instance = 0
        p_state.bcm_cache = {}
        p_state.trigger_mask_cache = {}
        p_state.cache_built = false
        p_state.last_bcm_ptr = ""

        -- RESET TRIAL on character change
        -- The trial depends on both characters, reset if either changes
        if not trial_state._xt_pending_save then
            if trial_state.is_recording then
                trial_state.is_recording = false
            end
            if trial_state.is_playing then
                trial_state.is_playing = false
            end
            trial_state.sequence = {}
            trial_state.current_step = 1
            trial_state.success_timer = 0
            trial_state.fail_timer = 0
            trial_state.fail_reason = nil
            trial_state._pending_current_absorb = nil
        end

        -- Refresh the list only if it's the character we are currently viewing
        if p_idx == ui_state.viewed_player and not trial_state._xt_pending_save then
            refresh_combo_list()
        end
        if p_state.profile_name ~= "Unknown" then
            p_state.exceptions = CharacterRules.load_for_character(p_state.profile_name)
        end
    end

end

local function ct_player_tracking(p_idx, p_state)
    -- LILY STRICT: Track physical button held on controller
    if p_state.profile_name == "Lily" and #p_state.log > 0 and p_state.log[1].trigger_mask then
        p_state.log[1].is_physically_holding = ((_pf.direct_input & p_state.log[1].trigger_mask) ~= 0)
    end

    -- ========================================================
    -- SIMPLIFIED COMBO COUNTER HANDLING
    -- ========================================================
    -- Update combo count in the log (for display)
    if (_pf.current_combo or 0) > 0 then
        if #p_state.log > 0 then
            p_state.log[1].combo_count = math.max(p_state.log[1].combo_count or 0,
                _pf.current_combo)
        end
        for i = 1, math.min(15, #p_state.log) do
            if p_state.log[i].intentional then
                p_state.log[i].combo_count = math.max(p_state.log[i].combo_count or 0, _pf.current_combo); break
            end
        end
    end

    -- ========================================================
    -- CONTINUOUS GAUGE TRACKING DURING RECORDING
    -- ========================================================
    		-- DELAYED SNAPSHOT: wait for P2 refresh (100% health) to be applied by the engine
    if trial_state.is_recording and p_idx == trial_state.recording_player
    and trial_state._rec_pending_snapshot and trial_state._rec_pending_snapshot > 0 then
    trial_state._rec_pending_snapshot = trial_state._rec_pending_snapshot - 1
    if trial_state._rec_pending_snapshot == 0 then
    trial_state._rec_gauges = snapshot_gauges(p_idx)
    -- At this point vital_new = character's real max_hp, so damage is calculated from 100%
    end
    end
    -- Fetch victim once for all checks below
    _pf.victim_idx = 1 - p_idx
    _pf.victim_obj = (_pf.victim_idx == 0) and GS.p1 or GS.p2

    if trial_state.is_recording and p_idx == trial_state.recording_player and trial_state._rec_gauges then
        pcall(_ct_track_rec_gauges, _pf.victim_obj, _pf.p_char, p_idx)
    end

    -- Hit detection for visual display (has_hit + actual_combo + projectile)
    if (_pf.current_combo or 0) > (p_state.last_combo_count or 0) then
        -- Verify hit source: projectile or direct player hit
        local hit_is_projectile = false
        pcall(function()
            hit_is_projectile = check_is_projectile(p_idx, _pf.p_char, _td_gBattle)
        end)

        if trial_state.is_recording and p_idx == trial_state.recording_player then
            if #trial_state.sequence > 0 then
                local step = trial_state.sequence[#trial_state.sequence]
                -- has_hit is now handled by on_frame delayed combo tracking
                -- Track if there was AT LEAST one projectile hit during the action
                step.is_projectile_hit = step.is_projectile_hit or hit_is_projectile
                -- Capture CH/PC at the moment of the hit
                if step.counter_type == 0 then
                    pcall(function()
                        local victim_obj = _pf.victim_obj
                        if victim_obj then
                            local pc = victim_obj:get_type_definition():get_field("counter_fw_flag"):get_data(victim_obj)
                            local ch = victim_obj:get_type_definition():get_field("counter_dm_flag"):get_data(victim_obj)
                            if pc == true then step.counter_type = 2
                            elseif ch == true then step.counter_type = 1 end
                        end
                    end)
                end
            end
        elseif trial_state.is_playing and p_idx == trial_state.playing_player
            and not (trial_state.fail_timer and trial_state.fail_timer > 0) then
            -- Step 1 tolerance: fail if the wrong hit LANDS on the dummy
            if trial_state._step1_wrong_pending and trial_state.current_step == 1 and not is_trial_action_grace_active() then
                trial_state._step1_wrong_pending = false
                trial_state.fail_timer = d2d_cfg.fail_display_frames or 120
                trial_state.fail_reason = "WRONG MOVE"
            end
            local target_step_idx = math.max(1, trial_state.current_step - 1)
            if trial_state._hit_grace and trial_state._hit_grace > 0 then
                target_step_idx = math.min(#trial_state.sequence, trial_state.current_step)
            end
            local prev_step = trial_state.sequence[target_step_idx]
            if prev_step then
                prev_step.actual_combo = _pf.current_combo
                prev_step.has_hit = true
                if hit_is_projectile then prev_step.is_projectile_hit = true end
                advance_same_action_continuation_steps(_pf.current_combo or 0, "hit_detection")

                -- Hit confirmed: apply the counter_type of the next step
                local next_step = trial_state.sequence[trial_state.current_step]
                if next_step and next_step.counter_type then
                    set_dummy_counter_type(next_step.counter_type)
                else
                    set_dummy_counter_type(0)
                end

                -- Advance ONLY the [ACTION X / Y] counter on impact
                trial_state.ui_visual_step = trial_state.current_step
                trial_state.floating_info = nil -- <-- Clear text while waiting for the next input
            end

        end
    			end

    -- Capture CH/PC continuously during recording (independent of combo count for DI etc.)
    if not trial_state._rec_hit_type and trial_state.is_recording and p_idx == trial_state.recording_player then
        pcall(_ct_capture_rec_hit_type, _pf.victim_obj)
    end

    -- Opponent knockdown detection (pose_st == 3)
    _pf.opponent_knocked_down = false
    local _ok_kd, _kd = pcall(_ct_check_knockdown, _pf.victim_obj)
    if _ok_kd and _kd then _pf.opponent_knocked_down = true end
    -- Guard off as soon as the opponent falls (for okis)
    if trial_state.is_playing and _pf.opponent_knocked_down and not trial_state._guard_off_on_kd then
        set_dummy_guard_type(0)
        trial_state._guard_off_on_kd = true
    elseif trial_state.is_playing and not _pf.opponent_knocked_down and trial_state._guard_off_on_kd then
        trial_state._guard_off_on_kd = false
    end

    -- ========================================================
end

local function ct_player_validation(p_idx, p_state)
    -- SUCCESS VERIFICATION + DROP DETECTION (Trial)
    -- ========================================================
    local is_demo_playing = (demo_state and demo_state.is_playing)
    if trial_state.is_playing and p_idx == trial_state.playing_player and not trial_state.manual_reset_pending then
        ComboTrialsModules.PendingAbsorb.check({
            state = trial_state,
            p_idx = p_idx,
            p_state = p_state,
            frame = engine_frame_count,
            pf = _pf,
            Validator = Validator,
            DebugTrace = DebugTrace,
            is_post_hit_setup_step = is_post_hit_setup_step,
            set_dummy_counter_type = set_dummy_counter_type,
            d2d_cfg = d2d_cfg,
            file_system = file_system,
            act_id_reverse_enum = act_id_reverse_enum
        }, "pending_current_absorb_validation")
    end
    if trial_state.is_playing and p_idx == trial_state.playing_player and not is_demo_playing and not trial_state.manual_reset_pending then
        local is_hold_pending = (trial_state.active_universal_hold ~= nil)

        if #trial_state.sequence > 0 and trial_state.current_step > #trial_state.sequence then
            local last_step = trial_state.sequence[#trial_state.sequence]
            local observed_combo = math.max(_pf.current_combo or 0, p_state.last_combo_count or 0, last_step.actual_combo or 0)
            local should_finish_success = trial_state.success_timer == 0 and not is_hold_pending and not (trial_state.fail_timer and trial_state.fail_timer > 0)
                and (is_pressure_tail_step(last_step) or not last_step.expected_combo or last_step.expected_combo == 0 or observed_combo >= last_step.expected_combo)
            if should_finish_success then
                trial_state.success_timer = d2d_cfg.fail_display_frames or 120
            end
        end

        -- CONTINUOUS COMBO DROP DETECTION:
        if (_pf.current_combo or 0) == 0 and (p_state.last_combo_count or 0) > 0 and not trial_state._pending_hit_cc and not (trial_state._hit_grace and trial_state._hit_grace > 0) then
            if trial_state.success_timer == 0 and not (trial_state.fail_timer and trial_state.fail_timer > 0) then
                local last_validated_idx = trial_state.current_step - 1
                if last_validated_idx >= 1 then
                    local last_validated = trial_state.sequence[last_validated_idx]

                    local current_expected = trial_state.sequence[trial_state.current_step]
                    local is_reset_expected = current_expected and current_expected.expected_combo == 0
                    local current_is_pressure_tail = is_pressure_tail_step(current_expected)

                    if last_validated and last_validated.expected_combo and last_validated.expected_combo > 0 then
                        if is_hold_pending then
                            trial_state.fail_timer = d2d_cfg.fail_display_frames or 120
                            local frames_since = engine_frame_count - (trial_state.last_played_frame or engine_frame_count)
                            if frames_since < 15 then
                                trial_state.fail_reason = "TOO LATE (Combo Drop)"
                            else
                                local diff_str = ""
                                if trial_state.active_universal_hold and trial_state.active_universal_hold.expected_frames then
                                    local diff = trial_state.active_universal_hold.frames - trial_state.active_universal_hold.expected_frames
                                    local sign = diff > 0 and "+" or ""
                                    diff_str = string.format(" [%s%df]", sign, diff)
                                end
                                trial_state.fail_reason = "HOLD TIMING" .. diff_str .. " (Combo Drop)"
                            end
                            trial_state.active_universal_hold = nil
                        elseif not _pf.opponent_knocked_down and not is_reset_expected
                            and not current_is_pressure_tail
                            and not (last_validated.expected_combo == (trial_state.current_step >= 3 and trial_state.sequence[trial_state.current_step - 2].expected_combo or 0)) then
                            ComboTrialsModules.PendingAbsorb.clear(trial_state, "combo_dropped")
                            trial_state.fail_timer = d2d_cfg.fail_display_frames or 120
                            local combo_drop_reason = nil
                            if last_validated.last_frame_diff and last_validated.last_frame_diff < -2 then
                                trial_state.fail_reason = string.format("TOO EARLY (%df)", math.abs(last_validated.last_frame_diff))
                                combo_drop_reason = "last_step_too_early"
                            elseif last_validated.last_frame_diff and last_validated.last_frame_diff > 2 then
                                trial_state.fail_reason = string.format("TOO LATE (%df)", last_validated.last_frame_diff)
                                combo_drop_reason = "last_step_too_late"
                            else
                                local expected = trial_state.sequence[trial_state.current_step]
                                if expected then
                                    local last_played = trial_state.last_played_frame or engine_frame_count
                                    local diff = (engine_frame_count - last_played) - (expected.delay_from_prev or 0)
                                    if diff > 2 then
                                        trial_state.fail_reason = string.format("TOO LATE (%df)", diff)
                                        combo_drop_reason = "expected_step_too_late"
                                    else
                                        trial_state.fail_reason = "COMBO DROPPED"
                                        combo_drop_reason = "combo_dropped_before_expected"
                                    end
                                else
                                    trial_state.fail_reason = "COMBO DROPPED"
                                    combo_drop_reason = "combo_dropped_after_final_step"
                                end
                            end
                            if trial_state.current_step > #trial_state.sequence then
                                DebugTrace.record_match_probe(trial_state, build_final_finish_debug({
                                    combo_drop_detected = true,
                                    combo_drop_reason = combo_drop_reason
                                }))
                            end
                        end
                    end
                end
            end
        end

        -- TIMEOUT CONTINUOUS DETECTION (Triggers if player does nothing or gets hit)
        if trial_state.success_timer == 0 and not is_hold_pending and not (trial_state.fail_timer and trial_state.fail_timer > 0) then
            local expected = trial_state.sequence[trial_state.current_step]
            if expected and trial_state.current_step > 1 then
                local last_played = trial_state.last_played_frame or engine_frame_count
                local frames_since = engine_frame_count - last_played
                local delay = expected.delay_from_prev or 0

                -- 60 frames (~1 sec) tolerance after the ideal timing
                if frames_since > (delay + 60) then
                    local prev_step = trial_state.current_step > 1 and trial_state.sequence[trial_state.current_step - 1] or nil
                    if is_pressure_tail_step(expected) then
                        DebugTrace.record_match_probe(trial_state, {
                            phase = "pressure_tail_timeout_skip",
                            frame = engine_frame_count,
                            trial_file = trial_state.current_file or trial_state.current_file_path,
                            trial_filename = trial_state.current_file_name,
                            character = p_state.profile_name,
                            step = trial_state.current_step,
                            trial_total = trial_state.sequence and #trial_state.sequence or 0,
                            expected_id = expected.id,
                            expected_motion = expected.motion,
                            expected_combo = expected.expected_combo,
                            expected_delay = delay,
                            previous_verified_step = trial_state.current_step - 1,
                            previous_id = prev_step and prev_step.id or nil,
                            previous_motion = prev_step and prev_step.motion or nil,
                            previous_expected_combo = prev_step and prev_step.expected_combo or nil,
                            current_combo = _pf.current_combo or 0,
                            combo_count = _pf.current_combo or 0,
                            actual_hp = _pf.p_char.vital_new,
                            frames_since_prev_step = frames_since,
                            frame_diff = frames_since - delay,
                            validation_role = expected.validation_role,
                            allow_whiff = expected.allow_whiff,
                            reject_reason = "pressure_tail_timeout_skipped"
                        })
                        local raw_timeout_frame_diff = frames_since - delay
                        expected.last_frame_diff = raw_timeout_frame_diff
                        ComboTrialsModules.PendingAbsorb.set_timing_ui_result(trial_state, trial_state.current_step, expected.last_frame_diff)
                        expected.actual_combo = _pf.current_combo or 0
                        trial_state.last_played_frame = engine_frame_count
                        trial_state.current_step = trial_state.current_step + 1
                        local next_step = trial_state.sequence[trial_state.current_step]
                        if next_step and next_step.counter_type then
                            set_dummy_counter_type(next_step.counter_type)
                        end
                    else
                    ComboTrialsModules.PendingAbsorb.clear(trial_state, "timeout")
                    trial_state.fail_timer = d2d_cfg.fail_display_frames or 120
                    local current_is_setup = is_post_hit_setup_step(trial_state.current_step)
                    local prev_is_setup = is_post_hit_setup_step(trial_state.current_step - 1)

                    if expected.expected_hp ~= nil and _pf.p_char.vital_new ~= expected.expected_hp then
                        if current_is_setup then
                            trial_state.fail_reason = "SETUP INTERRUPTED (Got hit)"
                        else
                            if prev_is_setup then
                                trial_state.fail_reason = "MEATY INTERRUPTED (Got hit)"
                            else
                                trial_state.fail_reason = "INTERRUPTED (Got hit)"
                            end
                        end
                    else
                        if prev_is_setup then
                            trial_state.fail_reason = "MEATY TOO LATE (Missed Input)"
                        else
                            trial_state.fail_reason = "TOO LATE (Missed Input)"
                        end
                    end
                    DebugTrace.record_match_probe(trial_state, {
                        phase = "timeout_validation",
                        frame = engine_frame_count,
                        trial_file = trial_state.current_file or trial_state.current_file_path,
                        trial_filename = trial_state.current_file_name,
                        character = p_state.profile_name,
                        step = trial_state.current_step,
                        trial_total = trial_state.sequence and #trial_state.sequence or 0,
                        expected_id = expected.id,
                        expected_motion = expected.motion,
                        expected_combo = expected.expected_combo,
                        expected_delay = delay,
                        previous_verified_step = trial_state.current_step - 1,
                        previous_id = prev_step and prev_step.id or nil,
                        previous_motion = prev_step and prev_step.motion or nil,
                        previous_expected_combo = prev_step and prev_step.expected_combo or nil,
                        previous_has_hit = prev_step and prev_step.has_hit or nil,
                        previous_last_frame_diff = prev_step and prev_step.last_frame_diff or nil,
                        current_combo = _pf.current_combo or 0,
                        combo_count = _pf.current_combo or 0,
                        actual_hp = _pf.p_char.vital_new,
                        frames_since_prev_step = frames_since,
                        frame_diff = frames_since - delay,
                        hitstop = _pf.hitstop,
                        blockstop = _pf.blockstop,
                        opponent_knocked_down = _pf.opponent_knocked_down,
                        reject_reason = "timeout"
                    })
                    DebugTrace.log_trial_failure(file_system, trial_state, engine_frame_count, _pf, "timeout_validation", {
                        expected_motion = expected.motion,
                        playback_state = "playing"
                    })
                    end
                end
            end
        end
    		end
end

local function ct_player_hold_charge(p_state)
    -- CONTINUOUS CHARGE HANDLING
    if #p_state.log > 0 then
        local current_log = p_state.log[1]
        if current_log.is_holdable and current_log.is_holding then
            if current_log.hold_mask > 0 and (_pf.direct_input & current_log.hold_mask) ~= 0 then
                current_log.hold_frames = current_log.hold_frames + 1
            else
                -- PLAYER RELEASED THE BUTTON
                current_log.is_holding = false

                -- Auto-detect max frame for JP/Lily if not configured
                if (p_state.profile_name == "JP" or p_state.profile_name == "Lily") and (current_log.charge_max == nil or current_log.charge_max == "") then
                    current_log.charge_max = current_log.hold_frames
                    local id_s = tostring(current_log.id)
                    local exc_to_update = CharacterRules.get_exception(p_state.exceptions, common_exceptions, id_s)
                    if exc_to_update then
                        exc_to_update.charge_max = current_log.hold_frames
                        if CharacterRules.has_character_exception(p_state.exceptions, id_s) then json.dump_file(get_exc_filename(p_state.profile_name), p_state.exceptions)
                        else json.dump_file("TrainingComboTrials_data/exceptions/Common.json", common_exceptions) end
                    end
                end
            end

            current_log.charge_status = evaluate_charge_status(
                p_state.profile_name, current_log.hold_frames,
                current_log.charge_min, current_log.charge_max,
                current_log.luke_perfect_min, current_log.luke_perfect_max
            )

            -- REAL-TIME HOLD SYNCHRONIZATION FOR THE TRIAL
            if trial_state.is_recording and current_log.trial_step_idx and trial_state.sequence[current_log.trial_step_idx] then
                trial_state.sequence[current_log.trial_step_idx].hold_frames = current_log.hold_frames
                trial_state.sequence[current_log.trial_step_idx].charge_status = current_log.charge_status
                trial_state.sequence[current_log.trial_step_idx].charge_max = current_log.charge_max
            end
        end
    end			
end

_G.CTSameActionTrace = _G.CTSameActionTrace or {}
_G.CTSameActionTrace.path = "TrainingComboTrials_data/SameActionTrace.json"
_G.CTSameActionTrace.max_events = 500

function _G.CTSameActionTrace.enabled()
    local same_flag = rawget(_G, "CT_SAME_ACTION_TRACE")
    if same_flag ~= nil then return same_flag == true end
    return rawget(_G, "CT_VERIFY_TRACE") == true
end

function _G.CTSameActionTrace.target()
    local name = tostring(trial_state.current_file_name or trial_state.current_file or trial_state.current_file_path or "")
    return name:find("Mai_OKI_DI_2858_D1_6_SA0", 1, true) ~= nil
        or name:find("Mai_OKI_DI_3158_D1_6_SA1", 1, true) ~= nil
end

function _G.CTSameActionTrace.build_base(phase, p_state)
    if not (_G.CTSameActionTrace.enabled() and _G.CTSameActionTrace.target()) then return nil end
    if not trial_state.is_playing then return nil end
    if p_state and p_state ~= players[trial_state.playing_player] then return nil end

    local expected = trial_state.sequence and trial_state.sequence[trial_state.current_step] or nil
    local prev_step = trial_state.current_step and trial_state.current_step > 1
        and trial_state.sequence[trial_state.current_step - 1] or nil
    local last_played = trial_state.last_played_frame or engine_frame_count
    local expected_delay = expected and expected.delay_from_prev or nil
    local frames_since_prev_step = trial_state.current_step and trial_state.current_step > 1
        and (engine_frame_count - last_played) or 0

    return {
        phase = phase,
        trial_name = trial_state.current_file_name,
        trial_file = trial_state.current_file or trial_state.current_file_path,
        frame = engine_frame_count,
        current_step = trial_state.current_step,
        expected_id = expected and expected.id or nil,
        expected_motion = expected and expected.motion or nil,
        previous_verified_step = trial_state.current_step and trial_state.current_step - 1 or nil,
        previous_expected_id = prev_step and prev_step.id or nil,
        previous_expected_motion = prev_step and prev_step.motion or nil,
        same_as_previous_expected = expected and prev_step and expected.id == prev_step.id or false,
        same_as_current_expected = expected and _pf and _pf.act_id == expected.id or false,
        frames_since_prev_step = frames_since_prev_step,
        expected_delay = expected_delay,
        frame_diff = expected_delay and (frames_since_prev_step - expected_delay) or nil
    }
end

function _G.CTSameActionTrace.record(event)
    if type(event) ~= "table" then return end
    trial_state._same_action_trace = trial_state._same_action_trace or {
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
        note = "Temporary trace for consecutive same-action validation. Enable with _G.CT_SAME_ACTION_TRACE=true.",
        path = _G.CTSameActionTrace.path,
        events = {}
    }

    local dump = trial_state._same_action_trace
    dump.updated_at = os.date("%Y-%m-%d %H:%M:%S")
    dump.enabled = true
    table.insert(dump.events, event)
    while #dump.events > _G.CTSameActionTrace.max_events do
        table.remove(dump.events, 1)
    end
    if rawget(_G, "CT_SAME_ACTION_TRACE_FILE") == true then
        pcall(function()
            DebugTrace.write_json(_G.CTSameActionTrace.path, dump)
        end)
    end
end

function _G.CTSameActionTrace.trace(phase, p_state, fields)
    local event = _G.CTSameActionTrace.build_base(phase, p_state)
    if not event then return end
    if type(fields) == "table" then
        for k, v in pairs(fields) do
            event[k] = v
        end
    end
    _G.CTSameActionTrace.record(event)
end

_G.CTSameDashFallback = _G.CTSameDashFallback or {}

function _G.CTSameDashFallback.edge_type_for_step(step)
    if type(step) ~= "table" then return nil end
    local motion = ActionMatcher.normalize_motion_token(step.motion)
    if tonumber(step.id) == 17 and motion == "66" then return "66" end
    if tonumber(step.id) == 18 and motion == "44" then return "44" end
    if type(step.motion_aliases) == "table" then
        for _, alias in ipairs(step.motion_aliases) do
            local normalized = ActionMatcher.normalize_motion_token(alias)
            if tonumber(step.id) == 17 and normalized == "66" then return "66" end
            if tonumber(step.id) == 18 and normalized == "44" then return "44" end
        end
    end
    return nil
end

function _G.CTSameDashFallback.build_candidate(p_state, detected_66_edge, detected_44_edge)
    if not (trial_state.is_playing and p_state == players[trial_state.playing_player]) then return nil end
    if trial_state.manual_reset_pending or (trial_state.success_timer and trial_state.success_timer > 0) then return nil end
    if trial_state.fail_timer and trial_state.fail_timer > 0 then return nil end
    if not trial_state.sequence or not trial_state.current_step or trial_state.current_step <= 1 then return nil end

    local expected = trial_state.sequence[trial_state.current_step]
    local prev_step = trial_state.sequence[trial_state.current_step - 1]
    if not expected or not prev_step or expected.id ~= prev_step.id then return nil end

    local edge_type = _G.CTSameDashFallback.edge_type_for_step(expected)
    if not edge_type then return nil end
    if _G.CTSameDashFallback.edge_type_for_step(prev_step) ~= edge_type then return nil end
    if edge_type == "66" and not detected_66_edge then return nil end
    if edge_type == "44" and not detected_44_edge then return nil end

    local consume_key = tostring(trial_state.current_step) .. ":" .. tostring(trial_state.last_played_frame or 0)
    if p_state._same_dash_fallback_key == consume_key then
        _G.CTSameActionTrace.trace("same_dash_fallback_rejected", p_state, {
            fallback_source = "input_same_dash_edge",
            edge_type = edge_type,
            accepted = false,
            reject_reason = "already_consumed"
        })
        return nil
    end

    local last_played = trial_state.last_played_frame or engine_frame_count
    local frames_since_prev_step = engine_frame_count - last_played
    local expected_delay = expected.delay_from_prev or 0
    local frame_diff = Validator.calculate_frame_diff(frames_since_prev_step, expected_delay)
    local early_window = 4
    local late_window = 2
    local accepted = frame_diff >= -early_window and frame_diff <= late_window
    local trace_fields = {
        step_index = trial_state.current_step,
        expected_id = expected.id,
        expected_motion = expected.motion,
        previous_step_id = prev_step.id,
        fallback_source = "input_same_dash_edge",
        edge_type = edge_type,
        frames_since_prev_step = frames_since_prev_step,
        expected_delay = expected_delay,
        frame_diff = frame_diff,
        early_window = early_window,
        late_window = late_window,
        accepted = accepted,
        reject_reason = accepted and nil or "timing_window"
    }
    p_state._same_dash_fallback_last_eval = trace_fields
    _G.CTSameActionTrace.trace("same_dash_fallback_evaluate", p_state, trace_fields)

    if not accepted then return nil end

    p_state._same_dash_fallback_key = consume_key
    local p1, p2, r1, r2 = capture_current_positions()
    return {
        id = expected.id,
        flags = 0,
        action_code = _pf.action_code or 0,
        direct_input = _pf.direct_input or 0,
        b_type = _pf.b_type or 0,
        engine_frame = engine_frame_count,
        action_instance = p_state.current_action_instance,
        buffer_hold_frames = 0,
        p1 = p1, p2 = p2,
        r1 = r1, r2 = r2,
        current_hp = _pf.p_char and _pf.p_char.vital_new or nil,
        synthetic = true,
        source = "input_same_dash_edge",
        fallback_source = "input_same_dash_edge",
        edge_type = edge_type,
        frames_since_prev_step = frames_since_prev_step,
        expected_delay = expected_delay,
        frame_diff = frame_diff
    }
end

local function ct_player_input_buffer(p_state)
    if trial_state.is_playing and p_state == players[trial_state.playing_player]
        and trial_state._action_grace and trial_state._action_grace > 0 then
        local hold_grace = should_hold_trial_action_grace()
        trial_state._action_grace = trial_state._action_grace - 1
        if hold_grace then
            reset_player_action_buffers(p_state)
            return {}
        end
        trial_state._action_grace = 0
        trial_state._action_grace_min = 0
        reset_player_action_buffers(p_state)
        return {}
    end

    local newly_pressed = (_pf.direct_input ~ p_state.last_direct_input) & _pf.direct_input
    local current_dir_val = _pf.direct_input & 0xF
    local current_dir = DIR_MAP[current_dir_val] or "5"
    if current_dir == "5" then current_dir = "" end
    local newly_pressed_dir = newly_pressed & 0xF
    local detected_66_edge = current_dir == "6" and newly_pressed_dir ~= 0
    local detected_44_edge = current_dir == "4" and newly_pressed_dir ~= 0

    if newly_pressed > 0 then
        table.insert(p_state.input_history_queue,
            { frame_tick = engine_frame_count, mask = newly_pressed, dir = current_dir })
    end
    p_state.last_direct_input = _pf.direct_input

    while #p_state.input_history_queue > 0 and (engine_frame_count - p_state.input_history_queue[1].frame_tick) > 60 do
        table.remove(p_state.input_history_queue, 1)
    end

    if _G.CTSameActionTrace.enabled() and _G.CTSameActionTrace.target()
        and trial_state.is_playing and p_state == players[trial_state.playing_player] then
        if p_state._same_action_trace_step ~= trial_state.current_step then
            p_state._same_action_trace_step = trial_state.current_step
            p_state._same_action_trace_summary = {
                saw_66_edge = false,
                saw_44_edge = false,
                saw_act17 = false,
                act17_min_frame = nil,
                act17_max_frame = nil,
                act17_rewound = false,
                previous_act17_frame = nil
            }
        end

        local same_trace_summary = p_state._same_action_trace_summary
        if same_trace_summary then
            if detected_66_edge then same_trace_summary.saw_66_edge = true end
            if detected_44_edge then same_trace_summary.saw_44_edge = true end
            if _pf.act_id == 17 then
                same_trace_summary.saw_act17 = true
                local act_frame = tonumber(_pf.act_frame) or 0
                if same_trace_summary.act17_min_frame == nil or act_frame < same_trace_summary.act17_min_frame then
                    same_trace_summary.act17_min_frame = act_frame
                end
                if same_trace_summary.act17_max_frame == nil or act_frame > same_trace_summary.act17_max_frame then
                    same_trace_summary.act17_max_frame = act_frame
                end
                if same_trace_summary.previous_act17_frame and act_frame < same_trace_summary.previous_act17_frame then
                    same_trace_summary.act17_rewound = true
                end
                same_trace_summary.previous_act17_frame = act_frame
            end
        end

        _G.CTSameActionTrace.trace("input_sample", p_state, {
            direct_input = _pf.direct_input,
            direction_input = current_dir,
            direction_bits = current_dir_val,
            newly_pressed = newly_pressed,
            newly_pressed_dir = newly_pressed_dir,
            current_input_bits = _pf.direct_input,
            detected_66_edge = detected_66_edge,
            detected_44_edge = detected_44_edge,
            input_history_size = #p_state.input_history_queue,
            current_act_id = _pf.act_id,
            current_act_frame = _pf.act_frame
        })
    end

    -- ANTI-GHOSTING DEBOUNCE LOGIC
    local ghost_wait = ctx.d2d_cfg.ghost_filter_frames or 4

    p_state.buffer_act_id = p_state.buffer_act_id or -1
    p_state.buffer_act_frame = p_state.buffer_act_frame or -1
    p_state.buffer_start_frame = p_state.buffer_start_frame or -1
    p_state.buffer_flags = p_state.buffer_flags or 0
    p_state.buffer_action_code = p_state.buffer_action_code or 0
    p_state.buffer_direct_input = p_state.buffer_direct_input or 0
    p_state.buffer_b_type = p_state.buffer_b_type or 0
    p_state.buffer_hold_frames = p_state.buffer_hold_frames or 0
    p_state.action_instance_counter = p_state.action_instance_counter or 0
    p_state.current_action_instance = p_state.current_action_instance or p_state.action_instance_counter
    p_state.buffer_action_instance = p_state.buffer_action_instance or p_state.current_action_instance
    if p_state.buffer_is_committed == nil then p_state.buffer_is_committed = true end

    local actions_to_process = {}
    if p_state._same_dash_fallback_eval_step ~= trial_state.current_step then
        p_state._same_dash_fallback_eval_step = trial_state.current_step
        p_state._same_dash_fallback_last_eval = nil
    end
    local same_dash_candidate = _G.CTSameDashFallback.build_candidate(p_state, detected_66_edge, detected_44_edge)
    if same_dash_candidate then
        table.insert(actions_to_process, same_dash_candidate)
        _G.CTSameActionTrace.trace("action_candidate_pushed", p_state, {
            push_reason = "input_same_dash_edge",
            pushed_action_id = same_dash_candidate.id,
            pushed_engine_frame = same_dash_candidate.engine_frame,
            pushed_to_actions_to_process = true,
            fallback_source = same_dash_candidate.fallback_source,
            edge_type = same_dash_candidate.edge_type,
            frames_since_prev_step = same_dash_candidate.frames_since_prev_step,
            expected_delay = same_dash_candidate.expected_delay,
            frame_diff = same_dash_candidate.frame_diff,
            synthetic = true
        })
    end
    local started_new_action = false
    local started_new_action_reason = "no_new_action"
    if _pf.act_id ~= p_state.buffer_act_id then
        started_new_action = true
        started_new_action_reason = "id_changed"
    elseif _pf.act_frame < p_state.buffer_act_frame and _pf.act_frame < 2 then
        started_new_action = true
        started_new_action_reason = "act_frame_rewind"
    end
    _G.CTSameActionTrace.trace("action_sample", p_state, {
        current_action_id = _pf.act_id,
        current_action_frame = _pf.act_frame,
        buffer_act_id = p_state.buffer_act_id,
        buffer_act_frame = p_state.buffer_act_frame,
        last_act_id = p_state.prev_act_id,
        last_act_frame = p_state.prev_act_frame,
        started_new_action = started_new_action,
        started_new_action_reason = started_new_action_reason,
        skipped_due_to_duplicate = not started_new_action and _pf.act_id == p_state.buffer_act_id,
        skipped_due_to_same_action = not started_new_action and _pf.act_id == p_state.buffer_act_id,
        action_instance = p_state.buffer_action_instance,
        candidate_window_open = p_state.buffer_is_committed == false,
        pushed_to_actions_to_process = false
    })
    p_state.buffer_act_frame = _pf.act_frame

    if started_new_action then
        if p_state.buffer_act_id ~= -1 and not p_state.buffer_is_committed then
            local duration = engine_frame_count - p_state.buffer_start_frame
            local is_ghost = false

            -- Bypass ghost filtering for Alex's action 976
            local is_alex_exempt = (p_state.profile_name == "Alex" and p_state.buffer_act_id == 976)

            if duration > 0 and duration < ghost_wait and p_state.buffer_act_id > 50 and not is_alex_exempt then
                -- EXACT EVALUATION OF THE NEW ACTION
                -- We must know if the game triggered it automatically or if the player pressed a button
                local new_is_intentional = false
                if _pf.flags == 0 then
                    new_is_intentional = true
                elseif _pf.flags == 16 then
                    if _pf.action_code > 0 and _pf.b_type ~= 0 then
                        new_is_intentional = true
                    elseif _pf.b_type == 536870932 and (_pf.direct_input & 0xFFFF) > 0 then
                        new_is_intentional = true
                    end
                end
                if _pf.act_id == 36 or _pf.act_id == 37 or _pf.act_id == 38 then new_is_intentional = true end

                local exc_new = CharacterRules.get_exception(p_state.exceptions, common_exceptions, _pf.act_id)
                if ActionMatcher.is_force_enabled(exc_new) then new_is_intentional = true end

                -- If the NEW action is truly intentional (e.g. player hit P, then PP 2 frames later),
                -- THEN the buffered action is a ghost.
                -- But if the NEW action is automatic (e.g. Kimberly auto-sprint after EX move),
                -- the buffered action IS NOT a ghost, it is valid and must be committed.
                if new_is_intentional then
                    is_ghost = true
                end
            end

            if is_ghost then
                local g_name = act_id_reverse_enum[p_state.buffer_act_id] or "Unknown"
                table.insert(p_state.log, 1, {
                    id = p_state.buffer_act_id,
                    name = g_name,
                    motion = p_state.bcm_cache[p_state.buffer_act_id] or g_name,
                    real_input = "Ghost",
                    frame_diff = "0f",
                    intentional = false,
                    is_holdable = false,
                    is_ignored = true,
                    ignore_reason = "[Ghost Input: " .. tostring(duration) .. "f]",
                    facing_left = false,
                    action_instance = p_state.buffer_action_instance,
                    start_frame = p_state.buffer_start_frame
                })
                if #p_state.log > 100 then table.remove(p_state.log) end
            else
                -- Not a ghost (survived or interrupted by system). Force commit it immediately!
                table.insert(actions_to_process, {
                    id = p_state.buffer_act_id,
                    flags = p_state.buffer_flags,
                    action_code = p_state.buffer_action_code,
                    direct_input = p_state.buffer_direct_input,
                    b_type = p_state.buffer_b_type,
                    engine_frame = p_state.buffer_start_frame,
                    action_instance = p_state.buffer_action_instance,
                    buffer_hold_frames = p_state.buffer_hold_frames,
                    p1 = p_state.buffer_p1, p2 = p_state.buffer_p2,
                    r1 = p_state.buffer_r1, r2 = p_state.buffer_r2,
                    current_hp = p_state.buffer_current_hp
                })
                _G.CTSameActionTrace.trace("action_candidate_pushed", p_state, {
                    push_reason = "started_new_action_commit_previous",
                    current_action_id = _pf.act_id,
                    current_action_frame = _pf.act_frame,
                    pushed_action_id = p_state.buffer_act_id,
                    pushed_engine_frame = p_state.buffer_start_frame,
                    pushed_action_instance = p_state.buffer_action_instance,
                    pushed_to_actions_to_process = true,
                    started_new_action = started_new_action,
                    started_new_action_reason = started_new_action_reason
                })
            end
        end
        p_state.action_instance_counter = (p_state.action_instance_counter or 0) + 1
        p_state.current_action_instance = p_state.action_instance_counter
        p_state.buffer_act_id = _pf.act_id
        p_state.buffer_start_frame = engine_frame_count
        p_state.buffer_action_instance = p_state.current_action_instance
        p_state.buffer_is_committed = false
        p_state.buffer_flags = _pf.flags
        p_state.buffer_action_code = _pf.action_code
        p_state.buffer_direct_input = _pf.direct_input
        p_state.buffer_b_type = _pf.b_type
        p_state.buffer_hold_frames = 0
        p_state.buffer_current_hp = _pf.p_char.vital_new
        -- Immediate position snapshot at the exact frame of the input
        local _p1, _p2, _r1, _r2 = capture_current_positions()
        p_state.buffer_p1 = _p1; p_state.buffer_p2 = _p2
        p_state.buffer_r1 = _r1; p_state.buffer_r2 = _r2
    end

    -- REAL-TIME HOLD TRACKING DURING BUFFER
    if not p_state.buffer_is_committed and p_state.buffer_act_id ~= -1 then
        local buf_btn = p_state.buffer_direct_input & 0xFFF0
        if buf_btn > 0 and (_pf.direct_input & buf_btn) ~= 0 then
            p_state.buffer_hold_frames = p_state.buffer_hold_frames + 1
        end
    end

    if not p_state.buffer_is_committed and (engine_frame_count - p_state.buffer_start_frame) >= ghost_wait then
        p_state.buffer_is_committed = true
        table.insert(actions_to_process, {
            id = p_state.buffer_act_id,
            flags = p_state.buffer_flags,
            action_code = p_state.buffer_action_code,
            direct_input = p_state.buffer_direct_input,
            b_type = p_state.buffer_b_type,
            engine_frame = p_state.buffer_start_frame,
            action_instance = p_state.buffer_action_instance,
            buffer_hold_frames = p_state.buffer_hold_frames,
            p1 = p_state.buffer_p1, p2 = p_state.buffer_p2,
            r1 = p_state.buffer_r1, r2 = p_state.buffer_r2,
            current_hp = p_state.buffer_current_hp
        })
        _G.CTSameActionTrace.trace("action_candidate_pushed", p_state, {
            push_reason = "ghost_wait_elapsed",
            pushed_action_id = p_state.buffer_act_id,
            pushed_engine_frame = p_state.buffer_start_frame,
            pushed_action_instance = p_state.buffer_action_instance,
            pushed_to_actions_to_process = true,
            started_new_action = started_new_action,
            started_new_action_reason = started_new_action_reason
        })
    end
    return actions_to_process
end

local function ct_player_process_actions(p_idx, p_state, actions_to_process)
    for _, process_act in ipairs(actions_to_process) do
        local act_id = process_act.id
        local flags = process_act.flags
        local action_code = process_act.action_code
        local direct_input = process_act.direct_input
        local b_type = process_act.b_type
        local engine_frame_count = process_act.engine_frame
        local act_name = act_id_reverse_enum[act_id] or "Unknown"

        -- 1. EARLY EXCEPTION RESOLUTION (For Hold Link)
        local exc = CharacterRules.get_exception(p_state.exceptions, common_exceptions, act_id)

        if p_state.editing_id == act_id then
            exc = ActionMatcher.build_edit_exception(p_state)
        end

        exc = CharacterRules.apply_runtime_overrides(p_state.profile_name, act_id, exc, p_state.log)

        -- ABSORPTION CHECK (Does the active parent action want to absorb this new ID?)
        local is_continuation = false
        if #p_state.log > 0 then
            local parent_id = p_state.log[1].id
            local parent_exc = CharacterRules.get_exception(p_state.exceptions, common_exceptions, parent_id)

            -- Real-time update if we are editing the parent action
            if p_state.editing_id == parent_id then
                parent_exc = { absorb_ids = p_state.edit_absorb_ids }
            end

            is_continuation = ActionMatcher.matches_absorb_id(parent_exc, act_id)
        end

        -- 2. CLOSING THE PREVIOUS ACTION
        if #p_state.log > 0 then
            local last_log = p_state.log[1]

            if not is_continuation then
                last_log.is_finished = true
                last_log.transition_id = act_id

                -- Safety stop if the action is abruptly interrupted
                if last_log.is_holdable and last_log.is_holding then
                    last_log.is_holding = false
                end
            else
                -- CONTINUATION: Keep the log active
                p_state.prev_act_id = act_id
            end
        end

        if not is_continuation then
        local is_trackable = false
            local is_ignored = false
            local ignore_reason = ""

            -- SAFETY: Global variable declarations to avoid "nil" values in the log
            local motion_str = act_name
            local real_input_str = "None"
            local frame_diff_str = "0f"
            local is_holdable = false
            local is_holding = false
            local hold_frames = 0
            local hold_mask = 0
            local charge_min = nil
            local charge_max = nil
            local charge_status = "Charging"
            local luke_perfect_min = nil
            local luke_perfect_max = nil
            local dual_threshold = false
            local trial_step_idx = nil
            local is_intentional = false
            local deep_data = nil
            local best_match = nil
            local is_facing_left = false

            if act_id > 50 or act_id == 17 or act_id == 18 or act_id == 36 or act_id == 37 or act_id == 38 then
                is_trackable = true
                _pf.ct_block_guard = string.find(act_name, "GRD_") ~= nil
                if trial_state.is_playing then
                    _pf.ct_block_defender_idx = 1 - (tonumber(trial_state.playing_player or 0) or 0)
                    _pf.ct_block_damage_type = nil
                    _pf.ct_block_defender_obj = (_pf.ct_block_defender_idx == 0) and GS.p1 or GS.p2
                    if _pf.ct_block_defender_obj then
                        _pf.ct_block_damage_type = _pf.ct_block_defender_obj:get_field("damage_type")
                        if _pf.ct_block_damage_type ~= nil then
                            _pf.ct_block_damage_type = tonumber(tostring(_pf.ct_block_damage_type)) or 0
                        end
                    end
                    _pf.ct_block_defender_act_st = (_pf.ct_block_defender_idx == 0) and GS.p1_act_st or GS.p2_act_st
                    _pf.ct_block_source = _pf.ct_block_guard and "GRD_action" or nil
                    if _pf.ct_block_damage_type == 30 then
                        _pf.ct_block_source = _pf.ct_block_source and (_pf.ct_block_source .. "+damage_type_30") or "damage_type_30"
                    end
                    if _pf.ct_block_source then
                        trial_state._recent_block_contact_frame = engine_frame_count
                        trial_state._recent_block_contact_actor = p_idx
                        trial_state._recent_block_contact_source = _pf.ct_block_source
                        trial_state._recent_block_damage_type = _pf.ct_block_damage_type
                        trial_state._recent_block_defender_frame_type = nil
                        trial_state._recent_block_defender_main_gauge = nil
                        trial_state._recent_block_defender_act_st = _pf.ct_block_defender_act_st
                        trial_state._recent_block_action_id = act_id
                        trial_state._recent_block_action_name = act_name
                        _pf.ct_pending_block = trial_state._pending_block_outcome
                        _pf.ct_block_delta = nil
                        _pf.ct_block_outcome_ok = false
                        if _pf.ct_pending_block
                            and _pf.ct_pending_block.step == trial_state.current_step
                            and _pf.ct_pending_block.expected_id == (trial_state.sequence[trial_state.current_step]
                                and trial_state.sequence[trial_state.current_step].id or nil) then
                            _pf.ct_block_delta = engine_frame_count - (_pf.ct_pending_block.action_frame or engine_frame_count)
                            if _pf.ct_block_delta >= 0 and _pf.ct_block_delta <= (_pf.ct_pending_block.window or 15) then
                                _pf.ct_block_outcome_ok = true
                                _pf.ct_pending_block.outcome_ok = true
                                _pf.ct_pending_block.block_contact_seen = true
                                _pf.ct_pending_block.block_contact_frame = engine_frame_count
                                _pf.ct_pending_block.block_contact_delta = _pf.ct_block_delta
                                _pf.ct_pending_block.block_contact_source = _pf.ct_block_source
                                _pf.ct_pending_block.block_contact_damage_type = _pf.ct_block_damage_type
                                _pf.ct_pending_block.block_contact_action_id = act_id
                                _pf.ct_pending_block.block_contact_action_name = act_name
                                _pf.ct_pending_block.block_contact_defender_frame_type = nil
                                _pf.ct_pending_block.block_contact_defender_main_gauge = nil
                                _pf.ct_pending_block.block_contact_defender_act_st = _pf.ct_block_defender_act_st
                            end
                        end
                        DebugTrace.record_match_probe(trial_state, {
                            phase = "block_contact_sample",
                            branch = "block_contact_sample",
                            frame = engine_frame_count,
                            trial_file = trial_state.current_file or trial_state.current_file_path,
                            trial_filename = trial_state.current_file_name,
                            character = p_state.profile_name,
                            actor = p_idx,
                            defender_idx = _pf.ct_block_defender_idx,
                            actual_action_id = act_id,
                            actual_action_name = act_name,
                            source = _pf.ct_block_source,
                            defender_damage_type = _pf.ct_block_damage_type,
                            defender_frame_type = nil,
                            defender_main_gauge = nil,
                            defender_act_st = _pf.ct_block_defender_act_st,
                            hit_result = _pf.ct_pending_block and _pf.ct_pending_block.hit_result or nil,
                            outcome_pending = _pf.ct_pending_block ~= nil,
                            outcome_ok = _pf.ct_block_outcome_ok,
                            block_contact_seen = true,
                            block_contact_frame = engine_frame_count,
                            block_contact_delta = _pf.ct_block_delta,
                            block_contact_source = _pf.ct_block_source,
                            block_contact_damage_type = _pf.ct_block_damage_type,
                            step = trial_state.current_step,
                            trial_total = trial_state.sequence and #trial_state.sequence or 0
                        })
                    end
                end
                if string.find(act_name, "DMG_") or _pf.ct_block_guard or string.find(act_name, "DOWN") or string.find(act_name, "PIYO") then
                    is_ignored = true
                    ignore_reason = "[System: Guard/Down/Stun]"
                end
                if not is_ignored and get_damage_type_safe(_pf.p_char) ~= 0 then
                    is_ignored = true
                    ignore_reason = "[System: Taking Damage]"
                end
            end

            if is_trackable then
                if ActionMatcher.is_exception_ignored(exc) then
                    is_ignored = true
                    ignore_reason = "[例外：忽略]"
                end

                -- Check ignore_prev_id condition (supports single number or table of numbers).
                -- During playback, an explicitly expected action must be allowed to validate
                -- even if its exception normally ignores it after a parent/hold action.
                local expected_for_ignore = nil
                if trial_state.is_playing and p_idx == trial_state.playing_player
                    and trial_state.sequence and trial_state.current_step then
                    expected_for_ignore = trial_state.sequence[trial_state.current_step]
                end
                local expected_action_matches_current = expected_for_ignore
                    and expected_for_ignore.id ~= nil
                    and expected_for_ignore.id == act_id

                if not is_ignored and not expected_action_matches_current then
                    local ignore_prev = ActionMatcher.evaluate_ignore_prev(exc, p_state.log, engine_frame_count)
                    if ignore_prev.ignored then
                        is_ignored = true
                        ignore_reason = ignore_prev.reason
                    end
                end

                if p_state.enable_deep_logging then deep_data = capture_deep_action_data(_pf.p_char) end

                if flags == 0 then
                    is_intentional = true
                elseif flags == 16 then
                    if action_code > 0 and b_type ~= 0 then
                        is_intentional = true
                    elseif b_type == 536870932 and (direct_input & 0xFFFF) > 0 then
                        is_intentional = true
                    end
                end

                if ActionMatcher.is_force_enabled(exc) then is_intentional = true end
                if act_id == 36 or act_id == 37 or act_id == 38 then is_intentional = true end

                -- Neutralize intentionality if the action is ignored
                if is_ignored then is_intentional = false end

                -- CALCULATE FACING DIRECTION AT THIS FRAME (outside is_intentional block so log has access)
                pcall(function()
                    local gs_p1 = GS.p1
                    local gs_p2 = GS.p2
                    if not gs_p1 or not gs_p2 then return end
                    local p1_x = gs_p1.pos.x.v
                    local p2_x = gs_p2.pos.x.v
                    if p_idx == 0 then
                        is_facing_left = (p1_x > p2_x)
                    else
                        is_facing_left = (p2_x > p1_x)
                    end
                end)

                local function apply_matched_step(matched_expected, matched_act_id, matched_motion, matched_input, matched_frame, matched_combo, matched_hp, match_reason, match_details)
                    local confirmed, matched_step_idx = ComboTrialsModules.PendingAbsorb.apply_matched_step({
                        state = trial_state,
                        p_idx = p_idx,
                        p_state = p_state,
                        frame = engine_frame_count,
                        pf = _pf,
                        Validator = Validator,
                        DebugTrace = DebugTrace,
                        is_post_hit_setup_step = is_post_hit_setup_step,
                        set_dummy_counter_type = set_dummy_counter_type,
                        d2d_cfg = d2d_cfg,
                        file_system = file_system,
                        act_id_reverse_enum = act_id_reverse_enum
                    }, {
                        expected = matched_expected,
                        actual_action_id = matched_act_id,
                        actual_motion = matched_motion,
                        actual_input = matched_input,
                        frame = matched_frame,
                        combo_count = matched_combo or 0,
                        actual_hp = matched_hp,
                        match_reason = match_reason,
                        match_details = match_details,
                        action_instance = match_details and match_details.action_instance or process_act.action_instance,
                        hold_mask = hold_mask,
                        direct_input = direct_input,
                        hold_frames = hold_frames
                    })
                    if confirmed then
                        trial_step_idx = matched_step_idx
                    end
                    return confirmed
                end

                local function build_match_probe(expected, phase)
                    local prev_step = nil
                    if trial_state.current_step and trial_state.current_step > 1 then
                        prev_step = trial_state.sequence[trial_state.current_step - 1]
                    end
                    local last_played = trial_state.last_played_frame or engine_frame_count
                    local expected_delay = expected and expected.delay_from_prev or nil
                    local frames_since_prev_step = trial_state.current_step and trial_state.current_step > 1
                        and (engine_frame_count - last_played) or 0

                    return {
                        phase = phase,
                        frame = engine_frame_count,
                        trial_file = trial_state.current_file or trial_state.current_file_path,
                        trial_filename = trial_state.current_file_name,
                        character = p_state.profile_name,
                        step = trial_state.current_step,
                        trial_total = trial_state.sequence and #trial_state.sequence or 0,
                        expected_id = expected and expected.id or nil,
                        expected_motion = expected and expected.motion or nil,
                        expected_combo = expected and expected.expected_combo or nil,
                        expected_delay = expected_delay,
                        previous_verified_step = trial_state.current_step and trial_state.current_step - 1 or nil,
                        previous_id = prev_step and prev_step.id or nil,
                        previous_motion = prev_step and prev_step.motion or nil,
                        previous_expected_combo = prev_step and prev_step.expected_combo or nil,
                        previous_has_hit = prev_step and prev_step.has_hit or nil,
                        previous_last_frame_diff = prev_step and prev_step.last_frame_diff or nil,
                        actual_action_id = act_id,
                        actual_action_name = act_name,
                        actual_motion = motion_str,
                        actual_input = real_input_str,
                        action_instance = process_act.action_instance,
                        candidate_action_instance = process_act.action_instance,
                        previous_action_instance = prev_step and prev_step.action_instance or nil,
                        current_combo = _pf.current_combo or 0,
                        combo_count = _pf.current_combo or 0,
                        actual_hp = process_act.current_hp,
                        frames_since_prev_step = frames_since_prev_step,
                        frame_diff = expected_delay and (frames_since_prev_step - expected_delay) or nil,
                        synthetic = process_act.synthetic == true,
                        fallback_source = process_act.fallback_source or process_act.source,
                        edge_type = process_act.edge_type,
                        fallback_frames_since_prev_step = process_act.frames_since_prev_step,
                        fallback_expected_delay = process_act.expected_delay,
                        fallback_frame_diff = process_act.frame_diff,
                        intentional = is_intentional,
                        is_ignored = is_ignored,
                        ignore_reason = ignore_reason,
                        flags = flags,
                        action_code = action_code,
                        branch_type = b_type,
                        direct_input = direct_input,
                        hitstop = _pf.hitstop,
                        blockstop = _pf.blockstop,
                        opponent_knocked_down = _pf.opponent_knocked_down,
                        recent_block_contact_frame = trial_state._recent_block_contact_frame,
                        recent_block_contact_age = trial_state._recent_block_contact_frame
                            and (engine_frame_count - trial_state._recent_block_contact_frame) or nil,
                        recent_block_contact_actor = trial_state._recent_block_contact_actor,
                        recent_block_contact_source = trial_state._recent_block_contact_source,
                        recent_block_damage_type = trial_state._recent_block_damage_type,
                        recent_block_defender_frame_type = trial_state._recent_block_defender_frame_type,
                        recent_block_defender_main_gauge = trial_state._recent_block_defender_main_gauge,
                        recent_block_defender_act_st = trial_state._recent_block_defender_act_st,
                        recent_block_action_id = trial_state._recent_block_action_id,
                        recent_block_action_name = trial_state._recent_block_action_name
                    }
                end

                ComboTrialsModules.PendingAbsorb.check({
                    state = trial_state,
                    p_idx = p_idx,
                    p_state = p_state,
                    frame = engine_frame_count,
                    pf = _pf,
                    Validator = Validator,
                    DebugTrace = DebugTrace,
                    is_post_hit_setup_step = is_post_hit_setup_step,
                    set_dummy_counter_type = set_dummy_counter_type,
                    d2d_cfg = d2d_cfg,
                    file_system = file_system,
                    act_id_reverse_enum = act_id_reverse_enum
                }, "pending_current_absorb_pre_action")

                if is_intentional then
                -- 1. Calculate charge properties
                if exc and exc.is_holdable then
                    is_holdable = true
                    if p_state.profile_name == "Luke" then
                        local w = get_luke_charge_windows(_pf.p_char)
                        luke_perfect_min = exc.perfect_min or w.perfect_min
                        luke_perfect_max = exc.perfect_max or w.perfect_max
                    end

                    charge_min = exc.charge_min
                    charge_max = exc.charge_max
                    dual_threshold = (p_state.profile_name == "Lily")
                    if charge_min == nil or charge_min == "" then
                        local detected_min = auto_detect_charge_min(_pf.p_char)
                        if detected_min then
                            charge_min = detected_min
                            local id_s = tostring(act_id)
                            local exc_to_update = CharacterRules.get_exception(p_state.exceptions, common_exceptions, id_s)
                            if exc_to_update then
                                exc_to_update.charge_min = detected_min
                                if CharacterRules.has_character_exception(p_state.exceptions, id_s) then
                                    json.dump_file(get_exc_filename(p_state.profile_name), p_state.exceptions)
                                else
                                    json.dump_file("TrainingComboTrials_data/exceptions/Common.json", common_exceptions)
                                end
                            end
                        end
                    end
                end

                -- 2. Final motion_str determination
                motion_str = p_state.bcm_cache[act_id]
                local required_mask = p_state.trigger_mask_cache[act_id] or 0
                local best_match = nil

                if required_mask > 0 then
                    for i = #p_state.input_history_queue, 1, -1 do
                        local entry = p_state.input_history_queue[i]
                        if (engine_frame_count - entry.frame_tick) <= 15 and (entry.mask & required_mask) ~= 0 then
                            best_match = entry
                            break
                        end
                    end
                end

                if not best_match then
                    for i = #p_state.input_history_queue, 1, -1 do
                        local entry = p_state.input_history_queue[i]
                        if (engine_frame_count - entry.frame_tick) <= 15 and (entry.mask & 0xFFF0) > 0 then
                            best_match = entry
                            break
                        end
                    end
                end

                if best_match then
                    local real_btn = decode_button_mask(best_match.mask)
                    real_input_str = best_match.dir
                    if real_btn ~= "" then
                        real_input_str = real_input_str ..
                            (real_input_str ~= "" and "+" or "") .. real_btn
                    end

                    local diff = engine_frame_count - best_match.frame_tick
                    if diff == 0 then
                        frame_diff_str = "Instant"
                    else
                        frame_diff_str = "Buffer: " .. tostring(diff) .. "f"
                    end

                    if is_holdable then
                        hold_mask = best_match.mask & 0xFFF0
                        if hold_mask > 0 then
                            is_holding = true
                            hold_frames = process_act.buffer_hold_frames or 1
                        end
                    end
                else
                    real_input_str = "None"
                    frame_diff_str = "?"
                    if is_holdable and p_state.profile_name == "Lily" then
                        hold_mask = direct_input & 0xFFF0
                        if hold_mask > 0 then
                            is_holding = true
                            hold_frames = process_act.buffer_hold_frames or 1
                        end
                    end
                end

                if not motion_str then
                    if best_match then
                        motion_str = "Follow-up (" .. decode_button_mask(best_match.mask) .. ")"
                    else
                        motion_str = act_name
                    end
                end

                if is_drive_rush_id(act_id) then
                    if not is_drive_rush_motion(motion_str) then motion_str = "DRIVE RUSH" end
                end
                if act_id == 17 then motion_str = "66" end
                if act_id == 18 then motion_str = "44" end
                if act_id == 36 then
                    motion_str = "8"; real_input_str = "8"; frame_diff_str = "Mouvement"
                end
                if act_id == 37 then
                    motion_str = "9"; real_input_str = "9"; frame_diff_str = "Mouvement"
                end
                if act_id == 38 then
                    motion_str = "7"; real_input_str = "7"; frame_diff_str = "Mouvement"
                end

                motion_str = ActionMatcher.apply_override_name(motion_str, exc)

                -- 3. COMBO TRIAL HANDLING (Now that motion_str is finalized!)
                if trial_state.is_recording and p_idx == trial_state.recording_player then
                    -- Keep playback start at the recording-start position; first action
                    -- position is only diagnostic/display data.
                    if #trial_state.sequence == 0 then
                        trial_state.first_action_pos_p1 = process_act.p1
                        trial_state.first_action_pos_p2 = process_act.p2
                        trial_state.first_action_pos_p1_raw = process_act.r1
                        trial_state.first_action_pos_p2_raw = process_act.r2
                    end

                    if #trial_state.sequence > 0 then
                        local prev_step = trial_state.sequence[#trial_state.sequence]
                        if not trial_state._pending_hit_cc then
                            prev_step.expected_combo = _pf.current_combo
                        end

                        -- Do not tag whiff here. During recording the combo counter can lag behind
                        -- the next action by a frame, which made the live list show false "空挥"
                        -- entries while the saved combo was correct. Final whiff detection still
                        -- runs once recording stops.
                        if (_pf.current_combo or 0) > 0 then
                            prev_step.has_hit = true
                            if prev_step.motion then
                                prev_step.motion = prev_step.motion:gsub("%s*%(空挥%)", ""):gsub("%s*%(WHIFF%)", "")
                            end
                            if p_state.log then
                                for _, log_to_update in ipairs(p_state.log) do
                                    if log_to_update.trial_step_idx == #trial_state.sequence and log_to_update.motion then
                                        log_to_update.motion = log_to_update.motion:gsub("%s*%(空挥%)", ""):gsub("%s*%(WHIFF%)", "")
                                        break
                                    end
                                end
                            end
                            -- Capture CH/PC at the moment of the hit
                            if trial_state.is_recording and prev_step.counter_type == 0 then
                                pcall(function()
                                    local v_obj = _pf.victim_obj
                                    if v_obj then
                                        local pc = v_obj:get_type_definition():get_field("counter_fw_flag"):get_data(v_obj)
                                        local ch = v_obj:get_type_definition():get_field("counter_dm_flag"):get_data(v_obj)
                                        if pc == true then prev_step.counter_type = 2
                                        elseif ch == true then prev_step.counter_type = 1 end
                                    end
                                end)
                            end
                        end
    						end

                    local last_rec = trial_state.last_recorded_frame or engine_frame_count
                    local delay = 0
                    if #trial_state.sequence > 0 then delay = engine_frame_count - last_rec end
                    trial_state.last_recorded_frame = engine_frame_count

                    -- Snapshot damage for the PREVIOUS step (damage done up to now)
                    if #trial_state.sequence > 0 and trial_state._rec_gauges then
                        local rg = trial_state._rec_gauges
                        local v_hp_now = rg.min_victim_hp or rg.victim_hp
                        trial_state.sequence[#trial_state.sequence].damage_at_step = math.max(0, rg.victim_hp - v_hp_now)
                    end

                    local recorded_hold_frames = tonumber(hold_frames or 0) or 0
                    local buffered_hold_frames = tonumber(process_act.buffer_hold_frames or 0) or 0
                    if buffered_hold_frames > recorded_hold_frames then
                        recorded_hold_frames = buffered_hold_frames
                    end

                    table.insert(trial_state.sequence, {
                        id = act_id,
                        motion = motion_str,
                        expected_hp = process_act.current_hp,
                        is_holdable = is_holdable,
                        dual_threshold = dual_threshold,
                        charge_min = charge_min,
                        charge_max = charge_max,
                        hold_frames = recorded_hold_frames,
                        hold_partial_check = ActionMatcher.hold_partial_check_enabled(exc),
                        expected_combo = 0,
                        actual_combo = 0,
                        has_hit = false,
                        delay_from_prev = delay,
                        facing_left = is_facing_left,
                        counter_type = 0, -- will be updated on hit (CH/PC detected via flags)
                        next_auto_id = nil -- Will be filled if the next action is automatic
                    })
                    trial_step_idx = #trial_state.sequence
                elseif trial_state.is_playing and p_idx == trial_state.playing_player and #trial_state.sequence > 0 then

                    if not trial_state.manual_reset_pending and trial_state.success_timer == 0 and not (trial_state.fail_timer and trial_state.fail_timer > 0) then
                        local allow_input = true
                        local expected = trial_state.sequence[trial_state.current_step]

                        if trial_state.fail_timer and trial_state.fail_timer > 0 then
                            -- Block ALL inputs during fail/reload period
                            allow_input = false
                        end

                        if allow_input then
                            while expected and expected.display_only == true do
                                local display_step_idx = trial_state.current_step
                                local last_played = trial_state.last_played_frame or engine_frame_count
                                DebugTrace.record_match_probe(trial_state, {
                                    phase = "display_only_skip",
                                    branch = "display_only_skip",
                                    skipped_display_only_step = true,
                                    frame = engine_frame_count,
                                    trial_file = trial_state.current_file or trial_state.current_file_path,
                                    trial_filename = trial_state.current_file_name,
                                    character = p_state.profile_name,
                                    step = display_step_idx,
                                    trial_total = trial_state.sequence and #trial_state.sequence or 0,
                                    expected_id = expected.id,
                                    expected_motion = expected.motion,
                                    expected_combo = expected.expected_combo,
                                    expected_delay = expected.delay_from_prev,
                                    actual_action_id = act_id,
                                    actual_action_name = act_name,
                                    actual_motion = motion_str,
                                    actual_input = real_input_str,
                                    current_combo = _pf.current_combo or 0,
                                    combo_count = _pf.current_combo or 0,
                                    actual_hp = process_act.current_hp,
                                    frames_since_prev_step = engine_frame_count - last_played,
                                    display_only = true,
                                    next_step = display_step_idx + 1,
                                    next_expected_id = trial_state.sequence[display_step_idx + 1]
                                        and trial_state.sequence[display_step_idx + 1].id or nil,
                                    next_expected_motion = trial_state.sequence[display_step_idx + 1]
                                        and trial_state.sequence[display_step_idx + 1].motion or nil
                                })
                                if trial_state.sequence[display_step_idx + 1] then
                                    trial_state._ui_step_hold_step = display_step_idx + 1
                                    trial_state._ui_step_hold_until_frame = engine_frame_count + 12
                                end
                                trial_state.current_step = trial_state.current_step + 1
                                trial_state.ui_visual_step = trial_state.current_step
                                expected = trial_state.sequence[trial_state.current_step]
                            end
                            if not expected then
                                allow_input = false
                            end
                        end

                        if allow_input then
                            _pf.ct_pending_block = trial_state._pending_block_outcome
                            if _pf.ct_pending_block and _pf.ct_pending_block.step == trial_state.current_step then
                                if _pf.ct_pending_block.outcome_ok == true then
                                    _pf.ct_pending_expected = trial_state.sequence[_pf.ct_pending_block.step]
                                    _pf.ct_block_details = {
                                        actual_action_id = _pf.ct_pending_block.action_id,
                                        match_reason = "block_outcome",
                                        outcome_pending = false,
                                        outcome_ok = true,
                                        block_contact_seen = _pf.ct_pending_block.block_contact_seen,
                                        block_contact_frame = _pf.ct_pending_block.block_contact_frame,
                                        block_contact_delta = _pf.ct_pending_block.block_contact_delta,
                                        block_contact_source = _pf.ct_pending_block.block_contact_source,
                                        block_contact_damage_type = _pf.ct_pending_block.block_contact_damage_type,
                                        block_contact_action_id = _pf.ct_pending_block.block_contact_action_id,
                                        block_contact_action_name = _pf.ct_pending_block.block_contact_action_name,
                                        source = "block_outcome_pending"
                                    }
                                    _pf.ct_block_probe = build_match_probe(_pf.ct_pending_expected, "block_outcome_confirm")
                                    _pf.ct_block_probe.branch = "block_outcome_confirm"
                                    _pf.ct_block_probe.hit_result = _pf.ct_pending_block.hit_result
                                    _pf.ct_block_probe.outcome_pending = false
                                    _pf.ct_block_probe.outcome_ok = true
                                    _pf.ct_block_probe.block_contact_seen = _pf.ct_pending_block.block_contact_seen
                                    _pf.ct_block_probe.block_contact_frame = _pf.ct_pending_block.block_contact_frame
                                    _pf.ct_block_probe.block_contact_delta = _pf.ct_pending_block.block_contact_delta
                                    _pf.ct_block_probe.block_contact_source = _pf.ct_pending_block.block_contact_source
                                    _pf.ct_block_probe.block_contact_damage_type = _pf.ct_pending_block.block_contact_damage_type
                                    _pf.ct_block_probe.block_contact_action_id = _pf.ct_pending_block.block_contact_action_id
                                    _pf.ct_block_probe.block_contact_action_name = _pf.ct_pending_block.block_contact_action_name
                                    DebugTrace.record_match_probe(trial_state, _pf.ct_block_probe)
                                    if apply_matched_step(
                                        _pf.ct_pending_expected,
                                        _pf.ct_pending_block.action_id,
                                        _pf.ct_pending_block.motion or "Unknown",
                                        _pf.ct_pending_block.input or "None",
                                        _pf.ct_pending_block.action_frame or engine_frame_count,
                                        _pf.ct_pending_block.combo_count or 0,
                                        _pf.ct_pending_block.actual_hp,
                                        "block_outcome",
                                        _pf.ct_block_details
                                    ) then
                                        trial_state._pending_block_outcome = nil
                                        expected = trial_state.sequence[trial_state.current_step]
                                        if not expected then allow_input = false end
                                    else
                                        trial_state.fail_timer = d2d_cfg.fail_display_frames or 120
                                        trial_state.fail_reason = "BLOCK OUTCOME VALIDATION FAILED"
                                        allow_input = false
                                    end
                                elseif engine_frame_count > (_pf.ct_pending_block.expires_at_frame or engine_frame_count) then
                                    _pf.ct_block_probe = build_match_probe(trial_state.sequence[_pf.ct_pending_block.step], "block_outcome_timeout")
                                    _pf.ct_block_probe.branch = "block_outcome_timeout"
                                    _pf.ct_block_probe.hit_result = _pf.ct_pending_block.hit_result
                                    _pf.ct_block_probe.outcome_pending = true
                                    _pf.ct_block_probe.outcome_ok = false
                                    _pf.ct_block_probe.block_contact_seen = false
                                    _pf.ct_block_probe.reject_reason = "block_outcome_timeout"
                                    DebugTrace.record_match_probe(trial_state, _pf.ct_block_probe)
                                    trial_state._pending_block_outcome = nil
                                    trial_state.fail_timer = d2d_cfg.fail_display_frames or 120
                                    trial_state.fail_reason = "BLOCK NOT CONFIRMED"
                                    allow_input = false
                                else
                                    _pf.ct_block_probe = build_match_probe(trial_state.sequence[_pf.ct_pending_block.step], "block_outcome_wait")
                                    _pf.ct_block_probe.branch = "block_outcome_wait"
                                    _pf.ct_block_probe.hit_result = _pf.ct_pending_block.hit_result
                                    _pf.ct_block_probe.outcome_pending = true
                                    _pf.ct_block_probe.outcome_ok = false
                                    _pf.ct_block_probe.reject_reason = "block_outcome_pending"
                                    DebugTrace.record_match_probe(trial_state, _pf.ct_block_probe)
                                    allow_input = false
                                end
                            end
                        end

                        if allow_input then
                            local action_match = ActionMatcher.match_expected_action(expected, act_id, motion_str, real_input_str)
                            if process_act.synthetic then
                                action_match.source = process_act.fallback_source or process_act.source
                                action_match.edge_type = process_act.edge_type
                                action_match.synthetic = true
                                action_match.frames_since_prev_step = process_act.frames_since_prev_step
                                action_match.expected_delay = process_act.expected_delay
                                action_match.frame_diff = process_act.frame_diff
                            end
                            local match_probe = build_match_probe(expected, "intentional_action")
                            local trace_prev_step = trial_state.current_step and trial_state.current_step > 1
                                and trial_state.sequence[trial_state.current_step - 1] or nil
                            local trace_combo_ok = expected and Validator.check_combo({
                                expected = expected,
                                prev_step = trace_prev_step,
                                current_combo = _pf.current_combo or 0,
                                opponent_knocked_down = _pf.opponent_knocked_down
                            }) or nil
                            local trace_hp_ok = expected and Validator.check_hp(
                                expected.expected_hp,
                                process_act.current_hp,
                                is_post_hit_setup_step((trial_state.current_step or 1) - 1),
                                expected
                            ) or nil
                            match_probe.action_match = {
                                matched = action_match.matched,
                                match_reason = action_match.match_reason,
                                expected_id = action_match.expected_id,
                                actual_action_id = action_match.actual_action_id,
                                source = action_match.source,
                                edge_type = action_match.edge_type,
                                synthetic = action_match.synthetic
                            }
                            _G.CTSameActionTrace.trace("action_match_entry", p_state, {
                                candidate_action_id = act_id,
                                candidate_action_instance = process_act.action_instance,
                                candidate_motion = motion_str,
                                candidate_input = real_input_str,
                                previous_step_id = trace_prev_step and trace_prev_step.id or nil,
                                action_match_matched = action_match.matched,
                                action_match_reason = action_match.match_reason,
                                match_result = action_match.matched,
                                reject_reason = action_match.matched and nil or "action_mismatch",
                                combo_ok = trace_combo_ok,
                                hp_ok = trace_hp_ok,
                                direct_input = direct_input,
                                flags = flags,
                                action_code = action_code,
                                branch_type = b_type
                            })
                            if expected and not action_match.matched
                                and ct_is_unreported_same_action_pressure_step(trace_prev_step, expected) then
                                _pf.pressure_skip = ct_try_skip_unreported_same_action_pressure_step({
                                    state = trial_state,
                                    expected = expected,
                                    prev_step = trace_prev_step,
                                    action_match_matched = action_match.matched,
                                    act_id = act_id,
                                    motion = motion_str,
                                    input = real_input_str,
                                    synthetic = process_act.synthetic,
                                    synthetic_frame = process_act.engine_frame,
                                    combo_count = _pf.current_combo or 0,
                                    ActionMatcher = ActionMatcher,
                                    Validator = Validator,
                                    DebugTrace = DebugTrace,
                                    match_probe = match_probe
                                })
                                if _pf.pressure_skip then
                                    expected = _pf.pressure_skip.expected
                                    action_match = _pf.pressure_skip.action_match
                                    trace_prev_step = _pf.pressure_skip.prev_step
                                    _pf.pressure_skip = nil
                                    match_probe = build_match_probe(expected, "intentional_action_after_pressure_same_skip")
                                    match_probe.action_match = {
                                        matched = action_match.matched,
                                        match_reason = action_match.match_reason,
                                        expected_id = action_match.expected_id,
                                        actual_action_id = action_match.actual_action_id,
                                        source = action_match.source,
                                        edge_type = action_match.edge_type,
                                        synthetic = action_match.synthetic
                                    }
                                else
                                    _pf.pressure_skip = nil
                                end
                            end
                            local skip_current_action = false
                            local consumed_for_step = nil
                            if process_act.action_instance ~= nil and type(trial_state._consumed_action_instances) == "table" then
                                consumed_for_step = trial_state._consumed_action_instances[process_act.action_instance]
                            end
                            if expected and not action_match.matched then
                                local recent_absorb = CharacterRules.find_recent_absorb_confirmation(
                                    p_state.exceptions,
                                    common_exceptions,
                                    expected,
                                    p_state.log,
                                    p_state.profile_name
                                )
                                match_probe.recent_absorb = recent_absorb
                                if recent_absorb.matched then
                                    local confirmed = apply_matched_step(
                                        expected,
                                        recent_absorb.actual_action_id,
                                        recent_absorb.motion or "Unknown",
                                        recent_absorb.real_input or "None",
                                        recent_absorb.start_frame or engine_frame_count,
                                        recent_absorb.combo_count or 0,
                                        process_act.current_hp,
                                        recent_absorb.match_reason,
                                        recent_absorb
                                    )
                                    match_probe.branch = "recent_absorb"
                                    match_probe.recent_absorb_confirmed = confirmed
                                    if confirmed then
                                        local chain_limit = 3
                                        local chain_count = 0
                                        match_probe.recent_absorb_chain_started = true
                                        match_probe.recent_absorb_chain = {}
                                        match_probe.chain_limit_reached = false

                                        while chain_count < chain_limit do
                                            local chain_step = trial_state.current_step
                                            local chain_expected = trial_state.sequence[chain_step]
                                            if not chain_expected then break end
                                            if chain_step <= 1 then
                                                table.insert(match_probe.recent_absorb_chain, {
                                                    chain_iteration = chain_count + 1,
                                                    chain_step = chain_step,
                                                    chain_result = "rejected",
                                                    chain_reject_reason = "step_not_after_first"
                                                })
                                                break
                                            end

                                            local chain_absorb = CharacterRules.find_recent_absorb_confirmation(
                                                p_state.exceptions,
                                                common_exceptions,
                                                chain_expected,
                                                p_state.log,
                                                p_state.profile_name
                                            )
                                            local chain_record = {
                                                chain_iteration = chain_count + 1,
                                                chain_step = chain_step,
                                                chain_expected_id = chain_expected.id,
                                                chain_expected_motion = chain_expected.motion,
                                                chain_absorb_candidate = chain_absorb
                                            }
                                            table.insert(match_probe.recent_absorb_chain, chain_record)

                                            if not chain_absorb.matched then
                                                chain_record.chain_result = "rejected"
                                                chain_record.chain_reject_reason = chain_absorb.block_reason or "no_recent_absorb_match"
                                                chain_record.chain_post_step = trial_state.current_step
                                                break
                                            end

                                            local chain_frame = chain_absorb.start_frame or engine_frame_count
                                            local chain_last_played = trial_state.last_played_frame or chain_frame
                                            local chain_actual_delay = chain_step > 1 and (chain_frame - chain_last_played) or 0
                                            local chain_frame_diff = Validator.calculate_frame_diff(chain_actual_delay, chain_expected.delay_from_prev)
                                            chain_record.chain_frames_since_prev_step = chain_actual_delay
                                            chain_record.chain_expected_delay = chain_expected.delay_from_prev
                                            chain_record.chain_frame_diff = chain_frame_diff

                                            if math.abs(chain_frame_diff) > 2 then
                                                chain_record.chain_result = "rejected"
                                                chain_record.chain_reject_reason = "timing_window"
                                                chain_record.chain_post_step = trial_state.current_step
                                                break
                                            end

                                            local chain_prev_step = chain_step > 1 and trial_state.sequence[chain_step - 1] or nil
                                            local chain_combo = chain_absorb.combo_count or 0
                                            local chain_combo_ok = Validator.check_combo({
                                                expected = chain_expected,
                                                prev_step = chain_prev_step,
                                                current_combo = chain_combo,
                                                opponent_knocked_down = _pf.opponent_knocked_down
                                            })
                                            local chain_hp_ok = Validator.check_hp(
                                                chain_expected.expected_hp,
                                                process_act.current_hp,
                                                is_post_hit_setup_step(chain_step - 1),
                                                chain_expected
                                            )
                                            chain_record.chain_combo_ok = chain_combo_ok
                                            chain_record.chain_hp_ok = chain_hp_ok

                                            if not chain_combo_ok then
                                                chain_record.chain_result = "rejected"
                                                chain_record.chain_reject_reason = "combo_check"
                                                chain_record.chain_post_step = trial_state.current_step
                                                break
                                            end
                                            if not chain_hp_ok then
                                                chain_record.chain_result = "rejected"
                                                chain_record.chain_reject_reason = "hp_check"
                                                chain_record.chain_post_step = trial_state.current_step
                                                break
                                            end

                                            local chain_details = {
                                                actual_action_id = chain_absorb.actual_action_id,
                                                match_reason = "ehonda_recent_absorb_chain",
                                                recent_index = chain_absorb.recent_index,
                                                combo_count = chain_absorb.combo_count,
                                                start_frame = chain_absorb.start_frame,
                                                action_instance = chain_absorb.action_instance,
                                                motion = chain_absorb.motion,
                                                real_input = chain_absorb.real_input,
                                                intentional = chain_absorb.intentional,
                                                expected_id = chain_absorb.expected_id,
                                                expected_combo = chain_absorb.expected_combo,
                                                absorb_ids = chain_absorb.absorb_ids,
                                                source = "recent_absorb_chain"
                                            }
                                            local chain_confirmed = apply_matched_step(
                                                chain_expected,
                                                chain_absorb.actual_action_id,
                                                chain_absorb.motion or "Unknown",
                                                chain_absorb.real_input or "None",
                                                chain_frame,
                                                chain_combo,
                                                process_act.current_hp,
                                                "ehonda_recent_absorb_chain",
                                                chain_details
                                            )
                                            chain_record.chain_result = chain_confirmed and "confirmed" or "failed"
                                            chain_record.chain_post_step = trial_state.current_step

                                            if not chain_confirmed then
                                                break
                                            end
                                            chain_count = chain_count + 1
                                        end

                                        if chain_count >= chain_limit and trial_state.sequence[trial_state.current_step] then
                                            match_probe.chain_limit_reached = true
                                        end
                                        match_probe.final_step_after_chain = trial_state.current_step

                                        expected = trial_state.sequence[trial_state.current_step]
                                        if expected then
                                            action_match = ActionMatcher.match_expected_action(expected, act_id, motion_str, real_input_str)
                                            match_probe.post_absorb_step = trial_state.current_step
                                            match_probe.post_absorb_action_match = {
                                                matched = action_match.matched,
                                                match_reason = action_match.match_reason,
                                                expected_id = action_match.expected_id,
                                                actual_action_id = action_match.actual_action_id
                                            }
                                        else
                                            skip_current_action = true
                                        end
                                    else
                                        skip_current_action = true
                                    end
                                end
                            end

                            if skip_current_action then
                                -- EHonda recent absorb already consumed the pending expected step.
                                match_probe.reject_reason = "skip_after_recent_absorb"
                                DebugTrace.record_match_probe(trial_state, match_probe)
                            elseif consumed_for_step and consumed_for_step < (trial_state.current_step or 1) then
                                match_probe.branch = "consumed_action_instance_ignored"
                                match_probe.reject_reason = nil
                                match_probe.duplicate_instance_ignored = true
                                match_probe.ignored_as_previous_step_residue = true
                                match_probe.candidate_action_instance = process_act.action_instance
                                match_probe.consumed_action_instance = process_act.action_instance
                                match_probe.candidate_consumed_for_step = consumed_for_step
                                match_probe.last_matched_action_instance = trial_state._last_matched_action_instance
                                DebugTrace.record_match_probe(trial_state, match_probe)
                            elseif expected and ActionMatcher.is_optional_parent_for_followup(
                                motion_str,
                                expected,
                                act_id,
                                CharacterRules.get_exception(p_state.exceptions, common_exceptions, expected.id)
                            ) then
                                -- Older combo JSON may omit the stance entry before a > follow-up.
                                -- Do not let the parent action match the follow-up by button input.
                                match_probe.reject_reason = "optional_parent_for_followup"
                                DebugTrace.record_match_probe(trial_state, match_probe)
                            elseif action_match.matched and expected and trace_prev_step
                                and trace_prev_step.id == expected.id
                                and trace_prev_step.id == act_id
                                and trace_prev_step.action_instance
                                and process_act.action_instance
                                and trace_prev_step.action_instance == process_act.action_instance then
                                match_probe.branch = "same_action_instance_duplicate_ignored"
                                match_probe.reject_reason = nil
                                match_probe.previous_action_instance = trace_prev_step.action_instance
                                match_probe.action_instance = process_act.action_instance
                                DebugTrace.record_match_probe(trial_state, match_probe)
                            elseif action_match.matched and expected and expected.hit_result == "block" then
                                _pf.ct_block_action_frame = process_act.synthetic
                                    and (process_act.engine_frame or engine_frame_count) or engine_frame_count
                                trial_state._pending_block_outcome = {
                                    step = trial_state.current_step,
                                    expected_id = expected.id,
                                    expected_motion = expected.motion,
                                    hit_result = expected.hit_result,
                                    action_frame = _pf.ct_block_action_frame,
                                    action_id = act_id,
                                    motion = motion_str,
                                    input = real_input_str,
                                    combo_count = _pf.current_combo or 0,
                                    actual_hp = process_act.current_hp,
                                    match_reason = action_match.match_reason,
                                    window = 15,
                                    expires_at_frame = _pf.ct_block_action_frame + 15,
                                    outcome_ok = false,
                                    block_contact_seen = false
                                }
                                _pf.ct_recent_block_frame = trial_state._recent_block_contact_frame
                                if _pf.ct_recent_block_frame then
                                    _pf.ct_block_delta = _pf.ct_recent_block_frame - _pf.ct_block_action_frame
                                    if _pf.ct_block_delta >= 0 and _pf.ct_block_delta <= 15 then
                                        trial_state._pending_block_outcome.outcome_ok = true
                                        trial_state._pending_block_outcome.block_contact_seen = true
                                        trial_state._pending_block_outcome.block_contact_frame = _pf.ct_recent_block_frame
                                        trial_state._pending_block_outcome.block_contact_delta = _pf.ct_block_delta
                                        trial_state._pending_block_outcome.block_contact_source = trial_state._recent_block_contact_source
                                        trial_state._pending_block_outcome.block_contact_damage_type = trial_state._recent_block_damage_type
                                        trial_state._pending_block_outcome.block_contact_action_id = trial_state._recent_block_action_id
                                        trial_state._pending_block_outcome.block_contact_action_name = trial_state._recent_block_action_name
                                    end
                                end
                                match_probe.branch = "block_outcome_pending"
                                match_probe.hit_result = expected.hit_result
                                match_probe.outcome_pending = true
                                match_probe.outcome_ok = trial_state._pending_block_outcome.outcome_ok == true
                                match_probe.block_contact_seen = trial_state._pending_block_outcome.block_contact_seen == true
                                match_probe.block_contact_frame = trial_state._pending_block_outcome.block_contact_frame
                                match_probe.block_contact_delta = trial_state._pending_block_outcome.block_contact_delta
                                match_probe.block_contact_source = trial_state._pending_block_outcome.block_contact_source
                                match_probe.block_contact_damage_type = trial_state._pending_block_outcome.block_contact_damage_type
                                match_probe.reject_reason = "block_outcome_pending"
                                DebugTrace.record_match_probe(trial_state, match_probe)
                            elseif action_match.matched then
                                match_probe.branch = process_act.synthetic and "same_dash_fallback" or "direct_match"
                                DebugTrace.record_match_probe(trial_state, match_probe)
                                apply_matched_step(
                                    expected,
                                    act_id,
                                    motion_str,
                                    real_input_str,
                                    process_act.synthetic and (process_act.engine_frame or engine_frame_count) or engine_frame_count,
                                    _pf.current_combo or 0,
                                    process_act.current_hp,
                                    action_match.match_reason,
                                    action_match
                                )
                            else
                                local is_parry = is_parry_action(motion_str, real_input_str, act_name)
                                local is_current_dr = is_drive_rush_id(act_id) or is_drive_rush_motion(motion_str)
                                local expecting_dr = expected and (is_drive_rush_id(expected.id) or is_drive_rush_motion(expected.motion))
                                local expecting_parry = expected and expected.motion and expected.motion:upper():match("PARRY") ~= nil
                                local is_first_step_dr = is_drive_rush_id(trial_state.sequence[1].id) or is_drive_rush_motion(trial_state.sequence[1].motion)
                                local is_first_step_parry = trial_state.sequence[1].motion and trial_state.sequence[1].motion:upper():match("PARRY") ~= nil
                                local first_step_dr_parry_reset_candidate = (is_first_step_dr and is_parry) or (is_first_step_parry and is_current_dr)
                                local combo_in_progress = (_pf.current_combo or 0) > 0
                                local just_confirmed_recent_absorb = match_probe.recent_absorb_confirmed == true
                                    and (match_probe.post_absorb_step or 0) > (match_probe.step or 0)
                                match_probe.is_parry = is_parry
                                match_probe.is_current_dr = is_current_dr
                                match_probe.expecting_dr = expecting_dr
                                match_probe.expecting_parry = expecting_parry
                                match_probe.is_first_step_dr = is_first_step_dr
                                match_probe.is_first_step_parry = is_first_step_parry
                                match_probe.first_step_dr_parry_reset_candidate = first_step_dr_parry_reset_candidate
                                match_probe.combo_in_progress = combo_in_progress
                                match_probe.just_confirmed_recent_absorb = just_confirmed_recent_absorb

                                if expected and is_pressure_tail_step(expected) then
                                    if expected.finish_on_action == true then
                                        match_probe.branch = "pressure_tail_wait_for_finish_action"
                                        match_probe.reject_reason = "pressure_tail_action_mismatch_wait"
                                        DebugTrace.record_match_probe(trial_state, match_probe)
                                    else
                                        match_probe.branch = "pressure_tail_whiff_tolerance"
                                        match_probe.reject_reason = nil
                                        DebugTrace.record_match_probe(trial_state, match_probe)
                                        apply_matched_step(
                                            expected,
                                            act_id,
                                            motion_str,
                                            real_input_str,
                                            process_act.synthetic and (process_act.engine_frame or engine_frame_count) or engine_frame_count,
                                            _pf.current_combo or 0,
                                            process_act.current_hp,
                                            "pressure_tail_whiff",
                                            action_match
                                        )
                                    end
                                elseif expecting_dr and is_parry then
                                    -- Tolerance: Expecting DR, got Parry → ignore, wait for DR
                                    match_probe.reject_reason = "expecting_dr_got_parry_wait"
                                    DebugTrace.record_match_probe(trial_state, match_probe)
                                elseif expecting_parry and is_current_dr then
                                    -- Tolerance: Expecting Parry, got DR directly → skip Parry step, validate DR on next
                                    match_probe.branch = "expecting_parry_got_dr_skip"
                                    DebugTrace.record_match_probe(trial_state, match_probe)
                                    trial_state._step1_wrong_pending = false
                                    ComboTrialsModules.PendingAbsorb.clear(trial_state, "parry_dr_skip")
                                    trial_state.last_played_frame = engine_frame_count
                                    trial_state.current_step = trial_state.current_step + 1
                                    local next_expected = trial_state.sequence[trial_state.current_step]
                                    if next_expected and (is_drive_rush_id(next_expected.id) or is_drive_rush_motion(next_expected.motion)) then
                                        trial_state.current_step = trial_state.current_step + 1
                                    end
                                elseif expecting_dr and is_current_dr then
                                    -- Tolerance: DR id mismatch (739 vs 740 vs char-specific) → validate
                                    match_probe.branch = "drive_rush_id_tolerance"
                                    DebugTrace.record_match_probe(trial_state, match_probe)
                                    trial_state._step1_wrong_pending = false
                                    ComboTrialsModules.PendingAbsorb.clear(trial_state, "drive_rush_tolerance")
                                    trial_state.last_played_frame = engine_frame_count
                                    trial_state.current_step = trial_state.current_step + 1
                                elseif ct_should_ignore_duplicate_previous_pressure_action(
                                    trace_prev_step,
                                    expected,
                                    act_id,
                                    process_act.action_instance
                                ) then
                                    match_probe.branch = "pressure_duplicate_previous_action_ignored"
                                    match_probe.reject_reason = nil
                                    match_probe.ignored_duplicate_previous_id = act_id
                                    match_probe.previous_id = trace_prev_step and trace_prev_step.id or nil
                                    match_probe.waiting_for_expected_id = expected and expected.id or nil
                                    match_probe.waiting_for_expected_motion = expected and expected.motion or nil
                                    DebugTrace.record_match_probe(trial_state, match_probe)
                                elseif first_step_dr_parry_reset_candidate and not combo_in_progress and not just_confirmed_recent_absorb then
                                    match_probe.branch = "reset_first_step_dr_parry"
                                    DebugTrace.record_match_probe(trial_state, match_probe)
                                    trial_state.fail_timer = 0
                                    trial_state.fail_reason = nil
                                    reset_trial_steps()
                                    trial_step_idx = nil
                                else
                                    if first_step_dr_parry_reset_candidate then
                                        match_probe.reset_first_step_dr_parry_blocked = true
                                        if combo_in_progress then
                                            match_probe.reset_first_step_dr_parry_block_reason = "combo_in_progress"
                                        elseif just_confirmed_recent_absorb then
                                            match_probe.reset_first_step_dr_parry_block_reason = "recent_absorb_advanced_step"
                                        end
                                    end
                                    if trial_state.current_step == 1 then
                                        match_probe.reject_reason = "step1_wrong_pending"
                                        DebugTrace.record_match_probe(trial_state, match_probe)
                                        trial_state._step1_wrong_pending = true
                                    else
                                        match_probe.reject_reason = "wrong_move"
                                        local same_summary = p_state._same_action_trace_summary or {}
                                        match_probe.same_action_trace = {
                                            expected_same_as_previous = expected and trace_prev_step and expected.id == trace_prev_step.id or false,
                                            expected_is_dash = expected and (expected.id == 17 or expected.id == 18
                                                or expected.motion == "66" or expected.motion == "44") or false,
                                            saw_66_edge_since_prev_step = same_summary.saw_66_edge,
                                            saw_44_edge_since_prev_step = same_summary.saw_44_edge,
                                            saw_act17_since_prev_step = same_summary.saw_act17,
                                            act17_min_frame = same_summary.act17_min_frame,
                                            act17_max_frame = same_summary.act17_max_frame,
                                            act17_rewound = same_summary.act17_rewound,
                                            same_dash_fallback_last_eval = p_state._same_dash_fallback_last_eval
                                        }
                                        _G.CTSameActionTrace.trace("wrong_move", p_state, {
                                            candidate_action_id = act_id,
                                            candidate_motion = motion_str,
                                            candidate_input = real_input_str,
                                            previous_step_id = trace_prev_step and trace_prev_step.id or nil,
                                            match_result = false,
                                            reject_reason = "wrong_move",
                                            combo_ok = trace_combo_ok,
                                            hp_ok = trace_hp_ok,
                                            expected_id_equals_previous_expected_id = expected and trace_prev_step and expected.id == trace_prev_step.id or false,
                                            expected_motion_is_dash = expected and (expected.motion == "66" or expected.motion == "44") or false,
                                            saw_66_edge_since_prev_step = same_summary.saw_66_edge,
                                            saw_44_edge_since_prev_step = same_summary.saw_44_edge,
                                            saw_act17_since_prev_step = same_summary.saw_act17,
                                            act17_min_frame = same_summary.act17_min_frame,
                                            act17_max_frame = same_summary.act17_max_frame,
                                            act17_rewound = same_summary.act17_rewound,
                                            same_dash_fallback_last_eval = p_state._same_dash_fallback_last_eval
                                        })
                                        DebugTrace.record_match_probe(trial_state, match_probe)
                                        ComboTrialsModules.PendingAbsorb.clear(trial_state, "wrong_move")
                                        trial_state.fail_timer = d2d_cfg.fail_display_frames or 120
                                        trial_state.fail_reason = "WRONG MOVE"
                                    end
                                end
                            end
                        end
                    end
                end
            end
            -- CODE OK 							

            if trial_state.is_playing and p_idx == trial_state.playing_player
                and not is_intentional
                and #trial_state.sequence > 0
                and not trial_state.manual_reset_pending
                and trial_state.success_timer == 0
                and not (trial_state.fail_timer and trial_state.fail_timer > 0) then
                local expected = trial_state.sequence[trial_state.current_step]
                local current_absorb = CharacterRules.match_current_absorb_confirmation(
                    p_state.exceptions,
                    common_exceptions,
                    expected,
                    act_id,
                    _pf.current_combo or 0,
                    p_state.profile_name
                )
                local match_probe = build_match_probe(expected, "non_intentional_action")
                match_probe.current_absorb = current_absorb
                match_probe.reject_reason = current_absorb.matched and nil or current_absorb.block_reason
                if not current_absorb.matched and current_absorb.block_reason == "combo_not_reached" then
                    ComboTrialsModules.PendingAbsorb.store({
                        state = trial_state,
                        p_idx = p_idx,
                        p_state = p_state,
                        frame = engine_frame_count,
                        pf = _pf,
                        Validator = Validator,
                        DebugTrace = DebugTrace,
                        is_post_hit_setup_step = is_post_hit_setup_step,
                        set_dummy_counter_type = set_dummy_counter_type,
                        d2d_cfg = d2d_cfg,
                        file_system = file_system,
                        act_id_reverse_enum = act_id_reverse_enum
                    }, expected, current_absorb, match_probe, process_act.current_hp)
                end
                DebugTrace.record_match_probe(trial_state, match_probe)
                if current_absorb.matched then
                    apply_matched_step(
                        expected,
                        current_absorb.actual_action_id,
                        current_absorb.motion or "Unknown",
                        current_absorb.real_input or "None",
                        engine_frame_count,
                        current_absorb.combo_count or 0,
                        process_act.current_hp,
                        current_absorb.match_reason,
                        current_absorb
                    )
                end
            end

            -- AUTOMATIC ACTION HANDLING AFTER A HOLD (outside is_intentional block)
            -- This must be OUTSIDE the is_intentional block because auto actions are not intentional

            -- DURING RECORDING: capture the automatic action following a holdable step
            if trial_state.is_recording and p_idx == trial_state.recording_player
                and not is_intentional and #trial_state.sequence > 0 then
                local prev_step = trial_state.sequence[#trial_state.sequence]
                if prev_step.is_holdable and prev_step.next_auto_id == nil then
                    prev_step.next_auto_id = act_id
                end
            end

            -- DURING PLAYBACK: verify the exact automatic action
            if trial_state.is_playing and p_idx == trial_state.playing_player
                and not is_intentional and trial_state.pending_auto_check then
                local pac = trial_state.pending_auto_check
                if act_id ~= pac.expected_id then
                    trial_state.fail_timer = d2d_cfg.fail_display_frames or 120
                    trial_state.fail_reason = "WRONG HOLD TIMING"
                end
                trial_state.pending_auto_check = nil
            end
    				end

            ::continue_to_log::
            table.insert(p_state.log, 1, {
                dual_threshold = dual_threshold,
                id = act_id,
                name = act_name,
                motion = motion_str,
                real_input = real_input_str,
                frame_diff = frame_diff_str,
                intentional = is_intentional,
                is_holdable = is_holdable,
                is_holding = is_holding,
                hold_frames = hold_frames,
                hold_mask = hold_mask,
                trigger_mask = best_match and (best_match.mask & 0xFFF0) or (direct_input & 0xFFF0),
                is_physically_holding = false,
                charge_min = charge_min,
                charge_max = charge_max,
                charge_status = charge_status,
                luke_perfect_min = luke_perfect_min,
                luke_perfect_max = luke_perfect_max,
                transition_id = nil,
                deep_data = deep_data,
                combo_count = 0,
                is_finished = false,
                trial_step_idx = trial_step_idx,
                action_instance = process_act.action_instance,
                start_frame = engine_frame_count,
                facing_left = is_facing_left,
                is_ignored = is_ignored,
                ignore_reason = ignore_reason
            })

            if trial_state.is_recording and p_idx == trial_state.recording_player
                and (p_state.profile_name == "EHonda" or p_state.profile_name == "Honda") then
                local json_step = trial_step_idx and trial_state.sequence[trial_step_idx] or nil
                DebugTrace.record_honda_normal_input(trial_state, {
                    frame = engine_frame_count,
                    character = p_state.profile_name,
                    trial_file = trial_state.current_file_name or trial_state.current_file or "",
                    recording = true,
                    recording_step = #trial_state.sequence,
                    action_id = act_id,
                    motion = motion_str,
                    real_input = real_input_str,
                    intentional = is_intentional,
                    trackable = is_trackable,
                    combo_count = _pf.current_combo or 0,
                    is_unknown = motion_str == "Unknown" or act_name == "Unknown",
                    json_step_written = json_step ~= nil,
                    json_step_motion = json_step and json_step.motion or nil,
                    json_step_id = json_step and json_step.id or nil,
                    display_name = act_name,
                    raw_input = direct_input,
                    flags = flags,
                    action_code = action_code,
                    branch_type = b_type,
                    input = "",
                    expected_motion = "",
                    notes = ""
                })
            end

            if #p_state.log > 100 then table.remove(p_state.log) end
        end -- END OF "if not is_continuation" block
    end -- END OF for _, process_act
    p_state.prev_act_id = _pf.act_id
end

local function ct_player_universal_hold(p_idx, p_state)
    -- UNIVERSAL HOLD EVALUATION (EVALUATE ONLY UPON FULL BUTTON RELEASE)
    -- ========================================================
    if trial_state.is_playing and p_idx == trial_state.playing_player and trial_state.active_universal_hold then
        local uh = trial_state.active_universal_hold
        if uh.hold_mask > 0 and (_pf.direct_input & uh.hold_mask) ~= 0 then
            uh.frames = uh.frames + 1
        else
            -- Optional retrieval of perfect windows (e.g. Luke)
            local p_min, p_max = nil, nil
            local act_id_str = tostring(uh.expected_action_id or p_state.prev_act_id)
            local exc = CharacterRules.get_exception(p_state.exceptions, common_exceptions, act_id_str)
            if exc then p_min = exc.perfect_min; p_max = exc.perfect_max end

            local release_frames = math.max(0, (tonumber(uh.frames) or 0) - 1)
            local final_status = evaluate_charge_status(
                uh.profile_name, release_frames,
                uh.charge_min, uh.charge_max,
                p_min, p_max
            )

            local hold_failed = false
            if final_status ~= uh.expected_status then
                -- If hold_partial_check == false, tolerate mismatches between intermediate levels
                -- (Instant, Partial, Charging, Lv1, Lv2...) but ALWAYS require Maxed/PERFECT/FAKE/LATE
                local hard_statuses = { Maxed = true, ["PERFECT!"] = true, FAKE = true, LATE = true }
                if uh.hold_partial_check == false
                    and not hard_statuses[final_status]
                    and not hard_statuses[uh.expected_status] then
                    -- Partial mismatch tolerated
                else
                    hold_failed = true
                end
            end

            if hold_failed then
            trial_state.success_timer = 0
            trial_state.fail_timer = d2d_cfg.fail_display_frames or 120

            local diff_str = ""
            if uh.expected_frames then
                local diff = release_frames - uh.expected_frames
                local sign = diff > 0 and "+" or ""
                diff_str = string.format(" [%s%df]", sign, diff)
            end

            trial_state.fail_reason = string.format("WRONG HOLD (Got: %s, Exp: %s)%s", final_status, uh.expected_status, diff_str)
            trial_state.current_step = math.max(1, trial_state.current_step - 1)
        end
            trial_state.active_universal_hold = nil
        end
    end
end

-- =========================================================
-- TRIAL SUCCESS: completion marking + auto-advance
-- Attached to ctx inside do..end: the main chunk is close to
-- Lua's 200-local limit, so no new top-level locals.
-- =========================================================
do
    local function advance_to_next_trial()
        if trial_state._xt_pending_save then return false end
        local p_idx = trial_state.playing_player or 0
        local paths = (p_idx == 0) and file_system.saved_combos_paths_p1 or file_system.saved_combos_paths_p2
        local idx = (p_idx == 0) and (file_system.selected_file_idx_p1 or 1) or (file_system.selected_file_idx_p2 or 1)
        if type(paths) ~= "table" or #paths == 0 then return false end
        if idx >= #paths then
            ct_ticker("已完成列表中最后一个连段")
            return false
        end

        if p_idx == 0 then
            file_system.selected_file_idx_p1 = idx + 1
        else
            file_system.selected_file_idx_p2 = idx + 1
        end
        load_and_start_trial(p_idx)
        ct_ticker(string.format("已进入下一个连段 (%d/%d)", idx + 1, #paths))
        return true
    end

    ctx.handle_trial_success_progress = function()
        if not trial_state.is_playing or (demo_state and demo_state.is_playing) then
            trial_state._success_latched = false
            trial_state._auto_next_countdown = nil
            return
        end

        -- Latch the first frame of the success banner: record completion once
        if (trial_state.success_timer or 0) > 0 and not trial_state._success_latched then
            trial_state._success_latched = true
            local path = trial_state.current_file_path or trial_state.current_file
            if file_system.mark_trial_completed(path) then
                refresh_combo_list_preserve_selection(false)
            end
            if d2d_cfg.auto_next_trial ~= false then
                trial_state._auto_next_countdown = d2d_cfg.fail_display_frames or 120
            end
        end

        -- The success banner re-arms itself, so advance on our own countdown.
        -- Keep _success_latched set: if advancing fails (last file in the list),
        -- the still-armed banner must not restart the countdown. A successful
        -- advance resets the latch via clear_trial_attempt_state.
        if trial_state._auto_next_countdown then
            trial_state._auto_next_countdown = trial_state._auto_next_countdown - 1
            if trial_state._auto_next_countdown <= 0 then
                trial_state._auto_next_countdown = nil
                advance_to_next_trial()
            end
        end
    end
end

-- =========================================================
-- MAIN ON_FRAME — ORCHESTRATOR
-- =========================================================
re.on_frame(function()
    file_system.diag_frame = (file_system.diag_frame or 0) + 1
    file_system.diag_runtime_allowed = RuntimeSafety.is_allowed()
    if file_system.diag_last_runtime_allowed ~= file_system.diag_runtime_allowed then
        file_system.diag_last_runtime_allowed = file_system.diag_runtime_allowed
        file_system.diag_log("runtime allowed=" .. tostring(file_system.diag_runtime_allowed)
            .. " mode=" .. tostring(_G.CurrentTrainerMode)
            .. " battlehub=" .. tostring(_G.IsInBattleHub)
            .. " flow=" .. tostring(_G.FlowMapID))
    end

    if not file_system.diag_runtime_allowed then
        if demo_state then
            demo_state.is_playing = false
            demo_state.p1_mask = 0
        end
        ct_handle_mode_exit()
        return
    end
    pcall(_ct_track_live_combo)
    ct_handle_web_commands()

    -- Export globals for web bridge
    local _p_idx = trial_state.playing_player or 0
    local _paths = (_p_idx == 0) and file_system.saved_combos_paths_p1 or file_system.saved_combos_paths_p2
    local _display = (_p_idx == 0) and file_system.saved_combos_display_p1 or file_system.saved_combos_display_p2
    local _fidx = (_p_idx == 0) and (file_system.selected_file_idx_p1 or 1) or (file_system.selected_file_idx_p2 or 1)
    local _fname = _paths and _paths[_fidx] or ""
    local _visual_step = trial_state.current_step or 0
    local _hold_step = trial_state._ui_step_hold_step
    local _hold_until = trial_state._ui_step_hold_until_frame
    local _frame_now = trial_state._engine_frame_count or engine_frame_count
    if _hold_step and _hold_until and _frame_now <= _hold_until then
        _visual_step = _hold_step
    elseif _hold_until and _frame_now > _hold_until then
        trial_state._ui_step_hold_step = nil
        trial_state._ui_step_hold_until_frame = nil
    end
    _G.ComboTrials_CurrentFile = _fname:match("([^/\\]+)$") or _fname
    _G.ComboTrials_CurrentStep = _visual_step
    _G.ComboTrials_ValidationStep = trial_state.current_step or 0
    _G.ComboTrials_TotalSteps = trial_state.sequence and #trial_state.sequence or 0
    _G.ComboTrials_IsPlaying = trial_state.is_playing or false
    _G.ComboTrials_IsRecording = trial_state.is_recording or false
    _G.ComboTrials_IsDemo = (demo_state and demo_state.is_playing) or false
    _G.ComboTrials_FileList = _display or {}
    _G.ComboTrials_FileIdx = _fidx
    _G.ComboTrials_PositionIdx = d2d_cfg.forced_position_idx or 1

    -- BATTLE HUB SPECTATE: script disabled

    if _G.IsInBattleHub then return end

    local _in_replay = (_G.FlowMapID == 10 or _G.IsInReplay)
    ct_handle_replay_cleanup(_in_replay)

    -- Live update of flip_inputs (only before the first hit of the sequence)
    if trial_state.is_playing and trial_state.current_step == 1 then
        pcall(_ct_update_flip_live)
    end

    -- REPLAY REMOTE STATE
    if _in_replay then
        if not _G._replay_web_counter then _G._replay_web_counter = 0 end
        _G._replay_web_counter = _G._replay_web_counter + 1
        if _G._replay_web_counter >= 60 then
            _G._replay_web_counter = 0
            pcall(function()
                json.dump_file("SF6_TrainingRemoteControl_data/Replay_WebState.json", {
                    in_replay = _in_replay,
                    is_recording = trial_state.is_recording or false,
                    recording_player = trial_state.recording_player or -1,
                    hide_ui = _G._tsm_hide_ui or false
                })
            end)
        end
    else
        _G._replay_web_counter = 0
    end


    -- REPLAY REMOTE BRIDGE
    if _in_replay then
        pcall(_ct_replay_bridge_poll)
    end

    ct_dev_hp_restore_test_tick()

    if _G.CurrentTrainerMode ~= 4 then ct_auto_refresh_combo_list(); ct_handle_mode_exit(); return end

    ct_auto_refresh_combo_list()
    ct_poll_trialhub_sync_signal()
    ct_handle_first_frame_init()
    _G.ComboTrials_HideNativeHUD = false

    local is_game_paused = GS.in_pause_menu
    ct_handle_pause_positions(is_game_paused, _in_replay)
    if is_game_paused then return end

    engine_frame_count = engine_frame_count + 1
    trial_state._engine_frame_count = engine_frame_count
    trial_state._demo_timing_ui_baseline = (demo_state and demo_state.is_playing == true) or false
    logger_process_game_state()
    if ctx.handle_trial_success_progress then ctx.handle_trial_success_progress() end

    if trial_state.is_recording then
        if not trial_state._rec_frame_count then trial_state._rec_frame_count = 0 end
        trial_state._rec_frame_count = trial_state._rec_frame_count + 1
        if not trial_state._piyo_detected then
            pcall(_ct_detect_piyo)
        end
    end


    ct_handle_playing_transition()
    ct_handle_position_correction(_in_replay)

    local gBattle = _td_gBattle
    if not gBattle then return end
    _pf.cmd_obj = gBattle:get_field("Command"):get_data(nil)
    if not _pf.cmd_obj then return end
    if not GS.sP then return end

    ct_handle_hp_injection()

    for p_idx = 0, 1 do
        local p_state = players[p_idx]
        ct_player_init(p_idx, p_state)

        _pf.p_char = (p_idx == 0) and GS.p1 or GS.p2
        if not _pf.p_char then p_state.last_combo_count = 0; goto ct_next_player end

        local bcm_resource = _pf.cmd_obj:get_field("mpBCMResource")
        if bcm_resource then
            local p_bcm = bcm_resource[p_idx]
            local current_bcm_ptr = tostring(p_bcm)
            if current_bcm_ptr ~= p_state.last_bcm_ptr then
                p_state.last_bcm_ptr = current_bcm_ptr
                p_state.cache_built = false
            end
        end
        if not p_state.cache_built then build_bcm_cache(p_idx) end

        _pf.act_id, _pf.act_frame, _pf.flags, _pf.action_code, _pf.direct_input, _pf.b_type = get_action_data(_pf.p_char)
        _pf.current_combo = get_combo_count(_pf.p_char)
        _pf.victim_idx = 1 - p_idx
        _pf.victim_obj = (_pf.victim_idx == 0) and GS.p1 or GS.p2

        ct_player_tracking(p_idx, p_state)
        ct_player_validation(p_idx, p_state)
        ct_player_hold_charge(p_state)
        local actions_to_process = ct_player_input_buffer(p_state)
        ct_player_process_actions(p_idx, p_state, actions_to_process)
        ct_player_universal_hold(p_idx, p_state)

        p_state.last_combo_count = _pf.current_combo
        ::ct_next_player::
    end
    ComboTrialsModules.PendingAbsorb.sync_failure_ui_result(trial_state)
end)




function save_trial_sequence(meta)
    if #trial_state.sequence == 0 then return end
    local rec_p = trial_state.recording_player
    local char_name = players[rec_p].profile_name

    local p_state = players[rec_p]
    if #trial_state.sequence > 0 and #p_state.log > 0 then
        local last_step = trial_state.sequence[#trial_state.sequence]
        for _, log_entry in ipairs(p_state.log) do
                    if log_entry.trial_step_idx == #trial_state.sequence then
                        last_step.expected_combo = log_entry.combo_count or 0
                        break
                    end
                end

                -- FINAL WHIFF DETECTION: Apply the tag on the very last recorded hit
                -- Also consider expected_combo > 0 as proof of hit (cancel/last hit)
                if not last_step.has_hit and (last_step.expected_combo or 0) == 0 then
                    local p_id = last_step.id or 0
                    local is_mov = (p_id == 17 or p_id == 18 or p_id == 36 or p_id == 37 or p_id == 38) or is_drive_rush_id(p_id)
                    local is_ingrid_charge_stock = ct_is_ingrid_charge_stock_action(char_name, p_id)
                    local m_str = last_step.motion and last_step.motion:upper() or ""
                    local is_parry = m_str:match("PARRY")
                    local is_dash = m_str:match("DASH") or m_str:match("66") or m_str:match("44") or is_drive_rush_motion(last_step.motion)

                    if not is_mov and not is_ingrid_charge_stock and not is_parry and not is_dash and not m_str:match("空挥") and not m_str:match("WHIFF") then
                        last_step.motion = last_step.motion .. " (空挥)"
                    end
                end

                if trial_state.start_pos_p1 and trial_state.start_pos_p2 then
            trial_state.sequence[1].start_pos_p1 = trial_state.start_pos_p1
            trial_state.sequence[1].start_pos_p2 = trial_state.start_pos_p2
            trial_state.sequence[1].start_pos_p1_raw = trial_state.start_pos_p1_raw
            trial_state.sequence[1].start_pos_p2_raw = trial_state.start_pos_p2_raw
            trial_state.sequence[1].recording_start_pos_p1 = trial_state.recording_start_pos_p1 or trial_state.start_pos_p1
            trial_state.sequence[1].recording_start_pos_p2 = trial_state.recording_start_pos_p2 or trial_state.start_pos_p2
            trial_state.sequence[1].recording_start_pos_p1_raw = trial_state.recording_start_pos_p1_raw or trial_state.start_pos_p1_raw
            trial_state.sequence[1].recording_start_pos_p2_raw = trial_state.recording_start_pos_p2_raw or trial_state.start_pos_p2_raw
            if trial_state.first_action_pos_p1 and trial_state.first_action_pos_p2 then
                trial_state.sequence[1].first_action_pos_p1 = trial_state.first_action_pos_p1
                trial_state.sequence[1].first_action_pos_p2 = trial_state.first_action_pos_p2
                trial_state.sequence[1].first_action_pos_p1_raw = trial_state.first_action_pos_p1_raw
                trial_state.sequence[1].first_action_pos_p2_raw = trial_state.first_action_pos_p2_raw
            end
            trial_state.sequence[1].recorded_by = rec_p
            if trial_state._piyo_detected then
                trial_state.sequence[1].has_piyo = true
                trial_state.sequence[1].piyo_frame = trial_state._piyo_frame
            end
        end

        -- Snapshot damage for the LAST step
        if #trial_state.sequence > 0 and trial_state._rec_gauges then
            local rg = trial_state._rec_gauges
            local v_hp_now = rg.min_victim_hp or rg.victim_hp
            trial_state.sequence[#trial_state.sequence].damage_at_step = math.max(0, rg.victim_hp - v_hp_now)
        end

        -- Calculate combo stats (damage, drive, super, hit type)
        -- Uses MIN values tracked frame-by-frame (training refills gauges)
        local init = trial_state._rec_gauges
        local stats = { hit_type = trial_state._rec_hit_type }
        if init then
            stats.damage     = math.max(0, init.victim_hp - (init.min_victim_hp or init.victim_hp))
            stats.drive_used = math.max(0, init.attacker_drive - (init.min_atk_drive or init.attacker_drive))
            stats.super_used = math.max(0, init.attacker_super - (init.min_atk_super or init.attacker_super))
        end
        trial_state.sequence[1].combo_stats = stats
        if init and init.defender_burnout == true then
            local snapshot = trial_state.sequence[1].snapshot_gauges
            if type(snapshot) ~= "table" then snapshot = {} end
            snapshot.defender_burnout = true
            snapshot.defender_drive = tonumber(init.defender_drive) or 0
            trial_state.sequence[1].snapshot_gauges = snapshot
        end
        local hp_init = trial_state._rec_hp_snapshot
        local hp_attacker = (type(hp_init) == "table" and hp_init.attacker) or (init and init.hp_attacker) or nil
        local hp_victim = (type(hp_init) == "table" and hp_init.victim) or (init and init.hp_victim) or nil
        if hp_snapshot_is_damaged(hp_attacker) or hp_snapshot_is_damaged(hp_victim) then
            local snapshot = trial_state.sequence[1].snapshot_gauges
            if type(snapshot) ~= "table" then snapshot = {} end
            if hp_snapshot_is_damaged(hp_attacker) then
                snapshot.attacker = copy_hp_snapshot(hp_attacker)
            end
            if hp_snapshot_is_damaged(hp_victim) then
                snapshot.victim = copy_hp_snapshot(hp_victim)
            end
            trial_state.sequence[1].snapshot_gauges = snapshot
        end
        if (trial_state.sequence[1].counter_type == nil or trial_state.sequence[1].counter_type == 0) and stats.hit_type then
            local inferred_ct = counter_type_from_hit_type(stats.hit_type)
            if inferred_ct ~= 0 then trial_state.sequence[1].counter_type = inferred_ct end
        end
        if logger_state.last_export_name then
            trial_state.sequence[1].raw_input_file = logger_state.last_export_name
        end
        trial_state._rec_gauges = nil
        trial_state._rec_hp_snapshot = nil
        trial_state._rec_hit_type = nil
    end

    if type(meta) == "table" and type(trial_state.sequence[1]) == "table" then
        local scene_state = trial_state._rec_scene_state or unique_resources.capture_scene_state(rec_p)
        if type(scene_state) == "table" then
            trial_state.sequence[1].scene_state = scene_state
        end
        trial_state.sequence[1]._xt_meta = apply_recording_environment_to_meta(meta)
    end
    normalize_sequence_counter_types(trial_state.sequence)

    if fs.create_dir then
        pcall(fs.create_dir, "TrainingComboTrials_data/CustomCombos"); pcall(fs.create_dir, "TrainingComboTrials_data/CustomCombos/" .. char_name)
    end

    -- Filename: CharName_COMBO_Motion_Damage_DriveBarSpent_SABarSpent.json
    local cs = trial_state.sequence[1] and trial_state.sequence[1].combo_stats
    local dmg = (cs and cs.damage) or 0
    local drive_spent = (cs and cs.drive_used) or 0
    local sa_spent = (cs and cs.super_used) or 0
    local drive_bars = string.format("%.1f", drive_spent / 10000)
    local sa_bars = string.format("%.1f", sa_spent / 10000)
    drive_bars = drive_bars:gsub("%.0$", "")
    sa_bars = sa_bars:gsub("%.0$", "")

    -- Detect OKI: combo was active (>0), drops to 0, then a later step hits
    local has_oki = false
    local saw_combo = false
    local combo_dropped = false
    for _, step in ipairs(trial_state.sequence) do
        if (step.expected_combo or 0) > 0 then saw_combo = true end
        if saw_combo and (step.expected_combo or 0) == 0 then combo_dropped = true end
        if combo_dropped and step.has_hit then has_oki = true; break end
    end

    local type_tag = has_oki and "_OKI" or "_COMBO"
    local starter_motion_raw = trial_state.sequence[1] and trial_state.sequence[1].motion or ""
    local starter_motion = file_system.get_safe_filename_motion(trial_state.sequence)
    file_system.log_combo_save("starter motion raw=" .. tostring(starter_motion_raw))
    file_system.log_combo_save("starter motion id=" .. tostring(starter_motion))
    local title_suffix = ""
    local meta_title = type(meta) == "table" and meta.title or nil
    if trim_string(meta_title) ~= "" then
        local safe_title = file_system.sanitize_filename_component(meta_title, 32, "")
        if safe_title ~= "" then
            title_suffix = "_" .. safe_title
        end
    end
    local safe_char_name = file_system.sanitize_filename_component(char_name, 32, "Unknown")
    local base_name = safe_char_name .. type_tag .. "_" .. starter_motion .. "_" .. dmg .. "_D" .. drive_bars .. "_SA" .. sa_bars .. title_suffix
    local fname = base_name .. ".json"
    local path = "TrainingComboTrials_data/CustomCombos/" .. char_name .. "/" .. fname

    -- Avoid overwriting: append timestamp if file exists
    if file_system.file_exists(path) then
        local ts = os.date("%Y%m%d_%H%M%S")
        fname = base_name .. "_" .. ts .. ".json"
        path = "TrainingComboTrials_data/CustomCombos/" .. char_name .. "/" .. fname
    end

    file_system.log_combo_save("output filename=" .. tostring(fname))

    assign_groups(trial_state.sequence)
    json.dump_file(path, trial_state.sequence)
    trial_state._rec_environment = nil
    trial_state._rec_scene_state = nil
    refresh_combo_list_preserve_selection(false)
    local paths = rec_p == 0 and file_system.saved_combos_paths_p1 or file_system.saved_combos_paths_p2
    for idx, combo_path in ipairs(paths) do
        if combo_path == path then
            if rec_p == 0 then
                file_system.selected_file_idx_p1 = idx
            else
                file_system.selected_file_idx_p2 = idx
            end
            break
        end
    end
    load_combo_from_file(path, true)

    _G.ComboTrials_LastSavedFilename = fname
    _G.ComboTrials_LastSavedPlayer = rec_p
    return path
end

-- =========================================================
-- MODULE UI (extracted to func/ComboTrials_UI.lua)
-- =========================================================
-- Add references to shared context for the UI module
ctx.file_system = file_system
ctx.common_exceptions = common_exceptions
ctx.load_and_start_trial = load_and_start_trial
ctx.start_recording = start_recording
ctx.stop_recording_and_save = stop_recording_and_save
ctx.cancel_recording = cancel_recording
ctx.cancel_recording_due_to_menu = cancel_recording_due_to_menu
ctx.refresh_combo_list = refresh_combo_list
ctx.restore_trial_vital = restore_trial_vital
ctx.save_d2d_config = save_d2d_config
ctx.clear_completed_trials = function()
    file_system.clear_completed_trials()
    refresh_combo_list_preserve_selection(false)
end
ctx.get_exc_filename = get_exc_filename
ctx.ui_state = ui_state
ctx.apply_forced_position = apply_forced_position
ctx.xt_settings = xt_settings
ctx.save_xt_settings = function(default_author)
    local author = trim_string(default_author)
    if author == "" then author = "佚名" end
    xt_settings.default_author = author
    save_xt_settings()
    return true
end
ctx.dump_last_fail = function()
    local last_fail_dump = DebugTrace.get_last_fail(trial_state)
    if not last_fail_dump then return nil end
    local char_name = players[trial_state.playing_player].profile_name or "Unknown"
    local ts = os.date("%Y%m%d_%H%M%S")
    local safe_char_name = file_system.sanitize_filename_component(char_name, 32, "Unknown")
    local fname = safe_char_name .. "_FAIL_" .. ts .. ".json"
    
    if fs.create_dir then 
        pcall(fs.create_dir, "TrainingComboTrials_data/CustomCombos")
        pcall(fs.create_dir, "TrainingComboTrials_data/CustomCombos/Fails") 
    end
    
    local path = "TrainingComboTrials_data/CustomCombos/Fails/" .. fname
    DebugTrace.write_json(path, last_fail_dump)
    return path
end
ctx.reset_visuals = function()
    reset_combo_visual_runtime()
    step_combo_reset_gc()
end
ctx.reset_trial_steps_and_load = function(player_idx)
    if #trial_state.sequence > 0 then
        trial_state.is_playing = true
        trial_state.playing_player = player_idx
        reset_trial_steps()
        return
    end

    local paths = (player_idx == 0) and file_system.saved_combos_paths_p1 or file_system.saved_combos_paths_p2
    local idx = (player_idx == 0) and (file_system.selected_file_idx_p1 or 1) or (file_system.selected_file_idx_p2 or 1)
    if #paths > 0 then
        load_combo_from_file(paths[idx], true)
        start_trial(player_idx)
    end
end
-- =========================================================
-- DEMO ENGINE LOGIC & EXPORTS
-- =========================================================
local function parse_timeline_line(line)
    local frames_str, rest = line:match("^(%d+)f%s*:%s*(.*)")
    if not frames_str then return nil end
    local frames = tonumber(frames_str)
    
    local parts = {}
    for p in rest:gmatch("[^+]+") do table.insert(parts, p:match("^%s*(.-)%s*$")) end
    
    local dir_to_mask = { ["7"]=9, ["8"]=1, ["9"]=5, ["4"]=8, ["5"]=0, ["6"]=4, ["1"]=10, ["2"]=2, ["3"]=6 }
    local btn_to_mask = { ["LP"]=16, ["MP"]=32, ["HP"]=64, ["LK"]=128, ["MK"]=256, ["HK"]=512 }
    
    local mask = dir_to_mask[parts[1]] or 0
    for i = 2, #parts do if btn_to_mask[parts[i]] then mask = mask | btn_to_mask[parts[i]] end end
    return { frames = frames, mask = mask }
end

CTStunDemoRuntime = CTStunDemoRuntime or {}

function CTStunDemoRuntime.needs_state_restore()
    local first = trial_state.sequence and trial_state.sequence[1]
    if type(first) ~= "table" then return false end
    local gauges = first.snapshot_gauges
    return first.has_piyo == true
        or (type(gauges) == "table" and gauges.defender_burnout == true)
end

function CTStunDemoRuntime.get_training_player_params(player_idx)
    local out = get_training_parameter_probe_objects(player_idx)
    if type(out) ~= "table" then out = {} end
    if not out.player_params and out.parameter_setting and out.parameter_setting.PlayerDatas then
        pcall(function() out.player_params = out.parameter_setting.PlayerDatas[player_idx] end)
    end
    return out
end

function CTStunDemoRuntime.save_drive_settings_once(player_idx, player_params)
    if not player_params then return end
    if type(trial_state._saved_drive_settings) ~= "table" then
        trial_state._saved_drive_settings = {}
    end
    if trial_state._saved_drive_settings[player_idx] ~= nil then return end

    local saved_drive = {}
    for _, field_name in ipairs(DRIVE_SETTING_FIELDS) do
        local value = player_params[field_name]
        if value ~= nil then saved_drive[field_name] = value end
    end
    if next(saved_drive) ~= nil then trial_state._saved_drive_settings[player_idx] = saved_drive end
end

function CTStunDemoRuntime.restore_pre_demo_state()
    if not CTStunDemoRuntime.needs_state_restore() then return false end

    local first = trial_state.sequence and trial_state.sequence[1]
    local gauges = type(first) == "table" and first.snapshot_gauges or nil
    if not (type(gauges) == "table" and gauges.defender_burnout == true) then return false end

    local attacker_idx = tonumber(trial_state.playing_player or 0) or 0
    if attacker_idx ~= 1 then attacker_idx = 0 end
    local defender_idx = 1 - attacker_idx
    local objects = CTStunDemoRuntime.get_training_player_params(defender_idx)
    local params = objects.player_params
    if not params then return false end

    local tm = objects.tm or sdk.get_managed_singleton("app.training.TrainingManager")
    local refresh_before = tm and tm:get_field("_IsReqRefresh") == true
    local defender_drive = math.max(0, tonumber(gauges.defender_drive) or 0)
    local defender_stock = math.floor((defender_drive + 5000) / 10000)

    CTStunDemoRuntime.save_drive_settings_once(defender_idx, params)
    pcall(function() params.DG_Point = defender_drive end)
    pcall(function() params.DG_Stock = defender_stock end)
    pcall(function() params.Is_DG_Break = true end)

    if objects.param_func then
        pcall(function() objects.param_func:call("SetDGDetailPoint", defender_idx, defender_drive) end)
        pcall(function() objects.param_func:call("SetDGStock", defender_idx, defender_stock) end)
    end

    local defender = (defender_idx == 1) and GS.p2 or GS.p1
    if defender then pcall(function() defender.focus_new = defender_drive end) end

    if tm and refresh_before ~= true and tm:get_field("_IsReqRefresh") == true then
        pcall(function() tm:set_field("_IsReqRefresh", false) end)
    end
    return true
end

function CTStunDemoRuntime.advance_timeline_frames(frame_count)
    frame_count = tonumber(frame_count or 0) or 0
    if frame_count <= 0 then return 0 end

    local advanced = 0
    while advanced < frame_count do
        local step = demo_state.sequence[demo_state.current_step]
        if not step then break end

        local step_frames = tonumber(step.frames or 0) or 0
        if step_frames <= 0 then
            demo_state.current_step = demo_state.current_step + 1
            demo_state.current_frame = 0
        else
            local current_frame = tonumber(demo_state.current_frame or 0) or 0
            local remaining = step_frames - current_frame
            if remaining <= 0 then
                demo_state.current_step = demo_state.current_step + 1
                demo_state.current_frame = 0
            else
                local consume = math.min(frame_count - advanced, remaining)
                demo_state.current_frame = current_frame + consume
                advanced = advanced + consume
                if demo_state.current_frame >= step_frames then
                    demo_state.current_step = demo_state.current_step + 1
                    demo_state.current_frame = 0
                end
            end
        end
    end

    return advanced
end

function CTStunDemoRuntime.catch_up_missed_engine_frames()
    if not CTStunDemoRuntime.needs_state_restore() then return 0 end
    local now_frame = engine_frame_count or 0
    local last_frame = demo_state._last_tick_frame
    if type(last_frame) ~= "number" then return 0 end

    local missed = now_frame - last_frame - 1
    if missed <= 0 then return 0 end
    return CTStunDemoRuntime.advance_timeline_frames(missed)
end

local function start_demo()
    if not trial_state.sequence or #trial_state.sequence == 0 then return end
    local first_stun_step = trial_state.sequence[1]
    local first_stun_gauges = type(first_stun_step) == "table" and first_stun_step.snapshot_gauges or nil
    local manual_stun_demo_required = type(first_stun_step) == "table"
        and first_stun_step.has_piyo == true
        and not (type(first_stun_gauges) == "table" and first_stun_gauges.defender_burnout == true)
    if manual_stun_demo_required and not _G._allow_stun_demo then return end
    
    -- 1. Check for embedded timeline directly in the file (Merged files)
    local timeline = trial_state.sequence[1].timeline
    
    -- 2. Backward compatibility fallback (Old 2-part files)
    if not timeline then
        local raw_file = trial_state.sequence[1].raw_input_file
        if not raw_file then print("[ComboTrials] No timeline or raw input file!"); return end
        
        local loaded = json.load_file("TrainingComboTrials_data/ReplayRecords/" .. raw_file)
        if not loaded or not loaded.timeline then print("[ComboTrials] Failed to load ReplayRecord"); return end
        timeline = loaded.timeline
    end
    
    demo_state.sequence = {}
    for _, line in ipairs(timeline) do
        local parsed = parse_timeline_line(line)
        if parsed then table.insert(demo_state.sequence, parsed) end
    end
    if #demo_state.sequence == 0 then return end

    -- Force Trial mode to stay active on P1
    trial_state.is_recording = false
    trial_state.is_playing = true
    trial_state.playing_player = 0
    
    -- CLEANUP TIMERS
    trial_state.success_timer = 0
    trial_state.fail_timer = 0
    trial_state.fail_reason = nil
    trial_state.active_universal_hold = nil
    
    -- Full history purge at Demo launch
    players[0].log = {}
    players[0].input_history_queue = {}
    reset_combo_visual_runtime()
    
    update_trial_flip_state()
    reset_trial_steps()

    demo_state.is_playing = true
    trial_state._demo_timing_ui_baseline = true
    demo_state.countdown = 10
    demo_state.current_frame = 0
    demo_state.current_step = 1
    demo_state.p1_mask = 0
    demo_state._last_tick_frame = nil
    demo_state._state_reinjected = false
    demo_state._total_frames = 0
    demo_state._piyo_waiting = false
    demo_state._piyo_triggered = false
    demo_state.current_file = trial_state.current_file
    demo_state.current_file_path = trial_state.current_file_path
    demo_state.current_file_name = trial_state.current_file_name

    print("[ComboTrials] DEMO Started for P1")
end

ctx.demo_state = demo_state
ctx.stop_demo = function()
    ctx.stop_demo_playback(
        "manual_stop",
        demo_state.current_file_path or trial_state.current_file_path or trial_state.current_file,
        nil,
        false
    )
end
ctx.start_demo = start_demo

local function can_start_combo_action()
    return not trial_state.is_recording
        and not trial_state.is_playing
        and not (demo_state and demo_state.is_playing)
end

local function is_replay_context()
    return _G.FlowMapID == 10 or _G.IsInReplay == true
end

local function switch_position_mode()
    d2d_cfg.forced_position_idx = (d2d_cfg.forced_position_idx or 1) + 1
    if d2d_cfg.forced_position_idx > 3 then d2d_cfg.forced_position_idx = 1 end
    save_d2d_config()

    if trial_state.is_playing then
        apply_forced_position()
        reset_trial_steps()
        if ctx.reset_visuals then ctx.reset_visuals() end
    elseif d2d_cfg.forced_position_idx == 1 then
        apply_forced_position()
    end

    ct_ticker("位置模式：" .. (POS_TICKER_NAMES[d2d_cfg.forced_position_idx] or ""))
end

ctx.commands = {
    record_p1 = function()
        if not can_start_combo_action() then return end
        if is_replay_context() then _G.ComboTrials_ReplaySavePlayer = 0 end
        start_recording(0)
        ct_ticker("录制中")
    end,
    record_p2 = function()
        if not can_start_combo_action() then return end
        if is_replay_context() then _G.ComboTrials_ReplaySavePlayer = 1 end
        start_recording(1)
        ct_ticker("录制中")
    end,
    save_recording = function()
        if not trial_state.is_recording then return end
        if is_replay_context() then _G.ComboTrials_ReplaySavePlayer = trial_state.recording_player end
        stop_recording_and_save()
        ct_ticker("录制已保存")
    end,
    cancel_recording = function()
        if not trial_state.is_recording then return end
        if is_replay_context() then _G.ComboTrials_ReplayCancelPlayer = trial_state.recording_player end
        cancel_recording()
        ct_ticker("录制已取消")
    end,
    start_trial = function()
        if not can_start_combo_action() then return end
        load_and_start_trial(0)
        ct_ticker("连段训练已启动")
    end,
    reset_trial = function()
        if demo_state and demo_state.is_playing then
            start_demo()
        elseif trial_state.is_playing then
            ctx.reset_trial_steps_and_load(trial_state.playing_player or 0)
        end
    end,
    stop_trial = function()
        if not trial_state.is_playing and not (demo_state and demo_state.is_playing) then return end
        if ctx.stop_demo_playback then
            ctx.stop_demo_playback(
                "manual_stop",
                demo_state.current_file_path or trial_state.current_file_path or trial_state.current_file,
                nil,
                true
            )
        end
        trial_state.is_playing = false
        ct_ticker("连段训练已停止")
    end,
    start_demo = function()
        if trial_state.is_recording then return end
        start_demo()
    end,
    restart_demo = function()
        if not (demo_state and demo_state.is_playing) then return end
        start_demo()
    end,
    quit_demo = function()
        if not (demo_state and demo_state.is_playing) then return end
        if ctx.stop_demo then ctx.stop_demo() end
    end,
    switch_position = function()
        if trial_state.is_recording then return end
        switch_position_mode()
    end,
    open_combo_dropdown = function()
        if trial_state.is_recording then return end
        _G.ComboTrials_OpenDropdown = true
    end,
}

local TrainingHotkeys = require("func/Training_Hotkeys")
local ComboTrialsHotkeys = require("func/ComboTrials_Hotkeys")
ComboTrialsHotkeys.init(ctx, TrainingHotkeys)

-- (Keep sf6_menu_state below this as before)
sf6_menu_state = { active = false, x = 0, y = 0, w = 0, h = 0 }
ctx.sf6_menu_state = sf6_menu_state


local ComboTrials_UI = require("func/ComboTrials_UI")
ComboTrials_UI.init(ctx)


-- ============================================================
-- SAVE STATE / LOAD STATE: sync with active trial
-- ============================================================
local _trial_snapshot    = nil
local _pending_restore   = 0
local _save_pending      = false
local _real_frame        = 0
local _save_fired_at     = 0
local _save_step_at_fire = 1

local function apply_restore()
    if not _trial_snapshot then return end
    if not trial_state.is_playing then return end
    trial_state.current_step      = _trial_snapshot.step or 1
    trial_state.success_timer     = 0
    trial_state.fail_timer        = 0
    trial_state.fail_reason       = nil
    local frames_since            = _trial_snapshot.frames_since_step or 0
    trial_state.last_played_frame = engine_frame_count - frames_since
    if _trial_snapshot.flip_inputs ~= nil then
        trial_state.flip_inputs = _trial_snapshot.flip_inputs
    end
    if _trial_snapshot.sequence then
        for i, saved in ipairs(_trial_snapshot.sequence) do
            if trial_state.sequence[i] then
                trial_state.sequence[i].has_hit      = saved.has_hit
                trial_state.sequence[i].actual_combo = saved.actual_combo
            end
        end
    else
        for _, item in ipairs(trial_state.sequence) do
            item.has_hit      = false
            item.actual_combo = 0
        end
    end
    reset_combo_visual_runtime()
end

local function clear_trial_snapshot()
    _trial_snapshot  = nil
    _pending_restore = 0
    _save_pending    = false
end

-- Debug log
local _dbg_log = {}
local function dbg(s)
    table.insert(_dbg_log, 1, string.format("[%d] %s", _real_frame, s))
    if #_dbg_log > 20 then table.remove(_dbg_log) end
end

local _save_display = "jamais"
local _save_count   = 0
local _load_display = "jamais"
local _load_count   = 0

-- re.on_draw_ui(function()
-- imgui.begin_window("TrialSaveState DEBUG", true, 0)
-- imgui.text_colored("SAVE: " .. _save_count .. "x  " .. _save_display, 0xFF88FF88)
-- imgui.text_colored("LOAD: " .. _load_count .. "x  " .. _load_display, 0xFF8888FF)
-- imgui.separator()
-- for _, l in ipairs(_dbg_log) do imgui.text(l) end
-- imgui.end_window()
-- end)


if not _G._allow_stun_demo then _G._allow_stun_demo = false end

local function _ct_get_field(obj, name)
    return obj:get_field(name)
end

local _ss_hooked = false
re.on_frame(function()
    if rawget(_G, "CT_SAVE_STATE_POC") ~= true then
        _save_pending = false
        _pending_restore = 0
        return
    end
    if not RuntimeSafety.is_training_allowed() then
        _save_pending = false
        _pending_restore = 0
        return
    end
    if not _ss_hooked then
        _ss_hooked = true
        local td = sdk.find_type_definition("app.training.TrainingManager")
        if td then
            local save_methods = { "requestSaveState", "SaveKeyData" }
            local load_methods = { "requestLoadState" }
            
            for _, name in ipairs(save_methods) do
                local m = td:get_method(name)
                if m then
                    pcall(function()
                        sdk.hook(m, function(args)
                            if _pending_restore > 0 then return end
                            _save_pending      = true
                            _save_fired_at     = _real_frame
                            _save_step_at_fire = trial_state.current_step
                            dbg("Save() " .. name .. " step=" .. tostring(trial_state.current_step))
                        end, function(retval) return retval end)
                    end)
                end
            end

            for _, name in ipairs(load_methods) do
                local m = td:get_method(name)
                if m then
                    pcall(function()
                        sdk.hook(m, function(args)
                            _load_count   = _load_count + 1
                            _save_pending = false
                            if _trial_snapshot and trial_state.is_playing then
                                _pending_restore = 8
                            end
                        end, function(retval) return retval end)
                    end)
                end
            end
        end
    end

    -- If Save fired and no Load followed within 5 frames -> real Save
    if _save_pending and (_real_frame - _save_fired_at) >= 5 then
        _save_pending = false
        if trial_state.is_playing then
            local snap_sequence = {}
            for i, item in ipairs(trial_state.sequence) do
                snap_sequence[i] = { has_hit = item.has_hit, actual_combo = item.actual_combo }
            end
            _trial_snapshot = {
                step              = _save_step_at_fire,
                frames_since_step = engine_frame_count - (trial_state.last_played_frame or engine_frame_count),
                sequence          = snap_sequence,
                flip_inputs       = trial_state.flip_inputs,
            }
            _save_count     = _save_count + 1
            _save_display   = os.date("%H:%M:%S") .. " [SnapShoted] step=" .. tostring(_save_step_at_fire)
            dbg("-> snapshot saved step=" ..
                tostring(_trial_snapshot.step) .. " frames_since=" .. tostring(_trial_snapshot.frames_since_step))
        end
    end

    -- STOP TRIAL -> clear
    if not trial_state.is_playing and _trial_snapshot then
        clear_trial_snapshot()
    end

    -- GUARD: cancel the refresh triggered by save shortcuts when trial is active with forced position.
    -- Do not cancel our own reset/start refresh; pending_exact_pos is set by apply_forced_position().
    local save_refresh_recent = _save_fired_at > 0 and (_real_frame - _save_fired_at) <= 8
    if trial_state.is_playing and save_refresh_recent and d2d_cfg.forced_position_idx ~= 1
        and not (trial_state.pending_exact_pos and trial_state.pending_exact_pos > 0) then
        local tm2 = sdk.get_managed_singleton("app.training.TrainingManager")
        if tm2 then
            local ok, ts = pcall(_ct_get_field, tm2, "_TrainingState")
            local ok2, rf = pcall(_ct_get_field, tm2, "_IsReqRefresh")
            if ok and ok2 and ts == 2 and rf == true then
                pcall(function()
                    tm2:set_field("_IsReqRefresh", false)
                    tm2:set_field("_TrainingState", 1)
                end)
            end
        end
    end

   -- Delayed restore
    if _pending_restore > 0 then
        _pending_restore = _pending_restore - 1
        if _pending_restore == 0 then
            dbg("apply_restore step=" .. tostring(_trial_snapshot and _trial_snapshot.step or "nil"))
            apply_restore()
        end
    end
end)

-- =========================================================
-- DEMO ENGINE INJECTION HOOKS (Stack-based Player ID tracking)
-- =========================================================
local bf_type = sdk.find_type_definition("app.BattleFlow")
if bf_type then
    local method = bf_type:get_method("UpdateFrameMain")
    if method then
        sdk.hook(method, function(args)
            tick_done_this_frame = false
            p_id_stack = {}
        end, function(retval) return retval end)
    end
end

-- Register with shared pl_input_sub hook (0_SharedHooks.lua)
if _G._shared_input_pre then
table.insert(_G._shared_input_pre, function(p_id, args)
    if not RuntimeSafety.is_training_allowed() then return end
    if not tick_done_this_frame and demo_state.is_playing then
        if not trial_state.is_playing then
            demo_state.is_playing = false
            demo_state.p1_mask = 0
            demo_state._last_tick_frame = nil
        else
            local pm = sdk.get_managed_singleton("app.PauseManager")
            local is_paused = false
            if pm then
                local b = pm:get_field("_CurrentPauseTypeBit")
                if b ~= 64 and b ~= 2112 then is_paused = true end
            end
            local is_refreshing = false
            local tm = sdk.get_managed_singleton("app.training.TrainingManager")
            if tm and tm:get_field("_IsReqRefresh") == true then is_refreshing = true end
            if trial_state.pending_exact_pos and trial_state.pending_exact_pos > 0 then is_refreshing = true end

            if not is_paused and not is_refreshing then
                if demo_state.countdown and demo_state.countdown > 0 then
                    demo_state.countdown = demo_state.countdown - 1
                    demo_state.p1_mask = 0
                    demo_state._last_tick_frame = nil
                else
                    CTStunDemoRuntime.catch_up_missed_engine_frames()
                    local step = demo_state.sequence[demo_state.current_step]
                    if step then
                        if demo_state.current_step == 1
                            and demo_state.current_frame == 0
                            and demo_state._state_reinjected ~= true then
                            CTStunDemoRuntime.restore_pre_demo_state()
                            demo_state._state_reinjected = true
                        end
                        demo_state.p1_mask = step.mask
                        CTStunDemoRuntime.advance_timeline_frames(1)
                        demo_state._last_tick_frame = engine_frame_count or 0
                    else
                        demo_state.current_step = 1
                        demo_state.current_frame = 0
                        demo_state.countdown = 10
                        demo_state.p1_mask = 0
                        demo_state._last_tick_frame = nil
                        demo_state._state_reinjected = false
                        reset_trial_steps()
                    end
                end
            else
                demo_state.p1_mask = 0
                demo_state._last_tick_frame = nil
            end
        end
        tick_done_this_frame = true
    end
end)

end
local function _ct_clear_inputs(idx)
    local p1 = _td_gBattle:get_field("Player"):get_data(nil).mcPlayer[idx]
    if p1 then p1:set_field("pl_input_new", 0); p1:set_field("pl_sw_new", 0) end
end

local function _ct_demo_inject_mask()
    local p1 = _td_gBattle:get_field("Player"):get_data(nil).mcPlayer[0]
    local final_mask = demo_state.p1_mask
    if not p1:get_field("rl_dir") then
        local has_right = (final_mask & 4) ~= 0
        local has_left  = (final_mask & 8) ~= 0
        final_mask = final_mask & ~12
        if has_right then final_mask = final_mask | 8 end
        if has_left  then final_mask = final_mask | 4 end
    end
    local orig_in = p1:get_field("pl_input_new") or 0
    local orig_sw = p1:get_field("pl_sw_new") or 0
    p1:set_field("pl_input_new", orig_in | final_mask)
    p1:set_field("pl_sw_new", orig_sw | final_mask)
end

if _G._shared_input_post then
table.insert(_G._shared_input_post, function(p_id, retval)
    if not RuntimeSafety.is_training_allowed() then return end
    if p_id == 0 and demo_state.is_playing and demo_state.p1_mask > 0 then
        pcall(_ct_demo_inject_mask)
    end
end)
end

