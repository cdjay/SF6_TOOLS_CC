"use strict";

const assert = require("assert");
const core = require("./trigger_group_core.js");
const reportTool = require("./trigger_group_report.js");

const ref = id => ({ kind: "ref", object_id: id });
const num = value => ({ kind: "number", value });

// BCM: trigger index 0 -> Action 900, index 70 -> Action 910 (bit 6 of word 1).
// Group 5 selects both; group 60 (key >= Count) selects Action 910 only.
function bcm(keyed) {
    const groupItems = [
        { index: 5, key: 5, value: ref(20) },
        { index: 60, key: 60, value: ref(30) }
    ];
    return {
        dictionary_encoding: keyed ? "int-keyed-entries" : undefined,
        triggers: [
            { trigger_index: 0, native_action_id: 900 },
            { trigger_index: 70, native_action_id: 910 }
        ],
        objects: [
            { object_id: 10, object_type: core.GROUP_DICTIONARY, count: 2,
                items: keyed ? groupItems : [{ index: 0, value: { kind: "nil" } }, { index: 1, value: { kind: "nil" } }] },
            { object_id: 20, object_type: "BCM.TRIGGER_GROUP", fields: [{ name: "Flag", value: ref(21) }] },
            { object_id: 21, object_type: "BCM.TRIGGER_FLAG", fields: [
                { name: "flag0", value: num(1) }, { name: "flag1", value: num(64) },
                { name: "flag2", value: num(0) }, { name: "flag3", value: num(0) }] },
            { object_id: 30, object_type: "BCM.TRIGGER_GROUP", fields: [{ name: "Flag", value: ref(31) }] },
            { object_id: 31, object_type: "BCM.TRIGGER_FLAG", fields: [
                { name: "flag0", value: num(0) }, { name: "flag1", value: { kind: "number", value: "64" } },
                { name: "flag2", value: num(0) }, { name: "flag3", value: num(0) }] }
        ]
    };
}

// AC: Action 600 enables group 5 on hit (condition 3); Action 610 enables group 60.
const ac = {
    records: [
        { native_action_id: 600, source_scope: "character", action_ref: ref(1) },
        { native_action_id: 610, source_scope: "character", action_ref: ref(5) }
    ],
    objects: [
        { object_id: 1, object_type: "Action", fields: [{ name: "Keys", value: ref(2) }] },
        { object_id: 2, object_type: "List", items: [{ value: ref(3) }] },
        { object_id: 3, object_type: "CharacterAsset.TriggerKey", fields: [
            { name: "TriggerGroup", value: num(5) }, { name: "ConditionFlag", value: num(3) }] },
        { object_id: 5, object_type: "Action", fields: [{ name: "Keys", value: ref(6) }] },
        { object_id: 6, object_type: "List", items: [{ value: ref(7) }] },
        { object_id: 7, object_type: "CharacterAsset.TriggerKey", fields: [
            { name: "TriggerGroup", value: num(60) }, { name: "ConditionFlag", value: num(1) }] }
    ]
};

const keyed = core.buildRelations(ac, bcm(true));
assert.strictEqual(keyed.keyed, true);
assert.strictEqual(keyed.complete, true);
assert.deepStrictEqual([...keyed.groups.get(5)].sort(), [900, 910]);
assert.deepStrictEqual(core.enabledBy(keyed, 600, 910), ["5:3"]);
assert.deepStrictEqual(core.enabledBy(keyed, 610, 910), ["60:1"]);
assert.deepStrictEqual(core.enabledBy(keyed, 610, 900), []);

// A legacy dump enumerated get_Item(0..Count-1): keys 5 and 60 are lost.
const legacy = core.buildRelations(ac, bcm(false));
assert.strictEqual(legacy.keyed, false);
assert.strictEqual(legacy.complete, false);
assert.deepStrictEqual(legacy.missing_groups, [5, 60]);
const keys = core.actionTriggerKeys(ac);
assert.strictEqual(reportTool.classify(keyed, { parent: 600, child: 900 }, keys), "explained");
assert.strictEqual(reportTool.classify(legacy, { parent: 600, child: 900 }, keys), "unknown_missing_group");
assert.strictEqual(reportTool.classify(keyed, { parent: 610, child: 900 }, keys), "unexplained");

console.log("trigger group relation tests passed");
