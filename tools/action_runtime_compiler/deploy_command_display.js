#!/usr/bin/env node
"use strict";

// Copies generated command tables (acbcm/<version>/lastjson) into the runtime
// data directory, or checks that the runtime data still equals the generator
// output. Runtime command tables are never edited by hand: they are deployed
// from one generated version as a whole (or per named fighter).

const fs = require("fs");
const path = require("path");
const builder = require("./lastjson_builder.js");
const fighterRoster = require("../fighter_roster.js");

const TOOL_ROOT = __dirname;
const DEFAULT_ACBCM_ROOT = path.join(TOOL_ROOT, "acbcm");
const DEFAULT_TARGET = path.resolve(TOOL_ROOT, "../../data/TrainingComboTrials_data/command_display");
const BOOLEAN_FLAGS = new Set(["--check"]);

function argsOf(argv) {
    const result = {};
    for (let index = 0; index < argv.length; index += 1) {
        const key = argv[index];
        if (!key.startsWith("--")) throw new Error(`未知参数: ${key}`);
        if (BOOLEAN_FLAGS.has(key)) {
            result[key] = true;
            continue;
        }
        const value = argv[index + 1];
        if (!value || value.startsWith("--")) throw new Error(`参数 ${key} 缺少值。`);
        result[key] = value;
        index += 1;
    }
    return result;
}

function resolveSource(options) {
    if (options.source) return path.resolve(options.source);
    if (!options.version) throw new Error("需要 --version <日期> 或 --source <lastjson 目录>。");
    const version = builder.normalizeVersion(options.version);
    const root = path.resolve(options.acbcmRoot || DEFAULT_ACBCM_ROOT);
    const matches = builder.versionDirectories(root).filter(item => item.normalized === version);
    if (matches.length !== 1) throw new Error(`ACBCM ${version} 必须正好存在一个对应目录，当前 ${matches.length} 个。`);
    return path.join(root, matches[0].name, "lastjson");
}

function selectFighters(roster, names) {
    if (!names) return roster.fighters;
    return names.map(name => {
        const fighter = roster.byKey(name);
        if (!fighter) throw new Error(`角色 ${name} 不在 data/SF6CC/fighters.json。`);
        return fighter;
    });
}

// Git may check text files out with CRLF; content equality ignores that.
function sameText(left, right) {
    const normalize = file => fs.readFileSync(file, "utf8").replace(/\r\n/g, "\n");
    return normalize(left) === normalize(right);
}

// Returns one entry per fighter: { key, source, target, status }.
// status: same | different | missing_target | missing_source
function compare(options) {
    const roster = fighterRoster.loadRoster(options.rosterPath);
    const source = resolveSource(options);
    const target = path.resolve(options.target || DEFAULT_TARGET);
    return selectFighters(roster, options.characters).map(fighter => {
        const sourceFile = path.join(source, `${fighter.key}.json`);
        const targetFile = path.join(target, `${fighter.key}.json`);
        let status = "same";
        if (!fs.existsSync(sourceFile)) status = "missing_source";
        else if (!fs.existsSync(targetFile)) status = "missing_target";
        else if (!sameText(sourceFile, targetFile)) status = "different";
        return { key: fighter.key, fighter_id: fighter.id, source: sourceFile, target: targetFile, status };
    });
}

function deploy(options) {
    const entries = compare(options);
    const missing = entries.filter(entry => entry.status === "missing_source");
    if (missing.length) {
        throw new Error(`生成目录缺少：${missing.map(entry => entry.key).join(", ")}。先运行 2_build_lastjson.bat。`);
    }
    // Validate every source before touching the runtime directory.
    for (const entry of entries) {
        const output = JSON.parse(fs.readFileSync(entry.source, "utf8"));
        builder.validateOutput(output, entry.key, entry.fighter_id);
    }
    const changed = entries.filter(entry => entry.status !== "same");
    builder.replaceFilesTransactional(changed.map(entry => ({ source: entry.source, target: entry.target })));
    return { entries, changed };
}

function run(argv) {
    const args = argsOf(argv);
    const options = {
        version: args["--version"],
        source: args["--source"],
        target: args["--target"],
        acbcmRoot: args["--acbcm-root"],
        rosterPath: args["--roster"],
        characters: builder.characterList(args["--characters"])
    };
    if (args["--check"]) {
        const entries = compare(options);
        const bad = entries.filter(entry => entry.status !== "same");
        for (const entry of bad) console.log(`${entry.key}: ${entry.status}`);
        console.log(`一致 ${entries.length - bad.length}/${entries.length}`);
        if (bad.length) process.exitCode = 1;
        return;
    }
    const result = deploy(options);
    for (const entry of result.changed) console.log(`${entry.key}: 已更新（${entry.status}）`);
    console.log(`部署完成：更新 ${result.changed.length}，未变 ${result.entries.length - result.changed.length}，目标 ${path.resolve(options.target || DEFAULT_TARGET)}`);
}

if (require.main === module) {
    try {
        run(process.argv.slice(2));
    } catch (error) {
        console.error(`错误: ${error.message}`);
        process.exitCode = 2;
    }
}

module.exports = { compare, deploy, run };
