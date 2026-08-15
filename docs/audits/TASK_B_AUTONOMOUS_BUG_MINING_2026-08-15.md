# Task B - SF6CC Autonomous Bug Mining

## 1. Final State

Offline mining state: `COMPLETE`

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
