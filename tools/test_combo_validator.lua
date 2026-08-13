package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local Validator = require("func/ComboTrials/Validator")
local PendingAbsorb = require("func/ComboTrials/PendingAbsorb")
local ActionMatcher = require("func/ComboTrials/ActionMatcher")
local DebugTrace = require("func/ComboTrials/DebugTrace")

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

do
    local trace_state = { _runtime_auditing = true }
    DebugTrace.record_step_confirmation(trace_state, {
        step = 2,
        confirmation_frame = 100,
    })
    DebugTrace.record_visual_step_state(trace_state, {
        frame = 100,
        validation_step = 2,
        visual_step = 2,
    })
    DebugTrace.record_visual_step_state(trace_state, {
        frame = 101,
        validation_step = 2,
        visual_step = 2,
    })
    DebugTrace.record_visual_step_state(trace_state, {
        frame = 102,
        validation_step = 3,
        visual_step = 3,
    })
    assert(#trace_state._step_confirmation_trace == 1
            and #trace_state._visual_step_trace == 2,
        "audit step traces must preserve confirmations and deduplicate stable visual frames")
end

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

local auto_demo_chord_precursor = ActionMatcher.classify_runtime_transition({
    previous_step = { id = 628, motion = "2+HP" },
    expected_step = { id = 958, motion = "2+PP" },
    expected_action_matches_current = false,
    actual_action_id = 628,
    actual_motion = "2+HP",
    action_button_mask = 32 | 64,
    recent_button_mask = 32 | 64,
    input_anchor_kind = "button_press",
    input_truth_mode = true,
    frames_since_previous = 34,
    chord_completion_frames = 0,
    successor_matches_expected = true,
})
assert(auto_demo_chord_precursor.ignored == true
        and auto_demo_chord_precursor.reason == "partial_chord_precursor",
    "a fast replay must wait when a single-button Action is exposed by a complete same-frame PP chord")

local manual_chord_precursor = ActionMatcher.classify_runtime_transition({
    previous_step = { id = 628, motion = "2+HP" },
    expected_step = { id = 958, motion = "2+PP" },
    expected_action_matches_current = false,
    actual_action_id = 628,
    actual_motion = "2+HP",
    action_button_mask = 64,
    recent_button_mask = 32 | 64,
    input_anchor_kind = "button_press",
    input_truth_mode = true,
    frames_since_previous = 120,
    chord_completion_frames = 8,
    successor_matches_expected = true,
})
assert(manual_chord_precursor.ignored == true
        and manual_chord_precursor.reason == "partial_chord_precursor",
    "manual stagger within the chord completion window must use the same semantics")

local boundary_chord_precursor = ActionMatcher.classify_runtime_transition({
    expected_step = { id = 958, motion = "2+PP" },
    actual_action_id = 628,
    actual_motion = "2+HP",
    action_button_mask = 64,
    recent_button_mask = 32 | 64,
    input_anchor_kind = "button_press",
    input_truth_mode = true,
    chord_completion_frames = ActionMatcher.CHORD_COMPLETION_WINDOW,
    successor_visibility_frames = ActionMatcher.CHORD_COMPLETION_WINDOW
        + ActionMatcher.CHORD_ACTION_VISIBILITY_GRACE,
    successor_matches_expected = true,
})
assert(boundary_chord_precursor.ignored == true,
    "a completed chord must remain valid on the inclusive completion boundary")

local late_chord_precursor = ActionMatcher.classify_runtime_transition({
    expected_step = { id = 958, motion = "2+PP" },
    actual_action_id = 628,
    actual_motion = "2+HP",
    action_button_mask = 64,
    recent_button_mask = 32 | 64,
    input_anchor_kind = "button_press",
    input_truth_mode = true,
    chord_completion_frames = ActionMatcher.CHORD_COMPLETION_WINDOW + 1,
    successor_matches_expected = true,
})
assert(late_chord_precursor.ignored == false,
    "a chord completed after the bounded window must leave the single-button Action real")

local late_successor_chord = ActionMatcher.classify_runtime_transition({
    expected_step = { id = 958, motion = "2+PP" },
    actual_action_id = 628,
    actual_motion = "2+HP",
    action_button_mask = 64,
    recent_button_mask = 32 | 64,
    input_anchor_kind = "button_press",
    input_truth_mode = true,
    chord_completion_frames = ActionMatcher.CHORD_COMPLETION_WINDOW,
    successor_visibility_frames = ActionMatcher.CHORD_COMPLETION_WINDOW
        + ActionMatcher.CHORD_ACTION_VISIBILITY_GRACE + 1,
    successor_matches_expected = true,
})
assert(late_successor_chord.ignored == false,
    "a chord Action exposed after the visibility grace must not hide its predecessor")

local unrelated_third_punch = ActionMatcher.classify_runtime_transition({
    expected_step = { id = 958, motion = "2+PP" },
    actual_action_id = 628,
    actual_motion = "2+HP",
    action_button_mask = 64,
    recent_button_mask = 16 | 32 | 64,
    input_anchor_kind = "button_press",
    input_truth_mode = true,
    button_press_frames = {
        [64] = 100,
        [32] = 120,
        [16] = 123,
    },
    action_start_frame = 100,
    successor_visibility_frames = 22,
    successor_matches_expected = true,
})
assert(unrelated_third_punch.ignored == true,
    "a generic PP chord must complete on the second valid punch, not a later unrelated third punch")

local stale_earlier_punch = ActionMatcher.classify_runtime_transition({
    expected_step = { id = 958, motion = "2+PP" },
    actual_action_id = 628,
    actual_motion = "2+HP",
    action_button_mask = 64,
    recent_button_mask = 32 | 64,
    input_anchor_kind = "button_press",
    input_truth_mode = true,
    button_press_frames = {
        [16] = 50,
        [64] = 100,
        [32] = 120,
    },
    action_start_frame = 100,
    successor_visibility_frames = 22,
    successor_matches_expected = true,
})
assert(stale_earlier_punch.ignored == true,
    "same-family button history before the Action start must not alter chord completion timing")

local variant_chord_precursor = ActionMatcher.classify_runtime_transition({
    previous_step = { id = 628, motion = "2+HP" },
    expected_step = { id = 959, motion = "2+PP" },
    expected_action_matches_current = false,
    actual_action_id = 628,
    actual_motion = "2+HP",
    action_button_mask = 64,
    recent_button_mask = 32 | 64,
    input_anchor_kind = "button_press",
    input_truth_mode = true,
    frames_since_previous = 80,
    chord_completion_frames = 4,
    successor_matches_expected = true,
})
assert(variant_chord_precursor.ignored == true
        and variant_chord_precursor.reason == "partial_chord_precursor",
    "chord completion must follow the expected command instead of one runtime Action variant")
local contacted_hp_is_not_a_precursor = ActionMatcher.classify_runtime_transition({
    previous_step = { id = 628, motion = "2+HP" },
    expected_step = { id = 958, motion = "2+PP" },
    expected_action_matches_current = false,
    actual_action_id = 628,
    actual_motion = "2+HP",
    action_button_mask = 32 | 64,
    recent_button_mask = 32 | 64,
    input_anchor_kind = "button_press",
    input_truth_mode = true,
    actual_has_contact = true,
    actual_has_hit = true,
    frames_since_previous = 34,
    chord_completion_frames = 1,
    successor_matches_expected = true,
})
assert(contacted_hp_is_not_a_precursor.ignored == false,
    "a contacted single-button Action must never be hidden by chord completion")

local incomplete_triple_chord = ActionMatcher.classify_runtime_transition({
    expected_step = { id = 200, motion = "PPP" },
    actual_action_id = 100,
    actual_motion = "HP",
    action_button_mask = 64,
    recent_button_mask = 32 | 64,
    input_anchor_kind = "button_press",
    input_truth_mode = true,
    chord_completion_frames = 2,
    successor_matches_expected = true,
})
assert(incomplete_triple_chord.ignored == false,
    "a two-button edge must not be accepted as completion of an expected three-button chord")

local complete_triple_chord = ActionMatcher.classify_runtime_transition({
    expected_step = { id = 200, motion = "PPP" },
    actual_action_id = 100,
    actual_motion = "HP",
    action_button_mask = 64,
    recent_button_mask = 16 | 32 | 64,
    input_anchor_kind = "button_press",
    input_truth_mode = true,
    chord_completion_frames = 3,
    successor_matches_expected = true,
})
assert(complete_triple_chord.ignored == true,
    "a complete three-button chord must use the same bounded precursor rule")

local non_button_word = ActionMatcher.classify_runtime_transition({
    expected_step = { id = 200, motion = "PP" },
    actual_action_id = 100,
    actual_motion = "JUMP",
    action_button_mask = 64,
    recent_button_mask = 32 | 64,
    input_anchor_kind = "button_press",
    input_truth_mode = true,
    chord_completion_frames = 3,
    successor_matches_expected = true,
})
assert(non_button_word.ignored == false,
    "motion words ending in P or K must not be parsed as single attack buttons")

local wrong_strength_edge = ActionMatcher.classify_runtime_transition({
    expected_step = { id = 200, motion = "PP" },
    actual_action_id = 100,
    actual_motion = "HP",
    action_button_mask = 16,
    recent_button_mask = 16 | 32,
    input_anchor_kind = "button_press",
    input_truth_mode = true,
    chord_completion_frames = 3,
    successor_matches_expected = true,
})
assert(wrong_strength_edge.ignored == false,
    "a named single-button Action must be backed by that button's physical edge")

local explicit_pair_chord = ActionMatcher.classify_runtime_transition({
    expected_step = { id = 201, motion = "MP+HP" },
    actual_action_id = 100,
    actual_motion = "HP",
    action_button_mask = 64,
    recent_button_mask = 32 | 64,
    input_anchor_kind = "button_press",
    input_truth_mode = true,
    chord_completion_frames = 2,
    successor_matches_expected = true,
})
assert(explicit_pair_chord.ignored == true
        and explicit_pair_chord.reason == "partial_chord_precursor",
    "an explicit multi-button command must use the same chord-completion predicate")

local missing_successor_chord = ActionMatcher.classify_runtime_transition({
    expected_step = { id = 201, motion = "MP+HP" },
    actual_action_id = 100,
    actual_motion = "HP",
    action_button_mask = 64,
    recent_button_mask = 32 | 64,
    input_anchor_kind = "button_press",
    input_truth_mode = true,
    chord_completion_frames = 2,
    successor_matches_expected = false,
})
assert(missing_successor_chord.ignored == false,
    "live validation must not hide a single-button Action until the expected chord Action actually appears")

assert(ActionMatcher.should_defer_partial_chord({
        expected_step = { id = 201, motion = "MP+HP" },
        actual_motion = "HP",
        action_button_mask = 64,
        input_anchor_kind = "button_press",
        input_truth_mode = true,
        elapsed_frames = 8,
    }) == true,
    "live buffering must keep a possible chord precursor pending beyond the normal ghost window")
assert(ActionMatcher.should_defer_partial_chord({
        expected_step = { id = 201, motion = "MP+HP" },
        actual_motion = "HP",
        action_button_mask = 64,
        input_anchor_kind = "button_press",
        input_truth_mode = true,
        elapsed_frames = ActionMatcher.CHORD_COMPLETION_WINDOW,
    }) == true,
    "the boundary frame must remain pending so a just-completed chord Action can appear on the next tick")
assert(ActionMatcher.should_defer_partial_chord({
        expected_step = { id = 201, motion = "MP+HP" },
        actual_motion = "HP",
        action_button_mask = 64,
        input_anchor_kind = "button_press",
        input_truth_mode = true,
        elapsed_frames = ActionMatcher.CHORD_COMPLETION_WINDOW + 1,
    }) == true,
    "the first visibility-grace frame must remain pending")
assert(ActionMatcher.should_defer_partial_chord({
        expected_step = { id = 201, motion = "MP+HP" },
        actual_motion = "HP",
        action_button_mask = 64,
        input_anchor_kind = "button_press",
        input_truth_mode = true,
        elapsed_frames = ActionMatcher.CHORD_COMPLETION_WINDOW
            + ActionMatcher.CHORD_ACTION_VISIBILITY_GRACE,
    }) == true,
    "the last visibility-grace frame must remain pending")
assert(ActionMatcher.should_defer_partial_chord({
        expected_step = { id = 201, motion = "MP+HP" },
        actual_motion = "HP",
        action_button_mask = 64,
        input_anchor_kind = "button_press",
        input_truth_mode = true,
        elapsed_frames = ActionMatcher.CHORD_COMPLETION_WINDOW
            + ActionMatcher.CHORD_ACTION_VISIBILITY_GRACE + 1,
    }) == false,
    "a chord precursor candidate must be released after the visibility grace")
assert(ActionMatcher.should_defer_partial_chord({
        expected_step = { id = 201, motion = "MP+HP" },
        actual_motion = "HP",
        action_button_mask = 64,
        input_anchor_kind = "button_press",
        input_truth_mode = true,
        actual_has_contact = true,
        elapsed_frames = 8,
    }) == false,
    "a blocked or hit single-button Action must never be deferred as a chord precursor")
assert(ActionMatcher.should_defer_partial_chord({
        expected_step = { id = 201, motion = "PP" },
        actual_motion = "HP",
        action_button_mask = 64 | 512,
        input_anchor_kind = "button_press",
        input_truth_mode = true,
        elapsed_frames = 8,
    }) == false,
    "a mixed-family system input must not be delayed as a possible same-family chord")

local latched_hit, latched_block = ActionMatcher.latch_buffer_contact(
    false, false, true, false)
assert(latched_hit == true and latched_block == false,
    "a hit observed during chord deferral must remain attached to the buffered Action")
latched_hit, latched_block = ActionMatcher.latch_buffer_contact(
    latched_hit, true, false, false)
assert(latched_hit == true and latched_block == true,
    "buffered hit and block facts must survive later frames where contact is no longer visible")

local repeated_hp_after_chord_window = ActionMatcher.classify_runtime_transition({
    previous_step = { id = 958, motion = "2+PP" },
    expected_step = { id = 977, motion = ">HP (INSTANT)" },
    expected_action_matches_current = false,
    actual_action_id = 628,
    actual_motion = "2+HP",
    action_button_mask = 64,
    recent_button_mask = 64,
    input_anchor_kind = "button_press",
    input_truth_mode = true,
    frames_since_previous = 1,
    chord_completion_frames = ActionMatcher.CHORD_COMPLETION_WINDOW + 1,
    successor_matches_expected = true,
})
assert(repeated_hp_after_chord_window.ignored == false,
    "a later standalone 2HP must remain eligible for failure instead of being hidden as a PP precursor")

local derived_followup_after_chord = ActionMatcher.classify_runtime_transition({
    previous_step = { id = 958, motion = "2+PP" },
    expected_step = { id = 977, motion = ">HP (INSTANT)" },
    expected_action_matches_current = true,
    actual_action_id = 977,
    actual_motion = ">HP (INSTANT)",
    action_button_mask = 64,
    recent_button_mask = 64,
    input_anchor_kind = "button_press",
    input_truth_mode = true,
    frames_since_previous = 17,
})
assert(derived_followup_after_chord.ignored == false
        and derived_followup_after_chord.reason == "expected_action",
    "the derived Action after a completed chord must remain eligible to advance")

assert(Validator.hp_mismatch_kind(1050, 10500) == "environment_not_applied",
    "HP above the recorded target must identify an unapplied training environment")
assert(Validator.hp_mismatch_kind(1050, 900) == "actor_hp_reduced",
    "HP below the recorded target must remain a real actor-damage mismatch")
assert(Validator.hp_mismatch_kind(1050, 1050) == nil,
    "matching HP must not report an environment mismatch")

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

local attempt_start_sequence = {
    { id = 17, motion = "66", expected_combo = 0, delay_from_prev = 0 },
    { id = 740, motion = "RAWDR", expected_combo = 0, delay_from_prev = 5 },
}
local attempt_start_trial = {
    sequence = attempt_start_sequence,
    current_step = 2,
    last_played_frame = 80,
    success_timer = 0,
    fail_timer = 0,
}
local attempt_start_applied, attempt_start_step, attempt_start_diff =
    PendingAbsorb.apply_matched_step({
        state = attempt_start_trial,
        p_idx = 0,
        p_state = {},
        frame = 100,
        pf = { opponent_knocked_down = false },
        Validator = Validator,
        DebugTrace = { record_validation_debug = function() end },
        is_post_hit_setup_step = function() return false end,
        set_dummy_counter_type = function() end,
        d2d_cfg = { fail_display_frames = 120 },
    }, {
        expected = attempt_start_sequence[2],
        actual_action_id = 740,
        actual_motion = "RAWDR",
        actual_input = "66",
        frame = 100,
        combo_count = 0,
        actual_hp = 10000,
        match_reason = "id",
        action_instance = 44,
        attempt_start_timing_baseline = true,
    })
assert(attempt_start_applied == true
        and attempt_start_step == 2
        and attempt_start_diff == 0
        and attempt_start_trial.last_played_frame == 100,
    "a skipped Drive Rush prefix must baseline timing on the semantic Action")

local environment_mismatch_sequence = {
    {
        id = 958,
        motion = "2+PP",
        expected_combo = 0,
        expected_hp = 1050,
        damage_at_step = 960,
        has_hit = false,
        delay_from_prev = 34,
        last_frame_diff = 0,
    },
    {
        id = 977,
        motion = ">HP (INSTANT)",
        expected_combo = 2,
        expected_hp = 1050,
        damage_at_step = 1960,
        has_hit = true,
        delay_from_prev = 17,
    },
}
local environment_mismatch_trial = {
    sequence = environment_mismatch_sequence,
    current_step = 2,
    last_played_frame = 100,
    success_timer = 0,
    fail_timer = 0,
}
local environment_applied = PendingAbsorb.apply_matched_step({
    state = environment_mismatch_trial,
    p_idx = 0,
    p_state = {},
    frame = 117,
    pf = { opponent_knocked_down = false },
    Validator = Validator,
    DebugTrace = {
        record_validation_debug = function() end,
        log_trial_failure = function() end,
    },
    is_post_hit_setup_step = function(step_idx) return step_idx == 1 end,
    set_dummy_counter_type = function() end,
    d2d_cfg = { fail_display_frames = 120 },
    file_system = {},
    act_id_reverse_enum = {},
}, {
    expected = environment_mismatch_sequence[2],
    actual_action_id = 977,
    actual_motion = "HP",
    actual_input = "HP",
    frame = 117,
    combo_count = 1,
    actual_hp = 10500,
    match_reason = "id",
    action_instance = 38,
})
assert(environment_applied == false
        and environment_mismatch_trial.fail_reason
            == "TRAINING ENVIRONMENT HP NOT APPLIED",
    "an unapplied actor HP snapshot must not masquerade as a meaty timing failure")

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

do
    local pending_state = {
        sequence = {
            { id = 605, expected_combo = 3 },
            { id = 700, delay_from_prev = 20 },
        },
        current_step = 1,
        success_timer = 0,
        fail_timer = 0,
    }
    local pending_probe = {
        step = 1,
        frame = 100,
        frame_diff = 0,
        current_combo = 1,
        action_instance = 9,
    }
    local stored = PendingAbsorb.store({
        state = pending_state,
        p_state = { profile_name = "AnyCharacter" },
        pf = { current_combo = 1 },
        frame = 100,
    }, pending_state.sequence[1], {
        block_reason = "combo_not_reached",
        allow_pending_absorb = true,
        actual_action_id = 606,
        absorb_ids = "606",
    }, pending_probe, 9000)
    assert(stored == true
            and pending_state._pending_current_absorb.actual_action_id == 606,
        "pending absorb storage must use the data policy instead of a character name")
end

do
    local repeat_state = {
        sequence = {
            {
                id = 614,
                motion = "2+LP",
                expected_combo = 2,
                has_hit = true,
            },
            {
                id = 614,
                motion = "2+LP",
                expected_combo = 3,
                expected_hp = 10000,
                delay_from_prev = 6,
            },
        },
        current_step = 2,
        last_played_frame = 100,
        success_timer = 0,
        fail_timer = 0,
        is_playing = true,
        playing_player = 0,
        _demo_timing_ui_baseline = true,
    }
    local debug_trace = {
        record_match_probe = function() end,
        record_validation_debug = function() end,
    }
    local repeat_ctx = {
        state = repeat_state,
        p_idx = 0,
        p_state = {
            profile_name = "Blanka",
            current_action_instance = 12,
        },
        frame = 106,
        pf = {
            current_combo = 2,
            p_char = { vital_new = 10000 },
            opponent_knocked_down = false,
        },
        Validator = Validator,
        DebugTrace = debug_trace,
        is_post_hit_setup_step = function() return false end,
        set_dummy_counter_type = function() end,
        d2d_cfg = { fail_display_frames = 120 },
        file_system = {},
        act_id_reverse_enum = {},
    }
    local stored = PendingAbsorb.store(repeat_ctx, repeat_state.sequence[2], {
        block_reason = "combo_not_reached",
        allow_pending_absorb = true,
        actual_action_id = 614,
        match_reason = "id",
        source = "same_action_light_repeat_contact",
    }, {
        step = 2,
        frame = 106,
        frame_diff = 10,
        current_combo = 2,
        action_instance = 12,
        actual_motion = "2+LP",
        actual_input = "2+LP",
    }, 10000)
    assert(stored == true and repeat_state.current_step == 2,
        "audit replay timing drift must not bypass repeated-light contact confirmation")

    repeat_ctx.frame = 120
    repeat_ctx.pf.current_combo = 3
    local confirmed = PendingAbsorb.check(repeat_ctx, "repeat_light_contact")
    assert(confirmed == true
            and repeat_state.current_step == 3
            and repeat_state.sequence[2].action_instance == 12,
        "the repeated light step must advance only after combo growth confirms contact")
end

print("combo validator tests passed")
