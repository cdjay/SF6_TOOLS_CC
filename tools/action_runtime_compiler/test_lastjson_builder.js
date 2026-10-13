"use strict";

const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const builder = require("./lastjson_builder.js");

assert.strictEqual(builder.normalizeVersion("2026.5.28"), "2026-05-28");
assert.strictEqual(builder.normalizeVersion("2026-05-28"), "2026-05-28");
assert.throws(() => builder.normalizeVersion("latest"), /版本目录不是/);
assert.strictEqual(builder.filenameFighterId("f032"), 32);
assert.strictEqual(builder.filenameFighterId("英格丽德32"), 32);
assert.strictEqual(builder.filenameFighterId("f0"), null);
assert.deepStrictEqual(builder.mapDiff({ "1": { x: 1 }, "2": {} }, {
    "1": { x: 2 }, "3": {}
}), { added: [3], removed: [2], changed: [1] });

const registry = require("../fighter_roster.js").officialRegistry();
assert.strictEqual(Object.keys(registry).length, 32);
assert.strictEqual(new Set(Object.values(registry).map(entry => Number(entry.fighter_id))).size, 32);
assert.strictEqual(registry.Yasmine.fighter_id, 33);
assert.strictEqual(registry.Arjun.fighter_id, 34);

const formalRoot = path.resolve(__dirname, "../../data/TrainingComboTrials_data/command_display");
let formalAlex = null;
for (const [character, registryEntry] of Object.entries(registry)) {
    const formal = JSON.parse(fs.readFileSync(path.join(formalRoot, `${character}.json`), "utf8"));
    assert.ok(builder.validateOutput(formal, character, registryEntry.fighter_id) > 0);
    assert.ok(Number(formal._meta.audit.classic_command_action_count)
        >= Number(formal._meta.audit.split_command_action_count));
    assert.strictEqual(Number(formal._meta.audit.classic_projection_pending_count), 0);
    const fingerprint = formal._meta.bcm_trigger_fingerprint;
    assert.ok(fingerprint && fingerprint.algorithm === require("./bcm_fingerprint.js").ALGORITHM
        && fingerprint.count > 0 && /^[0-9a-f]{8}$/.test(fingerprint.hash),
        `${character} 缺少运行时 BCM 指纹`);
    if (character === "Alex") formalAlex = formal;
}
assert.strictEqual(formalAlex["967"].classic_command.display, ">6+LP");
assert.strictEqual(formalAlex["968"].classic_command.display, ">6+MP");
assert.strictEqual(formalAlex["969"].classic_command.display, ">6+HP");
assert.strictEqual(formalAlex["968"].ownership, "type63_strength_variant");
assert.strictEqual(formalAlex["968"].motion_command.display, "> 6 + 中");
assert.strictEqual(formalAlex["969"].ownership, "type63_strength_variant");
assert.strictEqual(formalAlex["969"].motion_command.display, "> 6 + 强");
assert.deepStrictEqual(formalAlex._meta.type63_strength_variant_relations.map(relation => [
    relation.source_action_id, relation.target_action_id, relation.strength,
    relation.classic_param01, relation.modern_param01
]), [
    [967, 968, "medium", 32, 128],
    [967, 969, "heavy", 64, 256]
]);

const incompleteAlex = structuredClone(formalAlex);
const incompleteId = Object.keys(incompleteAlex).find(id => /^\d+$/.test(id)
    && incompleteAlex[id].classic_command && (incompleteAlex[id].simple_command
        || incompleteAlex[id].motion_command));
incompleteAlex[incompleteId].classic_command = null;
incompleteAlex[incompleteId].control_support = "unknown";
incompleteAlex._meta.audit.classic_command_action_count -= 1;
incompleteAlex._meta.audit.shared_command_action_count -= 1;
incompleteAlex._meta.audit.classic_projection_pending_count += 1;
assert.throws(() => builder.validateOutput(incompleteAlex, "Alex", 31), /仍有现代指令缺少经典投影/);

const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "sf6cc-lastjson-test-"));
try {
    fs.mkdirSync(path.join(temporary, "_refresh_20260803"));
    fs.mkdirSync(path.join(temporary, "2026.5.28"));
    assert.strictEqual(path.basename(builder.resolveOffDirectory(temporary, "2026-05-28")), "2026.5.28");
    fs.mkdirSync(path.join(temporary, "2026-05-28"));
    assert.throws(() => builder.resolveOffDirectory(temporary, "2026-05-28"), /正好存在一个/);
} finally {
    fs.rmSync(temporary, { recursive: true, force: true });
}

const f0Dump = fs.mkdtempSync(path.join(os.tmpdir(), "sf6cc-f0-pair-test-"));
try {
    fs.writeFileSync(path.join(f0Dump, "f032-fab-action-catalog-full-classic.json"), "{}");
    fs.writeFileSync(path.join(f0Dump, "f032-fab-bcm-full-classic.json"), "{}");
    const scan = require("./archive_builder.js").scanDumpDirectory(f0Dump);
    assert.strictEqual(scan.pairs.length, 1);
    assert.strictEqual(scan.pairs[0].stem, "f032");
    assert.strictEqual(scan.incomplete.length, 0);
} finally {
    fs.rmSync(f0Dump, { recursive: true, force: true });
}

const replaceRoot = fs.mkdtempSync(path.join(os.tmpdir(), "sf6cc-lastjson-replace-test-"));
try {
    const stage = path.join(replaceRoot, ".stage");
    const target = path.join(replaceRoot, "lastjson");
    fs.mkdirSync(stage);
    fs.mkdirSync(target);
    fs.writeFileSync(path.join(stage, "Ryu.json"), "new-ryu");
    fs.writeFileSync(path.join(stage, "Luke.json"), "new-luke");
    fs.writeFileSync(path.join(target, "Ryu.json"), "old-ryu");
    fs.writeFileSync(path.join(target, "Luke.json"), "old-luke");
    const originalRename = fs.renameSync;
    fs.renameSync = function(source, destination) {
        if (path.resolve(source) === path.resolve(stage) && path.resolve(destination) === path.resolve(target)) {
            const error = new Error("simulated Windows directory lock");
            error.code = "EPERM";
            throw error;
        }
        return originalRename.apply(this, arguments);
    };
    try {
        builder.replaceDirectory(stage, target);
    } finally {
        fs.renameSync = originalRename;
    }
    assert.strictEqual(fs.readFileSync(path.join(target, "Ryu.json"), "utf8"), "new-ryu");
    assert.strictEqual(fs.readFileSync(path.join(target, "Luke.json"), "utf8"), "new-luke");
} finally {
    fs.rmSync(replaceRoot, { recursive: true, force: true });
}

const replaceSetRoot = fs.mkdtempSync(path.join(os.tmpdir(), "sf6cc-lastjson-set-test-"));
try {
    const gameStage = path.join(replaceSetRoot, ".game-stage");
    const webStage = path.join(replaceSetRoot, ".web-stage");
    const gameTarget = path.join(replaceSetRoot, "lastjson");
    const webTarget = path.join(replaceSetRoot, "lastjson_web");
    for (const directory of [gameStage, webStage, gameTarget, webTarget]) fs.mkdirSync(directory);
    fs.writeFileSync(path.join(gameStage, "Ryu.json"), "new-game");
    fs.writeFileSync(path.join(webStage, "Ryu.json"), "new-web");
    fs.writeFileSync(path.join(gameTarget, "Ryu.json"), "old-game");
    fs.writeFileSync(path.join(webTarget, "Ryu.json"), "old-web");
    builder.replaceDirectorySet([
        { stage: gameStage, target: gameTarget },
        { stage: webStage, target: webTarget }
    ]);
    assert.strictEqual(fs.readFileSync(path.join(gameTarget, "Ryu.json"), "utf8"), "new-game");
    assert.strictEqual(fs.readFileSync(path.join(webTarget, "Ryu.json"), "utf8"), "new-web");
} finally {
    fs.rmSync(replaceSetRoot, { recursive: true, force: true });
}

const rollbackSetRoot = fs.mkdtempSync(path.join(os.tmpdir(), "sf6cc-lastjson-rollback-test-"));
try {
    const gameStage = path.join(rollbackSetRoot, ".game-stage");
    const missingWebStage = path.join(rollbackSetRoot, ".missing-web-stage");
    const gameTarget = path.join(rollbackSetRoot, "lastjson");
    const webTarget = path.join(rollbackSetRoot, "lastjson_web");
    for (const directory of [gameStage, gameTarget, webTarget]) fs.mkdirSync(directory);
    fs.writeFileSync(path.join(gameStage, "Ryu.json"), "new-game");
    fs.writeFileSync(path.join(gameTarget, "Ryu.json"), "old-game");
    fs.writeFileSync(path.join(webTarget, "Ryu.json"), "old-web");
    assert.throws(() => builder.replaceDirectorySet([
        { stage: gameStage, target: gameTarget },
        { stage: missingWebStage, target: webTarget }
    ]));
    assert.strictEqual(fs.readFileSync(path.join(gameTarget, "Ryu.json"), "utf8"), "old-game");
    assert.strictEqual(fs.readFileSync(path.join(webTarget, "Ryu.json"), "utf8"), "old-web");
} finally {
    fs.rmSync(rollbackSetRoot, { recursive: true, force: true });
}

// Release-day options: official data may be missing, and one fighter can be
// generated without rebuilding the whole roster.
assert.deepStrictEqual(builder.argsOf(["--version", "2026-10-13", "--allow-missing-official",
    "--characters", "Arjun,Ryu"]), {
    "--version": "2026-10-13", "--allow-missing-official": true, "--characters": "Arjun,Ryu"
});
assert.throws(() => builder.argsOf(["--characters"]), /缺少值/);
assert.deepStrictEqual(builder.characterList(" Arjun , Ryu "), ["Arjun", "Ryu"]);
assert.strictEqual(builder.characterList(undefined), null);

const releaseDay = fs.mkdtempSync(path.join(os.tmpdir(), "sf6cc-lastjson-release-day-"));
try {
    const offRoot = path.join(releaseDay, "off");
    const versionDirectory = path.join(releaseDay, "acbcm", "2026-10-13");
    fs.mkdirSync(offRoot, { recursive: true });
    fs.mkdirSync(versionDirectory, { recursive: true });
    assert.throws(() => builder.resolveOffDirectory(offRoot, "2026-10-13"), /正好存在一个/);
    assert.strictEqual(builder.resolveOffDirectory(offRoot, "2026-10-13", true), null);
    assert.strictEqual(builder.loadOfficial(null, "Ryu", 1, true), null);
    assert.strictEqual(builder.loadOfficial(offRoot, "Ryu", 1, true), null);
    assert.throws(() => builder.loadOfficial(offRoot, "Ryu", 1), /OFF 缺少角色 Ryu/);

    assert.throws(() => builder.buildVersion({ versionDirectory, offRoot, allowMissingOfficial: true,
        characters: ["FutureFighter"] }), /FutureFighter 不在 data\/SF6CC\/fighters.json/);
    assert.throws(() => builder.buildVersion({ versionDirectory, offRoot, allowMissingOfficial: true,
        characters: ["Arjun"] }), /缺少 AC\/BCM 完整配对：34\(Arjun\)/);
    assert.throws(() => builder.buildVersion({ versionDirectory, offRoot, allowMissingOfficial: true,
        characters: ["Yasmine"] }), /缺少 AC\/BCM 完整配对：33\(Yasmine\)/);
    assert.throws(() => builder.buildVersion({ versionDirectory, offRoot }), /OFF 2026-10-13/);

    // Incremental replacement restores every touched file when one write fails.
    const target = path.join(releaseDay, "lastjson");
    fs.mkdirSync(target);
    fs.writeFileSync(path.join(target, "Ryu.json"), "old-ryu");
    fs.writeFileSync(path.join(releaseDay, "new-ryu.json"), "new-ryu");
    assert.throws(() => builder.replaceFilesTransactional([
        { source: path.join(releaseDay, "new-ryu.json"), target: path.join(target, "Ryu.json") },
        { source: path.join(releaseDay, "missing.json"), target: path.join(target, "Luke.json") }
    ]));
    assert.strictEqual(fs.readFileSync(path.join(target, "Ryu.json"), "utf8"), "old-ryu");
    assert.ok(!fs.existsSync(path.join(target, "Luke.json")));
} finally {
    fs.rmSync(releaseDay, { recursive: true, force: true });
}

// The runtime guard (DataBuildGuard.lua) must hash exactly like the generator.
const bcmFingerprint = require("./bcm_fingerprint.js");
assert.strictEqual(bcmFingerprint.fnv1a32(""), "811c9dc5");
assert.strictEqual(bcmFingerprint.fnv1a32("a"), "e40c292c");
assert.deepStrictEqual(bcmFingerprint.fromActionIds([18, 17, 0, -1, "600", 17]),
    { algorithm: bcmFingerprint.ALGORITHM, count: 4, hash: "8eb684e6" });
assert.deepStrictEqual(bcmFingerprint.fromBcmSource({ triggers: [
    { native_action_id: 600 }, null, { native_action_id: 17 }, { native_action_id: 18 }, { native_action_id: 17 }
] }), bcmFingerprint.fromActionIds([17, 17, 18, 600]));
assert.throws(() => bcmFingerprint.fromBcmSource({}), /triggers/);

console.log("lastjson builder tests passed");
