param(
    [string]$Device = '127.0.0.1:21503',
    [switch]$SkipInstall,
    [switch]$AuthHttpDiagnosticsProxy
)
$ErrorActionPreference = 'Stop'
$adb = Join-Path $env:LOCALAPPDATA 'Android/Sdk/platform-tools/adb.exe'
$package = 'br.com.tudoaquimacacu.tudo_aqui_macacu.searchlocal'
. (Join-Path $PSScriptRoot 'search-local-adb-reverse.ps1')
$forwardPorts = @(9097, 8087, 5007)
if ($AuthHttpDiagnosticsProxy) {
    $proxyListeners = @(Get-NetTCPConnection -State Listen -LocalAddress '127.0.0.1' `
        -LocalPort 9197 -ErrorAction SilentlyContinue)
    $proxyReady = $false
    foreach ($listener in $proxyListeners) {
        $owner = Get-CimInstance Win32_Process -Filter "ProcessId = $($listener.OwningProcess)" `
            -ErrorAction SilentlyContinue
        if ($owner -and (Test-SearchLocalDiagnosticProxyIdentity `
                -CommandLine ([string]$owner.CommandLine) `
            -ProcessName ([string]$owner.Name) `
                -ListeningAddress ([string]$listener.LocalAddress) `
                -Port ([int]$listener.LocalPort))) {
            $proxyReady = $true
            break
        }
    }
    if (-not $proxyReady) {
        throw 'Auth diagnostics requested, but the demo-only loopback proxy is not verified on port 9197.'
    }
    $forwardPorts += 9197
}
$invokeAdb = {
    param($Arguments)
    $output = & $adb @Arguments 2>&1
    if ($LASTEXITCODE -eq 0) { return $output }
    $errorText = $output -join "`n"
    if ($errorText -match '(?i)device .*not found|device offline|no devices/emulators found|connection reset|protocol fault|closed') {
        throw 'ADB_TRANSPORT_UNAVAILABLE: the selected MEmu transport disconnected.'
    }
    throw 'ADB_READ_FAILED: the local device command failed.'
}.GetNewClosure()

Wait-SearchLocalDevice -Device $Device -InvokeAdb $invokeAdb
& $adb -s $Device shell am force-stop $package
if ($LASTEXITCODE -ne 0) { throw 'Could not stop the local test package.' }
# Await removal of this app's old tunnel so readiness cannot match stale state.
$oldTunnelDeadline = [DateTime]::UtcNow.AddSeconds(8)
while ([DateTime]::UtcNow -lt $oldTunnelDeadline) {
    $oldNetwork = (Invoke-SearchLocalAdbRead -Device $Device `
        -Arguments @('shell', 'dumpsys', 'connectivity') `
        -Operation 'previous VPN shutdown check' -InvokeAdb $invokeAdb `
        -MaxAttempts 2 -ReconnectWaitSeconds 4) -join "`n"
    if (!$oldNetwork.Contains('InterfaceName: tun0')) { break }
    Start-Sleep -Milliseconds 300
}
Wait-SearchLocalDevice -Device $Device -InvokeAdb $invokeAdb
& "$PSScriptRoot/test-search-local-apk.ps1"
if (!$SkipInstall) {
    & $adb -s $Device install --no-streaming -r -d build/app/outputs/flutter-apk/app-searchlocal-debug.apk
    if ($LASTEXITCODE -ne 0) { throw 'Debug install failed.' }
} else {
    $installedPath = (Invoke-SearchLocalAdbRead -Device $Device `
        -Arguments @('shell', 'pm', 'path', $package) `
        -Operation 'package path lookup' -InvokeAdb $invokeAdb `
        -MaxAttempts 2 -ReconnectWaitSeconds 8) -join ''
    $installedPath = $installedPath.Trim().Replace('package:', '')
    if ($installedPath -notmatch '^/data/app/[A-Za-z0-9._=/-]+/base.apk$') { throw 'Unexpected installed APK path.' }
    $installedHash = ((Invoke-SearchLocalAdbRead -Device $Device `
        -Arguments @('shell', 'sha256sum', $installedPath) `
        -Operation 'installed APK hash check' -InvokeAdb $invokeAdb `
        -MaxAttempts 2 -ReconnectWaitSeconds 8) -join '').Split(' ')[0]
    $builtHash = (Get-FileHash 'build/app/outputs/flutter-apk/app-searchlocal-debug.apk' -Algorithm SHA256).Hash
    if ($installedHash.ToUpperInvariant() -ne $builtHash) { throw 'Installed APK differs from verified debug build.' }
}
Wait-SearchLocalDevice -Device $Device -InvokeAdb $invokeAdb
# Authorizes only this test package to create its non-forwarding VPN.
# Android's gate still refuses Flutter initialization unless the VPN is active.
& $adb -s $Device shell appops set $package ACTIVATE_VPN allow
if ($LASTEXITCODE -ne 0) { throw 'VPN authorization failed. App not started.' }
Wait-SearchLocalDevice -Device $Device -InvokeAdb $invokeAdb
$gateArguments = @('-s', $Device, 'shell', 'am', 'start', '-n',
    "$package/br.com.tudoaquimacacu.tudo_aqui_macacu.SearchLocalGateActivity")
if ($AuthHttpDiagnosticsProxy) {
    $gateArguments += @('--ez', 'authHttpDiagnosticsProxy', 'true')
}
& $adb @gateArguments
if ($LASTEXITCODE -ne 0) { throw 'Local gate failed to start.' }
# MEmu can reset reverse mappings when its VPN network is created.
# The native gate does not start Flutter until these TCP endpoints are ready.
$ready = $false
$gateDeadline = [DateTime]::UtcNow.AddSeconds(30)
while ([DateTime]::UtcNow -lt $gateDeadline) {
    if (-not (Wait-SearchLocalDevice -Device $Device -InvokeAdb $invokeAdb `
            -TimeoutSeconds 2 -Quiet)) {
        Start-Sleep -Milliseconds 500
        continue
    }
    $network = (Invoke-SearchLocalAdbRead -Device $Device `
        -Arguments @('shell', 'dumpsys', 'connectivity') `
        -Operation 'VPN readiness check' -InvokeAdb $invokeAdb `
        -MaxAttempts 2 -ReconnectWaitSeconds 3) -join "`n"
    if ($network.Contains('InterfaceName: tun0')) { $ready = $true; break }
    Start-Sleep -Milliseconds 500
}
if (!$ready) { throw 'VPN unavailable; native gate must keep Flutter stopped.' }
$verifyLocalEndpoints = {
    param([int[]]$Ports)
    foreach ($port in $Ports) {
        $socket = [Net.Sockets.TcpClient]::new()
        try { $socket.Connect('127.0.0.1', $port) } catch { return $false }
        finally { $socket.Dispose() }
    }
    return $true
}
Wait-SearchLocalDevice -Device $Device -InvokeAdb $invokeAdb
$forwarding = Wait-SearchLocalForwardingStable `
    -Device $Device `
    -Package $package `
    -InvokeAdb $invokeAdb `
    -VerifyLocalEndpoints $verifyLocalEndpoints `
    -Ports $forwardPorts `
    -TimeoutSeconds 24 `
    -StableChecks 3 `
    -PollMilliseconds 1000
Write-Host "ADB reverse stable: device=$($forwarding.Device), checks=$($forwarding.StableChecks), reconnections=$($forwarding.ReconnectsDetected)."
