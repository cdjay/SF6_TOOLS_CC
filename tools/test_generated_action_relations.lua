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
        type20_action_phase_route_count = 1,
        type20_action_phase_relations = {
            {
                source_action_id = 900,
                target_action_id = 901,
                signatures = {
                    { param00 = 0, param01 = 8, param02 = 0, param03 = 1 },
                    { param00 = 0, param01 = 32, param02 = 0, param03 = 2 },
                    { param00 = 0, param01 = 8192, param02 = 0, param03 = 3 },
                    { param00 = 1, param01 = 8192, param02 = 0, param03 = 3 },
                },
                branch_type = 20,
                reason = "ac_type20_verified_multi_input_action_phase",
            },
        },
        internal_transition_suppression_count = 5,
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
            {
                kind = "ac_type37_automatic_execution_phase",
                source_action_id = 939,
                target_action_id = 943,
                tail_action_id = 944,
                branch_type = 37,
                action_frames = { 0, 10 },
                exit_branch_type = 12,
                exit_param01 = 4,
                exit_param02 = 190,
                fingerprint_fields = {
                    "Category", "Combo", "Projectile", "State",
                },
                reason = "ac_type37_unique_automatic_execution_phase",
            },
            {
                kind = "ac_type13_terminal_execution_phase",
                source_action_ids = { 940, 941, 942, 943 },
                target_action_id = 944,
                branch_type = 13,
                attr = 0,
                action_frame = 0,
                param00 = 0,
                param01 = 0,
                param02 = 0,
                param03 = 0,
                param04 = 0,
                param05 = 0,
                trigger_id = -1,
                reason = "ac_type13_zero_parameter_multi_owner_terminal_execution_phase",
            },
            {
                kind = "ac_type13_air_landing_execution_phase",
                source_action_ids = { 950, 951 },
                auxiliary_source_action_ids = { 958, 959 },
                target_action_id = 952,
                exit_target_action_id = 6,
                branch_type = 13,
                attr = 0,
                action_frame = 0,
                param00 = 1,
                param01 = 0,
                param02 = 0,
                param03 = 0,
                param04 = 0,
                param05 = 0,
                trigger_id = -1,
                exit_branch_type = 20,
                exit_attr = 0,
                exit_action_frame = 0,
                exit_param00 = 0,
                exit_param01 = 2,
                exit_param02 = 0,
                exit_param03 = 0,
                exit_param04 = 0,
                exit_param05 = 0,
                exit_trigger_id = -1,
                auxiliary_branches = {
                    {
                        branch_type = 5,
                        attr = 256,
                        action_frame = 0,
                        param00 = 0,
                        param01 = 0,
                        param02 = 0,
                        param03 = 0,
                        param04 = 0,
                        param05 = 0,
                        trigger_id = -1,
                    },
                    {
                        branch_type = 54,
                        attr = 256,
                        action_frame = 0,
                        param00 = 160,
                        param01 = 0,
                        param02 = 0,
                        param03 = 0,
                        param04 = 0,
                        param05 = 0,
                        trigger_id = -1,
                    },
                },
                reason = "ac_type13_multi_owner_air_landing_execution_phase",
            },
            {
                kind = "ac_type36_type13_execution_phase",
                source_action_id = 1023,
                target_action_id = 1024,
                tail_action_id = 1025,
                branch_type = 36,
                exit_branch_type = 13,
                attr = 0,
                action_frame = 0,
                param00 = 0,
                param01 = 0,
                param02 = 0,
                param03 = 0,
                param04 = 0,
                param05 = 0,
                trigger_id = -1,
                reason = "ac_type36_zero_parameter_phase_with_type13_terminal_exit",
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
            type20_action_phase_relation_count = 1,
            type20_action_phase_route_count = 1,
            internal_transition_suppression_count = 5,
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
    ["900"] = {
        ownership = "direct",
        classic_command = { display = "236+K", inputs = { "236+K" } },
        routes = { {
            source = "bcm_profile", direct_evidence = true, owner_action_id = 900,
            trigger_index = 80, profile = "sprt", command_no = 0, command_index = 1,
            raw_direction_inputs = { 2, 3, 6 }, raw_button_mask = 8,
            raw_button_condition = 81952, raw_dc_exc_flags = 0, raw_ng_key_flags = 0,
        } },
    },
    ["901"] = {
        ownership = "type20_action_phase",
        classic_command = { display = "236+K", inputs = { "236+K" } },
        routes = { {
            source = "ac_type20_action_phase",
            owner_action_id = 900,
            bcm_owner_action_id = 900,
            inherited_from_action_id = 900,
            display_action_id = 901,
            ac_relation_type = 20,
            ac_path = { 900, 901 },
            ac_phase_signatures = {
                { param00 = 0, param01 = 8, param02 = 0, param03 = 1 },
                { param00 = 0, param01 = 32, param02 = 0, param03 = 2 },
                { param00 = 0, param01 = 8192, param02 = 0, param03 = 3 },
                { param00 = 1, param01 = 8192, param02 = 0, param03 = 3 },
            },
            direct_evidence = false,
            inheritance_evidence = true,
            inheritance_reason = "ac_type20_verified_multi_input_action_phase",
            confidence = "verified_inherited_action_phase",
        } },
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
    ["943"] = {
        ownership = "internal_execution_phase",
        suppress_display = true,
        transition_evidence = {
            kind = "ac_type37_automatic_execution_phase",
            source_action_id = 939,
            target_action_id = 943,
            tail_action_id = 944,
            branch_type = 37,
            action_frames = { 0, 10 },
            exit_branch_type = 12,
            exit_param01 = 4,
            exit_param02 = 190,
            fingerprint_fields = {
                "Category", "Combo", "Projectile", "State",
            },
            reason = "ac_type37_unique_automatic_execution_phase",
        },
        routes = {},
    },
    ["944"] = {
        ownership = "internal_execution_phase",
        suppress_display = true,
        transition_evidence = {
            kind = "ac_type13_terminal_execution_phase",
            source_action_ids = { 940, 941, 942, 943 },
            target_action_id = 944,
            branch_type = 13,
            attr = 0,
            action_frame = 0,
            param00 = 0,
            param01 = 0,
            param02 = 0,
            param03 = 0,
            param04 = 0,
            param05 = 0,
            trigger_id = -1,
            reason = "ac_type13_zero_parameter_multi_owner_terminal_execution_phase",
        },
        routes = {},
    },
    ["952"] = {
        ownership = "internal_execution_phase",
        suppress_display = true,
        transition_evidence = {
            kind = "ac_type13_air_landing_execution_phase",
            source_action_ids = { 950, 951 },
            auxiliary_source_action_ids = { 958, 959 },
            target_action_id = 952,
            exit_target_action_id = 6,
            branch_type = 13,
            attr = 0,
            action_frame = 0,
            param00 = 1,
            param01 = 0,
            param02 = 0,
            param03 = 0,
            param04 = 0,
            param05 = 0,
            trigger_id = -1,
            exit_branch_type = 20,
            exit_attr = 0,
            exit_action_frame = 0,
            exit_param00 = 0,
            exit_param01 = 2,
            exit_param02 = 0,
            exit_param03 = 0,
            exit_param04 = 0,
            exit_param05 = 0,
            exit_trigger_id = -1,
            auxiliary_branches = {
                {
                    branch_type = 5,
                    attr = 256,
                    action_frame = 0,
                    param00 = 0,
                    param01 = 0,
                    param02 = 0,
                    param03 = 0,
                    param04 = 0,
                    param05 = 0,
                    trigger_id = -1,
                },
                {
                    branch_type = 54,
                    attr = 256,
                    action_frame = 0,
                    param00 = 160,
                    param01 = 0,
                    param02 = 0,
                    param03 = 0,
                    param04 = 0,
                    param05 = 0,
                    trigger_id = -1,
                },
            },
            reason = "ac_type13_multi_owner_air_landing_execution_phase",
        },
        routes = {},
    },
    ["1024"] = {
        ownership = "internal_execution_phase",
        suppress_display = true,
        transition_evidence = {
            kind = "ac_type36_type13_execution_phase",
            source_action_id = 1023,
            target_action_id = 1024,
            tail_action_id = 1025,
            branch_type = 36,
            exit_branch_type = 13,
            attr = 0,
            action_frame = 0,
            param00 = 0,
            param01 = 0,
            param02 = 0,
            param03 = 0,
            param04 = 0,
            param05 = 0,
            trigger_id = -1,
            reason = "ac_type36_zero_parameter_phase_with_type13_terminal_exit",
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
assert(Relations.is_internal_phase_of(relations, 939, 943),
    "audited Type37 automatic execution phases must retain their generated owner")
assert(Relations.is_internal_phase_of(relations, 940, 944)
        and Relations.is_internal_phase_of(relations, 943, 944),
    "multi-owner Type13 terminal phases must accept every audited direct owner")
assert(Relations.is_internal_phase_of(relations, 950, 952)
        and Relations.is_internal_phase_of(relations, 951, 952)
        and Relations.is_internal_phase_of(relations, 958, 952)
        and Relations.is_internal_phase_of(relations, 959, 952),
    "air-landing phases must retain direct and auxiliary generated owners")
assert(Relations.is_internal_phase_of(relations, 1023, 1024),
    "Type36 phases with a strict Type13 terminal exit must retain their owner")
assert(Relations.is_internal_phase_of(relations, 900, 901),
    "verified Type20 action phases must retain their direct BCM owner")
assert(Relations.is_command_owner_of(relations, 900, 901),
    "verified Type20 terminal phases must expose their direct BCM command owner")
assert(not Relations.is_command_owner_of(relations, 1062, 1063),
    "generic internal execution phases must not become command-owner aliases")
assert(not Relations.is_command_owner_of(relations, 901, 900),
    "Type20 command ownership must remain directional")
assert(not Relations.is_internal_phase_of(relations, 1063, 1062),
    "internal execution ownership must remain directional")

local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[clone(key)] = clone(child) end
    return result
end

local six_branch_phase = clone(document)
six_branch_phase._meta.type20_action_phase_relations[2] = {
    source_action_id = 686,
    target_action_id = 684,
    branch_type = 20,
    signatures = {
        { attr = 0, action_frame = 5, param00 = 0, param01 = 64, param02 = 0, param03 = 1 },
        { attr = 256, action_frame = 0, param00 = 2, param01 = 64, param02 = 0, param03 = 1 },
        { attr = 0, action_frame = 5, param00 = 0, param01 = 256, param02 = 0, param03 = 2 },
        { attr = 256, action_frame = 0, param00 = 2, param01 = 256, param02 = 0, param03 = 2 },
        { attr = 0, action_frame = 5, param00 = 0, param01 = 16, param02 = 0, param03 = 3 },
        { attr = 0, action_frame = 5, param00 = 1, param01 = 16, param02 = 0, param03 = 3 },
    },
    source_exit_signature = {
        target_action_id = 687, branch_type = 0, attr = 0, action_frame = 5,
        param00 = 0, param01 = 0, param02 = 0, param03 = 0,
        param04 = 0, param05 = 0, trigger_id = -1,
    },
    exit_signature = {
        target_action_id = 685, branch_type = 5, attr = 0, action_frame = 8,
        param00 = 1, param01 = 0, param02 = 0, param03 = 0,
        param04 = 0, param05 = 0, trigger_id = -1,
    },
    reason = "ac_type20_verified_six_branch_action_phase",
}
six_branch_phase._meta.type20_action_phase_route_count = 2
six_branch_phase._meta.audit.type20_action_phase_relation_count = 2
six_branch_phase._meta.audit.type20_action_phase_route_count = 2
six_branch_phase["686"] = {
    ownership = "direct",
    classic_command = { display = "4+HP", inputs = { "4+HP" } },
    motion_command = { display = "4 + 强", inputs = { "4 + 强" } },
    routes = { { source = "bcm_profile", direct_evidence = true, owner_action_id = 686 } },
}
six_branch_phase["684"] = {
    ownership = "type20_action_phase",
    classic_command = { display = "4+HP", inputs = { "4+HP" } },
    motion_command = { display = "4 + 强", inputs = { "4 + 强" } },
    routes = { {
        source = "ac_type20_six_branch_action_phase",
        owner_action_id = 686,
        bcm_owner_action_id = 686,
        inherited_from_action_id = 686,
        display_action_id = 684,
        ac_relation_type = 20,
        ac_path = { 686, 684 },
        ac_phase_signatures = clone(six_branch_phase._meta.type20_action_phase_relations[2].signatures),
        ac_source_exit_signature = clone(
            six_branch_phase._meta.type20_action_phase_relations[2].source_exit_signature),
        ac_exit_signature = clone(
            six_branch_phase._meta.type20_action_phase_relations[2].exit_signature),
        direct_evidence = false,
        inheritance_evidence = true,
        inheritance_reason = "ac_type20_verified_six_branch_action_phase",
        confidence = "verified_inherited_action_phase",
    } },
}
local six_branch_relations = Relations.parse(six_branch_phase, "Generic")
assert(six_branch_relations ~= nil
        and Relations.is_internal_phase_of(six_branch_relations, 686, 684)
        and Relations.is_command_owner_of(six_branch_relations, 686, 684),
    "strict six-branch Type20 action phases must share the generated command owner")

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
mismatched_internal_audit._meta.audit.internal_transition_suppression_count = 1
assert(Relations.parse(mismatched_internal_audit, "Generic") == nil,
    "internal execution phases must match the generated audit count")

local malformed_type37_phase = clone(document)
malformed_type37_phase._meta.suppressed_internal_transitions[2].action_frames[2] = 0
malformed_type37_phase["943"].transition_evidence.action_frames[2] = 0
assert(Relations.parse(malformed_type37_phase, "Generic") == nil,
    "malformed Type37 automatic execution evidence must fail closed")

local malformed_type13_owners = clone(document)
malformed_type13_owners._meta.suppressed_internal_transitions[3].source_action_ids = {
    940, 943, 942,
}
malformed_type13_owners["944"].transition_evidence.source_action_ids = { 940, 943, 942 }
assert(Relations.parse(malformed_type13_owners, "Generic") == nil,
    "multi-owner internal phases must use a unique sorted owner set")

local malformed_air_landing_auxiliary = clone(document)
malformed_air_landing_auxiliary._meta.suppressed_internal_transitions[4]
    .auxiliary_branches[2].param00 = 159
malformed_air_landing_auxiliary["952"].transition_evidence
    .auxiliary_branches[2].param00 = 159
assert(Relations.parse(malformed_air_landing_auxiliary, "Generic") == nil,
    "air-landing phases must require the exact paired Type5/54 auxiliary shape")

local malformed_air_landing_owners = clone(document)
malformed_air_landing_owners._meta.suppressed_internal_transitions[4]
    .auxiliary_source_action_ids = { 959, 958 }
malformed_air_landing_owners["952"].transition_evidence
    .auxiliary_source_action_ids = { 959, 958 }
assert(Relations.parse(malformed_air_landing_owners, "Generic") == nil,
    "air-landing auxiliary owners must be unique and sorted")

local malformed_type36_exit = clone(document)
malformed_type36_exit._meta.suppressed_internal_transitions[5].exit_branch_type = 20
malformed_type36_exit["1024"].transition_evidence.exit_branch_type = 20
assert(Relations.parse(malformed_type36_exit, "Generic") == nil,
    "Type36 internal phases without the exact Type13 terminal exit must fail closed")

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

local malformed_type20_signature = clone(document)
malformed_type20_signature._meta.type20_action_phase_relations[1]
    .signatures[4].param03 = 2
assert(Relations.parse(malformed_type20_signature, "Generic") == nil,
    "Type20 action phases must retain the complete generated signature family")

local mismatched_type20_owner = clone(document)
mismatched_type20_owner["901"].routes[1].inherited_from_action_id = 903
assert(Relations.parse(mismatched_type20_owner, "Generic") == nil,
    "Type20 action phases must retain the exact direct BCM owner")

local mismatched_type20_audit = clone(document)
mismatched_type20_audit._meta.audit.type20_action_phase_route_count = 2
assert(Relations.parse(mismatched_type20_audit, "Generic") == nil,
    "Type20 action-phase routes must match the generated audit count")

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
