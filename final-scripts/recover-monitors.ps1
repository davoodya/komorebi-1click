# recover-monitors.ps1
# ---------------------------------------------------------------------
# Run this after plugging/unplugging or powering a monitor off/on.
# It re-syncs komorebi with the currently active displays:
#   * restores any windows that got orphaned
#   * retiles everything
#   * re-applies the display index preferences
# Usage: powershell -ExecutionPolicy Bypass -File recover-monitors.ps1
# ---------------------------------------------------------------------
. "$PSScriptRoot\common.ps1"

$komorebic = Resolve-KomorebicExe

Write-Host "[recover-monitors] restoring hidden windows ..." -ForegroundColor Cyan
& $komorebic restore-windows
Start-Sleep -Milliseconds 500

Write-Host "[recover-monitors] re-applying display index preferences ..." -ForegroundColor Cyan
& $komorebic display-index-preference 0 DISPLAY1
& $komorebic display-index-preference 1 DISPLAY2
& $komorebic display-index-preference 2 DISPLAY3
Start-Sleep -Milliseconds 400

Write-Host "[recover-monitors] retiling ..." -ForegroundColor Cyan
& $komorebic retile
Start-Sleep -Milliseconds 400

Write-Host "[recover-monitors] active monitors:" -ForegroundColor Cyan
(& $komorebic state | ConvertFrom-Json).monitors.elements | ForEach-Object {
    Write-Host ("  {0} (device {1})" -f $_.name, $_.device) -ForegroundColor Green
}

Write-Host "[recover-monitors] DONE" -ForegroundColor Green
