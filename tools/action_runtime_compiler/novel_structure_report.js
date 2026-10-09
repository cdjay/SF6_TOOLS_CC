#!/usr/bin/env node
"use strict";

// Release-day check for a new fighter: AC structures that no other fighter
// uses. Generated rules match exact structural signatures, so a mechanic the
// roster has never shown (a new key class, a BranchKey shape, a TriggerKey
// condition set) is exactly what silently falls through to legacy handling.
// The report lists, per target fighter, what is new relative to every other
// fighter in the same dump, with the Actions that carry it.
//
//   node novel_structure_report.js --version 2026-10-13 --characters Arjun [--out report.md] [--json report.json]
//
// Without --characters every fighter is compared against the others, which
// shows the roster's baseline of fighter-specific mechanics.

const fs = require("fs");
const path = require("path");
const archive = require("./archive_builder.js");
const builder = require("./lastjson_builder.js");
const bcmCore = require("../bcm_catalog_builder/bcm_catalog_core.js");
const fighterRoster = require("../fighter_roster.js");

const TOOL_ROOT = __dirname;
const EXAMPLE_LIMIT = 5;
const PARAMS = ["Param00", "Param01", "Param02", "Param03", "Param04", "Param05"];

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

function scalars(object) {
    const result = {};
    for (const field of object && object.fields || []) {
        const value = field.value;
        if (value && value.kind !== "ref" && value.kind !== "nil") result[field.name] = value.value;
    }
    return result;
}

// Type, Attr and the small enum Params stay exact; Param values that carry
// Action IDs or button masks only record whether they are set.
function branchShape(fields) {
    const params = PARAMS.map(name => (Number(fields[name]) ? "n" : "0")).join("");
    return `T${Number(fields.Type)}`
        + `|attr=${Number(fields.Attr) || 0}`
        + `|frame=${Number(fields.ActionFrame) ? "n" : "0"}`
        + `|params=${params}`
        + `|trigger=${Number(fields.TriggerID) >= 0 ? "n" : "-"}`;
}

function addExample(map, key, example) {
    if (!map.has(key)) map.set(key, []);
    const list = map.get(key);
    if (list.length < EXAMPLE_LIMIT) list.push(example);
}

// Structures reachable from the fighter's own Actions (common Actions are
// shared by every fighter and can never be new).
function scanAc(ac) {
    const objects = new Map((ac && ac.objects || []).map(object => [object.object_id, object]));
    const result = { objectTypes: new Map(), branchShapes: new Map(), triggerConditions: new Map() };
    for (const record of ac && ac.records || []) {
        if (!record || record.source_scope !== "character" || !record.action_ref
            || record.action_ref.kind !== "ref") continue;
        const actionId = Number(record.native_action_id);
        const pending = [record.action_ref.object_id];
        const visited = new Set();
        while (pending.length) {
            const id = pending.pop();
            if (visited.has(id)) continue;
            visited.add(id);
            const object = objects.get(id);
            if (!object) continue;
            addExample(result.objectTypes, object.object_type, { action_id: actionId });
            if (object.object_type === "CharacterAsset.BranchKey") {
                const fields = scalars(object);
                addExample(result.branchShapes, branchShape(fields), {
                    action_id: actionId, target_action_id: Number(fields.Action),
                    params: PARAMS.map(name => Number(fields[name]) || 0)
                });
            } else if (object.object_type === "CharacterAsset.TriggerKey") {
                const fields = scalars(object);
                addExample(result.triggerConditions, String(Number(fields.ConditionFlag) || 0), {
                    action_id: actionId, trigger_group: Number(fields.TriggerGroup)
                });
            }
            for (const field of object.fields || []) if (field.value && field.value.kind === "ref") pending.push(field.value.object_id);
            for (const item of object.items || []) if (item.value && item.value.kind === "ref") pending.push(item.value.object_id);
        }
    }
    return result;
}

const CATEGORIES = ["objectTypes", "branchShapes", "triggerConditions"];

// scans: [{ character, scan }]; targets: characters to report (null = all).
// A structure is new for a target when no baseline fighter has it; the
// baseline is every non-target fighter, or every other fighter without
// targets (two new fighters sharing a mechanic both report it).
function compare(scans, targets) {
    const wanted = targets ? new Set(targets.map(name => name.toLowerCase())) : null;
    const owners = {};
    for (const category of CATEGORIES) {
        owners[category] = new Map();
        for (const { character, scan } of scans) {
            for (const key of scan[category].keys()) {
                if (!owners[category].has(key)) owners[category].set(key, new Set());
                owners[category].get(key).add(character);
            }
        }
    }
    const fighters = [];
    for (const { character, scan } of scans) {
        if (wanted && !wanted.has(character.toLowerCase())) continue;
        const isBaseline = owner => owner !== character && !(wanted && wanted.has(owner.toLowerCase()));
        const novel = {};
        for (const category of CATEGORIES) {
            novel[category] = [...scan[category].entries()]
                .filter(([key]) => ![...owners[category].get(key)].some(isBaseline))
                .map(([key, examples]) => ({ key, examples }))
                .sort((left, right) => left.key.localeCompare(right.key));
        }
        fighters.push({ character, novel });
    }
    return fighters;
}

function report(options) {
    const roster = fighterRoster.loadRoster(options.rosterPath);
    const root = path.resolve(options.acbcmRoot || path.join(TOOL_ROOT, "acbcm"));
    const normalized = builder.normalizeVersion(options.version);
    const match = builder.versionDirectories(root).filter(item => item.normalized === normalized);
    if (match.length !== 1) throw new Error(`ACBCM ${normalized} 必须正好存在一个对应目录。`);
    const directory = path.join(root, match[0].name);
    const scans = [];
    for (const pair of archive.scanDumpDirectory(directory).pairs) {
        const ac = bcmCore.parseSourceText(fs.readFileSync(path.join(directory, pair.ac), "utf8"));
        const fighter = roster.byId(Number(ac.fighter_id));
        const character = fighter ? fighter.key : `ESF_${String(ac.fighter_id).padStart(3, "0")}`;
        scans.push({ character, scan: scanAc(ac) });
    }
    if (scans.length < 2) throw new Error("至少需要两个角色的导出才能比较。");
    return {
        schema: "sf6cc.novel-structure-report.v1",
        version: normalized,
        compared_characters: scans.map(item => item.character),
        fighters: compare(scans, options.characters || null)
    };
}

const TITLES = {
    objectTypes: "其他角色都没有的对象类型",
    branchShapes: "其他角色都没有的 BranchKey 形态",
    triggerConditions: "其他角色都没有的 TriggerKey 条件"
};

function exampleText(category, example) {
    if (category === "branchShapes") {
        return `${example.action_id}→${example.target_action_id}（参数 ${example.params.join(",")}）`;
    }
    if (category === "triggerConditions") return `${example.action_id}（触发组 ${example.trigger_group}）`;
    return String(example.action_id);
}

function markdown(result) {
    const lines = [`# 新结构报告 ${result.version}`, "",
        `对比 ${result.compared_characters.length} 个角色。列出的结构只在该角色身上出现，生成规则可能还没有覆盖。`, ""];
    for (const fighter of result.fighters) {
        const total = CATEGORIES.reduce((sum, category) => sum + fighter.novel[category].length, 0);
        lines.push(`## ${fighter.character}（${total} 项）`, "");
        for (const category of CATEGORIES) {
            const items = fighter.novel[category];
            if (!items.length) continue;
            lines.push(`### ${TITLES[category]}（${items.length}）`, "");
            for (const item of items) {
                lines.push(`- \`${item.key}\`：${item.examples.map(example => exampleText(category, example)).join("；")}`);
            }
            lines.push("");
        }
    }
    return `${lines.join("\n")}\n`;
}

function run(argv) {
    const args = argsOf(argv);
    if (!args["--version"]) {
        throw new Error("用法: node novel_structure_report.js --version <日期> [--characters A,B] [--out 报告.md] [--json 报告.json]");
    }
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

module.exports = { branchShape, scanAc, compare, report, markdown };
