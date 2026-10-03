#Requires -Version 5.1
<#
    .SYNOPSIS
        The SAFE restart for komorebi + whkd.

    .DESCRIPTION
        Restarting komorebi used to break workspaces in two ways:

        1. WATCHDOG RACE. The service's `restart` kills komorebi and whkd, waits
           ~2s, then relaunches. The watchdog scheduled task runs every 5
           minutes, so it can land exactly inside that gap, see "both dead",
           and start a SECOND komorebi against the same socket. The loser of
           that race is killed mid-initialisation, which leaves the winner with
           a half-built state: workspace switching silently stops responding.

        2. HANDLE INHERITANCE HANG. Start-Process lets the long-lived komorebi
           and whkd children inherit this script's stdout/stderr pipes, so
           PowerShell cannot exit until they close them. The restart looked
           like it hung forever, which invited a second manual restart, which
           fed bug #1.

        This script fixes both, and additionally:
          * disables the watchdog for the whole restart window, so even a
            mutex bug could not cause a double start
          * snapshot + verifies the tiled windows across the restart, so a
            restart can never silently lose your layout
          * reports the workspace order per monitor afterwards

        Use this instead of a raw `komorebic stop` / manual kill.
#>

[CmdletBinding()]
param(
    [switch] $SkipVerify
)

$ErrorActionPreference = 'Stop'

$KomorebiExe = 'C:\Program Files\komorebi\bin\komorebic.exe'
$ServicePs1  = Join-Path $PSScriptRoot 'komorebi-service.ps1'
$StateDir    = Join-Path $env:LOCALAPPDATA 'komorebi'
$WatchTask   = 'KomorebiWatchdog'

function Say($msg, $color = 'Gray') { Write-Host $msg -ForegroundColor $color }

if (-not (Test-Path $ServicePs1)) { throw "komorebi-service.ps1 not found next to this script" }

# ── 1. snapshot the current layout so we can prove nothing was lost ──────
$before = @{}
if (-not $SkipVerify -and (Test-Path $KomorebiExe)) {
    try {
        $s = (& $KomorebiExe state) | ConvertFrom-Json
        foreach ($m in $s.monitors.elements) {
            foreach ($ws in $m.workspaces.elements) {
                foreach ($c in @($ws.containers.elements)) {
                    foreach ($w in @($c.windows.elements)) {
                        $before[$w.exe] = "$($m.name)/$($ws.name)"
                    }
                }
                foreach ($fw in @($ws.floating_windows.elements)) {
                    $before[$fw.exe] = "$($m.name)/$($ws.name) (float)"
                }
            }
        }
        Say ("  snapshot: {0} managed window(s)" -f $before.Count) 'DarkGray'
    } catch { Say "  could not snapshot state: $($_.Exception.Message)" 'Yellow' }
}

# ── 2. freeze the watchdog for the whole restart window ──────────────────
$watchWasEnabled = $false
try {
    $t = Get-ScheduledTask -TaskName $WatchTask -ErrorAction SilentlyContinue
    if ($t -and $t.State -ne 'Disabled') {
        $watchWasEnabled = $true
        Disable-ScheduledTask -TaskName $WatchTask | Out-Null
        Say "  watchdog frozen for the restart window" 'DarkGray'
    }
} catch { Say "  could not touch the watchdog task: $($_.Exception.Message)" 'Yellow' }

# ── 3. restart via the mutex-protected service script ────────────────────
# Run it IN THIS PROCESS. Spawning a nested powershell.exe makes the child
# inherit this script's stdout pipe, and since that child in turn launches the
# long-lived komorebi/whkd, the outer script would never exit.
Say '  restarting komorebi + whkd...' 'Cyan'
& $ServicePs1 -Action restart | Out-Null
Say '  restart returned' 'DarkGray'

# ── 4. restore the watchdog ──────────────────────────────────────────────
if ($watchWasEnabled) {
    try {
        Enable-ScheduledTask -TaskName $WatchTask | Out-Null
        Say '  watchdog re-enabled' 'DarkGray'
    } catch { Say "  could not re-enable the watchdog: $($_.Exception.Message)" 'Yellow' }
}

# ── 5. verify the layout survived ────────────────────────────────────────
if ($before.Count -gt 0) {
    Start-Sleep -Seconds 2
    try {
        $s  = (& $KomorebiExe state) | ConvertFrom-Json
        $after = @{}
        foreach ($m in $s.monitors.elements) {
            foreach ($ws in $m.workspaces.elements) {
                foreach ($c in @($ws.containers.elements)) {
                    foreach ($w in @($c.windows.elements)) { $after[$w.exe] = "$($m.name)/$($ws.name)" }
                }
                foreach ($fw in @($ws.floating_windows.elements)) { $after[$fw.exe] = "$($m.name)/$($ws.name) (float)" }
            }
        }
        $lost = @($before.Keys | Where-Object { $after.Keys -notcontains $_ })
        $moved = @($before.Keys | Where-Object { $after.ContainsKey($_) -and $after[$_] -ne $before[$_] })
        Say ''
        Say "  windows before: $($before.Count)   after: $($after.Count)" 'DarkGray'
        if ($lost.Count)   { Say "  [WARN] lost: $($lost -join ', ')" 'Yellow' }
        if ($moved.Count)  { Say "  [WARN] moved: $($moved -join ', ')" 'Yellow' }
        if (-not $lost.Count -and -not $moved.Count) { Say '  [OK] every window kept its place' 'Green' }
    } catch { Say "  could not verify state: $($_.Exception.Message)" 'Yellow' }
}

# ── 6. report the workspace order per monitor ────────────────────────────
Say ''
Say '=== workspace order per monitor ===' 'Cyan'
try {
    $s = (& $KomorebiExe state) | ConvertFrom-Json
    foreach ($m in $s.monitors.elements) {
        $names = @($m.workspaces.elements | ForEach-Object { $_.name })
        $ok    = ($names -join ',') -eq '1,2,3,4,5,6,7,8,9'
        $color = if ($ok) { 'Green' } else { 'Yellow' }
        Say ("  {0}: {1}" -f $m.name, ($names -join ' ')) $color
        if (-not $ok) { Say '     (not 1..9 in order - run 5-RESET-WORKSPACES.bat)' 'Yellow' }
    }
} catch { Say "  could not read state: $($_.Exception.Message)" 'Red' }

Say ''
Say '  done. Workspaces are per-monitor: alt+N acts on the CURRENT monitor.' 'Cyan'
