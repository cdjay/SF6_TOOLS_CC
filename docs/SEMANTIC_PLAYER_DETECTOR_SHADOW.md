# Semantic Player Detector Shadow

Status: development candidate only.

The Raw Stage 1 contract remains frozen:

- Combo V2 Action facts are unchanged.
- Raw Input and timeline remain the only Replay sources.
- ReplayVerifier continues to compare the complete Atomic Action sequence.

Player detection uses a separate current-build projection:

`Atomic Action -> MoveResolver -> membership event -> Shadow comparison`

The first Shadow policy is intentionally narrow:

- Actions with one or more current Move memberships remain ordered and duplicate-preserving.
- Actions with no current Move membership are excluded from comparison and retained in diagnostics.
- Multiple/shared memberships remain ambiguous candidate sets and are never collapsed to one Move.
- `NO_DIRECT_BCM_BINDING` is not an exclusion rule.
- Action ID numeric ranges are not semantic rules.
- An expected trace with no Move memberships is unavailable, never an automatic pass.

The SF6ACBCM artifact is still `READY WITH LIMITATIONS`. Shadow output cannot
replace production PASS/FAIL until comparison evidence and semantic review are complete.
