# RSS PHYSICAL TEST — QUICK CHECKLIST

> ## 🔴 ON A RED SCREEN
> **Take a photo of the error message and copy `F:\RSS-ADK-Deploy.log`**
> (from the Images partition) **before you retry.**
> Power off with the power button; the screen stays red deliberately.

Device: ______________  Date: ____-__-__  Tester: __________

## Before you start

- [ ] USB stick inserted (device OFF)
- [ ] Secure Boot **ON** in Surface UEFI
- [ ] TPM **ON**
- [ ] Power adapter connected

## Deployment (do not touch anything after step 3!)

- [ ] Boot from USB (UEFI)
- [ ] WinPE starts automatically (black/green screen)
- [ ] Correct model detected (shown on screen)
- [ ] Correct SF profile (SF4/SF5/SF6/SF7/SF8)
- [ ] Target disk = internal NVMe (shown on screen)
- [ ] After the 15 s countdown the wipe starts automatically

## Installation

- [ ] Windows image applied
- [ ] Drivers injected
- [ ] **GREEN screen** ("INSTALLATION SUCCESSFUL!")
- [ ] Automatic reboot → **USB removed during green screen**

## First Windows boot

- [ ] Windows boots with Secure Boot on
- [ ] Keyboard works
- [ ] Trackpad/touch works
- [ ] Wi-Fi networks visible
- [ ] **Normal OOBE** appears (no auto-signed-in user)
- [ ] MDM/Autopilot enrollment started / possible
- [ ] Device Manager: no unknown essential devices

## Notes

.................................................................

.................................................................
