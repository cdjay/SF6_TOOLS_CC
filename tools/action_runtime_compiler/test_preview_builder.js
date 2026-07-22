"use strict";

const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const preview = require("./preview_builder.js");

function writeJson(filename, value) {
    fs.mkdirSync(path.dirname(filename), { recursive: true });
    fs.writeFileSync(filename, JSON.stringify(value), "utf8");
}

const root = fs.mkdtempSync(path.join(os.tmpdir(), "sf6cc-preview-"));
const officialRoot = path.join(root, "official");
try {
    const version = "2026.5.28";
    const raw = path.join(root, "acbcm", version);
    const char = path.join(root, "char", version);
    const acName = "测试02-fab-action-catalog-full-classic.json";
    const bcmName = "测试02-fab-bcm-full-classic.json";
    writeJson(path.join(raw, "manifest.json"), {
        version,
        created_at: "2026-05-28T00:00:00.000Z",
        sources: [{ stem: "测试02", character: "Luke", fighter_id: 2, ac_file: acName, bcm_file: bcmName, ac_sha256: "ac", bcm_sha256: "bcm" }]
    });
    writeJson(path.join(raw, acName), {
        schema: "sf6cr.action-catalog-full.v2", fighter_id: 2, record_count: 1, truncated: false,
        records: [{ native_action_id: 600, source_scope: "character", style_index: 0, resource_index: 0, action_ref: { kind: "ref", object_id: 1 } }],
        objects: [
            { object_id: 1, object_type: "FAB.ACTION", fields: [
                { name: "ActionID", value: { kind: "number", value: 600 } },
                { name: "Frame", value: { kind: "number", value: 20 } },
                { name: "ActionFrame", value: { kind: "ref", object_id: 2 } }
            ] },
            { object_id: 2, object_type: "CharacterAsset.ActionFrame", fields: [
                { name: "MainFrame", value: { kind: "number", value: 5 } },
                { name: "FollowFrame", value: { kind: "number", value: 7 } }
            ] }
        ]
    });
    writeJson(path.join(raw, bcmName), {
        schema: "sf6cr.bcm-full.v2", character: "Luke", fighter_id: 2, truncated: false,
        hard_gate_passed: true, unique_action_ids: [600], triggers: [], objects: [], type_catalog: {}, graph_stats: {}
    });
    writeJson(path.join(officialRoot, "Luke.official.generated.json"), {
        _meta: { schema: "xt.modern_display.v1", character: "Luke", generated_from: "capcom_official" },
        600: { official_web_id: "600", move_name: "轻攻击", category: "NORMAL", classic_display: "LP", modern_display: "弱" }
    });
    writeJson(path.join(char, "Luke.command-display.json"), {
        _meta: { schema: "xt.command_display.v1", character: "Luke" },
        600: { classic_command: { display: "LP", inputs: ["LP"] },
            simple_command: { display: "弱", inputs: ["弱"] }, motion_command: null,
            ownership: "direct", routes: [{ display: "弱", owner_action_id: 600, trigger_index: 1, profile: "easy", source: "bcm_profile" }] }
    });

    const index = preview.buildPreviewIndex(root, version, { officialRoot });
    assert.strictEqual(index.characters.length, 1);
    assert.strictEqual(index.characters[0].official_file, "Luke.official.generated.json");
    const acRows = preview.buildAcRows(readJson(path.join(raw, acName)));
    const offRows = preview.buildOfficialRows(readJson(path.join(officialRoot, "Luke.official.generated.json")));
    const commandRows = preview.buildCommandRows(readJson(path.join(char, "Luke.command-display.json")));
    assert.strictEqual(acRows[0].action_id, 600);
    assert.strictEqual(acRows[0].main_frame, 5);
    assert.strictEqual(offRows[0].modern_display, "弱");
    assert.strictEqual(commandRows[0].classic_command, "LP");
    assert.strictEqual(commandRows[0].simple_command, "弱");
    assert.strictEqual(commandRows[0].routes[0].owner_action_id, 600);
    assert.throws(() => preview.buildPreview(root, "../escape", "Luke", { officialRoot }), /安全/);

    const repositoryHtml = path.join(__dirname, "html");
    const archivedManifest = path.join(repositoryHtml, "acbcm", version, "manifest.json");
    if (fs.existsSync(archivedManifest)) {
        const integration = preview.buildPreview(repositoryHtml, version, "Luke");
        assert(integration.ac.rows.length > 100);
        assert(integration.bcm.rows.length > 20);
        assert(integration.official.rows.length > 20);
        if (integration.files.command) assert(integration.command.rows.length > 20);
    }
    console.log("preview builder tests passed");
} finally {
    fs.rmSync(root, { recursive: true, force: true });
}

function readJson(filename) {
    return JSON.parse(fs.readFileSync(filename, "utf8"));
}
