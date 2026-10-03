#Requires -Version 5.1
<#
    komorebi + whkd  --  export / import the live configuration.

      -Mode export   copy the live config into the backup folder
      -Mode import   restore the config from the backup folder (backs up the
                     live files first, so this is always reversible)

    IMPORTANT
      Never run `komorebic.exe reload-configuration`. To apply a config change,
      stop the WM, replace the files, and start it again:

          .\0-SAFE-RESTART.bat

      (0-SAFE-RESTART.bat freezes the watchdog for the restart window and
       verifies your tiled layout survived. The old 1-RUN-RESTART.bat did
       neither, which is how workspaces used to break.)

    Run from Windows PowerShell.
#>
[CmdletBinding()]
param(
    [ValidateSet('export', 'import')]
    [string] $Mode = 'export',

    # Where the backup tree lives. The Dashboard and the CLI pass this in, so no
    # machine-specific path is baked in. When omitted, export/import use a
    # timestamped folder next to the live config so the operation always works
    # out of the box on a machine that has no backup drive.
    [string] $ZipPath
)

$ErrorActionPreference = 'Stop'
$KomorebiExe = 'C:\Program Files\komorebi\bin\komorebic.exe'

if (-not $ZipPath) {
    $ZipPath = Join-Path $env:USERPROFILE ('.config\komorebi-backup-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
}

# Live location  ->  location inside the backup folder.
# Only files that exist in this setup are listed; each is skipped when absent.
# NOTE: komorebi-shell.* and komorebi-resize.json are gone from this setup
#       (superseded / unused). whkdrc uses `.shell powershell`.
$Map = @(
    @{ Live = "$env:USERPROFILE\.config\whkdrc";              Rel = 'config\whkdrc' }
    @{ Live = "$env:USERPROFILE\komorebi.json";               Rel = 'config\komorebi.json' }
    @{ Live = "$env:USERPROFILE\applications.json";           Rel = 'config\applications.json' }
    @{ Live = "$env:USERPROFILE\.config\restart-whkd.cmd";    Rel = 'config\restart-whkd.cmd' }
    @{ Live = "$env:USERPROFILE\.config\toggle-transparency.ps1"; Rel = 'config\toggle-transparency.ps1' }
    @{ Live = "$env:USERPROFILE\.config\komorebi-watchdog.cs";    Rel = 'config\komorebi-watchdog.cs' }
    @{ Live = "$env:USERPROFILE\bin\komorebi-watchdog.exe";       Rel = 'config\komorebi-watchdog.exe' }
)

# whkdrc is the only file hotkeys cannot work without. Everything else can be
# regenerated (komorebi.json is also critical for workspaces, but a missing
# applications.json just means fewer app-specific rules).
$Critical = @('config\whkdrc', 'config\komorebi.json')

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

function Stop-Wm {
    Write-Host '  stopping komorebi + whkd...' -ForegroundColor DarkGray
    try { & $KomorebiExe stop --whkd 2>$null | Out-Null } catch { }
    Get-Process -Name komorebi, whkd -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

function Start-Wm {
    Write-Host '  starting komorebi + whkd...' -ForegroundColor DarkGray
    $m = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $u = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($m) { $env:Path = $m + ';' + $u }
    Start-Process -FilePath $KomorebiExe -ArgumentList 'start', '--whkd' | Out-Null
    Start-Sleep -Seconds 6
    if (@(Get-Process -Name whkd -ErrorAction SilentlyContinue).Count -eq 0) {
        if (Test-Path 'C:\Program Files\whkd\bin\whkd.exe') {
            Start-Process -FilePath 'C:\Program Files\whkd\bin\whkd.exe' -WindowStyle Hidden | Out-Null
        }
    }
}

switch ($Mode) {

    'export' {
        if (-not (Test-Path $ZipPath)) { New-Item -ItemType Directory -Path $ZipPath -Force | Out-Null }
        $n = 0
        foreach ($m in $Map) {
            if (-not (Test-Path $m.Live)) {
                Write-Host ("  skip   {0}  (not present)" -f (Split-Path $m.Live -Leaf)) -ForegroundColor DarkGray
                continue
            }
            $dest = Join-Path $ZipPath $m.Rel
            $dir  = Split-Path $dest -Parent
            if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            Copy-Item $m.Live $dest -Force
            Write-Host ("  saved  {0}  ({1:n0} bytes)" -f $m.Rel, (Get-Item $dest).Length) -ForegroundColor Green
            $n++
        }
        Write-Host ''
        Write-Host ("exported {0} file(s) to {1}" -f $n, $ZipPath) -ForegroundColor Cyan
    }

    'import' {
        $missing = @()
        foreach ($c in $Critical) {
            if (-not (Test-Path (Join-Path $ZipPath $c))) { $missing += $c }
        }
        if ($missing) {
            Write-Host "  [FAIL] backup is missing required file(s):" -ForegroundColor Red
            $missing | ForEach-Object { Write-Host "     $_" -ForegroundColor Red }
            exit 1
        }

        # Keep a copy of the current live config so an import is always reversible.
        $rollback = Join-Path $ZipPath ("pre-import-" + $stamp)
        New-Item -ItemType Directory -Path $rollback -Force | Out-Null
        foreach ($m in $Map) {
            if (Test-Path $m.Live) { Copy-Item $m.Live (Join-Path $rollback (Split-Path $m.Live -Leaf)) -Force }
        }
        Write-Host ("  rollback copy written to: {0}" -f $rollback) -ForegroundColor DarkGray
        Write-Host ''

        Stop-Wm

        foreach ($m in $Map) {
            $src = Join-Path $ZipPath $m.Rel
            if (-not (Test-Path $src)) { continue }
            $dir = Split-Path $m.Live -Parent
            if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            Copy-Item $src $m.Live -Force
            Write-Host ("  restored  {0}" -f $m.Live) -ForegroundColor Green
        }

        Start-Wm

        Write-Host ''
        Write-Host 'done. Check it with:  4-STATUS.bat' -ForegroundColor Cyan
    }
}
