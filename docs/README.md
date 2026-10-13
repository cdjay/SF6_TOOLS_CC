# SF6CC Documentation

Status: `CURRENT`

Start with this page instead of searching dated reports.

## Current

| Need | Read |
| --- | --- |
| Project overview | [README](../README.en.md) |
| 木人库用户说明 | [木人库使用说明](../木人库使用说明.md) |
| 独立木人库维护与打包 | [Training Library](training-library/README.md) |
| Documentation precedence | [Documentation Authority](DOCUMENTATION_AUTHORITY.md) |
| Current architecture | [Architecture](../ARCHITECTURE.md) |
| Action and Move semantics | [AC+BCM Semantic Core](AC_BCM_SEMANTIC_CORE.md) |
| Frozen Combo V2 | [Combo JSON Spec](COMBO_JSON_SPEC.md) |
| Tests and release evidence | [Testing Strategy](TESTING_STRATEGY.md) |
| Current blockers | [Known Limitations](KNOWN_LIMITATIONS.md) |
| Human semantic review | [Human Review](review/HUMAN_REVIEW.md) |
| Real-game validation | [Real-game Smoke](testing/REAL_GAME_SMOKE.md) |
| Tester builds | [Tester Workflow](TESTER_WORKFLOW.md) |
| Repository assets | [Repository Governance](REPOSITORY_GOVERNANCE.md) |
| Development rules | [AGENTS](../AGENTS.md) and [Contributing](../CONTRIBUTING.md) |
| Release history | [CHANGELOG](../CHANGELOG.md) |
| Replay-review terms | [CONTEXT](../CONTEXT.md) |

## Frozen And Generated Contracts

- [Combo JSON Spec](COMBO_JSON_SPEC.md)
- [Command Display Schema](command_display_schema.md)
- [Web Character Schema](web_character_schema.md)
- [Website Data Handoff](WEB_DATA_HANDOFF.md)
- [Versioning](VERSIONING.md)
- [Combo Feedback Outbox](COMBO_FEEDBACK_OUTBOX.md)
- [Validated Combo Backup](backup/VALIDATED_COMBO_BACKUP.md)
- [Combo Attempt Telemetry](combo_attempt_telemetry.md)
- [Hit Confirm Telemetry Schema](hit_confirm_telemetry_schema.md)

## Research And Experiments

- [Combo trial scene-state research](COMBO_TRIAL_STATE_RESEARCH.md): June 2026 survey of the game fields needed to record and restore the training scene with a combo; background for later scene-state work, not a contract.
- [CFN replay state capture](research/CFN_REPLAY_CAPTURE.md): isolated, opt-in experiment; live frame coverage is not yet verified.
- [CFN review window](research/CFN_REPLAY_REVIEW_UI.md): experimental damage review, current-round filtering and pre-event navigation; pending live verification.
- [CFN user rules](research/CFN_REPLAY_USER_RULES.md): offline editor and bounded damage/guard classification rules; local experimental deployment, latest changes await live verification.
- [CFN fact/rule workbench](research/CFN_REPLAY_WORKBENCH.md): integrated frame timeline, input history and paused rule re-evaluation from fixed facts; deployed locally with separate offline/live evidence.
- [Online battle Lua capture limit](research/LIVE_BATTLE_LUA_CAPTURE_LIMIT.md): REFramework skips Lua during online matches, so live match capture is not possible; analyze matches through the offline CFN replay path.

## Historical

- [CFN replay stage checkpoint, 2026-09-21](research/CFN_REPLAY_STAGE_20260921.md): scoped implementation, configuration restoration, test evidence and remaining limits.
- [Training library development history](training-library/DEVELOPMENT_HISTORY.md): per-round changes, deployments and acceptance up to the native-eight-slot switch.
- [Training library 80-slot logs, 2026-09](archive/training-library/KNOWN_LIMITATIONS_LOG_2026-09.md) and [architecture notes](archive/training-library/ARCHITECTURE_LIBRARY_LOG_2026-09.md): verbatim logs of the retired expansion.

See [Archive](archive/README.md). Dated audit and integration documents are
evidence for past baselines only. Removed phase reports remain available in Git
history.
