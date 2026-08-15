import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { analyzePhase2 } from "./architecture_convergence_phase2.mjs";

const root = fs.mkdtempSync(path.join(os.tmpdir(), "sf6cc-phase2-"));
const repoRoot = path.join(root, "repo");
const dataRoot = path.join(repoRoot, "data", "TrainingComboTrials_data");
fs.mkdirSync(path.join(dataRoot, "exceptions"), { recursive: true });
fs.mkdirSync(path.join(dataRoot, "command_display_overrides"), { recursive: true });
fs.mkdirSync(path.join(dataRoot, "action_compatibility"), { recursive: true });
fs.writeFileSync(path.join(dataRoot, "exceptions", "Ryu.json"), JSON.stringify({
  37: { force: true },
  600: { absorb_ids: "601", force: true },
  _character: { sequence_grouping: { break_followup_after_ids: "700" } }
}));
fs.writeFileSync(path.join(dataRoot, "command_display_overrides", "Ryu.json"), JSON.stringify({
  schema: "sf6cc.command-display-overrides.v1",
  character: "Ryu",
  entries: { 650: { classic: "2+MP", replace: true, evidence: "synthetic" } }
}));
fs.writeFileSync(path.join(dataRoot, "action_compatibility", "Ryu.json"), JSON.stringify({
  schema: "xt.action_compatibility.v1",
  character: "Ryu",
  entries: [{ recorded_action_id: 999, runtime_action_id: 700, evidence: "synthetic" }]
}));

const build = { build_uid: "build-test", display_version: "test" };
const anchor = (uid, owner, trigger, notation) => ({
  anchor_route_uid: uid,
  owner_action_id: owner,
  trigger_index: trigger,
  condition_hash: `${uid}-condition`,
  has_enabled_profile: true,
  profiles: [{ profile_name: "norm", normalized_notation: notation, enabled: true }]
});
const family = (uid, anchorUid, owner) => ({
  family_uid: uid,
  anchor_route_uids: [anchorUid],
  owners: [{ action_id: owner }]
});
const membership = (uid, actionId) => ({
  membership_uid: uid,
  action_id: actionId,
  role: "primary",
  strictness: "STRICT",
  evidence: { family_uids: [] }
});
const move = (uid, familyUid, actionId, membershipUid, notation, anchorUid, trigger) => ({
  move_uid: uid,
  family_uids: [familyUid],
  disabled_only: false,
  duplicate_owners: false,
  revision: {
    memberships: [membership(membershipUid, actionId)],
    command_revisions: [{ profile_name: "norm", normalized_notation: notation, enabled: true }],
    bcm_anchor_revisions: [{ owner_action_id: actionId, trigger_index: trigger, anchor_route_uid: anchorUid }]
  }
});

const m1 = {
  schema: "sf6acbcm.m1-extraction.v1",
  builds: [{
    build,
    characters: [{
      key: { ...build, character: "Ryu", fighter_id: 1 },
      anchor_routes: [
        anchor("route-1", 500, 1, "66"),
        anchor("route-2", 500, 2, "Parry"),
        anchor("route-3", 700, 3, "236+P")
      ],
      route_families: [
        family("family-1", "route-1", 500),
        family("family-2", "route-2", 500),
        family("family-3", "route-3", 700)
      ]
    }]
  }]
};

const census = (actionId, representation, sourceScope, edges = 0) => ({
  action_census_uid: `census-${actionId}`,
  action_id: actionId,
  representation,
  source_scope: sourceScope,
  membership_uids: representation === "membership" ? [`membership-${actionId}`] : [],
  inbound_edge_count: edges,
  outbound_edge_count: 0,
  reasons: [representation === "membership" ? "represented_by_move_membership" : "no_proven_move_membership"]
});
const m2 = {
  schema: "sf6acbcm.m2-current-graph.v1",
  build,
  characters: [{
    key: { ...build, character: "Ryu", fighter_id: 1 },
    moves: [
      move("move-1", "family-1", 500, "membership-500-a", "66", "route-1", 1),
      move("move-2", "family-2", 500, "membership-500-b", "Parry", "route-2", 2),
      move("move-3", "family-3", 700, "membership-700", "236+P", "route-3", 3)
    ],
    action_census: {
      character_scope: [
        census(37, "system_or_unanchored", "character", 0),
        { ...census(500, "membership", "character"), membership_uids: ["membership-500-a", "membership-500-b"] },
        census(600, "membership", "character"),
        census(601, "system_or_unanchored", "character", 1),
        census(650, "system_or_unanchored", "character", 0),
        census(700, "membership", "character")
      ],
      common_scope: [census(50, "system_or_unanchored", "common", 0)]
    }
  }]
};

const runtime = {
  schema: "sf6acbcm.runtime-current.v1",
  authority: "current_semantic_candidate_only",
  build,
  characters: []
};
const manifest = {
  schema: "sf6acbcm.m5-export-manifest.v1",
  authority: "current_semantic_candidate_only",
  auto_approved: false,
  build,
  ready: { artifact_set: true, review_complete: false, integration_candidate: false },
  approval_coverage: { moves: 3, stable_identities: 0 },
  unresolved: { rows: 1, transitions: 1 }
};
const corpus = {
  schema: "sf6cc.architecture-convergence-corpus.v1",
  source: { build },
  summary: { step_cases: 8, replayable_combos: 1, compatibility_cases: 1 },
  cases: [
    { file: "a.json", character: "Ryu", recorded_action_id: 500, recorded_motion: "RAW DR", resolution_status: "AMBIGUOUS", display_status: "AVAILABLE" },
    { file: "b.json", character: "Ryu", recorded_action_id: 500, recorded_motion: "Parry", resolution_status: "AMBIGUOUS", display_status: "AVAILABLE" },
    { file: "a.json", character: "Ryu", recorded_action_id: 37, recorded_motion: "9", resolution_status: "NOT_FOUND", display_status: "AVAILABLE" },
    { file: "a.json", character: "Ryu", recorded_action_id: 50, recorded_motion: "Normal", resolution_status: "NOT_FOUND", display_status: "MISSING" },
    { file: "a.json", character: "Ryu", recorded_action_id: 601, recorded_motion: null, resolution_status: "NOT_FOUND", display_status: "MISSING" },
    { file: "a.json", character: "Ryu", recorded_action_id: 650, recorded_motion: "2+MP", resolution_status: "NOT_FOUND", display_status: "AVAILABLE" },
    { file: "a.json", character: "Ryu", recorded_action_id: 999, recorded_motion: "legacy", resolution_status: "NOT_FOUND", display_status: "MISSING" },
    { file: "a.json", character: "Ryu", recorded_action_id: 700, recorded_motion: "236+P", resolution_status: "PROVISIONAL", display_status: "AVAILABLE" }
  ],
  legacy_family_cases: [{
    case_uid: "Ryu:600:absorb_ids:601",
    character: "Ryu",
    owner_action_id: 600,
    related_action_id: 601,
    legacy_classification: "MATCH",
    candidate_classification: "NOT_COMPARABLE",
    difference_category: "UNKNOWN",
    owner_resolution: "PROVISIONAL",
    related_resolution: "NOT_FOUND",
    runtime_mechanism_fields: ["force"],
    shared_current_move_uids: []
  }]
};

const report = analyzePhase2({ repoRoot, corpus, m1, m2, runtime, manifest });
assert.equal(report.frozen_contract.production_result, "legacy");
assert.equal(report.frozen_contract.production_authority_changed, false);
assert.equal(report.ambiguity.family_ledger.length, 1);
assert.equal(report.ambiguity.family_ledger[0].first_ambiguity_layer, "M1_ROUTE_FAMILY");
assert.equal(report.ambiguity.family_ledger[0].classification, "RUNTIME_MECHANISM");
assert.equal(report.unmapped.family_ledger.find((item) => item.action_id === 50).classification, "SYSTEM_ACTION");
assert.equal(report.unmapped.family_ledger.find((item) => item.action_id === 601).classification, "TRANSITION_ACTION");
assert.equal(report.unmapped.family_ledger.find((item) => item.action_id === 650).classification, "PRESENTATION_ACTION");
assert.equal(report.unmapped.family_ledger.find((item) => item.action_id === 999).classification, "LEGACY_ONLY");
assert.equal(report.legacy.relations.cases[0].offline_category, "OFFLINE_PROVABLE_NOT_IMPLEMENTED");
assert.equal(report.legacy.runtime_mechanisms.summary.subclasses.PARTICIPATION_CONTROL, 2);
assert.equal(report.presentation.summary.identity_affecting, 0);
assert.equal(report.character_policies.records[0].classification, "FOLLOWUP_GROUPING_POLICY");
assert.equal(report.stable_identity_review.moves, 3);
assert.equal(report.m5_gate_matrix.find((item) => item.gate === "real_game_smoke").current, "UNAVAILABLE");

const first = JSON.stringify(report);
const second = JSON.stringify(analyzePhase2({ repoRoot, corpus, m1, m2, runtime, manifest }));
assert.equal(crypto.createHash("sha256").update(first).digest("hex"),
  crypto.createHash("sha256").update(second).digest("hex"), "Phase 2 analysis must be deterministic");

console.log("Architecture convergence Phase 2 tests passed");
