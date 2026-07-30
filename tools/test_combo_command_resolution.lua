local function read_all(path)
    local file = assert(io.open(path, "rb"))
    local value = assert(file:read("*a"))
    file:close()
    return value:gsub("\r\n", "\n")
end

local command_resolver = dofile("autorun/func/ComboTrials/CommandResolver.lua")

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

motion, status = get_classic_display_motion(command_map, { id = 9998, motion = "214+HP" })
assert(motion == nil and status == "action_id_missing",
    "arbitrary recorded motion must not bypass the audited command table")

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
assert(character_rules.find_recording_absorb_owner({
        ["944"] = {
            absorb_ids = "936,941,945",
            record_absorb_as_parent = true
        }
    }, {}, 945) == 944,
    "an opted-in frame-zero absorb branch must resolve to its recording command owner")
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
        if action_id == 901 then return "214+MP", "strict_route" end
        if action_id == 944 then return "236+PP", "strict_route" end
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
