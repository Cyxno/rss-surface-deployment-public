# =============================================================================
# RSS OOBE diagnostics - run inside the FAILING OOBE via Shift+F10:
#   wpeutil UpdateBootInfo (ignore error) - not needed; directly:
#   powershell -NoProfile -ExecutionPolicy Bypass -File <drive>:\OOBE-Diag\Collect-RSSOOBEDiag.ps1
# Read-only. Collects everything into <stick>:\OOBE-Diag\<machinename>\
# =============================================================================
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$comp = $env:COMPUTERNAME

# find a writable target directory on the stick (look for OOBE-Diag or the Images label)
$targets = @()
foreach ($d in (Get-PSDrive -PSProvider FileSystem | Where-Object DriveLetter)) {
    $root = "$($d.Root)"
    if (Test-Path (Join-Path $root 'OOBE-Diag')) { $targets += (Join-Path $root 'OOBE-Diag') }
    if ((Get-Volume -DriveLetter $d.DriveLetter -ErrorAction SilentlyContinue).FileSystemLabel -eq 'Images') { $targets += $root.TrimEnd('\') }
}
if (-not $targets) { $targets = @("$env:SystemDrive\RSS-OOBE-Diag") }
$out = Join-Path $targets[0] "$comp-$stamp"
New-Item -ItemType Directory -Force -Path $out | Out-Null
Write-Host "Diagnostics output: $out" -ForegroundColor Cyan

function Save([string]$Name, [scriptblock]$SB) {
    try {
        $r = & $SB 2>&1 | Out-String
        "$r" | Set-Content -LiteralPath (Join-Path $out $Name) -Encoding UTF8
        Write-Host "  [ok] $Name"
    } catch { "ERROR: $($_.Exception.Message)" | Set-Content (Join-Path $out $Name); Write-Host "  [error] $Name" }
}

Save '01-netconnectionprofile.txt' { Get-NetConnectionProfile | Format-List * | Out-String }
Save '02-netadapter.txt' { Get-NetAdapter | Format-Table * -AutoSize | Out-String }
Save '03-ipconfig-all.txt' { ipconfig /all }
Save '04-ncsi-registry.txt' {
    "EnableActiveProbing = $((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\NlaSvc\Parameters\Internet' -ErrorAction SilentlyContinue).EnableActiveProbing)"
    Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\NlaSvc\Parameters\Internet' | Out-String
    "--- policy ---"
    Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\NetworkConnectivityStatusIndicator' -ErrorAction SilentlyContinue | Out-String
}
Save '05-ncsi-live-probe.txt' {
    "DNS dns.msftncsi.com:"; Resolve-DnsName dns.msftncsi.com -ErrorAction Continue | Out-String
    "HTTP probe:"; (Invoke-WebRequest -Uri 'http://www.msftconnecttest.com/connecttest.txt' -UseBasicParsing -TimeoutSec 10).Content
    "HTTPS probe:"; (Invoke-WebRequest -Uri 'https://www.msftconnecttest.com/connecttest.txt' -UseBasicParsing -TimeoutSec 10).Content
}
Save '06-oobe-endpoints.txt' {
    foreach ($ep in 'login.live.com','device.login.microsoftonline.com','sls.update.microsoft.com','config.api.microsoft.com','settings-win.data.microsoft.com','www.microsoft.com') {
        "=== $ep ==="
        try { $r = Invoke-WebRequest -Uri "https://$ep/" -UseBasicParsing -TimeoutSec 10; "HTTP $($r.StatusCode)" }
        catch { "ERROR: $($_.Exception.Message)" }
    }
}
Save '07-services.txt' {
    Get-Service NlaSvc, netprofm, WlanSvc, wlidsvc, WManSvc, EventLog, Dot3Svc, BFE, Dhcp, Dnscache, mpssvc, WebClient, WSearch | Format-Table Name, Status, StartType -AutoSize | Out-String
}
Save '08-oobe-registry.txt' {
    Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE' -ErrorAction SilentlyContinue | Out-String
    "--- SYSTEM\Setup ---"
    Get-ItemProperty 'HKLM:\SYSTEM\Setup' -ErrorAction SilentlyContinue | Select-Object SystemSetupInProgress, SetupType, CmdLine, OOBEInProgress | Out-String
}
Save '09-cxh-eventlog.txt' {
    Get-WinEvent -LogName 'Microsoft-Windows-CloudExperienceHost/Operational' -MaxEvents 80 -ErrorAction SilentlyContinue | Format-List TimeCreated, Id, LevelDisplayName, Message | Out-String
}
Save '10-ncsi-eventlog.txt' {
    Get-WinEvent -LogName 'Microsoft-Windows-NCI/Operational' -MaxEvents 60 -ErrorAction SilentlyContinue | Format-List TimeCreated, Id, Message | Out-String
    Get-WinEvent -LogName 'Microsoft-Windows-NLA/Operational' -MaxEvents 40 -ErrorAction SilentlyContinue | Format-List TimeCreated, Id, Message | Out-String
}
Save '11-wlan-eventlog.txt' {
    Get-WinEvent -LogName 'Microsoft-Windows-WLAN-AutoConfig/Operational' -MaxEvents 40 -ErrorAction SilentlyContinue | Format-Table TimeCreated, Id, Message -AutoSize -Wrap | Out-String
}
Save '12-appx-cxh.txt' {
    Get-AppxPackage -AllUsers Microsoft.Windows.CloudExperienceHost -ErrorAction SilentlyContinue | Format-List * | Out-String
    Get-AppxPackage -AllUsers *OOBE* -ErrorAction SilentlyContinue | Out-String
}
Save '13-netsh-show.txt' {
    netsh interface ipv4 show interfaces
    netsh wlan show interfaces
    netsh wlan show profiles
}
Save '14-time-tls.txt' {
    "time: $(Get-Date -Format o) (UTC: $((Get-Date).ToUniversalTime().ToString('o')))"
    "TLS: $([Net.ServicePointManager]::SecurityProtocol)"
    w32tm /query /status 2>&1 | Out-String
}
# Copy Panther/OOBE log files
$logDirs = 'C:\Windows\Panther', 'C:\Windows\OOBE\Logs', 'C:\Windows\Logs\MoSetup'
foreach ($ld in $logDirs) {
    if (Test-Path $ld) {
        $dest = Join-Path $out (Split-Path $ld -Leaf)
        Copy-Item $ld $dest -Recurse -Force -ErrorAction SilentlyContinue
    }
}
Write-Host ""
Write-Host "DONE. Copy this directory: $out" -ForegroundColor Green
