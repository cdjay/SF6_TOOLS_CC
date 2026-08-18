# Repository Governance

Status: `CURRENT_OPERATIONAL`

This document classifies long-lived repository assets. It governs retention;
it does not change Runtime semantics or external backup custody.

## Inventory Baseline

Inventory date: August 16, 2026. Baseline SHA:
`2d783181de6b6357c276e0d4ee11fce26f33e8a9`.

| Asset | Baseline |
| --- | ---: |
| Git-tracked files | 499 |
| Markdown documents | 61 |
| Test inventory | 70 |
| Executable test files | 69 |
| Tracked Lua files | 127 |
| Current frozen corpus | 965 Combo JSON files |
| Historical exact-unique corpus | 2,509 cases |
| External `release/tester_packages` storage | 2,134 files / 83 ZIP / 22 Lua / 2,021 JSON |

The complete machine-readable test and corpus inventory is generated on demand
by `tools/repository_test_audit.py`; generated run output is intentionally not
checked in.

## Asset Classes

| Class | Retention rule | Main assets |
| --- | --- | --- |
| Current authority | Keep unique and linked from `docs/README.md` | Architecture, AC+BCM semantics, Frozen V2, testing, limitations, review/smoke/workflow |
| Permanent regression | Keep indefinitely unless the protected contract is deliberately retired | All BUG-B001 through BUG-B006 tests and other confirmed-regression tests |
| Long-term test infrastructure | Keep with its owner | `tools/test_*`, generator/editor tests, corpus/audit runners, fixtures |
| Active review tooling | Keep until the review work is completed and superseded | `architecture_convergence_*`, benchmark, Move graph fixtures, 179-batch review packet |
| Build/release tooling | Keep | version bump and checked-in release packager |
| Authoritative generated asset | Keep tracked; regenerate only through its owner | command-display/product JSON, generated semantics, `modern_display_builder/out/` inputs |
| Sealed asset | Keep immutable | 633-case fixtures and validated combo backup manifest |
| Rebuildable evidence | Do not commit | corpus runs, determinism/mutation JSON, coverage, profiles, logs, test ZIPs |
| Historical decision/audit | Keep only when it explains a current boundary | `docs/archive/` |
| Phase report | Remove after durable conclusions are absorbed | Task completion reports and count/SHA-only summaries |
| Runtime/user data | Ignore and never package as source | Web state, replay slots, telemetry, caches, logs, local configs |

## Test Classification

- `PERMANENT_REGRESSION`: BUG-B001 through BUG-B006 and other tests with a
  documented production failure or lifecycle contract.
- `CONTRACT_TEST`: Frozen schema, generated semantics, version/release, main
  entry limit, resolver/graph, and serialization guards.
- `UNIT` / `MODULE` / `SIMULATION`: discovered from `tools/test_*` and
  generator/editor-local test files.
- `CORPUS_RUNNER`: current, historical, determinism, roundtrip, and consumer
  audit tools.
- `AUDIT_ONLY_RETAINED`: `tools/imgui_texture_bridge_validation.lua`; manual,
  not a release gate.
- `TEMPORARY_REMOVED`: none of the 70 baseline test assets. No executable test
  was removed by repository hygiene.

## Tool Classification

| Class | Tools |
| --- | --- |
| Long-term gate | `repository_test_audit.py`, `current_corpus_audit.py`, `historical_corpus_audit.py`, `corpus_determinism_audit.py`, `regression_mutation_audit.py` |
| Corpus helper | `corpus_roundtrip.mjs`, `corpus_consumer.lua` |
| Active semantic review | `architecture_convergence_corpus.mjs`, `architecture_convergence_phase2.mjs`, `benchmark_current_move_graph.mjs`, `character_exception_baseline.mjs` |
| Generator/build | `action_runtime_compiler/`, `bcm_catalog_builder/`, `modern_display_builder/`, version and packaging scripts |
| Authoring/migration active | `combo_json_editor/` and its guarded batch migrations |
| Audit-only retained | `imgui_texture_bridge_validation.lua` |

## Specific Retained Asset Decisions

These unresolved or generated assets retain explicit boundaries that must not
be lost when inventory reports are regenerated:

| Asset | Current decision |
| --- | --- |
| `plugins/reframework-imgui-texture.dll` | Active generated Runtime asset. Keep it with `native/reframework-imgui-texture/`; source inputs support a partial rebuild, not a byte-identical toolchain guarantee. |
| `plugins/reframework-sf6cc-atomic-file.dll` | Active restricted Runtime JSON bridge for cumulative telemetry and combo-feedback outbox publication. Keep it with its native source and fixed-path allowlist contract; it is not a general filesystem API. |
| `data/reframework-d2d.json`, `plugins/reframework-d2d.dll` | `INVESTIGATE`. Both remain tracked but are excluded by the standard packager. Do not delete or restore release inclusion without a dependency review. |
| `plugins/script_whitelist.dll` | `INVESTIGATE`. It remains tracked and packaged. Do not delete or replace it until provenance, security role, and required Runtime behavior are reviewed. |
| `autorun/SF6CC_DynamicRecords.lua` | Shipped diagnostic/authoring behavior only; it is not action-semantic authority. Changes to release exposure require an explicit product review. |

## Tester Patch Inventory

No tester ZIP, patch, hotfix Lua, or loose debug copy is tracked by Git. The
external backup path contains many historical or superseded-looking artifacts,
including v1.1.3/v1.1.5 test patches, a standalone `.patch`, archives, and loose
Lua backups. Repository policy cannot establish their external-use status, so
they remain `UNKNOWN_OR_HISTORICAL_EXTERNAL` and were not deleted. Current
packages are generated through [Tester Workflow](TESTER_WORKFLOW.md).

## Generated Artifact Policy

Keep a generated asset tracked only when Runtime/release consumes it, it is a
sealed fixture/manifest, or it is an intentional generator input required for
reproducibility. Rebuildable audit JSON, hashes, comparisons, profiles, caches,
and package outputs go to ignored or temporary directories. An ordinary test
must never rewrite a tracked generated asset.

`tools/modern_display_builder/out/` remains tracked because the active legacy
compiler reads it as versioned OFF/naming input. It is derived evidence, not
AC/BCM or Move-identity authority.

## Delete Rule

Delete only when an asset is not current, referenced, required by Runtime,
build, tests, reproduction, human review, smoke, compatibility, or a lasting
decision record. Git history is the archive for completed phase reports and
temporary evidence that do not meet that test.
