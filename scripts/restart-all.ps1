# =====================================================================
# restart-all.ps1  —  Restart komorebi + whkd + yasb (apply new configs)
#
# Use 0-SAFE-RESTART.bat instead when you can: it additionally freezes the
# watchdog for the restart window and verifies your tiled layout survived.
# This script is the lighter, dependency-free variant.
# Usage: powershell -ExecutionPolicy Bypass -File restart-all.ps1
# =====================================================================
. "$PSScriptRoot\common.ps1"

$komorebi = Resolve-KomorebiExe
$whkd     = Resolve-WhkdExe
$yasb     = 'C:\Program Files\yasb\yasb.exe'

Write-Host "[restart-all] stopping komorebi + whkd + yasb ..." -ForegroundColor Cyan
Stop-ProcessTree "komorebi"
Stop-ProcessTree "whkd"
Stop-ProcessTree "yasb"
Stop-ProcessTree "yasbc"

Write-Host "[restart-all] starting komorebi ..." -ForegroundColor Cyan
Start-Process -FilePath $komorebi -WindowStyle Hidden -WorkingDirectory $env:ProgramFiles
Start-Sleep -Seconds 2

Write-Host "[restart-all] starting whkd ..." -ForegroundColor Cyan
Start-Process -FilePath $whkd -WindowStyle Hidden -WorkingDirectory $env:ProgramFiles
Start-Sleep -Seconds 1

if (Test-Path $yasb) {
    Write-Host "[restart-all] starting yasb ..." -ForegroundColor Cyan
    # PATH is read at launch. Rebuild it from the registry so the komorebi
    # event listener can resolve komorebic.exe (see the -DiagnoseOnly switch in restart-yasb.ps1).
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($machine) { $env:Path = "$machine;$user" }
    Start-Process -FilePath $yasb -WorkingDirectory (Split-Path -Parent $yasb)
    Start-Sleep -Seconds 4
} else {
    Write-Host "[restart-all] yasb not installed - skipping" -ForegroundColor Yellow
}

$ok = (Test-Process "komorebi") -and (Test-Process "whkd") -and (Test-Process "yasb")
if ($ok) {
    Write-Host "[restart-all] DONE - all three running" -ForegroundColor Green
} else {
    Write-Host "[restart-all] PARTIAL - komorebi=$([int](Test-Process komorebi)) whkd=$([int](Test-Process whkd)) yasb=$([int](Test-Process yasb))" -ForegroundColor Yellow
}
