# TSLA Swing Trader

Analyse af swing trade setups i TSLA med en horisont på 2 dage til 3 uger.
PowerShell på en lokal server er datamotoren. GitHub Pages viser resultatet.

**Status: Fase 6** (alle faser: kurser, indikatorer, signaler, historiske setups, trade levels, status, nyheder, events og evaluering af modellen).

Siden er et analyseværktøj og ikke investeringsrådgivning.

## Struktur

```text
C:\Tools\TSLA
├── Update-TSLA.ps1            Hovedscript. Hent, beregn, skriv JSON, commit, push
├── Config.ps1                 Indstillinger. Ingen hemmeligheder her
├── Install-ScheduledTask.ps1  Opretter planlagt opgave på hverdage
├── Backfill-Setups.ps1        Fase 6: beregner modellens setups bagud (køres én gang)
├── Engine
│   ├── DataProvider.ps1       Yahoo, Tiingo og fil (test)
│   ├── Indicators.ps1         EMA, SMA, RSI, MACD, ATR, volumen, high/low
│   ├── Signals.ps1            Farveregler for de tekniske signaler
│   ├── HistoricalSetups.ps1   Fase 2: lignende historiske dage og deres udvikling
│   ├── TradeLevels.ps1        Fase 3: entry, stop, targets og samlet status
│   ├── News.ps1               Fase 4: nyheder fra SEC EDGAR og Nasdaq RSS
│   ├── Events.ps1             Fase 5: kommende events og event risk
│   └── SetupLog.ps1           Fase 6: log og evaluering af setups
├── Events.json                Event-kalender (vedligeholdes manuelt)
├── data                       JSON til frontend (committes)
│   ├── tsla.json              Aktuel status, indikatorer og signaler
│   ├── tsla-history.json      Ca. 3 års dagsdata til grafen
│   └── setups-log.json        Alle loggede setups og deres udfald
├── Cache                      Fuld kurshistorik (ikke i Git)
├── Logs                       Kørselslog pr. dag (ikke i Git)
├── Tests
│   └── sample-synthetic.json  Syntetiske testdata. Ikke rigtige TSLA-kurser
├── index.html
└── assets                     CSS, JS og graf-bibliotek
```

## Kom i gang

1. Kopiér filerne ind i `C:\Tools\TSLA` (repo-roden).
2. Test uden netværk og uden Git:
   ```powershell
   .\Update-TSLA.ps1 -Provider File -SampleFile .\Tests\sample-synthetic.json -NoGit
   ```
3. Slet `data`, `Cache` og `Logs` igen så testdata ikke ender på siden.
4. Kør med rigtige data uden Git og tjek `data\tsla.json`:
   ```powershell
   .\Update-TSLA.ps1 -NoGit
   ```
5. Kør normalt. Scriptet committer og pusher kun hvis data er ændret:
   ```powershell
   .\Update-TSLA.ps1
   ```
6. Slå GitHub Pages til: Settings > Pages > Deploy from a branch > `main` / root.
7. Planlæg kørslen (hverdage 22:45 dansk tid):
   ```powershell
   .\Install-ScheduledTask.ps1
   ```
   Opgaven kører kun når brugeren er logget på. Vælg "Run whether user is logged on or not" i Task Scheduler hvis den skal køre altid.

Lokal visning af siden kræver en webserver fordi `fetch()` ikke virker fra `file://`. For eksempel `python -m http.server` i mappen.

## Datakilder

| Kilde | Nøgle | Historik | Bemærkning |
|---|---|---|---|
| **Yahoo Finance chart v8** (standard) | Nej | 5 år+ | Uofficielt endpoint. Kan ændre sig uden varsel. Kun til personlig brug |
| **Tiingo** (fallback) | Gratis | 30 år | 50 kald/time, 1.000/dag. Gratis plan må ikke vises for andre |
| Alpha Vantage | Gratis | Kun 100 dage gratis | Fuld historik kræver betalt plan |
| Stooq | Kræver nu apikey | Lang | Ikke valgt |

Tiingo aktiveres ved at sætte en brugermiljøvariabel på serveren:

```powershell
[Environment]::SetEnvironmentVariable('TIINGO_API_KEY', '<din nøgle>', 'User')
```

Nøglen må aldrig ligge i repo'et.

**Licens:** Både Yahoo og Tiingo gratis tillader kun personlig brug. Et offentligt GitHub Pages-site der viser kursdata kan være i strid med vilkårene. Hold siden for dig selv eller afklar vilkårene før den deles.

## Indikatorer

| Indikator | Definition |
|---|---|
| 20 EMA | alpha = 2/21. Start = SMA af de første 20 |
| 50 / 200 SMA | Simpelt gennemsnit af lukkekurs |
| RSI 14 | Wilder smoothing |
| MACD | EMA12 - EMA26. Signal = EMA9 af MACD |
| ATR 14 | Wilder smoothing af True Range |
| Volumen-ratio | Dagens volumen / gennemsnit af de 20 foregående dage |
| 20d / 52u high-low | Højeste high og laveste low over 20 / 252 handelsdage |
| ATR percentil | Dagens ATR% sammenlignet med de seneste 252 dage |

Indikatorerne er kontrolleret mod en uafhængig Python/pandas-beregning på testdata.

## Signalregler

| Signal | Grøn | Gul | Rød |
|---|---|---|---|
| 20 EMA | Kurs over og EMA stigende (5 dage) | Blandet | Kurs under og EMA faldende |
| 50 SMA | Samme, hældning over 10 dage | Blandet | Samme |
| 200 SMA | Samme, hældning over 20 dage | Blandet | Samme |
| RSI 14 | 50-70 | 40-50 eller over 70 | Under 40 |
| MACD | Over signal og over 0 | Blandet | Under signal og under 0 |
| Volumen | Ratio ≥ 1,2 på op-dag | Ellers | Ratio ≥ 1,2 på ned-dag |
| Volatilitet | ATR-percentil under 70 | 70-90 | Over 90 |

Kort, mellem og lang trend svarer til 20 EMA, 50 SMA og 200 SMA.

## Tredjepart

Grafer: [TradingView Lightweight Charts™](https://www.tradingview.com/) 4.2.3, Apache License 2.0. Se `assets/vendor/lightweight-charts.LICENSE`.

## Fase 2: Historiske lignende setups

Modellen finder de 40 handelsdage i de seneste 5 år der ligner i dag mest, og måler hvad der skete bagefter.

**Features** (alle skalafri):

| Feature | Beregning |
|---|---|
| RSI 14 | Som ovenfor |
| Afstand til 20 EMA, 50 SMA, 200 SMA | (kurs / MA - 1) x 100 |
| MACD-histogram / ATR | Momentum målt i forhold til volatilitet |
| Volumen-ratio | Logaritme af volumen / 20d gns. |
| ATR percentil | Volatilitet i forhold til det seneste år |
| Afstand til 52u high | (kurs / 52u high - 1) x 100 |
| 50 SMA hældning | Ændring i 50 SMA over 10 dage i % |

**Metode**

1. Features standardiseres (z-score) over søgevinduet.
2. Afstand = RMS af z-forskellene. Alle features vægter ens.
3. De 40 nærmeste dage vælges, med mindst 5 handelsdage imellem, så samme situation ikke tæller flere gange.
4. For hvert match måles afkast efter 2, 3, 5, 10, 15 og 20 dage (lukkekurs til lukkekurs) samt max op og max ned inden for 5, 10 og 20 dage (high og low).
5. Alt sammenlignes med **"Alle dage"**: udviklingen efter samtlige dage i søgevinduet. Et match er kun interessant hvis det er bedre end en tilfældig dag.

Kun dage med 20 dages kendt fremtid kan være matches. Features bruger kun data til og med dagen selv.

**Forbehold:** Matchenes perioder overlapper, og 40 observationer er ikke meget. Forskelle på få procentpoint fra "Alle dage" kan være tilfældige.

Indstillinger i `Config.ps1`: `ModelYears`, `MatchCount`, `MatchMinGap`.

## Fase 3: Entry, stop, targets og status

Kun long-setups. Alle regler er faste.

| Niveau | Regel |
|---|---|
| Support | 20 EMA, 50 SMA, 200 SMA, 20d low og swing lows (120 dage) under kursen |
| Modstand | 20d high, 52u high, 50/200 SMA og swing highs (250 dage) over kursen |
| Swing low/high | Laveste low / højeste high blandt 3 dage før og efter |
| Entry high | Seneste lukkekurs |
| Entry low | Nærmeste support 0,25-1,5 ATR under kursen. Ellers kurs - 0,75 ATR |
| Stop | Næste support under entry low - 0,25 ATR. Risiko holdes mellem 1 og 3 ATR |
| Target 1 | Nærmeste modstand mindst 1 ATR over entry. Ellers 2R |
| Target 2 | Næste modstand mindst 1 ATR over T1. Ellers max(T1 + 1,5 ATR, 3R) |
| Horisont | 25-75% af antal dage til T1 blandt historiske matches der ramte |

Niveauer der ligger inden for 0,2% af hinanden slås sammen.

**Historisk test:** Samme procentafstande lægges på de 40 matches fra fase 2. Det tælles om Target 1 eller stop blev ramt først inden for 20 dage. Samme dag tæller som stop.

**Status**

| Krav | Opfyldt | Gør setup uinteressant |
|---|---|---|
| Trend-score (20 EMA, 50 SMA, 200 SMA, RSI, MACD) | ≥ 2 | ≤ -2 |
| Risk/reward til T1 | ≥ 1,5 | < 0,8 |
| Historisk T1 før stop | ≥ 50% | < 35% |
| Matches mod alle dage, median 10 dage | ≥ 0 | |
| Volatilitet | ikke rød | |
| Event risk (fase 5) | ikke høj | |

- INTERESSANT: alle krav opfyldt.
- UINTERESSANT: mindst ét krav i højre kolonne.
- AFVENT: resten.

Event risk indgår ikke endnu (fase 5).

## Fase 4: Nyheder

**Kilder**

| Kilde | Indhold | Nøgle |
|---|---|---|
| SEC EDGAR (`data.sec.gov`) | Teslas egne 8-K, 10-Q og 10-K. Item 2.02 = regnskab | Ingen, men kontakt-email i User-Agent |
| Nasdaq RSS | Artikler om TSLA fra bl.a. Motley Fool, Zacks, Barchart | Ingen |

Tesla IR har ikke et RSS-feed. Teslas væsentlige meddelelser indberettes også som 8-K til SEC.

SEC kræver en kontakt-email. Sæt den som miljøvariabel på serveren, så den ikke ligger i det offentlige repo:

```powershell
[Environment]::SetEnvironmentVariable('TSLA_SEC_CONTACT', 'din@email.dk', 'User')
```

Uden variablen springes SEC over og loggen skriver en advarsel.

**Klassifikation:** Faste nøgleord i overskriften giver kategori (Earnings, Deliveries, Regulering, Robotaxi, FSD, Optimus, Modeller, Kina, Musk, Analytiker, Makro) og tone (antal positive minus negative ord). De ord der udløste resultatet vises ved hver nyhed. Earnings, Deliveries, Regulering og SEC-indberetninger har høj betydning. Overskrifter der er spørgsmål tæller ikke som høj betydning.

**News risk**

- Høj: negativ nyhed med høj betydning inden for 2 dage, eller mindst 3 negative inden for 3 dage.
- Moderat: mindst 1 negativ inden for 3 dage, eller en nyhed med høj betydning inden for 2 dage.
- Lav: ellers.

Nyheder gemmes i `Cache/news.json`, så de ikke forsvinder hvis en kilde fejler en dag.

**Begrænsning:** Reglerne forstår ikke ironi eller negationer. "BYD gains share" er dårligt for Tesla, men ordene alene siger det ikke.

## Fase 5: Events

Kalenderen ligger i `Events.json` og vedligeholdes manuelt. Den indeholder:

| Type | Kilde | Status |
|---|---|---|
| FOMC | [Federal Reserve](https://www.federalreserve.gov/monetarypolicy/fomccalendars.htm) | Bekræftet |
| CPI | [BLS](https://www.bls.gov/schedule/news_release/cpi.htm) | Bekræftet |
| Tesla earnings | Kalendertjenester indtil Tesla bekræfter på [IR](https://ir.tesla.com/) | Estimat, indtil bekræftet |
| Tesla deliveries | Mønster: 2. hverdag i kvartalet | Estimat |

Mangler Tesla-datoer for de næste 2 kvartaler, laves automatiske estimater (deliveries: 2. hverdag i kvartalet, earnings: 4. onsdag i første måned). Ret `confirmed` til `true` og datoen når Tesla melder den ud.

Loggen advarer når der ikke er FOMC/CPI-datoer mere end 30 dage frem. Så skal næste års datoer tilføjes. Helligdage i `holidays` bruges til at tælle handelsdage.

**Event risk**

- Høj: Tesla earnings/deliveries inden for 5 handelsdage, eller FOMC/CPI i dag eller i morgen.
- Moderat: Tesla earnings/deliveries inden for 15 handelsdage, eller FOMC/CPI inden for 5 handelsdage.
- Lav: ellers.

Event risk indgår som krav i setup-status: Høj event risk giver AFVENT, men aldrig UINTERESSANT. Det er information om risiko og ikke et signal om at sælge.

## Tema

Siden bruger mørkt tema som standard. Knappen øverst skifter til lyst tema, og valget huskes i browseren.

## Fase 6: Evaluering af modellen

Hver aften gemmes dagens setup i `data/setups-log.json`: status, niveauer og den historiske forventning. Ved hver kørsel evalueres alle tidligere setups:

- Afkast efter 2, 5, 10 og 20 handelsdage.
- Udfald med entry på setup-dagens lukkekurs: Target 1 før stop, stop først, eller ingen af dem på 20 dage (lukket på dag 20). Samme dag tæller som stop.
- R = resultat i forhold til risikoen (lukkekurs - stop).

Siden viser resultat pr. status og om forventningen passer: når modellen forventede fx over 55% positive, hvor mange blev det så faktisk?

**Bagud-beregning:** For at få historik med det samme kan modellen køres bagud:

```powershell
.\Backfill-Setups.ps1 -Days 250
.\Update-TSLA.ps1
```

For hver dag bruges kun de kurser der fandtes den dag. Det er testet ved at køre det almindelige script på data der er skåret af på en given dag: resultatet er identisk. Nyheder og events kan ikke genskabes bagud og indgår ikke. Bagud-beregnede setups er markeret med *. Live-setups bliver aldrig overskrevet.

Kørslen tager nogle minutter (ca. 75 sek. for 250 dage i PowerShell 7, længere i 5.1).

**Forbehold:** Setups fra dag til dag overlapper og ligner hinanden. 250 dage er derfor ikke 250 uafhængige forsøg. Brug tallene til at se tendenser, ikke som bevis.
