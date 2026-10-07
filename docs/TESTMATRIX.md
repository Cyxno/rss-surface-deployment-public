# RSS test matrix — refresh 2026-10 (SF4 through SF8)

Run completely for each device before the production release of a new stick.
One candidate stick per build round; at least one full deployment per model.

Models: Surface Laptop 4 AMD · Surface Laptop 5 Intel · Surface Laptop 6
for Business Intel · Surface Laptop for Business 7th Edition Intel ·
Surface Laptop for Business 8th Edition Intel

> **Status tracking:** the physical validation status per model is in
> `config/sources.json` (`physicalValidation`) and is shown in the README and
> the manual. Models without a physical test remain explicitly
> **NOT PHYSICALLY VALIDATED**, even if they are "supported" at the software level.

## Boot and detection

| Check | SF4 | SF5 | SF6 | SF7 | SF8 |
|---|---|---|---|---|---|
| Secure Boot ON | ☐ | ☐ | ☐ | ☐ | ☐ |
| TPM ON | ☐ | ☐ | ☐ | ☐ | ☐ |
| USB UEFI boot | ☐ | ☐ | ☐ | ☐ | ☐ |
| WinPE starts automatically | ☐ | ☐ | ☐ | ☐ | ☐ |
| Correct model detected | ☐ | ☐ | ☐ | ☐ | ☐ |
| Correct SystemSKU shown | ☐ | ☐ | ☐ | ☐ | ☐ |
| Correct CPU detected (AMD/Intel) | ☐ | ☐ | ☐ | ☐ | ☐ |
| Correct USB disk detected | ☐ | ☐ | ☐ | ☐ | ☐ |
| Correct NVMe Disk 0 detected | ☐ | ☐ | ☐ | ☐ | ☐ |
| Manifest loaded (hash check active) | ☐ | ☐ | ☐ | ☐ | ☐ |

## Routing and safety

| Check | SF4 | SF5 | SF6 | SF7 | SF8 |
|---|---|---|---|---|---|
| Correct image selected (SFx) | ☐ | ☐ | ☐ | ☐ | ☐ |
| Correct driver archive selected | ☐ | ☐ | ☐ | ☐ | ☐ |
| Image and archive hashes verified before countdown | ☐ | ☐ | ☐ | ☐ | ☐ |
| Preflight stops safely on errors | ☐ | ☐ | ☐ | ☐ | ☐ |
| ARM/Snapdragon refused (negative test) | n/a | n/a | n/a | ☐ | ☐ |

## Deployment

| Check | SF4 | SF5 | SF6 | SF7 | SF8 |
|---|---|---|---|---|---|
| Disk wipe after 15 s countdown | ☐ | ☐ | ☐ | ☐ | ☐ |
| GPT layout (EFI 260 MB + MSR 16 MB + Windows) | ☐ | ☐ | ☐ | ☐ | ☐ |
| Windows image apply succeeded | ☐ | ☐ | ☐ | ☐ | ☐ |
| Full driver injection | ☐ | ☐ | ☐ | ☐ | ☐ |
| INF count exact (78/112/116/119/120) | ☐ | ☐ | ☐ | ☐ | ☐ |
| BCDBoot successful | ☐ | ☐ | ☐ | ☐ | ☐ |
| Microsoft bootmgfw.efi present | ☐ | ☐ | ☐ | ☐ | ☐ |
| Green success screen + automatic reboot | ☐ | ☐ | ☐ | ☐ | ☐ |

## First boot and handover

| Check | SF4 | SF5 | SF6 | SF7 | SF8 |
|---|---|---|---|---|---|
| USB removed, Windows boots with Secure Boot | ☐ | ☐ | ☐ | ☐ | ☐ |
| OOBE appears (normal Microsoft flow) | ☐ | ☐ | ☐ | ☐ | ☐ |
| Keyboard/trackpad work | ☐ | ☐ | ☐ | ☐ | ☐ |
| Touchscreen works | ☐ | ☐ | ☐ | ☐ | ☐ |
| Wi-Fi works | ☐ | ☐ | ☐ | ☐ | ☐ |
| Ethernet/USB-C if relevant | ☐ | ☐ | ☐ | ☐ | ☐ |
| Bluetooth works | ☐ | ☐ | ☐ | ☐ | ☐ |
| Camera works | ☐ | ☐ | ☐ | ☐ | ☐ |
| Audio works | ☐ | ☐ | ☐ | ☐ | ☐ |
| Device Manager without unknown essential devices | ☐ | ☐ | ☐ | ☐ | ☐ |
| MDM/Autopilot enrollment started / possible | ☐ | ☐ | ☐ | ☐ | ☐ |
| Windows Update finds at most updates newer than the build time | ☐ | ☐ | ☐ | ☐ | ☐ |
| Restart + clean shutdown | ☐ | ☐ | ☐ | ☐ | ☐ |

## Negative tests (stick level, once per release)

- [ ] Unsupported model shows a red screen without modifying Disk 0.
- [ ] Surface Laptop 7/8 ARM/Snapdragon is refused (model name or CPU vendor or SKU).
- [ ] Surface Laptop 5G for Business 7th Edition (SKU `_2119`) is refused.
- [ ] Unknown SystemSKU (e.g. a blocked/withdrawn variant) stops safely.
- [ ] Missing driver archive stops the preflight safely.
- [ ] Modified file on the stick (hash mismatch) stops before the countdown.
- [ ] No step asks for keyboard, mouse or on-screen input.
- [ ] RSS-ADK-Deploy.log ends with RESULT=SUCCESS on successful runs.

## OOBE/Autopilot (per release, at least one device)

- [ ] OOBE completes on a network that allows NCSI (msftconnecttest.com reachable).
- [ ] The Autopilot profile is fetched (event 161 in ModernDeployment-Diagnostics-Provider/Autopilot) or the cause of it not arriving is documented.
- [ ] If it hangs on "De verbinding met Microsoft wordt gecontroleerd" (the on-screen Dutch text for "checking the connection to Microsoft"): diagnose with `tools/Collect-RSSOOBEDiag.ps1` and classify per chapter 13.2 of the manual (image/network/service/Autopilot/regression).
