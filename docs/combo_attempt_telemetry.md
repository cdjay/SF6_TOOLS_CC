# Combo Attempt Telemetry

SF6CC records anonymous combo-attempt outcomes for a future tray uploader. The
Lua runtime does not access the network and does not store usernames, account
IDs, authentication tokens, or full player inputs.

## Runtime file

Events are appended as UTF-8 JSON Lines to:

```text
data/SF6_TrainingRemoteControl_data/ComboTrialTelemetry/events.jsonl
```

The path is runtime state and is ignored by Git. It must not be included in a
release package. A future tray uploader may atomically rotate this file, upload
the completed batch, and delete it only after the server acknowledges every
`event_id`.

## Event contract

Each line is one `sf6cc.combo_attempt.v1` object. One event is emitted when an
attempt first reaches `success` or `fail`. Repeated animation frames do not emit
duplicates. Manual training and automatic demonstrations use distinct `source`
values.

```json
{
  "anonymous": true,
  "combo": {
    "character": "Ryu",
    "combo_id": "optional-site-uuid",
    "declared_control": "classic",
    "identity_schema": "sf6cc.combo_identity.v1",
    "local_filename": "example.json",
    "revision_hash": "sha256:...",
    "sequence_length": 4,
    "title": "Example"
  },
  "event_id": "...",
  "occurred_at": "2026-07-22T15:20:00Z",
  "result": {
    "elapsed_frames": 180,
    "failure_code": "combo_dropped",
    "failure_reason": "COMBO DROPPED",
    "outcome": "fail",
    "reached_step": 3,
    "total_steps": 4
  },
  "runtime": {
    "demo_kind": null,
    "player_control": "classic",
    "projection": "none",
    "sf6cc_version": "0.99",
    "source": "manual"
  },
  "schema": "sf6cc.combo_attempt.v1",
  "started_at": "2026-07-22T15:19:57Z"
}
```

Fields whose values are unavailable are omitted rather than written as JSON
`null`.

## Combo identity

`combo_id` is optional and reserved for an immutable UUID assigned by the site.
Existing or local combos are identified by `revision_hash`. The hash is computed
from canonicalized gameplay content and excludes mutable labels such as title,
author, notes, upload dates, filenames, and runtime validation state. Changing a
step or training environment changes the hash; renaming the same combo does not.

The server should aggregate exact revisions by:

```text
combo_id or revision_hash
+ revision_hash
+ player_control
+ runtime.source
+ compatible game/mod version
```

The uploader should authenticate independently. The server must derive the
account identity from that authenticated request instead of trusting a username
inside the telemetry event.

## Automatic demonstration health

An automatic demonstration emits one event per completed playback cycle. A
cycle succeeds only when validation reaches the end of the sequence without a
failure state. An incomplete cycle is recorded as `fail` with
`DEMO INCOMPLETE`. Manual stops and unsupported demonstrations do not emit a
success/failure event and must not affect the health rate.
