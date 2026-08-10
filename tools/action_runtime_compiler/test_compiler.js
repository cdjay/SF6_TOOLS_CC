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
    unique_action_ids_by_scope: { character: [500, 501, 606, 661, 904, 905, 999, 1200] },
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
        "904": bcmAction(904, "236+LP", {}, "LP"),
        "1200": {
            action_id: 1200,
            classic_display: "6646+HP",
            triggers: [{
                trigger_index: 1200,
                classic_profile: "norm",
                classic_display: "6646+HP",
                profiles: { norm: {
                    button: "HP",
                    command: {
                        charge_bit: 256,
                        inputs: [
                            { direction: "6", charge_release: true },
                            { direction: "6", charge_release: false },
                            { direction: "4", charge_release: false },
                            { direction: "6", charge_release: false }
                        ]
                    }
                } },
                conditions: { function_id: 3, kind_level: 1 }
            }]
        }
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

const holdLevelSource = {
    schema: "sf6cr.action-catalog-full.v2",
    character: "Fab",
    fighter_id: 20,
    unique_action_ids_by_scope: { character: [1100, 1101, 1102, 1110, 1111, 1112, 1113] },
    objects: [
        action(400, 1100, 401),
        collection(401, [402, 403, 404, 405]),
        object(402, "CharacterAsset.BranchKey", { Action: scalar(1101), Type: scalar(29) }),
        object(403, "CharacterAsset.BranchKey", { Action: scalar(1102), Type: scalar(29) }),
        object(404, "CharacterAsset.BranchKey", { Action: scalar(1101), Type: scalar(20) }),
        object(405, "CharacterAsset.BranchKey", { Action: scalar(1102), Type: scalar(20) }),
        action(410, 1110, 411),
        collection(411, [412, 413, 414]),
        object(412, "CharacterAsset.BranchKey", { Action: scalar(1111), Type: scalar(20) }),
        object(413, "CharacterAsset.BranchKey", { Action: scalar(1112), Type: scalar(20) }),
        object(414, "CharacterAsset.BranchKey", { Action: scalar(1113), Type: scalar(0) })
    ],
    records: [
        { native_action_id: 1100, source_scope: "character", action_ref: ref(400) },
        { native_action_id: 1110, source_scope: "character", action_ref: ref(410) }
    ]
};
const holdLevelCatalog = {
    schema: "sf6cc.bcm-catalog.v1",
    source: { schema: "sf6cr.bcm-full.v1", character: "EHonda", fighter_id: 20, sha256: "bcm-hold" },
    actions: {
        "1100": bcmAction(1100, "236+P", {}, "P"),
        "1110": bcmAction(1110, "214+P", {}, "P")
    }
};
const holdLevelResult = compiler.compileFromCatalog(
    holdLevelSource, holdLevelCatalog, {}, { actionSourceSha256: "ac-hold" });
assert.strictEqual(holdLevelResult.runtime.aliases["1101"], undefined);
assert.strictEqual(holdLevelResult.runtime.aliases["1102"], undefined);
assert.strictEqual(holdLevelResult.runtime.actions["1101"], "236+P");
assert.strictEqual(holdLevelResult.runtime.actions["1102"], "236+P");
assert.strictEqual(holdLevelResult.runtime.validation.rules["1101"].force, true);
assert.strictEqual(holdLevelResult.runtime.validation.rules["1102"].force, true);
assert.strictEqual(holdLevelResult.runtime.validation.rules["1110"].is_holdable, undefined);

const directionalSource = {
    schema: "sf6cr.action-catalog-full.v2",
    character: "Fab",
    fighter_id: 20,
    unique_action_ids_by_scope: { character: [1300, 1301, 1302, 1310, 1311, 1312, 1320, 1321, 1330, 1331] },
    objects: [
        action(500, 1300, 501), collection(501, [502, 503]),
        object(502, "CharacterAsset.BranchKey", {
            Action: scalar(1301), Type: scalar(63), Param01: scalar(1), Param02: scalar(1)
        }),
        object(503, "CharacterAsset.BranchKey", {
            Action: scalar(1302), Type: scalar(63), Param01: scalar(8), Param02: scalar(0)
        }),
        action(510, 1310, 511), collection(511, [512]),
        object(512, "CharacterAsset.BranchKey", {
            Action: scalar(1311), Type: scalar(63), Param01: scalar(2), Param02: scalar(1)
        }),
        action(520, 1311, 521), collection(521, [522]),
        object(522, "CharacterAsset.BranchKey", {
            Action: scalar(1312), Type: scalar(63), Param01: scalar(4), Param02: scalar(1)
        }),
        action(530, 1320, 531), collection(531, [532]),
        object(532, "CharacterAsset.BranchKey", {
            Action: scalar(1321), Type: scalar(20), Param00: scalar(1),
            Param01: scalar(2), Param02: scalar(0), Param03: scalar(0)
        }),
        action(540, 1330, 541), collection(541, [542]),
        object(542, "CharacterAsset.BranchKey", {
            Action: scalar(1331), Type: scalar(63), Param01: scalar(8), Param02: scalar(1)
        })
    ],
    records: [
        { native_action_id: 1300, source_scope: "character", action_ref: ref(500) },
        { native_action_id: 1310, source_scope: "character", action_ref: ref(510) },
        { native_action_id: 1311, source_scope: "character", action_ref: ref(520) },
        { native_action_id: 1320, source_scope: "character", action_ref: ref(530) },
        { native_action_id: 1330, source_scope: "character", action_ref: ref(540) }
    ]
};
const directionalCatalog = {
    schema: "sf6cc.bcm-catalog.v1",
    source: { schema: "sf6cr.bcm-full.v1", character: "EHonda", fighter_id: 20, sha256: "bcm-direction" },
    actions: {
        "1300": bcmAction(1300, "j.P", {}, "P"),
        "1310": bcmAction(1310, "Throw", {}, "Throw"),
        "1330": bcmAction(1330, "MP", {}, "MP")
    }
};
const directionalResult = compiler.compileFromCatalog(
    directionalSource, directionalCatalog, {}, { actionSourceSha256: "ac-direction" });
assert.strictEqual(directionalResult.runtime.actions["1301"], ">8+P");
assert.strictEqual(directionalResult.runtime.validation.rules["1301"].force, false);
assert.strictEqual(directionalResult.runtime.actions["1311"], "2+THROW");
assert.strictEqual(directionalResult.runtime.validation.rules["1311"].force, false);
assert.strictEqual(directionalResult.runtime.actions["1312"], "4+THROW");
assert.strictEqual(directionalResult.runtime.validation.rules["1312"].force, true);
assert.strictEqual(directionalResult.runtime.actions["1321"], undefined);
assert.strictEqual(directionalResult.runtime.actions["1302"], undefined);
assert.strictEqual(directionalResult.runtime.actions["1331"], undefined);

const strengthVariantSource = {
    schema: "sf6cr.action-catalog-full.v2",
    character: "Fab",
    fighter_id: 20,
    unique_action_ids_by_scope: { character: [1400, 1401, 1402] },
    objects: [
        action(600, 1400, 601), collection(601, [602, 603, 604, 605]),
        object(602, "CharacterAsset.BranchKey", {
            Action: scalar(1401), Type: scalar(63), Attr: scalar(256),
            ActionFrame: scalar(0), Param00: scalar(1), Param01: scalar(32),
            Param02: scalar(0), Param03: scalar(1)
        }),
        object(603, "CharacterAsset.BranchKey", {
            Action: scalar(1402), Type: scalar(63), Attr: scalar(256),
            ActionFrame: scalar(0), Param00: scalar(1), Param01: scalar(64),
            Param02: scalar(0), Param03: scalar(1)
        }),
        object(604, "CharacterAsset.BranchKey", {
            Action: scalar(1401), Type: scalar(63), Attr: scalar(256),
            ActionFrame: scalar(0), Param00: scalar(1), Param01: scalar(128),
            Param02: scalar(0), Param03: scalar(2)
        }),
        object(605, "CharacterAsset.BranchKey", {
            Action: scalar(1402), Type: scalar(63), Attr: scalar(256),
            ActionFrame: scalar(0), Param00: scalar(1), Param01: scalar(256),
            Param02: scalar(0), Param03: scalar(2)
        }),
        action(610, 1401, 611), collection(611, []),
        action(620, 1402, 621), collection(621, [])
    ],
    records: [
        { native_action_id: 1400, source_scope: "character", action_ref: ref(600) },
        { native_action_id: 1401, source_scope: "character", action_ref: ref(610) },
        { native_action_id: 1402, source_scope: "character", action_ref: ref(620) }
    ]
};
const strengthVariantCatalog = {
    schema: "sf6cc.bcm-catalog.v1",
    source: { schema: "sf6cr.bcm-full.v1", character: "Fab", fighter_id: 20,
        sha256: "bcm-strength-variant" },
    actions: { "1400": bcmAction(1400, "6+P", {}, "P") }
};
const strengthVariantResult = compiler.compileFromCatalog(
    strengthVariantSource, strengthVariantCatalog, {},
    { actionSourceSha256: "ac-strength-variant" });
assert.strictEqual(strengthVariantResult.runtime.actions["1400"], "6+LP");
assert.strictEqual(strengthVariantResult.runtime.actions["1401"], "6+MP");
assert.strictEqual(strengthVariantResult.runtime.actions["1402"], "6+HP");
assert.strictEqual(
    strengthVariantResult.runtime.validation.rules["1401"].display_source,
    "ac-type63-strength-variant");
assert.deepStrictEqual(
    strengthVariantResult.runtime.evidence.ac_derived_commands
        .filter(item => item.derivation === "type63_strength_variant")
        .map(item => [item.action_id, item.strength, item.classic_param01,
            item.modern_param01]),
    [[1401, "medium", 32, 128], [1402, "heavy", 64, 256]]);

const acFollowupSource = {
    schema: "sf6cr.action-catalog-full.v2",
    character: "Fab",
    fighter_id: 20,
    unique_action_ids_by_scope: { character: [1500, 1501, 1510, 1511, 1600, 1601, 1602, 1610, 1611] },
    objects: [
        action(700, 1500, 701), collection(701, [702, 703]),
        object(702, "CharacterAsset.BranchKey", { Action: scalar(1600), Type: scalar(16) }),
        object(703, "CharacterAsset.BranchKey", { Action: scalar(1601), Type: scalar(29) }),
        action(710, 1501, 711), collection(711, [712]),
        object(712, "CharacterAsset.BranchKey", { Action: scalar(1602), Type: scalar(16) }),
        action(720, 1510, 721), collection(721, [722, 723]),
        object(722, "CharacterAsset.BranchKey", { Action: scalar(1610), Type: scalar(20) }),
        object(723, "CharacterAsset.BranchKey", { Action: scalar(1611), Type: scalar(29) }),
        action(730, 1511, 731), collection(731, [732]),
        object(732, "CharacterAsset.BranchKey", { Action: scalar(1610), Type: scalar(20) })
    ],
    records: [
        { native_action_id: 1500, source_scope: "character", action_ref: ref(700) },
        { native_action_id: 1501, source_scope: "character", action_ref: ref(710) },
        { native_action_id: 1510, source_scope: "character", action_ref: ref(720) },
        { native_action_id: 1511, source_scope: "character", action_ref: ref(730) }
    ]
};
const acFollowupCatalog = {
    schema: "sf6cc.bcm-catalog.v1",
    source: { schema: "sf6cr.bcm-full.v1", character: "EHonda", fighter_id: 20, sha256: "bcm-ac-followup" },
    actions: {
        "1500": bcmAction(1500, "MP", { category_flags: 2 ** 37 }, "MP"),
        "1501": bcmAction(1501, "HP", { category_flags: 2 ** 37 }, "HP"),
        "1510": bcmAction(1510, "6+P", { category_flags: 2 ** 37 }, "P"),
        "1511": bcmAction(1511, "6+P", { category_flags: 2 ** 37 }, "P")
    }
};
const acFollowupResult = compiler.compileFromCatalog(
    acFollowupSource, acFollowupCatalog, {}, { actionSourceSha256: "ac-followup" });
assert.strictEqual(acFollowupResult.runtime.actions["1500"], ">MP");
assert.strictEqual(acFollowupResult.runtime.actions["1501"], "HP");
assert.strictEqual(acFollowupResult.runtime.actions["1510"], "6+P");
assert.strictEqual(acFollowupResult.runtime.actions["1511"], "6+P");
assert.strictEqual(acFollowupResult.runtime.validation.rules["1500"].followup_evidence,
    "ac-category37-branch-evidence");
assert.strictEqual(acFollowupResult.runtime.validation.rules["1510"].target_combo_followup, false);
assert.strictEqual(acFollowupResult.runtime.validation.rules["1510"].followup_evidence, undefined);

const withExceptions = compiler.compileFromCatalog(acSource, bcmCatalog, {
    "999": { force: true, absorb_ids: "" },
    "1000": { force: true }
}, { actionSourceSha256: "ac-test" });
assert.strictEqual(withExceptions.runtime.actions["999"], undefined);
assert.strictEqual(withExceptions.runtime.validation.rules["999"].force, true);
assert.strictEqual(withExceptions.runtime.coverage.manual_behavior_entry_count, 1);
assert.strictEqual(withExceptions.runtime.coverage.manual_validation_rule_count, 1);
assert.strictEqual(withExceptions.runtime.coverage.manual_absorb_alias_count, 0);
assert.strictEqual(withExceptions.report.status, "valid-with-warnings");
assert.strictEqual(withExceptions.report.diagnostics[0].code, "STALE_EXCEPTION_ACTION_ID");
assert.strictEqual(withExceptions.report.diagnostics.some(item => item.code === "STALE_EXCEPTION_ABSORB_ID"), false);

const explicitEmptyAbsorb = compiler.compileFromCatalog(acSource, bcmCatalog, {
    "904": { absorb_ids: "" }
}, { actionSourceSha256: "ac-test" });
assert.strictEqual(explicitEmptyAbsorb.runtime.aliases["905"], undefined);
const explicitAbsorb = compiler.compileFromCatalog(acSource, bcmCatalog, {
    "904": { absorb_ids: "905" }
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
