package.path = table.concat({
    "./autorun/?.lua",
    "./autorun/?/init.lua",
    package.path,
}, ";")

local AtomicTrace = require("func/ComboTrials/Raw/AtomicTrace")
local Stage1Runtime = require("func/ComboTrials/Raw/Stage1Runtime")

local function equal(actual, expected, message)
    assert(actual == expected, (message or "values differ")
        .. ": expected=" .. tostring(expected) .. " actual=" .. tostring(actual))
end

local runtime = Stage1Runtime.new()
assert(runtime:begin_recording("Zangief", {
    fighter_id = 20,
    game_build = "sf6b_current",
    control_mode = "classic",
    recorded_at = "2026-08-09T00:00:00Z",
}))
assert(runtime:observe_recording({ action_id = 600, engine_frame = 1, action_frame = 0 }))
assert(runtime:observe_recording({ action_id = 601, engine_frame = 2, action_frame = 0 }))
assert(runtime:observe_recording({ action_id = 600, engine_frame = 3, action_frame = 0 }))
assert(runtime:finish_recording())

local meta = {}
assert(runtime:attach_last_recording(meta, {
    raw_input_ref = { source = "v2", field = "relative_raw_inputs" },
    timeline_ref = { source = "v2", field = "timeline" },
}))
assert(type(meta.raw_stage1) == "table")

local loaded, status = runtime:load_meta(meta)
assert(loaded)
equal(status, "loaded")
equal(loaded:trace():count(), 3)

assert(runtime:begin_attempt())
local result = assert(runtime:observe_attempt({ action_id = 600, engine_frame = 10, action_frame = 0 }))
equal(result.status, "progress")
result = assert(runtime:observe_attempt({ action_id = 601, engine_frame = 11, action_frame = 0 }))
equal(result.status, "progress")
result = assert(runtime:observe_attempt({ action_id = 600, engine_frame = 12, action_frame = 0 }))
equal(result.status, "passed")
equal(result.match, true)
result = assert(runtime:observe_attempt({ action_id = 999, engine_frame = 13, action_frame = 0 }))
equal(result.status, "passed", "a terminal success remains frozen")
equal(runtime:attempt_trace():count(), 3, "post-success actions are not appended")

assert(runtime:begin_attempt())
assert(runtime:observe_attempt({ action_id = 600, engine_frame = 20, action_frame = 0 }))
result = assert(runtime:observe_attempt({ action_id = 999, engine_frame = 21, action_frame = 0 }))
equal(result.status, "failed")
equal(result.first_divergence.step, 2)

-- Explicit finalize: a correct prefix that stops must report missing_expected.
assert(runtime:begin_attempt())
assert(runtime:observe_attempt({ action_id = 600, engine_frame = 30, action_frame = 0 }))
local finalized = assert(runtime:finalize_attempt())
equal(finalized.status, "failed")
equal(finalized.match, false)
equal(finalized.first_divergence.reason, "missing_expected")
equal(finalized.first_divergence.step, 2)
equal(finalized.first_divergence.expected.action_id, 601)
local finalized_again = assert(runtime:finalize_attempt())
equal(finalized_again.status, "failed", "terminal finalization is frozen")
equal(runtime.last_result, finalized)

-- A fully matched attempt finalizes as passed.
assert(runtime:begin_attempt())
assert(runtime:observe_attempt({ action_id = 600, engine_frame = 40, action_frame = 0 }))
assert(runtime:observe_attempt({ action_id = 601, engine_frame = 41, action_frame = 0 }))
assert(runtime:observe_attempt({ action_id = 600, engine_frame = 42, action_frame = 0 }))
local passed_finalized = assert(runtime:finalize_attempt())
equal(passed_finalized.status, "passed")
equal(passed_finalized.match, true)

-- Demo arming may observe that the expected first Action is already active.
-- Admit that exact current fact once, then keep strict order for every later
-- occurrence. A different current Action remains only the boundary baseline.
assert(runtime:begin_attempt({
    player_index = 0,
    start_engine_frame = 50,
    initial_action_id = 600,
    initial_action_frame = 4,
    admit_matching_initial = true,
}))
equal(runtime:attempt_trace():count(), 1)
equal(runtime.last_result.status, "progress")
result = assert(runtime:observe_attempt({
    player_index = 0, action_id = 601, engine_frame = 51, action_frame = 0,
}))
equal(result.status, "progress")
result = assert(runtime:observe_attempt({
    player_index = 0, action_id = 600, engine_frame = 52, action_frame = 0,
}))
equal(result.status, "passed")

assert(runtime:begin_attempt({
    player_index = 0,
    start_engine_frame = 60,
    initial_action_id = 999,
    initial_action_frame = 4,
    admit_matching_initial = true,
}))
equal(runtime:attempt_trace():count(), 0,
    "a non-matching current Action must not be admitted or skipped")
result = assert(runtime:observe_attempt({
    player_index = 0, action_id = 600, engine_frame = 61, action_frame = 0,
    active = true,
}))
equal(result.status, "progress")

-- Inactivity timeout derives from factual expected enter-frame gaps plus
-- tolerance. A stalled correct prefix times out to missing_expected.
local timed = Stage1Runtime.new()
local timed_trace = AtomicTrace.new()
timed_trace:append({ action_id = 600, enter_frame = 10 })
timed_trace:append({ action_id = 601, enter_frame = 40 })
timed_trace:append({ action_id = 602, enter_frame = 140 })
timed_trace:finalize()
local timed_meta = { raw_stage1 = { schema = "sf6cc.raw_stage1.trial.v1", version = 1,
    environment = { character = "Ryu" }, trace = timed_trace:to_payload() } }
local timed_loaded, timed_status = timed:load_meta(timed_meta)
assert(timed_loaded ~= nil and timed_status == "loaded")
assert(timed:begin_attempt())
local policy = timed:timeout_policy()
equal(policy.gap_count, 2)
equal(policy.basis, 100)
equal(policy.tolerance, 3)
equal(policy.timeout_frames, 310)
assert(timed:observe_attempt({ action_id = 600, engine_frame = 100, action_frame = 0 }))
local pending = assert(timed:attempt_inactivity_timeout(409))
equal(pending.status, "progress")
equal(pending.timed_out, false)
local timed_out = assert(timed:attempt_inactivity_timeout(410))
equal(timed_out.status, "failed")
equal(timed_out.timed_out, true)
equal(timed_out.first_divergence.reason, "missing_expected")
equal(timed_out.first_divergence.step, 2)

-- Absent raw_stage1 allows Legacy; malformed raw_stage1 fails closed and
-- never falls through to Legacy detection.
local malformed = Stage1Runtime.new()
local malformed_trial, malformed_status, malformed_code =
    malformed:load_meta({ raw_stage1 = "bad" })
equal(malformed_trial, nil)
equal(malformed_status, "invalid")
equal(malformed_code, "raw_stage1_not_object")
local malformed_attempt, malformed_attempt_status = malformed:begin_attempt()
equal(malformed_attempt, nil)
equal(malformed_attempt_status, "invalid")
local malformed_observed, malformed_observed_status = malformed:observe_attempt({
    action_id = 600, engine_frame = 1, action_frame = 0,
})
equal(malformed_observed, nil)
equal(malformed_observed_status, "invalid")
local malformed_finalize, malformed_finalize_status = malformed:finalize_attempt()
equal(malformed_finalize, nil)
equal(malformed_finalize_status, "attempt_not_active")

-- Controller query: samples are only meaningful while Stage 1 is active.
local idle_runtime = Stage1Runtime.new()
equal(idle_runtime:should_collect_sample(0), false)
equal(idle_runtime:should_collect_sample(1), false)
assert(idle_runtime:begin_recording("Ryu", { player_index = 0 }))
equal(idle_runtime:should_collect_sample(0), true)
equal(idle_runtime:should_collect_sample(1), false)
idle_runtime:cancel_recording()
local loaded_runtime = Stage1Runtime.new()
assert(loaded_runtime:load_meta({ raw_stage1 = { schema = "sf6cc.raw_stage1.trial.v1",
    version = 1, environment = { character = "Ryu" },
    trace = { schema = "sf6cc.raw_stage1.atomic_trace.v1", version = 1,
        finalized = true, instances = {
            { step = 1, occurrence = 1, action_id = 600 },
        } } } }))
equal(loaded_runtime:should_collect_sample(0), true)
equal(loaded_runtime:should_collect_sample(1), true)

local legacy = Stage1Runtime.new()
local legacy_trial, legacy_status = legacy:load_meta({ schema = 2 })
equal(legacy_trial, nil)
equal(legacy_status, "legacy")
local attempt, attempt_status = legacy:begin_attempt()
equal(attempt, nil)
equal(attempt_status, "legacy")

local empty = Stage1Runtime.new()
assert(empty:begin_recording("Ryu", {}))
local empty_trial, empty_error = empty:finish_recording()
equal(empty_trial, nil)
equal(empty_error, "empty_atomic_trace")

-- Recording start gate can be configured without changing the fact path.
local gated_runtime = Stage1Runtime.new()
assert(gated_runtime:begin_recording("Ryu", { start_gate = "explicit" }))
local gated_idle = gated_runtime:observe_recording({
    action_id = 1, engine_frame = 1, action_frame = 0,
})
equal(gated_idle.new_instance, false)
assert(gated_runtime:observe_recording({
    action_id = 600, engine_frame = 5, action_frame = 0, active = true,
}))
local gated_trial = assert(gated_runtime:finish_recording())
equal(gated_trial:trace():count(), 1)

print("stage1 runtime tests passed")
