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

$componentOutput = Join-Path ([System.IO.Path]::GetTempPath()) ("sf6cc-component-plan-" + [guid]::NewGuid().ToString('N'))
$componentPlan = & $packageScript -Workspace $workspacePath -TrainingLibraryOnly -OutputDir $componentOutput -DryRun *>&1 | Out-String
$shortCommit = (& git -C $workspacePath rev-parse --short=7 HEAD).Trim()
if ($componentPlan -notmatch [regex]::Escape("SF6CC_TrainingLibrary_v${productVersion}_${shortCommit}.zip") -or
    $componentPlan -match 'XiaoTun_SF6_TrainingMOD' -or (Test-Path -LiteralPath $componentOutput)) {
    throw 'Standalone dry run must plan only its component snapshot without creating output.'
}
$conflictRejected = $false
try {
    & $packageScript -TrainingLibraryOnly -TrainingConfigManagerOnly -DryRun | Out-Null
} catch {
    $conflictRejected = $_.Exception.Message -match 'Choose either'
}
if (-not $conflictRejected) { throw 'Standalone and legacy component modes must be mutually exclusive.' }
$noDllPlan = & $packageScript -TrainingLibraryOnly -ExcludeDll -OutputDir $componentOutput -DryRun *>&1 | Out-String
if ($noDllPlan -notmatch [regex]::Escape("SF6CC_TrainingLibrary_v${productVersion}_${shortCommit}_NoDLL.zip") -or
    (Test-Path -LiteralPath $componentOutput)) { throw 'DLL-free plan must be separate and read-only.' }
$noDllRejected = $false
try { & $packageScript -ExcludeDll -DryRun | Out-Null }
catch { $noDllRejected = $_.Exception.Message -match 'supported only' }
if (-not $noDllRejected) { throw 'Full release silently accepted standalone DLL exclusion.' }

$tokens = $null; $parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($packageScript, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'Packager parse failed' }
$guard = $ast.Find({param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Assert-FullPackageFeatures'
}, $true)
if (-not $guard) { throw 'Full package feature guard missing' }
. ([scriptblock]::Create($guard.Extent.Text))
$publishGuard = $ast.Find({param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Assert-FullPackagePublishPaths'
}, $true)
if (-not $publishGuard) { throw 'Full package publication path guard missing' }
. ([scriptblock]::Create($publishGuard.Extent.Text))
$zipWriter = $ast.Find({param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'New-ZipFromDirectory'
}, $true)
if (-not $zipWriter) { throw 'Release ZIP writer missing' }
. ([scriptblock]::Create($zipWriter.Extent.Text))
$featureRoot = Join-Path ([IO.Path]::GetTempPath()) ('sf6cc-feature-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $featureRoot | Out-Null
try {
    $requiredAssignment = $guard.Find({param($node)
        $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq '$required'
    }, $true)
    $requiredFiles = & ([scriptblock]::Create($requiredAssignment.Right.Extent.Text))
    foreach ($relative in $requiredFiles) {
        $target = Join-Path $featureRoot "reframework/$relative"
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        Set-Content -LiteralPath $target -Value 'x'
    }
    Assert-FullPackageFeatures -PackageRoot $featureRoot
    foreach ($relative in @('dinput8.dll', 're2_fw_config.txt', 'reframework/安装说明.txt')) {
        Set-Content -LiteralPath (Join-Path $featureRoot $relative) -Value 'x'
    }
    Assert-FullPackagePublishPaths -PackageRoot $featureRoot
    $emptyFile = Join-Path $featureRoot 'reframework/autorun/empty.lua'
    New-Item -ItemType File -Path $emptyFile | Out-Null
    $rejected = $false
    try { Assert-FullPackagePublishPaths -PackageRoot $featureRoot }
    catch { $rejected = $_.Exception.Message -match 'empty' }
    if (-not $rejected) { throw 'Empty package file accepted; the website rejects it.' }
    Remove-Item -LiteralPath $emptyFile
    # The website rejects '\' entry names (HTTP 422); Windows PowerShell 5.1 Compress-Archive wrote them.
    New-ZipFromDirectory -SourceDirectory $featureRoot -ZipPath "$featureRoot.zip"
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead("$featureRoot.zip")
    try { $entryNames = @($zip.Entries | ForEach-Object { $_.FullName }) }
    finally { $zip.Dispose() }
    if ($entryNames.Count -ne ($requiredFiles.Count + 3) -or
        @($entryNames | Where-Object { $_.Contains('\') -or $_.EndsWith('/') }).Count -gt 0 -or
        'reframework/autorun/func/Training_SharedUI.lua' -cnotin $entryNames -or 'dinput8.dll' -cnotin $entryNames) {
        throw 'Release ZIP must store only file entries with forward-slash paths.'
    }
    foreach ($relative in @('安装说明.txt', 'reframework-extra/test.txt')) {
        $target = Join-Path $featureRoot $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        Set-Content -LiteralPath $target -Value 'x'
        $rejected = $false
        try { Assert-FullPackagePublishPaths -PackageRoot $featureRoot }
        catch { $rejected = $_.Exception.Message -match 'outside the publication allowlist' }
        if (-not $rejected) { throw "Invalid publication path accepted: $relative" }
        Remove-Item -LiteralPath $target
    }
    foreach ($relative in $requiredFiles) {
        $target = Join-Path $featureRoot "reframework/$relative"
        Remove-Item -LiteralPath $target
        $rejected = $false
        try { Assert-FullPackageFeatures -PackageRoot $featureRoot }
        catch { $rejected = $_.Exception.Message -match 'dependency missing' }
        if (-not $rejected) { throw "Feature dependency was not enforced: $relative" }
        Set-Content -LiteralPath $target -Value 'x'
    }
    New-Item -ItemType File -Path (Join-Path $featureRoot 'reframework/autorun/SF6CC_DynamicRecords.lua') | Out-Null
    $rejected = $false
    try { Assert-FullPackageFeatures -PackageRoot $featureRoot }
    catch { $rejected = $_.Exception.Message -match 'legacy recording manager' }
    if (-not $rejected) { throw 'Legacy and new autorun entries were both accepted.' }
} finally {
    $resolved = (Resolve-Path -LiteralPath $featureRoot).Path
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Leaf $resolved) -notlike 'sf6cc-feature-test-*') { throw 'Unsafe test cleanup' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
    if (Test-Path -LiteralPath "$resolved.zip") { Remove-Item -LiteralPath "$resolved.zip" -Force }
}
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $versionPath).Hash -ne $beforeHash) {
    throw 'Packaging tests changed the canonical product version.'
}
Write-Host "release version tests passed"
