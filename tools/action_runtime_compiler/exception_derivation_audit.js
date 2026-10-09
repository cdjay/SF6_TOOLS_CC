#!/usr/bin/env node
"use strict";

// Exception derivation audit: for every curated rule in
// data/TrainingComboTrials_data/exceptions, the AC+BCM structure behind each
// rule facet. A facet is one runtime meaning of an entry (force, ignore,
// absorb_ids child, action_alias_ids member, ignore_prev source,
// optional_parent_ids parent, hold, transient precursor). Each facet item gets
// a structural signature, e.g. "bcm|T20/p0=0" for a forced Action that has a
// classic BCM trigger and is also entered through a Type 20 release branch.
//
// For Action-level facets (force, ignore) the audit also counts how many
// Actions WITHOUT that facet share the signature: a derivation rule keyed on
// the signature would change their behavior, so only signatures without such
// Actions can move to the generated layer unchanged.
//
// Candidate derivation rules are scored the same way: how many curated items
// a rule reproduces, how many Actions (or pairs) it would add, and how many
// of those additions occur as recorded steps in the frozen corpus
// (release/tester_packages/0803), where an addition would change behavior
// that players have actually exercised.
//
//   node exception_derivation_audit.js [--versions 2026-10-09,2026-08-03] [--characters Ryu,Luke]
//       [--corpus-root release/tester_packages/0803] [--out audit.md] [--json audit.json]

const fs = require("fs");
const path = require("path");
const archive = require("./archive_builder.js");
const builder = require("./lastjson_builder.js");
const bcmCore = require("../bcm_catalog_builder/bcm_catalog_core.js");
const fighterRoster = require("../fighter_roster.js");
const acModel = require("./ac_model.js");

const TOOL_ROOT = __dirname;
const DATA_ROOT = path.resolve(TOOL_ROOT, "../../data/TrainingComboTrials_data");
const DEFAULT_CORPUS_ROOT = path.resolve(TOOL_ROOT, "../../release/tester_packages/0803");
const DEFAULT_VERSIONS = ["2026-10-09", "2026-08-03"];
// Command-table ownerships whose Actions the runtime does not count as player
// steps on its own; force is the candidate rule (one rule per ownership).
const FORCE_OWNERSHIPS = ["inherited", "rebind", "automatic_hold_transition", "ac_state_direction",
    "type20_hold_continuation", "ac_type13_neutral", "ac_state_neutral", "internal_state_transition",
    "type20_action_phase", "verified_alias", "classic_runtime", "official_semantic", "direct"];
// Branch types through which an Action continues into its own internal phase.
const AUTOMATIC_PHASE_TYPES = new Set([0, 2, 4, 5, 12, 13, 29, 36, 37, 49, 52, 54]);

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

function readJson(filename, fallback) {
    return fs.existsSync(filename) ? JSON.parse(fs.readFileSync(filename, "utf8")) : fallback;
}

function ids(value) {
    if (value === undefined || value === null || value === "") return [];
    const items = Array.isArray(value) ? value : String(value).split(",");
    return items.map(item => Number(String(item).trim())).filter(Number.isInteger);
}

function actionRules(document) {
    return Object.entries(document || {})
        .filter(([id, rule]) => /^\d+$/.test(id) && rule && typeof rule === "object")
        .map(([id, rule]) => ({ id: Number(id), rule }));
}

// Branch kind as used in signatures. Type 20 keeps Param00 (release check 0
// vs press check 1); DynamicTriggerKeys are marked "D".
function branchKind(branch) {
    let kind = `T${branch.type}`;
    if (branch.type === 20) kind += `/p0=${branch.params[0]}`;
    return branch.dynamic ? `D${kind}` : kind;
}

function kindSet(branches) {
    return [...new Set(branches.map(branchKind))].sort().join("+");
}

function view(model, scope) {
    return scope === "common" ? model.common : model;
}

function incomingSignature(model, scope, actionId) {
    const scoped = view(model, scope);
    const incoming = (scoped.incoming.get(actionId) || []).filter(branch => branch.source !== actionId);
    const parts = [];
    if (acModel.classicTrigger(model, actionId)) parts.push("bcm");
    parts.push(incoming.length ? kindSet(incoming) : "noinc");
    return parts.join("|");
}

function pairSignature(model, scope, source, target) {
    const scoped = view(model, scope);
    const direct = (scoped.actions.get(source) || { branches: [] }).branches.filter(branch => branch.target === target);
    if (direct.length) return kindSet(direct);
    const reverse = (scoped.actions.get(target) || { branches: [] }).branches.filter(branch => branch.target === source);
    if (reverse.length) return `rev:${kindSet(reverse)}`;
    for (const first of (scoped.actions.get(source) || { branches: [] }).branches) {
        const second = (scoped.actions.get(first.target) || { branches: [] }).branches.filter(branch => branch.target === target);
        if (second.length && first.target !== source) return `2hop:${branchKind(first)}>${kindSet(second)}`;
    }
    const sharedParent = (scoped.incoming.get(source) || []).some(branch =>
        (scoped.actions.get(branch.source) || { branches: [] }).branches.some(other => other.target === target));
    return sharedParent ? "sibling" : "none";
}

function groupSignature(model, parent, child) {
    if (model.groups.enables.get(parent) && model.groups.enables.get(parent).has(child)) return "group";
    return model.keyed_groups ? null : "group_unknown";
}

function facetItems(entry, scope) {
    const { id, rule } = entry;
    const items = [];
    if (rule.force === true) items.push({ facet: "force", id });
    if (rule.ignore === true) items.push({ facet: "ignore", id });
    for (const child of ids(rule.absorb_ids)) items.push({ facet: "absorb", id, other: child });
    for (const alias of ids(rule.action_alias_ids)) items.push({ facet: "alias", id, other: alias });
    for (const previous of ids(rule.ignore_prev_id)) items.push({ facet: "ignore_prev", id, other: previous, frames: rule.ignore_prev_frames });
    for (const parent of ids(rule.optional_parent_ids)) items.push({ facet: "optional_parent", id, other: parent });
    if (rule.is_holdable === true) items.push({ facet: "hold", id, value: [rule.charge_min, rule.charge_max] });
    const events = rule.action_event_rules && typeof rule.action_event_rules === "object" ? rule.action_event_rules : null;
    for (const precursor of ids(events && events.transient_precursor_ids)) items.push({ facet: "transient_precursor", id, other: precursor });
    if (events && events.suppress_after) {
        for (const previous of ids(events.suppress_after.previous_ids)) items.push({ facet: "suppress_after", id, other: previous });
    }
    if (events && events.preserve_quick_successor) items.push({ facet: "quick_successor", id });
    return items.map(item => ({ ...item, scope }));
}

function signatureOf(model, item) {
    const scope = item.scope;
    switch (item.facet) {
    case "force":
    case "ignore":
    case "quick_successor":
        return incomingSignature(model, scope, item.id);
    case "absorb":
        return pairSignature(model, scope, item.id, item.other);
    case "alias":
    case "ignore_prev":
    case "transient_precursor":
    case "suppress_after":
        return pairSignature(model, scope, item.other, item.id);
    case "optional_parent": {
        const group = scope === "character" ? groupSignature(model, item.other, item.id) : null;
        const pair = pairSignature(model, scope, item.other, item.id);
        return group ? `${group}|${pair}` : pair;
    }
    case "hold": {
        const action = view(model, scope).actions.get(item.id);
        const holds = (action ? action.branches : []).filter(branch => branch.type === 20);
        if (!holds.length) return "no_t20";
        return model.frame_windows ? "t20_windows" : "t20_no_windows";
    }
    default:
        return "unknown";
    }
}

// Character -> { Action ID: occurrences as a recorded step }.
function corpusIndex(root) {
    const index = {};
    if (!root || !fs.existsSync(root)) return index;
    const walk = directory => fs.readdirSync(directory, { withFileTypes: true }).flatMap(entry =>
        entry.isDirectory() ? walk(path.join(directory, entry.name))
            : (entry.name.endsWith(".json") ? [path.join(directory, entry.name)] : []));
    for (const entry of fs.readdirSync(root, { withFileTypes: true })) {
        const match = entry.isDirectory() && entry.name.match(/^(.+)_CustomCombos$/);
        if (!match) continue;
        const counts = {};
        for (const file of walk(path.join(root, entry.name))) {
            let sequence;
            try { sequence = JSON.parse(fs.readFileSync(file, "utf8")); } catch (error) { continue; }
            if (!Array.isArray(sequence)) continue;
            for (const step of sequence) {
                const id = Number(step && step.id);
                if (Number.isInteger(id)) counts[id] = (counts[id] || 0) + 1;
            }
        }
        index[match[1]] = counts;
    }
    return index;
}

function emptyScore(name) {
    return { rule: name, covered: 0, added: 0, added_in_corpus: 0, added_examples: [], corpus_examples: [] };
}

function addTo(score, label, inCorpus) {
    score.added += 1;
    if (score.added_examples.length < 8) score.added_examples.push(label);
    if (inCorpus) {
        score.added_in_corpus += 1;
        if (score.corpus_examples.length < 8) score.corpus_examples.push(label);
    }
}

// Scores the candidate rules on one fighter and accumulates into scores.
function scoreCandidates(scores, key, model, curated, generated, display, corpus) {
    const seen = corpus[key] || {};
    const has = (document, id, test) => {
        const rule = document[String(id)];
        return Boolean(rule && typeof rule === "object" && test(rule));
    };
    const ownership = id => (display[String(id)] && display[String(id)].ownership) || "absent";
    for (const name of FORCE_OWNERSHIPS) {
        const score = scores[`force: ownership=${name}`] = scores[`force: ownership=${name}`] || emptyScore(`force: ownership=${name}`);
        for (const actionId of model.actions.keys()) {
            if (ownership(actionId) !== name) continue;
            if (has(curated, actionId, rule => rule.force === true)) score.covered += 1;
            else if (!has(generated, actionId, rule => rule.force === true)) addTo(score, `${key}:${actionId}`, Boolean(seen[actionId]));
        }
    }
    const pairsOf = (document, field) => {
        const result = new Set();
        for (const [id, rule] of Object.entries(document)) {
            if (!/^\d+$/.test(id) || !rule || typeof rule !== "object") continue;
            const values = field === "transient_precursor_ids"
                ? (rule.action_event_rules && rule.action_event_rules.transient_precursor_ids) : rule[field];
            for (const other of ids(values)) result.add(field === "absorb_ids" ? `${id}>${other}` : `${other}>${id}`);
        }
        return result;
    };
    const absorbCurated = pairsOf(curated, "absorb_ids");
    const absorbGenerated = pairsOf(generated, "absorb_ids");
    const prevCurated = pairsOf(curated, "ignore_prev_id");
    const absorb = scores["absorb: automatic phase of a BCM action"] = scores["absorb: automatic phase of a BCM action"]
        || emptyScore("absorb: automatic phase of a BCM action");
    const ignorePrev = scores["ignore_prev: Type 20 release continuation"] = scores["ignore_prev: Type 20 release continuation"]
        || emptyScore("ignore_prev: Type 20 release continuation");
    const seenPairs = new Set();
    for (const action of model.actions.values()) {
        const bcm = Boolean(acModel.classicTrigger(model, action.id));
        for (const branch of action.branches) {
            const pair = `${action.id}>${branch.target}`;
            if (branch.target === action.id || branch.target <= 0 || acModel.classicTrigger(model, branch.target)) continue;
            if (bcm && AUTOMATIC_PHASE_TYPES.has(branch.type) && ownership(branch.target) === "absent"
                && !seenPairs.has(`a${pair}`)) {
                seenPairs.add(`a${pair}`);
                if (absorbCurated.has(pair)) absorb.covered += 1;
                else if (!absorbGenerated.has(pair)) addTo(absorb, `${key}:${pair}`, Boolean(seen[branch.target]));
            }
            if (branch.type === 20 && branch.params[0] === 0 && !seenPairs.has(`p${pair}`)) {
                seenPairs.add(`p${pair}`);
                if (prevCurated.has(pair)) ignorePrev.covered += 1;
                else addTo(ignorePrev, `${key}:${pair}`, Boolean(seen[branch.target]));
            }
        }
    }
}

function loadFighter(roots, fighter, versions) {
    const stem = `f${String(fighter.id).padStart(3, "0")}`;
    for (const version of versions) {
        const match = builder.versionDirectories(roots).filter(item => item.normalized === builder.normalizeVersion(version));
        if (match.length !== 1) continue;
        const directory = path.join(roots, match[0].name);
        const pair = archive.scanDumpDirectory(directory).pairs.find(item => item.stem.toLowerCase() === stem);
        if (!pair) continue;
        const ac = bcmCore.parseSourceText(fs.readFileSync(path.join(directory, pair.ac), "utf8"));
        const bcm = bcmCore.parseSourceText(fs.readFileSync(path.join(directory, pair.bcm), "utf8"));
        return { version: match[0].normalized, model: acModel.buildModel(ac, bcm) };
    }
    return null;
}

// Action-level facets: Actions that share a signature but lack the facet.
function signatureCensus(model, scope, facet, curatedIds, generatedIds) {
    const result = new Map();
    for (const actionId of view(model, scope).actions.keys()) {
        const signature = incomingSignature(model, scope, actionId);
        if (!result.has(signature)) result.set(signature, { with: 0, without: 0 });
        const bucket = result.get(signature);
        if (curatedIds.has(actionId) || generatedIds.has(actionId)) bucket.with += 1;
        else bucket.without += 1;
    }
    return result;
}

function audit(options) {
    const roster = fighterRoster.loadRoster(options.rosterPath);
    const acbcmRoot = path.resolve(options.acbcmRoot || path.join(TOOL_ROOT, "acbcm"));
    const dataRoot = options.dataRoot || DATA_ROOT;
    const versions = options.versions || DEFAULT_VERSIONS;
    const wanted = options.characters ? new Set(options.characters.map(name => name.toLowerCase())) : null;
    const items = [];
    const fighters = [];
    const census = { force: new Map(), ignore: new Map() };
    const corpus = corpusIndex(options.corpusRoot === undefined ? DEFAULT_CORPUS_ROOT : options.corpusRoot);
    const candidates = {};
    let commonModel = null;
    for (const fighter of roster.fighters) {
        if (wanted && !wanted.has(fighter.key.toLowerCase())) continue;
        const loaded = loadFighter(acbcmRoot, fighter, versions);
        if (!loaded) {
            fighters.push({ character: fighter.key, version: null });
            continue;
        }
        const { model, version } = loaded;
        if (!commonModel) commonModel = { model, character: fighter.key, version };
        const curated = readJson(path.join(dataRoot, "exceptions", `${fighter.key}.json`), {});
        const generated = readJson(path.join(dataRoot, "generated_semantics", `${fighter.key}.json`), {});
        const withheld = new Set(ids(curated._generated_semantics && curated._generated_semantics.withhold));
        const display = readJson(path.join(dataRoot, "command_display", `${fighter.key}.json`), {});
        scoreCandidates(candidates, fighter.key, model, curated, generated, display, corpus);
        const entries = actionRules(curated);
        fighters.push({ character: fighter.key, version, entries: entries.length,
            keyed_groups: model.keyed_groups, frame_windows: model.frame_windows });
        for (const entry of entries) {
            for (const item of facetItems(entry, "character")) {
                items.push({
                    character: fighter.key, version, ...item,
                    signature: signatureOf(model, item),
                    in_ac: model.actions.has(item.id),
                    withheld: withheld.has(item.id)
                });
            }
        }
        for (const facet of ["force", "ignore"]) {
            const curatedIds = new Set(entries.filter(entry => entry.rule[facet] === true).map(entry => entry.id));
            const generatedIds = new Set(actionRules(generated).filter(entry => entry.rule[facet] === true).map(entry => entry.id));
            for (const [signature, bucket] of signatureCensus(model, "character", facet, curatedIds, generatedIds)) {
                const total = census[facet].get(signature) || { with: 0, without: 0 };
                total.with += bucket.with;
                total.without += bucket.without;
                census[facet].set(signature, total);
            }
        }
    }
    if (commonModel) {
        const common = readJson(path.join(dataRoot, "exceptions", "Common.json"), {});
        for (const entry of actionRules(common)) {
            for (const item of facetItems(entry, "common")) {
                items.push({
                    character: "Common", version: `${commonModel.version} (${commonModel.character})`, ...item,
                    signature: signatureOf(commonModel.model, item),
                    in_ac: commonModel.model.common.actions.has(item.id),
                    withheld: false
                });
            }
        }
    }
    const summary = {};
    for (const item of items) {
        if (!summary[item.facet]) summary[item.facet] = {};
        summary[item.facet][item.signature] = (summary[item.facet][item.signature] || 0) + 1;
    }
    const censusOut = {};
    for (const [facet, map] of Object.entries(census)) {
        censusOut[facet] = Object.fromEntries([...map.entries()].filter(([, bucket]) => bucket.with > 0)
            .sort((left, right) => right[1].with - left[1].with));
    }
    return {
        schema: "sf6cc.exception-derivation-audit.v1", versions, fighters, summary, census: censusOut,
        candidates: Object.values(candidates), corpus_files: Object.keys(corpus).length, items
    };
}

function markdown(result) {
    const lines = ["# 手写例外推导审计", "",
        `数据版本优先级：${result.versions.join(" → ")}。每个角色使用第一个存在的导出。`, "",
        "| 角色 | 导出版本 | 条目 | 触发组完整 | 帧窗口 |", "| --- | --- | ---: | --- | --- |"];
    for (const fighter of result.fighters) {
        lines.push(`| ${fighter.character} | ${fighter.version || "无导出"} | ${fighter.entries ?? ""} | `
            + `${fighter.keyed_groups ? "是" : "否"} | ${fighter.frame_windows ? "是" : "否"} |`);
    }
    lines.push("", "## 候选推导规则", "",
        "覆盖 = 规则能重现的手写条目；新增 = 规则会加到目前没有该规则的动作（或父子对）上；"
        + "语料中 = 这些新增动作在冻结录制里作为步骤出现过，迁移会改变已被实际使用的行为。", "",
        "| 规则 | 覆盖 | 新增 | 新增且出现在语料中 | 新增示例 |", "| --- | ---: | ---: | ---: | --- |");
    for (const score of result.candidates || []) {
        lines.push(`| ${score.rule} | ${score.covered} | ${score.added} | ${score.added_in_corpus} | `
            + `${(score.added <= 8 ? score.added_examples : score.corpus_examples).join(" ")} |`);
    }
    const facetCount = facet => Object.values(result.summary[facet] || {}).reduce((sum, count) => sum + count, 0);
    for (const facet of Object.keys(result.summary).sort((a, b) => facetCount(b) - facetCount(a))) {
        lines.push("", `## ${facet}（${facetCount(facet)}）`, "", "| 结构签名 | 条数 | 同签名但无此规则的动作 |", "| --- | ---: | ---: |");
        const census = result.census[facet] || {};
        for (const [signature, count] of Object.entries(result.summary[facet]).sort((a, b) => b[1] - a[1])) {
            const bucket = census[signature];
            lines.push(`| \`${signature}\` | ${count} | ${bucket ? bucket.without : ""} |`);
        }
    }
    return `${lines.join("\n")}\n`;
}

function run(argv) {
    const args = argsOf(argv);
    const result = audit({
        acbcmRoot: args["--acbcm-root"],
        versions: args["--versions"] ? args["--versions"].split(",").map(item => item.trim()).filter(Boolean) : null,
        corpusRoot: args["--corpus-root"],
        characters: args["--characters"] ? args["--characters"].split(",").map(item => item.trim()).filter(Boolean) : null
    });
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

module.exports = {
    ids, branchKind, kindSet, incomingSignature, pairSignature, facetItems, signatureOf,
    corpusIndex, scoreCandidates, audit, markdown
};
