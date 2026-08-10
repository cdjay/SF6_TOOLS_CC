package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local AtomicTrace = require("func/ComboTrials/Raw/AtomicTrace")

local function expect_invalid(status, code, expected)
    assert(status == "invalid", "expected invalid, got " .. tostring(status))
    assert(code == expected,
        "expected " .. expected .. ", got " .. tostring(code))
end

-- Duplicate action instances are preserved in order with occurrences.
local trace = AtomicTrace.new()
local first, first_step = trace:append(600)
assert(first_step == 1 and first.action_id == 600 and first.occurrence == 1)
local second = trace:append(601)
local third = trace:append(600)
local fourth = trace:append(602)
assert(trace:count() == 4)
assert(second.occurrence == 1 and third.occurrence == 2 and fourth.occurrence == 1)
local instances = trace:get_instances()
assert(#instances == 4)
assert(instances[1].action_id == 600 and instances[2].action_id == 601
    and instances[3].action_id == 600 and instances[4].action_id == 602)
assert(instances[1].step == 1 and instances[3].step == 3)

-- Query results are immutable views; writes must fail instead of corrupting.
local mutated = pcall(function() instances[3].action_id = 999 end)
assert(mutated == false, "instance views must reject writes")
local replaced = pcall(function() instances[2] = {} end)
assert(replaced == false, "instance arrays must reject writes")

-- ActionFrame may rewind; update accepts smaller later values.
local rewind, rewind_step = trace:append({
    action_id = 700,
    enter_frame = 10,
    exit_frame = 40,
    action_frame_start = 5,
    action_frame_end = 30,
})
assert(rewind_step == 5)
local updated = trace:update(rewind_step, {
    exit_frame = 20,
    action_frame_end = -1,
})
assert(updated.enter_frame == 10 and updated.exit_frame == 20
    and updated.action_frame_end == -1,
    "signed ActionFrame rewind facts must be preserved")

-- Identity fields are frozen after append; unknown steps fail closed.
local identity_update, identity_err = trace:update(1, { action_id = 999 })
assert(identity_update == nil and identity_err == "identity_field_frozen")
local missing_update, missing_err = trace:update(999, { enter_frame = 1 })
assert(missing_update == nil and missing_err == "step_not_found")

-- Invalid appends return explicit codes instead of throwing.
local empty, empty_err = trace:append({})
assert(empty == nil and empty_err == "action_id_required")
local bad_frame, bad_frame_err = trace:append({ action_id = 5, enter_frame = "x" })
assert(bad_frame == nil and bad_frame_err == "invalid_frame")

-- finalize seals append/update but keeps queries available.
local summary = trace:finalize()
assert(summary.finalized == true and summary.count == 5)
assert(trace:is_finalized() == true)
local late, late_err = trace:append(999)
assert(late == nil and late_err == "trace_finalized")
local late_update, late_update_err = trace:update(1, { enter_frame = 1 })
assert(late_update == nil and late_update_err == "trace_finalized")

-- Payload roundtrip preserves duplicates, frames and finalized state.
local payload = trace:to_payload()
assert(payload.schema == AtomicTrace.SCHEMA and payload.version == 1)
local restored, restored_status = AtomicTrace.from_payload(payload)
assert(restored ~= nil and restored_status == "loaded")
assert(restored:count() == 5 and restored:is_finalized() == true)
local original = trace:get_instances()
local restored_instances = restored:get_instances()
for index = 1, #original do
    for key, value in pairs(original[index]) do
        assert(restored_instances[index][key] == value,
            "roundtrip field mismatch at " .. tostring(key))
    end
end

-- Rewind payload is valid because no monotonic invariant exists.
local rewind_payload = {
    schema = AtomicTrace.SCHEMA,
    version = 1,
    finalized = true,
    instances = {
        { step = 1, occurrence = 1, action_id = 600,
          enter_frame = 30, exit_frame = 10,
          action_frame_start = 20, action_frame_end = 8 },
    },
}
local rewind_trace, rewind_status = AtomicTrace.from_payload(rewind_payload)
assert(rewind_trace ~= nil and rewind_status == "loaded")
assert(rewind_trace:get_instance(1).exit_frame == 10)

-- Unknown instance fields fail closed so semantic or presentation data cannot
-- be smuggled into the frozen Stage 1 trace contract.
local extra_trace = AtomicTrace.new()
local extra_instance, extra_error = extra_trace:append({
    action_id = 1, move_uid = "forbidden",
})
assert(extra_instance == nil and extra_error == "unknown_instance_field")

-- Empty trace roundtrip is valid.
local empty_trace = AtomicTrace.new()
empty_trace:finalize()
local empty_restored, empty_status = AtomicTrace.from_payload(empty_trace:to_payload())
assert(empty_restored ~= nil and empty_status == "loaded"
    and empty_restored:count() == 0)

-- Fail-closed parsing.
local function make_payload(overrides)
    local base = {
        schema = AtomicTrace.SCHEMA,
        version = 1,
        finalized = true,
        instances = { { step = 1, occurrence = 1, action_id = 600 } },
    }
    if overrides then
        for key, value in pairs(overrides) do base[key] = value end
    end
    return base
end

local no_schema, no_schema_status, no_schema_code = AtomicTrace.from_payload({})
expect_invalid(no_schema_status, no_schema_code, "unsupported_schema")
local no_version, no_version_status, no_version_code =
    AtomicTrace.from_payload(make_payload({ version = 2 }))
expect_invalid(no_version_status, no_version_code, "unsupported_version")
local missing_finalized_payload = make_payload()
missing_finalized_payload.finalized = nil
local no_finalized, no_finalized_status, no_finalized_code =
    AtomicTrace.from_payload(missing_finalized_payload)
expect_invalid(no_finalized_status, no_finalized_code, "finalized_trace_required")
local mutable_trace, mutable_status, mutable_code =
    AtomicTrace.from_payload(make_payload({ finalized = false }))
expect_invalid(mutable_status, mutable_code, "finalized_trace_required")
local semantic_instance, semantic_status, semantic_code =
    AtomicTrace.from_payload(make_payload({ instances = {
        { step = 1, occurrence = 1, action_id = 600, presentation = "x" },
    } }))
expect_invalid(semantic_status, semantic_code, "unknown_instance_field")
local bad_step, bad_step_status, bad_step_code =
    AtomicTrace.from_payload(make_payload({ instances = {
        { step = 2, occurrence = 1, action_id = 600 },
    } }))
expect_invalid(bad_step_status, bad_step_code, "step_mismatch")
local bad_occurrence, bad_occurrence_status, bad_occurrence_code =
    AtomicTrace.from_payload(make_payload({ instances = {
        { step = 1, occurrence = 3, action_id = 600 },
    } }))
expect_invalid(bad_occurrence_status, bad_occurrence_code, "occurrence_mismatch")
local bad_action, bad_action_status, bad_action_code =
    AtomicTrace.from_payload(make_payload({ instances = {
        { step = 1, occurrence = 1, action_id = "600" },
    } }))
expect_invalid(bad_action_status, bad_action_code, "invalid_action_id")
local not_array, not_array_status, not_array_code =
    AtomicTrace.from_payload(make_payload({ instances = {
        [2] = { step = 2, occurrence = 1, action_id = 600 },
    } }))
expect_invalid(not_array_status, not_array_code, "instances_not_array")

print("atomic trace tests passed")
