#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const bcmCore = require("../bcm_catalog_builder/bcm_catalog_core.js");
const compiler = require("./compiler_core.js");
const commandDisplay = require("./command_display_core.js");
const webCharacter = require("./web_character_core.js");

function argsOf(argv) {
    const args = {};
    for (let index = 0; index < argv.length; index += 2) args[argv[index]] = argv[index + 1];
    return args;
}

function readSource(filename) {
    const bytes = fs.readFileSync(filename);
    return {
        sha256: crypto.createHash("sha256").update(bytes).digest("hex"),
        value: bcmCore.parseSourceText(bytes.toString("utf8"))
    };
}

const args = argsOf(process.argv.slice(2));
if (Object.prototype.hasOwnProperty.call(args, "--supplement")) {
    console.error("--supplement 已禁用：统一指令表只允许可审计的 AC+BCM 结构证据。");
    process.exit(2);
}
if (!args["--ac"] || !args["--bcm"] || !args["--output"]) {
    console.error("用法: node build_command_display.js --ac <完整AC.json> --bcm <完整BCM.json> --output <统一三槽表.json> [--web-output <网页角色资料.json>] [--character <规范角色名>] [--official-semantics <官网语义候选.json>] [--community-semantics <实机验证语义.json>]");
    process.exit(2);
}

const ac = readSource(path.resolve(args["--ac"]));
const bcm = readSource(path.resolve(args["--bcm"]));
const options = {
    actionSourceSha256: ac.sha256,
    bcmSourceSha256: bcm.sha256,
    characterName: args["--character"] || undefined
};
let officialSource = null;
if (args["--official-semantics"]) {
    const official = readSource(path.resolve(args["--official-semantics"]));
    const meta = official.value && official.value._meta || {};
    if (meta.schema !== "xt.modern_display.v1" || meta.generated_from !== "capcom_official") {
        console.error("--official-semantics 不是受支持的官网语义候选文件。");
        process.exit(2);
    }
    options.officialSemantics = official.value;
    options.officialSemanticsSha256 = official.sha256;
    officialSource = official;
}
if (args["--community-semantics"]) {
    const community = readSource(path.resolve(args["--community-semantics"]));
    const meta = community.value && community.value._meta || {};
    if (meta.schema !== "xt.modern_display.community.v1"
        || meta.generated_from !== "verified_runtime_observation") {
        console.error("--community-semantics 不是受支持的实机验证语义文件。");
        process.exit(2);
    }
    options.communitySemantics = community.value;
    options.communitySemanticsSha256 = community.sha256;
}
const bcmCatalog = bcmCore.buildCatalog(bcm.value, {
    characterName: options.characterName,
    sourceSha256: bcm.sha256
});
const result = compiler.compileFromCatalog(ac.value, bcmCatalog, {}, options);
if (result.report.status === "invalid") {
    console.error("AC+BCM 编译无效，拒绝生成统一指令表。");
    process.exit(1);
}
const output = commandDisplay.buildCommandDisplay(
    ac.value, bcmCatalog, result.runtime, {}, options);
const filename = path.resolve(args["--output"]);
const outputBytes = Buffer.from(`${JSON.stringify(output, null, 2)}\n`, "utf8");
const parsedOutput = path.parse(filename);
const webFilename = path.resolve(args["--web-output"]
    || path.join(parsedOutput.dir, `${parsedOutput.name}.web${parsedOutput.ext || ".json"}`));
const webOutput = webCharacter.buildWebCharacter(output, {
    commandSourceSha256: crypto.createHash("sha256").update(outputBytes).digest("hex"),
    officialSnapshot: officialSource && officialSource.value,
    officialSha256: officialSource && officialSource.sha256
});
webCharacter.validateWebCharacter(webOutput, output);
fs.mkdirSync(path.dirname(filename), { recursive: true });
fs.writeFileSync(filename, outputBytes);
fs.mkdirSync(path.dirname(webFilename), { recursive: true });
fs.writeFileSync(webFilename, `${JSON.stringify(webOutput, null, 2)}\n`, "utf8");
console.log(JSON.stringify({
    output: filename,
    web_output: webFilename,
    character: result.runtime.character,
    action_count: Object.keys(output).filter(key => /^\d+$/.test(key)).length,
    schema: commandDisplay.SCHEMA,
    web_schema: webCharacter.SCHEMA,
    web_move_count: webOutput._meta.move_count
}, null, 2));
