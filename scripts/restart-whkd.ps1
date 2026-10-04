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

if (-not (Test-Process "whkd")) {
    Write-Host "[restart-whkd] FAILED - whkd is not running" -ForegroundColor Red
    exit 1
}

# A whkd that is running is NOT proof the hotkeys work. whkd is only effective
# when it is paired with a komorebi instance started with `--whkd`; a standalone
# whkd registers every hotkey and then drops every command, and the whole
# keyboard goes dead while the WM looks perfectly healthy.
# This script is the one a user reaches for when hotkeys stop working, so it
# must say so out loud instead of printing DONE.
$paired = $false
try {
    $cur = Get-CimInstance Win32_Process -Filter "Name = 'whkd.exe'" -ErrorAction SilentlyContinue |
        Select-Object -First 1
    $seen = @{}
    for ($i = 0; $cur -and $i -lt 12 -and -not $seen.ContainsKey($cur.ProcessId); $i++) {
        $seen[$cur.ProcessId] = $true
        $next = Get-CimInstance Win32_Process -Filter "ProcessId = $($cur.ParentProcessId)" -ErrorAction SilentlyContinue
        if ($null -eq $next) { $paired = $true; break }
        if ($next.Name -imatch 'pwsh\.exe|powershell\.exe|cmd\.exe|wt\.exe|conhost\.exe') { break }
        if ($next.Name -ieq 'komorebi.exe') { $paired = $true; break }
        $cur = $next
    }
} catch { }

if ($paired) {
    Write-Host "[restart-whkd] DONE - whkd running and paired, new hotkeys active" -ForegroundColor Green
} else {
    Write-Host "[restart-whkd] whkd is running but NOT paired with komorebi." -ForegroundColor Red
    Write-Host "[restart-whkd] Hotkeys will be dead. Repair with:" -ForegroundColor Red
    Write-Host "    komorebic stop --whkd" -ForegroundColor Red
    Write-Host "    komorebic start --whkd" -ForegroundColor Red
    Write-Host "[restart-whkd] (Komorebi restarts too — no open windows are lost.)" -ForegroundColor DarkGray
    exit 2
}
