package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local RawTrial = require("func/ComboTrials/Raw/RawTrial")

-- A trial owns the atomic trace plus references and metadata.
local trial = RawTrial.new("Ryu", {
    fighter_id = 0,
    game_build = "sf6b_test",
    control_mode = "Classic",
    recorded_at = "2026-08-09T00:00:00Z",
})
assert(trial ~= nil)
trial:trace():append(600)
trial:trace():append(601)
trial:trace():append(600)
assert(trial:set_raw_input_ref({
    source = "relative_raw_inputs",
    field = "relative_raw_inputs",
    encoding = "facing_relative_v1",
}) == true)
assert(trial:set_timeline_ref({
    source = "timeline",
    field = "timeline",
}) == true)
assert(trial:set_result({ legacy_step_count = 3, raw_input_count = 120 }) ~= nil)
trial:finalize()

-- The trial table itself is read-only; callers use methods only.
local trial_mutation = pcall(function() trial.character = "Ken" end)
assert(trial_mutation == false, "RawTrial instances must reject writes")

-- Environment copies cannot pollute internal state.
local env_copy = trial:environment()
env_copy.character = "Ken"
assert(trial:environment().character == "Ryu")

-- Payload roundtrip preserves trace, refs, environment and result metadata.
local payload = trial:to_payload()
assert(payload.schema == RawTrial.SCHEMA and payload.version == 1)
assert(payload.trace.instances[3].occurrence == 2)
assert(payload.raw_input_ref.encoding == "facing_relative_v1")
assert(payload.result.legacy_step_count == 3)

local restored, restored_status = RawTrial.from_payload(payload)
assert(restored ~= nil and restored_status == "loaded")
assert(restored:trace():count() == 3)
assert(restored:environment().character == "Ryu")
assert(restored:environment().control_mode == "Classic")
assert(restored:raw_input_ref().encoding == "facing_relative_v1")
assert(restored:timeline_ref().field == "timeline")
assert(restored:result().raw_input_count == 120)

-- The optional namespace is the only backward-compatible V2 insertion point.
local block = RawTrial.build_namespace_block(trial)
assert(block.raw_stage1.schema == RawTrial.SCHEMA)
local parsed, parsed_status = RawTrial.parse_namespace_block(block)
assert(parsed ~= nil and parsed_status == "loaded")
assert(parsed:trace():get_instances()[1].action_id == 600)

-- Old data without an atomic block reports legacy and is not reinterpreted.
local legacy_nil, legacy_nil_status = RawTrial.parse_namespace_block(nil)
assert(legacy_nil == nil and legacy_nil_status == "legacy")
local legacy_empty, legacy_empty_status = RawTrial.parse_namespace_block({})
assert(legacy_empty == nil and legacy_empty_status == "legacy")
local legacy_meta = { title = "old combo", environment = { character = "Ryu" } }
local legacy_old, legacy_old_status = RawTrial.parse_namespace_block(legacy_meta)
assert(legacy_old == nil and legacy_old_status == "legacy")

-- A present but malformed namespace fails closed with an explicit code.
local bad_block, bad_status, bad_code =
    RawTrial.parse_namespace_block({ raw_stage1 = "bad" })
assert(bad_block == nil and bad_status == "invalid"
    and bad_code == "raw_stage1_not_object")
local bad_schema_block, bad_schema_status, bad_schema_code =
    RawTrial.parse_namespace_block({ raw_stage1 = { schema = "wrong" } })
assert(bad_schema_block == nil and bad_schema_status == "invalid"
    and bad_schema_code == "unsupported_schema")
local bad_trace_block, bad_trace_status, bad_trace_code =
    RawTrial.parse_namespace_block({
        raw_stage1 = {
            schema = RawTrial.SCHEMA,
            version = 1,
            environment = { character = "Ryu" },
            trace = { schema = "wrong" },
        },
    })
assert(bad_trace_block == nil and bad_trace_status == "invalid"
    and bad_trace_code == "unsupported_schema")
local semantic_environment, semantic_environment_status, semantic_environment_code =
    RawTrial.parse_namespace_block({ raw_stage1 = {
        schema = RawTrial.SCHEMA,
        version = 1,
        environment = { character = "Ryu", move_uid = "forbidden" },
        trace = payload.trace,
    } })
assert(semantic_environment == nil and semantic_environment_status == "invalid"
    and semantic_environment_code == "unknown_environment_field")

-- Construction validation stays explicit.
local bad_char, bad_char_err = RawTrial.new("")
assert(bad_char == nil and bad_char_err == "invalid_character")
local bad_fighter, bad_fighter_err = RawTrial.new("Ryu", { fighter_id = -1 })
assert(bad_fighter == nil and bad_fighter_err == "invalid_environment")
local bad_ref, bad_ref_err = RawTrial.new("Ryu", {
    raw_input_ref = { source = "" },
})
assert(bad_ref == nil and bad_ref_err == "ref_source_required")

-- finalize delegates to the trace.
local trial_finalized = RawTrial.new("Luke", { game_build = "sf6b_test" })
trial_finalized:trace():append(1200)
local final_summary = trial_finalized:finalize()
assert(final_summary.finalized == true and final_summary.count == 1)

print("raw trial tests passed")
