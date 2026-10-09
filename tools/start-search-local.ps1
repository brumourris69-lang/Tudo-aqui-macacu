param([string]$Device = '127.0.0.1:21503', [switch]$SkipInstall)
$ErrorActionPreference = 'Stop'
$adb = Join-Path $env:LOCALAPPDATA 'Android/Sdk/platform-tools/adb.exe'
$package = 'br.com.tudoaquimacacu.tudo_aqui_macacu.searchlocal'
function Wait-LocalDevice {
    for ($retry = 0; $retry -lt 30; $retry++) {
        $state = & $adb -s $Device get-state 2>$null
        if ($LASTEXITCODE -eq 0 -and $state -eq 'device') { return }
        & $adb connect $Device | Out-Null
        Start-Sleep -Milliseconds 300
    }
    throw 'Android emulator disconnected; no Flutter startup.'
}
function Set-LocalReverse([int]$Port) {
    for ($retry = 0; $retry -lt 10; $retry++) {
        Wait-LocalDevice
        & $adb -s $Device reverse "tcp:$Port" "tcp:$Port" 2>$null
        if ($LASTEXITCODE -eq 0) { return }
        Start-Sleep -Milliseconds 300
    }
    throw 'Local port forwarding failed; no production fallback.'
}
Wait-LocalDevice
& $adb -s $Device shell am force-stop $package
if ($LASTEXITCODE -ne 0) { throw 'Could not stop the local test package.' }
# Await removal of this app's old tunnel so readiness cannot match stale state.
for ($retry = 0; $retry -lt 20; $retry++) {
    $oldNetwork = (& $adb -s $Device shell dumpsys connectivity) -join "`n"
    if (!$oldNetwork.Contains('InterfaceName: tun0')) { break }
    Start-Sleep -Milliseconds 300
}
Wait-LocalDevice
foreach ($port in @(9097, 8087, 5007)) {
    $socket = [Net.Sockets.TcpClient]::new()
    try { $socket.Connect('127.0.0.1', $port) } finally { $socket.Dispose() }
}
& "$PSScriptRoot/test-search-local-apk.ps1"
if (!$SkipInstall) {
    & $adb -s $Device install --no-streaming -r build/app/outputs/flutter-apk/app-searchlocal-debug.apk
    if ($LASTEXITCODE -ne 0) { throw 'Debug install failed.' }
} else {
    $installedPath = ((& $adb -s $Device shell pm path $package) -join '').Trim().Replace('package:', '')
    if ($installedPath -notmatch '^/data/app/[A-Za-z0-9._=/-]+/base.apk$') { throw 'Unexpected installed APK path.' }
    $installedHash = ((& $adb -s $Device shell sha256sum $installedPath) -join '').Split(' ')[0]
    $builtHash = (Get-FileHash 'build/app/outputs/flutter-apk/app-searchlocal-debug.apk' -Algorithm SHA256).Hash
    if ($installedHash.ToUpperInvariant() -ne $builtHash) { throw 'Installed APK differs from verified debug build.' }
}
Wait-LocalDevice
foreach ($port in @(9097, 8087, 5007)) {
    Set-LocalReverse $port
}
$reverse = (& $adb -s $Device reverse --list) -join "`n"
foreach ($port in @(9097, 8087, 5007)) {
    if (!$reverse.Contains("tcp:$port tcp:$port")) { throw 'Missing emulator forwarding. App not started.' }
}
# Authorizes only this test package to create its non-forwarding VPN.
# Android's gate still refuses Flutter initialization unless the VPN is active.
& $adb -s $Device shell appops set $package ACTIVATE_VPN allow
if ($LASTEXITCODE -ne 0) { throw 'VPN authorization failed. App not started.' }
& $adb -s $Device shell am start -n "$package/br.com.tudoaquimacacu.tudo_aqui_macacu.SearchLocalGateActivity"
if ($LASTEXITCODE -ne 0) { throw 'Local gate failed to start.' }
# MEmu can reset reverse mappings when its VPN network is created.
# The native gate does not start Flutter until these TCP endpoints are ready.
$ready = $false
for ($attempt = 0; $attempt -lt 30; $attempt++) {
    Wait-LocalDevice
    $network = (& $adb -s $Device shell dumpsys connectivity) -join "`n"
    if ($network.Contains('InterfaceName: tun0')) { $ready = $true; break }
    Start-Sleep -Milliseconds 500
}
if (!$ready) { throw 'VPN unavailable; native gate must keep Flutter stopped.' }
for ($settle = 0; $settle -lt 5; $settle++) {
    foreach ($port in @(9097, 8087, 5007)) { Set-LocalReverse $port }
    Start-Sleep -Milliseconds 400
}
