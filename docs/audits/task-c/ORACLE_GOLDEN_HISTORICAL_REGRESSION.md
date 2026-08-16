# Task C Oracle / Golden / Historical Regression Audit

Date: 2026-08-15

State: `AUDIT_COMPLETE`

## 1. Sealed Oracle Source Chain

The 633-case character-exception assets follow this chain:

```text
production exception/governance files
  -> tools/character_exception_baseline.mjs build()
  -> character_exception_baseline.json
  -> character_exception_legacy_oracle.json
  -> --check verifies pinned hashes/schema/counts
```

The same tool constructs both the baseline and the expected oracle from the
same production sources and transformation logic. No Runtime consumer or test
iterates the 633 cases and compares them with current recording, detection,
display, demo, or playback behavior.

Oracle independence rating: `LOW`.

What `633 / 633 PASS` proves:

- the two historical JSON files retain their sealed hashes;
- the schema and summary counts remain unchanged;
- the oracle root links to the sealed baseline root;
- normal `--write` refuses to overwrite existing sealed files.

What it does not prove:

- 633 current Runtime behaviors are correct;
- the expected values are independent from implementation/data defects;
- current generated semantics still reproduce the snapshot;
- Action IDs remain valid across builds.

`--verify-source` currently fails because the production source moved Jamie
981/989 Type 35 semantics out of Legacy exceptions after sealing. The drift is
documented and intentional. The sealed snapshot remains valid as a historical
regression record, not as current semantic authority.

## 2. Oracle Challenges

### ORACLE-C001

| Field | Value |
| --- | --- |
| Case | Entire 633-case asset |
| Current expected | Historical exception projection |
| Current actual | Integrity check passes; no Runtime comparison exists |
| Expected source | Same generator and production data as baseline |
| Independence risk | HIGH correlation / LOW independence |
| Reason | The label `oracle` can be misread as independent Runtime truth |
| Disposition | `ORACLE_CONFIRMED` only as an immutable historical snapshot |

### ORACLE-C002

| Field | Value |
| --- | --- |
| Case | 488 records with unresolved provenance |
| Current expected | Sealed historical values |
| Raw evidence | Provenance not recovered in the governance baseline |
| Independence risk | LOW |
| Reason | Correctness cannot be reconstructed from cited evidence |
| Disposition | `AMBIGUOUS`; retain sealed, do not promote to current authority |

### ORACLE-C003

| Field | Value |
| --- | --- |
| Case | Jamie 981 and 989 Type 35 |
| Current expected | Historical Legacy exception placement |
| Current actual | Current source uses generated semantics |
| Raw evidence | Type 35 convergence audit and source drift |
| Independence risk | Expected and current are intentionally versioned differently |
| Disposition | `ORACLE_CONFIRMED` historical; current implementation not suspect |

No sealed oracle file was modified.

## 3. Golden Inventory and Independence

| Asset family | Role | Independence | Finding |
| --- | --- | --- | --- |
| `modern_display_builder/out/*.json` | Versioned official-data generator input | DERIVED | Not an expected-output golden suite; generator consumes it |
| `fixtures/current_move_graph/runtime-current.v1.json` | Checked-in generated Runtime fixture | MEDIUM | Hash/manifest checks plus hand-authored semantic assertions |
| Character exception baseline/oracle | Historical sealed snapshot | LOW | Same tool/source builds baseline and expected |
| Inline Lua/JS expected tables | Focused unit/module truth | MEDIUM or LOW | Mostly hand-authored, but often coupled to implementation contracts |

No normal test command was found that automatically refreshes golden or oracle
expected output. The sealed tool refuses overwrite. Other `--write` commands
are explicit maintenance tools and are not invoked by the test inventory.

Golden conclusion: there is no high-independence, current-build, real-game
golden corpus. The strongest current expected facts are hand-authored module
assertions combined with real corpus invariants and current generated artifact
hash/schema checks.

## 4. Assertion Quality

The Phase 1 static inventory found 60 validation assets:

- 53 contain semantic comparison assertions;
- 6 are dominated by source-text/static contract assertions;
- 1 could not be classified reliably by token screening;
- no asset qualifies as HIGH independence because no independently labelled
  real-game truth set is consumed.

The controlled mutation audit strengthens four critical areas: wrong Action
acceptance, side-relative projection loss, timeline event loss, and combo-count
false positives all cause focused tests to fail. This does not generalize to
all branches or establish a repository mutation score.

## 5. Build-Local Fixture Risk

Many fixtures hardcode Action IDs while relying on repository-wide canonical
game version data rather than embedding build identity in each small fixture.
This is acceptable for current-build focused tests but creates
`BUILD_LOCAL_FIXTURE_RISK` when a fixture is copied, archived, or compared
across versions. The all-accessible audit demonstrates the consequence: old
files remain parseable but may not resolve through the current command-display
projection.

Mitigation is offline migration and explicit build/provenance metadata. Runtime
Action-ID compatibility tables must not become cross-version identity.

## 6. Historical Regression Coverage

| User-facing category | Current evidence | Level | Remaining gap |
| --- | --- | --- | --- |
| Recording frame/input loss | RawInputCodec, ActionEventCompiler, input priority, corpus immutability | E3/E6 | No sustained real-game capture trace |
| Demo frame/input loss | Demo/playback unit paths and RuntimeAuditor fixtures | E2/E3 | No full-corpus demo injection trace |
| Timeline offset / demo slow frames | Timeline normalizer, `+5` translation invariant, timing auditor fixtures | E3/E6 | No REFramework frame-clock evidence |
| Extra inputs / missing inputs | Raw-mask roundtrip, ID-less negative matrix, timeline parser tests | E5/E6 | No real-game input injection count |
| Not recognized / wrong detection | 7,736 exact and near-miss controlled matcher cases | E5/E6 | Game observation and hitstop remain simulated/absent |
| Win11 list anomaly | Multicolumn list and source-contract UI tests | E2/E3 | No Win11 rendered UI smoke |
| Performance-caused timing error | Local-count guard and deterministic tests only | E1/E2 | No timing/performance budget or long game soak |
| HP flicker / delayed refresh | HpVital and SceneStateRuntime simulations | E3/E8-like narrow simulation | No real-game character refresh smoke |
| Pressure tail / repeated light | Validator and RuntimeAuditor semantic regressions | E3/E7 | No broad real-game character matrix |
| Leading Drive Rush / prefix | Action compiler, start-gate, RAW precursor buffer tests | E3/E7 | No real-game playback/detection loop |

Historical fixes are well represented by focused semantic assertions, but the
repository has no single traceable ledger mapping every historical issue or
user report to one regression test. Several archive names preserve context that
is not represented in checked-in issue metadata. This is Evidence Debt, not a
confirmed production bug.

## 7. Escalation Decision

`BUG_ESCALATION_TO_TASK_B`: none.

`ARCHITECTURE_ESCALATION_TO_TASK_A`: none.

The low-independence oracle is already marked `historical_regression_only` and
`runtime_source=false`, so it does not currently violate the canonical semantic
authority contract. The risk is overclaiming evidence strength, addressed by
this audit and the final Evidence Map.
