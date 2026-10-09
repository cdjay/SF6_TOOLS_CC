#!/usr/bin/env node
"use strict";

// Compares two AC/BCM dump versions per fighter and lists what a game update
// broke: Action IDs that disappeared or now point at a different action, the
// most likely new ID for each (same structural signature), and every
// exception, display override or compatibility entry that names an affected
// ID. Action IDs are version-local, so this report decides whether existing
// per-fighter data and saved combos need an offline migration.

const fs = require("fs");
const path = require("path");
const archive = require("./archive_builder.js");
const builder = require("./lastjson_builder.js");
const bcmCore = require("../bcm_catalog_builder/bcm_catalog_core.js");
const bcmFingerprint = require("./bcm_fingerprint.js");
const fighterRoster = require("../fighter_roster.js");

const TOOL_ROOT = __dirname;
const DEFAULT_ACBCM_ROOT = path.join(TOOL_ROOT, "acbcm");
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

function readSource(filename) {
    return bcmCore.parseSourceText(fs.readFileSync(filename, "utf8"));
}

function versionDirectory(root, version) {
    const normalized = builder.normalizeVersion(version);
    const matches = builder.versionDirectories(root).filter(item => item.normalized === normalized);
    if (matches.length !== 1) throw new Error(`ACBCM ${normalized} 必须正好存在一个对应目录，当前 ${matches.length} 个。`);
    return path.join(root, matches[0].name);
}

// Signatures per character Action. structure = BranchKey types with counts
// and TriggerKey groups; full = total frames + structure. Equal signatures
// under different IDs mark an Action that moved; a frame-only difference at
// the same ID is a balance change, not a moved Action.
function actionSignatures(acSource) {
    const objects = new Map((acSource.objects || []).map(object => [object.object_id, object]));
    const fieldValue = (object, name) => {
        const field = (object.fields || []).find(item => item.name === name);
        return field && field.value;
    };
    const signatures = new Map();
    for (const record of acSource.records || []) {
        if (!record || record.source_scope !== "character" || !record.action_ref
            || record.action_ref.kind !== "ref") continue;
        const actionId = Number(record.native_action_id);
        const root = objects.get(record.action_ref.object_id);
        if (!root || signatures.has(actionId)) continue;
        const frame = fieldValue(root, "Frame");
        const branchTypes = new Map();
        const triggerGroups = [];
        const keys = fieldValue(root, "Keys");
        const pending = keys && keys.kind === "ref" ? [keys.object_id] : [];
        const visited = new Set();
        while (pending.length) {
            const id = pending.pop();
            if (visited.has(id)) continue;
            visited.add(id);
            const object = objects.get(id);
            if (!object) continue;
            if (object.object_type === "CharacterAsset.BranchKey") {
                const type = Number((fieldValue(object, "Type") || {}).value);
                branchTypes.set(type, (branchTypes.get(type) || 0) + 1);
            } else if (object.object_type === "CharacterAsset.TriggerKey") {
                triggerGroups.push(Number((fieldValue(object, "TriggerGroup") || {}).value));
            }
            for (const field of object.fields || []) if (field.value && field.value.kind === "ref") pending.push(field.value.object_id);
            for (const item of object.items || []) if (item.value && item.value.kind === "ref") pending.push(item.value.object_id);
        }
        const branches = [...branchTypes.entries()].sort((a, b) => a[0] - b[0])
            .map(([type, count]) => `${type}x${count}`).join(",");
        const structure = `B:${branches}|T:${triggerGroups.sort((a, b) => a - b).join(",")}`;
        signatures.set(actionId, { structure, full: `${frame && frame.value}|${structure}` });
    }
    return signatures;
}

function loadVersion(directory) {
    const scan = archive.scanDumpDirectory(directory);
    const fighters = new Map();
    for (const pair of scan.pairs) {
        const ac = readSource(path.join(directory, pair.ac));
        const bcm = readSource(path.join(directory, pair.bcm));
        const fighterId = Number(ac.fighter_id);
        fighters.set(fighterId, {
            signatures: actionSignatures(ac),
            fingerprint: bcmFingerprint.fromBcmSource(bcm)
        });
    }
    return fighters;
}

function idsOf(value) {
    if (value === undefined || value === null) return [];
    if (Array.isArray(value)) return value.map(Number).filter(Number.isFinite);
    return String(value).split(",").map(item => Number(item.trim())).filter(Number.isFinite);
}

// Every Action ID a per-fighter data file depends on, with where it appears.
function referencedIds(key) {
    const references = [];
    const add = (file, id, where) => references.push({ file, id: Number(id), where });
    const read = relative => {
        const filename = path.join(DATA_ROOT, relative);
        return fs.existsSync(filename) ? JSON.parse(fs.readFileSync(filename, "utf8")) : null;
    };
    const exceptions = read(`exceptions/${key}.json`) || {};
    for (const [idText, rule] of Object.entries(exceptions)) {
        if (!/^\d+$/.test(idText) || !rule || typeof rule !== "object") continue;
        add(`exceptions/${key}.json`, idText, "key");
        for (const field of ["absorb_ids", "optional_parent_ids", "ignore_prev_id", "action_alias_ids", "runtime_force_after_ids"]) {
            for (const id of idsOf(rule[field])) add(`exceptions/${key}.json`, id, `${idText}.${field}`);
        }
    }
    const overrides = read(`command_display_overrides/${key}.json`) || {};
    for (const section of ["entries", "contextual_internal_phases", "presentation_contexts"]) {
        for (const [idText, entry] of Object.entries(overrides[section] || {})) {
            if (/^\d+$/.test(idText)) add(`command_display_overrides/${key}.json`, idText, section);
            for (const id of idsOf(entry && entry.owner_ids)) add(`command_display_overrides/${key}.json`, id, `${section}.${idText}.owner_ids`);
        }
    }
    const compatibility = read(`action_compatibility/${key}.json`);
    for (const entry of (compatibility && compatibility.entries) || []) {
        add(`action_compatibility/${key}.json`, entry.runtime_action_id, "runtime_action_id");
    }
    return references;
}

function uniqueMatch(index, value) {
    const candidates = index.get(value) || [];
    return candidates.length === 1 ? candidates[0] : null;
}

function compareFighter(key, before, after, references = referencedIds(key)) {
    const removed = [], changed = [], framesChanged = [], added = [];
    for (const [id, signature] of before.signatures) {
        const current = after.signatures.get(id);
        if (!current) removed.push(id);
        else if (current.structure !== signature.structure) changed.push(id);
        else if (current.full !== signature.full) framesChanged.push(id);
    }
    for (const id of after.signatures.keys()) if (!before.signatures.has(id)) added.push(id);
    const byFull = new Map(), byStructure = new Map();
    for (const [id, signature] of after.signatures) {
        for (const [index, value] of [[byFull, signature.full], [byStructure, signature.structure]]) {
            if (!index.has(value)) index.set(value, []);
            index.get(value).push(id);
        }
    }
    const suggestions = {};
    for (const id of [...removed, ...changed]) {
        const signature = before.signatures.get(id);
        const match = uniqueMatch(byFull, signature.full) ?? uniqueMatch(byStructure, signature.structure);
        suggestions[id] = match !== null && match !== id ? match : null;
    }
    const affected = new Set([...removed, ...changed]);
    const impact = references.filter(reference => affected.has(reference.id))
        .map(reference => ({ ...reference, suggested_id: suggestions[reference.id] }));
    const fingerprintChanged = before.fingerprint.hash !== after.fingerprint.hash
        || before.fingerprint.count !== after.fingerprint.count;
    const status = removed.length || changed.length || added.length || fingerprintChanged
        ? "changed" : (framesChanged.length ? "frames_changed" : "unchanged");
    const sorted = values => values.sort((a, b) => a - b);
    return {
        character: key, status,
        bcm_fingerprint: { before: before.fingerprint, after: after.fingerprint, changed: fingerprintChanged },
        removed_action_ids: sorted(removed),
        changed_action_ids: sorted(changed),
        frames_changed_action_ids: sorted(framesChanged),
        added_action_ids: sorted(added),
        suggested_new_ids: suggestions,
        impacted_references: impact
    };
}

function compareVersions(options) {
    const root = path.resolve(options.acbcmRoot || DEFAULT_ACBCM_ROOT);
    const roster = fighterRoster.loadRoster(options.rosterPath);
    const before = loadVersion(versionDirectory(root, options.old));
    const after = loadVersion(versionDirectory(root, options.new));
    const fighters = [];
    for (const fighterId of [...new Set([...before.keys(), ...after.keys()])].sort((a, b) => a - b)) {
        const fighter = roster.byId(fighterId);
        const key = fighter ? fighter.key : `ESF_${String(fighterId).padStart(3, "0")}`;
        if (!before.has(fighterId)) fighters.push({ character: key, fighter_id: fighterId, status: "new" });
        else if (!after.has(fighterId)) fighters.push({ character: key, fighter_id: fighterId, status: "missing_in_new" });
        else fighters.push({ fighter_id: fighterId, ...compareFighter(key, before.get(fighterId), after.get(fighterId)) });
    }
    return {
        schema: "sf6cc.acbcm-version-diff.v1",
        old_version: builder.normalizeVersion(options.old),
        new_version: builder.normalizeVersion(options.new),
        summary: {
            unchanged: fighters.filter(item => item.status === "unchanged").map(item => item.character),
            frames_changed: fighters.filter(item => item.status === "frames_changed").map(item => item.character),
            changed: fighters.filter(item => item.status === "changed").map(item => item.character),
            new: fighters.filter(item => item.status === "new").map(item => item.character),
            missing_in_new: fighters.filter(item => item.status === "missing_in_new").map(item => item.character)
        },
        fighters
    };
}

function markdown(report) {
    const lines = [
        `# AC/BCM 版本对比 ${report.old_version} → ${report.new_version}`, "",
        `- 未变化：${report.summary.unchanged.length}（${report.summary.unchanged.join(", ") || "无"}）`,
        `- 仅帧数变化（Action ID 未移动）：${report.summary.frames_changed.join(", ") || "无"}`,
        `- 有变化：${report.summary.changed.length}（${report.summary.changed.join(", ") || "无"}）`,
        `- 新角色：${report.summary.new.join(", ") || "无"}`,
        `- 新版本缺少：${report.summary.missing_in_new.join(", ") || "无"}`, ""
    ];
    for (const fighter of report.fighters.filter(item => item.status === "changed")) {
        lines.push(`## ${fighter.character}（fighter ${fighter.fighter_id}）`, "");
        lines.push(`- BCM 指纹：${fighter.bcm_fingerprint.before.count}:${fighter.bcm_fingerprint.before.hash} → `
            + `${fighter.bcm_fingerprint.after.count}:${fighter.bcm_fingerprint.after.hash}`);
        lines.push(`- 删除 Action：${fighter.removed_action_ids.join(", ") || "无"}`);
        lines.push(`- 同 ID 结构变化：${fighter.changed_action_ids.join(", ") || "无"}`);
        lines.push(`- 仅帧数变化：${fighter.frames_changed_action_ids.join(", ") || "无"}`);
        lines.push(`- 新增 Action：${fighter.added_action_ids.join(", ") || "无"}`);
        const moves = Object.entries(fighter.suggested_new_ids).filter(([, value]) => value !== null);
        if (moves.length) lines.push(`- 结构唯一匹配的新 ID：${moves.map(([from, to]) => `${from}→${to}`).join(", ")}`);
        if (fighter.impacted_references.length) {
            lines.push("", "受影响的数据条目（需离线迁移）：", "");
            for (const reference of fighter.impacted_references) {
                const hint = typeof reference.suggested_id === "number" ? `，建议 ${reference.suggested_id}` : "";
                lines.push(`- \`${reference.file}\` ${reference.where}：${reference.id}${hint}`);
            }
        }
        lines.push("");
    }
    return `${lines.join("\n")}\n`;
}

function run(argv) {
    const args = argsOf(argv);
    if (!args["--old"] || !args["--new"]) {
        throw new Error("用法: node compare_acbcm_versions.js --old <日期> --new <日期> [--out 报告.md] [--json 报告.json]");
    }
    const report = compareVersions({ old: args["--old"], new: args["--new"], acbcmRoot: args["--acbcm-root"] });
    const text = markdown(report);
    if (args["--out"]) fs.writeFileSync(args["--out"], text, "utf8");
    if (args["--json"]) fs.writeFileSync(args["--json"], `${JSON.stringify(report, null, 2)}\n`, "utf8");
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

module.exports = { actionSignatures, compareFighter, compareVersions, referencedIds, markdown };
