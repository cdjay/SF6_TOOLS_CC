import assert from "node:assert/strict";
import {
    applyMetadataEdits,
    applyVersionProfile,
    COMBO_JSON_EDITOR,
    findFirstContactStep,
    mechanismProjection,
    migrateComboDocument,
    normalizeCounterPolicyDocument,
    parseComboJson,
    resolveCounterPolicy,
    serializeComboJson,
    stripCounterTags,
    validateComboDocument
} from "./combo_json_core.mjs";

const legacy = [
    {
        _xt_meta: {
            schema: "xt.combo_trial.meta.v1",
            title: "测试连段",
            author: "作者",
            note: "",
            step_notes: [""],
            tags: null,
            character: "Ryu",
            version: 1,
            dummy_guard: "all"
        },
        dummy_guard: "all",
        id: 100,
        motion: "5HP",
        expected_combo: 1,
        expected_hp: 10000,
        delay_from_prev: 0,
        recorded_by: 0,
        timeline: ["1f : 5+HP"],
        scene_state: {
            schema: "xt.combo_trial.scene.v1",
            recorded_by: 0,
            players: { p1: { fighter_id: 0, unique: { stock: 1 } } }
        }
    },
    {
        id: 101,
        motion: "236+HP",
        expected_combo: 2,
        expected_hp: 10000,
        delay_from_prev: 20
    }
];

const beforeMechanism = mechanismProjection(legacy);
const result = migrateComboDocument(legacy, {
    relativePath: "Ryu/example.json",
    timestamp: "2026-07-26T12:00:00+08:00"
});
assert.equal(result.document[0]._xt_meta.schema, 2);
assert.equal(result.document[0]._xt_meta.language, "und");
assert.equal(result.document[0]._xt_meta.control_mode, "unknown");
assert.deepEqual(result.document[0]._xt_meta.tags, []);
assert.deepEqual(result.document[0]._xt_meta.step_notes, ["", ""]);
assert.equal(result.document[0]._xt_meta.versions.json.id, "xt.combo_trial");
assert.equal(result.document[0]._xt_meta.versions.json.version, "2.0.0");
assert.equal(result.document[0]._xt_meta.versions.recorder.id, "unknown");
assert.equal(result.document[0]._xt_meta.version, 1);
assert.equal(result.document[0]._xt_meta.environment.dummy_guard_type, 3);
assert.equal(result.document[0]._xt_meta.environment.dummy_guard, undefined);
assert.equal(result.document[0]._xt_meta.dummy_guard, undefined);
assert.deepEqual(result.document[0].scene_state, legacy[0].scene_state);
assert.deepEqual(mechanismProjection(result.document), beforeMechanism);

const secondPass = migrateComboDocument(result.document, {
    relativePath: "Ryu/example.json",
    timestamp: "2026-07-27T12:00:00+08:00"
});
assert.deepEqual(secondPass.document, result.document);

const earlyV2Guard = migrateComboDocument([{
    _xt_meta: {
        schema: 2,
        environment: { dummy_guard_type: 1 },
        dummy_guard_type: 1
    },
    dummy_guard_type: 1,
    id: 100,
    motion: "5LP",
    delay_from_prev: 0
}], {
    relativePath: "Ryu/early-v2-guard.json",
    timestamp: "2026-07-26T12:00:00+08:00"
}).document;
assert.equal(earlyV2Guard[0]._xt_meta.environment.dummy_guard_type, 2);
assert.equal(earlyV2Guard[0]._xt_meta.dummy_guard_type, 2);
assert.equal(earlyV2Guard[0].dummy_guard_type, 2);

const edited = applyMetadataEdits(result.document, {
    title: "已审核",
    tags: "实战, 确反",
    environment: {
        dummy_stance: "crouch",
        dummy_action_type: 1,
        dummy_jump_type: 0,
        dummy_cpu_level: 8,
        dummy_counter_type: 3,
        dummy_counter_weight_normal: 10,
        dummy_counter_weight_counter: 9,
        dummy_counter_weight_punish: 8,
        dummy_guard_type: 5,
        dummy_guard_count: 2,
        dummy_guard_switching: false,
        dummy_guard_only_type: 3,
        dummy_drive_parry_type: 2,
        dummy_drive_reversal_type: 3,
        dummy_drive_reversal_delay: 5,
        dummy_drive_reversal_count: 6,
        dummy_drive_reversal_weight_none: 10,
        dummy_drive_reversal_weight_guard: 9,
        dummy_drive_reversal_weight_wakeup: 8,
        dummy_throw_escape_type: 2,
        dummy_wakeup_type: 1,
        requires_dummy_crouch: true
    },
    scene: {
        p2: {
            fighter_id: 1,
            resources: { hp: 8000, drive: 40000, super: 10000 },
            status: { burnout: false, stunned: false, stance: "crouching" },
            unique: { stock: 2 }
        }
    },
    snapshot: {
        victim: { current_hp: 8000, max_hp: 10000, heal_hp: 9000 }
    }
}, { timestamp: "2026-07-26T13:00:00+08:00" });
assert.equal(edited[0]._xt_meta.title, "已审核");
assert.deepEqual(edited[0]._xt_meta.tags, ["实战", "确反"]);
assert.equal(edited[0]._xt_meta.environment.dummy_stance, "crouch");
assert.equal(edited[0]._xt_meta.environment.dummy_jump_type, 0);
assert.equal(edited[0]._xt_meta.dummy_jump_type, 0);
assert.equal(edited[0].dummy_jump_type, 0);
assert.equal(edited[0].dummy_guard_type, 5);
assert.equal(edited[0]._xt_meta.environment.dummy_guard_count, 2);
assert.equal(edited[0]._xt_meta.dummy_guard_count, 2);
assert.equal(edited[0].dummy_guard_count, 2);
assert.equal(edited[0]._xt_meta.environment.dummy_counter_type, 3);
assert.equal(edited[0].dummy_counter_weight_normal, 10);
assert.equal(edited[0]._xt_meta.environment.dummy_guard_switching, false);
assert.equal(edited[0].dummy_guard_switching, false);
assert.equal(edited[0]._xt_meta.environment.dummy_drive_reversal_count, 6);
assert.equal(edited[0].dummy_drive_reversal_weight_wakeup, 8);
assert.equal(edited[0]._xt_meta.environment.dummy_throw_escape_type, 2);
assert.equal(edited[0].dummy_wakeup_type, 1);
assert.equal(edited[0]._xt_meta.environment.dummy_guard, undefined);
assert.equal(edited[0]._xt_meta.dummy_guard, undefined);
assert.equal(edited[0].dummy_guard, undefined);
assert.equal(edited[0].scene_state.schema, COMBO_JSON_EDITOR.sceneV2);
assert.equal(edited[0].scene_state.players.p2.resources.hp, 8000);
assert.equal(edited[0].snapshot_gauges.victim.heal_hp, 9000);
assert.equal(validateComboDocument(edited).valid, true);

const conflictingCounterSources = [
    {
        id: 480,
        motion: "PARRY (PC)",
        counter_type: 2,
        dummy_counter_type: 0,
        combo_stats: { hit_type: "PC" },
        _xt_meta: {
            dummy_counter_type: 0,
            environment: { dummy_counter_type: 0 }
        }
    },
    {
        id: 669,
        motion: "4HK (确反康)",
        counter_type: 2,
        expected_combo: 1,
        has_hit: true
    }
];
assert.equal(resolveCounterPolicy(conflictingCounterSources).counterType, 0,
    "canonical menu value must override stale legacy evidence");
assert.equal(resolveCounterPolicy(conflictingCounterSources, { recoverLegacyZero: true }).counterType, 2,
    "the one-time migration must recover legacy intent from an injected zero");
assert.equal(findFirstContactStep(conflictingCounterSources), 1);
assert.equal(stripCounterTags("4HK (确反康)"), "4HK");
const normalizedCounter = normalizeCounterPolicyDocument(conflictingCounterSources, {
    counterType: 1
}).document;
assert.equal(normalizedCounter[0]._xt_meta.environment.dummy_counter_type, 1);
assert.equal(normalizedCounter[0]._xt_meta.dummy_counter_type, 1);
assert.equal(normalizedCounter[0].dummy_counter_type, 1);
assert.equal(normalizedCounter[0].combo_stats.hit_type, "CH");
assert.equal(normalizedCounter[0].counter_type, undefined);
assert.equal(normalizedCounter[1].counter_type, undefined);
assert.equal(normalizedCounter[1].has_contact, true);
assert.equal(normalizedCounter[0].motion, "PARRY");
assert.equal(normalizedCounter[1].motion, "4HK");

const serialized = serializeComboJson(edited);
assert.deepEqual(parseComboJson(serialized, "roundtrip"), edited);
assert.throws(() => parseComboJson("{}", "invalid"), /根节点必须是非空步骤数组/);

const versioned = applyVersionProfile(result.document, {
    gameId: "sf6",
    gameVersion: "2026-05-28",
    recorderId: "sf6cc",
    recorderVersion: "1.0.0",
    frameworkId: "reframework",
    frameworkVersion: "1.5.9.1"
});
assert.deepEqual(versioned[0]._xt_meta.versions.game, { id: "sf6", version: "2026-05-28" });
assert.deepEqual(versioned[0]._xt_meta.versions.recorder, { id: "sf6cc", version: "1.0.0" });
assert.deepEqual(versioned[0]._xt_meta.versions.framework, { id: "reframework", version: "1.5.9.1" });
assert.deepEqual(mechanismProjection(versioned), beforeMechanism);

const declared = migrateComboDocument(versioned, {
    relativePath: "Ryu/example.json",
    metadataProfile: { language: "zh-CN", controlMode: "classic" }
}).document;
assert.equal(declared[0]._xt_meta.language, "zh-CN");
assert.equal(declared[0]._xt_meta.control_mode, "classic");
assert.deepEqual(mechanismProjection(declared), beforeMechanism);

console.log("combo_json_core tests passed");
