# Controlesums

`SHA256SUMS.txt` bevat SHA-256-controlewaarden voor de beheerde bronbestanden en voor de belangrijkste configuratiebestanden van de bewezen productie-USB. Grote Microsoft-binaries worden niet in de repository opgenomen; hun controlesom blijft wel bruikbaar om een lokaal archief of een gekloonde stick te controleren.

Controleer een bestand in PowerShell met:

```powershell
Get-FileHash -LiteralPath '<pad>' -Algorithm SHA256
```


N.B.: de controlesums zijn berekend op de Windows-werkkopie, dus met de door `.gitattributes` voorgeschreven regeleindes (CRLF voor PowerShell/CMD, LF voor de overige tekstbestanden). Controleer bij voorkeur op een Windows-checkout van dezelfde tag; op een Linux-checkout verschillen de regeleindes en daarmee de hashes van de betreffende bestanden.
