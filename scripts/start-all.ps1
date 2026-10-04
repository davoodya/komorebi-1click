# =====================================================================
# start-all.ps1  —  Start komorebi + whkd + yasb (if not already running)
#
#   powershell -ExecutionPolicy Bypass -File start-all.ps1
#   powershell -ExecutionPolicy Bypass -File start-all.ps1 -Components komorebi-whkd
#
# -Components (default: all)
#   all             komorebi + whkd + yasb
#   komorebi-whkd   komorebi + whkd only (the Dashboard's WM-only path)
#   yasb            yasb only
#
# komorebi must start FIRST (whkd/yasb talk to its socket).
# yasb needs komorebi\bin on PATH at launch or its komorebi widgets go
# stale, so PATH is rebuilt from the registry before yasb is started.
# =====================================================================
[CmdletBinding()]
param(
    [ValidateSet('all', 'komorebi-whkd', 'yasb')]
    [string]$Components = 'all'
)

. "$PSScriptRoot\common.ps1"

$komorebi = Resolve-KomorebiExe
$whkd     = Resolve-WhkdExe
$yasb     = Resolve-YasbExe

function Start-IfNotRunning([string]$Name, [scriptblock]$Start) {
    if (Test-Process $Name) {
        Write-Host "[start-all] $Name already running" -ForegroundColor DarkYellow
        return
    }
    Write-Host "[start-all] starting $Name ..." -ForegroundColor Cyan
    & $Start
}

if ($Components -ne 'yasb') {
    Start-IfNotRunning 'komorebi' {
        Start-Process -FilePath $komorebi -WindowStyle Hidden -WorkingDirectory $env:ProgramFiles
        Start-Sleep -Seconds 2
    }
    Start-Sleep -Milliseconds 500
    Start-IfNotRunning 'whkd' {
        Start-Process -FilePath $whkd -WindowStyle Hidden -WorkingDirectory $env:ProgramFiles
        Start-Sleep -Seconds 1
    }
}

if ($Components -ne 'komorebi-whkd') {
    Start-IfNotRunning 'yasb' {
        # PATH is read at launch. Rebuild it from the registry so the komorebi
        # event listener can resolve komorebic.exe (see the -DiagnoseOnly switch in restart-yasb.ps1).
        if ($yasb) {
            $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
            $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
            if ($machine) { $env:Path = "$machine;$user" }
            Start-Process -FilePath $yasb -WorkingDirectory (Split-Path -Parent $yasb)
            Start-Sleep -Seconds 4
        } else {
            Write-Host "[start-all] yasb not installed - skipping" -ForegroundColor Yellow
        }
    }
}

$expected = switch ($Components) {
    'all'             { @('komorebi', 'whkd', 'yasb') }
    'komorebi-whkd'   { @('komorebi', 'whkd') }
    'yasb'            { @('yasb') }
}
$missing = @($expected | Where-Object { -not (Test-Process $_) })
if ($missing.Count -eq 0) {
    Write-Host "[start-all] DONE - $Components running" -ForegroundColor Green
} else {
    $state = ($expected | ForEach-Object { "$_=$([int](Test-Process $_))" }) -join ' '
    Write-Host "[start-all] PARTIAL ($Components) - $state" -ForegroundColor Yellow
}
