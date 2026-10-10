# =====================================================================
# ahk-script.ps1  —  Enable or disable ONE AutoHotkey script
#
# WHAT THIS DOES
#   Turns one of the shipped AutoHotkey scripts on or off by name, edits the
#   generated AppRunner.vbs so the change survives the next logon, and
#   starts or stops that script's process immediately so no logoff is
#   required.
#
#   Only the scripts shipped in this repository's autohotkey\ directory are
#   touched. A script the user runs from somewhere else is never matched,
#   even if it shares a file name.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File ahk-script.ps1 -Name NewFile -State enabled
#   powershell -ExecutionPolicy Bypass -File ahk-script.ps1 -Name NewFile -State disabled
#   powershell -ExecutionPolicy Bypass -File ahk-script.ps1 -List
# Exit codes:
#   0  the script reached the requested state
#   1  the name is unknown, or the state/VBS could not be written
# =====================================================================

[CmdletBinding()]
param(
    # The shipped script to act on. Names are case-insensitive and match the
    # manifest in Install-Common.ps1.
    [string] $Name,
    [ValidateSet('enabled', 'disabled')]
    [string] $State,
    # List the shipped scripts and their current state, then exit.
    [switch] $List
)

$ErrorActionPreference = 'Stop'

# This script ships in <repo>\scripts\, so the repo root is one level up.
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) -Parent
. (Join-Path $RepoRoot 'scripts\common.ps1')
. (Join-Path $RepoRoot 'scripts\Install-Common.ps1')

function Say($msg, $color = 'Gray') { Write-Host $msg -ForegroundColor $color }

# --- list mode ---------------------------------------------------------
if ($List) {
    $flags = Get-AhkEnabledState -RepoRoot $RepoRoot
    Say ''
    Say 'Shipped AutoHotkey scripts' 'Cyan'
    foreach ($script in $script:AutoHotkeyScripts) {
        $on = [bool]$flags[$script.Name]
        $tag = if ($on) { 'enabled ' } else { 'disabled' }
        $color = if ($on) { 'Green' } else { 'Yellow' }
        Say ("  {0,-14} {1}  {2}  (AutoHotkey {3})" -f $script.Name, $tag, $script.File, $script.Interpreter) $color
    }
    Say ''
    Say 'Toggle one with:  ahk-script.ps1 -Name <name> -State <enabled|disabled>' 'DarkGray'
    Say 'Toggle all with:  ahk-toggle.ps1   -State <enabled|disabled>' 'DarkGray'
    exit 0
}

if (-not $Name) { Say '[ahk-script] -Name is required (or use -List)' 'Red'; exit 1 }
if (-not $State) { Say '[ahk-script] -State is required: enabled or disabled' 'Red'; exit 1 }

# --- resolve the name against the manifest -----------------------------
$target = @($script:AutoHotkeyScripts | Where-Object { $_.Name -ieq $Name })
if ($target.Count -eq 0) {
    $known = ($script:AutoHotkeyScripts | ForEach-Object { $_.Name }) -join ', '
    Say "[ahk-script] unknown script '$Name'." 'Red'
    Say "[ahk-script] known scripts: $known" 'Yellow'
    exit 1
}
$target = $target[0]
$want = ($State -eq 'enabled')

# --- is it already in that state? --------------------------------------
# NOTE: $State here is the hashtable from Get-AhkEnabledState. The parameter
# $State on this script is the string 'enabled'/'disabled' — do not confuse
# the two. The manifest's enable flags are keyed by script Name.
$flags = Get-AhkEnabledState -RepoRoot $RepoRoot
if ([bool]$flags[$target.Name] -eq $want) {
    Say ("[ahk-script] {0} is already {1}." -f $target.Name, $State) 'Green'
    exit 0
}

$flags[$target.Name] = $want
Say ("[ahk-script] turning {0} {1} ..." -f $target.Name, $State) 'Cyan'

# --- persist the state and regenerate AppRunner.vbs --------------------
try {
    Set-AhkEnabledState -RepoRoot $RepoRoot -State $flags
} catch {
    Say "[ahk-script] could not write the state or regenerate AppRunner.vbs: $($_.Exception.Message)" 'Red'
    exit 1
}
Say '[ahk-script] AppRunner.vbs regenerated' 'DarkGray'

# --- act on the running process immediately -----------------------------
# Match on the .ahk path under THIS repo's autohotkey\ dir only, so a script
# the user runs from another directory is never touched even if the file
# name is identical. The trailing * matters: the live command line quotes the
# script path, so it ends with `.ahk"` — without the wildcard the pattern
# matches nothing and a disable would leave the process running (and the next
# enable would start a duplicate).
$ahkDir = Join-Path $RepoRoot 'autohotkey'
$procs  = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object {
        ($_.CommandLine -like "*\$($target.File)*") -and
        ($_.CommandLine -like "*$ahkDir*")
    })

if ($want) {
    $interpreter = Get-AhkInterpreterPath -Version $target.Interpreter
    $scriptPath  = Join-Path $ahkDir $target.File
    if (-not (Test-Path -LiteralPath $interpreter)) {
        Say "[ahk-script] interpreter missing for $($target.Name): $interpreter" 'Yellow'
        exit 1
    }
    if ($procs.Count -gt 0) {
        Say "[ahk-script] $($target.Name) is already running" 'DarkGray'
    } else {
        try {
            # Reproduce the exact command line AppRunner.vbs uses so the
            # manually started process is indistinguishable from a logon one.
            Start-Process -FilePath $interpreter -ArgumentList "`"$scriptPath`"" -WindowStyle Hidden | Out-Null
            Say "[ahk-script] started $($target.Name)" 'Green'
        } catch {
            Say "[ahk-script] could not start $($target.Name): $($_.Exception.Message)" 'Yellow'
        }
    }
} else {
    # AutoHotkey has no unload API, so killing the process is the only way to
    # withdraw its hotkeys. The commented line in AppRunner.vbs keeps it from
    # coming back at the next logon.
    if ($procs.Count -eq 0) {
        Say "[ahk-script] $($target.Name) was not running" 'DarkGray'
    } else {
        foreach ($p in $procs) {
            try {
                $proc = Get-Process -Id $p.ProcessId -ErrorAction SilentlyContinue
                if ($proc) { $proc.Kill(); $proc.WaitForExit(3000) | Out-Null }
            } catch { }
        }
        Say "[ahk-script] stopped $($target.Name)" 'Green'
    }
}

Say ("[ahk-script] DONE - {0} is {1}." -f $target.Name, $State) 'Green'
exit 0
