---
title: "RSS — Test- en releaseprocedure"
subtitle: "Van codewijziging naar productievrijgave"
version: "2.0"
classification: "Source-available"
audience: "ICT-beheer, releasemanager"
---

# 1. Doel

Deze procedure beschrijft hoe een wijziging in RSS van code tot goedgekeurde productiestick komt, en welk bewijs per stap vereist is. Kernregel: **softwarematige tests bewijzen nooit fysieke correctheid op Surface-hardware.** De vier vrijgaveniveaus zijn expliciet:

```text
code validated → media validated → physically validated → production approved
```

# 2. Testmatrix

De volledige per-modelmatrix staat in `docs/TESTMATRIX.md`; de fysieke quicklist in `docs/PHYSICAL-TEST-QUICKLIST.md`. Samengevat per apparaat: boot/detectie (Secure Boot, TPM, USB-UEFI, model/CPU/diskdetectie), routing/veiligheid (juiste image en archief, preflight-stops, ARM-weigering), deployment (aftelling, GPT-layout, apply, driverinjectie met exact INF-aantal, BCDBoot, groen scherm), eerste boot (USB verwijderd, OOBE normaal, invoer/touch/Wi-Fi, Apparaatbeheer, Autopilot/Intune, Windows Update-niveau).

Negatieve tests (een keer per release, op een oefenapparaat): niet-ondersteund model toont rood zonder Disk 0 aan te raken; ARM/Snapdragon wordt geweigerd; missend driverarchief stopt veilig; geen enkele stap vraagt invoer; log eindigt op `RESULT=SUCCESS` bij geslaagde runs.

# 3. Validatieopdrachten (softwarematig)

```powershell
# volledige CI-equivalent lokaal (PowerShell 7 aanbevolen):
Invoke-Pester -Path tests                     # guardrailtests (33 stuks, gemockt)
Invoke-ScriptAnalyzer -Path . -Recurse        # linting
.\tools\Test-ManifestConsistency.ps1          # manifest + outputs + checksums

# na een media-build op de kandidaatstick:
.\tools\Validate-RSSMedia.ps1                 # read-only stickvalidatie (0 FAIL vereist)
.\tools\Test-DriverArchives.ps1 -Root <archieven> -WimlibPath <wimlib>   # optioneel, archieven apart
```

Acceptatie: Pester 0 FAIL; ScriptAnalyzer 0 errors; manifestconsistentie groen; stickvalidatie 0 FAIL (WARN's toelichten in de release).

# 4. Fysieke testprocedure (per model)

1. Kandidaatstick identificeren: boot.wim-hash + `RSS-INFO.txt` noteren.
2. Quicklist doorlopen (`docs/PHYSICAL-TEST-QUICKLIST.md`) en invullen: apparaat, datum, tester, alle checkpoints.
3. Negatieve fysieke test op minimaal één apparaat per release (stick moet veilig stoppen).
4. Resultaat vastleggen: geslaagde checkpoints, afwijkingen, logbestand.

Statusregistratie: de fysieke status per model wordt vastgelegd in `config/sources.json` (`physicalValidation` per profiel) en zichtbaar gemaakt in README en handleiding. Ongeteste modellen blijven expliciet **NOT PHYSICALLY VALIDATED**.

# 5. Vrijgavegates

| Gate | Vereiste | Bewijs |
|---|---|---|
| CI groen | syntax, PSSA, Pester, manifestconsistentie, links, secretscan, geen binaries | GitHub Actions-run op de releasecommit |
| Media validated | `Validate-RSSMedia.ps1` 0 FAIL op de kandidaatstick | validatierapport |
| Physical | per beoogd model een geslaagde volledige deployment + eerste boot | ingevulde quicklists |
| Documentation | DOCX/PDF opnieuw gegenereerd uit het manifest (`Build-Documentation.ps1`) en visueel gecontroleerd | docs/generated/ |
| Checksums | `Build-Checksums.ps1` gedraaid; SHA256SUMS.txt actueel | checksums/ |
| Manifest | releasevelden bijgewerkt (tag, datum, boot.wim-hash, validationState) | config/sources.json |

# 6. Sign-off

```text
Release:        v____   Tag: ______________
Media:          Windows ____ , drivers ____, boot.wim SHA-256 ______________
CI:             groen? JA/NEE   run: ______________
Stickvalidatie: PASS/WARN/FAIL  rapport: ______________
Fysiek getest:  SF4 [ ]  SF5 [ ]  SF6 [ ]  SF7 [ ]  SF8 [ ]  (quicklists bijgevoegd)
Known limitations: ______________________________
Goedgekeurd door: ______________  Datum: ____-__-____  Production approved: JA/NEE
```

# 7. Na de release

1. Tag pushen (`vX.Y.Z`) en in het manifest terugvermelden.
2. CHANGELOG-entrie controleren (Have-a-Changelog-formaat).
3. Productiesticks labelen met tag + datum + boot.wim-hash (kort); oude productiestick buiten bedrijf stellen (label "INGERUKT").
4. Fysieke validatiestatus per model bijwerken in het manifest zodra nieuwe veldtests zijn gedaan.
