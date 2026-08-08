# Writable Product Data: Exceptions Ownership Contract

**Status**: CURRENT Governance Contract / Runtime migration DESIGN_ONLY

**Scope**: `data/TrainingComboTrials_data/exceptions/` — 33 tracked JSON files, 489 action-level entries across 31 character files plus `Common.json` and `Unknown.json`.

**Classification**: `ACTIVE_RUNTIME_DATA` + product-default authority for evidence-backed Runtime exception rules. These files are not an AC/BCM semantic source of truth and must not become a second authority for Move identity or current-game Action relations. They are Git-tracked, included in every standard release package, and consumed by the Runtime semantic resolution pipeline. They are also **writable by Runtime code at game time**, creating a product-default / runtime-state mixed layer.

---

## 1. Current State Summary

| Property | Value |
|---|---|
| Tracked files | 33 |
| Total action entries | 489 |
| Character files | 31 (AKI through Zangief) |
| Shared files | `Common.json` (20 entries), `Unknown.json` (0 entries, placeholder) |
| Data purpose | Action detection behaviour rules: absorb, force-match, holdable timing, sequence grouping, transcription requirements, action event projection |
| Git status | Tracked source of truth |
| Release packaging | Included unconditionally via `git ls-files -- data` ([package_release.ps1:188](../tools/package_release.ps1)) |
| Runtime writability | **Yes** — 4 write paths modify tracked files at game time |

---

## 2. Runtime Readers

Every consumer reads through [CharacterRules.lua](../autorun/func/ComboTrials/CharacterRules.lua), never through direct file I/O.

### 2.1 Load Points

| Call site | File | Line | Trigger |
|---|---|---|---|
| `CharacterRules.load_common()` | CharacterRules.lua | 24 | MOD startup |
| `CharacterRules.load_for_character(name)` | CharacterRules.lua | 33 | Character switch |

Called from the entry script:

- `common_exceptions = CharacterRules.load_common()` — [TrainingComboTrials_v1.0.lua:136](../autorun/TrainingComboTrials_v1.0.lua)
- `p_state.exceptions = CharacterRules.load_for_character(p_state.profile_name)` — [TrainingComboTrials_v1.0.lua:5024](../autorun/TrainingComboTrials_v1.0.lua)

### 2.2 Per-Frame / Per-Action Consumers

| Function | Line | Called when |
|---|---|---|
| `get_exception(char, common, id)` | 39 | Every Action detection, combo validation, recording judgement |
| `get_match_rule(char, common, name, id)` | 46 | Action matching — shallow-merge common + character |
| `has_character_exception(char, id)` | 52 | Write-path routing (see Section 3) |
| `build_sequence_grouping_rules(char, common)` | 82 | Character switch |
| `build_transcription_rules(char, common)` | 116 | Recording compilation |
| `should_preserve_short_action(char, common, id)` | 141 | Recording compile phase |
| `build_action_event_rules(char, common)` | 177 | Character switch + recording compilation |
| `build_action_event_projection_rules(char, common)` | 243 | Character switch + recording compilation |
| `find_recording_absorb_owner(char, common, id)` | 362 | Recording — Action ownership resolution |
| `is_action_required(exception)` | 389 | Recording compile — auto-advance gating |
| `should_preserve_absorbed_transition(char, common, id)` | 396 | Recording compile — absorb transition filter |
| `find_recent_canonical_confirmation(char, common, ...)` | 419 | Combo validation — every frame |
| `match_current_canonical_confirmation(char, common, ...)` | 505 | Combo validation — current frame |
| `find_recent_absorb_confirmation(char, common, ...)` | 580 | Combo validation — absorb fallback |
| `match_current_absorb_confirmation(char, common, ...)` | 631 | Combo validation — current absorb match |

### 2.3 Memory Merge Strategy

`effective_exception_rules()` (line 160): common is the base, character shallow-merge overlays on top. When the same Action ID exists in both files, character fields completely replace common fields for that ID — no deep merge.

---

## 3. Runtime Writers

Four write paths exist. All use `json.dump_file()` for non-atomic, full-file overwrite.

### 3.1 Writer 1 — Auto-detect `charge_max`

- **File**: [TrainingComboTrials_v1.0.lua:5422-5430](../autorun/TrainingComboTrials_v1.0.lua)
- **Trigger**: JP or Lily character, `is_holdable` action, player releases hold button, `charge_max` is nil/empty
- **Writes**: `charge_max = current_log.hold_frames` (measured frame count)
- **Target routing**: If Action ID exists in character file → write character file; otherwise → write `Common.json`
- **Perception**: Silent — no user notification

### 3.2 Writer 2 — Auto-detect `charge_min`

- **File**: [TrainingComboTrials_v1.0.lua:6505-6517](../autorun/TrainingComboTrials_v1.0.lua)
- **Trigger**: Any character, intentional action, `is_holdable`, `charge_min` is nil/empty
- **Writes**: `charge_min = auto_detect_charge_min()` return value (engine-detected minimum hold frames)
- **Target routing**: Same as Writer 1 — character file if entry exists, otherwise `Common.json`
- **Perception**: Silent — no user notification

### 3.3 Writer 3 — UI Manual Save

- **File**: [ComboTrials_UI.lua:2319-2341](../autorun/func/ComboTrials_UI.lua)
- **Trigger**: User opens "Exception Management" panel (`例外管理`, line 2204), edits fields, clicks Save
- **Writes**: Full exception entry (ignore, force, is_holdable, absorb_ids, charge_min, charge_max, perfect_min, perfect_max, ignore_prev_id, ignore_prev_frames, hold_partial_check)
- **Target routing**: `edit_is_common = true` → writes `Common.json` + removes entry from character file; `edit_is_common = false` → writes character file only
- **Perception**: Shows "Saved" or "Critical error: cannot write file" status text

### 3.4 Writer 4 — UI Manual Delete

- **File**: [ComboTrials_UI.lua:2426-2431](../autorun/func/ComboTrials_UI.lua) (character), [ComboTrials_UI.lua:2472-2477](../autorun/func/ComboTrials_UI.lua) (common)
- **Trigger**: User clicks Delete button in Exception Management panel
- **Writes**: Removes entry from in-memory table, then `json.dump_file()` full overwrite
- **Perception**: Shows "Deleted from disk" status text
- **Note**: No confirmation dialog — one-click deletion

---

## 4. Access Control & User Visibility

The Exception Management panel (line 2204) is available to **all users** with no developer gate:

- No developer-mode detection
- No password or confirmation dialog for save
- No confirmation dialog for delete
- Auto-detection writes (Writers 1-2) are completely invisible to the user

A normal player using training mode may trigger silent file writes to their MOD installation directory without any awareness.

---

## 5. Write Safety & Corruption Risk

### 5.1 Non-atomic Write

All writes use `json.dump_file()` — REFramework's Lua binding. There is **no temp-file → rename atomic swap pattern**. A crash, power loss, or disk-full condition during `dump_file` may produce a truncated or empty JSON file.

### 5.2 Corruption Recovery

| File type | Load function | Corruption behaviour |
|---|---|---|
| `Common.json` | `safe_load_json()` ([SharedHooks.lua:35](../autorun/func/SharedHooks.lua)) | Detects corrupt/empty file, returns nil, logs to `_mod_errors.config_failures` |
| Character files | `json.load_file()` ([CharacterRules.lua:34](../autorun/func/ComboTrials/CharacterRules.lua)) | Corrupt file returns nil → treated as empty `{}` → **silently loses all character-specific exceptions** |

`safe_load_json` is **not** used for character exception files.

### 5.3 Concurrency

- No merge-on-save: UI save and auto-detection operate independently. If auto-detection fires while the editor panel is open, a subsequent UI save may overwrite the auto-detected values.
- Two-player scenario: P1 and P2 may both trigger auto-detection on the same frame, racing on the shared `Common.json` file. The last writer wins.

---

## 6. Two Contamination Scenarios

### 6.1 Normal Game Installation (User Mode)

REFramework runs from the Steam game directory. Exception files are MOD install copies. Runtime writes modify the **install directory copy** only:

- Git worktree: unaffected, stays clean
- Git-tracked source: unaffected
- MOD reinstall: overwrites user changes, losing auto-detected calibration and manual edits

This is the expected user scenario, but the data loss on reinstall is an unrecoverable side effect of the current mixed-layer design.

### 6.2 Direct Git Checkout (Developer Mode)

If REFramework is pointed at the repository root, Runtime writes **directly modify tracked files**:

- `git status` shows dirty `data/TrainingComboTrials_data/exceptions/`
- A subsequent `package_release.ps1` picks up the dirty content and **packages Runtime-modified exceptions into the release**
- This means a developer's local training session can silently alter the next release package's exception data

Recovery requires manual `git checkout` of the affected files. The modified values (e.g. auto-detected charge timings from one developer's machine) have no review and no evidence trail.

---

## 7. Field Classification: Semantic Patch Risk

### 7.1 Fields That May Mask Generator Defects

The following exception fields effectively **override or bypass the AC/BCM generator output**. If these exceptions were created because the generator produced incorrect results, they are hiding the defect rather than fixing it:

- `force` (206 entries): Force-accept an Action, bypassing normal matching
- `absorb_ids` (115 entries): Absorb multiple Actions into one logical move
- `optional_parent_ids` (59 entries): Relax parent matching
- `action_event_projection` (35 entries): Redefine Action projection relationships
- `ignore` (27 entries): Skip certain Actions entirely
- `action_event_rules` (15 entries): Modify action event compilation behaviour
- `action_alias_ids` (14 entries): Action aliasing
- `_character` (5 entries): Character-level strategy overrides
- `runtime_force_after_ids` (2 entries): Runtime force-match
- `action_alias_combo_deltas` (2 entries): Combo delta aliasing
- `action_required` (1 entry): Override auto-advance gating
- `record_absorb_as_parent` (1 entry): Override absorb recording

Per [Mandatory Architecture Constraints](../AGENTS.md): "Every exception must be evidence-backed, measurable, and explainable; exceptions must not hide generator defects." The current exception files contain **no `evidence` or `reason` field** — neither AI nor human reviewers can determine whether a given `force` or `absorb_ids` entry fixes a real game behaviour quirk or papers over a generator bug.

### 7.2 Display-adjacent Fields

Two entries in [Guile.json](../data/TrainingComboTrials_data/exceptions/Guile.json) contain match-notation strings:

- `optional_parent_motions`: `"214+PP"` (line 23)
- `follow_up_motion`: `">6+PP"` (line 24)

These are **ActionMatcher compatibility matching notations**, not UI display renderer output. They are consumed by the match/validation pipeline to resolve parent-child and follow-up relationships for Guile's special-cancel behaviour — they do not bypass or shadow the `command_display` generator output used by UI rendering.

However, they still represent a **second matching-authority risk**: if the AC/BCM generator's understanding of Guile's move relationships changes, these hardcoded motion strings remain frozen in the exception file and could diverge from the generator's current output. The risk is to action matching correctness, not to display rendering.

---

## 8. Three-Tier Ownership Contract (DESIGN_ONLY)

This contract is a **governance design proposal**, not an implemented change. No Runtime code or file layout has been modified.

| Tier | Name | Storage | Write Access | Lifecycle |
|---|---|---|---|---|
| **Tier 1** | Product Default | `data/.../exceptions/` (Git-tracked, release-packaged) | Read-only at Runtime | Version-controlled, updated via explicit commit |
| **Tier 2** | Local Runtime Override | `data/.../user/exceptions/` (Git-ignored, not packaged) | Runtime read/write | Governance goal: persist across MOD updates via installer cooperation. FMM or full-directory deletion may still destroy this layer — current implementation does not guarantee persistence. |
| **Tier 3** | Developer Authoring | Same as Tier 1 (Git-tracked) | Offline edit + review + commit only | Enters version control through explicit PR/commit workflow |

### Load & Merge Strategy (proposed, not implemented)

1. Load Product Default (Tier 1)
2. If Local Runtime Override (Tier 2) exists, load and shallow-merge it on top
3. Tier 2 fields override Tier 1 fields for the same Action ID
4. Auto-detection (Writers 1-2) writes **only to Tier 2**
5. UI editor writes to Tier 2 only. The UI may at most export an authoring candidate (e.g. a diff or proposed entry). Formal Tier 1 changes require offline developer authoring — explicit edit + review + commit to version control. Runtime must not provide a direct write path from game UI to Tier 1.
6. Deleting a Tier 2 entry (or writing a tombstone marker) restores the Tier 1 value

### Migration Strategy (proposed, not implemented)

Migration from the current mixed-layer state to the three-tier contract requires installer-assisted or manual audited migration. Runtime alone cannot reliably complete this migration because:

- Normal game installations have no Git baseline and therefore cannot differentiate historical product rules from learned calibration data by comparing against a commit.
- `charge_min`/`charge_max` values auto-detected by Writers 1-2 are indistinguishable from intentionally authored product defaults without external evidence.

Proposed migration workflow (not implemented):
1. Before upgrade, the installer/manager or a human operator preserves a copy of the legacy exception files as a migration snapshot.
2. An offline diff tool compares the preserved legacy files against a release-specific shipped baseline (e.g. a hash manifest or the corresponding Git tag).
3. Only entries with clear evidence of being local calibration (e.g. `charge_min`/`charge_max` not present in the shipped baseline) are migrated to Tier 2.
4. Ambiguous entries — where the diff cannot reliably determine provenance — are flagged for human review and must not be automatically migrated.
5. Runtime must not guess provenance, must not silently restore Tier 1 to any baseline, and must not perform migration on first run.

---

## 9. Phase 1 Scope Boundary

**Phase 1 does:**

- Document current state, risks, and ownership gaps
- Mark the three-tier contract as DESIGN_ONLY
- Record exact reader/writer line references for future Runtime tickets
- Flag `RUNTIME_DATA_OWNERSHIP_TICKET_REQUIRED`

**Phase 1 does NOT:**

- Modify Runtime code (no changes to `json.dump_file` calls, no atomic write, no file splitting)
- Move exception files (current directory structure preserved)
- Modify exception JSON content (no entries added, removed, or changed)
- Add UI gates (no developer-mode checks, no confirmation dialogs)
- Change `package_release.ps1` (no exceptions exclusion, no packaging path change)
- Refactor `CharacterRules.lua` (no API signature or logic changes)

---

## 10. Future Runtime Ticket: Proposed Scope

A future Runtime ticket implementing the ownership contract should cover:

- **Storage**: Establish a proposed local override path (e.g. `user/exceptions/` within the REFramework data tree), Git-ignored, excluded from release packaging
- **Load/Merge**: Implement Tier 1 → Tier 2 load-and-overlay with per-Action-ID shallow merge; support deletion tombstone so removing a Tier 2 entry falls back to Tier 1
- **Write safety**: Atomic write (temp-file + rename) for all exception file writes; extend corruption recovery to character files (use `safe_load_json` pattern)
- **Migration**: Installer-assisted or manual audited migration — preserve legacy files, diff against release-specific shipped baseline, migrate only evidence-clear local calibration entries to Tier 2, flag ambiguous entries for human review. Runtime must not attempt migration on its own; provenance ambiguity cannot be resolved at game time.
- **Release**: Verify that `package_release.ps1` does not include Tier 2 paths (current `git ls-files -- data` already excludes ignored files)
- **Tests**: Unit tests for merge priority, tombstone handling, atomic write recovery, and migration correctness
- **Live acceptance**: Verify `git status` stays clean after extended training session with auto-detection triggers and UI edits

The exact local override path, file naming, and merge implementation details are **not yet approved** — these are proposed design directions to be finalized in the Runtime ticket.

---

## 11. Related Documents

- [Documentation Authority](DOCUMENTATION_AUTHORITY.md) — Canonical document ownership hierarchy
- [AC+BCM Semantic Core](AC_BCM_SEMANTIC_CORE.md) — Unified action semantics contract
- [Architecture](../ARCHITECTURE.md) — Project architecture principles
- [AGENTS.md](../AGENTS.md) — Mandatory Architecture Constraints (exception evidence requirement)

---

## Status Flags

- `RUNTIME_DATA_OWNERSHIP_TICKET_REQUIRED` — Future Runtime work needed to implement the three-tier contract

`TICKET_1D_COMPLETE`
