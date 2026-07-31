package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local Validator = require("func/ComboTrials/Validator")
local PendingAbsorb = require("func/ComboTrials/PendingAbsorb")
local ActionMatcher = require("func/ComboTrials/ActionMatcher")

assert(ActionMatcher.should_observe_dash_direction_edge(0, 0) == true,
    "a direction-only frame may participate in a dash pair")
assert(ActionMatcher.should_observe_dash_direction_edge(32 | 256, 0) == false,
    "a Parry button edge must own its frame instead of also seeding a dash pair")
assert(ActionMatcher.should_observe_dash_direction_edge(0, 32) == false,
    "a button-release frame must not also seed a dash pair")

assert(ActionMatcher.sequence_uses_input_truth({
    { raw_inputs = { 0, 2, 18 } },
}) == true, "a raw-input recording must use strict input/Action truth")
assert(ActionMatcher.sequence_uses_input_truth({
    { timeline = { { frame = 1, input = 18 } } },
}) == false, "a legacy timeline-only trial must retain compatibility matching")

local ignored_kimberly_parent = { ignore = true }
assert(ActionMatcher.should_admit_ignored_expected_action(
        true,
        { id = 900, motion = "236+K" },
        900,
        ignored_kimberly_parent
    ) == true,
    "raw-input Action truth must override a legacy ignore rule for the expected ID")
assert(ActionMatcher.should_admit_ignored_expected_action(
        false,
        { id = 900, motion = "236+K" },
        900,
        ignored_kimberly_parent
    ) == false,
    "timeline-only legacy files must retain their ignore compatibility rules")
assert(ActionMatcher.should_admit_ignored_expected_action(
        true,
        { id = 900, motion = "236+K" },
        905,
        ignored_kimberly_parent
    ) == false,
    "raw-input truth must not admit a different runtime Action")

local unanchored_internal_transition = ActionMatcher.classify_runtime_transition({
    previous_step = { id = 904, motion = "[4]6+HP" },
    expected_step = { id = 34, motion = "8" },
    expected_action_matches_current = false,
    actual_action_id = 5,
    input_truth_mode = true,
    frames_since_previous = 40,
})
assert(unanchored_internal_transition.ignored == true
    and unanchored_internal_transition.reason == "unanchored_input_truth_transition",
    "an unanchored internal Action must not fail a raw-input trial")

local anchored_wrong_transition = ActionMatcher.classify_runtime_transition({
    previous_step = { id = 904, motion = "[4]6+HP" },
    expected_step = { id = 34, motion = "8" },
    expected_action_matches_current = false,
    actual_action_id = 674,
    input_anchor_kind = "button_press",
    input_truth_mode = true,
    frames_since_previous = 40,
})
assert(anchored_wrong_transition.ignored == false,
    "a fresh player input must keep an unexpected Action eligible for failure")

local exact_unanchored_transition = ActionMatcher.classify_runtime_transition({
    previous_step = { id = 904, motion = "[4]6+HP" },
    expected_step = { id = 34, motion = "8" },
    expected_action_matches_current = true,
    actual_action_id = 34,
    input_truth_mode = true,
    frames_since_previous = 45,
})
assert(exact_unanchored_transition.ignored == false
    and exact_unanchored_transition.reason == "expected_action",
    "the recorded Action ID must remain valid even when it has no button anchor")

local held_parry_transition = ActionMatcher.classify_runtime_transition({
    previous_step = { id = 480, motion = "PARRY" },
    expected_step = { id = 630, motion = "2+HP" },
    expected_action_matches_current = false,
    actual_action_id = 740,
    frames_since_previous = 6,
})
assert(held_parry_transition.ignored == true
    and held_parry_transition.reason == "unanchored_drive_parry_phase_transition",
    "a held-Parry phase transition without a new input must not fail the next trial step")

local anchored_drive_rush = ActionMatcher.classify_runtime_transition({
    previous_step = { id = 480, motion = "PARRY" },
    expected_step = { id = 630, motion = "2+HP" },
    expected_action_matches_current = false,
    actual_action_id = 740,
    input_anchor_kind = "double_tap",
    input_anchor_motion = "66",
    frames_since_previous = 6,
})
assert(anchored_drive_rush.ignored == false,
    "a fresh directional input must keep an unexpected RAW DR intentional")

local backward_dash_parry_phase = ActionMatcher.classify_runtime_transition({
    previous_step = { id = 480, motion = "PARRY" },
    expected_step = { id = 630, motion = "2+HP" },
    expected_action_matches_current = false,
    actual_action_id = 740,
    input_anchor_kind = "double_tap",
    input_anchor_motion = "44",
    frames_since_previous = 6,
})
assert(backward_dash_parry_phase.ignored == true
    and backward_dash_parry_phase.reason == "drive_rush_incompatible_direction_anchor",
    "a backward 44 input cannot be treated as the causal anchor of RAW DR")

local expected_drive_rush = ActionMatcher.classify_runtime_transition({
    previous_step = { id = 480, motion = "PARRY" },
    expected_step = { id = 740, motion = "RAW DR" },
    expected_action_matches_current = true,
    actual_action_id = 740,
    frames_since_previous = 6,
})
assert(expected_drive_rush.ignored == false,
    "an explicitly recorded RAW DR step must always remain validatable")

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

local segmented_previous = {
    expected_combo = 20,
    damage_at_step = 2985,
    has_contact = true,
}
local segmented_restart = {
    expected_combo = 1,
    damage_at_step = 3345,
    has_contact = true,
}
assert(Validator.is_expected_combo_restart_step(segmented_restart, segmented_previous),
    "a lower positive counter with increasing damage must identify a recorded OKI restart")
assert(Validator.check_combo({
    expected = segmented_restart,
    prev_step = segmented_previous,
    current_combo = 1,
}) == true, "the first hit of a recorded OKI restart must validate against the new segment")
assert(Validator.check_combo({
    expected = segmented_restart,
    prev_step = segmented_previous,
    current_combo = 2,
}) == false, "an OKI restart must not hide the wrong new-segment combo count")
assert(Validator.is_expected_combo_restart_step({
    expected_combo = 1,
    damage_at_step = 2985,
    has_contact = true,
}, segmented_previous) == false,
    "a lower counter without new damage must not create an implicit restart")
assert(Validator.is_expected_combo_restart_step({
    expected_combo = 1,
    damage_at_step = 3345,
    has_contact = false,
}, segmented_previous) == false,
    "a non-contact setup row must not create an implicit restart")

local pressure_trial = {
    {
        id = 600,
        motion = "LP",
        expected_combo = 1,
        damage_at_step = 300,
        has_hit = true,
    },
    {
        id = 17,
        motion = "66",
        expected_combo = 0,
        damage_at_step = 300,
        has_hit = false,
    },
    {
        id = 666,
        motion = "6+HP",
        expected_combo = 0,
        damage_at_step = 300,
        has_hit = false,
        has_contact = true,
        hit_result = "block",
        was_blocked = true,
    },
}
assert(Validator.annotate_terminal_pressure_tail(pressure_trial) == true
    and Validator.is_pressure_tail_step(pressure_trial[3]),
    "a post-hit terminal non-damaging Action must become a pressure tail")
assert(Validator.requires_block_outcome(pressure_trial[3]) == false,
    "a pressure tail must not wait for the generic block-contact window")
assert(Validator.check_combo({
    expected = pressure_trial[3],
    prev_step = pressure_trial[2],
    current_combo = 0,
}) == true, "a pressure tail must not require another combo-count increment")

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

local pressure_runtime = {
    sequence = pressure_trial,
    current_step = 3,
    last_played_frame = 100,
    success_timer = 0,
    fail_timer = 0,
}
local pressure_applied = PendingAbsorb.apply_matched_step({
    state = pressure_runtime,
    p_idx = 0,
    p_state = {},
    frame = 119,
    pf = { opponent_knocked_down = false },
    Validator = Validator,
    DebugTrace = { record_validation_debug = function() end },
    is_post_hit_setup_step = function() return false end,
    set_dummy_counter_type = function() end,
    d2d_cfg = { fail_display_frames = 120 },
}, {
    expected = pressure_trial[3],
    actual_action_id = 666,
    actual_motion = "6+HP",
    actual_input = "6+HP",
    frame = 119,
    combo_count = 0,
    actual_hp = 10000,
    match_reason = "id",
    action_instance = 43,
})
assert(pressure_applied == true
    and pressure_runtime.current_step == 4
    and pressure_runtime.success_timer == 120,
    "the exact terminal pressure Action must finish immediately without a hit")

print("combo validator tests passed")
