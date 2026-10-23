param(
    [switch]$SkipBuild,
    [switch]$SkipSeed,
    [switch]$ConfigureMEmu,
    [switch]$AuthHttpDiagnosticsProxy,
    [string]$Device = '127.0.0.1:21503'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$appRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'local-demo-runtime.ps1')
$runtime = Get-SearchLocalRuntime -AppRoot $appRoot
Set-SearchLocalRuntimeEnvironment -Runtime $runtime
$configPath = Join-Path $appRoot 'firebase.search-emulator.json'
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
if ($config.emulators.auth.host -ne '127.0.0.1' -or $config.emulators.auth.port -ne 9097 -or
    $config.emulators.firestore.host -ne '127.0.0.1' -or $config.emulators.firestore.port -ne 8087 -or
    $config.emulators.functions.host -ne '127.0.0.1' -or $config.emulators.functions.port -ne 5007) {
    throw 'Firebase Emulator config must match demo loopback endpoints 127.0.0.1:9097/8087/5007.'
}

$requiredPorts = @($config.emulators.auth.port, $config.emulators.firestore.port,
    $config.emulators.functions.port, $config.emulators.eventarc.port,
    $config.emulators.hub.port, $config.emulators.logging.port, 9150, 9499)
if ($AuthHttpDiagnosticsProxy) { $requiredPorts += 9197 }
$occupied = foreach ($port in $requiredPorts | Select-Object -Unique) {
    $listeners = Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue
    if ($listeners) {
        [pscustomobject]@{ Port = $port; ProcessIds = (($listeners.OwningProcess | Sort-Object -Unique) -join ',') }
    }
}
if ($occupied) {
    $summary = ($occupied | ForEach-Object { "$($_.Port) (PID $($_.ProcessIds))" }) -join ', '
    throw "Required local ports are already in use: $summary. No existing process was contacted or stopped."
}

if ($ConfigureMEmu) {
    $deviceState = (& $runtime.Adb -s $Device get-state 2>$null | Select-Object -First 1)
    if ($LASTEXITCODE -ne 0 -or $deviceState -ne 'device') {
        throw 'MEmu is not already connected. Start it manually before using -ConfigureMEmu.'
    }
}

$apk = Join-Path $appRoot 'build/app/outputs/flutter-apk/app-searchlocal-debug.apk'
if (!$SkipBuild) {
    Push-Location $appRoot
    try {
        $buildArguments = @(
            'build', 'apk', '--debug', '--flavor', 'searchLocal', '--no-pub',
            '--dart-define=LOCAL_SEARCH_EMULATORS=true',
            '--dart-define=LOCAL_SEARCH_PROJECT=demo-universal-search',
            '--dart-define=LOCAL_SEARCH_HOST=127.0.0.1'
        )
        if ($AuthHttpDiagnosticsProxy) {
            $buildArguments += '--dart-define=LOCAL_AUTH_HTTP_DIAGNOSTICS=true'
        }
        & $runtime.Flutter @buildArguments
        if ($LASTEXITCODE -ne 0) { throw 'searchLocal debug APK build failed.' }
    } finally { Pop-Location }
}
if (!(Test-Path -LiteralPath $apk)) { throw 'searchLocal debug APK is missing; build it first.' }
& (Join-Path $PSScriptRoot 'test-search-local-apk.ps1') -Apk $apk
if ($LASTEXITCODE -ne 0) { throw 'searchLocal APK isolation verification failed.' }

$dataDir = Join-Path $env:LOCALAPPDATA 'TudoAquiMacacu/searchLocal-memu-data-current'
$importExisting = $false
if (Test-Path -LiteralPath $dataDir) {
    $item = Get-Item -LiteralPath $dataDir -Force
    if (!$item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Persistent Emulator path must be a normal directory, not a file or symbolic link.'
    }
    $manifestPath = Join-Path $dataDir 'firebase-export-metadata.json'
    if (Test-Path -LiteralPath $manifestPath) {
        try { $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json }
        catch { throw 'Persistent Emulator export metadata is invalid; existing data was left untouched.' }
        if (!$manifest.version -or $manifest.auth.path -ne 'auth_export' -or
            $manifest.firestore.path -ne 'firestore_export' -or
            !(Test-Path (Join-Path $dataDir $manifest.auth.path)) -or
            !(Test-Path (Join-Path $dataDir $manifest.firestore.path))) {
            throw 'Persistent Emulator export is incomplete; existing data was left untouched.'
        }
        $importExisting = $true
    } elseif (Get-ChildItem -LiteralPath $dataDir -Force | Select-Object -First 1) {
        throw 'Persistent Emulator directory contains unrecognized data; nothing was overwritten.'
    }
} else {
    $parent = Split-Path $dataDir -Parent
    if (!(Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
}

$cliArguments = @('emulators:start', '--only', 'auth,firestore,functions',
    '--config', $configPath, '--project', 'demo-universal-search',
    "--export-on-exit=$dataDir", '--non-interactive')
if ($importExisting) { $cliArguments += "--import=$dataDir" }
$argumentLine = ($cliArguments | ForEach-Object {
    '"' + ([string]$_).Replace('"', '\"') + '"'
}) -join ' '

$previousProject = $env:GCLOUD_PROJECT
$previousGoogleProject = $env:GOOGLE_CLOUD_PROJECT
$previousFirebaseConfig = $env:FIREBASE_CONFIG
$previousFunctionsEmulator = $env:FUNCTIONS_EMULATOR
$previousAuthEmulator = $env:FIREBASE_AUTH_EMULATOR_HOST
$previousFirestoreEmulator = $env:FIRESTORE_EMULATOR_HOST
$previousFunctionsHost = $env:FUNCTIONS_EMULATOR_HOST
$previousFunctionsPort = $env:FUNCTIONS_EMULATOR_PORT
$previousCredentials = $env:GOOGLE_APPLICATION_CREDENTIALS
$previousFirebaseToken = $env:FIREBASE_TOKEN
$env:GCLOUD_PROJECT = 'demo-universal-search'
$env:GOOGLE_CLOUD_PROJECT = 'demo-universal-search'
$env:FIREBASE_CONFIG = '{"projectId":"demo-universal-search"}'
$env:FUNCTIONS_EMULATOR = 'true'
$env:FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9097'
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8087'
$env:FUNCTIONS_EMULATOR_HOST = '127.0.0.1:5007'
$env:FUNCTIONS_EMULATOR_PORT = '5007'
$env:GOOGLE_APPLICATION_CREDENTIALS = $null
$env:FIREBASE_TOKEN = $null
try {
    $server = Start-Process -FilePath $runtime.Firebase -ArgumentList $argumentLine `
        -WorkingDirectory $appRoot -PassThru -WindowStyle Normal
    Write-Host "Firebase Emulator started in its own console (PID $($server.Id)); close that console with Ctrl+C to save Auth/Firestore data."
    $deadline = (Get-Date).AddSeconds(120)
    $ready = $false
    while ((Get-Date) -lt $deadline) {
        if ($server.HasExited) { throw 'Firebase CLI exited before the Emulators became ready. Check its console; no process was terminated by this script.' }
        try {
            $hub = Invoke-RestMethod -Uri "http://127.0.0.1:$($config.emulators.hub.port)/emulators" -TimeoutSec 2
            $ready = $hub.auth.host -eq '127.0.0.1' -and $hub.auth.port -eq 9097 -and
                $hub.firestore.host -eq '127.0.0.1' -and $hub.firestore.port -eq 8087 -and
                $hub.functions.host -eq '127.0.0.1' -and $hub.functions.port -eq 5007
            if ($ready) { break }
        } catch { }
        Start-Sleep -Milliseconds 750
    }
    if (!$ready) { throw 'Loopback Emulator readiness was not confirmed within two minutes. Inspect the Emulator console.' }
    Write-Host 'Confirmed demo-universal-search; Auth, Firestore, and Functions are bound to 127.0.0.1.'

    if (!$SkipSeed) {
        $env:FUNCTIONS_EMULATOR = 'true'
        $env:FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9097'
        $env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8087'
        $env:FUNCTIONS_EMULATOR_HOST = '127.0.0.1:5007'
        $env:FUNCTIONS_EMULATOR_PORT = '5007'
        $env:LOCAL_DEMO_CONFIRM = 'demo-universal-search'
        Push-Location (Join-Path $appRoot 'functions')
        try {
            & $runtime.Node integration/seed_search_local_demo.js
            if ($LASTEXITCODE -ne 0) { throw 'Create-only demo fixture seeding did not complete.' }
        } finally { Pop-Location }
    }

    if ($ConfigureMEmu) {
        $reversePorts = @(9097, 8087, 5007)
        if ($AuthHttpDiagnosticsProxy) { $reversePorts += 9197 }
        foreach ($port in $reversePorts) {
            & $runtime.Adb -s $Device reverse "tcp:$port" "tcp:$port" | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'ADB loopback forwarding failed; the app was not installed or started.' }
        }
        Write-Host 'ADB reverse configured for the already-running MEmu; no app was installed or launched.'
    }
} finally {
    $env:GCLOUD_PROJECT = $previousProject
    $env:GOOGLE_CLOUD_PROJECT = $previousGoogleProject
    $env:FIREBASE_CONFIG = $previousFirebaseConfig
    $env:FUNCTIONS_EMULATOR = $previousFunctionsEmulator
    $env:FIREBASE_AUTH_EMULATOR_HOST = $previousAuthEmulator
    $env:FIRESTORE_EMULATOR_HOST = $previousFirestoreEmulator
    $env:FUNCTIONS_EMULATOR_HOST = $previousFunctionsHost
    $env:FUNCTIONS_EMULATOR_PORT = $previousFunctionsPort
    $env:GOOGLE_APPLICATION_CREDENTIALS = $previousCredentials
    $env:FIREBASE_TOKEN = $previousFirebaseToken
}

Write-Host "APK: $apk"
Write-Host 'To configure an already-running MEmu: rerun this script with -SkipBuild -ConfigureMEmu.'
if ($AuthHttpDiagnosticsProxy) {
    Write-Host 'Auth HTTP diagnostics are opt-in; start tools/start-auth-emulator-diagnostic-proxy.ps1 before the app launcher.'
}
Write-Host 'To install and launch the isolated app later, use tools/start-search-local.ps1 after starting MEmu manually.'
