param([string]$GameRoot='D:\Program Files (x86)\Steam\steamapps\common\Street Fighter 6')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$entry=Join-Path $PSScriptRoot 'package_release.ps1'
$out=Join-Path $root ('audit-output/cfn-package-dry-test-'+[guid]::NewGuid().ToString('N'))
$plan=@(& $entry -CFNReplayOnly -GameRoot $GameRoot -OutputDir $out -DryRun)
if(Test-Path -LiteralPath $out){throw 'Dry run wrote package output.'}
$names=@($plan | Where-Object { $_ -match '^(reframework|Prerequisites|Licenses)/|^README.txt$' })
if($names.Count -ne 58){throw 'Unexpected payload count; review dependency closure.'}
if(@($names | Where-Object {$_ -like '*.lua'}).Count -ne 32){throw 'Incomplete Lua closure.'}
if('reframework/CFNRuleEditor/index.html' -notin $names -or 'reframework/CFNRuleEditor/catalog.js' -notin $names){throw 'Rule editor missing.'}
if('reframework/autorun/func/UIKit.lua' -notin $names){throw 'Missing own shared UI utility.'}
if(@($names | Where-Object {$_ -match 'SharedHooks|Training_SessionRecap|Training_Hotkeys'}).Count){throw 'Training-only lifecycle must not be loaded by statistics.'}
if(@($names | Where-Object {$_ -match 'dinput8|managed/generated|(^|/)data/|TestWebAPI|WebAPI'}).Count){throw 'Private, generated or unrelated content included.'}
foreach($required in @('reframework/plugins/source/CFNKeyboardBridge.cs','reframework/plugins/REFramework.NET.dll',
    'reframework/plugins/Ijwhost.dll','reframework/plugins/managed/dependencies/Microsoft.CodeAnalysis.CSharp.dll',
    'reframework/fonts/msyh.ttc','Prerequisites/dotnet-runtime-10-win-x64.exe','Prerequisites/vc_redist.x64.exe','README.txt')){
    if($required -notin $names){throw "Missing dependency: $required"}
}
foreach($extra in @(@{Version='1.1.15'},@{Force=$true},@{FasterSF6Only=$true},@{TrainingLibraryOnly=$true},@{ExcludeDll=$true})){
    $blocked=$false
    try { & $entry -CFNReplayOnly -GameRoot $GameRoot -OutputDir $out -DryRun @extra | Out-Null } catch { $blocked=$true }
    if(-not $blocked){throw 'Conflicting product-release options were accepted.'}
}
$missing=Join-Path $out 'missing-dependencies'
$blocked=$false
try{ & (Join-Path $PSScriptRoot 'cfn_replay_capture/package.ps1') -GameRoot $GameRoot -OutputDir $out -DependencyCache $missing -DryRun | Out-Null }catch{$blocked=$true}
if(-not $blocked -or (Test-Path -LiteralPath $out)){throw 'Missing dependencies must fail without creating output.'}
'PASS: standalone dependency closure, required installers, private-data exclusion, read-only dry run and release-option guards.'
