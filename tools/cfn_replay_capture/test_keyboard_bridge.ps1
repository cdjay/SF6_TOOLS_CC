[CmdletBinding()]
param([string]$FrameworkDll = 'D:\Program Files (x86)\Steam\steamapps\common\Street Fighter 6\reframework\plugins\REFramework.NET.dll')
$ErrorActionPreference = 'Stop'
# Compile against installed API without starting the worker or calling user32.
$refs = @((Get-ChildItem -LiteralPath (Join-Path $PSHOME 'ref') -Filter '*.dll').FullName) + @($FrameworkDll)
Add-Type -Path @((Join-Path $PSScriptRoot 'CFNKeyboardBridge.cs'), (Join-Path $PSScriptRoot '../test_cfn_keyboard_bridge_recovery.cs')) -ReferencedAssemblies $refs
if ([Runtime.InteropServices.Marshal]::SizeOf([type][CFNKeyboardBridge+Input]) -ne 40) { throw 'INPUT ABI mismatch' }
$cases = @(
    @('ready', 't', 't', '1', '0', 67, 10, $true, $false, $false),
    @('stale', 'old', 't', '1', '0', 67, 10, $true, $false, $false),
    @('stale', 't', 't', '1', '1', 67, 10, $true, $false, $false),
    @('stale', 't', 't', '', '0', 67, 10, $true, $false, $false),
    @('expired', 't', 't', '1', '0', 67, 501, $true, $false, $false),
    @('expired', 't', 't', '1', '0', 67, -1, $true, $false, $false),
    @('key_unavailable', 't', 't', '1', '0', 1, 10, $true, $false, $false),
    @('focus_lost', 't', 't', '1', '0', 67, 10, $false, $false, $false),
    @('close_overlay', 't', 't', '1', '0', 67, 10, $true, $true, $false),
    @('key_held', 't', 't', '1', '0', 67, 10, $true, $false, $true)
)
foreach ($c in $cases) {
    $result = [CFNKeyboardBridge]::Validate($c[1], $c[2], $c[3], $c[4], $c[5], $c[6], $c[7], $c[8], $c[9])
    if ($result -ne $c[0]) { throw "Validation mismatch: $result != $($c[0])" }
}
foreach ($key in @(1, 16, 17, 18, 58, 64, 91, 136)) {
    if ([CFNKeyboardBridge]::AllowedKey($key)) { throw "Unexpected allowed key: $key" }
}
Write-Output 'PASS C# compilation, INPUT ABI, 10 validation cases and key allowlist (no keys sent)'
$pressCases = @(
    @('{}', 45), @('{"press_ms":45}', 45), @('{"press_ms":30}', 30),
    @('{"press_ms":20}', 20), @('{"press_ms":12}', 12),
    @('{"press_ms":0}', -1), @('{"press_ms":-1}', -1), @('{"press_ms":13}', -1),
    @('{"press_ms":20.5}', -1), @('{"press_ms":"20"}', -1),
    @('{"press_ms":null}', -1), @('{"press_ms":true}', -1), @('{"press_ms":2147483648}', -1)
)
foreach ($c in $pressCases) {
    $doc = [System.Text.Json.JsonDocument]::Parse([string]$c[0])
    try {
        $actual = [CFNKeyboardBridge]::ReadPressMilliseconds($doc.RootElement)
        if ($actual -ne $c[1]) { throw "Press duration mismatch: $actual != $($c[1])" }
    } finally { $doc.Dispose() }
}
Write-Output 'PASS 13 bounded-duration parsing cases (worker not started; no keys sent)'
[CFNBridgeRecoveryTest]::Run()
Write-Output 'PASS transient file-access recovery and fatal error boundary (no keys sent)'
