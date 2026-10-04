# =====================================================================
# restart-whkd.ps1  —  Restart whkd only (apply new whkdrc hotkeys)
#
# whkd is started by komorebi itself (`komorebic start --whkd`), so the
# reliable way to restart it is through komorebi. A bare `whkd.exe` start
# after a kill also works because whkd re-reads whkdrc on launch.
#
# Watchdog-safe: KomorebiWatchdog could land inside the restart gap and
# double-start the layer, which is what used to silently kill all hotkeys.
# Usage: powershell -ExecutionPolicy Bypass -File restart-whkd.ps1
# =====================================================================
. "$PSScriptRoot\common.ps1"

$whkd = Resolve-WhkdExe
$WatchTask = 'KomorebiWatchdog'

Write-Host "[restart-whkd] freezing the watchdog for the restart window ..." -ForegroundColor DarkGray
$watchWasEnabled = $false
try {
    $t = Get-ScheduledTask -TaskName $WatchTask -ErrorAction SilentlyContinue
    if ($t -and $t.State -ne 'Disabled') {
        $watchWasEnabled = $true
        Disable-ScheduledTask -TaskName $WatchTask | Out-Null
    }
} catch { }

Write-Host "[restart-whkd] stopping whkd ..." -ForegroundColor Cyan
Stop-ProcessTree "whkd"

Write-Host "[restart-whkd] starting whkd ..." -ForegroundColor Cyan
Start-Process -FilePath $whkd -WindowStyle Hidden -WorkingDirectory $env:ProgramFiles
Start-Sleep -Seconds 1

if ($watchWasEnabled) {
    try { Enable-ScheduledTask -TaskName $WatchTask | Out-Null } catch { }
    Write-Host "[restart-whkd] watchdog re-enabled" -ForegroundColor DarkGray
}

if (Test-Process "whkd") {
    Write-Host "[restart-whkd] DONE - whkd running, new hotkeys active" -ForegroundColor Green
} else {
    Write-Host "[restart-whkd] FAILED - whkd is not running" -ForegroundColor Red
    exit 1
}
