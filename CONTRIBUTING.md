# Contributing

This project is licensed under the **GNU Affero General Public License v3.0 only** (AGPL-3.0-only) — see [LICENSE](LICENSE). The repository is maintained by its owner. External pull requests are not accepted; an issue with clear reproduction steps is welcome.

## Core rule: proof before change

The deployment logic is destructive. Do not change working logic merely because an alternative looks nicer:

1. first reconstruct the current behavior (read `src/winpe/RSS-SafetyLib.ps1`, `RSS-Deploy.ps1` and the technical manual);
2. change only with a demonstrable reason (safety, a documented bug, a documented Microsoft change);
3. prove it with tests: new decision logic belongs in `RSS-SafetyLib.ps1` (pure functions) and gets Pester coverage in `tests/`;
4. fail-safe takes precedence over availability: `UNKNOWN/AMBIGUOUS/UNSUPPORTED/MISSING/INVALID = STOP`.

## Taking a change through

1. **Branch** from `main`.
2. **Manifest first:** versions, hashes, INF counts, SKUs and models live only in `config/sources.json`. Do not add a copy anywhere else; read the value from the manifest.
3. **Tests locally** (PowerShell 5.1 or 7+, no administrator required):
   ```powershell
   Invoke-Pester -Path tests
   Invoke-ScriptAnalyzer -Path . -Recurse -Settings .PSScriptAnalyzerSettings.psd1
   ./tools/Test-ManifestConsistency.ps1
   ./tools/Test-InternalLinks.ps1
   ```
4. **Documentation:** content changes go in `docs/source/**` (Markdown with `{{manifest.pad}}` tokens); afterwards regenerate the DOCX/PDF/stick docs and the README block:
   ```powershell
   ./tools/Build-Documentation.ps1
   ```
   Requires pandoc ≥ 3.6 and Typst ≥ 0.15 (or use `-StickDocsOnly` without those tools). **Never** generate the outputs by hand; `docs/generated/` is machine output.
5. **Checksums** after every file change:
   ```powershell
   ./tools/Build-Checksums.ps1
   ```
6. **Commit:** one logical theme per commit; commit messages like `feat: …`, `fix: …`, `docs: …`, `chore: …`, `build: …`.
7. **Pull request:** fill in the template. CI validates syntax, linting, Pester, manifest consistency, internal links, secrets (gitleaks) and absence of binaries.

## Rules

- **Never** commit secrets, passwords, product keys, serial numbers, hardware hashes, deployment logs or tenant identifiers.
- **Never** commit Microsoft binaries (`.wim/.esd/.msi/.msu/.iso/.cab`); `.gitignore` and CI guard against this.
- **Never** invent or guess a hash or download URL: verify against the official Microsoft source and record the date of verification in the manifest (`verifiedCurrent` fields).
- **Never** silently support new Surface models: a new profile = manifest extension (SKUs, driver package, INF count after extraction), a load order, a Pester fixture and its own physical test round.
- Changes to `RSS-Deploy.ps1`/`RSS-SafetyLib.ps1` require a **media rebuild and physical test** before production; state the status in the PR.
- Never modify a production stick directly; work via `Update-RSSMedia.ps1` on a candidate stick.

## Releases

Releases follow `docs/source/procedure/RSS_Test_and_Release_Procedure.md`: semver tag (`vX.Y.Z`), a CHANGELOG entry, up-to-date checksums and the four explicit gates (code / media / physical / production approved).
