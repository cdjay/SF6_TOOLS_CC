#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const core = require("./bcm_catalog_core.js");

const actionInput = process.argv[2];
const bcmInput = process.argv[3];
const output = process.argv[4];
const exceptionInput = process.argv[5];
if (!actionInput || !bcmInput || !output) {
    console.error("用法: node build_action_catalog.js <完整AC.json> <BCM审查简表.json> <运行时表.json> [例外表.json]");
    process.exit(2);
}

const actionBytes = fs.readFileSync(path.resolve(actionInput));
const actionSource = core.parseSourceText(actionBytes.toString("utf8"));
const bcmCatalog = JSON.parse(fs.readFileSync(path.resolve(bcmInput), "utf8").replace(/^\uFEFF/, ""));
const exceptions = exceptionInput ? JSON.parse(fs.readFileSync(path.resolve(exceptionInput), "utf8").replace(/^\uFEFF/, "")) : {};
const runtime = core.buildActionRuntimeCatalog(actionSource, bcmCatalog, exceptions, {
    actionSourceSha256: crypto.createHash("sha256").update(actionBytes).digest("hex")
});
fs.writeFileSync(path.resolve(output), `${JSON.stringify(runtime, null, 2)}\n`, "utf8");
console.log(JSON.stringify({
    output: path.resolve(output),
    character: runtime.character,
    action_count: runtime.action_ids.length,
    display_count: Object.keys(runtime.actions).length,
    alias_count: Object.keys(runtime.aliases).length
}, null, 2));
