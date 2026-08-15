package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local consumer = require("func/ComboTrials/UnifiedActionConsumer")
local compiler = require("func/ComboTrials/ActionEventCompiler")
local command_resolver = require("func/ComboTrials/CommandResolver")
local sequence_normalizer = require("func/ComboTrials/ActionSequenceNormalizer")

local function assert_equal(actual, expected, message)
    assert(actual == expected, string.format(
        "%s (expected=%s actual=%s)",
        message,
        tostring(expected),
        tostring(actual)
    ))
end

local source_timeline = { "5f : 4", "4f : 4+MP+MK", "6f : 6" }
local source_raw_inputs = { 8, 8 | 32 | 256, 4 }
local leading_prefix_source = {
    {
        id = 38,
        motion = "7",
        delay_from_prev = 0,
        timeline = source_timeline,
        relative_raw_inputs = source_raw_inputs,
        expected_hp = 8765,
        has_hit = true,
        _xt_meta = { schema = 2, title = "prefix" },
    },
    { id = 17, motion = "66", delay_from_prev = 3 },
    { id = 480, motion = "Drive Parry", delay_from_prev = 2 },
    { id = 500, motion = "drive rush", delay_from_prev = 4 },
    { id = 623, motion = "2MP", delay_from_prev = 22 },
    { id = 17, motion = "66", delay_from_prev = 18 },
    { id = 480, motion = "PARRY", delay_from_prev = 3 },
}
local leading_prefix_result = consumer.normalize_sequence(leading_prefix_source)
assert(leading_prefix_result.ok == true
        and leading_prefix_result.prefix_length == 1
        and leading_prefix_result.inline_removed_count == 2
        and #leading_prefix_result.sequence == 4,
    "a contiguous leading direction/dash/parry prefix must be removed")
assert(leading_prefix_result.sequence[1].id == 500
        and leading_prefix_result.sequence[1].delay_from_prev == 0
        and leading_prefix_result.sequence[1].expected_hp == nil
        and leading_prefix_result.sequence[1].has_hit == nil,
    "Presentation and Detector must start at the first semantic action")
assert(leading_prefix_result.sequence[2].id == 623
        and leading_prefix_result.sequence[3].id == 17
        and leading_prefix_result.sequence[4].id == 480,
    "directions, dashes and parries after the semantic start must remain strict")
assert(leading_prefix_result.sequence[1].timeline ~= source_timeline
        and leading_prefix_result.sequence[1].timeline[2] == source_timeline[2]
        and leading_prefix_result.sequence[1].relative_raw_inputs ~= source_raw_inputs
        and leading_prefix_result.sequence[1].relative_raw_inputs[2]
            == source_raw_inputs[2]
        and leading_prefix_result.sequence[1]._xt_meta.title == "prefix",
    "the normalized first step must copy the frozen replay and metadata payload")
assert(leading_prefix_source[1].id == 38
        and leading_prefix_source[2].id == 17
        and leading_prefix_source[3].id == 480
        and leading_prefix_source[4].delay_from_prev == 4,
    "normalization must not rewrite the frozen V2 source sequence")

for _, motions in ipairs({
    { "7", "66", "PARRY" },
    { "66" },
    { "2", "Drive Parry" },
}) do
    local source = {}
    for index, motion in ipairs(motions) do
        source[index] = { id = 100 + index, motion = motion, delay_from_prev = index - 1 }
    end
    source[#source + 1] = { id = 500, motion = "DR", delay_from_prev = 5 }
    source[#source + 1] = { id = 623, motion = "2MP", delay_from_prev = 10 }
    local result = consumer.normalize_sequence(source)
    assert(result.ok == true and #result.sequence == 2
            and result.sequence[1].id == 500
            and result.sequence[2].id == 623,
        "leading precursor order and cardinality must not alter the semantic sequence")
end

local wrong_semantic_start = sequence_normalizer.normalize({
    { id = 17, motion = "66" },
    { id = 623, motion = "2MP" },
    { id = 500, motion = "DR" },
})
assert(wrong_semantic_start.ok == true
        and wrong_semantic_start.sequence[1].id == 17,
    "a standalone leading 66 must remain a real checkpoint")

local jump_attack = sequence_normalizer.normalize({
    { id = 38, motion = "7" },
    { id = 652, motion = "j.HP", has_hit = true },
})
assert(jump_attack.ok == true and #jump_attack.sequence == 1
        and jump_attack.sequence[1].id == 652,
    "a leading jump direction must be hidden without hiding the jump attack Action")

local all_prefix = sequence_normalizer.normalize({
    { id = 38, motion = "7" },
    { id = 17, motion = "66" },
    { id = 480, motion = "PARRY" },
})
assert(all_prefix.ok == true
        and all_prefix.prefix_length == 1
        and #all_prefix.sequence == 2
        and all_prefix.sequence[1].id == 17
        and all_prefix.sequence[2].id == 480,
    "leading 66 and Parry must remain unless a bounded RAW DR owns them")

local ryu_6954_source = {
    {
        id = 1037,
        motion = "214+MP",
        delay_from_prev = 0,
        expected_combo = 0,
        has_hit = false,
        has_contact = false,
        timeline = { "4f : 2", "4f : 3", "3f : 6", "1f : 6+MP" },
        relative_raw_inputs = { 2, 6, 38, 102 },
        _xt_meta = { schema = 2, title = "Ryu 6954" },
    },
    {
        id = 1040,
        motion = "214+PP",
        delay_from_prev = 1,
        expected_combo = 1,
        has_hit = true,
        has_contact = true,
    },
    { id = 663, motion = "4+HP", delay_from_prev = 60 },
}
local ryu_6954 = consumer.normalize_sequence(ryu_6954_source)
assert(ryu_6954.ok == true
        and ryu_6954.inline_removed_count == 1
        and #ryu_6954.sequence == 2
        and ryu_6954.sequence[1].id == 1040
        and ryu_6954.sequence[1].delay_from_prev == 0,
    "legacy Ryu 214+MP must be projected out when 214+PP appears one frame later")
assert(ryu_6954.sequence[1].timeline ~= ryu_6954_source[1].timeline
        and ryu_6954.sequence[1].timeline[4] == "1f : 6+MP"
        and ryu_6954.sequence[1]._xt_meta.title == "Ryu 6954",
    "partial-chord projection must move frozen replay payload without mutating V2")
assert(ryu_6954_source[1].id == 1037
        and ryu_6954_source[2].delay_from_prev == 1,
    "partial-chord normalization must leave the frozen source sequence unchanged")

local staggered_multi_button = {
    {
        id = 608,
        motion = "MP",
        delay_from_prev = 0,
        expected_combo = 0,
        relative_raw_inputs = { 0 },
        timeline = { "1f : 5" },
        _xt_meta = { step_notes = { "MP", "LP", "PP" } },
    },
    { id = 601, motion = "LP", delay_from_prev = 1, expected_combo = 0 },
    { id = 700, motion = "PP", delay_from_prev = 1, expected_combo = 0 },
}
local staggered_multi_button_result = consumer.normalize_sequence(
    staggered_multi_button
)
assert(staggered_multi_button_result.ok == true
        and staggered_multi_button_result.partial_chord_removed_count == 2
        and #staggered_multi_button_result.sequence == 1
        and staggered_multi_button_result.sequence[1].motion == "PP"
        and staggered_multi_button_result.sequence[1].delay_from_prev == 0
        and staggered_multi_button_result.sequence[1]._xt_meta.step_notes[1] == "PP",
    "all adjacent non-contact button phases must collapse into one chord step")
local staggered_multi_button_second = consumer.normalize_sequence(
    staggered_multi_button_result.sequence
)
assert(staggered_multi_button_second.ok == true
        and staggered_multi_button_second.partial_chord_removed_count == 0
        and #staggered_multi_button_second.sequence == 1,
    "partial-chord normalization must be idempotent after one pass")

for _, fixture in ipairs({
    {
        name = "contacted precursor",
        sequence = {
            { id = 1, motion = "214+MP", has_contact = true, expected_combo = 1 },
            { id = 2, motion = "214+PP", delay_from_prev = 1, expected_combo = 2 },
        },
    },
    {
        name = "different command stem",
        sequence = {
            { id = 1, motion = "236+MP", has_contact = false },
            { id = 2, motion = "214+PP", delay_from_prev = 1 },
        },
    },
    {
        name = "outside completion window",
        sequence = {
            { id = 1, motion = "214+MP", has_contact = false },
            { id = 2, motion = "214+PP", delay_from_prev = 21 },
        },
    },
    {
        name = "button excluded by explicit chord",
        sequence = {
            { id = 1, motion = "214+MP", has_contact = false },
            { id = 2, motion = "214+LP+HP", delay_from_prev = 1 },
        },
    },
}) do
    local result = consumer.normalize_sequence(fixture.sequence)
    assert(result.ok == true and #result.sequence == 2,
        fixture.name .. " must remain two independent V2 checkpoints")
end

local action_semantic_parry = consumer.normalize_sequence({
    { id = 480, motion = "Normal", delay_from_prev = 0 },
    { id = 500, motion = "DR", delay_from_prev = 4 },
})
assert(action_semantic_parry.ok == true
        and action_semantic_parry.prefix_length == 0
        and action_semantic_parry.sequence[1].id == 500,
    "Drive Parry Action semantics must not depend on stale display text")

local terry_2220 = consumer.normalize_sequence({
    { id = 17, motion = "66", delay_from_prev = 0 },
    { id = 500, motion = "drive rush", delay_from_prev = 4 },
    { id = 623, motion = "2MP", delay_from_prev = 22 },
    { id = 635, motion = "2MK", delay_from_prev = 33 },
    { id = 670, motion = ">2HK", delay_from_prev = 16 },
    { id = 933, motion = "214+HP", delay_from_prev = 31 },
})
assert(terry_2220.ok == true and terry_2220.prefix_length == 0
        and terry_2220.inline_removed_count == 1
        and #terry_2220.sequence == 5
        and terry_2220.sequence[1].id == 500
        and terry_2220.sequence[2].id == 623
        and terry_2220.sequence[5].id == 933,
    "Terry 2220 must present and detect from Drive Rush without rewriting V2")

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
        ac_command_phase_relation_count = 1,
        ac_command_phase_relations = {
            {
                source_action_id = 936,
                target_action_id = 915,
                action_ids = { 915, 936 },
                source_trigger_index = 73,
                target_trigger_index = 82,
                branch_type = 52,
                attr = 256,
                action_frame = 0,
                param00 = 1,
                param01 = 3,
                condition_delta_fields = { "kind_level", "limit_shot_category" },
                fingerprint_fields = { "Category", "Combo", "Projectile", "State" },
                reason = "ac_type52_same_command_runtime_phase_family",
            },
        },
        internal_transition_suppression_count = 2,
        suppressed_internal_transitions = {
            {
                kind = "ac_type2_type4_terminal_execution_phase",
                source_action_id = 952,
                target_action_id = 953,
                branch_types = { 2, 4 },
                attr = 0,
                action_frame = 0,
                param00 = 0,
                param01 = 0,
                param02 = 0,
                param03 = 0,
                param04 = 0,
                param05 = 0,
                trigger_id = -1,
                reason = "ac_type2_type4_zero_parameter_terminal_execution_phase",
            },
            {
                kind = "ac_type2_same_structure_execution_phase",
                source_action_id = 1062,
                middle_action_id = 1063,
                tail_action_id = 1064,
                target_action_id = 1063,
                phase_index = 1,
                branch_type = 2,
                attr = 288,
                action_frame = 0,
                param00 = 0,
                param01 = 0,
                param02 = 0,
                param03 = 0,
                param04 = 0,
                param05 = 0,
                trigger_id = -1,
                fingerprint_fields = {
                    "Category", "Combo", "Projectile", "State",
                },
                reason = "ac_type2_same_structure_zero_parameter_execution_phase",
            },
        },
        audit = {
            ac_state_direction_relation_count = 1,
            ac_state_direction_route_count = 1,
            ac_command_phase_relation_count = 1,
            internal_transition_suppression_count = 2,
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
    ["915"] = {
        ownership = "direct",
        classic_command = { display = "214+LP", inputs = { "214+LP" } },
        routes = { {
            source = "bcm_profile", direct_evidence = true, owner_action_id = 915,
            trigger_index = 82, profile = "sprt", command_no = 2, command_index = 1,
            raw_direction_inputs = { 2, 6, 4 }, raw_button_mask = 16,
            raw_button_condition = 81952, raw_dc_exc_flags = 0, raw_ng_key_flags = 0,
        } },
    },
    ["936"] = {
        ownership = "direct",
        classic_command = { display = "214+LP", inputs = { "214+LP" } },
        routes = { {
            source = "bcm_profile", direct_evidence = true, owner_action_id = 936,
            trigger_index = 73, profile = "sprt", command_no = 2, command_index = 1,
            raw_direction_inputs = { 2, 6, 4 }, raw_button_mask = 16,
            raw_button_condition = 81952, raw_dc_exc_flags = 0, raw_ng_key_flags = 0,
        } },
    },
    ["953"] = {
        ownership = "internal_execution_phase",
        suppress_display = true,
        transition_evidence = {
            kind = "ac_type2_type4_terminal_execution_phase",
            source_action_id = 952,
            target_action_id = 953,
            branch_types = { 2, 4 },
            attr = 0,
            action_frame = 0,
            param00 = 0,
            param01 = 0,
            param02 = 0,
            param03 = 0,
            param04 = 0,
            param05 = 0,
            trigger_id = -1,
            reason = "ac_type2_type4_zero_parameter_terminal_execution_phase",
        },
        routes = {},
    },
    ["1063"] = {
        ownership = "internal_execution_phase",
        suppress_display = true,
        transition_evidence = {
            kind = "ac_type2_same_structure_execution_phase",
            source_action_id = 1062,
            middle_action_id = 1063,
            tail_action_id = 1064,
            target_action_id = 1063,
            phase_index = 1,
            branch_type = 2,
            attr = 288,
            action_frame = 0,
            param00 = 0,
            param01 = 0,
            param02 = 0,
            param03 = 0,
            param04 = 0,
            param05 = 0,
            trigger_id = -1,
            fingerprint_fields = {
                "Category", "Combo", "Projectile", "State",
            },
            reason = "ac_type2_same_structure_zero_parameter_execution_phase",
        },
        routes = {},
    },
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
local jp_second_step = {
    id = 915,
    motion = "214+LP",
    delay_from_prev = 162,
    has_hit = false,
    has_contact = false,
}
assert(consumer.matches_expected_action_id(
        jp_second_step, 936, nil, nil, generated_relations),
    "JP second-line playback Action 936 must satisfy the frozen 915 step")
assert(jp_second_step.motion == "214+LP"
        and jp_second_step.delay_from_prev == 162
        and jp_second_step.has_hit == false
        and jp_second_step.has_contact == false,
    "the JP fixture must retain the recorded second-line timing and no-contact facts")
assert(consumer.matches_expected_action_id(
        { id = 915 }, 936, nil, nil, generated_relations),
    "a strict Type52 command-phase variant must match the frozen Action step")
local jp_phase_match = consumer.match_expected_action(
    { id = 915, motion = "214+LP" }, 936, "214+LP", "214+LP",
    nil, nil, generated_relations)
assert(jp_phase_match.matched == true
        and jp_phase_match.match_reason == "generated_source_group",
    "detector and audit matching must consume the generated command-phase family")
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
local yasmine_9940_internal = consumer.classify_runtime_transition({
    previous_step = { id = 952, motion = ">6+P" },
    expected_step = { id = 17, motion = "66" },
    expected_action_matches_current = false,
    actual_action_id = 953,
    input_anchor_kind = "button_release",
    generated_action_relations = generated_relations,
})
assert(yasmine_9940_internal.ignored == true
        and yasmine_9940_internal.reason == "generated_internal_execution_phase",
    "Yasmine 9940 must ignore the generated residue of the verified 952 step")
local yasmine_3020_internal = consumer.classify_runtime_transition({
    previous_step = { id = 1062, motion = "214+PP" },
    expected_step = { id = 612, motion = "HP" },
    expected_action_matches_current = false,
    actual_action_id = 1063,
    input_anchor_kind = "button_release",
    generated_action_relations = generated_relations,
})
assert(yasmine_3020_internal.ignored == true
        and yasmine_3020_internal.reason == "generated_internal_execution_phase",
    "Yasmine 3020 must ignore the generated residue of the verified 1062 step")
assert(consumer.classify_runtime_transition({
        previous_step = { id = 951 },
        expected_step = { id = 17 },
        expected_action_matches_current = false,
        actual_action_id = 953,
        input_anchor_kind = "button_release",
        generated_action_relations = generated_relations,
    }).ignored == false,
    "an internal phase must not be ignored for the wrong previous owner")
assert(consumer.classify_runtime_transition({
        previous_step = { id = 952 },
        expected_step = { id = 953 },
        expected_action_matches_current = true,
        actual_action_id = 953,
        input_anchor_kind = "button_release",
        generated_action_relations = generated_relations,
    }).reason == "expected_action",
    "an explicitly recorded internal Action must remain a real V2 checkpoint")
assert(consumer.classify_runtime_transition({
        previous_step = { id = 952 },
        expected_step = { id = 17 },
        expected_action_matches_current = false,
        actual_action_id = 953,
        input_anchor_kind = "button_release",
        generated_action_relations = nil,
    }).ignored == false,
    "missing or unvalidated generated evidence must fail closed")
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
