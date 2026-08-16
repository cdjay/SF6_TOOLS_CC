# Testing Strategy

Status: `CURRENT`

SF6CC testing is layered. A pass at one layer must not be described as proof at
a stronger layer.

## Layers

| Layer | Purpose | Release meaning |
| --- | --- | --- |
| Unit | Pure helpers, parsers, formatting, state transitions | Required for touched modules. |
| Regression | Permanent reproduction of a confirmed production or infrastructure defect | Required; never remove merely because the test is narrow. |
| Contract | Frozen schema, generated artifact, architecture boundary, version, and entry-script guards | Required. |
| Integration / simulation | Multiple Runtime modules under a controlled standalone harness | Required where discovered, but still not live-game evidence. |
| Current corpus | 965 frozen current-build Combo files | Required offline corpus gate. |
| Historical corpus | 2,509 exact-unique Combo cases from accessible tester storage | Required compatibility/evidence gate when the storage is available. |
| Mutation | Deliberately injects four defects and requires focused tests to kill them | Required for governance/release evidence while this runner remains official. |
| Sealed oracle | Verifies 633 historical exception cases and fixture identity | Required integrity gate with `LOW` independence. |
| Real-game smoke | Executes RG-01 through RG-06 in Street Fighter 6 | Required before any production authority switch or equivalent Runtime claim. |

## Permanent Regressions

The following are failure tombstones, not temporary tests:

| Bugs | Test asset |
| --- | --- |
| BUG-B001 strict timeline parsing | `tools/test_combo_raw_input_codec.lua` |
| BUG-B002 multi-stage chord idempotence | `tools/test_unified_action_consumer.lua` |
| BUG-B003 atomic failed Combo loading | `tools/test_combo_file_load_recovery.lua` |
| BUG-B004 recording cancellation | `tools/test_combo_recording_lifecycle.lua` |
| BUG-B005 Demo cancellation on character change | `tools/test_combo_recording_lifecycle.lua` |
| BUG-B006 Demo/telemetry cancellation on mode exit and recovery | `tools/test_combo_demo_lifecycle.lua` |

Other `tools/test_*` files remain the executable characterization, unit,
contract, and simulation suite. Generator/editor tests stay beside their
owners. Test discovery is defined by `tools/repository_test_audit.py`.

## Official Offline Gate

Run from a clean repository worktree. Send generated JSON to a temporary
directory, not to `docs/`.

```powershell
$tmp = Join-Path $env:TEMP ("sf6cc-gate-" + [guid]::NewGuid())
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

python tools\repository_test_audit.py --repo-root . --audit-date (Get-Date -Format yyyy-MM-dd) --run-tests --output "$tmp\repository-test-audit.json"
python tools\current_corpus_audit.py --repo-root . --corpus-root "D:\CP\SF6CC\reframework\release\tester_packages\0803" --output-dir "$tmp\current-corpus"
python tools\historical_corpus_audit.py --repo-root . --backup-root "D:\CP\SF6CC\reframework\release\tester_packages" --output-dir "$tmp\historical-corpus"
python tools\corpus_determinism_audit.py --repo-root . --backup-root "D:\CP\SF6CC\reframework\release\tester_packages" --output "$tmp\corpus-determinism.json"
python tools\regression_mutation_audit.py --repo-root . --output "$tmp\regression-mutation.json"
```

Expected baseline on August 16, 2026:

- Lua parse: `127 / 127`.
- Test inventory: `70`; executable files: `69 / 69` pass.
- Sealed oracle: `633 / 633` integrity pass.
- Current corpus: `965 / 965`, normal and reverse, with zero roundtrip failures.
- Historical corpus: `2,509 / 2,509` exact-unique roundtrip pass.
- Mutation: `4 / 4` injected defects killed.
- Real-game evidence: still separate and required.

Counts are guards. A smaller `N / N PASS` is a failure until every removed test
is identified and justified.

## Oracle Meaning

The sealed oracle is generated from correlated historical production sources
and is not executed by Runtime consumers. It detects fixture drift and protects
a historical checkpoint. It must never be presented as an independent live-game
golden or as proof that production semantics are correct.

`node tools/character_exception_baseline.mjs --check` is the integrity gate.
`--verify-source` is a diagnostic comparison and is expected to report drift
after the reviewed Type35 convergence; it is not a requirement that current
production source equal the historical sealed snapshot.

## Clean-run Rule

After official gates, `git status --short` should remain clean. Default audit
outputs belong under ignored `audit-output/`, or an explicit system temporary
directory. Checked-in fixtures, frozen manifests, command-display data, and
`tools/modern_display_builder/out/` are intentional assets and must not be
silently refreshed by ordinary tests.
