# Tekniske indikatorer. Alle funktioner tager [double[]] og returnerer [object[]] af samme længde.
# Værdier i opvarmningsperioden er $null.
# Definitioner (standard):
#   SMA(n)   simpelt gennemsnit af de seneste n lukkekurser
#   EMA(n)   alpha = 2/(n+1), startværdi = SMA af de første n værdier
#   RSI(14)  Wilder smoothing, startværdi = simpelt gennemsnit af de første 14 ændringer
#   MACD     EMA12 - EMA26, signal = EMA9 af MACD, histogram = MACD - signal
#   ATR(14)  Wilder smoothing af True Range, startværdi = simpelt gennemsnit af de første 14 TR

function Get-SMA([double[]]$Values, [int]$Period) {
    $n = $Values.Count
    $out = New-Object object[] $n
    $sum = 0.0
    for ($i = 0; $i -lt $n; $i++) {
        $sum += $Values[$i]
        if ($i -ge $Period) { $sum -= $Values[$i - $Period] }
        if ($i -ge $Period - 1) { $out[$i] = $sum / $Period }
    }
    return ,$out
}

function Get-EMA([object[]]$Values, [int]$Period) {
    # Accepterer $null i starten (bruges til MACD-signal)
    $n = $Values.Count
    $out = New-Object object[] $n
    $alpha = 2.0 / ($Period + 1)
    $start = 0
    while ($start -lt $n -and $null -eq $Values[$start]) { $start++ }
    if ($n - $start -lt $Period) { return ,$out }

    $seed = 0.0
    for ($i = $start; $i -lt $start + $Period; $i++) { $seed += [double]$Values[$i] }
    $prev = $seed / $Period
    $out[$start + $Period - 1] = $prev
    for ($i = $start + $Period; $i -lt $n; $i++) {
        $prev = ([double]$Values[$i] - $prev) * $alpha + $prev
        $out[$i] = $prev
    }
    return ,$out
}

function Get-RSI([double[]]$Close, [int]$Period = 14) {
    $n = $Close.Count
    $out = New-Object object[] $n
    if ($n -le $Period) { return ,$out }
    $gain = 0.0; $loss = 0.0
    for ($i = 1; $i -le $Period; $i++) {
        $d = $Close[$i] - $Close[$i - 1]
        if ($d -gt 0) { $gain += $d } else { $loss -= $d }
    }
    $avgG = $gain / $Period; $avgL = $loss / $Period
    $out[$Period] = if ($avgL -eq 0) { 100.0 } else { 100 - 100 / (1 + $avgG / $avgL) }
    for ($i = $Period + 1; $i -lt $n; $i++) {
        $d = $Close[$i] - $Close[$i - 1]
        $g = if ($d -gt 0) { $d } else { 0.0 }
        $l = if ($d -lt 0) { -$d } else { 0.0 }
        $avgG = ($avgG * ($Period - 1) + $g) / $Period
        $avgL = ($avgL * ($Period - 1) + $l) / $Period
        $out[$i] = if ($avgL -eq 0) { 100.0 } else { 100 - 100 / (1 + $avgG / $avgL) }
    }
    return ,$out
}

function Get-MACD([double[]]$Close, [int]$Fast = 12, [int]$Slow = 26, [int]$SignalPeriod = 9) {
    $n = $Close.Count
    $ef = Get-EMA $Close $Fast
    $es = Get-EMA $Close $Slow
    $macd = New-Object object[] $n
    for ($i = 0; $i -lt $n; $i++) {
        if ($null -ne $ef[$i] -and $null -ne $es[$i]) { $macd[$i] = $ef[$i] - $es[$i] }
    }
    $sig = Get-EMA $macd $SignalPeriod
    $hist = New-Object object[] $n
    for ($i = 0; $i -lt $n; $i++) {
        if ($null -ne $macd[$i] -and $null -ne $sig[$i]) { $hist[$i] = $macd[$i] - $sig[$i] }
    }
    return @{ Macd = $macd; Signal = $sig; Hist = $hist }
}

function Get-ATR([double[]]$High, [double[]]$Low, [double[]]$Close, [int]$Period = 14) {
    $n = $Close.Count
    $tr = New-Object double[] $n
    $tr[0] = $High[0] - $Low[0]
    for ($i = 1; $i -lt $n; $i++) {
        $tr[$i] = [math]::Max($High[$i] - $Low[$i], [math]::Max([math]::Abs($High[$i] - $Close[$i - 1]), [math]::Abs($Low[$i] - $Close[$i - 1])))
    }
    $out = New-Object object[] $n
    if ($n -le $Period) { return ,$out }
    # Første TR bruges ikke (ingen forrige lukkekurs). Seed = gennemsnit af TR[1..Period]
    $sum = 0.0
    for ($i = 1; $i -le $Period; $i++) { $sum += $tr[$i] }
    $prev = $sum / $Period
    $out[$Period] = $prev
    for ($i = $Period + 1; $i -lt $n; $i++) {
        $prev = ($prev * ($Period - 1) + $tr[$i]) / $Period
        $out[$i] = $prev
    }
    return ,$out
}

function Get-RollingMax([double[]]$Values, [int]$Period) {
    $n = $Values.Count
    $out = New-Object object[] $n
    for ($i = $Period - 1; $i -lt $n; $i++) {
        $m = $Values[$i - $Period + 1]
        for ($j = $i - $Period + 2; $j -le $i; $j++) { if ($Values[$j] -gt $m) { $m = $Values[$j] } }
        $out[$i] = $m
    }
    return ,$out
}

function Get-RollingMin([double[]]$Values, [int]$Period) {
    $n = $Values.Count
    $out = New-Object object[] $n
    for ($i = $Period - 1; $i -lt $n; $i++) {
        $m = $Values[$i - $Period + 1]
        for ($j = $i - $Period + 2; $j -le $i; $j++) { if ($Values[$j] -lt $m) { $m = $Values[$j] } }
        $out[$i] = $m
    }
    return ,$out
}

function Get-PriorAverage([double[]]$Values, [int]$Period) {
    # Gennemsnit af de n foregående værdier, eksklusiv dagen selv.
    # Bruges til volumen, så dagens volumen sammenlignes med de 20 dage før.
    $n = $Values.Count
    $out = New-Object object[] $n
    $sma = Get-SMA $Values $Period
    for ($i = $Period; $i -lt $n; $i++) { $out[$i] = $sma[$i - 1] }
    return ,$out
}

function Get-PercentRank([object[]]$Values, [int]$Index, [int]$Lookback) {
    # Andel af de seneste $Lookback værdier (inkl. dagen) der er lavere end dagens værdi, 0-100
    $v = $Values[$Index]
    if ($null -eq $v) { return $null }
    $lower = 0; $count = 0
    for ($j = [math]::Max(0, $Index - $Lookback + 1); $j -le $Index; $j++) {
        if ($null -eq $Values[$j]) { continue }
        $count++
        if ($Values[$j] -lt $v) { $lower++ }
    }
    if ($count -lt 20) { return $null }
    return 100.0 * $lower / $count
}

function Get-PctDiff($a, $b) {
    if ($null -eq $a -or $null -eq $b -or $b -eq 0) { return $null }
    return ($a / $b - 1) * 100
}

function Add-Indicators {
    # Beregner alle indikatorer og returnerer en række pr. bar
    param([object[]]$Bars)
    $n = $Bars.Count
    $close = [double[]]($Bars | ForEach-Object { $_.Close })
    $high  = [double[]]($Bars | ForEach-Object { $_.High })
    $low   = [double[]]($Bars | ForEach-Object { $_.Low })
    $vol   = [double[]]($Bars | ForEach-Object { $_.Volume })

    $ema20  = Get-EMA $close 20
    $sma50  = Get-SMA $close 50
    $sma200 = Get-SMA $close 200
    $rsi    = Get-RSI $close 14
    $macd   = Get-MACD $close
    $atr    = Get-ATR $high $low $close 14
    $avgV20 = Get-PriorAverage $vol 20
    $hi20   = Get-RollingMax $high 20
    $lo20   = Get-RollingMin $low 20
    $hi52   = Get-RollingMax $high 252
    $lo52   = Get-RollingMin $low 252

    $atrPct = New-Object object[] $n
    for ($i = 0; $i -lt $n; $i++) { if ($null -ne $atr[$i]) { $atrPct[$i] = $atr[$i] / $close[$i] * 100 } }

    $rows = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt $n; $i++) {
        $b = $Bars[$i]
        $rows.Add([pscustomobject]@{
            Date       = $b.Date
            Open       = $b.Open
            High       = $b.High
            Low        = $b.Low
            Close      = $b.Close
            Volume     = $b.Volume
            Ema20      = $ema20[$i]
            Sma50      = $sma50[$i]
            Sma200     = $sma200[$i]
            Rsi14      = $rsi[$i]
            Macd       = $macd.Macd[$i]
            MacdSignal = $macd.Signal[$i]
            MacdHist   = $macd.Hist[$i]
            Atr14      = $atr[$i]
            AtrPct     = $atrPct[$i]
            AvgVol20   = $avgV20[$i]
            VolRatio   = if ($null -ne $avgV20[$i] -and $avgV20[$i] -gt 0) { $vol[$i] / $avgV20[$i] } else { $null }
            High20     = $hi20[$i]
            Low20      = $lo20[$i]
            High52w    = $hi52[$i]
            Low52w     = $lo52[$i]
            DistEma20  = Get-PctDiff $close[$i] $ema20[$i]
            DistSma50  = Get-PctDiff $close[$i] $sma50[$i]
            DistSma200 = Get-PctDiff $close[$i] $sma200[$i]
            DistHigh52w = Get-PctDiff $close[$i] $hi52[$i]
            DistLow52w  = Get-PctDiff $close[$i] $lo52[$i]
            AtrPctRank = Get-PercentRank $atrPct $i 252
        })
    }
    return $rows.ToArray()
}
