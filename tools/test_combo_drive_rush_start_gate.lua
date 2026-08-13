package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local consumer = require("func/ComboTrials/UnifiedActionConsumer")

local function classify(params)
    return consumer.classify_runtime_transition(params)
end

local function base(params)
    params = params or {}
    params.expected_action_matches_current =
        params.expected_action_matches_current ~= false
        and params.expected_action_matches_current ~= nil
    params.input_truth_mode = params.input_truth_mode ~= false
    params.input_anchor_kind = params.input_anchor_kind or "double_tap"
    params.action_event_rules = params.action_event_rules or {}
    params.sequence = params.sequence or {
        { id = 17, motion = "66" },
        { id = 740, motion = "RAWDR", delay_from_prev = 5 },
    }
    params.current_step = params.current_step or 1
    params.expected_step = params.expected_step or params.sequence[params.current_step]
    return params
end

local function assert_ignored(params, message)
    local result = classify(base(params))
    assert(result.ignored == true, string.format(
        "%s (expected ignored=true actual=%s reason=%s)",
        message,
        tostring(result.ignored),
        tostring(result.reason)
    ))
end

local function assert_skip(params, expected_step, message)
    local result = classify(base(params))
    assert(result.ignored ~= true, string.format(
        "%s must not be ignored (reason=%s)",
        message,
        tostring(result.reason)
    ))
    assert(result.skip_to_step == expected_step, string.format(
        "%s (expected skip_to_step=%s actual=%s reason=%s)",
        message,
        tostring(expected_step),
        tostring(result.skip_to_step),
        tostring(result.reason)
    ))
    assert(result.attempt_start_timing_baseline == true,
        message .. " must establish the first semantic timing baseline")
end

local function assert_not_gated(params, message)
    local result = classify(base(params))
    assert(result.skip_to_step == nil, string.format(
        "%s must not skip precursor steps (actual=%s reason=%s)",
        message,
        tostring(result.skip_to_step),
        tostring(result.reason)
    ))
    assert(result.reason ~= "drive_rush_attempt_start_precursor", string.format(
        "%s must not use the drive-rush start gate",
        message
    ))
end

local dash_then_dr = {
    { id = 17, motion = "66" },
    { id = 740, motion = "RAWDR", delay_from_prev = 5 },
}

assert_ignored({
    sequence = dash_then_dr,
    current_step = 1,
    actual_action_id = 480,
}, "parry before a recorded leading 66 must be a start precursor")

assert_ignored({
    sequence = dash_then_dr,
    current_step = 1,
    actual_action_id = 17,
    actual_motion = "66",
}, "the recorded leading 66 itself must not arm step-1 failure")

assert_skip({
    sequence = dash_then_dr,
    current_step = 1,
    actual_action_id = 740,
}, 2, "a semantic Drive Rush must consume a recorded leading 66")

assert_ignored({
    sequence = dash_then_dr,
    current_step = 2,
    actual_action_id = 17,
    actual_motion = "66",
}, "a different leading 66 must wait while the semantic Drive Rush is expected")

assert_skip({
    sequence = {
        { id = 480, motion = "PARRY" },
        { id = 740, motion = "RAWDR", delay_from_prev = 10 },
    },
    current_step = 1,
    actual_action_id = 740,
}, 2, "a semantic Drive Rush must consume a recorded leading parry")

assert_skip({
    sequence = {
        { id = 17, motion = "66" },
        { id = 480, motion = "PARRY", delay_from_prev = 2 },
        { id = 740, motion = "RAWDR", delay_from_prev = 8 },
    },
    current_step = 1,
    actual_action_id = 740,
}, 3, "a semantic Drive Rush must consume a recorded dash+parry prefix")

assert_ignored({
    sequence = {
        { id = 17, motion = "66" },
        { id = 480, motion = "PARRY", delay_from_prev = 2 },
        { id = 740, motion = "RAWDR", delay_from_prev = 8 },
    },
    current_step = 2,
    actual_action_id = 480,
}, "a second precursor step must also wait for the semantic Drive Rush")

local wrong_candidate = classify(base({
    sequence = dash_then_dr,
    current_step = 1,
    actual_action_id = 900,
    actual_motion = "5MP",
}))
assert(wrong_candidate.ignored == false
        and wrong_candidate.skip_to_step == nil
        and wrong_candidate.reason == "drive_rush_attempt_start_wrong_candidate",
    "a wrong attack at the first semantic checkpoint must remain a hard failure candidate")

assert_not_gated({
    sequence = {
        { id = 37, motion = "9" },
        { id = 740, motion = "RAWDR" },
    },
    current_step = 1,
    actual_action_id = 17,
    actual_motion = "66",
}, "a jump before a Drive Rush must not be globally ignored")

assert_not_gated({
    sequence = {
        { id = 17, motion = "66" },
    },
    current_step = 1,
    actual_action_id = 18,
    actual_motion = "44",
}, "a plain dash step without a following Drive Rush must remain strict")

assert_not_gated({
    sequence = {
        { id = 18, motion = "44" },
        { id = 740, motion = "RAWDR", delay_from_prev = 5 },
    },
    current_step = 1,
    actual_action_id = 18,
    actual_motion = "44",
    input_anchor_kind = "double_tap",
    input_anchor_motion = "44",
}, "backward movement before a Drive Rush must remain a meaningful checkpoint")

assert_not_gated({
    sequence = {
        { id = 17, motion = "66" },
        {
            id = 740,
            motion = "RAWDR",
            delay_from_prev = consumer.PLAYER_ACTION_BIND_WINDOW + 1,
        },
    },
    current_step = 1,
    actual_action_id = 17,
    actual_motion = "66",
}, "a long independent forward dash before Drive Rush must remain strict")

assert_not_gated({
    sequence = {
        { id = 17, motion = "66" },
        { id = 740, motion = "RAWDR" },
    },
    current_step = 1,
    actual_action_id = 17,
    actual_motion = "66",
}, "a prefix without recorded adjacency evidence must remain strict")

assert_ignored({
    sequence = dash_then_dr,
    current_step = 1,
    actual_action_id = 12345,
    actual_motion = nil,
    input_anchor_kind = "double_tap",
    input_anchor_motion = "66",
}, "a dash precursor is classified by semantic input evidence, not an Action ID")

assert_not_gated({
    sequence = {
        { id = 740, motion = "RAWDR" },
        { id = 740, motion = "RAWDR" },
    },
    current_step = 2,
    actual_action_id = 480,
}, "a mid-combo parry after the first Drive Rush must not be absorbed by the start gate")

local direct_match = classify(base({
    sequence = dash_then_dr,
    current_step = 2,
    expected_step = dash_then_dr[2],
    expected_action_matches_current = true,
    actual_action_id = 740,
}))
assert(direct_match.ignored == false
        and direct_match.skip_to_step == nil
        and direct_match.reason == "expected_action",
    "an exact Drive Rush match after skipping precursors must stay on the normal path")

local manual_start = classify(base({
    sequence = dash_then_dr,
    current_step = 1,
    actual_action_id = 740,
    demo_playback = false,
}))
local demo_start = classify(base({
    sequence = dash_then_dr,
    current_step = 1,
    actual_action_id = 740,
    demo_playback = true,
}))
assert(manual_start.skip_to_step == demo_start.skip_to_step
        and manual_start.attempt_start_timing_baseline
            == demo_start.attempt_start_timing_baseline
        and manual_start.reason == demo_start.reason,
    "manual training and automatic replay must share the checkpoint policy")

print("Combo drive rush start gate tests passed")
