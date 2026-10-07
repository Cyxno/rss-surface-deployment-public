<#
.SYNOPSIS
    Herbouwt checksums/SHA256SUMS.txt over alle door Git beheerde tekstbestanden.

.DESCRIPTION
    De controlesomlijst is een release-artefact: een ontvanger kan er repo- en
    stickconfiguratie mee verifiëren. Dit script leidt de lijst volledig af uit
    `git ls-files` (vastlegde bestanden, deterministische volgorde, LF-regels)
    zodat de lijst nooit meer verouderd raakt wanneer bestanden bijkomen of
    verdwijnen.

    Uitzonderingen (bewust buiten de lijst):
      - checksums/SHA256SUMS.txt zelf (cirkelverwijzing)
      - docs/generated/** (bouwartefacten; hun inhoud volgt uit de bronnen)

.PARAMETER Commit
    Schrijf het resultaat weg (standaard) of toon het alleen (-Commit:$false).

.EXAMPLE
    .\tools\Build-Checksums.ps1
#>
[CmdletBinding()]
param(
    [bool]$Commit = $true
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$target = Join-Path $repo 'checksums\SHA256SUMS.txt'

Set-Location -LiteralPath $repo
# ls-files bevat ook verwijderde-maar-nog-niet-gecommitte bestanden; filter op bestaan.
$files = @(git ls-files | Where-Object {
    $_ -ne 'checksums/SHA256SUMS.txt' -and $_ -notmatch '^docs/generated/'
} | Where-Object { Test-Path -LiteralPath ($_ -replace '/', [System.IO.Path]::DirectorySeparatorChar) })

$lines = foreach ($f in $files) {
    $path = Join-Path $repo ($f -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $f"
}

$output = ($lines -join "`n") + "`n"
if ($Commit) {
    # LF-regels, UTF-8 zonder BOM, deterministische volgorde
    [System.IO.File]::WriteAllText($target, $output, [System.Text.UTF8Encoding]::new($false))
    Write-Host "SHA256SUMS.txt bijgewerkt: $($files.Count) bestanden" -ForegroundColor Green
} else {
    $output
}
