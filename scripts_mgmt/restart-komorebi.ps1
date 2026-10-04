# =====================================================================
# restart-komorebi.ps1  —  Restart komorebi only (apply a new komorebi.json)
#
# Watchdog-safe: the KomorebiWatchdog scheduled task runs every 5 minutes
# and could land inside the restart gap, see komorebi dead, and start a
# SECOND komorebi against the same socket — that race is what used to make
# workspace switching silently stop responding. The watchdog is frozen for
# the whole restart window here to make that impossible.
# Usage: powershell -ExecutionPolicy Bypass -File restart-komorebi.ps1
# =====================================================================
. "$PSScriptRoot\common.ps1"

$komorebi = Resolve-KomorebiExe
$WatchTask = 'KomorebiWatchdog'

Write-Host "[restart-komorebi] freezing the watchdog for the restart window ..." -ForegroundColor DarkGray
$watchWasEnabled = $false
try {
    $t = Get-ScheduledTask -TaskName $WatchTask -ErrorAction SilentlyContinue
    if ($t -and $t.State -ne 'Disabled') {
        $watchWasEnabled = $true
        Disable-ScheduledTask -TaskName $WatchTask | Out-Null
    }
} catch { }

Write-Host "[restart-komorebi] stopping komorebi ..." -ForegroundColor Cyan
Stop-ProcessTree "komorebi"

Write-Host "[restart-komorebi] starting komorebi ..." -ForegroundColor Cyan
Start-Process -FilePath $komorebi -WindowStyle Hidden -WorkingDirectory $env:ProgramFiles
Start-Sleep -Seconds 2

if ($watchWasEnabled) {
    try { Enable-ScheduledTask -TaskName $WatchTask | Out-Null } catch { }
    Write-Host "[restart-komorebi] watchdog re-enabled" -ForegroundColor DarkGray
}

if (Test-Process "komorebi") {
    Write-Host "[restart-komorebi] DONE - komorebi running, new config active" -ForegroundColor Green
} else {
    Write-Host "[restart-komorebi] FAILED - komorebi is not running" -ForegroundColor Red
    exit 1
}
