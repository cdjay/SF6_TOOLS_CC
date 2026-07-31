package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local RuntimeAuditor = require("func/ComboTrials/RuntimeAuditor")

local selected = RuntimeAuditor.select_single_path({
    "TrainingComboTrials_data\\CustomCombos\\Ryu\\A.json",
    "TrainingComboTrials_data\\CustomCombos\\Ryu\\B.json",
}, "trainingcombotrials_data/customcombos/ryu/B.JSON")
assert(#selected == 1 and selected[1]:match("B%.json$"),
    "single audit must resolve the loaded combo without depending on slash or case")
assert(#RuntimeAuditor.select_single_path({ "A.json" }, "B.json") == 0,
    "single audit must not escape the current character's installed file list")

local candidate = {
    {
        id = 600,
        motion = "LP",
        expected_combo = 1,
        damage_at_step = 300,
        delay_from_prev = 0,
        raw_inputs = { 16, 0 },
        combo_stats = {
            damage = 300,
            drive_used = 0,
            super_used = 0,
        },
    },
}

local compiled = {
    steps = {
        {
            id = 600,
            motion = "LP",
            expected_combo = 1,
            damage_at_step = 300,
            delay_from_prev = 0,
        },
    },
    stats = {
        damage = 300,
        max_combo = 1,
        block_contacts = 0,
        drive_used = 0,
        super_used = 0,
        unresolved_anchors = 0,
    },
}

local passed = RuntimeAuditor.evaluate(candidate, compiled, {
    raw_inputs = candidate[1].raw_inputs,
    input_completed = true,
    timing_tolerance = 2,
    trial_completed = true,
    trial_completion = {
        completed = true,
        current_step = 2,
        total_steps = 1,
    },
})
assert(passed.ok == true,
    "runtime audit must accept an installed combo that reproduces its Action truth")

compiled.steps[1].id = 601
local failed = RuntimeAuditor.evaluate(candidate, compiled, {
    raw_inputs = candidate[1].raw_inputs,
    input_completed = true,
    timing_tolerance = 2,
    trial_completed = true,
})
assert(failed.ok == false
    and table.concat(failed.reasons, ","):match("raw_replay_action_id_mismatch"),
    "runtime audit must reject a different runtime Action ID")

compiled.steps[1].id = 600
local ui_incomplete = RuntimeAuditor.evaluate(candidate, compiled, {
    raw_inputs = candidate[1].raw_inputs,
    input_completed = true,
    timing_tolerance = 2,
    trial_completed = false,
    trial_completion = {
        completed = false,
        current_step = 1,
        total_steps = 1,
    },
})
assert(ui_incomplete.ok == false
    and ui_incomplete.reasons[#ui_incomplete.reasons]
        == "runtime_trial_not_completed",
    "runtime audit must reject an exact replay when the training UI does not finish")

local run = RuntimeAuditor.new_run("Ryu", { "A.json" }, "2026-07-30T00:00:00+08:00")
assert(run.mode == "runtime_audit",
    "runtime audit runs must remain distinguishable from transcription isolation")
run.active = false
run.index = 1
run.passed = 1
run.items = {
    {
        source_file = "A.json",
        source_name = "A.json",
        status = "passed",
        raw_replay_verified = true,
    },
}
local report = RuntimeAuditor.report(run)
assert(report.schema == RuntimeAuditor.REPORT_SCHEMA
    and report.verifier.input == "raw_inputs"
    and report.verifier.action_truth == "runtime_action_id",
    "runtime audit reports must disclose their truth source and validation policy")

local single_run = RuntimeAuditor.new_run(
    "Ryu",
    { "B.json" },
    "2026-07-30T00:00:00+08:00",
    { scope = "current", requested_path = "B.json" }
)
local single_report = RuntimeAuditor.report(single_run)
assert(single_report.audit_scope == "current"
    and single_report.requested_path == "B.json"
    and single_report.total == 1,
    "single audit reports must disclose their narrow scope")

local retry_paths, retry_counts = RuntimeAuditor.retry_source_paths({
    items = {
        {
            source_file = "A.json",
            status = "passed",
            validation_revision = RuntimeAuditor.VALIDATION_REVISION,
        },
        {
            source_file = "B.json",
            status = "passed",
            validation_revision = RuntimeAuditor.VALIDATION_REVISION - 1,
        },
        {
            source_file = "C.json",
            status = "failed",
            validation_revision = RuntimeAuditor.VALIDATION_REVISION,
        },
    },
})
assert(#retry_paths == 2
    and retry_paths[1] == "B.json"
    and retry_paths[2] == "C.json"
    and retry_counts.stale == 1
    and retry_counts.failed == 1,
    "retry selection must include stale passes without requeueing current passes")
local failed_paths = RuntimeAuditor.failed_source_paths({
    items = {
        {
            source_file = "A.json",
            status = "passed",
            validation_revision = RuntimeAuditor.VALIDATION_REVISION - 1,
        },
        {
            source_file = "B.json",
            status = "failed",
            validation_revision = RuntimeAuditor.VALIDATION_REVISION,
        },
        {
            source_file = "b.JSON",
            status = "failed",
            validation_revision = RuntimeAuditor.VALIDATION_REVISION,
        },
    },
})
assert(#failed_paths == 1 and failed_paths[1] == "B.json",
    "audit-to-transcription selection must exclude stale passes and deduplicate failures")

print("combo runtime auditor tests passed")
