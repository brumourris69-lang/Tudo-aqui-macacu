$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$appRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$nodeCandidates = @(
    (Join-Path (Split-Path $appRoot -Parent) 'work/hot-reload-runtimes/node-v22.23.0-win-x64/node.exe'),
    (Get-Command node -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue)
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
$node = $null
foreach ($candidate in $nodeCandidates) {
    $version = (& $candidate --version 2>$null | Select-Object -First 1)
    if ($version -match '^v22\.') { $node = $candidate; break }
}
if (!$node) { throw 'Node.js 22 existente não encontrado; nenhuma ferramenta será instalada.' }
if (!(Test-Path -LiteralPath (Join-Path $appRoot 'functions/node_modules/firebase-admin'))) {
    throw 'firebase-admin local não está disponível; nada será instalado.'
}

$previous = @{}
foreach ($name in @(
    'GCLOUD_PROJECT', 'GOOGLE_CLOUD_PROJECT', 'FIREBASE_CONFIG',
    'FIREBASE_AUTH_EMULATOR_HOST', 'FIRESTORE_EMULATOR_HOST',
    'FUNCTIONS_EMULATOR_HOST', 'FUNCTIONS_EMULATOR_PORT', 'LOCAL_ADMIN_BRIDGE_CONFIRM',
    'LOCAL_ADMIN_BRIDGE_PORT', 'GOOGLE_APPLICATION_CREDENTIALS', 'FIREBASE_TOKEN'
)) { $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }

try {
    $env:GCLOUD_PROJECT = 'demo-universal-search'
    $env:GOOGLE_CLOUD_PROJECT = 'demo-universal-search'
    $env:FIREBASE_CONFIG = '{"projectId":"demo-universal-search"}'
    $env:FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9097'
    $env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8087'
    $env:FUNCTIONS_EMULATOR_HOST = '127.0.0.1:5007'
    $env:FUNCTIONS_EMULATOR_PORT = '5007'
    $env:LOCAL_ADMIN_BRIDGE_CONFIRM = 'demo-universal-search'
    $env:LOCAL_ADMIN_BRIDGE_PORT = '5077'
    Remove-Item Env:GOOGLE_APPLICATION_CREDENTIALS -ErrorAction SilentlyContinue
    Remove-Item Env:FIREBASE_TOKEN -ErrorAction SilentlyContinue
    Push-Location $appRoot
    try {
        & $node 'functions/integration/local_admin_establishments_bridge.mjs'
        if ($LASTEXITCODE -ne 0) { throw 'Local Admin bridge exited with an error.' }
    } finally { Pop-Location }
} finally {
    foreach ($name in $previous.Keys) {
        [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process')
    }
}
