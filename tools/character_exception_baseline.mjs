import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";

const ROOT = process.cwd();
const DATA_ROOT = path.join(ROOT, "data", "TrainingComboTrials_data");
const EXCEPTION_DIR = path.join(DATA_ROOT, "exceptions");
const GENERATED_DIR = path.join(DATA_ROOT, "generated_semantics");
const PRESENTATION_DIR = path.join(DATA_ROOT, "command_display_overrides");
const COMPATIBILITY_DIR = path.join(DATA_ROOT, "action_compatibility");
const BASELINE_FILE = path.join(ROOT, "tests", "fixtures", "character_exception_baseline.json");
const ORACLE_FILE = path.join(ROOT, "tests", "fixtures", "character_exception_legacy_oracle.json");
const REPORT_FILE = path.join(ROOT, "docs", "audits", "CHARACTER_EXCEPTION_BASELINE.md");
const SEALED_BASELINE_SHA256 = "96a0a563e01477992f9931bfc469ef57286b22220e2ca8e4615f8b35c3b4ca49";
const SEALED_ORACLE_SHA256 = "f50d4e5253175d15582342b4e5318c3cd2191f9526aeea97470de732a265cc0b";

const FIGHTER_IDS = {
  Ryu: 1, Luke: 2, Kimberly: 3, ChunLi: 4, Manon: 5, Zangief: 6,
  JP: 7, Dhalsim: 8, Cammy: 9, Ken: 10, DeeJay: 11, Lily: 12,
  AKI: 13, Rashid: 14, Blanka: 15, Juri: 16, Marisa: 17, Guile: 18,
  Ed: 19, EHonda: 20, Jamie: 21, Akuma: 22, Sagat: 25, MBison: 26,
  Terry: 27, Mai: 28, Elena: 29, CViper: 30, Alex: 31, Ingrid: 32,
  Yasmine: 33
};

const FIELD_METADATA = {
  absorb_ids: { categories: ["A_AC_BCM_SEMANTIC"], meaning: "owner absorbs related Action outcomes", consumers: ["ActionMatcher", "PendingAbsorb", "CharacterRules"] },
  optional_parent_ids: { categories: ["A_AC_BCM_SEMANTIC"], meaning: "optional predecessor/follow-up relation", consumers: ["ActionMatcher"] },
  optional_parent_motions: { categories: ["B_INPUT_COMMAND_SEMANTIC"], meaning: "motion-guarded optional predecessor relation", consumers: ["ActionMatcher"] },
  follow_up_motion: { categories: ["B_INPUT_COMMAND_SEMANTIC"], meaning: "follow-up command identity", consumers: ["ActionMatcher", "CommandResolver"] },
  action_alias_ids: { categories: ["A_AC_BCM_SEMANTIC"], meaning: "Action alias equivalence", consumers: ["ActionMatcher"] },
  action_alias_combo_deltas: { categories: ["A_AC_BCM_SEMANTIC", "C_RUNTIME_MECHANISM"], meaning: "alias-specific combo-count adjustment", consumers: ["ActionMatcher"] },
  action_event_projection: { categories: ["A_AC_BCM_SEMANTIC", "B_INPUT_COMMAND_SEMANTIC"], meaning: "Action-event owner/internal/input-anchor projection", consumers: ["ActionEventCompiler", "ActionMatcher", "CharacterRules"] },
  action_event_rules: { categories: ["C_RUNTIME_MECHANISM"], meaning: "runtime event suppression or preservation policy", consumers: ["ActionEventCompiler", "ActionMatcher"] },
  force: { categories: ["C_RUNTIME_MECHANISM"], meaning: "force Action participation in Legacy matching/recording", consumers: ["ActionMatcher", "Recorder"] },
  ignore: { categories: ["C_RUNTIME_MECHANISM"], meaning: "ignore Action in Legacy matching", consumers: ["ActionMatcher"] },
  is_holdable: { categories: ["B_INPUT_COMMAND_SEMANTIC", "C_RUNTIME_MECHANISM"], meaning: "holdable command/runtime window", consumers: ["ActionMatcher", "Recorder", "UI"] },
  hold_partial_check: { categories: ["C_RUNTIME_MECHANISM"], meaning: "partial hold validation", consumers: ["ActionMatcher"] },
  charge_min: { categories: ["B_INPUT_COMMAND_SEMANTIC", "C_RUNTIME_MECHANISM"], meaning: "minimum charge/hold timing", consumers: ["ActionMatcher", "Recorder", "UI"] },
  charge_max: { categories: ["B_INPUT_COMMAND_SEMANTIC", "C_RUNTIME_MECHANISM"], meaning: "maximum charge/hold timing", consumers: ["ActionMatcher", "Recorder", "UI"] },
  perfect_min: { categories: ["C_RUNTIME_MECHANISM"], meaning: "perfect timing lower bound", consumers: ["ActionMatcher", "UI"] },
  perfect_max: { categories: ["C_RUNTIME_MECHANISM"], meaning: "perfect timing upper bound", consumers: ["ActionMatcher", "UI"] },
  ignore_prev_id: { categories: ["C_RUNTIME_MECHANISM"], meaning: "previous Action timing exception", consumers: ["ActionMatcher"] },
  ignore_prev_frames: { categories: ["C_RUNTIME_MECHANISM"], meaning: "previous Action frame window", consumers: ["ActionMatcher"] },
  finish_on_first_hit: { categories: ["C_RUNTIME_MECHANISM"], meaning: "completion behavior on first hit", consumers: ["ActionMatcher"] },
  runtime_force_after_ids: { categories: ["C_RUNTIME_MECHANISM"], meaning: "runtime force-after relation", consumers: ["ActionMatcher"] },
  action_required: { categories: ["C_RUNTIME_MECHANISM"], meaning: "Action must be observed", consumers: ["ActionMatcher"] },
  absorb_requires_combo: { categories: ["C_RUNTIME_MECHANISM"], meaning: "absorb confirmation combo requirement", consumers: ["ActionMatcher"] },
  record_absorb_as_parent: { categories: ["C_RUNTIME_MECHANISM"], meaning: "record absorbed Action as parent", consumers: ["Recorder", "CharacterRules"] },
  preserve_short_action: { categories: ["C_RUNTIME_MECHANISM"], meaning: "preserve short-lived Action", consumers: ["ActionEventCompiler"] }
};

function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonical(value[key])]));
  }
  return value;
}

function jsonText(value) {
  return `${JSON.stringify(canonical(value), null, 2)}\n`;
}

function sha256(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

function normalizedTextSha256(value) {
  return sha256(value.toString("utf8").replaceAll("\r\n", "\n"));
}

function relative(filename) {
  return path.relative(ROOT, filename).replaceAll("\\", "/");
}

function jsonFiles(directory, exclude = new Set()) {
  return fs.readdirSync(directory)
    .filter((name) => name.endsWith(".json") && !exclude.has(name))
    .sort()
    .map((name) => path.join(directory, name));
}

function lineOf(raw, pattern) {
  const index = raw.search(pattern);
  return index < 0 ? null : raw.slice(0, index).split("\n").length;
}

function numericList(value) {
  if (typeof value === "string") {
    return [...new Set(value.split(",").map((item) => Number(item.trim())).filter(Number.isSafeInteger))].sort((a, b) => a - b);
  }
  if (Array.isArray(value)) return [...new Set(value.map(Number).filter(Number.isSafeInteger))].sort((a, b) => a - b);
  return [];
}

function effectsFor(rule) {
  const fields = Object.keys(rule);
  const metadata = fields.map((field) => FIELD_METADATA[field]).filter(Boolean);
  const categories = [...new Set(metadata.flatMap((item) => item.categories))].sort();
  if (categories.length === 0) categories.push("F_UNKNOWN");
  return {
    categories,
    semantic_meaning: [...new Set(metadata.map((item) => item.meaning))].sort(),
    runtime_consumers: [...new Set(metadata.flatMap((item) => item.consumers))].sort(),
    presentation_effect: fields.some((field) => ["follow_up_motion", "is_holdable", "charge_min", "charge_max", "perfect_min", "perfect_max"].includes(field)),
    detector_effect: metadata.some((item) => item.consumers.includes("ActionMatcher")),
    recorder_effect: metadata.some((item) => item.consumers.includes("Recorder") || item.consumers.includes("ActionEventCompiler")),
    compatibility_effect: false
  };
}

function oracleForAction(character, actionId, rule) {
  const projection = rule.action_event_projection && rule.absorb_ids
    ? Object.fromEntries(numericList(rule.absorb_ids).map((child) => [String(child), {
        owner_id: actionId,
        kind: numericList(rule.action_event_projection.canonical_owner_ids).includes(child) ? "canonical_owner" : "internal_phase"
      }]))
    : {};
  return canonical({
    character,
    action_id: actionId,
    effective_rule: rule,
    normalized: {
      absorb_ids: numericList(rule.absorb_ids),
      alias_ids: numericList(rule.action_alias_ids),
      optional_parent_ids: numericList(rule.optional_parent_ids),
      runtime_force_after_ids: numericList(rule.runtime_force_after_ids),
      action_required: rule.action_required === true || rule.no_combo_auto_advance === true || rule.require_absorb === true,
      force: rule.force === true,
      ignore: rule.ignore === true,
      action_event_projection: projection
    }
  });
}

function sourceDescriptor(filename, raw) {
  return { file: relative(filename), sha256: sha256(raw), bytes: Buffer.byteLength(raw) };
}

function build() {
  const records = [];
  const oracleCases = [];
  const sources = [];

  for (const filename of jsonFiles(EXCEPTION_DIR)) {
    const raw = fs.readFileSync(filename, "utf8");
    const document = JSON.parse(raw);
    const character = path.basename(filename, ".json");
    sources.push(sourceDescriptor(filename, raw));
    for (const key of Object.keys(document).sort((a, b) => a.localeCompare(b, undefined, { numeric: true }))) {
      const rule = document[key];
      if (key === "_character") {
        records.push({
          record_uid: `policy:${character}`,
          source_kind: "legacy_character_policy",
          legacy_runtime_loaded: true,
          character,
          fighter_id: FIGHTER_IDS[character] ?? null,
          action_ids: [],
          source_file: relative(filename),
          source_location: "/_character",
          source_line: lineOf(raw, /^\s*"_character"\s*:/m),
          rule_category: ["B_INPUT_COMMAND_SEMANTIC", "C_RUNTIME_MECHANISM"],
          raw_legacy_rule: rule,
          semantic_meaning: ["character-scoped transcription or sequence policy"],
          runtime_consumer: ["CharacterRules", "Transcriber", "SequenceGrouping"],
          expected_normalized_result: canonical(rule),
          presentation_effect: false,
          detector_effect: true,
          recorder_effect: true,
          compatibility_effect: false,
          known_reason_comment: null,
          ac_provenance: null,
          bcm_provenance: null,
          provenance_status: "unresolved"
        });
        oracleCases.push({
          case_uid: `oracle:policy:${character}`,
          source_kind: "legacy_character_policy",
          character,
          action_id: null,
          effective_rule: canonical(rule)
        });
        continue;
      }
      const actionId = Number(key);
      const effects = effectsFor(rule);
      records.push({
        record_uid: `action:${character}:${key}`,
        source_kind: "legacy_action_exception",
        legacy_runtime_loaded: true,
        character,
        fighter_id: FIGHTER_IDS[character] ?? null,
        action_ids: Number.isSafeInteger(actionId) ? [actionId] : [],
        source_file: relative(filename),
        source_location: `/${key}`,
        source_line: lineOf(raw, new RegExp(`^\\s*"${key}"\\s*:`, "m")),
        rule_category: effects.categories,
        raw_legacy_rule: rule,
        semantic_meaning: effects.semantic_meaning,
        runtime_consumer: effects.runtime_consumers,
        expected_normalized_result: oracleForAction(character, actionId, rule).normalized,
        presentation_effect: effects.presentation_effect,
        detector_effect: effects.detector_effect,
        recorder_effect: effects.recorder_effect,
        compatibility_effect: false,
        known_reason_comment: null,
        ac_provenance: null,
        bcm_provenance: null,
        provenance_status: "unresolved"
      });
      oracleCases.push({ case_uid: `oracle:action:${character}:${key}`, source_kind: "legacy_action_exception", ...oracleForAction(character, actionId, rule) });
    }
  }

  const generatedManifestFile = path.join(GENERATED_DIR, "manifest.v1.json");
  const generatedManifest = JSON.parse(fs.readFileSync(generatedManifestFile, "utf8"));
  sources.push(sourceDescriptor(generatedManifestFile, fs.readFileSync(generatedManifestFile, "utf8")));
  for (const filename of jsonFiles(GENERATED_DIR, new Set(["manifest.v1.json"]))) {
    const raw = fs.readFileSync(filename, "utf8");
    const document = JSON.parse(raw);
    const character = path.basename(filename, ".json");
    sources.push(sourceDescriptor(filename, raw));
    for (const key of Object.keys(document).sort((a, b) => Number(a) - Number(b))) {
      const actionId = Number(key);
      const rule = document[key];
      const evidence = generatedManifest.projections.find((row) => row.character === character && row.owner_action_id === actionId) ?? null;
      const effects = effectsFor(rule);
      records.push({
        record_uid: `action:${character}:${key}`,
        source_kind: "migrated_pilot_exception",
        legacy_runtime_loaded: false,
        character,
        fighter_id: FIGHTER_IDS[character] ?? null,
        action_ids: [actionId],
        source_file: relative(filename),
        source_location: `/${key}`,
        source_line: lineOf(raw, new RegExp(`^\\s*"${key}"\\s*:`, "m")),
        historical_legacy_source: `data/TrainingComboTrials_data/exceptions/${character}.json#/${key}`,
        rule_category: effects.categories,
        raw_legacy_rule: rule,
        semantic_meaning: effects.semantic_meaning,
        runtime_consumer: effects.runtime_consumers,
        expected_normalized_result: oracleForAction(character, actionId, rule).normalized,
        presentation_effect: effects.presentation_effect,
        detector_effect: effects.detector_effect,
        recorder_effect: effects.recorder_effect,
        compatibility_effect: false,
        known_reason_comment: "Migrated by the Character Exception Convergence Pilot",
        ac_provenance: evidence ? { move_uid: evidence.move_uid, relationship_uids: evidence.relationship_uids } : null,
        bcm_provenance: evidence ? { owner_action_id: evidence.owner_action_id, replacement_action_ids: evidence.replacement_action_ids } : null,
        provenance_status: evidence ? "verified_generated" : "unresolved"
      });
      oracleCases.push({ case_uid: `oracle:action:${character}:${key}`, source_kind: "migrated_pilot_exception", ...oracleForAction(character, actionId, rule) });
    }
  }

  for (const filename of jsonFiles(PRESENTATION_DIR)) {
    const raw = fs.readFileSync(filename, "utf8");
    const document = JSON.parse(raw);
    const character = document.character ?? path.basename(filename, ".json");
    sources.push(sourceDescriptor(filename, raw));
    for (const key of Object.keys(document.entries ?? {}).sort((a, b) => Number(a) - Number(b))) {
      const rule = document.entries[key];
      records.push({
        record_uid: `presentation:${character}:${key}`,
        source_kind: "presentation_override",
        legacy_runtime_loaded: false,
        character,
        fighter_id: FIGHTER_IDS[character] ?? null,
        action_ids: [Number(key)],
        source_file: relative(filename),
        source_location: `/entries/${key}`,
        source_line: lineOf(raw, new RegExp(`^\\s*"${key}"\\s*:`, "m")),
        rule_category: ["D_PRESENTATION"],
        raw_legacy_rule: rule,
        semantic_meaning: ["presentation-only command override"],
        runtime_consumer: ["CommandDisplayOverrides", "CommandResolver"],
        expected_normalized_result: canonical(rule),
        presentation_effect: true,
        detector_effect: false,
        recorder_effect: false,
        compatibility_effect: false,
        known_reason_comment: rule.evidence ?? null,
        ac_provenance: null,
        bcm_provenance: null,
        provenance_status: rule.evidence ? "runtime_evidence_recorded" : "unresolved"
      });
      oracleCases.push({ case_uid: `oracle:presentation:${character}:${key}`, source_kind: "presentation_override", character, action_id: Number(key), effective_rule: canonical(rule) });
    }
  }

  for (const filename of jsonFiles(COMPATIBILITY_DIR)) {
    const raw = fs.readFileSync(filename, "utf8");
    const document = JSON.parse(raw);
    const character = document.character ?? path.basename(filename, ".json");
    sources.push(sourceDescriptor(filename, raw));
    for (let index = 0; index < (document.entries ?? []).length; index += 1) {
      const rule = document.entries[index];
      records.push({
        record_uid: `compatibility:${character}:${index}`,
        source_kind: "historical_compatibility",
        legacy_runtime_loaded: false,
        character,
        fighter_id: FIGHTER_IDS[character] ?? null,
        action_ids: [rule.recorded_action_id, rule.runtime_action_id, ...(rule.runtime_action_alias_ids ?? [])],
        source_file: relative(filename),
        source_location: `/entries/${index}`,
        source_line: lineOf(raw, new RegExp(`"recorded_action_id"\\s*:\\s*${rule.recorded_action_id}`)),
        rule_category: ["E_HISTORICAL_COMPATIBILITY"],
        raw_legacy_rule: rule,
        semantic_meaning: ["old-build Action to current-build playback projection"],
        runtime_consumer: ["ActionCompatibility", "ActionMatcher"],
        expected_normalized_result: canonical(rule),
        presentation_effect: false,
        detector_effect: true,
        recorder_effect: false,
        compatibility_effect: true,
        known_reason_comment: rule.evidence ?? null,
        ac_provenance: null,
        bcm_provenance: null,
        provenance_status: rule.evidence ? "historical_runtime_evidence" : "unresolved"
      });
      oracleCases.push({ case_uid: `oracle:compatibility:${character}:${index}`, source_kind: "historical_compatibility", character, action_id: rule.recorded_action_id, effective_rule: canonical(rule) });
    }
  }

  records.sort((a, b) => a.record_uid.localeCompare(b.record_uid));
  oracleCases.sort((a, b) => a.case_uid.localeCompare(b.case_uid));
  sources.sort((a, b) => a.file.localeCompare(b.file));

  const count = (predicate) => records.filter(predicate).length;
  const categoryCounts = Object.fromEntries([
    "A_AC_BCM_SEMANTIC", "B_INPUT_COMMAND_SEMANTIC", "C_RUNTIME_MECHANISM",
    "D_PRESENTATION", "E_HISTORICAL_COMPATIBILITY", "F_UNKNOWN"
  ].map((category) => [category, count((record) => record.rule_category.includes(category))]));
  const characterCoverage = [...new Set(records.map((record) => record.character))].sort();
  const actionRecords = records.filter((record) => ["legacy_action_exception", "migrated_pilot_exception"].includes(record.source_kind));
  const baseline = {
    schema: "sf6cc.character-exception-baseline.v1",
    authority: "historical_regression_only",
    runtime_source: false,
    immutable_snapshot: true,
    snapshot_date: "2026-08-10",
    source_root_hash: sha256(jsonText(sources)),
    summary: {
      records: records.length,
      historical_action_exceptions: actionRecords.length,
      production_loaded_legacy_action_exceptions: count((record) => record.source_kind === "legacy_action_exception"),
      migrated_pilot_action_exceptions: count((record) => record.source_kind === "migrated_pilot_exception"),
      character_policy_records: count((record) => record.source_kind === "legacy_character_policy"),
      presentation_overrides: count((record) => record.source_kind === "presentation_override"),
      historical_compatibility_mappings: count((record) => record.source_kind === "historical_compatibility"),
      category_counts: categoryCounts,
      character_scopes: characterCoverage.length,
      characters: characterCoverage,
      verified_generated_provenance: count((record) => record.provenance_status === "verified_generated"),
      unresolved_provenance: count((record) => record.provenance_status === "unresolved")
    },
    sources,
    records
  };
  const oracle = {
    schema: "sf6cc.character-exception-legacy-oracle.v1",
    authority: "test_oracle_only",
    runtime_source: false,
    baseline_source_root_hash: baseline.source_root_hash,
    summary: { cases: oracleCases.length },
    cases: oracleCases
  };
  return { baseline, oracle };
}

function markdown(baseline, oracle) {
  const byCharacter = new Map();
  for (const record of baseline.records) byCharacter.set(record.character, (byCharacter.get(record.character) ?? 0) + 1);
  const rows = [...byCharacter.entries()].sort(([a], [b]) => a.localeCompare(b))
    .map(([character, count]) => `| ${character} | ${FIGHTER_IDS[character] ?? "-"} | ${count} |`)
    .join("\n");
  return `# Character Exception Baseline\n\n` +
    `Snapshot: 2026-08-10\n\n` +
    `This immutable audit baseline is test evidence only. Production Runtime must never load it.\n\n` +
    `## Summary\n\n` +
    `- Governance records: ${baseline.summary.records}\n` +
    `- Historical Action exceptions: ${baseline.summary.historical_action_exceptions}\n` +
    `- Production-loaded Legacy Action exceptions: ${baseline.summary.production_loaded_legacy_action_exceptions}\n` +
    `- Migrated Pilot Action exceptions: ${baseline.summary.migrated_pilot_action_exceptions}\n` +
    `- Character policy records: ${baseline.summary.character_policy_records}\n` +
    `- Presentation overrides: ${baseline.summary.presentation_overrides}\n` +
    `- Historical compatibility mappings: ${baseline.summary.historical_compatibility_mappings}\n` +
    `- Oracle cases: ${oracle.summary.cases}\n` +
    `- Verified generated provenance records: ${baseline.summary.verified_generated_provenance}\n` +
    `- Unresolved provenance records: ${baseline.summary.unresolved_provenance}\n\n` +
    `## Category Counts\n\n` +
    Object.entries(baseline.summary.category_counts).map(([key, value]) => `- ${key}: ${value}`).join("\n") + `\n\n` +
    `## Character Coverage\n\n| Character | Fighter ID | Records |\n| --- | ---: | ---: |\n${rows}\n\n` +
    `## Artifacts\n\n` +
    `- Machine baseline: \`tests/fixtures/character_exception_baseline.json\`\n` +
    `- Legacy Oracle: \`tests/fixtures/character_exception_legacy_oracle.json\`\n` +
    `- Rebuild/check: \`node tools/character_exception_baseline.mjs --write|--check\`\n\n` +
    `Every record stores its source, raw rule, normalized result, consumers, effects, category, and provenance state. Unknown provenance is explicit and blocks semantic convergence until reviewed.\n`;
}

function writeOrCheck(mode) {
  if (mode === "--check") {
    const baselineRaw = fs.readFileSync(BASELINE_FILE);
    const oracleRaw = fs.readFileSync(ORACLE_FILE);
    if (normalizedTextSha256(baselineRaw) !== SEALED_BASELINE_SHA256) throw new Error("Sealed character exception baseline hash mismatch");
    if (normalizedTextSha256(oracleRaw) !== SEALED_ORACLE_SHA256) throw new Error("Sealed character exception Oracle hash mismatch");
    const baseline = JSON.parse(baselineRaw.toString("utf8"));
    const oracle = JSON.parse(oracleRaw.toString("utf8"));
    if (baseline.schema !== "sf6cc.character-exception-baseline.v1"
      || baseline.authority !== "historical_regression_only"
      || baseline.runtime_source !== false
      || baseline.immutable_snapshot !== true
      || baseline.summary.records !== 633
      || baseline.summary.historical_action_exceptions !== 484
      || oracle.schema !== "sf6cc.character-exception-legacy-oracle.v1"
      || oracle.runtime_source !== false
      || oracle.summary.cases !== 633
      || oracle.baseline_source_root_hash !== baseline.source_root_hash) {
      throw new Error("Sealed character exception baseline contract mismatch");
    }
    process.stdout.write(JSON.stringify({
      mode,
      baseline_records: baseline.summary.records,
      historical_action_exceptions: baseline.summary.historical_action_exceptions,
      production_loaded_legacy_action_exceptions: baseline.summary.production_loaded_legacy_action_exceptions,
      oracle_cases: oracle.summary.cases,
      unresolved_provenance: baseline.summary.unresolved_provenance
    }, null, 2) + "\n");
    return;
  }

  const { baseline, oracle } = build();
  const outputs = [
    [BASELINE_FILE, jsonText(baseline)],
    [ORACLE_FILE, jsonText(oracle)],
    [REPORT_FILE, markdown(baseline, oracle)]
  ];
  if (mode === "--write") {
    if (outputs.some(([filename]) => fs.existsSync(filename))) {
      throw new Error("Character exception baseline is already sealed; --write refuses to overwrite it");
    }
    for (const [filename, content] of outputs) {
      fs.mkdirSync(path.dirname(filename), { recursive: true });
      fs.writeFileSync(filename, content);
    }
  } else if (mode === "--verify-source") {
    for (const [filename, content] of outputs) {
      if (!fs.existsSync(filename) || fs.readFileSync(filename, "utf8") !== content) {
        throw new Error(`Character exception baseline drift: ${relative(filename)}`);
      }
    }
  } else {
    throw new Error("Usage: node tools/character_exception_baseline.mjs --write|--check|--verify-source");
  }
  process.stdout.write(JSON.stringify({
    mode,
    baseline_records: baseline.summary.records,
    historical_action_exceptions: baseline.summary.historical_action_exceptions,
    production_loaded_legacy_action_exceptions: baseline.summary.production_loaded_legacy_action_exceptions,
    oracle_cases: oracle.summary.cases,
    unresolved_provenance: baseline.summary.unresolved_provenance
  }, null, 2) + "\n");
}

writeOrCheck(process.argv[2]);
