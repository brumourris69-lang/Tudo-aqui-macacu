param([Parameter(Mandatory)][string]$Out)
$ErrorActionPreference = 'Stop'
$python = 'C:\Users\tiago\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$adb = Join-Path $env:LOCALAPPDATA 'Android/Sdk/platform-tools/adb.exe'
$device = '127.0.0.1:21503'
$uriText = & $python "$PSScriptRoot/read-search-local-vm-uri.py"
if ($LASTEXITCODE -ne 0 -or !$uriText) { throw 'Isolated local VM unavailable.' }
$uri = [uri]$uriText.Trim()
$port = & $adb -s $device forward tcp:0 "tcp:$($uri.Port)"
if ($LASTEXITCODE -ne 0) { throw 'Local screenshot forwarding failed.' }
try {
    if ((Get-NetTCPConnection -State Listen -LocalPort $port).LocalAddress -ne '127.0.0.1') {
        throw 'Screenshot service must use loopback only.'
    }
    $base = "http://127.0.0.1:$port$($uri.AbsolutePath)"
    $vm = Invoke-RestMethod "${base}getVM" -TimeoutSec 5
    $localPid = (& $adb -s $device shell pidof 'br.com.tudoaquimacacu.tudo_aqui_macacu.searchlocal').Trim()
    if ($vm.result.pid.ToString() -ne $localPid) { throw 'Unexpected screenshot process.' }
    $capture = Invoke-RestMethod "${base}_flutter.screenshot" -TimeoutSec 10
    if ($capture.error -or !$capture.result.screenshot) { throw 'Flutter engine screenshot unavailable.' }
    $bytes = [Convert]::FromBase64String($capture.result.screenshot)
    if ([BitConverter]::ToString($bytes[0..7]) -ne '89-50-4E-47-0D-0A-1A-0A') { throw 'Invalid PNG response.' }
    $path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Out)
    [IO.File]::WriteAllBytes($path, $bytes)
    Write-Output "Local Flutter PNG saved ($($bytes.Length) bytes): $path"
} finally {
    & $adb -s $device forward --remove "tcp:$port" 2>$null | Out-Null
}
