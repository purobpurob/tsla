# Dynamisk forklaring i klart sprog. Bygges af faste skabeloner ud fra dagens tal,
# så teksten altid passer med signalerne og kan spores tilbage til reglerne.

function Get-Narrative {
    param([object[]]$Rows, [object[]]$Signals, $Trend, $Setup, $Events)
    $da = [Globalization.CultureInfo]'da-DK'
    $n1 = { param($v) ([double]$v).ToString('N1', $da) }
    $usd = { param($v) '$' + ([double]$v).ToString('N2', $da) }
    $r = $Rows[-1]; $p = $Rows[-2]
    $sig = @{}; foreach ($s in $Signals) { $sig[$s.key] = $s.status }

    $parts = New-Object System.Collections.Generic.List[object]

    # 1. Trend
    $t = "$($Trend.short)/$($Trend.medium)/$($Trend.long)"
    $trendTxt = switch -Regex ($t) {
        '^positive/positive/positive$' { 'Trenden er positiv på alle 3 tidshorisonter. Kursen ligger over stigende gennemsnit på kort, mellem og lang sigt.' ; break }
        '^negative/negative/negative$' { 'Trenden er negativ på alle 3 tidshorisonter. Kursen ligger under faldende gennemsnit.' ; break }
        '^positive/\w+/negative$'      { 'Den korte trend peger op, men den lange peger stadig ned. Det er typisk for en aktie der er ved at rette sig op efter et fald, men som ikke har brudt den lange nedtrend.' ; break }
        '^negative/\w+/positive$'      { 'Den lange trend er intakt, men på kort sigt er kursen svag. Det er typisk for en pause eller et tilbagefald i en optrend.' ; break }
        '^positive/\w+/\w+$'           { 'Den korte trend peger op, mens mellem og lang trend er blandede.' ; break }
        '^negative/\w+/\w+$'           { 'Den korte trend peger ned, mens mellem og lang trend er blandede.' ; break }
        '^neutral/\w+/positive$'       { 'Den lange trend er positiv, men den korte er uden klar retning. Det ses ofte når kursen holder pause i en optrend.' ; break }
        '^neutral/\w+/negative$'       { 'Den lange trend er negativ, og den korte er uden klar retning.' ; break }
        default                         { 'Trenden er blandet uden en klar retning.' ; break }
    }
    $parts.Add([ordered]@{ topic = 'Trend'; text = $trendTxt })

    # 2. Momentum (RSI og MACD, inkl. kryds i dag)
    $m = New-Object System.Collections.Generic.List[string]
    if ($null -ne $r.Rsi14) {
        $rsi = & $n1 $r.Rsi14
        if ($r.Rsi14 -ge 70) { $m.Add("RSI er $rsi og i overkøbt område. Stigningen kan være ved at løbe tør.") }
        elseif ($r.Rsi14 -ge 50) { $m.Add("RSI er $rsi, altså positivt momentum uden at være overkøbt.") }
        elseif ($r.Rsi14 -ge 30) { $m.Add("RSI er $rsi, altså svagt momentum.") }
        else { $m.Add("RSI er $rsi og i oversolgt område. Faldet har været kraftigt.") }
    }
    if ($null -ne $r.MacdSignal -and $null -ne $p.MacdSignal) {
        $nowOver = $r.Macd -gt $r.MacdSignal; $prevOver = $p.Macd -gt $p.MacdSignal
        if ($nowOver -and -not $prevOver) { $m.Add('MACD krydsede op over signallinjen i dag, hvilket ofte ses som starten på stigende momentum.') }
        elseif (-not $nowOver -and $prevOver) { $m.Add('MACD krydsede ned under signallinjen i dag, hvilket ofte ses som aftagende momentum.') }
        elseif ($nowOver) { $m.Add('MACD ligger over signallinjen, så momentum er stigende.') }
        else { $m.Add('MACD ligger under signallinjen, så momentum er aftagende.') }
    }
    if ($m.Count) { $parts.Add([ordered]@{ topic = 'Momentum'; text = ($m -join ' ') }) }

    # 3. Nærmeste gennemsnit som støtte eller modstand (inden for 5%)
    $lv = New-Object System.Collections.Generic.List[string]
    foreach ($ma in @(@('20 EMA', $r.Ema20), @('50 SMA', $r.Sma50), @('200 SMA', $r.Sma200))) {
        if ($null -eq $ma[1]) { continue }
        $d = ($ma[1] / $r.Close - 1) * 100
        if ([math]::Abs($d) -le 5) {
            if ($d -gt 0) { $lv.Add("$($ma[0]) på $(& $usd $ma[1]) ligger $(& $n1 $d)% over kursen og kan virke som modstand.") }
            else { $lv.Add("$($ma[0]) på $(& $usd $ma[1]) ligger $(& $n1 ([math]::Abs($d)))% under kursen og kan virke som støtte.") }
        }
    }
    if ($lv.Count) { $parts.Add([ordered]@{ topic = 'Niveauer'; text = ($lv -join ' ') }) }

    # 4. Volumen og volatilitet
    $v = New-Object System.Collections.Generic.List[string]
    if ($null -ne $r.VolRatio) {
        $up = $r.Close -gt $p.Close
        $vr = ([double]$r.VolRatio).ToString('N2', $da)
        if ($r.VolRatio -ge 1.2) {
            if ($up) { $v.Add("Stigningen skete på høj volumen (${vr}x normalt), altså med bred opbakning.") } else { $v.Add("Faldet skete på høj volumen (${vr}x normalt), hvilket tyder på salgspres.") }
        } elseif ($r.VolRatio -lt 0.9) {
            if ($up) { $v.Add("Stigningen skete på lav volumen (${vr}x normalt), altså uden stor opbakning.") } else { $v.Add("Faldet skete på lav volumen (${vr}x normalt), så salgspresset er begrænset.") }
        } else { $v.Add("Volumen er normal (${vr}x gennemsnittet).") }
    }
    if ($null -ne $r.AtrPctRank) {
        if ($r.AtrPctRank -lt 10) { $v.Add('Udsvingene er blandt de laveste det seneste år. Rolige perioder bliver ofte afløst af større bevægelser, men retningen er ukendt.') }
        elseif ($r.AtrPctRank -gt 90) { $v.Add('Udsvingene er blandt de største det seneste år. Det giver større risiko og kræver et stop længere væk.') }
    }
    if ($v.Count) { $parts.Add([ordered]@{ topic = 'Volumen og volatilitet'; text = ($v -join ' ') }) }

    # 5. Hvad skal der til for INTERESSANT?
    $need = New-Object System.Collections.Generic.List[string]
    if ($Setup -and $Setup.criteria) {
        $atr = $r.Atr14
        foreach ($c in ($Setup.criteria | Where-Object { -not $_.pass })) {
            switch ($c.key) {
                'trend' { $need.Add("Trend-scoren skal op på mindst 2. Den stiger når flere af 20 EMA, 50 SMA, 200 SMA, RSI og MACD bliver grønne.") }
                'rr'    { $need.Add("Risk/reward skal op på mindst 1,5. Det sker hvis kursen falder mod bunden af entry-zonen, eller hvis Target 1 kommer til at ligge højere.") }
                'hist'  {
                    $sa = if ($atr) { ($Setup.entry - $Setup.stop) / $atr } else { $null }
                    $txt = "Flere historiske matches skal nå Target 1 før stop (nu $(& $n1 $Setup.historicalTest.target1Pct)%, krav 50%)."
                    if ($sa -and $sa -lt 2) { $txt += " Stoppet ligger kun $($sa.ToString('N1', $da)) ATR under entry, så det bliver let ramt af almindelige udsving." }
                    elseif ($sa) { $txt += " Stoppet ligger $($sa.ToString('N1', $da)) ATR under entry." }
                    $need.Add($txt)
                }
                'edge'  { $need.Add('Lignende setups skal have klaret sig mindst lige så godt som en tilfældig dag over 10 dage.') }
                'vol'   { $need.Add('Volatiliteten skal ned under 90. percentil for det seneste år.') }
                'event' { $need.Add("Event risk skal ned fra Høj. $($Events.risk.reasons[0]).") }
            }
        }
    }
    $needTitle = if ($Setup.status -eq 'green') { 'Alle krav er opfyldt' } else { 'Hvad skal der til for INTERESSANT?' }
    if ($Setup.status -eq 'green') { $need.Add('Setup ugyldigt ved lukkekurs under stop, eller hvis kursen stiger mere end 1 ATR over entry-zonen uden pullback.') }

    return [ordered]@{
        parts     = $parts.ToArray()
        needTitle = $needTitle
        need      = $need.ToArray()
        note      = 'Teksten dannes automatisk af faste regler ud fra dagens tal og opdateres ved hver kørsel.'
    }
}
