package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local AtomicTrace = require("func/ComboTrials/Raw/AtomicTrace")
local AtomicDetector = require("func/ComboTrials/Raw/AtomicDetector")

local function trace_of(ids)
    local trace = AtomicTrace.new()
    for _, id in ipairs(ids) do
        trace:append(id)
    end
    trace:finalize()
    return trace
end

local function expect_exact(expected, actual)
    local match, report = AtomicDetector.compare(expected, actual)
    assert(match == true, "exact atomic sequence must match")
    assert(report.match == true and report.first_divergence == nil)
    assert(report.expected_count == #report.expected_sequence
        and report.actual_count == #report.actual_sequence)
end

local function expect_divergence(expected, actual, step, reason)
    local match, report = AtomicDetector.compare(expected, actual)
    assert(match == false, "divergent atomic sequence must not match")
    local divergence = report.first_divergence
    assert(divergence ~= nil and divergence.step == step
        and divergence.reason == reason,
        "expected divergence " .. reason .. " at step " .. step)
end

expect_exact(trace_of({ 600, 601, 600, 602 }), trace_of({ 600, 601, 600, 602 }))
expect_exact(trace_of({}), trace_of({}))

-- Replay order is strict; duplicate Action IDs are order-sensitive.
expect_divergence(trace_of({ 600, 601, 600 }),
    trace_of({ 600, 600, 601 }), 2, "action_mismatch")
expect_divergence(trace_of({ 600, 601, 602 }),
    trace_of({ 600, 603, 602 }), 2, "action_mismatch")
expect_divergence(trace_of({ 600, 601, 602 }),
    trace_of({ 600, 601 }), 3, "missing_expected")
expect_divergence(trace_of({ 600, 601 }),
    trace_of({ 600, 601, 602 }), 3, "unexpected_extra")

-- Frame context is preserved in diagnostics but never decides the match.
local expected_frames = AtomicTrace.new()
expected_frames:append({ action_id = 600, enter_frame = 10, exit_frame = 40 })
expected_frames:append({ action_id = 601, enter_frame = 50, exit_frame = 70 })
expected_frames:finalize()
local actual_frames = AtomicTrace.new()
actual_frames:append({ action_id = 600, enter_frame = 99, exit_frame = 120 })
actual_frames:append({ action_id = 601, enter_frame = 130, exit_frame = 150 })
actual_frames:finalize()
expect_exact(expected_frames, actual_frames)

local actual_with_third = AtomicTrace.new()
actual_with_third:append({ action_id = 600, enter_frame = 99, exit_frame = 120 })
actual_with_third:append({ action_id = 601, enter_frame = 130, exit_frame = 150 })
actual_with_third:append({ action_id = 602, enter_frame = 160, exit_frame = 180 })
actual_with_third:finalize()

local frame_match, frame_report = AtomicDetector.compare(expected_frames, actual_with_third)
assert(frame_match == false and frame_report.first_divergence.step == 3)
assert(frame_report.first_divergence.actual.instance.enter_frame == 160
    and frame_report.first_divergence.actual.instance.exit_frame == 180,
    "divergence diagnostics must carry frame context")

-- No semantic equality: command/display/Move/owner fields are ignored.
local semantic_a = AtomicTrace.new()
semantic_a:append({ action_id = 600, command = "623HP",
    display = "Dragon Punch", move_uid = "move_a", owner_action_id = 600 })
semantic_a:append({ action_id = 601, command = "236K",
    display = "Tatsu", move_uid = "move_b", owner_action_id = 601 })
local semantic_b = AtomicTrace.new()
semantic_b:append({ action_id = 600, command = "6HP",
    display = "Different", move_uid = "move_z", owner_action_id = 999 })
semantic_b:append({ action_id = 601, command = "22P",
    display = "Also Different", move_uid = "move_y", owner_action_id = 998 })
expect_exact(semantic_a, semantic_b)

-- Payload inputs use the same strict comparison.
local payload_a = trace_of({ 600, 601 }):to_payload()
local restored_payload = AtomicTrace.from_payload(payload_a)
local payload_b = restored_payload:to_payload()
expect_exact(payload_a, payload_b)

-- Invalid inputs fail closed instead of matching on partial data.
local bad_expected, bad_expected_report =
    AtomicDetector.compare({ { action_id = "x" } }, trace_of({ 600 }))
assert(bad_expected == nil and bad_expected_report.error == "invalid_expected")
local bad_actual, bad_actual_report =
    AtomicDetector.compare(trace_of({ 600 }), {})
assert(bad_actual == nil and bad_actual_report.error == "invalid_actual")

print("atomic detector tests passed")
