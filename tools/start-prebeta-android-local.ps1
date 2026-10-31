param(
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
$apk = Join-Path $appRoot 'build/app/outputs/flutter-apk/app-prebetalocal-debug.apk'
$package = 'br.com.tudoaquimacacu.tudo_aqui_macacu.prebeta'
$expectedAvd = 'tudo_aqui_macacu_e2e'
$ports = @(9097, 8087, 5007)

if (!(Test-Path -LiteralPath $adb)) { throw 'Android Debug Bridge is not available in the existing SDK.' }
$configPath = Join-Path $appRoot 'firebase.search-emulator.json'
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
if ($config.emulators.auth.host -ne '127.0.0.1' -or $config.emulators.auth.port -ne 9097 -or
    $config.emulators.firestore.host -ne '127.0.0.1' -or $config.emulators.firestore.port -ne 8087 -or
    $config.emulators.functions.host -ne '127.0.0.1' -or $config.emulators.functions.port -ne 5007) {
    throw 'Only the demo loopback Emulator endpoints 127.0.0.1:9097/8087/5007 are accepted.'
}

$deviceState = (& $adb -s $Device get-state 2>$null | Select-Object -First 1)
if ($LASTEXITCODE -ne 0 -or $deviceState -ne 'device' -or $Device -notmatch '^emulator-\d+$') {
    throw 'Select the dedicated running AVD by its emulator serial. Physical devices and MEmu are refused.'
}
$avdName = ((& $adb -s $Device emu avd name 2>$null) | Select-Object -First 1).Trim()
if ($LASTEXITCODE -ne 0 -or $avdName -ne $expectedAvd) {
    throw "Only the dedicated AVD '$expectedAvd' is accepted."
}
if ((& $adb -s $Device shell getprop ro.kernel.qemu).Trim() -ne '1') {
    throw 'The selected Android target is not an Android Virtual Device.'
}

function Test-FirebaseEmulatorOwner([int]$ProcessId) {
    $seen = @{}
    while ($ProcessId -gt 0 -and !$seen.ContainsKey($ProcessId)) {
        $seen[$ProcessId] = $true
        $process = Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction SilentlyContinue
        if (!$process) { return $false }
        if ($process.Name -eq 'firebase-tools.exe' -and
            $process.CommandLine -match '(?is)emulators:start' -and
            $process.CommandLine -match '--project demo-universal-search') {
            $configMatch = [regex]::Match($process.CommandLine, '(?is)--config\s+(?:"([^"]+\.json)"|(.+?\.json))\s+--project')
            if (!$configMatch.Success) { return $false }
            $configFile = if ($configMatch.Groups[1].Success) {
                $configMatch.Groups[1].Value
            } else { $configMatch.Groups[2].Value.Trim() }
            if (!(Test-Path -LiteralPath $configFile)) { return $false }
            $configRoot = Split-Path $configFile -Parent
            try { $emulatorConfig = Get-Content -LiteralPath $configFile -Raw | ConvertFrom-Json }
            catch { return $false }
            if ($emulatorConfig.emulators.auth.host -ne '127.0.0.1' -or
                $emulatorConfig.emulators.auth.port -ne 9097 -or
                $emulatorConfig.emulators.firestore.host -ne '127.0.0.1' -or
                $emulatorConfig.emulators.firestore.port -ne 8087 -or
                $emulatorConfig.emulators.functions.host -ne '127.0.0.1' -or
                $emulatorConfig.emulators.functions.port -ne 5007 -or
                $emulatorConfig.functions.source -ne 'functions') { return $false }
            $source = Join-Path $configRoot 'functions'
            $dotenv = Join-Path $source '.env.local'
            $secretLocal = Join-Path $source '.secret.local'
            if (!(Test-Path -LiteralPath $dotenv) -or !(Test-Path -LiteralPath $secretLocal)) { return $false }
            $dotenvValues = Get-Content -LiteralPath $dotenv
            $secretValues = Get-Content -LiteralPath $secretLocal
            if ($dotenvValues -notcontains 'CLOUDINARY_CLOUD_NAME=local-prebeta-disabled' -or
                $dotenvValues -notcontains 'CLOUDINARY_API_KEY=LOCAL_SYNTHETIC_NOT_A_KEY' -or
                $secretValues -notcontains 'CLOUDINARY_API_SECRET=LOCAL_SYNTHETIC_NOT_A_SECRET') { return $false }
            if ($source.StartsWith($PSScriptRoot, [StringComparison]::OrdinalIgnoreCase) -or
                $source -notlike (Join-Path $env:LOCALAPPDATA 'Temp\MacacuPreBeta2-*\functions')) { return $false }
            return $true
        }
        $ProcessId = [int]$process.ParentProcessId
    }
    return $false
}

foreach ($port in $ports) {
    $listeners = @(Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue)
    if (!$listeners -or ($listeners | Where-Object { $_.LocalAddress -ne '127.0.0.1' })) {
        throw "Required Firebase Emulator port $port is absent or not bound exclusively to loopback."
    }
    foreach ($listener in $listeners) {
        if (!(Test-FirebaseEmulatorOwner -ProcessId ([int]$listener.OwningProcess))) {
            throw "Port $port is not owned by the explicitly configured demo Firebase Emulator."
        }
    }
}

if (!$SkipBuild) {
    Push-Location $appRoot
    try {
        & $flutter build apk --debug --flavor preBetaLocal --no-pub `
            --dart-define=LOCAL_SEARCH_EMULATORS=true `
            --dart-define=LOCAL_SEARCH_PROJECT=demo-universal-search `
            --dart-define=LOCAL_SEARCH_HOST=127.0.0.1
        if ($LASTEXITCODE -ne 0) { throw 'Pre-Beta local debug APK build failed.' }
    } finally { Pop-Location }
}
if (!(Test-Path -LiteralPath $apk)) { throw 'Pre-Beta local debug APK is missing.' }
& (Join-Path $PSScriptRoot 'test-prebeta-local-apk.ps1') -Apk $apk
if ($LASTEXITCODE -ne 0) { throw 'Pre-Beta APK isolation verification failed.' }

foreach ($port in $ports) {
    & $adb -s $Device reverse "tcp:$port" "tcp:$port" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Loopback forwarding failed; the app was not launched.' }
}
& $adb -s $Device install --no-streaming -r -d $apk
if ($LASTEXITCODE -ne 0) { throw 'Pre-Beta local app install failed.' }
& $adb -s $Device shell appops set $package ACTIVATE_VPN allow
if ($LASTEXITCODE -ne 0) { throw 'The dedicated AVD did not accept local VPN permission.' }
& $adb -s $Device shell am start -a android.intent.action.MAIN -n "$package/br.com.tudoaquimacacu.tudo_aqui_macacu.SearchLocalGateActivity"
if ($LASTEXITCODE -ne 0) { throw 'The fail-closed local VPN gate did not start.' }

$deadline = [DateTime]::UtcNow.AddSeconds(40)
$ready = $false
while ([DateTime]::UtcNow -lt $deadline) {
    $activity = (& $adb -s $Device shell dumpsys activity activities 2>$null) -join "`n"
    $log = (& $adb -s $Device logcat -d -s flutter:I 2>$null) -join "`n"
    $tun = ((& $adb -s $Device shell dumpsys connectivity 2>$null) -join "`n")
    if ($activity.Contains('.MainActivity') -and $log.Contains('LOCAL ISOLATION VALIDATED: demo-universal-search') -and
        $tun.Contains('InterfaceName: tun0')) { $ready = $true; break }
    Start-Sleep -Milliseconds 750
}
if (!$ready) { throw 'The AVD Gate did not prove VPN, demo project, local endpoints and Flutter startup within 40 seconds.' }
Write-Output "Pre-Beta local app launched on $expectedAvd ($Device); Auth/Firestore/Functions are demo-only loopback and VPN isolation is active."
