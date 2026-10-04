# =====================================================================
# restart-yasb.ps1  —  Restart YASB only
#
# Why a full restart and not a config hot-reload:
#   YASB's komorebi event listener shells out to `komorebic.exe` using the
#   environment YASB inherited AT LAUNCH. If that PATH predates the komorebi
#   install, the lookup fails and the komorebi widgets silently go stale.
#   watch_config also does not notice edits made from WSL (drvfs), so a
#   restart is the reliable way to apply a config.yaml change from WSL.
#
# This is the thin variant of 7-YASB-RESTART.ps1 (which additionally prints
# the PATH diagnosis and the log verdict).
# Usage: powershell -ExecutionPolicy Bypass -File restart-yasb.ps1
# =====================================================================
$ErrorActionPreference = 'Continue'
$Yasb = 'C:\Program Files\yasb\yasb.exe'
$Log  = Join-Path $env:USERPROFILE '.config\yasb\yasb.log'

if (-not (Test-Path $Yasb)) { Write-Host "yasb not installed at $Yasb" -ForegroundColor Red; exit 1 }

# remember the current log size so we can judge only NEW output
$marker = 0
if (Test-Path $Log) { $marker = (Get-Item $Log).Length }

Write-Host '[restart-yasb] stopping yasb ...' -ForegroundColor Cyan
taskkill /f /im yasb.exe  2>&1 | Out-Null
taskkill /f /im yasbc.exe 2>&1 | Out-Null
Start-Sleep -Seconds 3

# PATH is read at launch, so rebuild it from the registry first.
$machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
$user    = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($machine) { $env:Path = "$machine;$user" }

Write-Host '[restart-yasb] starting yasb with a registry-fresh PATH ...' -ForegroundColor Cyan
Start-Process -FilePath $Yasb -WorkingDirectory (Split-Path -Parent $Yasb)
Start-Sleep -Seconds 16

# verdict from the log lines this restart produced
$new = ''
if (Test-Path $Log) {
    $fs = [System.IO.File]::Open($Log, 'Open', 'Read', 'ReadWrite')
    try {
        [void]$fs.Seek([Math]::Min($marker, $fs.Length), 'Begin')
        $sr = New-Object System.IO.StreamReader($fs)
        $new = $sr.ReadToEnd(); $sr.Close()
    } finally { $fs.Close() }
}

if ($new -match 'connected to named pipe') {
    Write-Host '[restart-yasb] DONE - YASB is connected to komorebi.' -ForegroundColor Green
} elseif ($new -notmatch '\S') {
    Write-Host '[restart-yasb] DONE, but YASB wrote nothing to the log - it may not have started.' -ForegroundColor Yellow
} else {
    Write-Host '[restart-yasb] DONE, but the komorebi connection was NOT confirmed. Recent lines:' -ForegroundColor Yellow
    ($new -split "`r?`n") | Where-Object { $_ -match 'komorebi|whkd|connected|failed|not recognized|Invalid' } |
        Select-Object -Last 8 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
}
