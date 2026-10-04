# =====================================================================
# restart-whkd.ps1  —  Restart whkd so an edited whkdrc takes effect
#
# WHAT THIS DOES
#   whkd reads whkdrc only at launch, so editing the file changes nothing
#   until whkd restarts. This script performs that restart and, unlike a
#   bare "kill whkd and start it again", keeps whkd PAIRED with komorebi.
#
#   Pairing is the whole point. A whkd started by anything other than
#   `komorebic start --whkd` registers every hotkey with Windows and then
#   drops every command it fires, so the WM looks healthy while the entire
#   keyboard is dead (LGUG2Z/komorebi#956). Killing whkd alone and
#   relaunching whkd.exe directly reproduces exactly that broken state —
#   which is why this script restarts through komorebi instead.
#
#   Restarting whkd also has to restart komorebi, because komorebi spawns
#   whkd as its own child. komorebi saves its managed-window state to disk
#   and re-applies it on the next launch, so the tiled layout survives.
#
#   This is the SAFE restart: the KomorebiWatchdog scheduled task runs
#   every 5 minutes and can land inside the restart gap, see komorebi
#   dead, and start a SECOND komorebi against the same socket. That race
#   is what used to make workspace switching silently stop responding.
#   The watchdog is frozen for the whole restart window here.
#
#   The elevated/Hermes/custom windows komorebi manages via `manage_rules`
#   are only reachable from an ELEVATED window manager. If this script is
#   run elevated, the new komorebi inherits that elevation; if it is not,
#   those windows stay unmanaged until the next elevated logon-task run.
#   This matches safe-restart.ps1 behaviour.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File restart-whkd.ps1
# Exit codes:
#   0  whkd is running and paired, the new whkdrc is live
#   1  whkd did not come up at all
#   2  whkd is running but NOT paired — hotkeys will be dead
# =====================================================================

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\common.ps1"

$komorebic = Resolve-KomorebicExe
$WatchTask = 'KomorebiWatchdog'
$StateDir  = Join-Path $env:LOCALAPPDATA 'komorebi'

function Say($msg, $color = 'Gray') { Write-Host $msg -ForegroundColor $color }

# ── 1. freeze the watchdog for the whole restart window ─────────────────
# The watchdog sees a dead komorebi inside this gap and starts a second
# one against the same socket. That race silently breaks workspace
# switching, so it is disabled for the entire restart, not just the stop.
$watchWasEnabled = $false
try {
    $t = Get-ScheduledTask -TaskName $WatchTask -ErrorAction SilentlyContinue
    if ($t -and $t.State -ne 'Disabled') {
        $watchWasEnabled = $true
        Disable-ScheduledTask -TaskName $WatchTask | Out-Null
        Say '[restart-whkd] watchdog frozen for the restart window' 'DarkGray'
    }
} catch { Say "[restart-whkd] could not touch the watchdog task: $($_.Exception.Message)" 'Yellow' }
try {

# ── 2. stop the pair through the official command ───────────────────────
# `komorebic stop --whkd` removes komorebi AND the whkd child it owns. A
# plain Stop-Process would leave an orphaned whkd that a later `--whkd`
# start then refuses to replace, so always stop through komorebic.
Say '[restart-whkd] stopping komorebi + whkd ...' 'Cyan'
try { & $komorebic stop --whkd 2>$null | Out-Null } catch { }
Stop-ProcessTree 'komorebi'
Stop-ProcessTree 'whkd'
Start-Sleep -Seconds 1

# Clear stale IPC state so the new instance gets a clean socket surface.
# komorebi writes its state dump on a clean stop; only delete leftovers
# that survived an abnormal one.
Remove-Item (Join-Path $StateDir 'komorebi.sock')    -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $StateDir 'komorebi.hwnd.json') -Force -ErrorAction SilentlyContinue

# ── 3. start the pair again so komorebi owns the whkd child ─────────────
Say '[restart-whkd] starting komorebi + whkd ...' 'Cyan'

# Refresh PATH from the registry before starting: a stale inherited PATH
# makes komorebi report "could not find whkd" and refuse to start at all.
# That failure is what used to send restart scripts into a standalone-whkd
# fallback — the fallback that silently kills every hotkey.
$machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
$user    = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($machine) { $env:Path = $machine + ';' + $user }

# ELEVATE. komorebi can only manage a window it can open, and a non-elevated
# window manager cannot touch elevated processes (UAC integrity levels), so an
# unelevated restart silently drops every elevated window AND the Hermes window
# out of the layout. The installer's logon task runs at RunLevel Highest for
# exactly this reason; a restart must match it. When this script is already
# elevated the relaunch is a no-op pass-through.
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$elevated  = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

$argList = 'start', '--whkd'

if ($elevated) {
    # Already elevated: start directly, and redirect the children so they do
    # NOT inherit this script's stdout/stderr handles. When they inherit them
    # (the default), PowerShell cannot exit until the long-lived komorebi/whkd
    # children close their copy of the pipe, so the script appears to hang
    # forever even though everything actually started.
    try {
        Start-Process -FilePath $komorebic -ArgumentList $argList `
                      -WorkingDirectory (Split-Path $komorebic) `
                      -RedirectStandardOutput (Join-Path $StateDir 'komorebi.out.log') `
                      -RedirectStandardError (Join-Path $StateDir 'komorebi.err.log') `
                      -WindowStyle Hidden | Out-Null
    } catch {
        Say "[restart-whkd] launch failed: $($_.Exception.Message)" 'Red'
        if ($watchWasEnabled) { try { Enable-ScheduledTask -TaskName $WatchTask | Out-Null } catch { } }
        exit 1
    }
} else {
    # Not elevated: get an elevated komorebi by running the installer's own
    # elevated logon task. This is the reliable route on this host because the
    # current user is not an Administrator, so `Start-Process -Verb RunAs`
    # would raise a consent prompt that an automated run cannot answer — and
    # with ConsentPromptBehaviorAdmin=0 a non-admin account is not elevated
    # silently either. The registered task is RunLevel Highest, so a plain
    # `Start-ScheduledTask` launches komorebi with the same token the machine
    # uses at every logon. That token is what can see elevated windows and the
    # Hermes window, which is the whole reason to elevate here.
    try {
        Start-ScheduledTask -TaskName 'Komorebi' -ErrorAction Stop
        Say '[restart-whkd] elevated komorebi started via the Komorebi logon task' 'DarkGray'
    } catch {
        Say '[restart-whkd] could not start the elevated logon task.' 'Red'
        Say "[restart-whkd] $($_.Exception.Message)" 'Red'
        Say '[restart-whkd] fallback: log off and back on, or run this as Administrator.' 'Yellow'
        if ($watchWasEnabled) { try { Enable-ScheduledTask -TaskName $WatchTask | Out-Null } catch { } }
        exit 1
    }
}

# ── 4. restore the watchdog once the pair is stable ─────────────────────
if ($watchWasEnabled) {
    Start-Sleep -Seconds 2
    try { Enable-ScheduledTask -TaskName $WatchTask | Out-Null } catch { }
    Say '[restart-whkd] watchdog re-enabled' 'DarkGray'
}

# ── 5. verify whkd is up ────────────────────────────────────────────────
$up = $false
foreach ($i in 1..10) {
    if (Test-Process 'whkd') { $up = $true; break }
    Start-Sleep -Milliseconds 500
}
if (-not $up) {
    Say '[restart-whkd] FAILED - whkd is not running' 'Red'
    Say "[restart-whkd] check the log: $(Join-Path $StateDir 'komorebi.err.log')" 'Yellow'
    exit 1
}

# ── 6. verify the pairing, because a running whkd proves nothing ────────
# whkd can be alive, parse whkdrc perfectly, and still drop every hotkey —
# that happens when komorebi did not spawn it. The signal is the process
# tree: `--whkd` launches whkd through a transient helper that exits
# immediately, leaving a gone parent PID, while a standalone whkd has a
# live shell as an ancestor.
function Test-WhkdPaired {
    try {
        $cur = Get-CimInstance Win32_Process -Filter "Name = 'whkd.exe'" -ErrorAction SilentlyContinue |
            Select-Object -First 1
        $seen = @{}
        for ($i = 0; $cur -and $i -lt 12 -and -not $seen.ContainsKey($cur.ProcessId); $i++) {
            if ($cur.Name -ieq 'komorebi.exe') { return $true }
            $seen[$cur.ProcessId] = $true
            $next = Get-CimInstance Win32_Process -Filter "ProcessId = $($cur.ParentProcessId)" -ErrorAction SilentlyContinue
            if ($null -eq $next) { return $true }   # the official launcher exited
            if ($next.Name -imatch 'pwsh\.exe|powershell\.exe|cmd\.exe|wt\.exe|conhost\.exe') { return $false }
            $cur = $next
        }
    } catch { }
    return $false
}

if (Test-WhkdPaired) {
    Say '[restart-whkd] DONE - whkd running and paired, the new whkdrc is live' 'Green'
    exit 0
} else {
    Say '[restart-whkd] whkd is running but NOT paired with komorebi.' 'Red'
    Say '[restart-whkd] Hotkeys will be dead. Repair with:' 'Red'
    Say '    komorebic stop --whkd' 'Red'
    Say '    komorebic start --whkd' 'Red'
    Say '[restart-whkd] (Komorebi restarts too — its saved layout is re-applied.)' 'DarkGray'
    exit 2
}

# -- crash-safe watchdog restore (defect D4) ------------------------------
# The explicit restore earlier in this script only runs on the happy path.
# This `finally` also runs when a step throws, when the script exits early and
# on Ctrl+C, so a failed or interrupted restart can never leave the watchdog
# disabled. Komorebi + whkd must stay supervised at all times; only kill-all
# is allowed to stop them.
} finally {
    if ($watchWasEnabled) {
        try { Enable-ScheduledTask -TaskName $WatchTask | Out-Null } catch { }
    }
}
