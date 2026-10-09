#!/usr/bin/env node
"use strict";

// Coverage report for native cancel / follow-up relations (trigger_group_core):
// how many hand-written optional_parent_ids pairs and generated follow-up
// relations the AC TriggerKey -> BCM trigger group chain explains, and
// whether the dump carried every trigger group.
//
//   node trigger_group_report.js --version 2026-10-13 [--characters Ryu,Luke] [--out report.md]

const fs = require("fs");
const path = require("path");
const archive = require("./archive_builder.js");
const builder = require("./lastjson_builder.js");
const bcmCore = require("../bcm_catalog_builder/bcm_catalog_core.js");
const fighterRoster = require("../fighter_roster.js");
const core = require("./trigger_group_core.js");

const TOOL_ROOT = __dirname;
const DATA_ROOT = path.resolve(TOOL_ROOT, "../../data/TrainingComboTrials_data");

function argsOf(argv) {
    const result = {};
    for (let index = 0; index < argv.length; index += 1) {
        const key = argv[index];
        if (!key.startsWith("--")) throw new Error(`未知参数: ${key}`);
        const value = argv[index + 1];
        if (!value || value.startsWith("--")) throw new Error(`参数 ${key} 缺少值。`);
        result[key] = value;
        index += 1;
    }
    return result;
}

function readJsonIfExists(filename) {
    return fs.existsSync(filename) ? JSON.parse(fs.readFileSync(filename, "utf8")) : null;
}

function ids(value) {
    if (value === undefined || value === null) return [];
    const items = Array.isArray(value) ? value : String(value).split(",");
    return items.map(item => Number(String(item).trim())).filter(Number.isInteger);
}

// Pairs (parent -> child) the runtime currently gets from curation and from
// the generated command table's follow-up relations.
function expectedPairs(key, dataRoot) {
    const pairs = [];
    const curated = readJsonIfExists(path.join(dataRoot, "exceptions", `${key}.json`)) || {};
    for (const [child, rule] of Object.entries(curated)) {
        if (!/^\d+$/.test(child) || !rule || typeof rule !== "object") continue;
        for (const parent of ids(rule.optional_parent_ids)) pairs.push({ source: "optional_parent_ids", parent, child: Number(child) });
    }
    const table = readJsonIfExists(path.join(dataRoot, "command_display", `${key}.json`)) || {};
    for (const [child, entry] of Object.entries(table)) {
        const relation = /^\d+$/.test(child) && entry && entry.relation;
        if (relation && relation.type === "followup" && Number.isInteger(Number(relation.source_action_id))) {
            pairs.push({ source: "command_display.relation", parent: Number(relation.source_action_id), child: Number(child) });
        }
    }
    return pairs;
}

function classify(relations, pair, keys) {
    if (core.enabledBy(relations, pair.parent, pair.child).length) return "explained";
    const parentGroups = (keys.get(pair.parent) || []).map(item => item.group);
    return parentGroups.some(group => relations.missing_groups.includes(group)) ? "unknown_missing_group" : "unexplained";
}

function report(options) {
    const roster = fighterRoster.loadRoster(options.rosterPath);
    const root = path.resolve(options.acbcmRoot || path.join(TOOL_ROOT, "acbcm"));
    const normalized = builder.normalizeVersion(options.version);
    const match = builder.versionDirectories(root).filter(item => item.normalized === normalized);
    if (match.length !== 1) throw new Error(`ACBCM ${normalized} 必须正好存在一个对应目录。`);
    const directory = path.join(root, match[0].name);
    const wanted = options.characters ? new Set(options.characters.map(name => name.toLowerCase())) : null;
    const rows = [];
    for (const pair of archive.scanDumpDirectory(directory).pairs) {
        const stemId = builder.filenameFighterId(pair.stem);
        const stemFighter = stemId !== null ? roster.byId(stemId) : null;
        if (wanted && stemFighter && !wanted.has(stemFighter.key.toLowerCase())) continue;
        const ac = bcmCore.parseSourceText(fs.readFileSync(path.join(directory, pair.ac), "utf8"));
        const bcm = bcmCore.parseSourceText(fs.readFileSync(path.join(directory, pair.bcm), "utf8"));
        const fighter = roster.byId(Number(ac.fighter_id));
        const key = fighter ? fighter.key : `ESF_${String(ac.fighter_id).padStart(3, "0")}`;
        if (wanted && !wanted.has(key.toLowerCase())) continue;
        const relations = core.buildRelations(ac, bcm);
        const keys = core.actionTriggerKeys(ac);
        const counts = { explained: 0, unexplained: 0, unknown_missing_group: 0 };
        const unexplained = [];
        for (const expected of expectedPairs(key, options.dataRoot || DATA_ROOT)) {
            const verdict = classify(relations, expected, keys);
            counts[verdict] += 1;
            if (verdict !== "explained" && unexplained.length < 12) unexplained.push({ ...expected, verdict });
        }
        rows.push({
            character: key, fighter_id: Number(ac.fighter_id), keyed: relations.keyed,
            complete: relations.complete, trigger_key_actions: keys.size,
            referenced_groups: relations.referenced_groups.length,
            missing_groups: relations.missing_groups, counts, unexplained
        });
    }
    return { schema: "sf6cc.trigger-group-report.v1", version: normalized, fighters: rows };
}

function markdown(result) {
    const lines = [`# 触发组关系覆盖 ${result.version}`, "",
        "| 角色 | 字典带键 | 触发组完整 | 丢失组 | 已解释 | 未解释 | 因丢组未知 |",
        "| --- | --- | --- | ---: | ---: | ---: | ---: |"];
    for (const row of result.fighters) {
        lines.push(`| ${row.character} | ${row.keyed ? "是" : "否"} | ${row.complete ? "是" : "否"} | `
            + `${row.missing_groups.length} | ${row.counts.explained} | ${row.counts.unexplained} | ${row.counts.unknown_missing_group} |`);
    }
    lines.push("", "未解释或未知的父→子关系（每角色最多 12 条）：", "");
    for (const row of result.fighters) {
        for (const item of row.unexplained) {
            lines.push(`- ${row.character} ${item.parent}→${item.child}（${item.source}，${item.verdict}）`);
        }
    }
    return `${lines.join("\n")}\n`;
}

function run(argv) {
    const args = argsOf(argv);
    if (!args["--version"]) throw new Error("用法: node trigger_group_report.js --version <日期> [--characters A,B] [--out 报告.md] [--json 报告.json]");
    const result = report({
        version: args["--version"], acbcmRoot: args["--acbcm-root"],
        characters: args["--characters"] ? args["--characters"].split(",").map(item => item.trim()).filter(Boolean) : null
    });
    const text = markdown(result);
    if (args["--out"]) fs.writeFileSync(args["--out"], text, "utf8");
    if (args["--json"]) fs.writeFileSync(args["--json"], `${JSON.stringify(result, null, 2)}\n`, "utf8");
    process.stdout.write(text);
}

if (require.main === module) {
    try {
        run(process.argv.slice(2));
    } catch (error) {
        console.error(`错误: ${error.message}`);
        process.exitCode = 2;
    }
}

module.exports = { expectedPairs, classify, report, markdown };
