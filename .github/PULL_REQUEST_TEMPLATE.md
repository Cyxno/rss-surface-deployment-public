<!--
Fill in the checklist. CI validates syntax, guardrails, manifest consistency,
links and secrets; media and physical validation cannot be done via CI and must
be reported explicitly here.
-->

## What changes and why?

<!-- context: which implementation/manifest/docs change, with proof where needed
     (see CONTRIBUTING.md: proof before change) -->

## Impact on the deployment

- [ ] No impact on RSS-Deploy.ps1 / boot.wim
- [ ] Changes deployment logic → media rebuild + physical test required
- [ ] Changes the manifest (versions/hashes/SKUs) → source verified against Microsoft

## Checklist

- [ ] CI green (automatic)
- [ ] `tools/Build-Checksums.ps1` run after file changes
- [ ] Documentation regenerated where needed: `tools/Build-Documentation.ps1`
- [ ] Tests extended for new safety logic
- [ ] CHANGELOG.md updated
- [ ] No secrets or Microsoft binaries added

## Physical test status

<!-- for changes that require a rebuild: which models were physically
     (re)tested, and which are therefore NOT PHYSICALLY VALIDATED on the new media? -->
