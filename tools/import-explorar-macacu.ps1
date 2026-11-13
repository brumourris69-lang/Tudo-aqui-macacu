$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$appRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$configPath = Join-Path $env:LOCALAPPDATA 'TudoAquiMacacu/emulator-snapshots/banner-qa-20261111-pre-ui/spark-local-config.json'
$backupPath = Join-Path $env:LOCALAPPDATA 'TudoAquiMacacu/emulator-snapshots/explorar-macacu-20261112-pre-import'
$checksumPath = Join-Path $env:LOCALAPPDATA 'TudoAquiMacacu/emulator-snapshots/explorar-macacu-20261112-pre-import.sha256.txt'
$emulatorHosts = @{
    'Auth Emulator' = 9097
    'Firestore Emulator' = 8087
    'Emulator Hub' = 4407
}

foreach ($entry in $emulatorHosts.GetEnumerator()) {
    $client = [Net.Sockets.TcpClient]::new()
    try { $client.Connect('127.0.0.1', $entry.Value) }
    catch { throw "$($entry.Key) is not listening on 127.0.0.1:$($entry.Value). No write was attempted." }
    finally { $client.Dispose() }
}

if (!(Test-Path -LiteralPath $configPath) -or
    !(Test-Path -LiteralPath $backupPath) -or
    !(Test-Path -LiteralPath $checksumPath)) {
    throw 'Expected local Emulator config or verified pre-import backup is missing.'
}

$hub = Invoke-RestMethod -Method Get -Uri 'http://127.0.0.1:4407/emulators' -TimeoutSec 3
$activeEmulators = @($hub.PSObject.Properties.Name |
    Where-Object { $_ -notin @('hub', 'logging') } |
    Sort-Object)
if ($hub.auth.host -ne '127.0.0.1' -or $hub.auth.port -ne 9097 -or
    $hub.firestore.host -ne '127.0.0.1' -or $hub.firestore.port -ne 8087 -or
    ($activeEmulators -join ',') -ne 'auth,firestore') {
    throw 'Hub did not confirm the isolated Auth/Firestore-only Emulator set.'
}

$firebaseProcesses = @(Get-CimInstance Win32_Process | Where-Object {
    $_.Name -eq 'firebase-tools.exe' -and $_.CommandLine -match 'emulators:start'
})
if ($firebaseProcesses.Count -lt 1 -or $firebaseProcesses.Count -gt 2) {
    throw 'Could not prove one unambiguous running Firebase Emulator process; no write was attempted.'
}
$processIds = @($firebaseProcesses | ForEach-Object { $_.ProcessId })
$roots = @($firebaseProcesses | Where-Object { $_.ParentProcessId -notin $processIds })
if ($roots.Count -ne 1) {
    throw 'Firebase CLI processes do not form one parent-child Emulator invocation; no write was attempted.'
}
foreach ($process in $firebaseProcesses) {
    $commandLine = $process.CommandLine
    if ($commandLine -notmatch '--project demo-universal-search' -or
        $commandLine -notmatch '--only auth,firestore' -or
        $commandLine -notmatch [regex]::Escape($configPath) -or
        $commandLine -match 'functions|hosting|storage|macacu-beta-261030-cf4a81') {
        throw 'Running Firebase CLI process is not the expected local demo project/config; no write was attempted.'
    }
}

$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$configuredRules = [string]$config.firestore.rules
$rulesPath = if ([IO.Path]::IsPathRooted($configuredRules)) {
    [IO.Path]::GetFullPath($configuredRules)
} else {
    [IO.Path]::GetFullPath((Join-Path (Split-Path $configPath -Parent) $configuredRules))
}
$expectedRules = [IO.Path]::GetFullPath((Join-Path $appRoot 'firestore.beta.rules'))
if ($config.emulators.auth.host -ne '127.0.0.1' -or $config.emulators.auth.port -ne 9097 -or
    $config.emulators.firestore.host -ne '127.0.0.1' -or $config.emulators.firestore.port -ne 8087 -or
    $config.emulators.hub.host -ne '127.0.0.1' -or $config.emulators.hub.port -ne 4407 -or
    $rulesPath -ne $expectedRules) {
    throw 'Local config does not use the expected endpoints and Beta Rules; no write was attempted.'
}

$node = (Get-Command node -ErrorAction Stop).Source
$environmentNames = @(
    'GCLOUD_PROJECT', 'GOOGLE_CLOUD_PROJECT', 'FIREBASE_CONFIG',
    'FIRESTORE_EMULATOR_HOST', 'FIREBASE_AUTH_EMULATOR_HOST',
    'GOOGLE_APPLICATION_CREDENTIALS', 'FIREBASE_TOKEN',
    'LOCAL_TOURISM_IMPORT_CONFIRM', 'TOURISM_IMPORT_CONFIG',
    'TOURISM_IMPORT_BACKUP', 'TOURISM_IMPORT_BACKUP_CHECKSUMS'
)
$previous = @{}
foreach ($name in $environmentNames) { $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
try {
    $env:GCLOUD_PROJECT = 'demo-universal-search'
    $env:GOOGLE_CLOUD_PROJECT = 'demo-universal-search'
    $env:FIREBASE_CONFIG = '{"projectId":"demo-universal-search"}'
    $env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8087'
    $env:FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9097'
    $env:GOOGLE_APPLICATION_CREDENTIALS = $null
    $env:FIREBASE_TOKEN = $null
    $env:LOCAL_TOURISM_IMPORT_CONFIRM = 'demo-universal-search'
    $env:TOURISM_IMPORT_CONFIG = $configPath
    $env:TOURISM_IMPORT_BACKUP = $backupPath
    $env:TOURISM_IMPORT_BACKUP_CHECKSUMS = $checksumPath

    & $node (Join-Path $PSScriptRoot 'import-explorar-macacu.cjs')
    if ($LASTEXITCODE -ne 0) { throw 'The Emulator-only import did not complete successfully.' }
} finally {
    foreach ($name in $environmentNames) {
        [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process')
    }
}
