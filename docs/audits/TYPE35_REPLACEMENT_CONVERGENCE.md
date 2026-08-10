# Type 35 Strict Replacement Absorb Convergence

Date: 2026-08-10

Verdict: `TYPE35_FAMILY_CONVERGENCE_COMPLETE`

## Scope

This ticket closes only the two known Legacy `absorb_ids` families that are exactly equal to a BCM-owned M2 Move with STRICT Type 35 replacement memberships.

| Family | BCM owner | Replacement Actions | M2 Move | Result |
| --- | ---: | --- | --- | --- |
| Jamie 981 | 981 | 982, 983, 984 | `m2move_596961b76aff52ded307e13a` | generated; Legacy removed |
| Jamie 989 | 989 | 990, 991, 992 | `m2move_b6d156532ec7f5a4c380ce21` | generated; Legacy removed |

## 989 Evidence

- BCM direct owner: Action 989, trigger 183, `btrg_82b174dd9640fd0dbf4611cc`.
- Actions 990, 991, and 992 have no independent BCM trigger.
- AC source: Action 989, `act_9d56bf05e385b58166d07e12`, record 320, root object 41367.
- Raw edges: `edge_1a6776d3e5cef5e8e41e907e`, `edge_fda5922174fa386d89593010`, `edge_684d3c026ab1cbd29b716d79`.
- Every edge is Type 35, frame 0, attr 256, trigger -1, params `[25,0,0,0,0,0]`.
- M2 memberships: 989 `primary/STRICT`; 990, 991, and 992 `replacement/STRICT`, all context-free and relationship-backed.

## Shadow Equivalence

Legacy and generated data both normalize to:

```json
{
  "989": {
    "absorb_ids": "990,991,992"
  }
}
```

The generated rule intentionally contains no `action_event_projection`, matching Legacy. ActionMatcher receives the same absorb set; ActionEventCompiler receives no new projection; Recorder, Detector, Presentation, V2, and Replay behavior are unchanged.

## Generator

- Algorithm: `sf6cc-replacement-absorb.v1`
- Generator production code changed: no
- Selection uses generated Move UIDs and the generic `replacement_absorb` relation.
- Character, fighter ID, or Action ID production special case introduced: no
- Deterministic character artifact SHA-256: `2a1ae87d939061fa21975e7bb1e0e3971309434fa8a1727c8156d50111fcb10b`

## Coverage

- Exact historical Type 35 replacement absorb families: 2
- Generated coverage: 2/2
- Production Legacy remaining in this family: 0
- Other absorb, Type 13, alias, optional-parent, projection, Runtime, Presentation, and Compatibility rules: unchanged and out of scope

## Baseline And Runtime

The sealed 633-case Baseline and Oracle were not modified. They continue to preserve the pre-convergence historical expectation for Jamie 981 and 989. The Legacy character exception loader remains enabled for unrelated families.

## Git

- SF6ACBCM: selection commit containing the second reviewed Move family
- SF6CC: generated asset, Legacy removal, regression, and this report
- Push: not performed
