# RSS-testmatrix — refresh 2026-10 (SF4 t/m SF8)

Per apparaat volledig doorlopen vóór productievrijgave van een nieuwe stick.
Eén kandidaat-stick per bouwronde; minimaal één volledige deployment per model.

Modellen: Surface Laptop 4 AMD · Surface Laptop 5 Intel · Surface Laptop 6
for Business Intel · Surface Laptop for Business 7th Edition Intel ·
Surface Laptop for Business 8th Edition Intel

> **Statusregistratie:** de fysieke validatiestatus per model staat in
> `config/sources.json` (`physicalValidation`) en wordt zichtbaar in README en
> handleiding. Modellen zonder fysieke test blijven expliciet
> **NOT PHYSICALLY VALIDATED**, ook als ze softwarematig "supported" zijn.

## Boot en detectie

| Controle | SF4 | SF5 | SF6 | SF7 | SF8 |
|---|---|---|---|---|---|
| Secure Boot AAN | ☐ | ☐ | ☐ | ☐ | ☐ |
| TPM AAN | ☐ | ☐ | ☐ | ☐ | ☐ |
| USB UEFI boot | ☐ | ☐ | ☐ | ☐ | ☐ |
| WinPE start automatisch | ☐ | ☐ | ☐ | ☐ | ☐ |
| Correct model gedetecteerd | ☐ | ☐ | ☐ | ☐ | ☐ |
| Correcte SystemSKU getoond | ☐ | ☐ | ☐ | ☐ | ☐ |
| Juiste CPU gedetecteerd (AMD/Intel) | ☐ | ☐ | ☐ | ☐ | ☐ |
| Juiste USB-disk gedetecteerd | ☐ | ☐ | ☐ | ☐ | ☐ |
| Juiste NVMe Disk 0 gedetecteerd | ☐ | ☐ | ☐ | ☐ | ☐ |
| Manifest geladen (hashcontrole actief) | ☐ | ☐ | ☐ | ☐ | ☐ |

## Routing en veiligheid

| Controle | SF4 | SF5 | SF6 | SF7 | SF8 |
|---|---|---|---|---|---|
| Juiste image geselecteerd (SFx) | ☐ | ☐ | ☐ | ☐ | ☐ |
| Juiste driverarchive geselecteerd | ☐ | ☐ | ☐ | ☐ | ☐ |
| Image- en archief-hash geverifieerd vóór aftelling | ☐ | ☐ | ☐ | ☐ | ☐ |
| Preflight stopt veilig bij fouten | ☐ | ☐ | ☐ | ☐ | ☐ |
| ARM/Snapdragon geweigerd (negatieve test) | n.v.t. | n.v.t. | n.v.t. | ☐ | ☐ |

## Deployment

| Controle | SF4 | SF5 | SF6 | SF7 | SF8 |
|---|---|---|---|---|---|
| Disk wipe na 15 s aftelling | ☐ | ☐ | ☐ | ☐ | ☐ |
| GPT-indeling (EFI 260 MB + MSR 16 MB + Windows) | ☐ | ☐ | ☐ | ☐ | ☐ |
| Windows-image apply geslaagd | ☐ | ☐ | ☐ | ☐ | ☐ |
| Volledige driverinjectie | ☐ | ☐ | ☐ | ☐ | ☐ |
| INF-count klopt exact (78/112/116/119/120) | ☐ | ☐ | ☐ | ☐ | ☐ |
| BCDBoot succesvol | ☐ | ☐ | ☐ | ☐ | ☐ |
| Microsoft bootmgfw.efi aanwezig | ☐ | ☐ | ☐ | ☐ | ☐ |
| Groen successcherm + automatische reboot | ☐ | ☐ | ☐ | ☐ | ☐ |

## Eerste boot en overdracht

| Controle | SF4 | SF5 | SF6 | SF7 | SF8 |
|---|---|---|---|---|---|
| USB verwijderd, Windows boot met Secure Boot | ☐ | ☐ | ☐ | ☐ | ☐ |
| OOBE verschijnt (normale Microsoft-flow) | ☐ | ☐ | ☐ | ☐ | ☐ |
| Toetsenbord/trackpad werken | ☐ | ☐ | ☐ | ☐ | ☐ |
| Touchscreen werkt | ☐ | ☐ | ☐ | ☐ | ☐ |
| Wi-Fi werkt | ☐ | ☐ | ☐ | ☐ | ☐ |
| Ethernet/USB-C indien relevant | ☐ | ☐ | ☐ | ☐ | ☐ |
| Bluetooth werkt | ☐ | ☐ | ☐ | ☐ | ☐ |
| Camera werkt | ☐ | ☐ | ☐ | ☐ | ☐ |
| Audio werkt | ☐ | ☐ | ☐ | ☐ | ☐ |
| Apparaatbeheer zonder onbekende essentiële apparaten | ☐ | ☐ | ☐ | ☐ | ☐ |
| MDM/Autopilot-inschrijving gestart / mogelijk | ☐ | ☐ | ☐ | ☐ | ☐ |
| Windows Update vindt hooguit updates ná het bouwmoment | ☐ | ☐ | ☐ | ☐ | ☐ |
| Herstart + afsluiten netjes | ☐ | ☐ | ☐ | ☐ | ☐ |

## Negatieve tests (stick-niveau, één keer per release)

- [ ] Niet-ondersteund model toont rood scherm zonder Disk 0 aan te passen.
- [ ] Surface Laptop 7/8 ARM/Snapdragon wordt geweigerd (modelnaam óf CPU-vendor óf SKU).
- [ ] Surface Laptop 5G for Business 7th Edition (SKU `_2119`) wordt geweigerd.
- [ ] Onbekende SystemSKU (bijv. geblokkeerde/vervallen variant) stopt veilig.
- [ ] Missende driverarchive stopt de preflight veilig.
- [ ] Gewijzigd bestand op de stick (hash-mismatch) stopt vóór de aftelling.
- [ ] Geen enkele stap vraagt om toetsenbord-, muis- of scherminvoer.
- [ ] RSS-ADK-Deploy.log eindigt op RESULT=SUCCESS bij geslaagde runs.

## OOBE/Autopilot (per release, minimaal één apparaat)

- [ ] OOBE voltooit op een netwerk dat NCSI toestaat (msftconnecttest.com bereikbaar).
- [ ] Autopilot-profiel wordt opgehaald (event 161 in ModernDeployment-Diagnostics-Provider/Autopilot) óf de oorzaak van uitblijven is gedocumenteerd.
- [ ] Bij hang op "De verbinding met Microsoft wordt gecontroleerd": diagnose met `tools/Collect-RSSOOBEDiag.ps1` en classificatie volgens hoofdstuk 13.2 van de handleiding (image/netwerk/service/Autopilot/regressie).
