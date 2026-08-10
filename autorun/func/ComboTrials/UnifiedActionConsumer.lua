-- Single consumer gateway for the existing Action contract.
--
-- This module owns no Action rules. It only keeps recording, validation and
-- audit callers on the same compiler, matcher and command resolver APIs.

local ActionEventCompiler = require("func/ComboTrials/ActionEventCompiler")
local ActionMatcher = require("func/ComboTrials/ActionMatcher")
local CommandResolver = require("func/ComboTrials/CommandResolver")
local TrainingEnvironment = require("func/ComboTrials/TrainingEnvironment")

local M = {
    name = "ComboTrials.UnifiedActionConsumer",
}

function M.new_capture(options)
    return ActionEventCompiler.new(options)
end

function M.observe_capture(session, sample)
    return ActionEventCompiler.observe(session, sample)
end

function M.finalize_capture(session, options)
    return ActionEventCompiler.finalize(session, options)
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

function M.matches_expected_action_id(
    expected,
    actual_action_id,
    expected_exception,
    compatibility_rules
)
    return ActionMatcher.matches_expected_action_id(
        expected,
        actual_action_id,
        expected_exception,
        compatibility_rules
    )
end

function M.should_admit_ignored_expected_action(
    input_truth_mode,
    expected,
    actual_action_id,
    expected_exception,
    compatibility_rules
)
    return ActionMatcher.should_admit_ignored_expected_action(
        input_truth_mode,
        expected,
        actual_action_id,
        expected_exception,
        compatibility_rules
    )
end

function M.classify_runtime_transition(params)
    return ActionMatcher.classify_runtime_transition(params)
end

function M.match_expected_action(
    expected,
    actual_action_id,
    actual_motion,
    actual_input,
    expected_exception,
    compatibility_rules
)
    return ActionMatcher.match_expected_action(
        expected,
        actual_action_id,
        actual_motion,
        actual_input,
        expected_exception,
        compatibility_rules
    )
end

return M
