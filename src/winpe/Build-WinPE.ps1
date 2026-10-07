$ErrorActionPreference = 'Stop'
$base = 'C:\ADK\Assessment and Deployment Kit'
$dism = Join-Path $base 'Deployment Tools\amd64\DISM\dism.exe'
$source = Join-Path $base 'Windows Preinstallation Environment\amd64\en-us\winpe.wim'
$oc = Join-Path $base 'Windows Preinstallation Environment\amd64\WinPE_OCs'
$build = Split-Path -Parent $MyInvocation.MyCommand.Path
$wim = Join-Path $build 'boot-adk-full.wim'
$mount = Join-Path $build 'mount'
$log = Join-Path $build 'Build-WinPE.log'
$status = Join-Path $build 'Build-WinPE.status'

"START $(Get-Date -Format o)" | Set-Content -LiteralPath $log -Encoding UTF8
Remove-Item -LiteralPath $status -Force -ErrorAction SilentlyContinue

function Run-Dism([string[]]$DismArguments) {
    "DISM $($DismArguments -join ' ')" | Add-Content -LiteralPath $log -Encoding UTF8
    & $dism @DismArguments 2>&1 | Tee-Object -FilePath $log -Append
    if ($LASTEXITCODE -ne 0) { throw "DISM exitcode $LASTEXITCODE" }
}

try {
    if (Test-Path -LiteralPath $mount) {
        & $dism /English /Cleanup-Mountpoints 2>&1 | Add-Content -LiteralPath $log -Encoding UTF8
        Remove-Item -LiteralPath $mount -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $mount -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $wim -Force
    Run-Dism @('/English','/Mount-Image',"/ImageFile:$wim",'/Index:1',"/MountDir:$mount")

    foreach ($name in 'WinPE-WMI','WinPE-NetFX','WinPE-Scripting','WinPE-PowerShell','WinPE-StorageWMI','WinPE-DismCmdlets') {
        Run-Dism @('/English',"/Image:$mount",'/Add-Package',"/PackagePath:$oc\$name.cab")
        Run-Dism @('/English',"/Image:$mount",'/Add-Package',"/PackagePath:$oc\en-us\${name}_en-us.cab")
    }
    Run-Dism @('/English',"/Image:$mount",'/Set-ScratchSpace:512')

    New-Item -ItemType Directory -Path (Join-Path $mount 'Deploy') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $mount 'Tools') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $build 'RSS-Deploy.ps1') -Destination (Join-Path $mount 'Deploy\RSS-Deploy.ps1') -Force
    Copy-Item -LiteralPath (Join-Path $build 'RSS-SafetyLib.ps1') -Destination (Join-Path $mount 'Deploy\RSS-SafetyLib.ps1') -Force
    Copy-Item -LiteralPath (Join-Path $build 'startnet.cmd') -Destination (Join-Path $mount 'Windows\System32\startnet.cmd') -Force
    foreach ($tool in 'wimlib-imagex.exe','libwim-15.dll') {
        $toolSource = Join-Path $build $tool
        if (-not (Test-Path -LiteralPath $toolSource)) { throw "wimlib component missing next to Build-WinPE.ps1: $tool" }
        Copy-Item -LiteralPath $toolSource -Destination (Join-Path $mount "Tools\$tool") -Force
    }

    $required = @(
        'Windows\System32\WindowsPowerShell\v1.0\powershell.exe',
        'Windows\System32\WindowsPowerShell\v1.0\Modules\Dism\Dism.psd1',
        'Windows\System32\WindowsPowerShell\v1.0\Modules\Storage\Storage.psd1',
        'Windows\System32\Dism\DmiProvider.dll',
        'Deploy\RSS-Deploy.ps1',
        'Deploy\RSS-SafetyLib.ps1',
        'Tools\wimlib-imagex.exe',
        'Tools\libwim-15.dll'
    )
    foreach ($relativePath in $required) {
        if (-not (Test-Path -LiteralPath (Join-Path $mount $relativePath))) { throw "Missing in WIM: $relativePath" }
    }

    Run-Dism @('/English','/Unmount-Image',"/MountDir:$mount",'/Commit','/CheckIntegrity')
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $wim).Hash
    "SUCCESS`nHASH=$hash`nWIM=$wim" | Set-Content -LiteralPath $status -Encoding ASCII
    "SUCCESS HASH=$hash" | Add-Content -LiteralPath $log -Encoding UTF8
    exit 0
}
catch {
    $_ | Out-String | Add-Content -LiteralPath $log -Encoding UTF8
    & $dism /English /Unmount-Image "/MountDir:$mount" /Discard 2>&1 | Add-Content -LiteralPath $log -Encoding UTF8
    "FAILED`n$($_.Exception.Message)" | Set-Content -LiteralPath $status -Encoding ASCII
    exit 1
}

