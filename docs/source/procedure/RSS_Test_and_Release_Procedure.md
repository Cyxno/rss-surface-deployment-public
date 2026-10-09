---
title: "RSS — Test and Release Procedure"
subtitle: "From code change to production release"
version: "2.0"
classification: "Open source — AGPL-3.0-only"
audience: "IT administration, release manager"
---

# 1. Purpose

This procedure describes how a change to RSS goes from code to an approved production stick, and what evidence is required at each step. Core rule: **software tests never prove physical correctness on Surface hardware.** The four release levels are explicit:

```text
code validated → media validated → physically validated → production approved
```

# 2. Test matrix

The full per-model matrix is in `docs/TESTMATRIX.md`; the physical quicklist in `docs/PHYSICAL-TEST-QUICKLIST.md`. Summarized per device: boot/detection (Secure Boot, TPM, USB-UEFI, model/CPU/disk detection), routing/safety (correct image and archive, preflight stops, ARM refusal), deployment (countdown, GPT layout, apply, driver injection with exact INF count, BCDBoot, green screen), first boot (USB removed, normal OOBE, input/touch/Wi-Fi, Device Manager, Autopilot/Intune, Windows Update level).

Negative tests (once per release, on a practice device): an unsupported model shows red without touching Disk 0; ARM/Snapdragon is refused; a missing driver archive stops safely; no step asks for input; the log ends with `RESULT=SUCCESS` on successful runs.

# 3. Validation commands (software)

```powershell
# full CI equivalent locally (PowerShell 7 recommended):
Invoke-Pester -Path tests                     # guardrail tests (33, mocked)
Invoke-ScriptAnalyzer -Path . -Recurse        # linting
.\tools\Test-ManifestConsistency.ps1          # manifest + outputs + checksums

# after a media build, on the candidate stick:
.\tools\Validate-RSSMedia.ps1                 # read-only stick validation (0 FAIL required)
.\tools\Test-DriverArchives.ps1 -Root <archives> -WimlibPath <wimlib>   # optional, archives separately
```

Acceptance: Pester 0 FAIL; ScriptAnalyzer 0 errors; manifest consistency green; stick validation 0 FAIL (explain any WARNs in the release).

# 4. Physical test procedure (per model)

1. Identify the candidate stick: note the boot.wim hash + `RSS-INFO.txt`.
2. Work through the quicklist (`docs/PHYSICAL-TEST-QUICKLIST.md`) and fill it in: device, date, tester, all checkpoints.
3. One negative physical test on at least one device per release (the stick must stop safely).
4. Record the result: passed checkpoints, deviations, log file.

Status tracking: the physical status per model is recorded in `config/sources.json` (`physicalValidation` per profile) and made visible in the README and the manual. Untested models remain explicitly **NOT PHYSICALLY VALIDATED**.

# 5. Release gates

| Gate | Requirement | Evidence |
|---|---|---|
| CI green | syntax, PSSA, Pester, manifest consistency, links, secret scan, no binaries | GitHub Actions run on the release commit |
| Media validated | `Validate-RSSMedia.ps1` 0 FAIL on the candidate stick | validation report |
| Physical | per target model one successful full deployment + first boot | completed quicklists |
| Documentation | DOCX/PDF regenerated from the manifest (`Build-Documentation.ps1`) and visually checked | docs/generated/ |
| Checksums | `Build-Checksums.ps1` run; SHA256SUMS.txt up to date | checksums/ |
| Manifest | release fields updated (tag, date, boot.wim hash, validationState) | config/sources.json |

# 6. Sign-off

```text
Release:        v____   Tag: ______________
Media:          Windows ____ , drivers ____, boot.wim SHA-256 ______________
CI:             green? YES/NO   run: ______________
Stick validation: PASS/WARN/FAIL  report: ______________
Physically tested:  SF4 [ ]  SF5 [ ]  SF6 [ ]  SF7 [ ]  SF8 [ ]  (quicklists attached)
Known limitations: ______________________________
Approved by: ______________  Date: ____-__-____  Production approved: YES/NO
```

# 7. After the release

1. Push the tag (`vX.Y.Z`) and reference it back in the manifest.
2. Check the CHANGELOG entry (Keep a Changelog format).
3. Label production sticks with tag + date + boot.wim hash (short); take the old production stick out of service (label it "RETIRED").
4. Update the physical validation status per model in the manifest as soon as new field tests have been done.
