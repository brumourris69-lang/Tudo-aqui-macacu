$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'start-spark-local-memu.ps1')

function Assert-Equal {
    param([object]$Expected, [object]$Actual, [string]$Message)
    if ($Expected -ne $Actual) {
        throw "$Message Expected '$Expected'; got '$Actual'."
    }
}

$state = [pscustomobject]@{ Launches = 0 }
$passedPreflight = { 'SparkLocal MEmu preflight aprovado.' }
$countingLaunch = { $state.Launches++ }
Invoke-SparkLocalMEmuStart -RunPreflight $passedPreflight -LaunchGate $countingLaunch | Out-Null
Assert-Equal 1 $state.Launches 'The Gate should start exactly once after a successful preflight.'
Write-Output 'PASS: the Gate starts once after the existing preflight approval marker.'

$state.Launches = 0
$failingPreflight = { throw 'VPN unavailable' }
try {
    Invoke-SparkLocalMEmuStart -RunPreflight $failingPreflight -LaunchGate $countingLaunch | Out-Null
    throw 'Expected a failed preflight to block the Gate.'
} catch {
    if ($_.Exception.Message -notmatch 'VPN unavailable') { throw }
}
Assert-Equal 0 $state.Launches 'The Gate must not start if a required preflight check throws.'
Write-Output 'PASS: VPN/Emulator/preflight failures block the Gate.'

$missingApproval = { 'Preflight output without the approval marker.' }
try {
    Invoke-SparkLocalMEmuStart -RunPreflight $missingApproval -LaunchGate $countingLaunch | Out-Null
    throw 'Expected missing approval evidence to block the Gate.'
} catch {
    if ($_.Exception.Message -notmatch 'Pré-verificação SparkLocal não aprovada') { throw }
}
Assert-Equal 0 $state.Launches 'The Gate must not start without the explicit preflight marker.'
Write-Output 'PASS: missing/ambiguous preflight evidence blocks the Gate.'

$sequence = [System.Collections.Generic.List[string]]::new()
$installFlow = @{
    BuildAndVerifyApk = { $sequence.Add('build') }.GetNewClosure()
    RunInstallPreflight = { $sequence.Add('install-preflight'); 'SparkLocal MEmu installation preflight aprovado.' }.GetNewClosure()
    InstallApk = { $sequence.Add('install') }.GetNewClosure()
    RunBootstrapPreflight = { $sequence.Add('bootstrap-preflight'); 'SparkLocal MEmu bootstrap aprovado; somente Auth/Firestore locais encaminhados.' }.GetNewClosure()
    StartBootstrapGate = { $sequence.Add('bootstrap-gate') }.GetNewClosure()
    WaitForVpnApproval = { $sequence.Add('vpn-approval') }.GetNewClosure()
    RunFinalStart = { $sequence.Add('full-preflight-and-start') }.GetNewClosure()
}
Invoke-SparkLocalMEmuBuildInstallAndStart @installFlow | Out-Null
Assert-Equal 'build,install-preflight,install,bootstrap-preflight,bootstrap-gate,vpn-approval,full-preflight-and-start' `
    ($sequence -join ',') 'Build/install must be followed by both preflights and explicit VPN approval.'
Write-Output 'PASS: build/install flow preserves install, VPN bootstrap and final full-preflight order.'

$sequence.Clear()
$blockedInstall = @{
    BuildAndVerifyApk = { $sequence.Add('build') }.GetNewClosure()
    RunInstallPreflight = { $sequence.Add('install-preflight'); 'preflight recusado' }.GetNewClosure()
    InstallApk = { $sequence.Add('install') }.GetNewClosure()
}
try {
    Invoke-SparkLocalMEmuBuildInstallAndStart @blockedInstall | Out-Null
    throw 'Expected an unapproved install preflight to block installation.'
} catch {
    if ($_.Exception.Message -notmatch 'Pré-verificação de instalação não aprovada') { throw }
}
Assert-Equal 'build,install-preflight' ($sequence -join ',') 'APK installation must not occur without host preflight approval.'
Write-Output 'PASS: failed install preflight blocks APK installation.'

$sequence.Clear()
$blockedBootstrap = @{
    BuildAndVerifyApk = { $sequence.Add('build') }.GetNewClosure()
    RunInstallPreflight = { $sequence.Add('install-preflight'); 'SparkLocal MEmu installation preflight aprovado.' }.GetNewClosure()
    InstallApk = { $sequence.Add('install') }.GetNewClosure()
    RunBootstrapPreflight = { $sequence.Add('bootstrap-preflight'); 'bootstrap recusado' }.GetNewClosure()
    StartBootstrapGate = { $sequence.Add('bootstrap-gate') }.GetNewClosure()
}
try {
    Invoke-SparkLocalMEmuBuildInstallAndStart @blockedBootstrap | Out-Null
    throw 'Expected a failed bootstrap preflight to block app launch.'
} catch {
    if ($_.Exception.Message -notmatch 'Pré-verificação do Gate VPN não aprovada') { throw }
}
Assert-Equal 'build,install-preflight,install,bootstrap-preflight' ($sequence -join ',') `
    'The Gate must not start without approved loopback forwarding preparation.'
Write-Output 'PASS: failed bootstrap preflight blocks the Gate.'
