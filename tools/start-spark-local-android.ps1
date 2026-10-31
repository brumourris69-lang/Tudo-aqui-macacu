param(
    [Parameter(Mandatory = $true)][string]$EmulatorConfig,
    [string]$Device = 'emulator-5554',
    [switch]$SkipBuild
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$global:LASTEXITCODE = 0
$appRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sdk = Join-Path $env:LOCALAPPDATA 'Android/Sdk'
$adb = Join-Path $sdk 'platform-tools/adb.exe'
$flutter = (Get-Command flutter -ErrorAction Stop).Source
$package = 'br.com.tudoaquimacacu.tudo_aqui_macacu.sparklocal'
$expectedAvd = 'tudo_aqui_macacu_e2e'
$apk = Join-Path $appRoot 'build/app/outputs/flutter-apk/app-sparklocal-debug.apk'
$configPath = (Resolve-Path -LiteralPath $EmulatorConfig).Path
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$expectedRules = (Resolve-Path (Join-Path $appRoot 'firestore.beta.rules')).Path
if ($config.firestore.rules -ne $expectedRules -or
    ($config.PSObject.Properties.Name -contains 'functions' -and $config.functions) -or
    ($config.PSObject.Properties.Name -contains 'hosting' -and $config.hosting) -or
    $config.emulators.auth.host -ne '127.0.0.1' -or $config.emulators.auth.port -ne 9097 -or
    $config.emulators.firestore.host -ne '127.0.0.1' -or $config.emulators.firestore.port -ne 8087 -or
    ($config.emulators.PSObject.Properties.Name -contains 'functions' -and $config.emulators.functions)) {
    throw 'A configuração deve apontar somente Auth/Firestore de loopback e Rules Beta locais.'
}
if (!(Test-Path -LiteralPath $adb)) { throw 'Android Debug Bridge existente não encontrado.' }
$deviceState = (& $adb -s $Device get-state 2>$null | Select-Object -First 1)
if ($LASTEXITCODE -ne 0 -or $deviceState -ne 'device' -or $Device -notmatch '^emulator-\d+$') {
    throw 'Este runner aceita somente o AVD dedicado, nunca aparelho físico ou MEmu.'
}
$avdName = ((& $adb -s $Device emu avd name 2>$null) | Select-Object -First 1).Trim()
if ($LASTEXITCODE -ne 0 -or $avdName -ne $expectedAvd -or
    (& $adb -s $Device shell getprop ro.kernel.qemu).Trim() -ne '1') {
    throw "Somente o AVD '$expectedAvd' está autorizado para este teste local."
}
if ((& $adb -s $Device shell getprop sys.boot_completed).Trim() -ne '1') {
    throw 'O AVD ainda não terminou de iniciar.'
}
$existingPackage = (& $adb -s $Device shell pm list packages $package) -join "`n"
if ($existingPackage.Contains($package)) {
    throw 'O pacote Spark local já existe no AVD; instalação recusada para preservar seus dados.'
}

function Test-FirebaseEmulatorOwner([int]$ProcessId) {
    $seen = @{}
    while ($ProcessId -gt 0 -and !$seen.ContainsKey($ProcessId)) {
        $seen[$ProcessId] = $true
        $process = Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction SilentlyContinue
        if (!$process) { return $false }
        if ($process.Name -eq 'firebase-tools.exe' -and
            $process.CommandLine.Contains('emulators:start') -and
            $process.CommandLine.Contains('--only auth,firestore') -and
            $process.CommandLine.Contains('--project demo-universal-search') -and
            $process.CommandLine.Contains($configPath)) {
            return $true
        }
        $ProcessId = [int]$process.ParentProcessId
    }
    return $false
}
foreach ($port in @(9097, 8087)) {
    $listeners = @(Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue)
    if (!$listeners -or ($listeners | Where-Object { $_.LocalAddress -ne '127.0.0.1' })) {
        throw "Emulator $port ausente ou exposto além de loopback."
    }
    foreach ($listener in $listeners) {
        if (!(Test-FirebaseEmulatorOwner -ProcessId ([int]$listener.OwningProcess))) {
            throw "A porta $port não pertence aos Emulators Auth/Firestore deste projeto demo."
        }
    }
}

$reverseList = (& $adb -s $Device reverse --list) -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'Não foi possível inspecionar os encaminhamentos ADB.' }
$reverseMappings = @{}
foreach ($line in ($reverseList -split "`r?`n")) {
    $parts = @($line -split '\s+')
    if ($parts.Count -ge 3 -and $parts[-2] -match '^tcp:\d+$') {
        $reverseMappings[$parts[-2]] = $parts[-1]
    }
}
foreach ($port in @(9097, 8087)) {
    $deviceEndpoint = "tcp:$port"
    if ($reverseMappings.ContainsKey($deviceEndpoint) -and
        $reverseMappings[$deviceEndpoint] -ne $deviceEndpoint) {
        throw "ADB já tem um encaminhamento diferente em $port; nada será substituído."
    }
}
if (!$SkipBuild) {
    Push-Location $appRoot
    try {
        & $flutter build apk --debug --flavor sparkLocal --no-pub `
            --dart-define=SPARK_LOCAL_EMULATORS=true
        if ($LASTEXITCODE -ne 0) { throw 'Build APK Spark local falhou.' }
    } finally { Pop-Location }
}
& (Join-Path $PSScriptRoot 'test-spark-local-apk.ps1') -Apk $apk
if ($LASTEXITCODE -ne 0) { throw 'Verificação de isolamento do APK falhou.' }
foreach ($port in @(9097, 8087)) {
    $deviceEndpoint = "tcp:$port"
    if (!$reverseMappings.ContainsKey($deviceEndpoint)) {
        & $adb -s $Device reverse $deviceEndpoint $deviceEndpoint | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'ADB reverse falhou; o app não será iniciado.' }
    }
}
& $adb -s $Device install --no-streaming $apk
if ($LASTEXITCODE -ne 0) { throw 'Instalação do pacote Spark local falhou.' }
& $adb -s $Device shell appops set $package ACTIVATE_VPN allow
if ($LASTEXITCODE -ne 0) { throw 'O AVD recusou a VPN do pacote isolado.' }
& $adb -s $Device shell am start -a android.intent.action.MAIN `
    -n "$package/br.com.tudoaquimacacu.tudo_aqui_macacu.SearchLocalGateActivity"
if ($LASTEXITCODE -ne 0) { throw 'O Gate VPN isolado não iniciou.' }

$deadline = [DateTime]::UtcNow.AddSeconds(50)
$ready = $false
while ([DateTime]::UtcNow -lt $deadline) {
    $activity = (& $adb -s $Device shell dumpsys activity activities 2>$null) -join "`n"
    $log = (& $adb -s $Device logcat -d -s flutter:I 2>$null) -join "`n"
    $connectivity = (& $adb -s $Device shell dumpsys connectivity 2>$null) -join "`n"
    if ($activity.Contains('.MainActivity') -and
        $log.Contains('SPARK LOCAL ISOLATION VALIDATED: demo-universal-search') -and
        $connectivity.Contains('InterfaceName: tun0')) {
        $ready = $true
        break
    }
    Start-Sleep -Milliseconds 750
}
if (!$ready) { throw 'VPN, appFlavor Spark local e conexão com demo não foram comprovados no AVD.' }
Write-Output "Spark local started on $expectedAvd ($Device). Only Auth/Firestore loopback are forwarded; Functions, Storage and hosted Firebase are blocked."
