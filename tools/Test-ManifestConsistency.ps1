<#
.SYNOPSIS
    Checks manifest structure, generated outputs and the checksum list.

.DESCRIPTION
    Runs headless (without the stick, without administrator rights) and is
    therefore the CI counterpart of Validate-RSSMedia.ps1. Checks:

      - config/sources.json is valid JSON with all mandatory sections/fields
      - each driver profile: mandatory fields, SHA-256 format (64 hex),
        official URL hosts, INF count > 0, supported SystemSKUs present
      - refusal lists: SF7 contains the 5G SKU, SF8 contains the Snapdragon SKUs
      - load-order files exist per profile
      - deployment files (src/winpe) exist
      - generated documentation (docs/generated) is present and up to date
        (RSS-INFO mentions the manifest build and all INF counts)
      - checksums/SHA256SUMS.txt is up to date relative to the Git files
        (only with -CIChecksums or explicitly enabled: requires git)

.EXAMPLE
    ./tools/Test-ManifestConsistency.ps1
    ./tools/Test-ManifestConsistency.ps1 -CIChecksums
#>
[CmdletBinding()]
param(
    # In CI the checkout is clean, so the checksum comparison is reliable.
    [switch]$CIChecksums
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$fail = 0
function Assert-True([bool]$Condition, [string]$Message) {
    if ($Condition) { Write-Host "[PASS] $Message" } else { Write-Host "[FAIL] $Message" -ForegroundColor Red; $script:fail++ }
}

# ------------------------------------------------------------- manifest
$manifestPath = Join-Path $repo 'config\sources.json'
Assert-True (Test-Path $manifestPath) 'config/sources.json exists'
$mst = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($section in 'project', 'windows', 'adk', 'wimlib', 'media', 'diskSafety', 'surfaceDriverPacks', 'explicitlyUnsupported', 'nextRefresh') {
    Assert-True ($null -ne $mst.PSObject.Properties[$section]) "manifest section '$section' present"
}
Assert-True ($mst.windows.servicedImage.verifiedBuild -match '^\d+\.\d+$') "verifiedBuild is a build number ($($mst.windows.servicedImage.verifiedBuild))"
Assert-True ($mst.media.bootWimSha256 -match '^[0-9A-F]{64}$') 'boot.wim SHA-256 format'

$hex64 = '^[0-9A-Fa-f]{64}$'
foreach ($pack in $mst.surfaceDriverPacks) {
    $p = $pack.profile
    foreach ($field in 'profile', 'product', 'cpuVendor', 'infCount', 'msiFilename', 'directUrl', 'downloadPage', 'sha256', 'archiveSha256', 'systemSku', 'lifecycle', 'physicalValidation') {
        Assert-True ($null -ne $pack.PSObject.Properties[$field]) "$p field '$field' present"
    }
    Assert-True ($pack.sha256 -match $hex64) "$p MSI SHA-256 format"
    Assert-True ($pack.archiveSha256 -match $hex64) "$p archive SHA-256 format"
    Assert-True ($pack.infCount -gt 0) "$p INF count > 0 ($($pack.infCount))"
    Assert-True ($pack.directUrl -match '^https://download\.microsoft\.com/') "$p directUrl official host"
    Assert-True ($pack.downloadPage -match '^https://www\.microsoft\.com/en-us/download/') "$p downloadPage official host"
    Assert-True (@($pack.systemSku.supported).Count -gt 0) "$p has supported SystemSKUs"
    Assert-True (Test-Path (Join-Path $repo "config\load-orders\$p\load-order.txt")) "$p load-order exists"
    Assert-True ($null -ne $pack.physicalValidation.status) "$p has a physical validation status"
}
$skus = @{ SF7 = 'Surface_Laptop_5G_7th_Edition_With_Intel_For_Business_2119'; SF8 = 'Surface_Laptop_for_Business_13_8in_8th_Ed_Snapdragon_2036' }
foreach ($modelProfile in 'SF7', 'SF8') {
    $pack = $mst.surfaceDriverPacks | Where-Object profile -eq $modelProfile
    Assert-True (@($pack.systemSku.refused) -contains $skus[$modelProfile]) "$modelProfile refusal list contains the known refused SKU"
}

# --------------------------------------------------- deployment files
foreach ($f in 'src\winpe\RSS-Deploy.ps1', 'src\winpe\RSS-SafetyLib.ps1', 'src\winpe\Build-WinPE.ps1', 'src\winpe\startnet.cmd',
    'tools\Update-RSSMedia.ps1', 'tools\Validate-RSSMedia.ps1', 'tools\Test-DriverArchives.ps1', 'tools\Collect-RSSOOBEDiag.ps1',
    'docs\source\manual\RSS_Technical_Build_and_Management_Manual.md', 'docs\source\operations\RSS_Operations_Manual.md',
    'docs\source\procedure\RSS_Test_and_Release_Procedure.md') {
    Assert-True (Test-Path (Join-Path $repo $f)) "file present: $f"
}

# ------------------------------------------------------------ generated
foreach ($doc in 'RSS_Technical_Build_and_Management_Manual', 'RSS_Operations_Manual', 'RSS_Test_and_Release_Procedure') {
    foreach ($ext in '.docx', '.pdf') {
        Assert-True (Test-Path (Join-Path $repo "docs\generated\$doc$ext")) "generated document present: $doc$ext"
    }
}
$stickInfoPath = Join-Path $repo 'docs\generated\stick\RSS-INFO-production.txt'
Assert-True (Test-Path $stickInfoPath) 'generated stick documentation present'
if (Test-Path $stickInfoPath) {
    $stickInfo = Get-Content $stickInfoPath -Raw -Encoding UTF8
    Assert-True ($stickInfo -match [regex]::Escape($mst.windows.build)) "RSS-INFO mentions manifest build $($mst.windows.build)"
    foreach ($pack in $mst.surfaceDriverPacks) {
        Assert-True ($stickInfo -match [regex]::Escape("$($pack.profile)")) "RSS-INFO mentions $($pack.profile)"
        Assert-True ($stickInfo -match "$($pack.profile).*\b$($pack.infCount)\b") "RSS-INFO mentions $($pack.profile) with $($pack.infCount) INF"
    }
    Assert-True ($stickInfo -match [regex]::Escape($mst.media.bootWimSha256)) 'RSS-INFO mentions the boot.wim hash'
}

# --------------------------------------------------------------- checksums
if ($CIChecksums) {
    $sumsPath = Join-Path $repo 'checksums\SHA256SUMS.txt'
    Assert-True (Test-Path $sumsPath) 'checksums/SHA256SUMS.txt exists'
    if (Test-Path $sumsPath) {
        Push-Location $repo
        try {
            # same file set as Build-Checksums.ps1 (ls-files filters out
            # deleted-but-not-yet-committed files)
            $expected = @(git ls-files | Where-Object { $_ -ne 'checksums/SHA256SUMS.txt' -and $_ -notmatch '^docs/generated/' } |
                Where-Object { Test-Path -LiteralPath ($_ -replace '/', [System.IO.Path]::DirectorySeparatorChar) } | Sort-Object)
            $actual = @(Get-Content $sumsPath -Encoding UTF8 | Where-Object { $_.Trim() } | ForEach-Object { ($_ -split '  ', 2)[1] } | Sort-Object)
            $drift = Compare-Object $expected $actual
            Assert-True (-not $drift) "SHA256SUMS.txt covers exactly the Git files $(if ($drift) { "(difference: $(($drift | ForEach-Object { $_.InputObject }) -join ', '))" })"
        } finally { Pop-Location }
    }
}

Write-Host ''
if ($fail) { Write-Host "MANIFEST CONSISTENCY: $fail FAIL" -ForegroundColor Red; exit 1 }
Write-Host 'MANIFEST CONSISTENCY: ALL PASS' -ForegroundColor Green
exit 0
