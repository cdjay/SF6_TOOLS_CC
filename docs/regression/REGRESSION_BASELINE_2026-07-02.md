# Regression Baseline - 2026-07-02

## Git Baseline

| Field | Value |
|---|---|
| Branch | `master` |
| Commit | `17facdbce6d4f3a190f456bfdb2b0ca475036c15` |
| Merge commit | `merge: integrate validator architecture and Honda rules` |
| Date | 2026-07-02 |

## Merge Summary

This baseline records the verified state after merging the combo trial validator architecture and Honda rule fixes.

Included work:

- Chun-Li / crouch / UI baseline fixes.
- ComboTrials validator architecture split:
  - `DebugTrace.lua`
  - `ActionMatcher.lua`
  - `CharacterRules.lua`
  - `Validator.lua` helpers
- Sagat same-action auto-advance diagnostics and fix.
- Manon `unique_resources` recording, saving, applying, and restoring.
- EHonda normal input dump for diagnosis.
- EHonda action id absorbs:
  - `605 -> 606`
  - `622 -> 624`
  - `926 -> 921`
  - `972 -> 973`
- EHonda recent absorb confirmation for delayed intentional-action verification.
- EHonda current absorb confirmation for final non-intentional absorb hits.

## Verified Characters

| Character | Result | Scope | Notes |
|---|---|---|---|
| Chun-Li | PASS | Completed check | No regression observed. |
| Sagat | PASS | Completed check | Same-action samples pass. |
| Manon | PASS | Completed check | Medal resource record / restore verified. |
| EHonda | PARTIAL PASS | Core samples verified | Known open issues are tracked separately below. |

## EHonda Core Samples

| Combo | AI demo | Verify | Key behavior |
|---|---|---|---|
| `EHonda_COMBO_2_8_HK_2646_D1_SA0` | PASS | PASS | `972` confirmed by `973` through `ehonda_current_absorb`. |
| `EHonda_COMBO_MP_2940_D0_SA0` | PASS | PASS | `605` confirmed by recent `606` through `ehonda_recent_absorb`. |
| `EHonda_COMBO_MP_3201_D1_SA0` | PASS | PASS | `605` confirmed by recent `606` through `ehonda_recent_absorb`. |

## Sagat Same-Action Samples

| Combo | Result | Notes |
|---|---|---|
| `Sagat_COMBO_2HP_5630_D6_SA3` | PASS | Same-action continuation auto-advance remains valid. |
| `Sagat_COMBO_6HK_4200_D0_SA1` | PASS | Same-action continuation auto-advance remains valid. |
| `Sagat_COMBO_6HK_4637_D0_SA2` | PASS | Same-action continuation auto-advance remains valid. |

## Manon Unique Resources

Verified behavior:

- Existing Manon JSON files restore medal display correctly when switching combos.
- New Manon recording with 5 medals saves successfully.
- Saved JSON restores medal count correctly during replay / verify.
- The recording start behavior still keeps `apply_forced_position(true)`; the rejected fourth diff was not merged.

## Known Open Issues

These issues are intentionally not blockers for this baseline and must be handled in separate branches.

| Area | Issue | Status | Next action |
|---|---|---|---|
| EHonda | `EHonda_COMBO_PARRY_6559_D5_SA3` third line fails | OPEN | Capture fresh `LastFail` and classify separately. |
| EHonda | `EHonda_COMBO_214_HP_6928_D2_SA3` finish / active bar stuck | OPEN | Capture finish-state snapshot separately. |
| EHonda | `EHonda_COMBO_214_HP_7018_D2_SA3` finish / active bar stuck | OPEN | Capture finish-state snapshot separately. |
| EHonda | Sun / sumo-spirit resource field | OPEN | Confirm UniqueData field before adding resource support. |
| Marisa | SA3 final step waits for recognition | OPEN | Capture `LastFail` / state separately; do not expand EHonda rules globally. |

## Required Regression Before Validator Changes

Before modifying `Validator`, `ActionMatcher`, `CharacterRules`, or character exception rules, re-run this minimum regression set:

| Character | Required checks |
|---|---|
| Chun-Li | Previously passing Chun-Li combo set. |
| Sagat | `Sagat_COMBO_2HP_5630_D6_SA3`, `Sagat_COMBO_6HK_4200_D0_SA1`, `Sagat_COMBO_6HK_4637_D0_SA2`. |
| Manon | Existing medal-resource JSON switching plus one recorded medal restore sample. |
| EHonda | `EHonda_COMBO_2_8_HK_2646_D1_SA0`, `EHonda_COMBO_MP_2940_D0_SA0`, `EHonda_COMBO_MP_3201_D1_SA0`. |

Record at least:

- `character`
- `combo_name`
- `ai_demo_ok`
- `verify_ok`
- `failed_step`
- `expected_id`
- `actual_action_id`
- `match_reason`
- `fail_reason_ui`
- `frames_since_prev_step`
- `expected_delay`
- `frame_diff`
- `combo_ok`
- `hp_ok`
- `timeline_demo_ok_but_validator_failed`

Do not continue with new character fixes if this baseline regresses without an explicit root-cause note and approval.
