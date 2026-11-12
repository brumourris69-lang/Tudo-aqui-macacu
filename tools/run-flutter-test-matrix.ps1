param()

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not (Test-Path (Join-Path $projectRoot 'pubspec.yaml')) -or
    -not (Test-Path (Join-Path $projectRoot 'test/content_editor_persistence_test.dart'))) {
    throw 'Flutter project files were not found; no tests were started.'
}

$runs = @(
    @{
        Name = 'common'
        Args = @('test', '--no-pub', '--reporter=json', '--exclude-tags', 'search-local,beta-environment')
    },
    @{
        Name = 'beta-editor'
        Args = @('test', '--no-pub', '--reporter=json', '--dart-define=BETA_IOS_ENABLED=true',
            'test/content_editor_persistence_test.dart')
    },
    @{
        Name = 'search-local-mocks'
        Args = @('test', '--no-pub', '--reporter=json', '--dart-define=LOCAL_SEARCH_EMULATORS=true',
            '--dart-define=LOCAL_SEARCH_PROJECT=demo-universal-search', '--dart-define=LOCAL_SEARCH_HOST=127.0.0.1',
            'test/admin_authorization_test.dart', 'test/city_agenda_view_test.dart',
            'test/firestore_content_list_test.dart', 'test/global_search_view_test.dart',
            'test/local_demo_login_test.dart', 'test/local_native_gate_test.dart',
            'test/local_network_isolation_test.dart', 'test/local_universal_search_test.dart',
            'test/public_content_detail_repository_test.dart',
            'test/public_job_details_repository_test.dart', 'test/public_content_test.dart',
            'test/user_operations_test.dart', 'test/app_check_preparation_test.dart',
            'test/local_session_recovery_test.dart')
    },
    @{
        Name = 'local-app-check'
        Args = @('test', '--no-pub', '--reporter=json', '--dart-define=LOCAL_SEARCH_EMULATORS=true',
            '--dart-define=LOCAL_SEARCH_APP_CHECK=true', '--dart-define=LOCAL_SEARCH_HOST=127.0.0.1',
            'test/app_check_preparation_test.dart')
    }
)

$summary = [System.Collections.Generic.List[object]]::new()
$anyFailure = $false
Push-Location $projectRoot
try {
    foreach ($run in $runs) {
        Write-Output "RUN $($run.Name)"
        $arguments = $run.Args
        $output = @(& flutter @arguments 2>&1)
        $exitCode = $LASTEXITCODE
        $events = [System.Collections.Generic.List[object]]::new()
        foreach ($line in $output) {
            try {
                $event = ([string]$line | ConvertFrom-Json -ErrorAction Stop)
                if ($event.type) { $events.Add($event) }
            }
            catch { }
        }

        $visibleDone = @($events | Where-Object { $_.type -eq 'testDone' -and $_.hidden -ne $true })
        $passed = @($visibleDone | Where-Object { $_.result -eq 'success' -and $_.skipped -ne $true }).Count
        $skipped = @($visibleDone | Where-Object { $_.skipped -eq $true }).Count
        $failedTests = @($visibleDone | Where-Object { $_.result -ne 'success' -and $_.skipped -ne $true })
        $failed = $failedTests.Count
        if ($exitCode -ne 0 -and $failed -eq 0) { $failed = 1 }

        $namesById = @{}
        foreach ($event in $events | Where-Object { $_.type -eq 'testStart' }) {
            $namesById[[string]$event.test.id] = [string]$event.test.name
        }
        foreach ($failure in $failedTests) {
            $label = $namesById[[string]$failure.testID]
            if ($label) { Write-Output "FAIL TEST $label" }
        }

        $result = [pscustomobject]@{
            environment = $run.Name
            tests = $visibleDone.Count
            passed = $passed
            skipped = $skipped
            failed = $failed
            exitCode = $exitCode
        }
        $summary.Add($result)
        Write-Output "RESULT $($run.Name): tests=$($result.tests), passed=$passed, skipped=$skipped, failed=$failed, exit=$exitCode"
        if ($exitCode -ne 0 -or $failed -gt 0) {
            $anyFailure = $true
            foreach ($line in $output) { Write-Output ([string]$line) }
        }
    }
}
finally {
    Pop-Location
}

Write-Output ('MATRIX ' + (ConvertTo-Json -InputObject @($summary) -Compress))
if ($anyFailure) { exit 1 }
