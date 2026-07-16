"use strict";

const bcmCore = require("../bcm_catalog_builder/bcm_catalog_core.js");

const RUNTIME_SCHEMA = "sf6cc.action-runtime.v2";
const REPORT_SCHEMA = "sf6cc.action-runtime-compile-report.v1";
const RULES_VERSION = "sf6cc-ac-bcm-runtime-rules-v2";

const VALIDATION_FIELDS = [
    "force", "ignore", "is_holdable", "hold_partial_check", "charge_min", "charge_max",
    "perfect_min", "perfect_max", "ignore_prev_id", "ignore_prev_frames", "action_required",
    "no_combo_auto_advance", "require_absorb", "absorb_requires_combo", "optional_parent_ids",
    "optional_parent_motions", "follow_up_motion", "display_motion"
];

function sortedObject(input) {
    const output = {};
    for (const key of Object.keys(input || {}).sort((a, b) => Number(a) - Number(b))) {
        output[key] = input[key];
    }
    return output;
}

function triggerSuppliesDisplay(trigger, action) {
    return trigger && trigger.classic_display === action.classic_display;
}

function selectedTriggers(action) {
    const matching = (action.triggers || []).filter(trigger => triggerSuppliesDisplay(trigger, action));
    return matching.length ? matching : (action.triggers || []).filter(trigger => trigger.classic_display);
}

function isAirTrigger(trigger) {
    return Number(trigger && trigger.conditions && trigger.conditions.cond_owner_state_flags) === 4
        || (Number(trigger && trigger.conditions && trigger.conditions.category_flags) & 0x40000000) !== 0;
}

function inferBcmFollowups(bcmCatalog) {
    const result = {};
    const entries = Object.entries(bcmCatalog.actions || {})
        .map(([id, action]) => ({ id: Number(id), action, trigger: selectedTriggers(action)[0] }))
        .filter(item => item.trigger && item.action.classic_display)
        .sort((a, b) => a.id - b.id);
    for (const item of entries) {
        if (!selectedTriggers(item.action).some(trigger => Number(trigger.conditions && trigger.conditions.turn_around) === 2)) continue;
        const candidates = entries.filter(candidate => candidate.id < item.id && isAirTrigger(candidate.trigger) === isAirTrigger(item.trigger));
        let parent = candidates.find(candidate => candidate.id === item.id - 1) || null;
        if (!parent) {
            parent = candidates.slice().reverse().find(candidate =>
                candidate.action.classic_display === item.action.classic_display) || null;
        }
        result[String(item.id)] = {
            kind: "bcm-turn-around",
            parent_ids: parent ? [parent.id] : []
        };
    }

    // Some stance follow-ups use an identical BCM gate instead of turn_around=2.
    // A setup action such as 22+K and its later attack share the complete gate;
    // the later, differently displayed action is the follow-up.
    const groups = new Map();
    for (const item of entries) {
        if (result[String(item.id)]) continue;
        const conditions = item.trigger.conditions || {};
        if (Number(conditions.function_id) !== 2 || Number(conditions.turn_around) !== 0) continue;
        const key = JSON.stringify([
            conditions.function_id, conditions.category_flags, conditions.kind_level,
            conditions.kind_sub, conditions.action_status_sub, conditions.cond_owner_state_flags,
            conditions.action_dir
        ]);
        if (!groups.has(key)) groups.set(key, []);
        groups.get(key).push(item);
    }
    for (const group of groups.values()) {
        group.sort((a, b) => a.id - b.id);
        const setup = group.find(item => /^22\+/.test(item.action.classic_display));
        if (!setup) continue;
        for (const item of group) {
            if (item.id <= setup.id || item.action.classic_display === setup.action.classic_display) continue;
            result[String(item.id)] = { kind: "bcm-shared-gate", parent_ids: [setup.id] };
        }
    }
    return result;
}

function acBranchRelations(actionSource) {
    const objects = new Map((actionSource.objects || []).map(object => [object.object_id, object]));
    const roots = new Map();
    for (const record of actionSource.records || []) {
        if (record && record.source_scope === "character" && record.action_ref && record.action_ref.kind === "ref") {
            roots.set(String(Number(record.native_action_id)), record.action_ref.object_id);
        }
    }
    const relations = [];
    const seenRelations = new Set();
    for (const [sourceId, objectId] of roots) {
        const root = objects.get(objectId);
        const keys = root && (root.fields || []).find(field => field.name === "Keys");
        const pending = keys && keys.value && keys.value.kind === "ref" ? [keys.value.object_id] : [];
        const visited = new Set();
        while (pending.length) {
            const currentId = pending.pop();
            if (visited.has(currentId)) continue;
            visited.add(currentId);
            const object = objects.get(currentId);
            if (!object) continue;
            if (object.object_type === "CharacterAsset.BranchKey") {
                const fields = Object.fromEntries((object.fields || []).map(field => [field.name, field.value && field.value.value]));
                const targetId = Number(fields.Action);
                const type = Number(fields.Type);
                const key = `${sourceId}:${targetId}:${type}:${fields.Param01}:${fields.Param02}`;
                if (Number.isFinite(targetId) && !seenRelations.has(key)) {
                    seenRelations.add(key);
                    relations.push({
                        source_id: Number(sourceId), target_id: targetId, branch_type: type,
                        param01: Number(fields.Param01 || 0), param02: Number(fields.Param02 || 0)
                    });
                }
            }
            for (const field of object.fields || []) if (field.value && field.value.kind === "ref") pending.push(field.value.object_id);
            for (const item of object.items || []) if (item.value && item.value.kind === "ref") pending.push(item.value.object_id);
        }
    }
    return relations;
}

function inferHoldableSources(relations) {
    const bySource = new Map();
    for (const relation of relations) {
        if (!bySource.has(relation.source_id)) bySource.set(relation.source_id, { variants: new Set(), inputTransitions: new Set() });
        const group = bySource.get(relation.source_id);
        if (relation.branch_type === 29) group.variants.add(relation.target_id);
        if (relation.branch_type === 20) group.inputTransitions.add(relation.target_id);
    }
    const result = new Set();
    for (const [sourceId, group] of bySource) {
        const sharedTargets = [...group.variants].filter(targetId => group.inputTransitions.has(targetId));
        if (sharedTargets.length >= 2) result.add(String(sourceId));
    }
    return result;
}

function classifyBcmAction(action, compiledDisplay, followup) {
    const triggers = selectedTriggers(action);
    const isDrc = triggers.some(trigger =>
        Number(trigger.conditions && trigger.conditions.category_flags) === 0x100000
        && Number(trigger.conditions && trigger.conditions.function_id) === 13
        && Number(trigger.conditions && trigger.conditions.focus_consume) === 30000);
    const isRawDr = triggers.some(trigger =>
        Number(trigger.conditions && trigger.conditions.category_flags) === 0x200000
        && Number(trigger.conditions && trigger.conditions.function_id) === 13
        && Number(trigger.conditions && trigger.conditions.focus_consume) === 5000);
    const targetComboFollowup = Boolean(followup);
    const physicalButtonRequired = triggers.some(trigger => {
        const profile = trigger.classic_profile && trigger.profiles
            ? trigger.profiles[trigger.classic_profile] : null;
        return profile && typeof profile.button === "string" && profile.button !== "";
    });
    const chargeCommand = triggers.some(trigger => {
        const profile = trigger.classic_profile && trigger.profiles
            ? trigger.profiles[trigger.classic_profile] : null;
        return profile && profile.command && Number(profile.command.charge_bit || 0) !== 0;
    });
    return {
        display: compiledDisplay,
        display_source: "bcm",
        trigger_indices: triggers.map(trigger => Number(trigger.trigger_index)).sort((a, b) => a - b),
        system_action: isDrc ? "drc" : (isRawDr ? "raw_dr" : null),
        target_combo_followup: targetComboFollowup,
        target_combo_parent_status: targetComboFollowup
            ? ((followup.parent_ids || []).length ? "resolved" : "unresolved-from-current-dump") : null,
        optional_parent_ids: targetComboFollowup && (followup.parent_ids || []).length
            ? followup.parent_ids : undefined,
        followup_evidence: targetComboFollowup ? followup.kind : undefined,
        physical_button_required: physicalButtonRequired,
        charge_command: chargeCommand
    };
}

function acBranchEvidence(actionSource, aliases) {
    const objects = new Map((actionSource.objects || []).map(object => [object.object_id, object]));
    const records = new Map();
    for (const record of actionSource.records || []) {
        if (record && record.source_scope === "character" && record.action_ref && record.action_ref.kind === "ref") {
            records.set(String(Number(record.native_action_id)), record.action_ref.object_id);
        }
    }
    const evidence = [];
    for (const [aliasId, targetId] of Object.entries(aliases || {})) {
        const objectId = records.get(String(targetId));
        const root = objects.get(objectId);
        const keysField = root && (root.fields || []).find(field => field.name === "Keys");
        const pending = keysField && keysField.value && keysField.value.kind === "ref"
            ? [keysField.value.object_id] : [];
        const visited = new Set();
        let branchType = null;
        while (pending.length && branchType == null) {
            const currentId = pending.pop();
            if (visited.has(currentId)) continue;
            visited.add(currentId);
            const object = objects.get(currentId);
            if (!object) continue;
            if (object.object_type === "CharacterAsset.BranchKey") {
                const fields = Object.fromEntries((object.fields || []).map(field => [field.name, field.value && field.value.value]));
                if (Number(fields.Action) === Number(aliasId)) branchType = Number(fields.Type);
            }
            for (const field of object.fields || []) {
                if (field.value && field.value.kind === "ref") pending.push(field.value.object_id);
            }
            for (const item of object.items || []) {
                if (item.value && item.value.kind === "ref") pending.push(item.value.object_id);
            }
        }
        evidence.push({
            alias_action_id: Number(aliasId),
            target_action_id: Number(targetId),
            relation: "equivalent-action-variant",
            source: branchType == null ? "manual-exception" : "ac-branch",
            branch_type: branchType
        });
    }
    return evidence.sort((left, right) => left.alias_action_id - right.alias_action_id);
}

function applyExceptions(actionIds, actions, aliases, rules, exceptionTable, diagnostics) {
    const actionSet = new Set(actionIds.map(String));
    const stats = {
        entry_count: 0,
        display_override_count: 0,
        display_fill_count: 0,
        redundant_display_count: 0,
        validation_rule_count: 0,
        absorb_alias_count: 0
    };
    for (const [rawId, exception] of Object.entries(exceptionTable || {})) {
        if (!exception || typeof exception !== "object") continue;
        if (!/^-?\d+$/.test(rawId) || !Number.isSafeInteger(Number(rawId))) {
            diagnostics.push({ severity: "warning", code: "INVALID_EXCEPTION_ACTION_ID", value: rawId });
            continue;
        }
        const id = String(Number(rawId));
        if (!actionSet.has(id)) {
            diagnostics.push({ severity: "warning", code: "STALE_EXCEPTION_ACTION_ID", action_id: Number(id) });
            continue;
        }
        stats.entry_count += 1;
        const rule = rules[id] || { display: actions[id] || null, display_source: actions[id] ? "generated" : null };
        if (typeof exception.override_name === "string" && exception.override_name !== "") {
            const generatedDisplay = actions[id] || null;
            delete aliases[id];
            actions[id] = exception.override_name;
            rule.display = exception.override_name;
            if (generatedDisplay == null) stats.display_fill_count += 1;
            else if (generatedDisplay !== exception.override_name) stats.display_override_count += 1;
            else stats.redundant_display_count += 1;
            if (generatedDisplay !== exception.override_name) rule.display_source = "manual-exception";
            else rule.manual_display_redundant = true;
        }
        let hasValidationRule = false;
        for (const field of VALIDATION_FIELDS) {
            if (Object.prototype.hasOwnProperty.call(exception, field)) {
                rule[field] = exception[field];
                hasValidationRule = true;
            }
        }
        if (hasValidationRule) stats.validation_rule_count += 1;
        rule.manual_exception = true;
        rules[id] = rule;

        if (typeof exception.absorb_ids === "string") {
            for (const token of exception.absorb_ids.split(",")) {
                const trimmed = token.trim();
                if (trimmed === "") continue;
                if (!/^-?\d+$/.test(trimmed) || !Number.isSafeInteger(Number(trimmed))) {
                    diagnostics.push({
                        severity: "warning", code: "INVALID_EXCEPTION_ABSORB_ID",
                        action_id: Number(id), value: trimmed
                    });
                    continue;
                }
                const parsedAliasId = Number(trimmed);
                const aliasId = String(parsedAliasId);
                if (!actionSet.has(aliasId)) {
                    diagnostics.push({
                        severity: "warning", code: "STALE_EXCEPTION_ABSORB_ID",
                        action_id: Number(id), absorb_action_id: parsedAliasId
                    });
                    continue;
                }
                if (actions[aliasId] && aliasId !== String(id)) {
                    diagnostics.push({
                        severity: "warning", code: "EXCEPTION_ABSORB_CONFLICTS_WITH_DISPLAY",
                        action_id: Number(id), absorb_action_id: parsedAliasId,
                        absorb_display: actions[aliasId]
                    });
                    continue;
                }
                aliases[aliasId] = String(id);
                stats.absorb_alias_count += 1;
            }
        }
    }
    return stats;
}

function validateAliases(actionIds, actions, aliases, diagnostics) {
    const actionSet = new Set(actionIds.map(String));
    const reportedCycles = new Set();
    for (const [aliasId, initialTarget] of Object.entries(aliases)) {
        if (!actionSet.has(aliasId)) diagnostics.push({
            severity: "error", code: "ALIAS_ID_OUTSIDE_AC_CHARACTER_SCOPE", action_id: Number(aliasId)
        });
        let target = String(initialTarget);
        const path = [aliasId];
        const visited = new Set(path);
        while (Object.prototype.hasOwnProperty.call(aliases, target)) {
            path.push(target);
            if (visited.has(target)) {
                const cycle = [...path, String(aliases[target])];
                const signature = [...new Set(cycle)].sort((a, b) => Number(a) - Number(b)).join(",");
                if (!reportedCycles.has(signature)) {
                    reportedCycles.add(signature);
                    diagnostics.push({
                        severity: "error", code: "ALIAS_CYCLE", action_ids: cycle.map(Number)
                    });
                }
                target = null;
                break;
            }
            visited.add(target);
            target = String(aliases[target]);
        }
        if (target != null && !actions[target]) diagnostics.push({
            severity: "error", code: "ALIAS_TARGET_HAS_NO_DISPLAY",
            action_id: Number(aliasId), target_action_id: Number(target)
        });
    }
}

function appendSourceDiagnostics(actionSource, bcmCatalog, diagnostics) {
    if (actionSource.truncated === true) diagnostics.push({
        severity: "error", code: "AC_SOURCE_TRUNCATED"
    });
    if (actionSource.hard_gate_passed === false) diagnostics.push({
        severity: "error", code: "AC_SOURCE_HARD_GATE_FAILED"
    });
    if (!actionSource.unique_action_ids_by_scope.character.length) diagnostics.push({
        severity: "error", code: "AC_CHARACTER_ACTION_SCOPE_EMPTY"
    });
    if (bcmCatalog.source && bcmCatalog.source.complete === false) diagnostics.push({
        severity: "error", code: "BCM_SOURCE_INCOMPLETE"
    });
    for (const warning of bcmCatalog.warnings || []) {
        const isNormalization = /规范化/.test(warning);
        const coveredByCompletenessError = /truncated|hard_gate_passed=false/.test(warning);
        diagnostics.push({
            severity: (isNormalization || coveredByCompletenessError) ? "info" : "warning",
            code: "BCM_SOURCE_MESSAGE",
            message: warning
        });
    }
}

function compileFromCatalog(actionSource, bcmCatalog, exceptionTable, options) {
    options = options || {};
    exceptionTable = exceptionTable || {};
    const base = bcmCore.buildActionRuntimeCatalog(actionSource, bcmCatalog, {}, {
        actionSourceSha256: options.actionSourceSha256,
        characterName: options.characterName
    });
    const actions = { ...base.actions };
    const aliases = { ...base.aliases };
    const rules = {};
    const diagnostics = [];
    appendSourceDiagnostics(actionSource, bcmCatalog, diagnostics);
    const branchRelations = acBranchRelations(actionSource);
    const holdableSources = inferHoldableSources(branchRelations);
    const actionSet = new Set(base.action_ids.map(String));

    // Type 35 is an explicit runtime replacement. Unlike Type 29 state
    // variants it may legitimately change frame data, so it does not require
    // a structural fingerprint before inheriting the command.
    for (const relation of branchRelations) {
        const source = String(relation.source_id), target = String(relation.target_id);
        const isHoldLevel = relation.branch_type === 29 && holdableSources.has(source);
        if ((relation.branch_type === 35 || isHoldLevel) && actions[source] && actionSet.has(target)
            && !actions[target] && !aliases[target]) aliases[target] = source;
    }

    // Decode AC-only directional jump attacks and back-throw variants that BCM
    // reaches through an action branch rather than a separate trigger.
    const acDerivedCommands = [];
    for (const relation of branchRelations) {
        const source = String(relation.source_id), target = String(relation.target_id);
        if (!actions[source] || !actionSet.has(target) || actions[target] || aliases[target]) continue;
        let display = null;
        if (relation.branch_type === 20 && /^j\./i.test(actions[source])
            && (relation.param01 === 4 || relation.param01 === 8)) {
            const button = actions[source].replace(/^j\./i, "").replace(/^\d\+/, "");
            display = `j.${relation.param01 === 8 ? 6 : 4}+${button}`;
        } else if (relation.branch_type === 63 && relation.param02 === 1
            && /throw/i.test(actions[source]) && relation.param01 === 4) {
            display = "4THROW";
        }
        if (!display) continue;
        actions[target] = display;
        rules[target] = {
            display,
            display_source: "ac-branch-derived-command",
            force: true,
            branch_source_action_id: relation.source_id,
            branch_type: relation.branch_type
        };
        acDerivedCommands.push({ action_id: relation.target_id, source_action_id: relation.source_id, display, branch_type: relation.branch_type });
    }

    const followups = inferBcmFollowups(bcmCatalog);
    for (const [id, followup] of Object.entries(followups)) {
        if (actions[id] && !actions[id].startsWith(">")) actions[id] = `>${actions[id]}`;
        followup.display = actions[id] || null;
    }

    for (const [id, action] of Object.entries(bcmCatalog.actions || {})) {
        if (!actions[id]) continue;
        rules[id] = classifyBcmAction(action, actions[id], followups[id]);
        if (holdableSources.has(id)) {
            rules[id].is_holdable = true;
            rules[id].holdable_evidence = "ac-type29+type20-shared-variants";
        }
    }

    const exceptionStats = applyExceptions(
        base.action_ids, actions, aliases, rules, exceptionTable, diagnostics);
    for (const [aliasId, targetId] of Object.entries(aliases)) {
        rules[aliasId] = {
            ...(rules[aliasId] || {}),
            display: actions[targetId] || null,
            display_source: base.aliases[aliasId] === targetId
                ? "ac-derived-alias" : "manual-exception-alias",
            alias_target: Number(targetId),
            exact_id_or_alias_required: true
        };
    }
    validateAliases(base.action_ids, actions, aliases, diagnostics);
    const aliasEvidence = acBranchEvidence(actionSource, aliases);
    const bcmActionIdsOutsideAc = Object.keys(bcmCatalog.actions || {})
        .filter(id => !base.action_ids.includes(Number(id))).map(Number).sort((a, b) => a - b);
    for (const id of bcmActionIdsOutsideAc) diagnostics.push({
        severity: "warning", code: "BCM_ACTION_ID_OUTSIDE_AC_CHARACTER_SCOPE", action_id: id
    });

    const ambiguousBcmDisplays = [];
    for (const [id, action] of Object.entries(bcmCatalog.actions || {})) {
        const displays = [...new Set((action.triggers || [])
            .map(trigger => trigger.classic_display).filter(Boolean))].sort();
        if (displays.length > 1) ambiguousBcmDisplays.push({ action_id: Number(id), displays });
    }
    for (const item of ambiguousBcmDisplays) diagnostics.push({
        severity: "info", code: "MULTIPLE_BCM_CLASSIC_DISPLAYS",
        action_id: item.action_id, displays: item.displays
    });

    const targetComboIds = Object.entries(rules)
        .filter(([, rule]) => rule.target_combo_followup === true)
        .map(([id]) => Number(id)).sort((a, b) => a - b);
    const unclassifiedActionIds = base.action_ids
        .filter(id => !actions[String(id)] && !aliases[String(id)]);
    const status = diagnostics.some(item => item.severity === "error")
        ? "invalid" : (diagnostics.some(item => item.severity === "warning") ? "valid-with-warnings" : "valid");

    const runtime = {
        schema: RUNTIME_SCHEMA,
        compiler_rules_version: RULES_VERSION,
        character: base.character,
        fighter_id: base.fighter_id,
        policy: "universe:ac; commands:bcm; semantics:ac+bcm; manual-exceptions:last; off:forbidden",
        sources: base.sources,
        action_ids: base.action_ids,
        actions: sortedObject(actions),
        aliases: sortedObject(aliases),
        validation: { rules: sortedObject(rules) },
        evidence: {
            alias_relations: aliasEvidence,
            target_combo_followup_action_ids: targetComboIds,
            target_combo_relations: targetComboIds.map(actionId => ({
                action_id: actionId,
                parent_action_ids: rules[String(actionId)].optional_parent_ids || [],
                evidence: rules[String(actionId)].followup_evidence
            })),
            ac_derived_commands: acDerivedCommands,
            holdable_source_action_ids: [...holdableSources].map(Number).sort((a, b) => a - b),
            system_action_detection: "bcm-category+function+focus"
        },
        coverage: {
            ac_action_count: base.action_ids.length,
            bcm_display_count: Object.keys(base.actions).length,
            compiled_display_count: Object.keys(actions).length,
            alias_count: Object.keys(aliases).length,
            ac_derived_alias_count: base.coverage.ac_derived_alias_count,
            manual_exception_entry_count: exceptionStats.entry_count,
            manual_display_override_count: exceptionStats.display_override_count,
            manual_display_fill_count: exceptionStats.display_fill_count,
            redundant_manual_display_count: exceptionStats.redundant_display_count,
            manual_validation_rule_count: exceptionStats.validation_rule_count,
            manual_absorb_alias_count: exceptionStats.absorb_alias_count,
            ac_action_ids_without_command_semantics_count: unclassifiedActionIds.length
        }
    };
    const report = {
        schema: REPORT_SCHEMA,
        compiler_rules_version: RULES_VERSION,
        status,
        character: runtime.character,
        fighter_id: runtime.fighter_id,
        summary: runtime.coverage,
        inventory: {
            ac_action_ids_without_command_semantics: unclassifiedActionIds
        },
        unresolved: {
            bcm_action_ids_outside_ac_character_scope: bcmActionIdsOutsideAc,
            target_combo_followups_without_parent_context: targetComboIds
                .filter(actionId => rules[String(actionId)].target_combo_parent_status !== "resolved")
                .map(actionId => ({ action_id: actionId, status: "unresolved-from-current-dump" })),
            ambiguous_bcm_displays: ambiguousBcmDisplays
        },
        diagnostics
    };
    return { runtime, report };
}

function buildLegacyExceptionTable(runtime) {
    const output = {};
    const legacyFields = new Set(VALIDATION_FIELDS);
    for (const [id, display] of Object.entries(runtime.actions || {})) {
        const entry = { override_name: display };
        const rule = runtime.validation && runtime.validation.rules && runtime.validation.rules[id] || {};
        for (const field of legacyFields) {
            if (rule[field] !== undefined && rule[field] !== null) entry[field] = rule[field];
        }
        output[id] = entry;
    }
    const absorbedByTarget = {};
    for (const [aliasId, targetId] of Object.entries(runtime.aliases || {})) {
        if (!absorbedByTarget[targetId]) absorbedByTarget[targetId] = [];
        absorbedByTarget[targetId].push(Number(aliasId));
        output[aliasId] = {
            override_name: runtime.actions[targetId] || "Unknown",
            force: true
        };
    }
    for (const [targetId, aliasIds] of Object.entries(absorbedByTarget)) {
        if (!output[targetId]) output[targetId] = { override_name: runtime.actions[targetId] || "Unknown" };
        output[targetId].absorb_ids = aliasIds.sort((a, b) => a - b).join(",");
    }
    return sortedObject(output);
}

function compile(actionSource, bcmSource, exceptionTable, options) {
    options = options || {};
    const bcmCatalog = bcmCore.buildCatalog(bcmSource, {
        characterName: options.characterName,
        sourceSha256: options.bcmSourceSha256,
        generatedAt: options.generatedAt
    });
    return compileFromCatalog(actionSource, bcmCatalog, exceptionTable, options);
}

module.exports = {
    RUNTIME_SCHEMA,
    REPORT_SCHEMA,
    RULES_VERSION,
    compile,
    compileFromCatalog,
    buildLegacyExceptionTable
};
