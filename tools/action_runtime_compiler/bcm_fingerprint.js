"use strict";

// Fingerprint of a fighter's BCM trigger table that the runtime can compute
// from live game memory (autorun/func/ComboTrials/DataBuildGuard.lua). A
// command table whose fingerprint differs from the running game was
// generated from other game data and must be regenerated.
//
// Definition: the action_id of every trigger with a positive integer
// action_id, sorted ascending, joined with "," and hashed with FNV-1a 32-bit.
// Trigger order and empty trigger slots do not matter.

const ALGORITHM = "bcm-trigger-action-multiset.fnv1a32.v1";

function fnv1a32(text) {
    let hash = 0x811c9dc5;
    for (const byte of Buffer.from(String(text), "utf8")) {
        hash ^= byte;
        hash = Math.imul(hash, 0x01000193) >>> 0;
    }
    return hash.toString(16).padStart(8, "0");
}

function fromActionIds(actionIds) {
    const ids = actionIds.map(Number)
        .filter(id => Number.isInteger(id) && id > 0)
        .sort((left, right) => left - right);
    return { algorithm: ALGORITHM, count: ids.length, hash: fnv1a32(ids.join(",")) };
}

// bcmSource: a full BCM dump (sf6cr.bcm-full.v2) with triggers[].native_action_id.
function fromBcmSource(bcmSource) {
    if (!bcmSource || !Array.isArray(bcmSource.triggers)) {
        throw new Error("BCM dump 缺少 triggers，无法计算运行时指纹。");
    }
    return fromActionIds(bcmSource.triggers.map(trigger => trigger && trigger.native_action_id));
}

module.exports = { ALGORITHM, fnv1a32, fromActionIds, fromBcmSource };
