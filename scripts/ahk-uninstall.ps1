# =====================================================================
# ahk-uninstall.ps1  —  Remove both AutoHotkey versions from the machine
#
# WHAT THIS DOES
#   Uninstalls AutoHotkey v1 and v2 by their MSI/SFX product codes, stops
#   every interpreter process, and removes the generated startup launcher.
#   The three shipped .ahk scripts under autohotkey\ stay in the repo —
#   they are part of the repository, not part of the install.
#
#   This is the "uninstall" half of the AutoHotkey lifecycle; use
#   ahk-cleanup.ps1 for the "remove my leftovers" half.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File ahk-uninstall.ps1
# Exit codes:
#   0  both versions removed (or already absent)
#   1  one version could not be removed
# =====================================================================

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) -Parent
. (Join-Path $RepoRoot 'scripts\common.ps1')

function Say($msg, $color = 'Gray') { Write-Host $msg -ForegroundColor $color }

# Product codes from Install-Common.ps1's Install-AutoHotkeyV1/V2 wrappers.
$v1Code = '{5173E1C8-B594-4B5D-8E5A-3B9E5B2C0A11}'
$v2Code = '{A19A6C3A-8E2D-4E5F-9C3D-6B1F8A7E2C44}'

$failures = @()

function Remove-AhkProduct {
    param([string]$Code, [string]$Label)

    $installed = Get-InstalledMsiVersionSafe -ProductCode $Code
    if (-not $installed) {
        Say "[ahk-uninstall] $Label is not installed; skipping" 'DarkGray'
        return $true
    }

    Say "[ahk-uninstall] removing $Label ($installed) ..." 'Cyan'
    try {
        # msiexec with the uninstall code, quiet, no restart prompt.
        $proc = Start-Process -FilePath 'msiexec.exe' `
            -ArgumentList "/x", $Code, "/qn", "/norestart" `
            -Wait -PassThru -WindowStyle Hidden
        if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 1605) {
            Say "[ahk-uninstall] msiexec returned $($proc.ExitCode) for $Label" 'Yellow'
            $failures += $Label
            return $false
        }
    } catch {
        Say "[ahk-uninstall] could not run msiexec for $Label : $($_.Exception.Message)" 'Red'
        $failures += $Label
        return $false
    }

    Say "[ahk-uninstall] $Label removed" 'Green'
    return $true
}

# A tolerant wrapper: Get-InstalledMsiVersion is defined in Install-Common,
# which this script deliberately does not load (it is the installer library
# and would drag in unrelated state). Query the registry directly instead.
function Get-InstalledMsiVersionSafe {
    param([string]$ProductCode)

    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($k in $keys) {
        try {
            $item = Get-ItemProperty $k -ErrorAction SilentlyContinue |
                Where-Object { $_.PSChildName -ieq $ProductCode }
            if ($item) { return ($item.DisplayVersion) }
        } catch { }
    }
    return $null
}

# --- stop every interpreter before uninstalling -------------------------
# Both MSIs refuse to remove files a running process has open, so the
# interpreters must exit first. Only processes from the AutoHotkey install
# directory are stopped.
Say '[ahk-uninstall] stopping AutoHotkey processes ...' 'Cyan'
foreach ($name in 'AutoHotkey', 'AutoHotkey64') {
    Get-Process -Name $name -ErrorAction SilentlyContinue | ForEach-Object {
        $inInstallDir = $_.Path -and ($_.Path -like "$env:ProgramFiles\AutoHotkey\*")
        if ($inInstallDir) {
            try { $_.Kill(); $_.WaitForExit(3000) | Out-Null } catch { }
        }
    }
}

Remove-AhkProduct -Code $v1Code -Label 'AutoHotkey v1'
Remove-AhkProduct -Code $v2Code -Label 'AutoHotkey v2'

# --- remove the generated startup launcher ------------------------------
# The .ahk scripts live in the repo and stay. Only the generated launcher
# belongs to the install, and leaving it behind would point the next logon
# at interpreters that no longer exist.
$startup = Join-Path ([Environment]::GetFolderPath('Startup')) 'AppRunner.vbs'
if (Test-Path -LiteralPath $startup) {
    Remove-Item -LiteralPath $startup -Force -ErrorAction SilentlyContinue
    Say '[ahk-uninstall] removed the generated AppRunner.vbs from Startup' 'DarkGray'
}

if ($failures.Count) {
    Say ''
    Say "[ahk-uninstall] could not remove: $($failures -join ', ')" 'Red'
    Say '[ahk-uninstall] close any running AutoHotkey script and try again.' 'Yellow'
    exit 1
}

Say ''
Say '[ahk-uninstall] DONE - both AutoHotkey versions are gone.' 'Green'
exit 0
