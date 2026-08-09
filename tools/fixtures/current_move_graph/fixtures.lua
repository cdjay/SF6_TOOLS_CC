-- Lua mirror of the current_move_graph JSON fixtures, shaped exactly like
-- REFramework json.load_string() output (JSON null becomes an absent key).
-- Tests dispatch decode to this mirror so the loader is exercised without a
-- JSON parser; the canonical bytes remain the .json files in this directory.
-- The runtime_current sha256/bytes in the manifest mirror are re-pinned to
-- the real fixture bytes by the test harness before each load.

local BUILD_UID = "sf6b_c0269f7351fc73e06633b780"

local source = {
    m2_graph_file_sha256 = "eac036e86a7ee88f43b09df7a13de7c6b915bf16f6c785217c2e285e34f0f3de",
    m2_graph_canonical_sha256 = "0cefaa96ce82ab472cd98e1ec7e4cff6eb13ee3754bf4522a73f6c4137e1629d",
    m4_index_sha256 = "7b95f8250bbb708ced408cf4481351fcca8296190eee10ebd3c2bd93793886a4",
    ledger_sha256 = "4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945",
}

local function evidence(family_uids, relationship_uids)
    return {
        candidate_uids = {},
        extension_uids = {},
        family_uids = family_uids,
        reasons = {},
        relationship_uids = relationship_uids or {},
    }
end

local function membership(move_uid, action_id, role, family_uids, relationship_uids)
    return {
        build_uid = BUILD_UID,
        move_uid = move_uid,
        action_id = action_id,
        role = role,
        strictness = "STRICT",
        evidence = evidence(family_uids, relationship_uids),
    }
end

local function command(profile_name, enabled, notation, route)
    return {
        profile_name = profile_name,
        enabled = enabled,
        normalized_notation = notation,
        anchor_route_uid = route,
    }
end

local function disabled_commands(route)
    return {
        command("easy", false, "Normal", route),
        command("norm", false, "Normal", route),
        command("supr", false, "Normal", route),
        command("sprt", false, "Normal", route),
    }
end

local function anchor(route, trigger_index, owner_action_id, condition_hash,
    has_enabled_profile, resource_gated, availability)
    return {
        anchor_route_uid = route,
        trigger_index = trigger_index,
        owner_action_id = owner_action_id,
        condition_hash = condition_hash,
        has_enabled_profile = has_enabled_profile,
        charge_command = false,
        resource_gated = resource_gated,
        state_gated = false,
        control_mode_availability = availability,
    }
end

local function move(current_move_uid, revision_uid, fingerprint, owner_action_ids,
    anchors, commands, memberships, extra)
    local result = {
        current_move_uid = current_move_uid,
        provisional = true,
        revision_uid = revision_uid,
        fingerprint = fingerprint,
        duplicate_owners = false,
        disabled_only = false,
        owner_action_ids = owner_action_ids,
        anchors = anchors,
        commands = commands,
        memberships = memberships,
    }
    if extra then
        for key, value in pairs(extra) do result[key] = value end
    end
    return result
end

local honda965_route = "m1route_cdbc59478b1fb11973bd8014"
local honda965 = move(
    "m2move_6c92dae21a5e22f63d2bfc7f",
    "m2rev_3ac10406c9e8bf0d477121a9",
    "dc26b5a57cfc9f8f20b331d1712f99ddd3cb7fe886a6c43a5e89af680eb9990e",
    { 965 },
    { anchor(honda965_route, 83, 965,
        "5a1d0f7edea335d31ff4bfe4e15165ce5739d4ae838f0d3eb212a6720beba6f4",
        true, false, "classic_and_modern") },
    {
        command("easy", false, "Normal", honda965_route),
        command("supr", true, "2", honda965_route),
        command("norm", true, "2+P", honda965_route),
        command("sprt", true, "2+LP+MP+LK+MK", honda965_route),
    },
    { membership("m2move_6c92dae21a5e22f63d2bfc7f", 965, "primary",
        { "m1fam_d9d42c0d1bf0865ffe29357e" }) }
)

local honda961_route = "m1route_c4d7a2b6bbd3c14f26dced5c"
local honda961 = move(
    "m2move_adb56dc91f9b6663c6f61548",
    "m2rev_071083db53838af221b9f9c7",
    "ad95ade76ae585ba005513297b131c8ae1fddde443563aa4d7d2b657d4bfed75",
    { 961 },
    { anchor(honda961_route, 167, 961,
        "05b63391fa0baefd26304c7484afb4caa0f0eecd8a2da92c3a713627f667c593",
        false, true, "no_enabled_profile") },
    disabled_commands(honda961_route),
    { membership("m2move_adb56dc91f9b6663c6f61548", 961, "primary",
        { "m1fam_b48b3e2ab6e4f2494ab0d189" }) },
    { disabled_only = true }
)

local honda976_route = "m1route_a8cdcde7d8b28afd4f9cec75"
local honda976 = move(
    "m2move_0f36af1e59e2836967557403",
    "m2rev_6b83e2480b45445c53312838",
    "034c6f5e6fc46c1ddcb7d10fb0febc47e8f6706be91fba62013179065d7e834f",
    { 976 },
    { anchor(honda976_route, 49, 976,
        "d9ed97953115e8e81e00db9c92225279764732e9d1c267f22436a0b5bfb100d3",
        true, false, "classic_and_modern") },
    {
        command("supr", false, "Normal", honda976_route),
        command("easy", false, "Normal", honda976_route),
        command("norm", true, "2+HK", honda976_route),
        command("sprt", true, "2+LK", honda976_route),
    },
    {
        membership("m2move_0f36af1e59e2836967557403", 976, "primary",
            { "m1fam_8d4c8193c165aa379c45b4f8" }),
        membership("m2move_0f36af1e59e2836967557403", 977, "replacement",
            {}, { "m1rel_8b9f66eec59c44cda0eceb9d" }),
    }
)

local gief900_route = "m1route_a2a0871e485498a027460561"
local gief900 = move(
    "m2move_4d0ae239087cf32fa91e300a",
    "m2rev_fb16ce8510d78c9605c9cd99",
    "13d67a08078cb5348052e610e4ca8c7766a3ffcdc713facbd8b3bcbf68b9eb9a",
    { 900 },
    { anchor(gief900_route, 115, 900,
        "f19b46bb969cf052be0b6e04baca5146a3bfef1bb5f601d75c3020d2ae831ae6",
        true, true, "modern_only") },
    {
        command("sprt", true, "LK+MK", gief900_route),
        command("supr", false, "Normal", gief900_route),
        command("easy", false, "Normal", gief900_route),
        command("norm", false, "Normal", gief900_route),
    },
    { membership("m2move_4d0ae239087cf32fa91e300a", 900, "primary",
        { "m1fam_745f1b01d990f91de3a1f8b9" }) }
)

local gief_dbl_route_a = "m1route_3dfd46fd77985d5024a63983"
local gief_dbl_route_b = "m1route_9d464bb786a2853f119d40d4"
local gief_dbl_hash = "c81fdb3afcf36564da0fe4620d7abf2b01d33c23b89474f5bd07e92754dca4a2"
local gief_double = move(
    "m2move_6f6007b8f44f01b2b5339ab2",
    "m2rev_e5c44d50b80e39cd82608cd8",
    "0ddeacc308dd3294564ea647290dff5829604caf31f3853c4a3441fc4054944e",
    { 900, 903 },
    {
        anchor(gief_dbl_route_a, 79, 900, gief_dbl_hash, true, false, "classic_and_modern"),
        anchor(gief_dbl_route_b, 80, 903, gief_dbl_hash, true, false, "classic_and_modern"),
    },
    {
        command("supr", true, "2", gief_dbl_route_b),
        command("easy", true, "2+MP", gief_dbl_route_b),
        command("norm", true, "PP", gief_dbl_route_b),
        command("sprt", true, "LK+MK", gief_dbl_route_b),
        command("supr", true, "2", gief_dbl_route_a),
        command("easy", true, "2+MP", gief_dbl_route_a),
        command("norm", true, "PP", gief_dbl_route_a),
        command("sprt", true, "LK+MK", gief_dbl_route_a),
    },
    {
        membership("m2move_6f6007b8f44f01b2b5339ab2", 900, "primary",
            { "m1fam_5678133a076216cf03d91414" }),
        membership("m2move_6f6007b8f44f01b2b5339ab2", 903, "primary",
            { "m1fam_5678133a076216cf03d91414" }),
    },
    { duplicate_owners = true }
)

local ed_from_route = "m1route_6e589f7af481edcb4749d07b"
local ed_from = move(
    "m2move_1052594b4f203eed8dce1672",
    "m2rev_e133c81117e71e2a150fa20e",
    "ac079d5722187d2f79a6653e59dc29a2b5cafa48969ca719923dee4570b6c72f",
    { 988 },
    { anchor(ed_from_route, 91, 988,
        "f9604e200c952f203ff2295bc9b59ac19f776c885e6d55acf6841b9299ed1022",
        true, false, "classic_and_modern") },
    {
        command("easy", false, "Normal", ed_from_route),
        command("sprt", true, "LP+LK+MK", ed_from_route),
        command("supr", false, "Normal", ed_from_route),
        command("norm", true, "KK", ed_from_route),
    },
    { membership("m2move_1052594b4f203eed8dce1672", 988, "primary",
        { "m1fam_979d6df446d9230de3b1bc35" }) }
)

local ed_to_route = "m1route_b0d8803860594876f1fd9541"
local ed_to = move(
    "m2move_097e7341cf954d4bbb754fab",
    "m2rev_50d3ab4ae5de81456c0452bd",
    "0dcc39eb3d9c5f35b92212c2f2192cfa8b4a5d0fa14f8140b4466a9c6b7bdb0c",
    { 993 },
    { anchor(ed_to_route, 90, 993,
        "cae09f678a05b6d028c0bbdafd6136b665881e80122dfc266ee42fb65422b984",
        true, false, "classic_and_modern") },
    {
        command("norm", true, "44", ed_to_route),
        command("sprt", true, "44", ed_to_route),
        command("supr", false, "Normal", ed_to_route),
        command("easy", false, "Normal", ed_to_route),
    },
    { membership("m2move_097e7341cf954d4bbb754fab", 993, "primary",
        { "m1fam_d6fbfd7da4384e616b78aa81" }) }
)

local runtime = {
    schema = "sf6acbcm.runtime-current.v1",
    algorithm_version = "m5-export.v1",
    authority = "current_semantic_candidate_only",
    auto_approved = false,
    build = { build_uid = BUILD_UID, display_version = "2026-08-03" },
    source = source,
    unresolved_diagnostics = {
        {
            diagnostic_uid = "m2unr_0b5437660b904d001d22097b",
            diagnostic_kind = "row",
            fighter_id = 19,
            character = "Ed",
            source_action_id = 417,
            target_action_id = 422,
            detail = {
                candidate_uids = { "m1cand_de76775124b18572d153efab" },
                predicate = "t17_exact_rebind",
                reasons = { "param01_mismatch:expected_120_got_220", "source_member_unresolved" },
                relationship_uids = {},
                row_kind = "candidate",
            },
            review = {
                status = "pending",
                evidence_refs = {},
            },
        },
        {
            diagnostic_uid = "m2tr_02c87eca6d5f7c17f61e1af9",
            diagnostic_kind = "transition",
            fighter_id = 3,
            character = "Kimberly",
            source_action_id = 902,
            target_action_id = 906,
            detail = {
                evidence = {
                    branch_types = { 0 },
                    candidate_uids = {},
                    raw_edge_uids = { "edge_61d1382df0535b6bf2fc05e6" },
                    reasons = {
                        "anchored_to_anchored_raw_ac_pair_not_accepted_by_m1",
                        "family_resolution_not_exact_1x1",
                    },
                    source_family_uids = { "m1fam_275132d9651009311c193791" },
                    target_family_uids = {
                        "m1fam_446e35cf2bdf82800861dedb",
                        "m1fam_e28f894c5d6f092ba56569b2",
                        "m1fam_eca6192b2b5fb34474bc3bc4",
                    },
                },
                kind = "boundary_diagnostic",
                strictness = "UNRESOLVED",
            },
            review = {
                status = "pending",
                evidence_refs = {},
            },
        },
    },
    characters = {
        {
            fighter_id = 20,
            character = "EHonda",
            moves = { honda965, honda961, honda976 },
            transitions = {},
        },
        {
            fighter_id = 6,
            character = "Zangief",
            moves = { gief900, gief_double },
            transitions = {},
        },
        {
            fighter_id = 19,
            character = "Ed",
            moves = { ed_from, ed_to },
            transitions = {
                {
                    transition_uid = "m2tr_07194177839275b8f4bd537e",
                    kind = "followup",
                    strictness = "STRICT",
                    from_move_uid = "m2move_1052594b4f203eed8dce1672",
                    to_move_uid = "m2move_097e7341cf954d4bbb754fab",
                    source_action_id = 988,
                    target_action_id = 993,
                    evidence = {
                        branch_types = { 63 },
                        candidate_uids = { "m1cand_d85533495f15ba5d1b52b0f5" },
                        raw_edge_uids = { "edge_f0a842c77883ff48822b71e2" },
                        reasons = { "target_independently_anchored" },
                        source_family_uids = { "m1fam_979d6df446d9230de3b1bc35" },
                        target_family_uids = { "m1fam_d6fbfd7da4384e616b78aa81" },
                    },
                },
            },
        },
        {
            fighter_id = 2,
            character = "Luke",
            moves = {},
            transitions = {
                {
                    transition_uid = "m2tr_54b3c09e2a1340bb3cd5b556",
                    kind = "boundary_diagnostic",
                    strictness = "UNRESOLVED",
                    source_action_id = 1215,
                    target_action_id = 1215,
                    evidence = {
                        branch_types = { 25 },
                        candidate_uids = {},
                        raw_edge_uids = { "edge_4b9f20714896731d1698039d" },
                        reasons = {
                            "anchored_to_anchored_raw_ac_pair_not_accepted_by_m1",
                            "family_resolution_not_exact_1x1",
                        },
                        source_family_uids = {
                            "m1fam_3e4cb7f55fb251d3166ce624",
                            "m1fam_ead6f4f91c5c35f76750f710",
                        },
                        target_family_uids = {
                            "m1fam_3e4cb7f55fb251d3166ce624",
                            "m1fam_ead6f4f91c5c35f76750f710",
                        },
                    },
                },
            },
        },
    },
}

local manifest = {
    schema = "sf6acbcm.m5-export-manifest.v1",
    algorithm_version = "m5-export.v1",
    authority = "current_semantic_candidate_only",
    auto_approved = false,
    build = { build_uid = BUILD_UID, display_version = "2026-08-03" },
    source = source,
    artifacts = {
        runtime_current = {
            file = "runtime-current.v1.json",
            sha256 = "5da28017acb9be992ca7c7f1eee3e9e5659acef80700403e21dfcf49f1a0bc45",
            bytes = 21581,
        },
        public_catalog_current = {
            file = "public-catalog-current.v1.json",
            sha256 = "c4b753a4f0775b219f2ce4fc190b72f5ffa353ef69b5816b45021f6ed83c7318",
            bytes = 2453105,
        },
        legacy_projections = {
            file = "legacy-projections-current.v1.json",
            sha256 = "3ae3442c1dfc2dc88a9616790c2c9be18ea4038b41eab621743417c01f455307",
            bytes = 375,
        },
    },
    character_coverage = { expected = 4, generated = 4, failed = {} },
    unresolved = {
        migration_links = 0,
        memberships = 0,
        rows = 1,
        extensions = 0,
        transitions = 1,
    },
    review_pending = {
        migration_links = 0,
        memberships = 0,
        rows = 1,
        extensions = 0,
        transitions = 1,
    },
    approval_coverage = {
        moves = 7,
        stable_identities = 0,
        provisional = 7,
        decisions = 0,
        active_decisions = 0,
        approved_migration_links = 0,
    },
    provenance_summary = {
        current_only = true,
        raw_workspace_read_only = true,
        m4_index_query_only = true,
        legacy_projection_separate = true,
    },
    ready = {
        artifact_set = true,
        review_complete = false,
        integration_candidate = false,
    },
}

return { runtime = runtime, manifest = manifest }
