# Tester Workflow

Status: `CURRENT_OPERATIONAL`

Current tester builds are generated from a reviewed Git commit. Historical
ZIPs, loose Lua copies, and files named `fix`, `final`, `latest`, or `hotfix`
are not current authority.

## Build

1. Use a clean worktree at the exact reviewed SHA.
2. Confirm `data/SF6CC/version.json`; do not infer the version from manifests,
   folder names, tags, or old packages.
3. Run the offline gate in [Testing Strategy](TESTING_STRATEGY.md).
4. Preview the package plan:

```powershell
tools\package_release.bat -DryRun
```

5. Generate with the checked-in packager. Use `-Force` only when intentionally
   replacing the same local output; the packager creates a timestamped backup.

```powershell
tools\package_release.bat -Force
```

Do not assemble a tester ZIP by copying individual Lua files. The standard
package and Runtime package are generated under `release/<version>/` and are
ignored repository outputs.

## Identify And Verify

Every tester handoff must record:

- product version;
- full Git SHA and branch;
- generated package filename;
- SHA-256 from `Get-FileHash`;
- gate result;
- requested smoke cases;
- whether `re2_fw_config.txt` is included.

There is no repository-global "latest tester package". A package is current
only for its named test request when the handoff record identifies the reviewed
source SHA and the delivered file still matches the recorded SHA-256. Keep the
handoff record with the external test request or distribution channel; do not
commit ad hoc package ledgers or infer authority from a filename or timestamp.

A useful external delivery name is
`SF6CC_test_v<version>_<short-sha>_<yyyyMMdd>.zip`. Renaming a delivery copy does
not change the canonical package or product version.

## Install And Roll Back

- Install the complete generated package into a known REFramework directory.
- Never patch an installed `TrainingComboTrials_v1.0.lua` by hand.
- Preserve player/runtime state separately from product files.
- Roll back by reinstalling a previously identified complete package, not by
  mixing old and new loose files.

## Storage Policy

Tester packages are generated on demand and must not be committed. The local
`release/tester_packages` tree is backup/research storage, not a current tester
distribution channel. Its historical artifacts require explicit retention
review before deletion or redistribution.
