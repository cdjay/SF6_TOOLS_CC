"use strict";

// Projects AC+BCM relations of a generated command table onto the
// exception-shaped detection rules the runtime already reads
// (CharacterRules: absorb_ids, force). A new fighter gets these rules with no
// hand curation; existing hand-written rules converge onto generated data.
//
// Ownership is per Action: an Action is either generated or hand-written,
// never both. Curation can withhold a generated Action explicitly
// (exceptions/<key>.json "_generated_semantics.withhold"); every withheld
// Action is a measurable disagreement between AC+BCM and curated behavior.

const crypto = require("crypto");

const SCHEMA = "sf6cc.generated-character-semantics.v2";
const MANIFEST_SCHEMA = "sf6cc.generated-character-semantics-manifest.v2";
const ALGORITHM = "sf6cc-acbcm-exception-projection.v1";

// Relation kinds (command_display _meta) and the rule fields they imply.
// Agreement with curated data on 2026-08-03: Type 29 aliases 89/122 owners
// absorb their variant and 111/122 variants are forced; the other kinds
// matched curated force in every case.
const RELATIONS = Object.freeze([
    { kind: "verified_alias_relations", evidence: "ac_type29_verified_alias", absorb: true, force: true },
    { kind: "type63_strength_variant_relations", evidence: "ac_type63_strength_variant", force: true },
    { kind: "type20_directional_relations", evidence: "ac_type20_directional_variant", force: true },
    { kind: "type37_followup_execution_phase_relations", evidence: "ac_type37_followup_execution_phase", force: true },
]);

const numericKey = key => /^\d+$/.test(String(key));

function idSet(value) {
    if (value === undefined || value === null) return new Set();
    const items = Array.isArray(value) ? value : String(value).split(",");
    return new Set(items.map(item => Number(String(item).trim())).filter(Number.isInteger));
}

function formatIds(ids) {
    return [...ids].sort((left, right) => left - right).join(",");
}

// Candidate rules keyed by Action ID string: { rule, evidence[] }.
function candidateRules(commandDisplay) {
    const meta = commandDisplay && commandDisplay._meta || {};
    const absorb = new Map();
    const force = new Set();
    const evidence = new Map();
    const note = (actionId, item) => {
        const key = String(actionId);
        if (!evidence.has(key)) evidence.set(key, []);
        evidence.get(key).push(item);
    };
    for (const relation of RELATIONS) {
        for (const record of Array.isArray(meta[relation.kind]) ? meta[relation.kind] : []) {
            const source = Number(record && record.source_action_id);
            const target = Number(record && record.target_action_id);
            if (!Number.isInteger(source) || !Number.isInteger(target) || source === target) continue;
            const item = { kind: relation.kind, evidence: relation.evidence, source_action_id: source, target_action_id: target };
            if (relation.absorb) {
                if (!absorb.has(source)) absorb.set(source, new Set());
                absorb.get(source).add(target);
                note(source, { ...item, field: "absorb_ids" });
            }
            if (relation.force) {
                force.add(target);
                note(target, { ...item, field: "force" });
            }
        }
    }
    const rules = new Map();
    for (const [owner, targets] of absorb) rules.set(String(owner), { absorb_ids: formatIds(targets) });
    for (const target of force) {
        const key = String(target);
        rules.set(key, { ...(rules.get(key) || {}), force: true });
    }
    const result = new Map();
    for (const key of [...rules.keys()].sort((left, right) => Number(left) - Number(right))) {
        const rule = rules.get(key);
        const ordered = {};
        if (rule.absorb_ids !== undefined) ordered.absorb_ids = rule.absorb_ids;
        if (rule.force !== undefined) ordered.force = rule.force;
        result.set(key, { rule: ordered, evidence: evidence.get(key) || [] });
    }
    return result;
}

function withheldActions(curation) {
    const list = curation && curation._generated_semantics && curation._generated_semantics.withhold;
    return new Set((Array.isArray(list) ? list : []).map(item => String(item && item.action)));
}

// Rule equality as the runtime reads it: id lists compare as sets.
function sameRule(left, right) {
    if (!left || !right) return false;
    const fields = new Set([...Object.keys(left), ...Object.keys(right)]);
    for (const field of fields) {
        if (field === "absorb_ids") {
            const a = idSet(left[field]), b = idSet(right[field]);
            if (a.size !== b.size || [...a].some(id => !b.has(id))) return false;
        } else if (JSON.stringify(left[field]) !== JSON.stringify(right[field])) {
            return false;
        }
    }
    return true;
}

// The generated document for one fighter. Actions that curation defines or
// withholds are not emitted.
function buildDocument(options) {
    const curation = options.curation || {};
    const withheld = withheldActions(curation);
    const candidates = candidateRules(options.commandDisplay);
    const document = {};
    const projections = [];
    const counts = { candidates: candidates.size, generated: 0, curated: 0, withheld: 0 };
    for (const [key, candidate] of candidates) {
        if (withheld.has(key)) { counts.withheld += 1; continue; }
        if (Object.prototype.hasOwnProperty.call(curation, key)) { counts.curated += 1; continue; }
        document[key] = candidate.rule;
        projections.push({
            character: options.character,
            owner_action_id: Number(key),
            fields: Object.keys(candidate.rule),
            evidence: candidate.evidence
        });
        counts.generated += 1;
    }
    document._meta = {
        schema: SCHEMA,
        algorithm: ALGORITHM,
        character: options.character,
        fighter_id: options.fighterId,
        source_command_display_sha256: options.commandDisplaySha256 || null,
        bcm_trigger_fingerprint: options.commandDisplay && options.commandDisplay._meta
            && options.commandDisplay._meta.bcm_trigger_fingerprint || null,
        counts
    };
    return { document, projections, counts };
}

function serialize(value) {
    return `${JSON.stringify(value, null, 2)}\n`;
}

function sha256(text) {
    return crypto.createHash("sha256").update(Buffer.from(text, "utf8")).digest("hex");
}

function buildManifest(entries) {
    const sorted = [...entries].sort((left, right) => left.file.localeCompare(right.file));
    return {
        schema: MANIFEST_SCHEMA,
        algorithm_version: ALGORITHM,
        relations: RELATIONS.map(relation => ({
            kind: relation.kind, evidence: relation.evidence,
            fields: [relation.absorb ? "absorb_ids" : null, relation.force ? "force" : null].filter(Boolean)
        })),
        artifacts: sorted.map(entry => ({ file: entry.file, bytes: Buffer.byteLength(entry.text, "utf8"), sha256: sha256(entry.text) })),
        characters: sorted.map(entry => ({ character: entry.character, ...entry.counts })),
        projections: sorted.flatMap(entry => entry.projections)
    };
}

module.exports = {
    SCHEMA, MANIFEST_SCHEMA, ALGORITHM, RELATIONS,
    idSet, formatIds, candidateRules, withheldActions, sameRule, buildDocument, buildManifest, serialize
};
