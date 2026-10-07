<#
.SYNOPSIS
    RSS-veiligheidsbibliotheek: pure beslisfuncties voor de deployment.

.DESCRIPTION
    Alle veiligheidsbeslissingen van RSS-Deploy.ps1 staan in deze library als
    pure functies: model- en SKU-detectie, mediaherkenning, doelschijfselectie
    en artefactintegriteit. Geen enkele functie wijzigt een disk of bestand;
    elke functie stopt met een terminating error zodra een situatie niet
    ondubbelzinnig veilig is.

    Faalveilige filosofie (zie config/sources.json > diskSafety):
        UNKNOWN     = STOP
        AMBIGUOUS   = STOP
        UNSUPPORTED = STOP
        MISSING     = STOP
        INVALID     = STOP

    Omdat de functies parametergestuurd zijn, kunnen de Pester-tests in
    tests/ elke gevaarlijke situatie mocken zonder ooit echte disks aan
    te raken. De regexes, foutmeldingen en volgorde zijn identiek aan de
    bewezen productielogica; alleen de SKU-allowlist (uit het manifest)
    en de NVMe-eenduidigheidscontrole zijn nieuw en strikt faalveilig.
#>

# ------------------------------------------------------------- manifest

function Get-RSSManifest {
    <# Leest het canonical manifest van de stick. MISSING = STOP. #>
    param(
        [Parameter(Mandatory)] [string]$Path
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "RSS-manifest ontbreekt: $Path (verwacht sources.json in de wortel van de Images-partitie)"
    }
    $manifest = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($required in 'surfaceDriverPacks', 'windows', 'diskSafety') {
        if (-not $manifest.PSObject.Properties[$required]) {
            throw "RSS-manifest is incompleet: sectie '$required' ontbreekt in $Path"
        }
    }
    foreach ($pack in $manifest.surfaceDriverPacks) {
        foreach ($required in 'profile', 'infCount', 'archiveSha256', 'cpuVendor', 'systemSku') {
            if (-not $pack.PSObject.Properties[$required]) {
                throw "RSS-manifest is incompleet: driverpakket zonder '$required'"
            }
        }
        if (@($pack.systemSku.supported).Count -eq 0) {
            throw "RSS-manifest is incompleet: profiel $($pack.profile) heeft geen supported SystemSKU's"
        }
    }
    return $manifest
}

# ------------------------------------------------- model- en SKU-detectie

function Get-RSSModelProfile {
    <#
        Detecteert het Surface-model op basis van SMBIOS SystemProductName,
        SystemSKU en CPU-vendor. Levert het manifestprofiel van het model op.
        Elke afwijking is een terminating error (veilige stop).

        Volgorde is identiek aan de bewezen productielogica:
        1. Snapdragon-naamweigering,
        2. strikte regex-routering op SystemProductName,
        3. onbekende naam -> STOP,
        4. CPU-vendorcontrole per profiel,
        5. SystemSKU-controle tegen de allowlist/refuselist in het manifest.
    #>
    param(
        [Parameter(Mandatory)] [string]$SystemProductName,
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$SystemSku,
        [Parameter(Mandatory)] [string]$CpuVendor,
        [Parameter(Mandatory)] [object]$Manifest
    )

    if ($SystemProductName -match 'Snapdragon') {
        throw "ARM/Snapdragon-model wordt niet ondersteund: $SystemProductName (SKU: $SystemSku)"
    }

    $modelNumber = switch -Regex ($SystemProductName) {
        '^(?:Microsoft )?Surface Laptop 4$' { 4; break }
        '^(?:Microsoft )?Surface Laptop 5$' { 5; break }
        '^(?:Microsoft )?Surface Laptop 6(?: for Business)?$' { 6; break }
        '^(?:Microsoft )?Surface Laptop(?: for Business)?,? 7(?:th Edition)?(?: with Intel)?$' { 7; break }
        '^(?:Microsoft )?Surface Laptop for Business (?:13\.8in |15in )?8th Ed(?:ition)?(?: with)? Intel$' { 8; break }
        default { $null }
    }
    if (-not $modelNumber) {
        throw "niet-ondersteund model: $SystemProductName (SKU: $SystemSku)"
    }

    if ($modelNumber -eq 4 -and $CpuVendor -ne 'AuthenticAMD') {
        throw "Surface Laptop 4 is niet AMD: $CpuVendor"
    }
    if ($modelNumber -in 5, 6, 7, 8 -and $CpuVendor -ne 'GenuineIntel') {
        throw "Surface Laptop $modelNumber is niet Intel: $CpuVendor"
    }
    if ($CpuVendor -notin 'AuthenticAMD', 'GenuineIntel') {
        throw "CPU-architectuur wordt niet ondersteund (ARM/overig): $CpuVendor"
    }

    $modelProfile = $Manifest.surfaceDriverPacks |
        Where-Object { $_.profile -eq "SF$modelNumber" }
    if (-not $modelProfile) {
        throw "profiel SF$modelNumber ontbreekt in het RSS-manifest"
    }

    # SystemSKU-controle: UNKNOWN = STOP, UNSUPPORTED = STOP.
    $SystemSku = $SystemSku.Trim()
    if ([string]::IsNullOrWhiteSpace($SystemSku)) {
        throw "SystemSKU is leeg of onleesbaar; modeldetectie is niet eenduidig (naam: $SystemProductName)"
    }
    $supportedSkus = @($modelProfile.systemSku.supported)
    $refusedSkus = @($modelProfile.systemSku.refused)
    if ($refusedSkus -contains $SystemSku) {
        throw "SystemSKU $SystemSku staat op de weigerlijst voor SF$modelNumber ($($modelProfile.product))"
    }
    if ($supportedSkus -notcontains $SystemSku) {
        throw "SystemSKU $SystemSku is onbekend voor SF$modelNumber; werk config/sources.json bij na verificatie"
    }

    return $modelProfile
}

# ------------------------------------------------------- mediaherkenning

function Resolve-RSSMediaRoot {
    <#
        Vindt exact één RSS-datapartitie aan de hand van de herkenningspaden
        SF4 + SF8 install.esd. Nul of meerdere kandidaten = STOP (AMBIGUOUS).
        $DriveRoots is de lijst met wortelpaden (bijv. 'C:\', 'D:\') van de
        beschikbare filesystem-drives.
    #>
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]]$DriveRoots
    )
    $candidates = @($DriveRoots | Where-Object {
        (Test-Path -LiteralPath (Join-Path $_ 'RSSSetup\SF4\sources\install.esd')) -and
        (Test-Path -LiteralPath (Join-Path $_ 'RSSSetup\SF8\sources\install.esd'))
    })
    if ($candidates.Count -ne 1) {
        throw "verwacht exact een RSS-datapartitie, gevonden: $($candidates.Count)"
    }
    return $candidates[0].TrimEnd('\', '/')
}

# ----------------------------------------------------- doelschijfselectie

function Select-RSSTargetDisk {
    <#
        Kiest en valideert de interne doelschijf. Uitsluitend precies één
        interne NVMe-schijf die toevallig Disk 0 is, komt in aanmerking.
        De USB-datapartitie mag nooit Disk 0 en nooit de doelschijf zijn.
    #>
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]]$Disks,
        [Parameter(Mandatory)] [int]$MediaDiskNumber
    )
    if ($MediaDiskNumber -eq 0) {
        throw 'USB-datapartitie bevindt zich op Disk 0'
    }

    $disk0 = $Disks | Where-Object { $_.Number -eq 0 }
    $nvme = @($Disks | Where-Object { $_.BusType -eq 'NVMe' })

    if ($nvme.Count -eq 0) {
        $busType = if ($disk0) { $disk0.BusType } else { 'onbekend' }
        throw "Disk 0 is geen NVMe maar $busType"
    }
    if ($nvme.Count -gt 1) {
        throw "meerdere interne NVMe-schijven gevonden (Disk $(($nvme | ForEach-Object Number) -join ', Disk ')); doelschijf is niet eenduidig"
    }
    $target = $nvme[0]
    if ($target.Number -eq $MediaDiskNumber) {
        throw 'doelschijf en USB zijn dezelfde fysieke disk'
    }
    if ($target.Number -ne 0) {
        throw "interne NVMe-schijf is Disk $($target.Number), niet Disk 0; doelschijf is niet eenduidig"
    }
    return $target
}

# --------------------------------------------------- artefactintegriteit

function Test-RSSArtifactHash {
    <#
        Controleert SHA-256 van een bestand tegen het manifest vóórdat er ook
        maar iets destructiefs gebeurt. MISSING/INVALID = STOP.
    #>
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$ExpectedSha256,
        [Parameter(Mandatory)] [string]$Label
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$Label ontbreekt: $Path"
    }
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($actual -ne $ExpectedSha256) {
        throw "$Label komt niet overeen met het manifest (hash-wijkt-af): verwacht $ExpectedSha256, gevonden $actual"
    }
}
