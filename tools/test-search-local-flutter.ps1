param(
    [switch]$IncludeAppCheckMatrix
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot '..\pubspec.yaml'))) {
    throw 'Run this script from the application tools directory.'
}
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

# Remove credentials and hosted project selectors from this child process.
$sensitiveVariables = @(
    'FIREBASE_TOKEN', 'GOOGLE_APPLICATION_CREDENTIALS', 'GOOGLE_CLOUD_KEYFILE_JSON',
    'SUPABASE_ACCESS_TOKEN', 'SUPABASE_DB_PASSWORD', 'CATALOG_DATABASE_URL',
    'CATALOG_CONSUMER_HMAC_SECRET', 'FIREBASE_SERVICE_ACCOUNT_JSON'
)
foreach ($name in $sensitiveVariables) {
    Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue
}

# SDKs that honor emulator environment variables must fail against loopback only.
$env:GCLOUD_PROJECT = 'demo-universal-search'
$env:GOOGLE_CLOUD_PROJECT = 'demo-universal-search'
$env:FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9097'
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8087'
$env:FIREBASE_STORAGE_EMULATOR_HOST = '127.0.0.1:9199'

$localDefines = @(
    '--dart-define=LOCAL_SEARCH_EMULATORS=true',
    '--dart-define=LOCAL_SEARCH_PROJECT=demo-universal-search',
    '--dart-define=LOCAL_SEARCH_HOST=127.0.0.1'
)

function Invoke-FlutterTestRun {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )
    Write-Host "Running Flutter tests: $Label"
    Push-Location -LiteralPath $projectRoot
    try {
        & flutter @Arguments
        $flutterExitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }
    if ($flutterExitCode -ne 0) {
        throw "Flutter test run '$Label' failed with exit code $flutterExitCode."
    }
}

# Run each compile-time mode explicitly. Tests tagged search-local are kept
# separate so local session flows never run under the regular app flavor.
Invoke-FlutterTestRun -Label 'standard' -Arguments @(
    'test', '--no-pub', '--exclude-tags', 'search-local'
)
Invoke-FlutterTestRun -Label 'searchLocal' -Arguments (@(
    'test', '--no-pub'
) + $localDefines + @('--tags', 'search-local'))

if ($IncludeAppCheckMatrix) {
    $appCheckDefines = @($localDefines) + @('--dart-define=LOCAL_SEARCH_APP_CHECK=true')
    Invoke-FlutterTestRun -Label 'searchLocal-AppCheck' -Arguments (@(
        'test', '--no-pub'
    ) + $appCheckDefines + @('test\app_check_preparation_test.dart'))
}
