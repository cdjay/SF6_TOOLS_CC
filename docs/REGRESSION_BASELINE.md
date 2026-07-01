# Regression Baseline - 2026-07-02

## Git baseline

- Branch: `master`
- Commit: `17facdbce6d4f3a190f456bfdb2b0ca475036c15`
- Merge commit: `merge: integrate validator architecture and Honda rules`

## Purpose

This baseline records the verified state after integrating:

- Validator architecture split
- Sagat same-action auto-advance fix
- Manon unique resources record / restore
- EHonda action id absorbs
- EHonda recent absorb confirmation
- EHonda current absorb confirmation

## Verified characters

| Character | Result | Notes |
|---|---|---|
| Chun-Li | PASS | Existing verified combos passed |
| Sagat | PASS | Same-action samples passed |
| Manon | PASS | Existing JSON and medal resource restoration passed |
| EHonda | PARTIAL PASS | Core samples passed; remaining edge cases tracked separately |

## EHonda verified core samples

| Combo | Result | Notes |
|---|---|---|
| `EHonda_COMBO_2_8_HK_2646_D1_SA0` | PASS | `972 -> 973` current absorb confirmed |
| `EHonda_COMBO_MP_2940_D0_SA0` | PASS | `605 -> 606` recent absorb confirmed |
| `EHonda_COMBO_MP_3201_D1_SA0` | PASS | `605 -> 606` recent absorb confirmed |

## Sagat verified samples

| Combo | Result | Notes |
|---|---|---|
| `Sagat_COMBO_2HP_5630_D6_SA3` | PASS | Same-action auto-advance |
| `Sagat_COMBO_6HK_4200_D0_SA1` | PASS | Same-action auto-advance |
| `Sagat_COMBO_6HK_4637_D0_SA2` | PASS | Same-action auto-advance |

## Manon verification

| Item | Result | Notes |
|---|---|---|
| Existing 4 Manon JSON files | PASS | Medal display restored correctly when switching JSON |
| New 5-medal recording | PASS | JSON saved correctly; playback restored medal count correctly |

## Known open issues

These are intentionally excluded from this baseline and should be handled in separate branches:

| Issue | Status | Notes |
|---|---|---|
| `EHonda_COMBO_PARRY_6559_D5_SA3` | OPEN | Third line fails; needs fresh LastFail |
| `EHonda_COMBO_214_HP_6928_D2_SA3` | OPEN | Finish / active-bar stuck |
| `EHonda_COMBO_214_HP_7018_D2_SA3` | OPEN | Finish / active-bar stuck |
| Marisa SA3 final step | OPEN | Last step waits for recognition; needs separate LastFail / State |
| EHonda sun / sumo-spirit resource | OPEN | UniqueData field not confirmed |

## Regression rule going forward

Before modifying Validator, ActionMatcher, CharacterRules, or character rules, re-check:

1. Chun-Li sample set
2. Sagat same-action 3 samples
3. Manon resource restore sample
4. EHonda core samples:
   - `2646`
   - `2940`
   - `3201`

A fix is not acceptable if it regresses any of these unless the regression is explicitly explained and approved.