# Combo Telemetry Cumulative Checkpoint

SF6CC continues to append the legacy anonymous practice stream at:

```text
data/SF6_TrainingRemoteControl_data/ComboTrialTelemetry/events.jsonl
```

Manual terminal practice facts from that same producer also update the fixed
cumulative checkpoint:

```text
data/SF6_TrainingRemoteControl_data/ComboTrialTelemetry/cumulative-checkpoint-v1.json
```

The published schema is `sf6cc.combo_attempt_checkpoint.v1`. Its key is exactly
`(revisionHash, playerControl, positionSide)`, where `revisionHash` and
`identitySchema` come from `sf6cc.combo_identity.v1`. Auto demonstrations do
not update cumulative counters. The checkpoint contains no raw input, replay,
frame stream, failure details, path, account, or machine identity.

The legacy `sf6cc.combo_attempt.v1` JSON field set is unchanged. A terminal
event is appended and flushed first; only a successful append is eligible for
the cumulative producer. `events.jsonl` is therefore the write-ahead fact
source, while the checkpoint remains the bounded cumulative projection.

## Durable Local State

The ignored local producer state is:

```text
data/SF6_TrainingRemoteControl_data/ComboTrialTelemetry/producer-state-v1.json
```

Its canonical, single-line UTF-8 format is:

```json
{
  "schema": "sf6cc.combo_attempt_checkpoint_state.v1",
  "producerEpoch": "32-lowercase-hex",
  "checkpointSequence": 1,
  "historyStart": "all_time_v1",
  "baselineCursor": "origin-or-legacy-event-id",
  "legacyCursor": "origin-or-last-applied-event-id",
  "contentHash": "sha256-of-canonical-items",
  "items": [],
  "stateHash": "sha256-of-all-preceding-canonical-state-fields"
}
```

The actual file has no formatting whitespace. `items` use the checkpoint item
contract and fixed field order. Both hashes are lowercase SHA-256 hex without a
prefix. State loading requires exact fields, valid bounds, sorted unique keys,
matching hashes, and byte-for-byte canonical encoding. A corrupt state, or an
existing checkpoint with no provable state, fails closed: SF6CC keeps legacy
events and does not publish a reset epoch or lower counters.

On first installation, pre-existing valid legacy events establish an explicit
`all_time_v1` baseline at the current last `event_id`; those older events are
not counted. Afterwards every successfully appended event advances
`legacyCursor`; only manual success/failure events change counters and
`checkpointSequence`. Auto demonstrations advance the cursor without changing
checkpoint content.

Startup reads at most 16 MiB and 100,000 complete lines from the current
`events.jsonl`. It must find the stored cursor, then replays later valid events
exactly once before publication. A missing cursor after rotation/truncation, an
incomplete or malformed later line, or an unusable manual fact permanently
fails closed and preserves the last checkpoint. If both state and checkpoint
are explicitly removed, a new epoch may establish a new baseline.

The epoch is generated once from Windows `BCryptGenRandom` only when both state
and checkpoint are absent. After the legacy append succeeds, the updated state
is written first and then the checkpoint is published. A crash before the state
write is recovered from the WAL; a crash between state and checkpoint writes
leaves the old valid checkpoint in place and republishes the proven state on
the next load.

## Atomic Publication

`plugins/reframework-sf6cc-atomic-file.dll` writes only the two JSON paths above
and may probe those paths plus the fixed legacy `events.jsonl` path.
Its tri-state native probe classifies only Win32 file/path-not-found as
`missing`; access, sharing, and other probe failures block the producer without
generating an epoch or writing either file.
For each write it creates a unique same-directory temp file, writes all bytes,
flushes and closes the handle, and calls `MoveFileExW` with replace-existing and
write-through flags. A failure removes the temp and never truncates the prior
destination. Producer failures are logged and isolated from gameplay.
