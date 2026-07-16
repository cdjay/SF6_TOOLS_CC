param(
    [string]$Version,
    [string]$Workspace,
    [string]$GameRoot = "D:\Program Files (x86)\Steam\steamapps\common\Street Fighter 6",
    [string]$OutputDir,
    [switch]$Force,
    [switch]$DryRun,
    [switch]$AllowImmutable,
    [switch]$UpdateRepoManifest,
    [switch]$TrainingConfigManagerOnly
)

$ErrorActionPreference = "Stop"

function Resolve-ExistingPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$Label not found: $Path"
    }

    return (Resolve-Path -LiteralPath $Path).Path
}

function Resolve-OutputRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][bool]$AllowCreate
    )

    if (Test-Path -LiteralPath $Path) {
        return (Resolve-Path -LiteralPath $Path).Path
    }

    if (-not $AllowCreate) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    New-Item -ItemType Directory -Path $Path | Out-Null
    return (Resolve-Path -LiteralPath $Path).Path
}

function Assert-ChildPath {
    param(
        [Parameter(Mandatory = $true)][string]$ChildPath,
        [Parameter(Mandatory = $true)][string]$ParentPath
    )

    $childFull = [System.IO.Path]::GetFullPath($ChildPath)
    $parentFull = [System.IO.Path]::GetFullPath($ParentPath).TrimEnd('\') + '\'
    if (-not $childFull.StartsWith($parentFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to modify path outside output directory: $childFull"
    }
}

function Get-GitValue {
    param(
        [Parameter(Mandatory = $true)][string]$WorkspacePath,
        [Parameter(Mandatory = $true)][string[]]$Args
    )

    $value = & git -C $WorkspacePath @Args
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Args -join ' ') failed."
    }

    return (($value | Out-String).Trim())
}

function Get-SourceManifestVersion {
    param([Parameter(Mandatory = $true)][string]$WorkspacePath)

    $repoManifestPath = Join-Path $WorkspacePath "sf6cm_manifest.json"
    if (-not (Test-Path -LiteralPath $repoManifestPath)) {
        return "(missing)"
    }

    $repoManifest = Get-Content -Raw -LiteralPath $repoManifestPath | ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace($repoManifest.version)) {
        return "(empty)"
    }

    return [string]$repoManifest.version
}

function Assert-ValidReleaseVersion {
    param([Parameter(Mandatory = $true)][string]$ReleaseVersion)

    if ($ReleaseVersion -match '[\\/:\*\?"<>\|]' -or $ReleaseVersion.Contains("..")) {
        throw "Release version contains invalid path characters: $ReleaseVersion"
    }

    if ($ReleaseVersion -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
        throw "Release version has an invalid format: $ReleaseVersion"
    }
}

function Get-VersionOutputArtifacts {
    param([Parameter(Mandatory = $true)][string]$VersionOutputPath)

    if (-not (Test-Path -LiteralPath $VersionOutputPath)) {
        return @()
    }

    return @(Get-ChildItem -LiteralPath $VersionOutputPath -Force | Sort-Object FullName)
}

function Backup-VersionOutput {
    param(
        [Parameter(Mandatory = $true)][string]$VersionOutputPath,
        [Parameter(Mandatory = $true)][string]$OutputRoot,
        [Parameter(Mandatory = $true)][string]$ReleaseVersion
    )

    if (-not (Test-Path -LiteralPath $VersionOutputPath)) {
        return $null
    }

    Assert-ChildPath -ChildPath $VersionOutputPath -ParentPath $OutputRoot

    $existingItems = @(Get-ChildItem -LiteralPath $VersionOutputPath -Force)
    if ($existingItems.Count -eq 0) {
        Remove-Item -LiteralPath $VersionOutputPath -Force
        return $null
    }

    $backupRoot = Join-Path $OutputRoot "backups"
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupPath = Join-Path $backupRoot "${ReleaseVersion}_$timestamp"
    if (Test-Path -LiteralPath $backupPath) {
        throw "Backup destination already exists: $backupPath"
    }

    New-Item -ItemType Directory -Path $backupPath | Out-Null
    foreach ($item in $existingItems) {
        Move-Item -LiteralPath $item.FullName -Destination $backupPath
    }

    Remove-Item -LiteralPath $VersionOutputPath -Force
    return $backupPath
}

function Copy-TrackedReframeworkFiles {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$PackageRoot
    )

    $trackedFiles = & git -C $SourceRoot ls-files -- autorun data fonts images plugins
    if ($LASTEXITCODE -ne 0) {
        throw "git ls-files failed. Run this script inside a Git checkout."
    }

    $untrackedFiles = & git -C $SourceRoot ls-files --others --exclude-standard -- autorun data fonts images plugins
    if ($LASTEXITCODE -ne 0) {
        throw "git ls-files for untracked files failed. Run this script inside a Git checkout."
    }

    if ($untrackedFiles.Count -gt 0) {
        $preview = ($untrackedFiles | Select-Object -First 20) -join [Environment]::NewLine
        throw "Untracked package-source files exist. Track them or move them before packaging:$([Environment]::NewLine)$preview"
    }

    $releaseExcludedTrackedFiles = @(
        "autorun/SF6CC_DynamicRecords.lua",
        "autorun/func/DynamicRecords.lua"
    )
    $releaseExcludedSet = @{}
    foreach ($excludedPath in $releaseExcludedTrackedFiles) {
        $releaseExcludedSet[$excludedPath.ToLowerInvariant()] = $true
    }

    foreach ($relativePath in $trackedFiles) {
        if ([string]::IsNullOrWhiteSpace($relativePath)) {
            continue
        }
        $normalizedRelativePath = ($relativePath -replace '\\', '/').ToLowerInvariant()
        if ($releaseExcludedSet.ContainsKey($normalizedRelativePath)) {
            continue
        }

        $windowsRelativePath = $relativePath -replace '/', '\'
        $sourcePath = Join-Path $SourceRoot $windowsRelativePath
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            throw "Tracked file is missing: $sourcePath"
        }

        $destinationPath = Join-Path $PackageRoot (Join-Path "reframework" $windowsRelativePath)
        $destinationDirectory = Split-Path -Parent $destinationPath
        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
        Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
    }
}

function New-ZipFromDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$SourceDirectory,
        [Parameter(Mandatory = $true)][string]$ZipPath
    )

    if (Test-Path -LiteralPath $ZipPath) {
        throw "Target zip already exists after preflight cleanup: $ZipPath"
    }

    $zipItems = Join-Path $SourceDirectory "*"
    Compress-Archive -Path $zipItems -DestinationPath $ZipPath -CompressionLevel Optimal
}

function Copy-SelectedTrackedReframeworkFiles {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$PackageRoot,
        [Parameter(Mandatory = $true)][string[]]$RelativePaths
    )

    foreach ($relativePath in $RelativePaths) {
        & git -C $SourceRoot ls-files --error-unmatch -- $relativePath | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Required component package file is not Git-tracked: $relativePath"
        }

        $windowsRelativePath = $relativePath -replace '/', '\\'
        $sourcePath = Join-Path $SourceRoot $windowsRelativePath
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            throw "Required component package file is missing: $sourcePath"
        }

        $destinationPath = Join-Path $PackageRoot (Join-Path "reframework" $windowsRelativePath)
        $destinationDirectory = Split-Path -Parent $destinationPath
        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
        Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
    }
}

function Get-ReleaseFileEntry {
    param(
        [Parameter(Mandatory = $true)][System.IO.FileInfo]$File,
        [Parameter(Mandatory = $true)][string]$RootPath,
        [Parameter(Mandatory = $true)][string]$ReleaseVersion
    )

    $relativePath = $File.FullName.Substring($RootPath.Length + 1)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $stream = [System.IO.File]::OpenRead($File.FullName)
    try {
        $hashBytes = $sha256.ComputeHash($stream)
        $hash = [System.BitConverter]::ToString($hashBytes).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $stream.Dispose()
        $sha256.Dispose()
    }

    [pscustomobject]@{
        path = $relativePath
        version = $ReleaseVersion
        sha256 = $hash
        required = $true
    }
}

function New-ReleaseManifest {
    param(
        [Parameter(Mandatory = $true)][string]$RuntimePackageRoot,
        [Parameter(Mandatory = $true)][string]$ReleaseVersion,
        [Parameter(Mandatory = $true)][string]$RuntimeZipName
    )

    $rootPath = (Resolve-Path -LiteralPath $RuntimePackageRoot).Path
    $files = Get-ChildItem -LiteralPath $RuntimePackageRoot -Recurse -File |
        Sort-Object FullName |
        ForEach-Object { Get-ReleaseFileEntry -File $_ -RootPath $rootPath -ReleaseVersion $ReleaseVersion }

    [pscustomobject]@{
        version = $ReleaseVersion
        sourceZip = $RuntimeZipName
        files = @($files)
    }
}

function Assert-ManifestVersionConsistency {
    param(
        [Parameter(Mandatory = $true)]$Manifest,
        [Parameter(Mandatory = $true)][string]$ReleaseVersion,
        [Parameter(Mandatory = $true)][string]$RuntimeZipName
    )

    if ([string]$Manifest.version -ne $ReleaseVersion) {
        throw "Generated manifest version does not match -Version."
    }

    if ([string]$Manifest.sourceZip -ne $RuntimeZipName) {
        throw "Generated manifest sourceZip does not match runtime package filename."
    }

    foreach ($file in @($Manifest.files)) {
        if ([string]$file.version -ne $ReleaseVersion) {
            throw "Generated manifest file entry has mismatched version: $($file.path)"
        }
    }
}

function Write-PlanSummary {
    param(
        [Parameter(Mandatory = $true)][string]$ReleaseVersion,
        [Parameter(Mandatory = $true)][string]$Branch,
        [Parameter(Mandatory = $true)][string]$HeadCommit,
        [Parameter(Mandatory = $true)][string]$OutputPath,
        [Parameter(Mandatory = $true)][string]$SourceManifestVersion,
        [Parameter(Mandatory = $true)][string[]]$PackageFilenames,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$ExistingArtifacts,
        [Parameter(Mandatory = $true)][bool]$WillOverwrite,
        [string]$BackupPath
    )

    Write-Host "Release package plan:"
    Write-Host "  Version:                 $ReleaseVersion"
    Write-Host "  Branch:                  $Branch"
    Write-Host "  HEAD commit:             $HeadCommit"
    Write-Host "  Output dir:              $OutputPath"
    Write-Host "  Source manifest version: $SourceManifestVersion"
    Write-Host "  Package filenames:"
    foreach ($name in $PackageFilenames) {
        Write-Host "    - $name"
    }
    Write-Host "  Existing artifacts:"
    if ($ExistingArtifacts.Count -eq 0) {
        Write-Host "    - (none)"
    }
    else {
        foreach ($artifact in $ExistingArtifacts) {
            Write-Host "    - $($artifact.FullName)"
        }
    }
    Write-Host "  Will overwrite:          $WillOverwrite"
    if (-not [string]::IsNullOrWhiteSpace($BackupPath)) {
        Write-Host "  Backup dir:              $BackupPath"
    }
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    throw "Version is required. Pass an explicit target version, for example: tools\package_release.bat -Version 0.9c"
}

$releaseVersion = $Version.Trim()
if ($releaseVersion.StartsWith("v", [System.StringComparison]::OrdinalIgnoreCase)) {
    $releaseVersion = $releaseVersion.Substring(1)
}
if ([string]::IsNullOrWhiteSpace($releaseVersion)) {
    throw "Release version cannot be empty."
}
Assert-ValidReleaseVersion -ReleaseVersion $releaseVersion

$scriptDirectory = if ($PSScriptRoot) {
    $PSScriptRoot
}
else {
    Split-Path -Parent $MyInvocation.MyCommand.Path
}
$defaultWorkspace = Split-Path -Parent $scriptDirectory

if ([string]::IsNullOrWhiteSpace($Workspace)) {
    $Workspace = $defaultWorkspace
}

$workspacePath = Resolve-ExistingPath -Path $Workspace -Label "Workspace"
$headCommit = Get-GitValue -WorkspacePath $workspacePath -Args @("rev-parse", "HEAD")
$branch = Get-GitValue -WorkspacePath $workspacePath -Args @("branch", "--show-current")
if ([string]::IsNullOrWhiteSpace($branch)) {
    $branch = "(detached)"
}

if ($releaseVersion.Equals("0.9a", [System.StringComparison]::OrdinalIgnoreCase)) {
    if (-not $AllowImmutable) {
        throw "Release 0.9a is immutable. Ordinary packaging is not allowed. Use -AllowImmutable only from the matching 0.9a tag/commit/worktree."
    }

    $stable09aCommit = "2a156db4ec040cdad8496eb3699e75fb042f6c4f"
    if (-not $headCommit.Equals($stable09aCommit, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Release 0.9a may only be rebuilt from commit $stable09aCommit. Current HEAD is $headCommit."
    }
}

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $workspacePath "release"
}

$baseOutputPath = Resolve-OutputRoot -Path $OutputDir -AllowCreate (-not [bool]$DryRun)
$outputPath = Join-Path $baseOutputPath $releaseVersion
$sourceManifestVersion = Get-SourceManifestVersion -WorkspacePath $workspacePath

if ($TrainingConfigManagerOnly) {
    $componentPackageName = "XiaoTun_SF6_TrainingConfigManager_v$releaseVersion"
    $componentZipName = "$componentPackageName.zip"
    $componentPackagePath = Join-Path $outputPath $componentPackageName
    $componentZipPath = Join-Path $outputPath $componentZipName
    $packageFilenames = @($componentZipName)
}
else {
    $packagePrefix = "XiaoTun_SF6_TrainingMOD_v$releaseVersion"
    $standardPackageName = $packagePrefix
    $runtimePackageName = "${packagePrefix}_runtime"
    $standardZipName = "$standardPackageName.zip"
    $runtimeZipName = "$runtimePackageName.zip"
    $manifestName = "sf6cm_manifest_v$releaseVersion.json"

    $standardPackagePath = Join-Path $outputPath $standardPackageName
    $runtimePackagePath = Join-Path $outputPath $runtimePackageName
    $standardZipPath = Join-Path $outputPath $standardZipName
    $runtimeZipPath = Join-Path $outputPath $runtimeZipName
    $manifestPath = Join-Path $outputPath $manifestName
    $packageFilenames = @($standardZipName, $runtimeZipName, $manifestName)
}
$existingArtifacts = @(Get-VersionOutputArtifacts -VersionOutputPath $outputPath)
$willOverwrite = $existingArtifacts.Count -gt 0
$plannedBackupPath = if ($willOverwrite -and $Force) {
    Join-Path (Join-Path $baseOutputPath "backups") ("${releaseVersion}_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
}
else {
    $null
}

if ($willOverwrite -and -not $Force) {
    Write-PlanSummary -ReleaseVersion $releaseVersion `
        -Branch $branch `
        -HeadCommit $headCommit `
        -OutputPath $outputPath `
        -SourceManifestVersion $sourceManifestVersion `
        -PackageFilenames $packageFilenames `
        -ExistingArtifacts $existingArtifacts `
        -WillOverwrite $willOverwrite
    throw "Version output already exists. Re-run with -Force to back it up before overwriting: $outputPath"
}

Write-PlanSummary -ReleaseVersion $releaseVersion `
    -Branch $branch `
    -HeadCommit $headCommit `
    -OutputPath $outputPath `
    -SourceManifestVersion $sourceManifestVersion `
    -PackageFilenames $packageFilenames `
    -ExistingArtifacts $existingArtifacts `
    -WillOverwrite $willOverwrite `
    -BackupPath $plannedBackupPath

if ($DryRun) {
    Write-Host "Dry run complete. No package files were generated."
    return
}

if ($TrainingConfigManagerOnly) {
    if ($willOverwrite) {
        $actualBackupPath = Backup-VersionOutput -VersionOutputPath $outputPath -OutputRoot $baseOutputPath -ReleaseVersion $releaseVersion
        if (-not [string]::IsNullOrWhiteSpace($actualBackupPath)) {
            Write-Host "Existing version output backed up to: $actualBackupPath"
        }
    }

    if (-not (Test-Path -LiteralPath $outputPath)) {
        New-Item -ItemType Directory -Path $outputPath | Out-Null
    }

    New-Item -ItemType Directory -Path $componentPackagePath | Out-Null
    Copy-SelectedTrackedReframeworkFiles -SourceRoot $workspacePath -PackageRoot $componentPackagePath -RelativePaths @(
        "autorun/SF6CC_DynamicRecords.lua",
        "autorun/func/DynamicRecords.lua",
        "data/SF6CC_TrainingConfigs/editor/SF6CC_TrainingConfigEditor.html"
    )
    New-ZipFromDirectory -SourceDirectory $componentPackagePath -ZipPath $componentZipPath

    Write-Host "Training configuration manager component packaged successfully."
    Write-Host "Output directory: $outputPath"
    Write-Host "Package: $componentZipPath"
    return
}

$gameRootPath = Resolve-ExistingPath -Path $GameRoot -Label "Game root"
$dinputPath = Resolve-ExistingPath -Path (Join-Path $gameRootPath "dinput8.dll") -Label "dinput8.dll"
$configPath = Resolve-ExistingPath -Path (Join-Path $gameRootPath "re2_fw_config.txt") -Label "re2_fw_config.txt"

if ($willOverwrite) {
    $actualBackupPath = Backup-VersionOutput -VersionOutputPath $outputPath -OutputRoot $baseOutputPath -ReleaseVersion $releaseVersion
    if (-not [string]::IsNullOrWhiteSpace($actualBackupPath)) {
        Write-Host "Existing version output backed up to: $actualBackupPath"
    }
}

if (-not (Test-Path -LiteralPath $outputPath)) {
    New-Item -ItemType Directory -Path $outputPath | Out-Null
}

New-Item -ItemType Directory -Path $standardPackagePath | Out-Null
New-Item -ItemType Directory -Path $runtimePackagePath | Out-Null

Copy-TrackedReframeworkFiles -SourceRoot $workspacePath -PackageRoot $standardPackagePath
Copy-TrackedReframeworkFiles -SourceRoot $workspacePath -PackageRoot $runtimePackagePath

Copy-Item -LiteralPath $dinputPath -Destination (Join-Path $standardPackagePath "dinput8.dll") -Force
Copy-Item -LiteralPath $dinputPath -Destination (Join-Path $runtimePackagePath "dinput8.dll") -Force
Copy-Item -LiteralPath $configPath -Destination (Join-Path $runtimePackagePath "re2_fw_config.txt") -Force

New-ZipFromDirectory -SourceDirectory $standardPackagePath -ZipPath $standardZipPath
New-ZipFromDirectory -SourceDirectory $runtimePackagePath -ZipPath $runtimeZipPath

$manifest = New-ReleaseManifest -RuntimePackageRoot $runtimePackagePath -ReleaseVersion $releaseVersion -RuntimeZipName $runtimeZipName
Assert-ManifestVersionConsistency -Manifest $manifest -ReleaseVersion $releaseVersion -RuntimeZipName $runtimeZipName
$manifestJson = $manifest | ConvertTo-Json -Depth 5
Set-Content -LiteralPath $manifestPath -Value $manifestJson -Encoding UTF8

if ($UpdateRepoManifest) {
    Set-Content -LiteralPath (Join-Path $workspacePath "sf6cm_manifest.json") -Value $manifestJson -Encoding UTF8
}

Write-Host "Release packaged successfully."
Write-Host "Output directory: $outputPath"
Write-Host "Standard package: $standardZipPath"
Write-Host "Runtime package:  $runtimeZipPath"
Write-Host "Manifest:         $manifestPath"
