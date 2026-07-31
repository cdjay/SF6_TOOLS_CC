-- Pure policy and report helpers for end-to-end auditing of installed combos.
-- Runtime loading, replay and Action observation remain owned by the main script.

local Transcriber = require("func/ComboTrials/Transcriber")

local RuntimeAuditor = {
    name = "ComboTrials.RuntimeAuditor",
    REPORT_SCHEMA = "sf6cc.combo_runtime_audit.v1",
    REPORT_ROOT = "TrainingComboTrials_data/RuntimeAuditReports",
    VALIDATION_REVISION = 23,
}

local function deep_copy(value)
    return Transcriber.deep_copy(value)
end

local function normalize_path(value)
    return tostring(value or ""):gsub("\\", "/"):lower()
end

function RuntimeAuditor.select_single_path(paths, requested_path)
    local requested = normalize_path(requested_path)
    if requested == "" then return {} end
    for _, path in ipairs(type(paths) == "table" and paths or {}) do
        if normalize_path(path) == requested then return { path } end
    end
    return {}
end

function RuntimeAuditor.retry_source_paths(run)
    local paths = {}
    local seen = {}
    local counts = { failed = 0, stale = 0 }
    local items = type(run) == "table" and type(run.items) == "table"
        and run.items or {}
    for _, item in ipairs(items) do
        local path = item and item.source_file
        local key = normalize_path(path)
        local failed = item and item.status ~= "passed"
        local stale = item
            and tonumber(item.validation_revision)
                ~= RuntimeAuditor.VALIDATION_REVISION
        if failed then counts.failed = counts.failed + 1 end
        if stale then counts.stale = counts.stale + 1 end
        if (failed or stale) and key ~= "" and not seen[key] then
            paths[#paths + 1] = path
            seen[key] = true
        end
    end
    return paths, counts
end

function RuntimeAuditor.failed_source_paths(run)
    local paths = {}
    local seen = {}
    local items = type(run) == "table" and type(run.items) == "table"
        and run.items or {}
    for _, item in ipairs(items) do
        local path = item and item.source_file
        local key = normalize_path(path)
        if item and item.status ~= "passed"
            and key ~= "" and not seen[key] then
            paths[#paths + 1] = path
            seen[key] = true
        end
    end
    return paths
end

function RuntimeAuditor.new_run(character, paths, now, options)
    options = type(options) == "table" and options or {}
    local run = Transcriber.new_run(character, paths, now)
    run.mode = "runtime_audit"
    run.audit_scope = options.scope or "all"
    run.requested_path = options.requested_path
    run.status = "准备审计运行目录"
    return run
end

function RuntimeAuditor.evaluate(sequence, compiled, runtime)
    runtime = type(runtime) == "table" and runtime or {}
    local evaluation = Transcriber.verify_candidate(sequence, compiled, runtime)
    if runtime.trial_completed ~= true then
        evaluation.ok = false
        evaluation.reasons[#evaluation.reasons + 1] =
            "runtime_trial_not_completed"
    end
    evaluation.trial_completion = deep_copy(runtime.trial_completion or {})
    return evaluation
end

function RuntimeAuditor.report(run)
    return {
        schema = RuntimeAuditor.REPORT_SCHEMA,
        validation_revision = RuntimeAuditor.VALIDATION_REVISION,
        audit_scope = run.audit_scope or "all",
        requested_path = run.requested_path,
        source_audit_report = run.source_audit_report,
        character = run.character,
        started_at = run.started_at,
        finished_at = run.finished_at,
        canceled = run.cancel_requested == true,
        fatal_error = run.fatal_error,
        total = run.total,
        processed = run.index,
        passed = run.passed,
        failed = run.failed,
        status = run.status,
        report_path = run.report_path,
        verifier = {
            input = "raw_inputs",
            action_truth = "runtime_action_id",
            timing_tolerance = 2,
            outcome_checks = {
                "action_sequence",
                "action_timing",
                "combo_count",
                "damage",
                "block_contacts",
                "drive_usage",
                "super_usage",
                "training_ui_completion",
            },
        },
        items = deep_copy(run.items or {}),
    }
end

return RuntimeAuditor
