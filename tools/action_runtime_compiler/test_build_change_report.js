"use strict";
const assert = require("assert");
const core = require("./build_change_report.js");
function source(offset = 0) {
    const scalar = (name, value) => ({ name, value: { kind: "number", value } });
    return { records: [
        { source_scope: "character", resource_index: 0, style_index: 0, native_action_id: 600, action_ref: { kind: "ref", object_id: 1 + offset } },
        { source_scope: "character", resource_index: 0, style_index: 1, native_action_id: 600, action_ref: { kind: "ref", object_id: 1 + offset } },
        { source_scope: "common", resource_index: 6, style_index: 0, native_action_id: 600, action_ref: { kind: "ref", object_id: 1 + offset } }
    ], objects: [
        { object_id: 1 + offset, object_type: "FAB.ACTION", fields: [scalar("ActionID", 600), scalar("Frame", 30),
            { name: "Keys", value: { kind: "ref", object_id: 2 + offset } }] },
        { object_id: 2 + offset, object_type: "List", items: [{ index: 0, value: { kind: "ref", object_id: 3 + offset } }] },
        { object_id: 3 + offset, object_type: "CharacterAsset.BranchKey", fields: [scalar("Type", 20), scalar("Action", 601),
            scalar("Param00", 4), scalar("p00_ALIAS", 4), { name: "Vector", value: { kind: "ref", object_id: 4 + offset } }] },
        { object_id: 4 + offset, object_type: "Vector", fields: [scalar("x", 15), scalar("y", 0)] }
    ] };
}
const old = source(), next = source(100);
assert.deepStrictEqual(core.compareAc(old, next).changes, [], "Object IDs are not gameplay facts");
next.objects[2].fields.push({ name: "StartFrame", value: { kind: "number", value: 1 } });
assert.deepStrictEqual(core.compareAc(old, next).changes, [], "New exporter field cannot become a balance change");
next.objects[2].fields.find(field => field.name === "p00_ALIAS").value.value = 9;
assert.deepStrictEqual(core.compareAc(old, next).changes, [], "Repeated alias memory is not counted twice");
next.objects[3].fields[0].value.value = 16;
let change = core.compareAc(old, next);
assert.strictEqual(change.changes.length, 3, "Scope/style variants stay separate");
assert.strictEqual(change.changes[0].keys["CharacterAsset.BranchKey"].added[0].fields.Vector.fields.x, 16);
assert.strictEqual(change.changes[0].keys["CharacterAsset.BranchKey"].removed[0].fields.Vector.fields.x, 15);
assert.strictEqual(change.changes[0].auto_approved, false);
const oldVfx = source(), newVfx = source(100);
oldVfx.objects[2].object_type = "app.battle.VfxKey";
newVfx.objects[2].object_type = "app.battle.VfxKey";
newVfx.objects[2].fields.find(field => field.name === "Param00").value.value = 8;
assert.ok(core.compareAc(oldVfx, newVfx).changes[0].keys["app.battle.VfxKey"], "Presentation-layer keys outside CharacterAsset must not be omitted");
assert.deepStrictEqual(core.multisetDiff([{ a: 1 }, { a: 2 }], [{ a: 2 }, { a: 1 }]), { removed: [], added: [] });
assert.deepStrictEqual(core.multisetDiff([{ a: 1 }, { a: 1 }], [{ a: 1 }]), { removed: [{ a: 1 }], added: [] });
const noFields = new Map([[1, { object_type: "Key", fields: null }]]);
const emptyFields = new Map([[2, { object_type: "Key", fields: [], items: [] }]]);
assert.deepStrictEqual(core.projection(noFields, null)(1), core.projection(emptyFields, null)(2), "Empty reflection containers are exporter shape, not gameplay");
const newType = source(100);
newType.objects[1].items.push({ index: 1, value: { kind: "ref", object_id: 105 } });
newType.objects.push({ object_id: 105, object_type: "CharacterAsset.MotionDataKey",
    fields: [{ name: "StartFrame", value: { kind: "number", value: 23 } }] });
change = core.compareAc(old, newType);
assert.deepStrictEqual(change.changes, [], "Single-capture node types are not confirmed gameplay changes");
assert.strictEqual(change.incomparable_keys[0].after[0].fields.StartFrame, 23, "Keep full evidence for incomparable nodes");
const moved = source(100);
moved.records[0].native_action_id = 602;
moved.objects[0].fields[0].value.value = 602;
change = core.compareAc(old, moved);
assert.ok(change.identity_candidates.some(item => item.old_action_id === 600 && item.new_action_id_candidates.includes(602)));
assert.ok(change.identity_candidates.every(item => item.auto_approved === false));
assert.strictEqual(change.changes.find(item => item.added_locator).snapshot.fields.Frame, 30);
const bcmBefore = { objects: [{ object_id: 1, object_type: "Trigger", fields: [
    { name: "profile", value: { kind: "ref", object_id: 2 } }
] }, { object_id: 2, object_type: "Profile", fields: [{ name: "flags", value: { kind: "number", value: "18446744073709551615" } }] }],
triggers: [{ native_action_id: 600, trigger_index: 0, trigger_ref: { kind: "ref", object_id: 1 } }] };
const bcmAfter = structuredClone(bcmBefore);
bcmAfter.objects[1].fields[0].value.value = "18446744073709551614";
change = core.compareBcm(bcmBefore, bcmAfter);
assert.strictEqual(change[0].fields[0].before, "18446744073709551615");
assert.strictEqual(change[0].fields[0].after, "18446744073709551614");
const newRoute = structuredClone(bcmBefore);
newRoute.triggers[0].trigger_index = 1;
change = core.compareBcm(bcmBefore, newRoute);
assert.strictEqual(change.find(item => item.status === "added_locator").snapshot.fields.profile.fields.flags, "18446744073709551615");
console.log("nested AC/BCM change report tests passed");
