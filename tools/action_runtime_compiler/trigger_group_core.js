"use strict";

// Native cancel / follow-up relations: an AC TriggerKey on an Action enables a
// BCM TRIGGER_GROUP while the key is active; the group's flag bits select BCM
// triggers, and each trigger starts one Action. Together they say which
// Actions may follow which, which is what hand-written optional_parent_ids
// and the generator's Action-ID adjacency heuristics approximate today.
//
// Dumps exported before tools/acbcm_exporter fixed dictionary enumeration
// lost every trigger group whose key is >= the dictionary Count; such dumps
// are reported as incomplete instead of being trusted. The first fixed
// exporter (dictionary_encoding "int-keyed-entries", 2026-10-09) also emitted
// the never-used slots of this struct-valued dictionary (key 0, empty flags);
// game data is loaded without removals, so its live entries are exactly the
// slots below Count. "int-keyed-entries.v2" exports stop at the used slots.

const GROUP_DICTIONARY = "System.Collections.Generic.Dictionary`2<System.Int32,BCM.TRIGGER_GROUP>";

function objectIndex(source) {
    return new Map((source && source.objects || []).map(object => [object.object_id, object]));
}

function fieldValue(object, name) {
    const field = (object && object.fields || []).find(item => item.name === name);
    return field ? field.value : undefined;
}

function scalar(value) {
    return value && value.kind !== "ref" && value.kind !== "nil" ? value.value : undefined;
}

function keyedEncoding(bcm) {
    return /^int-keyed-entries(?:\.v\d+)?$/.test(String(bcm && bcm.dictionary_encoding || ""));
}

function liveItems(bcm, dictionary) {
    const items = dictionary && dictionary.items || [];
    if (!dictionary || dictionary.used_slots !== undefined
        || String(bcm && bcm.dictionary_encoding || "") !== "int-keyed-entries") return items;
    const count = Number(dictionary.count);
    if (!Number.isInteger(count) || items.length <= count
        || !items.every(item => item && Number.isInteger(Number(item.entry_index)))) return items;
    return items.filter(item => Number(item.entry_index) < count);
}

function triggerActions(bcm) {
    const result = new Map();
    for (const trigger of bcm && bcm.triggers || []) {
        const index = Number(trigger && trigger.trigger_index);
        const action = Number(trigger && trigger.native_action_id);
        if (Number.isInteger(index) && Number.isInteger(action) && action > 0) result.set(index, action);
    }
    return result;
}

function flagBits(flagObject, objects) {
    const words = [];
    for (let word = 0; word < 4; word += 1) words.push(scalar(fieldValue(flagObject, `flag${word}`)));
    // Some captures only fill the nested UInt64s copy.
    const nested = fieldValue(flagObject, "flags");
    if (nested && nested.kind === "ref") {
        const extended = objects.get(nested.object_id);
        for (let word = 0; word < 4; word += 1) {
            if (words[word] === undefined || words[word] === null) words[word] = scalar(fieldValue(extended, `p${word}`));
        }
    }
    const bits = [];
    words.forEach((raw, word) => {
        if (raw === undefined || raw === null) return;
        let value = BigInt(raw);
        for (let bit = 0; value > 0n; bit += 1, value >>= 1n) {
            if (value & 1n) bits.push(word * 64 + bit);
        }
    });
    return bits;
}

// group id -> Set of Action IDs, plus whether the dump carried real keys.
function triggerGroups(bcm) {
    const objects = objectIndex(bcm);
    const actions = triggerActions(bcm);
    const dictionary = (bcm && bcm.objects || []).find(object => object.object_type === GROUP_DICTIONARY);
    const keyed = Boolean(keyedEncoding(bcm) || dictionary && dictionary.dictionary === true);
    const groups = new Map();
    for (const item of liveItems(bcm, dictionary)) {
        if (!item || !item.value || item.value.kind !== "ref") continue;
        const groupId = Number(keyed && item.key !== undefined ? item.key : item.index);
        const group = objects.get(item.value.object_id);
        const flag = fieldValue(group, "Flag");
        const flagObject = flag && flag.kind === "ref" ? objects.get(flag.object_id) : null;
        const members = new Set();
        for (const bit of flagObject ? flagBits(flagObject, objects) : []) {
            if (actions.has(bit)) members.add(actions.get(bit));
        }
        groups.set(groupId, members);
    }
    return { groups, keyed, enumerated: dictionary ? Number(dictionary.count) : 0 };
}

// Character Action -> [{ group, condition }] from AC TriggerKeys.
function actionTriggerKeys(ac) {
    const objects = objectIndex(ac);
    const result = new Map();
    for (const record of ac && ac.records || []) {
        if (!record || record.source_scope !== "character" || !record.action_ref
            || record.action_ref.kind !== "ref") continue;
        const source = Number(record.native_action_id);
        const root = objects.get(record.action_ref.object_id);
        const keys = fieldValue(root, "Keys");
        const pending = keys && keys.kind === "ref" ? [keys.object_id] : [];
        const visited = new Set();
        while (pending.length) {
            const id = pending.pop();
            if (visited.has(id)) continue;
            visited.add(id);
            const object = objects.get(id);
            if (!object) continue;
            if (object.object_type === "CharacterAsset.TriggerKey") {
                const group = Number(scalar(fieldValue(object, "TriggerGroup")));
                if (Number.isInteger(group) && group >= 0) {
                    if (!result.has(source)) result.set(source, []);
                    result.get(source).push({ group, condition: Number(scalar(fieldValue(object, "ConditionFlag")) || 0) });
                }
            }
            for (const field of object.fields || []) if (field.value && field.value.kind === "ref") pending.push(field.value.object_id);
            for (const item of object.items || []) if (item.value && item.value.kind === "ref") pending.push(item.value.object_id);
        }
    }
    return result;
}

function buildRelations(ac, bcm) {
    const { groups, keyed, enumerated } = triggerGroups(bcm);
    const keys = actionTriggerKeys(ac);
    const referenced = new Set();
    const missing = new Set();
    const enables = new Map();
    for (const [source, list] of keys) {
        for (const { group, condition } of list) {
            referenced.add(group);
            if (!groups.has(group)) { missing.add(group); continue; }
            if (!enables.has(source)) enables.set(source, new Map());
            for (const target of groups.get(group)) {
                const conditions = enables.get(source);
                if (!conditions.has(target)) conditions.set(target, new Set());
                conditions.get(target).add(`${group}:${condition}`);
            }
        }
    }
    return {
        keyed,
        enumerated_groups: enumerated,
        complete: missing.size === 0,
        referenced_groups: [...referenced].sort((a, b) => a - b),
        missing_groups: [...missing].sort((a, b) => a - b),
        groups,
        enables
    };
}

function enabledBy(relations, source, target) {
    const targets = relations.enables.get(Number(source));
    return targets ? [...(targets.get(Number(target)) || [])] : [];
}

module.exports = {
    GROUP_DICTIONARY, keyedEncoding, liveItems, triggerActions, triggerGroups, actionTriggerKeys, buildRelations, enabledBy
};
