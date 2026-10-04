# =====================================================================
# config-export-import.ps1
#
#   Export the whole komorebi-1click config set to ONE ZIP archive, and
#   import it back. Export goes through a native Windows Save dialog,
#   import through a native Open dialog. Both paths also work from the
#   CLI when -ZipPath is supplied, and both reach the SAME code, so a
#   scripted export/import and a GUI one are the same operation.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File config-export-import.ps1 -Action export
#   powershell -NoProfile -ExecutionPolicy Bypass -File config-export-import.ps1 -Action import
#   powershell -NoProfile -ExecutionPolicy Bypass -File config-export-import.ps1 -Action export -ZipPath D:\bk.zip
#
#   Import is NEVER destructive: the current live config is copied to a
#   timestamped pre-import backup first, the WM is stopped, files are
#   restored, then the WM is started again.
#
#   Archive format (a flat set of "config\<name>" entries plus the YASB
#   tree under config\yasb\): see Export-ConfigSet.
# =====================================================================
#Requires -Version 5.1

[CmdletBinding()]
param(
    [ValidateSet('export', 'import')]
    [string] $Action = 'export',

    # When omitted: export uses a Save dialog, import uses an Open dialog.
    # When supplied: no dialog is shown (the CLI path).
    [string] $ZipPath,

    # Skips the dialogs even when -ZipPath is absent (for tests / headless).
    [switch] $NoDialog
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$ConfigHome = Join-Path $env:USERPROFILE '.config'
$YasbHome   = Join-Path $ConfigHome 'yasb'

function Say($msg, $color = 'Gray') { Write-Host $msg -ForegroundColor $color }

# ---------------------------------------------------------------------
# The set this setup ships, as relative archive paths. Every live path is
# derived from $env:USERPROFILE, so nothing here is machine-specific.
# komorebi-resize.json is INCLUDED ONLY WHEN NON-EMPTY: it is pure runtime
# state (per-monitor resize offsets) and importing another machine's stale
# offsets would silently distort the layout on the target.
# ---------------------------------------------------------------------
function Get-ConfigEntries {
    $entries = @(
        @{ Live = Join-Path $env:USERPROFILE 'komorebi.json';                    Rel = 'komorebi.json' }
        @{ Live = Join-Path $ConfigHome 'whkdrc';                                 Rel = 'whkdrc' }
        @{ Live = Join-Path $ConfigHome 'applications.json';                     Rel = 'applications.json' }
        @{ Live = Join-Path $ConfigHome 'restart-whkd.cmd';                      Rel = 'restart-whkd.cmd' }
        @{ Live = Join-Path $ConfigHome 'toggle-transparency.ps1';               Rel = 'toggle-transparency.ps1' }
        @{ Live = Join-Path $ConfigHome 'safe-restart.ps1';                      Rel = 'safe-restart.ps1' }
    )
    # The YASB tree is a whole directory (config.yaml + widgets + styles).
    if (Test-Path -LiteralPath $YasbHome) {
        $entries += @{ Live = $YasbHome; Rel = 'yasb'; IsDir = $true }
    }
    return $entries
}

# =====================================================================
# Dialogs
# =====================================================================

function Show-SaveDialog {
    $suggested = 'komorebi-1click-config-{0}.zip' -f (Get-Date -Format 'yyyy-MM-dd')
    $dialog = New-Object -TypeName System.Windows.Forms.SaveFileDialog
    $dialog.Filter      = 'ZIP archive (*.zip)|*.zip'
    $dialog.DefaultExt  = '.zip'
    $dialog.FileName    = $suggested
    $dialog.Title       = 'Export the komorebi configuration to'
    $dialog.OverwritePrompt = $true
    if ($dialog.ShowDialog() -ne 'OK') { return $null }
    return $dialog.FileName
}

function Show-OpenDialog {
    $dialog = New-Object -TypeName System.Windows.Forms.OpenFileDialog
    $dialog.Filter   = 'ZIP archive (*.zip)|*.zip'
    $dialog.Title    = 'Import the komorebi configuration from'
    if ($dialog.ShowDialog() -ne 'OK') { return $null }
    return $dialog.FileName
}

# =====================================================================
# EXPORT
# =====================================================================

function Export-ConfigSet {
    param([Parameter(Mandatory)][string] $DestinationZip)

    $entries = Get-ConfigEntries

    # Include komorebi-resize.json ONLY when it holds real runtime state.
    $resize = Join-Path $ConfigHome 'komorebi-resize.json'
    if ((Test-Path -LiteralPath $resize) -and (Get-Item -LiteralPath $resize).Length -gt 0) {
        $entries += @{ Live = $resize; Rel = 'komorebi-resize.json' }
        Say '  komorebi-resize.json holds runtime state - included.' 'DarkGray'
    } else {
        Say '  komorebi-resize.json is empty or absent - skipped (no stale offsets exported).' 'DarkGray'
    }

    $dir = Split-Path $DestinationZip -Parent
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    if (Test-Path -LiteralPath $DestinationZip) {
        Remove-Item -LiteralPath $DestinationZip -Force
    }

    $zip = [System.IO.Compression.ZipFile]::Open($DestinationZip, 'Create')
    try {
        $count = 0
        foreach ($e in $entries) {
            if (-not (Test-Path -LiteralPath $e.Live)) {
                Say ("  skipped (not present): {0}" -f $e.Rel) 'DarkGray'
                continue
            }
            if ($e.IsDir) {
                # A directory becomes a tree of entries under <rel>\.
                $files = Get-ChildItem -LiteralPath $e.Live -Recurse -File
                foreach ($f in $files) {
                    $rel = ($f.FullName.Substring($e.Live.TrimEnd('\').Length + 1)) -replace '\\', '/'
                    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $f.FullName, ($e.Rel + '/' + $rel)) | Out-Null
                    $count++
                }
            } else {
                [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $e.Live, $e.Rel) | Out-Null
                $count++
            }
            Say ("  added: {0}" -f $e.Rel) 'DarkGray'
        }
    }
    finally {
        $zip.Dispose()
    }

    Say ("  archive written: {0} ({1} entr{2})" -f $DestinationZip, $count, $(if ($count -eq 1) { 'y' } else { 'ies' })) 'Green'
    return $count
}

# =====================================================================
# IMPORT
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

function Import-ConfigSet {
    param([Parameter(Mandatory)][string] $SourceZip)

    if (-not (Test-Path -LiteralPath $SourceZip)) {
        throw "The archive does not exist: $SourceZip"
    }

    # --- 1. pre-import backup of the CURRENT live config (always reversible) --
    $preBackup = Join-Path $ConfigHome ('pre-import-backup-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Path $preBackup -Force | Out-Null
    foreach ($e in Get-ConfigEntries) {
        if (Test-Path -LiteralPath $e.Live) {
            Copy-Item -LiteralPath $e.Live -Destination $preBackup -Force -Recurse:$e.IsDir
        }
    }
    Say "  current config backed up to: $preBackup" 'Green'

    # --- 2. read the archive entry names ------------------------------------
    $archive = [System.IO.Compression.ZipFile]::OpenRead($SourceZip)
    $entryNames = @()
    try {
        $entryNames = $archive.Entries | ForEach-Object { $_.FullName }
    }
    finally {
        $archive.Dispose()
    }
    if ($entryNames.Count -eq 0) { throw 'The archive contains no files.' }

    # --- 3. stop the WM, restore every entry, start it again ----------------
    Say '  stopping the window manager ...' 'Cyan'
    Stop-WindowManager

    $restored = 0
    try {
        $archive = [System.IO.Compression.ZipFile]::OpenRead($SourceZip)
        try {
            foreach ($entry in $archive.Entries) {
                # Directory entries end with '/'; nothing to extract.
                if ($entry.FullName -match '/$') { continue }
                $rel = $entry.FullName -replace '/', '\'
                # komorebi.json lives directly in %USERPROFILE%, not under
                # .config; every other entry does. Map the top-level names
                # back to their real home so nothing is restored to the
                # wrong directory and then silently ignored.
                $base = if ($entry.FullName -eq 'komorebi.json') { $env:USERPROFILE } else { $ConfigHome }
                $dest = Join-Path $base $rel
                $destDir = Split-Path $dest -Parent
                if (-not (Test-Path -LiteralPath $destDir)) {
                    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                }
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $dest, $true)
                $restored++
                Say ("  restored: {0}" -f $entry.FullName) 'DarkGray'
            }
        }
        finally {
            $archive.Dispose()
        }
    }
    finally {
        Say '  starting the window manager ...' 'Cyan'
        Start-WindowManager
    }

    Say ("  import complete: {0} file(s) restored." -f $restored) 'Green'
    Say "  pre-import backup kept at: $preBackup" 'Green'
    return $restored
}

# =====================================================================
# Entry point (the CLI form and the GUI form reach this same code)
# =====================================================================

if (-not (Test-Path -LiteralPath $ConfigHome)) {
    New-Item -ItemType Directory -Path $ConfigHome -Force | Out-Null
}

switch ($Action) {
    'export' {
        Say 'Exporting the komorebi configuration ...' 'Cyan'
        $target = $ZipPath
        if (-not $target -and -not $NoDialog) {
            Add-Type -AssemblyName System.Windows.Forms
            $target = Show-SaveDialog
        }
        if (-not $target) {
            Say 'Export cancelled - no destination chosen.' 'Yellow'
            exit 0
        }
        Export-ConfigSet -DestinationZip $target | Out-Null
    }

    'import' {
        Say 'Importing a komorebi configuration archive ...' 'Cyan'
        $source = $ZipPath
        if (-not $source -and -not $NoDialog) {
            Add-Type -AssemblyName System.Windows.Forms
            $source = Show-OpenDialog
        }
        if (-not $source) {
            Say 'Import cancelled - no archive chosen.' 'Yellow'
            exit 0
        }
        Import-ConfigSet -SourceZip $source | Out-Null
    }
}

# =====================================================================
# Exit codes: 0 = success (or a deliberate cancel), 1 = an operation failed.
# The pre-import backup is always kept, so even a failed import is reversible.
# =====================================================================