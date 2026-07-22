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

const registry = JSON.parse(fs.readFileSync(path.resolve(
    __dirname, "../modern_display_builder/characters.json"), "utf8"));
assert.strictEqual(Object.keys(registry).length, 30);
assert.strictEqual(new Set(Object.values(registry).map(entry => Number(entry.fighter_id))).size, 30);

const formalRoot = path.resolve(__dirname, "../../data/TrainingComboTrials_data/modern_display");
let formalAlex = null;
for (const [character, registryEntry] of Object.entries(registry)) {
    const formal = JSON.parse(fs.readFileSync(path.join(formalRoot, `${character}.json`), "utf8"));
    assert.ok(builder.validateOutput(formal, character, registryEntry.fighter_id) > 0);
    assert.ok(Number(formal._meta.audit.classic_command_action_count)
        >= Number(formal._meta.audit.split_command_action_count));
    assert.strictEqual(Number(formal._meta.audit.classic_projection_pending_count), 0);
    if (character === "Alex") formalAlex = formal;
}

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

console.log("lastjson builder tests passed");
