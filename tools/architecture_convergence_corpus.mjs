import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

function sha256(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

function readJson(filename) {
  return JSON.parse(fs.readFileSync(filename, "utf8"));
}

function jsonFiles(root) {
  const result = [];
  const visit = (directory) => {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      const full = path.join(directory, entry.name);
      if (entry.isDirectory()) visit(full);
      else if (entry.isFile() && entry.name.toLowerCase().endsWith(".json")) result.push(full);
    }
  };
  visit(root);
  return result.sort();
}

function numericList(value) {
  const items = Array.isArray(value) ? value
    : (typeof value === "string" ? value.split(",") : []);
  return [...new Set(items.map((item) => Number(String(item).trim()))
    .filter(Number.isSafeInteger))].sort((a, b) => a - b);
}

function setIntersection(left, right) {
  const rightSet = new Set(right);
  return left.filter((item) => rightSet.has(item));
}

function buildGraphIndex(runtime) {
  const characters = new Map();
  for (const character of runtime.characters ?? []) {
    const actions = new Map();
    for (const move of character.moves ?? []) {
      for (const membership of move.memberships ?? []) {
        if (!Number.isSafeInteger(membership.action_id)) continue;
        const bucket = actions.get(membership.action_id) ?? [];
        bucket.push({
          current_move_uid: move.current_move_uid,
          stable_move_uid: move.stable_move_uid ?? null,
          provisional: move.provisional === true,
          role: membership.role,
          strictness: membership.strictness
        });
        actions.set(membership.action_id, bucket);
      }
    }
    characters.set(character.character, {
      fighter_id: character.fighter_id,
      actions
    });
  }
  return characters;
}

function resolveAction(index, character, actionId) {
  const characterIndex = index.get(character);
  const candidates = characterIndex?.actions.get(actionId) ?? [];
  const moveUids = [...new Set(candidates.map((item) => item.current_move_uid))].sort();
  const unresolved = candidates.some((item) => item.role === "unresolved"
    || item.strictness === "UNRESOLVED");
  let status = "NOT_FOUND";
  if (candidates.length > 0) status = unresolved ? "UNRESOLVED"
    : (moveUids.length > 1 ? "AMBIGUOUS"
      : (candidates.some((item) => item.provisional || !item.stable_move_uid)
        ? "PROVISIONAL" : "RESOLVED"));
  return { status, candidates, current_move_uids: moveUids };
}

function characterFromCombo(document, filename, knownCharacters) {
  const metaCharacter = document?.[0]?._xt_meta?.character;
  if (knownCharacters.has(metaCharacter)) return metaCharacter;
  const normalized = filename.replaceAll("\\", "/");
  return [...knownCharacters].sort((a, b) => b.length - a.length)
    .find((character) => normalized.includes(`/${character}_CustomCombos/`)
      || normalized.includes(`/CustomCombos/${character}/`)
      || path.basename(filename).startsWith(`${character}_`)) ?? null;
}

function loadDisplay(repoRoot, character) {
  const filename = path.join(repoRoot, "data", "TrainingComboTrials_data",
    "command_display", `${character}.json`);
  if (!fs.existsSync(filename)) return {};
  return readJson(filename);
}

function semanticFields(rule) {
  return ["absorb_ids", "action_alias_ids"].filter((field) => rule[field] != null);
}

function runtimeMechanismFields(rule) {
  const semantic = new Set(["absorb_ids", "action_alias_ids"]);
  return Object.keys(rule).filter((field) => !semantic.has(field));
}

function compareLegacyFamilies(repoRoot, index, corpusActions) {
  const directory = path.join(repoRoot, "data", "TrainingComboTrials_data", "exceptions");
  const cases = [];
  if (!fs.existsSync(directory)) return cases;
  for (const filename of jsonFiles(directory)) {
    const character = path.basename(filename, ".json");
    if (!index.has(character)) continue;
    const document = readJson(filename);
    for (const [ownerKey, rule] of Object.entries(document)) {
      const owner = Number(ownerKey);
      if (!Number.isSafeInteger(owner) || !rule || typeof rule !== "object") continue;
      for (const field of semanticFields(rule)) {
        for (const related of numericList(rule[field])) {
          const left = resolveAction(index, character, owner);
          const right = resolveAction(index, character, related);
          const shared = setIntersection(left.current_move_uids, right.current_move_uids);
          const comparable = left.status !== "NOT_FOUND" && right.status !== "NOT_FOUND";
          const ambiguous = [left.status, right.status].some((status) =>
            status === "AMBIGUOUS" || status === "UNRESOLVED");
          const candidate = !comparable ? "NOT_COMPARABLE"
            : (ambiguous ? "UNKNOWN"
              : (shared.length === 1 ? "SAME_MOVE" : "DISTINCT_MOVE"));
          const actionSet = corpusActions.get(character) ?? new Set();
          cases.push({
            case_uid: `${character}:${owner}:${field}:${related}`,
            character,
            owner_action_id: owner,
            related_action_id: related,
            legacy_classification: "MATCH",
            candidate_classification: candidate,
            difference_category: candidate === "SAME_MOVE" ? "SEMANTIC_MATCH"
              : (candidate === "DISTINCT_MOVE" ? "LEGACY_ONLY" : "UNKNOWN"),
            corpus_referenced: actionSet.has(owner) || actionSet.has(related),
            runtime_mechanism_fields: runtimeMechanismFields(rule),
            shared_current_move_uids: shared,
            owner_resolution: left.status,
            related_resolution: right.status
          });
        }
      }
    }
  }
  return cases;
}

function compareCompatibility(repoRoot, corpusActions) {
  const directory = path.join(repoRoot, "data", "TrainingComboTrials_data", "action_compatibility");
  const cases = [];
  if (!fs.existsSync(directory)) return cases;
  for (const filename of jsonFiles(directory)) {
    const document = readJson(filename);
    const character = document.character ?? path.basename(filename, ".json");
    const actionSet = corpusActions.get(character) ?? new Set();
    for (let index = 0; index < (document.entries ?? []).length; index += 1) {
      const entry = document.entries[index];
      cases.push({
        case_uid: `${character}:${index}`,
        character,
        recorded_action_id: entry.recorded_action_id,
        runtime_action_id: entry.runtime_action_id,
        runtime_action_alias_ids: entry.runtime_action_alias_ids ?? [],
        corpus_referenced: actionSet.has(entry.recorded_action_id),
        classification: "COMPATIBILITY_REQUIRED",
        expected_difference: true,
        evidence: entry.evidence ?? null
      });
    }
  }
  return cases;
}

function validateArtifact(manifestFile, runtimeFile) {
  const manifestRaw = fs.readFileSync(manifestFile);
  const runtimeRaw = fs.readFileSync(runtimeFile);
  const manifest = JSON.parse(manifestRaw.toString("utf8"));
  const entry = manifest.artifacts?.runtime_current;
  if (manifest.schema !== "sf6acbcm.m5-export-manifest.v1"
    || manifest.authority !== "current_semantic_candidate_only"
    || manifest.auto_approved !== false) {
    throw new Error("Unsupported SF6ACBCM export manifest");
  }
  if (!entry || entry.file !== path.basename(runtimeFile)
    || entry.bytes !== runtimeRaw.length || entry.sha256 !== sha256(runtimeRaw)) {
    throw new Error("Runtime artifact does not match export manifest");
  }
  const runtime = JSON.parse(runtimeRaw.toString("utf8"));
  if (runtime.schema !== "sf6acbcm.runtime-current.v1"
    || runtime.authority !== manifest.authority
    || runtime.build?.build_uid !== manifest.build?.build_uid) {
    throw new Error("Runtime artifact contract mismatch");
  }
  return { manifest, runtime };
}

export function analyzeCorpus({ repoRoot, corpusRoot, manifestFile, runtimeFile }) {
  const { manifest, runtime } = validateArtifact(manifestFile, runtimeFile);
  const graph = buildGraphIndex(runtime);
  const knownCharacters = new Set(graph.keys());
  const corpusActions = new Map();
  const cases = [];
  const blockedFiles = [];
  let parsedCombos = 0;
  let replayableCombos = 0;
  let parseFailures = 0;

  const files = jsonFiles(corpusRoot);
  for (const filename of files) {
    let document;
    try {
      document = readJson(filename);
    } catch (error) {
      parseFailures += 1;
      blockedFiles.push({ file: filename, reason: "PARSE_FAILED", message: error.message });
      continue;
    }
    if (!Array.isArray(document) || !document.some((step) => Number.isSafeInteger(step?.id))) continue;
    const character = characterFromCombo(document, filename, knownCharacters);
    if (!character) {
      blockedFiles.push({ file: filename, reason: "CHARACTER_UNKNOWN" });
      continue;
    }
    parsedCombos += 1;
    const first = document[0] ?? {};
    const hasReplayFacts = Array.isArray(first.relative_raw_inputs)
      || Array.isArray(first.raw_inputs) || Array.isArray(first.timeline);
    if (hasReplayFacts) replayableCombos += 1;
    const display = loadDisplay(repoRoot, character);
    const actionSet = corpusActions.get(character) ?? new Set();
    corpusActions.set(character, actionSet);
    for (let stepIndex = 0; stepIndex < document.length; stepIndex += 1) {
      const step = document[stepIndex];
      if (!Number.isSafeInteger(step?.id)) continue;
      actionSet.add(step.id);
      const resolution = resolveAction(graph, character, step.id);
      const displayAvailable = display[String(step.id)] != null;
      cases.push({
        file: path.relative(corpusRoot, filename).replaceAll("\\", "/"),
        character,
        step_index: stepIndex,
        recorded_action_id: step.id,
        recorded_motion: step.motion ?? null,
        raw_replay_available: hasReplayFacts,
        resolution_status: resolution.status,
        current_move_uids: resolution.current_move_uids,
        display_status: displayAvailable ? "AVAILABLE" : "MISSING",
        detection_authority: "LEGACY_PRODUCTION",
        demo_playback_authority: hasReplayFacts ? "FROZEN_V2_RAW_FACTS" : "LEGACY_STEPS_ONLY"
      });
    }
  }

  const familyCases = compareLegacyFamilies(repoRoot, graph, corpusActions);
  const compatibilityCases = compareCompatibility(repoRoot, corpusActions);
  const comparable = cases.filter((item) => item.resolution_status !== "NOT_FOUND").length;
  const exact = cases.filter((item) => ["RESOLVED", "PROVISIONAL"].includes(item.resolution_status)).length;
  const ambiguous = cases.filter((item) => ["AMBIGUOUS", "UNRESOLVED"].includes(item.resolution_status)).length;
  const unknown = cases.length - comparable;
  const semanticMatches = familyCases.filter((item) => item.difference_category === "SEMANTIC_MATCH").length;
  const expectedDifferences = compatibilityCases.filter((item) => item.corpus_referenced).length;
  const legacyOnly = familyCases.filter((item) => item.difference_category === "LEGACY_ONLY");
  const candidateReady = manifest.ready?.artifact_set === true
    && manifest.ready?.review_complete === true
    && manifest.ready?.integration_candidate === true;

  return {
    schema: "sf6cc.architecture-convergence-corpus.v1",
    authority: "diagnostic_only",
    source: {
      corpus_root: path.resolve(corpusRoot),
      runtime_artifact: path.resolve(runtimeFile),
      manifest: path.resolve(manifestFile),
      build: manifest.build,
      artifact_sha256: manifest.artifacts.runtime_current.sha256
    },
    readiness: {
      ...manifest.ready,
      production_switch_allowed: candidateReady,
      production_authority_unchanged: true
    },
    summary: {
      json_files_scanned: files.length,
      parsed_combos: parsedCombos,
      replayable_combos: replayableCombos,
      step_cases: cases.length,
      comparable_cases: comparable,
      exact_current_move_resolutions: exact,
      semantic_matches: semanticMatches,
      expected_differences: expectedDifferences,
      unexpected_differences: 0,
      unknown_cases: unknown,
      ambiguous_cases: ambiguous,
      blocked_cases: candidateReady ? ambiguous : comparable,
      parse_failures: parseFailures,
      legacy_family_cases: familyCases.length,
      legacy_only_family_cases: legacyOnly.length,
      compatibility_cases: compatibilityCases.length
    },
    interpretation: {
      exact_current_move_resolutions: "Build-local candidate Move membership only; provisional identity is not production approval.",
      unexpected_differences: "Zero because the corpus contains recorded facts, not paired live observations; negative equivalence cannot be inferred.",
      blocked_cases: candidateReady
        ? "Ambiguous or unresolved candidate membership."
        : "All comparable cases remain blocked from production switch by manifest readiness."
    },
    legacy_family_cases: familyCases,
    compatibility_cases: compatibilityCases,
    cases,
    blocked_files: blockedFiles
  };
}

function cliArgs(argv) {
  const result = {};
  for (let index = 0; index < argv.length; index += 2) {
    const key = argv[index];
    const value = argv[index + 1];
    if (!key?.startsWith("--") || value == null) throw new Error("Arguments must be --name value pairs");
    result[key.slice(2)] = value;
  }
  return result;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const args = cliArgs(process.argv.slice(2));
  for (const required of ["corpus", "manifest", "artifact"]) {
    if (!args[required]) throw new Error(`Missing --${required}`);
  }
  const report = analyzeCorpus({
    repoRoot: args.repo ? path.resolve(args.repo) : process.cwd(),
    corpusRoot: path.resolve(args.corpus),
    manifestFile: path.resolve(args.manifest),
    runtimeFile: path.resolve(args.artifact)
  });
  const output = `${JSON.stringify(report, null, 2)}\n`;
  if (args.out) {
    fs.mkdirSync(path.dirname(path.resolve(args.out)), { recursive: true });
    fs.writeFileSync(path.resolve(args.out), output);
  } else {
    process.stdout.write(output);
  }
}
