#Requires -Version 5.1
<#
    .SYNOPSIS
        Uninstall komorebi + whkd (+ optionally YASB and AutoHotkey) completely.

    .DESCRIPTION
        1. stops and removes the autostart scheduled tasks + watchdog
        2. stops the running komorebi / whkd / runner processes
        3. uninstalls the komorebi and whkd packages (MSI / registry)

        Config files are deliberately LEFT in place. Run
        cleanup-komorebi-whkd.ps1 afterwards to remove those too.

    .NOTES
        Reversible?  NO (the software is removed). Configs stay, so a
        re-install restores your setup via IMPORT-CONFIG.bat.
#>
[CmdletBinding()]
param(
    [switch] $KeepBinaries,

    # What to remove. Default keeps the original behaviour (komorebi + whkd).
    #   all               komorebi + whkd + YASB + AutoHotkey
    #   komorebi-whkd     komorebi + whkd only
    #   yasb              YASB only
    #   autohotkey        AutoHotkey v1 + v2 only
    [ValidateSet('all', 'komorebi-whkd', 'yasb', 'autohotkey')]
    [string] $Scope = 'komorebi-whkd'
)

$ErrorActionPreference = 'Continue'

# The scheduled tasks belong to the komorebi family; YASB uses its own
# autostart (yasbc enable-autostart / a Run key), AutoHotkey none.
$Tasks = @('Komorebi', 'KomorebiWatchdog')

# Which ARP DisplayName patterns each scope uninstalls, and which processes it
# stops. The `autohotkey` entry below matches the v1/v2 display names written
# by the two committed setups ("AutoHotkey 1.1.30.00", "AutoHotkey 2.0.12").
$patterns = switch ($Scope) {
    'all'             { @('komorebi|whkd|YASB|AutoHotkey') }
    'komorebi-whkd'   { @('komorebi|whkd') }
    'yasb'            { @('YASB') }
    'autohotkey'      { @('AutoHotkey') }
}
$procs = switch ($Scope) {
    'all'             { @('komorebi', 'whkd', 'komorebi-bar', 'yasb', 'yasbc', 'AutoHotkey', 'AutoHotkey64') }
    'komorebi-whkd'   { @('komorebi', 'whkd', 'komorebi-bar') }
    'yasb'            { @('yasb', 'yasbc') }
    'autohotkey'      { @('AutoHotkey', 'AutoHotkey64') }
}

function Say($msg, $color = 'Gray') { Write-Host $msg -ForegroundColor $color }

Say ''
Say '=== 1/4  removing autostart (scheduled tasks) ===' 'Cyan'
# The tasks only exist for the komorebi family. Nothing to do for yasb/autohotkey.
if ($Scope -ne 'yasb' -and $Scope -ne 'autohotkey') {
    foreach ($t in $Tasks) {
        if (Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue) {
            try {
                Unregister-ScheduledTask -TaskName $t -Confirm:$false
                Say "  removed task '$t'" 'Green'
            } catch { Say "  could not remove task '$t': $($_.Exception.Message)" 'Yellow' }
        } else {
            Say "  task '$t' not present" 'DarkGray'
        }
    }
} else {
    Say "  ($Scope has no scheduled tasks)" 'DarkGray'
}
# Old-style startup shortcut, if a previous version created one
$oldLnk = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\komorebi.lnk'
if (Test-Path $oldLnk) { Remove-Item $oldLnk -Force; Say "  removed startup shortcut" 'Yellow' }

Say ''
Say '=== 2/4  stopping processes ===' 'Cyan'
foreach ($n in $procs) {
    $running = Get-Process -Name $n -ErrorAction SilentlyContinue
    if ($running) {
        # Ask komorebi to stop gracefully first, then force-kill the rest.
        if ($n -eq 'komorebi') {
            try { & 'C:\Program Files\komorebi\bin\komorebic.exe' stop --whkd 2>$null | Out-Null } catch {}
            Start-Sleep -Seconds 2
        }
        $running | Stop-Process -Force -ErrorAction SilentlyContinue
        Say "  stopped $n" 'Green'
    } else {
        Say "  $n not running" 'DarkGray'
    }
}

if ($KeepBinaries) {
    Say ''
    Say '  -KeepBinaries set: leaving the installed programs in place.' 'Yellow'
    Say '=== done ===' 'Cyan'
    exit 0
}

Say ''
Say '=== 3/4  uninstalling the software ===' 'Cyan'
# This machine has a broken winget (it hangs), so go straight to the
# authoritative source: the MSI uninstall entries in the registry.
$regRoots = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'

$filter = ($patterns -join '|')
$entries = Get-ItemProperty $regRoots -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -match $filter }

if ($entries) {
    foreach ($e in $entries) {
        $prod = $e.PSChildName          # the {GUID}
        Say "  uninstalling $($e.DisplayName)  ($prod)" 'Gray'
        # /X<guid> /qn = silent uninstall; msiexec is quick and never hangs here.
        $proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList "/X$prod", '/qn' -Wait -PassThru
        Say "    msiexec exit code: $($proc.ExitCode)" 'DarkGray'
    }
} else {
    Say '  no MSI install entries found; falling back to directory removal.' 'Yellow'
    $dirs = switch ($Scope) {
        'all'             { @('C:\Program Files\komorebi', 'C:\Program Files\whkd', 'C:\Program Files\YASB', 'C:\Program Files\AutoHotkey') }
        'komorebi-whkd'   { @('C:\Program Files\komorebi', 'C:\Program Files\whkd') }
        'yasb'            { @('C:\Program Files\YASB') }
        'autohotkey'      { @('C:\Program Files\AutoHotkey') }
    }
    foreach ($d in $dirs + @("$env:LOCALAPPDATA\komorebi", "$env:LOCALAPPDATA\whkd")) {
        if (Test-Path $d) {
            Say "  removing $d" 'Gray'
            Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Say ''
Say '=== 4/4  verifying ===' 'Cyan'
$left = Get-Process -Name komorebi,whkd -ErrorAction SilentlyContinue
if ($left) {
    Say '  still running:' 'Red'
    $left | ForEach-Object { Say "     $($_.Name) (pid $($_.Id))" 'Red' }
    Say '  kill them manually or reboot to finish.' 'Yellow'
} else { Say '  no komorebi / whkd processes left' 'Green' }

$bin = Get-ChildItem 'C:\Program Files' -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match 'komorebi|whkd' }
if ($bin) {
    Say '  install folders still present:' 'Yellow'
    $bin | ForEach-Object { Say "     $($_.FullName)" 'Yellow' }
} else { Say '  install folders removed' 'Green' }

Say ''
Say 'DONE. Your config files were kept. Run CLEANUP-KOMOREBI-WHKD.bat to delete them too.' 'Cyan'
Say ''
