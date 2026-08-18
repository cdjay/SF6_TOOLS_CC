# Combo Feedback Outbox

Status: `CURRENT`

SF6CC can collect an explicit user report from the Combo Trials list without
changing Frozen Combo V2. The MOD writes a bounded local JSON outbox; SF6CM
Client owns authentication, idle upload, retry, and server acknowledgement.

## Files

MOD-owned, atomically published:

```text
data/SF6_TrainingRemoteControl_data/ComboFeedback/feedback-outbox-v1.json
```

Client-owned acknowledgement:

```text
data/SF6_TrainingRemoteControl_data/ComboFeedback/feedback-ack-v1.json
```

Both are Runtime files, ignored by Git and excluded from release packages.

## Outbox

```json
{
  "schema": "sf6cc.combo_feedback_outbox.v1",
  "items": [
    {
      "schema": "sf6cc.combo_feedback.v1",
      "feedback_id": "32-lowercase-hex",
      "created_at": "2026-08-17T00:00:00Z",
      "category": "unrecognized_action_id",
      "description": "optional user text",
      "combo": {
        "combo_id": "optional immutable community id",
        "revision_hash": "sha256:...",
        "identity_schema": "sf6cc.combo_identity.v1",
        "title": "display snapshot",
        "author": "optional display snapshot",
        "character": "Ryu",
        "control_mode": "classic",
        "step_count": 8
      },
      "runtime": {
        "mod_version": "1.1.9",
        "game_build": "2026-08-03"
      }
    }
  ]
}
```

Allowed categories are:

- `unrecognized_action_id`
- `detection_error`
- `demo_error`
- `other`

The queue contains at most 100 items, descriptions contain at most 1024 UTF-8
bytes, and the complete outbox is at most 262144 bytes. Invalid existing
outbox data fails closed and is not overwritten.

## Client Protocol

The Client reads an outbox snapshot only while idle, uploads each item using
`feedback_id` as the idempotency key, and writes acknowledgements atomically:

```json
{
  "schema": "sf6cc.combo_feedback_ack.v1",
  "acknowledged_feedback_ids": ["32-lowercase-hex"]
}
```

The Client must not edit the MOD-owned outbox. It skips IDs already present in
its acknowledgement file. On the next user submission, the MOD removes
acknowledged items before appending the new report. The Client should compact
acknowledgements to IDs still present in its latest outbox snapshot.

## Privacy And Authority

The outbox contains no local path, raw input, timeline, account, machine
identity, log, or gameplay recording. Client credentials remain outside Lua.
The exact combo join key is `sf6cc.combo_identity.v1` `revision_hash`; title,
author, and step count are presentation snapshots only. Feedback never mutates
V2 and never affects recording, replay, detection, or Action semantics.
