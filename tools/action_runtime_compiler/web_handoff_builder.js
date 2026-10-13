#!/usr/bin/env node
"use strict";

// Export transport data and evidence, never a second command resolver.
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const archive = require("./archive_builder.js");
const builder = require("./lastjson_builder.js");
const bcm = require("../bcm_catalog_builder/bcm_catalog_core.js");
const acModel = require("./ac_model.js");
const web = require("./web_character_core.js");
const roster = require("../fighter_roster.js");
const ROOT = path.resolve(__dirname, "../..");

function hash(bytes) { return crypto.createHash("sha256").update(bytes).digest("hex"); }
function read(file) { return bcm.parseSourceText(fs.readFileSync(file, "utf8")); }
function write(file, data) {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, `${JSON.stringify(data, null, 2)}\n`);
}
function directory(root, version) {
    const matches = builder.versionDirectories(root).filter(item => item.normalized === version);
    if (matches.length !== 1) throw new Error(`Missing or ambiguous version: ${version}`);
    return path.join(root, matches[0].name);
}
function stable(value) {
    if (Array.isArray(value)) return value.map(stable);
    if (!value || typeof value !== "object") return value;
    return Object.fromEntries(Object.keys(value).sort().map(key => [key, stable(value[key])]));
}
function deltas(before, after, prefix = "") {
    if (JSON.stringify(stable(before)) === JSON.stringify(stable(after))) return [];
    if (before && after && typeof before === "object" && typeof after === "object"
        && Array.isArray(before) === Array.isArray(after)) {
        return [...new Set([...Object.keys(before), ...Object.keys(after)])].sort().flatMap(key =>
            deltas(before[key], after[key], prefix ? `${prefix}.${key}` : key));
    }
    return [{ path: prefix, before_present: before !== undefined, after_present: after !== undefined,
        before: before ?? null, after: after ?? null }];
}

function nativeFacts(ac, source) {
    const objects = new Map((ac.objects || []).map(object => [object.object_id, object]));
    const actions = {};
    for (const record of ac.records || []) {
        const root = objects.get(record.action_ref?.object_id);
        if (!root) throw new Error(`Missing AC root: ${record.native_action_id}`);
        const locator = {
            source_scope: record.source_scope ?? null, resource_index: record.resource_index ?? null,
            style_index: record.style_index ?? null, action_id: record.native_action_id
        };
        const key = JSON.stringify(Object.values(locator));
        if (actions[key]) throw new Error(`Duplicate AC variant locator: ${key}`);
        const frame = (root.fields || []).find(field => field.name === "ActionFrame");
        const frameObject = objects.get(frame?.value?.object_id);
        const keys = {};
        const pending = [root.object_id], visited = new Set();
        while (pending.length) {
            const id = pending.pop();
            if (visited.has(id)) continue;
            visited.add(id);
            const object = objects.get(id);
            if (!object) throw new Error(`Unresolved AC reference: ${id}`);
            if (/^CharacterAsset\..*Key$/.test(object.object_type)) {
                (keys[object.object_type] ||= []).push(acModel.scalars(object));
            }
            const children = [...(object.fields || []), ...(object.items || [])]
                .filter(item => item.value?.kind === "ref").map(item => item.value.object_id);
            pending.push(...children.reverse());
        }
        actions[key] = { locator, fields: acModel.scalars(root),
            action_frame: acModel.scalars(frameObject), keys };
    }
    return { schema: "sf6cc.web-native-facts.v1", ...source,
        capabilities: { inherited_fields: ac.inherited_fields ?? null,
            dictionary_encoding: ac.dictionary_encoding ?? null },
        projection: "AC root/ActionFrame/key scalar fields; nested reference payloads remain in raw sources",
        actions };
}

function bcmFacts(source) {
    const catalog = bcm.buildCatalog(source);
    const objects = new Map(source.objects.map(object => [object.object_id, object]));
    const routes = {};
    for (const record of source.triggers) {
        const object = objects.get(record.trigger_ref?.object_id);
        if (!object) throw new Error(`Missing BCM trigger: ${record.trigger_index}`);
        const fields = acModel.scalars(object);
        const id = fields.action_id ?? record.native_action_id;
        const decoded = catalog.actions[String(id)]?.triggers.find(item => item.trigger_index === Number(record.trigger_index));
        if (!decoded) throw new Error(`Unresolved decoded BCM route: ${record.trigger_index}`);
        const key = `${id}:${record.trigger_index}`;
        if (routes[key]) throw new Error(`Duplicate BCM route: ${key}`);
        routes[key] = { action_id: id, trigger_index: record.trigger_index, fields,
            profiles: decoded.profiles, conditions: decoded.conditions };
    }
    return { routes, warnings: catalog.warnings, capabilities: {
        dictionary_encoding: source.dictionary_encoding ?? null, inherited_fields: source.inherited_fields ?? null } };
}

function compareNative(before, after) {
    const changes = [];
    for (const section of ["actions", "routes"]) {
        for (const key of [...new Set([...Object.keys(before?.[section] || {}), ...Object.keys(after[section])])].sort()) {
            const old = before?.[section]?.[key], current = after[section][key];
            const fields = deltas(old, current);
            if (!fields.length) continue;
            const capabilitiesDiffer = JSON.stringify(stable(before?.capabilities)) !== JSON.stringify(stable(after.capabilities));
            changes.push({ section, key, comparison_basis: "same_build_local_locator_candidate",
                identity_status: "not_verified", auto_approved: false,
                before_locator: old?.locator ?? (old ? { action_id: old.action_id, trigger_index: old.trigger_index } : null),
                after_locator: current?.locator ?? (current ? { action_id: current.action_id, trigger_index: current.trigger_index } : null),
                fields: fields.map(field => ({ ...field,
                    evidence_status: !field.before_present || !field.after_present
                        ? (capabilitiesDiffer ? "capture_availability_change" : "field_presence_change_unverified")
                        : "observed_snapshot_difference" })) });
        }
    }
    return changes;
}

function moveContent(move) {
    const { source_row_index, action_ids, command, ...content } = move;
    return content;
}
function compareWeb(before, after) {
    const moves = [], commands = [];
    for (const key of [...new Set([...Object.keys(before?.moves || {}), ...Object.keys(after.moves)])].sort()) {
        const old = before?.moves[key], current = after.moves[key];
        const comparable = !old || !current || (old.internal_name === current.internal_name && old.category === current.category);
        if (!comparable) {
            moves.push({ key, status: "ambiguous_row_pair", identity_status: "not_verified", auto_approved: false,
                before: old, after: current, fields: [] });
            continue;
        }
        const fields = deltas(old && moveContent(old), current && moveContent(current));
        if (fields.length) moves.push({ key, status: old ? (current ? "changed" : "removed") : "added",
            comparison_basis: "official_snapshot_row_candidate", identity_status: "not_verified", auto_approved: false,
            before_name: old?.name ?? null, after_name: current?.name ?? null, fields });
    }
    for (const id of [...new Set([...Object.keys(before?.actions || {}), ...Object.keys(after.actions)])].sort((a, b) => Number(a) - Number(b))) {
        const fields = deltas(before?.actions[id], after.actions[id]);
        if (fields.length) commands.push({ action_id: Number(id), identity_status: "not_verified", auto_approved: false, fields });
    }
    return { moves, commands };
}

function generate(options) {
    const oldVersion = builder.normalizeVersion(options.old), newVersion = builder.normalizeVersion(options.new);
    const supplemental = options.corroborate ? builder.normalizeVersion(options.corroborate) : null;
    const versions = [...new Set([oldVersion, supplemental, newVersion].filter(Boolean))];
    if (!(oldVersion < newVersion) || (supplemental && !(oldVersion < supplemental && supplemental < newVersion))) {
        throw new Error("Expected old < corroborate < new (or old < new)");
    }
    const output = path.resolve(options.output);
    if (fs.existsSync(output)) throw new Error(`Output already exists: ${output}`);
    fs.mkdirSync(output, { recursive: true });
    const acRoot = options.acRoot || path.join(__dirname, "acbcm");
    const offRoot = options.offRoot || path.join(__dirname, "off");
    const fighterRoster = roster.loadRoster(options.rosterPath);
    const inputs = [], snapshots = new Map();
    const copy = (source, relative) => {
        const target = path.join(output, relative);
        fs.mkdirSync(path.dirname(target), { recursive: true });
        fs.copyFileSync(source, target);
    };
    for (const version of versions) {
        const rawDir = directory(acRoot, version);
        const entries = new Map();
        const scan = archive.scanDumpDirectory(rawDir);
        if (scan.incomplete.length) throw new Error(`Unpaired raw inputs: ${version}`);
        for (const pair of scan.pairs) {
            const acPath = path.join(rawDir, pair.ac), bcmPath = path.join(rawDir, pair.bcm);
            const acBytes = fs.readFileSync(acPath), bcmBytes = fs.readFileSync(bcmPath);
            const ac = bcm.parseSourceText(acBytes.toString("utf8")), bcmSource = bcm.parseSourceText(bcmBytes.toString("utf8"));
            const acHash = hash(acBytes), bcmHash = hash(bcmBytes);
            const fighterId = Number(ac.fighter_id), fighter = fighterRoster.byId(fighterId);
            if (!fighter || Number(bcmSource.fighter_id) !== fighterId || builder.filenameFighterId(pair.stem) !== fighterId) {
                throw new Error(`Fighter ID mismatch: ${pair.stem}`);
            }
            if (entries.has(fighterId)) throw new Error(`Duplicate fighter: ${fighterId}`);
            for (const source of [ac, bcmSource]) if (source.truncated || source.hard_gate_passed === false) throw new Error(`Incomplete input: ${pair.stem}`);
            inputs.push({ version, character: fighter.key, fighter_id: fighterId,
                ac: { path: acPath, bytes: acBytes.length, sha256: acHash },
                bcm: { path: bcmPath, bytes: bcmBytes.length, sha256: bcmHash } });
            const native = nativeFacts(ac, { version, character: fighter.key, fighter_id: fighterId });
            const routes = bcmFacts(bcmSource);
            native.routes = routes.routes;
            native.capabilities.bcm = routes.capabilities;
            native.bcm_warnings = routes.warnings;
            const nativePath = path.join(output, "native", version, `${fighter.key}.json`);
            write(nativePath, native);
            let characterWeb = null;
            const webPath = path.join(rawDir, "lastjson_web", `${fighter.key}.json`);
            if (fs.existsSync(webPath)) {
                characterWeb = read(webPath);
                const commandPath = path.join(rawDir, "lastjson", `${fighter.key}.json`);
                const command = read(commandPath);
                web.validateWebCharacter(characterWeb, command);
                if (command._meta.ac_sha256 !== acHash || command._meta.bcm_sha256 !== bcmHash) {
                    throw new Error(`Compiled/raw source hash mismatch: ${fighter.key}`);
                }
                if (characterWeb._meta.generated_at.slice(0, 10) !== version) throw new Error(`Web version mismatch: ${fighter.key}`);
                if (characterWeb._meta.command_source_sha256 !== hash(fs.readFileSync(commandPath))) throw new Error(`Command hash mismatch: ${fighter.key}`);
                const officialPath = path.join(directory(offRoot, version), `${fighter.key}.official.generated.json`);
                if (characterWeb._meta.frame_source_sha256 !== hash(fs.readFileSync(officialPath))) throw new Error(`OFF hash mismatch: ${fighter.key}`);
                copy(webPath, `characters/${version}/${fighter.key}.json`);
                copy(commandPath, `commands/${version}/${fighter.key}.json`);
                copy(officialPath, `official/${version}/${fighter.key}.json`);
            } else if (version !== supplemental) throw new Error(`Missing web output: ${webPath}`);
            entries.set(fighterId, { character: fighter.key, nativePath, web: characterWeb });
            console.log(`[${version}] ${fighter.key}`);
        }
        snapshots.set(version, entries);
    }
    const current = snapshots.get(newVersion);
    if (current.size !== fighterRoster.fighters.length) throw new Error("Current roster incomplete");
    const summaries = [];
    for (const baseline of [oldVersion, supplemental].filter(Boolean)) {
        const previous = snapshots.get(baseline);
        for (const id of [...new Set([...previous.keys(), ...current.keys()])].sort((a, b) => a - b)) {
            const old = previous.get(id), next = current.get(id);
            if (!next) throw new Error(`Current build missing historical fighter: ${id}`);
            const diff = { schema: "sf6cc.web-version-diff.v1", old_version: baseline, new_version: newVersion,
                fighter_id: id, character: next.character, new_character: !old,
                native: compareNative(old && read(old.nativePath), read(next.nativePath)),
                web: next.web && baseline === oldVersion ? compareWeb(old?.web, next.web) : null };
            write(path.join(output, "differences", `${baseline}_to_${newVersion}`, `${next.character}.json`), diff);
            summaries.push({ old_version: baseline, character: next.character, fighter_id: id,
                new_character: !old, native_changed_locators: diff.native.length,
                native_observed_value_changed_locators: diff.native.filter(change => change.fields.some(field =>
                    field.before_present && field.after_present)).length,
                native_presence_only_changed_locators: diff.native.filter(change => change.fields.every(field =>
                    !field.before_present || !field.after_present)).length,
                official_changed_rows: diff.web?.moves.length ?? null, command_changed_locators: diff.web?.commands.length ?? null });
        }
    }
    for (const asset of Object.values(web.ICON_ASSETS)) copy(path.join(ROOT, "images/buttonsAndArrows", asset), `icons/${asset}`);
    copy(options.rosterPath || roster.ROSTER_PATH, "fighters.json");
    for (const name of ["web_character_schema.md", "command_display_schema.md", "AC_BCM_SEMANTIC_CORE.md", "WEB_DATA_HANDOFF.md"]) {
        copy(path.join(ROOT, "docs", name), `contracts/${name}`);
    }
    fs.writeFileSync(path.join(output, "SF6CMFF_PROMPT.md"),
        fs.readFileSync(path.join(__dirname, "web_handoff_prompt.md"), "utf8")
            .replaceAll("{{BUNDLE}}", output).replaceAll("{{OLD}}", oldVersion).replaceAll("{{NEW}}", newVersion));
    write(path.join(output, "sources.json"), { schema: "sf6cc.web-handoff-sources.v1", raw_files_copied: false, inputs });
    write(path.join(output, "differences/index.json"), { schema: "sf6cc.web-version-diff-index.v1", summaries });
    const files = [];
    function inventory(dir) {
        for (const item of fs.readdirSync(dir, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
            const file = path.join(dir, item.name);
            if (item.isDirectory()) inventory(file);
            else { const bytes = fs.readFileSync(file); files.push({ path: path.relative(output, file).split(path.sep).join("/"), bytes: bytes.length, sha256: hash(bytes) }); }
        }
    }
    inventory(output);
    write(path.join(output, "manifest.json"), { schema: "sf6cc.web-handoff.v1", old_version: oldVersion,
        new_version: newVersion, supplemental_version: supplemental, character_count: current.size,
        raw_inputs: "sources.json", difference_index: "differences/index.json", files,
        limitations: ["Same Action ID or official row key is a comparison candidate, never approved cross-build identity.",
            "AC scalar projection is not exhaustive; nested payloads require the original raw files.",
            "Native structural frames are not official startup/active/recovery/on-block/on-hit.",
            "Missing exporter fields are not zero and are not automatically gameplay changes."] });
    return { output, character_count: current.size, files: files.length, summaries };
}

if (require.main === module) {
    try {
        const args = builder.argsOf(process.argv.slice(2));
        if (!args["--old"] || !args["--new"] || !args["--output"]) throw new Error("Required: --old --new --output");
        const result = generate({ old: args["--old"], new: args["--new"], corroborate: args["--corroborate"],
            output: args["--output"], acRoot: args["--acbcm-root"], offRoot: args["--off-root"] });
        console.log(JSON.stringify({ output: result.output, character_count: result.character_count, files: result.files }));
    } catch (error) { console.error(error.stack); process.exitCode = 1; }
}
module.exports = { nativeFacts, bcmFacts, deltas, compareNative, compareWeb, generate };
