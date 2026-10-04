#Requires -Version 5.1
<#
    .SYNOPSIS
        Reset workspaces so every monitor shows 1..9 in order again.

    .DESCRIPTION
        komorebi keeps its workspace list as an internal vector whose ORDER
        changes as you switch workspaces - it is NOT sorted. After a long
        session the main monitor can report [2,3,5,6,7,8,9,1,4] instead of
        [1..9]. The bar then looks like it "starts at 2".

        retile / reload-configuration do NOT reorder that vector. The only way
        to get 1..9 back in order is a full stop + start.

        This script does exactly that, and confirms the order afterwards.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$KomorebiExe = 'C:\Program Files\komorebi\bin\komorebic.exe'

function Say($msg, $color = 'Gray') { Write-Host $msg -ForegroundColor $color }

Say ''
Say '=== freezing the watchdog for the restart window ===' 'Cyan'
$watchWasEnabled = $false
try {
    $t = Get-ScheduledTask -TaskName 'KomorebiWatchdog' -ErrorAction SilentlyContinue
    if ($t -and $t.State -ne 'Disabled') {
        $watchWasEnabled = $true
        Disable-ScheduledTask -TaskName 'KomorebiWatchdog' | Out-Null
        Say '  watchdog frozen' 'DarkGray'
    }
} catch { Say "  could not touch the watchdog task: $($_.Exception.Message)" 'Yellow' }

Say ''
Say '=== stopping komorebi + whkd ===' 'Cyan'
try { & $KomorebiExe stop --whkd 2>$null | Out-Null } catch {}
Get-Process -Name komorebi, whkd -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

Say '=== starting komorebi + whkd ===' 'Cyan'
$machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
$user    = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($machine) { $env:Path = $machine + ';' + $user }
Start-Process -FilePath $KomorebiExe -ArgumentList 'start', '--whkd' `
              -WorkingDirectory (Split-Path $KomorebiExe) | Out-Null

if (-not (Get-Process -Name komorebi -ErrorAction SilentlyContinue)) {
    Start-Sleep -Seconds 8
}
if (-not (Get-Process -Name whkd -ErrorAction SilentlyContinue)) {
    Start-Sleep -Seconds 4
}

if ($watchWasEnabled) {
    try { Enable-ScheduledTask -TaskName 'KomorebiWatchdog' | Out-Null } catch { }
    Say '  watchdog re-enabled' 'DarkGray'
}

Say ''
Say '=== workspace order per monitor ===' 'Cyan'
try {
    $s = (& $KomorebiExe state) | ConvertFrom-Json
    foreach ($m in $s.monitors.elements) {
        $names = @($m.workspaces.elements | ForEach-Object { $_.name })
        $ok    = ($names -join ',') -eq '1,2,3,4,5,6,7,8,9'
        $color = if ($ok) { 'Green' } else { 'Yellow' }
        Say ("  {0}: {1}" -f $m.name, ($names -join ' ')) $color
        if (-not $ok) { Say '     (not 1..9 - switch to workspace 1 on this monitor and re-run)' 'Yellow' }
    }
} catch {
    Say "  could not read state: $($_.Exception.Message)" 'Red'
}

Say ''
Say 'done' 'Cyan'
Say ''
