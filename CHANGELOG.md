# Changelog

Alle noemenswaardige wijzigingen in dit project worden hier vastgelegd. Het formaat volgt [Keep a Changelog](https://keepachangelog.com/nl/1.1.0/) en de versies volgen [SemVer](https://semver.org/).

## [2.0.0] — 2026-10-02

Grote repository-, veiligheids- en documentatiemodernisering. Deploymentgedrag op supported hardware is ongewijzigd; nieuwe guardrails zijn strikt faalveilig (ze stoppen méér, schrijven nooit méér weg).

### Added

- **Canonical manifest v2** (`config/sources.json`): SystemSKU-allowlists en weigerlijsten per profiel (op basis van de officiële Microsoft Surface SystemSKU-referentie), lifecycle-EOL-data per driverpakket, expliciete lijst van niet-ondersteunde varianten, `nextRefresh`-sectie (SafeOS DU KB5125758, Windows 26H2-evaluatie, Machine Identity Isolation-watch) en per-profiel `physicalValidation`-status. Het manifest reist mee op de stick en wordt door de deployment gelezen.
- **Veiligheidsbibliotheek** `src/winpe/RSS-SafetyLib.ps1`: alle beslisfuncties (model-/SKU-detectie, mediaherkenning, doelschijfselectie, hashcontrole) als pure, testbare functies.
- **Pre-wipe hashcontrole:** SHA-256 van het modelspecifieke Windows-image én het driverarchief wordt vóór de aftelling tegen het manifest gecontroleerd (INVALID = STOP).
- **NVMe-eenduidigheid:** de doelschijf moet de enige interne NVMe-schijf zijn én op Disk 0 liggen; meerdere NVMe-schijven of een verplaatste NVMe is een veilige stop (voorheen werd bij afwijkingen blind Disk 0 gewist).
- **SystemSKU-controle:** lege, onbekende of geweigerde SKU's stoppen de deployment (UNKNOWN/UNSUPPORTED = STOP).
- **Pester-guardrailtests** (`tests/`): 33 gemockte tests over de volledige gevaarmatrix; raken nooit echte disks; draaien in CI.
- **CI** (`.github/workflows/validate.yml`): PSScriptAnalyzer 1.25.0, Pester 5.7+, manifestconsistentie, interne linkcheck, gitleaks-secretscan, afwezigheid van Microsoft-binaries in Git. Voert nooit een deployment of download uit.
- **Repository-hygiene:** CONTRIBUTING.md, SECURITY.md, CHANGELOG.md, PR-/issue-templates, `.editorconfig`, `.gitattributes`, Dependabot (alleen Actions-pinning).
- **Documentatiepipeline** `tools/Build-Documentation.ps1`: DOCX (pandoc + referentiethema, koptekst/voettekst met paginanummers) en PDF (Typst, inhoudsopgave met paginanummers) uit één canonical bron (`docs/source/**` + manifesttokens), plus gegenereerde stickdocumentatie en het README-versieblok.
- **Onderhoudstools:** `tools/Build-Checksums.ps1` (herbouwt SHA256SUMS.txt uit `git ls-files`), `tools/Test-ManifestConsistency.ps1` (headless manifest-/outputcontrole), `tools/Test-InternalLinks.ps1`.
- **OOBE-documentatie op basis van actueel onderzoek (2026-10):** vijf OOBE-foutklassen (image/netwerk/Microsoft-service/Autopilot-MDM/regressie), officiële diagnosepaden en eventlog-locaties; `tools/Collect-RSSOOBEDiag.ps1` (overgeheveld van branch `refresh-2026-09-sf8`) als read-only collector.

### Changed

- `Validate-RSSMedia.ps1`: profiellijsten uit het manifest i.p.v. hardcoded; nieuwe controles op manifest-identiteit (sources.json op stick == repo), guardrail-aanwezigheid in de deploymentlogica en manifestconsistentie van RSS-INFO.txt; AST-controle nu ook voor `RSS-SafetyLib.ps1`.
- `Update-RSSMedia.ps1`: kapotte placeholder-DISM-aanroep in de Image-fase verwijderd; downloads gehard (`--fail --retry 3 --connect-timeout 30`, partiële downloads worden opgeruimd); Media-fase plaatst `sources.json` en gegenereerde stickdocumentatie op de stick; BootWim-fase kopieert de veiligheidsbibliotheek mee.
- `Test-DriverArchives.ps1`: manifestgedreven (INF-aantallen staan niet langer dubbel in het script).
- README volledig opnieuw ontworpen (badges, Mermaid-flow, generated hardwareblok, valideringsniveaus, releaseproces).
- Stickdocumentatie (`RSS-INFO-production.txt`, `LEESMIJ-AUTOINSTALL.txt`) wordt nu gegenereerd uit het manifest i.p.v. handmatig bijgehouden.

### Removed

- Verouderde handmatige documentatie: `docs/RSS_Technische_bouw_en_beheerhandleiding.docx/.pdf` (v2.0, 2026-09-23; vervangen door gegenereerde uitgaven; ophalen via tag `rss-2026-09-sf8`), de handmatige `docs/RSS-INFO-production.txt` en `docs/LEESMIJ-AUTOINSTALL.txt` (nu in `docs/generated/stick/`).
- Duplicatie van INF-aantallen en modellijsten in scripts (enige bron: het manifest).

### Validatiestatus van deze release

- Code validated: CI/Pester 33/33 PASS, manifestconsistentie PASS (lokaal geverifieerd).
- Media validated: op basis van de productiestick van 2026-09-23; nieuwe media ná deze modernisering vereisen een nieuwe stickvalidatieronde.
- Physically validated: uitsluitend SF6 (veldtest 2026-09). SF4, SF5, SF7 en SF8 zijn **NOT PHYSICALLY VALIDATED** op de huidige media.
- Production approved: pas na fysieke (her)validatie op nieuwbouw-media.

## [rss-2026-09-sf8] — 2026-09-24

Eerste getagde release van de V2-stick: Windows 11 25H2 build 26200.9457 (nl-NL), ADK 10.1.26100.9457 WinPE-basis, profielen SF4–SF8 met volledige officiële driverpakketten, read-only stickvalidator en technische handleiding. Fysiek gevalideerd op Surface Laptop 6.
