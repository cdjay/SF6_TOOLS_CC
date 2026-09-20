[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$GameReframework = 'D:\Program Files (x86)\Steam\steamapps\common\Street Fighter 6\reframework'
)
$ErrorActionPreference = 'Stop'
if (Get-Process -Name 'StreetFighter6' -ErrorAction SilentlyContinue) {
    throw 'Close Street Fighter 6 before installing the experimental capture hook. Do not use Reset Scripts.'
}
$target = (Resolve-Path -LiteralPath $GameReframework).Path
if ((Split-Path -Leaf $target) -ne 'reframework') { throw 'Target must be a reframework directory.' }
$autorun = Join-Path $target 'autorun'
$modules = Join-Path $autorun 'func\CFNReplayCapture'
$files = @('schema.lua', 'session.lua', 'sampler.lua', 'runtime.lua', 'presentation.lua', 'controls.lua', 'keyboard.lua', 'keybindings.lua', 'navigation.lua', 'round_navigation.lua', 'replay_speed.lua', 'candidates.lua', 'match_review.lua', 'saved_capture.lua', 'analysis.lua', 'review_panel.lua', 'damage_rules.lua', 'damage_review.lua', 'review_model.lua', 'review_window.lua', 'review_assessments.lua', 'statistics.lua', 'statistics_charts.lua', 'CFN_ReplayCapture.lua')
$files += @('guard_review.lua', 'guard_window.lua')
$files += 'statistics_popups.lua'
$files += @('rule_config.lua','rule_context.lua')
$files += 'workbench.lua'
$files += 'rule_evaluation.lua'
$editorFiles = @('index.html','editor.css','catalog.js','model.js','editor.js','game-files.js','timeline-model.js','timeline.js')
foreach ($name in $editorFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot ('rule_editor/'+$name)) -PathType Leaf)) {
        throw "Missing rule editor asset: $name"
    }
}
$uiSource = Join-Path $PSScriptRoot '../../autorun/func/UIKit.lua'
if (-not (Test-Path -LiteralPath $uiSource -PathType Leaf)) { throw 'Shared SF6CC UI utility is missing.' }
foreach ($name in $files) {
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $name) -PathType Leaf)) { throw "Missing dependency: $name" }
}
if (-not (Test-Path -LiteralPath (Join-Path $target 'plugins\REFramework.NET.dll'))) { throw 'REFramework.NET is required for keyboard input.' }
$helper = Join-Path $PSScriptRoot 'CFNKeyboardBridge.cs'
if (-not (Test-Path -LiteralPath $helper -PathType Leaf)) { throw 'Keyboard helper source is missing.' }
$fontSource = Join-Path $PSScriptRoot '..\..\fonts\msyh.ttc'
if (-not (Test-Path -LiteralPath $fontSource -PathType Leaf)) { throw 'Review font is missing.' }
if ($PSCmdlet.ShouldProcess($target, "Install isolated CFN capture experiment ($($files.Count + 1) Lua files and keyboard source helper)")) {
    $editorDir=Join-Path $target 'CFNRuleEditor'
    New-Item -ItemType Directory -Force -Path $editorDir | Out-Null
    foreach($name in $editorFiles) {
        $source=Join-Path $PSScriptRoot ('rule_editor/'+$name)
        $dest=Join-Path $editorDir $name
        Copy-Item -LiteralPath $source -Destination $dest -Force
        if((Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath $dest).Hash){throw 'Rule editor copy verification failed.'}
    }
    New-Item -ItemType Directory -Force -Path $modules | Out-Null
    foreach ($name in $files) {
        $destination = if ($name -eq 'CFN_ReplayCapture.lua') { Join-Path $autorun $name } else { Join-Path $modules $name }
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $destination -Force
        if ((Get-FileHash -LiteralPath $destination).Hash -ne (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name)).Hash) {
            throw "Copy verification failed: $name"
        }
        Write-Output $destination
    }
    $uiDestination = Join-Path $autorun 'func/UIKit.lua'
    Copy-Item -LiteralPath $uiSource -Destination $uiDestination -Force
    if ((Get-FileHash -LiteralPath $uiSource).Hash -ne (Get-FileHash -LiteralPath $uiDestination).Hash) { throw 'Shared UI verification failed.' }
    $helperDir = Join-Path $target 'plugins\source'
    New-Item -ItemType Directory -Force -Path $helperDir | Out-Null
    Copy-Item -LiteralPath $helper -Destination (Join-Path $helperDir 'CFNKeyboardBridge.cs') -Force
    if ((Get-FileHash -LiteralPath $helper).Hash -ne (Get-FileHash -LiteralPath (Join-Path $helperDir 'CFNKeyboardBridge.cs')).Hash) {
        throw 'Keyboard helper verification failed.'
    }
    $fontDir = Join-Path $target 'fonts'
    New-Item -ItemType Directory -Force -Path $fontDir | Out-Null
    Copy-Item -LiteralPath $fontSource -Destination (Join-Path $fontDir 'msyh.ttc') -Force
    if ((Get-FileHash -LiteralPath $fontSource).Hash -ne (Get-FileHash -LiteralPath (Join-Path $fontDir 'msyh.ttc')).Hash) {
        throw 'Review font verification failed.'
    }
}
