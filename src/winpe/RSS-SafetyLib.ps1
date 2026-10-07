<#
.SYNOPSIS
    RSS safety library: pure decision functions for the deployment.

.DESCRIPTION
    All safety decisions of RSS-Deploy.ps1 live in this library as
    pure functions: model and SKU detection, media recognition, target disk
    selection and artifact integrity. No function modifies a disk or file;
    every function stops with a terminating error as soon as a situation is
    not unambiguously safe.

    Fail-safe philosophy (see config/sources.json > diskSafety):
        UNKNOWN     = STOP
        AMBIGUOUS   = STOP
        UNSUPPORTED = STOP
        MISSING     = STOP
        INVALID     = STOP

    Because the functions are parameter-driven, the Pester tests in
    tests/ can mock every dangerous situation without ever touching real
    disks. The regexes, error messages and order are identical to the
    proven production logic; only the SKU allowlist (from the manifest)
    and the NVMe ambiguity check are new and strictly fail-safe.
#>

# ------------------------------------------------------------- manifest

function Get-RSSManifest {
    <# Reads the canonical manifest from the stick. MISSING = STOP. #>
    param(
        [Parameter(Mandatory)] [string]$Path
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "RSS manifest missing: $Path (expected sources.json in the root of the Images partition)"
    }
    $manifest = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($required in 'surfaceDriverPacks', 'windows', 'diskSafety') {
        if (-not $manifest.PSObject.Properties[$required]) {
            throw "RSS manifest is incomplete: section '$required' missing in $Path"
        }
    }
    foreach ($pack in $manifest.surfaceDriverPacks) {
        foreach ($required in 'profile', 'infCount', 'archiveSha256', 'cpuVendor', 'systemSku') {
            if (-not $pack.PSObject.Properties[$required]) {
                throw "RSS manifest is incomplete: driver pack without '$required'"
            }
        }
        if (@($pack.systemSku.supported).Count -eq 0) {
            throw "RSS manifest is incomplete: profile $($pack.profile) has no supported SystemSKUs"
        }
    }
    return $manifest
}

# ------------------------------------------------- model and SKU detection

function Get-RSSModelProfile {
    <#
        Detects the Surface model based on SMBIOS SystemProductName,
        SystemSKU and CPU vendor. Returns the manifest profile of the model.
        Every deviation is a terminating error (safe stop).

        Order is identical to the proven production logic:
        1. Snapdragon name refusal,
        2. strict regex routing on SystemProductName,
        3. unknown name -> STOP,
        4. CPU vendor check per profile,
        5. SystemSKU check against the allowlist/refusal list in the manifest.
    #>
    param(
        [Parameter(Mandatory)] [string]$SystemProductName,
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$SystemSku,
        [Parameter(Mandatory)] [string]$CpuVendor,
        [Parameter(Mandatory)] [object]$Manifest
    )

    if ($SystemProductName -match 'Snapdragon') {
        throw "ARM/Snapdragon model is not supported: $SystemProductName (SKU: $SystemSku)"
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
        throw "unsupported model: $SystemProductName (SKU: $SystemSku)"
    }

    if ($modelNumber -eq 4 -and $CpuVendor -ne 'AuthenticAMD') {
        throw "Surface Laptop 4 is not AMD: $CpuVendor"
    }
    if ($modelNumber -in 5, 6, 7, 8 -and $CpuVendor -ne 'GenuineIntel') {
        throw "Surface Laptop $modelNumber is not Intel: $CpuVendor"
    }
    if ($CpuVendor -notin 'AuthenticAMD', 'GenuineIntel') {
        throw "CPU architecture is not supported (ARM/other): $CpuVendor"
    }

    $modelProfile = $Manifest.surfaceDriverPacks |
        Where-Object { $_.profile -eq "SF$modelNumber" }
    if (-not $modelProfile) {
        throw "profile SF$modelNumber missing in the RSS manifest"
    }

    # SystemSKU check: UNKNOWN = STOP, UNSUPPORTED = STOP.
    $SystemSku = $SystemSku.Trim()
    if ([string]::IsNullOrWhiteSpace($SystemSku)) {
        throw "SystemSKU is empty or unreadable; model detection is not unambiguous (name: $SystemProductName)"
    }
    $supportedSkus = @($modelProfile.systemSku.supported)
    $refusedSkus = @($modelProfile.systemSku.refused)
    if ($refusedSkus -contains $SystemSku) {
        throw "SystemSKU $SystemSku is on the refusal list for SF$modelNumber ($($modelProfile.product))"
    }
    if ($supportedSkus -notcontains $SystemSku) {
        throw "SystemSKU $SystemSku is unknown for SF$modelNumber; update config/sources.json after verification"
    }

    return $modelProfile
}

# ------------------------------------------------------- media recognition

function Resolve-RSSMediaRoot {
    <#
        Finds exactly one RSS data partition using the recognition paths
        SF4 + SF8 install.esd. Zero or multiple candidates = STOP (AMBIGUOUS).
        $DriveRoots is the list of root paths (e.g. 'C:\', 'D:\') of the
        available filesystem drives.
    #>
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]]$DriveRoots
    )
    $candidates = @($DriveRoots | Where-Object {
        (Test-Path -LiteralPath (Join-Path $_ 'RSSSetup\SF4\sources\install.esd')) -and
        (Test-Path -LiteralPath (Join-Path $_ 'RSSSetup\SF8\sources\install.esd'))
    })
    if ($candidates.Count -ne 1) {
        throw "expected exactly one RSS data partition, found: $($candidates.Count)"
    }
    return $candidates[0].TrimEnd('\', '/')
}

# ----------------------------------------------------- target disk selection

function Select-RSSTargetDisk {
    <#
        Chooses and validates the internal target disk. Only exactly one
        internal NVMe disk that happens to be Disk 0 qualifies.
        The USB data partition may never be Disk 0 and never the target disk.
    #>
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]]$Disks,
        [Parameter(Mandatory)] [int]$MediaDiskNumber
    )
    if ($MediaDiskNumber -eq 0) {
        throw 'USB data partition is on Disk 0'
    }

    $disk0 = $Disks | Where-Object { $_.Number -eq 0 }
    $nvme = @($Disks | Where-Object { $_.BusType -eq 'NVMe' })

    if ($nvme.Count -eq 0) {
        $busType = if ($disk0) { $disk0.BusType } else { 'unknown' }
        throw "Disk 0 is not NVMe but $busType"
    }
    if ($nvme.Count -gt 1) {
        throw "multiple internal NVMe disks found (Disk $(($nvme | ForEach-Object Number) -join ', Disk ')); target disk is ambiguous"
    }
    $target = $nvme[0]
    if ($target.Number -eq $MediaDiskNumber) {
        throw 'target disk and USB are the same physical disk'
    }
    if ($target.Number -ne 0) {
        throw "internal NVMe disk is Disk $($target.Number), not Disk 0; target disk is ambiguous"
    }
    return $target
}

# --------------------------------------------------- artifact integrity

function Test-RSSArtifactHash {
    <#
        Checks the SHA-256 of a file against the manifest before anything
        destructive happens. MISSING/INVALID = STOP.
    #>
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$ExpectedSha256,
        [Parameter(Mandatory)] [string]$Label
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$Label missing: $Path"
    }
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($actual -ne $ExpectedSha256) {
        throw "$Label does not match the manifest (hash mismatch): expected $ExpectedSha256, found $actual"
    }
}
