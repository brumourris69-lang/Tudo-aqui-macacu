$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'search-local-adb-reverse.ps1')

# Keep a caller-local function in scope to prove the helper uses its own
# reusable serial wait instead of resolving an implicit callback dependency.
function Invoke-LauncherScopedReadRegression {
    function Wait-LocalDevice {
        throw 'The helper must not resolve a launcher-local Wait-LocalDevice.'
    }

    $read = {
        param($Arguments)
        if ($Arguments[0] -eq 'devices') { return @('127.0.0.1:21503 device transport_id:74') }
        if ($Arguments[0] -eq '-s' -and $Arguments[2] -eq 'shell') { return @('read-ok') }
        throw "Unexpected fake ADB command '$($Arguments -join ' ')' ."
    }

    return Invoke-SearchLocalAdbRead -Device '127.0.0.1:21503' `
        -Arguments @('shell', 'pm', 'path', 'demo.package') `
        -Operation 'launcher scope regression' -InvokeAdb $read
}

try {
    $scopeResult = Invoke-LauncherScopedReadRegression
} catch {
    throw "Regression: the helper depended on a launcher-local device function ($($_.Exception.Message))."
}
if ($scopeResult -ne 'read-ok') { throw 'Regression: launcher-scoped ADB read returned an unexpected result.' }
Write-Output 'PASS: helper resolves device readiness without a launcher-local function callback.'

# Exercise VPN isolation from the launcher's child-scope call path. The
# reusable helper owns ADB reads instead of a GetNewClosure callback.
$vpnScopeAdb = {
    param($Arguments)
    if ($Arguments[0] -eq 'devices') { return @('127.0.0.1:21503 device transport_id:76') }
    if ($Arguments[0] -eq 'connect') { return @('connected') }
    if ($Arguments[0] -eq '-s' -and $Arguments[2] -eq 'shell' -and $Arguments[3] -eq 'ip') {
        return @('30: tun0: <POINTOPOINT,UP,LOWER_UP>')
    }
    if ($Arguments[0] -eq '-s' -and $Arguments[3] -eq 'cmd') {
        return @('package:br.com.tudoaquimacacu.tudo_aqui_macacu.searchlocal uid:10073')
    }
    if ($Arguments[0] -eq '-s' -and $Arguments[3] -eq 'dumpsys') {
        return @('Transports: VPN Capabilities: INTERNET Uid: 10073 EstablishingAppUid: 10073')
    }
    throw "Unexpected fake ADB command '$($Arguments -join ' ')' ."
}.GetNewClosure()
function Invoke-LauncherScopedVpnValidation {
    return Test-SearchLocalVpnIsolation -Device '127.0.0.1:21503' `
        -Package 'br.com.tudoaquimacacu.tudo_aqui_macacu.searchlocal' -InvokeAdb $vpnScopeAdb
}
if (-not (Invoke-LauncherScopedVpnValidation)) {
    throw 'Regression: the imported VPN isolation helper rejected a matching tunnel and package UID.'
}
Write-Output 'PASS: VPN isolation helper works in launcher scope without a function-resolving closure.'

$mismatchedVpnAdb = {
    param($Arguments)
    if ($Arguments[0] -eq 'devices') { return @('127.0.0.1:21503 device transport_id:77') }
    if ($Arguments[0] -eq '-s' -and $Arguments[3] -eq 'ip') { return @('30: tun0: <POINTOPOINT,UP,LOWER_UP>') }
    if ($Arguments[0] -eq '-s' -and $Arguments[3] -eq 'cmd') {
        return @('package:br.com.tudoaquimacacu.tudo_aqui_macacu.searchlocal uid:10073')
    }
    if ($Arguments[0] -eq '-s' -and $Arguments[3] -eq 'dumpsys') {
        return @('Transports: VPN Capabilities: INTERNET Uid: 10099 EstablishingAppUid: 10099')
    }
}.GetNewClosure()
if (Test-SearchLocalVpnIsolation -Device '127.0.0.1:21503' `
        -Package 'br.com.tudoaquimacacu.tudo_aqui_macacu.searchlocal' -InvokeAdb $mismatchedVpnAdb) {
    throw 'Regression: VPN established by another UID must not authorize searchLocal access.'
}
Write-Output 'PASS: a VPN UID mismatch fails closed.'

function Assert-Equal($Expected, $Actual, [string]$Message) {
    if ($Expected -ne $Actual) {
        throw "$Message (expected '$Expected', got '$Actual')."
    }
}

$state = [pscustomobject]@{
    Transport = 70
    Switched = $false
    ReverseCommands = 0
    VpnChecks = 0
    Ports = [System.Collections.Generic.HashSet[int]]::new()
}
$invokeAdb = {
    param($Arguments)
    if ($Arguments[0] -eq 'devices') {
        if ($state.ReverseCommands -ge 3 -and !$state.Switched) {
            $state.Transport = 71
            $state.Switched = $true
            $state.Ports.Clear()
        }
        return @('List of devices attached', "127.0.0.1:21503`tdevice product:MEmu transport_id:$($state.Transport)")
    }
    if ($Arguments[0] -eq '-s' -and $Arguments[2] -eq 'shell' -and $Arguments[3] -eq 'ip') {
        $state.VpnChecks++
        return @('30: tun0: <POINTOPOINT,UP,LOWER_UP>')
    }
    if ($Arguments[0] -eq '-s' -and $Arguments[3] -eq 'cmd') {
        return @('package:br.com.tudoaquimacacu.tudo_aqui_macacu.searchlocal uid:10073')
    }
    if ($Arguments[0] -eq '-s' -and $Arguments[3] -eq 'dumpsys') {
        return @('Transports: VPN Capabilities: INTERNET Uid: 10073 EstablishingAppUid: 10073')
    }
    if ($Arguments[0] -eq '-s' -and $Arguments[1] -eq '127.0.0.1:21503' -and $Arguments[2] -eq 'reverse') {
        if ($Arguments[3] -eq '--list') {
            return @($state.Ports | Sort-Object | ForEach-Object { "host-$($state.Transport) tcp:$_ tcp:$_" })
        }
        $port = [int]($Arguments[3] -replace '^tcp:', '')
        [void]$state.Ports.Add($port)
        $state.ReverseCommands++
        return @('reversing local port to remote port')
    }
    throw "Unexpected fake ADB command '$($Arguments -join ' ')'."
}.GetNewClosure()
$verifyEndpoints = { return $true }

if (-not (Test-SearchLocalDiagnosticProxyIdentity `
        -CommandLine 'node tools/auth-emulator-diagnostic-proxy.cjs --project demo-universal-search' `
        -ProcessName 'node.exe' -ListeningAddress '127.0.0.1' -Port 9197)) {
    throw 'The correctly scoped loopback Auth diagnostic proxy must be accepted.'
}
foreach ($invalidProxy in @(
        @{ CommandLine = 'node tools/auth-emulator-diagnostic-proxy.cjs --project tudo-aqui-macacu'; Name = 'node.exe'; Address = '127.0.0.1'; Port = 9197 },
        @{ CommandLine = 'node tools/auth-emulator-diagnostic-proxy.cjs --project demo-universal-search'; Name = 'node.exe'; Address = '0.0.0.0'; Port = 9197 },
        @{ CommandLine = 'node tools/auth-emulator-diagnostic-proxy.cjs --project demo-universal-search'; Name = 'node.exe'; Address = '127.0.0.1'; Port = 9097 },
        @{ CommandLine = 'node tools/auth-emulator-diagnostic-proxy.cjs --project demo-universal-search'; Name = 'other.exe'; Address = '127.0.0.1'; Port = 9197 }
    )) {
    if (Test-SearchLocalDiagnosticProxyIdentity -CommandLine $invalidProxy.CommandLine `
            -ProcessName $invalidProxy.Name `
            -ListeningAddress $invalidProxy.Address -Port $invalidProxy.Port) {
        throw 'A non-demo, non-loopback, or wrong-port proxy must be rejected.'
    }
}
Write-Output 'PASS: diagnostic proxy identity requires project demo-universal-search, loopback, and port 9197.'

$result = Wait-SearchLocalForwardingStable `
    -Device '127.0.0.1:21503' `
    -Package 'br.com.tudoaquimacacu.tudo_aqui_macacu.searchlocal' `
    -InvokeAdb $invokeAdb `
    -VerifyLocalEndpoints $verifyEndpoints `
    -Ports @(9097, 9197, 8087, 5007) `
    -TimeoutSeconds 10 `
    -StableChecks 3 `
    -PollMilliseconds 10

Assert-Equal $true $state.Switched 'The fake MEmu transport should reconnect during setup.'
Assert-Equal 71 $result.TransportId 'The result should report the new transport.'
Assert-Equal 4 $state.Ports.Count 'All four mappings should be restored after reconnect.'
Assert-Equal 8 $state.ReverseCommands 'Each mapping should be restored once per transport.'
Assert-Equal 1 $result.ReconnectsDetected 'A single transport change should be counted once.'
if ($state.VpnChecks -lt 3) { throw 'VPN isolation must be rechecked during stabilization.' }
Write-Output 'PASS: transport reconnect restores and verifies all four diagnostic-mode ADB reverse mappings.'

$blocked = [pscustomobject]@{ ReverseCommands = 0 }
$blockedAdb = {
    param($Arguments)
    if ($Arguments[0] -eq 'devices') { return @('127.0.0.1:21503 device transport_id:72') }
    if ($Arguments[2] -eq 'reverse' -and $Arguments[3] -ne '--list') { $blocked.ReverseCommands++ }
    if ($Arguments[2] -eq 'reverse' -and $Arguments[3] -eq '--list') { return @() }
}.GetNewClosure()
try {
    Wait-SearchLocalForwardingStable -Device '127.0.0.1:21503' `
        -Package 'br.com.tudoaquimacacu.tudo_aqui_macacu.searchlocal' -InvokeAdb $blockedAdb `
        -VerifyLocalEndpoints $verifyEndpoints -TimeoutSeconds 1 `
        -StableChecks 1 -PollMilliseconds 10 | Out-Null
    throw 'Expected the routine to block when VPN isolation is absent.'
} catch {
    if ($_.Exception.Message -notmatch 'VPN isolation') { throw }
}
Assert-Equal 0 $blocked.ReverseCommands 'No mapping may be created before VPN isolation is confirmed.'
Write-Output 'PASS: missing VPN isolation blocks all ADB reverse changes.'

$endpointDenied = [pscustomobject]@{ ReverseCommands = 0 }
$denyEndpointAdb = {
    param($Arguments)
    if ($Arguments[0] -eq 'devices') { return @('127.0.0.1:21503 device transport_id:73') }
    if ($Arguments[0] -eq '-s' -and $Arguments[2] -eq 'shell' -and $Arguments[3] -eq 'ip') {
        return @('30: tun0: <POINTOPOINT,UP,LOWER_UP>')
    }
    if ($Arguments[0] -eq '-s' -and $Arguments[3] -eq 'cmd') {
        return @('package:br.com.tudoaquimacacu.tudo_aqui_macacu.searchlocal uid:10073')
    }
    if ($Arguments[0] -eq '-s' -and $Arguments[3] -eq 'dumpsys') {
        return @('Transports: VPN Capabilities: INTERNET Uid: 10073 EstablishingAppUid: 10073')
    }
    if ($Arguments[2] -eq 'reverse' -and $Arguments[3] -ne '--list') { $endpointDenied.ReverseCommands++ }
    if ($Arguments[2] -eq 'reverse' -and $Arguments[3] -eq '--list') { return @() }
}.GetNewClosure()
try {
    Wait-SearchLocalForwardingStable -Device '127.0.0.1:21503' `
        -Package 'br.com.tudoaquimacacu.tudo_aqui_macacu.searchlocal' -InvokeAdb $denyEndpointAdb `
        -VerifyLocalEndpoints { return $false } -TimeoutSeconds 1 `
        -StableChecks 1 -PollMilliseconds 10 | Out-Null
    throw 'Expected the routine to block when local demo endpoints are unavailable.'
} catch {
    if ($_.Exception.Message -notmatch 'local demo endpoint') { throw }
}
Assert-Equal 0 $endpointDenied.ReverseCommands 'No mapping may be created if local demo endpoints are unavailable.'
Write-Output 'PASS: unavailable local endpoints block all ADB reverse changes.'

$launcher = Get-Content (Join-Path $PSScriptRoot 'start-search-local.ps1') -Raw
$gateStart = $launcher.IndexOf('SearchLocalGateActivity', [StringComparison]::Ordinal)
$vpnReady = $launcher.IndexOf('if (!$ready)', [StringComparison]::Ordinal)
$stableForwarding = $launcher.IndexOf('Wait-SearchLocalForwardingStable', [StringComparison]::Ordinal)
if ($gateStart -lt 0 -or $vpnReady -lt $gateStart -or $stableForwarding -lt $vpnReady) {
    throw 'The launcher must start the protected gate, confirm VPN readiness, then stabilize ADB forwarding.'
}
$preGate = $launcher.Substring(0, $gateStart)
if ($preGate -match 'TcpClient|\.Connect\(|Set-LocalReverse\s+\$port') {
    throw 'The launcher must not access Emulator endpoints or create ADB reverse mappings before the protected gate confirms VPN isolation.'
}
if ($launcher.IndexOf('$verifyLocalEndpoints', [StringComparison]::Ordinal) -lt $vpnReady) {
    throw 'Local Emulator endpoints must be verified only after VPN readiness.'
}
if ($launcher -match 'Wait-LocalDevice|WaitForDevice|\$verifyVpnIsolation\s*=') {
    throw 'Launcher must not retain implicit device/VPN function callbacks.'
}
if ([regex]::Matches($launcher, '\.GetNewClosure\(\)').Count -ne 1) {
    throw 'Only the ADB executable adapter may use GetNewClosure in the launcher.'
}
$adbAdapterStart = $launcher.IndexOf('$invokeAdb = {', [StringComparison]::Ordinal)
$adbAdapterEnd = $launcher.IndexOf('}.GetNewClosure()', $adbAdapterStart, [StringComparison]::Ordinal)
if ($adbAdapterStart -lt 0 -or $adbAdapterEnd -lt 0 -or
    $launcher.Substring($adbAdapterStart, $adbAdapterEnd - $adbAdapterStart) -match '\b(Wait|Invoke|Test)-SearchLocal') {
    throw 'The closed ADB adapter must capture values only and must not resolve helper functions.'
}
if (-not $launcher.Contains('$socket.Connect(''127.0.0.1'', $port)') -or
    $launcher -notmatch '\$forwardPorts = @\(9097, 8087, 5007\)' -or
    $launcher -notmatch '\$forwardPorts \+= 9197' -or
    $launcher -notmatch '\[switch\]\$AuthHttpDiagnosticsProxy' -or
    $launcher -notmatch 'Test-SearchLocalDiagnosticProxyIdentity' -or
    $launcher -notmatch '-Package \$package') {
    throw 'Launcher must keep default reverse ports and verify the explicit diagnostic proxy before adding 9197.'
}
if ($launcher -notmatch '\$verifyLocalEndpoints\s*=\s*\{\s*param\(\[int\[\]\]\$Ports\)' -or
    $launcher -notmatch '-Ports \$forwardPorts') {
    throw 'Diagnostic mode must pass the exact endpoints through the recovery helper for stable checks.'
}
$demoLauncher = Get-Content (Join-Path $PSScriptRoot 'start-search-local-demo.ps1') -Raw
if ($demoLauncher -notmatch '\[switch\]\$AuthHttpDiagnosticsProxy' -or
    $demoLauncher -notmatch 'LOCAL_AUTH_HTTP_DIAGNOSTICS=true' -or
    $demoLauncher -notmatch '\$reversePorts \+= 9197') {
    throw 'Demo bootstrap must expose diagnostics only through the explicit opt-in and configure the proxy reverse port.'
}
$proxyStarter = Get-Content (Join-Path $PSScriptRoot 'start-auth-emulator-diagnostic-proxy.ps1') -Raw
if ($proxyStarter -notmatch 'firebase\.search-emulator\.json' -or
    $proxyStarter -notmatch 'demo-universal-search' -or
    $proxyStarter -notmatch '127\.0\.0\.1' -or
    $proxyStarter -notmatch 'LocalPort 9197' -or
    $proxyStarter -notmatch 'auth-emulator-diagnostic-proxy\.cjs') {
    throw 'Proxy starter must verify the existing demo Emulator and bind only the local diagnostic proxy.'
}
$gatePath = Join-Path $PSScriptRoot '../android/app/src/searchLocal/kotlin/br/com/tudoaquimacacu/tudo_aqui_macacu/SearchLocalGateActivity.kt'
$gate = Get-Content $gatePath -Raw
if ($launcher -notmatch "'--ez', 'authHttpDiagnosticsProxy', 'true'" -or
    $gate -notmatch 'getBooleanExtra\("authHttpDiagnosticsProxy", false\)' -or
    $gate -notmatch 'listOf\(9097, 8087, 5007, 9197\)' -or
    $gate -notmatch 'requiredPorts\.all') {
    throw 'The Android isolation gate must wait for port 9197 only under the explicit diagnostic opt-in.'
}
Write-Output 'PASS: launcher waits for VPN readiness before creating ADB reverse mappings.'

$readState = [pscustomobject]@{ ReadyChecks = 0; ReadAttempts = 0; Transport = 70 }
$readAdb = {
    param($Arguments)
    if ($Arguments[0] -eq 'devices') {
        $readState.ReadyChecks++
        if ($readState.ReadyChecks -eq 2) { $readState.Transport = 71 }
        return @("127.0.0.1:21503 device transport_id:$($readState.Transport)")
    }
    if ($Arguments[0] -eq 'connect') { return @('connected') }
    $readState.ReadAttempts++
    if ($readState.ReadAttempts -eq 1) { throw 'ADB_TRANSPORT_UNAVAILABLE: device not found' }
    return @('/data/app/searchLocal/base.apk')
}.GetNewClosure()
$path = Invoke-SearchLocalAdbRead -Device '127.0.0.1:21503' `
    -Arguments @('shell', 'pm', 'path', 'br.com.tudoaquimacacu.tudo_aqui_macacu.searchlocal') `
    -Operation 'package path lookup' -InvokeAdb $readAdb `
    -MaxAttempts 2 -ReconnectWaitSeconds 2
Assert-Equal '/data/app/searchLocal/base.apk' $path 'A package path read should recover after a transient ADB disconnect.'
Assert-Equal 71 $readState.Transport 'The simulated device should return on a new transport.'
Assert-Equal 2 $readState.ReadAttempts 'The read should be retried once after reconnection.'
Assert-Equal 2 $readState.ReadyChecks 'The device should be revalidated after the transport failure.'
Write-Output 'PASS: pm path read waits for the serial after reconnect and does not rely on a transport ID.'

$timeoutState = [pscustomobject]@{ ReadyChecks = 0; ReadAttempts = 0 }
$timeoutAdb = {
    param($Arguments)
    if ($Arguments[0] -eq 'devices') {
        $timeoutState.ReadyChecks++
        if ($timeoutState.ReadyChecks -eq 1) { return @('127.0.0.1:21503 device transport_id:75') }
        return @('List of devices attached')
    }
    if ($Arguments[0] -eq 'connect') { return @('unable to connect') }
    $timeoutState.ReadAttempts++
    throw 'ADB_TRANSPORT_UNAVAILABLE: device not found'
}.GetNewClosure()
try {
    Invoke-SearchLocalAdbRead -Device '127.0.0.1:21503' `
        -Arguments @('shell', 'pm', 'path', 'br.com.tudoaquimacacu.tudo_aqui_macacu.searchlocal') `
        -Operation 'package path lookup' -InvokeAdb $timeoutAdb `
        -MaxAttempts 2 -ReconnectWaitSeconds 1 | Out-Null
    throw 'Expected an informative failure when the device does not return.'
} catch {
    if ($_.Exception.Message -notmatch 'MEmu remained unavailable.*package path lookup') { throw }
}
Assert-Equal 1 $timeoutState.ReadAttempts 'A timed-out reconnect must not repeat the package lookup.'
if ($timeoutState.ReadyChecks -lt 2 -or $timeoutState.ReadyChecks -gt 5) {
    throw "Reconnect waiting must poll the serial within its bounded interval (checks: $($timeoutState.ReadyChecks))."
}
Write-Output 'PASS: package lookup stops clearly when MEmu does not return within the bounded wait.'
