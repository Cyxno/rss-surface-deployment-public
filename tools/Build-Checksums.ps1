<#
.SYNOPSIS
    Rebuilds checksums/SHA256SUMS.txt over all Git-managed text files.

.DESCRIPTION
    The checksum list is a release artifact: a recipient can use it to verify
    repo and stick configuration. This script derives the list entirely from
    `git ls-files` (committed files, deterministic order, LF line endings)
    so the list never goes stale when files are added or removed.

    Exceptions (deliberately outside the list):
      - checksums/SHA256SUMS.txt itself (circular reference)
      - docs/generated/** (build artifacts; their content follows from the sources)

.PARAMETER Commit
    Write the result to disk (default) or only display it (-Commit:$false).

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
# ls-files also contains deleted-but-not-yet-committed files; filter on existence.
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
    # LF line endings, UTF-8 without BOM, deterministic order
    [System.IO.File]::WriteAllText($target, $output, [System.Text.UTF8Encoding]::new($false))
    Write-Host "SHA256SUMS.txt updated: $($files.Count) files" -ForegroundColor Green
} else {
    $output
}
