# RSS FYSIEKE TEST — SNELLE CHECKLIST

> ## 🔴 BIJ ROOD SCHERM
> **Maak een foto van de foutmelding en kopieer `F:\RSS-ADK-Deploy.log`**
> (van de Images-partitie) **voordat je opnieuw probeert.**
> Schakel uit met de aan/uitknop; het scherm blijft bewust rood staan.

Apparaat: ______________  Datum: ____-__-__  Tester: __________

## Vooraf

- [ ] USB-stick geplaatst (apparaat UIT)
- [ ] Secure Boot **AAN** in Surface UEFI
- [ ] TPM **AAN**
- [ ] Netvoeding aangesloten

## Deployment (niets aanraken na stap 3!)

- [ ] Boot vanaf USB (UEFI)
- [ ] WinPE start automatisch (zwart/groen scherm)
- [ ] Correct model gedetecteerd (staat op het scherm)
- [ ] Juist SF-profiel (SF4/SF5/SF6/SF7/SF8)
- [ ] Doelschijf = interne NVMe (staat op het scherm)
- [ ] Na 15 s aftelling start het wissen automatisch

## Installatie

- [ ] Windows-image toegepast
- [ ] Drivers geïnjecteerd
- [ ] **GROEN scherm** ("INSTALLATIE GESLAAGD")
- [ ] Automatische reboot → **USB verwijderd tijdens groen scherm**

## Eerste Windows-boot

- [ ] Windows start met Secure Boot aan
- [ ] Toetsenbord werkt
- [ ] Trackpad/touch werkt
- [ ] Wi-Fi netwerken zichtbaar
- [ ] **Normale OOBE** verschijnt (geen auto-aangemelde gebruiker)
- [ ] MDM/Autopilot-inschrijving gestart / mogelijk
- [ ] Apparaatbeheer: geen onbekende essentiële apparaten

## Notities

.................................................................

.................................................................
