# Documentation Authority

This document defines the documentation authority hierarchy for SF6CC and establishes the canonical identity contract for Action IDs, Move UIDs, and related semantic entities.

All AI and human contributors must resolve documentation conflicts using the rules below.

---

## Documentation Status Hierarchy

When two documents disagree, the higher-tier document wins.

| Priority | Tier | Label | Meaning |
|---|---|---|---|
| 1 (highest) | `CURRENT` | Current Architecture Contract | Active, approved, and binding. Must not conflict with reality. |
| 2 | `FROZEN_SPEC` | Frozen Schema Specification | Immutable schema or format specification. Versioned and sealed. |
| 3 | `DESIGN` | Design / Research | Accepted design direction, but not yet fully implemented. May describe future state. |
| 4 | `STALE` | Stale -- Needs Update | Was once accurate. Contains claims that are no longer true. Must be fixed or reclassified. |
| 5 | `HISTORICAL` | Historical Record | Snapshot of past state. Retained for audit trail. Not binding. |
| 6 (lowest) | `ARCHIVE` | Archived | Retained for reference only. May be moved out of primary documentation. |

### How to Apply the Hierarchy

1. If a `CURRENT` document contradicts a `DESIGN` document, `CURRENT` wins. The `DESIGN` document should be updated or reclassified as `STALE`.
2. If a `FROZEN_SPEC` contradicts a `CURRENT` document within the Frozen spec's explicitly versioned format or compatibility domain, the `FROZEN_SPEC` is authoritative for that domain. The `CURRENT` document must be corrected. A `FROZEN_SPEC` does not overrule `CURRENT` documents in unrelated architectural domains.
3. If two `CURRENT` documents conflict, the more specific document wins for its domain. If both cover the same domain, the conflict is a governance defect and must be escalated.
4. `STALE` documents have no authority. They are warnings that need attention.
5. `HISTORICAL` documents describe past state only. Do not cite them as current architecture authority.

---

## Current Status of Key Documents

| Document | Status | Notes |
|---|---|---|
| [AGENTS.md](../AGENTS.md) | `CURRENT` | AI development guide and mandatory architecture constraints |
| [ARCHITECTURE.md](../ARCHITECTURE.md) | `CURRENT` | Overall architecture |
| [VISION.md](../VISION.md) | `CURRENT` | Long-term vision |
| [ROADMAP.md](../ROADMAP.md) | `CURRENT` | High-level roadmap |
| [AC+BCM Semantic Core](AC_BCM_SEMANTIC_CORE.md) | `CURRENT` | Architecture contract for character action data |
| [Documentation Authority](DOCUMENTATION_AUTHORITY.md) | `CURRENT` | This document |
| [COMBO_JSON_SPEC.md](COMBO_JSON_SPEC.md) | `FROZEN_SPEC` | `xt.combo_trial/2.0.0` schema 2 |
| [command_display_schema.md](command_display_schema.md) | `CURRENT` | `xt.command_display.v1` schema |
| [web_character_schema.md](web_character_schema.md) | `CURRENT` | `xt.character.web.v1` schema |
| [VERSIONING.md](VERSIONING.md) | `CURRENT` | Version truth source rules |
| [WAEL_HANDOVER_CONVERGENCE_AUDIT.zh-CN.md](WAEL_HANDOVER_CONVERGENCE_AUDIT.zh-CN.md) | `HISTORICAL` | 2026-07-23 handover audit snapshot |
| [WAEL_MERGE_ASSESSMENT.md](WAEL_MERGE_ASSESSMENT.md) | `HISTORICAL` | 2026-07-23 merge assessment snapshot |
| [REGRESSION_BASELINE.md](REGRESSION_BASELINE.md) | `HISTORICAL` | 2026-07-02 regression snapshot |
| [IMGUI_TEXTURE_BRIDGE_AUDIT.md](IMGUI_TEXTURE_BRIDGE_AUDIT.md) | `DESIGN` | One-time audit |
| [COMBO_TRIAL_STATE_RESEARCH.md](COMBO_TRIAL_STATE_RESEARCH.md) | `DESIGN` | Research document |
| [PERFORMANCE_AUDIT.md](../PERFORMANCE_AUDIT.md) | `DESIGN` | One-time audit |
| [design-qa.md](../design-qa.md) | `STALE` | Near-empty, content unclear |

---

## Canonical Identity Contract

### Action ID

An **Action ID** is a numeric identifier assigned by the current game build to a specific action node in the AC (Action Catalog) and BCM (Battle Command Manager) data.

- **Scope**: single game build only.
- **Stability**: not guaranteed across game versions. Capcom may reassign, insert, remove, or reorder Action IDs between builds.
- **Authority**: the current game's AC and BCM dumps.
- **Usage in SF6CC**: Action IDs are used internally for recording, detection, display, and audit. They are public in current-build Runtime artifacts (command display, web character data), but always qualified by game build version.

Action IDs must never be used as cross-version move keys. They are build-scoped technical identifiers.

### move_uid

A **move_uid** is a stable, cross-version identifier for a game move, defined and maintained by SF6CC/SF6ACBCM.

- **Scope**: across game versions.
- **Stability**: designed to survive Action ID reassignment, insertion, and removal across builds.
- **Authority**: SF6ACBCM identity/migration workspace (SQLite).
- **Usage**: offline migration of historical combo data, cross-version move comparison, and audit.

move_uid is not an Action ID. It is not a BCM command. It is not a web record key. It is the canonical stable entity for a Street Fighter 6 move.

### BCM Command

A **BCM command** is a command representation from the Battle Command Manager data.

- **Scope**: current game build.
- **Role**: provides command routes (norm/easy/sprt/supr) and control-type projections for Action IDs.
- **Authority**: the current game's BCM dump.

A BCM command is a route projection, not a move identity. It describes how an Action is executed via different control schemes. It is not equivalent to a move_uid.

### AC (Action Catalog)

The **AC** is the current game's Action semantic graph and relation authority.

- Defines action types, attributes, parent-child relations, cancel chains, and internal phase structure.
- Is the sole authority for action relationships within a single game build.
- OFF data may provide names or review hints, but must not bind or override AC structure.

### BCM (Battle Command Manager)

The **BCM** is the complete command catalog and route authority for the current game build.

- Provides Classic, Modern Simple, and Modern Motion input projections for each Action.
- Defines command entry conditions and resource requirements.

### SQLite (SF6ACBCM)

The **SQLite** database is the identity, migration, and audit workspace for SF6ACBCM.

- Stores move_uid definitions, version-to-version Action ID mappings, and migration evidence.
- Is not a second source of game facts. It derives from AC/BCM dumps and cross-references them across versions.
- Runtime SF6CC does not read SQLite directly.

### Current Runtime Artifact

A **Current Runtime Artifact** (e.g., `command_display/*.json`, `lastjson_web/*.json`) contains data for the current game build only.

- Action IDs in these artifacts are valid only for the annotated game build.
- These artifacts are projections of current AC/BCM data, not move_uid registries.
- Do not treat a Runtime artifact as a cross-version identity store.

### OFF Data

**OFF** data (Capcom official frame data, website snapshots) provides move names, frame data, damage, and category hints.

- OFF data is display, naming, and audit evidence.
- OFF data must not bind game Action IDs.
- OFF move indices or web IDs are Capcom's presentation keys, not SF6CC move_uids.

### web Move ID

The `web:<id>:<occurrence>` key in `xt.character.web.v1` is a current-snapshot record key for web character data.

- It identifies a Capcom official website entry within a single character snapshot.
- It is not a move_uid. It is not a cross-version authority.
- It repeats across characters (same `official_web_id` may appear on different characters).

### command_display Override

The `command_display_overrides/*.json` files are temporary display patches.

- They are evidence-backed Runtime audit fixes, not a second semantic authority.
- Every override entry must carry evidence. Override entries must not replace generated entries without evidence.
- The long-term goal is to eliminate overrides by fixing the generator, not to grow the override layer.

### Exception Tables

The `exceptions/*.json` files define Runtime behavior rules (charge windows, input holds, absorb IDs, force matches, ignore frames).

- Exceptions are Runtime behavior facts that cannot currently be derived from AC/BCM alone.
- Every exception must be evidence-backed, measurable, and explainable.
- Exceptions must not hide generator defects. When a generator defect is fixed, the corresponding exception must be retired.

---

## Conflict Resolution Examples

### Example 1: Action ID Stability

If a document claims "Action IDs are stable across versions", and [AC+BCM Semantic Core](AC_BCM_SEMANTIC_CORE.md) (`CURRENT`) says "Action IDs are version-scoped technical identifiers", the `CURRENT` contract wins. The conflicting document is `STALE` and must be corrected or reclassified.

### Example 2: move_uid vs web Move ID

If code or documentation conflates `web:<id>:<occurrence>` with `move_uid`, this document (`CURRENT`) is the authority: they are distinct entities with different scopes and stability guarantees.

### Example 3: OFF vs AC

If OFF data suggests a move name or category that contradicts AC structure, AC is the authority for action relationships. OFF is naming evidence, not structural authority.

---

## Mandatory Architecture Constraints (Reaffirmed)

The following constraints are restated here as the documentation-level authority. They are also enforceable through [AGENTS.md](../AGENTS.md).

> The current game's AC and BCM data are the only authority for character action relations, Action relations, and command routes.
>
> Action IDs are version-scoped technical identifiers, not cross-version move keys.
>
> The stable domain entity is a Move; Actions are version-specific bindings.
>
> Recording, detection, display, and audit must use one semantic resolver.
>
> OFF data, display overrides, exception tables, and historical mappings must not become a second semantic authority.

See [AC+BCM Semantic Core](AC_BCM_SEMANTIC_CORE.md) for the complete contract.

---

## Change Procedure

1. When adding a new document, assign it a status tier from the hierarchy above.
2. When changing a `CURRENT` or `FROZEN_SPEC` document, review whether the change invalidates any other document. If it does, reclassify or update the affected documents in the same commit or a linked follow-up.
3. When reclassifying a document (e.g., `CURRENT` to `STALE`), add a dated note at the top explaining the reclassification and pointing to the replacement document.
4. Do not silently delete or rewrite historical documents. Reclassify them and add a redirection note.

---

## Validation

Before merging any change that touches documented contracts:

- Run `rg "Action ID.*稳定身份" docs/` and verify no results (except in this document and explicitly marked `STALE`/`HISTORICAL` documents).
- Verify that all markdown links in modified documents resolve to existing files.
- Confirm that no `CURRENT` document makes a claim contradicted by a higher-tier document.
