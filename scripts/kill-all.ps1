# =====================================================================
# kill-all.ps1  —  PERMANENTLY STOP komorebi + whkd + yasb
#
#   powershell -ExecutionPolicy Bypass -File kill-all.ps1
#   powershell -ExecutionPolicy Bypass -File kill-all.ps1 -Components komorebi-whkd
#
# -Components (default: all)
#   all             komorebi + whkd + yasb (+ yasbc)
#   komorebi-whkd   komorebi + whkd only (yasb keeps running)
#   yasb            yasb only
# =====================================================================
[CmdletBinding()]
param(
    [ValidateSet('all', 'komorebi-whkd', 'yasb')]
    [string]$Components = 'all'
)

. "$PSScriptRoot\common.ps1"

$targets = switch ($Components) {
    'all'             { @('komorebi', 'whkd', 'yasb', 'yasbc') }
    'komorebi-whkd'   { @('komorebi', 'whkd') }
    'yasb'            { @('yasb', 'yasbc') }
}

Write-Host "[kill-all] stopping ($Components): $($targets -join ', ') ..." -ForegroundColor Cyan
foreach ($t in $targets) { Stop-ProcessTree $t }

# Verify exactly the components this scope was asked to stop.
$stillUp = @($targets | Where-Object { Test-Process $_ })
if ($stillUp.Count -eq 0) {
    Write-Host "[kill-all] DONE - $Components stopped (windows are left in place)" -ForegroundColor Green
} else {
    Write-Host "[kill-all] FAILED - still running: $($stillUp -join ', ')" -ForegroundColor Red
    exit 1
}
