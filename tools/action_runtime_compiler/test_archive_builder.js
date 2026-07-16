"use strict";

const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const archive = require("./archive_builder.js");

const before = {
    character: "Test",
    action_ids: [10, 11, 12],
    actions: { "10": "LP", "11": "MP" },
    aliases: { "12": "11" },
    validation: { rules: {
        "10": { display: "LP" },
        "11": { display: "MP", system_action: "drc" }
    } },
    evidence: { target_combo_followup_action_ids: [20] },
    sources: { ac_sha256: "old-ac", bcm_sha256: "old-bcm" }
};
const after = {
    character: "Test",
    action_ids: [10, 12, 13],
    actions: { "10": "2+LP", "13": "HP" },
    aliases: { "12": "10" },
    validation: { rules: {
        "10": { display: "2+LP" },
        "13": { display: "HP", system_action: "raw_dr" }
    } },
    evidence: { target_combo_followup_action_ids: [21] },
    sources: { ac_sha256: "new-ac", bcm_sha256: "new-bcm" }
};
const difference = archive.diffRuntimes(
    before, after,
    { diagnostics: [{ severity: "warning", code: "OLD" }] },
    { diagnostics: [{ severity: "info", code: "NEW" }] },
    { previousVersion: "old", currentVersion: "new" });

assert.strictEqual(difference.baseline, false);
assert.strictEqual(difference.has_changes, true);
assert.strictEqual(difference.summary.ac_source_changed, true);
assert.strictEqual(difference.summary.bcm_source_changed, true);
assert.deepStrictEqual(difference.details.action_ids, { added: [13], removed: [11] });
assert.strictEqual(difference.summary.displays_added, 1);
assert.strictEqual(difference.summary.displays_removed, 1);
assert.strictEqual(difference.summary.displays_changed, 1);
assert.strictEqual(difference.summary.aliases_changed, 1);
assert.strictEqual(difference.summary.system_actions_changed, 2);
assert.deepStrictEqual(difference.details.target_combo_followups, { added: [21], removed: [20] });
assert.deepStrictEqual(difference.details.diagnostic_codes, {
    added: ["info:NEW"], removed: ["warning:OLD"]
});

const baseline = archive.diffRuntimes(null, after, null, { diagnostics: [] }, {
    previousVersion: null, currentVersion: "first"
});
assert.strictEqual(baseline.baseline, true);
assert.strictEqual(baseline.has_changes, false);

assert.throws(() => archive.buildArchive({ version: ".." }), /版本必须/);
assert.throws(() => archive.buildArchive({ version: "CON" }), /Windows 保留名/);

function writeMinimalPair(directory, stem, fighterId, actionId) {
    const ac = {
        schema: "sf6cr.action-catalog-full.v2",
        character: "Fab",
        fighter_id: fighterId,
        unique_action_ids_by_scope: { character: [actionId] },
        objects: [],
        records: []
    };
    const bcm = {
        schema: "sf6cr.bcm-full.v1",
        character: "Fab",
        fighter_id: fighterId,
        command_root_ref: { kind: "ref", object_id: 1 },
        objects: [{
            object_id: 1,
            object_type: "System.Collections.Generic.Dictionary`2<System.Int32,BCM.COMMAND[]>",
            kind: "collection",
            fields: null,
            items: []
        }],
        triggers: []
    };
    fs.writeFileSync(path.join(directory, `${stem}${archive.AC_SUFFIX}`), JSON.stringify(ac));
    fs.writeFileSync(path.join(directory, `${stem}${archive.BCM_SUFFIX}`), JSON.stringify(bcm));
}

const mergeRoot = fs.mkdtempSync(path.join(os.tmpdir(), "sf6cc-archive-merge-test-"));
const dumpRoot = path.join(mergeRoot, "dump");
const outputRoot = path.join(mergeRoot, "output");
fs.mkdirSync(dumpRoot);
try {
    writeMinimalPair(dumpRoot, "隆01", 1, 600);
    writeMinimalPair(dumpRoot, "本田20", 20, 610);
    const first = archive.buildArchive({
        outputRoot, dumpDirectory: dumpRoot, version: "same-version", stems: ["隆01"]
    });
    const appended = archive.buildArchive({
        outputRoot, dumpDirectory: dumpRoot, version: "same-version", stems: ["本田20"]
    });
    const overwritten = archive.buildArchive({
        outputRoot, dumpDirectory: dumpRoot, version: "same-version", stems: ["隆01"]
    });
    const manifest = JSON.parse(fs.readFileSync(
        path.join(outputRoot, "char", "same-version", "manifest.json"), "utf8"));
    const rawManifest = JSON.parse(fs.readFileSync(
        path.join(outputRoot, "acbcm", "same-version", "manifest.json"), "utf8"));
    assert.strictEqual(first.archive_mode, "created");
    assert.strictEqual(appended.archive_mode, "merged");
    assert.strictEqual(overwritten.archive_mode, "merged");
    assert.deepStrictEqual(manifest.characters.map(item => item.character), ["Ryu", "EHonda"]);
    assert.strictEqual(rawManifest.sources.length, 2);
    assert.strictEqual(fs.existsSync(path.join(
        outputRoot, "char", "same-version", "Ryu.exceptions.json")), true);
    assert.strictEqual(overwritten.differences[0].comparison_mode, "same-version-before-overwrite");
    assert.strictEqual(overwritten.differences[0].has_changes, false);
} finally {
    const resolved = path.resolve(mergeRoot);
    const tempRoot = `${path.resolve(os.tmpdir())}${path.sep}`;
    if (!resolved.startsWith(tempRoot) || !path.basename(resolved).startsWith("sf6cc-archive-merge-test-")) {
        throw new Error("Unsafe test cleanup target");
    }
    fs.rmSync(resolved, { recursive: true, force: true });
}

console.log("Action runtime archive/diff tests passed.");
