# EHonda Regression Baseline - 2026-07-02

> Status: `HISTORICAL`. Current regression authority is executable tests; see
> [Testing Strategy](../../TESTING_STRATEGY.md).

## Purpose

This document freezes the EHonda validation baseline for the v0.9.1 Honda validation release checkpoint.

The goal is to record what is known-good now, what is intentionally deferred, and which JSON expectations must not be changed during this release.

## Verified Samples

| Combo | Result | Notes |
|---|---|---|
| `EHonda_COMBO_2_8_HK_2646_D1_SA0` | PASS | Current absorb confirmation validated. |
| `EHonda_COMBO_MP_2940_D0_SA0` | PASS | Recent absorb confirmation validated. |
| `EHonda_COMBO_MP_3201_D1_SA0` | PASS | Recent absorb confirmation validated. |
| `EHonda_COMBO_PARRY_6559_D5_SA3` | PASS under CA condition | Requires CA / low-health state. |

## 6559 CA Requirement

`EHonda_COMBO_PARRY_6559_D5_SA3` must be treated as a CA-condition sample.

Expected release behavior:

- CA / low-health condition passes with final action id `1221` and combo count `12`.
- Normal HP / normal SA3 produces action id `1215` and combo count `11`.
- The normal SA3 11-hit result is not a validator failure for this release.

The original 6559 JSON must keep:

- Step 15 `id=1221`.
- Step 15 `expected_combo=12`.
- `damage_at_step=6559`.

Do not lower the expected combo count to make the normal SA3 path pass.

## Deferred EHonda Issues

These items are intentionally sealed for this release and should be handled from a new post-release branch:

| Item | Status | Notes |
|---|---|---|
| `EHonda_COMBO_214_HP_6928_D2_SA3` | DEFERRED | Finish / active-bar stuck. |
| `EHonda_COMBO_214_HP_7018_D2_SA3` | DEFERRED | Finish / active-bar stuck. |
| EHonda sun / sumo-spirit resource | DEFERRED | Resource field not confirmed. |
| SA3 / CA requirements metadata | DEFERRED | Needs explicit requirements policy. |
| HP / Drive / Super start-state recording | DEFERRED | Needs JSON contract decision. |

## Release Guardrails

- Do not modify EHonda combo JSON as part of this release checkpoint.
- Do not modify `data/TrainingComboTrials_data/exceptions/EHonda.json` as part of this release checkpoint.
- Do not continue 6928 / 7018 diagnosis on this release branch.
- Do not continue requirements CSV cleanup on this release branch.
- Do not continue Marisa SA3 diagnosis on this release branch.

## Minimum EHonda Regression Set

Before changing EHonda validator rules after this release, re-check:

- `EHonda_COMBO_2_8_HK_2646_D1_SA0`
- `EHonda_COMBO_MP_2940_D0_SA0`
- `EHonda_COMBO_MP_3201_D1_SA0`
- `EHonda_COMBO_PARRY_6559_D5_SA3` under CA / low-health condition
