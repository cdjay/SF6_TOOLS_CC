#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_REPO_ROOT = path.resolve(SCRIPT_DIR, "..");
const DATA_RELATIVE = path.join("data", "TrainingComboTrials_data");
const SEVERITY_ORDER = { error: 0, warning: 1, info: 2 };

function round(value, digits = 2) {
  const factor = 10 ** digits;
  return Math.round((Number(value) + Number.EPSILON) * factor) / factor;
}

function percent(part, total) {
  return total > 0 ? round((part / total) * 100) : 0;
}

function sha256(buffer) {
  return crypto.createHash("sha256").update(buffer).digest("hex");
}

function relative(root, filename) {
  return path.relative(root, filename).replaceAll("\\", "/");
}

function jsonFiles(directory) {
  if (!fs.existsSync(directory)) return [];
  return fs.readdirSync(directory, { withFileTypes: true })
    .filter((entry) => entry.isFile() && entry.name.endsWith(".json"))
    .map((entry) => path.join(directory, entry.name))
    .sort((left, right) => left.localeCompare(right));
}

function numericKeys(document) {
  return Object.keys(document ?? {}).filter((key) => /^\d+$/.test(key));
}

function objectKeys(value) {
  return value && typeof value === "object" && !Array.isArray(value)
    ? Object.keys(value)
    : [];
}

function runGit(root, args) {
  const result = spawnSync("git", args, {
    cwd: root,
    encoding: "utf8",
    windowsHide: true,
    stdio: ["ignore", "pipe", "ignore"],
  });
  return result.status === 0 ? result.stdout.trim() : null;
}

function gitState(root) {
  const branch = runGit(root, ["branch", "--show-current"]);
  const head = runGit(root, ["rev-parse", "HEAD"]);
  const status = runGit(root, ["status", "--porcelain"]);
  const subject = runGit(root, ["log", "-1", "--pretty=%s"]);
  const upstream = runGit(root, ["rev-parse", "--abbrev-ref", "@{upstream}"]);
  let ahead = null;
  let behind = null;
  if (upstream) {
    const counts = runGit(root, ["rev-list", "--left-right", "--count", `HEAD...${upstream}`]);
    const match = counts?.match(/^(\d+)\s+(\d+)$/);
    if (match) {
      ahead = Number(match[1]);
      behind = Number(match[2]);
    }
  }
  return {
    branch: branch || "unknown",
    head_sha: head || "unknown",
    head_short: head ? head.slice(0, 8) : "unknown",
    commit_subject: subject || "unknown",
    clean: status === null ? null : status === "",
    upstream: upstream || null,
    ahead,
    behind,
  };
}

function productVersion(root, findings) {
  const filename = path.join(root, "data", "SF6CC", "version.json");
  if (!fs.existsSync(filename)) return "unknown";
  try {
    const document = JSON.parse(fs.readFileSync(filename, "utf8"));
    return String(
      document.product?.version
        ?? document.version
        ?? document.product_version
        ?? "unknown",
    );
  } catch (error) {
    findings.push({
      severity: "error",
      code: "INVALID_VERSION_JSON",
      message: `版本文件无法解析：${error.message}`,
      file: relative(root, filename),
    });
    return "unknown";
  }
}

function readJson(root, filename, findings, area) {
  try {
    return JSON.parse(fs.readFileSync(filename, "utf8"));
  } catch (error) {
    findings.push({
      severity: "error",
      code: "INVALID_JSON",
      area,
      message: `JSON 无法解析：${error.message}`,
      file: relative(root, filename),
    });
    return null;
  }
}

function ensureCharacter(characters, character) {
  if (!character || character === "Common" || character === "Unknown") return null;
  characters[character] ??= {
    handwritten_action_rules: 0,
    generated_action_rules: 0,
    character_policies: 0,
    generated_display_actions: 0,
    generated_display_routes: 0,
    effective_generated_display_actions: 0,
    display_override_declarations: 0,
    effective_display_overrides: 0,
    inactive_display_overrides: 0,
    presentation_context_rules: 0,
    compatibility_mappings: 0,
    final_display_actions: 0,
  };
  return characters[character];
}

function countFields(target, rule) {
  if (!rule || typeof rule !== "object" || Array.isArray(rule)) return;
  for (const field of Object.keys(rule)) target[field] = (target[field] ?? 0) + 1;
}

// manifest.json is written by tools/action_runtime_compiler/build_generated_semantics.js;
// manifest.v1.json was the SF6ACBCM pilot manifest.
const GENERATED_MANIFESTS = Object.freeze({
  "manifest.json": "sf6cc.generated-character-semantics-manifest.v2",
  "manifest.v1.json": "sf6acbcm.sf6cc-generated-semantics-manifest.v1",
});

function inspectManifest(root, directory, generatedFiles, findings) {
  const name = Object.keys(GENERATED_MANIFESTS)
    .find((candidate) => fs.existsSync(path.join(directory, candidate))) ?? "manifest.json";
  const filename = path.join(directory, name);
  if (!fs.existsSync(filename)) {
    if (generatedFiles.length > 0) findings.push({
      severity: "error",
      code: "GENERATED_MANIFEST_MISSING",
      message: "存在生成语义资产，但 manifest.json 缺失。",
      file: relative(root, filename),
    });
    return { algorithm_version: null, projection_count: 0 };
  }
  const manifest = readJson(root, filename, findings, "generated_semantics");
  if (!manifest) return { algorithm_version: null, projection_count: 0 };
  const expectedSchema = GENERATED_MANIFESTS[name];
  if (manifest.schema !== expectedSchema) findings.push({
    severity: "error",
    code: "GENERATED_MANIFEST_SCHEMA_INVALID",
    message: `生成语义 Manifest schema 不是 ${expectedSchema}。`,
    file: relative(root, filename),
  });

  const declared = new Set();
  for (const artifact of Array.isArray(manifest.artifacts) ? manifest.artifacts : []) {
    if (!artifact || typeof artifact.file !== "string") continue;
    declared.add(artifact.file);
    const artifactFile = path.join(directory, artifact.file);
    if (!fs.existsSync(artifactFile)) {
      findings.push({
        severity: "error",
        code: "GENERATED_ARTIFACT_MISSING",
        message: `Manifest 声明的生成资产不存在：${artifact.file}`,
        file: relative(root, filename),
      });
      continue;
    }
    const bytes = fs.readFileSync(artifactFile);
    const normalizedBytes = Buffer.from(
      bytes.toString("utf8").replaceAll("\r\n", "\n"),
      "utf8",
    );
    const expectedBytes = Number(artifact.bytes);
    const expectedHash = String(artifact.sha256 ?? "").toLowerCase();
    const rawMatches = expectedBytes === bytes.length
      && expectedHash === sha256(bytes);
    const normalizedMatches = expectedBytes === normalizedBytes.length
      && expectedHash === sha256(normalizedBytes);
    if (!rawMatches && !normalizedMatches && expectedBytes !== bytes.length) findings.push({
      severity: "error",
      code: "GENERATED_ARTIFACT_SIZE_MISMATCH",
      message: `${artifact.file} 的字节数与 Manifest 不一致。`,
      file: relative(root, artifactFile),
      expected: expectedBytes,
      actual: bytes.length,
    });
    const actualHash = sha256(bytes);
    if (!rawMatches && !normalizedMatches) findings.push({
      severity: "error",
      code: "GENERATED_ARTIFACT_HASH_MISMATCH",
      message: `${artifact.file} 的 SHA-256 与 Manifest 不一致。`,
      file: relative(root, artifactFile),
      expected: artifact.sha256 ?? null,
      actual: actualHash,
    });
  }
  for (const generatedFile of generatedFiles) {
    const basename = path.basename(generatedFile);
    if (!declared.has(basename)) findings.push({
      severity: "warning",
      code: "GENERATED_ARTIFACT_UNDECLARED",
      message: `${basename} 未被生成语义 Manifest 收录。`,
      file: relative(root, generatedFile),
    });
  }
  return {
    algorithm_version: manifest.algorithm_version ?? null,
    projection_count: Array.isArray(manifest.projections) ? manifest.projections.length : 0,
    projections: Array.isArray(manifest.projections) ? manifest.projections : [],
  };
}

function inspectCodeHardcodes(root, knownCharacters) {
  const roots = [
    path.join(root, "autorun", "TrainingComboTrials_v1.0.lua"),
    path.join(root, "autorun", "SF6_DistanceViewer.lua"),
    path.join(root, "autorun", "func", "ComboTrials_UI.lua"),
    path.join(root, "autorun", "func", "ComboTrials"),
  ];
  const files = [];
  for (const candidate of roots) {
    if (!fs.existsSync(candidate)) continue;
    const stat = fs.statSync(candidate);
    if (stat.isFile()) files.push(candidate);
    if (stat.isDirectory()) {
      for (const entry of fs.readdirSync(candidate, { withFileTypes: true })) {
        if (entry.isFile() && entry.name.endsWith(".lua")) {
          files.push(path.join(candidate, entry.name));
        }
      }
    }
  }
  const names = [...knownCharacters]
    .filter((name) => name !== "Unknown" && name !== "Common")
    .sort((left, right) => right.length - left.length);
  if (names.length === 0) return { character_conditions: [], policy_characters: [] };
  const escaped = names.map((name) => name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"));
  const condition = new RegExp(
    `\\b(profile_name|character_name|char_name|character)\\s*(==|~=)\\s*"(${escaped.join("|")})"`,
    "g",
  );
  const characterConditions = [];
  const policyCharacters = new Set();
  for (const filename of files) {
    const lines = fs.readFileSync(filename, "utf8").split(/\r?\n/);
    let inPolicyTable = false;
    for (let index = 0; index < lines.length; index += 1) {
      const code = lines[index].replace(/--.*$/, "");
      if (/^\s*local\s+POLICIES\s*=\s*{/.test(code)) inPolicyTable = true;
      if (inPolicyTable && /^\s*local\s+function\s+policy\b/.test(code)) inPolicyTable = false;
      if (inPolicyTable) {
        const policy = code.match(/^\s{4}([A-Za-z][A-Za-z0-9_]*)\s*=\s*{/);
        if (policy && names.includes(policy[1])) policyCharacters.add(policy[1]);
      }
      for (const match of code.matchAll(condition)) {
        characterConditions.push({
          file: relative(root, filename),
          line: index + 1,
          subject: match[1],
          operator: match[2],
          character: match[3],
          excerpt: code.trim(),
        });
      }
    }
  }
  return {
    character_conditions: characterConditions,
    policy_characters: [...policyCharacters].sort(),
  };
}

function sortObject(value) {
  return Object.fromEntries(Object.entries(value).sort(([left], [right]) =>
    left.localeCompare(right)));
}

export function analyzeRepository(repoRoot = DEFAULT_REPO_ROOT) {
  const root = path.resolve(repoRoot);
  const dataRoot = path.join(root, DATA_RELATIVE);
  const findings = [];
  const characters = {};
  const handwrittenFields = {};
  const generatedFields = {};
  const ownership = {};
  const generatorSources = {};
  const documents = {
    exceptions: {},
    generated: {},
    display: {},
  };

  let handwritten = 0;
  let generated = 0;
  let policies = 0;
  let displayBase = 0;
  let displayRoutes = 0;
  let overrideDeclarations = 0;
  let overrideReplace = 0;
  let overrideAdd = 0;
  let overrideInactive = 0;
  let presentationContexts = 0;
  let compatibilityMappings = 0;

  const exceptionDir = path.join(dataRoot, "exceptions");
  for (const filename of jsonFiles(exceptionDir)) {
    const character = path.basename(filename, ".json");
    const document = readJson(root, filename, findings, "exceptions");
    if (!document) continue;
    documents.exceptions[character] = document;
    const row = ensureCharacter(characters, character);
    const actions = numericKeys(document);
    handwritten += actions.length;
    if (row) row.handwritten_action_rules += actions.length;
    for (const actionId of actions) countFields(handwrittenFields, document[actionId]);
    if (document._character && typeof document._character === "object") {
      policies += 1;
      if (row) row.character_policies += 1;
    }
  }

  const generatedDir = path.join(dataRoot, "generated_semantics");
  const generatedFiles = jsonFiles(generatedDir)
    .filter((filename) => !Object.hasOwn(GENERATED_MANIFESTS, path.basename(filename)));
  for (const filename of generatedFiles) {
    const character = path.basename(filename, ".json");
    const document = readJson(root, filename, findings, "generated_semantics");
    if (!document) continue;
    documents.generated[character] = document;
    const row = ensureCharacter(characters, character);
    const actions = numericKeys(document);
    generated += actions.length;
    if (row) row.generated_action_rules += actions.length;
    for (const actionId of actions) {
      countFields(generatedFields, document[actionId]);
      if (documents.exceptions[character]?.[actionId] !== undefined) findings.push({
        severity: "error",
        code: "GENERATED_LEGACY_COLLISION",
        message: `${character} Action ${actionId} 同时存在于手写与生成语义中。`,
        file: relative(root, filename),
        character,
        action_id: Number(actionId),
      });
    }
  }
  const generatedManifest = inspectManifest(root, generatedDir, generatedFiles, findings);
  const manifestProjectionKeys = new Set((generatedManifest.projections ?? []).map((item) =>
    `${item.character}:${Number(item.owner_action_id)}`));
  for (const [character, document] of Object.entries(documents.generated)) {
    for (const actionId of numericKeys(document)) {
      if (!manifestProjectionKeys.has(`${character}:${Number(actionId)}`)) findings.push({
        severity: "warning",
        code: "GENERATED_PROJECTION_EVIDENCE_MISSING",
        message: `${character} Action ${actionId} 没有对应的 Manifest projection。`,
        character,
        action_id: Number(actionId),
      });
    }
  }

  const displayDir = path.join(dataRoot, "command_display");
  for (const filename of jsonFiles(displayDir)) {
    const character = path.basename(filename, ".json");
    const document = readJson(root, filename, findings, "command_display");
    if (!document) continue;
    documents.display[character] = document;
    const row = ensureCharacter(characters, character);
    const actions = numericKeys(document);
    displayBase += actions.length;
    if (row) row.generated_display_actions += actions.length;
    const meta = document._meta;
    if (!meta || meta.schema !== "xt.command_display.v1"
      || String(meta.character ?? "") !== character) findings.push({
      severity: "error",
      code: "COMMAND_DISPLAY_CONTRACT_INVALID",
      message: `${character} 生成指令表缺少有效 schema 或角色身份。`,
      file: relative(root, filename),
      character,
    });
    const source = String(meta?.generated_from ?? "unknown");
    generatorSources[source] = (generatorSources[source] ?? 0) + 1;
    for (const actionId of actions) {
      const entry = document[actionId] ?? {};
      const routes = Array.isArray(entry.routes) ? entry.routes.length : 0;
      displayRoutes += routes;
      if (row) row.generated_display_routes += routes;
      const owner = String(entry.ownership ?? "unknown");
      ownership[owner] = (ownership[owner] ?? 0) + 1;
    }
  }

  const overrideDir = path.join(dataRoot, "command_display_overrides");
  for (const filename of jsonFiles(overrideDir)) {
    const fallbackCharacter = path.basename(filename, ".json");
    const document = readJson(root, filename, findings, "command_display_overrides");
    if (!document) continue;
    const character = String(document.character ?? fallbackCharacter);
    const row = ensureCharacter(characters, character);
    if (document.schema !== "xt.command_display_overrides.v1"
      || character !== fallbackCharacter) findings.push({
      severity: "error",
      code: "DISPLAY_OVERRIDE_CONTRACT_INVALID",
      message: `${fallbackCharacter} 的展示覆盖 schema 或角色身份无效。`,
      file: relative(root, filename),
      character,
    });
    const base = documents.display[character] ?? {};
    const entries = document.entries && typeof document.entries === "object"
      && !Array.isArray(document.entries) ? document.entries : {};
    for (const [actionId, entry] of Object.entries(entries)) {
      overrideDeclarations += 1;
      if (row) row.display_override_declarations += 1;
      const exists = base[actionId] !== undefined;
      const mayReplace = entry?.replace === true;
      if (exists && mayReplace) {
        overrideReplace += 1;
        if (row) row.effective_display_overrides += 1;
      } else if (!exists) {
        overrideAdd += 1;
        if (row) row.effective_display_overrides += 1;
      } else {
        overrideInactive += 1;
        if (row) row.inactive_display_overrides += 1;
        findings.push({
          severity: "warning",
          code: "INACTIVE_DISPLAY_OVERRIDE",
          message: `${character} Action ${actionId} 已由生成表提供，但覆盖未声明 replace，因此不会生效。`,
          file: relative(root, filename),
          character,
          action_id: Number(actionId),
        });
      }
    }
    const contextCount = objectKeys(document.presentation_contexts).length
      + objectKeys(document.contextual_internal_phases).length;
    presentationContexts += contextCount;
    if (row) row.presentation_context_rules += contextCount;
  }

  const compatibilityDir = path.join(dataRoot, "action_compatibility");
  for (const filename of jsonFiles(compatibilityDir)) {
    const fallbackCharacter = path.basename(filename, ".json");
    const document = readJson(root, filename, findings, "action_compatibility");
    if (!document) continue;
    const character = String(document.character ?? fallbackCharacter);
    const row = ensureCharacter(characters, character);
    if (document.schema !== "xt.action_compatibility.v1") findings.push({
      severity: "error",
      code: "ACTION_COMPATIBILITY_CONTRACT_INVALID",
      message: `${character} 的兼容映射 schema 无效。`,
      file: relative(root, filename),
      character,
    });
    const count = Array.isArray(document.entries) ? document.entries.length : 0;
    compatibilityMappings += count;
    if (row) row.compatibility_mappings += count;
  }

  const effectiveOverrides = overrideReplace + overrideAdd;
  const effectiveGeneratedDisplay = Math.max(0, displayBase - overrideReplace);
  const finalDisplayActions = effectiveGeneratedDisplay + effectiveOverrides;
  for (const [character, row] of Object.entries(characters)) {
    const replacementCount = (() => {
      const filename = path.join(overrideDir, `${character}.json`);
      if (!fs.existsSync(filename)) return 0;
      const document = readJson(root, filename, [], "command_display_overrides") ?? {};
      const base = documents.display[character] ?? {};
      return Object.entries(document.entries ?? {}).filter(([actionId, entry]) =>
        base[actionId] !== undefined && entry?.replace === true).length;
    })();
    row.effective_generated_display_actions = row.generated_display_actions - replacementCount;
    row.final_display_actions = row.effective_generated_display_actions
      + row.effective_display_overrides;
  }

  const totalActionSemantics = handwritten + generated;
  if (totalActionSemantics > 0 && generated / totalActionSemantics < 0.25) findings.push({
    severity: "warning",
    code: "SEMANTIC_GENERATOR_COVERAGE_LOW",
    message: `Action 语义生成覆盖仅 ${generated}/${totalActionSemantics}，生产仍以 Legacy 为主。`,
  });

  const knownCharacters = new Set(Object.keys(characters));
  const codeHardcodes = inspectCodeHardcodes(root, knownCharacters);
  if (codeHardcodes.character_conditions.length > 0
    || codeHardcodes.policy_characters.length > 0) findings.push({
    severity: "info",
    code: "CHARACTER_CODE_POLICIES_PRESENT",
    message: `发现 ${codeHardcodes.character_conditions.length} 个角色条件点和 ${codeHardcodes.policy_characters.length} 个代码策略角色。`,
  });

  findings.sort((left, right) =>
    (SEVERITY_ORDER[left.severity] ?? 9) - (SEVERITY_ORDER[right.severity] ?? 9)
    || String(left.code).localeCompare(String(right.code))
    || String(left.file ?? "").localeCompare(String(right.file ?? "")));

  const ruleFamilies = {};
  for (const field of new Set([
    ...Object.keys(handwrittenFields),
    ...Object.keys(generatedFields),
  ])) {
    ruleFamilies[field] = {
      handwritten: handwrittenFields[field] ?? 0,
      generated: generatedFields[field] ?? 0,
      total: (handwrittenFields[field] ?? 0) + (generatedFields[field] ?? 0),
    };
  }

  return {
    schema: "sf6cc.semantic-governance-report.v1",
    generated_at: new Date().toISOString(),
    repository_root: root,
    product: {
      version: productVersion(root, findings),
      ...gitState(root),
      production_authority: "Legacy",
      generated_semantics_algorithm: generatedManifest.algorithm_version,
    },
    summary: {
      action_semantics: {
        handwritten,
        generated,
        total: totalActionSemantics,
        generated_percent: percent(generated, totalActionSemantics),
      },
      character_policies: policies,
      command_display: {
        generated_base: displayBase,
        generated_effective: effectiveGeneratedDisplay,
        override_declarations: overrideDeclarations,
        override_effective: effectiveOverrides,
        override_replace: overrideReplace,
        override_add: overrideAdd,
        override_inactive: overrideInactive,
        final_actions: finalDisplayActions,
        generated_percent: percent(effectiveGeneratedDisplay, finalDisplayActions),
        override_percent: percent(effectiveOverrides, finalDisplayActions),
        routes: displayRoutes,
      },
      presentation_context_rules: presentationContexts,
      compatibility_mappings: compatibilityMappings,
      governance_records: handwritten + generated + policies
        + overrideDeclarations + compatibilityMappings,
      findings: {
        error: findings.filter((item) => item.severity === "error").length,
        warning: findings.filter((item) => item.severity === "warning").length,
        info: findings.filter((item) => item.severity === "info").length,
      },
    },
    rule_families: sortObject(ruleFamilies),
    command_display_ownership: sortObject(ownership),
    command_display_generators: sortObject(generatorSources),
    characters: sortObject(characters),
    code_hardcodes: codeHardcodes,
    findings,
  };
}

function embeddedJson(value) {
  return JSON.stringify(value)
    .replaceAll("<", "\\u003c")
    .replaceAll("\u2028", "\\u2028")
    .replaceAll("\u2029", "\\u2029");
}

export function renderDashboard(report) {
  const data = embeddedJson(report);
  return `<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>SF6CC Semantic Governance Dashboard</title>
<style>
:root{color-scheme:light;--bg:#f3f5f7;--surface:#fff;--ink:#202428;--muted:#66717b;--line:#d5dadd;--strong:#30373d;--green:#1f7a4d;--green-soft:#e7f3ec;--blue:#286aa6;--blue-soft:#e8f1f8;--amber:#9a5d00;--amber-soft:#fff2d8;--red:#b22b32;--red-soft:#fbeaec;--radius:6px}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font-family:"Segoe UI","Microsoft YaHei UI",Arial,sans-serif;font-size:14px;letter-spacing:0}button,input,select{font:inherit;letter-spacing:0}
.topbar{background:#24292e;color:#fff;border-bottom:3px solid #2e8b57}.topbar-inner{max-width:1500px;margin:0 auto;padding:18px 24px 14px}.title-row{display:flex;align-items:flex-end;justify-content:space-between;gap:20px}.title-row h1{margin:0;font-size:22px;font-weight:650}.subtitle{margin-top:5px;color:#c9d0d5;font-size:13px}.build-meta{display:flex;gap:16px;flex-wrap:wrap;justify-content:flex-end;color:#dfe4e7}.build-meta b{color:#fff;font-weight:600}
.tabs{max-width:1500px;margin:0 auto;display:flex;gap:2px;padding:0 24px;background:#24292e}.tab{border:0;border-bottom:3px solid transparent;background:transparent;color:#c9d0d5;padding:10px 14px;cursor:pointer}.tab:hover,.tab:focus-visible{color:#fff;background:#31373c;outline:none}.tab.active{color:#fff;border-bottom-color:#63c38d;background:#2d3338}
main{max-width:1500px;margin:0 auto;padding:20px 24px 36px}.view{display:none}.view.active{display:block}.section-title{margin:0 0 12px;font-size:17px}.section-note{color:var(--muted);margin:-5px 0 14px}
.status-band{display:flex;align-items:center;justify-content:space-between;gap:20px;background:var(--surface);border:1px solid var(--line);border-left:5px solid var(--amber);padding:14px 16px;margin-bottom:14px}.status-main{font-size:16px;font-weight:650}.status-detail{color:var(--muted);margin-top:3px}.status-badge{white-space:nowrap;color:var(--amber);background:var(--amber-soft);border:1px solid #efcf91;padding:5px 9px;border-radius:4px;font-weight:650}
.metrics{display:grid;grid-template-columns:repeat(6,minmax(130px,1fr));gap:8px;margin-bottom:18px}.metric{background:var(--surface);border:1px solid var(--line);padding:12px;min-height:88px}.metric-label{color:var(--muted);font-size:12px}.metric-value{font-size:25px;font-weight:700;margin-top:5px}.metric-sub{color:var(--muted);font-size:12px;margin-top:3px}
.coverage-grid{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-bottom:18px}.panel{background:var(--surface);border:1px solid var(--line);padding:15px}.panel h3{font-size:14px;margin:0 0 10px}.bar{display:flex;height:18px;background:#e3e7e9;border:1px solid #cdd3d6;overflow:hidden}.bar span{display:block;height:100%}.bar .generated{background:var(--green)}.bar .legacy{background:#c6892b}.bar .override{background:var(--blue)}.bar-legend{display:flex;justify-content:space-between;gap:10px;color:var(--muted);font-size:12px;margin-top:7px}
.toolbar{display:flex;align-items:center;gap:8px;margin-bottom:10px;flex-wrap:wrap}.toolbar input,.toolbar select{height:34px;border:1px solid #bfc6ca;background:#fff;padding:0 9px;border-radius:4px}.toolbar input{min-width:260px}.count{color:var(--muted);margin-left:auto}
.table-wrap{background:var(--surface);border:1px solid var(--line);overflow:auto;max-height:calc(100vh - 230px)}table{border-collapse:separate;border-spacing:0;width:100%;min-width:860px}th,td{text-align:left;padding:8px 10px;border-bottom:1px solid #e3e6e8;vertical-align:top}th{position:sticky;top:0;z-index:1;background:#edf0f2;color:#41484e;font-size:12px;font-weight:650;border-bottom:1px solid #bbc3c8}tbody tr:hover td{background:#f7f9fa}.num{text-align:right;font-variant-numeric:tabular-nums}.mono{font-family:Consolas,"Cascadia Mono",monospace;font-size:12px}.muted{color:var(--muted)}
.severity{display:inline-block;min-width:58px;text-align:center;border-radius:4px;padding:2px 6px;font-size:12px;font-weight:650}.severity.error{color:var(--red);background:var(--red-soft)}.severity.warning{color:var(--amber);background:var(--amber-soft)}.severity.info{color:var(--blue);background:var(--blue-soft)}
.empty{padding:28px;text-align:center;color:var(--muted)}.finding-summary{display:flex;gap:8px;margin-bottom:12px}.finding-chip{padding:5px 8px;border:1px solid var(--line);background:#fff;border-radius:4px}.footer{max-width:1500px;margin:0 auto;padding:0 24px 24px;color:var(--muted);font-size:12px}
@media(max-width:1050px){.metrics{grid-template-columns:repeat(3,1fr)}.coverage-grid{grid-template-columns:1fr}.title-row{align-items:flex-start;flex-direction:column}.build-meta{justify-content:flex-start}}
@media(max-width:640px){.topbar-inner,.tabs,main,.footer{padding-left:12px;padding-right:12px}.metrics{grid-template-columns:repeat(2,1fr)}.tabs{overflow:auto}.tab{white-space:nowrap}.status-band{align-items:flex-start;flex-direction:column}.toolbar input{width:100%;min-width:0}.count{width:100%;margin-left:0}}
</style>
</head>
<body>
<header class="topbar"><div class="topbar-inner"><div class="title-row"><div><h1>SF6CC Semantic Governance Dashboard</h1><div class="subtitle">离线语义治理分析，不读取游戏运行时数据</div></div><div class="build-meta" id="build-meta"></div></div></div><nav class="tabs" aria-label="治理视图"><button class="tab active" data-view="overview">总览</button><button class="tab" data-view="characters">角色</button><button class="tab" data-view="families">规则家族</button><button class="tab" data-view="findings">主动发现</button><button class="tab" data-view="code">代码边界</button></nav></header>
<main>
<section class="view active" id="view-overview"><div id="overview"></div></section>
<section class="view" id="view-characters"><h2 class="section-title">角色覆盖</h2><p class="section-note">手工检测语义、生成语义和最终指令显示按角色分开统计。</p><div class="toolbar"><input id="character-search" type="search" placeholder="筛选角色"><span class="count" id="character-count"></span></div><div class="table-wrap"><table><thead><tr><th>角色</th><th class="num">手工语义</th><th class="num">生成语义</th><th class="num">生成显示</th><th class="num">有效覆盖</th><th class="num">上下文</th><th class="num">兼容</th><th class="num">最终显示</th></tr></thead><tbody id="character-body"></tbody></table></div></section>
<section class="view" id="view-families"><h2 class="section-title">规则家族</h2><p class="section-note">字段数量可以重叠，一条 Action 规则可能同时属于多个家族。</p><div class="toolbar"><input id="family-search" type="search" placeholder="筛选规则字段"><span class="count" id="family-count"></span></div><div class="table-wrap"><table><thead><tr><th>规则字段</th><th class="num">手工</th><th class="num">生成</th><th class="num">合计</th><th class="num">生成占比</th></tr></thead><tbody id="family-body"></tbody></table></div></section>
<section class="view" id="view-findings"><h2 class="section-title">主动发现</h2><p class="section-note">错误表示资产或合同不一致；警告表示治理缺口；信息用于定位仍存在的边界。</p><div class="finding-summary" id="finding-summary"></div><div class="toolbar"><input id="finding-search" type="search" placeholder="筛选代码、角色或文件"><select id="severity-filter"><option value="all">全部级别</option><option value="error">错误</option><option value="warning">警告</option><option value="info">信息</option></select><span class="count" id="finding-count"></span></div><div class="table-wrap"><table><thead><tr><th>级别</th><th>代码</th><th>说明</th><th>角色 / Action</th><th>文件</th></tr></thead><tbody id="finding-body"></tbody></table></div></section>
<section class="view" id="view-code"><h2 class="section-title">代码边界</h2><p class="section-note">这里只列出启发式发现的角色条件和显式策略角色，不把角色资源目录误算成语义例外。</p><div class="panel" style="margin-bottom:12px"><h3>代码策略角色</h3><div id="policy-characters" class="mono"></div></div><div class="table-wrap"><table><thead><tr><th>角色</th><th>条件对象</th><th>位置</th><th>代码</th></tr></thead><tbody id="code-body"></tbody></table></div></section>
</main><div class="footer" id="footer"></div>
<script>
const REPORT=${data};
const esc=value=>String(value??"").replace(/[&<>"']/g,ch=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[ch]));
const fmt=value=>Number(value??0).toLocaleString("zh-CN");
const shortSha=value=>String(value??"unknown").slice(0,8);
document.getElementById("build-meta").innerHTML=[\`<span>版本 <b>\${esc(REPORT.product.version)}</b></span>\`,\`<span>分支 <b>\${esc(REPORT.product.branch)}</b></span>\`,\`<span>提交 <b class="mono">\${esc(shortSha(REPORT.product.head_sha))}</b></span>\`,\`<span>工作区 <b>\${REPORT.product.clean===true?"Clean":REPORT.product.clean===false?"Dirty":"Unknown"}</b></span>\`].join("");
document.querySelectorAll(".tab").forEach(button=>button.addEventListener("click",()=>{document.querySelectorAll(".tab").forEach(item=>item.classList.toggle("active",item===button));document.querySelectorAll(".view").forEach(view=>view.classList.toggle("active",view.id===\`view-\${button.dataset.view}\`));}));
const action=REPORT.summary.action_semantics,display=REPORT.summary.command_display,findings=REPORT.summary.findings;
document.getElementById("overview").innerHTML=\`<h2 class="section-title">语义治理总览</h2><div class="status-band"><div><div class="status-main">生产权威：\${esc(REPORT.product.production_authority)}</div><div class="status-detail">Action 检测语义仍有 \${fmt(action.handwritten)} 条手工规则，生成器覆盖 \${fmt(action.generated)} / \${fmt(action.total)}。</div></div><div class="status-badge">LEGACY PRODUCTION</div></div><div class="metrics"><div class="metric"><div class="metric-label">手工 Action 语义</div><div class="metric-value">\${fmt(action.handwritten)}</div><div class="metric-sub">\${fmt(100-action.generated_percent)}%</div></div><div class="metric"><div class="metric-label">生成 Action 语义</div><div class="metric-value">\${fmt(action.generated)}</div><div class="metric-sub">\${fmt(action.generated_percent)}%</div></div><div class="metric"><div class="metric-label">有效显示覆盖</div><div class="metric-value">\${fmt(display.override_effective)}</div><div class="metric-sub">替换 \${fmt(display.override_replace)} / 补齐 \${fmt(display.override_add)}</div></div><div class="metric"><div class="metric-label">最终显示 Action</div><div class="metric-value">\${fmt(display.final_actions)}</div><div class="metric-sub">生成 \${fmt(display.generated_percent)}%</div></div><div class="metric"><div class="metric-label">历史兼容映射</div><div class="metric-value">\${fmt(REPORT.summary.compatibility_mappings)}</div><div class="metric-sub">Legacy playback only</div></div><div class="metric"><div class="metric-label">主动发现</div><div class="metric-value">\${fmt(findings.error+findings.warning)}</div><div class="metric-sub">错误 \${fmt(findings.error)} / 警告 \${fmt(findings.warning)}</div></div></div><div class="coverage-grid"><div class="panel"><h3>Action 检测语义</h3><div class="bar"><span class="generated" style="width:\${action.generated_percent}%"></span><span class="legacy" style="width:\${100-action.generated_percent}%"></span></div><div class="bar-legend"><span>生成器 \${fmt(action.generated)} (\${fmt(action.generated_percent)}%)</span><span>Legacy \${fmt(action.handwritten)}</span></div></div><div class="panel"><h3>最终指令显示</h3><div class="bar"><span class="generated" style="width:\${display.generated_percent}%"></span><span class="override" style="width:\${display.override_percent}%"></span></div><div class="bar-legend"><span>生成器 \${fmt(display.generated_effective)} (\${fmt(display.generated_percent)}%)</span><span>覆盖 \${fmt(display.override_effective)}</span></div></div></div><div class="panel"><h3>当前分析范围</h3><div class="muted">治理记录 \${fmt(REPORT.summary.governance_records)} · 角色策略 \${fmt(REPORT.summary.character_policies)} · 展示上下文 \${fmt(REPORT.summary.presentation_context_rules)} · 指令 routes \${fmt(display.routes)} · 生成算法 \${esc(REPORT.product.generated_semantics_algorithm??"未声明")}</div></div>\`;
const characterRows=Object.entries(REPORT.characters).sort((a,b)=>b[1].handwritten_action_rules-a[1].handwritten_action_rules||a[0].localeCompare(b[0]));
function renderCharacters(){const term=document.getElementById("character-search").value.trim().toLowerCase();const rows=characterRows.filter(([name])=>name.toLowerCase().includes(term));document.getElementById("character-count").textContent=\`\${rows.length} / \${characterRows.length} 个角色\`;document.getElementById("character-body").innerHTML=rows.map(([name,row])=>\`<tr><td><b>\${esc(name)}</b></td><td class="num">\${fmt(row.handwritten_action_rules)}</td><td class="num">\${fmt(row.generated_action_rules)}</td><td class="num">\${fmt(row.effective_generated_display_actions)}</td><td class="num">\${fmt(row.effective_display_overrides)}</td><td class="num">\${fmt(row.presentation_context_rules)}</td><td class="num">\${fmt(row.compatibility_mappings)}</td><td class="num">\${fmt(row.final_display_actions)}</td></tr>\`).join("")||\`<tr><td colspan="8" class="empty">没有匹配角色</td></tr>\`;}
document.getElementById("character-search").addEventListener("input",renderCharacters);renderCharacters();
const familyRows=Object.entries(REPORT.rule_families).sort((a,b)=>b[1].total-a[1].total||a[0].localeCompare(b[0]));
function renderFamilies(){const term=document.getElementById("family-search").value.trim().toLowerCase();const rows=familyRows.filter(([name])=>name.toLowerCase().includes(term));document.getElementById("family-count").textContent=\`\${rows.length} / \${familyRows.length} 个字段\`;document.getElementById("family-body").innerHTML=rows.map(([name,row])=>\`<tr><td class="mono">\${esc(name)}</td><td class="num">\${fmt(row.handwritten)}</td><td class="num">\${fmt(row.generated)}</td><td class="num">\${fmt(row.total)}</td><td class="num">\${fmt(row.total?row.generated/row.total*100:0)}%</td></tr>\`).join("")||\`<tr><td colspan="5" class="empty">没有匹配规则</td></tr>\`;}
document.getElementById("family-search").addEventListener("input",renderFamilies);renderFamilies();
document.getElementById("finding-summary").innerHTML=["error","warning","info"].map(level=>\`<span class="finding-chip"><span class="severity \${level}">\${level}</span> \${fmt(findings[level])}</span>\`).join("");
function renderFindings(){const term=document.getElementById("finding-search").value.trim().toLowerCase(),level=document.getElementById("severity-filter").value;const rows=REPORT.findings.filter(item=>(level==="all"||item.severity===level)&&[item.code,item.message,item.character,item.action_id,item.file].some(value=>String(value??"").toLowerCase().includes(term)));document.getElementById("finding-count").textContent=\`\${rows.length} / \${REPORT.findings.length} 条\`;document.getElementById("finding-body").innerHTML=rows.map(item=>\`<tr><td><span class="severity \${esc(item.severity)}">\${esc(item.severity)}</span></td><td class="mono">\${esc(item.code)}</td><td>\${esc(item.message)}</td><td>\${item.character?\`<b>\${esc(item.character)}</b>\${item.action_id!==undefined?\` / <span class="mono">\${esc(item.action_id)}</span>\`:""}\`:"-"}</td><td class="mono muted">\${esc(item.file??"-")}</td></tr>\`).join("")||\`<tr><td colspan="5" class="empty">没有匹配发现</td></tr>\`;}
document.getElementById("finding-search").addEventListener("input",renderFindings);document.getElementById("severity-filter").addEventListener("change",renderFindings);renderFindings();
document.getElementById("policy-characters").textContent=REPORT.code_hardcodes.policy_characters.length?REPORT.code_hardcodes.policy_characters.join(" · "):"未发现";
document.getElementById("code-body").innerHTML=REPORT.code_hardcodes.character_conditions.map(item=>\`<tr><td><b>\${esc(item.character)}</b></td><td class="mono">\${esc(item.subject)} \${esc(item.operator)}</td><td class="mono muted">\${esc(item.file)}:\${fmt(item.line)}</td><td class="mono">\${esc(item.excerpt)}</td></tr>\`).join("")||\`<tr><td colspan="4" class="empty">未发现直接角色条件</td></tr>\`;
document.getElementById("footer").textContent=\`生成时间 \${new Date(REPORT.generated_at).toLocaleString("zh-CN")} · \${REPORT.repository_root} · \${REPORT.product.commit_subject}\`;
</script>
</body>
</html>\n`;
}

function parseArgs(argv) {
  const options = {
    repoRoot: DEFAULT_REPO_ROOT,
    output: null,
    open: false,
    json: false,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--repo-root") options.repoRoot = path.resolve(argv[++index]);
    else if (arg === "--output") options.output = path.resolve(argv[++index]);
    else if (arg === "--open") options.open = true;
    else if (arg === "--json") options.json = true;
    else if (arg === "--help" || arg === "-h") options.help = true;
    else throw new Error(`未知参数：${arg}`);
  }
  options.output ??= path.join(options.repoRoot, "audit-output", "semantic-governance-dashboard.html");
  return options;
}

function printHelp() {
  process.stdout.write(`SF6CC Semantic Governance Dashboard\n\n` +
    `node tools/semantic_governance_dashboard.mjs [options]\n\n` +
    `  --repo-root <path>  SF6CC repository root\n` +
    `  --output <path>     self-contained HTML output\n` +
    `  --open              open the generated page\n` +
    `  --json              print the structured report instead of HTML\n`);
}

function openLocalFile(filename) {
  if (process.platform === "win32") {
    spawnSync("cmd", ["/c", "start", "", filename], { windowsHide: true });
  } else if (process.platform === "darwin") {
    spawnSync("open", [filename]);
  } else {
    spawnSync("xdg-open", [filename]);
  }
}

const invokedAsScript = process.argv[1]
  && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (invokedAsScript) {
  try {
    const options = parseArgs(process.argv.slice(2));
    if (options.help) {
      printHelp();
      process.exit(0);
    }
    const report = analyzeRepository(options.repoRoot);
    if (options.json) {
      process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
    } else {
      fs.mkdirSync(path.dirname(options.output), { recursive: true });
      fs.writeFileSync(options.output, renderDashboard(report), "utf8");
      process.stdout.write(`${JSON.stringify({
        output: options.output,
        action_semantics: report.summary.action_semantics,
        command_display: report.summary.command_display,
        findings: report.summary.findings,
      }, null, 2)}\n`);
      if (options.open) openLocalFile(options.output);
    }
  } catch (error) {
    process.stderr.write(`semantic governance dashboard failed: ${error.stack ?? error.message}\n`);
    process.exit(1);
  }
}
