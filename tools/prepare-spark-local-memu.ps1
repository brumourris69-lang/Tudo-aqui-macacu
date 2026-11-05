[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$appRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$script:adbPath = Join-Path $env:LOCALAPPDATA 'Android/Sdk/platform-tools/adb.exe'
$script:memucPath = 'C:\Program Files\Microvirt\MEmu\memuc.exe'
$script:device = '127.0.0.1:21503'
$script:package = 'br.com.tudoaquimacacu.tudo_aqui_macacu.sparklocal'
$script:ports = @(9097, 8087)
$script:rulesPath = (Resolve-Path (Join-Path $appRoot 'firestore.beta.rules')).Path

if (!(Test-Path -LiteralPath $script:adbPath)) {
    throw 'Android Debug Bridge não encontrado; nenhum encaminhamento foi alterado.'
}
if (!(Test-Path -LiteralPath $script:memucPath)) {
    throw 'MEmu CLI não encontrado; a identidade do dispositivo não pode ser confirmada.'
}

function Invoke-LocalAdb {
    param([Parameter(Mandatory)][string[]]$Arguments)

    if ($Arguments.Count -eq 2 -and $Arguments[0] -eq 'devices' -and $Arguments[1] -eq '-l') {
        $output = & $script:adbPath @Arguments 2>&1
    } elseif ($Arguments.Count -eq 2 -and $Arguments[0] -eq 'connect' -and
        $Arguments[1] -eq $script:device) {
        $output = & $script:adbPath @Arguments 2>&1
    } elseif ($Arguments.Count -ge 3 -and $Arguments[0] -eq '-s' -and
        $Arguments[1] -eq $script:device -and $Arguments[2] -eq 'reverse') {
        if ($Arguments.Count -eq 4 -and $Arguments[3] -eq '--list') {
            $output = & $script:adbPath @Arguments 2>&1
        } elseif ($Arguments.Count -eq 5 -and
            $Arguments[3] -match '^tcp:(9097|8087)$' -and
            $Arguments[4] -eq $Arguments[3]) {
            $localEndpoint = $Arguments[3]
            $existing = @(& $script:adbPath -s $script:device reverse --list 2>&1)
            if ($LASTEXITCODE -ne 0) {
                throw 'Não foi possível conferir o encaminhamento existente; nenhuma substituição foi tentada.'
            }
            foreach ($line in $existing) {
                $parts = @(([string]$line) -split '\s+')
                if ($parts.Count -ge 3 -and $parts[-2] -eq $localEndpoint -and
                    $parts[-1] -ne $localEndpoint) {
                    throw "Encaminhamento conflitante em $localEndpoint; nada foi substituído."
                }
            }
            $matching = @($existing | Where-Object {
                $parts = @(([string]$_) -split '\s+')
                $parts.Count -ge 3 -and $parts[-2] -eq $localEndpoint -and
                    $parts[-1] -eq $localEndpoint
            })
            if ($matching.Count -gt 0) { return @() }
            $output = & $script:adbPath @Arguments 2>&1
        } else {
            throw 'O preflight permite encaminhar somente tcp:9097 e tcp:8087 para a mesma porta local.'
        }
    } elseif ($Arguments.Count -ge 4 -and $Arguments[0] -eq '-s' -and
        $Arguments[1] -eq $script:device -and $Arguments[2] -eq 'shell') {
        $remote = @($Arguments[3..($Arguments.Count - 1)])
        $allowedRead =
            ($remote.Count -eq 5 -and $remote[0] -eq 'cmd' -and $remote[1] -eq 'package' -and
                $remote[2] -eq 'list' -and $remote[3] -eq 'packages' -and $remote[4] -eq '-U') -or
            ($remote.Count -eq 2 -and $remote[0] -eq 'dumpsys' -and $remote[1] -eq 'connectivity')
        if (!$allowedRead) { throw 'Comando Android fora das verificações somente leitura autorizadas.' }
        $output = & $script:adbPath @Arguments 2>&1
    } else {
        throw 'Comando ADB fora do escopo do preflight SparkLocal/MEmu.'
    }

    if ($LASTEXITCODE -eq 0) { return $output }
    $errorText = $output -join "`n"
    if ($errorText -match '(?i)device .*not found|device offline|no devices/emulators found|connection reset|protocol fault|closed') {
        throw 'ADB_TRANSPORT_UNAVAILABLE: MEmu desconectado durante a verificação local.'
    }
    throw 'ADB_READ_FAILED: falha na verificação local do MEmu.'
}

function Get-EmulatorCliAncestor {
    param([Parameter(Mandatory)][int]$ProcessId)

    $seen = @{}
    while ($ProcessId -gt 0 -and !$seen.ContainsKey($ProcessId)) {
        $seen[$ProcessId] = $true
        $process = Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId" `
            -ErrorAction SilentlyContinue
        if (!$process) { return $null }
        $commandLine = [string]$process.CommandLine
        if ($process.Name -eq 'firebase-tools.exe' -and
            $commandLine -match '(?i)emulators:start' -and
            $commandLine -match '(?i)--only\s+auth,firestore(?:\s|$)' -and
            $commandLine -match '(?i)--project\s+demo-universal-search(?:\s|$)') {
            return $process
        }
        $ProcessId = [int]$process.ParentProcessId
    }
    return $null
}

function Get-ConfigPathFromCli {
    param([Parameter(Mandatory)][string]$CommandLine)

    $match = [regex]::Match($CommandLine, '(?i)--config\s+(?:"(?<quoted>[^"]+\.json)"|(?<plain>[^\s]+\.json))')
    if (!$match.Success) { throw 'A CLI ativa não informa configuração local explícita.' }
    if ($match.Groups['quoted'].Success) { return $match.Groups['quoted'].Value }
    return $match.Groups['plain'].Value
}

function Get-LoopbackListener {
    param([Parameter(Mandatory)][int]$Port)

    $allListeners = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
        Where-Object { $_.LocalPort -eq $Port })
    if (!$allListeners -or ($allListeners | Where-Object { $_.LocalAddress -ne '127.0.0.1' })) {
        throw "A porta $Port está ausente ou não está limitada a 127.0.0.1."
    }
    return $allListeners
}

function Test-SparkLocalEndpoints {
    param([int[]]$Ports)

    if (@($Ports | Sort-Object) -join ',' -ne '8087,9097') { return $false }
    try {
        foreach ($port in @(9097, 8087, 4407)) {
            $listeners = @(Get-LoopbackListener -Port $port)
            foreach ($listener in $listeners) {
                $cli = Get-EmulatorCliAncestor -ProcessId ([int]$listener.OwningProcess)
                if (!$cli -or $cli.ProcessId -ne $script:firebaseCliPid) { return $false }
            }
        }
        $hub = Invoke-RestMethod -Uri 'http://127.0.0.1:4407' -TimeoutSec 3
        $services = Invoke-RestMethod -Uri 'http://127.0.0.1:4407/emulators' -TimeoutSec 3
        return $hub.version -eq '15.32.1' -and $hub.host -eq '127.0.0.1' -and
            $hub.port -eq 4407 -and $services.auth.host -eq '127.0.0.1' -and
            $services.auth.port -eq 9097 -and $services.firestore.host -eq '127.0.0.1' -and
            $services.firestore.port -eq 8087 -and
            !$services.PSObject.Properties['functions'] -and
            !$services.PSObject.Properties['hosting'] -and
            !$services.PSObject.Properties['storage']
    } catch {
        return $false
    }
}

# Prove this ADB serial is the sole active MEmu instance before any device
# command. Device model strings are deliberately not used as identity evidence.
$vmRows = @(& $script:memucPath listvms 2>&1)
if ($LASTEXITCODE -ne 0) { throw 'MEmu listvms falhou; nenhum comando Android foi enviado.' }
$vms = @()
foreach ($row in $vmRows) {
    $parts = @(([string]$row).Trim() -split ',')
    if ($parts.Count -ge 5 -and $parts[0] -match '^\d+$' -and $parts[3] -match '^\d+$') {
        $vms += [pscustomobject]@{
            Index = [int]$parts[0]
            Name = $parts[1]
            State = [int]$parts[3]
            ProcessId = [int]$parts[4]
        }
    }
}
$activeVms = @($vms | Where-Object { $_.State -eq 1 })
if ($activeVms.Count -ne 1 -or $activeVms[0].Index -ne 0 -or $activeVms[0].Name -ne 'MEmu') {
    throw 'A instância MEmu índice 0 não é a única instância ativa; destino ambíguo.'
}
$gui = Get-CimInstance Win32_Process -Filter "ProcessId = $($activeVms[0].ProcessId)" `
    -ErrorAction SilentlyContinue
if (!$gui -or $gui.Name -ne 'MEmu.exe' -or $gui.ExecutablePath -notmatch '\\Microvirt\\MEmu\\MEmu\.exe$') {
    throw 'O PID da instância MEmu não corresponde ao executável oficial.'
}
$headless = @(Get-CimInstance Win32_Process -Filter "Name = 'MEmuHeadless.exe'" |
    Where-Object { $_.ExecutablePath -match '\\Microvirt\\MEmuHyperv\\MEmuHeadless\.exe$' })
if ($headless.Count -ne 1) { throw 'O processo MEmuHeadless não é único; ADB não será usado.' }
$adbListener = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
    Where-Object { $_.LocalPort -eq 21503 })
if ($adbListener.Count -ne 1 -or $adbListener[0].LocalAddress -ne '127.0.0.1' -or
    $adbListener[0].OwningProcess -ne $headless[0].ProcessId) {
    throw 'A porta ADB 21503 não foi vinculada exclusivamente ao MEmuHeadless ativo.'
}

$deviceRows = @(Invoke-LocalAdb -Arguments @('devices', '-l'))
if (!($deviceRows | Where-Object { $_ -match '^127\.0\.0\.1:21503\s+device\b' })) {
    throw 'O serial ADB do MEmu não está pronto; nenhum outro dispositivo será usado.'
}

# Prove the live local Firebase process, its explicit project/config, loopback
# bindings and exact Rules file before restoring any reverse mapping.
$hub = Invoke-RestMethod -Uri 'http://127.0.0.1:4407' -TimeoutSec 3
$services = Invoke-RestMethod -Uri 'http://127.0.0.1:4407/emulators' -TimeoutSec 3
if ($hub.version -ne '15.32.1' -or $hub.host -ne '127.0.0.1' -or $hub.port -ne 4407 -or
    $services.auth.host -ne '127.0.0.1' -or $services.auth.port -ne 9097 -or
    $services.firestore.host -ne '127.0.0.1' -or $services.firestore.port -ne 8087 -or
    $services.PSObject.Properties['functions'] -or $services.PSObject.Properties['hosting'] -or
    $services.PSObject.Properties['storage'] -or $services.PSObject.Properties['eventarc']) {
    throw 'Hub Firebase não corresponde apenas a Auth/Firestore do demo em loopback.'
}

$cliOwners = [System.Collections.Generic.HashSet[int]]::new()
$cliProcesses = @{}
foreach ($port in @(4407, 9097, 8087)) {
    foreach ($listener in (Get-LoopbackListener -Port $port)) {
        $cli = Get-EmulatorCliAncestor -ProcessId ([int]$listener.OwningProcess)
        if (!$cli) { throw "A porta $port não pertence aos Emulators autorizados." }
        [void]$cliOwners.Add([int]$cli.ProcessId)
        $cliProcesses[[int]$cli.ProcessId] = $cli
    }
}
if ($cliOwners.Count -ne 1) { throw 'Os Emulators não compartilham um único processo CLI verificado.' }
$script:firebaseCliPid = [int]@($cliOwners)[0]
$firebaseCli = $cliProcesses[$script:firebaseCliPid]
$configPath = Get-ConfigPathFromCli -CommandLine ([string]$firebaseCli.CommandLine)
if (!(Test-Path -LiteralPath $configPath)) { throw 'A configuração temporária ativa não existe.' }
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$configRules = [IO.Path]::GetFullPath([string]$config.firestore.rules)
if ($configRules -ne $script:rulesPath -or
    $config.emulators.auth.host -ne '127.0.0.1' -or $config.emulators.auth.port -ne 9097 -or
    $config.emulators.firestore.host -ne '127.0.0.1' -or $config.emulators.firestore.port -ne 8087 -or
    $config.PSObject.Properties['functions'] -or $config.PSObject.Properties['hosting'] -or
    $config.emulators.PSObject.Properties['functions'] -or
    $config.emulators.PSObject.Properties['eventarc']) {
    throw 'A configuração ativa não é a configuração local SparkLocal Auth/Firestore aprovada.'
}

# Verify the installed SparkLocal package, VPN permission and UID-bound sink
# tunnel. This uses only the exact MEmu ADB serial, never the ASUS device.
$vpnSourcePath = Join-Path $appRoot 'android/app/src/searchLocal/kotlin/br/com/tudoaquimacacu/tudo_aqui_macacu/SearchLocalVpnService.kt'
$vpnSource = Get-Content -LiteralPath $vpnSourcePath -Raw
foreach ($requiredSource in @(
    '.addAllowedApplication(packageName)',
    '.addRoute("0.0.0.0", 0)',
    '.addRoute("::", 0)',
    '.setBlocking(true)')) {
    if (!$vpnSource.Contains($requiredSource)) {
        throw 'O código da VPN não corresponde ao isolamento fail-closed; nenhum encaminhamento será criado.'
    }
}
$packageRows = @(Invoke-LocalAdb -Arguments @('-s', $script:device, 'shell', 'cmd', 'package', 'list', 'packages', '-U'))
if (!($packageRows | Where-Object { $_ -match '^package:br\.com\.tudoaquimacacu\.tudo_aqui_macacu\.sparklocal\s+uid:\d+$' })) {
    throw 'O pacote SparkLocal não está instalado no MEmu identificado.'
}
$vpnPermission = & $script:adbPath -s $script:device shell appops get $script:package ACTIVATE_VPN 2>&1
if ($LASTEXITCODE -ne 0 -or ($vpnPermission -join "`n") -notmatch 'ACTIVATE_VPN:\s*allow') {
    throw 'A autorização da VPN SparkLocal não está ativa; não foi alterada.'
}
. (Join-Path $PSScriptRoot 'search-local-adb-reverse.ps1')
$vpnReady = Test-SearchLocalVpnIsolation -Device $script:device -Package $script:package `
    -InvokeAdb { param($Arguments) Invoke-LocalAdb -Arguments $Arguments }.GetNewClosure()
if (!$vpnReady) { throw 'A VPN ativa não corresponde ao UID SparkLocal; nenhum encaminhamento foi alterado.' }

$existingReverse = @(Invoke-LocalAdb -Arguments @('-s', $script:device, 'reverse', '--list'))
foreach ($line in $existingReverse) {
    $parts = @(([string]$line) -split '\s+')
    if ($parts.Count -ge 3 -and $parts[-2] -in @('tcp:9097', 'tcp:8087') -and
        $parts[-1] -ne $parts[-2]) {
        throw "Encaminhamento conflitante em $($parts[-2]); nada foi substituído."
    }
}

$verifyEndpoints = { param([int[]]$Ports) Test-SparkLocalEndpoints -Ports $Ports }.GetNewClosure()
$forwarding = Wait-SearchLocalForwardingStable -Device $script:device -Package $script:package `
    -InvokeAdb { param($Arguments) Invoke-LocalAdb -Arguments $Arguments }.GetNewClosure() `
    -VerifyLocalEndpoints $verifyEndpoints -Ports $script:ports -TimeoutSeconds 24 `
    -StableChecks 3 -PollMilliseconds 750

$finalReverse = @(Invoke-LocalAdb -Arguments @('-s', $script:device, 'reverse', '--list'))
foreach ($port in $script:ports) {
    $endpoint = "tcp:$port"
    $matches = @($finalReverse | Where-Object {
        $parts = @(([string]$_) -split '\s+')
        $parts.Count -ge 3 -and $parts[-2] -eq $endpoint -and $parts[-1] -eq $endpoint
    })
    if ($matches.Count -ne 1) { throw "Encaminhamento $endpoint não permaneceu estável." }
}
if (!(Test-SearchLocalVpnIsolation -Device $script:device -Package $script:package `
        -InvokeAdb { param($Arguments) Invoke-LocalAdb -Arguments $Arguments }.GetNewClosure()) -or
    !(Test-SparkLocalEndpoints -Ports $script:ports)) {
    throw 'VPN ou Emulators mudaram após o preflight; não inicie o aplicativo.'
}

$activity = & $script:adbPath -s $script:device shell dumpsys activity activities 2>&1
$mainActive = ($activity -join "`n") -match 'mResumedActivity:.*\.MainActivity'
$log = & $script:adbPath -s $script:device logcat -d -t 120 -s flutter:I 2>&1
$logText = $log -join "`n"
$isolationConfirmed = $logText.Contains('SPARK LOCAL ISOLATION VALIDATED: demo-universal-search')
$homeStartupReached = $logText.Contains('SPARK_STARTUP stage=home_listener_server_first')

Write-Output 'SparkLocal MEmu preflight aprovado.'
Write-Output "MEmu: instância índice $($activeVms[0].Index), ADB $script:device, processo MEmuHeadless confirmado."
Write-Output 'Firebase: demo-universal-search; Auth 127.0.0.1:9097; Firestore 127.0.0.1:8087; Rules locais firestore.beta.rules.'
Write-Output "VPN por UID SparkLocal: confirmada; encaminhamentos estáveis em $($forwarding.StableChecks) verificações."
Write-Output 'Portas gerenciadas por este comando: somente 9097 e 8087.'
Write-Output "App já em MainActivity: $mainActive; isolamento SparkLocal confirmado: $isolationConfirmed; carregamento da Home iniciado: $homeStartupReached."
Write-Output ("Para abrir pelo Gate após este preflight: & `"$script:adbPath`" -s $script:device shell am start -a android.intent.action.MAIN -n $script:package/br.com.tudoaquimacacu.tudo_aqui_macacu.SearchLocalGateActivity")
