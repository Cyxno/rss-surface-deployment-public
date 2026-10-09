---
title: "RSS — Operations Manual"
subtitle: "Using the stick on a Surface Laptop"
version: "2.0"
classification: "Open source — AGPL-3.0-only"
audience: "Staff who actually deploy the stick"
---

# 1. When may the stick be used?

- Only on a device from the supported list below, only by someone authorized to wipe it, and only if the data on the internal disk may be deliberately erased.
- **Supported:** Surface Laptop 4 (AMD), Surface Laptop 5 (Intel), Surface Laptop 6 for Business (Intel), Surface Laptop for Business 7th Edition with Intel, Surface Laptop for Business 8th Edition with Intel (13.8"/15").
- **Not supported (safe stop, nothing happens):** all other models, ARM/Snapdragon variants, the Surface Laptop 5G for Business 7th Edition, and the Intel variant of the Surface Laptop 4.

> **WARNING:** after the checks a 15-second countdown starts; after that the internal disk is wiped without further prompting. Powering off the device during the countdown = cancel.

# 2. Preparation

1. Check the device model (shown on screen during detection).
2. Connect mains power.
3. Make sure the device is fully powered off and insert the stick.
4. Boot from USB (UEFI). Secure Boot and TPM stay on.

# 3. What you see (normal phases)

| Phase | Screen | Duration (indicative) |
|---|---|---|
| Boot | black, brief WinPE start | ± 1 min |
| Green animation + steps | model, SKU, CPU, disk and driver information | ± 2 min (incl. hash check of image and drivers) |
| Yellow countdown | "Installation starts in" — 15 s | last chance to cancel (power off) |
| Steps 1–5 | disk partitioning, image, drivers, boot files | ± 10–20 min (may show little visible progress for a long time — normal) |
| Fully green | "INSTALLATION SUCCESSFUL!" + countdown | **remove the USB stick now** |
| Automatic reboot | first Windows boot and OOBE | ± 5–10 min (multiple restarts are normal) |

The stick requires no keyboard, mouse or touch: the entire flow runs automatically.

# 4. First boot and OOBE

- The device ends up in a completely normal Windows OOBE (Dutch). No local account is created and no bypass is active — precisely so that Autopilot/Intune enrollment can follow.
- In the OOBE, check: touchscreen, keyboard/trackpad, Wi-Fi networks visible, USB working.
- After organizational credentials are entered, the regular Autopilot/Intune enrollment starts.
- Before the first boot, the device is already fully provisioned with official Surface drivers (offline DriverStore).

**Does the OOBE hang on "De verbinding met Microsoft wordt gecontroleerd" (the on-screen Dutch text for "checking the connection to Microsoft")?** This is almost always a network or registration issue, not an image error: check that the network allows the Microsoft connectivity test and that the device is registered in Autopilot. Diagnosis: Shift+F10 and `tools\Collect-RSSOOBEDiag.ps1` from the stick (collects everything automatically, read-only). Never use an OOBE bypass.

# 5. Red screen (safe stop)

A fully red screen means: **stopped before the write action, or with a clear error message.**

1. Take a photo of the error message.
2. Copy `F:\RSS-ADK-Deploy.log` (Images partition) if the error occurred after the medium was recognized.
3. Power off with the power button; the screen is deliberately left as it is.
4. Contact IT administration with photo + log + device model.

If the stop happens before the countdown, the disk is **untouched**.

# 6. When to stop immediately

- The screen shows a different model from the device you are working on → power off, report the stick.
- The countdown starts while you are not authorized or in doubt → power off during the countdown.
- Smoke, smell, extreme heat or repeated identical errors → stop, leave the device alone and report it.

# 7. Post-deployment check

- [ ] Green screen appeared; USB removed at the green screen.
- [ ] Windows boots with Secure Boot on (no USB needed).
- [ ] OOBE appears normally; input, touch and Wi-Fi work.
- [ ] Autopilot/Intune enrollment started or possible.
- [ ] Device Manager: no unknown essential devices.
- [ ] Windows Update shows at most updates newer than the stick's build time.

# 8. Quick troubleshooting

| Symptom | Meaning | Action |
|---|---|---|
| Red before countdown | preflight stop; disk untouched | photo + log, report |
| Red at "hash"/"integrity" | stick contents corrupt | do not reuse the stick; report and rebuild |
| Red "unsupported model" | device out of scope | choose another deployment route |
| Countdown while cancelling is desired | last chance | power off the device during the countdown |
| Long "little visible progress" | normal for image/drivers | wait; do not power off after the countdown |
| OOBE hangs on the network check | network/Autopilot registration | diagnose per chapter 4; report to IT administration |
| Brief reboots at first boot | normal first-boot process | wait at least 10 minutes |

Full technical troubleshooting: `RSS_Technical_Build_and_Management_Manual`, chapter 18.
