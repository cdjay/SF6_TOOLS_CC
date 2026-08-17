# Combo Attempt Telemetry

SF6CC records anonymous combo-attempt outcomes for a future tray uploader. The
Lua runtime does not access the network and does not store usernames, account
IDs, authentication tokens, or full player inputs.

## Realtime Path Contract

Telemetry upload is eventually consistent and must not require synchronous
checkpoint durability on the SF6 realtime path. The MOD is a raw event
producer only: it appends facts cheaply to `events.jsonl` and returns to the
game. Aggregation, Checkpoint rebuilding, upload offset, retry, and retention
are Client/tray responsibilities.

The legacy cumulative checkpoint is diagnostic-only, disabled by default, and
must not be treated as an upload prerequisite. `events.jsonl` carries the
fields needed to rebuild it offline: `event_id` for idempotence,
`occurred_at`/`started_at` timestamps, combo identity (`revision_hash`,
`combo_id`, character, title, `sequence_length`, `declared_control`), runtime
dimensions (`player_control`, `position_side`, `source`, `projection`,
`position_mode`, `demo_kind`, `sf6cc_version`), and terminal `result.outcome`.

## Client Responsibilities (Future)

SF6CMFF Client must consume the raw `events.jsonl` spool without depending on
MOD-generated checkpoint files. It owns offline aggregate/Checkpoint rebuild,
upload offset, delayed and batched upload, retry, and retention. Uploads may
happen minutes, days, or game sessions later and should prefer game idle or
exited states.

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
    "position_mode": "original",
    "position_side": "p1",
    "projection": "none",
    "sf6cc_version": "1.2.3",
    "source": "manual"
  },
  "schema": "sf6cc.combo_attempt.v1",
  "started_at": "2026-07-22T15:19:57Z"
}
```

Fields whose values are unavailable are omitted rather than written as JSON
`null`.

`runtime.sf6cc_version` is read from the canonical
`data/SF6CC/version.json` product version; it is not maintained separately by
the telemetry modules.

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
+ position_side
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
`DEMO INCOMPLETE`. Manual stops, trial changes, scene exits and unsupported
demonstrations cancel the active attempt without emitting a success/failure
event and must not affect the health rate.

## Position split

`position_mode` preserves the MOD selection: `any`, `original`, or `mirror`.
`position_side` is the aggregation-friendly side: original position is `p1`,
mirror position is `p2`, and any position uses the player's actual starting
side. Public and per-user success rates should be split by `position_side`.
