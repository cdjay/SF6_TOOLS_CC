-- Single consumer gateway for the existing Action contract.
--
-- This module owns no Action rules. It only keeps recording, validation and
-- audit callers on the same compiler, matcher and command resolver APIs.

local ActionEventCompiler = require("func/ComboTrials/ActionEventCompiler")
local ActionMatcher = require("func/ComboTrials/ActionMatcher")
local ActionSequenceNormalizer = require("func/ComboTrials/ActionSequenceNormalizer")
local CommandResolver = require("func/ComboTrials/CommandResolver")
local GeneratedActionRelations = require("func/ComboTrials/GeneratedActionRelations")
local MoveResolver = require("func/ComboTrials/Semantic/MoveResolver")
local MoveResolverShadow = require("func/ComboTrials/Semantic/MoveResolverShadow")
local TrainingEnvironment = require("func/ComboTrials/TrainingEnvironment")

local M = {
    name = "ComboTrials.UnifiedActionConsumer",
    CHORD_COMPLETION_WINDOW = ActionMatcher.CHORD_COMPLETION_WINDOW,
    CHORD_ACTION_VISIBILITY_GRACE = ActionMatcher.CHORD_ACTION_VISIBILITY_GRACE,
    PLAYER_ACTION_BIND_WINDOW = ActionMatcher.PLAYER_ACTION_BIND_WINDOW,
    RAW_DRIVE_RUSH_DASH_PRECURSOR_WINDOW =
        ActionMatcher.RAW_DRIVE_RUSH_DASH_PRECURSOR_WINDOW,
    RAW_DRIVE_RUSH_PARRY_PRECURSOR_WINDOW =
        ActionMatcher.RAW_DRIVE_RUSH_PARRY_PRECURSOR_WINDOW,
    ATTEMPT_START_WRONG_TIMEOUT = ActionMatcher.ATTEMPT_START_WRONG_TIMEOUT,
}

local function normalize_sequence(sequence)
    return ActionSequenceNormalizer.normalize(
        sequence,
        ActionMatcher.sequence_normalization_options()
    )
end

function M.new_capture(options)
    return ActionEventCompiler.new(options)
end

function M.observe_capture(session, sample)
    return ActionEventCompiler.observe(session, sample)
end

function M.finalize_capture(session, options)
    local compiled = ActionEventCompiler.finalize(session, options)
    local normalization = normalize_sequence(compiled.steps)
    compiled.detectable_steps = normalization.sequence
    compiled.sequence_normalization = normalization
    return compiled
end

function M.normalize_sequence(sequence)
    return normalize_sequence(sequence)
end

function M.resolve_runtime_command(
    character,
    action_id,
    direct_input,
    newly_pressed,
    renderer
)
    return CommandResolver.resolve_unified_command_action(
        character,
        action_id,
        direct_input,
        newly_pressed,
        renderer
    )
end

function M.resolve_compiled_motion(character, action_id, event, session, renderer)
    if not renderer or not renderer.get_command_display
        or type(character) ~= "string" or character == "" then
        return nil, "map_unavailable"
    end

    local ok, display, status, metadata = pcall(
        renderer.get_command_display,
        character,
        action_id,
        "classic"
    )
    if not ok then return nil, "resolver_error", metadata end

    if status == "suppress_transition" then
        local anchor = type(event) == "table" and type(event.anchor) == "table"
            and event.anchor or {}
        local edge_buttons = CommandResolver.find_input_bound_transition_edge(
            character,
            event,
            session,
            renderer
        )
        local direct_input = (tonumber(anchor.held_buttons) or 0) | edge_buttons
        local intentional, transition_status, transition_motion =
            M.resolve_runtime_command(
                character,
                action_id,
                direct_input,
                edge_buttons,
                renderer
            )
        if intentional and type(transition_motion) == "string"
            and transition_motion ~= "" then
            return TrainingEnvironment.strip_counter_tags(transition_motion),
                transition_status,
                metadata
        end
        return nil, status, metadata
    end

    local trimmed = type(display) == "string"
        and display:match("^%s*(.-)%s*$") or ""
    if trimmed == "" then return nil, status, metadata end
    return TrainingEnvironment.strip_counter_tags(trimmed), status, metadata
end

function M.sequence_uses_input_truth(sequence)
    return ActionMatcher.sequence_uses_input_truth(sequence)
end

function M.should_defer_partial_chord(params)
    return ActionMatcher.should_defer_partial_chord(params)
end

function M.should_defer_raw_drive_rush_precursor(params)
    return ActionMatcher.should_defer_raw_drive_rush_precursor(params)
end

function M.load_generated_action_relations(character, loader)
    return GeneratedActionRelations.load(character, loader)
end

function M.load_move_resolver(options)
    return MoveResolver.load(options)
end

function M.compare_expected_action_shadow(resolver, params)
    if type(resolver) ~= "table" or type(resolver.compare_actions) ~= "function" then
        return {
            schema = "sf6cc.move-resolver-shadow.v1",
            authority = "diagnostic_only",
            production_result = "legacy",
            difference_category = "UNKNOWN",
            candidate_classification = "RESOLVER_UNAVAILABLE",
            severity = "BLOCKED",
            consumer = type(params) == "table" and params.consumer or "unknown",
        }
    end
    return MoveResolverShadow.compare_match(resolver, params)
end

function M.generated_actions_share_source_group(relations, left_id, right_id)
    return GeneratedActionRelations.share_source_group(relations, left_id, right_id)
end

function M.generated_action_command(relations, action_id)
    return GeneratedActionRelations.command_for_action(relations, action_id)
end

function M.latch_buffer_contact(
    has_hit,
    has_block_contact,
    observed_hit,
    observed_block_contact
)
    return ActionMatcher.latch_buffer_contact(
        has_hit,
        has_block_contact,
        observed_hit,
        observed_block_contact
    )
end

function M.attempt_start_wrong_timed_out(start_frame, current_frame)
    return ActionMatcher.attempt_start_wrong_timed_out(
        start_frame,
        current_frame
    )
end

function M.matches_expected_action_id(
    expected,
    actual_action_id,
    expected_exception,
    compatibility_rules,
    generated_action_relations
)
    return ActionMatcher.matches_expected_action_id(
        expected,
        actual_action_id,
        expected_exception,
        compatibility_rules
    )
        or GeneratedActionRelations.share_source_group(
            generated_action_relations,
            expected and expected.id,
            actual_action_id
        )
end

function M.should_admit_ignored_expected_action(
    input_truth_mode,
    expected,
    actual_action_id,
    expected_exception,
    compatibility_rules,
    generated_action_relations
)
    return input_truth_mode == true
        and M.matches_expected_action_id(
            expected,
            actual_action_id,
            expected_exception,
            compatibility_rules,
            generated_action_relations
        )
end

function M.should_preserve_absorbed_expected_action(
    input_truth_mode,
    expected,
    actual_action_id,
    expected_exception,
    compatibility_rules,
    generated_action_relations
)
    return input_truth_mode == true
        and M.matches_expected_action_id(
            expected,
            actual_action_id,
            expected_exception,
            compatibility_rules,
            generated_action_relations
        )
end

function M.classify_runtime_transition(params)
    params = type(params) == "table" and params or {}
    local result = ActionMatcher.classify_runtime_transition(params)
    if params.expected_action_matches_current ~= true
        and GeneratedActionRelations.is_internal_phase_of(
            params.generated_action_relations,
            params.previous_step and params.previous_step.id,
            params.actual_action_id
        ) then
        result.ignored = true
        result.reason = "generated_internal_execution_phase"
    end
    return result
end

function M.match_expected_action(
    expected,
    actual_action_id,
    actual_motion,
    actual_input,
    expected_exception,
    compatibility_rules,
    generated_action_relations
)
    local result = ActionMatcher.match_expected_action(
        expected,
        actual_action_id,
        actual_motion,
        actual_input,
        expected_exception,
        compatibility_rules
    )
    if result.matched ~= true
        and GeneratedActionRelations.share_source_group(
            generated_action_relations,
            expected and expected.id,
            actual_action_id
        ) then
        result.matched = true
        result.match_reason = "generated_source_group"
    end
    return result
end

return M
