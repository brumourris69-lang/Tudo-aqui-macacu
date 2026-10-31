$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$appRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$functionsRoot = Join-Path $appRoot 'functions'
. (Join-Path $PSScriptRoot 'local-demo-runtime.ps1')
$runtime = Get-SearchLocalRuntime -AppRoot $appRoot
$configPath = Join-Path $appRoot 'firebase.search-emulator.json'
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json

$expected = @{
    auth = 9097
    firestore = 8087
    functions = 5007
    eventarc = 9297
    hub = 4407
    logging = 4507
}
foreach ($name in $expected.Keys) {
    if ($config.emulators.$name.host -ne '127.0.0.1' -or
        [int]$config.emulators.$name.port -ne $expected[$name]) {
        throw "Firebase Emulator $name differs from its isolated demo loopback endpoint."
    }
}
if ($config.firestore.rules -ne 'firestore.rules' -or
    $config.functions.source -ne 'functions' -or
    $config.emulators.ui.enabled -ne $false -or
    $config.emulators.singleProjectMode -ne $true) {
    throw 'Firebase demo emulator configuration failed its isolation check.'
}

$ports = @($expected.Values) + @(9150, 9499)
$occupied = foreach ($port in ($ports | Sort-Object -Unique)) {
    $listener = Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue
    if ($listener) { $port }
}
if ($occupied) {
    throw "Demo Emulator ports are already in use ($($occupied -join ', ')); existing processes were not contacted."
}

$previous = @{}
$names = @(
    'GCLOUD_PROJECT', 'GOOGLE_CLOUD_PROJECT', 'FIREBASE_CONFIG',
    'FUNCTIONS_EMULATOR', 'FIRESTORE_EMULATOR_HOST', 'FIREBASE_AUTH_EMULATOR_HOST',
    'FUNCTIONS_EMULATOR_HOST', 'FUNCTIONS_EMULATOR_PORT',
    'GOOGLE_APPLICATION_CREDENTIALS', 'GOOGLE_CLOUD_KEYFILE_JSON', 'FIREBASE_TOKEN',
    'SUPABASE_ACCESS_TOKEN', 'SUPABASE_DB_PASSWORD', 'CATALOG_DATABASE_URL',
    'CATALOG_CONSUMER_HMAC_SECRET', 'FIREBASE_SERVICE_ACCOUNT_JSON'
)
foreach ($name in $names) { $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }

try {
    Set-SearchLocalRuntimeEnvironment -Runtime $runtime
    $env:GCLOUD_PROJECT = 'demo-universal-search'
    $env:GOOGLE_CLOUD_PROJECT = 'demo-universal-search'
    $env:FIREBASE_CONFIG = '{"projectId":"demo-universal-search"}'
    $env:FUNCTIONS_EMULATOR = 'true'
    $env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8087'
    $env:FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9097'
    $env:FUNCTIONS_EMULATOR_HOST = '127.0.0.1:5007'
    $env:FUNCTIONS_EMULATOR_PORT = '5007'
    foreach ($name in $names | Where-Object { $_ -match 'CREDENTIALS|KEYFILE|TOKEN|PASSWORD|DATABASE_URL|HMAC_SECRET|SERVICE_ACCOUNT_JSON' }) {
        Remove-Item "Env:$name" -ErrorAction SilentlyContinue
    }

    Write-Output 'Running public backend integration against demo-universal-search on loopback; no import/export or hosted project is selected.'
    Push-Location $functionsRoot
    try {
        & $runtime.Firebase emulators:exec --only auth,firestore,functions `
            --config $configPath --project demo-universal-search --non-interactive `
            'node integration/public_backend_emulator_suite.js'
        if ($LASTEXITCODE -ne 0) { throw "Public backend Emulator suite failed (exit $LASTEXITCODE)." }
    } finally { Pop-Location }
} finally {
    foreach ($name in $names) {
        [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process')
    }
}
