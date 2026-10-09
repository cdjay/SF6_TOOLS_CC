"use strict";

const assert = require("assert");
const tool = require("./novel_structure_report.js");

const ref = id => ({ kind: "ref", object_id: id });
const num = value => ({ kind: "number", value });

function key(id, type, fields) {
    return { object_id: id, object_type: type,
        fields: Object.entries(fields).map(([name, value]) => ({ name, value: num(value) })) };
}

// One character Action with the given keys, plus a common Action whose keys
// must never count as fighter-specific.
function ac(keys, commonKeys = []) {
    const objects = [
        { object_id: 1, object_type: "FAB.ACTION", fields: [{ name: "Keys", value: ref(2) }] },
        { object_id: 2, object_type: "List", items: keys.map(item => ({ value: ref(item.object_id) })) },
        { object_id: 3, object_type: "FAB.ACTION", fields: [{ name: "Keys", value: ref(4) }] },
        { object_id: 4, object_type: "List", items: commonKeys.map(item => ({ value: ref(item.object_id) })) },
        ...keys, ...commonKeys
    ];
    return {
        records: [
            { native_action_id: 900, source_scope: "character", action_ref: ref(1) },
            { native_action_id: 50, source_scope: "common", action_ref: ref(3) }
        ],
        objects
    };
}

const hold = id => key(id, "CharacterAsset.BranchKey", { Type: 20, Attr: 0, Action: 906, Param01: 16, Param03: 1, TriggerID: -1 });
const cancel = id => key(id, "CharacterAsset.TriggerKey", { TriggerGroup: 5, ConditionFlag: 3 });

assert.strictEqual(tool.branchShape({ Type: 20, Attr: 288, ActionFrame: 0, Param01: 16, Param03: 1, TriggerID: -1 }),
    "T20|attr=288|frame=0|params=0n0n00|trigger=-");

const scans = [
    { character: "Ryu", scan: tool.scanAc(ac([hold(10), cancel(11)])) },
    { character: "Ken", scan: tool.scanAc(ac([hold(10), cancel(11)])) },
    { character: "Arjun", scan: tool.scanAc(ac([
        hold(10), cancel(11),
        key(12, "CharacterAsset.BranchKey", { Type: 70, Attr: 0, Action: 950, Param00: 2, TriggerID: -1 }),
        key(13, "CharacterAsset.TriggerKey", { TriggerGroup: 9, ConditionFlag: 4096 }),
        key(14, "CharacterAsset.ArjunStanceKey", { Stance: 1 })
    ], [key(15, "CharacterAsset.CommonOnlyKey", { Value: 1 })])) }
];

const [arjun] = tool.compare(scans, ["Arjun"]);
assert.strictEqual(arjun.character, "Arjun");
assert.deepStrictEqual(arjun.novel.objectTypes.map(item => item.key), ["CharacterAsset.ArjunStanceKey"],
    "common Actions never make a structure fighter-specific");
assert.deepStrictEqual(arjun.novel.branchShapes.map(item => item.key), ["T70|attr=0|frame=0|params=n00000|trigger=-"]);
assert.deepStrictEqual(arjun.novel.branchShapes[0].examples[0], { action_id: 900, target_action_id: 950, params: [2, 0, 0, 0, 0, 0] });
assert.deepStrictEqual(arjun.novel.triggerConditions.map(item => item.key), ["4096"]);

// Without targets each fighter is compared with all the others.
const all = tool.compare(scans, null);
assert.strictEqual(all.length, 3);
assert.strictEqual(all[0].novel.branchShapes.length + all[1].novel.branchShapes.length, 0);

// Two new fighters sharing a mechanic both report it.
scans.push({ character: "NewTwo", scan: tool.scanAc(ac([
    key(12, "CharacterAsset.BranchKey", { Type: 70, Attr: 0, Action: 951, Param00: 2, TriggerID: -1 })])) });
const shared = tool.compare(scans, ["Arjun", "NewTwo"]);
assert(shared.every(fighter => fighter.novel.branchShapes.some(item => item.key.startsWith("T70|"))));

const text = tool.markdown({ version: "2026-10-13", compared_characters: ["Ryu", "Ken", "Arjun"], fighters: [arjun] });
assert(text.includes("## Arjun（3 项）") && text.includes("900→950（参数 2,0,0,0,0,0）"));

console.log("novel structure report tests passed");
