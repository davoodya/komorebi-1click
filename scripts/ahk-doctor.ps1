# =====================================================================
# ahk-doctor.ps1  —  read-only AutoHotkey diagnostics
#
# WHAT THIS DOES
#   Answers the questions you actually ask when an AutoHotkey script stops
#   working: which interpreter versions are installed, which one each shipped
#   script needs, whether that interpreter is present, and whether the script is
#   enabled and running.
#
#   It WRITES NOTHING. No state file, no AppRunner.vbs, no process is started or
#   stopped. That is deliberate: a diagnostic that changes the thing it is
#   measuring is not a diagnostic. Use ahk-toggle.ps1 / ahk-script.ps1 to change
#   state, and this to find out why you would want to.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File ahk-doctor.ps1 -Action versions
#   powershell -ExecutionPolicy Bypass -File ahk-doctor.ps1 -Action status
#   powershell -ExecutionPolicy Bypass -File ahk-doctor.ps1 -Action newfile
#
# Exit codes:
#   0  the check completed (a finding is not a failure)
#   1  the check could not be completed
# =====================================================================

[CmdletBinding()]
param(
    [ValidateSet('versions', 'status', 'newfile')]
    [string] $Action = 'status'
)

$ErrorActionPreference = 'Stop'

# Sits in <repo>\scripts\, so the repo root is one level up.
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) -Parent
. (Join-Path $RepoRoot 'scripts\common.ps1')
# The manifest is the authority for which scripts ship and which interpreter each
# needs. Dot-sourcing it (rather than re-listing the scripts here) is what keeps
# this file correct when the manifest gains a script.
. (Join-Path $RepoRoot 'scripts\Install-Common.ps1')

function Say($msg, $color = 'Gray') { Write-Host $msg -ForegroundColor $color }
function Head($msg) { Write-Host ''; Say "== $msg" 'Cyan' }

# ---------------------------------------------------------------------
# Interpreter facts, gathered once.
#
# Get-AhkInterpreterPath (from the manifest) is the single source of truth for
# where each version lives, so this reports the path the RUNNER would use rather
# than a path invented here. A doctor that checks a different path from the one
# the launcher uses would report "fine" while the script never starts.
# ---------------------------------------------------------------------
$interpreterPaths = @{}
foreach ($version in @('v1', 'v2')) {
    $path = Get-AhkInterpreterPath -Version $version
    $interpreterPaths[$version] = [pscustomobject]@{
        Version = $version
        Path    = $path
        Present = Test-Path -LiteralPath $path
    }
}

function Get-InterpreterFileVersion([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $vi = (Get-Item -LiteralPath $Path).VersionInfo
        if ($vi.FileVersion) { return $vi.FileVersion }
        if ($vi.ProductVersion) { return $vi.ProductVersion }
    } catch { }
    return $null
}

# The version that a bare `AutoHotkey` (or a double-clicked .ahk file) resolves
# to. This is genuinely useful to know: with both v1 and v2 installed, which one
# wins depends on the file association and PATH, and a v2-only script launched by
# a v1 interpreter fails in a way that looks like the script is broken.
function Get-DefaultAssociationVersion {
    try {
        $assoc = (Get-ItemProperty -Path 'Registry::HKEY_CLASSES_ROOT\.ahk' -ErrorAction Stop).'(default)'
        if (-not $assoc) { return 'unknown (no .ahk association)' }

        $cmd = (Get-ItemProperty -Path "Registry::HKEY_CLASSES_ROOT\$assoc\shell\open\command" -ErrorAction Stop).'(default)'
        if (-not $cmd) { return 'unknown (no open command)' }

        if ($cmd -match 'v2') { return "v2  ($cmd)" }
        if ($cmd -match 'AutoHotkey\.exe') { return "v1  ($cmd)" }
        return $cmd
    } catch {
        return 'unknown (association not readable)'
    }
}

# The hotkey a shipped script actually binds.
#
# Read from the SOURCE .ahk, not from the installer manifest: the manifest
# records Name/File/Interpreter and has no hotkey field at all, so a manifest
# lookup here yields an empty string and a doctor that reports nothing about the
# one thing the user is looking for. The .ahk file is the authority.
#
# Two binding forms have to be told apart or the answer is wrong:
#   F3::            a hotkey
#   ^#n::           a hotkey with modifiers
#   ::teh::the      a HOTSTRING -- its definition also contains "::", so a naive
#                   split reports "teh" as a key, which is not a key at all.
# Hotstrings are reported as their own case, because "runs on every word" is the
# accurate description of the autocorrect script and "no hotkey" would be
# misleading.
function Get-ScriptHotkey([string]$AhkDir, [string]$File) {
    $path = Join-Path $AhkDir $File
    if (-not (Test-Path -LiteralPath $path)) { return 'unknown (file missing)' }

    $lines = @(Get-Content -LiteralPath $path -ErrorAction SilentlyContinue)
    $hasHotstring = $false

    foreach ($line in $lines) {
        # Strip a trailing comment so "F3::  ; switch language" still parses.
        $code = ($line -split ';')[0]
        if ([string]::IsNullOrWhiteSpace($code)) { continue }

        $trimmed = $code.TrimStart()

        # A hotstring definition starts with "::" and contains a SECOND "::
        # (the replacement). Counted, not returned: it is not a hotkey.
        if ($trimmed.StartsWith('::')) { $hasHotstring = $true; continue }

        $m = [regex]::Match($trimmed, '^(?<key>[^\s:][^:]*)::')
        if (-not $m.Success) { continue }

        $key = $m.Groups['key'].Value.Trim()
        # A bare "::" would land here as an empty key from an odd definition.
        if ([string]::IsNullOrWhiteSpace($key)) { continue }

        return (Format-AhkKey $key)
    }

    if ($hasHotstring) { return 'hotstrings - runs on every word' }
    return 'not bound'
}

# Translate AutoHotkey's modifier sigils into read order.
#
# Canonical order (Win, Ctrl, Alt, Shift) rather than the order the sigils
# appear: "^#n" is Win+Ctrl+N, which is how the user's own documentation names
# it, and reading it as Ctrl+Win+N invites the question of whether they differ.
function Format-AhkKey([string]$Key) {
    $parts = @()
    if ($Key -match '#') { $parts += 'Win' }
    if ($Key -match '\^') { $parts += 'Ctrl' }
    if ($Key -match '!') { $parts += 'Alt' }
    if ($Key -match '\+') { $parts += 'Shift' }

    $base = ($Key -replace '[#^!+]', '')
    if ($base) { $parts += $base.ToUpper() }

    if ($parts.Count -eq 0) { return $Key }
    return ($parts -join '+')
}

# ---------------------------------------------------------------------
# -Action versions
# ---------------------------------------------------------------------
if ($Action -eq 'versions') {
    Head 'AutoHotkey interpreters'

    foreach ($version in @('v1', 'v2')) {
        $info = $interpreterPaths[$version]
        if ($info.Present) {
            $fv = Get-InterpreterFileVersion $info.Path
            Say ("  {0}  INSTALLED  {1}" -f $version, $info.Path) 'Green'
            if ($fv) { Say ("      file version: {0}" -f $fv) 'DarkGray' }
        } else {
            Say ("  {0}  MISSING    {1}" -f $version, $info.Path) 'Yellow'
        }
    }

    # Version notes from the shipped setups. v2 installs INTO the v1 tree, so
    # "v1 present" does not imply "v1 only" -- both are listed independently for
    # that reason.
    Say '  note: the v2 setup installs into the v1 directory tree; both can be present.' 'DarkGray'

    Head 'Which version a double-clicked .ahk resolves to'
    Say ("  " + (Get-DefaultAssociationVersion)) 'Gray'

    Head 'Shipped scripts and the interpreter each needs'
    foreach ($script in $script:AutoHotkeyScripts) {
        $info = $interpreterPaths[$script.Interpreter]
        $state = if ($info.Present) { 'interpreter present' } else { 'INTERPRETER MISSING' }
        $color = if ($info.Present) { 'Gray' } else { 'Yellow' }
        Say ("  {0,-14} needs {1}  ({2})  - {3}" -f $script.Name, $script.Interpreter, $script.File, $state) $color
    }

    Say ''
    Say '[ahk-doctor] versions check complete.' 'Green'
    exit 0
}

# ---------------------------------------------------------------------
# -Action status  /  -Action newfile
#
# Both need the same two facts per script: is it enabled in ahk-state.json, and
# is its process running. Gathered by the same code so the two actions cannot
# disagree.
# ---------------------------------------------------------------------
$state = Get-AhkEnabledState -RepoRoot $RepoRoot
$ahkDir = Join-Path $RepoRoot 'autohotkey'

# One CIM query rather than one per script: process enumeration is the expensive
# call here and the three scripts share an answer.
$running = @()
try {
    $running = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -like "*$ahkDir*" })
} catch {
    Say "[ahk-doctor] could not enumerate processes: $($_.Exception.Message)" 'Yellow'
}

function Get-RunningFor([string]$File) {
    return @($running | Where-Object { $_.CommandLine -like "*\$File*" })
}

# The shared verdict for one script. Returns $true when the script is healthy,
# so the caller can count findings without re-deriving them.
function Show-ScriptRow([object]$Script) {
    $enabled = $true
    if ($state.ContainsKey($Script.Name)) { $enabled = [bool]$state[$Script.Name] }

    $info = $interpreterPaths[$Script.Interpreter]
    $procs = Get-RunningFor $Script.File

    $enabledText = if ($enabled) { 'enabled' } else { 'disabled' }
    $runningText = if ($procs.Count -gt 0) { "running (pid $($procs[0].ProcessId))" } else { 'not running' }

    Say ("  {0,-14} {1,-9} {2,-22} {3}" -f $Script.Name, $enabledText, $runningText, (Get-ScriptHotkey $ahkDir $Script.File)) 'Gray'

    if (-not $info.Present) {
        Say ("      needs AutoHotkey {0}, which is NOT installed at {1}" -f $Script.Interpreter, $info.Path) 'Yellow'
        return $false
    }

    # A disabled script that is not running is exactly right, not a finding.
    if (-not $enabled) { return $true }

    # Enabled but absent is the genuinely broken case: the user believes it is
    # on, and it is not doing anything.
    if ($procs.Count -eq 0) {
        Say '      enabled but not running - it will start at the next logon, or run ahk-toggle.ps1 -State enabled' 'Yellow'
        return $false
    }

    return $true
}

if ($Action -eq 'status') {
    Head 'Shipped AutoHotkey scripts'

    # Get-AhkEnabledState returns a hashtable; .ContainsKey is the safe test on a
    # key that a script added since the state file was written will not have.
    $unhealthy = 0
    foreach ($script in $script:AutoHotkeyScripts) {
        if (-not (Show-ScriptRow $script)) { $unhealthy++ }
    }

    Head 'State file'
    $stateFile = Get-AhkStateFile -RepoRoot $RepoRoot
    if (Test-Path -LiteralPath $stateFile) {
        Say ("  " + $stateFile) 'DarkGray'
    } else {
        Say ("  not present yet: " + $stateFile) 'DarkGray'
        Say '  the installer writes it; until then every script is treated as enabled' 'DarkGray'
    }

    Head 'Interpreters'
    foreach ($version in @('v1', 'v2')) {
        $info = $interpreterPaths[$version]
        $color = if ($info.Present) { 'Gray' } else { 'Yellow' }
        $mark = if ($info.Present) { 'present' } else { 'MISSING' }
        Say ("  {0}  {1}" -f $version, $mark) $color
    }

    Say ''
    if ($unhealthy -gt 0) {
        # A finding, not a failure: the command did what it was asked to do.
        Say "[ahk-doctor] status complete - $unhealthy script(s) need attention." 'Yellow'
    } else {
        Say '[ahk-doctor] status complete - every shipped script is consistent.' 'Green'
    }
    exit 0
}

# ---------------------------------------------------------------------
# -Action newfile
#
# The WIN+CTRL+N script is the one script that runs on v2, so it is the one that
# breaks on its own whenever the v2 interpreter is missing -- and its symptom
# (nothing happens on the hotkey) says nothing about the cause.
# ---------------------------------------------------------------------
if ($Action -eq 'newfile') {
    Head 'New File Script (WIN+CTRL+N)'

    $target = @($script:AutoHotkeyScripts | Where-Object { $_.Name -ieq 'NewFile' })
    if ($target.Count -ne 1) {
        Say '[ahk-doctor] the manifest has no NewFile script; nothing to check.' 'Red'
        exit 1
    }
    $script = $target[0]

    $enabled = $true
    if ($state.ContainsKey($script.Name)) { $enabled = [bool]$state[$script.Name] }

    $info = $interpreterPaths[$script.Interpreter]
    $procs = Get-RunningFor $script.File
    $scriptPath = Join-Path $ahkDir $script.File

    $problems = @()

    Say ("  script:       " + $script.File) 'Gray'
    Say ("  hotkey:       " + (Get-ScriptHotkey $ahkDir $script.File)) 'Gray'
    Say ("  interpreter:  AutoHotkey $($script.Interpreter)") 'Gray'
    Say ("  path:         " + $info.Path) 'Gray'
    Say ("  file version: " + (Get-InterpreterFileVersion $info.Path)) 'DarkGray'

    if (-not $info.Present) {
        $problems += "the AutoHotkey $($script.Interpreter) interpreter is not installed at $($info.Path)"
        Say '  interpreter:  MISSING' 'Yellow'
    } else {
        Say '  interpreter:  present' 'Green'
    }

    if (-not (Test-Path -LiteralPath $scriptPath)) {
        $problems += "the script file is missing: $scriptPath"
        Say '  script file:  MISSING' 'Yellow'
    } else {
        Say '  script file:  present' 'Green'
    }

    if (-not $enabled) { $problems += 'the script is disabled in ahk-state.json' }
    Say ("  enabled:      " + $(if ($enabled) { 'yes' } else { 'no' })) $(if ($enabled) { 'Green' } else { 'Yellow' })

    # Only report "not running" as a problem when the script is enabled. A
    # deliberately disabled script is supposed to be absent.
    if ($enabled -and $procs.Count -eq 0) {
        $problems += 'it is enabled but no process is running'
        Say '  process:      not running' 'Yellow'
    } elseif ($procs.Count -gt 0) {
        Say ("  process:      running (pid $($procs[0].ProcessId))") 'Green'
    } else {
        Say '  process:      not running (disabled, so this is expected)' 'DarkGray'
    }

    Say ''
    if ($problems.Count -eq 0) {
        Say '[ahk-doctor] WIN+CTRL+N looks healthy.' 'Green'
        exit 0
    }

    Say "[ahk-doctor] WIN+CTRL+N will not work. $($problems.Count) problem(s):" 'Yellow'
    foreach ($p in $problems) { Say "  - $p" 'Yellow' }

    if (-not $info.Present) {
        Say ''
        Say '  Fix: install AutoHotkey v2, then run ahk-script.ps1 -Name NewFile -State enabled.' 'Gray'
    }
    exit 0
}

Say "[ahk-doctor] unknown action '$Action'." 'Red'
exit 1