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
$snapshotRoot = Join-Path $env:LOCALAPPDATA 'TudoAquiMacacu\emulator-snapshots'
$baseSnapshot = Join-Path $snapshotRoot 'sparklocal-visual-20261116-1007'
$sessionId = 'sparklocal-session-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' +
    [guid]::NewGuid().ToString('N').Substring(0, 8)
$exportPath = Join-Path $snapshotRoot $sessionId
$sessionManifestPath = Join-Path $snapshotRoot ($sessionId + '.json')
$rulesPath = Join-Path $appRoot 'firestore.beta.rules'

function Test-CompleteSparkLocalExport {
    param([Parameter(Mandatory)][string]$Path)

    $metadataPath = Join-Path $Path 'firebase-export-metadata.json'
    if (!(Test-Path -LiteralPath $metadataPath -PathType Leaf)) { return $false }
    try {
        $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
        return $metadata.version -eq '15.32.1' -and
            $metadata.auth.path -eq 'auth_export' -and
            $metadata.firestore.path -eq 'firestore_export' -and
            (Test-Path -LiteralPath (Join-Path $Path 'auth_export/accounts.json') -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-Path $Path 'firestore_export/firestore_export.overall_export_metadata') -PathType Leaf)
    } catch { return $false }
}

function Get-SparkLocalImportSnapshot {
    $sessions = @(Get-ChildItem -LiteralPath $snapshotRoot -Directory -Filter 'sparklocal-session-*' `
        -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    foreach ($session in $sessions) {
        $sidecarPath = Join-Path $snapshotRoot ($session.Name + '.json')
        if (!(Test-CompleteSparkLocalExport -Path $session.FullName) -or
            !(Test-Path -LiteralPath $sidecarPath -PathType Leaf)) { continue }
        try {
            $sidecar = Get-Content -LiteralPath $sidecarPath -Raw | ConvertFrom-Json
            if ($sidecar.projectId -eq 'demo-universal-search' -and
                $sidecar.rulesSha256 -eq (Get-FileHash -LiteralPath $rulesPath -Algorithm SHA256).Hash.ToLowerInvariant() -and
                $sidecar.firebaseCliVersion -eq '15.32.1') {
                return $session.FullName
            }
        } catch { continue }
    }

    $baseManifestPath = Join-Path $baseSnapshot 'spark-local-visual-manifest.json'
    if (!(Test-CompleteSparkLocalExport -Path $baseSnapshot) -or
        !(Test-Path -LiteralPath $baseManifestPath -PathType Leaf)) {
        throw 'Não existe snapshot SparkLocal completo e validado; nenhum Emulator foi iniciado.'
    }
    $baseManifest = Get-Content -LiteralPath $baseManifestPath -Raw | ConvertFrom-Json
    if ($baseManifest.project -ne 'demo-universal-search' -or
        $baseManifest.auth -ne '127.0.0.1:9097' -or
        $baseManifest.firestore -ne '127.0.0.1:8087' -or
        $baseManifest.rules -ne 'firestore.beta.rules') {
        throw 'A identidade do snapshot inicial não corresponde ao SparkLocal; nenhum Emulator foi iniciado.'
    }
    return $baseSnapshot
}

$importPath = Get-SparkLocalImportSnapshot
if (!(Test-Path -LiteralPath $snapshotRoot -PathType Container)) {
    throw 'A pasta de snapshots SparkLocal desapareceu antes da inicialização.'
}
$config = @{
    firestore = @{ rules = $rulesPath }
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
Write-Output "IMPORT_SNAPSHOT=$importPath"
Write-Output "EXPORT_SNAPSHOT=$exportPath"
Write-Output 'Starting only local Auth and Firestore emulators for demo-universal-search.'
$emulatorExitCode = $null
$exportSaved = $false
try {
    & $runtime.Firebase emulators:start --only auth,firestore --config $configPath `
        --project demo-universal-search "--import=$importPath" "--export-on-exit=$exportPath" --non-interactive
    $emulatorExitCode = $LASTEXITCODE
} finally {
    Remove-Item Env:FIREBASE_TOKEN -ErrorAction SilentlyContinue
    Remove-Item Env:GOOGLE_APPLICATION_CREDENTIALS -ErrorAction SilentlyContinue
    if (!(Get-NetTCPConnection -State Listen -LocalPort 9097,8087,4407 -ErrorAction SilentlyContinue)) {
        Remove-Item -LiteralPath $configPath -Force -ErrorAction SilentlyContinue
    }
    if (Test-CompleteSparkLocalExport -Path $exportPath) {
        $sessionManifest = [ordered]@{
            projectId = 'demo-universal-search'
            firebaseCliVersion = '15.32.1'
            rulesSha256 = (Get-FileHash -LiteralPath $rulesPath -Algorithm SHA256).Hash.ToLowerInvariant()
            sourceSnapshot = Split-Path -Leaf $importPath
            createdAt = [DateTime]::UtcNow.ToString('o')
        }
        [IO.File]::WriteAllText(
            $sessionManifestPath,
            ($sessionManifest | ConvertTo-Json),
            [Text.UTF8Encoding]::new($false)
        )
        $exportSaved = $true
    }
}

if (!$exportSaved) {
    throw "O Emulator encerrou sem um export completo. Snapshot anterior preservado em: $importPath"
}
if ($null -ne $emulatorExitCode -and $emulatorExitCode -ne 0) {
    throw "Emulator encerrou com status $emulatorExitCode, mas os dados foram salvos em: $exportPath"
}
Write-Output "SparkLocal data saved. Next launch will import: $exportPath"
