package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local TrainingEnvironment = require("func/ComboTrials/TrainingEnvironment")

local action_type, jump_type, action_source = TrainingEnvironment.resolve_dummy_action({
    dummy_action_type = 2,
    dummy_jump_type = 1,
    _xt_meta = {
        environment = {
            dummy_action_type = 1,
            dummy_jump_type = 0,
        },
    },
})
assert(action_type == 2 and jump_type == 1 and action_source == "step",
    "step action/jump pair must have highest priority")

action_type, jump_type, action_source = TrainingEnvironment.resolve_dummy_action({
    _xt_meta = {
        environment = {
            dummy_action_type = 2,
            dummy_jump_type = 3,
        },
    },
})
assert(action_type == 2 and jump_type == 3 and action_source == "environment",
    "v2 environment action/jump pair must be restored")

action_type, jump_type, action_source = TrainingEnvironment.resolve_dummy_action({
    dummy_action_type = 0,
    requires_dummy_crouch = true,
    _xt_meta = {
        environment = {
            dummy_action_type = 0,
            dummy_stance = "stand",
        },
    },
})
assert(action_type == 1 and jump_type == 0
        and action_source == "step_requires_crouch",
    "an explicit crouch requirement must override stale legacy stand fields")

local runtime_jump, was_random = TrainingEnvironment.resolve_runtime_jump_type(3, 0)
assert(runtime_jump == 0 and was_random == true, "random jump must resolve to vertical when rolled")
runtime_jump, was_random = TrainingEnvironment.resolve_runtime_jump_type(3, 1)
assert(runtime_jump == 1 and was_random == true, "random jump must resolve to front when rolled")
runtime_jump, was_random = TrainingEnvironment.resolve_runtime_jump_type(3, 2)
assert(runtime_jump == 2 and was_random == true, "random jump must resolve to back when rolled")
runtime_jump, was_random = TrainingEnvironment.resolve_runtime_jump_type(1, 2)
assert(runtime_jump == 1 and was_random == false, "fixed jump type must not be randomized")

action_type, jump_type, action_source = TrainingEnvironment.resolve_dummy_action({
    _xt_meta = {
        environment = {
            dummy_stance = "jump",
        },
    },
})
assert(action_type == 2 and jump_type == 0 and action_source == "environment_stance",
    "generic jump stance must fall back to a vertical jump")

action_type, jump_type, action_source = TrainingEnvironment.resolve_dummy_action({})
assert(action_type == nil and jump_type == nil and action_source == "unrecorded",
    "unrecorded action must remain available for legacy inference")

action_type, jump_type, action_source = TrainingEnvironment.resolve_dummy_action({
    recorded_by = 0,
    scene_state = {
        players = {
            p1 = { status = { stance = "standing" } },
            p2 = { status = { stance = "airborne" } },
        },
    },
})
assert(action_type == 2 and jump_type == 0 and action_source == "scene_defender_stance",
    "only the recorded defender stance may control dummy behavior")

local guard_type, source = TrainingEnvironment.resolve_dummy_guard_type({
    _xt_meta = {
        environment = {
            dummy_guard_type = 3,
        },
    },
}, 0)
assert(guard_type == 3 and source == "recorded", "recorded guard type must override the room")

guard_type, source = TrainingEnvironment.resolve_dummy_guard_type({
    dummy_guard = "after_first_hit",
}, 3)
assert(guard_type == 2 and source == "recorded_name", "legacy named guard type must remain supported")

guard_type, source = TrainingEnvironment.resolve_dummy_guard_type({
    dummy_guard_type = 1,
}, 3)
assert(guard_type == 2 and source == "recorded",
    "short-lived invalid value 1 must normalize to guard-after-first-hit value 2")

guard_type, source = TrainingEnvironment.resolve_dummy_guard_type({
    has_piyo = true,
    has_hit = false,
}, 0)
assert(guard_type == 3 and source == "legacy_blocked_wall_stun",
    "legacy blocked wall-stun recordings must restore full guard")

guard_type, source = TrainingEnvironment.resolve_dummy_guard_type({}, 4)
assert(guard_type == 4 and source == "training_room",
    "legacy recordings without evidence must preserve the room setting")

guard_type, source = TrainingEnvironment.resolve_dummy_guard_type({}, 99)
assert(guard_type == 2 and source == "legacy_default", "invalid legacy fallback must use the safe default")

guard_type, source = TrainingEnvironment.resolve_dummy_guard_type({
    dummy_guard_type = 5,
}, 0)
assert(guard_type == 5 and source == "recorded", "count guard type must remain supported")

local guard_count
guard_count, source = TrainingEnvironment.resolve_dummy_guard_count({
    _xt_meta = { environment = { dummy_guard_count = 2 } },
}, 10)
assert(guard_count == 2 and source == "recorded", "recorded guard count must override the room")

guard_count, source = TrainingEnvironment.resolve_dummy_guard_count({}, 10)
assert(guard_count == 10 and source == "training_room", "missing guard count must preserve the room")

guard_count, source = TrainingEnvironment.resolve_dummy_guard_count({}, 0)
assert(guard_count == nil and source == "unrecorded", "invalid missing guard count must stay unrecorded")

assert(TrainingEnvironment.guard_count_to_runtime(3) == 2,
    "user-visible guard count must encode to the zero-based game value")
assert(TrainingEnvironment.guard_count_from_runtime(2) == 3,
    "zero-based game guard count must decode to the user-visible value")
assert(TrainingEnvironment.guard_count_to_runtime(31) == nil,
    "out-of-range user-visible guard count must be rejected")

local advanced = TrainingEnvironment.resolve_recorded_settings({
    _xt_meta = {
        environment = {
            dummy_action_type = 5,
            dummy_cpu_level = 8,
            dummy_counter_type = 3,
            dummy_counter_weight_normal = 10,
            dummy_guard_switching = false,
            dummy_guard_only_type = 3,
            dummy_drive_parry_type = 2,
            dummy_drive_reversal_type = 3,
            dummy_drive_reversal_delay = 5,
            dummy_drive_reversal_count = 6,
            dummy_drive_reversal_weight_none = 10,
            dummy_drive_reversal_weight_guard = 9,
            dummy_drive_reversal_weight_wakeup = 8,
            dummy_throw_escape_type = 2,
            dummy_wakeup_type = 1,
        },
    },
})
assert(advanced.dummy_action_type == 5 and advanced.dummy_cpu_level == 8,
    "CPU dummy settings must remain portable")
assert(advanced.dummy_counter_type == 3 and advanced.dummy_counter_weight_normal == 10,
    "random counter and T/detail weights must be preserved")
assert(advanced.dummy_guard_switching == false and advanced.dummy_guard_only_type == 3,
    "false guard switching and random guard-only type must not be dropped")
assert(advanced.dummy_drive_parry_type == 2
        and advanced.dummy_drive_reversal_type == 3
        and advanced.dummy_drive_reversal_delay == 5,
    "drive defense settings must be restored as native menu values")
assert(advanced.dummy_throw_escape_type == 2 and advanced.dummy_wakeup_type == 1,
    "throw escape and wakeup settings must remain portable")
assert(TrainingEnvironment.has_recorded_defense_settings({
    dummy_wakeup_type = 0,
}) == true, "explicit zero-valued defense settings must count as recorded")
assert(TrainingEnvironment.has_recorded_defense_settings({}) == false,
    "legacy JSON without defense fields must retain the legacy cleanup path")

assert(TrainingEnvironment.counter_type_from_runtime(2, 2) == 3,
    "native random counter pair must decode to the portable random value")
assert(TrainingEnvironment.counter_type_from_runtime(0, 1) == 2,
    "native punish counter must decode correctly")
local migrated_counter_sequence = {
    {
        id = 480,
        motion = "PARRY (PC)",
        dummy_counter_type = 0,
        counter_type = 2,
        combo_stats = { hit_type = "PC" },
        _xt_meta = {
            dummy_counter_type = 0,
            environment = { dummy_counter_type = 0 },
        },
    },
    {
        id = 669,
        motion = "4HK (确反康)",
        counter_type = 2,
        expected_combo = 1,
        has_hit = true,
    },
}
local fixed_counter, contact_step, counter_source =
    TrainingEnvironment.normalize_counter_policy(migrated_counter_sequence, true)
assert(fixed_counter == 2 and counter_source == "legacy_consensus",
    "matching legacy summary and step facts must repair a migrated NORMAL placeholder")
assert(contact_step == 2 and migrated_counter_sequence[2].has_contact == true,
    "the first actual contact must be retained independently of the menu value")
assert(migrated_counter_sequence[1].counter_type == nil
        and migrated_counter_sequence[2].counter_type == nil,
    "normalization must remove all per-step counter rules")
assert(migrated_counter_sequence[1].motion == "PARRY"
        and migrated_counter_sequence[2].motion == "4HK",
    "normalization must remove counter labels embedded in commands")
local explicit_normal_sequence = {
    {
        combo_stats = { hit_type = "PC" },
        counter_type = 2,
        _xt_meta = { environment = { dummy_counter_type = 0 } },
    },
}
local explicit_normal, _, explicit_normal_source =
    TrainingEnvironment.normalize_counter_policy(explicit_normal_sequence, false)
assert(explicit_normal == 0 and explicit_normal_source == "environment",
    "disabling legacy inference must preserve the canonical fixed menu value")
assert(TrainingEnvironment.drive_reversal_count_to_runtime(6) == 5,
    "drive reversal count must encode to the zero-based native value")
assert(TrainingEnvironment.drive_reversal_count_from_runtime(5) == 6,
    "drive reversal count must decode to the user-visible value")
assert(TrainingEnvironment.cpu_level_to_runtime(8) == 7,
    "CPU level must encode to the zero-based native value")
assert(TrainingEnvironment.cpu_level_from_runtime(0) == 1,
    "CPU level must decode to the user-visible value")

print("combo training environment tests passed")
