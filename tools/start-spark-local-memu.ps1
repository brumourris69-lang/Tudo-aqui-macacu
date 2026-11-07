[CmdletBinding()]
param([switch]$BuildAndInstall)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'resolve-android-adb.ps1')
$script:adbPath = Resolve-AndroidAdbPath
$script:adbPath = (Resolve-Path -LiteralPath $script:adbPath).Path
$script:device = '127.0.0.1:21503'
$script:package = 'br.com.tudoaquimacacu.tudo_aqui_macacu.sparklocal'
$script:activity = 'br.com.tudoaquimacacu.tudo_aqui_macacu.SearchLocalGateActivity'
$script:preflightPath = Join-Path $PSScriptRoot 'prepare-spark-local-memu.ps1'
$script:appRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$script:memucPath = 'C:\Program Files\Microvirt\MEmu\memuc.exe'
$script:apkPath = Join-Path $script:appRoot 'build/app/outputs/flutter-apk/app-sparklocal-debug.apk'
$script:installPreflightMarker = 'SparkLocal MEmu installation preflight aprovado.'
$script:bootstrapMarker = 'SparkLocal MEmu bootstrap aprovado; somente Auth/Firestore locais encaminhados.'
$script:preflightMarker = 'SparkLocal MEmu preflight aprovado.'
Write-Host "ADB selecionado em Platform-Tools: $script:adbPath"

function Invoke-SparkLocalMEmuBuildAndVerifyApk {
    $flutter = (Get-Command flutter -ErrorAction Stop).Source
    Push-Location $script:appRoot
    try {
        & $flutter build apk --debug --flavor sparkLocal --no-pub `
            --dart-define=SPARK_LOCAL_EMULATORS=true
        if ($LASTEXITCODE -ne 0) { throw 'Build APK SparkLocal falhou.' }
    } finally { Pop-Location }

    & (Join-Path $PSScriptRoot 'test-spark-local-apk.ps1') -Apk $script:apkPath
    if ($LASTEXITCODE -ne 0) { throw 'A verificação de isolamento do APK SparkLocal falhou.' }
    Write-Output "APK SparkLocal validado: $script:apkPath"
}

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

function Invoke-SparkLocalMEmuBuildInstallAndStart {
    [CmdletBinding()]
    param(
        [scriptblock]$BuildAndVerifyApk = { Invoke-SparkLocalMEmuBuildAndVerifyApk },
        [scriptblock]$RunInstallPreflight = { & $script:preflightPath -InstallOnly },
        [scriptblock]$InstallApk = {
            & $script:memucPath installapp -i 0 $script:apkPath
            if ($LASTEXITCODE -ne 0) { throw 'A instalação do APK no MEmu falhou; nenhum dado foi removido.' }
        },
        [scriptblock]$RunBootstrapPreflight = { & $script:preflightPath -Bootstrap },
        [scriptblock]$StartBootstrapGate = {
            & $script:memucPath startapp -i 0 "$script:package/$script:activity"
            if ($LASTEXITCODE -ne 0) { throw 'O Gate inicial do SparkLocal não foi aberto no MEmu índice 0.' }
        },
        [scriptblock]$WaitForVpnApproval = {
            [void](Read-Host 'No MEmu, aprove a solicitação de conexão VPN do SparkLocal. Depois pressione Enter')
        },
        [scriptblock]$RunFinalStart = { Invoke-SparkLocalMEmuStart }
    )

    & $BuildAndVerifyApk

    $installOutput = @(& $RunInstallPreflight 2>&1)
    if (!(@($installOutput | Where-Object { ([string]$_).Trim() -eq $script:installPreflightMarker }).Count)) {
        throw 'Pré-verificação de instalação não aprovada; o APK não será instalado.'
    }
    $installOutput | ForEach-Object { Write-Host $_ }

    & $InstallApk

    $bootstrapOutput = @(& $RunBootstrapPreflight 2>&1)
    if (!(@($bootstrapOutput | Where-Object { ([string]$_).Trim() -eq $script:bootstrapMarker }).Count)) {
        throw 'Pré-verificação do Gate VPN não aprovada; o aplicativo não será aberto.'
    }
    $bootstrapOutput | ForEach-Object { Write-Host $_ }

    & $StartBootstrapGate
    & $WaitForVpnApproval

    # The regular full preflight remains authoritative for VPN, UID, emulator
    # endpoints and the final app launch. No check is skipped after install.
    & $RunFinalStart
    Write-Output 'APK SparkLocal instalado e Gate aprovado no MEmu índice 0.'
}

# Dot-sourcing exposes the guarded launcher to its local unit test without
# starting the app. Direct execution is the user's single-command entrypoint.
if ($MyInvocation.InvocationName -ne '.') {
    try {
        if ($BuildAndInstall) {
            Invoke-SparkLocalMEmuBuildInstallAndStart
        } else {
            Invoke-SparkLocalMEmuStart
        }
    } catch {
        [Console]::Error.WriteLine("SparkLocal não foi iniciado: $($_.Exception.Message)")
        exit 1
    }
}
