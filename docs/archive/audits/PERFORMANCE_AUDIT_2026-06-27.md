# Performance Audit v1

> Status: `HISTORICAL`. This static audit is bound to June 27, 2026 and is not
> current performance authority.

Date: 2026-06-27

Branch: `codex/performance-audit-v1`

Scope: static audit of the active REFramework Lua project under `autorun/` and
`autorun/func/`. Data JSON files were considered only where Lua code reads or
writes them during gameplay. Historical/reference copies under `release/` and
`exam/` were not counted as active runtime modules unless they are manually
copied into a live REFramework install.

Important: this audit intentionally does not optimize or modify runtime code.
All costs below are estimates from code inspection, callback frequency, allocation
shape, and REFramework/Lua runtime behavior. Runtime profiling is still needed to
confirm exact timing on a target machine.

## Executive Summary

The most likely sources of visible training-mode frame spikes are:

1. Runtime safety checks recompute native training context many times per frame.
2. Shared input hooks run safety checks and finalization inside `pl_input_sub`.
3. Training Script Manager scans and mutates native UI widgets every frame.
4. Combo Trials D2D parses motion strings and rebuilds draw data every frame.
5. Combo Trials scans combo files and reparses JSON on a 60-frame timer.
6. Distance Viewer rebuilds/sorts anti-air and move display data every frame.
7. Multiple modules do synchronous JSON/file polling on fixed frame intervals.

The common pattern is not one single huge loop. It is many medium-cost operations
that run on the game thread, often in the same frame: native reflection, singleton
lookups, table allocation, string formatting, JSON parsing, filesystem access,
and UI rebuilds. This can produce short stalls even on high-end hardware.

## Severity Scale

- P0: Very likely to cause user-visible frame spikes during normal training.
- P1: Likely to cause spikes when the related module or UI is enabled.
- P2: Conditional or lower-frequency spikes; still important for polish.
- P3: Structural or diagnostic issues that can amplify other costs.

Allocation estimates:

- Low: a few temporary locals or strings.
- Medium: repeated small tables/strings every frame.
- High: many tables/strings per frame or per visible row.
- Very high: synchronous JSON/filesystem or large transient structures.

CPU estimates:

- Low: simple arithmetic or flag checks.
- Medium: several Lua loops, string operations, or ImGui calls.
- High: native reflection, managed object traversal, sorting, or many draw calls.
- Very high: filesystem access, JSON parse/write, or large native graph traversal.

## Callback Inventory

### `autorun/Training_ScriptManager.lua`

- `sdk.hook`: `TickerUtil..cctor`, `TickerRequestData.GetMessage`,
  `bBootFlow.UpdatePhaseTransition`, `bBattleFighterEmoteFlow.setup`,
  `bBattleFlow.endReplay`.
- `re.on_pre_gui_draw_element`: native UI visibility interception.
- `re.on_frame`: main script orchestrator, hotkeys, web bridge, mode routing,
  native UI visibility management.
- `re.on_draw_ui`: manager ImGui panel.
- `d2d.register`: session recap D2D draw and hide-flash overlay.

### `autorun/func/SharedHooks.lua`

- `sdk.hook`: `FBattleMediator.UpdateGameInfo` for shared character info.
- `sdk.hook`: `nBattle.cPlayer.pl_input_sub` for shared input pre/post callbacks.
- `re.on_application_entry("UpdateBehavior")`: P2 input finalization and GC step.

### `autorun/func/GameState.lua`

- `re.on_frame`: shared game-state snapshot.

### `autorun/TrainingComboTrials_v1.0.lua`

- `re.on_frame`: shared player info copy.
- `re.on_frame`: main Combo Trials update/orchestrator.
- `re.on_frame`: save/load state tracking.
- `sdk.hook`: round result/KO hooks.
- `sdk.hook`: Training Manager save/load hooks.
- `sdk.hook`: Battle Flow update hook.
- Shared input callbacks registered into `_G._shared_input_pre` and
  `_G._shared_input_post`.

### `autorun/func/ComboTrials_UI.lua`

- `re.on_frame`: floating HUD/control bar and popup UI.
- `re.on_draw_ui`: debug/config ImGui UI.

### `autorun/func/ComboTrials_D2D.lua`

- `d2d.register`: Combo Trials D2D overlay.

### `autorun/SF6_DistanceViewer.lua`

- `sdk.hook`: `FBattleMediator.UpdateGameInfo` character info hook.
- `sdk.hook`: Training Manager refresh hook.
- Shared input post callback.
- `re.on_frame`: main Distance Viewer update.
- `re.on_draw_ui`: configuration/debug UI.
- `d2d.register`: icon rendering.

### `autorun/SheldonsBoxes.lua`

- `re.on_frame`: shared player info copy.
- `re.on_frame`: main hitbox/HUD processing.
- `d2d.register`: VR overlay and flash-zone draw.
- `re.on_draw_ui`: configuration UI.

### `autorun/TrainingHitConfirm_v1.0.lua`

- `re.on_frame`: hit-confirm detection.
- `re.on_draw_ui`: debug/config UI.

## Ranked Hotspots

### P0-01 Runtime safety checks recompute native training context

Location:

- `autorun/func/RuntimeSafety.lua`
- `native_training_context`: lines around 38-121.
- `is_training_allowed`, `is_allowed`, `can_inject_input`: lines around 123-140.
- Called from many hot paths, including:
  - `autorun/func/SharedHooks.lua`
  - `autorun/Training_ScriptManager.lua`
  - `autorun/TrainingComboTrials_v1.0.lua`
  - `autorun/func/ComboTrials_UI.lua`
  - `autorun/func/ComboTrials_D2D.lua`
  - `autorun/SF6_DistanceViewer.lua`
  - `autorun/SheldonsBoxes.lua`

Estimated execution frequency:

- Many times per frame during training.
- Also called inside shared input hook callbacks, likely at least once per player
  per frame and possibly more depending on native input update frequency.

Estimated allocation:

- Medium.
- Temporary candidate tables are built in `training_manager_allows`.
- Several `pcall` closures and intermediate locals are created.
- Native strings/type names may be produced while walking UI widgets.

Estimated CPU cost:

- High.
- Calls managed singleton lookup, field access, method calls, type-definition
  checks, type-name checks, and native UI widget traversal.

Why it may cause frame spikes:

- The safety gate is used like a cheap boolean, but it performs expensive native
  verification every time.
- `has_training_ui_widgets` can scan `_ViewUIWigetDict._entries` and nested UI
  widget arrays.
- If several modules call this in the same frame, the native UI graph is walked
  repeatedly.
- The cost can align with scene changes, UI refreshes, replay state changes, or
  TrialHub communication, producing short stalls.

How to optimize:

- Compute a single per-frame safety snapshot once from a central place, then make
  `is_allowed`, `is_training_allowed`, and `can_inject_input` read cached flags.
- Throttle expensive native verification to scene transitions, Training Manager
  refresh events, or a low-frequency interval.
- Cache Training Manager and widget evidence until invalidated.
- Keep separate flags for "script updates allowed", "UI draw allowed", and
  "input injection allowed" so input hooks do not need full UI verification.

### P0-02 Shared input hook performs repeated safety checks and finalization

Location:

- `autorun/func/SharedHooks.lua`
- `write_p2_input_mask`: lines around 118-130.
- `finalize_distance_viewer_p2_input`: lines around 132-181.
- `sdk.hook("nBattle.cPlayer.pl_input_sub")`: lines around 198-247.
- `re.on_application_entry("UpdateBehavior")`: lines around 248-251.

Estimated execution frequency:

- Every native `pl_input_sub` call.
- At minimum this is expected to be frame-level and player-level.
- It may be called more than once per frame depending on the game update path.

Estimated allocation:

- Medium.
- `table.insert` and `table.remove` are used for `p_id_stack`.
- Callback dispatch uses `pcall`.
- Runtime safety calls allocate as described in P0-01.

Estimated CPU cost:

- High in practice because it nests expensive safety checks inside a native input
  hook.
- Also refreshes player addresses from `gBattle` every 120 hook calls.

Why it may cause frame spikes:

- Input hooks run in one of the most latency-sensitive paths.
- `RuntimeSafety.can_inject_input()` is called before input callbacks and again
  in finalization paths.
- `finalize_distance_viewer_p2_input` can be invoked from the hook post path and
  again from `UpdateBehavior`.
- Any occasional native lookup or callback exception logging happens directly in
  the gameplay update path.

How to optimize:

- Use the cached safety snapshot from P0-01.
- Replace `table.insert`/`table.remove` stack operations with a numeric stack top.
- Avoid duplicate finalizer calls by using a per-frame or per-hook-call dirty flag.
- Cache P2 input object/field references more aggressively and refresh only when
  object identity changes.
- Keep input hook callbacks extremely small and move non-critical work to
  `re.on_frame`.

### P0-03 Native training UI visibility is scanned and mutated every frame

Location:

- `autorun/Training_ScriptManager.lua`
- `_tsm_apply_widget_visibility`: lines around 355-396.
- `manage_ui_visibility`: lines around 398-407.
- Called from main `re.on_frame`: lines around 767-768.

Estimated execution frequency:

- Every active training frame from the main Script Manager update.

Estimated allocation:

- Medium.
- Temporary `texts = { LeftText, CenterText, RightText }` tables are created for
  attack-info lines.
- Repeated `pcall` wrappers and native object access occur while traversing UI.

Estimated CPU cost:

- High.
- Uses managed singleton lookup, dictionary entry traversal, widget type-name
  checks, attack-info array traversal, and repeated native property writes.

Why it may cause frame spikes:

- The code walks native UI widgets and mutates visibility every frame, even when
  active script state has not changed.
- Native UI structures can be larger or unstable around training option changes,
  round reset, TrialHub transitions, and pause/menu states.
- Repeated `set_Visible` and `set_ForceInvisible` calls can force native-side UI
  work even if the desired state is unchanged.

How to optimize:

- Apply visibility changes only when `scripts_active`, mode, or refresh state
  changes.
- Cache widget references and last applied visibility values.
- Refresh the widget cache on known UI refresh hooks rather than every frame.
- Replace the per-line `texts` table with direct field checks.
- Split discovery from mutation: discover widgets rarely, write only when state
  changes.

### P0-04 Combo Trials D2D reparses and rebuilds visible motion lines every draw

Location:

- `autorun/func/ComboTrials_D2D.lua`
- `parse_motion_to_icons`: lines around 226-562.
- `draw_parsed_line`: lines around 584-620.
- Raw input reads and display-line construction: lines around 857-1051.
- `d2d.register`: line around 1110.

Estimated execution frequency:

- Every D2D draw frame while Combo Trials D2D is enabled.
- Work scales with visible log rows, trial steps, raw input lines, and P1/P2
  visibility.

Estimated allocation:

- High.
- Builds many temporary arrays and objects: motion tokens, text blocks, processed
  tokens, hold tokens, final tokens, line elements, display lines, and merged log
  rows.
- Creates many intermediate strings through `upper`, `gsub`, concatenation, and
  formatting.

Estimated CPU cost:

- High.
- Motion parsing performs many Lua pattern substitutions per line.
- Text measurement and D2D draw calls happen per token.
- Charge/hold/follow-up state can alter parsing every frame.

Why it may cause frame spikes:

- Parsing and layout are rebuilt in the draw path instead of cached as model
  state.
- Visible log length and raw input history can suddenly increase during combo
  practice.
- String-heavy parsing creates GC pressure, which can show up as periodic stutter.

How to optimize:

- Cache parsed motion output by motion string, facing/flip state, validation
  state, charge status, hold-frame bucket, and display mode.
- Cache text measurements for stable labels/icons.
- Build visible display lines only when combo state, current step, log, or layout
  dimensions change.
- Reuse scratch arrays or introduce small object pools for per-frame line data.
- Keep D2D draw functions mostly limited to drawing already prepared primitives.

### P0-05 Combo Trials main update allocates and scans heavily during gameplay

Location:

- `autorun/TrainingComboTrials_v1.0.lua`
- Main `re.on_frame`: lines around 3613-3742.
- Player tracking and validation: lines around 2473-2696.
- Input buffering: lines around 2738-2893.
- Action processing: lines around 2896-3555.
- Live combo tracking: lines around 1942-1955.

Estimated execution frequency:

- Every active training frame while Runtime Safety allows the script.
- Scales with P1/P2 processing, selected mode, input activity, action changes,
  and combo validation.

Estimated allocation:

- Medium to high.
- Creates `actions_to_process` tables per player/frame.
- Inserts action records, log entries, input history entries, and formatted
  messages.
- `table.insert(log, 1)` shifts existing log rows.
- `table.remove(queue, 1)` shifts input-history queues.

Estimated CPU cost:

- High when actions change or validation is active.
- Uses managed field reads, combo counters, action data extraction, validation
  rules, charge tracking, and per-player state machines.

Why it may cause frame spikes:

- The baseline per-frame work is moderate, but action transitions cause bursts.
- Front-inserting log entries and front-removing queues become more expensive as
  history grows.
- Validation, charge exception learning, input capture, and UI state updates can
  all happen in the same frame.

How to optimize:

- Use ring buffers/deques for logs and input history.
- Reuse per-player scratch arrays instead of allocating `actions_to_process`.
- Cache managed field descriptors and frequently accessed native references.
- Separate idle, recording, playback, and validation paths so inactive features do
  almost no work.
- Avoid processing P2 trial state when the current mode/UI only needs P1.

### P0-06 Combo Trials scans files and parses JSON on a 60-frame timer

Location:

- `autorun/TrainingComboTrials_v1.0.lua`
- `COMBO_LIST_AUTO_REFRESH_FRAMES`: line around 366.
- `ct_auto_refresh_combo_list`: lines around 2135-2151.
- `autorun/func/ComboTrials_Files.lua`
- `scan_combo_files`: lines around 177-261.
- `refresh_combo_list_preserve_selection`: lines around 303-318.

Estimated execution frequency:

- Every 60 frames while Combo Trials mode is active.
- Also runs after saves, character changes, explicit refreshes, and load paths.

Estimated allocation:

- Very high when many combo files exist.
- `fs.glob` returns path lists.
- Sorting allocates/computes comparison keys.
- `json.load_file` parses each combo file to derive display names.
- Sanitized labels and path/display arrays are rebuilt.

Estimated CPU cost:

- Very high for a frame callback because it performs synchronous filesystem and
  JSON work.

Why it may cause frame spikes:

- Directory scans and JSON parsing happen on the game thread.
- The timer can align with other periodic work such as web bridge polling,
  Distance Viewer dumps, or TrialHub sync.
- Filesystem latency can be inconsistent due to antivirus, drive state, cloud
  sync, or OS cache misses.

How to optimize:

- Remove frequent polling from gameplay frames.
- Refresh combo lists on explicit UI action, save completion, character change,
  or known external sync marker change.
- Cache directory metadata and display names by path plus modified time.
- Amortize scanning over many frames if polling remains necessary.
- Never parse every combo JSON file just to render a stable dropdown label.

### P1-07 Distance Viewer rebuilds and sorts move data every frame

Location:

- `autorun/SF6_DistanceViewer.lua`
- Main `re.on_frame`: lines around 3488-3644.
- `_dv_rebuild_aa_moves`: lines around 3438-3458.
- Character cache update: lines around 1073-1141.
- Combat box distances: lines around 1281-1383.
- Zone evaluation: lines around 1394-1435.
- Display table creation: lines around 3694-3696.

Estimated execution frequency:

- Every frame while Distance Viewer is enabled and Runtime Safety allows it.
- Anti-air move rebuild runs every frame when P2 cache is valid.
- Zone evaluation can run for both players every frame.

Estimated allocation:

- High.
- `_dv_rebuild_aa_moves` builds and sorts a move list table each frame.
- `evaluate_player_zone` builds and sorts advanced move tables.
- `p1_display` and `p2_display` tables are rebuilt every frame.
- Several `Vector3f.new` objects are created while resolving screen positions.

Estimated CPU cost:

- High.
- Collision box scans, move-list sorting, native field reads, and overlay state
  preparation all happen before draw.

Why it may cause frame spikes:

- Move definitions and sort order usually change only when character/config data
  changes, but the code rebuilds them every frame.
- The module combines data preparation, collision scanning, web-state dumping,
  anti-air automation, and overlay display in one frame path.
- Allocation-heavy sorting creates GC pressure during normal training movement.

How to optimize:

- Cache sorted anti-air and advanced move lists by character, side, and config
  revision.
- Rebuild move lists only after character change, config change, or data reload.
- Reuse display tables and vector objects.
- Share collision scan results between top-position, combat-distance, and zone
  evaluation where possible.
- Gate P2 anti-air processing behind explicit active state and dirty flags.

### P1-08 Sheldon's Boxes scans collision objects and draws many primitives

Location:

- `autorun/SheldonsBoxes.lua`
- Main `re.on_frame`: lines around 623-887.
- `draw_boxes`: lines around 494-596.
- Player/world loops: lines around 748-780.
- Charge bars and HUD formatting: lines around 395-430.
- `d2d.register`: line around 1131.

Estimated execution frequency:

- Every frame while Sheldon's Boxes is enabled.
- Work scales with active hitboxes, hurtboxes, projectiles, collision objects, and
  enabled labels.

Estimated allocation:

- Medium to high.
- Builds HUD part arrays and formatted strings.
- Builds property labels for boxes.
- Queues VR/D2D overlay data.

Estimated CPU cost:

- High when many boxes are active.
- Calls `draw.world_to_screen` repeatedly for box corners.
- Reads multiple native fields per box and issues many draw calls.

Why it may cause frame spikes:

- Collision and projectile object counts can burst during specific moves.
- Labels and outlines multiply draw and string work.
- Global work scanning is expensive if only a subset of box types is visible.

How to optimize:

- Skip global/projectile scans unless those visual layers are enabled.
- Precompute field handles and box classification where possible.
- Reuse HUD arrays and label buffers.
- Draw or format detailed labels only when the user enables them.
- Cull offscreen boxes before expensive label formatting and multi-pass drawing.

### P1-09 Synchronous JSON and WebBridge polling is spread across modules

Location:

- `autorun/Training_ScriptManager.lua`
  - Web bridge poll/write paths: lines around 570-615 and 770-780.
- `autorun/SF6_DistanceViewer.lua`
  - WebBridge polling: lines around 369-390.
  - Web state dump: lines around 3435 and 3515-3519.
- `autorun/SheldonsBoxes.lua`
  - Web state dump: lines around 892-925.
- `autorun/TrainingComboTrials_v1.0.lua`
  - Replay state polling: lines around 3653-3666.
  - Replay bridge polling: lines around 1989-2006.
  - TrialHub sync reads: lines around 2153-2178.

Estimated execution frequency:

- Multiple independent timers: 10, 30, 60, and 90-frame intervals.
- Some inactive-state writes can repeat frequently when modules are disabled or
  training is not allowed.

Estimated allocation:

- High to very high on polling frames.
- JSON load/dump creates strings, tables, and file buffers.
- Bridge state tables are rebuilt for serialization.

Estimated CPU cost:

- Medium to very high.
- Serialization itself is moderate; filesystem latency is unpredictable and can
  dominate.

Why it may cause frame spikes:

- All work is synchronous on the game thread.
- Independent fixed intervals can align, causing several JSON/file operations in
  the same frame.
- External processes, antivirus, or cloud sync can turn a small file write into a
  noticeable stall.

How to optimize:

- Add one central bridge/file scheduler with staggered phases and per-frame budget.
- Serialize only when state changes, using a last-state hash or revision counter.
- Stop writing inactive state every frame; write once on transition.
- Batch reads/writes and defer noncritical bridge operations until after gameplay
  critical work.
- Keep all runtime-generated bridge files out of source control.

### P1-10 Hit Confirm debug and meter scanning can become expensive

Location:

- `autorun/TrainingHitConfirm_v1.0.lua`
- Detection and frame-meter helpers: lines around 454-888.
- Main `re.on_frame`: lines around 1160-1220.
- Debug matrix UI: lines around 1268-1327.

Estimated execution frequency:

- Every frame in the relevant Script Manager mode.
- Widget cache refresh runs about every 300 frames.
- Debug matrix can scan up to the configured frame-meter window every UI frame.

Estimated allocation:

- Medium in normal use.
- High with debug matrix enabled: active-line arrays, per-line P1/P2 data tables,
  and formatted UI strings are rebuilt.

Estimated CPU cost:

- Medium normally.
- High with debug UI expanded or verbose logging enabled.

Why it may cause frame spikes:

- Frame-meter data is naturally frame-indexed and can grow into broad scans.
- Debug display rebuilds large matrix rows every draw.
- Logging/string formatting inside detection paths can amplify spikes while
  investigating issues.

How to optimize:

- Keep heavy debug views opt-in and clearly separated from normal mode.
- Throttle debug matrix rebuilds to a lower rate such as 10 Hz.
- Reuse per-line data tables.
- Cache field descriptors and avoid repeated string formatting until text is
  actually visible.

### P1-11 Session Recap D2D chart uses per-pixel fill loops

Location:

- `autorun/func/Training_SessionRecap.lua`
- Pixel `draw_line`: lines around 111-121.
- `_rec_fill_area_seg`: lines around 345-357.
- Chart draw path: lines around 420-620.
- `d2d_draw`: lines around 636-670.
- Queue/close handling `re.on_frame`: lines around 691-698.

Estimated execution frequency:

- Every D2D draw frame while the session recap overlay is visible.

Estimated allocation:

- Medium.
- Builds curve points, legends, labels, hover strings, and temporary draw values
  per frame.

Estimated CPU cost:

- High while visible.
- Area fill and line drawing use loops across pixel spans/chart width.

Why it may cause frame spikes:

- Per-pixel rectangle fill loops multiply quickly on larger chart widths.
- Recap appears near session transitions, where other modules may also be writing
  state or resetting.
- The chart is visually static for most frames but is still redrawn from scratch.

How to optimize:

- Cache chart geometry and primitive lists until sessions, layout, or resolution
  changes.
- Replace pixel loops with D2D polygon/line primitives if available.
- Reduce fill density or draw at a lower internal resolution.
- Rebuild hover text only when mouse position changes meaningfully.

### P1-12 ImGui HUD/control surfaces rebuild text and rectangles every frame

Location:

- `autorun/func/Training_SharedUI.lua`
- Floating rect registry and text drawing: lines around 1-420.
- `autorun/func/ComboTrials_UI.lua`
- Floating window/control bar: lines around 833-1206.
- Debug/config UI: lines around 2017 onward.

Estimated execution frequency:

- Every frame while active UI surfaces are visible.

Estimated allocation:

- Medium.
- `FloatingRects` is cleared and repopulated every frame.
- `publish_rect` creates tables for registered rectangles.
- `UI.draw_text` performs text escaping and sizing work.
- Multiple `Vector2f.new` values are created during layout.

Estimated CPU cost:

- Medium.
- ImGui window setup, text measurement, and text draw calls are repeated even
  when content is stable.

Why it may cause frame spikes:

- This work layers on top of Combo Trials D2D and main update costs.
- Text and rectangle state changes frequently during combo validation.
- ImGui cost is usually acceptable, but repeated allocation can contribute to GC
  spikes.

How to optimize:

- Reuse floating-rect tables and avoid per-frame registry allocation.
- Cache escaped strings and measured text widths for stable labels.
- Keep full-screen invisible ImGui windows out of frames where no controls are
  visible.
- Prefer prepared D2D primitives for high-frequency HUD text when practical.

### P2-13 Duplicate character-info hooks do overlapping work

Location:

- `autorun/func/SharedHooks.lua`
- `FBattleMediator.UpdateGameInfo` hook: lines around 76-99.
- `autorun/SF6_DistanceViewer.lua`
- Separate `FBattleMediator.UpdateGameInfo` hook: lines around 1012-1035.

Estimated execution frequency:

- Whenever the native battle mediator updates game info, likely frame-level or
  near frame-level during battle/training.

Estimated allocation:

- Low to medium.
- Builds or formats character names and stores shared player info.

Estimated CPU cost:

- Low to medium.
- The cost is small compared with UI and JSON work but is redundant.

Why it may cause frame spikes:

- Redundant hooks multiply native hook dispatch and string work.
- The duplicated result feeds other hot paths, so inconsistent timing can also
  cause extra cache rebuilds.

How to optimize:

- Use `SharedHooks` as the single character-info provider.
- Have Distance Viewer consume `_G._shared_player_info` instead of installing a
  second hook.
- Publish a revision counter when character info changes.

### P2-14 `sdk.find_type_definition` appears in frame-level raw input paths

Location:

- `autorun/func/ComboTrials_D2D.lua`
- `_ctd_raw_read_inputs_inner`: line around 97.
- Additional debug-only occurrences:
  - `autorun/func/ComboTrials_UI.lua`: line around 1212.
  - `autorun/SF6_DistanceViewer.lua`: line around 2395.
  - `autorun/SheldonsBoxes.lua`: lines around 372 and 632.

Estimated execution frequency:

- Every D2D draw frame if Combo Trials raw input overlay is enabled.
- Debug/config occurrences are conditional.

Estimated allocation:

- Low.

Estimated CPU cost:

- Medium to high for the raw overlay path.
- Type-definition lookup is much more expensive than reading a cached reference.

Why it may cause frame spikes:

- Raw input display can be active during the exact moments where players notice
  training stutter.
- Reflection lookup cost is unnecessary when the type is stable.

How to optimize:

- Cache `gBattle` type definitions and field handles at module load or first use.
- Prefer `GameState.GS` shared references where possible.
- Ensure debug-only lookups cannot run in the normal overlay path.

### P2-15 Auto-learned charge exceptions can write JSON mid-gameplay

Location:

- `autorun/TrainingComboTrials_v1.0.lua`
- `ct_player_hold_charge`: lines around 2710-2718.
- Charge-min exception write in action processing: lines around 3097-3109.

Estimated execution frequency:

- Rare, but can occur during active combo practice when the auto-detection logic
  learns an exception.

Estimated allocation:

- High on write frames.
- JSON serialization allocates output strings and file buffers.

Estimated CPU cost:

- High on write frames because disk write is synchronous.

Why it may cause frame spikes:

- A rare but synchronous JSON write can produce a noticeable hitch exactly when a
  charge move is being practiced.
- This can be mistaken for general rendering stutter because it happens during a
  real input sequence.

How to optimize:

- Queue learned exceptions in memory and flush during round idle, menu open,
  explicit save, or script shutdown.
- Debounce repeated writes to the same exception file.
- Persist a compact dirty set rather than rewriting broad data immediately.

### P2-16 Hotkey scanning is cheap by default but scales with enabled bindings

Location:

- `autorun/func/Training_Hotkeys.lua`
- Poll/update loop: lines around 220-268.
- Called from `autorun/Training_ScriptManager.lua`: line around 719.

Estimated execution frequency:

- Every active training frame while Script Manager is not suspended.

Estimated allocation:

- Low.

Estimated CPU cost:

- Low by default.
- Medium if many bindings and modifier combinations are enabled.

Why it may cause frame spikes:

- Key reads are wrapped in `pcall` and run every frame for active bindings.
- The current default appears conservative, so this is not a primary issue today.

How to optimize:

- Keep hotkeys disabled unless explicitly configured.
- Precompute active binding lists by mode/scope.
- Avoid `pcall` in the per-key path if the input API is stable.

### P2-17 Ticker hook scans message table with `pairs`

Location:

- `autorun/Training_ScriptManager.lua`
- `_ticker.message` setup and hook: lines around 37-63.

Estimated execution frequency:

- Whenever native ticker messages are requested.

Estimated allocation:

- Low.

Estimated CPU cost:

- Low currently.
- Can grow if stale messages accumulate.

Why it may cause frame spikes:

- The hook scans all `_ticker.message` entries with `pairs` for every
  `GetMessage` call.
- If message entries are not cleared, cost grows over long sessions.

How to optimize:

- Index messages directly by requested ID.
- Clear one-shot ticker messages after they are consumed.
- Keep the hook body free of table scans.

### P3-18 Error registry can become expensive during repeated callback failures

Location:

- `autorun/func/SharedHooks.lua`
- `safe_call` and error registry: lines around 19-72.

Estimated execution frequency:

- Only when callback errors occur.

Estimated allocation:

- Low normally.
- Medium to high if the same callback errors every frame.

Estimated CPU cost:

- Low normally.
- High during repeated error spam due to traceback/log construction and
  `table.remove(e.list, 1)`.

Why it may cause frame spikes:

- A broken callback can turn error handling into per-frame logging work.
- Front-removing from the error list shifts table entries.

How to optimize:

- Use a ring buffer for stored error samples.
- Rate-limit traceback capture and warning logs.
- Auto-disable a callback after repeated failures in a short window.

### P3-19 Historical `release/` and `exam/` copies can cause duplicate installs

Location:

- `release/`
- `exam/`

Estimated execution frequency:

- None when these folders are only repository artifacts/reference data.
- Potentially duplicate frame/hook frequency if copied into a live REFramework
  install alongside root `autorun/`.

Estimated allocation:

- None in normal repository use.
- Duplicative if accidentally loaded.

Estimated CPU cost:

- None in normal repository use.
- Potentially multiplicative if duplicate autorun scripts are loaded.

Why it may cause frame spikes:

- REFramework loads Lua files from autorun locations. If release/reference copies
  are packaged or copied incorrectly, hooks and `on_frame` callbacks can register
  more than once.
- This is a release/install hygiene risk rather than a source-code hot path.

How to optimize:

- Ensure release packaging includes only the intended runtime files.
- Keep generated release artifacts out of source control.
- Add a packaging check that rejects duplicate autorun scripts.

## Cross-Cutting Spike Patterns

### Fixed-interval alignment

Several systems use frame modulo timers such as 10, 30, 60, and 90 frames. These
intervals align periodically, which can stack JSON/file polling, combo list
refresh, web-state dumps, and UI rebuilds in one frame.

Recommended direction: centralize periodic work into a scheduler that staggers
tasks and enforces a small per-frame budget.

### Native reflection in hot paths

The project frequently uses `sdk.get_managed_singleton`, `sdk.find_type_definition`,
`get_field`, `call`, and type-name checks from frame callbacks or hooks.

Recommended direction: cache stable type definitions, field handles, singleton
references, and per-frame state snapshots. Invalidate caches from known game
state transitions instead of rediscovering everything from scratch.

### UI rebuilds in draw callbacks

Combo Trials D2D, Session Recap, and ImGui HUDs rebuild text, layout, and draw
data every frame.

Recommended direction: treat draw callbacks as render-only. Build model/layout
data only when source state or layout dimensions change.

### Front insertion/removal in Lua arrays

Several histories/logs use `table.insert(t, 1)` or `table.remove(t, 1)`. These
shift array contents and get more expensive as the list grows.

Recommended direction: use ring buffers for logs, input history, and error
samples.

### Runtime file writes during gameplay

WebBridge/WebState dumps, TrialHub sync reads, replay state polling, and learned
exception writes all run synchronously.

Recommended direction: write only on state changes, stagger IO, cache serialized
strings, and delay noncritical writes until idle states.

## Suggested Next Investigation Steps

No optimization should be merged before measuring. The next safe step is to add a
temporary profiling layer that records elapsed time and allocation proxies without
changing behavior:

1. Wrap each `re.on_frame`, `re.on_draw_ui`, `d2d.register`, and `sdk.hook`
   callback in a lightweight timer.
2. Track worst frame, moving average, call count, and last spike reason per
   module.
3. Add counters for JSON reads/writes, filesystem scans, combo list refreshes,
   safety-context recomputes, and D2D parsed-line counts.
4. Display profiling only in a debug UI or write it to a runtime log excluded
   from Git.
5. Reproduce in training mode with Distance Viewer, Combo Trials, Sheldon's
   Boxes, Hit Confirm, WebBridge, and TrialHub toggled independently.

## Highest-Value Optimization Order After Profiling

1. Cache Runtime Safety once per frame and remove native UI scans from repeated
   safety checks.
2. Make shared input hook callbacks minimal and remove duplicate finalization.
3. Stop scanning native training UI every frame; update only on state changes.
4. Remove 60-frame combo JSON directory polling or convert it to cached,
   amortized refresh.
5. Cache Combo Trials D2D parsed/layout data.
6. Cache Distance Viewer sorted move lists and reuse display objects.
7. Stagger all JSON/WebBridge/TrialHub filesystem work through one scheduler.
8. Replace log/history front insert/remove with ring buffers.
