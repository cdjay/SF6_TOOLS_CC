# Task A - SF6CC x SF6ACBCM Architecture Convergence

Date: 2026-08-15

## 1. Final State

`BLOCKED`

本轮完成了可安全落地的 shadow resolver、结构化 compare、sealed baseline source diff、
真实 corpus 批量审计和 generator determinism 复验。没有执行 production switch，也没有
关闭 Legacy。

外部硬阻塞：

- SF6ACBCM M5 当前 `stable_identities = 0 / 3023`；
- `review_complete = false`；
- `integration_candidate = false`；
- 273 个 migration link 与 109 个 current fact 仍待 review；
- Full Convergence real-game smoke evidence 不可用。

## 2. Baseline

- SF6CC baseline SHA: `1fd27f95ade064a54b789153a492df505497af57`
- SF6CC implementation commits:
  - `43ba98f` (`收敛：建立 MoveResolver 影子比较与语料审计`)
  - `9b98273` (`修复：封闭 MoveResolver 影子状态`)
- SF6ACBCM SHA: `6ee988dd0a2a30c23d57cf2d09493defadb6b44b`
- SF6CC worktree: `D:\CP\SF6CC\reframework-task-a`
- SF6ACBCM worktree: `D:\CP\SF6ACBCM-task-a`
- Parallel SF6CC worktree: `D:\CP\SF6CC\reframework-task-b`
  (`bugfix/autonomous-bug-mining-task-b`, observed only)
- Parallel SF6CC worktree: `D:\CP\SF6CC\reframework-task-c`
  (`review/full-corpus-audit-task-c`, observed only)
- Main SF6CC worktree remained dirty and untouched; its pre-existing changes are an integration risk.
- No merge and no push were performed.

Previous sealed evidence (2026-08-10):

- governance/oracle records: 633
- production-loaded Legacy Action exceptions: 483
- migrated pilot exceptions: 1
- character policies: 5
- presentation overrides: 132
- historical compatibility mappings: 12

Current observed production sources:

- diagnostic records: 629
- production-loaded Legacy Action exceptions: 482
- migrated pilot exceptions: 2
- character policies: 5
- presentation overrides: 128
- historical compatibility mappings: 12
- unresolved Legacy provenance: 482

Delta is explained by committed Alex/Jamie convergence changes after the sealed snapshot. The sealed
633-case oracle was not regenerated or modified. `--compare-source` reports four removed Alex
presentation records and 15 changed Alex/Jamie Action records.

## 3. Architecture Truth Map

Actual current implementation, not target architecture:

```text
Raw current AC / BCM
    -> SF6ACBCM phase1 raw workspace (read-only)
    -> M1/M2/M4/M5 candidate Move graph and migration workspace
    -> M5 current-only artifact (candidate_only, not integration candidate)
    -> SF6CC CurrentMoveGraph loader (implemented, fixture-tested, not production-loaded)
    -> MoveResolver shadow API (implemented in 43ba98f)
    -> structured compare through UnifiedActionConsumer (diagnostic only)

Production Runtime today:

command_display + generated_semantics + exceptions + action_compatibility
    -> CharacterRules / GeneratedActionRelations / ActionMatcher / CommandResolver
    -> UnifiedActionConsumer
    -> Recording / Detection / Demo / Audit

command_display + CommandDisplayOverrides + ActionCompatibility projection
    -> Display

Frozen V2 timeline / raw input / Action observations
    -> Replay and compatibility consumers without schema mutation
```

The candidate Move graph and the production Legacy path are therefore parallel, but only Legacy is
production authority. The new path is now observable and comparable; it is not switched.

## 4. Authority Matrix

| Domain | Canonical authority | Generated | Runtime consumer | Legacy fallback | Mutation allowed |
| --- | --- | --- | --- | --- | --- |
| Action ID | current AC/BCM build facts | yes, M5 binding | all consumers | V2 observed ID | no cross-build identity mutation |
| Move | reviewed SF6ACBCM stable identity | yes | shadow only | Action-centered Legacy | human ledger only |
| BCM input | raw BCM | command display/M5 | recording/display | saved motion text only as compatibility evidence | generator only |
| AC relationship | raw AC | M2/M5/generated semantics | recording/detection | exceptions | generator or evidence-backed curation |
| Move family | M5 reviewed membership | yes | shadow only | generated source group + exceptions | human review required |
| alias | equality kind must be explicit | partial | matcher | `action_alias_ids` | no identity collapse without evidence |
| absorb | owning domain varies | partial | compiler/matcher | `absorb_ids` | no Action-ID list expansion without evidence |
| character policy | runtime mechanism data | no | grouping/transcription | `_character` records | evidence-backed product data only |
| runtime mechanism | CharacterRules/ActionMatcher behavior | partial | recording/detection/demo | exceptions | runtime module/data only |
| timeline | Frozen V2 | no | replay/demo/audit | none | immutable meaning |
| raw input | Frozen V2 | no | replay/demo/audit | timeline | immutable meaning |
| display label | generated command display | yes | UI/audit | display overrides | presentation only |
| detection identity | currently ActionMatcher composition | partial | detection | exceptions/compatibility | no presentation mutation |
| demo identity | Frozen V2 facts + matcher | partial | demo/audit | compatibility projection | no destructive migration |
| compatibility mapping | ActionCompatibility | no | playback/display/matcher | none | compatibility-only, never Move identity |

## 5. Consumer Convergence Matrix

| Consumer | Current state | Actual authority | Shadow status |
| --- | --- | --- | --- |
| Recording | mixed Legacy/current-generated | ActionEventCompiler + CharacterRules + GeneratedActionRelations | resolver compare API available, not wired to live observations |
| Display | mixed presentation | generated command map + overrides + compatibility projection | corpus display availability compared; no switch |
| Detection | Legacy production | ActionMatcher + exceptions + compatibility + generated relations | structured compare available through UnifiedActionConsumer |
| Demo/Playback | Legacy-compatible | Frozen V2 raw/timeline + matcher + compatibility | corpus replay facts audited; no live compare |
| Audit/Validation | Legacy production | same matcher gateway plus RuntimeAuditor | structured compare available; no switch |

All consumers do not yet share MoveResolver as production authority. This is a known P1 blocker, not
an unexplained state.

## 6. Representative Data Lineage

### Normal Move: Ryu Action 600

- raw AC: one build-local Action variant, no AC edges;
- raw BCM: direct enabled `LP` route;
- M5: current candidate Move membership;
- SF6CC production: command display and Action matcher;
- MoveResolver: provisional candidate only; production remains Legacy.

### AC Follow-up / Runtime Continuation: Yasmine 941 -> 942

- raw AC: zero-frame Type 37 edge `941 -> 942`;
- BCM 941: enabled `6+P` route;
- BCM 942: no enabled input profile;
- Legacy: `941 absorb_ids 942` plus action-event projection;
- M5: distinct provisional Moves;
- classification: `RUNTIME_MECHANISM / REQUIRES_REVIEW`, not automatic identity merge.

### BCM Condition Split: EHonda 926 vs 921

- both expose the same Classic `214+HP` command signature;
- Action 926 carries `cond_param_id=0, cond_param_value=1` and additional AC continuation;
- Action 921 carries no corresponding condition;
- Legacy matches 926 with 921, while M5 keeps distinct provisional Moves;
- classification: condition-sensitive runtime equivalence, not proven same Move identity.

### Alias Family: Sagat 953 vs 951

- Legacy declares Action alias;
- raw BCM Classic routes differ: `214+MK` versus `214+LK`;
- M5 correctly keeps distinct provisional Moves;
- classification: Legacy runtime matching behavior, not identity evidence.

### Evidence-backed Absorb: Jamie 981

- raw AC contains exact Type 35 replacement edges to 982/983/984;
- generated semantics owns the migrated pilot;
- UnifiedActionConsumer consumes generated source-group equality;
- Legacy production exception count decreased without changing Frozen V2.

### Character Policy: EHonda

- `_character` owns pending-absorb and initial unique-resource preparation;
- this is runtime/training environment policy, not Move identity;
- it remains Legacy product data.

### Historical Playback: Blanka 924 -> 926

- four corpus steps still record old Action 924;
- ActionCompatibility projects playback/matching to current Action 926 using 2026-08-05 smoke evidence;
- the projection remains compatibility-only and does not feed Move identity.

### Newly Recorded / Current Corpus

- 965/965 combo files contain replayable timeline/raw facts;
- current Action observations are resolved without rewriting the V2 arrays;
- current candidate identity remains provisional and shadow-only.

## 7. Changes

Commit `43ba98f`:

- added `Semantic/MoveResolver.lua`;
- added `Semantic/MoveResolverShadow.lua`;
- exposed resolver load/compare through `UnifiedActionConsumer`;
- added deterministic real-corpus comparison tooling;
- added sealed baseline `--compare-source` without rewriting golden files;
- added focused Lua and Node regression tests;
- documented the shadow-only rollout contract.

Commit `9b98273`:

- moved resolver graph/readiness/build state into a private weak-map;
- rejected external mutation of resolver instances;
- added a mutation regression so callers cannot replace validated authority state.

Why safe:

- `production_result` is always `legacy`;
- no main-entry business logic was added;
- no Frozen V2 field or meaning changed;
- no exception, override, compatibility mapping, command display, or generated artifact changed;
- provisional/current Move identity is never reported as approved stable identity;
- ambiguity, unresolved membership, missing Action, and readiness remain explicit.

## 8. Corpus Comparison

Source: local `0803` corpus and M5 artifact for build `2026-08-03`.

- JSON files / parsed combos: 965 / 965
- replayable combos: 965
- step cases: 7,904
- comparable Action cases: 7,490
- exact single current-Move resolutions: 5,770 (all provisional)
- ambiguous current-Move resolutions: 1,720
- not found: 414
- command display available / missing: 7,747 / 157
- Legacy relation cases: 160
- candidate semantic matches: 6 total, 4 corpus-referenced
- Legacy-only differences: 3 total, all corpus-referenced
- unknown relation cases: 151 total, 121 corpus-referenced
- compatibility mappings: 12, all corpus-referenced
- unexpected differences: 0, because the corpus has recorded facts rather than paired live
  observations; negative equality cannot be inferred and was not marked PASS.
- production-blocked comparable cases: 7,490 because the manifest is not an integration candidate.

The structured local report is generated by `tools/architecture_convergence_corpus.mjs`; raw combo
content and local report output remain outside Git.

## 9. Legacy Residual Ledger

| ID | Domain | Current count/case | Classification | Status | Remaining risk |
| --- | --- | ---: | --- | --- | --- |
| L-001 | production Action exceptions | 482 | mixed semantic/runtime | BLOCKED | active production authority |
| L-002 | absorb records | 113 | mixed identity, continuation, contact, runtime mechanism | BLOCKED | false folding if generalized |
| L-003 | alias declarations | 14 records / 11 unique pairs | equality kind unresolved | BLOCKED | false identity collapse |
| L-004 | runtime-mechanism records | 328 | timing/state/force/hold/suppression | COMPATIBILITY_REQUIRED | no generic replacement suite |
| L-005 | character policies | 5 | explicit training/runtime policy | COMPATIBILITY_REQUIRED | not derivable from Move identity alone |
| L-006 | presentation overrides | 128 | presentation-only | CONFIRMED | generator cleanup still incomplete |
| L-007 | historical mappings | 12 | playback compatibility | COMPATIBILITY_REQUIRED | old combos depend on projection |
| L-008 | EHonda 926/921 | 1 relation | condition-sensitive runtime equivalence | REQUIRES_REAL_GAME | same command is insufficient identity evidence |
| L-009 | Sagat 953/951 | 1 relation | runtime alias, distinct inputs | CONFIRMED | must not merge Moves |
| L-010 | Yasmine 941/942 | 1 relation | Type 37 continuation/runtime projection | REQUIRES_REAL_GAME | ownership needs live evidence |

No remaining Legacy record was deleted in this task.

## 10. Verification

- SF6CC Lua parse: `118 / 118 PASS`
- SF6CC Lua tests: `44 / 44 PASS`
- SF6CC Node tests: `8 / 8 PASS`
- sealed oracle integrity: `633 / 633 PASS`
- sealed source equality: expected drift; structured comparison PASS, sealed files unchanged
- SF6ACBCM type check: PASS
- SF6ACBCM build: PASS (existing bundle-size advisory only)
- SF6ACBCM tests after build: `61 / 61 files`, `466 PASS`, `1 skipped`
- generator determinism: two real exports, all four files byte-identical
- M4 SQLite immutability: SHA-256 unchanged
- corpus comparison: PASS, 965 combos / 7,904 steps
- integration checks: resolver, gateway, corpus and baseline diagnostics PASS
- `git diff --check`: PASS
- real-game smoke: `REAL_GAME_SMOKE_NOT_AVAILABLE`

Deterministic export hashes:

- runtime: `af319d0f4ca96e49368cea976951558425fb14bc841fad217226e4a158eea5bf`
- public catalog: `c4b753a4f0775b219f2ce4fc190b72f5ffa353ef69b5816b45021f6ed83c7318`
- legacy projections: `3ae3442c1dfc2dc88a9616790c2c9be18ea4038b41eab621743417c01f455307`
- manifest: `bfb2c41f1c180427840608f4d3ea0269233e8d5898d4ebf877c9426b9a3e0002`

Test infrastructure observation: a clean SF6ACBCM worktree must run build before the MCP external-cwd
test because that test expects `dist/src/query/bin-mcp.js`. `check -> build -> test` passes completely.

## 11. Remaining P0/P1

P0: none reproduced.

P1:

- production consumers remain mixed/Legacy rather than MoveResolver-authoritative;
- candidate artifact has zero approved stable identities and cannot be switched;
- corpus contains 1,720 ambiguous and 414 unmapped step resolutions;
- 151/160 Legacy relation comparisons remain Unknown;
- three Legacy-only families require domain ownership decisions; none justifies identity merging;
- no Full Convergence real-game smoke evidence exists;
- main entry still contains Ingrid 969, Luke/JP/Lily, and universal Action-ID interpretation branches;
- ImGui still contains an Action 1231 presentation special case outside data-driven overrides;
- Main worktree contains overlapping uncommitted semantic changes and requires careful integration.

## 12. Switch Readiness

`NOT_READY`

Reason: review and integration gates fail, consumer convergence is not production-proven, corpus has
large ambiguous/unknown coverage, and real-game smoke is unavailable. Rollback is simple because the
new code is shadow-only and contained in commits `43ba98f` and `9b98273`.

## 13. Legacy OFF Readiness

`LEGACY_OFF_BLOCKED`

Reason: 482 production exceptions, 328 runtime-mechanism records, 5 character policies, 12 historical
compatibility mappings, unresolved corpus coverage, and missing smoke evidence still carry authority.

## 14. Unknowns

- Whether ambiguous M5 memberships represent legitimate shared/current route families or generator
  ownership defects for each corpus case.
- Whether the 414 unmapped observations are common/system Actions, historical Action IDs, or missing
  current graph facts; they require case-family triage.
- Real-game behavior of EHonda 926/921 and Yasmine 941/942 under the exact runtime states.
- Production performance/memory of loading the full 8.3 MB M5 runtime artifact inside REFramework.
- Final human Move identity decisions and migration ledger content.

## 15. Handoff to Main

- Review commits in order: `43ba98f`, then `9b98273`.
- Merge both implementation commits before the documentation handoff commits.
- Do not copy or commit files under either worktree's `scratch/` directories.
- Reconcile carefully with the dirty Main changes touching UnifiedActionConsumer and semantic
  generation; preserve `production_result = legacy` and stable-identity-first comparison.
- Next safe work package: classify the top ambiguous/unmapped corpus families by runtime/system Action
  versus Move membership, then obtain formal real-game observations for the three Legacy-only cases.
- Do not request production switch review until M5 human review, corpus ambiguity, consumer shadow
  equality, and smoke gates are satisfied.

`SF6_ARCHITECTURE_CONVERGENCE_BLOCKED`

`LEGACY_OFF_BLOCKED`
