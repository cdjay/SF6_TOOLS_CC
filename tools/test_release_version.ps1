$ErrorActionPreference = "Stop"

$workspacePath = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
$versionPath = Join-Path $workspacePath "data\SF6CC\version.json"
$bumpScript = Join-Path $PSScriptRoot "bump_version.ps1"
$packageScript = Join-Path $PSScriptRoot "package_release.ps1"

$beforeHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $versionPath).Hash
$bumpOutput = & $bumpScript -Workspace $workspacePath -Part Patch -DryRun *>&1 | Out-String
$afterHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $versionPath).Hash
if ($beforeHash -ne $afterHash) {
    throw "Version bump dry run changed the version file."
}
if ($bumpOutput -notmatch "Dry run complete") {
    throw "Version bump dry run did not complete."
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("sf6cc-version-test-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path (Join-Path $tempRoot "data\SF6CC") -Force | Out-Null
try {
    $tempVersionPath = Join-Path $tempRoot "data\SF6CC\version.json"
    Copy-Item -LiteralPath $versionPath -Destination $tempVersionPath
    $originalText = [System.IO.File]::ReadAllText($tempVersionPath)
    & $bumpScript -Workspace $tempRoot -Part Patch | Out-Null

    $currentParts = @(([string](Get-Content -Raw -LiteralPath $versionPath | ConvertFrom-Json).product.version).Split("."))
    $expectedVersion = "$($currentParts[0]).$($currentParts[1]).$([uint64]$currentParts[2] + 1)"
    $bumpedDocument = Get-Content -Raw -LiteralPath $tempVersionPath | ConvertFrom-Json
    if ([string]$bumpedDocument.product.version -ne $expectedVersion) {
        throw "Version bump did not write the expected patch version."
    }

    $productVersionPattern = '(?s)("product"\s*:\s*\{(?:(?!\}).)*?"version"\s*:\s*")([^"]+)(")'
    $replaceVersion = [System.Text.RegularExpressions.MatchEvaluator] {
        param($match)
        return $match.Groups[1].Value + $expectedVersion + $match.Groups[3].Value
    }
    $expectedText = [regex]::Replace($originalText, $productVersionPattern, $replaceVersion, 1)
    $bumpedText = [System.IO.File]::ReadAllText($tempVersionPath)
    if ($bumpedText -cne $expectedText) {
        throw "Version bump changed content outside the product version field."
    }

    $bumpedBytes = [System.IO.File]::ReadAllBytes($tempVersionPath)
    $hasUtf8Bom = $bumpedBytes.Length -ge 3 -and
        $bumpedBytes[0] -eq 0xEF -and
        $bumpedBytes[1] -eq 0xBB -and
        $bumpedBytes[2] -eq 0xBF
    if ($hasUtf8Bom) {
        throw "Version bump wrote an unexpected UTF-8 BOM."
    }
}
finally {
    $resolvedTempRoot = (Resolve-Path -LiteralPath $tempRoot).Path
    $systemTempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    $unexpectedTempRoot =
        -not $resolvedTempRoot.StartsWith($systemTempRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Leaf $resolvedTempRoot) -notlike "sf6cc-version-test-*"
    if ($unexpectedTempRoot) {
        throw "Refusing to clean an unexpected test directory: $resolvedTempRoot"
    }
    Remove-Item -LiteralPath $resolvedTempRoot -Recurse -Force
}

$packageOutput = & $packageScript -Workspace $workspacePath -DryRun -Force *>&1 | Out-String
$document = Get-Content -Raw -LiteralPath $versionPath | ConvertFrom-Json
$productVersion = [string]$document.product.version
if ($packageOutput -notmatch "Version:\s+$([regex]::Escape($productVersion))") {
    throw "Release dry run did not use the canonical product version."
}
if ($packageOutput -notmatch "Version source:\s+$([regex]::Escape($versionPath))") {
    throw "Release dry run did not report the canonical version source."
}

$mismatchRejected = $false
try {
    & $packageScript -Workspace $workspacePath -Version "9.9.9" -DryRun | Out-Null
}
catch {
    $mismatchRejected = $_.Exception.Message -match "does not match product version"
}
if (-not $mismatchRejected) {
    throw "Release packager accepted a mismatched explicit version."
}

Write-Host "release version tests passed"
