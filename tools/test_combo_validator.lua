package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local Validator = require("func/ComboTrials/Validator")
local PendingAbsorb = require("func/ComboTrials/PendingAbsorb")

assert(Validator.counter_type_for_display({
    motion = "PARRY",
    counter_type = 2,
    has_hit = false,
}) == 0, "a non-hit Parry must never display a punish-counter label")
assert(Validator.counter_type_for_display({
    motion = "4HK",
    _ct_counter_label_type = 2,
    has_hit = false,
}) == 2, "the menu-derived expected label must not depend on mutable runtime hit flags")
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

local terminal_whiff_trial = {
    {
        id = 929,
        motion = "214+HP",
        expected_combo = 6,
        has_hit = true,
    },
    {
        id = 652,
        motion = "j.HP (空挥)",
        expected_combo = 0,
        has_hit = false,
        delay_from_prev = 29,
        expected_hp = 2500,
    },
}
assert(Validator.is_terminal_explicit_whiff(terminal_whiff_trial, 2) == true,
    "an explicit final whiff must be identified")
assert(terminal_whiff_trial[2].validation_role == nil,
    "a terminal whiff must not inherit pressure-tail action/timeout tolerance")
assert(Validator.check_hp(2500, 10000, true, terminal_whiff_trial[2], true) == true,
    "a terminal whiff must tolerate health restoration after the hit sequence")
assert(Validator.check_hp(2500, 10000, true, terminal_whiff_trial[2], false) == false,
    "the same whiff must keep strict HP validation outside the terminal position")

local non_terminal_whiff_trial = {
    {
        id = 652,
        motion = "j.HP (空挥)",
        expected_combo = 0,
        has_hit = false,
    },
    {
        id = 600,
        motion = "LP",
        expected_combo = 1,
        has_hit = true,
    },
}
assert(Validator.is_terminal_explicit_whiff(non_terminal_whiff_trial, 1) == false,
    "a non-terminal whiff must keep normal validation")
assert(non_terminal_whiff_trial[1].validation_role == nil,
    "terminal-whiff detection must not mutate a non-terminal whiff")

local untagged_trial = {
    {
        id = 652,
        motion = "j.HP",
        expected_combo = 0,
        has_hit = false,
    },
}
assert(Validator.is_terminal_explicit_whiff(untagged_trial, 1) == false,
    "an untagged zero-combo action must not receive the HP exception")

local combo_counted_whiff_trial = {
    {
        id = 652,
        motion = "j.HP (空挥)",
        expected_combo = 1,
        has_hit = false,
    },
}
assert(Validator.is_terminal_explicit_whiff(combo_counted_whiff_trial, 1) == false,
    "a combo-counted action must not receive the HP exception")

local landed_whiff_trial = {
    {
        id = 652,
        motion = "j.HP (空挥)",
        expected_combo = 0,
        has_hit = true,
    },
}
assert(Validator.is_terminal_explicit_whiff(landed_whiff_trial, 1) == false,
    "a landed action must not receive the HP exception")

local runtime_trial = {
    sequence = terminal_whiff_trial,
    current_step = 2,
    last_played_frame = 100,
    success_timer = 0,
    fail_timer = 0,
}
local applied, applied_step, applied_diff = PendingAbsorb.apply_matched_step({
    state = runtime_trial,
    p_idx = 0,
    p_state = {},
    frame = 129,
    pf = { opponent_knocked_down = false },
    Validator = Validator,
    DebugTrace = { record_validation_debug = function() end },
    is_post_hit_setup_step = function(step_idx) return step_idx == 1 end,
    set_dummy_counter_type = function() end,
    d2d_cfg = { fail_display_frames = 120 },
}, {
    expected = terminal_whiff_trial[2],
    actual_action_id = 652,
    actual_motion = "j.HP",
    actual_input = "3+HP",
    frame = 129,
    combo_count = 0,
    actual_hp = 10000,
    match_reason = "id",
    action_instance = 42,
})
assert(applied == true and applied_step == 2 and applied_diff == 0,
    "the recorded terminal-whiff Action ID at the recorded timing must pass")
assert(runtime_trial.current_step == 3 and runtime_trial.fail_timer == 0,
    "the terminal whiff must advance without a false HP failure")
assert(runtime_trial.success_timer == 0,
    "the HP exception must not grant pressure-tail auto-success")

print("combo validator tests passed")
