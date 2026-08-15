import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const RUNTIME_FIELDS = new Set([
  "action_required", "absorb_requires_combo", "record_absorb_as_parent",
  "force", "ignore", "is_holdable", "charge_min", "charge_max",
  "hold_partial_check", "perfect_min", "perfect_max", "runtime_force_after_ids",
  "action_event_rules", "ignore_prev_frames",
  "ignore_prev_id", "finish_on_first_hit", "preserve_short_action",
  "action_alias_combo_deltas"
]);

const UNIVERSAL_NOTATIONS = new Set(["66", "Parry", "DI", "Drive Impact", "RAW DR"]);

function readJson(filename) {
  return JSON.parse(fs.readFileSync(filename, "utf8"));
}

function sha256File(filename) {
  return crypto.createHash("sha256").update(fs.readFileSync(filename)).digest("hex");
}

function jsonFiles(root) {
  if (!fs.existsSync(root)) return [];
  return fs.readdirSync(root, { withFileTypes: true })
    .filter((entry) => entry.isFile() && entry.name.toLowerCase().endsWith(".json"))
    .map((entry) => path.join(root, entry.name))
    .sort();
}

function numericList(value) {
  const values = Array.isArray(value) ? value
    : (typeof value === "string" ? value.split(",") : []);
  return [...new Set(values.map((item) => Number(String(item).trim()))
    .filter(Number.isSafeInteger))].sort((a, b) => a - b);
}

function sortedUnique(values) {
  return [...new Set(values.filter((value) => value != null))].sort();
}

function stableObject(value) {
  if (Array.isArray(value)) return value.map(stableObject);
  if (!value || typeof value !== "object") return value;
  return Object.fromEntries(Object.keys(value).sort().map((key) => [key, stableObject(value[key])]));
}

function signature(value) {
  return crypto.createHash("sha256")
    .update(JSON.stringify(stableObject(value)))
    .digest("hex").slice(0, 16);
}

function tally(items, keyOf) {
  const counts = new Map();
  for (const item of items) {
    const key = keyOf(item);
    counts.set(key, (counts.get(key) ?? 0) + 1);
  }
  return Object.fromEntries([...counts.entries()].sort(([a], [b]) => String(a).localeCompare(String(b))));
}

function group(items, keyOf) {
  const result = new Map();
  for (const item of items) {
    const key = keyOf(item);
    const bucket = result.get(key) ?? [];
    bucket.push(item);
    result.set(key, bucket);
  }
  return result;
}

function concentration(families) {
  const counts = families.map((item) => item.observations).sort((a, b) => b - a);
  const total = counts.reduce((sum, value) => sum + value, 0);
  const familiesFor = (ratio) => {
    if (total === 0) return 0;
    let sum = 0;
    for (let index = 0; index < counts.length; index += 1) {
      sum += counts[index];
      if (sum / total >= ratio) return index + 1;
    }
    return counts.length;
  };
  return {
    total_observations: total,
    unique_families: counts.length,
    families_for_50_percent: familiesFor(0.5),
    families_for_80_percent: familiesFor(0.8),
    families_for_90_percent: familiesFor(0.9)
  };
}

function validateInputs(corpus, m1, m2, runtime, manifest) {
  if (corpus.schema !== "sf6cc.architecture-convergence-corpus.v1") {
    throw new Error("Unsupported Phase 1 corpus report");
  }
  if (m1.schema !== "sf6acbcm.m1-extraction.v1"
    || m2.schema !== "sf6acbcm.m2-current-graph.v1"
    || runtime.schema !== "sf6acbcm.runtime-current.v1"
    || manifest.schema !== "sf6acbcm.m5-export-manifest.v1") {
    throw new Error("Unsupported SF6ACBCM lineage artifact");
  }
  const buildUid = m2.build?.build_uid;
  if (!buildUid || runtime.build?.build_uid !== buildUid || manifest.build?.build_uid !== buildUid
    || corpus.source?.build?.build_uid !== buildUid) {
    throw new Error("Phase 2 inputs do not describe the same build");
  }
  if (manifest.authority !== "current_semantic_candidate_only" || manifest.auto_approved !== false) {
    throw new Error("M5 candidate authority contract mismatch");
  }
}

function buildM1Index(m1, buildUid) {
  const build = (m1.builds ?? []).find((item) => item.build?.build_uid === buildUid);
  if (!build) throw new Error(`M1 build not found: ${buildUid}`);
  const characters = new Map();
  for (const character of build.characters ?? []) {
    const familyByAnchor = new Map();
    for (const family of character.route_families ?? []) {
      for (const anchorUid of family.anchor_route_uids ?? []) {
        const bucket = familyByAnchor.get(anchorUid) ?? [];
        bucket.push(family);
        familyByAnchor.set(anchorUid, bucket);
      }
    }
    const anchorsByAction = group(character.anchor_routes ?? [], (anchor) => anchor.owner_action_id);
    characters.set(character.key.character, { character, anchorsByAction, familyByAnchor });
  }
  return characters;
}

function enabledCommands(move) {
  return sortedUnique((move.revision?.command_revisions ?? [])
    .filter((command) => command.enabled)
    .map((command) => `${command.profile_name}:${command.normalized_notation}`));
}

function buildM2Index(m2) {
  const characters = new Map();
  for (const character of m2.characters ?? []) {
    const candidatesByAction = new Map();
    for (const move of character.moves ?? []) {
      for (const membership of move.revision?.memberships ?? []) {
        const bucket = candidatesByAction.get(membership.action_id) ?? [];
        bucket.push({
          move_uid: move.move_uid,
          family_uids: move.family_uids ?? [],
          disabled_only: move.disabled_only === true,
          duplicate_owners: move.duplicate_owners === true,
          commands: enabledCommands(move),
          anchors: (move.revision?.bcm_anchor_revisions ?? []).map((anchor) => ({
            owner_action_id: anchor.owner_action_id,
            trigger_index: anchor.trigger_index,
            anchor_route_uid: anchor.anchor_route_uid
          })),
          membership
        });
        candidatesByAction.set(membership.action_id, bucket);
      }
    }
    const censusByAction = new Map();
    for (const row of character.action_census?.common_scope ?? []) censusByAction.set(row.action_id, row);
    for (const row of character.action_census?.character_scope ?? []) censusByAction.set(row.action_id, row);
    characters.set(character.key.character, { character, candidatesByAction, censusByAction });
  }
  return characters;
}

function loadLegacy(repoRoot) {
  const exceptions = new Map();
  const policies = [];
  const exceptionRoot = path.join(repoRoot, "data", "TrainingComboTrials_data", "exceptions");
  for (const filename of jsonFiles(exceptionRoot)) {
    const character = path.basename(filename, ".json");
    const document = readJson(filename);
    for (const [key, rule] of Object.entries(document)) {
      if (key === "_character") {
        policies.push({ character, rule });
        continue;
      }
      const actionId = Number(key);
      if (!Number.isSafeInteger(actionId) || !rule || typeof rule !== "object") continue;
      exceptions.set(`${character}:${actionId}`, { character, action_id: actionId, rule });
    }
  }

  const presentation = new Map();
  const presentationRoot = path.join(repoRoot, "data", "TrainingComboTrials_data", "command_display_overrides");
  for (const filename of jsonFiles(presentationRoot)) {
    const document = readJson(filename);
    const character = document.character ?? path.basename(filename, ".json");
    for (const [key, rule] of Object.entries(document.entries ?? {})) {
      const actionId = Number(key);
      if (Number.isSafeInteger(actionId)) presentation.set(`${character}:${actionId}`, { character, action_id: actionId, rule });
    }
  }

  const compatibility = new Map();
  const compatibilityRoot = path.join(repoRoot, "data", "TrainingComboTrials_data", "action_compatibility");
  for (const filename of jsonFiles(compatibilityRoot)) {
    const document = readJson(filename);
    const character = document.character ?? path.basename(filename, ".json");
    for (const entry of document.entries ?? []) {
      if (!Number.isSafeInteger(entry.recorded_action_id)) continue;
      compatibility.set(`${character}:${entry.recorded_action_id}`, entry);
    }
  }
  return { exceptions, policies, presentation, compatibility };
}

function commandNotations(candidate) {
  return candidate.commands.map((command) => command.slice(command.indexOf(":") + 1));
}

function classifyAmbiguity(candidates) {
  const roles = sortedUnique(candidates.map((item) => item.membership.role));
  const strictness = sortedUnique(candidates.map((item) => item.membership.strictness));
  if (roles.includes("alias")) {
    return { classification: "ALIAS_EQUIVALENCE", requirement: "HUMAN_SEMANTIC_REVIEW_REQUIRED" };
  }
  if (roles.some((role) => ["derived", "replacement", "contextual"].includes(role))
    || strictness.some((value) => value !== "STRICT")) {
    return { classification: "FOLLOWUP_RELATION", requirement: "HUMAN_SEMANTIC_REVIEW_REQUIRED" };
  }

  const commandSets = candidates.map((item) => item.commands.join("|"));
  const uniqueCommandSets = sortedUnique(commandSets);
  const notations = sortedUnique(candidates.flatMap(commandNotations));
  const commandless = candidates.filter((item) => item.commands.length === 0).length;
  if (commandless > 0 && commandless < candidates.length) {
    return {
      classification: "GENERATOR_OVERLAP",
      requirement: "HUMAN_SEMANTIC_REVIEW_REQUIRED",
      subtype: "DISABLED_ROUTE_FAMILY_OVERLAP"
    };
  }
  const hasUniversalCollision = notations.some((notation) => UNIVERSAL_NOTATIONS.has(notation))
    && uniqueCommandSets.length > 1;
  if (hasUniversalCollision) {
    return { classification: "RUNTIME_MECHANISM", requirement: "HUMAN_SEMANTIC_REVIEW_REQUIRED", subtype: "UNIVERSAL_ROUTE_COLLISION" };
  }
  if (uniqueCommandSets.length === 1 && uniqueCommandSets[0] !== "") {
    return { classification: "GENERATOR_OVERLAP", requirement: "HUMAN_SEMANTIC_REVIEW_REQUIRED", subtype: "DUPLICATE_ENABLED_COMMAND_SET" };
  }
  if (uniqueCommandSets.length > 1 && candidates.every((item) => item.commands.length > 0)) {
    return { classification: "TRUE_MULTI_MOVE_MEMBERSHIP", requirement: "HUMAN_SEMANTIC_REVIEW_REQUIRED", subtype: "DISTINCT_ENABLED_COMMAND_SETS" };
  }
  return { classification: "INSUFFICIENT_FACT", requirement: "OFFLINE_INSUFFICIENT_DATA" };
}

function ambiguityFamilies(corpus, m1Index, m2Index) {
  const cases = corpus.cases.filter((item) => ["AMBIGUOUS", "UNRESOLVED"].includes(item.resolution_status));
  const groups = [...group(cases, (item) => `${item.character}:${item.recorded_action_id}`).entries()]
    .map(([key, observations]) => {
      const [character, actionText] = key.split(":");
      const actionId = Number(actionText);
      const m2 = m2Index.get(character);
      const candidates = (m2?.candidatesByAction.get(actionId) ?? [])
        .sort((a, b) => a.move_uid.localeCompare(b.move_uid));
      const classification = classifyAmbiguity(candidates);
      const m1 = m1Index.get(character);
      const anchors = (m1?.anchorsByAction.get(actionId) ?? []).map((anchor) => ({
        anchor_route_uid: anchor.anchor_route_uid,
        trigger_index: anchor.trigger_index,
        condition_hash: anchor.condition_hash,
        enabled_commands: sortedUnique((anchor.profiles ?? []).filter((profile) => profile.enabled)
          .map((profile) => `${profile.profile_name}:${profile.normalized_notation}`)),
        family_uids: sortedUnique((m1?.familyByAnchor.get(anchor.anchor_route_uid) ?? [])
          .map((family) => family.family_uid))
      })).sort((a, b) => a.trigger_index - b.trigger_index);
      const m1Families = sortedUnique(anchors.flatMap((anchor) => anchor.family_uids));
      const m2Families = sortedUnique(candidates.flatMap((candidate) => candidate.family_uids));
      return {
        character,
        action_id: actionId,
        observations: observations.length,
        combos: new Set(observations.map((item) => item.file)).size,
        recorded_motions: sortedUnique(observations.map((item) => item.recorded_motion)),
        classification: classification.classification,
        classification_subtype: classification.subtype ?? null,
        decision_requirement: classification.requirement,
        first_ambiguity_layer: m1Families.length > 1 ? "M1_ROUTE_FAMILY"
          : (m2Families.length > 1 ? "M2_MOVE_MEMBERSHIP" : "M5_RUNTIME_SERIALIZATION"),
        census: m2?.censusByAction.get(actionId) ?? null,
        m1_anchor_routes: anchors,
        candidates
      };
    })
    .sort((a, b) => b.observations - a.observations
      || a.character.localeCompare(b.character) || a.action_id - b.action_id);
  return groups.map((item, index) => ({ ledger_id: `AMB-A-${String(index + 1).padStart(4, "0")}`, ...item }));
}

function isDirectionOnly(motions) {
  return motions.length > 0 && motions.every((motion) => /^[1-9]$/.test(String(motion ?? "").trim()));
}

function runtimeFields(rule) {
  return Object.keys(rule ?? {}).filter((field) => RUNTIME_FIELDS.has(field)).sort();
}

function classifyUnmapped({ actionId, motions, census, anchors, legacy, presentation, compatibility, characterFrequency }) {
  if (compatibility) return { classification: "LEGACY_ONLY", reason: "EXPLICIT_ACTION_COMPATIBILITY_MAPPING" };
  if (census?.source_scope === "common") return { classification: "SYSTEM_ACTION", reason: "M2_COMMON_SCOPE" };
  if (legacy && runtimeFields(legacy.rule).length > 0) {
    return { classification: "RUNTIME_ONLY_ACTION", reason: "LEGACY_RUNTIME_MECHANISM_EVIDENCE" };
  }
  if (anchors.some((anchor) => anchor.has_enabled_profile)) {
    return { classification: "MISSING_GENERATED_FACT", reason: "ENABLED_M1_BCM_ANCHOR_WITHOUT_M2_MEMBERSHIP" };
  }
  if ((census?.inbound_edge_count ?? 0) + (census?.outbound_edge_count ?? 0) > 0) {
    return { classification: "TRANSITION_ACTION", reason: "AC_CONNECTED_WITHOUT_MOVE_MEMBERSHIP" };
  }
  if (presentation) return { classification: "PRESENTATION_ACTION", reason: "PRESENTATION_EVIDENCE_WITHOUT_MOVE_OR_RELATION" };
  if (isDirectionOnly(motions) && characterFrequency >= 3 && actionId < 100) {
    return { classification: "SYSTEM_ACTION", reason: "CROSS_CHARACTER_DIRECTIONAL_RUNTIME_FACT" };
  }
  if (census?.representation === "system_or_unanchored") {
    return { classification: "RUNTIME_ONLY_ACTION", reason: "CHARACTER_SCOPE_UNANCHORED_RUNTIME_FACT" };
  }
  if (!census) return { classification: "BUILD_MISMATCH", reason: "ACTION_ABSENT_FROM_M2_CENSUS" };
  return { classification: "UNKNOWN", reason: "OFFLINE_EVIDENCE_INSUFFICIENT" };
}

function unmappedFamilies(corpus, m1Index, m2Index, legacy) {
  const cases = corpus.cases.filter((item) => item.resolution_status === "NOT_FOUND");
  const grouped = group(cases, (item) => `${item.character}:${item.recorded_action_id}`);
  const characterFrequency = new Map();
  for (const observations of grouped.values()) {
    const actionId = observations[0].recorded_action_id;
    const characters = characterFrequency.get(actionId) ?? new Set();
    characters.add(observations[0].character);
    characterFrequency.set(actionId, characters);
  }
  const families = [...grouped.entries()].map(([key, observations]) => {
    const [character, actionText] = key.split(":");
    const actionId = Number(actionText);
    const m1 = m1Index.get(character);
    const m2 = m2Index.get(character);
    const anchors = m1?.anchorsByAction.get(actionId) ?? [];
    const motions = sortedUnique(observations.map((item) => item.recorded_motion));
    const legacyRecord = legacy.exceptions.get(key) ?? null;
    const presentationRecord = legacy.presentation.get(key) ?? null;
    const classification = classifyUnmapped({
      actionId,
      motions,
      census: m2?.censusByAction.get(actionId) ?? null,
      anchors,
      legacy: legacyRecord,
      presentation: presentationRecord,
      compatibility: legacy.compatibility.get(key) ?? null,
      characterFrequency: characterFrequency.get(actionId)?.size ?? 0
    });
    return {
      character,
      action_id: actionId,
      observations: observations.length,
      combos: new Set(observations.map((item) => item.file)).size,
      recorded_motions: motions,
      classification: classification.classification,
      reason: classification.reason,
      decision_requirement: classification.classification === "UNKNOWN"
        ? "OFFLINE_INSUFFICIENT_DATA" : "OFFLINE_EXPLAINED",
      census: m2?.censusByAction.get(actionId) ?? null,
      m1_anchor_routes: anchors.map((anchor) => ({
        anchor_route_uid: anchor.anchor_route_uid,
        trigger_index: anchor.trigger_index,
        has_enabled_profile: anchor.has_enabled_profile
      })),
      legacy_runtime_fields: runtimeFields(legacyRecord?.rule),
      presentation_override: presentationRecord != null,
      compatibility_mapping: legacy.compatibility.get(key) ?? null,
      cross_character_family_count: characterFrequency.get(actionId)?.size ?? 0
    };
  }).sort((a, b) => b.observations - a.observations
    || a.character.localeCompare(b.character) || a.action_id - b.action_id);
  return families.map((item, index) => ({ ledger_id: `UNMAP-A-${String(index + 1).padStart(4, "0")}`, ...item }));
}

function mechanismSubclass(fields) {
  if (fields.includes("action_event_rules")) return "ACTION_EVENT_PROJECTION";
  if (fields.some((field) => ["runtime_force_after_ids", "action_alias_combo_deltas"].includes(field))) return "FOLLOWUP_BRIDGE";
  if (fields.some((field) => ["is_holdable", "charge_min", "charge_max", "hold_partial_check", "perfect_min", "perfect_max"].includes(field))) return "HOLD_OR_CHARGE_TIMING";
  if (fields.some((field) => ["ignore", "ignore_prev_frames", "ignore_prev_id"].includes(field))) return "SUPPRESSION";
  if (fields.some((field) => ["action_required", "absorb_requires_combo", "record_absorb_as_parent", "finish_on_first_hit", "preserve_short_action"].includes(field))) return "STATE_OR_CONTACT";
  if (fields.includes("force")) return "PARTICIPATION_CONTROL";
  return "UNKNOWN_RUNTIME_MECHANISM";
}

function ownershipForAction(character, actionId, m1Index, m2Index, legacy, unmappedByKey) {
  const key = `${character}:${actionId}`;
  const observed = unmappedByKey.get(key);
  if (observed) return observed;
  const m1 = m1Index.get(character);
  const m2 = m2Index.get(character);
  const legacyRecord = legacy.exceptions.get(key) ?? null;
  const presentationRecord = legacy.presentation.get(key) ?? null;
  const result = classifyUnmapped({
    actionId,
    motions: [],
    census: m2?.censusByAction.get(actionId) ?? null,
    anchors: m1?.anchorsByAction.get(actionId) ?? [],
    legacy: legacyRecord,
    presentation: presentationRecord,
    compatibility: legacy.compatibility.get(key) ?? null,
    characterFrequency: 0
  });
  return { character, action_id: actionId, ...result };
}

function auditLegacy(legacy, corpus, unmappedByKey, m1Index, m2Index) {
  const mechanisms = [];
  const absorbRecords = [];
  const aliases = [];
  for (const record of legacy.exceptions.values()) {
    const fields = runtimeFields(record.rule);
    if (fields.length > 0) {
      mechanisms.push({
        record_uid: `action:${record.character}:${record.action_id}`,
        character: record.character,
        action_id: record.action_id,
        fields,
        subclass: mechanismSubclass(fields)
      });
    }
    const absorbIds = numericList(record.rule.absorb_ids);
    if (absorbIds.length > 0) absorbRecords.push({
      character: record.character,
      owner_action_id: record.action_id,
      absorb_ids: absorbIds,
      behavior_signature: signature({ fields, projection: record.rule.action_event_projection ?? null })
    });
    for (const aliasId of numericList(record.rule.action_alias_ids)) aliases.push({
      character: record.character,
      owner_action_id: record.action_id,
      alias_action_id: aliasId,
      equality_kind: "HUMAN_SEMANTIC_REVIEW_REQUIRED"
    });
  }

  mechanisms.sort((a, b) => a.record_uid.localeCompare(b.record_uid));
  absorbRecords.sort((a, b) => a.character.localeCompare(b.character) || a.owner_action_id - b.owner_action_id);
  aliases.sort((a, b) => a.character.localeCompare(b.character)
    || a.owner_action_id - b.owner_action_id || a.alias_action_id - b.alias_action_id);

  const relationCases = corpus.legacy_family_cases.map((item) => {
    let offline_category;
    let explanation;
    if (item.candidate_classification === "SAME_MOVE") {
      offline_category = "OFFLINE_PROVED_SAME_MOVE";
      explanation = "Both Actions have one shared current Move candidate.";
    } else if (item.candidate_classification === "DISTINCT_MOVE") {
      offline_category = "OFFLINE_PROVED_DISTINCT_MOVE";
      explanation = "Both Actions resolve singly, but their current Move candidates differ.";
    } else if ([item.owner_resolution, item.related_resolution].includes("AMBIGUOUS")
      || [item.owner_resolution, item.related_resolution].includes("UNRESOLVED")) {
      offline_category = "HUMAN_SEMANTIC_REVIEW_REQUIRED";
      explanation = "At least one Action has multiple or unresolved Move memberships.";
    } else {
      const missingAction = item.owner_resolution === "NOT_FOUND" ? item.owner_action_id : item.related_action_id;
      const ownership = ownershipForAction(item.character, missingAction,
        m1Index, m2Index, legacy, unmappedByKey);
      if (ownership && ["SYSTEM_ACTION", "RUNTIME_ONLY_ACTION", "TRANSITION_ACTION", "LEGACY_ONLY"].includes(ownership.classification)) {
        offline_category = "OFFLINE_PROVABLE_NOT_IMPLEMENTED";
        explanation = ownership.classification === "LEGACY_ONLY"
          ? "The missing Action is an explicit historical compatibility locator, so current Move equality must follow the compatibility projection first."
          : `The missing Action is classified as ${ownership.classification}, so Move equality is the wrong comparison.`;
      } else if (ownership?.classification === "MISSING_GENERATED_FACT") {
        offline_category = "OFFLINE_PROVABLE_NOT_IMPLEMENTED";
        explanation = "Raw BCM ownership exists, but the generated Move membership is missing.";
      } else if (ownership?.classification === "BUILD_MISMATCH") {
        offline_category = "OFFLINE_INSUFFICIENT_DATA";
        explanation = "The Action is absent from the current-build census.";
      } else {
        offline_category = "OFFLINE_INSUFFICIENT_DATA";
        explanation = "Current offline artifacts do not establish both sides of the relation.";
      }
    }
    return { ...item, offline_category, explanation };
  });

  const absorbFamilies = [...group(absorbRecords, (item) => `${item.character}:${item.behavior_signature}`).entries()]
    .map(([familyKey, records]) => ({
      family_uid: `ABS-${signature(familyKey)}`,
      character: records[0].character,
      behavior_signature: records[0].behavior_signature,
      records: records.length,
      owners: records.map((item) => item.owner_action_id).sort((a, b) => a - b),
      related_actions: sortedUnique(records.flatMap((item) => item.absorb_ids).map(String)).map(Number)
    })).sort((a, b) => b.records - a.records || a.family_uid.localeCompare(b.family_uid));

  return {
    runtime_mechanisms: {
      records: mechanisms,
      summary: {
        records: mechanisms.length,
        subclasses: tally(mechanisms, (item) => item.subclass),
        pure_unknown: mechanisms.filter((item) => item.subclass === "UNKNOWN_RUNTIME_MECHANISM").length
      }
    },
    absorb: { records: absorbRecords.length, families: absorbFamilies.length, family_ledger: absorbFamilies },
    aliases: {
      records: new Set(aliases.map((item) => `${item.character}:${item.owner_action_id}`)).size,
      links: aliases.length,
      unique_pairs: new Set(aliases.map((item) => `${item.character}:${Math.min(item.owner_action_id, item.alias_action_id)}:${Math.max(item.owner_action_id, item.alias_action_id)}`)).size,
      ledger: aliases
    },
    relations: {
      cases: relationCases,
      summary: {
        cases: relationCases.length,
        initial_unknown: corpus.legacy_family_cases.filter((item) => item.difference_category === "UNKNOWN").length,
        categories: tally(relationCases, (item) => item.offline_category),
        pure_unknown: relationCases.filter((item) => item.offline_category === "OFFLINE_INSUFFICIENT_DATA").length
      }
    }
  };
}

function auditPresentation(legacy) {
  const records = [...legacy.presentation.values()].map((record) => {
    const fields = Object.keys(record.rule).sort();
    const selectionFields = fields.filter((field) => ["commands", "button_masks", "variants", "require_recorded_motion_match"].includes(field));
    const forbiddenFields = fields.filter((field) => ["move_uid", "stable_move_uid", "absorb_ids", "action_alias_ids", "force", "ignore"].includes(field));
    return {
      record_uid: `presentation:${record.character}:${record.action_id}`,
      character: record.character,
      action_id: record.action_id,
      classification: forbiddenFields.length > 0 ? "MOVE_IDENTITY_PATCH"
        : (selectionFields.length > 0 ? "COMMAND_DISPLAY_ONLY" : "LABEL_ONLY"),
      fields,
      forbidden_fields: forbiddenFields,
      evidence_present: typeof record.rule.evidence === "string" && record.rule.evidence.trim().length > 0
    };
  }).sort((a, b) => a.record_uid.localeCompare(b.record_uid));
  return {
    records,
    summary: {
      records: records.length,
      classifications: tally(records, (item) => item.classification),
      identity_affecting: records.filter((item) => item.classification === "MOVE_IDENTITY_PATCH").length,
      missing_evidence: records.filter((item) => !item.evidence_present).length
    }
  };
}

function auditPolicies(policies) {
  return policies.map(({ character, rule }) => {
    const hasSequence = rule.sequence_grouping != null;
    const hasResource = (rule.transcription_rules?.initial_unique_requirements ?? []).length > 0;
    const classification = hasResource && rule.allow_pending_absorb === true ? "RESOURCE_GATED_ABSORB_POLICY"
      : (hasResource ? "RESOURCE_GATED_TRANSCRIPTION_POLICY"
        : (hasSequence ? "FOLLOWUP_GROUPING_POLICY" : "UNKNOWN_CHARACTER_POLICY"));
    return {
      record_uid: `policy:${character}`,
      character,
      classification,
      fields: Object.keys(rule).sort(),
      decision_requirement: classification === "UNKNOWN_CHARACTER_POLICY"
        ? "OFFLINE_INSUFFICIENT_DATA" : "OFFLINE_EXPLAINED"
    };
  }).sort((a, b) => a.record_uid.localeCompare(b.record_uid));
}

function pendingM2Review(m2, manifest) {
  const rows = (m2.characters ?? []).flatMap((character) =>
    (character.unresolved_rows ?? []).map((row) => ({
      character: character.key.character,
      row_kind: row.row_kind,
      predicate: row.predicate,
      reasons: row.reasons ?? []
    })));
  const rowGroups = [...group(rows, (item) => `${item.row_kind}:${item.predicate}:${item.reasons.map((reason) => reason.split(":")[0]).sort().join(",")}`).entries()]
    .map(([key, members]) => ({
      group_uid: `M2ROW-${signature(key)}`,
      row_kind: members[0].row_kind,
      predicate: members[0].predicate,
      reason_codes: sortedUnique(members.flatMap((item) => item.reasons.map((reason) => reason.split(":")[0]))),
      records: members.length,
      characters: sortedUnique(members.map((item) => item.character)),
      requirement: members[0].predicate === "t20_hold_continuation"
        ? "RAW_ACCESSOR_CONTRACT_REQUIRED" : "HUMAN_SEMANTIC_REVIEW_REQUIRED"
    })).sort((a, b) => a.predicate.localeCompare(b.predicate) || a.group_uid.localeCompare(b.group_uid));

  const extensions = m2.unresolved_extensions ?? [];
  const extensionGroups = [...group(extensions, (item) => `${item.extension_kind}:${item.predicate}:${item.attachment?.kind}`).entries()]
    .map(([key, members]) => ({
      group_uid: `M2EXT-${signature(key)}`,
      extension_kind: members[0].extension_kind,
      predicate: members[0].predicate,
      attachment: members[0].attachment?.kind ?? null,
      records: members.length,
      requirement: "HUMAN_SEMANTIC_REVIEW_REQUIRED"
    })).sort((a, b) => a.extension_kind.localeCompare(b.extension_kind) || a.group_uid.localeCompare(b.group_uid));

  const transitions = (m2.characters ?? []).flatMap((character) =>
    (character.transitions ?? []).filter((item) => item.strictness === "UNRESOLVED")
      .map((item) => ({ character: character.key.character, ...item })));
  const transitionGroups = [...group(transitions, (item) => `${item.kind}:${(item.evidence?.reasons ?? []).join(",")}`).entries()]
    .map(([key, members]) => ({
      group_uid: `M2TR-${signature(key)}`,
      kind: members[0].kind,
      reasons: sortedUnique(members.flatMap((item) => item.evidence?.reasons ?? [])),
      records: members.length,
      characters: sortedUnique(members.map((item) => item.character)),
      requirement: "HUMAN_SEMANTIC_REVIEW_REQUIRED"
    })).sort((a, b) => a.kind.localeCompare(b.kind) || a.group_uid.localeCompare(b.group_uid));

  return {
    unresolved_rows: { records: rows.length, groups: rowGroups.length, review_groups: rowGroups },
    unresolved_extensions: { records: extensions.length, groups: extensionGroups.length, review_groups: extensionGroups },
    unresolved_transitions: { records: transitions.length, groups: transitionGroups.length, review_groups: transitionGroups },
    migration_links: {
      records: manifest.review_pending?.migration_links ?? manifest.unresolved?.migration_links ?? 0,
      requirement: "HUMAN_MIGRATION_REVIEW_REQUIRED",
      auto_approved: false
    }
  };
}

function stableIdentityBatches(m2Index) {
  const rows = [];
  for (const [character, index] of m2Index) {
    for (const move of index.character.moves ?? []) {
      const memberships = move.revision?.memberships ?? [];
      const membershipCounts = memberships.map((membership) =>
        index.candidatesByAction.get(membership.action_id)?.length ?? 0);
      const commands = enabledCommands(move);
      const ambiguous = membershipCounts.some((count) => count > 1);
      const unresolved = memberships.some((membership) => membership.strictness === "UNRESOLVED" || membership.role === "unresolved");
      const classification = ambiguous ? "AMBIGUOUS"
        : (unresolved || move.disabled_only ? "UNKNOWN"
          : (commands.length > 0 && !move.duplicate_owners ? "HIGH_CONFIDENCE_UNAMBIGUOUS" : "MEDIUM"));
      rows.push({
        character,
        move_uid: move.move_uid,
        classification,
        membership_count: memberships.length,
        roles: sortedUnique(memberships.map((item) => item.role)),
        has_enabled_command: commands.length > 0,
        disabled_only: move.disabled_only === true,
        duplicate_owners: move.duplicate_owners === true,
        commands
      });
    }
  }
  const batches = [...group(rows, (item) => [
    item.classification,
    item.character,
    item.roles.join(","),
    item.has_enabled_command ? "commands" : "no_commands",
    item.disabled_only ? "disabled" : "active",
    item.duplicate_owners ? "duplicate_owners" : "single_owner",
    item.membership_count > 1 ? "multi_membership" : "single_membership"
  ].join(":")).entries()]
    .map(([key, members]) => ({
      batch_uid: `REVIEW-${signature(key)}`,
      classification: members[0].classification,
      character: members[0].character,
      roles: members[0].roles,
      evidence_shape: {
        has_enabled_command: members[0].has_enabled_command,
        disabled_only: members[0].disabled_only,
        duplicate_owners: members[0].duplicate_owners,
        multi_membership: members[0].membership_count > 1
      },
      sample_commands: sortedUnique(members.flatMap((item) => item.commands)).slice(0, 8),
      moves: members.length,
      members: members.map((item) => ({ character: item.character, move_uid: item.move_uid }))
        .sort((a, b) => a.character.localeCompare(b.character) || a.move_uid.localeCompare(b.move_uid))
    })).sort((a, b) => a.classification.localeCompare(b.classification)
      || a.character.localeCompare(b.character) || b.moves - a.moves || a.batch_uid.localeCompare(b.batch_uid));
  return {
    moves: rows.length,
    classifications: tally(rows, (item) => item.classification),
    review_batches: batches.length,
    batches
  };
}

function m5GateMatrix(manifest) {
  return [
    { gate: "artifact_set", current: manifest.ready?.artifact_set === true, required: true, can_improve_offline: true, needs_human: false, needs_real_game: false },
    { gate: "review_complete", current: manifest.ready?.review_complete === true, required: true, can_improve_offline: false, needs_human: true, needs_real_game: false },
    { gate: "integration_candidate", current: manifest.ready?.integration_candidate === true, required: true, can_improve_offline: false, needs_human: true, needs_real_game: true },
    { gate: "stable_identities", current: manifest.approval_coverage?.stable_identities ?? 0, required: manifest.approval_coverage?.moves ?? 0, can_improve_offline: false, needs_human: true, needs_real_game: false },
    { gate: "unresolved_rows", current: manifest.unresolved?.rows ?? 0, required: 0, can_improve_offline: true, needs_human: true, needs_real_game: false },
    { gate: "unresolved_transitions", current: manifest.unresolved?.transitions ?? 0, required: 0, can_improve_offline: true, needs_human: true, needs_real_game: true },
    { gate: "real_game_smoke", current: "UNAVAILABLE", required: "PASS", can_improve_offline: false, needs_human: true, needs_real_game: true }
  ];
}

function humanReviewPacket(ambiguity, stableIdentities, aliases, m2Review) {
  const ambiguityItems = ambiguity.filter((item) => item.decision_requirement === "HUMAN_SEMANTIC_REVIEW_REQUIRED")
    .map((item) => ({
      id: item.ledger_id,
      family: `${item.character} Action ${item.action_id}`,
      evidence: {
        observations: item.observations,
        first_ambiguity_layer: item.first_ambiguity_layer,
        candidate_moves: item.candidates.map((candidate) => candidate.move_uid),
        command_sets: item.candidates.map((candidate) => candidate.commands)
      },
      options: ["keep distinct Move memberships", "merge generator route families", "classify as runtime mechanism"],
      impact: "Changes candidate Move ownership only after a separate reviewed generator decision.",
      recommended_safe_default: "Keep all memberships provisional and production_result=legacy."
    }));
  return {
    schema: "sf6cc.human-review-packet.v1",
    authority: "review_input_only",
    auto_approved: false,
    summary: {
      ambiguity_decisions: ambiguityItems.length,
      stable_identity_batches: stableIdentities.review_batches,
      alias_decisions: aliases.unique_pairs,
      m2_row_groups: m2Review.unresolved_rows.groups,
      m2_extension_groups: m2Review.unresolved_extensions.groups,
      m2_transition_groups: m2Review.unresolved_transitions.groups,
      migration_links: m2Review.migration_links.records
    },
    ambiguity_items: ambiguityItems,
    stable_identity_batches: stableIdentities.batches,
    alias_items: aliases.ledger,
    m2_pending_review: m2Review
  };
}

function smokePacket(ambiguity, unmapped, legacyAudit) {
  const representativeAmbiguity = ambiguity[0] ?? null;
  const representativeUnmapped = unmapped[0] ?? null;
  const representativeMechanism = legacyAudit.runtime_mechanisms.records[0] ?? null;
  const cases = [
    {
      id: "SMOKE-EHONDA-926-921",
      setup: "EHonda with the stock/resource states used by Actions 921 and 926.",
      steps: ["Trigger Action 921 route", "Trigger Action 926 route", "Capture Action, resource state, input profile, and shadow compare"],
      observation_to_capture: ["Action sequence", "stock_0_020", "BCM route/profile", "Legacy match", "MoveResolver candidates"],
      legacy_expected: "Character policy and Legacy exceptions remain authoritative.",
      shadow_expected: "921 and 926 remain distinct provisional Move candidates unless live state proves a relation.",
      decision_resolved: "Whether the relation is resource-conditioned runtime behavior rather than stable Move identity."
    },
    {
      id: "SMOKE-YASMINE-941-942",
      setup: "Yasmine in normal and relevant stock/resource states.",
      steps: ["Trigger Action 941", "Observe any transition to 942", "Capture input profile, state, and shadow compare"],
      observation_to_capture: ["941->942 Action timing", "stock_0_033", "BCM enabled profile", "Legacy match", "MoveResolver candidates"],
      legacy_expected: "Legacy detection/playback remains authoritative.",
      shadow_expected: "941 and 942 remain distinct provisional Move candidates; 942 has no enabled BCM command in offline evidence.",
      decision_resolved: "Whether 942 is a transition/internal phase or an independently triggerable Move."
    }
  ];
  if (representativeAmbiguity) cases.push({
    id: "SMOKE-REPRESENTATIVE-AMBIGUITY",
    setup: `${representativeAmbiguity.character} Action ${representativeAmbiguity.action_id}`,
    steps: ["Execute each known enabled route into the Action", "Capture runtime state and shadow compare for each route"],
    observation_to_capture: ["route trigger", "control mode", "state/resource predicates", "candidate selected or unresolved"],
    legacy_expected: "Legacy result is used.",
    shadow_expected: `${representativeAmbiguity.candidates.length} provisional candidates are recorded without selecting one.`,
    decision_resolved: `Resolve ${representativeAmbiguity.ledger_id}.`
  });
  if (representativeUnmapped) cases.push({
    id: "SMOKE-REPRESENTATIVE-UNMAPPED",
    setup: `${representativeUnmapped.character} Action ${representativeUnmapped.action_id}`,
    steps: ["Reproduce the corpus step", "Capture surrounding Actions, input, and state"],
    observation_to_capture: ["previous/current/next Action", "raw input", "state flags", "Legacy handling"],
    legacy_expected: "Legacy behavior is unchanged.",
    shadow_expected: `Ownership remains ${representativeUnmapped.classification}; no fake Move is created.`,
    decision_resolved: `Validate ${representativeUnmapped.ledger_id} ownership.`
  });
  if (representativeMechanism) cases.push({
    id: "SMOKE-REPRESENTATIVE-LEGACY-MECHANISM",
    setup: `${representativeMechanism.character} Action ${representativeMechanism.action_id}`,
    steps: ["Execute the Legacy mechanism case", "Capture matcher/recorder outcome and shadow resolution"],
    observation_to_capture: ["runtime mechanism fields", "Legacy outcome", "shadow candidates", "saved V2 facts"],
    legacy_expected: "Legacy mechanism controls production behavior.",
    shadow_expected: "Resolver observation is diagnostic and Frozen V2 facts are unchanged.",
    decision_resolved: `Validate ${representativeMechanism.subclass} ownership outside Move identity.`
  });
  return { schema: "sf6cc.real-game-smoke-packet.v1", authority: "test_plan_only", status: "UNAVAILABLE", cases };
}

export function analyzePhase2({ repoRoot, corpus, m1, m2, runtime, manifest, sourceFiles = {} }) {
  validateInputs(corpus, m1, m2, runtime, manifest);
  const m1Index = buildM1Index(m1, m2.build.build_uid);
  const m2Index = buildM2Index(m2);
  const legacy = loadLegacy(repoRoot);
  const ambiguity = ambiguityFamilies(corpus, m1Index, m2Index);
  const unmapped = unmappedFamilies(corpus, m1Index, m2Index, legacy);
  const unmappedByKey = new Map(unmapped.map((item) => [`${item.character}:${item.action_id}`, item]));
  const legacyAudit = auditLegacy(legacy, corpus, unmappedByKey, m1Index, m2Index);
  const presentation = auditPresentation(legacy);
  const policies = auditPolicies(legacy.policies);
  const stableIdentities = stableIdentityBatches(m2Index);
  const m2Review = pendingM2Review(m2, manifest);
  const humanReview = humanReviewPacket(ambiguity, stableIdentities, legacyAudit.aliases, m2Review);
  const smoke = smokePacket(ambiguity, unmapped, legacyAudit);
  const source = Object.fromEntries(Object.entries(sourceFiles).map(([key, filename]) => [key, {
    file: path.resolve(filename),
    bytes: fs.statSync(filename).size,
    sha256: sha256File(filename)
  }]));
  return {
    schema: "sf6cc.architecture-convergence-phase2.v1",
    authority: "diagnostic_only",
    auto_approved: false,
    frozen_contract: {
      production_result: "legacy",
      production_switch: "BLOCKED",
      legacy_off: "BLOCKED",
      real_game_smoke: "UNAVAILABLE",
      frozen_v2_modified: false,
      production_authority_changed: false
    },
    source,
    build: m2.build,
    summary: {
      corpus_cases: corpus.summary.step_cases,
      ambiguous_observations: ambiguity.reduce((sum, item) => sum + item.observations, 0),
      ambiguous_families: ambiguity.length,
      unmapped_observations: unmapped.reduce((sum, item) => sum + item.observations, 0),
      unmapped_families: unmapped.length,
      legacy_relation_cases: legacyAudit.relations.summary.cases,
      runtime_mechanism_records: legacyAudit.runtime_mechanisms.summary.records,
      presentation_overrides: presentation.summary.records,
      character_policies: policies.length,
      stable_identity_candidates: stableIdentities.moves
    },
    ambiguity: {
      concentration: concentration(ambiguity),
      source_matrix: Object.entries(tally(ambiguity, (item) => item.classification)).map(([cause, families]) => ({
        cause,
        families,
        observations: ambiguity.filter((item) => item.classification === cause).reduce((sum, item) => sum + item.observations, 0),
        can_resolve_offline: cause === "GENERATOR_OVERLAP",
        needs_human: ambiguity.some((item) => item.classification === cause && item.decision_requirement === "HUMAN_SEMANTIC_REVIEW_REQUIRED"),
        needs_real_game: cause === "RUNTIME_MECHANISM"
      })),
      classification_counts: tally(ambiguity, (item) => item.classification),
      decision_requirements: tally(ambiguity, (item) => item.decision_requirement),
      pure_unknown: ambiguity.filter((item) => item.classification === "UNKNOWN").length,
      family_ledger: ambiguity
    },
    unmapped: {
      concentration: concentration(unmapped),
      classification_counts: tally(unmapped, (item) => item.classification),
      observation_counts: Object.fromEntries(Object.keys(tally(unmapped, (item) => item.classification)).map((classification) => [classification,
        unmapped.filter((item) => item.classification === classification).reduce((sum, item) => sum + item.observations, 0)
      ])),
      pure_unknown: unmapped.filter((item) => item.classification === "UNKNOWN").length,
      family_ledger: unmapped
    },
    legacy: legacyAudit,
    presentation,
    character_policies: {
      records: policies,
      summary: { records: policies.length, classifications: tally(policies, (item) => item.classification) }
    },
    stable_identity_review: stableIdentities,
    m2_pending_review: m2Review,
    m5_gate_matrix: m5GateMatrix(manifest),
    shadow_consumer_coverage: {
      recording: { offline_cases: corpus.summary.step_cases, runtime_shadow_observations: null, production_authority: "LEGACY" },
      display: { offline_display_available: corpus.cases.filter((item) => item.display_status === "AVAILABLE").length, runtime_shadow_observations: null, production_authority: "LEGACY_OR_PRESENTATION" },
      detection: { offline_cases: corpus.summary.step_cases, runtime_shadow_observations: null, production_authority: "LEGACY" },
      demo: { offline_replayable_combos: corpus.summary.replayable_combos, runtime_shadow_observations: null, production_authority: "LEGACY_COMPATIBILITY" },
      playback: { offline_compatibility_cases: corpus.summary.compatibility_cases, runtime_shadow_observations: null, production_authority: "FROZEN_V2_AND_LEGACY_COMPATIBILITY" }
    },
    human_review_packet: humanReview,
    real_game_smoke_packet: smoke,
    offline_exhaustion: {
      decision_independent_work_remaining: [],
      decision_dependent_blocks: [
        "245 ambiguity families require semantic review; representative runtime-mechanism cases also need live capture.",
        "M2 unresolved rows/extensions/transitions require human contract decisions or a pinned raw accessor contract.",
        "273 migration links and 3023 provisional Move identities require human review.",
        "Real-game smoke is unavailable."
      ],
      production_switch: "BLOCKED",
      legacy_off: "BLOCKED"
    }
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
  for (const required of ["corpus-report", "m1", "m2", "manifest", "runtime"]) {
    if (!args[required]) throw new Error(`Missing --${required}`);
  }
  const filenames = {
    corpus_report: path.resolve(args["corpus-report"]),
    m1: path.resolve(args.m1),
    m2: path.resolve(args.m2),
    manifest: path.resolve(args.manifest),
    runtime: path.resolve(args.runtime)
  };
  const report = analyzePhase2({
    repoRoot: args.repo ? path.resolve(args.repo) : process.cwd(),
    corpus: readJson(filenames.corpus_report),
    m1: readJson(filenames.m1),
    m2: readJson(filenames.m2),
    manifest: readJson(filenames.manifest),
    runtime: readJson(filenames.runtime),
    sourceFiles: filenames
  });
  const output = `${JSON.stringify(report, null, 2)}\n`;
  if (args.out) {
    const outputFile = path.resolve(args.out);
    fs.mkdirSync(path.dirname(outputFile), { recursive: true });
    fs.writeFileSync(outputFile, output);
  } else {
    process.stdout.write(output);
  }
}
