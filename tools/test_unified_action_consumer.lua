package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local consumer = require("func/ComboTrials/UnifiedActionConsumer")
local compiler = require("func/ComboTrials/ActionEventCompiler")
local command_resolver = require("func/ComboTrials/CommandResolver")

local function assert_equal(actual, expected, message)
    assert(actual == expected, string.format(
        "%s (expected=%s actual=%s)",
        message,
        tostring(expected),
        tostring(actual)
    ))
end

local function resolver(action_id)
    if tonumber(action_id) == 627 then return "2+MP", "direct" end
    return nil, "missing"
end

local direct_session = compiler.new({
    character = "Ingrid",
    frame = 0,
    motion_resolver = resolver,
})
local consumer_session = consumer.new_capture({
    character = "Ingrid",
    frame = 0,
    motion_resolver = resolver,
})

local samples = {
    { frame = 0, action_id = 1, action_frame = 0, direct_input = 0,
        facing_right = true, combo_count = 0, victim_hp = 10000 },
    { frame = 1, action_id = 1, action_frame = 1, direct_input = 32,
        facing_right = true, combo_count = 0, victim_hp = 10000 },
    { frame = 2, action_id = 627, action_frame = 0, direct_input = 32,
        facing_right = true, combo_count = 0, victim_hp = 10000 },
    { frame = 3, action_id = 627, action_frame = 1, direct_input = 0,
        facing_right = true, combo_count = 1, victim_hp = 9700 },
}

for _, sample in ipairs(samples) do
    assert(compiler.observe(direct_session, sample))
    assert(consumer.observe_capture(consumer_session, sample))
end

local direct = compiler.finalize(direct_session, {
    motion_resolver = resolver,
    flush_recording_contacts = false,
})
local through_consumer = consumer.finalize_capture(consumer_session, {
    motion_resolver = resolver,
    flush_recording_contacts = false,
})
assert_equal(#through_consumer.steps, #direct.steps,
    "consumer capture must preserve compiler step count")
for index, step in ipairs(direct.steps) do
    local projected = through_consumer.steps[index]
    assert_equal(projected.id, step.id,
        "consumer capture must preserve Action ID")
    assert_equal(projected.motion, step.motion,
        "consumer capture must preserve motion")
    assert_equal(projected.expected_combo, step.expected_combo,
        "consumer capture must preserve outcome facts")
end

local renderer = {
    get_command_display = function(_, action_id)
        if tonumber(action_id) == 900 then
            return nil, "suppress_transition", { ownership = "transition" }
        end
        return " 2+MP ", "direct", { ownership = "bcm" }
    end,
}

local motion, status, metadata = consumer.resolve_compiled_motion(
    "Ingrid",
    627,
    nil,
    nil,
    renderer
)
assert_equal(motion, "2+MP", "compiled motion must use the shared command resolver")
assert_equal(status, "direct", "compiled motion must preserve route status")
assert_equal(metadata.ownership, "bcm", "compiled motion must preserve metadata")

local transition_event = {
    id = 900,
    frame = 20,
    anchor = {
        pressed_buttons = 32,
        released_buttons = 0,
        held_buttons = 0,
    },
}
motion, status = consumer.resolve_compiled_motion(
    "Ingrid",
    900,
    transition_event,
    { events = { transition_event } },
    renderer
)
assert_equal(motion, ">P (取消)",
    "input-bound transitions must use the shared runtime command decision")
assert_equal(status, "player_input_transition",
    "transition status must remain unchanged")

local match = consumer.match_expected_action({ id = 627, motion = "2+MP" }, 627)
assert(match.matched and match.match_reason == "id",
    "expected Action matching must delegate without redefining V2")
assert(consumer.sequence_uses_input_truth({
    { relative_raw_inputs = { 0, 32, 0 } },
}), "input-truth detection must use the shared matcher policy")
assert_equal(consumer.CHORD_COMPLETION_WINDOW, 20,
    "the gateway must expose the matcher chord window without redefining it")
assert_equal(consumer.CHORD_ACTION_VISIBILITY_GRACE, 2,
    "the gateway must expose the bounded Action visibility grace")
assert(consumer.should_defer_partial_chord({
        expected_step = { motion = "PP" },
        actual_motion = "HP",
        action_button_mask = 64,
        input_anchor_kind = "button_press",
        input_truth_mode = true,
        elapsed_frames = 8,
    }), "live deferral must flow through the shared consumer gateway")
local generated_document = {
    _meta = {
        schema = "xt.command_display.v1",
        strict_policy = "verified_action_graph_v1",
        generated_from = "ac_bcm",
        character = "Generic",
        ac_state_direction_route_count = 1,
        ac_state_direction_relations = {
            {
                reason = "ac_type20_multi_direction_state_choice",
                source_action_id = 101,
                source_action_ids = { 101, 102 },
            },
        },
        audit = {
            ac_state_direction_relation_count = 1,
            ac_state_direction_route_count = 1,
        },
    },
    ["100"] = {
        classic_command = { display = "HP", inputs = { "HP" } },
        routes = { { source = "bcm_profile", direct_evidence = true, owner_action_id = 100 } },
    },
    ["101"] = {
        classic_command = { display = "PP", inputs = { "PP" } },
        routes = { { source = "bcm_profile", direct_evidence = true, owner_action_id = 101 } },
    },
    ["102"] = { classic_command = { display = "PP", inputs = { "PP" } } },
}
local generated_relations = select(1,
    consumer.load_generated_action_relations("Generic", function()
        return generated_document
    end))
assert(consumer.generated_actions_share_source_group(
        generated_relations, 101, 102),
    "AC-generated source groups must confirm runtime Action variants")
assert(not consumer.generated_actions_share_source_group(
        generated_relations, 100, 101),
    "matching display text must not create an Action relation")
assert(consumer.matches_expected_action_id(
        { id = 101 }, 102, nil, nil, generated_relations),
    "generated source variants must match the same frozen Action step")
local generated_variant_match = consumer.match_expected_action(
    { id = 101, motion = "PP" }, 102, "PP", "PP", nil, nil,
    generated_relations)
assert(generated_variant_match.matched == true
        and generated_variant_match.match_reason == "generated_source_group",
    "runtime validation must advance on a strict AC source-group variant")
assert(consumer.should_admit_ignored_expected_action(
        true, { id = 101 }, 102, nil, nil, generated_relations),
    "input-truth admission must accept the same generated source variant")
assert(consumer.should_preserve_absorbed_expected_action(
        true, { id = 102 }, 102, nil, nil, generated_relations),
    "an absorbed runtime Action that is the frozen step must remain matchable")
assert(consumer.should_preserve_absorbed_expected_action(
        true, { id = 101 }, 102, nil, nil, generated_relations),
    "a strict generated source variant must remain matchable through absorption")
assert(not consumer.should_preserve_absorbed_expected_action(
        false, { id = 102 }, 102, nil, nil, generated_relations),
    "timeline-only playback must retain legacy absorption behavior")
assert(not consumer.should_preserve_absorbed_expected_action(
        true, { id = 100 }, 102, nil, nil, generated_relations),
    "an absorbed Action for a different step must remain a continuation")
assert_equal(consumer.generated_action_command(generated_relations, 100), "HP",
    "generated classic commands must be available without presentation overrides")
local gateway_hit, gateway_block = consumer.latch_buffer_contact(
    false, false, true, true)
assert(gateway_hit and gateway_block,
    "buffer contact latching must flow through the shared consumer gateway")
local collected_edges, collected_span, collected_press_frames =
    command_resolver.collect_action_button_edges({
        { frame_tick = 100, mask = 64 },
        { frame_tick = 108, mask = 32 },
    }, 100, 108, 45)
assert_equal(collected_edges, 96,
    "live input buffering must retain every edge that completes a staggered chord")
assert_equal(collected_span, 8,
    "live input buffering must measure chord completion from the Action start")
assert_equal(collected_press_frames[64], 100,
    "live input buffering must retain the first chord button's physical frame")
assert_equal(collected_press_frames[32], 108,
    "live input buffering must retain the completing chord button's physical frame")
local _, repeated_span, repeated_press_frames =
    command_resolver.collect_action_button_edges({
        { frame_tick = 100, mask = 64 },
        { frame_tick = 108, mask = 32 },
        { frame_tick = 118, mask = 64 },
    }, 100, 120, 45)
assert_equal(repeated_span, 18,
    "a repeated button press must remain the latest chord edge")
assert_equal(repeated_press_frames[64], 118,
    "live input buffering must match compiler last-press semantics")
assert_equal(command_resolver.collect_action_button_edges({
        { frame_tick = 40, mask = 64 },
        { frame_tick = 100, mask = 32 },
    }, 100, 108, 45), 32,
    "button edges before the current Action instance must not complete its chord")

local main = assert(io.open("autorun/TrainingComboTrials_v1.0.lua", "rb"))
local main_source = main:read("*a")
main:close()
assert(main_source:find(
        'UnifiedActionConsumer = require("func/ComboTrials/UnifiedActionConsumer")',
        1,
        true
    ), "main entry must load the unified consumer gateway")
assert(not main_source:find("ComboTrialsModules.ActionEventCompiler", 1, true),
    "main entry must not bypass the capture gateway")
assert(not main_source:find(
        "ComboTrialsModules.CommandResolver.resolve_unified_command_action",
        1,
        true
    ), "main entry must not bypass the command gateway")
assert(not main_source:find("ActionMatcher.match_expected_action", 1, true),
    "main entry must not bypass the expected-Action gateway")
assert(main_source:find(
        "args.generated_action_relations",
        1,
        true
    ), "pressure-step skipping must preserve generated Action relations")
assert(main_source:find(
        "generated_action_relations =%s*%n?%s*p_state.generated_action_relations"
    ), "the live pressure-step caller must pass generated Action relations")
assert(main_source:find(
        "UnifiedActionConsumer.should_preserve_absorbed_expected_action",
        1,
        true
    ), "live absorption must preserve the active frozen Action step")

print("UnifiedActionConsumer tests passed")
