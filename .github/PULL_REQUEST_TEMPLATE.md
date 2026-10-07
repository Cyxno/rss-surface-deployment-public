<!--
Vul de checklist in. CI valideert syntax, guardrails, manifestconsistentie,
links en secrets; media- en fysieke validatie kan niet via CI en moet hier
expliciet gemeld worden.
-->

## Wat verandert er en waarom?

<!-- context: welke implementatie/manifest/docs-aanpassing, met bewijs waar nodig
     (zie CONTRIBUTING.md: bewijs vóór wijziging) -->

## Invloed op de deployment

- [ ] Geen invloed op RSS-Deploy.ps1 / boot.wim
- [ ] Wijzigt deploymentlogica → media-herbouw + fysieke test vereist
- [ ] Wijzigt manifest (versies/hashes/SKU's) → bron gecontroleerd tegen Microsoft

## Checklist

- [ ] CI groen (automatisch)
- [ ] `tools/Build-Checksums.ps1` gedraaid na bestandswijzigingen
- [ ] Documentatie regenereren waar nodig: `tools/Build-Documentation.ps1`
- [ ] Tests uitgebreid voor nieuwe veiligheidslogica
- [ ] CHANGELOG.md bijgewerkt
- [ ] Geen secrets of Microsoft-binaries toegevoegd

## Fysieke teststatus

<!-- bij wijzigingen die een rebuild vereisen: welke modellen zijn fysiek
     (her)getest, en welke zijn daarmee NOT PHYSICALLY VALIDATED op de nieuwe media? -->
