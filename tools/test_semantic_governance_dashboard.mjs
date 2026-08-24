import assert from "node:assert/strict";
import crypto from "node:crypto";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

import {
  analyzeRepository,
  renderDashboard,
} from "./semantic_governance_dashboard.mjs";

function writeJson(root, relativePath, value) {
  const filename = path.join(root, relativePath);
  fs.mkdirSync(path.dirname(filename), { recursive: true });
  fs.writeFileSync(filename, `${JSON.stringify(value, null, 2)}\n`, "utf8");
  return filename;
}

function sha256(filename) {
  return crypto.createHash("sha256").update(fs.readFileSync(filename)).digest("hex");
}

const root = fs.mkdtempSync(path.join(os.tmpdir(), "sf6cc-governance-dashboard-"));

try {
  writeJson(root, "data/SF6CC/version.json", {
    schema: "sf6cc.product_version.v1",
    product: { id: "sf6cc", version: "9.9.9" },
  });
  writeJson(root, "data/TrainingComboTrials_data/exceptions/Common.json", {
    1: { ignore: true },
  });
  writeJson(root, "data/TrainingComboTrials_data/exceptions/Ryu.json", {
    10: { force: true },
    11: { absorb_ids: "12" },
    _character: { allow_pending_absorb: true },
  });

  const generatedFile = writeJson(
    root,
    "data/TrainingComboTrials_data/generated_semantics/Ryu.json",
    { 20: { absorb_ids: "21" } },
  );
  writeJson(root, "data/TrainingComboTrials_data/generated_semantics/manifest.v1.json", {
    schema: "sf6acbcm.sf6cc-generated-semantics-manifest.v1",
    algorithm_version: "fixture.v1",
    artifacts: [{
      file: "Ryu.json",
      bytes: fs.statSync(generatedFile).size,
      sha256: sha256(generatedFile),
    }],
    projections: [{ character: "Ryu", owner_action_id: 20 }],
  });

  writeJson(root, "data/TrainingComboTrials_data/command_display/Ryu.json", {
    10: {
      classic_command: { display: "LP", inputs: ["LP"] },
      ownership: "direct",
      source: "ac_bcm+capcom_official_semantics",
      routes: [{ source: "bcm_profile" }],
    },
    11: {
      classic_command: { display: "MP", inputs: ["MP"] },
      ownership: "direct",
      source: "ac_bcm+capcom_official_semantics",
      routes: [{ source: "bcm_profile" }],
    },
    _meta: {
      schema: "xt.command_display.v1",
      character: "Ryu",
      generated_from: "ac_bcm+capcom_official_semantics",
    },
  });
  writeJson(root, "data/TrainingComboTrials_data/command_display_overrides/Ryu.json", {
    schema: "xt.command_display_overrides.v1",
    character: "Ryu",
    entries: {
      10: { classic: "LP", evidence: "fixture inactive override" },
      11: { classic: "MP", replace: true, evidence: "fixture replacement" },
      12: { classic: "HP", evidence: "fixture missing-action addition" },
    },
    presentation_contexts: {
      11: {
        labels: { "zh-CN": "状态中", "en-US": "During state" },
        separate_line: true,
        strip_followup_prefix: true,
        evidence: "fixture context",
      },
    },
    contextual_internal_phases: {
      12: { owner_ids: [11], evidence: "fixture phase" },
    },
  });
  writeJson(root, "data/TrainingComboTrials_data/action_compatibility/Ryu.json", {
    schema: "xt.action_compatibility.v1",
    character: "Ryu",
    entries: [{
      recorded_action_id: 100,
      runtime_action_id: 101,
      recorded_motions: ["236+P"],
      evidence: "fixture compatibility",
    }],
  });

  const report = analyzeRepository(root);
  assert.equal(report.product.version, "9.9.9");
  assert.deepEqual(report.summary.action_semantics, {
    handwritten: 3,
    generated: 1,
    total: 4,
    generated_percent: 25,
  });
  assert.equal(report.summary.character_policies, 1);
  assert.deepEqual(report.summary.command_display, {
    generated_base: 2,
    generated_effective: 1,
    override_declarations: 3,
    override_effective: 2,
    override_replace: 1,
    override_add: 1,
    override_inactive: 1,
    final_actions: 3,
    generated_percent: 33.33,
    override_percent: 66.67,
    routes: 2,
  });
  assert.equal(report.summary.presentation_context_rules, 2);
  assert.equal(report.summary.compatibility_mappings, 1);
  assert.equal(report.summary.governance_records, 9);
  assert.equal(report.characters.Ryu.handwritten_action_rules, 2);
  assert.equal(report.characters.Ryu.generated_action_rules, 1);
  assert.equal(report.characters.Ryu.effective_display_overrides, 2);
  assert(report.findings.some((item) => item.code === "INACTIVE_DISPLAY_OVERRIDE"
    && item.character === "Ryu" && item.action_id === 10));
  assert(!report.findings.some((item) => item.code === "GENERATED_ARTIFACT_HASH_MISMATCH"));

  const html = renderDashboard(report);
  assert.match(html, /<!doctype html>/i);
  assert.match(html, /SF6CC Semantic Governance Dashboard/);
  assert.match(html, /语义治理总览/);
  assert.match(html, /INACTIVE_DISPLAY_OVERRIDE/);
  assert(!/https?:\/\//i.test(html), "dashboard must remain fully offline");
  const scriptStart = html.indexOf("<script>") + "<script>".length;
  const scriptEnd = html.indexOf("</script>", scriptStart);
  assert(scriptStart >= "<script>".length && scriptEnd > scriptStart);
  assert.doesNotThrow(() => new Function(html.slice(scriptStart, scriptEnd)),
    "generated dashboard client script must parse independently");

  const cliOutput = path.join(root, "audit-output", "governance.html");
  const cli = spawnSync(process.execPath, [
    fileURLToPath(new URL("./semantic_governance_dashboard.mjs", import.meta.url)),
    "--repo-root", root,
    "--output", cliOutput,
  ], { encoding: "utf8", windowsHide: true });
  assert.equal(cli.status, 0, cli.stderr || cli.stdout);
  assert.equal(fs.existsSync(cliOutput), true);
  assert.match(fs.readFileSync(cliOutput, "utf8"), /9\.9\.9/);

  const lfSource = fs.readFileSync(generatedFile, "utf8");
  fs.writeFileSync(generatedFile, lfSource.replaceAll("\n", "\r\n"), "utf8");
  const windowsCheckout = analyzeRepository(root);
  assert(!windowsCheckout.findings.some((item) =>
    item.code === "GENERATED_ARTIFACT_HASH_MISMATCH"
      || item.code === "GENERATED_ARTIFACT_SIZE_MISMATCH"),
  "CRLF checkout must verify against the canonical LF manifest bytes");

  fs.appendFileSync(generatedFile, " ", "utf8");
  const damaged = analyzeRepository(root);
  assert(damaged.findings.some((item) =>
    item.code === "GENERATED_ARTIFACT_HASH_MISMATCH"));
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}

console.log("semantic governance dashboard tests passed");
