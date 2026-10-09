"use strict";

const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const core = require("./generated_semantics_core.js");
const builder = require("./build_generated_semantics.js");

// Candidate rules from AC+BCM relations in a command table.
const commandDisplay = {
    _meta: {
        verified_alias_relations: [
            { source_action_id: 900, target_action_id: 902, branch_type: 29 },
            { source_action_id: 900, target_action_id: 901, branch_type: 29 },
            { source_action_id: 905, target_action_id: 905, branch_type: 29 }
        ],
        type63_strength_variant_relations: [{ source_action_id: 910, target_action_id: 911 }],
        type20_directional_relations: [{ source_action_id: 920, target_action_id: 921 }],
        type37_followup_execution_phase_relations: [{ source_action_id: 930, target_action_id: 931 }],
        suppressed_internal_transitions: [{ source_action_id: 940, target_action_id: 941 }],
        bcm_trigger_fingerprint: { algorithm: "x", count: 1, hash: "00000000" }
    }
};
const candidates = core.candidateRules(commandDisplay);
assert.deepStrictEqual([...candidates.keys()], ["900", "901", "902", "911", "921", "931"],
    "self relations and internal phases do not become exception rules");
assert.deepStrictEqual(candidates.get("900").rule, { absorb_ids: "901,902" });
assert.deepStrictEqual(candidates.get("901").rule, { force: true });
assert.deepStrictEqual(candidates.get("931").evidence.map(item => item.evidence), ["ac_type37_followup_execution_phase"]);

// A new fighter without curation gets every candidate; curated or withheld
// Actions are never emitted, so the two layers stay disjoint.
let built = core.buildDocument({ character: "Arjun", fighterId: 34, commandDisplay });
assert.deepStrictEqual(Object.keys(built.document).filter(key => /^\d+$/.test(key)), ["900", "901", "902", "911", "921", "931"]);
assert.deepStrictEqual(built.counts, { candidates: 6, generated: 6, curated: 0, withheld: 0 });
assert.strictEqual(built.document._meta.schema, core.SCHEMA);
assert.strictEqual(built.document._meta.bcm_trigger_fingerprint.hash, "00000000");
built = core.buildDocument({ character: "Test", fighterId: 99, commandDisplay, curation: {
    "901": { force: true, action_alias_ids: "902" },
    _generated_semantics: { withhold: [{ action: 911, reason: "test" }] }
} });
assert.deepStrictEqual(built.counts, { candidates: 6, generated: 4, curated: 1, withheld: 1 });
assert.ok(!("901" in built.document) && !("911" in built.document));
assert.ok(built.projections.every(item => item.character === "Test" && item.evidence.length > 0));

assert.ok(core.sameRule({ absorb_ids: "902,901" }, { absorb_ids: "901,902" }));
assert.ok(!core.sameRule({ absorb_ids: "901" }, { absorb_ids: "901", force: true }));

// Migration keeps every effective rule: equal curated entries move to the
// generated layer, any other candidate is withheld explicitly.
const root = fs.mkdtempSync(path.join(os.tmpdir(), "sf6cc-generated-semantics-"));
try {
    const data = path.join(root, "data");
    for (const directory of ["command_display", "exceptions", "generated_semantics"]) {
        fs.mkdirSync(path.join(data, directory), { recursive: true });
    }
    const roster = path.join(root, "fighters.json");
    fs.writeFileSync(roster, JSON.stringify({ schema: "sf6cc.fighter_roster.v1", fighters: [
        { id: 1, key: "Ryu", name_en: "Ryu", name_zh: "隆" }
    ] }));
    fs.writeFileSync(path.join(data, "command_display", "Ryu.json"), JSON.stringify(commandDisplay));
    const curation = {
        "900": { absorb_ids: "902,901" },
        "901": { force: true },
        "902": { force: true, is_holdable: true },
        "950": { ignore: true },
        _character: { allow_pending_absorb: true }
    };
    fs.writeFileSync(path.join(data, "exceptions", "Ryu.json"), JSON.stringify(curation));
    fs.writeFileSync(path.join(data, "generated_semantics", "Ryu.json"), JSON.stringify({ "960": { absorb_ids: "961" } }));
    fs.writeFileSync(path.join(data, "generated_semantics", "manifest.v1.json"), "{}");
    const before = builder.effectiveRules(curation, { "960": { absorb_ids: "961" } });

    const report = builder.migrateCuration({ dataRoot: data, rosterPath: roster, reason: "test" });
    assert.deepStrictEqual(report, [{ character: "Ryu", moved: 2, withheld: 4, curated_before: 4, curated_after: 3 }]);
    const curatedAfter = JSON.parse(fs.readFileSync(path.join(data, "exceptions", "Ryu.json"), "utf8"));
    const generatedAfter = JSON.parse(fs.readFileSync(path.join(data, "generated_semantics", "Ryu.json"), "utf8"));
    assert.deepStrictEqual(Object.keys(curatedAfter).filter(key => /^\d+$/.test(key)), ["902", "950", "960"],
        "differing and non-derivable curated rules stay; a dropped pilot rule becomes curated");
    assert.deepStrictEqual(curatedAfter._generated_semantics.withhold.map(item => item.action), [902, 911, 921, 931]);
    assert.deepStrictEqual(curatedAfter._character, { allow_pending_absorb: true });
    assert.deepStrictEqual(Object.keys(generatedAfter).filter(key => /^\d+$/.test(key)), ["900", "901"]);
    const after = builder.effectiveRules(curatedAfter, generatedAfter);
    assert.deepStrictEqual(Object.keys(after).sort(), Object.keys(before).sort());
    for (const key of Object.keys(before)) assert.ok(core.sameRule(before[key], after[key]), `Action ${key} changed`);
    assert.ok(!fs.existsSync(path.join(data, "generated_semantics", "manifest.v1.json")));
    assert.deepStrictEqual(builder.check({ dataRoot: data, rosterPath: roster }), []);
    fs.writeFileSync(path.join(data, "generated_semantics", "Ryu.json"), "{}\n");
    assert.deepStrictEqual(builder.check({ dataRoot: data, rosterPath: roster }), ["Ryu.json"]);
} finally {
    fs.rmSync(root, { recursive: true, force: true });
}

// Repository gate: the shipped generated rules equal what the generator
// derives from the shipped command tables and curated exceptions.
assert.deepStrictEqual(builder.check(), [],
    "generated_semantics is stale; run node tools/action_runtime_compiler/build_generated_semantics.js");
const shipped = JSON.parse(fs.readFileSync(path.resolve(__dirname,
    "../../data/TrainingComboTrials_data/generated_semantics/manifest.json"), "utf8"));
assert.strictEqual(shipped.schema, core.MANIFEST_SCHEMA);
assert.strictEqual(shipped.algorithm_version, core.ALGORITHM);

console.log("generated semantics tests passed");
