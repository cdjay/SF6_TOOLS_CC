#!/usr/bin/env node
"use strict";

// Builds data/TrainingComboTrials_data/generated_semantics from the deployed
// command tables (AC+BCM relations) and the curated exceptions.
//
//   node build_generated_semantics.js            write all fighters
//   node build_generated_semantics.js --check    compare only, exit 1 on drift
//   node build_generated_semantics.js --characters Arjun
//   node build_generated_semantics.js --migrate-curation
//       one-off convergence: hand-written entries equal to a generated rule
//       are removed, every other generated candidate is withheld, and the
//       effective rules the runtime loads are verified to stay identical.

const fs = require("fs");
const path = require("path");
const core = require("./generated_semantics_core.js");
const fighterRoster = require("../fighter_roster.js");

const DATA_ROOT = path.resolve(__dirname, "../../data/TrainingComboTrials_data");
const BOOLEAN_FLAGS = new Set(["--check", "--migrate-curation"]);

function argsOf(argv) {
    const result = {};
    for (let index = 0; index < argv.length; index += 1) {
        const key = argv[index];
        if (!key.startsWith("--")) throw new Error(`未知参数: ${key}`);
        if (BOOLEAN_FLAGS.has(key)) { result[key] = true; continue; }
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

function sameText(filename, text) {
    return fs.existsSync(filename)
        && fs.readFileSync(filename, "utf8").replace(/\r\n/g, "\n") === text;
}

function paths(dataRoot) {
    return {
        commandDisplay: key => path.join(dataRoot, "command_display", `${key}.json`),
        exceptions: key => path.join(dataRoot, "exceptions", `${key}.json`),
        generated: key => path.join(dataRoot, "generated_semantics", `${key}.json`),
        manifest: path.join(dataRoot, "generated_semantics", "manifest.json"),
        legacyManifest: path.join(dataRoot, "generated_semantics", "manifest.v1.json"),
    };
}

// Planned output for every rostered fighter that has a command table.
function plan(options = {}) {
    const dataRoot = path.resolve(options.dataRoot || DATA_ROOT);
    const files = paths(dataRoot);
    const roster = fighterRoster.loadRoster(options.rosterPath);
    const entries = [];
    for (const fighter of roster.fighters) {
        const commandFile = files.commandDisplay(fighter.key);
        if (!fs.existsSync(commandFile)) continue;
        const commandText = fs.readFileSync(commandFile, "utf8").replace(/\r\n/g, "\n");
        const built = core.buildDocument({
            character: fighter.key,
            fighterId: fighter.id,
            commandDisplay: JSON.parse(commandText),
            commandDisplaySha256: require("crypto").createHash("sha256").update(commandText, "utf8").digest("hex"),
            curation: readJsonIfExists(files.exceptions(fighter.key)) || {}
        });
        entries.push({
            character: fighter.key, file: `${fighter.key}.json`, target: files.generated(fighter.key),
            text: core.serialize(built.document), counts: built.counts, projections: built.projections
        });
    }
    const manifestText = core.serialize(core.buildManifest(entries));
    return { files, entries, manifestText };
}

function check(options = {}) {
    const planned = plan(options);
    const drift = planned.entries.filter(entry => !sameText(entry.target, entry.text)).map(entry => entry.file);
    if (!sameText(planned.files.manifest, planned.manifestText)) drift.push("manifest.json");
    if (fs.existsSync(planned.files.legacyManifest)) drift.push("manifest.v1.json (obsolete)");
    return drift;
}

function write(options = {}) {
    const planned = plan(options);
    fs.mkdirSync(path.dirname(planned.files.manifest), { recursive: true });
    const wanted = options.characters ? new Set(options.characters.map(name => name.toLowerCase())) : null;
    for (const entry of planned.entries) {
        if (wanted && !wanted.has(entry.character.toLowerCase())) continue;
        if (!sameText(entry.target, entry.text)) fs.writeFileSync(entry.target, entry.text, "utf8");
    }
    // The manifest always describes the full set.
    fs.writeFileSync(planned.files.manifest, planned.manifestText, "utf8");
    if (fs.existsSync(planned.files.legacyManifest)) fs.rmSync(planned.files.legacyManifest);
    return planned;
}

// Effective per-Action rules as CharacterRules.load_for_character builds
// them: numeric keys of the curated file, overlaid field by field with the
// generated file.
function effectiveRules(curation, generated) {
    const result = {};
    for (const [key, rule] of Object.entries(curation || {})) if (/^\d+$/.test(key)) result[key] = { ...rule };
    for (const [key, rule] of Object.entries(generated || {})) {
        if (!/^\d+$/.test(key)) continue;
        result[key] = { ...(result[key] || {}), ...rule };
    }
    return result;
}

function sameEffective(left, right) {
    const keys = new Set([...Object.keys(left), ...Object.keys(right)]);
    for (const key of keys) {
        const a = left[key], b = right[key];
        if (!a || !b || !core.sameRule(a, b)) return key;
    }
    return null;
}

function migrateCuration(options = {}) {
    const dataRoot = path.resolve(options.dataRoot || DATA_ROOT);
    const files = paths(dataRoot);
    const roster = fighterRoster.loadRoster(options.rosterPath);
    const reason = options.reason || "2026-10-09 迁移：保留现有判定行为，待实机验证后再改用生成规则";
    const report = [];
    for (const fighter of roster.fighters) {
        const commandFile = files.commandDisplay(fighter.key);
        if (!fs.existsSync(commandFile)) continue;
        const curationFile = files.exceptions(fighter.key);
        const curation = readJsonIfExists(curationFile) || {};
        const oldGenerated = readJsonIfExists(files.generated(fighter.key)) || {};
        const before = effectiveRules(curation, oldGenerated);
        const candidates = core.candidateRules(JSON.parse(fs.readFileSync(commandFile, "utf8")));
        const next = JSON.parse(JSON.stringify(curation));
        // Old generated Actions that the new algorithm does not reproduce
        // become curated so their behavior is kept.
        for (const [key, rule] of Object.entries(oldGenerated)) {
            if (!/^\d+$/.test(key)) continue;
            const candidate = candidates.get(key);
            if (!candidate || !core.sameRule(candidate.rule, before[key])) next[key] = before[key];
        }
        const withhold = [];
        let moved = 0;
        for (const [key, candidate] of candidates) {
            if (before[key] && core.sameRule(before[key], candidate.rule)) {
                if (Object.prototype.hasOwnProperty.call(next, key)) delete next[key];
                moved += 1;
                continue;
            }
            withhold.push({
                action: Number(key),
                generated: candidate.rule,
                curated: before[key] || null,
                reason
            });
        }
        if (withhold.length) {
            next._generated_semantics = { withhold: withhold.sort((left, right) => left.action - right.action) };
        } else {
            delete next._generated_semantics;
        }
        const built = core.buildDocument({ character: fighter.key, fighterId: fighter.id,
            commandDisplay: JSON.parse(fs.readFileSync(commandFile, "utf8")), curation: next });
        const after = effectiveRules(next, built.document);
        const mismatch = sameEffective(before, after);
        if (mismatch !== null) throw new Error(`${fighter.key} Action ${mismatch} 的有效规则在迁移后发生变化，已中止。`);
        if (JSON.stringify(next) !== JSON.stringify(curation)) {
            fs.writeFileSync(curationFile, core.serialize(next), "utf8");
        }
        report.push({ character: fighter.key, moved, withheld: withhold.length,
            curated_before: Object.keys(curation).filter(key => /^\d+$/.test(key)).length,
            curated_after: Object.keys(next).filter(key => /^\d+$/.test(key)).length });
    }
    write(options);
    return report;
}

function run(argv) {
    const args = argsOf(argv);
    const characters = args["--characters"]
        ? String(args["--characters"]).split(",").map(name => name.trim()).filter(Boolean) : null;
    if (args["--check"]) {
        const drift = check();
        for (const file of drift) console.log(`过期: ${file}`);
        console.log(drift.length ? `生成语义与指令表/例外不一致：${drift.length} 项` : "生成语义一致");
        if (drift.length) process.exitCode = 1;
        return;
    }
    if (args["--migrate-curation"]) {
        const report = migrateCuration();
        for (const row of report) {
            console.log(`${row.character}: 手写 ${row.curated_before}→${row.curated_after}，转为生成 ${row.moved}，保留差异 ${row.withheld}`);
        }
        return;
    }
    const planned = write({ characters });
    const total = planned.entries.reduce((sum, entry) => sum + entry.counts.generated, 0);
    console.log(`生成语义已写入：${planned.entries.length} 个角色，生成规则 ${total} 条。`);
}

if (require.main === module) {
    try {
        run(process.argv.slice(2));
    } catch (error) {
        console.error(`错误: ${error.message}`);
        process.exitCode = 2;
    }
}

module.exports = { plan, check, write, effectiveRules, migrateCuration, run };
