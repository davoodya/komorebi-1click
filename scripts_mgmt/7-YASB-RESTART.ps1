# 7-YASB-RESTART.ps1 — restart YASB with a registry-fresh PATH, then verify.
#
# Why this exists:
#   YASB's komorebi event listener runs `komorebic.exe` through cmd (shell=True)
#   using the environment YASB inherited AT LAUNCH. On this machine that lookup
#   fails with "'komorebic.exe' is not recognized as an internal or external
#   command" even though the binary exists at
#   C:\Program Files\komorebi\bin\komorebic.exe — a stale inherited PATH.
#   komorebi-service.ps1 documents the same failure mode for whkd.
#
# What it does:
#   1. prints machine/user PATH status for komorebi\bin (registry, fresh)
#   2. prints how YASB is registered to start at logon (Run key / task)
#   3. kills YASB and relaunches it with PATH rebuilt from the registry
#   4. reads ONLY the log bytes written after the restart and prints the verdict
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\7-YASB-RESTART.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\7-YASB-RESTART.ps1 -DiagnoseOnly

param([switch]$DiagnoseOnly)

$ErrorActionPreference = 'Continue'
$Yasb = 'C:\Program Files\yasb\yasb.exe'
$Log  = Join-Path $env:USERPROFILE '.config\yasb\yasb.log'

Write-Host '--- 1. environment diagnosis (registry vs inherited) ---' -ForegroundColor Cyan
$machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
$user    = [Environment]::GetEnvironmentVariable('Path', 'User')
Write-Host ('  machine PATH has komorebi\bin : ' + ($machine -like '*komorebi\bin*'))
Write-Host ('  machine PATH has whkd\bin     : ' + ($machine -like '*whkd\bin*'))
Write-Host ('  user    PATH has komorebi\bin : ' + ($user    -like '*komorebi\bin*'))
$env:Path = "$machine;$user"
$kc = Get-Command komorebic.exe -ErrorAction SilentlyContinue
if ($kc) { Write-Host ('  komorebic.exe after refresh  : ' + $kc.Source) -ForegroundColor Green }
else     { Write-Host '  komorebic.exe after refresh  : NOT FOUND' -ForegroundColor Red }

Write-Host '--- 2. YASB autostart registration ---' -ForegroundColor Cyan
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

# remember the current log size so we only judge NEW output
$marker = 0
if (Test-Path $Log) { $marker = (Get-Item $Log).Length }

Write-Host '--- 3. restarting YASB with the refreshed PATH ---' -ForegroundColor Cyan
taskkill /f /im yasb.exe  2>&1 | Out-Null
taskkill /f /im yasbc.exe 2>&1 | Out-Null
Start-Sleep -Seconds 3
Start-Process -FilePath $Yasb -WorkingDirectory (Split-Path -Parent $Yasb)
Start-Sleep -Seconds 16

Write-Host '--- 4. verdict (log written after the restart) ---' -ForegroundColor Cyan
$new = ''
if (Test-Path $Log) {
    $fs = [System.IO.File]::Open($Log, 'Open', 'Read', 'ReadWrite')
    [void]$fs.Seek($marker, 'Begin')
    $sr = New-Object System.IO.StreamReader($fs)
    $new = $sr.ReadToEnd()
    $sr.Close()
}
$lines = $new -split "`r?`n" | Where-Object { $_ -match '\S' }
$lines | Where-Object { $_ -match 'komorebi|whkd|connected|failed|not recognized|Invalid|validation|hotkey|pipe' } |
    Select-Object -Last 18 | ForEach-Object { Write-Host ('  ' + $_) }

if ($new -match 'connected to named pipe') {
    Write-Host 'RESULT: YASB is connected to komorebi.' -ForegroundColor Green
} elseif ($new -notmatch '\S') {
    Write-Host 'RESULT: YASB wrote nothing to the log - it did not start.' -ForegroundColor Red
} else {
    Write-Host 'RESULT: still NOT connected - see lines above.' -ForegroundColor Red
}
