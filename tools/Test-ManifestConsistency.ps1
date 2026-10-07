<#
.SYNOPSIS
    Controleert manifeststructuur, gegenereerde outputs en checksumlijst.

.DESCRIPTION
    Draait headless (zonder stick, zonder administrator) en is daarmee de
    CI-tegenhanger van Validate-RSSMedia.ps1. Controleert:

      - config/sources.json is geldig JSON met alle verplichte secties/velden
      - elk driverprofiel: verplichte velden, SHA-256-formaat (64 hex),
        officiële URL-hosts, INF-aantal > 0, supported SystemSKU's aanwezig
      - weigerlijsten: SF7 bevat de 5G-SKU, SF8 bevat de Snapdragon-SKU's
      - load-orderbestanden bestaan per profiel
      - deploymentbestanden (src/winpe) bestaan
      - gegenereerde documentatie (docs/generated) is aanwezig en actueel
        (RSS-INFO bevat de manifest-build en alle INF-aantallen)
      - checksums/SHA256SUMS.txt is actueel t.o.v. de Git-bestanden
        (alleen met -CIChecksums of expliciet aangezet: vereist git)

.EXAMPLE
    ./tools/Test-ManifestConsistency.ps1
    ./tools/Test-ManifestConsistency.ps1 -CIChecksums
#>
[CmdletBinding()]
param(
    # In CI draait de checkout clean, dus de checksumvergelijking is betrouwbaar.
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
Assert-True (Test-Path $manifestPath) 'config/sources.json bestaat'
$mst = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($section in 'project', 'windows', 'adk', 'wimlib', 'media', 'diskSafety', 'surfaceDriverPacks', 'explicitlyUnsupported', 'nextRefresh') {
    Assert-True ($null -ne $mst.PSObject.Properties[$section]) "manifestsectie '$section' aanwezig"
}
Assert-True ($mst.windows.servicedImage.verifiedBuild -match '^\d+\.\d+$') "verifiedBuild is een buildnummer ($($mst.windows.servicedImage.verifiedBuild))"
Assert-True ($mst.media.bootWimSha256 -match '^[0-9A-F]{64}$') 'boot.wim SHA-256-formaat'

$hex64 = '^[0-9A-Fa-f]{64}$'
foreach ($pack in $mst.surfaceDriverPacks) {
    $p = $pack.profile
    foreach ($field in 'profile', 'product', 'cpuVendor', 'infCount', 'msiFilename', 'directUrl', 'downloadPage', 'sha256', 'archiveSha256', 'systemSku', 'lifecycle', 'physicalValidation') {
        Assert-True ($null -ne $pack.PSObject.Properties[$field]) "$p veld '$field' aanwezig"
    }
    Assert-True ($pack.sha256 -match $hex64) "$p MSI SHA-256-formaat"
    Assert-True ($pack.archiveSha256 -match $hex64) "$p archief SHA-256-formaat"
    Assert-True ($pack.infCount -gt 0) "$p INF-aantal > 0 ($($pack.infCount))"
    Assert-True ($pack.directUrl -match '^https://download\.microsoft\.com/') "$p directUrl officiële host"
    Assert-True ($pack.downloadPage -match '^https://www\.microsoft\.com/en-us/download/') "$p downloadPage officiële host"
    Assert-True (@($pack.systemSku.supported).Count -gt 0) "$p heeft supported SystemSKU's"
    Assert-True (Test-Path (Join-Path $repo "config\load-orders\$p\load-order.txt")) "$p load-order bestaat"
    Assert-True ($null -ne $pack.physicalValidation.status) "$p heeft fysieke validatiestatus"
}
$skus = @{ SF7 = 'Surface_Laptop_5G_7th_Edition_With_Intel_For_Business_2119'; SF8 = 'Surface_Laptop_for_Business_13_8in_8th_Ed_Snapdragon_2036' }
foreach ($modelProfile in 'SF7', 'SF8') {
    $pack = $mst.surfaceDriverPacks | Where-Object profile -eq $modelProfile
    Assert-True (@($pack.systemSku.refused) -contains $skus[$modelProfile]) "$modelProfile weigerlijst bevat de bekende weiger-SKU"
}

# --------------------------------------------------- deploymentbestanden
foreach ($f in 'src\winpe\RSS-Deploy.ps1', 'src\winpe\RSS-SafetyLib.ps1', 'src\winpe\Build-WinPE.ps1', 'src\winpe\startnet.cmd',
    'tools\Update-RSSMedia.ps1', 'tools\Validate-RSSMedia.ps1', 'tools\Test-DriverArchives.ps1', 'tools\Collect-RSSOOBEDiag.ps1',
    'docs\source\handleiding\RSS_Technische_bouw_en_beheerhandleiding.md', 'docs\source\operationeel\RSS_Operationele_handleiding.md',
    'docs\source\procedure\RSS_Test_en_releaseprocedure.md') {
    Assert-True (Test-Path (Join-Path $repo $f)) "bestand aanwezig: $f"
}

# ------------------------------------------------------------ gegenereerd
foreach ($doc in 'RSS_Technische_bouw_en_beheerhandleiding', 'RSS_Operationele_handleiding', 'RSS_Test_en_releaseprocedure') {
    foreach ($ext in '.docx', '.pdf') {
        Assert-True (Test-Path (Join-Path $repo "docs\generated\$doc$ext")) "gegenereerd document aanwezig: $doc$ext"
    }
}
$stickInfoPath = Join-Path $repo 'docs\generated\stick\RSS-INFO-production.txt'
Assert-True (Test-Path $stickInfoPath) 'gegenereerde stickdocumentatie aanwezig'
if (Test-Path $stickInfoPath) {
    $stickInfo = Get-Content $stickInfoPath -Raw -Encoding UTF8
    Assert-True ($stickInfo -match [regex]::Escape($mst.windows.build)) "RSS-INFO noemt manifest-build $($mst.windows.build)"
    foreach ($pack in $mst.surfaceDriverPacks) {
        Assert-True ($stickInfo -match [regex]::Escape("$($pack.profile)")) "RSS-INFO vermeldt $($pack.profile)"
        Assert-True ($stickInfo -match "$($pack.profile).*\b$($pack.infCount)\b") "RSS-INFO vermeldt $($pack.profile) met $($pack.infCount) INF"
    }
    Assert-True ($stickInfo -match [regex]::Escape($mst.media.bootWimSha256)) 'RSS-INFO noemt de boot.wim-hash'
}

# --------------------------------------------------------------- checksums
if ($CIChecksums) {
    $sumsPath = Join-Path $repo 'checksums\SHA256SUMS.txt'
    Assert-True (Test-Path $sumsPath) 'checksums/SHA256SUMS.txt bestaat'
    if (Test-Path $sumsPath) {
        Push-Location $repo
        try {
            # zelfde bestandenset als Build-Checksums.ps1 (ls-files filtert
            # verwijderde-maar-nog-niet-gecommitte bestanden eruit)
            $expected = @(git ls-files | Where-Object { $_ -ne 'checksums/SHA256SUMS.txt' -and $_ -notmatch '^docs/generated/' } |
                Where-Object { Test-Path -LiteralPath ($_ -replace '/', [System.IO.Path]::DirectorySeparatorChar) } | Sort-Object)
            $actual = @(Get-Content $sumsPath -Encoding UTF8 | Where-Object { $_.Trim() } | ForEach-Object { ($_ -split '  ', 2)[1] } | Sort-Object)
            $drift = Compare-Object $expected $actual
            Assert-True (-not $drift) "SHA256SUMS.txt dekt exact de Git-bestanden $(if ($drift) { "(verschil: $(($drift | ForEach-Object { $_.InputObject }) -join ', '))" })"
        } finally { Pop-Location }
    }
}

Write-Host ''
if ($fail) { Write-Host "MANIFESTCONSISTENTIE: $fail FAIL" -ForegroundColor Red; exit 1 }
Write-Host 'MANIFESTCONSISTENTIE: ALLES PASS' -ForegroundColor Green
exit 0
