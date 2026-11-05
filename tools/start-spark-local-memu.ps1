[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$script:adbPath = Join-Path $env:LOCALAPPDATA 'Android/Sdk/platform-tools/adb.exe'
$script:device = '127.0.0.1:21503'
$script:package = 'br.com.tudoaquimacacu.tudo_aqui_macacu.sparklocal'
$script:activity = 'br.com.tudoaquimacacu.tudo_aqui_macacu.SearchLocalGateActivity'
$script:preflightPath = Join-Path $PSScriptRoot 'prepare-spark-local-memu.ps1'
$script:preflightMarker = 'SparkLocal MEmu preflight aprovado.'

function Invoke-SparkLocalMEmuStart {
    [CmdletBinding()]
    param(
        [scriptblock]$RunPreflight = { & $script:preflightPath },
        [scriptblock]$LaunchGate = {
            & $script:adbPath -s $script:device shell am start `
                -a android.intent.action.MAIN `
                -n "$script:package/$script:activity"
            if ($LASTEXITCODE -ne 0) {
                throw 'O ADB não conseguiu abrir o Gate SparkLocal no MEmu verificado.'
            }
        }
    )

    $preflightOutput = @(& $RunPreflight 2>&1)
    $preflightPassed = @($preflightOutput | Where-Object {
        ([string]$_).Trim() -eq $script:preflightMarker
    }).Count -gt 0

    if (!$preflightPassed) {
        throw 'Pré-verificação SparkLocal não aprovada; o Gate não foi aberto.'
    }

    # Preserve the preflight's useful status messages for the one-command flow.
    $preflightOutput | ForEach-Object { Write-Host $_ }
    & $LaunchGate
    Write-Output 'Gate SparkLocal aberto no MEmu após o preflight aprovado.'
}

# Dot-sourcing exposes the guarded launcher to its local unit test without
# starting the app. Direct execution is the user's single-command entrypoint.
if ($MyInvocation.InvocationName -ne '.') {
    try {
        Invoke-SparkLocalMEmuStart
    } catch {
        [Console]::Error.WriteLine("SparkLocal não foi iniciado: $($_.Exception.Message)")
        exit 1
    }
}
