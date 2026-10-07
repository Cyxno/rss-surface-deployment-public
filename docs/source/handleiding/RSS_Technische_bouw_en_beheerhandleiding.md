---
title: "RSS — Technische bouw- en beheerhandleiding"
subtitle: "Surface Deployment Stick — automatische Windows 11-deployment voor Surface Laptop"
version: "2.0"
classification: "Source-available — geen opensourcelicentie"
audience: "ICT-beheer en werkplekbeheer"
---

# 1. Doel, status en leeswijzer

RSS (Surface Deployment Stick) is een volledig geautomatiseerde, bootable Windows 11-deploymentstick voor Microsoft Surface Laptop 4, 5, 6, 7 en 8 (uitsluitend de in dit document genoemde varianten). De stick is ontworpen voor situaties waarin een beheerder bewust vanaf USB opstart en daarbij geen invoerapparaat of interactie nodig heeft.

**In één zin:** boot vanaf USB; RSS detecteert model, SKU en processor, valideert bron- en doelschijf inclusief bestandshashes, wist Disk 0 pas na een aftelling van 15 seconden, past het juiste Windows-image toe, injecteert het volledige officiële Surface-driverpakket en maakt UEFI-bootbestanden aan.

Deze handleiding beschrijft release **{{project.version}}** met productiemedia van **{{project.productionRelease.mediaBuilt}}** (Windows-build {{windows.build}}).

## 1.1 Status en valideringsniveaus

RSS kent vier expliciete valideringsniveaus die niet door elkaar mogen worden gehaald:

| Niveau | Betekenis | Huidige status |
|---|---|---|
| Code validated | CI, syntax- en guardrailtests geslaagd | ja, per commit (CI) |
| Media validated | `Validate-RSSMedia.ps1` groen op een gebouwde stick | ja, op de productiestick van {{project.productionRelease.mediaBuilt}} |
| Physically validated | volledige deployment + eerste boot op fysieke Surface-hardware | uitsluitend SF6 (veldtest {{surfaceDriverPacks.2.physicalValidation.date}}) |
| Production approved | vrijgegeven tag + checksums + testbewijs | tag `{{project.productionRelease.tag}}` |

Modellen zonder fysieke test zijn expliciet **NOT PHYSICALLY VALIDATED** (zie appendix B). Softwarematige tests bewijzen nooit dat een Surface-model fysiek correct deployt.

## 1.2 Ondersteunde hardware

| Profiel | Model | Platform | INF | Status |
|---|---|---|---|---|
{{TABLE:MODELS}}

De volledige SystemSKU-lijst per profiel staat in `config/sources.json`; appendix B bevat de samenvatting. Bekende expliciete weigeringen: Surface Laptop 4 Intel, Surface Laptop 7th Edition Snapdragon, Surface Laptop 5G for Business 7th Edition (SKU `_2119`) en Surface Laptop 8th Edition Snapdragon. Deze modellen zijn veilige stops vóór elke schrijfactie.

## 1.3 KERNWAARSCHUWING

> **RSS wist na een geslaagde preflight en een aftelling van 15 seconden de volledige interne NVMe-schijf (Disk 0) zonder bevestigingsvraag.** Gebruik de stick uitsluitend op een apparaat waarvan de gegevens bewust mogen worden verwijderd.

# 2. Architectuur op hoofdlijnen

```text
USB boot (UEFI, MBR-stick)
  → ADK WinPE (boot.wim, startnet.cmd)
    → PowerShell: RSS-Deploy.ps1 (+ RSS-SafetyLib.ps1)
      → preflight: manifest, model, SKU, CPU, media, disks, hashes
        → aftelling 15 s
          → Disk 0 wissen + GPT (EFI 260 MB, MSR 16 MB, Windows NTFS)
            → DISM /Apply-Image (install.esd index 1)
              → wimlib-uitpakken driverarchief + Add-WindowsDriver (offline)
                → BCDBoot (UEFI)
                  → groen scherm + automatische reboot
                    → eerste boot: Windows → OOBE (normaal, geen bypass)
```

RSS is bewust een zelfstandige deploymentomgeving zonder interactieve Windows Setup en zonder unattend-bestand: het apparaat eindigt in een volledig normale, MDM/Autopilot-geschikte OOBE.

## 2.1 Scheiding van verantwoordelijkheden

| Laag | Verantwoordelijkheid |
|---|---|
| UEFI / MBR | USB vindbaar en bootable maken; actieve FAT32-partitie starten |
| ADK WinPE | PowerShell, WMI, Storage- en DISM-functionaliteit beschikbaar maken |
| `RSS-SafetyLib.ps1` | pure beslisfuncties: model/SKU-detectie, mediaherkenning, doelschijfselectie, hashcontrole |
| `RSS-Deploy.ps1` | orkestratie: preflight, diskindeling, imaging, drivers, boot, logging, visuele fasen |
| `config/sources.json` | enige bron van versies, modellen, SKU's, hashes en INF-aantallen; reist mee op de stick |
| Images-partitie | vijf Windows-images, vijf driverarchieven, WinPE-drivers, manifest, documentatie, log |
| Doel-NVMe | na volledige validatie als GPT-doel voor EFI, MSR en Windows |

## 2.2 Ontwerpprincipes

- **Bewijs vóór wijziging:** deploymentlogica verandert alleen met aantoonbare reden, testdekking en media-herbouw.
- **UNKNOWN/AMBIGUOUS/UNSUPPORTED/MISSING/INVALID = STOP:** elke onzekere situatie is een rode veilige stop vóór de eerste schrijfactie.
- **Eén bron van waarheid:** versies, modellen, SKU's, hashes en INF-aantallen staan uitsluitend in `config/sources.json`; README, validatie en documentatie leiden hiervan af.
- **Geen internet tijdens deployment:** RSS-Deploy gebruikt nooit het netwerk; alleen het onderhoudsscript doet downloads.

# 3. Repositorystructuur

```text
├── .github/            CI-workflow, issue- en PR-templates
├── config/
│   ├── sources.json    CANONICAAL manifest (versies, modellen, SKU's, hashes, INF)
│   └── load-orders/    bewezen WinPE-driverlaadvolgordes per profiel (SF4–SF8)
├── docs/
│   ├── source/         CANONIEKE documentatiebronnen (Markdown + templates)
│   ├── generated/      gegenereerde DOCX/PDF en stickdocumentatie
│   ├── MEDIA-LAYOUT.md, TESTMATRIX.md, PHYSICAL-TEST-QUICKLIST.md
│   └── ...
├── src/winpe/
│   ├── RSS-SafetyLib.ps1   veiligheidsbibliotheek (pure functies, getest)
│   ├── RSS-Deploy.ps1      deploymentorkestratie (draait in WinPE)
│   ├── Build-WinPE.ps1     boot.wim-bouw vanaf de officiële ADK-bron
│   └── startnet.cmd        wpeinit + start RSS-Deploy
├── tools/
│   ├── Update-RSSMedia.ps1     reproduceerbare mediavernieuwing (fases)
│   ├── Validate-RSSMedia.ps1   read-only stickvalidatie
│   ├── Test-DriverArchives.ps1 proefuitpaktest driverarchieven
│   ├── Build-Documentation.ps1 DOCX/PDF/stickdocs-generatie
│   └── Build-Checksums.ps1     herbouw checksums/SHA256SUMS.txt
├── tests/              Pester-guardrailtests (gemockt, raken nooit echte disks)
└── checksums/          SHA256SUMS.txt over alle Git-bestanden
```

Niet in Git: Windows-images, ADK/WinPE-bestanden, Surface-driverpakketten, uitgepakte drivers, gegenereerde WIM/ESD en uitvoeringslogs (zie `.gitignore`). Deze zijn groot, door derden uitgegeven en/of apparaatgebonden; `Update-RSSMedia.ps1` + het manifest reproduceren alles vanuit officiële bronnen.

# 4. Requirements

| Onderdeel | Eisen |
|---|---|
| Bouwwerkstation | Windows 10/11 x64 met PowerShell 5.1 of 7+, lokale administratorrechten |
| ADK | Windows ADK {{adk.version}} + WinPE-add-on, standaardpad `C:\ADK` (installatiepad met subst/symlink toegestaan) |
| wimlib | {{wimlib.version}} Windows x64-binaries (URL en SHA-256 in het manifest), beschikbaar op `D:\RSS-Build\wimlib` |
| Werkmap | minimaal 40 GB vrije ruimte, standaard `D:\RSS-Build` |
| Doelmedium | 64 GB USB 3.x-stick (productieroutering: Samsung), mag volledig gewist worden |
| Bronimage | geservicede `install.wim` uit de UUP-set zoals vastgelegd in het manifest |
| Documentatiebuild | pandoc ≥ 3.6 en Typst ≥ 0.15 (regenereerbaar, zie hoofdstuk 14 en `docs/source/README.md`) |

# 5. Windows-, ADK- en WinPE-basis

## 5.1 Vastgelegde versies

| Onderdeel | Versie | Gecontroleerd |
|---|---|---|
| Windows-editie | {{windows.edition}}, {{windows.architecture}}, {{windows.languageDisplay}} | — |
| Windows-baseline | UUP-set build {{windows.build}} | {{windows.cumulativeUpdate.verifiedCurrent}} |
| LCU | {{windows.cumulativeUpdate.kb}} ({{windows.cumulativeUpdate.released}}) | actueel |
| .NET CU | {{windows.netFrameworkUpdate.kb}} ({{windows.netFrameworkUpdate.released}}) | actueel |
| SafeOS DU (WinRE) | {{windows.winreUpdate.kb}} ({{windows.winreUpdate.released}}); opvolger {{windows.winreUpdate.supersededBy.kb}} bij eerstvolgende herbouw | zie manifest |
| Bewust niet gebruikt | {{windows.notUsed.kb}} ({{windows.notUsed.build}}, preview) | — |
| ADK | {{adk.version}} ({{adk.released}}) | actueel |
| wimlib | {{wimlib.version}} ({{wimlib.released}}) | actueel |

De einddatum van de basis-servicing: Home/Pro {{windows.endOfServicing.homePro}}, Enterprise/Education {{windows.endOfServicing.enterpriseEducation}}.

## 5.2 WinPE-samenstelling

De bootomgeving wordt volledig opgebouwd vanaf de officiële ADK-winpe.wim (geen ISO-boot.wim). Optional components: {{adk.winpeOptionalComponents}} (elk mét en-US-taalpakket), scratchruimte {{adk.winpeScratchSpaceMB}} MB. `Build-WinPE.ps1` verifieert na het inbouwen dat PowerShell, de Storage- en Dism-modules, de DISM-provider, beide deploymentbestanden en wimlib aanwezig zijn, en schrijft de SHA-256 naar `Build-WinPE.status`.

## 5.3 Startketen

`startnet.cmd` voert `wpeinit` uit en start daarna direct `powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File X:\Deploy\RSS-Deploy.ps1`. Er is geen menu, geen invoerapparaat en geen keuze nodig; bij een fout blijft het rode veiligescherm staan.

# 6. Surface-driverbronnen

| Profiel | Microsoft-pakket | Datum | INF | EOL servicing |
|---|---|---|---|---|
{{TABLE:DRIVERS}}

Alle MSI's worden gedownload van `download.microsoft.com` (link per profiel in het manifest), gecontroleerd op SHA-256 én geldige Authenticode-handtekening van Microsoft Corporation, en daarna met `msiexec /a` geëxtraheerd. Het INF-aantal wordt exact tegen het manifest gecontroleerd — een afwijkende telling is altijd een stop, nooit een aanpassing van het verwachte aantal zonder verificatie en manifestupdate.

Driver- en firmware-servicing per model loopt af op de in de tabel genoemde data (bron: Microsoft lifecycle). De vroegste EOL in de vloot is Surface Laptop 4 ({{surfaceDriverPacks.0.lifecycle.driverFirmwareEol}}); plan vervanging of imageactualisatie.

# 7. Modeldetectie en preflight

## 7.1 Detectiebronnen

- SMBIOS `SystemProductName` en `SystemSKU` uit `HKLM:\HARDWARE\DESCRIPTION\System\BIOS`;
- CPU `VendorIdentifier` uit `HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0`;
- `Get-PSDrive` voor exact één RSS-datapartitie (herkenningspaden SF4 + SF8 `install.esd`);
- `Get-Partition`/`Get-Disk` voor de fysieke USB-identiteit en alle NVMe-schijven.

## 7.2 Beslisvolgorde (RSS-SafetyLib)

1. Naam bevat `Snapdragon` → STOP (ARM);
2. strikte regex op `SystemProductName` (vijf profielen) → geen match is STOP;
3. CPU-vendorcontrole per profiel (SF4 = AuthenticAMD, overige = GenuineIntel) → mismatch is STOP;
4. `SystemSKU` leeg → STOP; SKU op de weigerlijst van het profiel → STOP; SKU niet op de allowlist → STOP met instructie om het manifest te verifiëren/bij te werken;
5. manifest ontbreekt of is incompleet → STOP;
6. image of driverarchief ontbreekt, te klein of hash wijkt af → STOP;
7. `dism /Get-WimInfo` op het archief moet index 1 leesbaar opleveren → anders STOP;
8. diskselectie: exact één interne NVMe op Disk 0, media er niet op → anders STOP;
9. pas ná al het bovenstaande start de aftelling van 15 seconden.

De regexes en meldingen zijn bewust identiek aan de bewezen productielogica; nieuwe lagen (SKU-allowlist, NVMe-eenduidigheid, hashcontrole) zijn strikt faalveilig en via `tests/RSS-Safety.Tests.ps1` gedekt.

## 7.3 SystemSKU-allowlists

Elk profiel bevat in het manifest een expliciete lijst ondersteunde SKU's (gebaseerd op de officiële Microsoft Surface SystemSKU-referentie, gecontroleerd {{generated}}) en — waar van toepassing — een weigerlijst. Nieuwe regionale SKU-varianten worden alleen toegevoegd na verificatie tegen de Microsoft-referentie, met manifestupdate, tests en een nieuwe buildronde.

# 8. Driverstrategie

**Twee gescheiden driverlagen:**

1. **Volledig officieel pakket (doel):** na het toepassen van Windows wordt het volledige Microsoft SurfaceUpdate-pakket (alle INF's van het model-MSI) offline in de DriverStore geïnjecteerd. Daardoor werken touchscreen, toetsenbord/Type Cover, touchpad, Wi-Fi, USB, sensoren en platformcomponenten vóór de eerste boot, zonder netwerk.
2. **WinPE-minimalisatie (bouw-/herstelmateriaal):** `RSSWinPEDrivers\SFx` + `config/load-orders` bevatten de minimale driverreeks voor WinPE-initialisatie. De actieve boot.wim start bewust zónder modelgebonden drivers, omdat de ADK-bron met Microsoft-inboxdrivers NVMe en USB betrouwbaar initialiseert; de load-orders zijn de vastgelegde bewezen volgorde voor herstel-/bouwgebruik en worden door de validatie op consistentie gecontroleerd.

**Onderscheid is belangrijk:** een klein setje inputdrivers volstaat om WinPE te bedienen, maar is niet het einddoel; de offline DriverStore moet het volledige pakket bevatten vóór de eerste boot.

# 9. Deploymentflow (runtime)

| Stap | Actie | Veiligheidscontrole |
|---|---|---|
| 0 | initialisatie modules + mediaherkenning | exact één RSS-datapartitie |
| 0b | manifest laden van de stick | manifest aanwezig en compleet |
| 1 | model/SKU/CPU-detectie | allowlists en weigerlijsten |
| 2 | paden + bestanden controleren | image, archief, grootte |
| 3 | fysieke diskherleiding | media ≠ Disk 0, exact één NVMe = Disk 0 |
| 4 | archief leesbaar (DISM) | index 1 |
| 5 | hashcontrole image + archief | manifest-SHA-256, vóór de wipe |
| 6 | samenvatting + aftelling 15 s | annuleren = apparaat uitschakelen |
| 7 | Disk 0 wissen, GPT: EFI 260 MB / MSR 16 MB / Windows NTFS | — |
| 8 | `DISM /Apply-Image /CheckIntegrity` | SYSTEM-hive aanwezig |
| 9 | wimlib-uitpakken archief + INF-telling | exact {{surfaceDriverPacks.2.infCount}}-achtig per profiel |
| 10 | `Add-WindowsDriver -Recurse` | DriverStore-count vóór/na gelogd |
| 11 | `bcdboot /f UEFI /l nl-NL` | `bootmgfw.efi` aanwezig |
| 12 | groen scherm + automatische reboot | USB verwijderen tijdens groen |

Het volledige verloop, inclusief alle DISM-uitvoer, DriverStore-aantallen en resultaatcodes, wordt gelogd naar `<Images>:\RSS-ADK-Deploy.log` (hoofdstuk 21).

# 10. Disk safety

De doelschijfregel is absoluut: **uitsluitend de enige interne NVMe-schijf, in WinPE steeds Disk 0, en nooit het USB-medium.** De faalveilige matrix uit het manifest:

```text
{{TABLE:SAFETY}}
```

- De aftelling van 15 seconden is de laatste annuleringsmogelijkheid: apparaat uitschakelen tijdens de aftelling en de wipe start niet.
- De stick mag nooit in de UEFI-bootvolgorde vóór de interne SSD blijven staan nadat het groene scherm is verschenen; verwijder de USB bij het groene scherm, anders kan dezelfde destructieve deployment herstarten.
- Onverwachte situaties (meerdere NVMe-schijven, NVMe niet op Disk 0, USB op Disk 0, SD/USB-media als doelschijfkandidaat) leiden tot een veilige stop, nooit tot "probeer maar".

# 11. Windows-servicing

De geïnstalleerde basis is een geserviced UUP-image: Engelse Professional-basis 26100.1 + enablement-eKB + checkpoint-LCU + actuele LCU + .NET CU, offline geserviced met ADK-DISM; WinRE wordt afzonderlijk geserviced met de SafeOS DU (WinRE volgt niet de hoofd-LCU). Het resultaat is per profiel `install.esd` (index 1, recovery-compressie) met SHA-256 in het manifest.

Regels bij een nieuwe servicingsronde:

1. Uitsluitend de laatste **stabiele** (niet-preview) cumulatieve update; preview-KB's blijven buiten productie (momenteel bewust: {{windows.notUsed.kb}}).
2. Werk het manifest bij (LCU/SSU/.NET/SafeOS + build + hash) vóór de herbouw en laat de validatie op de nieuwe waarden draaien.
3. SafeOS DU's en .NET-CU's verschijnen op eigen ritme; neem nieuwere versies over bij de eerstvolgende herbouw (zie `nextRefresh` in het manifest) — bouw niet opnieuw uitsluitend voor één pakket.
4. Eén media-build per servicingsronde; tussentijdse "losse" updates op sticks zijn verboden (drift).

# 12. Offline driverinjectie

`wimlib-imagex apply` pakt het driverarchief (ESD, `--check`) tijdelijk uit naar `<Windows>:\RSS-DriverStage`; de INF-telling moet exact het manifestaantal zijn. Daarna registreert `Get-WindowsDriver` het DriverStore-aantal vóór injectie, injecteert `Add-WindowsDriver -Path … -Driver <stage> -Recurse` alle drivers offline en registreert het aantal opnieuw. Een afnemend aantal is een fout; de stagingmap wordt na afloop verwijderd. Alle DISM-uitvoer gaat naar het log.

# 13. OOBE, Autopilot en netwerk

RSS levert het apparaat **onveranderd** aan bij OOBE: geen unattend, geen lokale account, geen netwerkbypass. Dat is een bewuste ontwerpkeuze: de installatie moet juist Autopilot/Intune-inschrijving mogelijk maken. Productkeys, `ms-cxh:localonly`, `BypassNRO` en vergelijkbare trucs zijn verboden in deze productieomgeving (`BypassNRO` is bovendien door Microsoft verwijderd uit de 26200-lijn en `ms-cxh:localonly` is sinds eind 2025 geblokkeerd; de validatie faalt bewust op deze patronen in de deploymentcode).

## 13.1 Verwacht eerste-bootgedrag

- De eerste boot kan één of meer automatische herstarts tonen; een veldtest op SF6 toonde een tijdelijke rebootcyclus van circa vijf minuten die zichzelf herstelde. Wacht bij herhaalde korte reboots minimaal 10 minuten vóór verder onderzoek.
- Na OOBE moeten touchscreen, toetsenbord/trackpad, Wi-Fi en USB direct werken vanuit de offline DriverStore.
- Autopilot: OOBE haalt na netwerkverbinding het Autopilot-profiel op; het apparaat moet in de tenant geregistreerd (hardware-hash + toegewezen profiel) zijn vóór de deployment.

## 13.2 De vijf OOBE-foutklassen

| Klasse | Kenmerk | Eerste diagnose |
|---|---|---|
| Image failure | installatie/bootprobleem vóór OOBE; herstelomgeving of reboot-loop | `C:\Windows\Panther\setupact.log`/`setuperr.log` |
| Network failure | hangt bij "De verbinding met Microsoft wordt gecontroleerd" of valt terug naar Wi-Fi | `Get-NetConnectionProfile` (moet `Internet` tonen), `nslookup dns.msftncsi.com`, `http://www.msftconnecttest.com/connecttest.txt` (moet "Microsoft Connect Test" teruggeven) |
| Microsoft service failure | netwerk OK, OOBE-dienst geeft fout | eventlog `Microsoft-Windows-CloudExperienceHost/Operational`, `NCSI/Operational` |
| Autopilot/MDM failure | profile-hang na netwerkcontrole; "Something went wrong" | eventlog `ModernDeployment-Diagnostics-Provider/Autopilot` (807/815 = niet geregistreerd/geen profiel; 171/172 = TPM-attestatie; 100 = wacht op profiel), `Mdmdiagnosticstool.exe -area Autopilot;TPM -cab C:\autopilot.cab` |
| OOBE regression | nieuw gedrag na build-wisseling | release-healthpagina van de betreffende build; media terugdraaien naar vorige release |

Voor build {{windows.build}} is géén OS-known-issue op OOBE bekend (status {{generated}}); een hang op de netwerkcontrole is daarom in eerste instantie een **omgevingskwestie**: NCSI-probe geblokkeerd (Wi-Fi gebruikt altijd de HTTP-probe naar `www.msftconnecttest.com`), firewall blokkeert Autopilot-endpoints (`ztd.dds.microsoft.com`, `login.live.com`, `*.microsoftaik.azure.net`, `time.windows.com` UDP 123) of het apparaat is nog niet in Autopilot geregistreerd. De NCSI-actieve probe mag nooit worden uitgeschakeld als "oplossing".

## 13.3 Diagnosetool

`tools/Collect-RSSOOBEDiag.ps1` is read-only en verzamelt in een falende OOBE (Shift+F10) alles naar de stick: netwerkprofielen, NCSI-registry en live-probes, Autopilot-endpointprobes, diensten, OOBE-registry, CloudExperienceHost/NCSI/NLA/WLAN-eventlogs, Appx-status en Panther-/OOBE-logbestanden. Gebruik deze tool vóór elke aanname; verwijs in incidenten altijd naar de verzamelde map.

# 14. Media bouwen en vernieuwen

Het volledige proces is geprogrammeerd in `tools/Update-RSSMedia.ps1` (fases: Drivers → Archives → WinPEDrivers → BootWim → Image → Media → Validate). Belangrijkste eigenschappen:

- downloads uitsluitend van de in het manifest vastgelegde officiële URL's, met SHA-256 + Authenticode-controle en partiële-downloadbeveiliging;
- INF-aantallen exact tegen het manifest; archieven worden na bouw proefuitgepakt;
- boot.wim volledig opnieuw vanaf de ADK-bron (inclusief `RSS-SafetyLib.ps1`);
- images geserviced en per profiel geëxporteerd; SafeOS DU en .NET CU vanuit `downloads\`;
- Media-fase weigert Disk 0, niet-USB-media en systeemdisks; partities WINPE (FAT32, 2 GB, actief) en Images (NTFS, rest);
- manifest en gegenereerde stickdocumentatie worden op de Images-partitie geplaatst (`sources.json` wordt door RSS-Deploy gelezen vóór de wipe);
- de Validate-fase en daarna `Validate-RSSMedia.ps1` (read-only, 30+ controles) moeten groen zijn vóór enige fysieke test.

Kort procedureoverzicht (volledige tekst: `docs/generated/RSS_Technische_bouw_en_beheerhandleiding.*` en `tools/Update-RSSMedia.ps1`):

```powershell
# 1. vereisten aanwezig? (ADK, wimlib, manifest actueel)
.\tools\Update-RSSMedia.ps1 -Phase Drivers -WorkingDir D:\RSS-Build
# 2..6 overige fases, daarna:
.\tools\Update-RSSMedia.ps1 -Phase Media -UsbDiskNumber <n> -SourceInstallWim D:\RSS-Build\install-serviced.wim
.\tools\Validate-RSSMedia.ps1
```

Klonen/dupliceren: blokniveau-kloon blijft de aanbevolen route; geef de kloon een unieke MBR-disksignatuur en verifieer labels, partitiegroottes en SHA-256's van images/archieven. Ga niet verder als bron en doel niet ondubbelzinnig te onderscheiden zijn.

# 15. Validatie

**`tools/Validate-RSSMedia.ps1` (read-only)** controleert o.a.: USB-identiteit, partities en filesystemstatus, vereiste bestanden, manifest-identiteit (sources.json op stick == repo), boot.wim-hash, Secure Boot-binaries en BCD-vlaggen, image-identiteit en DISM-metadata (editie/build/taal/KB's), driverarchief-hashes + integriteit + exacte INF-aantallen, load-orders en INF-inhoud, AST-syntax van deploymentlogica en veiligheidsbibliotheek, guardrail-aanwezigheid (manifest, hashcontrole, diskselectie), afwezigheid van interactie- en MDM/OOBE-risicopatronen en manifestconsistentie van RSS-INFO.txt. Resultaat per regel PASS/WARN/FAIL met eindrapport; FAIL = exitcode 1.

**`tests/RSS-Safety.Tests.ps1` (Pester, gemockt)** dekt de gevaarmatrix: ondersteund model + geldige media (doorgaat), onbekend model, lege/onbekende/weiger-SKU, SF7 5G, SF8 Snapdragon, ARM-naam, CPU-mismatch, geen/meerdere NVMe, NVMe niet op Disk 0, USB op Disk 0, USB = doelschijf, nul/meerdere datapartities, ontbrekende archieven, hash-mismatch en incompleet manifest — alles STOP. De tests raken nooit een echte disk en draaien in CI.

**`tools/Test-ManifestConsistency.ps1`** controleert manifeststructuur, hash-formaat, URL-hosts, load-orders, bestandsaanwezigheid, gegenereerde outputs en checksumlijst (CI en lokaal).

# 16. Physical testing

Automatische tests vervangen fysieke Surface-tests nooit. Per model geldt de quicklist `docs/PHYSICAL-TEST-QUICKLIST.md` en de matrix `docs/TESTMATRIX.md` (boot, detectie, routing/veiligheid, deployment, eerste boot, OOBE, invoer, Wi-Fi, USB, Apparaatbeheer, Autopilot/Intune, reboot/shutdown). Negatieve fysieke tests: onondersteund model toont rood zonder Disk 0 aan te raken; ARM/Snapdragon wordt geweigerd; missend archief stopt veilig; geen enkele stap vraagt invoer.

Huidige fysieke status: uitsluitend **SF6 is fysiek gevalideerd**; SF4, SF5, SF7 en SF8 zijn **NOT PHYSICALLY VALIDATED** (appendix B). Een model mag pas in productie worden gedeployed na een geslaagde fysieke test van dat model op die mediaronde.

# 17. Productievrijgave

Een release mag alleen als álle gates groen zijn (procedure: `docs/generated/RSS_Test_en_releaseprocedure.*`):

1. CI groen (syntax, PSScriptAnalyzer, Pester, manifestconsistentie, links, secretscan, geen binaries);
2. media validated: `Validate-RSSMedia.ps1` 0 FAIL op de kandidaatstick;
3. fysieke test per beoogd model uitgevoerd en gedocumenteerd;
4. known limitations gedocumenteerd (CHANGELOG + manifest);
5. tag (semver `vX.Y.Z`), checksums herbouwd (`Build-Checksums.ps1`), manifest-releasevelden bijgewerkt.

Onderscheid is verplicht: *code validated* ≠ *media validated* ≠ *physically validated* ≠ *production approved*.

# 18. Troubleshooting (evidence-based)

Werkwijze: symptoom → waarschijnlijke oorzaak → diagnose → veilige oplossing. Bewaar bewijs (foto van rood scherm + `RSS-ADK-Deploy.log` of OOBE-diagnosemap) vóór elke actie; herstel nooit ad hoc door losse bestanden terug te kopiëren of een productiestick ter plekke te "repareren".

| Symptoom | Waarschijnlijke oorzaak | Diagnose | Veilige oplossing |
|---|---|---|---|
| Rood scherm vóór aftelling | preflight-stop (model/SKU/CPU/media/disks/manifest) | lees de foutmelding; begin van `RSS-ADK-Deploy.log`; Disk 0 is onaangeraakt | oorzaak verhelpen (bijv. manifest bijwerken na SKU-verificatie), opnieuw |
| "SystemSKU is onbekend" | nieuwe regionale SKU-variant | SKU uit het rode scherm/log vergelijken met Microsoft SystemSKU-referentie | verificatie, manifest-update, hervalidatie, nieuwe stick |
| Rood scherm bij hashcontrole | corrupte of verouderde image/archief op de stick | hash lokaal nalopen tegen manifest | stick herbouwen; nooit hash-aanpassing om de fout weg te nemen |
| Driverarchiefcontrole faalt (DISM) | beschadigd/verkeerd archief | hash + `dism /Get-WimInfo` + proefuitpakken | herbouw Archives-fase |
| INF-telling wijkt af | onvolledig of nieuw Microsoft-pakket | telling vergelijken met de MSI-extractie | pakket verificeren, manifest-update, opnieuw — nooit doordrukken |
| Apply-Image faalt | corrupte image of USB-I/O | hash; andere USB-poort/stick testen | media herbouwen; stick vervangen bij herhaling |
| BCDBoot faalt | EFI-partitie of toegepaste map onjuist | `Windows\System32\config\SYSTEM` aanwezig? partitielayout nalopen | herbouw; log meesturen |
| Geen toetsenbord/touch in WinPE | zeldzaam; boot.wim niet de ADK-build of startnet faalt | `Build-WinPE.status` + log controleren | herbouw BootWim-fase; externe USB-keyboard alleen voor diagnose |
| "Findstr is not recognized" | legacy/minimale WinPE-constructie | niet de actieve productieroute | stick herbouwen vanaf ADK-bron |
| Rood scherm: geen interne NVMe | doelapparaat geen ondersteunde Surface, of opslagcontroller in verkeerde modus | apparaatmodel verifiëren; UEFI-storage-instelling | alleen ondersteunde modellen deployen |
| Rood scherm: meerdere NVMe-schijven | niet-standaard hardware | configuratie nalopen | apparaat valt buiten design; niet dwingen |
| OOBE hangt bij netwerkcontrole | NCSI-probe geblokkeerd / Autopilot niet geregistreerd / endpoint-filter | hoofdstuk 13.2; `Collect-RSSOOBEDiag.ps1` | netwerk/tenantzijde verhelpen; nooit OOBE-bypass |
| OOBE terug naar Wi-Fi | NCSI slaagt niet binnen time-out | NCSI-eventlog, probe handmatig | netwerkteam inschakelen; Captive Portal uitsluiten |
| Autopilot "Something went wrong" | endpoints geblokkeerd of registratie/onferentie | Autopilot-eventlog 807/815/100; registratie in Intune nalopen | hash uploaden/profiel toewijzen; reboot OOBE (Shift+F10, `shutdown /r /t 0`) |
| Korte reboot-loop bij eerste boot | eerste-boot PnP-verwerking (bekend fenomeen, zelfherstellend) | ≥ 10 minuten wachten | pas daarna Panther-log onderzoeken |
| Stick vol bij kopiëren | bestandskopie i.p.v. blokniveau-kloon | partitiegrootte/logische inhoud vergelijken | opnieuw blokniveau klonen |
| Deployment start opnieuw vanzelf na geslaagde install | USB vóór interne SSD in UEFI-bootvolgorde | bootvolgorde nalopen | USB verwijderen bij groen scherm; bootvolgorde corrigeren |

# 19. Recovery

- **Preflight-stop:** Disk 0 is onaangeraakt; apparaat uitschakelen, oorzaak verhelpen, opnieuw. Geen herstel nodig.
- **Onderbreking ná wipe, vóór geslaagde apply:** het apparaat heeft geen werkend besturingssysteem; herstart de procedure met dezelfde stick (de preflight draait opnieuw en de wipe begint opnieuw — het apparaat is al leeg).
- **Corrupte stick:** herbouw via `Update-RSSMedia.ps1`; herstel nooit door losse bestanden te vervangen. Bewaar vóór herstel de logs en noteer model, SKU, foutstap, tijdstip en gebruikte stick.
- **Herstel van gebruiksdata:** buiten scope — RSS is een wis-en-installeerproces; zorg vóóraf voor back-up op organisatieniveau.

# 20. Logging

Primair log: `<Images>:\RSS-ADK-Deploy.log`, bij elke run vernieuwd. Inhoud: tijdstempel, manifest-versie, model/SystemSKU/CPU, media- en doelschijf (bus, grootte), image- en archiefpaden, verwacht INF-aantal, hashcontroles, alle DISM/wimlib/BCDBoot-uitvoer, DriverStore-aantallen en als slot `RESULT=SUCCESS` of `RESULT=FAILED-SAFE MESSAGE=…`. Het log bevat geen gebruikersgegevens en blijft op de stick; kopieer het bij incidenten vóór herbouw.

# 21. Checksums en integriteit

- `checksums/SHA256SUMS.txt` dekt alle Git-beheerde bestanden (exclusief de lijst zelf en `docs/generated`); herbouw na elke wijziging: `tools\Build-Checksums.ps1`.
- Image-, archief- en boot.wim-hashes staan in `config/sources.json` en worden op drie momenten gecontroleerd: bij de download (onderhoudsscript), bij de stickvalidatie en vóór de wipe (RSS-Deploy).
- Ontvangers van een stick verifiëren minimaal: boot.wim-hash, vijf install.esd-hashes, vijf archief-hashes en `sources.json`-identiteit.

# 22. Releasebeheer

Zie hoofdstuk 17 en de losse procedure (`RSS_Test_en_releaseprocedure`). Versienummering: semver op repositoryniveau (`vX.Y.Z`); media-identiteit = Windows-build + driverdatum + boot.wim-hash (in het manifest en RSS-INFO.txt). Elke vrijgegeven stick-versie krijgt een Git-tag en een checksumlijst die bij die tag hoort.

# 23. Security en privacy

- Geen secrets, wachtwoorden, tokens, productsleutels, hardware-hashes of serienummers in Git of logs; CI draait gitleaks en een binary-scanner.
- RSS gebruikt uitsluitend officiële Microsoft-bronnen met hash- en handtekeningscontrole; geen Internet tijdens deployment.
- Stickdocumentatie bevat geen organisatie- of klantgegevens; repository blijft intern/proprietary zonder opensourcelicentie.
- Deploymentlogs blijven op de stick en worden niet centraal verzameld; bij incidenten alleen bewust en minimaal delen.
- Secure Boot blijft aan; de bootomgeving bevat uitsluitend Microsoft-ondertekende binaries en de BCD zonder testvlaggen (gevalideerd).

# 24. Known limitations

- Uitsluitend de vijf genoemde profielen; alle andere hardware (o.a. ARM/Snapdragon en de 5G-variant) valt bewust buiten scope.
- SF4 omvat alleen de AMD-variant; SF8 alleen de Intel Business-editie.
- Fysieke validatie ontbreekt voor SF4, SF5, SF7 en SF8 op de huidige mediaronde.
- De SafeOS DU {{windows.winreUpdate.kb}} in de productiemedia is opgevolgd door {{windows.winreUpdate.supersededBy.kb}}; overnemen bij de eerstvolgende herbouw.
- Windows 26H2 is beschikbaar maar is een aparte image-track (niet stilzwijgend overnemen).
- Surface Laptop 4 driver/firmware-servicing eindigt {{surfaceDriverPacks.0.lifecycle.driverFirmwareEol}}.
- De OOBE is netwerkafhankelijk (by design); een omgeving die NCSI/Autopilot-endpoints blokkeert laat OOBE niet voltooien — dat is een netwerk/tenantvoorwaarde, geen imagefout.

# Appendix A — Versies en bronnen

| Onderdeel | Waarde | Bron |
|---|---|---|
| Windows | 11 {{windows.displayVersion}} build {{windows.build}} ({{windows.edition}}, {{windows.languageDisplay}}) | UUP-set + manifest |
| LCU | {{windows.cumulativeUpdate.kb}} ({{windows.cumulativeUpdate.released}}) | Microsoft Update Catalog |
| SSU | {{windows.cumulativeUpdate.kb}} gebundeld (KB5124007) | idem |
| .NET CU | {{windows.netFrameworkUpdate.kb}} | idem |
| SafeOS DU | {{windows.winreUpdate.kb}} (media) / {{windows.winreUpdate.supersededBy.kb}} (volgende herbouw) | idem |
| ADK + WinPE add-on | {{adk.version}} | learn.microsoft.com (adk-install) |
| wimlib | {{wimlib.version}} | wimlib.net |
| Driverpakketten | zie hoofdstuk 6 | Microsoft Download Center |

# Appendix B — Modelmatrix met valideringsstatus

| Profiel | Model | SystemSKU's (supported) | INF | Fysieke status |
|---|---|---|---|---|
{{TABLE:MODELSKU}}

*N.B.: "supported" betekent softwarematig ontworpen en gevalideerd; alleen de status "PHYSICALLY VALIDATED" bewijst een geslaagde fysieke deployment op dat model.*
