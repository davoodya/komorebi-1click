# =====================================================================
# ahk-cleanup.ps1  —  Remove the AutoHotkey leftovers from this machine
#
# WHAT THIS DOES
#   Removes everything the AutoHotkey install put in the user's space,
#   WITHOUT uninstalling the interpreters:
#     * the generated AppRunner.vbs from the Startup folder
#     * the enable/disable state file
#     * any process running a script from this repo's autohotkey\ dir
#
#   This is the "remove my leftovers" half of the AutoHotkey lifecycle; use
#   ahk-uninstall.ps1 to remove the interpreters themselves.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File ahk-cleanup.ps1
# Exit codes:
#   0  the leftovers are gone (or were already gone)
# =====================================================================

[CmdletBinding()]
param(
    # Internal: used by the test suite to point the "Startup" folder at a
    # sandbox directory so a test run never touches the real one.
    [string] $StartupDirOverride
)

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) -Parent
. (Join-Path $RepoRoot 'scripts\common.ps1')

function Say($msg, $color = 'Gray') { Write-Host $msg -ForegroundColor $color }

function Get-StartupVbsPath {
    if ($StartupDirOverride) { return (Join-Path $StartupDirOverride 'AppRunner.vbs') }
    return (Join-Path ([Environment]::GetFolderPath('Startup')) 'AppRunner.vbs')
}

$removed = 0

# --- the generated startup launcher -------------------------------------
$startup = Get-StartupVbsPath
if (Test-Path -LiteralPath $startup) {
    Remove-Item -LiteralPath $startup -Force -ErrorAction SilentlyContinue
    Say '[ahk-cleanup] removed the generated AppRunner.vbs from Startup' 'DarkGray'
    $removed++
}

# --- the enable/disable state file --------------------------------------
$stateFile = Join-Path $RepoRoot 'autohotkey\ahk-state.json'
if (Test-Path -LiteralPath $stateFile) {
    Remove-Item -LiteralPath $stateFile -Force -ErrorAction SilentlyContinue
    Say '[ahk-cleanup] removed autohotkey\ahk-state.json' 'DarkGray'
    $removed++
}

# --- any process running one of our shipped scripts ---------------------
# Match on the repo's autohotkey\ dir so a script the user runs from
# somewhere else is left running.
$ahkDir = Join-Path $RepoRoot 'autohotkey'
$stopped = 0
@(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue) | Where-Object {
    ($_.CommandLine -like '*.ahk*') -and ($_.CommandLine -like "*$ahkDir*")
} | ForEach-Object {
    try {
        $proc = Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue
        if ($proc) { $proc.Kill(); $proc.WaitForExit(3000) | Out-Null; $stopped++ }
    } catch { }
}
if ($stopped -gt 0) {
    Say "[ahk-cleanup] stopped $stopped running script(s) from this repo" 'DarkGray'
    $removed++
}

if ($removed -eq 0) {
    Say '[ahk-cleanup] nothing to remove - the AutoHotkey footprint is already clean.' 'Green'
} else {
    Say ''
    Say "[ahk-cleanup] DONE - removed $removed item(s)." 'Green'
    Say '[ahk-cleanup] The interpreters are still installed; run ahk-uninstall.ps1 to remove them.' 'DarkGray'
}
exit 0
