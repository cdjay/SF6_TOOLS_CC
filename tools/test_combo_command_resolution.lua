local function read_all(path)
    local file = assert(io.open(path, "rb"))
    local value = assert(file:read("*a"))
    file:close()
    return value:gsub("\r\n", "\n")
end

local command_resolver = dofile("autorun/func/ComboTrials/CommandResolver.lua")
local command_display_overrides =
    dofile("autorun/func/ComboTrials/CommandDisplayOverrides.lua")

local override_map = { _slim = true, ["967"] = { classic = ">6+P" } }
local merged_overrides, applied_overrides, override_status =
    command_display_overrides.merge(override_map, "Alex", {
        schema = "xt.command_display_overrides.v1",
        character = "Alex",
        entries = {
            ["967"] = { classic = "bad replacement", evidence = "test" },
            ["968"] = { classic = ">6+MP", evidence = "three raw replays" },
            ["977"] = { classic = ">HP (INSTANT)", evidence = "five raw replays" },
            ["978"] = { classic = ">LK" },
        },
    })
assert(override_status == "loaded" and applied_overrides == 2
    and merged_overrides["967"].classic == ">6+P"
    and merged_overrides["968"].classic == ">6+MP"
    and merged_overrides["968"].status == "runtime_verified_override"
    and merged_overrides["977"].classic == ">HP (INSTANT)"
    and merged_overrides["978"] == nil,
    "verified command overrides must fill missing Actions without silently replacing catalog rows")
local _, invalid_override_count, invalid_override_status =
    command_display_overrides.merge({ _slim = true }, "Alex", {
        schema = "xt.command_display_overrides.v1",
        character = "Ryu",
        entries = { ["968"] = { classic = ">6+MP", evidence = "test" } },
    })
assert(invalid_override_count == 0 and invalid_override_status == "invalid_override_document",
    "command overrides for another character must fail closed")
local cammy_overrides, cammy_override_count, cammy_override_status =
    command_display_overrides.merge({ _slim = true }, "Cammy", {
        schema = "xt.command_display_overrides.v1",
        character = "Cammy",
        entries = {
            ["908"] = {
                classic = ">HK",
                evidence = "verified 4+MP follow-up HK",
            },
        },
    })
assert(cammy_override_status == "loaded" and cammy_override_count == 1
    and cammy_overrides["908"].classic == ">HK"
    and cammy_overrides["908"].status == "runtime_verified_override",
    "Cammy's verified target-combo follow-up must override the missing strict route")
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
    .. "\n_G.get_modern_display_motion = get_modern_display_motion",
    "classic-command-resolution", "t", _G))()
local validation_block = assert(renderer_source:match(
    "(local function select_modern_display_motion.-)\nlocal function build_display_lines"
))
assert(load(validation_block
        .. "\n_G.resolve_step_command_display = resolve_step_command_display"
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
local legacy_di_rule = character_rules.get_match_rule({}, {}, "ChunLi", 854)
local legacy_di_match = action_matcher.match_expected_action(
    { id = 854, motion = "DI" },
    855,
    "DI",
    "HP+HK",
    legacy_di_rule
)
assert(legacy_di_match.matched == true and legacy_di_match.match_reason == "action_alias_id",
    "a legacy Action ID 854 DI step must admit the current runtime Action ID 855")
local current_di_rule = character_rules.get_match_rule({}, {}, "ChunLi", 855)
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
    {},
    "Jamie",
    854
)
assert(jamie_di_rule.force == true
        and action_matcher.matches_expected_action_id({ id = 854 }, 855, jamie_di_rule) == true,
    "the universal DI alias must merge with character-specific Action ID 854 rules")
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
local deejay_sa3_exception = character_rules.get_match_rule({}, {}, "DeeJay", 1268)
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
local deejay_ca_exception = character_rules.get_match_rule({}, {}, "DeeJay", 1272)
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
