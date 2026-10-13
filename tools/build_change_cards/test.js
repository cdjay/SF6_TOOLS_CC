"use strict";
const assert = require("assert");
const { inputContexts, references } = require("./research.js");
const { displayName, inputIcons } = require("./build.js");
const web = { actions: { 10: { classic: { display: "214+LP" }, move_id: "a" } }, moves: { a: { name: "original" } } };
const edges = [
    { source: 10, target: 11, relation: "branch" },
    { source: 11, target: 12, relation: "shot_action_reference" },
    { source: 12, target: 13, relation: "lock_type1_param01_reference_unapproved" },
    { source: 13, target: 12, relation: "branch" }
];
const contexts = inputContexts(13, edges, web);
assert.strictEqual(contexts.length, 1);
assert.strictEqual(contexts[0].path.length, 3);
assert.strictEqual(contexts[0].identity_approved, false);
assert.deepStrictEqual(inputContexts(999, edges, web), []);
const scalar = (name, value) => ({ name, value: { kind: "number", value } });
const graph = { records: [{ source_scope: "character", native_action_id: 10, action_ref: { object_id: 1 } }], objects: [
    { object_id: 1, object_type: "FAB.ACTION", fields: [{ name: "Keys", value: { kind: "ref", object_id: 2 } }] },
    { object_id: 2, object_type: "List", items: [{ index: 0, value: { kind: "ref", object_id: 3 } }] },
    { object_id: 3, object_type: "CharacterAsset.ShotKey", fields: [scalar("ActionId", 12), scalar("StartFrame", 8), scalar("EndFrame", 9)] }
] };
assert.deepStrictEqual(references(graph), [{ source: 10, target: 12, relation: "shot_action_reference", start: 8, end: 9 }]);
const names = { names: { Demo: { "[t]原名": "Official Move" } } };
assert.strictEqual(displayName({ key: "Demo" }, "原名", names), "Official Move");
assert.strictEqual(displayName({ key: "Demo" }, "unknown", names), "unknown");
assert.strictEqual(displayName({ key: "Demo" }, "原系列", { names: { Demo: { "[t]弱 原系列": "L Official Family" } } }), "Official Family");
assert.ok(inputIcons("214+PP", "../").includes("../assets/inputs/P.png"));
assert.ok(inputIcons("[4]6+HP", "../").includes("4_HOLD.png"));
assert.strictEqual(inputIcons("内部动作1216", ""), "");
console.log("change-card context, naming and input-icon tests passed");
