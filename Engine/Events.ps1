# Fase 5: Events og event risk
#
# Kilde: Events.json i repo-roden (vedligeholdes manuelt). FOMC-datoer fra Federal Reserve, CPI fra BLS,
# Tesla-datoer fra IR eller kalendertjenester. confirmed=false betyder estimat.
# Mangler Tesla deliveries eller earnings for de næste kvartaler, laves et estimat ud fra Teslas mønster:
#   Deliveries: 2. hverdag i første måned af kvartalet
#   Earnings:   4. onsdag i første måned af kvartalet, efter lukketid
#
# Handelsdage tælles som hverdage minus helligdage fra Events.json (tilnærmelse).
#
# Event risk
#   Høj:     Tesla earnings/deliveries inden for 5 handelsdage, eller FOMC/CPI i dag eller i morgen
#   Moderat: Tesla earnings/deliveries inden for 15 handelsdage, eller FOMC/CPI inden for 5 handelsdage
#   Lav:     ellers
# Event risk er information om risiko. Den siger ikke "sælg".

$script:EventTypes = @{
    earnings   = @{ label = 'Earnings';   group = 'tesla' }
    deliveries = @{ label = 'Deliveries'; group = 'tesla' }
    tesla      = @{ label = 'Tesla-event'; group = 'tesla' }
    fomc       = @{ label = 'FOMC';       group = 'macro' }
    cpi        = @{ label = 'CPI';        group = 'macro' }
    macro      = @{ label = 'Makro';      group = 'macro' }
}

function Get-TradingDaysUntil([datetime]$From, [datetime]$To, [string[]]$Holidays) {
    if ($To.Date -le $From.Date) { return 0 }
    $n = 0
    $d = $From.Date.AddDays(1)
    while ($d -le $To.Date) {
        if ($d.DayOfWeek -ne 'Saturday' -and $d.DayOfWeek -ne 'Sunday' -and $Holidays -notcontains $d.ToString('yyyy-MM-dd')) { $n++ }
        $d = $d.AddDays(1)
    }
    return $n
}

function Get-NthWeekday([int]$Year, [int]$Month, [DayOfWeek]$Day, [int]$N) {
    $d = New-Object DateTime($Year, $Month, 1)
    while ($d.DayOfWeek -ne $Day) { $d = $d.AddDays(1) }
    return $d.AddDays(7 * ($N - 1))
}

function Get-TeslaEstimates([datetime]$Today, [object[]]$Existing, [string[]]$Holidays) {
    $out = New-Object System.Collections.Generic.List[object]
    $m = [int]([math]::Floor(($Today.Month - 1) / 3) * 3 + 1)
    $qStart = New-Object DateTime($Today.Year, $m, 1)
    for ($q = 1; $q -le 2; $q++) {
        $s = $qStart.AddMonths(3 * $q)
        $prevQ = [int]([math]::Floor(($s.AddMonths(-1).Month - 1) / 3) + 1)
        $prevY = $s.AddMonths(-1).Year

        # 2. hverdag
        $d = $s; $count = 0
        while ($true) {
            if ($d.DayOfWeek -ne 'Saturday' -and $d.DayOfWeek -ne 'Sunday' -and $Holidays -notcontains $d.ToString('yyyy-MM-dd')) { $count++ }
            if ($count -eq 2) { break }
            $d = $d.AddDays(1)
        }
        $cands = @(
            [ordered]@{ date = $d; type = 'deliveries'; title = "Tesla Q$prevQ $prevY production og deliveries"; time = $null
                source = 'Automatisk estimat: 2. hverdag i kvartalet.' },
            [ordered]@{ date = (Get-NthWeekday $s.Year $s.Month ([DayOfWeek]::Wednesday) 4); type = 'earnings'; title = "Tesla Q$prevQ $prevY earnings"; time = 'Efter lukketid'
                source = 'Automatisk estimat: 4. onsdag i første måned af kvartalet.' }
        )
        foreach ($c in $cands) {
            $dup = $Existing | Where-Object { $_.type -eq $c.type -and [math]::Abs(([datetime]$_.date - $c.date).TotalDays) -le 20 }
            if (-not $dup) {
                $out.Add([pscustomobject]@{ date = $c.date.ToString('yyyy-MM-dd'); type = $c.type; title = $c.title; time = $c.time
                    confirmed = $false; estimated = $true; source = $c.source; url = 'https://ir.tesla.com/' })
            }
        }
    }
    return $out.ToArray()
}

function Get-Events {
    param([string]$Path, [datetime]$Today, [int]$HorizonDays = 20, [int]$LookaheadDays = 90)
    if (-not (Test-Path $Path)) { return [ordered]@{ status = 'error'; reason = "Filen $Path findes ikke" } }
    $cfg = Get-Content -Raw -Encoding UTF8 $Path | ConvertFrom-Json
    $holidays = @($cfg.holidays | ForEach-Object { [string]$_ })
    $raw = @($cfg.events | ForEach-Object {
        $d = if ($_.date -is [datetime]) { $_.date.ToString('yyyy-MM-dd') } else { ([string]$_.date).Substring(0, 10) }
        [pscustomobject]@{ date = $d; type = $_.type; title = $_.title; time = $_.time; confirmed = [bool]$_.confirmed; estimated = $false; source = $_.source; url = $_.url }
    })
    $all = @($raw) + @(Get-TeslaEstimates $Today $raw $holidays)

    $warnings = New-Object System.Collections.Generic.List[string]
    $futureMacro = @($raw | Where-Object { $script:EventTypes[$_.type].group -eq 'macro' -and [datetime]$_.date -ge $Today.AddDays(30) })
    if ($futureMacro.Count -eq 0) { $warnings.Add('Events.json har ingen FOMC/CPI-datoer mere end 30 dage frem. Tilføj næste års datoer.') }

    $items = New-Object System.Collections.Generic.List[object]
    foreach ($e in ($all | Sort-Object date)) {
        $d = [datetime]::ParseExact($e.date, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
        if ($d -lt $Today.Date -or $d -gt $Today.AddDays($LookaheadDays)) { continue }
        $t = $script:EventTypes[[string]$e.type]
        if (-not $t) { $t = @{ label = [string]$e.type; group = 'macro' } }
        $td = Get-TradingDaysUntil $Today $d $holidays
        $items.Add([ordered]@{
            date          = $e.date
            time          = $e.time
            type          = $e.type
            typeLabel     = $t.label
            group         = $t.group
            title         = $e.title
            confirmed     = $e.confirmed
            estimated     = $e.estimated
            source        = $e.source
            url           = $e.url
            tradingDays   = $td
            insideHorizon = ($td -le $HorizonDays)
        })
    }
    $arr = $items.ToArray()

    # Event risk
    $reasons = New-Object System.Collections.Generic.List[string]
    $level = 'low'
    $describe = {
        param($e)
        $when = if ($e.tradingDays -eq 0) { 'i dag' } elseif ($e.tradingDays -eq 1) { 'i morgen (1 handelsdag)' } else { "om $($e.tradingDays) handelsdage" }
        $st = if ($e.confirmed) { 'bekræftet' } else { 'estimat' }
        "$($e.title) $when ($($e.date), $st)"
    }
    foreach ($e in $arr) {
        $hi = ($e.group -eq 'tesla' -and $e.tradingDays -le 5) -or ($e.group -eq 'macro' -and $e.tradingDays -le 1)
        $mo = ($e.group -eq 'tesla' -and $e.tradingDays -le 15) -or ($e.group -eq 'macro' -and $e.tradingDays -le 5)
        if ($hi) { $level = 'high'; $reasons.Add((& $describe $e)) }
        elseif ($mo) { if ($level -ne 'high') { $level = 'moderate' }; $reasons.Add((& $describe $e)) }
    }
    if ($reasons.Count -eq 0) { $reasons.Add('Ingen Tesla-events inden for 15 handelsdage og ingen FOMC/CPI inden for 5 handelsdage') }
    $next = $arr | Where-Object { $_.group -eq 'tesla' } | Select-Object -First 1

    return [ordered]@{
        status   = 'ok'
        today    = $Today.ToString('yyyy-MM-dd')
        risk     = [ordered]@{
            level   = $level
            label   = @{ low = 'Lav'; moderate = 'Moderat'; high = 'Høj' }[$level]
            status  = @{ low = 'green'; moderate = 'yellow'; high = 'red' }[$level]
            reasons = $reasons.ToArray()
            rule    = 'Høj: Tesla earnings/deliveries inden for 5 handelsdage, eller FOMC/CPI i dag eller i morgen. Moderat: Tesla earnings/deliveries inden for 15 handelsdage, eller FOMC/CPI inden for 5 handelsdage. Ellers lav. Handelsdage = hverdage minus helligdage i Events.json.'
        }
        nextTesla = $next
        warnings = $warnings.ToArray()
        items    = $arr
    }
}
