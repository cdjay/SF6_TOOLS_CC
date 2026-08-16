# Real-game Smoke Packet

Status: `CURRENT_OPERATIONAL` / `REAL_GAME_SMOKE_REQUIRED`

Baseline date: 2026-08-15

Execution state: `NOT_COMPLETE`

This is a minimal blocking packet, not a general manual test plan. Every case
must capture both Legacy production behavior and MoveResolver shadow output.

## RG-01 EHonda 921 / 926

Setup:

- current build `2026-08-03`;
- EHonda with visible `stock_0_020` and relevant resource state;
- Legacy production path plus structured shadow compare enabled.

Steps:

1. Trigger the Action 921 `214+HP` route.
2. Trigger the Action 926 route under every reproducible stock/resource state.
3. Capture the complete Action sequence through 941/942.

Capture:

- previous/current/next Action IDs and frames;
- input profile and command route;
- `stock_0_020` before and after activation;
- AC transitions observed;
- Legacy matcher/recorder result;
- MoveResolver candidate list and difference category.

Offline expectation:

```text
921: enabled BCM route, no AC edge
926: enabled BCM route, AC Type 54 -> 941
941: AC Type 4 -> 942
942: Type 4 self loop
```

Decision resolved: whether the Legacy absorb/policy relation is resource-state
runtime behavior and whether any identity relation is justified.

## RG-02 Yasmine 941 / 942

Setup:

- Yasmine in normal and relevant `stock_0_033` states;
- Classic and Modern routes where available.

Steps:

1. Trigger Action 941 using each enabled profile.
2. Observe the exact transition into 942.
3. Attempt to trigger 942 independently.

Capture:

- 941 start/end and 942 start/end frames;
- input/profile and button state;
- resource state;
- whether 942 can start without 941;
- Legacy result and shadow candidates.

Offline expectation:

```text
941 -> 942 is raw AC Type 37
942 has a BCM trigger record but no enabled profile
```

Decision resolved: internal/transition phase versus independently triggerable
Move ownership.

## RG-03 Ryu 739 Universal-route Ambiguity

Setup:

- Ryu, Classic and Modern control modes;
- structured shadow logging.

Steps:

1. Produce Action 739 through the `66` route.
2. Produce Action 739 through the `Parry` / Modern `HP` route.
3. Repeat while capturing state/resource predicates.

Capture:

- route trigger index/profile;
- control mode;
- Action 739 state flags and next Action;
- Legacy result;
- both provisional Move candidates.

Decision resolved: true condition-specific multi-membership versus universal
runtime mechanism ownership.

## RG-04 Mai 604 Unmapped Ownership

Setup:

- load a corpus combo containing Mai Action 604 (`HP`);
- enable recorder, detector, and shadow diagnostics.

Steps:

1. Reproduce the corpus step.
2. Capture surrounding Actions and raw input.
3. Repeat from neutral if independently possible.

Capture:

- previous/current/next Action IDs;
- Action duration and contact state;
- raw input and newly pressed buttons;
- Legacy handling;
- shadow `NOT_FOUND` result.

Offline expectation: M2 census contains AC connectivity without Move
membership, classified `TRANSITION_ACTION`.

Decision resolved: confirm not-a-Move ownership without creating a fallback
identity.

## RG-05 Ingrid 969 Hold / Stock Policy

Setup:

- Ingrid with zero through maximum `stock_0_032` states;
- record `214+LP` short, medium, and long holds.

Steps:

1. Trigger Action 969 at each hold duration and stock state.
2. Observe absorbed Action 975 and any commandless candidate route.
3. Save and replay the resulting Frozen V2 combo without editing its schema.

Capture:

- hold frames and physical button state;
- stock before/after;
- Actions 969/975 sequence;
- Legacy charge status and grouping;
- shadow candidate list;
- saved V2 timeline/raw input/Action IDs.

Decision resolved: separate charge runtime policy from the commandless
generator-overlap family while proving Frozen V2 remains unchanged.

## RG-06 Cross-consumer Shadow Packet

Use one successful case above and collect one structured bundle containing:

```text
Recording legacy vs shadow
Display legacy/presentation vs Move-derived candidate
Detection legacy vs shadow
Demo compatibility vs shadow projection
Playback Frozen V2/compatibility vs shadow projection
```

Required assertion:

```text
production_result remains legacy for every consumer
```

Decision resolved: whether consumer shadow coverage is operational in the real
REFramework runtime and whether offline load/memory estimates are representative.

## Exit Rule

Do not mark smoke PASS from screenshots or final UI text alone. The capture must
contain Action sequence, state/resource facts, Legacy result, shadow result, and
the exact decision each observation resolves.
