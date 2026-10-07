<#
.SYNOPSIS
    Trial-extraction test of the RSS driver archives (SFx-Official-Drivers.esd).

.DESCRIPTION
    Trial-extracts each archive in the manifest with wimlib and checks the
    exact INF count against config/sources.json. The manifest is the single
    source of INF counts; this script no longer contains any counts itself.

    Read-only mode: this script writes exclusively to a temporary stage
    directory and removes it afterwards. Production files are not modified.

.PARAMETER Root
    Directory containing the archives (default: the directory of this script,
    as in the original build workflow).

.PARAMETER WimlibPath
    Path to wimlib-imagex.exe.

.PARAMETER ManifestPath
    Path to config/sources.json (default: <repo>\config\sources.json).

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
        throw "archive missing: $archive"
    }
    if (Test-Path -LiteralPath $stage) {
        Remove-Item -LiteralPath $stage -Recurse -Force
    }
    New-Item -ItemType Directory -Path $stage | Out-Null
    & $WimlibPath apply $archive 1 $stage --check
    if ($LASTEXITCODE -ne 0) {
        throw "wimlib test $($pack.profile) failed: $LASTEXITCODE"
    }
    $actualInf = @(Get-ChildItem -LiteralPath $stage -Recurse -File -Filter '*.inf').Count
    if ($actualInf -ne $pack.infCount) {
        throw "INF check $($pack.profile): $actualInf instead of $($pack.infCount)"
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
