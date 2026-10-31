param([switch]$SkipBuilds, [switch]$Browser)

$ErrorActionPreference = 'Stop'
$appRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$backendRoot = Join-Path $appRoot 'backend/otp-relay'
$outputRoot = Join-Path $appRoot 'build/verification'
$null = New-Item -ItemType Directory -Force -Path $outputRoot
$flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
$flutterPath = if ($flutterCommand) { $flutterCommand.Source } else { 'C:/src/flutter/bin/flutter.bat' }
if (-not (Test-Path -LiteralPath $flutterPath)) { throw 'Flutter was not found.' }
$checks = [Collections.Generic.List[object]]::new()
$started = [DateTime]::UtcNow
$complete = $false

function Invoke-Check([string]$Name, [string]$Directory, [string]$Command, [string[]]$CommandArgs) {
    $checkStarted = [DateTime]::UtcNow
    Write-Host "Checking: $Name"
    Push-Location $Directory
    try {
        & $Command @CommandArgs
        $code = $LASTEXITCODE
        $checks.Add([ordered]@{ name = $Name; status = $(if ($code -eq 0) { 'passed' } else { 'failed' });
            exitCode = $code; durationMs = [int]([DateTime]::UtcNow - $checkStarted).TotalMilliseconds })
        if ($code -ne 0) { throw "$Name failed (exit $code)." }
    } finally { Pop-Location }
}

try {
    Invoke-Check '1. Native PostgreSQL migration, privacy and concurrency' $backendRoot 'npm.cmd' @('run', 'test:postgres')
    Invoke-Check '2. Full backend suite' $backendRoot 'npm.cmd' @('test')
    Invoke-Check '3. Flutter static analysis' $appRoot $flutterPath @('analyze', '--no-pub')
    Invoke-Check '4. Full Flutter suite' $appRoot $flutterPath @('test', '--no-pub')
    if (-not $SkipBuilds) {
        Invoke-Check '5. Web release' $appRoot $flutterPath @('build', 'web', '--no-pub', '--no-wasm-dry-run', '--no-web-resources-cdn', '--dart-define=DELIVERY_API_BASE_URL=http://127.0.0.1:8787/delivery/')
        Invoke-Check '6. Windows release' $appRoot $flutterPath @('build', 'windows', '--release', '--no-pub')
    }
    if ($Browser) {
        Invoke-Check '7. Marketplace desktop/mobile fixtures' $appRoot 'node' @('tool/check-marketplace-browser.cjs')
        Invoke-Check '8. Cloud compatibility desktop/mobile fixtures' $appRoot 'node' @('tool/check-cloud-browser.cjs')
        Invoke-Check '9. Separate Admin fixtures' $appRoot 'node' @('tool/check-admin-browser.cjs')
        Invoke-Check '10. Full role and feature-button acceptance gallery' $appRoot 'node' @('tool/check-full-ui-acceptance.cjs')
    }
    $complete = $true
} finally {
    [ordered]@{ environment = 'local-and-isolated-fixtures'; checkedAt = [DateTime]::UtcNow.ToString('o');
        startedAt = $started.ToString('o'); selectedChecksPassed = $complete; buildsSelected = (-not $SkipBuilds);
        browserSelected = [bool]$Browser; commercializationComplete = $false; checks = @($checks.ToArray());
        externalAcceptance = 'Not certified: cloud rollout, real Auth/providers, HTTPS, hosted CI, restore and pilot.'
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $outputRoot 'ordered-checks.json') -Encoding UTF8
}
