#Requires -Version 5.1
<#
    komorebi + whkd  --  export / import the live configuration.

      -Mode export   A folder picker opens. The folder you choose gets a new
                     komorebi-backup-<yyyyMMdd-HHmmss>\ directory holding the
                     WHOLE current configuration.
      -Mode import   A folder picker opens. The komorebi-backup folder you
                     choose REPLACES the live configuration. The current live
                     files are saved to a rollback copy first, so an import is
                     always reversible.

      -BackupPath    The backup directory itself (a plain folder, NOT a zip).
                     Supplying it skips the picker (CLI / scripted use).
      -NoDialog      Skips the picker even when -BackupPath is absent; export
                     then writes .config\komorebi-backup-<stamp> (headless).

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

    # The backup DIRECTORY. The Dashboard passes nothing, so the picker opens.
    [string] $BackupPath,

    # Skips the picker even when -BackupPath is absent (tests / headless).
    [switch] $NoDialog
)

$ErrorActionPreference = 'Stop'
# Dot-source common.ps1 for the shared config set, the critical-file rule and
# the directory selector. Resolution: next to this script (the repo and the
# shipped layout both put it there), then the repo root recorded in the
# installer marker, then %USERPROFILE%\.config. Nothing else is loaded.
$commonPs1 = Join-Path $PSScriptRoot 'common.ps1'
if (-not (Test-Path -LiteralPath $commonPs1)) {
    $marker = Join-Path $PSScriptRoot 'safe-restart.repo.txt'
    if (Test-Path -LiteralPath $marker) {
        $repoRoot = ((Get-Content -LiteralPath $marker -Raw) -replace "`r`n|`n", '').Trim()
        $candidate = Join-Path $repoRoot 'scripts\common.ps1'
        if (Test-Path -LiteralPath $candidate) { $commonPs1 = $candidate }
    }
}
if (-not (Test-Path -LiteralPath $commonPs1)) {
    $commonPs1 = Join-Path $env:USERPROFILE '.config\common.ps1'
}
if (-not (Test-Path -LiteralPath $commonPs1)) {
    throw 'common.ps1 (the shared config-set definition and directory selector) was not found next to this script, at the repo root, or in %USERPROFILE%\.config'
}
. $commonPs1   # Get-ConfigExportSet / Get-CriticalConfigSet / Show-DirectorySelector / Resolve-KomorebicExe

function Get-KomorebicPath {
    try { return Resolve-KomorebicExe } catch { return $null }
}

function Stop-Wm {
    Write-Host '  stopping komorebi + whkd...' -ForegroundColor DarkGray
    $komorebic = Get-KomorebicPath
    if ($komorebic) {
        try { & $komorebic stop --whkd 2>$null | Out-Null } catch { }
    } else {
        Write-Host '  komorebic.exe not found - assuming the WM is not running.' -ForegroundColor Yellow
    }
    Get-Process -Name komorebi, whkd -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

function Start-Wm {
    Write-Host '  starting komorebi + whkd...' -ForegroundColor DarkGray
    $m = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $u = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($m) { $env:Path = $m + ';' + $u }
    $komorebic = Get-KomorebicPath
    if ($komorebic) {
        Start-Process -FilePath $komorebic -ArgumentList 'start', '--whkd' | Out-Null
    }
    Start-Sleep -Seconds 6
    if (@(Get-Process -Name whkd -ErrorAction SilentlyContinue).Count -eq 0) {
        $whkd = Join-Path $env:ProgramFiles 'whkd\bin\whkd.exe'
        if (Test-Path -LiteralPath $whkd) {
            Start-Process -FilePath $whkd -WindowStyle Hidden | Out-Null
        }
    }
}

switch ($Mode) {

    'export' {
        if (-not $BackupPath -and -not $NoDialog) {
            $picked = Show-DirectorySelector -Description 'Choose the folder to export into. A new komorebi-backup-<date> folder holding your whole configuration will be created inside it.'
            if (-not $picked) {
                Write-Host 'Export cancelled - no folder chosen.' -ForegroundColor Yellow
                exit 0
            }
            $BackupPath = Join-Path $picked ('komorebi-backup-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
        }
        if (-not $BackupPath) {
            $BackupPath = Join-Path $env:USERPROFILE ('.config\komorebi-backup-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
        }
        if (-not (Test-Path -LiteralPath $BackupPath)) { New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null }

        $n = 0
        $skipped = @()
        foreach ($m in Get-ConfigExportSet) {
            if (-not (Test-Path -LiteralPath $m.Live)) {
                $skipped += (Split-Path $m.Rel -Leaf)
                continue
            }
            # Runtime state: empty means "no resize state", and another
            # machine's offsets would distort the layout.
            if ($m.OnlyWhenNonEmpty -and ((Get-Item -LiteralPath $m.Live).Length -eq 0)) {
                $skipped += ((Split-Path $m.Rel -Leaf) + ' (empty)')
                continue
            }
            $dest = Join-Path $BackupPath $m.Rel
            $dir  = Split-Path $dest -Parent
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            $size = ''
            if (-not $m.IsDir) { $size = (' ({0:n0} bytes)' -f (Get-Item -LiteralPath $m.Live).Length) }
            Copy-Item -LiteralPath $m.Live -Destination $dest -Force -Recurse:$m.IsDir
            Write-Host ("  saved  {0}{1}" -f $m.Rel, $size) -ForegroundColor Green
            $n++
        }
        Write-Host ''
        Write-Host ("exported {0} item(s) to {1}" -f $n, $BackupPath) -ForegroundColor Cyan
        if ($skipped.Count -gt 0) {
            Write-Host ("  skipped (not present / empty): {0}" -f ($skipped -join ', ')) -ForegroundColor DarkGray
        }
    }

    'import' {
        if (-not $BackupPath -and -not $NoDialog) {
            $picked = Show-DirectorySelector -Description 'Choose the komorebi-backup folder to restore. Its configuration replaces the live one, and a rollback copy of the current configuration is saved first.'
            if (-not $picked) {
                Write-Host 'Import cancelled - no folder chosen.' -ForegroundColor Yellow
                exit 0
            }
            $BackupPath = $picked
        }
        if (-not $BackupPath -or -not (Test-Path -LiteralPath $BackupPath)) {
            Write-Host ("  [FAIL] no backup folder: {0}" -f $BackupPath) -ForegroundColor Red
            exit 1
        }

        # Refuse a folder that is not a backup at all: the restore REPLACES
        # the live config, so importing a random directory would silently
        # wipe half the setup.
        $missing = @()
        foreach ($c in (Get-CriticalConfigSet)) {
            if (-not (Test-Path -LiteralPath (Join-Path $BackupPath $c))) { $missing += $c }
        }
        if ($missing.Count -gt 0) {
            Write-Host '  [FAIL] the chosen folder is not a komorebi backup (missing):' -ForegroundColor Red
            $missing | ForEach-Object { Write-Host ("     {0}" -f $_) -ForegroundColor Red }
            exit 1
        }

        # Keep a copy of the current live config so an import is always reversible.
        $rollback = Join-Path $env:USERPROFILE ('.config\pre-import-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
        New-Item -ItemType Directory -Path $rollback -Force | Out-Null
        foreach ($m in Get-ConfigExportSet) {
            if ($m.IsDir) { continue }
            if (Test-Path -LiteralPath $m.Live) {
                Copy-Item -LiteralPath $m.Live -Destination (Join-Path $rollback (Split-Path $m.Live -Leaf)) -Force
            }
        }
        Write-Host ("  rollback copy written to: {0}" -f $rollback) -ForegroundColor DarkGray
        Write-Host ''

        Stop-Wm

        $restored = 0
        foreach ($m in Get-ConfigExportSet) {
            $src = Join-Path $BackupPath $m.Rel
            if (-not (Test-Path -LiteralPath $src)) {
                if (-not $m.OnlyWhenNonEmpty) {
                    Write-Host ("  not in backup: {0}" -f $m.Rel) -ForegroundColor DarkGray
                }
                continue
            }
            if ($m.IsDir) {
                # Directory replacement, not a merge: a widget the old config
                # had and the backup does not must not survive the import.
                if (Test-Path -LiteralPath $m.Live) {
                    Remove-Item -LiteralPath $m.Live -Recurse -Force
                }
            } else {
                $dir = Split-Path $m.Live -Parent
                if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            }
            Copy-Item -LiteralPath $src -Destination $m.Live -Force -Recurse:$m.IsDir
            Write-Host ("  restored  {0}" -f $m.Live) -ForegroundColor Green
            $restored++
        }

        Start-Wm

        Write-Host ''
        Write-Host ("done: {0} item(s) restored. Check it with:  4-STATUS.bat" -f $restored) -ForegroundColor Cyan
    }
}
