local function read_all(path)
    local file = assert(io.open(path, "rb"))
    local value = assert(file:read("*a"))
    file:close()
    return value:gsub("\r\n", "\n")
end

local function extract_between(source, first_marker, next_marker)
    local first = assert(source:find(first_marker, 1, true),
        "missing source marker: " .. first_marker)
    local next_pos = assert(source:find(next_marker, first + #first_marker, true),
        "missing next source marker: " .. next_marker)
    return source:sub(first, next_pos - 1)
end

local source = read_all("autorun/TrainingComboTrials_v1.0.lua")
local start_trial_source = extract_between(
    source,
    "local function start_trial(player_idx)",
    "local function clear_recording_logger(player_idx)"
)
local reset_source = extract_between(
    source,
    "ctx.reset_trial_steps_and_load = function(player_idx)",
    "-- =========================================================\n-- DEMO ENGINE LOGIC & EXPORTS"
)

local trial_state = {
    is_playing = true,
    playing_player = 0,
    recording_player = 0,
    sequence = { { id = 600 } },
}
local players = {
    [0] = {},
    [1] = {},
}
local file_system = {
    saved_combos_paths_p1 = { "ActiveTrial.json" },
    saved_combos_paths_p2 = {},
    selected_file_idx_p1 = 1,
    selected_file_idx_p2 = 1,
}
local load_count = 0
local restore_refresh_count = 0
local environment_refresh_count = 0
local env = {
    trial_state = trial_state,
    players = players,
    file_system = file_system,
    d2d_cfg = {},
    ComboTrialsModules = {
        DummySettings = {
            restore_action_type = function() end,
            save_counter_type = function() end,
            save_guard_type = function() end,
            save_action_type = function() end,
        },
    },
    ctx = {
        reset_recording_preview = function() end,
        begin_trial_telemetry_attempt = function() end,
    },
    CTJsonInterop = {
        warn_control_mode_mismatch = function() end,
    },
    load_combo_from_file = function(path, force)
        load_count = load_count + 1
        assert(path == "ActiveTrial.json" and force == true,
            "reset must still reload the selected Combo from disk")
        trial_state.sequence = { { id = 600 } }
        trial_state.is_playing = false
        return true
    end,
    clear_pending_position_injection = function() end,
    read_actor_scene_hp = function() return nil end,
    restore_trial_vital = function()
        restore_refresh_count = restore_refresh_count + 1
    end,
    unique_resources = { restore = function() end },
    invalidate_recording_display_context = function() end,
    clear_trial_attempt_state = function() end,
    capture_current_positions = function() return 0, 1, 0, 65536 end,
    reset_combo_visual_runtime = function() end,
    apply_trial_training_environment = function()
        environment_refresh_count = environment_refresh_count + 1
    end,
    update_trial_flip_state = function() end,
    apply_forced_position = function() end,
    reset_trial_steps = function()
        error("loaded active trial must restart through start_trial")
    end,
}
setmetatable(env, { __index = _G })

local chunk = table.concat({
    start_trial_source,
    reset_source,
    "return ctx.reset_trial_steps_and_load",
}, "\n")
local reset_trial = assert(load(chunk, "combo-trial-reset-lifecycle", "t", env))()
reset_trial(0)

assert(load_count == 1,
    "one user reset must reload the selected Combo exactly once")
assert(restore_refresh_count == 0,
    "restarting an active Combo must not restore the old environment first")
assert(environment_refresh_count == 1,
    "one user reset must apply the selected Combo environment exactly once")
assert(trial_state.is_playing == true and trial_state.playing_player == 0,
    "the active Combo must remain in player training after reset")

print("combo trial reset lifecycle tests passed")
