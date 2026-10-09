# SF6CC Versioning

Status: `CURRENT`

SF6CC uses [`data/SF6CC/version.json`](../data/SF6CC/version.json) as the
single source of truth for product and combo JSON format versions.

The version axes are independent:

- `product.version`: the SF6CC release version. The menu, telemetry, combo
  recorder and release packager all read this value.
- `formats.combo_trial.version` / `schema`: the combo JSON specification
  version. Change these only when the JSON specification changes.
- `_xt_meta.versions.game.version`: the Street Fighter 6 data version. It is
  separate from SF6CC and must not be inferred from the mod release version.
  It is a date label maintained by hand in `version.json`; the factual
  provenance is `_xt_meta.versions.game.bcm_trigger_fingerprint`, which the
  recorder takes from the running game. When a loaded combo's fingerprint
  differs from the live one, SF6CC warns that its Action IDs may have moved.
  Generated command tables carry the same fingerprint
  (`_meta.bcm_trigger_fingerprint`) and are checked against the live game in
  the same way.

## Bump the product version

Choose the release change explicitly:

```powershell
tools\bump_version.bat -Part Patch
tools\bump_version.bat -Part Minor
tools\bump_version.bat -Part Major
```

Use `-DryRun` to preview the next version. An exact semantic version can be
selected with `-Version <x.y.z>`.

The bump command changes only the canonical version file. Review and commit
that change before packaging so a release can always be reproduced from its
Git commit.

## Package

```powershell
tools\package_release.bat -Force
```

The packager reads the canonical product version and uses it for the output
directory, ZIP filenames and generated manifest. `-Version` remains accepted
as an optional assertion for existing automation, but it must equal the
canonical version.

Packaging never increments a version by itself. This prevents repeated builds
of the same commit from silently producing different releases.
