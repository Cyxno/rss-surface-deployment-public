# Contributing

Dit is een **source-available** project zonder opensourcelicentie; de repository wordt onderhouden door de eigenaar. Externe pull requests worden niet geaccepteerd; een issue met duidelijke reproductiestappen is welkom.

## Kernregel: bewijs vóór wijziging

De deploymentlogica is destructief. Verander geen werkende logica alleen omdat een alternatief mooier lijkt:

1. reconstrueer eerst de huidige werking (lees `src/winpe/RSS-SafetyLib.ps1`, `RSS-Deploy.ps1` en de technische handleiding);
2. wijzig alleen met aantoonbare reden (veiligheid, gedocumenteerde bug, gedocumenteerde Microsoft-wijziging);
3. bewijs met tests: nieuwe beslislogica hoort in `RSS-SafetyLib.ps1` (pure functies) en krijgt Pester-dekking in `tests/`;
4. fail-safe heeft voorrang op beschikbaarheid: `UNKNOWN/AMBIGUOUS/UNSUPPORTED/MISSING/INVALID = STOP`.

## Een wijziging doorlopen

1. **Branch** vanaf `main`.
2. **Manifest eerst:** versies, hashes, INF-aantallen, SKU's en modellen staan uitsluitend in `config/sources.json`. Voeg nergens anders een kopie toe; lees de waarde uit het manifest.
3. **Tests lokaal** (PowerShell 5.1 of 7+, geen administrator nodig):
   ```powershell
   Invoke-Pester -Path tests
   Invoke-ScriptAnalyzer -Path . -Recurse -Settings .PSScriptAnalyzerSettings.psd1
   ./tools/Test-ManifestConsistency.ps1
   ./tools/Test-InternalLinks.ps1
   ```
4. **Documentatie:** wijzigingen aan inhoud gaan in `docs/source/**` (Markdown met `{{manifest.pad}}`-tokens); regenereer daarna DOCX/PDF/stickdocs en het README-blok:
   ```powershell
   ./tools/Build-Documentation.ps1
   ```
   Vereist pandoc ≥ 3.6 en Typst ≥ 0.15 (of gebruik `-StickDocsOnly` zonder die tools). Genereer de outputs **nooit handmatig**; `docs/generated/` is machine-output.
5. **Checksums** na elke bestandswijziging:
   ```powershell
   ./tools/Build-Checksums.ps1
   ```
6. **Commit:** één logisch thema per commit; commitmessages als `feat: …`, `fix: …`, `docs: …`, `chore: …`, `build: …`.
7. **Pull request:** vul de template in. CI valideert syntax, linting, Pester, manifestconsistentie, interne links, secrets (gitleaks) en afwezigheid van binaries.

## Regels

- **Nooit** secrets, wachtwoorden, productsleutels, serienummers, hardware-hashes, deploymentlogs of tenant-identifiers committeren.
- **Nooit** Microsoft-binaries (`.wim/.esd/.msi/.msu/.iso/.cab`) committeren; `.gitignore` en CI bewaken dit.
- **Nooit** een hash of download-URL verzinnen/gokken: verifieer tegen de officiële Microsoft-bron en leg de datum van verificatie in het manifest vast (`verifiedCurrent`-velden).
- **Nooit** nieuwe Surface-modellen "stil" ondersteunen: een nieuw profiel = manifestuitbreiding (SKU's, driverpakket, INF-telling na extractie), load-order, Pester-fixture en een eigen fysieke testronde.
- Wijzigingen in `RSS-Deploy.ps1`/`RSS-SafetyLib.ps1` vereisen een **media-herbouw en fysieke test** vóór productie; vermeld de status in de PR.
- Wijzig een productiestick nooit rechtstreeks; werk via `Update-RSSMedia.ps1` op een kandidaatstick.

## Releases

Releases volgen `docs/source/procedure/RSS_Test_en_releaseprocedure.md`: semver-tag (`vX.Y.Z`), CHANGELOG-entrie, actuele checksums en de vier expliciete gates (code / media / physical / production approved).
