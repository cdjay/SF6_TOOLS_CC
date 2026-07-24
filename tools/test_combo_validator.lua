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

print("combo validator tests passed")
