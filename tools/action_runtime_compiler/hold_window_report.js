#!/usr/bin/env node
"use strict";

// Button-hold thresholds: hand-written is_holdable exceptions
// (charge_min / charge_max) against the AC Type 20 BranchKeys that implement
// the hold. Param01 is the held button mask, Param03 the input profile, and
// the key's frame window (inherited from via.fighter.ActionKey) says when the
// release is checked. Only exports marked inherited_fields =
// "game-namespaces.v1" carry those windows; older dumps are reported as
// frame_window_missing instead of being guessed.
//
//   node hold_window_report.js --version 2026-10-13 [--characters Ryu,Luke] [--out report.md] [--json report.json]

const fs = require("fs");
const path = require("path");
const archive = require("./archive_builder.js");
const builder = require("./lastjson_builder.js");
const bcmCore = require("../bcm_catalog_builder/bcm_catalog_core.js");
const fighterRoster = require("../fighter_roster.js");

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

function fieldEntries(object) {
    return object && object.fields || [];
}

function scalarField(object, name) {
    const field = fieldEntries(object).find(item => item.name === name);
    const value = field && field.value;
    return value && value.kind !== "ref" && value.kind !== "nil" ? value.value : undefined;
}

// The engine names are not pinned down until a dump with inherited fields
// exists; accept StartFrame / _StartFrame / <StartFrame>k__BackingField.
function frameWindow(object) {
    let start;
    let end;
    for (const field of fieldEntries(object)) {
        const value = field.value && field.value.kind !== "ref" ? Number(field.value.value) : NaN;
        if (!Number.isFinite(value)) continue;
        if (/start_?frame/i.test(field.name)) start = value;
        else if (/end_?frame/i.test(field.name)) end = value;
    }
    return start === undefined || end === undefined ? null : { start, end };
}

function actionRoots(ac) {
    const objects = new Map((ac && ac.objects || []).map(object => [object.object_id, object]));
    const roots = new Map();
    for (const record of ac && ac.records || []) {
        if (!record || record.source_scope !== "character" || !record.action_ref
            || record.action_ref.kind !== "ref") continue;
        roots.set(Number(record.native_action_id), objects.get(record.action_ref.object_id));
    }
    return { objects, roots };
}

// Type 20 BranchKeys reachable from an action's Keys.
function holdKeys(graph, actionId) {
    const root = graph.roots.get(Number(actionId));
    const keys = fieldEntries(root).find(field => field.name === "Keys");
    const pending = keys && keys.value && keys.value.kind === "ref" ? [keys.value.object_id] : [];
    const visited = new Set();
    const result = [];
    while (pending.length) {
        const id = pending.pop();
        if (visited.has(id)) continue;
        visited.add(id);
        const object = graph.objects.get(id);
        if (!object) continue;
        if (object.object_type === "CharacterAsset.BranchKey" && Number(scalarField(object, "Type")) === 20) {
            result.push({
                target: Number(scalarField(object, "Action")),
                param00: Number(scalarField(object, "Param00")),
                button_mask: Number(scalarField(object, "Param01")),
                profile: Number(scalarField(object, "Param03")),
                window: frameWindow(object)
            });
        }
        for (const field of object.fields || []) if (field.value && field.value.kind === "ref") pending.push(field.value.object_id);
        for (const item of object.items || []) if (item.value && item.value.kind === "ref") pending.push(item.value.object_id);
    }
    return result.sort((left, right) => left.profile - right.profile || left.target - right.target);
}

function near(value, candidates) {
    return candidates.some(candidate => Math.abs(candidate - value) <= 1);
}

// consistent: every hand-written threshold sits on (±1 frame) a boundary of a
// Type 20 window in the classic profile (Param03 = 1) or on the action's
// last frame. The rule is a first approximation to be confirmed on the
// first dump that carries windows; the report lists the raw windows.
function classify(rule, keys, actionFrame) {
    if (!keys.length) return "no_type20";
    if (keys.some(key => !key.window)) return "frame_window_missing";
    const classic = keys.filter(key => key.profile === 1);
    const pool = classic.length ? classic : keys;
    const boundaries = pool.flatMap(key => [key.window.start, key.window.end]);
    if (Number.isFinite(Number(actionFrame))) boundaries.push(Number(actionFrame) - 1);
    const thresholds = [rule.charge_min, rule.charge_max]
        .filter(value => value !== undefined && value !== null && value !== "")
        .map(Number);
    if (!thresholds.length) return "no_threshold";
    return thresholds.every(value => near(value, boundaries)) ? "consistent" : "inconsistent";
}

function holdableRules(key, dataRoot) {
    const filename = path.join(dataRoot, "exceptions", `${key}.json`);
    if (!fs.existsSync(filename)) return [];
    const rules = JSON.parse(fs.readFileSync(filename, "utf8"));
    return Object.entries(rules)
        .filter(([id, rule]) => /^\d+$/.test(id) && rule && typeof rule === "object" && rule.is_holdable === true)
        .map(([id, rule]) => ({ action_id: Number(id), rule }));
}

function analyzeFighter(key, ac, dataRoot) {
    const graph = actionRoots(ac);
    const rows = [];
    for (const { action_id, rule } of holdableRules(key, dataRoot)) {
        const keys = holdKeys(graph, action_id);
        const frame = Number(scalarField(graph.roots.get(action_id), "Frame"));
        rows.push({
            action_id,
            charge_min: rule.charge_min,
            charge_max: rule.charge_max,
            action_frame: Number.isFinite(frame) ? frame : null,
            verdict: graph.roots.has(action_id) ? classify(rule, keys, frame) : "action_missing",
            keys
        });
    }
    return rows;
}

function report(options) {
    const roster = fighterRoster.loadRoster(options.rosterPath);
    const root = path.resolve(options.acbcmRoot || path.join(TOOL_ROOT, "acbcm"));
    const normalized = builder.normalizeVersion(options.version);
    const match = builder.versionDirectories(root).filter(item => item.normalized === normalized);
    if (match.length !== 1) throw new Error(`ACBCM ${normalized} 必须正好存在一个对应目录。`);
    const directory = path.join(root, match[0].name);
    const wanted = options.characters ? new Set(options.characters.map(name => name.toLowerCase())) : null;
    const fighters = [];
    for (const pair of archive.scanDumpDirectory(directory).pairs) {
        const stemId = builder.filenameFighterId(pair.stem);
        const stemFighter = stemId !== null ? roster.byId(stemId) : null;
        if (wanted && stemFighter && !wanted.has(stemFighter.key.toLowerCase())) continue;
        const ac = bcmCore.parseSourceText(fs.readFileSync(path.join(directory, pair.ac), "utf8"));
        const fighter = roster.byId(Number(ac.fighter_id));
        const key = fighter ? fighter.key : `ESF_${String(ac.fighter_id).padStart(3, "0")}`;
        if (wanted && !wanted.has(key.toLowerCase())) continue;
        const rows = analyzeFighter(key, ac, options.dataRoot || DATA_ROOT);
        if (!rows.length) continue;
        fighters.push({
            character: key,
            fighter_id: Number(ac.fighter_id),
            inherited_fields: ac.inherited_fields || null,
            rows
        });
    }
    return { schema: "sf6cc.hold-window-report.v1", version: normalized, fighters };
}

function windowText(keys) {
    return keys.map(key => `T20→${key.target}(键${key.button_mask},档${key.profile}`
        + `${key.window ? `,${key.window.start}-${key.window.end}` : ""})`).join(" ");
}

function markdown(result) {
    const counts = {};
    for (const fighter of result.fighters) {
        for (const row of fighter.rows) counts[row.verdict] = (counts[row.verdict] || 0) + 1;
    }
    const lines = [`# 长按阈值与 AC Type 20 帧窗口 ${result.version}`, "",
        `结论统计：${Object.entries(counts).map(([verdict, count]) => `${verdict} ${count}`).join("，") || "无"}`, "",
        "| 角色 | Action | 手写 min | 手写 max | 动作总帧 | 结论 | Type 20 分支 |",
        "| --- | ---: | ---: | ---: | ---: | --- | --- |"];
    for (const fighter of result.fighters) {
        for (const row of fighter.rows) {
            lines.push(`| ${fighter.character} | ${row.action_id} | ${row.charge_min ?? ""} | ${row.charge_max ?? ""} | `
                + `${row.action_frame ?? ""} | ${row.verdict} | ${windowText(row.keys)} |`);
        }
    }
    return `${lines.join("\n")}\n`;
}

function run(argv) {
    const args = argsOf(argv);
    if (!args["--version"]) throw new Error("用法: node hold_window_report.js --version <日期> [--characters A,B] [--out 报告.md] [--json 报告.json]");
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

module.exports = { frameWindow, holdKeys, actionRoots, classify, analyzeFighter, report, markdown };
