# SF6CC Character Semantic Convergence Pilot

Date: 2026-08-10

## 1. Exception Inventory Summary

The read-only inventory found 484 Action-scoped records across 33 exception JSON files (32 character/Common scopes), plus five `_character` policy records. Categories overlap when one record contains both relationship semantics and runtime behavior.

| Category | Records | Main locations | Typical fields |
| --- | ---: | --- | --- |
| Semantic exception | 183 Action records | `exceptions/*.json`, `CharacterRules.lua` | `absorb_ids`, `optional_parent_ids`, `action_alias_ids`, `action_event_projection` |
| Presentation exception | 132 entries / 30 files | `command_display_overrides/*.json` | command text replacement and display evidence |
| Runtime behavior exception | 328 Action records | `exceptions/*.json`, generic Recorder/Detector consumers | `force`, charge/hold windows, ignore policy, `action_event_rules` |
| Historical compatibility | 12 mappings / 3 files | `action_compatibility/*.json` | old Action to current Action playback projection |

`CharacterRules`, `ActionEventCompiler`, `ActionMatcher`, Recorder, Detector, audit, and Presentation were scanned. Their character-specific behavior is mostly data-driven, although older unrelated character branches remain in the frozen composition root and UI/runtime code. No such branch was added or changed in this Pilot.

## 2. Exception Inventory

| Character / Scope | Rule | Location | Action IDs | Purpose | Current consumer | AC/BCM evidence likely? | Category |
| --- | --- | --- | --- | --- | --- | --- | --- |
| All character exception files | absorb/parent/alias/projection relationships | `data/TrainingComboTrials_data/exceptions/*.json` | 183 relationship-bearing records | ownership, internal/replacement grouping, follow-up allowance | CharacterRules, ActionMatcher, ActionEventCompiler | mixed; requires per-family proof | A |
| All character exception files | timing/hold/force/ignore policy | same | 328 runtime-bearing records | runtime matching and recording behavior | Recorder, Detector, matcher/compiler | usually no | C |
| 30 characters | command display overrides | `command_display_overrides/*.json` | 132 entries | display replacement only | Presentation/CommandResolver | sometimes, but presentation-only | B |
| EHonda, JP, Luke | Legacy Action projection | `action_compatibility/*.json` | 12 mappings | old V2 playback compatibility | compatibility loader/matcher | historical evidence, not current semantics | D |
| Jamie | replacement absorb family | `exceptions/Jamie.json` | `981 -> 982,983,984` | treat three build-local replacement Actions as accepted outcomes of owner 981 | ActionMatcher absorb path | yes, exact Type 35 plus BCM owner | A, selected |
| Jamie | second replacement absorb family | `exceptions/Jamie.json` | `989 -> 990,991,992` | same relationship family | ActionMatcher absorb path | yes, exact Type 35 plus BCM owner | A, follow-up only |
| Ingrid | neutral continuation absorb | `exceptions/Ingrid.json` | `945 -> 953` | suppress/fold continuation | compiler/matcher | ambiguous Type 13 population | A/C, rejected |

## 3. Selected Pilot

Jamie Action 981 previously declared `absorb_ids = "982,983,984"` by hand. It was selected because the Runtime consumes it, the relation is not display or historical compatibility, and the current generated Move graph already contains an exact one-primary/three-replacement family.

## 4. Raw Evidence

- Character: Jamie, fighter 21, current build `2026-08-03` / `sf6b_c0269f7351fc73e06633b780`.
- BCM owner: Action 981, trigger index 108, raw trigger `btrg_5495709f5fac66c3ac693fb5`; Actions 982/983/984 have no independent BCM trigger.
- AC source: Action 981, raw Action `act_fbe55eaec9568a85f1d0a897`, record index 314, root object 40662.
- AC edges: `981 -> 982`, `981 -> 983`, `981 -> 984`; all are Type 35, frame 0, attr 256, trigger -1, params `[25,0,0,0,0,0]`.
- Raw edge UIDs: `edge_b4e6836ef924078f2d571799`, `edge_4d21e55686199a4e0e16228d`, `edge_c32edfcb7047bc72cfe4b7e4`.
- M2 Move: `m2move_596961b76aff52ded307e13a`, family `m1fam_aeb0154229d9d7a7f692bb55`.
- M2 memberships: 981 `primary/STRICT`; 982, 983, 984 `replacement/STRICT` with relationship UIDs recorded in the generated manifest.

## 5. Generator Gap

M1/M2 already inferred the relation generically from exact Type 35 evidence. The missing link was a reviewed, fail-closed projection from a selected strict Move family into SF6CC's mature `absorb_ids` compatibility contract. Runtime previously had no generated source for that contract.

## 6. Implementation

SF6ACBCM now provides a generic `generate-sf6cc-semantics` command. A selection document identifies a reviewed Move by `move_uid`; the generator requires exactly one context-free STRICT primary, at least one context-free STRICT replacement, exact AC relationship evidence for every replacement, a direct BCM anchor for the primary, and no independent BCM anchor for any target.

The rule contains no character name, fighter ID, or Action ID branch. The selected family generates `generated_semantics/Jamie.json` using the existing `absorb_ids` shape. `CharacterRules.load_for_character()` merges generated rules with remaining hand-written product rules.

## 7. Legacy Removal And Equivalence

The hand-written Jamie 981 object was removed from `exceptions/Jamie.json`. The generated file now supplies exactly:

```json
{
  "981": {
    "absorb_ids": "982,983,984"
  }
}
```

No `action_event_projection` was added, because Legacy 981 did not declare one. ActionMatcher receives the same absorb relation, unrelated Jamie rules remain unchanged, and ActionEventCompiler receives no new projection behavior.

## 8. Runtime Impact

- Recorder: no behavior change.
- Detector/ActionMatcher: same Jamie 981 absorb set from a generated source.
- Presentation: no behavior change.
- Audit: generated manifest adds AC/BCM provenance; no V2, timeline, raw input, Replay, or main-entry code changed.

## 9. Follow-up Candidates

An exact post-Pilot scan found one additional hand-written family matching this projection rule: Jamie `989 -> 990,991,992`. It remains untouched. No other character currently has a hand-written absorb family exactly equal to a generated STRICT Type 35 replacement family.

## 10. Recommendation

`PROVEN WITH LIMITATIONS`

The projection is proven for exact BCM-owned Type 35 replacement families and is safe to repeat through explicit review selection. It must not be generalized to Type 13 or to all `absorb_ids`; most exception records mix semantic and runtime facts that require separate evidence.
