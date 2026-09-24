# TSLA Swing Trader

Analyse af swing trade setups i TSLA med en horisont på 2 dage til 3 uger.
PowerShell på en lokal server er datamotoren. GitHub Pages viser resultatet.

**Status: Fase 1** (kurser, indikatorer, regelbaserede signaler og graf).

Siden er et analyseværktøj og ikke investeringsrådgivning.

## Struktur

```text
C:\Tools\TSLA
├── Update-TSLA.ps1            Hovedscript. Hent, beregn, skriv JSON, commit, push
├── Config.ps1                 Indstillinger. Ingen hemmeligheder her
├── Install-ScheduledTask.ps1  Opretter planlagt opgave på hverdage
├── Engine
│   ├── DataProvider.ps1       Yahoo, Tiingo og fil (test)
│   ├── Indicators.ps1         EMA, SMA, RSI, MACD, ATR, volumen, high/low
│   └── Signals.ps1            Farveregler for de tekniske signaler
├── data                       JSON til frontend (committes)
│   ├── tsla.json              Aktuel status, indikatorer og signaler
│   └── tsla-history.json      Ca. 3 års dagsdata til grafen
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

## Næste fase

Fase 2: Find historiske dage med lignende tekniske forhold og mål afkast efter 2, 3, 5, 10, 15 og 20 handelsdage samt max op og max drawdown.
