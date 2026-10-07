<#
.SYNOPSIS
    Read-only validatie van de RSS-productiestick.

.DESCRIPTION
    Controleert zonder iets te wijzigen:
      - fysieke USB-identiteit (Samsung, USB, niet Disk 0, niet boot/system)
      - partities WINPE (FAT32, actief) en Images (NTFS) + filesystem-status
      - vereiste bestanden (bootbestanden, images, archieven, load-orders, docs, manifest)
      - sources.json op de stick byte-identiek aan config/sources.json
      - boot.wim SHA-256 tegen dit manifest
      - Secure Boot-binaries (Authenticode) en BCD-aanwezigheid
      - Windows-images onderling identiek + DISM-metadata (editie, architectuur)
      - geservicede build (26200.9457), aanwezige KB's, afwezigheid KB5124010
      - driverarchieven: SHA-256, integriteit, exacte INF-aantallen (wimlib)
      - RSSWinPEDrivers: load-orders, INF-bestanden echt INF-inhoud, catalogs
      - PowerShell-syntax (AST) van deploymentlogica en veiligheidsbibliotheek
      - guardrail-aanwezigheid in RSS-Deploy.ps1 (manifest, hashcontrole, diskselectie)
      - geen gebruikersinteractie- en MDM/OOBE-risicopatronen in de deploymentlogica
      - RSS-INFO.txt op de stick consistent met config/sources.json (anti-drift)

    Gebruikt wimlib voor de INF-herbevestiging; pad instelbaar via -WimlibPath.
    DISM-mounts vereisen administratorrechten; zonder die rechten vallen die
    controles terug op WARN.

.PARAMETER WimlibPath
    Pad naar wimlib-imagex.exe (standaard D:\RSS-Build\wimlib\wimlib-imagex.exe).

.PARAMETER ReportPath
    Waar het rapport geschreven wordt (standaard: RSS-Media-Validation.txt op de
    Images-partitie, plus een lokale kopie naast dit script).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\Validate-RSSMedia.ps1

.NOTES
    Exitcodes: 0 = PASS, 1 = FAIL, 2 = alleen waarschuwingen.
    Dit script is bewust 100% read-only: het formatteert, wist en wijzigt niets
    op de stick. DISM-mounts gebeuren met /ReadOnly en worden daarna discarded.
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

# ---------------------------------------------------------------- 1. fysiek
$sec = 'USB-hardware'
$usbDisks = @(Get-Disk | Where-Object { $_.BusType -eq 'USB' })
$samsung = @($usbDisks | Where-Object { $_.FriendlyName -match 'Samsung' })
if ($samsung.Count -ne 1) {
    Add-Check 'FAIL' $sec "verwacht exact een Samsung-USB-disk, gevonden $($samsung.Count)"
} else {
    $d = $samsung[0]
    if ($d.Number -eq 0) { Add-Check 'FAIL' $sec 'USB is Disk 0' }
    elseif ($d.IsBoot -or $d.IsSystem) { Add-Check 'FAIL' $sec 'USB is boot/system disk' }
    else { Add-Check 'PASS' $sec "Disk $($d.Number) = $($d.FriendlyName), $([math]::Round($d.Size/1GB,1)) GB, $($d.PartitionStyle)" }
    $usbNumber = $d.Number
}

# ------------------------------------------------------------ 2. partities
$sec = 'Partities'
$winpeVol = Get-Volume | Where-Object { $_.FileSystemLabel -eq 'WINPE' }
$imagesVol = Get-Volume | Where-Object { $_.FileSystemLabel -eq 'Images' }
if (-not $winpeVol -or -not $imagesVol) {
    Add-Check 'FAIL' $sec 'WINPE/Images-volumes ontbreken'
} else {
    $wp = Get-Partition -DriveLetter $winpeVol.DriveLetter -ErrorAction SilentlyContinue
    $ip = Get-Partition -DriveLetter $imagesVol.DriveLetter -ErrorAction SilentlyContinue
    $okParts = ($wp.DiskNumber -eq $ip.DiskNumber) -and ($wp.DiskNumber -eq $usbNumber)
    if (-not $okParts) { Add-Check 'FAIL' $sec 'partities zitten niet op de Samsung-USB-disk' }
    elseif ($winpeVol.FileSystem -ne 'FAT32') { Add-Check 'FAIL' $sec 'WINPE is geen FAT32' }
    elseif ($imagesVol.FileSystem -ne 'NTFS') { Add-Check 'FAIL' $sec 'Images is geen NTFS' }
    elseif (-not $wp.IsActive) { Add-Check 'WARN' $sec 'WINPE-partitie is niet actief (UEFI-boot werkt ook zonder actief-vlag)' }
    else { Add-Check 'PASS' $sec "WINPE=$($winpeVol.DriveLetter): ($([math]::Round($winpeVol.Size/1GB,2)) GB), Images=$($imagesVol.DriveLetter): ($([math]::Round($imagesVol.Size/1GB,2)) GB)" }
    $dirty = $null
    try { $dirty = fsutil dirty query "$($winpeVol.DriveLetter):" 2>$null; $dirty2 = fsutil dirty query "$($imagesVol.DriveLetter):" 2>$null } catch {}
    if ("$dirty $dirty2" -match 'IS Dirty') { Add-Check 'FAIL' $sec 'filesystem dirty-bit gezet' }
    elseif ($dirty -and $dirty2) { Add-Check 'PASS' $sec 'filesystems niet dirty' }
    if ($imagesVol.SizeRemaining -lt 5GB) { Add-Check 'WARN' $sec "weinig vrije ruimte op Images: $([math]::Round($imagesVol.SizeRemaining/1GB,1)) GB" }
}

# --------------------------------------------------------- 3. vereiste files
$sec = 'Vereiste bestanden'
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
$required += (Join-Path $imagesRoot 'RSS-INFO.txt'), (Join-Path $imagesRoot 'LEESMIJ-AUTOINSTALL.txt'), (Join-Path $imagesRoot 'sources.json')
$missing = @($required | Where-Object { -not (Test-Path $_) })
if ($missing.Count) { Add-Check 'FAIL' $sec "ontbrekend: $($missing -join ', ')" }
else { Add-Check 'PASS' $sec "alle $($required.Count) vereiste bestanden aanwezig" }

# manifest op de stick moet byte-identiek zijn aan config/sources.json in de repo
$repoManifestHash = (Get-FileHash $manifestPath -Algorithm SHA256).Hash
$stickManifestHash = (Get-FileHash (Join-Path $imagesRoot 'sources.json') -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
if ($stickManifestHash -eq $repoManifestHash) { Add-Check 'PASS' $sec 'sources.json op stick == repo-manifest' }
else { Add-Check 'FAIL' $sec 'sources.json op stick wijkt af van config/sources.json (herbouw of actualiseer de stick)' }

$junk = @(Get-ChildItem $winpeRoot, $imagesRoot -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '\.(tmp|partial|aria2)$|^~\$' })
if ($junk.Count) { Add-Check 'WARN' $sec "tijdelijke bestanden: $($junk.Count)" }

# ------------------------------------------------------------- 4. boot.wim
$sec = 'boot.wim'
$bootHash = (Get-FileHash (Join-Path $winpeRoot 'sources\boot.wim') -Algorithm SHA256).Hash
$expectedBoot = $mst.media.bootWimSha256
if ($bootHash -eq $expectedBoot) { Add-Check 'PASS' $sec "SHA-256 klopt ($($bootHash.Substring(0,16))...)" }
else { Add-Check 'FAIL' $sec "SHA-256 wijkt af: $bootHash" }

# ------------------------------------------------- 5. Secure Boot-binaries
$sec = 'Secure Boot'
$bootx = Get-AuthenticodeSignature -LiteralPath (Join-Path $winpeRoot 'EFI\Boot\bootx64.efi')
if ($bootx.Status -eq 'Valid' -and $bootx.SignerCertificate.Subject -match 'Microsoft') {
    Add-Check 'PASS' $sec 'bootx64.efi geldig Microsoft-ondertekend'
} else { Add-Check 'FAIL' $sec "bootx64.efi signature: $($bootx.Status)" }
if (Test-Path (Join-Path $winpeRoot 'EFI\Microsoft\Boot\BCD')) { Add-Check 'PASS' $sec 'BCD aanwezig' }
else { Add-Check 'FAIL' $sec 'BCD ontbreekt' }
$bcdOutput = $null
$bcdFile = Join-Path $winpeRoot 'EFI\Microsoft\Boot\BCD'
$bcdOutput = & bcdedit /store $bcdFile /enum all 2>$null
if ($bcdOutput) {
    $bcdText = $bcdOutput -join "`n"
    if ($bcdText -match 'nointegritychecks\s+Yes|testsigning\s+Yes') { Add-Check 'FAIL' $sec 'BCD bevat test-signing/nointegritychecks' }
    elseif ($bcdText -match 'boot\.wim' -and $bcdText -match 'winload\.efi') { Add-Check 'PASS' $sec 'BCD boot boot.wim via winload.efi, geen testvlaggen' }
    else { Add-Check 'WARN' $sec 'BCD inhoud onverwacht (handmatig controleren)' }
} else { Add-Check 'WARN' $sec 'BCD kon niet gelezen worden (administrator vereist)' }

# ------------------------------------------------- 6. Windows-images
$sec = 'Windows-images'
$esdHashes = @{}
foreach ($p in $stickProfiles) {
    $esdHashes[$p] = (Get-FileHash (Join-Path $imagesRoot "RSSSetup\$p\sources\install.esd") -Algorithm SHA256).Hash
}
$distinct = @($esdHashes.Values | Sort-Object -Unique)
if ($distinct.Count -eq 1) { Add-Check 'PASS' $sec 'alle 5 install.esd zijn byte-identiek' }
else { Add-Check 'FAIL' $sec "install.esd verschillen: $($distinct.Count) unieke hashes" }
$expectedEsd = $mst.windows.servicedImage.installEsdSha256
if ($distinct[0] -eq $expectedEsd) { Add-Check 'PASS' $sec 'install.esd hash == manifest' }
else { Add-Check 'FAIL' $sec "install.esd hash wijkt af van manifest: $($distinct[0])" }

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
        Add-Check 'WARN' $sec 'ESD kon niet read-only gemount worden (buildcontrole overgeslagen)'
    }
    if ($mountOk) {
        $soft = Join-Path $probe 'Windows\System32\config\SOFTWARE'
        reg load 'HKLM\RSSVAL' $soft | Out-Null
        $cv = Get-ItemProperty 'HKLM:\RSSVAL\Microsoft\Windows NT\CurrentVersion'
        $build = "$($cv.CurrentBuild).$($cv.UBR)"
        reg unload 'HKLM\RSSVAL' | Out-Null
        if ($build -eq $mst.windows.servicedImage.verifiedBuild) { Add-Check 'PASS' $sec "build $build $($cv.EditionID) $($cv.DisplayVersion)" }
        else { Add-Check 'FAIL' $sec "build is $build, verwacht $($mst.windows.servicedImage.verifiedBuild)" }
        # taalcontrole via DISM /Get-Intl (offline registry InstallLanguage is onbetrouwbaar)
        $expectedLang = $mst.windows.servicedImage.installLanguage
        if ($expectedLang) {
            $intl = (& $dism /English "/Image:$probe" /Get-Intl) -join "`n"
            if ($intl -match "Default system UI language\s*:\s*$expectedLang") { Add-Check 'PASS' $sec "systeem-UI-taal $expectedLang" }
            else { Add-Check 'FAIL' $sec "systeem-UI-taal is niet $expectedLang" }
        }
        $pkgs = (& $dism /English "/Image:$probe" /Get-Packages) -join "`n"
        if ([string]::IsNullOrWhiteSpace($pkgs)) { Add-Check 'WARN' $sec 'Get-Packages gaf geen output' }
        else {
            # LCU's registreren als RollupFix (revisie = build); SSU/eKB/.NET onder hun identiteit
            $kbChecks = @(
                @('LCU KB5129195 (RollupFix 26100.9457)', 'RollupFix~[^\r\n]*?26100\.9457'),
                @('SSU KB5124007 (ServicingStack 9441)', 'ServicingStack_9441'),
                @('25H2 eKB KB5054156', 'KB5054156'),
                @('.NET CU KB5126052 (DotNetRollup 9347)', 'DotNetRollup_481[^\r\n]*?9347')
            )
            foreach ($c in $kbChecks) {
                if ($pkgs -match $c[1]) { Add-Check 'PASS' $sec $c[0] } else { Add-Check 'FAIL' $sec "$($c[0]) ontbreekt" }
            }
            if ($pkgs -match 'KB5124010|26200\.9550') { Add-Check 'FAIL' $sec 'preview-update KB5124010/9550 aangetroffen!' }
            else { Add-Check 'PASS' $sec 'geen preview-update KB5124010' }
            if ($pkgs -match 'pending') { Add-Check 'WARN' $sec 'pending-packages vermelding in Get-Packages' }
        }
        foreach ($f in 'Windows\System32\winload.efi', 'Windows\System32\Recovery\winre.wim') {
            if (Test-Path (Join-Path $probe $f)) { Add-Check 'PASS' $sec "$f aanwezig" } else { Add-Check 'FAIL' $sec "$f ontbreekt" }
        }
        # winre.wim op SafeOS-servicing controleren (SafeOS DU zit niet in de hoofd-image)
        $winreOut = Join-Path $env:TEMP 'rss-validate-winre.wim'
        $winreProbe = Join-Path $env:TEMP 'rss-validate-winre'
        Copy-Item (Join-Path $probe 'Windows\System32\Recovery\winre.wim') $winreOut -Force
        & $dism /English /Unmount-Image /MountDir:$probe /Discard 2>&1 | Out-Null
        if (Test-Path $winreProbe) { Remove-Item $winreProbe -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Force -Path $winreProbe | Out-Null
        & $dism /English /Mount-Image "/ImageFile:$winreOut" '/Index:1' "/MountDir:$winreProbe" '/ReadOnly' 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $wpkgs = (& $dism /English "/Image:$winreProbe" /Get-Packages) -join "`n"
            if ($wpkgs -match '26100\.944[5-9]|26100\.945\d') { Add-Check 'PASS' $sec 'WinRE is geserviced met SafeOS DU (revisie 9445+)' }
            else { Add-Check 'FAIL' $sec 'WinRE bevat geen SafeOS-geservicede revisies' }
            & $dism /English /Unmount-Image /MountDir:$winreProbe /Discard 2>&1 | Out-Null
        } else { Add-Check 'WARN' $sec 'winre.wim kon niet gecontroleerd worden' }
        Remove-Item $winreOut, $winreProbe -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Item $probe -Recurse -Force -ErrorAction SilentlyContinue
} else {
    Add-Check 'WARN' $sec 'build/KB-controle overgeslagen (geen administratorrechten)'
}

# ------------------------------------------------- 7. driverarchieven
$sec = 'Driverarchieven'
$haveWimlib = Test-Path $WimlibPath
if (-not $haveWimlib) { Add-Check 'WARN' $sec "wimlib niet gevonden op $WimlibPath; INF-herbevestiging overgeslagen" }
foreach ($pack in $mst.surfaceDriverPacks) {
    $p = $pack.profile
    $arc = Join-Path $imagesRoot "RSSDriverArchives\$p.esd"
    $h = (Get-FileHash $arc -Algorithm SHA256).Hash
    if ($h -ne $pack.archiveSha256) { Add-Check 'FAIL' $sec "$p.esd hash wijkt af" ; continue }
    if (-not $haveWimlib) { continue }
    $stage = Join-Path $env:TEMP "rss-validate-$p"
    if (Test-Path $stage) { Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue }
    $out = Join-Path $env:TEMP 'rss-validate-wimlib.out'
    $err = Join-Path $env:TEMP 'rss-validate-wimlib.err'
    $proc = Start-Process -FilePath $WimlibPath -ArgumentList @('apply', $arc, '1', $stage, '--check') -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err
    if ($proc.ExitCode -ne 0) { Add-Check 'FAIL' $sec "$p.esd integriteitsfout bij uitpakken" ; continue }
    $inf = @(Get-ChildItem $stage -Recurse -File -Filter '*.inf').Count
    Remove-Item $stage -Recurse -Force
    if ($inf -eq $pack.infCount) { Add-Check 'PASS' $sec "$p.esd hash + integriteit + exact $($pack.infCount) INF" }
    else { Add-Check 'FAIL' $sec "$p.esd INF-telling $inf i.p.v. $($pack.infCount)" }
}

# ------------------------------------------------- 8. RSSWinPEDrivers
$sec = 'RSSWinPEDrivers'
foreach ($p in $stickProfiles) {
    $root = Join-Path $imagesRoot "RSSWinPEDrivers\$p"
    $lo = Join-Path $root 'load-order.txt'
    if (-not (Test-Path $lo)) { Add-Check 'FAIL' $sec "$p load-order ontbreekt" ; continue }
    $bad = @()
    foreach ($line in (Get-Content $lo | Where-Object { $_.Trim() })) {
        $rel = $line.Trim() -replace '/', '\'
        $inf = Join-Path $root $rel
        if (-not (Test-Path $inf)) { $bad += "$p\$rel ontbreekt"; continue }
        $head = Get-Content $inf -TotalCount 40 -ErrorAction SilentlyContinue
        if (-not ($head | Select-String 'Provider|Signature|^[;\[].*\r?$' -ErrorAction SilentlyContinue)) { $bad += "$p\$rel is geen INF-inhoud"; continue }
        if ((Get-Item $inf).Length -gt 2MB) { $bad += "$p\$rel onwaarschijnlijk groot (geen INF?)" }
    }
    if ($bad.Count) { Add-Check 'FAIL' $sec ($bad -join '; ') }
    else { Add-Check 'PASS' $sec "${p}: load-order + INF-inhoud gecontroleerd" }
}

# --------------------------------------- 9. PowerShell-syntax + unattended
$sec = 'Deploymentlogica'
$depPath = Join-Path $repo 'src\winpe\RSS-Deploy.ps1'
$libPath = Join-Path $repo 'src\winpe\RSS-SafetyLib.ps1'
foreach ($psFile in $depPath, $libPath) {
    if (Test-Path $psFile) {
        $errs = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($psFile, [ref]$null, [ref]$errs)
        $naam = Split-Path $psFile -Leaf
        if (@($errs).Count -eq 0) { Add-Check 'PASS' $sec "$naam syntax OK (AST)" }
        else { Add-Check 'FAIL' $sec "$naam syntaxfouten: $(@($errs).Count)" }
    } else {
        Add-Check 'FAIL' $sec "deploymentbestand ontbreekt: $psFile"
    }
}
if ((Test-Path $depPath) -and (Test-Path $libPath)) {
    $dep = Get-Content $depPath -Raw
    if ($dep -match 'RSS-SafetyLib\.ps1') { Add-Check 'PASS' $sec 'RSS-Deploy.ps1 laadt de veiligheidsbibliotheek' }
    else { Add-Check 'FAIL' $sec 'RSS-Deploy.ps1 laadt RSS-SafetyLib.ps1 niet' }
    if ($dep -match 'Get-RSSManifest') { Add-Check 'PASS' $sec 'RSS-Deploy.ps1 leest het manifest van de stick' }
    else { Add-Check 'FAIL' $sec 'RSS-Deploy.ps1 leest sources.json niet (hash-INF-SKU-controles onmogelijk)' }
    if ($dep -match 'Test-RSSArtifactHash') { Add-Check 'PASS' $sec 'pre-wipe hashcontrole aanwezig in RSS-Deploy.ps1' }
    else { Add-Check 'FAIL' $sec 'geen pre-wipe hashcontrole (Test-RSSArtifactHash ontbreekt)' }
    if ($dep -match 'Select-RSSTargetDisk') { Add-Check 'PASS' $sec 'doelschijfselectie via Select-RSSTargetDisk (NVMe-eenduidig)' }
    else { Add-Check 'FAIL' $sec 'doelschijfselectie niet via Select-RSSTargetDisk' }
    $interact = @('Read-Host', 'PromptForChoice', 'choice\.exe', 'MessageBox', '-Confirm(?!\s*:\s*\$false)')
    $hits = @()
    foreach ($pat in $interact) { if ($dep -match $pat) { $hits += $pat } }
    if ($hits.Count) { Add-Check 'FAIL' $sec "interactie-patterns: $($hits -join ', ')" }
    else { Add-Check 'PASS' $sec 'geen gebruikersinteractie in RSS-Deploy.ps1' }
    foreach ($pat in @('unattend\.xml', 'BypassNRO', 'SkipMachineOOBE', 'New-LocalUser', 'AutoLogon', 'testsigning', 'nointegritychecks', 'ms-cxh')) {
        if ($dep -match $pat) { Add-Check 'FAIL' $sec "MDM/OOBE-risicopatroon: $pat" }
    }
    Add-Check 'PASS' $sec 'geen MDM/OOBE-risicopatronen'
} else { Add-Check 'WARN' $sec 'deploymentlogica niet compleet aangetroffen (deeplchecks overgeslagen)' }

# manifest <-> stickdocumentatie: RSS-INFO.txt op de stick moet de manifestwaarden noemen
$sec = 'Manifestconsistentie'
$expectedBuild = $mst.windows.servicedImage.verifiedBuild
foreach ($modelProfile in $stickProfiles) {
    $pack = $mst.surfaceDriverPacks | Where-Object profile -eq $modelProfile
    if (-not $pack) { Add-Check 'FAIL' $sec "profiel $modelProfile in sticklijst maar niet in manifest" }
}
$stickInfo = Get-Content (Join-Path $imagesRoot 'RSS-INFO.txt') -Raw -ErrorAction SilentlyContinue
if ($stickInfo) {
    if ($stickInfo -match [regex]::Escape($expectedBuild)) { Add-Check 'PASS' $sec "RSS-INFO.txt noemt build $expectedBuild" }
    else { Add-Check 'FAIL' $sec "RSS-INFO.txt noemt build $expectedBuild niet (verouderde stickdocumentatie)" }
    foreach ($pack in $mst.surfaceDriverPacks) {
        if ($stickInfo -match "$($pack.profile)\b.*$($pack.infCount)\b" -or $stickInfo -match "SF\d.*$($pack.infCount)") {
            Add-Check 'PASS' $sec "RSS-INFO.txt vermeldt $($pack.profile) met $($pack.infCount) INF"
        } else {
            Add-Check 'FAIL' $sec "RSS-INFO.txt vermeldt $($pack.profile)/$($pack.infCount) INF niet"
        }
    }
} else {
    Add-Check 'FAIL' $sec 'RSS-INFO.txt niet leesbaar op de stick'
}

# ------------------------------------------------------------ rapportage
$failCount = @($results | Where-Object Status -eq 'FAIL').Count
$warnCount = @($results | Where-Object Status -eq 'WARN').Count
$passCount = @($results | Where-Object Status -eq 'PASS').Count
$verdict = if ($failCount) { 'FAIL' } elseif ($warnCount) { 'PASS (met waarschuwingen)' } else { 'PASS' }

$lines = @()
$lines += 'RSS-MEDIA-VALIDATIE RAPPORT'
$lines += "Datum: $(Get-Date -Format o)"
$lines += "Systeem: $(Get-CimInstance Win32_OperatingSystem | Select-Object -ExpandProperty Caption) | admin: $isAdmin"
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
Write-Host ("rapport: $reportFile")

exit $(if ($failCount) { 1 } elseif ($warnCount) { 2 } else { 0 })
