param(
    [ValidateSet("Major", "Minor", "Patch")]
    [string]$Part,
    [string]$Version,
    [string]$Workspace,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Resolve-Workspace {
    param([string]$RequestedWorkspace)

    $scriptDirectory = if ($PSScriptRoot) {
        $PSScriptRoot
    }
    else {
        Split-Path -Parent $MyInvocation.MyCommand.Path
    }
    $candidate = if ([string]::IsNullOrWhiteSpace($RequestedWorkspace)) {
        Split-Path -Parent $scriptDirectory
    }
    else {
        $RequestedWorkspace
    }

    if (-not (Test-Path -LiteralPath $candidate -PathType Container)) {
        throw "Workspace not found: $candidate"
    }
    return (Resolve-Path -LiteralPath $candidate).Path
}

function Assert-SemanticVersion {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if ($Value -notmatch '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$') {
        throw "$Label must be a semantic version such as 1.0.3: $Value"
    }
}

function Get-BumpedVersion {
    param(
        [Parameter(Mandatory = $true)][string]$CurrentVersion,
        [Parameter(Mandatory = $true)][string]$BumpPart
    )

    Assert-SemanticVersion -Value $CurrentVersion -Label "Current product version"
    $core = $CurrentVersion.Split("-", 2)[0].Split("+", 2)[0]
    $numbers = @($core.Split(".") | ForEach-Object { [uint64]$_ })

    switch ($BumpPart) {
        "Major" { return "$($numbers[0] + 1).0.0" }
        "Minor" { return "$($numbers[0]).$($numbers[1] + 1).0" }
        "Patch" { return "$($numbers[0]).$($numbers[1]).$($numbers[2] + 1)" }
    }
}

if ([string]::IsNullOrWhiteSpace($Part) -eq [string]::IsNullOrWhiteSpace($Version)) {
    throw "Choose exactly one target: -Part Major|Minor|Patch or -Version <semantic-version>."
}

$workspacePath = Resolve-Workspace -RequestedWorkspace $Workspace
$versionPath = Join-Path $workspacePath "data\SF6CC\version.json"
if (-not (Test-Path -LiteralPath $versionPath -PathType Leaf)) {
    throw "Product version file not found: $versionPath"
}

$versionText = Get-Content -Raw -LiteralPath $versionPath
$document = $versionText | ConvertFrom-Json
$invalidDocument = $document.schema -ne "sf6cc.product_version.v1" -or
    $null -eq $document.product -or
    [string]::IsNullOrWhiteSpace([string]$document.product.version)
if ($invalidDocument) {
    throw "Product version file is invalid: $versionPath"
}

$currentVersion = [string]$document.product.version
Assert-SemanticVersion -Value $currentVersion -Label "Current product version"

$targetVersion = if (-not [string]::IsNullOrWhiteSpace($Version)) {
    $Version.Trim()
}
else {
    Get-BumpedVersion -CurrentVersion $currentVersion -BumpPart $Part
}
Assert-SemanticVersion -Value $targetVersion -Label "Target product version"

if ($targetVersion -eq $currentVersion) {
    throw "Target product version is unchanged: $targetVersion"
}

Write-Host "SF6CC product version:"
Write-Host "  Source:  $versionPath"
Write-Host "  Current: $currentVersion"
Write-Host "  Target:  $targetVersion"

if ($DryRun) {
    Write-Host "Dry run complete. The version file was not changed."
    return
}

$productVersionPattern = '(?s)("product"\s*:\s*\{(?:(?!\}).)*?"version"\s*:\s*")([^"]+)(")'
$versionMatches = [regex]::Matches($versionText, $productVersionPattern)
if ($versionMatches.Count -ne 1 -or $versionMatches[0].Groups[2].Value -ne $currentVersion) {
    throw "Could not locate the canonical product version field in: $versionPath"
}

$replaceVersion = [System.Text.RegularExpressions.MatchEvaluator] {
    param($match)
    return $match.Groups[1].Value + $targetVersion + $match.Groups[3].Value
}
$jsonText = [regex]::Replace($versionText, $productVersionPattern, $replaceVersion, 1)
$tempPath = Join-Path (Split-Path -Parent $versionPath) (".version-" + [guid]::NewGuid().ToString("N") + ".tmp")
try {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($tempPath, $jsonText, $utf8NoBom)
    Move-Item -LiteralPath $tempPath -Destination $versionPath -Force
}
finally {
    if (Test-Path -LiteralPath $tempPath) {
        Remove-Item -LiteralPath $tempPath -Force
    }
}

Write-Host "Version updated. Review and commit the version file before packaging."
