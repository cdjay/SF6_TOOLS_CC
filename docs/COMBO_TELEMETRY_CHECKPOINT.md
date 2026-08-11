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

The epoch is generated once from Windows `BCryptGenRandom` only when both state
and checkpoint are absent. Every changed cumulative item set is written to
state first with the next sequence, then published as the checkpoint. A crash
between those writes leaves the old valid checkpoint in place; the next load
republishes the newer proven durable state without changing its epoch or
sequence.

## Atomic Publication

`plugins/reframework-sf6cc-atomic-file.dll` accepts only the two paths above.
For each write it creates a unique same-directory temp file, writes all bytes,
flushes and closes the handle, and calls `MoveFileExW` with replace-existing and
write-through flags. A failure removes the temp and never truncates the prior
destination. Producer failures are logged and isolated from gameplay.
