"use strict";

const assert = require("assert");
const modern = require("./modern_display_core.js");

function profile(enabled, notation, flags, condition, extra) {
    extra = extra || {};
    return {
        enabled,
        notation,
        ok_key_flags: flags,
        ok_key_cond_flags: condition == null ? 16416 : condition,
        dc_exc_flags: extra.dc_exc_flags || 0,
        ng_key_flags: extra.ng_key_flags || 0,
        command_no: extra.command_no == null ? -1 : extra.command_no,
        command_index: extra.command_index == null ? -1 : extra.command_index,
        button: extra.button || "",
        command: extra.inputs ? { inputs: extra.inputs } : null
    };
}

function profiles(sprt, easy, supr, norm) {
    return {
        norm: norm || profile(false, "Normal", 0),
        easy: easy || profile(false, "Normal", 0),
        sprt: sprt || profile(false, "Normal", 0),
        supr: supr || profile(false, "Normal", 0)
    };
}

function trigger(triggerIndex, triggerProfiles, conditions) {
    return { trigger_index: triggerIndex, profiles: triggerProfiles, conditions: conditions || {} };
}

function scalar(value) {
    return { kind: "number", value };
}

function ref(objectId) {
    return { kind: "ref", object_id: objectId };
}

function makeActionSource() {
    let nextObjectId = 1;
    const objects = [], records = [];
    const addObject = object => {
        const result = { object_id: nextObjectId++, ...object };
        objects.push(result);
        return result.object_id;
    };
    const structureRefs = {};
    for (const name of ["Category", "Combo", "Projectile", "State"]) {
        structureRefs[name] = addObject({ kind: "managed-object", object_type: `Test.${name}`, fields: [] });
    }
    const branch = (action, type, options) => {
        options = options || {};
        const values = {
            Action: action,
            Type: type,
            Attr: options.attr == null ? 0 : options.attr,
            ActionFrame: options.frame == null ? 0 : options.frame,
            Param00: options.p00 == null ? 0 : options.p00,
            Param01: options.p01 == null ? 0 : options.p01,
            Param02: options.p02 == null ? 0 : options.p02,
            Param03: options.p03 == null ? 0 : options.p03,
            Param04: options.p04 == null ? 0 : options.p04,
            Param05: options.p05 == null ? 0 : options.p05,
            TriggerID: options.triggerId == null ? -1 : options.triggerId
        };
        return addObject({
            kind: "managed-object",
            object_type: "CharacterAsset.BranchKey",
            fields: Object.entries(values).map(([name, value]) => ({ name, value: scalar(value) }))
        });
    };
    const addAction = (actionId, frame, branchSpecs) => {
        const branchRefs = branchSpecs.map(spec => ref(branch(spec.action, spec.type, spec)));
        const keysId = addObject({ kind: "managed-array", object_type: "Test.Keys",
            items: branchRefs.map((value, index) => ({ index, value })) });
        const rootId = addObject({
            kind: "managed-object",
            object_type: "FAB.ACTION",
            fields: [
                { name: "ActionID", value: scalar(actionId) },
                { name: "ActionFrame", value: scalar(0) },
                { name: "Frame", value: scalar(frame) },
                ...Object.entries(structureRefs).map(([name, objectId]) => ({ name, value: ref(objectId) })),
                { name: "Keys", value: ref(keysId) }
            ]
        });
        records.push({ source_scope: "character", native_action_id: actionId, action_ref: ref(rootId) });
    };
    addAction(1015, 76, [
        { action: 918, type: 17, p00: 9, p01: 120 },
        { action: 1016, type: 36 }, { action: 1018, type: 36, p00: 2 }
    ]);
    addAction(1020, 76, [
        { action: 924, type: 17, p00: 9, p01: 120 },
        { action: 1021, type: 36 }, { action: 1023, type: 36, p00: 2 }
    ]);
    addAction(918, 210, [
        { action: 918, type: 17, frame: 72, p00: 10, p01: 240 },
        { action: 917, type: 17, p00: 10, p01: 240 }
    ]);
    addAction(924, 210, [
        { action: 924, type: 17, frame: 70, p00: 10, p01: 240 },
        { action: 923, type: 17, frame: 2, p00: 10, p01: 240 }
    ]);
    addAction(956, 90, []);
    addAction(957, 90, []);
    return { records, objects };
}

function branchObject(actionSource, targetId, param00) {
    return actionSource.objects.find(object => object.object_type === "CharacterAsset.BranchKey"
        && object.fields.some(field => field.name === "Action" && field.value.value === targetId)
        && object.fields.some(field => field.name === "Param00" && field.value.value === param00));
}

function actionRoot(actionSource, actionId) {
    const record = actionSource.records.find(item => item.native_action_id === actionId);
    return actionSource.objects.find(object => object.object_id === record.action_ref.object_id);
}

const actionIds = [
    17, 18, 36, 37, 38,
    480, 489, 600, 605, 606, 627, 640, 642, 647, 651, 652, 653, 681, 692, 715, 716, 717, 718,
    739, 740, 850, 855, 903, 904, 917, 918, 923, 924, 956, 957, 975, 976, 977, 978, 979, 1015, 1020,
    985, 1075, 1076, 1077, 1218, 1231, 1240
];
const runtime = {
    character: "Zangief",
    fighter_id: 6,
    action_ids: actionIds,
    // Classic strings deliberately contain tempting values. Strict Modern
    // generation must never inspect this table.
    actions: {
        "850": "6+DI", "855": "DI", "917": "63214789+LP", "918": "63214789+MP",
        "923": "63214789+LK", "924": "63214789+MK", "979": "236+HP"
    },
    aliases: { "979": "903", "917": "1015", "918": "1015", "923": "1020", "924": "1020" },
    sources: { ac_sha256: "ac", bcm_sha256: "bcm" },
    validation: { rules: {
        "606": { target_combo_followup: true, target_combo_parent_status: "resolved",
            physical_button_required: true },
        "739": { system_action: "drc" },
        "740": { system_action: "raw_dr" }
    } },
    evidence: { ac_derived_commands: [
        { action_id: 716, source_action_id: 715, display: "2+THROW", branch_type: 63 },
        { action_id: 717, source_action_id: 716, display: "4+THROW", branch_type: 63 },
        { action_id: 718, source_action_id: 715, display: "8+THROW", branch_type: 63 },
        { action_id: 652, source_action_id: 651, display: "j.6+HP", branch_type: 20, force: true },
        { action_id: 653, source_action_id: 651, display: "j.4+HP", branch_type: 20, force: true },
        { action_id: 917, source_action_id: 1015, display: "63214789+LP", branch_type: 17 },
        { action_id: 918, source_action_id: 1015, display: "63214789+MP", branch_type: 17 },
        { action_id: 923, source_action_id: 1020, display: "63214789+LK", branch_type: 17 },
        { action_id: 924, source_action_id: 1020, display: "63214789+MK", branch_type: 17 }
    ], target_combo_relations: [
        { action_id: 606, parent_action_ids: [605], evidence: "bcm-turn-around" }
    ] }
};

const catalog = { source: { character: "Zangief" }, actions: {
    "480": { action_id: 480, triggers: [trigger(30, profiles(null, null, null, null),
        { function_id: 10, focus_consume: 5000 })] },
    "600": { action_id: 600, triggers: [trigger(1, profiles(profile(true, "LP", 16)),
        { function_id: 1 })] },
    "605": { action_id: 605, triggers: [trigger(2, profiles(null, null,
        profile(true, "Normal", 256)), {})] },
    "606": { action_id: 606, triggers: [trigger(3, profiles(null, null, null,
        profile(true, "MK", 128)), { function_id: 1, turn_around: 2 })] },
    "627": { action_id: 627, triggers: [trigger(20, profiles(null, null, null,
        profile(true, "2+LK", 64)), { function_id: 1 })] },
    "640": { action_id: 640, triggers: [trigger(21, profiles(
        profile(true, "2+LK", 128), null, profile(true, "LK", 128)),
        { function_id: 1, cond_owner_state_flags: 0 })] },
    "642": { action_id: 642, triggers: [trigger(24, profiles(
        profile(true, "j.HP", 256), null, profile(true, "j.MP", 32),
        profile(true, "j.HP", 256)), { function_id: 1, cond_owner_state_flags: 4 })] },
    // function_id=1 supr is an internal selector, including in the air. Only
    // sprt is a player-visible Modern route.
    "647": { action_id: 647, triggers: [trigger(22, profiles(
        profile(true, "j.MK", 256), null, profile(true, "j.MP", 32),
        profile(true, "j.HK", 512)), { function_id: 1, cond_owner_state_flags: 4 })] },
    "651": { action_id: 651, triggers: [trigger(25, profiles(
        profile(true, "j.HP", 256), null, null, profile(true, "j.HP", 256)),
        { function_id: 1, cond_owner_state_flags: 4 })] },
    "692": { action_id: 692, triggers: [trigger(23, profiles(
        profile(true, "j.2+MK", 256), null, profile(true, "j.MK", 256),
        profile(true, "j.2+HP", 256)), { function_id: 1, cond_owner_state_flags: 4 })] },
    "715": { action_id: 715, triggers: [trigger(31, profiles(
        profile(true, "Throw", 144, 16480, { button: "Throw" })), { function_id: 1 })] },
    // A direct target must remain direct even when an allowed Type63 relation exists.
    "718": { action_id: 718, triggers: [trigger(32, profiles(
        profile(true, "8+Throw", 144, 16480, { button: "Throw" })), { function_id: 1 })] },
    "739": { action_id: 739, triggers: [trigger(33, profiles(profile(true, "66", 8)),
        { function_id: 13, category_flags: 0x100000, focus_consume: 30000 })] },
    "740": { action_id: 740, triggers: [trigger(34, profiles(profile(true, "66", 8)),
        { function_id: 13, category_flags: 0x200000, focus_consume: 5000 })] },
    "850": { action_id: 850, triggers: [trigger(35, profiles(null, null, null,
        profile(true, "6+DI", 576, 16480, { button: "DI", dc_exc_flags: 8 })),
        { function_id: 2 })] },
    "855": { action_id: 855, triggers: [trigger(36, profiles(null, null, null,
        profile(true, "DI", 576, 16480, { button: "DI" })), { function_id: 2 })] },
    "903": { action_id: 903, triggers: [trigger(4, profiles(
        profile(true, "236+MK", 256, 81952, { command_no: 14, command_index: 3,
            inputs: [{ raw_mask: 2 }, { raw_mask: 10 }, { raw_mask: 8 }] }),
        profile(true, "MP", 32), profile(true, "Normal", 8192)),
        { function_id: 2, focus_consume: 0, cond_owner_state_flags: 0 })] },
    "904": { action_id: 904, triggers: [trigger(5, profiles(
        profile(true, "236+LP+LK+MK", 400, 82016),
        profile(true, "MP", 32), profile(true, "Normal", 8192)),
        { function_id: 2, focus_consume: 20000, cond_owner_state_flags: 0 })] },
    "956": { action_id: 956, triggers: [trigger(166, profiles(
        profile(true, "236+LP+LK+MK", 400, 82016),
        profile(true, "6+MP", 32), profile(true, "6", 8192)),
        { function_id: 2, focus_consume: 20000, focus_need: 1, kind_level: 7,
            use_sprt: true, use_super: true })] },
    "957": { action_id: 957, triggers: [trigger(167, profiles(),
        { function_id: 2, focus_consume: 20000, focus_need: 1, kind_level: 7,
            use_sprt: true, use_super: false })] },
    "975": { action_id: 975, triggers: [trigger(6, profiles(null, null,
        profile(true, "Normal", 2147483648)), { function_id: 2, focus_consume: 0 })] },
    // The same shortcut is present on a no-cost normal version and its unique
    // Drive-consuming owner in one command family. Only the OD owner keeps it.
    "976": { action_id: 976, triggers: [trigger(7, profiles(
        profile(true, "236+LP", 16, 81952, { command_no: 1, command_index: 0,
            inputs: [{ raw_mask: 2 }, { raw_mask: 10 }, { raw_mask: 8 }] }), null,
        profile(true, "Normal", 8192)), { function_id: 2, focus_consume: 0 })] },
    "977": { action_id: 977, triggers: [trigger(8, profiles(
        profile(true, "236+LP+LK+MK", 400, 82016, { command_no: 1, command_index: 0,
            inputs: [{ raw_mask: 2 }, { raw_mask: 10 }, { raw_mask: 8 }] }), null,
        profile(true, "Normal", 8192)), { function_id: 2, focus_consume: 20000 })] },
    // An identical official AUTO normal owns the shortcut; this unrelated
    // special keeps only its manual route.
    "978": { action_id: 978, triggers: [trigger(9, profiles(
        profile(true, "236+LP", 16, 81952), null,
        profile(true, "Normal", 16)), { function_id: 2, focus_consume: 0 })] },
    // Zangief 1015: easy is direct 4+SP; sprt accepts any one valid attack.
    "1015": { action_id: 1015, triggers: [trigger(87, profiles(
        profile(true, "63214+LP+LK+MK", 400, 81952),
        profile(true, "4+MP", 32, 16416, { dc_exc_flags: 4 }),
        profile(true, "4", 8192, 16416, { dc_exc_flags: 4 })),
        { function_id: 2, focus_consume: 0, cond_owner_state_flags: 0 })] },
    // Zangief 1020: supr is 4+AUTO+SP; the same sprt candidates require two buttons.
    "1020": { action_id: 1020, triggers: [trigger(156, profiles(
        profile(true, "63214+LP+LK+MK", 400, 82016),
        profile(true, "4+MP", 32, 16416, { dc_exc_flags: 516 }),
        profile(true, "4", 8192, 16416, { dc_exc_flags: 4 })),
        { function_id: 2, focus_consume: 20000, cond_owner_state_flags: 0 })] },
    "1075": { action_id: 1075, triggers: [trigger(1075, profiles(
        profile(true, "6+KKK", 896, 128)), { function_id: 2 })] },
    "1076": { action_id: 1076, triggers: [trigger(1076, profiles(
        profile(true, "4+KK", 384, 64)), { function_id: 2 })] },
    "1077": { action_id: 1077, triggers: [trigger(1077, profiles(
        null, profile(true, "6+LP+LK+MK", 400, 16416)), { function_id: 2 })] },
    "1218": { action_id: 1218, triggers: [trigger(1218, profiles(
        profile(true, "720+MK", 256, 81952, { command_no: 38, command_index: 8,
            inputs: [{ direction: "720", raw_mask: 0x70000 }] }),
        profile(true, "2+Parry", 288, 16544)),
        { function_id: 3, gauge_consume: 30000 })] },
    "1231": { action_id: 1231, triggers: [trigger(138, profiles(profile(true, "555+MK", 256, 16416, {
        inputs: [{ direction: "5", raw_mask: 16 }, { direction: "5", raw_mask: 16 },
            { direction: "5", raw_mask: 128 }]
    })), { function_id: 3 })] },
    "1240": { action_id: 1240, triggers: [trigger(1240, profiles(
        profile(true, "6646+HP", 256), profile(true, "*+HP", 288)), { function_id: 3 })] }
} };

catalog.assist_combo_recipes = [
    // Existing identical display: must not duplicate the already proven route.
    { action_id: 605, trigger_id: 2, array_index: 80, assist_strength: "强",
        strength_index: 1, recipe_index: 0, step_index: 0, input_stage: "first" },
    // Missing owners and repeated occurrences are decoded without any role/ID rule.
    { action_id: 681, trigger_id: 48, array_index: 161, assist_strength: "中",
        strength_index: 2, recipe_index: 0, step_index: 1, input_stage: "repeat" },
    { action_id: 681, trigger_id: 48, array_index: 171, assist_strength: "中",
        strength_index: 2, recipe_index: 1, step_index: 1, input_stage: "repeat" },
    { action_id: 985, trigger_id: 77, array_index: 81, assist_strength: "强",
        strength_index: 1, recipe_index: 0, step_index: 1, input_stage: "repeat" },
    // Existing manual/special routes normalize the Assist step instead of
    // exposing it as a third player-visible move-command route.
    { action_id: 903, trigger_id: 4, array_index: 82, assist_strength: "强",
        strength_index: 1, recipe_index: 0, step_index: 2, input_stage: "repeat" }
];

const actionSource = makeActionSource();
const officialSemantics = {
    _meta: { schema: "xt.modern_display.v1", character: "Zangief", generated_from: "capcom_official" },
    "627": { classic_display: "2 + LK", modern_display: "AUTO + 弱", category: "NORMAL",
        official_web_id: "110", move_name: "crouching light kick" },
    "642": { classic_display: "空中 HP", modern_display: "空中 AUTO + 強", category: "AIR",
        official_web_id: "120", move_name: "jumping heavy punch" }
};
const output = modern.buildModernDisplay(actionSource, catalog, runtime, {}, {
    generatedAt: "test", officialSemantics, officialSemanticsSha256: "official"
});
assert.strictEqual(output._meta.schema, "xt.modern_display.v7");
assert.strictEqual(output._meta.strict_policy, modern.STRICT_POLICY);
assert.strictEqual(output._meta.generated_from, "ac_bcm+capcom_official_semantics");
assert.strictEqual(output["600"].modern_display, "弱");
assert.strictEqual(output["605"].modern_display, "AUTO + 强");
assert.strictEqual(output["606"].modern_display, "> 强");
assert.strictEqual(output["606"].ownership, "target_combo_repeat");
assert.strictEqual(output["606"].routes[0].source, "bcm_target_combo_repeat");
assert.strictEqual(output["652"].modern_display, "空中 6 + 强");
assert.strictEqual(output["653"].modern_display, "空中 4 + 强");
assert.strictEqual(output["652"].ownership, "type20_directional");
assert.strictEqual(output["652"].routes[0].source, "ac_type20_directional_air_attack");
assert.strictEqual(output["957"].modern_display, output["956"].modern_display);
assert.strictEqual(output["957"].ownership, "structural_twin");
assert.strictEqual(output["957"].routes.every(route => route.source === "ac_bcm_structural_twin"), true);
assert.strictEqual(output["640"].modern_display, "2 + 中");
assert.strictEqual(output["627"].modern_display, "AUTO + 弱");
assert.strictEqual(output["642"].modern_display, "空中 AUTO + 强");
assert.strictEqual(output["647"].modern_display, "空中 强");
assert.strictEqual(output["692"].modern_display, "空中 2 + 强");
assert.strictEqual(output["480"].modern_display, "DP");
assert.strictEqual(output["739"].modern_display, "DRC");
assert.strictEqual(output["740"].modern_display, "RAW DR");
assert.strictEqual(output["850"].modern_display, "DI");
assert.strictEqual(output["855"].modern_display, "DI");
assert.strictEqual(output["903"].modern_display, "SP/236 + 强");
assert.strictEqual(output["681"].modern_display, "> 中");
assert.strictEqual(output["985"].modern_display, "> 强");
assert.strictEqual(output["681"].ownership, "assist_combo");
assert.strictEqual(output["681"].routes[0].source, "bcm_assist_combo_recipe");
assert.strictEqual(output["681"].routes[0].assist_recipe_occurrences.length, 2);
assert.strictEqual(output["605"].routes.filter(route => route.display === "AUTO + 强").length, 1);
assert.strictEqual(output["904"].modern_display, "AUTO + SP/236 + 任意键 + 任意键");
assert.strictEqual(output["975"], undefined);
assert.strictEqual(output["976"].modern_display, "236 + 弱");
assert.strictEqual(output["976"].routes.some(route => route.profile === "supr"), false);
assert.strictEqual(output["977"].modern_display, "AUTO + SP/236 + 任意键 + 任意键");
assert.strictEqual(output["978"].modern_display, "236 + 弱");
assert.strictEqual(output["978"].routes.some(route => route.profile === "supr"), false);
assert.strictEqual(output["1015"], undefined);
assert.strictEqual(output["1020"], undefined);
assert.strictEqual(output["918"].modern_display, "4 + SP/63214 + 任意键");
assert.strictEqual(output["924"].modern_display, "4 + AUTO + SP/63214 + 任意键 + 任意键");
assert.strictEqual(output["1075"].modern_display, "6 + 弱 + 中 + 强");
assert.strictEqual(output["1076"].modern_display, "4 + 中 + 强");
assert.deepStrictEqual(output["1076"].routes[0].button_candidates, ["中", "强"]);
assert.strictEqual(output["1076"].routes[0].required_button_count, 2);
assert.strictEqual(output["1077"], undefined);
assert.strictEqual(output["1218"].modern_display, "2 + SP + 强/720 + 强");
assert.strictEqual(output["1231"].modern_display, "弱 > 弱 > 中 > 强");
assert.strictEqual(output["1240"].modern_display, "SP + 强/6646 + 强");

// Only the command-entry targets are rebound. Their internal Type17 stage
// edges must not be mistaken for another propagation hop.
for (const id of [917, 923, 979]) assert.strictEqual(output[String(id)], undefined);
for (const id of [917, 923, 1015, 1020]) assert(output._meta.unmapped_action_ids.includes(id));
for (const id of [918, 924]) assert.strictEqual(output._meta.unmapped_action_ids.includes(id), false);

for (const [id, display] of Object.entries({ 17: "66", 18: "44", 36: "8", 37: "9", 38: "7", 489: "DP" })) {
    const entry = output[id];
    assert(entry, `runtime common ${id}`);
    assert.strictEqual(entry.modern_display, display);
    assert.strictEqual(entry.ownership, "runtime_common");
    assert.strictEqual(entry.routes.length, 1);
    const route = entry.routes[0];
    assert.strictEqual(route.source, "runtime_common_action");
    assert.strictEqual(route.owner_action_id, Number(id));
    assert.strictEqual(route.display_action_id, Number(id));
    assert.strictEqual(route.runtime_common_evidence, true);
    assert.strictEqual(route.runtime_common_reason, "sf6_stable_runtime_common_movement_action");
}

// Type63 is the sole whitelist: inherited routes retain the original BCM owner.
assert.strictEqual(output["715"].ownership, "direct");
assert.strictEqual(output["716"].ownership, "inherited");
assert.strictEqual(output["716"].modern_display, "2 + THROW");
assert.strictEqual(output["716"].routes[0].owner_action_id, 715);
assert.strictEqual(output["716"].routes[0].ac_relation_type, 63);
assert.deepStrictEqual(output["716"].routes[0].ac_path, [715, 716]);
assert.strictEqual(output["717"].modern_display, "4 + THROW");
assert.strictEqual(output["717"].routes[0].owner_action_id, 715);
assert.deepStrictEqual(output["717"].routes[0].ac_path, [715, 716, 717]);
assert.strictEqual(output["718"].ownership, "direct");
assert.strictEqual(output["718"].routes[0].owner_action_id, 718);
assert.strictEqual(output["718"].routes[0].ac_relation_type, null);

const requiredFields = [
    "character", "owner_action_id", "trigger_index", "profile", "command_no", "command_index",
    "raw_direction_inputs", "raw_button_mask", "raw_button_condition", "raw_dc_exc_flags",
    "raw_ng_key_flags",
    "visible_direction", "visible_button", "button_candidates", "required_button_count", "source",
    "ac_relation_type", "ac_path", "inherited_from_action_id", "confidence", "direct_evidence",
    "inheritance_evidence", "inheritance_reason", "rebind_evidence", "rebind_reason",
    "runtime_common_evidence", "runtime_common_reason",
    "official_semantic_evidence", "official_semantic_reason",
    "community_semantic_evidence", "community_semantic_reason",
    "assist_combo_evidence", "assist_combo_reason"
];
for (const [id, entry] of Object.entries(output).filter(([key]) => /^\d+$/.test(key))) {
    assert.strictEqual(Object.prototype.hasOwnProperty.call(entry, "classic_display"), false);
    for (const route of entry.routes) {
        for (const field of requiredFields) assert(Object.prototype.hasOwnProperty.call(route, field), `${id}:${field}`);
        assert.strictEqual(route.character, "Zangief");
        assert(Number.isFinite(route.owner_action_id));
        assert.strictEqual([route.direct_evidence, route.inheritance_evidence, route.rebind_evidence,
            route.runtime_common_evidence, route.official_semantic_evidence,
            route.community_semantic_evidence]
            .filter(Boolean).length, 1);
        modern.assertValidDisplay(route.display);
    }
}

assert.strictEqual(output._meta.unresolved_candidates.some(item => item.action_id === 1015), false);
const candidate1077 = output._meta.unresolved_candidates.find(item =>
    item.action_id === 1077 && item.profile === "easy");
assert(candidate1077);
assert.strictEqual(candidate1077.required_button_count, 1);
assert.deepStrictEqual(candidate1077.button_candidates, ["弱", "中", "强"]);
assert.strictEqual(candidate1077.reason, "multi_button_candidate_requires_runtime_selection");
assert.strictEqual(output["924"].routes.find(route => route.profile === "sprt").required_button_count, 2);
assert.strictEqual(output["918"].routes.find(route => route.profile === "sprt").visible_button, "任意键");
assert.strictEqual(output["924"].routes.find(route => route.profile === "sprt").visible_button,
    "任意键 + 任意键");

for (const route of output["918"].routes.concat(output["924"].routes)) {
    assert.strictEqual(route.source, "ac_command_entry_rebind");
    assert.strictEqual(route.display_action_id, route.ac_path[1]);
    assert.strictEqual(route.bcm_owner_action_id, route.ac_path[0]);
    assert.strictEqual(route.owner_action_id, route.bcm_owner_action_id);
    assert.strictEqual(route.ac_relation_type, 17);
    assert.strictEqual(route.ac_attr, 0);
    assert.strictEqual(route.ac_frame, 0);
    assert.strictEqual(route.ac_param00, 9);
    assert.strictEqual(route.ac_param01, 120);
    for (const field of ["ac_param02", "ac_param03", "ac_param04", "ac_param05"]) {
        assert.strictEqual(route[field], 0);
    }
    assert.strictEqual(route.ac_trigger_id, -1);
    assert.strictEqual(route.confidence, "verified_rebind");
    assert.strictEqual(route.direct_evidence, false);
    assert.strictEqual(route.inheritance_evidence, false);
    assert.strictEqual(route.rebind_evidence, true);
    assert.strictEqual(route.runtime_common_evidence, false);
    assert.strictEqual(route.rebind_reason,
        "ac_type17_command_entry_rebind_from_verified_bcm_owner");
}

const audit = output._meta.audit;
for (const key of [
    "owner_missing_count", "no_evidence_count", "direct_overridden_count",
    "non_whitelist_propagation_count", "overlay_entry_count", "community_route_count",
    "legacy_supplement_entry_count", "classic_fallback_count", "classic_token_leak_count",
    "alias_propagation_count",
    "type17_route_count", "ac_automatic_transition_route_count", "replaces_profile_route_count"
]) assert.strictEqual(audit[key], 0, key);
assert.strictEqual(audit.ac_type17_relation_count, 6);
assert.strictEqual(audit.ac_command_entry_rebind_signature_count, 2);
assert.strictEqual(audit.ac_command_entry_rebind_relation_count, 2);
assert.strictEqual(audit.ac_command_entry_rebind_route_count, 4);
assert.strictEqual(output._meta.rebind_route_count, 4);
assert.strictEqual(audit.runtime_common_action_count, 6);
assert.strictEqual(audit.runtime_common_route_count, 6);
assert.strictEqual(output._meta.runtime_common_route_count, 6);
assert.strictEqual(audit.type20_directional_relation_count, 2);
assert.strictEqual(audit.type20_directional_route_count, 2);
assert.strictEqual(audit.target_combo_repeat_relation_count, 1);
assert.strictEqual(audit.target_combo_repeat_route_count, 1);
assert.strictEqual(audit.structural_twin_relation_count, 1);
assert.strictEqual(audit.structural_twin_route_count, 2);
assert.strictEqual(audit.assist_combo_candidate_count, 4);
assert.strictEqual(audit.assist_combo_relation_count, 2);
assert.strictEqual(audit.assist_combo_route_count, 2);
assert.strictEqual(audit.assist_combo_duplicate_display_count, 1);
assert.strictEqual(audit.assist_combo_normalized_to_existing_count, 1);
assert.strictEqual(audit.shadowed_supr_route_count, 2);
assert.deepStrictEqual(output._meta.shadowed_supr_routes.map(item =>
    [item.action_id, item.reason, item.shadowed_by_action_ids]), [
    [976, "drive_cost_owner_owns_identical_family_shortcut", [977]],
    [978, "official_semantic_owns_identical_shortcut", [627]]
]);
assert.strictEqual(output._meta.assist_combo_route_count, 2);
assert.strictEqual(output._meta.assist_combo_normalized_to_existing_count, 1);
assert.strictEqual(output._meta.assist_combo_relations.length, 2);
assert.deepStrictEqual(output._meta.runtime_common_actions.map(item => [item.action_id, item.display]),
    [[17, "66"], [18, "44"], [36, "8"], [37, "9"], [38, "7"], [489, "DP"]]);
assert.deepStrictEqual(output._meta.ac_command_entry_rebinds.map(item =>
    [item.source_action_id, item.target_action_id]), [[1015, 918], [1020, 924]]);
assert.strictEqual(audit.official_semantic_binding_count, 2);
assert.strictEqual(audit.official_semantic_route_count, 2);
assert.strictEqual(audit.official_semantic_unresolved_count, 0);
assert.strictEqual(audit.official_semantic_qualified_direct_route_count, 1);
assert.strictEqual(output._meta.official_semantic_qualified_direct_route_count, 1);
assert.strictEqual(output._meta.official_semantic_source_sha256, "official");
assert.deepStrictEqual(output._meta.official_semantic_bindings.map(item =>
    [item.official_action_id_hint, item.target_action_id, item.action_id_distance]),
    [[627, 627, 0], [642, 642, 0]]);
const officialRoute = output["627"].routes[0];
assert.strictEqual(officialRoute.source, "official_semantic_bcm_rebind");
assert.strictEqual(officialRoute.owner_action_id, 627);
assert.strictEqual(officialRoute.official_semantic_evidence, true);
assert.strictEqual(officialRoute.official_action_id_hint, 627);
assert.strictEqual(officialRoute.official_action_id_distance, 0);
assert.deepStrictEqual(output._meta.official_semantic_bindings[1].qualified_direct_displays,
    ["空中 强"]);
assert.strictEqual(output["642"].routes.some(route => route.direct_evidence === true), false);

const clone = value => JSON.parse(JSON.stringify(value));
const rebuild = (ac, bcm, compiled) => modern.buildModernDisplay(
    ac || actionSource, bcm || catalog, compiled || runtime, {}, { generatedAt: "negative" });

// Every field in the raw BranchKey signature is mandatory.
const missingParam = clone(actionSource);
branchObject(missingParam, 918, 9).fields = branchObject(missingParam, 918, 9).fields
    .filter(field => field.name !== "Param05");
assert.strictEqual(rebuild(missingParam)["918"], undefined);
const wrongTrigger = clone(actionSource);
branchObject(wrongTrigger, 918, 9).fields.find(field => field.name === "TriggerID").value.value = 0;
assert.strictEqual(rebuild(wrongTrigger)["918"], undefined);
const wrongRelationFrame = clone(actionSource);
branchObject(wrongRelationFrame, 918, 9).fields
    .find(field => field.name === "ActionFrame").value.value = 1;
assert.strictEqual(rebuild(wrongRelationFrame)["918"], undefined);
const wrongParam00 = clone(actionSource);
branchObject(wrongParam00, 918, 9).fields.find(field => field.name === "Param00").value.value = 8;
assert.strictEqual(rebuild(wrongParam00)["918"], undefined);
const wrongParam01 = clone(actionSource);
branchObject(wrongParam01, 918, 9).fields.find(field => field.name === "Param01").value.value = 119;
assert.strictEqual(rebuild(wrongParam01)["918"], undefined);
const sourceSelfLoop = clone(actionSource);
branchObject(sourceSelfLoop, 918, 9).fields.find(field => field.name === "Action").value.value = 1015;
assert.strictEqual(rebuild(sourceSelfLoop)["918"], undefined);

// Frame order, structural category, target stage family, target BCM absence,
// and ground-only source triggers are independent hard gates.
const reversedFrame = clone(actionSource);
actionRoot(reversedFrame, 918).fields.find(field => field.name === "Frame").value.value = 70;
assert.strictEqual(rebuild(reversedFrame)["918"], undefined);
const changedCategory = clone(actionSource);
const differentCategoryId = Math.max(...changedCategory.objects.map(object => object.object_id)) + 1;
changedCategory.objects.push({ object_id: differentCategoryId, kind: "managed-object",
    object_type: "Test.Category.Different", fields: [] });
actionRoot(changedCategory, 918).fields.find(field => field.name === "Category").value = ref(differentCategoryId);
assert.strictEqual(rebuild(changedCategory)["918"], undefined);
const missingSelfStage = clone(actionSource);
branchObject(missingSelfStage, 918, 10).fields.find(field => field.name === "Param00").value.value = 11;
assert.strictEqual(rebuild(missingSelfStage)["918"], undefined);
const targetHasBcm = clone(catalog);
targetHasBcm.actions["918"] = { action_id: 918, triggers: [] };
assert.strictEqual(rebuild(actionSource, targetHasBcm)["918"], undefined);
const sourceWithoutBcm = clone(catalog);
delete sourceWithoutBcm.actions["1015"];
assert.strictEqual(rebuild(actionSource, sourceWithoutBcm)["918"], undefined);
const airSource = clone(catalog);
airSource.actions["1015"].triggers[0].conditions.cond_owner_state_flags = 4;
assert.strictEqual(rebuild(actionSource, airSource)["918"], undefined);

// Normal and OD resource entries on different trigger structures cannot be
// merged into one command-entry owner.
const normalOdConflict = clone(catalog);
const odTrigger = clone(normalOdConflict.actions["1015"].triggers[0]);
odTrigger.trigger_index = 88;
odTrigger.conditions.focus_consume = 20000;
normalOdConflict.actions["1015"].triggers.push(odTrigger);
const normalOdOutput = rebuild(actionSource, normalOdConflict);
assert.strictEqual(normalOdOutput["918"], undefined);
assert.strictEqual(normalOdOutput["1015"].ownership, "direct");

// Rebound targets contain their own Type17 stage family. They must never feed
// another rebind pass, and every accepted path remains exactly one hop.
assert.strictEqual(output._meta.ac_command_entry_rebinds.some(relation =>
    relation.source_action_id === 918 || relation.source_action_id === 924), false);
assert.strictEqual(output["918"].routes.every(route => route.ac_path.length === 2
    && route.ac_path[0] === 1015 && route.ac_path[1] === 918), true);
assert.strictEqual(output["924"].routes.every(route => route.ac_path.length === 2
    && route.ac_path[0] === 1020 && route.ac_path[1] === 924), true);
assert.strictEqual(output["917"], undefined);
assert.strictEqual(output["923"], undefined);

// A source with more than one Type17 target is ambiguous and must stay direct.
const ambiguousSource = clone(actionSource);
const duplicateBranch = clone(branchObject(ambiguousSource, 918, 9));
duplicateBranch.object_id = Math.max(...ambiguousSource.objects.map(object => object.object_id)) + 1;
duplicateBranch.fields.find(field => field.name === "Action").value.value = 924;
ambiguousSource.objects.push(duplicateBranch);
const sourceKeys = actionRoot(ambiguousSource, 1015).fields.find(field => field.name === "Keys").value.object_id;
const sourceKeysObject = ambiguousSource.objects.find(object => object.object_id === sourceKeys);
sourceKeysObject.items.push({ index: sourceKeysObject.items.length, value: ref(duplicateBranch.object_id) });
assert.strictEqual(rebuild(ambiguousSource)["918"], undefined);

// Official Action IDs are hints, never targets. A stale ID is rebound to the
// unique nearest current BCM owner with the same Classic command identity.
const semanticCatalog = ids => ({ source: { character: "Semantic" }, actions: Object.fromEntries(ids.map(id =>
    [String(id), { action_id: id, triggers: [trigger(id, profiles(null, null, null,
        profile(true, "2+LK", 64)), { function_id: 1 })] }])) });
const semanticRuntime = ids => ({ character: "Semantic", fighter_id: 100, action_ids: ids,
    sources: {}, validation: { rules: {} }, evidence: { ac_derived_commands: [] } });
const semanticInput = { "625": { classic_display: "2 + LK", modern_display: "AUTO + 弱",
    category: "NORMAL", official_web_id: "110", move_name: "semantic normal" } };
const staleIdOutput = modern.buildModernDisplay({}, semanticCatalog([626, 627, 628]),
    semanticRuntime([626, 627, 628]), {}, { generatedAt: "stale", officialSemantics: semanticInput });
assert.strictEqual(staleIdOutput["626"].modern_display, "AUTO + 弱");
assert.strictEqual(staleIdOutput["627"], undefined);
assert.strictEqual(staleIdOutput["628"], undefined);
assert.strictEqual(staleIdOutput["626"].routes[0].official_action_id_hint, 625);
assert.strictEqual(staleIdOutput["626"].routes[0].official_action_id_distance, 1);

// Equal-distance candidates are not guessed.
const tiedOutput = modern.buildModernDisplay({}, semanticCatalog([624, 626]),
    semanticRuntime([624, 626]), {}, { generatedAt: "tie", officialSemantics: semanticInput });
assert.strictEqual(tiedOutput["624"], undefined);
assert.strictEqual(tiedOutput["626"], undefined);
assert.strictEqual(tiedOutput._meta.official_semantic_unresolved[0].reason,
    "ambiguous_nearest_current_bcm_identity");

// Paired official table dumps carry no Action IDs. Bind only when the current
// BCM identity has one unique owner without its own Modern profile.
const rowSemanticCatalog = { source: { character: "SemanticRows" }, actions: {
    "600": { action_id: 600, triggers: [trigger(600, profiles(null, null, null,
        profile(true, "LP", 16)), { function_id: 1 })] },
    "601": { action_id: 601, triggers: [trigger(601, profiles(
        profile(true, "LP", 16, 16416, { ng_key_flags: 512 }), null, null,
        profile(true, "LP", 16)), { function_id: 1 })] }
} };
const rowSemanticRuntime = { character: "SemanticRows", fighter_id: 101,
    action_ids: [600, 601], sources: {}, validation: { rules: {} },
    evidence: { ac_derived_commands: [], alias_relations: [] }, aliases: {} };
const rowSemanticInput = { _semantic_rows: [{ row_id: "en:0:0", classic_display: "LP",
    modern_display: "AUTO + 弱", category: "NORMAL", move_name: "Standing Light Punch" }] };
const rowSemanticOutput = modern.buildModernDisplay({}, rowSemanticCatalog, rowSemanticRuntime, {},
    { generatedAt: "semantic-rows", officialSemantics: rowSemanticInput });
assert.strictEqual(rowSemanticOutput["600"].modern_display, "AUTO + 弱");
assert.strictEqual(rowSemanticOutput["601"].modern_display, "弱");
assert.strictEqual(rowSemanticOutput["600"].routes[0].official_action_id_hint_kind,
    "derived_current_bcm_identity");
assert.strictEqual(rowSemanticOutput["600"].routes[0].official_semantic_row_id, "en:0:0");

// dc_exc_flags 0x200 is the player-visible AUTO modifier; ng_key_flags 0x200
// marks the otherwise identical plain route. This distinction is character-agnostic.
const autoAirCatalog = { source: { character: "AutoAir" }, actions: {
    "650": { action_id: 650, triggers: [trigger(650, profiles(
        profile(true, "j.LP", 16, 16416, { ng_key_flags: 512 }), null, null,
        profile(true, "j.LP", 16)), { function_id: 1, cond_owner_state_flags: 4 })] },
    "653": { action_id: 653, triggers: [trigger(653, profiles(
        profile(true, "j.LP", 16, 16416, { dc_exc_flags: 512 }), null, null,
        profile(true, "j.LK", 64)), { function_id: 1, cond_owner_state_flags: 4 })] }
} };
const autoAirRuntime = { character: "AutoAir", fighter_id: 102, action_ids: [650, 653],
    aliases: {}, sources: {}, validation: { rules: {} },
    evidence: { ac_derived_commands: [], alias_relations: [] } };
const autoAirOutput = modern.buildModernDisplay({}, autoAirCatalog, autoAirRuntime, {},
    { generatedAt: "auto-air" });
assert.strictEqual(autoAirOutput["650"].modern_display, "空中 弱");
assert.strictEqual(autoAirOutput["653"].modern_display, "空中 AUTO + 弱");
assert.strictEqual(autoAirOutput["650"].routes[0].raw_ng_key_flags, 512);
assert.strictEqual(autoAirOutput["653"].routes[0].raw_dc_exc_flags, 512);

// The high supr bit is an internal action selector, not AUTO+中. If an easy
// profile exists it owns the visible shortcut; otherwise only the manual sprt
// route remains. This rule has no character or Action-ID dependency.
const specialCatalog = { source: { character: "OfficialSpecial" }, actions: {
    "2000": { action_id: 2000, triggers: [trigger(2000, profiles(
        profile(true, "236+LP", 16, 81952), null,
        profile(true, "Normal", 2147483648), profile(true, "236+LP", 16)),
    { function_id: 2 })] },
    "2001": { action_id: 2001, triggers: [trigger(2001, profiles(
        profile(true, "236+LP+LK+MK", 400, 82016),
        profile(true, "2+MP", 32, 16416, { dc_exc_flags: 512 }),
        profile(true, "Normal", 2147483648), profile(true, "236+PP", 112)),
    { function_id: 2, focus_consume: 20000 })] },
    "2002": { action_id: 2002, triggers: [trigger(2002, profiles(
        profile(true, "22+LP+LK+MK", 400, 81952), null,
        profile(true, "2", 8192), profile(true, "22+P", 112)),
    { function_id: 2 })] },
    "2003": { action_id: 2003, triggers: [trigger(2003, profiles(
        profile(true, "4+MP", 32, 16416, { command_no: -1 }), null,
        profile(true, "4", 8192), profile(true, "63214+K", 896, 81952,
            { command_no: 39, command_index: 16 })),
    { function_id: 2, focus_consume: 0, turn_around: 1, kind_level: 8 })] },
    "2004": { action_id: 2004, triggers: [trigger(2004, profiles(
        profile(true, "22+LP+LK+MK", 400, 81952), null,
        profile(true, "2", 8192), profile(true, "22+P", 112)),
    { function_id: 2, focus_consume: 0 })] },
    "2005": { action_id: 2005, triggers: [trigger(2005, profiles(null,
        profile(true, "4+MP", 32, 16416, { dc_exc_flags: 516 }), null,
        profile(true, "63214+KK", 896, 82016, { command_no: 39, command_index: 16 })),
    { function_id: 2, focus_consume: 20000, turn_around: 1, kind_level: 8 })] },
    "2006": { action_id: 2006, triggers: [trigger(2006, profiles(
        profile(true, "3+MP", 32, 16416, { dc_exc_flags: 2 }), null, null,
        profile(true, "214+P", 112, 81952)),
    { function_id: 2 })] },
    "2007": { action_id: 2007, triggers: [trigger(2007, profiles(
        profile(true, "3+MP", 32, 16416, { dc_exc_flags: 514 }), null, null,
        profile(true, "214+PP", 112, 82016)),
    { function_id: 2, focus_consume: 20000 })] },
    "2008": { action_id: 2008, triggers: [trigger(2008, profiles(
        null,
        profile(true, "j.LP+MP+LK+MK", 432, 16416, { ng_key_flags: 2 }),
        profile(true, "j.Normal", 8192, 16416, { ng_key_flags: 2 }),
        profile(true, "j.P", 112, 16416)),
    { function_id: 2, kind_level: 8 })] }
} };
const specialRuntime = { character: "OfficialSpecial", fighter_id: 103,
    action_ids: [2000, 2001, 2002, 2003, 2004, 2005, 2006, 2007, 2008], aliases: {}, sources: {}, validation: { rules: {} },
    evidence: { ac_derived_commands: [], alias_relations: [] } };
const specialOutput = modern.buildModernDisplay({}, specialCatalog, specialRuntime, {},
    { generatedAt: "internal-selector" });
assert.strictEqual(specialOutput["2000"].modern_display, "236 + 弱");
assert.strictEqual(specialOutput["2000"].routes.some(route => route.profile === "supr"), false);
assert.strictEqual(specialOutput["2001"].modern_display,
    "2 + AUTO + SP/236 + 任意键 + 任意键");
assert.strictEqual(specialOutput["2002"].modern_display, "22 + 任意键");
assert.strictEqual(specialOutput["2003"].modern_display, "4 + SP");
assert.strictEqual(specialOutput["2005"].modern_display, "4 + AUTO + SP");
assert.strictEqual(specialOutput._meta.audit.paired_sprt_sp_relation_count, 1);
assert.strictEqual(specialOutput["2004"].modern_display, "22 + 任意键");
assert.strictEqual(specialOutput["2006"].modern_display, "3 + SP");
assert.strictEqual(specialOutput["2007"].modern_display, "3 + AUTO + SP");
assert.strictEqual(specialOutput["2008"].modern_display, "> 空中 任意键");
assert.strictEqual(specialOutput._meta.shadowed_supr_routes.some(item =>
    item.action_id === 2004 && item.reason === "direct_non_supr_route_owns_identical_shortcut"
    && item.shadowed_by_action_ids[0] === 2001), true);

function makeStrictHoldActionSource(sourceLoop, targetLoop) {
    let id = 1;
    const objects = [], records = [];
    const add = object => { const result = { object_id: id++, ...object }; objects.push(result); return result.object_id; };
    const targetState = add({ object_type: "CharacterAsset.ActionState",
        fields: [{ name: "LoopCount", value: scalar(targetLoop) }] });
    const targetKeys = add({ object_type: "Test.Keys", items: [] });
    const targetRoot = add({ object_type: "FAB.ACTION", fields: [
        { name: "State", value: ref(targetState) }, { name: "Keys", value: ref(targetKeys) }
    ] });
    const branchId = add({ object_type: "CharacterAsset.BranchKey", fields: [
        ["Action", 3001], ["Type", 20], ["Param00", 1], ["Param01", 112],
        ["Param02", 0], ["Param03", 1]
    ].map(([name, value]) => ({ name, value: scalar(value) })) });
    const sourceKeys = add({ object_type: "Test.Keys",
        items: [{ index: 0, value: ref(branchId) }] });
    const sourceState = add({ object_type: "CharacterAsset.ActionState",
        fields: [{ name: "LoopCount", value: scalar(sourceLoop) }] });
    const sourceRoot = add({ object_type: "FAB.ACTION", fields: [
        { name: "State", value: ref(sourceState) }, { name: "Keys", value: ref(sourceKeys) }
    ] });
    records.push({ source_scope: "character", native_action_id: 3000, action_ref: ref(sourceRoot) });
    records.push({ source_scope: "character", native_action_id: 3001, action_ref: ref(targetRoot) });
    return { objects, records };
}
const holdCatalog = { source: { character: "HoldEvidence" }, actions: {
    "3000": { action_id: 3000, triggers: [trigger(3000, profiles(
        profile(true, "22+LP+LK+MK", 400, 81952), null, null,
        profile(true, "22+P", 112)), { function_id: 2 })] }
} };
const holdRuntime = { character: "HoldEvidence", fighter_id: 104,
    action_ids: [3000, 3001], aliases: {}, sources: {}, validation: { rules: {} },
    evidence: { ac_derived_commands: [], alias_relations: [] } };
const holdOutput = modern.buildModernDisplay(makeStrictHoldActionSource(0, -1),
    holdCatalog, holdRuntime, {}, { generatedAt: "type20-hold" });
assert.strictEqual(holdOutput["3001"].modern_display, "> 任意键");
assert.strictEqual(holdOutput["3001"].routes[0].source, "ac_type20_hold_continuation");
assert.strictEqual(holdOutput._meta.audit.type20_hold_relation_count, 1);
const rejectedHold = modern.buildModernDisplay(makeStrictHoldActionSource(-1, -1),
    holdCatalog, holdRuntime, {}, { generatedAt: "type20-hold-negative" });
assert.strictEqual(rejectedHold["3001"], undefined);

function makeType20ActionPhaseSource(complete) {
    let id = 1;
    const objects = [], records = [];
    const add = object => { const result = { object_id: id++, ...object }; objects.push(result); return result.object_id; };
    const targetKeys = add({ object_type: "Test.Keys", items: [] });
    const targetRoot = add({ object_type: "FAB.ACTION", fields: [{ name: "Keys", value: ref(targetKeys) }] });
    const signatures = [[0, 8, 1], [0, 32, 2], [0, 8192, 3], [1, 8192, 3]];
    if (!complete) signatures.pop();
    const items = signatures.map(([param00, param01, param03], index) => {
        const branch = add({ object_type: "CharacterAsset.BranchKey", fields: [
            ["Action", 3101], ["Type", 20], ["Attr", 288], ["ActionFrame", 0],
            ["Param00", param00], ["Param01", param01], ["Param02", 0], ["Param03", param03],
            ["Param04", 0], ["Param05", 0], ["TriggerID", -1]
        ].map(([name, value]) => ({ name, value: scalar(value) })) });
        return { index, value: ref(branch) };
    });
    const sourceKeys = add({ object_type: "Test.Keys", items });
    const sourceRoot = add({ object_type: "FAB.ACTION", fields: [{ name: "Keys", value: ref(sourceKeys) }] });
    records.push({ source_scope: "character", native_action_id: 3100, action_ref: ref(sourceRoot) });
    records.push({ source_scope: "character", native_action_id: 3101, action_ref: ref(targetRoot) });
    return { objects, records };
}
const phaseCatalog = { source: { character: "ActionPhase" }, actions: {
    "3100": { action_id: 3100, triggers: [trigger(3100, profiles(null,
        profile(true, "6+MP", 32, 16416), null, null), { function_id: 2 })] }
} };
const phaseRuntime = { character: "ActionPhase", fighter_id: 106,
    action_ids: [3100, 3101], aliases: {}, sources: {}, validation: { rules: {} },
    evidence: { ac_derived_commands: [], alias_relations: [] } };
const phaseOutput = modern.buildModernDisplay(makeType20ActionPhaseSource(true), phaseCatalog,
    phaseRuntime, {}, { generatedAt: "type20-action-phase" });
assert.strictEqual(phaseOutput["3100"].modern_display, "6 + SP");
assert.strictEqual(phaseOutput["3101"].modern_display, "6 + SP");
assert.strictEqual(phaseOutput["3101"].ownership, "type20_action_phase");
assert.strictEqual(phaseOutput._meta.audit.type20_action_phase_relation_count, 1);
const rejectedPhase = modern.buildModernDisplay(makeType20ActionPhaseSource(false), phaseCatalog,
    phaseRuntime, {}, { generatedAt: "type20-action-phase-negative" });
assert.strictEqual(rejectedPhase["3101"], undefined);

// Only compiler-verified Type29/35 equivalent-action aliases inherit a route.
const aliasRuntime = clone(runtime);
aliasRuntime.evidence.alias_relations = [{ alias_action_id: 979, target_action_id: 903,
    relation: "equivalent-action-variant", source: "ac-branch", branch_type: 29 }];
const aliasOutput = rebuild(actionSource, catalog, aliasRuntime);
assert.strictEqual(aliasOutput["979"].modern_display, "SP/236 + 强");
assert.strictEqual(aliasOutput["903"].modern_display, "SP/236 + 强");
assert.strictEqual(aliasOutput["979"].ownership, "verified_alias");
assert.strictEqual(aliasOutput["979"].routes[0].source, "ac_verified_alias_variant");
assert.strictEqual(aliasOutput["979"].routes[0].inherited_from_action_id, 903);
assert.strictEqual(aliasOutput._meta.audit.verified_alias_relation_count, 1);
const rejectedAliasRuntime = clone(aliasRuntime);
rejectedAliasRuntime.evidence.alias_relations[0].branch_type = 17;
assert.strictEqual(rebuild(actionSource, catalog, rejectedAliasRuntime)["979"], undefined);

// A Type29 target reached from multiple distinct source actions, including a
// verified Type20 hold continuation, is an automatic hold/state transition.
// It cannot inherit an arbitrary command from one of the other source actions.
function makeAmbiguousType29ActionSource() {
    let id = 1;
    const objects = [], records = [];
    const add = object => { const result = { object_id: id++, ...object }; objects.push(result); return result.object_id; };
    const targetState = add({ object_type: "CharacterAsset.ActionState",
        fields: [{ name: "LoopCount", value: scalar(-1) }] });
    const targetKeys = add({ object_type: "Test.Keys", items: [] });
    const targetRoot = add({ object_type: "FAB.ACTION", fields: [
        { name: "Keys", value: ref(targetKeys) }, { name: "State", value: ref(targetState) }
    ] });
    for (const sourceId of [4000, 4001]) {
        const branch = add({ object_type: "CharacterAsset.BranchKey", fields: [
            ["Action", 4002], ["Type", 29], ["Param00", 0], ["Param01", 0],
            ["Param02", 0], ["Param03", 3]
        ].map(([name, value]) => ({ name, value: scalar(value) })) });
        const items = [{ index: 0, value: ref(branch) }];
        if (sourceId === 4000) {
            const holdBranch = add({ object_type: "CharacterAsset.BranchKey", fields: [
                ["Action", 4001], ["Type", 20], ["Param00", 1], ["Param01", 112],
                ["Param02", 0], ["Param03", 1]
            ].map(([name, value]) => ({ name, value: scalar(value) })) });
            items.push({ index: 1, value: ref(holdBranch) });
        }
        const keys = add({ object_type: "Test.Keys", items });
        const state = add({ object_type: "CharacterAsset.ActionState",
            fields: [{ name: "LoopCount", value: scalar(sourceId === 4000 ? 0 : -1) }] });
        const root = add({ object_type: "FAB.ACTION", fields: [
            { name: "Keys", value: ref(keys) }, { name: "State", value: ref(state) }
        ] });
        records.push({ source_scope: "character", native_action_id: sourceId, action_ref: ref(root) });
    }
    records.push({ source_scope: "character", native_action_id: 4002, action_ref: ref(targetRoot) });
    return { objects, records };
}
const ambiguousAliasCatalog = { source: { character: "AmbiguousAlias" }, actions: {
    "4000": { action_id: 4000, triggers: [trigger(4000, profiles(
        profile(true, "236+HP", 256, 16416), null, null,
        profile(true, "236+HP", 256)), { function_id: 2 })] }
} };
const ambiguousAliasRuntime = { character: "AmbiguousAlias", fighter_id: 105,
    action_ids: [4000, 4001, 4002], aliases: { "4002": "4000" }, sources: {},
    validation: { rules: {} }, evidence: { ac_derived_commands: [], alias_relations: [{
        alias_action_id: 4002, target_action_id: 4000, relation: "equivalent-action-variant",
        source: "ac-branch", branch_type: 29
    }] } };
const ambiguousAliasOutput = modern.buildModernDisplay(makeAmbiguousType29ActionSource(),
    ambiguousAliasCatalog, ambiguousAliasRuntime, {}, { generatedAt: "ambiguous-type29" });
assert.strictEqual(ambiguousAliasOutput["4000"].modern_display, "236 + 强");
assert.strictEqual(ambiguousAliasOutput["4002"].modern_display, null);
assert.strictEqual(ambiguousAliasOutput["4002"].suppress_display, true);
assert.strictEqual(ambiguousAliasOutput["4002"].ownership, "automatic_hold_transition");
assert.deepStrictEqual(ambiguousAliasOutput["4002"].routes, []);
assert.strictEqual(ambiguousAliasOutput._meta.audit.hold_transition_type29_alias_suppression_count, 1);
assert.strictEqual(ambiguousAliasOutput._meta.audit.hold_transition_suppressed_action_count, 1);
assert.deepStrictEqual(ambiguousAliasOutput._meta.hold_transition_type29_alias_suppressions[0]
    .incoming_source_action_ids, [4000, 4001]);

// The same evidence model works without character or Action-ID hardcoding.
const offset = 5000;
const remappedAc = clone(actionSource);
for (const record of remappedAc.records) record.native_action_id += offset;
for (const object of remappedAc.objects.filter(item => item.object_type === "CharacterAsset.BranchKey")) {
    object.fields.find(field => field.name === "Action").value.value += offset;
}
for (const record of remappedAc.records) {
    actionRoot(remappedAc, record.native_action_id).fields
        .find(field => field.name === "ActionID").value.value = record.native_action_id;
}
const remappedCatalog = { source: { character: "EvidenceOnly" }, actions: {
    [String(1015 + offset)]: clone(catalog.actions["1015"]),
    [String(1020 + offset)]: clone(catalog.actions["1020"])
} };
const remappedRuntime = {
    character: "EvidenceOnly", fighter_id: 99,
    action_ids: [1015, 1020, 918, 924, 917, 923].map(id => id + offset),
    sources: { ac_sha256: "ac", bcm_sha256: "bcm" },
    validation: { rules: {} }, evidence: { ac_derived_commands: [] }
};
const remapped = rebuild(remappedAc, remappedCatalog, remappedRuntime);
assert.strictEqual(remapped[String(1015 + offset)], undefined);
assert.strictEqual(remapped[String(918 + offset)].modern_display,
    "4 + SP/63214 + 任意键");
assert.strictEqual(remapped[String(924 + offset)].modern_display,
    "4 + AUTO + SP/63214 + 任意键 + 任意键");

assert.throws(() => modern.buildModernDisplay({}, catalog, runtime, {
    "600": { modern_display: "AUTO + 弱" }
}, { generatedAt: "supplement" }), /supplement\/overlay input is disabled/);
for (const display of ["LP", "4 + HP", "P", "PP", "K", "KK", "4 + + SP", "攻击三つ", "* + SP"]) {
    assert.throws(() => modern.assertValidDisplay(display), /非法 Modern 显示 token/);
}
for (const display of ["SP", "DP", "DI", "4 + AUTO + SP", "弱 + 中 + 强",
    "63214 + 任意键", "63214 + 任意键 + 任意键"]) {
    assert.doesNotThrow(() => modern.assertValidDisplay(display));
}

const deterministic = modern.buildModernDisplay(actionSource, catalog, runtime, {}, {
    generatedAt: "test", officialSemantics, officialSemanticsSha256: "official"
});
assert.deepStrictEqual(deterministic, output);
console.log("Strict Modern display compiler tests passed.");
