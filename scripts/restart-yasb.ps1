# =====================================================================
# restart-yasb.ps1  —  Restart YASB only, optionally with diagnosis
#
# Why a full restart and not a config hot-reload:
#   YASB's komorebi event listener shells out to `komorebic.exe` using the
#   environment YASB inherited AT LAUNCH. If that PATH predates the komorebi
#   install, the lookup fails and the komorebi widgets silently go stale
#   ("'komorebic.exe' is not recognized as an internal or external command"
#   even though the binary exists). watch_config also does not notice edits
#   made from WSL (drvfs), so a restart is the reliable way to apply a
#   config.yaml change made from WSL.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File restart-yasb.ps1
#   powershell -ExecutionPolicy Bypass -File restart-yasb.ps1 -DiagnoseOnly
#
# -DiagnoseOnly prints the PATH diagnosis (registry vs inherited) and how YASB
# is registered to start at logon, then exits WITHOUT restarting anything.
# It is the read-only half of what used to live in the separate
# 7-YASB-RESTART.ps1; that duplicate was merged into this switch.
# =====================================================================
[CmdletBinding()]
param([switch]$DiagnoseOnly)

$ErrorActionPreference = 'Continue'
$Yasb = 'C:\Program Files\yasb\yasb.exe'
$Log  = Join-Path $env:USERPROFILE '.config\yasb\yasb.log'

# --- diagnosis (read-only) ---------------------------------------------
Write-Host '[restart-yasb] --- environment diagnosis (registry vs inherited) ---' -ForegroundColor Cyan
$machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
$user    = [Environment]::GetEnvironmentVariable('Path', 'User')
Write-Host ('  machine PATH has komorebi\bin : ' + ($machine -like '*komorebi\bin*'))
Write-Host ('  machine PATH has whkd\bin     : ' + ($machine -like '*whkd\bin*'))
Write-Host ('  user    PATH has komorebi\bin : ' + ($user    -like '*komorebi\bin*'))

# PATH is read at launch, so rebuild it from the registry before anything runs.
if ($machine) { $env:Path = "$machine;$user" }
$kc = Get-Command komorebic.exe -ErrorAction SilentlyContinue
if ($kc) { Write-Host ('  komorebic.exe after refresh  : ' + $kc.Source) -ForegroundColor Green }
else     { Write-Host '  komorebic.exe after refresh  : NOT FOUND' -ForegroundColor Red }

Write-Host '[restart-yasb] --- YASB autostart registration ---' -ForegroundColor Cyan
$foundRun = $false
$rp = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue)
if ($rp) {
    $rp.PSObject.Properties | Where-Object { $_.Value -like '*yasb*' } | ForEach-Object {
        $foundRun = $true
        Write-Host ('  HKCU Run : ' + $_.Name + ' = ' + $_.Value)
    }
}
if (-not $foundRun) { Write-Host '  HKCU Run : (no yasb entry)' }
$tasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like '*yasb*' }
if ($tasks) { $tasks | ForEach-Object { Write-Host ('  Task     : ' + $_.TaskName) } }
else        { Write-Host '  Task     : (none)' }
$svc = Get-Process -Name yasb, yasbc -ErrorAction SilentlyContinue
if ($svc) { Write-Host ('  running  : ' + (($svc | ForEach-Object { $_.ProcessName }) -join ', ')) }
else      { Write-Host '  running  : (not running)' }

if ($DiagnoseOnly) { exit 0 }

if (-not (Test-Path $Yasb)) { Write-Host "yasb not installed at $Yasb" -ForegroundColor Red; exit 1 }

# remember the current log size so we can judge only NEW output
$marker = 0
if (Test-Path $Log) { $marker = (Get-Item $Log).Length }

Write-Host '[restart-yasb] stopping yasb ...' -ForegroundColor Cyan
taskkill /f /im yasb.exe  2>&1 | Out-Null
taskkill /f /im yasbc.exe 2>&1 | Out-Null
Start-Sleep -Seconds 3

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
    ($new -split "`r?`n") | Where-Object { $_ -match 'komorebi|whkd|connected|failed|not recognized|Invalid|validation|hotkey|pipe' } |
        Select-Object -Last 12 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
}
