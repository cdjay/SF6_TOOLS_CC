-- =========================================================
-- ComboTrials_ImGui.lua -- pure ImGui overlay rendering (icons, trial box)
-- Receives shared context (ctx) from the main file.
-- =========================================================

local sdk = sdk
local imgui = imgui

local M = {}
M.RENDERER_VERSION = 2026082005
local RuntimeSafety = require("func/RuntimeSafety")
local Canvas = require("func/ImGuiCanvas")
local SequenceGrouping = require("func/ComboTrials/SequenceGrouping")
local Validator = require("func/ComboTrials/Validator")
local TrainingEnvironment = require("func/ComboTrials/TrainingEnvironment")
local CommandDisplayOverrides = require("func/ComboTrials/CommandDisplayOverrides")
local MotionPresentation = require("func/ComboTrials/MotionPresentation")
local ActionCompatibility = require("func/ComboTrials/ActionCompatibility")
local SF6CCVersion = require("func/SF6CC_Version")
local TrialDisplayState = require("func/ComboTrials/TrialDisplayState")
local Type63StrengthSemantics = require("func/ComboTrials/Type63StrengthSemantics")

-- Shared context (set by init)
local ctx -- { d2d_cfg, trial_state, players, sf6_menu_state }

local assets = { font = nil, last_pixel_size = -1, title_font = nil, last_title_pixel_size = -1, imgs = {} }
local imgui_anim = { active_y = nil }
local imgui_last_runtime_allowed = nil
local imgui_last_content_visible = nil
local imgui_last_error = nil

local function is_combo_trials_runtime_allowed()
    if not ctx then return false end
    if ctx and type(ctx.is_runtime_allowed) == "function" then
        local ok, allowed = pcall(ctx.is_runtime_allowed)
        return ok and allowed == true
    end
    return RuntimeSafety.is_training_allowed()
        and _G.CurrentTrainerMode == 4
        and _G.TrainingModeActive == true
        and _G.TrainingScriptManagerActiveThisFrame == true
        and _G.IsInBattleHub ~= true
        and _G.IsInReplay ~= true
        and _G.FlowMapID ~= 9
        and _G.FlowMapID ~= 10
end

local image_files = {
    ["1"] = "1.png",
    ["2"] = "2.png",
    ["3"] = "3.png",
    ["4"] = "4.png",
    ["5"] = "5.png",
    ["6"] = "6.png",
    ["7"] = "7.png",
    ["8"] = "8.png",
    ["9"] = "9.png",
    ["lp"] = "lp.png",
    ["mp"] = "mp.png",
    ["hp"] = "hp.png",
    ["lk"] = "lk.png",
    ["mk"] = "mk.png",
    ["hk"] = "hk.png",
    ["modern_l"] = "modern_l.png",
    ["modern_m"] = "modern_m.png",
    ["modern_h"] = "modern_h.png",
    ["modern_n"] = "modern_n.png",
    ["modern_sp"] = "modern_sp.png",
    ["modern_auto"] = "modern_auto.png",
    ["p"] = "P.png",
    ["k"] = "K.png",
    ["360"] = "360.png",
    ["4_hold"] = "4_HOLD.png",
    ["2_hold"] = "2_HOLD.png",
    ["6_hold"] = "6_HOLD.png",
    ["hcb"] = "HCB.png",
    ["hcf"] = "HCF.png",
    ["throw"] = "THROW.png",
    ["arrow"] = "arrow.png",
    ["arrow_success"] = "arrow_green.png",
    ["arrow_fail"] = "arrow_red.png",
    ["followup"] = "FollowUp.png",
    ["validfollowup"] = "validfollowup.png",
    ["hold"] = "hold.png",
    ["plus"] = "PLUS.png",
    ["parry"] = "parry.png",
    ["dr"] = "dr.png",
    ["drc"] = "drc.png",
    ["rev"] = "rev.png",
    ["di"] = "DI.png"
}

-- =========================================================
-- RAW INPUT SYSTEM (InputVisualiser-style integrated)
-- =========================================================
local raw_state = { history_p1 = {}, history_p2 = {} }

local function raw_get_numpad(dir_val)
    local u = (dir_val & 1) ~= 0
    local d = (dir_val & 2) ~= 0
    local r = (dir_val & 8) ~= 0
    local l = (dir_val & 4) ~= 0
    if u and l then return "7" elseif u and r then return "9" elseif d and l then return "1"
    elseif d and r then return "3" elseif u then return "8" elseif d then return "2"
    elseif l then return "4" elseif r then return "6" end
    return "5"
end

local function raw_get_buttons(val)
    local list = {}
    if (val & 16) ~= 0  then table.insert(list, "lp") end
    if (val & 32) ~= 0  then table.insert(list, "mp") end
    if (val & 64) ~= 0  then table.insert(list, "hp") end
    if (val & 128) ~= 0 then table.insert(list, "lk") end
    if (val & 256) ~= 0 then table.insert(list, "mk") end
    if (val & 512) ~= 0 then table.insert(list, "hk") end
    return list
end

local function raw_update_history(history, d, b, max_size)
    local top = history[1]
    if top and (d == top.dir) and (b == top.btn) and top.active then
        top.frames = top.frames + 1
    else
        table.insert(history, 1, { dir = d, btn = b, frames = 1, active = true })
        while #history > max_size do table.remove(history) end
    end
end

local function _ctd_raw_read_inputs_inner(p_idx, history, max_size)
    local gBattle = sdk.find_type_definition("gBattle")
    if not gBattle then return end
    local mgr = gBattle:get_field("Player"):get_data(nil)
    if not mgr then return end
    local p = mgr:call("getPlayer", p_idx)
    if not p then return end
    local d = p:get_type_definition():get_field("pl_input_new"):get_data(p) or 0
    local b = p:get_type_definition():get_field("pl_sw_new"):get_data(p) or 0
    raw_update_history(history, d, b, max_size)
end

local function raw_read_inputs(p_idx, history, max_size)
    pcall(_ctd_raw_read_inputs_inner, p_idx, history, max_size)
end

-- Helper: apply mirror transform to position and flip
local function apply_mirror(pos, flip)
    return { x = 1.0 - pos.x, y = pos.y }, not flip
end

local function trim_string(value)
    local s = tostring(value or "")
    return s:match("^%s*(.-)%s*$") or ""
end

local function get_meta_table(first)
    if type(first) ~= "table" then return nil end
    if type(first._xt_meta) == "table" then return first._xt_meta end
    if type(first._wtt_cn_meta) == "table" then return first._wtt_cn_meta end
    return nil
end

local function get_trial_meta()
    local state = ctx and ctx.trial_state
    local seq = state and state.sequence
    local first = seq and seq[1]
    return get_meta_table(first) or {}
end

-- =========================================================
-- Follow-up group helpers
-- =========================================================
local COMMAND_DISPLAY_DIR = "TrainingComboTrials_data/command_display/"
local RUNTIME_COMMON_REASON = "sf6_stable_runtime_common_movement_action"
local OFFICIAL_SEMANTIC_REASON = "capcom_official_command_semantics_matched_to_current_bcm_identity"
local COMMUNITY_SEMANTIC_REASON = "verified_community_command_semantics_matched_to_current_bcm_identity"
local VERIFIED_ALIAS_REASON = "ac_verified_equivalent_action_variant"
local TYPE20_DIRECTION_REASON = "ac_type20_verified_directional_air_attack"
local TYPE20_HOLD_REASON = "ac_type20_verified_hold_continuation"
local TYPE20_PHASE_REASON = "ac_type20_verified_multi_input_action_phase"
local TYPE20_SIX_BRANCH_PHASE_REASON =
    "ac_type20_verified_six_branch_action_phase"
local TYPE20_TERMINAL_COMMAND_PHASE_REASON =
    "ac_type20_complete_punch_strength_terminal_command_phase"
local TYPE20_DELAYED_EFFECT_REASON = "ac_type20_multi_owner_delayed_contact_effect"
local TYPE20_SAME_STRUCTURE_PHASE_REASON =
    "ac_type20_verified_same_structure_execution_phase"
local TYPE37_FOLLOWUP_PHASE_REASON = "ac_type37_verified_followup_execution_phase"
local CHARGE_CONTEXT_REASON = "bcm_charge_profile_context_proves_modern_held_shortcut"
local AC_CHARGE_CONTEXT_REASON = "ac_full_structure_peer_and_bcm_selector_prove_charge_context"
local SUPER_SHORTCUT_DIRECTION_REASON = "bcm_super_supr_direction_qualifies_easy_shortcut"
local CHARGE_COMPATIBILITY_REASON = "bcm_true_charge_trigger_suppresses_uncharged_compatibility_trigger"
local OFFICIAL_DIRECT_ROUTE_REASON = "capcom_official_exact_action_and_classic_identity_select_unique_direct_route"
local AC_STATE_DIRECTION_REASON = "ac_type20_multi_direction_state_choice"
local AC_STATE_NEUTRAL_REASON = "ac_type1_neutral_branch_beside_multi_direction_state_choices"
local AC_TYPE13_NEUTRAL_REASON = "ac_type13_zero_input_terminal_continuation_with_directional_sibling"
local AC_STATE_RELEASE_REASON = "ac_type20_release_transition_from_verified_direction_state"
local BCM_ZERO_INPUT_TRANSITION_REASON = "bcm_function2_normal_has_no_player_visible_input"
local AC_TERMINAL_EXECUTION_PHASE_REASON =
    "ac_type2_type4_zero_parameter_terminal_execution_phase"
local AC_NUMBERED_EXECUTION_PHASE_REASON =
    "ac_type2_numbered_same_structure_execution_phase"
local AC_SAME_STRUCTURE_EXECUTION_PHASE_REASON =
    "ac_type2_same_structure_zero_parameter_execution_phase"
local AC_TYPE13_TERMINAL_EXECUTION_PHASE_REASON =
    "ac_type13_zero_parameter_multi_owner_terminal_execution_phase"
local AC_TYPE13_AIR_LANDING_EXECUTION_PHASE_REASON =
    "ac_type13_multi_owner_air_landing_execution_phase"
local AC_TYPE36_TYPE13_EXECUTION_PHASE_REASON =
    "ac_type36_zero_parameter_phase_with_type13_terminal_exit"
local AC_TYPE37_AUTOMATIC_EXECUTION_PHASE_REASON =
    "ac_type37_unique_automatic_execution_phase"
local TARGET_COMBO_REPEAT_REASON = "bcm_turn_around_target_combo_repeats_parent_button"
local STRUCTURAL_TWIN_REASON = "ac_bcm_unique_structural_twin_with_internal_use_super_delta"
local ASSIST_COMBO_REASON = "bcm_assist_combo_recipe_direct_input_sequence"

local function valid_contextual_effect_relation(relation, target_action_id)
    if type(relation) ~= "table"
        or tonumber(relation.target_action_id) ~= tonumber(target_action_id)
        or tonumber(relation.branch_type) ~= 20
        or tonumber(relation.attr) ~= 288
        or (tonumber(relation.action_frame) or 0) <= 0
        or tonumber(relation.param00) ~= 1
        or tonumber(relation.param02) ~= 1
        or tonumber(relation.param03) ~= 2
        or tonumber(relation.param04) ~= 0
        or tonumber(relation.param05) ~= 0
        or tonumber(relation.trigger_id) ~= -1
        or relation.reason ~= TYPE20_DELAYED_EFFECT_REASON
        or type(relation.fingerprint_fields) ~= "table"
        or table.concat(relation.fingerprint_fields, ":")
            ~= "Category:Combo:Projectile:State"
        or type(relation.source_action_ids) ~= "table"
        or #relation.source_action_ids < 2 then
        return false
    end
    for index, source_id in ipairs(relation.source_action_ids) do
        source_id = tonumber(source_id)
        if source_id == nil or source_id == tonumber(target_action_id)
            or (index > 1 and tonumber(relation.source_action_ids[index - 1]) >= source_id) then
            return false
        end
    end
    return true
end

local function same_contextual_effect_relation(left, right)
    if not valid_contextual_effect_relation(left, left and left.target_action_id)
        or not valid_contextual_effect_relation(right, right and right.target_action_id)
        or tonumber(left.target_action_id) ~= tonumber(right.target_action_id)
        or tonumber(left.action_frame) ~= tonumber(right.action_frame)
        or tonumber(left.param01) ~= tonumber(right.param01)
        or #left.source_action_ids ~= #right.source_action_ids then
        return false
    end
    for index, source_id in ipairs(left.source_action_ids) do
        if tonumber(source_id) ~= tonumber(right.source_action_ids[index]) then return false end
    end
    return true
end

local RUNTIME_COMMON_ACTIONS = {
    [17] = "66",
    [18] = "44",
    [36] = "8",
    [37] = "9",
    [38] = "7",
    [489] = "DP"
}
local command_display_cache = {}
local command_display_runtime = {
    cache_status = {},
    seen_refs = setmetatable({}, { __mode = "k" }),
    seen_keys = {}
}
local build_slim_command_display_map

local function reset_command_display_cache()
    for key in pairs(command_display_cache) do
        command_display_cache[key] = nil
    end
    for key in pairs(command_display_runtime.cache_status) do
        command_display_runtime.cache_status[key] = nil
    end
end

local function get_sequence_meta(sequence)
    if type(sequence) ~= "table" then return nil end
    local first = sequence[1]
    return get_meta_table(first)
end

local function is_modern_sequence(sequence)
    local meta = get_sequence_meta(sequence)
    if not meta then return false end
    local control_mode = tostring(meta.control_mode or ""):lower()
    local control_type = tostring(meta.control_type or ""):lower()
    local input_profile = tostring(meta.timeline_input_profile or ""):lower()
    return control_mode == "modern" or control_type == "modern" or input_profile == "modern"
end

local function get_sequence_character(sequence)
    local meta = get_sequence_meta(sequence)
    if not meta then return nil end
    local character = meta.character
    if type(character) ~= "string" or character == "" then return nil end
    return character
end

local function clean_meta_text(value)
    if value == nil then return "" end
    return trim_string(value)
end

local function get_upload_date(meta)
    if type(meta) ~= "table" then return "" end

    local raw = meta.uploaded_at or meta.uploadDate or meta.uploadedAt or meta.upload_date or
        meta.created_at or meta.createdAt or meta.updated_at or meta.updatedAt
    local value = clean_meta_text(raw)
    if value == "" then return "" end

    local ymd = value:match("^(%d%d%d%d%-%d%d%-%d%d)")
    return ymd or value
end

local function get_step_notes_table(meta)
    if type(meta) ~= "table" or type(meta.step_notes) ~= "table" then return nil end
    return meta.step_notes
end

local function get_display_line_note(meta, first_idx, last_idx)
    local step_notes = get_step_notes_table(meta)
    if not step_notes then return "" end

    local parts = {}
    for idx = first_idx or 1, last_idx or first_idx or 1 do
        local note = clean_meta_text(step_notes[idx])
        if note == "" then note = clean_meta_text(step_notes[tostring(idx)]) end
        if note ~= "" then table.insert(parts, note) end
    end
    return table.concat(parts, " / ")
end

local function has_nonempty_step_note(meta)
    local step_notes = get_step_notes_table(meta)
    if not step_notes then return false end
    for _, value in pairs(step_notes) do
        if clean_meta_text(value) ~= "" then return true end
    end
    return false
end

local function has_trial_note_content(meta)
    if type(meta) ~= "table" then return false end
    return clean_meta_text(meta.author) ~= "" or clean_meta_text(meta.note) ~= "" or
        get_upload_date(meta) ~= "" or has_nonempty_step_note(meta)
end

local function build_author_upload_line(meta)
    if not has_trial_note_content(meta) then return "" end

    local author = clean_meta_text(meta.author)
    if author == "" then author = "不明" end

    local upload = get_upload_date(meta)
    local line = "连段由 " .. author .. " 录制于"
    if upload == "" then upload = "不明" end
    line = line .. " " .. upload
    return line
end

local function load_command_display_map(character)
    local key = tostring(character or "")
    key = key:gsub("[^%w_]", "")
    if key == "" or key == "Unknown" then return nil, "invalid_character" end

    if command_display_cache[key] ~= nil then
        return command_display_cache[key] ~= false and command_display_cache[key] or nil,
            command_display_runtime.cache_status[key]
    end

    local path = COMMAND_DISPLAY_DIR .. key .. ".json"
    local ok, loaded = false, nil
    if type(_G.safe_load_json) == "function" then
        ok, loaded = pcall(_G.safe_load_json, path)
    elseif json and json.load_file then
        ok, loaded = pcall(json.load_file, path)
    end

    local meta = ok and type(loaded) == "table" and loaded._meta or nil
    local audit = type(meta) == "table" and meta.audit or nil
    local schema = type(meta) == "table" and tostring(meta.schema or ""):lower() or ""
    local policy = type(meta) == "table" and tostring(meta.strict_policy or ""):lower() or ""
    local has_rebind_audit = type(audit) == "table"
        and (audit.ac_type17_relation_count ~= nil
            or audit.ac_command_entry_rebind_signature_count ~= nil
            or audit.ac_command_entry_rebind_relation_count ~= nil
            or audit.ac_command_entry_rebind_route_count ~= nil)
    local rebind_audit_ok = not has_rebind_audit
    if has_rebind_audit then
        local type17 = tonumber(audit.ac_type17_relation_count)
        local signatures = tonumber(audit.ac_command_entry_rebind_signature_count)
        local relations = tonumber(audit.ac_command_entry_rebind_relation_count)
        local routes = tonumber(audit.ac_command_entry_rebind_route_count)
        rebind_audit_ok = type17 ~= nil and signatures ~= nil and relations ~= nil and routes ~= nil
            and type17 >= signatures and signatures >= relations and routes >= relations and relations >= 0
            and type17 == math.floor(type17) and signatures == math.floor(signatures)
            and relations == math.floor(relations) and routes == math.floor(routes)
            and (meta.rebind_route_count == nil or tonumber(meta.rebind_route_count) == routes)
            and type(meta.ac_command_entry_rebinds) == "table"
            and #meta.ac_command_entry_rebinds == relations
    end
    local has_runtime_common_audit = type(audit) == "table"
        and (audit.runtime_common_action_count ~= nil or audit.runtime_common_route_count ~= nil)
    local runtime_common_audit_ok = not has_runtime_common_audit
    if has_runtime_common_audit then
        local actions = tonumber(audit.runtime_common_action_count)
        local routes = tonumber(audit.runtime_common_route_count)
        runtime_common_audit_ok = actions ~= nil and routes ~= nil and actions >= 0 and routes == actions
            and actions == math.floor(actions) and routes == math.floor(routes)
            and tonumber(meta.runtime_common_route_count) == routes
            and type(meta.runtime_common_actions) == "table"
            and #meta.runtime_common_actions == actions
    end
    local official_routes = type(audit) == "table" and tonumber(audit.official_semantic_route_count) or nil
    local official_bindings = type(audit) == "table" and tonumber(audit.official_semantic_binding_count) or nil
    local official_unresolved = type(audit) == "table" and tonumber(audit.official_semantic_unresolved_count) or nil
    local official_qualified = type(audit) == "table"
        and tonumber(audit.official_semantic_qualified_direct_route_count) or nil
    local official_semantic_audit_ok = official_routes ~= nil and official_bindings ~= nil
        and official_unresolved ~= nil and official_qualified ~= nil
        and official_routes >= 0 and official_bindings >= 0 and official_qualified >= 0
        and official_unresolved >= 0 and official_routes == math.floor(official_routes)
        and official_bindings == math.floor(official_bindings)
        and official_unresolved == math.floor(official_unresolved)
        and official_qualified == math.floor(official_qualified)
        and tonumber(meta.official_semantic_route_count) == official_routes
        and tonumber(meta.official_semantic_qualified_direct_route_count) == official_qualified
        and type(meta.official_semantic_bindings) == "table"
        and #meta.official_semantic_bindings == official_bindings
        and type(meta.official_semantic_unresolved) == "table"
        and #meta.official_semantic_unresolved == official_unresolved
    local community_routes = type(audit) == "table" and tonumber(audit.community_semantic_route_count) or nil
    local community_bindings = type(audit) == "table" and tonumber(audit.community_semantic_binding_count) or nil
    local community_unresolved = type(audit) == "table" and tonumber(audit.community_semantic_unresolved_count) or nil
    local community_qualified = type(audit) == "table"
        and tonumber(audit.community_semantic_qualified_direct_route_count) or nil
    local community_semantic_audit_ok = community_routes ~= nil and community_bindings ~= nil
        and community_unresolved ~= nil and community_qualified ~= nil
        and community_routes >= 0 and community_bindings >= 0 and community_unresolved >= 0
        and community_qualified >= 0 and community_routes == math.floor(community_routes)
        and community_bindings == math.floor(community_bindings)
        and community_unresolved == math.floor(community_unresolved)
        and community_qualified == math.floor(community_qualified)
        and tonumber(meta.community_semantic_route_count) == community_routes
        and tonumber(meta.community_semantic_qualified_direct_route_count) == community_qualified
        and type(meta.community_semantic_bindings) == "table"
        and #meta.community_semantic_bindings == community_bindings
        and type(meta.community_semantic_unresolved) == "table"
        and #meta.community_semantic_unresolved == community_unresolved
    local verified_alias_relations = type(audit) == "table"
        and tonumber(audit.verified_alias_relation_count) or nil
    local verified_alias_routes = type(audit) == "table"
        and tonumber(audit.verified_alias_route_count) or nil
    local verified_alias_audit_ok = verified_alias_relations ~= nil and verified_alias_routes ~= nil
        and verified_alias_relations >= 0 and verified_alias_routes >= verified_alias_relations
        and verified_alias_relations == math.floor(verified_alias_relations)
        and verified_alias_routes == math.floor(verified_alias_routes)
        and tonumber(meta.verified_alias_route_count) == verified_alias_routes
        and type(meta.verified_alias_relations) == "table"
        and #meta.verified_alias_relations == verified_alias_relations
    local type20_relations = type(audit) == "table"
        and tonumber(audit.type20_directional_relation_count) or nil
    local type20_routes = type(audit) == "table"
        and tonumber(audit.type20_directional_route_count) or nil
    local type20_audit_ok = type20_relations ~= nil and type20_routes ~= nil
        and type20_relations >= 0 and type20_routes >= type20_relations
        and tonumber(meta.type20_directional_route_count) == type20_routes
        and type(meta.type20_directional_relations) == "table"
        and #meta.type20_directional_relations == type20_relations
    local type63_strength_audit_ok = Type63StrengthSemantics.validate_audit(meta, audit)
    local type20_hold_relations = type(audit) == "table"
        and tonumber(audit.type20_hold_relation_count) or nil
    local type20_hold_routes = type(audit) == "table"
        and tonumber(audit.type20_hold_route_count) or nil
    local type20_hold_audit_ok = type20_hold_relations ~= nil and type20_hold_routes ~= nil
        and type20_hold_relations >= 0 and type20_hold_routes == type20_hold_relations
        and type20_hold_relations == math.floor(type20_hold_relations)
        and type20_hold_routes == math.floor(type20_hold_routes)
        and tonumber(meta.type20_hold_route_count) == type20_hold_routes
        and type(meta.type20_hold_relations) == "table"
        and #meta.type20_hold_relations == type20_hold_relations
    local type20_phase_relations = type(audit) == "table"
        and tonumber(audit.type20_action_phase_relation_count) or nil
    local type20_phase_routes = type(audit) == "table"
        and tonumber(audit.type20_action_phase_route_count) or nil
    local type20_phase_audit_ok = type20_phase_relations ~= nil and type20_phase_routes ~= nil
        and type20_phase_relations >= 0 and type20_phase_routes >= type20_phase_relations
        and type20_phase_relations == math.floor(type20_phase_relations)
        and type20_phase_routes == math.floor(type20_phase_routes)
        and tonumber(meta.type20_action_phase_route_count) == type20_phase_routes
        and type(meta.type20_action_phase_relations) == "table"
        and #meta.type20_action_phase_relations == type20_phase_relations
    local has_type20_terminal_phase_audit = type(audit) == "table"
        and (audit.type20_terminal_command_phase_relation_count ~= nil
            or audit.type20_terminal_command_phase_route_count ~= nil)
    local type20_terminal_phase_relations = has_type20_terminal_phase_audit
        and tonumber(audit.type20_terminal_command_phase_relation_count) or nil
    local type20_terminal_phase_routes = has_type20_terminal_phase_audit
        and tonumber(audit.type20_terminal_command_phase_route_count) or nil
    local type20_terminal_phase_audit_ok = not has_type20_terminal_phase_audit
        or (type20_terminal_phase_relations ~= nil and type20_terminal_phase_routes ~= nil
            and type20_terminal_phase_relations >= 0
            and type20_terminal_phase_routes >= type20_terminal_phase_relations
            and type20_terminal_phase_relations == math.floor(type20_terminal_phase_relations)
            and type20_terminal_phase_routes == math.floor(type20_terminal_phase_routes)
            and tonumber(meta.type20_terminal_command_phase_route_count)
                == type20_terminal_phase_routes
            and type(meta.type20_terminal_command_phase_relations) == "table"
            and #meta.type20_terminal_command_phase_relations
                == type20_terminal_phase_relations)
    local type20_delayed_effect_relations = type(audit) == "table"
        and tonumber(audit.type20_delayed_effect_relation_count) or nil
    local type20_delayed_effect_routes = type(audit) == "table"
        and tonumber(audit.type20_delayed_effect_route_count) or nil
    local type20_delayed_effect_audit_ok = type20_delayed_effect_relations ~= nil
        and type20_delayed_effect_routes ~= nil
        and type20_delayed_effect_relations >= 0
        and type20_delayed_effect_routes >= 0
        and type20_delayed_effect_routes <= type20_delayed_effect_relations
        and type20_delayed_effect_relations == math.floor(type20_delayed_effect_relations)
        and type20_delayed_effect_routes == math.floor(type20_delayed_effect_routes)
        and tonumber(meta.type20_delayed_effect_route_count) == type20_delayed_effect_routes
        and type(meta.type20_delayed_effect_relations) == "table"
        and #meta.type20_delayed_effect_relations == type20_delayed_effect_relations
    local has_type20_same_structure_audit = type(audit) == "table"
        and (audit.type20_same_structure_execution_relation_count ~= nil
            or audit.type20_same_structure_execution_route_count ~= nil)
    local type20_same_structure_relations = has_type20_same_structure_audit
        and tonumber(audit.type20_same_structure_execution_relation_count) or nil
    local type20_same_structure_routes = has_type20_same_structure_audit
        and tonumber(audit.type20_same_structure_execution_route_count) or nil
    local type20_same_structure_audit_ok = not has_type20_same_structure_audit
        or (type20_same_structure_relations ~= nil and type20_same_structure_routes ~= nil
            and type20_same_structure_relations >= 0
            and type20_same_structure_routes >= type20_same_structure_relations
            and type20_same_structure_relations == math.floor(type20_same_structure_relations)
            and type20_same_structure_routes == math.floor(type20_same_structure_routes)
            and tonumber(meta.type20_same_structure_execution_route_count)
                == type20_same_structure_routes
            and type(meta.type20_same_structure_execution_relations) == "table"
            and #meta.type20_same_structure_execution_relations
                == type20_same_structure_relations)
    local has_type37_followup_phase_audit = type(audit) == "table"
        and (audit.type37_followup_execution_phase_relation_count ~= nil
            or audit.type37_followup_execution_phase_route_count ~= nil)
    local type37_followup_phase_relations = has_type37_followup_phase_audit
        and tonumber(audit.type37_followup_execution_phase_relation_count) or nil
    local type37_followup_phase_routes = has_type37_followup_phase_audit
        and tonumber(audit.type37_followup_execution_phase_route_count) or nil
    local type37_followup_phase_audit_ok = not has_type37_followup_phase_audit
        or (type37_followup_phase_relations ~= nil and type37_followup_phase_routes ~= nil
        and type37_followup_phase_relations >= 0
        and type37_followup_phase_routes >= type37_followup_phase_relations
        and type37_followup_phase_relations == math.floor(type37_followup_phase_relations)
        and type37_followup_phase_routes == math.floor(type37_followup_phase_routes)
        and tonumber(meta.type37_followup_execution_phase_route_count)
            == type37_followup_phase_routes
        and type(meta.type37_followup_execution_phase_relations) == "table"
        and #meta.type37_followup_execution_phase_relations
            == type37_followup_phase_relations)
    local target_combo_relations = type(audit) == "table"
        and tonumber(audit.target_combo_repeat_relation_count) or nil
    local target_combo_routes = type(audit) == "table"
        and tonumber(audit.target_combo_repeat_route_count) or nil
    local target_combo_audit_ok = target_combo_relations ~= nil and target_combo_routes ~= nil
        and target_combo_relations >= 0 and target_combo_routes >= target_combo_relations
        and tonumber(meta.target_combo_repeat_route_count) == target_combo_routes
        and type(meta.target_combo_repeat_relations) == "table"
        and #meta.target_combo_repeat_relations == target_combo_relations
    local structural_twin_relations = type(audit) == "table"
        and tonumber(audit.structural_twin_relation_count) or nil
    local structural_twin_routes = type(audit) == "table"
        and tonumber(audit.structural_twin_route_count) or nil
    local structural_twin_audit_ok = structural_twin_relations ~= nil and structural_twin_routes ~= nil
        and structural_twin_relations >= 0 and structural_twin_routes >= structural_twin_relations
        and tonumber(meta.structural_twin_route_count) == structural_twin_routes
        and type(meta.structural_twin_relations) == "table"
        and #meta.structural_twin_relations == structural_twin_relations
    local assist_combo_candidates = type(audit) == "table"
        and tonumber(audit.assist_combo_candidate_count) or nil
    local assist_combo_relations = type(audit) == "table"
        and tonumber(audit.assist_combo_relation_count) or nil
    local assist_combo_routes = type(audit) == "table"
        and tonumber(audit.assist_combo_route_count) or nil
    local assist_combo_duplicates = type(audit) == "table"
        and tonumber(audit.assist_combo_duplicate_display_count) or nil
    local assist_combo_normalized = type(audit) == "table"
        and tonumber(audit.assist_combo_normalized_to_existing_count) or nil
    local assist_combo_chain_count = type(audit) == "table"
        and tonumber(audit.assist_combo_chain_count) or nil
    local assist_combo_audit_ok = assist_combo_candidates ~= nil and assist_combo_relations ~= nil
        and assist_combo_routes ~= nil and assist_combo_duplicates ~= nil
        and assist_combo_normalized ~= nil
        and assist_combo_candidates >= 0 and assist_combo_relations >= 0
        and assist_combo_routes == assist_combo_relations
        and assist_combo_duplicates >= 0 and assist_combo_normalized >= 0
        and assist_combo_candidates == assist_combo_relations
            + assist_combo_duplicates + assist_combo_normalized
        and assist_combo_candidates == math.floor(assist_combo_candidates)
        and assist_combo_relations == math.floor(assist_combo_relations)
        and assist_combo_routes == math.floor(assist_combo_routes)
        and assist_combo_duplicates == math.floor(assist_combo_duplicates)
        and assist_combo_normalized == math.floor(assist_combo_normalized)
        and tonumber(meta.assist_combo_route_count) == assist_combo_routes
        and tonumber(meta.assist_combo_normalized_to_existing_count) == assist_combo_normalized
        and type(meta.assist_combo_relations) == "table"
        and #meta.assist_combo_relations == assist_combo_relations
    if assist_combo_audit_ok
        and (assist_combo_chain_count ~= nil or meta.assist_combo_chains ~= nil) then
        local chains = type(meta.assist_combo_chains) == "table"
            and meta.assist_combo_chains or {}
        local expected = assist_combo_chain_count
            or (assist_combo_chain_count == nil and #chains) or nil
        if expected == nil
            or tonumber(meta.assist_combo_chain_count) ~= expected
            or #chains ~= expected then
            assist_combo_audit_ok = false
        else
            local seen_action_positions = {}
            local valid = true
            for _, chain in ipairs(chains) do
                if type(chain) ~= "table"
                    or type(chain.strength) ~= "string" or chain.strength == ""
                    or type(chain.steps) ~= "table" or #chain.steps == 0 then
                    valid = false
                    break
                end
                local prior_position = nil
                for _, step in ipairs(chain.steps) do
                    local position = step ~= nil and tonumber(step.position) or nil
                    local action_ids = type(step) == "table" and step.action_ids or nil
                    if position == nil or position < 1
                        or (prior_position ~= nil and position <= prior_position)
                        or type(action_ids) ~= "table" or #action_ids == 0 then
                        valid = false
                        break
                    end
                    for _, action in ipairs(action_ids) do
                        local aid = tonumber(action)
                        if aid == nil then valid = false; break end
                        seen_action_positions[aid] = true
                    end
                    if not valid then break end
                    prior_position = position
                end
                if not valid then break end
            end
            assist_combo_audit_ok = assist_combo_audit_ok and valid
        end
    end
    local paired_sprt_sp_relations = type(audit) == "table"
        and tonumber(audit.paired_sprt_sp_relation_count) or nil
    local paired_sprt_sp_routes = type(audit) == "table"
        and tonumber(audit.paired_sprt_sp_route_count) or nil
    local paired_sprt_sp_audit_ok = paired_sprt_sp_relations ~= nil
        and paired_sprt_sp_routes ~= nil
        and paired_sprt_sp_relations >= 0
        and paired_sprt_sp_routes == paired_sprt_sp_relations
        and paired_sprt_sp_relations == math.floor(paired_sprt_sp_relations)
        and paired_sprt_sp_routes == math.floor(paired_sprt_sp_routes)
        and tonumber(meta.paired_sprt_sp_route_count) == paired_sprt_sp_routes
        and type(meta.paired_sprt_sp_relations) == "table"
        and #meta.paired_sprt_sp_relations == paired_sprt_sp_relations
    local shadowed_supr_count = type(audit) == "table"
        and tonumber(audit.shadowed_supr_route_count) or nil
    local shadowed_supr_audit_ok = shadowed_supr_count ~= nil
        and shadowed_supr_count >= 0
        and shadowed_supr_count == math.floor(shadowed_supr_count)
        and tonumber(meta.shadowed_supr_route_count) == shadowed_supr_count
        and type(meta.shadowed_supr_routes) == "table"
        and #meta.shadowed_supr_routes == shadowed_supr_count
    local hold_transition_aliases = type(audit) == "table"
        and tonumber(audit.hold_transition_type29_alias_suppression_count) or nil
    local hold_transition_actions = type(audit) == "table"
        and tonumber(audit.hold_transition_suppressed_action_count) or nil
    local hold_transition_audit_ok = hold_transition_aliases ~= nil
        and hold_transition_actions ~= nil and hold_transition_aliases >= 0
        and hold_transition_actions >= 0 and hold_transition_actions <= hold_transition_aliases
        and hold_transition_aliases == math.floor(hold_transition_aliases)
        and hold_transition_actions == math.floor(hold_transition_actions)
        and tonumber(meta.hold_transition_type29_alias_suppression_count) == hold_transition_aliases
        and tonumber(meta.hold_transition_suppressed_action_count) == hold_transition_actions
        and type(meta.hold_transition_type29_alias_suppressions) == "table"
        and #meta.hold_transition_type29_alias_suppressions == hold_transition_aliases
    local charge_context_routes = type(audit) == "table"
        and tonumber(audit.charge_context_route_count) or nil
    local super_shortcut_routes = type(audit) == "table"
        and tonumber(audit.super_shortcut_direction_route_count) or nil
    local ac_charge_relations = type(audit) == "table"
        and tonumber(audit.ac_charge_context_relation_count) or nil
    local charge_suppressions = type(audit) == "table"
        and tonumber(audit.charge_compatibility_trigger_suppression_count) or nil
    local charge_context_audit_ok = charge_context_routes ~= nil
        and super_shortcut_routes ~= nil and ac_charge_relations ~= nil
        and charge_suppressions ~= nil
        and charge_context_routes >= 0 and super_shortcut_routes >= 0
        and ac_charge_relations >= 0 and charge_suppressions >= 0
        and charge_context_routes == math.floor(charge_context_routes)
        and super_shortcut_routes == math.floor(super_shortcut_routes)
        and ac_charge_relations == math.floor(ac_charge_relations)
        and charge_suppressions == math.floor(charge_suppressions)
        and tonumber(meta.charge_context_route_count) == charge_context_routes
        and tonumber(meta.super_shortcut_direction_route_count) == super_shortcut_routes
        and tonumber(meta.ac_charge_context_relation_count) == ac_charge_relations
        and type(meta.ac_charge_context_relations) == "table"
        and #meta.ac_charge_context_relations == ac_charge_relations
        and tonumber(meta.charge_compatibility_trigger_suppression_count) == charge_suppressions
        and type(meta.charge_compatibility_trigger_suppressions) == "table"
        and #meta.charge_compatibility_trigger_suppressions == charge_suppressions
    if charge_context_audit_ok then
        for _, relation in ipairs(meta.charge_compatibility_trigger_suppressions) do
            if type(relation) ~= "table" or tonumber(relation.action_id) == nil
                or tonumber(relation.suppressed_trigger_index) == nil
                or type(relation.retained_trigger_indices) ~= "table"
                or #relation.retained_trigger_indices == 0
                or relation.profile ~= "sprt"
                or relation.reason ~= CHARGE_COMPATIBILITY_REASON then
                charge_context_audit_ok = false
                break
            end
        end
    end
    if charge_context_audit_ok then
        for _, relation in ipairs(meta.ac_charge_context_relations) do
            if type(relation) ~= "table" or tonumber(relation.source_action_id) == nil
                or tonumber(relation.target_action_id) == nil
                or tonumber(relation.source_action_id) == tonumber(relation.target_action_id)
                or tonumber(relation.target_trigger_index) == nil
                or type(relation.source_trigger_indices) ~= "table"
                or #relation.source_trigger_indices == 0
                or (relation.profile ~= "easy" and relation.profile ~= "supr")
                or type(relation.direction) ~= "string"
                or relation.direction:match("^[1246789]$") == nil
                or (relation.source_charge_profile ~= "sprt"
                    and relation.source_charge_profile ~= "norm")
                or relation.reason ~= AC_CHARGE_CONTEXT_REASON then
                charge_context_audit_ok = false
                break
            end
        end
    end
    local official_direct_restrictions = type(audit) == "table"
        and tonumber(audit.official_direct_route_restriction_count) or nil
    local state_direction_relations = type(audit) == "table"
        and tonumber(audit.ac_state_direction_relation_count) or nil
    local state_direction_routes = type(audit) == "table"
        and tonumber(audit.ac_state_direction_route_count) or nil
    local state_neutral_relations = type(audit) == "table"
        and tonumber(audit.ac_state_neutral_relation_count) or nil
    local state_neutral_routes = type(audit) == "table"
        and tonumber(audit.ac_state_neutral_route_count) or nil
    local type13_neutral_relations = type(audit) == "table"
        and tonumber(audit.ac_type13_neutral_relation_count) or nil
    local type13_neutral_routes = type(audit) == "table"
        and tonumber(audit.ac_type13_neutral_route_count) or nil
    local internal_suppressions = type(audit) == "table"
        and tonumber(audit.internal_transition_suppression_count) or nil
    local state_choice_audit_ok = official_direct_restrictions ~= nil
        and state_direction_relations ~= nil and state_direction_routes ~= nil
        and state_neutral_relations ~= nil and state_neutral_routes ~= nil
        and type13_neutral_relations ~= nil and type13_neutral_routes ~= nil
        and internal_suppressions ~= nil
        and official_direct_restrictions >= 0
        and state_direction_relations >= 0 and state_direction_routes == state_direction_relations
        and state_neutral_relations >= 0 and state_neutral_routes == state_neutral_relations
        and type13_neutral_relations >= 0 and type13_neutral_routes == type13_neutral_relations
        and internal_suppressions >= 0
        and tonumber(meta.official_direct_route_restriction_count) == official_direct_restrictions
        and type(meta.official_direct_route_restrictions) == "table"
        and #meta.official_direct_route_restrictions == official_direct_restrictions
        and tonumber(meta.ac_state_direction_route_count) == state_direction_routes
        and type(meta.ac_state_direction_relations) == "table"
        and #meta.ac_state_direction_relations == state_direction_relations
        and tonumber(meta.ac_state_neutral_route_count) == state_neutral_routes
        and type(meta.ac_state_neutral_relations) == "table"
        and #meta.ac_state_neutral_relations == state_neutral_relations
        and tonumber(meta.ac_type13_neutral_route_count) == type13_neutral_routes
        and type(meta.ac_type13_neutral_relations) == "table"
        and #meta.ac_type13_neutral_relations == type13_neutral_relations
        and tonumber(meta.internal_transition_suppression_count) == internal_suppressions
        and type(meta.suppressed_internal_transitions) == "table"
        and #meta.suppressed_internal_transitions == internal_suppressions
    local split_command_audit_ok = true
    if schema == "xt.command_display.v1" then
        local split_actions = type(audit) == "table"
            and tonumber(audit.split_command_action_count) or nil
        local followup_count = type(audit) == "table"
            and tonumber(audit.followup_relation_count) or nil
        local overflow_count = type(audit) == "table"
            and tonumber(audit.command_slot_overflow_count) or nil
        split_command_audit_ok = split_actions ~= nil and followup_count ~= nil
            and overflow_count == 0 and split_actions >= 0 and followup_count >= 0
            and split_actions == math.floor(split_actions)
            and followup_count == math.floor(followup_count)
            and tonumber(meta.split_command_action_count) == split_actions
            and tonumber(meta.followup_relation_count) == followup_count
            and type(meta.followup_relations) == "table"
            and #meta.followup_relations == followup_count
        if split_command_audit_ok then
            for _, relation in ipairs(meta.followup_relations) do
                if type(relation) ~= "table" or relation.type ~= "followup"
                    or tonumber(relation.source_action_id) == nil
                    or tonumber(relation.target_action_id) == nil
                    or tonumber(relation.source_action_id) == tonumber(relation.target_action_id)
                    or relation.evidence ~= "capcom_official_followup_context_matches_source_move" then
                    split_command_audit_ok = false
                    break
                end
            end
        end
    end
    local unified_command_audit_ok = true
    if schema == "xt.command_display.v1" then
        local classic_count = 0
        local shared_count = 0
        local action_count = 0
        for action_id, entry in pairs(loaded) do
            if tostring(action_id):match("^%d+$") and type(entry) == "table" then
                action_count = action_count + 1
                local classic = entry.classic_command
                local has_classic = type(classic) == "table"
                    and type(classic.display) == "string" and trim_string(classic.display) ~= ""
                    and type(classic.inputs) == "table" and #classic.inputs > 0
                if has_classic then
                    for _, input in ipairs(classic.inputs) do
                        if type(input) ~= "string" or trim_string(input) == "" then
                            has_classic = false
                            break
                        end
                    end
                elseif classic ~= nil then
                    unified_command_audit_ok = false
                end
                local has_modern = type(entry.simple_command) == "table"
                    or type(entry.motion_command) == "table"
                if has_classic then classic_count = classic_count + 1 end
                if has_classic and has_modern then shared_count = shared_count + 1 end
            end
        end
        unified_command_audit_ok = unified_command_audit_ok
            and tonumber(audit and audit.classic_command_action_count) == classic_count
            and tonumber(audit and audit.shared_command_action_count) == shared_count
            and tonumber(audit and audit.classic_projection_pending_count)
                == tonumber(audit and audit.split_command_action_count) - shared_count
            and tonumber(audit and audit.classic_projection_pending_count) == 0
            and tonumber(audit and audit.command_display_action_count) == action_count
            and type(meta.classic_profile_order) == "table"
            and meta.classic_profile_order[1] == "norm"
            and meta.classic_profile_order[2] == "sprt"
        local projection_count = tonumber(meta.classic_projection_relation_count)
        local projection_relations = meta.classic_projection_relations
        unified_command_audit_ok = unified_command_audit_ok
            and projection_count ~= nil
            and tonumber(audit and audit.classic_projection_relation_count) == projection_count
            and type(projection_relations) == "table"
            and #projection_relations == projection_count
        local projection_reasons = {
            ac_full_structure_unique_classic_projection = true,
            ac_full_structure_bcm_condition_classic_projection = true,
            ac_full_structure_assist_strength_classic_projection = true,
            bcm_unique_condition_classic_projection = true,
        }
        if unified_command_audit_ok then
            for _, relation in ipairs(projection_relations) do
                if type(relation) ~= "table"
                    or tonumber(relation.source_action_id) == nil
                    or tonumber(relation.target_action_id) == nil
                    or tonumber(relation.source_action_id) == tonumber(relation.target_action_id)
                    or type(relation.classic_display) ~= "string"
                    or trim_string(relation.classic_display) == ""
                    or projection_reasons[relation.reason] ~= true then
                    unified_command_audit_ok = false
                    break
                end
            end
        end
    end
    local strict_audit = type(audit) == "table" and audit.strict_route_ownership == true
        and tonumber(audit.owner_missing_count or -1) == 0
        and tonumber(audit.no_evidence_count or -1) == 0
        and tonumber(audit.direct_overridden_count or -1) == 0
        and tonumber(audit.overlay_entry_count or -1) == 0
        and tonumber(audit.community_route_count or -1) == 0
        and tonumber(audit.alias_propagation_count or -1) == 0
        and tonumber(audit.type17_route_count or -1) == 0
        and tonumber(audit.ac_automatic_transition_route_count or -1) == 0
        and tonumber(audit.replaces_profile_route_count or -1) == 0
        and tonumber(audit.non_whitelist_propagation_count or -1) == 0
        and rebind_audit_ok
        and runtime_common_audit_ok
        and official_semantic_audit_ok
        and community_semantic_audit_ok
        and verified_alias_audit_ok
        and type20_audit_ok
        and type63_strength_audit_ok
        and type20_hold_audit_ok
        and type20_phase_audit_ok
        and type20_terminal_phase_audit_ok
        and type20_delayed_effect_audit_ok
        and type20_same_structure_audit_ok
        and type37_followup_phase_audit_ok
        and target_combo_audit_ok
        and structural_twin_audit_ok
        and assist_combo_audit_ok
        and paired_sprt_sp_audit_ok
        and shadowed_supr_audit_ok
        and hold_transition_audit_ok
        and charge_context_audit_ok
        and state_choice_audit_ok
        and split_command_audit_ok
        and unified_command_audit_ok
    local supported_schema = schema == "xt.command_display.v1"
        and policy == "verified_action_graph_v1"
    if type(meta) == "table"
        and supported_schema
        and (tostring(meta.generated_from or ""):lower() == "ac_bcm"
            or tostring(meta.generated_from or ""):lower() == "ac_bcm+capcom_official_semantics"
            or tostring(meta.generated_from or ""):lower() == "ac_bcm+community_verified_semantics"
            or tostring(meta.generated_from or ""):lower() == "ac_bcm+capcom_official_semantics+community_verified_semantics")
        and tostring(meta.character or "") == key
        and strict_audit then
        local slim = build_slim_command_display_map(loaded)
        slim = CommandDisplayOverrides.load_and_merge(slim, key, function(filename)
            if type(_G.safe_load_json) == "function" then
                return _G.safe_load_json(filename)
            end
            return json.load_file(filename)
        end)
        slim._action_compatibility = select(1, ActionCompatibility.load(
            key,
            SF6CCVersion.GAME_VERSION,
            function(filename)
                if type(_G.safe_load_json) == "function" then
                    return _G.safe_load_json(filename)
                end
                return json.load_file(filename)
            end
        ))
        loaded = nil
        command_display_cache[key] = slim
        command_display_runtime.cache_status[key] = "loaded"
        return slim, "loaded"
    end

    command_display_cache[key] = false
    command_display_runtime.cache_status[key] = ok and "invalid_schema_or_policy" or "map_load_failed"
    return nil, command_display_runtime.cache_status[key]
end

local function get_player_visible_transition_motion(step)
    if type(step) ~= "table" then return nil end
    local motion = trim_string(step.motion)
    if motion == "" then return nil end
    if step.player_input_transition == true or step._ct_player_input_transition == true then return motion end
    local upper = motion:upper()
    if motion:match("^>") and (upper:find("FEINT", 1, true)
        or upper:find("CANCEL", 1, true)
        or motion:find("取消", 1, true)
        or motion:find("假动作", 1, true)) then
        return motion
    end
    return nil
end

local function get_recorded_universal_motion(step)
    if type(step) ~= "table" then return nil end
    -- Historical DI compatibility is an explicit Action-ID variant
    -- (854 -> 855), not permission to trust arbitrary saved motion text for
    -- an unmapped Action.
    local action_id = tonumber(step.id)
    if action_id ~= 854 and action_id ~= 855 then return nil end
    local motion = trim_string(step.motion):upper():gsub("%s+", "")
    if motion == "DI" or motion == "HP+HK" then return "DI" end
    return nil
end

local function project_historical_action_step(command_map, step)
    if type(command_map) ~= "table" or type(step) ~= "table" then
        return step, nil
    end
    return ActionCompatibility.project_step(
        command_map._action_compatibility,
        step
    )
end

local function get_modern_display_motion(modern_map, step)
    if type(modern_map) ~= "table" or type(step) ~= "table" then return nil, "map_unavailable" end
    local step_id = tonumber(step.id)
    if modern_map._slim == true then
        local resolved = modern_map[tostring(step.id or "")]
        if type(resolved) ~= "table" then
            local conditioned_motion, conditioned_status =
                CommandDisplayOverrides.resolve_recorded_input_conditioned(
                    modern_map,
                    step.id,
                    step.motion,
                    "simple"
                )
            if conditioned_motion then
                return conditioned_motion, conditioned_status
            end
            local universal_motion = get_recorded_universal_motion(step)
            if universal_motion then return universal_motion, "recorded_universal_command" end
            return nil, "action_id_missing"
        end
        if resolved.status == "suppress_transition" then
            local player_transition = get_player_visible_transition_motion(step)
            if player_transition then return player_transition, "player_input_transition" end
        end
        return resolved.commands or resolved.motion, resolved.status or "route_unverified"
    end
    local entry = modern_map[tostring(step.id or "")]
    if type(entry) ~= "table" or type(entry.routes) ~= "table" then return nil, "action_id_missing" end
    if entry.suppress_display == true then
        local player_transition = get_player_visible_transition_motion(step)
        if player_transition then return player_transition, "player_input_transition" end
        local evidence = entry.transition_evidence
        local declared = false
        local internal_declarations = type(modern_map._meta) == "table"
            and modern_map._meta.suppressed_internal_transitions or nil
        if type(evidence) == "table" and type(internal_declarations) == "table"
            and (entry.ownership == "internal_state_transition"
                or entry.ownership == "internal_execution_phase") and #entry.routes == 0
            and step_id ~= nil and tonumber(evidence.target_action_id) == step_id then
            for _, relation in ipairs(internal_declarations) do
                local same = type(relation) == "table"
                    and tostring(relation.kind or "") == tostring(evidence.kind or "")
                    and tonumber(relation.target_action_id) == step_id
                    and tostring(relation.reason or "") == tostring(evidence.reason or "")
                if same and evidence.kind == "ac_state_direction_release" then
                    same = tonumber(relation.branch_type) == 20
                        and tonumber(relation.param00) == 0
                        and tonumber(relation.direction_mask) == tonumber(evidence.direction_mask)
                        and relation.reason == AC_STATE_RELEASE_REASON
                elseif same and evidence.kind == "bcm_zero_input_transition" then
                    same = tonumber(relation.function_id) == 2
                        and type(relation.trigger_indices) == "table"
                        and #relation.trigger_indices > 0
                        and relation.reason == BCM_ZERO_INPUT_TRANSITION_REASON
                elseif same and evidence.kind == "ac_type2_type4_terminal_execution_phase" then
                    same = entry.ownership == "internal_execution_phase"
                        and tonumber(relation.source_action_id)
                            == tonumber(evidence.source_action_id)
                        and tonumber(relation.source_action_id) ~= step_id
                        and type(relation.branch_types) == "table"
                        and #relation.branch_types == 2
                        and tonumber(relation.branch_types[1]) == 2
                        and tonumber(relation.branch_types[2]) == 4
                        and tonumber(relation.attr) == 0
                        and tonumber(relation.action_frame) == 0
                        and tonumber(relation.param00) == 0
                        and tonumber(relation.param01) == 0
                        and tonumber(relation.param02) == 0
                        and tonumber(relation.param03) == 0
                        and tonumber(relation.param04) == 0
                        and tonumber(relation.param05) == 0
                        and tonumber(relation.trigger_id) == -1
                        and relation.reason == AC_TERMINAL_EXECUTION_PHASE_REASON
                elseif same and evidence.kind == "ac_type2_numbered_execution_phase" then
                    local phase_index = tonumber(relation.phase_index)
                    local expected_attr = phase_index == 1 and 288
                        or phase_index == 2 and 32 or nil
                    local expected_param00 = phase_index == 1 and 1
                        or phase_index == 2 and 2 or nil
                    local expected_target = phase_index == 1
                        and tonumber(relation.middle_action_id)
                        or phase_index == 2 and tonumber(relation.tail_action_id) or nil
                    local fingerprints = relation.fingerprint_fields
                    same = entry.ownership == "internal_execution_phase"
                        and tonumber(relation.source_action_id)
                            == tonumber(evidence.source_action_id)
                        and tonumber(relation.middle_action_id)
                            == tonumber(evidence.middle_action_id)
                        and tonumber(relation.tail_action_id)
                            == tonumber(evidence.tail_action_id)
                        and tonumber(relation.exit_action_id)
                            == tonumber(evidence.exit_action_id)
                        and tonumber(relation.target_action_id) == expected_target
                        and expected_target == step_id
                        and tonumber(relation.branch_type) == 2
                        and tonumber(relation.attr) == expected_attr
                        and tonumber(relation.action_frame) == 0
                        and tonumber(relation.param00) == expected_param00
                        and tonumber(relation.param01) == 0
                        and tonumber(relation.param02) == 0
                        and tonumber(relation.param03) == 0
                        and tonumber(relation.param04) == 0
                        and tonumber(relation.param05) == 0
                        and tonumber(relation.trigger_id) == -1
                        and tonumber(relation.exit_branch_type) == 13
                        and type(fingerprints) == "table" and #fingerprints == 4
                        and fingerprints[1] == "Category" and fingerprints[2] == "Combo"
                        and fingerprints[3] == "Projectile" and fingerprints[4] == "State"
                        and relation.reason == AC_NUMBERED_EXECUTION_PHASE_REASON
                elseif same and evidence.kind == "ac_type2_same_structure_execution_phase" then
                    local phase_index = tonumber(relation.phase_index)
                    local expected_attr = phase_index == 1 and 288
                        or phase_index == 2 and 32 or nil
                    local expected_target = phase_index == 1
                        and tonumber(relation.middle_action_id)
                        or phase_index == 2 and tonumber(relation.tail_action_id) or nil
                    local fingerprints = relation.fingerprint_fields
                    same = entry.ownership == "internal_execution_phase"
                        and tonumber(relation.source_action_id)
                            == tonumber(evidence.source_action_id)
                        and tonumber(relation.middle_action_id)
                            == tonumber(evidence.middle_action_id)
                        and tonumber(relation.tail_action_id)
                            == tonumber(evidence.tail_action_id)
                        and tonumber(relation.source_action_id)
                            ~= tonumber(relation.middle_action_id)
                        and tonumber(relation.middle_action_id)
                            ~= tonumber(relation.tail_action_id)
                        and tonumber(relation.source_action_id)
                            ~= tonumber(relation.tail_action_id)
                        and tonumber(relation.target_action_id) == expected_target
                        and expected_target == step_id
                        and tonumber(relation.branch_type) == 2
                        and tonumber(relation.attr) == expected_attr
                        and tonumber(relation.action_frame) == 0
                        and tonumber(relation.param00) == 0
                        and tonumber(relation.param01) == 0
                        and tonumber(relation.param02) == 0
                        and tonumber(relation.param03) == 0
                        and tonumber(relation.param04) == 0
                        and tonumber(relation.param05) == 0
                        and tonumber(relation.trigger_id) == -1
                        and type(fingerprints) == "table" and #fingerprints == 4
                        and fingerprints[1] == "Category" and fingerprints[2] == "Combo"
                        and fingerprints[3] == "Projectile" and fingerprints[4] == "State"
                        and relation.reason == AC_SAME_STRUCTURE_EXECUTION_PHASE_REASON
                elseif same and evidence.kind == "ac_type37_automatic_execution_phase" then
                    local frames = relation.action_frames
                    local fingerprints = relation.fingerprint_fields
                    local source_action_id = tonumber(relation.source_action_id)
                    local tail_action_id = tonumber(relation.tail_action_id)
                    same = entry.ownership == "internal_execution_phase"
                        and source_action_id ~= nil and source_action_id ~= step_id
                        and source_action_id == tonumber(evidence.source_action_id)
                        and tail_action_id ~= nil and tail_action_id ~= source_action_id
                        and tail_action_id ~= step_id
                        and tail_action_id == tonumber(evidence.tail_action_id)
                        and tonumber(relation.branch_type) == 37
                        and type(frames) == "table" and #frames == 2
                        and tonumber(frames[1]) == 0 and tonumber(frames[2]) ~= nil
                        and tonumber(frames[2]) > 0
                        and tonumber(relation.exit_branch_type) == 12
                        and tonumber(relation.exit_param01) ~= nil
                        and tonumber(relation.exit_param01) > 0
                        and tonumber(relation.exit_param02) ~= nil
                        and tonumber(relation.exit_param02) > 0
                        and type(fingerprints) == "table" and #fingerprints == 4
                        and fingerprints[1] == "Category" and fingerprints[2] == "Combo"
                        and fingerprints[3] == "Projectile" and fingerprints[4] == "State"
                        and relation.reason == AC_TYPE37_AUTOMATIC_EXECUTION_PHASE_REASON
                elseif same and evidence.kind == "ac_type13_terminal_execution_phase" then
                    local source_action_ids = relation.source_action_ids
                    local evidence_source_ids = evidence.source_action_ids
                    same = entry.ownership == "internal_execution_phase"
                        and type(source_action_ids) == "table" and #source_action_ids >= 2
                        and type(evidence_source_ids) == "table"
                        and #evidence_source_ids == #source_action_ids
                        and tonumber(relation.branch_type) == 13
                        and tonumber(relation.attr) == 0
                        and tonumber(relation.action_frame) == 0
                        and tonumber(relation.param00) == 0
                        and tonumber(relation.param01) == 0
                        and tonumber(relation.param02) == 0
                        and tonumber(relation.param03) == 0
                        and tonumber(relation.param04) == 0
                        and tonumber(relation.param05) == 0
                        and tonumber(relation.trigger_id) == -1
                        and relation.reason == AC_TYPE13_TERMINAL_EXECUTION_PHASE_REASON
                    if same then
                        for index, source_id in ipairs(source_action_ids) do
                            if tonumber(source_id) == nil
                                or tonumber(source_id) == step_id
                                or tonumber(evidence_source_ids[index]) ~= tonumber(source_id)
                                or (index > 1 and tonumber(source_action_ids[index - 1])
                                    >= tonumber(source_id)) then
                                same = false
                                break
                            end
                        end
                    end
                elseif same and evidence.kind == "ac_type13_air_landing_execution_phase" then
                    local source_action_ids = relation.source_action_ids
                    local evidence_source_ids = evidence.source_action_ids
                    local auxiliary_source_ids = relation.auxiliary_source_action_ids
                    local evidence_auxiliary_ids = evidence.auxiliary_source_action_ids
                    local exit_target_action_id = tonumber(relation.exit_target_action_id)
                    local auxiliary_branches = relation.auxiliary_branches
                    local evidence_auxiliary_branches = evidence.auxiliary_branches
                    local function exact_auxiliary_branch(value, branch_type, param00)
                        return type(value) == "table"
                            and tonumber(value.branch_type) == branch_type
                            and tonumber(value.attr) == 256
                            and tonumber(value.action_frame) == 0
                            and tonumber(value.param00) == param00
                            and tonumber(value.param01) == 0
                            and tonumber(value.param02) == 0
                            and tonumber(value.param03) == 0
                            and tonumber(value.param04) == 0
                            and tonumber(value.param05) == 0
                            and tonumber(value.trigger_id) == -1
                    end
                    same = entry.ownership == "internal_execution_phase"
                        and type(source_action_ids) == "table" and #source_action_ids >= 2
                        and type(evidence_source_ids) == "table"
                        and #evidence_source_ids == #source_action_ids
                        and type(auxiliary_source_ids) == "table"
                        and type(evidence_auxiliary_ids) == "table"
                        and #evidence_auxiliary_ids == #auxiliary_source_ids
                        and exit_target_action_id ~= nil and exit_target_action_id ~= step_id
                        and exit_target_action_id == tonumber(evidence.exit_target_action_id)
                        and tonumber(relation.branch_type) == 13
                        and tonumber(evidence.branch_type) == 13
                        and tonumber(relation.attr) == 0 and tonumber(evidence.attr) == 0
                        and tonumber(relation.action_frame) == 0
                        and tonumber(evidence.action_frame) == 0
                        and tonumber(relation.param00) == 1 and tonumber(evidence.param00) == 1
                        and tonumber(relation.param01) == 0 and tonumber(evidence.param01) == 0
                        and tonumber(relation.param02) == 0 and tonumber(evidence.param02) == 0
                        and tonumber(relation.param03) == 0 and tonumber(evidence.param03) == 0
                        and tonumber(relation.param04) == 0 and tonumber(evidence.param04) == 0
                        and tonumber(relation.param05) == 0 and tonumber(evidence.param05) == 0
                        and tonumber(relation.trigger_id) == -1
                        and tonumber(evidence.trigger_id) == -1
                        and tonumber(relation.exit_branch_type) == 20
                        and tonumber(evidence.exit_branch_type) == 20
                        and tonumber(relation.exit_attr) == 0 and tonumber(evidence.exit_attr) == 0
                        and tonumber(relation.exit_action_frame) == 0
                        and tonumber(evidence.exit_action_frame) == 0
                        and tonumber(relation.exit_param00) == 0
                        and tonumber(evidence.exit_param00) == 0
                        and tonumber(relation.exit_param01) == 2
                        and tonumber(evidence.exit_param01) == 2
                        and tonumber(relation.exit_param02) == 0
                        and tonumber(evidence.exit_param02) == 0
                        and tonumber(relation.exit_param03) == 0
                        and tonumber(evidence.exit_param03) == 0
                        and tonumber(relation.exit_param04) == 0
                        and tonumber(evidence.exit_param04) == 0
                        and tonumber(relation.exit_param05) == 0
                        and tonumber(evidence.exit_param05) == 0
                        and tonumber(relation.exit_trigger_id) == -1
                        and tonumber(evidence.exit_trigger_id) == -1
                        and type(auxiliary_branches) == "table" and #auxiliary_branches == 2
                        and type(evidence_auxiliary_branches) == "table"
                        and #evidence_auxiliary_branches == 2
                        and exact_auxiliary_branch(auxiliary_branches[1], 5, 0)
                        and exact_auxiliary_branch(auxiliary_branches[2], 54, 160)
                        and exact_auxiliary_branch(evidence_auxiliary_branches[1], 5, 0)
                        and exact_auxiliary_branch(evidence_auxiliary_branches[2], 54, 160)
                        and relation.reason == AC_TYPE13_AIR_LANDING_EXECUTION_PHASE_REASON
                    local seen_sources = {}
                    if same then
                        for index, source_id in ipairs(source_action_ids) do
                            local numeric_id = tonumber(source_id)
                            if numeric_id == nil or numeric_id == step_id
                                or numeric_id == exit_target_action_id
                                or tonumber(evidence_source_ids[index]) ~= numeric_id
                                or (index > 1 and tonumber(source_action_ids[index - 1])
                                    >= numeric_id) then
                                same = false
                                break
                            end
                            seen_sources[numeric_id] = true
                        end
                    end
                    if same then
                        for index, source_id in ipairs(auxiliary_source_ids) do
                            local numeric_id = tonumber(source_id)
                            if numeric_id == nil or numeric_id == step_id
                                or numeric_id == exit_target_action_id
                                or seen_sources[numeric_id] == true
                                or tonumber(evidence_auxiliary_ids[index]) ~= numeric_id
                                or (index > 1 and tonumber(auxiliary_source_ids[index - 1])
                                    >= numeric_id) then
                                same = false
                                break
                            end
                        end
                    end
                elseif same and evidence.kind == "ac_type36_type13_execution_phase" then
                    local source_action_id = tonumber(relation.source_action_id)
                    local tail_action_id = tonumber(relation.tail_action_id)
                    same = entry.ownership == "internal_execution_phase"
                        and source_action_id ~= nil and source_action_id ~= step_id
                        and source_action_id == tonumber(evidence.source_action_id)
                        and tail_action_id ~= nil and tail_action_id ~= source_action_id
                        and tail_action_id ~= step_id
                        and tail_action_id == tonumber(evidence.tail_action_id)
                        and tonumber(relation.branch_type) == 36
                        and tonumber(relation.exit_branch_type) == 13
                        and tonumber(relation.attr) == 0
                        and tonumber(relation.action_frame) == 0
                        and tonumber(relation.param00) == 0
                        and tonumber(relation.param01) == 0
                        and tonumber(relation.param02) == 0
                        and tonumber(relation.param03) == 0
                        and tonumber(relation.param04) == 0
                        and tonumber(relation.param05) == 0
                        and tonumber(relation.trigger_id) == -1
                        and relation.reason == AC_TYPE36_TYPE13_EXECUTION_PHASE_REASON
                else
                    same = false
                end
                if same then declared = true; break end
            end
        end
        if declared then return nil, "suppress_transition" end
        local declarations = type(modern_map._meta) == "table"
            and modern_map._meta.hold_transition_type29_alias_suppressions or nil
        if type(evidence) == "table" and type(declarations) == "table"
            and entry.ownership == "automatic_hold_transition" and #entry.routes == 0
            and step_id ~= nil and tonumber(evidence.target_action_id) == step_id
            and tonumber(evidence.selected_source_action_id) ~= nil
            and type(evidence.incoming_source_action_ids) == "table"
            and #evidence.incoming_source_action_ids > 1
            and evidence.reason == "type29_target_is_reached_from_verified_hold_continuation" then
            for _, relation in ipairs(declarations) do
                if type(relation) == "table" and tonumber(relation.target_action_id) == step_id
                    and tonumber(relation.selected_source_action_id) == tonumber(evidence.selected_source_action_id)
                    and relation.reason == evidence.reason
                    and type(relation.incoming_source_action_ids) == "table"
                    and #relation.incoming_source_action_ids == #evidence.incoming_source_action_ids then
                    local same_sources = true
                    for index, source_id in ipairs(evidence.incoming_source_action_ids) do
                        if tonumber(relation.incoming_source_action_ids[index]) ~= tonumber(source_id) then
                            same_sources = false
                            break
                        end
                    end
                    if same_sources then declared = true; break end
                end
            end
        end
        if declared then return nil, "suppress_transition" end
        return nil, "invalid_suppress_transition"
    end
    local displays, seen = {}, {}
    local type63_strength = nil
    if entry.ownership == "type63_strength_variant" then
        type63_strength = Type63StrengthSemantics.validate_target(modern_map, step_id)
    end
    for _, route in ipairs(entry.routes) do
        local source = type(route) == "table" and tostring(route.source or "") or ""
        local route_character = type(route) == "table" and tostring(route.character or "") or ""
        local map_character = type(modern_map._meta) == "table" and tostring(modern_map._meta.character or "") or ""
        local charge_direction = type(route) == "table"
            and tostring(route.charge_context_direction or "") or ""
        local charge_manual_direction = type(route) == "table"
            and tostring(route.charge_context_manual_direction or "") or ""
        local charge_relation = type(route) == "table"
            and tostring(route.charge_context_relation or "") or ""
        local charge_source_action = type(route) == "table"
            and tonumber(route.charge_context_source_action_id) or nil
        local charge_owner_action = type(route) == "table"
            and tonumber(route.owner_action_id) or nil
        local charge_source_triggers = type(route) == "table"
            and route.charge_context_source_trigger_indices or nil
        local charge_reason_ok = type(route) == "table" and (
            charge_relation == "same_trigger_bcm"
                and charge_source_action == charge_owner_action
                and route.charge_context_reason == CHARGE_CONTEXT_REASON
            or charge_relation == "ac_full_structure_peer"
                and charge_source_action ~= nil
                and charge_source_action ~= charge_owner_action
                and route.charge_context_reason == AC_CHARGE_CONTEXT_REASON)
        local charge_context_ok = type(route) == "table"
            and (route.charge_context_evidence ~= true
                or ((route.charge_context_profile == "sprt"
                    or route.charge_context_profile == "norm")
                    and charge_direction:match("^[1246789]$") ~= nil
                    and charge_manual_direction:match("^[1246789]$") ~= nil
                    and (route.charge_context_direction_profile == "sprt"
                        or route.charge_context_direction_profile == "norm"
                        or route.charge_context_direction_profile == "supr")
                    and tonumber(route.charge_context_command_no) ~= nil
                    and tonumber(route.charge_context_command_no) >= 0
                    and tonumber(route.charge_context_command_index) ~= nil
                    and tonumber(route.charge_context_command_index) >= 0
                    and type(route.charge_context_notation) == "string"
                    and route.charge_context_notation:find(
                        "[" .. charge_manual_direction .. "]", 1, true) ~= nil
                    and type(charge_source_triggers) == "table"
                    and #charge_source_triggers > 0
                    and charge_reason_ok
                    and type(route.display) == "string"
                    and route.display:find("[" .. charge_direction .. "]", 1, true) ~= nil))
        local super_shortcut_direction = type(route) == "table"
            and tostring(route.super_shortcut_direction or "") or ""
        local super_shortcut_ok = type(route) == "table"
            and (route.super_shortcut_direction_evidence ~= true
                or (route.super_shortcut_direction_profile == "supr"
                    and super_shortcut_direction:match("^[1246789]$") ~= nil
                    and type(route.super_shortcut_direction_notation) == "string"
                    and route.super_shortcut_direction_reason
                        == SUPER_SHORTCUT_DIRECTION_REASON))
        local direct_ok = (source == "bcm_profile" or source == "bcm_common_semantic")
            and route.direct_evidence == true and route.inheritance_evidence == false
            and route.rebind_evidence ~= true and route.rebind_reason == nil
            and route.runtime_common_evidence ~= true and route.runtime_common_reason == nil
            and step_id ~= nil and tonumber(route.owner_action_id) == step_id
            and route.confidence == "direct_structural" and route_character == map_character
        local contextual_effect_ok = false
        if source == "ac_type20_delayed_effect_dual_role"
            and entry.ownership == "contextual_dual_role"
            and route.direct_evidence == true and route.inheritance_evidence == false
            and route.rebind_evidence ~= true and route.rebind_reason == nil
            and route.runtime_common_evidence ~= true and route.runtime_common_reason == nil
            and route.contextual_effect_evidence == true
            and route.contextual_effect_reason == TYPE20_DELAYED_EFFECT_REASON
            and route.projection_scope == "classic_only"
            and route.profile == "norm"
            and step_id ~= nil and tonumber(route.owner_action_id) == step_id
            and route.confidence == "direct_structural" and route_character == map_character
            and type(route.display) == "string"
            and type(route.contextual_effect_bcm_notation) == "string"
            and trim_string(route.display):gsub("^>%s*", ""):gsub("%s+", "")
                == trim_string(route.contextual_effect_bcm_notation):gsub("%s+", "")
            and valid_contextual_effect_relation(
                route.contextual_effect_relation, step_id) then
            local declarations = type(modern_map._meta) == "table"
                and modern_map._meta.type20_delayed_effect_relations or nil
            for _, relation in ipairs(type(declarations) == "table" and declarations or {}) do
                if same_contextual_effect_relation(
                    route.contextual_effect_relation, relation) then
                    contextual_effect_ok = true
                    break
                end
            end
        end
        local ac_path = type(route) == "table" and route.ac_path or nil
        local inherited_ok = source == "ac_type63_throw"
            and route.direct_evidence == false and route.inheritance_evidence == true
            and route.rebind_evidence ~= true and route.rebind_reason == nil
            and route.runtime_common_evidence ~= true and route.runtime_common_reason == nil
            and tonumber(route.ac_relation_type) == 63
            and tonumber(route.owner_action_id) ~= nil
            and tonumber(route.inherited_from_action_id) ~= nil
            and step_id ~= nil and type(ac_path) == "table" and #ac_path >= 2
            and tonumber(ac_path[#ac_path]) == step_id
            and route.confidence == "verified_inherited" and route_character == map_character
            and tostring(route.visible_button or ""):upper() == "THROW"
        local type63_strength_ok = source == "ac_type63_strength_variant"
            and type(type63_strength) == "table"
            and tostring(type63_strength.display or "") == tostring(route.display or "")
        local rebind_owner = type(route) == "table" and tonumber(route.bcm_owner_action_id) or nil
        local declared_rebind = false
        local declared_rebinds = type(modern_map._meta) == "table"
            and modern_map._meta.ac_command_entry_rebinds or nil
        if type(declared_rebinds) == "table" then
            for _, relation in ipairs(declared_rebinds) do
                if type(relation) == "table" and tonumber(relation.source_action_id) == rebind_owner
                    and tonumber(relation.target_action_id) == step_id
                    and relation.reason == "ac_type17_command_entry_rebind_from_verified_bcm_owner" then
                    declared_rebind = true
                    break
                end
            end
        end
        local rebind_ok = source == "ac_command_entry_rebind"
            and route.direct_evidence == false and route.inheritance_evidence == false
            and route.rebind_evidence == true
            and route.runtime_common_evidence ~= true and route.runtime_common_reason == nil
            and entry.ownership == "rebind" and declared_rebind
            and step_id ~= nil and rebind_owner ~= nil and rebind_owner ~= step_id
            and tonumber(route.owner_action_id) == rebind_owner
            and tonumber(route.display_action_id) == step_id
            and tonumber(route.ac_relation_type) == 17
            and type(ac_path) == "table" and #ac_path == 2
            and tonumber(ac_path[1]) == rebind_owner and tonumber(ac_path[2]) == step_id
            and route.inherited_from_action_id == nil
            and route.confidence == "verified_rebind" and route_character == map_character
            and route.rebind_reason == "ac_type17_command_entry_rebind_from_verified_bcm_owner"
            and route.inheritance_reason == nil
            and tonumber(route.ac_attr) == 0 and tonumber(route.ac_frame) == 0
            and tonumber(route.ac_param00) == 9 and tonumber(route.ac_param01) == 120
            and tonumber(route.ac_param02) == 0 and tonumber(route.ac_param03) == 0
            and tonumber(route.ac_param04) == 0 and tonumber(route.ac_param05) == 0
            and tonumber(route.ac_trigger_id) == -1
            and tonumber(route.trigger_index) ~= nil
            and (route.profile == "easy" or route.profile == "supr" or route.profile == "sprt")
            and tonumber(route.command_no) ~= nil and tonumber(route.command_index) ~= nil
            and type(route.raw_direction_inputs) == "table"
            and tonumber(route.raw_button_mask) ~= nil and tonumber(route.raw_button_condition) ~= nil
            and tonumber(route.raw_dc_exc_flags) ~= nil
            and type(route.visible_direction) == "string" and route.visible_direction ~= ""
            and type(route.visible_button) == "string" and route.visible_button ~= ""
            and type(route.button_candidates) == "table" and tonumber(route.required_button_count) ~= nil
        local expected_common = step_id ~= nil and RUNTIME_COMMON_ACTIONS[step_id] or nil
        local declared_common = false
        local declared_common_actions = type(modern_map._meta) == "table"
            and modern_map._meta.runtime_common_actions or nil
        if expected_common and type(declared_common_actions) == "table" then
            for _, common in ipairs(declared_common_actions) do
                if type(common) == "table" and tonumber(common.action_id) == step_id
                    and tostring(common.display or "") == expected_common
                    and common.reason == RUNTIME_COMMON_REASON then
                    declared_common = true
                    break
                end
            end
        end
        local runtime_common_ok = source == "runtime_common_action"
            and route.direct_evidence == false and route.inheritance_evidence == false
            and route.rebind_evidence == false and route.runtime_common_evidence == true
            and route.rebind_reason == nil and route.inheritance_reason == nil
            and route.runtime_common_reason == RUNTIME_COMMON_REASON
            and entry.ownership == "runtime_common" and declared_common
            and step_id ~= nil and tonumber(route.owner_action_id) == step_id
            and tonumber(route.display_action_id) == step_id
            and route.bcm_owner_action_id == nil
            and route.ac_relation_type == nil and type(ac_path) == "table" and #ac_path == 0
            and route.inherited_from_action_id == nil
            and route.confidence == "verified_runtime_common" and route_character == map_character
            and route.profile == "runtime_common" and tonumber(route.trigger_index) == -1
            and tonumber(route.command_no) == -1 and tonumber(route.command_index) == -1
            and type(route.raw_direction_inputs) == "table" and #route.raw_direction_inputs == 0
            and tonumber(route.raw_button_mask) == 0 and tonumber(route.raw_button_condition) == 0
            and tonumber(route.raw_dc_exc_flags) == 0
            and tostring(route.visible_direction or "") == expected_common
            and route.visible_button == nil and type(route.button_candidates) == "table"
            and #route.button_candidates == 0 and tonumber(route.required_button_count) == 0
        local declared_official = false
        local declared_official_bindings = type(modern_map._meta) == "table"
            and modern_map._meta.official_semantic_bindings or nil
        if type(declared_official_bindings) == "table" then
            for _, binding in ipairs(declared_official_bindings) do
                if type(binding) == "table" and tonumber(binding.target_action_id) == step_id
                    and tostring(binding.display or "") == tostring(route.display or "")
                    and binding.reason == OFFICIAL_SEMANTIC_REASON then
                    declared_official = true
                    break
                end
            end
        end
        local official_semantic_ok = source == "official_semantic_bcm_rebind"
            and route.direct_evidence == false and route.inheritance_evidence == false
            and route.rebind_evidence == false and route.runtime_common_evidence == false
            and route.official_semantic_evidence == true
            and route.official_semantic_reason == OFFICIAL_SEMANTIC_REASON
            and route.rebind_reason == nil and route.inheritance_reason == nil
            and route.runtime_common_reason == nil
            and declared_official and step_id ~= nil
            and tonumber(route.owner_action_id) == step_id
            and tonumber(route.display_action_id) == step_id
            and tonumber(route.bcm_owner_action_id) == step_id
            and route.ac_relation_type == nil and type(ac_path) == "table" and #ac_path == 0
            and route.inherited_from_action_id == nil
            and route.confidence == "verified_official_semantic_bcm_identity"
            and route_character == map_character and route.profile == "norm_identity"
            and tonumber(route.official_action_id_hint) ~= nil
            and tonumber(route.official_action_id_distance) ~= nil
            and tonumber(route.official_action_id_distance) >= 0
            and (route.official_action_id_hint_kind == "capcom_action_id"
                or route.official_action_id_hint_kind == "derived_current_bcm_identity")
            and ((route.official_action_id_hint_kind == "capcom_action_id"
                    and route.official_semantic_row_id == nil)
                or (route.official_action_id_hint_kind == "derived_current_bcm_identity"
                    and type(route.official_semantic_row_id) == "string"
                    and route.official_semantic_row_id ~= ""))
            and type(route.official_classic_display) == "string"
            and type(route.official_modern_display) == "string"
        local alias_source = type(route) == "table" and tonumber(route.inherited_from_action_id) or nil
        local alias_type = type(route) == "table" and tonumber(route.ac_relation_type) or nil
        local declared_alias = false
        local declared_aliases = type(modern_map._meta) == "table"
            and modern_map._meta.verified_alias_relations or nil
        if type(declared_aliases) == "table" then
            for _, relation in ipairs(declared_aliases) do
                if type(relation) == "table" and tonumber(relation.source_action_id) == alias_source
                    and tonumber(relation.target_action_id) == step_id
                    and tonumber(relation.branch_type) == alias_type
                    and relation.reason == VERIFIED_ALIAS_REASON then
                    declared_alias = true
                    break
                end
            end
        end
        local verified_alias_ok = source == "ac_verified_alias_variant"
            and route.direct_evidence == false and route.inheritance_evidence == true
            and route.rebind_evidence == false and route.runtime_common_evidence == false
            and route.official_semantic_evidence == false
            and route.community_semantic_evidence == false
            and route.rebind_reason == nil and route.runtime_common_reason == nil
            and route.official_semantic_reason == nil and route.community_semantic_reason == nil
            and route.inheritance_reason == VERIFIED_ALIAS_REASON
            and entry.ownership == "verified_alias" and declared_alias
            and step_id ~= nil and (alias_type == 29 or alias_type == 35)
            and alias_source ~= nil and tonumber(route.owner_action_id) ~= nil
            and tonumber(route.display_action_id) == step_id
            and type(ac_path) == "table" and #ac_path >= 2
            and tonumber(ac_path[#ac_path - 1]) == alias_source
            and tonumber(ac_path[#ac_path]) == step_id
            and route.confidence == "verified_inherited_alias"
            and route_character == map_character
        local inherited_source = type(route) == "table" and tonumber(route.inherited_from_action_id) or nil
        local declared_type20 = false
        local type20_declarations = type(modern_map._meta) == "table"
            and modern_map._meta.type20_directional_relations or nil
        if type(type20_declarations) == "table" then
            for _, relation in ipairs(type20_declarations) do
                if type(relation) == "table" and tonumber(relation.source_action_id) == inherited_source
                    and tonumber(relation.target_action_id) == step_id
                    and tonumber(relation.branch_type) == 20
                    and tostring(relation.direction or "") == tostring(route.visible_direction or "")
                    and tostring(relation.button or "") == tostring(route.visible_button or "")
                    and relation.reason == TYPE20_DIRECTION_REASON then
                    declared_type20 = true
                    break
                end
            end
        end
        local type20_ok = source == "ac_type20_directional_air_attack"
            and entry.ownership == "type20_directional" and declared_type20
            and route.direct_evidence == false and route.inheritance_evidence == true
            and route.rebind_evidence == false and route.runtime_common_evidence == false
            and route.official_semantic_evidence == false and route.community_semantic_evidence == false
            and route.inheritance_reason == TYPE20_DIRECTION_REASON
            and tonumber(route.ac_relation_type) == 20 and inherited_source ~= nil
            and step_id ~= nil and type(ac_path) == "table" and #ac_path >= 2
            and tonumber(ac_path[#ac_path - 1]) == inherited_source
            and tonumber(ac_path[#ac_path]) == step_id
            and tonumber(route.display_action_id) == step_id
            and route.confidence == "verified_inherited_directional_attack"
            and route_character == map_character
            and tostring(route.display or "") == "空中 " .. tostring(route.visible_direction)
                .. " + " .. tostring(route.visible_button)
        local declared_type20_hold = false
        local type20_hold_declarations = type(modern_map._meta) == "table"
            and modern_map._meta.type20_hold_relations or nil
        if type(type20_hold_declarations) == "table" then
            for _, relation in ipairs(type20_hold_declarations) do
                if type(relation) == "table" and tonumber(relation.source_action_id) == inherited_source
                    and tonumber(relation.target_action_id) == step_id
                    and tonumber(relation.branch_type) == 20
                    and tonumber(relation.param00) == 1 and tonumber(relation.param02) == 0
                    and tonumber(relation.param03) == 1
                    and tonumber(relation.source_loop_count) == 0
                    and tonumber(relation.target_loop_count) == -1
                    and tostring(relation.button or "") == tostring(route.visible_button or "")
                    and relation.reason == TYPE20_HOLD_REASON then
                    declared_type20_hold = true
                    break
                end
            end
        end
        local type20_hold_ok = source == "ac_type20_hold_continuation"
            and entry.ownership == "type20_hold_continuation" and declared_type20_hold
            and route.direct_evidence == false and route.inheritance_evidence == true
            and route.rebind_evidence == false and route.runtime_common_evidence == false
            and route.official_semantic_evidence == false and route.community_semantic_evidence == false
            and route.inheritance_reason == TYPE20_HOLD_REASON
            and tonumber(route.ac_relation_type) == 20 and inherited_source ~= nil
            and step_id ~= nil and type(ac_path) == "table" and #ac_path >= 2
            and tonumber(ac_path[#ac_path - 1]) == inherited_source
            and tonumber(ac_path[#ac_path]) == step_id
            and tonumber(route.display_action_id) == step_id
            and tonumber(route.owner_action_id) ~= nil
            and tonumber(route.bcm_owner_action_id) == tonumber(route.owner_action_id)
            and route.confidence == "verified_inherited_hold_continuation"
            and route_character == map_character
            and tostring(route.display or "") == "> " .. tostring(route.visible_button)
            and tonumber(route.ac_param00) == 1 and tonumber(route.ac_param02) == 0
            and tonumber(route.ac_param03) == 1
            and tonumber(route.source_loop_count) == 0 and tonumber(route.target_loop_count) == -1
        local declared_type20_phase = false
        local type20_phase_declarations = type(modern_map._meta) == "table"
            and modern_map._meta.type20_action_phase_relations or nil
        local phase_signature_ok = false
        if type(route.ac_phase_signatures) == "table" and #route.ac_phase_signatures == 4 then
            local signatures = {}
            for _, signature in ipairs(route.ac_phase_signatures) do
                if type(signature) == "table" then
                    signatures[string.format("%s:%s:%s:%s", tostring(signature.param00),
                        tostring(signature.param01), tostring(signature.param02),
                        tostring(signature.param03))] = true
                end
            end
            phase_signature_ok = signatures["0:8:0:1"] == true
                and signatures["0:32:0:2"] == true
                and signatures["0:8192:0:3"] == true
                and signatures["1:8192:0:3"] == true
        end
        if type(type20_phase_declarations) == "table" and phase_signature_ok then
            for _, relation in ipairs(type20_phase_declarations) do
                if type(relation) == "table" and tonumber(relation.source_action_id) == inherited_source
                    and tonumber(relation.target_action_id) == step_id
                    and tonumber(relation.branch_type) == 20
                    and relation.reason == TYPE20_PHASE_REASON
                    and type(relation.signatures) == "table" and #relation.signatures == 4 then
                    declared_type20_phase = true
                    break
                end
            end
        end
        local type20_phase_ok = source == "ac_type20_action_phase"
            and entry.ownership == "type20_action_phase" and declared_type20_phase
            and route.direct_evidence == false and route.inheritance_evidence == true
            and route.rebind_evidence == false and route.runtime_common_evidence == false
            and route.official_semantic_evidence == false and route.community_semantic_evidence == false
            and route.inheritance_reason == TYPE20_PHASE_REASON
            and tonumber(route.ac_relation_type) == 20 and inherited_source ~= nil
            and step_id ~= nil and type(ac_path) == "table" and #ac_path >= 2
            and tonumber(ac_path[#ac_path - 1]) == inherited_source
            and tonumber(ac_path[#ac_path]) == step_id
            and tonumber(route.display_action_id) == step_id
            and route.confidence == "verified_inherited_action_phase"
            and route_character == map_character and phase_signature_ok
        local six_branch_signatures = {
            ["0:5:1:16:0:3"] = true,
            ["0:5:0:16:0:3"] = true,
            ["0:5:0:256:0:2"] = true,
            ["256:0:2:256:0:2"] = true,
            ["0:5:0:64:0:1"] = true,
            ["256:0:2:64:0:1"] = true,
        }
        local six_branch_signature_ok = false
        if type(route.ac_phase_signatures) == "table"
            and #route.ac_phase_signatures == 6 then
            local signatures = {}
            for _, signature in ipairs(route.ac_phase_signatures) do
                if type(signature) == "table" then
                    local key = string.format("%s:%s:%s:%s:%s:%s",
                        tostring(signature.attr), tostring(signature.action_frame),
                        tostring(signature.param00), tostring(signature.param01),
                        tostring(signature.param02), tostring(signature.param03))
                    signatures[key] = (signatures[key] or 0) + 1
                end
            end
            six_branch_signature_ok = true
            for key in pairs(six_branch_signatures) do
                if signatures[key] ~= 1 then
                    six_branch_signature_ok = false
                    break
                end
            end
        end
        local function exact_phase_exit(value, branch_type, action_frame, param00)
            return type(value) == "table"
                and tonumber(value.target_action_id) ~= nil
                and tonumber(value.branch_type) == branch_type
                and tonumber(value.attr) == 0
                and tonumber(value.action_frame) == action_frame
                and tonumber(value.param00) == param00
                and tonumber(value.param01) == 0
                and tonumber(value.param02) == 0
                and tonumber(value.param03) == 0
                and tonumber(value.param04) == 0
                and tonumber(value.param05) == 0
                and tonumber(value.trigger_id) == -1
        end
        local declared_type20_six_branch = false
        if type(type20_phase_declarations) == "table" and six_branch_signature_ok then
            for _, relation in ipairs(type20_phase_declarations) do
                if type(relation) == "table"
                    and tonumber(relation.source_action_id) == inherited_source
                    and tonumber(relation.target_action_id) == step_id
                    and tonumber(relation.branch_type) == 20
                    and relation.reason == TYPE20_SIX_BRANCH_PHASE_REASON
                    and type(relation.signatures) == "table" and #relation.signatures == 6
                    and exact_phase_exit(relation.source_exit_signature, 0, 5, 0)
                    and exact_phase_exit(relation.exit_signature, 5, 8, 1) then
                    declared_type20_six_branch = true
                    break
                end
            end
        end
        local type20_six_branch_ok = source == "ac_type20_six_branch_action_phase"
            and entry.ownership == "type20_action_phase"
            and declared_type20_six_branch and six_branch_signature_ok
            and route.direct_evidence == false and route.inheritance_evidence == true
            and route.rebind_evidence == false and route.runtime_common_evidence == false
            and route.official_semantic_evidence == false
            and route.community_semantic_evidence == false
            and route.inheritance_reason == TYPE20_SIX_BRANCH_PHASE_REASON
            and tonumber(route.ac_relation_type) == 20 and inherited_source ~= nil
            and step_id ~= nil and type(ac_path) == "table" and #ac_path >= 2
            and tonumber(ac_path[#ac_path - 1]) == inherited_source
            and tonumber(ac_path[#ac_path]) == step_id
            and tonumber(route.display_action_id) == step_id
            and route.confidence == "verified_inherited_action_phase"
            and route_character == map_character
            and exact_phase_exit(route.ac_source_exit_signature, 0, 5, 0)
            and exact_phase_exit(route.ac_exit_signature, 5, 8, 1)
        local terminal_phase_signature_ok = false
        local required_terminal_phase_signatures = {
            ["256:0:0:112:0:1"] = true,
            ["256:0:0:32:0:2"] = true,
            ["256:0:0:256:0:3"] = true,
        }
        if type(route.ac_phase_signatures) == "table" and #route.ac_phase_signatures == 3 then
            local signatures = {}
            for _, signature in ipairs(route.ac_phase_signatures) do
                if type(signature) == "table" then
                    local key = string.format("%s:%s:%s:%s:%s:%s",
                        tostring(signature.attr), tostring(signature.action_frame),
                        tostring(signature.param00), tostring(signature.param01),
                        tostring(signature.param02), tostring(signature.param03))
                    signatures[key] = (signatures[key] or 0) + 1
                end
            end
            terminal_phase_signature_ok = true
            for key in pairs(required_terminal_phase_signatures) do
                if signatures[key] ~= 1 then
                    terminal_phase_signature_ok = false
                    break
                end
            end
        end
        local declared_type20_terminal_phase = false
        local terminal_phase_declarations = type(modern_map._meta) == "table"
            and modern_map._meta.type20_terminal_command_phase_relations or nil
        if type(terminal_phase_declarations) == "table" and terminal_phase_signature_ok then
            for _, relation in ipairs(terminal_phase_declarations) do
                local fingerprints = type(relation) == "table"
                    and relation.fingerprint_fields or nil
                if type(relation) == "table"
                    and tonumber(relation.source_action_id) == inherited_source
                    and tonumber(relation.target_action_id) == step_id
                    and tonumber(relation.branch_type) == 20
                    and type(relation.signatures) == "table" and #relation.signatures == 3
                    and type(fingerprints) == "table" and #fingerprints == 4
                    and fingerprints[1] == "Category" and fingerprints[2] == "Combo"
                    and fingerprints[3] == "Projectile" and fingerprints[4] == "State"
                    and relation.reason == TYPE20_TERMINAL_COMMAND_PHASE_REASON then
                    declared_type20_terminal_phase = true
                    break
                end
            end
        end
        local terminal_route_fingerprints = route.ac_fingerprint_fields
        local type20_terminal_phase_ok = source == "ac_type20_terminal_command_phase"
            and entry.ownership == "type20_action_phase"
            and declared_type20_terminal_phase
            and route.direct_evidence == false and route.inheritance_evidence == true
            and route.rebind_evidence == false and route.runtime_common_evidence == false
            and route.official_semantic_evidence == false
            and route.community_semantic_evidence == false
            and route.inheritance_reason == TYPE20_TERMINAL_COMMAND_PHASE_REASON
            and tonumber(route.ac_relation_type) == 20 and inherited_source ~= nil
            and step_id ~= nil and type(ac_path) == "table" and #ac_path >= 2
            and tonumber(ac_path[#ac_path - 1]) == inherited_source
            and tonumber(ac_path[#ac_path]) == step_id
            and tonumber(route.display_action_id) == step_id
            and tonumber(route.bcm_owner_action_id) == tonumber(route.owner_action_id)
            and route.confidence == "verified_inherited_action_phase"
            and route_character == map_character and terminal_phase_signature_ok
            and type(terminal_route_fingerprints) == "table"
            and #terminal_route_fingerprints == 4
            and terminal_route_fingerprints[1] == "Category"
            and terminal_route_fingerprints[2] == "Combo"
            and terminal_route_fingerprints[3] == "Projectile"
            and terminal_route_fingerprints[4] == "State"
        local same_structure_signature_ok = false
        local required_same_structure_signatures = {
            ["256:0:1:256:0:3"] = true,
            ["256:0:0:256:0:3"] = true,
            ["0:4:0:256:0:2"] = true,
            ["256:0:0:256:0:2"] = true,
            ["0:4:0:64:0:1"] = true,
            ["256:0:0:64:0:1"] = true,
        }
        if type(route.ac_phase_signatures) == "table" and #route.ac_phase_signatures == 6 then
            local signatures = {}
            for _, signature in ipairs(route.ac_phase_signatures) do
                if type(signature) == "table" then
                    local key = string.format("%s:%s:%s:%s:%s:%s",
                        tostring(signature.attr), tostring(signature.action_frame),
                        tostring(signature.param00), tostring(signature.param01),
                        tostring(signature.param02), tostring(signature.param03))
                    signatures[key] = (signatures[key] or 0) + 1
                end
            end
            same_structure_signature_ok = true
            for key in pairs(required_same_structure_signatures) do
                if signatures[key] ~= 1 then
                    same_structure_signature_ok = false
                    break
                end
            end
        end
        local declared_type20_same_structure = false
        local type20_same_structure_declarations = type(modern_map._meta) == "table"
            and modern_map._meta.type20_same_structure_execution_relations or nil
        if type(type20_same_structure_declarations) == "table"
            and same_structure_signature_ok then
            for _, relation in ipairs(type20_same_structure_declarations) do
                local relation_signature_ok = false
                if type(relation) == "table" and type(relation.signatures) == "table"
                    and #relation.signatures == 6 then
                    local signatures = {}
                    for _, signature in ipairs(relation.signatures) do
                        if type(signature) == "table" then
                            local key = string.format("%s:%s:%s:%s:%s:%s",
                                tostring(signature.attr), tostring(signature.action_frame),
                                tostring(signature.param00), tostring(signature.param01),
                                tostring(signature.param02), tostring(signature.param03))
                            signatures[key] = (signatures[key] or 0) + 1
                        end
                    end
                    relation_signature_ok = true
                    for key in pairs(required_same_structure_signatures) do
                        if signatures[key] ~= 1 then
                            relation_signature_ok = false
                            break
                        end
                    end
                end
                local fingerprints = type(relation) == "table" and relation.fingerprint_fields or nil
                if relation_signature_ok
                    and tonumber(relation.source_action_id) == inherited_source
                    and tonumber(relation.target_action_id) == step_id
                    and tonumber(relation.branch_type) == 20
                    and type(fingerprints) == "table" and #fingerprints == 4
                    and fingerprints[1] == "Category" and fingerprints[2] == "Combo"
                    and fingerprints[3] == "Projectile" and fingerprints[4] == "State"
                    and relation.reason == TYPE20_SAME_STRUCTURE_PHASE_REASON then
                    declared_type20_same_structure = true
                    break
                end
            end
        end
        local route_fingerprints = route.ac_fingerprint_fields
        local type20_same_structure_ok = source == "ac_type20_same_structure_execution_phase"
            and entry.ownership == "type20_action_phase"
            and declared_type20_same_structure
            and route.direct_evidence == false and route.inheritance_evidence == true
            and route.rebind_evidence == false and route.runtime_common_evidence == false
            and route.official_semantic_evidence == false
            and route.community_semantic_evidence == false
            and route.inheritance_reason == TYPE20_SAME_STRUCTURE_PHASE_REASON
            and tonumber(route.ac_relation_type) == 20 and inherited_source ~= nil
            and step_id ~= nil and type(ac_path) == "table" and #ac_path >= 2
            and tonumber(ac_path[#ac_path - 1]) == inherited_source
            and tonumber(ac_path[#ac_path]) == step_id
            and tonumber(route.display_action_id) == step_id
            and tonumber(route.bcm_owner_action_id) == tonumber(route.owner_action_id)
            and route.confidence == "verified_inherited_action_phase"
            and route_character == map_character and same_structure_signature_ok
            and type(route_fingerprints) == "table" and #route_fingerprints == 4
            and route_fingerprints[1] == "Category" and route_fingerprints[2] == "Combo"
            and route_fingerprints[3] == "Projectile" and route_fingerprints[4] == "State"
        local declared_type37_followup_phase = false
        local declared_type37_followup_source = nil
        local type37_followup_phase_declarations = type(modern_map._meta) == "table"
            and modern_map._meta.type37_followup_execution_phase_relations or nil
        if type(type37_followup_phase_declarations) == "table" then
            for _, relation in ipairs(type37_followup_phase_declarations) do
                if type(relation) == "table"
                    and tonumber(relation.source_action_id) == inherited_source
                    and tonumber(relation.target_action_id) == step_id
                    and tonumber(relation.branch_type) == 37
                    and tonumber(relation.attr) == 64
                    and tonumber(relation.action_frame) == 0
                    and tonumber(relation.param00) == 0
                    and tonumber(relation.param01) == 0
                    and tonumber(relation.param02) == 0
                    and tonumber(relation.param03) == 0
                    and tonumber(relation.param04) == 0
                    and tonumber(relation.param05) == 0
                    and tonumber(relation.trigger_id) == -1
                    and tonumber(relation.official_followup_source_action_id) ~= nil
                    and relation.reason == TYPE37_FOLLOWUP_PHASE_REASON then
                    declared_type37_followup_phase = true
                    declared_type37_followup_source =
                        tonumber(relation.official_followup_source_action_id)
                    break
                end
            end
        end
        local type37_followup_phase_ok =
            source == "ac_type37_followup_execution_phase"
            and entry.ownership == "type37_followup_execution_phase"
            and declared_type37_followup_phase
            and route.direct_evidence == false and route.inheritance_evidence == true
            and route.rebind_evidence == false and route.runtime_common_evidence == false
            and route.official_semantic_evidence == false
            and route.community_semantic_evidence == false
            and route.inheritance_reason == TYPE37_FOLLOWUP_PHASE_REASON
            and tonumber(route.ac_relation_type) == 37 and inherited_source ~= nil
            and step_id ~= nil and type(ac_path) == "table" and #ac_path >= 2
            and tonumber(ac_path[#ac_path - 1]) == inherited_source
            and tonumber(ac_path[#ac_path]) == step_id
            and tonumber(route.display_action_id) == step_id
            and route.confidence == "verified_inherited_followup_execution_phase"
            and route_character == map_character
            and tonumber(route.ac_attr) == 64 and tonumber(route.ac_action_frame) == 0
            and tonumber(route.ac_param00) == 0 and tonumber(route.ac_param01) == 0
            and tonumber(route.ac_param02) == 0 and tonumber(route.ac_param03) == 0
            and tonumber(route.ac_param04) == 0 and tonumber(route.ac_param05) == 0
            and tonumber(route.ac_trigger_id) == -1
            and tonumber(route.official_followup_source_action_id)
                == declared_type37_followup_source
        local state_relation_list = nil
        local state_reason = nil
        local state_confidence = nil
        local state_ownership = nil
        local state_expected_type = nil
        if source == "ac_type20_state_direction" then
            state_relation_list = type(modern_map._meta) == "table"
                and modern_map._meta.ac_state_direction_relations or nil
            state_reason = AC_STATE_DIRECTION_REASON
            state_confidence = "verified_ac_state_direction"
            state_ownership = "ac_state_direction"
            state_expected_type = 20
        elseif source == "ac_type1_state_neutral" then
            state_relation_list = type(modern_map._meta) == "table"
                and modern_map._meta.ac_state_neutral_relations or nil
            state_reason = AC_STATE_NEUTRAL_REASON
            state_confidence = "verified_ac_state_neutral"
            state_ownership = "ac_state_neutral"
            state_expected_type = 1
        elseif source == "ac_type13_neutral_continuation" then
            state_relation_list = type(modern_map._meta) == "table"
                and modern_map._meta.ac_type13_neutral_relations or nil
            state_reason = AC_TYPE13_NEUTRAL_REASON
            state_confidence = "verified_ac_type13_neutral"
            state_ownership = "ac_type13_neutral"
            state_expected_type = 13
        end
        local declared_state_choice = false
        if type(state_relation_list) == "table" then
            for _, relation in ipairs(state_relation_list) do
                if type(relation) == "table" and tonumber(relation.target_action_id) == step_id
                    and tonumber(relation.branch_type) == state_expected_type
                    and relation.reason == state_reason
                    and type(relation.source_action_ids) == "table"
                    and #relation.source_action_ids > 0 then
                    for _, source_id in ipairs(relation.source_action_ids) do
                        if tonumber(source_id) == inherited_source then
                            declared_state_choice = true
                            break
                        end
                    end
                end
                if declared_state_choice then break end
            end
        end
        local state_choice_ok = state_relation_list ~= nil and declared_state_choice
            and entry.ownership == state_ownership
            and route.direct_evidence == false and route.inheritance_evidence == true
            and route.rebind_evidence == false and route.runtime_common_evidence == false
            and route.official_semantic_evidence == false and route.community_semantic_evidence == false
            and route.inheritance_reason == state_reason
            and tonumber(route.ac_relation_type) == state_expected_type
            and inherited_source ~= nil and step_id ~= nil
            and type(ac_path) == "table" and #ac_path == 2
            and tonumber(ac_path[1]) == inherited_source and tonumber(ac_path[2]) == step_id
            and tonumber(route.display_action_id) == step_id
            and route.bcm_owner_action_id == nil
            and route.confidence == state_confidence and route_character == map_character
            and type(route.state_choice_source_action_ids) == "table"
            and #route.state_choice_source_action_ids > 0
            and ((source == "ac_type20_state_direction"
                    and tostring(route.display or ""):match("^[2468]$") ~= nil
                    and tonumber(route.state_choice_direction_mask) ~= nil)
                or ((source == "ac_type1_state_neutral"
                        or source == "ac_type13_neutral_continuation")
                    and route.display == "N"))
        local declared_target_combo = false
        local target_combo_declarations = type(modern_map._meta) == "table"
            and modern_map._meta.target_combo_repeat_relations or nil
        if type(target_combo_declarations) == "table" then
            for _, relation in ipairs(target_combo_declarations) do
                if type(relation) == "table" and tonumber(relation.parent_action_id) == inherited_source
                    and tonumber(relation.target_action_id) == step_id
                    and tonumber(relation.trigger_index) == tonumber(route.trigger_index)
                    and tostring(relation.button or "") == tostring(route.visible_button or "")
                    and relation.evidence == "bcm-turn-around"
                    and relation.reason == TARGET_COMBO_REPEAT_REASON then
                    declared_target_combo = true
                    break
                end
            end
        end
        local target_combo_ok = source == "bcm_target_combo_repeat"
            and entry.ownership == "target_combo_repeat" and declared_target_combo
            and route.direct_evidence == false and route.inheritance_evidence == true
            and route.rebind_evidence == false and route.runtime_common_evidence == false
            and route.official_semantic_evidence == false and route.community_semantic_evidence == false
            and route.inheritance_reason == TARGET_COMBO_REPEAT_REASON
            and route.ac_relation_type == nil and inherited_source ~= nil
            and step_id ~= nil and type(ac_path) == "table" and #ac_path == 2
            and tonumber(ac_path[1]) == inherited_source and tonumber(ac_path[2]) == step_id
            and tonumber(route.owner_action_id) == step_id
            and tonumber(route.bcm_owner_action_id) == step_id
            and tonumber(route.display_action_id) == step_id
            and route.confidence == "verified_bcm_target_combo_repeat"
            and route_character == map_character
            and tostring(route.display or "") == "> " .. tostring(route.visible_button)
        local declared_structural_twin = false
        local structural_twin_declarations = type(modern_map._meta) == "table"
            and modern_map._meta.structural_twin_relations or nil
        if type(structural_twin_declarations) == "table" then
            for _, relation in ipairs(structural_twin_declarations) do
                if type(relation) == "table" and tonumber(relation.source_action_id) == inherited_source
                    and tonumber(relation.target_action_id) == step_id
                    and tonumber(relation.source_trigger_index) == tonumber(route.trigger_index)
                    and relation.ignored_condition_delta == "use_super:true->false"
                    and relation.reason == STRUCTURAL_TWIN_REASON then
                    declared_structural_twin = true
                    break
                end
            end
        end
        local structural_twin_ok = source == "ac_bcm_structural_twin"
            and entry.ownership == "structural_twin" and declared_structural_twin
            and route.direct_evidence == false and route.inheritance_evidence == true
            and route.rebind_evidence == false and route.runtime_common_evidence == false
            and route.official_semantic_evidence == false and route.community_semantic_evidence == false
            and route.inheritance_reason == STRUCTURAL_TWIN_REASON
            and route.ac_relation_type == nil and inherited_source ~= nil
            and step_id ~= nil and type(ac_path) == "table" and #ac_path >= 2
            and tonumber(ac_path[#ac_path - 1]) == inherited_source
            and tonumber(ac_path[#ac_path]) == step_id
            and tonumber(route.display_action_id) == step_id
            and route.confidence == "verified_unique_structural_twin"
            and route_character == map_character
        local declared_assist_combo = false
        local assist_combo_declarations = type(modern_map._meta) == "table"
            and modern_map._meta.assist_combo_relations or nil
        if type(assist_combo_declarations) == "table" then
            for _, relation in ipairs(assist_combo_declarations) do
                if type(relation) == "table" and tonumber(relation.action_id) == step_id
                    and tostring(relation.display or "") == tostring(route.display or "")
                    and tostring(relation.assist_strength or "") == tostring(route.assist_strength or "")
                    and tostring(relation.input_stage or "") == tostring(route.assist_input_stage or "")
                    and relation.reason == ASSIST_COMBO_REASON then
                    declared_assist_combo = true
                    break
                end
            end
        end
        local assist_occurrences_ok = type(route.assist_recipe_occurrences) == "table"
            and #route.assist_recipe_occurrences > 0
        local assist_trigger_declared = false
        if assist_occurrences_ok then
            for _, occurrence in ipairs(route.assist_recipe_occurrences) do
                if type(occurrence) ~= "table" or tonumber(occurrence.array_index) == nil
                    or tonumber(occurrence.trigger_id) == nil
                    or tonumber(occurrence.trigger_id) < 0 then
                    assist_occurrences_ok = false
                    break
                end
                if tonumber(occurrence.trigger_id) == tonumber(route.trigger_index) then
                    assist_trigger_declared = true
                end
            end
        end
        local assist_expected_display = route.assist_input_stage == "first"
            and ("AUTO + " .. tostring(route.assist_strength or ""))
            or ("> " .. tostring(route.assist_strength or ""))
        local assist_combo_ok = source == "bcm_assist_combo_recipe"
            and declared_assist_combo and assist_occurrences_ok and assist_trigger_declared
            and route.direct_evidence == true and route.inheritance_evidence == false
            and route.rebind_evidence == false and route.runtime_common_evidence == false
            and route.official_semantic_evidence == false and route.community_semantic_evidence == false
            and route.assist_combo_evidence == true
            and route.assist_combo_reason == ASSIST_COMBO_REASON
            and route.inheritance_reason == nil and route.rebind_reason == nil
            and route.runtime_common_reason == nil and route.official_semantic_reason == nil
            and route.community_semantic_reason == nil
            and step_id ~= nil and tonumber(route.owner_action_id) == step_id
            and tonumber(route.display_action_id) == step_id
            and tonumber(route.bcm_owner_action_id) == step_id
            and route.ac_relation_type == nil and type(ac_path) == "table" and #ac_path == 0
            and route.inherited_from_action_id == nil
            and route.confidence == "direct_assist_combo_recipe"
            and route_character == map_character and route.profile == "assist_combo"
            and tonumber(route.command_no) == -1 and tonumber(route.command_index) == -1
            and type(route.raw_direction_inputs) == "table" and #route.raw_direction_inputs == 0
            and tonumber(route.raw_button_mask) == 0 and tonumber(route.raw_button_condition) == 0
            and tonumber(route.raw_dc_exc_flags) == 0 and tonumber(route.raw_ng_key_flags) == 0
            and (route.assist_strength == "弱" or route.assist_strength == "中"
                or route.assist_strength == "强")
            and (route.assist_input_stage == "first" or route.assist_input_stage == "repeat")
            and tostring(route.display or "") == assist_expected_display
        local display = type(route) == "table" and route.display or nil
        if charge_context_ok and super_shortcut_ok
            and (direct_ok or contextual_effect_ok
                or inherited_ok or rebind_ok or runtime_common_ok or official_semantic_ok
                or verified_alias_ok or type20_ok or type20_hold_ok or type20_phase_ok
                or type20_six_branch_ok
                or type20_terminal_phase_ok
                or type20_same_structure_ok
                or type37_followup_phase_ok or type63_strength_ok
                or state_choice_ok
                or target_combo_ok or structural_twin_ok
                or assist_combo_ok)
            and type(display) == "string" and display ~= "" and not seen[display] then
            seen[display] = true
            table.insert(displays, display)
        end
    end
    if #displays == 0 then return nil, "route_unverified" end
    return table.concat(displays, "/"), "strict_route"
end

local function resolve_classic_common_semantic(entry, classic, motion, status)
    if status == "suppress_transition" or type(entry) ~= "table" then return classic end
    if trim_string(classic):upper() ~= "NORMAL" then return classic end

    local has_drive_parry_route = false
    for _, route in ipairs(type(entry.routes) == "table" and entry.routes or {}) do
        if type(route) == "table" and route.source == "bcm_common_semantic"
            and trim_string(route.display):upper() == "DP" then
            has_drive_parry_route = true
            break
        end
    end
    if not has_drive_parry_route then return classic end

    for variant in tostring(motion or ""):gmatch("[^/|]+") do
        if trim_string(variant):upper() == "DP" then return "PARRY" end
    end
    return classic
end

-- 派生指令拼接时，若前置与后续的显示文本完全相同，就只保留后续一项，
-- 避免同一动作在同一行重复成“空中 任意键 > 空中 任意键”。
local function merge_followup_display(parent, child)
    local trimmed_parent = trim_string(parent)
    local trimmed_child = trim_string(child)
    if trimmed_child ~= "" and trimmed_parent == trimmed_child then
        return trimmed_child
    end
    return parent .. " > " .. child
end

-- 指令映射包含大量生成期审计与路由证据。加载时先用完整数据完成严格校验和
-- 路由解析，随后只保留运行时实际需要的 action id、显示文本与解析状态，避免
-- 多个约 490KB 的角色表长期驻留并触发周期性 GC 卡顿。
build_slim_command_display_map = function(loaded)
    local slim = { _slim = true }
    local catalog_meta = type(loaded) == "table" and loaded._meta or nil
    if type(catalog_meta) == "table"
        and type(catalog_meta.followup_relations) == "table" then
        slim._followup_relations = catalog_meta.followup_relations
    end
    if type(catalog_meta) == "table"
        and type(catalog_meta.assist_combo_chains) == "table" then
        slim._assist_combo_chains = catalog_meta.assist_combo_chains
    end
    if type(catalog_meta) == "table"
        and type(catalog_meta.type20_delayed_effect_relations) == "table" then
        slim._contextual_effect_relations = catalog_meta.type20_delayed_effect_relations
    end
    for action_id, entry in pairs(loaded) do
        if type(entry) == "table" and tostring(action_id):match("^%d+$") then
            local motion, status = get_modern_display_motion(loaded, { id = action_id })
            do
                local runtime_metadata = nil
                if entry.ownership == "ac_state_direction" then
                    runtime_metadata = {
                        ownership = entry.ownership,
                    }
                elseif entry.ownership == "type20_action_phase" then
                    local inherited_from_action_id = nil
                    local inheritance_is_consistent = true
                    for _, route in ipairs(type(entry.routes) == "table" and entry.routes or {}) do
                        if type(route) == "table"
                            and (route.source == "ac_type20_action_phase"
                                or route.source == "ac_type20_six_branch_action_phase"
                                or route.source == "ac_type20_terminal_command_phase"
                                or route.source == "ac_type20_same_structure_execution_phase")
                            and route.confidence == "verified_inherited_action_phase" then
                            local candidate = tonumber(route.inherited_from_action_id)
                            if candidate ~= nil and inherited_from_action_id ~= nil
                                and candidate ~= inherited_from_action_id then
                                inheritance_is_consistent = false
                                break
                            end
                            inherited_from_action_id = candidate or inherited_from_action_id
                        end
                    end
                    if inheritance_is_consistent and inherited_from_action_id ~= nil then
                        runtime_metadata = {
                            ownership = entry.ownership,
                            inherited_from_action_id = inherited_from_action_id,
                        }
                    end
                end
                local function read_classic(command)
                    if type(command) ~= "table" or type(command.display) ~= "string"
                        or trim_string(command.display) == "" or type(command.inputs) ~= "table"
                        or #command.inputs == 0 then return nil end
                    for _, input in ipairs(command.inputs) do
                        if type(input) ~= "string" or trim_string(input) == "" then return nil end
                    end
                    return trim_string(command.display)
                end
                local classic = read_classic(entry.classic_command)
                classic = resolve_classic_common_semantic(entry, classic, motion, status)
                if status == "suppress_transition" then
                    slim[tostring(action_id)] = {
                        classic = classic,
                        motion = nil,
                        status = status,
                        metadata = runtime_metadata,
                    }
                else
                    local relation = type(entry.relation) == "table" and entry.relation or nil
                    local strip_followup = relation and relation.type == "followup"
                    local verified_inputs = {}
                    for variant in tostring(motion or ""):gmatch("[^/|]+") do
                        local value = trim_string(variant)
                        if strip_followup then value = value:gsub("^>%s*", "") end
                        if value ~= "" then verified_inputs[value] = true end
                    end
                    local function read_command(command)
                        if type(command) ~= "table" or type(command.display) ~= "string"
                            or trim_string(command.display) == "" or type(command.inputs) ~= "table"
                            or #command.inputs == 0 then return nil end
                        for _, input in ipairs(command.inputs) do
                            if type(input) ~= "string" or not verified_inputs[trim_string(input)] then
                                return nil
                            end
                        end
                        return trim_string(command.display)
                    end
                    local simple = read_command(entry.simple_command)
                    local manual = read_command(entry.motion_command)
                    local relation_ok = relation == nil or (relation.type == "followup"
                        and tonumber(relation.source_action_id) ~= nil
                        and relation.evidence == "capcom_official_followup_context_matches_source_move")
                    if (simple or manual or classic) and relation_ok then
                        slim[tostring(action_id)] = {
                            classic = classic,
                            simple = simple,
                            motion = manual,
                            relation = relation and {
                                type = relation.type,
                                source_action_id = tonumber(relation.source_action_id)
                            } or nil,
                            status = status,
                            metadata = runtime_metadata,
                        }
                    else
                        slim[tostring(action_id)] = {
                            motion = nil,
                            status = "invalid_split_commands",
                            metadata = runtime_metadata,
                        }
                    end
                end
            end
        end
    end
    do
        local function resolve(action_id, slot, stack)
            local key = tostring(action_id or "")
            local item = slim[key]
            if type(item) ~= "table" then return nil end
            local local_motion = item[slot]
                or (slot == "simple" and item.motion or item.simple)
            if type(local_motion) ~= "string" or local_motion == "" then return nil end
            if type(item.relation) ~= "table" then return local_motion end
            if stack[key] then return nil end
            stack[key] = true
            local parent = resolve(item.relation.source_action_id, slot, stack)
            stack[key] = nil
            if not parent then return nil end
            return merge_followup_display(parent, local_motion)
        end
        -- Compute followup-merged commands first without mutating entries.
        -- Reading and clearing item fields inside one unordered pairs() walk
        -- makes the result depend on iteration order: a child processed after
        -- its parent would find the parent fields already cleared and lose its
        -- followup display (e.g. MBison 918->939). Two passes are order-free.
        local resolved_commands = {}
        for action_id, item in pairs(slim) do
            if tostring(action_id):match("^%d+$") and type(item) == "table" then
                resolved_commands[action_id] = {
                    simple = resolve(action_id, "simple", {}),
                    manual = resolve(action_id, "motion", {}),
                }
            end
        end
        for action_id, item in pairs(slim) do
            if tostring(action_id):match("^%d+$") and type(item) == "table" then
                local computed = resolved_commands[action_id]
                local simple = computed.simple
                local manual = computed.manual
                if simple or manual then
                    item.commands = {
                        simple = simple or manual,
                        motion = manual or simple
                    }
                    item.commands.all = item.commands.simple == item.commands.motion
                        and item.commands.simple
                        or (item.commands.simple .. "/" .. item.commands.motion)
                elseif item.status ~= "suppress_transition" and not item.classic then
                    item.status = "invalid_followup_relation"
                end
                item.simple = nil
                item.motion = nil
                item.relation = nil
            end
        end
    end
    return slim
end

local function is_catalog_strength_refinement(recorded_motion, catalog_motion)
    local recorded = trim_string(recorded_motion):upper():gsub("[%s+]", "")
    local catalog = trim_string(catalog_motion):upper():gsub("[%s+]", "")
    local recorded_prefix, recorded_family = recorded:match("^(.-)([PK])$")
    local catalog_prefix, _, catalog_family = catalog:match("^(.-)([LMH])([PK])$")
    return recorded_prefix ~= nil
        and recorded_prefix == catalog_prefix
        and recorded_family == catalog_family
end

local function get_classic_display_motion(command_map, step)
    if type(command_map) ~= "table" or type(step) ~= "table" or command_map._slim ~= true then
        return nil, "map_unavailable"
    end
    local resolved = command_map[tostring(step.id or "")]
    if type(resolved) ~= "table" then
        local conditioned_motion, conditioned_status =
            CommandDisplayOverrides.resolve_recorded_input_conditioned(
                command_map,
                step.id,
                step.motion,
                "classic"
            )
        if conditioned_motion then return conditioned_motion, conditioned_status end
        local universal_motion = get_recorded_universal_motion(step)
        if universal_motion then return universal_motion, "recorded_universal_command" end
        return nil, "action_id_missing"
    end
    if resolved.status == "suppress_transition" then
        local player_transition = get_player_visible_transition_motion(step)
        if player_transition then return player_transition, "player_input_transition" end
        return nil, resolved.status
    end
    local recorded_motion = trim_string(step.motion)
    local contextual_motion = recorded_motion:match("^>") ~= nil
        or recorded_motion:upper():match("^J%.") ~= nil
        or recorded_motion:upper():find("[AIR]", 1, true) ~= nil
        or recorded_motion:find("空中", 1, true) ~= nil
        or recorded_motion:match("%b()") ~= nil
    local presentation_context =
        CommandDisplayOverrides.resolve_presentation_context(
            command_map,
            step.id,
            "en-US"
        )
    local replace_recorded_context = type(presentation_context) == "table"
        and presentation_context.replace_recorded_context == true
    -- The generated table describes the action's standalone command. A saved
    -- trial can carry stricter contextual input (cancel shortcut, aerial state,
    -- timing/hold annotation). Replacing that text changes the trial semantics,
    -- so preserve it and use the generated command only for plain actions.
    if type(resolved.classic) == "string" and resolved.classic ~= "" then
        if recorded_motion ~= "" and contextual_motion
            and not replace_recorded_context
            and not is_catalog_strength_refinement(recorded_motion, resolved.classic) then
            return recorded_motion, "recorded_context"
        end
        return resolved.classic, resolved.status or "loaded"
    end
    if recorded_motion ~= "" and contextual_motion then return recorded_motion, "recorded_context" end
    return nil, resolved.status or "command_unavailable"
end

local function get_command_display(command_map, action_id, mode)
    if type(command_map) ~= "table" or command_map._slim ~= true then
        return nil, "map_unavailable"
    end
    local resolved = command_map[tostring(action_id or "")]
    if type(resolved) ~= "table" then return nil, "action_id_missing" end
    if resolved.status == "suppress_transition" then
        return nil, resolved.status, resolved.metadata
    end
    if mode == "classic" then
        return resolved.classic, resolved.status or "loaded", resolved.metadata
    end
    local commands = resolved.commands
    if type(commands) ~= "table" then
        return nil, resolved.status or "command_unavailable", resolved.metadata
    end
    if mode ~= "motion" and mode ~= "all" then mode = "simple" end
    return commands[mode] or commands.simple or commands.motion or commands.all,
        resolved.status or "loaded", resolved.metadata
end

local function unresolved_action_placeholder(step)
    if ctx and ctx.d2d_cfg and ctx.d2d_cfg.show_unresolved_action_ids == true then
        return string.format("[ID %s 未识别]", tostring(step and step.id or "?"))
    end
    return "[指令未识别]"
end

local function ensure_unresolved_action_audit()
    local state = ctx and ctx.trial_state
    if type(state) ~= "table" then return nil end
    if type(state.unresolved_action_audit) ~= "table" then
        state.unresolved_action_audit = {
            session_id = tonumber(state.unresolved_action_audit_session) or 0,
            unresolved_id_count = 0,
            unresolved_step_count = 0,
            current_character = "Unknown",
            entries = {}
        }
    end
    return state.unresolved_action_audit
end

local function clear_unresolved_action_audit()
    local state = ctx and ctx.trial_state
    command_display_runtime.seen_refs = setmetatable({}, { __mode = "k" })
    command_display_runtime.seen_keys = {}
    if type(state) ~= "table" then return end
    state.unresolved_action_audit_session = (tonumber(state.unresolved_action_audit_session) or 0) + 1
    state.unresolved_action_audit = {
        session_id = state.unresolved_action_audit_session,
        unresolved_id_count = 0,
        unresolved_step_count = 0,
        current_character = "Unknown",
        entries = {}
    }
end

local function audit_unresolved_action(character, step, context_name, control_mode, source, source_file, stable_identity)
    local audit = ensure_unresolved_action_audit()
    if not audit then return end
    if type(step) == "table" then
        if command_display_runtime.seen_refs[step] then return end
        command_display_runtime.seen_refs[step] = true
    else
        local identity = tostring(stable_identity or "")
        if command_display_runtime.seen_keys[identity] then return end
        command_display_runtime.seen_keys[identity] = true
    end

    character = type(character) == "string" and character ~= "" and character or "Unknown"
    local action_id = tonumber(step and step.id)
    local key = character .. ":" .. tostring(action_id or "Unknown")
    local entry = audit.entries[key]
    if not entry then
        entry = {
            character = character,
            action_id = action_id,
            occurrence_count = 0,
            first_seen_at = os.time(),
            context = context_name or "live",
            control_mode = control_mode or "unknown",
            source_file = source_file,
            classic_motion_debug_reference = type(step) == "table" and tostring(step.motion or "") or "",
            source = source or "unresolved"
        }
        audit.entries[key] = entry
        audit.unresolved_id_count = (audit.unresolved_id_count or 0) + 1
    end
    entry.control_mode = control_mode or entry.control_mode or "unknown"
    entry.occurrence_count = (entry.occurrence_count or 0) + 1
    audit.unresolved_step_count = (audit.unresolved_step_count or 0) + 1
    audit.current_character = character
end

local function clone_step_for_display(step, motion, is_modern)
    if not motion then return step end
    local copy = {}
    for k, v in pairs(step) do copy[k] = v end
    copy.motion = motion
    copy._ct_modern_display = is_modern == true
    return copy
end

local function get_classic_trial_modern_projection(sequence, sequence_character)
    local state = ctx and ctx.trial_state
    local config = ctx and ctx.d2d_cfg
    if not state or not config or config.allow_classic_trials_in_modern ~= true
        or state.is_recording == true or sequence ~= state.sequence or is_modern_sequence(sequence) then
        return nil
    end

    local player_idx = tonumber(state.playing_player) or 0
    local contexts = state.live_display_contexts
    local live_context = type(contexts) == "table" and contexts[player_idx] or nil
    local control_mode = live_context and (live_context.control_mode or live_context.control_type)
    if type(live_context) ~= "table" or live_context.active ~= true
        or tostring(control_mode or ""):lower() ~= "modern" then
        return nil
    end

    local character = sequence_character
    if type(character) ~= "string" or character == "" then character = live_context.character end
    if type(character) ~= "string" or character == "" then character = "Unknown" end
    local command_map, status = load_command_display_map(character)
    return {
        command_map = command_map,
        character = character,
        status = status
    }
end

local function resolve_modern_display_context(sequence)
    local sequence_character = get_sequence_character(sequence)
    if is_modern_sequence(sequence) then
        local modern_map, status = load_command_display_map(sequence_character)
        return true, modern_map, sequence_character or "Unknown", status, false
    end

    local trial_state = ctx and ctx.trial_state
    local recording_context = trial_state and trial_state.recording_display_context
    local control_mode = recording_context and (recording_context.control_mode or recording_context.control_type)
    if trial_state and trial_state.is_recording == true
        and type(recording_context) == "table" and recording_context.active == true
        and sequence == trial_state.sequence
        and recording_context.recording_player == trial_state.recording_player
        and recording_context.session_id == trial_state.recording_display_session_id
        and tostring(control_mode or ""):lower() == "modern" then
        local character = recording_context.character or "Unknown"
        local modern_map, status = load_command_display_map(character)
        return true, modern_map, character, status, false
    end
    local projection = get_classic_trial_modern_projection(sequence, sequence_character)
    if projection then
        return true, projection.command_map, projection.character, projection.status, true
    end
    local command_map, status = load_command_display_map(sequence_character)
    return false, command_map, sequence_character or "Unknown", status or "classic", false
end

local function resolve_live_player_command_display_context(player_idx)
    local trial_state = ctx and ctx.trial_state
    if type(trial_state) ~= "table" then return false, nil, "Unknown", "missing_state" end

    if trial_state.is_recording == true and player_idx == trial_state.recording_player then
        local recording_context = trial_state.recording_display_context
        local control_mode = recording_context and (recording_context.control_mode or recording_context.control_type)
        if type(recording_context) ~= "table" or recording_context.active ~= true
            or recording_context.recording_player ~= player_idx
            or recording_context.session_id ~= trial_state.recording_display_session_id then
            return false, nil, "Unknown", "invalid_recording_context"
        end
        local character = recording_context.character or "Unknown"
        local command_map, status = load_command_display_map(character)
        return tostring(control_mode or ""):lower() == "modern", command_map, character, status
    end

    local contexts = trial_state.live_display_contexts
    local live_context = type(contexts) == "table" and contexts[player_idx] or nil
    local control_mode = live_context and (live_context.control_mode or live_context.control_type)
    if type(live_context) ~= "table" or live_context.active ~= true
        or live_context.player_idx ~= player_idx
        or type(live_context.generation) ~= "number" then
        return false, nil, live_context and live_context.character or "Unknown", "invalid_live_context"
    end
    local character = live_context.character or "Unknown"
    local command_map, status = load_command_display_map(character)
    return tostring(control_mode or ""):lower() == "modern", command_map, character, status
end

local function select_modern_display_motion(motion)
    local mode = ctx and ctx.d2d_cfg and ctx.d2d_cfg.modern_display_mode or "simple"
    if type(motion) == "table" then
        return motion[mode] or motion.simple or motion.motion or motion.all
    end
    if type(motion) ~= "string" or motion == "" then return motion end
    if mode == "all" then return motion end

    local variants = {}
    for variant in motion:gmatch("[^/|]+") do
        local trimmed = trim_string(variant)
        if trimmed ~= "" then table.insert(variants, trimmed) end
    end
    if #variants == 0 then return motion end
    if mode == "motion" then return variants[2] or variants[1] end
    return variants[1]
end

local ACCEPTED_COMMAND_DISPLAY_ROUTE_STATUSES = {
    strict_route = true,
    runtime_verified_override = true,
    runtime_verified_conditioned_override = true,
    recorded_universal_command = true,
    player_input_transition = true,
}

local ACCEPTED_RECORDED_CONTEXT_CATALOG_STATUSES = {
    strict_route = true,
    runtime_verified_override = true,
}

local function normalize_resolved_command_motion(motion)
    if type(motion) ~= "string" then return nil end
    local normalized = trim_string(motion)
    if normalized == "" then return nil end
    local upper = normalized:upper()
    if normalized:find("未识别", 1, true) ~= nil
        or upper:find("UNKNOWN", 1, true) ~= nil
        or upper:find("ACTION_", 1, true) ~= nil then
        return nil
    end
    return normalized
end

local function get_catalog_route_status(command_map, step)
    if type(command_map) ~= "table" or type(step) ~= "table" then return nil end
    local entry = command_map[tostring(step.id or "")]
    if type(entry) ~= "table" then return nil end
    return entry.status
end

local function get_catalog_metadata(command_map, step)
    if type(command_map) ~= "table" or type(step) ~= "table" then return nil end
    local entry = command_map[tostring(step.id or "")]
    if type(entry) ~= "table" or type(entry.metadata) ~= "table" then return nil end
    return entry.metadata
end

local function normalize_recorded_motion_match(value)
    local stripped = TrainingEnvironment.strip_counter_tags(value)
    local normalized = normalize_resolved_command_motion(stripped)
    if normalized == nil then return nil end
    return normalized:upper():gsub("%s+", "")
end

local function sequence_display_language(sequence)
    local first = type(sequence) == "table" and sequence[1] or nil
    local meta = type(first) == "table" and first._xt_meta or nil
    local language = type(meta) == "table" and meta.language or nil
    return type(language) == "string" and language ~= "" and language or "zh-CN"
end

local function apply_presentation_context(command_map, action_id, motion, language)
    if type(motion) ~= "string" or motion == "" then return motion, nil end
    local context = CommandDisplayOverrides.resolve_presentation_context(
        command_map,
        action_id,
        language
    )
    if type(context) ~= "table" then return motion, nil end
    if context.strip_followup_prefix then
        motion = motion:gsub("^%s*>%s*", "")
    end
    local label = tostring(context.label)
    local separator = (label:match("%)$") or label:match("）$")) and " " or ""
    return label .. separator .. motion, context
end

-- Resolve the semantic command-display state before any localized placeholder,
-- display clone or unresolved-action audit is produced. Keeping this decision
-- in one helper makes programmatic validation agree with the trial table:
-- modern mode treats every non-suppressed missing motion as unresolved, while
-- classic mode only shows the placeholder after a command map was loaded.
local function resolve_step_command_display(command_map, step, is_modern)
    local display_step, projected_action_id =
        project_historical_action_step(command_map, step)
    local motion, route_status
    if is_modern then
        motion, route_status = get_modern_display_motion(command_map, display_step)
    else
        motion, route_status = get_classic_display_motion(command_map, display_step)
    end

    local suppressed = route_status == "suppress_transition"
    if is_modern then motion = select_modern_display_motion(motion) end
    local catalog_route_status = get_catalog_route_status(command_map, display_step)
    local metadata = get_catalog_metadata(command_map, display_step)
    local route_accepted = ACCEPTED_COMMAND_DISPLAY_ROUTE_STATUSES[route_status] == true
    if route_status == "recorded_context" then
        route_accepted = ACCEPTED_RECORDED_CONTEXT_CATALOG_STATUSES[catalog_route_status] == true
    end
    local normalized_motion = normalize_resolved_command_motion(motion)
    local resolved = not suppressed and route_accepted and normalized_motion ~= nil
    local unresolved = not suppressed and not resolved
        and (is_modern or type(command_map) == "table")
    local failure_status = nil
    if not route_accepted then
        if route_status == "recorded_context" then
            failure_status = catalog_route_status or "invalid_recorded_context_route"
        else
            failure_status = route_status or "command_unavailable"
        end
    elseif normalized_motion == nil then
        failure_status = "invalid_display_motion"
    end
    return {
        motion = resolved and normalized_motion or nil,
        raw_motion = motion,
        route_status = route_status,
        catalog_route_status = catalog_route_status,
        failure_status = failure_status,
        suppressed = suppressed,
        unresolved = unresolved,
        effective_action_id = tonumber(display_step and display_step.id),
        projected_action_id = projected_action_id,
        metadata = metadata,
    }
end

-- Resolve one step with presentation-only, predecessor-scoped phase metadata.
-- The compiler and runtime keep both real Actions; only the command display
-- hides a verified child after one of its exact, immediately preceding owners.
-- The child then becomes the next predecessor; a longer phase chain must
-- declare every adjacent edge instead of inheriting an older owner.
local function resolve_contextual_step_command_display(
    command_map,
    step,
    is_modern,
    previous_effective_owner_id
)
    local resolution = resolve_step_command_display(command_map, step, is_modern)
    local declared_internal =
        CommandDisplayOverrides.is_contextual_internal_phase(
        command_map,
        previous_effective_owner_id,
        resolution.effective_action_id
    )
    local player_transition = declared_internal
        and get_player_visible_transition_motion(step) or nil
    if player_transition ~= nil then
        local normalized_transition =
            normalize_resolved_command_motion(player_transition)
        return {
            motion = normalized_transition,
            raw_motion = player_transition,
            route_status = "player_input_transition",
            catalog_route_status = resolution.catalog_route_status,
            failure_status = normalized_transition == nil
                and "invalid_display_motion" or nil,
            suppressed = false,
            unresolved = normalized_transition == nil,
            effective_action_id = resolution.effective_action_id,
            projected_action_id = resolution.projected_action_id,
            metadata = resolution.metadata,
        }, resolution.effective_action_id
    end
    if declared_internal then
        return {
            motion = nil,
            raw_motion = nil,
            route_status = "declared_internal_phase",
            catalog_route_status = get_catalog_route_status(command_map, step),
            failure_status = nil,
            suppressed = true,
            unresolved = false,
            effective_action_id = resolution.effective_action_id,
            projected_action_id = resolution.projected_action_id,
            metadata = resolution.metadata,
        }, resolution.effective_action_id
    end

    if resolution.suppressed then
        return resolution, resolution.effective_action_id
    end

    -- Any ordinary numeric Action cuts the prior relationship, even when its
    -- display route is currently unresolved. This prevents a later child from
    -- hiding across an unrelated step while still allowing an unresolved
    -- owner to retain only its own immediately declared phases.
    local effective_owner_id = resolution.effective_action_id
    return resolution, effective_owner_id
end

local function resolve_live_log_command_displays(
    command_map,
    full_logs,
    logs_to_draw,
    is_modern
)
    local resolutions = {}
    local previous_effective_owner_id = nil
    local history = type(full_logs) == "table" and full_logs or {}
    local visible = type(logs_to_draw) == "table" and logs_to_draw or {}
    local oldest_visible = visible[#visible]
    if oldest_visible == nil then return resolutions end

    local oldest_source_index = nil
    for index, log in ipairs(history) do
        if log == oldest_visible then
            oldest_source_index = index
            break
        end
    end
    if oldest_source_index == nil then return resolutions end

    -- Live history is newest-first. Begin one real Action before the oldest
    -- visible row, then resolve oldest-to-newest through index 1. This retains
    -- the boundary predecessor and any ignore-auto rows in between without
    -- reprocessing the whole 100-entry history every frame.
    local start_index = math.min(#history, oldest_source_index + 1)
    for log_index = start_index, 1, -1 do
        local log = history[log_index]
        local resolution
        resolution, previous_effective_owner_id =
            resolve_contextual_step_command_display(
                command_map,
                log,
                is_modern,
                previous_effective_owner_id
            )
        resolutions[log] = resolution
    end
    return resolutions
end

local function effective_command_display_status(map_status, route_status)
    if map_status ~= nil and map_status ~= "loaded" then return map_status end
    return route_status or map_status or "command_unavailable"
end

-- Structured, non-rendering validation for the exact sequence/context that the
-- trial table would render. `unresolved` contains only steps that would receive
-- the localized unresolved placeholder. A missing/invalid command map is also
-- fail-closed through `ok=false`, but remains distinct in `map_status`; in
-- AC/BCM 派生关系被精简进指令表后，用于在显示层把真实续招接续到前置动作所在
-- 的行，并识别夹在其中的无 BCM 路由内部执行阶段（例如 918→921→939，921 无
-- 独立按键路由）。这些决定只影响显示与指令完整性审计，不改变 Action 检测。
local function setup_followup_child_sources(command_map)
    local child_source = {}
    local relations = type(command_map) == "table"
        and command_map._followup_relations or nil
    if type(relations) == "table" then
        for _, relation in ipairs(relations) do
            if type(relation) == "table" and tostring(relation.type or "") == "followup" then
                local child = tonumber(relation.target_action_id)
                local source = tonumber(relation.source_action_id)
                if child ~= nil and source ~= nil then
                    child_source[child] = source
                end
            end
        end
    end
    return child_source
end

local function is_same_command_phase(metadata, previous_action_id)
    if type(metadata) ~= "table"
        or tostring(metadata.ownership or "") ~= "type20_action_phase" then
        return false
    end
    local owner = tonumber(metadata.inherited_from_action_id)
    local previous = tonumber(previous_action_id)
    return owner ~= nil and previous ~= nil and owner == previous
end

local function is_internal_bridge_candidate(command_map, step)
    if type(command_map) ~= "table" or type(step) ~= "table" then return false end
    local entry = command_map[tostring(step.id or "")]
    if type(entry) ~= "table" then
        -- 目录里没有这条 Action：AC/BCM 没有给它独立按键路由。
        return true
    end
    -- 覆盖型指令只源于运行时观测，不属于生成图的 BCM 按键路由；它只有在被
    -- 派生前后夹住时才按内部执行阶段隐藏，避免伪装成一次真实输入。
    local metadata = type(entry.metadata) == "table" and entry.metadata or nil
    return type(metadata) == "table"
        and tostring(metadata.source or "") == "command_display_override"
end

local function compute_internal_bridge_suppressions(sequence, command_map)
    local suppress = {}
    if type(sequence) ~= "table" then return suppress end
    local child_source = setup_followup_child_sources(command_map)
    local n = #sequence
    local i = 1
    while i <= n do
        if not is_internal_bridge_candidate(command_map, sequence[i]) then
            i = i + 1
        else
            local run_start = i
            while i <= n and is_internal_bridge_candidate(command_map, sequence[i]) do
                i = i + 1
            end
            local run_end = i - 1
            local prev_id = run_start > 1 and tonumber(sequence[run_start - 1].id) or nil
            local next_id = run_end < n and tonumber(sequence[run_end + 1].id) or nil
            if prev_id ~= nil and next_id ~= nil and child_source[next_id] == prev_id then
                for j = run_start, run_end do suppress[j] = true end
            end
        end
    end
    return suppress
end

local function setup_contextual_effect_targets(command_map)
    local targets = {}
    local relations = type(command_map) == "table"
        and command_map._contextual_effect_relations or nil
    for _, relation in ipairs(type(relations) == "table" and relations or {}) do
        local target_id = tonumber(relation and relation.target_action_id)
        if target_id ~= nil and valid_contextual_effect_relation(relation, target_id) then
            targets[target_id] = relation
        end
    end
    return targets
end

local function compute_contextual_effect_line_breaks(sequence, command_map)
    local line_breaks = {}
    if type(sequence) ~= "table" then return line_breaks end
    local targets = setup_contextual_effect_targets(command_map)
    for index = 2, #sequence do
        local previous = sequence[index - 1]
        local current = sequence[index]
        local relation = targets[tonumber(current and current.id)]
        local same_group = type(previous) == "table" and type(current) == "table"
            and previous.group_id ~= nil and current.group_id ~= nil
            and tostring(previous.group_id) == tostring(current.group_id)
        local contact_result = current and (current.has_contact == true or current.has_hit == true)
        local previous_contact = previous
            and (previous.has_contact == true or previous.has_hit == true)
        local combo_advanced = (tonumber(current and current.expected_combo) or 0)
            > (tonumber(previous and previous.expected_combo) or 0)
        local damage_advanced = (tonumber(current and current.damage_at_step) or 0)
            > (tonumber(previous and previous.damage_at_step) or 0)
        if relation and same_group and previous_contact and contact_result
            and (combo_advanced or damage_advanced)
            and (tonumber(current.delay_from_prev) or 0)
                >= (tonumber(relation.action_frame) or math.huge) then
            line_breaks[index] = true
        end
    end
    return line_breaks
end

local function requires_separate_display_line(presentation_context, contextual_effect_break)
    return contextual_effect_break == true
        or (type(presentation_context) == "table"
            and presentation_context.separate_line == true)
end

-- classic mode the renderer preserves recorded text instead of manufacturing a
-- placeholder when the whole map is unavailable.
local function validate_sequence_command_display(sequence)
    if type(sequence) ~= "table" or type(sequence[1]) ~= "table" then
        return {
            ok = false,
            status = "invalid_sequence",
            mode = "unknown",
            character = "Unknown",
            map_available = false,
            map_status = "invalid_sequence",
            total_steps = type(sequence) == "table" and #sequence or 0,
            resolved_step_count = 0,
            preserved_step_count = 0,
            suppressed_step_count = 0,
            visible_step_count = 0,
            visible_line_count = 0,
            unresolved_count = 0,
            unresolved = {},
            recorded_motion_drift_count = 0,
            recorded_motion_drift = {},
            steps = {},
        }
    end

    local is_modern, command_map, character, map_status, classic_modern_projection =
        resolve_modern_display_context(sequence)
    local result = {
        ok = false,
        status = nil,
        mode = is_modern and "modern" or "classic",
        character = character or "Unknown",
        map_available = type(command_map) == "table",
        map_status = map_status or "map_unavailable",
        classic_modern_projection = classic_modern_projection == true,
        total_steps = #sequence,
        resolved_step_count = 0,
        preserved_step_count = 0,
        suppressed_step_count = 0,
        visible_step_count = 0,
        visible_line_count = 0,
        unresolved_count = 0,
        unresolved = {},
        recorded_motion_drift_count = 0,
        recorded_motion_drift = {},
        steps = {},
    }

    local previous_effective_owner_id = nil
    local previous_visible_group_key = nil
    local display_language = sequence_display_language(sequence)
    local suppress_map = compute_internal_bridge_suppressions(sequence, command_map)
    local contextual_effect_line_breaks =
        compute_contextual_effect_line_breaks(sequence, command_map)
    local child_source = setup_followup_child_sources(command_map)
    local last_visible_action_id = nil
    for index, step in ipairs(sequence) do
        local resolution
        if suppress_map[index] then
            resolution = {
                motion = nil,
                raw_motion = nil,
                route_status = "suppressed_internal_bridge",
                catalog_route_status = nil,
                failure_status = nil,
                suppressed = true,
                unresolved = false,
                effective_action_id = tonumber(step.id),
                projected_action_id = nil,
                metadata = nil,
            }
        else
            resolution, previous_effective_owner_id =
                resolve_contextual_step_command_display(
                    command_map,
                    step,
                    is_modern,
                    previous_effective_owner_id
                )
        end
        local classification = nil
        local display_motion = nil
        if resolution.suppressed then
            classification = "suppressed"
            result.suppressed_step_count = result.suppressed_step_count + 1
        elseif resolution.unresolved then
            classification = "unresolved"
            display_motion = "[指令未识别]"
            local route_status = resolution.failure_status
                or resolution.route_status or "command_unavailable"
            result.unresolved[#result.unresolved + 1] = {
                index = index,
                action_id = tonumber(step.id),
                action_id_raw = step.id,
                recorded_motion = type(step.motion) == "string" and step.motion or nil,
                mode = result.mode,
                status = effective_command_display_status(result.map_status, route_status),
                route_status = route_status,
                resolved_route_status = resolution.route_status,
                catalog_route_status = resolution.catalog_route_status,
            }
        elseif resolution.motion then
            classification = "resolved"
            display_motion = resolution.motion
            result.resolved_step_count = result.resolved_step_count + 1
        else
            -- This is the classic renderer's whole-map-unavailable fallback:
            -- the saved motion remains visible, but it was not catalog-resolved.
            classification = "preserved"
            display_motion = type(step.motion) == "string" and step.motion or ""
            result.preserved_step_count = result.preserved_step_count + 1
        end

        local visible = classification ~= "suppressed"
        local require_recorded_motion_match = classification == "resolved"
            and type(resolution.metadata) == "table"
            and resolution.metadata.require_recorded_motion_match == true
        local recorded_motion_matches = nil
        if require_recorded_motion_match then
            recorded_motion_matches =
                normalize_recorded_motion_match(step.motion)
                == normalize_recorded_motion_match(display_motion)
            if not recorded_motion_matches then
                result.recorded_motion_drift[#result.recorded_motion_drift + 1] = {
                    index = index,
                    action_id = tonumber(step.id),
                    recorded_motion = type(step.motion) == "string" and step.motion or "",
                    display_motion = display_motion,
                }
            end
        end
        local presentation_context = nil
        if visible and display_motion ~= nil then
            display_motion, presentation_context = apply_presentation_context(
                command_map,
                resolution.effective_action_id,
                display_motion,
                display_language
            )
        end
        local group_key = tostring(step.group_id ~= nil
            and step.group_id or ("step:" .. tostring(index)))
        if requires_separate_display_line(
            presentation_context, contextual_effect_line_breaks[index]) then
            group_key = group_key .. ":context:" .. tostring(index)
        end
        local visible_line_index = nil
        local same_command_phase = visible
            and is_same_command_phase(resolution.metadata, last_visible_action_id)
        if visible then
            result.visible_step_count = result.visible_step_count + 1
            local effective_action = resolution.effective_action_id
            local chain_followup = last_visible_action_id ~= nil
                and effective_action ~= nil
                and child_source[effective_action] == last_visible_action_id
            if previous_visible_group_key ~= group_key
                and not chain_followup and not same_command_phase then
                result.visible_line_count = result.visible_line_count + 1
            end
            previous_visible_group_key = group_key
            visible_line_index = result.visible_line_count
            last_visible_action_id = effective_action
        end
        result.steps[#result.steps + 1] = {
            index = index,
            source_action_id = tonumber(step.id),
            effective_action_id = resolution.effective_action_id,
            projected_action_id = resolution.projected_action_id,
            recorded_motion = type(step.motion) == "string" and step.motion or "",
            display_motion = display_motion,
            route_status = resolution.route_status or "command_unavailable",
            catalog_route_status = resolution.catalog_route_status,
            failure_status = resolution.failure_status,
            classification = classification,
            group_key = group_key,
            visible = visible,
            visible_line_index = visible_line_index,
            require_recorded_motion_match = require_recorded_motion_match,
            recorded_motion_matches = recorded_motion_matches,
            presentation_context = presentation_context,
            same_command_phase = same_command_phase,
        }
    end

    result.unresolved_count = #result.unresolved
    result.recorded_motion_drift_count = #result.recorded_motion_drift
    if not result.map_available then
        result.status = result.map_status
    elseif result.unresolved_count > 0 then
        result.status = "unresolved_action_commands"
    elseif result.recorded_motion_drift_count > 0 then
        result.status = "recorded_motion_drift"
    else
        result.ok = true
        result.status = "resolved"
    end
    return result
end

local function build_display_lines(sequence)
    local lines = {}
    local counter_policy = TrainingEnvironment.resolve_counter_policy(sequence, false)
    local counter_contact_step = TrainingEnvironment.find_first_contact_step(sequence)
    local sequence_character = get_sequence_character(sequence)
    local is_modern, modern_map, modern_character, modern_status, classic_modern_projection =
        resolve_modern_display_context(sequence)
    local state = ctx and ctx.trial_state
    local audit_context = state and state.is_recording == true and sequence == state.sequence
        and "recording" or "loaded"
    if audit_context == "recording" and type(state._rec_environment) == "table" then
        counter_policy = tonumber(state._rec_environment.dummy_counter_type) or counter_policy
    end
    local source_file = audit_context == "loaded" and state
        and (state.current_file_path or state.current_file) or nil

    local previous_effective_owner_id = nil
    local display_language = sequence_display_language(sequence)
    local suppress_map = compute_internal_bridge_suppressions(sequence, modern_map)
    local contextual_effect_line_breaks =
        compute_contextual_effect_line_breaks(sequence, modern_map)
    local child_source = setup_followup_child_sources(modern_map)
    local last_placed_action_id = nil
    -- AUTO连(assist combo) chain collapsing: a maximal run of consecutive steps
    -- that march through one assist-combo chain (position +1 each step) is
    -- rendered as a single held-AUTO input such as AUTO + [强>强>强]. Prefix
    -- termination is natural (only the steps actually present fold), and a
    -- step may accept several action ids so resource-dependent terminal
    -- variants stay on the same chain. Non-auto mode leaves every step as-is.
    local auto_mode = false
    do
        local mode = ctx and ctx.d2d_cfg and ctx.d2d_cfg.modern_display_mode or "simple"
        if type(mode) == "string" and mode:find("auto", 1, true) then
            auto_mode = true
        end
    end
    local auto_group = {}
    local auto_strength_for_step = {}
    if auto_mode and type(modern_map) == "table"
        and type(modern_map._assist_combo_chains) == "table" then
        local chain_position_for_action = {}
        for chain_index, chain in ipairs(modern_map._assist_combo_chains) do
            if type(chain) == "table" and type(chain.steps) == "table" then
                for _, step in ipairs(chain.steps) do
                    local position = type(step) == "table" and tonumber(step.position) or nil
                    local action_ids = type(step) == "table" and step.action_ids or nil
                    if position ~= nil and type(action_ids) == "table" then
                        for _, action in ipairs(action_ids) do
                            local aid = tonumber(action)
                            if aid ~= nil then
                                local bucket = chain_position_for_action[aid]
                                if bucket == nil then
                                    bucket = {}
                                    chain_position_for_action[aid] = bucket
                                end
                                bucket[#bucket + 1] = {
                                    chain_index = chain_index,
                                    position = position,
                                    strength = chain.strength,
                                }
                            end
                        end
                    end
                end
            end
        end
        local n = #sequence
        local i = 1
        local run_index = 0
        while i <= n do
            local step = sequence[i]
            local candidates = step and chain_position_for_action[tonumber(step.id)] or nil
            local base = nil
            if type(candidates) == "table" then
                for _, candidate in ipairs(candidates) do
                    if candidate.position == 1 then base = candidate break end
                end
            end
            if base == nil then
                i = i + 1
            else
                local run_start = i
                local run_end = i
                local current_chain = base.chain_index
                local current_position = 1
                i = i + 1
                while i <= n do
                    local next_step = sequence[i]
                    local next_group = next_step
                        and chain_position_for_action[tonumber(next_step.id)] or nil
                    local follow = nil
                    if type(next_group) == "table" then
                        for _, candidate in ipairs(next_group) do
                            if candidate.chain_index == current_chain
                                and candidate.position == current_position + 1 then
                                follow = candidate
                                break
                            end
                        end
                    end
                    if follow == nil then break end
                    run_end = i
                    current_position = follow.position
                    i = i + 1
                end
                if run_end > run_start then
                    run_index = run_index + 1
                    local key = "assist_chain:" .. tostring(run_index)
                    local strength = base.strength
                    for j = run_start, run_end do
                        auto_group[j] = key
                        auto_strength_for_step[j] = strength
                    end
                end
            end
        end
    end
    for i, raw_step in ipairs(sequence) do
        if not suppress_map[i] then
        local step = raw_step
        local include_step = true
        local modern_unavailable = false
        local resolution
        resolution, previous_effective_owner_id =
            resolve_contextual_step_command_display(
                modern_map,
                raw_step,
                is_modern,
                previous_effective_owner_id
            )
        if is_modern then
            local modern_motion = resolution.motion
            if resolution.suppressed then
                include_step = false
            elseif resolution.unresolved then
                modern_unavailable = classic_modern_projection == true
                modern_motion = unresolved_action_placeholder(raw_step)
                audit_unresolved_action(modern_character, raw_step, audit_context, "modern",
                    effective_command_display_status(modern_status,
                        resolution.failure_status or resolution.route_status),
                    source_file, audit_context .. ":" .. tostring(i))
            end
            step = clone_step_for_display(raw_step, modern_motion, true)
        else
            local classic_motion = resolution.motion
            if resolution.suppressed then
                include_step = false
            elseif resolution.unresolved then
                classic_motion = unresolved_action_placeholder(raw_step)
                audit_unresolved_action(modern_character, raw_step, audit_context, "classic",
                    effective_command_display_status(modern_status,
                        resolution.failure_status or resolution.route_status),
                    source_file, audit_context .. ":" .. tostring(i))
            end
            step = clone_step_for_display(raw_step, classic_motion, false)
        end
        step.motion = TrainingEnvironment.strip_counter_tags(step.motion)
        local presentation_context
        step.motion, presentation_context = apply_presentation_context(
            modern_map,
            resolution.effective_action_id,
            step.motion,
            display_language
        )
        if i == counter_contact_step and (counter_policy == 1 or counter_policy == 2) then
            step._ct_counter_label_type = counter_policy
        end
        if include_step then
            if auto_strength_for_step[i] ~= nil then
                step._auto_chain_strength = auto_strength_for_step[i]
            end
            local gid = auto_group[i] or step.group_id or i
            local separate_line = requires_separate_display_line(
                presentation_context, contextual_effect_line_breaks[i])
            local cur_action = resolution.effective_action_id
            local chain_followup = last_placed_action_id ~= nil
                and cur_action ~= nil
                and child_source[cur_action] == last_placed_action_id
            local same_command_phase =
                is_same_command_phase(resolution.metadata, last_placed_action_id)
            step._ct_same_command_phase = same_command_phase
            local same_group = #lines > 0 and lines[#lines].group_id == gid
            if #lines == 0
                or (not same_group and not chain_followup and not same_command_phase)
                or separate_line then
                table.insert(lines, {
                    group_id = gid,
                    first = i,
                    last = i,
                    steps = { step },
                    modern_unavailable = modern_unavailable
                })
            else
                lines[#lines].last = i
                table.insert(lines[#lines].steps, step)
                lines[#lines].modern_unavailable = lines[#lines].modern_unavailable or modern_unavailable
            end
            last_placed_action_id = resolution.effective_action_id
        end
        end
    end
    return lines, classic_modern_projection == true
end

local function strip_line_leading_followup(motion)
    return tostring(motion or ""):gsub("^%s*>%s*", "")
end

local function merge_group_log_item(steps)
    local motions = {}

    -- AUTO连 chain: the whole line is one held-AUTO input, so render it as a
    -- single bracket group instead of the internal expansion.
    local auto_strength = type(steps) == "table"
        and steps[1] and steps[1]._auto_chain_strength or nil
    if type(steps) == "table" and auto_strength ~= nil and #steps > 0 then
        local parts = {}
        for _ = 1, #steps do parts[#parts + 1] = tostring(auto_strength) end
        local first = steps[1]
        local last = steps[#steps]
        local has_modern_display = false
        local ui_result_text = nil
        local ui_result_kind = nil
        local counter_label_type = nil
        for _, s in ipairs(steps) do
            if s._ct_modern_display then has_modern_display = true end
            if s.ui_result_text then
                ui_result_text = s.ui_result_text
                ui_result_kind = s.ui_result_kind
            end
            if s._ct_counter_label_type ~= nil then
                counter_label_type = s._ct_counter_label_type
            end
        end
        return {
            motion = "AUTO + [" .. table.concat(parts, " > ") .. "]",
            is_holdable = false,
            expected_combo = last and last.expected_combo,
            actual_combo = last and last.actual_combo,
            has_hit = true,
            combo_stats = first and first.combo_stats,
            facing_left = first and first.facing_left,
            _ct_modern_display = has_modern_display,
            _ct_counter_label_type = counter_label_type,
            ui_result_text = ui_result_text,
            ui_result_kind = ui_result_kind,
        }
    end

    -- Count holdable steps
    local holdable_count = 0
    for _, s in ipairs(steps) do
        if s.is_holdable then holdable_count = holdable_count + 1 end
    end

    local first_holdable_done = false
    for step_index, s in ipairs(steps) do
        local m = s.motion or ""
        -- For follow-ups: ensure > is BEFORE [AIR]/J. (not reversed)
        m = m:gsub("^(%[AIR%])%s*(>)", "%2%1")
        m = m:gsub("^(J%.)%s*(>)", "%2%1")
        if step_index == 1 then
            -- A follow-up marker describes a relationship to a visible item
            -- on the same line. Once grouping starts a new line, the prefix is
            -- orphaned and must not render as a standalone triangle.
            m = strip_line_leading_followup(m)
        else
            m = SequenceGrouping.ensure_followup_prefix(m)
        end
        if s._ct_same_command_phase == true then
            -- The Action remains in V2/detection, but its command was already
            -- rendered by the immediately preceding BCM owner Action.
        elseif s.is_holdable then
            if holdable_count > 3 then
                -- Only display the first holdable with "(xN)", ignore the rest
                if not first_holdable_done then
                    first_holdable_done = true
                    table.insert(motions, m)
                end
                -- subsequent ones: not added
            else
                -- 3 or fewer: individual hold on each step
                local frames = s.hold_frames
                if frames and frames > 0 then
                    m = m .. " (Hold " .. frames .. ")"
                else
                    m = m .. " (Hold)"
                end
                table.insert(motions, m)
            end
        else
            table.insert(motions, m)
        end
    end

    local first = steps[1]
    local last  = steps[#steps]
    local has_same_command_phase = false
    for _, s in ipairs(steps) do
        if s._ct_same_command_phase == true then
            has_same_command_phase = true
            break
        end
    end
    local all_hit = true
    if has_same_command_phase then
        all_hit = last.has_hit == true
    else
        for _, s in ipairs(steps) do
            if not s.has_hit then all_hit = false break end
        end
    end
    local has_modern_display = false
    for _, s in ipairs(steps) do
        if s._ct_modern_display then has_modern_display = true; break end
    end
    local ui_result_text = nil
    local ui_result_kind = nil
    local counter_label_type = nil
    for _, s in ipairs(steps) do
        if s.ui_result_text then
            ui_result_text = s.ui_result_text
            ui_result_kind = s.ui_result_kind
        end
        if s._ct_counter_label_type ~= nil then
            counter_label_type = s._ct_counter_label_type
        end
    end

    return {
        motion         = table.concat(motions, " "),
        is_holdable    = false,  -- handled inline in the motion
        hold_repeat    = holdable_count > 3 and holdable_count or nil,
        expected_combo = last.expected_combo,
        actual_combo   = last.actual_combo,
        has_hit        = all_hit,
        combo_stats    = first.combo_stats,
        facing_left    = first.facing_left,
        _ct_modern_display = has_modern_display,
        _ct_counter_label_type = counter_label_type,
        ui_result_text = ui_result_text,
        ui_result_kind = ui_result_kind,
    }
end

local function display_line_log_item(steps)
    if type(steps) ~= "table" or type(steps[1]) ~= "table" then return {} end
    if #steps > 1 then return merge_group_log_item(steps) end
    local item = {}
    for key, value in pairs(steps[1]) do item[key] = value end
    item.motion = strip_line_leading_followup(item.motion)
    return item
end

-- =========================================================
-- parse_motion_to_icons
-- =========================================================
local function localize_motion_text(s)
    s = tostring(s or "")

    -- Longer phrases must be replaced before their shorter components.
    s = s:gsub("FULLY%s+DELAYED", "完全延迟")
    s = s:gsub("CANCEL%s+ACTION", "取消动作")
    s = s:gsub("DO%s+NOTHING", "不操作")
    s = s:gsub("RUN%s+STOP", "急停")
    s = s:gsub("1ST%s+HALF", "前半段")
    s = s:gsub("2ND%s+HALF", "后半段")
    s = s:gsub("FLASH%s+KICK", "脚刀")
    s = s:gsub("SHUN%s+GOKU%s+SATSU", "瞬狱杀")

    s = s:gsub("ENHANCED", "强化")
    s = s:gsub("PERFECT", "完美")
    s = s:gsub("INSTANT", "即时")
    s = s:gsub("DELAYED", "延迟")
    s = s:gsub("FEINT", "假动作")
    s = s:gsub("CANCEL", "取消")
    s = s:gsub("SLIDE", "滑步")
    s = s:gsub("UNKNOWN", "未知")

    s = s:gsub("LVL%s*(%d+)", "等级 %1")
    s = s:gsub("LEVEL%s*(%d+)", "等级 %1")
    s = s:gsub("(%d+)%s+MEDALS", "%1 枚奖牌")
    s = s:gsub("(%d+)%s+MEDAL", "%1 枚奖牌")
    return s
end

local function parse_motion_to_icons(log_entry, trial_mode, should_flip, reverse_layout)
    local d2d_cfg = ctx and ctx.d2d_cfg or {}
    local motion_tokens = {}
    local s = TrainingEnvironment.strip_counter_tags(log_entry.motion)

    -- Convert to uppercase IMMEDIATELY so that j. becomes J.
    s = s:upper()
    s = s:gsub("＋", "+")
    s = MotionPresentation.resolve_named_sequence(log_entry.id, s) or s

    -- 1. Inline normalization of aerial state (J. -> [空中], keeps each [空中] at its position)
    s = s:gsub("J%.", "[空中]")
    s = s:gsub("%[空中%]%s*", "[空中] ")

    local text_blocks = {}
    local text_idx = 0

    -- Protect unresolved placeholders before horizontal direction
    -- inversion. The temporary marker deliberately contains no digits, so an
    -- Action ID such as 1021 cannot be mirrored into a different ID.
    local function protect_unresolved_placeholder(match)
        text_idx = text_idx + 1
        text_blocks[text_idx] = match
        return "##U" .. string.char(64 + text_idx) .. "##"
    end
    s = s:gsub("(%[指令未识别%])", protect_unresolved_placeholder)
    -- Compatibility with sequences/logs produced before the audit became
    -- common to both control modes.
    s = s:gsub("(%[现代指令未识别%])", protect_unresolved_placeholder)
    s = s:gsub("(%[ID%s+%d+%s+未识别%])", protect_unresolved_placeholder)

    -- 2. Command inversion (Visual Only) for P2
    if should_flip then
        -- Protect content inside parentheses (plain text, e.g. "(4 Medals)")
        -- Markers without digits so they are not affected by the swap
        local paren_store = {}
        s = s:gsub("(%b())", function(match)
            table.insert(paren_store, match)
            return "##P" .. string.char(64 + #paren_store) .. "##"
        end)

        -- Protect full circle motions
        s = s:gsub("720", "{C2}")
        s = s:gsub("360", "{C1}")
        s = s:gsub("5252", "{D2}")

        -- Swap left and right (1<->3, 4<->6, 7<->9)
        local swap = { ["1"] = "3", ["3"] = "1", ["4"] = "6", ["6"] = "4", ["7"] = "9", ["9"] = "7" }
        s = s:gsub("%d", function(c) return swap[c] or c end)

        -- Restore circle motions
        s = s:gsub("{C2}", "720")
        s = s:gsub("{C1}", "360")
        s = s:gsub("{D2}", "5252")

        -- Restore parentheses intact
        s = s:gsub("##P(.)##", function(c)
            return paren_store[string.byte(c) - 64]
        end)
    end

    -- Convert the digit-free flip marker to the parser's existing text token.
    s = s:gsub("##U(.)##", function(marker)
        return string.format("{txt_%d}", string.byte(marker) - 64)
    end)

    s = s:gsub("%(THROW%)", "{throw}")
    s = s:gsub("THROW", "{throw}")
    s = s:gsub("LP%+LK", "{throw}")

    s = s:gsub("FORWARD DASH", "{6}{6}")
    s = s:gsub("BACK DASH", "{4}{4}")
    s = s:gsub("5252", "{2}{2}")
    -- Keep 720 away from the later generic 360 replacement. Expanding it
    -- directly to {360}{360} here would make that pass rewrite the digits
    -- inside both tokens and produce nested braces instead of icons.
    s = s:gsub("720", "{double_circle}")

    -- Auto-translate to icons (Parry and Drive Rush)
    s = s:gsub("MP%+MK %(PARRY%)", "{parry}") -- Intercept native game text
    s = s:gsub("%(PARRY_JUST_[LMH]%)", "{parry}")
    s = s:gsub("PARRY_JUST_[LMH]", "{parry}")
    s = s:gsub("%(PARRY_HIT_[LMH]%)", "{parry}")
    s = s:gsub("PARRY_HIT_[LMH]", "{parry}")
    s = s:gsub("%(PARRY%)", "{parry}")
    s = s:gsub("PARRY", "{parry}")
    s = s:gsub("%(DP%)", "{parry}")
    s = s:gsub("%f[%a]DP%f[%A]", "{parry}")

    s = s:gsub("HP%+HK", "{di}") -- Replace raw button combo
    s = s:gsub("DI", "{di}")     -- Replace DI keyword
    s = s:gsub("%(DI%)", "")     -- Remove leftover (DI)

    s = s:gsub("%(REVERSAL%)", "{rev}")
    s = s:gsub("REVERSAL", "{rev}")

    s = s:gsub("%(WHIFF%)", "(空挥)")
    s = s:gsub("WHIFF", "空挥")

    s = s:gsub("DRIVE RUSH CANCEL", "{drc}")
    s = s:gsub("%(DRC%)", "{drc}")
    s = s:gsub("DRC", "{drc}")

    s = s:gsub("RAW DR", "{dr}")
    s = s:gsub("DRIVE RUSH", "{dr}")
    s = s:gsub("%(DR%)", "{dr}")

    -- Commas separate sequential command inputs without drawing a plus sign.
    s = s:gsub(",", "{seq}")

    -- Break the parenthesis trap for follow-ups
    s = s:gsub("%(>%)", "{followup}")
    s = s:gsub("%(> (.-)%)", "{followup} %1")
    s = s:gsub(">", "{followup}")

    s = s:gsub("%(HOLD%)", "{hold}")
    s = s:gsub("%(HOLD (.-)%)", "{hold} (%1)")
    s = s:gsub("HOLD", "{hold}")

    s = s:gsub("FOLLOW%-UP", "{followup}")
    s = localize_motion_text(s)

    if log_entry._ct_modern_display then
        s = s:gsub("%+", "{plus}")
    end

    s = s:gsub("63214", "{6}{3}{2}{1}{4}")
    s = s:gsub("41236", "{4}{1}{2}{3}{6}")
    s = s:gsub("%[4%]", "{4_hold}")
    s = s:gsub("%[2%]", "{2_hold}")
    s = s:gsub("%[6%]", "{6_hold}")
    s = s:gsub("360", "{360}")
    s = s:gsub("{double_circle}", "{360}{360}")

    s = s:gsub("(%b())", function(match)
        text_idx = text_idx + 1
        text_blocks[text_idx] = match
        return string.format("{txt_%d}", text_idx)
    end)

    s = s:gsub("%f[%a]PPP%f[%A]", "{p}{p}{p}")
    s = s:gsub("%f[%a]PP%f[%A]", "{p}{p}")
    s = s:gsub("%f[%a]KKK%f[%A]", "{k}{k}{k}")
    s = s:gsub("%f[%a]KK%f[%A]", "{k}{k}")
    s = s:gsub("%f[%a]LP%f[%A]", "{lp}")
    s = s:gsub("%f[%a]MP%f[%A]", "{mp}")
    s = s:gsub("%f[%a]HP%f[%A]", "{hp}")
    s = s:gsub("%f[%a]LK%f[%A]", "{lk}")
    s = s:gsub("%f[%a]MK%f[%A]", "{mk}")
    s = s:gsub("%f[%a]HK%f[%A]", "{hk}")
    s = s:gsub("%f[%a]P%f[%A]", "{p}")
    s = s:gsub("%f[%a]K%f[%A]", "{k}")
    s = s:gsub("%f[%a]MODERN_L%f[%A]", "{modern_l}")
    s = s:gsub("%f[%a]MODERN_M%f[%A]", "{modern_m}")
    s = s:gsub("%f[%a]MODERN_H%f[%A]", "{modern_h}")
    s = s:gsub("%f[%a]MODERN_SP%f[%A]", "{modern_sp}")
    s = s:gsub("%f[%a]MODERN_AUTO%f[%A]", "{modern_auto}")
    s = s:gsub("%f[%a]AUTO%f[%A]", "{modern_auto}")
    s = s:gsub("%f[%a]SP%f[%A]", "{modern_sp}")

    local function replace_modern_text_token(src, token, img)
        local repl = "{" .. img .. "}"
        -- A modern display can contain alternate routes separated by / or |.
        -- Treat those separators as token boundaries so the final button of
        -- the first route (for example `SP + 强/236236 + 弱`) becomes an icon.
        local sep = "[%s%+%{%}/|%[%]]"
        for _ = 1, 3 do
            local before = src
            src = src:gsub("^" .. token .. "$", repl)
            src = src:gsub("^" .. token .. "(" .. sep .. ")", repl .. "%1")
            src = src:gsub("(" .. sep .. ")" .. token .. "$", "%1" .. repl)
            src = src:gsub("(" .. sep .. ")" .. token .. "(" .. sep .. ")", "%1" .. repl .. "%2")
            if src == before then break end
        end
        return src
    end

    s = replace_modern_text_token(s, "弱", "modern_l")
    s = replace_modern_text_token(s, "中", "modern_m")
    s = replace_modern_text_token(s, "強", "modern_h")
    s = replace_modern_text_token(s, "强", "modern_h")
    s = replace_modern_text_token(s, "任意键", "modern_n")
    s = s:gsub("攻撃二つ", "{modern_l}{modern_m}")
    s = s:gsub("攻击二つ", "{modern_l}{modern_m}")
    s = s:gsub("攻撃", "{modern_h}")
    s = s:gsub("攻击", "{modern_h}")

    local i = 1
    local current_text = ""

    local function flush_text()
        if current_text ~= "" then
            local trimmed = current_text:match("^%s*(.-)%s*$")
            if trimmed ~= "" then table.insert(motion_tokens, { type = "text", val = trimmed }) end
            current_text = ""
        end
    end

    while i <= #s do
        local c = s:sub(i, i)
        if c == "{" then
            flush_text()
            local end_idx = s:find("}", i)
            if end_idx then
                local tok = s:sub(i + 1, end_idx - 1)
                if tok:sub(1, 4) == "txt_" then
                    local idx = tonumber(tok:sub(5))
                    table.insert(motion_tokens, { type = "text", val = text_blocks[idx] })
                else
                    table.insert(motion_tokens, { type = "img", val = tok:lower() })
                end
                i = end_idx + 1
            else
                i = i + 1
            end
        elseif c:match("%d") then
            flush_text()
            if c ~= "0" then table.insert(motion_tokens, { type = "img", val = c }) end
            i = i + 1
        elseif c == "+" then
            flush_text()
            i = i + 1
        else
            current_text = current_text .. c
            i = i + 1
        end
    end
    flush_text()

    -- NEW: Auto-insert PLUS icon between directions and attack buttons
    local is_btn = {
        p = true, k = true, lp = true, mp = true, hp = true, lk = true, mk = true, hk = true, throw = true,
        modern_l = true, modern_m = true, modern_h = true, modern_n = true,
        modern_sp = true, modern_auto = true,
    }
    local processed_tokens = {}
    local suppress_plus = false
    for token_idx, tok in ipairs(motion_tokens) do
        if tok.type == "img" and tok.val == "seq" then
            suppress_plus = true
        else
            local prev = processed_tokens[#processed_tokens]
            local next_tok = motion_tokens[token_idx + 1]
            local skip_button_separator = tok.type == "img" and tok.val == "plus"
                and prev and prev.type == "img" and is_btn[prev.val]
                and next_tok and next_tok.type == "img" and is_btn[next_tok.val]
            if skip_button_separator then
                suppress_plus = false
            else
            if #processed_tokens > 0 then
                if not suppress_plus and tok.type == "img" and is_btn[tok.val] then
                    if prev.type == "img" and not is_btn[prev.val] and prev.val ~= "plus" and prev.val ~= "followup" and prev.val ~= "validfollowup" then
                        table.insert(processed_tokens, { type = "img", val = "plus" })
                    end
                end
            end
            table.insert(processed_tokens, tok)
            suppress_plus = false
            end
        end
    end
    motion_tokens = processed_tokens

    -- Swap validated followups -> validfollowup
    if log_entry.validated_followups and log_entry.validated_followups > 0 then
        local swapped = 0
        for _, tok in ipairs(motion_tokens) do
            if swapped >= log_entry.validated_followups then break end
            if tok.type == "img" and tok.val == "followup" then
                tok.val = "validfollowup"
                swapped = swapped + 1
            end
        end
    end

    -- 3. Hold status handling
    local hold_tokens = {}
    if log_entry.hold_repeat then
        -- Repeated hold case (>3): hold icon + "(xN)"
        table.insert(hold_tokens, { type = "img",  val = "hold" })
        table.insert(hold_tokens, { type = "text", val = "(x" .. log_entry.hold_repeat .. ")", col = 0xFFFFFFFF })
    elseif log_entry.is_holdable then
        local frames = log_entry.hold_frames or 0
        local status = log_entry.charge_status or "蓄力中"

        -- Universal Math Logic: Independent of engine's is_holding flag
        if log_entry.charge_min and log_entry.charge_max then
            if frames <= log_entry.charge_min then
                status = "即时"
            elseif frames >= log_entry.charge_max then
                status = "蓄满"
            else
                status = "部分"
            end
        elseif log_entry.charge_min then
            if frames <= log_entry.charge_min then
                status = "即时"
            else
                status = "部分"
            end
        end

        -- Preserve specific engine statuses like perfect timing
        if log_entry.charge_status == "PERFECT!" then
            status = "完美!"
        elseif log_entry.charge_status == "FAKE" then
            status = "伪连"
        elseif log_entry.charge_status == "LATE" then
            status = "过晚"
        elseif log_entry.charge_status == "Maxed" then
            status = "蓄满"
        end

        local col = 0xFFFFFFFF -- White (Instant default)
        local show_icon = false

        if status == "Instant" then
            col = 0xFFFFFFFF
            show_icon = false
        elseif status:match("Partial") then
            col = 0xFFFFA500 -- Orange
            show_icon = true
        elseif status:match("Maxed") or status == "PERFECT!" or status == "FAKE" then
            col = 0xFFFFFF00 -- Yellow
            show_icon = true
        elseif status == "LATE" then
            col = 0xFFFF0000 -- Red
            show_icon = true
        elseif status == "Lv1" then
            col = 0xFF00AAFF  -- Orange (ABGR)
            show_icon = true
        elseif status == "Lv2" then
            col = 0xFF00FFFF  -- Yellow (ABGR)
            show_icon = true
        else
            if frames > 0 then show_icon = true end
        end

        -- Always show frames, but hide the yellow icon if Instant
        local charge_str = ""
        if frames > 0 then
            charge_str = string.format("(%d)", frames)
        else
            charge_str = "(Hold)"
        end

        if show_icon then table.insert(hold_tokens, { type = "img", val = "hold" }) end
        table.insert(hold_tokens, { type = "text", val = charge_str, col = col })
    end

    -- 4. Combo counter management
    local combo_token = nil
    if d2d_cfg.show_combo_count then
        if trial_mode == "playing" then
            if log_entry.expected_combo ~= nil and log_entry.expected_combo > 0 then
                local actual = log_entry.actual_combo or 0
                local col = (actual >= log_entry.expected_combo) and 0xFF00FF00 or 0xFF888888
                combo_token = {
                    type = "text",
                    val = string.format("[连段: %d / %d]", actual, log_entry.expected_combo),
                    col = col
                }
            end
        elseif trial_mode == "recording" or trial_mode == "saved" then
            if log_entry.expected_combo ~= nil and log_entry.expected_combo > 0 then
                combo_token = { type = "text", val = string.format("[连段: %d]", log_entry.expected_combo), col = 0xFF00FF00 }
            end
        elseif trial_mode == "log" then
            if log_entry.combo_count ~= nil and log_entry.combo_count > 0 then
                combo_token = { type = "text", val = string.format("[连段: %d]", log_entry.combo_count), col = 0xFF00FF00 }
            end
        end
    end

    -- 5. ASSEMBLY (Inline: each [AIR] and (XXX) stays at its natural position)
    local final_tokens = {}
    if reverse_layout then
        if combo_token then
            table.insert(final_tokens, { type = "text", val = combo_token.val .. " ", col = combo_token.col })
        end

        for _, t in ipairs(motion_tokens) do table.insert(final_tokens, t) end

        if #hold_tokens > 0 then table.insert(final_tokens, { type = "text", val = " " }) end
        for _, t in ipairs(hold_tokens) do
            if t.type == "text" then
                table.insert(final_tokens, { type = "text", val = t.val .. " ", col = t.col })
            else
                table.insert(final_tokens, t)
            end
        end
    else
        for _, t in ipairs(motion_tokens) do table.insert(final_tokens, t) end

        if #hold_tokens > 0 then table.insert(final_tokens, { type = "text", val = " " }) end
        for _, t in ipairs(hold_tokens) do table.insert(final_tokens, t) end

        if combo_token then
            table.insert(final_tokens, { type = "text", val = " " .. combo_token.val, col = combo_token.col })
        end
    end

    -- CH/PC belongs to an actual contact, never to setup actions such as
    -- Parry, Drive Rush, movement, jump, or a recorded whiff.
    local ct = Validator.counter_type_for_display(log_entry)
    if ct == 1 then
        table.insert(final_tokens, { type = "text", val = " (打康)", col = 0xFFFFFFFF })
    elseif ct == 2 then
        table.insert(final_tokens, { type = "text", val = " (确反康)", col = 0xFFFFFFFF })
    end

    return final_tokens
end

-- =========================================================
-- get_render_logs
-- =========================================================
local function get_render_logs(p_log, max_count)
    local limit = max_count or ctx.d2d_cfg.max_history
    local draw_logs = {}
    for _, log in ipairs(p_log) do
        local is_gray = not log.intentional
        if not (ctx.d2d_cfg.ignore_auto and is_gray) then
            table.insert(draw_logs, log)
            if #draw_logs >= limit then break end
        end
    end
    return draw_logs
end

-- =========================================================
-- draw_parsed_line
-- =========================================================
local function draw_parsed_line(tokens, base_x, y, icon_w, icon_h, spacing_x, final_text_y_offset, align_right,
                                color_override)
    local special_icons = { dr = true, drc = true, parry = true, rev = true, di = true }
    local line_elements = {}
    local total_w = 0

    for _, tok in ipairs(tokens) do
        if tok.type == "img" then
            if assets.imgs[tok.val] then
                local scale = (special_icons[tok.val] and ctx.d2d_cfg.special_icon_scale or 1.0)
                local current_w = icon_w * scale
                table.insert(line_elements, { type = "img", val = tok.val, w = current_w, scale = scale })
                total_w = total_w + current_w + spacing_x
            end
        elseif tok.type == "text" then
            local text_to_draw = tok.val
            if tok.val:match("{hold}") then
                table.insert(line_elements, { type = "img", val = "hold", w = icon_w, scale = 1.0 })
                total_w = total_w + icon_w + spacing_x
                text_to_draw = tok.val:gsub("{hold}%s*", "")
            end
            local w = 0
            if assets.font then w = select(1, assets.font:measure(text_to_draw)) end
            table.insert(line_elements, { type = "text", val = text_to_draw, w = w, col = tok.col })
            total_w = total_w + w + spacing_x
        end
    end
    if total_w > 0 then total_w = total_w - spacing_x end

    local cur_x = base_x
    if align_right then cur_x = base_x - total_w end

    for _, elem in ipairs(line_elements) do
        if elem.type == "img" then
            local img = assets.imgs[elem.val]
            if img then
                local current_h = icon_h * elem.scale
                local offset_y = (current_h - icon_h) / 2
                Canvas.image(img, cur_x, y - offset_y, elem.w, current_h)
            end
            cur_x = cur_x + elem.w + spacing_x
        elseif elem.type == "text" then
            if assets.font then
                local text_color = color_override or elem.col or 0xFFFFFFFF
                Canvas.text(assets.font, elem.val, cur_x + 2, y + final_text_y_offset + 2, 0xFF000000)
                Canvas.text(assets.font, elem.val, cur_x, y + final_text_y_offset, text_color)
            end
            cur_x = cur_x + elem.w + spacing_x
        end
    end
    return total_w
end

local function measure_text(text)
    if assets.font then
        local w, h = assets.font:measure(tostring(text or ""))
        return w or 0, h or (assets.text_h or 0)
    end
    return 0, assets.text_h or 0
end

local function next_utf8_char(s, index)
    local b = s:byte(index)
    if not b then return nil, index + 1 end

    local len = 1
    if b >= 240 and b <= 244 then
        len = 4
    elseif b >= 224 and b <= 239 then
        len = 3
    elseif b >= 194 and b <= 223 then
        len = 2
    end

    if index + len - 1 > #s then len = 1 end
    return s:sub(index, index + len - 1), index + len
end

local function append_wrapped_text(lines, text, max_w)
    local source = tostring(text or "")
    for raw_line in (source .. "\n"):gmatch("(.-)\n") do
        local line = trim_string(raw_line)
        if line == "" then
            table.insert(lines, "")
        else
            local cur = ""
            local i = 1
            while i <= #line do
                local ch
                ch, i = next_utf8_char(line, i)
                local next_line = cur .. (ch or "")
                local w = measure_text(next_line)
                if cur ~= "" and max_w > 0 and w > max_w then
                    table.insert(lines, cur)
                    cur = ch or ""
                else
                    cur = next_line
                end
            end
            if cur ~= "" then table.insert(lines, cur) end
        end
    end
end

local function draw_text_with_shadow(font, text, x, y, color)
    Canvas.text(font, text, x + 2, y + 2, 0xFF000000)
    Canvas.text(font, text, x, y, color)
end

local function draw_step_note(note, x, y, final_text_y_offset)
    if not assets.font or note == "" then return end
    local text = "# " .. tostring(note)
    draw_text_with_shadow(assets.font, text, x, y + final_text_y_offset, 0xFFFFA000)
end

local function draw_trial_meta_note(sw, sh, spacing_y)
    local d2d_cfg = ctx and ctx.d2d_cfg
    if not d2d_cfg or d2d_cfg.show_trial_notes ~= true then return end
    if not assets.font then return end

    local meta = get_trial_meta()
    if not has_trial_note_content(meta) then return end

    local author_line = build_author_upload_line(meta)
    if author_line ~= "" then
        local _, author_h = measure_text(author_line)
        local author_x = sw * 0.796875
        local author_y = (sh * 0.972222) - ((author_h or 0) * 0.5)
        draw_text_with_shadow(assets.font, author_line, author_x, author_y, 0xFFE0E0E0)
    end

    local note = clean_meta_text(meta.note)
    if note == "" then return end

    local x = sw * 0.332031
    if x < 0 or x > sw then x = sw * 0.25 end
    local max_w = math.min(sw * 0.50, sw - x - (sw * 0.08))
    local lines = {}
    append_wrapped_text(lines, note, max_w)
    if #lines == 0 then return end

    local max_lines = 5
    if #lines > max_lines then
        while #lines > max_lines do table.remove(lines) end
        lines[#lines] = lines[#lines] .. "..."
    end

    local line_h = math.max((assets.text_h or 0), spacing_y * 0.60)
    local y = (sh * 0.256944) - (line_h * 0.5)
    local color = 0xFFE0E0E0
    for i, line in ipairs(lines) do
        draw_text_with_shadow(assets.font, line, x, y + (i - 1) * line_h, color)
    end
end

-- =========================================================
-- imgui_init & imgui_draw
-- =========================================================
local _img_arrow_down = nil
local _img_arrow_up = nil

local function imgui_init()
    local folder = "buttonsAndArrows/"
    for k, filename in pairs(image_files) do
        assets.imgs[k] = Canvas.Image.new(folder .. filename)
    end
    _img_arrow_down = Canvas.Image.new("ui_icons/chevron_down_ios.png")
    _img_arrow_up = Canvas.Image.new("ui_icons/chevron_up_ios.png")
    -- Cartouche bar images (with built-in arrow + gradient)
    assets.imgs["done_bar"] = Canvas.Image.new("done-bar.png")
    assets.imgs["active_bar"] = Canvas.Image.new("active-bar.png")
    assets.imgs["fail_bar"] = Canvas.Image.new("fail-bar.png")
    assets.imgs["success_bar"] = Canvas.Image.new("success-bar.png")
end

local function ensure_main_font(sh)
    local cfg = ctx and ctx.d2d_cfg
    if not cfg then return false end
    local pixel_font_h = cfg.font_size * sh
    if math.abs(assets.last_pixel_size - pixel_font_h) > 1.0 or assets.font == nil then
        assets.font = Canvas.Font.new("msyhbd.ttc", math.floor(pixel_font_h))
        assets.last_pixel_size = pixel_font_h
        if assets.font then
            local _, measured_height = assets.font:measure("Combo: 8")
            assets.text_h = (measured_height and measured_height > 0) and measured_height or pixel_font_h
        end
    end
    return assets.font ~= nil
end

local function ensure_title_font(sh)
    local cfg = ctx and ctx.d2d_cfg
    if not cfg then return false end
    local title_px = math.max(10, math.floor((cfg.trial_title_font_size or 0.030) * sh))
    if math.abs((assets.last_title_pixel_size or -1) - title_px) > 1.0 or assets.title_font == nil then
        assets.title_font = Canvas.Font.new("msyhbd.ttc", title_px)
        assets.last_title_pixel_size = title_px
    end
    return assets.title_font ~= nil
end

local function draw_bar_toggle_arrows()
    if not is_combo_trials_runtime_allowed() then return end
    local pm = sdk.get_managed_singleton("app.PauseManager")
    if pm then
        local pb = pm:get_field("_CurrentPauseTypeBit")
        if pb ~= 64 and pb ~= 2112 then return end
    end
    local geo = _G._ct_bar_geometry
    if not geo then return end

    local sw, sh = Canvas.surface_size()
    local collapsed = (_G._ct_bar_collapsed == true)
    local icon_sz = math.floor(sh * 0.022)
    local margin_x = math.floor(sw * 0.008)
    local arrow_y = sh - icon_sz - math.floor(sh * 0.012)

    local lx = margin_x
    local rx = sw - margin_x - icon_sz

    local img = collapsed and _img_arrow_up or _img_arrow_down
    if img then
        Canvas.image(img, lx, arrow_y, icon_sz, icon_sz)
        Canvas.image(img, rx, arrow_y, icon_sz, icon_sz)
    end

    -- Click detection
    if imgui.is_mouse_clicked(0) then
        local m = imgui.get_mouse()
        if m then
            local pad = 10
            if (m.x >= lx - pad and m.x <= lx + icon_sz + pad and m.y >= arrow_y - pad and m.y <= arrow_y + icon_sz + pad) or
               (m.x >= rx - pad and m.x <= rx + icon_sz + pad and m.y >= arrow_y - pad and m.y <= arrow_y + icon_sz + pad) then
                _G._ct_bar_collapsed = not _G._ct_bar_collapsed
            end
        end
    end
end

local function imgui_draw_inner()
    local runtime_allowed = is_combo_trials_runtime_allowed()
    if runtime_allowed ~= imgui_last_runtime_allowed then
        imgui_last_runtime_allowed = runtime_allowed
        local rs = _G.SF6CC_RuntimeSafety or {}
        RuntimeSafety.trace("runtime_allowed=" .. tostring(runtime_allowed)
            .. " reason=" .. tostring(rs.reason)
            .. " battle_input=" .. tostring(rs.battle_input_type)
            .. " online=" .. tostring(rs.in_online_battle)
            .. " mode=" .. tostring(_G.CurrentTrainerMode)
            .. " renderer=" .. tostring(_G.ComboTrialsD2DEnabled), "ComboTrialsImGui")
    end

    if not runtime_allowed then
        _G._ct_bar_geometry = nil
        return
    end

    local d2d_cfg = ctx and ctx.d2d_cfg
    local trial_state = ctx and ctx.trial_state
    local players = ctx and ctx.players

    local should_draw = d2d_cfg and d2d_cfg.enabled and (_G.ComboTrialsD2DEnabled == true)
    local has_ui_context = _G.TrainingScriptManagerActiveThisFrame == true
        or RuntimeSafety.is_replay_allowed()

    local content_visible = should_draw
        and has_ui_context
        and _G.TrainingBarsDrawn == true
        and _G.CurrentTrainerMode == 4
    if content_visible ~= imgui_last_content_visible then
        imgui_last_content_visible = content_visible
        RuntimeSafety.trace("content_visible=" .. tostring(content_visible)
            .. " enabled=" .. tostring(_G.ComboTrialsD2DEnabled)
            .. " bars=" .. tostring(_G.TrainingBarsDrawn)
            .. " manager=" .. tostring(_G.TrainingScriptManagerActiveThisFrame)
            .. " mode=" .. tostring(_G.CurrentTrainerMode), "ComboTrialsImGui")
    end

    -- The matchmaking confirmation/pause UI disables the renderer before
    -- FlowMap leaves training. Background DrawList data is frame-local, so an
    -- early return clears the overlay without an explicit render-target pass.
    if not content_visible then
        _G._ct_bar_geometry = nil
        return
    end

    local sw, sh = Canvas.surface_size()

    -- content_visible is the final gate for every ComboTrials ImGui command.
    if content_visible then

    ctx.cached_sw, ctx.cached_sh = sw, sh

    -- SF6 NEON MENU BACKGROUND: handled by NeonBarQueue from ComboTrials_UI on_frame only


    local pixel_font_h = d2d_cfg.font_size * sh
    if not ensure_main_font(sh) then return end

    local icon_h = d2d_cfg.icon_size * sh
    local icon_w = icon_h
    local spacing_y = d2d_cfg.spacing_y * sh
    local spacing_x = d2d_cfg.spacing_x * sh

    local base_text_y = (icon_h - (assets.text_h or pixel_font_h)) / 2
    local final_text_y_offset = base_text_y + (d2d_cfg.text_y_offset * sh)

    local function draw_player_icons(p_idx, base_x, base_y, align_right, max_count, reverse_layout,
        is_modern, modern_map, modern_character, modern_status, audit_context)
        local full_logs = players[p_idx].log or {}
        if trial_state.is_recording == true and p_idx == trial_state.recording_player
            and type(trial_state._recording_preview_logs) == "table" then
            full_logs = trial_state._recording_preview_logs
        end
        local logs_to_draw = get_render_logs(full_logs, max_count)
        local contextual_resolutions = resolve_live_log_command_displays(
            modern_map,
            full_logs,
            logs_to_draw,
            is_modern
        )
        local draw_row = 0
        for i, log in ipairs(logs_to_draw) do
            local should_flip = log.facing_left or false
            local display_log = log
            local suppress_log = false
            local resolution = contextual_resolutions[log]
                or resolve_step_command_display(modern_map, log, is_modern)
            if is_modern then
                local modern_motion = resolution.motion
                if resolution.suppressed then
                    suppress_log = true
                elseif resolution.unresolved then
                    modern_motion = unresolved_action_placeholder(log)
                    audit_unresolved_action(modern_character, log, audit_context or "live", "modern",
                        effective_command_display_status(modern_status,
                            resolution.failure_status or resolution.route_status),
                        nil, (audit_context or "live") .. ":" .. tostring(p_idx) .. ":" .. tostring(i))
                end
                if not suppress_log then display_log = clone_step_for_display(log, modern_motion, true) end
            else
                local classic_motion = resolution.motion
                if resolution.suppressed then
                    suppress_log = true
                elseif resolution.unresolved then
                    classic_motion = unresolved_action_placeholder(log)
                    audit_unresolved_action(modern_character, log, audit_context or "live", "classic",
                        effective_command_display_status(modern_status,
                            resolution.failure_status or resolution.route_status),
                        nil, (audit_context or "live") .. ":" .. tostring(p_idx) .. ":" .. tostring(i))
                end
                if not suppress_log then display_log = clone_step_for_display(log, classic_motion, false) end
            end
            if not suppress_log then
                local y = base_y + draw_row * spacing_y
                draw_row = draw_row + 1
                local tokens = parse_motion_to_icons(display_log, "log", should_flip, reverse_layout)
                draw_parsed_line(tokens, base_x, y, icon_w, icon_h, spacing_x, final_text_y_offset, align_right, nil)
            end
        end
    end

    -- RAW INPUT DRAW (InputVisualiser-style, uses d2d_cfg.raw.* settings)
    local function draw_raw_player(history, base_x, base_y, is_right_side, max_count)
        local rc = d2d_cfg.raw or {}
        local r_icon = (rc.icon_size or 0.030) * sh
        local r_spacing_y = (rc.spacing_y or 0.040) * sh
        local r_text_y = (rc.text_y_offset or 0.002) * sh
        local mirror = is_right_side and -1.0 or 1.0

        local r_font = assets.font
        local ref_w = 0
        if r_font then ref_w, _ = r_font:measure("99") end

        local slots = {
            rc.col_frame or 0.000, rc.col_dir or 0.050,
            rc.slot1 or 0.100, rc.slot2 or 0.140, rc.slot3 or 0.180,
            rc.slot4 or 0.220, rc.slot5 or 0.260, rc.slot6 or 0.300
        }

        for i, entry in ipairs(history) do
            if i > max_count then break end
            if entry.active then
                local y = base_y + (i - 1) * r_spacing_y

                if r_font then
                    local txt = tostring(entry.frames > 99 and 99 or entry.frames)
                    local w, _ = r_font:measure(txt)
                    local off_x = slots[1] * sh * mirror
                    local anchor_x = base_x + off_x
                    local fx = is_right_side and (anchor_x + (ref_w - w)) or (anchor_x - w)
                    Canvas.text(r_font, txt, fx + 2, y + r_text_y + 2, 0xFF000000)
                    Canvas.text(r_font, txt, fx, y + r_text_y, 0xFFFFFFFF)
                end

                local dir_str = raw_get_numpad(entry.dir)
                local img_dir = assets.imgs[dir_str]
                if img_dir then
                    local off_x = slots[2] * sh * mirror
                    local fx = base_x + off_x
                    if is_right_side then fx = fx - r_icon end
                    Canvas.image(img_dir, fx, y, r_icon, r_icon)
                end

                if entry.btn >= 16 then
                    local files = raw_get_buttons(entry.btn)
                    for idx, fname in ipairs(files) do
                        local img_btn = assets.imgs[fname]
                        if img_btn and slots[idx + 2] then
                            local off_x = slots[idx + 2] * sh * mirror
                            local fx = base_x + off_x
                            if is_right_side then fx = fx - r_icon end
                            Canvas.image(img_btn, fx, y, r_icon, r_icon)
                        end
                    end
                end
            end
        end
    end

    -- Who is active in the trial?
    local target_trial_p = -1
    if trial_state.is_recording then
        target_trial_p = trial_state.recording_player
    elseif trial_state.is_playing then
        target_trial_p = trial_state.playing_player
    end

    local in_trial = (trial_state.is_recording or trial_state.is_playing)

    -- Resolve per-mode config
    local live_show_p1, live_show_p2, live_max
    local live_raw_p1, live_raw_p2, live_raw_max
    local live_mirror_p1, live_mirror_p2
    local base_pos_p1, base_pos_p2
    local base_raw_pos_p1, base_raw_pos_p2

    if in_trial then
        live_show_p1 = d2d_cfg.show_p1;       live_show_p2 = d2d_cfg.show_p2
        live_raw_p1  = d2d_cfg.raw_p1 or false; live_raw_p2 = d2d_cfg.raw_p2 or false
        live_mirror_p1 = d2d_cfg.mirror_p1 or false; live_mirror_p2 = d2d_cfg.mirror_p2 or false
        base_pos_p1  = d2d_cfg.pos_p1;        base_pos_p2 = d2d_cfg.pos_p2
        base_raw_pos_p1 = d2d_cfg.raw_pos_p1 or d2d_cfg.pos_p1
        base_raw_pos_p2 = d2d_cfg.raw_pos_p2 or d2d_cfg.pos_p2
        live_max     = d2d_cfg.max_history
        live_raw_max = d2d_cfg.raw_max_history or 19
    else
        live_show_p1 = d2d_cfg.idle_show_p1;   live_show_p2 = d2d_cfg.idle_show_p2
        live_raw_p1  = d2d_cfg.idle_raw_p1 or false; live_raw_p2 = d2d_cfg.idle_raw_p2 or false
        live_mirror_p1 = d2d_cfg.idle_mirror_p1 or false; live_mirror_p2 = d2d_cfg.idle_mirror_p2 or false
        base_pos_p1  = d2d_cfg.idle_pos_p1;   base_pos_p2 = d2d_cfg.idle_pos_p2
        base_raw_pos_p1 = d2d_cfg.raw_pos_p1 or d2d_cfg.pos_p1  -- idle raw uses trial raw positions as base
        base_raw_pos_p2 = d2d_cfg.raw_pos_p2 or d2d_cfg.pos_p2
        live_max     = d2d_cfg.idle_max_history
        live_raw_max = d2d_cfg.idle_raw_max_history or 19
    end

    -- NON-RAW : base alignment (P1=left in trial, P2=always right)
    local nr_align_p1 = in_trial
    local nr_align_p2 = true

    -- Apply mirror to non-raw
    local nr_pos_p1, nr_pos_p2 = base_pos_p1, base_pos_p2
    if live_mirror_p1 then nr_pos_p1, nr_align_p1 = apply_mirror(base_pos_p1, nr_align_p1) end
    if live_mirror_p2 then nr_pos_p2, nr_align_p2 = apply_mirror(base_pos_p2, nr_align_p2) end

    -- RAW : base flip (P1=left, P2=right)
    local raw_flip_p1 = false
    local raw_flip_p2 = true
    local raw_pos_p1, raw_pos_p2 = base_raw_pos_p1, base_raw_pos_p2

    -- Apply mirror to raw
    if live_mirror_p1 then raw_pos_p1, raw_flip_p1 = apply_mirror(base_raw_pos_p1, raw_flip_p1) end
    if live_mirror_p2 then raw_pos_p2, raw_flip_p2 = apply_mirror(base_raw_pos_p2, raw_flip_p2) end

    -- Read raw inputs
    if live_show_p1 and live_raw_p1 then raw_read_inputs(0, raw_state.history_p1, live_raw_max) end
    if live_show_p2 and live_raw_p2 then raw_read_inputs(1, raw_state.history_p2, live_raw_max) end

    -- DRAW P1
    if live_show_p1 then
        if live_raw_p1 then
            draw_raw_player(raw_state.history_p1, raw_pos_p1.x * sw, raw_pos_p1.y * sh, raw_flip_p1, live_raw_max)
        else
            local is_modern, modern_map, character, status = resolve_live_player_command_display_context(0)
            local audit_context = trial_state.is_recording and trial_state.recording_player == 0
                and "recording" or "live"
            draw_player_icons(0, nr_pos_p1.x * sw, nr_pos_p1.y * sh, nr_align_p1, live_max, in_trial,
                is_modern, modern_map, character, status, audit_context)
        end
    end
    -- DRAW P2
    if live_show_p2 then
        if live_raw_p2 then
            draw_raw_player(raw_state.history_p2, raw_pos_p2.x * sw, raw_pos_p2.y * sh, raw_flip_p2, live_raw_max)
        else
            local is_modern, modern_map, character, status = resolve_live_player_command_display_context(1)
            local audit_context = trial_state.is_recording and trial_state.recording_player == 1
                and "recording" or "live"
            draw_player_icons(1, nr_pos_p2.x * sw, nr_pos_p2.y * sh, nr_align_p2, live_max, true,
                is_modern, modern_map, character, status, audit_context)
        end
    end

    local function draw_trial_title()
        if d2d_cfg.trial_title_show == false then return end
        if not trial_state.sequence or not trial_state.sequence[1] then return end

        local first = trial_state.sequence[1]
        local title = first.display_name or first.title
        if type(title) ~= "string" or title == "" then return end

        local title_px = math.max(10, math.floor((d2d_cfg.trial_title_font_size or 0.030) * sh))
        if not ensure_title_font(sh) then return end

        local pos = d2d_cfg.pos_trial_header or { x = 0.5, y = 0.05 }
        local tw, th = assets.title_font:measure(title)
        local x = (pos.x * sw) - ((tw or 0) * 0.5)
        local y = (pos.y * sh) - ((th or title_px) * 0.5)

        Canvas.text(assets.title_font, title, x + 2, y + 2, 0xFF000000)
        Canvas.text(assets.title_font, title, x, y, 0xFFFFFFFF)
    end

    draw_trial_title()

    -- TRIAL CARTOUCHE (Scrolling sequence display)
    if target_trial_p ~= -1 then
        local trial_x = (d2d_cfg.pos_trial_p1 and d2d_cfg.pos_trial_p1.x or d2d_cfg.pos_p1.x) * sw
        local trial_y = (d2d_cfg.pos_trial_p1 and d2d_cfg.pos_trial_p1.y or d2d_cfg.pos_p1.y) * sh
        local is_aligned_right = false
        local visible = d2d_cfg.trial_visible_steps
        local cartouche_w = d2d_cfg.cartouche_width * sw

        local mode = "saved"
        if trial_state.is_recording then
            mode = "recording"
        elseif trial_state.is_playing then
            mode = "playing"
        end

        local padding_y = spacing_y * 0.15
        local rect_x = is_aligned_right and (trial_x - cartouche_w + spacing_x * 2) or (trial_x - spacing_x * 2)
        local target_anim_y = nil
        local active_bg_h = spacing_y * (d2d_cfg.cartouche_height or 1.0)
        local c_off_x = (d2d_cfg.cartouche_offset_x or 0) * sw
        local c_off_y = (d2d_cfg.cartouche_offset_y or 0) * sh
        local b_off_x = (d2d_cfg.bar_img_offset_x or 0) * sw
        local b_off_y = (d2d_cfg.bar_img_offset_y or 0) * sh
        local final_rect_x = rect_x + c_off_x

        -- Recording previews come from the ActionEvent compiler. The saved
        -- sequence remains untouched until recording is finalized.
        local display_sequence = trial_state.sequence
        if mode == "recording"
            and type(trial_state._recording_preview_sequence) == "table" then
            display_sequence = trial_state._recording_preview_sequence
        end
        local display_lines, classic_modern_projection = build_display_lines(display_sequence)
        local n_lines = #display_lines
        if classic_modern_projection and assets.font then
            -- Calibrated at desktop (2800, 260), i.e. game-local (240, 260)
            -- after the 2560 px-wide primary display. Keep the calibration
            -- relative to the current trial-table anchor so layout movement
            -- moves this warning by the same amount.
            local warning_text = "经典指令转现代指令，自动播放无效"
            local _, warning_h = measure_text(warning_text)
            local trial_pos = d2d_cfg.pos_trial_p1 or d2d_cfg.pos_p1 or { x = 0.105, y = 0.212 }
            local warning_x = (2800 - 2560) + ((trial_pos.x or 0.105) - 0.105) * sw
            local warning_center_y = 260 + ((trial_pos.y or 0.212) - 0.212) * sh
            local warning_y = warning_center_y - ((warning_h or 0) * 0.5)
            draw_text_with_shadow(
                assets.font,
                warning_text,
                warning_x,
                warning_y,
                0xFFFF0000
            )
        end
        local trial_meta = get_trial_meta()
        local display_state = TrialDisplayState.resolve(
            trial_state.sequence,
            trial_state.current_step,
            trial_state.success_timer
        )
        local is_succ = mode == "playing" and display_state.is_success

        local visual_step_idx = mode == "playing"
            and display_state.active_step or (trial_state.current_step or 1)
        local hold_step = trial_state._ui_step_hold_step
        local hold_until = trial_state._ui_step_hold_until_frame
        local frame_now = trial_state._engine_frame_count or 0
        if mode == "playing" and not display_state.terminal_visual_complete
            and hold_step and hold_until and frame_now <= hold_until then
            visual_step_idx = math.max(1, math.min(hold_step, #trial_state.sequence))
        elseif hold_until and frame_now > hold_until then
            trial_state._ui_step_hold_step = nil
            trial_state._ui_step_hold_until_frame = nil
        end

        -- Find the active display_line (the one containing visual_step_idx)
        local raw_visual_dl = 1
        for dl_idx, dl in ipairs(display_lines) do
            if visual_step_idx >= dl.first and visual_step_idx <= dl.last then
                raw_visual_dl = dl_idx
                break
            end
            if visual_step_idx > dl.last then
                raw_visual_dl = dl_idx + 1
            end
        end
        if raw_visual_dl > n_lines then raw_visual_dl = n_lines end

        -- VISUAL FREEZE: Wait for button release (LILY ONLY)
        local visual_dl = raw_visual_dl
        

        -- Scroll
        local start_idx = 1
        if mode == "recording" then
            start_idx = math.max(1, n_lines - math.floor(visible / 2))
        else
            start_idx = math.max(1, visual_dl - math.floor(visible / 2))
            if start_idx + visible - 1 > n_lines then
                start_idx = math.max(1, n_lines - visible + 1)
            end
        end

        -- Animation target Y
        if mode == "playing" and n_lines > 0 then
            target_anim_y = trial_y + (visual_dl - start_idx) * spacing_y
        elseif mode == "recording" and n_lines > 0 then
            target_anim_y = trial_y + (n_lines - start_idx) * spacing_y
        end

        -- Completed step backgrounds
        if mode == "playing" then
            for dl_idx = start_idx, math.min(start_idx + visible - 1, n_lines) do
                local cur_y_pos = trial_y + (dl_idx - start_idx) * spacing_y
                if is_succ or (dl_idx < visual_dl) then
                    local sy = cur_y_pos - padding_y + c_off_y
                    if assets.imgs["done_bar"] then
                        Canvas.image(assets.imgs["done_bar"], final_rect_x + b_off_x, sy + b_off_y, cartouche_w, active_bg_h)
                    else
                        Canvas.fill_rect(final_rect_x, sy, cartouche_w, active_bg_h, d2d_cfg.colors.bg_success)
                        Canvas.fill_rect(final_rect_x, sy, cartouche_w, 1, d2d_cfg.colors.bg_success_line)
                        Canvas.fill_rect(final_rect_x, sy + active_bg_h - 1, cartouche_w, 1, d2d_cfg.colors.bg_success_line)
                    end
                end
            end
        end

        -- Animated cursor
        if target_anim_y then
            if not imgui_anim.active_y or math.abs(imgui_anim.active_y - target_anim_y) > (spacing_y * 3) then
                imgui_anim.active_y = target_anim_y
            end
            imgui_anim.active_y = imgui_anim.active_y + (target_anim_y - imgui_anim.active_y) * 0.15

            local is_fail_state = (trial_state.fail_timer and trial_state.fail_timer > 0) or trial_state.manual_reset_pending
            local bar_img = nil
            if mode == "recording" then
                bar_img = assets.imgs["success_bar"]
            elseif is_succ then
                bar_img = assets.imgs["success_bar"]
            elseif is_fail_state then
                bar_img = assets.imgs["fail_bar"]
            else
                bar_img = assets.imgs["active_bar"]
            end

            local sy = imgui_anim.active_y - padding_y + c_off_y
            if bar_img then
                Canvas.image(bar_img, final_rect_x + b_off_x, sy + b_off_y, cartouche_w, active_bg_h)
            else
                local bg_c, li_c
                if mode == "recording" then
                    bg_c = 0x90FF0000; li_c = 0xFFFF0000
                else
                    bg_c = d2d_cfg.colors.bg_active; li_c = d2d_cfg.colors.bg_active_line
                end
                Canvas.fill_rect(final_rect_x, sy, cartouche_w, active_bg_h, bg_c)
                Canvas.fill_rect(final_rect_x, sy, cartouche_w, 3, li_c)
                Canvas.fill_rect(final_rect_x, sy + active_bg_h - 3, cartouche_w, 3, li_c)
            end
        else
            imgui_anim.active_y = nil
        end

        -- Static compatibility marker only: it does not mutate trial failure
        -- state and therefore cannot affect Action ID validation.
        if classic_modern_projection then
            for dl_idx = start_idx, math.min(start_idx + visible - 1, n_lines) do
                local dl = display_lines[dl_idx]
                if dl and dl.modern_unavailable then
                    local cur_y_pos = trial_y + (dl_idx - start_idx) * spacing_y
                    local sy = cur_y_pos - padding_y + c_off_y
                    if assets.imgs["fail_bar"] then
                        Canvas.image(assets.imgs["fail_bar"], final_rect_x + b_off_x,
                            sy + b_off_y, cartouche_w, active_bg_h)
                    else
                        Canvas.fill_rect(final_rect_x, sy, cartouche_w, active_bg_h,
                            d2d_cfg.colors.bg_fail)
                        Canvas.fill_rect(final_rect_x, sy, cartouche_w, 3,
                            d2d_cfg.colors.bg_fail_line)
                        Canvas.fill_rect(final_rect_x, sy + active_bg_h - 3, cartouche_w, 3,
                            d2d_cfg.colors.bg_fail_line)
                    end
                end
            end
        end

        local result_col_w = (d2d_cfg.result_col_width or 0.027) * sw
        local result_colors = {
            ok = 0xFFFFA500,
            early = 0xFF00FFAD,
            late = 0xFF00A5FF,
            wrong = 0xFFFF0000,
            missing = 0xFFFF0000,
            drop = 0xFFFF0000,
            fail = 0xFFFF0000,
        }
        draw_trial_meta_note(sw, sh, spacing_y)

        -- Draw text and icons for each visible display line
        for dl_idx = start_idx, math.min(start_idx + visible - 1, n_lines) do
            local dl = display_lines[dl_idx]
            local log_item = display_line_log_item(dl.steps)

            -- Number of validated follow-ups in this group (to swap followup -> validfollowup)
            if mode == "playing" and #dl.steps > 1 then
                log_item.validated_followups = math.max(0, math.min(trial_state.current_step - dl.first, #dl.steps - 1))
            end
            local y = trial_y + (dl_idx - start_idx) * spacing_y

            local current_should_flip = false
            if mode == "recording" then
                current_should_flip = log_item.facing_left or false
            else
                local step_facing_left = log_item.facing_left or false
                local init_facing_left = trial_state.sequence and trial_state.sequence[1] and trial_state.sequence[1].facing_left or false
                current_should_flip = (trial_state.flip_inputs ~= step_facing_left) ~= init_facing_left
            end

            local result_x = trial_x
            local command_x = trial_x + result_col_w
            if assets.font and log_item.ui_result_text and log_item.ui_result_text ~= "" then
                local result_text = tostring(log_item.ui_result_text)
                local result_color = result_colors[log_item.ui_result_kind or ""] or 0xFFFFFFFF
                Canvas.text(assets.font, result_text, result_x + 2, y + final_text_y_offset + 2, 0xFF000000)
                Canvas.text(assets.font, result_text, result_x, y + final_text_y_offset, result_color)
            end

            local tokens = parse_motion_to_icons(log_item, mode, current_should_flip, true)
            local line_w = draw_parsed_line(tokens, command_x, y, icon_w, icon_h, spacing_x, final_text_y_offset, is_aligned_right, nil)
            if d2d_cfg.show_trial_notes == true then
                local note = get_display_line_note(trial_meta, dl.first, dl.last)
                if note ~= "" then
                    draw_step_note(note, command_x + line_w + spacing_x * 3, y, final_text_y_offset)
                end
            end

            -- Smart overlay removed — bar images (done/fail/success) handle all visual states
        end

        -- Arrow on top (bar images have arrow built-in)
        if trial_state.is_playing and imgui_anim.active_y then
            -- Bar images (recording/success/fail/active) all have arrows built-in.
            -- Only draw standalone arrow when bar images are unavailable.
            if not assets.imgs["active_bar"] and not assets.imgs["fail_bar"] and not assets.imgs["success_bar"] then
                local arrow_tex = "arrow"
                local is_fail_state = (trial_state.fail_timer and trial_state.fail_timer > 0) or trial_state.manual_reset_pending
                if trial_state.success_timer > 0 then
                    arrow_tex = "arrow_success"
                elseif is_fail_state then
                    arrow_tex = "arrow_fail"
                end

                if assets.imgs[arrow_tex] then
                    local arr_w = d2d_cfg.arrow_size * sh
                    local arr_x = is_aligned_right and (trial_x - (d2d_cfg.offset_x_arrow * sw)) or
                        (trial_x + (d2d_cfg.offset_x_arrow * sw))
                    local arr_y = imgui_anim.active_y + (spacing_y - arr_w) / 2 + (d2d_cfg.offset_y_arrow * sh)
                    Canvas.image(assets.imgs[arrow_tex], arr_x, arr_y, arr_w, arr_w)
                end
            end
        end
    end

    -- Mouse clicks use ImGui coordinates. Do not draw a software cursor here:
    -- the game/system cursor is already visible and drawing another one creates double cursors.

    end -- close "if should_draw and not is_paused and CurrentTrainerMode == 4"

    if should_draw then
        draw_bar_toggle_arrows()
    else
        _G._ct_bar_geometry = nil
    end
end

-- =========================================================
-- Public API
-- =========================================================
local function imgui_draw()
    local ok, err = pcall(imgui_draw_inner)
    if ok then
        imgui_last_error = nil
    elseif tostring(err) ~= imgui_last_error then
        imgui_last_error = tostring(err)
        RuntimeSafety.trace("draw_error=" .. imgui_last_error, "ComboTrialsImGui")
    end
end

function M.init(shared_ctx)
    ctx = shared_ctx
    reset_command_display_cache()
    clear_unresolved_action_audit()
    ctx.clear_command_display_cache = M.clear_command_display_cache
    ctx.clear_unresolved_action_audit = M.clear_unresolved_action_audit
    ctx.localize_motion_text = function(motion, action_id)
        local named_sequence = MotionPresentation.resolve_named_sequence(
            action_id,
            motion
        )
        if named_sequence ~= nil then return named_sequence end
        return localize_motion_text(tostring(motion or ""):upper())
    end
    Canvas.register(imgui_init, imgui_draw)
end

function M.clear_command_display_cache()
    reset_command_display_cache()
end

function M.preload_next_font()
    if not ctx or not ctx.d2d_cfg then return true end
    local _, sh = Canvas.surface_size()
    local main_px = ctx.d2d_cfg.font_size * sh
    if assets.font == nil or math.abs(assets.last_pixel_size - main_px) > 1.0 then
        ensure_main_font(sh)
        return false
    end

    local title_px = math.max(10, math.floor((ctx.d2d_cfg.trial_title_font_size or 0.030) * sh))
    if assets.title_font == nil
        or math.abs((assets.last_title_pixel_size or -1) - title_px) > 1.0 then
        ensure_title_font(sh)
        return false
    end
    return true
end

function M.clear_unresolved_action_audit()
    clear_unresolved_action_audit()
end

function M.get_unresolved_action_audit()
    return ensure_unresolved_action_audit()
end

function M.get_command_display(character, action_id, mode)
    local command_map, status = load_command_display_map(character)
    if not command_map then return nil, status end
    return get_command_display(command_map, action_id, mode)
end

function M.get_input_conditioned_command_display(
    character,
    action_id,
    direct_input,
    newly_pressed,
    mode
)
    local command_map, status = load_command_display_map(character)
    if not command_map then return nil, status end
    return CommandDisplayOverrides.resolve_input_conditioned(
        command_map,
        action_id,
        direct_input,
        newly_pressed,
        mode
    )
end

function M.validate_sequence_command_display(sequence)
    return validate_sequence_command_display(sequence)
end

function M.parse_starter_icons(starter)
    local motion = tostring(starter or ""):upper():gsub("_", " ")
    local compact = motion:gsub("%s+", "")
    if compact == "RAWDR" then
        motion = "RAW DR"
    elseif compact == "DRIVERUSH" then
        motion = "DRIVE RUSH"
    end

    local tokens = parse_motion_to_icons({ motion = motion }, "starter", false, false)
    if type(tokens) ~= "table" or #tokens == 0 then return nil end
    for _, token in ipairs(tokens) do
        if type(token) ~= "table" or token.type ~= "img" then return nil end
    end
    return tokens
end

function M.reset_anim()
    imgui_anim.active_y = nil
end

function M.reset_raw()
    raw_state.history_p1 = {}
    raw_state.history_p2 = {}
end

return M
