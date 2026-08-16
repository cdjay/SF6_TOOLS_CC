# Character Exception Oracle Baseline

Status: `HISTORICAL_INTEGRITY_FIXTURE`

Snapshot: 2026-08-10

This immutable audit baseline is test evidence only. Production Runtime must never load it.

`--check` verifies this sealed fixture. `--verify-source` is diagnostic and is
expected to differ after reviewed Type35 convergence; current source equality
is not the oracle's contract.

## Summary

- Governance records: 633
- Historical Action exceptions: 484
- Production-loaded Legacy Action exceptions: 483
- Migrated Pilot Action exceptions: 1
- Character policy records: 5
- Presentation overrides: 132
- Historical compatibility mappings: 12
- Oracle cases: 633
- Verified generated provenance records: 1
- Unresolved provenance records: 488

## Category Counts

- A_AC_BCM_SEMANTIC: 183
- B_INPUT_COMMAND_SEMANTIC: 115
- C_RUNTIME_MECHANISM: 333
- D_PRESENTATION: 132
- E_HISTORICAL_COMPATIBILITY: 12
- F_UNKNOWN: 0

## Character Coverage

| Character | Fighter ID | Records |
| --- | ---: | ---: |
| AKI | 13 | 7 |
| Akuma | 22 | 21 |
| Alex | 31 | 17 |
| Blanka | 15 | 23 |
| Cammy | 9 | 16 |
| ChunLi | 4 | 11 |
| Common | - | 20 |
| CViper | 30 | 8 |
| DeeJay | 11 | 10 |
| Dhalsim | 8 | 16 |
| Ed | 19 | 16 |
| EHonda | 20 | 37 |
| Elena | 29 | 3 |
| Guile | 18 | 27 |
| Ingrid | 32 | 56 |
| Jamie | 21 | 61 |
| JP | 7 | 17 |
| Juri | 16 | 69 |
| Ken | 10 | 4 |
| Kimberly | 3 | 15 |
| Lily | 12 | 9 |
| Luke | 2 | 20 |
| Mai | 28 | 16 |
| Manon | 5 | 10 |
| Marisa | 17 | 27 |
| MBison | 26 | 13 |
| Rashid | 14 | 30 |
| Ryu | 1 | 7 |
| Sagat | 25 | 13 |
| Terry | 27 | 6 |
| Yasmine | 33 | 9 |
| Zangief | 6 | 19 |

## Artifacts

- Machine baseline: `tests/fixtures/character_exception_baseline.json`
- Legacy Oracle: `tests/fixtures/character_exception_legacy_oracle.json`
- Rebuild/check: `node tools/character_exception_baseline.mjs --write|--check`

Every record stores its source, raw rule, normalized result, consumers, effects, category, and provenance state. Unknown provenance is explicit and blocks semantic convergence until reviewed.
