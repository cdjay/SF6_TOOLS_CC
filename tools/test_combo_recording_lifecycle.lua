local function read_file(path)
    local file = assert(io.open(path, "rb"))
    local value = assert(file:read("*a"))
    file:close()
    return value
end

local function extract_between(source, first_marker, next_marker)
    local first = assert(source:find(first_marker, 1, true),
        "missing source marker: " .. first_marker)
    local next_pos = assert(source:find(next_marker, first + #first_marker, true),
        "missing next source marker: " .. next_marker)
    return source:sub(first, next_pos - 1)
end

local source = read_file("autorun/TrainingComboTrials_v1.0.lua")
local clear_logger_source = extract_between(
    source,
    "local function clear_recording_logger(player_idx)",
    "local function cancel_recording()"
)
local cancel_source = extract_between(
    source,
    "local function cancel_recording()",
    "local function cancel_recording_due_to_menu(reason)"
)
local player_init_source = extract_between(
    source,
    "local function ct_player_init(p_idx, p_state)",
    "local function ct_player_tracking(p_idx, p_state)"
)

local function build_player(name)
    return {
        profile_name = name,
        last_profile_name = "PreviousCharacter",
        log = { { stale = true } },
        input_history_queue = { 1 },
        dash_tap_state = { stale = true },
        raw_drive_rush_precursor_state = { stale = true },
        recording_contact_state = { stale = true },
        trigger_mask_cache = { stale = true },
    }
end

local function run_character_switch(recording_player, changed_player)
    local trial_state = {
        playing_player = 99,
        recording_player = recording_player,
        is_recording = true,
        is_playing = false,
        sequence = { { id = 600 } },
        source_sequence = { { id = 600 } },
        current_step = 2,
        _raw_rec_active = true,
        _raw_rec_buffer = { 0x10, 0 },
        _action_event_session = { events = { { id = 600 } } },
        _recording_compiler_used = true,
        _last_action_compile = { steps = { { id = 600 } } },
        _rec_environment = { dummy_stance = "crouch" },
        _rec_scene_state = { actor = {} },
        _xt_pending_save = false,
    }
    local players = {
        [0] = build_player(changed_player == 0 and "Unknown" or "P1"),
        [1] = build_player(changed_player == 1 and "Unknown" or "P2"),
    }
    local logger_state = {
        rec_p1 = { active = recording_player == 0, has_started = true, wait_neutral = false, data = { { frames = 4 } } },
        rec_p2 = { active = recording_player == 1, has_started = true, wait_neutral = false, data = { { frames = 4 } } },
    }
    local reset_count = 0
    local env = {
        trial_state = trial_state,
        players = players,
        logger_state = logger_state,
        live_display_context = { refresh = function() end },
        invalidate_recording_display_context = function() end,
        reset_combo_visual_runtime = function() reset_count = reset_count + 1 end,
        step_combo_reset_gc = function() end,
        ctx = { reset_recording_preview = function() end },
        ui_state = { viewed_player = 99 },
        file_system = {},
        demo_state = {},
        CharacterRules = {},
        ComboTrialsModules = {},
        common_exceptions = {},
        SF6CCVersion = { GAME_VERSION = "test" },
        json = {},
        select = select,
        type = type,
        tonumber = tonumber,
        math = math,
        ipairs = ipairs,
        pairs = pairs,
        tostring = tostring,
    }
    setmetatable(env, { __index = _G })

    local chunk = table.concat({
        clear_logger_source,
        cancel_source,
        player_init_source,
        "return ct_player_init",
    }, "\n")
    local init = assert(load(chunk, "recording-character-switch", "t", env))()
    init(changed_player, players[changed_player])

    local recorder = recording_player == 0 and logger_state.rec_p1 or logger_state.rec_p2
    assert(trial_state.is_recording == false,
        "a character switch must end the visible recording session")
    assert(recorder.active == false and recorder.has_started == false and #recorder.data == 0,
        "a character switch must stop the hidden timeline logger")
    assert(trial_state._raw_rec_active == false and #trial_state._raw_rec_buffer == 0,
        "a character switch must discard captured raw input")
    assert(trial_state._action_event_session == nil
            and trial_state._recording_compiler_used == false
            and trial_state._last_action_compile == nil,
        "a character switch must discard the action compiler session")
    assert(trial_state._rec_environment == nil and trial_state._rec_scene_state == nil,
        "a character switch must discard recording-only environment snapshots")
    assert(reset_count == 1,
        "recording cancellation must reset visual state exactly once")
end

local function run_demo_character_switch(changed_player)
    local trial_state = {
        playing_player = 99,
        recording_player = 0,
        is_recording = false,
        is_playing = true,
        sequence = { { id = 600 } },
        source_sequence = { { id = 600 } },
        current_step = 2,
        _xt_pending_save = false,
    }
    local players = {
        [0] = build_player(changed_player == 0 and "Unknown" or "P1"),
        [1] = build_player(changed_player == 1 and "Unknown" or "P2"),
    }
    local demo_state = {
        is_playing = true,
        p1_mask = 0x30,
        raw_buffer = { 0x30, 0 },
        raw_input_source = "relative_raw_inputs",
        play_index = 2,
        playlist_active = true,
        playlist_index = 3,
        playlist_total = 8,
        playlist_pending_next = true,
        playlist_loading = true,
        sequence = { { frames = 9, mask = 0x30 } },
        current_step = 1,
        current_frame = 4,
        countdown = 7,
        _last_tick_frame = 123,
        _state_reinjected = true,
        current_file = "old.json",
        current_file_path = "old.json",
        current_file_name = "old.json",
    }
    local stop_calls = 0
    local env = {
        trial_state = trial_state,
        players = players,
        logger_state = {
            rec_p1 = { active = false, data = {} },
            rec_p2 = { active = false, data = {} },
        },
        live_display_context = { refresh = function() end },
        invalidate_recording_display_context = function() end,
        reset_combo_visual_runtime = function() end,
        step_combo_reset_gc = function() end,
        ctx = {
            reset_recording_preview = function() end,
            stop_demo_playback = function(reason, old_file, new_file, stop_trial, keep_playlist)
                stop_calls = stop_calls + 1
                assert(reason == "character_change" and old_file == "old.json"
                        and new_file == nil and stop_trial == true
                        and keep_playlist == false,
                    "character change must identify the demo cancellation")
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
        ui_state = { viewed_player = 99 },
        file_system = {},
        demo_state = demo_state,
        CharacterRules = {},
        ComboTrialsModules = {},
        common_exceptions = {},
        SF6CCVersion = { GAME_VERSION = "test" },
        json = {},
        select = select,
        type = type,
        tonumber = tonumber,
        math = math,
        ipairs = ipairs,
        pairs = pairs,
        tostring = tostring,
    }
    setmetatable(env, { __index = _G })

    local chunk = table.concat({
        clear_logger_source,
        cancel_source,
        player_init_source,
        "return ct_player_init",
    }, "\n")
    local init = assert(load(chunk, "demo-character-switch", "t", env))()
    init(changed_player, players[changed_player])

    assert(stop_calls == 1,
        "a character switch must use the shared Demo cancellation lifecycle")
    assert(demo_state.is_playing == false
            and demo_state.raw_buffer == nil
            and #demo_state.sequence == 0
            and demo_state.current_frame == 0
            and demo_state.countdown == 0
            and demo_state._last_tick_frame == nil
            and demo_state.current_file_path == nil,
        "a character switch must not retain old Demo runtime state")
end

run_character_switch(0, 0)
run_character_switch(0, 1)
run_character_switch(1, 0)
run_character_switch(1, 1)
run_demo_character_switch(0)
run_demo_character_switch(1)

print("combo recording lifecycle tests passed")
