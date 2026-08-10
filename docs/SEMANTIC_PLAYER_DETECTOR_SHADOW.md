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

## Staged Candidate

- Source: SF6ACBCM M5 current export generated on August 10, 2026.
- Schema: `sf6acbcm.runtime-current.v1`
- Build: `sf6b_c0269f7351fc73e06633b780`
- Character coverage: 31/31
- Runtime bytes: `8,336,048`
- Runtime SHA-256: `af319d0f4ca96e49368cea976951558425fb14bc841fad217226e4a158eea5bf`
- Readiness: `artifact_set=true`, `review_complete=false`, `integration_candidate=false`

The staged files are development inputs for Shadow diagnostics. Their presence
does not authorize a production semantic switch.
