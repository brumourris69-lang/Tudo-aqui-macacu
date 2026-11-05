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
