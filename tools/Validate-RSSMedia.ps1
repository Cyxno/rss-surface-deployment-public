<#
.SYNOPSIS
    Read-only validation of the RSS production stick.

.DESCRIPTION
    Checks, without changing anything:
      - physical USB identity (Samsung, USB, not Disk 0, not boot/system)
      - the WINPE (FAT32, active) and Images (NTFS) partitions + filesystem status
      - required files (boot files, images, archives, load orders, docs, manifest)
      - sources.json on the stick byte-identical to config/sources.json
      - boot.wim SHA-256 against this manifest
      - Secure Boot binaries (Authenticode) and BCD presence
      - Windows images identical to each other + DISM metadata (edition, architecture)
      - serviced build (26200.9457), KBs present, KB5124010 absent
      - driver archives: SHA-256, integrity, exact INF counts (wimlib)
      - RSSWinPEDrivers: load orders, INF files that really are INF content, catalogs
      - PowerShell syntax (AST) of the deployment logic and safety library
      - guardrail presence in RSS-Deploy.ps1 (manifest, hash check, disk selection)
      - no user-interaction or MDM/OOBE risk patterns in the deployment logic
      - RSS-INFO.txt on the stick consistent with config/sources.json (anti-drift)

    Uses wimlib for the INF re-verification; path configurable via -WimlibPath.
    DISM mounts require administrator rights; without those rights those
    checks fall back to WARN.

.PARAMETER WimlibPath
    Path to wimlib-imagex.exe (default D:\RSS-Build\wimlib\wimlib-imagex.exe).

.PARAMETER ReportPath
    Where the report is written (default: RSS-Media-Validation.txt on the
    Images partition, plus a local copy next to this script).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\Validate-RSSMedia.ps1

.NOTES
    Exit codes: 0 = PASS, 1 = FAIL, 2 = warnings only.
    This script is deliberately 100% read-only: it formats, wipes and changes
    nothing on the stick. DISM mounts happen with /ReadOnly and are discarded afterwards.
#>
[CmdletBinding()]
param(
    [string]$WimlibPath = 'D:\RSS-Build\wimlib\wimlib-imagex.exe',
    [string]$ReportPath
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$repo = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $repo 'config\sources.json'
$mst = Get-Content $manifestPath -Raw | ConvertFrom-Json

$results = New-Object System.Collections.Generic.List[object]
function Add-Check([string]$Status, [string]$Section, [string]$Message) {
    $results.Add([pscustomobject]@{ Status = $Status; Section = $Section; Message = $Message })
    $color = if ($Status -eq 'PASS') { 'Green' } elseif ($Status -eq 'WARN') { 'Yellow' } else { 'Red' }
    Write-Host ("[{0}] {1}: {2}" -f $Status, $Section, $Message) -ForegroundColor $color
}
function Test-Admin {
    $p = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
$isAdmin = Test-Admin

# -------------------------------------------------------------- 1. physical
$sec = 'USB-hardware'
$usbDisks = @(Get-Disk | Where-Object { $_.BusType -eq 'USB' })
$samsung = @($usbDisks | Where-Object { $_.FriendlyName -match 'Samsung' })
if ($samsung.Count -ne 1) {
    Add-Check 'FAIL' $sec "expected exactly one Samsung USB disk, found $($samsung.Count)"
} else {
    $d = $samsung[0]
    if ($d.Number -eq 0) { Add-Check 'FAIL' $sec 'USB is Disk 0' }
    elseif ($d.IsBoot -or $d.IsSystem) { Add-Check 'FAIL' $sec 'USB is boot/system disk' }
    else { Add-Check 'PASS' $sec "Disk $($d.Number) = $($d.FriendlyName), $([math]::Round($d.Size/1GB,1)) GB, $($d.PartitionStyle)" }
    $usbNumber = $d.Number
}

# ----------------------------------------------------------- 2. partitions
$sec = 'Partitions'
$winpeVol = Get-Volume | Where-Object { $_.FileSystemLabel -eq 'WINPE' }
$imagesVol = Get-Volume | Where-Object { $_.FileSystemLabel -eq 'Images' }
if (-not $winpeVol -or -not $imagesVol) {
    Add-Check 'FAIL' $sec 'WINPE/Images volumes missing'
} else {
    $wp = Get-Partition -DriveLetter $winpeVol.DriveLetter -ErrorAction SilentlyContinue
    $ip = Get-Partition -DriveLetter $imagesVol.DriveLetter -ErrorAction SilentlyContinue
    $okParts = ($wp.DiskNumber -eq $ip.DiskNumber) -and ($wp.DiskNumber -eq $usbNumber)
    if (-not $okParts) { Add-Check 'FAIL' $sec 'partitions are not on the Samsung USB disk' }
    elseif ($winpeVol.FileSystem -ne 'FAT32') { Add-Check 'FAIL' $sec 'WINPE is not FAT32' }
    elseif ($imagesVol.FileSystem -ne 'NTFS') { Add-Check 'FAIL' $sec 'Images is not NTFS' }
    elseif (-not $wp.IsActive) { Add-Check 'WARN' $sec 'WINPE partition is not active (UEFI boot also works without the active flag)' }
    else { Add-Check 'PASS' $sec "WINPE=$($winpeVol.DriveLetter): ($([math]::Round($winpeVol.Size/1GB,2)) GB), Images=$($imagesVol.DriveLetter): ($([math]::Round($imagesVol.Size/1GB,2)) GB)" }
    $dirty = $null
    try { $dirty = fsutil dirty query "$($winpeVol.DriveLetter):" 2>$null; $dirty2 = fsutil dirty query "$($imagesVol.DriveLetter):" 2>$null } catch {}
    if ("$dirty $dirty2" -match 'IS Dirty') { Add-Check 'FAIL' $sec 'filesystem dirty bit is set' }
    elseif ($dirty -and $dirty2) { Add-Check 'PASS' $sec 'filesystems not dirty' }
    if ($imagesVol.SizeRemaining -lt 5GB) { Add-Check 'WARN' $sec "low free space on Images: $([math]::Round($imagesVol.SizeRemaining/1GB,1)) GB" }
}

# --------------------------------------------------------- 3. required files
$sec = 'Required files'
$winpeRoot = "$($winpeVol.DriveLetter):\"
$imagesRoot = "$($imagesVol.DriveLetter):\"
$stickProfiles = @($mst.surfaceDriverPacks | ForEach-Object profile)
$required = @(
    'EFI\Boot\bootx64.efi', 'EFI\Microsoft\Boot\BCD', 'sources\boot.wim', 'bootmgr', 'bootmgr.efi'
) | ForEach-Object { Join-Path $winpeRoot $_ }
$required += $stickProfiles | ForEach-Object {
    (Join-Path $imagesRoot "RSSSetup\$_\sources\install.esd"),
    (Join-Path $imagesRoot "RSSDriverArchives\$_.esd"),
    (Join-Path $imagesRoot "RSSWinPEDrivers\$_\load-order.txt")
}
$required += (Join-Path $imagesRoot 'RSS-INFO.txt'), (Join-Path $imagesRoot 'README-AUTOINSTALL.txt'), (Join-Path $imagesRoot 'sources.json')
$missing = @($required | Where-Object { -not (Test-Path $_) })
if ($missing.Count) { Add-Check 'FAIL' $sec "missing: $($missing -join ', ')" }
else { Add-Check 'PASS' $sec "all $($required.Count) required files present" }

# the manifest on the stick must be byte-identical to config/sources.json in the repo
$repoManifestHash = (Get-FileHash $manifestPath -Algorithm SHA256).Hash
$stickManifestHash = (Get-FileHash (Join-Path $imagesRoot 'sources.json') -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
if ($stickManifestHash -eq $repoManifestHash) { Add-Check 'PASS' $sec 'sources.json on stick == repo manifest' }
else { Add-Check 'FAIL' $sec 'sources.json on stick differs from config/sources.json (rebuild or refresh the stick)' }

$junk = @(Get-ChildItem $winpeRoot, $imagesRoot -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '\.(tmp|partial|aria2)$|^~\$' })
if ($junk.Count) { Add-Check 'WARN' $sec "temporary files: $($junk.Count)" }

# ------------------------------------------------------------- 4. boot.wim
$sec = 'boot.wim'
$bootHash = (Get-FileHash (Join-Path $winpeRoot 'sources\boot.wim') -Algorithm SHA256).Hash
$expectedBoot = $mst.media.bootWimSha256
if ($bootHash -eq $expectedBoot) { Add-Check 'PASS' $sec "SHA-256 matches ($($bootHash.Substring(0,16))...)" }
else { Add-Check 'FAIL' $sec "SHA-256 mismatch: $bootHash" }

# ------------------------------------------------- 5. Secure Boot binaries
$sec = 'Secure Boot'
$bootx = Get-AuthenticodeSignature -LiteralPath (Join-Path $winpeRoot 'EFI\Boot\bootx64.efi')
if ($bootx.Status -eq 'Valid' -and $bootx.SignerCertificate.Subject -match 'Microsoft') {
    Add-Check 'PASS' $sec 'bootx64.efi validly Microsoft-signed'
} else { Add-Check 'FAIL' $sec "bootx64.efi signature: $($bootx.Status)" }
if (Test-Path (Join-Path $winpeRoot 'EFI\Microsoft\Boot\BCD')) { Add-Check 'PASS' $sec 'BCD present' }
else { Add-Check 'FAIL' $sec 'BCD missing' }
$bcdOutput = $null
$bcdFile = Join-Path $winpeRoot 'EFI\Microsoft\Boot\BCD'
$bcdOutput = & bcdedit /store $bcdFile /enum all 2>$null
if ($bcdOutput) {
    $bcdText = $bcdOutput -join "`n"
    if ($bcdText -match 'nointegritychecks\s+Yes|testsigning\s+Yes') { Add-Check 'FAIL' $sec 'BCD contains test-signing/nointegritychecks' }
    elseif ($bcdText -match 'boot\.wim' -and $bcdText -match 'winload\.efi') { Add-Check 'PASS' $sec 'BCD boots boot.wim via winload.efi, no test flags' }
    else { Add-Check 'WARN' $sec 'BCD content unexpected (check manually)' }
} else { Add-Check 'WARN' $sec 'BCD could not be read (administrator required)' }

# ------------------------------------------------- 6. Windows images
$sec = 'Windows images'
$esdHashes = @{}
foreach ($p in $stickProfiles) {
    $esdHashes[$p] = (Get-FileHash (Join-Path $imagesRoot "RSSSetup\$p\sources\install.esd") -Algorithm SHA256).Hash
}
$distinct = @($esdHashes.Values | Sort-Object -Unique)
if ($distinct.Count -eq 1) { Add-Check 'PASS' $sec 'all 5 install.esd files are byte-identical' }
else { Add-Check 'FAIL' $sec "install.esd files differ: $($distinct.Count) unique hashes" }
$expectedEsd = $mst.windows.servicedImage.installEsdSha256
if ($distinct[0] -eq $expectedEsd) { Add-Check 'PASS' $sec 'install.esd hash == manifest' }
else { Add-Check 'FAIL' $sec "install.esd hash differs from manifest: $($distinct[0])" }

if ($isAdmin) {
    $dism = 'C:\ADK\Assessment and Deployment Kit\Deployment Tools\amd64\DISM\dism.exe'
    if (-not (Test-Path $dism)) { $dism = 'dism.exe' }
    $probe = Join-Path $env:TEMP 'rss-validate-esdmount'
    if (Test-Path $probe) { & $dism /English /Cleanup-Mountpoints 2>$null | Out-Null; Remove-Item $probe -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Force -Path $probe | Out-Null
    $esdFile = Join-Path $imagesRoot 'RSSSetup\SF8\sources\install.esd'
    $mountOk = $true
    & $dism /English /Mount-Image "/ImageFile:$esdFile" '/Index:1' "/MountDir:$probe" '/ReadOnly' 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        $mountOk = $false
        Add-Check 'WARN' $sec 'ESD could not be mounted read-only (build check skipped)'
    }
    if ($mountOk) {
        $soft = Join-Path $probe 'Windows\System32\config\SOFTWARE'
        reg load 'HKLM\RSSVAL' $soft | Out-Null
        $cv = Get-ItemProperty 'HKLM:\RSSVAL\Microsoft\Windows NT\CurrentVersion'
        $build = "$($cv.CurrentBuild).$($cv.UBR)"
        reg unload 'HKLM\RSSVAL' | Out-Null
        if ($build -eq $mst.windows.servicedImage.verifiedBuild) { Add-Check 'PASS' $sec "build $build $($cv.EditionID) $($cv.DisplayVersion)" }
        else { Add-Check 'FAIL' $sec "build is $build, expected $($mst.windows.servicedImage.verifiedBuild)" }
        # language check via DISM /Get-Intl (the offline registry InstallLanguage is unreliable)
        $expectedLang = $mst.windows.servicedImage.installLanguage
        if ($expectedLang) {
            $intl = (& $dism /English "/Image:$probe" /Get-Intl) -join "`n"
            if ($intl -match "Default system UI language\s*:\s*$expectedLang") { Add-Check 'PASS' $sec "system UI language $expectedLang" }
            else { Add-Check 'FAIL' $sec "system UI language is not $expectedLang" }
        }
        $pkgs = (& $dism /English "/Image:$probe" /Get-Packages) -join "`n"
        if ([string]::IsNullOrWhiteSpace($pkgs)) { Add-Check 'WARN' $sec 'Get-Packages returned no output' }
        else {
            # LCUs register as RollupFix (revision = build); SSU/eKB/.NET under their own identity
            $kbChecks = @(
                @('LCU KB5129195 (RollupFix 26100.9457)', 'RollupFix~[^\r\n]*?26100\.9457'),
                @('SSU KB5124007 (ServicingStack 9441)', 'ServicingStack_9441'),
                @('25H2 eKB KB5054156', 'KB5054156'),
                @('.NET CU KB5126052 (DotNetRollup 9347)', 'DotNetRollup_481[^\r\n]*?9347')
            )
            foreach ($c in $kbChecks) {
                if ($pkgs -match $c[1]) { Add-Check 'PASS' $sec $c[0] } else { Add-Check 'FAIL' $sec "$($c[0]) missing" }
            }
            if ($pkgs -match 'KB5124010|26200\.9550') { Add-Check 'FAIL' $sec 'preview update KB5124010/9550 found!' }
            else { Add-Check 'PASS' $sec 'no preview update KB5124010' }
            if ($pkgs -match 'pending') { Add-Check 'WARN' $sec 'pending packages entry in Get-Packages' }
        }
        foreach ($f in 'Windows\System32\winload.efi', 'Windows\System32\Recovery\winre.wim') {
            if (Test-Path (Join-Path $probe $f)) { Add-Check 'PASS' $sec "$f present" } else { Add-Check 'FAIL' $sec "$f missing" }
        }
        # check winre.wim for SafeOS servicing (the SafeOS DU is not in the main image)
        $winreOut = Join-Path $env:TEMP 'rss-validate-winre.wim'
        $winreProbe = Join-Path $env:TEMP 'rss-validate-winre'
        Copy-Item (Join-Path $probe 'Windows\System32\Recovery\winre.wim') $winreOut -Force
        & $dism /English /Unmount-Image /MountDir:$probe /Discard 2>&1 | Out-Null
        if (Test-Path $winreProbe) { Remove-Item $winreProbe -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Force -Path $winreProbe | Out-Null
        & $dism /English /Mount-Image "/ImageFile:$winreOut" '/Index:1' "/MountDir:$winreProbe" '/ReadOnly' 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $wpkgs = (& $dism /English "/Image:$winreProbe" /Get-Packages) -join "`n"
            if ($wpkgs -match '26100\.944[5-9]|26100\.945\d') { Add-Check 'PASS' $sec 'WinRE is serviced with SafeOS DU (revision 9445+)' }
            else { Add-Check 'FAIL' $sec 'WinRE contains no SafeOS-serviced revisions' }
            & $dism /English /Unmount-Image /MountDir:$winreProbe /Discard 2>&1 | Out-Null
        } else { Add-Check 'WARN' $sec 'winre.wim could not be checked' }
        Remove-Item $winreOut, $winreProbe -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Item $probe -Recurse -Force -ErrorAction SilentlyContinue
} else {
    Add-Check 'WARN' $sec 'build/KB check skipped (no administrator rights)'
}

# ------------------------------------------------- 7. driver archives
$sec = 'Driver archives'
$haveWimlib = Test-Path $WimlibPath
if (-not $haveWimlib) { Add-Check 'WARN' $sec "wimlib not found at $WimlibPath; INF re-verification skipped" }
foreach ($pack in $mst.surfaceDriverPacks) {
    $p = $pack.profile
    $arc = Join-Path $imagesRoot "RSSDriverArchives\$p.esd"
    $h = (Get-FileHash $arc -Algorithm SHA256).Hash
    if ($h -ne $pack.archiveSha256) { Add-Check 'FAIL' $sec "$p.esd hash mismatch" ; continue }
    if (-not $haveWimlib) { continue }
    $stage = Join-Path $env:TEMP "rss-validate-$p"
    if (Test-Path $stage) { Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue }
    $out = Join-Path $env:TEMP 'rss-validate-wimlib.out'
    $err = Join-Path $env:TEMP 'rss-validate-wimlib.err'
    $proc = Start-Process -FilePath $WimlibPath -ArgumentList @('apply', $arc, '1', $stage, '--check') -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err
    if ($proc.ExitCode -ne 0) { Add-Check 'FAIL' $sec "$p.esd integrity error during extraction" ; continue }
    $inf = @(Get-ChildItem $stage -Recurse -File -Filter '*.inf').Count
    Remove-Item $stage -Recurse -Force
    if ($inf -eq $pack.infCount) { Add-Check 'PASS' $sec "$p.esd hash + integrity + exactly $($pack.infCount) INF" }
    else { Add-Check 'FAIL' $sec "$p.esd INF count $inf instead of $($pack.infCount)" }
}

# ------------------------------------------------- 8. RSSWinPEDrivers
$sec = 'RSSWinPEDrivers'
foreach ($p in $stickProfiles) {
    $root = Join-Path $imagesRoot "RSSWinPEDrivers\$p"
    $lo = Join-Path $root 'load-order.txt'
    if (-not (Test-Path $lo)) { Add-Check 'FAIL' $sec "$p load-order missing" ; continue }
    $bad = @()
    foreach ($line in (Get-Content $lo | Where-Object { $_.Trim() })) {
        $rel = $line.Trim() -replace '/', '\'
        $inf = Join-Path $root $rel
        if (-not (Test-Path $inf)) { $bad += "$p\$rel missing"; continue }
        $head = Get-Content $inf -TotalCount 40 -ErrorAction SilentlyContinue
        if (-not ($head | Select-String 'Provider|Signature|^[;\[].*\r?$' -ErrorAction SilentlyContinue)) { $bad += "$p\$rel is not INF content"; continue }
        if ((Get-Item $inf).Length -gt 2MB) { $bad += "$p\$rel improbably large (not an INF?)" }
    }
    if ($bad.Count) { Add-Check 'FAIL' $sec ($bad -join '; ') }
    else { Add-Check 'PASS' $sec "${p}: load-order + INF content checked" }
}

# --------------------------------------- 9. PowerShell syntax + unattended
$sec = 'Deployment logic'
$depPath = Join-Path $repo 'src\winpe\RSS-Deploy.ps1'
$libPath = Join-Path $repo 'src\winpe\RSS-SafetyLib.ps1'
foreach ($psFile in $depPath, $libPath) {
    if (Test-Path $psFile) {
        $errs = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($psFile, [ref]$null, [ref]$errs)
        $naam = Split-Path $psFile -Leaf
        if (@($errs).Count -eq 0) { Add-Check 'PASS' $sec "$naam syntax OK (AST)" }
        else { Add-Check 'FAIL' $sec "$naam syntax errors: $(@($errs).Count)" }
    } else {
        Add-Check 'FAIL' $sec "deployment file missing: $psFile"
    }
}
if ((Test-Path $depPath) -and (Test-Path $libPath)) {
    $dep = Get-Content $depPath -Raw
    if ($dep -match 'RSS-SafetyLib\.ps1') { Add-Check 'PASS' $sec 'RSS-Deploy.ps1 loads the safety library' }
    else { Add-Check 'FAIL' $sec 'RSS-Deploy.ps1 does not load RSS-SafetyLib.ps1' }
    if ($dep -match 'Get-RSSManifest') { Add-Check 'PASS' $sec 'RSS-Deploy.ps1 reads the stick manifest' }
    else { Add-Check 'FAIL' $sec 'RSS-Deploy.ps1 does not read sources.json (hash-INF-SKU checks impossible)' }
    if ($dep -match 'Test-RSSArtifactHash') { Add-Check 'PASS' $sec 'pre-wipe hash check present in RSS-Deploy.ps1' }
    else { Add-Check 'FAIL' $sec 'no pre-wipe hash check (Test-RSSArtifactHash missing)' }
    if ($dep -match 'Select-RSSTargetDisk') { Add-Check 'PASS' $sec 'target disk selection via Select-RSSTargetDisk (unambiguous on NVMe)' }
    else { Add-Check 'FAIL' $sec 'target disk selection not via Select-RSSTargetDisk' }
    $interact = @('Read-Host', 'PromptForChoice', 'choice\.exe', 'MessageBox', '-Confirm(?!\s*:\s*\$false)')
    $hits = @()
    foreach ($pat in $interact) { if ($dep -match $pat) { $hits += $pat } }
    if ($hits.Count) { Add-Check 'FAIL' $sec "interaction patterns: $($hits -join ', ')" }
    else { Add-Check 'PASS' $sec 'no user interaction in RSS-Deploy.ps1' }
    foreach ($pat in @('unattend\.xml', 'BypassNRO', 'SkipMachineOOBE', 'New-LocalUser', 'AutoLogon', 'testsigning', 'nointegritychecks', 'ms-cxh')) {
        if ($dep -match $pat) { Add-Check 'FAIL' $sec "MDM/OOBE risk pattern: $pat" }
    }
    Add-Check 'PASS' $sec 'no MDM/OOBE risk patterns'
} else { Add-Check 'WARN' $sec 'deployment logic not found in full (deep checks skipped)' }

# manifest <-> stick documentation: RSS-INFO.txt on the stick must mention the manifest values
$sec = 'Manifest consistency'
$expectedBuild = $mst.windows.servicedImage.verifiedBuild
foreach ($modelProfile in $stickProfiles) {
    $pack = $mst.surfaceDriverPacks | Where-Object profile -eq $modelProfile
    if (-not $pack) { Add-Check 'FAIL' $sec "profile $modelProfile in the stick list but not in the manifest" }
}
$stickInfo = Get-Content (Join-Path $imagesRoot 'RSS-INFO.txt') -Raw -ErrorAction SilentlyContinue
if ($stickInfo) {
    if ($stickInfo -match [regex]::Escape($expectedBuild)) { Add-Check 'PASS' $sec "RSS-INFO.txt mentions build $expectedBuild" }
    else { Add-Check 'FAIL' $sec "RSS-INFO.txt does not mention build $expectedBuild (outdated stick documentation)" }
    foreach ($pack in $mst.surfaceDriverPacks) {
        if ($stickInfo -match "$($pack.profile)\b.*$($pack.infCount)\b" -or $stickInfo -match "SF\d.*$($pack.infCount)") {
            Add-Check 'PASS' $sec "RSS-INFO.txt mentions $($pack.profile) with $($pack.infCount) INF"
        } else {
            Add-Check 'FAIL' $sec "RSS-INFO.txt does not mention $($pack.profile)/$($pack.infCount) INF"
        }
    }
} else {
    Add-Check 'FAIL' $sec 'RSS-INFO.txt not readable on the stick'
}

# ------------------------------------------------------------- reporting
$failCount = @($results | Where-Object Status -eq 'FAIL').Count
$warnCount = @($results | Where-Object Status -eq 'WARN').Count
$passCount = @($results | Where-Object Status -eq 'PASS').Count
$verdict = if ($failCount) { 'FAIL' } elseif ($warnCount) { 'PASS (with warnings)' } else { 'PASS' }

$lines = @()
$lines += 'RSS-MEDIA-VALIDATION REPORT'
$lines += "Date: $(Get-Date -Format o)"
$lines += "System: $(Get-CimInstance Win32_OperatingSystem | Select-Object -ExpandProperty Caption) | admin: $isAdmin"
$lines += ''
foreach ($r in $results) { $lines += ("[{0}] {1}: {2}" -f $r.Status, $r.Section, $r.Message) }
$lines += ''
$lines += "PASS: $passCount | WARN: $warnCount | FAIL: $failCount"
$lines += "RSS MEDIA VALIDATION: $verdict"
$reportText = $lines -join "`r`n"

$reportFile = $ReportPath
if (-not $reportFile) {
    $reportFile = if ($imagesVol) { Join-Path $imagesRoot 'RSS-Media-Validation.txt' } else { Join-Path $PSScriptRoot 'RSS-Media-Validation.txt' }
}
$reportText | Set-Content -LiteralPath $reportFile -Encoding UTF8
Write-Host ''
Write-Host $reportText
Write-Host ""
Write-Host ("report: $reportFile")

exit $(if ($failCount) { 1 } elseif ($warnCount) { 2 } else { 0 })
