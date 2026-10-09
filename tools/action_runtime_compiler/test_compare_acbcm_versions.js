"use strict";

const assert = require("assert");
const compare = require("./compare_acbcm_versions.js");

// Minimal AC object graph: Action 600 (Frame 30) has two Type-20 BranchKeys
// and one TriggerKey for group 15; Action 601 has nothing.
const ref = id => ({ kind: "ref", object_id: id });
const num = value => ({ kind: "number", value });
const ac = {
    records: [
        { native_action_id: 600, source_scope: "character", action_ref: ref(1) },
        { native_action_id: 601, source_scope: "character", action_ref: ref(10) },
        { native_action_id: 17, source_scope: "common", action_ref: ref(20) }
    ],
    objects: [
        { object_id: 1, object_type: "CharacterAsset.ActionData", fields: [
            { name: "Frame", value: num(30) }, { name: "Keys", value: ref(2) }] },
        { object_id: 2, object_type: "List", items: [{ value: ref(3) }, { value: ref(4) }, { value: ref(5) }] },
        { object_id: 3, object_type: "CharacterAsset.BranchKey", fields: [{ name: "Type", value: num(20) }] },
        { object_id: 4, object_type: "CharacterAsset.BranchKey", fields: [{ name: "Type", value: num(20) }] },
        { object_id: 5, object_type: "CharacterAsset.TriggerKey", fields: [{ name: "TriggerGroup", value: num(15) }] },
        { object_id: 10, object_type: "CharacterAsset.ActionData", fields: [{ name: "Frame", value: num(12) }] },
        { object_id: 20, object_type: "CharacterAsset.ActionData", fields: [{ name: "Frame", value: num(99) }] }
    ]
};
const signatures = compare.actionSignatures(ac);
assert.deepStrictEqual([...signatures.keys()].sort(), [600, 601], "common Actions are not compared");
assert.deepStrictEqual(signatures.get(600), { structure: "B:20x2|T:15", full: "30|B:20x2|T:15" });
assert.deepStrictEqual(signatures.get(601), { structure: "B:|T:", full: "12|B:|T:" });

const s = (frame, structure) => ({ structure, full: `${frame}|${structure}` });
const fingerprint = { algorithm: "x", count: 3, hash: "aaaaaaaa" };
const before = { fingerprint, signatures: new Map([
    [600, s(30, "B:20x2|T:15")], [601, s(12, "B:0x1|T:")], [602, s(40, "B:29x1|T:32")], [700, s(9, "B:2x1|T:")]
]) };
const after = { fingerprint: { ...fingerprint, count: 4, hash: "bbbbbbbb" }, signatures: new Map([
    [600, s(30, "B:20x2|T:15")], [601, s(14, "B:0x1|T:")], [603, s(40, "B:29x1|T:32")], [700, s(9, "B:4x1|T:")]
]) };
const references = [
    { file: "exceptions/Test.json", id: 602, where: "key" },
    { file: "exceptions/Test.json", id: 601, where: "600.absorb_ids" },
    { file: "command_display_overrides/Test.json", id: 700, where: "entries" }
];
const result = compare.compareFighter("Test", before, after, references);
assert.strictEqual(result.status, "changed");
assert.deepStrictEqual(result.removed_action_ids, [602]);
assert.deepStrictEqual(result.changed_action_ids, [700]);
assert.deepStrictEqual(result.frames_changed_action_ids, [601], "a frame-only change is a balance change");
assert.deepStrictEqual(result.added_action_ids, [603]);
assert.strictEqual(result.suggested_new_ids[602], 603, "the moved Action is found by its signature");
assert.strictEqual(result.suggested_new_ids[700], null);
assert.deepStrictEqual(result.impacted_references.map(item => [item.id, item.suggested_id]), [[602, 603], [700, null]]);
assert.strictEqual(result.bcm_fingerprint.changed, true);

const quiet = compare.compareFighter("Test", before, { fingerprint, signatures: before.signatures }, references);
assert.strictEqual(quiet.status, "unchanged");
assert.strictEqual(quiet.impacted_references.length, 0);

const text = compare.markdown({
    old_version: "2026-08-03", new_version: "2026-10-13",
    summary: { unchanged: [], frames_changed: [], changed: ["Test"], new: ["Arjun"], missing_in_new: [] },
    fighters: [{ fighter_id: 99, ...result }]
});
assert.ok(text.includes("新角色：Arjun") && text.includes("602→603") && text.includes("建议 603"));

console.log("AC/BCM version comparison tests passed");
