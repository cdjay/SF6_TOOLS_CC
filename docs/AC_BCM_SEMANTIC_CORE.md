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

Recording may recover a missed transient Drive Rush Cancel Action only when a
double direction tap during an attack, subsequent contact, and a local three-bar
spend (or exhaustion of the remaining gauge) agree before the next Action.
The current character's command resolver must independently identify the DRC
Action. The recovered event is marked as inferred in the capture trace; an
observed DRC takes precedence. Input alone must never create a command step.

When a Function 3 Action has no player-visible Modern profile but its enabled BCM `norm` profile exactly matches the generated Classic command identity, the catalog may retain that direct route with `projection_scope: classic_only`. This route verifies Classic presentation only; it must not populate either Modern command slot or imply Modern control support.

Presentation, detection, and audit remove only the contiguous attempt-start
prefix made of single directions (`1`-`9`), basic dashes (`44`/`66`), and Drive
Parry. The first following semantic Action is the first visible and detectable
checkpoint. The frozen V2 Action list and raw/timeline replay facts remain
unchanged; the same normalized sequence is used by manual validation and
automatic replay. Matching becomes strict after that first semantic Action, and
an all-prefix sequence fails closed.

Migration is incremental: freeze current behavior, generate the graph, run resolver shadow comparisons, switch recording/detection/display/audit one by one, then remove obsolete patch layers and continue decomposing the entry script.

## Generated Detection Rules And Data Guard (2026-10-09)

Runtime detection still reads exception-shaped rules through `CharacterRules`
(`absorb_ids`, `force`, ...), now from two disjoint layers. The generated layer
(`generated_semantics/<key>.json`, built by
`tools/action_runtime_compiler/build_generated_semantics.js`, algorithm
`sf6cc-acbcm-exception-projection.v2`) projects AC+BCM relations of the deployed
command table: a Type 29 verified variant is absorbed by its source Action and
forced; Type 63 strength variants, Type 20 directional variants and Type 37
follow-up execution phases are forced; so are Actions whose command-table
ownership the runtime does not count as a player step on its own
(`inherited`, e.g. every back throw, `rebind`, `automatic_hold_transition`,
`ac_state_direction`, `type20_hold_continuation`, `ac_type13_neutral`,
`ac_state_neutral`). `manifest.json` carries the relation evidence of every rule. The curated layer (`exceptions/<key>.json`) keeps only
behavior that AC+BCM does not derive or that differs from it; an Action belongs
to exactly one layer. `_generated_semantics.withhold` lists every Action where
AC+BCM derives a rule but current behavior differs; those Actions are not
generated until live verification removes the entry. The 2026-10-09
convergence moved identical curated entries to the generated layer (curated
462→290, generated 174, withheld 47) with identical effective runtime rules; the
2026-10-10 ownership rules moved 51 more (curated 290→239, generated 225,
withheld 59, effective rules again identical). Ten of the new withheld Actions
have no curated rule at all, e.g. Yasmine 717, the only back throw without
force.
A fighter without curation receives every generated rule.

Each command table stores `_meta.bcm_trigger_fingerprint`; `ComboTrials/DataBuildGuard.lua`
computes the same fingerprint in game and warns when a table is missing or was
generated from other game data. Recordings carry the fingerprint they were made
with (`_xt_meta.versions.game.bcm_trigger_fingerprint`), so loading a combo
recorded on other game data warns that its Action IDs may have moved. While a
fighter has no usable table (missing or failed validation), classic command
text is decoded from the live BCM triggers by `ComboTrials/BcmCommandDecoder.lua`,
a port of the generator's decoder that matches it on all 3276 triggers of the
2026-08-03 roster; follow-up splitting, phase suppression and modern commands
still require the generated table.

## Current Resolver Rollout State (2026-08-15)

`MoveResolver` is implemented as a shadow-only semantic entry over the validated
`CurrentMoveGraph` data-access layer. Resolution prefers an approved
`stable_move_uid`; while review is incomplete it reports the build-local
`current_move_uid` explicitly as provisional identity. Multi-valued membership,
unresolved membership, missing Actions, and artifact readiness remain distinct
results and are never collapsed into a match.

`UnifiedActionConsumer` exposes resolver loading and structured shadow comparison,
but the comparison always reports `production_result = legacy`. No runtime consumer
has switched authority, and an artifact with `review_complete=false` or
`integration_candidate=false` is valid only for diagnostics, corpus comparison,
and future shadow observation.

Phase 2 keeps character-conditioned hold/charge behavior behind
`ChargeRuntimePolicy`; the entry script only invokes that module. The module is
not keyed by fighter name: a fighter whose hold is judged differently declares
it in the `_charge_policy` section of `exceptions/<key>.json` (`levels` with
three labels, `perfect_window`, `autodetect_charge_max`, `track_physical_hold`,
`charge_stock_actions`), so a new fighter needs data, not code. Named command
expansion such as Akuma Action 1231 lives in `MotionPresentation`, which may
return display text but cannot alter recording, detection, compatibility, or
MoveResolver identity. Presentation overrides are covered by a resolver
isolation test.
