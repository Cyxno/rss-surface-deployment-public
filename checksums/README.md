# Checksums

`SHA256SUMS.txt` contains SHA-256 checksums for the managed source files and for the key configuration files of the proven production USB. Large Microsoft binaries are not included in the repository; their checksums remain useful for verifying a local archive or a cloned stick.

Verify a file in PowerShell with:

```powershell
Get-FileHash -LiteralPath '<path>' -Algorithm SHA256
```


Note: the checksums were computed on the Windows working copy, i.e. with the line endings prescribed by `.gitattributes` (CRLF for PowerShell/CMD, LF for the other text files). Verify preferably on a Windows checkout of the same tag; on a Linux checkout the line endings — and with them the hashes of the affected files — differ.
