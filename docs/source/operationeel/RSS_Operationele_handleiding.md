---
title: "RSS — Operationele handleiding"
subtitle: "De stick gebruiken op een Surface Laptop"
version: "2.0"
classification: "Source-available"
audience: "Medewerkers die de stick daadwerkelijk inzetten"
---

# 1. Wanneer mag de stick worden gebruikt?

- Alleen op een apparaat uit de ondersteunde lijst hieronder, alleen door iemand die bevoegd is tot het wissen ervan, en alleen als de gegevens op de interne schijf bewust mogen verwijderen.
- **Ondersteund:** Surface Laptop 4 (AMD), Surface Laptop 5 (Intel), Surface Laptop 6 for Business (Intel), Surface Laptop for Business 7th Edition with Intel, Surface Laptop for Business 8th Edition with Intel (13,8"/15").
- **Niet ondersteund (veilige stop, er gebeurt niets):** alle overige modellen, ARM/Snapdragon-varianten, de Surface Laptop 5G for Business 7th Edition en de Intel-variant van de Surface Laptop 4.

> **WAARSCHUWING:** na de controles volgt een aftelling van 15 seconden; daarna wordt de interne schijf gewist zonder verdere vraag. Apparaat uitschakelen tijdens de aftelling = annuleren.

# 2. Voorbereiding

1. Controleer het apparaatmodel (staat op het scherm bij de detectie).
2. Sluit netvoeding aan.
3. Zorg dat het apparaat volledig is uitgeschakeld en plaats de stick.
4. Start op vanaf USB (UEFI). Secure Boot en TPM blijven aan.

# 3. Wat je ziet (normale fasen)

| Fase | Scherm | Duur (indicatief) |
|---|---|---|
| Boot | zwart, kort WinPE-start | ± 1 min |
| Groene animatie + stappen | model-, SKU-, CPU-, disk- en driverinformatie | ± 2 min (incl. hashcontrole van image en drivers) |
| Gele aftelling | "Installatie start over" — 15 s | laatste kans om te annuleren (uitschakelen) |
| Stappen 1–5 | schijfindeling, image, drivers, bootbestanden | ± 10–20 min (kan lang weinig zichtbare voortgang tonen — normaal) |
| Volledig groen | "INSTALLATIE GESLAAGD" + aftelling | **nu de USB-stick verwijderen** |
| Automatische reboot | eerste Windows-boot en OOBE | ± 5–10 min (meerdere herstarts zijn normaal) |

De stick vereist geen toetsenbord, muis of touch: de hele flow loopt automatisch.

# 4. Eerste boot en OOBE

- Het apparaat eindigt in een volledig normale Windows-OOBE (Nederlands). Er wordt geen lokale account aangemaakt en er is geen bypass actief — juist zo kan Autopilot/Intune-inschrijving volgen.
- Controleer in de OOBE: touchscreen, toetsenbord/trackpad, Wi-Fi-netwerken zichtbaar, USB werkt.
- Na invoer van organisatiereferenties start de reguliere Autopilot/Intune-inschrijving.
- De apparatuur is vóór de eerste boot al volledig van officiële Surface-drivers voorzien (offline DriverStore).

**OOBE hangt op "De verbinding met Microsoft wordt gecontroleerd"?** Dit is vrijwel altijd een netwerk- of registratiekwestie, geen imagefout: controleer of het netwerk de Microsoft-connectiviteitstest toestaat en of het apparaat in Autopilot geregistreerd is. Diagnose: Shift+F10 en `tools\Collect-RSSOOBEDiag.ps1` vanaf de stick (verzamelt alles automatisch, read-only). Ga nooit een OOBE-bypass gebruiken.

# 5. Rood scherm (veilige stop)

Een volledig rood scherm betekent: **gestopt vóór de schrijfactie of met een duidelijke foutmelding.**

1. Maak een foto van de foutmelding.
2. Kopieer `F:\RSS-ADK-Deploy.log` (Images-partitie) als de fout ná de mediaherkenning optrad.
3. Schakel uit met de aan/uitknop; het scherm blijft bewust staan.
4. Neem contact op met ICT-beheer met foto + log + apparaatmodel.

Bij een stop vóór de aftelling is de schijf **onaangeraakt**.

# 6. Wanneer onmiddellijk stoppen

- Het scherm toont een ander model dan het apparaat waarop je werkt → uitschakelen, stick melden.
- De aftelling begint terwijl je niet bevoegd bent of twijfelt → uitschakelen tijdens de aftelling.
- Rook, geur, Extreme hitte of herhaalde identieke fouten → stopt, apparaat laten staan en melden.

# 7. Controle na de deployment

- [ ] Groen scherm verschenen; USB verwijderd bij het groene scherm.
- [ ] Windows start met Secure Boot aan (geen USB nodig).
- [ ] OOBE verschijnt normaal; invoer, touch en Wi-Fi werken.
- [ ] Autopilot/Intune-inschrijving gestart of mogelijk.
- [ ] Apparaatbeheer: geen onbekende essentiële apparaten.
- [ ] Windows Update toont hoogstens updates ná het bouwmoment van de stick.

# 8. Korte troubleshooting

| Symptoom | Betekenis | Actie |
|---|---|---|
| Rood vóór aftelling | preflight-stop; schijf onaangeraakt | foto + log, melden |
| Rood bij "hash"/"integriteit" | stick inhoudelijk corrupt | stick niet hergebruiken; melden en herbouwen |
| Rood "niet-ondersteund model" | apparaat buiten scope | andere inzetweg kiezen |
| Aftelling terwijl annuleren gewenst is | laatste kans | apparaat uitschakelen tijdens aftelling |
| Lang "weinig zichtbare voortgang" | normaal bij image/drivers | wachten; niet uitschakelen na de aftelling |
| OOBE hangt op netwerkcontrole | netwerk/Autopilot-registratie | diagnose per hoofdstuk 4; ICT melden |
| Korte reboots bij eerste boot | normaal eerste-bootproces | minimaal 10 minuten wachten |

Volledige technische troubleshooting: `RSS_Technische_bouw_en_beheerhandleiding`, hoofdstuk 18.
