"use strict";

const assert = require("assert");
const compiler = require("./compiler_core.js");

function ref(object_id) { return { kind: "ref", object_id }; }
function scalar(value) { return { kind: "number", value }; }
function object(object_id, object_type, fields) {
    return {
        object_id, object_type, kind: "managed-object",
        fields: Object.entries(fields).map(([name, value]) => ({ name, declared_type: "test", value }))
    };
}
function collection(object_id, refs) {
    return {
        object_id, object_type: "ActionKeyList", kind: "collection", count: refs.length,
        fields: null, items: refs.map((value, index) => ({ index, value: ref(value) }))
    };
}
function action(objectId, actionId, keysId, frame = 10) {
    return object(objectId, "FAB.ACTION", {
        ActionID: scalar(actionId), ActionFrame: scalar(9), Category: scalar(1), Combo: scalar(0),
        Frame: scalar(frame), Projectile: scalar(-1), State: scalar(0), Keys: ref(keysId)
    });
}
function bcmAction(actionId, display, conditions, button) {
    return {
        action_id: actionId,
        classic_display: display,
        triggers: [{
            trigger_index: actionId,
            classic_profile: "norm",
            classic_display: display,
            profiles: { norm: { button: button || "", command: null } },
            conditions: conditions || {}
        }]
    };
}

const acSource = {
    schema: "sf6cr.action-catalog-full.v2",
    character: "Fab",
    fighter_id: 20,
    unique_action_ids_by_scope: { character: [500, 501, 606, 661, 904, 905, 999] },
    objects: [
        action(100, 904, 200), action(101, 905, 202, 11),
        collection(200, [201]),
        object(201, "CharacterAsset.BranchKey", { Action: scalar(905), Type: scalar(29) }),
        collection(202, [])
    ],
    records: [
        { native_action_id: 904, source_scope: "character", action_ref: ref(100) },
        { native_action_id: 905, source_scope: "character", action_ref: ref(101) }
    ]
};

const bcmCatalog = {
    schema: "sf6cc.bcm-catalog.v1",
    source: { schema: "sf6cr.bcm-full.v1", character: "EHonda", fighter_id: 20, sha256: "bcm-test" },
    actions: {
        "500": bcmAction(500, "66", { category_flags: 0x100000, function_id: 13, focus_consume: 30000 }),
        "501": bcmAction(501, "66", { category_flags: 0x200000, function_id: 13, focus_consume: 5000 }),
        "606": bcmAction(606, "MK", { turn_around: 2 }, "MK"),
        "661": bcmAction(661, "6+MP", { turn_around: 0 }, "MP"),
        "904": bcmAction(904, "236+LP", {}, "LP")
    }
};

const base = compiler.compileFromCatalog(acSource, bcmCatalog, {}, { actionSourceSha256: "ac-test" });
assert.strictEqual(base.runtime.schema, compiler.RUNTIME_SCHEMA);
assert.strictEqual(base.runtime.actions["500"], "DRC");
assert.strictEqual(base.runtime.actions["501"], "RAW DR");
assert.strictEqual(base.runtime.actions["606"], ">MK");
assert.strictEqual(base.runtime.actions["661"], "6+MP");
assert.strictEqual(base.runtime.aliases["905"], "904");
assert.strictEqual(base.runtime.validation.rules["606"].target_combo_followup, true);
assert.strictEqual(base.runtime.validation.rules["661"].target_combo_followup, false);
assert.strictEqual(base.runtime.evidence.alias_relations[0].branch_type, 29);
assert.deepStrictEqual(base.report.inventory.ac_action_ids_without_command_semantics, [999]);
const legacy = compiler.buildLegacyExceptionTable(base.runtime);
assert.deepStrictEqual(legacy["500"], { override_name: "DRC" });
assert.deepStrictEqual(legacy["904"], { override_name: "236+LP", absorb_ids: "905" });
assert.deepStrictEqual(legacy["905"], { override_name: "236+LP", force: true });
const compatibility = compiler.buildLegacyCompatibility({
    "905": { override_name: "236+LP (Level)", force: false, ignore_prev_frames: 5 },
    "999": { override_name: "MANUAL", force: true },
    "1000": { override_name: "STALE" }
}, legacy, base.runtime.action_ids);
assert.deepStrictEqual(compatibility.missing_action_ids, [999]);
assert.deepStrictEqual(compatibility.stale_reference_action_ids, [1000]);
assert.strictEqual(compatibility.summary.fallback_entry_count, 2);
assert.deepStrictEqual(compatibility.overlay["905"], {
    override_name: "236+LP (Level)", force: false, ignore_prev_frames: 5
});
const compatibleLegacy = compiler.applyLegacyCompatibilityOverlay(legacy, compatibility.overlay);
const compatibilityAfter = compiler.buildLegacyCompatibility(
    { "905": { override_name: "236+LP (Level)", force: false, ignore_prev_frames: 5 } },
    compatibleLegacy, base.runtime.action_ids);
assert.strictEqual(compatibilityAfter.summary.fallback_entry_count, 0);

const withExceptions = compiler.compileFromCatalog(acSource, bcmCatalog, {
    "999": { override_name: "MANUAL", force: true, absorb_ids: "" },
    "1000": { override_name: "STALE" }
}, { actionSourceSha256: "ac-test" });
assert.strictEqual(withExceptions.runtime.actions["999"], "MANUAL");
assert.strictEqual(withExceptions.runtime.validation.rules["999"].force, true);
assert.strictEqual(withExceptions.runtime.coverage.manual_exception_entry_count, 1);
assert.strictEqual(withExceptions.runtime.coverage.manual_display_fill_count, 1);
assert.strictEqual(withExceptions.runtime.coverage.manual_validation_rule_count, 1);
assert.strictEqual(withExceptions.runtime.coverage.manual_absorb_alias_count, 0);
assert.strictEqual(withExceptions.report.status, "valid-with-warnings");
assert.strictEqual(withExceptions.report.diagnostics[0].code, "STALE_EXCEPTION_ACTION_ID");
assert.strictEqual(withExceptions.report.diagnostics.some(item => item.code === "STALE_EXCEPTION_ABSORB_ID"), false);

const explicitEmptyAbsorb = compiler.compileFromCatalog(acSource, bcmCatalog, {
    "904": { override_name: "236+LP", absorb_ids: "" }
}, { actionSourceSha256: "ac-test" });
assert.strictEqual(explicitEmptyAbsorb.runtime.aliases["905"], undefined);
const explicitAbsorb = compiler.compileFromCatalog(acSource, bcmCatalog, {
    "904": { override_name: "236+LP", absorb_ids: "905" }
}, { actionSourceSha256: "ac-test" });
assert.strictEqual(explicitAbsorb.runtime.aliases["905"], "904");

const incomplete = compiler.compileFromCatalog(
    { ...acSource, truncated: true },
    { ...bcmCatalog, source: { ...bcmCatalog.source, complete: false } },
    {}, { actionSourceSha256: "ac-test" });
assert.strictEqual(incomplete.report.status, "invalid");
assert.strictEqual(incomplete.report.diagnostics.some(item => item.code === "AC_SOURCE_TRUNCATED"), true);
assert.strictEqual(incomplete.report.diagnostics.some(item => item.code === "BCM_SOURCE_INCOMPLETE"), true);

console.log("Action runtime compiler tests passed.");
