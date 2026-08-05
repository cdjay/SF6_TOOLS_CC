-- Pure policy and report helpers for end-to-end auditing of installed combos.
-- Runtime loading, replay and Action observation remain owned by the main script.

local Transcriber = require("func/ComboTrials/Transcriber")
local TrainingEnvironment = require("func/ComboTrials/TrainingEnvironment")

local RuntimeAuditor = {
    name = "ComboTrials.RuntimeAuditor",
    REPORT_SCHEMA = "sf6cc.combo_runtime_audit.v1",
    REPORT_ROOT = "TrainingComboTrials_data/RuntimeAuditReports",
    VALIDATION_REVISION = 47,
    COMPATIBLE_VALIDATION_REVISIONS = {
        [35] = "monotonic_timeline_outcome_relaxation",
        [36] = "data_driven_quick_successor_live_validation",
        [37] = "monotonic_runtime_damage_drift_advisory",
        [38] = "top_level_runtime_damage_drift_advisory",
        [39] = "contextual_input_anchor_owner_projection",
        [40] = "contextual_internal_phase_damage_and_input_projection",
        [41] = "strict_training_ui_completion_requirement",
        [43] = "monotonic_legacy_timeline_outcome_relaxation",
        [44] = "burnout_guard_chip_tail_attribution",
        [45] = "version_scoped_motion_guarded_action_compatibility",
        [46] = "timeline_transcription_source_outcome_restore",
    },
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

local function exact_action_sequence_matches(sequence, compiled)
    local steps = type(compiled) == "table" and compiled.steps or nil
    if type(sequence) ~= "table" or type(steps) ~= "table"
        or #sequence == 0 or #sequence ~= #steps then
        return false
    end
    for index = 1, #sequence do
        if tonumber(sequence[index] and sequence[index].id)
            ~= tonumber(steps[index] and steps[index].id) then
            return false
        end
    end
    return true
end

local function recorded_defender_is_burned_out(sequence)
    local first = type(sequence) == "table" and sequence[1] or nil
    local scene = type(first) == "table" and first.scene_state or nil
    local players = type(scene) == "table" and scene.players or nil
    if type(players) ~= "table" then return false end
    local recorded_by = tonumber(first.recorded_by or scene.recorded_by) == 1
        and 1 or 0
    local defender = players[recorded_by == 1 and "p1" or "p2"]
    return type(defender) == "table"
        and type(defender.status) == "table"
        and defender.status.burnout == true
end

-- Burnout chip damage can arrive as HP-loss samples after the first contact of
-- a terminal multi-hit super even though the Action owner never changes. Audit
-- only: require full guard, exact Actions, completed UI, and exact HP closure.
local function burnout_guard_chip_tail_proof(sequence, compiled, runtime, evaluation)
    local reasons = type(evaluation) == "table" and evaluation.reasons or nil
    local expected = type(evaluation) == "table" and evaluation.expected or nil
    local observed = type(evaluation) == "table" and evaluation.observed or nil
    local steps = type(compiled) == "table" and compiled.steps or nil
    local trace = type(compiled) == "table" and compiled.trace or nil
    local first = type(sequence) == "table" and sequence[1] or nil
    local source_environment = type(first) == "table"
        and type(first._xt_meta) == "table"
        and type(first._xt_meta.environment) == "table"
        and first._xt_meta.environment or {}
    local source_guard = tonumber(type(first) == "table" and first.dummy_guard_type)
        or tonumber(source_environment.dummy_guard_type)
    local observed_guard = tonumber(
        type(runtime.environment_observed) == "table"
            and runtime.environment_observed.dummy_guard_type
    )
    if type(reasons) ~= "table" or #reasons ~= 1
        or not tostring(reasons[1]):match(
            "^replay_unattributed_damage_tick:max=%d+:unconfirmed=%d+$"
        )
        or runtime.trial_completed ~= true
        or runtime.input_completed ~= true
        or runtime.timed_out == true
        or source_guard ~= TrainingEnvironment.DUMMY_GUARD.ALL
        or observed_guard ~= TrainingEnvironment.DUMMY_GUARD.ALL
        or not recorded_defender_is_burned_out(sequence)
        or not exact_action_sequence_matches(sequence, compiled)
        or type(expected) ~= "table" or type(observed) ~= "table"
        or type(steps) ~= "table" or type(trace) ~= "table" then
        return nil
    end

    local expected_damage = tonumber(expected.damage)
    local event_damage = tonumber(observed.damage)
    local hp_loss = tonumber(observed.observed_hp_loss)
    local unconfirmed = math.max(0, tonumber(observed.unconfirmed_hp_loss) or 0)
    if expected_damage == nil or event_damage == nil or hp_loss == nil
        or unconfirmed <= 0
        or math.abs(hp_loss - expected_damage) > 1
        or math.abs(event_damage + unconfirmed - hp_loss) > 1
        or (tonumber(observed.max_combo) or 0)
            ~= (tonumber(expected.max_combo) or 0)
        or (tonumber(observed.block_contacts) or 0)
            ~= (tonumber(expected.block_contacts) or 0) then
        return nil
    end

    local expected_terminal = sequence[#sequence]
    local observed_terminal = steps[#steps]
    local bound_events = type(trace.input_bound_events) == "table"
        and trace.input_bound_events or nil
    local bound_terminal = bound_events and bound_events[#bound_events] or nil
    if type(expected_terminal) ~= "table"
        or type(observed_terminal) ~= "table"
        or type(bound_terminal) ~= "table"
        or tonumber(expected_terminal.id) ~= tonumber(observed_terminal.id)
        or tonumber(observed_terminal.id) ~= tonumber(bound_terminal.id)
        or (bound_terminal.has_contact ~= true and bound_terminal.has_hit ~= true)
        or math.abs((tonumber(expected_terminal.damage_at_step) or -1)
            - expected_damage) > 1
        or math.abs((tonumber(bound_terminal.damage_at_step) or -1)
            + unconfirmed - expected_damage) > 1 then
        return nil
    end

    local contact_frame = tonumber(bound_terminal.first_contact_frame)
        or tonumber(bound_terminal.frame)
    local last_activity = tonumber(trace.last_activity_frame)
    local samples = type(trace.passive_damage_samples) == "table"
        and trace.passive_damage_samples or nil
    if contact_frame == nil or last_activity == nil
        or last_activity <= contact_frame or samples == nil or #samples < 2 then
        return nil
    end
    local count, total, first_frame, final_frame = 0, 0, nil, nil
    for _, sample in ipairs(samples) do
        local frame = tonumber(type(sample) == "table" and sample.frame)
        local delta = tonumber(type(sample) == "table" and sample.delta)
        if frame == nil or delta == nil or delta <= 0
            or frame <= contact_frame or frame > last_activity then
            return nil
        end
        count = count + 1
        total = total + delta
        first_frame = first_frame == nil and frame or math.min(first_frame, frame)
        final_frame = final_frame == nil and frame or math.max(final_frame, frame)
    end
    if count < 2 or math.abs(total - unconfirmed) > 1 then return nil end
    return {
        action_id = tonumber(bound_terminal.id),
        count = count,
        total = total,
        contact_frame = contact_frame,
        first_frame = first_frame,
        final_frame = final_frame,
    }
end

local function strict_raw_replay_proves_completion(evaluation, runtime)
    local input_source = runtime.input_source
    local has_strict_input = input_source == "raw_inputs"
        or input_source == "relative_raw_inputs"
    return has_strict_input
        and runtime.input_completed == true
        and runtime.timed_out ~= true
        and evaluation.ok == true
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
    local revision = tonumber(item.validation_revision)
    if revision ~= RuntimeAuditor.VALIDATION_REVISION
        and RuntimeAuditor.COMPATIBLE_VALIDATION_REVISIONS[revision] == nil then
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
    local replay_runtime = {}
    for key, value in pairs(runtime) do replay_runtime[key] = value end
    replay_runtime.allow_timeline = true
    replay_runtime.reason_prefix = "replay_"
    -- Legacy timeline rows are validated by the same training UI the player
    -- uses, plus final outcome and command-display checks. Their historical
    -- step counters and Action grouping are not the strict compiler schema
    -- used by generated raw candidates, so retain trace drift as diagnostics.
    replay_runtime.strict_step_validation = runtime.input_source ~= "timeline"
    replay_runtime.allow_legacy_timeline_outcome_compatibility =
        runtime.input_source == "timeline"
            and runtime.trial_completed == true
    -- Compatibility audits answer whether the route still executes on the
    -- current game build. When Action truth, combo count, terminal contact,
    -- blocks, resources and environment still agree, a damage-only balance
    -- change is stale derived data rather than a broken route.
    replay_runtime.allow_runtime_damage_drift =
        runtime.trial_completed == true
    replay_runtime.allow_transcription_outcome_restore = true
    local evaluation = Transcriber.verify_replay(
        sequence,
        compiled,
        replay_runtime
    )
    local guard_chip_tail = burnout_guard_chip_tail_proof(
        sequence,
        compiled,
        runtime,
        evaluation
    )
    if guard_chip_tail ~= nil then
        evaluation.reasons = {}
        evaluation.ok = true
        evaluation.burnout_guard_chip_tail = deep_copy(guard_chip_tail)
        evaluation.advisories = type(evaluation.advisories) == "table"
            and evaluation.advisories or {}
        evaluation.advisories[#evaluation.advisories + 1] = string.format(
            "burnout_guard_chip_tail:action=%s:count=%d:total=%d:"
                .. "first=%d:last=%d:contact=%d",
            tostring(guard_chip_tail.action_id),
            guard_chip_tail.count,
            guard_chip_tail.total,
            guard_chip_tail.first_frame,
            guard_chip_tail.final_frame,
            guard_chip_tail.contact_frame
        )
    end
    validate_command_display(evaluation, runtime, sequence)
    local training_ui_completed = runtime.trial_completed == true
    local strict_replay_completed = not training_ui_completed
        and strict_raw_replay_proves_completion(evaluation, runtime)
    if not training_ui_completed and not strict_replay_completed then
        append_reason(evaluation, "runtime_trial_not_completed")
    end
    evaluation.trial_completion = deep_copy(runtime.trial_completion or {})
    evaluation.trial_completion.effective_completed = training_ui_completed
        or strict_replay_completed
    if training_ui_completed then
        evaluation.trial_completion.completion_source = "training_ui"
    elseif strict_replay_completed then
        evaluation.trial_completion.completion_source = "strict_raw_replay"
    end
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
            input = "relative_raw_inputs_or_raw_inputs_or_timeline",
            input_priority = {
                "relative_raw_inputs",
                "raw_inputs",
                "timeline",
            },
            action_truth = "runtime_action_id_or_verified_command_owner",
            replay_action_trace = "compiled.trace.observed_actions",
            raw_action_trace = "compiled.trace.observed_actions",
            timing_tolerance = 2,
            step_trace_policy = {
                relative_raw_inputs = "strict",
                raw_inputs = "strict",
                timeline = "advisory_with_training_ui_completion_required",
            },
            timeline_outcome_policy = {
                guarded_followup =
                    "advisory_when_explicit_noncontact_bridge_runtime_reset_and_post_reset_block_are_proven",
                combo_count_only =
                    "advisory_when_damage_contacts_and_completion_match",
                damage_only =
                    "advisory_when_actions_combo_terminal_contact_blocks_and_completion_match",
                damage_and_combo =
                    "advisory_for_completed_timeline_with_exact_actions_terminal_contact_and_blocks",
                drive_only =
                    "advisory_for_completed_timeline_with_exact_actions_outcome_and_positive_consumption",
                super_and_terminal_contact = "strict",
            },
            raw_outcome_policy = {
                transcribed_timeline_restore =
                    "advisory_only_when_provenance_original_outcome_exact_actions_contacts_resources_and_terminal_match",
            },
            compatible_validation_revisions =
                deep_copy(RuntimeAuditor.COMPATIBLE_VALIDATION_REVISIONS),
            command_display = {
                source = "runtime.command_display_validation",
                required = true,
                pass_condition = "strict_resolved_step_count_invariants",
            },
            completion_policy = {
                timeline = "training_ui_required",
                raw_inputs = "training_ui_or_strict_replay",
                relative_raw_inputs = "training_ui_or_strict_replay",
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
                "completion_proof",
            },
        },
        items = deep_copy(run.items or {}),
    }
end

return RuntimeAuditor
