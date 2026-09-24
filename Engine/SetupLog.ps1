# Fase 6: Log af modellens setups og hvad der faktisk skete bagefter
#
# Hver afsluttet handelsdag gemmes modellens setup i data/setups-log.json:
#   status, entry-zone, stop, targets, risk/reward og den historiske forventning (fase 2).
# Ved hver kørsel evalueres alle loggede setups mod de kurser der er kommet siden:
#   Afkast efter 2, 5, 10 og 20 handelsdage (lukkekurs til lukkekurs)
#   Trade-udfald inden for 20 dage med entry på setup-dagens lukkekurs:
#     t1   = Target 1 ramt før stop
#     stop = stop ramt først (samme dag som T1 tæller som stop)
#     none = ingen af dem på 20 dage, lukket på dag 20
#     open = endnu ikke 20 dage og ingen af dem ramt
#   R = gevinst eller tab i forhold til risikoen (entry - stop)
#
# Setups markeret backfill=true er beregnet bagud med Backfill-Setups.ps1 med kun de data
# der fandtes på dagen. De har ikke nyheder og events med, fordi de ikke kan genskabes.

$script:LogHorizons = @(2, 5, 10, 20)

function New-SetupLogEntry {
    param($Row, $Setup, $Historical, $Events, [bool]$Backfill = $false)
    $hp = @{}
    if ($Historical -and $Historical.status -eq 'ok') {
        foreach ($h in $Historical.horizons) { $hp["d$($h.days)"] = [ordered]@{ matches = $h.matches.pctPositive; baseline = $h.baseline.pctPositive; median = $h.matches.median } }
    }
    return [ordered]@{
        date       = $Row.Date
        close      = [math]::Round($Row.Close, 2)
        backfill   = $Backfill
        status     = $Setup.status
        label      = $Setup.label
        entryLow   = $Setup.entryLow
        entryHigh  = $Setup.entryHigh
        stop       = $Setup.stop
        target1    = $Setup.target1
        target2    = $Setup.target2
        rr1        = $Setup.riskReward1
        horizon    = if ($Setup.horizon) { "$($Setup.horizon.low)-$($Setup.horizon.high)" } else { $null }
        histT1Pct  = if ($Setup.historicalTest) { $Setup.historicalTest.target1Pct } else { $null }
        expected   = $hp
        eventRisk  = if ($Events -and $Events.status -eq 'ok') { $Events.risk.label } else { $null }
        failed     = @($Setup.criteria | Where-Object { -not $_.pass } | ForEach-Object { $_.key })
    }
}

function Get-SetupOutcome {
    param($Entry, [object[]]$Rows, [hashtable]$Index)
    $i = $Index[$Entry.date]
    if ($null -eq $i) { return $null }
    $n = $Rows.Count
    $c = $Rows[$i].Close
    $ret = [ordered]@{}
    foreach ($h in $script:LogHorizons) {
        $ret["d$h"] = if ($i + $h -lt $n) { [math]::Round(($Rows[$i + $h].Close / $c - 1) * 100, 2) } else { $null }
    }
    $res = 'open'; $days = $null; $r = $null; $t2 = $false
    $risk = $c - [double]$Entry.stop
    if ($risk -gt 0) {
        $t1Day = $null
        $last = [math]::Min($n - 1, $i + 20)
        for ($k = $i + 1; $k -le $last; $k++) {
            if ($Rows[$k].Low -le $Entry.stop) { if ($null -eq $t1Day) { $res = 'stop'; $days = $k - $i }; break }
            if ($null -eq $t1Day -and $Rows[$k].High -ge $Entry.target1) { $t1Day = $k - $i; $res = 't1'; $days = $t1Day }
            if ($Rows[$k].High -ge $Entry.target2) { $t2 = $true; break }
        }
        if ($res -eq 't1') { $r = [math]::Round(($Entry.target1 - $c) / $risk, 2) }
        elseif ($res -eq 'stop') { $r = -1 }
        elseif ($i + 20 -lt $n) { $res = 'none'; $days = 20; $r = [math]::Round(($Rows[$i + 20].Close - $c) / $risk, 2) }
    }
    return [ordered]@{ returns = $ret; result = $res; days = $days; r = $r; target2 = $t2; daysSince = ($n - 1 - $i) }
}

function Get-GroupStats([object[]]$Entries) {
    $closed = @($Entries | Where-Object { $_.outcome -and $_.outcome.result -ne 'open' })
    $s = [ordered]@{ n = $Entries.Count; closed = $closed.Count }
    if ($closed.Count -gt 0) {
        $s.t1Pct = [math]::Round(100.0 * @($closed | Where-Object { $_.outcome.result -eq 't1' }).Count / $closed.Count, 1)
        $s.stopPct = [math]::Round(100.0 * @($closed | Where-Object { $_.outcome.result -eq 'stop' }).Count / $closed.Count, 1)
        $sum = 0.0; foreach ($e in $closed) { $sum += [double]$e.outcome.r }
        $s.avgR = [math]::Round($sum / $closed.Count, 2)
    }
    foreach ($h in $script:LogHorizons) {
        $v = @($Entries | Where-Object { $_.outcome -and $null -ne $_.outcome.returns["d$h"] } | ForEach-Object { [double]$_.outcome.returns["d$h"] })
        if ($v.Count -gt 0) {
            $sum = 0.0; foreach ($x in $v) { $sum += $x }
            $s["d$h"] = [ordered]@{ n = $v.Count; pctPositive = [math]::Round(100.0 * @($v | Where-Object { $_ -gt 0 }).Count / $v.Count, 1); mean = [math]::Round($sum / $v.Count, 2) }
        }
    }
    return $s
}

function Get-Calibration([object[]]$Entries, [int]$Days) {
    # Sammenligner modellens forventede andel positive med den faktiske andel, i 3 grupper
    $key = "d$Days"
    $buckets = @(
        @{ label = 'Under 45%'; lo = -1; hi = 45 },
        @{ label = '45-55%'; lo = 45; hi = 55 },
        @{ label = 'Over 55%'; lo = 55; hi = 101 }
    )
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($b in $buckets) {
        $sel = @($Entries | Where-Object {
            $_.expected -and $_.expected[$key] -and $_.outcome -and $null -ne $_.outcome.returns[$key] -and
            [double]$_.expected[$key].matches -ge $b.lo -and [double]$_.expected[$key].matches -lt $b.hi })
        if ($sel.Count -eq 0) { $out.Add([ordered]@{ bucket = $b.label; n = 0 }); continue }
        $sumP = 0.0; foreach ($e in $sel) { $sumP += [double]$e.expected[$key].matches }
        $pos = @($sel | Where-Object { [double]$_.outcome.returns[$key] -gt 0 }).Count
        $out.Add([ordered]@{ bucket = $b.label; n = $sel.Count; predicted = [math]::Round($sumP / $sel.Count, 1); actual = [math]::Round(100.0 * $pos / $sel.Count, 1) })
    }
    return $out.ToArray()
}

function ConvertTo-Hashtable($o) {
    # ConvertFrom-Json giver PSCustomObject. Laves om til ordered hashtables, så felter kan opdateres.
    if ($null -eq $o) { return $null }
    if ($o -is [System.Management.Automation.PSCustomObject]) {
        $h = [ordered]@{}
        foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = ConvertTo-Hashtable $p.Value }
        return $h
    }
    if ($o -is [array]) { return ,@($o | ForEach-Object { ConvertTo-Hashtable $_ }) }
    if ($o -is [datetime]) { return $o.ToString('yyyy-MM-dd') }
    return $o
}

function Read-SetupLog([string]$Path) {
    if (-not (Test-Path $Path)) { return @() }
    $raw = Get-Content -Raw -Encoding UTF8 $Path | ConvertFrom-Json
    return @($raw.entries | ForEach-Object { ConvertTo-Hashtable $_ })
}

function Save-SetupLog([string]$Path, [object[]]$Entries) {
    $doc = [ordered]@{ schemaVersion = 1; entries = @($Entries | Sort-Object { $_.date }) }
    [IO.File]::WriteAllText($Path, ($doc | ConvertTo-Json -Depth 8 -Compress), (New-Object System.Text.UTF8Encoding($false)))
}

function Update-SetupLog {
    param([string]$Path, [object[]]$Rows, $Entry, [int]$RecentCount = 30)
    $entries = @(Read-SetupLog $Path)
    $map = [ordered]@{}
    foreach ($e in $entries) { $map[$e.date] = $e }
    if ($Entry) {
        # Live-kørsel erstatter altid en tidligere eller bagud-beregnet version for samme dag
        $map[$Entry.date] = $Entry
    }
    $idx = @{}
    for ($i = 0; $i -lt $Rows.Count; $i++) { $idx[$Rows[$i].Date] = $i }

    $all = New-Object System.Collections.Generic.List[object]
    foreach ($k in $map.Keys) {
        $e = $map[$k]
        $e.outcome = Get-SetupOutcome $e $Rows $idx
        $all.Add($e)
    }
    $arr = @($all | Sort-Object { $_.date })
    Save-SetupLog $Path $arr

    $groups = [ordered]@{
        all    = Get-GroupStats $arr
        green  = Get-GroupStats @($arr | Where-Object { $_.status -eq 'green' })
        yellow = Get-GroupStats @($arr | Where-Object { $_.status -eq 'yellow' })
        red    = Get-GroupStats @($arr | Where-Object { $_.status -eq 'red' })
    }
    return [ordered]@{
        status     = 'ok'
        total      = $arr.Count
        live       = @($arr | Where-Object { -not $_.backfill }).Count
        backfilled = @($arr | Where-Object { $_.backfill }).Count
        firstDate  = if ($arr.Count) { $arr[0].date } else { $null }
        groups     = $groups
        calibration = [ordered]@{ d5 = Get-Calibration $arr 5; d10 = Get-Calibration $arr 10 }
        recent     = @($arr | Select-Object -Last $RecentCount | Sort-Object { $_.date } -Descending)
        note       = 'Setups fra dag til dag overlapper og er ikke uafhængige. Mange ens dage i træk tæller som mange setups. Bagud-beregnede setups har ikke nyheder og events med.'
        file       = 'data/setups-log.json'
    }
}
