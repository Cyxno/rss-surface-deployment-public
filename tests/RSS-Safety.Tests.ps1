<#
.SYNOPSIS
    Pester-guardrailtests voor de RSS-destructieve veiligheidslogica.

.DESCRIPTION
    Test uitsluitend pure beslisfuncties uit src/winpe/RSS-SafetyLib.ps1 met
    gefixteerde disks, SKU's en hashes. Er wordt NOOIT een echte disk,
    partitie of bestand buiten de tijdelijke testomgeving aangeraakt.

    Gedekte gevarenmatrix (STOP = terminating error):
        supported model + geldige media          => doorgaat
        unsupported model                        => STOP
        unknown/lege SystemSKU                   => STOP
        onbekende SKU bij bekend model           => STOP
        SF7 5G-variant (SKU _2119)               => STOP
        SF8 Snapdragon-SKU                       => STOP
        ARM/Snapdragon-naam                      => STOP
        CPU/platform mismatch                    => STOP
        geen interne NVMe-doelschijf             => STOP
        meerdere interne NVMe-schijven           => STOP
        NVMe niet op Disk 0                      => STOP
        USB-datapartitie op Disk 0               => STOP
        USB lijkt doelschijf                     => STOP
        nul of meerdere datapartities            => STOP
        driverarchief/image ontbreekt            => STOP
        hash mismatch                            => STOP
        manifest ontbreekt/incompleet            => STOP

    Draaien (Windows, PowerShell 5.1 of 7+):
        Invoke-Pester -Path tests

    In CI: zie .github/workflows/validate.yml (ubuntu, Pester preinstalled).
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

Describe 'Manifest-integriteit (config/sources.json)' {

    It 'laadt het canonical manifest zonder fouten' {
        { Get-RSSManifest -Path $script:manifestPath } | Should -Not -Throw
    }

    It 'stopt wanneer het manifest ontbreekt (MISSING = STOP)' {
        { Get-RSSManifest -Path (Join-Path $TestDrive 'bestaat-niet.json') } |
            Should -Throw '*RSS-manifest ontbreekt*'
    }

    It 'stopt bij een incompleet manifest zonder surfaceDriverPacks (INVALID = STOP)' {
        $pad = Join-Path $TestDrive 'incompleet.json'
        '{"windows": {}, "diskSafety": {}}' | Set-Content -LiteralPath $pad
        { Get-RSSManifest -Path $pad } | Should -Throw '*incompleet*surfaceDriverPacks*'
    }

    It 'stopt bij een profiel zonder supported SystemSKU (INVALID = STOP)' {
        $pad = Join-Path $TestDrive 'profiel-incompleet.json'
        @'
{
  "windows": {},
  "diskSafety": {},
  "surfaceDriverPacks": [
    { "profile": "SF9", "infCount": 10, "archiveSha256": "X", "cpuVendor": "GenuineIntel", "systemSku": { "supported": [] } }
  ]
}
'@ | Set-Content -LiteralPath $pad
        { Get-RSSManifest -Path $pad } | Should -Throw '*geen supported SystemSKU*'
    }

    It 'heeft voor elk profiel exact dezelfde INF-count in manifest en testreferentie' {
        # Koppelingscontrole: het manifest is de enige bron van INF-aantallen.
        $verwacht = @{ SF4 = 78; SF5 = 112; SF6 = 116; SF7 = 119; SF8 = 120 }
        foreach ($pack in $script:manifest.surfaceDriverPacks) {
            $pack.infCount | Should -Be $verwacht[$pack.profile] -Because "$($pack.profile) INF-aantal moet overeenkomen met de getelde productiereferentie"
        }
    }
}

Describe 'Modeldetectie (Get-RSSModelProfile)' {

    Context 'ondersteunde combinaties (data-gedreven over het hele manifest)' {

        It 'accepteert elke gedocumenteerde SMBIOS-naam + supported SKU per profiel' {
            foreach ($pack in $script:manifest.surfaceDriverPacks) {
                foreach ($naam in @($pack.smbiosProductNames)) {
                    foreach ($sku in @($pack.systemSku.supported)) {
                        $result = Get-RSSModelProfile -SystemProductName $naam -SystemSku $sku -CpuVendor $pack.cpuVendor -Manifest $script:manifest
                        $result.profile | Should -Be $pack.profile -Because "naam '$naam' met SKU '$sku' hoort bij $($pack.profile)"
                    }
                }
            }
        }

        It 'geeft het juiste INF-aantal uit het manifest terug per profiel' {
            foreach ($pack in $script:manifest.surfaceDriverPacks) {
                $result = Get-RSSModelProfile `
                    -SystemProductName $pack.smbiosProductNames[0] `
                    -SystemSku $pack.systemSku.supported[0] `
                    -CpuVendor $pack.cpuVendor `
                    -Manifest $script:manifest
                [int]$result.infCount | Should -Be $pack.infCount -Because "INF-aantal van $($pack.profile) moet uit het manifest komen"
            }
        }
    }

    Context 'gevaarlijke of onzekere situaties (alles STOP)' {

        It 'weigert een onbekend model (UNSUPPORTED = STOP)' {
            { Get-RSSModelProfile -SystemProductName 'Surface Book 3' -SystemSku 'Surface_Book_3_1900' -CpuVendor 'GenuineIntel' -Manifest $script:manifest } |
                Should -Throw '*niet-ondersteund model*'
        }

        It 'weigert een volledig vreemde naam (UNKNOWN = STOP)' {
            { Get-RSSModelProfile -SystemProductName 'FabrieksX Laptop 9000' -SystemSku 'X9000' -CpuVendor 'GenuineIntel' -Manifest $script:manifest } |
                Should -Throw '*niet-ondersteund model*'
        }

        It 'weigert Snapdragon in de modelnaam (UNSUPPORTED = STOP)' {
            { Get-RSSModelProfile -SystemProductName 'Surface Laptop 7th Edition (Snapdragon)' -SystemSku 'Surface_Laptop_7th_Edition_For_Business_2036' -CpuVendor 'GenuineIntel' -Manifest $script:manifest } |
                Should -Throw '*Snapdragon*'
        }

        It 'weigert Surface Laptop 4 met Intel-CPU (CPU mismatch = STOP)' {
            { Get-RSSModelProfile -SystemProductName 'Surface Laptop 4' -SystemSku 'Surface_Laptop_4_1958:1959' -CpuVendor 'GenuineIntel' -Manifest $script:manifest } |
                Should -Throw '*niet AMD*'
        }

        It 'weigert Surface Laptop 6 met AMD-CPU (CPU mismatch = STOP)' {
            { Get-RSSModelProfile -SystemProductName 'Surface Laptop 6 for Business' -SystemSku 'Surface_Laptop_6_for_Business_2033' -CpuVendor 'AuthenticAMD' -Manifest $script:manifest } |
                Should -Throw '*niet Intel*'
        }

        It 'weigert Surface Laptop 8 met niet-x64 CPU-vendor (PLATFORM mismatch = STOP)' {
            { Get-RSSModelProfile -SystemProductName 'Surface Laptop for Business 13.8in 8th Ed Intel' -SystemSku 'Surface_Laptop_for_Business_13_8in_8th_Ed_Intel_2107' -CpuVendor 'ARM Ltd' -Manifest $script:manifest } |
                Should -Throw '*niet Intel*'
        }

        It 'stopt bij een lege SystemSKU (UNKNOWN = STOP)' {
            { Get-RSSModelProfile -SystemProductName 'Surface Laptop 6 for Business' -SystemSku '' -CpuVendor 'GenuineIntel' -Manifest $script:manifest } |
                Should -Throw '*SystemSKU is leeg*'
        }

        It 'stopt bij een onbekende SKU bij een bekend model (UNKNOWN = STOP)' {
            { Get-RSSModelProfile -SystemProductName 'Surface Laptop 6 for Business' -SystemSku 'Surface_Laptop_6_for_Business_9999' -CpuVendor 'GenuineIntel' -Manifest $script:manifest } |
                Should -Throw '*onbekend voor SF6*'
        }

        It 'weigert de SF7 5G-variant via de weigerlijst (UNSUPPORTED = STOP)' {
            { Get-RSSModelProfile -SystemProductName 'Surface Laptop for Business 7th Edition with Intel' -SystemSku 'Surface_Laptop_5G_7th_Edition_With_Intel_For_Business_2119' -CpuVendor 'GenuineIntel' -Manifest $script:manifest } |
                Should -Throw '*weigerlijst*'
        }

        It 'weigert de SF8 Snapdragon-SKU ook als de naam Intel suggereert (defense in depth)' {
            { Get-RSSModelProfile -SystemProductName 'Surface Laptop for Business 13.8in 8th Ed Intel' -SystemSku 'Surface_Laptop_for_Business_13_8in_8th_Ed_Snapdragon_2036' -CpuVendor 'GenuineIntel' -Manifest $script:manifest } |
                Should -Throw '*weigerlijst*'
        }

        It 'weigert een consument-SKU van de 7th Edition zonder For_Business' {
            { Get-RSSModelProfile -SystemProductName 'Surface Laptop 7th Edition' -SystemSku 'Surface_Laptop_7th_Edition_2036' -CpuVendor 'GenuineIntel' -Manifest $script:manifest } |
                Should -Throw '*onbekend voor SF7*'
        }
    }
}

Describe 'Mediaherkenning (Resolve-RSSMediaRoot)' {

    It 'vindt exact de enige RSS-datapartitie (geval: supported model + geldige media)' {
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

    It 'stopt bij nul kandidaat-datapartities (AMBIGUOUS = STOP)' {
        $caseRoot = Join-Path $TestDrive 'zero'
        $roots = @('c', 'd') | ForEach-Object {
            $root = Join-Path $caseRoot $_
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            $root
        }
        { Resolve-RSSMediaRoot -DriveRoots $roots } | Should -Throw '*gevonden: 0*'
    }

    It 'stopt bij meerdere kandidaat-datapartities (AMBIGUOUS = STOP)' {
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
        { Resolve-RSSMediaRoot -DriveRoots $roots } | Should -Throw '*gevonden: 3*'
    }

    It 'stopt als alleen SF4-image aanwezig is en SF8 ontbreekt (incomplete media)' {
        $root = Join-Path $TestDrive 'incomplete/d'
        $file = Join-Path $root 'RSSSetup/SF4/sources/install.esd'
        New-Item -ItemType Directory -Path (Split-Path $file -Parent) -Force | Out-Null
        Set-Content -LiteralPath $file -Value 'test'
        { Resolve-RSSMediaRoot -DriveRoots @($root) } | Should -Throw '*gevonden: 0*'
    }
}

Describe 'Doelschijfselectie (Select-RSSTargetDisk)' {

    It 'kiest de enige interne NVMe op Disk 0 bij USB op Disk 1 (normaal geval)' {
        $disks = @((New-FakeDisk 1 'USB'), (New-FakeDisk 0 'NVMe' 'Interne SSD'))
        $target = Select-RSSTargetDisk -Disks $disks -MediaDiskNumber 1
        $target.Number | Should -Be 0
        $target.BusType | Should -Be 'NVMe'
    }

    It 'stopt als er helemaal geen disk is (geen interne target disk = STOP)' {
        { Select-RSSTargetDisk -Disks @() -MediaDiskNumber 1 } |
            Should -Throw '*Disk 0 is geen NVMe*'
    }

    It 'stopt als Disk 0 geen NVMe is maar USB (INVALID = STOP)' {
        $disks = @((New-FakeDisk 0 'USB'), (New-FakeDisk 1 'NVMe'))
        { Select-RSSTargetDisk -Disks $disks -MediaDiskNumber 0 } |
            Should -Throw '*USB-datapartitie bevindt zich op Disk 0*'
    }

    It 'stopt als Disk 0 SATA is (INVALID = STOP)' {
        $disks = @(New-FakeDisk 0 'SATA')
        { Select-RSSTargetDisk -Disks $disks -MediaDiskNumber 1 } |
            Should -Throw '*Disk 0 is geen NVMe maar SATA*'
    }

    It 'stopt bij meerdere interne NVMe-schijven (meerdere plausibele targets = STOP)' {
        $disks = @((New-FakeDisk 1 'USB'), (New-FakeDisk 0 'NVMe' 'NVMe A'), (New-FakeDisk 2 'NVMe' 'NVMe B'))
        { Select-RSSTargetDisk -Disks $disks -MediaDiskNumber 1 } |
            Should -Throw '*meerdere interne NVMe-schijven*'
    }

    It 'stopt als de enige NVMe niet Disk 0 is (doelschijf niet eenduidig = STOP)' {
        $disks = @((New-FakeDisk 0 'SATA'), (New-FakeDisk 1 'USB'), (New-FakeDisk 2 'NVMe'))
        { Select-RSSTargetDisk -Disks $disks -MediaDiskNumber 1 } |
            Should -Throw '*niet Disk 0*niet eenduidig*'
    }

    It 'stopt als de doelschijf en USB dezelfde fysieke disk zijn (deployment USB lijkt target = STOP)' {
        $disks = @(New-FakeDisk 1 'NVMe')
        { Select-RSSTargetDisk -Disks $disks -MediaDiskNumber 1 } |
            Should -Throw '*dezelfde fysieke disk*'
    }
}

Describe 'Artefactintegriteit (Test-RSSArtifactHash)' {

    It 'stopt als het bestand ontbreekt (driverarchief ontbreekt = STOP)' {
        Mock Test-Path { $false }
        { Test-RSSArtifactHash -Path 'D:\RSSDriverArchives\SF6.esd' -ExpectedSha256 'ABCD' -Label 'Driverarchief SF6' } |
            Should -Throw '*ontbreekt*'
    }

    It 'stopt bij een Windows-image dat ontbreekt (Windows image ontbreekt = STOP)' {
        Mock Test-Path { $false }
        { Test-RSSArtifactHash -Path 'D:\RSSSetup\SF6\sources\install.esd' -ExpectedSha256 'ABCD' -Label 'Windows-image SF6' } |
            Should -Throw '*ontbreekt*'
    }

    It 'stopt bij een hash mismatch (INVALID = STOP)' {
        Mock Test-Path { $true }
        Mock Get-FileHash { [pscustomobject]@{ Hash = 'DEAD0000' } }
        { Test-RSSArtifactHash -Path 'D:\x.esd' -ExpectedSha256 'ABCD0000' -Label 'Test' } |
            Should -Throw '*hash-wijkt-af*'
    }

    It 'gaat door bij een overeenkomende hash' {
        Mock Test-Path { $true }
        Mock Get-FileHash { [pscustomobject]@{ Hash = 'ABCD0000' } }
        { Test-RSSArtifactHash -Path 'D:\x.esd' -ExpectedSha256 'ABCD0000' -Label 'Test' } | Should -Not -Throw
    }
}
