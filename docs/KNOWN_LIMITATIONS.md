# Known Limitations

Status: `CURRENT`

This is the sole current list of evidence and architecture blockers. Green
offline tests do not remove these limitations.

| Limitation | Current state | Consequence |
| --- | --- | --- |
| Production authority | `Legacy` | No Runtime consumer may claim M5 or `MoveResolver` production authority. |
| M5 | Shadow only | Candidate results are diagnostic and `production_result` remains Legacy. |
| Frozen V2 | Unchanged | The `xt.combo_trial/2.0.0` schema and existing field meanings cannot be changed. |
| Human review | 179 stable-Move batches remain | No batch is approved automatically; ambiguous identities remain provisional. |
| Real-game smoke | Required, not complete | Offline tests cannot prove REFramework callback order, live game observations, input injection, or visible playback. |
| Legacy OFF | Blocked | Legacy exception loading and compatibility behavior remain required. |
| Sealed oracle | 633 cases, independence `LOW` | It proves historical snapshot integrity, not independent Runtime truth. Runtime consumers execute `0 / 633` oracle cases. |
| Real-game golden | Unavailable | There is no current high-independence golden captured from live game truth. |
| Current corpus | 965 frozen current-build files | Strong serialization and offline-consumer evidence, but not a live-game end-to-end proof. |
| Historical corpus | 2,509 exact-unique cases | Contains mixed-build data; 34 current command-display gaps are expected historical incompatibilities. |
| Frozen archive | Loose source passes; archive unavailable | Current local status is `LOOSE_SOURCE_PASS_ARCHIVE_UNAVAILABLE`; no archive PASS may be claimed. |
| External tester storage | Retention not fully adjudicated | Historical packages under local `release/tester_packages` are not current source and must not be redistributed without provenance review. |

The active review procedures are [Human Review](review/HUMAN_REVIEW.md) and
[Real-game Smoke](testing/REAL_GAME_SMOKE.md). Do not close a limitation by
editing this file alone; close the underlying evidence or architecture gate
first.

