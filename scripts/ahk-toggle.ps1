# =====================================================================
# ahk-toggle.ps1  —  Turn all configured AutoHotkey scripts on or off
#
# WHAT THIS DOES
#   Flips every shipped AutoHotkey script to the same state at once, edits
#   the generated AppRunner.vbs so the change survives the next logon, and
#   starts or stops the affected processes immediately so no logoff is
#   required.
#
#   Only the scripts shipped in this repository's autohotkey\ directory are
#   touched. Any AutoHotkey script the user runs from somewhere else is
#   left completely alone.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File ahk-toggle.ps1 -State enabled
#   powershell -ExecutionPolicy Bypass -File ahk-toggle.ps1 -State disabled
# Exit codes:
#   0  every script reached the requested state
#   1  the state file or the AppRunner.vbs could not be written
# =====================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('enabled', 'disabled')]
    [string] $State
)

$ErrorActionPreference = 'Stop'

# This script ships in <repo>\scripts\, so the repo root is one level up.
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) -Parent
. (Join-Path $RepoRoot 'scripts\common.ps1')
. (Join-Path $RepoRoot 'scripts\Install-Common.ps1')

$want = ($State -eq 'enabled')

function Say($msg, $color = 'Gray') { Write-Host $msg -ForegroundColor $color }

# --- read the current state, flip every script -------------------------
$state = Get-AhkEnabledState -RepoRoot $RepoRoot
$changed = 0
foreach ($name in @($state.Keys)) {
    if ([bool]$state[$name] -ne $want) { $changed++ }
    $state[$name] = $want
}

if ($changed -eq 0) {
    Say ("[ahk-toggle] all scripts are already {0}." -f $State) 'Green'
    exit 0
}

Say ("[ahk-toggle] turning {0} script(s) {1} ..." -f $changed, $State) 'Cyan'

# --- persist the state and regenerate AppRunner.vbs --------------------
try {
    Set-AhkEnabledState -RepoRoot $RepoRoot -State $state
} catch {
    Say "[ahk-toggle] could not write the state or regenerate AppRunner.vbs: $($_.Exception.Message)" 'Red'
    exit 1
}
Say '[ahk-toggle] AppRunner.vbs regenerated' 'DarkGray'

# --- act on the running processes immediately --------------------------
# Match on the .ahk path under THIS repo's autohotkey\ dir only. Process
# name alone is not enough: every v1 script shows up as "AutoHotkey", and
# the user may run scripts from other directories that must stay untouched.
$ahkDir = Join-Path $RepoRoot 'autohotkey'

function Find-AhkProcesses {
    param([string]$ScriptFile)
    $pattern = '*' + ($ScriptFile -replace '\.ahk$', '') + '*.ahk'
    return @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            ($_.CommandLine -like "*\$ScriptFile") -and
            ($_.CommandLine -like "*$ahkDir*")
        })
}

foreach ($script in $script:AutoHotkeyScripts) {
    $procs = Find-AhkProcesses -ScriptFile $script.File

    if ($want) {
        # ENABLE: start it now so the change is immediate. The VBS already
        # points at the interpreter; reproduce the exact same command line
        # so the process is indistinguishable from the logon-started one.
        $interpreter = Get-AhkInterpreterPath -Version $script.Interpreter
        $scriptPath  = Join-Path $ahkDir $script.File
        if (-not (Test-Path -LiteralPath $interpreter)) {
            Say "[ahk-toggle] interpreter missing for $($script.Name): $interpreter" 'Yellow'
            continue
        }
        if ($procs.Count -gt 0) {
            Say "[ahk-toggle] $($script.Name) is already running" 'DarkGray'
            continue
        }
        try {
            Start-Process -FilePath $interpreter -ArgumentList "`"$scriptPath`"" -WindowStyle Hidden | Out-Null
            Say "[ahk-toggle] started $($script.Name)" 'Green'
        } catch {
            Say "[ahk-toggle] could not start $($script.Name): $($_.Exception.Message)" 'Yellow'
        }
    } else {
        # DISABLE: stop the running process. AutoHotkey has no reload API, so
        # killing the process is the only way to withdraw its hotkeys.
        if ($procs.Count -eq 0) {
            Say "[ahk-toggle] $($script.Name) was not running" 'DarkGray'
            continue
        }
        foreach ($p in $procs) {
            try {
                $proc = Get-Process -Id $p.ProcessId -ErrorAction SilentlyContinue
                if ($proc) { $proc.Kill(); $proc.WaitForExit(3000) | Out-Null }
            } catch { }
        }
        Say "[ahk-toggle] stopped $($script.Name) ($($procs.Count) process(es))" 'Green'
    }
}

Say ("[ahk-toggle] DONE - all scripts are {0}." -f $State) 'Green'
exit 0
