$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$appRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'local-demo-runtime.ps1')
$runtime = Get-SearchLocalRuntime -AppRoot $appRoot
Set-SearchLocalRuntimeEnvironment -Runtime $runtime

$expected = 'demo-universal-search'
$typed = Read-Host "Confirme o projeto local digitando $expected"
if ($typed -cne $expected) { throw 'Confirmação recusada; nenhuma conta foi criada.' }

$config = Get-Content -LiteralPath (Join-Path $appRoot 'firebase.search-emulator.json') -Raw | ConvertFrom-Json
foreach ($service in @(
    [pscustomobject]@{ Name = 'auth'; Port = 9097 },
    [pscustomobject]@{ Name = 'firestore'; Port = 8087 },
    [pscustomobject]@{ Name = 'functions'; Port = 5007 }
)) {
    $name = $service.Name
    $port = $service.Port
    if ($config.emulators.$name.host -ne '127.0.0.1' -or
        $config.emulators.$name.port -ne $port -or !(Test-SearchLocalTcpPort -Port $port)) {
        throw "The expected loopback $name Emulator on port $port is not ready."
    }
}
$hub = Invoke-RestMethod -Uri "http://127.0.0.1:$($config.emulators.hub.port)/emulators" -TimeoutSec 3
foreach ($name in @('auth', 'firestore', 'functions')) {
    $expectedPort = [int]$config.emulators.$name.port
    if ($hub.$name.host -ne '127.0.0.1' -or $hub.$name.port -ne $expectedPort) {
        throw 'Emulator Hub identity does not match the local loopback configuration.'
    }
}

$listeners = Get-NetTCPConnection -State Listen -LocalPort 5007 -ErrorAction SilentlyContinue
$serverPids = @($listeners.OwningProcess | Sort-Object -Unique)
$verifiedDemoServer = $false
foreach ($processId in $serverPids) {
    $process = Get-CimInstance Win32_Process -Filter "ProcessId = $processId" -ErrorAction SilentlyContinue
    $line = [string]$process.CommandLine
    if ($process.Name -eq 'firebase-tools.exe' -and
        $line.Contains('emulators:start') -and
        $line.Contains('--project demo-universal-search') -and
        $line.Contains('firebase.search-emulator.json')) {
        $verifiedDemoServer = $true
    }
}
if (!$verifiedDemoServer) {
    throw 'Could not verify the Emulator CLI process is explicitly running the demo project/config.'
}

$email = (Read-Host 'E-mail fictício para a conta Admin local').Trim()
$securePassword = Read-Host 'Crie uma senha local com pelo menos 12 caracteres' -AsSecureString
$secureConfirmation = Read-Host 'Repita a senha local' -AsSecureString
$passwordBstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
$confirmationBstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureConfirmation)
$plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordBstr)
$plainConfirmation = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($confirmationBstr)
try {
    if ($plainPassword -cne $plainConfirmation) { throw 'As senhas não correspondem.' }
    $previous = @{
        Project = $env:GCLOUD_PROJECT
        GoogleProject = $env:GOOGLE_CLOUD_PROJECT
        FirebaseConfig = $env:FIREBASE_CONFIG
        Functions = $env:FUNCTIONS_EMULATOR
        Auth = $env:FIREBASE_AUTH_EMULATOR_HOST
        Firestore = $env:FIRESTORE_EMULATOR_HOST
        FunctionsHost = $env:FUNCTIONS_EMULATOR_HOST
        FunctionsPort = $env:FUNCTIONS_EMULATOR_PORT
        Confirm = $env:LOCAL_DEMO_CONFIRM
        Email = $env:LOCAL_DEMO_ADMIN_EMAIL
        Password = $env:LOCAL_DEMO_ADMIN_PASSWORD
        Credentials = $env:GOOGLE_APPLICATION_CREDENTIALS
        FirebaseToken = $env:FIREBASE_TOKEN
    }
    try {
        $env:GCLOUD_PROJECT = $expected
        $env:GOOGLE_CLOUD_PROJECT = $expected
        $env:FIREBASE_CONFIG = '{"projectId":"demo-universal-search"}'
        $env:FUNCTIONS_EMULATOR = 'true'
        $env:FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9097'
        $env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8087'
        $env:FUNCTIONS_EMULATOR_HOST = '127.0.0.1:5007'
        $env:FUNCTIONS_EMULATOR_PORT = '5007'
        $env:FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9097'
        $env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8087'
        $env:LOCAL_DEMO_CONFIRM = $expected
        $env:LOCAL_DEMO_ADMIN_EMAIL = $email
        $env:LOCAL_DEMO_ADMIN_PASSWORD = $plainPassword
        $env:GOOGLE_APPLICATION_CREDENTIALS = $null
        $env:FIREBASE_TOKEN = $null
        Push-Location (Join-Path $appRoot 'functions')
        try {
            & $runtime.Node integration/create_local_search_admin.js
            if ($LASTEXITCODE -ne 0) { throw 'Admin local provisioning failed; see the sanitized message above.' }
        } finally { Pop-Location }
    } finally {
        $env:GCLOUD_PROJECT = $previous.Project
        $env:GOOGLE_CLOUD_PROJECT = $previous.GoogleProject
        $env:FIREBASE_CONFIG = $previous.FirebaseConfig
        $env:FUNCTIONS_EMULATOR = $previous.Functions
        $env:FIREBASE_AUTH_EMULATOR_HOST = $previous.Auth
        $env:FIRESTORE_EMULATOR_HOST = $previous.Firestore
        $env:FUNCTIONS_EMULATOR_HOST = $previous.FunctionsHost
        $env:FUNCTIONS_EMULATOR_PORT = $previous.FunctionsPort
        $env:LOCAL_DEMO_CONFIRM = $previous.Confirm
        $env:LOCAL_DEMO_ADMIN_EMAIL = $previous.Email
        $env:LOCAL_DEMO_ADMIN_PASSWORD = $previous.Password
        $env:GOOGLE_APPLICATION_CREDENTIALS = $previous.Credentials
        $env:FIREBASE_TOKEN = $previous.FirebaseToken
    }
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordBstr)
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($confirmationBstr)
    $plainPassword = $null
    $plainConfirmation = $null
}
