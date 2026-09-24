# TSLA Swing Trader

Et website der hjælper med at vurdere om der er et interessant **swing trade setup** i Tesla-aktien (TSLA) lige nu. Tidshorisonten er fra ca. 2 dage til 3 uger.

Siden giver ikke et "køb nu"-signal. Den viser zoner, niveauer og scenarier og forklarer hvorfor. Alle vurderinger bygger på faste regler, som kan ses direkte på siden.

> Siden er et analyseværktøj og ikke investeringsrådgivning. Signalerne er regelbaserede og kan tage fejl.

## Hvad viser siden?

| Sektion | Indhold |
|---|---|
| **Current setup** | Samlet status (INTERESSANT, AFVENT eller UINTERESSANT), entry-zone, stop, targets, risk/reward og forventet horisont. Hvert krav vises med ✓ eller ✗ og en forklaring |
| **Technical trend** | Kort, mellem og lang trend samt RSI, MACD, volumen og volatilitet med grøn, gul eller rød. Under signalerne står en forklaring i klart sprog, og hvad der skal til for at status skifter |
| **Min position** | Indtast købsdato og kurs, og se hvor du er i forhold til stop og targets fra den dag du købte. Gemmes kun i din egen browser |
| **Historical matches** | De 40 dage i de seneste 5 år der ligner i dag mest, og hvad kursen gjorde bagefter |
| **Price chart** | Kursgraf med gennemsnit, RSI, MACD og dagens niveauer |
| **News** | Nyheder om Tesla, markeret positiv, neutral eller negativ, med de ord der gav vurderingen |
| **Events** | Kommende earnings, deliveries, rentemøder og inflationstal |
| **Previous setups** | Hvad modellen sagde tidligere, og hvad der faktisk skete bagefter |

## Sådan virker det

```text
Kursdata og nyheder
        |
        v
PowerShell-script på en lokal server (hver hverdag efter børsens lukning)
        |
        +-- Beregner indikatorer
        +-- Finder lignende historiske dage
        +-- Beregner entry, stop og targets
        +-- Vurderer nyheder og kommende events
        +-- Evaluerer tidligere setups
        |
        v
JSON-filer i data/  -->  Git push  -->  GitHub Pages  -->  Websitet
```

Scriptet kører automatisk hver hverdag kl. 22:45 dansk tid, når den amerikanske børs har lukket. Analysen bygger altid på afsluttede handelsdage.

## Modellen i korte træk

**1. Tekniske signaler**
Kursen sammenlignes med 20, 50 og 200 dages gennemsnit, og momentum, volumen og volatilitet måles. Hvert signal får en farve efter en fast regel.

**2. Lignende situationer i historikken**
Dagen i dag beskrives med 9 tal, fx RSI, afstand til gennemsnit og volatilitet. Modellen finder de 40 dage i de seneste 5 år der ligner mest, og måler hvad kursen gjorde efter 2, 3, 5, 10, 15 og 20 handelsdage. Resultatet sammenlignes altid med en tilfældig dag, så man kan se om mønsteret faktisk er bedre end normalt.

**3. Entry, stop og targets**
Niveauerne findes ud fra tidligere top- og bundpunkter, gennemsnit og det normale daglige udsving (ATR). De samme afstande testes på de historiske matches: hvor ofte nåede kursen Target 1 før stop?

**4. Samlet status**

| Status | Betydning |
|---|---|
| 🟢 **INTERESSANT** | Alle 6 krav er opfyldt |
| 🟡 **AFVENT** | Et eller flere krav mangler, men intet er langt fra |
| 🔴 **UINTERESSANT** | Mindst ét krav er langt fra |

De 6 krav er trend, risk/reward, historisk Target 1 før stop, resultat sammenlignet med alle dage, volatilitet og event risk.

**5. Nyheder og events**
Nyheder klassificeres med faste nøgleord. Kommende earnings, deliveries, rentemøder og inflationstal giver en event risk, som indgår i status.

**6. Evaluering**
Hver dags setup gemmes. Bagefter måles hvad der faktisk skete, så det over tid kan ses om modellen har værdi.

## Datakilder

| Kilde | Bruges til |
|---|---|
| Yahoo Finance | Daglige kurser (Tiingo som reserve) |
| SEC EDGAR | Teslas egne indberetninger (regnskaber og væsentlige meddelelser) |
| Nasdaq RSS | Nyhedsartikler om TSLA |
| Federal Reserve og BLS | Datoer for rentemøder og inflationstal |
| Tesla IR og kalendertjenester | Forventede datoer for earnings og deliveries |

Datoerne for events vedligeholdes manuelt i `Events.json`. Datoer der ikke er bekræftet, er markeret som estimat.

## Mapper

```text
Update-TSLA.ps1        Den daglige kørsel
Backfill-Setups.ps1    Beregner modellens setups bagud i tid (køres én gang)
Config.ps1             Indstillinger
Events.json            Kalender med kommende events
Engine/                Beregningerne
data/                  Data til websitet
index.html, assets/    Websitet
Tests/                 Syntetiske testdata (ikke rigtige kurser)
```

## Kom i gang

```powershell
.\Update-TSLA.ps1 -NoGit        # Test uden at pushe
.\Backfill-Setups.ps1           # Historik til "Previous setups" (én gang)
.\Update-TSLA.ps1               # Normal kørsel med push
.\Install-ScheduledTask.ps1     # Daglig kørsel på hverdage
```

Siden kan ses lokalt med en simpel webserver, fx `python -m http.server`.

## Begrænsninger

- Modellen er ny og ikke bevist på rigtige handler. Følg "Previous setups" i en periode, før du lægger vægt på den.
- 40 historiske matches er ikke mange, og dagene overlapper. Små forskelle kan være tilfældige.
- Nyhedsvurderingen læser kun ord i overskriften og forstår ikke ironi eller negationer.
- Kursdata fra de gratis kilder må kun bruges personligt.

## Tredjepart

Grafer: [TradingView Lightweight Charts™](https://www.tradingview.com/), Apache License 2.0. Se `assets/vendor/lightweight-charts.LICENSE`.
