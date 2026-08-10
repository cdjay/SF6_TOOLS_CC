package.path = table.concat({
    "./autorun/?.lua",
    "./autorun/?/init.lua",
    package.path,
}, ";")

local AtomicTrace = require("func/ComboTrials/Raw/AtomicTrace")
local AtomicCapture = require("func/ComboTrials/Raw/AtomicCapture")

local function equal(actual, expected, message)
    assert(actual == expected, (message or "values differ")
        .. ": expected=" .. tostring(expected) .. " actual=" .. tostring(actual))
end

local trace = AtomicTrace.new()
local capture = assert(AtomicCapture.new(trace))

equal(capture:observe({ action_id = 600, engine_frame = 10, action_frame = 0 }).new_instance, true)
equal(capture:observe({ action_id = 600, engine_frame = 11, action_frame = 1 }).new_instance, false)
equal(capture:observe({ action_id = 601, engine_frame = 12, action_frame = 0 }).new_instance, true)
equal(capture:observe({ action_id = 601, engine_frame = 13, action_frame = 4 }).new_instance, false)
equal(capture:observe({ action_id = 601, engine_frame = 14, action_frame = 3,
    restart = true }).new_instance, true)
equal(capture:observe({ action_id = 601, engine_frame = 15, action_frame = 1,
    restart = true }).new_instance, true)
equal(capture:observe({ action_id = 600, engine_frame = 16, action_frame = -2 }).new_instance, true)

capture:finish()
local instances = trace:get_instances()
equal(#instances, 5, "action changes and explicit same-ID restarts create instances")
equal(instances[1].action_id, 600)
equal(instances[1].occurrence, 1)
equal(instances[1].enter_frame, 10)
equal(instances[1].exit_frame, 11)
equal(instances[1].action_frame_start, 0)
equal(instances[1].action_frame_end, 1)
equal(instances[2].action_id, 601)
equal(instances[2].occurrence, 1)
equal(instances[2].exit_frame, 13)
equal(instances[3].action_id, 601)
equal(instances[3].occurrence, 2)
equal(instances[3].enter_frame, 14)
equal(instances[3].exit_frame, 14)
equal(instances[3].action_frame_start, 3)
equal(instances[3].action_frame_end, 3)
equal(instances[4].action_id, 601)
equal(instances[4].occurrence, 3)
equal(instances[4].enter_frame, 15)
equal(instances[4].exit_frame, 15)
equal(instances[4].action_frame_start, 1)
equal(instances[4].action_frame_end, 1)
equal(instances[5].action_id, 600)
equal(instances[5].occurrence, 2)
equal(instances[5].enter_frame, 16)
equal(instances[5].exit_frame, 16)
equal(instances[5].action_frame_start, -2)

-- A rewind alone stays in the same instance. RawActionBoundary must provide
-- explicit factual restart evidence before AtomicCapture splits the Action.
local rewind_trace = AtomicTrace.new()
local rewind_capture = assert(AtomicCapture.new(rewind_trace))
assert(rewind_capture:observe({ action_id = 700, engine_frame = 100, action_frame = 12 }))
assert(rewind_capture:observe({ action_id = 700, engine_frame = 101, action_frame = 11 }))
assert(rewind_capture:observe({ action_id = 700, engine_frame = 102, action_frame = 8, restart = true }))
assert(rewind_capture:observe({ action_id = 700, engine_frame = 103, action_frame = 7 }))
rewind_capture:finish()
local rewind_instances = rewind_trace:get_instances()
equal(#rewind_instances, 2, "unconfirmed rewinds do not create instances")
equal(rewind_instances[1].action_frame_start, 12)
equal(rewind_instances[1].action_frame_end, 11)
equal(rewind_instances[2].action_frame_start, 8)
equal(rewind_instances[2].action_frame_end, 7)

-- Explicit start gate: idle/setup samples before the controller's factual
-- activity signal are not admitted into the AtomicTrace.
local gated_trace = AtomicTrace.new()
local gated = assert(AtomicCapture.new(gated_trace, { start_gate = "explicit" }))
local idle = gated:observe({ action_id = 1, engine_frame = 5, action_frame = 0 })
equal(idle.new_instance, false)
equal(idle.started, false)
equal(gated:is_started(), false)
equal(gated_trace:count(), 0)
local started = gated:observe({ action_id = 1, engine_frame = 20, action_frame = 1, active = true })
equal(started.new_instance, false)
equal(started.started, true)
equal(started.armed, true)
equal(gated:is_started(), true)
assert(gated:observe({ action_id = 600, engine_frame = 21, action_frame = 0 }))
assert(gated:observe({ action_id = 601, engine_frame = 22, action_frame = 0 }))
gated:finish()
local gated_instances = gated_trace:get_instances()
equal(#gated_instances, 2)
equal(gated_instances[1].action_id, 600)
equal(gated_instances[1].enter_frame, 21)
equal(gated_instances[2].action_id, 601)
equal(gated_instances[2].enter_frame, 22)

-- If the physical input edge and Action transition share a frame, that factual
-- transition is admitted as the first instance.
local edge_trace = AtomicTrace.new()
local edge_capture = assert(AtomicCapture.new(edge_trace, {
    start_gate = "explicit",
    initial_action_id = 1,
    initial_action_frame = 5,
}))
assert(edge_capture:observe({ action_id = 600, engine_frame = 31, action_frame = 0, active = true }))
assert(edge_capture:observe({ action_id = 600, engine_frame = 32, action_frame = 1 }))
assert(edge_capture:observe({ action_id = 601, engine_frame = 33, action_frame = 0 }))
edge_capture:finish()
local edge_instances = edge_trace:get_instances()
equal(#edge_instances, 2)
equal(edge_instances[1].action_id, 600)
equal(edge_instances[1].enter_frame, 31)
equal(edge_instances[2].action_id, 601)
equal(edge_instances[2].enter_frame, 33)

-- A same-ID Runtime restart produces a second occurrence without any input
-- evidence. The baseline Action itself is not emitted as a new occurrence.
local repeat_trace = AtomicTrace.new()
local repeat_capture = assert(AtomicCapture.new(repeat_trace, {
    start_gate = "explicit",
    initial_action_id = 600,
    initial_action_frame = 8,
}))
assert(repeat_capture:observe({ action_id = 600, engine_frame = 40,
    action_frame = 0, active = true, restart = true }))
assert(repeat_capture:observe({ action_id = 600, engine_frame = 41,
    action_frame = 1 }))
assert(repeat_capture:observe({ action_id = 600, engine_frame = 42,
    action_frame = 0, active = true, restart = true }))
repeat_capture:finish()
local repeat_instances = repeat_trace:get_instances()
equal(#repeat_instances, 2)
equal(repeat_instances[1].occurrence, 1)
equal(repeat_instances[2].occurrence, 2)

-- Unknown gate modes and immutable traces fail closed.
local bad_gate, bad_gate_err = AtomicCapture.new(AtomicTrace.new(), { start_gate = "guess" })
equal(bad_gate, nil)
equal(bad_gate_err, "invalid_start_gate")
local sealed_trace = AtomicTrace.new()
sealed_trace:finalize()
local sealed, sealed_err = AtomicCapture.new(sealed_trace)
equal(sealed, nil)
equal(sealed_err, "mutable_trace_required")

local invalid_trace = AtomicTrace.new()
local invalid_capture = assert(AtomicCapture.new(invalid_trace))
local observed, err = invalid_capture:observe({ action_id = 1, engine_frame = 2, action_frame = 0 })
assert(observed and not err)
observed, err = invalid_capture:observe({ action_id = 1, engine_frame = 1, action_frame = 1 })
equal(observed, nil)
equal(err, "engine_frame_rewind")

print("atomic capture tests passed")
