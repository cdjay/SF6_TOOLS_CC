# Website Data Handoff

Status: `CURRENT`

This document defines the offline handoff bundle, not a new semantic authority.
The [web-character contract](web_character_schema.md) remains the authority for
`xt.character.web.v1`. The existing compiler/decoder produces all command data;
the handoff builder only projects and compares evidence. No runtime, OFF frozen
snapshot, Move approval state, or external website project is modified.

## Generate

```powershell
node tools/action_runtime_compiler/web_handoff_builder.js --old 2026-08-03 --new 2026-10-13 --corroborate 2026-10-09 --output release/sf6cmff-data-2026-10-13
node tools/action_runtime_compiler/test_web_handoff.js
```

Generate the existing `lastjson` and `lastjson_web` outputs first. Output must be
a new directory. Partial failed output has no final `manifest.json`; never use
it as a completed bundle. All bundle output remains ignored and uncommitted.

## Contents

| Path | Role |
| --- | --- |
| `manifest.json` | Completed bundle, explicit versions, roster count, relative paths, bytes and SHA256. Excludes itself. |
| `fighters.json` | Shared roster; use fighter_id, not unreliable capture names such as Fab. |
| `characters/<build>/<fighter>.json` | Existing web contract, including OFF frames and AC/BCM command tokens. |
| `commands/<build>/<fighter>.json` | Existing unified command output, copied without regeneration or new rules. |
| `official/<build>/<fighter>.json` | Same-date official snapshot used by web output. |
| `native/<build>/<fighter>.json` | AC frame/key scalars and raw BCM trigger scalars plus existing decoded profiles. |
| `differences/<old>_to_<new>/<fighter>.json` | Observed before/after field changes, including command and official move rows when web snapshots exist. |
| `differences/index.json` | Counts of changed comparison locators, not counts of confirmed balance changes. |
| `sources.json` | Absolute read-only paths, bytes and SHA256 for original AC/BCM; raw files are not duplicated. |
| `icons/` | Exact-case existing button and direction assets. |
| `contracts/` | Source/identity/schema constraints. |
| `SF6CMFF_PROMPT.md` | Ready-to-use downstream task with the actual bundle path. |

The bundle is local-machine consumable. Moving it to another machine requires
copying the raw files separately and remapping `sources.json`; it is not a
self-contained raw archive. Historical builds use their actual fighter roster;
new builds must cover the entire current shared roster.

## Comparison Contract

`sf6cc.web-native-facts.v1` preserves AC source scope, resource index, style
index, and action_id. Character and common actions do not merge. Only root,
ActionFrame and reachable CharacterAsset `*Key` scalar fields are projected;
reference payloads, boxes, hit data and other nested values are **not exhaustive**.
Use the raw originals for those. Key arrays retain traversal order; insertion
may produce shifted-index deltas rather than proven key-to-key correspondence.

`sf6cc.web-version-diff.v1` includes `native` and optional `web` changes. Each
field has `path`, `before`, `after`, and explicit presence flags. No missing
field is defaulted to zero. Native missing fields under different capture
capabilities are tagged `capture_availability_change`; other deltas are
`field_presence_change_unverified` when a field is missing on one side, or
`observed_snapshot_difference` when both values exist. None of these tags
asserts a gameplay/balance change. The index separates value changes from
presence-only changes, so newly captured fields are not counted as balance
changes merely because the exporter capability marker did not change.

Native pairing uses the same build-local locator only as a candidate. Official
rows use snapshot-local keys plus compatible internal name/category; ambiguous
pairs preserve both rows separately. All candidates have
`identity_status: not_verified` and `auto_approved: false`. This is not the
SF6ACBCM stable Move mapping and must never become a runtime migration table.

Compare actual fields, not generated timestamps or source hashes. Official
frame/notes/resource differences are separate from AC structural frames and
BCM input/condition differences. A supplemental capture comparison helps
identify exporter omissions; it does not identify the official patch date.

## Validation Boundary

Generation rejects unpaired/incomplete raw inputs, duplicate fighter/variant/
route locators, mismatching IDs, invalid web schemas, command/OFF hash mismatch,
missing current characters and version mismatch. It validates and copies
existing outputs rather than compiling semantics again. The compiled AC/BCM
source hashes must also match the actual raw files. Source checksums and
file inventory establish reproducibility, not completeness of projected native
facts or approval of cross-build move identities. Website integration and real
game verification remain downstream work.

## Nested Build Evidence Report

For a deeper read-only audit of the raw graphs behind the handoff bundle:

```powershell
node --max-old-space-size=4096 tools/action_runtime_compiler/build_change_report.js --bundle release/sf6cmff-data-2026-10-13-final --output release/acbcm-changes-0803-1013-verified
node tools/action_runtime_compiler/test_build_change_report.js
```

The output directory must not exist. This tool currently compares the explicit
2026-08-03 and 2026-10-13 captures, with 2026-10-09 as supplemental evidence.
It writes `REPORT.md` and one JSON per fighter; reports stay ignored in
`release/`. This is evidence tooling, not a new runtime semantic resolver.

Unlike the scalar handoff projection, it resolves nested AC/BCM references,
ignores capture object IDs, compares key nodes as multisets, and restricts
comparison to field names observed on both sides. Empty reflection containers
are normalized; repeated `p00_*` parameter aliases are not counted twice.
Key types present in only one capture are retained as `incomparable_keys` with
full snapshots, not confirmed gameplay additions. Added/removed action and BCM
route locators also retain full snapshots. Missing inherited timing windows
cannot be inferred from their new availability.

Same-locator differences and ID-neutral exact graph matches are review
candidates only. They do not establish stable Move identity. Cancellation
group membership is compared only when both captures preserve actual keys
and complete membership; 8.03 does not satisfy this requirement. A new trigger
key with an empty target group is not evidence of a newly usable combo.
AC/BCM captures do not include a complete attack damage table; unchanged OFF
damage rows cannot prove that every hidden damage parameter is unchanged.

The nested scanner covers `*Key` in every namespace, including
`app.battle.VfxKey` and `WindKey`, not only `CharacterAsset`. The first 0803/1013
report was narrower; its no-difference conclusions do not cover these later
presentation-layer findings. Use the deeper research output for that scope.
`tools/build_change_cards/research.js` reuses the audit and existing AC model
to retain current-build branch/shot references, unapproved LockKey parameter
references, complete current key payloads, and their available frame windows.
These are evidence paths, not a second Move resolver or runtime compiler.

Local screenshot pages and PNG generation are documented in
[`tools/build_change_cards/README.md`](../tools/build_change_cards/README.md).
Official images/names, screenshots, and research outputs remain uncommitted.
