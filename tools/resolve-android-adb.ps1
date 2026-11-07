function Resolve-AndroidAdbPath {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$AndroidSdkRoot = $env:ANDROID_SDK_ROOT,
        [AllowNull()][string]$AndroidHome = $env:ANDROID_HOME,
        [AllowNull()][string]$LocalAppData = $env:LOCALAPPDATA
    )

    $candidates = [System.Collections.Generic.List[string]]::new()
    if (![string]::IsNullOrWhiteSpace($AndroidSdkRoot)) {
        $candidates.Add($AndroidSdkRoot)
    }
    if (![string]::IsNullOrWhiteSpace($AndroidHome)) {
        $candidates.Add($AndroidHome)
    }
    if (![string]::IsNullOrWhiteSpace($LocalAppData)) {
        $candidates.Add((Join-Path $LocalAppData 'Android\Sdk'))
    }

    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($candidate in $candidates) {
        try {
            $sdkRoot = [IO.Path]::GetFullPath($candidate)
        } catch {
            continue
        }
        if (!$seen.Add($sdkRoot)) { continue }

        $platformTools = Join-Path $sdkRoot 'platform-tools'
        $adbPath = Join-Path $platformTools 'adb.exe'
        $metadataPath = Join-Path $platformTools 'source.properties'
        if (!(Test-Path -LiteralPath $sdkRoot -PathType Container) -or
            !(Test-Path -LiteralPath $platformTools -PathType Container) -or
            !(Test-Path -LiteralPath $adbPath -PathType Leaf) -or
            !(Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
            continue
        }

        $metadata = Get-Content -LiteralPath $metadataPath -Raw
        if ($metadata -match '(?m)^Pkg\.Revision=\d+(\.\d+){1,3}\s*$') {
            return [IO.Path]::GetFullPath($adbPath)
        }
    }

    throw 'Android SDK Platform-Tools válido não encontrado em ANDROID_SDK_ROOT, ANDROID_HOME ou no caminho LOCALAPPDATA legado.'
}
