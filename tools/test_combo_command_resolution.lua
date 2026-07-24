local function read_all(path)
    local file = assert(io.open(path, "rb"))
    local value = assert(file:read("*a"))
    file:close()
    return value:gsub("\r\n", "\n")
end

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

assert(load(classic_block .. "\n_G.get_classic_display_motion = get_classic_display_motion",
    "classic-command-resolution", "t", _G))()

local command_map = {
    _slim = true,
    ["901"] = { classic = "214+MP", status = "strict_route" },
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

local main_source = read_all("autorun/TrainingComboTrials_v1.0.lua")
local resolver_block = assert(main_source:match(
    "(local function decode_transition_button_mask.-\nend)\n\nlocal esf_names_map"))
ComboTrials_Renderer = {
    get_command_display = function(_, action_id)
        if action_id == 906 then return nil, "suppress_transition" end
        if action_id == 901 then return "214+MP", "strict_route" end
        return nil, "action_id_missing"
    end
}
resolver_block = resolver_block:gsub(
    "local ComboTrials_Renderer", "local ComboTrials_Renderer = _G.ComboTrials_Renderer", 1)
assert(load(resolver_block
    .. "\n_G.resolve_unified_command_action = resolve_unified_command_action"
    .. "\n_G.find_recent_action_button_edge = find_recent_action_button_edge",
    "recording-command-resolution", "t", _G))()

local recent_edge = find_recent_action_button_edge({
    { frame_tick = 100, mask = 32 },  -- MP launched the parent 214+MP
    { frame_tick = 105, mask = 128 }  -- K requested the derived cancel
}, 100, 106, 12)
assert(recent_edge == 128, "a delayed cancel must recover the newest post-parent button edge")
assert(find_recent_action_button_edge({ { frame_tick = 100, mask = 32 } }, 100, 106, 12) == 0,
    "the parent attack button must never be reinterpreted as a cancel")
assert(find_recent_action_button_edge({ { frame_tick = 90, mask = 128 } }, 100, 106, 12) == 0,
    "a stale pre-parent button must never produce a derived cancel")

local intentional, route_status, classic = resolve_unified_command_action("AnyCharacter", 901, 32, 32)
assert(intentional == true and route_status == "strict_route" and classic == "214+MP",
    "a physical catalog command must remain intentional")

intentional, route_status, classic = resolve_unified_command_action("AnyCharacter", 906, 0, 0)
assert(intentional == false and route_status == "suppress_transition" and classic == nil,
    "a zero-input internal transition must be non-intentional in every control mode")

intentional, route_status, classic = resolve_unified_command_action("AnyCharacter", 906, 128, 128)
assert(intentional == true and route_status == "player_input_transition" and classic == ">K (取消)",
    "a physical button edge must recover a player-triggered cancel without character-specific IDs")

print("combo command resolution tests passed")
