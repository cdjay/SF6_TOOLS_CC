# CFN Replay Capture Experiment

Status: experimental, excluded from normal product releases; standalone preview packaging is explicit. Common-interval live
state and event-evidence comparisons passed; full-round coverage, actionable
timing and punish analysis remain unverified.

## Saved File Names

Captures use `cfn-capture-<replay-ID>-YYYYMMDD-HHMMSS.json` with two-space
indentation. Repeated saves in the same second keep numbered suffixes. The reader
accepts both this format and legacy timestamp-only names, checks the embedded
replay identity, and sorts by timestamp then numeric suffix. No sample schema changes.

`migrate_capture_files.mjs DATA_DIR BACKUP_DIR [--apply]` previews by default.
It processes only root-level `cfn-*.json`, adds embedded IDs to capture/jump-trace
archives, preserves fixed protocol filenames, and formats without changing numeric
lexemes. Apply preflights all files, backs up originals and a hash manifest, verifies
every output, and restores originals on a caught write error. Run with the game closed.

The workbench candidate also exports `cfn-workbench-<replay-ID>.json`; the fixed
`cfn-workbench.json` remains its browser-link alias. That candidate is separate
from the narrow storage update (`runtime.lua`, `saved_capture.lua`).

## Current Candidate: Fact Timeline And Rule Workbench

Synced to the local game on 2026-09-21; this candidate still needs live validation.
The active profile path is `data/cfn-replay-rules.json`. At the stage checkpoint,
the user requested restoration of `profiles/system-default.json` (“系统默认规则”),
which retains system classifications and human confirmations. The separate
`profiles/precise-review.json` starter is preserved with no custom rules yet and
`include_system: false`. Only enabled matching custom rules enter issue lists and
priority counts; unmatched facts and historical manual notes remain stored.
All damage, guard and resource facts remain available. Older profiles without
this switch retain system suggestions. Facts are still extracted by the analyzers.

The offline editor now accepts saved scalar captures and `cfn-workbench.json`,
showing exact recorded round/frame values, gaps, resource facts, input waterfalls
with existing MOD icons, exported event evidence and condition traces. Modern
unverified input bits remain unnamed; manual icon labels never affect evidence.
The browser sends nothing to the game: folder-authorized config writes and result
reads are the only integration. Unsupported browsers retain file import/export.

The runtime can explicitly export evidence, update rules, or opt into paused-only
polling. `rule_evaluation` judges a fixed fact snapshot without sample traversal,
event extraction, playback or statistics reaccumulation. Facts remain in saved
captures; the derived in-memory snapshot is built once per load. The browser
acknowledges application only after reading a matching exported configuration.
See [workflow and limits](../../docs/research/CFN_REPLAY_WORKBENCH.md).

Two additional own Lua modules and three static files bring the closure to32 Lua
and58 payload files. No new external dependency, game hook or automatic agent
execution is introduced. Local game deployment is complete; live checks remain pending.

## Prior Rule Candidate: Offline Editor (Not Synced)

Open `rule_editor/index.html` directly; no server, network access or new dependency
is required. The Lua-generated catalog exposes294 typed evidence fields, bounded
all/any/not conditions, numeric field comparisons, ordered rules and four system
thresholds. Users and Codex share the validated `sf6cc.replay-rules.v1` JSON format.
Browser directory permission can save only `data/cfn-replay-rules.json`; export
is available when directory access is unsupported. Neither operation installs Lua.

Rules classify existing damage/guard events, preserve damage and navigation,
retain unknown evidence and cannot assign P0. Config is frozen per analysis;
re-reading a saved capture applies an edited profile without re-recording. Invalid
configuration visibly falls back to system rules. See the
[full contract and limits](../../docs/research/CFN_REPLAY_USER_RULES.md).

The candidate adds two own Lua modules and five static editor assets:30 Lua files,
53 payload files.19 CFN Lua test files,106 Node tests, four-capture default parity
and the standalone package dry-run gate pass. No game files or input were changed
for this candidate; installation and live validation remain pending.

## Prior UI Candidate: Own Shared UI Reuse (Synced, Awaiting Load)

`statistics_popups.lua` replaces the embedded statistics pages with independent
1P, 2P and comparison windows. Each has its own round/view state. Native charts
use fixed blue/orange player colors, shared scales, paired resource curves,
behavior bars/radar, damage histograms/boxplots and record-coverage reporting.
The bottom review window retains Problem/Guard and three explicit statistics
buttons. Opening a statistics window never starts capture or sends game input.

Reuse is limited to SF6CC's hook-free `autorun/func/UIKit.lua` and the existing
ImGui DrawList technique used by the training session recap. Do not import the
full recap module: it loads SharedHooks and training lifecycle state. The old
embedded renderer remains a test reference, not an entry dependency. Package and
deployment closure at that sync was28 Lua files including UIKit,46 payload files in total.

At the user's request, four Lua files were updated and two added on2026-09-20
at18:58 while the game remained open. All28 runtime Lua dependency hashes match
the workspace;58 other installed Lua files are unchanged. Previous files and the
manifest are backed up under ignored `audit-output/cfn-statistics-sync-20260920-185843`.
No live game input, Reset, DLL, helper source, saved capture or user config was
changed. File sync does not mean the running process loaded the candidate: stop
analysis/seeking and pause before a user Reset, or load at the next cold start.
Offline tests cover window independence,
four desktop sizes, chart geometry, gaps, unknown values, UI stack cleanup and
existing captured rows. Native window appearance and click seeking need live QA.

No external dependency was added. Existing .NET dependencies are still required
by the keyboard helper host, not the Lua statistics UI. The license inventory
does not mean this UI uses Hexa.NET.ImGui directly. Do not delete individual host
DLLs; a tester crash is not diagnosed without its actual failure evidence.

The sections below retain earlier implementation/deployment history.

## Current Follow-Up: Guard Ledger And Corrections (Synced, Awaiting Reset)

The problem table now has a sortable event-frame column. Synchronized but unlinked
advantage snapshots remain separate from guard-associated evidence and never drive
punish classification or seek targets. Cinematic counter-only contacts, held1HP
and delayed KO are grouped conservatively; HOLD/CATCH does not prove a throw.
Actual HP loss and native combo-damage readout are explicitly distinct.

The sixth view, Guard, consumes the same saved rows through `guard_review.lua` and
`guard_window.lua`. It lists ordinary guard intervals, optional synchronized native
advantage, bounded post-guard attack-state observations and existing recovery-cell
candidates. Continuous pressure may cover multiple contacts; this is not a per-hit
guarantee. Raw magnitude>=4 is only a sign-unattributed review lead, not a punish.
Neither guard rows nor opportunity filtering alter the damage ledger or grades.

Analysis completion/cancellation arms a bounded1x restoration job before ownership
release. Only the existing UI post-hook may change speed, for the same replay/build
and a safe current context. Result-window destruction defers it until replay resumes;
no retained native pointer, extra hook or OS key is involved. A single write requires
readback; expiry, foreign identity, reset and faults stop it. Failures are visible.

16 Lua test files,27 Lua parse checks,102 Node tests and standalone dependency gates
pass. Four local captures have identical Lua/JS damage groups and totals. Capture
122147 has28 guard intervals,25 associated readings and6 review leads; third-round2P
has5 damage groups totaling10000, including5187 actual damage at1391–2058.
After explicit user authorization, seven Lua files were updated and two added
while the game remained open. All27 plugin Lua hashes match;53 other Lua files
are unchanged. No DLL, helper source, capture or configuration was modified.
No input or Reset was sent; the user must stop analysis/seeking and pause before
Reset to load the files. Live behavior of these changes is not yet verified.
See [current review contract](../../docs/research/CFN_REPLAY_REVIEW_UI.md).

## Standalone Preview Package

`tools/package_release.bat -CFNReplayOnly` invokes the isolated preview packager;
`-DryRun` checks all dependencies and prints the plan without writing output.
This is not a versioned full-product release: no canonical product-version bump,
SF6CM manifest or stable-release overwrite. Default output is a new timestamped
directory below repository `release/`; existing output is refused.

The entry's literal Lua imports resolve32 files, including the explicitly allowed
own `func/UIKit` module. Eight offline editor assets are included under `CFNRuleEditor`;
personal rule configurations are excluded. Include the keyboard helper,
existing Chinese font and installed REFramework.NET runtime/dependency files,
but not dinput8.dll, generated game assemblies, remote WebAPI/MCP tools, captures,
local identity/confirmation records, key bindings or other mods. Source is the
current working tree, explicitly recorded in the per-file SHA256 manifest.
Do not claim an unmodified commit or generic no-DLL package.

Packaging requires the official .NET10 Windows x64 and VC++ x64 installers,
download provenance and upstream license texts in ignored
`audit-output/cfn-package-dependencies`. The .NET download must match its official
SHA512; both installers must have valid Microsoft signatures. The packager does
not download, install or run them. Testers install prerequisites manually only
when missing. The current development host uses a private DOTNET_ROOT, so copying
the plugin DLL alone is not enough for a clean tester machine.

The ZIP contains a plain-language installation guide,45 payload files and a
manifest, with all payload hashes checked from compressed entries after writing.
`tools/test_cfn_replay_package.ps1` checks dependency closure, forbidden content,
no-write dry run, missing prerequisites and conflicting product-release options.
System installers and release artifacts remain ignored; no game files are changed.

## Previous Deployment: Review And Statistics Preview

Five views share the existing recording: Problems, Overview, Behavior, Damage
and Resources. Statistics support whole-match/round and single-player filters.
Native charts include behavior radar, direction/distance histograms, damage
histogram/boxplot, ranked cause contributions and separate resource timelines
per round. Means, population SD, quartiles, P90 and normalized direction entropy
are observations of this recording, not skill ratings or causal proof.
Missing data stays unknown. Recorded introductory waiting is included in time
denominators; KO/timeout tails, gaps and round resets are handled explicitly.
Chart clicks reuse guarded same-round navigation and owned overlay restoration.
See [definitions and current limitations](../../docs/research/CFN_REPLAY_STATISTICS.md).

The candidate passes15 CFN Lua test files,25 Lua syntax checks,100 Node tests
and no-input C# helper compilation/recovery checks. Native geometry is tested
at three widths; actual game appearance and automatic mouse restoration still
require the next live test. Existing recordings can be read without recapture.

Cold deployment completed with the game absent before and after:25 Lua files,
helper source and font match source hashes. Seven existing files changed, five
were added (including local confirmed notes),242 were unchanged and none deleted.
No DLL, capture, training-library or intro-skip files changed. No live inputs,
game launch or Reset were performed; in-game smoke is still pending.

The bottom movable window is bounded to720px wide, with natural content height,
no collapse, pagination or internal scrollbars (not an unlimited-screen guarantee).
Its four columns are priority, description, damage and native advantage; all
filtered rows are rendered in full. Round, player and priority filters work
independently; native table sorting now sorts the data. A unique current login
short_id match chooses the local replay player, otherwise1P is the fallback.
Manual player selection persists across rounds. The current live account was
directly confirmed against2P before closing the game, not inferred by name.

Accepted window actions request one overlay-close tap through the keyboard
helper, using the saved REFramework menu key. Foreground, request identity,
expiry, held-key and cancellation guards remain. Already-hidden UI is not
toggled open; gameplay keys still wait for UI closure and key-up receipt.
After owned work ends, the helper restores the UI and mouse once, only if it
was hidden by that handoff and no keys are still awaiting release. Manually
reopened UI is not toggled closed. Reset clears ownership; failed restoration
does not retry blindly. The user accepted temporary hiding while seeking.
This updates helper source, not its DLL, and requires closed-game deployment.

The round selector has a Go To Round button with per-step native round checks;
frame navigation remains same-round. Native guard context is associated only
with continuous, display-synchronized and changed final readings nearby. Show
the raw signed value explicitly without pretending its sign belongs to the
selected player. Missing attribution stays unknown. Targets use the final-value
change frame, or the observed setup when unavailable, with no120-frame lead.
The real032052 capture still has112 losses/38 groups and9 native-context items;
the third-round1990 damage item targets1949. Lua and offline outputs agree.
Deployment now comprises25 Lua files, helper source and font, without replacing
DLLs, recordings, the training library or the intro-skip plugin.
See [current UI contract](../../docs/research/CFN_REPLAY_REVIEW_UI.md).

Review assessments are layered over unchanged damage groups. P0 requires an
identity/evidence-checked player confirmation. P1 prioritizes player-confirmed
ordinary issues and observed new counter/punish events for review, not certain
mistake verdicts; other observed contexts are P2, inferred/unknown causes P3.
The optional local `cfn-review-confirmations.json` also admits confirmed missed
opportunities with zero received damage. It is runtime user data, not packaged
or tracked. There is no general automatic missed-opportunity verdict yet.

## Previous Candidate: Floating Damage Review

The isolated replay experiment now has a movable bottom review window, round
selection (current round by default), paged damage-cause table, Analyze and Read
Previous Analysis actions, and same-round pre-event navigation. The classifier
processes saved samples incrementally with no new native hooks. It includes all
observed HP losses and retains native-counter grouping, fresh-flag and gap guards.
Offline and Lua rules are compared by tests; the actual032052 capture matches
112 losses and38 groups, including every category and group damage total.

Review targets lead the relevant setup by120 frames and clamp to the recorded
round range, without subtracting191 from the replay clock. Cross-round rows can
be read but cannot navigate. Native advantage attribution remains unverified,
so that column is blank rather than populated from stale/global values. Automatic
priorities are conservative P2/P3 process labels, not confirmed player mistakes.
P0/P1 confirmation, no-damage missed opportunities and replay-to-combo recording
are follow-up work. The native Replay Again window still requires user selection.

Deployment includes20 Lua files, the existing keyboard helper source and the
repository's Chinese font; no full ComboTrials installation or DLL replacement.
See [UI design and current limits](../../docs/research/CFN_REPLAY_REVIEW_UI.md).
Cold deployment is complete; live appearance and mouse/input handoff remain
unverified. Source/installed hashes match for all20 Lua files, the unchanged
keyboard helper and the font. Four existing files changed and five files were
added;240 other files, including captures, training-library files and DLLs,
are unchanged. No files were deleted, and no keys or Reset were sent. The game
was absent before and after deployment. First smoke: reopen the same replay,
pause, Read Previous Analysis, then test current-round pre-event navigation.

## Previous Candidate: Reload Saved Analysis After Restart

The restarted panel correctly showed idle: prior work preserved results across
native Replay Again but did not read them back after process/Lua restart. The
saved032052 file is intact. New explicit Read Previous Analysis is read-only:
select newest matching replay ID by timestamp/numeric suffix, validate schema,
columns, stopped status, row count and scalar clocks, then reuse match_review.
Files are considered one per frame and rows validated256 per frame. No replay
input, recording start, file writes or replacement of the manual capture session.
Cancelled/failed loading or switching replay preserves the previous result.
Invalid newest matching data is reported, not silently replaced by an older file.
No load during active analysis/navigation/manual capture. Stop reason is retained:
the032052 left_replay record is not promoted to complete playback.

355 Lua/Node checks pass. An additional real-file check restores8720 rows and the
round3/frame1984 candidate. Live07:17 navigation confirms keyboard controls now
work (round1,202->1984); that is not the round3 candidate verification. Lua-only
deployment needs saved_capture.lua, analysis.lua, review_panel.lua and entry,
then a paused Reset. Read Previous Analysis restores the list without recapture.
The standalone deployment manifest now includes the16th Lua dependency.

Deployed the four Lua files with matching hashes after MCP confirmed paused/no
round transition and the keyboard receipt was terminal.27 other modules,
recordings/helper files remained unchanged; request hash unchanged. No Reset
or game input was sent. Saved-result reload in the live panel awaits user Reset.

## Previous Candidate: Keyboard Worker File-Access Recovery

At04:55:48 the installed worker logged "Access to the path is denied" and
returned from Run. Its ready file stopped updating at04:55:46. At07:07/07:08,
navigation queued one key per attempt but received no matching receipt; actual
frame stayed208. This explains why both candidate and manual navigation failed.
The live process was still the same; disconnect/reentry is not established as
the cause of the file denial, and the exact denied file is unknown.

The worker now treats UnauthorizedAccessException, IOException and partial JSON
as recoverable file iterations, with10..250ms bounded backoff. It does not retry
consumed input: LastId is recorded before injection, and500ms expiry still rejects
old queued commands. Other exceptions remain fatal. No filesystem permission or
security settings are changed. Its2-second readiness message includes an epoch
timestamp; Lua requires freshness within6 seconds for sending or awaiting a new
receipt. A matching completed receipt remains valid independently. Old helpers
without timestamp require updating and restarting; Lua Reset cannot revive a
terminated C# worker. The candidate panel also shows navigation failure reasons.

346 Lua/Node checks pass, plus C# compilation/INPUT layout,10 validation cases,
13 duration cases, recoverable/fatal errors, consumed-input non-retry and stale
request expiry. Tests never call SendInput. Cold deployment updates only the
helper source, keyboard.lua, review_panel.lua and experimental entry; no DLL,
navigation algorithm, recordings or prior saved analysis change. Live recovery
from a real file denial remains to be verified. Restart then try one-frame
forward and same-round1984 navigation; a full recapture is not needed for this.

Cold deployment completed: four source/installed hashes match;28 other modules,
recordings and DLLs are unchanged. SF6 was absent before and after copying.
No old requests/receipts were edited and no key or Reset was sent. The new
worker token rejects previous-process requests; timestamped readiness and live
navigation must be checked after the user's next launch.

## Previous Candidate: End Polling Without UI Updates

Live032052 saved8720 rows across all3 rounds but stopped with left_replay;
analysis reported position_unavailable. Offline scan: rounds0/1/2 reach
KO3412/2292/2095, no in-round gaps,4 transitional rows excluded. One candidate:
round2 frame1984, defender2, at least6 fresh cells, distance142.707; reach and
actionability remain unverified. Original file and stop reason are not edited.

A new regression fails when the final UI stops calling update even though its
end flags are readable. This proves a code-path gap, not the exact live callback
sequence. The existing on-frame clock reader now reacquires GuiManager ->
get_Esports -> GetReplayUICtrl only for an owned active capture with a witness
and absent live context, outside battle/UI updates. It shares the same strict
end checker as the native callback. No new hooks, game-object retention, input,
timeout increase or inferred completion from KO. A compact end_check field in
the existing phase log distinguishes remaining window/identity failures.

342 checks pass, including real runtime/controls/analysis integration without
a final UI callback and negative polling guards. Native full-match end recognition
remains pending live verification. Previous saved results remain usable; avoid
Reset until the current candidate has been inspected, since Reset clears memory.

Deployed controls/analysis/entry with matching SHA256. Read-only MCP confirmed
paused/no round transition; terminal keyboard request hash stayed unchanged.
26 other modules/captures were unchanged. No Reset or game input was sent.

## Previous Candidate: Preserve Results Across Replay Restart

The 03:08 live attempt stopped during `first_round / position_unavailable`,
after one acknowledged previous-round key. Capture never started and no new
recording was saved; the older 025555 first-round recording remains on disk.
Starting that attempt also cleared the prior in-memory result too early.

Read-only MCP at the user's final window confirmed `_ReplayEnd=true`,
`get_IsResultMenuOpened=true`, and BattleReplay `get_Replay=false`, round=-1.
The manager still resolved the selected replay and core. An earlier UI read
reported result=false, so the generic result getter alone is not sufficient
evidence of the final window. Live-context-only code cannot detect this ending.

The fix keeps a bounded, already-sent analysis previous-round request alive
through missing context, with no repeated key and no cached game objects.
The response must retain replay/core identity and acknowledge the expected round.
Preparation failure retains the previous capture, result list and save status,
labelled as previous results; a successfully armed new capture replaces them.

End detection runs before live-context gating in the existing UI callback. It
requires both native end flags, the same UI address previously observed during
this capture, and freshly resolved selected replay/core identity. An owned
whole-match capture may wait at most120 render ticks for the end notification
after context loss; no synthetic samples or inputs are produced. Timeout is a
partial capture, and an earlier capture failure cannot become successful end.

Workflow: let the match finish naturally; save and analyze; the user selects
Replay Again and pauses. The saved capture/results remain in memory across that
native restart, with no new recording. Candidate navigation checks replay ID
and current round, not the former scene core. Other-round candidates still
require selecting that round first. No automatic dialog click or attempt to
prevent the final window is introduced. Lua Reset is different: it destroys
in-memory results; saved JSON remains, but reload-from-file is not implemented.

340 offline checks pass (27 analysis,10 candidate,75 capture,79 controls,
23 keyboard,10 match review,41 navigation,7 speed,14 UI,54 Node), including
real runtime+controls+analysis end-window/restart integration. All experimental
Lua files pass syntax checking. This is not a completed live whole-match test.
Only sampler/runtime/controls/analysis/review_panel Lua changes are needed;
no DLL, keyboard helper, input mapping, production plugin or recording edits.

Deployment completed for these five Lua files with source/installed SHA256
equality. Read-only MCP confirmed the final window remained open. The last
keyboard request already had its matching sent receipt and its hash did not
change during copying;23 other module/entry/capture files were unchanged.
No Reset, replay confirmation or game input was sent by the agent. Next live
check: Replay Again, native pause, Reset, then one whole-match analysis; after
save, Replay Again without Reset must retain the result list.

## Previous Candidate: Whole-Match Analysis

At user request, analysis now plays the entire replay rather than stopping at
each knockout. Start paused in the replay (not its end dialog), click Analyze
Entire Match, and close the overlay. Verified previous-round keyboard controls
return to round0 before the existing large/single lower-bound probe. No capture
starts until that preparation and8x selection succeed. Actual round count comes
from replay metadata, not a constant3. The existing1/45ms navigator is unchanged.

Capture runs unscoped across rounds, bounded to120000 samples. The existing
ReplayUICtrl.update observer now exposes get_IsResultMenuOpened separately from
other modals; a matching analysis-owned capture stops as soon as that signal is
observed. On-frame analysis saves the raw capture and scans each round separately.
No pause, resume, speed restore, dialog confirmation or next-round key is sent at
match end. In particular a failed end-of-round key can no longer leave this flow
waiting for a pause. The actual final-dialog signal still needs a live full run.

New pure match_review.lua owns partitioning/coverage, reusing candidates.lua
without changing4/5-frame rules or character semantics. Transitional mismatched
round clocks stay in the raw file but cannot bridge candidate windows. Each round's
candidate scan ends at its observed KO/time-up; post-KO frozen data cannot create
false windows. Results show round and frame, and navigation remains same-round:
close the native end dialog, return to the desired round and pause before locating.

Coverage checks include metadata round count, contiguous observed round numbers,
in-round clock gaps and observed ends. Missing rounds/end evidence, conflicting
samples, rewinds or early termination never become complete evidence just because
a result window appeared. Earliest actionable frame remains unverified, so
full_replay_verified stays false even when basic coverage passes. Aborts preserve
partial capture (including overlay reopen, midmatch pause, unrelated modal, exit,
identity change, capacity/read failure). No background key retries.

326 offline checks pass:23 analysis,10 candidate,71 capture,73 controls,23 keyboard,
10 match review,41 navigation,7 speed,14 UI,54 Node. Tests cover2/3/5 rounds,
starting from round3, stale/foreign result flags, early pauses, capture limits,
mixed-round rows, missing rounds, backwards playback and per-round results.
Existing025555/222852 raw captures also scan offline without merging rounds;
neither is mislabelled a complete match. Await live Reset validation.
No helper/DLL, production plugin, input mapping or saved recording changes.

Six Lua files are deployed and hash-verified (runtime, controls, analysis,
review_panel, match_review, entry). Read-only MCP confirmed paused/no transition;
the terminal keyboard request/receipt remained unchanged throughout copying.
23 other module/capture/helper files were hash-verified unchanged. No Reset or
game input was sent by the agent. Full-match real-game validation remains pending.

## Previous Candidate: Speed Field Readback Fix

The 02:44:49 live run stopped at `set_speed / speed_unavailable`, before any
resume or capture. The stale preceding back-key result hid that reason as
`not_confirmed`. Waiting longer could not start playback.

Read-only MCP located the UI through GuiManager -> get_Esports -> GetReplayUICtrl.
Its eight SpeedData entries returned 0.5 from GetSpeedValue, while the array's
stored (Type, Speed) pairs were (1,0), (1,3), (0,5), (1,6), (1,7), (0,11),
(0,12), (0,13). The current and previous indices were both7. The named ESpeed
schema includes Speed_8_0; CanChangedSpeed(7) returned false and (6) true.
No speed mutation or keyboard input was sent during this inspection.

The adapter now reads each entry's Speed field and resolves named ESpeed constants
through the current SDK, sharing this decoder for target selection and current
speed. No hardcoded enum ordinals, array indices, raw offsets or GetSpeedValue
calls remain in this path. An already-selected target is a no-op; changed targets
still require CanChangedSpeed and the existing verified-readback gate. Missing,
ambiguous and refused targets have distinct reasons, preserved by analysis.

Regression tests reproduced both failures before the fix. 303 checks now pass
(14 analysis,10 candidate,70 capture,71 control,23 keyboard,41 navigation,7 speed,
13 UI,54 Node). Controls/analysis integration now uses the broken 0.5 getter with
separate enum fields, and enum test IDs intentionally differ from game ordinals.
This is offline evidence; corrected Lua field decoding and automatic full-round
playback still need live Reset validation. Navigation stays fixed at1/45ms;
helper/DLL, candidate classification and capture boundaries are unchanged.

Deployment completed: replay_speed.lua, controls.lua, analysis.lua and entry
match workspace hashes. The last acknowledged keyboard request remained unchanged
throughout copying;23 other capture/module/helper files were verified unchanged.
No Reset or input was sent. Await paused-user Reset and one analysis attempt.

## Previous Candidate: Direct Replay Speed And Fixed Navigation

The previous candidate was deployed and Reset, but failed before playback as
described above. Its original deployment notes follow. User reports analysis rewinds but does not start
playback. The last keyboard receipt was W/sent; opening the overlay replaces the
active stage with cancellation. This does not establish the original stall cause.
The initial hypothesis of0.1 increments throughout was explicitly rejected by
the user (reported discrete1/1.1/1.2/1.5/2/4/8). The local192-key budget change
was withdrawn before deployment; it is NOT the fix.

At user request analysis now uses native ChangeSpeed directly, not repeated speed
hotkeys. Read-only MCP verified ReplayUICtrl.ChangeSpeed(Int32,Boolean),
CanChangedSpeed(Int32), SpeedData.GetSpeedValue and the native speed array. The
installed generated application assembly metadata names the parameters speedIndex
and isOverwritePrev. replay_speed.lua finds a unique target value in that array,
checks CanChangedSpeed, then invokes ChangeSpeed(index,true) once to remember the
choice for resume. It never writes _CurretSpeed or assumes an index equals8.
The previous speed is independently retained and restored by the same adapter.

This is a deliberate narrow exception to the earlier keyboard-only policy,
authorized by the user's direct-speed request. Dispatch is in the existing UI
update post-hook with freshly acquired UI/core, paused same-replay/round/frame,
no open battle update/modal/takeover, no active capture and closed overlay.
No managed instance survives the callback, no new hook and no on-frame native
write. Native readback at the target across a three-render gate is required before
resume; missing target, native refusal, context change or timeout stops without
retry or silently falling back to W. Method names/parameters verified, but live
thread safety, semantic effect and full playback flow still require validation.
The native call must not be described as already proven to fix the original stall.

Analysis stage request/result/stop logs now identify the last stage. UI preserves
the stopped stage and shows actual/target speed. The old capture-speed dropdown
is explicitly labeled as a manual recording tag, not a speed control.

User chose fastest-candidate confirmation1 +45ms holds as the fixed navigation
configuration. Removed both experimental selectors and recent comparison history
from the UI; target/current frame, cancel, elapsed time and key count remain.
Backend diagnostic logs/history remain. This selection is user-validated, not a
proof of a universally fastest setting; short-duration trials are no longer UI
options. Manual frame controls keep their existing confirmation behavior.

299 checks pass:71 control,41 navigation,13 UI,23 keyboard,70 capture,10
candidates,13 analysis,4 native-speed,54 Node. Existing3 UI tests now assert the
requested fixed-profile/removal contract; the newly written erroneous70-key
scenario was replaced before deployment. Actual-controls/analysis integration
reaches resume after a single native speed call; no speed hotkeys are sent.

Deployment: initial closed-process guard rejected before copying anything.
User had confirmed analysis stopped and accepts Lua-only Reset; a second scoped
deployment verified the latest key request older than10s, matching its receipt
and unchanged throughout copying. Five Lua files match workspace SHA256;87 other
plugin/binding/capture files unchanged. No helper/DLL, game input or Reset was
performed. This verifies installation, not native speed behavior. Installed hashes:
- replay_speed: `CD710B111A7A6853782ABEAEFFBABE1BB9A0BB54585E2AEF458BFC06B1C071CD`
- controls: `360522C5C46A316999858EC9A7CB9D105FFEA906831E499CBB5CAEF21874AAE5`
- analysis: `58F4500E448A69DC35EB74F36DB618C3BCF94A129BAFA544BA0660FEA75D28D9`
- review_panel: `5CC07C3DAB4FC6540E9ECE4A67B54830F2ABEC1A1212DBACE7BEB486DCBD2007`
- entry: `5EBB78EA75EFBDE2F39C4F1BE93B4E960B1322DAFB5484E67DB476C58AA6B98D`

## Previous Candidate: Single-Round Analysis (2026-09-20)

Cold-deployed, live validation pending. The new analysis button owns the existing keyboard
controller, rewinds within the current round, confirms actual8x speed, arms the
capture before resuming, then stops sampling at either HP<=0 or timer seconds
AND subsecond counter zero. A next-round sample is rejected before insertion,
including during eight native updates between rendered callbacks. Playback pause
is a separate best-effort OS hotkey after sampling has stopped; no native control
methods are called and there is no claim of zero-latency playback interruption.
When still in the same replay/round, the workflow attempts to pause and restore
the prior speed. On a round change it sends no more keys; reopening the overlay,
manual interruption, stale state or failed input stops the workflow without retry.

There is no verified native round-start accessor. One acknowledged stationary
large-back, followed by one acknowledged stationary single-back, probes a lower
limit. This is NOT proof of a complete round: a missed keyboard sample can look
stationary. Start remains unverified and the UI displays actual recorded range.
This bounded probe never retries an unconfirmed key; it uses baseline45ms holds.
Any incomplete capture remains explicitly partial, with raw rows preserved.

Modules: analysis.lua orchestrates; session.lua enforces scope/finish per native
update; candidates.lua scans plain captured rows; review_panel.lua renders the
list. The entry only assembles them. controls.lua grants the analysis owner a
separate limited whitelist (back, rewind, speed, resume, pause); existing manual
and navigation restrictions remain. The owner may arm capture and issue only
resume/pause while that capture is active. Reset disables callbacks, not restart
or disk export. No DLL/helper, new native hook, character Action-ID resolver or
production module change. Candidate analysis runs in256-row chunks outside hooks.

Rules are conservative review heuristics scoped to build20004000, not guaranteed
punish judgments. A fully observed ordinary ground guard interval must end1->0
in a supported ground state, with unchanged HP and no hitstop. Then count only
consecutive fresh opponent ENDSTUN8 cells at aligned clocks, valid80-cell cursor,
unchanged meter epoch, clear exclusion flags and the same action sequence.
Missing/gapped/stale evidence, new reaction or sequence change stops the count.
Exactly4 with an observed nonblue end is a four-frame boundary candidate;
5+ is a suspected four-frame-punish opportunity (incomplete end stays lower-bound).
4 truncated cells never become an exact-four label. Duplicates with conflicting
evidence and rewinds invalidate the report. No range, earliest-action, attack
ownership, invulnerability, cancelability or missed-punish claim is made.
An entry locates to the observed guard-exit frame only in the same replay/round.

Raw records auto-save through the existing unique capture exporter. Existing
unsaved stopped records must save successfully before replacement; active manual
capture is not replaced. Results remain in memory until Reset; raw data is kept.
Prior213710 and222852 captures scanned through first KO:3221 unique rows each,
zero gaps and zero>=4 candidates, consistent with earlier1-3 fresh-blue findings.
This is not proof there are no punish opportunities. Live automated analysis and
the two classification boundaries remain to be checked in game.

285 relevant checks pass:65 control,41 navigation,12 UI,23 keyboard,70 capture,
10 candidate/round-scope,10 analysis orchestration and54 Node.27 checks added
relative to258; none retired. All experiment Lua files parse. Deployment checked
game absent before/after,8 Lua files match workspace and225 other plugin/data
files remain unchanged. No game input or Reset performed. Installed SHA256:
- session: `873CCF475F234F39805D5DA36C11575D8DBAE3FF1C3E547B9623545F858B2BA9`
- runtime: `8EC6C37899E6D1E0770F7134934FA1FF76F18172E21E07E0F40538C694CF2C57`
- controls: `A65B38D1B70B7EC3938412EE49BF598B650381170A4EE163C0BB7F6FE8F6B1B1`
- keybindings: `BE158BA65B0E93E229B42918B7A353B8C7C3F5284FA2ACC3FD496413309AE62E`
- candidates: `971826D6E13308D0D35068D698BFE47DB14ECACAC5C005E12414C2D576454582`
- analysis: `45108754B81C1799F2138A48163EB0EFA3537EFCBDFC430BC8B7BE892FE6BA5B`
- review_panel: `34F7E3FB3AAB9800D952DA9671B9A13D6F65669C710F2BDBB6CFC482C18B9EBE`
- entry: `645759EBFE0234F42DC20A315AD8DF231530B1A86A24BAFAED86BAD2579FB818`

## Previous Control Candidate: Same-Round Positioning (2026-09-20)

Current candidate: bounded key-hold comparison (cold-deployed). User reports
one faster and two fastest-candidate runs accurate. Logs confirm stable2:
2468->238,1.584s/14 presses; stable1:238->2238,2.134s/16 presses and
2238->1238,2.471s/20 presses. Different endpoints are not a speed comparison.
Dispatch-to-key-up receipt consumed56/52/73 render ticks versus7/7/18 for
confirmation; receipt includes transport and sampling, not just key-hold time.

An independent navigation-only hold selector adds45/30/20/12ms; default45,
manual controls45, helper poll10ms unchanged. The duration is frozen per run.
Missing duration keeps old Lua compatible at45; non45 requires advertised helper
support and a matching receipt. Invalid durations send no key. Actual hold time
is measured by Stopwatch and logged with confirmed-command sample counts.
No batching or retries: a missed short press stops the run. All existing focus,
pause, same-round, key-up acknowledgement and final-target checks remain.

258 checks pass (62 control,41 navigation,11 UI,23 keyboard,67 capture,54 Node),
plus actual-dependency C# compilation, INPUT ABI,10 safety cases and13 duration
parsing cases without starting the worker or sending keys. Experiment Lua parses.
This update includes helper source, so deploy with the game closed and restart
normally. Compare the same round/endpoints at fastest-candidate confirmation,
first30ms, then20ms, then12ms only after repeated accurate runs. Stop at the
first failure.12ms may miss a60Hz input sample; no fastest reliable boundary is
claimed and shorter configured duration is not proof of faster execution.

Deployment: game absent before/after copy; only entry, controls, navigation,
keyboard and helper source updated. All five SHA256 values match workspace;
225 other autorun/plugins/data files unchanged. No DLL change, Reset or key input.
Live duration comparison remains pending. Installed SHA256:
- entry: `1A50B42D4FD74DD979CCFB53EEAB60301A13E06748C5FAAEDA637BF64F0C1E89`
- controls: `4FA4D2A4E3249AFA65B803AFCE9ABE43B7B3737CB5872D153B2857E91C676847`
- navigation: `A0D12BA0EF781FB395870A45A74DA7B82983E67950243666767A39401CDDF9D6`
- keyboard: `356585AA24722AD1EAF1AA109B7C70110A04784AA705C114225060BD933E82C1`
- helper: `CD359C9BEBF64AF17F624E190D80A3C92E8BEE0C0580656F1D8A9773E1007817`

### Earlier Deployment History

The following pending/live statements describe their own earlier stage only.

Speed-comparison deployment completed after user confirmation that navigation
was stopped. The first attempt was blocked by the recent-input guard before any
copy. On retry the old request timestamp was unchanged and older than10 seconds;
only controls.lua, navigation.lua and the entry were copied and hash-verified,
with73 other plugin/binding files unchanged. No Reset or game input was performed.
The user can Reset while replay remains paused. The3/2/1 comparison and fastest
boundary remain pending live results; the default remains3.
SHA256: controls=`1F07F31095FE30082970324DAE251959CE1B9C13E701276E6460F734C1989706`,
navigation=`565A2454127F09EB0F4DE21D2786CA86B384CA01B7FBCB62DAF21C3620F9820D`,
entry=`BBDE02BE4410876B8934EFA594D5EEF3C054993376DE10ED1A1F67B5F5E9A999`.

Latest live feedback confirms the speed-corrected version is accurate and faster.
The user now requests the fastest reliable boundary. A Lua-only comparison
candidate adds run-scoped confirmation thresholds3/2/1 (verified baseline / faster
experiment / fastest candidate), defaulting to3. Manual buttons stay at3. No
zero-read mode, batching, retry or changes to the45ms/10ms keyboard helper.
The faster modes retain an extra three-render final-target check and stop on
drift. Profile is frozen at run start; changing the dropdown affects future runs.

Each run reports elapsed seconds excluding overlay wait, key count and status;
the last12 completed/stopped runs remain in memory until Reset. One compact
`[CFN navigation]` log line records start/target/actual, profile, duration, render
ticks and confirmed-action prepare/release/confirmation tick totals. Release
means dispatch-to-observed-key-up receipt, not pure OS key-hold time. Tick totals
exclude incomplete commands and final settle/loop overhead. Windows Lua os.clock
is used for elapsed comparison (local500ms sleep sanity check advanced0.733s
including process-launch overhead); elapsed timing on the embedded runtime is
not independently calibrated. Absolute timings are comparative evidence, not a
guaranteed frame rate or theoretical hardware limit.

250 relevant checks pass:60 control,40 navigation,10 UI,19 keyboard,67 capture,
54 Node. Twelve cases were added for thresholds, acknowledgement, same-render
callbacks, final drift, timing, bounded history and UI; none retired. Modified
Lua parses. Candidate requires real comparison on the same replay round, speed
and endpoints; fastest boundary is NOT established. First compare baseline and
one-read candidate on500 ->1000 ->500, then use the middle profile if the fastest
fails. Repeated accurate arrivals are required before promoting a candidate.
If profiles are equally fast, inspect release-vs-confirmation data before
changing the helper. No automatic live benchmark or game control was performed.

Speed correction is now copied to the game directory, superseding the pending
status below. User explicitly chose Lua Reset instead of a game restart for this
update. Last keyboard request was96 seconds old at copy; only controls.lua,
navigation.lua and the entry changed, with73 other plugin/binding files unchanged.
No Reset or input was performed by the assistant. Pause the replay and stop
navigation before Reset; live speed/accuracy and this reload path remain unverified.
This scoped choice does not validate arbitrary hook/helper/DLL hot reloads.
Hashes: controls=`B7E6CB7E380D1A8C1710C59094BAB53D62438CE51D5468CE0FAFD486E9A1D376`,
navigation=`6192B78A93832AAE6274B94866772BDCA8D55C493711B54D07630BBC34A833F2`,
entry=`499B2B428BB36FD9A7D0F92E41FB589BE420CE4120DEE8FC24926ED9136A6050`.

Latest user validation: subsequent forward and backward positioning are accurate;
the initial screenshot showed cancellation at909 with target1000, not completion.
Opening REFramework during a run cancels it. The last E request had a sent receipt;
its displayed zero delta does not establish that all medium actions fail. The
opening clock191 remains an absolute frame, with no191 offset or universal floor.

Prepared speed correction (NOT deployed): remove the fixed12-render wait, retain
the helper's post-key-up acknowledgement and three stable transitions across
distinct render ticks. Multiple native UI callbacks within one render cannot
fake stability. The helper's45ms press and10ms poll are unchanged. The planner
may select a nearer landing past the target and then reduce step size, instead
of using a long medium-only tail. With simulated299/8/1 steps,191 ->1000 takes14
inputs rather than31 (2 large +26 medium +3 single). This is not measured live
latency. Exact final clock, same-round checks, one request at a time, cancellation
and all failure limits remain. No burst or retry of an unconfirmed key.

Completion is evaluated before idle overlay cancellation, so opening the panel
after an already confirmed final result cannot relabel success as cancellation.
The entry no longer cancels independently before navigation can inspect that
result. An unfinished run still cancels on reopening; UI states the reason and
remaining distance.238 offline checks pass (55 control,35 navigation,19 keyboard,
67 capture,8 UI,54 Node);3 control and3 navigation cases added, none retired.
Only controls.lua, navigation.lua and the entry need cold deployment.

Input correction is now cold-deployed, superseding the pending status below:
after user confirmation and two closed-process checks, only CFN_ReplayCapture.lua
was copied. Installed SHA256 matches
`917336A4B16FA30BAB1F93E96EAEEE1F580E6E85D1BB50C85D0E4E067E75FE21`;
229 other plugin/data files were unchanged. Live UI and positioning validation
remain pending; start normally, do not Reset.

Latest live UI failure: screenshot reports two Missing TreePop warnings. The
entry called imgui.input_int, which is not exported by the installed framework
revision0a07faae (checked upstream src/mods/bindings/ImGui.cpp). The original UI
test incorrectly supplied that API. Removing it reproduces the entry exception
at line122 before either enclosing tree is popped. The log did not contain the
Lua exception, so this diagnosis combines source compatibility and reproduction.
Prepared correction uses the existing input_text API with a persistent string
and parses nonnegative decimal integers only on confirmation; invalid/empty text
cannot reuse an old target. Tests now track balanced tree depth and pass without
input_int.8 UI tests pass (2 added);52 control,32 navigation,19 keyboard and67
capture checks also pass. Entry syntax passes. Only the entry needs cold-copy;
game was running at the check, so this correction is NOT deployed yet. No changes
to navigation, bindings, control timing or keyboard helper for this correction.

Same-round target positioning is now implemented as an isolated navigation
module. It uses the existing keyboard transport, not native seek/control calls.
There are medium-forward/backward buttons as well as large jumps and single
frames. Medium shortcuts resolve FAST_FORWARD/REWIND from the game's shortcut
dictionary and current keyboard settings; Q/E are not hardcoded. Enum names
were checked through read-only MCP; actual medium input still needs live testing.

Pause using the game first, enter a target frame in the current round, click
the positioning button and close REFramework. Opening REFramework again cancels
the sequence; the cancel button also cancels before starting. The run never
requests previous/next round. Choose another round manually before starting
another positioning run. Targets beyond the native accessible range stop on
unconfirmed movement, rather than silently switching rounds or declaring success.

Large/medium distances start with estimates300/8, used only to select a key.
Each action waits for acknowledgement and confirmed observed movement, and the
next decision uses the fresh independent clock. Estimates adapt to observed
distance; overshooting permanently reduces the largest permitted step for that
run. Single frames finish exactly. No calibration sequence, assumed landing,
direct native seek, repeated unconfirmed input or additional refresh hook.

Sequence ownership blocks unrelated control and recording requests. Expected
replay/core/round/frame are checked again before each send. Request IDs bind
results to actions. Missing/stale clock, changing replay/round, resumed playback,
menus, transport failure or lost focus stop the run. It is bounded to512 inputs,
600 render ticks waiting for overlay closure and18000 ticks executing. OS-accepted
input cannot be retracted; existing helper cancellation remains best effort.
Owner lifetime keeps control-only reads awake, without renewing the full-player
preview. UI pause-state age remains independent from clock freshness.

Offline:230 checks pass (52 control including real-module navigation integration,
32 navigation including multiple start/target pairs,19 keyboard,67 capture,
6 entry/UI,54 Node analysis). All experimental Lua files parse. Existing24 draft
navigation scenarios were adapted for three sizes and the independent clock;
8 navigation,10 control,1 binding and6 UI checks were added, none retired.
Cold deployment/live verification status is recorded below. Standard product
packaging is unchanged; this remains an explicit experiment.

Cold deployment completed after the user closed SF6: only controls.lua,
keybindings.lua, navigation.lua and CFN_ReplayCapture.lua were copied and
SHA256-verified.227 other plugin/data files were unchanged. The keyboard helper,
DLLs, stored captures and settings were not modified. Game remained closed;
medium actions and automatic positioning await live validation. Do not Reset.

Deployment SHA256:
- controls.lua: `56F9E6853DAC86172EC9EAFB47EFFD0B6225954E89DCBCCB3CC7CA6F1F604CE4`
- keybindings.lua: `6232CC735134284DB6EAC140D2AC8606F8B5D8C1C7743F6C6AC92191DE97A4A5`
- navigation.lua: `C782CC4A057EA9289A23CC08914C6C36887AF93284E206AE76ED5C834DAA8F37`
- CFN_ReplayCapture.lua: `D364BD525813848EC23D9B39A690DF68413F835DD28C21130EB6A3ED9FDFB6C2`

## Keyboard Validation History (2026-09-20)

The following records describe earlier stages, not the current availability of
target positioning above.

Live feedback after the read-only correction: the user performed two forward
jumps and reported both normal. The supplied screenshot shows confirmed game
response, paused at speed0.5, round1/frame789, last action round1/frame490 ->789,
delta+299, key C resolved from game settings. This validates the reported two
forward operations and the displayed second result, not a universal299-frame
stride, backward controls or precise target navigation. No further runtime
changes or deployment were made for this feedback.

Latest screenshot resolves the two visible clocks: old player snapshot790 is
explicitly stale, while control position1089 matches MCP. Last action still
shows492 ->492 (F, unconfirmed), so stale UI observations must not overwrite a
newer observed action result. A read-only correction is now cold-deployed:
controls polls only replay round/time from the existing on_frame callback while
preview/request is active, reacquiring context and requiring no open battle/UI
callback. It copies plain values, retains no scene objects, does not sample
players and does not refresh the game or send another key. The new clock never
refreshes the age of the separate pause/modal snapshot or alone confirms success.
Timeout preserves recent clock evidence instead of reverting to the old UI frame.
Player clocks are labelled "读取时"; the control panel distinguishes a fresh
position from a last-read position.181 relevant tests pass (42 control,67 capture,
18 keyboard,54 Node), including7 new control and1 display tests; none retired.
Only controls.lua, presentation.lua and the entry were copied after checking
SF6 was closed. All three installed hashes match the workspace;72 other plugin
and settings files were unchanged. The helper and keyboard bindings were not
modified. No Reset is needed; start the game normally for live validation.
Automatic navigation remains unwired; its draft ownership changes were removed
from this candidate. Two forward jumps now have the live confirmation above;
broader paused-clock behavior and target navigation remain unverified.

Deployment SHA256 (2026-09-20):
- controls.lua: `2D603A5716621E21BBA8844856187F93306B16110A9F4088EC5BD87C4AD8E1A4`
- presentation.lua: `DD2BE7E364B51FCFA98F69F52BFF0E44A92EAC68D0C2E3201D8CC7FF7715CE34`
- CFN_ReplayCapture.lua: `2C04E2FFF19BBDB4E9CF30CB740733EC96126573056E3C6EC9E24B538FF85CF2`

Native-C comparison now read790 ->1089, same round0, SeekWait=false. A second
read without further input remained1089. Manager RollbackFrame=1089,
RollforwardFrame=300, RewindFrame=1. This establishes299 observed clock steps for
this one native input, not a universal stride or correct panel refresh timing.
The user has been asked to reopen the panel without another key and report its
current frame, to compare against1089. No new probe or deployment.

Latest feedback blocks target-frame navigation: user observed191 ->192 ->491
after two coarse forward clicks, then790 after one single-frame forward click,
while the picture had already jumped twice. The corrected arithmetic is
(790 -1 -191)/2 =299, but this does not establish native stride because the
clock-to-operation correspondence is unresolved. A read-only MCP check also
returned ReplayTime790/Round0, RollbackFrame789, RollforwardFrame300 and
RewindFrame1. The latter fields are not independently proven displayed clocks.
PauseTime/PauseRound=-1, SeekWait=false and native Paused=false were observed;
do not substitute these for the previously verified UI pause flag.
A single native-C comparison is requested; no new probe or game write is used.
The navigation.lua draft and24 offline tests exist only in the workspace;
its required control ownership support is not in the current candidate. Neither entry nor deployment includes
navigation. All35 existing control tests still pass. Do not deploy the draft
until the clock discrepancy is resolved; confirmed input is not precise seeking.

First live failure is localized to key lookup: helper startup passed, but no
request was written and the UI reported an unknown key. `GetConfigParam`'s
two-parameter prototype was missing the comma-space required by the framework's
exact signature matching. The test fixture repeated that mistake. It now uses
the live TDB signature, reproduced failure before the one-line fix, then passed
all18 keyboard and35 control tests. After the user closed SF6, only the one-line
keybindings.lua correction was deployed and hash-verified;73 other plugin files
and the saved manual bindings were unchanged. Lua syntax also passed.
Live read-only configuration is C/67, no second key or modifier, device0.
Manual C override has produced a matching `sent` acknowledgement in the current
process. The user then confirmed both lowercase c and uppercase C successfully
jump forward and update the picture after closing the overlay. This validates
the manual-forward path. After the one-line fix was deployed, the user also
reported success for the cold-start test with the forward override cleared.
Automatic lookup plus forward input is now user-verified for this configuration;
other actions, changed key assignments and exact step sizes are not yet verified.
Do not Reset the running scripts.

The user requested actual game keyboard input, replacing direct replay-control
method calls. The preceding measurement exercise was not performed. Reported
old behavior was1813 ->1814 on the first click, then2113 on the next, with a
potentially stale picture. No new scene-refresh investigation is authorized.

The controls hook now only reads state and resolves the current shortcut's
InputId through InputManager's keyboard configuration. The ordinary render
callback hands a single request to `CFNKeyboardBridge.cs`, a source plugin for
the already installed REFramework.NET. The helper sends a45ms Windows scan-code
key press. It never calls game methods or accesses game objects. No DLL changes.
Auto key lookup has passed the user's forward-action test with the current binding.
Ambiguous/chord/missing bindings refuse execution; per-action single-key manual
overrides are available, with no silent C/Z/R defaults.

Use the native pause key first (R unless remapped). Click one control, then close
the REFramework overlay with its usual toggle. The game must stay foreground;
the helper refuses input while the overlay is visible, a modifier/requested key
is held, or the request is stale. Open the panel again to inspect the actual
before/after round and frame. It does not close the overlay automatically.
If automatic lookup fails, fill in that action's actual keyboard key in the
key settings and retry. Letters, digits, F1-F24 and named navigation keys are
supported; modifier chords and mouse bindings are not.

Requests wait at most600 render ticks for overlay closure; dispatched requests
are observed for180 ticks. There is one key press, no automatic retry. A helper
acknowledgement means input was sent, not that the game acted. Confirmation also
requires observed clock/state change. Large jumps require more than one frame
in the requested direction, with a stable clock, not a hardcoded300-frame delta.
The panel reports actual delta; this does not validate rendered-world freshness
or establish an absolute seek target. Direct seek remains absent.

Reset/scene changes cancel pending tickets. Helper tokens, unique IDs, a500ms
request lifetime, foreground checks and a cancellation file bound stale work.
Cancellation cannot retract a key already accepted by Windows; the short OS
handoff is not an atomic transaction with the game scene. Key-up is always
attempted even on helper unload. This build requires a cold start, not Reset.
Runtime handoff/override JSON files are ignored and are not release assets.

Offline gates:35 controls +18 keyboard/position +66 capture/UI +54 Node =173
tests, plus C# compilation against the installed API, x64 INPUT ABI and10 pure
validation cases. The previous23 control tests are adapted to keyboard dispatch
(native-method/enum assertions replaced, protection scenarios retained) and12
additional control cases are added. No permanent production regression removed.
Live validation is limited to the forward-action results above. Installation status is
recorded in the research document after file verification.

## Historical Direct-Call Policy (Superseded)

Latest live result after observer removal: large jumps sometimes refresh the
paused picture and sometimes do not; resuming playback restores normal visuals.
The user accepts this limitation and has stopped scene-refresh investigation.
Do not reinstall timing observers or add speculative refresh calls. Resource
changes alone do not validate every state field or the target replay frame.
Continue with read-only round/frame measurements for target-frame navigation;
the approximate300-frame step is still unverified. Analysis continues to use
continuous-playback captures, not the potentially stale paused picture.

2026-09-20 cleanup deployed: the user also confirmed three forward and three
backward clicks refreshed without arming the observer. This was still the
instrumented process, so it does not establish behavior without hooks.
The temporary observer, both comparison buttons and all call-site markers
are now removed. Replay control methods, enums, dispatch timing and guards
are unchanged. Process absence was checked twice before copying only the entry
and controls.lua; both SHA256 hashes exactly match their pre-observer versions.
The installed observer file was hash-checked and removed;41 other autorun files
were unchanged. All143 checks and both Lua syntax checks passed. The final
uninstrumented live check is pending.
The original failure's cause remains unproven; this is not a claimed fix.

The user chose manual native pause (R) as a requirement for replay controls,
because controls are responsive after that pause. Playback-time pause latency
research has stopped. The plugin pause button and its command were removed;
resume remains available from a paused replay, alongside all other controls.
Both click-time and execution-time state must be paused. A playing click is
rejected without stopping capture or creating a pending command. Resumed
playback, update conflicts or menus cancel pending commands instead of keeping
them for later. The prior same-thread nested dispatch permission is withdrawn.

The initial failure report superseded the earlier control-bar requirement: all
controls work while paused with or without that bar, except the large-jump
scene refresh. Plugin rollback/rollforward change HP, SA and drive readings,
but the character picture remains frozen. Direct native Z/C refreshes the
picture. A subsequent single-frame command also refreshes the plugin jump,
but adds/subtracts a frame and is not an acceptable refresh-only fix.
Resource changes do not yet prove that every world-state component or the
target frame was restored correctly. The approximately300-frame Z/C interval
is user-reported, not measured. "Operation sent" confirms dispatch only.
Static inspection confirms plugin dispatch occurs in ReplayUICtrl.update's
post-hook. Whether native dispatch timing, the selected action, or an additional
native refresh phase explains the difference requires a short call-order
comparison. MCP rechecked method signatures only; it did not establish their
behavior. No forced UI visibility, automatic stepping, new probe or runtime
change was added for this report. Any new hooks require a cold start.

Live information and capture retain their existing behavior. Control operations
still stop active capture and preserve its samples; when recording a replay,
use the game's R to resume after starting capture, not the plugin resume button.
No new latency tracing is deployed; its work-in-progress implementation was
removed on this scope change. Current tests:23 control +66 capture/UI +54 offline
=143. Control tests were reviewed for the new contract: plugin-pause and
playback-time deferred/nested-success tests are replaced by paused-only and
no-delayed-execution tests, while lifecycle/error/thread/capture protections
remain covered. No permanent production regression test was removed.

This policy supersedes the historical control candidates below. After the user
closed SF6, process absence was rechecked and controls.lua, runtime.lua and the
experimental entry were replaced and hash-verified. The other40 installed
autorun files were unchanged. The subsequent user test has the large-jump
refresh issue above; do not describe all paused controls as fully verified.
Frame-seeking automation is not implemented; a future implementation must
verify each jump's actual round/frame and refresh behavior, not count clicks.

Read [the experiment contract and validation steps](../../docs/research/CFN_REPLAY_CAPTURE.md).

### Temporary Jump Comparison (Historical, Retired 2026-09-20)

The following records the diagnostic build, not current installation steps.
The observer and its11 temporary tests were retired together; the optional
observer integration test was replaced by a no-instrumentation guard. Test
count changes from154 to143, with all22 original control tests preserved.
No permanent production regression is retired. The observer source and tests
are retained only in ignored `audit-output/cfn-jump-20260920/retired-observer/`,
alongside the saved evidence. Runtime JSON ignores remain to protect evidence.

A cold-load-only observer is prepared for the plugin jump vs native Z/C
scene-refresh discrepancy. It does not implement a fix. Twelve verified
ReplayUICtrl methods are observed (jump routes, pause checks, UpdateUI,
RefreshUI and single-frame routes). The existing control hook emits update
pre/post-begin and plugin-dispatch markers, without adding a second update
hook or changing dispatch timing. No native method is called by the observer;
no game fields are written and no object references are retained. Only plain
argument values, thread IDs, render ticks and existing update counters are
recorded. Pointer numbers are identity labels, not retained callable objects.

Each manually armed run lasts at most15 seconds /20,000 events. Overflow is
explicit in the output. Export happens once from on_frame, never a native
method hook; errors disable the observer, and Reset discards pending exports.
Output is non-overwriting `data/cfn-jump-trace-*.json` runtime evidence, excluded
from source/release assets. No capture session is started or overwritten.

With replay paused away from round boundaries, arm `记录插件跳转对照`, click
`向前跳进` once, observe the picture, and wait for `对照已保存`. Then arm
`记录原生按键对照`, close the REFramework overlay, tap C once in the game, and
wait15 seconds. Do not step another frame or resume between these observations.
Report both visual results; logs alone do not prove rendered scene freshness.
11 observer tests,23 control tests,66 capture/UI tests and54 offline tests
cover recording/dispatch contracts, not native refresh behavior.

Deployed after process absence was checked twice: only the entry, controls.lua
and jump_trace.lua were copied and SHA256-verified;41 other autorun files were
unchanged. No config, saved replay, DLL or intro mod changed. All154 checks and
the three changed Lua syntax checks passed. Awaiting the two live observations;
this is instrumentation, not a refresh fix. Remove the temporary observer once
the comparison has established the missing native path.

Live comparison received: both operations refreshed according to the user.
`cfn-jump-trace-20260920-001718-plugin.json` contains4991 events and
`cfn-jump-trace-20260920-001736-native.json` contains3554, both `complete`,
same replay F978A6QHF and UI instance. Each records exactly one rollForward;
neither records frameStep/frameBack, RefreshUI or another jump route.
At render tick4272, plugin dispatch is on thread30712 after update, while
UpdateUI is open on thread147796. At tick5332, native rollForward executes
inside UpdateUI on thread147796. Each path subsequently records
CheckReplayPauseNow, an intervening tick with battle_in_flight=1, and
CheckReplayPauseOnly two render ticks after dispatch. These render ticks are
not replay-frame deltas. Raw rollForward arg3 differs (64 vs0xffffffff);
do not replace enum arguments or interpret raw UpdateUI arg4/arg5 as decoded
semantic state based on this trace alone.

This successful pair establishes call-order differences, not the old failure's
cause. Instrumentation may affect scheduling. The original blank-scene symptom
was not reproduced, so there is no failing-vs-successful native comparison yet.
Next check is ordinary forward/backward clicks without arming a recording in
the current process. Inactive observer hooks remain installed: passing that
check is not equivalent to a clean run with instrumentation removed. No control
behavior or deployment changed after reading these files. Raw files are copied
and hash-verified under ignored `audit-output/cfn-jump-20260920/`.

Files:

- `CFN_ReplayCapture.lua`: opt-in experiment UI and composition root.
- `schema.lua`: ordered, dense sample columns; `false` means unavailable.
- `session.lua`: bounded in-memory recording and integrity diagnostics, no game APIs.
- `sampler.lua`: read-only native adapter; never retains scene-owned objects between calls.
- `runtime.lua`: hook lifecycle, manual start/stop/export, no replay controls.
- `presentation.lua`: plain-value information panel, no game API calls.
- `controls.lua`: paused-only keyboard request orchestration and clock confirmation.
- `keybindings.lua`: current native shortcut mapping and explicit manual overrides.
- `keyboard.lua`: plain JSON handoff; no native object calls.
- `CFNKeyboardBridge.cs`: foreground-only Windows key sender using existing REFramework.NET.
- `analyze.mjs`: independent offline continuity and state-comparison report.
- `events.mjs`: offline HP-loss/flag-onset observations and raw Action changes;
  no attack ownership, move semantics, actionable timing or punish verdicts.
- `recovery.mjs`: state-gated guard/parry/damage counter episodes; rejects new-hit
  and stale-counter false recovery. State exits remain candidates, not legal-action times.
- `boundaries.mjs`: pairs ordinary guard-exit candidates with the opponent's raw
  engine sequence and first subsequent boundary. Stops at sequence changes and
  gaps; reports observed timing only, never frame advantage or punish verdicts.
- `opportunities.mjs`: offline evidence assembly using recovery, boundary and
  event readers. Lists newly advanced blue cells, attack-state entry delay,
  coordinate separation and nearby events. No move semantics or punish verdicts.
- `deploy.ps1`: installs nine experimental Lua files and one C# source helper; refuses while SF6 runs.

From repository root:

```powershell
& 'C:\Users\76025\AppData\Local\Programs\Lua\bin\lua.exe' tools/test_cfn_replay_capture.lua
& 'C:\Users\76025\AppData\Local\Programs\Lua\bin\lua.exe' tools/test_cfn_replay_controls.lua
& 'C:\Users\76025\AppData\Local\Programs\Lua\bin\lua.exe' tools/test_cfn_replay_keyboard.lua
& tools/cfn_replay_capture/test_keyboard_bridge.ps1
node --test tools/cfn_replay_capture/analyze.test.mjs
node --test tools/cfn_replay_capture/events.test.mjs
node --test tools/cfn_replay_capture/recovery.test.mjs
node --test tools/cfn_replay_capture/boundaries.test.mjs
node --test tools/cfn_replay_capture/opportunities.test.mjs
```

Extract first-round observations from a stopped capture (output must not exist):

```powershell
node tools/cfn_replay_capture/events.mjs <capture.json> audit-output/round1-events
```

This writes JSON evidence and a plain-language Markdown table. The HIT_ST flag
profile is explicitly scoped to game version `20004000` and rejects other builds.
It is not a character Action resolver. See the research document for evidence.

For captures containing the supplemental recovery fields:

```powershell
node tools/cfn_replay_capture/recovery.mjs <capture.json> audit-output/recovery.json
```

The current-build ACT_ST profile is based on read-only native enum evidence.
It does not assert frame advantage, move ownership, cancel legality or punish reach.

The prepared sampler also records optional `nAction.Engine.mParam` scalars under
`metadata.engine_fields_profile = raw_engine_param_v1`: action identity/progress,
frame count, margin start, speed, flags, battle version, loop count and style.
Live short-capture reads passed (463 samples, no missing engine fields; action
identity/progress agree with existing getters). Timing semantics remain unverified.
Long-capture reads also passed (3889 samples); engine identity/progress agree on
every sample, and the 463 shared short-capture clocks match all 78 raw player columns.
The known round-boundary reset warning remains. The engine battle-version field
was zero throughout, not a verified build identifier.
No new native methods or hooks are called. Missing fields remain unavailable;
a read exception discards that player's engine evidence block, not the core sample.
`engine_margin_start_raw` is not an actionable frame or a proven cancel boundary.
Old captures cannot supply these fields retroactively. Cross-speed comparisons
must use captures with matching columns; the analyzer rejects mismatched schemas.

```powershell
node tools/cfn_replay_capture/boundaries.mjs <capture.json> audit-output/boundaries.json
```

The native frame meter's cell classifications now have one paused visual check:
blue ENDSTUN8, green FIRSTSTUN7, red HITBOX13, orange SHOTHITBOX14, yellow GUARDSTUN10.
Blue is punish-counter vulnerability, not an already-landed punish counter.
At round index1/frame2092, cursor34 identifies P1 guard stun and P2 attack-active.
The current buffer is circular; old dim cells are not future states. Native UI
frame-advantage text was -- despite a retained global StunFrame=-11.

Deployed after the user closed the game; first short live capture checked:
`frame_meter_profile=native_cursor_cell_v1` adds each side's
current cell index/type/flags and buffer size, plus global FMActive. It uses the
existing display clock and sampling hook, not a new hook or UI update call. Cell
reads fail independently, invalid cursors are never wrapped, and clock/cursor
changes discard the affected evidence. Missing/unknown Boolean reads stay absent.
The 475-sample capture (first-round frames192-666) has no missing meter fields
or clock gaps; display and replay clocks agree throughout. All 78 raw player
columns match the earlier long capture at shared clocks. Lua flags are readable,
but independent per-sample Boolean validation and 8x coverage remain unverified.
An advancing display clock does not prove the player's cell was freshly written:
P1 retained blue type8 on a held cursor at state exits389 and521. Do not extend
vulnerability windows from retained cells or infer actionability from type0.
The MCP Boolean strings disagreed with raw bytes in an earlier paused read;
byte-level evidence was used there rather than assuming every cell was empty.
The short interval contained no ordinary guard-stun type10. The subsequent long
capture has 3888 samples (3887 unique clocks), all meter fields readable and all
78 raw player columns identical to the earlier capture at shared clocks. It
covers 15 ordinary guard episodes, including the 11 existing exit candidates.
All 435 raw guard-state samples have type10. At exits2970,3066,3110 the defender
retains the old yellow cell; at1649-1653 the attacker retains blue after walking.
Fresh blue observations at1646-1648 and1774-1775 corroborate the earlier raw
boundary observations, but are not frame advantage or missed-punish verdicts.
At3090 type10 changes to0 while raw DEF persists: this unresolved case must not
be erased or automatically promoted to actionable. A hit may also overwrite a
same-tick blue cell, so previous-tick blue is not a necessary punish-event rule.
The subsequent 8x capture has 3917 samples, 3915 unique clocks and up to eight
samples per render callback, with no forward gaps or missing meter values.
At all 3887 clocks shared with the normal-speed capture, both players' cell
types and flags match exactly. All 21 meter columns match from first-round
frame199 onward; frames192-198 differ only in global/player cursor and meter
start. The first shared frame192 also differs in P2 raw action progress (81 vs191)
and engine flags (48 vs32); these discrepancies are retained, not filtered out.
The candidate continues 28 frames longer into round2. Thus the strict whole-file
comparison remains false, also retaining the known round-transition warning.
All first-round recovery episodes, boundary observations and HP/flag events
match exactly. This supports accelerated collection for the observed interval,
not all replays, earliest legal action, or missed-punish verdicts. Older display
summaries still differ at207 shared clocks and must not override cell evidence.

After explicitly closing SF6, installation is:

```powershell
powershell -NoProfile -File tools/cfn_replay_capture/deploy.ps1
```

No production entry, menu, library configuration, DLL, or release version is changed.
Do not install via Reset Scripts. Disable/remove the experimental entry only with the game closed.

Generate the offline first-round review table and detailed JSON (new output base):

```powershell
node tools/cfn_replay_capture/opportunities.mjs <capture.json> audit-output/opportunities
```

This requires the native cursor-cell profile and current verified build. It
keeps all ordinary guard episodes, including unresolved DEF/type0 disagreement,
and does not upgrade them to actionable. Blue observations stop at held/reset/
skipped/invalid cells, clock gaps, reaction/HP-loss/hitstop, sequence changes or
120 updates. Attack-state entry and event context are bounded to30 updates;
no attack observed is not a missed punish. Raw coordinate distance is not reach.
Same-clock player/display conflicts are rejected. Same-clock fight-state changes
are retained as barriers, not silently merged across the round-ending transition.
Both normal and8x recordings produce identical15 observations, six with newly
advanced blue cells. These have1-3 cells, not verified1-3-frame punish windows.

## Information And Controls Candidate

The original candidate was deployed after the user closed SF6. The user reports
all control buttons working except pause/resume. All seven installed
files passed hash verification. The original pre-deployment gates passed63 capture/UI Lua,
8 control Lua and54 offline Node tests (125 total). The information panel requests a
short-lived preview lease while visible. Without a recording, the existing
battle-update hook samples at most once per render tick, without creating a
session or writing files. During recording the preview reuses captured values;
8x capture remains per simulation update. Only copied Lua values reach ImGui.
Unrefreshed snapshots are marked as last-read, not as current pause state.
Unknown fields remain unknown. Position separation, stale meter cells and raw
recovery counters are not labelled as guaranteed actionability or punish reach.

The separate ReplayUICtrl.update post hook obtains its own current instance
from the same native invocation and validates it against the replay's battle
core. UI buttons only queue one command, stop recording (unsaved data remains),
and block starting a new recording while pending. Commands expire after120
render ticks and reject changed replay identity, modal menus, takeover, round
transitions, overlapping callbacks, and in-flight sampling. Failures latch off.
The installed SetPause-based pause/resume did not work in the user's test.
The deployed correction uses pauseOnly(PAUSE_ONLY) and resume(PAUSE), with
shortcut values read at runtime and execution-time state guards. MCP confirmed
the methods and enum names, not their behavior. These corrected calls still
require live verification after the next cold start; the12 control tests assert
dispatch, no-op guards, failure handling and single consumption, not engine
pause semantics. The63 capture/UI and54 offline tests also pass (129 total).
Other controls remain unchanged. Previous/next round use native availability
flags. The takeover button opens the native choice dialog, not direct1P/2P
injection. No automatic command is issued when opening the panel.

After the user closed SF6, only controls.lua was replaced and hash-verified
(SHA256 0D3829810BF95DD410E5453EB07A09417998A50E18C90D6B87B3E7501F15C4F7).
The other42 installed autorun files were unchanged. Pause/resume are not yet
confirmed fixed in the game; test that the replay actually stops and advances.

Follow-up live feedback: after pausing with the game's own controls, resume and
the other plugin controls work. While playing, all plugin commands are blocked,
whereas native controls work. This does not prove which shared guard fired.
The next candidate removes immediate rejection at click time
when a battle update is open, and retains the queued request until an idle UI
callback (at most120 render ticks). It still never dispatches while a battle
update is open. Timeout cancels the request, so pausing later cannot execute it.
Menus, dialogs, takeover and round changes cancel immediately with distinct
messages. No new hook, native-object retention, forced pause or polling writes
were added. An integration test uses the real battle runtime pre/post callbacks
to reproduce the deferred-request path.17 control,63 capture/UI and54 offline
tests pass (134 total); continuous nesting may still prevent dispatch and is
explicitly reported as a playback-time timeout, not a menu error. Live testing
must establish whether idle UI callbacks actually occur while playing.

This queue correction was subsequently deployed after the user closed SF6.
All134 tests were rerun successfully. Only controls.lua and the experimental
entry (status messages) were replaced and hash-verified; the other41 installed
autorun files were unchanged. Live playback-time dispatch remains unverified.
No target-frame automation or keyboard mapping changes are included. The user
identified V as previous-round; do not infer Z/C behavior or fixed step sizes
from the icons. Measure actual round/frame changes before implementing seeking.

### Playback Control Window Correction (Deployed, Awaiting Live Test)

Live screenshots confirmed the queued command waits for battle-update completion
and expires during playback. This identifies the in-flight guard, but does not
by itself prove same-thread nesting. The previous idle-only policy above is
superseded by the following guarded candidate.

Runtime now owns `can_dispatch_control(thread_id)`: an idle battle update or
exactly one open native battle update on the current UI callback's thread is
eligible, provided no battle post-hook is running. A balanced `post_in_flight`
counter spans all post-hook reads, including context and metadata, and is
released on errors and early returns. Multiple open updates, another thread,
missing thread identity, reset, and reentry during reads cannot qualify.
Controls still require their own non-overlapping UI callback, current replay
identity, no active capture and no modal/round/takeover state. They keep using
the current callback's UI instance, not a retained object or a different hook.

This changes runtime orchestration only, not sampling data or Action semantics.
The same-thread nesting integration test failed against the idle-only version
and passes with the correction.21 control,66 capture/UI and54 offline tests
pass (141 total), including read reentry, cross-thread waiting, overlap, error
cleanup and preservation of stopped capture data. These are simulated callback
orders, not proof of the live engine's order or safety.

SF6 was absent at deployment and rechecked immediately before copying. Only
runtime.lua and controls.lua were replaced and hash-verified;41 other autorun
files were unchanged. No config, saved capture, DLL or intro-skip mod changed.
The next live check is one pause click while playing, followed by resume if
pause succeeds. Do not Reset; absolute/combined frame seeking remains absent.

Absolute frame seeking is NOT implemented: seek(int,int) alone does not prove
full world-state restoration, and the seekbar float event's units are unverified.
The UI reports this limitation instead of exposing a nonfunctional jump button.
Deployment of this candidate requires closing SF6; do not hot-load or Reset.
