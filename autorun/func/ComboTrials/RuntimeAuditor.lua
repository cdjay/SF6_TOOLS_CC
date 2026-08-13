-- Pure policy and report helpers for end-to-end auditing of installed combos.
-- Runtime loading, replay and Action observation remain owned by the main script.

local Transcriber = require("func/ComboTrials/Transcriber")
local TrainingEnvironment = require("func/ComboTrials/TrainingEnvironment")
local ActionSequenceNormalizer = require("func/ComboTrials/ActionSequenceNormalizer")
local ActionMatcher = require("func/ComboTrials/ActionMatcher")

local RuntimeAuditor = {
    name = "ComboTrials.RuntimeAuditor",
    REPORT_SCHEMA = "sf6cc.combo_runtime_audit.v1",
    REPORT_ROOT = "TrainingComboTrials_data/RuntimeAuditReports",
    VALIDATION_REVISION = 61,
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
        [57] = "recorded_motion_drift_and_strict_terminal_completion",
        [58] = "strict_timeline_unexpected_contact_action",
        [59] = "aggregated_same_action_contact_rows",
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

local function runtime_action_ids_match(runtime, expected_id, observed_id, index)
    expected_id = tonumber(expected_id)
    observed_id = tonumber(observed_id)
    if expected_id == nil or observed_id == nil then return false end
    if expected_id == observed_id then return true end
    if type(runtime.action_ids_equivalent) ~= "function" then return false end
    local ok, matched = pcall(
        runtime.action_ids_equivalent,
        expected_id,
        observed_id,
        index
    )
    return ok and matched == true
end

local function aggregated_contact_progresses(expected, previous, current)
    if type(expected) ~= "table" or type(previous) ~= "table"
        or type(current) ~= "table" then
        return false
    end

    local compared = 0
    local progressed = false
    for _, field in ipairs({ "expected_combo", "damage_at_step" }) do
        local limit = tonumber(expected[field])
        local before = tonumber(previous[field])
        local after = tonumber(current[field])
        if limit ~= nil and limit > 0 and before ~= nil and after ~= nil then
            compared = compared + 1
            if after < before or after > limit then return false end
            if after > before then progressed = true end
        end
    end
    return compared > 0 and progressed
end

-- Legacy timeline rows may carry obsolete non-contact state Actions, but an
-- additional compiled Action with hit/contact truth is a real omitted command.
-- Character phase rules and versioned Action compatibility run before this
-- check, so only still-unexplained contact Actions fail the audit.
local function timeline_unexpected_contact_actions(sequence, compiled, runtime)
    if runtime.input_source ~= "timeline"
        or runtime.input_completed ~= true
        or runtime.timed_out == true then
        return {}, {}
    end
    local expected_steps = type(sequence) == "table" and sequence or {}
    local observed_steps = type(compiled) == "table"
        and type(compiled.steps) == "table" and compiled.steps or {}
    if #expected_steps == 0 or #observed_steps == 0 then return {}, {} end

    local unexpected = {}
    local aggregated = {}
    local expected_index = 1
    local last_matched_expected_index = nil
    local last_matched_observed_index = nil
    local last_matched_observed = nil
    for observed_index, observed in ipairs(observed_steps) do
        local matched_index = nil
        for candidate_index = expected_index, #expected_steps do
            if runtime_action_ids_match(
                    runtime,
                    expected_steps[candidate_index] and expected_steps[candidate_index].id,
                    observed and observed.id,
                    candidate_index
                ) then
                matched_index = candidate_index
                break
            end
        end
        if matched_index ~= nil then
            expected_index = matched_index + 1
            last_matched_expected_index = matched_index
            last_matched_observed_index = observed_index
            last_matched_observed = observed
        elseif type(observed) == "table"
            and (observed.has_contact == true or observed.has_hit == true) then
            local repeated_expected = last_matched_expected_index
                and expected_steps[last_matched_expected_index] or nil
            local represented_repeat = last_matched_expected_index
                    == expected_index - 1
                and last_matched_observed_index == observed_index - 1
                and runtime_action_ids_match(
                    runtime,
                    repeated_expected and repeated_expected.id,
                    observed.id,
                    last_matched_expected_index
                )
                and aggregated_contact_progresses(
                    repeated_expected,
                    last_matched_observed,
                    observed
                )
            if represented_repeat then
                aggregated[#aggregated + 1] = {
                    observed_step = observed_index,
                    source_step = last_matched_expected_index,
                    action_id = tonumber(observed.id),
                    motion = observed.motion,
                }
                last_matched_observed_index = observed_index
                last_matched_observed = observed
            else
                unexpected[#unexpected + 1] = {
                    observed_step = observed_index,
                    action_id = tonumber(observed.id),
                    motion = observed.motion,
                    has_contact = observed.has_contact == true,
                    has_hit = observed.has_hit == true,
                }
            end
        end
    end
    return unexpected, aggregated
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
    local completion = type(runtime.trial_completion) == "table"
        and runtime.trial_completion or nil
    local current_step = completion and tonumber(completion.current_step) or nil
    local total_steps = completion and tonumber(completion.total_steps) or nil
    local fail_reason = completion and tostring(completion.fail_reason or "") or ""
    local fail_timer = completion and tonumber(completion.fail_timer) or 0
    -- An exact Action replay can repair only a missing success banner. The live
    -- validator must still have consumed the terminal step, and no wrong-move
    -- state may have occurred. Otherwise a route that stopped in the middle can
    -- reproduce its aggregate Action trace and be promoted to a false pass.
    local terminal_step_consumed = current_step ~= nil
        and total_steps ~= nil
        and total_steps > 0
        and current_step > total_steps
        and not fail_reason:find("%S")
        and (fail_timer or 0) <= 0
    return has_strict_input
        and runtime.input_completed == true
        and runtime.timed_out ~= true
        and terminal_step_consumed
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

    local actual_recorded_motion_drift_count =
        table_entry_count(validation.recorded_motion_drift)
    if actual_recorded_motion_drift_count == nil then
        return {
            ok = false,
            reason = "runtime_command_display_validation_invalid:recorded_motion_drift",
            actual_unresolved_count = actual_unresolved_count,
            actual_recorded_motion_drift_count = 0,
        }
    end

    local count_fields = {
        "total_steps",
        "resolved_step_count",
        "preserved_step_count",
        "suppressed_step_count",
        "unresolved_count",
        "recorded_motion_drift_count",
    }
    for _, field in ipairs(count_fields) do
        if not is_nonnegative_integer(validation[field]) then
            return {
                ok = false,
                reason = "runtime_command_display_validation_invalid:" .. field,
                actual_unresolved_count = actual_unresolved_count,
                actual_recorded_motion_drift_count = actual_recorded_motion_drift_count,
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
    if validation.recorded_motion_drift_count
        ~= actual_recorded_motion_drift_count then
        return {
            ok = false,
            reason = "runtime_command_display_validation_invalid:recorded_motion_drift_count_mismatch",
            actual_unresolved_count = actual_unresolved_count,
            actual_recorded_motion_drift_count = actual_recorded_motion_drift_count,
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
        actual_recorded_motion_drift_count = actual_recorded_motion_drift_count,
    }
end

local function valid_command_display_motion(value)
    if type(value) ~= "string" then return false end
    local normalized = value:match("^%s*(.-)%s*$") or ""
    if normalized == "" then return false end
    local upper = normalized:upper()
    return normalized:find("未识别", 1, true) == nil
        and upper:find("UNKNOWN", 1, true) == nil
        and upper:find("ACTION_", 1, true) == nil
end

local function validate_recorded_motion_drift_proof(validation)
    local actual_unresolved_count = table_entry_count(validation.unresolved) or 0
    local actual_recorded_motion_drift_count =
        table_entry_count(validation.recorded_motion_drift) or 0
    if actual_recorded_motion_drift_count == 0 then
        return {
            ok = true,
            actual_unresolved_count = actual_unresolved_count,
            actual_recorded_motion_drift_count = 0,
        }
    end
    if type(validation.steps) ~= "table"
        or table_entry_count(validation.steps) ~= validation.total_steps
        or #validation.steps ~= validation.total_steps then
        return {
            ok = false,
            reason = "runtime_command_display_validation_invalid:recorded_motion_drift_steps",
            actual_unresolved_count = actual_unresolved_count,
            actual_recorded_motion_drift_count = actual_recorded_motion_drift_count,
        }
    end

    local seen = {}
    for _, drift in ipairs(validation.recorded_motion_drift) do
        local index = tonumber(type(drift) == "table"
            and (drift.index or drift.step_index))
        local proof = index ~= nil and validation.steps[index] or nil
        if not is_nonnegative_integer(index) or index <= 0
            or index > validation.total_steps or seen[index]
            or type(proof) ~= "table" or proof.index ~= index
            or tonumber(drift.action_id) ~= tonumber(proof.source_action_id)
            or drift.recorded_motion ~= proof.recorded_motion
            or drift.display_motion ~= proof.display_motion
            or proof.require_recorded_motion_match ~= true
            or proof.recorded_motion_matches ~= false then
            return {
                ok = false,
                reason = "runtime_command_display_validation_invalid:recorded_motion_drift_steps",
                actual_unresolved_count = actual_unresolved_count,
                actual_recorded_motion_drift_count = actual_recorded_motion_drift_count,
            }
        end
        seen[index] = true
    end
    return {
        ok = true,
        actual_unresolved_count = actual_unresolved_count,
        actual_recorded_motion_drift_count = actual_recorded_motion_drift_count,
    }
end

local function validate_command_display_step_proof(validation, context)
    context = type(context) == "table" and context or {}
    local actual_unresolved_count = table_entry_count(validation.unresolved) or 0
    if not is_nonnegative_integer(validation.visible_step_count) then
        return {
            ok = false,
            reason = "runtime_command_display_validation_invalid:visible_step_count",
            actual_unresolved_count = actual_unresolved_count,
        }
    end
    if not is_nonnegative_integer(validation.visible_line_count) then
        return {
            ok = false,
            reason = "runtime_command_display_validation_invalid:visible_line_count",
            actual_unresolved_count = actual_unresolved_count,
        }
    end
    if type(validation.steps) ~= "table"
        or table_entry_count(validation.steps) ~= validation.total_steps
        or #validation.steps ~= validation.total_steps then
        return {
            ok = false,
            reason = "runtime_command_display_validation_invalid:steps",
            actual_unresolved_count = actual_unresolved_count,
        }
    end

    local expected_sequence = type(context.expected_sequence) == "table"
        and context.expected_sequence or nil
    local proof_counts = {
        resolved = 0,
        preserved = 0,
        suppressed = 0,
        unresolved = 0,
    }
    local unresolved_indexes = {}
    for _, unresolved in ipairs(validation.unresolved) do
        local index = tonumber(type(unresolved) == "table"
            and (unresolved.index or unresolved.step_index))
        if not is_nonnegative_integer(index) or index <= 0
            or index > validation.total_steps or unresolved_indexes[index] then
            return {
                ok = false,
                reason = "runtime_command_display_validation_invalid:unresolved_steps",
                actual_unresolved_count = actual_unresolved_count,
            }
        end
        unresolved_indexes[index] = true
    end

    local previous_group_key = nil
    local expected_visible_line = 0
    for index = 1, validation.total_steps do
        local proof = validation.steps[index]
        if type(proof) ~= "table" or proof.index ~= index then
            return {
                ok = false,
                reason = "runtime_command_display_validation_invalid:step_index",
                actual_unresolved_count = actual_unresolved_count,
            }
        end
        local source_action_id = tonumber(proof.source_action_id)
        local effective_action_id = tonumber(proof.effective_action_id)
        if not is_nonnegative_integer(source_action_id) then
            return {
                ok = false,
                reason = "runtime_command_display_validation_invalid:source_action_id",
                actual_unresolved_count = actual_unresolved_count,
            }
        end
        if expected_sequence ~= nil
            and source_action_id ~= tonumber(expected_sequence[index]
                and expected_sequence[index].id) then
            return {
                ok = false,
                reason = "runtime_command_display_validation_invalid:source_action_id_context",
                actual_unresolved_count = actual_unresolved_count,
            }
        end
        if not is_nonnegative_integer(effective_action_id) then
            return {
                ok = false,
                reason = "runtime_command_display_validation_invalid:effective_action_id",
                actual_unresolved_count = actual_unresolved_count,
            }
        end
        if proof.projected_action_id ~= nil then
            local projected_action_id = tonumber(proof.projected_action_id)
            if not is_nonnegative_integer(projected_action_id)
                or projected_action_id == source_action_id
                or effective_action_id ~= projected_action_id then
                return {
                    ok = false,
                    reason = "runtime_command_display_validation_invalid:projected_action_id",
                    actual_unresolved_count = actual_unresolved_count,
                }
            end
        elseif effective_action_id ~= source_action_id then
            return {
                ok = false,
                reason = "runtime_command_display_validation_invalid:effective_action_id",
                actual_unresolved_count = actual_unresolved_count,
            }
        end

        local classification = proof.classification
        if proof_counts[classification] == nil then
            return {
                ok = false,
                reason = "runtime_command_display_validation_invalid:classification",
                actual_unresolved_count = actual_unresolved_count,
            }
        end
        proof_counts[classification] = proof_counts[classification] + 1
        if type(proof.group_key) ~= "string" or proof.group_key == "" then
            return {
                ok = false,
                reason = "runtime_command_display_validation_invalid:group_key",
                actual_unresolved_count = actual_unresolved_count,
            }
        end
        if type(proof.route_status) ~= "string" or proof.route_status == "" then
            return {
                ok = false,
                reason = "runtime_command_display_validation_invalid:route_status",
                actual_unresolved_count = actual_unresolved_count,
            }
        end
        if type(proof.require_recorded_motion_match) ~= "boolean"
            or (proof.require_recorded_motion_match
                and proof.recorded_motion_matches ~= true)
            or (not proof.require_recorded_motion_match
                and proof.recorded_motion_matches ~= nil) then
            return {
                ok = false,
                reason = "runtime_command_display_validation_invalid:recorded_motion_match_proof",
                actual_unresolved_count = actual_unresolved_count,
            }
        end

        if classification == "suppressed" then
            if proof.visible ~= false or proof.visible_line_index ~= nil
                or proof.display_motion ~= nil then
                return {
                    ok = false,
                    reason = "runtime_command_display_validation_invalid:suppressed_step_visibility",
                    actual_unresolved_count = actual_unresolved_count,
                }
            end
        else
            if proof.visible ~= true then
                return {
                    ok = false,
                    reason = "runtime_command_display_validation_invalid:visible_step",
                    actual_unresolved_count = actual_unresolved_count,
                }
            end
            if previous_group_key ~= proof.group_key then
                expected_visible_line = expected_visible_line + 1
            end
            previous_group_key = proof.group_key
            if proof.visible_line_index ~= expected_visible_line then
                return {
                    ok = false,
                    reason = "runtime_command_display_validation_invalid:visible_line_topology",
                    actual_unresolved_count = actual_unresolved_count,
                }
            end
            if not valid_command_display_motion(proof.display_motion) then
                return {
                    ok = false,
                    reason = "runtime_command_display_validation_invalid:display_motion",
                    actual_unresolved_count = actual_unresolved_count,
                }
            end
        end
        if (classification == "unresolved") ~= (unresolved_indexes[index] == true) then
            return {
                ok = false,
                reason = "runtime_command_display_validation_invalid:unresolved_steps",
                actual_unresolved_count = actual_unresolved_count,
            }
        end
    end

    if proof_counts.resolved ~= validation.resolved_step_count
        or proof_counts.preserved ~= validation.preserved_step_count
        or proof_counts.suppressed ~= validation.suppressed_step_count
        or proof_counts.unresolved ~= validation.unresolved_count then
        return {
            ok = false,
            reason = "runtime_command_display_validation_invalid:step_proof_counts",
            actual_unresolved_count = actual_unresolved_count,
        }
    end
    if validation.visible_step_count
        ~= validation.total_steps - validation.suppressed_step_count then
        return {
            ok = false,
            reason = "runtime_command_display_validation_invalid:visible_step_count",
            actual_unresolved_count = actual_unresolved_count,
        }
    end
    if validation.visible_line_count ~= expected_visible_line then
        return {
            ok = false,
            reason = "runtime_command_display_validation_invalid:visible_line_count",
            actual_unresolved_count = actual_unresolved_count,
        }
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
    local actual_recorded_motion_drift_count =
        shape.actual_recorded_motion_drift_count
    if actual_unresolved_count > 0 then
        return {
            ok = false,
            reason = string.format(
                "runtime_command_display_unresolved:count=%d",
                actual_unresolved_count
            ),
            actual_unresolved_count = actual_unresolved_count,
            actual_recorded_motion_drift_count = actual_recorded_motion_drift_count,
        }
    end
    if actual_recorded_motion_drift_count > 0 then
        local drift_proof = validate_recorded_motion_drift_proof(validation)
        if not drift_proof.ok then return drift_proof end
        return {
            ok = false,
            reason = string.format(
                "runtime_command_display_recorded_motion_drift:count=%d",
                actual_recorded_motion_drift_count
            ),
            actual_unresolved_count = actual_unresolved_count,
            actual_recorded_motion_drift_count = actual_recorded_motion_drift_count,
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
    return validate_command_display_step_proof(validation, context)
end

-- REFramework serializes an empty Lua table as JSON null. On report reload,
-- that null becomes nil, so recover only lists whose persisted counters prove
-- they were empty. Keep the live validator strict: direct callers that pass a
-- required list as nil must still fail closed.
local function normalize_persisted_empty_command_display_lists(validation, item_status)
    if type(validation) ~= "table" then return validation end
    local successful_proof = validation.ok == true
        and validation.status == "resolved"
    local retained_failure = item_status == "failed"
        and validation.ok == false
        and type(validation.status) == "string"
        and validation.status ~= ""
    if not successful_proof and not retained_failure then return validation end

    local normalized = deep_copy(validation)
    if validation.unresolved == nil
        and validation.unresolved_count == 0
        and validation.actual_unresolved_count == 0 then
        normalized.unresolved = {}
    end
    if validation.recorded_motion_drift == nil
        and validation.recorded_motion_drift_count == 0
        and validation.actual_recorded_motion_drift_count == 0 then
        normalized.recorded_motion_drift = {}
    end
    return normalized
end

local function validate_command_display(evaluation, runtime, sequence)
    local validation = runtime.command_display_validation
    local result = RuntimeAuditor.validate_command_display_payload(validation, {
        expected_total_steps = type(sequence) == "table" and #sequence or 0,
        expected_character = runtime.character == nil and "" or runtime.character,
        expected_sequence = sequence,
    })
    if type(validation) == "table" then
        evaluation.command_display_validation = deep_copy(validation)
        evaluation.command_display_validation.actual_unresolved_count =
            result.actual_unresolved_count
        evaluation.command_display_validation.actual_recorded_motion_drift_count =
            result.actual_recorded_motion_drift_count or 0
    else
        evaluation.command_display_validation = {
            ok = false,
            unresolved = {},
            unresolved_count = 0,
            actual_unresolved_count = 0,
            recorded_motion_drift = {},
            recorded_motion_drift_count = 0,
            actual_recorded_motion_drift_count = 0,
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

    local persisted_validation = normalize_persisted_empty_command_display_lists(
        item.command_display_validation,
        item.status
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
    local normalization_options = ActionMatcher.sequence_normalization_options()
    local expected_normalization = ActionSequenceNormalizer.normalize(
        sequence,
        normalization_options
    )
    local observed_steps = type(compiled) == "table"
        and (compiled.detectable_steps or compiled.steps) or nil
    local observed_normalization = ActionSequenceNormalizer.normalize(
        observed_steps,
        normalization_options
    )
    if expected_normalization.ok ~= true or observed_normalization.ok ~= true then
        return {
            ok = false,
            reasons = {
                "sequence_normalization_failed:expected="
                    .. tostring(expected_normalization.reason)
                    .. ":observed=" .. tostring(observed_normalization.reason),
            },
            advisories = {},
            expected = {},
            observed = {},
        }
    end
    sequence = expected_normalization.sequence
    local normalized_compiled = {}
    for key, value in pairs(type(compiled) == "table" and compiled or {}) do
        normalized_compiled[key] = value
    end
    normalized_compiled.steps = observed_normalization.sequence
    compiled = normalized_compiled
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
    local unexpected_contact_actions, aggregated_contact_actions =
        timeline_unexpected_contact_actions(
        sequence,
        compiled,
        runtime
    )
    if #aggregated_contact_actions > 0 then
        evaluation.timeline_aggregated_same_action_contacts =
            deep_copy(aggregated_contact_actions)
    end
    if #unexpected_contact_actions > 0 then
        evaluation.timeline_unexpected_contact_actions =
            deep_copy(unexpected_contact_actions)
        for _, action in ipairs(unexpected_contact_actions) do
            append_reason(evaluation, string.format(
                "replay_unexpected_contact_action:observed_step=%d:action=%s",
                action.observed_step,
                tostring(action.action_id)
            ))
        end
    end
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
    evaluation.runtime_step_trace = deep_copy(runtime.runtime_step_trace or {})
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
                pass_condition = "strict_step_and_visible_line_invariants",
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
