function Wait-SearchLocalDevice {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Device,
        [Parameter(Mandatory)][scriptblock]$InvokeAdb,
        [ValidateRange(1, 120)][int]$TimeoutSeconds = 12,
        [switch]$Quiet
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $poll = 0
    $devicePattern = '^\s*' + [regex]::Escape($Device) + '\s+device\b'
    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            $rows = @(& $InvokeAdb -Arguments @('devices', '-l'))
            if ($rows | Where-Object { $_ -match $devicePattern } | Select-Object -First 1) {
                return $true
            }
        } catch {
            # ADB may be between transports; keep waiting by serial.
        }

        # Reconnect by serial at a moderate cadence; transport IDs may change.
        if (($poll % 4) -eq 0) {
            try { $null = & $InvokeAdb -Arguments @('connect', $Device) } catch { }
        }
        $poll++
        Start-Sleep -Milliseconds 750
    }
    if ($Quiet) { return $false }
    throw "MEmu did not return on serial $Device within $TimeoutSeconds seconds; Flutter startup was blocked."
}

function Invoke-SearchLocalAdbRead {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Device,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$Operation,
        [Parameter(Mandatory)][scriptblock]$InvokeAdb,
        [ValidateRange(1, 3)][int]$MaxAttempts = 2,
        [ValidateRange(1, 30)][int]$ReconnectWaitSeconds = 12
    )

    $ready = Wait-SearchLocalDevice -Device $Device -InvokeAdb $InvokeAdb `
        -TimeoutSeconds $ReconnectWaitSeconds -Quiet
    $adbArguments = @('-s', $Device) + $Arguments
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        if (-not $ready) {
            throw "MEmu remained unavailable during $Operation after the bounded reconnect wait."
        }

        try {
            return & $InvokeAdb -Arguments $adbArguments
        } catch {
            if ($_.Exception.Message -notmatch '^ADB_TRANSPORT_UNAVAILABLE:') {
                throw "ADB read failed during $Operation."
            }
            if ($attempt -ge $MaxAttempts) {
                throw "MEmu disconnected during $Operation and did not recover within $MaxAttempts attempts."
            }

            $ready = Wait-SearchLocalDevice -Device $Device -InvokeAdb $InvokeAdb `
                -TimeoutSeconds $ReconnectWaitSeconds -Quiet
        }
    }

    throw "MEmu remained unavailable during $Operation after the bounded reconnect wait."
}

function Test-SearchLocalVpnIsolationOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Connectivity,
        [Parameter(Mandatory)][string]$Package,
        [Parameter(Mandatory)][string]$PackageUid
    )

    $session = 'ni{VPN CONNECTED extra: VPN:' + $Package + '}'
    $sessionIndex = $Connectivity.IndexOf($session, [StringComparison]::Ordinal)
    if ($sessionIndex -lt 0) { return $false }

    $blockStart = $Connectivity.LastIndexOf('NetworkAgentInfo{network{', $sessionIndex, [StringComparison]::Ordinal)
    if ($blockStart -lt 0) { return $false }
    $blockEnd = $Connectivity.IndexOf('NetworkAgentInfo{network{', $sessionIndex, [StringComparison]::Ordinal)
    if ($blockEnd -lt 0) { $blockEnd = $Connectivity.Length }
    if ($blockEnd -le $sessionIndex) { return $false }
    $block = $Connectivity.Substring($blockStart, $blockEnd - $blockStart)

    if ($block -notmatch 'InterfaceName:\s*tun0\b' -or
        $block -notmatch 'Transports:\s*[^\]]*\bVPN\b' -or
        $block -notmatch 'TransportInfo:\s*<VpnTransportInfo\{[^>]*sessionId=Macacu — somente emuladores locais,\s*bypassable=false') {
        return $false
    }

    $modernUid = [regex]::Match($block,
        'Uids:\s*<\{(?<uids>[^}]+)\}>\s+OwnerUid:\s*(?<owner>\d+)\s+AdminUids:\s*\[(?<admin>\d+)\]')
    if ($modernUid.Success) {
        if ($modernUid.Groups['owner'].Value -ne $PackageUid -or
            $modernUid.Groups['admin'].Value -ne $PackageUid) { return $false }

        $allowedUids = @([long]$PackageUid, ([long]$PackageUid + 10000))
        $observedUids = @()
        foreach ($entry in ($modernUid.Groups['uids'].Value -split ',')) {
            $range = [regex]::Match($entry.Trim(), '^(?<first>\d+)-(?<last>\d+)$')
            if (-not $range.Success -or $range.Groups['first'].Value -ne $range.Groups['last'].Value) {
                return $false
            }
            $observedUids += [long]$range.Groups['first'].Value
        }
        return $observedUids.Count -gt 0 -and
            $observedUids -contains [long]$PackageUid -and
            @($observedUids | Where-Object { $_ -notin $allowedUids }).Count -eq 0
    }

    # Android versions before per-UID range reporting expose the same
    # package-bound VPN through Uid + EstablishingAppUid.
    $legacyUid = [regex]::Match($block,
        'Uid:\s*(?<uid>\d+)\s+EstablishingAppUid:\s*(?<established>\d+)\b')
    return $legacyUid.Success -and
        $legacyUid.Groups['uid'].Value -eq $PackageUid -and
        $legacyUid.Groups['established'].Value -eq $PackageUid
}

function Test-SearchLocalVpnIsolation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Device,
        [Parameter(Mandatory)][string]$Package,
        [Parameter(Mandatory)][scriptblock]$InvokeAdb
    )

    $packageRows = Invoke-SearchLocalAdbRead -Device $Device `
        -Arguments @('shell', 'cmd', 'package', 'list', 'packages', '-U') `
        -Operation 'searchLocal UID check' -InvokeAdb $InvokeAdb `
        -MaxAttempts 2 -ReconnectWaitSeconds 4
    $packageRow = $packageRows | Where-Object { $_ -match [regex]::Escape($Package) }
    $uidMatch = [regex]::Match(($packageRow -join "`n"), '\buid:(\d+)\b')
    if (!$uidMatch.Success) { return $false }
    $packageUid = $uidMatch.Groups[1].Value

    $connectivity = (Invoke-SearchLocalAdbRead -Device $Device `
        -Arguments @('shell', 'dumpsys', 'connectivity') `
        -Operation 'VPN app isolation check' -InvokeAdb $InvokeAdb `
        -MaxAttempts 2 -ReconnectWaitSeconds 4) -join "`n"
    return Test-SearchLocalVpnIsolationOutput -Connectivity $connectivity `
        -Package $Package -PackageUid $packageUid
}

function Test-SearchLocalDiagnosticProxyIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CommandLine,
        [Parameter(Mandatory)][string]$ProcessName,
        [Parameter(Mandatory)][string]$ListeningAddress,
        [Parameter(Mandatory)][int]$Port
    )

    return $ProcessName -eq 'node.exe' -and
        $ListeningAddress -eq '127.0.0.1' -and
        $Port -eq 9197 -and
        $CommandLine -match '(?i)auth-emulator-diagnostic-proxy\.cjs' -and
        $CommandLine -match '(?i)--project\s+demo-universal-search(?:\s|$)'
}

function Wait-SearchLocalForwardingStable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Device,
        [Parameter(Mandatory)][string]$Package,
        [Parameter(Mandatory)][scriptblock]$InvokeAdb,
        [Parameter(Mandatory)][scriptblock]$VerifyLocalEndpoints,
        [int[]]$Ports = @(9097, 8087, 5007),
        [int]$TimeoutSeconds = 24,
        [int]$StableChecks = 3,
        [int]$PollMilliseconds = 1000
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $lastTransportId = $null
    $stableCount = 0
    $reconnects = 0
    $vpnConfirmed = $false

    while ([DateTime]::UtcNow -lt $deadline) {
        if (-not (Test-SearchLocalVpnIsolation -Device $Device -Package $Package -InvokeAdb $InvokeAdb)) {
            $stableCount = 0
            $lastTransportId = $null
            Start-Sleep -Milliseconds $PollMilliseconds
            continue
        }
        $vpnConfirmed = $true
        if (-not (& $VerifyLocalEndpoints $Ports)) {
            throw 'A local demo endpoint is unavailable; forwarding was not changed.'
        }

        $deviceRows = @(& $InvokeAdb -Arguments @('devices', '-l'))
        $devicePattern = '^\s*' + [regex]::Escape($Device) + '\s+device\b'
        $deviceRow = $deviceRows | Where-Object { $_ -match $devicePattern } | Select-Object -First 1
        if (-not $deviceRow) {
            $stableCount = 0
            $lastTransportId = $null
            Start-Sleep -Milliseconds $PollMilliseconds
            continue
        }

        $transportId = $null
        if ($deviceRow -match 'transport_id:(\d+)') { $transportId = $Matches[1] }
        if ($lastTransportId -and $transportId -and $transportId -ne $lastTransportId) {
            $stableCount = 0
        }

        $reverseRows = @(& $InvokeAdb -Arguments @('-s', $Device, 'reverse', '--list'))
        $missingPorts = @($Ports | Where-Object {
            $port = $_
            -not ($reverseRows | Where-Object { $_ -match "tcp:$port\s+tcp:$port(?:\s|$)" })
        })

        if ($missingPorts.Count -gt 0) {
            if (-not (Test-SearchLocalVpnIsolation -Device $Device -Package $Package -InvokeAdb $InvokeAdb) -or
                -not (& $VerifyLocalEndpoints $Ports)) {
                throw 'VPN isolation or local demo endpoints changed; forwarding was not changed.'
            }
            $mappingRestoreFailed = $false
            foreach ($port in $missingPorts) {
                $null = & $InvokeAdb -Arguments @('-s', $Device, 'reverse', "tcp:$port", "tcp:$port")
                $portRows = @(& $InvokeAdb -Arguments @('-s', $Device, 'reverse', '--list'))
                if (-not ($portRows | Where-Object { $_ -match "tcp:$port\s+tcp:$port(?:\s|$)" })) {
                    $mappingRestoreFailed = $true
                    break
                }
            }
            if ($mappingRestoreFailed) {
                $stableCount = 0
                Start-Sleep -Milliseconds $PollMilliseconds
                continue
            }
        }

        # Verify the serial's current transport and every mapping after repair.
        $finalRows = @(& $InvokeAdb -Arguments @('devices', '-l'))
        $finalDevice = $finalRows | Where-Object { $_ -match $devicePattern } | Select-Object -First 1
        $finalTransportId = $null
        if ($finalDevice -match 'transport_id:(\d+)') { $finalTransportId = $Matches[1] }
        $finalReverseRows = @(& $InvokeAdb -Arguments @('-s', $Device, 'reverse', '--list'))
        $stillMissing = @($Ports | Where-Object {
            $port = $_
            -not ($finalReverseRows | Where-Object { $_ -match "tcp:$port\s+tcp:$port(?:\s|$)" })
        })

        if (-not $finalDevice -or $stillMissing.Count -gt 0 -or
            ($transportId -and $finalTransportId -and $transportId -ne $finalTransportId)) {
            if ($transportId -and $finalTransportId -and $transportId -ne $finalTransportId) {
                $reconnects++
            }
            $stableCount = 0
            $lastTransportId = $finalTransportId
            Start-Sleep -Milliseconds $PollMilliseconds
            continue
        }

        if (-not (Test-SearchLocalVpnIsolation -Device $Device -Package $Package -InvokeAdb $InvokeAdb) -or
            -not (& $VerifyLocalEndpoints $Ports)) {
            throw 'VPN isolation or local demo endpoints changed during forwarding verification.'
        }

        if ($lastTransportId -and $finalTransportId -and $finalTransportId -ne $lastTransportId) {
            $reconnects++
            $stableCount = 1
        } else {
            $stableCount++
        }
        $lastTransportId = $finalTransportId

        if ($stableCount -ge $StableChecks) {
            return [pscustomobject]@{
                Device = $Device
                TransportId = if ($finalTransportId) { $finalTransportId } else { 'unavailable' }
                Ports = @($Ports)
                StableChecks = $stableCount
                ReconnectsDetected = $reconnects
            }
        }

        Start-Sleep -Milliseconds $PollMilliseconds
    }

    if (-not $vpnConfirmed) {
        throw 'VPN isolation was not confirmed; forwarding was not changed.'
    }
    throw "ADB reverse did not remain stable for $StableChecks checks within $TimeoutSeconds seconds."
}
