<#
.SYNOPSIS
    Pester guardrail tests for the RSS destructive safety logic.

.DESCRIPTION
    Tests only the pure decision functions from src/winpe/RSS-SafetyLib.ps1 with
    fixed disks, SKUs and hashes. A real disk, partition or file outside the
    temporary test environment is NEVER touched.

    Covered hazard matrix (STOP = terminating error):
        supported model + valid media            => proceeds
        unsupported model                        => STOP
        unknown/empty SystemSKU                  => STOP
        unknown SKU for a known model            => STOP
        SF7 5G variant (SKU _2119)               => STOP
        SF8 Snapdragon SKU                       => STOP
        ARM/Snapdragon name                      => STOP
        CPU/platform mismatch                    => STOP
        no internal NVMe target disk             => STOP
        multiple internal NVMe disks             => STOP
        NVMe not on Disk 0                       => STOP
        USB data partition on Disk 0             => STOP
        USB looks like the target disk           => STOP
        zero or multiple data partitions         => STOP
        driver archive/image missing             => STOP
        hash mismatch                            => STOP
        manifest missing/incomplete              => STOP

    Running (Windows, PowerShell 5.1 or 7+):
        Invoke-Pester -Path tests

    In CI: see .github/workflows/validate.yml (ubuntu, Pester preinstalled).
#>
[CmdletBinding()]
param()

BeforeAll {
    . (Join-Path $PSScriptRoot '..\src\winpe\RSS-SafetyLib.ps1')
    $script:manifestPath = Join-Path $PSScriptRoot '..\config\sources.json'
    $script:manifest = Get-RSSManifest -Path $script:manifestPath

    function New-FakeDisk {
        param([int]$Number, [string]$BusType, [string]$FriendlyName)
        [pscustomobject]@{
            Number       = $Number
            BusType      = $BusType
            FriendlyName = if ($FriendlyName) { $FriendlyName } else { "Fake $BusType $Number" }
            Size         = 512GB
        }
    }
}

Describe 'Manifest integrity (config/sources.json)' {

    It 'loads the canonical manifest without errors' {
        { Get-RSSManifest -Path $script:manifestPath } | Should -Not -Throw
    }

    It 'stops when the manifest is missing (MISSING = STOP)' {
        { Get-RSSManifest -Path (Join-Path $TestDrive 'does-not-exist.json') } |
            Should -Throw '*RSS manifest missing*'
    }

    It 'stops on an incomplete manifest without surfaceDriverPacks (INVALID = STOP)' {
        $path = Join-Path $TestDrive 'incomplete.json'
        '{"windows": {}, "diskSafety": {}}' | Set-Content -LiteralPath $path
        { Get-RSSManifest -Path $path } | Should -Throw '*incomplete*surfaceDriverPacks*'
    }

    It 'stops on a profile without supported SystemSKU (INVALID = STOP)' {
        $path = Join-Path $TestDrive 'profile-incomplete.json'
        @'
{
  "windows": {},
  "diskSafety": {},
  "surfaceDriverPacks": [
    { "profile": "SF9", "infCount": 10, "archiveSha256": "X", "cpuVendor": "GenuineIntel", "systemSku": { "supported": [] } }
  ]
}
'@ | Set-Content -LiteralPath $path
        { Get-RSSManifest -Path $path } | Should -Throw '*no supported SystemSKU*'
    }

    It 'has exactly the same INF count per profile in manifest and test reference' {
        # Cross-check: the manifest is the single source of INF counts.
        $expected = @{ SF4 = 78; SF5 = 112; SF6 = 116; SF7 = 119; SF8 = 120 }
        foreach ($pack in $script:manifest.surfaceDriverPacks) {
            $pack.infCount | Should -Be $expected[$pack.profile] -Because "$($pack.profile) INF count must match the counted production reference"
        }
    }
}

Describe 'Model detection (Get-RSSModelProfile)' {

    Context 'supported combinations (data-driven across the whole manifest)' {

        It 'accepts every documented SMBIOS name + supported SKU per profile' {
            foreach ($pack in $script:manifest.surfaceDriverPacks) {
                foreach ($name in @($pack.smbiosProductNames)) {
                    foreach ($sku in @($pack.systemSku.supported)) {
                        $result = Get-RSSModelProfile -SystemProductName $name -SystemSku $sku -CpuVendor $pack.cpuVendor -Manifest $script:manifest
                        $result.profile | Should -Be $pack.profile -Because "name '$name' with SKU '$sku' belongs to $($pack.profile)"
                    }
                }
            }
        }

        It 'returns the correct INF count from the manifest per profile' {
            foreach ($pack in $script:manifest.surfaceDriverPacks) {
                $result = Get-RSSModelProfile `
                    -SystemProductName $pack.smbiosProductNames[0] `
                    -SystemSku $pack.systemSku.supported[0] `
                    -CpuVendor $pack.cpuVendor `
                    -Manifest $script:manifest
                [int]$result.infCount | Should -Be $pack.infCount -Because "INF count of $($pack.profile) must come from the manifest"
            }
        }
    }

    Context 'dangerous or uncertain situations (all STOP)' {

        It 'rejects an unknown model (UNSUPPORTED = STOP)' {
            { Get-RSSModelProfile -SystemProductName 'Surface Book 3' -SystemSku 'Surface_Book_3_1900' -CpuVendor 'GenuineIntel' -Manifest $script:manifest } |
                Should -Throw '*unsupported model*'
        }

        It 'rejects a completely foreign name (UNKNOWN = STOP)' {
            { Get-RSSModelProfile -SystemProductName 'FactoryX Laptop 9000' -SystemSku 'X9000' -CpuVendor 'GenuineIntel' -Manifest $script:manifest } |
                Should -Throw '*unsupported model*'
        }

        It 'rejects Snapdragon in the model name (UNSUPPORTED = STOP)' {
            { Get-RSSModelProfile -SystemProductName 'Surface Laptop 7th Edition (Snapdragon)' -SystemSku 'Surface_Laptop_7th_Edition_For_Business_2036' -CpuVendor 'GenuineIntel' -Manifest $script:manifest } |
                Should -Throw '*Snapdragon*'
        }

        It 'rejects Surface Laptop 4 with Intel CPU (CPU mismatch = STOP)' {
            { Get-RSSModelProfile -SystemProductName 'Surface Laptop 4' -SystemSku 'Surface_Laptop_4_1958:1959' -CpuVendor 'GenuineIntel' -Manifest $script:manifest } |
                Should -Throw '*not AMD*'
        }

        It 'rejects Surface Laptop 6 with AMD CPU (CPU mismatch = STOP)' {
            { Get-RSSModelProfile -SystemProductName 'Surface Laptop 6 for Business' -SystemSku 'Surface_Laptop_6_for_Business_2033' -CpuVendor 'AuthenticAMD' -Manifest $script:manifest } |
                Should -Throw '*not Intel*'
        }

        It 'rejects Surface Laptop 8 with non-x64 CPU vendor (PLATFORM mismatch = STOP)' {
            { Get-RSSModelProfile -SystemProductName 'Surface Laptop for Business 13.8in 8th Ed Intel' -SystemSku 'Surface_Laptop_for_Business_13_8in_8th_Ed_Intel_2107' -CpuVendor 'ARM Ltd' -Manifest $script:manifest } |
                Should -Throw '*not Intel*'
        }

        It 'stops on an empty SystemSKU (UNKNOWN = STOP)' {
            { Get-RSSModelProfile -SystemProductName 'Surface Laptop 6 for Business' -SystemSku '' -CpuVendor 'GenuineIntel' -Manifest $script:manifest } |
                Should -Throw '*SystemSKU is empty*'
        }

        It 'stops on an unknown SKU for a known model (UNKNOWN = STOP)' {
            { Get-RSSModelProfile -SystemProductName 'Surface Laptop 6 for Business' -SystemSku 'Surface_Laptop_6_for_Business_9999' -CpuVendor 'GenuineIntel' -Manifest $script:manifest } |
                Should -Throw '*unknown for SF6*'
        }

        It 'rejects the SF7 5G variant via the refusal list (UNSUPPORTED = STOP)' {
            { Get-RSSModelProfile -SystemProductName 'Surface Laptop for Business 7th Edition with Intel' -SystemSku 'Surface_Laptop_5G_7th_Edition_With_Intel_For_Business_2119' -CpuVendor 'GenuineIntel' -Manifest $script:manifest } |
                Should -Throw '*refusal list*'
        }

        It 'rejects the SF8 Snapdragon SKU even when the name suggests Intel (defense in depth)' {
            { Get-RSSModelProfile -SystemProductName 'Surface Laptop for Business 13.8in 8th Ed Intel' -SystemSku 'Surface_Laptop_for_Business_13_8in_8th_Ed_Snapdragon_2036' -CpuVendor 'GenuineIntel' -Manifest $script:manifest } |
                Should -Throw '*refusal list*'
        }

        It 'rejects a consumer SKU of the 7th Edition without For_Business' {
            { Get-RSSModelProfile -SystemProductName 'Surface Laptop 7th Edition' -SystemSku 'Surface_Laptop_7th_Edition_2036' -CpuVendor 'GenuineIntel' -Manifest $script:manifest } |
                Should -Throw '*unknown for SF7*'
        }
    }
}

Describe 'Media recognition (Resolve-RSSMediaRoot)' {

    It 'finds exactly the single RSS data partition (case: supported model + valid media)' {
        $caseRoot = Join-Path $TestDrive 'valid'
        $roots = @('c', 'd', 'x') | ForEach-Object {
            $root = Join-Path $caseRoot $_
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            $root
        }
        foreach ($mediaProfile in 'SF4', 'SF8') {
            $file = Join-Path $roots[1] "RSSSetup/$mediaProfile/sources/install.esd"
            New-Item -ItemType Directory -Path (Split-Path $file -Parent) -Force | Out-Null
            Set-Content -LiteralPath $file -Value 'test'
        }
        Resolve-RSSMediaRoot -DriveRoots $roots | Should -Be $roots[1].TrimEnd([char]92, [char]47)
    }

    It 'stops on zero candidate data partitions (AMBIGUOUS = STOP)' {
        $caseRoot = Join-Path $TestDrive 'zero'
        $roots = @('c', 'd') | ForEach-Object {
            $root = Join-Path $caseRoot $_
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            $root
        }
        { Resolve-RSSMediaRoot -DriveRoots $roots } | Should -Throw '*found: 0*'
    }

    It 'stops on multiple candidate data partitions (AMBIGUOUS = STOP)' {
        $caseRoot = Join-Path $TestDrive 'multiple'
        $roots = @('c', 'd', 'e') | ForEach-Object {
            $root = Join-Path $caseRoot $_
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            foreach ($mediaProfile in 'SF4', 'SF8') {
                $file = Join-Path $root "RSSSetup/$mediaProfile/sources/install.esd"
                New-Item -ItemType Directory -Path (Split-Path $file -Parent) -Force | Out-Null
                Set-Content -LiteralPath $file -Value 'test'
            }
            $root
        }
        { Resolve-RSSMediaRoot -DriveRoots $roots } | Should -Throw '*found: 3*'
    }

    It 'stops when only the SF4 image is present and SF8 is missing (incomplete media)' {
        $root = Join-Path $TestDrive 'incomplete/d'
        $file = Join-Path $root 'RSSSetup/SF4/sources/install.esd'
        New-Item -ItemType Directory -Path (Split-Path $file -Parent) -Force | Out-Null
        Set-Content -LiteralPath $file -Value 'test'
        { Resolve-RSSMediaRoot -DriveRoots @($root) } | Should -Throw '*found: 0*'

    }
}

Describe 'Target disk selection (Select-RSSTargetDisk)' {

    It 'chooses the single internal NVMe on Disk 0 with USB on Disk 1 (normal case)' {
        $disks = @((New-FakeDisk 1 'USB'), (New-FakeDisk 0 'NVMe' 'Internal SSD'))
        $target = Select-RSSTargetDisk -Disks $disks -MediaDiskNumber 1
        $target.Number | Should -Be 0
        $target.BusType | Should -Be 'NVMe'
    }

    It 'stops when there is no disk at all (no internal target disk = STOP)' {
        { Select-RSSTargetDisk -Disks @() -MediaDiskNumber 1 } |
            Should -Throw '*Disk 0 is not NVMe*'
    }

    It 'stops when Disk 0 is not NVMe but USB (INVALID = STOP)' {
        $disks = @((New-FakeDisk 0 'USB'), (New-FakeDisk 1 'NVMe'))
        { Select-RSSTargetDisk -Disks $disks -MediaDiskNumber 0 } |
            Should -Throw '*USB data partition is on Disk 0*'
    }

    It 'stops when Disk 0 is SATA (INVALID = STOP)' {
        $disks = @(New-FakeDisk 0 'SATA')
        { Select-RSSTargetDisk -Disks $disks -MediaDiskNumber 1 } |
            Should -Throw '*Disk 0 is not NVMe but SATA*'
    }

    It 'stops on multiple internal NVMe disks (multiple plausible targets = STOP)' {
        $disks = @((New-FakeDisk 1 'USB'), (New-FakeDisk 0 'NVMe' 'NVMe A'), (New-FakeDisk 2 'NVMe' 'NVMe B'))
        { Select-RSSTargetDisk -Disks $disks -MediaDiskNumber 1 } |
            Should -Throw '*multiple internal NVMe disks*'
    }

    It 'stops when the only NVMe is not Disk 0 (target disk ambiguous = STOP)' {
        $disks = @((New-FakeDisk 0 'SATA'), (New-FakeDisk 1 'USB'), (New-FakeDisk 2 'NVMe'))
        { Select-RSSTargetDisk -Disks $disks -MediaDiskNumber 1 } |
            Should -Throw '*not Disk 0*ambiguous*'
    }

    It 'stops when the target disk and USB are the same physical disk (deployment USB looks like the target = STOP)' {
        $disks = @(New-FakeDisk 1 'NVMe')
        { Select-RSSTargetDisk -Disks $disks -MediaDiskNumber 1 } |
            Should -Throw '*the same physical disk*'
    }
}

Describe 'Artifact integrity (Test-RSSArtifactHash)' {

    It 'stops when the file is missing (driver archive missing = STOP)' {
        Mock Test-Path { $false }
        { Test-RSSArtifactHash -Path 'D:\RSSDriverArchives\SF6.esd' -ExpectedSha256 'ABCD' -Label 'Driver archive SF6' } |
            Should -Throw '*missing*'
    }

    It 'stops when the Windows image is missing (Windows image missing = STOP)' {
        Mock Test-Path { $false }
        { Test-RSSArtifactHash -Path 'D:\RSSSetup\SF6\sources\install.esd' -ExpectedSha256 'ABCD' -Label 'Windows image SF6' } |
            Should -Throw '*missing*'
    }

    It 'stops on a hash mismatch (INVALID = STOP)' {
        Mock Test-Path { $true }
        Mock Get-FileHash { [pscustomobject]@{ Hash = 'DEAD0000' } }
        { Test-RSSArtifactHash -Path 'D:\x.esd' -ExpectedSha256 'ABCD0000' -Label 'Test' } |
            Should -Throw '*hash mismatch*'
    }

    It 'proceeds on a matching hash' {
        Mock Test-Path { $true }
        Mock Get-FileHash { [pscustomobject]@{ Hash = 'ABCD0000' } }
        { Test-RSSArtifactHash -Path 'D:\x.esd' -ExpectedSha256 'ABCD0000' -Label 'Test' } | Should -Not -Throw
    }
}
