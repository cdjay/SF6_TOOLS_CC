# SF6CC Validated Frozen Combo Backup — 2026-08-06 v1

## Snapshot Identity

- **Snapshot ID**: SF6CC-VALIDATED-COMBO-BACKUP-2026-08-06-V1
- **Combo Schema**: `xt.combo_trial/2.0.0`
- **Target Game Build**: 2026-08-03
- **Sealed**: 2026-08-08
- **Source Latest Updated**: 2026-08-06T01:17:30+08:00

## Purpose

This is a **Validated Frozen Combo Backup Snapshot**. It is:

- A disaster recovery backup
- A historical verified snapshot
- An audit reference

It is **NOT**:

- A runtime artifact or runtime data
- An AC/BCM semantic source of truth
- A current generator input
- Normal release content
- An asset that ships with the SF6CC MOD installation

Normal SF6CC users should never see or interact with this archive.

## Separation of Concerns

```
Current working content  !=  Validated Backup Snapshot
```

The backup does not participate in:

- Runtime behavior
- Semantic Core resolution
- Current generator pipelines
- Normal recording workflows
- Standard release packaging

It exists solely for disaster recovery, historical comparison, and targeted audit.

## Corpus Contents

| Metric | Value |
|---|---|
| Characters | 31 |
| Combo JSON files | 965 |
| Total uncompressed bytes | 14,656,741 |
| Archive file | SF6CC-Validated-Combo-Backup-2026-08-06-v1.zip |
| Archive size | 14,909,093 bytes |
| Archive SHA-256 | `93bffe0e8cb31dbb336ddb9e18045b75a42179c5e8626692b91152ef3dd1ff1a` |
| Root hash | `a44ef6eef72789d60bd1b1b454234f129a4ffe33cc9911af53a443d1e04a5e10` |

### Root Hash Definition

SHA-256 of UTF-8 encoded concatenation of lines, where each line is canonical_path<TAB>size<TAB>lowercase_sha256, lines sorted by ordinal canonical_path, LF between lines, no trailing LF

### Character Aggregate Hash Definition

SHA-256 of UTF-8 encoded concatenation of lines, where each line is canonical_path<TAB>size<TAB>lowercase_sha256, restricted to files belonging to the character, lines sorted by ordinal canonical_path, LF between lines, no trailing LF

## Archive Location

The archive is stored **outside the MOD worktree** in an external backup directory. The current local Primary is:

```text
D:\CP\SF6CC\archive\validated-combo-backups\SF6CC-Validated-Combo-Backup-2026-08-06-v1.zip
```

It is not under `D:\CP\SF6CC\reframework` and will never be included in standard release packages.

## Immutability

This v1 snapshot is immutable. If future content changes produce a new stable recovery point, create a **new snapshot (v2)** rather than modifying v1. The v1 archive and its manifest are never overwritten.

## Restoration

1. Verify the archive SHA-256 against this manifest's `archive.sha256`.
2. Extract the ZIP preserving canonical paths.
3. Verify each extracted file's SHA-256 against `files[]` entries.
4. Recompute the root hash per root_hash_definition and compare to `root_hash`.
5. Optionally verify per-character aggregate hashes per character_aggregate_hash_definition.
6. All checks must pass before considering the restoration valid.

Canonical extraction root:
```
reframework/data/TrainingComboTrials_data/CustomCombos/<Character>/<filename>.json
```

## Secondary Backup

**SECONDARY_BACKUP_PENDING**

A second independent copy of this archive (NAS, remote storage, or other device) has not yet been created. This is recommended for proper disaster recovery coverage.

## Historical Source

The source candidate used to build this archive was:
```
D:\CP\SF6CC\reframework\release\tester_packages\0803
```

The 31 individual character ZIP files in that directory are **GENERATED / HISTORICAL DISTRIBUTION ARTIFACTS**, not independent data authorities. This manifest is the canonical integrity record.

## Manifest

The machine-readable manifest is:
```
docs/backup/SF6CC_VALIDATED_COMBO_BACKUP_2026-08-06_V1.manifest.json
```

Schema: `sf6cc.validated_combo_backup_manifest.v1`
