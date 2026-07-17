#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const bcmCore = require("../bcm_catalog_builder/bcm_catalog_core.js");
const compiler = require("./compiler_core.js");
const modern = require("./modern_display_core.js");

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
    console.error("--supplement 已禁用：Strict Modern 输出只允许 AC+BCM 结构证据。");
    process.exit(2);
}
if (!args["--ac"] || !args["--bcm"] || !args["--output"]) {
    console.error("用法: node build_modern_display.js --ac <完整AC.json> --bcm <完整BCM.json> --output <Modern映射.json> [--character <规范角色名>] [--official-semantics <官网语义候选.json>] [--community-semantics <实机验证语义.json>]");
    process.exit(2);
}

const ac = readSource(path.resolve(args["--ac"]));
const bcm = readSource(path.resolve(args["--bcm"]));
const options = {
    actionSourceSha256: ac.sha256,
    bcmSourceSha256: bcm.sha256,
    characterName: args["--character"] || undefined
};
if (args["--official-semantics"]) {
    const official = readSource(path.resolve(args["--official-semantics"]));
    const meta = official.value && official.value._meta || {};
    if (meta.schema !== "xt.modern_display.v1" || meta.generated_from !== "capcom_official") {
        console.error("--official-semantics 不是受支持的官网语义候选文件。");
        process.exit(2);
    }
    options.officialSemantics = official.value;
    options.officialSemanticsSha256 = official.sha256;
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
    console.error("AC+BCM 编译无效，拒绝生成 Modern 映射。");
    process.exit(1);
}
const output = modern.buildModernDisplay(
    ac.value, bcmCatalog, result.runtime, {}, options);
const filename = path.resolve(args["--output"]);
fs.mkdirSync(path.dirname(filename), { recursive: true });
fs.writeFileSync(filename, `${JSON.stringify(output, null, 2)}\n`, "utf8");
console.log(JSON.stringify({
    output: filename,
    character: result.runtime.character,
    action_count: Object.keys(output).filter(key => /^\d+$/.test(key)).length,
    schema: modern.SCHEMA
}, null, 2));
