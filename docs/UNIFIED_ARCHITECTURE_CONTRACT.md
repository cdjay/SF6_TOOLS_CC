# SF6CC Unified Architecture Contract

**Status**: CURRENT architecture invariant

**Baseline**: `075440cf0fbb07356f57f00abcaad8253765f128`

This contract defines the boundaries for SF6CC unified-architecture work. It does not authorize a production switch or a Runtime implementation by itself.

## A. Move Identity

The stable semantic identity across game versions is a `Move`. An `Action ID` is not a stable identity.

## B. Action

An Action ID is a Runtime fact scoped to the current game build.

## C. Input And Semantic Authority

- BCM is the primary input authority.
- AC is the embedded follow-up input extension authority.
- AC is the action-relationship authority.

## D. Current-Only Runtime

New SF6CC semantic data consumes only the current game version. Historical Action IDs must not become new Runtime semantic identities.

## E. Legacy Projection

`old Action -> current Action` is allowed only as a Legacy playback or compatibility projection. It must not define Move identity.

## F. Combo V2 Contract Immutable

Combo V2 is a frozen data contract. Unified-architecture work must not change its schema, redefine the meaning of existing fields, or require existing V2 data to be rewritten.

V2 remains a simple factual container consisting of:

- community / authoring attributes
- combo metadata
- `timeline`, `raw input`, or both as replay sources
- the existing Action ID list as the Layer-1 original Action instruction/fact sequence

The Action ID list is not System Presentation and is not User Presentation. It must remain an original V2-level factual/instruction layer and must not be rewritten into Move UID, current-build semantic identities, or presentation text.

Move semantics, System Interpretation / System Presentation, and User Interpretation / User Presentation must exist outside the frozen V2 contract and attach to V2 data through separate runtime or sidecar layers.

Unified architecture must therefore follow:

`V2 Action ID List -> System Interpretation through the current Move Graph / MoveResolver -> optional User Interpretation -> UI`

Neither System Interpretation nor User Interpretation may mutate V2.

Future semantic architecture must not require adding Move UID, Move Revision, Command Revision, presentation overrides, migration state, or other new semantic fields into V2.

## G. Single Semantic Resolver

Recorder, Detector, Auditor, and Presentation must ultimately converge on one `MoveResolver` for Action semantics. They must not continue maintaining independent interpretation rules.

## H. Presentation Isolation

Presentation decides only how information is displayed. It must not modify Runtime facts, Move identity, detection semantics, or Replay data.

## I. Main Entry Frozen

The existing main-entry governance is complete. The current approximately 165 top-level locals/functions are the frozen safety baseline. Remaining local capacity is safety margin, not a development budget.

New functionality must live in dedicated modules. `autorun/TrainingComboTrials_v1.0.lua` may only contain:

- `require` declarations
- initialization
- dependency wiring
- callback forwarding
- lifecycle orchestration
- minimal adjustment of existing call sites

No new business implementation function may be added to the main entry.

## J. Shadow First

Every new architecture consumer must follow:

`Shadow -> Compare -> Verify -> Switch`

Direct replacement of Legacy behavior is prohibited.

## K. Legacy Policy

Legacy remains the stable production implementation. Unified-architecture work must not become another large-scale Legacy governance effort.

Ordinary semantic issues must not expand:

- `CharacterRules`
- absorb rules
- action compatibility
- display overrides
- `group_id` patches

A genuinely severe user-facing problem may receive a minimal hotfix.

## L. SF6ACBCM Query Policy

Investigation of Move, Action, BCM, AC relations, membership, migration, or commands must first use the SF6ACBCM structured index, API, or CLI. Normal development must not directly parse large raw AC/BCM dumps.

Direct raw-dump access is allowed only when:

- SF6ACBCM reports an unresolved result
- the query layer lacks required data
- importer or parser behavior is suspected
- raw provenance is required

Raw AC/BCM remains the final game-data authority.

## M. Integration Safety

SF6ACBCM is currently `READY WITH LIMITATIONS`.

Candidate artifacts may be used for development, shadow execution, diagnostics, and comparison. They must not replace Legacy as production authority before formal semantic review is complete.
