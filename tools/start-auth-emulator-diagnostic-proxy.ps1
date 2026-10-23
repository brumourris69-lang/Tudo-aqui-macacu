$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$appRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'local-demo-runtime.ps1')
$runtime = Get-SearchLocalRuntime -AppRoot $appRoot
$configPath = Join-Path $appRoot 'firebase.search-emulator.json'
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json

if ($config.emulators.auth.host -ne '127.0.0.1' -or $config.emulators.auth.port -ne 9097 -or
    $config.emulators.firestore.host -ne '127.0.0.1' -or $config.emulators.firestore.port -ne 8087 -or
    $config.emulators.functions.host -ne '127.0.0.1' -or $config.emulators.functions.port -ne 5007 -or
    $config.emulators.hub.host -ne '127.0.0.1' -or $config.emulators.hub.port -ne 4407) {
    throw 'Diagnostic proxy requires firebase.search-emulator.json on the approved demo loopback ports.'
}

$firebaseProcesses = @(Get-CimInstance Win32_Process | Where-Object {
    $_.CommandLine -and $_.CommandLine -match '(?i)firebase' -and
    $_.CommandLine -match '(?i)emulators:(?:start|exec)'
})
$demoCli = $firebaseProcesses | Where-Object {
    $_.CommandLine -match '(?i)--project(?:=|\s+)"?demo-universal-search(?:"|\s|$)' -and
    $_.CommandLine -match '(?i)--config(?:=|\s+)"?[^"\r\n]*firebase\.search-emulator\.json(?:"|\s|$)'
} | Select-Object -First 1
if (!$demoCli) {
    throw 'Could not verify an active Firebase CLI process explicitly using demo-universal-search and firebase.search-emulator.json.'
}

$processes = @(Get-CimInstance Win32_Process)
$processById = @{}
foreach ($process in $processes) { $processById[[int]$process.ProcessId] = $process }
foreach ($port in @(9097, 8087, 5007)) {
    $listeners = @(Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue)
    if (!$listeners -or @($listeners | Where-Object { $_.LocalAddress -ne '127.0.0.1' }).Count -gt 0) {
        throw "Required Emulator port $port is not exclusively listening on loopback."
    }
    foreach ($listener in $listeners) {
        $current = $processById[[int]$listener.OwningProcess]
        $belongsToDemo = $false
        for ($depth = 0; $depth -lt 12 -and $current; $depth++) {
            if ([int]$current.ProcessId -eq [int]$demoCli.ProcessId) {
                $belongsToDemo = $true
                break
            }
            $parentId = [int]$current.ParentProcessId
            if (!$processById.ContainsKey($parentId)) { break }
            $current = $processById[$parentId]
        }
        if (!$belongsToDemo) {
            throw "Emulator port $port is not owned by the verified demo CLI process."
        }
    }
}

try {
    $hub = Invoke-RestMethod -Uri 'http://127.0.0.1:4407/emulators' -TimeoutSec 2
} catch {
    throw 'The local Firebase Emulator Hub did not respond; proxy was not started.'
}
if ($hub.auth.host -ne '127.0.0.1' -or $hub.auth.port -ne 9097 -or
    $hub.firestore.host -ne '127.0.0.1' -or $hub.firestore.port -ne 8087 -or
    $hub.functions.host -ne '127.0.0.1' -or $hub.functions.port -ne 5007) {
    throw 'The Emulator Hub does not match the approved local endpoints; proxy was not started.'
}

if (Get-NetTCPConnection -State Listen -LocalPort 9197 -ErrorAction SilentlyContinue) {
    throw 'Port 9197 is already occupied; the existing process was left untouched.'
}

$proxyPath = Join-Path $PSScriptRoot 'auth-emulator-diagnostic-proxy.cjs'
$previousProject = $env:GCLOUD_PROJECT
$previousGoogleProject = $env:GOOGLE_CLOUD_PROJECT
$previousFirebaseConfig = $env:FIREBASE_CONFIG
try {
    $env:GCLOUD_PROJECT = 'demo-universal-search'
    $env:GOOGLE_CLOUD_PROJECT = 'demo-universal-search'
    $env:FIREBASE_CONFIG = '{"projectId":"demo-universal-search"}'
    & $runtime.Node $proxyPath --project demo-universal-search
    if ($LASTEXITCODE -ne 0) { throw 'Diagnostic proxy exited; no Emulator process was modified.' }
} finally {
    $env:GCLOUD_PROJECT = $previousProject
    $env:GOOGLE_CLOUD_PROJECT = $previousGoogleProject
    $env:FIREBASE_CONFIG = $previousFirebaseConfig
}
