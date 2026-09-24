<#
.SYNOPSIS
    Fase 6: Beregner modellens setups bagud i tid, så der er historik at evaluere med det samme.

.DESCRIPTION
    For hver af de seneste -Days handelsdage køres fase 2 og 3 med KUN de kurser der fandtes den dag.
    Resultatet gemmes i data/setups-log.json med backfill=true. Eksisterende live-setups overskrives ikke.
    Nyheder og events indgår ikke, fordi de ikke kan genskabes for fortiden.
    Kør Update-TSLA.ps1 først, så cachen er opdateret. Kør derefter Update-TSLA.ps1 igen for at
    få statistikken ud på siden, eller brug -Push.

.EXAMPLE
    .\Backfill-Setups.ps1 -Days 250
#>
[CmdletBinding()]
param(
    [int]$Days = 250,
    [switch]$Force   # Overskriv også eksisterende bagud-beregnede dage
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 1.0
if ($PSVersionTable.PSVersion.Major -lt 6) { Remove-TypeData System.Array -ErrorAction SilentlyContinue }

$Root = $PSScriptRoot
. (Join-Path $Root 'Config.ps1')
foreach ($f in @('DataProvider', 'Indicators', 'Signals', 'HistoricalSetups', 'TradeLevels', 'SetupLog')) {
    . (Join-Path (Join-Path $Root 'Engine') "$f.ps1")
}
function Write-Log([string]$Message, [string]$Level = 'INFO') { Write-Host ("{0} [{1}] {2}" -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message) }

$cacheFile = Join-Path (Join-Path $Root $Config.CacheDir) "$($Config.Symbol)_daily.json"
if (-not (Test-Path $cacheFile)) { throw "Cache mangler: $cacheFile. Kør Update-TSLA.ps1 først." }
$bars = @(Get-Content -Raw $cacheFile | ConvertFrom-Json | ForEach-Object { ConvertTo-Bar $_ } | Sort-Object Date)
Write-Log "Indlæst $($bars.Count) bars. Beregner indikatorer ..."

# Indikatorerne bruger kun data bagud i tid (glidende gennemsnit, Wilder, rullende max/min),
# så de kan beregnes én gang for hele serien uden at fremtiden lækker ind.
$rows = Add-Indicators -Bars $bars
$n = $rows.Count

$logPath = Join-Path (Join-Path $Root $Config.DataDir) 'setups-log.json'
$existing = @{}
foreach ($e in (Read-SetupLog $logPath)) { $existing[$e.date] = $e }

$start = [math]::Max(300, $n - 1 - $Days)
$new = New-Object System.Collections.Generic.List[object]
$sw = [Diagnostics.Stopwatch]::StartNew()
for ($t = $start; $t -le $n - 2; $t++) {
    $d = $rows[$t].Date
    if ($existing.ContainsKey($d) -and (-not $existing[$d].backfill -or -not $Force)) { continue }
    $slice = $rows[0..$t]    # Kun data til og med dag t
    $sig = Get-TechnicalSignals -Rows $slice
    $hist = Get-HistoricalMatches -Rows $slice -ModelYears $Config.ModelYears -K $Config.MatchCount -MinGapDays $Config.MatchMinGap
    $setup = Get-TradeSetup -Rows $slice -Signals $sig -Historical $hist -Events $null
    if ($setup.status -eq 'na') { continue }
    $new.Add((New-SetupLogEntry -Row $rows[$t] -Setup $setup -Historical $hist -Events $null -Backfill $true))
    if ($new.Count % 25 -eq 0) { Write-Log ("{0} dage beregnet ({1:N0} sek)" -f $new.Count, $sw.Elapsed.TotalSeconds) }
}

foreach ($e in $new) { $existing[$e.date] = $e }
Save-SetupLog $logPath @($existing.Values)
$summary = Update-SetupLog -Path $logPath -Rows $rows -Entry $null   # Evaluerer udfald og beregner statistik

Write-Log ("Færdig: {0} nye dage. Log indeholder {1} setups. Tid {2:N0} sek" -f $new.Count, $summary.total, $sw.Elapsed.TotalSeconds)
foreach ($k in @('green', 'yellow', 'red', 'all')) {
    $g = $summary.groups[$k]
    Write-Log ("{0,-6} n={1,4} afsluttede={2,4} T1 først={3,5}% stop først={4,5}% gns. R={5}" -f $k, $g.n, $g.closed, $g.t1Pct, $g.stopPct, $g.avgR)
}
Write-Log 'Kør .\Update-TSLA.ps1 for at få statistikken med på siden.'
