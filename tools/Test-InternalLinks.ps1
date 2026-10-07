<#
.SYNOPSIS
    Checks internal links in README and docs (relative paths and anchors).

.DESCRIPTION
    Walks all Markdown files in the repository and checks that every
    relative link target (path or path#anchor) exists. External http(s)-links
    are not followed (CI stays deterministic and offline); those are checked
    periodically by hand during the maintenance round.

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
        # skip external URLs, anchors and GitHub-UI pseudo paths (../../releases)
        if ($url -match '^(https?:|mailto:|#|\.\./)') { continue }
        $targetPath = Join-Path $file.DirectoryName ($url -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $targetPath)) {
            Write-Host "[FAIL] $($file.FullName.Substring($repo.Length + 1)): link target missing -> $url" -ForegroundColor Red
            $script:fail++
        } elseif ($link.Groups[2].Value -and (Get-Item -LiteralPath $targetPath).Extension -eq '.md') {
            if (-not (Test-Anchor -MarkdownPath $targetPath -Anchor ($link.Groups[2].Value.Substring(1)))) {
                Write-Host "[FAIL] $($file.FullName.Substring($repo.Length + 1)): anchor missing -> $($link.Groups[2].Value)" -ForegroundColor Red
                $script:fail++
            }
        }
    }
}

Write-Host ''
if ($fail) { Write-Host "LINKCHECK: $fail broken internal link(s)" -ForegroundColor Red; exit 1 }
Write-Host "LINKCHECK: all internal links ok ($($files.Count) markdown files)" -ForegroundColor Green
exit 0
