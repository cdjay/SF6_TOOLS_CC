"use strict";

const assert = require("assert");
const core = require("./bcm_catalog_core.js");

assert.strictEqual(core.normalizeMotion("5252"), "22");
assert.strictEqual(core.normalizeMotion("5656"), "66");
assert.strictEqual(core.normalizeMotion("5454"), "44");
assert.strictEqual(core.normalizeMotion("626"), "623");

function ref(object_id) { return { kind: "ref", object_id }; }
function scalar(value) { return { kind: typeof value === "boolean" ? "boolean" : "number", value }; }
function object(object_id, object_type, fields) {
    return { object_id, object_type, kind: "managed-object", fields: Object.entries(fields).map(([name, value]) => ({ name, declared_type: "test", value })) };
}
function collection(object_id, object_type, refs) {
    return { object_id, object_type, kind: "collection", count: refs.length, fields: null, items: refs.map((value, index) => ({ index, value: value == null ? { kind: "nil" } : ref(value) })) };
}

const objects = [
    collection(1, "Dictionary", [null, 2]),
    collection(2, "BCM.COMMAND[]", [3]),
    object(3, "BCM.COMMAND", { charge_bit: scalar(0), input_num: scalar(3), inputs: ref(4), max_frame: scalar(31), total_frame: scalar(-1) }),
    collection(4, "BCM.INPUT[]", [5, 8, 11]),
    object(5, "BCM.INPUT", { frame_num: scalar(11), type: scalar(0), normal: ref(6), charge: ref(7) }),
    object(6, "BCM.INPUT.NORMAL", { ok_key_flags: scalar(2) }), object(7, "BCM.INPUT.CHARGE", { id: scalar(2), is_release: scalar(false) }),
    object(8, "BCM.INPUT", { frame_num: scalar(11), type: scalar(0), normal: ref(9), charge: ref(10) }),
    object(9, "BCM.INPUT.NORMAL", { ok_key_flags: scalar(10) }), object(10, "BCM.INPUT.CHARGE", { id: scalar(10), is_release: scalar(false) }),
    object(11, "BCM.INPUT", { frame_num: scalar(10), type: scalar(0), normal: ref(12), charge: ref(13) }),
    object(12, "BCM.INPUT.NORMAL", { ok_key_flags: scalar(8) }), object(13, "BCM.INPUT.CHARGE", { id: scalar(8), is_release: scalar(false) }),
    object(14, "BCM.TRIGGER", {
        action_id: scalar(904), cond_owner_state_flags: scalar(0), category_flags: scalar(0),
        norm: ref(15), norm_NG: scalar(false), easy: ref(16), easy_NG: scalar(true),
        sprt: ref(17), sprt_NG: scalar(true), supr: ref(18), supr_NG: scalar(true),
        use_sprt: scalar(false), use_super: scalar(false)
    }),
    object(15, "BCM.TRIGGER.CMD", { command_no: scalar(1), command_index: scalar(7), command_ptr: ref(2), ok_key_flags: scalar(16), ok_key_cond_flags: scalar(81952), dc_exc_flags: scalar(0), preceding_time: scalar(4) }),
    object(16, "BCM.TRIGGER.CMD", { command_no: scalar(-1), command_index: scalar(0), ok_key_flags: scalar(32), ok_key_cond_flags: scalar(0) }),
    object(17, "BCM.TRIGGER.CMD", { command_no: scalar(-1), command_index: scalar(0), ok_key_flags: scalar(0), ok_key_cond_flags: scalar(0) }),
    object(18, "BCM.TRIGGER.CMD", { command_no: scalar(-1), command_index: scalar(0), ok_key_flags: scalar(0), ok_key_cond_flags: scalar(0) })
];

const source = {
    schema: "sf6cr.ingrid-bcm-full.v1", character: "Ingrid", fighter_id: 32,
    hard_gate_passed: true, truncated: false, command_root_ref: ref(1), objects,
    triggers: [{ trigger_index: 0, native_action_id: 904, trigger_ref: ref(14) }]
};
const catalog = core.buildCatalog(source, { generatedAt: "2026-01-01T00:00:00.000Z" });
assert.strictEqual(catalog.schema, "sf6cc.bcm-catalog.v1");
assert.strictEqual(catalog.actions["904"].classic_display, "236+LP");
assert.strictEqual(catalog.actions["904"].triggers[0].profiles.easy.notation, "MP");
assert.strictEqual(catalog.stats.action_count, 1);
const runtime = core.buildRuntimeCatalog(catalog);
assert.strictEqual(runtime.schema, "sf6cc.bcm-runtime.v1");
assert.strictEqual(runtime.actions["904"], "236+LP");

const fabSource = { ...source, character: "Fab", fighter_id: 20 };
const hondaCatalog = core.buildCatalog(fabSource, { generatedAt: "2026-01-01T00:00:00.000Z" });
assert.strictEqual(hondaCatalog.source.character, "EHonda");
assert.strictEqual(hondaCatalog.source.capture_character, "Fab");

const acSource = {
    schema: "sf6cr.action-catalog-full.v2",
    character: "Fab",
    fighter_id: 20,
    unique_action_ids_by_scope: { character: [605, 606, 652] }
};
const actionRuntime = core.buildActionRuntimeCatalog(acSource, hondaCatalog, {
    "605": { override_name: "HP", absorb_ids: "606" },
    "652": { override_name: "j.6+HP" }
}, { actionSourceSha256: "ac-test" });
assert.strictEqual(actionRuntime.schema, "sf6cc.action-runtime.v1");
assert.strictEqual(actionRuntime.aliases["606"], "605");
assert.strictEqual(actionRuntime.actions["652"], "j.6+HP");
assert.strictEqual(actionRuntime.action_ids.length, 3);
console.log("BCM catalog tests passed.");
