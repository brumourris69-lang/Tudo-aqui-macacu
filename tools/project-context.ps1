[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string[]] $Query,

    [ValidateRange(1, 80)]
    [int] $MaximumResults = 24
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$searchRoots = @(
    'AGENTS.md',
    'README.md',
    '.agents/skills',
    'lib',
    'test',
    'functions',
    'workers',
    'docs',
    'firestore.rules',
    'firestore.beta.rules'
)
$includeGlobs = @('*.dart', '*.js', '*.mjs', '*.md', '*.rules', '*.yaml')
$excludeGlobs = @(
    '!**/.git/**',
    '!**/.dart_tool/**',
    '!**/build/**',
    '!**/node_modules/**',
    '!**/fixtures/**',
    '!**/failures/**',
    '!docs/review/**',
    '!docs/visual-audits/**'
)

$rg = Get-Command 'rg' -ErrorAction SilentlyContinue
if ($null -eq $rg) {
    throw 'ripgrep (rg) is required and was not found on PATH.'
}

function Protect-SearchResult([string] $Line) {
    $safe = $Line
    $safe = $safe -replace '(?i)\bAIza[0-9A-Za-z_-]{30,}\b', '[redacted-key]'
    $safe = $safe -replace '(?i)\bya29\.[0-9A-Za-z._-]+', '[redacted-token]'
    $safe = $safe -replace '(?i)\bBearer\s+\S+', 'Bearer [redacted-token]'
    $safe = $safe -replace '(?i)\b(password|secret|token|api[_-]?key)\s*[:=]\s*(?:"[^"]*"|''[^'']*''|[^\s,;]+)', '$1=[redacted]'
    $safe = $safe -replace '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b', '[redacted-email]'
    $safe = $safe -replace '(?<!\w)(?:\+?55\s?)?(?:\(?\d{2}\)?\s?)9?\d{4}[-.\s]?\d{4}(?!\w)', '[redacted-phone]'
    return $safe
}

Push-Location $projectRoot
try {
    foreach ($term in $Query) {
        if ([string]::IsNullOrWhiteSpace($term)) { continue }

        Write-Output "## $term"
        $rgArgs = @(
            '--line-number', '--ignore-case', '--fixed-strings',
            '--max-count', '3'
        )
        foreach ($glob in $includeGlobs) {
            $rgArgs += @('--glob', $glob)
        }
        foreach ($glob in $excludeGlobs) {
            $rgArgs += @('--glob', $glob)
        }
        $rgArgs += @('--', $term) + $searchRoots

        $results = @(& $rg.Source @rgArgs 2>$null)
        $rgExit = $LASTEXITCODE
        if ($rgExit -gt 1) {
            Write-Warning "Search failed for query '$term' (ripgrep exit $rgExit)."
            continue
        }
        if ($results.Count -eq 0) {
            Write-Output '(no matches)'
            continue
        }

        $results | Select-Object -First $MaximumResults | ForEach-Object {
            Protect-SearchResult ([string] $_)
        }
    }
}
finally {
    Pop-Location
}
