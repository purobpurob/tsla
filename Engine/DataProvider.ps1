# Datakilder. Alle providere returnerer samme form:
#   @{ Bars = @( [pscustomobject]@{ Date='yyyy-MM-dd'; Open; High; Low; Close; Volume } ... )
#      Quote = @{ Price; Time (UTC ISO); PreviousClose; Currency; Source } }
# Priserne er split-justerede. TSLA betaler ikke udbytte, så udbyttejustering er ikke relevant.

function Initialize-Tls {
    # Windows PowerShell 5.1 bruger ikke altid TLS 1.2 som standard
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch { }
}

function ConvertFrom-UnixToIso([long]$Seconds) {
    return [DateTimeOffset]::FromUnixTimeSeconds($Seconds).UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ssZ')
}

function ConvertFrom-YahooChart {
    param([Parameter(Mandatory)] $Json, [string]$Source = 'Yahoo Finance (chart v8)')

    if ($Json.chart.error) { throw "Yahoo fejl: $($Json.chart.error.description)" }
    $r = $Json.chart.result[0]
    if (-not $r -or -not $r.timestamp) { throw 'Yahoo returnerede ingen data' }

    $q = $r.indicators.quote[0]
    $gmtOffset = [long]$r.meta.gmtoffset
    $bars = New-Object System.Collections.Generic.List[object]

    for ($i = 0; $i -lt $r.timestamp.Count; $i++) {
        $o = $q.open[$i]; $h = $q.high[$i]; $l = $q.low[$i]; $c = $q.close[$i]; $v = $q.volume[$i]
        if ($null -eq $o -or $null -eq $h -or $null -eq $l -or $null -eq $c) { continue }
        # Tidsstempel + børsens UTC-offset giver den lokale handelsdato i New York
        $date = [DateTimeOffset]::FromUnixTimeSeconds([long]$r.timestamp[$i] + $gmtOffset).UtcDateTime.ToString('yyyy-MM-dd')
        $bars.Add([pscustomobject]@{
            Date   = $date
            Open   = [double]$o
            High   = [double]$h
            Low    = [double]$l
            Close  = [double]$c
            Volume = if ($null -eq $v) { [long]0 } else { [long]$v }
        })
    }

    $m = $r.meta
    $quote = @{
        Price         = [double]$m.regularMarketPrice
        Time          = if ($m.regularMarketTime) { ConvertFrom-UnixToIso ([long]$m.regularMarketTime) } else { $null }
        PreviousClose = $null
        Currency      = $m.currency
        Exchange      = $m.exchangeName
        Source        = $Source
    }
    return @{ Bars = $bars.ToArray(); Quote = $quote }
}

function Get-YahooDaily {
    param([string]$Symbol, [int]$Years, $Config)
    Initialize-Tls
    $range = "$($Years)y"
    $hosts = @('query1.finance.yahoo.com', 'query2.finance.yahoo.com')
    $lastError = $null
    foreach ($h in $hosts) {
        $url = "https://$h/v8/finance/chart/$($Symbol)?range=$range&interval=1d&includePrePost=false&events=split"
        try {
            $json = Invoke-RestMethod -Uri $url -UserAgent $Config.UserAgent -TimeoutSec $Config.TimeoutSec -ErrorAction Stop
            return ConvertFrom-YahooChart -Json $json
        } catch {
            $lastError = $_
            Write-Log "Yahoo via $h fejlede: $($_.Exception.Message)" 'WARN'
        }
    }
    throw "Yahoo fejlede på alle hosts: $lastError"
}

function Get-TiingoDaily {
    param([string]$Symbol, [int]$Years, $Config)
    Initialize-Tls
    $key = $env:TIINGO_API_KEY
    if (-not $key) { throw 'TIINGO_API_KEY er ikke sat som miljøvariabel' }

    $start = (Get-Date).AddYears(-$Years).ToString('yyyy-MM-dd')
    $url = "https://api.tiingo.com/tiingo/daily/$($Symbol.ToLower())/prices?startDate=$start"
    $headers = @{ Authorization = "Token $key"; 'Content-Type' = 'application/json' }
    $rows = Invoke-RestMethod -Uri $url -Headers $headers -UserAgent $Config.UserAgent -TimeoutSec $Config.TimeoutSec -ErrorAction Stop

    $bars = foreach ($row in $rows) {
        # Tiingo 'date' kan blive parset til DateTime af ConvertFrom-Json. Håndter begge.
        $d = if ($row.date -is [datetime]) { $row.date.ToString('yyyy-MM-dd') } else { ([string]$row.date).Substring(0, 10) }
        [pscustomobject]@{
            Date   = $d
            Open   = [double]$row.adjOpen
            High   = [double]$row.adjHigh
            Low    = [double]$row.adjLow
            Close  = [double]$row.adjClose
            Volume = [long]$row.adjVolume
        }
    }
    $bars = @($bars)
    $last = $bars[-1]
    return @{
        Bars  = $bars
        Quote = @{ Price = $last.Close; Time = $null; PreviousClose = $null; Currency = 'USD'; Exchange = $null; Source = 'Tiingo EOD' }
    }
}

function Get-FileDaily {
    # Til test uden netværk. Læser en fil i Yahoo chart-format.
    param([string]$Path)
    $json = Get-Content -Raw -Path $Path | ConvertFrom-Json
    return ConvertFrom-YahooChart -Json $json -Source "Fil: $(Split-Path -Leaf $Path)"
}

function Get-DailyData {
    param($Config, [string]$Provider, [string]$SampleFile)
    switch ($Provider) {
        'Yahoo'  { return Get-YahooDaily  -Symbol $Config.Symbol -Years $Config.HistoryYears -Config $Config }
        'Tiingo' { return Get-TiingoDaily -Symbol $Config.Symbol -Years $Config.HistoryYears -Config $Config }
        'File'   { return Get-FileDaily -Path $SampleFile }
        default  { throw "Ukendt provider: $Provider" }
    }
}

function ConvertTo-Bar($b) {
    # Normaliserer en bar. ConvertFrom-Json kan give DateTime eller decimal afhængigt af PowerShell-version.
    $d = if ($b.Date -is [datetime]) { $b.Date.ToString('yyyy-MM-dd') } else { ([string]$b.Date).Substring(0, 10) }
    return [pscustomobject]@{
        Date = $d; Open = [double]$b.Open; High = [double]$b.High; Low = [double]$b.Low; Close = [double]$b.Close; Volume = [long]$b.Volume
    }
}

function Merge-BarCache {
    # Fletter nye bars ind i cachen. Nye data vinder ved samme dato (dækker ufærdige dagsbars).
    param([object[]]$Cached, [object[]]$Fresh)
    $map = @{}
    foreach ($b in $Cached) { $n = ConvertTo-Bar $b; $map[$n.Date] = $n }
    foreach ($b in $Fresh)  { $n = ConvertTo-Bar $b; $map[$n.Date] = $n }
    return @($map.Values | Sort-Object Date)
}

function Test-Bars {
    # Returnerer liste af advarsler. Kaster fejl ved data der ikke kan bruges.
    param([object[]]$Bars, [int]$MinBars = 250)
    $warnings = New-Object System.Collections.Generic.List[string]
    if ($Bars.Count -lt $MinBars) { throw "For få bars: $($Bars.Count) (minimum $MinBars)" }

    for ($i = 0; $i -lt $Bars.Count; $i++) {
        $b = $Bars[$i]
        if ($b.Close -le 0 -or $b.High -lt $b.Low) { throw "Ugyldig bar $($b.Date): O=$($b.Open) H=$($b.High) L=$($b.Low) C=$($b.Close)" }
        if ($i -gt 0) {
            $gap = ([datetime]$b.Date - [datetime]$Bars[$i - 1].Date).TotalDays
            if ($gap -gt 5) { $warnings.Add("Hul i data: $($Bars[$i-1].Date) til $($b.Date) ($gap dage)") }
            $move = [math]::Abs($b.Close / $Bars[$i - 1].Close - 1)
            if ($move -gt 0.35) { $warnings.Add("Stor dagsbevægelse $($b.Date): $([math]::Round($move*100,1))%. Tjek for split") }
        }
    }
    return $warnings.ToArray()
}
