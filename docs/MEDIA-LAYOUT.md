# Production medium

The RSS stick consists of two partitions (MBR partition scheme):

| Label | File system | Size | Purpose |
|---|---|---|---|
| `WINPE` | FAT32 | 2 GiB | UEFI boot files and the customized WinPE `boot.wim` |
| `Images` | NTFS | rest of the medium | Model installations, official driver archives, WinPE driver selection, manifest and documentation |

The 64 GB medium is partitioned completely; hard links are not needed: each model contains its own complete `install.esd`.

Main paths on the `Images` partition:

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
├── sources.json          ← canonical manifest (read before the wipe)
├── RSS-INFO.txt          ← generated from the manifest
├── README-AUTOINSTALL.txt
└── RSS-ADK-Deploy.log    (refreshed on every run)
```

## Roles

- **`RSSSetup\SFx\sources\install.esd`** — per profile, index 1 of the serviced Windows image (byte-identical per model; hash in the manifest).
- **`RSSDriverArchives\SFx.esd`** — the full official Surface driver package in wimlib archive form; during deployment it is extracted to the target disk and injected offline (exact INF count checked against the manifest).
- **`RSSWinPEDrivers\SFx` + `load-order.txt`** — build/recovery material: the minimal WinPE driver set with the proven load order. The active boot.wim deliberately starts without model-specific drivers (the Microsoft inbox drivers from the ADK source initialize NVMe/USB reliably); this folder is therefore not part of the active deployment, but it is still checked for consistency by the validation.
- **`sources.json`** — the canonical manifest: before anything is written to the disk, RSS-Deploy reads the expected hashes, INF counts and SKU allowlists from it. If it is missing or deviates from the repo version, the deployment stops (and the stick validation flags it).

The concrete build, recovery and validation steps are in the technical manual (`docs/generated/RSS_Technical_Build_and_Management_Manual.pdf`) and in `tools/Update-RSSMedia.ps1`.
