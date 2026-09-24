# Fase 4: Nyheder
#
# Kilder
#   1. SEC EDGAR (data.sec.gov): Teslas egne indberetninger (8-K, 10-Q, 10-K). Primær kilde.
#      8-K med Item 2.02 er regnskab. SEC kræver en User-Agent med kontakt-email.
#      Den læses fra miljøvariablen TSLA_SEC_CONTACT, så den ikke ligger i det offentlige repo.
#   2. Nasdaq RSS for TSLA: artikler fra bl.a. Motley Fool, Zacks, Barchart.
#   Tesla IR (ir.tesla.com) har ikke et RSS-feed. Teslas vigtige meddelelser kommer også som 8-K hos SEC.
#
# Klassifikation (regelbaseret, ingen sort boks)
#   Kategori: nøgleord i overskriften, fx 'recall' -> Regulering, 'deliveries' -> Deliveries.
#   Tone:     antal positive ord minus antal negative ord. Over 0 positiv, under 0 negativ, ellers neutral.
#   De ord der udløste kategori og tone gemmes, så frontend kan vise hvorfor.
#   Begrænsning: reglerne forstår ikke ironi, spørgsmål eller negationer ("not a recall").

$script:NewsCategories = [ordered]@{
    earnings   = @{ label = 'Earnings';     impact = 'high'; words = @('earnings', 'quarterly results', 'revenue', 'eps', 'guidance', 'profit', 'margin', 'margins', 'q1 results', 'q2 results', 'q3 results', 'q4 results') }
    deliveries = @{ label = 'Deliveries';   impact = 'high'; words = @('deliveries', 'delivery', 'delivered', 'production numbers', 'registrations', 'sales in') }
    regulation = @{ label = 'Regulering';   impact = 'high'; words = @('nhtsa', 'recall', 'recalls', 'probe', 'investigation', 'regulator', 'regulators', 'lawsuit', 'sued', 'doj', 'ftc', 'sec charges', 'fine', 'fined', 'ban') }
    robotaxi   = @{ label = 'Robotaxi';     impact = 'medium'; words = @('robotaxi', 'robotaxis', 'cybercab', 'ride-hailing', 'ride hailing', 'driverless') }
    fsd        = @{ label = 'FSD';          impact = 'medium'; words = @('fsd', 'full self-driving', 'self-driving', 'autopilot', 'autonomy', 'autonomous') }
    optimus    = @{ label = 'Optimus';      impact = 'medium'; words = @('optimus', 'humanoid') }
    models     = @{ label = 'Modeller';     impact = 'medium'; words = @('model y', 'model 3', 'model s', 'model x', 'cybertruck', 'semi', 'roadster', 'new model', 'affordable model', 'cheaper model') }
    china      = @{ label = 'Kina';         impact = 'medium'; words = @('china', 'chinese', 'shanghai', 'byd', 'beijing') }
    musk       = @{ label = 'Musk';         impact = 'medium'; words = @('musk', 'elon') }
    analyst    = @{ label = 'Analytiker';   impact = 'medium'; words = @('upgrade', 'upgrades', 'downgrade', 'downgrades', 'price target', 'analyst', 'analysts', 'rating') }
    macro      = @{ label = 'Makro';        impact = 'medium'; words = @('fed', 'interest rate', 'rates', 'inflation', 'cpi', 'tariff', 'tariffs', 'recession', 'jobs report') }
    filing     = @{ label = 'SEC-indberetning'; impact = 'high'; words = @() }
}

$script:PositiveWords = @('beat', 'beats', 'record', 'records', 'surge', 'surges', 'soar', 'soars', 'jump', 'jumps', 'rally', 'rallies',
    'upgrade', 'upgrades', 'upgraded', 'approval', 'approved', 'approves', 'launch', 'launches', 'expands', 'expansion', 'strong',
    'raises', 'raised', 'tops', 'wins', 'bullish', 'outperform', 'buy rating', 'rebound', 'rebounds')
$script:NegativeWords = @('miss', 'misses', 'missed', 'recall', 'recalls', 'probe', 'investigation', 'lawsuit', 'sued', 'crash', 'crashes',
    'plunge', 'plunges', 'drop', 'drops', 'fall', 'falls', 'slump', 'slumps', 'downgrade', 'downgrades', 'downgraded', 'cut', 'cuts',
    'weak', 'weaker', 'decline', 'declines', 'delay', 'delays', 'delayed', 'halt', 'halts', 'ban', 'fine', 'fined', 'bearish',
    'underperform', 'sell rating', 'warning', 'warns', 'slowdown', 'loses', 'loss', 'losses', 'trails', 'overvalued', 'sinks', 'tumbles')

$script:SecItems = @{
    '1.01' = 'Væsentlig aftale'; '2.01' = 'Opkøb eller salg af aktiver'; '2.02' = 'Regnskab (earnings)'; '2.03' = 'Ny gæld'
    '5.02' = 'Ændring i ledelse eller bestyrelse'; '5.03' = 'Ændring af vedtægter'; '5.07' = 'Generalforsamling, afstemning'
    '7.01' = 'Offentliggørelse (Reg FD)'; '8.01' = 'Anden væsentlig begivenhed'; '9.01' = 'Bilag'
}

function Find-Words([string]$Text, [string[]]$Words) {
    # Hele ord/fraser, ikke dele af ord ('fall' matcher ikke 'fallout')
    $t = ' ' + ($Text.ToLowerInvariant() -replace '[^a-z0-9\-\s]', ' ') + ' '
    $hits = New-Object System.Collections.Generic.List[string]
    foreach ($w in $Words) { if ($t.Contains(' ' + $w + ' ')) { $hits.Add($w) } }
    return ,$hits.ToArray()
}

function ConvertFrom-RssDate([string]$s) {
    # RFC 822, fx "Sat, 19 Sep 2026 21:25:00 +0000" eller "... GMT" / "... -0400" / "... EDT"
    $m = [regex]::Match($s, '(\d{1,2})\s+(\w{3})\w*\s+(\d{4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([+-]\d{4}|[A-Z]{1,4})?')
    if (-not $m.Success) { return $null }
    $months = @{ jan = 1; feb = 2; mar = 3; apr = 4; may = 5; jun = 6; jul = 7; aug = 8; sep = 9; oct = 10; nov = 11; dec = 12 }
    $mon = $months[$m.Groups[2].Value.ToLowerInvariant()]
    if (-not $mon) { return $null }
    $sec = if ($m.Groups[6].Success) { [int]$m.Groups[6].Value } else { 0 }
    $tz = $m.Groups[7].Value
    $offMin = 0
    if ($tz -match '^[+-]\d{4}$') { $sign = if ($tz[0] -eq '-') { -1 } else { 1 }; $offMin = $sign * ([int]$tz.Substring(1, 2) * 60 + [int]$tz.Substring(3, 2)) }
    elseif ($tz -eq 'EDT') { $offMin = -240 } elseif ($tz -eq 'EST') { $offMin = -300 }
    elseif ($tz -eq 'PDT') { $offMin = -420 } elseif ($tz -eq 'PST') { $offMin = -480 }
    $dto = New-Object DateTimeOffset([int]$m.Groups[3].Value, $mon, [int]$m.Groups[1].Value, [int]$m.Groups[4].Value, [int]$m.Groups[5].Value, $sec, [TimeSpan]::FromMinutes($offMin))
    return $dto.UtcDateTime
}

function Get-Utf8Content($Uri, $Headers, $Config) {
    $r = Invoke-WebRequest -Uri $Uri -Headers $Headers -UseBasicParsing -TimeoutSec $Config.TimeoutSec -ErrorAction Stop
    return [Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray())
}

function ConvertFrom-NasdaqRss([string]$XmlText) {
    [xml]$x = $XmlText
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($it in $x.SelectNodes('//item')) {
        $get = { param($name) $n = $it.ChildNodes | Where-Object { $_.LocalName -eq $name } | Select-Object -First 1; if ($n) { $n.InnerText.Trim() } else { '' } }
        $title = & $get 'title'
        $date = ConvertFrom-RssDate (& $get 'pubDate')
        if (-not $title -or -not $date) { continue }
        $src = & $get 'creator'
        $out.Add([pscustomobject]@{ Title = $title; Link = (& $get 'link'); Time = $date; Source = $(if ($src) { $src } else { 'Nasdaq' }); Feed = 'Nasdaq RSS'; Kind = 'article' })
    }
    return $out.ToArray()
}

function ConvertFrom-SecSubmissions($Json, [int]$Days) {
    $r = $Json.filings.recent
    $out = New-Object System.Collections.Generic.List[object]
    $cutoff = [DateTime]::UtcNow.Date.AddDays(-$Days)
    for ($i = 0; $i -lt $r.form.Count; $i++) {
        $form = $r.form[$i]
        if ($form -notin @('8-K', '8-K/A', '10-Q', '10-K')) { continue }
        $d = [datetime]::ParseExact([string]$r.filingDate[$i], 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
        if ($d -lt $cutoff) { continue }
        $time = $d
        if ($r.acceptanceDateTime -and $r.acceptanceDateTime[$i]) {
            $a = $r.acceptanceDateTime[$i]
            # PowerShell 7 laver ISO-strenge om til DateTime ved ConvertFrom-Json. 5.1 gør ikke.
            try { $time = if ($a -is [datetime]) { $a.ToUniversalTime() } else { [DateTimeOffset]::Parse([string]$a, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime } } catch { }
        }
        $items = @(([string]$r.items[$i]) -split ',' | Where-Object { $_ } | ForEach-Object { $_.Trim() })
        $desc = @($items | Where-Object { $_ -ne '9.01' } | ForEach-Object { if ($script:SecItems[$_]) { "Item $_ $($script:SecItems[$_])" } else { "Item $_" } })
        $title = switch ($form) {
            '10-Q' { 'Tesla 10-Q: kvartalsrapport' }
            '10-K' { 'Tesla 10-K: årsrapport' }
            default { "Tesla $($form): " + $(if ($desc) { $desc -join ', ' } else { 'indberetning' }) }
        }
        $acc = ([string]$r.accessionNumber[$i]) -replace '-', ''
        $link = "https://www.sec.gov/Archives/edgar/data/1318605/$acc/$($r.primaryDocument[$i])"
        $out.Add([pscustomobject]@{ Title = $title; Link = $link; Time = $time; Source = 'SEC EDGAR'; Feed = 'SEC EDGAR'; Kind = 'filing'; Items = $items })
    }
    return $out.ToArray()
}

function Get-NewsClassification($Item) {
    $cats = New-Object System.Collections.Generic.List[string]
    $catWords = New-Object System.Collections.Generic.List[string]
    $high = $false
    if ($Item.Kind -eq 'filing') {
        $cats.Add('filing'); $high = $true
        if ($Item.Items -contains '2.02' -or $Item.Title -match '10-Q|10-K') { $cats.Add('earnings') }
    }
    foreach ($k in $script:NewsCategories.Keys) {
        $w = Find-Words $Item.Title $script:NewsCategories[$k].words
        if ($w.Count -gt 0) {
            if (-not $cats.Contains($k)) { $cats.Add($k) }
            foreach ($x in $w) { $catWords.Add($x) }
            if ($script:NewsCategories[$k].impact -eq 'high') { $high = $true }
        }
    }
    # Overskrifter formuleret som spørgsmål er typisk holdningsstof og tæller ikke som høj betydning
    $question = $Item.Title.Trim().EndsWith('?')
    if ($question -and $Item.Kind -ne 'filing') { $high = $false }
    $pos = Find-Words $Item.Title $script:PositiveWords
    $neg = Find-Words $Item.Title $script:NegativeWords
    $score = $pos.Count - $neg.Count
    $tone = if ($score -gt 0) { 'positive' } elseif ($score -lt 0) { 'negative' } else { 'neutral' }

    $why = if ($Item.Kind -eq 'filing') { 'Officiel indberetning fra Tesla til SEC. Tone vurderes ikke.' }
           elseif ($pos.Count -eq 0 -and $neg.Count -eq 0) { if ($question) { 'Ingen positive eller negative nøgleord. Spørgsmål tæller ikke som høj betydning.' } else { 'Ingen positive eller negative nøgleord.' } }
           else {
               $parts = @()
               if ($pos.Count) { $parts += "Positive ord: " + ($pos -join ', ') }
               if ($neg.Count) { $parts += "Negative ord: " + ($neg -join ', ') }
               ($parts -join '. ') + '.'
           }
    if ($Item.Kind -eq 'filing') { $tone = 'neutral' }

    return [ordered]@{
        categories   = $cats.ToArray()
        categoryLabels = @($cats | ForEach-Object { $script:NewsCategories[$_].label })
        matchedWords = @($catWords | Select-Object -Unique)
        tone         = $tone
        toneScore    = $score
        positiveWords = $pos
        negativeWords = $neg
        highImpact   = $high
        why          = $why
    }
}

function Get-NewsRisk([object[]]$Items) {
    $now = [DateTime]::UtcNow
    $in = { param($it, $days) ($now - [DateTimeOffset]::Parse($it.time, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime).TotalDays -le $days }
    $neg3 = @($Items | Where-Object { $_.tone -eq 'negative' -and (& $in $_ 3) })
    $negHigh2 = @($Items | Where-Object { $_.tone -eq 'negative' -and $_.highImpact -and (& $in $_ 2) })
    $high2 = @($Items | Where-Object { $_.highImpact -and (& $in $_ 2) })

    $reasons = New-Object System.Collections.Generic.List[string]
    if ($negHigh2.Count -ge 1) { $reasons.Add("$($negHigh2.Count) negativ(e) nyhed(er) med høj betydning de seneste 2 dage (fx: $($negHigh2[0].title))") }
    if ($neg3.Count -ge 3) { $reasons.Add("$($neg3.Count) negative nyheder de seneste 3 dage") }
    if ($reasons.Count -gt 0) { $level = 'high' }
    else {
        if ($neg3.Count -ge 1) { $reasons.Add("$($neg3.Count) negativ(e) nyhed(er) de seneste 3 dage") }
        if ($high2.Count -ge 1) { $reasons.Add("$($high2.Count) nyhed(er) med høj betydning de seneste 2 dage (earnings, deliveries, regulering eller SEC)") }
        $level = if ($reasons.Count -gt 0) { 'moderate' } else { 'low' }
        if ($level -eq 'low') { $reasons.Add('Ingen negative nyheder de seneste 3 dage og ingen nyheder med høj betydning de seneste 2 dage') }
    }
    $label = @{ low = 'Lav'; moderate = 'Moderat'; high = 'Høj' }[$level]
    $status = @{ low = 'green'; moderate = 'yellow'; high = 'red' }[$level]
    return [ordered]@{
        level   = $level
        label   = $label
        status  = $status
        reasons = $reasons.ToArray()
        rule    = 'Høj: negativ nyhed med høj betydning inden for 2 dage, eller mindst 3 negative nyheder inden for 3 dage. Moderat: mindst 1 negativ nyhed inden for 3 dage, eller en nyhed med høj betydning inden for 2 dage. Ellers lav.'
    }
}

function Get-News {
    param($Config, [string]$CacheDir, [string]$OfflineDir)
    $all = New-Object System.Collections.Generic.List[object]
    $sources = New-Object System.Collections.Generic.List[object]
    $days = $Config.NewsDays

    # SEC EDGAR
    try {
        if ($OfflineDir) { $sec = Get-Content -Raw (Join-Path $OfflineDir 'sec-sample.json') | ConvertFrom-Json }
        else {
            if (-not $env:TSLA_SEC_CONTACT) { throw 'TSLA_SEC_CONTACT er ikke sat (SEC kræver en kontakt-email i User-Agent)' }
            $h = @{ 'User-Agent' = "TSLA-Swing-Trader $($env:TSLA_SEC_CONTACT)"; 'Accept' = 'application/json' }
            $sec = (Get-Utf8Content 'https://data.sec.gov/submissions/CIK0001318605.json' $h $Config) | ConvertFrom-Json
        }
        $f = @(ConvertFrom-SecSubmissions $sec $days)
        foreach ($x in $f) { $all.Add($x) }
        $sources.Add([ordered]@{ name = 'SEC EDGAR'; ok = $true; items = $f.Count })
    } catch {
        Write-Log "Nyheder: SEC fejlede: $($_.Exception.Message)" 'WARN'
        $sources.Add([ordered]@{ name = 'SEC EDGAR'; ok = $false; error = $_.Exception.Message })
    }

    # Nasdaq RSS
    try {
        if ($OfflineDir) { $xml = Get-Content -Raw -Encoding UTF8 (Join-Path $OfflineDir 'nasdaq-sample.xml') }
        else {
            $h = @{ 'User-Agent' = $Config.UserAgent; 'Accept' = 'application/rss+xml, application/xml, text/xml' }
            $xml = Get-Utf8Content 'https://www.nasdaq.com/feed/rssoutbound?symbol=TSLA' $h $Config
        }
        $cut = [DateTime]::UtcNow.AddDays(-$days)
        $f = @(ConvertFrom-NasdaqRss $xml | Where-Object { $_.Time -ge $cut })
        foreach ($x in $f) { $all.Add($x) }
        $sources.Add([ordered]@{ name = 'Nasdaq RSS'; ok = $true; items = $f.Count })
    } catch {
        Write-Log "Nyheder: Nasdaq RSS fejlede: $($_.Exception.Message)" 'WARN'
        $sources.Add([ordered]@{ name = 'Nasdaq RSS'; ok = $false; error = $_.Exception.Message })
    }

    # Flet med cache, så nyheder ikke forsvinder hvis en kilde fejler en dag
    $cacheFile = Join-Path $CacheDir 'news.json'
    $map = @{}
    if (Test-Path $cacheFile) {
        foreach ($c in @(Get-Content -Raw $cacheFile | ConvertFrom-Json | ForEach-Object { $_ })) {
            $t = if ($c.time -is [datetime]) { $c.time.ToUniversalTime() } else { [DateTimeOffset]::Parse([string]$c.time, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime }
            $map[$c.key] = [pscustomobject]@{ Title = $c.title; Link = $c.link; Time = $t; Source = $c.source; Feed = $c.feed; Kind = $c.kind; Items = @($c.items) }
        }
    }
    foreach ($x in $all) {
        $key = ($x.Title.ToLowerInvariant() -replace '[^a-z0-9]', '')
        if ($key.Length -gt 80) { $key = $key.Substring(0, 80) }
        $map[$key] = $x
    }
    $cut = [DateTime]::UtcNow.AddDays(-$days)
    $merged = @($map.GetEnumerator() | Where-Object { $_.Value.Time -ge $cut } | Sort-Object { $_.Value.Time } -Descending)

    $cacheOut = @($merged | ForEach-Object { [ordered]@{ key = $_.Key; title = $_.Value.Title; link = $_.Value.Link; time = $_.Value.Time.ToString('yyyy-MM-ddTHH:mm:ssZ'); source = $_.Value.Source; feed = $_.Value.Feed; kind = $_.Value.Kind; items = @($_.Value.Items) } })
    [IO.File]::WriteAllText($cacheFile, (ConvertTo-Json -InputObject $cacheOut -Depth 5 -Compress), (New-Object System.Text.UTF8Encoding($false)))

    $items = New-Object System.Collections.Generic.List[object]
    foreach ($e in ($merged | Select-Object -First $Config.NewsMaxItems)) {
        $x = $e.Value
        $cl = Get-NewsClassification $x
        $o = [ordered]@{
            title  = $x.Title
            link   = $x.Link
            time   = $x.Time.ToString('yyyy-MM-ddTHH:mm:ssZ')
            source = $x.Source
            feed   = $x.Feed
            kind   = $x.Kind
        }
        foreach ($k in $cl.Keys) { $o[$k] = $cl[$k] }
        $items.Add($o)
    }
    $arr = $items.ToArray()

    $counts = [ordered]@{
        positive = @($arr | Where-Object { $_.tone -eq 'positive' }).Count
        neutral  = @($arr | Where-Object { $_.tone -eq 'neutral' }).Count
        negative = @($arr | Where-Object { $_.tone -eq 'negative' }).Count
    }
    $catCounts = [ordered]@{}
    foreach ($k in $script:NewsCategories.Keys) {
        $c = @($arr | Where-Object { $_.categories -contains $k }).Count
        if ($c -gt 0) { $catCounts[$script:NewsCategories[$k].label] = $c }
    }

    return [ordered]@{
        status     = if ($arr.Count -gt 0 -or @($sources | Where-Object { $_.ok }).Count -gt 0) { 'ok' } else { 'error' }
        days       = $days
        sources    = $sources.ToArray()
        risk       = Get-NewsRisk $arr
        counts     = $counts
        categories = $catCounts
        method     = 'Kategori og tone findes med faste nøgleord i overskriften. Tone = antal positive minus antal negative ord. Reglerne forstår ikke ironi, spørgsmål eller negationer.'
        items      = $arr
    }
}
