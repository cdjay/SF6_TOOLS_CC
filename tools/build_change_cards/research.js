"use strict";

const fs = require("fs"), path = require("path");
const audit = require("../action_runtime_compiler/build_change_report.js");
const bcm = require("../bcm_catalog_builder/bcm_catalog_core.js");
const models = require("../action_runtime_compiler/ac_model.js");

function references(ac) {
    const objects = audit.index(ac), full = audit.projection(objects, null), edges = [];
    for (const record of ac.records.filter(row => row.source_scope === "character")) {
        const keys = audit.keysFor(record.action_ref.object_id, objects, full);
        for (const [type, list] of Object.entries(keys)) for (const key of audit.scalarGraph(list)) {
            const f = key.fields || {};
            if (["CharacterAsset.BranchKey", "CharacterAsset.DynamicTriggerKey"].includes(type) && Number.isInteger(f.Action))
                edges.push({ source: record.native_action_id, target: f.Action, relation: "branch", type: f.Type,
                    start: f.StartFrame ?? null, end: f.EndFrame ?? null });
            else if (type === "CharacterAsset.ShotKey" && Number.isInteger(f.ActionId))
                edges.push({ source: record.native_action_id, target: f.ActionId, relation: "shot_action_reference",
                    start: f.StartFrame ?? null, end: f.EndFrame ?? null });
            else if (type === "CharacterAsset.LockKey" && f.Type === 1 && Number.isInteger(f.Param01))
                edges.push({ source: record.native_action_id, target: f.Param01, relation: "lock_type1_param01_reference_unapproved",
                    start: f.StartFrame ?? null, end: f.EndFrame ?? null });
        }
    }
    return edges;
}

function inputContexts(target, edges, web) {
    const reverse = new Map();
    for (const edge of edges) (reverse.get(edge.target) || reverse.set(edge.target, []).get(edge.target)).push(edge);
    const pending = [{ id: target, path: [] }], seen = new Set(), output = [];
    while (pending.length) {
        const current = pending.shift();
        if (seen.has(current.id) || current.path.length > 10) continue;
        seen.add(current.id);
        const command = web.actions[current.id];
        if (command?.classic?.display && command.classic.display !== "Normal") {
            const move = web.moves[command.move_id];
            output.push({ action_id: current.id, command: command.classic.display,
                move: move?.name ?? null, path: current.path, identity_approved: false });
        }
        for (const edge of reverse.get(current.id) || []) pending.push({ id: edge.source, path: [edge, ...current.path] });
    }
    return output;
}

function enrich(entry) {
    if (entry.new_character) return { character: entry.character, new_character: true };
    const read = file => bcm.parseSourceText(fs.readFileSync(file, "utf8"));
    const old = read(entry.sources.raw.before.ac), next = read(entry.sources.raw.after.ac);
    const oldBcm = read(entry.sources.raw.before.bcm), nextBcm = read(entry.sources.raw.after.bcm);
    const refreshed = audit.compareAc(old, next);
    const oldObjects = audit.index(old), nextObjects = audit.index(next);
    const allowed = audit.sharedVocabulary(old, next);
    const nextComparable = audit.projection(nextObjects, allowed), nextFull = audit.projection(nextObjects, null);
    const oldFull = audit.projection(oldObjects, null);
    const refs = references(next), model = models.buildModel(next, nextBcm);
    const result = { character: entry.character, identity_approved: false, ac: refreshed,
        bcm: audit.compareBcm(oldBcm, nextBcm), references: refs, contexts: [] };
    for (const change of refreshed.changes.filter(item => item.scope === "character")) {
        const record = next.records.find(r => JSON.stringify([r.source_scope, r.resource_index, r.style_index, r.native_action_id]) === change.locator);
        const previous = old.records.find(r => JSON.stringify([r.source_scope, r.resource_index, r.style_index, r.native_action_id]) === change.locator);
        const comparableKeys = record ? audit.scalarGraph(audit.keysFor(record.action_ref.object_id, nextObjects, nextComparable)) : {};
        const fullKeys = record ? audit.scalarGraph(audit.keysFor(record.action_ref.object_id, nextObjects, nextFull)) : {};
        const keyDetails = {};
        for (const [type, diff] of Object.entries(change.keys || {})) {
            const counts = new Map();
            for (const value of diff.added) {
                const encoded = JSON.stringify(value);
                counts.set(encoded, (counts.get(encoded) || 0) + 1);
            }
            const added = [];
            for (let i = 0; i < (comparableKeys[type] || []).length; i++) {
                const encoded = JSON.stringify(comparableKeys[type][i]), count = counts.get(encoded) || 0;
                if (count) { added.push(fullKeys[type][i]); counts.set(encoded, count - 1); }
            }
            keyDetails[type] = { added_full: added,
                before_full: previous ? audit.scalarGraph(audit.keysFor(previous.action_ref.object_id, oldObjects, oldFull)[type] || []) : [],
                note: "New frame windows are current-build evidence, not necessarily changed timing." };
        }
        result.contexts.push({ action_id: change.action_id, locator: change.locator,
            frame: model.actions.get(change.action_id)?.frame ?? null,
            input_contexts: inputContexts(change.action_id, refs, entry.current_web), key_details: keyDetails });
    }
    return result;
}

function run(input, output) {
    fs.mkdirSync(output, { recursive: true });
    for (const file of fs.readdirSync(input).filter(name => name.endsWith(".json"))) {
        const result = enrich(JSON.parse(fs.readFileSync(path.join(input, file), "utf8")));
        fs.writeFileSync(path.join(output, file), JSON.stringify(result, null, 2));
        console.log(`${result.character}: ${result.contexts?.length || 0} researched contexts`);
    }
}
if (require.main === module) run(path.resolve(process.argv[2]), path.resolve(process.argv[3]));
module.exports = { references, inputContexts, enrich };
