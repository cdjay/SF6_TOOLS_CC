# Task B - SF6CC Autonomous Bug Mining

## 1. Final State

Phase 1 state: `TASK_B_PHASE_1_COMPLETE`

Deep Phase 2+ offline mining state: `COMPLETE`

Real-game smoke state: `REQUIRES_REAL_GAME`

Task B worked in the isolated worktree
`D:\CP\SF6CC\reframework-task-b` on branch
`bugfix/autonomous-bug-mining-task-b`. The baseline SHA was
`1fd27f95ade064a54b789153a492df505497af57`.

## 2. Baseline

The unmodified baseline passed:

- Lua parse: 115/115 files.
- Lua tests: 43/43.
- Action runtime and BCM generator tests: 8/8.
- Combo JSON editor tests: 6/6.
- Python snapshot test and release-version gate: 2/2.

No known baseline failure or flaky test was observed.

## 3. Mining Coverage

| Surface | Attack performed |
| --- | --- |
| Recording / Raw Input | Exhaustive horizontal mirror checks, uint16 stream checks, raw/timeline differential comparison, malformed timeline playback cases |
| Side-relative | Compared every frame of 293 native streams against the corresponding timeline under direct or mirrored orientation; identified 9 real side-switch files and no button corruption |
| Timeline | Zero-duration, unknown token, lowercase token, same-line multi-button, cumulative duration, and 10,000-case chunking tests |
| Hitstop | Verified wall-stun catch-up compression and `advance_timeline_frames(N)` equivalence to N single-frame advances across 10,000 cases |
| Detection | Boundary and idempotence mining for partial-chord and RAW DR sequence normalization |
| Demo / Playback | Differential test between timeline usability and the actual injected mask; strict all-or-nothing timeline build |
| Fast-forward | Verified missed-engine-frame catch-up consumes exactly the missing count without double application |
| Compatibility | Scanned 515 production Combo files across 21 character directories: 293 native streams and 222 facing-relative streams |
| Character-specific | Included charge, stance, follow-up, grab, multi-stage, wall-stun, and side-switch corpus cases without adding character hardcodes |
| Serialization | Ran fixed-timestamp load/migrate/serialize/load/migrate on all 515 files; no mechanism projection drift or second-pass drift |
| Error recovery | Rejected preparation and normalization loads followed by a successful load while observing current-session state |

## 4. Confirmed Bugs

### BUG-B001

- Severity: P1
- Domain: `TIMELINE`, `DEMO`, `PLAYBACK`
- Character: Generic
- Status: `FIXED`
- Reproduction: `"1f : 6+lp"` was accepted as usable, but Demo parsed mask `4` instead of `20`; `0f` and unknown tokens were also accepted and partially replayed.
- Root cause: Timeline usability and Demo playback used separate permissive parsers. Playback was case-sensitive and silently ignored unknown button tokens.
- Fix: Added one strict parser and all-or-nothing timeline builder to `RawInputCodec`; Demo now consumes that shared result.
- Commit: `aa3f2a5`
- Regression: `tools/test_combo_raw_input_codec.lua`
- Adversarial retest: Nine directions, six buttons, mixed case, invalid token boundaries, 100 deterministic repeats, and all 23,752 timeline rows in the 515-file corpus.
- Architecture impact: Parser ownership moved out of the entry script; no schema or semantic authority change.

### BUG-B002

- Severity: P1
- Domain: `NORMALIZATION`, `DETECTION`
- Character: Generic multi-button input
- Status: `FIXED`
- Reproduction: `MP -> LP -> PP` normalized to `MP -> PP` on the first pass and only to `PP` on the second pass.
- Root cause: Partial-chord normalization removed only the immediately preceding single-button phase instead of every adjacent owned phase inside the cumulative completion window.
- Fix: Changed the existing projection to consume adjacent precursors in one bounded loop while recomputing cumulative delay.
- Commit: `fe822b4`
- Regression: `tools/test_unified_action_consumer.lua`
- Adversarial retest: Punch and kick chords, command stems, exact 20-frame boundary, over-window input, explicit chord exclusion, contact deltas, source immutability, and 515-file corpus idempotence.
- Architecture impact: None. V2 input facts remain unchanged and the existing matcher remains authoritative.

### BUG-B003

- Severity: P2
- Domain: `RUNTIME_STATE`, `COMPATIBILITY`
- Character: Generic
- Status: `FIXED`
- Reproduction: Loading a structurally valid Combo that failed preparation or action normalization returned `false` and kept the old sequence, but fired `on_combo_file_change` first and stopped the active Demo.
- Root cause: The lifecycle callback ran before all fallible load preparation completed.
- Fix: Delayed the callback until preparation and normalization succeed.
- Commit: `f9b46f1`
- Regression: `tools/test_combo_file_load_recovery.lua`
- Adversarial retest: Preparation failure, normalization failure, retained old session, then successful replacement with exactly one lifecycle callback.
- Architecture impact: None. Successful load ordering and callback data are unchanged.

## 5. Bugs Fixed

- P0: 0
- P1: 2
- P2: 1

## 6. Confirmed But Unfixed

None.

## 7. False Positives / Expected Behavior

### FP-B001 - Lily raw/timeline length mismatch

One Lily wall-stun file has 532 timeline frames and 503 captured relative raw
frames. The 29-frame difference begins exactly at the wall-stun catch-up region
and is expected: missed input-hook frames are consumed from the timeline but do
not create captured hook samples.

### FP-B002 - Jamie step-note count mismatch

Three Jamie files contain one extra blank `step_notes` entry. No authored note
is lost, runtime behavior is unchanged, and fixed-timestamp editor migration
normalizes the blank overflow without mechanism drift.

### FP-B003 - Repeated same-kind Parry projection

An artificial sequence with multiple adjacent `PARRY` phases before RAW DR is
not idempotent under repeated one-shot normalization. The current guard
intentionally absorbs at most one precursor of each kind, the behavior was not
present in any of the 515 production files, and changing it could erase a real
independent Parry. Status: `EXPECTED_GUARD / AMBIGUOUS`, no fix.

## 8. Architecture Escalations

None. No finding requires changing AC/BCM authority, Move identity, Action ID
scope, the frozen V2 schema, or the unified semantic resolver contract.

## 9. Corpus Evidence

- Files scanned: 515 Combo JSON files.
- Character directories: 21.
- Timeline rows scanned: 23,752.
- Native raw streams: 293.
- Facing-relative raw streams: 222.
- Native side-switch files detected: 9.
- Raw/timeline button-corruption findings: 0.
- Serialization mechanism drift: 0.
- Serialization second-pass drift: 0.
- New focused regressions: 3.

## 10. Verification

Final verification completed:

- Focused regressions: BUG-B001 through BUG-B003 passed.
- Lua parse: 116/116 passed.
- Lua tests: 44/44 passed.
- Action runtime and BCM generator tests: 8/8 passed.
- Combo JSON editor tests: 6/6 passed.
- Python snapshot test and release-version gate: 2/2 passed.
- Corpus: 515/515 timeline syntax checks passed; 515/515 action
  normalizations were stable on a second pass.

Real-game smoke was not available in this worktree. The following remain
`REQUIRES_REAL_GAME`: recording capture, live side switch, hitstop input,
manual Demo injection, and bad-file selection while a Demo is visibly active.

## 11. Remaining Risks

- The corpus represents 21 character directories rather than every generated
  character catalog in the repository.
- Real-game callback frequency and REFramework object lifetime cannot be fully
  proven by standalone Lua tests.
- Timeline syntax outside the observed V2 form is now rejected instead of
  partially replayed; all scanned production rows use the accepted form.

## 12. Handoff to Main

Merge order:

1. `aa3f2a5` - strict timeline playback parsing.
2. `fe822b4` - multi-stage chord precursor normalization.
3. `f9b46f1` - atomic failed Combo loading.

Conflict risk is low for BUG-B002 and BUG-B003. BUG-B001 touches the main entry
near Demo timeline construction and may conflict textually with Task A entry
extraction; preserve the call to `RawInputCodec.build_timeline_steps` if
resolving that conflict.

---

# Deep Autonomous Bug Mining Phase 2+

All Phase 2 evidence below was collected on August 15, 2026. Phase 1 commits
and findings remain the baseline and were not reimplemented.

## 13. Deep Mining Coverage

| ID | Surface | Attack methods and cases | Character / corpus coverage | Bugs / regressions | Offline confidence | Real-game dependency | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SURFACE-B-001 | Recording lifecycle | Start-state characterization, abort, menu/character interruption, opposite-player character switch, fresh-state comparison, 1,000-repeat lifecycle run | Generic P1/P2 recorder; four recorder/switch-player combinations | BUG-B004; `test_combo_recording_lifecycle.lua` | High | Live start/stop callback ordering | `DEEPLY_ATTACKED` |
| SURFACE-B-002 | Raw Input transitions | Exhaustive 0..65535 masks under both facings, press/release/hold, multi-button, direction+button, neutral, malformed stream, cache invalidation | 515 files; 293 native and 222 relative streams | Expanded `test_combo_raw_input_codec.lua` | High | Actual REFramework input-hook frequency | `DEEPLY_ATTACKED` |
| SURFACE-B-003 | Side-relative / facing | Mirror invariant, capture/playback roundtrip, semantic hold, physical hold, switch-frame press/release/neutral, nine native cross-up files | Nine real switch files across Blanka, Elena, Guile, Ken, Kimberly, Luke and Ryu; synthetic all-mask coverage | Expanded `test_combo_raw_input_codec.lua` | High | Live facing sampling on a cross-up frame | `DEEPLY_ATTACKED` |
| SURFACE-B-004 | Timeline / hitstop | 10,000 deterministic chunking cases, zero-step defense, long jumps, engine-frame rewind, catch-up gate, 515-file length/outlier scan | All 515 files; Lily 29-frame wall-stun case retained as expected | `test_combo_demo_timing.lua` | High for cursor math | Input/action sampling during actual hitstop | `DEEPLY_ATTACKED` |
| SURFACE-B-005 | Detection adversarial | Remove, duplicate, wrong ID, swap order, timing -3/-1/+1/+3; 45 ranked real Combo candidates | 45 outliers spanning all 21 corpus characters | Expanded compiler verifier regression; 315/315 mutation verdicts matched contract | High | Exact game Action observations for synthetic wrong physical inputs | `DEEPLY_ATTACKED` |
| SURFACE-B-006 | Demo / playback / catch-up | Timeline/raw differential, long/short streams, chunking, catch-up, abort/restart, character switch, mode exit, first-frame recovery | Longest 1,665-frame and shortest 96-frame streams; native and relative paths | BUG-B005, BUG-B006; two lifecycle regressions and timing regression | High | Manual injection, visible pacing and hitstop | `DEEPLY_ATTACKED` |
| SURFACE-B-007 | State leakage / recovery | Case B after Case A, opposite-player interruption, bad load then good load, Demo stop paths, 2,000 lifecycle repeats | Generic P1/P2 plus prior BUG-B003 load fixture | BUG-B003, BUG-B004, BUG-B005, BUG-B006 | High | Scene transitions controlled by the game | `DEEPLY_ATTACKED` |
| SURFACE-B-008 | Legacy/current compatibility and serialization | Native-vs-relative stratification; fixed-time load/migrate/serialize/load/migrate; second-pass idempotence | 293 legacy native, 222 facing-relative, all 515 files | 0 mechanism drift; 0 second-pass drift | High | Cross-build Action migration still requires build evidence | `DEEPLY_ATTACKED` |
| SURFACE-B-009 | Character long tail | Canonical directory comparison, legacy oracle, command-resolution tests, generated catalog tests | 31 total; 21 real corpus; 10 synthetic/catalog only | No character hardcode added | Medium-high offline | Real Combo/gameplay for the ten missing corpus characters | `DEEPLY_ATTACKED` |
| SURFACE-B-010 | Unknown/error recovery | Unknown Action fail-closed tests, malformed stream/timeline, failed load recovery, missing catalog/renderer paths | Generic plus JP, Yasmine and generated semantic fixtures | Existing fail-closed tests plus BUG-B003 | High | Missing live generated artifact behavior | `DEEPLY_ATTACKED` |

## 14. Phase 2+ Confirmed Bugs

### BUG-B004

- Severity: P2
- Domain: `RUNTIME_STATE`, `RECORDING`
- Character: Generic; P1 and P2
- Status: `FIXED`
- Reproduction: Start recording for either player, then change either player's
  character. The UI leaves recording, but the recording player's timeline
  logger remains active and the Action compiler session and environment
  snapshots remain allocated.
- Root cause: `ct_player_init` duplicated only a subset of `cancel_recording`
  when it observed a profile change.
- Fix: Route character-change interruption through `cancel_recording`.
- Commit: `5e28a26`
- Regression: `tools/test_combo_recording_lifecycle.lua`
- Adversarial retest: All four recorder/switch-player combinations, 1,000
  repeated runs, then a fresh recording-lifecycle run.
- Architecture impact: Runtime orchestration only; no schema or authority
  change.

### BUG-B005

- Severity: P2
- Domain: `RUNTIME_STATE`, `DEMO`, `PLAYBACK`
- Character: Generic
- Status: `FIXED`
- Reproduction: Start a Demo, then change either character. The old path set
  a few booleans but retained timeline steps, cursor, countdown, current file,
  tick frame and reinjection state.
- Root cause: Character-change handling bypassed the shared
  `stop_demo_playback` lifecycle.
- Fix: Use `stop_demo_playback("character_change", ...)`.
- Commit: `7bb95cd`
- Regression: `tools/test_combo_recording_lifecycle.lua`
- Adversarial retest: P1/P2 character changes and 100 repeated recovery runs.
- Architecture impact: Runtime orchestration only.

### BUG-B006

- Severity: P2
- Domain: `RUNTIME_STATE`, `DEMO`, `TELEMETRY`
- Character: Generic
- Status: `FIXED`
- Reproduction: Exit the Combo Trials training script during a Demo, or enter
  its first-frame recovery with a stale Demo. The old path did not cancel the
  Demo telemetry attempt and retained raw/timeline playback state.
- Root cause: Mode-exit and first-frame recovery used partial field resets
  instead of the shared Demo cancellation lifecycle.
- Fix: Route both stop paths through `stop_demo_playback`.
- Commit: `2cfa8ce`
- Regression: `tools/test_combo_demo_lifecycle.lua`
- Adversarial retest: Both interruption paths, neighboring character-change
  path, telemetry checkpoint tests and 1,000 repeated runs.
- Architecture impact: Runtime orchestration only.

Phase 2+ fixed counts:

- P0: 0
- P1: 0
- P2: 3
- Confirmed but unfixed: 0
- Open P0/P1 candidates: 0

## 15. Corpus Outlier Evidence

- Files: 515 across 21 directories.
- Longest stream: 1,665 frames,
  `AKI/AKI_COMBO_DI_6699_D6_SA3.json`.
- Shortest stream: 96 frames,
  `JURI/Juri_COMBO_2MK_980_D0_SA0.json`.
- Most raw transitions: 182,
  `JAMIE/Jamie_OKI_HP_4278_D6_SA1_3.json`.
- Longest Action sequence: 35 steps, the same Jamie outlier.
- Unique sequence shapes: 475 shapes occurred once out of 494 total shapes.
- Rare masks and rare Action IDs were traced back to their source files; the
  rarest observed masks and 31 Action IDs each occurred once.
- Native side-switch files: 9. The observed orientation patterns were `RL`,
  `LR`, or `RLR`; no button bits changed under direction comparison.
- One stream-length mismatch remains the known Lily wall-stun case:
  `LILY/Lily_COMBO_DI_3060_D1_SA0.json`, raw input is 29 frames shorter than
  timeline due to the explicit missed-hook catch-up contract.

## 16. Character Coverage

Canonical character universe: 31 command-display character directories.

Real Combo corpus coverage: 21 characters:

`AKI, Akuma, Alex, Blanka, Cammy, CViper, Ed, EHonda, Elena, Guile, Jamie,
Juri, Ken, Kimberly, Lily, Luke, Manon, Marisa, MBison, Rashid, Ryu`.

No real Combo evidence in the 515-file corpus: 10 characters:

`ChunLi, DeeJay, Dhalsim, Ingrid, JP, Mai, Sagat, Terry, Yasmine, Zangief`.

Those ten were attacked only through checked-in command-display data,
character exceptions, the legacy oracle, generator fixtures and command
resolution tests. They are not reported as real-corpus covered. Live recording,
hitstop and playback behavior for those characters remains
`REQUIRES_REAL_GAME`.

## 17. Historical Regression Audit

| Historical category | Classification | Evidence |
| --- | --- | --- |
| Recording drop / repeated Action | `REGRESSION_SEALED` | Action restart/contact/compiler suites plus BUG-B004 lifecycle regression |
| Demo dropped frames / fast-forward | `REGRESSION_SEALED_OFFLINE` | New 10,000-case timing equivalence and exact missed-frame catch-up test |
| 29-frame timeline mismatch | `NO_LONGER_RELEVANT_AS_BUG` | The single Lily case is the documented wall-stun hook/catch-up difference |
| Empty or damaged Combo list | `REGRESSION_SEALED` | Multi-column list, refresh, sync signal and recoverable JSON tests |
| Extra/missing input or Action | `REGRESSION_SEALED` | Compiler tests plus 45-case real-corpus near-miss matrix |
| Detection false result | `REGRESSION_SEALED_OFFLINE` | Strict Action ID/order/count/timing verifier mutations across all corpus characters |
| Demo interruption telemetry | `FIXED_AND_SEALED_PHASE_2` | BUG-B006 |
| Win11-specific timing/runtime | `REQUIRES_REAL_GAME` | No platform-specific reproducible fixture or committed regression was found |

## 18. Test Sensitivity

Temporary deliberate defects were applied one at a time and restored before
commit:

1. Reversed the `native_to_relative` facing condition. The raw-input test
   failed on the live-facing assertion.
2. Allowed `0f` timeline rows. The strict timeline boundary assertion failed.
3. Added one frame to Demo step remaining time. The deterministic timing test
   failed at iteration 2.
4. The three lifecycle bugs were each observed red before their fixes.

Mutation result: 6/6 targeted defects were caught. No mutation remained in the
working tree or commit history.

## 19. Order, Repetition And Determinism

- Lua test files: 47/47 sorted, 47/47 reversed, 47/47 fixed-random order.
- Recording lifecycle: 1,000/1,000 repeated runs.
- Demo lifecycle: 1,000/1,000 repeated runs.
- Demo timing: 10,000 generated sequences per run.
- Raw facing transform: all 65,536 masks under both facing values.
- Detection near-miss: 45 ranked real Combo files across all 21 corpus
  characters. Base, remove, duplicate, swap, wrong ID, +1 and +3 verdicts were
  315/315 as expected; the permanent focused test also covers -1 and -3.

## 20. Phase 2+ Verification

- Lua parse: 119/119.
- Lua tests: 47/47 in three independent orders.
- Action runtime and BCM generator tests: 8/8.
- Combo JSON editor tests: 6/6.
- Python official snapshot tests: 3/3.
- Release version gate: passed.
- Serialization: 515/515; 0 mechanism drift; 0 second-pass drift.
- Real-game smoke: not available.

## 21. Marginal Yield

| Pass | New bugs | High-value regression gaps | Result |
| --- | --- | --- | --- |
| Recording/state sequence | BUG-B004 | Recording interruption lifecycle | Closed |
| Side-relative exhaustive/metamorphic | 0 | Full-mask and switch-frame coverage | Closed |
| Demo/state sequence | BUG-B005, BUG-B006 | Shared stop lifecycle and telemetry cancellation | Closed |
| Detection near-miss/corpus outliers | 0 | Duplicate and neighbor timing coverage | Closed |
| Timing mutation/order/repetition | 0 | Permanent catch-up/chunking sensitivity | Closed |
| Serialization/legacy-current differential | 0 | 0 drift across 515 files | Closed |

The final independent dimensions (mutation, order perturbation, repeated run,
serialization and cross-character catalog tests) produced no additional
confirmed bug after BUG-B006. Offline marginal yield is therefore considered
materially reduced.

## 22. Phase 2+ Handoff

Merge after the Phase 1 commits, in this order:

1. `5e28a26` - cancel recording completely on character change.
2. `7bb95cd` - cancel Demo completely on character change.
3. `2cfa8ce` - cancel Demo and telemetry on mode exit/recovery.
4. `f6baf90` - deepen raw/facing, timing and detection regressions.

The three fixes touch lifecycle orchestration in
`autorun/TrainingComboTrials_v1.0.lua` and may conflict textually with Task A
entry-script extraction. Preserve the calls to `cancel_recording` and
`ctx.stop_demo_playback`; do not reproduce their cleanup field-by-field.
