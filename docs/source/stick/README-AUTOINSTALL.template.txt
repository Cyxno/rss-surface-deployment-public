RSS - AUTOMATED ADK WINPE SURFACE INSTALLATION

1. Insert the stick into a powered-off, supported Surface Laptop (4 AMD, 5 Intel, 6 Intel, 7 Intel x64 or 8 Intel x64).
2. Boot from USB (Secure Boot and TPM stay on).
3. Model, SystemSKU, CPU, USB disk, NVMe target disk, image and driver hashes are checked automatically against the included manifest.
4. After a 15-second countdown, NVMe Disk 0 is wiped completely.
5. Windows, the full official Microsoft driver package and the UEFI boot files are installed automatically; after that the normal Windows OOBE starts (Autopilot/Intune-ready).

No keyboard, mouse, menu or Windows Setup interface is required.
ARM/Snapdragon models, the 5G variant and all unsupported devices are safely refused with a red screen - without writing anything to the disk.

The boot environment is built with Microsoft ADK WinPE ({{adk.version}}) and contains PowerShell, WMI, StorageWMI and DISM cmdlets.
INF counts per model (from sources.json): {{TABLE:INFSLINE}}.
During deployment, RSS shows colored steps and countdowns; after a successful installation the entire screen turns green.
On any preflight, hash, image, driver or boot error the process stops and the error remains visible.

Full log: <Images>:\RSS-ADK-Deploy.log
Operations manual: <Images>:\README-AUTOINSTALL.txt and the RSS_Operations_Manual (docs/generated in the repository).
