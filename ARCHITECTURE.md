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

`ComboTrials/RecordingPolicy.lua` gates recording by scene. Training recording
is enabled (restored in 1.1.17). In CFN replay, the entry script rejects legacy
recording starts before any recording state changes, UI, hotkeys and remote
commands do not expose replay recording, and the replay-only bottom recording
bar is hidden. Existing training, demos, saved combos, compilation and
cancellation paths are retained; the standalone training library's recordings
are unaffected.

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

## Fighter Roster

`data/SF6CC/fighters.json` is the single fighter roster. It maps a native
fighter ID to the SF6CC key that names per-fighter data
(`command_display/<key>.json`, `exceptions/<key>.json`, `CustomCombos/<key>/`),
plus English/Chinese display names and the official site slug. Runtime modules
read it through `autorun/func/FighterRoster.lua`; generator, snapshot and
packaging tools read the same file through `tools/fighter_roster.js` or their
own loaders. A fighter missing from the roster still gets the distinct key
`ESF_<id>`, so recording and character switching keep working on release day.
Once the roster names that fighter, the combo list copies its recordings from
`CustomCombos/ESF_<id>/` into `CustomCombos/<key>/` once per session
(`ComboTrials/FallbackComboMigration.lua`; existing files are never
overwritten and the originals stay in place).
The standalone training library may only load `SF6CCTrainingLibrary/*`
modules; its name tables are checked against the roster by
`tools/test_fighter_roster.lua`.

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

# Training Library (Native Eight Slots)

The standalone training library (`autorun/SF6CC_TrainingLibrary.lua` and
`autorun/SF6CCTrainingLibrary/`) manages training configurations over the
game's own eight recording slots. It is independent of the ComboTrials entry
and of SF6CM.

- `NativeEightRuntime` observes the native session read-only. It never replaces
  `RecordSlots`, native record/play rows or the reversal picker capacity.
- `Library` owns selection, per-fighter memory and the single operation queue.
  `Records` and `TrainingRecordImport` convert configurations into the existing
  native slots, reversals and guard settings.
- `NativeLibraryTab` publishes one owned root page after the reversal settings;
  `NativeSlotNames` substitutes "number - description" text on native lists.
- `NativeOwnership` is the only path for objects handed to game structures: one
  permanent engine reference, never released from Lua. See
  [Known Limitations](docs/KNOWN_LIMITATIONS.md) for the October 8 crash analysis.
- `Context.training_state()` separates offline training, the matchmaking
  `online` hold and leaving training.

The retired 80-slot expansion modules (`NativeRecordingRuntime`,
`NativeRecordingSession`, `NativeRecordingMenu`, `NativeRecordingSeed`,
`NativeSaveCompletion`, `NativeMenu`, `NativeRecordingNamePage`) remain in the
source tree but are not loaded. Their September 2026 design and deployment
notes are archived in
[ARCHITECTURE_LIBRARY_LOG_2026-09](docs/archive/training-library/ARCHITECTURE_LIBRARY_LOG_2026-09.md).
Maintainer details: [Training Library](docs/training-library/README.md).

---

# Upstream Compatibility

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
