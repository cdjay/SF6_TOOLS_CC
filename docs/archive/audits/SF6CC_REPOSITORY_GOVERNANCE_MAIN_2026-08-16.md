# SF6CC Repository Governance Main Baseline

Status: `HISTORICAL`

## Baseline

- Previous Main: `2d783181de6b6357c276e0d4ee11fce26f33e8a9`
- Validated Main before this report: `f68fbbac34fbf5356199e48c9d821e985a5ef3f7`
- Worker baseline: `2d783181de6b6357c276e0d4ee11fce26f33e8a9`
- Worker HEAD: `b91ca08a1a16e38c2694f057b9513a1824963980`

## Integration

Accepted in order:

- `60bcf7d` - long-term corpus/audit tool names and generated-output policy;
- `35507cb` - current documentation authority and operational entry points;
- `92eaa5f` - historical archive and phase-noise removal;
- `e7d75c3` - removal of Task C labels from reusable audit output;
- `b91ca08` - completion-token cleanup.

Main review edits in `f68fbba`:

- corrected the Markdown baseline from 63 to 61;
- made README point to the complete offline gate;
- retained B001-B006 failure and correction semantics;
- retained D2D, whitelist, native bridge, and DynamicRecords boundaries;
- restored an executable 179-batch review rebuild procedure;
- marked real-game smoke blocked pending a reviewed shadow harness;
- defined tester-package currentness by source SHA and package hash;
- removed the superseded 221-line Worker handoff report.

Deferred, non-blocking work:

- external tester-package retention decision;
- reviewed live shadow harness;
- 179 human semantic-review batches;
- RG-01 through RG-06 real-game evidence.

## Runtime Boundary

- Runtime/product files changed by Worker integration: `0`.
- Runtime behavior: unchanged.
- Production authority: `Legacy`.
- M5 / MoveResolver: shadow only.
- Frozen V2: unchanged.
- Legacy OFF: blocked.

## Validation

- Test inventory: `70`; executable files: `69 / 69 PASS`.
- Lua parse: `127 / 127 PASS`.
- BUG-B001 through BUG-B006: PASS.
- Sealed oracle: `633 / 633`; independence remains `LOW`.
- Current corpus: `965 / 965`, normal and reverse, zero roundtrip/consumer failures.
- Historical exact-unique: `2,509 / 2,509`, normal and reverse, zero roundtrip failures.
- Historical consumer findings: `34`, unchanged mixed-build display gaps.
- Fresh-process and same-process order: PASS.
- Current and historical determinism: PASS.
- Mutation: `4 / 4` killed.
- Frozen archive: `LOOSE_SOURCE_PASS_ARCHIVE_UNAVAILABLE`.
- Markdown broken links: `0`.
- `git diff --check`: PASS.

## Repository State

- Final tracked files after this report: `493`.
- Final Markdown documents after this report: `56`.
- Human Review and Real-game Smoke remain active pending assets.
- External tester packages remain outside Git and were not deleted or imported.
- The protected Blanka Type63/performance-cache stash remained untouched.

This report records a knowledge-governance integration. It is not current
architecture authority and does not authorize a release or production switch.
