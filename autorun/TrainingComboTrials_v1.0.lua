local sdk = sdk
local imgui = imgui
local re = re
local json = json
require("func/SharedHooks")
local SF6CCVersion = require("func/SF6CC_Version")
local RuntimeSafety = require("func/RuntimeSafety")
local GS = require("func/GameState")
local ComboTrialsModules = {
    DebugTrace = require("func/ComboTrials/DebugTrace"),
    ActionCompatibility = require("func/ComboTrials/ActionCompatibility"),
    ActionMatcher = require("func/ComboTrials/ActionMatcher"),
    ActionRestartDetector = require("func/ComboTrials/ActionRestartDetector"),
    CharacterRules = require("func/ComboTrials/CharacterRules"),
    SequenceGrouping = require("func/ComboTrials/SequenceGrouping"),
    Validator = require("func/ComboTrials/Validator"),
    TrainingEnvironment = require("func/ComboTrials/TrainingEnvironment"),
    SceneState = require("func/ComboTrials/SceneState"),
    SceneStateRuntime = require("func/ComboTrials/SceneStateRuntime"),
    PendingAbsorb = require("func/ComboTrials/PendingAbsorb"),
    Telemetry = require("func/ComboTrials/Telemetry"),
    CommandResolver = require("func/ComboTrials/CommandResolver"),
    ActionEventCompiler = require("func/ComboTrials/ActionEventCompiler"),
    RawInputCodec = require("func/ComboTrials/RawInputCodec"),
    Transcriber = require("func/ComboTrials/Transcriber"),
    RuntimeAuditor = require("func/ComboTrials/RuntimeAuditor"),
    TimelineSequenceNormalizer = require("func/ComboTrials/TimelineSequenceNormalizer"),
    DummySettings = require("func/ComboTrials/DummySettings"),
    GameProbe = require("func/ComboTrials/GameProbe")
}
local DebugTrace = ComboTrialsModules.DebugTrace
local ActionMatcher = ComboTrialsModules.ActionMatcher
local ActionRestartDetector = ComboTrialsModules.ActionRestartDetector
local CharacterRules = ComboTrialsModules.CharacterRules
local RawInputCodec = ComboTrialsModules.RawInputCodec
local SequenceGrouping = ComboTrialsModules.SequenceGrouping
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
local INPUT_DIR_MAP = {
    [0] = "5",
    [1] = "8",
    [2] = "2",
    [4] = "6",
    [8] = "4",
    [5] = "9",
    [6] = "3",
    [9] = "7",
    [10] = "1",
    [15] = "*"
}
local ComboTrials_Renderer

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
    ["ESF_032"] = "Ingrid",
    ["ESF_033"] = "Yasmine"
}


local common_exceptions = CharacterRules.load_common()

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
    },
    [33] = {
        name = "Yasmine",
        resources = {
            { id = "timer_0_033", kind = "timer", min = 0, max = 2 },
            { id = "stock_0_033", kind = "stock", min = 0, max = 1, allow_infinite = true }
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
    return ActionMatcher.is_drive_rush_action_id(act_id)
end

local function is_drive_rush_motion(motion)
    return ActionMatcher.is_drive_rush_motion(motion)
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
        buffer_combo_count = 0,
        trigger_mask_cache = {}, trigger_cache_built = false,
        last_bcm_ptr = "", last_direct_input = 0, last_direction_input = 0,
        input_history_queue = {}, dash_tap_state = {},
        profile_name = "Unknown", last_profile_name = "", exceptions = {},
        action_compatibility = nil,
        action_event_rules = {}, sequence_grouping_rules = {},
        editing_id = -1, edit_ignore = false, edit_force = false,
		edit_is_common = false, edit_holdable = false, edit_absorb_ids = "",
        edit_charge_min = "", edit_charge_max = "", enable_deep_logging = false,
        edit_ignore_prev_id = "", edit_ignore_prev_frames = "5"
    },
    [1] = {
        log = {}, prev_act_id = -1, prev_act_frame = -1, last_combo_count = 0,
        action_instance_counter = 0, current_action_instance = 0, buffer_action_instance = 0,
        buffer_combo_count = 0,
        trigger_mask_cache = {}, trigger_cache_built = false,
        last_bcm_ptr = "", last_direct_input = 0, last_direction_input = 0,
        input_history_queue = {}, dash_tap_state = {},
        profile_name = "Unknown", last_profile_name = "", exceptions = {},
        action_compatibility = nil,
        action_event_rules = {}, sequence_grouping_rules = {},
        editing_id = -1, edit_ignore = false, edit_force = false,
		edit_is_common = false, edit_holdable = false, edit_absorb_ids = "",
        edit_charge_min = "", edit_charge_max = "", enable_deep_logging = false,
        edit_ignore_prev_id = "", edit_ignore_prev_frames = "5"
    }
}

-- GLOBAL COMBO TRIAL STATE
local trial_state = {
    is_recording = false,
    recording_player = 0,
    recording_display_context = nil,
    recording_display_session_id = 0,
    live_display_contexts = {},
    live_display_generation = 0,
    unresolved_action_audit = nil,
    unresolved_action_audit_session = 0,
    is_playing = false,
    playing_player = 0,
    sequence = {},
    _recording_preview_sequence = {},
    _recording_preview_logs = {},
    _recording_preview_signature = nil,
    _recording_preview_error = nil,
    current_step = 1,
    success_timer = 0,
    _success_latched = false,
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
    _rec_gauges = nil,     -- Internal gauge sample at recording start
    _rec_hit_type = nil,   -- Derived from the fixed recorded counter-menu value
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
    _demo_backup_slot = nil,
    _raw_rec_active = false,
    -- Stored facing-relative; the legacy name remains runtime-local only.
    _raw_rec_buffer = {}
}

local XT_SETTINGS_FILE = "TrainingComboTrials_data/XT_Settings.json"
CTJsonInterop = CTJsonInterop or {}
CTJsonInterop.RECORDER_VERSION = SF6CCVersion.PRODUCT_VERSION
local xt_settings = {
    default_author = "佚名",
    language = "zh-CN"
}

local function load_xt_settings()
    if type(_G.safe_load_json) ~= "function" then return end
    local ok, loaded = pcall(_G.safe_load_json, XT_SETTINGS_FILE)
    if not ok then return end
    if type(loaded) == "table" then
        if type(loaded.default_author) == "string" and loaded.default_author ~= "" then
            xt_settings.default_author = loaded.default_author
        end
        if type(loaded.language) == "string" and loaded.language ~= "" then
            xt_settings.language = loaded.language
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
    input_type = tonumber(input_type)
    if input_type == 1 then return "modern" end
    if input_type == 0 then return "classic" end
    return "unknown"
end

local function invalidate_recording_display_context()
    local context = trial_state.recording_display_context
    if type(context) == "table" then context.active = false end
    trial_state.recording_display_context = nil
end

local live_display_context = {}

function live_display_context.next_generation()
    trial_state.live_display_generation = (tonumber(trial_state.live_display_generation) or 0) + 1
    return trial_state.live_display_generation
end

function live_display_context.invalidate()
    local contexts = trial_state.live_display_contexts
    if type(contexts) == "table" then
        for _, context in pairs(contexts) do
            if type(context) == "table" then context.active = false end
        end
    end
    trial_state.live_display_contexts = {}
end

function live_display_context.set(player_idx, character, input_type, control_type)
    if player_idx ~= 0 and player_idx ~= 1 then return nil end
    if type(trial_state.live_display_contexts) ~= "table" then
        trial_state.live_display_contexts = {}
    end
    if type(character) ~= "string" or character == "" then character = "Unknown" end
    control_type = tostring(control_type or control_type_from_input_type(input_type)):lower()
    if control_type ~= "modern" and control_type ~= "classic" then control_type = "unknown" end
    local context = {
        active = true,
        player_idx = player_idx,
        character = character,
        input_type = input_type ~= nil and input_type or "unknown",
        control_mode = control_type,
        control_type = control_type,
        generation = live_display_context.next_generation()
    }
    trial_state.live_display_contexts[player_idx] = context
    return context
end

function live_display_context.refresh(player_idx)
    local character = players[player_idx] and players[player_idx].profile_name or "Unknown"
    local input_type = read_player_input_type(player_idx)
    return live_display_context.set(player_idx, character, input_type, control_type_from_input_type(input_type))
end

function live_display_context.refresh_all()
    live_display_context.refresh(0)
    live_display_context.refresh(1)
end

function live_display_context.ensure()
    local contexts = trial_state.live_display_contexts
    if type(contexts) ~= "table" or type(contexts[0]) ~= "table" then
        live_display_context.refresh(0)
    end
    contexts = trial_state.live_display_contexts
    if type(contexts) ~= "table" or type(contexts[1]) ~= "table" then
        live_display_context.refresh(1)
    end
end

function live_display_context.sync_recording()
    local context = trial_state.recording_display_context
    if type(context) ~= "table" or context.active ~= true then return nil end
    return live_display_context.set(
        context.recording_player,
        context.character,
        context.input_type,
        context.control_mode or context.control_type
    )
end

local function begin_recording_display_context(player_idx)
    invalidate_recording_display_context()
    trial_state.recording_display_session_id = (tonumber(trial_state.recording_display_session_id) or 0) + 1
    local input_type = read_player_input_type(player_idx)
    local control_type = control_type_from_input_type(input_type)
    local frozen_input_type = input_type ~= nil and input_type or "unknown"
    local character = players[player_idx] and players[player_idx].profile_name or "Unknown"
    if type(character) ~= "string" or character == "" then character = "Unknown" end
    trial_state.recording_display_context = {
        active = true,
        recording_player = player_idx,
        character = character,
        input_type = frozen_input_type,
        control_mode = control_type,
        control_type = control_type,
        session_id = trial_state.recording_display_session_id
    }
end

function CTJsonInterop.iso8601_now()
    local now = os.time()
    local timezone = os.date("%z", now) or ""
    if timezone:match("^[+-]%d%d%d%d$") then
        timezone = timezone:sub(1, 3) .. ":" .. timezone:sub(4)
    else
        local utc = os.date("!*t", now)
        local local_time = os.date("*t", now)
        utc.isdst = local_time.isdst
        local offset = math.floor(os.difftime(os.time(local_time), os.time(utc)))
        local sign = offset < 0 and "-" or "+"
        offset = math.abs(offset)
        timezone = string.format("%s%02d:%02d", sign, math.floor(offset / 3600), math.floor((offset % 3600) / 60))
    end
    return os.date("%Y-%m-%dT%H:%M:%S", now) .. timezone
end

function CTJsonInterop.sequence_control_mode(sequence)
    local first = type(sequence) == "table" and sequence[1] or nil
    local meta = type(first) == "table" and first._xt_meta or nil
    if type(meta) ~= "table" then return "classic" end
    local mode = tostring(meta.control_mode or meta.control_type or meta.timeline_input_profile or "classic"):lower()
    return mode == "modern" and "modern" or "classic"
end

function CTJsonInterop.warn_control_mode_mismatch(sequence, player_idx, allow_classic_in_modern)
    local file_mode = CTJsonInterop.sequence_control_mode(sequence)
    local live_mode = control_type_from_input_type(read_player_input_type(player_idx or 0))
    if file_mode == live_mode then return false end
    if allow_classic_in_modern == true and file_mode == "classic" and live_mode == "modern" then
        return false
    end
    local message = string.format("控制模式不一致：配置为%s，当前为%s", file_mode, live_mode)
    if type(_G.show_custom_ticker) == "function" then
        pcall(_G.show_custom_ticker, message, 0.3)
    else
        pcall(print, "[ComboTrials] " .. message)
    end
    return true
end

local function build_auto_xt_meta(recording_player, sequence)
    if not SF6CCVersion.loaded then
        error("无法写入连段版本信息：" .. tostring(SF6CCVersion.error or "产品版本未知"))
    end
    local player_idx = recording_player or trial_state.recording_player or 0
    local recording_context = trial_state.recording_display_context
    if type(recording_context) ~= "table" or recording_context.active ~= true
        or recording_context.recording_player ~= player_idx
        or recording_context.session_id ~= trial_state.recording_display_session_id then
        recording_context = nil
    end
    local input_type = recording_context and recording_context.input_type or nil
    local control_type = recording_context and (recording_context.control_mode or recording_context.control_type)
        or "unknown"
    control_type = tostring(control_type or "unknown"):lower()
    if control_type ~= "modern" and control_type ~= "classic" then control_type = "unknown" end
    local character = recording_context and recording_context.character
    if type(character) ~= "string" or character == "" then
        character = "Unknown"
    end
    local now = CTJsonInterop.iso8601_now()
    local step_notes = {}
    for index = 1, (type(sequence) == "table" and #sequence or 0) do
        step_notes[index] = ""
    end
    return {
        title = "",
        note = "",
        author = xt_settings.default_author or "佚名",
        tags = {},
        step_notes = step_notes,
        language = xt_settings.language or "zh-CN",
        control_mode = control_type,
        created_at = now,
        updated_at = now,
        versions = {
            game = {
                id = SF6CCVersion.GAME_ID,
                version = SF6CCVersion.GAME_VERSION
            },
            recorder = {
                id = SF6CCVersion.PRODUCT_ID,
                version = CTJsonInterop.RECORDER_VERSION
            },
            json = {
                id = SF6CCVersion.COMBO_JSON_ID,
                version = SF6CCVersion.COMBO_JSON_VERSION
            }
        },
        schema = SF6CCVersion.COMBO_JSON_SCHEMA,
        -- Legacy aliases retained so pre-v2 SF6CC readers keep filtering correctly.
        control_type = control_type,
        timeline_input_profile = control_type,
        input_type = input_type,
        character = character
    }
end

load_xt_settings()

_G.CTRecordingRepeat = _G.CTRecordingRepeat or {}

function _G.CTRecordingRepeat.read_live_counter_type(victim_obj)
    if not victim_obj then return 0 end
    local pc = victim_obj:get_type_definition():get_field("counter_fw_flag"):get_data(victim_obj)
    local ch = victim_obj:get_type_definition():get_field("counter_dm_flag"):get_data(victim_obj)
    if pc == true then return 2 end
    if ch == true then return 1 end
    return 0
end

function _G.CTRecordingRepeat.read_live_damage_type(player_obj)
    if not player_obj then return 0 end
    local raw_value = player_obj:get_field("damage_type")
    return tonumber(raw_value) or tonumber(tostring(raw_value)) or 0
end

function _G.CTRecordingRepeat.read_live_hit_stop(player_obj)
    if not player_obj then return 0 end
    local raw_value = player_obj:get_field("hit_stop")
    return tonumber(raw_value) or tonumber(tostring(raw_value)) or 0
end

-- =========================================================
-- DEMO ENGINE STATE
-- =========================================================
local demo_state = {
    is_playing = false,
    current_frame = 0,
    current_step = 1,
    sequence = {},
    p1_mask = 0,
    raw_buffer = nil,
    raw_input_source = nil,
    play_index = 1,
    auto_playlist_enabled = false,
    playlist_active = false,
    playlist_index = 0,
    playlist_total = 0,
    playlist_pending_next = false,
    playlist_loading = false
}
demo_state.transcription_run = nil
demo_state.mark_transcription_input_finished = function()
    local run = demo_state.transcription_run
    if not run or run.active ~= true
        or run.input_finished_frame ~= nil then
        return false
    end
    run.input_finished_frame = engine_frame_count
    run.status = "等待末尾命中结算"
    demo_state._transcription_input_finished = true
    demo_state.p1_mask = 0
    return true
end

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
    saved_combos_info_p1 = {},
    saved_combos_paths_p1 = {},
    saved_combos_control_p1 = {},
    saved_combos_all_display_p1 = {},
    saved_combos_all_info_p1 = {},
    saved_combos_all_paths_p1 = {},
    saved_combos_all_control_p1 = {},
    skipped_combos_p1 = 0,
    selected_file_idx_p1 = 1,

    saved_combos_display_p2 = {},
    saved_combos_info_p2 = {},
    saved_combos_paths_p2 = {},
    saved_combos_control_p2 = {},
    saved_combos_all_display_p2 = {},
    saved_combos_all_info_p2 = {},
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
    combo_list_character_p1 = nil,
    combo_list_character_p2 = nil,
    combo_list_cached_filter = nil,
    combo_list_cached_effective_filter = nil,
    combo_list_pending_save_refreshed = false,
    combo_list_refresh_pending = false,
    combo_list_refresh_pending_reload = false,
    combo_list_refresh_pending_reason = nil,
    combo_list_refresh_deferred_logged = false,
    combo_list_last_signature = nil,
    combo_list_signature_warn_counter = 0,
    combo_idle_prewarm_key = nil,
    combo_idle_prewarm_stage = 0,
    combo_idle_prewarm_delay = 0,
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
-- IMGUI VISUALIZER CONFIGURATION
-- =========================================================
local RENDER_CONFIG_FILE = "TrainingComboTrials_data/CommandLogger_Visualizer.json"
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
    show_combo_count = false,
    show_unresolved_action_ids = false,
    modern_display_mode = "simple",
    allow_classic_trials_in_modern = false,
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
    show_trial_notes = true,
    auto_next_trial = false,    -- after a manual success: auto-load the next combo in the list
    auto_retry_on_fail = false, -- after the fail banner ends: auto-reset the trial (no manual reset needed)
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
    local loaded = _G.safe_load_json(RENDER_CONFIG_FILE)
    if loaded then
        for k, v in pairs(loaded) do
            if type(v) == "table" and type(d2d_cfg[k]) == "table" then
                for k2, v2 in pairs(v) do d2d_cfg[k][k2] = v2 end
            else
                d2d_cfg[k] = v
            end
        end
        -- 0.99 以前该开关只用于现代模式。保留用户旧值，但统一迁移到
        -- 经典/现代共用的未识别 Action ID 调试开关。
        if loaded.show_unresolved_action_ids == nil and loaded.show_modern_unresolved_ids ~= nil then
            d2d_cfg.show_unresolved_action_ids = loaded.show_modern_unresolved_ids == true
        end
        d2d_cfg.show_modern_unresolved_ids = nil
    end
end

local function save_d2d_config()
    return json.dump_file(RENDER_CONFIG_FILE, d2d_cfg)
end
load_d2d_config()
d2d_cfg.show_combo_count = false
if d2d_cfg.modern_display_mode ~= "simple"
    and d2d_cfg.modern_display_mode ~= "motion"
    and d2d_cfg.modern_display_mode ~= "all" then
    d2d_cfg.modern_display_mode = "simple"
end
d2d_cfg.allow_classic_trials_in_modern = d2d_cfg.allow_classic_trials_in_modern == true

-- =========================================================
-- COMPLETED TRIALS TRACKING (runtime file, not committed)
-- Keep state on file_system to avoid adding main-chunk locals.
-- =========================================================
file_system.completed_trials = file_system.completed_trials or {}
file_system.completed_trials_store = require("func/RecoverableJsonFile").new(
    "TrainingComboTrials_data/CompletedTrials.json",
    "TrainingComboTrials_data/CompletedTrials.recovery.json"
)

file_system.completed_trial_key = function(path)
    return (tostring(path or ""):gsub("\\", "/")):lower()
end

file_system.save_completed_trials = function()
    return file_system.completed_trials_store:save(file_system.completed_trials)
end

file_system.is_trial_completed = function(path)
    local key = file_system.completed_trial_key(path)
    return key ~= "" and file_system.completed_trials[key] == true
end

file_system.mark_trial_completed = function(path)
    local key = file_system.completed_trial_key(path)
    if key == "" or file_system.completed_trials[key] then return false end
    file_system.completed_trials[key] = true
    file_system.save_completed_trials()
    return true
end

file_system.clear_completed_trials = function()
    file_system.completed_trials = {}
    file_system.save_completed_trials()
end

pcall(function()
    local loaded = file_system.completed_trials_store:load({})
    if type(loaded) ~= "table" then return end
    for key, value in pairs(loaded) do
        if type(key) == "string" and value then file_system.completed_trials[key] = true end
    end
end)


-- =========================================================
-- SHARED CONTEXT & IMGUI RENDERER
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

ctx.stop_demo_playback = function(reason, old_file, new_file, stop_trial, keep_playlist)
    if not demo_state then return end
    local old_sequence_len = (type(demo_state.sequence) == "table") and #demo_state.sequence or 0
    local old_raw_len = (type(demo_state.raw_buffer) == "table") and #demo_state.raw_buffer or 0
    local was_playing = demo_state.is_playing == true
    local old_play_index = demo_state.current_step or 1
    local old_frame = demo_state.current_frame or 0
    local had_demo_state = was_playing
        or old_sequence_len > 0
        or old_raw_len > 0
        or (demo_state.p1_mask or 0) ~= 0
        or demo_state.playlist_active == true
        or demo_state.playlist_pending_next == true
    if not had_demo_state then return end

    -- A user may stop after watching only the useful part of a demo. Explicit
    -- stops, trial changes and scene cleanup are cancellations, never failures.
    ComboTrialsModules.Telemetry.cancel_attempt()

    demo_state.is_playing = false
    trial_state._demo_timing_ui_baseline = false
    demo_state.current_frame = 0
    demo_state.current_step = 1
    demo_state.countdown = 0
    demo_state.sequence = {}
    demo_state.p1_mask = 0
    demo_state.raw_buffer = nil
    demo_state.raw_input_source = nil
    demo_state.play_index = 1
    demo_state._last_tick_frame = nil
    demo_state._state_reinjected = false
    demo_state._total_frames = 0
    demo_state._piyo_waiting = false
    demo_state._piyo_triggered = false
    demo_state.transcribing = false
    demo_state._transcription_input_finished = false
    demo_state._transcription_capture_frame = false
    demo_state.current_file = nil
    demo_state.current_file_path = nil
    demo_state.current_file_name = nil
    if keep_playlist ~= true then
        demo_state.playlist_active = false
        demo_state.playlist_index = 0
        demo_state.playlist_total = 0
        demo_state.playlist_pending_next = false
        demo_state.playlist_loading = false
    end

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
            tostring(old_sequence_len > 0 or old_raw_len > 0)
        ))
    end
end

ctx.on_combo_file_change = function(info)
    if demo_state and demo_state.playlist_loading == true then return end
    info = info or {}
    local old_file = info.old_file or trial_state.current_file_path or trial_state.current_file
    local new_file = info.new_file
    local reason = info.reason or "trial_changed"
    local same_file = old_file and new_file and tostring(old_file) == tostring(new_file)
    if same_file and reason == "trial_changed" and info.force ~= true then return end
    ctx.stop_demo_playback(reason, old_file, new_file, true)
end

if type(package.loaded["func/ComboTrials_ImGui"]) == "table"
    and type(package.loaded["func/ComboTrials_ImGui"].clear_command_display_cache) ~= "function" then
    package.loaded["func/ComboTrials_ImGui"] = nil
end
ComboTrials_Renderer = require("func/ComboTrials_ImGui")
ComboTrials_Renderer.init(ctx)
ctx.combo_renderer = ComboTrials_Renderer

-- Pure ImGui rendering is implemented by ComboTrials_ImGui.lua.

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

ComboTrialsModules.GameProbe.init({
    g_battle_type = _td_gBattle,
    players = players,
})

local function get_exc_filename(name)
    return CharacterRules.get_exception_filename(name)
end

local function auto_detect_charge_min(p_char)
    local min_frame = nil
    pcall(function()
        local engine = p_char:get_field("mpActParam"):get_field("ActionPart"):get_field("_Engine")
        local keys_obj = engine:get_field("mParam"):get_field("action"):get_field("Keys")

        local groups = ComboTrialsModules.GameProbe.get_elements_safe(keys_obj)
        if groups then
            for _, group in ipairs(groups) do
                local keys = ComboTrialsModules.GameProbe.get_elements_safe(group)
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

        local groups = ComboTrialsModules.GameProbe.get_elements_safe(keys_obj)
        if groups then
            local frames_by_act = {}
            for _, group in ipairs(groups) do
                local keys = ComboTrialsModules.GameProbe.get_elements_safe(group)
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

SUPER_SETTING_FIELDS = {
    "SA_Type",
    "SA_Stock",
    "SA_Point",
    "Is_SA_Point_Lock",
    "Is_SA_No_Recovery",
    "Is_SA_Recovery_Timer",
    "SA_Timer"
}

function restore_trial_vital(skip_hp_setting_restore)
    clear_trial_vital_state()
    if skip_hp_setting_restore ~= true and type(restore_hp_training_setting_if_needed) == "function" then
        restore_hp_training_setting_if_needed("restore_trial_vital", trial_state.playing_player)
    end

    local saved_drive_settings = trial_state._saved_drive_settings
    local saved_super_settings = trial_state._saved_super_settings
    local tm = sdk.get_managed_singleton("app.training.TrainingManager")
    local changed = false
    local t_data = tm and tm:get_field("_tData")
    local parameter_setting = t_data and t_data:get_field("ParameterSetting")
    local player_datas = parameter_setting and parameter_setting.PlayerDatas

    if player_datas then
        for idx, settings in pairs(type(saved_drive_settings) == "table" and saved_drive_settings or {}) do
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

        for idx, settings in pairs(type(saved_super_settings) == "table" and saved_super_settings or {}) do
            local params = player_datas[idx]
            if params and type(settings) == "table" then
                for _, field_name in ipairs(SUPER_SETTING_FIELDS) do
                    if settings[field_name] ~= nil then
                        params[field_name] = settings[field_name]
                        changed = true
                    end
                end
            end
        end
    end

    trial_state._saved_drive_settings = nil
    trial_state._saved_super_settings = nil
    if changed then tm._IsReqRefresh = true end
    ComboTrialsModules.SceneStateRuntime.restore_live_resources(trial_state)
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
    local read_snapshot, read_skip_reason = read_actor_scene_hp()
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
            first_scene_state = type(first) == "table" and first.scene_state or nil
        },
        playing_player = trial_state.playing_player,
        current_step = trial_state.current_step,
        pending_reinject_settings = trial_state._pending_reinject_settings == true,
        tm_is_req_refresh = tm and tm:get_field("_IsReqRefresh") or nil,
        first_scene_state = type(first) == "table" and first.scene_state or nil,
        read_actor_scene_hp = {
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

function read_actor_scene_hp()
    local first = trial_state.sequence and trial_state.sequence[1]
    if type(first) ~= "table" then return nil, "missing_first_step" end

    local roles = ComboTrialsModules.SceneState.resolve_roles(first, trial_state.playing_player)
    local resources = roles and ComboTrialsModules.SceneState.resources(roles.actor) or nil
    local current_hp = normalize_hp_value(resources and resources.hp)
    if current_hp == nil then return nil, "missing_actor_scene_hp" end

    local target = roles.actor.player_index == 1 and GS.p2 or GS.p1
    local max_hp = nil
    pcall(function() max_hp = normalize_hp_value(target and target.vital_max) end)
    local snapshot = {
        current_hp = current_hp,
        heal_hp = current_hp
    }
    if max_hp and max_hp > 0 then snapshot.max_hp = max_hp end
    return snapshot, nil
end

function init_hp_restore_attempt(phase, player_idx)
    trial_state._hp_restore_token = (trial_state._hp_restore_token or 0) + 1
    local snapshot, skip_reason = read_actor_scene_hp()
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

ComboTrialsModules.DummySettings.init(trial_state)
CT_COUNTER_RUNTIME_FIELDS = ComboTrialsModules.DummySettings.COUNTER_RUNTIME_FIELDS
CT_GUARD_RUNTIME_FIELDS = ComboTrialsModules.DummySettings.GUARD_RUNTIME_FIELDS
CT_DUMMY_ACTION_RUNTIME_FIELDS = ComboTrialsModules.DummySettings.DUMMY_ACTION_RUNTIME_FIELDS
CT_TRIAL_DEFENSE_FIELDS = ComboTrialsModules.DummySettings.TRIAL_DEFENSE_FIELDS
ct_read_dummy_counter_settings = ComboTrialsModules.DummySettings.read_counter_settings
ct_read_dummy_guard_settings = ComboTrialsModules.DummySettings.read_guard_settings
ct_read_dummy_action_settings = ComboTrialsModules.DummySettings.read_action_settings
ct_get_tf_defense_system = ComboTrialsModules.DummySettings.get_tf_defense_system
ct_get_trial_defense_objects = ComboTrialsModules.DummySettings.get_trial_defense_objects
ct_copy_trial_defense_fields = ComboTrialsModules.DummySettings.copy_trial_defense_fields
ct_capture_training_defense_environment = ComboTrialsModules.DummySettings.capture_training_defense_environment
ct_write_trial_defense_fields = ComboTrialsModules.DummySettings.write_trial_defense_fields
ct_backup_trial_defense_settings = ComboTrialsModules.DummySettings.backup_trial_defense_settings
restore_trial_defense_settings = ComboTrialsModules.DummySettings.restore_trial_defense_settings
apply_trial_defense_cleanup = ComboTrialsModules.DummySettings.apply_trial_defense_cleanup
ct_apply_recorded_defense_settings = ComboTrialsModules.DummySettings.apply_recorded_defense_settings
ct_trial_dummy_guard_type = ComboTrialsModules.DummySettings.trial_dummy_guard_type
ct_trial_dummy_guard_count = ComboTrialsModules.DummySettings.trial_dummy_guard_count
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
    local players_state = unique_resources.capture_by_side() or {}

    for player_idx = 0, 1 do
        local side_key = player_idx == 0 and "p1" or "p2"
        local side = players_state[side_key] or {}
        if side.fighter_id == nil then
            side.fighter_id = unique_resources.read_training_fighter_id(player_idx)
        end

        pcall(function()
            local player = player_idx == 0 and GS.p1 or GS.p2
            if not player then return end

            local super = 0
            pcall(function()
                local battle_team = _td_gBattle:get_field("Team"):get_data(nil)
                local team = battle_team and battle_team.mcTeam and battle_team.mcTeam[player_idx]
                super = team and tonumber(team.mSuperGauge) or 0
            end)

            side.resources = {
                hp = tonumber(player.vital_new) or 0,
                drive = tonumber(player.focus_new) or 0,
                super = super
            }

            local pose = tonumber(tostring(player:get_field("pose_st"))) or 0
            local stance = "standing"
            if pose == 1 then
                stance = "crouching"
            elseif pose == 2 then
                stance = "airborne"
            end

            local stunned = false
            pcall(function()
                local engine = player.mpActParam.ActionPart._Engine
                local action_id = engine and engine:get_ActionID()
                stunned = action_id == 293 or action_id == 294
            end)

            local burnout = false
            pcall(function()
                local tm = sdk.get_managed_singleton("app.training.TrainingManager")
                local training_data = tm and tm:get_field("_tData")
                local parameter_setting = training_data and training_data:get_field("ParameterSetting")
                local params = parameter_setting and parameter_setting.PlayerDatas and parameter_setting.PlayerDatas[player_idx]
                if params then
                    burnout = params.Is_DG_Break == true or params.Is_DG_Break == 1
                end
            end)

            side.status = {
                burnout = burnout,
                stunned = stunned,
                stance = stance
            }
        end)

        players_state[side_key] = side
    end

    return {
        schema = "xt.combo_trial.scene.v2",
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

function unique_resources.dedupe_shared_entries(entries)
    local out = {}
    local index_by_resource = {}
    local priority_by_resource = {}

    for _, entry in ipairs(type(entries) == "table" and entries or {}) do
        local resource_id = entry.resource_id
        if resource_id ~= nil then
            local priority = entry.source == "scene_state" and 2 or 1
            local index = index_by_resource[resource_id]
            if index == nil then
                out[#out + 1] = entry
                index_by_resource[resource_id] = #out
                priority_by_resource[resource_id] = priority
            elseif priority >= (priority_by_resource[resource_id] or 0) then
                -- UniqueData is shared. Within the same source, entries are
                -- ordered defender first and recorded actor last, so the
                -- actor wins a legacy same-character conflict.
                out[index] = entry
                priority_by_resource[resource_id] = priority
            end
        end
    end

    return out
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
    return unique_resources.dedupe_shared_entries(entries)
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
    local action_settings = ct_read_dummy_action_settings()
    local action_type = tonumber(action_settings.action_type) or ComboTrialsModules.DummySettings.DUMMY_ACTION_STAND
    local jump_type = tonumber(action_settings.jump_type)
        or ComboTrialsModules.TrainingEnvironment.DUMMY_JUMP.VERTICAL
    local stance = action_type == ComboTrialsModules.DummySettings.DUMMY_ACTION_CROUCH and "crouch"
        or (action_type == ComboTrialsModules.TrainingEnvironment.DUMMY_ACTION.JUMP and "jump")
        or (action_type == ComboTrialsModules.DummySettings.DUMMY_ACTION_STAND and "stand")
        or nil
    local counter_settings = ct_read_dummy_counter_settings()
    local guard_settings = ct_read_dummy_guard_settings()
    local guard_type = guard_settings.guard_type
    local guard_count = guard_settings.guard_count
    local env = {
        schema = "xt.training_environment.v1",
        dummy_action_type = action_type,
        dummy_jump_type = jump_type,
        dummy_stance = stance,
        dummy_jump_weight_front = action_settings.JumpWeight_Front,
        dummy_jump_weight_vertical = action_settings.JumpWeight_Virtical,
        dummy_jump_weight_back = action_settings.JumpWeight_Back,
        dummy_cpu_level =
            ComboTrialsModules.TrainingEnvironment.cpu_level_from_runtime(
                action_settings.CpuLevel
            ),
        dummy_counter_type = counter_settings.counter_type,
        dummy_counter_weight_normal = counter_settings.NH_Weight,
        dummy_counter_weight_counter = counter_settings.NC_Weight,
        dummy_counter_weight_punish = counter_settings.PC_Weight,
        dummy_guard_type = guard_type,
        dummy_guard_switching = guard_settings.IsGuardSwitching,
        dummy_guard_weight = guard_settings.GuardWeight,
        dummy_guard_only_type = guard_settings.GuardOnlyType,
    }
    if guard_type == ComboTrialsModules.TrainingEnvironment.DUMMY_GUARD.COUNT then
        env.dummy_guard_count = guard_count
    end
    ct_capture_training_defense_environment(env)
    local players_state = unique_resources.capture_by_side()
    if players_state then
        env.players = players_state
        env.unique = players_state
    end
    return env
end

local function value_requests_dummy_crouch(value)
    if type(value) == "boolean" then return value end
    if type(value) == "number" then return value == ComboTrialsModules.DummySettings.DUMMY_ACTION_CROUCH end
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
    if tonumber(env.dummy_action_type) == ComboTrialsModules.DummySettings.DUMMY_ACTION_CROUCH then return true end
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
    for _, field_name in ipairs(ComboTrialsModules.TrainingEnvironment.OPTIONAL_FIELDS) do
        meta[field_name] = env[field_name]
    end

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

    local scene_state = type(first.scene_state) == "table" and first.scene_state or nil
    if scene_state and type(scene_state.players) == "table" then
        local recorded_by = tonumber(first.recorded_by or scene_state.recorded_by or 0) or 0
        local defender_side = recorded_by == 1 and "p1" or "p2"
        local defender = scene_state.players[defender_side]
        local status = type(defender) == "table" and defender.status or nil
        if type(status) == "table" and value_requests_dummy_crouch(status.stance) then return true end
    end

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

local function apply_trial_training_environment(skip_refresh_settings)
    local apply_refresh_settings = skip_refresh_settings ~= true
    -- Training refresh can rebuild UniqueData. Reapply recorded character
    -- resources during the existing post-refresh pass, but do not request a
    -- second refresh that would immediately clear them again.
    unique_resources.apply_recorded()
    local first_step = trial_state.sequence and trial_state.sequence[1]
    local settings =
        ComboTrialsModules.TrainingEnvironment.resolve_recorded_settings(first_step)
    local first_ct = settings.dummy_counter_type or 0
    ComboTrialsModules.SceneStateRuntime.apply(
        first_step,
        trial_state.playing_player,
        trial_state,
        apply_refresh_settings
    )
    local dummy_action_type, dummy_jump_type, dummy_action_source =
        ComboTrialsModules.TrainingEnvironment.resolve_dummy_action(first_step)
    trial_state._dummy_action_source = dummy_action_source
    local action_raw_settings = {
        JumpWeight_Front = settings.dummy_jump_weight_front,
        JumpWeight_Virtical = settings.dummy_jump_weight_vertical,
        JumpWeight_Back = settings.dummy_jump_weight_back,
        CpuLevel = ComboTrialsModules.TrainingEnvironment.cpu_level_to_runtime(
            settings.dummy_cpu_level
        )
    }
    if dummy_action_type ~= nil then
        ComboTrialsModules.DummySettings.set_action_type(
            dummy_action_type,
            dummy_jump_type,
            true,
            action_raw_settings
        )
    elseif trial_requires_dummy_crouch() then
        ComboTrialsModules.DummySettings.set_action_type(ComboTrialsModules.DummySettings.DUMMY_ACTION_CROUCH)
    else
        ComboTrialsModules.DummySettings.set_action_type(
            ComboTrialsModules.DummySettings.DUMMY_ACTION_STAND,
            ComboTrialsModules.TrainingEnvironment.DUMMY_JUMP.VERTICAL
        )
    end
    ComboTrialsModules.DummySettings.set_counter_type(first_ct or 0, {
        NH_Weight = settings.dummy_counter_weight_normal,
        NC_Weight = settings.dummy_counter_weight_counter,
        PC_Weight = settings.dummy_counter_weight_punish
    })
    local dummy_guard_type = ct_trial_dummy_guard_type()
    local dummy_guard_count = ct_trial_dummy_guard_count()
    -- 标题声明“被防连段”且整条连段只包含被防接触时，强制全防御。
    -- 避免防御值缺失或录制为“第 1 击后防御”时首段命中，从而中断录制的输入序列。
    if dummy_guard_type ~= ComboTrialsModules.TrainingEnvironment.DUMMY_GUARD.ALL then
        local first_step = trial_state.sequence and trial_state.sequence[1]
        local meta = type(first_step) == "table" and first_step._xt_meta or nil
        local title = type(meta) == "table" and tostring(meta.title or "") or ""
        if title:find("被防连段", 1, true) and title:find("命中", 1, true) == nil then
            local contact_count = 0
            local blocked_count = 0
            for _, step in ipairs(trial_state.sequence or {}) do
                if step.has_contact == true or step.hit_result == "block" then
                    contact_count = contact_count + 1
                    if step.hit_result == "block" or step.was_blocked == true then
                        blocked_count = blocked_count + 1
                    end
                end
            end
            if contact_count > 0 and blocked_count == contact_count then
                dummy_guard_type = ComboTrialsModules.TrainingEnvironment.DUMMY_GUARD.ALL
                trial_state._dummy_guard_type_source =
                    tostring(trial_state._dummy_guard_type_source or "recorded")
                    .. ":blocked_title_override"
            end
        end
    end
    _G.CT_COMBO_TRIALS_DUMMY_GUARD_TYPE = dummy_guard_type
    ct_apply_recorded_defense_settings(first_step)
    -- Guard must be the final training-setting write. Defense cleanup applies
    -- its own function and could otherwise restore the previous guard mode.
    ComboTrialsModules.DummySettings.set_guard_type(dummy_guard_type, dummy_guard_count, {
        IsGuardSwitching = settings.dummy_guard_switching,
        GuardWeight = settings.dummy_guard_weight,
        GuardOnlyType = settings.dummy_guard_only_type
    })
    if apply_refresh_settings then
        pcall(function()
            local tm = sdk.get_managed_singleton("app.training.TrainingManager")
            if tm then tm._IsReqRefresh = true end
        end)
    end
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


local function assign_groups(sequence, character_name, grouping_rules)
    local resolved_character = SequenceGrouping.character_from_sequence(
        sequence,
        character_name
    )
    if type(grouping_rules) ~= "table" then
        grouping_rules = CharacterRules.build_sequence_grouping_rules(
            CharacterRules.load_for_character(resolved_character),
            common_exceptions
        )
    end
    return SequenceGrouping.assign_groups(
        sequence,
        resolved_character,
        grouping_rules
    )
end

ctx.ensure_run_product_rules = function(run)
    if type(run) ~= "table" then return end
    if type(run.transcription_rules) == "table"
        and type(run.sequence_grouping_rules) == "table" then
        return
    end
    local character_rules = CharacterRules.load_for_character(run.character)
    run.transcription_rules = CharacterRules.build_transcription_rules(
        character_rules,
        common_exceptions
    )
    run.sequence_grouping_rules = CharacterRules.build_sequence_grouping_rules(
        character_rules,
        common_exceptions
    )
end

CTTimelineSequenceNormalizer = ComboTrialsModules.TimelineSequenceNormalizer
CTTimelineSequenceNormalizer.init({ is_drive_rush_id = is_drive_rush_id })

local function normalize_sequence_counter_types(sequence, infer_first_from_legacy_stats)
    if type(sequence) ~= "table" or type(sequence[1]) ~= "table" then return end
    -- Recorded action IDs are the validation ground truth. Timeline data is
    -- playback-only and must never synthesize additional command steps.
    ComboTrialsModules.TrainingEnvironment.normalize_counter_policy(
        sequence,
        infer_first_from_legacy_stats
    )

    for _, step in ipairs(sequence) do
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
    normalize_sequence_semantics = Validator.annotate_terminal_pressure_tail,
    normalize_sequence_scene_state =
        ComboTrialsModules.SceneState.materialize_stable_legacy_actor_hp,
    assign_groups = assign_groups,
    restore_trial_dummy_action_type = ComboTrialsModules.DummySettings.restore_action_type,
})

local function load_combo_from_file(path, force)
    ComboTrialsModules.DummySettings.restore_action_type()
    local ok = ComboTrials_Files.load_combo_from_file(path, force)
    if ok and type(read_actor_scene_hp) == "function"
        and type(restore_hp_training_setting_if_needed) == "function" then
        local snapshot = read_actor_scene_hp()
        if type(snapshot) ~= "table" then
            restore_hp_training_setting_if_needed("load_plain_trial", trial_state.playing_player)
        end
    end
    return ok
end

local function clear_combo_state()
    invalidate_recording_display_context()
    ComboTrialsModules.DummySettings.restore_action_type()
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
    p_state.dash_tap_state = {}
    p_state.prev_act_id = -1
    p_state.prev_act_frame = -1
    p_state.last_direct_input = direct_input
    p_state.last_direction_input = _pf.direction_input or direct_input
    p_state.last_combo_count = 0
    p_state.action_instance_counter = p_state.action_instance_counter or 0
    p_state.current_action_instance = p_state.action_instance_counter
    p_state.buffer_act_id = act_id
    p_state.buffer_act_frame = act_frame
    p_state.buffer_action_instance = p_state.current_action_instance
    p_state.buffer_combo_count = _pf.current_combo or 0
    p_state.recording_block_contact_active = false
    p_state.recording_last_victim_hp = nil
    p_state.recording_contact_state = {}
    p_state.buffer_start_frame = engine_frame_count
    p_state.buffer_flags = _pf.flags or 0
    p_state.buffer_action_code = _pf.action_code or 0
    p_state.buffer_direct_input = direct_input
    p_state.buffer_newly_pressed = 0
    p_state.buffer_input_anchor_kind = nil
    p_state.buffer_input_anchor_frame = nil
    p_state.buffer_input_anchor_motion = nil
    p_state.last_player_action_anchor = nil
    p_state.consumed_player_action_anchor_serial = nil
    p_state.player_action_anchor_serial = 0
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

ctx.build_trial_telemetry_context = function(source)
    local player_idx = trial_state.playing_player or 0
    local first = type(trial_state.sequence) == "table" and trial_state.sequence[1] or nil
    local meta = type(first) == "table" and first._xt_meta or nil
    local declared_control = CTJsonInterop.sequence_control_mode(trial_state.sequence)
    local player_control = control_type_from_input_type(read_player_input_type(player_idx))
    local projection = declared_control == "classic" and player_control == "modern"
        and "classic_to_modern" or "none"
    local position_index = tonumber(d2d_cfg.forced_position_idx or 1) or 1
    local position_mode = position_index == 2 and "original"
        or (position_index == 3 and "mirror" or "any")
    local position_side = position_index == 2 and "p1"
        or (position_index == 3 and "p2" or (trial_state.flip_inputs and "p2" or "p1"))
    local character = type(meta) == "table" and meta.character or nil
    if type(character) ~= "string" or character == "" then
        character = players[player_idx] and players[player_idx].profile_name or "Unknown"
    end
    return {
        sequence = trial_state.sequence,
        file_path = trial_state.current_file_path or trial_state.current_file,
        file_name = trial_state.current_file_name,
        character = character,
        declared_control = declared_control,
        player_control = player_control,
        projection = projection,
        position_mode = position_mode,
        position_side = position_side,
        source = source,
        demo_kind = source == "auto_demo" and (demo_state.raw_buffer and "raw" or "timeline") or nil,
        engine_frame = engine_frame_count or 0
    }
end

ctx.begin_trial_telemetry_attempt = function(source)
    pcall(ComboTrialsModules.Telemetry.begin_attempt, ctx.build_trial_telemetry_context(source))
end

ctx.finish_trial_telemetry_attempt = function(outcome, failure_reason)
    pcall(ComboTrialsModules.Telemetry.finish_attempt, outcome, {
        failure_reason = failure_reason,
        current_step = trial_state.current_step,
        total_steps = type(trial_state.sequence) == "table" and #trial_state.sequence or 0,
        engine_frame = engine_frame_count or 0
    })
end

ctx.finish_demo_telemetry_cycle = function()
    local total_steps = type(trial_state.sequence) == "table" and #trial_state.sequence or 0
    local failed = trial_state.fail_reason ~= nil
        or (trial_state.fail_timer or 0) > 0
        or trial_state.manual_reset_pending == true
    local completed = total_steps > 0 and (trial_state.current_step or 1) > total_steps
    if not failed and completed then
        ctx.finish_trial_telemetry_attempt("success")
    else
        ctx.finish_trial_telemetry_attempt("fail", trial_state.fail_reason or "DEMO INCOMPLETE")
    end
end

local function clear_trial_attempt_state(player_idx, phase)
    trial_state.success_timer = 0
    trial_state.fail_timer = 0
    trial_state.fail_reason = nil
    trial_state.manual_reset_pending = false
    -- Auto-flow state, owned by ctx.handle_trial_auto_flow:
    -- _success_latched      = this attempt reached its terminal success state.
    --                         It freezes further validation after the banner
    --                         and also prevents duplicate completion/advance.
    -- _auto_next_countdown  = frames left before auto-loading the next combo
    -- _attempt_had_demo     = demo playback drove (part of) this attempt, so a
    --                         resulting success must not count as completed
    trial_state._success_latched = false
    trial_state._auto_next_countdown = nil
    trial_state._attempt_had_demo = false
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
    trial_state._pending_current_absorb = nil
    trial_state._pending_block_outcome = nil
    trial_state._consumed_action_instances = nil
    trial_state._last_matched_action_instance = nil
    trial_state._ui_step_hold_step = nil
    trial_state._ui_step_hold_until_frame = nil
    trial_state._step_confirmation_trace = nil
    trial_state._visual_step_trace = nil
    trial_state.last_played_frame = engine_frame_count
    begin_trial_action_grace()
    init_hp_restore_attempt(phase or "attempt", player_idx or trial_state.playing_player)

    reset_player_action_buffers(players[player_idx or trial_state.playing_player])
    for _, item in ipairs(trial_state.sequence) do
        item.actual_combo = 0
        item.actual_hp = nil
        item.has_hit = false
        item.last_frame_diff = nil
        item._runtime_action_id = nil
        item._runtime_match_reason = nil
        item._runtime_combo_on_match = nil
        item._runtime_connected_on_match = nil
        item.ui_result_text = nil
        item.ui_result_kind = nil
    end
    reset_combo_visual_runtime()
    step_combo_reset_gc()
end

reset_combo_visual_runtime = function()
    if not ComboTrials_Renderer then return end
    pcall(function() ComboTrials_Renderer.reset_anim() end)
    pcall(function() ComboTrials_Renderer.reset_raw() end)
end

step_combo_reset_gc = function()
    pcall(function() collectgarbage("step", 16) end)
end

-- =========================================================
-- END DEMO PLAYBACK AREA
-- =========================================================

ctx.resolve_compiled_motion = function(action_id, event, session)
    local character = type(session) == "table" and session.character or nil
    if ComboTrials_Renderer and ComboTrials_Renderer.get_command_display
        and type(character) == "string" and character ~= "" then
        local ok, display, status, metadata = pcall(
            ComboTrials_Renderer.get_command_display,
            character,
            action_id,
            "classic"
        )
        if ok and status == "suppress_transition" then
            local anchor = type(event) == "table" and type(event.anchor) == "table"
                and event.anchor or {}
            local edge_buttons =
                ComboTrialsModules.CommandResolver.find_input_bound_transition_edge(
                    character,
                    event,
                    session,
                    ComboTrials_Renderer
                )
            local direct_input =
                ((tonumber(anchor.held_buttons) or 0) | edge_buttons)
            local intentional, transition_status, transition_motion =
                ComboTrialsModules.CommandResolver.resolve_unified_command_action(
                    character,
                    action_id,
                    direct_input,
                    edge_buttons,
                    ComboTrials_Renderer
                )
            if intentional and type(transition_motion) == "string"
                and transition_motion ~= "" then
                return ComboTrialsModules.TrainingEnvironment.strip_counter_tags(
                    transition_motion
                ), transition_status, metadata
            end
            return nil, status
        end
        -- Do not call the later-declared local trim_string here. This resolver
        -- is defined before that declaration, so Lua would resolve it as a
        -- missing global and silently fall back to guessed input notation.
        local trimmed = type(display) == "string"
            and display:match("^%s*(.-)%s*$") or ""
        if ok and trimmed ~= "" then
            return ComboTrialsModules.TrainingEnvironment.strip_counter_tags(trimmed),
                status, metadata
        end
        return nil, ok and status or "resolver_error", metadata
    end
    return nil, "map_unavailable"
end

ctx.new_action_event_session = function(player_idx, source)
    local p_state = players[player_idx]
    return ComboTrialsModules.ActionEventCompiler.new({
        character = p_state and p_state.profile_name or "Unknown",
        control_mode = control_type_from_input_type(read_player_input_type(player_idx)),
        source = source,
        frame = engine_frame_count,
        motion_resolver = ctx.resolve_compiled_motion,
        action_event_projection_rules =
            CharacterRules.build_action_event_projection_rules(
                p_state and p_state.exceptions or nil,
                common_exceptions
            ),
        action_event_rules = p_state and p_state.action_event_rules
            or CharacterRules.build_action_event_rules(nil, common_exceptions),
    })
end

ctx.compile_action_event_session = function(session, options)
    if type(session) ~= "table" then return nil end
    local finalize_options = {}
    if type(options) == "table" then
        for key, value in pairs(options) do finalize_options[key] = value end
    end
    finalize_options.motion_resolver = ctx.resolve_compiled_motion
    return ComboTrialsModules.ActionEventCompiler.finalize(session, finalize_options)
end

ctx.reset_recording_preview = function()
    trial_state._recording_preview_sequence = {}
    trial_state._recording_preview_logs = {}
    trial_state._recording_preview_signature = nil
    trial_state._recording_preview_error = nil
end

ctx.recording_preview_signature = function(session)
    if type(session) ~= "table" then return nil end
    local events = type(session.events) == "table" and session.events or {}
    local observed = type(session.observed_actions) == "table" and session.observed_actions or {}
    local event = events[#events]
    local anchor = type(event) == "table" and event.anchor or nil
    local observed_action = observed[#observed]
    return table.concat({
        #events,
        #observed,
        tonumber(session.input_anchor_count) or 0,
        tonumber(session.unresolved_anchor_count) or 0,
        type(event) == "table" and tostring(event.id or "") or "",
        type(event) == "table" and tostring(event.promoted_from_id or "") or "",
        type(event) == "table" and tostring(event.bind_reason or "") or "",
        type(event) == "table" and tostring(event.hold_frames or 0) or "0",
        type(event) == "table" and tostring(event.has_hit == true) or "false",
        type(event) == "table" and tostring(event.has_contact == true) or "false",
        type(event) == "table" and tostring(event.was_blocked == true) or "false",
        type(event) == "table" and tostring(event.expected_combo or 0) or "0",
        type(anchor) == "table" and tostring(anchor.kind or "") or "",
        type(anchor) == "table" and tostring(anchor.pressed_buttons or 0) or "0",
        type(anchor) == "table" and tostring(anchor.released_buttons or 0) or "0",
        type(observed_action) == "table" and tostring(observed_action.id or "") or "",
        type(observed_action) == "table" and tostring(observed_action.frame or "") or "",
    }, ":")
end

ctx.refresh_recording_preview = function(session)
    local signature = ctx.recording_preview_signature(session)
    if signature == nil or signature == trial_state._recording_preview_signature then return end
    trial_state._recording_preview_signature = signature

    local ok, compiled = pcall(ctx.compile_action_event_session, session, {
        flush_recording_contacts = false,
    })
    if not ok or type(compiled) ~= "table" or type(compiled.steps) ~= "table" then
        trial_state._recording_preview_error = ok and "invalid_preview" or tostring(compiled)
        return
    end

    trial_state._recording_preview_error = nil
    trial_state._recording_preview_sequence = compiled.steps
    local logs = {}
    for index = #compiled.steps, 1, -1 do
        local source = compiled.steps[index]
        local log = {}
        for key, value in pairs(source) do log[key] = value end
        log.intentional = true
        logs[#logs + 1] = log
    end
    trial_state._recording_preview_logs = logs
end


local function start_recording(player_idx)
    if _G.CurrentTrainerMode ~= 4
        or not (RuntimeSafety.is_training_allowed() or RuntimeSafety.is_replay_allowed()) then
        return false
    end
    if player_idx ~= 0 and player_idx ~= 1 then return false end

    trial_state.recording_player = player_idx
    trial_state.sequence = {}
    ctx.reset_recording_preview()
    begin_recording_display_context(player_idx)
    live_display_context.sync_recording()
    trial_state.is_recording = true
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
    players[player_idx].dash_tap_state = {}
    players[player_idx].prev_act_id = -1
    players[player_idx].prev_act_frame = -1
    players[player_idx].last_combo_count = 0
    players[player_idx].buffer_combo_count = 0
    players[player_idx].recording_block_contact_active = false
    players[player_idx].recording_last_victim_hp = nil
    players[player_idx].recording_contact_state = {}
    players[player_idx].last_direct_input = 0
    players[player_idx].last_direction_input = 0
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
    apply_forced_position(true) -- skip_mirror: record in normal position

    trial_state._rec_gauges = nil
    trial_state._rec_pending_snapshot = 8
    local recorded_counter_type = tonumber(
        trial_state._rec_environment and trial_state._rec_environment.dummy_counter_type
    ) or 0
    trial_state._rec_hit_type = recorded_counter_type == 2 and "PC"
        or (recorded_counter_type == 1 and "CH" or nil)
    trial_state._piyo_detected = false
    trial_state._piyo_frame = nil
    trial_state._rec_frame_count = 0
    trial_state._raw_rec_buffer = {}
    trial_state._raw_rec_active = true
    trial_state._action_event_session = ctx.new_action_event_session(player_idx, "recording")
    trial_state._recording_compiler_used = false
    trial_state._last_action_compile = nil
    return true
end

local function start_trial(player_idx)
    ComboTrialsModules.DummySettings.restore_action_type()
    local was_playing = trial_state.is_playing
    clear_pending_position_injection()
    if was_playing then
        trial_state._pending_victim_hp = nil
        trial_state._pending_attacker_hp = nil
        trial_state._hp_inject_frames = 0
    else
        local starting_hp_snapshot = type(read_actor_scene_hp()) == "table"
        restore_trial_vital(starting_hp_snapshot)
        unique_resources.restore()
    end
    trial_state.is_recording = false
    players[trial_state.recording_player].recording_block_contact_active = false
    players[trial_state.recording_player].recording_last_victim_hp = nil
    players[trial_state.recording_player].recording_contact_state = {}
    invalidate_recording_display_context()
    trial_state._raw_rec_active = false
    trial_state._action_event_session = nil
    trial_state._recording_compiler_used = false
    ctx.reset_recording_preview()
    trial_state._rec_gauges = nil
    trial_state._rec_hit_type = nil
    trial_state._rec_environment = nil
    trial_state._rec_scene_state = nil
    trial_state.is_playing = true
    trial_state.playing_player = player_idx
    trial_state._was_playing = false
    trial_state._hp_inject_frames = 0
    clear_trial_attempt_state(player_idx, "start_trial")

    trial_state.live_start_pos_p1, trial_state.live_start_pos_p2, trial_state.live_start_pos_p1_raw, trial_state.live_start_pos_p2_raw = capture_current_positions()

    -- Full display reset (text log + ImGui raw and animated views)
    reset_combo_visual_runtime()

    ComboTrialsModules.DummySettings.save_counter_type()
    ComboTrialsModules.DummySettings.save_guard_type()
    ComboTrialsModules.DummySettings.save_action_type()

    -- INJECT FIRST-STEP TRAINING ENVIRONMENT
    apply_trial_training_environment()
    apply_hp_restore_training_setting_once("start_trial_training_setting")
    update_trial_flip_state()
    apply_forced_position()
    trial_state._pending_reinject_settings = true
    ctx.begin_trial_telemetry_attempt("manual")
    CTJsonInterop.warn_control_mode_mismatch(
        trial_state.sequence,
        player_idx,
        d2d_cfg.allow_classic_trials_in_modern == true
    )
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
    players[canceled_player].recording_block_contact_active = false
    players[canceled_player].recording_last_victim_hp = nil
    players[canceled_player].recording_contact_state = {}
    trial_state.is_playing = false
    invalidate_recording_display_context()
    trial_state.sequence = {}
    trial_state.current_step = 1
    trial_state._xt_pending_save = false
    trial_state._xt_pending_save_player = nil
    trial_state._xt_pending_save_error = nil
    trial_state._rec_environment = nil
    trial_state._rec_scene_state = nil
    trial_state._raw_rec_active = false
    trial_state._raw_rec_buffer = {}
    trial_state._action_event_session = nil
    trial_state._recording_compiler_used = false
    trial_state._last_action_compile = nil
    ctx.reset_recording_preview()
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
    local saved_player = trial_state.recording_player
    local compiled = ctx.compile_action_event_session(trial_state._action_event_session)
    trial_state._action_event_session = nil
    ctx.reset_recording_preview()
    trial_state._last_action_compile = compiled
    if compiled and type(compiled.steps) == "table" and #compiled.steps > 0 then
        -- The legacy recorder may still collect its diagnostics while recording,
        -- but only the input-bound runtime compiler is allowed to create V2 steps.
        trial_state.sequence = compiled.steps
        Validator.annotate_terminal_pressure_tail(trial_state.sequence)
        trial_state._recording_compiler_used = true
    else
        trial_state.sequence = {}
        trial_state._recording_compiler_used = false
    end

    -- Check if logger has data (for replay/BH mode where sequence stays empty)
    local logger_has_data = false
    if saved_player == 0 then
        logger_has_data = logger_state.rec_p1.has_started and #logger_state.rec_p1.data > 0
    else
        logger_has_data = logger_state.rec_p2.has_started and #logger_state.rec_p2.data > 0
    end

    -- If nothing was recorded anywhere, act exactly like Cancel
    if #trial_state.sequence == 0 and not logger_has_data then
        local canceled_player = saved_player
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

    if #trial_state.sequence == 0 then
        cancel_recording()
        trial_state._xt_pending_save_error = "输入流没有绑定到任何实际 Action，未生成文件"
        _G.ComboTrials_SaveFailedPlayer = saved_player
        _G.ComboTrials_PendingSaveCanceled = saved_player
        return
    end

    trial_state.is_recording = false
    players[saved_player].recording_block_contact_active = false
    players[saved_player].recording_last_victim_hp = nil
    players[saved_player].recording_contact_state = {}
    trial_state._raw_rec_active = false

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

    trial_state.recording_player = saved_player
    local ok, saved_path = pcall(save_trial_sequence, build_auto_xt_meta(saved_player, trial_state.sequence))
    invalidate_recording_display_context()
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
    if trial_state._transcribing ~= true then
        ctx.begin_trial_telemetry_attempt((demo_state and demo_state.is_playing) and "auto_demo" or "manual")
    end
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
            recorded_by = 0,
            _xt_meta = {
                title = CT_DEV_HP_TEST_TITLE,
                note = "DEV HP restore test, attacker current_hp=1000",
                author = "DEV",
                tags = { "dev", "hp_restore" },
                schema = 1
            },
            scene_state = {
                schema = "xt.combo_trial.scene.v2",
                recorded_by = 0,
                players = {
                    p1 = {
                        fighter_id = 21,
                        resources = {
                            hp = 1000
                        }
                    },
                    p2 = {
                        fighter_id = 1
                    }
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

    local scene = type(first.scene_state) == "table" and first.scene_state or {}
    local recorded_by = tonumber(first.recorded_by or scene.recorded_by) == 1 and 1 or 0
    local actor_side = recorded_by == 1 and "p2" or "p1"
    scene.schema = "xt.combo_trial.scene.v2"
    scene.recorded_by = recorded_by
    scene.players = type(scene.players) == "table" and scene.players or {}
    scene.players[actor_side] = type(scene.players[actor_side]) == "table" and scene.players[actor_side] or {}
    scene.players[actor_side].resources = type(scene.players[actor_side].resources) == "table"
        and scene.players[actor_side].resources or {}
    scene.players[actor_side].resources.hp = 1000
    first.scene_state = scene
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
        if trial_state.is_playing
            and trial_state.success_timer == 0 and trial_state._success_latched ~= true then
            local seq = trial_state.sequence or {}
            local last_step = seq[#seq]
            local previous_step = seq[#seq - 1]
            local player_state = players[trial_state.playing_player or 0]
            local last_exception = CharacterRules.get_match_rule(
                player_state and player_state.exceptions or nil,
                common_exceptions,
                player_state and player_state.profile_name or nil,
                last_step and last_step.id
            )
            local attacker = (trial_state.playing_player == 1) and GS.p2 or GS.p1
            local combo_count = math.max(ComboTrialsModules.GameProbe.get_combo_count(attacker) or 0, last_step and (last_step.actual_combo or 0) or 0)
            local completion_satisfied = ActionMatcher.is_completion_satisfied(
                last_step,
                previous_step,
                last_exception,
                combo_count
            )
            if #seq > 0 and trial_state.current_step > #seq and last_step
                and completion_satisfied then
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
    if attacker_char and ComboTrialsModules.GameProbe.get_combo_count(attacker_char) > 0 then
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

function ct_step_requires_action(step)
    if type(step) ~= "table" or step.id == nil then return false end
    local player_idx = trial_state.playing_player or trial_state.recording_player or 0
    local p_state = players[player_idx]
    local exc = CharacterRules.get_exception(
        p_state and p_state.exceptions or nil,
        common_exceptions,
        step.id
    )
    return CharacterRules.is_action_required(exc)
end

local function is_same_action_continuation_step(prev_step, step, combo_count, current_action_instance)
    if not prev_step or not step then return false end
    if ct_step_requires_action(step) then return false end
    if prev_step.id == nil or step.id == nil then return false end
    if prev_step.id ~= step.id then return false end
    local timeline_expanded_repeat = step._ct_timeline_expanded == true

    local prev_combo = tonumber(prev_step.expected_combo) or 0
    local expected_combo = tonumber(step.expected_combo) or 0
    local current_combo = combo_count or 0
    if expected_combo <= 0 or expected_combo <= prev_combo then return false end
    if current_combo < expected_combo then return false end
    if prev_step.action_instance and current_action_instance
        and prev_step.action_instance == current_action_instance
        and not timeline_expanded_repeat
        and not (CTTimelineSequenceNormalizer.simple_button_step_key(prev_step)
            and CTTimelineSequenceNormalizer.simple_button_step_key(prev_step)
                == CTTimelineSequenceNormalizer.simple_button_step_key(step)) then
        return false
    end
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
    if ct_step_requires_action(args.expected) then return nil end
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
        local pending = trial_state._pending_current_absorb
        if type(pending) == "table" and pending.step == trial_state.current_step then
            auto_advance_debug.auto_advance_block_reason = "pending_contact_confirmation"
            DebugTrace.record_auto_advance(trial_state, auto_advance_debug)
            break
        end
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
        DebugTrace.record_step_confirmation(trial_state, {
            step = trial_state.current_step,
            action_id = step.id,
            motion = step.motion,
            validation_frame = engine_frame_count,
            confirmation_frame = engine_frame_count,
            combo_count = combo_count or 0,
            action_instance = current_action_instance,
            match_reason = "same_action_continuation_auto_advance",
            source = call_site,
        })
        ComboTrialsModules.PendingAbsorb.set_timing_ui_result(trial_state, trial_state.current_step, step.last_frame_diff)
        trial_state.current_step = trial_state.current_step + 1
        trial_state.last_played_frame = engine_frame_count
        trial_state.ui_visual_step = trial_state.current_step
        trial_state.floating_info = nil

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
        if cmd == "record" then
            if start_recording(0) then ct_ticker("录制中") end
            return
        end
        if cmd == "cancel_record" then
            _G.ComboTrials_ReplayCancelPlayer = trial_state.recording_player or 0
            cancel_recording(); ct_ticker("录制已取消")
            return
        end
        if cmd == "stop_record" then
            stop_recording_and_save(); ct_ticker("录制已保存")
            return
        end

        -- Replay is read-only apart from observing and saving recorded data.
        if not RuntimeSafety.can_inject_input() then return end

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
            local current_filter = file_system.normalize_combo_control_filter(file_system.combo_control_filter)
            local current_effective = file_system.effective_combo_control_filter(current_filter)
            local cache_matches = file_system.combo_list_character_p1 == (players[0] and players[0].profile_name)
                and file_system.combo_list_character_p2 == (players[1] and players[1].profile_name)
                and file_system.combo_list_cached_filter == current_filter
                and file_system.combo_list_cached_effective_filter == current_effective

            -- Switching modules must only reveal the already prepared list.
            -- File changes are handled by the sync signal / periodic refresh;
            -- re-reading the selected JSON here stalls every mode transition.
            if not cache_matches then
                refresh_combo_list_preserve_selection(true)
                local refreshed_signature, refreshed_error = file_system.build_combo_file_signature()
                if refreshed_signature then
                    file_system.combo_list_last_signature = refreshed_signature
                elseif refreshed_error then
                    file_system.warn_combo_signature_failure(refreshed_error)
                end
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

function file_system.combo_idle_prewarm_allowed()
    return _G.CurrentTrainerMode ~= 4
        and RuntimeSafety.is_training_allowed()
        and _G.TrainingModeActive == true
        and _G.TrainingScriptManagerActiveThisFrame == true
        and _G.IsInBattleHub ~= true
        and _G.IsInReplay ~= true
        and _G.FlowMapID ~= 9
        and _G.FlowMapID ~= 10
        and GS
        and GS.valid == true
end

function file_system.idle_prewarm_combo_mode()
    if not file_system.combo_idle_prewarm_allowed() then return end

    local p1_character = players[0] and players[0].profile_name or "Unknown"
    local p2_character = players[1] and players[1].profile_name or "Unknown"
    if p1_character == "Unknown" or p2_character == "Unknown" then return end

    local current_filter = file_system.normalize_combo_control_filter(file_system.combo_control_filter)
    local current_effective = file_system.effective_combo_control_filter(current_filter)
    local key = table.concat({ p1_character, p2_character, current_filter, current_effective }, "|")
    if file_system.combo_idle_prewarm_key ~= key then
        file_system.combo_idle_prewarm_key = key
        file_system.combo_idle_prewarm_stage = 1
        file_system.combo_idle_prewarm_delay = 0
        file_system.combo_list_was_active = false
    end

    if (file_system.combo_idle_prewarm_delay or 0) > 0 then
        file_system.combo_idle_prewarm_delay = file_system.combo_idle_prewarm_delay - 1
        return
    end

    local stage = file_system.combo_idle_prewarm_stage or 0
    if stage == 1 then
        if file_system.update_combo_file_list(0) then
            file_system.selected_file_idx_p1 = 1
            file_system.combo_idle_prewarm_stage = 2
        end
        return
    end
    if stage == 2 then
        if file_system.update_combo_file_list(1) then
            file_system.selected_file_idx_p2 = 1
            local signature = file_system.build_combo_file_signature()
            if signature then file_system.combo_list_last_signature = signature end
            file_system.combo_idle_prewarm_stage = 3
        end
        return
    end
    if stage == 3 then
        if ComboTrials_Renderer.preload_next_font() then
            file_system.combo_idle_prewarm_stage = 4
        end
        return
    end
    if stage == 4 then
        if not ctx.preload_combo_ui_fonts or ctx.preload_combo_ui_fonts() then
            file_system.combo_idle_prewarm_stage = 5
            -- The list and fonts are ready. Entering Combo Trials should be a
            -- pure visibility switch, with no JSON or font work on that frame.
            file_system.combo_list_was_active = true
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
    local time_value = signal.time or signal.updated_at or signal.updatedAt or signal.timestamp
    if version == nil and time_value == nil then
        file_system.diag_invalid_signal_counter = file_system.diag_invalid_signal_counter + 1
        if file_system.diag_invalid_signal_counter == 1 or file_system.diag_invalid_signal_counter >= 20 then
            file_system.diag_log("sync signal invalid path=" .. tostring(signal_path)
                .. " version=nil time=nil updated_at=nil updatedAt=nil timestamp=nil")
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
        if demo_state then
            demo_state.is_playing = false
            demo_state.p1_mask = 0
            demo_state.playlist_active = false
            demo_state.playlist_index = 0
            demo_state.playlist_total = 0
            demo_state.playlist_pending_next = false
            demo_state.playlist_loading = false
        end
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

local function is_combo_trials_scene_allowed()
    if _G.CurrentTrainerMode ~= 4
        or _G.TrainingModeActive ~= true
        or _G.IsInBattleHub == true then
        return false
    end

    if RuntimeSafety.is_replay_allowed() then
        return _G.IsInReplay == true or _G.FlowMapID == 10
    end

    return RuntimeSafety.is_training_allowed()
        and _G.TrainingScriptManagerActiveThisFrame == true
        and _G.IsInReplay ~= true
        and _G.FlowMapID ~= 9
        and _G.FlowMapID ~= 10
end

local function is_combo_trials_runtime_allowed()
    return is_combo_trials_scene_allowed()
        and GS
        and GS.valid == true
end

ctx.is_scene_allowed = is_combo_trials_scene_allowed
ctx.is_runtime_allowed = is_combo_trials_runtime_allowed

local function publish_combo_trials_inactive_state()
    _G.ComboTrialsD2DEnabled = false
    _G.ComboTrials_HideNativeHUD = false
    _G._ct_bar_geometry = nil
    _G.TrainingBarsDrawn = false
    _G.ComboTrials_IsPlaying = false
    _G.ComboTrials_IsRecording = false
    _G.ComboTrials_IsDemo = false
    _G.ComboTrials_IsAutoDemo = false
    _G.ComboTrials_AutoDemoIndex = 0
    _G.ComboTrials_AutoDemoTotal = 0
end

local function combo_trials_has_runtime_state()
    return trial_state.is_playing == true
        or trial_state.is_recording == true
        or trial_state._xt_pending_save == true
        or trial_state.pending_exact_pos ~= nil
        or (type(trial_state.sequence) == "table" and #trial_state.sequence > 0)
        or (demo_state and (
            demo_state.is_playing == true
            or demo_state.playlist_active == true
            or demo_state.playlist_pending_next == true
            or (demo_state.p1_mask or 0) ~= 0
            or (type(demo_state.sequence) == "table" and #demo_state.sequence > 0)
            or (type(demo_state.raw_buffer) == "table" and #demo_state.raw_buffer > 0)
        ))
end

local combo_trials_runtime_was_allowed = false

local function cleanup_combo_trials_runtime_on_scene_exit(reason)
    publish_combo_trials_inactive_state()
    invalidate_recording_display_context()
    live_display_context.invalidate()
    ComboTrials_Renderer.clear_unresolved_action_audit()

    if demo_state.transcription_run and demo_state.transcription_run.active == true
        and ctx.cancel_transcription then
        pcall(ctx.cancel_transcription)
    end
    if trial_state.is_recording then
        cancel_recording()
    end
    if ctx.stop_demo_playback then
        ctx.stop_demo_playback(
            reason or "scene_exit",
            demo_state and (demo_state.current_file_path or demo_state.current_file) or trial_state.current_file_path or trial_state.current_file,
            nil,
            true,
            false
        )
    end

    trial_state.is_playing = false
    trial_state.is_recording = false
    ctx.reset_recording_preview()
    players[0].recording_block_contact_active = false
    players[1].recording_block_contact_active = false
    players[0].recording_last_victim_hp = nil
    players[1].recording_last_victim_hp = nil
    players[0].recording_contact_state = {}
    players[1].recording_contact_state = {}
    trial_state._raw_rec_active = false
    trial_state._raw_rec_buffer = {}
    trial_state._was_playing = false
    trial_state._xt_pending_save = false
    trial_state._xt_pending_save_player = nil
    trial_state._xt_pending_save_error = nil
    trial_state.flip_inputs = false
    trial_state.floating_info = nil
    trial_state._vital_initialized = false
    trial_state._pause_live_r1 = nil
    trial_state._pause_live_r2 = nil
    trial_state._unpause_delay = nil
    trial_state.pending_exact_pos = nil
    trial_state.pending_exact_timeout = nil
    trial_state._pending_current_absorb = nil
    trial_state.pending_auto_check = nil

    clear_pending_position_injection()
    pcall(clear_combo_state)
    pcall(reset_combo_visual_runtime)
    pcall(restore_trial_vital)
    pcall(function() unique_resources.restore() end)
    pcall(restore_trial_defense_settings)
    pcall(ComboTrialsModules.DummySettings.restore_counter_type)
    pcall(ComboTrialsModules.DummySettings.restore_guard_type)
    pcall(ComboTrialsModules.DummySettings.restore_action_type)
end

local function ct_handle_runtime_scene_gate()
    local allowed = is_combo_trials_runtime_allowed()
    if allowed then
        if not combo_trials_runtime_was_allowed then
            live_display_context.refresh_all()
        end
        combo_trials_runtime_was_allowed = true
        return true
    end

    if is_combo_trials_scene_allowed() then
        publish_combo_trials_inactive_state()
        return false
    end

    if combo_trials_runtime_was_allowed or combo_trials_has_runtime_state() then
        cleanup_combo_trials_runtime_on_scene_exit("training_scene_exit")
    else
        publish_combo_trials_inactive_state()
    end
    combo_trials_runtime_was_allowed = false
    return false
end

local function ct_handle_mode_exit()
    if _G.CurrentTrainerMode ~= 4 then
        if demo_state.transcription_run and demo_state.transcription_run.active == true
            and ctx.cancel_transcription then
            pcall(ctx.cancel_transcription)
        end
        invalidate_recording_display_context()
        live_display_context.invalidate()
        if trial_state._vital_initialized ~= false then
            ComboTrials_Renderer.clear_unresolved_action_audit()
        end
        _G.ComboTrialsD2DEnabled = false
        _G.ComboTrials_HideNativeHUD = false
        _G._ct_bar_geometry = nil
        _G.TrainingBarsDrawn = false
        reset_combo_visual_runtime()
        -- Clean shutdown if switching scripts during an active Trial/Demo
        if trial_state.is_playing or (demo_state and (demo_state.is_playing or demo_state.playlist_active)) then
            trial_state.is_playing = false
            trial_state._was_playing = false
            if demo_state then
                demo_state.is_playing = false
                demo_state.p1_mask = 0
                demo_state.playlist_active = false
                demo_state.playlist_index = 0
                demo_state.playlist_total = 0
                demo_state.playlist_pending_next = false
                demo_state.playlist_loading = false
            end

            restore_trial_vital()
            unique_resources.restore()
            restore_trial_defense_settings()
            ComboTrialsModules.DummySettings.restore_counter_type()
            ComboTrialsModules.DummySettings.restore_guard_type()
            ComboTrialsModules.DummySettings.restore_action_type()
            apply_current_position_refresh()
        elseif trial_state.is_recording then
            cancel_recording()
        end
        trial_state._vital_initialized = false
        return
    end
end

local function ct_handle_first_frame_init(_in_replay)
    if not trial_state._vital_initialized then
        invalidate_recording_display_context()
        live_display_context.ensure()
        ComboTrials_Renderer.clear_unresolved_action_audit()
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

        if not _in_replay then
            restore_trial_vital()
            unique_resources.restore()
        end
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

local function ct_handle_playing_transition(_in_replay)
    if _in_replay then
        trial_state._was_playing = false
        return
    end

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
        ComboTrialsModules.DummySettings.restore_action_type()
        ComboTrialsModules.DummySettings.restore_counter_type()
        ComboTrialsModules.DummySettings.restore_guard_type()
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
        live_display_context.refresh(p_idx)
        p_state.log = {}
        p_state.input_history_queue = {}
        p_state.dash_tap_state = {}
        p_state.action_instance_counter = 0
        p_state.current_action_instance = 0
        p_state.buffer_action_instance = 0
        p_state.buffer_combo_count = 0
        p_state.recording_block_contact_active = false
        p_state.recording_last_victim_hp = nil
        p_state.recording_contact_state = {}
        p_state.trigger_mask_cache = {}
        p_state.trigger_cache_built = false
        p_state._trigger_cache_build = nil
        p_state.last_bcm_ptr = ""

        -- RESET TRIAL on character change
        -- The trial depends on both characters, reset if either changes
        if not trial_state._xt_pending_save then
            if trial_state.is_recording then
                trial_state.is_recording = false
                invalidate_recording_display_context()
                trial_state._raw_rec_active = false
                trial_state._raw_rec_buffer = {}
                ctx.reset_recording_preview()
            end
            if trial_state.is_playing then
                trial_state.is_playing = false
            end
            if demo_state then
                demo_state.is_playing = false
                demo_state.p1_mask = 0
                demo_state.raw_buffer = nil
                demo_state.raw_input_source = nil
                demo_state.play_index = 1
                demo_state.playlist_active = false
                demo_state.playlist_index = 0
                demo_state.playlist_total = 0
                demo_state.playlist_pending_next = false
                demo_state.playlist_loading = false
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
            local cached_character = file_system.combo_list_character_p2
            if p_idx == 0 then cached_character = file_system.combo_list_character_p1 end
            if cached_character ~= p_state.profile_name then
                refresh_combo_list()
            end
        end
        if p_state.profile_name ~= "Unknown" then
            p_state.exceptions = CharacterRules.load_for_character(p_state.profile_name)
            p_state.action_compatibility = select(1,
                ComboTrialsModules.ActionCompatibility.load(
                p_state.profile_name,
                SF6CCVersion.GAME_VERSION,
                function(filename) return json.load_file(filename) end
            ))
            p_state.action_event_rules = CharacterRules.build_action_event_rules(
                p_state.exceptions,
                common_exceptions
            )
            p_state.sequence_grouping_rules =
                CharacterRules.build_sequence_grouping_rules(
                    p_state.exceptions,
                    common_exceptions
                )
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
    trial_state._rec_gauges = ComboTrialsModules.GameProbe.capture_recording_gauges(p_idx)
    -- At this point vital_new = character's real max_hp, so damage is calculated from 100%
    end
    end
    -- Fetch victim once for all checks below
    _pf.victim_idx = 1 - p_idx
    _pf.victim_obj = (_pf.victim_idx == 0) and GS.p1 or GS.p2

    if trial_state.is_recording and p_idx == trial_state.recording_player and trial_state._rec_gauges then
        pcall(_ct_track_rec_gauges, _pf.victim_obj, _pf.p_char, p_idx)
    end

    local recording_hit_contact = { accepted = false }
    if trial_state.is_recording and p_idx == trial_state.recording_player then
        local victim_damage_type = 0
        local damage_ok, captured_damage_type =
            pcall(_G.CTRecordingRepeat.read_live_damage_type, _pf.victim_obj)
        if damage_ok then victim_damage_type = captured_damage_type or 0 end
        local victim_hit_stop = 0
        local hit_stop_ok, captured_hit_stop =
            pcall(_G.CTRecordingRepeat.read_live_hit_stop, _pf.victim_obj)
        if hit_stop_ok then victim_hit_stop = captured_hit_stop or 0 end
        p_state.recording_contact_state =
            type(p_state.recording_contact_state) == "table"
                and p_state.recording_contact_state or {}
        local current_victim_hp = nil
        pcall(function()
            current_victim_hp = tonumber(_pf.victim_obj and _pf.victim_obj.vital_new)
        end)
        local contact_truth = ActionRestartDetector.observe_recording_contacts(
            p_state.recording_contact_state,
            {
                frame = engine_frame_count,
                current_combo = _pf.current_combo or 0,
                previous_combo = p_state.last_combo_count or 0,
                current_hp = current_victim_hp,
                previous_hp = p_state.recording_last_victim_hp,
                damage_type = victim_damage_type,
                hit_stop = victim_hit_stop,
                contact_candidate = true,
            }
        )
        local block_contact = contact_truth.block_contact
        if block_contact.started then
            if #trial_state.sequence > 0 then
                local step = trial_state.sequence[#trial_state.sequence]
                step.has_contact = true
                step.was_blocked = true
            end
        end
        p_state.recording_block_contact_active = block_contact.active
        recording_hit_contact = contact_truth.hit_contact
        p_state.recording_last_victim_hp = current_victim_hp
    else
        p_state.recording_block_contact_active = false
        p_state.recording_last_victim_hp = nil
        p_state.recording_contact_state = {}
    end

    -- Hit detection for visual display (has_hit + actual_combo + projectile)
    if (_pf.current_combo or 0) > (p_state.last_combo_count or 0)
        or recording_hit_contact.accepted then
        -- Verify hit source: projectile or direct player hit
        local hit_is_projectile = false
        pcall(function()
            hit_is_projectile = ComboTrialsModules.GameProbe.check_is_projectile(p_idx, _pf.p_char, _td_gBattle)
        end)

        if trial_state.is_recording and p_idx == trial_state.recording_player then
            if #trial_state.sequence > 0 then
                local step = trial_state.sequence[#trial_state.sequence]
                step.has_contact = true
                -- has_hit is now handled by on_frame delayed combo tracking
                -- Track if there was AT LEAST one projectile hit during the action
                step.is_projectile_hit = step.is_projectile_hit or hit_is_projectile
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

                -- Advance ONLY the [ACTION X / Y] counter on impact
                trial_state.ui_visual_step = trial_state.current_step
                trial_state.floating_info = nil -- <-- Clear text while waiting for the next input
            end

        end
    			end

    -- Opponent knockdown detection (pose_st == 3)
    _pf.opponent_knocked_down = false
    local _ok_kd, _kd = pcall(_ct_check_knockdown, _pf.victim_obj)
    if _ok_kd and _kd then _pf.opponent_knocked_down = true end
    -- Preserve the trial's configured guard mode through knockdown. Pressure
    -- routes may continue after the damaging combo ends and must still be able
    -- to demonstrate a guarded meaty/string on wake-up.

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
            set_dummy_counter_type = ComboTrialsModules.DummySettings.set_counter_type,
            d2d_cfg = d2d_cfg,
            file_system = file_system,
            act_id_reverse_enum = ComboTrialsModules.GameProbe.act_id_reverse_enum
        }, "pending_current_absorb_validation")
    end
    if trial_state.is_playing and p_idx == trial_state.playing_player and not trial_state.manual_reset_pending then
        local is_hold_pending = (trial_state.active_universal_hold ~= nil)

        if #trial_state.sequence > 0 and trial_state.current_step > #trial_state.sequence then
            local last_step = trial_state.sequence[#trial_state.sequence]
            local previous_step = trial_state.sequence[#trial_state.sequence - 1]
            local last_exception = CharacterRules.get_match_rule(
                p_state.exceptions,
                common_exceptions,
                p_state.profile_name,
                last_step and last_step.id
            )
            local observed_combo = math.max(_pf.current_combo or 0, p_state.last_combo_count or 0, last_step.actual_combo or 0)
            local completion_satisfied = ActionMatcher.is_completion_satisfied(
                last_step,
                previous_step,
                last_exception,
                observed_combo
            )
            local should_finish_success = trial_state.success_timer == 0 and not is_hold_pending and not (trial_state.fail_timer and trial_state.fail_timer > 0)
                and (is_pressure_tail_step(last_step) or completion_satisfied)
            if should_finish_success then
                trial_state.success_timer = d2d_cfg.fail_display_frames or 120
            end
        end

        -- Demo playback must show the same terminal success state as manual
        -- play, while its completion remains excluded from persistent records
        -- by _attempt_had_demo in handle_trial_auto_flow.
        if is_demo_playing then return end

        -- CONTINUOUS COMBO DROP DETECTION:
        if (_pf.current_combo or 0) == 0 and (p_state.last_combo_count or 0) > 0 and not trial_state._pending_hit_cc and not (trial_state._hit_grace and trial_state._hit_grace > 0) then
            if trial_state.success_timer == 0 and not (trial_state.fail_timer and trial_state.fail_timer > 0) then
                local last_validated_idx = trial_state.current_step - 1
                if last_validated_idx >= 1 then
                    local last_validated = trial_state.sequence[last_validated_idx]

                    local current_expected = trial_state.sequence[trial_state.current_step]
                    local is_reset_expected = current_expected and current_expected.expected_combo == 0
                    local is_combo_restart_expected =
                        Validator.is_expected_combo_restart_step(
                            current_expected,
                            last_validated
                        )
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
                            and not is_combo_restart_expected
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
                            phase = "pressure_tail_timeout",
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
                            reject_reason = "pressure_tail_action_missed"
                        })
                        ComboTrialsModules.PendingAbsorb.clear(trial_state, "pressure_tail_timeout")
                        trial_state.fail_timer = d2d_cfg.fail_display_frames or 120
                        trial_state.fail_reason = "PRESSURE TOO LATE (Missed Input)"
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

    local previous_direct_input = tonumber(p_state.last_direct_input) or 0
    local newly_pressed = (_pf.direct_input ~ previous_direct_input) & _pf.direct_input
    local newly_released = (_pf.direct_input ~ previous_direct_input) & previous_direct_input
    local pressed_buttons = newly_pressed & 0xFFF0
    local released_buttons = newly_released & 0xFFF0
    local direction_input = tonumber(_pf.direction_input) or (_pf.direct_input & 0xF)
    local previous_direction_input = tonumber(p_state.last_direction_input) or 0
    local newly_pressed_dir = ((direction_input ~ previous_direction_input) & direction_input) & 0xF
    local current_dir_val = ActionRestartDetector.normalize_input_direction_bits(
        direction_input, _pf.facing_right)
    local current_dir = INPUT_DIR_MAP[current_dir_val] or "5"
    if current_dir == "5" then current_dir = "" end
    local detected_66_edge = current_dir == "6" and newly_pressed_dir ~= 0
    local detected_44_edge = current_dir == "4" and newly_pressed_dir ~= 0

    p_state.dash_tap_state = p_state.dash_tap_state or {}
    local dash_pair = nil
    if (detected_66_edge or detected_44_edge)
        and ActionMatcher.should_observe_dash_direction_edge(
            pressed_buttons, released_buttons) then
        dash_pair = ActionRestartDetector.observe_dash_direction_edge(
            p_state.dash_tap_state, current_dir, engine_frame_count)
    end

    local anchor_kind = nil
    if pressed_buttons ~= 0 then
        anchor_kind = "button_press"
    elseif released_buttons ~= 0 then
        anchor_kind = "button_release"
    end
    if dash_pair then anchor_kind = "double_tap" end
    if anchor_kind then
        p_state.player_action_anchor_serial = (p_state.player_action_anchor_serial or 0) + 1
        p_state.last_player_action_anchor = {
            serial = p_state.player_action_anchor_serial,
            frame = engine_frame_count,
            kind = anchor_kind,
            motion = dash_pair and (dash_pair.direction .. dash_pair.direction) or nil,
        }
    end

    if newly_pressed > 0 then
        table.insert(p_state.input_history_queue,
            { frame_tick = engine_frame_count, mask = newly_pressed, dir = current_dir })
    end
    p_state.last_direct_input = _pf.direct_input
    p_state.last_direction_input = direction_input

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
    p_state.buffer_newly_pressed = p_state.buffer_newly_pressed or 0
    p_state.buffer_b_type = p_state.buffer_b_type or 0
    p_state.buffer_hold_frames = p_state.buffer_hold_frames or 0
    p_state.buffer_combo_count = p_state.buffer_combo_count or 0
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
    local action_input_edge = newly_pressed & 0xFFF0
    local restart_input_edge = action_input_edge
    if restart_input_edge == 0 then
        restart_input_edge = ComboTrialsModules.CommandResolver.find_recent_action_button_edge(
            p_state.input_history_queue, p_state.buffer_start_frame,
            engine_frame_count, ComboTrialsModules.CommandResolver.PLAYER_TRANSITION_INPUT_WINDOW)
    end
    local repeat_expected = trial_state.is_playing
        and p_state == players[trial_state.playing_player]
        and trial_state.sequence
        and trial_state.sequence[trial_state.current_step] or nil
    local repeat_previous = repeat_expected and trial_state.current_step > 1
        and trial_state.sequence[trial_state.current_step - 1] or nil
    local expected_repeat_input = ActionRestartDetector.evaluate_expected_repeat_input({
        expected_id = repeat_expected and repeat_expected.id or nil,
        previous_id = repeat_previous and repeat_previous.id or nil,
        current_id = _pf.act_id,
        buffered_id = p_state.buffer_act_id,
        current_combo = _pf.current_combo or 0,
        previous_expected_combo = repeat_previous and repeat_previous.expected_combo or 0,
        frames_since_previous = engine_frame_count - (trial_state.last_played_frame or engine_frame_count),
        expected_delay = repeat_expected and repeat_expected.delay_from_prev or 0,
        action_button_edge = action_input_edge
    })
    local confirmed_repeat_input = expected_repeat_input.accepted
    local started_new_action, started_new_action_reason = ActionRestartDetector.detect(
        _pf.act_id, _pf.act_frame, p_state.buffer_act_id, p_state.buffer_act_frame,
        p_state.dash_tap_state, engine_frame_count, restart_input_edge,
        confirmed_repeat_input)
    if started_new_action and action_input_edge == 0 then
        -- Some actions switch one or two frames after the button edge. Reuse the
        -- newest post-parent physical edge instead of treating a held button as
        -- new. Character cancel transitions can arrive later than ghost_wait.
        action_input_edge = restart_input_edge
    end
    local current_input_anchor_kind = nil
    local current_input_anchor_frame = nil
    local current_input_anchor_motion = nil
    if started_new_action and type(p_state.last_player_action_anchor) == "table" then
        local player_anchor = p_state.last_player_action_anchor
        local anchor_serial = tonumber(player_anchor.serial)
        local anchor_frame = tonumber(player_anchor.frame)
        local anchor_age = anchor_frame and (engine_frame_count - anchor_frame) or nil
        if anchor_serial ~= nil
            and anchor_serial ~= tonumber(p_state.consumed_player_action_anchor_serial)
            and anchor_frame ~= nil
            and anchor_frame > (tonumber(p_state.buffer_start_frame) or -1)
            and anchor_age >= 0
            and anchor_age <= ActionMatcher.PLAYER_ACTION_BIND_WINDOW then
            current_input_anchor_kind = player_anchor.kind
            current_input_anchor_frame = anchor_frame
            current_input_anchor_motion = player_anchor.motion
            p_state.consumed_player_action_anchor_serial = anchor_serial
        end
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
        expected_repeat_input = expected_repeat_input,
        dash_pair_direction = dash_pair and dash_pair.direction or nil,
        dash_pair_interval = dash_pair and dash_pair.interval or nil,
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

            local preserve_short_action =
                CharacterRules.should_preserve_short_action(
                    p_state.exceptions,
                    common_exceptions,
                    p_state.buffer_act_id
                )
            local preserve_quick_successor =
                ActionMatcher.should_preserve_quick_successor(
                    p_state.action_event_rules,
                    p_state.buffer_act_id,
                    duration
                )
            -- A buffered action with both a physical attack input and a BCM
            -- command owner is a real player command. State/resource branches
            -- can replace it within the ghost window (for example, a status-
            -- dependent follow-up); the later action must not erase the command.
            local buffered_is_catalog_command = ComboTrialsModules.CommandResolver.resolve_unified_command_action(
                p_state.profile_name, p_state.buffer_act_id, p_state.buffer_direct_input,
                p_state.buffer_newly_pressed, ComboTrials_Renderer)

            if duration > 0 and duration < ghost_wait and p_state.buffer_act_id > 50
                and not preserve_short_action
                and not preserve_quick_successor
                and not buffered_is_catalog_command then
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
                local new_is_catalog_command, new_command_status =
                    ComboTrialsModules.CommandResolver.resolve_unified_command_action(
                        p_state.profile_name, _pf.act_id, _pf.direct_input, action_input_edge,
                        ComboTrials_Renderer)
                if not new_is_intentional and new_is_catalog_command then
                    new_is_intentional = true
                end
                if _pf.act_id == 36 or _pf.act_id == 37 or _pf.act_id == 38 then new_is_intentional = true end

                local exc_new = CharacterRules.get_exception(p_state.exceptions, common_exceptions, _pf.act_id)
                if ActionMatcher.is_force_enabled(exc_new) then new_is_intentional = true end
                -- 指令表已审计的零输入/自动状态跳转不是第二次玩家输入，不能
                -- 把它当成新意图并误删前一个真实指令。
                if new_command_status == "suppress_transition" then new_is_intentional = false end

                -- If the NEW action is truly intentional (e.g. player hit P, then PP 2 frames later),
                -- THEN the buffered action is a ghost.
                -- But if the NEW action is automatic (e.g. Kimberly auto-sprint after EX move),
                -- the buffered action IS NOT a ghost, it is valid and must be committed.
                if new_is_intentional then
                    is_ghost = true
                end
            end

            if is_ghost then
                local g_name = ComboTrialsModules.GameProbe.act_id_reverse_enum[p_state.buffer_act_id] or "Unknown"
                local ghost_motion = nil
                if ComboTrials_Renderer and ComboTrials_Renderer.get_command_display then
                    local ok, value = pcall(ComboTrials_Renderer.get_command_display,
                        p_state.profile_name, p_state.buffer_act_id, "classic")
                    if ok then ghost_motion = value end
                end
                table.insert(p_state.log, 1, {
                    id = p_state.buffer_act_id,
                    name = g_name,
                    motion = ghost_motion or g_name,
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
                    newly_pressed = p_state.buffer_newly_pressed,
                    input_anchor_kind = p_state.buffer_input_anchor_kind,
                    input_anchor_frame = p_state.buffer_input_anchor_frame,
                    input_anchor_motion = p_state.buffer_input_anchor_motion,
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
        p_state.buffer_combo_count = _pf.current_combo or 0
        p_state.buffer_is_committed = false
        p_state.buffer_flags = _pf.flags
        p_state.buffer_action_code = _pf.action_code
        p_state.buffer_direct_input = _pf.direct_input
        p_state.buffer_newly_pressed = action_input_edge
        p_state.buffer_input_anchor_kind = current_input_anchor_kind
        p_state.buffer_input_anchor_frame = current_input_anchor_frame
        p_state.buffer_input_anchor_motion = current_input_anchor_motion
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
            newly_pressed = p_state.buffer_newly_pressed,
            input_anchor_kind = p_state.buffer_input_anchor_kind,
            input_anchor_frame = p_state.buffer_input_anchor_frame,
            input_anchor_motion = p_state.buffer_input_anchor_motion,
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
    local input_truth_mode = ActionMatcher.sequence_uses_input_truth(trial_state.sequence)
    for _, process_act in ipairs(actions_to_process) do
        local runtime_act_id = process_act.id
        local act_id = runtime_act_id
        local flags = process_act.flags
        local action_code = process_act.action_code
        local direct_input = process_act.direct_input
        local b_type = process_act.b_type
        local engine_frame_count = process_act.engine_frame

        -- ABSORPTION CHECK (Does the active parent action want to absorb this new ID?)
        local is_continuation = false
        if #p_state.log > 0 then
            local parent_id = p_state.log[1].id
            local parent_exc = CharacterRules.get_exception(p_state.exceptions, common_exceptions, parent_id)

            -- Real-time update if we are editing the parent action
            if p_state.editing_id == parent_id then
                parent_exc = { absorb_ids = p_state.edit_absorb_ids }
            end

            is_continuation = ActionMatcher.matches_absorb_id(parent_exc, runtime_act_id)
            if is_continuation
                and CharacterRules.should_preserve_absorbed_transition(
                    parent_exc,
                    process_act.input_anchor_kind
                ) then
                is_continuation = false
            end
        end

        -- Some state-dependent commands branch away from their catalog Action
        -- at frame zero, so polling never observes the command owner itself.
        -- Character rules must opt in, and a physical catalog command is still
        -- required before recording an absorbed runtime ID as its parent.
        if not is_continuation and trial_state.is_recording
            and p_idx == trial_state.recording_player then
            local absorb_owner_id = CharacterRules.find_recording_absorb_owner(
                p_state.exceptions, common_exceptions, runtime_act_id)
            if absorb_owner_id then
                local owner_is_command = ComboTrialsModules.CommandResolver.resolve_unified_command_action(
                    p_state.profile_name, absorb_owner_id, direct_input, process_act.newly_pressed,
                    ComboTrials_Renderer)
                if owner_is_command then act_id = absorb_owner_id end
            end
        end

        local act_name = ComboTrialsModules.GameProbe.act_id_reverse_enum[act_id] or "Unknown"

        -- 1. EARLY EXCEPTION RESOLUTION (For Hold Link)
        local exc = CharacterRules.get_exception(p_state.exceptions, common_exceptions, act_id)

        if p_state.editing_id == act_id then
            exc = ActionMatcher.build_edit_exception(p_state)
        end

        exc = CharacterRules.apply_runtime_overrides(p_state.profile_name, act_id, exc, p_state.log)

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
            local transition_policy = nil
            local unified_command_action, unified_command_status, unified_classic_motion =
                ComboTrialsModules.CommandResolver.resolve_unified_command_action(
                    p_state.profile_name, act_id, direct_input, process_act.newly_pressed,
                    ComboTrials_Renderer)

            if act_id > 50 or act_id == 17 or act_id == 18
                or act_id == 36 or act_id == 37 or act_id == 38 then
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
                if not is_ignored and ComboTrialsModules.GameProbe.get_damage_type_safe(_pf.p_char) ~= 0 then
                    is_ignored = true
                    ignore_reason = "[System: Taking Damage]"
                end
            end

            if is_trackable then
                if ActionMatcher.is_exception_ignored(exc) then
                    is_ignored = true
                    ignore_reason = "[例外：忽略]"
                end
                -- 角色指令表中的 suppress_transition 是跨操作模式的共用语义：
                -- 该 Action 只负责返回/切换内部状态，没有第二次可见玩家输入。
                if unified_command_status == "suppress_transition" then
                    is_ignored = true
                    ignore_reason = "[指令表：内部状态跳转]"
                end

                -- Check ignore_prev_id condition (supports single number or table of numbers).
                -- During playback, an explicitly expected action must be allowed to validate
                -- even if its exception normally ignores it after a parent/hold action.
                local expected_for_ignore = nil
                if trial_state.is_playing and p_idx == trial_state.playing_player
                    and trial_state.sequence and trial_state.current_step then
                    expected_for_ignore = trial_state.sequence[trial_state.current_step]
                end
                local expected_exception = expected_for_ignore
                    and CharacterRules.get_match_rule(
                        p_state.exceptions,
                        common_exceptions,
                        p_state.profile_name,
                        expected_for_ignore.id
                    ) or nil
                local expected_action_matches_current = expected_for_ignore
                    and ActionMatcher.matches_expected_action_id(
                        expected_for_ignore,
                        act_id,
                        expected_exception,
                        p_state.action_compatibility
                    )

                if is_ignored and ignore_reason == "[例外：忽略]"
                    and ActionMatcher.should_admit_ignored_expected_action(
                        input_truth_mode,
                        expected_for_ignore,
                        act_id,
                        expected_exception,
                        p_state.action_compatibility
                    ) then
                    is_ignored = false
                    ignore_reason = ""
                end
                if is_ignored and ignore_reason == "[指令表：内部状态跳转]"
                    and ActionMatcher.should_admit_ignored_expected_action(
                        input_truth_mode,
                        expected_for_ignore,
                        act_id,
                        expected_exception,
                        p_state.action_compatibility
                    ) then
                    -- A raw-input candidate is created from an input-bound
                    -- runtime Action. Static command data may classify the
                    -- same ID as a zero-input phase in other contexts; it must
                    -- not erase the exact expected Action during playback.
                    is_ignored = false
                    ignore_reason = ""
                end

                local previous_expected_for_transition = expected_for_ignore
                    and trial_state.current_step
                    and trial_state.current_step > 1
                    and trial_state.sequence[trial_state.current_step - 1] or nil
                transition_policy = ActionMatcher.classify_runtime_transition({
                    previous_step = previous_expected_for_transition,
                    expected_step = expected_for_ignore,
                    expected_action_matches_current = expected_action_matches_current == true,
                    actual_action_id = act_id,
                    character = p_state.profile_name,
                    action_event_rules = p_state.action_event_rules,
                    input_anchor_kind = process_act.input_anchor_kind,
                    input_anchor_motion = process_act.input_anchor_motion,
                    input_truth_mode = input_truth_mode,
                    frames_since_previous = engine_frame_count
                        - (tonumber(trial_state.last_played_frame) or engine_frame_count),
                })
                if transition_policy.ignored then
                    is_ignored = true
                    ignore_reason = transition_policy.reason == "transient_input_precursor"
                        and "[输入事实：瞬态前驱，等待完整指令]"
                        or "[输入事实：无新输入的内部状态跳转]"
                end

                if not is_ignored and not expected_action_matches_current then
                    local ignore_prev = ActionMatcher.evaluate_ignore_prev(exc, p_state.log, engine_frame_count)
                    if ignore_prev.ignored then
                        is_ignored = true
                        ignore_reason = ignore_prev.reason
                    end
                end

                if p_state.enable_deep_logging then deep_data = ComboTrialsModules.GameProbe.capture_deep_action_data(_pf.p_char) end

                if flags == 0 then
                    is_intentional = true
                elseif flags == 16 then
                    if action_code > 0 and b_type ~= 0 then
                        is_intentional = true
                    elseif b_type == 536870932 and (direct_input & 0xFFFF) > 0 then
                        is_intentional = true
                    end
                end

                -- BCM/exception-backed stance normals are intentional when an
                -- attack button is physically present, even if the engine marks
                -- their transition as flags=16 with no action/branch code.
                if not is_intentional and unified_command_action then
                    is_intentional = true
                end

                -- A recorded step is runtime evidence that this Action ID can be
                -- player-relevant even when the generated command table cannot
                -- classify a character-specific hit/branch phase. Admit only an
                -- exact or configured variant match for the active expected step.
                if not is_intentional and expected_action_matches_current then
                    is_intentional = true
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

                local pending_absorb_ctx = {
                        state = trial_state,
                        p_idx = p_idx,
                        p_state = p_state,
                        frame = engine_frame_count,
                        pf = _pf,
                        Validator = Validator,
                        DebugTrace = DebugTrace,
                        is_post_hit_setup_step = is_post_hit_setup_step,
                        set_dummy_counter_type = ComboTrialsModules.DummySettings.set_counter_type,
                        d2d_cfg = d2d_cfg,
                        file_system = file_system,
                        act_id_reverse_enum = ComboTrialsModules.GameProbe.act_id_reverse_enum
                    }
                local function apply_matched_step(matched_expected, matched_act_id, matched_motion, matched_input, matched_frame, matched_combo, matched_hp, match_reason, match_details)
                    local confirmed, matched_step_idx = ComboTrialsModules.PendingAbsorb.apply_matched_step(pending_absorb_ctx, {
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

                ComboTrialsModules.PendingAbsorb.check(
                    pending_absorb_ctx,
                    "pending_current_absorb_pre_action"
                )

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
                -- The unified three-slot command table is the only source for
                -- Classic command text. Live trigger/action data remains
                -- detection evidence above, but must not silently restore another
                -- display source when a generated table fails its audit.
                motion_str = unified_classic_motion or act_name
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
                    local real_btn = ComboTrialsModules.GameProbe.decode_button_mask(best_match.mask)
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
                        motion_str = "Follow-up (" .. ComboTrialsModules.GameProbe.decode_button_mask(best_match.mask) .. ")"
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
                        if process_act.previous_combo ~= nil then
                            prev_step.expected_combo = process_act.previous_combo
                        elseif not trial_state._pending_hit_cc then
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
                        trial_state.sequence[#trial_state.sequence].damage_at_step =
                            math.max(0, rg.victim_hp - v_hp_now)
                    end

                    local recorded_hold_frames = tonumber(hold_frames or 0) or 0
                    local buffered_hold_frames = tonumber(process_act.buffer_hold_frames or 0) or 0
                    if buffered_hold_frames > recorded_hold_frames then
                        recorded_hold_frames = buffered_hold_frames
                    end

                    table.insert(trial_state.sequence, {
                        id = act_id,
                        motion = motion_str,
                        player_input_transition = unified_command_status == "player_input_transition",
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
                        has_contact = false,
                        was_blocked = false,
                        is_projectile_hit = false,
                        delay_from_prev = delay,
                        facing_left = is_facing_left,
                        next_auto_id = nil -- Will be filled if the next action is automatic
                    })
                    assign_groups(
                        trial_state.sequence,
                        p_state.profile_name,
                        p_state.sequence_grouping_rules
                    )
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
                            local expected_exception = CharacterRules.get_match_rule(
                                p_state.exceptions,
                                common_exceptions,
                                p_state.profile_name,
                                expected.id
                            )
                            local action_match = ActionMatcher.match_expected_action(
                                expected,
                                act_id,
                                motion_str,
                                real_input_str,
                                expected_exception,
                                p_state.action_compatibility
                            )
                            if process_act.synthetic then
                                action_match.source = process_act.fallback_source or process_act.source
                                action_match.edge_type = process_act.edge_type
                                action_match.synthetic = true
                                action_match.frames_since_prev_step = process_act.frames_since_prev_step
                                action_match.expected_delay = process_act.expected_delay
                                action_match.frame_diff = process_act.frame_diff
                            end
                            local match_probe = build_match_probe(expected, "intentional_action")
                            match_probe.transition_policy = transition_policy
                            match_probe.input_anchor_kind = process_act.input_anchor_kind
                            match_probe.input_anchor_motion = process_act.input_anchor_motion
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
                                expected,
                                Validator.is_terminal_explicit_whiff(
                                    trial_state.sequence,
                                    trial_state.current_step
                                )
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
                            local replay_dash_retrigger =
                                ActionRestartDetector.evaluate_replay_dash_retrigger_residue({
                                    replay_active = demo_state and demo_state.is_playing,
                                    previous_id = trace_prev_step and trace_prev_step.id or nil,
                                    expected_id = expected and expected.id or nil,
                                    actual_id = act_id,
                                    previous_action_instance = trace_prev_step
                                        and trace_prev_step.action_instance or nil,
                                    candidate_action_instance = process_act.action_instance,
                                    input_anchor_kind = process_act.input_anchor_kind,
                                    frames_since_previous = match_probe.frames_since_prev_step,
                                    expected_delay = expected and expected.delay_from_prev or nil,
                                    timing_tolerance = 2,
                                })
                            match_probe.replay_dash_retrigger = replay_dash_retrigger
                            if expected and not action_match.matched then
                                local recent_absorb = input_truth_mode
                                    and CharacterRules.find_recent_canonical_confirmation(
                                        p_state.exceptions,
                                        common_exceptions,
                                        expected,
                                        p_state.log,
                                        p_state.profile_name
                                    )
                                    or CharacterRules.find_recent_absorb_confirmation(
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
                                                chain_expected,
                                                Validator.is_terminal_explicit_whiff(
                                                    trial_state.sequence,
                                                    chain_step
                                                )
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
                                                match_reason = "recent_absorb_chain",
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
                                                ignore_combo_check = chain_absorb.ignore_combo_check,
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
                                                "recent_absorb_chain",
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
                                            local chain_expected_exception = CharacterRules.get_match_rule(
                                                p_state.exceptions,
                                                common_exceptions,
                                                p_state.profile_name,
                                                expected.id
                                            )
                                            action_match = ActionMatcher.match_expected_action(
                                                expected,
                                                act_id,
                                                motion_str,
                                                real_input_str,
                                                chain_expected_exception,
                                                p_state.action_compatibility
                                            )
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
                                -- A recent absorbed phase already consumed the pending expected step.
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
                                CharacterRules.get_exception(p_state.exceptions, common_exceptions, expected.id),
                                trace_prev_step,
                                real_input_str
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
                            elseif replay_dash_retrigger.ignored then
                                match_probe.branch = "replayed_previous_dash_retrigger_ignored"
                                match_probe.reject_reason = nil
                                match_probe.ignored_as_previous_step_residue = true
                                DebugTrace.record_match_probe(trial_state, match_probe)
                            elseif action_match.matched and expected
                                and Validator.requires_block_outcome(expected)
                                and not (demo_state and demo_state.is_playing) then
                                -- 演示回放以录制的输入事实为准，被防接触由运行审计的
                                -- block_contacts 统计独立校验，不再等待 15 帧防御确认。
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
                            elseif action_match.matched and expected then
                                local repeat_prev = trial_state.current_step > 1
                                    and trial_state.sequence[trial_state.current_step - 1] or nil
                                local repeat_contact_gate =
                                    ActionRestartDetector.evaluate_playback_light_repeat_contact_gate({
                                        expected_id = expected.id,
                                        expected_motion = expected.motion,
                                        expected_combo = expected.expected_combo,
                                        previous_id = repeat_prev and repeat_prev.id or nil,
                                        previous_motion = repeat_prev and repeat_prev.motion or nil,
                                        previous_expected_combo = repeat_prev
                                            and repeat_prev.expected_combo or nil,
                                        previous_has_hit = repeat_prev and repeat_prev.has_hit == true,
                                        current_combo = _pf.current_combo or 0,
                                    })
                                if repeat_contact_gate.required then
                                    match_probe.branch = "same_action_light_repeat_contact_pending"
                                    match_probe.repeat_contact_gate = repeat_contact_gate
                                    local stored = ComboTrialsModules.PendingAbsorb.store(
                                        pending_absorb_ctx,
                                        expected,
                                        {
                                            block_reason = "combo_not_reached",
                                            allow_pending_absorb = true,
                                            actual_action_id = act_id,
                                            match_reason = action_match.match_reason,
                                            source = "same_action_light_repeat_contact",
                                        },
                                        match_probe,
                                        process_act.current_hp
                                    )
                                    match_probe.pending_current_absorb_created = stored == true
                                    if stored then
                                        DebugTrace.record_match_probe(trial_state, match_probe)
                                    else
                                        match_probe.branch = "same_action_light_repeat_contact_pending_fallback"
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
                                    end
                                else
                                    match_probe.branch = process_act.synthetic and "same_dash_fallback" or "direct_match"
                                    match_probe.repeat_contact_gate = repeat_contact_gate
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
                                end
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
                                    -- Pressure/setup tails validate the real
                                    -- recorded Action, but never require that
                                    -- terminal Action to hit or be blocked.
                                    match_probe.branch = "pressure_tail_wait_for_action"
                                    match_probe.reject_reason = "pressure_tail_action_mismatch_wait"
                                    DebugTrace.record_match_probe(trial_state, match_probe)
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
                local current_absorb = input_truth_mode
                    and CharacterRules.match_current_canonical_confirmation(
                        p_state.exceptions,
                        common_exceptions,
                        expected,
                        act_id,
                        _pf.current_combo or 0,
                        p_state.profile_name
                    )
                    or CharacterRules.match_current_absorb_confirmation(
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
                        set_dummy_counter_type = ComboTrialsModules.DummySettings.set_counter_type,
                        d2d_cfg = d2d_cfg,
                        file_system = file_system,
                        act_id_reverse_enum = ComboTrialsModules.GameProbe.act_id_reverse_enum
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
                _ct_player_input_transition = unified_command_status == "player_input_transition",
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
-- TRIAL SUCCESS/FAIL: completion marking, auto-advance, auto-retry
-- Keep helpers on ctx to avoid adding main-chunk locals.
-- =========================================================
ctx.advance_to_next_trial = function()
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

ctx.handle_trial_auto_flow = function()
    if trial_state.is_playing and not (demo_state and demo_state.is_playing) then
        if (trial_state.fail_timer or 0) > 0 then
            ctx.finish_trial_telemetry_attempt("fail", trial_state.fail_reason)
        elseif (trial_state.success_timer or 0) > 0 then
            ctx.finish_trial_telemetry_attempt("success")
        end
    end

    if not trial_state.is_playing or (demo_state and demo_state.is_playing) then
        if demo_state and demo_state.is_playing then
            -- Demo playback drives the same validation pipeline, and the
            -- finished steps survive quitting the demo, which can trigger
            -- a success banner afterwards. Taint the attempt so a
            -- demo-driven finish never counts as completed; any manual
            -- reset/restart clears this via clear_trial_attempt_state.
            trial_state._attempt_had_demo = true
        end
        trial_state._success_latched = false
        trial_state._auto_next_countdown = nil
        return
    end

    -- AUTO-RETRY ON FAIL: when the fail banner finishes, the vanilla
    -- flow sets manual_reset_pending and waits for a manual reset.
    -- Perform the same reset automatically (mirrors the reset button:
    -- reset_trial_steps clears manual_reset_pending, so this fires once).
    if d2d_cfg.auto_retry_on_fail ~= false
        and trial_state.manual_reset_pending
        and #trial_state.sequence > 0
        and (trial_state.fail_timer or 0) == 0
        and (trial_state.success_timer or 0) == 0 then
        reset_trial_steps()
        ct_ticker("失败，自动重试")
        return
    end

    -- Latch the first frame of the success banner: record completion once.
    -- A demo-tainted attempt gets neither the completion mark nor the
    -- auto-advance - only manual play counts.
    if (trial_state.success_timer or 0) > 0 and not trial_state._success_latched then
        trial_state._success_latched = true
        -- Success is terminal until an explicit reset, restart or trial switch.
        -- Discard delayed validators so post-success inputs cannot overwrite
        -- the completed final line with a failure.
        trial_state._step1_wrong_pending = false
        trial_state.active_universal_hold = nil
        trial_state._pending_hit_cc = nil
        trial_state._pending_hit_delay = nil
        trial_state._hit_grace = 0
        ComboTrialsModules.PendingAbsorb.clear(trial_state, "trial_success_locked")
        if not trial_state._attempt_had_demo then
            local path = trial_state.current_file_path or trial_state.current_file
            if file_system.mark_trial_completed(path) then
                if file_system.mark_combo_display_completed then
                    file_system.mark_combo_display_completed(path)
                end
            end
            if d2d_cfg.auto_next_trial ~= false then
                trial_state._auto_next_countdown = d2d_cfg.fail_display_frames or 120
            end
        end
    end

    -- Advance on our own countdown while validation remains terminally locked.
    -- Keep _success_latched set if advancing fails (last file in the list);
    -- a successful advance resets it via clear_trial_attempt_state.
    if trial_state._auto_next_countdown then
        trial_state._auto_next_countdown = trial_state._auto_next_countdown - 1
        if trial_state._auto_next_countdown <= 0 then
            trial_state._auto_next_countdown = nil
            ctx.advance_to_next_trial()
        end
    end
end

ctx.observe_runtime_action_truth = function(p_idx)
    local session = nil
    if trial_state.is_recording and p_idx == trial_state.recording_player then
        session = trial_state._action_event_session
    elseif demo_state.transcription_run
        and demo_state.transcription_run.active == true and p_idx == 0 then
        session = demo_state.transcription_run.session
    end
    if type(session) ~= "table" then return end

    local actor_hp, actor_drive, actor_super = nil, nil, nil
    local victim_hp, victim_damage_type, victim_hit_stop = nil, 0, 0
    pcall(function() actor_hp = tonumber(_pf.p_char and _pf.p_char.vital_new) end)
    pcall(function() actor_drive = tonumber(_pf.p_char and _pf.p_char.focus_new) end)
    pcall(function()
        local team = _td_gBattle:get_field("Team"):get_data(nil)
        actor_super = tonumber(team and team.mcTeam
            and team.mcTeam[p_idx] and team.mcTeam[p_idx].mSuperGauge)
    end)
    pcall(function() victim_hp = tonumber(_pf.victim_obj and _pf.victim_obj.vital_new) end)
    pcall(function()
        victim_damage_type = tonumber(
            _pf.victim_obj and _pf.victim_obj:get_field("damage_type")
        ) or 0
    end)
    pcall(function()
        local reader = _G.CTRecordingRepeat
            and _G.CTRecordingRepeat.read_live_hit_stop
        if type(reader) == "function" then
            victim_hit_stop = tonumber(reader(_pf.victim_obj)) or 0
        end
    end)
    local event_count_before = #session.events
    pcall(ComboTrialsModules.ActionEventCompiler.observe, session, {
        frame = engine_frame_count,
        action_id = _pf.act_id,
        action_frame = _pf.act_frame,
        direct_input = _pf.direct_input,
        direction_input = _pf.direction_input,
        facing_right = _pf.facing_right,
        combo_count = _pf.current_combo,
        actor_hp = actor_hp,
        actor_drive = actor_drive,
        actor_super = actor_super,
        victim_hp = victim_hp,
        victim_damage_type = victim_damage_type,
        victim_hit_stop = victim_hit_stop,
    })
    if trial_state.is_recording and p_idx == trial_state.recording_player then
        ctx.refresh_recording_preview(session)
    end
    if trial_state.is_recording and p_idx == trial_state.recording_player
        and event_count_before == 0 and #session.events > 0
        and trial_state.first_action_pos_p1 == nil then
        trial_state.first_action_pos_p1,
            trial_state.first_action_pos_p2,
            trial_state.first_action_pos_p1_raw,
            trial_state.first_action_pos_p2_raw = capture_current_positions()
    end
end

-- =========================================================
-- MAIN ON_FRAME — ORCHESTRATOR
-- =========================================================
re.on_frame(function()
    file_system.diag_frame = (file_system.diag_frame or 0) + 1
    file_system.diag_runtime_allowed = is_combo_trials_runtime_allowed()
    if file_system.diag_last_runtime_allowed ~= file_system.diag_runtime_allowed then
        file_system.diag_last_runtime_allowed = file_system.diag_runtime_allowed
        local rs = _G.SF6CC_RuntimeSafety or {}
        local gate_message = "runtime allowed=" .. tostring(file_system.diag_runtime_allowed)
            .. " mode=" .. tostring(_G.CurrentTrainerMode)
            .. " battlehub=" .. tostring(_G.IsInBattleHub)
            .. " flow=" .. tostring(_G.FlowMapID)
            .. " reason=" .. tostring(rs.reason)
            .. " battle_input=" .. tostring(rs.battle_input_type)
            .. " online=" .. tostring(rs.in_online_battle)
            .. " renderer=" .. tostring(_G.ComboTrialsD2DEnabled)
        RuntimeSafety.trace(gate_message, "ComboTrialsGate")
        file_system.diag_log(gate_message)
    end

    file_system.idle_prewarm_combo_mode()
    if not ct_handle_runtime_scene_gate() then
        return
    end
    local _in_replay = RuntimeSafety.is_replay_allowed()
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
    if trial_state._runtime_auditing then
        DebugTrace.record_visual_step_state(trial_state, {
            frame = _frame_now,
            validation_step = trial_state.current_step or 0,
            visual_step = _visual_step,
            hold_step = trial_state._ui_step_hold_step,
            hold_until_frame = trial_state._ui_step_hold_until_frame,
        })
    end
    _G.ComboTrials_CurrentFile = _fname:match("([^/\\]+)$") or _fname
    _G.ComboTrials_CurrentStep = _visual_step
    _G.ComboTrials_ValidationStep = trial_state.current_step or 0
    _G.ComboTrials_TotalSteps = trial_state.sequence and #trial_state.sequence or 0
    _G.ComboTrials_IsPlaying = trial_state.is_playing or false
    _G.ComboTrials_IsRecording = trial_state.is_recording or false
    _G.ComboTrials_IsDemo = (demo_state and demo_state.is_playing) or false
    _G.ComboTrials_IsAutoDemo = (demo_state and demo_state.playlist_active) or false
    _G.ComboTrials_AutoDemoIndex = (demo_state and demo_state.playlist_index) or 0
    _G.ComboTrials_AutoDemoTotal = (demo_state and demo_state.playlist_total) or 0
    _G.ComboTrials_FileList = _display or {}
    _G.ComboTrials_FileIdx = _fidx
    _G.ComboTrials_PositionIdx = d2d_cfg.forced_position_idx or 1

    -- BATTLE HUB SPECTATE: script disabled

    if _G.IsInBattleHub then return end

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

    if not _in_replay then ct_dev_hp_restore_test_tick() end

    if _G.CurrentTrainerMode ~= 4 then ct_auto_refresh_combo_list(); ct_handle_mode_exit(); return end

    ct_auto_refresh_combo_list()
    ct_poll_trialhub_sync_signal()
    ct_handle_first_frame_init(_in_replay)
    _G.ComboTrials_HideNativeHUD = false

    local is_game_paused = GS.in_pause_menu
    ct_handle_pause_positions(is_game_paused, _in_replay)
    if is_game_paused then return end

    engine_frame_count = engine_frame_count + 1
    trial_state._engine_frame_count = engine_frame_count
    trial_state._demo_timing_ui_baseline = (demo_state and demo_state.is_playing == true) or false
    logger_process_game_state()
    if not _in_replay and ctx.handle_trial_auto_flow then ctx.handle_trial_auto_flow() end

    if trial_state.is_recording then
        if not trial_state._rec_frame_count then trial_state._rec_frame_count = 0 end
        trial_state._rec_frame_count = trial_state._rec_frame_count + 1
        if not trial_state._piyo_detected then
            pcall(_ct_detect_piyo)
        end
    end


    ct_handle_playing_transition(_in_replay)
    ct_handle_position_correction(_in_replay)

    local gBattle = _td_gBattle
    if not gBattle then return end
    _pf.cmd_obj = gBattle:get_field("Command"):get_data(nil)
    if not _pf.cmd_obj then return end
    if not GS.sP then return end

    if not _in_replay then ct_handle_hp_injection() end

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
                p_state.trigger_cache_built = false
                p_state._trigger_cache_build = nil
            end
        end
        if not p_state.trigger_cache_built then ComboTrialsModules.GameProbe.build_bcm_trigger_cache(p_idx) end

        _pf.act_id, _pf.act_frame, _pf.flags, _pf.action_code, _pf.direct_input,
            _pf.b_type, _pf.direction_input, _pf.facing_right = ComboTrialsModules.GameProbe.get_action_data(_pf.p_char)
        _pf.current_combo = ComboTrialsModules.GameProbe.get_combo_count(_pf.p_char)
        _pf.victim_idx = 1 - p_idx
        _pf.victim_obj = (_pf.victim_idx == 0) and GS.p1 or GS.p2
        ctx.observe_runtime_action_truth(p_idx)

        if trial_state._transcribing == true then
            p_state.last_combo_count = _pf.current_combo
            goto ct_next_player
        end
        if trial_state.is_recording then
            -- Keep only result/gauge sampling from the legacy pipeline. Step
            -- admission, command lookup, exception learning and charge mutation
            -- are intentionally bypassed for new recordings.
            if p_idx == trial_state.recording_player then
                ct_player_tracking(p_idx, p_state)
            end
            p_state.last_combo_count = _pf.current_combo
            goto ct_next_player
        end

        -- Once manual play reaches success, freeze the validation pipeline.
        -- The banner timer may expire, but _success_latched remains true until
        -- clear_trial_attempt_state starts a fresh attempt.
        local trial_success_locked = trial_state.is_playing
            and p_idx == trial_state.playing_player
            and not (demo_state and demo_state.is_playing)
            and ((trial_state.success_timer or 0) > 0 or trial_state._success_latched == true)
        if trial_success_locked then
            p_state.last_combo_count = _pf.current_combo
            goto ct_next_player
        end

        ct_player_tracking(p_idx, p_state)
        ct_player_validation(p_idx, p_state)
        ct_player_hold_charge(p_state)
        local actions_to_process = ct_player_input_buffer(p_state)
        ct_player_process_actions(p_idx, p_state, actions_to_process)
        ct_player_universal_hold(p_idx, p_state)

        p_state.last_combo_count = _pf.current_combo
        ::ct_next_player::
    end
    if ctx.tick_transcription then ctx.tick_transcription() end
    if trial_state._transcribing ~= true
        and (trial_state.success_timer or 0) <= 0
        and trial_state._success_latched ~= true then
        ComboTrialsModules.PendingAbsorb.sync_failure_ui_result(trial_state)
    end
end)




function save_trial_sequence(meta)
    if #trial_state.sequence == 0 then return end
    local rec_p = trial_state.recording_player
    local char_name = players[rec_p].profile_name

    local p_state = players[rec_p]
    if #trial_state.sequence > 0 then
        if trial_state._recording_compiler_used ~= true and #p_state.log > 0 then
            local last_step = trial_state.sequence[#trial_state.sequence]
            for _, log_entry in ipairs(p_state.log) do
                if log_entry.trial_step_idx == #trial_state.sequence then
                    last_step.expected_combo = log_entry.combo_count or 0
                    break
                end
            end

            -- Legacy-only presentation tag. Input-compiled steps retain their
            -- neutral motion notation and express contact through V2 fields.
            if not last_step.has_hit and not last_step.has_contact
                and (last_step.expected_combo or 0) == 0 then
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
        local compiled_stats = type(trial_state._last_action_compile) == "table"
            and trial_state._last_action_compile.stats or {}
        local stats = {
            hit_type = trial_state._rec_hit_type,
            damage = tonumber(compiled_stats.damage) or 0,
            drive_used = tonumber(compiled_stats.drive_used) or 0,
            super_used = tonumber(compiled_stats.super_used) or 0,
        }
        if init then
            stats.damage     = math.max(0, init.victim_hp - (init.min_victim_hp or init.victim_hp))
            stats.drive_used = math.max(0, init.attacker_drive - (init.min_atk_drive or init.attacker_drive))
            stats.super_used = math.max(0, init.attacker_super - (init.min_atk_super or init.attacker_super))
        end
        trial_state.sequence[1].combo_stats = stats
        if logger_state.last_export_name then
            trial_state.sequence[1].raw_input_file = logger_state.last_export_name
        end
        trial_state._rec_gauges = nil
        trial_state._rec_hit_type = nil
    end

    if type(meta) == "table" and type(trial_state.sequence[1]) == "table" then
        local scene_state = trial_state._rec_scene_state or unique_resources.capture_scene_state(rec_p)
        if type(scene_state) == "table" then
            trial_state.sequence[1].scene_state = scene_state
        end
        local environment = trial_state._rec_environment
        if type(environment) == "table" then
            trial_state.sequence[1].dummy_stance = environment.dummy_stance
            for _, field_name in ipairs(
                ComboTrialsModules.TrainingEnvironment.OPTIONAL_FIELDS
            ) do
                trial_state.sequence[1][field_name] = environment[field_name]
            end
        end
        trial_state.sequence[1]._xt_meta = apply_recording_environment_to_meta(meta)
        if type(trial_state._raw_rec_buffer) == "table" and #trial_state._raw_rec_buffer > 0 then
            -- New recordings keep a portable, facing-relative raw stream.
            -- The timeline remains alongside it so older WTT builds that do
            -- not know this extension can continue replaying the JSON.
            RawInputCodec.invalidate_stream_cache(trial_state.sequence[1])
            trial_state.sequence[1].relative_raw_inputs =
                trial_state._raw_rec_buffer
            trial_state.sequence[1].raw_inputs = nil
            trial_state.sequence[1]._xt_meta.input_stream =
                RawInputCodec.describe_relative_stream()
        end
    end
    -- Counter state is a fixed training-menu rule for the entire recording.
    normalize_sequence_counter_types(trial_state.sequence, false)

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

    assign_groups(trial_state.sequence, char_name)
    json.dump_file(path, trial_state.sequence)
    trial_state._raw_rec_buffer = {}
    trial_state._recording_compiler_used = false
    trial_state._last_action_compile = nil
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
    local paths = (player_idx == 0) and file_system.saved_combos_paths_p1 or file_system.saved_combos_paths_p2
    local idx = (player_idx == 0) and (file_system.selected_file_idx_p1 or 1) or (file_system.selected_file_idx_p2 or 1)
    local path = paths and paths[idx] or nil
    if path and load_combo_from_file(path, true) then
        start_trial(player_idx)
    elseif #trial_state.sequence > 0 then
        trial_state.is_playing = true
        trial_state.playing_player = player_idx
        reset_trial_steps()
    end
end
-- =========================================================
-- DEMO ENGINE LOGIC & EXPORTS
-- =========================================================
local function parse_timeline_line(line)
    if type(line) ~= "string" then return nil end
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

function CTJsonInterop.normalize_raw_inputs(raw_inputs)
    return RawInputCodec.normalize_stream(raw_inputs)
end

function CTJsonInterop.select_transcription_input(first_step, runtime_audit)
    return RawInputCodec.select_transcription_stream(
        first_step,
        runtime_audit
    )
end

CTStunDemoRuntime = CTStunDemoRuntime or {}

function CTStunDemoRuntime.needs_state_restore()
    local first = trial_state.sequence and trial_state.sequence[1]
    if type(first) ~= "table" then return false end
    return first.has_piyo == true
        or type(first.scene_state) == "table"
end

function CTStunDemoRuntime.needs_timeline_catch_up()
    local first = trial_state.sequence and trial_state.sequence[1]
    if type(first) ~= "table" then return false end

    -- Timeline catch-up is a legacy workaround for stun/burnout sequences
    -- whose input hook genuinely runs fewer times during the wall-stun state.
    -- A portable scene snapshot also needs restoration, but must not opt an
    -- ordinary combo into catch-up: doing so consumes inputs during hitstop.
    return ComboTrialsModules.SceneState.requires_timeline_catch_up(first)
end

function CTStunDemoRuntime.restore_pre_demo_state()
    if not CTStunDemoRuntime.needs_state_restore() then return false end

    local first = trial_state.sequence and trial_state.sequence[1]
    return ComboTrialsModules.SceneStateRuntime.apply(
        first,
        trial_state.playing_player,
        trial_state,
        false
    )
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
    if not CTStunDemoRuntime.needs_timeline_catch_up() then return 0 end
    local now_frame = engine_frame_count or 0
    local last_frame = demo_state._last_tick_frame
    if type(last_frame) ~= "number" then return 0 end

    local missed = now_frame - last_frame - 1
    if missed <= 0 then return 0 end
    return CTStunDemoRuntime.advance_timeline_frames(missed)
end

local function start_demo(opts)
    opts = opts or {}
    if opts.transcribe == true
        and (not demo_state.transcription_run
            or demo_state.transcription_run.active ~= true) then
        return false
    end
    if opts.playlist_start == true and trial_state.is_recording then return false end
    if opts.playlist_start == true then
        if file_system.refresh_combo_list_preserve_selection then
            file_system.refresh_combo_list_preserve_selection(false)
        end
        ctx.stop_demo_playback(
            "playlist_start",
            demo_state.current_file_path or trial_state.current_file_path or trial_state.current_file,
            nil,
            true,
            true
        )
        demo_state.playlist_active = true
        demo_state.playlist_index = 0
        demo_state.playlist_total = #(file_system.saved_combos_paths_p1 or {})
        demo_state.playlist_pending_next = false
        return start_demo({ playlist_next = true })
    elseif opts.playlist_next == true then
        local paths = file_system.saved_combos_paths_p1 or {}
        local idx = math.max(1, (demo_state.playlist_index or 0) + 1)
        local loaded = false
        while idx <= #paths do
            demo_state.playlist_loading = true
            file_system.selected_file_idx_p1 = idx
            loaded = load_combo_from_file(paths[idx], true)
            demo_state.playlist_loading = false
            if loaded then break end
            idx = idx + 1
        end
        if not loaded then
            ctx.stop_demo_playback(
                "playlist_complete",
                demo_state.current_file_path or trial_state.current_file_path or trial_state.current_file,
                nil,
                true,
                false
            )
            trial_state.is_playing = false
            return false
        end
        demo_state.playlist_active = true
        demo_state.playlist_index = idx
        demo_state.playlist_total = #paths
        demo_state.playlist_pending_next = false
        opts.keep_playlist = true
    end
    if opts.keep_playlist ~= true then
        demo_state.playlist_active = false
        demo_state.playlist_index = 0
        demo_state.playlist_total = 0
        demo_state.playlist_pending_next = false
        demo_state.playlist_loading = false
    end
    if not trial_state.sequence or #trial_state.sequence == 0 then return false end
    local first_stun_step = trial_state.sequence[1]
    local input_stream, input_source =
        RawInputCodec.select_stream(first_stun_step)
    local timeline = type(first_stun_step) == "table" and first_stun_step.timeline or nil
    local has_usable_timeline = RawInputCodec.has_usable_timeline(timeline)
    local input_mode_mismatch = false
    if input_stream then
        input_mode_mismatch =
            CTJsonInterop.warn_control_mode_mismatch(trial_state.sequence, 0)
    end
    local force_timeline_capture = opts.transcribe == true
        and demo_state.transcription_run
        and demo_state.transcription_run.input_source == "timeline"
        and has_usable_timeline
    local strict_selected_stream = opts.transcribe == true
        and demo_state.transcription_run
        and demo_state.transcription_run.input_source ~= "timeline"
    local use_input_stream = input_stream ~= nil
        and not force_timeline_capture
        and not (not strict_selected_stream
            and input_mode_mismatch
            and has_usable_timeline)
    if opts.transcribe == true and demo_state.transcription_run then
        local run = demo_state.transcription_run
        local previous_source = run.input_source
        local resolved_source = use_input_stream and input_source or "timeline"
        run.input_source = resolved_source
        if resolved_source == "timeline" and previous_source ~= "timeline" then
            -- Never append a timeline capture to a preloaded raw stream.
            run.captured_raw_inputs = {}
        end
        if run.phase == "capture" then
            run.capture_input_source = resolved_source
        end
    end
    local manual_stun_demo_required = type(first_stun_step) == "table"
        and first_stun_step.has_piyo == true
        and not use_input_stream
        and not ComboTrialsModules.SceneState.defender_is_burnout(first_stun_step)
    if manual_stun_demo_required and opts.transcribe ~= true and not _G._allow_stun_demo then
        return false
    end

    if use_input_stream then
        demo_state.raw_buffer = input_stream
        demo_state.raw_input_source = input_source
        demo_state.sequence = {}
    else
        -- Legacy and cross-control-mode fallback: timeline stays a supported source.
        if not timeline then
            local raw_file = trial_state.sequence[1].raw_input_file
            if not raw_file then print("[ComboTrials] No raw_inputs, timeline or raw_input_file!"); return false end

            local loaded = json.load_file("TrainingComboTrials_data/ReplayRecords/" .. raw_file)
            if not loaded or not loaded.timeline then print("[ComboTrials] Failed to load ReplayRecord"); return false end
            timeline = loaded.timeline
        end

        demo_state.raw_buffer = nil
        demo_state.raw_input_source = nil
        demo_state.sequence = {}
        for _, line in ipairs(timeline) do
            local parsed = parse_timeline_line(line)
            if parsed then table.insert(demo_state.sequence, parsed) end
        end
        if #demo_state.sequence == 0 then return false end
    end

    -- Force Trial mode to stay active on P1
    invalidate_recording_display_context()
    trial_state.is_recording = false
    ctx.reset_recording_preview()
    trial_state._raw_rec_active = false
    trial_state.is_playing = true
    trial_state.playing_player = 0
    -- Transcription observes Action truth without running the legacy trial
    -- matcher. Runtime audit still captures through the same replay plumbing,
    -- but must exercise the normal training UI validation pipeline.
    local runtime_audit = opts.transcribe == true
        and demo_state.transcription_run
        and demo_state.transcription_run.mode == "runtime_audit"
    trial_state._transcribing = opts.transcribe == true
        and runtime_audit ~= true
    trial_state._runtime_auditing = runtime_audit == true
    
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
    demo_state.countdown = tonumber(opts.countdown_frames or 10) or 10
    demo_state.current_frame = 0
    demo_state.current_step = 1
    demo_state.p1_mask = 0
    demo_state.play_index = 1
    demo_state._last_tick_frame = nil
    demo_state._state_reinjected = false
    demo_state._total_frames = 0
    demo_state._piyo_waiting = false
    demo_state._piyo_triggered = false
    demo_state.transcribing = opts.transcribe == true
    demo_state._transcription_input_finished = false
    demo_state._transcription_capture_frame = false
    demo_state.current_file = trial_state.current_file
    demo_state.current_file_path = trial_state.current_file_path
    demo_state.current_file_name = trial_state.current_file_name
    if opts.transcribe ~= true then ctx.begin_trial_telemetry_attempt("auto_demo") end

    print("[ComboTrials] " .. (opts.transcribe == true and "TRANSCRIBE" or "DEMO")
        .. " Started" .. (use_input_stream
            and (input_source == RawInputCodec.RELATIVE_FIELD
                and " (RAW facing-relative)" or " (RAW native)")
            or " (LEGACY timeline)"))
    return true
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

ctx.persist_transcription_report = nil

ctx.transcription_item = function(path, status, details)
    details = type(details) == "table" and details or {}
    local is_runtime_audit = details.audit_mode == "runtime_audit"
    local replay_verified = nil
    local raw_replay_verified = nil
    local timeline_replay_verified = nil
    if is_runtime_audit then
        replay_verified = details.replay_verified == true
        if details.input_source == "timeline" then
            timeline_replay_verified = replay_verified
        elseif details.input_source == "raw_inputs"
            or details.input_source == RawInputCodec.RELATIVE_FIELD then
            raw_replay_verified = replay_verified
        end
    else
        raw_replay_verified = details.raw_replay_verified == true
    end
    local item = {
        source_file = path,
        source_name = tostring(path or ""):match("([^/\\]+)$") or tostring(path or ""),
        status = status,
        input_source = details.input_source,
        candidate_file = details.candidate_file,
        reasons = details.reasons or {},
        advisories = details.advisories or {},
        suspected_causes = details.suspected_causes or {},
        expected = details.expected,
        capture_expected = details.capture_expected,
        observed = details.observed,
        capture_observed = details.capture_observed,
        capture_advisories = details.capture_advisories,
        capture_source_action_match = details.capture_source_action_match,
        verification_observed = details.verification_observed,
        environment_validation = details.environment_validation,
        capture_environment_validation =
            details.capture_environment_validation,
        verification_environment_validation =
            details.verification_environment_validation,
        environment_adjustments = details.environment_adjustments,
        raw_input_count = details.raw_input_count,
        replay_input_count = details.replay_input_count,
        action_trace = details.action_trace,
        verification_action_trace = details.verification_action_trace,
        action_comparison = details.action_comparison,
        trial_completion = details.trial_completion,
        runtime_step_trace = details.runtime_step_trace,
        command_display_validation = details.command_display_validation,
        replay_verified = replay_verified,
        raw_replay_verified = raw_replay_verified,
        timeline_replay_verified = timeline_replay_verified,
        audit_mode = details.audit_mode,
        validation_revision =
            details.audit_mode == "runtime_audit"
                and ComboTrialsModules.RuntimeAuditor.VALIDATION_REVISION
                or ComboTrialsModules.Transcriber.VALIDATION_REVISION,
    }
    local run = demo_state.transcription_run
    run.items[#run.items + 1] = item
    if status == "passed" then
        run.passed = run.passed + 1
    else
        run.failed = run.failed + 1
    end
    if ctx.persist_transcription_report then ctx.persist_transcription_report(run) end
    return item
end

ctx.create_transcription_directories = function(run)
    if not fs or not fs.create_dir then return end
    pcall(fs.create_dir, "TrainingComboTrials_data")
    if run.mode == "runtime_audit" then
        pcall(fs.create_dir, ComboTrialsModules.RuntimeAuditor.REPORT_ROOT)
        return
    end
    pcall(fs.create_dir, ComboTrialsModules.Transcriber.OUTPUT_ROOT)
    pcall(fs.create_dir, ComboTrialsModules.Transcriber.OUTPUT_ROOT .. "/" .. run.character)
    pcall(fs.create_dir, run.output_dir)
    pcall(fs.create_dir, ComboTrialsModules.Transcriber.REPORT_ROOT)
end

ctx.persist_transcription_report = function(run)
    if not run or not run.report_path then return false end
    local report = run.mode == "runtime_audit"
        and ComboTrialsModules.RuntimeAuditor.report(run)
        or ComboTrialsModules.Transcriber.report(run)
    local ok, result = pcall(
        json.dump_file,
        run.report_path,
        report
    )
    if not ok or result == false then
        run.report_error = ok and "json.dump_file returned false" or tostring(result)
        return false
    end
    run.report_error = nil
    return true
end

ctx.read_transcription_environment = function()
    local action = ct_read_dummy_action_settings()
    local counter = ct_read_dummy_counter_settings()
    local guard = ct_read_dummy_guard_settings()
    return {
        dummy_action_type = tonumber(action.action_type),
        dummy_counter_type = tonumber(counter.counter_type),
        dummy_guard_type = tonumber(guard.guard_type),
        dummy_guard_count = tonumber(guard.guard_count),
        counter_runtime = counter,
        guard_runtime = guard,
        action_runtime = action,
    }
end

ctx.reset_transcription_environment = function()
    pcall(restore_trial_vital)
    pcall(function() unique_resources.restore() end)
    pcall(restore_trial_defense_settings)
    pcall(ComboTrialsModules.DummySettings.restore_counter_type)
    pcall(ComboTrialsModules.DummySettings.restore_guard_type)
    pcall(ComboTrialsModules.DummySettings.restore_action_type)
    pcall(reset_positions_to_default)
    pcall(function()
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        if tm then tm._IsReqRefresh = true end
    end)
end

ctx.finish_transcription_run = function(canceled)
    local run = demo_state.transcription_run
    if not run then return false end
    local is_audit = run.mode == "runtime_audit"
    run.cancel_requested = canceled == true or run.cancel_requested == true
    run.active = false
    run.finished_at = CTJsonInterop.iso8601_now()
    run.status = run.fatal_error
        and ((is_audit and "审计" or "转录") .. "已停止：" .. tostring(run.fatal_error))
        or (run.cancel_requested and "已取消，报告已生成"
            or (is_audit and "运行目录审计完成" or "转录完成"))
    trial_state._transcribing = false
    trial_state._runtime_auditing = false
    demo_state.transcribing = false
    demo_state._transcription_input_finished = false
    if demo_state.is_playing then
        ctx.stop_demo_playback(
            run.cancel_requested and "transcription_canceled" or "transcription_complete",
            demo_state.current_file_path or trial_state.current_file_path or trial_state.current_file,
            nil,
            true
        )
    end
    ctx.reset_transcription_environment()
    run.pending_next = false
    run.pending_next_frame = nil

    ctx.create_transcription_directories(run)
    if not ctx.persist_transcription_report(run) then
        run.status = "转录结束，但报告写入失败：" .. tostring(run.report_error)
    end

    if run.return_path then pcall(load_combo_from_file, run.return_path, true) end
    ct_ticker(string.format(
        "%s%s：成功 %d，需处理 %d",
        is_audit and "运行审计" or "转录",
        run.cancel_requested and "已取消" or "完成",
        run.passed,
        run.failed
    ))
    return true
end

ctx.complete_transcription_item = function(run, evaluation, details)
    details = type(details) == "table" and details or {}
    evaluation = type(evaluation) == "table" and evaluation or {}
    evaluation.reasons = type(evaluation.reasons) == "table"
        and evaluation.reasons or { "transcription_evaluation_missing" }
    evaluation.suspected_causes =
        type(evaluation.suspected_causes) == "table"
        and evaluation.suspected_causes or {}
    if not evaluation.ok and #evaluation.suspected_causes == 0 then
        evaluation.suspected_causes =
            ComboTrialsModules.Transcriber.suspected_causes(
                run.current_source,
                run.transcription_rules
            )
    end
    local final_is_verification =
        run.phase == "verify_raw" or run.phase == "audit_replay"
    local capture_environment_validation =
        run.capture_evaluation
            and run.capture_evaluation.environment_validation or nil
    if capture_environment_validation == nil and not final_is_verification then
        capture_environment_validation = evaluation.environment_validation
    end
    local verification_environment_validation =
        details.verification_environment_validation
    if verification_environment_validation == nil and final_is_verification then
        verification_environment_validation = evaluation.environment_validation
    end
    ctx.transcription_item(run.current_path, evaluation.ok and "passed" or "failed", {
        input_source = run.capture_input_source or run.input_source,
        candidate_file = details.candidate_file,
        reasons = evaluation.reasons,
        advisories = evaluation.advisories,
        suspected_causes = evaluation.suspected_causes,
        expected = evaluation.expected,
        capture_expected = run.capture_evaluation
            and run.capture_evaluation.expected or nil,
        observed = evaluation.observed,
        capture_observed = run.capture_evaluation and run.capture_evaluation.observed or nil,
        capture_advisories =
            run.capture_evaluation and run.capture_evaluation.advisories or nil,
        capture_source_action_match =
            run.capture_evaluation and run.capture_evaluation.source_action_match or nil,
        verification_observed = details.verification_observed,
        environment_validation = evaluation.environment_validation,
        capture_environment_validation = capture_environment_validation,
        verification_environment_validation =
            verification_environment_validation,
        environment_adjustments = run.capture_environment_adjustments,
        raw_input_count = run.mode ~= "runtime_audit"
            and type(run.captured_raw_inputs) == "table"
            and #run.captured_raw_inputs or nil,
        replay_input_count = run.mode == "runtime_audit"
            and type(run.captured_raw_inputs) == "table"
            and #run.captured_raw_inputs or nil,
        action_trace = run.capture_compiled and run.capture_compiled.trace
            or (details.compiled and details.compiled.trace or nil),
        verification_action_trace = details.verification_action_trace,
        action_comparison = evaluation.action_comparison,
        trial_completion = evaluation.trial_completion,
        runtime_step_trace = evaluation.runtime_step_trace,
        command_display_validation = evaluation.command_display_validation,
        replay_verified = details.replay_verified,
        raw_replay_verified = details.raw_replay_verified == true,
        audit_mode = run.mode,
    })

    ctx.stop_demo_playback(
        "transcription_file_complete",
        demo_state.current_file_path or trial_state.current_file_path or trial_state.current_file,
        nil,
        true
    )
    trial_state.is_playing = false
    ctx.reset_transcription_environment()
    run.current_path = nil
    run.current_name = nil
    run.current_source = nil
    run.input_source = nil
    run.capture_input_source = nil
    run.input_finished_frame = nil
    run.session = nil
    run.captured_raw_inputs = nil
    run.phase = nil
    run.capture_compiled = nil
    run.capture_evaluation = nil
    run.capture_environment_adjustments = nil
    run.verification_candidate = nil
    if run.cancel_requested then return ctx.finish_transcription_run(true) end
    run.pending_next = true
    run.pending_next_frame = engine_frame_count or 0
    run.status = string.format(
        "正在重置%s环境 %d/%d",
        run.mode == "runtime_audit" and "审计" or "训练",
        run.index,
        run.total
    )
    return true
end

ctx.begin_raw_transcription_verification = function(run, candidate, compiled, evaluation)
    run.phase = "verify_raw"
    run.capture_input_source = run.input_source
    run.capture_compiled = compiled
    run.capture_evaluation = evaluation
    run.verification_candidate = candidate

    ctx.stop_demo_playback(
        "transcription_capture_complete",
        demo_state.current_file_path or trial_state.current_file_path or trial_state.current_file,
        run.current_path,
        true
    )
    trial_state.is_playing = false
    ctx.reset_transcription_environment()

    local verification_sequence =
        ComboTrialsModules.Transcriber.deep_copy(candidate)
    local loaded = ComboTrials_Files.load_combo_sequence(
        verification_sequence,
        run.current_path,
        true
    )
    if loaded then
        start_trial(0)
        local verification_inputs, verification_source =
            CTJsonInterop.select_transcription_input(candidate[1], true)
        run.input_source = verification_source
        run.captured_raw_inputs = verification_inputs or {}
        run.input_finished_frame = nil
        run.session = ctx.new_action_event_session(0, "transcription_raw_verify")
        run.status = string.format(
            "正在验证 raw input %d/%d：%s",
            run.index,
            run.total,
            run.current_name
        )
        if start_demo({ transcribe = true, countdown_frames = 20 }) then
            return true
        end
    end

    return ctx.complete_transcription_item(run, {
        ok = false,
        reasons = { "raw_replay_demo_start_failed" },
        suspected_causes =
            ComboTrialsModules.Transcriber.suspected_causes(
                run.current_source,
                run.transcription_rules
            ),
        expected = evaluation.expected,
        observed = {},
    }, {
        verification_observed = {},
    })
end

ctx.begin_guardless_transcription_retry = function(run, retry_source, adjustments)
    if not run or type(retry_source) ~= "table" then return false end

    ctx.stop_demo_playback(
        "transcription_guard_retry",
        demo_state.current_file_path or trial_state.current_file_path or trial_state.current_file,
        run.current_path,
        true
    )
    trial_state.is_playing = false
    ctx.reset_transcription_environment()

    run.current_source = retry_source
    run.capture_guard_retry_attempted = true
    run.input_finished_frame = nil
    run.phase = "capture"
    run.capture_compiled = nil
    run.capture_evaluation = nil
    run.verification_candidate = nil
    run.capture_environment_adjustments =
        type(run.capture_environment_adjustments) == "table"
            and run.capture_environment_adjustments or {}
    for _, adjustment in ipairs(type(adjustments) == "table" and adjustments or {}) do
        run.capture_environment_adjustments[#run.capture_environment_adjustments + 1] =
            adjustment
    end

    local replay_inputs, replay_source =
        CTJsonInterop.select_transcription_input(retry_source[1], false)
    run.input_source = replay_source
    run.capture_input_source = run.input_source
    run.captured_raw_inputs = replay_inputs or {}
    run.session = ctx.new_action_event_session(0, "transcription_guard_retry")
    run.status = string.format(
        "首次回放被防御截断，正在自动关闭防御重试 %d/%d：%s",
        run.index,
        run.total,
        run.current_name
    )

    local loaded = ComboTrials_Files.load_combo_sequence(
        ComboTrialsModules.Transcriber.deep_copy(retry_source),
        run.current_path,
        true
    )
    if loaded then
        start_trial(0)
        if start_demo({ transcribe = true, countdown_frames = 20 }) then
            return true
        end
    end
    return false
end

ctx.finish_current_transcription_file = function(timed_out)
    local run = demo_state.transcription_run
    if not run or run.active ~= true or type(run.current_source) ~= "table" then return false end

    local compiled = ctx.compile_action_event_session(run.session)
    local function runtime_action_ids_equivalent(expected_id, observed_id, index)
        local player_state = players[trial_state.playing_player or 0]
        local expected_step = type(run.current_source) == "table"
            and type(index) == "number" and run.current_source[index] or nil
        if type(expected_step) ~= "table"
            or tonumber(expected_step.id) ~= tonumber(expected_id) then
            expected_step = { id = expected_id }
        end
        local match_rule = CharacterRules.get_match_rule(
            player_state and player_state.exceptions or nil,
            common_exceptions,
            run.character,
            expected_id
        )
        return ActionMatcher.matches_expected_action_id(
            expected_step,
            observed_id,
            match_rule,
            player_state and player_state.action_compatibility or nil
        )
    end
    local function source_action_ids_equivalent(expected_id, observed_id, index)
        if runtime_action_ids_equivalent(expected_id, observed_id, index) then
            return true
        end
        local player_state = players[trial_state.playing_player or 0]
        local owner_id = CharacterRules.find_recording_absorb_owner(
            player_state and player_state.exceptions or nil,
            common_exceptions,
            observed_id
        )
        return tonumber(owner_id) == tonumber(expected_id)
    end
    if run.phase == "audit_replay" then
        local sequence_count = #(trial_state.sequence or {})
        local current_step = tonumber(trial_state.current_step) or 0
        local fail_timer = tonumber(trial_state.fail_timer) or 0
        local trial_completion = {
            completed = sequence_count > 0
                and current_step > sequence_count
                and fail_timer <= 0
                and trial_state.fail_reason == nil,
            current_step = current_step,
            total_steps = sequence_count,
            success_timer = tonumber(trial_state.success_timer) or 0,
            success_latched = trial_state._success_latched == true,
            fail_timer = fail_timer,
            fail_reason = trial_state.fail_reason,
        }
        local command_display_validation = nil
        if ComboTrials_Renderer
            and type(ComboTrials_Renderer.validate_sequence_command_display)
                == "function" then
            local validation_ok, validation_result = pcall(
                ComboTrials_Renderer.validate_sequence_command_display,
                type(trial_state.sequence) == "table"
                    and trial_state.sequence or run.current_source
            )
            if validation_ok and type(validation_result) == "table" then
                command_display_validation = validation_result
            else
                command_display_validation = {
                    ok = false,
                    status = validation_ok
                        and "invalid_validator_result" or "validator_error",
                    error = validation_ok and nil or tostring(validation_result),
                    unresolved = {},
                }
            end
        end
        local evaluation = ComboTrialsModules.RuntimeAuditor.evaluate(
            run.current_source,
            compiled,
            {
                replay_inputs = run.captured_raw_inputs,
                input_source = run.input_source,
                input_completed = run.input_finished_frame ~= nil,
                timed_out = timed_out == true,
                action_ids_equivalent = runtime_action_ids_equivalent,
                timing_tolerance = 2,
                trial_completed = trial_completion.completed,
                trial_completion = trial_completion,
                runtime_step_trace = {
                    confirmations = trial_state._step_confirmation_trace,
                    visual_steps = trial_state._visual_step_trace,
                    recent_match_probes = trial_state._match_probe_history,
                    last_auto_advance = trial_state._auto_advance_debug,
                    last_validation = trial_state._validation_debug,
                },
                character = run.character,
                command_display_validation = command_display_validation,
                verify_environment = true,
                environment_observed = ctx.read_transcription_environment(),
                transcription_rules = run.transcription_rules,
            }
        )
        return ctx.complete_transcription_item(run, evaluation, {
            candidate_file = run.current_path,
            compiled = compiled,
            verification_observed = evaluation.observed,
            verification_action_trace = compiled and compiled.trace or nil,
            replay_verified = evaluation.ok == true,
        })
    end
    if run.phase == "verify_raw" then
        local evaluation = ComboTrialsModules.Transcriber.verify_candidate(
            run.verification_candidate,
            compiled,
            {
                raw_inputs = run.captured_raw_inputs,
                input_source = run.input_source,
                input_completed = run.input_finished_frame ~= nil,
                timed_out = timed_out == true,
                action_ids_equivalent = runtime_action_ids_equivalent,
                timing_tolerance = 2,
                verify_environment = true,
                environment_observed = ctx.read_transcription_environment(),
            }
        )
        local candidate_path = nil
        local raw_replay_verified = false
        if evaluation.ok then
            ComboTrialsModules.Transcriber.mark_raw_replay_verified(
                run.verification_candidate,
                CTJsonInterop.iso8601_now()
            )
            candidate_path = run.output_dir .. "/" .. run.current_name
            local written, write_result = pcall(
                json.dump_file,
                candidate_path,
                run.verification_candidate
            )
            if not written or write_result == false then
                candidate_path = nil
                evaluation.ok = false
                evaluation.reasons[#evaluation.reasons + 1] =
                    "candidate_write_failed:" .. tostring(
                        written and "json.dump_file returned false" or write_result
                    )
            else
                raw_replay_verified = true
            end
        end

        return ctx.complete_transcription_item(run, evaluation, {
            candidate_file = candidate_path,
            verification_observed = evaluation.observed,
            verification_action_trace = compiled and compiled.trace or nil,
            raw_replay_verified = raw_replay_verified,
        })
    end

    local evaluation = ComboTrialsModules.Transcriber.evaluate(run.current_source, compiled, {
        input_source = run.input_source,
        raw_inputs = run.captured_raw_inputs,
        input_completed = run.input_finished_frame ~= nil,
        timed_out = timed_out == true,
        action_ids_equivalent = runtime_action_ids_equivalent,
        -- This bridge is used only to compare an old derived V2 source with
        -- current runtime truth. Generated candidates and their second raw
        -- replay continue to require the captured real Action ID.
        source_action_ids_equivalent = source_action_ids_equivalent,
        -- Legacy drive totals are not a stable replay oracle because Drive
        -- regenerates during a combo and old recorders used different sampling
        -- windows. The generated candidate is still checked strictly against
        -- its own second raw replay.
        compare_drive_usage = false,
        -- Old damage metadata may predate current burnout chip rules or may
        -- span a training-health refill. Accept drift only when every expected
        -- Action ID and the combo structure were reproduced exactly.
        allow_legacy_damage_drift = true,
        -- timeline/raw_inputs and the restored scene are the transcription
        -- facts. Old derived outcome fields may be rebuilt when current play
        -- adds hits, but a smaller maximum combo remains a hard failure.
        -- Every accepted capture must then survive an exact second raw replay.
        allow_legacy_outcome_rebuild = true,
        environment_adjustments = run.capture_environment_adjustments,
        verify_environment = true,
        environment_observed = ctx.read_transcription_environment(),
        transcription_rules = run.transcription_rules,
    })
    if type(run.capture_environment_adjustments) == "table" then
        for _, adjustment in ipairs(run.capture_environment_adjustments) do
            evaluation.advisories[#evaluation.advisories + 1] = string.format(
                "capture_environment_adjusted:%s:%s->%s:%s",
                tostring(adjustment.field),
                tostring(adjustment.from),
                tostring(adjustment.to),
                tostring(adjustment.reason)
            )
        end
    end
    if not evaluation.ok and run.capture_guard_retry_attempted ~= true then
        local retry_source, retry_adjustments =
            ComboTrialsModules.Transcriber.prepare_guard_retry(
                run.current_source,
                evaluation
            )
        if retry_source then
            if ctx.begin_guardless_transcription_retry(
                run,
                retry_source,
                retry_adjustments
            ) then
                return true
            end
            evaluation.reasons[#evaluation.reasons + 1] =
                "guard_retry_demo_start_failed"
        end
    end
    if evaluation.ok then
        local candidate, candidate_error = ComboTrialsModules.Transcriber.build_candidate(
            run.current_source,
            compiled,
            {
                schema = SF6CCVersion.COMBO_JSON_SCHEMA,
                product_id = SF6CCVersion.PRODUCT_ID,
                product_version = SF6CCVersion.PRODUCT_VERSION,
                game_id = SF6CCVersion.GAME_ID,
                game_version = SF6CCVersion.GAME_VERSION,
                json_id = SF6CCVersion.COMBO_JSON_ID,
                json_version = SF6CCVersion.COMBO_JSON_VERSION,
            },
            CTJsonInterop.iso8601_now(),
            {
                input_source = run.input_source,
                raw_inputs = run.input_source == "raw_inputs"
                    and run.captured_raw_inputs or nil,
                relative_raw_inputs = (run.input_source == "timeline"
                        or run.input_source == RawInputCodec.RELATIVE_FIELD)
                    and run.captured_raw_inputs or nil,
                source_advisories = evaluation.advisories,
                environment_adjustments =
                    run.capture_environment_adjustments,
            }
        )
        if candidate then
            local prepared, prepare_error = pcall(function()
                normalize_sequence_counter_types(candidate, false)
                assign_groups(
                    candidate,
                    run.character,
                    run.sequence_grouping_rules
                )
            end)
            if prepared then
                return ctx.begin_raw_transcription_verification(
                    run,
                    candidate,
                    compiled,
                    evaluation
                )
            else
                evaluation.ok = false
                evaluation.reasons[#evaluation.reasons + 1] =
                    "candidate_prepare_failed:" .. tostring(prepare_error)
            end
        else
            evaluation.ok = false
            evaluation.reasons[#evaluation.reasons + 1] =
                "candidate_build_failed:" .. tostring(candidate_error)
        end
    end

    return ctx.complete_transcription_item(run, evaluation, {
        compiled = compiled,
    })
end

ctx.start_next_transcription_file = function()
    local run = demo_state.transcription_run
    if not run or run.active ~= true then return false end
    ctx.ensure_run_product_rules(run)

    run.path_index = tonumber(run.path_index) or 0
    run.resume_processed = tonumber(run.resume_processed) or 0
    while run.path_index < #run.paths do
        run.path_index = run.path_index + 1
        run.index = run.resume_processed + run.path_index
        local path = run.paths[run.path_index]
        local loaded_ok, source = pcall(json.load_file, path)
        local valid_source = loaded_ok and type(source) == "table" and type(source[1]) == "table"
        if not valid_source then
            ctx.transcription_item(path, "failed", {
                reasons = { "source_json_load_failed" },
                audit_mode = run.mode,
            })
        else
            local is_audit = run.mode == "runtime_audit"
            local replay_inputs, replay_source, has_timeline =
                CTJsonInterop.select_transcription_input(source[1], is_audit)
            if is_audit and not replay_inputs and not has_timeline then
                ctx.transcription_item(path, "failed", {
                    reasons = { "runtime_audit_input_stream_missing" },
                    suspected_causes =
                        ComboTrialsModules.Transcriber.suspected_causes(
                            source,
                            run.transcription_rules
                        ),
                    audit_mode = run.mode,
                })
            elseif not is_audit and not replay_inputs and not has_timeline then
                ctx.transcription_item(path, "failed", {
                    reasons = { "missing_input_stream" },
                    suspected_causes =
                        ComboTrialsModules.Transcriber.suspected_causes(
                            source,
                            run.transcription_rules
                        ),
                    audit_mode = run.mode,
                })
            else
                local environment_adjustments = {}
                if not is_audit then
                    source, environment_adjustments =
                        ComboTrialsModules.Transcriber.prepare_capture_sequence(
                            source,
                            run.transcription_rules
                        )
                end
                run.current_path = path
                run.current_name = tostring(path):match("([^/\\]+)$") or ("combo_" .. tostring(run.index) .. ".json")
                run.current_source = source
                run.input_source = replay_source
                run.capture_input_source = run.input_source
                run.captured_raw_inputs = replay_inputs or {}
                run.input_finished_frame = nil
                run.phase = is_audit and "audit_replay" or "capture"
                run.capture_compiled = nil
                run.capture_evaluation = nil
                run.capture_environment_adjustments =
                    environment_adjustments
                run.capture_guard_retry_attempted = false
                run.verification_candidate = nil
                run.session = ctx.new_action_event_session(
                    0,
                    is_audit and "runtime_audit" or "transcription"
                )
                run.status = string.format(
                    "正在%s %d/%d：%s",
                    is_audit and "审计" or "转录",
                    run.index,
                    run.total,
                    run.current_name
                )
                trial_state._transcribing = not is_audit
                trial_state._runtime_auditing = is_audit
                local loaded = false
                if is_audit then
                    loaded = load_combo_from_file(path, true)
                else
                    loaded = ComboTrials_Files.load_combo_sequence(
                        ComboTrialsModules.Transcriber.deep_copy(source),
                        path,
                        true
                    )
                end
                if loaded then
                    start_trial(0)
                    if start_demo({ transcribe = true, countdown_frames = 20 }) then
                        return true
                    end
                end

                return ctx.complete_transcription_item(run, {
                    ok = false,
                    reasons = {
                        is_audit
                            and "runtime_audit_demo_start_failed"
                            or "demo_start_failed",
                    },
                    suspected_causes =
                        ComboTrialsModules.Transcriber.suspected_causes(
                            source,
                            run.transcription_rules
                        ),
                    expected = ComboTrialsModules.Transcriber.expected_outcome(source),
                    observed = {},
                }, {
                    compiled = nil,
                })
            end
        end
    end
    return ctx.finish_transcription_run(false)
end

ctx.tick_transcription = function()
    local run = demo_state.transcription_run
    if not run or run.active ~= true then return end
    if run.cancel_requested then
        ctx.finish_transcription_run(true)
        return
    end
    if run.pending_next == true then
        local elapsed = (engine_frame_count or 0) - (run.pending_next_frame or 0)
        local refreshing = false
        pcall(function()
            local tm = sdk.get_managed_singleton("app.training.TrainingManager")
            refreshing = tm and tm:get_field("_IsReqRefresh") == true or false
        end)
        if elapsed >= 180 and refreshing then
            run.fatal_error = "训练环境重置超时"
            ctx.finish_transcription_run(true)
        elseif elapsed >= 5 and not refreshing then
            run.pending_next = false
            run.pending_next_frame = nil
            ctx.start_next_transcription_file()
        end
        return
    end
    if run.input_finished_frame == nil then return end
    local elapsed = engine_frame_count - run.input_finished_frame
    local session = run.session
    local last_activity = type(session) == "table"
        and tonumber(session.last_activity_frame) or run.input_finished_frame
    local last_sample = type(session) == "table" and session.last_sample or nil
    local combo = tonumber(type(last_sample) == "table" and last_sample.combo_count) or 0
    local playback_inactive = elapsed >= 90
        and (engine_frame_count - last_activity) >= 45
    -- Runtime audit already validates the complete raw input stream, Action
    -- sequence and terminal outcome. Some valid routes leave the training UI's
    -- combo counter latched after every real Action has settled, so audit must
    -- not wait for that UI-only counter until the hard timeout. Recording still
    -- requires combo zero so its captured terminal outcome remains complete.
    local settled = playback_inactive
        and (run.mode == "runtime_audit" or combo == 0)
    if settled or elapsed >= 360 then
        ctx.finish_current_transcription_file(not settled)
    end
end

local function is_resumable_transcription_run(run)
    if type(run) ~= "table" or run.mode == "runtime_audit" then return false end
    return ComboTrialsModules.Transcriber.is_resumable_scope(
        run.transcription_scope
    )
end

local function remember_resumable_transcription_run(run)
    if is_resumable_transcription_run(run) and run.active ~= true then
        demo_state.resumable_transcription_run = run
    end
end

local function transcription_resume_source()
    local current = demo_state.transcription_run
    if is_resumable_transcription_run(current) then return current end
    local remembered = demo_state.resumable_transcription_run
    if is_resumable_transcription_run(remembered) then return remembered end
    return nil
end

ctx.get_transcription_resume_state = function()
    local character = players[0] and players[0].profile_name or "Unknown"
    local paths = file_system.saved_combos_all_paths_p1
        or file_system.saved_combos_paths_p1
        or {}
    return ComboTrialsModules.Transcriber.resume_info(
        transcription_resume_source(),
        character,
        paths
    )
end

ctx.start_transcription = function(force_new)
    local displayed_run = demo_state.transcription_run
    if displayed_run and displayed_run.active == true then return false end
    if trial_state.is_recording or trial_state.is_playing or demo_state.is_playing then
        ct_ticker("请先停止录制、训练或演示")
        return false
    end
    if file_system.refresh_combo_list_preserve_selection then
        file_system.refresh_combo_list_preserve_selection(false)
    end
    local character = players[0] and players[0].profile_name or "Unknown"
    local paths = file_system.saved_combos_all_paths_p1
        or file_system.saved_combos_paths_p1
        or {}
    if character == "Unknown" or #paths == 0 then
        ct_ticker("当前角色没有可转录的连段文件")
        return false
    end

    local now = CTJsonInterop.iso8601_now()
    local existing_run = transcription_resume_source()
    local run = nil
    if force_new ~= true
        and (not existing_run
            or (existing_run.mode ~= "runtime_audit"
                and existing_run.transcription_scope ~= "current")) then
        run = ComboTrialsModules.Transcriber.resume_run(
            existing_run,
            character,
            paths,
            now
        )
    end
    local resumed = run ~= nil
    if not run then
        run = ComboTrialsModules.Transcriber.new_run(character, paths, now)
    end
    demo_state.transcription_run = run
    demo_state.resumable_transcription_run = nil
    run.return_path = trial_state.current_file_path or trial_state.current_file
    if not resumed then
        run.run_id = os.date("%Y%m%d_%H%M%S")
        run.output_dir = ComboTrialsModules.Transcriber.OUTPUT_ROOT
            .. "/" .. file_system.sanitize_filename_component(character, 32, "Unknown")
            .. "/" .. run.run_id
        run.report_path = ComboTrialsModules.Transcriber.REPORT_ROOT
            .. "/" .. file_system.sanitize_filename_component(character, 32, "Unknown")
            .. "_" .. run.run_id .. ".json"
    end
    ctx.create_transcription_directories(run)
    ctx.persist_transcription_report(run)
    if resumed then
        ct_ticker(string.format(
            "继续转录 %s：已处理 %d，剩余 %d",
            character,
            run.resume_processed,
            #run.paths
        ))
    else
        ct_ticker(string.format("开始转录 %s 的 %d 个连段", character, #paths))
    end
    return ctx.start_next_transcription_file()
end

ctx.start_transcription_current = function()
    local existing_run = demo_state.transcription_run
    if existing_run and existing_run.active == true then return false end
    if trial_state.is_recording or trial_state.is_playing or demo_state.is_playing then
        ct_ticker("请先停止录制、训练或演示")
        return false
    end
    if file_system.refresh_combo_list_preserve_selection then
        file_system.refresh_combo_list_preserve_selection(false)
    end

    local character = players[0] and players[0].profile_name or "Unknown"
    local all_paths = file_system.saved_combos_all_paths_p1
        or file_system.saved_combos_paths_p1
        or {}
    local requested_path = trial_state.current_file_path or trial_state.current_file
    if not requested_path then
        local selected_index = file_system.selected_file_idx_p1 or 1
        requested_path = file_system.saved_combos_paths_p1
            and file_system.saved_combos_paths_p1[selected_index] or nil
    end
    local paths = ComboTrialsModules.RuntimeAuditor.select_single_path(
        all_paths,
        requested_path
    )
    if character == "Unknown" or #paths == 0 then
        ct_ticker("请先在当前角色列表中载入或选中一个连段")
        return false
    end

    remember_resumable_transcription_run(existing_run)

    local run_id = os.date("%Y%m%d_%H%M%S")
    local run = ComboTrialsModules.Transcriber.new_run(
        character,
        paths,
        CTJsonInterop.iso8601_now(),
        {
            scope = "current",
            requested_path = requested_path,
        }
    )
    run.run_id = run_id
    run.return_path = requested_path
    run.output_dir = ComboTrialsModules.Transcriber.OUTPUT_ROOT
        .. "/" .. file_system.sanitize_filename_component(character, 32, "Unknown")
        .. "/" .. run_id .. "_single"
    run.report_path = ComboTrialsModules.Transcriber.REPORT_ROOT
        .. "/" .. file_system.sanitize_filename_component(character, 32, "Unknown")
        .. "_single_" .. run_id .. ".json"
    demo_state.transcription_run = run
    ctx.create_transcription_directories(run)
    ctx.persist_transcription_report(run)
    ct_ticker(string.format(
        "开始单条转录 %s：%s",
        character,
        tostring(paths[1]):match("([^/\\]+)$") or tostring(paths[1])
    ))
    return ctx.start_next_transcription_file()
end

local function normalized_runtime_combo_path(value)
    return tostring(value or ""):gsub("\\", "/"):lower()
end

local function available_combo_paths(requested_paths)
    local all_paths = file_system.saved_combos_all_paths_p1
        or file_system.saved_combos_paths_p1
        or {}
    local available = {}
    for _, path in ipairs(all_paths) do
        available[normalized_runtime_combo_path(path)] = path
    end
    local selected = {}
    local seen = {}
    for _, requested in ipairs(type(requested_paths) == "table" and requested_paths or {}) do
        local path = available[normalized_runtime_combo_path(requested)]
        local key = normalized_runtime_combo_path(path)
        if path and not seen[key] then
            selected[#selected + 1] = path
            seen[key] = true
        end
    end
    return selected
end

ctx.restore_transcription_source_paths = function(report)
    if type(report) ~= "table" or report.transcription_scope ~= "audit_failures" then
        return
    end
    local existing = available_combo_paths(report.source_paths)
    if #existing > 0 then
        report.source_paths = existing
        return
    end

    local source_report = report.source_audit_report
    if type(source_report) ~= "string" or source_report == "" then return end
    local ok, audit_report = pcall(json.load_file, source_report)
    if not ok or type(audit_report) ~= "table" then return end
    local requested = ComboTrialsModules.RuntimeAuditor.failed_source_paths(audit_report)
    local restored = available_combo_paths(requested)
    if #restored > 0 then report.source_paths = restored end
end

local function retryable_audit_paths(run)
    if type(run) ~= "table" or run.mode ~= "runtime_audit"
        or type(run.items) ~= "table" then
        return {}, { failed = 0, stale = 0 }
    end
    local requested, counts =
        ComboTrialsModules.RuntimeAuditor.retry_source_paths(run)
    return available_combo_paths(requested), counts
end

local function failed_transcription_paths(run)
    local requested = ComboTrialsModules.Transcriber.failed_source_paths(run)
    local seen = {}
    for _, path in ipairs(requested) do
        seen[normalized_runtime_combo_path(path)] = true
    end
    for _, item in ipairs(type(run) == "table" and type(run.items) == "table"
        and run.items or {}) do
        local path = item and item.source_file
        local key = normalized_runtime_combo_path(path)
        if item and item.status == "passed" and key ~= "" and not seen[key] then
            local repaired = false
            for _, adjustment in ipairs(type(item.environment_adjustments) == "table"
                and item.environment_adjustments or {}) do
                if adjustment.reason
                    == "legacy_counter_policy_canonicalized:legacy_consensus" then
                    repaired = true
                    break
                end
            end
            if not repaired then
                local ok, source = pcall(json.load_file, path)
                local conflict = ok and type(source) == "table"
                    and ComboTrialsModules.TrainingEnvironment
                        .has_legacy_counter_conflict(source)
                if conflict then
                    requested[#requested + 1] = path
                    seen[key] = true
                end
            end
        end
    end
    return available_combo_paths(requested)
end

ctx.get_transcription_failure_retry_state = function()
    local run = demo_state.transcription_run
    if not run or run.active == true or run.mode == "runtime_audit" then return nil end
    local paths = failed_transcription_paths(run)
    if #paths == 0 then return nil end
    return {
        count = #paths,
        report_path = run.report_path,
    }
end

ctx.start_transcription_failures = function()
    local source_run = demo_state.transcription_run
    local paths = failed_transcription_paths(source_run)
    if #paths == 0 then
        ct_ticker("最近转录报告没有可重试的失败项")
        return false
    end
    if trial_state.is_recording or trial_state.is_playing or demo_state.is_playing then
        ct_ticker("请先停止录制、训练或演示")
        return false
    end
    local character = players[0] and players[0].profile_name or "Unknown"
    if character == "Unknown" then return false end
    local run_id = os.date("%Y%m%d_%H%M%S")
    local run = ComboTrialsModules.Transcriber.failure_retry_run(
        source_run,
        character,
        paths,
        CTJsonInterop.iso8601_now()
    )
    run.run_id = run_id
    run.source_transcription_report = source_run.report_path
    run.return_path = trial_state.current_file_path or trial_state.current_file
    run.output_dir = ComboTrialsModules.Transcriber.OUTPUT_ROOT
        .. "/" .. file_system.sanitize_filename_component(character, 32, "Unknown")
        .. "/" .. run_id .. "_failure_retry"
    run.report_path = ComboTrialsModules.Transcriber.REPORT_ROOT
        .. "/" .. file_system.sanitize_filename_component(character, 32, "Unknown")
        .. "_failure_retry_" .. run_id .. ".json"
    demo_state.transcription_run = run
    ctx.create_transcription_directories(run)
    ctx.persist_transcription_report(run)
    ct_ticker(string.format(
        "开始重试 %s 的 %d 个转录失败项",
        character,
        #paths
    ))
    return ctx.start_next_transcription_file()
end

ctx.start_runtime_audit = function(options)
    options = type(options) == "table" and options or {}
    local existing_run = demo_state.transcription_run
    if existing_run and existing_run.active == true then return false end
    if trial_state.is_recording or trial_state.is_playing or demo_state.is_playing then
        ct_ticker("请先停止录制、训练或演示")
        return false
    end
    if file_system.refresh_combo_list_preserve_selection then
        file_system.refresh_combo_list_preserve_selection(false)
    end

    local character = players[0] and players[0].profile_name or "Unknown"
    local all_paths = file_system.saved_combos_all_paths_p1
        or file_system.saved_combos_paths_p1
        or {}
    local paths = all_paths
    local requested_path = nil
    local audit_scope = options.scope == "current" and "current"
        or (options.scope == "retry_failures" and "retry_failures" or "all")
    if type(options.paths) == "table" then
        paths = available_combo_paths(options.paths)
    elseif audit_scope == "current" then
        requested_path = trial_state.current_file_path or trial_state.current_file
        if not requested_path then
            local selected_index = file_system.selected_file_idx_p1 or 1
            requested_path = file_system.saved_combos_paths_p1
                and file_system.saved_combos_paths_p1[selected_index] or nil
        end
        paths = ComboTrialsModules.RuntimeAuditor.select_single_path(
            all_paths,
            requested_path
        )
    end
    if character == "Unknown" or #paths == 0 then
        ct_ticker(audit_scope == "current"
            and "请先在当前角色列表中载入或选中一个连段"
            or (audit_scope == "retry_failures"
                and "最近审计没有可复审的失败或过期项"
                or "当前角色没有可审计的连段文件"))
        return false
    end

    remember_resumable_transcription_run(existing_run)

    local run_id = os.date("%Y%m%d_%H%M%S")
    local run = ComboTrialsModules.RuntimeAuditor.new_run(
        character,
        paths,
        CTJsonInterop.iso8601_now(),
        {
            scope = audit_scope,
            requested_path = requested_path,
        }
    )
    run.run_id = run_id
    run.source_audit_report = options.source_audit_report
    run.return_path = trial_state.current_file_path or trial_state.current_file
    run.report_path = ComboTrialsModules.RuntimeAuditor.REPORT_ROOT
        .. "/" .. file_system.sanitize_filename_component(character, 32, "Unknown")
        .. (audit_scope == "current" and "_single"
            or (audit_scope == "retry_failures" and "_retry" or ""))
        .. "_" .. run_id .. ".json"
    demo_state.transcription_run = run

    ctx.create_transcription_directories(run)
    ctx.persist_transcription_report(run)
    ct_ticker(string.format(
        audit_scope == "current"
            and "开始单条审计 %s：%s"
            or (audit_scope == "retry_failures"
                and "开始复审 %s 的 %d 个待处理项"
                or "开始审计 %s 运行目录中的 %d 个连段"),
        character,
        audit_scope == "current"
            and (tostring(paths[1]):match("([^/\\]+)$") or tostring(paths[1]))
            or #paths
    ))
    return ctx.start_next_transcription_file()
end

ctx.start_runtime_audit_current = function()
    return ctx.start_runtime_audit({ scope = "current" })
end

ctx.cancel_transcription = function()
    local run = demo_state.transcription_run
    if not run or run.active ~= true then return false end
    run.cancel_requested = true
    return ctx.finish_transcription_run(true)
end

ctx.get_transcription_state = function()
    return demo_state.transcription_run
end

ctx.get_runtime_audit_state = function()
    local run = demo_state.transcription_run
    return run and run.mode == "runtime_audit" and run or nil
end

ctx.get_runtime_audit_retry_state = function()
    local run = demo_state.transcription_run
    if not run or run.active == true or run.mode ~= "runtime_audit" then return nil end
    local paths, counts = retryable_audit_paths(run)
    local failed_paths =
        ComboTrialsModules.RuntimeAuditor.failed_source_paths(run)
    if #paths == 0 then return nil end
    local item_label = counts.stale > 0
        and (counts.failed > 0 and "失败/待复审项" or "待复审项")
        or "失败项"
    return {
        count = #paths,
        report_path = run.report_path,
        failed_count = counts.failed,
        stale_count = counts.stale,
        transcription_count = #failed_paths,
        item_label = item_label,
    }
end

ctx.start_transcription_from_audit_failures = function()
    local audit_run = demo_state.transcription_run
    local paths =
        ComboTrialsModules.RuntimeAuditor.failed_source_paths(audit_run)
    if #paths == 0 then
        ct_ticker("最近审计没有可转录的失败项")
        return false
    end
    if trial_state.is_recording or trial_state.is_playing or demo_state.is_playing then
        ct_ticker("请先停止录制、训练或演示")
        return false
    end
    local character = players[0] and players[0].profile_name or "Unknown"
    if character == "Unknown" then return false end
    local run_id = os.date("%Y%m%d_%H%M%S")
    local run = ComboTrialsModules.Transcriber.new_run(
        character,
        paths,
        CTJsonInterop.iso8601_now(),
        {
            scope = audit_run.audit_scope == "current"
                and "current" or "audit_failures",
            requested_path = audit_run.audit_scope == "current"
                and audit_run.requested_path or nil,
        }
    )
    run.run_id = run_id
    run.source_audit_report = audit_run.report_path
    run.return_path = trial_state.current_file_path or trial_state.current_file
    run.output_dir = ComboTrialsModules.Transcriber.OUTPUT_ROOT
        .. "/" .. file_system.sanitize_filename_component(character, 32, "Unknown")
        .. "/" .. run_id .. "_audit_retry"
    run.report_path = ComboTrialsModules.Transcriber.REPORT_ROOT
        .. "/" .. file_system.sanitize_filename_component(character, 32, "Unknown")
        .. "_audit_retry_" .. run_id .. ".json"
    demo_state.transcription_run = run
    ctx.create_transcription_directories(run)
    ctx.persist_transcription_report(run)
    ct_ticker(string.format("开始转录 %s 的 %d 个审计待处理项", character, #paths))
    return ctx.start_next_transcription_file()
end

ctx.start_runtime_audit_failures = function()
    local audit_run = demo_state.transcription_run
    local paths = retryable_audit_paths(audit_run)
    if #paths == 0 then
        ct_ticker("最近审计没有可复审的失败或过期项")
        return false
    end
    return ctx.start_runtime_audit({
        scope = "retry_failures",
        paths = paths,
        source_audit_report = audit_run.report_path,
    })
end

ctx.load_latest_runtime_audit_report = function()
    local character = players[0] and players[0].profile_name or "Unknown"
    if character == "Unknown" or not fs or not fs.glob then return false end
    local safe_character = file_system.sanitize_filename_component(character, 32, "Unknown")
    local glob_ok, paths = pcall(
        fs.glob,
        "TrainingComboTrials_data\\\\RuntimeAuditReports\\\\" .. safe_character .. "_.*json"
    )
    if not glob_ok or type(paths) ~= "table" or #paths == 0 then
        ct_ticker("没有找到当前角色的审计报告")
        return false
    end
    local report_path, report =
        ComboTrialsModules.Transcriber.select_latest_report(
            paths,
            json.load_file,
            ComboTrialsModules.RuntimeAuditor.REPORT_SCHEMA
        )
    if report then
        local effective_report, counts =
            ComboTrialsModules.RuntimeAuditor.recompute_loaded_report_state(report)
        report = effective_report
        report.active = false
        report.mode = "runtime_audit"
        report.report_path = report_path
        report.status = string.format(
            "已载入审计报告：有效通过 %d，失败 %d，待复审 %d",
            counts.passed,
            counts.failed,
            counts.stale
        )
        remember_resumable_transcription_run(demo_state.transcription_run)
        demo_state.transcription_run = report
        return true
    end
    ct_ticker("最近的审计报告无法读取")
    return false
end

ctx.load_latest_transcription_report = function()
    local character = players[0] and players[0].profile_name or "Unknown"
    if character == "Unknown" or not fs or not fs.glob then return false end
    local safe_character = file_system.sanitize_filename_component(character, 32, "Unknown")
    local glob_ok, paths = pcall(
        fs.glob,
        "TrainingComboTrials_data\\\\TranscriptionReports\\\\" .. safe_character .. "_.*json"
    )
    if not glob_ok or type(paths) ~= "table" or #paths == 0 then
        ct_ticker("没有找到当前角色的转录报告")
        return false
    end
    local report_path, report =
        ComboTrialsModules.Transcriber.select_latest_report(
            paths,
            json.load_file,
            ComboTrialsModules.Transcriber.REPORT_SCHEMA
        )
    if not report then
        ct_ticker("最近的转录报告无法读取")
        return false
    end
    ctx.restore_transcription_source_paths(report)
    remember_resumable_transcription_run(demo_state.transcription_run)
    local full_report_path, full_report =
        ComboTrialsModules.Transcriber.select_latest_report(
            paths,
            json.load_file,
            ComboTrialsModules.Transcriber.REPORT_SCHEMA,
            function(candidate)
                return candidate.transcription_scope == nil
                    or candidate.transcription_scope == "all"
            end
        )
    if full_report then
        full_report.active = false
        full_report.report_path = full_report_path
        full_report.output_dir = full_report.candidate_root
        demo_state.resumable_transcription_run = full_report
    end
    report.active = false
    report.report_path = report_path
    report.output_dir = report.candidate_root
    report.review_index = 1
    local verified_passes = 0
    local pending_reverification = 0
    local current_failures = 0
    for _, item in ipairs(report.items) do
        if item.status == "passed" and item.raw_replay_verified == true then
            verified_passes = verified_passes + 1
        elseif item.raw_replay_verified == nil
            or (item.status ~= "passed"
                and tonumber(item.validation_revision)
                    ~= ComboTrialsModules.Transcriber.VALIDATION_REVISION) then
            pending_reverification = pending_reverification + 1
        elseif item.status ~= "passed" then
            current_failures = current_failures + 1
        end
    end
    report.status = string.format(
        "已载入报告：已验证 %d，待补验 %d，本轮需处理 %d",
        verified_passes,
        pending_reverification,
        current_failures
    )
    demo_state.transcription_run = report
    return true
end

ctx.get_transcription_candidate_state = function()
    local run = demo_state.transcription_run
    if not run or run.mode == "runtime_audit"
        or type(run.items) ~= "table" then
        return nil
    end
    local candidates = {}
    for _, item in ipairs(run.items) do
        if item.status == "passed"
            and item.raw_replay_verified == true
            and type(item.candidate_file) == "string"
            and item.candidate_file ~= "" then
            candidates[#candidates + 1] = item
        end
    end
    if #candidates == 0 then return { count = 0, index = 0 } end
    run.review_index = math.max(1, math.min(#candidates, tonumber(run.review_index) or 1))
    local item = candidates[run.review_index]
    return {
        count = #candidates,
        index = run.review_index,
        name = item.source_name or tostring(item.candidate_file):match("([^/\\]+)$"),
        path = item.candidate_file,
    }
end

ctx.change_transcription_candidate = function(delta)
    local run = demo_state.transcription_run
    local state = ctx.get_transcription_candidate_state()
    if not run or not state or state.count == 0 then return false end
    local next_index = state.index + (tonumber(delta) or 0)
    if next_index < 1 then next_index = state.count end
    if next_index > state.count then next_index = 1 end
    run.review_index = next_index
    return true
end

ctx.start_transcription_candidate = function()
    local state = ctx.get_transcription_candidate_state()
    if not state or not state.path or trial_state.is_recording then return false end
    if demo_state.is_playing then
        ctx.stop_demo_playback(
            "transcription_candidate_switch",
            demo_state.current_file_path or trial_state.current_file_path or trial_state.current_file,
            state.path,
            true
        )
    else
        trial_state.is_playing = false
    end
    if not load_combo_from_file(state.path, true) then
        ct_ticker("候选文件加载失败")
        return false
    end
    start_trial(0)
    local run = demo_state.transcription_run
    if run then run.status = "正在审阅候选：" .. tostring(state.name or state.path) end
    ct_ticker(string.format("已加载候选 %d/%d", state.index, state.count))
    return true
end

ctx.stop_demo_without_transcription = ctx.stop_demo
ctx.stop_demo = function()
    local run = demo_state.transcription_run
    if run and run.active == true then
        ctx.cancel_transcription()
        return
    end
    ctx.stop_demo_without_transcription()
end

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
        if demo_state and demo_state.auto_playlist_enabled == true then
            start_demo({ playlist_start = true })
        else
            start_demo()
        end
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
ctx.save_state = ctx.save_state or {
    trial_snapshot = nil,
    pending_restore = 0,
    save_pending = false,
    real_frame = 0,
    save_fired_at = 0,
    save_step_at_fire = 1,
    dbg_log = {},
    save_display = "jamais",
    save_count = 0,
    load_display = "jamais",
    load_count = 0,
    hooked = false
}

ctx.apply_restore = function()
    if not ctx.save_state.trial_snapshot then return end
    if not trial_state.is_playing then return end
    trial_state.current_step      = ctx.save_state.trial_snapshot.step or 1
    trial_state.success_timer     = 0
    trial_state._success_latched  = false
    trial_state._auto_next_countdown = nil
    trial_state.fail_timer        = 0
    trial_state.fail_reason       = nil
    local frames_since            = ctx.save_state.trial_snapshot.frames_since_step or 0
    trial_state.last_played_frame = engine_frame_count - frames_since
    if ctx.save_state.trial_snapshot.flip_inputs ~= nil then
        trial_state.flip_inputs = ctx.save_state.trial_snapshot.flip_inputs
    end
    if ctx.save_state.trial_snapshot.sequence then
        for i, saved in ipairs(ctx.save_state.trial_snapshot.sequence) do
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

ctx.clear_trial_snapshot = function()
    ctx.save_state.trial_snapshot = nil
    ctx.save_state.pending_restore = 0
    ctx.save_state.save_pending = false
end

-- Debug log
ctx.save_state_dbg = function(s)
    table.insert(ctx.save_state.dbg_log, 1, string.format("[%d] %s", ctx.save_state.real_frame, s))
    if #ctx.save_state.dbg_log > 20 then table.remove(ctx.save_state.dbg_log) end
end

-- re.on_draw_ui(function()
-- imgui.begin_window("TrialSaveState DEBUG", true, 0)
-- imgui.text_colored("SAVE: " .. ctx.save_state.save_count .. "x  " .. ctx.save_state.save_display, 0xFF88FF88)
-- imgui.text_colored("LOAD: " .. ctx.save_state.load_count .. "x  " .. ctx.save_state.load_display, 0xFF8888FF)
-- imgui.separator()
-- for _, l in ipairs(ctx.save_state.dbg_log) do imgui.text(l) end
-- imgui.end_window()
-- end)


if _G._allow_stun_demo == nil then _G._allow_stun_demo = true end

ctx.ct_get_field = function(obj, name)
    return obj:get_field(name)
end

re.on_frame(function()
    if rawget(_G, "CT_SAVE_STATE_POC") ~= true then
        ctx.save_state.save_pending = false
        ctx.save_state.pending_restore = 0
        return
    end
    if not is_combo_trials_runtime_allowed() then
        ctx.save_state.save_pending = false
        ctx.save_state.pending_restore = 0
        return
    end
    if not ctx.save_state.hooked then
        ctx.save_state.hooked = true
        local td = sdk.find_type_definition("app.training.TrainingManager")
        if td then
            local save_methods = { "requestSaveState", "SaveKeyData" }
            local load_methods = { "requestLoadState" }
            
            for _, name in ipairs(save_methods) do
                local m = td:get_method(name)
                if m then
                    pcall(function()
                        sdk.hook(m, function(args)
                            if ctx.save_state.pending_restore > 0 then return end
                            ctx.save_state.save_pending = true
                            ctx.save_state.save_fired_at = ctx.save_state.real_frame
                            ctx.save_state.save_step_at_fire = trial_state.current_step
                            ctx.save_state_dbg("Save() " .. name .. " step=" .. tostring(trial_state.current_step))
                        end, function(retval) return retval end)
                    end)
                end
            end

            for _, name in ipairs(load_methods) do
                local m = td:get_method(name)
                if m then
                    pcall(function()
                        sdk.hook(m, function(args)
                            ctx.save_state.load_count = ctx.save_state.load_count + 1
                            ctx.save_state.save_pending = false
                            if ctx.save_state.trial_snapshot and trial_state.is_playing then
                                ctx.save_state.pending_restore = 8
                            end
                        end, function(retval) return retval end)
                    end)
                end
            end
        end
    end

    -- If Save fired and no Load followed within 5 frames -> real Save
    if ctx.save_state.save_pending and (ctx.save_state.real_frame - ctx.save_state.save_fired_at) >= 5 then
        ctx.save_state.save_pending = false
        if trial_state.is_playing then
            local snap_sequence = {}
            for i, item in ipairs(trial_state.sequence) do
                snap_sequence[i] = { has_hit = item.has_hit, actual_combo = item.actual_combo }
            end
            ctx.save_state.trial_snapshot = {
                step              = ctx.save_state.save_step_at_fire,
                frames_since_step = engine_frame_count - (trial_state.last_played_frame or engine_frame_count),
                sequence          = snap_sequence,
                flip_inputs       = trial_state.flip_inputs,
            }
            ctx.save_state.save_count = ctx.save_state.save_count + 1
            ctx.save_state.save_display = os.date("%H:%M:%S") .. " [SnapShoted] step=" .. tostring(ctx.save_state.save_step_at_fire)
            ctx.save_state_dbg("-> snapshot saved step=" ..
                tostring(ctx.save_state.trial_snapshot.step) .. " frames_since=" .. tostring(ctx.save_state.trial_snapshot.frames_since_step))
        end
    end

    -- STOP TRIAL -> clear
    if not trial_state.is_playing and ctx.save_state.trial_snapshot then
        ctx.clear_trial_snapshot()
    end

    -- GUARD: cancel the refresh triggered by save shortcuts when trial is active with forced position.
    -- Do not cancel our own reset/start refresh; pending_exact_pos is set by apply_forced_position().
    local save_refresh_recent = ctx.save_state.save_fired_at > 0 and (ctx.save_state.real_frame - ctx.save_state.save_fired_at) <= 8
    if trial_state.is_playing and save_refresh_recent and d2d_cfg.forced_position_idx ~= 1
        and not (trial_state.pending_exact_pos and trial_state.pending_exact_pos > 0) then
        local tm2 = sdk.get_managed_singleton("app.training.TrainingManager")
        if tm2 then
            local ok, ts = pcall(ctx.ct_get_field, tm2, "_TrainingState")
            local ok2, rf = pcall(ctx.ct_get_field, tm2, "_IsReqRefresh")
            if ok and ok2 and ts == 2 and rf == true then
                pcall(function()
                    tm2:set_field("_IsReqRefresh", false)
                    tm2:set_field("_TrainingState", 1)
                end)
            end
        end
    end

   -- Delayed restore
    if ctx.save_state.pending_restore > 0 then
        ctx.save_state.pending_restore = ctx.save_state.pending_restore - 1
        if ctx.save_state.pending_restore == 0 then
            ctx.save_state_dbg("apply_restore step=" .. tostring(ctx.save_state.trial_snapshot and ctx.save_state.trial_snapshot.step or "nil"))
            ctx.apply_restore()
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
    if not is_combo_trials_runtime_allowed() then return end
    if demo_state.playlist_active == true and demo_state.playlist_pending_next == true then
        demo_state.playlist_pending_next = false
        start_demo({ playlist_next = true })
    end
    if not tick_done_this_frame and demo_state.is_playing and not demo_state.raw_buffer then
        demo_state._transcription_capture_frame = false
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
            if trial_state._pending_reinject_settings == true then is_refreshing = true end

            if not is_paused and not is_refreshing then
                if demo_state._transcription_input_finished == true then
                    demo_state.p1_mask = 0
                    demo_state._last_tick_frame = nil
                elseif demo_state.countdown and demo_state.countdown > 0 then
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
                        demo_state._transcription_capture_frame =
                            demo_state.transcribing == true
                    else
                        if demo_state.transcribing == true then
                            demo_state.mark_transcription_input_finished()
                        else
                            ctx.finish_demo_telemetry_cycle()
                        end
                        if demo_state.transcribing == true then
                            demo_state.p1_mask = 0
                            demo_state._last_tick_frame = nil
                        elseif demo_state.playlist_active == true then
                            demo_state.is_playing = false
                            demo_state.current_frame = 0
                            demo_state.current_step = 1
                            demo_state.countdown = 0
                            demo_state.p1_mask = 0
                            demo_state._last_tick_frame = nil
                            demo_state._state_reinjected = false
                            demo_state.playlist_pending_next = true
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
    local final_mask = RawInputCodec.relative_to_native(
        demo_state.p1_mask,
        p1:get_field("rl_dir") ~= false
    )
    if demo_state.transcribing == true then
        -- Batch transcription must be deterministic. Do not merge accidental
        -- physical input into the replay stream being captured.
        p1:set_field("pl_input_new", final_mask)
        p1:set_field("pl_sw_new", final_mask)
    else
        local orig_in = p1:get_field("pl_input_new") or 0
        local orig_sw = p1:get_field("pl_sw_new") or 0
        p1:set_field("pl_input_new", orig_in | final_mask)
        p1:set_field("pl_sw_new", orig_sw | final_mask)
    end
end

CTRawInputRuntime = CTRawInputRuntime or {}

function CTRawInputRuntime.capture(p_id)
    local player = p_id == 0 and GS.p1 or GS.p2
    if not player then return end
    local input = player:get_field("pl_input_new")
    local buffer = trial_state._raw_rec_buffer
    if type(buffer) ~= "table" then
        buffer = {}
        trial_state._raw_rec_buffer = buffer
    end
    local facing_right = player:get_field("rl_dir") ~= false
    buffer[#buffer + 1] = RawInputCodec.native_to_relative(
        (input and tonumber(tostring(input))) or 0,
        facing_right
    )
end

function CTRawInputRuntime.play()
    if demo_state._transcription_input_finished == true then
        local waiting_player = GS.p1
        if waiting_player then
            waiting_player:set_field("pl_input_new", 0)
            waiting_player:set_field("pl_sw_new", 0)
        end
        return
    end

    local pm = sdk.get_managed_singleton("app.PauseManager")
    if pm then
        local pause_bits = pm:get_field("_CurrentPauseTypeBit")
        if pause_bits ~= 64 and pause_bits ~= 2112 then return end
    end

    local tm = sdk.get_managed_singleton("app.training.TrainingManager")
    if tm and tm:get_field("_IsReqRefresh") == true then return end
    if trial_state.pending_exact_pos and trial_state.pending_exact_pos > 0 then return end
    if trial_state._pending_reinject_settings == true then return end

    -- Countdown is a stable pre-roll, not a refresh timeout. Burning it while
    -- position/resource restoration is still pending makes the first replay
    -- start earlier than every subsequent replay of the same raw stream.
    if demo_state.countdown and demo_state.countdown > 0 then
        demo_state.countdown = demo_state.countdown - 1
        return
    end

    local buffer = demo_state.raw_buffer
    if type(buffer) ~= "table" or #buffer == 0 then return end
    local index = demo_state.play_index or 1
    if index > #buffer then
        if demo_state.transcribing == true then
            demo_state.mark_transcription_input_finished()
            local waiting_player = GS.p1
            if waiting_player then
                waiting_player:set_field("pl_input_new", 0)
                waiting_player:set_field("pl_sw_new", 0)
            end
        else
            ctx.finish_demo_telemetry_cycle()
        end
        if demo_state.transcribing == true then
            return
        elseif demo_state.playlist_active == true then
            demo_state.is_playing = false
            demo_state.raw_buffer = nil
            demo_state.raw_input_source = nil
            demo_state.play_index = 1
            demo_state.countdown = 0
            demo_state._state_reinjected = false
            demo_state.playlist_pending_next = true
        else
            demo_state.play_index = 1
            demo_state.countdown = 10
            demo_state._state_reinjected = false
            reset_trial_steps()
        end
        return
    end

    if index == 1 and demo_state._state_reinjected ~= true then
        CTStunDemoRuntime.restore_pre_demo_state()
        demo_state._state_reinjected = true
    end

    local p1 = GS.p1
    if not p1 then return end
    local mask = buffer[index]
    if demo_state.raw_input_source == RawInputCodec.RELATIVE_FIELD then
        mask = RawInputCodec.relative_to_native(
            mask,
            p1:get_field("rl_dir") ~= false
        )
    end
    p1:set_field("pl_input_new", mask)
    p1:set_field("pl_sw_new", mask)
    demo_state.play_index = index + 1
end

if _G._shared_input_post then
table.insert(_G._shared_input_post, function(p_id, retval)
    if not is_combo_trials_runtime_allowed() then return end
    if p_id == trial_state.recording_player and trial_state._raw_rec_active then
        pcall(CTRawInputRuntime.capture, p_id)
    end
    if p_id == 0 and demo_state.is_playing and demo_state.raw_buffer then
        pcall(CTRawInputRuntime.play)
    elseif p_id == 0 and demo_state.is_playing
        and (demo_state.p1_mask > 0
            or demo_state._transcription_capture_frame == true) then
        pcall(_ct_demo_inject_mask)
    end
    if p_id == 0
        and demo_state.transcribing == true
        and demo_state._transcription_capture_frame == true then
        local run = demo_state.transcription_run
        if run and type(run.captured_raw_inputs) == "table" then
            -- Timeline masks are already facing-relative. Capturing the
            -- injected native value here would freeze the current screen side
            -- and break any route that crosses through the opponent.
            local value = tonumber(demo_state.p1_mask) or 0
            run.captured_raw_inputs[#run.captured_raw_inputs + 1] =
                math.floor(value) & 0xFFFF
        end
        demo_state._transcription_capture_frame = false
    end
end)
end

