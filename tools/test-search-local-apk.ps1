param([string]$Apk = 'build/app/outputs/flutter-apk/app-searchlocal-debug.apk')
$ErrorActionPreference = 'Stop'
$aapt = Join-Path $env:LOCALAPPDATA 'Android/Sdk/build-tools/36.0.0/aapt.exe'
$manifest = (& $aapt dump xmltree $Apk AndroidManifest.xml) -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect APK manifest.' }
$resources = (& $aapt dump resources $Apk) -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect APK resources.' }
foreach ($required in @('br.com.tudoaquimacacu.tudo_aqui_macacu.searchlocal',
    'SearchLocalApplication', 'SearchLocalGateActivity', 'SearchLocalVpnService', 'firebase_messaging_auto_init_enabled',
    'firebase_data_collection_default_enabled')) {
    if (!$manifest.Contains($required)) { throw "Missing local manifest setting: $required" }
}
foreach ($forbidden in @('FirebaseInitProvider', 'FlutterFirebaseMessagingInitProvider',
    'FlutterFirebaseMessagingService', 'FirebaseInstanceIdReceiver')) {
    if ($manifest.Contains($forbidden)) { throw "Forbidden native component: $forbidden" }
}
foreach ($forbidden in @('google_app_id', 'google_api_key', 'default_web_client_id', 'tudo-aqui-macacu')) {
    if ($resources.Contains($forbidden)) { throw "Production resource found: $forbidden" }
}
foreach ($key in @('firebase_messaging_auto_init_enabled',
    'firebase_analytics_collection_enabled', 'firebase_crashlytics_collection_enabled',
    'firebase_data_collection_default_enabled')) {
    if ($manifest -notmatch ("(?s)" + [regex]::Escape($key) + "(?:(?!\n\s*E:).)*?android:value[^\r\n]*0x0\b")) {
        throw "Collection not disabled: $key"
    }
}
if ($manifest -notmatch 'android:debuggable[^\r\n]*0xffffffff') { throw 'Not a debug APK.' }
Write-Output 'APK checks passed: exclusive ID, debug, no native Firebase/FCM provider, no production Google resources, collection disabled.'
