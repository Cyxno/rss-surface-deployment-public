# Security Policy

## Scope

RSS is a deployment project for rolling out Windows 11 on Microsoft Surface Laptop hardware. No open-source license is granted; the code is made available 'as-is'.

## Reporting a security issue

Report security issues (for example: a guardrail that lets an unsafe situation through anyway, a manifest hash that does not match, an inadvertently committed secret) directly to the repository owner through a **private** channel — not via a public issue.

Always apply the following:

- **Never** include secrets, product keys, serial numbers, hardware hashes or deployment logs containing device data in a report.
- For deployment-related reports, include the profile (SF4–SF8), the error text of the red screen and the RESULT=… line from the log.

## Assurance model (what RSS does and does not guarantee)

1. **Destructive action by design:** RSS wipes the internal NVMe disk of the target device after a preflight and a countdown of 15 seconds. The guardrails (model/SKU/CPU detection, media unambiguity, NVMe uniqueness, hash check) narrow the target scenario; they never make a wipe action on a supported device impossible.
2. **Chain of trust:** all sources (ADK, WinPE add-on, wimlib, Surface MSIs, Windows updates) come from official Microsoft domains and are checked for SHA-256 and Authenticode signature before use. The manifest (`config/sources.json`) is the trust base; changes to it follow the normal release process.
3. **Offline deployment:** RSS-Deploy uses no network during deployment. OOBE does require a network after installation (by design, for Autopilot/Intune).
4. **No bypass:** unattend files, local accounts, `ms-cxh:localonly`, `BypassNRO` or test signing are forbidden; validation deliberately fails on these patterns.
5. **Stick before internal SSD:** after the green screen the USB stick must be removed; a stick that remains ahead of the internal SSD in the boot order can trigger another deployment on the next boot.

## Known limitations

See chapter 24 (Known limitations) of the technical manual (`docs/generated/RSS_Technical_Build_and_Management_Manual.pdf`) and `nextRefresh` in the manifest.
