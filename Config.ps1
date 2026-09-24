# TSLA Swing Trader - konfiguration
# Ingen hemmeligheder i denne fil. API-nøgler læses fra miljøvariabler.

$Config = @{
    Symbol          = 'TSLA'

    # Datakilde: 'Yahoo' (ingen nøgle, uofficielt endpoint) eller 'Tiingo' (gratis nøgle i $env:TIINGO_API_KEY)
    DataProvider    = 'Yahoo'
    FallbackProvider = 'Tiingo'   # Bruges hvis den primære fejler. Sæt til $null for at slå fra.

    # Hvor meget historik der hentes ved hver kørsel. Cachen gemmer alt og vokser over tid.
    HistoryYears    = 5

    # Hvor mange handelsdage frontend-grafen får med
    ChartBars       = 756          # ca. 3 år

    # Stier (relativt til repo-roden)
    DataDir         = 'data'
    CacheDir        = 'Cache'
    LogDir          = 'Logs'

    # Git
    GitEnabled      = $true
    GitCommitMessage = 'Update TSLA data'

    # Http
    UserAgent       = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) TSLA-Swing-Trader/1.0'
    TimeoutSec      = 30
}
