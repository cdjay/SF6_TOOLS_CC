# Task C Final Correctness Evidence Audit

Date: 2026-08-15

Final state: `COMPLETE`

`COMPLETE` means all currently accessible Task C evidence has been inventoried,
executed, challenged, and classified. It does not mean SF6CC has no bugs.

## 1. Baseline

| Item | Result |
| --- | --- |
| Baseline SHA | `1fd27f95ade064a54b789153a492df505497af57` |
| Worktree | `D:\CP\SF6CC\reframework-task-c` |
| Branch | `review/full-corpus-audit-task-c` |
| Lua parse | `115 / 115 PASS` |
| Test files | `59 / 59 PASS` |
| Sealed oracle integrity | `633 cases PASS` |
| Frozen corpus | `965 / 965 PASS` |
| All accessible exact-unique corpus | `2,509 / 2,509 roundtrip PASS` |
| Real-game evidence | `UNAVAILABLE` |

## 2. Test Inventory

| Type | Assets |
| --- | ---: |
| UNIT | 39 |
| MODULE | 16 |
| SIMULATION | 4 |
| ORACLE | 1 |
| Total | 60 |

There is no checked-in real-game smoke suite. Test names containing `runtime`
are not automatically E8; each claim is classified by the behavior actually
executed.

## 3. Final Evidence Coverage Matrix

Legend: `Y` established, `P` partial/narrow, `H` historical low-independence,
`-` absent.

| Domain | E1 | E2 | E3 | E4 | E5 | E6 | E7 | E8 | E9 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Raw Input | Y | Y | Y | - | Y | Y | P | - | - |
| Recording | Y | Y | Y | - | - | P | P | - | - |
| Action observation | Y | Y | Y | - | - | P | P | - | - |
| Timeline | Y | Y | Y | - | Y | Y | P | - | - |
| Side-relative direction | Y | Y | Y | - | P | Y | P | - | - |
| Hitstop | Y | Y | Y | - | - | P | P | - | - |
| Normalization | Y | Y | Y | - | Y | Y | Y | - | - |
| Move resolution | Y | Y | Y | H | P | P | P | - | - |
| AC relation | Y | Y | Y | - | P | P | P | - | - |
| BCM input facts | Y | Y | Y | - | P | P | P | - | - |
| Display | Y | Y | Y | H | Y | Y | Y | - | - |
| Detection | Y | Y | Y | - | Y | Y | Y | - | - |
| Demo | Y | P | P | - | - | - | P | - | - |
| Playback | Y | Y | Y | - | - | P | P | - | - |
| Fast-forward/catch-up | Y | P | P | - | - | P | P | - | - |
| Legacy compatibility | Y | Y | Y | H | Y | Y | Y | - | - |
| Serialization | Y | Y | Y | - | Y | Y | P | - | - |
| Metadata | Y | Y | Y | - | Y | Y | P | - | - |
| Generated artifact loading | Y | Y | Y | - | Y | Y | P | - | - |
| Unknown handling | Y | Y | Y | - | Y | P | P | - | - |
| Character policies | Y | Y | Y | H | Y | P | P | - | - |
| Consumer agreement | Y | P | P | - | P | Y | P | - | - |

No E9 claim exists. Narrow HP/refresh tests approach Runtime simulation but do
not justify a general E8 claim for the domains above.

## 4. Strongest Proven Behaviors

- All 965 frozen current-build cases repeatedly roundtrip through the production
  editor core without Frozen V2 fact drift.
- The same 965 cases normalize deterministically and do not mutate source data.
- All 7,736 displayed semantic steps resolve or are explicitly suppressed;
  none is unresolved.
- Controlled Action/motion/combo-count positive and negative matrices show no
  FP or FN for the exercised matcher contracts.
- Raw input native/relative transforms are involutive for both facings over the
  corpus masks.
- Timeline `+5` translation preserves parsed event order/content for all 965
  cases.
- Fresh-process test order, same-process Lua test order, and corpus order are
  deterministic after `TEST-INFRA-C001` remediation.
- Four high-value deliberate mutations are rejected by focused tests.

## 5. Consumer Differential

The full-corpus harness feeds one normalized sequence into detection, display,
grouping, scene-state, validator, raw-input, and timeline consumers. On the
frozen corpus there are no unexpected consumer differences.

The harness does not run real recording hooks, demo injection, playback frame
loops, or game observation. Therefore it establishes partial consumer
agreement, not the full Recording -> Display -> Detection -> Demo -> Playback
agreement contract.

On the mixed historical set, 34 command-display differences are classified
`EXPECTED_HISTORICAL_INCOMPATIBILITY`; they do not reproduce on the frozen
current-build corpus.

## 6. Oracle and Golden Conclusions

- Sealed oracle independence: `LOW`.
- Oracle cases executed by Runtime consumers: `0 / 633`.
- Oracle value: immutable historical snapshot integrity.
- Current source regeneration: intentionally differs after Type 35 convergence.
- Current high-independence real-game golden: none.
- Snapshot auto-refresh in normal tests: not found.

## 7. Evidence Debt Ledger

| ID | Severity | Domain | Current -> Desired | Debt / Blocker | Owner |
| --- | --- | --- | --- | --- | --- |
| ED-C001 | Critical | End-to-end correctness | E3/E7 -> E9 | No real-game recording/detection/demo/playback smoke | Future Runtime validation |
| ED-C002 | High | Recording loop | E3 -> E8/E9 | No record -> save -> load -> detect trace from game hooks | Task B/future harness |
| ED-C003 | High | Demo/playback timing | E3 -> E8/E9 | No full-corpus frame injection and completion trace | Task B/future harness |
| ED-C004 | High | Same-frame/hitstop/side switch | E2/E3 -> E8/E9 | Frozen corpus has gap strings and no facing trace | Runtime validation |
| ED-C005 | High | Independent oracle | H/LOW -> E4 HIGH | No independently labelled current truth set | Main/data curation |
| ED-C006 | High | Move/AC/BCM coverage | Proxy E5/E6 -> exact E6 | No bulk Move/raw AC/raw BCM universe in SF6CC | Task A/SF6ACBCM |
| ED-C007 | Medium | Generator determinism | Synthetic E6 -> authoritative E6 | Full raw generator inputs are external | SF6ACBCM/release process |
| ED-C008 | Medium | Rare characters | Sparse E5 -> stratified E5 | Kimberly 3, Manon 4, Yasmine 5, Rashid 7 | Corpus curation |
| ED-C009 | Medium | Historical migration | Parse E5 -> migrated E5 | 34 old display findings lack offline migrated twins | Data migration |
| ED-C010 | Medium | Performance/Win11 UI | E1-E3 -> E9 | No timing budget, soak, or rendered Win11 smoke | Future QA |
| ED-C011 | Low | Metadata notes | E5 -> clean E5 | Nine frozen `step_notes` count warnings | Data curation |
| ED-C012 | Low | Archive integrity | Loose 965 PASS -> archive hash PASS | Declared frozen ZIP was unavailable | Backup custodian |

## 8. Adversarial Second Pass

The second pass assumed all green results could be misleading and rechecked:

- oracle self-reference and non-execution;
- generated/golden source correlation;
- exact duplicate inflation in historical packages;
- rare-character imbalance;
- wrong-ID, wrong-motion, missing-input, and wrong-combo negatives;
- same-frame and side-switch absence;
- repeated serialization mutation;
- test order and same-process cache leakage;
- current artifact identity versus mixed historical files;
- regression sensitivity through deliberate mutation;
- raw AC existence for the eight historical display Action locators.

No P0/P1 production correctness defect was confirmed. The material findings
are evidence limitations, one fixed test-infrastructure defect, and expected
historical incompatibility.

## 9. Escalations

`BUG_ESCALATION_TO_TASK_B`: none.

`ARCHITECTURE_ESCALATION_TO_TASK_A`: none.

The audit does not establish a conflicting semantic authority. It identifies
where current evidence is too weak to answer a Runtime question.

## 10. Reproduction Ladder

```powershell
python tools\task_c_phase1_audit.py --repo-root . --audit-date 2026-08-15 --run-tests --output docs\audits\task-c\phase1-evidence.json
python tools\task_c_full_corpus_audit.py --repo-root . --corpus-root "D:\CP\SF6CC\reframework\release\tester_packages\0803" --output-dir docs\audits\task-c
python tools\task_c_all_accessible_corpus_audit.py --repo-root . --backup-root "D:\CP\SF6CC\reframework\release\tester_packages" --output-dir docs\audits\task-c
python tools\task_c_determinism_audit.py --repo-root . --backup-root "D:\CP\SF6CC\reframework\release\tester_packages" --output docs\audits\task-c\determinism-audit.json
python tools\task_c_mutation_audit.py --repo-root . --output docs\audits\task-c\mutation-audit.json
```

The declared real-game boundary remains:

```text
REAL_GAME_EVIDENCE_UNAVAILABLE
```
