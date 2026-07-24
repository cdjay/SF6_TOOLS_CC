package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local Validator = require("func/ComboTrials/Validator")

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

local legacy_deejay_double_dash = {
    {
        expected_hp = 10000,
    },
    {
        expected_hp = 10000,
        actual_hp = 1,
    },
    {
        expected_hp = 10000,
    },
}
local legacy_hp_context = Validator.build_hp_context(legacy_deejay_double_dash, 3)
assert(legacy_hp_context and legacy_hp_context.legacy_relative_hp == true,
    "legacy trials without an HP snapshot must use a relative HP baseline")
assert(Validator.check_hp(10000, 1, true, legacy_deejay_double_dash[3], legacy_hp_context) == true,
    "a legacy setup must accept unchanged runtime HP even when it differs from recorded HP")
assert(Validator.check_hp(10000, 900, true, legacy_deejay_double_dash[3], {
    legacy_relative_hp = true,
    previous_expected_hp = 10000,
    previous_actual_hp = 1000,
}) == false, "a legacy setup must still reject unexpected HP loss")

local snapshot_trial = {
    {
        snapshot_gauges = {
            attacker = {
                current_hp = 10000,
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
assert(Validator.build_hp_context(snapshot_trial, 3) == nil,
    "trials with an explicit attacker HP snapshot must keep absolute validation")
assert(Validator.check_hp(10000, 1, true, snapshot_trial[3],
    Validator.build_hp_context(snapshot_trial, 3)) == false,
    "explicit HP snapshot trials must reject the wrong absolute HP")

print("combo validator tests passed")
