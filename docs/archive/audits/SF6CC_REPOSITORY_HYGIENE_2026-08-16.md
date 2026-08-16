# SF6CC Repository Hygiene & Knowledge Governance

Status: `HISTORICAL_HANDOFF`

## 1. Final State

`COMPLETE` for the Git repository. External historical tester-package retention
decisions remain with the backup custodian.

## 2. Baseline

- Main SHA: `2d783181de6b6357c276e0d4ee11fce26f33e8a9`
- Task worktree: `D:\CP\SF6CC\reframework-worktrees\repository-hygiene`
- Branch: `refactor/repository-hygiene`
- Protected stash: `stash@{0}` remained untouched.

## 3. Repository Inventory

| Asset | Before | After |
| --- | ---: | ---: |
| Git-tracked files | 499 | 493 |
| Markdown documents | 61 | 56 |
| Archived documents | 0 governed archive | 12 |
| Test inventory | 70 | 70 |
| Executable test files | 69 | 69 |

Fixtures, product data, Runtime sources, release sources, fonts, images, native
sources, plugins, sealed manifests, and generated product assets were retained.

The official machine-readable inventory is generated on demand:

```powershell
python tools\repository_test_audit.py --repo-root . --run-tests --output (Join-Path $env:TEMP 'sf6cc-repository-test-audit.json')
```

## 4. Current Authority

| Topic | Authority |
| --- | --- |
| Project overview | `README.md` / `README.en.md` |
| Documentation map | `docs/README.md`, resolved by `docs/DOCUMENTATION_AUTHORITY.md` |
| Architecture | `ARCHITECTURE.md` |
| Frozen V2 | `docs/COMBO_JSON_SPEC.md` |
| Move/Action and AC/BCM | `docs/AC_BCM_SEMANTIC_CORE.md` |
| Testing | `docs/TESTING_STRATEGY.md` |
| Known limitations | `docs/KNOWN_LIMITATIONS.md` |
| Human review | `docs/review/HUMAN_REVIEW.md` |
| Real-game smoke | `docs/testing/REAL_GAME_SMOKE.md` |
| Development/release workflow | `AGENTS.md`, `docs/VERSIONING.md`, checked-in scripts |
| Tester packages | `docs/TESTER_WORKFLOW.md` |

## 5. Documents

Kept current: architecture, AC+BCM semantics, Frozen V2, subsystem contracts,
versioning, writable product data, telemetry/transcription, backup recovery, and
the new governance set.

Consolidated: Task A/B/C conclusions were absorbed into Testing Strategy, Known
Limitations, Human Review, Real-game Smoke, Repository Governance, and the
Documentation Authority map.

Archived: A/B/C main integration, Legacy exception convergence blocker,
unified-architecture decision record, WTT handover/merge assessments, old
regression/release baselines, performance audit, and ImGui texture audit.

Deleted from the working tree: 13 phase/duplicate/temporary assets, including
Task A/B/C phase reports, the pilot/Type35 completion reports, the old repository
asset registry, duplicate regression summary, Task C evidence ledger, and the
temporary `design-qa.md`. Git history retains them.

## 6. Tests

- Before: 70 inventory assets; 69 executable files.
- After: 70 inventory assets; 69 executable files.
- Removed tests: none.
- New tests: none.
- Permanent regressions: preserved.
- Contract/unit/module/simulation tests: preserved.
- Corpus and oracle runners: preserved and promoted to long-term names.
- Audit-only retained: `tools/imgui_texture_bridge_validation.lua`.
- B001-B006 regressions: `PRESERVED`.

## 7. Corpus / Oracle

- Current corpus: `965 / 965`; zero roundtrip and consumer failures.
- Historical exact-unique corpus: `2,509 / 2,509` roundtrip pass.
- Historical consumer findings: 34 known mixed-build display findings.
- Sealed oracle: `633 / 633` integrity pass.
- Oracle independence: `LOW`; Runtime consumers execute `0 / 633` cases.
- Evidence semantics: preserved; no real-game truth claim was added.
- Frozen archive: `LOOSE_SOURCE_PASS_ARCHIVE_UNAVAILABLE`.

## 8. Tester Patches

- Tracked tester patches found: 0.
- Current stored patches: 0.
- Generate on demand: checked-in release packager and Tester Workflow.
- External storage found: 2,134 files, including 83 ZIP, 22 Lua, and 2,021 JSON.
- Removed external artifacts: 0; destructive work was restricted to the task
  worktree and external-use status is unknown.
- External classification: `UNKNOWN_OR_HISTORICAL_EXTERNAL`.

## 9. Tools / Scripts

Long-term gate tools:

- `repository_test_audit.py`
- `current_corpus_audit.py`
- `historical_corpus_audit.py`
- `corpus_determinism_audit.py`
- `regression_mutation_audit.py`
- `corpus_roundtrip.mjs`
- `corpus_consumer.lua`

Active review tools for the 179 batches remain in place. Build, version,
generator, editor, and migration tools were retained. No tool was deleted.

## 10. Generated / Evidence

Authoritative generated assets retained: current command display, generated
semantics, product JSON, binary Runtime assets, and tracked OFF/naming snapshots
used by the active legacy compiler.

Sealed assets retained: 633-case fixtures and validated combo backup manifest.

Rebuildable evidence now defaults to `audit-output/` or an explicit system
temporary directory. Task C phase reports and its compact checked-in ledger were
removed after their durable conclusions were consolidated.

## 11. Gitignore

Added rules for `audit-output`, test output, coverage, Python/tool caches, logs,
profiles, temporary files, patches/diffs, and Node debug logs. Existing Runtime,
release, ZIP, replay, telemetry, and user-state rules remain.

No authoritative generated asset, sealed fixture, or Runtime product-data path
was hidden.

## 12. Governance Files

- README: current architecture state, documentation entry, and offline command.
- AGENTS: current authority set, mandatory tests, archive rule, output policy.
- CONTEXT: absent before and after; no duplicate context file was created.
- Docs index: added.
- Documentation Authority: rewritten around one topic, one authority.
- Known Limitations: added as the sole current blocker list.
- Tester Workflow: added; generate-over-store is the current policy.

## 13. Validation

| Gate | Result |
| --- | --- |
| Lua parse | `127 / 127 PASS` |
| Lua tests | `50 / 50 PASS` |
| Node generator/editor/tests | `17 / 17 PASS` |
| Python snapshot | `3 / 3 PASS` in one executable test file |
| PowerShell release/version | `1 / 1 PASS` |
| Total executable files | `69 / 69 PASS` |
| Test inventory | `70`, unchanged |
| Oracle | `633 / 633 PASS` |
| Current corpus | `965 / 965 PASS` |
| Historical corpus | `2,509 / 2,509 roundtrip PASS` |
| Fresh-process order | normal/reverse/seeded, `69 / 69` each |
| Same-process Lua order | forward/reverse, `50 / 50` each |
| Corpus determinism | current and historical PASS |
| Mutation | `4 / 4` killed |
| Main-entry guard | 164 locals/functions; 36 below hard limit |
| `git diff --check` | PASS |
| Broken Markdown links | 0 |
| Production source diff | 0 files |
| Clean-run `git status --short` | clean |

Real-game smoke was not executed and remains required.

## 14. File/Test Count Delta

- Tracked files: `499 -> 493` after this handoff report.
- Markdown: `61 -> 56`.
- Tests: `70 -> 70`.
- Removed tests: 0.
- New tests: 0.
- Net reduction is documentation/evidence noise, not test coverage.

## 15. Remaining Unknowns

- Which external historical tester patches are still retained by a human or
  external workflow.
- The declared frozen archive copy is unavailable at the audited local path.
- Human review and real-game smoke remain product/evidence work, not hygiene
  work.

## 16. Main Review Items

Potentially controversial deletions:

- Task A/B/C final and phase reports after consolidation.
- The old `REPOSITORY_ASSETS.md` registry after replacement.
- Task C's compact evidence ledger after its conclusions moved to current docs.
- The temporary visual `design-qa.md` with machine-local screenshot paths.

Assets not removed due to uncertainty: every external tester artifact, the
audit-only ImGui validator, active architecture-review tools, sealed fixtures,
OFF snapshots, and all Runtime/release assets.

## 17. Handoff

Commits, in merge order:

1. `60bcf7d` - promote audit tools and govern generated output.
2. `35507cb` - establish unique current authority.
3. `92eaa5f` - archive decisions and remove phase reports.
4. `e7d75c3` - remove Task C labels from long-term audit output.
5. Final handoff report commit.

Post-merge checks: rerun the commands in `docs/TESTING_STRATEGY.md`, confirm the
protected stash still exists, and keep real-game smoke and 179-batch review open.

```text
SF6CC_REPOSITORY_HYGIENE_COMPLETE
EXTERNAL_RETENTION_DECISIONS_REMAIN
```
