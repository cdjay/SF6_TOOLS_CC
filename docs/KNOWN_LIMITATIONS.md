# Known Limitations

Status: `CURRENT`

This is the sole current list of evidence and architecture blockers. Green
offline tests do not remove these limitations.

October 8 native-eight-slot branch (`codex/native-eight-slots`): the startup
entry no longer mounts an expanded recording bank, rebuilds the native
record/play rows, expands the reversal picker, or offers page reload. The
independent Wood Library tab remains, with configuration selection, save,
save-as, import, clear, note editing and information. Only the game's native
eight recording slots can be read or changed. Files containing more than eight
recordings remain on disk and visible in the catalog, but cannot be imported
or overwritten by an eight-slot save. This is an offline-tested branch, not a
live-game crash fix claim. The earlier 80-slot evidence below applies to the
previous implementation, not to this branch. Cold-start and role-switch smoke
tests are still required before distributing this variant.
An October 8 live read found the current Mai bank still contained 80 slots after
this branch loaded. The old gate therefore never installed the Wood Library
tab. The read-only legacy-bank presentation fix keeps the tab and character
catalog visible, while refusing all configuration writes and autoload until
the actual bank is eight slots. It does not truncate or migrate game data
automatically; live-game confirmation of the tab is still pending.

October 8 crash root cause and hardening: the 00:47 REFramework dump and log
show a freshly created playback menu row dying (refs 2 to 0) while the next row
was created, then an access violation in the engine's UpdateVM cycle collector
on a destroyed object, the same site as the September 15-16 expansion crashes.
REFramework Lua references are keyed by address and deduplicated, so Lua cannot
reliably own objects that game structures reference. The branch now gives every
injected object one permanent engine reference (`NativeOwnership`), never
releases from Lua, never uses `create_*_global`, reuses one root page per Lua
state, serves cached permanent hook strings, and reads/writes recording inputs
in raw memory instead of boxing one object per frame. Legacy banks gain an
explicit, double-confirmed restore that keeps slots 1-8, drops the rest, and
clears recording reversals pointing past slot 8. All of this is offline
contract coverage only: cold start, legacy restore, 1P/2P switching, match
return and save still need real-game confirmation before tagging.

October 5 configuration-save review: the shared library queue now waits for
30 update callbacks after a newly mounted session, both SaveManager idle and
the training manager's save request to clear before running a closed-menu job.
It also refuses to run while native Release is in progress. A fake-SDK
regression covers the gates, resumption, and cancellation when training ends
during the wait. This prevents confirmed control-flow overlaps, but does not
identify the cause of the tester's crash:
there is no crash report for that event, and match return / P2 switch with
the new build still needs real-game validation. Native Release retirement and
configuration snapshot reads remain outside the protection of Lua exception
handling for process-level access violations.

ComboTrials recording remains available in training. Its legacy CFN replay
recording entry, hotkeys and remote recording commands are disabled; the replay
bottom recording bar is hidden. Existing training/demo playback and standalone
training-library recordings are unchanged. Recording in the new replay-analysis
UI is planned, not yet implemented. The training/replay recording scope has a
focused regression, but real-game acceptance is still required.

Dummy guard persistence has focused offline coverage but still requires a
real-game smoke. New training-library saves include the five verified native
guard fields; older v2 files intentionally leave the current guard state alone.
The shared training-mode guard override now restores the captured full state
when a mode closes, training becomes unavailable, replay/Battle Hub is entered,
or scripts reset. This fixes the proven old control-flow gap where leaving
training returned before restoration and the old fallback assumed no guard.
Offline tests do not yet prove native menu text refresh or persistence across a
full game restart.

September17 recovery evidence supersedes blanket restart-only guidance:
the user disabled/re-enabled the script inside training, observed waiting, then
pressed pagination reload and received the stop/restart message. They exited
training, reloaded outside training and reentered successfully; the screenshot
reports 6 imported recordings, 74 cleared slots and 30 restored reversal entries,
and the user confirms usability. This is one successful outside-training recovery
without restarting the game, not proof of safe in-training reload, every Reset
mechanism, repeated-cycle stability or completed native cleanup. No lifecycle
logic or stop-message policy changed in this release.

Version1.1.14 also changes only the native named-slot display to
"number - description", without outer brackets, for recording/playback and reversal
labels. Empty descriptions retain native defaults. Saved annotations, frame text,
configuration labels and confirmation markers are unchanged. Focused offline
regressions cover reused rows, name changes and all three reversal scopes; the
post-removal appearance has not been separately accepted by the user.

InlineClear is prepared, not deployed. User rejected SlotListLayout's ticker-only
clear confirmation: it must match import's inline confirmation. First activation
now marks the existing clear row without notifying or queuing work; the second
submits the unchanged clear operation. Cancellation removes the marker. 36 related
test files pass; the inline rendering still needs live acceptance.

SlotListLayout was cold-deployed September16 at16:25: the slot-description page uses row1
for its native pager, rows2-9 for recordings and row10 for Back. The duplicate
title and save reminder are removed; unused trailing rows remain nonfocusable.
The existing 13-row array and spin commit protocol are retained. The catalog
still uses row10 for paging. Tests cover each pager position and switching
between both lists; first-row input and visual layout still require live acceptance.
The same pending candidate adds native-tab reentry reset and two-step clearing.
ChangeTabIndex(Int32) and get_PrimaryListIndex were confirmed through read-only
MCP schema inspection. A guarded pre-hook resets only owned row data before the
original tab transition; no native refresh is invoked. Simulated transitions
cover reentry, same-tab preservation and confirmation cancellation, but actual
mouse/keyboard tab routing and the clear prompt still require live acceptance.
36 related test files and deployment checks passed. Only NativeLibraryTab,
NativeLibraryView and LibraryMessages changed;173 other files were unchanged,
none added or removed. This deployment is not live-game acceptance.

SlotFrameStyle (cold-deployed September16 at16:01, focused live acceptance received) changes NativeLibraryView text only:
uniform slot-number/name/length labels, default-name fallback, full gray text and
a dash for empty recordings. Empty rows remain focusable/editable; unknown frame
reads are not marked empty. 36 related test files pass, including restoring normal
text after a recording is added. User reports normal behavior; screenshots confirm
uniform names, frame labels, full gray empty rows and page2 showing slots9-16 with
the matching 2/10 indicator. This does not verify all record/import/clear freshness
cases below, all reversal groups or absence of historical crashes. Deployment updated NativeLibraryView
only;172 other files unchanged, none added or removed.

Current SlotFrames candidate was cold-deployed September16 at15:48: the description list adds current
recording Frame values from a closed-menu scalar snapshot, not saved JSON data.
Empty recordings are distinguished from failed reads; snapshots with mismatched
fighter/capacity are not used. 36 related test files pass. Live agreement with
the native recording page, after recording/import/clear and across pages, remains
to be checked. No recording pager, native initialization or lifecycle changes.
Only Records, Library and NativeLibraryView were updated;169 other files unchanged,
none added or removed. Recordings and configuration files were not modified.

Prior ListPagerReversal smoke FAILED: the visible page number advanced but the
slot list stayed on page1. MCP inspected the displayed spin and found null
SpinAction/CheckAdd/CheckSub, default MaxNum99 and unchanged ViewData.Index0.
The TEXT/SPIN variant change had not initialized the native input control; fake
tests had incorrectly bypassed this prerequisite by directly invoking its event.
The ListPagerInit candidate only adds validated per-row InitSpinBox(Int32)
on entering SPIN or changing its options, with reentrant user-action suppression.
The new regression fails against the deployed code and passes with this fix.
No whole-page rebuild, recording pager change or extra hooks. Exact native row
initialization required a live-game check; user has now explicitly confirmed
paging works. Reversal-name acceptance remains pending.
Cold deployment September16 at15:29 updated NativeLibraryTab only, with170 other
files unchanged and none added/removed. 35 related test files passed. Focused list
paging acceptance does not prove absence of historical intermittent crashes.

Latest September16 follow-up supersedes the broad reversal overview acceptance
below: Down names work, but Guard/Damage default labels remain. The native format
argument is a reversal row ordinal, not its referenced recording number; the old
mock used matching numbers and missed this. The ListPagerReversal fix
resolves names from the displayed parent group's SkillIndex and checks SlotID+1
against the formatter. A differing-index regression failed before the fix and
now passes for all three groups. Live acceptance is still required.
The same candidate replaces list Previous/Next buttons with a native
page spin (hidden for a single page), reusing the accepted recording-spin protocol
through a separately scoped adapter. Simulated first-click refresh, adjacent
option probes, both hook registration orders, catalog/slot paging, return to main,
one-page hiding and stale-session cancellation pass (35 related test files).
Actual spin initialization after a TEXT/SPIN display-variant change remains a
real-game check, not proven by mock tests. Cold deployment September16 at15:12
updated three existing menu/name modules and added one adapter;165 other files
were unchanged, none removed. AutoLoad behavior, configuration files, recording
capacity and lifecycle are unchanged. User acceptance is pending.

User accepted ConfigRename (cold-deployed September16 at14:01): configuration
title display, native prefill and cancellation work. The SlotRename candidate
was cold-deployed September16 at14:19: it enables the existing slot editor through a fixed-row,
eight-per-page list with a closed-menu capacity/name snapshot. Slot descriptions
change only runtime annotations; Save/Save As is required to retain them.
User now reports slot-list editing/saving/switching normal, with screenshots
confirming names in recording/playback and the reversal recording picker.
ReversalNames (cold-deployed September16 at14:34, overview display accepted) adds
scoped native overview text substitution using the actual recorded action index;
it does not draw labels independently. Offline regression reproduces the missing
overview name and passes after the fix; differing row/recording indices and all
three reversal groups were not individually reported by the user. No runtime,
recording pager, native input ownership or lifecycle changes are included.
Historical native ownership/crash limitations are not declared resolved.

Before AutoLoad, fresh-entry names remained default until import because the entry
explicitly suppressed autoload; Runtime clears annotations for each new session.
Read-only inspection and the existing entry simulation confirm this behavior.
The user reported it after overview acceptance and approved restoring full per-P2
remembered configuration import. AutoLoad (cold-deployed September16 at14:47,
user accepted) removes the entry's
no-op autoload proxy only, retaining the existing post-attachment/closed-menu job
queue and staged native-root loader. First-entry/reentry name restoration,
readiness gates, missing/mismatched configurations and no automatic retry are
covered offline. The user confirmed all requested first-entry, training reentry
and P2-switch checks normal; broader historical crash limitations remain open.
Names are loaded with recordings, never overlaid on unrelated native content.

ConfigLayout user smoke accepted filtering/layout/color but showed LINE visuals
remaining inside the catalog. MCP confirmed Type0 in data versus SwitchShow
focus4 in its display group. ConfigPolish was cold-deployed September16 at13:47,
with live acceptance pending. It synchronizes
only the two owned group variants in the native action scope, moves lines to
rows2/8, colors all information, uses Chinese brackets/duplicate display numbers
and bounded named success messages without the library prefix. Fake tests cover
the retained visual state, foreign group refusal, display return, title identity
and truncation. This does not yet establish live group-switch safety or visual
correctness. Both editors remain disabled; no changes to recordings or stored
configuration names. Earlier pending ConfigLayout text below is stage history.

Latest follow-up: user accepted ConfigList switching and rendering. The next
ConfigLayout (cold-deployed September16 at07:15, live acceptance pending) changes
only NativeLibraryTab/NativeLibraryView: merged
selection title, reordered actions, native LINE separators, colored info title
and strict current-P2 catalog filtering. LINE/TEXT_ONLY transitions on existing
rows and color rendering still need live acceptance. No new hooks, forced
ViewUpdate, recorder changes or editor enablement. Offline tests must verify
original-index selection after filtering, no foreign/unknown/P1 entries even
with import override enabled, character-change confirmation cancellation and
restored native row types on list return. The previous ConfigList pending
acceptance text below records its deployment stage, now superseded by feedback.

Latest September16 scope: user accepted seven native actions and concise,
single-result feedback, then requested a daily-use configuration list instead
of full REFramework-panel migration. The ConfigList candidate was cold-deployed
at06:57 on September16 but is NOT live accepted. It reuses13 native rows, eight configs per list page and
owned ViewData.IsUpdate; preflight must find every row before a body change.
Offline coverage includes first-select/second-import, stale catalogs, missing
view rejection and confirmation cancellation on brief menu closure. It cannot
prove native layout/focus correctness or crash freedom. Backup/restore remain
in REFramework; options migration is paused. Both rename rows are deliberately
disabled until the separate editor stage. Earlier migration plans below are
historical stage evidence, not the latest requested menu scope.

Ticker-create correction smoke: user reports executable, and screenshot
codex-clipboard-db3e640d-eda0-4443-a979-c6fe729b8543.png visibly shows the native
left ticker "木人库：已排队，关闭游戏暂停菜单后执行" with the native pause menu
closed. The old panel shows saved state. This proves native ticker rendering,
not yet failed-request visibility over an OPEN pause menu or the final success
ticker. Captured native-ticker-user-accepted.log/png in system temp
sf6cc-library-ticker-create-20260916-052955; no NativeLibraryTicker stop or the
prior MemberAccessException/corrupted-VMContext appears in this captured run.
The next undeployed action-only stage extends the root to four fixed buttons:
save, export, refresh and clear. All delegate to Library.request and native
feedback; no file picker/editor, new navigation hooks, forced refresh, Runtime
or recording changes.26 root checks and32 related test files pass. Full native
configuration selection/import/rename/options migration remains incomplete.

Native-message smoke FAILED: user reports save succeeded in the old panel but
no ticker appeared. The captured ticker-send-failed.log in system temp
sf6cc-library-native-feedback-20260916-052100 records NativeLibraryTicker stopping
at05:24:40 with "caught (...) exception", immediately followed by MemberAccessException
and a previously corrupted VMContext report on get_RecordFunc. No further live
method calls/Reset were requested. Source comparison found the new ticker omitted
the simplify=true argument used by both original SF6CC and WTT. REFramework's
Sdk.cpp forwards that argument identically for local/global factories;
RETypeDefinition.cpp uses distinct Activator creation paths. The correction,
cold-deployed at2026-09-16 05:29 after confirmed closure and process checks,
changes only that argument, retaining the global-wrapper ownership.
A regression rejecting the missing argument fails before the correction and
passes afterward; all32 related test files pass. This establishes the omitted
creation contract, not yet successful live ticker display. Restart is required
after the native exception; no live retry or menu/recording change was made.
Only NativeTicker.lua changed,123 files unchanged, zero added/removed. Evidence:
system temp sf6cc-library-ticker-create-20260916-052955. Live ticker retest pending.

Current accepted checkpoint is99c5733. The subsequent notification
stage routes library reasons/progress/results to the game's native Ticker,
not menu text or REFramework. NativeTicker follows the published SF6CC/WTT
TickerRequestData.Init(112,nil), TickerId1, Category6 request route, with owned
GetMessage replies, bounded queues and late-update-only submission. MCP confirms
the current type signatures/fields. IsForceDisplay is requested for visibility
over pause menus, but position/visibility are NOT yet live-verified. All32 related
test files pass; the full no-REFramework menu migration is not yet implemented.
Only the save row is connected pending this native-message acceptance gate.
Cold-deployed at2026-09-16 05:21 after closure confirmation and process checks:
one root module changed, two message modules added,119 files unchanged, none
removed. Entry, Runtime, recordings and configs unchanged. Evidence/rollback:
system temp sf6cc-library-native-feedback-20260916-052100. Live smoke pending.

Cold-deployed candidate at2026-09-16 04:58: the existing Release pre-hook now invalidates a
scalar presentation-session identity. NativeLibraryTab binds that identity and
the Runtime instance before serving callbacks, including message/layout getters.
Tests reproduced stale callback dispatch while state() still reports active;
the new guard blocks it before native argument access, preserves in-flight
post-hook returns and re-adopts reused resources without allocation. All30
related Lua test files pass (25 root contracts,88 Runtime integration cases).
These are fake-SDK dispatch tests, NOT a reproduction/fix of the04:40 crash.
After closure confirmation and process-absence checks, only Runtime and
NativeLibraryTab changed;114 files unchanged, zero added/removed. The entry and
configs remain unchanged. Previous/candidate code and hash inventories are in
system temp sf6cc-library-session-guard-20260916-045815. User accepted the whole
requested smoke: paging/library, Mai-Bison-Mai switching, exit/reentry and save.
The captured session-guard-user-accepted.log confirms matched save completion
at05:03:25 (issued1/completed1/readers0), retirement/close at05:03:26 and root
re-adoption at05:03:36. All24 deployed autorun hashes match the manifest.
Object-release ownership and Function reentrancy warnings remain; this is one
accepted run, not proof of crash-free lifetime or the earlier crash's cause.
No additional game changes or repeated smoke requested at this checkpoint.

Save-row user smoke: native Save Current Configuration and automatic menu
closure worked; user reports recording intact. Screenshot shows Mai config
Mai_20260916_030520.json saved at04:41:35 with7/80 valid recordings and a success
message in the existing panel. Native guide repaint and a clear/reimport
roundtrip were not separately confirmed. User also reports ONE character-switch
crash before restart; repeated1P/2P switching after restart worked.
The matching04:40:18 dump is preserved in system temp
sf6cc-library-save-row-20260916-043544/character-switch-044018.dmp, SHA256
20136C7BB3C5E42520B5E27905F5308ABF024DFACAA4ADA800466AE16A04BE39.
Offline CDB confirms c0000005 at146f25612, R9=0, through the same original
UpdateVM entry as earlier failures. This establishes the repeated endpoint,
not the invalidating writer or causality of the save action/root tab.
Current framework log starts after that crash, so the prior pre-crash plugin
sequence is unavailable in this log. The new run log and screenshot are saved
as save-and-repeat-character-switch-accepted.log and save-accepted.png. Code
hashes still match the deployed pilot. Four ownership-release warnings persist
in the normal run. Deferred hooks did NOT establish crash-free character
switching. Further feature deployment is paused; no live debugger, runtime
changes, forced Reset, or additional reproduction was requested. Asked only
which player/characters were involved and whether save had already been used.

Deferred-root same-process exit/reentry ACCEPTED by the user. Log shows native
save fence retired with issued1/completed1/readers0/released=true at04:28:56,
then Runtime active at04:29:07 and the owned root adopted at04:29:08. Deployed
autorun hashes match the pilot manifest. Accepted entry/root copies and
empty-root-reentry-accepted.log are retained in system temp
sf6cc-deferred-library-root-20260916-042329. This bounds functional acceptance
to the tested run, not a general crash-free lifecycle guarantee.

The next source stage, DEPLOYED at2026-09-16 04:35 after confirmed closure and
process-absence checks, replaces the existing blank row with Save
Current Configuration. Only NativeLibraryTab changes: it delegates to shared
Library.request("save"), returning the established native close code1 only
when the request is accepted. Existing entry/Library execute after menu closure;
no file/native recording writes occur in the button handler. Root navigation,
foreign rows, layout callbacks and dormant Runtime cannot queue saves. Pending
jobs suppress duplicates; rejection stays open, request exceptions cancel the
queue through the existing deferred cancellation API. The guide reads cached
selection/status, without a file scan or forced native refresh. Selection still
uses the existing management panel during this one-button pilot. Nineteen root
contracts and30 related test files pass; save/close acceptance and remaining
native validation limits are recorded above. Preview with deploy_deferred_library_root.ps1 -Stage SaveRow
allowlists only the root module. Deployment changed exactly that file, leaving
110 files unchanged and none added/removed. Rollback copies and manifests are
in system temp sf6cc-library-save-row-20260916-043544. No commit, package or data
editing was performed. Native guide repaint remains unconfirmed.

Deferred-hook empty-root pilot DEPLOYED at2026-09-16 04:23 after user closure
confirmation and process-absence checks. Only entry and NativeLibraryTab changed;
109 files unchanged, none added/removed. Rollback copies and hashes are in
system temp sf6cc-deferred-library-root-20260916-042329. Sixteen root contracts
and the stub-root/manual-entry harness passed again. User accepted initial
entry, paging and root navigation/close-reopen. Screenshots show the blank
Library after Reversal and recording page1/10 with both native footer settings.
Log confirms Runtime active at04:26:53.494, root installed at04:26:53.734 and
180 active updates survived. Autorun hashes still match the deployment.
Evidence: empty-root-navigation-accepted.log, empty-root-accepted.png and
recording-footer-paging-accepted.png in that temp directory. No expiry/AV or
Lua ownership-release marker was found in this captured run. This is initial
functional acceptance only; the subsequent same-process reentry acceptance is
recorded above. Do not Reset; the later save-only pilot is described above.

User revalidated the restored0d27b37 baseline: training entry, paging and
character switching all normal. Captured log shows active mounts at04:20:34
and04:20:49, each surviving180 updates. All deployed autorun file hashes match
the rollback baseline. Evidence: rollback-paging-character-switch-accepted.log
in system temp sf6cc-empty-library-root-20260916-035026. Four Lua ownership
release warnings and Function reentrancy warnings remain; this is functional
acceptance, not a lifetime-safety proof or causal proof against the rejected tab.
The deferred-hook candidate has a separate preview-by-default deployment helper
under exam/native-training-library/deploy_deferred_library_root.ps1. Its preview
passed16 root contracts and the stub-root/manual-entry harness without game
writes. The subsequent cold deployment above changes only
entry + NativeLibraryTab are allowlisted. No config controls are added this round.

The empty-root source now defers ALL native method lookups/hook registration
until recording Runtime is active, offline training is allowed and the native
menu is confirmed closed. The rejected pilot only delayed page allocation:
its module load eagerly installed seven hooks and its message hook decoded GUIDs
before any root existed. A new contract test failed on this eager SDK access,
then passed after deferral. Dormant/failed hooks pass through without native
argument/owner reads; partial setup stops once without publishing/retrying.
Sixteen root contract checks and30 related test files pass. The separate staged
entry harness stubs the root module and verifies manual jobs, not native root
integration. These tests establish startup isolation, NOT a reproduction or
fix of the native lifetime crash. This source change is now a game-only pilot;
canonical entry and committed checkpoint0d27b37 still leave root support disabled.

Offline CDB inspection of the latest03:53:26 dump confirms a null dereference
at146f25612 (R9=0) from the original UpdateVM application-entry call. This is
the same previously identified endpoint, not a newly identified writer. The
small dump omits the relevant object heap bytes; it cannot recover the first
invalidating operation. No live debugger was attached. Upstream SDK sources
were read at the run's logged commit0a07faae46a6fc1c51cd1699a0cf99a3f9c2679f;
no DLL, allocator, GC control or reference-count policy was changed.

Empty-root pilot REJECTED after two user-reported startup/entry crashes.
At2026-09-16 03:56, with the game process absent, restored only the game entry
and NativeLibraryTab from the verified pre-deployment copies for0d27b37;
109 other files unchanged, none added/removed. Configurations are untouched.
Evidence/manifests: system temp sf6cc-empty-library-root-20260916-035026,
failed-second-launch.log and rollback-result.json. Only the second crash log
has been verified. At03:53:26.364, recording menu construction reported a
previously retained row expired (refs2 ->0, type unavailable) after creating
slot7; at03:53:26.368 native access violation c0000005 occurred at146f25612.
No active Runtime or successful root installation was logged. This does not
prove the tab insertion caused the failure or identify the invalidating native
instruction. Offline contract tests cannot reproduce this native lifetime
failure; the rollback contains the candidate, not a proven crash fix. Suspend
the pilot's navigation test instructions until a discriminating diagnosis exists.

Checkpoint committed as0d27b37 (not pushed/packaged). Subsequent uncommitted
root-tab pilot places an EMPTY library page immediately after REVERSAL(5),
confirmed through live read-only metadata. One blank focus target preserves
native navigation; no configuration reads/jobs/editor/autoload. Installation
requires active recording Runtime and closed native pause menu. Native and
foreign roots retain their relative order. Eleven root contract checks,30
related test files and staged-entry integration passed before the failed smoke.
Game is restored to the checkpoint; the pilot helper must not be redeployed.
Canonical entry still does not load it. Root navigation/close-reopen/reentry
must be validated before restoring actual library controls. Existing release
warnings are unchanged. This is not an accepted new UI or lifecycle fix.

Baseline consolidation: canonical entry and22 private Lua modules now match
the currently user-accepted game deployment byte for byte. Seed expansion and
allocation-free busy deferral are included; native root/editor and autoload
remain disabled. All30 related test files pass. The87 runtime checks retain
six legacy-constructor fault cases against a test-only pre-seed Session fixture;
all remaining cases use the current Session. Eight seed-path checks and the
real manual-entry harness are now discoverable tools tests. No regression was
deleted. This is a local checkpoint, not full-corpus/release or complete native
lifetime acceptance. Ownership-release warnings remain open. Prior statements
that accepted sources are only in exam are superseded by this consolidation.

Transient-idle live regression accepted (2026-09-16 03:39): user reports Mai,
Bison and Sagat all work. This process logged four active mounts with factory
wrapper counts125/170/295/421 and no recorder-not-idle, Slot Init or expired-menu
error. Screenshot confirms Sagat expansion to80 and correct refusal of the
selected Mai configuration for a different P2. Bison slot9 record/play had
already passed in the prior run. Eleven ownership-release warnings remain
across the three switches; no complete lifetime-safety claim is made. No runtime
change during acceptance. Evidence: latest deployment temp directory,
three-character-switch-accepted.log. Tested entry/seed Session still differ
from canonical sources; preserve them accurately before a baseline commit and
root-tab work, rather than committing an untested entry as the accepted runtime.

Transient-idle fix DEPLOYED at2026-09-16 03:36 after user confirmation and
verified process absence. Changed game Runtime and candidate Session only;
109 other files unchanged, none added/removed. Seed helper, entry, pager and
configs unchanged. Manifest/prior sources: system temp
sf6cc-native-seed-idle-fix-20260916-033607. Live automatic recovery pending:
same training session Mai/Bison/Mai/Bison, wait3 seconds after each switch with
pause menu closed, then inspect pagination. Do not use scene exit or Reset as
recovery. No need to repeat accepted slot9 recording/playback. Commit/root-tab
restoration remains paused; ownership-release warnings are not fixed by this.

Subsequent Mai-to-Bison switch failed at2026-09-16 03:29:51 with
`[context] recorder not idle`, before any native allocation/save baseline.
Runtime nevertheless retained a failed entry and latched the context attempt;
user exit/reentry recovered. This is a distinct transient-readiness handling
defect, not new evidence of slot Init corruption. User additionally confirmed
Bison slot9 recording and playback work. The pre-allocation idle gate now
returns structured deferral (fourth prepare result, no failed lease). Runtime
clears only that attempt, waits through existing layout/context checks and does
not log it as expansion failure. All post-allocation errors remain nonretryable.
Regression failed on old behavior, then passed;87 Runtime cases,8 seed cases,
28 related test files and both entry harnesses pass. Not deployed yet; cold
deployment of candidate Session and Runtime is prepared. No new native hooks,
bank-copy/pager changes, config writes or relaxed import checks. Release warnings
remain unresolved. Evidence: prior deployment temp directory's
busy-context-failure-and-reentry.log. Commit/root-tab restoration still paused.

Native-seed first cross-character paging acceptance (2026-09-16 03:28): user
entered training through R with P2 Mai, switched to Bison, then back to Mai;
pagination remained available. Screenshot verifies Bison page2 slots9-16.
Log shows three active mounts (factory wrapper counts45/170/215) and two
successful retire/close cycles, without prior Init/menu-construction failures.
There remain3 then4 Lua ownership-release warnings after switches; this is NOT
overall lifetime stability or leak-free acceptance. Direct Bison cold-start and
newly constructed slot recording/playback remain unverified. Candidate/game
hashes match. No runtime edits; log archived in the deployment temp directory
as mai-bison-mai-paging-accepted.log. Next test only Bison slot9 record/play;
no Reset, no Mai import, no root-menu changes or commit yet.

Native-seed candidate deployed at2026-09-16 03:25 after user-confirmed closure
and process-absence checks: replaced game NativeRecordingSession.lua, added
NativeRecordingSeed.lua;106 other files unchanged, none removed. Entry, pager,
configuration files and save-completion guards unchanged. Seven candidate
simulations rerun successfully. Deployment manifests and prior code: system
temp sf6cc-native-seed-candidate-20260916-032503. Game acceptance remains pending:
cold start directly with P2 Bison, inspect recording/playback pagination and
one page2 switch. No Mai import, Reset, new hooks, root tab or commit.

Cold-start M. Bison comparison (2026-09-16 03:17) FAILED before menu creation:
slot52 created/retained refs=1, private-array-owned refs=2, then Init returned
with refs=0/type unavailable. No previous character switch is required. The
screenshot independently confirms a normal import compatibility refusal:
selected Mai configuration ID28 versus current P2 ID26. Do not disable it.
This repeats the known per-slot Init lifetime failure; it does not establish a
51-slot limit or the same invalidating instruction as the earlier pager fault.
Archive: system temp sf6cc-bison-cold-init-20260916-0317/bison-cold-start.log.
An isolated exam candidate NativeRecordingSessionSeed.lua changes only the
original-eight bank path: duplicate a detached native seed, give its bank eighty
references, then native Duplicate creates the final independent slot/input/buffer
graph. The aliased seed is never mounted or saved; existing full-bank identity
validation runs before clearing added slots or attaching. Existing eighty-bank
construction and entry/pager/save guards stay unchanged. Native copy traversal
was inspected in SLOT_EXTENSION_RESEARCH.md; actual seed expansion is NOT yet
game-verified. Seven fake-SDK checks include captured-Init-failure contrast,
empty banks, first-page navigation, existing eighty path, and fail-closed copy/
alias rejection. All28 related test files and accepted manual-entry harness pass.
No production source or game file changed. Cold-deployment helper is prepared
under exam; it requires process absence and verifies the exact two-file delta.
Next: user closes game, deploy candidate, cold start directly with P2 Bison;
inspect pagination only, no Mai import or Reset. Commit/menu restoration paused.

Character-switch regression (2026-09-16 03:09): user reports Mai to M. Bison
(P2) loses pagination and refuses import; returning to Mai restores pagination.
The log shows retire/close of the previous session followed by a rejected
page107 pager_part_1 allocation: created_refs=0, retained refs=0, unavailable
native type. Later active recovery also logged three Lua ownership-release
warnings. This identifies the failed construction boundary, not the invalidator.
Read-only MCP confirms fighter26 has8 slots and fighter28 has80. No character
allowlist or corrupt JSON is established. Expansion-error import protection
rejects configurations over8 slots; the exact user-visible refusal text has not
been confirmed, so fighter mismatch may be an additional independent gate.
Manual operations remain user-accepted, but cross-character stability is not.
Commit and new root-tab work paused; no runtime deployment. Evidence: system
temp sf6cc-character-switch-20260916-0309/character-switch.log. Next comparison:
cold-start directly with P2 M. Bison using unchanged scripts, no Reset/probe.

Manual-stage acceptance (2026-09-16 03:04): user reports export, import and clear
all working. Runtime reached active. The game configs directory now contains
Mai_20260916_030347.json (104318 bytes), confirming a new real export, alongside
fresh automatic pre-operation backups. No runtime code changed for acceptance.
The user subsequently confirmed save-current also works. Native root/editor
restoration and repeated reentry/Reset after these operations remain outside
this acceptance. Earlier pending steps below
are historical; do not repeat the accepted manual workflow.

Earlier manual-stage failure (2026-09-16 02:46, PID46008): export/import/clear
were refused with the offline-training/context message. No new export appeared;
only the two09-15 configurations remain. Runtime never logged active. This is
NOT evidence of failed empty-slot clearing after successful import. The new
entry omitted Context preloading while Library.runtime_context first required
it from a deferred callback. REFramework's autorun module search path is not
available then. Earlier entry/editor loading masked this dependency.
Library now loads Context eagerly itself; the gate remains unchanged. New real
runtime_context/loader-window regression failed before and passed after the fix.
Prior staged integration used a mocked runtime_context and missed this failure.
28 related test files and both staged entry harnesses pass. At02:55 user confirmed
closure and process absence was verified. Deployed Library.lua only;78 files
unchanged, none added/removed. Hash06E04F44619E4E940915DDD5E8DE29BE341B5EF0F1EE49CA5530279906337D30.
Archive: system temp sf6cc-manual-library-context-fix-20260916-025513.
The previously requested manual export/import/clear check is now user-accepted;
preserve the independently accepted paging baseline. This does not establish
complete native-menu or long-run lifecycle stability.
Evidence: system temp sf6cc-manual-library-stage-20260916-024424/blocked-operations.log.

Current stage DEPLOYED at2026-09-16 02:44 after user confirmation and verified
process exit: manual shared-library operations through the
existing REFramework panel, with automatic import explicitly suppressed. Native
root tab and editor remain disabled; accepted Runtime/Pager/SaveCompletion and
factory-wrapper policy are unchanged. New ignored entry uses the real shared
Library and one closed-menu job owner; simulation covers deferred import/save/
export, status/names sharing, cached redraw, exit cancellation and no reentry
autoload.27 related test files and9 accepted-entry checks also pass. This is not
native import or full-menu acceptance. Only the entry changed;78 files unchanged,
none added/removed. Candidate hash83D9A69BA0B3A2B5B7A1689C417F6CCE86CC3AABD24D26C17DA2AD5B3082F6ED.
Deployment: system temp sf6cc-manual-library-stage-20260916-024424.
Next operator action: enter training, verify paging, close native pause menu,
open REFramework's standalone library panel, export current data and import that
newly exported selection. Verify status and paging. No fabricated JSON, Reset,
automatic import, editor or root-tab test. Baseline is independently preserved
under ignored audit-output/native-library-baselines/20260916-0236-reentry-accepted,
all79 files verified against deployment hashes. No commit or release was made.

Latest acceptance (2026-09-16 02:36, same PID102992): user reentered training,
opened Dynamic Recording, confirmed pagination and exited normally. Runtime
became active at02:35:59.452 with a new TrainingData/baseline identity. FinishSave
matched1 at02:36:16.767, issued1/completed1; retire/close completed before PHASE
unloaded at02:36:16.990. No new plugin error in this interval. Thus first entry
plus ONE same-process reentry passed, not long-run/Reset/full-library acceptance.
Factory retention increased45->90, so this does not prove leak-free teardown.
No game files or runtime behavior changed. Log: system temp
sf6cc-save-completion-fix-20260916-022725/reentry-accepted.log.
Do not request another identical capture without a new question. Keep this
baseline; editor/config autoload/root tab and hot reload remain separate work.

Latest live result (2026-09-16 02:29, PID102992): first entry/exit with the
correlation fix passed. Save handoff captured1 ticket; FinishSave matched1 and
returned Success=2, advancing issued1/completed1. Release then retire/close ran
at02:29:50.696, followed by Runtime PHASE unloaded without a stop/error. This
confirms one successful retirement, not repeated reentry/Reset safety. Factory
wrappers are still retained by the diagnostic entry (allocations45); do not
describe all process memory as freed. No game code changed in this follow-up.
Log: system temp sf6cc-save-completion-fix-20260916-022725/captured-exit.log.
The requested same-process reentry is now complete; see the02:36 result above.

User also reports first-open menu defaults to Dynamic Recording, whereas their
unmodified-game comparison defaults to Basic Settings. Deployed Lua/C# search
found no explicit write selecting that top-level page. Session restores
SelectChildIndex on detach; full TrainingData baseline includes SelectIndex and
SelectChildIndex (confirmed by read-only MCP type metadata). Preserved selection
is a possible indirect cause, not verified. No default-menu change made; do not
dismiss the observation as normal vanilla behavior or a confirmed root cause.

Latest capture (2026-09-16 02:17, PID96632): the substituted baseline and saved
TrainingData item differ within one StartSaveDirectSlot invocation. That same
controller/container/item tuple persists through FinishSave Success=2. Thus
baseline-address equality is not the correct completion identity for this path.
Runtime/NativeSaveCompletion now correlate per-invocation tickets and acknowledge
only exact captured completions, including out-of-order saves.86 Runtime tests
pass, including six full save/retire/reentry simulations. The reproduction failed
before the fix with "successful correlated storage copy was not acknowledged".
At02:27 user confirmed game exit; process absence and full file hashes verified.
Deployed2 replacements (diagnostic entry/Runtime),1 addition (NativeSaveCompletion),
76 existing files unchanged and none removed. Temporary two-hook observer removed;
Runtime now owns the single save-start hook.27 related test files and9 diagnostic
entry checks pass in addition to the86 Runtime checks. No commit or package.
Deployment archive: system temp sf6cc-save-completion-fix-20260916-022725.
Runtime SHA256 E2BC7A57D6777F4931977448066BDF17BED0E0705312D91558CED02837F990BE;
completion module9D875CE2FB5C65582FF9AF4494D939745C14594AB555C1F67510B85CCB1C16C2;
entry BD6FB3F53907110D55B06C96AF1F542B5FBF5ED7EDB3C9A9AD01FBC231081D8A.
Existing native row invalidation/Reset crash is not fixed by this evidence.
That first entry/exit check is complete; see the02:29 result above.
Evidence: ignored exam/native-training-library/
SAVE_HANDOFF_20260916.md and system temp sf6cc-save-handoff-trace-20260916-021451.

Latest capture (2026-09-16 02:05, PID26916): SaveSaveData substitution issued1;
TRAINING_SAVE_DATA FinishSave returned Success=2 with List count1 but matches0.
Release followed and the entry retired with completed0. The completion arrived;
the exact baseline-identity comparison failed. Cloning versus original-data
handoff versus another identity mismatch remains unresolved. Do not treat a
successful unrelated/uncorrelated save as permission to release all sessions.
Captured log: system temp sf6cc-save-fence-trace-20260916-020240/captured-exit.log.

Previous deployment (2026-09-16 02:14, DIAGNOSIS ONLY): after verified game exit,
updated only diagnostic entry and Runtime;76 files unchanged, none added/removed.
Adds bounded optional scalar identities/type/bank size to existing trace and
two read-only save-start hooks in the ignored entry (at most8 invocations).
No change to paging, configuration, save substitution, release rules or cap.
78 Runtime simulations,27 related test files and9 entry scenarios pass.
Archive: system temp sf6cc-save-handoff-trace-20260916-021451.
Entry SHA256 437F61EE05D77E72B6F9AF77742E48B659BB1ACEB29CF9E62CCE2A7BFF8C0EF0;
Runtime SHA256 1CBAF7CA5A75D870F7FA4CD1C2AB9688D4B6F49D5577500B91F3EA6A980F8F60.
That entry/exit capture is complete; see the02:17 result above.
This is NOT a fix for the retained-session cap or native initialization crash.

Latest differentiated result (2026-09-16 01:52-01:56): user loaded the script
after startup; first view had blank/inert pager, later regular-menu and shortcut
training entries worked. Four active sessions logged retained factory counts
45/90/135/180. At01:55:48 the next entry was refused by MAX_RETAINED=4 with
"save task not released". This is the direct cause of the fifth missing pager,
not evidence that the R shortcut is broken or recording JSON is corrupt.
The later02:05 capture above demonstrates missing completion correlation.
At01:56:31 user Reset; next prepare at01:56:32 reproduced playback row1 refs2->0
during row2 creation, followed by0x146F25612 AV. Do not merge the cap refusal
and subsequent crash into one cause. Original first blank pager is unresolved.
Full latest log/dump/scripts/hashes: system temp sf6cc-five-entry-reset-20260916-015632.

Previous deployment (2026-09-16 02:02, TRACE NOT A FIX): process absence verified;
only diagnostic entry and NativeRecordingRuntime changed,76 files unchanged,
none added/removed. Existing save/release/finish callbacks optionally emit up
to48 scalar events with issued/completed/readers/phase and match refusal reason.
No new native hook, native write, forced cleanup or raised retention cap. Pager
remains the accepted child-route version.76 fake-SDK Runtime tests,27 related
test files and8 entry checks pass; native lifecycle safety is still unverified.
Deployment: system temp sf6cc-save-fence-trace-20260916-020240. Entry SHA256
C8644324218D84F370B4DA7F0AF5B97EA7FA67922AD56CF6BC51BD36F28090A7;
Runtime A43582EB30675049298983A2C15C84CD5AFE6A7FE512114BCDFF66EEAF6FBC69.
Its requested entry/exit capture is complete; see the02:05 result above.

Latest lifecycle failure (2026-09-16 01:36:54, PID116860): after the accepted
single-click repaint run, user exited and reentered training and crashed.
Runtime logged unloaded at01:36:44.602. New Menu.prepare then observed playback
page108 private row1 at0x2008B0C7EC0 dropping refs2->0 across row2 creation/retention,
before the second session attached. Native AV followed4ms later at0x146F25612.
Offline dump confirms null R9 read; the row's heap memory is absent, so neither
the releasing instruction nor prior-session corruption can be determined.
This reproduces the earlier initialization signature WITHOUT NativeLibraryTab,
config autoload or editor. They are not necessary to trigger this signature.
Fixed eight-row windows and factory-wrapper retention do not resolve ownership.
Reentry acceptance FAILED; first-session repaint acceptance is not withdrawn.
No runtime/deployment changes made. Evidence and exact deployed sources/hashes:
system temp sf6cc-reentry-crash-20260916-013654/FINDING.md.
Do not request unchanged repeated launches as a substitute for ownership evidence.

Latest acceptance (2026-09-16 01:33, PID116860): user completed the requested
page-switch operations and reports that a single click now refreshes. Deployed
Pager and RuntimeWithoutRoot entry hashes match the01:22 deployment. Runtime
reached active at01:32:52 with45 retained factory objects and passed180 updates.
First-click repaint is accepted for this run. Log retains two HookManager
Function reentrancy warnings; this is not a warning-free or startup-stability
claim. Root-tab integration and intermittent startup/teardown failures remain
separate unresolved issues. No further code/game changes or commit made for
this acceptance. Evidence: system temp sf6cc-child-spin-commit-20260916-012219/
single-click-accepted-game-log.txt. Earlier pending repaint checks below are
superseded by this user result.

Current finding (2026-09-16 01:14, PID32716): both captured clicks used a temporary
child-option ViewData, not the live pager ViewData. Focus and spinner row were1.
Live Index was1 then2, temporary Index was0, and Function argument low32 was1
(spinner row). owns_pager=false bypassed immediate commit on BOTH clicks; both
fell back to QUEUE. This establishes the missing route, not a first-focus fault.
Constructor inspection at0x146589F10 maps child to Data(+0x28) and pager to
ParentData(+0x20). Full log preserved under system temp
sf6cc-first-spin-trace-20260916-011048/completed-two-click-log.txt.

Candidate status: precise child-route validation added to production Pager only;
selected child, canonical pager, live ViewData, owner, Param and spinner row must
match the captured spin. Direct-row and delayed fallback paths remain. No new
hooks, forced refresh, native allocation, recording or configuration changes.
The captured-child regression failed before the fix and now passes;74 fake-SDK
Runtime cases,27 related Lua test files,8 diagnostic-entry checks and syntax pass.
Deployment (2026-09-16 01:22, REPAINT ACCEPTED at01:33): user closed game and process
absence was verified. Only Pager replaced;77 files unchanged, none added/removed.
Temporary trace removed from game; RuntimeWithoutRoot entry unchanged.
Pager SHA256: CFCC614518A47C2FA78379E8160F3B5C8F24A6DFC8BDA590A3C0A5287FD3621E.
Full hashes, prior log and exact scripts: system temp
sf6cc-child-spin-commit-20260916-012219. Next: cold start, recording page1->2->3->2
without leaving pager focus; inspect immediate slot labels, then repeat in playback.
Do not record, import or Reset during this initial repaint check.
Root-tab diagnosis and intermittent startup crashes remain unresolved.
Earlier dated investigation/deployment statements below are historical.

First-click follow-up: user confirms keyboard and mouse both fail on the first
page change. Do not attribute this to mouse focus. Read-only MCP after one
keyboard click on previously untouched Playback: Param._SecondarySpinIndex=1,
pager ViewData.Index=1/IsUpdate=true; first PLAY_SLOT has _SlotID=8 and its
ViewData.IsUpdate=true. Page2 data is present while visible repaint is missing.
Evidence: system temp sf6cc-native-spin-commit-20260916-005544/
keyboard-first-spin-static-state.json (PID85140). This does not identify which
Function/scope guard bypassed synchronous commit.

Trace deployment (2026-09-16 01:10, CAPTURE COMPLETED at01:14): user closed game; process
absence verified. ONLY game NativeRecordingPager.lua replaced;77 files unchanged,
none added/removed. Original entry remains RuntimeWithoutRoot. Trace Pager SHA256:
1684A972252D1E74785DB2D9FC8A8FF6D7A90872FA87C1FA04FB2F7FED3C1F6D.
Source/previous Pager/entry/test/final prior log/full hashes: system temp
sf6cc-first-spin-trace-20260916-011048.70 Runtime regressions, trace bounds,
unchanged hook count and syntax passed again. Completed operator step: cold start,
enter ordinary training, open recording page, select page number then press
right once (1->2), wait1s, right once (2->3), wait1s; do not move focus between
clicks, record, import or Reset. Capture SF6CC-FirstSpin PRE/CAPTURE/FUNCTION/
COMMIT/POST/QUEUE; first-click symptom is not expected to be fixed by logging.

NativeRecordingPagerFirstTrace.lua is
a copy of current Pager with bounded scalar logs inside existing callbacks.
No new hooks/native writes/refresh calls; at most8 spins and64 lines. The same70
Runtime regressions pass, hook-registration count matches base, and logging stops
at the bound. The temporary diagnostic remains deployed; the preceding production
source was3BB14E61EB830E93BDE0B6A9E7C27141C1672654ABFF5D7A70B41D56E1DAC07A.
Earlier mouse/keyboard clarification requests below are historical.

Latest live result (2026-09-16 00:59, PID85140): native-spin timing patch PARTIALLY
accepted only. Startup reached active45 and SURVIVED180; user1->2 did not refresh,
then2->3 and3->2 worked. First-click repaint remains BROKEN. Log has no new
expiry/exception marker. Evidence: system temp sf6cc-native-spin-commit-20260916-005544/
first-spin-partial-result.json and first-spin-partial-live-log.txt. The mocked
spin path covers a focused same-ViewData Function but has not captured the first
live callback identity/order. Distinguish initial focus setup from alternate
native callback routing before relaxing identity guards. Asked whether initial
input was mouse or keyboard/controller. No further code patch or deployment yet;
same running build should be retained pending that answer. Older acceptance
steps below are historical, not proof of a complete fix.

Latest menu evidence (2026-09-16, current RuntimeWithoutRoot build): user reports
page1->2 paints old slots; next click2->3 paints page2, etc. Moving focus refreshes
all eight rows. Read-only live MCP resolved SecondaryList.SelectionChanged.Method
to UpdateSecondaryList. Live machine-code inspection confirmed OnUpdateSpin
(0x143EA4310) calls UpdateSpinBox at0x143F86B70, which writes ViewData.Index at
0x143F86FBE before Function at0x143F8776B /0x143F87A70, immediately followed by
UpdateSecondaryList at0x143F87785 /0x143F87A86. These are build-local evidence,
not hardcoded runtime addresses. No method was invoked or hook installed by MCP.

Current deployment (2026-09-16 00:55, LIVE RESULT PENDING): after confirmed game
shutdown, ONLY NativeRecordingPager.lua changed;77 files unchanged, none added
or removed. RuntimeWithoutRoot entry remains0A0E0A301BC2EADFC8613C62440D591EE2DD9E497F82942CCD6E69051ACB10D1.
New Pager SHA256:3BB14E61EB830E93BDE0B6A9E7C27141C1672654ABFF5D7A70B41D56E1DAC07A.
Twenty-seven related test files,8 entry scenarios and syntax passed again.
Exact before/after Pager, unchanged entry, tests, final preceding log and full
hash manifest: system temp sf6cc-native-spin-commit-20260916-005544.
Next operator step: cold start ordinary training, wait10s without Reset, then
if startup is normal open recording settings and select page2 without moving
focus. Require immediate9..16, then page3 immediate17..24, then page2 immediate9..16.
Stop on crash/hang/error; this live timing change is not yet accepted.

NativeRecordingPager previously ignored Function
inside the spin scope and committed two updates after the native repaint. It now
commits only a correlated, owned native Function with matching live committed
Index before returning to the engine repaint. No array replacement/allocation,
forced refresh, new hooks or recording/config changes. Other command paths retain
deferred fallback. A new real-Runtime fixture first failed with wanted1/slot0;
after the fix, forward/backward record/play paths paint wanted*8. Foreign callback,
uncommitted argument and busy-operation guards have regressions.70 fake-SDK
runtime cases,27 related Lua test files,8 entry scenarios and syntax pass.
Mocks do not prove native thread/lifetime safety. Evidence and exact before/after
Pager: system temp sf6cc-native-spin-order-20260916-005335.
Game now runs the corrected Pager with the unchanged RuntimeWithoutRoot entry.
Startup/teardown crash root cause remains unresolved. Older operator steps below
are historical.

Latest live result (2026-09-16 00:44, PID48072): RuntimeWithoutRoot reached
PHASE active at00:44:22.827 with45 allocations; SURVIVED active runtime180 at
00:44:25.800. User idle10s normal. This is an actual mounted Runtime startup,
not merely private preparation. No NativeLibraryTab installation was logged.
Evidence: system temp sf6cc-runtime-without-root-20260916-004107/
runtime-without-root-result.json and runtime-without-root-passed-live-log.txt.
Only one startup passed: root-tab causality, repeated startup/teardown safety
and current menu interaction remain unverified.

Next operator step uses the SAME running build, no restart or Reset: open
recording settings, choose page2 and observe before moving focus. If unchanged,
move focus down once without confirming a recording; check all eight rows become
9..16. Do not add forced refresh or new hooks. Earlier pending-startup instructions
below are historical; deployed entry hash remains0A0E0A301BC2EADFC8613C62440D591EE2DD9E497F82942CCD6E69051ACB10D1.

Latest live result (2026-09-16 00:35, PID94416):18 dormant Runtime hooks installed
at00:34:43.635; real Session.prepare on thread118228 reached PREPARED45 at
00:35:25.492 and SURVIVED180 at00:35:28.483. Recorder/bank/menu remained unchanged.
User idle10s normal. Evidence: system temp
sf6cc-private-session-hooks-20260916-003346/hooks-session-result.json and
hooks-session-passed-live-log.txt. Active Runtime/attachment remains untested in
this sequence; this pass does not exclude intermittent faults.

Current deployment (2026-09-16 00:41, LIVE RESULT PENDING): after confirmed game
shutdown, only the standalone entry was replaced;77 other files unchanged,
none added/removed. All20 standalone Lua modules match development. Eight entry
harness scenarios and syntax passed again. Entry SHA256:
0A0E0A301BC2EADFC8613C62440D591EE2DD9E497F82942CCD6E69051ACB10D1.
Exact modules/entry/tests, final prior log and full hash manifest: system temp
sf6cc-runtime-without-root-20260916-004107. Next operator step: cold start into
ordinary training,10seconds idle, no menus/input/Reset. Require PHASE active
and SURVIVED active runtime180 under SF6CC-RuntimeWithoutRoot, not just no crash.
Unlike the prior private probes, this candidate can mount recording pages;
library root tab and configuration autoload remain disabled. Menu testing waits
until startup logs are verified.

This candidate, SF6CC_RuntimeWithoutRoot.lua, restores the
archived MountRetained runtime entry, omitting only NativeLibraryTab loading
(other differences are comments/log tag). It now ticks real Runtime and permits
bank/menu attachment, paging and production save/retirement guards. No shared
Library instance, config autoload, editor or library root tab. Eight entry harness
scenarios, syntax and27 related Lua test files pass. Mocks test real Runtime but
substitute Library.runtime_context; native safety is unverified.

Reason for this comparison: archived failure at2026-09-15 23:31 recorded root-tab
installation at23:31:49.639, menu-row expiry at23:31:50.145 and AV at23:31:50.149.
Menu/Pager/Runtime/Session source hashes match the four modules in that crash
archive. Root-tab loading was absent from all four passing private probes. This
temporal association is NOT a cause determination. Compared with the current
dormant probe, actual Runtime orchestration and attachment return together;
compared with the old failed entry, the root-tab import is the single functional
omission. Cold startup must pass before requesting menu/recording operations.
The previous dormant-hook entry
10DA9CBC9CC0DAB2E26FB13FC69CD0A55A8BF5FB358E115FE92120C4CC822855 is archived,
not currently deployed.
Older pending/live-step statements below are historical.

Latest live result (2026-09-16 00:29, PID121300): real Session.prepare completed
on thread100072, PREPARED at00:29:33.950 with45 allocations and SURVIVED180 at
00:29:36.940. Original recorder,80-slot bank and menu unchanged; user idle10s
normal. No UInt16 buffers were allocated in this run: empty-buffer filling was
not exercised. Evidence: system temp sf6cc-private-session-20260916-002632/
private-session-result.json and private-session-passed-live-log.txt. One pass
does not certify stability or exclude intermittent native lifetime loss.

Current deployment (2026-09-16 00:33, LIVE RESULT PENDING): after user clarified
the game was closed, confirmed process absent and no new crash report observed.
Replaced ONLY standalone entry;77 files unchanged, none added/removed. All20
standalone Lua modules match development. Thirteen probe scenarios and syntax
passed again. Entry SHA256:10DA9CBC9CC0DAB2E26FB13FC69CD0A55A8BF5FB358E115FE92120C4CC822855.
Exact entry, modules, tests, final preceding log and full deployment hashes:
system temp sf6cc-private-session-hooks-20260916-003346. Next operator step:
cold start ordinary training,10seconds idle, no menus/input/Reset. Require
HOOKS_INSTALLED, BEGIN, PREPARED and SURVIVED180 under SF6CC-PrivateSessionHooks;
no-crash alone does not establish execution. No pagination/library UI expected.

This comparison uses the same real private Session
probe, now registering production Runtime hooks at script startup. Runtime is
never ticked and never receives the private entry; callbacks remain without an
active session. No attachment, config IO, save replacement or cleanup. This tests
the hook-registration environment, not active-session hook behavior. Thirteen
probe scenarios, syntax and27 related Lua test files pass. Tests reject Runtime
tick/ui_tick/reset/reload, require actual hook registration, preserve save results
before/after preparation, and stop preparation on hook-install failure.
The previous no-hook entryF6FB0B15EE9ED1B1ED18182930C6FF0E6B3554459D875528776C7FC5E24F8197
is archived, not currently deployed. Older pending deployment/results below are historical.

Latest live result (2026-09-16 00:19, PID119988): the private recorder baseline,
two data duplicates and real Menu.prepare completed this one run. RECORDER
retained/after_init/after_copy all reported refs=1; PREPARED at00:19:38.859 with45
allocations; SURVIVED180 at00:19:41.851. Live recorder/bank/menu were unchanged.
User reported10seconds idle without crash. Evidence in system temp
sf6cc-menu-after-recorder-20260916-001805/recorder-menu-result.json and
recorder-menu-passed-live-log.txt. This is not a full-runtime stability result.

Current deployment (2026-09-16 00:26, LIVE RESULT PENDING): after confirmed game
shutdown, SF6CC_PrivateSessionOnly.lua replaced ONLY the standalone entry;77
other files unchanged, none added/removed. Twelve probe scenarios and syntax
passed again. Session/Menu/Pager/Context/TrainingSlotLayout hashes match development.
Entry SHA256:F6FB0B15EE9ED1B1ED18182930C6FF0E6B3554459D875528776C7FC5E24F8197.
Exact entry, five dependencies, tests, preceding final log and full hash manifest:
system temp sf6cc-private-session-20260916-002632. Next operator step: one cold
ordinary-training entry,10seconds idle, no menus/input/Reset. Require BEGIN,
PREPARED real Session and SURVIVED180 under SF6CC-PrivateSession. No pagination
or library UI is expected. No-crash alone does not establish that preparation ran.

This comparison directly calls
production Session.prepare on the observed80-bank branch, rather than reproducing
its sequence in an adapter. It includes working-bank retention, buffer validation
and filling empty PRIVATE copied buffers. No Runtime hooks, attachment, live bank
writes, config IO, save, disposal or retries. Twelve fake-SDK scenarios and syntax
pass; live-owner writes are forbidden in the harness, menu expiry is injected.
This isolates the remaining preparation-wrapper differences as a group, not one
native instruction. Other candidates remain runtime hooks and intermittent native
lifetime failure; prior passes exclude none conclusively. The preceding recorder
entry4415446CAB6EFF4086DBDF0561B46BC6FA87CC4B838787DA554452A76995FD22 is archived,
not currently deployed.
Earlier pending/live-step statements below are historical.

Latest live result (2026-09-16 00:10, PID97864): two TrainingData.Duplicate calls
plus real Menu.prepare PASSED this one run. Both copies completed at00:10:05;
PREPARED reported44 allocations, SURVIVED at00:10:08.831 after180 updates.
Original80-slot bank and menu arrays remained unchanged. User reported10seconds
idle without a crash. Evidence: system temp
sf6cc-menu-after-duplicate-20260916-000818/duplicate-menu-result.json and
duplicate-menu-passed-live-log.txt. This does not establish full-runtime safety.

Current deployment (2026-09-16 00:18, LIVE RESULT PENDING): after confirmed game
shutdown, the recorder comparison replaced ONLY the standalone entry;77 files
unchanged, none added/removed. Eighteen probe scenarios and syntax passed again;
NativeRecordingMenu, NativeRecordingPager and Context hashes match development.
Entry SHA256:4415446CAB6EFF4086DBDF0561B46BC6FA87CC4B838787DA554452A76995FD22.
Manifest, previous entry, candidate, tests and final prior log: system temp
sf6cc-menu-after-recorder-20260916-001805. Next operator step: cold start into
ordinary training,10seconds idle, no menu/input/Reset. Require RECORDER retained,
after_init, after_copy, both Duplicate pairs, PREPARED45 and SURVIVED180 in logs.
No pagination/library UI is expected from this unmounted diagnostic.

This comparison adds one private recorder
GameLocalData allocation, Init and DeepCopy before the same two data duplicates
and Menu.prepare. No initialization of the live recorder, bank writes, hooks,
attachment, save or release. Eighteen fake-SDK probe scenarios and syntax pass;
these check scope/failure handling, not native safety. Expected allocations:45.
The game now runs this recorder comparison. Older next-step/deployment statements
below are historical; no live result for this candidate has been collected yet.

Deployment record (2026-09-16 00:08, live result recorded above): user closed the game;
the menu-after-two-Duplicate diagnostic replaced ONLY the standalone entry.
77 other files unchanged, none added/removed. Fourteen probe checks and syntax
passed before deployment; no production modules, DLLs or configuration changed.
Entry SHA2561DD6D70E3BEAC867B6B3A0D87A91F0F1133FEF7BF75A725E6573D9FC3FA4D951;
source/previous entry/final preceding log/full hashes in system temp
sf6cc-menu-after-duplicate-20260916-000818. The two copies remain private;
no bank attachment, recording, save or cleanup. Next operator step: one cold
ordinary-training entry,10seconds idle, no menus/input/Reset. Check both
BEFORE/AFTER_DUPLICATE pairs and PREPARED/SURVIVED under SF6CC-MenuAfterDuplicate;
no crash alone is not acceptance. Pagination/library UI remains absent by design.
Earlier statements that this candidate was not deployed are now historical.

Latest live result (2026-09-16 00:04, PID106684): corrected MENU-ONLY comparison
PASSED this one run. BEGIN at00:04:32.994, PREPARED at00:04:33.002 (44 allocations),
SURVIVED after180 updates at00:04:35.994. Existing80-slot bank and original menu
arrays remained unchanged. User reported idle10seconds without a crash. Unlike
the preceding precondition failure, this actually ran real Menu.prepare. It does
not certify full-runtime startup/teardown or exclude intermittent menu faults.
Log/result are in sf6cc-private-menu-existing-bank-20260916-000052 in system temp.

Next comparison is PREPARED IN EXAM ONLY, NOT DEPLOYED: same private-menu probe
with two TrainingData.Duplicate calls and retention before Menu.prepare, matching
the baseline/working-data copies on the current existing80 branch. No recorder
GameLocalData initialization, slot expansion, hooks, live attachment, config IO,
save or teardown. Checks reject aliasing slots/inputs/buffers and expired copies;
14 fake-SDK harness scenarios pass, including copy failure, aliasing and loss of
the first copy while making the second. These do not reproduce native corruption.
The game still runs the passing menu-only entry (5A2B1B400F0D29923F1B018DB9FC35ED2D3DD4DBCAF3AA62B510E86DE7B7B2BF).
Wait for user shutdown before replacing the entry. Do not silently deploy the
modified exam source while the game is live. A pass would only accept the combined
private path in that run; a failure would implicate the added copy/retention
interaction, not establish which native writer or collector invalidated an object.

Current action (2026-09-16 00:00, user resumed local diagnosis): corrected
PRIVATE-MENU-ONLY entry DEPLOYED after user shutdown/process verification.
The probe now accepts the observed existing80 bank as well as8, preserves its
identity/count and all existing slot snapshots, and calls only real Menu.prepare.
No Session.prepare, recorder baseline, TrainingData.Duplicate, bank construction,
method hooks, attachment, save or manual release. Failure stops without retry.
Eleven harness cases pass, including the previously failing80 precondition,
slot80 mutation detection and injected page108/row1 expiry at row2 creation;
27 related Lua test files pass. These are mock contracts, not native safety.
Only autorun/SF6CC_TrainingLibrary.lua changed;77 files unchanged,none added/removed.
Entry SHA2565A2B1B400F0D29923F1B018DB9FC35ED2D3DD4DBCAF3AA62B510E86DE7B7B2BF;
source, previous entry, preceding log and whole-directory hashes are in system
temp sf6cc-private-menu-existing-bank-20260916-000052. No product-module edits,
config changes, DLL changes, commit or package in this deployment. One cold
training entry with10seconds idle/no menus/input/Reset is needed; original menu
only/no pagination is expected. Acceptance requires actual BEGIN/PREPARED and
SURVIVED markers (44 menu allocations), not merely no crash. One passing run
would not exclude intermittent menu faults or prove preceding data-copy cause.
Earlier pause/deployment instructions below are superseded by this paragraph.

User's clarified functional floor: MORE THAN8 recordings concurrently enabled,
individual weights and full enabled-pool access for random playback plus all
three reversal triggers, without manually rotating configurations. Merely
storing30 recordings and swapping8 at a time is REJECTED as an equivalent feature.
Capacity80 is negotiable (30/50 acceptable); this does not authorize truncation
of existing data. Native expansion and full-pool virtual scheduling remain
candidates, neither certified. Public WTT v3.0.1 ZIP was inspected without
installation: RSM still validates IDs1-8, and RecordingManagerTab is absent.
Public Reaction Drills reads8 states and restarts native playback; it does not
establish private virtual-slot scheduling. The newer guide names virtual9-30
but does not disclose full-pool random/reversal behavior. Source/author evidence
is needed to resolve that specific question; no repeated game probes requested.

Current direction after user feedback: PAUSE capacity/lifetime probe deployments;
review upstream's implementation path instead of insisting on80 native slots.
The 23:47 PID119208 no-crash report is NOT a Menu.prepare pass: the probe stopped
before construction on its eight-slot-bank assertion. Read-only MCP confirmed
P2/FighterData ID28 and existing RecordSlots length80. The exam-only correction
accepting existing8/80 banks passed11 harness cases but was NOT deployed and is
not the next requested test. Game still contains the stopped diagnostic entry.
No further startup/Reset/re-entry is requested. WTT public main c7c72b6 exposes
an eight-slot recorder; its newer document describes30 slots with virtual9-30
in a private module, not a published80-slot expansion. Library capacity, native
execution capacity and visible UI rows must be treated separately. The proposed
virtual-library direction has not been implemented or accepted as a reduction
of simultaneous random/reversal coverage. Research evidence and open tradeoffs:
exam/native-training-library/WTT_ROUTE_REVIEW_20260915.md (ignored research).

Current game diagnostic (2026-09-15 23:45, LIVE RESULT PENDING): ONLY the entry
is replaced by exam/native-training-library/SF6CC_PrivateMenuOnly.lua;77 other
files unchanged. No production module or configuration edits. This one-shot
probe calls real Menu.prepare for both fixed-window pages, omitting Session,
recorder baseline, TrainingData.Duplicate and recording-bank construction.
Its capacity80 adapter describes ONLY private page layout; the live bank must
remain8. It authorizes menu_prepare only, never attach/bind/dispose/save, installs
no method hooks and retains private allocations/failed lease without cleanup.
Original bank identity/slot fields and original page arrays are checked;44 menu
allocations are expected, followed by checks on callbacks1/180. Context changes
or failure stop without retry. Eight fake-SDK harness cases use real Menu.prepare,
including injected page108 row1 expiry at row2 creation; nine existing window
tests pass. Injection checks diagnostic behavior, NOT the native cause/safety.
One idle cold entry is needed; no menus, recording, import, Reset or re-entry.
Original8-slot menus/no custom pages are intentional. Failure would show this
menu-only path can reproduce without bank work; one success cannot exonerate
menu allocation or establish stability. Exact source/previous entry/full hashes:
system temp sf6cc-private-menu-only-20260915-234513; entry SHA256
8F52F6BCFFA99EA38710E64B09BD32D98E1ADE1DA4A36E80557AFAB480591B69.
The earlier retained entry is preserved for explicit restoration, not currently
active. Crash remains unresolved; no commit/package.

Latest live result (2026-09-15 23:31:50): fixed-window initialization CRASHED
before user menu input. The corrected PageFocusTrace compiled, installed its
hooks and logged ARMED/main-thread readiness, but no captured `seq=` events
or active-mount marker preceded the failure. Playback page108 private row1
became invalid while constructing row2: refs2 ->0, type unavailable, at
construction_slot_2:after_create. Four milliseconds later the engine raised
C0000005 at0x146f25612, reading address0 (R9=0), matching earlier initialization
crashes. Reducing private slot rows from144 to16 did NOT eliminate this failure.
This is a menu-object lifetime observation, not evidence of corrupt recordings.
Observer timing effects remain unexcluded; temporal adjacency is not causation.
The latest minidump omits memory at the expired row0x2008098DEC0 and exception
R15/RAX targets, so it cannot identify the invalidating writer or owner. The
reported expired row and R15 are different addresses; do not equate them.
Log, dump, exact modules, manifests and offline dump evidence are archived in
system temp sf6cc-fixed-window-crash-20260915-233150; dump SHA256 is
ED55F7CDED599EC5FE501A5B671AD0EAC4217BDB9CFC4D1E8F4690FBF539C8E5.
With the game absent, ONLY the temporary PageFocusTrace.cs observer was removed;
all remaining78 deployed files match their prior hashes. No behavioral patch,
configuration change, commit or package. Startup remains unsafe; automatic
redraw work is paused pending initialization evidence. Earlier next-step/start
instructions below are historical, not the current test request. A mock test
cannot reproduce or certify this native failure; another identical idle-start
test would not resolve the missing object-memory evidence.

Latest workspace state: fixed-window candidate (user approved after the
22:28 crash on 2026-09-15), TWO MODULES DEPLOYED 22:56 / LIVE ACCEPTANCE PENDING. Recording and playback
each reuse eight private menu rows in one stable native array, with ten page
bindings over the unchanged 80 recordings. Slot-row allocations fall from144
to16; pager option objects are separate and unchanged. Borrowed original rows
and footer positions are preserved. Deferred paging marks owned ViewData dirty,
with no explicit ViewUpdate/UpdateSecondaryList. Nine new fixed-window tests
cover identity, data/weight preservation, name binding, native command
passthrough and failure containment; the existing67 runtime,25 pager and18
mount cases remain. These are simulated contracts, NOT a crash reproducer or
evidence that the engine redraws dirty rows. Native allocation corruption and
startup/exit stability remain OPEN. After27 related test files passed again,
only NativeRecordingMenu.lua and NativeRecordingPager.lua were deployed while
the game was absent:2 changed,76 unchanged,none added/removed. Entry SHA256
74F6CE8ED93AD781C73F22788D243D5248157573EFF8785AE0155307FA00A09C remains the
retained-mount diagnostic with no config autoload/editor. DLLs and configurations
are unchanged. Exact previous/candidate modules and full hash manifest are in
system temp sf6cc-fixed-window-deploy-20260915-225637. No commit/package. The
first idle test passed by user report (PID88920, started23:07:32): runtime
active at23:08:19.294 with45 retained factory returns, then180 active updates
at23:08:22.267. No earlier menu-row-expiry or forced-refresh failure signature
appears in this capture; all78 deployed file hashes still match. Evidence is
first-idle-passed-live-log.txt in the deployment directory. This accepts only
one idle entry, not repeated-start or teardown stability. Next test: keep this
process, open Recording, select page2 and observe whether rows9-16 appear
without closing the menu or switching tabs. No recording/import/Reset yet.
Stop on failure; this is not a stable build.
Earlier dated experiment states below
are investigation history, not authorization to restart or deploy.

Fixed-window immediate refresh FAILED in the same PID88920 session: screenshot
shows pager2/10 with stale slots1-8 and frame counts. Read-only MCP resolved
current Param0x2001BF309F0; all eight ViewData.Data slot IDs were8..15 (native
zero-based), with RECORD_SLOT118. First/last row IsUpdate wereTrue. The user
then moved focus and confirmed ALL eight labels updated to9-16. ViewData
identities remained unchanged; both sampled IsUpdate flags still readTrue.
Thus binding worked, but setting IsUpdate alone did not produce immediate
redraw. Do not present this flag as a proven per-frame dirty queue. The current
SecondaryList.SelectionChanged delegate's get_Method/get_Target resolve to
UpdateSecondaryList on that same Param. This is read-only identification, not
permission to invoke a method previously associated with a native AV. No game
method was invoked for refresh and no fields were written by these MCP reads.
Evidence: page2-stale-mcp.json, page2-stale-user.png, page2-stale-live-log.txt
in the fixed-window deployment directory. Do not click a stale-labelled slot.

After the user closed the game, a separate bounded C# observer was deployed
at23:21:59: plugins/source/SF6CCPageFocusTrace.cs only; all78 existing files
unchanged. It records raw arguments, call ordering and C# thread identity for
OnUpdateSpin, UpdateCursol, UpdateSecondaryList and record/play row writers;
it never dereferences game objects, invokes game methods, writes args/returns,
or changes menu/configuration behavior. First training spin selects one Param
identity;192 events/30seconds bound the capture (10minute startup wait limit).
Logging drains in pre LateUpdateBehavior. Six stub-SDK checks passed; actual
plugin compilation and hook behavior await the next start. Source/manifest
and preceding final log: system temp sf6cc-page-focus-trace-20260915-232159.
Next user step: one cold start, open Recording, change page1->2, wait1second,
then move focus down one row without confirming. No recording/import/Reset.

Observer run PID119088 (started23:24:04) did NOT collect: compileCycle1 failed
with CS0118 at SF6CCPageFocusTrace.cs:88 because the game's generated namespace
`_` makes `out _` bind to a namespace instead of a discard. WebAPI loaded; the
observer did not. No callback order/thread conclusion may be drawn from the
user's completed actions. The offline stub fixture now includes namespace `_`,
reproduces the exact compiler error, then passes all6 checks after replacing
the discard with `out var discarded`. Workspace diagnostic-only correction;
deployment awaits game closure. Next startup must first confirm compile status
and ARMED/main-thread logs before requesting another page/focus action.
Evidence: compile-failure.json and compile-failed-run-log.txt in the observer
deployment temp directory. Recording runtime again reached active allocations45;
that is not evidence of the observer loading or of immediate refresh passing.

User subsequently closed the game. The one-line diagnostic fix is deployed:
one changed C# source,78 unchanged files,no additions/removals. Pager, menu,
entry,DLLs and configurations were not altered. Actual host compilation remains
unverified until next startup; request idle training entry only, then inspect
compile status and ARMED logs before requesting input. The matching deployment
manifest is under system temp sf6cc-page-focus-compile-fix-*.

WTT field-note candidate (2026-09-15, upstream c7c72b6, DEPLOYED, LIVE ACCEPTANCE FAILED): recording
and library page rebuilds queue input and wait two unblocked pre
LateUpdateBehavior ticks. Borrowed native parameters are re-resolved, not
retained for later invocation. Back, tab changes, closure and changed owners
cancel queued refreshes. Recording bank/menu lifecycle also runs on this intended
entry phase. Render callbacks enqueue clear/backup/restore instead of invoking
the backend directly. The configuration picker holds six files per page;
export and refresh live inside it. All three custom menu layouts assert a
13-row ceiling (currently at most 12 rows).

Deployed at 07:59 after the user closed the game: nine changed Lua files,
20 plugin Lua hashes verified, 17 configuration files unchanged. Isolated
dependency and entry tests passed against the game directory. No DLL, MCP,
legacy MOD, commit or package changes were made by this deployment.

Live failure at 08:01:46 after paging (process started 08:00:44):
`TrainingMenuFunc.ViewUpdate` reached `InitSpinBox -> UpdateSpinBox ->
UpdateSecondaryList -> TrainingManager.UpdateGuideMessage ->
UIWidgetCtrl_InputGuide.SetData -> UIPartsInputGuideList.Add` and raised
`c0000005`. REFramework caught the invoke exception; the game then remained
frozen while D3D re-hook watchdog messages repeated. A pure lock deadlock
has NOT been established. Post-failure read-only MCP inspection found the
current ViewData list size was two, consistent with interrupted rebuilding.
At the exception instruction the indirect call target was
`0xCCCCCCCCCCCCCCCC`; a subsequent raw read reproduced the dispatch pointer
chain, but does not identify the writer or prove an object-lifetime cause.
The plugin does not directly call InputGuideList.Add, so the identically
named upstream case is not sufficient to diagnose this failure. The upstream
native /EHa deadlock case is also not established here. Do not retry the
same candidate, lengthen the delay as a claimed fix, or recover by writing
to the guide widget's list. Two delayed ticks and mocked tests have NOT
validated this native rebuild contract. No corrective runtime change has
yet been made for this live failure. Logs, process metadata and raw MCP
evidence were retained outside Git in the temporary investigation directory
`sf6cc-pager-hang-20260915-080235`.

08:14 diagnostic deployment: only the game-directory NativeRecordingPager.lua
differs from workspace source. A temporary copy omits the explicit ViewUpdate
after the same deferred page-array assignment and logs
`[DEBUG-SF6CC-pager-natural-reopen]`. The user must close/reopen the pause menu
before using any recording row; stale rows immediately after the arrow are
expected in this experiment. This isolates forced live rebuilding from native
reopening with the same expanded data; neither outcome alone proves the root
cause. No new hooks, guide-list writes, delay changes or config changes.
The intervention checks passed 3/3 and the unchanged source pager tests 22/22;
neither simulates the native exception. Candidate, test and deployment manifest
are in temporary `sf6cc-pager-natural-reopen-20260915`. Exactly one of 68 game
REFramework files changed; three top-level configuration JSONs were untouched.
This is not a release or a fix and must be removed/replaced after the comparison.

Natural-reopen result (08:16, process 115904): user confirmed the unchanged
expanded data displays slots 9-16 after closing/reopening the menu, without
a hang. The pager still shows 1/10 (slots 1-8). The log records two selections
of page 2 at 08:16:10/22 with forced ViewUpdate disabled; no matching invoke
exception was found in this captured run. Read-only MCP found 13 ViewData
entries and the pager ViewData.Index was zero. Thus natural reconstruction
completed where the previous forced refresh stopped at two entries. This
narrows investigation to the forced rebuild path/context, but does not prove
absence of data/lifetime races or identify the native AV's root cause. Pager
initialization/selection synchronization is independently unresolved; capture
its construction-time getter context before choosing a hook fix. No additional
native calls, writes, reset or hot-reload were performed in this comparison.

08:25 diagnostic follow-up deployed after game closure: game-only pager now
adds bounded scalar observations in its existing focus/index/text/action hooks,
flushed in its existing UI tick (96-event cap). No new hooks, native writes or
forced ViewUpdate added. Exactly one file changed, 68 others unchanged. Temporary
candidate, three passing intervention tests and deployment hashes are under
`sf6cc-pager-init-observer-20260915`. Initialization capture is pending; workspace
runtime source has not adopted this observer. Remove it after investigation.

08:27 capture identified the pager initialization defect independently of the
native AV: event 30 has owned_parent=true, page_index=1, allowed=false and
GetFocusIndex passthrough returned=0 on reopening. Events 18-24 also show
layout_func=107 (the parent recording page) with allowed=true, but option
queries pass through as -1 because only the pager row was recognized. ParentData
was present in both cases. Workspace candidate now separates read-only rendering
permission (same active offline-training owner) from interactive permission
(menu-open additionally required); parent layouts resolve only their own pager.
During opening, option reads use SecondarySpinIndex and return the selected
page rather than treating availability probes as user input. No native refresh
call was added or changed by this fix. Regression first failed on the captured
initialization pattern, then passed: pager 25, runtime 60, mount 18, standalone
entry. This does not reproduce/fix the native AV. Prepared game candidate in
temporary `sf6cc-pager-init-fix-20260915` still omits forced ViewUpdate and removes
the observer; deploy that pager plus the workspace NativeRecordingMenu.lua and
NativeRecordingRuntime.lua only after closure. Deployed at 08:33:15 after
confirmed closure of process 79668: three Lua files changed, 67 others unchanged,
hashes verified in the temporary deployment manifest. Observer removed; forced
ViewUpdate remains off in the game-only pager. Live acceptance pending.
No commit or packaging.

Initialization candidate live acceptance (08:34, process 95464): user confirms
natural reopening now shows page 2/10 together with slots 9-16. The no-refresh
intervention remains active; instantaneous paging and the original native AV
are NOT accepted. Captured log is in `sf6cc-pager-init-fix-20260915`.
Next prepared comparison re-enables only the existing deferred ViewUpdate on
top of these corrected initialization queries. It does not substitute another
native method or increase delays. Source pager differs from the accepted
game-only diagnostic pager at exactly that call site. Enhanced fake refresh
now queries the owned parent layout's focus/option before returning; 25 pager
and 60 runtime tests pass, with native crash risk still unproven. Await game
closure before deploying. Deployed at 08:37:48 after confirmed closure: only
pager changed (SHA256 CE501559D8C2A22D6056F1087044D08E630ACE77450EB79ADD0D1CB16314AAA1),
70 other files unchanged. Game now matches workspace pager; the no-refresh
intervention and observer are removed. Immediate-refresh live test pending.

Immediate refresh FAILED at 08:40:57 (process115908). User saw no redraw but no
hang; log nevertheless caught c0000005 at the SAME RIP 0x145629AB1 inside
UIPartsInputGuideList.Add with RAX=0xCCCCCCCCCCCCCCCC, through ViewUpdate. The
ViewData list again had only two entries. Thus fixing page initialization did
not eliminate the native exception; lack of a hang is not safety acceptance.
Log preserved as failed-immediate-refresh-log.txt in the initialization-fix
temporary directory. After user closure, 08:43 recovery restored game pager
DD6EF8434643AE4D175DBEBA704B945363AA2F36C2102E5BF4C29EA02822152C, exactly one file
changed and 71 unchanged. Workspace still contains the rejected direct call:
DO NOT bulk deploy/package it. Do not retry direct refresh or blindly substitute
CreateViewData/UpdateSecondaryList; prior research records these risks too.

08:46 passive flow observer added while game closed; all72 existing files
unchanged. Game autorun/zzz_SF6CC_NativePagerFlowProbe.lua only observes native
CreateViewData, ViewUpdate and UpdateSecondaryList pre/post states. No native
writes, UI invocations or modified returns. Records scalar rows/indices/update
flags, caps64 events/7200 ticks/16 JSON writes; widget snapshots sampled every15
ticks. Source/tests/manifest in temporary sf6cc-pager-native-flow-20260915. Two
offline observer checks passed. This capture ended in the startup crash below;
the observer and its runtime JSON have now been archived and removed.

08:49:40 startup FAILED before a paging test: page107 expanded slot12 at
0x2007cb9a070 was valid at slot_assigned with refs=2, then failed at
after_slot_creation with refs=1688060279 (0x649dc177), type unavailable.
Four milliseconds later, c0000005 at 0x146f25612 dereferenced a null type
pointer during UpdateVM. This repeats the earlier staged-owner failure even
with forced pager ViewUpdate disabled; staging and deferred-refresh removal
are not startup fixes. The passive observer had no flushed relevant events,
but that does not exclude its hooks/timing as a contributing factor. After
game exit its script and JSON were removed, without changing configurations,
DLLs or the accepted no-refresh pager. Logs, dump and removed probe are in
temporary sf6cc-startup-crash-20260915-084940. Offline CDB confirms the fault
instruction but the minidump does not contain the damaged row/collector heap;
the first invalidating writer cannot be recovered from this dump. Do not
retry unchanged launches or attach a live debugger again without a new plan.

08:58 targeted construction diagnostic deployed after verifying game closure:
only NativeRecordingMenu.lua changed, 71 other files and the no-refresh pager
unchanged. The existing startup checks now inspect the last eight expanded
rows after creation/retention, staging, source-field reads, field writes and
slot assignment. The log names both the damaged row and the construction
slot/field boundary; whole-page checks still cover older rows. No new hooks,
native writers, periodic IO or retries. Additional reads can affect timing;
a passing launch cannot disprove a race, and a failing boundary does not by
itself identify a concurrently executing writer. Three injected failures
first reproduced the old after_slot_creation-only diagnostic, then confirmed
earlier refusal at create/read/write boundaries. Runtime63, mount18, pager25
and standalone entry tests pass; these are simulations, not native crash
reproductions. Manifest and previous module are in temporary
sf6cc-construction-boundary-20260915. One cold start into idle offline training
is needed; no paging, import or Reset. This is NOT a crash fix or release.

First diagnostic cold start (process121556, started08:59:56) completed normally
per user, without training operations. Captured log has no menu-lifetime failure
or caught invoke AV. Read-only MCP confirms fighter28 RecordSlots.Length=80,
the recording pager has10 options, both recording/playback pages have12 rows
with slots0-7 and both original footer actions, and the selector has3 children.
These checks confirm expansion mounted, rather than simply remaining unloaded.
Normal log and scalar/object-graph evidence are archived in the construction
diagnostic directory. One non-reproducing launch does not identify the corrupting
writer or certify startup stability; no runtime changes or hot reload were made.

Re-entry FAILED at09:07:23 in the SAME process121556 (uptime7m27s). The user's
latest crash report supersedes their preceding normal report for this re-entry,
not the separately captured first-entry success. The new diagnostic caught
page107 slot23 at0x200857c6960 losing refs2 ->0 between
construction_slot_31:before_create and after_create, before slot31 field copy
or staging. That interval includes factory/retention/checks, not solely the
allocator instruction. Five milliseconds later the same0x146f25612 UpdateVM
AV occurred. The captured count was now0, not the earlier GUID-like garbage;
therefore do not reduce every failure to a direct GUID write. Dump heap is
still absent. Log/dump/CDB output archived in temporary
sf6cc-reentry-crash-20260915-090748. No live debugger attachment or forced GUI
refresh was used. This narrows the boundary, not the releasing instruction.

Next single-variable diagnostic is game-only NativeRecordingMenu.lua in
temporary sf6cc-menu-gc-scope-20260915: automatic Lua collection is paused only
around the existing protected menu preparation, then restored on success or
Lua error, preserving an already-stopped caller state. The native collector,
allocators, references, capacity, fields, hooks and recordings are unchanged.
No forced collection is invoked. A bounded completion log records restoration.
Four offline state checks (red against the old source) and63 Runtime simulations
pass. This is not a native reproducer or production remedy: changed timing and
deferred finalization can merely postpone corruption. Verified game closed;
deployed only that module,72 other files unchanged, no-refresh pager retained.
Workspace still has the unsuppressed diagnostic menu and rejected active-refresh
pager, so DO NOT bulk deploy/package. Live scope comparison requires a new
process; no Reset or script toggle. Restore this temporary GC intervention after
comparison, and do not count one good launch as root-cause confirmation.

GC-scope comparison FAILED on re-entry at16:20:54.831: the same page107 slot23
lost refs2 ->0 at construction_slot_31:after_create, followed6ms later by
0x146f25612 AV. First entry16:20:25.479 logged prepare_ok=true. IMPORTANT:
BOTH preparations logged lua_gc_was_running=false. The proposed suppression
therefore made no collector-state change and is NOT evidence excluding Lua
finalization. Pinned REFramework0a07faa ScriptRunner.cpp confirms automatic
collection is stopped and explicit LUA_GCCOLLECT/STEP is run at EndRendering
under its execution mutex. collectgarbage("stop") does not gate that scheduler.
Do not claim this was a successful GC isolation experiment or disable the
framework's scheduler globally. Crash log/dump archived outside Git in
sf6cc-gc-scope-crash-20260915-162127; signature comparison against09:07 confirms
the same failing boundary, not the native writer.

After confirming game exit, the ineffective game-only GC scope was removed:
NativeRecordingMenu restored to BCE07BDF79BCFCF97245577C39CF24C78AC316931EB13D94BF10F4591F049938.
The game-only standalone entry is temporarily paused before ANY dependency
imports, hooks or native allocations so the next startup can inspect native
factory/copy metadata without executing the known failing expansion. Its exact
original entry, held copy, no-runtime-access test and deployment manifest are
under temporary sf6cc-native-factory-readonly-20260915. Workspace entry and
configuration/DLL/MCP files unchanged. Pagination and import/export are
intentionally unavailable during this hold. This is temporary investigation,
not a fix or release: restore the original entry explicitly before live feature
testing. Next operator action: one offline-training entry, no Reset/re-entry;
MCP inspection must remain read-only and must not invoke an unverified factory.

Read-only hold-session comparison completed: the native TrainingManager remains
the same instance across training exit/re-entry. On exit, read_field confirms
_tData, _tBeforeData, _UIData, _UIFunc and _ViewData are null, while IsLoaded
remains true (IsInit/IsSetuped false, GameMode/TrainingState NONE). Re-entry
provides different TrainingData, UIData, UIFunc, recording/playback page and
slot-row instances. The UIData resource path remains
Product/GUI/gm/ui11200/TrainingData_ES.user. Recording still has the native
12-row layout with eight slots and both footer options. Same manager or
resource path is not proof of child-object continuity. These reads do not
prove old objects were destroyed or establish a crash cause: Runtime.matches
already checks training-data identity and layout readiness checks page/array
identities. No dedicated TrainingMenuData factory/copy method was found in
exposed metadata; AddDynamicMenu takes an existing row and was NOT invoked.
The bare native-only boundary comparison is complete; do not repeat it as a
replacement for isolating expanded-row creation/retention/cleanup. Evidence
is in temporary sf6cc-native-factory-readonly-20260915/live-inspection.md.
Entry remains intentionally paused; no runtime/configuration changes made.

Borrowed-wrapper cleanup candidate (16:46, deployed; LIVE ACCEPTANCE PENDING):
the installed SDK deduplicates Lua add_ref for an already wrapped object;
release consumes the shared wrapper reference, not a distinct per-module
reference. Menu and Session each put the same borrowed manager/data/fighter
in their manual-release roots. A new production-path simulation first failed
when native Release cleared the engine's TrainingData reference while another
Lua consumer still retained the wrapper. Menu.close/Session.close consumed
that shared Lua reference. This is an ownership-contract defect, NOT proof of
the previously captured slot23/31 allocation-time crash or the cold-start AV.

Only borrowed objects were removed from manual-release lists: manager, live
training data, recorder/local state, fighter/original bank and original menu
pages/arrays remain strongly referenced by Lua closures/tables. Newly created
objects and their existing teardown remain unchanged. Two regressions cover
retirement and pre-attach discard; the native mount mock now accounts for
initial reference-field ownership just as its setter already does, without
dropping any cases. Runtime65, mount18, pager25 and nine other related test
files passed (12 executable files total). These are offline simulations.

After confirming game closure, only NativeRecordingMenu.lua and
NativeRecordingSession.lua were updated, and the exact pre-hold entry was
restored (SHA256 4D97F75B27B626994E1339ABDD7C01D4C46FC88332E985E6BF8A6781FDAAA0D1).
Whole game REFramework hash comparison: 3 files changed, 71 unchanged.
The hold is now OVER; native expansion runs again. No configuration/DLL/MCP
changes. Game pager still disables forced ViewUpdate and retains hash
DD6EF8434643AE4D175DBEBA704B945363AA2F36C2102E5BF4C29EA02822152C.
Deployment/source rollback copies are in temporary
sf6cc-borrowed-wrapper-fix-20260915-164613. Do not bulk deploy/package the
workspace pager. Next live test is ONE enabled-plugin cold entry followed by
ONE training re-entry, with no paging/import/Reset. Stop on the first failure;
do not claim crash stability from the offline fix or one successful run.

Borrowed-wrapper candidate FAILED live startup at16:48:30: first training entry,
before any user exit/re-entry, repeats page107 slot23 refs2 ->0 at
construction_slot_31:after_create (last=before_create, created_refs1).
Four milliseconds later the same c0000005 at0x146f25612 occurs in UpdateVM.
This refutes exit cleanup as a necessary trigger of this crash. The separate
borrowed-wrapper ownership correction remains, but must NOT be presented as
a fix for startup AV. NativeLibraryPilot installed at16:48:29.371, before
this construction failure. Log190014 bytes/dump1957919 bytes archived outside
Git in sf6cc-borrowed-wrapper-crash-20260915-165133. Process confirmed exited.

Next single-variable isolation DEPLOYED: only the game entry's require of
SF6CCTrainingLibrary/NativeMenu is replaced with a diagnostic log; recording
runtime, native editor, Panel, shared jobs, eighty-slot capacity, borrowed-ref
correction and no-forced-refresh pager are unchanged. There will be NO native
import/export tab during this experiment. This reduces an overlapping native
menu constructor path; it is not a product fix. One unchanged failure would
show NativeMenu is not necessary for that failure, while a single success
would not prove NativeMenu is the cause (allocation count/timing also change).
Exact-diff and isolated-entry simulation passed; verified1 game file changed,
73 unchanged, entry SHA256
C74277BD7B592FE15742731B9E10A14B3F1195ADAC0346536203FE2DFA0DF639.
Original/candidate/test/manifest are in temporary
sf6cc-native-library-isolation-20260915. Workspace entry unchanged. Next user
operation: one cold startup into idle ordinary training, no menu interaction,
exit/re-entry, import or Reset; report result. Do not request repeated launches
of this unchanged candidate after failure.

NativeMenu isolation FAILED at16:58:10 on first training entry. The isolation
log is present and NativeLibraryPilot is not loaded. Failure is now page107
slot40 refs2 ->0 at construction_slot_48:after_create, followed6ms later by
the same UpdateVM AV at0x146f25612. NativeMenu is therefore not necessary to
reproduce this failure; the different allocation index does not establish
which allocator, collector or writer is responsible. Log186629 bytes and
dump1958593 bytes are archived in temporary
sf6cc-native-library-isolation-crash-20260915-165934. No repeated launch of
that candidate is requested.

Previous isolated baseline: temporary PRIVATE ALLOCATION-ONLY probe, full training
library DISABLED. One-shot pre LateUpdateBehavior waits for three stable
offline-training checks, creates80 blank TrainingMenuData objects using the
same global factory/retain/private-array pattern, and checks array/last-eight
row lifetimes at separate create-return, retain and staging boundaries.
No requires, method hooks, recording-bank operations, configuration access,
field copies, live-menu attachments, refreshes or manual releases. Surviving
private wrappers stay rooted; failures never retry. Successful construction
is checked again on the next and180th subsequent callback. Neither success
nor failure alone proves the cause of the original full-runtime crash.
Six offline probe tests cover normal completion, four failure boundaries,
later-frame expiry, no retry and no allocations outside training. They are
mock checks, not native evidence. Probe replaces only game entry (1 changed,
73 unchanged), hash0097DE687D3FDC03EE4801D77B07B55D423BAE545D40916196FE97675B641B1B.
Files/test/previous entry/manifest: temporary sf6cc-native-allocation-only-20260915.
Workspace runtime/entry, configs, DLLs and MCP unchanged this round. No paging
or import/export UI is expected. Live result at17:05:29: all80 blank rows were
constructed; at17:05:32 they passed180 later callbacks. The user reported idle
training without opening menus and no crash. This is one minimal passing run,
not proof of full-runtime stability or exclusion of the SDK/allocator. Its log
is retained as passed-live-log.txt in the same temporary directory.

Previous isolated entry: field-copy-entry.lua from that
temporary directory. It preserves the80-row private allocation/holding/frame
checks and adds the production field-copy loop from the real recording-slot8
template, including native Guid/Int2 setters and private SlotID assignment.
No live menu writes, bank allocation, configuration, module imports or hooks
are added. Eight mocked checks pass, including scalar/struct-write lifetime
failures. This distinguishes field copying from blank allocation; if it passes,
prior bank allocation pressure and other runtime interactions remain open.
After the user closed the game, this candidate replaced only the isolated
entry: one changed file,73 unchanged, no removed files. Deployed SHA256 is
E045BFE849392A9672E73515332E949B0CAAEEB4800075A399EB3E69983C67EA;
field-copy-deployment.json records before/after hashes. All eight mocked
checks passed again. Full library remains disabled; no paging or import/export
UI is expected. Live result at17:17:25: all80 copied rows constructed; at17:17:28
they passed180 later callbacks. User confirmed idle training without menu use
or Reset and no crash. Log: field-copy-passed-live-log.txt. This one passing
run does not exclude intermittent field-copy faults or prove startup stability.

Previous isolated entry: prepare-only-entry.lua reuses
production Session.prepare (including recorder baseline, TrainingData duplicate,
private80-slot bank, both private menu pages and pager arrays). It never calls
attach, installs no method hooks, accesses no configs and does not save, retire
or release. The construction permission flag is used only for preparation;
no native save protection is asserted and nothing is mounted. Same safe update
and stable-layout gate; original bank/page arrays must remain identical. New
allocations and private bank/input/buffers are checked after preparation and
at1/180 later callbacks. Failed lease and allocations remain rooted, no retry.
Four entry-harness cases pass (completion, construction failure, expired object,
unexpected mounted bank);65 production runtime fake-SDK tests pass. These are
offline checks, not native crash proof. After user-confirmed shutdown and a
fresh process check, deployed only this entry:1 changed,73 unchanged,0 removed.
SHA256:2E746B1B8D3FA4911648BD4ACF26EE808CFF23BAA92C3FD157E1AAA277007D7F.
prepare-only-deployment.json records all before/after hashes. Four harness
cases passed again. Await one cold start into idle ordinary training for5seconds;
no menu, recording, import or Reset. No paging/import-export UI is expected.
Stop on crash; do not repeatedly launch the same failing candidate.

Private full preparation FAILED at17:34:55 on first idle training entry:
recording-bank construction reached menu preparation. Recording page107 slot29
changed from refs2/type-present to refs0/type-unavailable at slot37:after_create.
Four milliseconds later c0000005 at0x146f25612, matching prior startup failures.
No attach, method hooks, configuration loading, retirement or manual release
had run. Those operations are therefore not necessary for this reproduction;
blank/copied80-row passes still do not isolate which preceding operation is causal.
Log/dump/failed entry are retained in temporary sf6cc-prepare-only-crash-20260915-173455.

Previous isolated entry: prepare-global-recorder-entry.lua, one factory differential
against that failing probe. Only create_instance(GameLocalData) is redirected
to create_instance_global; native Session/Menu production modules unchanged.
This targets the remaining local factory in recorder-baseline construction,
whose SDK wrapper/promotion path differs from the global factory. Native data
Duplicate, record allocation, field copying, counts and timing gates unchanged.
Alternative causes remain preceding copy/allocation pressure and private-menu
construction differences from the minimal probe. No root cause claimed.
The routing harness failed before the redirect and passed its four cases after;
this validates routing/fail-closed behavior, NOT the native crash cause.
Process confirmed exited; deployed one entry,73 files unchanged,0 removed.
Manifest: prepare-global-recorder-deployment.json in allocation-only temp folder.
No configs, DLLs or product Lua modules edited. Await one cold idle-training run
for5seconds without menus or Reset; no paging/import-export UI expected.

Global-recorder differential PASSED at17:43:31: redirect marker occurred once,
Session.prepare completed80 private recording slots, both menu pages and193
tracked allocations; at17:43:34 all follow-up180 checks passed and live bank/menu
arrays were unchanged. User confirmed idle training with no crash. Log retained
as prepare-global-recorder-passed-live-log.txt. Compared with the17:34 failed
private prepare, this supports the GameLocalData factory change as a candidate;
one pass does not prove the exact native release mechanism or full stability.

Workspace candidate now makes that exact change in NativeRecordingSession:
idle_gdata uses create_instance_global instead of create_instance. No semantics,
configuration, paging or cleanup change this round. Two new runtime integration
checks enforce one global recorder-baseline creation and no local creation for
original bank sizes8 and80, without pretending to reproduce engine GC. The
first check failed on old production code, then both passed after the change.
Runtime suite67 cases passes; native mount18 cases passes; ten related Lua test
files also pass (12 files total). Full official corpus gate not run for this
isolated standalone factory candidate; all these tests remain fake-SDK evidence.
CURRENT GAME DEPLOYMENT: after user-confirmed shutdown and process verification,
restored the original full standalone entry (4D97F75B27B626994E1339ABDD7C01D4C46FC88332E985E6BF8A6781FDAAA0D1)
and copied ONLY NativeRecordingSession (CEABBD74C23AAC088ACC5C50B27D2390E4D3CC116243CF8A8828332C1D822BED).
Two files changed,72 unchanged,none removed; full-global-recorder-deployment.json
holds before/after hashes. No-forced-ViewUpdate game pager retained unchanged
(DD6EF8434643AE4D175DBEBA704B945363AA2F36C2102E5BF4C29EA02822152C).
No config, recording, DLL or MCP files changed. Full startup/actual menu mount
and lifecycle still require acceptance; immediate paging refresh remains open.
Next smoke: cold start into idle training5seconds, then open recording settings
to inspect paging and import/export tabs only; no paging/import/Reset yet.

First full-plugin startup/menu smoke is visually confirmed for the17:49:47
process: recording and playback show1/10 (slots1-8), original footers and saved
slot1 name; import/export body shows the selected Mai config and applied-import
status; reversal recording picker shows renamed slot1 and slots9-12. This is
evidence of actual mounting/UI availability, not just isolated construction.
Do not infer manual import, playback or paging acceptance from these images.
At inspection no prior menu-lifetime failure or access-violation signature was
present. One HookManager TrainingMenuFunc.Function reentry warning at17:50:49
remains recorded, without assigning it a crash cause. Framework startup errors
also remain; the log is not globally error-free. Five screenshots and log are
retained in temporary sf6cc-full-global-recorder-smoke-20260915.
No deployment/code changes for this observation. Next operator step: exit to
mode selection, re-enter ordinary training and inspect the same menu, without
Reset, paging or importing. Reentry and cold-start repeat reliability remain open.

The same process later HUNG while switching the record/play/import-export tabs
(user clarified this subtab row, not the main training categories). At17:53:18,
NativeMenu.flush_refresh's ViewUpdate raised c0000005 at0x145629ab1 with
RAX=0xCCCCCCCCCCCCCCCC, through UpdateSecondaryList/UpdateGuideMessage/input-guide
construction. NativeLibraryPilot reported body-update failure; subsequent frames
stopped rendering and D3D rehook attempts continued. This differs from the earlier
allocation-time0x146f25612/refcount-loss signature, and matches the previously
rejected forced-refresh address. Do not mark startup fix reverted or all lifecycle
tests passed. Noninvasive CDB thread capture finished and detached normally;
no wait-cycle proof or exact stale-request event sequence was established.
Evidence: temporary sf6cc-library-tab-hang-20260915-175318 (log, screenshot, threads).

Workspace-only NativeMenu candidate now cancels pending library refresh upon
the owned selector's normal0/1 Function input, before native navigation. Prior
code waited for the107/108 page callback; a simulated delayed page callback
reproduced the stale ViewUpdate. Cancellation does not consume native input,
and layout probes, GetOptionIndex queries and foreign selectors cannot cancel it.
The expanded regression failed on old code and passed after the change;42 native
menu checks and11 other related test files pass. Test coverage establishes this
cancellation defect, not causation of the exact live hang. Legitimate ViewUpdate
calls remain and their general safety is still unproven. Error guidance now asks
for full game restart rather than reentering an already faulted native UI.
After user-confirmed shutdown and process verification, deployed ONLY NativeMenu.lua
(SHA2560356AFFDB9BA173740581ED7361F94C2F0D11BB183E1E1A907D4BF2102955A4A).
One file changed,74 unchanged,none removed; selector-cancel-deployment.json in
the hang-evidence directory holds before/after hashes. All42 menu checks passed
again. Global-recorder fix and no-forced-pager-refresh module remain unchanged.
Await one cold-start subtab-switch smoke: record -> play -> import/export ->
play -> record, checking each body. No slot paging, config operation or Reset;
stop on hang/error. General ViewUpdate safety and reentry remain unaccepted.

Selector-cancellation candidate FAILED real acceptance at18:19:45. The user
could switch subtabs, close the menu and reopen it, but then could not navigate
main categories. This is not established as a keyboard binding issue: log again
shows NativeMenu ViewUpdate c0000005 at0x145629ab1, caught invoke exception/body
update failure, then repeated D3D rehook attempts. No new allocation-time refcount
signature was observed. The cancellation regression remains a valid independent
defect check, but it did not fix the real UI failure. Do not add another guessed
delay or call a different native refresh method without evidence.
Source review: WTT guide/lua/func/NativePauseMenu.lua hooks ViewUpdate for layout
context; it does not use the same explicit body-refresh invocation. A verified
replacement navigation path for our nested library pages is still needed.

CURRENT GAME CONTAINMENT ENTRY is sourced from temporary
sf6cc-library-reopen-failure-20260915-181945/contained-entry.lua. It removes only
the NativeMenu require from the full standalone entry. Recording Runtime/editor,
REFramework panel and lifecycle callbacks remain; no config data is changed.
This deliberately withdraws the native import/export tab and is NOT a functional
fix. The entry-contract harness passes (NativeMenu not loaded, other dependencies
and callbacks retained, repeat load idempotent). Real startup/navigation remain
to test. Live failed log/screenshot/original entry are preserved in that directory.
After user-confirmed shutdown and process verification, deployed only the entry:
1 changed file,75 unchanged,0 removed. SHA256 is
187EF401FF8746FECE1A041470A7ED96155984DA5700A1FA354DC27F5D950731;
containment-deployment.json records all before/after hashes. Entry harness passed
again. Source entry and all other game modules/configs/recordings remain unchanged.
Await cold-start main-category navigation, close/reopen, then navigation again;
native import/export tab must be absent by design. No slot paging/config edits or
Reset during this smoke. This contains a known call path, not a completed UI fix.

Containment smoke PASSED for process16500 starting18:26:45: user reports normal
main-category switching and close/reopen navigation. Log confirms the18:26:56
native-tab-disabled marker, no NativeLibraryPilot installation and no repeated
ViewUpdate exception or allocation-lifetime signature at inspection. Function
reentry warnings still occurred without the reported navigation failure, so
those warnings alone cannot identify its cause. Evidence is retained as
containment-passed-live-log.txt in the same temporary directory. This accepts
the tested containment workflow, not restored native-library functionality or
all lifecycle/recording operations. No source/runtime deployment this turn.
Reviewed WTT guide/lua/func/NativePauseMenu.lua: page()/install_tabs() append a
top-level page and leave navigation to the game, without explicit ViewUpdate.
User choice requested before relocating our library from recording subtab to
independent main tab. No new UI implementation or deployment pending that choice.

The user subsequently authorized trying the independent root tab. Source now
contains `NativeLibraryTab.lua` and the entry loads it instead of `NativeMenu`.
This candidate has only three information rows (selected configuration,
character, recording/reversal metadata); it does not restore native library
actions. Root type and navigation fields follow the existing native template,
with a correctly typed empty DynamicChildData list. Installation only occurs
in a closed-menu pre-LateUpdateBehavior callback. The ViewUpdate hook is an
observer; there is no direct native refresh call. Primitive hooks are scoped
to the owned layout and thread, and the existing eight native roots plus any
foreign roots remain unchanged. Stable private GUIDs permit closed-menu
adoption without deleting foreign dynamic pages. New allocations are retained
and bounded to four mounts per Lua state; native UI disposal/hot reset remains
unverified. No disk scanning, recording mutation, config writes, or new controls.
Ten fake-SDK checks and twelve related test files pass. These validate contracts,
not the native hang/crash outcome. The accepted game containment and its
no-forced-refresh pager remain deployed while awaiting user-confirmed shutdown;
the planned deployment is only the entry plus the new root-tab module.
Do not copy the workspace pager, which still contains the rejected forced
refresh candidate. No package, commit or push for this experiment.

After user-confirmed shutdown, the root-tab pilot was deployed at19:13:38.
Full game REFramework hash comparison:1 changed entry,1 added module,76
unchanged files,0 removed. Entry SHA256:
8E4CB252BB1F07CD1544E534BBAC3BA9E70C084B19A29185F9ED38F77D84A4CE;
NativeLibraryTab SHA256:
E0CE43A23DF0FB0CB6ADF76D41F45680DD08EDEF629570642001E172CAA86BB3.
The accepted containment entry and deployment.json are retained in the system
temporary directory sf6cc-library-root-tab-20260915-191338. Game entry-contract
simulation passes; live navigation is pending. Pager, Session, all recordings,
configuration files and DLLs remain unchanged. Cold-start and test only the
new read-only root tab, category switching, menu close/reopen and switching
again. Do not Reset or exercise import/recording during this isolation smoke.

ROOT-TAB COMBINED SMOKE FAILED at19:15:12.694. The log shows the root page
installed at19:15:11.922, followed at19:15:12.690 by the existing allocation
failure: recording page107, slot23 refs2 -> 0 immediately after creating slot31,
then access violation RIP0x146f25612 four milliseconds later. No explicit
ViewUpdate failure appears in this run. This reproduces the prior startup
signature despite the global GameLocalData factory candidate; that candidate
is not a complete initialization fix. The added root tab was mounted before
the recording runtime finished preparation. Temporal order does not establish
whether it affected the old failure through allocation pressure/order, whether
the old failure simply recurred, or whether another interaction is involved.
Root-tab navigation itself has not received live acceptance.

The game process was absent. Archived log, dump and exact failed entry/module
under system temp sf6cc-library-root-tab-crash-20260915-191512. Restored the
accepted containment entry (SHA187EF401FF8746FECE1A041470A7ED96155984DA5700A1FA354DC27F5D950731)
and removed only the added game NativeLibraryTab.lua; rollback.json verifies
1 changed,1 removed,76 unchanged. Source entry now also omits both native library
menus. Entry regression was first red with the root-tab require, then green
for source and game containment. This verifies withdrawal, not crash safety.
Recording modules, pager, DLLs and configurations are unchanged. The standalone
root-page candidate and its contract tests remain as inactive research source.
Do not request repeated combined startup trials or re-enable manual ViewUpdate.
The next differentiating experiment would run the read-only root page with
the native eight-slot bank, omitting all recording expansion/lifecycle hooks;
that experiment has not been deployed and cannot establish combined safety.

User authorized the next differential. CURRENT GAME ENTRY is now the temporary
root-only entry from system temp sf6cc-library-root-only-20260915/entry.lua,
SHA256 D33493B2D0779EE27DF243D73CDD458E926C48F9D4948354CC3EB4E623E42802.
It loads State and the unchanged NativeLibraryTab candidate only. Library/Records
definitions load transitively, but no recording Runtime/Session/Pager, editor,
panel, deferred job loop, automatic import or save/lifecycle hooks are installed.
The remembered-selection file may be read once; no catalog scan or file writes.
Native recording data is left entirely to the game; eight native slots and no
pagination are expected. The page may say no configuration because no catalog
is loaded. The root module SHA remains E0CE43A23DF0FB0CB6ADF76D41F45680DD08EDEF629570642001E172CAA86BB3.
After confirming the game process absent, deployment verified 1 changed entry,
1 added module,76 unchanged files,0 removed. Configurations and DLLs unchanged.
deployment.json and the containment entry are in the same temporary directory.
The entry isolation harness rejects the full containment entry (recording runtime
loaded) and passes both the temporary source and actual deployed entry: seven UI
hooks, two callbacks, no expansion/job owner/config writes, idempotent load.
Ten existing root-page contracts also pass. Live result remains pending; this
is neither a production entry nor evidence of combined root-tab/80-slot safety.
Repository entry remains containment. No commit, package or push.

ROOT-ONLY NAVIGATION SMOKE PASSED in process117596 (start19:30:46). Screenshot
root-tab-display.png confirms the native top-level library and all three rows;
the user then explicitly confirmed switching categories and closing/reopening
the menu followed by further switching works normally. The19:30:57.365 log
marker confirms expansion/lifecycle/pager/editor/automatic config loading are
disabled, and19:31:45.634 records root-tab installation. Archived
navigation-passed-live-log.txt shows no prior menu-row-expiry or ViewUpdate
failure signature at inspection. Function reentry warnings alone still do not
imply failure. This accepts the root-only display/navigation workflow, not
80-slot initialization, combined loading, reset or training reentry. Keep the
current game deployment unchanged. No new runtime changes, commit or package.

Next diagnostic after root-only acceptance: offline CDB examination of the
19:15 dump reconfirms UpdateVM's null object-info dereference at0x146f25612,
not a menu ViewUpdate call. The dump has no readable heap for the faulting
object; it cannot identify the first invalidating write. CDB analyzed only the
dump and exited, with no live attach. Output is offline-exception.txt beside
that archived dump. MCP was unavailable because the game process had exited;
no bridge configuration or DLL was changed.

CURRENT GAME ENTRY is the data-only differential from system temp
sf6cc-data-only-20260915/entry.lua, SHA256
AC349D775B23DDF6A63D578184951F2D8D44D6C95D0713E7C30A55118EF5C5A2.
The accepted read-only root module remains byte-identical. This entry calls
production Session.prepare for private recorder/save-baseline/80-slot data
construction, but temporarily intercepts Menu.prepare to OMIT expanded menu
construction entirely. That interception is restored after success or thrown
error. Its Lua-only sentinel is never sent to the engine or used for attach.
No recording Runtime/save/Release hooks, bank attachment, automatic import,
file writes, cleanup or retries. Successful private construction is followed
by180 engine frames and bounded liveness/source-identity checks; eight original
slots and original recording/playback page arrays must remain live and unchanged.
Native reference operations inherent in construction remain risky: this is a
differential, not a fix. Keep surviving private references until process exit;
no Reset, recording, import, mode exit or repeated trials during this capture.
After process-absent verification, only the entry changed,77 files unchanged,
0 added/removed. deployment.json and exact Session/Menu sources plus the prior
root-only entry are retained in the same temp directory. Five offline probe
sequence checks pass (success, returned/thrown failure, expiry, unexpected mount),
including hook-interception restoration and no retry; four related repo tests
also pass. The actual deployed entry passes that sequence harness. None of these
simulate the native collector or establish a cause. One cold-start idle training
capture was reported crash-free, but did NOT complete (see below). Source entry
stays containment; no commit or package.

DATA-ONLY FIRST CAPTURE: the user reported ten idle seconds without a crash.
At19:47:33.507 the probe reached the omitted Menu.prepare, then failed its own
hardcoded `original:get_size()==8` assertion before PREPARED/180-frame observation.
This is not a native crash or a successful differential. Read-only MCP confirmed
P2 FighterID28 and its live RecordSlots array length80. Eight visible native
menu rows do not establish an eight-element recording bank. The probe contains
no attachment and Session.prepare accepts8 or80; this run followed the existing
80-slot duplication path, not the fresh80-slot allocation path. The origin of
the pre-existing80 bank is not established by this capture.
Evidence is retained as idle-no-crash-assertion-failed-live-log.txt in the same
temp directory. A temp-only correction captures source identity/count before construction,
checks they remain unchanged, and labels new_slots_from_8 separately from
duplicate_existing_80. Its80-source test failed against the old probe and passes
after correction; seven sequence checks pass, including source-count mutation.
After the user closed the game and process absence was verified, this corrected
entry was deployed with SHA256
3069DFFCEA2CA32DA240CDF180A5B0066ADF6E4C3DD70FF97336086F4096EBCF.
This supersedes the previous game-entry hash above. Only the entry changed,
77 files unchanged,0 added/removed; deployment-source-count-correction.json
records both snapshots. Seven sequence checks also pass against the deployed
file. The final old-run log is original-probe-after-exit-log.txt. No production
module, config, recording or DLL changed. Corrected real-game capture is pending:
start training, remain idle ten seconds without opening menus or Reset.
Do not Reset retained experimental objects.

CORRECTED CAPTURE INTERRUPTED BEFORE TRAINING (Sep15,19:57): official
CrashReport/2026_0915_1957/CrashReport.txt explicitly reports
`Fatal D3D error (25, DXGI_ERROR_DEVICE_HUNG, 0x887a0006)`.
System events corroborate NVIDIA TDR: nvlddmkm153 at19:57:00 (twice),
Display4101 at19:57:02 says the display driver stopped responding and recovered.
The entry logged ARMED at19:57:00.702, but no SOURCE/BEGIN/PREPARED/SURVIVED
and no root-tab installed marker occurred. Thus this is not evidence of private
80-slot preparation failing. Lua module loading/hooks were present; this does
not exonerate all injected components or identify the initiating GPU fault.
Official dump exception record is0x146f279e0, context RIP0x146f27aef, with no
exception parameters; do not confuse context RIP with the first invalid read
or trust distant exported-symbol names as function identity. REFramework's own
crash dump remains the OLD19:15 file. The later D3D rehook loop is not, by itself,
the initiating cause. Driver versus rendering hooks versus hardware/background
load remains unresolved. No DLL, driver, setting or Lua was changed in response.
Official folder/ZIP, live log, exact entry, offline CDB analysis and System-event
XML are retained under system temp sf6cc-startup-crash-20260915-195658.
CDB used only the saved dump and exited; no live debugger attached. Game and
reporter processes subsequently absent.

CORRECTED DATA-ONLY CAPTURE PASSED on the next unchanged launch (PID81008,
started20:14:41). Root installed20:15:39.133; SOURCE at20:15:39.633 was
fighter28/count80/duplicate_existing_80. PREPARED20:15:39.640 and
SURVIVED20:15:42.632 confirm private duplication plus180 subsequent frames,
with live bank/menu identities unchanged. User independently reported normal
entry. Saved log: sf6cc-data-only-20260915/data-only-80-copy-passed-live-log.txt.
This accepts one80-source copy run, not fresh80 allocation, expanded menu
construction, attachment, Reset/exit cleanup or long-term stability. The earlier
GPU hang remains a separate observed failure, not a resolved driver diagnosis.
Next TEMP-ONLY candidate sf6cc-data-menu-only-20260915/entry.lua restores the
production Menu.prepare call while retaining the accepted root tab and every
other isolation boundary. It constructs detached recording/playback menu data,
never attaches, explicitly refreshes, imports, releases or retries. Nine offline
sequence checks pass, including changed page identity and an unexpectedly
attached menu. Native menu construction has previously crashed: this is not a fix.
After user-confirmed closure and process-absent checks, this entry was deployed:
SHA256 2FA4A35B46FC5D6A85240A1C1962383A4E3EC519EB23B983D07C1B4F3586DE19.
It is now the CURRENT GAME ENTRY, superseding the data-only entry above.
Only1 file changed,77 unchanged,0 added/removed. Root/Session/Menu/Pager hashes
were checked against the prior deployment, including the no-forced-refresh
game Pager (not the rejected workspace refresh candidate). deployment.json,
the accepted data-only entry, its final log and exact four module sources are
retained in the candidate temp directory. Nine offline sequence checks also pass
against the actual deployed file. Await one cold start into ordinary training,
ten seconds idle without menus, recording, import or Reset. No native stability
claim until the branch-labelled PREPARED/SURVIVED capture is read.

DATA+MENU DETACHED CAPTURE PASSED (PID123120, started20:20:07): SOURCE at
20:21:04.001 was fighter28/count80/duplicate_existing_80; PREPARED20:21:04.076
reported193 intercepted allocations, and SURVIVED20:21:07.075 passed180 later
updates with original bank/pages unchanged. User reported ten idle seconds
normal. Log retained as sf6cc-data-menu-only-20260915/
data-menu-only-80-copy-passed-live-log.txt. One successful run does not retire
the earlier intermittent construction crashes or prove attachment/teardown.
Next TEMP-ONLY candidate sf6cc-runtime-mount-only-20260915/entry.lua restores
the existing recording Runtime (including save/Release guards and its standard
pager/name/reversal hooks) plus accepted root tab. It supplies a no-job,
empty-name library facade: no shared config instance, autoload, editor, panel,
old NativeMenu or config actions. It uses existing runtime_context with its
dependencies preloaded. Runtime state ACTIVE for180 updates is an observation,
not proof of navigation, recording or playback. Unexpected tick exceptions
stop the candidate without invoking native cleanup; Reset uses production
outside-update abandonment. Three entry simulation scenarios passed, as did
67 workspace Runtime fake-SDK cases. The latter exercise the WORKSPACE pager,
including the rejected refresh candidate, and are not evidence for game pager
refresh behavior. Deployment must retain the game no-forced-refresh pager.
After user-confirmed game closure and process-absent checks, this mount-only
entry was deployed, SHA256
4DFFD2F8D0C251F4BA382092B6370423613B15B2E674D977FBC55E0FE48FCB74.
It is now the CURRENT GAME ENTRY. Only1 entry changed,77 files unchanged,
0 added/removed. All library-module hashes match the preceding deployment;
game Pager remains DD6EF8434643AE4D175DBEBA704B945363AA2F36C2102E5BF4C29EA02822152C.
The temp directory retains deployment.json, the accepted detached-menu entry,
its final log and five exact module sources. Three entry simulation scenarios
also passed against the deployed file. Await ordinary training startup and ten
seconds idle, no menu, recording or Reset; read ACTIVE/SURVIVED before asking
for navigation. Mounting is enabled but live validation is pending.

MOUNT-ONLY CAPTURE FAILED Sep15 at21:09:55.790, BEFORE attachment. Root tab
installed21:09:55.017; phase stayed unloaded. At21:09:55.785 Menu.prepare
reported page107 expanded slot23 lost refs2->0 while constructing slot31
(after_create; created_refs1). No ACTIVE or SURVIVED occurred. Offline CDB of
the new21:09 dump confirms RIP0x146f25612 reading invalid0x3000000001, with
the same UpdateVM entry hash ca20cfb12adf9af1 as prior allocation crashes.
This reproduces the earlier menu lifetime failure, not the19:57 D3D device-hung
signature. It does not prove mount/save/teardown caused the failure, because
prepare had not returned successfully. Raw DLL/module presence is not causation.
Dump, log, exact entry, all library modules and deployment manifest are retained
in system temp sf6cc-mount-crash-20260915-210955; offline debugger exited and no
live attach occurred. Three hypotheses remain: passive runtime hooks alter the
construction environment; Runtime's preparation call path differs; or prior
passes sampled an intermittent allocation/lifetime bug.

CURRENT GAME ENTRY now is sf6cc-detached-with-hooks-20260915/entry.lua,
SHA256 D1BE072FB3AB57D7FEA3C96499B577C1156F8FB41277ABE8A4E6F17A2B189A01.
After verifying game absence, only1 entry changed,77 files unchanged,0 added/
removed. This returns to accepted detached direct Session.prepare construction
but installs the same production runtime hooks with an empty config facade.
Runtime.tick/ui_tick/reset are NEVER called, so its entries/active stay empty:
no attachment, save redirection, menu refresh, teardown or retry. The existing
read-only root is unchanged. Relative to the accepted detached baseline this
adds passive hooks only; success/failure is not by itself a proven root cause.
Nine probe sequence simulations pass including actual deployed entry; game
modules including no-forced-refresh Pager remain unchanged. deployment.json
records the delta. Await a ten-second idle training capture without menu or Reset.

DETACHED WITH PASSIVE HOOKS CAPTURE PASSED (PID73904, start21:14:39):
hooks installed21:14:51.792; SOURCE fighter28/count80/duplicate_existing_80
at21:15:34.941; PREPARED21:15:35.014 with193 tracked allocations;
SURVIVED21:15:38.012 after180 updates with live bank/menu unchanged. User
reported normal idle entry. Log retained as sf6cc-detached-with-hooks-20260915/
detached-hooks-80-copy-passed-live-log.txt. This one pass does not rule out
intermittent hook effects. A confound is now explicit: detached probes retain
all native factory-return wrappers in state.allocations, while failed runtime
entries passed raw sdk. They also differ in context/preparation orchestration;
the previous contrasts do not isolate hooks or prove a lifetime fix.
Next TEMP-ONLY candidate sf6cc-mount-retained-20260915/entry.lua derives from
the failed mount-only entry and adds only the passing probes' factory wrapper
retention (create_instance/create_instance_global/create_managed_array), bounded
at2048 returns. It preserves native arguments/returns and delegates other SDK
members unchanged; no extra add_ref/release, GC changes or factory promotion.
Production runtime, context, save guards and no-job facade remain unchanged.
Three entry simulation scenarios pass, including factory forwarding and retained
wrapper identity. This is diagnostic lifetime extension until process exit,
not a production ownership policy or proof of native validity. No Reset or
training exit during the proposed capture. After user-confirmed closure and
process-absent checks, this retained-mount candidate is now DEPLOYED, current
entry SHA256 74F6CE8ED93AD781C73F22788D243D5248157573EFF8785AE0155307FA00A09C.
Only1 entry changed,77 files unchanged,0 added/removed. All library modules
match the previous manifest and game Pager remains the no-forced-refresh
baseline. deployment.json, prior accepted entry/final log, and five exact module
sources are retained in sf6cc-mount-retained-20260915. Three entry simulation
scenarios also passed against the actual deployed file. Await ordinary training
entry plus ten idle seconds without menus, recording, Reset or training exit;
read ACTIVE/SURVIVED before proceeding. No production lifetime fix is claimed.

RETAINED-MOUNT FIRST CAPTURE PASSED (PID49272, started21:35:37): root tab
installed21:39:04.544; runtime PHASE active at21:39:05.370 with193 retained
factory returns; SURVIVED at21:39:08.350 after180 active updates. User reported
normal ten-second idle entry. The deployed hash remains74F6CE8E...FA00A09C.
Log retained as sf6cc-mount-retained-20260915/
mount-retained-active-passed-live-log.txt. This is an actual attachment plus
idle-update pass, unlike the prior detached probes. It supports investigating
factory-wrapper lifetime/retention, but a single pass cannot distinguish that
from timing effects or establish the original invalidating operation. Retention
remains diagnostic, not an accepted production ownership strategy. Next use this
same process without Reset or redeployment: inspect native recording/playback
first-page pager and labels only, no page change or recording yet. Do not claim
navigation, playback, repeated startup or teardown has passed from this log.

RETAINED-MOUNT UI EVIDENCE: user screenshots show recording and playback both
at1/10 (slots1-8), original footer controls intact, native frame counts and empty
slots rendered. Reversal picker screenshot reaches slot12 with a scrollbar;
this proves more than eight visible/selectable-list entries are exposed, not
that every80 entry or actual reversal playback works. Images and current log
are retained in the same temp directory (record-page-one.png, play-page-one.png,
reversal-list-visible-twelve.png, first-page-display-live-log.txt). The log also
records page input selections10/1/2/.../1 at21:41:03-07, all forced_ViewUpdate=off.
These callbacks do not prove the visible rows refreshed. No new failure marker
was found in the scoped scan. No code redeployed. Next verify a single page2
selection followed by closing/reopening the pause menu, before using any slot:
expected2/10 and slots9-16 together. Immediate in-place refresh remains disabled.

User subsequently clarified that page input leaves visible slots1-8, then
confirmed closing/reopening the native pause menu displays the corresponding
page content. This accepts natural-reopen paging in the retained-mount run;
in-place refresh is still missing, not repaired. Evidence saved as
page-reopen-user-confirmed-live-log.txt in the same temp directory. Keep the
rejected explicit ViewUpdate path disabled. Next user step is a short slot9
recording and isolated playback after reopening each page, without Reset or
training exit; no new deployment required. Record/playback result is pending.

SLOT9 RECORD/PLAY ACCEPTED BY USER in this retained-mount run. User confirmed
both recording and playback normal after the prescribed page-reopen sequence.
Log saved as slot9-record-play-user-passed-live-log.txt. This is functional
evidence for an expanded slot, not instantaneous paging or lifecycle stability.
No code or game files changed. A read-only MCP get_type query for native Param
failed to return a schema; no setters/invocations or new probes were issued.
Existing Sep13 page_refresh capture documents native107/108 Function invoking
ViewUpdate internally on subtab changes. Direct UpdateSecondaryList was rejected
after a native AV, and explicit pager ViewUpdate remains rejected. Next manual
comparison: select a new recording page, switch to playback then back to recording
without closing pause; check whether page number and visible slots now agree.
This tests native navigation behavior, not permission to invoke the methods from
Lua. User has now confirmed recording page2->3, playback, then recording shows
page3 without closing pause. This accepts manual native subtab rebuilding in
the current retained-mount session, not automatic in-place refresh. Log saved as
subtab-roundtrip-user-passed-live-log.txt in the same temp directory. Entry,
diagnostic retention and all game modules remain unchanged. Next investigation
is the native navigation call context; do not simulate subtab switching or
reintroduce explicit ViewUpdate/UpdateSecondaryList from this observation alone.

After user-confirmed game closure, deployed TEMP-ONLY passive route observer from
sf6cc-native-refresh-route-20260915. Accepted retained-mount entry body is unchanged;
only an observer require is appended. Entry SHA256
F5F546EB54E130E0983DD90335F28605E0BFFFFE50EDEDDA8104A381C4C02DFA;
observer SHA256 935E3C0FAE54615F04B01E468357E15A4AFFDFE7AC3304FD8160252D62486FD7.
Manifest confirms one changed entry, one new module,77 unchanged files,no removals.
Function/ViewUpdate/OnChangedTab/CreateViewData hooks observe native calls only;
no native invocation, argument/return override, GUI write or retained object wrapper.
Capture stops at160 events or60 seconds after relevant Function input, with a
10-minute unarmed bound. Four offline checks cover passthrough, primitive-only
output, missing-ABI preflight and error/event bounds, not native safety. Pending
user page change plus playback/recording roundtrip; no Reset or recording needed.

PASSIVE ROUTE RUN FAILED before active mount (22:17:58.492). During creation
of page107 slot31, slot23 at0x20077822960 changed refs2->0/type unavailable.
Five milliseconds later AV0x146f25612 recurred. Offline dump confirms null r9
dereferenced by `mov rdx,[r9]`; crash pointer r15=0x20077822f10 is NOT the logged
slot23 pointer. The small dump contains neither object's heap bytes, so it cannot
identify the invalidating writer. Do not infer Reset Scripts from the preceding
D3D12 resize/device-reset log or call this the earlier DEVICE_HUNG incident.
No active-mount marker or page-selection marker; observer installed at22:17:11.969,
but no report completed. Retaining factory wrappers is therefore NOT a reliable
remedy; observer/timing contribution remains unisolated. Evidence and dump SHA256
8A926F80EF99DBC80819BB3DCDD93E272201A79D2E61DFF7852F9EAB3ED25A12 are in
system temp sf6cc-route-observer-crash-20260915-221758. Removed the exact observer
and restored its preceding entry; all78 files matched the pre-observer manifest.

NEXT DEPLOYMENT: failure-only Lua reference-ledger diagnostic, no new hooks.
Only game NativeRecordingMenu changed to SHA256
75929BA9639DB6A7A9D0C61F3DB56E5E2BC98DC0595DA78B9852DD7E65507175;
77 files unchanged. Source/rollback/manifest are in system temp
sf6cc-menu-reference-ledger-20260915. At existing lifetime checkpoints, read only
numeric entries from `_sol_lua_push_ref_counts`/`_sol_lua_push_ephemeral_counts`,
preserving previous/current values in a failure message. No ledger writes,
additional native calls, wrapper-cache reads, allocator/GC/ownership changes.
Pinned Sdk.cpp0a07faa matches this run's logged REFramework commit and documents
these tables. Three simulated diagnostic cases distinguish retained/removed/
unavailable ledgers;67 Runtime fake-SDK tests also pass with this diagnostic and
workspace dependencies (including workspace pager, NOT the deployed no-refresh
pager). Neither test set reproduces native lifetime corruption. A ledger still
present or missing is a boundary observation, not proof of the ultimate writer.
Await one entry only, no menus/Reset/re-entry; no crash-fix or stability claim.

LEDGER RUN FAILED (22:28:34.856): page107 slot23 expired at
construction_slot_31:after_create again. Native refs2->0 while the Lua ledger
remained1->1; ephemeral entries absent before/after. AV0x146f25612 followed5ms
later, without an active-mount marker. The separate route observer was absent.
This does not support ordinary disappearance of this Lua wrapper's tracked
reference at the observed boundary. It does NOT exclude native over-release,
memory corruption, SDK accounting defects or other object/GC interactions.
Slot23 is the first checked member of the recent-eight window, not proof that
it was the first corrupted allocation or that recording23 is faulty.
Evidence archived in system temp sf6cc-ledger-crash-20260915-222834; dump SHA256
F2F0F6463F1F153848922A39FA3D3B07831A553972A40885D41135FB7444A07E.
The three simulated ledger tests were diagnostic tests only, not a native fix.

After capture, removed only the temporary ledger additions by restoring the
exact preceding menu module (885BA57F7703939AC1ADE179DC5B45C6BF7FE15A65A2F19781298860831EB3BC).
All78 game files now match the pre-observer retained-mount deployment. This
rollback is NOT a stable build; native expansion still has the reproduced risk.
No further identical startup test requested. The user approved the next design:
keep80 recording-data entries but reuse eight presentation rows per native page
instead of allocating72 extra slot rows for each record/play page. It is now an
candidate implementation (see latest workspace state above), not a confirmed crash fix. It must preserve slot-index
binding, names, all-slot random weights/reversals, footer positions and lifecycle
ownership; cannot merely reduce recording capacity or mutate shared native rows
without restoration/ownership checks. The two-module deployment is complete; native acceptance remains pending.

Candidate Reset restriction: exit
training and allow normal teardown before resetting scripts. Reset outside
the safe update scope only stops Lua and abandons pending work: no task.cancel,
native menu restore, bank detach or RequestHide. Reset with mounted data or a
live dialog requires a full game restart. Retained references are intentionally
not explicitly released from the reset callback. This is a restriction, not
verified safe hot unloading or automatic recovery; a destroyed Lua state
cannot be assumed to run a queued teardown. Normal exit/re-entry remains.

Remaining WTT audit gaps: DYNAMIC dispatch still relies on owned object
identity instead of delegate ownership; stable menu GUID reuse, existing native
object lifetimes and dialog closing are not certified against the upstream
contracts. Data row creation is not GUI control creation. The upstream
OptionManager dialog recipe and C++ /EHa rule must not be blindly applied to
Lua UITextInputDialog. Absence of a Lua frame in a collector crash is not proof
of plugin innocence. Offline candidate tests do not prove the startup crash fixed.

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

Standalone clean deployment (2026-09-15): the fresh process logged a failure
at the original-eight baseline assertion before any expansion allocation.
A bounded read-only capture after Reset returned 80 from both array APIs in
all 15 samples (P2 fighter 28, idle, correct fighter index). The creation or
persistence source of that native bank is not established. The candidate now
validates and independently clones an entry bank of 8 or 80 slots, preserving
every existing recording, original array and same-sized save snapshot. It does
not truncate to 8, adopt the incoming array as its writable bank, or accept
unsupported counts, missing inputs or aliases. The prior incomplete-residual
bank refusal regression remains. Simulation covers ten-page mounting, slot80
content, save baseline and reset restoration; live acceptance is still pending.

The next cold boot passed that count guard but failed at slot 67: the newly
created SlotData lost its type and both references during Init (2 -> 0), while
the source remained valid. Native allocation lifetime is therefore still open.
The new manual "重新加载分页" panel action queues one owner-thread attempt,
never loops automatically or imports/saves a configuration. An active session
can reapply its own page arrays only; a failed start over a valid native 80-slot
bank can build a second TrainingData.Duplicate as its writable bank, validating
disjoint slots/inputs/buffers from both entry data and save baseline. Eight-slot
starts retain the existing allocator and its unresolved risk. Scene/busy guards,
foreign replacements and the four-retained-session limit still apply. Failure
injection covers the observed Init boundary, but does not prove its cause or
native whole-copy correctness; manual reload still needs live acceptance.

The user subsequently confirmed that Reset restored normal script operation
and clicking the manual reload button made pagination appear. This accepts
that observed recovery workflow only. A prior 05:10 attempt failed at
`menu array did not retain row`; its cause and intermittent automatic startup
remain unresolved. No additional object-factory or refcount-guard change was
made in response to that screenshot after the user reported success. This
acceptance does not certify all recordings, characters or cold-start lifetimes.

The next ScriptRunner disable/re-enable + Reset sequence ended in a crash after
repeated reload clicks. At 05:11:58 the log reported `recording header layout
changed`, followed about 11 ms later by native access violation `c0000005`.
The stack does not establish the responsible object or thread. The candidate
now reuses the native menu layout validator before any Session allocation,
add_ref or Duplicate. Invalid preflight blocks recovery immediately. One failed
manual attempt also latches recovery off for this Lua runtime; further clicks
do not read native recovery context, allocate, copy or log the same failure.
The four-entry retention cap remains secondary protection, not retry permission.
The latch is not claimed to survive Reset; users must restart the process after
the restart warning, not toggle scripts to bypass it. Simulations cover zero
allocations/copies for stale headers, 100 blocked clicks, mode re-entry after
failure, and successful manual recovery. Native crash elimination and arbitrary
script-toggle safety are NOT established. Existing standalone ZIP predates these
uncommitted safeguards.

Automatic recovery candidate (subsequent 2026-09-15 change): later logs showed
menu-row retention failure and System.Array.SetValue exceptions as well as
slot 53/58 losing references during Init. Startup now waits for three consecutive
idle, closed-menu, save-idle observations with the same native layout, at one
check per 15 UpdateBehavior calls. Invalid startup layouts only wait/read; a
manual forced attempt still uses Session's fail-closed preflight. Valid incoming
80-slot banks use the independent native Duplicate path immediately on automatic
startup; the repeated per-slot Init route is no longer their default. Original
8-slot expansion retains per-slot allocation and its unresolved native risk.
New menu rows, blank rows and pager options use create_instance_global; this
addresses the upstream local-promotion model but is not proof of the observed
native crash cause. Dead rows are rejected before SetValue; an expired slot
after Init cannot reach DeepCopy. When an active session's page arrays revert
to its own recorded originals, idle closed-menu updates restore the existing
windows without allocating, importing or resetting names. Healthy pages receive
no writes. Unknown replacements and native failures still stop recovery.
42 runtime simulation cases and 18 native-mount cases pass; real-game automatic
recovery and cold-start lifetime acceptance remain pending. Normal use no longer
requires the REFramework reload button. No configuration files or DLL changed.

Re-entry follow-up: user accepted normal first-session workflows, but exiting
on page ten and re-entering left blank pager text, inactive arrows and an empty
library tab. Hot reload then waited indefinitely for an original menu layout.
The log repeatedly reported `recording bank changed` from 05:35 onward; it
does not itself record whether Release preceded the first replacement. New
regressions reproduce blocked cleanup when native Release replaces RecordSlots.
Only a positively observed Release now permits detaching that obsolete claim
without writing to the replacement bank; owned menu windows can then restore.
Unreleased foreign-bank rejection is preserved. Successful retirement clears
the old attempt/block state; persistent retirement failure is reported once,
and pending native recorder state defers recovery rather than latching it off.
The library tab now checks training-data identity and Runtime's Release epoch,
and can restore an owned selector reused under a new native UI wrapper. These
changes cover 46 Runtime and 37 library-menu simulations, not live re-entry
acceptance. Unknown leftovers after a prior Lua reset still require cold start;
no heuristic takes over arbitrary dynamic native rows or reconstructs lost GUIDs.

Cold-start crash investigation (2026-09-15, still OPEN): disabling the MatchScout
proxy did not eliminate the native failure. With the former REFramework commit
`a0e9010` and the official nightly01422 commit `0a07faa`, the log reports an
expired menu row before array insertion, followed 4-5 ms later by access
violation at game offset `0x6f25612`. The newer stack has no hardread_core frame.
The nearest TDB symbol labels do not identify the actual failing function. The
separately reported earlier startup crash has no retained per-run log, so it
cannot be assigned this same cause. Neither DLL choice nor configuration data
is an established explanation; successful launches do not close this issue.

The next diagnostic candidate changes only NativeRecordingMenu at deployment.
Bounded startup observations cache row origin, page/slot/address, creation
refcount and the last successful stage before checking copied rows, pager
creation and window-array insertion. Failure logs use the temporary tag
`[DEBUG-SF6CC-menu-lifetime]`; there is no recurring diagnostic IO or new retry
loop. A known zero-reference object is not subsequently queried for its type or
inserted. Six injected-failure checks verify attribution/refusal through the real
Runtime/Session/Menu path (52 Runtime simulations total); they do not reproduce
native memory corruption or prove the cause of the crash. Native allocation,
retention and release policy is unchanged by this diagnostic. Remove the
temporary observations after the cause is established and covered. Live
attribution remains pending; do not distribute the old ZIP as a crash fix.

The next observed crash at 06:30:42 identifies an expanded recording-menu row:
page 107, slot 15, last stage `slot_assigned`, refs=1 at creation and assignment;
at `after_slot_creation`, type was unavailable and the refcount read was garbage
(`1688060279`). The row had not yet been inserted into any native menu array.
The same access violation followed 5 ms later. This locates the affected object
and interval, not the releasing/corrupting instruction. The candidate now
allocates one private staging array per page and inserts each new row immediately
before field copy and subsequent allocations, checking native retention. It
preserves this owner until the existing lease cleanup; no recorder buffer,
configuration or DLL is changed. A deduplicated-Lua-ref/reclamation model now
passes (53 Runtime simulations); it cannot certify the actual native lifetime.

User corrected the previous "normal" 06:26 launch: recording pagination worked,
but the import/export tab was absent. Do not count it as complete UI acceptance.
A separate simulated gap was found: a retained owned three-child array with its
selector reset to two-item layout bypassed recovery. Closed-menu checks now
restore only that known layout when the reachable selector and third child
still belong to this plugin. Unknown layouts/replaced children are untouched,
and visible menus are not rewritten. Thirty-eight presentation simulations pass;
the cause of the reported missing tab and the live recovery remain unconfirmed.

The immediate staged-owner retest FAILED at 06:36:26.500: recording page 107,
slot 12 was valid at `slot_assigned` with refs=2 (created refs=1), then lost its
type at `after_slot_creation` with the same invalid header value `1688060279`.
This disproves the sufficiency of the sole-Lua-reference explanation/staging
change. Do not claim the native staging array fixed startup, add more references
on this evidence, or treat the simulated reclamation model as the live cause.
The access violation followed 4 ms later at `0x146f25612`.

Offline examination of that dump and the matching installed binaries resolves
the REFramework return address `+0xb5555` to the original application-entry call,
not an ImGui function (export-nearest labels are misleading). The saved entry
name pointer `0x14bb2b4e0` resolves to `UpdateVM` in this game binary; its saved
hash is `0xca20cfb12adf9af1`. The faulting instruction dereferences the zero type
pointer loaded from the object in R15. This identifies the crash stage, not the
earlier invalidating write. The minidump lacks memory for the diagnostic slot-12
address, so the first invalidation cannot be reconstructed from it alone.
Logs, dump and deployed Lua sources are retained outside Git in the system-temp
directory `sf6cc-staged-menu-crash-20260915-063654`. No further runtime patch or
DLL/configuration change was deployed in response to this failed retest.

With user approval, a temporary native write-watch investigation is prepared.
The only additional deployed runtime change is a numeric row-address callback
plus a separate temporary autorun marker for recording rows 9, 12, 15 and 18;
configuration contents and native object construction are unchanged. Microsoft
CDB is kept in system temp, not the game directory. A separate fixture verified
hidden attachment, four hardware write watchpoints, the exact third-header
write, object-byte capture, breakpoint removal, debugger detach and target
resumption. Five focused Lua test files pass, including 54 runtime simulations
and 38 menu simulations; these do not reproduce or fix the native corruption.
Live attachment and capture remain pending. Start at the main menu and attach
before entering offline training. A captured write may be legitimate and must
be interpreted before assigning causality. Remove the temporary marker script,
generated marker JSON and callback after this investigation; none is a release
dependency. No configuration, DLL, commit or package was changed by this step.

The live CDB attachment at 07:08:14 failed before training or row markers:
the initial recorded event is process exit `0x3541caf0`, followed by
`No runnable debuggees` when the startup command file tries to continue.
All four hardware address registers are zero and no row marker was received.
The fallback dump is an exit-context artifact, NOT a first-write capture or
the earlier `0x146f25612` access violation. No matching Windows Application
1000/1001 crash event was found at inspection. An attachment-related exit is
suspected, but an anti-debug/protection cause is unproven. Do not repeatedly
attach or interpret the last sampled Windows message stack as the crash cause.
The temporary autorun marker and its optional callback were removed; only its
temporary test was retired (54 to 53 runtime tests), not a production regression.
Sources and logs remain in system temp `sf6cc-crash-tools/capture-20260915-070814`.
The original native lifetime defect remains unresolved.

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

The accepted minimal title-edit version was subsequently committed as `421c021`
at the user's request, before beginning the next feature. The new native-menu
candidate removes the separate import row and moves its two-confirmation action
to the file picker: first click selects and remains in the picker, second click
on the same file queues the existing import. Navigation, cancellation and stale
catalog checks clear confirmation, and layout callbacks cannot confirm a file.
The sole changed runtime file is NativeMenu.lua; no import, bank, pager or
title-edit backend is changed. Thirty-two fake-SDK menu checks pass, with live
two-click interaction and cold-start pagination still pending. The existing
Combo locals ceiling failure remains the only failing Lua test file (79/80).

The user subsequently confirmed the two-click switch feature works normally.
This accepts the reported menu workflow; no additional lifetime fix is implied.

The accepted switch was committed as `f7e0cfe`. The next candidate adds a native
clear-current-configuration row below refresh, routed through the shared idle
queue to the existing Records clear backend. It clears all allocated recording
slots, annotations and all three reversal groups, retaining the bank and saved
configuration files. Backend backup and failure behavior is unchanged: native
write failures are not transactional rollback, and ForceApply warnings remain
part of the result. Native clear, retained pagination and subsequent reimport
still require live acceptance; no allocation or lifecycle fix is claimed.

The active review procedures are [Human Review](review/HUMAN_REVIEW.md) and
[Real-game Smoke](testing/REAL_GAME_SMOKE.md). Do not close a limitation by
editing this file alone; close the underlying evidence or architecture gate
first.
