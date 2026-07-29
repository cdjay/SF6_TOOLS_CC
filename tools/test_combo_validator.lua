package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local Validator = require("func/ComboTrials/Validator")

assert(Validator.counter_type_for_display({
    motion = "PARRY",
    counter_type = 2,
    has_hit = false,
}) == 0, "a non-hit Parry must never display a punish-counter label")
assert(Validator.counter_type_for_display({
    motion = "4HK",
    counter_type = 2,
    has_hit = true,
}) == 2, "the action that actually hit must retain its punish-counter label")

local previous_hit = {
    expected_combo = 2,
    damage_at_step = 1470,
}
local drive_rush_transition = {
    expected_combo = 2,
    damage_at_step = 1470,
}

assert(Validator.is_non_damage_transition(drive_rush_transition, previous_hit),
    "equal combo and damage totals must identify a non-damaging transition")
assert(Validator.check_combo({
    expected = drive_rush_transition,
    prev_step = previous_hit,
    current_combo = 3,
}) == true, "a transition must tolerate one delayed combo-count increment")

assert(Validator.check_combo({
    expected = drive_rush_transition,
    prev_step = previous_hit,
    current_combo = 4,
}) == false, "a transition must not hide multiple unexpected hits")

assert(Validator.check_combo({
    expected = {
        expected_combo = 2,
        damage_at_step = 1600,
    },
    prev_step = previous_hit,
    current_combo = 3,
}) == false, "a damaging step must keep strict combo validation")

assert(Validator.check_combo({
    expected = {
        expected_combo = 3,
        damage_at_step = 1929,
    },
    prev_step = previous_hit,
    current_combo = 3,
}) == true, "the existing same-frame current-hit tolerance must remain")

local absolute_hp_trial = {
    {
        expected_hp = 10000,
        scene_state = {
            schema = "xt.combo_trial.scene.v2",
            recorded_by = 0,
            players = {
                p1 = { resources = { hp = 10000 } },
                p2 = { resources = { hp = 10000 } },
            },
        },
    },
    {
        expected_hp = 10000,
        actual_hp = 1,
    },
    {
        expected_hp = 10000,
    },
}
assert(Validator.check_hp(10000, 1, true, absolute_hp_trial[3]) == false,
    "v2 trials must reject the wrong absolute HP")

print("combo validator tests passed")
