package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local Relations = require("func/ComboTrials/GeneratedActionRelations")

local function phase_route(owner_action_id, trigger_index)
    return {
        source = "bcm_profile",
        direct_evidence = true,
        owner_action_id = owner_action_id,
        trigger_index = trigger_index,
        profile = "sprt",
        command_no = 2,
        command_index = 1,
        raw_direction_inputs = { 2, 6, 4 },
        raw_button_mask = 16,
        raw_button_condition = 81952,
        raw_dc_exc_flags = 0,
        raw_ng_key_flags = 0,
    }
end

local document = {
    _meta = {
        schema = "xt.command_display.v1",
        strict_policy = "verified_action_graph_v1",
        generated_from = "ac_bcm+capcom_official_semantics",
        character = "Generic",
        ac_state_direction_route_count = 1,
        type63_strength_variant_route_count = 1,
        type63_strength_variant_relation_count = 1,
        type63_strength_variant_relations = {
            {
                source_action_id = 20,
                target_action_id = 21,
                branch_type = 63,
                strength = "medium",
                classic_param01 = 32,
                modern_param01 = 128,
                reason = "ac_type63_classic_modern_strength_family",
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
        internal_transition_suppression_count = 1,
        suppressed_internal_transitions = {
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
        ac_state_direction_relations = {
            {
                reason = "ac_type20_multi_direction_state_choice",
                source_action_id = 10,
                source_action_ids = { 10, 11, 12 },
            },
        },
        audit = {
            ac_state_direction_relation_count = 1,
            ac_state_direction_route_count = 1,
            type63_strength_variant_relation_count = 1,
            type63_strength_variant_route_count = 1,
            ac_command_phase_relation_count = 1,
            internal_transition_suppression_count = 1,
        },
    },
    ["9"] = {
        classic_command = { display = "HP", inputs = { "HP" } },
        routes = { { source = "bcm_profile", direct_evidence = true, owner_action_id = 9 } },
    },
    ["10"] = {
        classic_command = { display = "2+PP", inputs = { "2+PP" } },
        routes = { { source = "bcm_profile", direct_evidence = true, owner_action_id = 10 } },
    },
    ["11"] = { classic_command = { display = "2+PP", inputs = { "2+PP" } } },
    ["12"] = { classic_command = { display = "2+PP", inputs = { "2+PP" } } },
    ["20"] = {
        ownership = "direct",
        classic_command = { display = "6+LP", inputs = { "6+LP" } },
        routes = { {
            display = "6 + 弱",
            character = "Generic",
            source = "bcm_profile",
            direct_evidence = true,
            inheritance_evidence = false,
            rebind_evidence = false,
            runtime_common_evidence = false,
            official_semantic_evidence = false,
            community_semantic_evidence = false,
            assist_combo_evidence = false,
            confidence = "direct_structural",
            owner_action_id = 20,
            visible_direction = "6",
            visible_button = "弱",
            button_candidates = { "弱" },
            required_button_count = 1,
        } },
    },
    ["21"] = {
        ownership = "type63_strength_variant",
        classic_command = { display = "6+MP", inputs = { "6+MP" } },
        routes = { {
            display = "6 + 中",
            character = "Generic",
            source = "ac_type63_strength_variant",
            owner_action_id = 20,
            bcm_owner_action_id = 20,
            display_action_id = 21,
            inherited_from_action_id = 20,
            ac_relation_type = 63,
            ac_path = { 20, 21 },
            direct_evidence = false,
            inheritance_evidence = true,
            rebind_evidence = false,
            runtime_common_evidence = false,
            official_semantic_evidence = false,
            community_semantic_evidence = false,
            assist_combo_evidence = false,
            inheritance_reason = "ac_type63_classic_modern_strength_family",
            confidence = "verified_inherited_strength_variant",
            strength = "medium",
            classic_param01 = 32,
            modern_param01 = 128,
            visible_direction = "6",
            visible_button = "中",
            button_candidates = { "中" },
            required_button_count = 1,
        } },
    },
    ["915"] = {
        ownership = "direct",
        classic_command = { display = "214+LP", inputs = { "214+LP" } },
        routes = { phase_route(915, 82) },
    },
    ["936"] = {
        ownership = "direct",
        classic_command = { display = "214+LP", inputs = { "214+LP" } },
        routes = { phase_route(936, 73) },
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

local relations, count, status = Relations.parse(document, "Generic")
assert(status == "loaded" and count == 2)
assert(Relations.command_for_action(relations, 9) == "HP")
assert(Relations.command_for_action(relations, 21) == "6+MP")
assert(Relations.share_source_group(relations, 10, 11))
assert(Relations.share_source_group(relations, 11, 12))
assert(not Relations.share_source_group(relations, 9, 10))
assert(not Relations.share_source_group(relations, 20, 21),
    "strength variants are distinct Actions, not source-group aliases")
assert(Relations.share_source_group(relations, 915, 936),
    "AC+BCM command-phase variants must share one runtime Move interpretation")
assert(Relations.is_internal_phase_of(relations, 1062, 1063),
    "audited internal execution phases must retain their generated owner")
assert(not Relations.is_internal_phase_of(relations, 1063, 1062),
    "internal execution ownership must remain directional")

local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[clone(key)] = clone(child) end
    return result
end

local wrong_strength_param = clone(document)
wrong_strength_param._meta.type63_strength_variant_relations[1].modern_param01 = 256
assert(Relations.parse(wrong_strength_param, "Generic") == nil,
    "mismatched Classic/Modern strength parameters must fail closed")

local wrong_strength_route = clone(document)
wrong_strength_route["21"].routes[1].visible_button = "强"
assert(Relations.parse(wrong_strength_route, "Generic") == nil,
    "a route that disagrees with the audited strength relation must fail closed")

local incomplete_phase_evidence = clone(document)
incomplete_phase_evidence._meta.ac_command_phase_relations[1].attr = nil
assert(Relations.parse(incomplete_phase_evidence, "Generic") == nil,
    "command-phase relations without complete AC evidence must fail closed")

local wrong_phase_conditions = clone(document)
wrong_phase_conditions._meta.ac_command_phase_relations[1].condition_delta_fields = {
    "kind_level",
}
assert(Relations.parse(wrong_phase_conditions, "Generic") == nil,
    "command-phase relations with incomplete BCM condition evidence must fail closed")

local wrong_phase_fingerprint = clone(document)
wrong_phase_fingerprint._meta.ac_command_phase_relations[1].fingerprint_fields = {
    "Category", "Combo", "State",
}
assert(Relations.parse(wrong_phase_fingerprint, "Generic") == nil,
    "command-phase relations without the complete AC core must fail closed")

local non_direct_phase_owner = clone(document)
non_direct_phase_owner["936"].ownership = "structural_twin"
assert(Relations.parse(non_direct_phase_owner, "Generic") == nil,
    "command-phase relations must require two direct BCM owners")

local mismatched_phase_inputs = clone(document)
mismatched_phase_inputs["936"].classic_command.inputs = { "236+LP" }
assert(Relations.parse(mismatched_phase_inputs, "Generic") == nil,
    "matching display text must not hide different BCM command inputs")

local mismatched_internal_audit = clone(document)
mismatched_internal_audit._meta.audit.internal_transition_suppression_count = 2
assert(Relations.parse(mismatched_internal_audit, "Generic") == nil,
    "internal execution phases must match the generated audit count")

local mismatched_internal_evidence = clone(document)
mismatched_internal_evidence["1063"].transition_evidence.attr = 32
assert(Relations.parse(mismatched_internal_evidence, "Generic") == nil,
    "target entries must repeat the exact audited transition evidence")

local routed_internal_target = clone(document)
routed_internal_target["1063"].routes = {
    { source = "bcm_profile", direct_evidence = true, owner_action_id = 1063 },
}
assert(Relations.parse(routed_internal_target, "Generic") == nil,
    "an internal execution phase must not own an independent command route")

local unaudited_strength = clone(document)
unaudited_strength._meta.type63_strength_variant_relations = nil
unaudited_strength._meta.type63_strength_variant_relation_count = nil
unaudited_strength._meta.type63_strength_variant_route_count = nil
unaudited_strength._meta.audit.type63_strength_variant_relation_count = nil
unaudited_strength._meta.audit.type63_strength_variant_route_count = nil
local unaudited_relations = Relations.parse(unaudited_strength, "Generic")
assert(unaudited_relations ~= nil
        and Relations.command_for_action(unaudited_relations, 21) == nil,
    "Classic display text without audited Type63 provenance must not become detection authority")

local invalid = Relations.parse({
    _meta = {
        schema = "xt.command_display.v1",
        strict_policy = "verified_action_graph_v1",
        generated_from = "ac_bcm",
        character = "Generic",
        ac_state_direction_route_count = 1,
        ac_state_direction_relations = {},
        audit = {
            ac_state_direction_relation_count = 1,
            ac_state_direction_route_count = 1,
        },
    },
}, "Generic")
assert(invalid == nil, "mismatched AC relation audits must fail closed")

local inconsistent = Relations.parse({
    _meta = {
        schema = "xt.command_display.v1",
        strict_policy = "verified_action_graph_v1",
        generated_from = "ac_bcm",
        character = "Generic",
        ac_state_direction_route_count = 1,
        internal_transition_suppression_count = 0,
        suppressed_internal_transitions = {},
        ac_state_direction_relations = {
            {
                reason = "ac_type20_multi_direction_state_choice",
                source_action_id = 10,
                source_action_ids = { 10, 11 },
            },
        },
        audit = {
            ac_state_direction_relation_count = 1,
            ac_state_direction_route_count = 1,
            internal_transition_suppression_count = 0,
        },
    },
    ["10"] = {
        classic_command = { display = "PP", inputs = { "PP" } },
        routes = { { source = "bcm_profile", direct_evidence = true, owner_action_id = 10 } },
    },
    ["11"] = {
        classic_command = { display = "KK", inputs = { "KK" } },
        routes = { { source = "bcm_profile", direct_evidence = true, owner_action_id = 11 } },
    },
}, "Generic")
assert(inconsistent ~= nil
        and Relations.command_for_action(inconsistent, 10) == "PP"
        and Relations.command_for_action(inconsistent, 11) == "KK"
        and not Relations.share_source_group(inconsistent, 10, 11),
    "an inconsistent AC group must be skipped without discarding direct BCM commands")

local community = Relations.parse({
    _meta = {
        schema = "xt.command_display.v1",
        strict_policy = "verified_action_graph_v1",
        generated_from = "ac_bcm+community_verified_semantics",
        character = "Generic",
        ac_state_direction_route_count = 0,
        ac_state_direction_relations = {},
        audit = {
            ac_state_direction_relation_count = 0,
            ac_state_direction_route_count = 0,
        },
    },
}, "Generic")
assert(community == nil,
    "community-enriched command catalogs must not become detection authority")

print("generated action relations tests passed")
