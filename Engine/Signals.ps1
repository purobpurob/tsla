# Regelbaserede tekniske signaler. Hver regel er skrevet ud i klartekst, så frontend kan vise den.
# Status: 'green' | 'yellow' | 'red' | 'na'

function New-Signal($Key, $Label, $Status, $Value, $Rule, $Reason) {
    return [ordered]@{ key = $Key; label = $Label; status = $Status; value = $Value; rule = $Rule; reason = $Reason }
}

function Get-MaSignal {
    param($Rows, [int]$i, [string]$Field, [string]$Label, [int]$SlopeBars, [string]$Key)
    $ma = $Rows[$i].$Field
    $maPrev = if ($i -ge $SlopeBars) { $Rows[$i - $SlopeBars].$Field } else { $null }
    $rule = "Grøn: kurs over $Label og $Label stigende over $SlopeBars dage. Rød: kurs under og faldende. Ellers gul."
    if ($null -eq $ma -or $null -eq $maPrev) { return New-Signal $Key $Label 'na' $null $rule 'For lidt historik' }

    $c = $Rows[$i].Close
    $above = $c -gt $ma
    $rising = $ma -gt $maPrev
    $dist = ($c / $ma - 1) * 100
    $pos = if ($above) { 'over' } else { 'under' }
    $dir = if ($rising) { 'stigende' } else { 'faldende' }
    $reason = [string]::Format([Globalization.CultureInfo]'da-DK', "Kurs {0:N1}% $pos $Label. $Label er $dir.", [math]::Abs($dist))

    $status = if ($above -and $rising) { 'green' } elseif (-not $above -and -not $rising) { 'red' } else { 'yellow' }
    return New-Signal $Key $Label $status ([math]::Round($ma, 2)) $rule $reason
}

function Get-TechnicalSignals {
    param([object[]]$Rows)
    $i = $Rows.Count - 1
    $r = $Rows[$i]
    $inv = [Globalization.CultureInfo]'da-DK'   # Dansk talformat i forklaringer
    $signals = New-Object System.Collections.Generic.List[object]

    $signals.Add((Get-MaSignal $Rows $i 'Ema20'  '20 EMA'  5  'ema20'))
    $signals.Add((Get-MaSignal $Rows $i 'Sma50'  '50 SMA'  10 'sma50'))
    $signals.Add((Get-MaSignal $Rows $i 'Sma200' '200 SMA' 20 'sma200'))

    # RSI
    $rule = 'Grøn: 50-70 (positivt momentum uden at være overkøbt). Gul: 40-50 eller over 70. Rød: under 40.'
    if ($null -eq $r.Rsi14) { $signals.Add((New-Signal 'rsi' 'RSI 14' 'na' $null $rule 'For lidt historik')) }
    else {
        $v = $r.Rsi14
        $st = if ($v -ge 50 -and $v -lt 70) { 'green' } elseif ($v -lt 40) { 'red' } else { 'yellow' }
        $why = if ($v -ge 70) { 'Overkøbt område' } elseif ($v -ge 50) { 'Positivt momentum' } elseif ($v -ge 40) { 'Neutralt til svagt momentum' } else { 'Svagt momentum' }
        $signals.Add((New-Signal 'rsi' 'RSI 14' $st ([math]::Round($v, 1)) $rule ("RSI {0}. $why." -f $v.ToString('0.0', $inv))))
    }

    # MACD
    $rule = 'Grøn: MACD over signallinjen og over 0. Rød: MACD under signallinjen og under 0. Ellers gul.'
    if ($null -eq $r.MacdSignal) { $signals.Add((New-Signal 'macd' 'MACD' 'na' $null $rule 'For lidt historik')) }
    else {
        $overSig = $r.Macd -gt $r.MacdSignal
        $overZero = $r.Macd -gt 0
        $st = if ($overSig -and $overZero) { 'green' } elseif (-not $overSig -and -not $overZero) { 'red' } else { 'yellow' }
        $a = if ($overSig) { 'over' } else { 'under' }
        $b = if ($overZero) { 'over' } else { 'under' }
        $signals.Add((New-Signal 'macd' 'MACD' $st ([math]::Round($r.Macd, 2)) $rule "MACD er $a signallinjen og $b 0."))
    }

    # Volumen
    $rule = 'Grøn: volumen mindst 1,2x gennemsnittet af de 20 foregående dage på en op-dag. Rød: samme volumen på en ned-dag. Ellers gul.'
    if ($null -eq $r.VolRatio -or $i -lt 1) { $signals.Add((New-Signal 'volume' 'Volumen' 'na' $null $rule 'For lidt historik')) }
    else {
        $up = $r.Close -gt $Rows[$i - 1].Close
        $high = $r.VolRatio -ge 1.2
        $st = if ($high -and $up) { 'green' } elseif ($high -and -not $up) { 'red' } else { 'yellow' }
        $dayTxt = if ($up) { 'op-dag' } else { 'ned-dag' }
        $signals.Add((New-Signal 'volume' 'Volumen' $st ([math]::Round($r.VolRatio, 2)) $rule ("Volumen {0}x 20-dages gennemsnit på en $dayTxt." -f $r.VolRatio.ToString('0.00', $inv))))
    }

    # Volatilitet
    $rule = 'ATR14 i procent af kursen sammenlignet med det seneste år. Grøn: under 70. percentil. Gul: 70-90. Rød: over 90. percentil.'
    if ($null -eq $r.AtrPctRank) { $signals.Add((New-Signal 'volatility' 'Volatilitet' 'na' $null $rule 'For lidt historik')) }
    else {
        $p = $r.AtrPctRank
        $st = if ($p -lt 70) { 'green' } elseif ($p -le 90) { 'yellow' } else { 'red' }
        $atrTxt = $r.AtrPct.ToString('0.00', $inv)
        $why = if ($p -lt 5) { "ATR er $atrTxt% af kursen. Det er blandt de laveste niveauer det seneste år." }
               elseif ($p -gt 95) { "ATR er $atrTxt% af kursen. Det er blandt de højeste niveauer det seneste år." }
               else { "ATR er $atrTxt% af kursen. Højere end $([math]::Round($p))% af dagene det seneste år." }
        $signals.Add((New-Signal 'volatility' 'Volatilitet' $st ([math]::Round($r.AtrPct, 2)) $rule $why))
    }

    return $signals.ToArray()
}

function Get-TrendSummary {
    param([object[]]$Signals)
    $map = @{ green = 'positive'; yellow = 'neutral'; red = 'negative'; na = 'unknown' }
    $get = { param($k) ($Signals | Where-Object { $_.key -eq $k } | Select-Object -First 1).status }
    return [ordered]@{
        short  = $map[(& $get 'ema20')]
        medium = $map[(& $get 'sma50')]
        long   = $map[(& $get 'sma200')]
    }
}
