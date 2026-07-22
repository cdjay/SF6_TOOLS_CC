"use strict";

const SCHEMA = "xt.command_display.v1";
const STRICT_POLICY = "verified_action_graph_v1";
const CLASSIC_PROFILE_ORDER = ["norm", "sprt"];
const MODERN_PROFILE_ORDER = ["easy", "supr", "sprt"];
const CLASSIC_TOKEN = /(^|[\s+>/])(?:LP|MP|HP|LK|MK|HK|PPP|KKK|PP|KK|P|K)(?=$|[\s+>/])/i;
const PROFILE_BUTTONS = new Set([
    "LP", "MP", "HP", "LK", "MK", "HK", "P", "K", "PP", "KK", "PPP", "KKK",
    "Throw", "Parry", "DI"
]);
const ATTACK_BITS = [[16, "弱"], [128, "中"], [256, "强"]];
const REBIND_REASON = "ac_type17_command_entry_rebind_from_verified_bcm_owner";
const RUNTIME_COMMON_REASON = "sf6_stable_runtime_common_movement_action";
const OFFICIAL_SEMANTIC_REASON = "capcom_official_command_semantics_matched_to_current_bcm_identity";
const COMMUNITY_SEMANTIC_REASON = "verified_community_command_semantics_matched_to_current_bcm_identity";
const VERIFIED_ALIAS_REASON = "ac_verified_equivalent_action_variant";
const TYPE20_DIRECTION_REASON = "ac_type20_verified_directional_air_attack";
const TYPE20_HOLD_REASON = "ac_type20_verified_hold_continuation";
const TYPE20_PHASE_REASON = "ac_type20_verified_multi_input_action_phase";
const CHARGE_CONTEXT_REASON = "bcm_charge_profile_context_proves_modern_held_shortcut";
const AC_CHARGE_CONTEXT_REASON = "ac_full_structure_peer_and_bcm_selector_prove_charge_context";
const SUPER_SHORTCUT_DIRECTION_REASON = "bcm_super_supr_direction_qualifies_easy_shortcut";
const CHARGE_COMPATIBILITY_REASON = "bcm_true_charge_trigger_suppresses_uncharged_compatibility_trigger";
const OFFICIAL_DIRECT_ROUTE_REASON = "capcom_official_exact_action_and_classic_identity_select_unique_direct_route";
const AC_STATE_DIRECTION_REASON = "ac_type20_multi_direction_state_choice";
const AC_STATE_NEUTRAL_REASON = "ac_type1_neutral_branch_beside_multi_direction_state_choices";
const AC_TYPE13_NEUTRAL_REASON = "ac_type13_zero_input_terminal_continuation_with_directional_sibling";
const AC_STATE_RELEASE_REASON = "ac_type20_release_transition_from_verified_direction_state";
const BCM_ZERO_INPUT_TRANSITION_REASON = "bcm_function2_normal_has_no_player_visible_input";
const TARGET_COMBO_REPEAT_REASON = "bcm_turn_around_target_combo_repeats_parent_button";
const STRUCTURAL_TWIN_REASON = "ac_bcm_unique_structural_twin_with_internal_use_super_delta";
const ASSIST_COMBO_REASON = "bcm_assist_combo_recipe_direct_input_sequence";
const OFFICIAL_FOLLOWUP_REASON = "capcom_official_followup_context_matches_source_move";
const ANY_BUTTON = "任意键";
const RUNTIME_COMMON_ACTIONS = Object.freeze({
    17: "66",
    18: "44",
    36: "8",
    37: "9",
    38: "7",
    489: "DP"
});
const AC_STRUCTURE_FIELDS = ["Category", "Combo", "Projectile", "State"];
const AC_FULL_STRUCTURE_FIELDS = ["ActionFrame", "Category", "Combo", "Frame", "Projectile", "State"];

function requiredButtonCount(profile) {
    return ((Number(profile && profile.ok_key_cond_flags || 0) >> 6) & 3) + 1;
}

function splitNotation(profile) {
    let notation = String(profile && profile.notation || "");
    const air = notation.startsWith("j.");
    if (air) notation = notation.slice(2);
    const parts = notation.split("+").filter(Boolean).map(part => part === "4236" ? "236" : part);
    return { air, parts };
}

function visibleDirections(parts) {
    return parts.filter(part => !PROFILE_BUTTONS.has(part) && part !== "Normal" && part !== "*");
}

function joinRoute(air, directions, buttons) {
    const parts = [...directions, ...buttons];
    if (!parts.length) return null;
    return `${air ? "空中 " : ""}${parts.join(" + ")}`;
}

function chargeContextFromProfiles(profiles) {
    for (const profileName of ["sprt", "norm"]) {
        const profile = profiles && profiles[profileName];
        const command = profile && profile.command;
        const match = profile && String(profile.notation || "").match(/^(j\.)?\[([1246789])\]/);
        const inputs = command && command.inputs;
        if (!profile || profile.enabled !== true || !command || Number(command.charge_bit || 0) === 0
            || !match || !Array.isArray(inputs)
            || !inputs.some(input => Number(input && input.type) === 1
                || input && input.charge_release === true)) continue;
        return {
            air: Boolean(match[1]),
            direction: match[2],
            profile: profileName,
            command_no: Number(profile.command_no),
            command_index: Number(profile.command_index),
            notation: String(profile.notation),
            source_action_id: null,
            source_trigger_indices: [],
            relation: "same_trigger_bcm",
            reason: CHARGE_CONTEXT_REASON
        };
    }
    return null;
}

function isChargeStateSelector(profile) {
    const command = profile && profile.command;
    const inputs = command && command.inputs;
    return Number(command && command.charge_bit || 0) !== 0
        && Array.isArray(inputs) && inputs.length === 1
        && Number(inputs[0] && inputs[0].type) === 1
        && inputs[0].charge_release !== true;
}

function superShortcutDirection(profiles, conditions) {
    if (Number(conditions && conditions.function_id) !== 3) return null;
    const supr = profiles && profiles.supr;
    if (!supr || supr.enabled !== true) return null;
    const { air, parts } = splitNotation(supr);
    const directions = visibleDirections(parts);
    return directions.length === 1 ? { air, direction: directions[0], profile: "supr",
        notation: String(supr.notation || ""), reason: SUPER_SHORTCUT_DIRECTION_REASON } : null;
}

function applySuperShortcutDirection(name, profiles, conditions, detail) {
    const context = name === "easy" ? superShortcutDirection(profiles, conditions) : null;
    if (!context || !detail || !detail.display || !detail.visible_button) return detail;
    const buttons = String(detail.visible_button).split(/\s+\+\s+/).filter(Boolean);
    if (!buttons.length) return detail;
    return { ...detail,
        display: joinRoute(context.air, [context.direction], buttons),
        visible_direction: context.direction,
        super_shortcut_direction_evidence: true,
        super_shortcut_direction_profile: context.profile,
        super_shortcut_direction: context.direction,
        super_shortcut_direction_notation: context.notation,
        super_shortcut_direction_reason: context.reason
    };
}

function applyChargeShortcutContext(name, profile, profiles, detail, inheritedContext) {
    const context = chargeContextFromProfiles(profiles) || inheritedContext;
    if (!context || !detail || !detail.display || !detail.visible_button
        || (name !== "easy" && name !== "supr")) return detail;
    const { air, parts } = splitNotation(profile);
    const directions = visibleDirections(parts);
    const selector = name === "easy" && isChargeStateSelector(profile);
    const selectedDirection = detail.super_shortcut_direction || context.direction;
    const heldDirection = !profile.command && directions.length === 1
        && (directions[0] === context.direction || directions[0] === selectedDirection);
    if (!selector && !heldDirection) return detail;
    const buttons = String(detail.visible_button).split(/\s+\+\s+/).filter(Boolean);
    if (!buttons.length) return detail;
    return {
        ...detail,
        display: joinRoute(air || context.air, [`[${selectedDirection}]`], buttons),
        visible_direction: `[${selectedDirection}]`,
        charge_context_evidence: true,
        charge_context_profile: context.profile,
        charge_context_direction: selectedDirection,
        charge_context_manual_direction: context.direction,
        charge_context_direction_profile: detail.super_shortcut_direction_profile || context.profile,
        charge_context_command_no: context.command_no,
        charge_context_command_index: context.command_index,
        charge_context_notation: context.notation,
        charge_context_source_action_id: context.source_action_id,
        charge_context_source_trigger_indices: context.source_trigger_indices,
        charge_context_relation: context.relation,
        charge_context_reason: context.reason
    };
}

function attackCandidates(profile) {
    const raw = Number(profile && profile.ok_key_flags || 0);
    if (raw === 112 || raw === 896) return ["弱", "中", "强"];
    return ATTACK_BITS.filter(([bit]) => (raw & bit) !== 0).map(([, name]) => name);
}

function translateSequentialAttack(profile) {
    const inputs = profile && profile.command && profile.command.inputs;
    if (!Array.isArray(inputs) || inputs.length < 2) return null;
    const nameOf = rawMask => {
        const found = ATTACK_BITS.find(([bit]) => Number(rawMask) === bit);
        return found ? found[1] : null;
    };
    const sequence = [];
    for (const input of inputs) {
        if (String(input && input.direction) !== "5") return null;
        const name = nameOf(input && input.raw_mask);
        if (!name) return null;
        sequence.push(name);
    }
    const finalButton = nameOf(profile.ok_key_flags);
    if (!finalButton) return null;
    sequence.push(finalButton);
    return sequence;
}

function resolved(display, direction, button, candidates, count) {
    return {
        display,
        visible_direction: direction || null,
        visible_button: button || null,
        button_candidates: candidates || [],
        required_button_count: Number.isFinite(count) ? count : null,
        unresolved_reason: null
    };
}

function unresolved(direction, candidates, count, reason) {
    return {
        display: null,
        visible_direction: direction || null,
        visible_button: null,
        button_candidates: candidates || [],
        required_button_count: Number.isFinite(count) ? count : null,
        unresolved_reason: reason
    };
}

function translateSprt(profile, conditions) {
    const { air, parts } = splitNotation(profile);
    const directions = visibleDirections(parts);
    const direction = directions.join("+") || null;
    const sequence = translateSequentialAttack(profile);
    if (sequence) {
        const button = sequence.join(" > ");
        return resolved(`${air ? "空中 " : ""}${button}`, direction, button,
            [...new Set(sequence)], requiredButtonCount(profile));
    }

    const raw = Number(profile && profile.ok_key_flags || 0);
    const count = requiredButtonCount(profile);
    const candidates = attackCandidates(profile);
    const pureDirection = directions.length === 1 && parts.length === 1
        && candidates.length === 0 && !profile.button && !profile.command
        && Number(conditions && conditions.function_id) === 1
        && [1, 2, 4, 8].includes(raw);
    if (pureDirection) {
        return resolved(`${air ? "空中 " : ""}${directions[0]}`, directions[0], null, [], 0);
    }
    let buttons = [];
    if (profile.button === "Throw" || raw === 144) buttons = ["THROW"];
    else if (profile.button === "Parry" || raw === 288) buttons = ["DP"];
    else if (profile.button === "DI" || raw === 576) buttons = ["DI"];
    else if (raw === 32 && Number(conditions && conditions.function_id) === 2) buttons = ["SP"];
    else if (candidates.length > 1 && candidates.length === count) buttons = candidates;
    else if (candidates.length > count && count === 1) buttons = [ANY_BUTTON];
    else if (candidates.length > count && count === 2) buttons = [ANY_BUTTON, ANY_BUTTON];
    else if (candidates.length > 1 && count >= 3) buttons = candidates;
    else if (candidates.length === 1) buttons = candidates;
    else if ((raw & 64) !== 0) buttons = ["DP"];
    else return unresolved(direction, candidates, count, "unsupported_sprt_button_mask");

    // Modern normal selection stores AUTO as a control-condition bit rather
    // than in the visible attack mask. A matching NG bit marks the plain
    // route; DC-only 0x200 marks the assisted route.
    const requiresAuto = (Number(profile.dc_exc_flags || 0) & 0x200) !== 0
        && (Number(profile.ng_key_flags || 0) & 0x200) === 0;
    if (requiresAuto) buttons = ["AUTO", ...buttons];

    const display = joinRoute(air, directions, buttons);
    return display
        ? resolved(display, direction, buttons.join(" + "), candidates, count)
        : unresolved(direction, candidates, count, "empty_sprt_route");
}

function translateEasy(profile, conditions) {
    const { air, parts } = splitNotation(profile);
    const directions = visibleDirections(parts);
    const direction = directions.join("+") || null;
    const raw = Number(profile && profile.ok_key_flags || 0);
    const candidates = attackCandidates(profile);
    const count = requiredButtonCount(profile);
    if (candidates.length > 1) {
        if (candidates.length === count) {
            return resolved(joinRoute(air, directions, candidates), direction,
                candidates.join(" + "), candidates, count);
        }
        const contextualAnyAttack = raw === 432 && count === 1
            && Number(profile.ng_key_flags || 0) === 2
            && Number(conditions && conditions.function_id) === 2
            && directions.length === 0;
        if (contextualAnyAttack) {
            const display = `${air ? "> 空中 " : "> "}${ANY_BUTTON}`;
            return resolved(display, null, ANY_BUTTON, candidates, count);
        }
        return unresolved(direction, candidates, count,
            count === 1 ? "multi_button_candidate_requires_runtime_selection"
                : "unsupported_easy_multi_button_selector");
    }
    let buttons = null;
    if (raw === 32) buttons = ["SP"];
    else if (raw === 288) buttons = ["SP", "强"];
    else if (raw === 16) buttons = ["弱"];
    else if (raw === 128) buttons = ["中"];
    else if (raw === 256) buttons = ["强"];
    if (!buttons) return unresolved(direction, candidates, count,
        "unsupported_easy_selector_mask");
    const requiresAuto = (Number(profile.dc_exc_flags || 0) & 0x200) !== 0
        && (Number(profile.ng_key_flags || 0) & 0x200) === 0;
    if (requiresAuto) buttons = ["AUTO", ...buttons];
    return resolved(joinRoute(air, directions, buttons), direction, buttons.join(" + "),
        candidates, count);
}

function translateSupr(profile, conditions) {
    if (Number(conditions && conditions.function_id) === 3) {
        return unresolved(null, [], requiredButtonCount(profile), "super_art_supr_selector_not_player_input");
    }
    const { air, parts } = splitNotation(profile);
    const directions = visibleDirections(parts);
    const direction = directions.join("+") || null;
    const raw = Number(profile && profile.ok_key_flags || 0);
    if (raw === 2147483648) {
        return unresolved(direction, [], requiredButtonCount(profile),
            "supr_internal_action_selector_not_player_input");
    }
    const buttons = ["AUTO"];
    if (raw === 8192 || raw === 32) buttons.push("SP");
    else if (raw === 16) buttons.push("弱");
    else if (raw === 128) buttons.push("中");
    else if (raw === 256 || raw === 512) buttons.push("强");
    else return unresolved(direction, attackCandidates(profile), requiredButtonCount(profile),
        "unsupported_supr_selector_mask");
    return resolved(joinRoute(air, directions, buttons), direction, buttons.join(" + "),
        attackCandidates(profile), requiredButtonCount(profile));
}

function translateProfileDetailed(name, profile, conditions, profiles, inheritedChargeContext) {
    if (!profile || profile.enabled !== true) return unresolved(null, [], null, "profile_disabled_or_missing");
    let detail;
    if (name === "sprt") detail = translateSprt(profile, conditions);
    else if (name === "easy") detail = translateEasy(profile, conditions);
    else if (name === "supr") detail = translateSupr(profile, conditions);
    else detail = unresolved(null, [], null, "unsupported_profile");
    detail = applySuperShortcutDirection(name, profiles, conditions, detail);
    return applyChargeShortcutContext(name, profile, profiles, detail, inheritedChargeContext);
}

function translateProfile(name, profile, conditions, profiles) {
    return translateProfileDetailed(name, profile, conditions, profiles).display;
}

function selectedProfiles(conditions, profiles) {
    const functionId = Number(conditions && conditions.function_id || 0);
    if (functionId === 1) {
        if (profiles && profiles.sprt && profiles.sprt.enabled === true) return ["sprt"];
        return ["sprt"];
    }
    if (functionId === 2) {
        const easyEnabled = profiles && profiles.easy && profiles.easy.enabled === true;
        const suprEnabled = profiles && profiles.supr && profiles.supr.enabled === true;
        const suprIsInternalSelector = suprEnabled
            && Number(profiles.supr.ok_key_flags || 0) === 2147483648;
        if (suprIsInternalSelector) return easyEnabled ? ["easy", "sprt"] : ["sprt"];
        if (easyEnabled && suprEnabled) {
            return Number(conditions && conditions.focus_consume || 0) >= 20000
                ? ["supr", "sprt"] : ["easy", "sprt"];
        }
        if (easyEnabled) return ["easy", "sprt"];
        if (suprEnabled) return ["supr", "sprt"];
        return ["sprt"];
    }
    if (functionId === 3) return ["easy", "sprt"];
    return ["supr", "sprt"];
}

function canonicalMultiButtonIdentity(value) {
    return normalizeClassicIdentity(value)
        .replace(/(?:LPMPHP|PPP|PP)$/i, "P_MULTI")
        .replace(/(?:LKMKHK|KKK|KK)$/i, "K_MULTI");
}

function selectedProfilesForAction(actionId, trigger, officialSemantics) {
    const selected = selectedProfiles(trigger.conditions, trigger.profiles);
    if (Number(trigger.conditions && trigger.conditions.function_id) !== 1) return selected;
    const profiles = trigger.profiles || {};
    const official = officialSemantics && officialSemantics[String(actionId)];
    const norm = profiles.norm;
    const verifiedOfficialFallback = official && String(official.modern_display || "").trim() !== ""
        && norm && norm.enabled === true
        && profiles.easy && profiles.easy.enabled === true
        && (!profiles.sprt || profiles.sprt.enabled !== true)
        && profiles.supr && profiles.supr.enabled === true
        && Number(profiles.supr.ok_key_flags || 0) === 2147483648
        && canonicalMultiButtonIdentity(official.classic_display)
            === canonicalMultiButtonIdentity(norm.notation);
    return verifiedOfficialFallback ? ["easy"] : selected;
}

function chargeCompatibilityConditionKey(conditions) {
    return JSON.stringify([
        Number(conditions && conditions.function_id || 0),
        Number(conditions && conditions.focus_consume || 0),
        Number(conditions && conditions.kind_level || 0),
        Number(conditions && conditions.kind_sub || 0),
        Number(conditions && conditions.category_flags || 0),
        Number(conditions && conditions.action_status_sub || 0),
        Number(conditions && conditions.turn_around || 0)
    ]);
}

function chargeCommandIsReal(profile) {
    const command = profile && profile.command;
    const inputs = command && command.inputs;
    return profile && profile.enabled === true && command
        && Number(command.charge_bit || 0) !== 0 && Array.isArray(inputs)
        && inputs.some(input => Number(input && input.type) === 1
            || input && input.charge_release === true)
        && /^j?\.?\[[1246789]\]/.test(String(profile.notation || ""));
}

function chargeCommandIsPlainCompatibility(profile) {
    const command = profile && profile.command;
    const inputs = command && command.inputs;
    return profile && profile.enabled === true && command
        && Number(command.charge_bit || 0) === 0 && Array.isArray(inputs)
        && !inputs.some(input => Number(input && input.type) === 1
            || input && input.charge_release === true);
}

function chargeCompatibilitySuppressions(action) {
    const triggers = action && action.triggers || [];
    const suppressions = [];
    for (const trigger of triggers) {
        const plain = trigger.profiles && trigger.profiles.sprt;
        if (!chargeCommandIsPlainCompatibility(plain)) continue;
        const plainNotation = String(plain.command.notation || "");
        const retained = triggers.filter(candidate => {
            const charge = candidate.profiles && candidate.profiles.sprt;
            return chargeCommandIsReal(charge)
                && Number(charge.ok_key_flags) === Number(plain.ok_key_flags)
                && String(charge.command.notation || "").replace(/[\[\]]/g, "") === plainNotation
                && chargeCompatibilityConditionKey(candidate.conditions)
                    === chargeCompatibilityConditionKey(trigger.conditions);
        });
        if (!retained.length) continue;
        suppressions.push({
            suppressed_trigger_index: Number(trigger.trigger_index),
            retained_trigger_indices: retained.map(item => Number(item.trigger_index))
                .sort((left, right) => left - right),
            profile: "sprt",
            plain_command_no: Number(plain.command_no),
            plain_command_index: Number(plain.command_index),
            plain_notation: plainNotation,
            charge_command_nos: [...new Set(retained.map(item =>
                Number(item.profiles.sprt.command_no)))].sort((left, right) => left - right),
            charge_command_indices: [...new Set(retained.map(item =>
                Number(item.profiles.sprt.command_index)))].sort((left, right) => left - right),
            charge_notations: [...new Set(retained.map(item =>
                String(item.profiles.sprt.command.notation)))].sort(),
            button_mask: Number(plain.ok_key_flags),
            reason: CHARGE_COMPATIBILITY_REASON
        });
    }
    return suppressions.sort((left, right) =>
        left.suppressed_trigger_index - right.suppressed_trigger_index);
}

function normalizeDisplay(display) {
    return typeof display === "string" ? display
        .replace(/強/g, "强")
        .replace(/攻撃/g, "攻击")
        .replace(/\s*>\s*/g, " > ")
        .replace(/\s*\+\s*/g, " + ")
        .replace(/\s+/g, " ")
        .trim() : "";
}

function assertValidDisplay(display) {
    if (!display || /\+\s*\+/.test(display) || display.includes("攻击三つ") || display.includes("*")
        || CLASSIC_TOKEN.test(display)) {
        throw new Error(`非法 Modern 显示 token: ${display}`);
    }
}

function scalar(value) {
    return value === undefined || value === null ? null : value;
}

function rawDirectionInputs(profile) {
    const inputs = profile && profile.command && profile.command.inputs;
    return Array.isArray(inputs) ? inputs.map(input => Number(input && input.raw_mask || 0)) : [];
}

function routeProvenance(character, ownerActionId, trigger, profileName, profile, detail, source) {
    return {
        character,
        owner_action_id: Number(ownerActionId),
        trigger_index: scalar(Number.isFinite(Number(trigger && trigger.trigger_index))
            ? Number(trigger.trigger_index) : null),
        profile: profileName || null,
        command_no: scalar(profile && Number.isFinite(Number(profile.command_no)) ? Number(profile.command_no) : null),
        command_index: scalar(profile && Number.isFinite(Number(profile.command_index)) ? Number(profile.command_index) : null),
        raw_direction_inputs: rawDirectionInputs(profile),
        raw_button_mask: scalar(profile ? Number(profile.ok_key_flags || 0) : null),
        raw_button_condition: scalar(profile ? Number(profile.ok_key_cond_flags || 0) : null),
        raw_dc_exc_flags: scalar(profile ? Number(profile.dc_exc_flags || 0) : null),
        raw_ng_key_flags: scalar(profile ? Number(profile.ng_key_flags || 0) : null),
        visible_direction: detail.visible_direction,
        visible_button: detail.visible_button,
        button_candidates: [...detail.button_candidates],
        required_button_count: detail.required_button_count,
        source,
        ac_relation_type: null,
        ac_path: [],
        inherited_from_action_id: null,
        confidence: "direct_structural",
        direct_evidence: true,
        inheritance_evidence: false,
        inheritance_reason: null,
        rebind_evidence: false,
        rebind_reason: null,
        runtime_common_evidence: false,
        runtime_common_reason: null,
        official_semantic_evidence: false,
        official_semantic_reason: null,
        community_semantic_evidence: false,
        community_semantic_reason: null,
        assist_combo_evidence: false,
        assist_combo_reason: null,
        charge_context_evidence: detail.charge_context_evidence === true,
        charge_context_profile: scalar(detail.charge_context_profile),
        charge_context_direction: scalar(detail.charge_context_direction),
        charge_context_manual_direction: scalar(detail.charge_context_manual_direction),
        charge_context_direction_profile: scalar(detail.charge_context_direction_profile),
        charge_context_command_no: scalar(detail.charge_context_command_no),
        charge_context_command_index: scalar(detail.charge_context_command_index),
        charge_context_notation: scalar(detail.charge_context_notation),
        charge_context_source_action_id: detail.charge_context_evidence === true
            ? Number(detail.charge_context_source_action_id == null
                ? ownerActionId : detail.charge_context_source_action_id) : null,
        charge_context_source_trigger_indices: detail.charge_context_evidence === true
            ? ((detail.charge_context_source_trigger_indices || []).length
                ? detail.charge_context_source_trigger_indices.map(Number)
                : [Number(trigger.trigger_index)]) : [],
        charge_context_relation: scalar(detail.charge_context_relation),
        charge_context_reason: scalar(detail.charge_context_reason),
        super_shortcut_direction_evidence: detail.super_shortcut_direction_evidence === true,
        super_shortcut_direction_profile: scalar(detail.super_shortcut_direction_profile),
        super_shortcut_direction: scalar(detail.super_shortcut_direction),
        super_shortcut_direction_notation: scalar(detail.super_shortcut_direction_notation),
        super_shortcut_direction_reason: scalar(detail.super_shortcut_direction_reason)
    };
}

function routeKey(route) {
    return [route.display, route.owner_action_id, route.trigger_index, route.profile, route.source].join(":");
}

function pushRoute(routes, seen, display, provenance) {
    display = normalizeDisplay(display);
    if (!display) return;
    assertValidDisplay(display);
    const route = { display, ...provenance };
    const key = routeKey(route);
    if (seen.has(key)) return;
    seen.add(key);
    routes.push(route);
}

function routeTriggerConditions(route, bcmCatalog) {
    const action = bcmCatalog.actions && bcmCatalog.actions[String(route.owner_action_id)];
    const trigger = action && (action.triggers || []).find(item =>
        Number(item.trigger_index) === Number(route.trigger_index));
    return trigger && trigger.conditions || {};
}

function sprtCommandKeys(entry) {
    return new Set((entry && entry.routes || []).filter(route =>
        route.source === "bcm_profile" && route.profile === "sprt"
        && Number(route.command_no) >= 0 && Number(route.command_index) >= 0)
        .map(route => `${Number(route.command_no)}:${Number(route.command_index)}`));
}

function setsIntersect(left, right) {
    for (const value of left) if (right.has(value)) return true;
    return false;
}

function promotePairedSprtSpRoutes(entries, bcmCatalog) {
    const relations = [];
    const actions = Object.entries(bcmCatalog.actions || {});
    const comparableCondition = conditions => JSON.stringify([
        Number(conditions && conditions.kind_level || 0),
        Number(conditions && conditions.kind_sub || 0),
        Number(conditions && conditions.turn_around || 0),
        Number(conditions && conditions.action_status_sub || 0),
        Number(conditions && conditions.cond_owner_state_flags || 0)
    ]);
    const normCommandKey = trigger => {
        const profile = trigger && trigger.profiles && trigger.profiles.norm;
        const commandNo = Number(profile && profile.command_no);
        const commandIndex = Number(profile && profile.command_index);
        return commandNo >= 0 && commandIndex >= 0 ? `${commandNo}:${commandIndex}` : null;
    };
    for (const [sourceId, action] of actions) {
        const entry = entries[sourceId];
        if (!entry) continue;
        for (const trigger of action.triggers || []) {
            const conditions = trigger.conditions || {};
            const sprt = trigger.profiles && trigger.profiles.sprt;
            const supr = trigger.profiles && trigger.profiles.supr;
            if (Number(conditions.function_id) !== 2 || Number(conditions.focus_consume || 0) >= 20000
                || !sprt || sprt.enabled !== true || Number(sprt.ok_key_flags) !== 32
                || Number(sprt.command_no) !== -1 || !supr || supr.enabled !== true
                || Number(supr.ok_key_flags) !== 8192) continue;
            const suprDetail = translateSupr(supr, conditions);
            if (!suprDetail.display) continue;
            const commandKey = normCommandKey(trigger);
            if (!commandKey) continue;
            const candidates = [];
            for (const [targetId, targetAction] of actions) {
                if (targetId === sourceId || !entries[targetId]) continue;
                for (const targetTrigger of targetAction.triggers || []) {
                    const targetConditions = targetTrigger.conditions || {};
                    const easy = targetTrigger.profiles && targetTrigger.profiles.easy;
                    if (Number(targetConditions.function_id) !== 2
                        || Number(targetConditions.focus_consume || 0) < 20000
                        || comparableCondition(targetConditions) !== comparableCondition(conditions)
                        || normCommandKey(targetTrigger) !== commandKey
                        || !easy || easy.enabled !== true || Number(easy.ok_key_flags) !== 32) continue;
                    const easyDetail = translateEasy(easy, trigger.conditions);
                    if (easyDetail.display === suprDetail.display) {
                        candidates.push({ targetId: Number(targetId), targetTrigger, easyDetail });
                    }
                }
            }
            const targetIds = [...new Set(candidates.map(item => item.targetId))];
            if (targetIds.length !== 1) continue;
            const { air, parts } = splitNotation(sprt);
            const directions = visibleDirections(parts);
            const direction = directions.join("+") || null;
            const detail = resolved(joinRoute(air, directions, ["SP"]), direction, "SP", [], 1);
            if (!detail.display) continue;
            const route = { display: normalizeDisplay(detail.display),
                ...routeProvenance("", sourceId, trigger, "sprt", sprt, detail, "bcm_profile") };
            route.character = entry.routes[0] && entry.routes[0].character || "Unknown";
            if (!entry.routes.some(existing => existing.display === route.display
                && existing.trigger_index === route.trigger_index && existing.profile === "sprt")) {
                assertRoute(route);
                entry.routes.push(route);
            }
            relations.push({ source_action_id: Number(sourceId), target_action_id: targetIds[0],
                trigger_index: Number(trigger.trigger_index), command_key: commandKey,
                display: route.display, shadowed_supr_display: suprDetail.display,
                reason: "paired_normal_od_command_owner_proves_sprt_sp" });
        }
    }
    return relations.sort((left, right) => left.source_action_id - right.source_action_id);
}

function suppressShadowedSuprRoutes(entries, bcmCatalog) {
    const suprRoutes = [];
    const directNonSuprRoutes = [];
    const officialByDisplay = new Map();
    for (const [id, entry] of Object.entries(entries)) {
        for (const route of entry.routes || []) {
            if (route.source === "bcm_profile" && route.profile === "supr"
                && route.direct_evidence === true) {
                suprRoutes.push({ id, entry, route });
            }
            if (route.source === "bcm_profile" && route.profile !== "supr"
                && route.direct_evidence === true) {
                directNonSuprRoutes.push({ id, entry, route });
            }
            if (route.official_semantic_evidence === true) {
                if (!officialByDisplay.has(route.display)) officialByDisplay.set(route.display, []);
                officialByDisplay.get(route.display).push({ id, route });
            }
        }
    }

    const suppressed = [];
    for (const candidate of suprRoutes) {
        // Never erase an Action's sole route. This pass only removes a
        // demonstrably shadowed shortcut while preserving its manual route.
        if (candidate.entry.routes.length < 2) continue;
        let reason = null, winners = [];

        const candidateConditions = routeTriggerConditions(candidate.route, bcmCatalog);
        const directOwners = directNonSuprRoutes.filter(item => item.id !== candidate.id
            && item.route.display === candidate.route.display);
        const directOwnerIds = [...new Set(directOwners.map(item => Number(item.id)))];
        if (!reason && directOwnerIds.length === 1) {
            reason = "direct_non_supr_route_owns_identical_shortcut";
            winners = directOwnerIds;
        }

        const officialOwners = (officialByDisplay.get(candidate.route.display) || [])
            .filter(item => item.id !== candidate.id);
        if (!reason && officialOwners.length === 1) {
            reason = "official_semantic_owns_identical_shortcut";
            winners = officialOwners.map(item => Number(item.id));
        } else if (!reason) {
            const candidateCost = Number(candidateConditions.focus_consume || 0);
            const candidateCommands = sprtCommandKeys(candidate.entry);
            if (candidateCost < 20000 && candidateCommands.size) {
                const odOwners = suprRoutes.filter(peer => peer.id !== candidate.id
                    && peer.route.display === candidate.route.display
                    && Number(routeTriggerConditions(peer.route, bcmCatalog).focus_consume || 0) >= 20000
                    && setsIntersect(candidateCommands, sprtCommandKeys(peer.entry)));
                if (odOwners.length === 1) {
                    reason = "drive_cost_owner_owns_identical_family_shortcut";
                    winners = odOwners.map(item => Number(item.id));
                }
            }
        }
        if (!reason) continue;
        candidate.entry.routes = candidate.entry.routes.filter(route => route !== candidate.route);
        suppressed.push({
            action_id: Number(candidate.id),
            display: candidate.route.display,
            trigger_index: Number(candidate.route.trigger_index),
            reason,
            shadowed_by_action_ids: winners
        });
    }
    suppressed.sort((left, right) => left.action_id - right.action_id
        || left.display.localeCompare(right.display));
    return suppressed;
}

function commonSemantic(trigger, rule) {
    const conditions = trigger && trigger.conditions || {};
    if (rule && rule.system_action === "drc") return { display: "DRC", source: "bcm_common_semantic", profile: null };
    if (rule && rule.system_action === "raw_dr") return { display: "RAW DR", source: "bcm_common_semantic", profile: null };
    if (Number(conditions.function_id) === 10 && Number(conditions.focus_consume) === 5000) {
        return { display: "DP", source: "bcm_common_semantic", profile: null };
    }
    const norm = trigger && trigger.profiles && trigger.profiles.norm;
    if (norm && norm.enabled === true && Number(norm.ok_key_flags) === 576 && norm.button === "DI") {
        return { display: "DI", source: "bcm_common_semantic", profile: "norm" };
    }
    return null;
}

function commonDetail(common) {
    return resolved(common.display, null, common.display, [], null);
}

function inheritedThrowRoute(character, relation, sourceRoute, direction) {
    const sourceId = Number(relation.source_action_id);
    const targetId = Number(relation.action_id);
    const path = Array.isArray(sourceRoute.ac_path) && sourceRoute.ac_path.length
        ? [...sourceRoute.ac_path, targetId] : [sourceId, targetId];
    return {
        display: direction ? `${direction} + THROW` : "THROW",
        character,
        owner_action_id: sourceRoute.owner_action_id,
        trigger_index: sourceRoute.trigger_index,
        profile: sourceRoute.profile,
        command_no: sourceRoute.command_no,
        command_index: sourceRoute.command_index,
        raw_direction_inputs: [...sourceRoute.raw_direction_inputs],
        raw_button_mask: sourceRoute.raw_button_mask,
        raw_button_condition: sourceRoute.raw_button_condition,
        raw_dc_exc_flags: sourceRoute.raw_dc_exc_flags,
        raw_ng_key_flags: sourceRoute.raw_ng_key_flags,
        visible_direction: direction || null,
        visible_button: "THROW",
        button_candidates: [...sourceRoute.button_candidates],
        required_button_count: sourceRoute.required_button_count,
        source: "ac_type63_throw",
        ac_relation_type: 63,
        ac_path: path,
        inherited_from_action_id: sourceId,
        confidence: "verified_inherited",
        direct_evidence: false,
        inheritance_evidence: true,
        inheritance_reason: "ac_type63_directional_throw_from_verified_throw_route",
        rebind_evidence: false,
        rebind_reason: null,
        runtime_common_evidence: false,
        runtime_common_reason: null,
        official_semantic_evidence: false,
        official_semantic_reason: null,
        community_semantic_evidence: false,
        community_semantic_reason: null,
        assist_combo_evidence: false,
        assist_combo_reason: null
    };
}

function runtimeCommonRoute(character, actionId, display) {
    const route = {
        display: normalizeDisplay(display),
        character,
        owner_action_id: Number(actionId),
        display_action_id: Number(actionId),
        bcm_owner_action_id: null,
        trigger_index: -1,
        profile: "runtime_common",
        command_no: -1,
        command_index: -1,
        raw_direction_inputs: [],
        raw_button_mask: 0,
        raw_button_condition: 0,
        raw_dc_exc_flags: 0,
        raw_ng_key_flags: 0,
        visible_direction: String(display),
        visible_button: null,
        button_candidates: [],
        required_button_count: 0,
        source: "runtime_common_action",
        ac_relation_type: null,
        ac_path: [],
        inherited_from_action_id: null,
        confidence: "verified_runtime_common",
        direct_evidence: false,
        inheritance_evidence: false,
        inheritance_reason: null,
        rebind_evidence: false,
        rebind_reason: null,
        runtime_common_evidence: true,
        runtime_common_reason: RUNTIME_COMMON_REASON,
        official_semantic_evidence: false,
        official_semantic_reason: null,
        community_semantic_evidence: false,
        community_semantic_reason: null,
        assist_combo_evidence: false,
        assist_combo_reason: null
    };
    assertValidDisplay(route.display);
    return route;
}

function acStateChoiceRoute(character, relation, display, source, reason, confidence) {
    const sourceId = Number(relation.source_action_id);
    const targetId = Number(relation.target_action_id);
    const route = {
        ...routeProvenance(character, sourceId, { trigger_index: -1 }, "ac_state_choice", null,
            resolved(display, display === "N" ? null : display, null, [], 0), source),
        display,
        display_action_id: targetId,
        bcm_owner_action_id: null,
        ac_relation_type: Number(relation.branch_type),
        ac_path: [sourceId, targetId],
        inherited_from_action_id: sourceId,
        confidence,
        direct_evidence: false,
        inheritance_evidence: true,
        inheritance_reason: reason,
        state_choice_source_action_ids: [...relation.source_action_ids],
        state_choice_direction_mask: relation.direction_mask == null
            ? null : Number(relation.direction_mask),
        state_choice_exit_action_id: relation.exit_action_id == null
            ? null : Number(relation.exit_action_id)
    };
    route.trigger_index = -1;
    route.command_no = -1;
    route.command_index = -1;
    route.raw_button_mask = 0;
    route.raw_button_condition = 0;
    route.raw_dc_exc_flags = 0;
    route.raw_ng_key_flags = 0;
    return route;
}

function normalizeClassicIdentity(value) {
    let text = String(value || "").replace(/強/g, "强").trim();
    text = text.replace(/^空中\s*/, "j.").replace(/\s+/g, "");
    return text;
}

function normalizeOfficialMoveName(value) {
    return String(value || "").replace(/[\s（）()]/g, "").replace(/後に$/, "");
}

function officialFollowupContext(entry) {
    for (const value of [entry && entry.classic_display, entry && entry.modern_display]) {
        const match = String(value || "").match(/^[（(]\s*(.+?)\s*後に\s*[）)]/);
        if (match) return normalizeOfficialMoveName(match[1]);
    }
    return null;
}

function inferOfficialFollowupRelations(officialSemantics, entries) {
    const officialEntries = Object.entries(officialSemantics || {})
        .filter(([id, entry]) => /^\d+$/.test(id) && entry && typeof entry === "object")
        .map(([id, entry]) => ({ id: Number(id), entry }));
    const moveIds = new Map();
    for (const item of officialEntries) {
        const name = normalizeOfficialMoveName(item.entry.move_name);
        if (!name) continue;
        if (!moveIds.has(name)) moveIds.set(name, []);
        moveIds.get(name).push(item.id);
    }

    const relations = new Map();
    for (const item of officialEntries) {
        const context = officialFollowupContext(item.entry);
        const targetId = String(item.id);
        if (!context || !entries[targetId]) continue;
        const sourceIds = (moveIds.get(context) || [])
            .map(Number).filter(id => id !== item.id && entries[String(id)]);
        if (sourceIds.length !== 1) continue;
        relations.set(targetId, {
            type: "followup",
            source_action_id: sourceIds[0],
            evidence: OFFICIAL_FOLLOWUP_REASON,
            official_move_name: String(item.entry.move_name || "")
        });
    }
    return relations;
}

function cleanCommandDisplay(value, stripFollowup) {
    const display = normalizeDisplay(value);
    return (stripFollowup ? display.replace(/^>\s*/, "") : display).trim();
}

function commandKind(route) {
    const profile = String(route && route.profile || "");
    const display = cleanCommandDisplay(route && route.display);
    const button = String(route && route.visible_button || "");
    if (profile === "easy" || profile === "supr" || profile === "assist_combo") return "simple";
    if (/\bAUTO\b/.test(display) || /\bAUTO\b/.test(button)) return "simple";
    if (button === "SP" && !/\d{2,}|\[[1246789]\]/.test(display)) return "simple";
    return "motion";
}

function compactCommand(routes, stripFollowup) {
    const unique = [];
    const seen = new Set();
    for (const route of routes) {
        const display = cleanCommandDisplay(route.display, stripFollowup);
        if (!display || seen.has(display)) continue;
        seen.add(display);
        unique.push({ route, display });
    }
    if (!unique.length) return null;

    let display = unique[0].display;
    const buttons = [...new Set(unique.map(item => String(item.route.visible_button || "")))];
    const directions = [...new Set(unique.map(item => String(item.route.visible_direction || "")))];
    const air = unique.every(item => item.display.startsWith("空中 "));
    const mergeableDirections = unique.length > 1 && buttons.length === 1 && buttons[0]
        && directions.length === unique.length && directions.every(direction => /^[1246789]$/.test(direction));
    if (mergeableDirections) {
        display = `${air ? "空中 " : ""}${directions.join(" 或 ")} + ${buttons[0]}`;
    } else if (unique.length > 1) {
        display = unique.map(item => item.display).join(" 或 ");
    }
    return { display, inputs: unique.map(item => item.display) };
}

function splitCommands(entry, relation) {
    let routes = entry.routes || [];
    if (relation && relation.type === "followup" && routes.some(route => route.profile !== "supr")) {
        routes = routes.filter(route => route.profile !== "supr");
    }
    const stripFollowup = relation && relation.type === "followup";
    const simple = compactCommand(routes.filter(route => commandKind(route) === "simple"), stripFollowup);
    const motion = compactCommand(routes.filter(route => commandKind(route) === "motion"), stripFollowup);
    return { simple, motion };
}

function compactClassicCommand(value) {
    const display = String(value || "").trim();
    if (!display || display === "Unknown") return null;
    return { display, inputs: [display] };
}

function commandControlSupport(classic, modern) {
    if (classic && modern) return "classic_modern";
    if (classic) return "classic_only";
    // A missing Classic projection is a compiler coverage gap, not evidence
    // that the underlying Action is Modern-only.
    if (modern) return "unknown";
    return "unknown";
}

function canonicalClassicIdentity(value) {
    return normalizeClassicIdentity(value)
        .replace(/PPP$/i, "LPMPHP")
        .replace(/KKK$/i, "LKMKHK");
}

function exactOfficialButtonDisplay(entry) {
    if (!entry || !["NORMAL", "AIR"].includes(String(entry.category || ""))) return null;
    const compact = String(entry.modern_display || "").replace(/強/g, "强")
        .replace(/[\s+]/g, "");
    if (!/^[弱中强]{1,3}$/.test(compact)) return null;
    const buttons = [...compact];
    if (new Set(buttons).size !== buttons.length) return null;
    return buttons.join(" + ");
}

function restrictDirectRoutesByExactOfficialSemantics(entries, officialSemantics, bcmCatalog) {
    const applied = [];
    for (const [idText, official] of Object.entries(officialSemantics || {})) {
        if (!/^\d+$/.test(idText)) continue;
        const id = Number(idText), entry = entries[idText];
        const action = bcmCatalog.actions && bcmCatalog.actions[idText];
        const expectedDisplay = exactOfficialButtonDisplay(official);
        if (!entry || !action || !expectedDisplay) continue;
        const officialClassic = canonicalClassicIdentity(official.classic_display);
        const identityTriggers = (action.triggers || []).filter(trigger => {
            const norm = trigger.profiles && trigger.profiles.norm;
            return Number(trigger.conditions && trigger.conditions.function_id) === 1
                && norm && norm.enabled === true
                && canonicalClassicIdentity(norm.notation) === officialClassic;
        });
        if (identityTriggers.length !== 1) continue;
        const direct = entry.routes.filter(route => route.source === "bcm_profile"
            && route.direct_evidence === true && Number(route.owner_action_id) === id);
        const winners = direct.filter(route => normalizeDisplay(route.display) === expectedDisplay);
        if (winners.length !== 1 || direct.length <= 1) continue;
        const removed = direct.filter(route => route !== winners[0]);
        if (!removed.length) continue;
        const removedSet = new Set(removed);
        entry.routes = entry.routes.filter(route => !removedSet.has(route));
        applied.push({
            action_id: id,
            official_classic_display: String(official.classic_display || ""),
            official_modern_display: String(official.modern_display || ""),
            matched_trigger_index: Number(identityTriggers[0].trigger_index),
            retained_display: winners[0].display,
            retained_trigger_index: Number(winners[0].trigger_index),
            suppressed_routes: removed.map(route => ({
                display: route.display,
                trigger_index: Number(route.trigger_index),
                profile: route.profile
            })),
            reason: OFFICIAL_DIRECT_ROUTE_REASON
        });
    }
    return applied.sort((left, right) => left.action_id - right.action_id);
}

function atomicOfficialAssistedNormal(entry) {
    if (!entry || (entry.category !== "NORMAL" && entry.category !== "AIR")) return null;
    const display = normalizeDisplay(String(entry.modern_display || "").replace(/強/g, "强"));
    const match = display.match(/^(空中\s+)?AUTO\s*\+\s*(弱|中|强)$/);
    if (!match) return null;
    const classicIdentity = normalizeClassicIdentity(entry.classic_display);
    if (!/^j\.(?:[1-9]\+)?(?:LP|MP|HP|LK|MK|HK)$/.test(classicIdentity)
        && !/^(?:[1-9]\+)?(?:LP|MP|HP|LK|MK|HK)$/.test(classicIdentity)) return null;
    return {
        display,
        classic_identity: classicIdentity,
        air: classicIdentity.startsWith("j."),
        visible_button: `AUTO + ${match[2]}`,
        button: match[2]
    };
}

function officialQualifiedDirectDisplay(semanticDisplay) {
    return normalizeDisplay(semanticDisplay).replace(/^(空中\s+)?AUTO\s*\+\s*/, "$1").trim();
}

function officialSemanticRoute(character, targetId, trigger, profile, semantic, officialId, entry, distance,
    hintKind, rowId) {
    const route = {
        ...routeProvenance(character, targetId, trigger, "norm_identity", profile,
            resolved(semantic.display, semantic.air ? "空中" : null,
                semantic.visible_button,
                semantic.button_candidates || (semantic.button ? [semantic.button] : []),
                Number.isFinite(semantic.required_button_count)
                    ? semantic.required_button_count : 1), "official_semantic_bcm_rebind"),
        display: semantic.display,
        display_action_id: Number(targetId),
        bcm_owner_action_id: Number(targetId),
        confidence: "verified_official_semantic_bcm_identity",
        direct_evidence: false,
        official_semantic_evidence: true,
        official_semantic_reason: OFFICIAL_SEMANTIC_REASON,
        official_action_id_hint: Number(officialId),
        official_action_id_hint_kind: String(hintKind || "capcom_action_id"),
        official_semantic_row_id: rowId == null ? null : String(rowId),
        official_action_id_distance: Number(distance),
        official_classic_display: String(entry.classic_display || ""),
        official_modern_display: String(entry.modern_display || ""),
        official_web_id: entry.official_web_id == null ? null : String(entry.official_web_id),
        official_move_name: entry.move_name == null ? null : String(entry.move_name)
    };
    assertValidDisplay(route.display);
    return route;
}

function communitySemanticRoute(character, targetId, trigger, profile, semantic, actionIdHint, entry, distance) {
    const route = {
        ...routeProvenance(character, targetId, trigger, "norm_identity", profile,
            resolved(semantic.display, semantic.air ? "空中" : null,
                semantic.visible_button, [semantic.button], 1), "community_semantic_bcm_rebind"),
        display: semantic.display,
        display_action_id: Number(targetId),
        bcm_owner_action_id: Number(targetId),
        confidence: "verified_community_semantic_bcm_identity",
        direct_evidence: false,
        community_semantic_evidence: true,
        community_semantic_reason: COMMUNITY_SEMANTIC_REASON,
        community_action_id_hint: Number(actionIdHint),
        community_action_id_distance: Number(distance),
        community_classic_display: String(entry.classic_display || ""),
        community_modern_display: String(entry.modern_display || ""),
        community_evidence_id: entry.evidence_id == null ? null : String(entry.evidence_id),
        community_evidence_note: entry.evidence_note == null ? null : String(entry.evidence_note)
    };
    assertValidDisplay(route.display);
    return route;
}

function verifiedAliasRoute(character, relation, sourceRoute) {
    const sourceId = Number(relation.target_action_id);
    const targetId = Number(relation.alias_action_id);
    const branchType = Number(relation.branch_type);
    const path = Array.isArray(sourceRoute.ac_path) && sourceRoute.ac_path.length
        ? [...sourceRoute.ac_path, targetId] : [sourceId, targetId];
    return {
        ...sourceRoute,
        character,
        display_action_id: targetId,
        source: "ac_verified_alias_variant",
        ac_relation_type: branchType,
        ac_path: path,
        inherited_from_action_id: sourceId,
        confidence: "verified_inherited_alias",
        direct_evidence: false,
        inheritance_evidence: true,
        inheritance_reason: VERIFIED_ALIAS_REASON,
        rebind_evidence: false,
        rebind_reason: null,
        runtime_common_evidence: false,
        runtime_common_reason: null,
        official_semantic_evidence: false,
        official_semantic_reason: null,
        community_semantic_evidence: false,
        community_semantic_reason: null,
        assist_combo_evidence: false,
        assist_combo_reason: null
    };
}

function inheritedRouteFromSource(character, sourceRoute, sourceId, targetId, display, source,
    relationType, reason, confidence) {
    const path = Array.isArray(sourceRoute.ac_path) && sourceRoute.ac_path.length
        ? [...sourceRoute.ac_path, targetId] : [sourceId, targetId];
    return {
        ...sourceRoute,
        display: normalizeDisplay(display),
        character,
        display_action_id: targetId,
        bcm_owner_action_id: Number.isFinite(Number(sourceRoute.bcm_owner_action_id))
            ? Number(sourceRoute.bcm_owner_action_id) : Number(sourceRoute.owner_action_id),
        source,
        ac_relation_type: relationType,
        ac_path: path,
        inherited_from_action_id: sourceId,
        confidence,
        direct_evidence: false,
        inheritance_evidence: true,
        inheritance_reason: reason,
        rebind_evidence: false,
        rebind_reason: null,
        runtime_common_evidence: false,
        runtime_common_reason: null,
        official_semantic_evidence: false,
        official_semantic_reason: null,
        community_semantic_evidence: false,
        community_semantic_reason: null,
        assist_combo_evidence: false,
        assist_combo_reason: null
    };
}

function type20DirectionalRoute(character, relation, sourceRoute, direction, button) {
    const sourceId = Number(relation.source_action_id);
    const targetId = Number(relation.action_id);
    const route = inheritedRouteFromSource(character, sourceRoute, sourceId, targetId,
        `空中 ${direction} + ${button}`, "ac_type20_directional_air_attack", 20,
        TYPE20_DIRECTION_REASON, "verified_inherited_directional_attack");
    route.visible_direction = String(direction);
    route.visible_button = button;
    route.button_candidates = [button];
    route.required_button_count = 1;
    return route;
}

function type20HoldRoute(character, relation, sourceRoute, button) {
    const sourceId = Number(relation.source_action_id);
    const targetId = Number(relation.target_action_id);
    const route = inheritedRouteFromSource(character, sourceRoute, sourceId, targetId,
        `> ${button}`, "ac_type20_hold_continuation", 20,
        TYPE20_HOLD_REASON, "verified_inherited_hold_continuation");
    route.visible_direction = null;
    route.visible_button = button;
    route.button_candidates = [button];
    route.required_button_count = 1;
    route.ac_param00 = relation.param00;
    route.ac_param01 = relation.param01;
    route.ac_param02 = relation.param02;
    route.ac_param03 = relation.param03;
    route.source_loop_count = relation.source_loop_count;
    route.target_loop_count = relation.target_loop_count;
    return route;
}

function type20ActionPhaseRoute(character, relation, sourceRoute) {
    const sourceId = Number(relation.source_action_id);
    const targetId = Number(relation.target_action_id);
    const route = inheritedRouteFromSource(character, sourceRoute, sourceId, targetId,
        sourceRoute.display, "ac_type20_action_phase", 20,
        TYPE20_PHASE_REASON, "verified_inherited_action_phase");
    route.ac_phase_signatures = relation.signatures.map(signature => ({ ...signature }));
    return route;
}

function targetComboRepeatRoute(character, targetId, parentId, trigger, profile, parentButton) {
    const detail = resolved(`> ${parentButton}`, null, parentButton, [parentButton], 1);
    const route = {
        ...routeProvenance(character, targetId, trigger, "norm_target_combo", profile, detail,
            "bcm_target_combo_repeat"),
        display: `> ${parentButton}`,
        display_action_id: targetId,
        bcm_owner_action_id: targetId,
        ac_path: [parentId, targetId],
        inherited_from_action_id: parentId,
        confidence: "verified_bcm_target_combo_repeat",
        direct_evidence: false,
        inheritance_evidence: true,
        inheritance_reason: TARGET_COMBO_REPEAT_REASON
    };
    return route;
}

function structuralTwinRoute(character, relation, sourceRoute) {
    return inheritedRouteFromSource(character, sourceRoute, relation.source_action_id,
        relation.target_action_id, sourceRoute.display, "ac_bcm_structural_twin", null,
        STRUCTURAL_TWIN_REASON, "verified_unique_structural_twin");
}

function assistComboRelations(bcmCatalog, actionSet) {
    const grouped = new Map();
    for (const row of bcmCatalog.assist_combo_recipes || []) {
        const actionId = Number(row && row.action_id);
        const triggerId = Number(row && row.trigger_id);
        const strength = String(row && row.assist_strength || "");
        const stage = String(row && row.input_stage || "");
        if (!Number.isInteger(actionId) || !actionSet.has(String(actionId))
            || !Number.isInteger(triggerId) || triggerId < 0
            || !["弱", "中", "强"].includes(strength)
            || !["first", "repeat"].includes(stage)) continue;
        const display = stage === "first" ? `AUTO + ${strength}` : `> ${strength}`;
        const key = `${actionId}:${display}`;
        if (!grouped.has(key)) grouped.set(key, {
            action_id: actionId,
            display,
            assist_strength: strength,
            input_stage: stage,
            reason: ASSIST_COMBO_REASON,
            occurrences: []
        });
        grouped.get(key).occurrences.push({
            array_index: Number(row.array_index),
            strength_index: Number(row.strength_index),
            recipe_index: Number(row.recipe_index),
            step_index: Number(row.step_index),
            trigger_id: triggerId,
            is_end_at_normal: row.is_end_at_normal === true,
            delay: Number(row.delay || 0),
            next_input_delay: Number(row.next_input_delay ?? -1),
            next_input_limit: Number(row.next_input_limit ?? -1),
            condition_flag: row.condition_flag == null ? null : row.condition_flag,
            wt_action_trigger: Number(row.wt_action_trigger || 0),
            wt_action_strength: Number(row.wt_action_strength || 0),
            wt_action_is_air: row.wt_action_is_air === true
        });
    }
    const relations = [...grouped.values()];
    for (const relation of relations) relation.occurrences.sort((left, right) =>
        left.array_index - right.array_index || left.trigger_id - right.trigger_id);
    relations.sort((left, right) => left.action_id - right.action_id
        || left.display.localeCompare(right.display));
    return relations;
}

function assistComboRoute(character, relation) {
    const first = relation.occurrences[0];
    return {
        display: relation.display,
        character,
        owner_action_id: relation.action_id,
        display_action_id: relation.action_id,
        bcm_owner_action_id: relation.action_id,
        trigger_index: first.trigger_id,
        profile: "assist_combo",
        command_no: -1,
        command_index: -1,
        raw_direction_inputs: [],
        raw_button_mask: 0,
        raw_button_condition: 0,
        raw_dc_exc_flags: 0,
        raw_ng_key_flags: 0,
        visible_direction: null,
        visible_button: relation.input_stage === "first"
            ? `AUTO + ${relation.assist_strength}` : relation.assist_strength,
        button_candidates: [relation.assist_strength],
        required_button_count: 1,
        source: "bcm_assist_combo_recipe",
        ac_relation_type: null,
        ac_path: [],
        inherited_from_action_id: null,
        confidence: "direct_assist_combo_recipe",
        direct_evidence: true,
        inheritance_evidence: false,
        inheritance_reason: null,
        rebind_evidence: false,
        rebind_reason: null,
        runtime_common_evidence: false,
        runtime_common_reason: null,
        official_semantic_evidence: false,
        official_semantic_reason: null,
        community_semantic_evidence: false,
        community_semantic_reason: null,
        assist_combo_evidence: true,
        assist_combo_reason: ASSIST_COMBO_REASON,
        assist_strength: relation.assist_strength,
        assist_input_stage: relation.input_stage,
        assist_recipe_occurrences: relation.occurrences.map(item => ({ ...item }))
    };
}

function bindOfficialSemantics(officialSemantics, bcmCatalog, actionSet) {
    const identityIndex = new Map();
    for (const [id, action] of Object.entries(bcmCatalog.actions || {})) {
        if (!actionSet.has(id)) continue;
        for (const trigger of action.triggers || []) {
            if (Number(trigger.conditions && trigger.conditions.function_id) !== 1) continue;
            const profile = trigger.profiles && trigger.profiles.norm;
            if (!profile || profile.enabled !== true) continue;
            const identity = normalizeClassicIdentity(profile.notation);
            if (!identityIndex.has(identity)) identityIndex.set(identity, []);
            const hasModernProfile = MODERN_PROFILE_ORDER.some(profileName =>
                trigger.profiles && trigger.profiles[profileName]
                && trigger.profiles[profileName].enabled === true);
            identityIndex.get(identity).push({ id: Number(id), trigger, profile, hasModernProfile });
        }
    }

    const bindings = [], unresolved = [];
    const semanticInputs = [];
    for (const [officialIdText, entry] of Object.entries(officialSemantics || {})) {
        if (/^\d+$/.test(officialIdText)) {
            semanticInputs.push({ entry, officialId: Number(officialIdText), rowId: null,
                hintKind: "capcom_action_id" });
        }
    }
    for (const entry of (officialSemantics && officialSemantics._semantic_rows) || []) {
        if (entry && typeof entry === "object") {
            semanticInputs.push({ entry, officialId: null, rowId: String(entry.row_id || ""),
                hintKind: "derived_current_bcm_identity" });
        }
    }
    for (const input of semanticInputs) {
        const { entry, officialId, rowId, hintKind } = input;
        const semantic = atomicOfficialAssistedNormal(entry);
        if (!semantic) continue;
        const candidates = (identityIndex.get(semantic.classic_identity) || []).slice();
        if (!candidates.length) {
            unresolved.push({ official_action_id_hint: officialId, display: semantic.display,
                official_semantic_row_id: rowId, classic_identity: semantic.classic_identity,
                reason: "no_current_bcm_identity_match" });
            continue;
        }
        let selected = null, distance = 0;
        if (officialId !== null) {
            candidates.sort((left, right) => Math.abs(left.id - officialId) - Math.abs(right.id - officialId)
                || left.id - right.id || Number(left.trigger.trigger_index) - Number(right.trigger.trigger_index));
            distance = Math.abs(candidates[0].id - officialId);
            const nearestIds = [...new Set(candidates.filter(candidate =>
                Math.abs(candidate.id - officialId) === distance).map(candidate => candidate.id))];
            if (nearestIds.length === 1) selected = candidates.find(candidate => candidate.id === nearestIds[0]);
        } else {
            const missingDirectIds = [...new Set(candidates.filter(candidate => !candidate.hasModernProfile)
                .map(candidate => candidate.id))];
            const allIds = [...new Set(candidates.map(candidate => candidate.id))];
            const selectedIds = missingDirectIds.length === 1 ? missingDirectIds
                : (allIds.length === 1 ? allIds : []);
            if (selectedIds.length === 1) selected = candidates.find(candidate => candidate.id === selectedIds[0]);
        }
        if (!selected) {
            unresolved.push({ official_action_id_hint: officialId, display: semantic.display,
                official_semantic_row_id: rowId, classic_identity: semantic.classic_identity,
                candidate_action_ids: [...new Set(candidates.map(candidate => candidate.id))],
                reason: officialId === null ? "ambiguous_current_bcm_identity"
                    : "ambiguous_nearest_current_bcm_identity" });
            continue;
        }
        bindings.push({ official_action_id_hint: officialId === null ? selected.id : officialId,
            official_action_id_hint_kind: hintKind, official_semantic_row_id: rowId,
            target_action_id: selected.id, action_id_distance: distance,
            semantic, entry, trigger: selected.trigger, profile: selected.profile });
    }
    bindings.sort((left, right) => left.target_action_id - right.target_action_id
        || left.official_action_id_hint - right.official_action_id_hint);
    return { bindings, unresolved };
}

function fieldsOf(object) {
    return new Map((object && object.fields || []).map(field => [field.name, field]));
}

function numericField(fields, name) {
    const field = fields.get(name);
    const value = field && field.value;
    return value && value.kind === "number" && Number.isFinite(Number(value.value))
        ? Number(value.value) : null;
}

function stableGraphValue(value, objects, seen) {
    if (!value || typeof value !== "object") return value;
    if (value.kind === "ref") {
        if (seen.has(value.object_id)) return ["cycle"];
        const object = objects.get(value.object_id);
        if (!object) return null;
        const nextSeen = new Set([...seen, value.object_id]);
        return {
            type: object.object_type || "",
            fields: (object.fields || []).slice()
                .sort((left, right) => String(left.name).localeCompare(String(right.name)))
                .map(field => [field.name, stableGraphValue(field.value, objects, nextSeen)]),
            items: (object.items || []).map(item =>
                [item.index, stableGraphValue(item.value, objects, nextSeen)])
        };
    }
    if (Array.isArray(value)) return value.map(item => stableGraphValue(item, objects, seen));
    const output = {};
    for (const key of Object.keys(value).sort()) output[key] = stableGraphValue(value[key], objects, seen);
    return output;
}

function actionStructureCategory(root, objects) {
    if (!root || root.object_type !== "FAB.ACTION") return null;
    const fields = fieldsOf(root);
    const parts = [];
    for (const name of AC_STRUCTURE_FIELDS) {
        const field = fields.get(name);
        if (!field || !field.value || field.value.kind !== "ref") return null;
        parts.push([name, stableGraphValue(field.value, objects, new Set([root.object_id]))]);
    }
    return JSON.stringify(parts);
}

function actionFullStructure(root, objects) {
    if (!root || root.object_type !== "FAB.ACTION") return null;
    const fields = fieldsOf(root);
    const parts = [];
    for (const name of AC_FULL_STRUCTURE_FIELDS) {
        const field = fields.get(name);
        if (!field || !field.value) return null;
        parts.push([name, stableGraphValue(field.value, objects, new Set([root.object_id]))]);
    }
    return JSON.stringify(parts);
}

function characterActionGraph(actionSource, actionSet) {
    const objects = new Map((actionSource.objects || []).map(object => [object.object_id, object]));
    const actions = new Map();
    for (const record of actionSource.records || []) {
        const actionId = Number(record && record.native_action_id);
        const ref = record && record.action_ref;
        if (record && record.source_scope === "character" && actionSet.has(String(actionId))
            && ref && ref.kind === "ref" && !actions.has(actionId)) {
            const root = objects.get(ref.object_id);
            if (root) actions.set(actionId, root);
        }
    }
    return { objects, actions };
}

function actionBranches(root, objects) {
    const keys = referencedObject(root, "Keys", objects);
    const pending = keys ? [keys.object_id] : [];
    const visited = new Set(), branches = [];
    while (pending.length) {
        const objectId = pending.pop();
        if (visited.has(objectId)) continue;
        visited.add(objectId);
        const object = objects.get(objectId);
        if (!object) continue;
        if (object.object_type === "CharacterAsset.BranchKey") {
            const fields = fieldsOf(object), branch = {};
            for (const name of ["Action", "Type", "Attr", "ActionFrame", "Param00", "Param01",
                "Param02", "Param03", "Param04", "Param05", "TriggerID"]) {
                branch[name] = numericField(fields, name);
            }
            branches.push(branch);
        }
        for (const field of object.fields || []) {
            if (field.value && field.value.kind === "ref") pending.push(field.value.object_id);
        }
        for (const item of object.items || []) {
            if (item.value && item.value.kind === "ref") pending.push(item.value.object_id);
        }
    }
    return branches;
}

function exactStateBranch(branch, type, param00, param01) {
    return Number(branch.Type) === type && Number(branch.Attr) === 0
        && Number(branch.ActionFrame) === 0 && Number(branch.Param00) === param00
        && (param01 === undefined || Number(branch.Param01) === param01)
        && Number(branch.Param02) === 0 && Number(branch.Param03) === 0
        && Number(branch.Param04) === 0 && Number(branch.Param05) === 0
        && Number(branch.TriggerID) === -1;
}

function strictStateChoiceEvidence(actionSource, bcmCatalog, actionSet) {
    const { objects, actions } = characterActionGraph(actionSource, actionSet);
    const branchesByAction = new Map([...actions].map(([id, root]) =>
        [id, actionBranches(root, objects)]));
    const directionOfMask = new Map([[1, "8"], [2, "2"], [4, "4"], [8, "6"]]);
    const directionCandidates = [], neutralCandidates = [];
    const stateSources = new Set();
    for (const [sourceId, branches] of branchesByAction) {
        const directions = branches.filter(branch => exactStateBranch(branch, 20, 1)
            && directionOfMask.has(Number(branch.Param01)));
        const sourceAction = bcmCatalog.actions && bcmCatalog.actions[String(sourceId)];
        const verifiedInternalSelectorEntry = sourceAction && (sourceAction.triggers || []).length === 1
            && (sourceAction.triggers || []).every(trigger => {
                const profiles = trigger.profiles || {};
                return Number(trigger.conditions && trigger.conditions.function_id) === 1
                    && profiles.easy && profiles.easy.enabled === true
                    && (!profiles.sprt || profiles.sprt.enabled !== true)
                    && profiles.supr && profiles.supr.enabled === true
                    && Number(profiles.supr.ok_key_flags || 0) === 2147483648;
            });
        const isMultiDirectionChoice = new Set(directions.map(branch => Number(branch.Param01))).size >= 2;
        if (!isMultiDirectionChoice
            && !verifiedInternalSelectorEntry) continue;
        stateSources.add(sourceId);
        for (const branch of directions) directionCandidates.push({
            source_action_id: sourceId,
            target_action_id: Number(branch.Action),
            direction_mask: Number(branch.Param01),
            direction: directionOfMask.get(Number(branch.Param01)),
            branch_type: 20,
            param00: 1,
            param01: Number(branch.Param01),
            param02: 0,
            param03: 0,
            reason: AC_STATE_DIRECTION_REASON
        });
        const neutralTargets = isMultiDirectionChoice ? [...new Set(branches.filter(branch =>
            exactStateBranch(branch, 1, 0, 0)).map(branch => Number(branch.Action)))] : [];
        if (neutralTargets.length === 1) neutralCandidates.push({
            source_action_id: sourceId,
            target_action_id: neutralTargets[0],
            branch_type: 1,
            reason: AC_STATE_NEUTRAL_REASON
        });
    }

    const groupedDirections = new Map();
    for (const relation of directionCandidates) {
        const key = String(relation.target_action_id);
        if (!groupedDirections.has(key)) groupedDirections.set(key, []);
        groupedDirections.get(key).push(relation);
    }
    const directions = [];
    for (const relations of groupedDirections.values()) {
        const directionsFound = [...new Set(relations.map(item => item.direction))];
        const targetId = relations[0].target_action_id;
        if (directionsFound.length !== 1 || bcmCatalog.actions && bcmCatalog.actions[String(targetId)]) continue;
        directions.push({
            ...relations[0],
            source_action_ids: [...new Set(relations.map(item => item.source_action_id))]
                .sort((left, right) => left - right)
        });
    }

    const neutrals = [];
    for (const relation of neutralCandidates) {
        if (bcmCatalog.actions && bcmCatalog.actions[String(relation.target_action_id)]) continue;
        if (!neutrals.some(item => item.target_action_id === relation.target_action_id)) {
            neutrals.push({ ...relation, source_action_ids: [relation.source_action_id] });
        } else {
            const existing = neutrals.find(item => item.target_action_id === relation.target_action_id);
            existing.source_action_ids.push(relation.source_action_id);
            existing.source_action_ids.sort((left, right) => left - right);
        }
    }

    const directionBySource = new Map(directions.flatMap(relation =>
        relation.source_action_ids.map(sourceId => [sourceId, relation])));
    const releases = [];
    for (const direction of directions) {
        const targetBranches = branchesByAction.get(direction.target_action_id) || [];
        const releaseTargets = [...new Set(targetBranches.filter(branch =>
            exactStateBranch(branch, 20, 0, direction.direction_mask))
            .map(branch => Number(branch.Action)))];
        if (releaseTargets.length !== 1) continue;
        const releaseTarget = releaseTargets[0];
        if (bcmCatalog.actions && bcmCatalog.actions[String(releaseTarget)]) continue;
        if (directions.some(item => item.target_action_id === releaseTarget)
            || neutrals.some(item => item.target_action_id === releaseTarget)) continue;
        releases.push({
            source_action_id: direction.target_action_id,
            source_action_ids: [direction.target_action_id],
            target_action_id: releaseTarget,
            direction_mask: direction.direction_mask,
            direction: direction.direction,
            branch_type: 20,
            param00: 0,
            param01: direction.direction_mask,
            param02: 0,
            param03: 0,
            reason: AC_STATE_RELEASE_REASON
        });
    }

    const type13Grouped = new Map();
    for (const [sourceId, branches] of branchesByAction) {
        if (!branches.some(branch => exactStateBranch(branch, 20, 1, 2))) continue;
        for (const branch of branches.filter(item => exactStateBranch(item, 13, 0, 0))) {
            const targetId = Number(branch.Action), targetBranches = branchesByAction.get(targetId) || [];
            const exits = targetBranches.filter(item => Number(item.Type) === 5 && Number(item.Attr) === 288
                && Number(item.ActionFrame) === 0 && Number(item.Param00) === 1
                && Number(item.Param01) === 0 && Number(item.Param02) === 0
                && Number(item.Param03) === 0 && Number(item.Param04) === 0
                && Number(item.Param05) === 0 && Number(item.TriggerID) === -1);
            if (exits.length !== 1 || bcmCatalog.actions && bcmCatalog.actions[String(targetId)]) continue;
            if (!type13Grouped.has(targetId)) type13Grouped.set(targetId, {
                source_action_id: sourceId,
                source_action_ids: [],
                target_action_id: targetId,
                exit_action_id: Number(exits[0].Action),
                branch_type: 13,
                reason: AC_TYPE13_NEUTRAL_REASON
            });
            type13Grouped.get(targetId).source_action_ids.push(sourceId);
        }
    }
    const type13Neutrals = [...type13Grouped.values()].map(relation => ({ ...relation,
        source_action_ids: [...new Set(relation.source_action_ids)].sort((left, right) => left - right)
    })).sort((left, right) => left.target_action_id - right.target_action_id);

    directions.sort((left, right) => left.target_action_id - right.target_action_id);
    neutrals.sort((left, right) => left.target_action_id - right.target_action_id);
    releases.sort((left, right) => left.target_action_id - right.target_action_id);
    return { directions, neutrals, type13Neutrals, releases };
}

function strictBcmZeroInputTransitions(bcmCatalog, runtime, actionSet) {
    const output = [];
    for (const [id, action] of Object.entries(bcmCatalog.actions || {})) {
        const rule = runtime.validation && runtime.validation.rules && runtime.validation.rules[id];
        if (!actionSet.has(id) || !rule || rule.display !== "Normal"
            || rule.physical_button_required !== false || !(action.triggers || []).length) continue;
        const valid = action.triggers.every(trigger => {
            if (Number(trigger.conditions && trigger.conditions.function_id) !== 2) return false;
            return ["norm", "easy", "sprt", "supr"].every(profileName => {
                const profile = trigger.profiles && trigger.profiles[profileName];
                return !profile || profile.enabled !== true
                    || (String(profile.notation || "") === "Normal"
                        && Number(profile.ok_key_flags || 0) === 0
                        && Number(profile.ok_key_cond_flags || 0) === 0
                        && !profile.command);
            });
        });
        if (!valid) continue;
        output.push({
            action_id: Number(id),
            trigger_indices: action.triggers.map(trigger => Number(trigger.trigger_index))
                .sort((left, right) => left - right),
            function_id: 2,
            reason: BCM_ZERO_INPUT_TRANSITION_REASON
        });
    }
    return output.sort((left, right) => left.action_id - right.action_id);
}

function chargeSelectorSignature(profile) {
    if (!isChargeStateSelector(profile)) return null;
    const command = profile.command;
    return JSON.stringify({
        ok_key_flags: Number(profile.ok_key_flags || 0),
        ok_key_cond_flags: Number(profile.ok_key_cond_flags || 0),
        dc_exc_flags: Number(profile.dc_exc_flags || 0),
        ng_key_flags: Number(profile.ng_key_flags || 0),
        command_no: Number(profile.command_no),
        command_index: Number(profile.command_index),
        command_notation: String(command.notation || ""),
        charge_bit: Number(command.charge_bit || 0),
        inputs: (command.inputs || []).map(input => ({
            direction: String(input && input.direction || ""),
            raw_mask: Number(input && input.raw_mask || 0),
            type: Number(input && input.type || 0),
            charge_id: Number(input && input.charge_id || 0),
            charge_release: input && input.charge_release === true
        }))
    });
}

function acChargeContextEvidence(actionSource, bcmCatalog, actionSet) {
    const { objects, actions } = characterActionGraph(actionSource, actionSet);
    const groups = new Map();
    for (const [actionId, root] of actions) {
        const fingerprint = actionFullStructure(root, objects);
        if (!fingerprint) continue;
        if (!groups.has(fingerprint)) groups.set(fingerprint, []);
        groups.get(fingerprint).push(actionId);
    }
    const contexts = new Map(), relations = [];
    for (const [targetIdText, targetAction] of Object.entries(bcmCatalog.actions || {})) {
        const targetId = Number(targetIdText);
        if (!actionSet.has(String(targetId))) continue;
        const fingerprint = actionFullStructure(actions.get(targetId), objects);
        const peers = fingerprint && groups.get(fingerprint) || [];
        if (peers.length < 2) continue;
        for (const targetTrigger of targetAction.triggers || []) {
            if (chargeContextFromProfiles(targetTrigger.profiles)) continue;
            for (const profileName of ["easy", "supr"]) {
                const targetProfile = targetTrigger.profiles && targetTrigger.profiles[profileName];
                const selector = chargeSelectorSignature(targetProfile);
                if (!selector) continue;
                const candidates = [];
                for (const sourceId of peers) {
                    if (sourceId === targetId) continue;
                    const sourceAction = bcmCatalog.actions && bcmCatalog.actions[String(sourceId)];
                    for (const sourceTrigger of sourceAction && sourceAction.triggers || []) {
                        if (triggerConditionSignature(sourceTrigger.conditions)
                            !== triggerConditionSignature(targetTrigger.conditions)) continue;
                        const sourceProfile = sourceTrigger.profiles && sourceTrigger.profiles[profileName];
                        if (chargeSelectorSignature(sourceProfile) !== selector) continue;
                        const context = chargeContextFromProfiles(sourceTrigger.profiles);
                        if (context) candidates.push({ sourceId, sourceTrigger, context });
                    }
                }
                const grouped = new Map();
                for (const candidate of candidates) {
                    const key = `${candidate.sourceId}:${candidate.context.profile}:${candidate.context.direction}`;
                    if (!grouped.has(key)) grouped.set(key, { ...candidate,
                        triggerIndices: [] });
                    grouped.get(key).triggerIndices.push(Number(candidate.sourceTrigger.trigger_index));
                }
                if (grouped.size !== 1) continue;
                const candidate = [...grouped.values()][0];
                candidate.triggerIndices.sort((left, right) => left - right);
                const relation = {
                    source_action_id: Number(candidate.sourceId),
                    target_action_id: targetId,
                    source_trigger_indices: candidate.triggerIndices,
                    target_trigger_index: Number(targetTrigger.trigger_index),
                    profile: profileName,
                    direction: candidate.context.direction,
                    source_charge_profile: candidate.context.profile,
                    source_charge_command_no: candidate.context.command_no,
                    source_charge_command_index: candidate.context.command_index,
                    source_charge_notation: candidate.context.notation,
                    fingerprint_fields: [...AC_FULL_STRUCTURE_FIELDS],
                    reason: AC_CHARGE_CONTEXT_REASON
                };
                contexts.set(`${targetId}:${targetTrigger.trigger_index}:${profileName}`, {
                    ...candidate.context,
                    source_action_id: Number(candidate.sourceId),
                    source_trigger_indices: candidate.triggerIndices,
                    relation: "ac_full_structure_peer",
                    reason: AC_CHARGE_CONTEXT_REASON
                });
                relations.push(relation);
            }
        }
    }
    relations.sort((left, right) => left.target_action_id - right.target_action_id
        || left.target_trigger_index - right.target_trigger_index
        || left.profile.localeCompare(right.profile));
    return { contexts, relations };
}

function referencedObject(root, fieldName, objects) {
    const field = root && (root.fields || []).find(item => item.name === fieldName);
    return field && field.value && field.value.kind === "ref"
        ? objects.get(field.value.object_id) : null;
}

function actionLoopCount(root, objects) {
    return numericField(fieldsOf(referencedObject(root, "State", objects)), "LoopCount");
}

function strictType20HoldRelations(actionSource, actionSet) {
    const { objects, actions } = characterActionGraph(actionSource, actionSet);
    const relations = [], seen = new Set();
    const allowedMasks = new Set([16, 32, 64, 112, 128, 256, 512, 896]);
    for (const [sourceId, root] of actions) {
        if (actionLoopCount(root, objects) !== 0) continue;
        const keys = referencedObject(root, "Keys", objects);
        const pending = keys ? [keys.object_id] : [];
        const visited = new Set();
        while (pending.length) {
            const objectId = pending.pop();
            if (visited.has(objectId)) continue;
            visited.add(objectId);
            const object = objects.get(objectId);
            if (!object) continue;
            if (object.object_type === "CharacterAsset.BranchKey") {
                const fields = fieldsOf(object);
                const targetId = numericField(fields, "Action");
                const branchType = numericField(fields, "Type");
                const param00 = numericField(fields, "Param00");
                const param01 = numericField(fields, "Param01");
                const param02 = numericField(fields, "Param02");
                const param03 = numericField(fields, "Param03");
                const target = actions.get(targetId);
                const key = `${sourceId}:${targetId}`;
                if (branchType === 20 && targetId !== sourceId && target
                    && param00 === 1 && allowedMasks.has(param01)
                    && param02 === 0 && param03 === 1
                    && actionLoopCount(target, objects) === -1 && !seen.has(key)) {
                    seen.add(key);
                    relations.push({ source_action_id: sourceId, target_action_id: targetId,
                        branch_type: 20, param00, param01, param02, param03,
                        source_loop_count: 0, target_loop_count: -1 });
                }
            }
            for (const field of object.fields || []) {
                if (field.value && field.value.kind === "ref") pending.push(field.value.object_id);
            }
            for (const item of object.items || []) {
                if (item.value && item.value.kind === "ref") pending.push(item.value.object_id);
            }
        }
    }
    return relations.sort((left, right) => left.source_action_id - right.source_action_id
        || left.target_action_id - right.target_action_id);
}

function strictType20ActionPhaseRelations(actionSource, actionSet) {
    const { objects, actions } = characterActionGraph(actionSource, actionSet);
    const grouped = new Map();
    for (const [sourceId, root] of actions) {
        const keys = referencedObject(root, "Keys", objects);
        const pending = keys ? [keys.object_id] : [];
        const visited = new Set();
        while (pending.length) {
            const objectId = pending.pop();
            if (visited.has(objectId)) continue;
            visited.add(objectId);
            const object = objects.get(objectId);
            if (!object) continue;
            if (object.object_type === "CharacterAsset.BranchKey") {
                const fields = fieldsOf(object);
                const targetId = numericField(fields, "Action");
                const relation = {
                    param00: numericField(fields, "Param00"),
                    param01: numericField(fields, "Param01"),
                    param02: numericField(fields, "Param02"),
                    param03: numericField(fields, "Param03")
                };
                if (numericField(fields, "Type") === 20 && targetId !== sourceId && actions.has(targetId)
                    && numericField(fields, "Attr") === 288
                    && numericField(fields, "ActionFrame") === 0
                    && relation.param02 === 0
                    && numericField(fields, "Param04") === 0
                    && numericField(fields, "Param05") === 0
                    && numericField(fields, "TriggerID") === -1) {
                    const key = `${sourceId}:${targetId}`;
                    if (!grouped.has(key)) grouped.set(key, { source_action_id: sourceId,
                        target_action_id: targetId, signatures: [] });
                    grouped.get(key).signatures.push(relation);
                }
            }
            for (const field of object.fields || []) {
                if (field.value && field.value.kind === "ref") pending.push(field.value.object_id);
            }
            for (const item of object.items || []) {
                if (item.value && item.value.kind === "ref") pending.push(item.value.object_id);
            }
        }
    }
    const expected = new Set(["0:8:0:1", "0:32:0:2", "0:8192:0:3", "1:8192:0:3"]);
    const output = [];
    for (const relation of grouped.values()) {
        const signatures = new Set(relation.signatures.map(item =>
            `${item.param00}:${item.param01}:${item.param02}:${item.param03}`));
        if (signatures.size !== expected.size || [...expected].some(item => !signatures.has(item))) continue;
        relation.signatures.sort((left, right) => left.param03 - right.param03
            || left.param01 - right.param01 || left.param00 - right.param00);
        output.push({ ...relation, branch_type: 20 });
    }
    return output.sort((left, right) => left.source_action_id - right.source_action_id
        || left.target_action_id - right.target_action_id);
}

function automaticHoldTransitionType29Targets(actionSource, actionSet) {
    const { objects, actions } = characterActionGraph(actionSource, actionSet);
    const holdTargets = new Set(strictType20HoldRelations(actionSource, actionSet)
        .map(relation => Number(relation.target_action_id)));
    const incoming = new Map();
    for (const [sourceId, root] of actions) {
        const keys = referencedObject(root, "Keys", objects);
        const pending = keys ? [keys.object_id] : [];
        const visited = new Set();
        while (pending.length) {
            const objectId = pending.pop();
            if (visited.has(objectId)) continue;
            visited.add(objectId);
            const object = objects.get(objectId);
            if (!object) continue;
            if (object.object_type === "CharacterAsset.BranchKey") {
                const fields = fieldsOf(object);
                const targetId = numericField(fields, "Action");
                if (numericField(fields, "Type") === 29 && targetId !== sourceId
                    && actions.has(targetId)) {
                    if (!incoming.has(targetId)) incoming.set(targetId, new Set());
                    incoming.get(targetId).add(sourceId);
                }
            }
            for (const field of object.fields || []) {
                if (field.value && field.value.kind === "ref") pending.push(field.value.object_id);
            }
            for (const item of object.items || []) {
                if (item.value && item.value.kind === "ref") pending.push(item.value.object_id);
            }
        }
    }
    return new Map([...incoming].filter(([, sources]) => sources.size > 1
            && [...sources].some(sourceId => holdTargets.has(sourceId)))
        .map(([targetId, sources]) => [targetId, [...sources].sort((left, right) => left - right)]));
}

function stablePlainValue(value) {
    if (Array.isArray(value)) return value.map(stablePlainValue);
    if (!value || typeof value !== "object") return value;
    const output = {};
    for (const key of Object.keys(value).sort()) output[key] = stablePlainValue(value[key]);
    return output;
}

function triggerConditionSignature(conditions) {
    const filtered = {};
    for (const key of Object.keys(conditions || {}).sort()) {
        if (key !== "use_super") filtered[key] = stablePlainValue(conditions[key]);
    }
    return JSON.stringify(filtered);
}

function triggerHasModernProfile(trigger) {
    return MODERN_PROFILE_ORDER.some(name => trigger && trigger.profiles
        && trigger.profiles[name] && trigger.profiles[name].enabled === true);
}

function triggerHasAnyProfile(trigger) {
    return ["norm", ...MODERN_PROFILE_ORDER].some(name => trigger && trigger.profiles
        && trigger.profiles[name] && trigger.profiles[name].enabled === true);
}

function structuralTwinEvidence(actionSource, bcmCatalog, actionSet, entries) {
    const { objects, actions } = characterActionGraph(actionSource, actionSet);
    const fingerprintGroups = new Map();
    for (const [actionId, root] of actions) {
        const fingerprint = actionFullStructure(root, objects);
        if (!fingerprint) continue;
        if (!fingerprintGroups.has(fingerprint)) fingerprintGroups.set(fingerprint, []);
        fingerprintGroups.get(fingerprint).push(actionId);
    }
    const relations = [];
    for (const [targetIdText, targetAction] of Object.entries(bcmCatalog.actions || {})) {
        const targetId = Number(targetIdText);
        if (!actionSet.has(String(targetId)) || entries[String(targetId)]) continue;
        const fingerprint = actionFullStructure(actions.get(targetId), objects);
        const peers = fingerprint && fingerprintGroups.get(fingerprint) || [];
        if (peers.length < 2) continue;
        for (const targetTrigger of targetAction.triggers || []) {
            if (triggerHasAnyProfile(targetTrigger)
                || targetTrigger.conditions && targetTrigger.conditions.use_super !== false) continue;
            const signature = triggerConditionSignature(targetTrigger.conditions);
            const candidates = [];
            for (const sourceId of peers) {
                if (sourceId === targetId) continue;
                const sourceEntry = entries[String(sourceId)];
                const sourceAction = bcmCatalog.actions && bcmCatalog.actions[String(sourceId)];
                if (!sourceEntry || sourceEntry.ownership !== "direct" || !sourceAction) continue;
                for (const sourceTrigger of sourceAction.triggers || []) {
                    if (!triggerHasModernProfile(sourceTrigger)
                        || !(sourceTrigger.conditions && sourceTrigger.conditions.use_super === true)
                        || triggerConditionSignature(sourceTrigger.conditions) !== signature) continue;
                    const routes = sourceEntry.routes.filter(route => route.direct_evidence === true
                        && Number(route.trigger_index) === Number(sourceTrigger.trigger_index));
                    if (routes.length) candidates.push({ sourceId, sourceTrigger, routes });
                }
            }
            if (candidates.length !== 1) continue;
            const candidate = candidates[0];
            relations.push({
                source_action_id: candidate.sourceId,
                target_action_id: targetId,
                source_trigger_index: Number(candidate.sourceTrigger.trigger_index),
                target_trigger_index: Number(targetTrigger.trigger_index),
                ignored_condition_delta: "use_super:true->false",
                fingerprint_fields: [...AC_FULL_STRUCTURE_FIELDS],
                reason: STRUCTURAL_TWIN_REASON,
                routes: candidate.routes
            });
        }
    }
    relations.sort((left, right) => left.target_action_id - right.target_action_id
        || left.source_action_id - right.source_action_id);
    return relations;
}

function branchKeys(root, objects) {
    const keys = fieldsOf(root).get("Keys");
    const pending = keys && keys.value && keys.value.kind === "ref" ? [keys.value.object_id] : [];
    const visited = new Set(), branches = [];
    while (pending.length) {
        const objectId = pending.pop();
        if (visited.has(objectId)) continue;
        visited.add(objectId);
        const object = objects.get(objectId);
        if (!object) continue;
        if (object.object_type === "CharacterAsset.BranchKey") branches.push(fieldsOf(object));
        for (const field of object.fields || []) {
            if (field.value && field.value.kind === "ref") pending.push(field.value.object_id);
        }
        for (const item of object.items || []) {
            if (item.value && item.value.kind === "ref") pending.push(item.value.object_id);
        }
    }
    return branches;
}

function completeBranch(fields) {
    const names = ["Action", "Type", "Attr", "ActionFrame", "Param00", "Param01",
        "Param02", "Param03", "Param04", "Param05", "TriggerID"];
    const values = {};
    for (const name of names) {
        const value = numericField(fields, name);
        if (value === null) return null;
        values[name] = value;
    }
    return values;
}

function exactRebindBranch(branch) {
    return branch && branch.Type === 17 && branch.Attr === 0 && branch.ActionFrame === 0
        && branch.Param00 === 9 && branch.Param01 === 120
        && branch.Param02 === 0 && branch.Param03 === 0 && branch.Param04 === 0
        && branch.Param05 === 0 && branch.TriggerID === -1;
}

function internalStageBranch(branch) {
    return branch && branch.Type === 17 && branch.Attr === 0
        && branch.Param00 === 10 && branch.Param01 === 240
        && branch.Param02 === 0 && branch.Param03 === 0 && branch.Param04 === 0
        && branch.Param05 === 0 && branch.TriggerID === -1;
}

function acRebindEvidence(actionSource, actionSet) {
    const objects = new Map((actionSource.objects || []).map(object => [object.object_id, object]));
    const actions = new Map();
    for (const record of actionSource.records || []) {
        const actionId = Number(record && record.native_action_id);
        const ref = record && record.action_ref;
        if (record && record.source_scope === "character" && actionSet.has(String(actionId))
            && ref && ref.kind === "ref" && !actions.has(actionId)) {
            const root = objects.get(ref.object_id);
            if (root) actions.set(actionId, root);
        }
    }

    const branchCache = new Map();
    const branchesFor = actionId => {
        if (!branchCache.has(actionId)) {
            branchCache.set(actionId, branchKeys(actions.get(actionId), objects));
        }
        return branchCache.get(actionId);
    };
    const type17Relations = new Map();
    const signatureCandidates = [];
    for (const [sourceId, sourceRoot] of actions) {
        const rawBranches = branchesFor(sourceId);
        const rawType17 = rawBranches.filter(branch => numericField(branch, "Type") === 17);
        for (const fields of rawType17) {
            const branch = completeBranch(fields);
            if (!branch) continue;
            type17Relations.set([sourceId, branch.Action, branch.Type, branch.Attr, branch.ActionFrame,
                branch.Param00, branch.Param01, branch.Param02, branch.Param03, branch.Param04,
                branch.Param05, branch.TriggerID].join(":"), branch);
        }
        if (rawType17.length !== 1
            || rawBranches.filter(branch => numericField(branch, "Type") === 36).length !== 2) continue;
        const relation = completeBranch(rawType17[0]);
        if (!relation) continue;
        const targetId = relation.Action;
        if (!exactRebindBranch(relation) || targetId === sourceId || !actionSet.has(String(targetId))) continue;
        const targetRoot = actions.get(targetId);
        const sourceFrame = numericField(fieldsOf(sourceRoot), "Frame");
        const targetFrame = numericField(fieldsOf(targetRoot), "Frame");
        const sourceCategory = actionStructureCategory(sourceRoot, objects);
        const targetCategory = actionStructureCategory(targetRoot, objects);
        if (sourceFrame === null || targetFrame === null || targetFrame <= sourceFrame
            || sourceCategory === null || targetCategory === null || sourceCategory !== targetCategory) continue;
        const targetStages = branchesFor(targetId).map(completeBranch).filter(internalStageBranch);
        if (!targetStages.some(branch => branch.Action === targetId && branch.ActionFrame > 0)
            || !targetStages.some(branch => branch.Action !== targetId && actionSet.has(String(branch.Action)))) continue;
        signatureCandidates.push({
            source_action_id: sourceId,
            target_action_id: targetId,
            source_frame: sourceFrame,
            target_frame: targetFrame,
            ac_attr: relation.Attr,
            ac_frame: relation.ActionFrame,
            ac_param00: relation.Param00,
            ac_param01: relation.Param01,
            ac_param02: relation.Param02,
            ac_param03: relation.Param03,
            ac_param04: relation.Param04,
            ac_param05: relation.Param05,
            ac_trigger_id: relation.TriggerID
        });
    }
    const sourceCounts = new Map(), targetCounts = new Map();
    signatureCandidates.sort((left, right) => left.source_action_id - right.source_action_id
        || left.target_action_id - right.target_action_id);
    for (const relation of signatureCandidates) {
        sourceCounts.set(relation.source_action_id, (sourceCounts.get(relation.source_action_id) || 0) + 1);
        targetCounts.set(relation.target_action_id, (targetCounts.get(relation.target_action_id) || 0) + 1);
    }
    return {
        type17_relation_count: type17Relations.size,
        signature_candidate_count: signatureCandidates.length,
        relations: signatureCandidates.filter(relation => sourceCounts.get(relation.source_action_id) === 1
            && targetCounts.get(relation.target_action_id) === 1)
    };
}

function rebindRoute(relation, provenance, display, visibleButton) {
    const sourceId = relation.source_action_id, targetId = relation.target_action_id;
    const route = {
        ...provenance,
        display: normalizeDisplay(display),
        visible_button: visibleButton === undefined ? provenance.visible_button : visibleButton,
        display_action_id: targetId,
        bcm_owner_action_id: sourceId,
        source: "ac_command_entry_rebind",
        ac_relation_type: 17,
        ac_attr: relation.ac_attr,
        ac_frame: relation.ac_frame,
        ac_param00: relation.ac_param00,
        ac_param01: relation.ac_param01,
        ac_param02: relation.ac_param02,
        ac_param03: relation.ac_param03,
        ac_param04: relation.ac_param04,
        ac_param05: relation.ac_param05,
        ac_trigger_id: relation.ac_trigger_id,
        ac_path: [sourceId, targetId],
        inherited_from_action_id: null,
        confidence: "verified_rebind",
        direct_evidence: false,
        inheritance_evidence: false,
        inheritance_reason: null,
        rebind_evidence: true,
        rebind_reason: REBIND_REASON
    };
    assertValidDisplay(route.display);
    return route;
}

const REQUIRED_ROUTE_FIELDS = [
    "character", "owner_action_id", "trigger_index", "profile", "command_no", "command_index",
    "raw_direction_inputs", "raw_button_mask", "raw_button_condition", "raw_dc_exc_flags", "raw_ng_key_flags",
    "visible_direction", "visible_button", "button_candidates", "required_button_count", "source",
    "ac_relation_type", "ac_path", "inherited_from_action_id", "confidence", "direct_evidence",
    "inheritance_evidence", "inheritance_reason", "rebind_evidence", "rebind_reason",
    "runtime_common_evidence", "runtime_common_reason",
    "official_semantic_evidence", "official_semantic_reason",
    "community_semantic_evidence", "community_semantic_reason"
    , "assist_combo_evidence", "assist_combo_reason"
];
const REQUIRED_REBIND_FIELDS = [
    "display_action_id", "bcm_owner_action_id", "ac_attr", "ac_frame", "ac_param00",
    "ac_param01", "ac_param02", "ac_param03", "ac_param04", "ac_param05", "ac_trigger_id"
];

function assertRoute(route) {
    assertValidDisplay(route.display);
    for (const field of REQUIRED_ROUTE_FIELDS) {
        if (!Object.prototype.hasOwnProperty.call(route, field)) throw new Error(`Modern route 缺少 provenance: ${field}`);
    }
    if (!Number.isFinite(route.owner_action_id) || !Array.isArray(route.raw_direction_inputs)
        || !Array.isArray(route.button_candidates) || !Array.isArray(route.ac_path)) {
        throw new Error(`Modern route provenance 非法: ${route.display}`);
    }
    const evidenceCount = [route.direct_evidence, route.inheritance_evidence, route.rebind_evidence,
        route.runtime_common_evidence, route.official_semantic_evidence, route.community_semantic_evidence]
        .filter(value => value === true).length;
    if (evidenceCount !== 1) {
        throw new Error(`Modern route evidence 必须明确 direct、inherited、rebind、runtime-common、official-semantic 或 community-semantic 六选一: ${route.display}`);
    }
    if (route.charge_context_evidence === true) {
        const direction = String(route.charge_context_direction || "");
        const manualDirection = String(route.charge_context_manual_direction || "");
        const sourceActionId = Number(route.charge_context_source_action_id);
        const sourceTriggers = route.charge_context_source_trigger_indices;
        const localContext = route.charge_context_relation === "same_trigger_bcm";
        const inheritedContext = route.charge_context_relation === "ac_full_structure_peer";
        if (!["sprt", "norm"].includes(route.charge_context_profile)
            || !["1", "2", "4", "6", "7", "8", "9"].includes(direction)
            || !["1", "2", "4", "6", "7", "8", "9"].includes(manualDirection)
            || !["sprt", "norm", "supr"].includes(route.charge_context_direction_profile)
            || !Number.isFinite(Number(route.charge_context_command_no))
            || Number(route.charge_context_command_no) < 0
            || !Number.isFinite(Number(route.charge_context_command_index))
            || Number(route.charge_context_command_index) < 0
            || typeof route.charge_context_notation !== "string"
            || !route.charge_context_notation.includes(`[${manualDirection}]`)
            || !Number.isFinite(sourceActionId)
            || !Array.isArray(sourceTriggers) || sourceTriggers.length === 0
            || sourceTriggers.some(value => !Number.isFinite(Number(value)))
            || (localContext && (sourceActionId !== Number(route.owner_action_id)
                || route.charge_context_reason !== CHARGE_CONTEXT_REASON))
            || (inheritedContext && (sourceActionId === Number(route.owner_action_id)
                || route.charge_context_reason !== AC_CHARGE_CONTEXT_REASON))
            || (!localContext && !inheritedContext)
            || !String(route.display).includes(`[${direction}]`)) {
            throw new Error(`Modern charge-context route 证据非法: ${route.display}`);
        }
    } else if ([route.charge_context_profile, route.charge_context_direction,
        route.charge_context_manual_direction, route.charge_context_direction_profile,
        route.charge_context_command_no, route.charge_context_command_index,
        route.charge_context_notation, route.charge_context_source_action_id,
        route.charge_context_relation, route.charge_context_reason]
        .some(value => value !== null && value !== undefined)) {
        throw new Error(`非 charge-context route 不得携带蓄力上下文: ${route.display}`);
    } else if (Array.isArray(route.charge_context_source_trigger_indices)
        && route.charge_context_source_trigger_indices.length !== 0) {
        throw new Error(`非 charge-context route 不得携带蓄力 trigger: ${route.display}`);
    }
    if (route.super_shortcut_direction_evidence === true) {
        if (route.super_shortcut_direction_profile !== "supr"
            || !["1", "2", "4", "6", "7", "8", "9"].includes(
                String(route.super_shortcut_direction || ""))
            || typeof route.super_shortcut_direction_notation !== "string"
            || route.super_shortcut_direction_reason !== SUPER_SHORTCUT_DIRECTION_REASON) {
            throw new Error(`Modern super shortcut direction 证据非法: ${route.display}`);
        }
    } else if ([route.super_shortcut_direction_profile, route.super_shortcut_direction,
        route.super_shortcut_direction_notation, route.super_shortcut_direction_reason]
        .some(value => value !== null && value !== undefined)) {
        throw new Error(`非 super shortcut route 不得携带方向证据: ${route.display}`);
    }
    if (route.rebind_evidence === true) {
        for (const field of REQUIRED_REBIND_FIELDS) {
            if (!Object.prototype.hasOwnProperty.call(route, field)) {
                throw new Error(`Modern rebind route 缺少证据: ${field}`);
            }
        }
        if (route.source !== "ac_command_entry_rebind"
            || route.confidence !== "verified_rebind"
            || route.rebind_reason !== REBIND_REASON
            || route.inheritance_reason !== null
            || route.ac_relation_type !== 17
            || route.ac_attr !== 0 || route.ac_frame !== 0
            || route.ac_param00 !== 9 || route.ac_param01 !== 120
            || route.ac_param02 !== 0 || route.ac_param03 !== 0
            || route.ac_param04 !== 0 || route.ac_param05 !== 0 || route.ac_trigger_id !== -1
            || route.display_action_id === route.bcm_owner_action_id
            || route.owner_action_id !== route.bcm_owner_action_id
            || route.ac_path.length !== 2 || route.ac_path[0] !== route.bcm_owner_action_id
            || route.ac_path[1] !== route.display_action_id) {
            throw new Error(`Modern rebind route 证据非法: ${route.display}`);
        }
    } else if (route.rebind_reason !== null) {
        throw new Error(`非 rebind route 不得携带 rebind_reason: ${route.display}`);
    }
    if (route.runtime_common_evidence === true) {
        const expected = RUNTIME_COMMON_ACTIONS[String(route.owner_action_id)];
        if (route.source !== "runtime_common_action" || route.confidence !== "verified_runtime_common"
            || route.runtime_common_reason !== RUNTIME_COMMON_REASON || expected !== route.display
            || route.display_action_id !== route.owner_action_id || route.bcm_owner_action_id !== null
            || route.direct_evidence !== false || route.inheritance_evidence !== false
            || route.rebind_evidence !== false || route.ac_relation_type !== null
            || route.ac_path.length !== 0 || route.inherited_from_action_id !== null) {
            throw new Error(`Modern runtime-common route 证据非法: ${route.display}`);
        }
    } else if (route.runtime_common_reason !== null) {
        throw new Error(`非 runtime-common route 不得携带 runtime_common_reason: ${route.display}`);
    }
    if (route.official_semantic_evidence === true) {
        if (route.source !== "official_semantic_bcm_rebind"
            || route.confidence !== "verified_official_semantic_bcm_identity"
            || route.official_semantic_reason !== OFFICIAL_SEMANTIC_REASON
            || route.direct_evidence !== false || route.inheritance_evidence !== false
            || route.rebind_evidence !== false || route.runtime_common_evidence !== false
            || route.ac_relation_type !== null || route.ac_path.length !== 0
            || route.inherited_from_action_id !== null
            || route.display_action_id !== route.owner_action_id
            || route.bcm_owner_action_id !== route.owner_action_id
            || !Number.isFinite(route.official_action_id_hint)
            || !Number.isFinite(route.official_action_id_distance)
            || route.official_action_id_distance < 0
            || !["capcom_action_id", "derived_current_bcm_identity"].includes(route.official_action_id_hint_kind)
            || (route.official_action_id_hint_kind === "derived_current_bcm_identity"
                && (typeof route.official_semantic_row_id !== "string" || route.official_semantic_row_id === ""))
            || (route.official_action_id_hint_kind === "capcom_action_id"
                && route.official_semantic_row_id !== null)
            || typeof route.official_classic_display !== "string"
            || typeof route.official_modern_display !== "string") {
            throw new Error(`Modern official-semantic route 证据非法: ${route.display}`);
        }
    } else if (route.official_semantic_reason !== null) {
        throw new Error(`非 official-semantic route 不得携带 official_semantic_reason: ${route.display}`);
    }
    if (route.community_semantic_evidence === true) {
        if (route.source !== "community_semantic_bcm_rebind"
            || route.confidence !== "verified_community_semantic_bcm_identity"
            || route.community_semantic_reason !== COMMUNITY_SEMANTIC_REASON
            || route.direct_evidence !== false || route.inheritance_evidence !== false
            || route.rebind_evidence !== false || route.runtime_common_evidence !== false
            || route.official_semantic_evidence !== false
            || route.ac_relation_type !== null || route.ac_path.length !== 0
            || route.inherited_from_action_id !== null
            || route.display_action_id !== route.owner_action_id
            || route.bcm_owner_action_id !== route.owner_action_id
            || !Number.isFinite(route.community_action_id_hint)
            || !Number.isFinite(route.community_action_id_distance)
            || route.community_action_id_distance < 0
            || typeof route.community_classic_display !== "string"
            || typeof route.community_modern_display !== "string"
            || typeof route.community_evidence_id !== "string"
            || route.community_evidence_id === "") {
            throw new Error(`Modern community-semantic route 证据非法: ${route.display}`);
        }
    } else if (route.community_semantic_reason !== null) {
        throw new Error(`非 community-semantic route 不得携带 community_semantic_reason: ${route.display}`);
    }
    if (route.assist_combo_evidence === true) {
        if (route.source !== "bcm_assist_combo_recipe"
            || route.confidence !== "direct_assist_combo_recipe"
            || route.assist_combo_reason !== ASSIST_COMBO_REASON
            || route.direct_evidence !== true || route.inheritance_evidence !== false
            || route.rebind_evidence !== false || route.runtime_common_evidence !== false
            || route.official_semantic_evidence !== false || route.community_semantic_evidence !== false
            || route.ac_relation_type !== null || route.ac_path.length !== 0
            || route.inherited_from_action_id !== null
            || route.display_action_id !== route.owner_action_id
            || route.bcm_owner_action_id !== route.owner_action_id
            || route.profile !== "assist_combo" || route.command_no !== -1
            || route.command_index !== -1 || route.trigger_index < 0
            || route.raw_direction_inputs.length !== 0 || route.raw_button_mask !== 0
            || route.raw_button_condition !== 0 || route.raw_dc_exc_flags !== 0
            || route.raw_ng_key_flags !== 0
            || !["弱", "中", "强"].includes(route.assist_strength)
            || !["first", "repeat"].includes(route.assist_input_stage)
            || route.display !== (route.assist_input_stage === "first"
                ? `AUTO + ${route.assist_strength}` : `> ${route.assist_strength}`)
            || !Array.isArray(route.assist_recipe_occurrences)
            || route.assist_recipe_occurrences.length === 0
            || route.assist_recipe_occurrences.some(item =>
                !Number.isInteger(item.array_index) || !Number.isInteger(item.trigger_id)
                || item.trigger_id < 0)) {
            throw new Error(`Modern assist-combo route 证据非法: ${route.display}`);
        }
    } else if (route.assist_combo_reason !== null) {
        throw new Error(`非 assist-combo route 不得携带 assist_combo_reason: ${route.display}`);
    }
    if (route.source === "ac_verified_alias_variant") {
        if (route.inheritance_evidence !== true || route.inheritance_reason !== VERIFIED_ALIAS_REASON
            || route.confidence !== "verified_inherited_alias"
            || ![29, 35].includes(Number(route.ac_relation_type))
            || route.ac_path.length < 2
            || Number(route.ac_path[route.ac_path.length - 1]) !== Number(route.display_action_id)
            || Number(route.inherited_from_action_id) !== Number(route.ac_path[route.ac_path.length - 2])) {
            throw new Error(`Modern verified alias route 证据非法: ${route.display}`);
        }
    }
    if (route.source === "ac_type20_directional_air_attack") {
        if (route.inheritance_evidence !== true || route.inheritance_reason !== TYPE20_DIRECTION_REASON
            || route.confidence !== "verified_inherited_directional_attack"
            || Number(route.ac_relation_type) !== 20 || route.ac_path.length < 2
            || Number(route.ac_path[route.ac_path.length - 1]) !== Number(route.display_action_id)
            || Number(route.inherited_from_action_id) !== Number(route.ac_path[route.ac_path.length - 2])
            || !/^空中 [469] \+ (弱|中|强)$/.test(route.display)) {
            throw new Error(`Modern Type20 directional route 证据非法: ${route.display}`);
        }
    }
    if (route.source === "ac_type20_hold_continuation") {
        if (route.inheritance_evidence !== true || route.inheritance_reason !== TYPE20_HOLD_REASON
            || route.confidence !== "verified_inherited_hold_continuation"
            || Number(route.ac_relation_type) !== 20 || route.ac_path.length < 2
            || Number(route.ac_path[route.ac_path.length - 1]) !== Number(route.display_action_id)
            || Number(route.inherited_from_action_id) !== Number(route.ac_path[route.ac_path.length - 2])
            || route.ac_param00 !== 1 || route.ac_param02 !== 0 || route.ac_param03 !== 1
            || route.source_loop_count !== 0 || route.target_loop_count !== -1
            || !/^> (弱|中|强|任意键)$/.test(route.display)) {
            throw new Error(`Modern Type20 hold route 证据非法: ${route.display}`);
        }
    }
    if (route.source === "ac_type20_action_phase") {
        const signatures = Array.isArray(route.ac_phase_signatures) ? route.ac_phase_signatures : [];
        const actual = new Set(signatures.map(item =>
            `${item.param00}:${item.param01}:${item.param02}:${item.param03}`));
        const expected = ["0:8:0:1", "0:32:0:2", "0:8192:0:3", "1:8192:0:3"];
        if (route.inheritance_evidence !== true || route.inheritance_reason !== TYPE20_PHASE_REASON
            || route.confidence !== "verified_inherited_action_phase"
            || Number(route.ac_relation_type) !== 20 || route.ac_path.length < 2
            || Number(route.ac_path[route.ac_path.length - 1]) !== Number(route.display_action_id)
            || Number(route.inherited_from_action_id) !== Number(route.ac_path[route.ac_path.length - 2])
            || actual.size !== expected.length || expected.some(item => !actual.has(item))) {
            throw new Error(`Modern Type20 action-phase route 证据非法: ${route.display}`);
        }
    }
    if (["ac_type20_state_direction", "ac_type1_state_neutral",
        "ac_type13_neutral_continuation"].includes(route.source)) {
        const directionRoute = route.source === "ac_type20_state_direction";
        const type1Route = route.source === "ac_type1_state_neutral";
        const expectedType = directionRoute ? 20 : (type1Route ? 1 : 13);
        const expectedReason = directionRoute ? AC_STATE_DIRECTION_REASON
            : (type1Route ? AC_STATE_NEUTRAL_REASON : AC_TYPE13_NEUTRAL_REASON);
        const expectedConfidence = directionRoute ? "verified_ac_state_direction"
            : (type1Route ? "verified_ac_state_neutral" : "verified_ac_type13_neutral");
        if (route.inheritance_evidence !== true || route.inheritance_reason !== expectedReason
            || route.confidence !== expectedConfidence
            || Number(route.ac_relation_type) !== expectedType || route.ac_path.length !== 2
            || Number(route.ac_path[0]) !== Number(route.inherited_from_action_id)
            || Number(route.ac_path[1]) !== Number(route.display_action_id)
            || !Array.isArray(route.state_choice_source_action_ids)
            || route.state_choice_source_action_ids.length === 0
            || !route.state_choice_source_action_ids.includes(Number(route.inherited_from_action_id))
            || (directionRoute && (![1, 2, 4, 8].includes(Number(route.state_choice_direction_mask))
                || !["2", "4", "6", "8"].includes(route.display)))
            || (!directionRoute && route.display !== "N")
            || (route.source === "ac_type13_neutral_continuation"
                && !Number.isFinite(Number(route.state_choice_exit_action_id)))) {
            throw new Error(`Modern AC state-choice route 证据非法: ${route.display}`);
        }
    }
    if (route.source === "bcm_target_combo_repeat") {
        if (route.inheritance_evidence !== true || route.inheritance_reason !== TARGET_COMBO_REPEAT_REASON
            || route.confidence !== "verified_bcm_target_combo_repeat"
            || route.ac_relation_type !== null || route.ac_path.length !== 2
            || Number(route.ac_path[0]) !== Number(route.inherited_from_action_id)
            || Number(route.ac_path[1]) !== Number(route.display_action_id)
            || Number(route.owner_action_id) !== Number(route.display_action_id)
            || Number(route.bcm_owner_action_id) !== Number(route.display_action_id)
            || !/^> (弱|中|强)$/.test(route.display)) {
            throw new Error(`Modern target-combo repeat route 证据非法: ${route.display}`);
        }
    }
    if (route.source === "ac_bcm_structural_twin") {
        if (route.inheritance_evidence !== true || route.inheritance_reason !== STRUCTURAL_TWIN_REASON
            || route.confidence !== "verified_unique_structural_twin"
            || route.ac_relation_type !== null || route.ac_path.length < 2
            || Number(route.ac_path[route.ac_path.length - 1]) !== Number(route.display_action_id)
            || Number(route.inherited_from_action_id) !== Number(route.ac_path[route.ac_path.length - 2])) {
            throw new Error(`Modern structural-twin route 证据非法: ${route.display}`);
        }
    }
}

function buildModernDisplay(actionSource, bcmCatalog, runtime, supplement, options) {
    options = options || {};
    supplement = supplement || {};
    if (Object.keys(supplement).length) throw new Error("Modern supplement/overlay input is disabled by strict policy.");

    const character = String(runtime.character || bcmCatalog.source && bcmCatalog.source.character || "Unknown");
    const actionSet = new Set((runtime.action_ids || []).map(value => String(Number(value))));
    const entries = {};
    const unresolvedCandidates = [];
    const runtimeCommonActions = [];
    const suppressedChargeCompatibilityTriggers = [];
    const acChargePlan = acChargeContextEvidence(actionSource, bcmCatalog, actionSet);
    const stateChoicePlan = strictStateChoiceEvidence(actionSource, bcmCatalog, actionSet);
    const zeroInputTransitions = strictBcmZeroInputTransitions(bcmCatalog, runtime, actionSet);

    for (const [id, action] of Object.entries(bcmCatalog.actions || {})) {
        if (!actionSet.has(id)) continue;
        const routes = [], seen = new Set();
        const rule = runtime.validation && runtime.validation.rules && runtime.validation.rules[id] || null;
        const chargeSuppressions = chargeCompatibilitySuppressions(action);
        const suppressedTriggerIndices = new Set(chargeSuppressions.map(item =>
            item.suppressed_trigger_index));
        for (const relation of chargeSuppressions) {
            suppressedChargeCompatibilityTriggers.push({ action_id: Number(id), ...relation });
        }
        const triggers = (action.triggers || []).filter(trigger =>
            !suppressedTriggerIndices.has(Number(trigger.trigger_index)));
        const commonRoutes = triggers.map(trigger => ({ trigger, common: commonSemantic(trigger, rule) }))
            .filter(item => item.common);
        if (commonRoutes.length) {
            for (const { trigger, common } of commonRoutes) {
                const profile = common.profile && trigger.profiles && trigger.profiles[common.profile] || null;
                const detail = commonDetail(common);
                pushRoute(routes, seen, common.display,
                    routeProvenance(character, id, trigger, common.profile, profile, detail, common.source));
            }
        } else {
            for (const trigger of triggers) {
                for (const profileName of selectedProfilesForAction(
                    id, trigger, options.officialSemantics)) {
                    const profile = trigger.profiles && trigger.profiles[profileName];
                    const inheritedChargeContext = acChargePlan.contexts.get(
                        `${Number(id)}:${Number(trigger.trigger_index)}:${profileName}`);
                    const detail = translateProfileDetailed(
                        profileName, profile, trigger.conditions, trigger.profiles,
                        inheritedChargeContext);
                    const provenance = routeProvenance(
                        character, id, trigger, profileName, profile, detail, "bcm_profile");
                    if (!detail.display) {
                        unresolvedCandidates.push({ action_id: Number(id), ...provenance,
                            reason: detail.unresolved_reason });
                        continue;
                    }
                    const followup = Number(trigger.conditions && trigger.conditions.turn_around) === 2;
                    const display = followup && !detail.display.startsWith(">")
                        ? `> ${detail.display}` : detail.display;
                    pushRoute(routes, seen, display, provenance);
                }
            }
        }
        if (routes.length) entries[id] = { routes, ownership: "direct" };
    }

    for (const [id, display] of Object.entries(RUNTIME_COMMON_ACTIONS)) {
        if (!actionSet.has(id) || entries[id]) continue;
        const route = runtimeCommonRoute(character, Number(id), display);
        assertRoute(route);
        entries[id] = { routes: [route], ownership: "runtime_common" };
        runtimeCommonActions.push({ action_id: Number(id), display, reason: RUNTIME_COMMON_REASON });
    }

    const officialResult = bindOfficialSemantics(options.officialSemantics, bcmCatalog, actionSet);
    const officialBindings = [], officialSeen = new Set();
    let officialQualifiedDirectRouteCount = 0;
    for (const binding of officialResult.bindings) {
        const id = String(binding.target_action_id);
        const key = `${id}:${binding.semantic.display}`;
        if (officialSeen.has(key)) continue;
        officialSeen.add(key);
        const route = officialSemanticRoute(character, binding.target_action_id,
            binding.trigger, binding.profile, binding.semantic,
            binding.official_action_id_hint, binding.entry, binding.action_id_distance,
            binding.official_action_id_hint_kind, binding.official_semantic_row_id);
        assertRoute(route);
        const qualifiedDisplay = officialQualifiedDirectDisplay(binding.semantic.display);
        const qualifiedDirectRoutes = entries[id] ? entries[id].routes.filter(existing =>
            existing.direct_evidence === true && existing.source === "bcm_profile"
            && Number(existing.owner_action_id) === binding.target_action_id
            && normalizeDisplay(existing.display) === qualifiedDisplay) : [];
        if (qualifiedDirectRoutes.length) {
            const qualifiedSet = new Set(qualifiedDirectRoutes);
            entries[id].routes = entries[id].routes.filter(existing => !qualifiedSet.has(existing));
            officialQualifiedDirectRouteCount += qualifiedDirectRoutes.length;
        }
        if (!entries[id] || entries[id].routes.length === 0) {
            entries[id] = { routes: [], ownership: "official_semantic" };
        }
        if (!entries[id].routes.some(existing => existing.display === route.display)) {
            entries[id].routes.push(route);
            officialBindings.push({
                official_action_id_hint: binding.official_action_id_hint,
                official_action_id_hint_kind: binding.official_action_id_hint_kind,
                official_semantic_row_id: binding.official_semantic_row_id,
                target_action_id: binding.target_action_id,
                action_id_distance: binding.action_id_distance,
                classic_identity: binding.semantic.classic_identity,
                display: binding.semantic.display,
                qualified_direct_displays: qualifiedDirectRoutes.map(item => item.display),
                reason: OFFICIAL_SEMANTIC_REASON
            });
        }
    }

    const communityResult = bindOfficialSemantics(options.communitySemantics, bcmCatalog, actionSet);
    const communityBindings = [], communitySeen = new Set();
    let communityQualifiedDirectRouteCount = 0;
    for (const binding of communityResult.bindings) {
        const id = String(binding.target_action_id);
        const key = `${id}:${binding.semantic.display}`;
        if (communitySeen.has(key)) continue;
        communitySeen.add(key);
        const route = communitySemanticRoute(character, binding.target_action_id,
            binding.trigger, binding.profile, binding.semantic,
            binding.official_action_id_hint, binding.entry, binding.action_id_distance);
        assertRoute(route);
        const qualifiedDisplay = officialQualifiedDirectDisplay(binding.semantic.display);
        const qualifiedDirectRoutes = entries[id] ? entries[id].routes.filter(existing =>
            existing.direct_evidence === true && existing.source === "bcm_profile"
            && Number(existing.owner_action_id) === binding.target_action_id
            && normalizeDisplay(existing.display) === qualifiedDisplay) : [];
        if (qualifiedDirectRoutes.length) {
            const qualifiedSet = new Set(qualifiedDirectRoutes);
            entries[id].routes = entries[id].routes.filter(existing => !qualifiedSet.has(existing));
            communityQualifiedDirectRouteCount += qualifiedDirectRoutes.length;
        }
        if (!entries[id] || entries[id].routes.length === 0) {
            entries[id] = { routes: [], ownership: "community_semantic" };
        }
        if (!entries[id].routes.some(existing => existing.display === route.display)) {
            entries[id].routes.push(route);
            communityBindings.push({
                community_action_id_hint: binding.official_action_id_hint,
                target_action_id: binding.target_action_id,
                action_id_distance: binding.action_id_distance,
                classic_identity: binding.semantic.classic_identity,
                display: binding.semantic.display,
                evidence_id: String(binding.entry.evidence_id || ""),
                qualified_direct_displays: qualifiedDirectRoutes.map(item => item.display),
                reason: COMMUNITY_SEMANTIC_REASON
            });
        }
    }

    const officialDirectRouteRestrictions = restrictDirectRoutesByExactOfficialSemantics(
        entries, options.officialSemantics, bcmCatalog);

    const pairedSprtSpRelations = promotePairedSprtSpRoutes(entries, bcmCatalog);

    // supr can be a player shortcut or an internal command selector. Resolve
    // only conflicts with a unique stronger owner: an exact official normal,
    // or the unique Drive-consuming owner in the same manual command family.
    // State/resource variants without such evidence intentionally remain.
    const shadowedSuprRoutes = suppressShadowedSuprRoutes(entries, bcmCatalog);

    const appliedStateDirectionRelations = [];
    for (const relation of stateChoicePlan.directions) {
        const targetId = String(relation.target_action_id);
        if (!actionSet.has(targetId) || entries[targetId]) continue;
        const route = acStateChoiceRoute(character, relation, relation.direction,
            "ac_type20_state_direction", AC_STATE_DIRECTION_REASON,
            "verified_ac_state_direction");
        assertRoute(route);
        entries[targetId] = { routes: [route], ownership: "ac_state_direction" };
        appliedStateDirectionRelations.push({ ...relation });
    }

    const appliedStateNeutralRelations = [];
    for (const relation of stateChoicePlan.neutrals) {
        const targetId = String(relation.target_action_id);
        if (!actionSet.has(targetId) || entries[targetId]) continue;
        const route = acStateChoiceRoute(character, relation, "N",
            "ac_type1_state_neutral", AC_STATE_NEUTRAL_REASON,
            "verified_ac_state_neutral");
        assertRoute(route);
        entries[targetId] = { routes: [route], ownership: "ac_state_neutral" };
        appliedStateNeutralRelations.push({ ...relation });
    }

    const appliedType13NeutralRelations = [];
    for (const relation of stateChoicePlan.type13Neutrals) {
        const targetId = String(relation.target_action_id);
        if (!actionSet.has(targetId) || entries[targetId]) continue;
        const route = acStateChoiceRoute(character, relation, "N",
            "ac_type13_neutral_continuation", AC_TYPE13_NEUTRAL_REASON,
            "verified_ac_type13_neutral");
        assertRoute(route);
        entries[targetId] = { routes: [route], ownership: "ac_type13_neutral" };
        appliedType13NeutralRelations.push({ ...relation });
    }

    const type63Relations = (runtime.evidence && runtime.evidence.ac_derived_commands || [])
        .filter(relation => Number(relation.branch_type) === 63)
        .sort((left, right) => Number(left.action_id) - Number(right.action_id));
    for (let pass = 0; pass < type63Relations.length; pass += 1) {
        let progress = false;
        for (const relation of type63Relations) {
            const id = String(Number(relation.action_id));
            const sourceId = String(Number(relation.source_action_id));
            if (!actionSet.has(id) || entries[id] || !entries[sourceId]) continue;
            const match = String(relation.display || "").toUpperCase().replace(/\s+/g, "")
                .match(/^>?([1-9])?\+?THROW$/);
            if (!match) continue;
            const sourceRoute = entries[sourceId].routes.find(route => route.visible_button === "THROW"
                && (route.direct_evidence === true || route.source === "ac_type63_throw"));
            if (!sourceRoute) continue;
            const route = inheritedThrowRoute(character, relation, sourceRoute, match[1] || "");
            assertRoute(route);
            entries[id] = { routes: [route], ownership: "inherited" };
            progress = true;
        }
        if (!progress) break;
    }

    const type20Relations = (runtime.evidence && runtime.evidence.ac_derived_commands || [])
        .filter(relation => Number(relation.branch_type) === 20 && relation.force === true)
        .sort((left, right) => Number(left.action_id) - Number(right.action_id));
    const appliedType20Relations = [];
    for (const relation of type20Relations) {
        const targetId = String(Number(relation.action_id));
        const sourceId = String(Number(relation.source_action_id));
        if (!actionSet.has(targetId) || entries[targetId] || !entries[sourceId]) continue;
        const match = String(relation.display || "").replace(/\s+/g, "")
            .match(/^j\.([469])\+(?:LP|MP|HP|LK|MK|HK)$/i);
        if (!match) continue;
        const sourceRoutes = entries[sourceId].routes.filter(route => route.direct_evidence === true
            && /^空中\s+(弱|中|强)$/.test(normalizeDisplay(route.display))
            && /^(弱|中|强)$/.test(String(route.visible_button || "")));
        const buttons = [...new Set(sourceRoutes.map(route => route.visible_button))];
        if (sourceRoutes.length !== 1 || buttons.length !== 1) continue;
        const route = type20DirectionalRoute(character, relation, sourceRoutes[0], match[1], buttons[0]);
        assertRoute(route);
        entries[targetId] = { routes: [route], ownership: "type20_directional" };
        appliedType20Relations.push({
            source_action_id: Number(sourceId), target_action_id: Number(targetId),
            branch_type: 20, direction: match[1], button: buttons[0], reason: TYPE20_DIRECTION_REASON
        });
    }

    const targetComboRelations = (runtime.evidence && runtime.evidence.target_combo_relations || [])
        .filter(relation => relation && relation.evidence === "bcm-turn-around"
            && Array.isArray(relation.parent_action_ids) && relation.parent_action_ids.length === 1)
        .sort((left, right) => Number(left.action_id) - Number(right.action_id));
    const appliedTargetComboRelations = [];
    for (const relation of targetComboRelations) {
        const targetId = String(Number(relation.action_id));
        const parentId = String(Number(relation.parent_action_ids[0]));
        const rule = runtime.validation && runtime.validation.rules
            && runtime.validation.rules[targetId] || null;
        const targetAction = bcmCatalog.actions && bcmCatalog.actions[targetId];
        if (!actionSet.has(targetId) || entries[targetId] || !entries[parentId] || !targetAction
            || !rule || rule.target_combo_followup !== true
            || rule.target_combo_parent_status !== "resolved"
            || rule.physical_button_required !== true) continue;
        const parentButtons = [...new Set(entries[parentId].routes.map(route => {
            const match = normalizeDisplay(route.display).match(/^AUTO \+ (弱|中|强)$/);
            return match ? match[1] : null;
        }).filter(Boolean))];
        if (parentButtons.length !== 1) continue;
        const targetTriggers = (targetAction.triggers || []).filter(item =>
            Number(item.conditions && item.conditions.function_id) === 1
            && Number(item.conditions && item.conditions.turn_around) === 2
            && item.profiles && item.profiles.norm && item.profiles.norm.enabled === true
            && !triggerHasModernProfile(item));
        if (targetTriggers.length !== 1) continue;
        const trigger = targetTriggers[0];
        const route = targetComboRepeatRoute(character, Number(targetId), Number(parentId), trigger,
            trigger.profiles.norm, parentButtons[0]);
        assertRoute(route);
        entries[targetId] = { routes: [route], ownership: "target_combo_repeat" };
        appliedTargetComboRelations.push({
            parent_action_id: Number(parentId), target_action_id: Number(targetId),
            trigger_index: Number(trigger.trigger_index), button: parentButtons[0],
            evidence: "bcm-turn-around", reason: TARGET_COMBO_REPEAT_REASON
        });
    }

    const appliedStructuralTwins = structuralTwinEvidence(actionSource, bcmCatalog, actionSet, entries);
    let structuralTwinRouteCount = 0;
    for (const relation of appliedStructuralTwins) {
        const targetId = String(relation.target_action_id);
        if (entries[targetId]) continue;
        const routes = relation.routes.map(sourceRoute => structuralTwinRoute(character, relation, sourceRoute));
        for (const route of routes) assertRoute(route);
        entries[targetId] = { routes, ownership: "structural_twin" };
        structuralTwinRouteCount += routes.length;
        delete relation.routes;
    }

    const rawRebindEvidence = acRebindEvidence(actionSource, actionSet);
    const plannedRebinds = [];
    for (const relation of rawRebindEvidence.relations) {
        const sourceId = String(relation.source_action_id);
        const targetId = String(relation.target_action_id);
        const sourceEntry = entries[sourceId];
        const sourceAction = bcmCatalog.actions && bcmCatalog.actions[sourceId];
        if (!sourceEntry || sourceEntry.ownership !== "direct" || entries[targetId] || !sourceAction
            || Object.prototype.hasOwnProperty.call(bcmCatalog.actions || {}, targetId)) continue;
        if (!sourceEntry.routes.length || !sourceEntry.routes.every(route => route.source === "bcm_profile"
            && route.direct_evidence === true && route.inheritance_evidence === false
            && route.rebind_evidence === false && Number(route.owner_action_id) === relation.source_action_id)) continue;

        const sourceUnresolved = unresolvedCandidates.filter(candidate =>
            candidate.action_id === relation.source_action_id);
        const triggerIds = new Set(sourceEntry.routes.map(route => Number(route.trigger_index)));
        for (const candidate of sourceUnresolved) triggerIds.add(Number(candidate.trigger_index));
        if (triggerIds.size !== 1) continue;
        const triggerIndex = [...triggerIds][0];
        const trigger = (sourceAction.triggers || []).find(item => Number(item.trigger_index) === triggerIndex);
        if (!trigger || Number(trigger.conditions && trigger.conditions.function_id) !== 2
            || Number(trigger.conditions && trigger.conditions.cond_owner_state_flags) !== 0) continue;

        if (sourceUnresolved.length) continue;
        plannedRebinds.push({ relation, sourceId, targetId, sourceEntry });
    }

    let rebindRouteCount = 0;
    for (const plan of plannedRebinds) {
        const routes = plan.sourceEntry.routes.map(route =>
            rebindRoute(plan.relation, route, route.display));
        for (const route of routes) assertRoute(route);
        entries[plan.targetId] = { routes, ownership: "rebind" };
        delete entries[plan.sourceId];
        rebindRouteCount += routes.length;
    }

    const automaticHoldType29 = automaticHoldTransitionType29Targets(actionSource, actionSet);
    const suppressedAutomaticHoldType29Aliases = [];
    const verifiedAliasRelations = (runtime.evidence && runtime.evidence.alias_relations || [])
        .filter(relation => relation && relation.relation === "equivalent-action-variant"
            && relation.source === "ac-branch" && [29, 35].includes(Number(relation.branch_type)))
        .filter(relation => {
            const targetId = Number(relation.alias_action_id);
            if (Number(relation.branch_type) !== 29 || !automaticHoldType29.has(targetId)) return true;
            suppressedAutomaticHoldType29Aliases.push({
                target_action_id: targetId,
                selected_source_action_id: Number(relation.target_action_id),
                incoming_source_action_ids: automaticHoldType29.get(targetId),
                reason: "type29_target_is_reached_from_verified_hold_continuation"
            });
            return false;
        })
        .sort((left, right) => Number(left.alias_action_id) - Number(right.alias_action_id));
    const appliedVerifiedAliases = [];
    let verifiedAliasRouteCount = 0;
    for (let pass = 0; pass < verifiedAliasRelations.length; pass += 1) {
        let progress = false;
        for (const relation of verifiedAliasRelations) {
            const targetId = String(Number(relation.alias_action_id));
            const sourceId = String(Number(relation.target_action_id));
            if (!actionSet.has(targetId) || entries[targetId] || !entries[sourceId]
                || String(runtime.aliases && runtime.aliases[targetId] || "") !== sourceId) continue;
            const routes = entries[sourceId].routes.map(route =>
                verifiedAliasRoute(character, relation, route));
            for (const route of routes) assertRoute(route);
            entries[targetId] = { routes, ownership: "verified_alias" };
            appliedVerifiedAliases.push({
                source_action_id: Number(sourceId),
                target_action_id: Number(targetId),
                branch_type: Number(relation.branch_type),
                reason: VERIFIED_ALIAS_REASON
            });
            verifiedAliasRouteCount += routes.length;
            progress = true;
        }
        if (!progress) break;
    }

    let suppressedAutomaticHoldTransitionCount = 0;
    for (const evidence of suppressedAutomaticHoldType29Aliases) {
        const targetId = String(Number(evidence.target_action_id));
        if (!actionSet.has(targetId) || entries[targetId]) continue;
        entries[targetId] = {
            routes: [],
            ownership: "automatic_hold_transition",
            suppress_display: true,
            transition_evidence: { ...evidence }
        };
        suppressedAutomaticHoldTransitionCount += 1;
    }

    const suppressedInternalTransitions = [];
    for (const relation of stateChoicePlan.releases) {
        const targetId = String(relation.target_action_id);
        if (!actionSet.has(targetId) || entries[targetId]) continue;
        const evidence = { kind: "ac_state_direction_release", ...relation };
        entries[targetId] = {
            routes: [],
            ownership: "internal_state_transition",
            suppress_display: true,
            transition_evidence: evidence
        };
        suppressedInternalTransitions.push(evidence);
    }
    for (const relation of zeroInputTransitions) {
        const targetId = String(relation.action_id);
        if (!actionSet.has(targetId) || entries[targetId]) continue;
        const evidence = { kind: "bcm_zero_input_transition",
            target_action_id: relation.action_id, ...relation };
        entries[targetId] = {
            routes: [],
            ownership: "internal_state_transition",
            suppress_display: true,
            transition_evidence: evidence
        };
        suppressedInternalTransitions.push(evidence);
    }
    suppressedInternalTransitions.sort((left, right) =>
        Number(left.target_action_id) - Number(right.target_action_id));

    const type20PhaseCandidates = strictType20ActionPhaseRelations(actionSource, actionSet);
    const appliedType20PhaseRelations = [];
    let type20PhaseRouteCount = 0;
    for (const relation of type20PhaseCandidates) {
        const sourceId = String(relation.source_action_id);
        const targetId = String(relation.target_action_id);
        const sourceEntry = entries[sourceId];
        if (!sourceEntry || entries[targetId]) continue;
        const sourceRoutes = sourceEntry.routes.filter(route => route.direct_evidence === true
            && route.inheritance_evidence === false && Number(route.owner_action_id) === Number(sourceId));
        if (!sourceRoutes.length || sourceRoutes.length !== sourceEntry.routes.length) continue;
        const routes = sourceRoutes.map(route => type20ActionPhaseRoute(character, relation, route));
        for (const route of routes) assertRoute(route);
        entries[targetId] = { routes, ownership: "type20_action_phase" };
        appliedType20PhaseRelations.push({ ...relation, reason: TYPE20_PHASE_REASON });
        type20PhaseRouteCount += routes.length;
    }

    const holdButtonForMask = mask => {
        if (mask === 112 || mask === 896) return ANY_BUTTON;
        if (mask === 16 || mask === 128) return "弱";
        if (mask === 32 || mask === 256) return "中";
        if (mask === 64 || mask === 512) return "强";
        return null;
    };
    const strictHoldCandidates = strictType20HoldRelations(actionSource, actionSet);
    const appliedType20HoldRelations = [];
    let type20HoldRouteCount = 0;
    for (const relation of strictHoldCandidates) {
        const sourceId = String(relation.source_action_id);
        const targetId = String(relation.target_action_id);
        const sourceEntry = entries[sourceId];
        const button = holdButtonForMask(relation.param01);
        if (!sourceEntry || entries[targetId] || !button) continue;
        const sourceRoute = sourceEntry.routes.find(route => route.direct_evidence === true)
            || sourceEntry.routes.find(route => route.official_semantic_evidence === true)
            || sourceEntry.routes.find(route => route.inheritance_evidence === true);
        if (!sourceRoute) continue;
        const route = type20HoldRoute(character, relation, sourceRoute, button);
        assertRoute(route);
        entries[targetId] = { routes: [route], ownership: "type20_hold_continuation" };
        appliedType20HoldRelations.push({ ...relation, button, reason: TYPE20_HOLD_REASON });
        type20HoldRouteCount += 1;
    }

    // Assist Combo recipes are direct BCM ownership evidence. Each 10-step
    // recipe belongs to one fixed strength block: the first step is entered
    // with AUTO + strength, every later step repeats that strength. They are
    // only a fallback for an otherwise unmapped Action. If BCM/AC/official
    // evidence already provides an Action entry, the Assist step reaches that
    // same Action but is not an additional move-command route for the UI.
    const assistComboCandidates = assistComboRelations(bcmCatalog, actionSet);
    const appliedAssistComboRelations = [];
    let assistComboDuplicateDisplayCount = 0;
    let assistComboNormalizedToExistingCount = 0;
    for (const relation of assistComboCandidates) {
        const id = String(relation.action_id);
        if (entries[id]) {
            if (entries[id].routes.some(route => normalizeDisplay(route.display) === relation.display)) {
                assistComboDuplicateDisplayCount += 1;
            } else {
                assistComboNormalizedToExistingCount += 1;
            }
            continue;
        }
        entries[id] = { routes: [], ownership: "assist_combo" };
        const route = assistComboRoute(character, relation);
        assertRoute(route);
        entries[id].routes.push(route);
        appliedAssistComboRelations.push({
            action_id: relation.action_id,
            display: relation.display,
            assist_strength: relation.assist_strength,
            input_stage: relation.input_stage,
            reason: ASSIST_COMBO_REASON,
            occurrences: relation.occurrences.map(item => ({ ...item }))
        });
    }
    const sortedActionIds = [...actionSet].map(Number).sort((left, right) => left - right);
    const unmappedActionIds = sortedActionIds.filter(id => !entries[String(id)]);
    unresolvedCandidates.sort((left, right) => left.action_id - right.action_id
        || Number(left.trigger_index || -1) - Number(right.trigger_index || -1)
        || String(left.profile).localeCompare(String(right.profile)));

    const allRoutes = Object.values(entries).flatMap(entry => entry.routes);
    for (const route of allRoutes) assertRoute(route);
    const directRouteCount = allRoutes.filter(route => route.direct_evidence === true).length;
    const inheritedRouteCount = allRoutes.filter(route => route.inheritance_evidence === true).length;
    const runtimeCommonRouteCount = allRoutes.filter(route => route.runtime_common_evidence === true).length;
    const officialSemanticRouteCount = allRoutes.filter(route => route.official_semantic_evidence === true).length;
    const communitySemanticRouteCount = allRoutes.filter(route => route.community_semantic_evidence === true).length;
    const type20DirectionalRouteCount = allRoutes.filter(route =>
        route.source === "ac_type20_directional_air_attack").length;
    const chargeContextRouteCount = allRoutes.filter(route =>
        route.charge_context_evidence === true).length;
    const superShortcutDirectionRouteCount = allRoutes.filter(route =>
        route.super_shortcut_direction_evidence === true).length;
    const appliedAcChargeKeys = new Set(allRoutes.filter(route =>
        route.charge_context_relation === "ac_full_structure_peer")
        .map(route => `${Number(route.owner_action_id)}:${Number(route.trigger_index)}:${route.profile}`));
    const appliedAcChargeRelations = acChargePlan.relations.filter(relation =>
        appliedAcChargeKeys.has(`${relation.target_action_id}:${relation.target_trigger_index}:${relation.profile}`));
    const targetComboRepeatRouteCount = allRoutes.filter(route =>
        route.source === "bcm_target_combo_repeat").length;
    const assistComboRouteCount = allRoutes.filter(route =>
        route.source === "bcm_assist_combo_recipe").length;
    const stateDirectionRouteCount = allRoutes.filter(route =>
        route.source === "ac_type20_state_direction").length;
    const stateNeutralRouteCount = allRoutes.filter(route =>
        route.source === "ac_type1_state_neutral").length;
    const type13NeutralRouteCount = allRoutes.filter(route =>
        route.source === "ac_type13_neutral_continuation").length;
    const relationCounts = {};
    for (const route of allRoutes) if (route.ac_relation_type !== null) {
        const key = String(route.ac_relation_type);
        relationCounts[key] = (relationCounts[key] || 0) + 1;
    }
    const officialFollowupRelations = inferOfficialFollowupRelations(options.officialSemantics, entries);
    const separatedCommands = new Map();
    for (const [id, entry] of Object.entries(entries)) {
        if (entry.suppress_display === true) continue;
        separatedCommands.set(id, splitCommands(entry, officialFollowupRelations.get(id)));
    }
    const splitCommandActionCount = [...separatedCommands.values()]
        .filter(commands => commands.simple || commands.motion).length;
    const classicCommands = new Map(Object.entries(runtime.actions || {})
        .filter(([id]) => actionSet.has(String(Number(id))))
        .map(([id, display]) => [String(Number(id)), compactClassicCommand(display)])
        .filter(([, command]) => command));
    for (const [id, display] of Object.entries(RUNTIME_COMMON_ACTIONS)) {
        if (actionSet.has(String(Number(id))) && !classicCommands.has(String(Number(id)))) {
            classicCommands.set(String(Number(id)), compactClassicCommand(display));
        }
    }
    for (const [id, action] of Object.entries(bcmCatalog.actions || {})) {
        if (actionSet.has(String(Number(id))) && !classicCommands.has(String(Number(id)))) {
            const command = compactClassicCommand(action && action.classic_display);
            if (command) classicCommands.set(String(Number(id)), command);
        }
    }
    const equivalentOwnership = new Set(["verified_alias", "structural_twin", "rebind"]);
    let classicProjectionChanged = true;
    while (classicProjectionChanged) {
        classicProjectionChanged = false;
        for (const [id, entry] of Object.entries(entries)) {
            if (classicCommands.has(id)) continue;
            if (["ac_state_direction", "ac_state_neutral", "ac_type13_neutral"]
                .includes(entry.ownership)) {
                const displays = [...new Set((entry.routes || []).map(route => String(route.display || ""))
                    .filter(display => /^(?:N|[1246789])$/.test(display)))];
                if (displays.length === 1) {
                    classicCommands.set(id, compactClassicCommand(displays[0]));
                    classicProjectionChanged = true;
                    continue;
                }
            }
            if (!equivalentOwnership.has(entry.ownership)) continue;
            const inherited = [...new Set((entry.routes || [])
                .map(route => route.inherited_from_action_id != null
                    ? String(Number(route.inherited_from_action_id))
                    : (entry.ownership === "rebind"
                        ? String(Number(route.bcm_owner_action_id)) : "NaN"))
                .filter(sourceId => sourceId !== "NaN" && classicCommands.has(sourceId))
                .map(sourceId => classicCommands.get(sourceId).display))];
            if (inherited.length === 1) {
                classicCommands.set(id, compactClassicCommand(inherited[0]));
                classicProjectionChanged = true;
            }
        }
    }
    const outputActionIds = [...new Set([...Object.keys(entries), ...classicCommands.keys()])]
        .sort((left, right) => Number(left) - Number(right));
    const sharedCommandActionCount = outputActionIds.filter(id => {
        const commands = separatedCommands.get(id);
        return classicCommands.has(id) && commands && (commands.simple || commands.motion);
    }).length;
    const classicProjectionPendingCount = splitCommandActionCount - sharedCommandActionCount;
    const followupRelations = [...officialFollowupRelations.entries()]
        .map(([targetId, relation]) => ({ target_action_id: Number(targetId), ...relation }))
        .sort((left, right) => left.target_action_id - right.target_action_id);

    const generatedFrom = options.communitySemantics
        ? (options.officialSemantics
            ? "ac_bcm+capcom_official_semantics+community_verified_semantics"
            : "ac_bcm+community_verified_semantics")
        : (options.officialSemantics ? "ac_bcm+capcom_official_semantics" : "ac_bcm");
    const output = {
        _meta: {
            schema: SCHEMA,
            strict_policy: STRICT_POLICY,
            character,
            fighter_id: runtime.fighter_id,
            generated_from: generatedFrom,
            generated_at: options.generatedAt || new Date().toISOString(),
            ac_sha256: runtime.sources && runtime.sources.ac_sha256 || null,
            bcm_sha256: runtime.sources && runtime.sources.bcm_sha256 || null,
            modern_profile_order: MODERN_PROFILE_ORDER,
            direct_route_count: directRouteCount,
            inherited_route_count: inheritedRouteCount,
            rebind_route_count: rebindRouteCount,
            runtime_common_route_count: runtimeCommonRouteCount,
            official_semantic_route_count: officialSemanticRouteCount,
            official_semantic_qualified_direct_route_count: officialQualifiedDirectRouteCount,
            community_semantic_route_count: communitySemanticRouteCount,
            community_semantic_qualified_direct_route_count: communityQualifiedDirectRouteCount,
            community_semantic_source_sha256: options.communitySemanticsSha256 || null,
            verified_alias_route_count: verifiedAliasRouteCount,
            hold_transition_type29_alias_suppression_count: suppressedAutomaticHoldType29Aliases.length,
            hold_transition_suppressed_action_count: suppressedAutomaticHoldTransitionCount,
            hold_transition_type29_alias_suppressions: suppressedAutomaticHoldType29Aliases,
            type20_directional_route_count: type20DirectionalRouteCount,
            type20_hold_route_count: type20HoldRouteCount,
            type20_action_phase_route_count: type20PhaseRouteCount,
            charge_context_route_count: chargeContextRouteCount,
            super_shortcut_direction_route_count: superShortcutDirectionRouteCount,
            ac_charge_context_relation_count: appliedAcChargeRelations.length,
            ac_charge_context_relations: appliedAcChargeRelations,
            charge_compatibility_trigger_suppression_count:
                suppressedChargeCompatibilityTriggers.length,
            charge_compatibility_trigger_suppressions:
                suppressedChargeCompatibilityTriggers.sort((left, right) =>
                    left.action_id - right.action_id
                    || left.suppressed_trigger_index - right.suppressed_trigger_index),
            target_combo_repeat_route_count: targetComboRepeatRouteCount,
            structural_twin_route_count: structuralTwinRouteCount,
            assist_combo_route_count: assistComboRouteCount,
            assist_combo_normalized_to_existing_count: assistComboNormalizedToExistingCount,
            paired_sprt_sp_route_count: pairedSprtSpRelations.length,
            paired_sprt_sp_relations: pairedSprtSpRelations,
            shadowed_supr_route_count: shadowedSuprRoutes.length,
            shadowed_supr_routes: shadowedSuprRoutes,
            official_direct_route_restriction_count: officialDirectRouteRestrictions.length,
            official_direct_route_restrictions: officialDirectRouteRestrictions,
            ac_state_direction_route_count: stateDirectionRouteCount,
            ac_state_direction_relations: appliedStateDirectionRelations,
            ac_state_neutral_route_count: stateNeutralRouteCount,
            ac_state_neutral_relations: appliedStateNeutralRelations,
            ac_type13_neutral_route_count: type13NeutralRouteCount,
            ac_type13_neutral_relations: appliedType13NeutralRelations,
            internal_transition_suppression_count: suppressedInternalTransitions.length,
            suppressed_internal_transitions: suppressedInternalTransitions,
            split_command_action_count: splitCommandActionCount,
            followup_relation_count: followupRelations.length,
            followup_relations: followupRelations,
            official_semantic_source_sha256: options.officialSemanticsSha256 || null,
            classic_profile_order: CLASSIC_PROFILE_ORDER,
            ac_relation_route_counts: relationCounts,
            ac_command_entry_rebinds: plannedRebinds.map(plan => ({
                source_action_id: Number(plan.sourceId),
                target_action_id: Number(plan.targetId),
                reason: REBIND_REASON
            })),
            runtime_common_actions: runtimeCommonActions,
            official_semantic_bindings: officialBindings,
            official_semantic_unresolved: officialResult.unresolved,
            community_semantic_bindings: communityBindings,
            community_semantic_unresolved: communityResult.unresolved,
            verified_alias_relations: appliedVerifiedAliases,
            type20_directional_relations: appliedType20Relations,
            type20_hold_relations: appliedType20HoldRelations,
            type20_action_phase_relations: appliedType20PhaseRelations,
            target_combo_repeat_relations: appliedTargetComboRelations,
            structural_twin_relations: appliedStructuralTwins,
            assist_combo_relations: appliedAssistComboRelations,
            unresolved_candidate_count: unresolvedCandidates.length,
            unresolved_candidates: unresolvedCandidates,
            unmapped_action_count: unmappedActionIds.length,
            unmapped_action_ids: unmappedActionIds,
            audit: {
                strict_route_ownership: true,
                owner_missing_count: allRoutes.filter(route => !Number.isFinite(route.owner_action_id)).length,
                no_evidence_count: allRoutes.filter(route =>
                    [route.direct_evidence, route.inheritance_evidence, route.rebind_evidence,
                        route.runtime_common_evidence, route.official_semantic_evidence,
                        route.community_semantic_evidence]
                        .filter(value => value === true).length !== 1).length,
                direct_overridden_count: 0,
                non_whitelist_propagation_count: 0,
                overlay_entry_count: 0,
                community_route_count: 0,
                legacy_supplement_entry_count: 0,
                classic_fallback_count: 0,
                classic_token_leak_count: 0,
                alias_propagation_count: 0,
                type17_route_count: 0,
                ac_type17_relation_count: rawRebindEvidence.type17_relation_count,
                ac_command_entry_rebind_signature_count: rawRebindEvidence.signature_candidate_count,
                ac_command_entry_rebind_relation_count: plannedRebinds.length,
                ac_command_entry_rebind_route_count: rebindRouteCount,
                runtime_common_action_count: runtimeCommonActions.length,
                runtime_common_route_count: runtimeCommonRouteCount,
                official_semantic_binding_count: officialBindings.length,
                official_semantic_route_count: officialSemanticRouteCount,
                official_semantic_qualified_direct_route_count: officialQualifiedDirectRouteCount,
                official_semantic_unresolved_count: officialResult.unresolved.length,
                community_semantic_binding_count: communityBindings.length,
                community_semantic_route_count: communitySemanticRouteCount,
                community_semantic_qualified_direct_route_count: communityQualifiedDirectRouteCount,
                community_semantic_unresolved_count: communityResult.unresolved.length,
                verified_alias_relation_count: appliedVerifiedAliases.length,
                verified_alias_route_count: verifiedAliasRouteCount,
                hold_transition_type29_alias_suppression_count: suppressedAutomaticHoldType29Aliases.length,
                hold_transition_suppressed_action_count: suppressedAutomaticHoldTransitionCount,
                type20_directional_relation_count: appliedType20Relations.length,
                type20_directional_route_count: type20DirectionalRouteCount,
                type20_hold_relation_count: appliedType20HoldRelations.length,
                type20_hold_route_count: type20HoldRouteCount,
                type20_action_phase_relation_count: appliedType20PhaseRelations.length,
                type20_action_phase_route_count: type20PhaseRouteCount,
                charge_context_route_count: chargeContextRouteCount,
                super_shortcut_direction_route_count: superShortcutDirectionRouteCount,
                ac_charge_context_relation_count: appliedAcChargeRelations.length,
                charge_compatibility_trigger_suppression_count:
                    suppressedChargeCompatibilityTriggers.length,
                target_combo_repeat_relation_count: appliedTargetComboRelations.length,
                target_combo_repeat_route_count: targetComboRepeatRouteCount,
                structural_twin_relation_count: appliedStructuralTwins.length,
                structural_twin_route_count: structuralTwinRouteCount,
                assist_combo_candidate_count: assistComboCandidates.length,
                assist_combo_relation_count: appliedAssistComboRelations.length,
                assist_combo_route_count: assistComboRouteCount,
                assist_combo_duplicate_display_count: assistComboDuplicateDisplayCount,
                assist_combo_normalized_to_existing_count: assistComboNormalizedToExistingCount,
                paired_sprt_sp_relation_count: pairedSprtSpRelations.length,
                paired_sprt_sp_route_count: pairedSprtSpRelations.length,
                shadowed_supr_route_count: shadowedSuprRoutes.length,
                official_direct_route_restriction_count: officialDirectRouteRestrictions.length,
                ac_state_direction_relation_count: appliedStateDirectionRelations.length,
                ac_state_direction_route_count: stateDirectionRouteCount,
                ac_state_neutral_relation_count: appliedStateNeutralRelations.length,
                ac_state_neutral_route_count: stateNeutralRouteCount,
                ac_type13_neutral_relation_count: appliedType13NeutralRelations.length,
                ac_type13_neutral_route_count: type13NeutralRouteCount,
                internal_transition_suppression_count: suppressedInternalTransitions.length,
                split_command_action_count: splitCommandActionCount,
                classic_command_action_count: classicCommands.size,
                shared_command_action_count: sharedCommandActionCount,
                classic_projection_pending_count: classicProjectionPendingCount,
                command_display_action_count: outputActionIds.length,
                followup_relation_count: followupRelations.length,
                command_slot_overflow_count: 0,
                ac_automatic_transition_route_count: 0,
                replaces_profile_route_count: 0
            },
            description: `${character} unified Classic and Modern command projections generated from one verified AC ActionGraph, BCM profiles, runtime semantics, and Capcom command semantics.`
        }
    };

    for (const id of outputActionIds) {
        const entry = entries[id] || { routes: [], ownership: "classic_runtime" };
        const classicCommand = classicCommands.get(id) || null;
        const commands = separatedCommands.get(id) || { simple: null, motion: null };
        const displays = [commands.simple && commands.simple.display,
            commands.motion && commands.motion.display].filter(Boolean);
        const hasModernCommand = displays.length > 0;
        if (entry.suppress_display === true) {
            output[id] = {
                modern_display: null,
                classic_command: classicCommand,
                control_support: commandControlSupport(classicCommand, false),
                source: generatedFrom,
                ownership: entry.ownership,
                suppress_display: true,
                transition_evidence: entry.transition_evidence,
                routes: []
            };
            continue;
        }
        output[id] = {
            modern_display: hasModernCommand ? displays.join("/") : null,
            classic_command: classicCommand,
            control_support: commandControlSupport(classicCommand, hasModernCommand),
            source: generatedFrom,
            ownership: entry.ownership,
            simple_command: commands.simple,
            motion_command: commands.motion,
            relation: officialFollowupRelations.get(id) || undefined,
            routes: entry.routes
        };
    }
    return output;
}

module.exports = {
    SCHEMA,
    STRICT_POLICY,
    CLASSIC_PROFILE_ORDER,
    MODERN_PROFILE_ORDER,
    RUNTIME_COMMON_ACTIONS,
    buildModernDisplay,
    translateProfile,
    assertValidDisplay
};
