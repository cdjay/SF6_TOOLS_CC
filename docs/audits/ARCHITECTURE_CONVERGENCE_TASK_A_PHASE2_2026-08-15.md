# Task A Phase 2 - Deep Shadow Convergence

Date: 2026-08-15

## 1. Verdict

```text
production_result = legacy
PRODUCTION_SWITCH = BLOCKED
LEGACY_OFF = BLOCKED
REAL_GAME_SMOKE = UNAVAILABLE
```

Phase 2 did not change production authority, Frozen V2, stable identity approval,
or M5 loading. It exhausted decision-independent offline classification and
prepared bounded human-review and real-game packets.

Machine evidence is generated locally by:

```powershell
node tools/architecture_convergence_phase2.mjs `
  --corpus-report scratch/task-a-final-corpus-1.json `
  --m1 D:/CP/SF6ACBCM/data/local/m1/m1-extraction.v1.json `
  --m2 D:/CP/SF6ACBCM/data/local/m2/m2-graph.v1.json `
  --manifest D:/CP/SF6ACBCM/data/local/m5/export/export-manifest.v1.json `
  --runtime D:/CP/SF6ACBCM/data/local/m5/export/runtime-current.v1.json `
  --out scratch/task-a-phase2-final.json
```

The local machine report is evidence only and is not committed. Two final runs
were byte-identical:

```text
e6686082f8d62b4fe7c3b95d6fbe1f7bd84e99ad40c4979c3f3b82f57fe41a15
```

## 2. Ambiguity Reduction

```text
initial observations: 1720
final raw observations: 1720
explained observations: 1720
families: 245
pure unknown: 0
```

Raw ambiguity was not hidden or force-resolved. It was compressed into family
decisions and traced to its first visible lineage layer.

| Cause | Families | Observations | First-line disposition |
| --- | ---: | ---: | --- |
| TRUE_MULTI_MOVE_MEMBERSHIP | 130 | 610 | human semantic review |
| GENERATOR_OVERLAP | 81 | 659 | review route-family separation |
| RUNTIME_MECHANISM | 32 | 449 | human review plus representative live capture |
| FOLLOWUP_RELATION | 2 | 2 | human semantic review |

Concentration:

```text
36 families explain 50%
96 families explain 80%
135 families explain 90%
```

Representative findings:

| Ledger | Family | Observations | Evidence |
| --- | --- | ---: | --- |
| AMB-A-0001 | Terry 500 | 68 | two M1 route families, both `66`; generator overlap review |
| AMB-A-0002 | Luke 739 | 46 | `66` versus `Parry/HP`; universal runtime-route collision |
| AMB-A-0003 | Terry 902 | 46 | `4236+HP` versus `236+HP`; distinct enabled command sets |
| AMB-A-0004 | Ryu 739 | 37 | `Parry/HP` versus `66`; universal runtime-route collision |
| AMB-A-0006 | Mai 1012 | 33 | `4236+LK` versus `236+LK`; distinct enabled command sets |
| AMB-A-0009 | Guile 901 | 28 | two families with the same charge presentation |
| AMB-A-0026 | Ingrid 969 | 17 | one enabled command family and one commandless family |

Every high-frequency case first diverges in M1 route-family construction or M2
membership. MoveResolver and M5 serialization preserve the ambiguity rather
than creating it.

## 3. Unmapped Reduction

```text
initial observations: 414
final raw observations: 414
owned observations: 414
families: 124
pure unknown: 0
```

| Ownership | Families | Observations |
| --- | ---: | ---: |
| SYSTEM_ACTION | 39 | 140 |
| RUNTIME_ONLY_ACTION | 44 | 151 |
| TRANSITION_ACTION | 34 | 96 |
| LEGACY_ONLY | 7 | 27 |

No fake Move, nearest-candidate fallback, or identity patch was created.

The apparent EHonda build mismatches are explicit compatibility cases:

```text
944 -> 948
945 -> 949
967 -> 971
```

The checked-in compatibility data and the SF6ACBCM cross-build scorer agree on
these leading candidates. They remain compatibility projections, not stable
identity approvals.

## 4. Legacy Provenance

Current production Legacy remains 482 Action exception records. Phase 2
classified ownership without deleting any remaining record.

```text
absorb records: 113 -> 38 behavior families
alias records: 14 -> 11 unique pairs / 15 directed links
runtime-mechanism Action records: 328
character policies: 5
presentation overrides: 128
compatibility mappings: 12
```

These sets overlap. They are not intended to sum to 482.

Runtime-mechanism subclasses:

| Subclass | Records |
| --- | ---: |
| PARTICIPATION_CONTROL | 193 |
| HOLD_OR_CHARGE_TIMING | 84 |
| SUPPRESSION | 31 |
| ACTION_EVENT_PROJECTION | 15 |
| FOLLOWUP_BRIDGE | 4 |
| STATE_OR_CONTACT | 1 |
| Unknown | 0 |

## 5. Legacy Relation Unknown

```text
initial Unknown: 151 / 160
final pure Unknown: 0 / 160
```

| Result | Cases | Meaning |
| --- | ---: | --- |
| OFFLINE_PROVED_SAME_MOVE | 6 | both sides share one candidate Move |
| OFFLINE_PROVED_DISTINCT_MOVE | 3 | single candidates differ |
| OFFLINE_PROVABLE_NOT_IMPLEMENTED | 128 | comparison asked Move equality for runtime, transition, system, or compatibility ownership |
| HUMAN_SEMANTIC_REVIEW_REQUIRED | 23 | one or both sides retain ambiguous membership |

`OFFLINE_PROVABLE_NOT_IMPLEMENTED` is not a claim of semantic equivalence. It
means the Phase 1 comparison interface lacked the ownership type required to
ask the right question.

## 6. Presentation Overrides

```text
128 total
122 LABEL_ONLY
6 COMMAND_DISPLAY_ONLY
0 identity-affecting
0 runtime-affecting
0 missing evidence
0 unknown
```

The resolver test now proves that applying a display override cannot change
MoveResolver identities. Runtime-only Actions also remain `NOT_FOUND` rather
than receiving a fake stable identity.

## 7. Main-entry P1

Behavior-preserving extractions completed:

- Luke, JP, Lily, and Ingrid hold/charge behavior moved to
  `ChargeRuntimePolicy`.
- Ingrid Action 969 charge-stock classification moved out of the entry script.
- Lily physical-hold tracking and JP/Lily charge-max policy now call the same
  runtime policy module.
- ImGui Action 1231 name expansion moved to `MotionPresentation`, which returns
  display text only.

Akuma Action 1231 evidence is build-local: two BCM routes expose `5565+HP` and
Modern `MK`, with AC Type 36 `1231 -> 1232`. The extracted code only expands
the recognized move name into `LP,LP,6,LK,HP` for rendering. It cannot mutate
detection identity, recording, compatibility, or MoveResolver state.

## 8. Focused Offline Lineage

### EHonda 926 / 921

- 921 has an enabled `214+HP` / Modern `214+MK` BCM route and no AC edge.
- 926 has the same visible command family plus a Super profile.
- Raw AC: `926 -> 941` Type 54; then `941 -> 942` Type 4 and `942 -> 942`
  Type 4.
- M2 keeps 921 and 926 in distinct provisional Moves.

Visible command equality is insufficient to merge them. Live state/resource
capture remains required.

### Yasmine 941 / 942

- 941 has enabled `6+P`, Modern chord, and Super profiles.
- Raw AC has direct Type 37 `941 -> 942`.
- 942 has a BCM trigger record but no enabled profile.
- M2 keeps 941 and 942 in distinct provisional Moves.

The remaining question is runtime ownership of 942, not absence of static AC
evidence.

## 9. Stable Identity Review Pack

```text
3023 total Moves
1986 HIGH_CONFIDENCE_UNAMBIGUOUS
150 MEDIUM
865 AMBIGUOUS
22 UNKNOWN
179 compressed review batches
stable identities approved: 0
```

No record was marked approved. Batches group by character, membership role,
enabled-command presence, disabled/duplicate-owner flags, and membership
shape. See `HUMAN_REVIEW_PACKET_TASK_A_2026-08-15.md`.

## 10. M5 Gate Matrix

| Gate | Current | Required | Remaining authority |
| --- | --- | --- | --- |
| artifact_set | true | true | satisfied |
| review_complete | false | true | human review |
| integration_candidate | false | true | human review plus real-game smoke |
| stable identities | 0 / 3023 | 3023 / 3023 | human review |
| unresolved rows | 65 | 0 | 13 review groups; 16 require pinned raw accessor contract |
| unresolved extensions | 24 | 0 | 2 unresolved-source-anchor groups |
| unresolved transitions | 20 | 0 | 2 non-1x1 family-resolution groups |
| migration links | 273 | reviewed | human migration review |
| real-game smoke | unavailable | pass | real game |

The 65 rows are fully grouped by predicate and rejection reasons. The 16
`t20_hold_continuation` rows remain intentionally fail-closed because the
immutable raw workspace contract does not pin the loop-count accessor.

## 11. Shadow Consumer Coverage

| Consumer | Offline evidence | Live shadow observations | Production authority |
| --- | ---: | --- | --- |
| Recording | 7,904 step facts | unavailable | Legacy |
| Display | 7,747 display entries available | unavailable | Legacy/presentation |
| Detection | 7,904 step facts | unavailable | Legacy |
| Demo | 965 replayable combos | unavailable | Legacy compatibility |
| Playback | 12 compatibility cases | unavailable | Frozen V2 plus Legacy compatibility |

Coverage here means offline observation/compare input, not real runtime
coverage. No consumer was switched.

## 12. Offline Performance Estimate

Full runtime artifact:

```text
bytes: 8,336,048
characters: 31
moves: 3,023
memberships: 3,508
action lookup keys: 3,014
```

Node v24.12.0 x64 estimate, nine iterations:

```text
read median / p95: 11.808 / 13.601 ms
parse median / p95: 12.081 / 15.792 ms
index build: 0.757 ms
index heap delta: 1,384,656 bytes
2,000,000 lookup loop: 34.264 ms
```

This is `OFFLINE_ESTIMATE`, not REFramework performance evidence. LuaJIT/cjson
was not available in the local CLI environment.

## 13. Verification

- SF6CC Lua parse: `122 / 122 PASS`
- SF6CC Lua tests: `46 / 46 PASS`
- SF6CC Node tests: `9 / 9 PASS`
- sealed oracle integrity: `633 / 633 PASS`
- sealed source comparison: expected Phase 1 drift only; sealed artifacts unchanged
- SF6ACBCM type check: PASS
- SF6ACBCM build: PASS; existing bundle-size advisory only
- SF6ACBCM tests: `61 / 61 files`, `466 PASS`, `1 skipped`
- real M5 export determinism: two runs; all four files byte-identical
- Phase 2 report determinism: two runs; byte-identical
- M4 index SHA-256 unchanged: `7b95f8250bbb708ced408cf4481351fcca8296190eee10ebd3c2bd93793886a4`
- real-game smoke: unavailable

M5 hashes:

```text
runtime-current.v1.json
af319d0f4ca96e49368cea976951558425fb14bc841fad217226e4a158eea5bf

public-catalog-current.v1.json
c4b753a4f0775b219f2ce4fc190b72f5ffa353ef69b5816b45021f6ed83c7318

legacy-projections-current.v1.json
3ae3442c1dfc2dc88a9616790c2c9be18ea4038b41eab621743417c01f455307

export-manifest.v1.json
bfb2c41f1c180427840608f4d3ea0269233e8d5898d4ebf877c9426b9a3e0002
```

## 14. Offline Exhaustion Evidence

Methods attempted:

- corpus family clustering and concentration analysis;
- raw Action/AC/BCM queries through the SF6ACBCM MCP tools;
- M1 route-family and anchor lineage;
- M2 membership, census, unresolved row, extension, and transition analysis;
- M5 manifest/readiness and real deterministic exports;
- current Legacy source, compatibility, presentation, policy, and sealed oracle;
- focused entry-script and presentation isolation tests;
- offline load, memory, indexing, and lookup benchmark.

Decision-independent offline work remaining:

```text
none identified
```

Remaining work requires one of:

- human semantic/stable-identity/migration review;
- a separately governed raw accessor contract decision;
- real-game capture.

## 15. Final State

```text
SF6_DEEP_SHADOW_CONVERGENCE_COMPLETE
OFFLINE_CONVERGENCE_EXHAUSTED
HUMAN_REVIEW_REQUIRED
REAL_GAME_SMOKE_REQUIRED
PRODUCTION_SWITCH_BLOCKED
LEGACY_OFF_BLOCKED
```
