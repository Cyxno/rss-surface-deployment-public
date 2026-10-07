<#
.SYNOPSIS
    RSS media refresh: reproducible rebuild of the RSS production stick.

.DESCRIPTION
    Automates the complete refresh cycle of the RSS stick:

      1. Download and verify the Surface driver packages (config/sources.json)
         (Authenticode + SHA-256).
      2. Extract the MSIs and check the INF counts against the manifest.
      3. Build the driver archives (SFx-Official-Drivers.esd) and trial-extract them.
      4. Prepare RSSWinPEDrivers per model according to config/load-orders.
      5. Rebuild boot.wim from the official ADK winpe.wim (src/winpe).
      6. Service the Windows image from a prepared install.wim (UUP-convert
         or ISO) and export it per model as RSSSetup\SFx\sources\install.esd.
      7. Partition the target medium and assemble the complete media, including
         config/sources.json (read by RSS-Deploy before the wipe) and the
         generated stick documentation.
      8. Validate the media (files, hashes, DISM index, boot files).

    Internet is used ONLY while this maintenance script runs; the resulting
    stick deploys fully offline. RSS-Deploy.ps1 itself needs no network.

.PARAMETER Phase
    Which phase(s) to run: Drivers, Archives, WinPEDrivers, BootWim, Image,
    Media, Validate or All (default, in the order shown above).

.PARAMETER WorkingDir
    Build working directory (default D:\RSS-Build).

.PARAMETER UsbDiskNumber
    Physical disk number of the target USB for phase Media. Required with Media;
    the build explicitly checks BusType USB and refuses Disk 0.

.PARAMETER SourceInstallWim
    Path to a serviced or to-be-serviced install.wim (input for phase Image).

.EXAMPLE
    .\Update-RSSMedia.ps1 -Phase All -UsbDiskNumber 1 -SourceInstallWim D:\RSS-Build\iso\install.wim

.NOTES
    Requires: Windows ADK 10.1.26100.9457 + WinPE add-on (default path C:\ADK),
    wimlib 1.14.5 (see config/sources.json), administrator rights.
    No credentials or tokens are ever stored in Git.
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
        if (-not (Test-Path -LiteralPath $f)) { throw "required component missing: $f" }
    }
}

# -------------------------------------------------------------- phase Drivers
function Invoke-DriverPhase {
    Write-Phase 'Drivers: download + verify'
    foreach ($pack in $mst.surfaceDriverPacks) {
        $target = Join-Path $msiDir $pack.msiFilename
        if (-not (Test-Path -LiteralPath $target)) {
            Write-Host "  download $($pack.profile): $($pack.msiFilename)"
            # --fail: fail on HTTP error codes; --retry: transient network glitches;
            # partial downloads are left behind as .partial and are removed.
            $partial = "$target.partial"
            curl.exe -sSfL --retry 3 --retry-delay 5 --connect-timeout 30 -o $partial $pack.directUrl
            if ($LASTEXITCODE -ne 0) {
                Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
                throw "download failed for $($pack.profile) (curl exit $LASTEXITCODE)"
            }
            Move-Item -LiteralPath $partial -Destination $target
        }
        $hash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
        if ($hash -ne $pack.sha256) { throw "SHA-256 mismatch for $($pack.profile)" }
        $sig = Get-AuthenticodeSignature -LiteralPath $target
        if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Microsoft Corporation') {
            throw "signature invalid for $($pack.profile)"
        }
        Write-Host "  OK $($pack.profile) ($([math]::Round((Get-Item $target).Length/1MB,1)) MB)"
    }
}

# ------------------------------------------------------------- phase Archives
function Invoke-ArchivesPhase {
    Write-Phase 'Archives: extract, count, build'
    foreach ($pack in $mst.surfaceDriverPacks) {
        $modelProfile = $pack.profile
        $msi = Join-Path $msiDir $pack.msiFilename
        $targetDir = Join-Path $extractDir $modelProfile
        if (-not (Test-Path (Join-Path $targetDir 'SurfaceUpdate'))) {
            $p = Start-Process msiexec.exe -ArgumentList '/a', "`"$msi`"", '/qn', "TARGETDIR=`"$targetDir`"" -Wait -PassThru
            if ($p.ExitCode -ne 0) { throw "msiexec /a failed for $modelProfile" }
        }
        $infCount = @(Get-ChildItem $targetDir -Recurse -File -Filter '*.inf').Count
        if ($infCount -ne $pack.infCount) {
            throw "INF count ${profile}: $infCount instead of $($pack.infCount); update config/sources.json"
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
        if ($verifyInf -ne $pack.infCount) { throw "archive $modelProfile contains $verifyInf INF files" }
        Write-Host ("  OK {0}: {1} INF, archive {2:N0} MB" -f $modelProfile, $verifyInf, ((Get-Item $dst).Length/1MB))
    }
}

# --------------------------------------------------------- phase WinPEDrivers
function Invoke-WinPEDriversPhase {
    Write-Phase 'WinPEDrivers: minimal driver sets + load orders'
    foreach ($pack in $mst.surfaceDriverPacks) {
        $modelProfile = $pack.profile
        $loadOrder = Join-Path $repo "config\load-orders\$modelProfile\load-order.txt"
        if (-not (Test-Path $loadOrder)) { throw "load-order missing: $loadOrder" }
        $outDir = Join-Path $WorkingDir "media\RSSWinPEDrivers\$modelProfile"
        if (Test-Path $outDir) { Remove-Item $outDir -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $outDir | Out-Null
        Copy-Item -LiteralPath $loadOrder -Destination (Join-Path $outDir 'load-order.txt') -Force
        foreach ($line in (Get-Content $loadOrder | Where-Object { $_.Trim() })) {
            $rel = $line.Trim() -replace '/', '\'
            $src = Join-Path $extractDir "$modelProfile\SurfaceUpdate\$rel"
            if (-not (Test-Path -LiteralPath $src)) { throw "load-order references a missing file: $modelProfile\$rel" }
            $destDir = Join-Path $outDir (Split-Path -Parent $rel)
            New-Item -ItemType Directory -Force -Path $destDir | Out-Null
            # copy the INF together with all adjacent files under their own names
            foreach ($f in (Get-ChildItem (Split-Path -Parent $src) -File)) {
                Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $destDir $f.Name) -Force
            }
        }
        Write-Host "  OK $modelProfile ($(@(Get-ChildItem $outDir -Recurse -File).Count) files)"
    }
}

# -------------------------------------------------------------- phase BootWim
function Invoke-BootWimPhase {
    Write-Phase 'BootWim: rebuild boot.wim from the ADK winpe.wim'
    $buildDir = Join-Path $WorkingDir 'winpe'
    New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
    foreach ($f in 'RSS-Deploy.ps1','RSS-SafetyLib.ps1','startnet.cmd') {
        Copy-Item -LiteralPath (Join-Path $repo "src\winpe\$f") -Destination (Join-Path $buildDir $f) -Force
    }
    foreach ($t in 'wimlib-imagex.exe','libwim-15.dll') {
        $src = Join-Path (Split-Path -Parent $wimlib) $t
        if (-not (Test-Path $src)) { throw "wimlib component missing: $src" }
        Copy-Item -LiteralPath $src -Destination (Join-Path $buildDir $t) -Force
    }
    $repoBuild = Join-Path $repo 'src\winpe\Build-WinPE.ps1'
    $localBuild = Join-Path $buildDir 'Build-WinPE.ps1'
    Copy-Item -LiteralPath $repoBuild -Destination $localBuild -Force
    & powershell -NoProfile -ExecutionPolicy Bypass -File $localBuild
    if ($LASTEXITCODE -ne 0) { throw 'Build-WinPE.ps1 failed; see Build-WinPE.log' }
    Get-Content (Join-Path $buildDir 'Build-WinPE.status')
}

# ---------------------------------------------------------------- phase Image
function Invoke-ImagePhase {
    Write-Phase 'Image: service and export per model'
    if (-not $SourceInstallWim -or -not (Test-Path -LiteralPath $SourceInstallWim)) {
        throw "SourceInstallWim missing: supply an install.wim (UUP-convert or ISO)"
    }
    $mount = Join-Path $WorkingDir 'imgmount'
    $reMount = Join-Path $WorkingDir 'remount'
    foreach ($d in $mount, $reMount) {
        if (Test-Path $d) { & $adkDism /English /Cleanup-Mountpoints | Out-Null; Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Force -Path $d | Out-Null
    }

    # 1. Service WinRE following the Microsoft media flow (SafeOS DU + re-staging)
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
            Write-Host '  SafeOS-DU not found; WinRE stays at the UUP-convert LCU level' -ForegroundColor Yellow
        }
    }

    # 2. .NET Framework CU (optionally present in downloads\NET-CU\*.msu)
    $netCu = Get-ChildItem (Join-Path $WorkingDir 'downloads\NET-CU') -Filter '*.msu' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($netCu) {
        Invoke-AdkDism @('/English',"/Image:$mount",'/Add-Package',"/PackagePath:$($netCu.FullName)")
    }

    # 3. Check build level and edition
    Invoke-AdkDism @('/English',"/Image:$mount",'/Get-Packages') | Out-File (Join-Path $logDir 'image-packages.txt') -Encoding UTF8
    Invoke-AdkDism @('/English',"/Image:$mount",'/Get-Intl') | Out-Null
    Invoke-AdkDism @('/English','/Unmount-Image',"/MountDir:$mount",'/Commit')

    # 4. Export per model as recovery-compressed install.esd
    foreach ($pack in $mst.surfaceDriverPacks) {
        $modelProfile = $pack.profile
        $esdDir = Join-Path $WorkingDir "media\RSSSetup\$modelProfile\sources"
        New-Item -ItemType Directory -Force -Path $esdDir | Out-Null
        $esd = Join-Path $esdDir 'install.esd'
        & $adkDism /English /Export-Image /SourceImageFile:$serviced /SourceIndex:1 /DestinationImageFile:$esd /Compress:recovery /CheckIntegrity 2>&1 | Select-Object -Last 2 | Write-Host
        if ($LASTEXITCODE -ne 0) { throw "export failed for $modelProfile" }
        Write-Host ("  OK {0}: install.esd {1:N1} GB" -f $modelProfile, ((Get-Item $esd).Length/1GB))
    }
}

# --------------------------------------------------------------- phase Media
function Invoke-MediaPhase {
    Write-Phase 'Media: partition and assemble'
    if ($UsbDiskNumber -lt 0) { throw '-UsbDiskNumber required for phase Media' }
    $disk = Get-Disk -Number $UsbDiskNumber
    if ($disk.BusType -ne 'USB') { throw "Disk $UsbDiskNumber is not a USB medium ($($disk.BusType))" }
    if ($disk.IsBoot -or $disk.IsSystem) { throw "Disk $UsbDiskNumber is a system/boot disk" }
    if ($UsbDiskNumber -eq 0) { throw 'Disk 0 must never be the target medium' }
    Write-Host ("  target: Disk {0} = {1} ({2:N1} GB, {3})" -f $disk.Number, $disk.FriendlyName, ($disk.Size/1GB), $disk.PartitionStyle)

    Clear-Disk -Number $UsbDiskNumber -RemoveData -RemoveOEM -Confirm:$false
    Initialize-Disk -Number $UsbDiskNumber -PartitionStyle MBR
    $winpe = New-Partition -DiskNumber $UsbDiskNumber -Size 2GB -IsActive -MbrType FAT32 -AssignDriveLetter
    Format-Volume -Partition $winpe -FileSystem FAT32 -NewFileSystemLabel 'WINPE' -Confirm:$false -Force | Out-Null
    $images = New-Partition -DiskNumber $UsbDiskNumber -UseMaximumSize -MbrType IFS -AssignDriveLetter
    Format-Volume -Partition $images -FileSystem NTFS -NewFileSystemLabel 'Images' -Confirm:$false -Force | Out-Null
    $winpeRoot = "$($winpe.DriveLetter):\"
    $imagesRoot = "$($images.DriveLetter):\"

    # WinPE media from the ADK (all of it Microsoft-signed)
    $adkMedia = Join-Path $adkBase 'Windows Preinstallation Environment\Media'
    Copy-Item -LiteralPath $adkMedia -Destination $winpeRoot -Recurse -Force
    Remove-Item (Join-Path $winpeRoot 'sources\boot.wim') -Force
    Copy-Item (Join-Path $WorkingDir 'winpe\boot-adk-full.wim') (Join-Path $winpeRoot 'sources\boot.wim') -Force
    # UEFI fallback bootloader on the FAT32 root (so Surface boots straight from removable media)
    $bootmgfw = Get-ChildItem (Join-Path $adkMedia 'EFI') -Recurse -Filter 'bootmgfw.efi' | Select-Object -First 1
    New-Item -ItemType Directory -Force -Path (Join-Path $winpeRoot 'EFI\Boot') | Out-Null
    Copy-Item -LiteralPath $bootmgfw.FullName -Destination (Join-Path $winpeRoot 'EFI\Boot\bootx64.efi') -Force

    # Images partition
    Copy-Item (Join-Path $WorkingDir 'media\RSSSetup') (Join-Path $imagesRoot 'RSSSetup') -Recurse -Force
    New-Item -ItemType Directory -Force -Path (Join-Path $imagesRoot 'RSSDriverArchives') | Out-Null
    foreach ($pack in $mst.surfaceDriverPacks) {
        Copy-Item (Join-Path $archiveDir "$($pack.profile)-Official-Drivers.esd") (Join-Path $imagesRoot "RSSDriverArchives\$($pack.profile).esd") -Force
    }
    Copy-Item (Join-Path $WorkingDir 'media\RSSWinPEDrivers') (Join-Path $imagesRoot 'RSSWinPEDrivers') -Recurse -Force

    # Canonical manifest: RSS-Deploy reads this before the first destructive
    # action (hashes, INF counts, SKU allowlists).
    Copy-Item -LiteralPath $manifest -Destination (Join-Path $imagesRoot 'sources.json') -Force

    # Stick documentation: generated from the manifest (Build-Documentation.ps1).
    $stickDocs = Join-Path $repo 'docs\generated\stick'
    foreach ($doc in 'RSS-INFO-production.txt','README-AUTOINSTALL.txt') {
        $generated = Join-Path $stickDocs $doc
        $fallback  = Join-Path $repo "docs\$doc"
        $src = if (Test-Path -LiteralPath $generated) { $generated }
               elseif (Test-Path -LiteralPath $fallback) { $fallback }
               else { throw "stick doc missing: $generated (run tools\Build-Documentation.ps1 -StickDocs)" }
        if ($generated -notmatch 'generated\\stick') {
            Write-Host "  NOTE: $doc comes from docs\ and may be outdated; generate stick docs with Build-Documentation.ps1" -ForegroundColor Yellow
        }
        Copy-Item $src (Join-Path $imagesRoot $doc) -Force
    }
    Write-Host "  WINPE = $($winpe.DriveLetter): / Images = $($images.DriveLetter):"
}

# ------------------------------------------------------------ phase Validate
function Invoke-ValidatePhase {
    Write-Phase 'Validate: media validation'
    $imagesVol = Get-Volume | Where-Object { $_.FileSystemLabel -eq 'Images' }
    $winpeVol  = Get-Volume | Where-Object { $_.FileSystemLabel -eq 'WINPE' }
    if (-not $imagesVol -or -not $winpeVol) { throw 'WINPE/Images volumes not found; run phase Media' }
    $imagesRoot = "$($imagesVol.DriveLetter):\"
    $winpeRoot  = "$($winpeVol.DriveLetter):\"

    foreach ($pack in $mst.surfaceDriverPacks) {
        $p = $pack.profile
        $esd = Join-Path $imagesRoot "RSSSetup\$p\sources\install.esd"
        $arc = Join-Path $imagesRoot "RSSDriverArchives\$p.esd"
        foreach ($f in $esd, $arc) { if (-not (Test-Path $f)) { throw "missing: $f" } }
        & $adkDism /English /Get-WimInfo /WimFile:$esd /Index:1 | Select-String 'Size|Name|Architecture' | Write-Host
        & $adkDism /English /Get-WimInfo /WimFile:$arc /Index:1 | Select-String 'Name' | Write-Host
    }
    $boot = Join-Path $winpeRoot 'sources\boot.wim'
    & $adkDism /English /Get-WimInfo /WimFile:$boot | Select-Object -First 6 | Write-Host
    foreach ($f in (Join-Path $winpeRoot 'EFI\Boot\bootx64.efi'), (Join-Path $winpeRoot 'bootmgr.efi')) {
        if (-not (Test-Path $f)) { throw "boot file missing: $f" }
        $s = Get-AuthenticodeSignature -LiteralPath $f
        if ($s.Status -ne 'Valid') { throw "boot file not validly signed: $f" }
    }
    Write-Host '  VALIDATION OK' -ForegroundColor Green
}

# ------------------------------------------------------------- invocation
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
Write-Host 'RSS-MEDIA-REFRESH COMPLETED' -ForegroundColor Green
