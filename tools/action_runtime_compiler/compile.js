#!/usr/bin/env node
"use strict";

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const bcmCore = require("../bcm_catalog_builder/bcm_catalog_core.js");
const compiler = require("./compiler_core.js");

function usage() {
    console.error("用法: node compile.js --ac <完整AC.json> --bcm <完整BCM.json> --output <动作运行时.json> [--report <报告.json>] [--character <规范角色名>]");
}

function parseArgs(argv) {
    const result = {};
    for (let index = 0; index < argv.length; index += 1) {
        const key = argv[index];
        if (!key.startsWith("--") || index + 1 >= argv.length) throw new Error(`无效参数: ${key}`);
        result[key.slice(2)] = argv[++index];
    }
    return result;
}

function readSource(filename) {
    const bytes = fs.readFileSync(path.resolve(filename));
    return {
        bytes,
        value: bcmCore.parseSourceText(bytes.toString("utf8")),
        sha256: crypto.createHash("sha256").update(bytes).digest("hex")
    };
}

function writeJson(filename, value) {
    const resolved = path.resolve(filename);
    fs.mkdirSync(path.dirname(resolved), { recursive: true });
    fs.writeFileSync(resolved, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function defaultReportPath(output) {
    const parsed = path.parse(output);
    return path.join(parsed.dir, `${parsed.name}.report.json`);
}

let args;
try {
    args = parseArgs(process.argv.slice(2));
    if (!args.ac || !args.bcm || !args.output) throw new Error("缺少 --ac、--bcm 或 --output");
} catch (error) {
    usage();
    console.error(error.message);
    process.exit(2);
}

try {
    const ac = readSource(args.ac);
    const bcm = readSource(args.bcm);
    const result = compiler.compile(ac.value, bcm.value, {}, {
        actionSourceSha256: ac.sha256,
        bcmSourceSha256: bcm.sha256,
        characterName: args.character
    });
    writeJson(args.output, result.runtime);
    const reportPath = args.report || defaultReportPath(args.output);
    writeJson(reportPath, result.report);
    console.log(JSON.stringify({
        output: path.resolve(args.output),
        report: path.resolve(reportPath),
        status: result.report.status,
        character: result.runtime.character,
        coverage: result.runtime.coverage
    }, null, 2));
    process.exit(result.report.status === "invalid" ? 1 : 0);
} catch (error) {
    console.error(JSON.stringify({ status: "invalid", error: error.message }, null, 2));
    process.exit(1);
}
