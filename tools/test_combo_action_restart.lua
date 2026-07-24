local detector = dofile("autorun/func/ComboTrials/ActionRestartDetector.lua")

assert(detector.normalize_input_direction_bits(4, true) == 4,
    "P1-side physical right must remain relative forward")
assert(detector.normalize_input_direction_bits(8, false) == 4,
    "P2-side physical left must normalize to the same relative forward bit")
assert(detector.normalize_input_direction_bits(8, true) == 8,
    "P1-side physical left must remain relative back")
assert(detector.normalize_input_direction_bits(4, false) == 8,
    "P2-side physical right must normalize to the same relative back bit")

local started, reason = detector.detect(17, 3, 17, 18)
assert(started == true and reason == "repeatable_common_action_rewind",
    "a repeated 66 must create a new action instance even when frame 0/1 was not sampled")

started, reason = detector.detect(18, 4.5, 18, 21)
assert(started == true and reason == "repeatable_common_action_rewind",
    "a repeated 44 must create a new action instance even when frame 0/1 was not sampled")

started, reason = detector.detect(17, 19, 17, 18)
assert(started == false and reason == "no_new_action",
    "a normally advancing dash must not be duplicated")

started, reason = detector.detect(900, 3, 900, 18)
assert(started == false and reason == "no_new_action",
    "an unrelated same-ID frame adjustment above frame 1 must retain the conservative rule")

started, reason = detector.detect(900, 3, 900, 18, nil, nil, 32)
assert(started == true and reason == "input_confirmed_act_frame_rewind",
    "a same-ID ActionFrame rewind with a physical attack edge must create a new action instance")

started, reason = detector.detect(900, 19, 900, 18, nil, nil, 32)
assert(started == false and reason == "no_new_action",
    "an attack edge without sequence evidence must not duplicate an advancing action")

local repeat_eval = detector.evaluate_expected_repeat_input({
    expected_id = 904,
    previous_id = 904,
    current_id = 904,
    buffered_id = 904,
    current_combo = 4,
    previous_expected_combo = 4,
    frames_since_previous = 48,
    expected_delay = 48,
    action_button_edge = 32 | 64
})
assert(repeat_eval.accepted == true and repeat_eval.reason == "expected_repeat_input_ready",
    "a gated physical edge must admit the next explicitly expected same-ID action")

started, reason = detector.detect(904, 61, 904, 60, nil, nil, 32 | 64, repeat_eval.accepted)
assert(started == true and reason == "expected_repeat_action_input",
    "an expected same-ID command must create a new instance even when ActionFrame keeps advancing")

repeat_eval = detector.evaluate_expected_repeat_input({
    expected_id = 904,
    previous_id = 904,
    current_id = 904,
    buffered_id = 904,
    current_combo = 1,
    previous_expected_combo = 4,
    frames_since_previous = 48,
    expected_delay = 48,
    action_button_edge = 32 | 64
})
assert(repeat_eval.accepted == true and repeat_eval.reason == "expected_repeat_input_ready",
    "a timed projectile repeat must not wait for every hit from the previous command")

repeat_eval = detector.evaluate_expected_repeat_input({
    expected_id = 904,
    previous_id = 904,
    current_id = 904,
    buffered_id = 904,
    current_combo = 4,
    previous_expected_combo = 4,
    frames_since_previous = 9,
    expected_delay = 48,
    action_button_edge = 32 | 64
})
assert(repeat_eval.accepted == false and repeat_eval.reason == "before_expected_repeat_window",
    "an early repeated edge inside the first command buffer must not create the next trial step")

started, reason = detector.detect(900, 3, 900, 18, nil, nil, 4)
assert(started == false and reason == "no_new_action",
    "a direction-only edge must not confirm a same-ID attack restart")

started, reason = detector.detect(900, 1, 900, 18)
assert(started == true and reason == "act_frame_rewind",
    "the existing near-zero same-ID restart behavior must remain intact")

started, reason = detector.detect(18, 20, 17, 20)
assert(started == true and reason == "id_changed",
    "an Action ID transition must remain a new action")

assert(detector.get_repeatable_motion(17) == "66", "Action 17 must stay data-mapped to 66")
assert(detector.get_repeatable_motion(18) == "44", "Action 18 must stay data-mapped to 44")
assert(detector.get_repeatable_motion(900) == nil, "character actions must not be hardcoded")

local function collect_pairs(directions)
    local state = {}
    local pairs = {}
    for index, direction in ipairs(directions) do
        local pair = detector.observe_dash_direction_edge(state, direction, index * 3)
        if pair then table.insert(pairs, pair) end
    end
    return pairs, state
end

local pairs = collect_pairs({ "6", "6", "6", "6" })
assert(#pairs == 2, "6666 must produce two non-overlapping 66 commands")

pairs = collect_pairs({ "6", "6", "6", "6", "6", "6" })
assert(#pairs == 3, "666666 must produce three non-overlapping 66 commands")
pairs = collect_pairs({ "6", "6", "6", "6", "6" })
assert(#pairs == 2, "an odd rapid 66666 stream must keep two full 66 commands and one pending tap")

pairs = collect_pairs({ "4", "4", "6", "6", "4", "4", "6", "6" })
assert(#pairs == 4, "44664466 must preserve all four commands")

local stale_state = {}
assert(detector.observe_dash_direction_edge(stale_state, "6", 1) == nil)
assert(detector.observe_dash_direction_edge(stale_state, "6", 20) == nil,
    "two stale taps must not create a dash command")

local function press_pair(state, direction, first_frame)
    assert(detector.observe_dash_direction_edge(state, direction, first_frame) == nil)
    return assert(detector.observe_dash_direction_edge(state, direction, first_frame + 2))
end

local p1_state = {}
local first_66 = press_pair(p1_state, "6", 10)
started, reason = detector.detect(17, 1, 1, 20, p1_state, 12)
assert(started == true and reason == "id_changed",
    "the first P1-side 66 must bind raw 6 to the actual Action 17 transition")
local second_66 = press_pair(p1_state, "6", 16)
started, reason = detector.detect(17, 30, 17, 29, p1_state, 18)
assert(started == true and reason == "repeatable_common_action_input",
    "the next P1-side 66 must restart Action 17 while its frame keeps advancing")

local p2_state = {}
local first_44 = press_pair(p2_state, "4", 30)
started, reason = detector.detect(17, 1, 1, 20, p2_state, 32)
assert(started == true and reason == "id_changed",
    "the first P2-side forward dash must bind raw 4 to actual Action 17")
local second_44 = press_pair(p2_state, "4", 36)
started, reason = detector.detect(17, 40, 17, 39, p2_state, 38)
assert(started == true and reason == "repeatable_common_action_input",
    "the next P2-side raw 44 must use the learned Action 17 binding")

local p2_back = press_pair(p2_state, "6", 42)
started, reason = detector.detect(17, 45, 17, 44, p2_state, 44)
assert(started == false and reason == "no_new_action",
    "P2-side raw 66 must not reuse the forward-dash binding")
started, reason = detector.detect(18, 1, 17, 45, p2_state, 45)
assert(started == true and reason == "id_changed",
    "the real P2-side Action 18 transition must bind raw 6 as back dash")
local repeated_p2_back = press_pair(p2_state, "6", 48)
started, reason = detector.detect(18, 50, 18, 49, p2_state, 50)
assert(started == true and reason == "repeatable_common_action_input",
    "P2-side repeated back dash must work with the learned raw 6 binding")

local opposite_pair = press_pair(p1_state, "4", 22)
started, reason = detector.detect(17, 45, 17, 44, p1_state, 24)
assert(started == false and reason == "no_new_action",
    "an opposite pair must wait for the real Action ID instead of duplicating the old dash")
started, reason = detector.detect(18, 1, 17, 45, p1_state, 25)
assert(started == true and reason == "id_changed",
    "the following Action 18 transition must bind the pending opposite pair")
local repeated_44 = press_pair(p1_state, "4", 28)
started, reason = detector.detect(18, 50, 18, 49, p1_state, 30)
assert(started == true and reason == "repeatable_common_action_input",
    "the learned back-dash direction must repeat without a coordinate lookup")

local queued_state = {}
local queued_first = press_pair(queued_state, "6", 60)
local queued_second = press_pair(queued_state, "6", 64)
started, reason = detector.detect(17, 1, 1, 20, queued_state, 66)
assert(started == true and reason == "id_changed",
    "the first actual Action 17 transition must consume only the first queued 66")
assert(#queued_state.completed_pairs == 1 and queued_state.completed_pairs[1] == queued_second,
    "a second ultra-fast 66 completed before the ID transition must remain queued")
started, reason = detector.detect(17, 3, 17, 2, queued_state, 67)
assert(started == true and reason == "repeatable_common_action_input",
    "the queued ultra-fast second 66 must create its own action instance")
assert(#queued_state.completed_pairs == 0,
    "all confirmed ultra-fast dash pairs must be consumed exactly once")

print("combo action restart tests passed")
