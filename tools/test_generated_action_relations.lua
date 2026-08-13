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
}

local relations, count, status = Relations.parse(document, "Generic")
assert(status == "loaded" and count == 1)
assert(Relations.command_for_action(relations, 9) == "HP")
assert(Relations.share_source_group(relations, 10, 11))
assert(Relations.share_source_group(relations, 11, 12))
assert(not Relations.share_source_group(relations, 9, 10))

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
