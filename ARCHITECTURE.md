# ARCHITECTURE.md

Language: [简体中文](ARCHITECTURE.zh-CN.md)

Status: `CURRENT`

## Operational Baseline

- Production action semantics: `Legacy`.
- M5 / `MoveResolver`: shadow-only diagnostics.
- Frozen Combo V2: unchanged.
- Legacy OFF: blocked.
- Human semantic review and real-game smoke: required.

The resolver graph below is the approved target architecture. It is not a
claim that production authority has already switched.

## Combo Recording Transition

Legacy ComboTrials recording is disabled by `ComboTrials/RecordingPolicy.lua`.
The entry script rejects starts before any recording state changes; UI, hotkey
registration and remote command dispatch no longer expose legacy recording.
The replay-only bottom recording bar is hidden. Existing training, demos,
saved combos, compilation and cancellation paths are retained; the standalone
training library's recordings are unaffected.

Moving recording into replay analysis is planned, not implemented. See the
[replay review UI design](docs/research/CFN_REPLAY_REVIEW_UI.md). This is a
product-entry change, not a change to action semantics or Frozen V2.

The isolated replay experiment under `tools/cfn_replay_capture` separates pure
damage/context analysis, filter/sort state, floating UI, same-round navigation,
and `round_navigation` orchestration. Its keyboard helper accepts a distinct
one-shot overlay-hide/restore request using the saved menu binding; ordinary replay
keys retain the UI-closed guard. No new game hook or production semantic route
is introduced. Native signed advantage remains raw contextual evidence, not
an automatically attributed player-relative punish verdict.
The separate `review_assessments` layer assigns review priority and validates
local player confirmations against replay identity and captured evidence. It
may add zero-received-damage confirmed opportunities without mutating the
damage ledger or teaching replay-specific frame numbers to the classifier.

The offline-verified user-rule candidate adds pure `rule_config` validation and
`rule_context` evaluation before human confirmations and statistics. Its bounded,
declarative JSON can relabel existing damage/guard events, not generate arbitrary
events, modify the damage ledger, bypass navigation guards or confer P0. Missing
evidence uses three-valued logic. The dependency-free offline editor derives its
field catalog from the Lua authority; it does not define a second action resolver.
Configuration is frozen once per evaluation. `rule_evaluation` rejudges a fixed
damage/guard fact snapshot without replaying sample rows or accumulating statistics
again; the raw capture remains persistent and the event snapshot is rebuilt once
on load. `workbench` exports scalar evidence and exact applied configuration for
the offline timeline/editor. Opt-in paused-only polling never acquires input or
new native hooks. The candidate is deployed locally; the latest configuration-only
filter change still needs live verification. `include_system=false` limits issue
lists and priority counts to enabled matching user rules without dropping facts.
The local stage checkpoint restores the system-default profile at user request.
See [user-rule contract](docs/research/CFN_REPLAY_USER_RULES.md).
See [timeline and live-rule workflow](docs/research/CFN_REPLAY_WORKBENCH.md).

Saved-data statistics are another pure consumer, not a second semantic resolver.
`statistics` computes observed distributions, resource timelines and coverage;
`statistics_charts` and `statistics_popups` render native ImGui views. Independent
1P, 2P and comparison windows reuse the project's hook-free `func/UIKit` palette
and controls, with the session-recap dual-curve presentation pattern. They do not
import `Training_SessionRecap` or `SharedHooks`, retain game objects, or acquire
input ownership when opened. Window scope is independent of the problem filter.
The old `statistics_window` remains an offline characterization reference; it is
not imported by the deployed entry or included in its package dependency closure. Chart
navigation reuses the identity-checked same-round controller. No move-specific
state inference, new hook, capture field, runtime dependency or skill score is
introduced. See [statistics definitions](docs/research/CFN_REPLAY_STATISTICS.md).

The experimental `guard_review` consumer independently records zero-damage guard
intervals and post-guard observations, reusing the existing state rules and recovery
candidate evidence. `guard_window` owns its display only. Unattributed native
advantage snapshots never become punish verdicts or damage-review seek targets.
Analysis teardown schedules a bounded, identity-scoped1x speed restoration through
the existing controls UI post-hook; it does not retain native objects, send keys,
add hooks or widen the normal playback-control permissions. The follow-up is
offline-verified and was explicitly authorized for Lua-only synchronization while
the game remained open; user-controlled Reset and live validation are still pending.

## Documentation

* [Standalone Training Library](docs/training-library/README.md): current entry,
  dependency boundary, native menu contracts and release packaging.

* [README](README.en.md)
* [Vision](VISION.md)
* [Roadmap](ROADMAP.md)
* **Architecture**
* [AI Development Guide](AGENTS.md)
* [AC+BCM Semantic Core](docs/AC_BCM_SEMANTIC_CORE.md)
* [Contributing](CONTRIBUTING.md)

---

# SF6CC Architecture

## Purpose

This document explains the architecture of SF6CC.

It describes why the project is structured this way and how new features should be integrated.

This document is intended for both human contributors and AI coding assistants.

---

# High Level Overview

The ecosystem consists of three independent layers:

```
Street Fighter 6
        │
        ▼
 REFramework
        │
        ▼
     SF6CC
        │
        ▼
     SF6CM
```

Each layer has a different responsibility.

---

# WTT Core

WTT provides the base training framework.

Examples include:

* Drawing
* Game hooks
* Basic UI
* Script loading

Whenever possible, improvements that benefit every user should remain compatible with WTT.

---

# SF6CC

SF6CC extends WTT with improvements designed for a better training experience.

Typical additions include:

* UI improvements
* Localization
* Better layouts
* Better fonts
* Better combo training
* Better user experience
* Community-oriented workflow

SF6CC should remain modular.

Avoid coupling unrelated systems.

---

# SF6CM

SF6CM is NOT part of this repository.

Responsibilities include:

* Combo sharing
* Community
* Metadata
* Ratings
* Search
* Downloads
* User content

Communication between SF6CC and SF6CM happens only through JSON.

No Lua code should directly depend on the website.

---

# Repository Layout

```
autorun/
    Lua entry scripts

autorun/func/
    Shared modules

data/
    Product data
    Config
    Combo database
    Exception database

fonts/
    UI fonts

images/
    Icons
    UI assets

plugins/
    REFramework plugins

docs/
    Documentation
```

---

# Architectural Layers

## 1. UI Layer

Responsible for:

* windows
* menus
* drawing
* interaction

UI should never contain gameplay logic.

---

## 2. Logic Layer

Responsible for:

* combo parsing
* training logic
* validation
* calculations

Logic should remain reusable.

---

## 3. Data Layer

Contains:

* Combo JSON
* Character data
* Exception rules
* Product default configuration

No runtime state belongs here.

---

## 4. Runtime Layer

Generated locally.

Examples:

* WebState
* WebBridge
* Replay Data
* LastFail
* sync_signal

Runtime files must never be committed.

---

# Config Philosophy

There are two kinds of Config.

## Product Config

Defines:

* default UI
* default colors
* default fonts
* default layout
* default enabled modules

These are version controlled.

---

## Runtime Config

Generated automatically.

Examples:

* window positions
* session state
* temporary cache

These should not be committed.

---

# Data Driven Design

Whenever possible:

Lua should describe behaviour.

JSON should describe content.

Avoid hardcoding character-specific logic.

Prefer configuration over branching.

---

# Modularity

Every module should have a single responsibility.

Examples:

TrainingComboTrials

↓

Only combo training.

DistanceViewer

↓

Only distance analysis.

TrainingHitConfirm

↓

Only hit confirm training.

Avoid hidden dependencies.

---

# Combo Action Data Architecture

Recording, detection, display, and audit may have different workflow responsibilities, but the approved target does not allow independent character-action semantics. The current production implementation remains Legacy while the AC+BCM graph and resolver run in shadow for comparison and review.

```text
Current-version AC + BCM
        │
        ▼
xt.character_move_graph.v1
        │
        ▼
Lua MoveResolver
   ┌────┼────┬────┐
   ▼    ▼    ▼    ▼
record detect display audit
```

AC owns the Action universe and structural relations. BCM owns actual input routes, profiles, trigger conditions, and resource conditions. OFF data may provide names or review material only.

Action IDs are not cross-version primary keys. The domain key is a Move; an Action is a current-version binding. Historical combo data is upgraded offline by comparing old and new AC+BCM graphs, not by keeping permanent runtime mappings.

Display overrides and exception tables must not become semantic authorities or conceal generator defects.

---

# Entry Script And Module Boundaries

`autorun/TrainingComboTrials_v1.0.lua` remains a large composition root and workflow container. Existing extraction work is frozen at the current safety baseline; future changes must preserve behavior and keep new business logic in modules. The long-term direction remains:

1. Freeze current behavior with characterization tests.
2. Move action compilation, detection, audit, and training-environment workflows into modules.
3. Replace scattered Action/command interpretation with `MoveResolver`.
4. Remove obsolete compatibility layers and character patches.
5. Leave the entry script responsible only for hooks, lifecycle, context, and orchestration.

New business logic must not continue to accumulate in the entry script. See [AC+BCM Semantic Core](docs/AC_BCM_SEMANTIC_CORE.md) for the data contract, exception boundary, and migration order.

---

# Upstream Compatibility

## Native Recording Library Import

SlotFrames candidate (cold-deployed September16 at15:48, live acceptance pending): slot-description labels include current P2
recording lengths, or the empty-slot label. Records.get_record_frames reads only
IsValid/Frame into a detached scalar snapshot; it does not export, read saved
configurations, touch input buffers or inspect reversals. Library delegates this
read, and NativeLibraryView captures it during the existing closed-menu update,
rejecting mismatched fighter/capacity data. Display/navigation read only the
snapshot. Missing or invalid reads remain unknown rather than empty; descriptions
and editing remain available. 36 related test files pass. Only Records, Library
and NativeLibraryView change; native pager and lifecycle code remain unchanged.
Deployment verified169 other files unchanged, with none added or removed.

ListPagerInit follow-up (cold-deployed September16 at15:29, user confirms paging works): ListPagerReversal failed its real list
paging check. Read-only MCP found the visible spin's SpinAction/CheckAdd/CheckSub
all null, default MaxNum99 and unchanged ViewData.Index0. Changing TEXT to SPIN
only displayed the widget; it did not initialize its native input delegates.
The earlier mock injected OnUpdateSpin directly and missed this prerequisite.
The new failing-before-fix regression requires initialization. Only NativeLibraryTab
changes: after owned row validation, variant/option/index binding, call the exact
InitSpinBox(Int32) overload for row9 (zero based) when entering SPIN or replacing
its option array. Block action dispatch during initialization; ordinary page
changes never reinitialize it. No whole-page refresh or added hooks. Single-row
initialization/input behavior has focused user acceptance for list paging.
Deployment updated NativeLibraryTab only;170 other files unchanged, none added
or removed. 35 related test files passed; this focused acceptance does not close
historical crash risks or establish all remaining reversal-name checks.

ListPagerReversal candidate (cold-deployed September16 at15:12, live acceptance pending): configuration and slot
lists retain their 13 owned rows, with row10 switching between text and a native
spin control. NativeLibraryPager adapts the existing NativeRecordingPager commit
protocol without modifying it; namespaced per-invocation storage isolates the
two consumers. Option nodes/arrays are prepared on closed-menu updates only,
bounded by the 256-configuration catalog (32 pages). Navigation selects a retained
option array, changes owned display variants and marks existing rows dirty before
native repaint; it never allocates a page or calls ViewUpdate. One-page lists
hide the spin control. Session/ownership checks and double-confirm import remain.
New screenshots show the accepted reversal overview was only correct where row
ordinal happened to equal the recording number. MCP confirms the three parent
functions134/135/136 and common row137/type8; Guard row1 references SkillIndex4.
The candidate resolves the recording name through the displayed parent group
and SkillIndex, while validating the native formatter against reversal SlotID+1.
35 related test files pass, including both pager hook registration orders and a
red-before-fix differing-index reversal regression. Cold-game rendering/interaction
is still pending. AutoLoad is the preceding accepted baseline. Deployment updated
three existing modules and added the adapter, leaving165 other files unchanged
and deleting none. No entry, recording bank, lifecycle, editor or configuration-data
changes in this candidate.

Current ReversalNames (cold-deployed September16 at14:34, user confirms overview display): SlotRename user smoke passed,
except reversal overview names. Existing native writer traces and current MCP
reads distinguish UpdateReversalItem from the already-covered recording picker.
NativeReversalRecordings now scopes name substitution to that native overview
update, resolves the current reversal group/row to valid RECORDING SkillIndex,
and validates its format argument before reusing the existing name source.
No GUI setters, retained controls, forced refresh, data writes or entry/pager
changes. Empty/ordinary moves retain native text; scopes cannot leak across
threads/nested updates. An overview read failure disables only its own labels.
Overview name display now has user acceptance; differing reversal/recording
indices and each reversal group were not separately reported.
The preceding deployed entry explicitly suppressed autoload from the earlier manual
reintegration stage. Fresh training sessions reset annotations; importing loads
names with their matching recordings. Default names before import are therefore
expected under that entry, not failed persistence. The user approved restoring
per-P2 automatic import. AutoLoad (cold-deployed September16 at14:47, user accepted) removes only the entry's no-op
autoload proxy, using the existing Runtime post-attachment call and shared job
queue. Both the canonical entry and staged native-root entry use the same queue;
deployment retains the staged root loader. No Runtime hooks/lifecycle changes.
No remembered match means no import/fallback; failed attempts are not retried per
frame. Manual page reload still does not autoload. 34 related test files pass,
including real-entry simulation of first load/reentry, safe gates and no retries.
The user reports all requested first-entry, training reentry and P2-switch checks
normal. This focused acceptance does not close historical intermittent crash risks.

Accepted SlotRename (cold-deployed September16 at14:19): user accepted ConfigRename, including
title display, native prefill and cancellation. The new slot browser reuses the
same 13 owned rows, eight slots per page, and delegates a global slot index to
the existing editor. Capacity and names are captured only on closed-menu updates;
message/navigation callbacks consume Lua snapshots. Context/capacity changes
invalidate the old list. Editing does not require a selected configuration and
does not save automatically: only Save/Save As persists runtime annotations.
No new native hooks, page arrays, runtime or recording pager changes. Slot-list
rendering and save/reimport passed user smoke; 34 related test files pass.

Accepted ConfigRename (cold-deployed September16 at14:01):
The root enables configuration-title editing, gated on a matching
selected P2 configuration and the existing editor's availability. NativeNoteEditor
captures pure dependencies at module load; its existing three hooks install once
during an active-runtime, closed-menu update. Installation failure disables only
the editor and is not retried. The native action delegates to editor.request,
returns the established close-menu result, and the existing editor waits for
actual pause closure before opening the input dialog. No entry/runtime/pager
or native string/delegate ownership changes are introduced. The existing title
transaction modifies only title at the same path, refreshes shared labels and
publishes the renamed configuration identity for a bounded native result message.
An already-ended dialog's queue notice is suppressed, not its commit outcome.
The subsequent SlotRename candidate only routes slot indices through this same
editor/queue contract; native string/delegate ownership remains unchanged.

Latest ConfigPolish candidate (cold-deployed September16 at13:47, live acceptance pending): ConfigLayout was accepted except
for retained LINE visuals inside the catalog. Read-only MCP found owned row
data Type0 while the same-index SwitchShow group retained focus4. The regression
now models those two separate states. During the existing owned Function scope,
preflight validates all ViewData owners and the two display groups' indices,
SwitchShow layout and variant bounds before changing only their displayed
variants with ChangeFocusIndex. No page cursor, forced ViewUpdate, new hook or
cached GUI handle is added; uncertain native mutation stops further module work.
Current divider positions are2/8 and all information rows use the same constant
color tag. Native behavior of this group synchronization remains unaccepted.

Library catalog labels now use Chinese brackets and stable, per-fighter
duplicate-title display numbering with collision avoidance. Paths and stored
titles are unchanged. Successful import/save/export expose a primitive
result_configuration (result revision, operation kind, captured display title)
for feedback; no new recording IO or job timing is introduced. Feedback never
substitutes the later current selection for this result identity. Native ticker
messages omit the library prefix and use save-as wording. Success captions may
include the result title within26 characters, preserving duplicate suffixes when
truncated; missing/invalid titles fall back to a generic caption, never a path.
Failure/partial-application classification and ticker ownership are unchanged.

The native recording library is a standalone, still-experimental plugin with
entry `autorun/SF6CC_TrainingLibrary.lua` and private modules under
`autorun/SF6CCTrainingLibrary/`. It does not require legacy SF6CC autoruns,
GameState/RuntimeSafety publishers, the menu registry, client, C# or custom fonts.
The accepted entry owns one pre-LateUpdate lifecycle/job/pager callback per Lua
state. Only its REFramework panel is enabled; native root/subtab/editor and
automatic imports remain disabled. Manual operations share `Library`; browsing
never imports. Factory wrapper retention remains diagnostic and bounded, not a
claim of leak-free ownership. `Records`, extracted
from the previous backend, owns file validation, backup, native slot
access and final import. `TrainingRecordImport` owns only the bounded, update-driven
empty-slot initialization lifecycle, using an adapter supplied by `Records`.
It does not own files, character semantics or menu rendering.

The September 15 native-UI containment disables the old `NativeMenu` subtab:
its explicit `ViewUpdate` call failed again after closing/reopening the menu.
The experimental `NativeLibraryTab` is not loaded by the canonical source entry.
Its first combined smoke reproduced the allocation-time crash in
recording menu preparation and was withdrawn. This
does not establish that the new tab caused the allocation failure.
The subsequent empty-root candidate was also withdrawn after two reported
entry crashes. The latest log records an expired recording-menu row before
Runtime became active, followed by native access violation; no successful
root installation was logged. The two deployed files were restored to0d27b37.
This is containment, not proof of root-tab causality or lifetime safety.
The revised source, cold-deployed as a game-only pilot at September16 04:23,
defers hook registration as well as mounting
until recording Runtime is active and the offline training menu is closed.
Loading the optional module must not touch the SDK; dormant hooks must not
read native arguments/owners. Partial setup failure stops without retry. These
are offline startup-isolation contracts, not proof of native lifetime safety.
The lifetime-guard candidate, cold-deployed on September16 at04:58, adds Runtime.presentation_session():
a scalar generation, valid only while the active recording session is neither
releasing nor released. The existing Release pre-hook invalidates it before
native teardown; successful attachment advances it. This does not change
state(), save completion, ownership or retirement timing. The root binds both
the Runtime instance and generation, rejecting new stale callbacks before SDK
access. A closed-menu update re-adopts reused native resources under the new
generation. Already-skipped calls still complete their post-hook return.
This guards a reproduced dispatch window, not the unknown native crash writer.
The user accepted one full character-switch/exit-reentry/paging/save smoke of
this candidate. The captured log confirms retirement after matched save
completion and root re-adoption; ownership/reentrancy warnings still remain.
The accepted pilot is a single-row root tab based on WTT's published root-page
installation. The blank-page entry/navigation/exit-reentry smoke passed in one
process. The September16 04:35 single-module follow-on turns that row into Save Current Configuration,
delegating to the existing Library request queue and native close-result protocol;
it does not own recording IO or add imports/selection/editor functionality.
The NativeFeedback stage, cold-deployed on September16 at05:21, keeps only the configuration identity in
the guide. NativeLibraryFeedback routes rejected requests and changed operation
status to NativeTicker, which uses WTT/SF6CC's TickerRequestData/RequestShowTicker
path rather than drawing text or requiring the old ScriptManager. User callbacks
enqueue plain Lua messages; only LateUpdateBehavior creates/submits requests.
The queue is bounded, owns only its request/text mappings, and never changes
native global visibility or manually invokes a UI refresh. Native pause-menu
ticker visibility remains an explicit live acceptance gate before further menu
operations are accepted. A subsequent user screenshot confirms the left ticker
with the pause menu closed; open-menu failure visibility remains unverified.
The presentation-only LibraryMessages adapter converts the shared diagnostic
status channel into fixed, concise user-facing Chinese. It never echoes paths,
user titles or exception strings. Partial application is distinguished from
success before success-prefix matching; unknown progress is not reported as
completion. Full source messages remain in the feedback log. This copy change
does not alter native request lifetime, operation results or menu construction.
NativeLibraryFeedback.request is the native action-row entry: accepted requests
return the game's close result and silently remember the queued status. The
existing Library closed-menu execution gate, not a feedback timer, determines
when the operation runs; only subsequent results are notified. Rejections remain
immediate. This distinction also applies to a slow native close animation.
For externally queued operations (the optional REFramework panel), close-menu
reminders are held in plain Lua until two allowed feedback updates
observe the pause menu still open through the existing Context.pause_open query.
Closed or unknown pause state never emits that instruction; native action
callbacks perform no pause query. Completion or closure discards only unsent
reminders, preserving submitted native ticker ownership and subsequent failures.
The user accepted the root stage with export, refresh and clear beside save.
The user also accepted backup, restore and reload for seven immutable
button rows. Backup/restore reuse Library's existing operation queue; reload
uses Runtime.request_reload and the same native close-result/feedback routing.
Busy/cancelled reloads have user-facing reasons distinct from restart-required
failures. No new recording IO, native close call or hook is introduced;
each row is inserted into its native array before the next row is allocated.
The newest request supersedes full-panel migration: backup/restore stay in
REFramework; import-option migration is paused. The ConfigList candidate, cold-deployed
on September16 at06:57 and awaiting live acceptance,
uses NativeLibraryView, a pure-Lua fixed13-row presentation model.
Its catalog snapshots labels and paths under the same Library revision, with
eight entries per page, previous/next, refresh and return. First confirmation
selects; a second confirmation of the same path queues the existing import.
Refresh, paging, return and observed menu closure disarm confirmation. Native
actions preflight all13 current ViewData owners before switching the body,
reuse installed rows and set IsUpdate for the game's normal redraw. No new
hooks, direct ViewUpdate calls, native array replacements during navigation,
or recording/backend changes are introduced. Closed-menu mounting loads the
shared catalog once if needed, without requiring the REFramework panel.
The user accepted ConfigList navigation and double confirmation. Rename rows
remain disabled pending the next editor stage. The ConfigLayout candidate, cold-deployed
on September16 at07:15 and awaiting live acceptance,
merges selection identity into the first row and removes native reload.
Owned rows5/8 switch between native LINE(4) on main and TEXT_ONLY(0) in the
catalog; row count, arrays, hooks and the normal dirty-update route are unchanged.
The info header uses a constant native color tag; no external title becomes markup.
Library.runtime_context supplies a primitive P2 snapshot on closed-menu updates.
NativeLibraryView filters with the existing TrainingConfigCompatibility policy
with mismatch rejection forced on, retaining source indices beside filtered paths.
Unknown/P1/other-character entries are hidden regardless of optional import
override. Character changes clear old view/confirmation state; an incompatible
shared selection has no displayed summary or native Save action. The underlying
REFramework catalog and recording/storage behavior remain unchanged. Layout,
separator type transitions, title color and filtering need live acceptance.
It inserts after the
native REVERSAL root while recording Runtime is active and the offline training
menu is closed, preserving all native/foreign roots; native
navigation owns rendering. Its layout hook only observes calls and scopes
primitive getters, never invokes a refresh. Plugin-private GUIDs identify its
own page across Lua states; no unowned DYNAMIC pages are removed. The current
candidate allocates its13 rows once per mount and reuses them during navigation.
New menu allocations are retained, with four mounts per Lua state as a research
limit; no native objects are released/restored from reset or stale scene
callbacks. This is not a validated native UI disposal/hot-reload contract.
Cold-start, category-switch and close/reopen smoke are required before adding
interactive controls. Existing recording/backend behavior is outside this change.
At checkpoint0d27b37 the canonical entry and all22 private Lua modules matched
the accepted manual-library game deployment byte for byte, with no root tab
loaded. The current two-file pilot differs only in entry and root module;
empty-root acceptance is recorded above. Save-row execution and native closure
passed user smoke, but a character-switch crash recurred at the prior UpdateVM
endpoint; deferred registration is not a demonstrated lifetime fix. Further
feature deployment is paused. See Known Limitations for the
remaining ownership-release warnings and acceptance boundaries.

An explicit import validates the whole configuration and backs up before starting
native recording. Only empty, unallocated slots are initialized. The final write
revalidates actual buffer capacities using the original in-memory configuration;
there is no second file read or replacement of the pre-import backup. Environment
changes cancel the task without touching stale native objects. Legacy synchronous
backend callers still reject unallocated slots; the two shared menus use the
deferred entry point. This does not change Combo V2, matching or replay semantics.

`TrainingSlotLayout` owns bounded configuration layout inspection (up to 200
entries per file group) separately from observed native import capacity (8
recordings, or 9 when actually mounted; 10 reversals per group). Metadata counts the complete bounded file.
Malformed/sparse arrays or unsupported native spans are rejected before backup
or native initialization; larger files are never silently truncated. These
bounds do not authorize additional native allocations.

The recording-bank draft in `tools/training_record_bank` is offline/research code
excluded from releases. It supplies stable local recording IDs, exact-content
merge, explicit edits and save/discard state, not game execution or persistence
integration. Native lifetime safety, native reversal adapters and UI integration
remain pending; see its README for the draft boundary.

The same offline draft now has a .NET `AtomicBankStore` backend for fixed
per-character bank files, bounded envelope validation, optimistic versions and
same-directory atomic publication under a cooperative writer lock. It has no
game/bridge dependency and is not deployed or packaged. Recording semantics
remain in the Lua bank model; runtime wiring must validate through that model
and turn storage failures into an unsaved state without blocking gameplay.

Offline bank draft2 adds bounded logical recording references. The Lua model
rejects dangling targets, blocks deletion while referenced, remaps IDs on merge
and rejects location conflicts atomically. Projection computes zero-based indices
for explicitly supplied capacities without touching game objects. This is not
complete reversal persistence or native Type/SkillIndex conversion; both remain
pending, and the game's ten-entry reversal execution limit remains in force.

`SF6CC_TrainingLibrary.lua` composes the fixed 80-slot runtime in autorun:
Session preparation has a distinct allocation-free transient outcome: a busy
native recorder returns `(nil, reason, nil, true)`. Runtime waits and repeats
the existing readiness checks without retaining a failed lease or latching the
context. This outcome is only valid before native allocation; initialization,
copy and menu failures retain their existing fail-closed/no-retry policy.
`NativeRecordingSession` owns independent recordings and an entry save baseline,
using `NativeRecordingSeed` for original-eight banks. A detached duplicate gets
an eighty-reference seed array; a second native Duplicate creates independent
slots, inputs and buffers. The seed is never mounted or saved. Full-bank alias
validation precedes clearing the added recordings and final attachment. Existing
eighty-slot banks retain the prior direct-duplicate path. The old per-slot Lua
Init constructor is preserved in a test-only fixture for six historical fault
checks, not chosen by the production bank path.
`NativeRecordingMenu` now owns one stable eight-row private window per recording/
playback page (two-module candidate deployed 2026-09-15 22:56; not live accepted). The
80-entry recording bank is unchanged. Each window clones the eight original
rows once, preserving the borrowed originals for retirement. It rebinds those
same private rows by page offset instead of allocating 72 additional slot rows
per page or selecting among ten native arrays. Native slot/footer positions are
preserved. The pager replaces the empty record
header; the playback start hint moves to the separator row. Short pages retain
non-focusable blank rows, so neither the slots nor footer move between pages.
`NativeRecordingPager` routes only owned spin-row/message identities. Within a
correlated native OnUpdateSpin -> Function scope, a verified committed ViewData.Index
rebinds the owned stable rows before the engine's following UpdateSecondaryList.
Owner, parameter, focused ViewData, pager, parent and argument must all agree;
the Function may carry either the live pager ViewData or a temporary child-option
ViewData. The child route requires its parent to be the captured pager, its data
to be the exact selected child, and its Int32 argument to identify the current
spinner row (whose live ViewData must match the capture), not the page value.
blocked, foreign or uncommitted callbacks cannot take this path. No new hook or
native refresh call is introduced. The00:55 direct-row-only correction failed
the first-click live test. The01:14 trace identified temporary child-option
callbacks on both clicks, rejected before synchronous commit despite valid focus.
The child-route correction passes74 Runtime simulations and27 related test files;
it was deployed2026-09-16 at01:22 as a Pager-only update. At01:33 the user
completed the requested checks and confirmed a single click now repaints.
This accepts the repaint fix, not startup/teardown safety or root-tab integration.
Other input paths queue a selection; two
unblocked UI update ticks later they re-resolve the live owner, parameter,
focus and page. The implementation rebinds existing private rows and
marks their owned `ViewData.IsUpdate` fields, including the pager. It never calls
`ViewUpdate` or `UpdateSecondaryList`; natural ViewUpdate calls are observed only.
Whether the engine consumes these dirty flags for immediate visible refresh is
NOT verified. Paging never swaps or filters the recording bank. Window arrays
are retained through the existing session lease; no per-click native allocation
is needed for rows/arrays. No borrowed UI wrapper is queued across ticks.
Native UI Function callbacks need not share the bank's UpdateBehavior thread.
The session grants a synchronous navigation scope only after validating the
current UI owner and owned pager/parent identities. This scope permits private
row binding and owned view dirty flags on that UI update thread only, is cleared even on errors, and
blocks retirement while active. Bank attach/detach/disposal retain their
original update-thread checks; UI navigation cannot authorize those operations.
The native SPIN control owns mouse arrows and left/right input. Read-only focus
and label hooks return the current page; option-index queries use the active
row layout or the current native focused ViewData, never a stale global row.
The group focus indexes the ViewData list; ViewData.Index is an option value,
not a list position. GetOptionIndex is a pure candidate lookup; it must not
authorize navigation because neighbouring availability queries can follow the
selected value. A validated synchronous Param.OnUpdateSpin scope reads the
same owned ViewData.Index after the native setter returns, then queues that
selection once. Failed partial binding disables every command in that window;
a failed deferred operation stops that controller without automatic retries.
Names resolve through the same current row-to-slot binding. No cached parameter
survives the callback.
Unscoped layout queries cannot select a page; Function is a guarded native-spin
commit point or queued confirmation path, not the sole source of spin changes. These paths have
simulation coverage. Earlier user acceptance of paging/recording/playback does
not certify this fixed-window candidate, current startup/teardown safety or
unrelated save boundaries. The game retains the pre-observer diagnostic entry
with only NativeRecordingMenu/NativeRecordingPager updated to the fixed-window
candidate. This two-file deployment does not establish the cause of the earlier
initialization crash. That entry still disables configuration autoload/editing;
startup acceptance must precede pagination and recording tests.
The 2026-09-15 23:31 live run failed this startup gate: playback private row1
expired during row2 creation, followed by the prior native AV signature.
Eight-row windows reduce allocations but do not establish safe ownership.
The temporary focus observer has been removed. The game entry is now a one-shot
the archived MountRetained Runtime diagnostic with NativeLibraryTab loading
omitted (deployed2026-09-16 at00:41; one mounted-runtime startup passed at00:44,
45 allocations and180 active updates). Menu interaction and repeated lifecycle
safety remain unverified; root-tab causality is not established. It now ticks Runtime
and permits recording-bank/page attachment with production save/retirement guards.
Configuration autoload and the root tab are disabled. The preceding private
Session.prepare with18 dormant hooks passed one run at00:35. It includes bank-rooting,
validation and private-buffer work, though no empty buffer needed filling in
the preceding no-hook run at00:29. The dormant-hook comparison did not tick Runtime
or assign it the private Session and therefore did not test active hook behavior.
Root-tab installation preceded the archived crash, but causality is unproven.
The preceding adapter path with private
recorder Init/DeepCopy, two data duplicates and real Menu.prepare passed one run
at00:19; the variant without recorder baseline passed one run at00:10.
Full-runtime safety remains unverified.
The optional Runtime trace callback receives at most48 scalar lifecycle/save
events, never native wrappers; trace failures cannot change save behavior.
It diagnoses unresolved save-completion correlation. The four-retained-session
cap is unchanged: the01:55 fifth-entry refusal reached this cap, whereas the
subsequent Reset triggered a separate initialization AV. Missing confirmation
must not authorize forced disposal or be labelled active IO without evidence.
At02:05 and02:17, FinishSave Success=2 did not match the baseline address. The
02:17 scoped trace identified one StartSaveDirectSlot call with a substituted
baseline and a distinct storage item. Controller/container/item identities
then remained identical through FinishSave. Native code reads confirm the
intermediate data transformation; full deep-copy semantics are not inferred.
`NativeSaveCompletion` now binds each substituted-save ticket to that synchronous
start invocation and its post-start storage identity. Finish captures the exact
binding before native cleanup, and Success acknowledges only those tickets.
Completed is an acknowledgement count, not a high-water generation: out-of-order
or duplicate callbacks cannot complete another save. Failed, replaced, foreign
or uncorrelated saves remain retained. Direct unscoped baseline returns require
exactly one pending ticket. Pending-ticket overflow above64 fails closed.
Optional bounded scalar trace reads remain protected and disabled by default.
The temporary two-hook observer is removed from the candidate entry; Runtime
alone owns StartSaveDirectSlot observation. Retirement still waits for all
tickets, zero readers and navigation quiescence on the existing update thread.
At02:29 the first live entry/exit matched one ticket, acknowledged Success=2,
and completed retire/close before Runtime reported unloaded. This validates one
actual completion path only. At02:36 one same-process reentry with user-verified
pagination also completed save/retire/close. Long-run and Reset safety, the
separate initialization crash and full-library reintegration remain unverified;
retained diagnostic factory wrappers increased45->90 across those two entries.
On2026-09-16 at01:36 the RuntimeWithoutRoot reentry failed during new playback
row2 construction: row1 refs2->0, followed by the same0x146F25612 AV. The root
tab is therefore not required for this initialization signature. First-session
repaint acceptance does not establish row lifetime or exit/reentry safety.
Both window modules are unchanged; the existing native bank
(8 or80) is preserved at its actual incoming count, not forced down to8.
The former retained entry is preserved for explicit restoration. Initialization
is unresolved; deployment, evidence and dump limitations are in Known Limitations.
`NativeRecordingRuntime` owns training-entry loading, hook notifications and
game-thread retirement. Existing TrainingLibrary imports/exports remain the
only configuration workflow. Last successful configuration is remembered per P2;
`Library` must load its Context dependency at module initialization, independent
of whether an editor or native menu is enabled. First-time deferred require is
not valid under REFramework's autorun search-path lifetime. The manual-only
entry exposed this missing dependency; context failure blocked operations and
mounting. Runtime-context tests must exercise the real loader boundary rather
than replace the context function with a permanently ready stub.
exit discards unsaved recordings without a JSON save. Native training autosaves
during expansion receive the entry training baseline, not current temporary
changes; explicit library export is required to preserve the user's setup.

The expanded capacity is centralized in TrainingSlotLayout (80 recordings,
ten eight-row pages). Session allocation initializes independent 3600-frame
buffers for slots9-80; import/export admits larger spans only when the matching
native bank is mounted. Reversal capacity and native save isolation are unchanged.
NativeRecordingNamePage supplies bounded native subpages under the existing
Import/Export menu. TrainingLibrary serializes slot-name edits with other library
operations and reuses NativeNoteEditor for the existing native input dialog.
Names edit current annotations without IO and persist only on explicit export,
using existing annotations.record_slots[].text and slots[].name fields. Entry
and retirement clear transient annotations; import restores the chosen config.
NativeRecordingNames substitutes only an owned live slot label's source string
on hGUI's normal text writer, following the accepted C# display experiment.
It retains no dereferenceable GUI pointers across callbacks, validates current
row/parent/label identity, and does not force widget updates. The standalone
plugin has no fixed-position ImGui annotation layer. Legacy files are unchanged;
disable the old DynamicRecords autorun when using this replacement to avoid two
independent recording/configuration writers. No deletion
or slot renumbering is implemented. The user confirmed paging and recording/
playback on the 80-slot build. The initially unresponsive rename entry now opens
the native input dialog; the user confirmed text entry, correct renaming and
subsequent playback. No rename fix was applied between those reports, so the
earlier intermittent symptom has no proven cause. The user subsequently accepted
the corrected right arrow, slot display and one Reset retaining expansion. Independent per-row rename buttons are
not implemented; exported/imported name persistence remains to be verified live.

Reset recovery remains limited: the 2026-09-14 21:01 log shows an unowned
replacement RecordSlots array rejected during retirement, after menu restoration.
The new Lua session then rejects the remaining 80-slot array as a non-eight-slot
baseline. Session retirement now checks bank identity before restoring menu rows;
it does not adopt unknown arrays or discard recordings. The replacement source
is not yet proven. Such a residual session requires a full game restart, not
repeated script resets; the 8-row UI alone does not prove the bank has 8 slots.

TrainingLibrary's explicit `save` request updates the selected configuration via
the standalone Records snapshot collector, including all recordings and
the three reversal groups. TrainingConfigNotes shares its verified backup,
concurrent-change checks and restore path with snapshot updates (16 MiB bound).
File identity, title, description and unknown top-level metadata are preserved;
runtime fields are replaced, schema unchanged. This is not crash-atomic storage.
Both native pilot and ImGui enqueue it; no file IO runs inside native UI hooks.
NativeReversalRecordings scopes InitList's original eight-item count substitution
to the current recording-reversal Param, scroll control and owned 80-slot bank,
during native InitScrollList only. Native scrolling, confirmation and execution
remain unchanged; the three groups still have ten reversal entries each.
The user accepted the reversal recording picker. Live save failed its roundtrip
guard because REFramework serializes empty Lua tables as null and decodes null
as nil. Comparison now permits that equivalence only for slots[].input_buff
when both frame and input_num are zero, only during snapshot updates. Nonempty
buffers, metadata, annotations and other fields remain strictly compared.
The backend regression models the engine codec, rather than a codec preserving
empty containers. Corrected save awaits live acceptance.

On 2026-09-14 the user confirmed recording and playback in the Lua ninth slot.
The subsequent paged UI and restored layout were also accepted that day. This
does not certify the save/release lifecycle or retire the earlier intermittent
row-copy failure.
The observed save/getter/release callbacks use worker threads, distinct from
UpdateBehavior. They return only the prepared baseline or record notifications;
they do not allocate or restore native fields. Pending snapshots require a
TRAINING_SAVE_DATA controller containing the exact baseline and FinishSave
Success, correlated to the captured save generation, before releasing owned
references. Native completion behavior remains an acceptance risk, not a proven
consequence of mocked tests. At most four unconfirmed sessions are retained;
new mounts stop at this bound. Busy script reset requires cold restart rather
than speculative reclamation. The old C# capacity probes remain excluded.

Whenever practical:

Improvements should remain mergeable into WTT.

Large architectural changes should be documented before implementation.

Compatibility is preferred over unnecessary divergence.

---

# Long-Term Vision

```
          WTT
           │
           ▼
         SF6CC
           │
           ▼
         SF6CM
```

WTT provides the core framework.

SF6CC provides a better user experience.

SF6CM provides the community ecosystem.

Each project should remain independent while sharing common data formats.

This architecture enables long-term maintenance, collaboration, and future expansion.
