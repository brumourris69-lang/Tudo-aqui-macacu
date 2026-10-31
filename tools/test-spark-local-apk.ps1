param([Parameter(Mandatory = $true)][string]$Apk)
$ErrorActionPreference = 'Stop'
$aapt = Join-Path $env:LOCALAPPDATA 'Android/Sdk/build-tools/36.0.0/aapt.exe'
if (!(Test-Path -LiteralPath $Apk) -or !(Test-Path -LiteralPath $aapt)) {
    throw 'APK Spark local ou inspetor Android existente não encontrado.'
}
$manifest = (& $aapt dump xmltree $Apk AndroidManifest.xml) -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'Não foi possível inspecionar o manifesto Spark local.' }
$resources = (& $aapt dump resources $Apk) -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'Não foi possível inspecionar os recursos Spark local.' }
$badging = (& $aapt dump badging $Apk) -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'Não foi possível inspecionar o pacote Spark local.' }

foreach ($required in @(
    "package: name='br.com.tudoaquimacacu.tudo_aqui_macacu.sparklocal'",
    'SearchLocalApplication', 'SearchLocalGateActivity', 'SearchLocalVpnService',
    'android.net.VpnService', 'android.intent.action.MAIN', 'android.intent.action.VIEW',
    'tudoaqui', 'firebase_messaging_auto_init_enabled',
    'firebase_data_collection_default_enabled')) {
    if (!$manifest.Contains($required) -and !$badging.Contains($required)) {
        throw "Configuração ausente no APK Spark local: $required"
    }
}
foreach ($forbidden in @(
    'FirebaseInitProvider', 'FlutterFirebaseMessagingInitProvider',
    'FlutterFirebaseMessagingService', 'FirebaseInstanceIdReceiver',
    'google_app_id', 'google_api_key', 'default_web_client_id',
    'macacu-beta-', 'tudo-aqui-macacu')) {
    if ($manifest.Contains($forbidden) -or $resources.Contains($forbidden)) {
        throw "APK Spark local contém configuração Firebase hospedada: $forbidden"
    }
}
foreach ($key in @('firebase_messaging_auto_init_enabled',
    'firebase_analytics_collection_enabled', 'firebase_crashlytics_collection_enabled',
    'firebase_data_collection_default_enabled')) {
    if ($manifest -notmatch ("(?s)" + [regex]::Escape($key) + "(?:(?!\n\s*E:).)*?android:value[^\r\n]*0x0\b")) {
        throw "Coleta não desativada no APK Spark local: $key"
    }
}
if ($manifest -notmatch 'android:debuggable[^\r\n]*0xffffffff') {
    throw 'A variante Spark local precisa ser somente debug.'
}
$mainStart = $manifest.IndexOf('br.com.tudoaquimacacu.tudo_aqui_macacu.MainActivity')
$gateStart = $manifest.IndexOf('br.com.tudoaquimacacu.tudo_aqui_macacu.SearchLocalGateActivity')
if ($mainStart -lt 0 -or $gateStart -le $mainStart) {
    throw 'Gate e Activity Flutter não foram identificadas no APK.'
}
$main = $manifest.Substring($mainStart, $gateStart - $mainStart)
$gateEnd = $manifest.IndexOf("`n        E: service", $gateStart)
if ($gateEnd -lt $gateStart) { $gateEnd = $manifest.Length }
$gate = $manifest.Substring($gateStart, $gateEnd - $gateStart)
if ($main -match 'android:exported[^\r\n]*0xffffffff' -or $main.Contains('android.intent.action.VIEW')) {
    throw 'A MainActivity não pode contornar o Gate VPN.'
}
if ($gate -notmatch 'android:exported[^\r\n]*0xffffffff' -or
    !$gate.Contains('android.intent.action.VIEW') -or !$gate.Contains('android.intent.action.MAIN')) {
    throw 'O Gate deve ser a única entrada pública do APK.'
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $Apk).Path)
try {
    $font = $archive.GetEntry('assets/flutter_assets/assets/fonts/local-poppins/Poppins-Regular.ttf')
    if (!$font -or $font.Length -le 0) { throw 'Fonte local Poppins ausente no APK.' }
} finally { $archive.Dispose() }
Write-Output 'APK Spark local aprovado: demo-only source mode, VPN gate required, no hosted Firebase resources/providers, no Functions endpoint or production OAuth.'
