import assert from "node:assert/strict";
import {
    applyMetadataEdits,
    applyVersionProfile,
    COMBO_JSON_EDITOR,
    mechanismProjection,
    migrateComboDocument,
    parseComboJson,
    serializeComboJson,
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
            version: 1
        },
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
assert.deepEqual(result.document[0].scene_state, legacy[0].scene_state);
assert.deepEqual(mechanismProjection(result.document), beforeMechanism);

const secondPass = migrateComboDocument(result.document, {
    relativePath: "Ryu/example.json",
    timestamp: "2026-07-27T12:00:00+08:00"
});
assert.deepEqual(secondPass.document, result.document);

const edited = applyMetadataEdits(result.document, {
    title: "已审核",
    tags: "实战, 确反",
    environment: {
        dummy_stance: "crouch",
        dummy_action_type: 1,
        dummy_jump_type: 0,
        dummy_guard_type: 3,
        dummy_guard: "all",
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
assert.equal(edited[0].dummy_guard_type, 3);
assert.equal(edited[0].scene_state.schema, COMBO_JSON_EDITOR.sceneV2);
assert.equal(edited[0].scene_state.players.p2.resources.hp, 8000);
assert.equal(edited[0].snapshot_gauges.victim.heal_hp, 9000);
assert.equal(validateComboDocument(edited).valid, true);

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
