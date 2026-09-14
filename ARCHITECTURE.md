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

## Documentation

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

The native recording library is a standalone, still-experimental plugin with
entry `autorun/SF6CC_TrainingLibrary.lua` and private modules under
`autorun/SF6CCTrainingLibrary/`. It does not require legacy SF6CC autoruns,
GameState/RuntimeSafety publishers, the menu registry, client, C# or custom fonts.
The entry owns one deferred job queue per Lua state. Its native menu and own
REFramework panel share `Library`; browsing never imports. `Records`, extracted
from the previous backend, owns file validation, backup, native slot
access and final import. `TrainingRecordImport` owns only the bounded, update-driven
empty-slot initialization lifecycle, using an adapter supplied by `Records`.
It does not own files, character semantics or menu rendering.

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
`NativeRecordingSession` owns independent recordings and an entry save baseline,
`NativeRecordingMenu` owns prebuilt eight-row recording/playback windows and
preserves native slot/footer row positions. The pager replaces the empty record
header; the playback start hint moves to the separator row. Short pages retain
non-focusable blank rows, so neither the slots nor footer move between pages.
`NativeRecordingPager` routes only owned spin-row/message identities and rebuilds
the visible body only inside native input navigation, with recursive layout
calls suppressed. Paging never swaps or filters the recording bank. Page arrays
are retained through the existing session lease; no per-click native allocation
is needed for rows/arrays, and no cached UI parameter is rebuilt on a timer.
Native UI Function callbacks need not share the bank's UpdateBehavior thread.
The session grants a synchronous navigation scope only after validating the
current UI owner and owned pager/parent identities. This scope permits page
array changes on that callback thread only, is cleared even on errors, and
blocks retirement while active. Bank attach/detach/disposal retain their
original update-thread checks; UI navigation cannot authorize those operations.
The native SPIN control owns mouse arrows and left/right input. Read-only focus
and label hooks return the current page; option-index queries use the active
row layout or the current native focused ViewData, never a stale global row.
The group focus indexes the ViewData list; ViewData.Index is an option value,
not a list position. GetOptionIndex is a pure candidate lookup; it must not
authorize navigation because neighbouring availability queries can follow the
selected value. A validated synchronous Param.OnUpdateSpin scope reads the
same owned ViewData.Index after the native setter returns, then commits and
refreshes that page once. No cached parameter survives the callback.
Unscoped layout queries cannot select a page; Function remains a guarded
confirmation path, not the sole source of spin changes. These paths have
simulation coverage. On 2026-09-14 the user accepted the updated live pagination,
layout, recording and playback; this does not certify unrelated save boundaries.
`NativeRecordingRuntime` owns training-entry loading, hook notifications and
game-thread retirement. Existing TrainingLibrary imports/exports remain the
only configuration workflow. Last successful configuration is remembered per P2;
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
