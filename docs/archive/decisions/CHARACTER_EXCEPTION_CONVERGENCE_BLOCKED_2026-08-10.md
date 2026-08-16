# SF6CC Character Exception Convergence Final

> Status: `HISTORICAL_DECISION_RECORD`. Retained because it explains why
> Legacy OFF remains blocked; current counts and limitations live in current
> authority documents.

Date: 2026-08-10

Final verdict: `CONVERGENCE_BLOCKED`

## Baseline

The pre-migration snapshot is sealed before any additional Legacy rule was changed.

- Governance records: 633
- Historical Action exceptions: 484
- Production-loaded Legacy Action exceptions: 483
- Migrated Pilot Action exceptions: 1
- Character-level policy records: 5
- Presentation overrides: 132
- Historical compatibility mappings: 12
- Character scopes: 32
- Regression Oracle cases: 633
- Records with verified generated provenance: 1
- Records whose provenance still requires review: 488

The machine baseline and Oracle are immutable test artifacts. The baseline checker pins their SHA-256 values and marks both as `runtime_source = false`. `--verify-source` also proves that the snapshot still matches the current production data at the blocked checkpoint.

## Generator Convergence

| Semantic family | Legacy count | Current structured evidence | Generic rule | Automatic exact coverage | Status |
| --- | ---: | --- | --- | ---: | --- |
| Type 35 strict replacement absorb | 2 exact families | BCM primary owner plus unanchored STRICT Type 35 replacements | `sf6cc-replacement-absorb.v1` | 2 | Jamie 981 migrated; Jamie 989 remains a valid follow-up candidate |
| Other `absorb_ids` families | 113 | Mixed AC branch types, runtime phases, contact continuations, and unresolved ownership | None proven for the whole family | 0 | BLOCKED |
| Hand-written Action aliases | 13 | No exact equality with current M2 STRICT alias memberships | None | 0 | BLOCKED |
| Optional parent/follow-up relations | 59 records | Mixed static transition and runtime matching intent | No reviewed complete rule set | 0 complete-family coverage | BLOCKED |
| Action event projections | 35 records | Mixed owner/internal semantics and runtime input-anchor behavior | Pilot rule does not cover these mixed contracts | 0 complete-family coverage | BLOCKED |

The current M2 graph was compared directly with all historical Action rules. Only two of 115 absorb families are exact STRICT replacement matches. Promoting broader reachability would change Legacy behavior rather than preserve it.

### Type 13 blocker

Ingrid `945 -> 953` is backed by raw edge `edge_7cd754645306493c734ad777`, Type 13, frame 0, attr 0, trigger -1, and zero params. However, the current 31-character raw corpus contains:

- 1,058 Type 13 edges in total
- 218 edges with the same broad BCM-owner/unanchored/frame-zero neutral shape

The raw shape is therefore not a bounded internal-phase predicate. Generating all 218 would create unreviewed semantic memberships; selecting only Ingrid would be a prohibited character/Action special case.

## Runtime Convergence

No additional Legacy rule was removed in this Full Convergence run.

Category C contains 333 records, including timing, hold/charge windows, forced participation, ignore policy, transient event suppression, and character-level transcription/grouping policy. These are not all AC/BCM Move facts. No complete generic Runtime mechanism and equivalence suite currently replaces them.

The frozen composition root also still contains existing character-conditioned behavior, including Ingrid Action 969 handling and Luke/JP/Lily timing branches. They were inventoried but not changed because their generic runtime contracts are not proven.

Production legacy exceptions remaining: **483**.

## Presentation

The 132 Presentation overrides already use the separate `CommandDisplayOverrides` mechanism rather than the Legacy character-exception loader. They remain presentation-only and do not mutate V2, Recorder, Detector, or Replay. They are frozen in the Baseline/Oracle but were not moved into AC semantics.

## Compatibility

The 12 historical mappings already use the separate `ActionCompatibility` mechanism. They remain old-Action to current-Action playback projections and are not treated as current Move identity. They are frozen in the Baseline/Oracle and were not injected into the semantic generator.

## Legacy OFF

Legacy OFF was not enabled because its mandatory prerequisites failed:

1. 483 production Action exception records are still required by current consumers.
2. 113 absorb families and all 13 hand-written alias families lack exact generated equivalence.
3. 333 Runtime-mechanism records do not yet have complete generic replacements.
4. Existing character-conditioned Runtime branches remain unresolved.

`CharacterRules.load_for_character()` therefore still loads `exceptions/<Character>.json`. There is no hidden attempt to claim Legacy OFF while retaining fallback behavior.

## Regression

- Sealed Baseline cases: 633
- Legacy Oracle cases: 633
- Baseline internal integrity: PASS
- Baseline versus current source checkpoint: PASS
- Jamie Pilot generated equivalence: PASS
- SF6CC Lua parse: 95/95 PASS
- SF6CC Lua tests: 33/33 PASS
- SF6ACBCM tests: 60 files / 434 tests PASS
- SF6ACBCM type check: PASS
- SF6ACBCM production build: PASS
- Legacy OFF regression: NOT RUN; prerequisite blocked
- Unresolved production rules: 483

The permanent regression artifacts are:

- `tests/fixtures/character_exception_baseline.json`
- `tests/fixtures/character_exception_legacy_oracle.json`
- `tools/character_exception_baseline.mjs`

## Real-game Smoke

No Full Convergence real-game Smoke was requested from the user because Legacy OFF was not reached. Running the final Smoke matrix against unchanged Legacy production would not validate convergence. The previously accepted Jamie Pilot behavior remains covered by its automated equivalence test.

## Remaining Exceptions

Target: `0 production-loaded legacy character exceptions`

Actual: `483 production-loaded legacy Action exceptions + 5 character policy records`

Because the actual value is not zero, this task cannot announce `CHARACTER_EXCEPTION_CONVERGENCE_COMPLETE`.

## Blocking Rules

| Character / Scope | Rule | Why it cannot currently be generated | Why it cannot currently be generalized | Runtime necessity | Risk |
| --- | --- | --- | --- | --- | --- |
| Ingrid | `945 -> 953` absorb/internal projection | Type 13 raw shape is not a unique semantic predicate | Same broad shape occurs 218 times | Existing compiler/matcher folding | False absorption and lost recorded steps |
| All characters | 113 non-Type-35 exact absorb families | Current M2 has no exact membership equality | Families mix contact phases, runtime continuation, and other branch types | Matcher/compiler behavior | Recorder/Detector regressions |
| DeeJay/EHonda/Jamie/Mai/Sagat | 13 Action alias declarations | Current M2 emits no exact equivalent alias sets | Alias intent may be runtime or historical rather than Move identity | Matcher equivalence | False positive or missed detection |
| Multiple characters | 333 Runtime-mechanism records | Timing/state behavior is not static AC/BCM identity | No complete state/type predicate and shadow suite exists | Recording and player detection | Timing, hold, combo and suppression regressions |
| Composition root/UI | Ingrid/Luke/JP/Lily branches | Existing behavior depends on character/runtime context | Generic mechanism has not been characterized | Mature production behavior | Main-entry and UI regression |

## Recommended Next Step

Resume only with independently routed semantic workers and divide work by semantic family, not character. The first bounded follow-up is Jamie `989 -> 990,991,992`, followed by separate evidence programs for Type 13 continuation, alias semantics, optional-parent transitions, and runtime timing mechanisms. Each family must independently reach Shadow equality before any Legacy removal.

## Git

- SF6ACBCM generator baseline: `5784b5c926e1862a46e2194cd068f3eff1541b05`
- SF6CC audit/baseline commit: commit containing this report; exact SHA is reported after commit
- Stable workspaces: unchanged
- Push: not performed
