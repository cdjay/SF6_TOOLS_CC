package.path = table.concat({
    "./autorun/?.lua",
    "./autorun/?/init.lua",
    package.path,
}, ";")

local Stage1Controller = require("func/ComboTrials/Raw/Stage1Controller")

local function equal(actual, expected, message)
    assert(actual == expected, (message or "values differ")
        .. ": expected=" .. tostring(expected) .. " actual=" .. tostring(actual))
end

local catalog = {
    get_build_info = function()
        return { build_uid = "sf6b_current", display_version = "2026-08-03" }
    end,
    get_character = function()
        return { fighter_id = 1, character = "Ryu" }
    end,
    get_bindings = function(_, action_id)
        if action_id ~= 600 then return nil end
        return { {
            action_id = 600,
            raw_trigger_uid = "trigger_1",
            trigger_index = 1,
            raw_command_uid = "command_1",
            profile_name = "norm",
            command_no = 1,
            command_index = 6,
            command_definition_uids = { "definition_1" },
            variant_indexes = { 0 },
            direct_command_tokens = { "236+HP" },
            ng_flag = false,
            enabled = true,
        } }
    end,
    get_definition = function(_, uid)
        if uid == "definition_1" then
            return { definition_uid = uid, inputs = { { direction = "2" } } }
        end
    end,
    get_bindings_snapshot = function(self, action_id)
        return self:get_bindings(action_id)
    end,
    get_audit_info = function()
        return {
            counts = { bcm_commands = 1 },
            reconciliation = { direct_binding_miss_count = 0, all_match = true },
        }
    end,
}

local fake_raw_catalog = {
    DIRECTORY = "raw/current",
    load = function(options)
        equal(options.fighter_id, 1)
        equal(options.expected_display_version, "2026-08-03")
        return catalog, { ok = true }
    end,
}

local state = {
    sequence = { {} },
    current_step = 1,
    success_timer = 0,
    fail_timer = 0,
    is_recording = false,
    is_playing = false,
}
local written_path = nil
local written_value = nil
local controller = assert(Stage1Controller.new({
    trial_state = state,
    target_game_version = "2026-08-03",
    raw_catalog = fake_raw_catalog,
    get_context = function()
        return { control_mode = "classic", fail_display_frames = 90, current_combo = 2 }
    end,
    write_json = function(path, value)
        written_path = path
        written_value = value
        return true
    end,
}))

local _, legacy_status = controller:install_sequence({ { _xt_meta = {} } })
equal(legacy_status, "legacy")
equal(controller:blocks_legacy_detector(), false)

local invalid, invalid_status = controller:install_sequence({ {
    _xt_meta = { raw_stage1 = "bad" },
} })
equal(invalid, nil)
equal(invalid_status, "invalid")
equal(controller:blocks_legacy_detector(), true)

local trace_payload = {
    schema = "sf6cc.raw_stage1.atomic_trace.v1",
    version = 1,
    finalized = true,
    instances = { {
        step = 1,
        occurrence = 1,
        action_id = 600,
        enter_frame = 1,
        exit_frame = 1,
        action_frame_start = 0,
        action_frame_end = 0,
    } },
}
local valid_meta = { raw_stage1 = {
    schema = "sf6cc.raw_stage1.trial.v1",
    version = 1,
    environment = {
        character = "Ryu",
        fighter_id = 1,
        game_build = "sf6b_current",
        control_mode = "classic",
        recorded_at = "2026-08-09T00:00:00Z",
    },
    trace = trace_payload,
} }

local mismatch_meta = { raw_stage1 = {
    schema = valid_meta.raw_stage1.schema,
    version = valid_meta.raw_stage1.version,
    environment = {
        character = "Ryu",
        fighter_id = 1,
        game_build = "sf6b_old",
        control_mode = "classic",
        recorded_at = "2026-08-09T00:00:00Z",
    },
    trace = trace_payload,
} }
local mismatch, mismatch_status, mismatch_code = controller:install_sequence({ {
    _xt_meta = mismatch_meta,
} })
equal(mismatch, nil)
equal(mismatch_status, "catalog_error")
equal(mismatch_code, "raw_trial_build_mismatch")
equal(controller:blocks_legacy_detector(), true)

local loaded, loaded_status = controller:install_sequence({ { _xt_meta = valid_meta } })
assert(loaded)
equal(loaded_status, "loaded")
equal(state._raw_stage1_rows[1].action_id, 600)
equal(state._raw_stage1_rows[1].status, "DIRECT")
equal(state._raw_stage1_rows[1].display_text, "Action 600 #1 | [norm v0] 236+HP")

state.is_playing = true
state.playing_player = 0
assert(controller:begin_attempt(10, 0, 1, 5))
local idle = assert(controller:observe_frame(0, 11, 1, 5, 0))
equal(idle.status, "progress")
local passed = assert(controller:observe_frame(0, 12, 600, 0, 16))
equal(passed.status, "passed")
equal(state.success_timer, 90)
equal(state._raw_stage1_visual_step, 2)
equal(state._raw_stage1_terminal, "passed")
state.success_timer = 0
local passed_again = assert(controller:observe_frame(0, 13, 600, 1, 16))
equal(passed_again.status, "passed")
equal(state.success_timer, 0, "terminal success is applied once")

state.success_timer = 0
assert(controller:begin_attempt(15, 0, 600, 3, {
    admit_matching_initial = true,
}))
equal(state._raw_stage1_visual_step, 2,
    "matching Action active at demo arm must advance the first raw row")
equal(state._raw_stage1_terminal, "passed")

state.is_playing = false
assert(controller:prepare_recording(1))
state.is_recording = true
state.recording_player = 0
assert(controller:begin_recording("Ryu", {
    fighter_id = 1,
    control_mode = "classic",
    player_index = 0,
    initial_action_id = 1,
    initial_action_frame = 5,
    recorded_at = "2026-08-09T00:00:00Z",
}))
assert(controller:reseed_recording(0, 1, 8))
assert(controller:observe_frame(0, 21, 600, 0, 0))
assert(controller:observe_frame(0, 22, 600, 5, 0))
assert(controller:observe_frame(0, 23, 600, 0, 0))
local recorded = assert(controller:finish_recording("norm"))
equal(recorded:trace():count(), 2)
equal(#state._raw_stage1_rows, 2)
equal(state._raw_stage1_rows[1].action_id, 600)
equal(state._raw_stage1_rows[1].occurrence, 1)
equal(state._raw_stage1_rows[2].action_id, 600)
equal(state._raw_stage1_rows[2].occurrence, 2)
equal(state._raw_stage1_rows[2].display_text, "Action 600 #2 | [norm v0] 236+HP")
local v2_sequence = assert(controller:build_v2_sequence())
equal(v2_sequence[1].id, 600)
equal(v2_sequence[1].motion, "Action 600")
equal(v2_sequence[1].expected_combo, 2)
equal(v2_sequence[2].id, 600)
equal(v2_sequence[2].expected_combo, 2)
local save_diagnostic = controller:write_save_diagnostic("write_failed", {
    character = "Ryu",
})
equal(save_diagnostic.failure_phase, "save")
equal(save_diagnostic.failure_code, "write_failed")
equal(save_diagnostic.controller_status, "recorded")
equal(save_diagnostic.recording_observation.sample_count, 3)
equal(save_diagnostic.recording_observation.boundary_count, 2)
equal(save_diagnostic.recording_observation.invalid_sample_count, 0)
equal(save_diagnostic.recording_observation.last_sample.action_id, 600)
equal(written_path, "TrainingComboTrials_data/LastRawStage1Diagnostic.json")
equal(written_value.failure_code, "write_failed")
local meta = {}
assert(controller:attach_last_recording(meta, {
    timeline_ref = { source = "combo_v2", field = "timeline" },
}))
equal(meta.raw_stage1.environment.game_build, "sf6b_current")

print("raw stage1 controller tests passed")
