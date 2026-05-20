# Compares BenchmarkDotNet CSV results between net10.0 and net11.0 runs.
# Requires `BenchmarkResults/net10/results/*.csv` and `BenchmarkResults/net11/results/*.csv` to exist.

param(
    [string]$Net10Dir = "BenchmarkResults\net10\results",
    [string]$Net11Dir = "BenchmarkResults\net11\results",
    [string]$OutputCsv = "BenchmarkResults\comparison.csv"
)

function Get-BenchmarkRows {
    param([string]$Dir)
    if (-not (Test-Path $Dir)) { return @() }
    $rows = @()
    foreach ($file in Get-ChildItem -Path $Dir -Filter "*-report.csv") {
        $csv = Import-Csv -Path $file.FullName -Delimiter ','
        foreach ($r in $csv) {
            # BDN headers vary slightly between runs/cultures; tolerate either.
            $type = $file.BaseName -replace '-report$', ''
            $method = $r.Method
            $mean = $r.'Mean'
            $alloc = $r.'Allocated'
            $rows += [pscustomobject]@{
                Type      = $type
                Method    = $method
                Params    = ($r.PSObject.Properties.Where{ $_.Name -in 'Iterations','Yields','Messages' } | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ';'
                Mean      = $mean
                Allocated = $alloc
            }
        }
    }
    return $rows
}

function Parse-Ns {
    param([string]$Value)
    if (-not $Value) { return $null }
    # BDN en-US format: comma = thousands separator, dot = decimal. Strip commas, trim whitespace.
    $v = ($Value -replace ',', '').Trim()
    # BDN emits 'μs' (Greek mu U+03BC) but some sources use 'µs' (micro sign U+00B5) or 'us' (ascii).
    # Normalize all to 'us' before regex.
    $vNorm = $v -replace "[µμ]", 'u'
    if ($vNorm -match '^([0-9]*\.?[0-9]+)\s*(ns|us|ms|s)$') {
        $num = [double]::Parse($matches[1], [System.Globalization.CultureInfo]::InvariantCulture)
        switch ($matches[2]) {
            'ns' { return $num }
            'us' { return $num * 1000 }
            'ms' { return $num * 1000000 }
            's'  { return $num * 1000000000 }
        }
    }
    try { return [double]::Parse($v, [System.Globalization.CultureInfo]::InvariantCulture) } catch { return $null }
}

function Parse-Bytes {
    param([string]$Value)
    if (-not $Value -or $Value -eq '-') { return 0.0 }
    $v = ($Value -replace ',', '').Trim()
    if ($v -match '^([0-9]*\.?[0-9]+)\s*(B|KB|MB|GB)?$') {
        $num = [double]::Parse($matches[1], [System.Globalization.CultureInfo]::InvariantCulture)
        switch ($matches[2]) {
            'KB'    { return $num * 1024 }
            'MB'    { return $num * 1024 * 1024 }
            'GB'    { return $num * 1024 * 1024 * 1024 }
            default { return $num }
        }
    }
    try { return [double]::Parse($v, [System.Globalization.CultureInfo]::InvariantCulture) } catch { return 0.0 }
}

$rows10 = Get-BenchmarkRows -Dir $Net10Dir
$rows11 = Get-BenchmarkRows -Dir $Net11Dir

if (-not $rows10) { Write-Error "No net10 results found in $Net10Dir"; exit 1 }
if (-not $rows11) { Write-Error "No net11 results found in $Net11Dir"; exit 1 }

$idx10 = @{}
foreach ($r in $rows10) { $idx10["$($r.Type)::$($r.Method)::$($r.Params)"] = $r }

$results = @()
foreach ($r11 in $rows11) {
    $key = "$($r11.Type)::$($r11.Method)::$($r11.Params)"
    $r10 = $idx10[$key]
    if (-not $r10) { continue }

    $ns10 = Parse-Ns -Value $r10.Mean
    $ns11 = Parse-Ns -Value $r11.Mean
    $b10  = Parse-Bytes -Value $r10.Allocated
    $b11  = Parse-Bytes -Value $r11.Allocated

    $speedup = if ($ns11 -and $ns11 -gt 0) { [math]::Round($ns10 / $ns11, 2) } else { $null }
    $deltaPct = if ($ns10 -and $ns10 -gt 0) { [math]::Round(($ns11 - $ns10) / $ns10 * 100, 1) } else { $null }
    $allocDelta = if ($b10 -gt 0) { [math]::Round(($b11 - $b10) / $b10 * 100, 1) } else { if ($b11 -eq 0) { 0 } else { $null } }

    $results += [pscustomobject]@{
        Benchmark    = "$($r11.Type -replace 'AsyncBenchmark.Benchmarks.','').$($r11.Method)"
        Params       = $r11.Params
        Net10_Mean   = $r10.Mean
        Net11_Mean   = $r11.Mean
        Delta_Pct    = $deltaPct
        Speedup_X    = $speedup
        Net10_Alloc  = $r10.Allocated
        Net11_Alloc  = $r11.Allocated
        Alloc_Delta_Pct = $allocDelta
    }
}

$results | Sort-Object Benchmark | Format-Table -AutoSize
$outputDir = Split-Path -Parent $OutputCsv
if ($outputDir -and -not (Test-Path $outputDir)) { New-Item -ItemType Directory -Path $outputDir | Out-Null }
$results | Sort-Object Benchmark | Export-Csv -NoTypeInformation -Path $OutputCsv
Write-Host ""
Write-Host "Saved to $OutputCsv"
