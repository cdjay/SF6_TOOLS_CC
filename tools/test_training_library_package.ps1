param(
    [Parameter(Mandatory=$true)][string]$PackageRoot,
    [Parameter(Mandatory=$true)][string]$ZipPath,
    [string]$Lua='C:\Users\76025\AppData\Local\Programs\Lua\bin\lua.exe'
)
$ErrorActionPreference='Stop'
$root=(Resolve-Path -LiteralPath $PackageRoot).Path
$repo=Split-Path -Parent $PSScriptRoot
$manifest=Get-Content -LiteralPath (Join-Path $root 'package_manifest.json') -Raw | ConvertFrom-Json
$canonical=Get-Content -LiteralPath (Join-Path $repo 'data/SF6CC/version.json') -Raw | ConvertFrom-Json
if($manifest.product_version -ne $canonical.product.version){throw 'Package version mismatch'}
if($manifest.commit -ne (& git -C $repo rev-parse HEAD)){throw 'Package source commit mismatch'}
$paths=@{}
foreach($entry in $manifest.files){
    $relative=$entry.path.Replace('\','/')
    if($paths.ContainsKey($relative)){throw "Duplicate manifest entry: $relative"}
    $path=[IO.Path]::GetFullPath((Join-Path $root $relative))
    if(-not $path.StartsWith($root.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe manifest path'}
    if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $entry.sha256){throw "Package hash mismatch: $relative"}
    if((Get-Item -LiteralPath $path).Length -ne $entry.bytes){throw "Package length mismatch: $relative"}
    $paths[$relative]=$true
}
foreach($required in @('dinput8.dll','reframework/木人库使用说明.md','reframework/autorun/SF6CC_TrainingLibrary.lua',
    'reframework/data/SF6CC/version.json','reframework/LICENSE','reframework/LICENSE_NOTES.md')){
    if(-not $paths.ContainsKey($required)){throw "Missing package requirement: $required"}
}
$scripts=@(Get-ChildItem -LiteralPath (Join-Path $root 'reframework/autorun') -Recurse -Filter '*.lua')
foreach($script in $scripts){
    $text=Get-Content -LiteralPath $script.FullName -Raw
    foreach($match in [regex]::Matches($text,'require\s*\(?\s*["'']([^"'']+)["'']')){
        $name=$match.Groups[1].Value
        if(-not $name.StartsWith('SF6CCTrainingLibrary/')){throw "External Lua dependency: $name"}
        if(-not $paths.ContainsKey("reframework/autorun/$name.lua")){throw "Missing Lua dependency: $name"}
    }
}
$entry=Get-Content -LiteralPath (Join-Path $root 'reframework/autorun/SF6CC_TrainingLibrary.lua') -Raw
if($entry -notmatch 'pcall\(require,"SF6CCTrainingLibrary/NativeLibraryTab"\)'){throw 'Native menu entry missing'}
$configs=@(Get-ChildItem -LiteralPath (Join-Path $root 'reframework/data/SF6CC_TrainingConfigs/configs') -Filter '*.json')
if($configs.Count -ne $manifest.configurations){throw 'Configuration count mismatch'}
foreach($config in $configs){
    $value=Get-Content -LiteralPath $config.FullName -Raw | ConvertFrom-Json
    if($value.schema -notin @('sf6cc.training_setup.v2','sf6cc.dynamic_records.v1') -or $null -eq $value.fighter_id -or $null -eq $value.slots){throw 'Invalid packaged configuration'}
}
foreach($path in $paths.Keys){
    if($path -match '(^|/)(exam|docs|logs|plugins|backups|audit-output)/' -or $path -match '\.(log|cs|pdb)$'){
        throw "Development artifact in package: $path"
    }
}
Push-Location $repo
try {
    & $Lua tools/test_training_standalone.lua (Join-Path $root 'reframework')
    if($LASTEXITCODE){throw 'Packaged standalone entry failed'}
} finally {Pop-Location}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip=[IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $ZipPath).Path)
try {
    $entries=@($zip.Entries | Where-Object {$_.Name -ne ''})
    if($entries.Count -ne $paths.Count+1){throw 'ZIP entry count differs from manifest'}
    foreach($file in $entries){
        $name=$file.FullName.Replace('\','/')
        if($name -ne 'package_manifest.json' -and -not $paths.ContainsKey($name)){throw "Unexpected ZIP entry: $name"}
        $stream=$file.Open(); $sha=[Security.Cryptography.SHA256]::Create()
        try { $hash=[BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','') }
        finally {$stream.Dispose(); $sha.Dispose()}
        if($hash -ne (Get-FileHash -LiteralPath (Join-Path $root $name)).Hash){throw "ZIP content mismatch: $name"}
    }
} finally {$zip.Dispose()}
Write-Host "PASS standalone package: $($scripts.Count) Lua files, $($configs.Count) configurations, manifest and ZIP hashes verified."
