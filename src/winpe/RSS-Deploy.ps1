$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Alle veiligheidsbeslissingen staan in RSS-SafetyLib.ps1 (zelfde map in boot.wim).
# Die library is puur en parametergestuurd zodat elke guardrail getest kan worden
# zonder ooit een echte disk aan te raken (zie tests/ in de repository).
. (Join-Path $PSScriptRoot 'RSS-SafetyLib.ps1')

function Set-RSSTheme {
    $Host.UI.RawUI.WindowTitle = "RSS - Surface Deployment Stick V2"
    $Host.UI.RawUI.BackgroundColor = 'Black'
    $Host.UI.RawUI.ForegroundColor = 'Gray'
    Clear-Host
}

function Show-RSSArt([ConsoleColor]$Color) {
    Write-Host '   ____  _____ ____  ' -ForegroundColor $Color
    Write-Host '  |  _ \|  ___/ ___| ' -ForegroundColor $Color
    Write-Host '  | |_) | |_ _\___ \ ' -ForegroundColor $Color
    Write-Host '  |  _ <|  _| ___) |' -ForegroundColor $Color
    Write-Host '  |_| \_\_| |____/ ' -ForegroundColor $Color
}

function Write-RSSType([string]$Text, [ConsoleColor]$Color) {
    foreach ($ch in $Text.ToCharArray()) {
        Write-Host $ch -NoNewline -ForegroundColor $Color
        Start-Sleep -Milliseconds 22
    }
    Write-Host ''
}

function Show-RSSTitleAnimation {
    $origin = $Host.UI.RawUI.CursorPosition
    try {
        $frames = [ConsoleColor[]]@('DarkGreen','Green','Cyan','White','Cyan','Green','Yellow','Green')
        foreach ($c in $frames) {
            [Console]::SetCursorPosition($origin.X, $origin.Y)
            Show-RSSArt $c
            Start-Sleep -Milliseconds 110
        }
    } catch {
        # console zonder cursorpositionering: val terug op het statische logo
    }
    Show-RSSArt 'Green'
}

function Show-RSSBanner([string]$Subtitle) {
    $Host.UI.RawUI.WindowTitle = "RSS - Surface Deployment Stick V2"
    $Host.UI.RawUI.BackgroundColor = 'Black'
    $Host.UI.RawUI.ForegroundColor = 'Gray'
    Clear-Host
    Write-Host ''
    Show-RSSTitleAnimation
    Write-Host '    ==================================================' -ForegroundColor DarkGreen
    Write-Host '    ' -NoNewline
    Write-RSSType "Surface Deployment Stick V2" 'Cyan'
    Write-Host '    ==================================================' -ForegroundColor DarkGreen
    if ($Subtitle) {
        Write-Host ("                       {0}" -f $Subtitle) -ForegroundColor Cyan
        Write-Host ''
    }
}

function Write-RSSStep([int]$Number, [int]$Total, [string]$Text) {
    Write-Host ''
    Write-Host ("  [{0}/{1}] " -f $Number, $Total) -NoNewline -ForegroundColor Green
    Write-Host $Text -ForegroundColor White
}

function Show-RSSCountdown([int]$Seconds, [string]$Text, [ConsoleColor]$Color = 'Yellow') {
    $frames = @('|', '/', '-', '\')
    for ($remaining = $Seconds; $remaining -ge 1; $remaining--) {
        $frame = $frames[($Seconds - $remaining) % $frames.Count]
        Write-Host ("`r  {0} {1} {2,2} seconden...   " -f $frame, $Text, $remaining) -NoNewline -ForegroundColor $Color
        Start-Sleep -Seconds 1
    }
    Write-Host "`r  [OK] $Text                         " -ForegroundColor Green
}

function Show-RSSSuccess([string]$Product, [int]$Model) {
    $Host.UI.RawUI.BackgroundColor = 'DarkGreen'
    $Host.UI.RawUI.ForegroundColor = 'White'
    Clear-Host
    Write-Host ''
    Show-RSSArt 'White'
    Write-Host "              Surface Deployment Stick V2" -ForegroundColor Yellow
    Write-Host '    ==================================================' -ForegroundColor White
    Write-Host ''
    Write-Host '                    INSTALLATIE GESLAAGD!' -ForegroundColor White
    Write-Host ''
    Write-Host "                  $Product / profiel SF$Model" -ForegroundColor White
    Write-Host ''
    Write-Host '       Windows, Surface-drivers en UEFI-boot zijn gereed.' -ForegroundColor White
    Write-Host '                     Verwijder de USB-stick.' -ForegroundColor White
    Write-Host ''
    Write-Host '       [' -NoNewline
    for ($i = 0; $i -lt 24; $i++) {
        Write-Host '#' -NoNewline -ForegroundColor Yellow
        Start-Sleep -Milliseconds 45
    }
    Write-Host ']' -ForegroundColor Yellow
    Show-RSSCountdown 15 'Automatische herstart over' White
}

function Stop-Safely([string]$Message) {
    $Host.UI.RawUI.BackgroundColor = 'DarkRed'
    $Host.UI.RawUI.ForegroundColor = 'White'
    Clear-Host
    Show-RSSBanner 'VEILIG GESTOPT'
    Write-Host "FOUT: $Message" -ForegroundColor White
    if ($script:Log) {
        "RESULT=FAILED-SAFE MESSAGE=$Message" | Add-Content -LiteralPath $script:Log -Encoding UTF8
    }
    Write-Host 'Houd de aan/uitknop ingedrukt om af te sluiten.'
    while ($true) { Start-Sleep -Seconds 30 }
}

function Invoke-Native([string]$FilePath, [string[]]$Arguments, [string]$Description) {
    "COMMAND=$FilePath $($Arguments -join ' ')" | Add-Content -LiteralPath $script:Log -Encoding UTF8
    & $FilePath @Arguments 2>&1 | Tee-Object -FilePath $script:Log -Append
    if ($LASTEXITCODE -ne 0) {
        throw "$Description mislukt met exitcode $LASTEXITCODE"
    }
}

try {
    Set-RSSTheme
    Show-RSSBanner 'Automatische Surface-installatie'
    Write-Host '  WinPE en deploymentmodules initialiseren...' -ForegroundColor Cyan
    Import-Module Storage -ErrorAction Stop
    Import-Module Dism -ErrorAction Stop

    $mediaRoot = Resolve-RSSMediaRoot -DriveRoots @(
        @(Get-PSDrive -PSProvider FileSystem | Where-Object DriveLetter | ForEach-Object Root)
    )
    $mediaLetter = $mediaRoot.Substring(0, 1)
    $script:Log = Join-Path $mediaRoot 'RSS-ADK-Deploy.log'
    "RSS ADK deployment - $(Get-Date -Format o)" | Set-Content -LiteralPath $script:Log -Encoding UTF8

    $manifest = Get-RSSManifest -Path (Join-Path $mediaRoot 'sources.json')

    $bios = Get-ItemProperty -LiteralPath 'HKLM:\HARDWARE\DESCRIPTION\System\BIOS'
    $product = $bios.SystemProductName
    $systemSku = $bios.SystemSKU
    $cpuVendor = (Get-ItemProperty -LiteralPath 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0' -Name VendorIdentifier).VendorIdentifier
    $modelProfile = Get-RSSModelProfile -SystemProductName $product -SystemSku $systemSku -CpuVendor $cpuVendor -Manifest $manifest
    $model = [int]($modelProfile.profile -replace '^SF', '')

    $setupRoot = Join-Path $mediaRoot "RSSSetup\SF$model"
    $image = Join-Path $setupRoot 'sources\install.esd'
    $driverArchive = Join-Path $mediaRoot "RSSDriverArchives\SF$model.esd"
    $expectedInf = [int]$modelProfile.infCount
    if (-not (Test-Path -LiteralPath $image)) { throw "image ontbreekt: $image" }
    if (-not (Test-Path -LiteralPath $driverArchive)) { throw "officieel driverarchief ontbreekt: $driverArchive" }
    if ((Get-Item -LiteralPath $driverArchive).Length -lt 1MB) { throw "driverarchief SF$model is onverwacht klein" }

    $mediaPartition = Get-Partition -DriveLetter $mediaLetter
    $mediaDisk = Get-Disk -Number $mediaPartition.DiskNumber
    $targetDisk = Select-RSSTargetDisk -Disks @(Get-Disk) -MediaDiskNumber $mediaDisk.Number

    "MODEL=$product SKU=$systemSku PROFILE=SF$model CPU=$cpuVendor" | Add-Content -LiteralPath $script:Log -Encoding UTF8
    "MANIFEST=$(Get-Content -LiteralPath (Join-Path $mediaRoot 'sources.json') -TotalCount 1 | Out-String) generated=$($manifest.generated) release=$($manifest.project.version)" | Add-Content -LiteralPath $script:Log -Encoding UTF8
    "MEDIA_DISK=$($mediaDisk.Number) $($mediaDisk.FriendlyName) BUS=$($mediaDisk.BusType)" | Add-Content -LiteralPath $script:Log -Encoding UTF8
    "TARGET_DISK=$($targetDisk.Number) $($targetDisk.FriendlyName) BUS=$($targetDisk.BusType) SIZE=$($targetDisk.Size)" | Add-Content -LiteralPath $script:Log -Encoding UTF8
    "IMAGE=$image DRIVERARCHIVE=$driverArchive EXPECTED_INF=$expectedInf" | Add-Content -LiteralPath $script:Log -Encoding UTF8
    Invoke-Native 'dism.exe' @('/English','/Get-WimInfo',"/WimFile:$driverArchive",'/Index:1') 'Driverarchief controleren'

    # Pre-destructieve integriteitscontrole: hash van image en driverarchief tegen
    # het manifest, vóórdat Disk 0 wordt aangeraakt (INVALID = STOP).
    Test-RSSArtifactHash -Path $image -ExpectedSha256 $manifest.windows.servicedImage.installEsdSha256 -Label "Windows-image SF$model"
    Test-RSSArtifactHash -Path $driverArchive -ExpectedSha256 $modelProfile.archiveSha256 -Label "Driverarchief SF$model"
    "HASHCHECK=image+driverarchief overeenkomstig manifest" | Add-Content -LiteralPath $script:Log -Encoding UTF8

    Clear-Host
    Show-RSSBanner 'Automatische Surface-installatie'
    Write-Host "  Model    : $product" -ForegroundColor White
    Write-Host "  SKU      : $systemSku" -ForegroundColor White
    Write-Host "  CPU      : $cpuVendor" -ForegroundColor White
    Write-Host "  Image    : SF$model - Windows 11 Pro" -ForegroundColor White
    Write-Host "  USB      : Disk $($mediaDisk.Number)" -ForegroundColor White
    Write-Host "  Doelschijf: Disk $($targetDisk.Number) - $($targetDisk.FriendlyName) (NVMe)" -ForegroundColor White
    Write-Host "  Drivers  : volledig officieel pakket ($expectedInf INF)" -ForegroundColor White
    Write-Host "  Integriteit: image en driverarchief geverifieerd" -ForegroundColor White
    Write-Host ''
    Write-Host '  LET OP: DISK 0 WORDT VOLLEDIG GEWIST!' -ForegroundColor White -BackgroundColor DarkRed
    Write-Host '  Schakel het apparaat uit tijdens de aftelling om te annuleren.' -ForegroundColor Yellow
    Show-RSSCountdown 15 'Installatie start over' Yellow

    Write-RSSStep 1 5 'Disk 0 als GPT indelen...'
    Set-Disk -Number 0 -IsOffline $false -ErrorAction SilentlyContinue
    Set-Disk -Number 0 -IsReadOnly $false -ErrorAction SilentlyContinue
    Clear-Disk -Number 0 -RemoveData -RemoveOEM -Confirm:$false
    Initialize-Disk -Number 0 -PartitionStyle GPT
    $efi = New-Partition -DiskNumber 0 -Size 260MB -GptType '{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}' -AssignDriveLetter
    Format-Volume -Partition $efi -FileSystem FAT32 -NewFileSystemLabel 'SYSTEM' -Confirm:$false -Force | Out-Null
    New-Partition -DiskNumber 0 -Size 16MB -GptType '{E3C9E316-0B5C-4DB8-817D-F92DF00215AE}' | Out-Null
    $windows = New-Partition -DiskNumber 0 -UseMaximumSize -GptType '{EBD0A0A2-B9E5-4433-87C0-68B6B72699C7}' -AssignDriveLetter
    Format-Volume -Partition $windows -FileSystem NTFS -NewFileSystemLabel 'Windows' -Confirm:$false -Force | Out-Null
    $windowsRoot = "$($windows.DriveLetter):\"
    $efiRoot = "$($efi.DriveLetter):"

    Write-RSSStep 2 5 'Windows 11 Pro-image toepassen...'
    Invoke-Native 'dism.exe' @('/English','/Apply-Image',"/ImageFile:$image",'/Index:1',"/ApplyDir:$windowsRoot",'/CheckIntegrity') 'Windows-image toepassen'
    if (-not (Test-Path -LiteralPath (Join-Path $windowsRoot 'Windows\System32\config\SYSTEM'))) { throw 'toegepaste Windows SYSTEM-hive ontbreekt' }

    Write-RSSStep 3 5 'Volledige officiele Surface-drivers installeren...'
    $driverStage = Join-Path $windowsRoot 'RSS-DriverStage'
    New-Item -ItemType Directory -Path $driverStage -Force | Out-Null
    Invoke-Native 'X:\Tools\wimlib-imagex.exe' @('apply',$driverArchive,'1',$driverStage,'--check') 'Driverarchief uitpakken'
    $sourceInf = @(Get-ChildItem -LiteralPath $driverStage -Recurse -File -Filter '*.inf')
    if ($sourceInf.Count -ne $expectedInf) { throw "uitgepakt SF$model-pakket bevat $($sourceInf.Count) INF in plaats van $expectedInf" }
    $before = @(Get-WindowsDriver -Path $windowsRoot -ErrorAction Stop).Count
    Add-WindowsDriver -Path $windowsRoot -Driver $driverStage -Recurse -ErrorAction Stop | Out-File -LiteralPath $script:Log -Append -Encoding UTF8
    $after = @(Get-WindowsDriver -Path $windowsRoot -ErrorAction Stop).Count
    "OFFICIAL_INF=$($sourceInf.Count) DRIVERSTORE_BEFORE=$before DRIVERSTORE_AFTER=$after" | Add-Content -LiteralPath $script:Log -Encoding UTF8
    if ($after -lt $before) { throw 'DriverStore-aantal is onverwacht afgenomen' }
    Remove-Item -LiteralPath $driverStage -Recurse -Force

    Write-RSSStep 4 5 'UEFI-opstartbestanden maken...'
    Invoke-Native 'bcdboot.exe' @((Join-Path $windowsRoot 'Windows'),'/s',$efiRoot,'/f','UEFI','/l','nl-NL') 'BCDBoot'
    if (-not (Test-Path -LiteralPath (Join-Path "$efiRoot\" 'EFI\Microsoft\Boot\bootmgfw.efi'))) { throw 'UEFI bootmgfw.efi ontbreekt' }

    Write-RSSStep 5 5 'Eindcontrole geslaagd.'
    "RESULT=SUCCESS DRIVERSTORE_BEFORE=$before DRIVERSTORE_AFTER=$after" | Add-Content -LiteralPath $script:Log -Encoding UTF8
    Show-RSSSuccess $product $model
    wpeutil reboot
}
catch {
    if (-not $script:Log) {
        $script:Log = $null
    } else {
        $_ | Out-String | Add-Content -LiteralPath $script:Log -Encoding UTF8
    }
    Stop-Safely $_.Exception.Message
}
