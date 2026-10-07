# Security Policy

## Scope

RSS is een deploymentproject voor het uitrollen van Windows 11 op Microsoft Surface Laptop-hardware. Er is geen opensourcelicentie toegekend; de code wordt 'as-is' beschikbaar gesteld.

## Een beveiligingsprobleem melden

Meld beveiligingsproblemen (bijvoorbeeld: een guardrail die een onveilige situatie toch laat doorgaan, een manifesthash die niet klopt, een onbedoeld opgenomen secret) rechtstreeks bij de eigenaar van de repository via een **private** kanaal — niet via een publieke issue.

Wat altijd geldt:

- Voeg in een melding **nooit** secrets, productsleutels, serienummers, hardware-hashes of deploymentlogs met apparaatgegevens toe.
- Vermeld bij deployment-gerelateerde meldingen het profiel (SF4–SF8), de fouttekst van het rode scherm en de RESULT=…-regel uit het log.

## Zekerheidsmodel (wat RSS wél en niet garandeert)

1. **Destructieve werking by design:** RSS wist de interne NVMe-schijf van het doelapparaat na preflight en een aftelling van 15 seconden. De guardrails (model-/SKU-/CPU-detectie, media-eenduidigheid, NVMe-uniekheid, hashcontrole) beperken het doelscenario; ze maken een wisactie op een supported apparaat nooit onmogelijk.
2. **Vertrouwensketen:** alle bronnen (ADK, WinPE-add-on, wimlib, Surface-MSI's, Windows-updates) komen van officiële Microsoft-domeinen en worden gecontroleerd op SHA-256 en Authenticode-handtekening vóór gebruik. Het manifest (`config/sources.json`) is de vertrouwensbasis; wijzigingen daaraan volgen de gewone releaseprocedure.
3. **Offline deployment:** RSS-Deploy gebruikt tijdens deployment geen netwerk. OOBE vereist na de installatie wél netwerk (by design, voor Autopilot/Intune).
4. **Geen bypass:** unattend-bestanden, lokale accounts, `ms-cxh:localonly`, `BypassNRO` of test-signing zijn verboden; de validatie faalt bewust op deze patronen.
5. **Stick vóór interne SSD:** na het groene scherm moet de USB worden verwijderd; een stick die in de bootvolgorde vóór de interne SSD blijft staan, kan een volgende boot opnieuw laten deployen.

## Bekende beperkingen

Zie hoofdstuk 24 (Known limitations) van de technische handleiding (`docs/generated/RSS_Technische_bouw_en_beheerhandleiding.pdf`) en `nextRefresh` in het manifest.
