"use strict";
const assert = require("assert");
const core = require("./web_handoff_builder.js");

const scalar = (name, value) => ({ name, value: { kind: "number", value } });
const ref = (name, id) => ({ name, value: { kind: "ref", object_id: id } });
function source(offset = 0) {
    return { inherited_fields: "game-namespaces.v2", records: [
        { native_action_id: 600, source_scope: "character", resource_index: 0, style_index: 0, action_ref: { object_id: 1 + offset } },
        { native_action_id: 600, source_scope: "character", resource_index: 0, style_index: 1, action_ref: { object_id: 1 + offset } },
        { native_action_id: 600, source_scope: "common", resource_index: 6, style_index: 0, action_ref: { object_id: 1 + offset } }
    ], objects: [
        { object_id: 1 + offset, object_type: "FAB.ACTION", fields: [scalar("Frame", 39), ref("Keys", 2 + offset), ref("ActionFrame", 4 + offset)] },
        { object_id: 2 + offset, object_type: "List", items: [{ index: 0, value: { kind: "ref", object_id: 3 + offset } }] },
        { object_id: 3 + offset, object_type: "CharacterAsset.BranchKey", fields: [scalar("Param00", 5), scalar("StartFrame", 0), scalar("EndFrame", 38), scalar("Attr", "18446744073709551615")] },
        { object_id: 4 + offset, object_type: "CharacterAsset.ActionFrame", fields: [scalar("MainFrame", 13)] }
    ] };
}
const first = core.nativeFacts(source(), {}), renamed = core.nativeFacts(source(100), {});
assert.deepStrictEqual(first, renamed, "Native object IDs are not semantic changes");
assert.strictEqual(Object.keys(first.actions).length, 3, "Scope and style variants must remain separate");
assert.strictEqual(first.actions[Object.keys(first.actions)[0]].keys["CharacterAsset.BranchKey"][0].Attr, "18446744073709551615");
first.routes = {}; renamed.routes = {};
assert.deepStrictEqual(core.compareNative(first, renamed), []);
const changed = structuredClone(renamed);
changed.actions[Object.keys(changed.actions)[0]].keys["CharacterAsset.BranchKey"][0].Param00 = 7;
changed.actions[Object.keys(changed.actions)[0]].fields.Frame = 40;
let diff = core.compareNative(first, changed);
assert.strictEqual(diff.length, 1);
assert.deepStrictEqual(diff[0].fields.map(field => field.path), ["fields.Frame", "keys.CharacterAsset.BranchKey.0.Param00"]);
assert.strictEqual(diff[0].auto_approved, false);
assert.strictEqual(diff[0].identity_status, "not_verified");
const incomplete = structuredClone(first);
incomplete.capabilities.inherited_fields = null;
delete incomplete.actions[Object.keys(incomplete.actions)[0]].keys["CharacterAsset.BranchKey"][0].StartFrame;
diff = core.compareNative(incomplete, first);
assert.strictEqual(diff[0].fields[0].evidence_status, "capture_availability_change");
assert.strictEqual(diff[0].fields[0].before_present, false);
assert.strictEqual(diff[0].fields[0].after, 0);
const absentWithoutCapabilityChange = structuredClone(first);
delete absentWithoutCapabilityChange.actions[Object.keys(absentWithoutCapabilityChange.actions)[0]].fields.Frame;
assert.strictEqual(core.compareNative(absentWithoutCapabilityChange, first)[0].fields[0].evidence_status, "field_presence_change_unverified");
const routes = { capabilities: {}, actions: {}, routes: { "600:1": { profiles: { norm: { mask: 16 } } } } };
const otherRoutes = structuredClone(routes);
otherRoutes.routes["600:1"].profiles.norm.mask = 32;
assert.strictEqual(core.compareNative(routes, otherRoutes)[0].fields[0].path, "profiles.norm.mask");
const bcmSource = { fighter_id: 1, command_root_ref: { kind: "ref", object_id: 12 }, objects: [
    { object_id: 10, object_type: "BCM.TRIGGER", fields: [scalar("action_id", 600), ref("norm", 11), scalar("category_flags", "18446744073709551615")] },
    { object_id: 11, object_type: "BCM.TRIGGER.CMD", fields: [scalar("command_no", -1), scalar("ok_key_flags", 16), scalar("ok_key_cond_flags", 81952)] },
    { object_id: 12, object_type: "Dictionary", items: [] }
], triggers: [{ trigger_index: 0, native_action_id: 600, trigger_ref: { kind: "ref", object_id: 10 } }] };
const bcmBefore = core.bcmFacts(bcmSource);
assert.strictEqual(bcmBefore.routes["600:0"].fields.category_flags, "18446744073709551615");
bcmSource.objects[1].fields.find(field => field.name === "ok_key_flags").value.value = 32;
assert.ok(core.compareNative({ actions: {}, routes: bcmBefore.routes }, { actions: {}, routes: core.bcmFacts(bcmSource).routes })
    .some(change => change.fields.some(field => field.path === "profiles.norm.ok_key_flags")));
const duplicateRoute = structuredClone(bcmSource);
duplicateRoute.triggers.push(duplicateRoute.triggers[0]);
assert.throws(() => core.bcmFacts(duplicateRoute), /Duplicate BCM route/);
assert.deepStrictEqual(core.deltas({ a: null }, {}), [{ path: "a", before_present: true, after_present: false, before: null, after: null }]);
assert.deepStrictEqual(core.deltas({ a: 1, b: 2 }, { b: 2, a: 1 }), []);
const move = { internal_name: "(5LP)", category: "NORMAL", name: "LP", frames: { startup: { raw: "4", value: 4 } }, source_row_index: 0 };
const oldWeb = { _meta: { generated_at: "old" }, actions: {}, moves: { "web:100:1": structuredClone(move), "web:100:2": structuredClone(move) } };
const newWeb = structuredClone(oldWeb);
newWeb._meta.generated_at = "new";
newWeb.moves["web:100:1"].source_row_index = 15;
assert.deepStrictEqual(core.compareWeb(oldWeb, newWeb), { moves: [], commands: [] });
newWeb.moves["web:100:2"].frames.startup = { raw: "5", value: 5 };
diff = core.compareWeb(oldWeb, newWeb);
assert.strictEqual(diff.moves.length, 1);
assert.strictEqual(diff.moves[0].key, "web:100:2");
assert.strictEqual(diff.moves[0].fields[1].after, 5);
newWeb.moves["web:100:2"].internal_name = "(5MP)";
assert.strictEqual(core.compareWeb(oldWeb, newWeb).moves[0].status, "ambiguous_row_pair");
assert.strictEqual(core.compareWeb(null, oldWeb).moves.length, 2);
const duplicate = source(); duplicate.records.push(duplicate.records[0]);
assert.throws(() => core.nativeFacts(duplicate, {}), /Duplicate/);
const missing = source(); missing.objects.pop();
assert.throws(() => core.nativeFacts(missing, {}), /Unresolved/);
assert.throws(() => core.generate({ old: "2026-10-13", new: "2026-08-03", output: "unused" }), /Expected old/);
console.log("web handoff projection/comparison tests passed");
