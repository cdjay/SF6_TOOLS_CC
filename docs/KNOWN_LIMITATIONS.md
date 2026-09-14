# Known Limitations

Status: `CURRENT`

This is the sole current list of evidence and architecture blockers. Green
offline tests do not remove these limitations.

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
| Native recording expansion | User confirmed paging and recording/playback on the fixed 80-slot build, native text entry, renaming and playback, then corrected right arrow and one Reset retaining expansion | The earlier unresponsive rename entry now works without a rename-code change; its intermittent cause is unproven. Independent per-row rename buttons are not implemented and name persistence across export/import awaits live acceptance. The old C# finalizer crash and intermittent Lua row-copy failure are not declared fixed. Development runtime allocates 80 recordings in ten pages, and retains 10 reversals per group. No slot deletion/renumbering. Names persist on explicit configuration export or save. Paging changes visible rows only, not playback eligibility. Autosaves use the entry training baseline. Pending native snapshots are bounded to four sessions; busy script reset may require restart. User confirmation is not exhaustive per-slot or lifecycle certification. |

Native Reset limitation (2026-09-14): retirement rejected a replaced recording
array after restoring menu rows, leaving an 8-row UI over an 80-slot bank.
The next Lua session correctly refused to adopt that residual bank. A new
retirement preflight prevents this predictable partial menu restoration, but
does not establish the replacement's cause or certify general Reset recovery.
That residual state required a full game restart. The user subsequently confirmed
normal right-arrow paging, slots and one Reset retaining expansion; this is not
general lifecycle certification. User confirmed the expanded reversal recording
picker works. Selected-configuration save failed on the engine's empty-table to
null/nil conversion; the narrowly scoped zero-frame buffer correction has offline
coverage and awaits live save/reimport acceptance. Configuration replacement
uses a verified original backup, not an atomic filesystem swap.

The subsequent A80 import/rename report exposed two separate display defects:
the name writer stopped after invoking array-only methods on `GetChildren()`;
expanded slots had valid `Frame` data but an empty native `SlotData.Title` GUID,
so the native frame-count label resolved to blank. Direct child getters and
inheritance of the original slots' localization templates now have red/green
offline coverage and are deployed for live retest, not yet accepted. The same
log later shows a busy-recorder Reset followed by rejected residual 80-slot
mounts; a full game restart remains required in that state. No ownership guard
was weakened to recover menu labels or reversal choices.

Follow-up A/B evidence: A still had its original names on disk; B had been
explicitly overwritten. Imports failed at the lazy-buffer initializer's old
eight-slot assertion with 20 empty buffers. The initializer now accepts up to
80 validated slots with bounded per-bank deadlines, and uses the exact native
ETrainingState overload. An 80-buffer import/edit/reimport simulation passes;
live acceptance remains pending. Reversal recording picker names now use the
same library names inside its owned native update scope; this is also pending
live acceptance, separate from the already accepted list capacity.

2026-09-15 follow-up: imports still failed after cold restart. Live read-only
inspection found InputData shared every eight expanded slots (9/17, 10/18,
etc.). The generic Title value-type copy used the boxed Guid size (32 bytes)
for a 16-byte inline field immediately preceding InputData. That path is now
removed: native DeepCopy transfers the template, expanded recordings are reset,
and all 80 slots/inputs/buffers are checked for independence from each other,
the original eight and the save baseline before mounting. Empty original slots
receive buffers only in the owned clone. A simulated SDK oversized Guid copy
reproduced the alias before the fix; fault-injected slot/input/buffer aliases
are rejected before mounting. These are offline tests, not live acceptance.
An already affected session requires a full game restart, not script reset.
All-empty native banks retain native title metadata; frame-label behavior on
their first imported recordings is not yet certified. This evidence does not
establish a slot-count/performance limit or justify reducing capacity alone.

Live follow-up (2026-09-15): the user confirmed A/B import switching and
rename/save/reimport isolation; the later-page screenshot also shows frame
counts. The remaining reversal-name defect is separate: the legacy fixed-row
ImGui annotations remain visible over the recording picker while its native
labels still show default slot numbers. The expanded-bank path now disables
that legacy overlay on both recording and reversal tabs; a panel regression
reproduces and guards against the leak. Native reversal-name replacement is
not accepted yet. Current MCP object/type requests failed; a bounded read-only
Lua writer trace in ignored exam storage awaits one menu/scroll sample. No
recording or configuration mutation is part of this display diagnosis.

The 00:32:29 Reset sample failed during native menu preparation with an access
violation caught in System.Array.SetValue. The session was not mounted, so both
record/play expansion and the reversal picker stayed at eight slots. This is
not a timeout and is not explained by the trace's 90-second observation bound.
The precise failing menu array operation/root cause is not yet established;
do not retry an uncertain native mutation or describe hot reload as reliable.
Cold restart is the current recovery recommendation. The same trace proved
that boxed Int32.ToString returned 305922504 for distinct slot indices, while
mValue held the correct 1..8 values. Picker naming now reads the typed mValue,
with regression coverage for the captured SDK behavior. Native name rendering
still needs live acceptance. The ten-row reversal overview is a separate UI
and does not yet have native custom-name rendering after disabling its overlay.

The subsequent cold start (00:38:39) also failed, this time because the new
slot's InputData was null after DeepCopy. A/B import was correctly refused at
the actual eight-slot capacity; missing paging and native rename rendering
were consequences of the unmounted session. Thus cold restart is a recovery
attempt, not a guaranteed fix. Failure messages now identify the slot and Init
versus DeepCopy stage, and menu failures retain their original traceback.
Inspection also found generic boxed-size struct copies in menu-row cloning;
the five Guid properties and Int2 limit now use their captured native setters.
Offline tests prohibit these unsafe direct struct writes. This known hazard
is removed, but it is not established as the cause of the null input or every
SetValue failure. The new plugin has no fixed-position ImGui annotations,
including the eight-slot fallback. Annotation data and editing are retained;
the intended rendering path remains native. Live mounting must pass before
repeating import/name acceptance; no automatic retry or ownership bypass was added.

The 00:49:03 cold-start sample failed with `sol_lua_push: ... is not a managed
object`, again leaving eight slots. A/B import was rejected twice at that actual
capacity. The original error discarded its preparation callsite. The session
now captures a bounded stage (baseline, slot Init/copy/buffer/array, verification,
or menu) and traceback only on failure. This improves evidence, not native
allocation reliability; the root cause remains open. Oversized import and slot
rename are now refused explicitly after expansion failure instead of reporting
a generic file error or accepting an invisible name edit.

The implementation has been extracted into `SF6CC_TrainingLibrary.lua` and its
private `SF6CCTrainingLibrary/` modules. Legacy DynamicRecords files are restored
unchanged. The standalone entry drives the queue, offline safety gate, native
menu, input dialog and its own REFramework panel. Do not load the old experimental
TrainingSlots/NativeLibraryPilot/NativeNotes entries alongside it, or the legacy
DynamicRecords autorun as a second recording writer. Independent loading and
queue ownership pass offline; subsequent real-game acceptance is recorded below.
Current Lua suite: 77/78 pass; the untouched Combo entry local-limit
gate remains at 166 versus 165. The 43 native-menu simulation checks pass.

Standalone cold-start follow-up at 01:06:23 on 2026-09-15: only the new entry
loaded, with no expansion failure in the captured log. A read-only WebAPI chain
from TrainingManager to Mai's RecordSlots returned get_Length = 80. The user
reported correct recording and reversal-picker names while viewing only, with
no manual import, rename or save performed. This accepts this one startup and
observed naming state, not A/B transactions, scrolling/recycling, hot reset,
or a proven fix for intermittent native allocation failures. The older
NativeLibraryPilot log prefix now comes from the private NativeMenu module,
not a second autorun entry.

The user subsequently accepted A/B/A switching and saved-name persistence.
A separate rename failure at 01:13:00 was traced to the installed REFramework
commit `a0e9010fb0449dc9d824b5978ee759eeaf50f7c6`: its Lua native-call argument
marshalling checks lua_isnumber before lua_isstring. Reopening a name `1111`
therefore passed double bits `0x40915c0000000000` where OpenTextInputDialog
expected a System.String; that exact value appears in the fault's RCX register.
The editor then intentionally halted further requests after the native error.
The standalone NativeNoteEditor now creates an explicit managed prefill string,
roots it through the dialog and releases its reference on completion. Regression
tests reproduce the installed marshalling order and cover numeric strings,
leading zeroes, exponent/hex/decimal forms, empty text, repeated edits and failed
factory cleanup. No configuration contents or DLL were changed.

Final user acceptance on 2026-09-15 after the managed-string fix: configuration
switching, saving, repeated slot renaming, recording, playback and the reversal
list all worked, with no reported problems. This closes the numeric-name reopen
defect and accepts the current standalone library's tested functional workflow.
It does not establish a retrospective cause for the earlier intermittent native
allocation failures or imply unreported lifecycle stress tests were executed.
No further runtime change, commit, package or push was requested at acceptance.

Subsequent cold starts reproduced missing pagination on the same accepted
19-file runtime, verified against the recorded 01:26:32 acceptance point.
`NativeRecordingSession.prepare` failed at slot 34 or 52 after native
Init/DeepCopy left InputData unreadable, before bank attachment or pager setup.
The native allocation root cause remains open; menu rollback did not resolve it.
A failure-only diagnostic now records source/target raw input fields, reference
counts and native method addresses. It does not retry, repair pointers, reduce
capacity, or change menus/configuration. This is diagnostic, not a proven fix.

The 02:17:30 snapshot narrowed this to native target lifetime: slot 23 had
reference count zero, no type/Frame/InputData, while its source remained valid.
Upstream [REFramework #1448](https://github.com/praydog/REFramework/issues/1448)
describes local-object promotion leaving a temporary Lua wrapper whose finalizer
can release the live object; [#1504](https://github.com/praydog/REFramework/pull/1504)
adds global factories to root the object before exposing it to Lua. Both the old
and global instance factories are present in the installed commit cited above.
The standalone session now uses `sdk.create_instance_global` for new SlotData
only, retaining its existing owned-reference cleanup and capacity. A fake-SDK
regression models that promotion/finalizer path through the actual session and
runtime: the old factory loses the native target and paging; the new factory
passes at allocation boundaries 1/23/52/80. All 25 runtime integration cases pass.
Cold-start validation at 02:27:33 rejected this as a fix: the deployed global
factory still failed at slot 57, with Init=false, target refs=0/type unavailable
and a valid source. The 25-case fake-SDK result models an upstream hypothesis;
it is not a reproducer or proof of the live root cause. No fix is accepted.
The next diagnostic records only the current slot's created/retained/initialized/
before-copy/copied address, reference count and type, emitting them on failure.
It does not add retries, native allocations, writes, GC controls or capacity
changes. Four injected lifetime-loss boundaries verify diagnostic attribution;
26 fake-SDK runtime cases pass. Menus, configs and DLL are unchanged, and the
global-factory attempt remains in place for a like-for-like boundary capture.

The 02:35:26 boundary capture reproduced slot 57 again: created and retained
both reported refs=1 and the correct SlotData type; initialized reported refs=0
and no type, before DeepCopy was called. This localizes loss across the Init
call boundary, but does not identify the exact releasing instruction or thread.
The next candidate changes only private-bank construction order: SetValue and
readback precede Init, giving the slot a native array owner while initialization
runs. The array is still unmounted until all ownership checks and menu preparation
succeed. No new permanent references, retries, capacity changes, or early live-bank
attachment were added. The observed one-reference loss is injected at slots
1/23/57/80 in a fake SDK; the old order loses the target and paging, while the new
order passes. All 27 runtime cases pass, including rejection of partial failures
and late slot/input/buffer aliases. Boundary evidence remains for real-game
validation; this candidate is not yet accepted as a live fix or a release.

Before candidate deployment, the user authorized discarding all test recordings
and questioned the constructed A/B files. All eight saved configs parsed and
passed the shared 80-slot layout check; valid recordings had no missing buffers,
capacity overflow or timing truncation. Their contents are not consumed on the
failing Init path (automatic import follows successful session attachment).
Game-area test storage was cleared without creating another backup: eight
configs, 137 old test backup JSONs, and three index/selection/backup markers.
The editor and runtime scripts were preserved. Next cold start tests an empty
configuration directory with the existing boundary-diagnostic runtime; the
private-array-order candidate remains development-only to isolate this variable.

The subsequent 02:43 cold start with no saved configs had no expansion error.
Read-only MCP confirmed FighterID=28 and RecordSlots.get_Length=80; the installed
session hash was still FCD359CE7CD44C09951B166B4AC2C1C2079464B39D7E3C09A955B02D4C5AC70B,
not the private-array-order candidate. This is one successful empty-library
startup, not evidence that A/B JSON is corrupt or that the intermittent lifetime
defect is resolved. Configuration-reading allocation pressure or changed timing
remain hypotheses; visible paging and subsequent operations await user feedback.

The user accepted all visible operations in the empty-library run and exported
Mai_20260915_024812.json from live native data (80 slots, six valid recordings,
three reversal groups of ten). JSON/layout and valid input/frame bounds passed;
live RecordSlots remained 80 immediately after export. The next cold start at
02:51:04, with only this fresh export, again failed at slot 57: created/retained
refs=1, initialized refs=0/type unavailable. Thus old constructed A/B files are
not required to reproduce the defect. Keep the fresh export for the next test;
do not delete configs again. Private-array ownership before Init remains the
single prepared runtime candidate. After the user closed the game, only
NativeRecordingSession.lua was deployed with SHA256
66D942059F110BBE20075B7B52FF4D5530D70EA9C1420E876D35B986DF43D9CC.
The fresh export's hash was unchanged; isolated deployed dependency and standalone
entry gates passed. Cold-start acceptance of this candidate is still pending.

The user subsequently reported everything normal on the 02:56 cold start with
the fresh exported configuration present. The installed hash still matched
66D942059F110BBE20075B7B52FF4D5530D70EA9C1420E876D35B986DF43D9CC;
read-only MCP confirmed RecordSlots length 80, and the startup log had no slot
initialization/lifetime failure. This accepts the reported paging/configured
startup workflow for the private-array-before-Init change, not prolonged stress
or an identified native releasing instruction. Do not attribute the problem to
corrupt A/B JSON. Preserve the tested runtime without additional menu changes;
failure-only boundary diagnostics remain pending separate cleanup/revalidation.
No commit, release package or push was performed for this acceptance.

The accepted standalone runtime was saved in commit `82b7d4f` before the next
menu-only iteration. That iteration changes native row order/separators and
display labels only: character/config labels, bilingual character details and
the UI term 栏位. Selection still does not import, import still requires its
existing confirmation, notes remain notes, and no config-rename operation was
added. NativeRecordingSession and its tested allocation order are untouched.
The user subsequently accepted the display-only iteration in game.

The next scoped change replaces the native edit-notes row with configuration
title editing. It reuses the native dialog and deferred transaction, changes
only the saved JSON title, preserves the file path and refreshes selection by
that path. It does not rename files, import recordings or change the accepted
80-slot initialization. Blank titles are rejected; overlength existing titles
use an empty prefill for replacement, never a silently truncated write. Offline
storage/controller/native-dialog/menu checks pass (78/79 Lua files overall;
the existing Combo top-level-local ceiling failure remains). Live title editing
acceptance is pending.

At 2026-09-15 03:21:31, following Lua-only deployment and an in-training
Reset Scripts, the user reported pagination missing again. The unchanged
NativeRecordingSession hash above failed at slot 23: created/retained refs=1,
private-array-owned refs=2, then immediately after Init refs=0/type unavailable;
InputData remained unavailable before/after DeepCopy. Read-only MCP confirmed
FighterID 28 still had eight RecordSlots. This reopens initialization stability:
private-array ownership is not a complete fix, and the offline simulated
single-reference-loss test is not a reproducer of this new 2-to-0 native loss.
Numerous Lua reference-release warnings also occurred during Reset; their
causal relationship is not established. The error preceded config autoload.
No runtime repair, config deletion, pointer write or automatic retry was made.
Log and deployed session source were retained in the system temporary directory
`sf6cc-reset-slot23-20260915-032354`. An unchanged-code cold restart is the next
operator comparison; do not claim that either hot reset or cold start is now
proven reliable, or attribute this incident to fabricated configuration files.

The user's subsequent unchanged-code cold start at 03:26:09 also failed:
03:27:06 reports slot 52 with the same private-array refs=2 to initialized
refs=0/type-unavailable transition. This excludes a Reset-only explanation.
To test the title-edit regression hypothesis without changing allocation or
configuration data, only the five title-edit runtime modules were returned to
the previously accepted menu-display version; associated tests were restored.
The candidate and cold-start log are retained in the system temporary directory
`sf6cc-title-rollback-20260915-032902`. Seven focused test files pass on the
rollback. An identical-config cold-start comparison of this rollback is pending;
neither title-edit causality nor initialization recovery is yet established.

After that scoped rollback, the user confirmed pagination recovered on the
03:33:14 cold start. The new log shows the standalone entry at 03:33:25 and no
TrainingLibrary initialization failure at inspection. Configurations and the
allocation module were not changed during rollback. This is a positive
before/after comparison implicating the title-edit change set, not proof of a
specific releasing instruction or deterministic root cause. Keep the rollback
deployed; title editing remains withdrawn. Any reimplementation must isolate
the triggering change instead of dismissing it as unrelated or changing the
accepted pagination mechanism at the same time.

The recovered menu baseline was committed as `8224814`. A subsequent minimal
title-edit candidate reuses the existing editor request and deferred file job,
replacing only the edited JSON field and prefill text contract. It introduces
no new editor mode, native hook or request argument. Four Lua modules were
deployed; Records, the entry, native bank/pager modules and configuration files
were unchanged. The real controller/store integration test covers title-only
writes, stable path selection, repeated edits, cancellation and conflicts.
Offline results are 79/80 Lua test files (same existing Combo locals failure).
Cold-start pagination followed by title editing is still awaiting user
acceptance; this candidate is not proof of the initialization failure's cause.

The user subsequently accepted the minimal candidate with four screenshots:
configuration label shows 测试配置功能; recording page 10/10 displays slots
73-80; playback paging and the renamed first slot remain visible; the reversal
recording picker shows the same slot name and entries beyond slot 8. A read-only
check confirmed title 测试配置功能, FighterID 28 and 80 slots in the unchanged
filename Mai_20260915_024812.json. The log for the 03:44:55 entry load had no
TrainingLibrary initialization error at inspection. This accepts the reported
configuration-renaming workflow and accompanying UI regression check, not all
reset/lifetime scenarios or a root-cause explanation of the previous candidate.
No new commit, package or push was made for this acceptance.

The active review procedures are [Human Review](review/HUMAN_REVIEW.md) and
[Real-game Smoke](testing/REAL_GAME_SMOKE.md). Do not close a limitation by
editing this file alone; close the underlying evidence or architecture gate
first.
