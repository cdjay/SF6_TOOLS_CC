# Documentation Authority

Status: `CURRENT`

This document is the sole index for deciding which SF6CC documents are current
authority. A dated report, completion report, audit snapshot, or file under
`docs/archive/` is never current authority unless this table explicitly says
otherwise.

## Status Precedence

| Priority | Status | Meaning |
| --- | --- | --- |
| 1 | `CURRENT` | Active operational or architecture authority. It must match the repository. |
| 2 | `FROZEN_SPEC` | Immutable authority inside its explicitly versioned schema domain. |
| 3 | `DESIGN` | Proposed or research direction. It does not describe implemented production state. |
| 4 | `HISTORICAL` | Past-state evidence retained to explain decisions or reproduce a baseline. |
| 5 | `ARCHIVE` | Reference only. It has no current authority. |

Within a domain, use the single document named below. A more specific frozen
schema overrides a general architecture document only for that schema.

## Current Authority Map

| Topic | Current authority | Boundary |
| --- | --- | --- |
| Project overview and entry points | [README](../README.en.md) | Short project and contributor entry; not a detailed architecture contract. |
| AI/repository workflow | [AGENTS.md](../AGENTS.md) | Mandatory contributor, release, architecture, and repository rules. |
| Current architecture and production state | [ARCHITECTURE.md](../ARCHITECTURE.md) | Legacy is production authority; M5 remains shadow-only. |
| Move/Action identity and AC/BCM semantics | [AC+BCM Semantic Core](AC_BCM_SEMANTIC_CORE.md) | Current-build Action semantics, stable Move identity, resolver boundary, and exception rules. |
| Frozen Combo V2 | [Combo JSON Spec](COMBO_JSON_SPEC.md) | `xt.combo_trial/2.0.0` is immutable. |
| Testing and release evidence | [Testing Strategy](TESTING_STRATEGY.md) | Test layers, official commands, gates, counts, and evidence meaning. |
| Known limitations and blockers | [Known Limitations](KNOWN_LIMITATIONS.md) | Human review, smoke, oracle, archive, M5, and Legacy blockers. |
| Human semantic review | [Human Review](review/HUMAN_REVIEW.md) | Active 179-batch review packet; review input only. |
| Real-game validation | [Real-game Smoke](testing/REAL_GAME_SMOKE.md) | Active RG-01 through RG-06 procedure and required evidence. |
| Tester package workflow | [Tester Workflow](TESTER_WORKFLOW.md) | Generate, identify, verify, distribute, and roll back tester builds. |
| Repository assets and generated files | [Repository Governance](REPOSITORY_GOVERNANCE.md) | Asset classification and retain/generate/archive policy. |
| Product version | [Versioning](VERSIONING.md) | `data/SF6CC/version.json` is the only product-version source. |
| Command-display JSON | [Command Display Schema](command_display_schema.md) | `xt.command_display.v1` transport/schema contract. |
| Web-character JSON | [Web Character Schema](web_character_schema.md) | `xt.character.web.v1` transport/schema contract. |
| Writable product defaults | [Writable Product Data](WRITABLE_PRODUCT_DATA.md) | Current mixed product-default/runtime-write boundary and its risks. |
| Combo action transcription | [Combo Action Transcription](COMBO_ACTION_TRANSCRIPTION.md) | Current recording/transcription and audit workflow. |
| Combo telemetry checkpoint | [Combo Telemetry Checkpoint](COMBO_TELEMETRY_CHECKPOINT.md) | Current durable checkpoint protocol. |
| Validated combo backup | [Validated Combo Backup](backup/VALIDATED_COMBO_BACKUP.md) | Recovery procedure; the tracked manifest is exact identity authority. |

`VISION.md` and `ROADMAP.md` are `DESIGN` documents. They describe direction,
not current production behavior. Research documents are authoritative only for
the experiment they describe.

## Current Operational Baseline

The following statements are binding until the current authority documents are
deliberately updated together:

- Production authority: `Legacy`.
- M5 / `MoveResolver`: shadow-only diagnostics.
- Frozen V2: unchanged and immutable.
- Legacy OFF: blocked.
- Stable Move review: 179 human-review batches remain unapproved.
- Real-game smoke: required and not complete.
- Sealed 633-case oracle: historical integrity evidence with low independence.
- Current high-independence real-game golden: unavailable.

## Historical Material

Historical documents live under [the archive index](archive/README.md). They
may contain accurate statements about their recorded commit and date, but they
must not be used to answer current-state questions. Git history is the archive
for phase reports that had no lasting decision or reproducibility value.
