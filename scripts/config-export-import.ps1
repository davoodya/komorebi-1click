# =====================================================================
# config-export-import.ps1
#
#   Export the whole komorebi-1click config set to a DIRECTORY, and import
#   it back. Export opens a native directory selector and creates a fresh
#   timestamped folder inside the chosen directory; import opens the same
#   selector and REPLACES the live config from the chosen backup folder.
#   Both paths also work from the CLI when -BackupPath is supplied, and
#   both reach the SAME code, so a scripted export/import and a GUI one
#   are the same operation.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File config-export-import.ps1 -Action export
#   powershell -NoProfile -ExecutionPolicy Bypass -File config-export-import.ps1 -Action import
#   powershell -NoProfile -ExecutionPolicy Bypass -File config-export-import.ps1 -Action export -BackupPath D:\backups\komorebi-backup-2026-10-10
#   powershell -NoProfile -ExecutionPolicy Bypass -File config-export-import.ps1 -Action export -NoDialog
#
#   The Dashboard's Export/Import buttons are exactly the no-path form:
#   komorebi-backup.ps1 is the entry point there, and both scripts share
#   the config set and the directory selector through common.ps1.
#
#   Import is NEVER destructive: the current live config is copied to a
#   timestamped pre-import backup first, the WM is stopped, files are
#   restored, then the WM is started again.
#
#   Backup layout (a plain directory, no archive): "config\<name>" entries
#   plus the YASB tree under "config\yasb\" — see Get-ConfigExportSet.
# =====================================================================
#Requires -Version 5.1

[CmdletBinding()]
param(
    [ValidateSet('export', 'import')]
    [string] $Action = 'export',

    # The backup DIRECTORY (a plain folder, not a zip). When omitted and no
    # -NoDialog: a directory selector opens (the GUI form).
    [string] $BackupPath,

    # Skips the directory selector even when -BackupPath is absent
    # (tests / headless): export then writes .config\komorebi-backup-<stamp>.
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
. $commonPs1   # Get-ConfigExportSet / Get-CriticalConfigSet / Show-DirectorySelector

$ConfigHome = Join-Path $env:USERPROFILE '.config'

function Say($msg, $color = 'Gray') { Write-Host $msg -ForegroundColor $color }

# =====================================================================
# Window manager restart around the swap
# =====================================================================

function Stop-WindowManager {
    # A config swap while komorebi is running leaves the live WM holding a
    # half-applied state, so stop it first. komorebic stop is the supported
    # shutdown; it also takes whkd down with it.
    $komorebic = Join-Path $env:ProgramFiles 'komorebi\bin\komorebic.exe'
    if (Test-Path -LiteralPath $komorebic) {
        try { & $komorebic stop } catch { Say "  komorebic stop reported: $($_.Exception.Message)" 'Yellow' }
    } else {
        Say '  komorebic.exe not found - assuming the WM is not installed/running.' 'Yellow'
    }
}

function Start-WindowManager {
    $komorebic = Join-Path $env:ProgramFiles 'komorebi\bin\komorebic.exe'
    if (Test-Path -LiteralPath $komorebic) {
        try { & $komorebic start --whkd } catch { Say "  komorebic start reported: $($_.Exception.Message)" 'Yellow' }
    }
}

# =====================================================================
# EXPORT — write the whole config set into a fresh directory
# =====================================================================

function Export-ConfigDirectory {
    param([Parameter(Mandatory)][string] $BackupDir)

    if (-not (Test-Path -LiteralPath $BackupDir)) {
        New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    }

    $count = 0
    $skipped = @()
    foreach ($e in (Get-ConfigExportSet)) {
        if (-not (Test-Path -LiteralPath $e.Live)) {
            $skipped += (Split-Path $e.Rel -Leaf)
            continue
        }
        # Runtime state: empty means "no resize state", and another machine's
        # offsets would distort the layout, so it travels only when real.
        if ($e.OnlyWhenNonEmpty -and ((Get-Item -LiteralPath $e.Live).Length -eq 0)) {
            Say ("  skipped (empty runtime state): {0}" -f $e.Rel) 'DarkGray'
            continue
        }
        $dest = Join-Path $BackupDir $e.Rel
        $destDir = Split-Path $dest -Parent
        if (-not (Test-Path -LiteralPath $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
        if ($e.IsDir) {
            # A directory becomes a whole tree under <rel>\.
            Copy-Item -LiteralPath $e.Live -Destination $dest -Recurse -Force
        } else {
            Copy-Item -LiteralPath $e.Live -Destination $dest -Force
        }
        Say ("  added: {0}" -f $e.Rel) 'DarkGray'
        $count++
    }
    if ($skipped.Count -gt 0) {
        Say ("  skipped (not present): {0}" -f ($skipped -join ', ')) 'DarkGray'
    }

    Say ("  backup written: {0} ({1} item(s))" -f $BackupDir, $count) 'Green'
    return $count
}

# =====================================================================
# IMPORT — replace the live config from the chosen backup directory
# =====================================================================

function Import-ConfigDirectory {
    param([Parameter(Mandatory)][string] $BackupDir)

    if (-not (Test-Path -LiteralPath $BackupDir)) {
        throw "The backup directory does not exist: $BackupDir"
    }

    # Refuse a folder that is not a backup at all: the restore REPLACES the
    # live config, so importing a random directory would silently wipe half
    # the setup.
    $missing = @()
    foreach ($c in (Get-CriticalConfigSet)) {
        if (-not (Test-Path -LiteralPath (Join-Path $BackupDir $c))) { $missing += $c }
    }
    if ($missing.Count -gt 0) {
        throw ("The chosen folder is not a komorebi backup (missing: {0})" -f ($missing -join ', '))
    }

    # --- 1. pre-import backup of the CURRENT live config (always reversible) --
    $preBackup = Join-Path $ConfigHome ('pre-import-backup-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Path $preBackup -Force | Out-Null
    foreach ($e in (Get-ConfigExportSet)) {
        if ($e.IsDir) { continue }
        if (Test-Path -LiteralPath $e.Live) {
            Copy-Item -LiteralPath $e.Live -Destination (Join-Path $preBackup (Split-Path $e.Live -Leaf)) -Force
        }
    }
    Say "  current config backed up to: $preBackup" 'Green'

    # --- 2. stop the WM, restore every entry, start it again ----------------
    Say '  stopping the window manager ...' 'Cyan'
    Stop-WindowManager

    $restored = 0
    try {
        foreach ($e in (Get-ConfigExportSet)) {
            $src = Join-Path $BackupDir $e.Rel
            if (-not (Test-Path -LiteralPath $src)) {
                if (-not $e.OnlyWhenNonEmpty) {
                    Say ("  not in backup: {0}" -f $e.Rel) 'DarkGray'
                }
                continue
            }
            if ($e.IsDir) {
                # Directory replacement, not a merge: a widget the old config
                # had and the backup does not must not survive the import.
                if (Test-Path -LiteralPath $e.Live) {
                    Remove-Item -LiteralPath $e.Live -Recurse -Force
                }
            } else {
                $destDir = Split-Path $e.Live -Parent
                if (-not (Test-Path -LiteralPath $destDir)) {
                    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                }
            }
            Copy-Item -LiteralPath $src -Destination $e.Live -Force -Recurse:$e.IsDir
            Say ("  restored: {0}" -f $e.Rel) 'DarkGray'
            $restored++
        }
    }
    finally {
        Say '  starting the window manager ...' 'Cyan'
        Start-WindowManager
    }

    Say ("  import complete: {0} item(s) restored." -f $restored) 'Green'
    Say "  pre-import backup kept at: $preBackup" 'Green'
    return $restored
}

# =====================================================================
# Entry point (the CLI form and the directory selector reach this same code)
# =====================================================================

if (-not (Test-Path -LiteralPath $ConfigHome)) {
    New-Item -ItemType Directory -Path $ConfigHome -Force | Out-Null
}

switch ($Action) {
    'export' {
        Say 'Exporting the komorebi configuration ...' 'Cyan'
        if (-not $BackupPath -and -not $NoDialog) {
            $picked = Show-DirectorySelector -Description 'Choose the folder to export into. A new komorebi-backup-<date> folder holding your whole configuration will be created inside it.'
            if (-not $picked) {
                Say 'Export cancelled - no directory chosen.' 'Yellow'
                exit 0
            }
            $BackupPath = Join-Path $picked ('komorebi-backup-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
        }
        if (-not $BackupPath) {
            $BackupPath = Join-Path $ConfigHome ('komorebi-backup-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
        }
        Export-ConfigDirectory -BackupDir $BackupPath | Out-Null
    }

    'import' {
        Say 'Importing a komorebi configuration backup ...' 'Cyan'
        if (-not $BackupPath -and -not $NoDialog) {
            $picked = Show-DirectorySelector -Description 'Choose the komorebi-backup folder to restore. Its configuration replaces the live one, and a rollback copy of the current configuration is saved first.'
            if (-not $picked) {
                Say 'Import cancelled - no directory chosen.' 'Yellow'
                exit 0
            }
            $BackupPath = $picked
        }
        if (-not $BackupPath) {
            Say 'Import skipped - no backup directory chosen.' 'Yellow'
            exit 0
        }
        Import-ConfigDirectory -BackupDir $BackupPath | Out-Null
    }
}

# =====================================================================
# Exit codes: 0 = success (or a deliberate cancel), 1 = an operation failed.
# The pre-import backup is always kept, so even a failed import is reversible.
# =====================================================================
