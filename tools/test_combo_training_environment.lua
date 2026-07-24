package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local TrainingEnvironment = require("func/ComboTrials/TrainingEnvironment")

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
