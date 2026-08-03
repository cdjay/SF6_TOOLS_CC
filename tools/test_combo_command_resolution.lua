local function read_all(path)
    local file = assert(io.open(path, "rb"))
    local value = assert(file:read("*a"))
    file:close()
    return value:gsub("\r\n", "\n")
end

local command_resolver = dofile("autorun/func/ComboTrials/CommandResolver.lua")
local command_display_overrides =
    dofile("autorun/func/ComboTrials/CommandDisplayOverrides.lua")
CommandDisplayOverrides = command_display_overrides

local override_map = {
    _slim = true,
    ["958"] = { classic = "2+PP", status = "route_unverified" },
    ["959"] = { classic = "2+PP", status = "route_unverified" },
    ["967"] = { classic = ">6+P" },
}
local merged_overrides, applied_overrides, override_status =
    command_display_overrides.merge(override_map, "Alex", {
        schema = "xt.command_display_overrides.v1",
        character = "Alex",
        entries = {
            ["958"] = {
                classic = "2+PP",
                replace = true,
                evidence = "twenty-seven completed runtime events",
            },
            ["959"] = {
                classic = "2+PP",
                replace = true,
                evidence = "one runtime event before a later mismatch",
            },
            ["967"] = { classic = "bad replacement", evidence = "test" },
            ["968"] = { classic = ">6+MP", evidence = "three raw replays" },
            ["977"] = { classic = ">HP (INSTANT)", evidence = "five raw replays" },
            ["978"] = { classic = ">LK" },
        },
    })
assert(override_status == "loaded" and applied_overrides == 4
    and merged_overrides["958"].classic == "2+PP"
    and merged_overrides["959"].classic == "2+PP"
    and merged_overrides["958"].status == "runtime_verified_override"
    and merged_overrides["959"].status == "runtime_verified_override"
    and merged_overrides["958"].metadata.replaced_existing == true
    and merged_overrides["959"].metadata.replaced_existing == true
    and merged_overrides["967"].classic == ">6+P"
    and merged_overrides["968"].classic == ">6+MP"
    and merged_overrides["968"].status == "runtime_verified_override"
    and merged_overrides["977"].classic == ">HP (INSTANT)"
    and merged_overrides["978"] == nil,
    "verified command overrides must fill missing Actions without silently replacing catalog rows")
local ingrid_catalog = {
    _slim = true,
    ["609"] = { classic = "HP", status = "route_unverified" },
    ["622"] = { classic = "2+LP", status = "route_unverified" },
    ["1202"] = { classic = "236236+K", status = "route_unverified" },
    ["1219"] = { classic = "214214+MP", status = "route_unverified" },
    ["1229"] = { classic = "214214+HP", status = "route_unverified" },
}
local ingrid_overrides, ingrid_override_count, ingrid_override_status =
    command_display_overrides.merge(ingrid_catalog, "Ingrid", {
        schema = "xt.command_display_overrides.v1",
        character = "Ingrid",
        entries = {
            ["609"] = { classic = "HP", replace = true, evidence = "runtime audit" },
            ["622"] = { classic = "2+LP", replace = true, evidence = "runtime audit" },
            ["1202"] = { classic = "236236+K", replace = true, evidence = "runtime audit" },
            ["1219"] = { classic = "214214+MP", replace = true, evidence = "runtime audit" },
            ["1229"] = { classic = "214214+HP", replace = true, evidence = "runtime audit" },
        },
    })
assert(ingrid_override_status == "loaded" and ingrid_override_count == 5
        and ingrid_overrides["609"].classic == "HP"
        and ingrid_overrides["622"].classic == "2+LP"
        and ingrid_overrides["1202"].classic == "236236+K"
        and ingrid_overrides["1219"].classic == "214214+MP"
        and ingrid_overrides["1229"].classic == "214214+HP"
        and ingrid_overrides["609"].metadata.replaced_existing == true
        and ingrid_overrides["1229"].metadata.replaced_existing == true,
    "Ingrid's runtime-verified commands must replace route-unverified catalog rows")
local _, invalid_override_count, invalid_override_status =
    command_display_overrides.merge({ _slim = true }, "Alex", {
        schema = "xt.command_display_overrides.v1",
        character = "Ryu",
        entries = { ["968"] = { classic = ">6+MP", evidence = "test" } },
    })
assert(invalid_override_count == 0 and invalid_override_status == "invalid_override_document",
    "command overrides for another character must fail closed")
local cammy_overrides, cammy_override_count, cammy_override_status =
    command_display_overrides.merge({
        _slim = true,
        ["979"] = { classic = "j.Throw", status = "route_unverified" },
    }, "Cammy", {
        schema = "xt.command_display_overrides.v1",
        character = "Cammy",
        entries = {
            ["908"] = {
                classic = ">HK",
                evidence = "verified 4+MP follow-up HK",
            },
            ["979"] = {
                classic = "j.LP+LK",
                replace = true,
                evidence = "verified airborne LP+LK raw input",
            },
        },
    })
assert(cammy_override_status == "loaded" and cammy_override_count == 2
    and cammy_overrides["908"].classic == ">HK"
    and cammy_overrides["908"].status == "runtime_verified_override"
    and cammy_overrides["979"].classic == "j.LP+LK"
    and cammy_overrides["979"].status == "runtime_verified_override"
    and cammy_overrides["979"].metadata.replaced_existing == true,
    "Cammy's verified follow-up and air throw must resolve through data overrides")
local honda_overrides, honda_override_count, honda_override_status =
    command_display_overrides.merge({
        _slim = true,
        ["660"] = { classic = "3+HK", status = "route_unverified" },
    }, "EHonda", {
        schema = "xt.command_display_overrides.v1",
        character = "EHonda",
        entries = {
            ["660"] = {
                classic = "3+HK",
                replace = true,
                evidence = "verified directional HK runtime audit",
            },
        },
    })
assert(honda_override_status == "loaded" and honda_override_count == 1
        and honda_overrides["660"].classic == "3+HK"
        and honda_overrides["660"].status == "runtime_verified_override"
        and honda_overrides["660"].metadata.replaced_existing == true,
    "E. Honda's verified 3+HK must replace its unverified catalog row")
local aki_catalog = {
    _slim = true,
    ["623"] = { classic = "2+MP", status = "route_unverified" },
    ["672"] = { classic = "6+HP", status = "route_unverified" },
    ["955"] = { classic = "214+LK", status = "route_unverified" },
    ["957"] = { classic = "214+MK", status = "route_unverified" },
}
local aki_override_document = {
    schema = "xt.command_display_overrides.v1",
    character = "AKI",
    entries = {
        ["623"] = {
            classic = "2+MP",
            replace = true,
            evidence = "two verified raw-input replays",
        },
        ["672"] = {
            classic = "6+HP",
            replace = true,
            evidence = "one verified raw-input replay",
        },
        ["955"] = {
            classic = "214+LK",
            replace = true,
            evidence = "two verified raw-input replays",
        },
        ["957"] = {
            classic = "214+MK",
            replace = true,
            evidence = "three verified raw-input replays",
        },
    },
}
local aki_overrides, aki_override_count, aki_override_status =
    command_display_overrides.merge(aki_catalog, "AKI", aki_override_document)
assert(aki_override_status == "loaded" and aki_override_count == 4
        and aki_overrides["623"].classic == "2+MP"
        and aki_overrides["672"].classic == "6+HP"
        and aki_overrides["955"].classic == "214+LK"
        and aki_overrides["957"].classic == "214+MK"
        and aki_overrides["623"].status == "runtime_verified_override"
        and aki_overrides["672"].status == "runtime_verified_override"
        and aki_overrides["955"].status == "runtime_verified_override"
        and aki_overrides["957"].status == "runtime_verified_override",
    "AKI's verified Classic Actions must replace only their unverified catalog rows")
local lily_catalog = {
    _slim = true,
    ["600"] = { classic = "LP", status = "route_unverified" },
    ["612"] = { classic = "MK", status = "route_unverified" },
    ["651"] = { classic = "3+HP", status = "route_unverified" },
}
local lily_override_document = {
    schema = "xt.command_display_overrides.v1",
    character = "Lily",
    entries = {
        ["600"] = {
            classic = "LP",
            replace = true,
            evidence = "four verified raw-input runtime replays",
        },
        ["612"] = {
            classic = "MK",
            replace = true,
            evidence = "two verified raw-input runtime replays",
        },
        ["651"] = {
            classic = "3+HP",
            replace = true,
            evidence = "one verified facing-relative raw-input runtime replay",
        },
    },
}
local lily_overrides, lily_override_count, lily_override_status =
    command_display_overrides.merge(lily_catalog, "Lily", lily_override_document)
assert(lily_override_status == "loaded" and lily_override_count == 3
        and lily_overrides["600"].classic == "LP"
        and lily_overrides["612"].classic == "MK"
        and lily_overrides["651"].classic == "3+HP"
        and lily_overrides["600"].status == "runtime_verified_override"
        and lily_overrides["612"].status == "runtime_verified_override"
        and lily_overrides["651"].status == "runtime_verified_override",
    "Lily's verified Classic Actions must replace only their unverified catalog rows")
local juri_catalog = {
    _slim = true,
    ["600"] = { classic = "LP", status = "route_unverified" },
    ["612"] = { classic = "MK", status = "route_unverified" },
    ["665"] = { classic = "8", status = "route_unverified" },
}
local juri_override_document = {
    schema = "xt.command_display_overrides.v1",
    character = "Juri",
    entries = {
        ["600"] = {
            classic = "LP",
            replace = true,
            evidence = "two verified relative raw-input runtime replays",
        },
        ["612"] = {
            classic = "MK",
            replace = true,
            evidence = "one verified relative raw-input runtime replay",
        },
        ["613"] = {
            classic = "MK",
            replace = true,
            evidence = "five verified relative raw-input runtime replay events across four trials",
        },
        ["665"] = {
            classic = "8",
            replace = true,
            evidence = "verified relative raw-input runtime replays for the jump-start Action",
        },
    },
}
local juri_overrides, juri_override_count, juri_override_status =
    command_display_overrides.merge(juri_catalog, "Juri", juri_override_document)
assert(juri_override_status == "loaded" and juri_override_count == 4
        and juri_overrides["600"].classic == "LP"
        and juri_overrides["612"].classic == "MK"
        and juri_overrides["613"].classic == "MK"
        and juri_overrides["665"].classic == "8"
        and juri_overrides["600"].status == "runtime_verified_override"
        and juri_overrides["612"].status == "runtime_verified_override"
        and juri_overrides["613"].status == "runtime_verified_override"
        and juri_overrides["665"].status == "runtime_verified_override",
    "Juri's verified Classic Actions must fill missing rows and replace unverified catalog rows")
local mai_catalog = {
    _slim = true,
    ["600"] = { classic = "LP", status = "route_unverified" },
    ["603"] = { classic = "MP", status = "route_unverified" },
    ["907"] = { classic = "6", status = "route_unverified" },
}
local mai_override_document = {
    schema = "xt.command_display_overrides.v1",
    character = "Mai",
    entries = {
        ["600"] = {
            classic = "LP",
            replace = true,
            evidence = "twenty-two timeline runtime audit events",
        },
        ["603"] = {
            classic = "MP",
            replace = true,
            evidence = "one timeline runtime audit event with hit contact",
        },
        ["604"] = {
            classic = "HP",
            evidence = "thirty-six legacy Action 604 display failures with an explicit 604 to 605 alias",
        },
        ["605"] = {
            classic = "HP",
            evidence = "three post-update runtime audit events with hit contact",
        },
        ["907"] = {
            classic = ">6+MP",
            replace = true,
            evidence = "three relative-forward MP follow-up runtime audit events",
        },
    },
}
local mai_overrides, mai_override_count, mai_override_status =
    command_display_overrides.merge(mai_catalog, "Mai", mai_override_document)
assert(mai_override_status == "loaded" and mai_override_count == 5
        and mai_overrides["600"].classic == "LP"
        and mai_overrides["603"].classic == "MP"
        and mai_overrides["604"].classic == "HP"
        and mai_overrides["605"].classic == "HP"
        and mai_overrides["907"].classic == ">6+MP"
        and mai_overrides["600"].status == "runtime_verified_override"
        and mai_overrides["603"].status == "runtime_verified_override"
        and mai_overrides["604"].status == "runtime_verified_override"
        and mai_overrides["605"].status == "runtime_verified_override"
        and mai_overrides["907"].status == "runtime_verified_override"
        and mai_overrides["604"].metadata.replaced_existing == false
        and mai_overrides["605"].metadata.replaced_existing == false
        and mai_overrides["907"].metadata.replaced_existing == true,
    "Mai's runtime-audited Classic Actions must replace unverified catalog rows")
local sagat_catalog = {
    _slim = true,
    ["600"] = { classic = "LP", status = "route_unverified" },
    ["604"] = { classic = "MP", status = "route_unverified" },
}
local sagat_override_document = {
    schema = "xt.command_display_overrides.v1",
    character = "Sagat",
    entries = {
        ["600"] = {
            classic = "LP",
            replace = true,
            evidence = "one post-update runtime audit event with hit contact",
        },
        ["604"] = {
            classic = "MP",
            replace = true,
            evidence = "repeated post-update runtime audit events with hit contact",
        },
        ["954"] = {
            classic = "214+MK",
            replace = true,
            evidence = "five completed post-update runtime audit replays",
        },
    },
}
local sagat_overrides, sagat_override_count, sagat_override_status =
    command_display_overrides.merge(sagat_catalog, "Sagat", sagat_override_document)
assert(sagat_override_status == "loaded" and sagat_override_count == 3
        and sagat_overrides["600"].classic == "LP"
        and sagat_overrides["604"].classic == "MP"
        and sagat_overrides["954"].classic == "214+MK"
        and sagat_overrides["600"].status == "runtime_verified_override"
        and sagat_overrides["604"].status == "runtime_verified_override"
        and sagat_overrides["954"].status == "runtime_verified_override"
        and sagat_overrides["600"].metadata.replaced_existing == true
        and sagat_overrides["604"].metadata.replaced_existing == true
        and sagat_overrides["954"].metadata.replaced_existing == false,
    "Sagat's runtime-audited commands must replace or fill catalog rows")
local cviper_catalog = {
    _slim = true,
    ["608"] = { classic = "HK", status = "route_unverified" },
    ["1037"] = { classic = "528", status = "route_unverified" },
}
local cviper_override_document = {
    schema = "xt.command_display_overrides.v1",
    character = "CViper",
    entries = {
        ["608"] = {
            classic = "HK",
            replace = true,
            evidence = "three runtime audit hit events",
        },
        ["1037"] = {
            classic = "28",
            replace = true,
            evidence = "runtime-audited high-jump cancel",
        },
    },
}
local cviper_overrides, cviper_override_count, cviper_override_status =
    command_display_overrides.merge(cviper_catalog, "CViper", cviper_override_document)
assert(cviper_override_status == "loaded" and cviper_override_count == 2
        and cviper_overrides["608"].classic == "HK"
        and cviper_overrides["1037"].classic == "28"
        and cviper_overrides["608"].status == "runtime_verified_override"
        and cviper_overrides["1037"].status == "runtime_verified_override"
        and cviper_overrides["608"].metadata.replaced_existing == true
        and cviper_overrides["1037"].metadata.replaced_existing == true,
    "C. Viper's runtime-audited HK and high-jump Actions must replace unverified catalog rows")
local akuma_catalog = { _slim = true }
local akuma_override_document = {
    schema = "xt.command_display_overrides.v1",
    character = "Akuma",
    contextual_internal_phases = {
        ["908"] = {
            owner_ids = { 903.0 },
            evidence = "verified 903 to 908 runtime transition",
        },
        ["914"] = {
            owner_ids = { 904 },
            evidence = "verified 904 to 914 runtime transition",
        },
        ["948"] = {
            owner_ids = { 947, 952 },
            evidence = "verified air-command runtime transitions",
        },
        ["1010"] = {
            owner_ids = { 998, 999, 1000, 1005, 1006, 1007 },
            evidence = "verified Demon Raid runtime transitions",
        },
        ["1216"] = {
            owner_ids = { 1213, 1214 },
            evidence = "verified level-three runtime transitions",
        },
    },
    entries = {},
}
local akuma_classic_overrides = {
    ["622"] = "2+LP",
    ["627"] = "2+MP",
    ["661"] = "6+MP",
    ["975"] = "214+LP",
    ["977"] = "214+HP",
    ["982"] = "6+P",
    ["985"] = "6+P",
    ["991"] = "236+HK",
}
for action_id, classic in pairs(akuma_classic_overrides) do
    akuma_catalog[action_id] = {
        classic = classic,
        status = "route_unverified",
    }
    akuma_override_document.entries[action_id] = {
        classic = classic,
        replace = true,
        evidence = "verified Akuma relative raw-input replay",
    }
end
local akuma_overrides, akuma_override_count, akuma_override_status =
    command_display_overrides.merge(
        akuma_catalog,
        "Akuma",
        akuma_override_document
    )
assert(akuma_override_status == "loaded" and akuma_override_count == 8,
    "Akuma's eight verified Classic Actions must replace their unverified catalog rows")
for _, pair in ipairs({
    { 903, 908 },
    { 904, 914 },
    { 947, 948 },
    { 952, 948 },
    { 998, 1010 },
    { 999, 1010 },
    { 1000, 1010 },
    { 1005, 1010 },
    { 1006, 1010 },
    { 1007, 1010 },
    { 1213, 1216 },
    { 1214, 1216 },
}) do
    assert(command_display_overrides.is_contextual_internal_phase(
            akuma_overrides, pair[1], pair[2]) == true,
        "validated Akuma display metadata must preserve every exact owner-child pair")
end
assert(command_display_overrides.is_contextual_internal_phase(
        akuma_overrides, 997, 1010) == false
        and command_display_overrides.is_contextual_internal_phase(
            akuma_overrides, nil, 1010) == false,
    "contextual display metadata must reject missing and undeclared owners")
for action_id, classic in pairs(akuma_classic_overrides) do
    assert(akuma_overrides[action_id].classic == classic
            and akuma_overrides[action_id].commands == nil
            and akuma_overrides[action_id].status == "runtime_verified_override",
        "Akuma Classic overrides must resolve without inventing Modern commands")
end
for _, malformed_phases in ipairs({
    "908",
    {},
    { ["bad"] = { owner_ids = { 903 }, evidence = "test" } },
    { ["908"] = { owner_ids = {}, evidence = "test" } },
    { ["908"] = { owner_ids = { 908 }, evidence = "test" } },
    { ["908"] = { owner_ids = { 903.5 }, evidence = "test" } },
    { ["908"] = { owner_ids = { 903, 903 }, evidence = "test" } },
    { ["908"] = { owner_ids = { 903 } } },
}) do
    local malformed_map = {
        _slim = true,
        ["622"] = { classic = "catalog", status = "route_unverified" },
    }
    local merged, count, status = command_display_overrides.merge(
        malformed_map,
        "Akuma",
        {
            schema = "xt.command_display_overrides.v1",
            character = "Akuma",
            contextual_internal_phases = malformed_phases,
            entries = {
                ["622"] = {
                    classic = "2+LP",
                    replace = true,
                    evidence = "would otherwise apply",
                },
            },
        }
    )
    assert(status == "invalid_contextual_internal_phases"
            and count == 0
            and merged["622"].classic == "catalog"
            and command_display_overrides.is_contextual_internal_phase(
                merged, 903, 908) == false,
        "malformed contextual display metadata must fail closed without partial overrides")
end
local ryu_with_aki_overrides, ryu_aki_override_count, ryu_aki_override_status =
    command_display_overrides.merge({ _slim = true }, "Ryu", aki_override_document)
assert(ryu_aki_override_status == "invalid_override_document"
        and ryu_aki_override_count == 0
        and ryu_with_aki_overrides["623"] == nil,
    "AKI's replacement overrides must not be applicable to another character")
local elena_overrides, elena_override_count, elena_override_status =
    command_display_overrides.merge({ _slim = true }, "Elena", {
        schema = "xt.command_display_overrides.v1",
        character = "Elena",
        entries = {
            ["856"] = {
                classic = "DI",
                commands = { simple = "DI", motion = "DI" },
                evidence = "verified Elena raw-input replay",
            },
        },
    })
assert(elena_override_status == "loaded" and elena_override_count == 1
        and elena_overrides["856"].classic == "DI"
        and elena_overrides["856"].commands.simple == "DI"
        and elena_overrides["856"].commands.motion == "DI"
        and elena_overrides["856"].commands.all == "DI"
        and elena_overrides["856"].status == "runtime_verified_override",
    "Elena Action 856 must carry a verified classic/modern DI override")
local jamie_overrides, jamie_override_count, jamie_override_status =
    command_display_overrides.merge({ _slim = true }, "Jamie", {
        schema = "xt.command_display_overrides.v1",
        character = "Jamie",
        entries = {
            ["860"] = {
                classic = "DI",
                commands = { simple = "DI", motion = "DI" },
                evidence = "verified Jamie raw-input replay",
            },
        },
    })
assert(jamie_override_status == "loaded" and jamie_override_count == 1
        and jamie_overrides["860"].classic == "DI"
        and jamie_overrides["860"].commands.simple == "DI"
        and jamie_overrides["860"].commands.motion == "DI"
        and jamie_overrides["860"].status == "runtime_verified_override",
    "Jamie Action 860 must carry a verified classic/modern DI override")
local malformed_modern_override, malformed_modern_count =
    command_display_overrides.merge({ _slim = true }, "Elena", {
        schema = "xt.command_display_overrides.v1",
        character = "Elena",
        entries = {
            ["856"] = {
                classic = "DI",
                commands = { simple = "DI" },
                evidence = "incomplete modern declaration",
            },
        },
    })
assert(malformed_modern_count == 0 and malformed_modern_override["856"] == nil,
    "an incomplete modern override must fail closed instead of applying classic only")
-- Load only the pure resolver functions from the active ImGui renderer; do not
-- boot REFramework globals or exercise backend-specific drawing code.
local renderer_source = read_all("autorun/func/ComboTrials_ImGui.lua")
assert(not renderer_source:find("CharacterRules", 1, true),
    "command display must consume cached display metadata without a CharacterRules hot path")
assert(renderer_source:find("resolve_live_log_command_displays", 1, true)
        and renderer_source:find("oldest_source_index + 1", 1, true),
    "live display must resolve from one real predecessor before the visible window")
local classic_block = assert(renderer_source:match(
    "(local function get_player_visible_transition_motion.-)\nlocal function get_command_display"))
trim_string = function(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local semantic_block = assert(renderer_source:match(
    "(local function resolve_classic_common_semantic.-)\nbuild_slim_command_display_map = function"))
assert(load(semantic_block .. "\n_G.resolve_classic_common_semantic = resolve_classic_common_semantic",
    "classic-common-semantic", "t", _G))()

assert(load(classic_block .. "\n_G.get_classic_display_motion = get_classic_display_motion"
    .. "\n_G.get_modern_display_motion = get_modern_display_motion"
    .. "\n_G.get_player_visible_transition_motion = get_player_visible_transition_motion",
    "classic-command-resolution", "t", _G))()
local validation_block = assert(renderer_source:match(
    "(local function select_modern_display_motion.-)\nlocal function build_display_lines"
))
assert(load(validation_block
        .. "\n_G.resolve_step_command_display = resolve_step_command_display"
        .. "\n_G.resolve_contextual_step_command_display = resolve_contextual_step_command_display"
        .. "\n_G.resolve_live_log_command_displays = resolve_live_log_command_displays"
        .. "\n_G.validate_sequence_command_display = validate_sequence_command_display",
    "command-display-validation", "t", _G))()

local command_map = {
    _slim = true,
    ["901"] = { classic = "214+MP", status = "strict_route" },
    ["936"] = { classic = "PP", status = "strict_route" },
    ["906"] = { classic = "Normal", status = "suppress_transition" },
    ["1037"] = { classic = "528", status = "strict_route" }
}

local parry_entry = {
    routes = { { source = "bcm_common_semantic", display = "DP" } }
}
assert(resolve_classic_common_semantic(parry_entry, "Normal", "DP", "strict_route") == "PARRY",
    "audited common Drive Parry semantics must replace a stale classic Normal projection")
assert(resolve_classic_common_semantic({ routes = {} }, "Normal", "DP", "strict_route") == "Normal",
    "an unverified Normal action must not be rewritten")
assert(resolve_classic_common_semantic(parry_entry, "Normal", "DP", "suppress_transition") == "Normal",
    "an internal transition must retain its suppression semantics")
assert(resolve_classic_common_semantic(parry_entry, "MP+MK", "DP", "strict_route") == "MP+MK",
    "an explicit classic command must take precedence over semantic recovery")

local motion, status = get_classic_display_motion(command_map, { id = 901, motion = "Unknown" })
assert(motion == "214+MP" and status == "strict_route", "classic mode must use the unified command table")

motion, status = get_classic_display_motion(command_map, { id = 906, motion = "Unknown" })
assert(motion == nil and status == "suppress_transition",
    "an audited zero-input transition must remain suppressed")

motion, status = get_classic_display_motion(command_map, { id = 906, motion = ">K (FEINT)" })
assert(motion == ">K (FEINT)" and status == "player_input_transition",
    "saved player-triggered cancels must override zero-input suppression")

motion, status = get_classic_display_motion(command_map, { id = 1037, motion = ">29 (cancel)" })
assert(motion == ">29 (cancel)" and status == "recorded_context",
    "contextual trial notation must survive classic command resolution")

motion, status = get_classic_display_motion(command_map, { id = 936, motion = ">PP" })
assert(motion == ">PP" and status == "recorded_context",
    "a verified execution-phase action must retain its recorded follow-up notation")

RUNTIME_COMMON_ACTIONS = {}
TYPE37_FOLLOWUP_PHASE_REASON = "ac_type37_verified_followup_execution_phase"
local type37_route = {
    display = "SP",
    character = "Luke",
    owner_action_id = 935,
    display_action_id = 936,
    bcm_owner_action_id = 935,
    source = "ac_type37_followup_execution_phase",
    ac_relation_type = 37,
    ac_path = { 935, 936 },
    inherited_from_action_id = 935,
    confidence = "verified_inherited_followup_execution_phase",
    direct_evidence = false,
    inheritance_evidence = true,
    inheritance_reason = TYPE37_FOLLOWUP_PHASE_REASON,
    rebind_evidence = false,
    runtime_common_evidence = false,
    official_semantic_evidence = false,
    community_semantic_evidence = false,
    assist_combo_evidence = false,
    charge_context_evidence = false,
    super_shortcut_direction_evidence = false,
    ac_attr = 64,
    ac_action_frame = 0,
    ac_param00 = 0,
    ac_param01 = 0,
    ac_param02 = 0,
    ac_param03 = 0,
    ac_param04 = 0,
    ac_param05 = 0,
    ac_trigger_id = -1,
    official_followup_source_action_id = 933
}
local type37_map = {
    _meta = {
        character = "Luke",
        type37_followup_execution_phase_relations = {
            {
                source_action_id = 935,
                target_action_id = 936,
                branch_type = 37,
                attr = 64,
                action_frame = 0,
                param00 = 0,
                param01 = 0,
                param02 = 0,
                param03 = 0,
                param04 = 0,
                param05 = 0,
                trigger_id = -1,
                official_followup_source_action_id = 933,
                reason = TYPE37_FOLLOWUP_PHASE_REASON
            }
        }
    },
    ["936"] = {
        ownership = "type37_followup_execution_phase",
        routes = { type37_route }
    }
}
motion, status = get_modern_display_motion(type37_map, { id = 936 })
assert(motion == "SP" and status == "strict_route",
    "the runtime must admit a fully audited Type37 follow-up execution phase")
type37_route.ac_attr = 0
motion, status = get_modern_display_motion(type37_map, { id = 936 })
assert(motion == nil and status == "route_unverified",
    "the runtime must reject a Type37 phase whose AC signature was altered")
type37_route.ac_attr = 64

motion, status = get_classic_display_motion(command_map, { id = 9999, motion = "Unknown" })
assert(motion == nil and status == "action_id_missing", "missing classic IDs must reach the common audit path")

motion, status = get_classic_display_motion(command_map, { id = 854, motion = "DI" })
assert(motion == "DI" and status == "recorded_universal_command",
    "an unmapped character-specific Drive Impact phase must retain the universal DI command")

motion, status = get_classic_display_motion(command_map, { id = 9999, motion = "DI" })
assert(motion == nil and status == "action_id_missing",
    "arbitrary unmapped Actions must not impersonate Drive Impact through saved motion text")
motion, status = get_modern_display_motion(command_map, { id = 9999, motion = "HP+HK" })
assert(motion == nil and status == "action_id_missing",
    "modern display must apply the same Action-bound DI compatibility rule")
motion, status = get_classic_display_motion(command_map, { id = 856, motion = "DI" })
assert(motion == nil and status == "action_id_missing",
    "Elena's Action 856 DI override must not leak into another character map")
motion, status = get_classic_display_motion(command_map, { id = 860, motion = "DI" })
assert(motion == nil and status == "action_id_missing",
    "Jamie's Action 860 DI override must not leak into another character map")

motion, status = get_classic_display_motion(elena_overrides, { id = 856, motion = "Unknown" })
assert(motion == "DI" and status == "runtime_verified_override",
    "Elena Action 856 must resolve from its verified classic override")
local modern_motion
modern_motion, status = get_modern_display_motion(elena_overrides, { id = 856, motion = "Unknown" })
assert(type(modern_motion) == "table" and modern_motion.simple == "DI"
        and modern_motion.motion == "DI" and status == "runtime_verified_override",
    "Elena Action 856 must resolve from its verified modern override")
motion, status = get_classic_display_motion(jamie_overrides, { id = 860, motion = "Unknown" })
assert(motion == "DI" and status == "runtime_verified_override",
    "Jamie Action 860 must resolve from its verified classic override")
modern_motion, status = get_modern_display_motion(jamie_overrides, { id = 860, motion = "Unknown" })
assert(type(modern_motion) == "table" and modern_motion.simple == "DI"
        and modern_motion.motion == "DI" and status == "runtime_verified_override",
    "Jamie Action 860 must resolve from its verified modern override")

motion, status = get_classic_display_motion(command_map, { id = 9998, motion = "214+HP" })
assert(motion == nil and status == "action_id_missing",
    "arbitrary recorded motion must not bypass the audited command table")

resolve_modern_display_context = function()
    return false, command_map, "AKI", "loaded", false
end
local display_validation = validate_sequence_command_display({
    { id = 901, motion = "214+MP" },
    { id = 854, motion = "DI" },
    { id = 906, motion = "Unknown" },
    { id = 9999, motion = "2+HK" },
})
assert(display_validation.ok == false
        and display_validation.resolved_step_count == 2
        and display_validation.suppressed_step_count == 1
        and display_validation.unresolved_count == 1
        and display_validation.unresolved[1].index == 4
        and display_validation.unresolved[1].action_id == 9999
        and display_validation.unresolved[1].route_status == "action_id_missing",
    "the audit validator must match the classic table's resolved, suppressed and placeholder paths")

resolve_modern_display_context = function()
    return false, elena_overrides, "Elena", "loaded", false
end
local elena_di_validation = validate_sequence_command_display({
    { id = 856, motion = "Unknown" },
})
assert(elena_di_validation.ok == true
        and elena_di_validation.resolved_step_count == 1
        and elena_di_validation.unresolved_count == 0,
    "Elena Action 856 must pass the strict classic audit only through its override")

resolve_modern_display_context = function()
    return false, aki_overrides, "AKI", "loaded", false
end
local aki_classic_validation = validate_sequence_command_display({
    { id = 623, motion = "2+MP" },
    { id = 672, motion = "6+HP" },
    { id = 955, motion = "214+LK" },
    { id = 957, motion = "214+MK" },
})
assert(aki_classic_validation.ok == true
        and aki_classic_validation.mode == "classic"
        and aki_classic_validation.resolved_step_count == 4
        and aki_classic_validation.unresolved_count == 0,
    "AKI's four runtime-verified Classic overrides must pass strict display audit")

resolve_modern_display_context = function()
    return false, lily_overrides, "Lily", "loaded", false
end
local lily_runtime_audit_validation = validate_sequence_command_display({
    { id = 600, motion = "LP" },
    { id = 612, motion = "MK" },
    { id = 651, motion = "3+HP" },
})
assert(lily_runtime_audit_validation.ok == true
        and lily_runtime_audit_validation.total_steps == 3
        and lily_runtime_audit_validation.resolved_step_count == 3
        and lily_runtime_audit_validation.suppressed_step_count == 0
        and lily_runtime_audit_validation.unresolved_count == 0,
    "Lily's three runtime-verified Classic overrides must pass strict display audit")

for action_id, classic in pairs({
    ["903"] = "236+HP",
    ["904"] = "236+PP",
    ["947"] = "j.236+PP",
    ["952"] = "j.236+P",
    ["1000"] = "j.HK",
    ["1213"] = "214214+P",
}) do
    akuma_overrides[action_id] = {
        classic = classic,
        status = "strict_route",
    }
end
resolve_modern_display_context = function()
    return false, akuma_overrides, "Akuma", "loaded", false
end
local akuma_runtime_audit_validation = validate_sequence_command_display({
    { id = 622, motion = "2+LP" },
    { id = 627, motion = "2+MP" },
    { id = 661, motion = "6+MP" },
    { id = 975, motion = "214+LP" },
    { id = 977, motion = "214+HP" },
    { id = 982, motion = "6+P" },
    { id = 985, motion = "6+P" },
    { id = 991, motion = "236+HK" },
    { id = 903, motion = "236+HP" },
    { id = 908, motion = "HP" },
    { id = 904, motion = "236+PP" },
    { id = 914, motion = "4+LP+MP" },
    { id = 952, motion = "j.236+P" },
    { id = 948, motion = "4+LP" },
    { id = 952, motion = "j.236+P" },
    { id = 948, motion = "HP" },
    { id = 1000, motion = "j.HK" },
    { id = 1010, motion = "HK" },
    { id = 1213, motion = "214214+P" },
    { id = 1216, motion = "4+LP+MP+HP" },
})
assert(akuma_runtime_audit_validation.ok == true
        and akuma_runtime_audit_validation.total_steps == 20
        and akuma_runtime_audit_validation.resolved_step_count == 14
        and akuma_runtime_audit_validation.suppressed_step_count == 6
        and akuma_runtime_audit_validation.unresolved_count == 0,
    "Akuma's runtime-audit routes and six contextual internal phases must validate exactly as rendered")
local repeated_akuma_internal_validation = validate_sequence_command_display({
    { id = 947, motion = "j.236+PP" },
    { id = 948, motion = "HP" },
    { id = 948, motion = "4+LP" },
})
assert(repeated_akuma_internal_validation.ok == false
        and repeated_akuma_internal_validation.resolved_step_count == 1
        and repeated_akuma_internal_validation.suppressed_step_count == 1
        and repeated_akuma_internal_validation.unresolved_count == 1
        and repeated_akuma_internal_validation.unresolved[1].action_id == 948,
    "contextual suppression must not inherit an older owner across a real child Action")
akuma_overrides["906"] = {
    classic = "Normal",
    status = "suppress_transition",
}
local intervening_suppressed_action_validation = validate_sequence_command_display({
    { id = 947, motion = "j.236+PP" },
    { id = 906, motion = "Normal" },
    { id = 948, motion = "HP" },
})
assert(intervening_suppressed_action_validation.ok == false
        and intervening_suppressed_action_validation.resolved_step_count == 1
        and intervening_suppressed_action_validation.suppressed_step_count == 1
        and intervening_suppressed_action_validation.unresolved_count == 1
        and intervening_suppressed_action_validation.unresolved[1].action_id == 948,
    "contextual suppression must not cross a different catalog-suppressed Action")
local standalone_akuma_internal = validate_sequence_command_display({
    { id = 948, motion = "HP" },
})
assert(standalone_akuma_internal.ok == false
        and standalone_akuma_internal.suppressed_step_count == 0
        and standalone_akuma_internal.unresolved_count == 1
        and standalone_akuma_internal.unresolved[1].route_status
            == "action_id_missing",
    "a standalone internal Action must remain unresolved without its declared predecessor")
local wrong_akuma_internal_owner = validate_sequence_command_display({
    { id = 903, motion = "236+HP" },
    { id = 948, motion = "HP" },
})
assert(wrong_akuma_internal_owner.ok == false
        and wrong_akuma_internal_owner.resolved_step_count == 1
        and wrong_akuma_internal_owner.suppressed_step_count == 0
        and wrong_akuma_internal_owner.unresolved_count == 1,
    "an internal Action after the wrong owner must fail closed")
local visible_akuma_transition = validate_sequence_command_display({
    { id = 947, motion = "j.236+PP" },
    { id = 948, motion = ">HP", player_input_transition = true },
})
assert(visible_akuma_transition.ok == true
        and visible_akuma_transition.resolved_step_count == 2
        and visible_akuma_transition.suppressed_step_count == 0,
    "an explicitly player-triggered transition must remain visible after a contextual owner")

local boundary_child = { id = 948, motion = "HP", intentional = true }
local boundary_owner = { id = 947, motion = "j.236+PP", intentional = false }
local live_boundary_resolutions = resolve_live_log_command_displays(
    akuma_overrides,
    { boundary_child, boundary_owner },
    { boundary_child },
    false
)
assert(live_boundary_resolutions[boundary_child].suppressed == true
        and live_boundary_resolutions[boundary_owner].suppressed == false,
    "live contextual resolution must see an owner outside the filtered or truncated display window")

resolve_modern_display_context = function()
    return true, aki_overrides, "AKI", "loaded", true
end
local aki_modern_validation = validate_sequence_command_display({
    { id = 623, motion = "2+MP" },
    { id = 672, motion = "6+HP" },
    { id = 955, motion = "214+LK" },
    { id = 957, motion = "214+MK" },
})
assert(aki_modern_validation.ok == false
        and aki_modern_validation.mode == "modern"
        and aki_modern_validation.resolved_step_count == 0
        and aki_modern_validation.unresolved_count == 4,
    "Classic-only AKI overrides must remain unresolved in Modern mode")

resolve_modern_display_context = function()
    return true, jamie_overrides, "Jamie", "loaded", true
end
local jamie_di_validation = validate_sequence_command_display({
    { id = 860, motion = "Unknown" },
})
assert(jamie_di_validation.ok == true
        and jamie_di_validation.resolved_step_count == 1
        and jamie_di_validation.unresolved_count == 0,
    "Jamie Action 860 must pass the strict modern audit only through its override")

resolve_modern_display_context = function()
    return false, nil, "AKI", "map_load_failed", false
end
local missing_map_validation = validate_sequence_command_display({
    { id = 901, motion = "214+MP" },
})
assert(missing_map_validation.ok == false
        and missing_map_validation.map_available == false
        and missing_map_validation.preserved_step_count == 1
        and missing_map_validation.unresolved_count == 0,
    "a missing classic command map must preserve UI text but fail audit closed")

local modern_map = {
    _slim = true,
    ["901"] = {
        commands = { simple = "SP", motion = "214 + SP" },
        status = "strict_route",
    },
}
resolve_modern_display_context = function()
    return true, modern_map, "AKI", "loaded", true
end
local modern_validation = validate_sequence_command_display({
    { id = 901, motion = "214+MP" },
    { id = 9999, motion = "2+HK" },
})
assert(modern_validation.ok == false
        and modern_validation.mode == "modern"
        and modern_validation.classic_modern_projection == true
        and modern_validation.resolved_step_count == 1
        and modern_validation.unresolved_count == 1,
    "classic-to-modern projection must reject every step that would render an unresolved placeholder")

-- Renderer and audit must reject the same malformed display structures. These
-- cases used to be truthy Lua values and could therefore pass runtime audit
-- while the table rendered an unknown command (or silently reused saved text).
local malformed_classic_map = {
    _slim = true,
    ["920"] = { classic = "[指令未识别]", status = "strict_route" },
    ["921"] = { classic = "236+HP", status = "route_unverified" },
    ["922"] = { classic = nil, status = "invalid_split_commands" },
    ["923"] = { classic = ">LP", status = "strict_route" },
    ["924"] = { classic = "LP", status = "invalid_split_commands" },
}
resolve_modern_display_context = function()
    return false, malformed_classic_map, "AKI", "loaded", false
end
local malformed_classic_validation = validate_sequence_command_display({
    { id = 920, motion = "236+LP" },
    { id = 921, motion = "236+HP" },
    { id = 922, motion = ">PP (cancel)" },
    { id = 923, motion = ">LP (cancel)" },
    { id = 924, motion = "LP" },
})
assert(malformed_classic_validation.ok == false
        and malformed_classic_validation.resolved_step_count == 1
        and malformed_classic_validation.unresolved_count == 4
        and malformed_classic_validation.unresolved[1].route_status == "invalid_display_motion"
        and malformed_classic_validation.unresolved[2].route_status == "route_unverified"
        and malformed_classic_validation.unresolved[3].route_status == "invalid_split_commands"
        and malformed_classic_validation.unresolved[3].resolved_route_status == "recorded_context"
        and malformed_classic_validation.unresolved[3].catalog_route_status == "invalid_split_commands"
        and malformed_classic_validation.unresolved[4].route_status == "invalid_split_commands"
        and malformed_classic_validation.unresolved[4].resolved_route_status == "invalid_split_commands",
    "classic sentinels, unverified routes and invalid split commands must fail even with saved context")

local malformed_modern_map = {
    _slim = true,
    ["930"] = { commands = {}, status = "strict_route" },
    ["931"] = {
        commands = { simple = "Unknown", motion = "ACTION_931", all = "[现代指令未识别]" },
        status = "strict_route",
    },
    ["932"] = { commands = { simple = "SP", motion = "236+SP" }, status = "route_unverified" },
    ["933"] = { commands = { simple = "SP", motion = "236+SP" }, status = "strict_route" },
    ["934"] = { status = "suppress_transition" },
}
resolve_modern_display_context = function()
    return true, malformed_modern_map, "AKI", "loaded", true
end
local malformed_modern_validation = validate_sequence_command_display({
    { id = 930, motion = "236+MP" },
    { id = 931, motion = "236+HP" },
    { id = 932, motion = "236+SP" },
    { id = 933, motion = "236+SP" },
    { id = 934, motion = "Unknown" },
})
assert(malformed_modern_validation.ok == false
        and malformed_modern_validation.resolved_step_count == 1
        and malformed_modern_validation.suppressed_step_count == 1
        and malformed_modern_validation.unresolved_count == 3
        and malformed_modern_validation.unresolved[1].route_status == "invalid_display_motion"
        and malformed_modern_validation.unresolved[2].route_status == "invalid_display_motion"
        and malformed_modern_validation.unresolved[3].route_status == "route_unverified",
    "modern empty/sentinel commands and unverified routes must fail while valid and suppressed paths remain intact")

local action_matcher = dofile("autorun/func/ComboTrials/ActionMatcher.lua")
assert(action_matcher.is_exact_expected_action({ id = 854 }, 854) == true,
    "an unmapped runtime action must be admitted when it exactly matches the active expected step")
assert(action_matcher.is_exact_expected_action({ id = 854 }, 855) == false,
    "a different runtime action must not be admitted by the exact expected-step fallback")
assert(action_matcher.is_exact_expected_action(nil, 854) == false,
    "the expected-step fallback must remain disabled outside active playback")
local kimberly_parent_match = action_matcher.match_expected_action(
    { id = 908, motion = ">LK" },
    904,
    "236+KK",
    "LK"
)
assert(kimberly_parent_match.matched == false and kimberly_parent_match.match_reason == "none",
    "Kimberly's internal 904 phase must not satisfy the recorded 908 follow-up by its LK input")
assert(action_matcher.is_optional_parent_for_followup(
        "236+KK",
        { id = 908, motion = ">LK" },
        904,
        nil,
        { id = 903, motion = "236+KK" },
        "LK"
    ) == true,
    "Kimberly's internal 904 phase must be ignored while playback waits for Action ID 908")
assert(action_matcher.is_optional_parent_for_followup(
        "236+KK",
        { id = 908, motion = ">LK" },
        904,
        nil,
        { id = 903, motion = "236+KK" },
        "HK"
    ) == false,
    "a different physical button must not be hidden as a follow-up transition phase")
assert(action_matcher.is_optional_parent_for_followup(
        ">HK",
        { id = 983, motion = ">HK" },
        983,
        nil,
        { id = 982, motion = ">HK" },
        "HK"
    ) == false,
    "an exact expected Action must not be rejected when adjacent follow-ups share one motion")
assert(action_matcher.is_optional_parent_for_followup(
        "j.P",
        { id = 979, motion = "j.Throw" },
        966,
        { optional_parent_ids = { 966 } },
        { id = 951, motion = "236+MP+HP" },
        "LK"
    ) == true,
    "an explicit transient parent rule must work for a button chord without a > notation")
local kimberly_followup_match = action_matcher.match_expected_action(
    { id = 908, motion = ">LK" },
    908,
    "Unknown",
    "None"
)
assert(kimberly_followup_match.matched == true and kimberly_followup_match.match_reason == "id",
    "the recorded Kimberly follow-up must advance only when runtime Action ID 908 occurs")
local idless_legacy_match = action_matcher.match_expected_action(
    { motion = "DI" },
    854,
    "DI",
    "DI"
)
assert(idless_legacy_match.matched == true and idless_legacy_match.match_reason == "motion",
    "motion fallback must remain available only for legacy steps without an Action ID")

local character_rules = dofile("autorun/func/ComboTrials/CharacterRules.lua")
assert(character_rules.should_preserve_short_action(
        { ["976"] = { preserve_short_action = true } },
        {},
        976
    ) == true
    and character_rules.should_preserve_short_action({}, {}, 976) == false,
    "short Action preservation must come from exception data")
local common_variant_rules = {
    ["854"] = { action_alias_ids = "855" },
}
local deejay_variant_rules = {
    ["1268"] = {
        action_alias_ids = "1272",
        action_alias_combo_deltas = { ["1272"] = 23 },
        finish_on_first_hit = true,
    },
    ["1272"] = {
        action_alias_ids = "1268",
        action_alias_combo_deltas = { ["1268"] = 32 },
        finish_on_first_hit = true,
    },
}
local legacy_di_rule = character_rules.get_match_rule(
    {}, common_variant_rules, "ChunLi", 854)
local legacy_di_match = action_matcher.match_expected_action(
    { id = 854, motion = "DI" },
    855,
    "DI",
    "HP+HK",
    legacy_di_rule
)
assert(legacy_di_match.matched == true and legacy_di_match.match_reason == "action_alias_id",
    "a legacy Action ID 854 DI step must admit the current runtime Action ID 855")
local mai_hp_rule = character_rules.get_match_rule(
    { ["604"] = { action_alias_ids = "605" } }, {}, "Mai", 604)
local mai_hp_match = action_matcher.match_expected_action(
    { id = 604, motion = "HP" },
    605,
    "HP",
    "HP",
    mai_hp_rule
)
assert(mai_hp_match.matched == true
        and mai_hp_match.match_reason == "action_alias_id",
    "a legacy Mai HP step must admit the post-update Action ID 605")
local mai_hp_reverse = action_matcher.match_expected_action(
    { id = 605, motion = "HP" },
    604,
    "HP",
    "HP",
    character_rules.get_match_rule(
        { ["604"] = { action_alias_ids = "605" } }, {}, "Mai", 605)
)
assert(mai_hp_reverse.matched == false,
    "Mai's post-update HP Action must not gain an unsupported reverse alias")
local mai_throw_rule = character_rules.get_match_rule(
    { ["715"] = { action_alias_ids = "725" } }, {}, "Mai", 715)
local mai_throw_match = action_matcher.match_expected_action(
    { id = 715, motion = "THROW" },
    725,
    "THROW",
    "THROW",
    mai_throw_rule
)
assert(mai_throw_match.matched == true
        and mai_throw_match.match_reason == "action_alias_id",
    "a legacy Mai throw startup Action must admit the current hit Action ID 725")
local mai_throw_reverse = action_matcher.match_expected_action(
    { id = 725, motion = "THROW" },
    715,
    "THROW",
    "THROW",
    character_rules.get_match_rule(
        { ["715"] = { action_alias_ids = "725" } }, {}, "Mai", 725)
)
assert(mai_throw_reverse.matched == false,
    "Mai's throw hit Action must not gain an unsupported reverse alias")
local sagat_nexus_rule = character_rules.get_match_rule(
    { ["953"] = { action_alias_ids = "951" } }, {}, "Sagat", 953)
local sagat_nexus_match = action_matcher.match_expected_action(
    { id = 953, motion = "214+LK" },
    951,
    "41236+LK",
    "LK",
    sagat_nexus_rule
)
assert(sagat_nexus_match.matched == true
        and sagat_nexus_match.match_reason == "action_alias_id",
    "a legacy Sagat light Tiger Nexus Action must admit the post-update Action ID 951")
local sagat_nexus_reverse = action_matcher.match_expected_action(
    { id = 951, motion = "41236+LK" },
    953,
    "214+LK",
    "LK",
    character_rules.get_match_rule(
        { ["953"] = { action_alias_ids = "951" } }, {}, "Sagat", 951)
)
assert(sagat_nexus_reverse.matched == false,
    "Sagat's post-update Tiger Nexus Action must not gain an unsupported reverse alias")
local sagat_medium_nexus_rule = character_rules.get_match_rule(
    { ["954"] = { action_alias_ids = "953" } }, {}, "Sagat", 954)
local sagat_medium_nexus_match = action_matcher.match_expected_action(
    { id = 954, motion = "214+MK" },
    953,
    "214+MK",
    "MK",
    sagat_medium_nexus_rule
)
assert(sagat_medium_nexus_match.matched == true
        and sagat_medium_nexus_match.match_reason == "action_alias_id",
    "a legacy Sagat medium Tiger Nexus Action must admit the post-update Action ID 953")
local sagat_medium_nexus_reverse = action_matcher.match_expected_action(
    { id = 953, motion = "214+MK" },
    954,
    "214+MK",
    "MK",
    character_rules.get_match_rule(
        { ["954"] = { action_alias_ids = "953" } }, {}, "Sagat", 953)
)
assert(sagat_medium_nexus_reverse.matched == false,
    "Sagat's post-update medium Tiger Nexus Action must not gain an unsupported reverse alias")
assert(action_matcher.is_optional_parent_for_followup(
        "236+HK",
        { id = 944, motion = "236+KK" },
        943,
        { optional_parent_ids = { 943 } },
        { id = 901, motion = "236+MP" },
        "HK"
    ) == true,
    "Sagat's one-frame 943 precursor must not block the expected 236+KK Action 944")
local current_di_rule = character_rules.get_match_rule(
    {}, common_variant_rules, "ChunLi", 855)
local reverse_di_match = action_matcher.match_expected_action(
    { id = 855, motion = "DI" },
    854,
    "DI",
    "HP+HK",
    current_di_rule
)
assert(reverse_di_match.matched == false,
    "current Action ID 855 DI recordings must not gain an unsupported reverse alias")
local jamie_di_rule = character_rules.get_match_rule(
    { ["854"] = { force = true } },
    common_variant_rules,
    "Jamie",
    854
)
assert(jamie_di_rule.force == true
        and action_matcher.matches_expected_action_id({ id = 854 }, 855, jamie_di_rule) == true,
    "the universal DI alias must merge with character-specific Action ID 854 rules")
local cammy_force_rule = { runtime_force_after_ids = "652,653,926" }
local resolved_cammy_force = character_rules.apply_runtime_overrides(
    "AnyCharacter",
    908,
    cammy_force_rule,
    { { id = 653 } }
)
assert(resolved_cammy_force.force == true
        and cammy_force_rule.force == nil,
    "runtime force transitions must come from exception data without mutating it")
assert(character_rules.apply_runtime_overrides(
        "Cammy",
        908,
        cammy_force_rule,
        { { id = 700 } }
    ).force ~= true,
    "runtime force mappings must reject an undeclared predecessor")
do
local aki_recording_rules = {
        ["944"] = {
            absorb_ids = "936,941,945",
            action_required = true,
            absorb_requires_combo = false,
            record_absorb_as_parent = true,
            action_event_projection = {
                canonical_owner_ids = "945",
                max_fold_delay_frames = 1,
                require_same_anchor = true,
            },
        },
        ["998"] = {
            absorb_ids = "999",
            action_event_projection = {},
        },
    }
assert(character_rules.find_recording_absorb_owner(
        aki_recording_rules, {}, 945) == 944,
    "an opted-in frame-zero absorb branch must resolve to its recording command owner")
assert(character_rules.find_recording_absorb_owner(
        aki_recording_rules, {}, 936) == nil,
    "an internal hit phase must not canonicalize when its command owner is absent")
local aki_projection_rules =
    character_rules.build_action_event_projection_rules(aki_recording_rules, {})
assert(aki_projection_rules[945].kind == "canonical_owner"
        and aki_projection_rules[945].owner_id == 944
        and aki_projection_rules[945].max_fold_delay_frames == 1
        and aki_projection_rules[945].require_same_anchor == true
        and aki_projection_rules[936].kind == "internal_phase"
        and aki_projection_rules[936].owner_id == 944
        and aki_projection_rules[941].kind == "internal_phase"
        and aki_projection_rules[999].kind == "internal_phase"
        and aki_projection_rules[999].owner_id == 998,
    "loaded AKI exceptions must compile into exact canonical and internal projection rules")
assert(next(character_rules.build_action_event_projection_rules({
        ["944"] = { absorb_ids = "945" },
    }, {})) == nil,
    "absorb rules must not affect ActionEventCompiler without an explicit projection declaration")
assert(character_rules.build_action_event_projection_rules({
        ["944"] = {
            absorb_ids = "999",
            action_event_projection = {},
        },
        ["998"] = {
            absorb_ids = "999",
            action_event_projection = {},
        },
    }, {})[999] == nil,
    "ambiguous projection owners must fail closed")
local aki_expected_owner = { id = 944, expected_combo = 7 }
local current_canonical = character_rules.match_current_canonical_confirmation(
    aki_recording_rules,
    {},
    aki_expected_owner,
    945,
    5,
    "AKI"
)
assert(current_canonical.matched == true
        and current_canonical.actual_action_id == 945
        and current_canonical.ignore_combo_check == true
        and current_canonical.source == "action_event_projection",
    "input-truth playback must admit AKI's projected runtime owner before its hits land")
for _, internal_id in ipairs({ 936, 941 }) do
    local internal_phase = character_rules.match_current_canonical_confirmation(
        aki_recording_rules,
        {},
        aki_expected_owner,
        internal_id,
        7,
        "AKI"
    )
    assert(internal_phase.matched == false
            and internal_phase.block_reason == "current_id_not_canonical_owner",
        "AKI internal hit phases must not advance the canonical owner step")
end
local recent_canonical = character_rules.find_recent_canonical_confirmation(
    aki_recording_rules,
    {},
    aki_expected_owner,
    {
        { id = 941, combo_count = 7, start_frame = 124 },
        { id = 936, combo_count = 6, start_frame = 122 },
        { id = 945, combo_count = 5, start_frame = 100, action_instance = 44 },
    },
    "AKI"
)
assert(recent_canonical.matched == true
        and recent_canonical.actual_action_id == 945
        and recent_canonical.recent_index == 3
        and recent_canonical.start_frame == 100,
    "recent canonical lookup must skip newer internal phases and recover runtime owner 945")
local legacy_absorb_only = {
    ["944"] = {
        absorb_ids = "945",
        action_required = true,
        absorb_requires_combo = false,
    },
}
assert(character_rules.match_current_absorb_confirmation(
        legacy_absorb_only, {}, aki_expected_owner, 945, 5, "AKI").matched == true,
    "non-input playback must retain the legacy absorb confirmation path")
assert(character_rules.match_current_canonical_confirmation(
        legacy_absorb_only, {}, aki_expected_owner, 945, 5, "AKI").matched == false,
    "input-truth playback must not admit a legacy absorb without canonical projection")
assert(character_rules.find_recent_canonical_confirmation(
        legacy_absorb_only,
        {},
        aki_expected_owner,
        { { id = 945, combo_count = 7, start_frame = 100 } },
        "AKI"
    ).matched == false,
    "recent input-truth confirmation must also fail closed without canonical projection")
local ambiguous_canonical_owners = {
    ["944"] = {
        absorb_ids = "945",
        action_required = true,
        absorb_requires_combo = false,
        action_event_projection = { canonical_owner_ids = "945" },
    },
    ["998"] = {
        absorb_ids = "945",
        action_required = true,
        absorb_requires_combo = false,
        action_event_projection = { canonical_owner_ids = "945" },
    },
}
assert(character_rules.match_current_canonical_confirmation(
        ambiguous_canonical_owners,
        {},
        aki_expected_owner,
        945,
        7,
        "AKI"
    ).matched == false,
    "live canonical matching must inherit the compiler's ambiguous-owner rejection")
assert(character_rules.find_recent_canonical_confirmation(
        ambiguous_canonical_owners,
        {},
        aki_expected_owner,
        { { id = 945, combo_count = 7, start_frame = 100 } },
        "AKI"
    ).matched == false,
    "recent canonical matching must also fail closed for ambiguous owners")
end
assert(character_rules.find_recording_absorb_owner({
        ["944"] = { absorb_ids = "936,941,945" }
    }, {}, 945) == nil,
    "absorb aliases must not change recording identity without an explicit character rule")
assert(character_rules.find_recording_absorb_owner({
        ["969"] = { absorb_ids = "975", record_absorb_as_parent = true },
        ["970"] = { absorb_ids = "975", record_absorb_as_parent = true }
    }, {}, 975) == nil,
    "ambiguous absorb parents must fail closed instead of choosing an arbitrary command")
local lily_930_rules = {
    ["930"] = {
        absorb_ids = "929",
        action_event_rules = {
            transient_precursor_ids = "929",
        },
    },
}
local lily_action_event_rules =
    character_rules.build_action_event_rules(lily_930_rules, {})
assert(lily_action_event_rules.transient_input_precursor_transitions[929][930]
        == true,
    "exception data must compile transient precursor mappings for compiler and runtime")
assert(next(character_rules.build_action_event_rules({
        ["930"] = { action_event_rules = { transient_precursor_ids = "bad" } },
    }, {}).transient_input_precursor_transitions) == nil,
    "malformed transient precursor mappings must fail closed")
local jamie_tail_rules = character_rules.build_action_event_rules({
    ["657"] = {
        action_event_rules = {
            suppress_after = {
                previous_ids = "652",
                anchor_kind = "button_release",
                max_delay_frames = 64,
                require_no_contact = true,
            },
        },
    },
}, {})
assert(jamie_tail_rules.suppress_after[657].previous_ids[652] == true
        and jamie_tail_rules.suppress_after[657].anchor_kind == "button_release"
        and jamie_tail_rules.suppress_after[657].max_delay_frames == 64
        and jamie_tail_rules.suppress_after[657].require_no_contact == true,
    "exception data must compile exact Action-event suppression predicates")
local cviper_quick_successor_rules = character_rules.build_action_event_rules({
    ["1037"] = {
        action_event_rules = {
            preserve_quick_successor = { max_delay_frames = 4 },
        },
    },
}, {})
assert(cviper_quick_successor_rules.quick_successor_sources[1037].max_delay_frames
        == 4,
    "exception data must compile bounded same-input successor preservation")
local lily_930_expected = { id = 930, expected_combo = 6 }
local lily_930_canonical = character_rules.match_current_canonical_confirmation(
    lily_930_rules, {}, lily_930_expected, 929, 6, "Lily")
assert(lily_930_canonical.matched == false
        and lily_930_canonical.block_reason == "canonical_owner_projection_missing",
    "Lily must not canonicalize 929 through the absorb-only exception")
assert(action_matcher.matches_expected_action_id(
        lily_930_expected, 929, lily_930_rules["930"]) == false,
    "Lily's transient 929 precursor must not advance the 930 step through action_alias_ids")
local lily_transient_ignore = action_matcher.classify_runtime_transition({
    character = "Lily",
    expected_step = lily_930_expected,
    expected_action_matches_current = false,
    actual_action_id = 929,
    action_event_rules = lily_action_event_rules,
    input_anchor_kind = "button_press",
    input_truth_mode = true,
})
assert(lily_transient_ignore.ignored == true
        and lily_transient_ignore.reason == "transient_input_precursor",
    "the live trial must ignore Lily's 929 precursor while waiting for durable 930")
local lily_transient_wrong_step = action_matcher.classify_runtime_transition({
    character = "Lily",
    expected_step = { id = 941, expected_combo = 8 },
    expected_action_matches_current = false,
    actual_action_id = 929,
    action_event_rules = lily_action_event_rules,
    input_anchor_kind = "button_press",
    input_truth_mode = true,
})
assert(lily_transient_wrong_step.ignored == false,
    "Lily's 929 precursor must not be ignored for a different expected step")
local ryu_transient_mismatch = action_matcher.classify_runtime_transition({
    character = "Ryu",
    expected_step = lily_930_expected,
    expected_action_matches_current = false,
    actual_action_id = 929,
    action_event_rules = {},
    input_anchor_kind = "button_press",
    input_truth_mode = true,
})
assert(ryu_transient_mismatch.ignored == false,
    "transient precursor ignoring must stay character-scoped")
local lily_930_early = character_rules.match_current_absorb_confirmation(
    lily_930_rules, {}, lily_930_expected, 929, 3, "Lily")
assert(lily_930_early.matched == false
        and lily_930_early.block_reason == "combo_not_reached",
    "Lily 929 chord precursor must wait for the durable 930 before combo is reached")
local lily_930_absorb = character_rules.match_current_absorb_confirmation(
    lily_930_rules, {}, lily_930_expected, 929, 6, "Lily")
assert(lily_930_absorb.matched == true
        and lily_930_absorb.actual_action_id == 929,
    "input-truth playback must admit Lily's transient 929 precursor through absorb_ids")
local lily_930_recent = character_rules.find_recent_absorb_confirmation(
    lily_930_rules,
    {},
    lily_930_expected,
    { { id = 929, combo_count = 6, start_frame = 100 } },
    "Lily"
)
assert(lily_930_recent.matched == true
        and lily_930_recent.actual_action_id == 929,
    "recent-input playback must retain the same Lily 929 absorb confirmation")
local honda_pending_policy = character_rules.match_current_absorb_confirmation(
    {
        _character = { allow_pending_absorb = true },
        ["605"] = { absorb_ids = "606" },
    },
    {},
    { id = 605, expected_combo = 3 },
    606,
    1,
    "AnyCharacter"
)
assert(honda_pending_policy.matched == false
        and honda_pending_policy.block_reason == "combo_not_reached"
        and honda_pending_policy.allow_pending_absorb == true,
    "pending absorb permission must come from character exception data")
local lily_exception_source = read_all(
    "data/TrainingComboTrials_data/exceptions/Lily.json")
assert(lily_exception_source:find('"930"', 1, true)
        and lily_exception_source:find('"absorb_ids": "929"', 1, true)
        and lily_exception_source:find('"transient_precursor_ids": "929"', 1, true)
        and not lily_exception_source:find('"action_alias_ids": "929"', 1, true)
        and not lily_exception_source:find('"canonical_owner_ids": "929"', 1, true),
    "the shipped Lily exception must keep 929 as an absorb-only transient precursor")
local alex_override_source = read_all(
    "data/TrainingComboTrials_data/command_display_overrides/Alex.json")
assert(alex_override_source:find('"958"', 1, true)
        and alex_override_source:find('"959"', 1, true)
        and alex_override_source:find('"classic": "2+PP"', 1, true)
        and alex_override_source:find('"replace": true', 1, true),
    "the shipped Alex command overrides must preserve the verified 2+PP stance entries")
local ingrid_override_source = read_all(
    "data/TrainingComboTrials_data/command_display_overrides/Ingrid.json")
assert(ingrid_override_source:find('"609"', 1, true)
        and ingrid_override_source:find('"classic": "HP"', 1, true)
        and ingrid_override_source:find('"622"', 1, true)
        and ingrid_override_source:find('"classic": "2+LP"', 1, true)
        and ingrid_override_source:find('"1202"', 1, true)
        and ingrid_override_source:find('"classic": "236236+K"', 1, true)
        and ingrid_override_source:find('"1219"', 1, true)
        and ingrid_override_source:find('"classic": "214214+MP"', 1, true)
        and ingrid_override_source:find('"1229"', 1, true)
        and ingrid_override_source:find('"classic": "214214+HP"', 1, true),
    "the shipped Ingrid command overrides must preserve runtime-verified commands")
local ingrid_exception_source = read_all(
    "data/TrainingComboTrials_data/exceptions/Ingrid.json")
assert(ingrid_exception_source:find('"945"', 1, true)
        and ingrid_exception_source:find('"absorb_ids": "953"', 1, true)
        and ingrid_exception_source:find('"action_event_projection": {}', 1, true)
        and ingrid_exception_source:find('"949"', 1, true)
        and ingrid_exception_source:find('"transient_precursor_ids": "906,945"', 1, true),
    "the shipped Ingrid exceptions must preserve projectile continuation and OD precursor rules")
local mai_exception_source = read_all(
    "data/TrainingComboTrials_data/exceptions/Mai.json")
assert(mai_exception_source:find('"604"', 1, true)
        and mai_exception_source:find('"action_alias_ids": "605"', 1, true)
        and mai_exception_source:find('"715"', 1, true)
        and mai_exception_source:find('"action_alias_ids": "725"', 1, true),
    "the shipped Mai exception must preserve verified post-update Action aliases")
local mai_override_source = read_all(
    "data/TrainingComboTrials_data/command_display_overrides/Mai.json")
assert(mai_override_source:find('"604"', 1, true)
        and mai_override_source:find('"classic": "HP"', 1, true)
        and mai_override_source:find('legacy Mai Action 604', 1, true),
    "the shipped Mai command override must preserve the legacy 604 HP display")
local sagat_exception_source = read_all(
    "data/TrainingComboTrials_data/exceptions/Sagat.json")
assert(sagat_exception_source:find('"944"', 1, true)
        and sagat_exception_source:find('"optional_parent_ids"', 1, true)
        and sagat_exception_source:find('"953"', 1, true)
        and sagat_exception_source:find('"action_alias_ids": "951"', 1, true)
        and sagat_exception_source:find('"954"', 1, true)
        and sagat_exception_source:find('"action_alias_ids": "953"', 1, true),
    "the shipped Sagat exception must preserve verified post-update Action transitions")
local sagat_override_source = read_all(
    "data/TrainingComboTrials_data/command_display_overrides/Sagat.json")
assert(sagat_override_source:find('"600"', 1, true)
        and sagat_override_source:find('"classic": "LP"', 1, true)
        and sagat_override_source:find('"604"', 1, true)
        and sagat_override_source:find('"classic": "MP"', 1, true)
        and sagat_override_source:find('"954"', 1, true)
        and sagat_override_source:find('"classic": "214+MK"', 1, true),
    "the shipped Sagat command overrides must preserve runtime-verified commands")
local cviper_override_source = read_all(
    "data/TrainingComboTrials_data/command_display_overrides/CViper.json")
assert(cviper_override_source:find('"608"', 1, true)
        and cviper_override_source:find('"classic": "HK"', 1, true)
        and cviper_override_source:find('"1037"', 1, true)
        and cviper_override_source:find('"classic": "28"', 1, true),
    "the shipped C. Viper command overrides must preserve runtime-verified commands")
local combo_imgui_source = read_all("autorun/func/ComboTrials_ImGui.lua")
assert(combo_imgui_source:find("local function reset_command_display_cache()", 1, true)
        and combo_imgui_source:find("ctx.clear_command_display_cache = M.clear_command_display_cache", 1, true)
        and combo_imgui_source:find("function M.clear_command_display_cache()", 1, true),
    "renderer initialization must expose and invoke command-display cache invalidation")
local combo_entry_source = read_all("autorun/TrainingComboTrials_v1.0.lua")
assert(combo_entry_source:find('package.loaded["func/ComboTrials_ImGui"] = nil', 1, true)
        and combo_entry_source:find('package.loaded["func/ComboTrials_ImGui"].clear_command_display_cache', 1, true)
        and not combo_entry_source:find("local cached_combo_trials_renderer", 1, true),
    "the entry script must upgrade an already-cached legacy renderer exactly once")
local deejay_sa3_exception = character_rules.get_match_rule(
    deejay_variant_rules, {}, "DeeJay", 1268)
assert(deejay_sa3_exception ~= nil,
    "Dee Jay SA3/CA compatibility must live in character rules, not legacy combo JSON")
assert(action_matcher.matches_expected_action_id({ id = 1268 }, 1272, deejay_sa3_exception) == true,
    "a legacy Dee Jay SA3 step must admit the low-health CA runtime action")
local ca_match = action_matcher.match_expected_action(
    { id = 1268, motion = "214214+P" },
    1272,
    "Unknown",
    "None",
    deejay_sa3_exception
)
assert(ca_match.matched == true and ca_match.match_reason == "action_alias_id",
    "the health-selected CA action must validate as the recorded SA3 command")
local legacy_sa3_step = {
    id = 1268,
    expected_combo = 46,
    _runtime_action_id = 1272,
    _runtime_combo_on_match = 14
}
local effective_combo, combo_source = action_matcher.effective_expected_combo(
    legacy_sa3_step,
    { expected_combo = 14 },
    deejay_sa3_exception
)
assert(effective_combo == 37 and combo_source == "action_alias_combo_delta",
    "a CA runtime variant must replace the old SA3 hit-count target with 14 + 23")
local completion_satisfied, completion_target, completion_source =
    action_matcher.is_completion_satisfied(
        legacy_sa3_step,
        { expected_combo = 14 },
        deejay_sa3_exception,
        15
    )
assert(completion_satisfied == true and completion_target == 37
        and completion_source == "connected_after_action_match",
    "a connected Dee Jay CA must finish after its first hit without waiting for the cinematic hit count")
legacy_sa3_step._runtime_action_id = 1268
effective_combo, combo_source = action_matcher.effective_expected_combo(
    legacy_sa3_step,
    { expected_combo = 14 },
    deejay_sa3_exception
)
assert(effective_combo == 46 and combo_source == "recorded_expected_combo",
    "the normal SA3 runtime variant must retain the old file's recorded target")
local deejay_ca_exception = character_rules.get_match_rule(
    deejay_variant_rules, {}, "DeeJay", 1272)
local legacy_ca_step = {
    id = 1272,
    expected_combo = 37,
    _runtime_action_id = 1268,
    _runtime_combo_on_match = 14,
    _runtime_connected_on_match = true
}
effective_combo, combo_source = action_matcher.effective_expected_combo(
    legacy_ca_step,
    { expected_combo = 14 },
    deejay_ca_exception
)
assert(effective_combo == 46 and combo_source == "action_alias_combo_delta",
    "an old CA recording must likewise accept the normal-health SA3 variant")
completion_satisfied, completion_target, completion_source =
    action_matcher.is_completion_satisfied(
        legacy_ca_step,
        { expected_combo = 14 },
        deejay_ca_exception,
        14
    )
assert(completion_satisfied == true and completion_target == 46
        and completion_source == "connected_on_action_match",
    "a first hit already counted on the action frame must finish the Dee Jay super")
assert(action_matcher.matches_expected_action_id({ id = 1268 }, 1200, deejay_sa3_exception) == false,
    "a different super art must not inherit the SA3/CA compatibility rule")
assert(action_matcher.matches_expected_action_id({ id = 1268 }, 1220, deejay_sa3_exception) == false,
    "an unrelated Dee Jay action ID must not be accepted as the super variant")

local main_source = read_all("autorun/TrainingComboTrials_v1.0.lua")
assert(main_source:find("ActionMatcher.matches_expected_action_id", 1, true),
    "playback intentionality must admit configured action aliases before filtering")
assert(main_source:find("ActionMatcher.should_admit_ignored_expected_action", 1, true),
    "raw-input expected Actions must override legacy ignore rules during live validation")
assert(main_source:find("expected_exception", 1, true),
    "playback action matching must receive the expected step's character rule")
assert(main_source:find("CharacterRules.find_recording_absorb_owner", 1, true),
    "recording must recover explicitly configured frame-zero command owners")
assert(main_source:find("ActionMatcher.matches_absorb_id(parent_exc, runtime_act_id)", 1, true),
    "existing absorbed phases must be checked before recording-time owner recovery")
assert(main_source:match(
        "local recent_absorb = input_truth_mode%s+and CharacterRules%.find_recent_canonical_confirmation"
    ),
    "input-truth recent matching must use canonical projection instead of legacy absorb")
assert(main_source:match(
        "local current_absorb = input_truth_mode%s+and CharacterRules%.match_current_canonical_confirmation"
    ),
    "input-truth current matching must use canonical projection instead of legacy absorb")
assert(main_source:find("CharacterRules.find_recent_absorb_confirmation", 1, true)
        and main_source:find("CharacterRules.match_current_absorb_confirmation", 1, true),
    "non-input playback must retain both legacy absorb confirmation paths")
local completion_calls = 0
for _ in main_source:gmatch("ActionMatcher%.is_completion_satisfied") do
    completion_calls = completion_calls + 1
end
assert(completion_calls >= 2,
    "normal completion and KO completion must both support connected super completion")
local validation_source = assert(main_source:match(
    "(local function ct_player_validation.-\nend)\n\nlocal function ct_player_hold_charge"
))
assert(not validation_source:find(
        "and not is_demo_playing and not trial_state.manual_reset_pending",
        1,
        true
    ),
    "demo playback must not be excluded from terminal completion checks")
assert(validation_source:find("if is_demo_playing then return end", 1, true),
    "demo playback must still skip manual drop and timeout failures after checking completion")
assert(main_source:find("if not trial_state._attempt_had_demo then", 1, true),
    "demo-visible success must remain excluded from persistent player completion records")
local pending_source = read_all("autorun/func/ComboTrials/PendingAbsorb.lua")
assert(pending_source:find("._runtime_action_id = actual_id", 1, true),
    "matched steps must retain the runtime SA3/CA variant for final completion")
assert(pending_source:find("._runtime_combo_on_match = combo_count", 1, true),
    "matched steps must retain the combo baseline used to confirm the first super hit")
local renderer = {
    get_command_display = function(_, action_id)
        if action_id == 906 then return nil, "suppress_transition" end
        if action_id == 907 then return nil, "suppress_transition" end
        if action_id == 901 then return "214+MP", "strict_route" end
        if action_id == 903 then return "214+HP", "strict_route" end
        if action_id == 944 then return "236+PP", "strict_route" end
        if action_id == 1037 then return "528", "route_unverified" end
        if action_id == 608 then return "HK", "route_unverified" end
        return nil, "action_id_missing"
    end
}

local recent_edge = command_resolver.find_recent_action_button_edge({
    { frame_tick = 100, mask = 32 },  -- MP launched the parent 214+MP
    { frame_tick = 105, mask = 128 }  -- K requested the derived cancel
}, 100, 106, 12)
assert(recent_edge == 128, "a delayed cancel must recover the newest post-parent button edge")
assert(command_resolver.find_recent_action_button_edge(
        { { frame_tick = 100, mask = 32 } }, 100, 106, 12) == 0,
    "the parent attack button must never be reinterpreted as a cancel")
assert(command_resolver.find_recent_action_button_edge(
        { { frame_tick = 90, mask = 128 } }, 100, 106, 12) == 0,
    "a stale pre-parent button must never produce a derived cancel")

local viper_owner_event = {
    id = 903,
    frame = 100,
    anchor = {
        pressed_buttons = 192,
        released_buttons = 0,
        held_buttons = 192,
    },
}
local viper_cancel_event = {
    id = 907,
    frame = 102,
    anchor = {
        pressed_buttons = 0,
        released_buttons = 64,
        held_buttons = 0,
    },
}
local viper_session = {
    events = { viper_owner_event, viper_cancel_event },
}
local transition_edge = command_resolver.find_input_bound_transition_edge(
    "CViper", viper_cancel_event, viper_session, renderer)
assert(transition_edge == 128,
    "a delayed C. Viper cancel must subtract the preceding command's HP owner")
viper_cancel_event.anchor.released_buttons = 192
transition_edge = command_resolver.find_input_bound_transition_edge(
    "CViper", viper_cancel_event, viper_session, renderer)
assert(transition_edge == 128,
    "a combined HP+LK release must retain only the K transition edge")
local transition_intentional, transition_status, transition_motion =
    command_resolver.resolve_unified_command_action(
        "CViper",
        907,
        transition_edge,
        transition_edge,
        renderer
    )
assert(transition_intentional == true
        and transition_status == "player_input_transition"
        and transition_motion == ">K (取消)",
    "the recovered C. Viper cancel must render as one stable K transition")

local intentional, route_status, classic = command_resolver.resolve_unified_command_action(
    "AnyCharacter", 901, 32, 32, renderer)
assert(intentional == true and route_status == "strict_route" and classic == "214+MP",
    "a physical catalog command must remain intentional")

intentional, route_status, classic = command_resolver.resolve_unified_command_action(
    "AKI", 944, 0, 48, renderer)
assert(intentional == true and route_status == "strict_route" and classic == "236+PP",
    "A.K.I. 236+PP must survive a delayed state-dependent Action transition")

intentional, route_status, classic = command_resolver.resolve_unified_command_action(
    "AnyCharacter", 901, 0, 0, renderer)
assert(intentional == false and route_status == "strict_route" and classic == "214+MP",
    "a catalog action without held buttons or a recovered edge must remain non-intentional")

intentional, route_status, classic = command_resolver.resolve_unified_command_action(
    "AnyCharacter", 906, 0, 0, renderer)
assert(intentional == false and route_status == "suppress_transition" and classic == nil,
    "a zero-input internal transition must be non-intentional in every control mode")

intentional, route_status, classic = command_resolver.resolve_unified_command_action(
    "AnyCharacter", 906, 128, 128, renderer)
assert(intentional == true and route_status == "player_input_transition" and classic == ">K (取消)",
    "a physical button edge must recover a player-triggered cancel without character-specific IDs")

intentional, route_status, classic = command_resolver.resolve_unified_command_action(
    "CViper", 1037, 32, 32, renderer)
assert(intentional == false and route_status == "route_unverified" and classic == "528",
    "a direction-only route must not claim an unexplained attack-button edge")

intentional, route_status, classic = command_resolver.resolve_unified_command_action(
    "CViper", 608, 512, 512, renderer)
assert(intentional == true and route_status == "route_unverified" and classic == "HK",
    "a route-unverified normal must remain intentional when its button is visible")

intentional, route_status, classic = command_resolver.resolve_unified_command_action(
    "AnyCharacter", 901, 32, 32, nil)
assert(intentional == false and route_status == "resolver_unavailable" and classic == nil,
    "a missing renderer must retain the resolver-unavailable fallback")

intentional, route_status, classic = command_resolver.resolve_unified_command_action(
    "AnyCharacter", 901, 32, 32, {
        get_command_display = function() error("resolver failure") end
    })
assert(intentional == false and route_status == "resolver_error" and classic == nil,
    "a renderer error must retain the resolver-error fallback")

print("combo command resolution tests passed")
