import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { analyzeCorpus } from "./architecture_convergence_corpus.mjs";

const root = fs.mkdtempSync(path.join(os.tmpdir(), "sf6cc-convergence-corpus-"));
const repoRoot = path.join(root, "repo");
const corpusRoot = path.join(root, "corpus");
const artifactRoot = path.join(root, "artifact");
const dataRoot = path.join(repoRoot, "data", "TrainingComboTrials_data");
fs.mkdirSync(path.join(dataRoot, "command_display"), { recursive: true });
fs.mkdirSync(path.join(dataRoot, "exceptions"), { recursive: true });
fs.mkdirSync(path.join(dataRoot, "action_compatibility"), { recursive: true });
fs.mkdirSync(corpusRoot, { recursive: true });
fs.mkdirSync(artifactRoot, { recursive: true });

fs.writeFileSync(path.join(dataRoot, "command_display", "Ryu.json"), JSON.stringify({
  600: { classic_command: { display: "LP" } },
  602: { classic_command: { display: "MP" } }
}));
fs.writeFileSync(path.join(dataRoot, "exceptions", "Ryu.json"), JSON.stringify({
  600: { action_alias_ids: "601" }
}));
fs.writeFileSync(path.join(dataRoot, "action_compatibility", "Ryu.json"), JSON.stringify({
  schema: "sf6cc.action_compatibility.v1",
  character: "Ryu",
  entries: [{
    recorded_action_id: 500,
    runtime_action_id: 600,
    evidence: "synthetic compatibility evidence"
  }]
}));
fs.writeFileSync(path.join(corpusRoot, "Ryu_combo.json"), JSON.stringify([
  { id: 600, motion: "LP", timeline: ["1f : LP"], _xt_meta: { character: "Ryu" } },
  { id: 602, motion: "MP" },
  { id: 500, motion: "legacy" },
  { id: 999, motion: "unknown" }
]));

const runtime = {
  schema: "sf6acbcm.runtime-current.v1",
  algorithm_version: "m5-export.v1",
  authority: "current_semantic_candidate_only",
  auto_approved: false,
  build: { build_uid: "build_test", display_version: "2026-08-03" },
  characters: [{
    fighter_id: 1,
    character: "Ryu",
    transitions: [],
    moves: [
      {
        current_move_uid: "move_a",
        stable_move_uid: null,
        provisional: true,
        memberships: [
          { action_id: 600, role: "primary", strictness: "STRICT" },
          { action_id: 601, role: "alias", strictness: "STRICT" }
        ]
      },
      {
        current_move_uid: "move_b",
        stable_move_uid: null,
        provisional: true,
        memberships: [{ action_id: 602, role: "primary", strictness: "STRICT" }]
      }
    ]
  }]
};
const runtimeRaw = Buffer.from(`${JSON.stringify(runtime)}\n`);
const runtimeFile = path.join(artifactRoot, "runtime-current.v1.json");
fs.writeFileSync(runtimeFile, runtimeRaw);
const manifest = {
  schema: "sf6acbcm.m5-export-manifest.v1",
  algorithm_version: "m5-export.v1",
  authority: "current_semantic_candidate_only",
  auto_approved: false,
  build: runtime.build,
  ready: { artifact_set: true, review_complete: false, integration_candidate: false },
  artifacts: {
    runtime_current: {
      file: "runtime-current.v1.json",
      bytes: runtimeRaw.length,
      sha256: crypto.createHash("sha256").update(runtimeRaw).digest("hex")
    }
  }
};
const manifestFile = path.join(artifactRoot, "export-manifest.v1.json");
fs.writeFileSync(manifestFile, JSON.stringify(manifest));

try {
  const report = analyzeCorpus({ repoRoot, corpusRoot, manifestFile, runtimeFile });
  assert.equal(report.summary.json_files_scanned, 1);
  assert.equal(report.summary.parsed_combos, 1);
  assert.equal(report.summary.replayable_combos, 1);
  assert.equal(report.summary.step_cases, 4);
  assert.equal(report.summary.comparable_cases, 2);
  assert.equal(report.summary.exact_current_move_resolutions, 2);
  assert.equal(report.summary.semantic_matches, 1);
  assert.equal(report.summary.expected_differences, 1);
  assert.equal(report.summary.unexpected_differences, 0);
  assert.equal(report.summary.unknown_cases, 2);
  assert.equal(report.summary.blocked_cases, 2);
  assert.equal(report.readiness.production_authority_unchanged, true);
  assert.equal(report.legacy_family_cases[0].candidate_classification, "SAME_MOVE");
  assert.equal(report.compatibility_cases[0].classification, "COMPATIBILITY_REQUIRED");
  assert.equal(JSON.stringify(report), JSON.stringify(analyzeCorpus({
    repoRoot, corpusRoot, manifestFile, runtimeFile
  })), "analysis must be deterministic for identical inputs");
  console.log("Architecture convergence corpus tests passed");
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
