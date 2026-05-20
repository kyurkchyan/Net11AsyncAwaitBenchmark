# Runs the benchmark suite N times for both net10.0 and net11.0, sequentially
# (never overlapping on the CPU), stores each trial's BDN artifacts under
# BenchmarkResults/run-N/, runs the comparison script per trial, and then
# aggregates speedup/delta statistics across trials.
#
# Output:
#   BenchmarkResults/run-1..N/{net10,net11}/results/*.csv  (raw BDN reports)
#   BenchmarkResults/run-1..N/comparison.csv               (per-trial diff)
#   BenchmarkResults/run-1..N/logs/{net10,net11}.log       (raw BDN console output)
#   BenchmarkResults/aggregate.csv                         (mean/stddev across trials)

param(
    [int]$Trials = 5,
    [string]$ResultsRoot = "BenchmarkResults"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Clean any prior state so the trial dirs are unambiguous.
if (Test-Path $ResultsRoot) {
    Get-ChildItem -Path $ResultsRoot -Force | Remove-Item -Recurse -Force
}
New-Item -ItemType Directory -Path $ResultsRoot -Force | Out-Null

Write-Host "Building Release for net10.0 and net11.0..." -ForegroundColor Cyan
dotnet build -c Release | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Build failed" }

for ($i = 1; $i -le $Trials; $i++) {
    $trialDir = Join-Path $ResultsRoot "run-$i"
    $logDir   = Join-Path $trialDir "logs"
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null

    Write-Host ""
    Write-Host "=== Trial $i / $Trials ===" -ForegroundColor Cyan

    Write-Host "  net10.0 ..." -NoNewline
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    dotnet run -c Release -f net10.0 --no-build -- `
        --filter "AsyncBenchmark.Benchmarks.*" `
        --artifacts (Join-Path $trialDir "net10") `
        *> (Join-Path $logDir "net10.log")
    if ($LASTEXITCODE -ne 0) { throw "net10.0 trial $i failed" }
    Write-Host " done in $([math]::Round($sw.Elapsed.TotalSeconds, 1))s"

    Write-Host "  net11.0 ..." -NoNewline
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    dotnet run -c Release -f net11.0 --no-build -- `
        --filter "AsyncBenchmark.Benchmarks.*" `
        --artifacts (Join-Path $trialDir "net11") `
        *> (Join-Path $logDir "net11.log")
    if ($LASTEXITCODE -ne 0) { throw "net11.0 trial $i failed" }
    Write-Host " done in $([math]::Round($sw.Elapsed.TotalSeconds, 1))s"

    Write-Host "  comparison ..." -NoNewline
    & (Join-Path $PSScriptRoot "compare-results.ps1") `
        -Net10Dir (Join-Path $trialDir "net10\results") `
        -Net11Dir (Join-Path $trialDir "net11\results") `
        -OutputCsv (Join-Path $trialDir "comparison.csv") `
        *> $null
    if ($LASTEXITCODE -ne 0) { throw "comparison trial $i failed" }
    Write-Host " done"
}

# --- Aggregate across trials ---
Write-Host ""
Write-Host "=== Aggregating $Trials trials ===" -ForegroundColor Cyan

$allRows = @{}  # key: "Benchmark::Params" -> list of per-trial rows
for ($i = 1; $i -le $Trials; $i++) {
    $csvPath = Join-Path $ResultsRoot "run-$i\comparison.csv"
    foreach ($r in Import-Csv -Path $csvPath) {
        $key = "$($r.Benchmark)::$($r.Params)"
        if (-not $allRows.ContainsKey($key)) { $allRows[$key] = @() }
        $allRows[$key] += $r
    }
}

function Get-Stats {
    param([double[]]$Values)
    if (-not $Values -or $Values.Count -eq 0) { return $null }
    $mean = ($Values | Measure-Object -Average).Average
    $stddev = if ($Values.Count -gt 1) {
        [Math]::Sqrt((($Values | ForEach-Object { ($_ - $mean) * ($_ - $mean) }) | Measure-Object -Sum).Sum / ($Values.Count - 1))
    } else { 0 }
    return @{
        Mean   = $mean
        StdDev = $stddev
        Min    = ($Values | Measure-Object -Minimum).Minimum
        Max    = ($Values | Measure-Object -Maximum).Maximum
    }
}

$aggregated = @()
foreach ($key in $allRows.Keys | Sort-Object) {
    $rows = $allRows[$key]
    $speedups = @($rows | ForEach-Object { [double]$_.Speedup_X })
    $deltas   = @($rows | ForEach-Object { [double]$_.Delta_Pct })

    $sStats = Get-Stats -Values $speedups
    $dStats = Get-Stats -Values $deltas
    $first = $rows[0]

    $aggregated += [pscustomobject]@{
        Benchmark          = $first.Benchmark
        Params             = $first.Params
        N_Trials           = $speedups.Count
        Mean_Speedup       = [math]::Round($sStats.Mean, 3)
        StdDev_Speedup     = [math]::Round($sStats.StdDev, 3)
        Min_Speedup        = [math]::Round($sStats.Min, 3)
        Max_Speedup        = [math]::Round($sStats.Max, 3)
        Mean_Delta_Pct     = [math]::Round($dStats.Mean, 2)
        StdDev_Delta_Pct   = [math]::Round($dStats.StdDev, 2)
        Trial_Speedups     = ($speedups | ForEach-Object { [math]::Round($_, 2) }) -join ", "
    }
}

$aggregated | Sort-Object @{Expression='Mean_Speedup';Descending=$true} | Format-Table -AutoSize
$aggregated | Sort-Object @{Expression='Mean_Speedup';Descending=$true} | Export-Csv -NoTypeInformation -Path (Join-Path $ResultsRoot "aggregate.csv")
Write-Host "Saved aggregate to $ResultsRoot\aggregate.csv"
