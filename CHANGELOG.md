# Changelog

All notable changes to this project are documented in this file. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the versions follow [SemVer](https://semver.org/).

## [2.0.0] — 2026-10-02

A major modernization of the repository, the safety mechanisms and the documentation. Deployment behavior on supported hardware is unchanged; the new guardrails are strictly fail-safe (they stop more often, never write more).

### Added

- **Canonical manifest v2** (`config/sources.json`): SystemSKU allowlists and refusal lists per profile (based on the official Microsoft Surface SystemSKU reference), lifecycle EOL dates per driver package, an explicit list of unsupported variants, a `nextRefresh` section (SafeOS DU KB5125758, Windows 26H2 evaluation, Machine Identity Isolation watch) and a per-profile `physicalValidation` status. The manifest travels on the stick and is read by the deployment.
- **Safety library** `src/winpe/RSS-SafetyLib.ps1`: all decision functions (model/SKU detection, media recognition, target disk selection, hash check) as pure, testable functions.
- **Pre-wipe hash check:** the SHA-256 of both the model-specific Windows image and the driver archive is verified against the manifest before the countdown (INVALID = STOP).
- **Unambiguous NVMe targeting:** the target disk must be the only internal NVMe disk and must sit on Disk 0; multiple NVMe disks or a relocated NVMe results in a safe stop (previously, Disk 0 was wiped blindly on deviations).
- **SystemSKU check:** empty, unknown or refused SKUs stop the deployment (UNKNOWN/UNSUPPORTED = STOP).
- **Pester guardrail tests** (`tests/`): 33 mocked tests covering the complete hazard matrix; they never touch real disks and run in CI.
- **CI** (`.github/workflows/validate.yml`): PSScriptAnalyzer 1.25.0, Pester 5.7+, manifest consistency, internal link check, gitleaks secret scan, absence of Microsoft binaries in Git. It never runs a deployment or a download.
- **Repository hygiene:** CONTRIBUTING.md, SECURITY.md, CHANGELOG.md, PR/issue templates, `.editorconfig`, `.gitattributes`, Dependabot (Actions pinning only).
- **Documentation pipeline** `tools/Build-Documentation.ps1`: DOCX (pandoc + reference theme, header/footer with page numbers) and PDF (Typst, table of contents with page numbers) from a single canonical source (`docs/source/**` + manifest tokens), plus generated stick documentation and the README version block.
- **Maintenance tools:** `tools/Build-Checksums.ps1` (rebuilds SHA256SUMS.txt from `git ls-files`), `tools/Test-ManifestConsistency.ps1` (headless manifest/output check), `tools/Test-InternalLinks.ps1`.
- **OOBE documentation based on current research (2026-10):** five OOBE failure classes (image/network/Microsoft service/Autopilot-MDM/regression), official diagnostic paths and event log locations; `tools/Collect-RSSOOBEDiag.ps1` (moved over from branch `refresh-2026-09-sf8`) as a read-only collector.

### Changed

- `Validate-RSSMedia.ps1`: profile lists now come from the manifest instead of being hardcoded; new checks on manifest identity (sources.json on the stick == repo), guardrail presence in the deployment logic and manifest consistency of RSS-INFO.txt; the AST check now also covers `RSS-SafetyLib.ps1`.
- `Update-RSSMedia.ps1`: removed the broken placeholder DISM call in the Image phase; hardened downloads (`--fail --retry 3 --connect-timeout 30`, partial downloads are cleaned up); the Media phase places `sources.json` and the generated stick documentation on the stick; the BootWim phase copies the safety library along.
- `Test-DriverArchives.ps1`: manifest-driven (INF counts are no longer duplicated in the script).
- README fully redesigned (badges, Mermaid flow, generated hardware block, validation levels, release process).
- Stick documentation (`RSS-INFO-production.txt`, `README-AUTOINSTALL.txt`) is now generated from the manifest instead of being maintained by hand.

### Removed

- Outdated hand-maintained documentation: `docs/RSS_Technical_Build_and_Management_Manual.docx/.pdf` (v2.0, 2026-09-23; replaced by generated editions; retrieve via tag `rss-2026-09-sf8`), the hand-maintained `docs/RSS-INFO-production.txt` and `docs/README-AUTOINSTALL.txt` (now in `docs/generated/stick/`).
- Duplication of INF counts and model lists in scripts (single source: the manifest).

### Validation status of this release

- Code validated: CI/Pester 33/33 PASS, manifest consistency PASS (verified locally).
- Media validated: based on the production stick of 2026-09-23; new media built after this modernization require a new stick validation round.
- Physically validated: SF6 only (field test 2026-09). SF4, SF5, SF7 and SF8 are **NOT PHYSICALLY VALIDATED** on the current media.
- Production approved: only after physical (re)validation on freshly built media.

## [rss-2026-09-sf8] — 2026-09-24

First tagged release of the V2 stick: Windows 11 25H2 build 26200.9457 (nl-NL), ADK 10.1.26100.9457 WinPE base, profiles SF4–SF8 with full official driver packages, a read-only stick validator and the technical manual. Physically validated on Surface Laptop 6.
