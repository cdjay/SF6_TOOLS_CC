"use strict";

const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const deployer = require("./deploy_command_display.js");

const formal = path.resolve(__dirname, "../../data/TrainingComboTrials_data/command_display");
const root = fs.mkdtempSync(path.join(os.tmpdir(), "sf6cc-deploy-test-"));
try {
    const source = path.join(root, "lastjson");
    const target = path.join(root, "command_display");
    fs.mkdirSync(source);
    fs.mkdirSync(target);
    const roster = path.join(root, "fighters.json");
    fs.writeFileSync(roster, JSON.stringify({
        schema: "sf6cc.fighter_roster.v1",
        fighters: [
            { id: 1, key: "Ryu", name_en: "Ryu", name_zh: "隆" },
            { id: 2, key: "Luke", name_en: "Luke", name_zh: "卢克" }
        ]
    }));
    for (const name of ["Ryu.json", "Luke.json"]) fs.copyFileSync(path.join(formal, name), path.join(source, name));
    fs.copyFileSync(path.join(formal, "Luke.json"), path.join(target, "Luke.json"));
    const options = { source, target, rosterPath: roster };

    // A new fighter has no runtime table yet; an unchanged one is left alone.
    let entries = deployer.compare(options);
    assert.deepStrictEqual(entries.map(entry => [entry.key, entry.status]),
        [["Ryu", "missing_target"], ["Luke", "same"]]);
    const result = deployer.deploy(options);
    assert.deepStrictEqual(result.changed.map(entry => entry.key), ["Ryu"]);
    entries = deployer.compare(options);
    assert.ok(entries.every(entry => entry.status === "same"));

    // CRLF checkouts are the same content.
    const crlf = fs.readFileSync(path.join(target, "Ryu.json"), "utf8").replace(/\n/g, "\r\n");
    fs.writeFileSync(path.join(target, "Ryu.json"), crlf);
    assert.strictEqual(deployer.compare(options).find(entry => entry.key === "Ryu").status, "same");

    // A hand-edited runtime table is detected and replaced by the generator output.
    fs.writeFileSync(path.join(target, "Luke.json"), "{}\n");
    assert.strictEqual(deployer.compare(options).find(entry => entry.key === "Luke").status, "different");

    // Every source is validated before the runtime directory is touched.
    const luke = JSON.parse(fs.readFileSync(path.join(source, "Luke.json"), "utf8"));
    luke._meta.audit.command_display_action_count += 1;
    fs.writeFileSync(path.join(source, "Luke.json"), JSON.stringify(luke));
    assert.throws(() => deployer.deploy(options), /统一指令覆盖审计/);
    assert.strictEqual(fs.readFileSync(path.join(target, "Luke.json"), "utf8"), "{}\n");

    // A partial generation never deploys silently.
    fs.rmSync(path.join(source, "Luke.json"));
    assert.throws(() => deployer.deploy(options), /生成目录缺少：Luke/);
    assert.throws(() => deployer.deploy({ ...options, characters: ["Arjun"] }), /不在 data\/SF6CC\/fighters.json/);
    deployer.deploy({ ...options, characters: ["Ryu"] });
} finally {
    fs.rmSync(root, { recursive: true, force: true });
}

console.log("command display deploy tests passed");
