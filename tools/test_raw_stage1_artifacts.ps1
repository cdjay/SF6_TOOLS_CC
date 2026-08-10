$ErrorActionPreference = "Stop"

$root = Join-Path $PSScriptRoot "..\data\TrainingComboTrials_data\raw\current"
$manifestPath = Join-Path $root "raw-current-manifest.v1.json"
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json

if ($manifest.schema -ne "sf6.raw.current-manifest.v1") { throw "manifest schema mismatch" }
if ($manifest.characters.Count -ne 31) { throw "expected 31 characters" }
if ($manifest.character_coverage.generated -ne 31 -or $manifest.character_coverage.failed.Count -ne 0) {
    throw "character coverage mismatch"
}

$expected = @{
    actions = 23448
    ac_edges = 11200
    bcm_triggers = 3276
    bcm_commands = 13104
    bcm_command_definitions = 1162
    bcm_inputs = 4301
}
foreach ($name in $expected.Keys) {
    if ([int64]$manifest.totals.$name -ne [int64]$expected[$name]) {
        throw "manifest total mismatch: $name"
    }
}

$totals = @{
    actions = 0L
    ac_edges = 0L
    bcm_triggers = 0L
    bcm_commands = 0L
    bcm_command_definitions = 0L
    bcm_inputs = 0L
}

foreach ($entry in $manifest.characters) {
    $path = Join-Path $root $entry.file
    $file = Get-Item -LiteralPath $path
    if ($file.Length -ne [int64]$entry.bytes) { throw "size mismatch: $($entry.file)" }
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -ne $entry.sha256) { throw "hash mismatch: $($entry.file)" }

    $artifact = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
    if ($artifact.schema -ne "sf6.raw.current.v1") { throw "artifact schema mismatch: $($entry.file)" }
    if ($artifact.character.fighter_id -ne $entry.fighter_id) { throw "fighter mismatch: $($entry.file)" }
    if (($artifact.build | ConvertTo-Json -Depth 20 -Compress) -ne
        ($manifest.build | ConvertTo-Json -Depth 20 -Compress)) {
        throw "build mismatch: $($entry.file)"
    }
    if (($artifact.source | ConvertTo-Json -Depth 100 -Compress) -ne
        ($entry.source | ConvertTo-Json -Depth 100 -Compress)) {
        throw "source descriptor mismatch: $($entry.file)"
    }
    foreach ($name in @($totals.Keys)) {
        if ([int64]$artifact.counts.$name -ne [int64]$entry.counts.$name) {
            throw "entry count mismatch: $($entry.file) $name"
        }
        $totals[$name] += [int64]$artifact.counts.$name
    }
    foreach ($trigger in $artifact.command_catalog.triggers) {
        if ($trigger.profiles.Count -ne 4) { throw "profile completeness mismatch: $($entry.file)" }
        foreach ($profile in $trigger.profiles) {
            if ($null -eq $profile.command_definition_uids -or $null -eq $profile.variant_indexes -or
                $null -eq $profile.direct_command_tokens) {
                throw "missing plural direct-binding fields: $($entry.file)"
            }
            if ($profile.command_definition_uids.Count -ne $profile.variant_indexes.Count) {
                throw "variant binding length mismatch: $($entry.file)"
            }
            if ($null -ne $profile.command_token -or $null -ne $profile.command_definition_uid) {
                throw "legacy singular command field present: $($entry.file)"
            }
        }
    }
    foreach ($edge in $artifact.action_catalog.edges) {
        if ($edge.PSObject.Properties.Name -contains "target_raw_action_uid") {
            throw "artificial target projection present: $($entry.file)"
        }
    }
    foreach ($definition in $artifact.command_catalog.definitions) {
        foreach ($input in $definition.inputs) {
            if ($null -eq $input.direction -or $input.direction -isnot [string]) {
                throw "missing input direction: $($entry.file)"
            }
        }
    }
}

foreach ($name in $totals.Keys) {
    if ($totals[$name] -ne [int64]$expected[$name]) { throw "aggregate mismatch: $name" }
}

Write-Output "raw stage1 artifact tests passed: 31 characters, 3276 triggers, 13104 profiles"
