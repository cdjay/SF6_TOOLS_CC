# Combo Telemetry Cumulative Checkpoint

Telemetry upload is eventually consistent and must not require synchronous
checkpoint durability on the SF6 realtime path. This producer is a
legacy/diagnostic aid, not an upload prerequisite or production runtime
requirement.

SF6CC continues to append the unchanged anonymous legacy stream at:

```text
data/SF6_TrainingRemoteControl_data/ComboTrialTelemetry/events.jsonl
```

The `sf6cc.combo_attempt.v1` field set and lifecycle remain independent. The
formal cumulative producer never scans, parses, probes, or depends on this
file, so normal rotation, truncation, absence, or unbounded growth cannot block
checkpoint startup.

The fixed cumulative output is:

```text
data/SF6_TrainingRemoteControl_data/ComboTrialTelemetry/cumulative-checkpoint-v1.json
```

Its schema is `sf6cc.combo_attempt_checkpoint.v1`, keyed exactly by
`(revisionHash, playerControl, positionSide)`. Only manual terminal facts enter
cumulative counters. Auto demonstrations never enter the pending journal or
state. No checkpoint file contains raw input, replay, frame streams, failure
details, paths, accounts, or machine identity.

## Legacy / Diagnostic Runtime Opt-In

The cumulative producer is opt-in at runtime and is not part of the normal
upload path. Release defaults keep
`CT_TELEMETRY_CHECKPOINT` disabled so forced write-through atomic file writes
do not run on the game thread during combo training. The `events.jsonl` stream
remains enabled and is the default external interface.

Set `_G.CT_TELEMETRY_CHECKPOINT = true` before or during a session to opt in.
The first manual terminal fact initializes the pending/state/checkpoint files;
the flag must remain enabled for checkpoint commits to continue. Disabling it
again stops further checkpoint writes without touching the legacy event
stream.

## Durable Files

The ignored local state and bounded pending slot are:

```text
data/SF6_TrainingRemoteControl_data/ComboTrialTelemetry/producer-state-v1.json
data/SF6_TrainingRemoteControl_data/ComboTrialTelemetry/producer-pending-v1.json
```

Canonical state fields are:

```json
{
  "schema": "sf6cc.combo_attempt_checkpoint_state.v1",
  "producerEpoch": "32-lowercase-hex",
  "checkpointSequence": 1,
  "historyStart": "all_time_v1",
  "lastAppliedEventId": "origin-or-64-lowercase-hex",
  "contentHash": "sha256-of-canonical-items",
  "items": [],
  "stateHash": "sha256-of-all-preceding-canonical-state-fields"
}
```

The pending file has schema `sf6cc.combo_attempt_checkpoint_pending.v1` and is
always one of two canonical states:

```json
{
  "schema": "sf6cc.combo_attempt_checkpoint_pending.v1",
  "status": "empty",
  "pendingHash": "sha256-of-preceding-fields"
}
```

or one projected manual fact containing only the existing `event_id`, combo
identity/display facts, control, side, sequence length, success/failure
outcome, and Unix timestamp. It is limited to 4096 bytes. It never stores the
legacy event body, failure details, raw input, replay, or local identity.

All state and pending reads require exact fields, canonical bytes, valid
bounds, and matching lowercase SHA-256 hashes. Malformed, missing, conflicting,
or unreadable durable files fail closed and preserve the last checkpoint.

## Commit Protocol

When the cumulative producer is enabled, for each manual terminal fact:

1. Atomically write the projected fact to `producer-pending-v1.json`.
2. Attempt the unchanged legacy `events.jsonl` append and check the returned
   write, flush, and close results.
3. Atomically apply the fact to cumulative state and set
   `lastAppliedEventId`.
4. Atomically publish the checkpoint.
5. Atomically replace pending with its canonical empty state.

The legacy append is best-effort and independent. A returned write, flush, or
close failure is reported through the existing telemetry result, but a fact
already protected by pending still commits to cumulative state. A pending
write failure prevents counting and blocks that producer instance; gameplay
and the legacy append attempt remain isolated from the error.

On restart, an empty pending file only triggers normal state/checkpoint
validation. A pending event whose ID is not `lastAppliedEventId` is applied
once. A matching ID means state already committed it, so checkpoint recovery
and pending clear proceed without recounting. State-write, checkpoint-write,
and pending-clear crashes therefore converge deterministically. A malformed or
conflicting pending file fails closed.

## Atomic Bridge

`plugins/reframework-sf6cc-atomic-file.dll` accepts the three fixed telemetry
JSON paths above plus the separately documented fixed combo-feedback outbox.
Its tri-state probe classifies only Win32 file/path-not-found as `missing`;
ACL, sharing, and other failures return errors.

Each write uses a unique same-directory temporary file, complete write,
`FlushFileBuffers`, close, and `MoveFileExW` with replace-existing and
write-through flags. Failure removes only the temp and never truncates the
previous destination. The epoch is generated with Windows `BCryptGenRandom`
only when a new empty pending/state/checkpoint set is initialized.
