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

Direct BCM Actions may share one runtime command-phase family only when the generated catalog proves identical Classic command definitions, identical AC core structure, an exact audited AC phase edge, and a narrowly reviewed runtime-condition delta. Recording, detection, presentation, and audit consume that declaration from the same generated catalog; equal display text alone is never identity evidence.

When a Function 3 Action has no player-visible Modern profile but its enabled BCM `norm` profile exactly matches the generated Classic command identity, the catalog may retain that direct route with `projection_scope: classic_only`. This route verifies Classic presentation only; it must not populate either Modern command slot or imply Modern control support.

A Type 63 directional punch follow-up may inherit a Classic-only `>direction+P`
verification route only when the AC relation has the exact zero-frame,
zero-extra-parameter punch-family shape, the source owns a direct BCM `j.P`
identity, and the target has no independent BCM binding. The target retains its
own Action ID, no Modern command is invented, and character, fighter, or Action
ID special cases cannot substitute for structural evidence.

Presentation, detection, and audit remove only the contiguous attempt-start
prefix made of single directions (`1`-`9`), basic dashes (`44`/`66`), and Drive
Parry. The first following semantic Action is the first visible and detectable
checkpoint. The frozen V2 Action list and raw/timeline replay facts remain
unchanged; the same normalized sequence is used by manual validation and
automatic replay. Matching becomes strict after that first semantic Action, and
an all-prefix sequence fails closed.

Migration is incremental: freeze current behavior, generate the graph, run resolver shadow comparisons, switch recording/detection/display/audit one by one, then remove obsolete patch layers and continue decomposing the entry script.
