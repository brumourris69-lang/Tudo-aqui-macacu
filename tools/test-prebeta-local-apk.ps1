param([string]$Apk = 'build/app/outputs/flutter-apk/app-prebetalocal-debug.apk')
$ErrorActionPreference = 'Stop'
$aapt = Join-Path $env:LOCALAPPDATA 'Android/Sdk/build-tools/36.0.0/aapt.exe'
if (!(Test-Path -LiteralPath $Apk) -or !(Test-Path -LiteralPath $aapt)) {
    throw 'The pre-Beta APK or Android manifest inspector is missing.'
}
$manifest = (& $aapt dump xmltree $Apk AndroidManifest.xml) -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect pre-Beta APK manifest.' }
$resources = (& $aapt dump resources $Apk) -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect pre-Beta APK resources.' }
$badging = (& $aapt dump badging $Apk) -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect pre-Beta APK package.' }

foreach ($required in @(
    "package: name='br.com.tudoaquimacacu.tudo_aqui_macacu.prebeta'",
    'SearchLocalApplication', 'SearchLocalGateActivity', 'SearchLocalVpnService',
    'android.permission.POST_NOTIFICATIONS', 'android.permission.RECEIVE_BOOT_COMPLETED',
    'android.permission.FOREGROUND_SERVICE_SPECIAL_USE', 'android.net.VpnService',
    'android.intent.action.VIEW', 'tudoaqui', 'content',
    'firebase_messaging_auto_init_enabled', 'firebase_data_collection_default_enabled')) {
    if (!$manifest.Contains($required) -and !$badging.Contains($required)) {
        throw "Missing required isolated test APK setting: $required"
    }
}
foreach ($forbidden in @(
    'FirebaseInitProvider', 'FlutterFirebaseMessagingInitProvider',
    'FlutterFirebaseMessagingService', 'FirebaseInstanceIdReceiver',
    'google_app_id', 'google_api_key', 'default_web_client_id', 'tudo-aqui-macacu')) {
    if ($manifest.Contains($forbidden) -or $resources.Contains($forbidden)) {
        throw "Forbidden Firebase/production component or resource found in pre-Beta APK: $forbidden"
    }
}
foreach ($key in @('firebase_messaging_auto_init_enabled',
    'firebase_analytics_collection_enabled', 'firebase_crashlytics_collection_enabled',
    'firebase_data_collection_default_enabled')) {
    if ($manifest -notmatch ("(?s)" + [regex]::Escape($key) + "(?:(?!\n\s*E:).)*?android:value[^\r\n]*0x0\b")) {
        throw "Collection not disabled in pre-Beta APK: $key"
    }
}
if ($manifest -notmatch 'android:debuggable[^\r\n]*0xffffffff') {
    throw 'Pre-Beta local APK must be debug-only.'
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$apkArchive = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $Apk).Path)
try {
    $fontEntry = $apkArchive.GetEntry('assets/flutter_assets/assets/fonts/local-poppins/Poppins-Regular.ttf')
    if (!$fontEntry -or $fontEntry.Length -le 0) {
        throw 'Pre-Beta local APK must bundle Poppins-Regular because external font fetching is disabled.'
    }
} finally {
    $apkArchive.Dispose()
}

$mainStart = $manifest.IndexOf('br.com.tudoaquimacacu.tudo_aqui_macacu.MainActivity')
$gateStart = $manifest.IndexOf('br.com.tudoaquimacacu.tudo_aqui_macacu.SearchLocalGateActivity')
if ($mainStart -lt 0 -or $gateStart -lt 0 -or $gateStart -le $mainStart) {
    throw 'Could not identify isolated Gate and Flutter activity declarations.'
}
$mainBlock = $manifest.Substring($mainStart, $gateStart - $mainStart)
$gateEnd = $manifest.IndexOf("`n        E: service", $gateStart)
if ($gateEnd -lt $gateStart) { $gateEnd = $manifest.Length }
$gateBlock = $manifest.Substring($gateStart, $gateEnd - $gateStart)
if ($mainBlock -match 'android:exported[^\r\n]*0xffffffff' -or $mainBlock.Contains('android.intent.action.VIEW')) {
    throw 'Flutter MainActivity must remain private; incoming links must pass through the VPN Gate.'
}
if ($gateBlock -notmatch 'android:exported[^\r\n]*0xffffffff' -or
    !$gateBlock.Contains('android.intent.action.VIEW') -or
    !$gateBlock.Contains('android.intent.action.MAIN')) {
    throw 'Exported Gate must be the only launcher and VIEW intent entry point.'
}

Write-Output 'APK checks passed: dedicated debug package, Firebase resources/providers absent, collections disabled, VPN Gate is the only exported launcher/link target, notifications and boot receiver are present, offline Poppins font is bundled.'
