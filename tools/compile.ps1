# Compile source only. This helper never starts a trading terminal or test agent.
[CmdletBinding()]
param(
    [string]$MetaEditorPath,
    [ValidateRange(10, 600)]
    [int]$TimeoutSeconds = 120
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    $projectDirectory = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    if ([string]::IsNullOrWhiteSpace($MetaEditorPath)) {
        # Deliberately fixed candidates; no recursive search or terminal startup.
        $candidates = @(
            (Join-Path $env:ProgramFiles 'XM Global MT5\MetaEditor64.exe'),
            (Join-Path $env:ProgramFiles 'MetaTrader 5\MetaEditor64.exe')
        )
        $MetaEditorPath = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
        if ([string]::IsNullOrWhiteSpace($MetaEditorPath)) {
            throw 'MetaEditor64.exe was not found in the fixed installation paths. Supply -MetaEditorPath explicitly.'
        }
    }
    $MetaEditorPath = (Resolve-Path -LiteralPath $MetaEditorPath).ProviderPath
    if ([IO.Path]::GetFileName($MetaEditorPath) -ine 'MetaEditor64.exe') {
        throw '-MetaEditorPath must name MetaEditor64.exe.'
    }
    $targets = @(
        @{ Source = 'MQL5\Experts\Biltech_AMD_FVG_Research.mq5'; Log = 'tests\compile_ea.log' },
        @{ Source = 'MQL5\Scripts\Biltech_AMD_Tests.mq5'; Log = 'tests\compile_fixtures.log' }
    )
    $failed = $false
    foreach ($target in $targets) {
        $sourcePath = Join-Path $projectDirectory $target.Source
        $logPath = Join-Path $projectDirectory $target.Log
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw "Source file missing: $sourcePath" }
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($logPath)) | Out-Null
        # Remove only this exact old log, so stale success cannot satisfy this run.
        if (Test-Path -LiteralPath $logPath -PathType Leaf) { Remove-Item -LiteralPath $logPath }
        $arguments = @(('/compile:"' + $sourcePath + '"'), ('/log:"' + $logPath + '"'))
        $compilerProcess = Start-Process -FilePath $MetaEditorPath -ArgumentList $arguments -WindowStyle Hidden -PassThru
        if (-not $compilerProcess.WaitForExit($TimeoutSeconds * 1000)) {
            # Stop only the process launched by this helper, never an inventory of editors.
            $compilerProcess.Kill()
            throw "Compiler timed out after $TimeoutSeconds seconds for $($target.Source)"
        }
        # An existing editor can handle /compile asynchronously. Wait only for a
        # fresh final result record, bounded by the same explicit timeout.
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $summary = $null
        do {
            if (Test-Path -LiteralPath $logPath -PathType Leaf) {
                $content = Get-Content -LiteralPath $logPath -Raw
                $resultMatches = [regex]::Matches($content, '(?m)^Result:\s*(\d+) errors?,\s*(\d+) warnings?[^\r\n]*\r?$')
                if ($resultMatches.Count -gt 0) { $summary = $resultMatches[$resultMatches.Count - 1]; break }
            }
            Start-Sleep -Milliseconds 200
        } while ($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds)
        if ($null -eq $summary) {
            $failed = $true
            Write-Warning "No fresh final compiler summary: $logPath"
            continue
        }
        Write-Output "$($target.Source): $($summary.Value.Trim())"
        if ($summary.Groups[1].Value -ne '0' -or $summary.Groups[2].Value -ne '0') { $failed = $true }
    }
    if ($failed) { exit 1 }
    Write-Output 'Both sources compiled with 0 errors and 0 warnings. Native fixture execution and Strategy Tester remain separate checks.'
    exit 0
} catch {
    Write-Error -Message $_.Exception.Message -ErrorAction Continue
    exit 1
}
