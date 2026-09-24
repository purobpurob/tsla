# Fase 3: Entry zone, stop, targets, risk/reward og samlet setup-status
#
# Kun long-setups (køb og sælg højere). Alle regler er faste og skrevet ud i forklaringerne.
#
# Niveauer
#   Support    = 20 EMA, 50 SMA, 200 SMA, 20-dages low og swing lows (seneste 120 dage) under kursen
#   Modstand   = 20-dages high, 52u high, 50/200 SMA og swing highs (seneste 250 dage) over kursen
#   Swing low/high = en dag hvis low/high er lavest/højest blandt de 3 dage før og efter
#
#   Entry high = seneste lukkekurs (ingen jagt over kursen)
#   Entry low  = nærmeste support mellem 0,25 og 1,5 ATR under kursen. Ingen support: kurs - 0,75 ATR
#   Stop       = nærmeste support under entry low minus 0,25 ATR buffer.
#                Risiko fra midten af entry-zonen holdes mellem 1 og 3 ATR (ellers 2 ATR-stop)
#   Target 1   = nærmeste modstand mindst 1 ATR over entry. Ingen modstand: entry + 2R
#   Target 2   = næste modstand mindst 1 ATR over Target 1. Ingen modstand: det højeste af T1 + 1,5 ATR og entry + 3R
#
# Historisk test
#   De samme procentafstande (stop, T1, T2) lægges på hvert af de historiske matches fra fase 2
#   med entry på matchets lukkekurs. Derefter tælles hvad der blev ramt først inden for 20 dage.
#   Rammes stop og target samme dag, tælles det som stop (forsigtigt).

$script:DaCulture = [Globalization.CultureInfo]'da-DK'
function Fmt-Usd($v) { return '$' + ([double]$v).ToString('N2', $script:DaCulture) }
function Fmt-Num($v, $f = 'N1') { return ([double]$v).ToString($f, $script:DaCulture) }

function Get-Pivots {
    param([object[]]$Rows, [int]$Lookback, [int]$Wing = 3, [ValidateSet('low', 'high')] [string]$Type)
    $n = $Rows.Count
    $out = New-Object System.Collections.Generic.List[object]
    $start = [math]::Max($Wing, $n - $Lookback)
    for ($j = $start; $j -le $n - 1 - $Wing; $j++) {
        $v = if ($Type -eq 'low') { $Rows[$j].Low } else { $Rows[$j].High }
        $ok = $true
        for ($k = $j - $Wing; $k -le $j + $Wing; $k++) {
            if ($k -eq $j) { continue }
            $w = if ($Type -eq 'low') { $Rows[$k].Low } else { $Rows[$k].High }
            if (($Type -eq 'low' -and $w -lt $v) -or ($Type -eq 'high' -and $w -gt $v)) { $ok = $false; break }
        }
        if ($ok) { $out.Add([pscustomobject]@{ Price = $v; Label = "Swing $Type $($Rows[$j].Date)" }) }
    }
    return $out.ToArray()
}

function Merge-Levels([object[]]$Levels) {
    # Slår niveauer sammen der ligger inden for 0,2% af hinanden, fx 20-dages high og 52u high samme dag
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($l in $Levels) {
        $prev = if ($out.Count) { $out[$out.Count - 1] } else { $null }
        if ($prev -and [math]::Abs($l.Price / $prev.Price - 1) -le 0.002) { $prev.Label = "$($prev.Label) / $($l.Label)" }
        else { $out.Add([pscustomobject]@{ Price = $l.Price; Label = $l.Label }) }
    }
    return ,$out.ToArray()
}

function New-Level($Price, $Label) { return [pscustomobject]@{ Price = [double]$Price; Label = $Label } }

function Get-TradeSetup {
    param([object[]]$Rows, [object[]]$Signals, $Historical, $Events)

    $n = $Rows.Count
    $r = $Rows[$n - 1]
    $c = $r.Close
    $atr = $r.Atr14
    if ($null -eq $atr -or $null -eq $r.Sma200) { return [ordered]@{ status = 'na'; reason = 'For lidt historik' } }

    # Support og modstand
    $supports = New-Object System.Collections.Generic.List[object]
    $resist = New-Object System.Collections.Generic.List[object]
    foreach ($m in @(@($r.Ema20, '20 EMA'), @($r.Sma50, '50 SMA'), @($r.Sma200, '200 SMA'))) {
        if ($m[0] -lt $c) { $supports.Add((New-Level $m[0] $m[1])) } else { $resist.Add((New-Level $m[0] $m[1])) }
    }
    $supports.Add((New-Level $r.Low20 '20-dages low'))
    if ($r.High20 -gt $c) { $resist.Add((New-Level $r.High20 '20-dages high')) }
    if ($r.High52w -gt $c) { $resist.Add((New-Level $r.High52w '52u high')) }
    foreach ($p in (Get-Pivots -Rows $Rows -Lookback 120 -Type low))  { if ($p.Price -lt $c) { $supports.Add($p) } }
    foreach ($p in (Get-Pivots -Rows $Rows -Lookback 250 -Type high)) { if ($p.Price -gt $c) { $resist.Add($p) } }
    $supports = Merge-Levels @($supports | Sort-Object Price -Descending)   # nærmeste først
    $resist = Merge-Levels @($resist | Sort-Object Price)                     # nærmeste først

    $why = [ordered]@{}
    $horizon = $null

    # Entry
    $entryHigh = $c
    $near = $supports | Where-Object { $_.Price -le $c - 0.25 * $atr -and $_.Price -ge $c - 1.5 * $atr } | Select-Object -First 1
    if ($near) {
        $entryLow = $near.Price
        $why.entry = "Fra $($near.Label) ($(Fmt-Usd $near.Price)) op til seneste lukkekurs. $($near.Label) er nærmeste support mellem 0,25 og 1,5 ATR under kursen."
    } else {
        $entryLow = $c - 0.75 * $atr
        $why.entry = "Ingen support mellem 0,25 og 1,5 ATR under kursen. Zonen går derfor fra 0,75 ATR under kursen op til lukkekursen."
    }
    $entry = ($entryLow + $entryHigh) / 2

    # Stop
    $below = $supports | Where-Object { $_.Price -lt $entryLow - 0.25 * $atr } | Select-Object -First 1
    if ($below) {
        $stop = $below.Price - 0.25 * $atr
        $why.stop = "0,25 ATR under $($below.Label) ($(Fmt-Usd $below.Price)), som er næste support under entry-zonen."
    } else {
        $stop = $entry - 2 * $atr
        $why.stop = "Ingen support under entry-zonen. Stop er 2 ATR under midten af zonen."
    }
    $risk = $entry - $stop
    if ($risk -gt 3 * $atr) {
        $stop = $entry - 2 * $atr
        $why.stop = "Nærmeste support lå mere end 3 ATR under entry. Stop er derfor 2 ATR under midten af zonen."
    } elseif ($risk -lt $atr) {
        $stop = $entry - $atr
        $why.stop = "Support lå under 1 ATR fra entry, hvilket er for tæt til TSLA's normale udsving. Stop er 1 ATR under midten af zonen."
    }
    $risk = $entry - $stop

    # Targets
    $t1L = $resist | Where-Object { $_.Price -ge $entry + $atr } | Select-Object -First 1
    if ($t1L) {
        $t1 = $t1L.Price
        $why.target1 = "$($t1L.Label) ($(Fmt-Usd $t1L.Price)) er nærmeste modstand mindst 1 ATR over entry."
    } else {
        $t1 = $entry + 2 * $risk
        $why.target1 = 'Ingen modstand over entry. Target 1 er sat til 2 gange risikoen (2R).'
    }
    $t2L = $resist | Where-Object { $_.Price -ge $t1 + $atr } | Select-Object -First 1
    if ($t2L) {
        $t2 = $t2L.Price
        $why.target2 = "$($t2L.Label) ($(Fmt-Usd $t2L.Price)) er næste modstand mindst 1 ATR over Target 1."
    } else {
        $t2 = [math]::Max($t1 + 1.5 * $atr, $entry + 3 * $risk)
        $why.target2 = 'Ingen modstand mindst 1 ATR over Target 1. Target 2 er det højeste af Target 1 + 1,5 ATR og 3R.'
    }
    $rr1 = ($t1 - $entry) / $risk
    $rr2 = ($t2 - $entry) / $risk

    # Historisk test på fase 2-matches
    $sim = $null
    if ($Historical -and $Historical.status -eq 'ok') {
        $idx = @{}
        for ($i = 0; $i -lt $n; $i++) { $idx[$Rows[$i].Date] = $i }
        $sPct = $stop / $entry - 1; $t1Pct = $t1 / $entry - 1; $t2Pct = $t2 / $entry - 1
        $hitT1 = 0; $hitT2 = 0; $hitStop = 0; $none = 0; $sumR = 0.0
        $days = New-Object System.Collections.Generic.List[int]
        foreach ($mt in $Historical.matches) {
            $m = $idx[$mt.date]
            if ($null -eq $m -or $m + 20 -ge $n) { continue }
            $e = $Rows[$m].Close
            $sp = $e * (1 + $sPct); $p1 = $e * (1 + $t1Pct); $p2 = $e * (1 + $t2Pct)
            $res = 'none'; $t1Day = $null; $t2Reached = $false
            for ($k = 1; $k -le 20; $k++) {
                $b = $Rows[$m + $k]
                if ($b.Low -le $sp) { $res = 'stop'; break }
                if ($b.High -ge $p1 -and $null -eq $t1Day) { $t1Day = $k; $res = 't1' }
                if ($b.High -ge $p2) { $t2Reached = $true; break }
            }
            # Target 1 tæller kun hvis det blev ramt før et eventuelt stop
            if ($res -eq 'stop' -and $null -ne $t1Day) { $res = 't1' }
            switch ($res) {
                't1'   { $hitT1++; $days.Add($t1Day); $sumR += $rr1; if ($t2Reached) { $hitT2++ } }
                'stop' { $hitStop++; $sumR += -1 }
                default { $none++; $sumR += ($Rows[$m + 20].Close - $e) / ($e - $sp) }
            }
        }
        $tot = $hitT1 + $hitStop + $none
        $horizon = $null
        if ($days.Count -ge 5) {
            $sd = [double[]]($days | Sort-Object)
            $lo = [math]::Max(2, [math]::Round((Get-Quantile $sd 0.25)))
            $hi = [math]::Max($lo + 1, [math]::Round((Get-Quantile $sd 0.75)))
            $horizon = [ordered]@{ low = $lo; high = $hi; source = 'Dage til Target 1 blandt matches der ramte (25-75%)' }
        }
        $sim = [ordered]@{
            matches      = $tot
            target1First = $hitT1
            target2      = $hitT2
            stopFirst    = $hitStop
            neither      = $none
            target1Pct   = if ($tot) { [math]::Round(100.0 * $hitT1 / $tot, 1) } else { $null }
            stopPct      = if ($tot) { [math]::Round(100.0 * $hitStop / $tot, 1) } else { $null }
            avgR         = if ($tot) { [math]::Round($sumR / $tot, 2) } else { $null }
            rule         = 'Samme procentafstand til stop og targets lagt på hvert historisk match med entry på matchets lukkekurs. Ramt samme dag tæller som stop. Ingen af dem inden for 20 dage: lukket på dag 20.'
        }
    }
    if (-not $horizon) { $horizon = [ordered]@{ low = 5; high = 20; source = 'For få historiske træffere. Standardhorisont for swing trade.' } }

    # Kriterier for samlet status
    $score = 0
    foreach ($k in @('ema20', 'sma50', 'sma200', 'rsi', 'macd')) {
        $st = ($Signals | Where-Object { $_.key -eq $k } | Select-Object -First 1).status
        if ($st -eq 'green') { $score++ } elseif ($st -eq 'red') { $score-- }
    }
    $vol = ($Signals | Where-Object { $_.key -eq 'volatility' } | Select-Object -First 1).status
    $h10 = if ($Historical -and $Historical.status -eq 'ok') { $Historical.horizons | Where-Object { $_.days -eq 10 } } else { $null }

    $crit = New-Object System.Collections.Generic.List[object]
    $crit.Add([ordered]@{ key = 'trend'; label = 'Trend og momentum'; pass = ($score -ge 2); hardFail = ($score -le -2)
        detail = "Score $score af 5 (20 EMA, 50 SMA, 200 SMA, RSI, MACD: grøn +1, rød -1). Krav: mindst 2. Under -1 gør setup uinteressant." })
    $crit.Add([ordered]@{ key = 'rr'; label = 'Risk/reward til Target 1'; pass = ($rr1 -ge 1.5); hardFail = ($rr1 -lt 0.8)
        detail = "$(Fmt-Num $rr1 'N2'):1. Krav: mindst 1,5. Under 0,8 gør setup uinteressant." })
    if ($sim) {
        $crit.Add([ordered]@{ key = 'hist'; label = 'Historisk Target 1 før stop'; pass = ($sim.target1Pct -ge 50); hardFail = ($sim.target1Pct -lt 35)
            detail = "$($sim.target1First) af $($sim.matches) matches ($(Fmt-Num $sim.target1Pct)%). Stop først i $($sim.stopFirst). Krav: mindst 50%. Under 35% gør setup uinteressant." })
    }
    if ($h10) {
        $crit.Add([ordered]@{ key = 'edge'; label = 'Lignende setups mod alle dage (10 dage)'; pass = ($h10.edgeMedian -ge 0); hardFail = $false
            detail = "Median $(Fmt-Num $h10.matches.median 'N2')% mod $(Fmt-Num $h10.baseline.median 'N2')% for alle dage. Krav: mindst lige så godt." })
    }
    $crit.Add([ordered]@{ key = 'vol'; label = 'Volatilitet ikke ekstrem'; pass = ($vol -ne 'red'); hardFail = $false
        detail = 'Krav: volatilitetssignalet er ikke rødt (ATR over 90. percentil).' })

    if ($Events -and $Events.status -eq 'ok') {
        $crit.Add([ordered]@{ key = 'event'; label = 'Ingen større event lige forude'; pass = ($Events.risk.level -ne 'high'); hardFail = $false
            detail = "Event risk $($Events.risk.label). $($Events.risk.reasons[0]). Krav: event risk er ikke høj. Et event gør ikke setup uinteressant, men giver ekstra risiko." })
    }

    $hard = @($crit | Where-Object { $_.hardFail }).Count
    $allPass = @($crit | Where-Object { -not $_.pass }).Count -eq 0
    if ($hard -gt 0) { $status = 'red'; $label = 'UINTERESSANT' }
    elseif ($allPass) { $status = 'green'; $label = 'INTERESSANT' }
    else { $status = 'yellow'; $label = 'AFVENT' }

    $invalid = @(
        "Lukkekurs under stop ($(Fmt-Usd $stop)).",
        "Kursen stiger over $(Fmt-Usd ($entryHigh + $atr)) (1 ATR over zonen) uden at komme ned i entry-zonen. Så er det for sent at gå ind.",
        'Niveauerne beregnes igen hver dag efter lukketid. Et setup gælder kun indtil næste beregning.'
    )

    return [ordered]@{
        status        = $status
        label         = $label
        direction     = 'long'
        entryLow      = [math]::Round($entryLow, 2)
        entryHigh     = [math]::Round($entryHigh, 2)
        entry         = [math]::Round($entry, 2)
        stop          = [math]::Round($stop, 2)
        target1       = [math]::Round($t1, 2)
        target2       = [math]::Round($t2, 2)
        riskPct       = [math]::Round(($stop / $entry - 1) * 100, 2)
        target1Pct    = [math]::Round(($t1 / $entry - 1) * 100, 2)
        target2Pct    = [math]::Round(($t2 / $entry - 1) * 100, 2)
        riskReward1   = [math]::Round($rr1, 2)
        riskReward2   = [math]::Round($rr2, 2)
        horizon       = $horizon
        why           = $why
        criteria      = $crit.ToArray()
        eventRisk     = if ($Events -and $Events.status -eq 'ok') { [ordered]@{ status = $Events.risk.status; label = $Events.risk.label; note = ($Events.risk.reasons -join '. ') + '.' } } else { [ordered]@{ status = 'na'; label = '-'; note = 'Events kunne ikke indlæses.' } }
        historicalTest = $sim
        invalidation  = $invalid
        supports      = @($supports | Select-Object -First 6 | ForEach-Object { [ordered]@{ price = [math]::Round($_.Price, 2); label = $_.Label } })
        resistances   = @($resist | Select-Object -First 6 | ForEach-Object { [ordered]@{ price = [math]::Round($_.Price, 2); label = $_.Label } })
    }
}
