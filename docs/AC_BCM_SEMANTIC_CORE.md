# AC+BCM Unified Action Semantic Core

Status: CURRENT Architecture Contract

Language: [简体中文](AC_BCM_SEMANTIC_CORE.zh-CN.md)

This document defines the architectural contract for character action data in SF6CC. The Chinese version is the normative working document for the current migration.

The repository maintains three infrastructure tracks:

1. Decouple `autorun/TrainingComboTrials_v1.0.lua` so it remains a composition root.
2. Generate one AC+BCM-driven character move graph consumed by recording, detection, display, and audit.
3. Keep architecture and AI constraints versioned and enforceable.

The current game's AC and BCM dumps are the authority for Action relations and command routes. OFF data may provide names or review hints, but must not bind game Action IDs. Action IDs are version-scoped technical identifiers; the stable domain entity is a `Move` with version-specific Action bindings.

The target generated contract is `xt.character_move_graph.v1`. Lua exposes one semantic service, tentatively `MoveResolver`, for action resolution, input resolution, ownership, internal-phase classification, matching, and command projection.

Display overrides, permanent runtime compatibility maps, and character-specific Action-ID branches must not become semantic authorities. Exceptions must be structured, evidence-backed, and limited to facts that AC+BCM cannot express.

Migration is incremental: freeze current behavior, generate the graph, run resolver shadow comparisons, switch recording/detection/display/audit one by one, then remove obsolete patch layers and continue decomposing the entry script.
