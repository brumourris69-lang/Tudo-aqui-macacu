param(
    [string]$Flutter = 'C:\Users\tiago\Documents\Codex\2026-09-10\https-github-com-brumourris69-lang-tudo\work\flutter\bin\flutter.bat',
    [string]$Python = 'C:\Users\tiago\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
)
$ErrorActionPreference = 'Stop'
$appRoot = (Resolve-Path "$PSScriptRoot/..").Path
$device = '127.0.0.1:21503'
$adb = Join-Path $env:LOCALAPPDATA 'Android/Sdk/platform-tools/adb.exe'
$package = 'br.com.tudoaquimacacu.tudo_aqui_macacu.searchlocal'
foreach ($port in @(9097,8087,5007)) {
    $socket = [Net.Sockets.TcpClient]::new()
    try { $socket.Connect('127.0.0.1', $port) } finally { $socket.Dispose() }
}
& "$PSScriptRoot/test-search-local-apk.ps1"
# Reading the already-running local process does not restart or stop its VPN.
$vmUriText = & $Python "$PSScriptRoot/read-search-local-vm-uri.py"
if ($LASTEXITCODE -ne 0 -or !$vmUriText) { throw 'Local debug URI unavailable.' }
$vmUri = [uri]$vmUriText.Trim()
$hostPort = & $adb -s $device forward tcp:0 "tcp:$($vmUri.Port)"
if ($LASTEXITCODE -ne 0) { throw 'Loopback debugger forwarding failed.' }
$hostUri = "http://127.0.0.1:$hostPort$($vmUri.AbsolutePath)"
$vm = Invoke-RestMethod "${hostUri}getVM" -TimeoutSec 5
$localPid = (& $adb -s $device shell pidof $package).Trim()
if ($vm.result.pid.ToString() -ne $localPid) { throw 'Debugger PID differs from local package.' }
if ((Get-NetTCPConnection -State Listen -LocalPort $hostPort).LocalAddress -ne '127.0.0.1') {
    throw 'Debugger must listen on host loopback only.'
}

# Flutter attach has no --flavor option. Keep its asset bundle and Dart flavor
# identical to the APK through a disposable project manifest, not production's
# pubspec. Sources and entry point remain the original files for Hot Reload.
$sessionRoot = Join-Path (Split-Path $appRoot) 'work/search-local-debug-session'
New-Item -ItemType Directory -Path "$sessionRoot/.dart_tool" -Force | Out-Null
$manifest = Get-Content "$appRoot/pubspec.yaml" -Raw
if ($manifest -match '(?m)^  default-flavor:') { throw 'Unexpected default flavor in source manifest.' }
$manifest = [regex]::Replace($manifest, '(?m)^flutter:\s*$', "flutter:`n  default-flavor: searchLocal")
Set-Content -LiteralPath "$sessionRoot/pubspec.yaml" -Value $manifest -Encoding utf8
foreach ($file in @('pubspec.lock','.metadata','.flutter-plugins-dependencies')) {
    if (Test-Path "$appRoot/$file") { Copy-Item -LiteralPath "$appRoot/$file" -Destination "$sessionRoot/$file" -Force }
}
$config = Get-Content "$appRoot/.dart_tool/package_config.json" -Raw | ConvertFrom-Json
$configBase = [uri]::new(($appRoot.Replace('\','/') + '/.dart_tool/'))
foreach ($entry in $config.packages) { $entry.rootUri = [uri]::new($configBase, $entry.rootUri).AbsoluteUri }
($config.packages | Where-Object name -eq 'tudo_aqui_macacu').rootUri = [uri]::new($sessionRoot.Replace('\','/') + '/').AbsoluteUri
$config | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath "$sessionRoot/.dart_tool/package_config.json" -Encoding utf8
Copy-Item -LiteralPath "$appRoot/.dart_tool/package_graph.json" -Destination "$sessionRoot/.dart_tool/package_graph.json" -Force
foreach ($directory in @('lib','assets','android')) {
    $link = "$sessionRoot/$directory"
    if (!(Test-Path $link)) { New-Item -ItemType Junction -Path $link -Target "$appRoot/$directory" | Out-Null }
    if ((Get-Item -LiteralPath $link).Target -ne "$appRoot/$directory") {
        # Windows may canonicalize separators. Verify the resolved junction target.
        if (((Get-Item -LiteralPath $link).Target -replace '/', '\') -ne "$appRoot\$directory") {
            throw 'Unexpected debugger junction target.'
        }
    }
}
Write-Output 'Attaching to the existing isolated demo process; VPN and VM authentication retained.'
Push-Location $sessionRoot
try {
    & $Flutter --suppress-analytics attach -d $device --app-id $package --no-dds `
        --debug-url $vmUriText.Trim() --host-vmservice-port $hostPort `
        --target "$appRoot/lib/main.dart" `
        --dart-define=LOCAL_SEARCH_EMULATORS=true `
        --dart-define=LOCAL_SEARCH_PROJECT=demo-universal-search `
        --dart-define=LOCAL_SEARCH_HOST=127.0.0.1
} finally {
    Pop-Location
    & $adb -s $device forward --remove "tcp:$hostPort" 2>$null | Out-Null
}
