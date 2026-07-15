#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const core = require("./bcm_catalog_core.js");

const input = process.argv[2];
const output = process.argv[3];
const characterName = process.argv[4];
if (!input || !output) {
    console.error("用法: node build_catalog.js <完整BCM.json> <BCM简表.json> [角色规范名]");
    process.exit(2);
}

const sourceBytes = fs.readFileSync(path.resolve(input));
const source = core.parseSourceText(sourceBytes.toString("utf8"));
const sourceSha256 = crypto.createHash("sha256").update(sourceBytes).digest("hex");
const catalog = core.buildCatalog(source, { sourceSha256, characterName });
fs.writeFileSync(path.resolve(output), `${JSON.stringify(catalog, null, 2)}\n`, "utf8");
console.log(JSON.stringify({ output: path.resolve(output), stats: catalog.stats, warnings: catalog.warnings }, null, 2));
