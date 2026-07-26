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

print("combo training environment tests passed")
