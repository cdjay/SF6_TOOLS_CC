# Known Limitations

Status: `CURRENT`

This is the sole current list of evidence and architecture blockers. Green
offline tests do not remove these limitations. Keep entries current and short;
dated debugging logs belong in the archive. The September 2026
training-library expansion log was moved verbatim to
[the training-library archive](archive/training-library/KNOWN_LIMITATIONS_LOG_2026-09.md)
on 2026-10-09.

## Blocker Summary

| Limitation | Current state | Consequence |
| --- | --- | --- |
| Production authority | `Legacy` | No Runtime consumer may claim M5 or `MoveResolver` production authority. |
| M5 | Shadow only | Candidate results are diagnostic and `production_result` remains Legacy. |
| Frozen V2 | Unchanged | The `xt.combo_trial/2.0.0` schema and existing field meanings cannot be changed. |
| Human review | 179 stable-Move batches remain | No batch is approved automatically; ambiguous identities remain provisional. |
| Real-game smoke | Required; blocked pending a reviewed shadow harness; not complete | Current Main does not wire live MoveResolver shadow capture. Offline tests cannot prove REFramework callback order, live game observations, input injection, or visible playback. |
| Legacy OFF | Blocked | Legacy exception loading and compatibility behavior remain required. |
| Sealed oracle | 633 cases, independence `LOW` | It proves historical snapshot integrity, not independent Runtime truth. Runtime consumers execute `0 / 633` oracle cases. |
| Real-game golden | Unavailable | There is no current high-independence golden captured from live game truth. |
| Current corpus | 965 frozen current-build files | Strong serialization and offline-consumer evidence, but not a live-game end-to-end proof. |
| Historical corpus | 2,509 exact-unique cases | Contains mixed-build data; 34 current command-display gaps are expected historical incompatibilities. |
| Frozen archive | Loose source passes; archive unavailable | Current local status is `LOOSE_SOURCE_PASS_ARCHIVE_UNAVAILABLE`; no archive PASS may be claimed. |
| External tester storage | Retention not fully adjudicated | Historical packages under local `release/tester_packages` are not current source and must not be redistributed without provenance review. |
| Training library capacity | Native eight recording slots; the 80-slot expansion is retired (tag `training-library-v1.1.18-native8`) | More than eight concurrently enabled recordings is unavailable. Banks or files with more than eight recordings stay read-only until restored to native eight. |

## Training Library (Native Eight Slots)

Runtime scope: the startup entry uses the read-only `NativeEightRuntime`. It
does not mount an expanded recording bank, rebuild native record/play rows,
expand the reversal picker, or offer page reload. The independent Wood Library
tab keeps configuration selection, save, save-as, import, clear, note editing
and information. Only the game's native eight recording slots can be read or
changed. Files containing more than eight recordings stay visible in the
catalog but cannot be imported or overwritten by an eight-slot save. Entering
training never imports a configuration: native recordings, reversals and
training settings persist in the game's own data, and an import on entry could
only overwrite unsaved changes. Slot descriptions, which the game does not
store, are kept per P2 fighter for the Lua session and read from the
remembered configuration only the first time a fighter appears.

Live evidence (user, October 9, 2026): on the deployed `e8d0338` runtime a
cold start showed the tab and the "number - description" names on the record
and play lists, no import ticker on entry, a silent per-fighter configuration
switch on P2 change, no import after matchmaking or match return, and list
names updating after a rename. Earlier the same day the user confirmed a new
configuration, save/save-as/rename, a ranked match with return to training,
and the matchmaking hold. This is one live session, not a long-run stability
certification. Not yet confirmed live: legacy restore, 1P switching, and the
reversal picker/overview names.

Matchmaking hold: while searching for a match from training,
`BattleRule.GameMode` switches between 14 and 0 for about a second per attempt
while FlowMap stays 3. The gate treats this as an `online` hold (queue paused,
session kept) instead of leaving training. List reads check `get_Count` first,
because reading an empty `FighterDataList` during scene load previously raised
two engine ArgumentOutOfRangeException per frame.

Crash root cause and ownership rule (October 8): the 00:47 REFramework dump and
log show a freshly created playback menu row dying (refs 2 to 0) while the next
row was created, then an access violation in the engine's UpdateVM cycle
collector on a destroyed object, the same site as the September 15-16 expansion
crashes. REFramework Lua references are keyed by address and deduplicated, so
Lua cannot reliably own objects that game structures reference. Every injected
object therefore receives one permanent engine reference through
`NativeOwnership` and is never released from Lua; `create_*_global` is not
used; one root page is reused per Lua state; hook strings are cached permanent
strings; recording inputs are read and written in raw memory instead of boxing
one object per frame. Reintroducing per-session native allocation or Lua-side
release reopens this crash class.

Legacy 80-slot banks: an October 8 live read found Mai's bank still at 80 slots
from the old build. For such a fighter the tab stays visible, but the catalog is
read-only (save, import, clear and rename disabled) until the bank is eight
slots. A double-confirmed restore keeps slots 1-8, drops the rest, and clears
recording reversals pointing past slot 8. It never runs automatically and has
not been exercised live (Mai was already eight slots by October 9).

Configuration queue: closed-menu jobs wait for 30 update callbacks after a new
session, for SaveManager idle and for the training manager's save request to
clear, and refuse to run during native Release. This prevents confirmed
control-flow overlaps; the October 5 tester crash that prompted it still has no
crash report. Native Release and configuration snapshot reads remain outside
Lua exception handling for process-level access violations.

Script reset: reloading scripts inside training is not certified for the
native-eight runtime. Deploy updated files with the game closed and cold start.

Remaining WTT audit gaps: DYNAMIC dispatch still relies on owned object identity
instead of delegate ownership; stable menu GUID reuse, existing native object
lifetimes and dialog closing are not certified against the upstream contracts.
Data row creation is not GUI control creation. The upstream OptionManager dialog
recipe and C++ /EHa rule must not be blindly applied to Lua UITextInputDialog.
Absence of a Lua frame in a collector crash is not proof of plugin innocence.

Expansion beyond eight slots is deferred (user decision, October 9, 2026). Any
revival must meet the user's earlier functional floor: more than eight
recordings concurrently enabled, individual weights, and full enabled-pool
access for random playback and all three reversal triggers, without manual
rotation; swapping eight recordings at a time is not equivalent. Engine
constraints found during the September research: `FighterData.Init` allocates
eight slots, the `UpdateReversalCheck` candidate loop is fixed at ten entries,
`ChangeRecordSlot` does not range-check, the native save persisted an 80-slot
bank, an earlier save substitution relabeled a fighter's bank, and ownership
across the asynchronous save completion is unproven. Research notes live in the
ignored local `exam/native-training-library/` directory.

## Combo Trials Recording

ComboTrials recording remains available in training. In CFN replay, the legacy
recording entry, its hotkeys and remote recording commands are disabled
(`ComboTrials/RecordingPolicy.lua`), and the replay bottom recording bar is
hidden. Existing training/demo playback and training-library recordings are
unchanged. Recording in the new replay-analysis UI is planned, not yet
implemented. The training/replay recording scope has a focused regression, but
real-game acceptance is still required.

## AC+BCM Single Truth (branch `feature/acbcm-single-truth`, 2026-10-09)

Detection rules, display and the data guard now derive from AC+BCM where the
dumps allow it; the rest is blocked on evidence, not on code:

- **Dumps predate the fixed exporter.** Every 2026-08-03 dump lost the
  dictionary keys at or above `Count` (7–39 trigger groups per fighter) and all
  inherited key fields (frame windows). Cancel/follow-up relations
  (`trigger_group_report.js`: 10 pairs explained, 22 unexplained, 39 unknown)
  and hold thresholds (`hold_window_report.js`: 77 of 82 `is_holdable` rules sit
  on Type 20 keys, all `frame_window_missing`) can only be generated after a
  re-export with `tools/acbcm_exporter`. Until then `optional_parent_ids`,
  `charge_min`/`charge_max` and official-site follow-up text stay in use.
- **Generator gaps.** 34 overridden Actions have no BCM trigger and are absent
  from the generated tables (hold/phase/follow-up targets); about 13 would be
  covered by inheriting the source command, but counterexamples of the same
  branch type exist (Marisa 672/687, Mai 604, Guile 922), so they stay curated.
  Five overrides fix decode differences (Blanka 926/931 support-profile
  alternative buttons, C. Viper 1037, Cammy 979, Mai 907).
- **Runtime BCM fallback** shows only classic notation, and only while a fighter
  has no usable table; follow-up splitting, phase suppression and modern
  commands need the generated table.
- **Not live-verified:** the data guard and recording fingerprint warnings, the
  BCM fallback display, fallback-key combo migration, the `_charge_policy`
  move and the 10 fighters whose air normals gained landing phases (AKI, Alex,
  C. Viper, Ingrid, Ken, Lily, Luke, Manon, Ryu, Yasmine).
- **Release day unknowns:** the new fighter's ID (23/24/34 are unused in the
  August enums), whether the update moves existing Action IDs
  (`compare_acbcm_versions.js`), and REFramework compatibility.
- `MoveResolver`/`CurrentMoveGraph` remain unwired (see Blocker Summary).

## Dummy Guard Persistence

Dummy guard persistence has focused offline coverage but still requires a
real-game smoke. New training-library saves include the five verified native
guard fields; older v2 files intentionally leave the current guard state alone.
The shared training-mode guard override now restores the captured full state
when a mode closes, training becomes unavailable, replay/Battle Hub is entered,
or scripts reset. This fixes the proven old control-flow gap where leaving
training returned before restoration and the old fallback assumed no guard.
Offline tests do not yet prove native menu text refresh or persistence across a
full game restart.

---

The active review procedures are [Human Review](review/HUMAN_REVIEW.md) and
[Real-game Smoke](testing/REAL_GAME_SMOKE.md). Do not close a limitation by
editing this file alone; close the underlying evidence or architecture gate
first.
