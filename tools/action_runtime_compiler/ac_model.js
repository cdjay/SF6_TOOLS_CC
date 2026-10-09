"use strict";

// Character-scope view of one AC+BCM dump for semantic analysis: every
// Action's frame count and keys (BranchKey and DynamicTriggerKey with their
// parameters and, in v2 exports, frame windows; TriggerKey groups), the
// reverse branch index, BCM triggers per Action and trigger-group relations.
// Common-scope Actions (gBattle.Resource.Data[6]) are kept apart because
// their IDs can overlap character IDs.

const bcmCore = require("../bcm_catalog_builder/bcm_catalog_core.js");
const triggerGroupCore = require("./trigger_group_core.js");

const BRANCH_TYPES = new Set(["CharacterAsset.BranchKey", "CharacterAsset.DynamicTriggerKey"]);

function scalars(object) {
    const result = {};
    for (const field of object && object.fields || []) {
        const value = field.value;
        if (value && value.kind !== "ref" && value.kind !== "nil") result[field.name] = value.value;
    }
    return result;
}

function number(value, fallback = 0) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : fallback;
}

function frameWindow(fields) {
    const start = fields.StartFrame;
    const end = fields.EndFrame;
    return start === undefined || end === undefined ? null : { start: number(start), end: number(end) };
}

function scanAction(objects, rootId, actionId) {
    const root = objects.get(rootId);
    const rootFields = scalars(root);
    const action = { id: actionId, frame: number(rootFields.Frame, null), branches: [], triggerKeys: [] };
    const pending = [rootId];
    const visited = new Set();
    while (pending.length) {
        const id = pending.pop();
        if (visited.has(id)) continue;
        visited.add(id);
        const object = objects.get(id);
        if (!object) continue;
        if (BRANCH_TYPES.has(object.object_type)) {
            const fields = scalars(object);
            action.branches.push({
                source: actionId,
                target: number(fields.Action, -1),
                type: number(fields.Type, -1),
                attr: number(fields.Attr),
                action_frame: number(fields.ActionFrame),
                params: [0, 1, 2, 3, 4, 5].map(index => number(fields[`Param0${index}`])),
                trigger_id: number(fields.TriggerID, -1),
                window: frameWindow(fields),
                dynamic: object.object_type === "CharacterAsset.DynamicTriggerKey"
            });
        } else if (object.object_type === "CharacterAsset.TriggerKey") {
            const fields = scalars(object);
            action.triggerKeys.push({
                group: number(fields.TriggerGroup, -1),
                condition: number(fields.ConditionFlag),
                window: frameWindow(fields)
            });
        }
        for (const field of object.fields || []) if (field.value && field.value.kind === "ref") pending.push(field.value.object_id);
        for (const item of object.items || []) if (item.value && item.value.kind === "ref") pending.push(item.value.object_id);
    }
    return action;
}

function buildModel(ac, bcm) {
    const objects = new Map((ac && ac.objects || []).map(object => [object.object_id, object]));
    const actions = new Map();
    const commonActions = new Map();
    for (const record of ac && ac.records || []) {
        if (!record || !record.action_ref || record.action_ref.kind !== "ref") continue;
        const id = number(record.native_action_id, null);
        if (id === null) continue;
        const target = record.source_scope === "character" ? actions : commonActions;
        if (!target.has(id)) target.set(id, scanAction(objects, record.action_ref.object_id, id));
    }
    const catalog = bcmCore.buildCatalog(bcm);
    const bcmActions = new Map(Object.entries(catalog.actions || {}).map(([id, entry]) => [Number(id), entry]));
    return {
        fighter_id: number(ac && ac.fighter_id, null),
        keyed_groups: triggerGroupCore.keyedEncoding(bcm),
        frame_windows: String(ac && ac.inherited_fields || "") === "game-namespaces.v2",
        actions,
        incoming: reverseIndex(actions),
        common: { actions: commonActions, incoming: reverseIndex(commonActions) },
        bcmActions,
        groups: triggerGroupCore.buildRelations(ac, bcm)
    };
}

function reverseIndex(actions) {
    const incoming = new Map();
    for (const action of actions.values()) {
        for (const branch of action.branches) {
            if (!incoming.has(branch.target)) incoming.set(branch.target, []);
            incoming.get(branch.target).push(branch);
        }
    }
    return incoming;
}

function classicTrigger(model, actionId) {
    const entry = model.bcmActions.get(Number(actionId));
    return entry ? (entry.triggers || []).find(trigger => trigger.classic_display) || null : null;
}

function branchesBetween(model, source, target) {
    const action = model.actions.get(Number(source));
    return action ? action.branches.filter(branch => branch.target === Number(target)) : [];
}

module.exports = { scalars, buildModel, classicTrigger, branchesBetween };
