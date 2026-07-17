"use strict";

const assert = require("assert");
const core = require("./bcm_catalog_core.js");

assert.strictEqual(core.normalizeMotion("5252"), "22");
assert.strictEqual(core.normalizeMotion("5656"), "66");
assert.strictEqual(core.normalizeMotion("5454"), "44");
assert.strictEqual(core.normalizeMotion("626"), "623");

// SF6 stores full-circle commands as one release-style 0x40001 input. The
// low nibble alone is direction 8, but the complete signature means 360.
const circleObjects = [
    collection(101, "Dictionary", [null, 102]),
    collection(102, "BCM.COMMAND[]", [103]),
    object(103, "BCM.COMMAND", { charge_bit: scalar(0), input_num: scalar(1), inputs: ref(104), max_frame: scalar(21), total_frame: scalar(-1) }),
    collection(104, "BCM.INPUT[]", [105]),
    object(105, "BCM.INPUT", { frame_num: scalar(21), type: scalar(2), normal: ref(106), charge: ref(107) }),
    object(106, "BCM.INPUT.NORMAL", { ok_key_flags: scalar(0x40001) }),
    object(107, "BCM.INPUT.CHARGE", { id: scalar(1), is_release: scalar(true) }),
    object(108, "BCM.TRIGGER", {
        action_id: scalar(940), cond_owner_state_flags: scalar(0), category_flags: scalar(0),
        norm: ref(109), norm_NG: scalar(false), easy: ref(110), easy_NG: scalar(true),
        sprt: ref(111), sprt_NG: scalar(true), supr: ref(112), supr_NG: scalar(true),
        use_sprt: scalar(false), use_super: scalar(false)
    }),
    object(109, "BCM.TRIGGER.CMD", { command_no: scalar(16), command_index: scalar(0), command_ptr: ref(102), ok_key_flags: scalar(64), ok_key_cond_flags: scalar(81952), dc_exc_flags: scalar(0), preceding_time: scalar(4) }),
    object(110, "BCM.TRIGGER.CMD", { command_no: scalar(-1), command_index: scalar(0), ok_key_flags: scalar(0), ok_key_cond_flags: scalar(0) }),
    object(111, "BCM.TRIGGER.CMD", { command_no: scalar(-1), command_index: scalar(0), ok_key_flags: scalar(0), ok_key_cond_flags: scalar(0) }),
    object(112, "BCM.TRIGGER.CMD", { command_no: scalar(-1), command_index: scalar(0), ok_key_flags: scalar(0), ok_key_cond_flags: scalar(0) })
];
const circleCatalog = core.buildCatalog({
    schema: "test", character: "Zangief", fighter_id: 6, hard_gate_passed: true,
    truncated: false, command_root_ref: ref(101), objects: circleObjects,
    triggers: [{ trigger_index: 0, native_action_id: 940, trigger_ref: ref(108) }]
}, { generatedAt: "2026-01-01T00:00:00.000Z" });
assert.strictEqual(circleCatalog.actions["940"].classic_display, "360+HP");
assert.strictEqual(circleCatalog.actions["940"].triggers[0].profiles.norm.command.inputs[0].direction, "360");

function adjacentCircleDirection(mask, inputType, chargeId, chargeRelease, actionId) {
    const base = actionId * 10;
    const adjacentObjects = [
        collection(base + 1, "Dictionary", [null, base + 2]),
        collection(base + 2, "BCM.COMMAND[]", [base + 3]),
        object(base + 3, "BCM.COMMAND", { charge_bit: scalar(0), input_num: scalar(1), inputs: ref(base + 4), max_frame: scalar(21), total_frame: scalar(-1) }),
        collection(base + 4, "BCM.INPUT[]", [base + 5]),
        object(base + 5, "BCM.INPUT", { frame_num: scalar(21), type: scalar(inputType), normal: ref(base + 6), charge: ref(base + 7) }),
        object(base + 6, "BCM.INPUT.NORMAL", { ok_key_flags: scalar(mask) }),
        object(base + 7, "BCM.INPUT.CHARGE", { id: scalar(chargeId), is_release: scalar(chargeRelease) }),
        object(base + 8, "BCM.TRIGGER", {
            action_id: scalar(actionId), cond_owner_state_flags: scalar(0), category_flags: scalar(0),
            norm: ref(base + 9), norm_NG: scalar(false), easy: ref(base + 10), easy_NG: scalar(true),
            sprt: ref(base + 11), sprt_NG: scalar(true), supr: ref(base + 12), supr_NG: scalar(true),
            use_sprt: scalar(false), use_super: scalar(false)
        }),
        object(base + 9, "BCM.TRIGGER.CMD", { command_no: scalar(16), command_index: scalar(0), command_ptr: ref(base + 2), ok_key_flags: scalar(64), ok_key_cond_flags: scalar(81952), dc_exc_flags: scalar(0), preceding_time: scalar(4) }),
        object(base + 10, "BCM.TRIGGER.CMD", { command_no: scalar(-1), command_index: scalar(0), ok_key_flags: scalar(0), ok_key_cond_flags: scalar(0) }),
        object(base + 11, "BCM.TRIGGER.CMD", { command_no: scalar(-1), command_index: scalar(0), ok_key_flags: scalar(0), ok_key_cond_flags: scalar(0) }),
        object(base + 12, "BCM.TRIGGER.CMD", { command_no: scalar(-1), command_index: scalar(0), ok_key_flags: scalar(0), ok_key_cond_flags: scalar(0) })
    ];
    const adjacent = core.buildCatalog({
        schema: "test", character: "Zangief", fighter_id: 6, hard_gate_passed: true,
        truncated: false, command_root_ref: ref(base + 1), objects: adjacentObjects,
        triggers: [{ trigger_index: 0, native_action_id: actionId, trigger_ref: ref(base + 8) }]
    }, { generatedAt: "2026-01-01T00:00:00.000Z" });
    return adjacent.actions[String(actionId)].triggers[0].profiles.norm.command.inputs[0].direction;
}

// Every component of the 0x40001/type=2/charge=1/release signature is required.
assert.strictEqual(adjacentCircleDirection(0x40001, 2, 1, false, 941), "8");
assert.strictEqual(adjacentCircleDirection(0x40001, 2, 2, true, 942), "8");
assert.strictEqual(adjacentCircleDirection(0x40001, 1, 1, true, 943), "8");
assert.strictEqual(adjacentCircleDirection(0x40002, 2, 1, true, 944), "2");

// Double full-circle has its own exact 0x70000/type=2/charge=0/release
// signature. Every component is required; nearby values remain ordinary
// direction masks instead of being guessed as 720.
assert.strictEqual(adjacentCircleDirection(0x70000, 2, 0, true, 945), "720");
assert.strictEqual(adjacentCircleDirection(0x70000, 2, 0, false, 946), "5");
assert.strictEqual(adjacentCircleDirection(0x70000, 2, 1, true, 947), "5");
assert.strictEqual(adjacentCircleDirection(0x70000, 1, 0, true, 948), "5");
assert.strictEqual(adjacentCircleDirection(0x70001, 2, 0, true, 949), "8");

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

// AssistComboRecipeData is a fixed 3 strength x 8 recipe x 10 step table.
// TriggerID is the stable owner link: never infer these routes from AC family
// similarity or from neighbouring Action IDs.
const assistItems = Array(240).fill(null);
const assistObjects = [];
let nextAssistObjectId = 1001;
for (const index of [0, 1, 80, 81, 160, 161]) {
    const comboId = nextAssistObjectId++;
    assistItems[index] = comboId;
    assistObjects.push(object(comboId, "CharacterAsset.AssistComboRecipeData.ComboData", {
        TriggerID: scalar(0), IsEndAtNormal: scalar(index % 2 === 1), Delay: scalar(index % 2),
        NextInputDelay: scalar(2), NextInputLimit: scalar(20), ConditionFlag: scalar(0)
    }));
}
const assistSource = {
    ...source,
    objects: [...source.objects,
        collection(1000, "CharacterAsset.AssistComboRecipeData.ComboData[,,]", assistItems),
        ...assistObjects]
};
const assistCatalog = core.buildCatalog(assistSource,
    { generatedAt: "2026-01-01T00:00:00.000Z" });
assert.strictEqual(assistCatalog.stats.assist_combo_recipe_step_count, 6);
assert.deepStrictEqual(assistCatalog.assist_combo_recipes.map(item => [
    item.array_index, item.action_id, item.assist_strength, item.recipe_index,
    item.step_index, item.input_stage
]), [
    [0, 904, "弱", 0, 0, "first"],
    [1, 904, "弱", 0, 1, "repeat"],
    [80, 904, "强", 0, 0, "first"],
    [81, 904, "强", 0, 1, "repeat"],
    [160, 904, "中", 0, 0, "first"],
    [161, 904, "中", 0, 1, "repeat"]
]);
const malformedAssistSource = {
    ...source,
    objects: [...source.objects,
        collection(1100, "CharacterAsset.AssistComboRecipeData.ComboData[,,]", Array(239).fill(null))]
};
const malformedAssistCatalog = core.buildCatalog(malformedAssistSource,
    { generatedAt: "2026-01-01T00:00:00.000Z" });
assert.deepStrictEqual(malformedAssistCatalog.assist_combo_recipes, []);
assert(malformedAssistCatalog.warnings.some(message => message.includes("3x8x10")));

const driveRuntime = core.buildRuntimeCatalog({
    schema: core.OUTPUT_SCHEMA,
    source: { character: "Fab", fighter_id: 20, schema: "test", sha256: "test" },
    actions: {
        "500": { classic_display: "66", triggers: [{ conditions: { category_flags: 0x100000, function_id: 13, focus_consume: 30000 } }] },
        "501": { classic_display: "66", triggers: [{ conditions: { category_flags: 0x200000, function_id: 13, focus_consume: 5000 } }] },
        "667": { classic_display: "MP", triggers: [{ classic_display: "MP", conditions: { turn_around: 2 } }] },
        "661": { classic_display: "6+MP", triggers: [{ classic_display: "6+MP", conditions: { turn_around: 0 } }] }
    }
});
assert.strictEqual(driveRuntime.actions["500"], "DRC");
assert.strictEqual(driveRuntime.actions["501"], "RAW DR");
assert.strictEqual(driveRuntime.actions["667"], ">MP");
assert.strictEqual(driveRuntime.actions["661"], "6+MP");

const fabSource = { ...source, character: "Fab", fighter_id: 20 };
const hondaCatalog = core.buildCatalog(fabSource, { generatedAt: "2026-01-01T00:00:00.000Z" });
assert.strictEqual(hondaCatalog.source.character, "EHonda");
assert.strictEqual(hondaCatalog.source.capture_character, "Fab");

const derivedAction = (objectId, actionId, keysRef, frame = 10) => object(objectId, "FAB.ACTION", {
    ActionID: scalar(actionId), ActionFrame: scalar(9), Category: scalar(1),
    Combo: scalar(0), Frame: scalar(frame), Projectile: scalar(-1), State: scalar(0), Keys: ref(keysRef)
});
const acSource = {
    schema: "sf6cr.action-catalog-full.v2",
    character: "Fab",
    fighter_id: 20,
    unique_action_ids_by_scope: { character: [605, 606, 652, 904, 905, 906] },
    objects: [
        derivedAction(100, 904, 200), derivedAction(101, 905, 202, 11), derivedAction(102, 906, 204),
        collection(200, "ActionKeyList", [201, 203]),
        object(201, "CharacterAsset.BranchKey", { Action: scalar(905), Type: scalar(29) }),
        collection(202, "ActionKeyList", []),
        object(203, "CharacterAsset.BranchKey", { Action: scalar(906), Type: scalar(35) }),
        collection(204, "ActionKeyList", [])
    ],
    records: [
        { native_action_id: 904, source_scope: "character", action_ref: ref(100) },
        { native_action_id: 905, source_scope: "character", action_ref: ref(101) },
        { native_action_id: 906, source_scope: "character", action_ref: ref(102) }
    ]
};
const actionRuntime = core.buildActionRuntimeCatalog(acSource, hondaCatalog, {
    "605": { override_name: "HP", absorb_ids: "606" },
    "652": { override_name: "j.6+HP" }
}, { actionSourceSha256: "ac-test" });
assert.strictEqual(actionRuntime.schema, "sf6cc.action-runtime.v1");
assert.strictEqual(actionRuntime.aliases["606"], "605");
assert.strictEqual(actionRuntime.actions["652"], "j.6+HP");
assert.strictEqual(actionRuntime.action_ids.length, 6);
assert.strictEqual(actionRuntime.aliases["606"], "605");
assert.strictEqual(actionRuntime.aliases["905"], "904");
assert.strictEqual(actionRuntime.aliases["906"], "904");
assert.strictEqual(actionRuntime.coverage.ac_derived_alias_count, 2);
console.log("BCM catalog tests passed.");
