$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$appRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'local-demo-runtime.ps1')
$runtime = Get-SearchLocalRuntime -AppRoot $appRoot
Set-SearchLocalRuntimeEnvironment -Runtime $runtime
foreach ($port in @(9097, 8087, 4407)) {
    if (Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue) {
        throw "Port $port já está ocupado; nada foi iniciado."
    }
}
$configPath = Join-Path $env:LOCALAPPDATA ("Temp\MacacuSparkLocal-" + [guid]::NewGuid().ToString('N') + '.json')
$config = @{
    firestore = @{ rules = (Join-Path $appRoot 'firestore.beta.rules') }
    emulators = @{
        auth = @{ host = '127.0.0.1'; port = 9097 }
        firestore = @{ host = '127.0.0.1'; port = 8087 }
        hub = @{ host = '127.0.0.1'; port = 4407 }
        ui = @{ enabled = $false }
        singleProjectMode = $true
    }
}
$json = $config | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText($configPath, $json, [System.Text.UTF8Encoding]::new($false))
$env:GCLOUD_PROJECT = 'demo-universal-search'
$env:GOOGLE_CLOUD_PROJECT = 'demo-universal-search'
$env:FIREBASE_CONFIG = '{"projectId":"demo-universal-search"}'
$env:FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9097'
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8087'
Remove-Item Env:FIREBASE_TOKEN -ErrorAction SilentlyContinue
Remove-Item Env:GOOGLE_APPLICATION_CREDENTIALS -ErrorAction SilentlyContinue
Write-Output "CONFIG_PATH=$configPath"
Write-Output 'Starting only local Auth and Firestore emulators for demo-universal-search.'
try {
    & $runtime.Firebase emulators:start --only auth,firestore --config $configPath `
        --project demo-universal-search --non-interactive
    if ($LASTEXITCODE -ne 0) { throw 'Firebase Emulators did not exit cleanly.' }
} finally {
    Remove-Item Env:FIREBASE_TOKEN -ErrorAction SilentlyContinue
    Remove-Item Env:GOOGLE_APPLICATION_CREDENTIALS -ErrorAction SilentlyContinue
    if (!(Get-NetTCPConnection -State Listen -LocalPort 9097,8087,4407 -ErrorAction SilentlyContinue)) {
        Remove-Item -LiteralPath $configPath -Force -ErrorAction SilentlyContinue
    }
}
