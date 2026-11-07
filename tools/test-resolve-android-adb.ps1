$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'resolve-android-adb.ps1')

function Assert-Equal {
    param([string]$Expected, [string]$Actual, [string]$Message)
    if (![string]::Equals($Expected, $Actual, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Message Expected '$Expected'; got '$Actual'."
    }
}

function Assert-Throws {
    param([scriptblock]$Action, [string]$Message)
    try { & $Action | Out-Null } catch { return }
    throw $Message
}

$allowedParent = [IO.Path]::GetFullPath((Join-Path $env:USERPROFILE 'Documents\Codex'))
$testRoot = Join-Path $allowedParent ("_adb_resolver_test_" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
try {
    function New-TestSdk([string]$Root, [bool]$IncludeAdb = $true) {
        $platformTools = Join-Path $Root 'platform-tools'
        New-Item -ItemType Directory -Path $platformTools -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $platformTools 'source.properties') -Value "Pkg.Revision=37.0.1`n"
        if ($IncludeAdb) { Set-Content -LiteralPath (Join-Path $platformTools 'adb.exe') -Value 'test-only placeholder' }
        return [IO.Path]::GetFullPath((Join-Path $platformTools 'adb.exe'))
    }

    $sdkRoot = Join-Path $testRoot 'sdk-root'
    $homeRoot = Join-Path $testRoot 'android-home'
    $legacyLocal = Join-Path $testRoot 'local-app-data'
    $expectedSdkRoot = New-TestSdk $sdkRoot
    $expectedHome = New-TestSdk $homeRoot
    $expectedLegacy = New-TestSdk (Join-Path $legacyLocal 'Android\Sdk')

    Assert-Equal $expectedSdkRoot (Resolve-AndroidAdbPath -AndroidSdkRoot $sdkRoot -AndroidHome $homeRoot -LocalAppData $legacyLocal) 'ANDROID_SDK_ROOT should take precedence.'
    Write-Output 'PASS: ANDROID_SDK_ROOT resolves to platform-tools\adb.exe.'

    Assert-Equal $expectedHome (Resolve-AndroidAdbPath -AndroidSdkRoot $null -AndroidHome $homeRoot -LocalAppData $legacyLocal) 'ANDROID_HOME should be supported.'
    Write-Output 'PASS: ANDROID_HOME resolves when ANDROID_SDK_ROOT is absent.'

    Assert-Equal $expectedLegacy (Resolve-AndroidAdbPath -AndroidSdkRoot $null -AndroidHome $null -LocalAppData $legacyLocal) 'Legacy LOCALAPPDATA SDK location should remain supported.'
    Write-Output 'PASS: legacy LOCALAPPDATA\Android\Sdk remains supported.'

    $invalidRoot = Join-Path $testRoot 'invalid-sdk'
    $invalidPlatformTools = Join-Path $invalidRoot 'platform-tools'
    New-Item -ItemType Directory -Path $invalidPlatformTools -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $invalidPlatformTools 'adb.exe') -Value 'not enough without SDK metadata'
    Assert-Throws { Resolve-AndroidAdbPath -AndroidSdkRoot $invalidRoot -AndroidHome $null -LocalAppData $null } 'An SDK without Platform-Tools metadata must be rejected.'
    Write-Output 'PASS: invalid SDK path is blocked.'

    $missingAdbRoot = Join-Path $testRoot 'sdk-without-adb'
    $null = New-TestSdk $missingAdbRoot $false
    Assert-Throws { Resolve-AndroidAdbPath -AndroidSdkRoot $missingAdbRoot -AndroidHome $null -LocalAppData $null } 'A valid SDK without adb.exe must be rejected.'
    Write-Output 'PASS: missing adb.exe is blocked.'

    $wrongFolder = Join-Path $testRoot 'adb-outside-platform-tools'
    New-Item -ItemType Directory -Path $wrongFolder -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $wrongFolder 'adb.exe') -Value 'not an SDK adb'
    Assert-Throws { Resolve-AndroidAdbPath -AndroidSdkRoot $wrongFolder -AndroidHome $null -LocalAppData $null } 'An adb.exe outside a valid SDK platform-tools folder must be rejected.'
    Write-Output 'PASS: adb.exe outside a valid platform-tools folder is blocked.'

    $prepare = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'prepare-spark-local-memu.ps1') -Raw
    if ($prepare -notmatch '(?m)^\$script:device = ''127\.0\.0\.1:21503''$') {
        throw 'The preflight no longer pins ADB to the identified MEmu serial.'
    }
    if ($prepare -notmatch 'MEmuHeadless\.exe' -or $prepare -notmatch 'listvms') {
        throw 'The preflight must retain process and MEMUC instance identity checks.'
    }
    if ($prepare -notmatch 'Invoke-LocalAdb -Arguments @\(''-s'', \$script:device, ''get-state''\)' -or
        $prepare -match 'Invoke-LocalAdb -Arguments @\(''devices'', ''-l''\)') {
        throw 'The preflight must probe only the already-verified MEmu serial, never enumerate global ADB devices.'
    }
    if ($prepare -notmatch '\[switch\]\$InstallOnly' -or $prepare -notmatch '\[switch\]\$Bootstrap' -or
        $prepare -notmatch "SparkLocal MEmu installation preflight aprovado\." -or
        $prepare -notmatch "SparkLocal MEmu bootstrap aprovado;") {
        throw 'MEmu installation and VPN bootstrap require separate host-verified preflight stages.'
    }
    Write-Output 'PASS: preflight remains pinned to MEmu serial and retains MEmu identity checks.'
    Write-Output 'PASS: ADB readiness probes only the verified MEmu serial.'
    Write-Output 'PASS: installation and VPN bootstrap have separate preflight approvals.'

    $start = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'start-spark-local-memu.ps1') -Raw
    if ($start -notmatch '\[switch\]\$BuildAndInstall' -or
        $start -notmatch 'flutter build apk --debug --flavor sparkLocal --no-pub' -or
        $start -notmatch 'SPARK_LOCAL_EMULATORS=true' -or
        $start -notmatch 'installapp -i 0' -or $start -notmatch 'startapp -i 0' -or
        $start -notmatch '\$RunFinalStart') {
        throw 'MEmu build/install must use the guarded SparkLocal build, index-0 MEMUC installation and final full preflight.'
    }
    Write-Output 'PASS: one-command MEmu flow builds, validates, targets only index 0 and reuses the full preflight.'

    & (Join-Path $PSScriptRoot 'test-start-spark-local-memu.ps1') 2>&1 | Out-Null
    Write-Output 'PASS: Gate refusal without explicit preflight authorization remains tested.'
} finally {
    $resolvedParent = [IO.Path]::GetFullPath($allowedParent).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
    if (!$resolvedTestRoot.StartsWith($resolvedParent, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Refusing to remove test files outside the dedicated temporary directory.'
    }
    Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
}
