package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local Relations = require("func/ComboTrials/GeneratedActionRelations")

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
}

local relations, count, status = Relations.parse(document, "Generic")
assert(status == "loaded" and count == 1)
assert(Relations.command_for_action(relations, 9) == "HP")
assert(Relations.command_for_action(relations, 21) == "6+MP")
assert(Relations.share_source_group(relations, 10, 11))
assert(Relations.share_source_group(relations, 11, 12))
assert(not Relations.share_source_group(relations, 9, 10))
assert(not Relations.share_source_group(relations, 20, 21),
    "strength variants are distinct Actions, not source-group aliases")

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
