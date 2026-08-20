package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

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
ActionCompatibility = dofile("autorun/func/ComboTrials/ActionCompatibility.lua")
TrainingEnvironment = dofile("autorun/func/ComboTrials/TrainingEnvironment.lua")
Type63StrengthSemantics = dofile(
    "autorun/func/ComboTrials/Type63StrengthSemantics.lua")
do
local honda_compatibility, honda_compatibility_count,
    honda_compatibility_status = ActionCompatibility.parse({
        schema = "xt.action_compatibility.v1",
        character = "EHonda",
        target_game_version = "2026-08-03",
        entries = {
            {
                recorded_action_id = 955,
                runtime_action_id = 959,
                recorded_motions = { "236+K" },
                evidence = "verified Honda runtime migration",
            },
            {
                recorded_action_id = 961,
                runtime_action_id = 965,
                recorded_motions = { ">2+P" },
                evidence = "motion-guarded overlapping Honda Action",
            },
            {
                recorded_action_id = 972,
                runtime_action_id = 977,
                runtime_action_alias_ids = { 976 },
                recorded_motions = { ">2+HK" },
                evidence = "verified Honda runtime phase variants",
            },
        },
    }, "EHonda", "2026-08-03")
assert(honda_compatibility_status == "loaded"
        and honda_compatibility_count == 3
        and ActionCompatibility.resolve(
            honda_compatibility, { id = 955, motion = "236+K" }) == 959
        and ActionCompatibility.matches(
            honda_compatibility, { id = 961, motion = ">2+P" }, 965)
        and not ActionCompatibility.matches(
            honda_compatibility, { id = 961, motion = ">2+P" }, 963)
        and ActionCompatibility.matches(
            honda_compatibility, { id = 972, motion = ">2+HK" }, 976)
        and ActionCompatibility.resolve(
            honda_compatibility, { id = 972, motion = ">2+HK" }) == 977
        and ActionCompatibility.resolve(
            honda_compatibility, { id = 961, motion = "236+KK" }) == nil,
    "historical Action compatibility must require version, ID, motion and runtime target")
HONDA_COMPATIBILITY_TEST = honda_compatibility
local mismatched_honda_compatibility = ActionCompatibility.parse({
    schema = "xt.action_compatibility.v1",
    character = "EHonda",
    target_game_version = "2026-08-03",
    entries = {
        {
            recorded_action_id = 955,
            runtime_action_id = 959,
            recorded_motions = { "236+K" },
            evidence = "version mismatch fixture",
        },
    },
}, "EHonda", "2026-09-01")
assert(mismatched_honda_compatibility == nil,
    "historical compatibility must fail closed on another game version")
end
do
local blanka_compatibility, blanka_compatibility_count,
    blanka_compatibility_status = ActionCompatibility.parse({
        schema = "xt.action_compatibility.v1",
        character = "Blanka",
        target_game_version = "2026-08-03",
        entries = {
            {
                recorded_action_id = 924,
                runtime_action_id = 926,
                recorded_motions = { "214+LP+LK+MK" },
                evidence = "verified Blanka runtime migration",
            },
        },
    }, "Blanka", "2026-08-03")
assert(blanka_compatibility_status == "loaded"
        and blanka_compatibility_count == 1
        and ActionCompatibility.matches(
            blanka_compatibility,
            { id = 924, motion = "214+LP+LK+MK" },
            926
        )
        and not ActionCompatibility.matches(
            blanka_compatibility,
            { id = 924, motion = "214+LP+LK+MK" },
            931
        )
        and not ActionCompatibility.matches(
            blanka_compatibility,
            { id = 924, motion = "214+LP+MP+HP" },
            926
        ),
    "Blanka compatibility must accept only the verified 924 to 926 command migration")
BLANKA_COMPATIBILITY_TEST = blanka_compatibility
end
do
local zangief_compatibility, zangief_compatibility_count,
    zangief_compatibility_status = ActionCompatibility.parse({
        schema = "xt.action_compatibility.v1",
        character = "Zangief",
        target_game_version = "2026-08-03",
        entries = {
            {
                recorded_action_id = 900,
                runtime_action_id = 903,
                recorded_motions = { "PP" },
                evidence = "verified Zangief runtime migration",
            },
        },
    }, "Zangief", "2026-08-03")
assert(zangief_compatibility_status == "loaded"
        and zangief_compatibility_count == 1
        and ActionCompatibility.matches(
            zangief_compatibility, { id = 900, motion = "PP" }, 903)
        and not ActionCompatibility.matches(
            zangief_compatibility, { id = 900, motion = "PPP" }, 903)
        and not ActionCompatibility.matches(
            zangief_compatibility, { id = 900, motion = "PP" }, 901),
    "Zangief compatibility must accept only the verified PP Action 900 to 903 migration")
ZANGIEF_COMPATIBILITY_TEST = zangief_compatibility
end

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
        presentation_contexts = {
            ["967"] = {
                labels = {
                    ["zh-CN"] = "（破坏姿势中/前滑步中）",
                    ["en-US"] = "(During Breaker Stance / Step-in)",
                },
                separate_line = true,
                strip_followup_prefix = true,
                evidence = "Capcom official Slash Elbow context",
            },
            ["973"] = {
                labels = {
                    ["zh-CN"] = "（破坏姿势中）",
                    ["en-US"] = "(During Breaker Stance)",
                },
                separate_line = true,
                strip_followup_prefix = true,
                evidence = "Capcom official Shoulder Launcher context",
            },
            ["977"] = {
                labels = {
                    ["zh-CN"] = "（破坏姿势中）",
                    ["en-US"] = "(During Breaker Stance)",
                },
                separate_line = true,
                strip_followup_prefix = true,
                replace_recorded_context = true,
                evidence = "Capcom official Heavy Lariat context",
            },
        },
        entries = {
            ["958"] = {
                classic = "2+PP",
                replace = true,
                require_recorded_motion_match = true,
                evidence = "twenty-seven completed runtime events",
            },
            ["959"] = {
                classic = "2+PP",
                replace = true,
                evidence = "one runtime event before a later mismatch",
            },
            ["967"] = { classic = "bad replacement", evidence = "test" },
            ["968"] = { classic = ">6+MP", evidence = "three raw replays" },
            ["977"] = { classic = "HP", evidence = "five raw replays" },
            ["978"] = { classic = ">LK" },
        },
    })
assert(override_status == "loaded" and applied_overrides == 4
    and merged_overrides["958"].classic == "2+PP"
    and merged_overrides["959"].classic == "2+PP"
    and merged_overrides["958"].status == "runtime_verified_override"
    and merged_overrides["959"].status == "runtime_verified_override"
    and merged_overrides["958"].metadata.replaced_existing == true
    and merged_overrides["958"].metadata.require_recorded_motion_match == true
    and merged_overrides["959"].metadata.replaced_existing == true
    and merged_overrides["959"].metadata.require_recorded_motion_match == false
    and merged_overrides["967"].classic == ">6+P"
    and merged_overrides["968"].classic == ">6+MP"
    and merged_overrides["968"].status == "runtime_verified_override"
    and merged_overrides["977"].classic == "HP"
    and merged_overrides["978"] == nil,
    "verified command overrides must fill missing Actions without silently replacing catalog rows")
ALEX_SLASH_CONTEXT_TEST = command_display_overrides.resolve_presentation_context(
    merged_overrides, 967, "zh-CN")
ALEX_SHOULDER_CONTEXT_TEST = command_display_overrides.resolve_presentation_context(
    merged_overrides, 973, "en-US")
ALEX_HP_CONTEXT_TEST = command_display_overrides.resolve_presentation_context(
    merged_overrides, 977, "zh-CN")
assert(type(ALEX_SLASH_CONTEXT_TEST) == "table"
        and ALEX_SLASH_CONTEXT_TEST.label == "（破坏姿势中/前滑步中）"
        and ALEX_SLASH_CONTEXT_TEST.separate_line == true
        and ALEX_SLASH_CONTEXT_TEST.strip_followup_prefix == true
        and type(ALEX_SHOULDER_CONTEXT_TEST) == "table"
        and ALEX_SHOULDER_CONTEXT_TEST.label == "(During Breaker Stance)"
        and type(ALEX_HP_CONTEXT_TEST) == "table"
        and ALEX_HP_CONTEXT_TEST.replace_recorded_context == true,
    "presentation contexts must resolve localized labels without replacing commands")
do
    local conditioned_map, conditioned_count, conditioned_status =
        command_display_overrides.merge({
            _slim = true,
            ["645"] = { classic = "route missing", status = "route_unverified" },
        }, "JP", {
        schema = "xt.command_display_overrides.v1",
        character = "JP",
        entries = {
            ["645"] = {
                classic = "HK",
                replace = true,
                button_masks = { 512 },
                evidence = "distinct runtime HK press",
            },
        },
        })
    local conditioned_hk, conditioned_hk_status =
        command_display_overrides.resolve_input_conditioned(
            conditioned_map, 645, 512, 512, "classic")
    local conditioned_mp = command_display_overrides.resolve_input_conditioned(
        conditioned_map, 645, 32, 32, "classic")
    local recorded_conditioned_hk, recorded_conditioned_status =
        command_display_overrides.resolve_recorded_input_conditioned(
            conditioned_map, 645, "HK", "classic")
    assert(conditioned_status == "loaded" and conditioned_count == 1
            and conditioned_map["645"] == nil
            and conditioned_hk == "HK"
            and conditioned_hk_status == "runtime_verified_conditioned_override"
            and conditioned_mp == nil
            and recorded_conditioned_hk == "HK"
            and recorded_conditioned_status == "runtime_verified_conditioned_override",
        "input-conditioned overrides must resolve only their exact physical button mask")
end
do
    local variant_map, variant_count, variant_status =
        command_display_overrides.merge({
            _slim = true,
            ["954"] = { classic = "route missing", status = "route_unverified" },
        }, "MBison", {
            schema = "xt.command_display_overrides.v1",
            character = "MBison",
            entries = {
                ["954"] = {
                    replace = true,
                    evidence = "distinct runtime button paths",
                    variants = {
                        { classic = "4+HP", button_masks = { 64 } },
                        { classic = "MK+HK", button_masks = { 768 } },
                    },
                },
                ["974"] = {
                    evidence = "LP and parry runtime paths",
                    variants = {
                        { classic = "236+LP", button_masks = { 16 } },
                        {
                            classic = "PARRY",
                            button_masks = { 288 },
                            recorded_motions = { "PARRY", "MP+MK" },
                        },
                    },
                },
            },
        })
    local back_hp = command_display_overrides.resolve_input_conditioned(
        variant_map, 954, 64, 64, "classic")
    local kick_pair = command_display_overrides.resolve_input_conditioned(
        variant_map, 954, 768, 768, "classic")
    local psycho_punisher = command_display_overrides.resolve_input_conditioned(
        variant_map, 974, 16, 16, "classic")
    local parry = command_display_overrides.resolve_input_conditioned(
        variant_map, 974, 288, 288, "classic")
    local legacy_parry =
        command_display_overrides.resolve_recorded_input_conditioned(
            variant_map, 974, "MP+MK", "classic")
    assert(variant_status == "loaded" and variant_count == 2
            and variant_map["954"] == nil and variant_map["974"] == nil
            and back_hp == "4+HP" and kick_pair == "MK+HK"
            and psycho_punisher == "236+LP" and parry == "PARRY"
            and legacy_parry == "PARRY",
        "variant overrides must distinguish reused Action IDs by buttons and accept verified legacy recorded aliases")
end
do
    local mbison_game_area_map, override_count, override_status =
        command_display_overrides.merge({
            _slim = true,
            _followup_relations = {
                {
                    type = "followup",
                    source_action_id = 918,
                    target_action_id = 939,
                },
            },
            ["910"] = {
                classic = "[2]8+HK",
                commands = { simple = "[2]8 + 强", motion = "[2]8 + 强" },
                status = "strict_route",
            },
            ["918"] = {
                classic = ">j.K",
                commands = { simple = "空中 任意键", motion = "空中 任意键" },
                status = "strict_route",
            },
            ["939"] = {
                classic = ">j.P",
                commands = { simple = "空中 任意键", motion = "空中 任意键" },
                status = "strict_route",
            },
        }, "MBison", {
            schema = "xt.command_display_overrides.v1",
            character = "MBison",
            entries = {
                ["921"] = {
                    classic = "HK",
                    commands = { simple = "强", motion = "强" },
                    replace = true,
                    evidence = "four verified Modern game-area recordings",
                },
            },
        })
    assert(override_status == "loaded" and override_count == 1
            and mbison_game_area_map["921"].classic == "HK"
            and mbison_game_area_map["921"].commands.simple == "强"
            and mbison_game_area_map["921"].commands.motion == "强"
            and mbison_game_area_map["921"].metadata.control_support
                == "classic_modern",
        "M. Bison Action 921 must expose its verified HK input in both Modern command slots")
    MBISON_GAME_AREA_MAP = mbison_game_area_map
end
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
        ["609"] = { classic = "LK", status = "route_unverified" },
        ["618"] = { classic = "2+LP", status = "route_unverified" },
        ["750"] = { classic = ">8", status = "route_unverified" },
        ["979"] = { classic = "j.Throw", status = "route_unverified" },
    }, "Cammy", {
        schema = "xt.command_display_overrides.v1",
        character = "Cammy",
        entries = {
            ["609"] = {
                classic = "LK",
                replace = true,
                evidence = "verified LK raw input",
            },
            ["618"] = {
                classic = "2+LP",
                replace = true,
                evidence = "verified down plus LP raw input",
            },
            ["750"] = {
                classic = ">8",
                replace = true,
                evidence = "verified upward transition after 651",
            },
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
assert(cammy_override_status == "loaded" and cammy_override_count == 5
    and cammy_overrides["609"].classic == "LK"
    and cammy_overrides["609"].status == "runtime_verified_override"
    and cammy_overrides["609"].metadata.replaced_existing == true
    and cammy_overrides["618"].classic == "2+LP"
    and cammy_overrides["618"].status == "runtime_verified_override"
    and cammy_overrides["618"].metadata.replaced_existing == true
    and cammy_overrides["750"].classic == ">8"
    and cammy_overrides["750"].status == "runtime_verified_override"
    and cammy_overrides["750"].metadata.replaced_existing == true
    and cammy_overrides["908"].classic == ">HK"
    and cammy_overrides["908"].status == "runtime_verified_override"
    and cammy_overrides["979"].classic == "j.LP+LK"
    and cammy_overrides["979"].status == "runtime_verified_override"
    and cammy_overrides["979"].metadata.replaced_existing == true,
    "Cammy's verified follow-up and air throw must resolve through data overrides")
do
    local ryu_catalog = {
        _slim = true,
        ["617"] = { classic = "HK", status = "route_unverified" },
        ["622"] = { classic = "2+LP", status = "route_unverified" },
        ["663"] = { classic = "4+HP", status = "route_unverified" },
        ["1005"] = { classic = "214+HK", status = "route_unverified" },
    }
    local ryu_overrides, ryu_override_count, ryu_override_status =
        command_display_overrides.merge(ryu_catalog, "Ryu", {
            schema = "xt.command_display_overrides.v1",
            character = "Ryu",
            entries = {
                ["617"] = {
                    classic = "HK",
                    replace = true,
                    evidence = "verified neutral HK raw input",
                },
                ["622"] = {
                    classic = "2+LP",
                    replace = true,
                    evidence = "verified down plus LP raw input",
                },
                ["663"] = {
                    classic = "4+HP",
                    replace = true,
                    evidence = "verified recorded 4+HP raw input",
                },
                ["1005"] = {
                    classic = "214+HK",
                    replace = true,
                    evidence = "verified quarter-circle-back HK raw input",
                },
            },
        })
    assert(ryu_override_status == "loaded" and ryu_override_count == 4
            and ryu_overrides["617"].classic == "HK"
            and ryu_overrides["617"].status == "runtime_verified_override"
            and ryu_overrides["617"].metadata.replaced_existing == true
            and ryu_overrides["622"].classic == "2+LP"
            and ryu_overrides["622"].status == "runtime_verified_override"
            and ryu_overrides["622"].metadata.replaced_existing == true
            and ryu_overrides["663"].classic == "4+HP"
            and ryu_overrides["663"].status == "runtime_verified_override"
            and ryu_overrides["663"].metadata.replaced_existing == true
            and ryu_overrides["1005"].classic == "214+HK"
            and ryu_overrides["1005"].status == "runtime_verified_override"
            and ryu_overrides["1005"].metadata.replaced_existing == true,
        "Ryu's runtime-verified commands must replace route-unverified catalog rows")
end
local honda_overrides, honda_override_count, honda_override_status =
    command_display_overrides.merge({
        _slim = true,
        ["608"] = { classic = "LK", status = "route_unverified" },
        ["660"] = { classic = "3+HK", status = "route_unverified" },
    }, "EHonda", {
        schema = "xt.command_display_overrides.v1",
        character = "EHonda",
        entries = {
            ["608"] = {
                classic = "LK",
                replace = true,
                evidence = "verified LK runtime audit",
            },
            ["660"] = {
                classic = "3+HK",
                replace = true,
                evidence = "verified directional HK runtime audit",
            },
        },
    })
assert(honda_override_status == "loaded" and honda_override_count == 2
        and honda_overrides["608"].classic == "LK"
        and honda_overrides["608"].status == "runtime_verified_override"
        and honda_overrides["608"].metadata.replaced_existing == true
        and honda_overrides["660"].classic == "3+HK"
        and honda_overrides["660"].status == "runtime_verified_override"
        and honda_overrides["660"].metadata.replaced_existing == true,
    "E. Honda's verified 3+HK must replace its unverified catalog row")
BLANKA_OVERRIDES_TEST, BLANKA_OVERRIDE_COUNT_TEST, BLANKA_OVERRIDE_STATUS_TEST =
    command_display_overrides.merge({
        _slim = true,
        _action_compatibility = BLANKA_COMPATIBILITY_TEST,
        ["613"] = { classic = "2+LP", status = "strict_route" },
        ["614"] = { classic = "2+LP", status = "strict_route" },
        ["926"] = { classic = "214+LP+LK+MK", status = "strict_route" },
        ["931"] = { classic = "214+LP+LK+MK", status = "strict_route" },
    }, "Blanka", {
        schema = "xt.command_display_overrides.v1",
        character = "Blanka",
        entries = {
            ["613"] = {
                classic = "2+LP",
                replace = true,
                evidence = "verified crouching LP runtime input",
            },
            ["926"] = {
                classic = "214+P",
                replace = true,
                evidence = "BCM requires one punch from the allowed set",
            },
            ["931"] = {
                classic = "214+PP",
                replace = true,
                evidence = "BCM requires two punches from the allowed set",
            },
        },
    })
assert(BLANKA_OVERRIDE_STATUS_TEST == "loaded" and BLANKA_OVERRIDE_COUNT_TEST == 3
        and BLANKA_OVERRIDES_TEST["926"].classic == "214+P"
        and BLANKA_OVERRIDES_TEST["931"].classic == "214+PP"
        and BLANKA_OVERRIDES_TEST["926"].metadata.replaced_existing == true
        and BLANKA_OVERRIDES_TEST["931"].metadata.replaced_existing == true,
    "Blanka's alternative punch masks must render as 214+P and 214+PP")
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
do
    local deejay_catalog = {
        _slim = true,
        ["606"] = { classic = "HP", status = "route_unverified" },
        ["611"] = { classic = "MK", status = "route_unverified" },
        ["617"] = { classic = "2+LP", status = "route_unverified" },
        ["1229"] = { classic = "236236+HP", status = "route_unverified" },
    }
    local deejay_overrides, deejay_override_count, deejay_override_status =
        command_display_overrides.merge(deejay_catalog, "DeeJay", {
            schema = "xt.command_display_overrides.v1",
            character = "DeeJay",
            entries = {
                ["606"] = { classic = "HP", replace = true, evidence = "runtime audit" },
                ["611"] = { classic = "MK", replace = true, evidence = "runtime audit" },
                ["617"] = { classic = "2+LP", replace = true, evidence = "runtime audit" },
                ["1229"] = {
                    classic = "236236+HP",
                    replace = true,
                    evidence = "runtime audit",
                },
            },
        })
    assert(deejay_override_status == "loaded" and deejay_override_count == 4
            and deejay_overrides["606"].classic == "HP"
            and deejay_overrides["611"].classic == "MK"
            and deejay_overrides["617"].classic == "2+LP"
            and deejay_overrides["1229"].classic == "236236+HP"
            and deejay_overrides["606"].status == "runtime_verified_override"
            and deejay_overrides["611"].status == "runtime_verified_override"
            and deejay_overrides["617"].status == "runtime_verified_override"
            and deejay_overrides["1229"].status == "runtime_verified_override"
            and deejay_overrides["606"].metadata.replaced_existing == true
            and deejay_overrides["611"].metadata.replaced_existing == true
            and deejay_overrides["617"].metadata.replaced_existing == true
            and deejay_overrides["1229"].metadata.replaced_existing == true,
        "Dee Jay's runtime-audited Classic commands must replace route-unverified catalog rows")
end
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
local luke_catalog = {
    _slim = true,
    ["609"] = { classic = "LK", status = "route_unverified" },
    ["612"] = { classic = "MK", status = "route_unverified" },
    ["669"] = { classic = "4+HK", status = "route_unverified" },
}
local luke_overrides, luke_override_count, luke_override_status =
    command_display_overrides.merge(luke_catalog, "Luke", {
        schema = "xt.command_display_overrides.v1",
        character = "Luke",
        entries = {
            ["609"] = { classic = "LK", replace = true, evidence = "runtime audit" },
            ["612"] = { classic = "MK", replace = true, evidence = "runtime audit" },
            ["669"] = { classic = "4+HK", replace = true, evidence = "runtime audit" },
        },
    })
assert(luke_override_status == "loaded" and luke_override_count == 3
        and luke_overrides["609"].classic == "LK"
        and luke_overrides["612"].classic == "MK"
        and luke_overrides["669"].classic == "4+HK"
        and luke_overrides["609"].status == "runtime_verified_override"
        and luke_overrides["612"].status == "runtime_verified_override"
        and luke_overrides["669"].status == "runtime_verified_override"
        and luke_overrides["609"].metadata.replaced_existing == true
        and luke_overrides["612"].metadata.replaced_existing == true
        and luke_overrides["669"].metadata.replaced_existing == true,
    "Luke's runtime-audited commands must replace route-unverified catalog rows")
local manon_catalog = {
    _slim = true,
    ["628"] = { classic = "2+MP", status = "route_unverified" },
    ["1022"] = { classic = "236+MP", status = "route_unverified" },
}
local manon_overrides, manon_override_count, manon_override_status =
    command_display_overrides.merge(manon_catalog, "Manon", {
        schema = "xt.command_display_overrides.v1",
        character = "Manon",
        entries = {
            ["628"] = { classic = "2+MP", replace = true, evidence = "runtime audit" },
            ["1022"] = { classic = "236+MP", replace = true, evidence = "runtime audit" },
        },
    })
assert(manon_override_status == "loaded" and manon_override_count == 2
        and manon_overrides["628"].classic == "2+MP"
        and manon_overrides["1022"].classic == "236+MP"
        and manon_overrides["628"].status == "runtime_verified_override"
        and manon_overrides["1022"].status == "runtime_verified_override"
        and manon_overrides["628"].metadata.replaced_existing == true
        and manon_overrides["1022"].metadata.replaced_existing == true,
    "Manon's runtime-audited commands must replace route-unverified catalog rows")
local guile_catalog = {
    _slim = true,
    ["609"] = { classic = "HP", status = "route_unverified" },
    ["653"] = { classic = "3+HK", status = "route_unverified" },
    ["674"] = { classic = "6+HK", status = "route_unverified" },
}
local guile_overrides, guile_override_count, guile_override_status =
    command_display_overrides.merge(guile_catalog, "Guile", {
        schema = "xt.command_display_overrides.v1",
        character = "Guile",
        entries = {
            ["609"] = { classic = "HP", replace = true, evidence = "runtime audit" },
            ["653"] = { classic = "3+HK", replace = true, evidence = "runtime audit" },
            ["674"] = { classic = "6+HK", replace = true, evidence = "runtime audit" },
            ["922"] = { classic = "236+LP+MP", replace = true, evidence = "runtime audit" },
            ["923"] = { classic = "214+PP", replace = true, evidence = "runtime audit" },
        },
    })
assert(guile_override_status == "loaded" and guile_override_count == 5
        and guile_overrides["609"].classic == "HP"
        and guile_overrides["653"].classic == "3+HK"
        and guile_overrides["674"].classic == "6+HK"
        and guile_overrides["922"].classic == "236+LP+MP"
        and guile_overrides["923"].classic == "214+PP"
        and guile_overrides["609"].status == "runtime_verified_override"
        and guile_overrides["922"].metadata.replaced_existing == false
        and guile_overrides["923"].metadata.replaced_existing == false,
    "Guile's runtime-audited commands must replace unverified rows and fill missing Actions")
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
do
local ed_overrides, ed_override_count, ed_override_status =
    command_display_overrides.merge({
        _slim = true,
        ["606"] = { classic = "HP", status = "strict_route" },
        ["634"] = { classic = "2+LK", status = "route_unverified" },
        ["639"] = { classic = "2+MK", status = "route_unverified" },
    }, "Ed", {
        schema = "xt.command_display_overrides.v1",
        character = "Ed",
        contextual_internal_phases = {
            ["605"] = {
                owner_ids = { 606 },
                evidence = "verified 606 to 605 Psycho Knuckle transition",
            },
        },
        entries = {
            ["634"] = {
                classic = "2+LK",
                replace = true,
                evidence = "verified crouching LK",
            },
            ["639"] = {
                classic = "2+MK",
                replace = true,
                evidence = "verified crouching MK",
            },
        },
    })
assert(ed_override_status == "loaded" and ed_override_count == 2
        and ed_overrides["605"] == nil
        and ed_overrides["634"].classic == "2+LK"
        and ed_overrides["639"].classic == "2+MK"
        and command_display_overrides.is_contextual_internal_phase(
            ed_overrides, 606, 605) == true
        and command_display_overrides.is_contextual_internal_phase(
            ed_overrides, 621, 605) == false,
    "Ed Action 605 must be display-only after 606 instead of becoming a standalone HP override")
ED_OVERRIDES_TEST = ed_overrides
end
do
local dhalsim_overrides, dhalsim_override_count, dhalsim_override_status =
    command_display_overrides.merge({
        _slim = true,
        ["1200"] = { classic = "236236+LP", status = "route_unverified" },
        ["1206"] = { classic = "236236+HP", status = "route_unverified" },
    }, "Dhalsim", {
        schema = "xt.command_display_overrides.v1",
        character = "Dhalsim",
        entries = {
            ["1200"] = {
                classic = "236236+LP",
                replace = true,
                evidence = "verified SA1 LP route",
            },
            ["1206"] = {
                classic = "236236+HP",
                replace = true,
                evidence = "verified SA1 HP route",
            },
        },
    })
assert(dhalsim_override_status == "loaded" and dhalsim_override_count == 2
        and dhalsim_overrides["1200"].classic == "236236+LP"
        and dhalsim_overrides["1200"].status == "runtime_verified_override"
        and dhalsim_overrides["1206"].classic == "236236+HP"
        and dhalsim_overrides["1206"].status == "runtime_verified_override",
    "Dhalsim overrides must resolve the runtime-verified LP and HP SA1 Actions")
end
do
local terry_overrides, terry_override_count, terry_override_status =
    command_display_overrides.merge({
        _slim = true,
        ["609"] = { classic = "LK", status = "route_unverified" },
        ["612"] = { classic = "MK", status = "route_unverified" },
        ["955"] = { classic = "214+LK", status = "route_unverified" },
        ["956"] = { classic = "214+MK", status = "route_unverified" },
    }, "Terry", {
        schema = "xt.command_display_overrides.v1",
        character = "Terry",
        entries = {
            ["609"] = { classic = "LK", replace = true, evidence = "runtime audit" },
            ["612"] = { classic = "MK", replace = true, evidence = "runtime audit" },
            ["955"] = { classic = "214+LK", replace = true, evidence = "runtime audit" },
            ["956"] = { classic = "214+MK", replace = true, evidence = "runtime audit" },
        },
    })
assert(terry_override_status == "loaded" and terry_override_count == 4
        and terry_overrides["609"].classic == "LK"
        and terry_overrides["612"].classic == "MK"
        and terry_overrides["955"].classic == "214+LK"
        and terry_overrides["956"].classic == "214+MK"
        and terry_overrides["609"].status == "runtime_verified_override"
        and terry_overrides["612"].status == "runtime_verified_override"
        and terry_overrides["955"].status == "runtime_verified_override"
        and terry_overrides["956"].status == "runtime_verified_override",
    "Terry overrides must resolve the four runtime-verified Classic commands")
end
do
local zangief_overrides, zangief_override_count, zangief_override_status =
    command_display_overrides.merge({
        _slim = true,
        ["609"] = { classic = "HP", status = "route_unverified" },
        ["615"] = { classic = "HK", status = "route_unverified" },
        ["631"] = { classic = "2+MK", status = "route_unverified" },
        ["923"] = { classic = "41236+LK+MK", status = "route_unverified" },
        ["1020"] = { classic = "63214+KK", status = "route_unverified" },
    }, "Zangief", {
        schema = "xt.command_display_overrides.v1",
        character = "Zangief",
        contextual_internal_phases = {
            ["948"] = {
                owner_ids = { 945 },
                evidence = "verified 945 to 948 command throw contact phase",
            },
        },
        entries = {
            ["609"] = {
                classic = "HP",
                replace = true,
                evidence = "verified standing HP",
            },
            ["615"] = {
                classic = "HK",
                replace = true,
                evidence = "verified standing HK",
            },
            ["631"] = {
                classic = "2+MK",
                replace = true,
                evidence = "verified crouching MK",
            },
            ["923"] = {
                classic = "41236+LK+MK",
                replace = true,
                evidence = "verified command grab",
            },
            ["1020"] = {
                classic = "63214+KK",
                replace = true,
                evidence = "verified running bear grab",
            },
        },
    })
assert(zangief_override_status == "loaded" and zangief_override_count == 5
        and zangief_overrides["609"].classic == "HP"
        and zangief_overrides["609"].status == "runtime_verified_override"
        and zangief_overrides["615"].classic == "HK"
        and zangief_overrides["631"].classic == "2+MK"
        and zangief_overrides["923"].classic == "41236+LK+MK"
        and zangief_overrides["923"].status == "runtime_verified_override"
        and zangief_overrides["1020"].classic == "63214+KK"
        and command_display_overrides.is_contextual_internal_phase(
            zangief_overrides, 945, 948) == true
        and command_display_overrides.is_contextual_internal_phase(
            zangief_overrides, 900, 948) == false,
    "Zangief overrides must resolve verified normals and hide only the 945 to 948 contact phase")
ZANGIEF_OVERRIDES_TEST = zangief_overrides
end
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
SequenceGrouping = dofile("autorun/func/ComboTrials/SequenceGrouping.lua")
do
    local merge_group_block = assert(renderer_source:match(
    "(local function strip_line_leading_followup.-)\n%-%- =========================================================\n%-%- parse_motion_to_icons"))
    assert(load(merge_group_block
            .. "\n_G.merge_group_log_item = merge_group_log_item"
            .. "\n_G.display_line_log_item = display_line_log_item",
        "merge-group-log-item", "t", _G))()
    local standalone_followup_line = display_line_log_item({
        { motion = ">22+HP", has_hit = true },
    })
    local chained_followup_line = display_line_log_item({
        { motion = "2PP", has_hit = true },
        { motion = ">HP", has_hit = true },
    })
    local same_command_phase_line = display_line_log_item({
        { motion = "4 + 强", has_hit = false },
        { motion = "4 + 强", has_hit = true, _ct_same_command_phase = true },
    })
    assert(standalone_followup_line.motion == "22+HP"
            and chained_followup_line.motion == "2PP >HP"
            and same_command_phase_line.motion == "4 + 强"
            and same_command_phase_line.has_hit == true,
        "a line-leading follow-up marker must be hidden while an inline follow-up remains visible")
end
local classic_block = assert(renderer_source:match(
    "(local function get_player_visible_transition_motion.-)\nlocal function get_command_display"))
trim_string = function(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

CONTEXTUAL_EFFECT_BLOCK_TEST = assert(renderer_source:match(
    "(local function valid_contextual_effect_relation.-)\nlocal RUNTIME_COMMON_ACTIONS"))
assert(load(CONTEXTUAL_EFFECT_BLOCK_TEST
        .. "\n_G.valid_contextual_effect_relation = valid_contextual_effect_relation"
        .. "\n_G.same_contextual_effect_relation = same_contextual_effect_relation",
    "contextual-effect-relations", "t", _G))()

local semantic_block = assert(renderer_source:match(
    "(local function resolve_classic_common_semantic.-)\nbuild_slim_command_display_map = function"))
assert(load(semantic_block
        .. "\n_G.resolve_classic_common_semantic = resolve_classic_common_semantic"
        .. "\n_G.merge_followup_display = merge_followup_display",
    "classic-common-semantic", "t", _G))()
assert(merge_followup_display("空中 任意键", "空中 任意键") == "空中 任意键"
        and merge_followup_display("空中 任意键", "任意键") == "空中 任意键 > 任意键"
        and merge_followup_display("236+HP", "MP") == "236+HP > MP"
        and merge_followup_display(" 强 ", "强") == "强",
    "a followup whose display equals its source move must not duplicate the same command token")

do
local slim_map_block = assert(renderer_source:match(
    "(build_slim_command_display_map = function.-)\n\nlocal function get_classic_display_motion"))
assert(load(slim_map_block, "slim-command-display-map", "t", _G))()
end

assert(load(classic_block .. "\n_G.get_classic_display_motion = get_classic_display_motion"
    .. "\n_G.get_modern_display_motion = get_modern_display_motion"
    .. "\n_G.project_historical_action_step = project_historical_action_step"
    .. "\n_G.get_player_visible_transition_motion = get_player_visible_transition_motion",
    "classic-command-resolution", "t", _G))()
local validation_block = assert(renderer_source:match(
    "(local function select_modern_display_motion.-)\nlocal function build_display_lines"
))
TYPE20_DELAYED_EFFECT_REASON = "ac_type20_multi_owner_delayed_contact_effect"
assert(load(validation_block
        .. "\n_G.resolve_step_command_display = resolve_step_command_display"
        .. "\n_G.resolve_contextual_step_command_display = resolve_contextual_step_command_display"
        .. "\n_G.resolve_live_log_command_displays = resolve_live_log_command_displays"
        .. "\n_G.apply_presentation_context = apply_presentation_context"
        .. "\n_G.setup_followup_child_sources = setup_followup_child_sources"
        .. "\n_G.is_internal_bridge_candidate = is_internal_bridge_candidate"
        .. "\n_G.compute_internal_bridge_suppressions = compute_internal_bridge_suppressions"
        .. "\n_G.compute_contextual_effect_line_breaks = compute_contextual_effect_line_breaks"
        .. "\n_G.requires_separate_display_line = requires_separate_display_line"
        .. "\n_G.validate_sequence_command_display = validate_sequence_command_display",
    "command-display-validation", "t", _G))()

do
    local bridge_map = {
        _slim = true,
        _followup_relations = {
            { type = "followup", source_action_id = 918, target_action_id = 939 },
        },
        ["918"] = { classic = ">j.K", commands = { simple = "空中 任意键", motion = "空中 任意键" } },
        ["921"] = {
            classic = "HK",
            commands = { simple = "强", motion = "强" },
            metadata = { source = "command_display_override" },
        },
        ["939"] = { classic = ">j.P", commands = { simple = "空中 任意键", motion = "空中 任意键" } },
    }
    local suppressed = compute_internal_bridge_suppressions(
        { { id = 910 }, { id = 918 }, { id = 921 }, { id = 939 } }, bridge_map)
    assert(suppressed[3] == true and suppressed[2] == nil,
        "a BCM-route-less step enveloped by a followup relation must be hidden as an internal bridge")
    assert(setup_followup_child_sources(bridge_map)[939] == 918,
        "followup child/source lookup must derive from the catalog relation")
    local normal_map = {
        _slim = true,
        _followup_relations = {
            { type = "followup", source_action_id = 918, target_action_id = 939 },
        },
        ["918"] = { commands = { simple = "空中 任意键" } },
        ["921"] = { commands = { simple = "强" } },
        ["939"] = { commands = { simple = "空中 任意键" } },
    }
    local not_suppressed = compute_internal_bridge_suppressions(
        { { id = 918 }, { id = 921 }, { id = 939 } }, normal_map)
    assert(not_suppressed[2] == nil,
        "a normal catalog Action must not be hidden by the internal-bridge rule")
end

do
    CONTEXTUAL_EFFECT_MAP_TEST = {
        _slim = true,
        _contextual_effect_relations = {
            {
                source_action_ids = { 975, 977 },
                target_action_id = 979,
                branch_type = 20,
                attr = 288,
                action_frame = 9,
                param00 = 1,
                param01 = 8,
                param02 = 1,
                param03 = 2,
                param04 = 0,
                param05 = 0,
                trigger_id = -1,
                fingerprint_fields = { "Category", "Combo", "Projectile", "State" },
                reason = "ac_type20_multi_owner_delayed_contact_effect",
            },
        },
        ["715"] = { classic = "Throw", status = "strict_route" },
        ["979"] = { classic = ">22+HP", status = "strict_route" },
    }
    CONTEXTUAL_EFFECT_LINE_BREAKS_TEST = compute_contextual_effect_line_breaks({
        { id = 715, group_id = 2, expected_combo = 2, damage_at_step = 861,
            has_contact = true, has_hit = true },
        { id = 979, group_id = 2, delay_from_prev = 119,
            expected_combo = 3, damage_at_step = 1221,
            has_contact = true, has_hit = true },
    }, CONTEXTUAL_EFFECT_MAP_TEST)
    assert(CONTEXTUAL_EFFECT_LINE_BREAKS_TEST[2] == true
            and CONTEXTUAL_EFFECT_LINE_BREAKS_TEST[1] == nil,
        "a dual-role command after contact must start a new presentation line")
    assert(requires_separate_display_line(nil, true) == true
            and requires_separate_display_line({ separate_line = true }, false) == true
            and requires_separate_display_line(nil, false) == false,
        "validation and runtime rendering must share one separate-line decision")
    resolve_modern_display_context = function()
        return false, CONTEXTUAL_EFFECT_MAP_TEST, "StructuralFixture", "loaded", false
    end
    CONTEXTUAL_EFFECT_VALIDATION_TEST = validate_sequence_command_display({
        {
            id = 715,
            motion = "Throw",
            group_id = 2,
            expected_combo = 2,
            damage_at_step = 861,
            has_contact = true,
            has_hit = true,
            _xt_meta = { character = "StructuralFixture", language = "zh-CN" },
        },
        {
            id = 979,
            motion = ">22+HP",
            group_id = 2,
            delay_from_prev = 119,
            expected_combo = 3,
            damage_at_step = 1221,
            has_contact = true,
            has_hit = true,
        },
    })
    assert(CONTEXTUAL_EFFECT_VALIDATION_TEST.ok == true
            and CONTEXTUAL_EFFECT_VALIDATION_TEST.visible_step_count == 2
            and CONTEXTUAL_EFFECT_VALIDATION_TEST.visible_line_count == 2
            and CONTEXTUAL_EFFECT_VALIDATION_TEST.steps[1].display_motion == "Throw"
            and CONTEXTUAL_EFFECT_VALIDATION_TEST.steps[2].display_motion == ">22+HP"
            and CONTEXTUAL_EFFECT_VALIDATION_TEST.steps[2].classification == "resolved"
            and CONTEXTUAL_EFFECT_VALIDATION_TEST.steps[1].visible_line_index == 1
            and CONTEXTUAL_EFFECT_VALIDATION_TEST.steps[2].visible_line_index == 2,
        "a real dual-role command must remain visible but not merge into the preceding throw")
    CONTEXTUAL_EFFECT_STANDALONE_TEST = compute_contextual_effect_line_breaks({
        { id = 979, group_id = 1, has_contact = false, has_hit = false },
    }, CONTEXTUAL_EFFECT_MAP_TEST)
    assert(CONTEXTUAL_EFFECT_STANDALONE_TEST[1] == nil,
        "the same dual-role Action needs no synthetic line break as a standalone setup command")
end

do
    local parser_block = assert(renderer_source:match(
        "(local function localize_motion_text.-)\n%-%- =========================================================\n%-%- get_render_logs"))
    MotionPresentation = MotionPresentation
        or require("func/ComboTrials/MotionPresentation")
    Validator = Validator or {
        counter_type_for_display = function() return 0 end,
    }
    assert(load(parser_block .. "\n_G.parse_motion_to_icons = parse_motion_to_icons",
        "command-icon-parser", "t", _G))()
end

local command_map = {
    _slim = true,
    _action_compatibility = HONDA_COMPATIBILITY_TEST,
    _presentation_contexts = merged_overrides._presentation_contexts,
    ["901"] = { classic = "214+MP", status = "strict_route" },
    ["958"] = { classic = "2+PP", status = "strict_route" },
    ["959"] = { classic = "236+K", status = "strict_route" },
    ["961"] = { classic = "236+KK", status = "strict_route" },
    ["965"] = { classic = ">2+P", status = "strict_route" },
    ["936"] = { classic = "PP", status = "strict_route" },
    ["967"] = { classic = ">6+LP", status = "strict_route" },
    ["968"] = { classic = ">6+MP", status = "strict_route" },
    ["969"] = { classic = ">6+HP", status = "strict_route" },
    ["973"] = { classic = "MP", status = "strict_route" },
    ["977"] = { classic = "HP", status = "runtime_verified_override" },
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

do
local state_direction_slim_map = build_slim_command_display_map({
    ["1048"] = {
        ownership = "ac_state_direction",
        routes = {},
        classic_command = { display = "4", inputs = { "4" } },
    },
})
assert(type(state_direction_slim_map["1048"].metadata) == "table"
        and state_direction_slim_map["1048"].metadata.ownership == "ac_state_direction",
    "slim command maps must preserve verified AC state-direction ownership")
end

local motion, status = get_classic_display_motion(command_map, { id = 901, motion = "Unknown" })
assert(motion == "214+MP" and status == "strict_route", "classic mode must use the unified command table")

do
RUNTIME_COMMON_ACTIONS = RUNTIME_COMMON_ACTIONS or {}
local classic_only_function3_map = {
    _meta = { character = "ClassicOnlyDirect" },
    ["8000"] = {
        ownership = "direct",
        classic_command = { display = "214214+HP", inputs = { "214214+HP" } },
        simple_command = nil,
        motion_command = nil,
        control_support = "classic_only",
        routes = { {
            display = "214214+HP",
            character = "ClassicOnlyDirect",
            owner_action_id = 8000,
            profile = "norm",
            source = "bcm_profile",
            projection_scope = "classic_only",
            confidence = "direct_structural",
            direct_evidence = true,
            inheritance_evidence = false,
            rebind_evidence = false,
            rebind_reason = nil,
            runtime_common_evidence = false,
            runtime_common_reason = nil,
            charge_context_evidence = false,
            super_shortcut_direction_evidence = false,
            ac_path = {},
        } },
    },
}
local route_motion, route_status = get_modern_display_motion(
    classic_only_function3_map, { id = 8000 })
assert(route_motion == "214214+HP" and route_status == "strict_route",
    "a Function 3 norm route must provide strict Classic verification evidence")
local classic_only_slim = build_slim_command_display_map(classic_only_function3_map)
local classic_motion, classic_status = get_classic_display_motion(
    classic_only_slim, { id = 8000, motion = "Unknown" })
assert(classic_motion == "214214+HP" and classic_status == "strict_route",
    "Classic presentation must consume the verified Function 3 norm route")
local modern_motion, modern_status = get_modern_display_motion(
    classic_only_slim, { id = 8000, motion = "Unknown" })
assert(modern_motion == nil and modern_status == "strict_route",
    "a classic-only verification route must not create a Modern command")
end

do
AC_TERMINAL_EXECUTION_PHASE_REASON =
    "ac_type2_type4_zero_parameter_terminal_execution_phase"
AC_NUMBERED_EXECUTION_PHASE_REASON =
    "ac_type2_numbered_same_structure_execution_phase"
AC_SAME_STRUCTURE_EXECUTION_PHASE_REASON =
    "ac_type2_same_structure_zero_parameter_execution_phase"
local terminal_evidence = {
    kind = "ac_type2_type4_terminal_execution_phase",
    source_action_id = 8200,
    target_action_id = 8201,
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
    reason = AC_TERMINAL_EXECUTION_PHASE_REASON,
}
local numbered_evidence = {
    kind = "ac_type2_numbered_execution_phase",
    source_action_id = 8210,
    middle_action_id = 8211,
    tail_action_id = 8212,
    exit_action_id = 8299,
    target_action_id = 8211,
    phase_index = 1,
    branch_type = 2,
    attr = 288,
    action_frame = 0,
    param00 = 1,
    param01 = 0,
    param02 = 0,
    param03 = 0,
    param04 = 0,
    param05 = 0,
    trigger_id = -1,
    exit_branch_type = 13,
    fingerprint_fields = { "Category", "Combo", "Projectile", "State" },
    reason = AC_NUMBERED_EXECUTION_PHASE_REASON,
}
local same_structure_evidence = {
    kind = "ac_type2_same_structure_execution_phase",
    source_action_id = 8230,
    middle_action_id = 8231,
    tail_action_id = 8232,
    target_action_id = 8231,
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
    fingerprint_fields = { "Category", "Combo", "Projectile", "State" },
    reason = AC_SAME_STRUCTURE_EXECUTION_PHASE_REASON,
}
AC_TYPE37_AUTOMATIC_EXECUTION_PHASE_REASON =
    "ac_type37_unique_automatic_execution_phase"
AC_TYPE13_TERMINAL_EXECUTION_PHASE_REASON =
    "ac_type13_zero_parameter_multi_owner_terminal_execution_phase"
AC_TYPE13_AIR_LANDING_EXECUTION_PHASE_REASON =
    "ac_type13_multi_owner_air_landing_execution_phase"
AC_TYPE36_TYPE13_EXECUTION_PHASE_REASON =
    "ac_type36_zero_parameter_phase_with_type13_terminal_exit"
local type37_automatic_evidence = {
    kind = "ac_type37_automatic_execution_phase",
    source_action_id = 8240,
    target_action_id = 8241,
    tail_action_id = 8242,
    branch_type = 37,
    action_frames = { 0, 10 },
    exit_branch_type = 12,
    exit_param01 = 4,
    exit_param02 = 190,
    fingerprint_fields = { "Category", "Combo", "Projectile", "State" },
    reason = AC_TYPE37_AUTOMATIC_EXECUTION_PHASE_REASON,
}
local type13_terminal_evidence = {
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
    reason = AC_TYPE13_TERMINAL_EXECUTION_PHASE_REASON,
}
local type13_air_landing_evidence = {
    kind = "ac_type13_air_landing_execution_phase",
    source_action_ids = { 650, 651, 652, 653, 654, 655, 656 },
    auxiliary_source_action_ids = { 1159, 1166 },
    target_action_id = 657,
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
            branch_type = 5, attr = 256, action_frame = 0,
            param00 = 0, param01 = 0, param02 = 0, param03 = 0,
            param04 = 0, param05 = 0, trigger_id = -1,
        },
        {
            branch_type = 54, attr = 256, action_frame = 0,
            param00 = 160, param01 = 0, param02 = 0, param03 = 0,
            param04 = 0, param05 = 0, trigger_id = -1,
        },
    },
    reason = AC_TYPE13_AIR_LANDING_EXECUTION_PHASE_REASON,
}
local type36_type13_evidence = {
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
    reason = AC_TYPE36_TYPE13_EXECUTION_PHASE_REASON,
}
local phase_map = {
    _meta = {
        character = "InternalPhase",
        suppressed_internal_transitions = {
            terminal_evidence, numbered_evidence, same_structure_evidence,
            type37_automatic_evidence, type13_terminal_evidence,
            type13_air_landing_evidence, type36_type13_evidence,
        },
    },
    ["8201"] = {
        ownership = "internal_execution_phase",
        suppress_display = true,
        routes = {},
        transition_evidence = terminal_evidence,
    },
    ["8211"] = {
        ownership = "internal_execution_phase",
        suppress_display = true,
        routes = {},
        transition_evidence = numbered_evidence,
    },
    ["8231"] = {
        ownership = "internal_execution_phase",
        suppress_display = true,
        routes = {},
        transition_evidence = same_structure_evidence,
    },
    ["8241"] = {
        ownership = "internal_execution_phase",
        suppress_display = true,
        routes = {},
        transition_evidence = type37_automatic_evidence,
    },
    ["944"] = {
        ownership = "internal_execution_phase",
        suppress_display = true,
        routes = {},
        transition_evidence = type13_terminal_evidence,
    },
    ["657"] = {
        ownership = "internal_execution_phase",
        suppress_display = true,
        routes = {},
        transition_evidence = type13_air_landing_evidence,
    },
    ["1024"] = {
        ownership = "internal_execution_phase",
        suppress_display = true,
        routes = {},
        transition_evidence = type36_type13_evidence,
    },
}
local terminal_motion, terminal_status = get_modern_display_motion(phase_map, { id = 8201 })
assert(terminal_motion == nil and terminal_status == "suppress_transition",
    "an exact Type 2+4 terminal execution phase must remain hidden")
local numbered_motion, numbered_status = get_modern_display_motion(phase_map, { id = 8211 })
assert(numbered_motion == nil and numbered_status == "suppress_transition",
    "an exact numbered execution phase must remain hidden")
local same_structure_motion, same_structure_status =
    get_modern_display_motion(phase_map, { id = 8231 })
assert(same_structure_motion == nil and same_structure_status == "suppress_transition",
    "an exact same-structure execution phase must remain hidden")
local type37_automatic_motion, type37_automatic_status =
    get_modern_display_motion(phase_map, { id = 8241 })
assert(type37_automatic_motion == nil and type37_automatic_status == "suppress_transition",
    "an exact Type37 automatic execution phase must remain hidden")
local type13_terminal_motion, type13_terminal_status =
    get_modern_display_motion(phase_map, { id = 944 })
assert(type13_terminal_motion == nil and type13_terminal_status == "suppress_transition",
    "an exact multi-owner Type13 terminal execution phase must remain hidden")
local type13_air_landing_motion, type13_air_landing_status =
    get_modern_display_motion(phase_map, { id = 657 })
assert(type13_air_landing_motion == nil
        and type13_air_landing_status == "suppress_transition",
    "an exact multi-owner Type13 air-landing execution phase must remain hidden")
local type36_type13_motion, type36_type13_status =
    get_modern_display_motion(phase_map, { id = 1024 })
assert(type36_type13_motion == nil and type36_type13_status == "suppress_transition",
    "an exact Type36 phase with a Type13 terminal exit must remain hidden")
local phase_slim = build_slim_command_display_map(phase_map)
assert(phase_slim["8201"].status == "suppress_transition"
        and phase_slim["8211"].status == "suppress_transition"
        and phase_slim["8231"].status == "suppress_transition"
        and phase_slim["8241"].status == "suppress_transition"
        and phase_slim["944"].status == "suppress_transition"
        and phase_slim["657"].status == "suppress_transition"
        and phase_slim["1024"].status == "suppress_transition",
    "slim cache construction must preserve audited transition suppression")
type37_automatic_evidence.action_frames[2] = 0
type37_automatic_motion, type37_automatic_status =
    get_modern_display_motion(phase_map, { id = 8241 })
assert(type37_automatic_motion == nil and type37_automatic_status == "invalid_suppress_transition",
    "a malformed Type37 automatic execution phase must fail closed")
type37_automatic_evidence.action_frames[2] = 10
numbered_evidence.attr = 32
numbered_motion, numbered_status = get_modern_display_motion(phase_map, { id = 8211 })
assert(numbered_motion == nil and numbered_status == "invalid_suppress_transition",
    "a mutated numbered execution phase declaration must fail closed")
numbered_evidence.attr = 288
type13_terminal_evidence.source_action_ids = { 940, 943, 942 }
type13_terminal_motion, type13_terminal_status =
    get_modern_display_motion(phase_map, { id = 944 })
assert(type13_terminal_motion == nil and type13_terminal_status == "invalid_suppress_transition",
    "an unsorted or incomplete Type13 owner set must fail closed")
type13_terminal_evidence.source_action_ids = { 940, 941, 942, 943 }
type13_air_landing_evidence.auxiliary_branches[2].param00 = 159
type13_air_landing_motion, type13_air_landing_status =
    get_modern_display_motion(phase_map, { id = 657 })
assert(type13_air_landing_motion == nil
        and type13_air_landing_status == "invalid_suppress_transition",
    "a malformed air-landing auxiliary relation must fail closed")
type13_air_landing_evidence.auxiliary_branches[2].param00 = 160
end

do
TYPE20_TERMINAL_COMMAND_PHASE_REASON =
    "ac_type20_complete_punch_strength_terminal_command_phase"
local terminal_signatures = {
    { attr = 256, action_frame = 0, param00 = 0, param01 = 112, param02 = 0, param03 = 1 },
    { attr = 256, action_frame = 0, param00 = 0, param01 = 32, param02 = 0, param03 = 2 },
    { attr = 256, action_frame = 0, param00 = 0, param01 = 256, param02 = 0, param03 = 3 },
}
local terminal_relation = {
    source_action_id = 965,
    target_action_id = 966,
    branch_type = 20,
    signatures = terminal_signatures,
    fingerprint_fields = { "Category", "Combo", "Projectile", "State" },
    reason = TYPE20_TERMINAL_COMMAND_PHASE_REASON,
}
local terminal_route = {
    display = "2 + SP",
    character = "Kimberly",
    owner_action_id = 965,
    display_action_id = 966,
    bcm_owner_action_id = 965,
    source = "ac_type20_terminal_command_phase",
    ac_relation_type = 20,
    ac_path = { 965, 966 },
    inherited_from_action_id = 965,
    confidence = "verified_inherited_action_phase",
    direct_evidence = false,
    inheritance_evidence = true,
    inheritance_reason = TYPE20_TERMINAL_COMMAND_PHASE_REASON,
    rebind_evidence = false,
    runtime_common_evidence = false,
    official_semantic_evidence = false,
    community_semantic_evidence = false,
    assist_combo_evidence = false,
    charge_context_evidence = false,
    super_shortcut_direction_evidence = false,
    ac_phase_signatures = terminal_signatures,
    ac_fingerprint_fields = { "Category", "Combo", "Projectile", "State" },
}
local terminal_map = {
    _meta = {
        character = "Kimberly",
        type20_terminal_command_phase_relations = { terminal_relation },
    },
    ["966"] = {
        ownership = "type20_action_phase",
        routes = { terminal_route },
    },
}
local terminal_inherited_motion, terminal_inherited_status =
    get_modern_display_motion(terminal_map, { id = 966 })
assert(terminal_inherited_motion == "2 + SP" and terminal_inherited_status == "strict_route",
    "a complete punch-strength Type20 terminal phase must inherit one command")
terminal_route.ac_phase_signatures[1].param01 = 16
terminal_inherited_motion, terminal_inherited_status =
    get_modern_display_motion(terminal_map, { id = 966 })
assert(terminal_inherited_motion == nil and terminal_inherited_status == "route_unverified",
    "an incomplete Type20 punch-strength family must fail closed")
end

do
TYPE20_SIX_BRANCH_PHASE_REASON =
    "ac_type20_verified_six_branch_action_phase"
local signatures = {
    { attr = 0, action_frame = 5, param00 = 0, param01 = 64, param02 = 0, param03 = 1 },
    { attr = 256, action_frame = 0, param00 = 2, param01 = 64, param02 = 0, param03 = 1 },
    { attr = 0, action_frame = 5, param00 = 0, param01 = 256, param02 = 0, param03 = 2 },
    { attr = 256, action_frame = 0, param00 = 2, param01 = 256, param02 = 0, param03 = 2 },
    { attr = 0, action_frame = 5, param00 = 0, param01 = 16, param02 = 0, param03 = 3 },
    { attr = 0, action_frame = 5, param00 = 1, param01 = 16, param02 = 0, param03 = 3 },
}
local source_exit = {
    target_action_id = 687, branch_type = 0, attr = 0, action_frame = 5,
    param00 = 0, param01 = 0, param02 = 0, param03 = 0,
    param04 = 0, param05 = 0, trigger_id = -1,
}
local target_exit = {
    target_action_id = 685, branch_type = 5, attr = 0, action_frame = 8,
    param00 = 1, param01 = 0, param02 = 0, param03 = 0,
    param04 = 0, param05 = 0, trigger_id = -1,
}
local relation = {
    source_action_id = 686,
    target_action_id = 684,
    branch_type = 20,
    signatures = signatures,
    source_exit_signature = source_exit,
    exit_signature = target_exit,
    reason = TYPE20_SIX_BRANCH_PHASE_REASON,
}
local route = {
    display = "4 + 强",
    character = "Marisa",
    owner_action_id = 686,
    display_action_id = 684,
    bcm_owner_action_id = 686,
    source = "ac_type20_six_branch_action_phase",
    ac_relation_type = 20,
    ac_path = { 686, 684 },
    inherited_from_action_id = 686,
    confidence = "verified_inherited_action_phase",
    direct_evidence = false,
    inheritance_evidence = true,
    inheritance_reason = TYPE20_SIX_BRANCH_PHASE_REASON,
    rebind_evidence = false,
    runtime_common_evidence = false,
    official_semantic_evidence = false,
    community_semantic_evidence = false,
    assist_combo_evidence = false,
    charge_context_evidence = false,
    super_shortcut_direction_evidence = false,
    ac_phase_signatures = signatures,
    ac_source_exit_signature = source_exit,
    ac_exit_signature = target_exit,
}
local six_branch_map = {
    _meta = {
        character = "Marisa",
        type20_action_phase_relations = { relation },
    },
    ["684"] = {
        ownership = "type20_action_phase",
        routes = { route },
    },
}
local six_branch_motion, six_branch_status =
    get_modern_display_motion(six_branch_map, { id = 684 })
assert(six_branch_motion == "4 + 强" and six_branch_status == "strict_route",
    "a strict six-branch Type20 phase must inherit its direct BCM owner command")
route.ac_exit_signature.action_frame = 7
six_branch_motion, six_branch_status =
    get_modern_display_motion(six_branch_map, { id = 684 })
assert(six_branch_motion == nil and six_branch_status == "route_unverified",
    "a mutated six-branch Type20 exit must fail closed")
end

do
TYPE20_SAME_STRUCTURE_PHASE_REASON =
    "ac_type20_verified_same_structure_execution_phase"
local signatures = {
    { attr = 0, action_frame = 4, param00 = 0, param01 = 64, param02 = 0, param03 = 1 },
    { attr = 256, action_frame = 0, param00 = 0, param01 = 64, param02 = 0, param03 = 1 },
    { attr = 0, action_frame = 4, param00 = 0, param01 = 256, param02 = 0, param03 = 2 },
    { attr = 256, action_frame = 0, param00 = 0, param01 = 256, param02 = 0, param03 = 2 },
    { attr = 256, action_frame = 0, param00 = 0, param01 = 256, param02 = 0, param03 = 3 },
    { attr = 256, action_frame = 0, param00 = 1, param01 = 256, param02 = 0, param03 = 3 },
}
local relation = {
    source_action_id = 976,
    target_action_id = 977,
    branch_type = 20,
    signatures = signatures,
    fingerprint_fields = { "Category", "Combo", "Projectile", "State" },
    reason = TYPE20_SAME_STRUCTURE_PHASE_REASON,
}
local route = {
    display = "强",
    character = "Alex",
    owner_action_id = 976,
    display_action_id = 977,
    bcm_owner_action_id = 976,
    source = "ac_type20_same_structure_execution_phase",
    ac_relation_type = 20,
    ac_path = { 976, 977 },
    inherited_from_action_id = 976,
    confidence = "verified_inherited_action_phase",
    direct_evidence = false,
    inheritance_evidence = true,
    inheritance_reason = TYPE20_SAME_STRUCTURE_PHASE_REASON,
    rebind_evidence = false,
    runtime_common_evidence = false,
    official_semantic_evidence = false,
    community_semantic_evidence = false,
    assist_combo_evidence = false,
    charge_context_evidence = false,
    super_shortcut_direction_evidence = false,
    ac_phase_signatures = signatures,
    ac_fingerprint_fields = { "Category", "Combo", "Projectile", "State" },
}
local map = {
    _meta = {
        character = "Alex",
        type20_same_structure_execution_relations = { relation },
    },
    ["977"] = {
        ownership = "type20_action_phase",
        routes = { route },
    },
}
local inherited_motion, inherited_status = get_modern_display_motion(map, { id = 977 })
assert(inherited_motion == "强" and inherited_status == "strict_route",
    "the runtime must admit a fully audited Type20 same-structure execution phase")
route.ac_phase_signatures[6].param00 = 0
inherited_motion, inherited_status = get_modern_display_motion(map, { id = 977 })
assert(inherited_motion == nil and inherited_status == "route_unverified",
    "a mutated Type20 same-structure phase must fail closed")
end

do
local legacy_honda_resolution = resolve_step_command_display(
    command_map, { id = 955, motion = "236+K" }, false)
assert(legacy_honda_resolution.motion == "236+K"
        and legacy_honda_resolution.projected_action_id == 959
        and legacy_honda_resolution.effective_action_id == 959,
    "legacy Honda commands must project to the current catalog Action")
local overlapping_honda_resolution = resolve_step_command_display(
    command_map, { id = 961, motion = ">2+P" }, false)
assert(overlapping_honda_resolution.motion == ">2+P"
        and overlapping_honda_resolution.projected_action_id == 965
        and overlapping_honda_resolution.effective_action_id == 965,
    "motion guards must disambiguate a reused Honda Action ID")
local current_honda_resolution = resolve_step_command_display(
    command_map, { id = 961, motion = "236+KK" }, false)
assert(current_honda_resolution.motion == "236+KK"
        and current_honda_resolution.projected_action_id == nil
        and current_honda_resolution.effective_action_id == 961,
    "current Honda recordings must retain the current meaning of reused Action IDs")
end

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

motion, status = get_classic_display_motion(command_map, { id = 967, motion = ">6+P" })
assert(motion == ">6+LP" and status == "strict_route",
    "a current catalog strength must refine a generic historical follow-up display")

motion, status = get_classic_display_motion(command_map, { id = 968, motion = ">6+MP" })
assert(motion == ">6+MP" and status == "recorded_context",
    "an already precise historical follow-up must remain unchanged")

motion, status = get_classic_display_motion(command_map, { id = 967, motion = ">6+P (WHIFF)" })
assert(motion == ">6+P (WHIFF)" and status == "recorded_context",
    "strength refinement must not discard historical contextual annotations")

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

TYPE63_STRENGTH_REASON = "ac_type63_classic_modern_strength_family"
TYPE63_STRENGTH_TEST = {}
TYPE63_STRENGTH_TEST.route = {
    display = "> 6 + 中",
    character = "Generic",
    owner_action_id = 1700,
    display_action_id = 1701,
    bcm_owner_action_id = 1700,
    source = "ac_type63_strength_variant",
    ac_relation_type = 63,
    ac_path = { 1700, 1701 },
    inherited_from_action_id = 1700,
    confidence = "verified_inherited_strength_variant",
    direct_evidence = false,
    inheritance_evidence = true,
    inheritance_reason = TYPE63_STRENGTH_REASON,
    rebind_evidence = false,
    rebind_reason = nil,
    runtime_common_evidence = false,
    runtime_common_reason = nil,
    official_semantic_evidence = false,
    official_semantic_reason = nil,
    community_semantic_evidence = false,
    community_semantic_reason = nil,
    assist_combo_evidence = false,
    assist_combo_reason = nil,
    charge_context_evidence = false,
    super_shortcut_direction_evidence = false,
    visible_direction = "6",
    visible_button = "中",
    button_candidates = { "中" },
    required_button_count = 1,
    strength = "medium",
    classic_param01 = 32,
    modern_param01 = 128,
}
TYPE63_STRENGTH_TEST.map = {
    _meta = {
        character = "Generic",
        type63_strength_variant_relation_count = 2,
        type63_strength_variant_route_count = 2,
        type63_strength_variant_relations = {
            {
                source_action_id = 1700,
                target_action_id = 1701,
                branch_type = 63,
                strength = "medium",
                classic_param01 = 32,
                modern_param01 = 128,
                reason = TYPE63_STRENGTH_REASON,
            },
            {
                source_action_id = 1700,
                target_action_id = 1702,
                branch_type = 63,
                strength = "heavy",
                classic_param01 = 64,
                modern_param01 = 256,
                reason = TYPE63_STRENGTH_REASON,
            },
        },
        audit = {
            type63_strength_variant_relation_count = 2,
            type63_strength_variant_route_count = 2,
        },
    },
    ["1700"] = {
        ownership = "direct",
        classic_command = { display = ">6+LP", inputs = { ">6+LP" } },
        routes = { {
            display = "> 6 + 任意键",
            character = "Generic",
            owner_action_id = 1700,
            source = "bcm_profile",
            direct_evidence = true,
            inheritance_evidence = false,
            rebind_evidence = false,
            runtime_common_evidence = false,
            official_semantic_evidence = false,
            community_semantic_evidence = false,
            assist_combo_evidence = false,
            confidence = "direct_structural",
            visible_direction = "6",
            visible_button = "任意键",
            button_candidates = { "弱", "中", "强" },
            required_button_count = 1,
        } },
    },
    ["1701"] = {
        ownership = "type63_strength_variant",
        classic_command = { display = ">6+MP", inputs = { ">6+MP" } },
        simple_command = nil,
        motion_command = { display = "> 6 + 中", inputs = { "> 6 + 中" } },
        routes = { TYPE63_STRENGTH_TEST.route },
    },
    ["1702"] = {
        ownership = "type63_strength_variant",
        classic_command = { display = ">6+HP", inputs = { ">6+HP" } },
        simple_command = nil,
        motion_command = { display = "> 6 + 强", inputs = { "> 6 + 强" } },
        routes = { {
            display = "> 6 + 强",
            character = "Generic",
            owner_action_id = 1700,
            display_action_id = 1702,
            bcm_owner_action_id = 1700,
            source = "ac_type63_strength_variant",
            ac_relation_type = 63,
            ac_path = { 1700, 1702 },
            inherited_from_action_id = 1700,
            confidence = "verified_inherited_strength_variant",
            direct_evidence = false,
            inheritance_evidence = true,
            inheritance_reason = TYPE63_STRENGTH_REASON,
            rebind_evidence = false,
            runtime_common_evidence = false,
            official_semantic_evidence = false,
            community_semantic_evidence = false,
            assist_combo_evidence = false,
            visible_direction = "6",
            visible_button = "强",
            button_candidates = { "强" },
            required_button_count = 1,
            strength = "heavy",
            classic_param01 = 64,
            modern_param01 = 256,
        } },
    },
}
motion, status = get_modern_display_motion(TYPE63_STRENGTH_TEST.map, { id = 1701 })
assert(motion == "> 6 + 中" and status == "strict_route",
    "Presentation must admit an audited generic Type63 strength variant")
motion, status = get_modern_display_motion(TYPE63_STRENGTH_TEST.map, { id = 1702 })
assert(motion == "> 6 + 强" and status == "strict_route",
    "Presentation must admit the symmetric heavy Type63 strength variant")
TYPE63_STRENGTH_TEST.slim = build_slim_command_display_map(TYPE63_STRENGTH_TEST.map)
assert(TYPE63_STRENGTH_TEST.slim["1701"].classic == ">6+MP"
        and TYPE63_STRENGTH_TEST.slim["1701"].commands.motion == "> 6 + 中"
        and TYPE63_STRENGTH_TEST.slim["1701"].status == "strict_route",
    "the slim Presentation map must preserve audited Type63 Classic and Modern commands")
assert(TYPE63_STRENGTH_TEST.slim["1702"].classic == ">6+HP"
        and TYPE63_STRENGTH_TEST.slim["1702"].commands.motion == "> 6 + 强"
        and TYPE63_STRENGTH_TEST.slim["1702"].status == "strict_route",
    "the slim Presentation map must preserve the heavy Type63 command")

TYPE63_STRENGTH_TEST.route.modern_param01 = 256
motion, status = get_modern_display_motion(TYPE63_STRENGTH_TEST.map, { id = 1701 })
assert(motion == nil and status == "route_unverified",
    "Presentation must reject mismatched Classic/Modern strength parameters")
TYPE63_STRENGTH_TEST.route.modern_param01 = 128
TYPE63_STRENGTH_TEST.route.visible_button = "强"
motion, status = get_modern_display_motion(TYPE63_STRENGTH_TEST.map, { id = 1701 })
assert(motion == nil and status == "route_unverified",
    "Presentation must reject a Type63 route with the wrong visible strength")
TYPE63_STRENGTH_TEST.route.visible_button = "中"
TYPE63_STRENGTH_TEST.route.owner_action_id = 1701
motion, status = get_modern_display_motion(TYPE63_STRENGTH_TEST.map, { id = 1701 })
assert(motion == nil and status == "route_unverified",
    "Presentation must reject a Type63 route whose BCM owner changed")
TYPE63_STRENGTH_TEST.route.owner_action_id = 1700
TYPE63_STRENGTH_TEST.map._meta.audit.type63_strength_variant_relation_count = nil
motion, status = get_modern_display_motion(TYPE63_STRENGTH_TEST.map, { id = 1701 })
assert(motion == nil and status == "route_unverified",
    "Presentation must reject Type63 display text without complete audit evidence")
TYPE63_STRENGTH_TEST.map._meta.audit.type63_strength_variant_relation_count = 2

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
    return false, command_map, "Alex", "loaded", false
end
ALEX_STANCE_VALIDATION_TEST = validate_sequence_command_display({
    {
        id = 958,
        motion = "2+PP",
        group_id = 1,
        _xt_meta = { character = "Alex", language = "zh-CN" },
    },
    { id = 973, motion = "MP", group_id = 2 },
    { id = 958, motion = "2+PP", group_id = 3 },
    { id = 967, motion = ">6+P", group_id = 3 },
    { id = 958, motion = "2+PP", group_id = 4 },
    { id = 977, motion = ">HP (INSTANT)", group_id = 4 },
})
assert(ALEX_STANCE_VALIDATION_TEST.ok == true
        and ALEX_STANCE_VALIDATION_TEST.visible_step_count == 6
        and ALEX_STANCE_VALIDATION_TEST.visible_line_count == 6
        and ALEX_STANCE_VALIDATION_TEST.steps[2].display_motion
            == "（破坏姿势中） MP"
        and ALEX_STANCE_VALIDATION_TEST.steps[4].display_motion
            == "（破坏姿势中/前滑步中） 6+LP"
        and ALEX_STANCE_VALIDATION_TEST.steps[4].visible_line_index == 4
        and ALEX_STANCE_VALIDATION_TEST.steps[4].presentation_context.separate_line == true
        and ALEX_STANCE_VALIDATION_TEST.steps[6].display_motion
            == "（破坏姿势中） HP"
        and ALEX_STANCE_VALIDATION_TEST.steps[6].visible_line_index == 6
        and ALEX_STANCE_VALIDATION_TEST.steps[6].presentation_context
            .replace_recorded_context == true,
    "Alex stance commands must display official context on independent lines")
do
    local alex_contextual_heavy = apply_presentation_context(
        command_map, 977, "强", "zh-CN")
    local alex_contextual_heavy_tokens = parse_motion_to_icons({
        motion = alex_contextual_heavy,
        _ct_modern_display = true,
    }, "playing", false, true)
    assert(alex_contextual_heavy == "（破坏姿势中） 强"
            and #alex_contextual_heavy_tokens == 2
            and alex_contextual_heavy_tokens[1].type == "text"
            and alex_contextual_heavy_tokens[1].val == "（破坏姿势中）"
            and alex_contextual_heavy_tokens[2].type == "img"
            and alex_contextual_heavy_tokens[2].val == "modern_h",
        "a localized presentation label must keep the Modern strength as an icon")
end

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

do
    local yasmine_drift_map = select(1, command_display_overrides.merge({
        _slim = true,
        ["970"] = { classic = "4+HP", status = "strict_route" },
    }, "Yasmine", {
        schema = "xt.command_display_overrides.v1",
        character = "Yasmine",
        entries = {
            ["970"] = {
                classic = "236+HP",
                replace = true,
                require_recorded_motion_match = true,
                evidence = "verified Yasmine heavy Daloy ng Tubig command",
            },
        },
    }))
    resolve_modern_display_context = function()
        return false, yasmine_drift_map, "Yasmine", "loaded", false
    end
    local stale_recording = validate_sequence_command_display({
        { id = 970, motion = "4+HP" },
    })
    assert(stale_recording.ok == false
            and stale_recording.status == "recorded_motion_drift"
            and stale_recording.recorded_motion_drift_count == 1
            and stale_recording.recorded_motion_drift[1].index == 1
            and stale_recording.steps[1].display_motion == "236+HP"
            and stale_recording.steps[1].require_recorded_motion_match == true
            and stale_recording.steps[1].recorded_motion_matches == false,
        "an explicitly guarded override must display the authoritative command but fail stale saved motion")
    local current_recording = validate_sequence_command_display({
        { id = 970, motion = "236+HP" },
    })
    assert(current_recording.ok == true
            and current_recording.recorded_motion_drift_count == 0
            and current_recording.steps[1].recorded_motion_matches == true,
        "a newly recorded authoritative command must pass the guarded override")
end

resolve_modern_display_context = function()
    return false, BLANKA_OVERRIDES_TEST, "Blanka", "loaded", false
end
BLANKA_STRICT_VALIDATION_TEST = validate_sequence_command_display({
    { id = 613, motion = "2+LP", group_id = 1 },
    { id = 614, motion = "2+LP", group_id = 2 },
    { id = 924, motion = "214+LP+LK+MK", group_id = 3 },
    { id = 931, motion = "214+LP+LK+MK", group_id = 4 },
})
assert(BLANKA_STRICT_VALIDATION_TEST.ok == true
        and BLANKA_STRICT_VALIDATION_TEST.resolved_step_count == 4
        and BLANKA_STRICT_VALIDATION_TEST.visible_step_count == 4
        and BLANKA_STRICT_VALIDATION_TEST.visible_line_count == 4
        and #BLANKA_STRICT_VALIDATION_TEST.steps == 4
        and BLANKA_STRICT_VALIDATION_TEST.steps[1].source_action_id == 613
        and BLANKA_STRICT_VALIDATION_TEST.steps[1].visible_line_index == 1
        and BLANKA_STRICT_VALIDATION_TEST.steps[2].source_action_id == 614
        and BLANKA_STRICT_VALIDATION_TEST.steps[2].visible_line_index == 2
        and BLANKA_STRICT_VALIDATION_TEST.steps[3].source_action_id == 924
        and BLANKA_STRICT_VALIDATION_TEST.steps[3].projected_action_id == 926
        and BLANKA_STRICT_VALIDATION_TEST.steps[3].effective_action_id == 926
        and BLANKA_STRICT_VALIDATION_TEST.steps[3].display_motion == "214+P"
        and BLANKA_STRICT_VALIDATION_TEST.steps[4].effective_action_id == 931
        and BLANKA_STRICT_VALIDATION_TEST.steps[4].display_motion == "214+PP",
    "Blanka validation must retain both 2LP rows and project legacy Actions to correct punch notation")

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

do
local ed_overrides = ED_OVERRIDES_TEST
for action_id, classic in pairs({
    ["600"] = "LP",
    ["601"] = "LP",
    ["602"] = "LP",
    ["900"] = "236+P",
    ["959"] = "236+KK",
}) do
    ed_overrides[action_id] = {
        classic = classic,
        status = "strict_route",
    }
end
resolve_modern_display_context = function()
    return false, ed_overrides, "Ed", "loaded", false
end
local ed_internal_phase_validation = validate_sequence_command_display({
    { id = 606, motion = "HP" },
    { id = 605, motion = "HP" },
})
assert(ed_internal_phase_validation.ok == true
        and ed_internal_phase_validation.total_steps == 2
        and ed_internal_phase_validation.resolved_step_count == 1
        and ed_internal_phase_validation.suppressed_step_count == 1
        and ed_internal_phase_validation.unresolved_count == 0,
    "Ed 606 then 605 must render as one HP instruction")
local standalone_ed_605_validation = validate_sequence_command_display({
    { id = 605, motion = "HP" },
})
assert(standalone_ed_605_validation.ok == false
        and standalone_ed_605_validation.suppressed_step_count == 0
        and standalone_ed_605_validation.unresolved_count == 1,
    "Ed Action 605 must fail closed without its immediate 606 owner")
local ed_real_repeat_validation = validate_sequence_command_display({
    { id = 600, motion = "LP" },
    { id = 601, motion = "LP" },
    { id = 602, motion = "LP" },
    { id = 959, motion = "236+KK" },
    { id = 959, motion = "236+KK" },
    { id = 900, motion = "236+P" },
    { id = 900, motion = "236+P" },
})
assert(ed_real_repeat_validation.ok == true
        and ed_real_repeat_validation.resolved_step_count == 7
        and ed_real_repeat_validation.suppressed_step_count == 0,
    "Ed's verified LP, 236+KK and 236+P repeats must remain visible")
end

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

MARISA_COMMAND_PHASE_MAP = {
    _slim = true,
    ["686"] = {
        commands = { motion = "4 + 强" },
        status = "strict_route",
    },
    ["684"] = {
        commands = { motion = "4 + 强" },
        status = "strict_route",
        metadata = {
            ownership = "type20_action_phase",
            inherited_from_action_id = 686,
        },
    },
}
resolve_modern_display_context = function()
    return true, MARISA_COMMAND_PHASE_MAP, "Marisa", "loaded", true
end
MARISA_COMMAND_PHASE_VALIDATION = validate_sequence_command_display({
    { id = 686, motion = "4+HP", group_id = 5, expected_combo = 0, has_hit = false },
    { id = 684, motion = "4+HP", group_id = 6, expected_combo = 6, has_hit = true },
})
assert(MARISA_COMMAND_PHASE_VALIDATION.ok == true
        and MARISA_COMMAND_PHASE_VALIDATION.visible_step_count == 2
        and MARISA_COMMAND_PHASE_VALIDATION.visible_line_count == 1
        and MARISA_COMMAND_PHASE_VALIDATION.steps[1].visible_line_index == 1
        and MARISA_COMMAND_PHASE_VALIDATION.steps[2].visible_line_index == 1
        and MARISA_COMMAND_PHASE_VALIDATION.steps[2].same_command_phase == true,
    "a validated Type20 command phase must preserve both Actions but render as one input line")

resolve_modern_display_context = function()
    return true, MBISON_GAME_AREA_MAP, "MBison", "loaded", false
end
for _, combo_name in ipairs({
    "MBison_OKI_214_HP_3640_D2.7_SA0",
    "MBison_OKI_214_HP_3870_D2.7_SA0",
    "MBison_OKI_214_HP_3870_D2.4_SA0",
    "MBison_OKI_214_LP_3560_D2_SA0",
}) do
    local validation = validate_sequence_command_display({
        { id = 910, motion = "[2]8+HK", group_id = 1 },
        { id = 918, motion = ">j.K", group_id = 1 },
        { id = 921, motion = "HK", group_id = 2 },
        { id = 939, motion = ">j.P", group_id = 2 },
    })
    assert(validation.ok == true
            and validation.mode == "modern"
            and validation.resolved_step_count == 3
            and validation.suppressed_step_count == 1
            and validation.unresolved_count == 0
            and validation.visible_step_count == 3
            and validation.visible_line_count == 1
            and validation.steps[3].source_action_id == 921
            and validation.steps[3].classification == "suppressed"
            and validation.steps[4].source_action_id == 939
            and validation.steps[4].classification == "resolved"
            and validation.steps[4].display_motion == "空中 任意键",
        "M. Bison game-area combo " .. combo_name
            .. " must hide the BCM-route-less bridge 921 and chain followup 939 onto line 8")
end

do
    -- Slim-map followup resolution must not depend on pairs() iteration order.
    -- A child such as 939 (source 918) used to lose its display when the
    -- unordered walk cleared the parent fields before the child was resolved
    -- (two-pass computation is order-free). Include an unrelated action so the
    -- hash layout differs from a bare pair, matching the live-game scenario.
    local function followup_catalog_map()
        local function direct(owner_id, display)
            return {
                display = display,
                character = "MBison",
                owner_action_id = owner_id,
                source = "bcm_profile",
                confidence = "direct_structural",
                direct_evidence = true,
                inheritance_evidence = false,
                inheritance_reason = nil,
                rebind_evidence = false,
                rebind_reason = nil,
                runtime_common_evidence = false,
                runtime_common_reason = nil,
                official_semantic_evidence = false,
                official_semantic_reason = nil,
                community_semantic_evidence = false,
                community_semantic_reason = nil,
                assist_combo_evidence = false,
                assist_combo_reason = nil,
                charge_context_evidence = false,
                super_shortcut_direction_evidence = false,
            }
        end
        return {
            _meta = { character = "MBison" },
            ["918"] = {
                classic_command = { display = ">j.K", inputs = { ">j.K" } },
                simple_command = { display = "空中 任意键", inputs = { "空中 任意键" } },
                motion_command = { display = "空中 任意键", inputs = { "空中 任意键" } },
                ownership = "direct",
                routes = { direct(918, "空中 任意键") },
            },
            ["939"] = {
                classic_command = { display = ">j.P", inputs = { ">j.P" } },
                simple_command = { display = "空中 任意键", inputs = { "空中 任意键" } },
                motion_command = { display = "空中 任意键", inputs = { "空中 任意键" } },
                ownership = "direct",
                relation = {
                    type = "followup",
                    source_action_id = 918,
                    evidence = "capcom_official_followup_context_matches_source_move",
                },
                routes = { direct(939, "空中 任意键") },
            },
            ["921"] = {
                classic_command = { display = "HK", inputs = { "HK" } },
                simple_command = { display = "强", inputs = { "强" } },
                motion_command = { display = "强", inputs = { "强" } },
                ownership = "direct",
                routes = { direct(921, "强") },
            },
        }
    end
    for _ = 1, 50 do
        local slim = build_slim_command_display_map(followup_catalog_map())
        local child = slim["939"]
        local parent = slim["918"]
        assert(type(parent.commands) == "table"
                and parent.commands.motion == "空中 任意键",
            "followup source 918 must keep a resolved command after slim build")
        assert(type(child.commands) == "table"
                and child.commands.motion == "空中 任意键",
            "followup child 939 must resolve regardless of slim-map iteration order")
    end
end

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
assert(action_matcher.matches_expected_action_id(
        { id = 961, motion = ">2+P" }, 965, nil, HONDA_COMPATIBILITY_TEST)
        and not action_matcher.matches_expected_action_id(
            { id = 961, motion = "236+KK" }, 965, nil, HONDA_COMPATIBILITY_TEST),
    "runtime matching must apply historical aliases only to the recorded motion")
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
do
local alex_hp_release_rule = {
    force = true,
    optional_parent_ids = "976",
}
assert(action_matcher.is_optional_parent_for_followup(
        "HP",
        { id = 977, motion = "HP" },
        976,
        alex_hp_release_rule,
        { id = 958, motion = "2+PP" },
        "HP"
    ) == true,
    "Alex's HP parent phase must wait for the recorded release Action 977")
assert(action_matcher.is_optional_parent_for_followup(
        "HP",
        { id = 977, motion = "HP" },
        977,
        alex_hp_release_rule,
        { id = 958, motion = "2+PP" },
        "HP"
    ) == false,
    "Alex's exact HP release Action 977 must remain eligible to complete the step")
end
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
local contextual_absorb_rule = {
    absorb_ids = "684",
    action_event_projection = { preserve_fresh_button_press = true },
}
assert(character_rules.should_preserve_absorbed_transition(
        contextual_absorb_rule,
        "button_press"
    ) == true
        and character_rules.should_preserve_absorbed_transition(
            contextual_absorb_rule,
            "button_release"
        ) == false
        and character_rules.should_preserve_absorbed_transition(
            contextual_absorb_rule,
            "direction_action"
        ) == false,
    "runtime absorption must preserve only explicitly configured fresh button presses")
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
local lily_932_rules = {
    ["932"] = {
        absorb_ids = "931",
        action_event_rules = {
            transient_precursor_ids = "931",
        },
    },
}
local lily_action_event_rules =
    character_rules.build_action_event_rules(lily_932_rules, {})
assert(lily_action_event_rules.transient_input_precursor_transitions[931][932]
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
local lily_932_expected = { id = 932, expected_combo = 6 }
local lily_932_canonical = character_rules.match_current_canonical_confirmation(
    lily_932_rules, {}, lily_932_expected, 931, 6, "Lily")
assert(lily_932_canonical.matched == false
        and lily_932_canonical.block_reason == "canonical_owner_projection_missing",
    "Lily must not canonicalize 931 through the absorb-only exception")
assert(action_matcher.matches_expected_action_id(
        lily_932_expected, 931, lily_932_rules["932"]) == false,
    "Lily's transient 931 precursor must not advance the 932 step through action_alias_ids")
local lily_transient_ignore = action_matcher.classify_runtime_transition({
    character = "Lily",
    expected_step = lily_932_expected,
    expected_action_matches_current = false,
    actual_action_id = 931,
    action_event_rules = lily_action_event_rules,
    input_anchor_kind = "button_press",
    input_truth_mode = true,
})
assert(lily_transient_ignore.ignored == true
        and lily_transient_ignore.reason == "transient_input_precursor",
    "the live trial must ignore Lily's 931 precursor while waiting for durable 932")
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
    "Lily's 931 precursor must not be ignored for a different expected step")
local ryu_transient_mismatch = action_matcher.classify_runtime_transition({
    character = "Ryu",
    expected_step = lily_932_expected,
    expected_action_matches_current = false,
    actual_action_id = 929,
    action_event_rules = {},
    input_anchor_kind = "button_press",
    input_truth_mode = true,
})
assert(ryu_transient_mismatch.ignored == false,
    "transient precursor ignoring must stay character-scoped")
local lily_932_early = character_rules.match_current_absorb_confirmation(
    lily_932_rules, {}, lily_932_expected, 931, 3, "Lily")
assert(lily_932_early.matched == false
        and lily_932_early.block_reason == "combo_not_reached",
    "Lily 931 chord precursor must wait for the durable 932 before combo is reached")
local lily_932_absorb = character_rules.match_current_absorb_confirmation(
    lily_932_rules, {}, lily_932_expected, 931, 6, "Lily")
assert(lily_932_absorb.matched == true
        and lily_932_absorb.actual_action_id == 931,
    "input-truth playback must admit Lily's transient 931 precursor through absorb_ids")
local lily_932_recent = character_rules.find_recent_absorb_confirmation(
    lily_932_rules,
    {},
    lily_932_expected,
    { { id = 931, combo_count = 6, start_frame = 100 } },
    "Lily"
)
assert(lily_932_recent.matched == true
        and lily_932_recent.actual_action_id == 931,
    "recent-input playback must retain the same Lily 931 absorb confirmation")
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
assert(lily_exception_source:find('"932"', 1, true)
        and lily_exception_source:find('"absorb_ids": "931"', 1, true)
        and lily_exception_source:find('"transient_precursor_ids": "931"', 1, true)
        and not lily_exception_source:find('"action_alias_ids": "931"', 1, true)
        and not lily_exception_source:find('"canonical_owner_ids": "931"', 1, true),
    "the shipped Lily exception must keep 931 as an absorb-only transient precursor")
local cammy_override_source = read_all(
    "data/TrainingComboTrials_data/command_display_overrides/Cammy.json")
assert(cammy_override_source:find('"609"', 1, true)
        and cammy_override_source:find('"classic": "LK"', 1, true)
        and cammy_override_source:find('"618"', 1, true)
        and cammy_override_source:find('"classic": "2+LP"', 1, true)
        and cammy_override_source:find('"750"', 1, true)
        and cammy_override_source:find('"classic": ">8"', 1, true)
        and cammy_override_source:find('"replace": true', 1, true),
    "the shipped Cammy command overrides must preserve runtime-verified commands")
do
    local honda_override_source = read_all(
        "data/TrainingComboTrials_data/command_display_overrides/EHonda.json")
    local honda_compatibility_source = read_all(
        "data/TrainingComboTrials_data/action_compatibility/EHonda.json")
    assert(honda_override_source:find('"608"', 1, true)
            and honda_override_source:find('"classic": "LK"', 1, true)
            and honda_override_source:find('"replace": true', 1, true),
        "the shipped Honda override must preserve the runtime-verified LK command")
    assert(honda_compatibility_source:find(
                '"target_game_version": "2026-08-03"', 1, true)
            and honda_compatibility_source:find(
                '"recorded_action_id": 955', 1, true)
            and honda_compatibility_source:find(
                '"runtime_action_id": 959', 1, true)
            and honda_compatibility_source:find(
                '"recorded_action_id": 961', 1, true)
            and honda_compatibility_source:find(
                '"runtime_action_id": 965', 1, true)
            and honda_compatibility_source:find(
                '"recorded_action_id": 977', 1, true)
            and honda_compatibility_source:find(
                '"runtime_action_id": 981', 1, true),
        "the shipped Honda compatibility map must retain verified ID migrations")
end
do
    local blanka_override_source = read_all(
        "data/TrainingComboTrials_data/command_display_overrides/Blanka.json")
    local blanka_compatibility_source = read_all(
        "data/TrainingComboTrials_data/action_compatibility/Blanka.json")
    local blanka_exception_source = read_all(
        "data/TrainingComboTrials_data/exceptions/Blanka.json")
    assert(blanka_override_source:find('"613"', 1, true)
            and blanka_override_source:find('"classic": "2+LP"', 1, true)
            and blanka_override_source:find('"926"', 1, true)
            and blanka_override_source:find('"classic": "214+P"', 1, true)
            and blanka_override_source:find('"931"', 1, true)
            and blanka_override_source:find('"classic": "214+PP"', 1, true)
            and blanka_override_source:find('"930"', 1, true)
            and blanka_override_source:find(
                '"classic": "236+LP+MP+HP"', 1, true)
            and blanka_override_source:find('"972"', 1, true)
            and blanka_override_source:find('"classic": "4+LK"', 1, true)
            and blanka_override_source:find('"1093"', 1, true)
            and blanka_override_source:find('"replace": true', 1, true)
            and not blanka_override_source:find(
                '"classic": "214+LP+LK+MK"', 1, true),
        "the shipped Blanka overrides must preserve all runtime-verified commands")
    assert(blanka_compatibility_source:find(
                '"target_game_version": "2026-08-03"', 1, true)
            and blanka_compatibility_source:find(
                '"recorded_action_id": 924', 1, true)
            and blanka_compatibility_source:find(
                '"runtime_action_id": 926', 1, true)
            and blanka_compatibility_source:find(
                '"recorded_motions": ["214+LP+LK+MK"]', 1, true),
        "the shipped Blanka compatibility map must retain the verified doll Action migration")
    assert(blanka_exception_source:find('"absorb_ids": "928,929,930"', 1, true)
            and blanka_exception_source:find('"action_event_projection": {}', 1, true),
        "the shipped Blanka rules must fold doll contact Action 930 into owner 931")
end
do
    local dhalsim_override_source = read_all(
        "data/TrainingComboTrials_data/command_display_overrides/Dhalsim.json")
    local dhalsim_exception_source = read_all(
        "data/TrainingComboTrials_data/exceptions/Dhalsim.json")
    assert(dhalsim_override_source:find('"1200"', 1, true)
            and dhalsim_override_source:find(
                '"classic": "236236+LP"', 1, true)
            and dhalsim_override_source:find('"1206"', 1, true)
            and dhalsim_override_source:find(
                '"classic": "236236+HP"', 1, true),
        "the shipped Dhalsim overrides must retain both runtime-verified SA1 commands")
    assert(dhalsim_exception_source:find('"642"', 1, true)
            and dhalsim_exception_source:find(
                '"transient_precursor_ids": "1048"', 1, true),
        "the shipped Dhalsim rules must retain the 1048 to 642 transient state transition")
end
do
    local terry_override_source = read_all(
        "data/TrainingComboTrials_data/command_display_overrides/Terry.json")
    local terry_exception_source = read_all(
        "data/TrainingComboTrials_data/exceptions/Terry.json")
    for action_id, classic in pairs({
        ["609"] = "LK",
        ["612"] = "MK",
        ["955"] = "214+LK",
        ["956"] = "214+MK",
    }) do
        assert(terry_override_source:find('"' .. action_id .. '"', 1, true)
                and terry_override_source:find(
                    '"classic": "' .. classic .. '"', 1, true),
            "the shipped Terry overrides must retain every runtime-verified Classic command")
    end
    assert(terry_exception_source:find('"606"', 1, true)
            and terry_exception_source:find('"absorb_ids": "607"', 1, true)
            and terry_exception_source:find('"action_event_projection": {}', 1, true),
        "the shipped Terry rules must keep HP Action 607 inside owner Action 606")
end
do
    local zangief_override_source = read_all(
        "data/TrainingComboTrials_data/command_display_overrides/Zangief.json")
    local zangief_compatibility_source = read_all(
        "data/TrainingComboTrials_data/action_compatibility/Zangief.json")
    local zangief_exception_source = read_all(
        "data/TrainingComboTrials_data/exceptions/Zangief.json")
    assert(zangief_override_source:find('"609"', 1, true)
            and zangief_override_source:find('"classic": "HP"', 1, true)
            and zangief_override_source:find('"615"', 1, true)
            and zangief_override_source:find('"classic": "HK"', 1, true)
            and zangief_override_source:find('"631"', 1, true)
            and zangief_override_source:find('"classic": "2+MK"', 1, true)
            and zangief_override_source:find('"923"', 1, true)
            and zangief_override_source:find(
                '"classic": "41236+LK+MK"', 1, true)
            and zangief_override_source:find('"1020"', 1, true)
            and zangief_override_source:find(
                '"classic": "63214+KK"', 1, true)
            and zangief_override_source:find(
                '"contextual_internal_phases"', 1, true)
            and zangief_override_source:find('"948"', 1, true),
        "the shipped Zangief overrides must retain every runtime-verified Classic command and contact phase")
    assert(zangief_compatibility_source:find(
                '"target_game_version": "2026-08-03"', 1, true)
            and zangief_compatibility_source:find(
                '"recorded_action_id": 900', 1, true)
            and zangief_compatibility_source:find(
                '"runtime_action_id": 903', 1, true)
            and zangief_compatibility_source:find(
                '"recorded_motions": ["PP"]', 1, true),
        "the shipped Zangief compatibility map must retain the verified PP Action migration")
    assert(zangief_exception_source:find('"945"', 1, true)
            and zangief_exception_source:find('"absorb_ids": "948"', 1, true)
            and zangief_exception_source:find(
                '"max_fold_delay_frames": 12', 1, true)
            and zangief_exception_source:find(
                '"allow_same_button_press_fold": true', 1, true),
        "the shipped Zangief rules must fold the 948 contact phase into command owner 945")
end
do
    local ed_override_source = read_all(
        "data/TrainingComboTrials_data/command_display_overrides/Ed.json")
    local ed_exception_source = read_all(
        "data/TrainingComboTrials_data/exceptions/Ed.json")
    assert(ed_override_source:find('"contextual_internal_phases"', 1, true)
            and ed_override_source:find('"605"', 1, true)
            and ed_override_source:find('"owner_ids"', 1, true)
            and ed_override_source:find('606', 1, true)
            and not ed_override_source:find(
                '"605": {\n      "classic": "HP"', 1, true)
            and ed_override_source:find('"634"', 1, true)
            and ed_override_source:find('"639"', 1, true),
        "the shipped Ed overrides must hide 605 only after 606 and retain the verified crouching normals")
    assert(ed_exception_source:find('"606"', 1, true)
            and ed_exception_source:find('"absorb_ids": "605"', 1, true)
            and ed_exception_source:find(
                '"max_fold_delay_frames": 12', 1, true)
            and ed_exception_source:find(
                '"require_same_anchor": true', 1, true)
            and ed_exception_source:find(
                '"allow_same_button_press_fold": true', 1, true),
        "the shipped Ed rules must fold the short same-HP 605 contact phase into 606")
    assert(ed_exception_source:find(
                '"structural_followup_chains"', 1, true)
            and ed_exception_source:find('[986, 989]', 1, true)
            and ed_exception_source:find('[988, 991]', 1, true)
            and ed_exception_source:find('"1001"', 1, true)
            and ed_exception_source:find(
                '"transient_precursor_ids": "996,997,999"', 1, true),
        "the shipped Ed rules must group every KK to 6+P variant and suppress staggered single-P OD precursors")
end
do
    local yasmine_override_source = read_all(
        "data/TrainingComboTrials_data/command_display_overrides/Yasmine.json")
    local yasmine_exception_source = read_all(
        "data/TrainingComboTrials_data/exceptions/Yasmine.json")
    local combo_trials_source = read_all("autorun/TrainingComboTrials_v1.0.lua")
    assert(yasmine_override_source:find('"970"', 1, true)
            and yasmine_override_source:find('"classic": "236+HP"', 1, true)
            and yasmine_override_source:find(
                '"require_recorded_motion_match": true', 1, true)
            and not yasmine_override_source:find('"classic": "4+HP"', 1, true)
            and yasmine_override_source:find('"replace": true', 1, true)
            and not yasmine_override_source:find('"938"', 1, true)
            and not yasmine_override_source:find('"942"', 1, true)
            and not yasmine_override_source:find('"972"', 1, true)
            and not yasmine_override_source:find('"976"', 1, true)
            and not yasmine_override_source:find('"1058"', 1, true),
        "the shipped Yasmine overrides must map Action 970 to heavy Daloy ng Tubig and exclude automatic phases")
    assert(yasmine_exception_source:find('"fighter_id": 33', 1, true)
            and yasmine_exception_source:find(
                '"resource_id": "stock_0_033"', 1, true)
            and yasmine_exception_source:find(
                '"required_action_ids": "954,955,956"', 1, true)
            and yasmine_exception_source:find(
                '"producer_action_ids": "1210"', 1, true),
        "the shipped Yasmine rules must infer an initial Bayani state only when required")
    assert(yasmine_exception_source:find('"955"', 1, true)
            and yasmine_exception_source:find(
                '"absorb_ids": "956"', 1, true)
            and yasmine_exception_source:find(
                '"absorb_ids": "938"', 1, true)
            and yasmine_exception_source:find(
                '"absorb_ids": "942"', 1, true)
            and yasmine_exception_source:find(
                '"absorb_ids": "961"', 1, true)
            and yasmine_exception_source:find(
                '"absorb_ids": "972"', 1, true)
            and yasmine_exception_source:find(
                '"absorb_ids": "976"', 1, true)
            and yasmine_exception_source:find('"1057"', 1, true)
            and yasmine_exception_source:find(
                '"absorb_ids": "1058,1060"', 1, true)
            and not yasmine_exception_source:find(
                '"preserve_fresh_button_press": true', 1, true),
        "the shipped Yasmine rules must fold all automatic 1057 finishing phases")
    assert(combo_trials_source:find('[33] = {', 1, true)
            and combo_trials_source:find('name = "Yasmine"', 1, true)
            and combo_trials_source:find(
                'id = "timer_0_033"', 1, true)
            and combo_trials_source:find(
                'id = "stock_0_033"', 1, true),
        "the runtime unique-resource registry must include both Yasmine resources")
end
do
    local ryu_override_source = read_all(
        "data/TrainingComboTrials_data/command_display_overrides/Ryu.json")
    assert(ryu_override_source:find('"617"', 1, true)
            and ryu_override_source:find('"classic": "HK"', 1, true)
            and ryu_override_source:find('"622"', 1, true)
            and ryu_override_source:find('"classic": "2+LP"', 1, true)
            and ryu_override_source:find('"663"', 1, true)
            and ryu_override_source:find('"classic": "4+HP"', 1, true)
            and ryu_override_source:find('"1005"', 1, true)
            and ryu_override_source:find('"classic": "214+HK"', 1, true)
            and ryu_override_source:find('"replace": true', 1, true),
        "the shipped Ryu command overrides must preserve runtime-verified commands")
end
do
    local ken_override_source = read_all(
        "data/TrainingComboTrials_data/command_display_overrides/Ken.json")
    assert(ken_override_source:find('"618"', 1, true)
            and ken_override_source:find('"classic": "2+LP"', 1, true)
            and ken_override_source:find('"623"', 1, true)
            and ken_override_source:find('"classic": "2+MP"', 1, true)
            and ken_override_source:find('"981"', 1, true)
            and ken_override_source:find('"classic": "623+MK"', 1, true)
            and ken_override_source:find('"replace": true', 1, true),
        "the shipped Ken command overrides must preserve the runtime-verified commands")
end
do
    local chunli_override_source = read_all(
        "data/TrainingComboTrials_data/command_display_overrides/ChunLi.json")
    assert(chunli_override_source:find('"605"', 1, true)
            and chunli_override_source:find('"classic": "HK"', 1, true)
            and chunli_override_source:find('"627"', 1, true)
            and chunli_override_source:find('"classic": "3+HP"', 1, true)
            and chunli_override_source:find('"replace": true', 1, true),
        "the shipped Chun-Li command overrides must preserve the runtime-verified commands")
end
do
    local mbison_override_source = read_all(
        "data/TrainingComboTrials_data/command_display_overrides/MBison.json")
    local mbison_921_source = assert(mbison_override_source:match(
        '"921"%s*:%s*(%b{})'))
    local mbison_catalog_source = read_all(
        "data/TrainingComboTrials_data/command_display/MBison.json")
    local mbison_exception_source = read_all(
        "data/TrainingComboTrials_data/exceptions/MBison.json")
    assert(mbison_override_source:find('"608"', 1, true)
            and mbison_override_source:find('"classic": "LK"', 1, true)
            and mbison_override_source:find('"612"', 1, true)
            and mbison_override_source:find('"classic": "HK"', 1, true)
            and mbison_override_source:find('"653"', 1, true)
            and mbison_override_source:find('"classic": "3+HK"', 1, true)
            and mbison_921_source:find('"simple": "强"', 1, true)
            and mbison_921_source:find('"motion": "强"', 1, true)
            and mbison_override_source:find('"954"', 1, true)
            and mbison_override_source:find('"variants"', 1, true)
            and mbison_override_source:find('"974"', 1, true)
            and mbison_override_source:find('"recorded_motions"', 1, true)
            and mbison_override_source:find('"MP+MK"', 1, true),
        "the shipped M. Bison overrides must resolve Action 921 in Modern mode and preserve verified conditioned commands and legacy aliases")
    local mbison_918_source = assert(mbison_catalog_source:match(
        '"918"%s*:%s*(%b{})'))
    local mbison_939_source = assert(mbison_catalog_source:match(
        '"939"%s*:%s*(%b{})'))
    assert(mbison_918_source:find('"display": "空中 任意键"', 1, true)
            and mbison_939_source:find('"display": "空中 任意键"', 1, true)
            and mbison_939_source:find('"type": "followup"', 1, true)
            and mbison_939_source:find('"source_action_id": 918', 1, true)
            and merge_followup_display(
                "空中 任意键", "空中 任意键") == "空中 任意键",
        "M. Bison Action 939 is a followup of 918 with an identical air command; the display must not duplicate 任意键")
    local mbison_strong_steps = assert(mbison_catalog_source:match(
        '"strength": "强"%s*,%s*"steps"%s*:%s*(%b[])'))
    assert(mbison_catalog_source:find('"assist_combo_chains"', 1, true)
            and mbison_catalog_source:find('"assist_combo_chain_count": 3', 1, true)
            and mbison_strong_steps:find('604', 1, true)
            and mbison_strong_steps:find('618', 1, true)
            and mbison_strong_steps:find('902', 1, true)
            and mbison_strong_steps:find('906', 1, true),
        "the M. Bison catalog must declare the 强 AUTO-auto chain 604->618->906/902 for AUTO连 folding")
    assert(mbison_exception_source:find('"649"', 1, true)
            and mbison_exception_source:find(
                '"transient_precursor_ids": "954"', 1, true),
        "the shipped M. Bison rules must preserve the verified 954-to-649 transient precursor")
end
do
    local slim = build_slim_command_display_map({ _meta = {
        character = "MBison",
        assist_combo_chains = {
            {
                strength = "强",
                steps = {
                    { position = 1, action_ids = { 604 } },
                    { position = 2, action_ids = { 618 } },
                },
            },
        },
    } })
    assert(type(slim._assist_combo_chains) == "table"
            and #slim._assist_combo_chains == 1
            and slim._assist_combo_chains[1].strength == "强",
        "slim command maps must carry assist-auto chains for AUTO连 folding")
end
local alex_override_source = read_all(
    "data/TrainingComboTrials_data/command_display_overrides/Alex.json")
assert(alex_override_source:find('"entries": {}', 1, true)
        and not alex_override_source:find('"958"', 1, true)
        and not alex_override_source:find('"959"', 1, true),
    "Alex command ownership must stay in the generated catalog instead of stale replacements")
do
    local alex_catalog_source = read_all(
        "data/TrainingComboTrials_data/command_display/Alex.json")
    assert(alex_catalog_source:find('"957": {', 1, true)
            and alex_catalog_source:find('"958": {', 1, true)
            and alex_catalog_source:find('"959": {', 1, true)
            and alex_catalog_source:find(
                '"source_action_ids": [\n          957,\n          958,\n          959',
                1,
                true
            ),
        "the shipped AC catalog must retain the 957/958/959 state-source relation")
    assert(alex_catalog_source:find('"display": "2 + 中 + 强"', 1, true)
            and alex_catalog_source:find('"profile": "easy"', 1, true)
            and alex_catalog_source:find('"required_button_count": 2', 1, true),
        "the generated Alex catalog must own the Modern 2+PP command")
end
do
    local deejay_override_source = read_all(
        "data/TrainingComboTrials_data/command_display_overrides/DeeJay.json")
    assert(deejay_override_source:find('"606"', 1, true)
            and deejay_override_source:find('"classic": "HP"', 1, true)
            and deejay_override_source:find('"611"', 1, true)
            and deejay_override_source:find('"classic": "MK"', 1, true)
            and deejay_override_source:find('"617"', 1, true)
            and deejay_override_source:find('"classic": "2+LP"', 1, true)
            and deejay_override_source:find('"1229"', 1, true)
            and deejay_override_source:find('"classic": "236236+HP"', 1, true)
            and deejay_override_source:find('"replace": true', 1, true),
        "the shipped Dee Jay command overrides must preserve runtime-verified commands")
end
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
local kimberly_override_source = read_all(
    "data/TrainingComboTrials_data/command_display_overrides/Kimberly.json")
assert(kimberly_override_source:find('"613"', 1, true)
        and kimberly_override_source:find('"classic": "2+MP"', 1, true)
        and kimberly_override_source:find('"980"', 1, true)
        and kimberly_override_source:find('"classic": "5252+MP+HP"', 1, true)
        and kimberly_override_source:find('"983"', 1, true)
        and kimberly_override_source:find('"classic": ">22+MP+HP"', 1, true)
        and kimberly_override_source:find('"replace": true', 1, true),
    "the shipped Kimberly command overrides must preserve runtime-verified commands")
local jp_override_source = read_all(
    "data/TrainingComboTrials_data/command_display_overrides/JP.json")
assert(jp_override_source:find('"622"', 1, true)
        and jp_override_source:find('"classic": "2+HK"', 1, true)
        and jp_override_source:find('"645"', 1, true)
        and jp_override_source:find('"classic": "HK"', 1, true)
        and jp_override_source:find('"720"', 1, true)
        and jp_override_source:find('"classic": "LP+LK"', 1, true)
        and jp_override_source:find('"856"', 1, true)
        and jp_override_source:find('"classic": "MP"', 1, true)
        and jp_override_source:find('"974"', 1, true)
        and jp_override_source:find('"classic": "236+LK"', 1, true)
        and jp_override_source:find('"975"', 1, true)
        and jp_override_source:find('"classic": "236+MK"', 1, true)
        and jp_override_source:find('"976"', 1, true)
        and jp_override_source:find('"classic": "236+HK"', 1, true)
        and jp_override_source:find('"replace": true', 1, true)
        and not jp_override_source:find('"943"', 1, true),
    "the shipped JP command overrides must preserve verified commands without reviving legacy Action 943")
local jp_exception_source = read_all(
    "data/TrainingComboTrials_data/exceptions/JP.json")
assert(jp_exception_source:find('"947"', 1, true)
        and jp_exception_source:find('"absorb_ids": "914"', 1, true)
        and jp_exception_source:find('"action_event_projection": {}', 1, true),
    "the shipped JP exception must preserve the 214+HP internal contact phase")
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
local luke_override_source = read_all(
    "data/TrainingComboTrials_data/command_display_overrides/Luke.json")
assert(luke_override_source:find('"609"', 1, true)
        and luke_override_source:find('"classic": "LK"', 1, true)
        and luke_override_source:find('"612"', 1, true)
        and luke_override_source:find('"classic": "MK"', 1, true)
        and luke_override_source:find('"669"', 1, true)
        and luke_override_source:find('"classic": "4+HK"', 1, true),
    "the shipped Luke command overrides must preserve runtime-verified commands")
local luke_exception_source = read_all(
    "data/TrainingComboTrials_data/exceptions/Luke.json")
assert(luke_exception_source:find('"absorb_ids": "921"', 1, true)
        and luke_exception_source:find('"absorb_ids": "926"', 1, true)
        and luke_exception_source:find('"absorb_ids": "930"', 1, true)
        and luke_exception_source:find('"960"', 1, true)
        and luke_exception_source:find('"previous_ids": "955"', 1, true)
        and luke_exception_source:find('"anchor_kind": "button_press"', 1, true)
        and luke_exception_source:find('"1210"', 1, true)
        and luke_exception_source:find('"transient_precursor_ids": "17"', 1, true),
    "the shipped Luke exceptions must preserve internal hit phases and the uppercut tail rule")
local manon_override_source = read_all(
    "data/TrainingComboTrials_data/command_display_overrides/Manon.json")
assert(manon_override_source:find('"628"', 1, true)
        and manon_override_source:find('"classic": "2+MP"', 1, true)
        and manon_override_source:find('"1022"', 1, true)
        and manon_override_source:find('"classic": "236+MP"', 1, true),
    "the shipped Manon command overrides must preserve runtime-verified commands")
local manon_exception_source = read_all(
    "data/TrainingComboTrials_data/exceptions/Manon.json")
assert(manon_exception_source:find('"1022"', 1, true)
        and manon_exception_source:find('"absorb_ids": "1041"', 1, true),
    "the shipped Manon exceptions must preserve the 236+MP internal contact phase")
local guile_override_source = read_all(
    "data/TrainingComboTrials_data/command_display_overrides/Guile.json")
assert(guile_override_source:find('"609"', 1, true)
        and guile_override_source:find('"classic": "HP"', 1, true)
        and guile_override_source:find('"653"', 1, true)
        and guile_override_source:find('"classic": "3+HK"', 1, true)
        and guile_override_source:find('"674"', 1, true)
        and guile_override_source:find('"classic": "6+HK"', 1, true)
        and guile_override_source:find('"922"', 1, true)
        and guile_override_source:find('"classic": "236+LP+MP"', 1, true)
        and guile_override_source:find('"923"', 1, true)
        and guile_override_source:find('"classic": "214+PP"', 1, true),
    "the shipped Guile command overrides must preserve runtime-verified commands")
local guile_exception_source = read_all(
    "data/TrainingComboTrials_data/exceptions/Guile.json")
assert(guile_exception_source:find('"994"', 1, true)
        and guile_exception_source:find('"transient_precursor_ids": "33"', 1, true),
    "the shipped Guile exceptions must suppress the transient Flash Kick precursor")
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
assert(combo_imgui_source:find("trial_state._recording_preview_logs", 1, true)
        and combo_imgui_source:find("trial_state._recording_preview_sequence", 1, true),
    "recording UI must render ActionEvent-compiled live logs and trial steps")
local combo_entry_source = read_all("autorun/TrainingComboTrials_v1.0.lua")
assert(combo_imgui_source:find("M.RENDERER_VERSION = 2026082005", 1, true)
        and combo_entry_source:find("REQUIRED_RENDERER_VERSION = 2026082005", 1, true)
        and combo_entry_source:find("cached_renderer.RENDERER_VERSION", 1, true)
        and combo_entry_source:find('package.loaded["func/ComboTrials_ImGui"] = nil', 1, true)
        and combo_entry_source:find("cached_renderer.clear_command_display_cache", 1, true)
        and not combo_entry_source:find("local cached_combo_trials_renderer", 1, true),
    "the entry script must reload the renderer when its module version changes and upgrade a legacy renderer exactly once")
assert(combo_entry_source:find("ctx.refresh_recording_preview(session)", 1, true)
        and combo_entry_source:find("flush_recording_contacts = false", 1, true)
        and combo_entry_source:find("trial_state.sequence = compiled.steps", 1, true),
    "recording preview must stay separate from the final saved sequence")
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
assert(main_source:find("UnifiedActionConsumer.matches_expected_action_id", 1, true),
    "playback intentionality must consume configured action aliases through the shared gateway")
assert(main_source:find("UnifiedActionConsumer.should_admit_ignored_expected_action", 1, true),
    "raw-input expected Actions must consume legacy admission through the shared gateway")
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
        if action_id == 17 then return "66", "strict_route" end
        if action_id == 18 then return "44", "strict_route" end
        if action_id == 36 then return "8", "strict_route" end
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

do
    local conditioned_runtime_map = select(1,
        command_display_overrides.merge({ _slim = true }, "JP", {
            schema = "xt.command_display_overrides.v1",
            character = "JP",
            entries = {
                ["645"] = {
                    classic = "HK",
                    replace = true,
                    button_masks = { 512 },
                    evidence = "distinct runtime HK press",
                },
            },
        }))
    local conditioned_renderer = {
        get_command_display = function() return nil, "action_id_missing" end,
        get_input_conditioned_command_display = function(_, action_id, direct_input, edge, mode)
            return command_display_overrides.resolve_input_conditioned(
                conditioned_runtime_map, action_id, direct_input, edge, mode)
        end,
    }
    intentional, route_status, classic = command_resolver.resolve_unified_command_action(
        "JP", 645, 512, 512, conditioned_renderer)
    assert(intentional == true
            and route_status == "runtime_verified_conditioned_override"
            and classic == "HK",
        "JP Action 645 must resolve as HK only when the runtime binds an HK input")
    intentional, route_status, classic = command_resolver.resolve_unified_command_action(
        "JP", 645, 32, 32, conditioned_renderer)
    assert(intentional == false and route_status == "action_id_missing" and classic == nil,
        "JP Action 645 must remain promotable when it carries another move's input")
end

intentional, route_status, classic = command_resolver.resolve_unified_command_action(
    "AKI", 944, 0, 48, renderer)
assert(intentional == true and route_status == "strict_route" and classic == "236+PP",
    "A.K.I. 236+PP must survive a delayed state-dependent Action transition")

intentional, route_status, classic = command_resolver.resolve_unified_command_action(
    "AnyCharacter", 901, 0, 0, renderer)
assert(intentional == false and route_status == "strict_route" and classic == "214+MP",
    "a catalog action without held buttons or a recovered edge must remain non-intentional")

intentional, route_status, classic = command_resolver.resolve_unified_command_action(
    "AnyCharacter", 17, 0, 0, renderer)
assert(intentional == true and route_status == "strict_route" and classic == "66",
    "runtime Dash Action 17 must be intentional without attack buttons")
intentional, route_status, classic = command_resolver.resolve_unified_command_action(
    "AnyCharacter", 18, 0, 0, renderer)
assert(intentional == true and route_status == "strict_route" and classic == "44",
    "runtime back-dash Action 18 must be intentional without attack buttons")
intentional, route_status, classic = command_resolver.resolve_unified_command_action(
    "AnyCharacter", 36, 0, 0, renderer)
assert(intentional == true and route_status == "strict_route" and classic == "8",
    "runtime jump Action 36 must retain direction-only intentionality")

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
