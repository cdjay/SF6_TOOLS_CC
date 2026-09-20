[CmdletBinding()]
param(
    [string]$GameRoot = 'D:\Program Files (x86)\Steam\steamapps\common\Street Fighter 6',
    [string]$OutputDir,
    [string]$DependencyCache,
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Security/Microsoft.PowerShell.Security.psd1') -Force
Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Utility/Microsoft.PowerShell.Utility.psd1') -Force
$workspace = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
if (-not $DependencyCache) { $DependencyCache = Join-Path $workspace 'audit-output/cfn-package-dependencies' }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if (-not $OutputDir) { $OutputDir = Join-Path $workspace "release/cfn-replay-preview-$stamp" }
$out = [IO.Path]::GetFullPath($OutputDir)
$zipPath = Join-Path $out "SF6_ReplayAnalysis_Preview_${stamp}_WithDependencies.zip"
if (Test-Path -LiteralPath $out) { throw "Refusing to reuse output directory: $out" }
$files = [ordered]@{}
function Add-Payload([string]$Name, [string]$Source) {
    if ($Name -match '(^|/)\.\.(/|$)|^/|\\|:' -or $files.Contains($Name)) { throw "Unsafe or duplicate package path: $Name" }
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { throw "Required file missing: $Source" }
    $files[$Name] = (Resolve-Path -LiteralPath $Source).Path
}
# Follow plugin-local modules and the one hook-free SF6CC UI utility.
$pending = New-Object 'System.Collections.Generic.Queue[string]'
$seen = @{}
$pending.Enqueue('CFN_ReplayCapture.lua')
while ($pending.Count -gt 0) {
    $name = $pending.Dequeue()
    if ($seen.ContainsKey($name)) { continue }
    $seen[$name] = $true
    $source = if ($name -eq 'func/UIKit.lua') { Join-Path $workspace 'autorun/func/UIKit.lua' } else { Join-Path $PSScriptRoot $name }
    $relative = if ($name -eq 'CFN_ReplayCapture.lua' -or $name -eq 'func/UIKit.lua') { "reframework/autorun/$name" } else { "reframework/autorun/func/CFNReplayCapture/$name" }
    Add-Payload $relative $source
    $text = [IO.File]::ReadAllText($source)
    foreach ($match in [regex]::Matches($text, 'require\s*\(\s*["'']([^"'']+)["'']\s*\)')) {
        $dependency = $match.Groups[1].Value
        if ($dependency -eq 'func/UIKit') { $pending.Enqueue('func/UIKit.lua') }
        elseif ($dependency -match '^func/CFNReplayCapture/([A-Za-z_][A-Za-z_0-9]*)$') { $pending.Enqueue($Matches[1] + '.lua') }
        else { throw "Unexpected Lua dependency in $name" }
    }
}
Add-Payload 'reframework/plugins/source/CFNKeyboardBridge.cs' (Join-Path $PSScriptRoot 'CFNKeyboardBridge.cs')
Add-Payload 'reframework/fonts/msyh.ttc' (Join-Path $workspace 'fonts/msyh.ttc')
$pluginRoot = Join-Path $GameRoot 'reframework/plugins'
$runtimeFiles = @('REFramework.NET.dll','Ijwhost.dll','REFramework.NET.runtimeconfig.json',
    'managed/dependencies/AssemblyGenerator.dll','managed/dependencies/REFCoreDeps.dll',
    'managed/dependencies/Hexa.NET.ImGui.dll','managed/dependencies/HexaGen.Runtime.dll',
    'managed/dependencies/Microsoft.CodeAnalysis.dll','managed/dependencies/Microsoft.CodeAnalysis.CSharp.dll')
foreach ($file in $runtimeFiles) { Add-Payload "reframework/plugins/$file" (Join-Path $pluginRoot $file) }
$config = Get-Content -LiteralPath (Join-Path $pluginRoot 'REFramework.NET.runtimeconfig.json') -Raw | ConvertFrom-Json
if ($config.runtimeOptions.framework.name -ne 'Microsoft.NETCore.App' -or $config.runtimeOptions.framework.version -notmatch '^10\.') {
    throw 'Recheck the .NET prerequisite: the installed plugin runtime contract changed.'
}
$sources = Get-Content -LiteralPath (Join-Path $DependencyCache 'sources.json') -Raw | ConvertFrom-Json
if ($sources.runtime_version -notmatch '^10\.' -or $sources.runtime_url -notmatch '^https://builds\.dotnet\.microsoft\.com/' -or $sources.vc_url -ne 'https://aka.ms/vc14/vc_redist.x64.exe') {
    throw 'Unexpected prerequisite origin.'
}
foreach ($installer in @('dotnet-runtime-10-win-x64.exe','vc_redist.x64.exe')) {
    $path = Join-Path $DependencyCache $installer
    $signature = Get-AuthenticodeSignature -LiteralPath $path
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') { throw "Unverified installer: $installer" }
    Add-Payload "Prerequisites/$installer" $path
}
if ((Get-FileHash -LiteralPath (Join-Path $DependencyCache 'dotnet-runtime-10-win-x64.exe') -Algorithm SHA512).Hash -ne $sources.sha512) {
    throw '.NET installer does not match the official release checksum.'
}
foreach ($name in @('REFramework-LICENSE.txt','roslyn-LICENSE.txt','Hexa.NET.ImGui-LICENSE.txt','HexaGen-LICENSE.txt')) {
    Add-Payload "Licenses/$name" (Join-Path $DependencyCache $name)
}
Add-Payload 'README.txt' (Join-Path $PSScriptRoot 'INSTALL.zh-CN.txt')
foreach($name in @('index.html','editor.css','catalog.js','model.js','editor.js','game-files.js','timeline-model.js','timeline.js')) {
    Add-Payload "reframework/CFNRuleEditor/$name" (Join-Path $PSScriptRoot "rule_editor/$name")
}
$inventory = @($files.GetEnumerator() | ForEach-Object {
    [ordered]@{path=$_.Key;bytes=(Get-Item -LiteralPath $_.Value).Length;sha256=(Get-FileHash -LiteralPath $_.Value -Algorithm SHA256).Hash}
})
foreach ($entry in $inventory) {
    if ($entry.path -match 'dinput8\.dll|(^|/)data/|managed/generated/|WebAPI|TestWebAPI|\.zip$') { throw "Forbidden package content: $($entry.path)" }
}
$commit = & git -C $workspace rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Cannot read repository identity.' }
$manifest = [ordered]@{
    schema='sf6cc.cfn_replay_preview_package.v1'; kind='isolated-preview'; created_at=(Get-Date).ToUniversalTime().ToString('o')
    source_base_commit=$commit; source_mode='working-tree'; official_product_release=$false
    includes_dinput8=$false; includes_personal_data=$false; lua_files=$seen.Count
    prerequisites=[ordered]@{dotnet=$sources.runtime_version;dotnet_url=$sources.runtime_url;vc_url=$sources.vc_url;installed_automatically=$false}
    files=$inventory
} | ConvertTo-Json -Depth 8
Write-Output "Preview package: $zipPath"
Write-Output "Lua: $($seen.Count); payload: $($files.Count) files + manifest; includes .NET dependencies and official prerequisite installers; excludes dinput8.dll and personal data."
if ($DryRun) { $files.Keys; return }
New-Item -ItemType Directory -Path $out | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression
$zip = [IO.Compression.ZipFile]::Open($zipPath,[IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($pair in $files.GetEnumerator()) {
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$pair.Value,$pair.Key,[IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
    $entry = $zip.CreateEntry('package_manifest.json')
    $stream = $entry.Open()
    try { $bytes=[Text.Encoding]::UTF8.GetBytes($manifest);$stream.Write($bytes,0,$bytes.Length) } finally { $stream.Dispose() }
} finally { $zip.Dispose() }
# Check every compressed entry against the planned file hash without extracting executable content.
$zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    if ($zip.Entries.Count -ne $files.Count+1) { throw 'Archive entry count mismatch.' }
    foreach ($record in $inventory) {
        $entry=$zip.GetEntry($record.path)
        if (-not $entry -or $entry.Length -ne $record.bytes) { throw "Archive size mismatch: $($record.path)" }
        $stream=$entry.Open();$sha=[Security.Cryptography.SHA256]::Create()
        try { $hash=[BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','') } finally { $sha.Dispose();$stream.Dispose() }
        if ($hash -ne $record.sha256) { throw "Archive hash mismatch: $($record.path)" }
    }
} finally { $zip.Dispose() }
$archiveHash=(Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
"$archiveHash  $([IO.Path]::GetFileName($zipPath))" | Set-Content -LiteralPath (Join-Path $out 'SHA256.txt') -Encoding ASCII
Write-Output "Verified: $($inventory.Count) payload hashes; $([math]::Round((Get-Item -LiteralPath $zipPath).Length/1MB,2)) MiB. No installation performed."
