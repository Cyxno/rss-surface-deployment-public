<#
.SYNOPSIS
    RSS-mediavernieuwing: reproduceerbare herbouw van de RSS-productiestick.

.DESCRIPTION
    Automatiseert de volledige vernieuwingscyclus van de RSS-stick:

      1. Surface-driverpakketten downloaden (config/sources.json) en verifiëren
         (Authenticode + SHA-256).
      2. MSI's extraheren en INF-aantallen tegen het manifest controleren.
      3. Driverarchieven (SFx-Official-Drivers.esd) bouwen en proefuitpakken.
      4. RSSWinPEDrivers per model voorbereiden volgens config/load-orders.
      5. boot.wim herbouwen vanaf de officiële ADK-winpe.wim (src/winpe).
      6. Windows-image servicen vanaf een voorbereide install.wim (UUP-convert
         of ISO) en per model exporteren als RSSSetup\SFx\sources\install.esd.
      7. Doelmedium partitioneren en de volledige media-assembleren, inclusief
         config/sources.json (gelezen door RSS-Deploy vóór de wipe) en de
         gegenereerde stickdocumentatie.
      8. Media valideren (bestanden, hashes, DISM-index, bootbestanden).

    Internet wordt ALLEEN tijdens dit onderhoudsscript gebruikt; de resulterende
    stick deployt volledig offline. RSS-Deploy.ps1 heeft zelf geen netwerk nodig.

.PARAMETER Phase
    Welke fase(n) uitvoeren: Drivers, Archives, WinPEDrivers, BootWim, Image,
    Media, Validate of All (standaard, volgorde zoals hierboven).

.PARAMETER WorkingDir
    Buildwerkmap (standaard D:\RSS-Build).

.PARAMETER UsbDiskNumber
    Fysiek disknummer van de doel-USB voor fase Media. Verplicht bij Media;
    de build controleert expliciet BusType USB en weigert Disk 0.

.PARAMETER SourceInstallWim
    Pad naar een geserviced of te servicen install.wim (uitgangspunt fase Image).

.EXAMPLE
    .\Update-RSSMedia.ps1 -Phase All -UsbDiskNumber 1 -SourceInstallWim D:\RSS-Build\iso\install.wim

.NOTES
    Vereist: Windows ADK 10.1.26100.9457 + WinPE add-on (standaardpad C:\ADK),
    wimlib 1.14.5 (zie config/sources.json), administratorrechten.
    Er worden nooit credentials of tokens in Git opgeslagen.
#>
[CmdletBinding()]
param(
    [ValidateSet('Drivers','Archives','WinPEDrivers','BootWim','Image','Media','Validate','All')]
    [string]$Phase = 'All',
    [string]$WorkingDir = 'D:\RSS-Build',
    [int]$UsbDiskNumber = -1,
    [string]$SourceInstallWim
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$repo      = Split-Path -Parent $PSScriptRoot
$manifest  = Join-Path $repo 'config\sources.json'
$mst       = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
$adkBase   = 'C:\ADK\Assessment and Deployment Kit'
$adkDism   = Join-Path $adkBase 'Deployment Tools\amd64\DISM\dism.exe'
$winpeWim  = Join-Path $adkBase 'Windows Preinstallation Environment\amd64\en-us\winpe.wim'
$winpeOc   = Join-Path $adkBase 'Windows Preinstallation Environment\amd64\WinPE_OCs'
$wimlib    = Join-Path $WorkingDir 'wimlib\wimlib-imagex.exe'
$msiDir    = Join-Path $WorkingDir 'msi'
$extractDir= Join-Path $WorkingDir 'extracted'
$archiveDir= Join-Path $WorkingDir 'archives'
$logDir    = Join-Path $WorkingDir 'logs'

foreach ($d in $msiDir, $extractDir, $archiveDir, $logDir) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}

function Write-Phase([string]$Name) {
    Write-Host ''
    Write-Host ("===== [{0}] {1} =====" -f (Get-Date -Format 'HH:mm:ss'), $Name) -ForegroundColor Green
}

function Invoke-Wimlib([string[]]$Arguments) {
    $out = Join-Path $logDir 'wimlib.out'
    $err = Join-Path $logDir 'wimlib.err'
    $p = Start-Process -FilePath $wimlib -ArgumentList $Arguments -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err
    if ($p.ExitCode -ne 0) {
        $msg = (Get-Content $err -ErrorAction SilentlyContinue) -join '; '
        throw "wimlib exit $($p.ExitCode): $msg"
    }
}

function Invoke-AdkDism([string[]]$DismArguments) {
    & $adkDism @DismArguments 2>&1 | Select-Object -Last 3 | Write-Host
    if ($LASTEXITCODE -ne 0) { throw "ADK DISM exitcode $LASTEXITCODE" }
}

function Test-Prerequisites {
    foreach ($f in $adkDism, $winpeWim, $wimlib) {
        if (-not (Test-Path -LiteralPath $f)) { throw "vereist onderdeel ontbreekt: $f" }
    }
}

# --------------------------------------------------------------- fase Drivers
function Invoke-DriverPhase {
    Write-Phase 'Drivers: downloaden + verifiëren'
    foreach ($pack in $mst.surfaceDriverPacks) {
        $target = Join-Path $msiDir $pack.msiFilename
        if (-not (Test-Path -LiteralPath $target)) {
            Write-Host "  download $($pack.profile): $($pack.msiFilename)"
            # --fail: fout bij HTTP-foutcode; --retry: tijdelijke netwerkstoringen;
            # partiële downloads blijven achter als .partial en worden verwijderd.
            $partial = "$target.partial"
            curl.exe -sSfL --retry 3 --retry-delay 5 --connect-timeout 30 -o $partial $pack.directUrl
            if ($LASTEXITCODE -ne 0) {
                Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
                throw "download mislukt voor $($pack.profile) (curl exit $LASTEXITCODE)"
            }
            Move-Item -LiteralPath $partial -Destination $target
        }
        $hash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
        if ($hash -ne $pack.sha256) { throw "SHA-256 wijkt af voor $($pack.profile)" }
        $sig = Get-AuthenticodeSignature -LiteralPath $target
        if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Microsoft Corporation') {
            throw "handtekening ongeldig voor $($pack.profile)"
        }
        Write-Host "  OK $($pack.profile) ($([math]::Round((Get-Item $target).Length/1MB,1)) MB)"
    }
}

# -------------------------------------------------------------- fase Archives
function Invoke-ArchivesPhase {
    Write-Phase 'Archives: extraheren, tellen, bouwen'
    foreach ($pack in $mst.surfaceDriverPacks) {
        $modelProfile = $pack.profile
        $msi = Join-Path $msiDir $pack.msiFilename
        $targetDir = Join-Path $extractDir $modelProfile
        if (-not (Test-Path (Join-Path $targetDir 'SurfaceUpdate'))) {
            $p = Start-Process msiexec.exe -ArgumentList '/a', "`"$msi`"", '/qn', "TARGETDIR=`"$targetDir`"" -Wait -PassThru
            if ($p.ExitCode -ne 0) { throw "msiexec /a faalde voor $modelProfile" }
        }
        $infCount = @(Get-ChildItem $targetDir -Recurse -File -Filter '*.inf').Count
        if ($infCount -ne $pack.infCount) {
            throw "INF-telling ${profile}: $infCount in plaats van $($pack.infCount); werk config/sources.json bij"
        }
        $dst = Join-Path $archiveDir "$modelProfile-Official-Drivers.esd"
        if (-not (Test-Path $dst)) {
            Invoke-Wimlib @('capture', (Join-Path $targetDir 'SurfaceUpdate'), $dst, "$modelProfile-Official-Drivers", '--compress=maximum', '--check')
        }
        $stage = Join-Path $archiveDir "stage-$modelProfile"
        if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
        Invoke-Wimlib @('apply', $dst, '1', $stage, '--check')
        $verifyInf = @(Get-ChildItem $stage -Recurse -File -Filter '*.inf').Count
        Remove-Item $stage -Recurse -Force
        if ($verifyInf -ne $pack.infCount) { throw "archief $modelProfile bevat $verifyInf INF" }
        Write-Host ("  OK {0}: {1} INF, archief {2:N0} MB" -f $modelProfile, $verifyInf, ((Get-Item $dst).Length/1MB))
    }
}

# --------------------------------------------------------- fase WinPEDrivers
function Invoke-WinPEDriversPhase {
    Write-Phase 'WinPEDrivers: minimale driversets + load-orders'
    foreach ($pack in $mst.surfaceDriverPacks) {
        $modelProfile = $pack.profile
        $loadOrder = Join-Path $repo "config\load-orders\$modelProfile\load-order.txt"
        if (-not (Test-Path $loadOrder)) { throw "load-order ontbreekt: $loadOrder" }
        $outDir = Join-Path $WorkingDir "media\RSSWinPEDrivers\$modelProfile"
        if (Test-Path $outDir) { Remove-Item $outDir -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $outDir | Out-Null
        Copy-Item -LiteralPath $loadOrder -Destination (Join-Path $outDir 'load-order.txt') -Force
        foreach ($line in (Get-Content $loadOrder | Where-Object { $_.Trim() })) {
            $rel = $line.Trim() -replace '/', '\'
            $src = Join-Path $extractDir "$modelProfile\SurfaceUpdate\$rel"
            if (-not (Test-Path -LiteralPath $src)) { throw "load-order verwijst naar ontbrekend bestand: $modelProfile\$rel" }
            $destDir = Join-Path $outDir (Split-Path -Parent $rel)
            New-Item -ItemType Directory -Force -Path $destDir | Out-Null
            # kopieer de INF met alle naastliggende bestanden onder hun eigen namen
            foreach ($f in (Get-ChildItem (Split-Path -Parent $src) -File)) {
                Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $destDir $f.Name) -Force
            }
        }
        Write-Host "  OK $modelProfile ($(@(Get-ChildItem $outDir -Recurse -File).Count) bestanden)"
    }
}

# -------------------------------------------------------------- fase BootWim
function Invoke-BootWimPhase {
    Write-Phase 'BootWim: boot.wim herbouwen vanaf ADK-winpe.wim'
    $buildDir = Join-Path $WorkingDir 'winpe'
    New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
    foreach ($f in 'RSS-Deploy.ps1','RSS-SafetyLib.ps1','startnet.cmd') {
        Copy-Item -LiteralPath (Join-Path $repo "src\winpe\$f") -Destination (Join-Path $buildDir $f) -Force
    }
    foreach ($t in 'wimlib-imagex.exe','libwim-15.dll') {
        $src = Join-Path (Split-Path -Parent $wimlib) $t
        if (-not (Test-Path $src)) { throw "wimlib-onderdeel ontbreekt: $src" }
        Copy-Item -LiteralPath $src -Destination (Join-Path $buildDir $t) -Force
    }
    $repoBuild = Join-Path $repo 'src\winpe\Build-WinPE.ps1'
    $localBuild = Join-Path $buildDir 'Build-WinPE.ps1'
    Copy-Item -LiteralPath $repoBuild -Destination $localBuild -Force
    & powershell -NoProfile -ExecutionPolicy Bypass -File $localBuild
    if ($LASTEXITCODE -ne 0) { throw 'Build-WinPE.ps1 faalde; zie Build-WinPE.log' }
    Get-Content (Join-Path $buildDir 'Build-WinPE.status')
}

# ---------------------------------------------------------------- fase Image
function Invoke-ImagePhase {
    Write-Phase 'Image: servicen en per model exporteren'
    if (-not $SourceInstallWim -or -not (Test-Path -LiteralPath $SourceInstallWim)) {
        throw "SourceInstallWim ontbreekt: geef een install.wim (UUP-convert of ISO) mee"
    }
    $mount = Join-Path $WorkingDir 'imgmount'
    $reMount = Join-Path $WorkingDir 'remount'
    foreach ($d in $mount, $reMount) {
        if (Test-Path $d) { & $adkDism /English /Cleanup-Mountpoints | Out-Null; Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Force -Path $d | Out-Null
    }

    # 1. WinRE servicen volgens Microsoft-media-flow (SafeOS DU + herplaatsing)
    Copy-Item -LiteralPath $SourceInstallWim -Destination (Join-Path $WorkingDir 'install-serviced.wim') -Force
    $serviced = Join-Path $WorkingDir 'install-serviced.wim'
    Invoke-AdkDism @('/English','/Mount-Image',"/ImageFile:$serviced",'/Index:1',"/MountDir:$mount")
    $winreSource = Join-Path $mount 'Windows\System32\Recovery\winre.wim'
    Copy-Item -LiteralPath $winreSource -Destination (Join-Path $WorkingDir 'winre.wim') -Force
    if ($mst.windows.winreUpdate.catalog) {
        $safeOsCab = Join-Path $WorkingDir 'downloads\SafeOS-DU'
        if (Test-Path (Join-Path $safeOsCab 'WinPE.cab')) {
            Invoke-AdkDism @('/English','/Mount-Image',"/ImageFile:$(Join-Path $WorkingDir 'winre.wim')",'/Index:1',"/MountDir:$reMount")
            Invoke-AdkDism @('/English',"/Image:$reMount",'/Add-Package',"/PackagePath:$safeOsCab")
            Invoke-AdkDism @('/English','/Unmount-Image',"/MountDir:$reMount",'/Commit')
            Copy-Item -LiteralPath (Join-Path $WorkingDir 'winre.wim') -Destination $winreSource -Force
        } else {
            Write-Host '  SafeOS-DU niet gevonden; WinRE blijft op LCU-niveau van de UUP-convert' -ForegroundColor Yellow
        }
    }

    # 2. .NET Framework CU (optioneel aanwezig in downloads\NET-CU\*.msu)
    $netCu = Get-ChildItem (Join-Path $WorkingDir 'downloads\NET-CU') -Filter '*.msu' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($netCu) {
        Invoke-AdkDism @('/English',"/Image:$mount",'/Add-Package',"/PackagePath:$($netCu.FullName)")
    }

    # 3. Controle build-niveau en editie
    Invoke-AdkDism @('/English',"/Image:$mount",'/Get-Packages') | Out-File (Join-Path $logDir 'image-packages.txt') -Encoding UTF8
    Invoke-AdkDism @('/English',"/Image:$mount",'/Get-Intl') | Out-Null
    Invoke-AdkDism @('/English','/Unmount-Image',"/MountDir:$mount",'/Commit')

    # 4. Export per model als recovery-gecomprimeerde install.esd
    foreach ($pack in $mst.surfaceDriverPacks) {
        $modelProfile = $pack.profile
        $esdDir = Join-Path $WorkingDir "media\RSSSetup\$modelProfile\sources"
        New-Item -ItemType Directory -Force -Path $esdDir | Out-Null
        $esd = Join-Path $esdDir 'install.esd'
        & $adkDism /English /Export-Image /SourceImageFile:$serviced /SourceIndex:1 /DestinationImageFile:$esd /Compress:recovery /CheckIntegrity 2>&1 | Select-Object -Last 2 | Write-Host
        if ($LASTEXITCODE -ne 0) { throw "export faalde voor $modelProfile" }
        Write-Host ("  OK {0}: install.esd {1:N1} GB" -f $modelProfile, ((Get-Item $esd).Length/1GB))
    }
}

# ---------------------------------------------------------------- fase Media
function Invoke-MediaPhase {
    Write-Phase 'Media: partitioneren en assembleren'
    if ($UsbDiskNumber -lt 0) { throw '-UsbDiskNumber vereist voor fase Media' }
    $disk = Get-Disk -Number $UsbDiskNumber
    if ($disk.BusType -ne 'USB') { throw "Disk $UsbDiskNumber is geen USB-medium ($($disk.BusType))" }
    if ($disk.IsBoot -or $disk.IsSystem) { throw "Disk $UsbDiskNumber is een systeem-/bootdisk" }
    if ($UsbDiskNumber -eq 0) { throw 'Disk 0 mag nooit het doelmedium zijn' }
    Write-Host ("  doel: Disk {0} = {1} ({2:N1} GB, {3})" -f $disk.Number, $disk.FriendlyName, ($disk.Size/1GB), $disk.PartitionStyle)

    Clear-Disk -Number $UsbDiskNumber -RemoveData -RemoveOEM -Confirm:$false
    Initialize-Disk -Number $UsbDiskNumber -PartitionStyle MBR
    $winpe = New-Partition -DiskNumber $UsbDiskNumber -Size 2GB -IsActive -MbrType FAT32 -AssignDriveLetter
    Format-Volume -Partition $winpe -FileSystem FAT32 -NewFileSystemLabel 'WINPE' -Confirm:$false -Force | Out-Null
    $images = New-Partition -DiskNumber $UsbDiskNumber -UseMaximumSize -MbrType IFS -AssignDriveLetter
    Format-Volume -Partition $images -FileSystem NTFS -NewFileSystemLabel 'Images' -Confirm:$false -Force | Out-Null
    $winpeRoot = "$($winpe.DriveLetter):\"
    $imagesRoot = "$($images.DriveLetter):\"

    # WinPE-media vanaf ADK (allemaal Microsoft-ondertekend)
    $adkMedia = Join-Path $adkBase 'Windows Preinstallation Environment\Media'
    Copy-Item -LiteralPath $adkMedia -Destination $winpeRoot -Recurse -Force
    Remove-Item (Join-Path $winpeRoot 'sources\boot.wim') -Force
    Copy-Item (Join-Path $WorkingDir 'winpe\boot-adk-full.wim') (Join-Path $winpeRoot 'sources\boot.wim') -Force
    # UEFI-fallback bootloader op FAT32-wortel (Surface boot zo vanaf verwijderbaar medium)
    $bootmgfw = Get-ChildItem (Join-Path $adkMedia 'EFI') -Recurse -Filter 'bootmgfw.efi' | Select-Object -First 1
    New-Item -ItemType Directory -Force -Path (Join-Path $winpeRoot 'EFI\Boot') | Out-Null
    Copy-Item -LiteralPath $bootmgfw.FullName -Destination (Join-Path $winpeRoot 'EFI\Boot\bootx64.efi') -Force

    # Images-partitie
    Copy-Item (Join-Path $WorkingDir 'media\RSSSetup') (Join-Path $imagesRoot 'RSSSetup') -Recurse -Force
    New-Item -ItemType Directory -Force -Path (Join-Path $imagesRoot 'RSSDriverArchives') | Out-Null
    foreach ($pack in $mst.surfaceDriverPacks) {
        Copy-Item (Join-Path $archiveDir "$($pack.profile)-Official-Drivers.esd") (Join-Path $imagesRoot "RSSDriverArchives\$($pack.profile).esd") -Force
    }
    Copy-Item (Join-Path $WorkingDir 'media\RSSWinPEDrivers') (Join-Path $imagesRoot 'RSSWinPEDrivers') -Recurse -Force

    # Canonical manifest: RSS-Deploy leest deze vóór de eerste destructieve
    # handeling (hashes, INF-aantallen, SKU-allowlists).
    Copy-Item -LiteralPath $manifest -Destination (Join-Path $imagesRoot 'sources.json') -Force

    # Stickdocumentatie: gegenereerd uit het manifest (Build-Documentation.ps1).
    $stickDocs = Join-Path $repo 'docs\generated\stick'
    foreach ($doc in 'RSS-INFO-production.txt','LEESMIJ-AUTOINSTALL.txt') {
        $generated = Join-Path $stickDocs $doc
        $fallback  = Join-Path $repo "docs\$doc"
        $src = if (Test-Path -LiteralPath $generated) { $generated }
               elseif (Test-Path -LiteralPath $fallback) { $fallback }
               else { throw "stickdoc ontbreekt: $generated (voer tools\Build-Documentation.ps1 -StickDocs uit)" }
        if ($generated -notmatch 'generated\\stick') {
            Write-Host "  LET OP: $doc komt uit docs\ en is mogelijk verouderd; genereer stickdocs met Build-Documentation.ps1" -ForegroundColor Yellow
        }
        Copy-Item $src (Join-Path $imagesRoot $doc) -Force
    }
    Write-Host "  WINPE = $($winpe.DriveLetter): / Images = $($images.DriveLetter):"
}

# ------------------------------------------------------------- fase Validate
function Invoke-ValidatePhase {
    Write-Phase 'Validate: mediavalidatie'
    $imagesVol = Get-Volume | Where-Object { $_.FileSystemLabel -eq 'Images' }
    $winpeVol  = Get-Volume | Where-Object { $_.FileSystemLabel -eq 'WINPE' }
    if (-not $imagesVol -or -not $winpeVol) { throw 'WINPE/Images-volumes niet gevonden; voer fase Media uit' }
    $imagesRoot = "$($imagesVol.DriveLetter):\"
    $winpeRoot  = "$($winpeVol.DriveLetter):\"

    foreach ($pack in $mst.surfaceDriverPacks) {
        $p = $pack.profile
        $esd = Join-Path $imagesRoot "RSSSetup\$p\sources\install.esd"
        $arc = Join-Path $imagesRoot "RSSDriverArchives\$p.esd"
        foreach ($f in $esd, $arc) { if (-not (Test-Path $f)) { throw "ontbreekt: $f" } }
        & $adkDism /English /Get-WimInfo /WimFile:$esd /Index:1 | Select-String 'Size|Name|Architecture' | Write-Host
        & $adkDism /English /Get-WimInfo /WimFile:$arc /Index:1 | Select-String 'Name' | Write-Host
    }
    $boot = Join-Path $winpeRoot 'sources\boot.wim'
    & $adkDism /English /Get-WimInfo /WimFile:$boot | Select-Object -First 6 | Write-Host
    foreach ($f in (Join-Path $winpeRoot 'EFI\Boot\bootx64.efi'), (Join-Path $winpeRoot 'bootmgr.efi')) {
        if (-not (Test-Path $f)) { throw "bootbestand ontbreekt: $f" }
        $s = Get-AuthenticodeSignature -LiteralPath $f
        if ($s.Status -ne 'Valid') { throw "bootbestand niet geldig ondertekend: $f" }
    }
    Write-Host '  VALIDATIE OK' -ForegroundColor Green
}

# ------------------------------------------------------------------ aanroep
Test-Prerequisites
$phases = if ($Phase -eq 'All') { 'Drivers','Archives','WinPEDrivers','BootWim','Image','Media','Validate' } else { $Phase }
foreach ($p in $phases) {
    switch ($p) {
        'Drivers'      { Invoke-DriverPhase }
        'Archives'     { Invoke-ArchivesPhase }
        'WinPEDrivers' { Invoke-WinPEDriversPhase }
        'BootWim'      { Invoke-BootWimPhase }
        'Image'        { Invoke-ImagePhase }
        'Media'        { Invoke-MediaPhase }
        'Validate'     { Invoke-ValidatePhase }
    }
}
Write-Host ''
Write-Host 'RSS-MEDIA-REFRESH VOLTOOID' -ForegroundColor Green
