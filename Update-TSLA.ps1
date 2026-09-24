<#
.SYNOPSIS
    TSLA Swing Trader - datamotor (Fase 1).
    Henter daglige kurser, beregner indikatorer og signaler, skriver JSON og pusher til GitHub.

.PARAMETER NoGit
    Spring commit og push over.

.PARAMETER Provider
    Overstyr datakilde fra Config.ps1 ('Yahoo', 'Tiingo' eller 'File').

.PARAMETER SampleFile
    Sti til en fil i Yahoo chart-format. Bruges sammen med -Provider File til test uden netværk.

.PARAMETER Force
    Skriv JSON selvom data er uændrede.

.EXAMPLE
    .\Update-TSLA.ps1
    .\Update-TSLA.ps1 -NoGit
    .\Update-TSLA.ps1 -Provider File -SampleFile .\Tests\sample.json -NoGit
#>
[CmdletBinding()]
param(
    [switch]$NoGit,
    [string]$Provider,
    [string]$SampleFile,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 1.0

# Windows PowerShell 5.1 serialiserer ellers indlejrede arrays som {"value":[...],"Count":n}
if ($PSVersionTable.PSVersion.Major -lt 6) { Remove-TypeData System.Array -ErrorAction SilentlyContinue }

$Root = $PSScriptRoot
. (Join-Path $Root 'Config.ps1')
. (Join-Path (Join-Path $Root 'Engine') 'DataProvider.ps1')
. (Join-Path (Join-Path $Root 'Engine') 'Indicators.ps1')
. (Join-Path (Join-Path $Root 'Engine') 'Signals.ps1')

$DataDir  = Join-Path $Root $Config.DataDir
$CacheDir = Join-Path $Root $Config.CacheDir
$LogDir   = Join-Path $Root $Config.LogDir
foreach ($d in @($DataDir, $CacheDir, $LogDir)) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d | Out-Null } }

$LogFile = Join-Path $LogDir ("update-{0}.log" -f (Get-Date -Format 'yyyyMMdd'))
function Write-Log([string]$Message, [string]$Level = 'INFO') {
    $line = "{0} [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    if ($Level -eq 'ERROR') { Write-Host $line -ForegroundColor Red }
    elseif ($Level -eq 'WARN') { Write-Host $line -ForegroundColor Yellow }
    else { Write-Host $line }
}

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
function Write-JsonFile($Path, $Object, [switch]$Compress) {
    $json = if ($Compress) { $Object | ConvertTo-Json -Depth 8 -Compress } else { $Object | ConvertTo-Json -Depth 8 }
    [IO.File]::WriteAllText($Path, $json, $Utf8NoBom)
}

function Rnd($Value, [int]$Digits = 2) {
    if ($null -eq $Value) { return $null }
    return [math]::Round([double]$Value, $Digits)
}

function Get-Sha256([string]$Text) {
    $sha = [Security.Cryptography.SHA256]::Create()
    $bytes = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))
    return -join ($bytes | ForEach-Object { $_.ToString('x2') })
}

function Get-NewYorkNow {
    foreach ($id in @('Eastern Standard Time', 'America/New_York')) {
        try { return [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::UtcNow, $id) } catch { }
    }
    return [DateTime]::UtcNow.AddHours(-4)
}

function Invoke-Git([string[]]$GitArgs) {
    # Git skriver statusbeskeder til stderr. Windows PowerShell 5.1 gør dem til fejl når
    # ErrorActionPreference er 'Stop'. Derfor 'Continue' her og kun exit-koden afgør om det gik godt.
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & git -C $Root @GitArgs 2>&1 | ForEach-Object { "$_" }
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $old
    }
    if ($code -ne 0) { throw "git $($GitArgs -join ' ') fejlede (exit $code): $($out -join ' | ')" }
    return $out
}

try {
    Write-Log '=== Start opdatering ==='
    $sw = [Diagnostics.Stopwatch]::StartNew()

    # 1. Hent data (med fallback)
    $prov = if ($Provider) { $Provider } else { $Config.DataProvider }
    $result = $null
    try {
        $result = Get-DailyData -Config $Config -Provider $prov -SampleFile $SampleFile
    } catch {
        Write-Log "Provider $prov fejlede: $($_.Exception.Message)" 'WARN'
        if ($Config.FallbackProvider -and -not $Provider) {
            $prov = $Config.FallbackProvider
            Write-Log "Prøver fallback: $prov"
            $result = Get-DailyData -Config $Config -Provider $prov
        } else { throw }
    }
    Write-Log "Hentet $($result.Bars.Count) bars fra $($result.Quote.Source)"

    # 2. Opdater historik i cache
    $cacheFile = Join-Path $CacheDir "$($Config.Symbol)_daily.json"
    $cached = @()
    if (Test-Path $cacheFile) {
        # ForEach-Object udfolder arrayet. Nødvendigt i Windows PowerShell 5.1
        $cached = @(Get-Content -Raw $cacheFile | ConvertFrom-Json | ForEach-Object { $_ })
        Write-Log "Cache: $($cached.Count) bars"
    }
    $bars = Merge-BarCache -Cached $cached -Fresh $result.Bars
    Write-JsonFile $cacheFile $bars -Compress

    $warnings = @(Test-Bars -Bars $bars)
    foreach ($w in $warnings) { Write-Log $w 'WARN' }

    # 3. Indikatorer
    $rows = Add-Indicators -Bars $bars
    $last = $rows[-1]
    $prev = $rows[-2]
    Write-Log ("Seneste bar {0}: close {1}" -f $last.Date, (Rnd $last.Close))

    # 4. Signaler
    $signals = Get-TechnicalSignals -Rows $rows
    $trend = Get-TrendSummary -Signals $signals

    # Er seneste dagsbar afsluttet? (NYSE lukker 16:00 New York-tid)
    $ny = Get-NewYorkNow
    $nyDate = $ny.ToString('yyyy-MM-dd')
    $barComplete = ($last.Date -lt $nyDate) -or ($ny.Hour -ge 16)

    $price = if ($result.Quote.Price) { $result.Quote.Price } else { $last.Close }
    $prevClose = $prev.Close   # Seneste bar er enten i dag (ufærdig) eller sidste handelsdag. Forrige bar er dagen før.
    $change = $price - $prevClose

    # 5. Byg JSON
    $summary = [ordered]@{
        schemaVersion = 1
        symbol        = $Config.Symbol
        generatedAt   = $null   # sættes nedenfor
        dataHash      = $null
        source        = $result.Quote.Source
        provider      = $prov
        quote         = [ordered]@{
            price         = Rnd $price
            time          = $result.Quote.Time
            previousClose = Rnd $prevClose
            change        = Rnd $change
            changePct     = Rnd ($change / $prevClose * 100)
            currency      = $result.Quote.Currency
        }
        lastBar       = [ordered]@{
            date     = $last.Date
            complete = $barComplete
            open = Rnd $last.Open; high = Rnd $last.High; low = Rnd $last.Low; close = Rnd $last.Close; volume = $last.Volume
        }
        trend         = $trend
        indicators    = [ordered]@{
            ema20       = Rnd $last.Ema20
            sma50       = Rnd $last.Sma50
            sma200      = Rnd $last.Sma200
            rsi14       = Rnd $last.Rsi14 1
            macd        = Rnd $last.Macd 3
            macdSignal  = Rnd $last.MacdSignal 3
            macdHist    = Rnd $last.MacdHist 3
            atr14       = Rnd $last.Atr14
            atrPct      = Rnd $last.AtrPct
            atrPctRank  = Rnd $last.AtrPctRank 0
            avgVolume20 = Rnd $last.AvgVol20 0
            volumeRatio = Rnd $last.VolRatio
            high20      = Rnd $last.High20
            low20       = Rnd $last.Low20
            high52w     = Rnd $last.High52w
            low52w      = Rnd $last.Low52w
            distEma20   = Rnd $last.DistEma20
            distSma50   = Rnd $last.DistSma50
            distSma200  = Rnd $last.DistSma200
            distHigh52w = Rnd $last.DistHigh52w
            distLow52w  = Rnd $last.DistLow52w
        }
        signals       = $signals
        # Pladsholdere til senere faser, så frontend kan vise at de endnu ikke er bygget
        setup         = [ordered]@{ status = 'pending'; phase = 3 }
        historical    = [ordered]@{ status = 'pending'; phase = 2 }
        news          = [ordered]@{ status = 'pending'; phase = 4 }
        events        = [ordered]@{ status = 'pending'; phase = 5 }
        dataWarnings  = $warnings
        history       = [ordered]@{ bars = $bars.Count; firstDate = $bars[0].Date; lastDate = $last.Date; file = 'data/tsla-history.json' }
    }

    $chartRows = $rows | Select-Object -Last $Config.ChartBars
    $histRows = New-Object System.Collections.Generic.List[object]
    foreach ($x in $chartRows) {
        $histRows.Add([object[]]@($x.Date, (Rnd $x.Open), (Rnd $x.High), (Rnd $x.Low), (Rnd $x.Close), $x.Volume,
            (Rnd $x.Ema20), (Rnd $x.Sma50), (Rnd $x.Sma200), (Rnd $x.Rsi14 1),
            (Rnd $x.Macd 3), (Rnd $x.MacdSignal 3), (Rnd $x.MacdHist 3), (Rnd $x.Atr14)))
    }
    $history = [ordered]@{
        symbol  = $Config.Symbol
        columns = @('date','open','high','low','close','volume','ema20','sma50','sma200','rsi14','macd','macdSignal','macdHist','atr14')
        rows    = $histRows.ToArray()
    }

    # Hash af indholdet uden tidsstempel. Uændret hash = ingen skrivning og intet commit.
    $historyJson = $history | ConvertTo-Json -Depth 8 -Compress
    $hash = Get-Sha256 (($summary | ConvertTo-Json -Depth 8 -Compress) + $historyJson)
    $summary.dataHash = $hash
    $summary.generatedAt = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')

    $summaryFile = Join-Path $DataDir 'tsla.json'
    $historyFile = Join-Path $DataDir 'tsla-history.json'
    $oldHash = $null
    if (Test-Path $summaryFile) {
        try { $oldHash = (Get-Content -Raw $summaryFile | ConvertFrom-Json).dataHash } catch { }
    }

    if ($oldHash -eq $hash -and -not $Force) {
        Write-Log 'Data er uændrede. Ingen filer skrevet.'
    } else {
        # 6. Valider JSON inden den skrives
        $check = ($summary | ConvertTo-Json -Depth 8) | ConvertFrom-Json
        if (-not $check.quote.price -or $check.signals.Count -lt 1) { throw 'JSON-validering fejlede: pris eller signaler mangler' }
        $checkH = $historyJson | ConvertFrom-Json
        if ($checkH.rows.Count -lt 50 -or $checkH.rows[0].Count -ne $checkH.columns.Count) { throw 'JSON-validering fejlede: historik har forkert form' }

        Write-JsonFile $summaryFile $summary
        [IO.File]::WriteAllText($historyFile, $historyJson, $Utf8NoBom)
        Write-Log "Skrev $summaryFile og $historyFile"
    }

    # 7. Git
    if ($Config.GitEnabled -and -not $NoGit) {
        $status = Invoke-Git @('status', '--porcelain', '--', $Config.DataDir)
        if ([string]::IsNullOrWhiteSpace(($status | Out-String))) {
            Write-Log 'Ingen ændringer i data. Intet commit.'
        } else {
            Invoke-Git @('add', '--', $Config.DataDir) | Out-Null
            Invoke-Git @('commit', '-m', "$($Config.GitCommitMessage) $($last.Date)") | Out-Null
            Invoke-Git @('push') | Out-Null
            Write-Log 'Commit og push gennemført'
        }
    }

    Write-Log ("=== Færdig på {0:N1} sek ===" -f $sw.Elapsed.TotalSeconds)
    exit 0
}
catch {
    Write-Log "FEJL: $($_.Exception.Message)" 'ERROR'
    Write-Log $_.ScriptStackTrace 'ERROR'
    exit 1
}