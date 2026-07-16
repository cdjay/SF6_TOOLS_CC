"use strict";

const SCHEMA = "xt.modern_display.v2";
const MODERN_PROFILE_ORDER = ["easy", "supr", "sprt"];

function buttonCount(profile) {
    return ((Number(profile && profile.ok_key_cond_flags || 0) >> 6) & 3) + 1;
}

function splitNotation(profile) {
    let notation = String(profile && profile.notation || "");
    const air = notation.startsWith("j.");
    if (air) notation = notation.slice(2);
    const parts = notation.split("+").filter(Boolean).map(part => part === "4236" ? "236" : part);
    return { air, parts };
}

function joinRoute(air, parts) {
    if (!parts.length) return null;
    return `${air ? "空中 " : ""}${parts.join(" + ")}`;
}

function translatedDirection(parts, buttonNames) {
    // BCM uses `*` as a wildcard direction in some profiles. It is a matching
    // token, not player-facing notation (for example Guile SA shortcuts).
    return parts.filter(part => !buttonNames.has(part) && part !== "Normal" && part !== "*");
}

function translateSequentialAttack(profile) {
    const inputs = profile && profile.command && profile.command.inputs;
    if (!Array.isArray(inputs) || inputs.length < 2) return null;

    const attackName = rawMask => {
        const raw = Number(rawMask);
        if (raw === 16) return "弱";
        if (raw === 128) return "中";
        if (raw === 256) return "强";
        return null;
    };
    const sequence = [];
    for (const input of inputs) {
        // Some BCM commands encode sequential attack presses as neutral (5)
        // direction slots whose raw masks carry the actual button identity.
        if (String(input && input.direction) !== "5") return null;
        const button = attackName(input && input.raw_mask);
        if (!button) return null;
        sequence.push(button);
    }
    const finalButton = attackName(profile.ok_key_flags);
    if (!finalButton) return null;
    sequence.push(finalButton);
    return sequence.join(" > ");
}

function translateSprt(profile) {
    const { air, parts } = splitNotation(profile);
    const sequentialAttack = translateSequentialAttack(profile);
    if (sequentialAttack) return `${air ? "空中 " : ""}${sequentialAttack}`;
    const buttons = new Set(["LP", "MP", "HP", "LK", "MK", "HK", "P", "K", "PP", "KK", "PPP", "KKK", "Throw", "Parry", "DI"]);
    const result = translatedDirection(parts, buttons);
    const raw = Number(profile.ok_key_flags || 0);
    const count = buttonCount(profile);
    const attackBits = [16, 128, 256].filter(bit => (raw & bit) !== 0);

    if (profile.button === "Throw" || raw === 144) result.push("THROW");
    else if (profile.button === "Parry" || raw === 288) result.push("DP");
    else if (profile.button === "DI" || raw === 576) result.push("DI");
    else if (attackBits.length > 1) {
        // D2D already understands the explicit Modern strength tokens and the
        // two-button compatibility token. It does not understand 攻击三つ.
        if (count >= 3) result.push("弱", "中", "强");
        else result.push("攻击二つ");
    }
    else if ((raw & 16) !== 0) result.push("弱");
    else if ((raw & 128) !== 0) result.push("中");
    else if ((raw & 256) !== 0) result.push("强");
    else if ((raw & 64) !== 0) result.push("DP");
    else if (parts.length === result.length && parts.length === 0) return null;
    return joinRoute(air, result);
}

function translateEasy(profile) {
    const { air, parts } = splitNotation(profile);
    const buttons = new Set(["LP", "MP", "HP", "LK", "MK", "HK", "P", "K", "PP", "KK", "PPP", "KKK", "Throw", "Parry", "DI"]);
    const result = translatedDirection(parts, buttons);
    const raw = Number(profile.ok_key_flags || 0);
    if (raw === 32) result.push("SP");
    else if (raw === 288) result.push("SP", "强");
    else if (raw === 16) result.push("弱");
    else if (raw === 128) result.push("中");
    else if (raw === 256) result.push("强");
    else if (raw === 400 || raw === 432) result.push("攻击");
    else return null;
    return joinRoute(air, result);
}

function translateSupr(profile, conditions) {
    // `supr` is the assisted route. Super Arts use easy=SP+强; their supr
    // profile belongs to a different internal selector and must not be shown
    // as AUTO input.
    if (Number(conditions && conditions.function_id) === 3) return null;
    const { air, parts } = splitNotation(profile);
    const buttons = new Set(["LP", "MP", "HP", "LK", "MK", "HK", "P", "K", "PP", "KK", "PPP", "KKK", "Throw", "Parry", "DI"]);
    const result = translatedDirection(parts, buttons);
    const raw = Number(profile.ok_key_flags || 0);
    result.push("AUTO");
    if (raw === 2147483648) result.push("中");
    else if (raw === 8192 || raw === 32) result.push("SP");
    else if (raw === 16) result.push("弱");
    else if (raw === 128) result.push("中");
    else if (raw === 256 || raw === 512) result.push("强");
    else return null;
    return joinRoute(air, result);
}

function translateProfile(name, profile, conditions) {
    if (!profile || profile.enabled !== true) return null;
    if (name === "sprt") return translateSprt(profile);
    if (name === "easy") return translateEasy(profile);
    if (name === "supr") return translateSupr(profile, conditions);
    return null;
}

function selectedProfiles(conditions, profiles) {
    const functionId = Number(conditions && conditions.function_id || 0);
    if (functionId === 1 && Number(conditions && conditions.cond_owner_state_flags || 0) !== 4) {
        // Ground normals can expose both the direct Modern profile and an
        // assisted candidate. When sprt is enabled it is the winning action
        // for this ID; AUTO resolves through a separate supr-only trigger.
        if (profiles && profiles.sprt && profiles.sprt.enabled === true) return ["sprt"];
        if (profiles && profiles.supr && profiles.supr.enabled === true) return ["supr"];
        return ["sprt"];
    }
    if (functionId === 2) {
        // For Modern specials, both slots can be populated in the dump. The
        // trigger's Drive cost decides which shortcut wins at runtime:
        // normal special = easy (SP), OD special = supr (AUTO+SP).
        const easyEnabled = profiles && profiles.easy && profiles.easy.enabled === true;
        const suprEnabled = profiles && profiles.supr && profiles.supr.enabled === true;
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
    if (/\+\s*\+/.test(display) || display.includes("攻击三つ") || display.includes("*")) {
        throw new Error(`非法 Modern 显示 token: ${display}`);
    }
}

function isCommunityAudit(value) {
    return value && value.source === "community_sample";
}

function assertCommunityAudit(audit, display) {
    if (!isCommunityAudit(audit)) return;
    if (typeof audit.reason !== "string" || audit.reason.trim() === ""
        || typeof audit.note !== "string" || audit.note.trim() === "") {
        throw new Error(`community_sample route 缺少 reason/note: ${display}`);
    }
}

function assertValidRoute(display, evidence) {
    assertValidDisplay(display);
    assertCommunityAudit(evidence, display);
    assertCommunityAudit(evidence && evidence.verification, display);
}

function pushRoute(routes, seen, display, evidence) {
    display = normalizeDisplay(display);
    assertValidRoute(display, evidence);
    if (!display) return;
    if (seen.has(display)) {
        const existing = routes.find(route => route.display === display);
        // Preserve the automatic route as the execution evidence while making
        // a same-display community verification independently auditable.
        if (existing && isCommunityAudit(evidence) && !isCommunityAudit(existing)) {
            existing.verification = { ...evidence };
        }
        return;
    }
    seen.add(display);
    routes.push({ display, ...evidence });
}

function buildModernDisplay(actionSource, bcmCatalog, runtime, supplement, options) {
    options = options || {};
    supplement = supplement || {};
    const actionSet = new Set((runtime.action_ids || []).map(value => String(Number(value))));
    const entries = {};

    for (const [id, action] of Object.entries(bcmCatalog.actions || {})) {
        if (!actionSet.has(id)) continue;
        const routes = [], seen = new Set();
        for (const trigger of action.triggers || []) {
            for (const profileName of selectedProfiles(trigger.conditions, trigger.profiles)) {
                const display = translateProfile(profileName, trigger.profiles && trigger.profiles[profileName], trigger.conditions);
                if (!display) continue;
                const followup = Number(trigger.conditions && trigger.conditions.turn_around) === 2;
                pushRoute(routes, seen, followup && !display.startsWith(">") ? `> ${display}` : display, {
                    source: "bcm_profile",
                    profile: profileName,
                    trigger_index: trigger.trigger_index
                });
            }
        }
        if (routes.length) entries[id] = { routes };
    }

    // AC aliases inherit every generated modern route from their target.
    for (const [aliasId, targetId] of Object.entries(runtime.aliases || {})) {
        if (!entries[targetId] || entries[aliasId]) continue;
        entries[aliasId] = {
            routes: entries[targetId].routes.map(route => ({ ...route, source: "ac_alias", inherited_from: Number(targetId) }))
        };
    }

    // AC Type 63 encodes the back throw as a derived action without its own
    // BCM trigger. Preserve the direction while inheriting Throw semantics.
    for (const relation of runtime.evidence && runtime.evidence.ac_derived_commands || []) {
        const id = String(Number(relation.action_id));
        if (!actionSet.has(id) || entries[id]) continue;
        const display = String(relation.display || "").toUpperCase();
        const throwMatch = display.replace(/\s+/g, "").match(/^>?([1-9])?\+?THROW$/);
        if (throwMatch) {
            const direction = throwMatch[1] || "";
            entries[id] = { routes: [{
                display: direction ? `${direction} + THROW` : "THROW",
                source: "ac_derived",
                inherited_from: Number(relation.source_action_id)
            }] };
        }
    }

    // DRC and raw Drive Rush are semantic BCM actions. Their 66/DP trigger
    // shapes are implementation alternatives, not the labels shown to users.
    for (const [id, rule] of Object.entries(runtime.validation && runtime.validation.rules || {})) {
        if (!actionSet.has(id) || !rule || !rule.system_action) continue;
        let display = null;
        if (rule.system_action === "drc") display = "DRC";
        else if (rule.system_action === "raw_dr") display = "RAW DR";
        if (display) entries[id] = { routes: [{ display, source: "bcm_system_action" }] };
    }

    // Preserve universal semantic controls instead of exposing their internal
    // profile masks. Drive Parry is identified by BCM behavior; DI/Drive
    // Reversal already have stable runtime displays compiled from BCM.
    for (const id of actionSet) {
        const action = bcmCatalog.actions && bcmCatalog.actions[id];
        const isDriveParry = action && (action.triggers || []).some(trigger =>
            Number(trigger.conditions && trigger.conditions.function_id) === 10
            && Number(trigger.conditions && trigger.conditions.focus_consume) === 5000);
        if (isDriveParry) {
            entries[id] = { routes: [{ display: "DP", source: "bcm_system_action" }] };
            continue;
        }
        const classicDisplay = String(runtime.actions && runtime.actions[id] || "")
            .toUpperCase().replace(/\s+/g, "");
        if (classicDisplay === "DI" || /^\d+\+DI$/.test(classicDisplay)) {
            entries[id] = { routes: [{
                display: classicDisplay.replace("+DI", " + DI"),
                source: "bcm_system_action"
            }] };
        }
    }

    // Keep only explicitly runtime-verified supplements. Official web rows are
    // intentionally excluded because their Action IDs can drift from the dump.
    for (const [id, value] of Object.entries(supplement)) {
        if (!/^\d+$/.test(id) || !actionSet.has(id) || !value) continue;
        const verifiedRoutes = Array.isArray(value.routes)
            ? value.routes.flatMap(route => {
                const audit = isCommunityAudit(route)
                    ? route : (isCommunityAudit(route && route.verification) ? route.verification : null);
                if (!audit) return [];
                const reason = [audit.reason, audit.note, audit.evidence, value.note]
                    .find(item => typeof item === "string" && item.trim() !== "");
                const note = [audit.note, audit.reason, audit.evidence, value.note]
                    .find(item => typeof item === "string" && item.trim() !== "");
                return [{
                    display: route.display,
                    reason,
                    note,
                    evidence: typeof audit.evidence === "string" ? audit.evidence : undefined
                }];
            })
            : [];
        const legacyVerified = value.source === "community_sample"
            || (typeof value.source === "string" && value.source.includes("community_sample"));
        if (!legacyVerified && !verifiedRoutes.length) continue;
        const entry = entries[id] || { routes: [] };
        const seen = new Set(entry.routes.map(route => route.display));
        const displays = verifiedRoutes.length
            ? verifiedRoutes
            : (typeof value.modern_display === "string" ? value.modern_display.split("/").map(display => ({
                display,
                reason: value.note,
                note: value.note
            })) : []);
        for (const route of displays) {
            // Older hand-written rows sometimes embedded the next grouped step
            // in the first action ("4+SP > 6+Attack"). The generated map owns
            // grouping, so only atomic or explicitly leading follow-up routes
            // are accepted as supplements.
            const trimmed = String(route.display || "").trim();
            if (trimmed.includes(">") && !trimmed.startsWith(">")) continue;
            if (trimmed.startsWith(">")) {
                const followupBody = normalizeDisplay(trimmed).replace(/^>\s*/, "");
                entry.routes = entry.routes.filter(route => normalizeDisplay(route.display) !== followupBody);
                seen.clear();
                for (const route of entry.routes) seen.add(route.display);
            }
            pushRoute(entry.routes, seen, trimmed, {
                source: "community_sample",
                reason: route.reason,
                note: route.note,
                ...(route.evidence ? { evidence: route.evidence } : {})
            });
        }
        if (!entry.routes.length) continue;
        entries[id] = entry;
    }

    const unmappedClassicActionIds = Object.keys(runtime.actions || {})
        .filter(id => actionSet.has(id) && !entries[id])
        .map(Number).sort((left, right) => left - right);
    const output = {
        _meta: {
            schema: SCHEMA,
            character: runtime.character,
            fighter_id: runtime.fighter_id,
            generated_from: "ac_bcm",
            generated_at: options.generatedAt || new Date().toISOString(),
            ac_sha256: runtime.sources && runtime.sources.ac_sha256 || null,
            bcm_sha256: runtime.sources && runtime.sources.bcm_sha256 || null,
            modern_profile_order: MODERN_PROFILE_ORDER,
            supplement_policy: "community_sample_atomic_routes_only",
            unmapped_classic_action_count: unmappedClassicActionIds.length,
            unmapped_classic_action_ids: unmappedClassicActionIds,
            description: `${runtime.character} modern display mapping generated from game AC+BCM.`
        }
    };
    for (const id of Object.keys(entries).sort((left, right) => Number(left) - Number(right))) {
        const routes = entries[id].routes;
        for (const route of routes) assertValidRoute(normalizeDisplay(route.display), route);
        const classic = runtime.actions && runtime.actions[id];
        output[id] = {
            classic_display: typeof classic === "string" ? classic : null,
            modern_display: routes.map(route => route.display).join("/"),
            control_support: "classic_modern",
            source: routes.some(route => isCommunityAudit(route) || isCommunityAudit(route.verification))
                ? "ac_bcm+community_sample" : "ac_bcm",
            routes
        };
    }
    return output;
}

module.exports = {
    SCHEMA,
    MODERN_PROFILE_ORDER,
    buildModernDisplay,
    translateProfile
};
