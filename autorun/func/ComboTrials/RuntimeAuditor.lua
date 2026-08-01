-- Pure policy and report helpers for end-to-end auditing of installed combos.
-- Runtime loading, replay and Action observation remain owned by the main script.

local Transcriber = require("func/ComboTrials/Transcriber")

local RuntimeAuditor = {
    name = "ComboTrials.RuntimeAuditor",
    REPORT_SCHEMA = "sf6cc.combo_runtime_audit.v1",
    REPORT_ROOT = "TrainingComboTrials_data/RuntimeAuditReports",
    VALIDATION_REVISION = 31,
}

local function deep_copy(value)
    return Transcriber.deep_copy(value)
end

local function normalize_path(value)
    return tostring(value or ""):gsub("\\", "/"):lower()
end

local function normalize_character(value)
    return tostring(value or "")
        :gsub("^%s+", "")
        :gsub("%s+$", "")
        :lower()
        :gsub("[^%w]", "")
end

local function table_entry_count(value)
    if type(value) ~= "table" then return nil end
    local count = 0
    for _ in pairs(value) do count = count + 1 end
    return count
end

local function is_nonnegative_integer(value)
    return type(value) == "number"
        and value >= 0
        and value < math.huge
        and value == math.floor(value)
end

local function append_reason(evaluation, reason)
    evaluation.reasons = type(evaluation.reasons) == "table"
        and evaluation.reasons or {}
    evaluation.reasons[#evaluation.reasons + 1] = reason
    evaluation.ok = false
end

-- This validator intentionally accepts only the complete payload emitted by
-- ComboTrials_ImGui.validate_sequence_command_display. A partial/forged
-- `ok=true` must never turn an unresolved command table into an audit pass.
-- The function is pure so persisted reports can be checked with the same
-- contract without trusting their stored counters or status.
local function validate_command_display_shape(validation, context)
    context = type(context) == "table" and context or {}
    if type(validation) ~= "table" then
        return {
            ok = false,
            reason = "runtime_command_display_validation_missing",
            actual_unresolved_count = 0,
        }
    end

    local actual_unresolved_count = table_entry_count(validation.unresolved)
    if actual_unresolved_count == nil then
        return {
            ok = false,
            reason = "runtime_command_display_validation_invalid:unresolved",
            actual_unresolved_count = 0,
        }
    end

    local count_fields = {
        "total_steps",
        "resolved_step_count",
        "preserved_step_count",
        "suppressed_step_count",
        "unresolved_count",
    }
    for _, field in ipairs(count_fields) do
        if not is_nonnegative_integer(validation[field]) then
            return {
                ok = false,
                reason = "runtime_command_display_validation_invalid:" .. field,
                actual_unresolved_count = actual_unresolved_count,
            }
        end
    end

    if validation.unresolved_count ~= actual_unresolved_count then
        return {
            ok = false,
            reason = "runtime_command_display_validation_invalid:unresolved_count_mismatch",
            actual_unresolved_count = actual_unresolved_count,
        }
    end
    if validation.resolved_step_count + validation.preserved_step_count
        + validation.suppressed_step_count + validation.unresolved_count
        ~= validation.total_steps then
        return {
            ok = false,
            reason = "runtime_command_display_validation_invalid:step_count_mismatch",
            actual_unresolved_count = actual_unresolved_count,
        }
    end
    if validation.map_status == nil or type(validation.map_status) ~= "string"
        or validation.map_status == "" then
        return {
            ok = false,
            reason = "runtime_command_display_validation_invalid:map_status",
            actual_unresolved_count = actual_unresolved_count,
        }
    end
    if validation.mode ~= "classic" and validation.mode ~= "modern" then
        return {
            ok = false,
            reason = "runtime_command_display_validation_invalid:mode",
            actual_unresolved_count = actual_unresolved_count,
        }
    end
    local validation_character = normalize_character(validation.character)
    if validation_character == "" or validation_character == "unknown" then
        return {
            ok = false,
            reason = "runtime_command_display_validation_invalid:character",
            actual_unresolved_count = actual_unresolved_count,
        }
    end
    if context.expected_total_steps ~= nil then
        if not is_nonnegative_integer(context.expected_total_steps)
            or context.expected_total_steps <= 0 then
            return {
                ok = false,
                reason = "runtime_command_display_validation_invalid:expected_total_steps",
                actual_unresolved_count = actual_unresolved_count,
            }
        end
        if validation.total_steps ~= context.expected_total_steps then
            return {
                ok = false,
                reason = "runtime_command_display_validation_invalid:total_steps_context",
                actual_unresolved_count = actual_unresolved_count,
            }
        end
    end
    if context.expected_character ~= nil then
        local expected_character = normalize_character(context.expected_character)
        if expected_character == "" or expected_character == "unknown" then
            return {
                ok = false,
                reason = "runtime_command_display_validation_invalid:expected_character",
                actual_unresolved_count = actual_unresolved_count,
            }
        end
        if validation_character ~= expected_character then
            return {
                ok = false,
                reason = "runtime_command_display_validation_invalid:character_context",
                actual_unresolved_count = actual_unresolved_count,
            }
        end
    end

    return {
        ok = true,
        actual_unresolved_count = actual_unresolved_count,
    }
end

function RuntimeAuditor.validate_command_display_payload(validation, context)
    local shape = validate_command_display_shape(validation, context)
    if not shape.ok then return shape end
    local actual_unresolved_count = shape.actual_unresolved_count
    if actual_unresolved_count > 0 then
        return {
            ok = false,
            reason = string.format(
                "runtime_command_display_unresolved:count=%d",
                actual_unresolved_count
            ),
            actual_unresolved_count = actual_unresolved_count,
        }
    end
    if validation.ok ~= true then
        return {
            ok = false,
            reason = "runtime_command_display_validation_invalid:ok",
            actual_unresolved_count = 0,
        }
    end
    if validation.status ~= "resolved" then
        return {
            ok = false,
            reason = "runtime_command_display_validation_invalid:status",
            actual_unresolved_count = 0,
        }
    end
    if validation.map_available ~= true then
        return {
            ok = false,
            reason = "runtime_command_display_validation_invalid:map_available",
            actual_unresolved_count = 0,
        }
    end
    if validation.map_status ~= "loaded" then
        return {
            ok = false,
            reason = "runtime_command_display_validation_invalid:map_status",
            actual_unresolved_count = 0,
        }
    end
    if validation.total_steps <= 0 then
        return {
            ok = false,
            reason = "runtime_command_display_validation_invalid:total_steps_empty",
            actual_unresolved_count = 0,
        }
    end
    -- Preserved text means the classic renderer fell back to the JSON motion
    -- because the catalog could not resolve it. It is a defined diagnostic
    -- class, but it is never acceptable in a successful runtime audit.
    if validation.preserved_step_count ~= 0 then
        return {
            ok = false,
            reason = "runtime_command_display_validation_invalid:preserved_steps",
            actual_unresolved_count = 0,
        }
    end
    return {
        ok = true,
        actual_unresolved_count = 0,
    }
end

-- REFramework serializes an empty Lua table as JSON null. On report reload,
-- that null becomes nil, so recover only the exact persisted proof emitted by
-- a successful live validation. Keep the live validator strict: callers that
-- pass unresolved=nil directly must still fail closed.
local function normalize_persisted_empty_unresolved(validation)
    if type(validation) ~= "table"
        or validation.unresolved ~= nil
        or validation.unresolved_count ~= 0
        or validation.actual_unresolved_count ~= 0
        or validation.ok ~= true
        or validation.status ~= "resolved" then
        return validation
    end

    local normalized = deep_copy(validation)
    normalized.unresolved = {}
    return normalized
end

local function validate_command_display(evaluation, runtime, sequence)
    local validation = runtime.command_display_validation
    local result = RuntimeAuditor.validate_command_display_payload(validation, {
        expected_total_steps = type(sequence) == "table" and #sequence or 0,
        expected_character = runtime.character == nil and "" or runtime.character,
    })
    if type(validation) == "table" then
        evaluation.command_display_validation = deep_copy(validation)
        evaluation.command_display_validation.actual_unresolved_count =
            result.actual_unresolved_count
    else
        evaluation.command_display_validation = {
            ok = false,
            unresolved = {},
            unresolved_count = 0,
            actual_unresolved_count = 0,
            status = "missing",
        }
    end
    if not result.ok then append_reason(evaluation, result.reason) end
end

function RuntimeAuditor.classify_report_item(item, context)
    if type(item) ~= "table" then
        return "stale", "runtime_audit_item_invalid"
    end
    if tonumber(item.validation_revision) ~= RuntimeAuditor.VALIDATION_REVISION then
        return "stale", "runtime_audit_item_revision_stale"
    end
    if item.status ~= "passed" and item.status ~= "failed" then
        return "stale", "runtime_audit_item_status_invalid"
    end

    local total_steps = type(item.trial_completion) == "table"
        and item.trial_completion.total_steps or nil
    if not is_nonnegative_integer(total_steps) or total_steps <= 0 then
        return "stale", "runtime_audit_item_trial_total_steps_invalid"
    end
    local expected_character = type(context) == "table" and context.character or nil
    local normalized_expected_character = normalize_character(expected_character)
    if normalized_expected_character == ""
        or normalized_expected_character == "unknown" then
        return "stale", "runtime_audit_report_character_invalid"
    end

    local persisted_validation = normalize_persisted_empty_unresolved(
        item.command_display_validation
    )
    local shape = validate_command_display_shape(
        persisted_validation,
        {
            expected_total_steps = total_steps,
            expected_character = expected_character,
        }
    )
    if not shape.ok then return "stale", shape.reason end
    if item.status == "failed" then return "failed", nil end

    local display = RuntimeAuditor.validate_command_display_payload(
        persisted_validation,
        {
            expected_total_steps = total_steps,
            expected_character = expected_character,
        }
    )
    if not display.ok then return "stale", display.reason end
    return "passed", nil
end

-- Return a copy whose counters represent what the current validator can
-- actually trust. Persisted summary counters remain available for diagnostics,
-- but are never presented as current audit truth after loading.
function RuntimeAuditor.recompute_loaded_report_state(report)
    local recalculated = type(report) == "table" and deep_copy(report) or {}
    recalculated.items = type(recalculated.items) == "table"
        and recalculated.items or {}
    recalculated.persisted_counts = {
        passed = type(report) == "table" and tonumber(report.passed) or 0,
        failed = type(report) == "table" and tonumber(report.failed) or 0,
        stale = type(report) == "table" and tonumber(report.stale) or 0,
    }

    local counts = { passed = 0, failed = 0, stale = 0 }
    for _, item in ipairs(recalculated.items) do
        local state, reason = RuntimeAuditor.classify_report_item(item, {
            character = recalculated.character,
        })
        item.effective_audit_status = state
        item.effective_audit_reason = reason
        counts[state] = counts[state] + 1
    end
    recalculated.total = #recalculated.items
    recalculated.passed = counts.passed
    recalculated.failed = counts.failed
    recalculated.stale = counts.stale
    recalculated.effective_counts = deep_copy(counts)
    return recalculated, counts
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
        local state = RuntimeAuditor.classify_report_item(item, {
            character = type(run) == "table" and run.character or nil,
        })
        if state == "failed" then counts.failed = counts.failed + 1 end
        if state == "stale" then counts.stale = counts.stale + 1 end
        if state ~= "passed" and key ~= "" and not seen[key] then
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
        local state = RuntimeAuditor.classify_report_item(item, {
            character = type(run) == "table" and run.character or nil,
        })
        if state == "failed"
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
    validate_command_display(evaluation, runtime, sequence)
    if runtime.trial_completed ~= true then
        append_reason(evaluation, "runtime_trial_not_completed")
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
            input = "relative_raw_inputs_or_raw_inputs",
            input_priority = {
                "relative_raw_inputs",
                "raw_inputs",
            },
            action_truth = "runtime_action_id_or_verified_command_owner",
            raw_action_trace = "compiled.trace.observed_actions",
            timing_tolerance = 2,
            command_display = {
                source = "runtime.command_display_validation",
                required = true,
                pass_condition = "strict_resolved_step_count_invariants",
            },
            outcome_checks = {
                "action_sequence",
                "action_timing",
                "combo_count",
                "damage",
                "block_contacts",
                "drive_usage",
                "super_usage",
                "command_display_completeness",
                "training_ui_completion",
            },
        },
        items = deep_copy(run.items or {}),
    }
end

return RuntimeAuditor
