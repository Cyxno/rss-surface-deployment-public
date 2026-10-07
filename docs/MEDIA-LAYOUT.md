# Productiemedium

De RSS-stick bestaat uit twee partities (MBR-partitieschema):

| Label | Bestandssysteem | Grootte | Functie |
|---|---|---|---|
| `WINPE` | FAT32 | 2 GiB | UEFI-bootbestanden en de aangepaste WinPE `boot.wim` |
| `Images` | NTFS | rest van het medium | Modelinstallaties, officiële driverarchieven, WinPE-driverselectie, manifest en documentatie |

Het 64-GB-medium wordt volledig gepartitioneerd; hardlinks zijn niet nodig: elk model bevat zijn eigen volledige `install.esd`.

Belangrijkste paden op de partitie `Images`:

```text
Images:\
├── RSSSetup\
│   ├── SF4\sources\install.esd
│   ├── SF5\sources\install.esd
│   ├── SF6\sources\install.esd
│   ├── SF7\sources\install.esd
│   └── SF8\sources\install.esd
├── RSSDriverArchives\
│   ├── SF4.esd
│   ├── SF5.esd
│   ├── SF6.esd
│   ├── SF7.esd
│   └── SF8.esd
├── RSSWinPEDrivers\
│   ├── SF4\
│   ├── SF5\
│   ├── SF6\
│   ├── SF7\
│   └── SF8\
├── sources.json          ← canonical manifest (gelezen vóór de wipe)
├── RSS-INFO.txt          ← gegenereerd uit het manifest
├── LEESMIJ-AUTOINSTALL.txt
└── RSS-ADK-Deploy.log    (bij iedere uitvoering vernieuwd)
```

## Rollen

- **`RSSSetup\SFx\sources\install.esd`** — per profiel index 1 van het geservicede Windows-image (byte-identiek per model; hash in het manifest).
- **`RSSDriverArchives\SFx.esd`** — het volledige officiële Surface-driverpakket in wimlib-archiefvorm; wordt tijdens deployment op de doelschijf uitgepakt en offline geïnjecteerd (exacte INF-telling tegen het manifest).
- **`RSSWinPEDrivers\SFx` + `load-order.txt`** — bouw-/herstelmateriaal: de minimale WinPE-driverreeks met de bewezen laadvolgorde. De actieve boot.wim start bewust zónder modelgebonden drivers (de Microsoft-inboxdrivers van de ADK-bron initialiseren NVMe/USB betrouwbaar); deze map is dus geen onderdeel van de actieve deployment maar wordt wél door de validatie op consistentie gecontroleerd.
- **`sources.json`** — het canonical manifest: RSS-Deploy leest hieruit de verwachte hashes, INF-aantallen en SKU-allowlists vóórdat er iets op de schijf wordt geschreven. Ontbreekt het of wijkt het af van de repo-versie, dan stopt de deployment (en de stickvalidatie markeert het).

De concrete bouw-, herstel- en validatiestappen staan in de technische handleiding (`docs/generated/RSS_Technische_bouw_en_beheerhandleiding.pdf`) en in `tools/Update-RSSMedia.ps1`.
