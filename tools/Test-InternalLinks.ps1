<#
.SYNOPSIS
    Controleert interne links in README en docs (relatieve paden en ankertjes).

.DESCRIPTION
    Loopt alle Markdown-bestanden in de repository en controleert dat ieder
    relatief linkdoel (pad of pad#anker) bestaat. Externe http(s)-links worden
    niet gevolgd (CI blijft deterministisch en offline); die worden periodiek
    handmatig gecontroleerd in de onderhoudsronde.

.EXAMPLE
    ./tools/Test-InternalLinks.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$files = @(Get-ChildItem $repo -Recurse -Filter '*.md' -File |
    Where-Object { $_.FullName -notmatch '\\(\.git|node_modules)\\' })
$fail = 0

function Test-Anchor([string]$MarkdownPath, [string]$Anchor) {
    if (-not $Anchor) { return $true }
    $target = $Anchor.ToLowerInvariant() -replace '[^a-z0-9\- ]', '' -replace ' ', '-'
    foreach ($line in (Get-Content -LiteralPath $MarkdownPath -Encoding UTF8)) {
        if ($line -match '^#{1,6}\s+(.*)$') {
            $heading = $Matches[1].Trim().ToLowerInvariant() -replace '[^a-z0-9\- ]', '' -replace ' ', '-'
            if ($heading -eq $target) { return $true }
        }
    }
    return $false
}

foreach ($file in $files) {
    $text = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
    $links = [regex]::Matches($text, '\[[^\]]+\]\(([^)#\s]+)(#[^)\s]*)?\)')
    foreach ($link in $links) {
        $url = $link.Groups[1].Value
        # externe URL's, ankertjes en GitHub-UI-pseudopaden (../../releases) overslaan
        if ($url -match '^(https?:|mailto:|#|\.\./)') { continue }
        $targetPath = Join-Path $file.DirectoryName ($url -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $targetPath)) {
            Write-Host "[FAIL] $($file.FullName.Substring($repo.Length + 1)): linkdoel ontbreekt -> $url" -ForegroundColor Red
            $script:fail++
        } elseif ($link.Groups[2].Value -and (Get-Item -LiteralPath $targetPath).Extension -eq '.md') {
            if (-not (Test-Anchor -MarkdownPath $targetPath -Anchor ($link.Groups[2].Value.Substring(1)))) {
                Write-Host "[FAIL] $($file.FullName.Substring($repo.Length + 1)): anker ontbreekt -> $($link.Groups[2].Value)" -ForegroundColor Red
                $script:fail++
            }
        }
    }
}

Write-Host ''
if ($fail) { Write-Host "LINKCHECK: $fail gebroken interne link(s)" -ForegroundColor Red; exit 1 }
Write-Host "LINKCHECK: alle interne links ok ($($files.Count) markdown-bestanden)" -ForegroundColor Green
exit 0
