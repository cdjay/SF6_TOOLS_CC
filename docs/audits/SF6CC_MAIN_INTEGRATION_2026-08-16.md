# SF6CC A/B/C Main Integration

Date: 2026-08-16

## Baseline

- Previous Main: `1fd27f95ade064a54b789153a492df505497af57`
- Integrated code/test baseline: `d0a38a8e809fb32c562e8ebf300b24b8342c5f8a`
- Integration branch: `master`
- Production authority: `Legacy / unchanged`
- M5: `Shadow only`
- Frozen V2: `UNCHANGED`
- Legacy OFF: `BLOCKED`
- Human review: `REQUIRED`
- Real-game smoke: `REQUIRED`

The report commit follows the integrated code/test baseline above. No release,
package, push, production switch, stable Move approval, or Legacy shutdown was
performed.

## Task B

All Task B commits were integrated in source order.

| Original | Main | Decision |
| --- | --- | --- |
| `aa3f2a5` | `6becaf1` | strict all-or-nothing timeline parser |
| `fe822b4` | `5e4e71e` | idempotent multi-stage chord normalization |
| `f9b46f1` | `bf0cbd1` | atomic failed Combo loading |
| `c2ab407` | `a6b9434` | Phase 1 evidence report |
| `5e28a26` | `2705041` | recording cancellation lifecycle |
| `7bb95cd` | `657c02a` | character-change Demo cancellation |
| `2cfa8ce` | `d80689f` | mode-exit and first-frame Demo cancellation |
| `f6baf90` | `da7d0d4` | lifecycle/timing/facing regression expansion |
| `5d3d431` | `7a8e26d` | final Task B report |

Deferred Task B commits: none.

The final main entry retains the complete shared lifecycle calls:

- `cancel_recording()` on recording interruption;
- `ctx.stop_demo_playback("character_change", ...)`;
- `ctx.stop_demo_playback("training_mode_exit", ...)`;
- `ctx.stop_demo_playback("first_frame_recovery", ...)`.

## Task C

`c44364f` was integrated as `42eb201`; it changes test isolation only.

Task C tools, four human-readable evidence reports, and the compact final
evidence ledger were selected into `59db0d0`. The Task C branch was not merged
wholesale.

The following reproducible machine outputs were intentionally excluded from
main:

- `phase1-evidence.json`;
- full/all-accessible corpus audit, consumer, and roundtrip JSON;
- determinism and mutation run JSON.

They contain machine-local paths and large generated run output. They remain
available in Task C history and can be regenerated with the integrated tools;
they are not Runtime data or production authority.

## Task A

All Task A source commits were integrated after B and C.

| Original | Main | Decision |
| --- | --- | --- |
| `43ba98f` | `284b418` | MoveResolver and structured shadow comparison |
| `9b98273` | `20fc515` | private resolver state |
| `e8201d4` | `7ade94d` | Phase 1 architecture evidence |
| `fa17322` | `61dde77` | parallel-worktree provenance |
| `6e2eccb` | `4e7ed65` | deterministic Phase 2 analyzer |
| `583d457` | `97656e9` | ChargeRuntimePolicy and MotionPresentation extraction |
| `18b5fc1` | `6f4d4f0` | exhaustive offline classification and benchmark |
| `a27cc62` | `a8bd661` | final review and real-game smoke packets |

Task A does not load MoveResolver from the main entry and does not route any
production result through M5. `MoveResolverShadow` remains diagnostic-only and
reports `production_result = legacy`.

The Action 1231 presentation rule remains a hand-authored display-only rule. It
was moved out of ImGui, but was not reclassified as generated semantic truth.

## Conflict Resolutions

1. Task A entry extraction was applied after Task B. Textual auto-merge was
   followed by semantic verification that all B lifecycle cleanup calls remain.
2. Task C was integrated by asset class. Reproducible tools and compact reports
   entered main; large generated run dumps did not.
3. `MoveResolver.resolve_action()` now returns a deep copy of build metadata so
   one diagnostic consumer cannot mutate later shadow provenance.
4. The B file-load regression and completion-display regression now save and
   restore `package.loaded` and REFramework globals. Same-process reverse-order
   execution is clean.
5. Python tool bytecode/cache directories are ignored and do not become Git or
   release assets.

## Regression

- Main-entry local guard: `164`, with `36` remaining below the hard limit.
- Final test inventory: `70`, failures: `0`.
- Focused B parser/load/lifecycle/timing tests: PASS.
- Focused A resolver/policy/presentation and Node analyzer tests: PASS.
- Lua/Node/Python/release gates through Task C Phase 1 runner: PASS.
- Sealed character exception Oracle: `633 / 633`, unchanged.
- Current frozen corpus: `965 / 965`, normal and reverse order; roundtrip
  failures `0`, consumer failures `0`.
- Historical exact-unique corpus: `2509 / 2509`, normal and reverse order;
  roundtrip failures `0`.
- Historical consumer findings: `34`, identical to the original Task C
  baseline. They are mixed-build command-display gaps, not new integration
  regressions.
- Fresh-process normal/reverse/seeded order: PASS.
- Same-process forward/reverse Lua order: PASS.
- Frozen and all-accessible semantic determinism: PASS.
- Mutation sensitivity: `4 / 4` injected defects killed.

The frozen loose source passed its manifest identity check. The default local
audit path did not contain the expected archive copy, so archive validation
remains `LOOSE_SOURCE_PASS_ARCHIVE_UNAVAILABLE`; no archive PASS is claimed.

## Deferred Work

- 179 stable Move review batches and related semantic/migration decisions;
- real-game smoke packet RG-01 through RG-06;
- M5 production authority switch;
- Legacy OFF;
- historical mixed-build command-display remediation;
- unrelated pre-integration Blanka Type63/performance-cache work preserved in
  a named local stash and excluded from this integration.

## Final

`SF6CC_MAIN_INTEGRATION_COMPLETE`

