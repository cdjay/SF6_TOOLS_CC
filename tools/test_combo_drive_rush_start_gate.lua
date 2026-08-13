package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local consumer = require("func/ComboTrials/UnifiedActionConsumer")

local function assert_ignored(params, message)
    local result = consumer.classify_runtime_transition(params)
    assert(result.ignored == true
            and result.reason == "attempt_start_leading_precursor",
        string.format("%s (ignored=%s reason=%s)",
            message, tostring(result.ignored), tostring(result.reason)))
end

local function assert_strict(params, message)
    local result = consumer.classify_runtime_transition(params)
    assert(result.ignored ~= true
            and result.reason ~= "attempt_start_leading_precursor",
        string.format("%s (ignored=%s reason=%s)",
            message, tostring(result.ignored), tostring(result.reason)))
end

local source = {
    { id = 38, motion = "7", delay_from_prev = 0 },
    { id = 17, motion = "66", delay_from_prev = 3 },
    { id = 480, motion = "PARRY", delay_from_prev = 2 },
    { id = 740, motion = "RAWDR", delay_from_prev = 5 },
    { id = 630, motion = "2HP", delay_from_prev = 20 },
    { id = 18, motion = "44", delay_from_prev = 12 },
}
local normalized = consumer.normalize_sequence(source)
assert(normalized.ok == true
        and normalized.prefix_length == 1
        and normalized.inline_removed_count == 2
        and #normalized.sequence == 3
        and normalized.sequence[1].id == 740
        and normalized.sequence[2].id == 630
        and normalized.sequence[3].id == 18,
    "the shared sequence projection must remove only the contiguous prefix")

local inline_source = {
    { id = 606, motion = "HP", delay_from_prev = 0 },
    { id = 17, motion = "66", delay_from_prev = 12 },
    { id = 17, motion = "66", delay_from_prev = 20 },
    { id = 480, motion = "PARRY", delay_from_prev = 2 },
    { id = 500, motion = "drive rush", delay_from_prev = 3 },
    { id = 615, motion = "HK", delay_from_prev = 18 },
}
local inline_normalized = consumer.normalize_sequence(inline_source)
assert(inline_normalized.ok == true
        and inline_normalized.inline_removed_count == 2
        and inline_normalized.first_source_index == 1
        and #inline_normalized.sequence == 4
        and inline_normalized.sequence[1].id == 606
        and inline_normalized.sequence[2].id == 17
        and inline_normalized.sequence[3].id == 500
        and inline_normalized.sequence[3].delay_from_prev == 25
        and inline_normalized.sequence[4].id == 615,
    "only the final fast 66 and Parry owned by RAW DR may be projection-only noise")

local slow_dash = consumer.normalize_sequence({
    { id = 606, motion = "HP", delay_from_prev = 0 },
    { id = 17, motion = "66", delay_from_prev = 20 },
    { id = 500, motion = "drive rush", delay_from_prev = 6 },
})
assert(#slow_dash.sequence == 3 and slow_dash.inline_removed_count == 0,
    "a standalone 66 outside the RAW DR startup window must remain strict")

local slow_parry = consumer.normalize_sequence({
    { id = 606, motion = "HP", delay_from_prev = 0 },
    { id = 480, motion = "PARRY", delay_from_prev = 20 },
    { id = 500, motion = "drive rush", delay_from_prev = 13 },
})
assert(#slow_parry.sequence == 3 and slow_parry.inline_removed_count == 0,
    "a standalone Parry outside the RAW DR transition window must remain strict")

local inherited_contact = consumer.normalize_sequence({
    {
        id = 615,
        motion = "HK",
        expected_combo = 6,
        damage_at_step = 2687,
        has_hit = true,
        has_contact = true,
        delay_from_prev = 0,
    },
    {
        id = 17,
        motion = "66",
        expected_combo = 6,
        damage_at_step = 2687,
        has_hit = true,
        has_contact = true,
        delay_from_prev = 53,
    },
    {
        id = 500,
        motion = "drive rush",
        expected_combo = 6,
        damage_at_step = 2687,
        has_hit = true,
        has_contact = true,
        delay_from_prev = 4,
    },
})
assert(#inherited_contact.sequence == 2
        and inherited_contact.inline_removed_count == 1
        and inherited_contact.sequence[1].id == 615
        and inherited_contact.sequence[2].id == 500,
    "an inherited combo snapshot must not make a fast 66 look independently contacting")

local independent_contact = consumer.normalize_sequence({
    {
        id = 615,
        motion = "HK",
        expected_combo = 5,
        damage_at_step = 2400,
        has_hit = true,
        delay_from_prev = 0,
    },
    {
        id = 17,
        motion = "66",
        expected_combo = 6,
        damage_at_step = 2687,
        has_hit = true,
        has_contact = true,
        delay_from_prev = 53,
    },
    { id = 500, motion = "drive rush", delay_from_prev = 4 },
})
assert(#independent_contact.sequence == 3
        and independent_contact.inline_removed_count == 0,
    "a precursor with a new outcome delta must remain a real recorded step")

local drc_source = {
    { id = 606, motion = "HP", delay_from_prev = 0 },
    { id = 480, motion = "PARRY", delay_from_prev = 12 },
    { id = 740, motion = "DRC", delay_from_prev = 2 },
}
local drc_normalized = consumer.normalize_sequence(drc_source)
assert(#drc_normalized.sequence == 3
        and drc_normalized.inline_removed_count == 0,
    "DRC must retain a preceding independent Parry step")

local expected = normalized.sequence[1]
for _, precursor in ipairs({
    { actual_action_id = 38, actual_motion = "7" },
    {
        actual_action_id = 12345,
        input_anchor_kind = "double_tap",
        input_anchor_motion = "44",
    },
}) do
    precursor.sequence = normalized.sequence
    precursor.current_step = 1
    precursor.expected_step = expected
    precursor.expected_action_matches_current = false
    precursor.input_truth_mode = true
    assert_ignored(precursor,
        "a normalized attempt may use any allowed leading precursor order")
end

assert_strict({
    sequence = normalized.sequence,
    current_step = 1,
    expected_step = expected,
    expected_action_matches_current = false,
    actual_action_id = 630,
    actual_motion = "2HP",
    input_anchor_kind = "button_press",
    input_truth_mode = true,
}, "a wrong first semantic Action must remain a failure candidate")
assert(consumer.attempt_start_wrong_timed_out(100, 160) == false
        and consumer.attempt_start_wrong_timed_out(100, 161) == true,
    "a wrong first semantic Action must fail after a bounded wait")

assert_strict({
    sequence = normalized.sequence,
    current_step = 2,
    previous_step = normalized.sequence[1],
    expected_step = normalized.sequence[2],
    expected_action_matches_current = false,
    actual_action_id = 17,
    actual_motion = "66",
    input_anchor_kind = "double_tap",
    input_anchor_motion = "66",
    input_truth_mode = true,
}, "a mid-combo dash must not use the attempt-start precursor rule")

local mid_raw_dr_expected = { id = 500, motion = "drive rush" }
for _, precursor in ipairs({
    {
        actual_action_id = 17,
        actual_motion = "66",
        successor_action_id = 500,
        successor_visibility_frames = 5,
    },
    {
        actual_action_id = 480,
        actual_motion = "PARRY",
        successor_action_id = 500,
        successor_visibility_frames = 12,
    },
}) do
    precursor.current_step = 5
    precursor.expected_step = mid_raw_dr_expected
    precursor.expected_action_matches_current = false
    precursor.input_truth_mode = true
    local result = consumer.classify_runtime_transition(precursor)
    assert(result.ignored == true
            and result.reason == "raw_drive_rush_precursor",
        "only a bounded final 66/Parry RAW DR precursor may be hidden")
end

for _, standalone in ipairs({
    {
        actual_action_id = 17,
        actual_motion = "66",
        successor_action_id = 500,
        successor_visibility_frames = 6,
    },
    {
        actual_action_id = 480,
        actual_motion = "PARRY",
        successor_action_id = 500,
        successor_visibility_frames = 13,
    },
    {
        actual_action_id = 17,
        actual_motion = "66",
    },
}) do
    standalone.current_step = 5
    standalone.expected_step = mid_raw_dr_expected
    standalone.expected_action_matches_current = false
    standalone.input_truth_mode = true
    local result = consumer.classify_runtime_transition(standalone)
    assert(result.reason ~= "raw_drive_rush_precursor",
        "a real or unproven 66/Parry must not be swallowed by RAW DR projection")
end

assert_strict({
    current_step = 5,
    expected_step = { id = 740, motion = "DRC" },
    expected_action_matches_current = false,
    actual_action_id = 480,
    actual_motion = "PARRY",
    input_anchor_kind = "button_press",
    input_truth_mode = true,
}, "DRC must not inherit the RAW DR precursor policy")

assert_strict({
    sequence = normalized.sequence,
    current_step = 3,
    previous_step = normalized.sequence[2],
    expected_step = normalized.sequence[3],
    expected_action_matches_current = true,
    actual_action_id = 18,
    actual_motion = "44",
    input_anchor_kind = "double_tap",
    input_anchor_motion = "44",
    input_truth_mode = true,
}, "a recorded mid-combo dash must remain directly matchable")

local manual = consumer.classify_runtime_transition({
    sequence = normalized.sequence,
    current_step = 1,
    expected_step = expected,
    expected_action_matches_current = false,
    actual_action_id = 480,
    actual_motion = "PARRY",
    demo_playback = false,
})
local demo = consumer.classify_runtime_transition({
    sequence = normalized.sequence,
    current_step = 1,
    expected_step = expected,
    expected_action_matches_current = false,
    actual_action_id = 480,
    actual_motion = "PARRY",
    demo_playback = true,
})
assert(manual.ignored == demo.ignored and manual.reason == demo.reason,
    "manual training and automatic replay must share the prefix policy")

local matcher = require("func/ComboTrials/ActionMatcher")
assert(matcher.is_quick_drive_parry_precursor({
    precursor_action_id = 480,
    successor_action_id = 500,
    elapsed_frames = 4,
}) == true,
    "the Recorder and live buffer must share the four-frame Parry-to-RAW-DR rule")
assert(matcher.is_quick_drive_parry_precursor({
    precursor_action_id = 480,
    successor_motion = "RAW_DR",
    elapsed_frames = 4,
}) == true,
    "historical RAW_DR spelling must use the same shared precursor rule")
assert(matcher.is_quick_drive_parry_precursor({
    precursor_action_id = 480,
    successor_action_id = 500,
    elapsed_frames = 5,
}) == false,
    "a held standalone Parry must remain strict outside the shared window")
assert(matcher.is_quick_drive_parry_precursor({
    precursor_action_id = 480,
    successor_action_id = 740,
    successor_motion = "DRC",
    elapsed_frames = 2,
}) == false,
    "Drive Rush Cancel must not consume a neutral-Parry precursor")
assert(matcher.is_quick_drive_parry_precursor({
    precursor_action_id = 480,
    precursor_has_contact = true,
    successor_action_id = 500,
    elapsed_frames = 2,
}) == false,
    "a contacting or explicitly independent Parry must remain a real command")
assert(matcher.should_promote_quick_drive_parry({
    precursor_action_id = 480,
    successor_action_id = 500,
    elapsed_frames = 4,
    expected_step = { id = 500, motion = "drive rush" },
}) == true,
    "the live buffer must promote the captured LastFail 480-to-500 RAW DR chain")
assert(matcher.should_promote_quick_drive_parry({
    precursor_action_id = 480,
    successor_action_id = 740,
    elapsed_frames = 2,
    expected_step = { id = 740, motion = "DRC" },
}) == false,
    "the same Action family must remain strict when the expected command is DRC")
assert(matcher.should_defer_raw_drive_rush_precursor({
    expected_step = mid_raw_dr_expected,
    actual_action_id = 17,
    actual_motion = "66",
    elapsed_frames = 5,
}) == true
        and matcher.should_defer_raw_drive_rush_precursor({
            expected_step = mid_raw_dr_expected,
            actual_action_id = 17,
            actual_motion = "66",
            elapsed_frames = 6,
        }) == false,
    "live validation must wait only through the bounded 66-to-RAW-DR window")
assert(matcher.should_defer_raw_drive_rush_precursor({
    expected_step = mid_raw_dr_expected,
    actual_action_id = 480,
    actual_motion = "PARRY",
    elapsed_frames = 12,
}) == true
        and matcher.should_defer_raw_drive_rush_precursor({
            expected_step = mid_raw_dr_expected,
            actual_action_id = 480,
            actual_motion = "PARRY",
            elapsed_frames = 13,
        }) == false,
    "live validation must wait only through the bounded Parry-to-RAW-DR window")

local main = assert(io.open("autorun/TrainingComboTrials_v1.0.lua", "rb")):read("*a")
assert(main:find("raw_drive_rush_precursor", 1, true)
        and main:find("should_defer_raw_drive_rush_precursor", 1, true)
        and not main:find("promote_quick_drive_parry", 1, true),
    "display and validation must consume the shared RAW DR precursor projection")

print("Combo leading prefix tests passed")
