# SF6 Combo Trial File Format — v2.0.0 (FROZEN)

> Joint specification for WTT/SF6_Tools and SF6_TOOLS_CC (+ SF6CM), so
> combo files recorded in either project replay in the other, permanently.
> Status: **frozen**. Editorial corrections do not change schema 2.

## 1. Goals

1. A combo file recorded by any compliant tool replays in every compliant tool.
2. Old files never break: readers accept every schema version they know, and
   ignore fields they don't.
3. Ecosystem components (mods, sites, trays) can tell which versions produced a
   file and whether they can handle it — without parsing heuristics.

## 2. File shape

A combo file is a JSON **array of steps**. Step 1 additionally carries the
file-level payloads:

```
[ step1 = { <step fields> + _xt_meta + scene_state? + raw_inputs? + combo_stats
            + start_pos_* + timeline? + recorded_by },
  step2 = { <step fields> },
  ... ]
```

### Step fields (all steps)

| Field | Type | Meaning |
|---|---|---|
| `id` | int | Action id of the expected move |
| `motion` | string | Display/matching notation ("5HP", "236+P", "> 214+P"…) |
| `motion_aliases` | string[]? | Extra notations accepted by the matcher (§3d) |
| `expected_combo` | int | Combo counter expected after the previous step |
| `expected_hp` | int? | Combo actor HP expected at this step (validation, NOT either player's starting HP — see §3c) |
| `delay_from_prev` | int | Frames between this step and the previous one |
| `counter_type` | int | 0 normal / 1 CH / 2 PC required on this step |
| `victim_pose` | int? | 0 stand / 1 crouch (live pose at recording) |
| `dummy_action_type`, `dummy_jump_type` | int? | Configured dummy behavior (step 1). Action: 0 stand / 1 crouch / 2 jump / 3 play native recording / 4 human control / 5 CPU. Jump: 0 vertical / 1 front / 2 back / 3 random |
| `dummy_guard_type` | int? | Configured dummy guard (step 1): 0 none / 2 guard after first hit / 3 all / 4 random / 5 count guard. A short-lived local editor build emitted 1 incorrectly; readers SHOULD normalize 1 to 2. `dummy_guard` is a legacy reader alias and MUST NOT be written by v2 writers |
| `dummy_guard_count` | int? | User-visible guard count (1–30), meaningful when `dummy_guard_type` is 5. Game runtime stores this value minus one. Optional; missing readers MUST preserve the room value |
| `is_holdable`, `hold_frames`, `hold_partial_check` | — | Hold system |
| `dual_threshold`, `is_projectile_hit`, `group_id`, `facing_left` | — | Matching helpers |
| `validation_role` | string? | e.g. `"pressure_tail"` (CC) |
| `actual_combo`, `has_hit`, `damage_at_step` | — | Runtime; writers SHOULD reset, readers MUST ignore |

#### Optional native dummy-menu environment (step 1)

These fields mirror the game Dummy Settings menu. New recordings SHOULD write
the complete current set. They are additive v2 fields: an old JSON that omits
them keeps the reader's established legacy behavior and MUST NOT be bulk-filled
with guessed values.

Canonical storage is `_xt_meta.environment`; SF6CC also writes the same scalar
aliases on step 1 and `_xt_meta` for existing WTT-style readers.

| Field | Type / native mapping |
|---|---|
| `dummy_cpu_level` | int?; user-visible CPU level 1–8 (native value is minus one) |
| `dummy_counter_type` | int?; 0 normal / 1 counter / 2 punish counter / 3 random |
| `dummy_counter_weight_normal`, `dummy_counter_weight_counter`, `dummy_counter_weight_punish` | int? 0–10; native `T` detail-menu weights |
| `dummy_guard_switching` | bool?; native guard switching |
| `dummy_guard_weight` | int?; native raw guard weight |
| `dummy_guard_only_type` | int?; 0 normal / 1 standing guard only / 2 crouching guard only / 3 random |
| `dummy_drive_parry_type` | int?; 0 inactive / 1 active / 2 perfect parry / 3 random |
| `dummy_drive_reversal_type` | int?; 0 inactive / 1 after guard / 2 on wakeup / 3 random |
| `dummy_drive_reversal_delay` | int?; user-visible delay frames |
| `dummy_drive_reversal_count` | int?; user-visible activation count (native value is minus one) |
| `dummy_drive_reversal_weight_none`, `dummy_drive_reversal_weight_guard`, `dummy_drive_reversal_weight_wakeup` | int? 0–10; native `T` detail-menu weights |
| `dummy_throw_escape_type` | int?; 0 inactive / 1 active / 2 random |
| `dummy_throw_escape_weight` | int?; native raw random weight |
| `dummy_wakeup_type` | int?; 0 in-place recovery / 1 back recovery / 2 random |
| `dummy_wakeup_weight` | int?; native raw random weight |
| `dummy_jump_weight_front`, `dummy_jump_weight_vertical`, `dummy_jump_weight_back` | int?; native raw random-jump weights |

Raw weight fields are deliberately not normalized to percentages: the game
uses different internal units in different detail menus.

### File-level payloads (step 1)

| Field | Meaning |
|---|---|
| `_xt_meta` | Authoring metadata + versioning — see §3 |
| `scene_state` | Playback preconditions snapshot — see §3c |
| `raw_inputs` | uint16[] — raw per-frame input stream for native-fidelity DEMO playback. **Optional** (§5) |
| `combo_stats` | Result analytics ONLY: `{ damage, drive_used, super_used }` — consumption/outcome, never starting state (§3c) |
| `start_pos_p1/p2` (+`_raw`) | Recorded positions |
| `recorded_by` | 0/1 — recording side (orients `scene_state.players`) |
| `timeline` | Step-timeline DEMO data — supported playback source when `raw_inputs` is absent (§5) |

## 3. `_xt_meta` — authoring metadata and versioning carrier

```json
"_xt_meta": {
    "schema": 2,
    "title": "", "author": "", "note": "", "tags": [],
    "step_notes": ["", "Slight delay before 236MK", ""],
    "language": "en",
    "control_mode": "classic",
    "created_at": "2026-07-13T18:00:00+02:00",
    "updated_at": "2026-07-14T12:00:00+02:00",
    "versions": {
        "game":     { "id": "sf6", "version": "1.14.2" },
        "recorder": { "id": "wtt", "version": "2.9.0" },
        "framework":{ "id": "reframework", "version": "1.5.9.1" },
        "json":     { "id": "xt.combo_trial", "version": "2.0.0" }
    },
    "environment": { ... }
}
```

- `schema` (int): **major** version of the step/file layout. Bump ONLY on
  breaking change (field renamed/retyped/removed).
- `versions.*`: structured `{ id, version }` objects. `game` covers act-id
  drift between patches; `recorder` identifies the producing tool
  (`wtt`, `sf6cc`, `sf6cm`); optional `framework` identifies the host runtime;
  `json` is the format version.
  **RESOLVED (review pass 1):** format id is the neutral `xt.combo_trial`;
  the `id` field MAY be omitted on the `json` entry (the format is already
  identified by `schema` + this spec) — `"json": { "version": "2.0.0" }`
  is valid. Platforms add their own `distribution` entry if needed.
- `step_notes` (string[]): per-step community annotations, **index-aligned
  with the step array** (empty string = no note). Kept in `_xt_meta` so the
  step objects stay engine-only.
- `language` (BCP-47): authoring language of title/note/tags/step_notes.
  Notations ("236+HP") are language-neutral by design.
- `control_mode`: `"classic"` or `"modern"`. Recorded inputs and expected
  actions are NOT portable across control modes; tools must be able to
  filter on it. Absent = assume classic (legacy files).
- `created_at` / `updated_at`: **ISO 8601 with timezone offset**. `updated_at`
  changes on any re-record, fix, note edit or game-version adaptation —
  community platforms rely on it for sync.

## 3b. Explicit playback preconditions (principle)

Everything required to replay a combo MUST be explicitly declared in the file —
never inferred from titles, notes or filenames. The complete precondition set:

| Precondition | Where |
|---|---|
| Positions | `start_pos_p1/p2` (+`_raw`) |
| Dummy behavior (stance/jump/guard config) | `dummy_action_type` + `dummy_jump_type` + `dummy_guard_type` (step 1), `victim_pose` per step as live fallback |
| Starting resources (HP/drive/super) | `scene_state.players.*.resources` (§3c) |
| Unique resources (installs, stocks, drinks) | `scene_state.players.*.unique` |
| Character status (stun, burnout, stance) | `scene_state.players.*.status` (§3c) |
| Counter/punish requirements | `counter_type` per step |
| Control mode | `_xt_meta.control_mode` |
| Recording side | `recorded_by` |

A reader that honors this table needs zero heuristics before pressing play.

## 3c. `scene_state` — playback preconditions snapshot (v2)

Starting state is NOT the same thing as consumption: `drive_used` is what the
combo spends; the drive value before playback is a precondition. The two live
in different places:

```json
"scene_state": {
    "schema": "xt.combo_trial.scene.v2",
    "recorded_by": 0,
    "players": {
        "p1": {
            "fighter_id": 21,
            "resources": { "hp": 10000, "drive": 60000, "super": 20000 },
            "status": { "burnout": false, "stunned": false, "stance": "standing" },
            "unique": { "stock_0_021": 2 }
        },
        "p2": { ... }
    }
}
```

- `resources`: exact starting values injected before playback.
- `status`: `burnout` (bool), `stunned`/piyo (bool), `stance`
  (`"standing" | "crouching" | "airborne"`).
- `unique`: per-fighter unique resource map (unchanged from scene.v1).
- SF6 training settings expose one shared `ParameterSetting.UniqueData` map.
  When both sides use the same fighter, writers MUST emit the same value for
  the same unique-resource key on both sides. Readers resolve a conflict in
  favor of the recorded combo actor.
- `combo_stats` keeps ONLY result analytics: `{ damage, drive_used,
  super_used }`.
- scene.v1 files (unique only) remain valid; readers fall back to legacy
  behavior for missing blocks.

## 3d. Action id drift and `motion_aliases`

Real-world case (E.Honda Sumo Spirit, verified 2026-07-14): install states can
CHANGE the action ids of empowered normals (5HP under Sumo Spirit is a
different id than normal 5HP — and the install move itself shifts id too).
Matching MUST therefore accept id OR normalized notation, and files SHOULD be
able to declare equivalences explicitly:

```json
{ "id": 970, "motion": "5252+K", "motion_aliases": ["22+K"] }
```

- Matchers normalize notations (uppercase, strip whitespace and whiff markers)
  and accept `motion` or any alias.
- The unified per-character command table maps variant IDs to the canonical
  Classic, Modern Simple, and Modern Motion projections. Exception files only
  control detection behavior and never override recorded or displayed notation.

## 4. Compatibility rules

1. **Readers MUST ignore unknown fields** (both file-level and step-level).
2. **Writers MUST NOT reuse a field name with different semantics** — new
   meaning = new name (+ schema bump if breaking).
3. Additive changes (new optional field) do NOT bump `schema`.
4. A reader seeing `schema` > its known max SHOULD still attempt playback with
   known fields, warning the user, unless the file declares
   `requires_strict: true` in `_xt_meta`.
5. Runtime fields (`actual_combo`, `has_hit`, …) are never meaningful on disk.
6. Sidecar runtime files (e.g. `CompletedTrials.json`) MUST live outside the
   per-character combo directories.
7. **`raw_inputs` is optional.** A file without it is fully v2-compliant;
   `timeline` remains a supported playback source (not deprecated). When both
   are present, `raw_inputs` takes precedence for DEMO fidelity.
8. **No batch conversion required.** Existing community JSONs (schema 1 /
   scene.v1) stay valid forever; tools upgrade files opportunistically when
   re-saving.
9. Raw input portability caveat: `raw_inputs` streams are only guaranteed
   meaningful for the same `control_mode` and may drift across `versions.game`
   — players SHOULD be warned when either differs, and `timeline` used as the
   fallback source.

## 5. Remaining open questions

| Topic | Status |
|---|---|
| Unique-resource capture: menu vs live overlay (`mStyleNo`) | WTT captures live-gained resources too; recommended behavior, same format |
| Dummy behavior: `environment` (configured) + `victim_pose` (live fallback) | Both kept; precedence = configured first |
| Localization of display strings | Files store neutral notation; localization stays in the UI layer |
| Completion tracking sidecar name/key format | `CompletedTrials.json`, lowercased forward-slash path keys — confirm |

## 6. Version history

| `schema` | Date | Changes |
|---|---|---|
| 1 | 2026-06 | `_xt_meta` introduced (author/title/tags/created_at) |
| 2 rev 1 | 2026-07-13 | `versions` block, `language`, `control_mode`, `environment`, `raw_inputs`, `scene_state`, `motion_aliases`, explicit-preconditions principle, compat rules |
| 2 rev 2 | 2026-07-14 | Review pass 1: `resources`/`status` in scene_state (start state ≠ consumption), `step_notes`, ISO 8601 + `updated_at`, structured `versions` objects, raw_inputs optionality + timeline status + no-batch-conversion rules |
| 2.0.0 errata | 2026-07-26 | Freeze status; clarify actual `expected_hp` actor semantics; document optional REFramework host version, numeric `dummy_guard_type`, count guard, and the additive native Dummy Settings environment fields (including `T` detail weights). No JSON layout change. |
