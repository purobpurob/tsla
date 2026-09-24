# Fase 2: Historiske lignende setups (nærmeste naboer)
#
# Metode
# 1. Hver handelsdag beskrives med 9 tal (features). Alle er skalafri, så en dag i 2022 kan
#    sammenlignes med en dag i 2026 selvom kursen er en helt anden.
# 2. Hver feature standardiseres (z-score) over søgevinduet, så ingen feature fylder mere end andre.
# 3. Afstand = kvadratrod af det vægtede gennemsnit af de kvadrerede z-forskelle (RMS i z-enheder).
# 4. De K dage med mindst afstand vælges. Matches skal ligge mindst MinGapDays handelsdage fra
#    hinanden, ellers tæller den samme situation flere gange.
# 5. For hvert match måles hvad der faktisk skete bagefter. Resultatet sammenlignes med en baseline:
#    alle dage i søgevinduet. Så kan man se om matchene er bedre eller dårligere end en tilfældig dag.
#
# Kun data til og med dagen selv bruges i features. Ingen fremtidsdata.

$script:FeatureDefs = @(
    [ordered]@{ key = 'rsi14';       label = 'RSI 14';                  unit = '' }
    [ordered]@{ key = 'distEma20';   label = 'Afstand til 20 EMA';      unit = '%' }
    [ordered]@{ key = 'distSma50';   label = 'Afstand til 50 SMA';      unit = '%' }
    [ordered]@{ key = 'distSma200';  label = 'Afstand til 200 SMA';     unit = '%' }
    [ordered]@{ key = 'macdHistAtr'; label = 'MACD-histogram / ATR';    unit = '' }
    [ordered]@{ key = 'volRatio';    label = 'Volumen / 20d gns.';      unit = 'x' }
    [ordered]@{ key = 'atrPctRank';  label = 'ATR percentil 1 år';      unit = '' }
    [ordered]@{ key = 'distHigh52w'; label = 'Afstand til 52u high';    unit = '%' }
    [ordered]@{ key = 'sma50Slope';  label = '50 SMA hældning 10 dage'; unit = '%' }
)

function Get-FeatureVector {
    # Returnerer [double[]] i samme rækkefølge som FeatureDefs, eller $null hvis noget mangler.
    # volRatio logges i beregningen fordi den er skæv (1x og 3x er ikke "lige langt" fra 2x)
    param([object[]]$Rows, [int]$i)
    if ($i -lt 10) { return $null }
    $r = $Rows[$i]
    $p = $Rows[$i - 10]
    if ($null -eq $r.Rsi14 -or $null -eq $r.DistEma20 -or $null -eq $r.DistSma50 -or $null -eq $r.DistSma200 -or
        $null -eq $r.MacdHist -or $null -eq $r.Atr14 -or $null -eq $r.VolRatio -or $null -eq $r.AtrPctRank -or
        $null -eq $r.DistHigh52w -or $null -eq $r.Sma50 -or $null -eq $p.Sma50 -or $r.Atr14 -le 0 -or $r.VolRatio -le 0) {
        return $null
    }
    return [double[]]@(
        $r.Rsi14,
        $r.DistEma20,
        $r.DistSma50,
        $r.DistSma200,
        ($r.MacdHist / $r.Atr14),
        [math]::Log($r.VolRatio),
        $r.AtrPctRank,
        $r.DistHigh52w,
        (($r.Sma50 / $p.Sma50 - 1) * 100)
    )
}

function Get-Quantile([double[]]$Sorted, [double]$Q) {
    # Lineær interpolation (samme som numpy/Excel PERCENTILE.INC). $Sorted skal være sorteret.
    $n = $Sorted.Count
    if ($n -eq 0) { return $null }
    if ($n -eq 1) { return $Sorted[0] }
    $pos = ($n - 1) * $Q
    $lo = [math]::Floor($pos)
    $hi = [math]::Ceiling($pos)
    return $Sorted[$lo] + ($Sorted[$hi] - $Sorted[$lo]) * ($pos - $lo)
}

function Get-Stats([double[]]$Values) {
    $s = [double[]]($Values | Sort-Object)
    $n = $s.Count
    $pos = @($s | Where-Object { $_ -gt 0 }).Count
    $sum = 0.0; foreach ($v in $s) { $sum += $v }
    return [ordered]@{
        n           = $n
        pctPositive = [math]::Round(100.0 * $pos / $n, 1)
        median      = [math]::Round((Get-Quantile $s 0.5), 2)
        mean        = [math]::Round($sum / $n, 2)
        p25         = [math]::Round((Get-Quantile $s 0.25), 2)
        p75         = [math]::Round((Get-Quantile $s 0.75), 2)
    }
}

function Get-PercentileOf([double[]]$Values, [double]$X) {
    # Andel af værdier der er lavere end X, 0-100
    $lower = 0
    foreach ($v in $Values) { if ($v -lt $X) { $lower++ } }
    return [math]::Round(100.0 * $lower / $Values.Count, 0)
}

function Get-HistoricalMatches {
    param(
        [object[]]$Rows,
        [int]$ModelYears = 5,
        [int]$K = 40,
        [int]$MinGapDays = 5,
        [int[]]$Horizons = @(2, 3, 5, 10, 15, 20),
        [int]$PathBack = 10,
        [double[]]$Weights = $null
    )
    $n = $Rows.Count
    $nf = $script:FeatureDefs.Count
    if (-not $Weights) { $Weights = [double[]](@(1.0) * $nf) }
    $maxH = ($Horizons | Measure-Object -Maximum).Maximum
    $last = $n - 1

    $current = Get-FeatureVector $Rows $last
    if ($null -eq $current) { return [ordered]@{ status = 'insufficient'; reason = 'Aktuel dag mangler indikatorer' } }

    # Søgevindue: dage inden for ModelYears, med fuld fremtid (maxH dage) og nok fortid til grafen
    $cutoff = ([datetime]$Rows[$last].Date).AddYears(-$ModelYears).ToString('yyyy-MM-dd')
    $cand = New-Object System.Collections.Generic.List[int]
    $vec = @{}
    for ($i = $PathBack; $i -le $last - $maxH; $i++) {
        if ($Rows[$i].Date -lt $cutoff) { continue }
        $f = Get-FeatureVector $Rows $i
        if ($null -eq $f) { continue }
        $cand.Add($i); $vec[$i] = $f
    }
    if ($cand.Count -lt $K * 3) { return [ordered]@{ status = 'insufficient'; reason = "Kun $($cand.Count) brugbare dage i søgevinduet" } }

    # Standardisering over søgevinduet
    $mean = New-Object double[] $nf
    $std = New-Object double[] $nf
    foreach ($i in $cand) { for ($j = 0; $j -lt $nf; $j++) { $mean[$j] += $vec[$i][$j] } }
    for ($j = 0; $j -lt $nf; $j++) { $mean[$j] /= $cand.Count }
    foreach ($i in $cand) { for ($j = 0; $j -lt $nf; $j++) { $d = $vec[$i][$j] - $mean[$j]; $std[$j] += $d * $d } }
    for ($j = 0; $j -lt $nf; $j++) { $std[$j] = [math]::Sqrt($std[$j] / ($cand.Count - 1)); if ($std[$j] -eq 0) { $std[$j] = 1 } }
    $wSum = 0.0; foreach ($w in $Weights) { $wSum += $w }

    # Afstand for alle kandidater
    $dist = New-Object System.Collections.Generic.List[object]
    foreach ($i in $cand) {
        $s = 0.0
        for ($j = 0; $j -lt $nf; $j++) {
            $z = ($vec[$i][$j] - $current[$j]) / $std[$j]
            $s += $Weights[$j] * $z * $z
        }
        $dist.Add([pscustomobject]@{ Index = $i; Distance = [math]::Sqrt($s / $wSum) })
    }

    # Grådigt valg med minimumsafstand i tid. Ved lige afstand vinder den tidligste dag.
    $picked = New-Object System.Collections.Generic.List[int]
    $pickedDist = @{}
    foreach ($d in ($dist | Sort-Object Distance, Index)) {
        $ok = $true
        foreach ($p in $picked) { if ([math]::Abs($p - $d.Index) -lt $MinGapDays) { $ok = $false; break } }
        if ($ok) { $picked.Add($d.Index); $pickedDist[$d.Index] = $d.Distance }
        if ($picked.Count -ge $K) { break }
    }

    # Outcomes
    $ret = { param($i, $h) ($Rows[$i + $h].Close / $Rows[$i].Close - 1) * 100 }
    $excursion = {
        param($i, $h)
        $hi = $Rows[$i + 1].High; $lo = $Rows[$i + 1].Low
        for ($k = 2; $k -le $h; $k++) {
            if ($Rows[$i + $k].High -gt $hi) { $hi = $Rows[$i + $k].High }
            if ($Rows[$i + $k].Low -lt $lo) { $lo = $Rows[$i + $k].Low }
        }
        @((($hi / $Rows[$i].Close - 1) * 100), (($lo / $Rows[$i].Close - 1) * 100))
    }
    $exWindows = @(5, 10, 20) | Where-Object { $_ -le $maxH }

    $matchList = New-Object System.Collections.Generic.List[object]
    foreach ($i in ($picked | Sort-Object)) {
        $o = [ordered]@{}
        foreach ($h in $Horizons) { $o["d$h"] = [math]::Round((& $ret $i $h), 2) }
        $mfe = [ordered]@{}; $mae = [ordered]@{}
        foreach ($w in $exWindows) { $e = & $excursion $i $w; $mfe["d$w"] = [math]::Round($e[0], 2); $mae["d$w"] = [math]::Round($e[1], 2) }
        $path = New-Object System.Collections.Generic.List[double]
        for ($k = -$PathBack; $k -le $maxH; $k++) { $path.Add([math]::Round($Rows[$i + $k].Close / $Rows[$i].Close * 100, 2)) }
        $matchList.Add([ordered]@{
            date     = $Rows[$i].Date
            close    = [math]::Round($Rows[$i].Close, 2)
            distance = [math]::Round($pickedDist[$i], 3)
            returns  = $o
            maxUp    = $mfe
            maxDown  = $mae
            path     = $path.ToArray()
        })
    }

    # Statistik for matches og baseline (alle kandidater)
    $horizonStats = New-Object System.Collections.Generic.List[object]
    foreach ($h in $Horizons) {
        $mv = [double[]]@($picked | ForEach-Object { & $ret $_ $h })
        $bv = [double[]]@($cand | ForEach-Object { & $ret $_ $h })
        $ms = Get-Stats $mv
        $bs = Get-Stats $bv
        $horizonStats.Add([ordered]@{
            days       = $h
            matches    = $ms
            baseline   = $bs
            edgePositive = [math]::Round($ms.pctPositive - $bs.pctPositive, 1)
            edgeMedian   = [math]::Round($ms.median - $bs.median, 2)
        })
    }

    $excStats = New-Object System.Collections.Generic.List[object]
    foreach ($w in $exWindows) {
        $up = [double[]]@($matchList | ForEach-Object { $_.maxUp["d$w"] })
        $dn = [double[]]@($matchList | ForEach-Object { $_.maxDown["d$w"] })
        $upS = [double[]]($up | Sort-Object); $dnS = [double[]]($dn | Sort-Object)
        $excStats.Add([ordered]@{
            days = $w
            maxUpMedian = [math]::Round((Get-Quantile $upS 0.5), 2)
            maxDownMedian = [math]::Round((Get-Quantile $dnS 0.5), 2)
            maxDownP25 = [math]::Round((Get-Quantile $dnS 0.25), 2)
        })
    }

    # Kursforløb: percentiler pr. dag relativt til setup-dagen (=100)
    $bands = New-Object System.Collections.Generic.List[object]
    $len = $PathBack + $maxH + 1
    for ($k = 0; $k -lt $len; $k++) {
        $col = [double[]]($matchList | ForEach-Object { $_.path[$k] } | Sort-Object)
        $bands.Add([ordered]@{ t = $k - $PathBack; p25 = [math]::Round((Get-Quantile $col 0.25), 2); p50 = [math]::Round((Get-Quantile $col 0.5), 2); p75 = [math]::Round((Get-Quantile $col 0.75), 2) })
    }
    $curPath = New-Object System.Collections.Generic.List[double]
    for ($k = -$PathBack; $k -le 0; $k++) { $curPath.Add([math]::Round($Rows[$last + $k].Close / $Rows[$last].Close * 100, 2)) }

    # Feature-sammenligning: aktuel værdi, percentil i historikken og median blandt matches
    $features = New-Object System.Collections.Generic.List[object]
    for ($j = 0; $j -lt $nf; $j++) {
        $all = [double[]]@($cand | ForEach-Object { $vec[$_][$j] })
        $mm = [double[]]@($picked | ForEach-Object { $vec[$_][$j] } | Sort-Object)
        $cv = $current[$j]; $med = Get-Quantile $mm 0.5
        if ($script:FeatureDefs[$j].key -eq 'volRatio') { $cv = [math]::Exp($cv); $med = [math]::Exp($med) }
        $features.Add([ordered]@{
            key          = $script:FeatureDefs[$j].key
            label        = $script:FeatureDefs[$j].label
            unit         = $script:FeatureDefs[$j].unit
            current      = [math]::Round($cv, 2)
            matchMedian  = [math]::Round($med, 2)
            percentile   = Get-PercentileOf $all $current[$j]
            weight       = $Weights[$j]
        })
    }

    $dists = [double[]]($picked | ForEach-Object { $pickedDist[$_] } | Sort-Object)
    $medDist = Get-Quantile $dists 0.5
    $quality = if ($medDist -lt 0.5) { 'tæt' } elseif ($medDist -lt 0.8) { 'moderat' } else { 'svag' }

    return [ordered]@{
        status        = 'ok'
        method        = 'Nærmeste naboer på 9 standardiserede features'
        searchFrom    = $Rows[$cand[0]].Date
        searchTo      = $Rows[$cand[$cand.Count - 1]].Date
        candidates    = $cand.Count
        similarSetups = $matchList.Count
        minGapDays    = $MinGapDays
        medianDistance = [math]::Round($medDist, 3)
        quality       = $quality
        qualityRule   = 'Median afstand i z-enheder. Under 0,5: tæt. 0,5-0,8: moderat. Over 0,8: svag.'
        horizons      = $horizonStats.ToArray()
        excursions    = $excStats.ToArray()
        features      = $features.ToArray()
        pathBack      = $PathBack
        bands         = $bands.ToArray()
        currentPath   = $curPath.ToArray()
        matches       = $matchList.ToArray()
    }
}
