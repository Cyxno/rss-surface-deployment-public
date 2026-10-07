<#
.SYNOPSIS
    Proefuitpaktest van de RSS-driverarchieven (SFx-Official-Drivers.esd).

.DESCRIPTION
    Pakt elk archief in het manifest proefmatig uit met wimlib en controleert
    het exacte INF-aantal tegen config/sources.json. Het manifest is de enige
    bron van INF-aantallen; dit script bevat zelf geen aantallen meer.

    Leesmodus: dit script schrijft uitsluitend in een tijdelijke stage-map en
    verwijdert die na afloop. Produktiebestanden worden niet gewijzigd.

.PARAMETER Root
    Map met de archieven (standaard: de map van dit script, zoals in de
    oorspronkelijke buildworkflow).

.PARAMETER WimlibPath
    Pad naar wimlib-imagex.exe.

.PARAMETER ManifestPath
    Pad naar config/sources.json (standaard: <repo>\config\sources.json).

.EXAMPLE
    .\Test-DriverArchives.ps1 -Root D:\RSS-Build\archives -WimlibPath D:\RSS-Build\wimlib\wimlib-imagex.exe
#>
[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $MyInvocation.MyCommand.Path),
    [string]$WimlibPath = (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'wimlib\wimlib-imagex.exe'),
    [string]$ManifestPath
)

$ErrorActionPreference = 'Stop'
if (-not $ManifestPath) {
    $ManifestPath = Join-Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) 'config\sources.json'
}
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$stage = Join-Path $Root 'DriverArchive-DISM-Test'

$results = foreach ($pack in $manifest.surfaceDriverPacks) {
    $archive = Join-Path $Root "$($pack.profile)-Official-Drivers.esd"
    if (-not (Test-Path -LiteralPath $archive)) {
        throw "archief ontbreekt: $archive"
    }
    if (Test-Path -LiteralPath $stage) {
        Remove-Item -LiteralPath $stage -Recurse -Force
    }
    New-Item -ItemType Directory -Path $stage | Out-Null
    & $WimlibPath apply $archive 1 $stage --check
    if ($LASTEXITCODE -ne 0) {
        throw "wimlib-test $($pack.profile) mislukt: $LASTEXITCODE"
    }
    $actualInf = @(Get-ChildItem -LiteralPath $stage -Recurse -File -Filter '*.inf').Count
    if ($actualInf -ne $pack.infCount) {
        throw "INF-controle $($pack.profile): $actualInf in plaats van $($pack.infCount)"
    }
    [pscustomobject]@{
        Profile    = $pack.profile
        ExpectedInf = $pack.infCount
        ActualInf  = $actualInf
        Result     = 'OK'
    }
}

if (Test-Path -LiteralPath $stage) {
    Remove-Item -LiteralPath $stage -Recurse -Force
}
$results | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Root 'DriverArchive-DISM-Test-result.json') -Encoding UTF8
