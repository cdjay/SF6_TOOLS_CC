package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local function read_all(path)
    local file = assert(io.open(path, "rb"))
    local value = assert(file:read("*a"))
    file:close()
    return value:gsub("\r\n", "\n")
end

local command_display_overrides =
    dofile("autorun/func/ComboTrials/CommandDisplayOverrides.lua")
CommandDisplayOverrides = command_display_overrides
ActionCompatibility = dofile("autorun/func/ComboTrials/ActionCompatibility.lua")
TrainingEnvironment = dofile("autorun/func/ComboTrials/TrainingEnvironment.lua")
SequenceGrouping = dofile("autorun/func/ComboTrials/SequenceGrouping.lua")
Type63StrengthSemantics =
    dofile("autorun/func/ComboTrials/Type63StrengthSemantics.lua")

local renderer_source = read_all("autorun/func/ComboTrials_ImGui.lua")
trim_string = function(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local semantic_block = assert(renderer_source:match(
    "(local function resolve_classic_common_semantic.-)\nbuild_slim_command_display_map = function"))
assert(load(semantic_block
        .. "\n_G.merge_followup_display = merge_followup_display",
    "semantic", "t", _G))()
local slim_map_block = assert(renderer_source:match(
    "(build_slim_command_display_map = function.-)\n\nlocal function get_classic_display_motion"))
assert(load(slim_map_block, "slim-map", "t", _G))()
local classic_block = assert(renderer_source:match(
    "(local function get_player_visible_transition_motion.-)\nlocal function get_command_display"))
assert(load(classic_block
        .. "\n_G.get_classic_display_motion = get_classic_display_motion"
        .. "\n_G.get_modern_display_motion = get_modern_display_motion"
        .. "\n_G.project_historical_action_step = project_historical_action_step"
        .. "\n_G.get_player_visible_transition_motion = get_player_visible_transition_motion"
        .. "\n_G.apply_presentation_context = apply_presentation_context",
    "classic", "t", _G))()
local display_block = assert(renderer_source:match(
    "(local function select_modern_display_motion.-)\nlocal function localize_motion_text"))
assert(load(display_block
        .. "\n_G.resolve_step_command_display = resolve_step_command_display"
        .. "\n_G.resolve_contextual_step_command_display = resolve_contextual_step_command_display"
        .. "\n_G.resolve_live_log_command_displays = resolve_live_log_command_displays"
        .. "\n_G.setup_followup_child_sources = setup_followup_child_sources"
        .. "\n_G.is_internal_bridge_candidate = is_internal_bridge_candidate"
        .. "\n_G.compute_internal_bridge_suppressions = compute_internal_bridge_suppressions"
        .. "\n_G.validate_sequence_command_display = validate_sequence_command_display"
        .. "\n_G.merge_group_log_item = merge_group_log_item"
        .. "\n_G.build_display_lines = build_display_lines",
    "display", "t", _G))()

RUNTIME_COMMON_REASON = "sf6_stable_runtime_common_movement_action"
OFFICIAL_SEMANTIC_REASON =
    "capcom_official_command_semantics_matched_to_current_bcm_identity"
VERIFIED_ALIAS_REASON = "ac_verified_equivalent_action_variant"
TYPE20_DIRECTION_REASON = "ac_type20_verified_directional_air_attack"
TYPE20_HOLD_REASON = "ac_type20_verified_hold_continuation"
TYPE20_PHASE_REASON = "ac_type20_verified_multi_input_action_phase"
CHARGE_CONTEXT_REASON =
    "bcm_charge_profile_context_proves_modern_held_shortcut"
AC_CHARGE_CONTEXT_REASON =
    "ac_full_structure_peer_and_bcm_selector_prove_charge_context"
SUPER_SHORTCUT_DIRECTION_REASON =
    "bcm_super_supr_direction_qualifies_easy_shortcut"
AC_STATE_RELEASE_REASON =
    "ac_type20_release_transition_from_verified_direction_state"
BCM_ZERO_INPUT_TRANSITION_REASON =
    "bcm_function2_normal_has_no_player_visible_input"
AC_TERMINAL_EXECUTION_PHASE_REASON =
    "ac_type2_type4_zero_parameter_terminal_execution_phase"
AC_NUMBERED_EXECUTION_PHASE_REASON =
    "ac_type2_numbered_same_structure_execution_phase"
AC_SAME_STRUCTURE_EXECUTION_PHASE_REASON =
    "ac_type2_same_structure_zero_parameter_execution_phase"
AC_TYPE37_AUTOMATIC_EXECUTION_PHASE_REASON =
    "ac_type37_unique_automatic_execution_phase"
RUNTIME_COMMON_ACTIONS = {}

get_sequence_character = function() return "MBison" end
clone_step_for_display = function(step, motion, modern)
    local copy = {}
    for key, value in pairs(step) do copy[key] = value end
    copy.motion = motion
    copy._ct_modern_display = modern == true
    return copy
end
unresolved_action_placeholder = function() return "[指令未识别]" end
audit_unresolved_action = function() end
apply_presentation_context = function() return nil end

local auto_map = {
    _slim = true,
    _assist_combo_chains = {
        {
            strength = "强",
            steps = {
                { position = 1, action_ids = { 604 } },
                { position = 2, action_ids = { 618 } },
                { position = 3, action_ids = { 906 } },
            },
        },
    },
    ["604"] = { commands = { simple = "AUTO + 强" } },
    ["618"] = { commands = { simple = "AUTO + 中" } },
    ["906"] = { commands = { simple = "6 + AUTO + SP" } },
}

resolve_modern_display_context = function()
    return true, auto_map, "MBison", "loaded", false
end
sequence_display_language = function() return "zh-CN" end

local function line_motions(sequence)
    local out = {}
    local lines = build_display_lines(sequence)
    for _, dl in ipairs(lines) do
        local motion = #dl.steps > 1
            and merge_group_log_item(dl.steps).motion
            or dl.steps[1].motion
        out[#out + 1] = motion
    end
    return out
end

-- Non-auto mode keeps each expanded hit on its own line.
ctx = { d2d_cfg = { modern_display_mode = "simple" } }
local flat = line_motions({
    { id = 604, motion = "MP", group_id = 5 },
    { id = 618, motion = "2+MP", group_id = 6 },
    { id = 906, motion = "236+KK", group_id = 7 },
})
assert(#flat == 3,
    "non-AUTO连 mode must keep expanded hits on separate lines")

-- AUTO连 mode folds the whole chain into one held-AUTO bracket.
ctx = { d2d_cfg = { modern_display_mode = "auto" } }
local full = line_motions({
    { id = 604, motion = "MP", group_id = 5 },
    { id = 618, motion = "2+MP", group_id = 6 },
    { id = 906, motion = "236+KK", group_id = 7 },
})
assert(#full == 1 and full[1] == "AUTO + [强 > 强 > 强]",
    "AUTO连 mode must fold a complete heavy chain to AUTO + [强>强>强]")

-- Prefix interruption: only 强,强 played.
local prefix = line_motions({
    { id = 604, motion = "MP", group_id = 5 },
    { id = 618, motion = "2+MP", group_id = 6 },
})
assert(#prefix == 1 and prefix[1] == "AUTO + [强 > 强]",
    "AUTO连 mode must support prefix interruption (AUTO + [强>强])")

-- Sequence ending mid-chain then continuing to a normal move stays separate.
local after = line_motions({
    { id = 604, motion = "MP", group_id = 5 },
    { id = 904, motion = "236+HK", group_id = 8 },
})
assert(#after == 2,
    "a chain prefix followed by an unrelated move must not over-fold")

print("combo auto-chain fold tests passed")
