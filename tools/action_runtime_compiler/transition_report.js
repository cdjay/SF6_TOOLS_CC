#!/usr/bin/env node
"use strict";

// Joins a transition capture (tools/acbcm_exporter/SF6CC_Transition_Probe.lua,
// transitions-fNNN.jsonl) with the fighter's AC+BCM dump. Each observed
// Action change gets the AC mechanism that entered it (a BranchKey from the
// previous Action, preferring one whose frame window holds the previous
// Action's last frame, else the BCM trigger of the new Action) and the
// engine values the runtime reads. The runtime counts a change as a player
// step from the engine values alone when
//   state_flags == 0, or state_flags == 16 and action_code > 0 and BranchType != 0,
//   or BranchType == 0x20000014 (Type 20) while a button is held;
// force / ignore exceptions correct that decision. The report shows, per
// mechanism, how often the engine already decides "player step", and for
// every Action with a curated force or ignore whether the capture agrees
// the correction is needed.
//
// Branch.BranchType is a bit set: bit n is set when a BranchKey of Type n
// entered the Action (a Type 13 landing reads 8192). A Type 63 branch (the
// back throw) sets no bit. The first captures (2026-10-10) carried no fighter
// ID; pass --fighter for those.
//
//   node transition_report.js --capture transitions-f001.jsonl --version 2026-10-13
//       [--fighter Akuma] [--out report.md] [--json report.json]

const fs = require("fs");
const path = require("path");
const archive = require("./archive_builder.js");
const builder = require("./lastjson_builder.js");
const bcmCore = require("../bcm_catalog_builder/bcm_catalog_core.js");
const fighterRoster = require("../fighter_roster.js");
const acModel = require("./ac_model.js");

const TOOL_ROOT = __dirname;
const DATA_ROOT = path.resolve(TOOL_ROOT, "../../data/TrainingComboTrials_data");
const TYPE20_BRANCH = 0x20000014;

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

function readCapture(filename) {
    return fs.readFileSync(filename, "utf8").split(/\r?\n/).filter(line => line.trim())
        .map(line => JSON.parse(line));
}

// Bit indices of a BranchType value (exact for the full 64-bit range).
function branchBits(value) {
    if (value === undefined || value === null) return [];
    let rest;
    try { rest = BigInt(typeof value === "number" ? Math.round(value) : String(value)); } catch (error) { return []; }
    if (rest < 0n) rest = BigInt.asUintN(64, rest);
    const bits = [];
    for (let bit = 0; rest > 0n; bit += 1, rest >>= 1n) if (rest & 1n) bits.push(bit);
    return bits;
}

function engineStep(record) {
    const flags = Number(record.flags);
    const code = Number(record.code) || 0;
    const branch = Number(record.branch) || 0;
    if (flags === 0) return true;
    if (flags !== 16) return false;
    if (code > 0 && branch !== 0) return true;
    return branch === TYPE20_BRANCH && (Number(record.input) & 0xFFFF) > 0;
}

// The AC mechanism that entered record.act from record.prev.
function mechanism(model, record) {
    const prev = model.actions.get(Number(record.prev))
        || (model.common && model.common.actions.get(Number(record.prev)));
    const candidates = prev ? prev.branches.filter(branch => branch.target === Number(record.act)) : [];
    const frame = Number(record.prev_frame);
    const inWindow = candidates.filter(branch => branch.window
        && frame >= branch.window.start - 1 && frame <= branch.window.end + 1);
    const chosen = inWindow.length ? inWindow : candidates;
    if (chosen.length) {
        const kinds = [...new Set(chosen.map(branch => branch.type === 20 ? `T20/p0=${branch.params[0]}` : `T${branch.type}`))].sort();
        return kinds.join("+");
    }
    if (acModel.classicTrigger(model, record.act) || model.bcmActions.has(Number(record.act))) return "bcm";
    return "unexplained";
}

function analyze(model, records, curated) {
    const byMechanism = {};
    const byAction = new Map();
    for (const record of records) {
        if (record.prev === undefined || record.prev === null) continue;
        const kind = mechanism(model, record);
        const step = engineStep(record);
        const engineBits = branchBits(record.branch).map(bit => `T${bit}`).join("+") || "none";
        const bucket = byMechanism[kind] = byMechanism[kind] || { total: 0, engine_step: 0, branch_types: {} };
        bucket.total += 1;
        if (step) bucket.engine_step += 1;
        bucket.branch_types[engineBits] = (bucket.branch_types[engineBits] || 0) + 1;
        const actionId = Number(record.act);
        if (!byAction.has(actionId)) byAction.set(actionId, { total: 0, engine_step: 0, mechanisms: {} });
        const action = byAction.get(actionId);
        action.total += 1;
        if (step) action.engine_step += 1;
        action.mechanisms[kind] = (action.mechanisms[kind] || 0) + 1;
    }
    const corrections = [];
    for (const [id, rule] of Object.entries(curated || {})) {
        if (!/^\d+$/.test(id) || !rule || typeof rule !== "object" || (rule.force !== true && rule.ignore !== true)) continue;
        const observed = byAction.get(Number(id));
        const facet = rule.force === true ? "force" : "ignore";
        let verdict = "not_observed";
        if (observed) {
            const allStep = observed.engine_step === observed.total;
            const noStep = observed.engine_step === 0;
            if (facet === "force") verdict = noStep ? "needed" : (allStep ? "redundant" : "partly_needed");
            else verdict = allStep ? "needed" : (noStep ? "redundant" : "partly_needed");
        }
        corrections.push({ action_id: Number(id), facet, verdict, observed: observed || null });
    }
    return { by_mechanism: byMechanism, corrections };
}

function loadModel(acbcmRoot, version, fighterId) {
    const match = builder.versionDirectories(acbcmRoot).filter(item => item.normalized === builder.normalizeVersion(version));
    if (match.length !== 1) throw new Error(`ACBCM ${version} 必须正好存在一个对应目录。`);
    const directory = path.join(acbcmRoot, match[0].name);
    const stem = `f${String(fighterId).padStart(3, "0")}`;
    const pair = archive.scanDumpDirectory(directory).pairs.find(item => item.stem.toLowerCase() === stem);
    if (!pair) throw new Error(`ACBCM ${version} 没有 ${stem} 的导出。`);
    const ac = bcmCore.parseSourceText(fs.readFileSync(path.join(directory, pair.ac), "utf8"));
    const bcm = bcmCore.parseSourceText(fs.readFileSync(path.join(directory, pair.bcm), "utf8"));
    return acModel.buildModel(ac, bcm);
}

function report(options) {
    const records = readCapture(options.capture);
    const roster = fighterRoster.loadRoster(options.rosterPath);
    let fighterId = Number((records.find(record => record.fighter !== undefined) || {}).fighter);
    if (options.fighter !== undefined && options.fighter !== null) {
        const named = roster.byKey(String(options.fighter)) || roster.byId(Number(options.fighter));
        fighterId = named ? named.id : Number(options.fighter);
    }
    if (!Number.isInteger(fighterId)) throw new Error("采集文件里没有 fighter，请用 --fighter 指定角色。");
    const fighter = roster.byId(fighterId);
    const key = fighter ? fighter.key : `ESF_${String(fighterId).padStart(3, "0")}`;
    const model = loadModel(path.resolve(options.acbcmRoot || path.join(TOOL_ROOT, "acbcm")), options.version, fighterId);
    const curatedFile = path.join(options.dataRoot || DATA_ROOT, "exceptions", `${key}.json`);
    const curated = fs.existsSync(curatedFile) ? JSON.parse(fs.readFileSync(curatedFile, "utf8")) : {};
    return { schema: "sf6cc.transition-report.v1", character: key, fighter_id: fighterId,
        transitions: records.length, ...analyze(model, records, curated) };
}

function markdown(result) {
    const lines = [`# 动作切换与引擎标志 ${result.character}`, "", `共 ${result.transitions} 次切换。`, "",
        "| 进入方式 | 次数 | 引擎判为玩家步骤 | 引擎 BranchType 位 |", "| --- | ---: | ---: | --- |"];
    for (const [kind, bucket] of Object.entries(result.by_mechanism).sort((a, b) => b[1].total - a[1].total)) {
        lines.push(`| ${kind} | ${bucket.total} | ${bucket.engine_step} | ${JSON.stringify(bucket.branch_types)} |`);
    }
    lines.push("", "| 手写规则 | Action | 结论 | 观察到的进入方式 |", "| --- | ---: | --- | --- |");
    for (const item of result.corrections) {
        lines.push(`| ${item.facet} | ${item.action_id} | ${item.verdict} | `
            + `${item.observed ? JSON.stringify(item.observed.mechanisms) : ""} |`);
    }
    return `${lines.join("\n")}\n`;
}

function run(argv) {
    const args = argsOf(argv);
    if (!args["--capture"] || !args["--version"]) {
        throw new Error("用法: node transition_report.js --capture transitions-f001.jsonl --version <日期> [--out 报告.md] [--json 报告.json]");
    }
    const result = report({ capture: args["--capture"], version: args["--version"], acbcmRoot: args["--acbcm-root"],
        fighter: args["--fighter"] });
    const text = markdown(result);
    if (args["--out"]) fs.writeFileSync(args["--out"], text, "utf8");
    if (args["--json"]) fs.writeFileSync(args["--json"], `${JSON.stringify(result, null, 1)}\n`, "utf8");
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

module.exports = { readCapture, branchBits, engineStep, mechanism, analyze, markdown };
