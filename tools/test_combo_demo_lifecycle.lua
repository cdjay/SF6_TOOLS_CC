local function read_file(path)
    local file = assert(io.open(path, "rb"))
    local value = assert(file:read("*a"))
    file:close()
    return value
end

local function extract_function(source, first_marker, next_marker, return_name)
    local first = assert(source:find(first_marker, 1, true))
    local next_pos = assert(source:find(next_marker, first + #first_marker, true))
    local body = source:sub(first, next_pos - 1)
    return body .. "\nreturn " .. return_name
end

local source = read_file("autorun/TrainingComboTrials_v1.0.lua")
local mode_exit_chunk = extract_function(
    source,
    "local function ct_handle_mode_exit()",
    "local function ct_handle_first_frame_init(_in_replay)",
    "ct_handle_mode_exit"
)
local first_frame_chunk = extract_function(
    source,
    "local function ct_handle_first_frame_init(_in_replay)",
    "local function ct_handle_pause_positions(is_game_paused, _in_replay)",
    "ct_handle_first_frame_init"
)

local function new_demo_state()
    return {
        is_playing = true,
        p1_mask = 0x40,
        raw_buffer = { 0x40, 0 },
        raw_input_source = "relative_raw_inputs",
        play_index = 2,
        sequence = { { frames = 8, mask = 0x40 } },
        current_step = 1,
        current_frame = 3,
        countdown = 6,
        _last_tick_frame = 80,
        _state_reinjected = true,
        current_file = "demo.json",
        current_file_path = "demo.json",
        current_file_name = "demo.json",
        playlist_active = false,
        playlist_pending_next = false,
    }
end

local function build_env()
    local trial_state = {
        is_playing = false,
        is_recording = false,
        _was_playing = false,
        _vital_initialized = true,
    }
    local demo_state = new_demo_state()
    local stop_calls = 0
    local env = {
        trial_state = trial_state,
        demo_state = demo_state,
        ctx = {
            stop_demo_playback = function(reason, old_file, new_file, stop_trial, keep_playlist)
                stop_calls = stop_calls + 1
                assert(type(reason) == "string" and old_file == "demo.json"
                        and new_file == nil and stop_trial == true,
                    "Demo lifecycle cleanup must identify the interrupted file")
                demo_state.is_playing = false
                demo_state.p1_mask = 0
                demo_state.raw_buffer = nil
                demo_state.raw_input_source = nil
                demo_state.play_index = 1
                demo_state.sequence = {}
                demo_state.current_step = 1
                demo_state.current_frame = 0
                demo_state.countdown = 0
                demo_state._last_tick_frame = nil
                demo_state._state_reinjected = false
                demo_state.current_file = nil
                demo_state.current_file_path = nil
                demo_state.current_file_name = nil
                trial_state.is_playing = false
            end,
        },
        live_display_context = {
            invalidate = function() end,
            ensure = function() end,
        },
        ComboTrials_Renderer = { clear_unresolved_action_audit = function() end },
        ComboTrialsModules = {
            DummySettings = {
                restore_counter_type = function() end,
                restore_guard_type = function() end,
                restore_action_type = function() end,
            },
        },
        unique_resources = { restore = function() end },
        invalidate_recording_display_context = function() end,
        reset_combo_visual_runtime = function() end,
        restore_trial_vital = function() end,
        restore_trial_defense_settings = function() end,
        apply_current_position_refresh = function() end,
        cancel_recording = function() end,
        _G = { CurrentTrainerMode = 3 },
        type = type,
        pcall = pcall,
    }
    setmetatable(env._G, { __index = _G })
    setmetatable(env, { __index = _G })
    return env, trial_state, demo_state, function() return stop_calls end
end

local function assert_demo_cleared(demo_state, stop_calls, message)
    assert(stop_calls == 1, message .. " must use stop_demo_playback")
    assert(demo_state.is_playing == false
            and demo_state.raw_buffer == nil
            and #demo_state.sequence == 0
            and demo_state.current_frame == 0
            and demo_state.countdown == 0
            and demo_state._last_tick_frame == nil
            and demo_state.current_file_path == nil,
        message .. " must clear the complete Demo session")
end

do
    local env, _, demo_state, stop_calls = build_env()
    local mode_exit = assert(load(mode_exit_chunk, "mode-exit", "t", env))()
    mode_exit()
    assert_demo_cleared(demo_state, stop_calls(), "training-script exit")
end

do
    local env, trial_state, demo_state, stop_calls = build_env()
    trial_state._vital_initialized = false
    local first_frame = assert(load(first_frame_chunk, "first-frame", "t", env))()
    first_frame(false)
    assert_demo_cleared(demo_state, stop_calls(), "first-frame recovery")
end

print("combo Demo lifecycle tests passed")
